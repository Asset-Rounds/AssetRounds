import Darwin
import Foundation

/// Per-instance regression observations. Normal callers use nil; release
/// builds never invoke a boundary or cleanup callback.
struct StoreControlInitializationTestHooksV1 {
    enum Boundary: CaseIterable, Equatable { case beforeOwnershipTransfer, afterOwnershipTransfer, beforeCompletion }
    enum CleanupOwner: Equatable { case local, object }
    enum DescriptorRole: Equatable {
        case applicationSupport, operations, migration, lease, owners, mutationLock, ownerLock
    }
    enum Cleanup: Equatable {
        case closed(DescriptorRole, CleanupOwner, succeeded: Bool)
        case ownerUnlocked(CleanupOwner, succeeded: Bool)
        case ownerGuardCleanupRequested
    }
    var boundary: (Boundary) throws -> Void = { _ in }
    var cleanup: (Cleanup) -> Void = { _ in }

    static func close(_ descriptor: Int32, role: DescriptorRole, owner: CleanupOwner,
                      testing: Self?) {
        let succeeded = Darwin.close(descriptor) == 0
        #if DEBUG
        testing?.cleanup(.closed(role, owner, succeeded: succeeded))
        #else
        _ = succeeded
        #endif
    }

    static func unlockOwner(_ descriptor: Int32, owner: CleanupOwner, testing: Self?) {
        let succeeded = flock(descriptor, LOCK_UN) == 0
        #if DEBUG
        testing?.cleanup(.ownerUnlocked(owner, succeeded: succeeded))
        #else
        _ = succeeded
        #endif
    }
}

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
    fileprivate static let migrationName = "schema-migration"
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
    private var retirementManifestReadCloseUncertain = false
    private let initializationTesting: StoreControlInitializationTestHooksV1?

    init(applicationSupportURL: URL,
         initializationTesting: StoreControlInitializationTestHooksV1? = nil) throws {
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
        var ownershipTransferred = false
        defer {
            if !ownershipTransferred {
                let roles: [StoreControlInitializationTestHooksV1.DescriptorRole] =
                    [.applicationSupport, .operations, .migration]
                for (index, descriptor) in retained.enumerated().reversed() {
                    StoreControlInitializationTestHooksV1.close(descriptor, role: roles[index],
                        owner: .local, testing: initializationTesting)
                }
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

            #if DEBUG
            try initializationTesting?.boundary(.beforeOwnershipTransfer)
            #endif
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
            self.initializationTesting = initializationTesting
            // From this point the fully initialized object is the sole owner,
            // including when any subsequent validation throws.
            ownershipTransferred = true
            retained.removeAll()
            #if DEBUG
            try initializationTesting?.boundary(.afterOwnershipTransfer)
            #endif
            try protectDirectory(.stagingDirectory, at: self.operationsURL)
            try protectDirectory(.stagingDirectory, at: self.migrationURL)
            guard Darwin.fsync(migrationDescriptor) == 0,
                  Darwin.fsync(operationsDescriptor) == 0,
                  Darwin.fsync(rootDescriptor) == 0 else {
                throw StoreMigrationFailure.invalidIdentity
            }
            try verify()
            try restoreErasedCurrentManifestIfPresent()
            try reconcileDeletionTombstones()
            try requireOnlyOwnedNames(validateManifests: false)
            try reconcilePreparedEnvelopeIfPresent()
            try requireOnlyOwnedNames()
            #if DEBUG
            try initializationTesting?.boundary(.beforeCompletion)
            #endif
        } catch {
            throw error
        }
    }

    deinit {
        StoreControlInitializationTestHooksV1.close(migrationDescriptor, role: .migration,
            owner: .object, testing: initializationTesting)
        StoreControlInitializationTestHooksV1.close(operationsDescriptor, role: .operations,
            owner: .object, testing: initializationTesting)
        StoreControlInitializationTestHooksV1.close(applicationSupportDescriptor, role: .applicationSupport,
            owner: .object, testing: initializationTesting)
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

    // Erase removes Operations, including the current manifest. Move its complete
    // authenticated inode out just before deletion; the next store initialization
    // moves it back before any ordinary manifest consumer can observe the store.
    // No pointer or manifest payload is regenerated by this handoff.
    private static let eraseDataName = "FieldEvidenceData"
    private static let eraseManifestName = "erase-current-manifest.json"

    func preserveCurrentManifestForErase(expectedGenerationID: UUID) throws {
        guard let dataRoot = try openEraseDataDirectory() else {
            throw StoreMigrationFailure.invalidIdentity
        }
        defer { _ = Darwin.close(dataRoot.descriptor) }
        let pointer = try readPinnedControlFile(parent: dataRoot.descriptor, name: "current.json")
        let envelope = try CurrentPointerCodecV1.decode(pointer.data)
        guard envelope.generationID == expectedGenerationID.uuidString.lowercased(),
              try !Self.itemExists(parent: dataRoot.descriptor, name: Self.eraseManifestName) else {
            throw StoreMigrationFailure.invalidIdentity
        }
        if case .legacy = envelope { return }
        let name = try Self.manifestName(for: expectedGenerationID)
        let source = try readPinnedControlFile(parent: migrationDescriptor, name: name)
        try requireEraseManifest(source.data, pointer: envelope)
        try protectFile(.journal, name: name, expected: source.identity)
        try transferEraseManifest(
            sourceParent: migrationDescriptor, sourceName: name,
            destinationParent: dataRoot.descriptor, destinationName: Self.eraseManifestName,
            dataRoot: dataRoot, pointer: pointer, source: source, allowIdenticalDestination: false
        )
    }

    private func restoreErasedCurrentManifestIfPresent() throws {
        guard let dataRoot = try openEraseDataDirectory() else { return }
        defer { _ = Darwin.close(dataRoot.descriptor) }
        guard try Self.itemExists(parent: dataRoot.descriptor, name: Self.eraseManifestName) else { return }
        let pointer = try readPinnedControlFile(parent: dataRoot.descriptor, name: "current.json")
        let envelope = try CurrentPointerCodecV1.decode(pointer.data)
        let source = try readPinnedControlFile(parent: dataRoot.descriptor, name: Self.eraseManifestName)
        try requireEraseManifest(source.data, pointer: envelope)
        guard let generationID = UUID(uuidString: envelope.generationID) else {
            throw StoreMigrationFailure.invalidIdentity
        }
        let name = try Self.manifestName(for: generationID)
        try transferEraseManifest(
            sourceParent: dataRoot.descriptor, sourceName: Self.eraseManifestName,
            destinationParent: migrationDescriptor, destinationName: name,
            dataRoot: dataRoot, pointer: pointer, source: source, allowIdenticalDestination: true
        )
    }

    private func requireEraseManifest(_ data: Data, pointer: CurrentPointerEnvelopeV1) throws {
        let digest: String
        let schema: Int
        switch pointer {
        case .legacy:
            throw StoreMigrationFailure.invalidIdentity
        case .v2(let value, _):
            digest = value.generationManifestSHA256
            schema = value.storeSchemaVersion
        case .v3(let value, _):
            digest = value.generationManifestSHA256
            schema = value.storeSchemaVersion
        }
        let manifest = try StoreGenerationManifestV1.decodeCanonical(from: data)
        guard manifest.generationID.uuidString.lowercased() == pointer.generationID,
              manifest.storeSchemaRelease.versionIdentifier.major == schema,
              StoreMigrationCanonicalJSONV1.sha256(data) == digest else {
            throw StoreMigrationFailure.digestMismatch
        }
    }

    private func openEraseDataDirectory() throws -> (descriptor: Int32, identity: Identity)? {
        try verify()
        guard try Self.itemExists(parent: applicationSupportDescriptor, name: Self.eraseDataName) else {
            return nil
        }
        let descriptor = Darwin.openat(applicationSupportDescriptor, Self.eraseDataName,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw StoreMigrationFailure.invalidIdentity }
        do {
            let identity = try Self.directoryIdentity(descriptor)
            try verifyEraseDataDirectory(descriptor: descriptor, identity: identity)
            return (descriptor, identity)
        } catch {
            _ = Darwin.close(descriptor)
            throw error
        }
    }

    private func verifyEraseDataDirectory(descriptor: Int32, identity: Identity) throws {
        try verify()
        try Self.requireDirectory(descriptor, identity: identity)
        try verifyChildDirectory(parent: applicationSupportDescriptor,
            name: Self.eraseDataName, expected: identity)
    }

    private func verifyControlFileIdentity(parent: Int32, name: String, expected: Identity) throws {
        try Self.requireSafeName(name)
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard descriptor >= 0 else { throw StoreMigrationFailure.invalidIdentity }
        defer { _ = Darwin.close(descriptor) }
        guard try Self.regularFileIdentity(descriptor) == expected else {
            throw StoreMigrationFailure.invalidIdentity
        }
    }

    private func readPinnedControlFile(parent: Int32, name: String) throws -> (data: Data, identity: Identity) {
        try verify()
        try Self.requireSafeName(name)
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard descriptor >= 0 else { throw StoreMigrationFailure.invalidIdentity }
        defer { _ = Darwin.close(descriptor) }
        let before = try Self.regularFileSnapshot(descriptor)
        let bytes = try Self.readAll(from: descriptor)
        guard try Self.regularFileSnapshot(descriptor) == before else {
            throw StoreMigrationFailure.invalidIdentity
        }
        try verifyControlFileIdentity(parent: parent, name: name, expected: before.identity)
        try verify()
        return (bytes, before.identity)
    }

    private func transferEraseManifest(
        sourceParent: Int32, sourceName: String,
        destinationParent: Int32, destinationName: String,
        dataRoot: (descriptor: Int32, identity: Identity),
        pointer: (data: Data, identity: Identity),
        source: (data: Data, identity: Identity),
        allowIdenticalDestination: Bool
    ) throws {
        func requireBinding() throws {
            try verifyEraseDataDirectory(descriptor: dataRoot.descriptor, identity: dataRoot.identity)
            let current = try readPinnedControlFile(parent: dataRoot.descriptor, name: "current.json")
            guard current.identity == pointer.identity, current.data == pointer.data else {
                throw StoreMigrationFailure.invalidIdentity
            }
        }
        try requireBinding()
        let original = try readPinnedControlFile(parent: sourceParent, name: sourceName)
        guard original.identity == source.identity, original.data == source.data else {
            throw StoreMigrationFailure.invalidIdentity
        }
        let destinationExists = try Self.itemExists(parent: destinationParent, name: destinationName)
        let destinationIdentity: Identity
        if destinationExists {
            guard allowIdenticalDestination else { throw StoreMigrationFailure.invalidIdentity }
            let existing = try readPinnedControlFile(parent: destinationParent, name: destinationName)
            guard existing.data == source.data else { throw StoreMigrationFailure.digestMismatch }
            destinationIdentity = existing.identity
        } else {
            // Exclusive same-volume rename preserves complete bytes and inode.
            // On any later failure, retain the moved file for cold recovery.
            guard Darwin.renameatx_np(sourceParent, sourceName, destinationParent, destinationName,
                UInt32(RENAME_EXCL)) == 0 else { throw StoreMigrationFailure.invalidIdentity }
            destinationIdentity = source.identity
        }
        try requireBinding()
        let destinationURL: URL
        if destinationParent == dataRoot.descriptor {
            destinationURL = applicationSupportURL.appendingPathComponent(Self.eraseDataName)
                .appendingPathComponent(destinationName)
        } else {
            destinationURL = migrationURL.appendingPathComponent(destinationName)
        }
        try ProtectedFilePolicyV1.applyAndVerify(.journal, at: destinationURL, authorityCheck: {
            try requireBinding()
            try self.verifyControlFileIdentity(parent: destinationParent, name: destinationName,
                expected: destinationIdentity)
        })
        let descriptor = Darwin.openat(destinationParent, destinationName, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard descriptor >= 0 else { throw StoreMigrationFailure.invalidIdentity }
        defer { _ = Darwin.close(descriptor) }
        guard try Self.regularFileIdentity(descriptor) == destinationIdentity,
              Darwin.fsync(descriptor) == 0, Darwin.fsync(destinationParent) == 0 else {
            throw StoreMigrationFailure.invalidIdentity
        }
        let persisted = try readPinnedControlFile(parent: destinationParent, name: destinationName)
        guard persisted.identity == destinationIdentity, persisted.data == source.data else {
            throw StoreMigrationFailure.digestMismatch
        }
        try requireBinding()
        if destinationExists {
            // The ordinary manifest is now durable. Remove only the exact
            // matching handoff; never overwrite or repair conflicting evidence.
            let retained = try readPinnedControlFile(parent: sourceParent, name: sourceName)
            guard retained.identity == source.identity, retained.data == source.data,
                  Darwin.unlinkat(sourceParent, sourceName, 0) == 0 else {
                throw StoreMigrationFailure.invalidIdentity
            }
        }
        guard Darwin.fsync(sourceParent) == 0 else { throw StoreMigrationFailure.invalidIdentity }
        try requireBinding()
        let final = try readPinnedControlFile(parent: destinationParent, name: destinationName)
        guard final.identity == destinationIdentity, final.data == source.data,
              try !Self.itemExists(parent: sourceParent, name: sourceName) else {
            throw StoreMigrationFailure.invalidIdentity
        }
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
        // readRegularFile already protected and verified this exact identity as
        // .journal (manifest names map to .journal) and proved the snapshot
        // stable across the read, so a second protectFile here was duplicate work.
        return manifest
    }

    /// Fixed Erase retirement read. Ordinary loadManifest remains unchanged;
    /// no reconciliation, pending promotion, policy setter or constructor runs.
    @MainActor
    func readManifestForEraseRetirement(targetGenerationID: UUID, expectedDigest: String,
        binding: EraseRetirementBindingV1, exclusion: EraseRetirementExclusionV1) throws -> StoreGenerationManifestV1 {
        guard !retirementManifestReadCloseUncertain else { throw StoreMigrationFailure.invalidIdentity }
        try exclusion.requireLiveRegistry(binding: binding)
        try verify()
        guard applicationSupportURL.standardizedFileURL == binding.subject.applicationSupportURL,
              Int64(applicationSupportIdentity.device) == binding.subject.applicationSupportDevice,
              UInt64(applicationSupportIdentity.inode) == binding.subject.applicationSupportInode,
              UInt64(operationsIdentity.device) == binding.registryIdentity.device,
              UInt64(operationsIdentity.inode) == binding.registryIdentity.inode,
              targetGenerationID == binding.subject.newGenerationID,
              targetGenerationID == binding.generationEpoch.generationID,
              expectedDigest == binding.generationEpoch.generationManifestSHA256,
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(expectedDigest) else {
            throw StoreMigrationFailure.invalidIdentity
        }
        let beforeNames = try Self.names(in: migrationDescriptor).sorted()
        // A pending/tombstone/allocation residue is not repaired or adopted by
        // this observer. Its presence requires the ordinary pre-EX recovery law.
        guard beforeNames.allSatisfy({ name in
            name == Self.journalName || name == Self.preparedEnvelopeName
                || name == StoreAggregateMigrationControlV1.name || Self.isManifestName(name)
        }) else { throw StoreMigrationFailure.invalidPath }
        let directoryPolicy = try ProtectedFilePolicyV1.observeTemporalPolicy(.stagingDirectory, at: migrationURL)
        guard directoryPolicy.state == .strictComplete else { throw StoreMigrationFailure.invalidIdentity }
        let targetName = try Self.manifestName(for: targetGenerationID)
        var target: StoreGenerationManifestV1?
        for name in beforeNames {
            let fd = Darwin.openat(migrationDescriptor, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw StoreMigrationFailure.invalidIdentity }
            var descriptorOwned = true
            defer {
                if descriptorOwned, Darwin.close(fd) != 0 {
                    retirementManifestReadCloseUncertain = true
                }
            }
            let before = try Self.regularFileSnapshot(fd)
            var named = stat()
            guard Darwin.fstatat(migrationDescriptor, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
                  FileSnapshot(named) == before else { throw StoreMigrationFailure.invalidIdentity }
            let url = migrationURL.appendingPathComponent(name)
            let policy = try ProtectedFilePolicyV1.observeTemporalPolicy(Self.ownedFileKind(for: name), at: url)
            guard policy.state == .strictComplete else { throw StoreMigrationFailure.invalidIdentity }
            if Self.isManifestName(name) {
                let bytes = try Self.readAll(from: fd)
                let manifest = try StoreGenerationManifestV1.decodeCanonical(from: bytes)
                guard try Self.manifestName(for: manifest.generationID) == name else { throw StoreMigrationFailure.invalidIdentity }
                if name == targetName {
                    guard StoreMigrationCanonicalJSONV1.sha256(bytes) == expectedDigest,
                          manifest.generationID == targetGenerationID else { throw StoreMigrationFailure.digestMismatch }
                    target = manifest
                }
            }
            guard try Self.regularFileSnapshot(fd) == before,
                  Darwin.fstatat(migrationDescriptor, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
                  FileSnapshot(named) == before,
                  try ProtectedFilePolicyV1.observeTemporalPolicy(Self.ownedFileKind(for: name), at: url) == policy else {
                throw StoreMigrationFailure.invalidIdentity
            }
            try exclusion.requireLiveRegistry(binding: binding)
            try verify()
            // An ambiguous close is terminal for this retained store's Erase
            // read route. Never retry the possibly reused descriptor integer.
            descriptorOwned = false
            guard Darwin.close(fd) == 0 else {
                retirementManifestReadCloseUncertain = true
                throw StoreMigrationFailure.invalidIdentity
            }
        }
        guard !retirementManifestReadCloseUncertain, let target, try Self.names(in: migrationDescriptor).sorted() == beforeNames,
              try ProtectedFilePolicyV1.observeTemporalPolicy(.stagingDirectory, at: migrationURL) == directoryPolicy else {
            throw StoreMigrationFailure.invalidIdentity
        }
        try verify()
        try exclusion.requireLiveRegistry(binding: binding)
        return target
    }

    /// No descriptor is opened here. The real retirement proof must retain the
    /// returned object and enter its preparing phase before initialization.
    @MainActor
    func makeEraseManifestRetirementAttempt(binding: EraseRetirementBindingV1,
        exclusion: EraseRetirementExclusionV1, retirement: ErasedRegistryRetirementProofV1) throws
        -> EraseManifestRetirementAttemptV1 {
        try retirement.requireManifestAttemptCreation(exclusion: exclusion, binding: binding)
        guard !retirementManifestReadCloseUncertain,
              applicationSupportURL.standardizedFileURL == binding.subject.applicationSupportURL,
              Int64(applicationSupportIdentity.device) == binding.subject.applicationSupportDevice,
              UInt64(applicationSupportIdentity.inode) == binding.subject.applicationSupportInode,
              UInt64(operationsIdentity.device) == binding.registryIdentity.device,
              UInt64(operationsIdentity.inode) == binding.registryIdentity.inode else {
            throw StoreMigrationFailure.invalidIdentity
        }
        return EraseManifestRetirementAttemptV1(store: self, binding: binding,
            exclusion: exclusion, retirement: retirement)
    }

    /// This retained attempt owns every newly opened FD before validation can
    /// throw. It neither reconstructs ownership from names nor repairs policy.
    @MainActor
    final class EraseManifestRetirementAttemptV1 {
        private enum Phase { case registered, observedOriginal, moving, preserved, namespaceRetiring, closing, released }
        private let store: StoreMigrationJournalStoreV1
        private let binding: EraseRetirementBindingV1
        private weak var exclusion: EraseRetirementExclusionV1?
        private weak var retirement: ErasedRegistryRetirementProofV1?
        private var phase: Phase = .registered
        private var dataDescriptor: Int32?
        private var dataIdentity: Identity?
        private final class File {
            let descriptor: Int32
            var snapshot: FileSnapshot?
            var bytes: Data?
            var closeAttempted = false
            init(_ descriptor: Int32) { self.descriptor = descriptor }
        }
        private var pointer: File?
        private var files: [String: File] = [:]
        private var originalNames: [String]?
        private var dataCloseAttempted = false
        private var closeUncertain = false
        private var targetName: String { "manifest-" + binding.subject.newGenerationID.uuidString.lowercased() + ".json" }
        fileprivate init(store: StoreMigrationJournalStoreV1, binding: EraseRetirementBindingV1,
            exclusion: EraseRetirementExclusionV1, retirement: ErasedRegistryRetirementProofV1) {
            self.store = store; self.binding = binding; self.exclusion = exclusion; self.retirement = retirement
        }
        func matches(binding expected: EraseRetirementBindingV1, exclusion expectedExclusion: EraseRetirementExclusionV1,
            retirement expectedRetirement: ErasedRegistryRetirementProofV1) -> Bool {
            binding == expected && exclusion === expectedExclusion && retirement === expectedRetirement
        }
        private func requireOwners(_ expected: ErasedRegistryRetirementProofV1) throws -> EraseRetirementExclusionV1 {
            guard retirement === expected, let exclusion, !closeUncertain else { throw StoreMigrationFailure.invalidIdentity }
            return exclusion
        }
        private func requireSupportAndData() throws {
            guard let exclusion, !closeUncertain else { throw StoreMigrationFailure.invalidIdentity }
            try exclusion.requireSupport(binding: binding)
            var named = stat()
            guard Darwin.lstat(store.applicationSupportURL.path, &named) == 0,
                  Identity(named) == store.applicationSupportIdentity else { throw StoreMigrationFailure.invalidIdentity }
            try StoreMigrationJournalStoreV1.requireDirectory(store.applicationSupportDescriptor, identity: store.applicationSupportIdentity)
            if let dataDescriptor, let dataIdentity {
                try StoreMigrationJournalStoreV1.requireDirectory(dataDescriptor, identity: dataIdentity)
                guard Darwin.fstatat(store.applicationSupportDescriptor, StoreMigrationJournalStoreV1.eraseDataName,
                    &named, AT_SYMLINK_NOFOLLOW) == 0, Identity(named) == dataIdentity else {
                    throw StoreMigrationFailure.invalidIdentity
                }
                try requirePolicy(.durableDirectory, at: store.applicationSupportURL.appendingPathComponent(StoreMigrationJournalStoreV1.eraseDataName))
            }
        }
        private func requireLiveMigration() throws {
            try requireSupportAndData()
            guard let exclusion else { throw StoreMigrationFailure.invalidIdentity }
            try exclusion.requireLiveRegistry(binding: binding)
            var named = stat()
            try StoreMigrationJournalStoreV1.requireDirectory(store.operationsDescriptor, identity: store.operationsIdentity)
            try StoreMigrationJournalStoreV1.requireDirectory(store.migrationDescriptor, identity: store.migrationIdentity)
            guard Darwin.fstatat(store.applicationSupportDescriptor, StoreMigrationJournalStoreV1.operationsName,
                    &named, AT_SYMLINK_NOFOLLOW) == 0, Identity(named) == store.operationsIdentity,
                  Darwin.fstatat(store.operationsDescriptor, StoreMigrationJournalStoreV1.migrationName,
                    &named, AT_SYMLINK_NOFOLLOW) == 0, Identity(named) == store.migrationIdentity else {
                throw StoreMigrationFailure.invalidIdentity
            }
            try requirePolicy(.stagingDirectory, at: store.migrationURL)
        }
        private func requirePolicy(_ kind: OwnedFileKindV1, at url: URL) throws {
            guard try ProtectedFilePolicyV1.observeTemporalPolicy(kind, at: url).state == .strictComplete else {
                throw StoreMigrationFailure.invalidIdentity
            }
        }
        private func openFile(parent: Int32, name: String) throws -> File {
            let fd = Darwin.openat(parent, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw StoreMigrationFailure.invalidIdentity }
            return File(fd) // Caller stores this object before the first throwing check.
        }
        private func observe(_ file: File, parent: Int32, name: String, url: URL,
            kind: OwnedFileKindV1, allowRenameMetadata: Bool = false) throws -> Data {
            guard !file.closeAttempted, !closeUncertain else { throw StoreMigrationFailure.invalidIdentity }
            let before = try StoreMigrationJournalStoreV1.regularFileSnapshot(file.descriptor)
            var named = stat()
            guard Darwin.fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
                  FileSnapshot(named) == before else { throw StoreMigrationFailure.invalidIdentity }
            if let expected = file.snapshot {
                guard before.identity == expected.identity, before.byteCount == expected.byteCount,
                      before.modifiedSeconds == expected.modifiedSeconds,
                      before.modifiedNanoseconds == expected.modifiedNanoseconds,
                      allowRenameMetadata || before == expected else { throw StoreMigrationFailure.invalidIdentity }
            }
            guard before.byteCount >= 0, before.byteCount <= off_t(StoreMigrationJournalStoreV1.maximumOwnedArtifactByteCount) else {
                throw StoreMigrationFailure.invalidContract
            }
            let policy = try ProtectedFilePolicyV1.observeTemporalPolicy(kind, at: url)
            guard policy.state == .strictComplete,
                  policy.device == UInt64(before.identity.device), policy.inode == UInt64(before.identity.inode) else {
                throw StoreMigrationFailure.invalidIdentity
            }
            var bytes = Data(count: Int(before.byteCount))
            try bytes.withUnsafeMutableBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let amount = Darwin.pread(file.descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset, off_t(offset))
                    if amount < 0, errno == EINTR { continue }
                    guard amount > 0 else { throw StoreMigrationFailure.invalidIdentity }
                    offset += amount
                }
            }
            guard try StoreMigrationJournalStoreV1.regularFileSnapshot(file.descriptor) == before,
                  Darwin.fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0, FileSnapshot(named) == before,
                  try ProtectedFilePolicyV1.observeTemporalPolicy(kind, at: url) == policy else { throw StoreMigrationFailure.invalidIdentity }
            if let expected = file.bytes { guard bytes == expected else { throw StoreMigrationFailure.digestMismatch } }
            if file.snapshot == nil { file.snapshot = before }
            if file.bytes == nil { file.bytes = bytes }
            return bytes
        }
        private func requirePointer() throws -> CurrentPointerEnvelopeV1 {
            guard let dataDescriptor, let pointer else { throw StoreMigrationFailure.invalidIdentity }
            try requireAbsent(parent: dataDescriptor, name: ".current.json.restore-next")
            let bytes = try observe(pointer, parent: dataDescriptor, name: "current.json",
                url: store.applicationSupportURL.appendingPathComponent("FieldEvidenceData/current.json"), kind: .generationPointer)
            try requireAbsent(parent: dataDescriptor, name: ".current.json.restore-next")
            let value = try CurrentPointerCodecV1.decode(bytes)
            guard value.generationID == binding.subject.newGenerationID.uuidString.lowercased() else { throw StoreMigrationFailure.invalidIdentity }
            if case .v3(let current, _) = value {
                guard try current.identity() == binding.workspaceIdentity else { throw StoreMigrationFailure.invalidIdentity }
            }
            return value
        }
        private func requireOriginalControls(excludingMovedManifest: Bool) throws {
            guard let originalNames else { throw StoreMigrationFailure.invalidIdentity }
            let expected = excludingMovedManifest ? originalNames.filter { $0 != targetName } : originalNames
            guard try StoreMigrationJournalStoreV1.names(in: store.migrationDescriptor).sorted() == expected else {
                throw StoreMigrationFailure.invalidPath
            }
            for name in expected {
                guard let file = files[name] else { throw StoreMigrationFailure.invalidIdentity }
                let bytes = try observe(file, parent: store.migrationDescriptor, name: name,
                    url: store.migrationURL.appendingPathComponent(name), kind: StoreMigrationJournalStoreV1.ownedFileKind(for: name))
                if name == StoreAggregateMigrationControlV1.name {
                    let aggregate = try StoreAggregateMigrationJournalV1.decodeCanonical(from: bytes)
                    guard !aggregate.reservationIsActive else { throw StoreMigrationFailure.invalidPhaseTransition }
                } else {
                    let manifest = try StoreGenerationManifestV1.decodeCanonical(from: bytes)
                    guard try StoreMigrationJournalStoreV1.manifestName(for: manifest.generationID) == name else {
                        throw StoreMigrationFailure.invalidIdentity
                    }
                }
            }
            guard try StoreMigrationJournalStoreV1.names(in: store.migrationDescriptor).sorted() == expected else {
                throw StoreMigrationFailure.invalidPath
            }
        }
        func observeOriginalAfterRegistration(retirement expected: ErasedRegistryRetirementProofV1) throws {
            let exclusion = try requireOwners(expected)
            guard phase == .registered || phase == .observedOriginal else { throw StoreMigrationFailure.invalidIdentity }
            try expected.requireManifestPreparation(exclusion: exclusion, attempt: self)
            if phase == .observedOriginal {
                _ = try requireCurrentManifest(binding: binding, exclusion: exclusion)
                return // exact initialized attempt; registration may have failed later
            }
            try requireLiveMigration()
            if dataDescriptor == nil {
                let fd = Darwin.openat(store.applicationSupportDescriptor, StoreMigrationJournalStoreV1.eraseDataName,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard fd >= 0 else { throw StoreMigrationFailure.invalidIdentity }
                dataDescriptor = fd // retain before fstat or policy can throw
            }
            guard let dataDescriptor else { throw StoreMigrationFailure.invalidIdentity }
            let actualDataIdentity = try StoreMigrationJournalStoreV1.directoryIdentity(dataDescriptor)
            if let dataIdentity { guard actualDataIdentity == dataIdentity else { throw StoreMigrationFailure.invalidIdentity } }
            else { dataIdentity = actualDataIdentity }
            try requireSupportAndData()
            if pointer == nil { pointer = try openFile(parent: dataDescriptor, name: "current.json") }
            let pointerValue = try requirePointer()
            let names = try StoreMigrationJournalStoreV1.names(in: store.migrationDescriptor).sorted()
            guard names.contains(targetName), names.allSatisfy({ StoreMigrationJournalStoreV1.isManifestName($0) || $0 == StoreAggregateMigrationControlV1.name }) else {
                throw StoreMigrationFailure.invalidPath
            }
            if let originalNames { guard names == originalNames else { throw StoreMigrationFailure.invalidIdentity } }
            else { originalNames = names }
            for name in names where files[name] == nil { files[name] = try openFile(parent: store.migrationDescriptor, name: name) }
            try requireOriginalControls(excludingMovedManifest: false)
            guard let bytes = files[targetName]?.bytes,
                  StoreMigrationCanonicalJSONV1.sha256(bytes) == binding.generationEpoch.generationManifestSHA256 else {
                throw StoreMigrationFailure.digestMismatch
            }
            try store.requireEraseManifest(bytes, pointer: pointerValue)
            try requireAbsent(parent: dataDescriptor, name: StoreMigrationJournalStoreV1.eraseManifestName)
            try requireLiveMigration()
            try expected.requireManifestPreparation(exclusion: exclusion, attempt: self)
            phase = .observedOriginal
        }
        func requireOriginalPointerBytes(_ expected: Data) throws {
            guard phase == .observedOriginal else { throw StoreMigrationFailure.invalidIdentity }
            _ = try requirePointer()
            guard pointer?.bytes == expected else { throw StoreMigrationFailure.digestMismatch }
        }
        private func requireAbsent(parent: Int32, name: String) throws {
            var info = stat()
            guard Darwin.fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else {
                throw StoreMigrationFailure.invalidIdentity
            }
        }
        private func observePreserved() throws -> StoreGenerationManifestV1 {
            try requireSupportAndData()
            guard let dataDescriptor, let file = files[targetName] else { throw StoreMigrationFailure.invalidIdentity }
            let pointerValue = try requirePointer()
            let bytes = try observe(file, parent: dataDescriptor, name: StoreMigrationJournalStoreV1.eraseManifestName,
                url: store.applicationSupportURL.appendingPathComponent("FieldEvidenceData/" + StoreMigrationJournalStoreV1.eraseManifestName),
                kind: .journal, allowRenameMetadata: true)
            try store.requireEraseManifest(bytes, pointer: pointerValue)
            try requireLiveMigration()
            try requireOriginalControls(excludingMovedManifest: true)
            try requireAbsent(parent: store.migrationDescriptor, name: targetName)
            try requireSupportAndData()
            return try StoreGenerationManifestV1.decodeCanonical(from: bytes)
        }
        /// Full control observation is consumed before recursive removal. The
        /// caller must synchronously enter its exact removing phase on return.
        func sealOriginalNamespaceForRemoval(retirement expected: ErasedRegistryRetirementProofV1) throws {
            let exclusion = try requireOwners(expected)
            guard phase == .preserved else { throw StoreMigrationFailure.invalidIdentity }
            try expected.requireManifestNamespaceRemovalAdmission(exclusion: exclusion, attempt: self)
            _ = try observePreserved()
            try expected.requireManifestNamespaceRemovalAdmission(exclusion: exclusion, attempt: self)
            phase = .namespaceRetiring
        }
        private func observeRetiringNamespace() throws -> StoreGenerationManifestV1 {
            guard phase == .namespaceRetiring, let retirement, let exclusion,
                  let dataDescriptor, let file = files[targetName], let originalNames else {
                throw StoreMigrationFailure.invalidIdentity
            }
            try retirement.requireManifestNamespaceRetirementOwnership(exclusion: exclusion, attempt: self)
            try requireSupportAndData()
            let pointerValue = try requirePointer()
            let bytes = try observe(file, parent: dataDescriptor, name: StoreMigrationJournalStoreV1.eraseManifestName,
                url: store.applicationSupportURL.appendingPathComponent("FieldEvidenceData/" + StoreMigrationJournalStoreV1.eraseManifestName),
                kind: .journal, allowRenameMetadata: true)
            try store.requireEraseManifest(bytes, pointer: pointerValue)
            var named = stat()
            if Darwin.fstatat(store.applicationSupportDescriptor, StoreMigrationJournalStoreV1.operationsName,
                &named, AT_SYMLINK_NOFOLLOW) == 0 {
                guard Identity(named) == store.operationsIdentity else { throw StoreMigrationFailure.invalidIdentity }
                try StoreMigrationJournalStoreV1.requireDirectory(store.operationsDescriptor, identity: store.operationsIdentity)
                if Darwin.fstatat(store.operationsDescriptor, StoreMigrationJournalStoreV1.migrationName,
                    &named, AT_SYMLINK_NOFOLLOW) == 0 {
                    guard Identity(named) == store.migrationIdentity else { throw StoreMigrationFailure.invalidIdentity }
                    try StoreMigrationJournalStoreV1.requireDirectory(store.migrationDescriptor, identity: store.migrationIdentity)
                    try requirePolicy(.stagingDirectory, at: store.migrationURL)
                    let remaining = try StoreMigrationJournalStoreV1.names(in: store.migrationDescriptor).sorted()
                    guard Set(remaining).isSubset(of: Set(originalNames.filter { $0 != targetName })) else {
                        throw StoreMigrationFailure.invalidPath
                    }
                    for name in remaining {
                        guard let captured = files[name] else { throw StoreMigrationFailure.invalidIdentity }
                        _ = try observe(captured, parent: store.migrationDescriptor, name: name,
                            url: store.migrationURL.appendingPathComponent(name), kind: StoreMigrationJournalStoreV1.ownedFileKind(for: name))
                    }
                    guard try StoreMigrationJournalStoreV1.names(in: store.migrationDescriptor).sorted() == remaining else {
                        throw StoreMigrationFailure.invalidPath
                    }
                } else { guard errno == ENOENT else { throw StoreMigrationFailure.invalidIdentity } }
            } else { guard errno == ENOENT else { throw StoreMigrationFailure.invalidIdentity } }
            try requireSupportAndData()
            try retirement.requireManifestNamespaceRetirementOwnership(exclusion: exclusion, attempt: self)
            return try StoreGenerationManifestV1.decodeCanonical(from: bytes)
        }
        func requireCurrentManifest(binding expected: EraseRetirementBindingV1,
            exclusion expectedExclusion: EraseRetirementExclusionV1) throws -> StoreGenerationManifestV1 {
            guard binding == expected, exclusion === expectedExclusion else { throw StoreMigrationFailure.invalidIdentity }
            switch phase {
            case .observedOriginal:
                try requireLiveMigration()
                let pointerValue = try requirePointer()
                try requireOriginalControls(excludingMovedManifest: false)
                guard let dataDescriptor, let bytes = files[targetName]?.bytes else { throw StoreMigrationFailure.invalidIdentity }
                try requireAbsent(parent: dataDescriptor, name: StoreMigrationJournalStoreV1.eraseManifestName)
                try store.requireEraseManifest(bytes, pointer: pointerValue)
                return try StoreGenerationManifestV1.decodeCanonical(from: bytes)
            case .preserved: return try observePreserved()
            case .namespaceRetiring: return try observeRetiringNamespace()
            case .registered, .moving, .closing, .released: throw StoreMigrationFailure.invalidIdentity
            }
        }
        func preserveAfterLeaseDrain(retirement expected: ErasedRegistryRetirementProofV1) throws {
            let exclusion = try requireOwners(expected)
            switch phase {
            case .observedOriginal:
                try expected.beginManifestTransfer(attempt: self)
                phase = .moving // no throwing/await gap after proof changes phase
            case .moving, .preserved:
                try exclusion.requireManifestTransferRetry(retirement: expected, attempt: self)
            case .registered, .namespaceRetiring, .closing, .released: throw StoreMigrationFailure.invalidIdentity
            }
            try exclusion.requireManifestTransferRetry(retirement: expected, attempt: self)
            try requireLiveMigration()
            _ = try requirePointer()
            guard let dataDescriptor, let source = files[targetName] else { throw StoreMigrationFailure.invalidIdentity }
            var original = stat()
            if Darwin.fstatat(store.migrationDescriptor, targetName, &original, AT_SYMLINK_NOFOLLOW) == 0 {
                guard phase == .moving else { throw StoreMigrationFailure.invalidIdentity }
                try requireOriginalControls(excludingMovedManifest: false)
                try requireAbsent(parent: dataDescriptor, name: StoreMigrationJournalStoreV1.eraseManifestName)
                guard Darwin.renameatx_np(store.migrationDescriptor, targetName, dataDescriptor,
                    StoreMigrationJournalStoreV1.eraseManifestName, UInt32(RENAME_EXCL)) == 0 else {
                    throw StoreMigrationFailure.invalidIdentity
                }
            } else { guard errno == ENOENT else { throw StoreMigrationFailure.invalidIdentity } }
            _ = try observePreserved()
            guard Darwin.fsync(source.descriptor) == 0, Darwin.fsync(dataDescriptor) == 0,
                  Darwin.fsync(store.migrationDescriptor) == 0 else { throw StoreMigrationFailure.invalidIdentity }
            _ = try observePreserved()
            try exclusion.requireManifestTransferRetry(retirement: expected, attempt: self)
            phase = .preserved
            try expected.recordManifestPreserved(attempt: self)
        }
        func requirePreserved(binding expectedBinding: EraseRetirementBindingV1,
            exclusion expectedExclusion: EraseRetirementExclusionV1,
            retirement expectedRetirement: ErasedRegistryRetirementProofV1) throws {
            guard phase == .preserved, matches(binding: expectedBinding, exclusion: expectedExclusion,
                retirement: expectedRetirement) else { throw StoreMigrationFailure.invalidIdentity }
            _ = try observePreserved()
        }
        func closeAfterExclusionRelease(retirement expected: ErasedRegistryRetirementProofV1) throws {
            let exclusion = try requireOwners(expected)
            guard phase == .namespaceRetiring || phase == .closing else { throw StoreMigrationFailure.invalidIdentity }
            try expected.requireManifestResourceRelease(exclusion: exclusion, attempt: self)
            phase = .closing
            for file in Array(files.values) + (pointer.map { [$0] } ?? []) where !file.closeAttempted {
                file.closeAttempted = true
                guard Darwin.close(file.descriptor) == 0 else { closeUncertain = true; throw StoreMigrationFailure.invalidIdentity }
            }
            if let dataDescriptor, !dataCloseAttempted {
                dataCloseAttempted = true
                guard Darwin.close(dataDescriptor) == 0 else { closeUncertain = true; throw StoreMigrationFailure.invalidIdentity }
            }
            phase = .released
        }
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
        // Already protected and verified by readRegularFile for this identity.
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
            guard let name = OwnedStorageDirectoryEntryNameV1.decode(entry) else {
                throw StoreMigrationFailure.invalidIdentity
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
    /// New publication observations close each transient descriptor once.
    /// An ambiguous close is retained as terminal owner evidence; its integer
    /// is never retried or reused to authorize a publication.
    private var localJobPublicationUncertainDescriptors: [Int32] = []
    #if DEBUG
    private var failNextLocalJobPublicationCloseForTesting = false
    func injectLocalJobPublicationCloseFailureOnceForTesting() {
        Self.processMutationLock.lock()
        defer { Self.processMutationLock.unlock() }
        failNextLocalJobPublicationCloseForTesting = true
    }
    #endif

    private func closeLocalJobPublicationDescriptor(_ descriptor: Int32) -> Bool {
        #if DEBUG
        if failNextLocalJobPublicationCloseForTesting {
            failNextLocalJobPublicationCloseForTesting = false
            // Retain the real opened descriptor without a synthetic close
            // success. This exercises the same terminal uncertainty branch.
            return false
        }
        #endif
        return Darwin.close(descriptor) == 0
    }
    /// Retained only for the exact actual handle's maintenance release. A
    /// failed write/rename/fsync never adopts an unrelated preexisting temp.
    private final class TemporalReleaseAttempt {
        let token: GenerationLeaseTokenV1
        let original: Int32
        let originalSnapshot: FileSnapshot
        let originalBytes: Data
        let replacementBytes: Data
        var temporary: Int32 = -1
        var temporaryIdentity: Identity?
        var preparedSnapshot: FileSnapshot?
        var renamed = false
        var temporaryRemoved = false
        private var checkedClosed = Set<Int32>()
        private var closeUncertain = false
        func requireCertainDescriptors() throws {
            guard !closeUncertain else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        }
        func closeOwnedDescriptorsChecked() throws {
            try requireCertainDescriptors()
            for descriptor in [original, temporary] where descriptor >= 0 && !checkedClosed.contains(descriptor) {
                checkedClosed.insert(descriptor)
                guard Darwin.close(descriptor) == 0 else {
                    closeUncertain = true
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
            }
        }
        init(token: GenerationLeaseTokenV1, original: Int32, snapshot: FileSnapshot,
             originalBytes: Data, replacementBytes: Data) {
            self.token = token; self.original = original; originalSnapshot = snapshot
            self.originalBytes = originalBytes; self.replacementBytes = replacementBytes
        }
        deinit {
            if !checkedClosed.contains(original) { _ = Darwin.close(original) }
            if temporary >= 0, !checkedClosed.contains(temporary) { _ = Darwin.close(temporary) }
        }
    }
    private final class FreshAdoptionReplacement {
        let token: GenerationLeaseTokenV1
        var original: Int32 = -1
        var originalCloseAttempted = false
        var closeUncertain = false
        var replacement: TemporalReleaseAttempt?
        var completed = false
        init(token: GenerationLeaseTokenV1) { self.token = token }
        func closeOwnedDescriptorsChecked() throws {
            guard !closeUncertain else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            if let replacement {
                do { try replacement.closeOwnedDescriptorsChecked() }
                catch { closeUncertain = true; throw error }
            }
            if original >= 0, !originalCloseAttempted {
                originalCloseAttempted = true
                guard Darwin.close(original) == 0 else {
                    closeUncertain = true
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
            }
        }
        deinit {
            if original >= 0, !originalCloseAttempted { _ = Darwin.close(original) }
        }
    }
    private var freshWriterPublications: [ObjectIdentifier: FreshAdoptionReplacement] = [:]
    private var freshReaderPublications: [ObjectIdentifier: FreshAdoptionReplacement] = [:]
    private var preparationReaderPublications: [ObjectIdentifier: FreshAdoptionReplacement] = [:]
    private var coldPreparationReaderPublications: [ObjectIdentifier: FreshAdoptionReplacement] = [:]
    private var preparationWriterPublications: [ObjectIdentifier: FreshAdoptionReplacement] = [:]
    private var freshAdoptionReleases: [UUID: FreshAdoptionReplacement] = [:]
    private var temporalReleaseAttempts: [UUID: TemporalReleaseAttempt] = [:]
    private var temporalReaderAllocations: [ObjectIdentifier: TemporalReleaseAttempt] = [:]
    private var temporalColdGuardRemoved = false
    private var isTemporalColdOwner = false
#if DEBUG
    private var isV949HostileFixtureOwner = false
    private var v949HostileWitnessID: ObjectIdentifier?
#endif
#if DEBUG
    private let eraseAbandonmentLock = NSLock()
    private var eraseAbandonedForColdRestart = false
    /// Selective fence for the one original ticket's checked host shutdown.
    /// The lock is recursive because fixed G transactions reenter verify().
    private let originalEraseClosingLock = NSRecursiveLock()
    private var originalEraseClosingWitness: ObjectIdentifier?
    private var originalEraseScopeThread: pthread_t?
    private var originalEraseGuardUnlinked = false
    private final class OriginalEraseReleaseCapture {
        let token: GenerationLeaseTokenV1
        let descriptor: Int32
        var transferredToAttempt = false
        init(token: GenerationLeaseTokenV1, descriptor: Int32) {
            self.token = token; self.descriptor = descriptor
        }
        // An incomplete capture is retained by the registry until host exit;
        // deinit is never accepted as a checked shutdown proof.
        deinit { if !transferredToAttempt { _ = Darwin.close(descriptor) } }
    }
    private var originalEraseReleaseCaptures: [UUID: OriginalEraseReleaseCapture] = [:]
    private var originalEraseForeignLeases: [GenerationLeaseTokenV1]?
#if DEBUG
    private var postRetiredClosingProof: ObjectIdentifier?
    private var postRetiredScopeThread: pthread_t?
    private var postRetiredGuardUnlinked = false
    private let postRetiredIO = EraseAbortCheckedSnapshotIOV1()
    private var postRetiredStableOperationsDigest: String?
#endif

    private func requireOriginalEraseAdmission() throws {
        try originalEraseClosingLock.withLock {
            let originalAllowed = originalEraseClosingWitness == nil ||
                originalEraseScopeThread.map({ pthread_equal($0, pthread_self()) != 0 }) == true
#if DEBUG
            let postRetiredAllowed = postRetiredClosingProof == nil ||
                postRetiredScopeThread.map({ pthread_equal($0, pthread_self()) != 0 }) == true
#else
            let postRetiredAllowed = true
#endif
            guard originalAllowed && postRetiredAllowed else {
                throw Self.uncertainOwnerFailure()
            }
        }
    }

#if DEBUG
    /// The original post-retirement proof, not a reconstructed early writer,
    /// installs this selective fence while its transferred EX is still held.
    @MainActor
    func beginPostRetiredEraseCheckedShutdown(
        proof: ErasedRegistryRetirementProofV1,
        originalOperationsDigest: String
    ) throws {
        Self.processMutationLock.lock()
        defer { Self.processMutationLock.unlock() }
        try verify()
        try proof.requireReadyForPreDeletionAbandonmentForTesting(registry: self)
        guard try postRetiredIO.postRetiredTree(
            parent: operationsDescriptor, name: ".") == originalOperationsDigest else {
            throw Self.uncertainOwnerFailure()
        }
        let guardPath = "\(Self.leaseDirectoryName)/\(Self.ownerDirectoryName)/\(Self.ownerLockName(ownerID))"
        let ownersPath = "\(Self.leaseDirectoryName)/\(Self.ownerDirectoryName)"
        let stable = try postRetiredIO.postRetiredTree(
            parent: operationsDescriptor, name: ".",
            excluding: [guardPath],
            ignoringDirectoryMetadata: [ownersPath])
        try originalEraseClosingLock.withLock {
            guard postRetiredClosingProof == nil,
                  originalEraseClosingWitness == nil,
                  temporalReleaseAttempts.isEmpty,
                  freshAdoptionReleases.isEmpty,
                  freshWriterPublications.isEmpty,
                  freshReaderPublications.isEmpty,
                  !postRetiredGuardUnlinked else {
                throw Self.uncertainOwnerFailure()
            }
            postRetiredStableOperationsDigest = stable
            postRetiredClosingProof = ObjectIdentifier(proof)
        }
    }

    @MainActor
    private func withPostRetiredEraseShutdownScope<Value>(
        proof: ErasedRegistryRetirementProofV1,
        _ body: () throws -> Value
    ) throws -> Value {
        Self.processMutationLock.lock()
        defer { Self.processMutationLock.unlock() }
        originalEraseClosingLock.lock()
        defer { originalEraseClosingLock.unlock() }
        guard postRetiredClosingProof == ObjectIdentifier(proof),
              postRetiredScopeThread == nil, !postRetiredGuardUnlinked else {
            throw Self.uncertainOwnerFailure()
        }
        postRetiredScopeThread = pthread_self()
        defer { postRetiredScopeThread = nil }
        return try body()
    }

    @MainActor
    func closePostRetiredEraseExclusion(
        proof: ErasedRegistryRetirementProofV1,
        activity: GenerationTemporalActivityHandleV1,
        physicalRoot: StoreTemporalPhysicalRootExclusionV1
    ) throws {
        try withPostRetiredEraseShutdownScope(proof: proof) {
            try proof.requirePreDeletionAbandonmentPendingForTesting(registry: self)
            let observed = try observeTemporalRegistryLocked()
            guard observed.leases.isEmpty,
                  temporalReleaseAttempts.isEmpty,
                  originalEraseReleaseCaptures.isEmpty,
                  freshAdoptionReleases.isEmpty,
                  freshWriterPublications.isEmpty,
                  freshReaderPublications.isEmpty,
                  coldPreparationReaderPublications.isEmpty,
                  preparationReaderPublications.isEmpty,
                  preparationWriterPublications.isEmpty,
                  try migrationReservationLocked()?.ownerID == nil else {
                throw Self.uncertainOwnerFailure()
            }
            try activity.closeCheckedForMaintenance()
            try physicalRoot.closeCheckedForPostRetiredEraseAbandonment()
        }
    }

    @MainActor
    func unlinkPostRetiredEraseOwnerGuard(
        proof: ErasedRegistryRetirementProofV1
    ) throws {
        try withPostRetiredEraseShutdownScope(proof: proof) {
            try proof.requirePreDeletionExclusionClosedForTesting(registry: self)
            guard flock(mutationLockDescriptor, LOCK_EX) == 0 else {
                throw Self.uncertainOwnerFailure()
            }
            do {
                try verify()
                let observed = try observeTemporalRegistryLocked()
                guard observed.leases.isEmpty,
                      temporalReleaseAttempts.isEmpty,
                      originalEraseReleaseCaptures.isEmpty,
                      try migrationReservationLocked()?.ownerID == nil else {
                    throw Self.uncertainOwnerFailure()
                }
                try requireNamedIdentity(parent: ownersDescriptor,
                    name: Self.ownerLockName(ownerID), expected: ownerLockIdentity)
                guard Darwin.unlinkat(ownersDescriptor,
                    Self.ownerLockName(ownerID), 0) == 0 else {
                    throw Self.uncertainOwnerFailure()
                }
                postRetiredGuardUnlinked = true
                try provePostRetiredUnlinkedGuardHeld()
                let guardPath = "\(Self.leaseDirectoryName)/\(Self.ownerDirectoryName)/\(Self.ownerLockName(ownerID))"
                let ownersPath = "\(Self.leaseDirectoryName)/\(Self.ownerDirectoryName)"
                guard let expected = postRetiredStableOperationsDigest,
                      try postRetiredIO.postRetiredTree(
                          parent: operationsDescriptor, name: ".",
                          excluding: [guardPath],
                          ignoringDirectoryMetadata: [ownersPath]) == expected else {
                    throw Self.uncertainOwnerFailure()
                }
            } catch {
                guard flock(mutationLockDescriptor, LOCK_UN) == 0 else {
                    throw Self.uncertainOwnerFailure()
                }
                throw error
            }
            guard flock(mutationLockDescriptor, LOCK_UN) == 0 else {
                throw Self.uncertainOwnerFailure()
            }
        }
        eraseAbandonmentLock.withLock { eraseAbandonedForColdRestart = true }
    }

    @MainActor
    private func provePostRetiredUnlinkedGuardHeld() throws {
        var held = stat(), named = stat()
        guard postRetiredGuardUnlinked,
              Darwin.fstat(ownerLockDescriptor, &held) == 0,
              held.st_dev == ownerLockIdentity.device,
              held.st_ino == ownerLockIdentity.inode,
              held.st_mode & S_IFMT == S_IFREG,
              held.st_nlink == 0,
              Darwin.fstatat(ownersDescriptor, Self.ownerLockName(ownerID),
                  &named, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT,
              Darwin.fsync(ownersDescriptor) == 0 else {
            throw Self.uncertainOwnerFailure()
        }
    }
#endif

    @MainActor
    func beginOriginalEraseCheckedShutdown(_ witness: EraseOriginalShutdownWitnessV1) throws {
        Self.processMutationLock.lock()
        defer { Self.processMutationLock.unlock() }
        try verify()
        try witness.requireBound(registry: self)
        try originalEraseClosingLock.withLock {
            guard originalEraseClosingWitness == nil, !originalEraseGuardUnlinked,
                  temporalReleaseAttempts.isEmpty else { throw Self.uncertainOwnerFailure() }
            originalEraseClosingWitness = ObjectIdentifier(witness)
        }
    }

    @MainActor
    private func withOriginalEraseShutdownScope<Value>(
        _ witness: EraseOriginalShutdownWitnessV1,
        _ body: () throws -> Value
    ) throws -> Value {
        Self.processMutationLock.lock()
        defer { Self.processMutationLock.unlock() }
        originalEraseClosingLock.lock()
        defer { originalEraseClosingLock.unlock() }
        guard originalEraseClosingWitness == ObjectIdentifier(witness),
              originalEraseScopeThread == nil, !originalEraseGuardUnlinked else {
            throw Self.uncertainOwnerFailure()
        }
        originalEraseScopeThread = pthread_self()
        defer { originalEraseScopeThread = nil }
        try witness.requireBound(registry: self)
        return try body()
    }

    @MainActor
    func requireCompletedAbortNoEffectUnderOriginalShutdown(
        witness: EraseOriginalShutdownWitnessV1,
        service: EraseAllService,
        operation: EraseRouterOperationV1,
        receipt: AbortedEraseAdmissionReceiptV1,
        coordinator: StoreSessionCoordinator
    ) throws {
        try withOriginalEraseShutdownScope(witness) {
            try service.requireCompletedAbortFreshLedgerForTesting(
                operation: operation, receipt: receipt,
                coordinator: coordinator, witness: witness, registry: self)
        }
    }

    @MainActor
    func requireCompletedAbortFinalNoEffectUnderOriginalShutdown(
        witness: EraseOriginalShutdownWitnessV1,
        service: EraseAllService,
        operation: EraseRouterOperationV1,
        receipt: AbortedEraseAdmissionReceiptV1
    ) throws {
        try withOriginalEraseShutdownScope(witness) {
            try service.requireCompletedAbortNoEffectForTesting(
                operation: operation, receipt: receipt)
        }
    }
#endif
    private let initializationTesting: StoreControlInitializationTestHooksV1?
    private var didCompleteInitialization = false

    init(
        applicationSupportURL: URL,
        ownerID: UUID = UUID(),
        makeLeaseID: @escaping @Sendable () -> UUID = UUID.init,
        now: @escaping @Sendable () -> Date = Date.init,
        initializationTesting: StoreControlInitializationTestHooksV1? = nil
    ) throws {
        guard applicationSupportURL.isFileURL,
              ownerID != GenerationEpochV1.zeroUUID else {
            throw GenerationLeaseRegistryFailureV1.invalidContract
        }
        let initializationActivity = try OwnedStorageProducerActivityV1.acquire(
            applicationSupportURL: applicationSupportURL)
        defer { initializationActivity.close() }
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
        var ownershipTransferred = false
        defer {
            if !ownershipTransferred {
                if ownerLockWasAcquired, let descriptor = retained.last {
                    StoreControlInitializationTestHooksV1.unlockOwner(descriptor,
                        owner: .local, testing: initializationTesting)
                }
                let roles: [StoreControlInitializationTestHooksV1.DescriptorRole] =
                    [.applicationSupport, .operations, .lease, .owners, .mutationLock, .ownerLock]
                for (index, descriptor) in retained.enumerated().reversed() {
                    StoreControlInitializationTestHooksV1.close(descriptor, role: roles[index],
                        owner: .local, testing: initializationTesting)
                }
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

        #if DEBUG
        try initializationTesting?.boundary(.beforeOwnershipTransfer)
        #endif
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
        self.initializationTesting = initializationTesting
        // Post-initialization failures unwind through deinit, so the local
        // construction scope relinquishes every descriptor before validation.
        ownershipTransferred = true
        retained.removeAll()
        #if DEBUG
        try initializationTesting?.boundary(.afterOwnershipTransfer)
        #endif

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
        #if DEBUG
        try initializationTesting?.boundary(.beforeCompletion)
        #endif
        didCompleteInitialization = true
    }

    @MainActor
    private init(temporalColdAt applicationSupportURL: URL,
                 operation: TemporalNormalizationColdOperationAuthorityV1,
                 scope: TemporalNormalizationColdAccessScopeV1,
                 construction: TemporalColdRegistryConstructionV1) throws {
        try scope.requireOperation(operation)
        let ownerID = UUID()
        let makeLeaseID: @Sendable () -> UUID = UUID.init
        let now: @Sendable () -> Date = Date.init
        let initializationTesting: StoreControlInitializationTestHooksV1? = nil
        let root = applicationSupportURL.standardizedFileURL
        let rootDescriptor = Darwin.open(
            root.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard rootDescriptor >= 0 else {
            throw Self.mappedFailure()
        }
        construction.retain(rootDescriptor, at: root)
        let rootIdentity = try Self.directoryIdentity(rootDescriptor)
        let operationsDescriptor = try Self.openExistingTemporalDirectory(
            parent: rootDescriptor,
            name: Self.operationsName
        )
        construction.retain(operationsDescriptor, at: root.appendingPathComponent(Self.operationsName, isDirectory: true))
        let operationsIdentity = try Self.directoryIdentity(
            operationsDescriptor
        )
        let leaseDescriptor = try Self.openExistingTemporalDirectory(
            parent: operationsDescriptor,
            name: Self.leaseDirectoryName
        )
        construction.retain(leaseDescriptor, at: root.appendingPathComponent(Self.operationsName, isDirectory: true).appendingPathComponent(Self.leaseDirectoryName, isDirectory: true))
        let leaseIdentity = try Self.directoryIdentity(leaseDescriptor)
        let ownersDescriptor = try Self.openExistingTemporalDirectory(
            parent: leaseDescriptor,
            name: Self.ownerDirectoryName
        )
        construction.retain(ownersDescriptor, at: root.appendingPathComponent(Self.operationsName, isDirectory: true).appendingPathComponent(Self.leaseDirectoryName, isDirectory: true).appendingPathComponent(Self.ownerDirectoryName, isDirectory: true))
        let ownersIdentity = try Self.directoryIdentity(ownersDescriptor)
        let mutationDescriptor = Darwin.openat(leaseDescriptor, Self.mutationLockName,
            O_RDWR | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard mutationDescriptor >= 0 else { throw Self.mappedFailure() }
        construction.retain(mutationDescriptor, at: root.appendingPathComponent(Self.operationsName).appendingPathComponent(Self.leaseDirectoryName).appendingPathComponent(Self.mutationLockName))
        let mutation = (descriptor: mutationDescriptor,
                        identity: try Self.regularFileIdentity(mutationDescriptor))
        let ownerName = Self.ownerLockName(ownerID)
        let ownerDescriptor = Darwin.openat(ownersDescriptor, ownerName,
            O_RDWR | O_CREAT | O_EXCL | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard ownerDescriptor >= 0 else { throw Self.mappedFailure() }
        construction.retainCreatedGuard(ownerDescriptor, parent: ownersDescriptor, name: ownerName,
            at: root.appendingPathComponent(Self.operationsName).appendingPathComponent(Self.leaseDirectoryName).appendingPathComponent(Self.ownerDirectoryName).appendingPathComponent(ownerName))
        let owner = (descriptor: ownerDescriptor,
                     identity: try Self.regularFileIdentity(ownerDescriptor))
        guard flock(owner.descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw GenerationLeaseRegistryFailureV1.duplicateLease
        }


        #if DEBUG
        try initializationTesting?.boundary(.beforeOwnershipTransfer)
        #endif
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
        self.initializationTesting = initializationTesting
        // No further throwing work before the caller retains this registry.
        construction.transferDescriptorsToRegistry()
        isTemporalColdOwner = true
    }

#if DEBUG
    @MainActor
    private init(v949HostileAt applicationSupportURL: URL,
                 witness: V949PostHandoffHostileFixtureWitnessV1,
                 construction: TemporalColdRegistryConstructionV1) throws {
        try witness.requireFixtureOwnerStarted()
        let ownerID = UUID()
        let makeLeaseID: @Sendable () -> UUID = UUID.init
        let now: @Sendable () -> Date = Date.init
        let initializationTesting: StoreControlInitializationTestHooksV1? = nil
        let root = applicationSupportURL.standardizedFileURL
        let rootDescriptor = Darwin.open(
            root.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard rootDescriptor >= 0 else {
            throw Self.mappedFailure()
        }
        construction.retain(rootDescriptor, at: root)
        let rootIdentity = try Self.directoryIdentity(rootDescriptor)
        let operationsDescriptor = try Self.openExistingTemporalDirectory(
            parent: rootDescriptor,
            name: Self.operationsName
        )
        construction.retain(operationsDescriptor, at: root.appendingPathComponent(Self.operationsName, isDirectory: true))
        let operationsIdentity = try Self.directoryIdentity(
            operationsDescriptor
        )
        let leaseDescriptor = try Self.openExistingTemporalDirectory(
            parent: operationsDescriptor,
            name: Self.leaseDirectoryName
        )
        construction.retain(leaseDescriptor, at: root.appendingPathComponent(Self.operationsName, isDirectory: true).appendingPathComponent(Self.leaseDirectoryName, isDirectory: true))
        let leaseIdentity = try Self.directoryIdentity(leaseDescriptor)
        let ownersDescriptor = try Self.openExistingTemporalDirectory(
            parent: leaseDescriptor,
            name: Self.ownerDirectoryName
        )
        construction.retain(ownersDescriptor, at: root.appendingPathComponent(Self.operationsName, isDirectory: true).appendingPathComponent(Self.leaseDirectoryName, isDirectory: true).appendingPathComponent(Self.ownerDirectoryName, isDirectory: true))
        let ownersIdentity = try Self.directoryIdentity(ownersDescriptor)
        let mutationDescriptor = Darwin.openat(leaseDescriptor, Self.mutationLockName,
            O_RDWR | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard mutationDescriptor >= 0 else { throw Self.mappedFailure() }
        construction.retain(mutationDescriptor, at: root.appendingPathComponent(Self.operationsName).appendingPathComponent(Self.leaseDirectoryName).appendingPathComponent(Self.mutationLockName))
        let mutation = (descriptor: mutationDescriptor,
                        identity: try Self.regularFileIdentity(mutationDescriptor))
        let ownerName = Self.ownerLockName(ownerID)
        let ownerDescriptor = Darwin.openat(ownersDescriptor, ownerName,
            O_RDWR | O_CREAT | O_EXCL | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard ownerDescriptor >= 0 else { throw Self.mappedFailure() }
        construction.retainCreatedGuard(ownerDescriptor, parent: ownersDescriptor, name: ownerName,
            at: root.appendingPathComponent(Self.operationsName).appendingPathComponent(Self.leaseDirectoryName).appendingPathComponent(Self.ownerDirectoryName).appendingPathComponent(ownerName))
        let owner = (descriptor: ownerDescriptor,
                     identity: try Self.regularFileIdentity(ownerDescriptor))
        guard flock(owner.descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw GenerationLeaseRegistryFailureV1.duplicateLease
        }


        #if DEBUG
        try initializationTesting?.boundary(.beforeOwnershipTransfer)
        #endif
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
        self.initializationTesting = initializationTesting
        // No further throwing work before the caller retains this registry.
        construction.transferDescriptorsToRegistry()
        isV949HostileFixtureOwner = true
        v949HostileWitnessID = ObjectIdentifier(witness)
    }

#endif

    @MainActor
    func finishTemporalColdConstruction(operation: TemporalNormalizationColdOperationAuthorityV1,
        scope: TemporalNormalizationColdAccessScopeV1) throws {
        guard isTemporalColdOwner else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try scope.requireOperation(operation)
        // Existing originals are observed only. The sole policy setter is
        // for the just-created owner guard, never an adopted preexisting file.
        try verify()
        _ = try ProtectedFilePolicyV1.observeTemporalPolicy(.generationLeaseDirectory, at: self.operationsURL)
        _ = try ProtectedFilePolicyV1.observeTemporalPolicy(.generationLeaseDirectory, at: self.leaseURL)
        _ = try ProtectedFilePolicyV1.observeTemporalPolicy(.generationLeaseDirectory, at: self.ownersURL)
        _ = try ProtectedFilePolicyV1.observeTemporalPolicy(.generationLeaseControl,
            at: self.leaseURL.appendingPathComponent(Self.mutationLockName))
        try protectFile(.generationLeaseOwnerLock, parent: ownersDescriptor,
            directoryURL: self.ownersURL, name: Self.ownerLockName(ownerID), expected: ownerLockIdentity)
        try scope.requireOperation(operation)
        // No generic init cleanup/reconciliation is enabled. The cold owner
        // later disposes this exact new guard under its retained EX.
    }

    @MainActor
    static func openExistingForTemporalCold(applicationSupportURL: URL,
        operation: TemporalNormalizationColdOperationAuthorityV1,
        scope: TemporalNormalizationColdAccessScopeV1,
        construction: TemporalColdRegistryConstructionV1) throws -> GenerationLeaseRegistryV1 {
        try scope.requireOperation(operation)
        return try GenerationLeaseRegistryV1(temporalColdAt: applicationSupportURL,
            operation: operation, scope: scope, construction: construction)
    }

#if DEBUG
    @MainActor
    static func openExistingForV949HostileFixture(
        applicationSupportURL: URL,
        witness: V949PostHandoffHostileFixtureWitnessV1,
        construction: TemporalColdRegistryConstructionV1
    ) throws -> GenerationLeaseRegistryV1 {
        try witness.requireFixtureOwnerStarted()
        guard applicationSupportURL.standardizedFileURL
                == witness.subject.applicationSupportURL else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return try GenerationLeaseRegistryV1(v949HostileAt: applicationSupportURL,
            witness: witness, construction: construction)
    }

    @MainActor
    func finishV949HostileFixtureConstruction(
        witness: V949PostHandoffHostileFixtureWitnessV1
    ) throws {
        try requireV949HostileOwner(witness)
        try verify()
        // Existing controls are observed only; protect the new owner guard.
        _ = try ProtectedFilePolicyV1.observeTemporalPolicy(
            .generationLeaseDirectory, at: operationsURL)
        _ = try ProtectedFilePolicyV1.observeTemporalPolicy(
            .generationLeaseDirectory, at: leaseURL)
        _ = try ProtectedFilePolicyV1.observeTemporalPolicy(
            .generationLeaseDirectory, at: ownersURL)
        _ = try ProtectedFilePolicyV1.observeTemporalPolicy(
            .generationLeaseControl,
            at: leaseURL.appendingPathComponent(Self.mutationLockName))
        try protectFile(.generationLeaseOwnerLock, parent: ownersDescriptor,
            directoryURL: ownersURL, name: Self.ownerLockName(ownerID),
            expected: ownerLockIdentity)
        try requireV949HostileOwner(witness)
        didCompleteInitialization = true
    }

    @MainActor
    private func requireV949HostileOwner(
        _ witness: V949PostHandoffHostileFixtureWitnessV1
    ) throws {
        try witness.requireFixtureOwnerStarted()
        guard isV949HostileFixtureOwner,
              v949HostileWitnessID == ObjectIdentifier(witness),
              applicationSupportURL == witness.subject.applicationSupportURL,
              Int64(rootIdentity.device) == witness.subject.applicationSupportDevice,
              UInt64(rootIdentity.inode) == witness.subject.applicationSupportInode,
              !temporalColdGuardRemoved else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    /// The real exclusive activity is retained by the caller immediately.
    /// It proves no writer; the explicit full lease census below proves no
    /// old/foreign reader before the fixture publishes its one reader.
    @MainActor
    func makeV949HostileActivityAcquisition(
        witness: V949PostHandoffHostileFixtureWitnessV1
    ) throws -> GenerationTemporalColdActivityAcquisitionV1 {
        try requireV949HostileOwner(witness)
        return makeColdRetirementActivityAcquisition()
    }

    @MainActor
    func acquireV949HostileExclusive(
        witness: V949PostHandoffHostileFixtureWitnessV1,
        attempt: GenerationTemporalColdActivityAcquisitionV1,
        retain: (GenerationTemporalActivityHandleV1) throws -> Void
    ) throws {
        try requireV949HostileOwner(witness)
        guard attempt.matches(registry: self) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        // The caller pins this attempt before it opens its first descriptor.
        // Its pretransfer FD and later handle both have checked disposition.
        let activity = try attempt.acquire()
        try retain(activity)
        try withTemporalNormalizationMutationLock(activity: activity) {
            try requireV949ZeroLeaseCensusLocked()
        }
    }

    private func requireV949ZeroLeaseCensusLocked() throws {
        let observation = try observeTemporalRegistryLocked()
        guard observation.leases.isEmpty,
              temporalReleaseAttempts.isEmpty,
              temporalReaderAllocations.isEmpty,
              try migrationReservationLocked() == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }

    @MainActor
    func withV949HostileMutationLock<T>(
        witness: V949PostHandoffHostileFixtureWitnessV1,
        activity: GenerationTemporalActivityHandleV1,
        _ body: () throws -> T
    ) throws -> T {
        try requireV949HostileOwner(witness)
        return try withTemporalNormalizationMutationLock(activity: activity) {
            try requireV949HostileOwner(witness)
            return try body()
        }
    }

    @MainActor
    func requireV949ZeroLeaseCensus(
        witness: V949PostHandoffHostileFixtureWitnessV1,
        activity: GenerationTemporalActivityHandleV1
    ) throws {
        try withV949HostileMutationLock(witness: witness, activity: activity) {
            try requireV949ZeroLeaseCensusLocked()
        }
    }
#endif

    private static func openExistingTemporalDirectory(parent: Int32, name: String) throws -> Int32 {
        try requireSafeName(name)
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Self.mappedFailure() }
        do { _ = try directoryIdentity(descriptor); return descriptor }
        catch { _ = Darwin.close(descriptor); throw error }
    }

    deinit {
        if didCompleteInitialization {
            #if DEBUG
            initializationTesting?.cleanup(.ownerGuardCleanupRequested)
            #endif
            try? removeOwnerGuardIfUnused()
        }
        StoreControlInitializationTestHooksV1.unlockOwner(ownerLockDescriptor,
            owner: .object, testing: initializationTesting)
        StoreControlInitializationTestHooksV1.close(ownerLockDescriptor, role: .ownerLock,
            owner: .object, testing: initializationTesting)
        StoreControlInitializationTestHooksV1.close(mutationLockDescriptor, role: .mutationLock,
            owner: .object, testing: initializationTesting)
        StoreControlInitializationTestHooksV1.close(ownersDescriptor, role: .owners,
            owner: .object, testing: initializationTesting)
        StoreControlInitializationTestHooksV1.close(leaseDescriptor, role: .lease,
            owner: .object, testing: initializationTesting)
        StoreControlInitializationTestHooksV1.close(operationsDescriptor, role: .operations,
            owner: .object, testing: initializationTesting)
        StoreControlInitializationTestHooksV1.close(rootDescriptor, role: .applicationSupport,
            owner: .object, testing: initializationTesting)
    }

    func acquire(
        epoch: GenerationEpochV1,
        role: GenerationLeaseRoleV1
    ) throws -> GenerationLeaseTokenV1 {
        try epoch.validate()
        // Acquire before G, never upgrade a producer SH handle to EX. Existing
        // callers already under G still use a nonblocking acquisition, so they
        // cannot wait for a normalizer which needs their generation lock.
        // Readers also change the exact source census. Every ordinary lease
        // registration takes SH; the fixed normalization owner uses its
        // separate reader-only registration while already holding EX.
        let temporalRegistration = try acquireTemporalWriterRegistrationActivity()
        defer { temporalRegistration.close() }
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
        let temporalRegistration = try acquireTemporalWriterRegistrationActivity()
        defer { temporalRegistration.close() }
        try withExclusiveGenerationMutationLock {
            // A retained normalization release must finish through its exact
            // held-inode attempt; ordinary close/deinit cannot adopt its temp.
            guard temporalReleaseAttempts[token.leaseID] == nil,
                  freshAdoptionReleases[token.leaseID] == nil,
                  !freshWriterPublications.values.contains(where: { $0.token == token }),
                  !freshReaderPublications.values.contains(where: { $0.token == token }),
                  !coldPreparationReaderPublications.values.contains(where: { $0.token == token }),
                  !preparationReaderPublications.values.contains(where: { $0.token == token }),
                  !preparationWriterPublications.values.contains(where: { $0.token == token }) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
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

#if DEBUG
    /// The original operation supplies the captured wrapper. Check that the
    /// exact lease remains active within one G interval before test cold exit.
    func requireCapturedOriginalReaderActiveForV949Fixture(
        _ reader: GenerationLeaseHandleV1
    ) throws {
        guard reader.token.role == .reader else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try withExclusiveGenerationMutationLock {
            try reader.requireLiveTemporalIdentity(mutationRegistry: self)
            try validateActiveLocked(reader.token, requiredRole: .reader)
        }
    }
#endif

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
        guard try migrationReservationLocked()?.ownerID == nil else { throw Self.uncertainOwnerFailure() }
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
                  try migrationReservationLocked() == expected else { throw Self.uncertainOwnerFailure() }
            guard let control = try StoreAggregateMigrationControlV1(applicationSupportURL: applicationSupportURL) else {
                throw Self.uncertainOwnerFailure()
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
                throw Self.uncertainOwnerFailure()
            }
            let name = Self.ownerLockName(previousOwner)
            let fd = Darwin.openat(ownersDescriptor, name, O_RDWR | O_NONBLOCK | O_NOFOLLOW)
            guard fd >= 0 else { throw Self.uncertainOwnerFailure() }
            defer { _ = Darwin.close(fd) }
            let identity = try Self.regularFileIdentity(fd)
            try requireNamedIdentity(parent: ownersDescriptor, name: name, expected: identity)
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw Self.uncertainOwnerFailure() }
            defer { _ = flock(fd, LOCK_UN) }
            try requireNamedIdentity(parent: ownersDescriptor, name: name, expected: identity)
            let result = try replaceReservation()
            guard let replacement = try migrationReservationLocked(), replacement.ownerID == ownerID else {
                throw Self.uncertainOwnerFailure()
            }
            try replacement.validateReplacement(of: expected)
            try requireNamedIdentity(parent: ownersDescriptor, name: name, expected: identity)
            let state = try loadStateLocked()
            if !state.leases.contains(where: { $0.ownerID == previousOwner }) {
                guard Darwin.unlinkat(ownersDescriptor, name, 0) == 0, Darwin.fsync(ownersDescriptor) == 0 else {
                    throw Self.uncertainOwnerFailure()
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
                    throw Self.uncertainOwnerFailure()
                }
                let identity: Identity
                do {
                    identity = try Self.regularFileIdentity(descriptor)
                } catch {
                    _ = Darwin.close(descriptor)
                    throw Self.uncertainOwnerFailure()
                }
                if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                    abandoned.insert(candidate)
                    retainedDescriptors.append((candidate, descriptor, identity))
                } else {
                    let failure = errno
                    _ = Darwin.close(descriptor)
                    guard failure == EWOULDBLOCK || failure == EAGAIN else {
                        throw Self.uncertainOwnerFailure()
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
                    throw Self.uncertainOwnerFailure()
                }
                _ = descriptor
            }
            guard Darwin.fsync(ownersDescriptor) == 0 else {
                throw Self.uncertainOwnerFailure()
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
        let activity = try acquireTemporalWriterRegistrationActivity()
        defer { activity.close() }
        return try withExclusiveGenerationMutationLock(
            verifyAfterOperation: true,
            operation
        )
    }

    /// The only EX-preserving G entry is private and consumes an actual live
    /// exclusive descriptor. Fixed owner operations below use it; ordinary
    /// caller closures cannot bypass their shared admission.
    private func withTemporalNormalizationMutationLock<Value>(
        activity: GenerationTemporalActivityHandleV1,
        _ operation: () throws -> Value
    ) throws -> Value {
        try activity.validateSharedNormalizationRegistry(self)
        return try withExclusiveGenerationMutationLock(verifyAfterOperation: true) {
            try activity.validateSharedNormalizationRegistry(self)
            let result = try operation()
            try activity.validateSharedNormalizationRegistry(self)
            return result
        }
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
        let activity = try acquireTemporalWriterRegistrationActivity()
        defer { activity.close() }
        return try withExclusiveGenerationMutationLock(
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
                throw Self.identityFailure(errorNumber: errno)
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
        let activity = try acquireTemporalWriterRegistrationActivity()
        defer { activity.close() }
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
            ) == 0 else {
                throw Self.identityFailure(errorNumber: errno)
            }
            guard Darwin.fsync(ownersDescriptor) == 0 else {
                throw Self.identityFailure(errorNumber: errno)
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
            throw Self.identityFailure()
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
            throw Self.identityFailure()
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
            throw Self.identityFailure()
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
            throw Self.identityFailure()
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
            throw Self.identityFailure()
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
#if DEBUG
        try requireOriginalEraseAdmission()
        guard eraseAbandonmentLock.withLock({ !eraseAbandonedForColdRestart }) else {
            throw Self.uncertainOwnerFailure()
        }
#endif
        let reopenedRoot = Darwin.open(
            applicationSupportURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard reopenedRoot >= 0 else {
            throw Self.identityFailure(errorNumber: errno)
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
            throw Self.identityFailure()
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
            throw Self.identityFailure(errorNumber: errno)
        }
        defer { _ = Darwin.close(descriptor) }
        guard try regularFileIdentity(descriptor) == expected else {
            throw Self.identityFailure()
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
            throw Self.identityFailure(errorNumber: errno)
        }
        defer { _ = Darwin.close(descriptor) }
        guard try Self.directoryIdentity(descriptor) == expected else {
            throw Self.identityFailure()
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
                let failureErrno = errno
                if descriptor >= 0 { _ = Darwin.close(descriptor) }
                throw mappedFailure(errorNumber: failureErrno)
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
        guard Darwin.fstat(descriptor, &information) == 0 else {
            throw Self.identityFailure(errorNumber: errno)
        }
        guard (information.st_mode & S_IFMT) == S_IFDIR,
              information.st_nlink >= 1 else {
            throw Self.identityFailure()
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
        guard Darwin.fstat(descriptor, &information) == 0 else {
            throw Self.identityFailure(errorNumber: errno)
        }
        guard (information.st_mode & S_IFMT) == S_IFREG,
              information.st_nlink == 1,
              information.st_size >= 0,
              information.st_size <= off_t(maximumControlFileBytes) else {
            throw Self.identityFailure()
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
            throw Self.identityFailure()
        }
        return true
    }

    private static func readAll(from descriptor: Int32) throws -> Data {
        guard Darwin.lseek(descriptor, 0, SEEK_SET) >= 0 else {
            throw Self.identityFailure(errorNumber: errno)
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

    private static func mappedFailure(
        errorNumber: Int32 = errno,
        operation: StaticString = #function,
        line: UInt = #line
    ) -> GenerationLeaseRegistryFailureV1 {
        reportFailure(operation: operation, line: line, errorNumber: errorNumber)
        if errorNumber == EACCES || errorNumber == EPERM {
            return .protectedDataUnavailable
        }
        return .invalidIdentity
    }

    private static func uncertainOwnerFailure(
        operation: StaticString = #function,
        line: UInt = #line
    ) -> GenerationLeaseRegistryFailureV1 {
        // No errno is inferred from a failed logical ownership predicate.
        reportFailure(operation: operation, line: line, errorNumber: nil)
        return .uncertainOwner
    }

    private static func identityFailure(
        errorNumber: Int32? = nil,
        operation: StaticString = #function,
        line: UInt = #line
    ) -> GenerationLeaseRegistryFailureV1 {
        // This may be a failed predicate after a successful syscall. Report
        // no errno rather than attributing an unrelated earlier value to it.
        reportFailure(operation: operation, line: line, errorNumber: errorNumber)
        return .invalidIdentity
    }

    private static func reportFailure(
        operation: StaticString,
        line: UInt,
        errorNumber: Int32?
    ) {
        #if DEBUG
        let code = errorNumber.map { String($0) } ?? "not-captured"
        print("GenerationLeaseRegistryV1.failure operation=\(operation) line=\(line) errno=\(code)")
        #endif
    }
}

// The job runner executes off the main actor. This adapter retains the actual
// registry and writer lease, then performs the same no-suspension G-locked
// writer/epoch reproof as a normal commit without crossing a MainActor fence.
extension GenerationLeaseRegistryV1 {
    func makeBoundLocalJobPublicationAdapter(
        writerHandle: GenerationLeaseHandleV1,
        expectedEpoch: GenerationEpochV1
    ) throws -> GenerationLocalJobPublicationAdapterV1 {
        try expectedEpoch.validate()
        guard writerHandle.token.role == .writer,
              writerHandle.token.epoch == expectedEpoch else {
            throw GenerationLeaseRegistryFailureV1.wrongLeaseRole
        }
        try writerHandle.requireExactRegistry(self)
        try writerHandle.requireLiveTemporalIdentity(mutationRegistry: self)
        _ = try currentBoundLocalJobEpoch(
            writerHandle: writerHandle, expectedEpoch: expectedEpoch)
        return GenerationLocalJobPublicationAdapterV1(
            currentGenerationEpoch: { [self, writerHandle] in
                try currentBoundLocalJobEpoch(
                    writerHandle: writerHandle, expectedEpoch: expectedEpoch)
            },
            withAuthorizedCommit: { [self, writerHandle] epoch, effect in
                guard epoch == expectedEpoch else {
                    throw GenerationLocalJobPublicationFailureV1.staleGeneration
                }
                try writerHandle.requireExactRegistry(self)
                try writerHandle.requireLiveTemporalIdentity(mutationRegistry: self)
                return try withExclusiveGenerationCommitLock {
                    try requireNoMigrationReservationLocked()
                    try validateActiveLocked(writerHandle.token, requiredRole: .writer)
                    try requireBoundLocalJobEpochLocked(expectedEpoch)
                    return try effect()
                }
            }
        )
    }

    private func currentBoundLocalJobEpoch(
        writerHandle: GenerationLeaseHandleV1,
        expectedEpoch: GenerationEpochV1
    ) throws -> GenerationEpochV1 {
        try writerHandle.requireExactRegistry(self)
        try writerHandle.requireLiveTemporalIdentity(mutationRegistry: self)
        return try withExclusiveGenerationMutationLock {
            try requireNoMigrationReservationLocked()
            try validateActiveLocked(writerHandle.token, requiredRole: .writer)
            try requireBoundLocalJobEpochLocked(expectedEpoch)
            return expectedEpoch
        }
    }

    private func requireBoundLocalJobEpochLocked(
        _ expected: GenerationEpochV1
    ) throws {
        guard localJobPublicationUncertainDescriptors.isEmpty else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        let dataName = "FieldEvidenceData"
        let dataURL = applicationSupportURL.appendingPathComponent(
            dataName, isDirectory: true)
        try withLocalJobPublicationDirectory(
            parent: rootDescriptor, name: dataName,
            url: dataURL, kind: .durableDirectory
        ) { dataDescriptor in
            var pending = stat()
            guard Darwin.fstatat(dataDescriptor, ".current.json.restore-next",
                &pending, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else {
                throw GenerationLeaseRegistryFailureV1.staleGeneration
            }
            let pointerData = try readLocalJobPublicationFile(
                parent: dataDescriptor, name: "current.json",
                url: dataURL.appendingPathComponent("current.json"),
                kind: .generationPointer, maximumBytes: Self.maximumControlFileBytes)
            guard case .v3(let pointer, _) = try CurrentPointerCodecV1.decode(pointerData),
                  pointer.generationID == expected.generationID.uuidString.lowercased(),
                  pointer.generationManifestSHA256 == expected.generationManifestSHA256 else {
                throw GenerationLeaseRegistryFailureV1.staleGeneration
            }
        }
        let migrationName = StoreMigrationJournalStoreV1.migrationName
        let migrationURL = applicationSupportURL
            .appendingPathComponent(Self.operationsName, isDirectory: true)
            .appendingPathComponent(migrationName, isDirectory: true)
        try withLocalJobPublicationDirectory(
            parent: operationsDescriptor, name: migrationName,
            url: migrationURL, kind: .stagingDirectory
        ) { migrationDescriptor in
            let manifestName = "manifest-"
                + expected.generationID.uuidString.lowercased() + ".json"
            let manifestData = try readLocalJobPublicationFile(
                parent: migrationDescriptor, name: manifestName,
                url: migrationURL.appendingPathComponent(manifestName),
                kind: .journal, maximumBytes: 32 * 1_048_576)
            guard StoreMigrationCanonicalJSONV1.sha256(manifestData)
                    == expected.generationManifestSHA256 else {
                throw GenerationLeaseRegistryFailureV1.staleGeneration
            }
            let manifest = try StoreGenerationManifestV1.decodeCanonical(
                from: manifestData)
            guard manifest.generationID == expected.generationID,
                  manifest.storeSchemaRelease == PersistentSchemaReleaseRegistryV1.activeRelease else {
                throw GenerationLeaseRegistryFailureV1.staleGeneration
            }
        }
    }

    private func withLocalJobPublicationDirectory<Value>(
        parent: Int32, name: String, url: URL, kind: OwnedFileKindV1,
        _ body: (Int32) throws -> Value
    ) throws -> Value {
        let descriptor = Darwin.openat(
            parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw GenerationLeaseRegistryFailureV1.invalidIdentity
        }
        var didAttemptClose = false
        do {
            let before = try Self.directoryIdentity(descriptor)
            let policy = try ProtectedFilePolicyV1.observeTemporalPolicy(kind, at: url)
            guard policy.state == .strictComplete,
                  policy.device == UInt64(before.device),
                  policy.inode == UInt64(before.inode) else {
                throw GenerationLeaseRegistryFailureV1.invalidIdentity
            }
            let result = try body(descriptor)
            let after = try Self.directoryIdentity(descriptor)
            let afterPolicy = try ProtectedFilePolicyV1.observeTemporalPolicy(kind, at: url)
            var named = stat()
            guard before == after, afterPolicy == policy,
                  Darwin.fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
                  Identity(named) == before else {
                throw GenerationLeaseRegistryFailureV1.invalidIdentity
            }
            didAttemptClose = true
            guard closeLocalJobPublicationDescriptor(descriptor) else {
                localJobPublicationUncertainDescriptors.append(descriptor)
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            return result
        } catch {
            if !didAttemptClose {
                didAttemptClose = true
                guard closeLocalJobPublicationDescriptor(descriptor) else {
                    localJobPublicationUncertainDescriptors.append(descriptor)
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
            }
            throw error
        }
    }

    private func readLocalJobPublicationFile(
        parent: Int32, name: String, url: URL,
        kind: OwnedFileKindV1, maximumBytes: Int
    ) throws -> Data {
        let descriptor = Darwin.openat(
            parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw GenerationLeaseRegistryFailureV1.invalidIdentity
        }
        var didAttemptClose = false
        do {
            var before = stat()
            guard Darwin.fstat(descriptor, &before) == 0,
                  before.st_mode & S_IFMT == S_IFREG,
                  before.st_nlink == 1,
                  before.st_size >= 0,
                  before.st_size <= off_t(maximumBytes) else {
                throw GenerationLeaseRegistryFailureV1.invalidIdentity
            }
            let protection = try ProtectedFilePolicyV1.observeTemporalPolicy(
                kind, at: url)
            guard protection.state == .strictComplete,
                  protection.device == UInt64(before.st_dev),
                  protection.inode == UInt64(before.st_ino) else {
                throw GenerationLeaseRegistryFailureV1.invalidIdentity
            }
            var bytes = Data()
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            while true {
                let count = buffer.withUnsafeMutableBytes {
                    Darwin.read(descriptor, $0.baseAddress, $0.count)
                }
                if count == 0 { break }
                if count < 0, errno == EINTR { continue }
                guard count > 0, bytes.count <= maximumBytes - count else {
                    throw GenerationLeaseRegistryFailureV1.invalidIdentity
                }
                bytes.append(contentsOf: buffer.prefix(count))
            }
            var after = stat(), named = stat()
            guard Darwin.fstat(descriptor, &after) == 0,
                  Darwin.fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
                  before.st_dev == after.st_dev, before.st_ino == after.st_ino,
                  before.st_size == after.st_size,
                  before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
                  before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
                  before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
                  before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
                  named.st_dev == before.st_dev, named.st_ino == before.st_ino,
                  named.st_mode & S_IFMT == S_IFREG, named.st_nlink == 1,
                  bytes.count == Int(after.st_size) else {
                throw GenerationLeaseRegistryFailureV1.invalidIdentity
            }
            didAttemptClose = true
            guard closeLocalJobPublicationDescriptor(descriptor) else {
                localJobPublicationUncertainDescriptors.append(descriptor)
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            return bytes
        } catch {
            if !didAttemptClose {
                didAttemptClose = true
                guard closeLocalJobPublicationDescriptor(descriptor) else {
                    localJobPublicationUncertainDescriptors.append(descriptor)
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
            }
            throw error
        }
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

    fileprivate init(registry: GenerationLeaseRegistryV1,
                     publishedReaderToken: GenerationLeaseTokenV1) throws {
        try publishedReaderToken.validate()
        guard publishedReaderToken.role == .reader else { throw GenerationLeaseRegistryFailureV1.invalidContract }
        self.registry = registry; token = publishedReaderToken
    }

    fileprivate init(registry: GenerationLeaseRegistryV1,
                     publishedWriterToken: GenerationLeaseTokenV1) throws {
        try publishedWriterToken.validate()
        guard publishedWriterToken.role == .writer else { throw GenerationLeaseRegistryFailureV1.invalidContract }
        self.registry = registry; token = publishedWriterToken
    }
    fileprivate func requireRecordedFreshAdoptionRelease(registry expected: GenerationLeaseRegistryV1) throws {
        try lock.withLock {
            guard registry === expected, isClosed else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        }
    }
    fileprivate func recordFreshAdoptionRelease(registry expected: GenerationLeaseRegistryV1) throws {
        try lock.withLock {
            guard registry === expected else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            isClosed = true // fixed durable release finished; outer G failure remains owned for retry
        }
    }

    /// The actual retained wrapper must still own its lease. This is a pure
    /// physical comparison; the caller's one G interval supplies the census.
    func requireLiveTemporalIdentity(mutationRegistry: GenerationLeaseRegistryV1) throws {
        try lock.withLock {
            guard !isClosed else { throw GenerationLeaseRegistryFailureV1.leaseNotActive }
            try registry.requireSharedTemporalRegistryIdentity(mutationRegistry)
        }
    }

    /// A publication owner must use the wrapper's actual retained registry,
    /// not a second owner opened over the same physical control directory.
    fileprivate func requireExactRegistry(_ expected: GenerationLeaseRegistryV1) throws {
        try lock.withLock {
            guard registry === expected else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            guard !isClosed else {
                throw GenerationLeaseRegistryFailureV1.leaseNotActive
            }
        }
    }

    func close() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        try registry.release(token)
        isClosed = true
    }

    /// A checked writer release must precede retirement of the original
    /// reader cohort after a no-effect Erase abort.  An invalidated writer is
    /// insufficient: its durable lease may still be held by a producer.
    func requireClosedForAbortedEraseReaderRetirement() throws {
        try lock.withLock {
            guard isClosed else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        }
    }

    /// Fixed maintenance release through an actual still-held normalization
    /// EX. Ordinary close semantics are unchanged for all other callers.
    func closeForTemporalMaintenance(activity: GenerationTemporalActivityHandleV1) throws {
        try lock.withLock {
            guard !isClosed else { return }
            try registry.releaseTemporalMaintenance(token, activity: activity)
            isClosed = true
        }
    }

#if DEBUG
    @MainActor
    func closeForOriginalEraseShutdown(witness: EraseOriginalShutdownWitnessV1,
        activity: GenerationTemporalActivityHandleV1) throws {
        try lock.withLock {
            guard !isClosed else { return }
            try registry.releaseOriginalEraseShutdownLease(token,
                witness: witness, activity: activity)
            isClosed = true
        }
    }

    func requireCheckedClosedForOriginalEraseShutdown(
        registry expected: GenerationLeaseRegistryV1) throws {
        try lock.withLock {
            guard registry === expected, isClosed else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
    }
#endif

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
    /// Exact retained object for owner-wide activity. This is not a mint or
    /// a substitute for this fence's fixed under-G validation.
    var retainedTemporalRegistry: GenerationLeaseRegistryV1 { registry }

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
        let activity = try registry.acquireTemporalWriterRegistrationActivity()
        defer { activity.close() }
        try registry.withExclusiveGenerationMutationLock {
            try validateCurrentLocked()
        }
    }

    struct ReadFenceFailure: Error {
        let underlying: any Error
    }

    /// A read interval holds the same cross-process generation lock as writes,
    /// and proves the writer epoch at both ends. The body cannot suspend.
    /// Tag only fence/root failures so the journal can map those without
    /// converting a graph or domain rejection thrown by the read itself.
    func withAuthorizedRead<Value>(_ body: () throws -> Value) throws -> Value {
        let activity: GenerationTemporalActivityHandleV1
        do { activity = try registry.acquireTemporalWriterRegistrationActivity() }
        catch { throw ReadFenceFailure(underlying: error) }
        defer { activity.close() }
        var bodyFailure: (any Error)?
        do {
            return try registry.withExclusiveGenerationMutationLock {
                try validateCurrentLocked()
                let result: Value
                do { result = try body() }
                catch {
                    bodyFailure = error
                    throw error
                }
                try validateCurrentLocked()
                return result
            }
        } catch {
            if let bodyFailure { throw bodyFailure }
            throw ReadFenceFailure(underlying: error)
        }
    }

    func withAuthorizedCommit<Value>(
        _ operation: () throws -> Value
    ) throws -> Value {
        let activity = try registry.acquireTemporalWriterRegistrationActivity()
        defer { activity.close() }
        return try registry.withExclusiveGenerationCommitLock {
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


/// An advisory activity lifetime, never canonical or filesystem mutation
/// authority. Each handle owns a distinct open description of the already
/// pinned registry directory. Keeping this object alive keeps its registry
/// owner guard alive across asynchronous producer work.
final class GenerationTemporalActivityHandleV1: @unchecked Sendable {
    private let registry: GenerationLeaseRegistryV1
    private let lock = NSLock()
    private var descriptor: Int32
    private enum RetirementCloseState { case open, closed, uncertain }
    private var retirementCloseState: RetirementCloseState = .open
    fileprivate let exclusive: Bool

    fileprivate init(registry: GenerationLeaseRegistryV1, descriptor: Int32,
                     exclusive: Bool) {
        self.registry = registry
        self.descriptor = descriptor
        self.exclusive = exclusive
    }

    fileprivate func validate(for expectedRegistry: GenerationLeaseRegistryV1,
                              exclusive expectedExclusive: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        guard registry === expectedRegistry, exclusive == expectedExclusive,
              descriptor >= 0 else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try registry.validateTemporalActivityDescriptor(descriptor, observationOnly: exclusive)
    }

    fileprivate func validateSharedNormalizationRegistry(_ expected: GenerationLeaseRegistryV1) throws {
        try lock.withLock {
            guard exclusive, descriptor >= 0 else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            try registry.requireSharedTemporalRegistryIdentity(expected)
            try registry.validateTemporalActivityDescriptor(descriptor, observationOnly: true)
        }
    }

    /// Only the Coordinator can hand out a retained producer resource. This
    /// checks the real SH descriptor without admitting or extending a writer.
    func requireLiveProducerResource() throws {
        try validate(for: registry, exclusive: false)
    }

    func closeCheckedForMaintenance() throws {
        try lock.withLock {
            if retirementCloseState == .closed { return }
            guard retirementCloseState == .open, exclusive, descriptor >= 0 else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try registry.validateTemporalActivityDescriptor(descriptor, observationOnly: true)
            guard flock(descriptor, LOCK_UN) == 0 else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            let owned = descriptor; descriptor = -1
            guard Darwin.close(owned) == 0 else {
                retirementCloseState = .uncertain
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            retirementCloseState = .closed
        }
    }

    func closeAfterColdOwnerGuardRemoval() throws {
        try lock.withLock {
            if retirementCloseState == .closed { return }
            guard retirementCloseState == .open, exclusive, descriptor >= 0 else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try registry.requireColdGuardRemoved(activityDescriptor: descriptor)
            guard flock(descriptor, LOCK_UN) == 0 else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            let owned = descriptor; descriptor = -1
            guard Darwin.close(owned) == 0 else {
                retirementCloseState = .uncertain
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            retirementCloseState = .closed
        }
    }

    func closeAfterNamespaceRemoval() throws {
        try lock.withLock {
            if retirementCloseState == .closed { return }
            guard retirementCloseState == .open, exclusive, descriptor >= 0 else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try registry.requireHeldTemporalNamespaceAfterRemoval(activityDescriptor: descriptor)
            guard flock(descriptor, LOCK_UN) == 0 else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            let owned = descriptor; descriptor = -1
            guard Darwin.close(owned) == 0 else {
                retirementCloseState = .uncertain
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            retirementCloseState = .closed
        }
    }

#if DEBUG
    @MainActor
    func requireUnlinkedOriginalOwnerGuardForEraseAbandonment() throws {
        try lock.withLock {
            guard retirementCloseState == .open, exclusive, descriptor >= 0 else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try registry.proveUnlinkedOriginalOwnerGuardForEraseAbandonment(
                activityDescriptor: descriptor)
        }
    }
#endif

    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard descriptor >= 0 else { return }
        let owned = descriptor
        descriptor = -1
        _ = flock(owned, LOCK_UN)
        _ = Darwin.close(owned)
    }

    deinit { close() }
}

extension GenerationLeaseRegistryV1 {
    /// No create or policy repair. A free directory lock establishes only
    /// exclusion; callers must still obtain their genuine generation owner.
    private func acquireTemporalActivity(exclusive: Bool) throws
        -> GenerationTemporalActivityHandleV1 {
        try verify()
        let descriptor = Darwin.openat(leaseDescriptor, ".",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Self.mappedFailure() }
        var transferred = false
        defer { if !transferred { _ = Darwin.close(descriptor) } }
        // Physical identity is pure. Ordinary policy verification may have
        // DEBUG fallback effects, so it must occur only AFTER SH admission.
        try validateTemporalActivityIdentity(descriptor)
        guard flock(descriptor, (exclusive ? LOCK_EX : LOCK_SH) | LOCK_NB) == 0 else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        do { try validateTemporalActivityDescriptor(descriptor, observationOnly: exclusive) }
        catch { _ = flock(descriptor, LOCK_UN); throw error }
        let handle = GenerationTemporalActivityHandleV1(registry: self,
            descriptor: descriptor, exclusive: exclusive)
        transferred = true
        return handle
    }

    fileprivate func validateTemporalActivityDescriptor(_ descriptor: Int32,
                                                       observationOnly: Bool) throws {
        try validateTemporalActivityIdentity(descriptor)
        if observationOnly {
            _ = try ProtectedFilePolicyV1.observeTemporalPolicy(.stagingDirectory, at: leaseURL)
        } else {
            try ProtectedFilePolicyV1.verify(.stagingDirectory, at: leaseURL)
        }
        try requireNamedDirectoryIdentity(parent: operationsDescriptor,
            name: Self.leaseDirectoryName, expected: leaseIdentity)
        guard try Self.directoryIdentity(descriptor) == leaseIdentity else {
            throw Self.identityFailure()
        }
    }

    private func validateTemporalActivityIdentity(_ descriptor: Int32) throws {
        try verify()
        guard try Self.directoryIdentity(descriptor) == leaseIdentity else {
            throw Self.identityFailure()
        }
        try requireNamedDirectoryIdentity(parent: operationsDescriptor,
            name: Self.leaseDirectoryName, expected: leaseIdentity)
    }

    /// Held only through a writer token's registry publication. This uses a
    /// distinct SH open description and never waits behind normalization.
    fileprivate func acquireTemporalWriterRegistrationActivity() throws
        -> GenerationTemporalActivityHandleV1 {
        try acquireTemporalActivity(exclusive: false)
    }

    func acquireTemporalProducerActivity(writer: GenerationLeaseTokenV1) throws
        -> GenerationTemporalActivityHandleV1 {
        let handle = try acquireTemporalActivity(exclusive: false)
        do {
            try withExclusiveGenerationMutationLock {
                try requireNoMigrationReservationLocked()
                try handle.validate(for: self, exclusive: false)
                try validateActiveLocked(writer, requiredRole: .writer)
            }
            return handle
        } catch {
            handle.close()
            throw error
        }
    }

    /// The caller has already closed its local admission and drained actual
    /// asynchronous work. A foreign writer is never guessed idle or harmless.
    func acquireTemporalNormalizationActivity(retainedWriter: GenerationLeaseTokenV1?) throws
        -> GenerationTemporalActivityHandleV1 {
        let handle = try acquireTemporalActivity(exclusive: true)
        do {
            try validateTemporalNormalizationActivity(handle, retainedWriter: retainedWriter)
            return handle
        } catch {
            handle.close()
            throw error
        }
    }

#if DEBUG
    /// The retained operation receives the exact EX before any validation or
    /// root construction can throw. A failure leaves that owner reachable.
    @MainActor
    func acquireTemporalNormalizationActivityForOriginalEraseShutdown(
        witness: EraseOriginalShutdownWitnessV1,
        retainedWriter: GenerationLeaseTokenV1,
        retain: (GenerationTemporalActivityHandleV1) throws -> Void
    ) throws {
        try withOriginalEraseShutdownScope(witness) {
            guard retainedWriter.ownerID == ownerID,
                  retainedWriter.role == .writer else { throw Self.uncertainOwnerFailure() }
            let handle = try acquireTemporalActivity(exclusive: true)
            try retain(handle)
            try validateTemporalNormalizationActivity(handle, retainedWriter: retainedWriter)
            try withTemporalNormalizationMutationLock(activity: handle) {
                let observed = try observeTemporalRegistryLocked()
                originalEraseForeignLeases = observed.leases.filter { $0.ownerID != ownerID }
            }
        }
    }
#endif

    func validateTemporalProducerActivity(_ handle: GenerationTemporalActivityHandleV1,
                                         writer: GenerationLeaseTokenV1) throws {
        try withExclusiveGenerationMutationLock {
            try requireNoMigrationReservationLocked()
            try handle.validate(for: self, exclusive: false)
            try validateActiveLocked(writer, requiredRole: .writer)
        }
    }

    /// Full current writer census, re-read under the same G at every effect.
    /// This intentionally does not reconcile or delete abandoned owners.
    func validateTemporalNormalizationActivity(_ handle: GenerationTemporalActivityHandleV1,
                                              retainedWriter: GenerationLeaseTokenV1?) throws {
        try withTemporalNormalizationMutationLock(activity: handle) {
            try requireNoMigrationReservationLocked()
            try handle.validate(for: self, exclusive: true)
            let observation = try observeTemporalRegistryLocked()
            let writers = observation.leases.filter { $0.role == .writer }
            if let retainedWriter {
                try retainedWriter.validate()
                guard retainedWriter.role == .writer,
                      retainedWriter.ownerID == ownerID, writers == [retainedWriter] else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
            } else {
                guard writers.isEmpty else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            }
            // This is writer census only. All reader/retired/source owners in
            // observation.leases still require the concrete source owner's
            // separate lifetime classification; EX does not discharge them.
        }
    }
}


/// Raw, independently reread registry facts. This has no completion/admission
/// bit: a source owner must classify every retained lease and its lifetime.
struct TemporalGenerationRegistryObservationV1 {
    let leases: [GenerationLeaseTokenV1]
    let registryBytes: Data
    let registryPolicy: TemporalPolicyObservationV1
    let directoryPolicy: TemporalPolicyObservationV1
}

extension GenerationLeaseRegistryV1 {
    private func observeTemporalRegistryLocked() throws -> TemporalGenerationRegistryObservationV1 {
        try verify()
        let directoryPolicy = try ProtectedFilePolicyV1.observeTemporalPolicy(.stagingDirectory, at: leaseURL)
        let descriptor = Darwin.openat(leaseDescriptor, Self.registryName,
            O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Self.mappedFailure() }
        defer { _ = Darwin.close(descriptor) }
        let before = try Self.regularFileSnapshot(descriptor)
        try requireNamedIdentity(parent: leaseDescriptor, name: Self.registryName, expected: before.identity)
        let policy = try ProtectedFilePolicyV1.observeTemporalPolicy(
            try Self.controlKind(for: Self.registryName),
            at: leaseURL.appendingPathComponent(Self.registryName))
        let data = try Self.readAll(from: descriptor)
        guard try Self.regularFileSnapshot(descriptor) == before,
              data.count == Int(before.byteCount) else { throw Self.identityFailure() }
        try requireNamedIdentity(parent: leaseDescriptor, name: Self.registryName, expected: before.identity)
        let state: RegistryStateV1
        do { state = try RegistryStateV1.decodeCanonical(from: data) }
        catch { throw GenerationLeaseRegistryFailureV1.corruptRegistry }
        try verify()
        return TemporalGenerationRegistryObservationV1(leases: state.leases,
            registryBytes: data, registryPolicy: policy, directoryPolicy: directoryPolicy)
    }

    /// Pure observation under the actual retained registry's G. The exact EX
    /// descriptor is required; this method never reconciles owners or controls.
    func observeTemporalNormalizationRegistry(_ handle: GenerationTemporalActivityHandleV1) throws
        -> TemporalGenerationRegistryObservationV1 {
        try withTemporalNormalizationMutationLock(activity: handle) {
            try requireNoMigrationReservationLocked()
            try handle.validate(for: self, exclusive: true)
            return try observeTemporalRegistryLocked()
        }
    }
}


extension GenerationLeaseRegistryV1 {
    fileprivate func requireSharedTemporalRegistryIdentity(_ other: GenerationLeaseRegistryV1) throws {
        try verify(); try other.verify()
        guard rootIdentity == other.rootIdentity,
              operationsIdentity == other.operationsIdentity,
              leaseIdentity == other.leaseIdentity,
              mutationLockIdentity == other.mutationLockIdentity else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }
}


extension GenerationLeaseRegistryV1 {
    /// Changes only this genuine handle's durable lease membership. Existing
    /// controls are read through pure observations; policy setters apply only
    /// to the new temp inode retained by this exact release attempt.
    fileprivate func releaseTemporalMaintenance(_ token: GenerationLeaseTokenV1,
        activity: GenerationTemporalActivityHandleV1) throws {
        try withTemporalNormalizationMutationLock(activity: activity) {
            try token.validate()
            guard token.ownerID == ownerID else { throw GenerationLeaseRegistryFailureV1.leaseNotActive }
            try activity.validateSharedNormalizationRegistry(self)
            let attempt: TemporalReleaseAttempt
            if let retained = temporalReleaseAttempts[token.leaseID] {
                guard retained.token == token else { throw GenerationLeaseRegistryFailureV1.leaseNotActive }
                attempt = retained
            } else {
                let observed = try observeTemporalRegistryLocked()
                guard observed.leases.filter({ $0.leaseID == token.leaseID }) == [token] else {
                    throw GenerationLeaseRegistryFailureV1.leaseNotActive
                }
                let replacement = try RegistryStateV1(leases: observed.leases.filter { $0.leaseID != token.leaseID })
                let original = Darwin.openat(leaseDescriptor, Self.registryName,
                    O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
                guard original >= 0 else { throw Self.mappedFailure() }
                do {
                    let snapshot = try Self.regularFileSnapshot(original)
                    try requireNamedIdentity(parent: leaseDescriptor, name: Self.registryName,
                        expected: snapshot.identity)
                    let bytes = try Self.readAll(from: original)
                    guard bytes == observed.registryBytes,
                          try Self.regularFileSnapshot(original) == snapshot else { throw Self.identityFailure() }
                    attempt = TemporalReleaseAttempt(token: token, original: original,
                        snapshot: snapshot, originalBytes: bytes,
                        replacementBytes: try replacement.canonicalData())
                } catch { _ = Darwin.close(original); throw error }
                temporalReleaseAttempts[token.leaseID] = attempt
            }
            try finishTemporalReplacementLocked(attempt)
            let persisted = try observeTemporalRegistryLocked()
            guard !persisted.leases.contains(where: { $0.leaseID == token.leaseID }) else {
                throw GenerationLeaseRegistryFailureV1.corruptRegistry
            }
        }
        // Preserve the exact attempt until all G/activity postconditions have
        // returned successfully, not merely until the rename body finished.
        temporalReleaseAttempts.removeValue(forKey: token.leaseID)
    }
}


#if DEBUG
extension GenerationLeaseRegistryV1 {
    /// Exact original-owner lease release under the selective closing fence.
    /// The retained attempt owns every open descriptor through a rename and
    /// any failed postcondition. Only a checked descriptor close removes it.
    @MainActor
    func closeOriginalEraseShutdownExclusion(
        witness: EraseOriginalShutdownWitnessV1,
        activity: GenerationTemporalActivityHandleV1,
        physicalRoot: StoreTemporalPhysicalRootExclusionV1
    ) throws {
        try withOriginalEraseShutdownScope(witness) {
            try witness.requireDrained(registry: self)
            try activity.closeCheckedForMaintenance()
            try physicalRoot.closeCheckedForOriginalEraseShutdown()
        }
    }

    @MainActor
    func requireOriginalEraseShutdownLeaseCensus(
        witness: EraseOriginalShutdownWitnessV1,
        activity: GenerationTemporalActivityHandleV1
    ) throws {
        try withOriginalEraseShutdownScope(witness) {
            try witness.requireDrained(registry: self)
            try withTemporalNormalizationMutationLock(activity: activity) {
                let observed = try observeTemporalRegistryLocked()
                guard let foreign = originalEraseForeignLeases,
                      observed.leases == foreign,
                      !observed.leases.contains(where: { $0.ownerID == ownerID }),
                      temporalReleaseAttempts.isEmpty, originalEraseReleaseCaptures.isEmpty,
                      temporalReaderAllocations.isEmpty, freshAdoptionReleases.isEmpty,
                      freshWriterPublications.isEmpty, freshReaderPublications.isEmpty,
                      coldPreparationReaderPublications.isEmpty,
                      preparationReaderPublications.isEmpty,
                      preparationWriterPublications.isEmpty,
                      try migrationReservationLocked()?.ownerID != ownerID else {
                    throw Self.uncertainOwnerFailure()
                }
                try witness.requireDrained(registry: self)
            }
        }
    }

    /// The named guard remains present through the checked EX and root close.
    /// The final unlink has no name-based postverification; its held inode and
    /// fsynced parent supply the only terminal proof.
    @MainActor
    func unlinkOriginalEraseShutdownOwnerGuard(
        witness: EraseOriginalShutdownWitnessV1
    ) throws {
        try withOriginalEraseShutdownScope(witness) {
            try witness.requireDrained(registry: self)
            guard originalEraseForeignLeases != nil,
                  temporalReleaseAttempts.isEmpty,
                  originalEraseReleaseCaptures.isEmpty else {
                throw Self.uncertainOwnerFailure()
            }
            guard flock(mutationLockDescriptor, LOCK_EX) == 0 else {
                throw Self.uncertainOwnerFailure()
            }
            do {
                try verify()
                let observed = try observeTemporalRegistryLocked()
                guard let foreign = originalEraseForeignLeases,
                      observed.leases == foreign,
                      !observed.leases.contains(where: { $0.ownerID == ownerID }),
                      try migrationReservationLocked()?.ownerID != ownerID else {
                    throw Self.uncertainOwnerFailure()
                }
                try requireNamedIdentity(parent: ownersDescriptor,
                    name: Self.ownerLockName(ownerID), expected: ownerLockIdentity)
                guard Darwin.unlinkat(ownersDescriptor, Self.ownerLockName(ownerID), 0) == 0 else {
                    throw Self.uncertainOwnerFailure()
                }
                originalEraseGuardUnlinked = true
                try proveOriginalEraseShutdownUnlinkedGuardHeld()
            } catch {
                guard flock(mutationLockDescriptor, LOCK_UN) == 0 else {
                    throw Self.uncertainOwnerFailure()
                }
                throw error
            }
            guard flock(mutationLockDescriptor, LOCK_UN) == 0 else {
                throw Self.uncertainOwnerFailure()
            }
        }
    }

    @MainActor
    private func proveOriginalEraseShutdownUnlinkedGuardHeld() throws {
        var held = stat(), named = stat()
        guard originalEraseGuardUnlinked,
              Darwin.fstat(ownerLockDescriptor, &held) == 0,
              held.st_dev == ownerLockIdentity.device,
              held.st_ino == ownerLockIdentity.inode,
              (held.st_mode & S_IFMT) == S_IFREG, held.st_nlink == 0,
              Darwin.fstatat(ownersDescriptor, Self.ownerLockName(ownerID), &named,
                  AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT,
              Darwin.fsync(ownersDescriptor) == 0 else {
            throw Self.uncertainOwnerFailure()
        }
    }

    @MainActor
    func finishOriginalEraseShutdownUnlinkedGuard(
        witness: EraseOriginalShutdownWitnessV1
    ) throws {
        Self.processMutationLock.lock()
        defer { Self.processMutationLock.unlock() }
        originalEraseClosingLock.lock()
        defer { originalEraseClosingLock.unlock() }
        guard originalEraseClosingWitness == ObjectIdentifier(witness),
              originalEraseGuardUnlinked else { throw Self.uncertainOwnerFailure() }
        guard flock(mutationLockDescriptor, LOCK_EX) == 0 else {
            throw Self.uncertainOwnerFailure()
        }
        do { try proveOriginalEraseShutdownUnlinkedGuardHeld() }
        catch {
            guard flock(mutationLockDescriptor, LOCK_UN) == 0 else {
                throw Self.uncertainOwnerFailure()
            }
            throw error
        }
        guard flock(mutationLockDescriptor, LOCK_UN) == 0 else {
            throw Self.uncertainOwnerFailure()
        }
        eraseAbandonmentLock.withLock { eraseAbandonedForColdRestart = true }
    }

    @MainActor
    fileprivate func releaseOriginalEraseShutdownLease(
        _ token: GenerationLeaseTokenV1,
        witness: EraseOriginalShutdownWitnessV1,
        activity: GenerationTemporalActivityHandleV1
    ) throws {
        try withOriginalEraseShutdownScope(witness) {
            try witness.requireDrained(registry: self)
            try withTemporalNormalizationMutationLock(activity: activity) {
                try witness.requireDrained(registry: self)
                try token.validate()
                guard token.ownerID == ownerID,
                      !freshAdoptionReleases.keys.contains(token.leaseID),
                      !freshWriterPublications.values.contains(where: { $0.token == token }),
                      !freshReaderPublications.values.contains(where: { $0.token == token }),
                      !coldPreparationReaderPublications.values.contains(where: { $0.token == token }),
                      !preparationReaderPublications.values.contains(where: { $0.token == token }),
                      !preparationWriterPublications.values.contains(where: { $0.token == token }) else {
                    throw Self.uncertainOwnerFailure()
                }
                let attempt: TemporalReleaseAttempt
                if let retained = temporalReleaseAttempts[token.leaseID] {
                    guard retained.token == token else { throw Self.uncertainOwnerFailure() }
                    attempt = retained
                } else {
                    let observed = try observeTemporalRegistryLocked()
                    guard observed.leases.filter({ $0.leaseID == token.leaseID }) == [token] else {
                        throw Self.uncertainOwnerFailure()
                    }
                    let replacement = try RegistryStateV1(
                        leases: observed.leases.filter { $0.leaseID != token.leaseID })
                    let capture: OriginalEraseReleaseCapture
                    if let retained = originalEraseReleaseCaptures[token.leaseID] {
                        guard retained.token == token, !retained.transferredToAttempt else {
                            throw Self.uncertainOwnerFailure()
                        }
                        capture = retained
                    } else {
                        let descriptor = Darwin.openat(leaseDescriptor, Self.registryName,
                            O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
                        guard descriptor >= 0 else { throw Self.mappedFailure() }
                        capture = OriginalEraseReleaseCapture(token: token, descriptor: descriptor)
                        originalEraseReleaseCaptures[token.leaseID] = capture
                    }
                    // Every throw before a complete attempt retains the same
                    // physical descriptor; a retry cannot adopt a new inode.
                    let snapshot = try Self.regularFileSnapshot(capture.descriptor)
                    try requireNamedIdentity(parent: leaseDescriptor, name: Self.registryName,
                        expected: snapshot.identity)
                    let bytes = try Self.readAll(from: capture.descriptor)
                    guard bytes == observed.registryBytes,
                          try Self.regularFileSnapshot(capture.descriptor) == snapshot else {
                        throw Self.identityFailure()
                    }
                    let record = TemporalReleaseAttempt(token: token,
                        original: capture.descriptor, snapshot: snapshot,
                        originalBytes: bytes, replacementBytes: try replacement.canonicalData())
                    temporalReleaseAttempts[token.leaseID] = record
                    capture.transferredToAttempt = true
                    attempt = record
                }
                try finishTemporalReplacementLocked(attempt)
                let persisted = try observeTemporalRegistryLocked()
                guard !persisted.leases.contains(where: { $0.leaseID == token.leaseID }) else {
                    throw Self.uncertainOwnerFailure()
                }
                try attempt.closeOwnedDescriptorsChecked()
                try witness.requireDrained(registry: self)
            }
            temporalReleaseAttempts.removeValue(forKey: token.leaseID)
            originalEraseReleaseCaptures.removeValue(forKey: token.leaseID)
        }
    }
}
#endif

extension GenerationLeaseRegistryV1 {
    /// Cold-owner cleanup never adopts another owner's guard or repairs a
    /// control. Foreign leases may remain; this exact new owner must own none.
    func closeTemporalColdOwnerGuard(activity: GenerationTemporalActivityHandleV1) throws {
#if DEBUG
        guard isTemporalColdOwner || isV949HostileFixtureOwner else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
#else
        guard isTemporalColdOwner else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
#endif
        if temporalColdGuardRemoved {
            try finishTemporalColdGuardRemoval()
            return
        }
        try activity.validateSharedNormalizationRegistry(self)
        // No post-operation verify: this fixed operation removes its own named
        // guard after the last prevalidation. All later use must be terminal.
        try withExclusiveGenerationMutationLock(verifyAfterOperation: false) {
            try activity.validateSharedNormalizationRegistry(self)
            let observation = try observeTemporalRegistryLocked()
            guard !observation.leases.contains(where: { $0.ownerID == ownerID }),
                  temporalReleaseAttempts.isEmpty, temporalReaderAllocations.isEmpty,
                  try migrationReservationLocked()?.ownerID != ownerID else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try requireNamedIdentity(parent: ownersDescriptor, name: Self.ownerLockName(ownerID),
                expected: ownerLockIdentity)
            guard Darwin.unlinkat(ownersDescriptor, Self.ownerLockName(ownerID), 0) == 0 else {
                throw Self.mappedFailure()
            }
            temporalColdGuardRemoved = true
            guard Darwin.fsync(ownersDescriptor) == 0 else { throw Self.mappedFailure() }
        }
    }

    /// Only a recorded successful unlink of this exact retained guard reaches
    /// this retry. Ordinary verification correctly refuses its missing name.
    private func finishTemporalColdGuardRemoval() throws {
        guard temporalColdGuardRemoved else { throw Self.identityFailure() }
        Self.processMutationLock.lock()
        defer { Self.processMutationLock.unlock() }
        guard flock(mutationLockDescriptor, LOCK_EX) == 0 else { throw Self.mappedFailure() }
        defer { _ = flock(mutationLockDescriptor, LOCK_UN) }
        var root = stat(), heldGuard = stat(), named = stat()
        guard Darwin.lstat(applicationSupportURL.path, &root) == 0, Identity(root) == rootIdentity,
              try Self.directoryIdentity(rootDescriptor) == rootIdentity,
              try Self.directoryIdentity(operationsDescriptor) == operationsIdentity,
              try Self.directoryIdentity(leaseDescriptor) == leaseIdentity,
              try Self.directoryIdentity(ownersDescriptor) == ownersIdentity,
              try Self.regularFileIdentity(mutationLockDescriptor) == mutationLockIdentity else {
            throw Self.identityFailure()
        }
        try requireNamedDirectoryIdentity(parent: rootDescriptor, name: Self.operationsName, expected: operationsIdentity)
        try requireNamedDirectoryIdentity(parent: operationsDescriptor, name: Self.leaseDirectoryName, expected: leaseIdentity)
        try requireNamedDirectoryIdentity(parent: leaseDescriptor, name: Self.ownerDirectoryName, expected: ownersIdentity)
        try requireNamedIdentity(parent: leaseDescriptor, name: Self.mutationLockName, expected: mutationLockIdentity)
        guard Darwin.fstat(ownerLockDescriptor, &heldGuard) == 0,
              heldGuard.st_dev == ownerLockIdentity.device, heldGuard.st_ino == ownerLockIdentity.inode,
              heldGuard.st_mode & S_IFMT == S_IFREG, heldGuard.st_nlink == 0,
              Darwin.fstatat(ownersDescriptor, Self.ownerLockName(ownerID), &named, AT_SYMLINK_NOFOLLOW) != 0,
              errno == ENOENT, Darwin.fsync(ownersDescriptor) == 0 else { throw Self.mappedFailure() }
    }
}


extension GenerationLeaseRegistryV1 {
    /// Returns the support identity captured by this source registry when its
    /// original descriptor was opened. This is an observation only: it never
    /// creates or reconciles a control and cannot authorize Erase retirement.
    func originalSupportIdentityForUnadmittedErase() throws
        -> StoreApplicationSupportIdentity {
        guard didCompleteInitialization else { throw Self.identityFailure() }
        try verify()
        var named = stat(), held = stat()
        guard Darwin.lstat(applicationSupportURL.path, &named) == 0,
              Darwin.fstat(rootDescriptor, &held) == 0,
              Identity(named) == rootIdentity,
              Identity(held) == rootIdentity,
              named.st_mode & S_IFMT == S_IFDIR else {
            throw Self.identityFailure()
        }
        return StoreApplicationSupportIdentity(
            device: rootIdentity.device, inode: rootIdentity.inode)
    }

    func requireTemporalEraseNamespace(_ expected: StreamingArchiveRootIdentityV1) throws {
        try verify()
        guard UInt64(operationsIdentity.device) == expected.device,
              UInt64(operationsIdentity.inode) == expected.inode else { throw Self.identityFailure() }
    }
    /// After Operations unlink, only held descriptors plus a noncreating root
    /// absence proof are meaningful; live registry verification must refuse.
    fileprivate func requireHeldTemporalNamespaceAfterRemoval(activityDescriptor: Int32) throws {
        var root = stat(), named = stat()
        guard Darwin.lstat(applicationSupportURL.path, &root) == 0,
              Identity(root) == rootIdentity,
              try Self.directoryIdentity(rootDescriptor) == rootIdentity,
              try Self.directoryIdentity(operationsDescriptor) == operationsIdentity,
              try Self.directoryIdentity(leaseDescriptor) == leaseIdentity,
              try Self.directoryIdentity(activityDescriptor) == leaseIdentity,
              Darwin.fstatat(rootDescriptor, Self.operationsName, &named, AT_SYMLINK_NOFOLLOW) != 0,
              errno == ENOENT else { throw Self.identityFailure() }
    }

#if DEBUG
    /// A retained original guard on an unlinked old namespace cannot guard
    /// the freshly named cold registry. This deliberately does not claim its
    /// descriptor was closed. The caller poisons registry access only after
    /// the EX release has used its final exact drain validation.
    @MainActor
    fileprivate func proveUnlinkedOriginalOwnerGuardForEraseAbandonment(
        activityDescriptor: Int32) throws {
        Self.processMutationLock.lock()
        defer { Self.processMutationLock.unlock() }
        guard eraseAbandonmentLock.withLock({ !eraseAbandonedForColdRestart }),
              didCompleteInitialization,
              !isTemporalColdOwner, generationMutationLockDepth == 0,
              temporalReleaseAttempts.isEmpty, temporalReaderAllocations.isEmpty,
              freshAdoptionReleases.isEmpty, freshWriterPublications.isEmpty,
              freshReaderPublications.isEmpty, coldPreparationReaderPublications.isEmpty,
              preparationReaderPublications.isEmpty, preparationWriterPublications.isEmpty else {
            throw Self.uncertainOwnerFailure()
        }
        try requireHeldTemporalNamespaceAfterRemoval(activityDescriptor: activityDescriptor)
        var held = stat(), named = stat()
        guard Darwin.fstat(ownerLockDescriptor, &held) == 0,
              ownerLockIdentity.type == S_IFREG, ownerLockIdentity.linkCount == 1,
              held.st_dev == ownerLockIdentity.device,
              held.st_ino == ownerLockIdentity.inode,
              (held.st_mode & S_IFMT) == S_IFREG, held.st_nlink == 0,
              Darwin.fstatat(ownersDescriptor, Self.ownerLockName(ownerID), &named,
                  AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else {
            throw Self.uncertainOwnerFailure()
        }
        guard flock(mutationLockDescriptor, LOCK_UN) == 0 else {
            throw Self.uncertainOwnerFailure()
        }
    }

    @MainActor
    func poisonAfterEraseColdRestartAbandonmentForTesting() {
        eraseAbandonmentLock.withLock { eraseAbandonedForColdRestart = true }
    }
#endif
}


extension GenerationLeaseRegistryV1 {
    private func finishTemporalReplacementLocked(_ attempt: TemporalReleaseAttempt) throws {
    try attempt.requireCertainDescriptors()
    if !attempt.renamed {
        try requireNamedIdentity(parent: leaseDescriptor, name: Self.registryName,
            expected: attempt.originalSnapshot.identity)
        guard try Self.regularFileSnapshot(attempt.original) == attempt.originalSnapshot else {
            throw Self.identityFailure()
        }
        _ = try ProtectedFilePolicyV1.observeTemporalPolicy(.generationLeaseControl,
            at: leaseURL.appendingPathComponent(Self.registryName))
        if attempt.temporary < 0 {
            // O_EXCL refuses all prior temps, including equal bytes.
            let temporary = Darwin.openat(leaseDescriptor, Self.registryTemporaryName,
                O_RDWR | O_CREAT | O_EXCL | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
            guard temporary >= 0 else { throw Self.mappedFailure() }
            attempt.temporary = temporary
            attempt.temporaryIdentity = try Self.regularFileIdentity(temporary)
        }
        guard let temporaryIdentity = attempt.temporaryIdentity else { throw Self.identityFailure() }
        try requireNamedIdentity(parent: leaseDescriptor, name: Self.registryTemporaryName,
            expected: temporaryIdentity)
        guard try Self.regularFileIdentity(attempt.temporary) == temporaryIdentity else {
            throw Self.identityFailure()
        }
        if attempt.preparedSnapshot == nil {
            // Retrying preparation touches only this retained newly
            // created inode, never the original or a discovered temp.
            try protectFile(.generationLeaseControlTemporary, parent: leaseDescriptor,
                directoryURL: leaseURL, name: Self.registryTemporaryName, expected: temporaryIdentity)
            guard Darwin.ftruncate(attempt.temporary, 0) == 0,
                  Darwin.lseek(attempt.temporary, 0, SEEK_SET) == 0 else { throw Self.mappedFailure() }
            try Self.writeAll(attempt.replacementBytes, to: attempt.temporary)
            guard Darwin.fsync(attempt.temporary) == 0,
                  Darwin.lseek(attempt.temporary, 0, SEEK_SET) == 0 else { throw Self.mappedFailure() }
            let before = try Self.regularFileSnapshot(attempt.temporary)
            guard try Self.readAll(from: attempt.temporary) == attempt.replacementBytes,
                  try Self.regularFileSnapshot(attempt.temporary) == before else { throw Self.identityFailure() }
            _ = try ProtectedFilePolicyV1.observeTemporalPolicy(.generationLeaseControlTemporary,
                at: leaseURL.appendingPathComponent(Self.registryTemporaryName))
            attempt.preparedSnapshot = try Self.regularFileSnapshot(attempt.temporary)
        }
        guard let prepared = attempt.preparedSnapshot,
              try Self.regularFileSnapshot(attempt.temporary) == prepared,
              try Self.regularFileSnapshot(attempt.original) == attempt.originalSnapshot else {
            throw Self.identityFailure()
        }
        try requireNamedIdentity(parent: leaseDescriptor, name: Self.registryName,
            expected: attempt.originalSnapshot.identity)
        try requireNamedIdentity(parent: leaseDescriptor, name: Self.registryTemporaryName,
            expected: temporaryIdentity)
        try verify()
        guard Darwin.renameat(leaseDescriptor, Self.registryTemporaryName,
            leaseDescriptor, Self.registryName) == 0 else { throw Self.mappedFailure() }
        attempt.renamed = true
    }
    // A failed post-rename fsync is retryable only through this held
    // inode and exact attempt, never merely equal replacement bytes.
    guard let identity = attempt.temporaryIdentity else { throw Self.identityFailure() }
    try requireNamedIdentity(parent: leaseDescriptor, name: Self.registryName, expected: identity)
    guard Darwin.fsync(leaseDescriptor) == 0 else { throw Self.mappedFailure() }
    let persisted = try observeTemporalRegistryLocked()
    guard persisted.registryBytes == attempt.replacementBytes else {
        throw GenerationLeaseRegistryFailureV1.corruptRegistry
    }
    try requireNamedIdentity(parent: leaseDescriptor, name: Self.registryName, expected: identity)
    }
}


fileprivate struct FreshAdoptionDisposalCompletionV1 {
    let token: GenerationLeaseTokenV1?
}

/// Registered in a concrete reader inventory BEFORE publication. It retains
/// the exact publication attempt even when wrapper creation or an outer G
/// postcondition throws. No deinit cleanup or reconstructed reader is proof.
@MainActor
final class GenerationLeaseAllocationAttemptV1 {
    fileprivate let registry: GenerationLeaseRegistryV1
    fileprivate let epoch: GenerationEpochV1
    var generationEpoch: GenerationEpochV1 { epoch }
    fileprivate var token: GenerationLeaseTokenV1?
    fileprivate var handle: GenerationLeaseHandleV1?
    fileprivate var closed = false
    fileprivate var freshDisposalCompletion: FreshAdoptionDisposalCompletionV1?
    private(set) var sealedForRetirement = false
    fileprivate var residualReleaseCompleted = false
    private var coldPreparationAcquisitionStarted = false
    private weak var coldPreparationOperation: EraseColdPreparationOperationV1?
    private var preparationAcquisitionStarted = false
    private weak var preparationOperation: EraseRouterOperationV1?
    private var freshAdoptionAcquisitionStarted = false
    private weak var freshAdoption: EraseFreshAdoptionOwnerV1?
    func sealForRetirement() { sealedForRetirement = true }
    fileprivate init(registry: GenerationLeaseRegistryV1, epoch: GenerationEpochV1) {
        self.registry = registry; self.epoch = epoch
    }
    var allocatedHandle: GenerationLeaseHandleV1? { handle }
    func matches(registry expected: GenerationLeaseRegistryV1) -> Bool { registry === expected }
    func closeAfterEraseFreshAdoptionFailure(proof: EraseFreshAdoptionDrainWitnessV1) throws {
        try proof.requireDrained(registry: registry, readerAllocation: self)
        guard sealedForRetirement else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        if closed { return }
        try registry.closeFreshAdoptionReader(self, proof: proof)
        closed = true
    }
    func acquireReaderForEraseFreshAdoption(adoption expected: EraseFreshAdoptionOwnerV1) throws -> GenerationLeaseHandleV1 {
        guard !coldPreparationAcquisitionStarted, !preparationAcquisitionStarted, !freshAdoptionAcquisitionStarted, !closed, !sealedForRetirement,
              token == nil, handle == nil else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try expected.requireReaderAllocation(self, registry: registry)
        freshAdoptionAcquisitionStarted = true; freshAdoption = expected
        do { return try registry.publishFreshAdoptionReader(self, adoption: expected) }
        catch { sealedForRetirement = true; throw error }
    }
    fileprivate func requireFreshAdoptionDisposalEligibility() throws {
        guard !coldPreparationAcquisitionStarted, !preparationAcquisitionStarted, freshAdoptionAcquisitionStarted || (token == nil && handle == nil) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }
    fileprivate func requireFreshAdoptionAcquiring(_ expected: EraseFreshAdoptionOwnerV1) throws {
        guard !coldPreparationAcquisitionStarted, freshAdoptionAcquisitionStarted, freshAdoption === expected, !closed, !sealedForRetirement else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try expected.requireReaderAllocation(self, registry: registry)
    }
    var preparationPublishedToken: GenerationLeaseTokenV1? {
        guard preparationAcquisitionStarted, !closed else { return nil }
        return registry.preparationPublishedToken(reader: self)
    }
    func acquireReaderForErasePreparation(operation expected: EraseRouterOperationV1) throws -> GenerationLeaseHandleV1 {
        guard !coldPreparationAcquisitionStarted, !preparationAcquisitionStarted, !freshAdoptionAcquisitionStarted,
              !closed, !sealedForRetirement, token == nil, handle == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try expected.requirePreparationReaderAllocation(self, registry: registry)
        preparationAcquisitionStarted = true; preparationOperation = expected
        do { return try registry.publishPreparationReader(self, operation: expected) }
        catch { sealedForRetirement = true; throw error }
    }
    fileprivate func requirePreparationAcquiring(_ expected: EraseRouterOperationV1) throws {
        guard !coldPreparationAcquisitionStarted, preparationAcquisitionStarted, !freshAdoptionAcquisitionStarted,
              preparationOperation === expected, !closed, !sealedForRetirement else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try expected.requirePreparationReaderAllocation(self, registry: registry)
    }
    fileprivate func requirePreparationDisposalEligibility() throws {
        guard !coldPreparationAcquisitionStarted, !freshAdoptionAcquisitionStarted,
              preparationAcquisitionStarted || (token == nil && handle == nil) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }
#if DEBUG
    /// A partially published reader without a wrapper is retained uncertain;
    /// only its original publication attempt can settle that state.
    func closeForOriginalEraseShutdown(proof: EraseOriginalShutdownWitnessV1,
        activity: GenerationTemporalActivityHandleV1) throws {
        try proof.requirePreparationReader(self, registry: registry)
        try requirePreparationDisposalEligibility()
        guard sealedForRetirement else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        if closed { return }
        if let handle {
            try handle.closeForOriginalEraseShutdown(witness: proof, activity: activity)
        } else {
            guard token == nil else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        }
        closed = true
    }
#endif

    func closeAfterErasePreparationFailure(proof: ErasePreparationFailureDrainWitnessV1) throws {
        try proof.requireDrained(registry: registry, readerAllocation: self)
        try requirePreparationDisposalEligibility()
        guard sealedForRetirement else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        if closed { return }
        try registry.closePreparationReader(self, proof: proof)
        closed = true
    }
    var coldPreparationPublishedToken: GenerationLeaseTokenV1? {
        guard coldPreparationAcquisitionStarted, !closed else { return nil }
        return registry.coldPreparationPublishedToken(reader: self)
    }
    func acquireReaderForColdErasePreparation(operation expected: EraseColdPreparationOperationV1) throws -> GenerationLeaseHandleV1 {
        guard !coldPreparationAcquisitionStarted, !preparationAcquisitionStarted, !freshAdoptionAcquisitionStarted,
              !closed, !sealedForRetirement, token == nil, handle == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try expected.requireColdPreparationReaderAllocation(self, registry: registry)
        coldPreparationAcquisitionStarted = true; coldPreparationOperation = expected
        do { return try registry.publishColdPreparationReader(self, operation: expected) }
        catch { sealedForRetirement = true; throw error }
    }
    fileprivate func requireColdPreparationAcquiring(_ expected: EraseColdPreparationOperationV1) throws {
        guard coldPreparationAcquisitionStarted, !preparationAcquisitionStarted, !freshAdoptionAcquisitionStarted,
              coldPreparationOperation === expected, !closed, !sealedForRetirement else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try expected.requireColdPreparationReaderAllocation(self, registry: registry)
    }
    fileprivate func requireColdPreparationDisposalEligibility() throws {
        guard !preparationAcquisitionStarted, !freshAdoptionAcquisitionStarted,
              coldPreparationAcquisitionStarted || (token == nil && handle == nil) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }
    func closeAfterColdErasePreparationFailure(proof: EraseColdPreparationFailureDrainWitnessV1) throws {
        try proof.requireDrained(registry: registry, readerAllocation: self)
        try requireColdPreparationDisposalEligibility()
        guard sealedForRetirement else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        if closed { return }
        try registry.closeColdPreparationReader(self, proof: proof)
        closed = true
    }
    func acquireReader() throws -> GenerationLeaseHandleV1 {
        guard !coldPreparationAcquisitionStarted, !preparationAcquisitionStarted, !freshAdoptionAcquisitionStarted, !closed, !sealedForRetirement else { throw GenerationLeaseRegistryFailureV1.leaseNotActive }
        return try registry.publishOrdinaryReaderAllocation(self)
    }
    func acquireReaderWhileExcluded(activity: GenerationTemporalActivityHandleV1) throws -> GenerationLeaseHandleV1 {
        guard !coldPreparationAcquisitionStarted, !preparationAcquisitionStarted, !freshAdoptionAcquisitionStarted, !closed, !sealedForRetirement else { throw GenerationLeaseRegistryFailureV1.leaseNotActive }
        return try registry.publishExcludedReaderAllocation(self, activity: activity)
    }
    func observedRetirementToken(activity: GenerationTemporalActivityHandleV1) throws -> GenerationLeaseTokenV1? {
        guard sealedForRetirement else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        return try registry.observeReaderAllocationForRetirement(self, activity: activity)
    }
    func closeAfterDrain(activity: GenerationTemporalActivityHandleV1) throws {
        guard !closed else { return }
        try registry.closeReaderAllocation(self, activity: activity)
        closed = true
    }
}

extension GenerationLeaseRegistryV1 {
    @MainActor
    func makeReaderAllocationAttempt(epoch: GenerationEpochV1) throws -> GenerationLeaseAllocationAttemptV1 {
        try epoch.validate()
        return GenerationLeaseAllocationAttemptV1(registry: self, epoch: epoch)
    }
    @MainActor
    fileprivate func publishOrdinaryReaderAllocation(_ allocation: GenerationLeaseAllocationAttemptV1) throws
        -> GenerationLeaseHandleV1 {
        try withExclusiveGenerationMutationLock { try publishReaderAllocationLocked(allocation) }
    }
    @MainActor
    fileprivate func publishExcludedReaderAllocation(_ allocation: GenerationLeaseAllocationAttemptV1,
        activity: GenerationTemporalActivityHandleV1) throws -> GenerationLeaseHandleV1 {
        try withTemporalNormalizationMutationLock(activity: activity) {
            try publishReaderAllocationLocked(allocation)
        }
    }
    @MainActor
    private func publishReaderAllocationLocked(_ allocation: GenerationLeaseAllocationAttemptV1) throws
        -> GenerationLeaseHandleV1 {
        guard allocation.registry === self, !allocation.closed else {
            throw GenerationLeaseRegistryFailureV1.leaseNotActive
        }
        try requireNoMigrationReservationLocked()
        let identity = ObjectIdentifier(allocation)
        if let handle = allocation.handle {
            let observed = try observeTemporalRegistryLocked()
            guard observed.leases.filter({ $0.leaseID == handle.token.leaseID }) == [handle.token] else {
                throw GenerationLeaseRegistryFailureV1.leaseNotActive
            }
            return handle
        }
        let attempt: TemporalReleaseAttempt
        if let retained = temporalReaderAllocations[identity] {
            attempt = retained
        } else {
            let observed = try observeTemporalRegistryLocked()
            guard observed.leases.count < Self.maximumActiveLeaseCount else {
                throw GenerationLeaseRegistryFailureV1.registryLimitExceeded
            }
            let owners = Set(observed.leases.map(\.ownerID))
            guard owners.contains(ownerID) || owners.count < Self.maximumOwnerCount else {
                throw GenerationLeaseRegistryFailureV1.registryLimitExceeded
            }
            let token: GenerationLeaseTokenV1
            if let retained = allocation.token { token = retained }
            else {
                token = try GenerationLeaseTokenV1(leaseID: makeLeaseID(), ownerID: ownerID,
                    epoch: allocation.epoch, role: .reader, acquiredAt: now())
                allocation.token = token
            }
            guard !observed.leases.contains(where: { $0.leaseID == token.leaseID }) else {
                throw GenerationLeaseRegistryFailureV1.duplicateLease
            }
            let original = Darwin.openat(leaseDescriptor, Self.registryName,
                O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            guard original >= 0 else { throw Self.mappedFailure() }
            do {
                let snapshot = try Self.regularFileSnapshot(original)
                try requireNamedIdentity(parent: leaseDescriptor, name: Self.registryName, expected: snapshot.identity)
                let data = try Self.readAll(from: original)
                guard data == observed.registryBytes, try Self.regularFileSnapshot(original) == snapshot else {
                    throw Self.identityFailure()
                }
                let replacement = try RegistryStateV1(leases: observed.leases + [token])
                attempt = TemporalReleaseAttempt(token: token, original: original, snapshot: snapshot,
                    originalBytes: data, replacementBytes: try replacement.canonicalData())
            } catch { _ = Darwin.close(original); throw error }
            temporalReaderAllocations[identity] = attempt
        }
        try finishTemporalReplacementLocked(attempt)
        let observed = try observeTemporalRegistryLocked()
        guard observed.leases.filter({ $0.leaseID == attempt.token.leaseID }) == [attempt.token] else {
            throw GenerationLeaseRegistryFailureV1.leaseNotActive
        }
        let handle = try GenerationLeaseHandleV1(registry: self, publishedReaderToken: attempt.token)
        allocation.handle = handle
        temporalReaderAllocations.removeValue(forKey: identity)
        return handle
    }
    @MainActor
    fileprivate func closeReaderAllocation(_ allocation: GenerationLeaseAllocationAttemptV1,
        activity: GenerationTemporalActivityHandleV1) throws {
        guard allocation.registry === self,
              coldPreparationReaderPublications[ObjectIdentifier(allocation)] == nil,
              preparationReaderPublications[ObjectIdentifier(allocation)] == nil,
              freshReaderPublications[ObjectIdentifier(allocation)] == nil else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        if let handle = allocation.handle {
            try handle.closeForTemporalMaintenance(activity: activity)
            return
        }
        try withTemporalNormalizationMutationLock(activity: activity) {
            let identity = ObjectIdentifier(allocation)
            if let attempt = temporalReaderAllocations[identity] {
                if attempt.renamed {
                    if !allocation.residualReleaseCompleted {
                        // A retained release attempt supersedes the original
                        // insertion proof once removal has begun.
                        if temporalReleaseAttempts[attempt.token.leaseID] == nil {
                            try finishTemporalReplacementLocked(attempt)
                        }
                        try releaseTemporalMaintenance(attempt.token, activity: activity)
                        allocation.residualReleaseCompleted = true
                    }
                    guard try !observeTemporalRegistryLocked().leases.contains(where: { $0.leaseID == attempt.token.leaseID }) else {
                        throw GenerationLeaseRegistryFailureV1.uncertainOwner
                    }
                } else {
                    // Publication never occurred. Dispose only this retained
                    // new temp; do not publish a synthetic reader to close it.
                    try requireNamedIdentity(parent: leaseDescriptor, name: Self.registryName,
                        expected: attempt.originalSnapshot.identity)
                    guard try Self.regularFileSnapshot(attempt.original) == attempt.originalSnapshot else {
                        throw Self.identityFailure()
                    }
                    if attempt.temporary >= 0, !attempt.temporaryRemoved {
                        guard let temporaryIdentity = attempt.temporaryIdentity else { throw Self.identityFailure() }
                        try requireNamedIdentity(parent: leaseDescriptor, name: Self.registryTemporaryName,
                            expected: temporaryIdentity)
                        guard try Self.regularFileIdentity(attempt.temporary) == temporaryIdentity,
                              Darwin.unlinkat(leaseDescriptor, Self.registryTemporaryName, 0) == 0 else {
                            throw Self.identityFailure()
                        }
                        attempt.temporaryRemoved = true
                    }
                    if attempt.temporaryRemoved {
                        var named = stat(), held = stat()
                        guard let identity = attempt.temporaryIdentity,
                              Darwin.fstat(attempt.temporary, &held) == 0,
                              held.st_dev == identity.device, held.st_ino == identity.inode,
                              held.st_nlink == 0, held.st_mode & S_IFMT == S_IFREG,
                              Darwin.fstatat(leaseDescriptor, Self.registryTemporaryName, &named, AT_SYMLINK_NOFOLLOW) != 0,
                              errno == ENOENT else { throw Self.identityFailure() }
                    }
                    guard Darwin.fsync(leaseDescriptor) == 0 else { throw Self.mappedFailure() }
                }
                temporalReaderAllocations.removeValue(forKey: identity)
            } else if let token = allocation.token {
                let observed = try observeTemporalRegistryLocked()
                guard !observed.leases.contains(where: { $0.leaseID == token.leaseID }) else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
            }
        }
    }
}


extension GenerationLeaseRegistryV1 {
    @MainActor
    fileprivate func observeReaderAllocationForRetirement(_ allocation: GenerationLeaseAllocationAttemptV1,
        activity: GenerationTemporalActivityHandleV1) throws -> GenerationLeaseTokenV1? {
        guard allocation.registry === self, allocation.sealedForRetirement,
              coldPreparationReaderPublications[ObjectIdentifier(allocation)] == nil,
              preparationReaderPublications[ObjectIdentifier(allocation)] == nil,
              freshReaderPublications[ObjectIdentifier(allocation)] == nil else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        return try withTemporalNormalizationMutationLock(activity: activity) {
            guard let token = allocation.token else { return nil }
            let observed = try observeTemporalRegistryLocked()
            let matches = observed.leases.filter { $0.leaseID == token.leaseID }
            guard matches.isEmpty || matches == [token] else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            return matches.first
        }
    }
}


extension GenerationLeaseRegistryV1 {
    fileprivate func requireColdGuardRemoved(activityDescriptor: Int32) throws {
#if DEBUG
        let permitted = isTemporalColdOwner || isV949HostileFixtureOwner
#else
        let permitted = isTemporalColdOwner
#endif
        guard permitted, temporalColdGuardRemoved,
              try Self.directoryIdentity(activityDescriptor) == leaseIdentity else { throw Self.identityFailure() }
        try finishTemporalColdGuardRemoval()
    }
}


/// Retained before cold construction opens any descriptor. Only the exact new
/// owner guard may be removed; no durable reader token can exist at this stage.
@MainActor
final class TemporalColdRegistryConstructionV1 {
    private struct Entry { let fd: Int32; let url: URL }
    private var entries: [Entry] = []
    private var guardFD: Int32?
    private var guardParent: Int32?
    private var guardName: String?
    private var guardRemoved = false
    private var transferred = false
    private var uncertainClose = false
    fileprivate func retain(_ fd: Int32, at url: URL) { entries.append(Entry(fd: fd, url: url)) }
    fileprivate func retainCreatedGuard(_ fd: Int32, parent: Int32, name: String, at url: URL) {
        retain(fd, at: url); guardFD = fd; guardParent = parent; guardName = name
    }
    fileprivate func transferDescriptorsToRegistry() {
        transferred = true; entries.removeAll(); guardFD = nil; guardParent = nil; guardName = nil
    }
    /// Caller retains the real support EX throughout this method. Failed checks
    /// keep all handles; successful unlink is separately remembered for fsync retry.
    func closeUntransferred() throws {
        guard !uncertainClose else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        guard !transferred else { return }
        for entry in entries {
            var held = stat(); var named = stat()
            guard fstat(entry.fd, &held) == 0 else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            if entry.fd == guardFD, guardRemoved {
                errno = 0
                guard held.st_nlink == 0, lstat(entry.url.path, &named) == -1, errno == ENOENT else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
            } else {
                guard lstat(entry.url.path, &named) == 0,
                      held.st_dev == named.st_dev, held.st_ino == named.st_ino,
                      (held.st_mode & S_IFMT) == (named.st_mode & S_IFMT),
                      (held.st_mode & S_IFMT) != S_IFLNK else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
            }
        }
        if let guardFD, let guardParent, let guardName {
            if !guardRemoved {
                var held = stat(); var named = stat()
                guard fstat(guardFD, &held) == 0, held.st_nlink == 1,
                      (held.st_mode & S_IFMT) == S_IFREG,
                      fstatat(guardParent, guardName, &named, AT_SYMLINK_NOFOLLOW) == 0,
                      held.st_dev == named.st_dev, held.st_ino == named.st_ino,
                      flock(guardFD, LOCK_EX | LOCK_NB) == 0 else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                guard unlinkat(guardParent, guardName, 0) == 0 else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
                guardRemoved = true
            }
            guard fsync(guardParent) == 0 else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        }
        while let entry = entries.last {
            // Remove the numeric descriptor before close: an ambiguous close
            // must never retry against a possibly reused descriptor number.
            entries.removeLast()
            if Darwin.close(entry.fd) != 0 {
                uncertainClose = true
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
        guardFD = nil; guardParent = nil; guardName = nil
    }
}


/// Physical EX acquisition only. The genuine Router authority owns this
/// attempt before opening; it grants neither access nor lease classification.
@MainActor
final class GenerationTemporalColdActivityAcquisitionV1 {
    private let registry: GenerationLeaseRegistryV1
    private var descriptor: Int32 = -1
    private var locked = false
    private var uncertain = false
    private var closed = false
    private var result: GenerationTemporalActivityHandleV1?
    fileprivate init(registry: GenerationLeaseRegistryV1) { self.registry = registry }
    fileprivate func matches(registry expected: GenerationLeaseRegistryV1) -> Bool {
        registry === expected
    }
    func acquire() throws -> GenerationTemporalActivityHandleV1 {
        guard !closed, !uncertain else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        if let result {
            try registry.validateTemporalNormalizationActivity(result, retainedWriter: nil)
            return result
        }
        if descriptor < 0 { descriptor = try registry.openColdRetirementActivityDescriptor() }
        try registry.validateColdRetirementActivityDescriptor(descriptor)
        if !locked {
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            locked = true
        }
        try registry.validateColdRetirementActivityDescriptor(descriptor)
        // Transfer the actual descriptor before any higher-level census check.
        let handle = GenerationTemporalActivityHandleV1(registry: registry, descriptor: descriptor, exclusive: true)
        result = handle; descriptor = -1; locked = false
        try registry.validateTemporalNormalizationActivity(handle, retainedWriter: nil)
        return handle
    }
    func closeAfterFailure() throws {
        guard !uncertain else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        if closed { return }
        if let result {
            try result.closeCheckedForMaintenance()
            self.result = nil
        }
        if descriptor >= 0 {
            if locked {
                guard flock(descriptor, LOCK_UN) == 0 else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
                locked = false
            }
            let owned = descriptor; descriptor = -1
            guard Darwin.close(owned) == 0 else {
                uncertain = true; throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
        closed = true
    }
}

extension GenerationLeaseRegistryV1 {
    @MainActor
    func makeColdRetirementActivityAcquisition() -> GenerationTemporalColdActivityAcquisitionV1 {
        GenerationTemporalColdActivityAcquisitionV1(registry: self)
    }
    fileprivate func openColdRetirementActivityDescriptor() throws -> Int32 {
        try verify()
        let fd = Darwin.openat(leaseDescriptor, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Self.mappedFailure() }
        return fd // caller stores before any subsequent throwing operation
    }
    fileprivate func validateColdRetirementActivityDescriptor(_ fd: Int32) throws {
        try validateTemporalActivityDescriptor(fd, observationOnly: true)
    }
}

// Concrete Store-owned type; its constructor is not available to consumers.
typealias EraseManifestRetirementAttemptV1 = StoreMigrationJournalStoreV1.EraseManifestRetirementAttemptV1

/// Writer allocation retained before publication by its genuine, distinct
/// fresh-adoption or original preparation owner. Never retired-writer authority.
@MainActor
final class GenerationWriterAllocationAttemptV1 {
    fileprivate let registry: GenerationLeaseRegistryV1
    let generationEpoch: GenerationEpochV1
    fileprivate var token: GenerationLeaseTokenV1?
    fileprivate var handle: GenerationLeaseHandleV1?
    fileprivate var closed = false
    fileprivate var freshDisposalCompletion: FreshAdoptionDisposalCompletionV1?
    private var preparationAcquisitionStarted = false
    private weak var preparationOperation: EraseRouterOperationV1?
    private var acquisitionStarted = false
    private weak var adoption: EraseFreshAdoptionOwnerV1?
    private(set) var sealedForRetirement = false
    fileprivate init(registry: GenerationLeaseRegistryV1, epoch: GenerationEpochV1) {
        self.registry = registry; generationEpoch = epoch
    }
    var allocatedHandle: GenerationLeaseHandleV1? { handle }
    func matches(registry expected: GenerationLeaseRegistryV1) -> Bool { registry === expected }
    func sealForRetirement() { sealedForRetirement = true }
    func acquireWriter(adoption expected: EraseFreshAdoptionOwnerV1) throws -> GenerationLeaseHandleV1 {
        guard !preparationAcquisitionStarted, !acquisitionStarted, !closed, !sealedForRetirement else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try expected.requireWriterAllocation(self, registry: registry)
        acquisitionStarted = true; adoption = expected
        do { return try registry.publishFreshAdoptionWriter(self, adoption: expected) }
        catch { sealedForRetirement = true; throw error }
    }
    fileprivate func requireAcquiring(adoption expected: EraseFreshAdoptionOwnerV1) throws {
        guard acquisitionStarted, adoption === expected, !closed, !sealedForRetirement else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try expected.requireWriterAllocation(self, registry: registry)
    }
    var preparationPublishedToken: GenerationLeaseTokenV1? {
        guard preparationAcquisitionStarted, !closed else { return nil }
        return registry.preparationPublishedToken(writer: self)
    }
    func acquireWriterForErasePreparation(operation expected: EraseRouterOperationV1) throws -> GenerationLeaseHandleV1 {
        guard !preparationAcquisitionStarted, !acquisitionStarted, !closed, !sealedForRetirement,
              token == nil, handle == nil else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try expected.requirePreparationWriterAllocation(self, registry: registry)
        preparationAcquisitionStarted = true; preparationOperation = expected
        do { return try registry.publishPreparationWriter(self, operation: expected) }
        catch { sealedForRetirement = true; throw error }
    }
    fileprivate func requirePreparationAcquiring(_ expected: EraseRouterOperationV1) throws {
        guard preparationAcquisitionStarted, !acquisitionStarted, preparationOperation === expected,
              !closed, !sealedForRetirement else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try expected.requirePreparationWriterAllocation(self, registry: registry)
    }
    fileprivate func requirePreparationDisposalEligibility() throws {
        guard !acquisitionStarted, preparationAcquisitionStarted || (token == nil && handle == nil) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }
#if DEBUG
    /// Installed target writers are eligible only through this exact original
    /// shutdown witness. The ordinary preparation-failure close stays guarded.
    func closeForOriginalEraseShutdown(proof: EraseOriginalShutdownWitnessV1,
        activity: GenerationTemporalActivityHandleV1) throws {
        try proof.requirePreparationWriter(self, registry: registry)
        try requirePreparationDisposalEligibility()
        guard sealedForRetirement else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        if closed { return }
        if let handle {
            try handle.closeForOriginalEraseShutdown(witness: proof, activity: activity)
        } else {
            guard token == nil else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        }
        closed = true
    }
#endif

    func closeAfterErasePreparationFailure(proof: ErasePreparationFailureDrainWitnessV1) throws {
        try proof.requireDrained(registry: registry, writerAllocation: self)
        try requirePreparationDisposalEligibility()
        guard sealedForRetirement else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        if closed { return }
        try registry.closePreparationWriter(self, proof: proof)
        closed = true
    }
    func closeAfterEraseFreshAdoptionFailure(proof: EraseFreshAdoptionDrainWitnessV1) throws {
        try proof.requireDrained(registry: registry, writerAllocation: self)
        guard !preparationAcquisitionStarted, sealedForRetirement else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        if closed { return }
        try registry.closeFreshAdoptionWriter(self, proof: proof)
        closed = true
    }
}

extension GenerationLeaseRegistryV1 {
    @MainActor
    func makeWriterAllocationAttempt(epoch: GenerationEpochV1) throws -> GenerationWriterAllocationAttemptV1 {
        try epoch.validate()
        return GenerationWriterAllocationAttemptV1(registry: self, epoch: epoch)
    }
    /// Captures only this actual retained replacement's original descriptor.
    /// Caller registers `record` before this first open; failed fstat/read and
    /// canonical encoding leave that exact FD owned for fixed disposal.
    private func captureFreshAdoptionReplacementLocked(_ record: FreshAdoptionReplacement,
        observed: TemporalGenerationRegistryObservationV1, replacement: RegistryStateV1) throws {
        guard record.replacement == nil, !record.originalCloseAttempted, !record.closeUncertain else { throw Self.identityFailure() }
        if record.original < 0 {
            let fd = Darwin.openat(leaseDescriptor, Self.registryName, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw Self.mappedFailure() }
            record.original = fd
        }
        let fd = record.original
        let snapshot = try Self.regularFileSnapshot(fd)
        try requireNamedIdentity(parent: leaseDescriptor, name: Self.registryName, expected: snapshot.identity)
        let bytes = try Self.readAll(from: fd)
        guard bytes == observed.registryBytes, try Self.regularFileSnapshot(fd) == snapshot else { throw Self.identityFailure() }
        let attempt = TemporalReleaseAttempt(token: record.token, original: fd, snapshot: snapshot,
            originalBytes: bytes, replacementBytes: try replacement.canonicalData())
        record.replacement = attempt
        record.original = -1 // transfer only after the actual replacement owns it
    }
    @MainActor
    fileprivate func publishFreshAdoptionWriter(_ allocation: GenerationWriterAllocationAttemptV1,
        adoption: EraseFreshAdoptionOwnerV1) throws -> GenerationLeaseHandleV1 {
        guard allocation.registry === self else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try allocation.requireAcquiring(adoption: adoption)
        let handle = try withExclusiveGenerationMutationLock {
            try allocation.requireAcquiring(adoption: adoption)
            try requireNoMigrationReservationLocked()
            let observed = try observeTemporalRegistryLocked()
            guard !observed.leases.contains(where: { $0.role == .writer }) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            guard observed.leases.count < Self.maximumActiveLeaseCount else {
                throw GenerationLeaseRegistryFailureV1.registryLimitExceeded
            }
            let owners = Set(observed.leases.map(\.ownerID))
            guard owners.contains(ownerID) || owners.count < Self.maximumOwnerCount else {
                throw GenerationLeaseRegistryFailureV1.registryLimitExceeded
            }
            let token = try GenerationLeaseTokenV1(leaseID: makeLeaseID(), ownerID: ownerID,
                epoch: allocation.generationEpoch, role: .writer, acquiredAt: now())
            guard !observed.leases.contains(where: { $0.leaseID == token.leaseID }), allocation.token == nil else {
                throw GenerationLeaseRegistryFailureV1.duplicateLease
            }
            allocation.token = token
            let record = FreshAdoptionReplacement(token: token)
            let id = ObjectIdentifier(allocation)
            guard freshWriterPublications[id] == nil else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            freshWriterPublications[id] = record
            try captureFreshAdoptionReplacementLocked(record, observed: observed,
                replacement: RegistryStateV1(leases: observed.leases + [token]))
            guard let attempt = record.replacement else { throw Self.identityFailure() }
            try finishTemporalReplacementLocked(attempt)
            let current = try observeTemporalRegistryLocked()
            guard current.leases.filter({ $0.role == .writer }) == [token] else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            let handle = try GenerationLeaseHandleV1(registry: self, publishedWriterToken: token)
            allocation.handle = handle // before outer G/post-admission can throw
            try allocation.requireAcquiring(adoption: adoption)
            return handle
        }
        try allocation.requireAcquiring(adoption: adoption)
        try withExclusiveGenerationMutationLock {
            try allocation.requireAcquiring(adoption: adoption)
            guard let record = freshWriterPublications[ObjectIdentifier(allocation)] else { throw Self.identityFailure() }
            let observed = try observeTemporalRegistryLocked()
            guard observed.leases.filter({ $0.leaseID == handle.token.leaseID }) == [handle.token] else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try record.closeOwnedDescriptorsChecked()
            freshWriterPublications.removeValue(forKey: ObjectIdentifier(allocation))
        }
        try allocation.requireAcquiring(adoption: adoption)
        return handle
    }

    @MainActor
    fileprivate func publishFreshAdoptionReader(_ allocation: GenerationLeaseAllocationAttemptV1,
        adoption: EraseFreshAdoptionOwnerV1) throws -> GenerationLeaseHandleV1 {
        guard allocation.registry === self else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try allocation.requireFreshAdoptionAcquiring(adoption)
        let handle = try withExclusiveGenerationMutationLock {
            try allocation.requireFreshAdoptionAcquiring(adoption)
            try requireNoMigrationReservationLocked()
            let observed = try observeTemporalRegistryLocked()
            guard !observed.leases.contains(where: { $0.role == .writer }) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            guard observed.leases.count < Self.maximumActiveLeaseCount else {
                throw GenerationLeaseRegistryFailureV1.registryLimitExceeded
            }
            let owners = Set(observed.leases.map(\.ownerID))
            guard owners.contains(ownerID) || owners.count < Self.maximumOwnerCount else {
                throw GenerationLeaseRegistryFailureV1.registryLimitExceeded
            }
            let token = try GenerationLeaseTokenV1(leaseID: makeLeaseID(), ownerID: ownerID,
                epoch: allocation.epoch, role: .reader, acquiredAt: now())
            guard !observed.leases.contains(where: { $0.leaseID == token.leaseID }), allocation.token == nil else {
                throw GenerationLeaseRegistryFailureV1.duplicateLease
            }
            allocation.token = token
            let record = FreshAdoptionReplacement(token: token)
            let id = ObjectIdentifier(allocation)
            guard freshReaderPublications[id] == nil else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            freshReaderPublications[id] = record
            try captureFreshAdoptionReplacementLocked(record, observed: observed,
                replacement: RegistryStateV1(leases: observed.leases + [token]))
            guard let attempt = record.replacement else { throw Self.identityFailure() }
            try finishTemporalReplacementLocked(attempt)
            let current = try observeTemporalRegistryLocked()
            guard current.leases.filter({ $0.leaseID == token.leaseID }) == [token],
                  !current.leases.contains(where: { $0.role == .writer }) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            let handle = try GenerationLeaseHandleV1(registry: self, publishedReaderToken: token)
            allocation.handle = handle // before outer G/post-admission can throw
            try allocation.requireFreshAdoptionAcquiring(adoption)
            return handle
        }
        try allocation.requireFreshAdoptionAcquiring(adoption)
        try withExclusiveGenerationMutationLock {
            try allocation.requireFreshAdoptionAcquiring(adoption)
            guard let record = freshReaderPublications[ObjectIdentifier(allocation)] else { throw Self.identityFailure() }
            let observed = try observeTemporalRegistryLocked()
            guard observed.leases.filter({ $0.leaseID == handle.token.leaseID }) == [handle.token] else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try record.closeOwnedDescriptorsChecked()
            freshReaderPublications.removeValue(forKey: ObjectIdentifier(allocation))
        }
        try allocation.requireFreshAdoptionAcquiring(adoption)
        return handle
    }

    /// Disposes only a retained insertion that never crossed rename. Never
    /// publishes a synthetic lease merely to be able to release one.
    private func abandonFreshAdoptionInsertionLocked(_ attempt: TemporalReleaseAttempt) throws {
        try attempt.requireCertainDescriptors()
        guard !attempt.renamed else { throw Self.identityFailure() }
        try requireNamedIdentity(parent: leaseDescriptor, name: Self.registryName, expected: attempt.originalSnapshot.identity)
        guard try Self.regularFileSnapshot(attempt.original) == attempt.originalSnapshot else { throw Self.identityFailure() }
        if attempt.temporary >= 0, !attempt.temporaryRemoved {
            let held = try Self.regularFileIdentity(attempt.temporary)
            if let expected = attempt.temporaryIdentity { guard held == expected else { throw Self.identityFailure() } }
            else { attempt.temporaryIdentity = held } // actual still-held O_EXCL-created FD, never name discovery
            try requireNamedIdentity(parent: leaseDescriptor, name: Self.registryTemporaryName, expected: held)
            guard Darwin.unlinkat(leaseDescriptor, Self.registryTemporaryName, 0) == 0 else { throw Self.mappedFailure() }
            attempt.temporaryRemoved = true
        }
        if attempt.temporaryRemoved {
            var held = stat(), named = stat()
            guard let identity = attempt.temporaryIdentity,
                  Darwin.fstat(attempt.temporary, &held) == 0,
                  held.st_dev == identity.device, held.st_ino == identity.inode,
                  held.st_nlink == 0, held.st_mode & S_IFMT == S_IFREG,
                  Darwin.fstatat(leaseDescriptor, Self.registryTemporaryName, &named, AT_SYMLINK_NOFOLLOW) != 0,
                  errno == ENOENT else { throw Self.identityFailure() }
        }
        guard Darwin.fsync(leaseDescriptor) == 0,
              try !observeTemporalRegistryLocked().leases.contains(where: { $0.leaseID == attempt.token.leaseID }) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
    }
    /// Fixed genuine fresh-owner release under ordinary SH + G. The caller's
    /// exact weak-alias witness is checked before and after this operation.
    private func releaseFreshAdoptionTokenLocked(_ token: GenerationLeaseTokenV1) throws {
        try token.validate()
        guard token.ownerID == ownerID else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        let record: FreshAdoptionReplacement
        if let retained = freshAdoptionReleases[token.leaseID] {
            guard retained.token == token else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            record = retained
        } else {
            let observed = try observeTemporalRegistryLocked()
            guard observed.leases.filter({ $0.leaseID == token.leaseID }) == [token] else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            record = FreshAdoptionReplacement(token: token)
            freshAdoptionReleases[token.leaseID] = record
            try captureFreshAdoptionReplacementLocked(record, observed: observed,
                replacement: RegistryStateV1(leases: observed.leases.filter { $0.leaseID != token.leaseID }))
        }
        guard !record.closeUncertain else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        if record.replacement == nil {
            // Retry the same retained read/capture record and descriptor. No
            // second removal owner or reconstructed publication is introduced.
            let observed = try observeTemporalRegistryLocked()
            guard observed.leases.filter({ $0.leaseID == token.leaseID }) == [token] else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try captureFreshAdoptionReplacementLocked(record, observed: observed,
                replacement: RegistryStateV1(leases: observed.leases.filter { $0.leaseID != token.leaseID }))
        }
        guard let attempt = record.replacement else { throw Self.identityFailure() }
        try finishTemporalReplacementLocked(attempt)
        guard try !observeTemporalRegistryLocked().leases.contains(where: { $0.leaseID == token.leaseID }) else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        record.completed = true
    }
    private func finishFreshAdoptionRelease(_ token: GenerationLeaseTokenV1) throws {
        guard let record = freshAdoptionReleases[token.leaseID], record.completed else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try record.closeOwnedDescriptorsChecked()
        freshAdoptionReleases.removeValue(forKey: token.leaseID)
    }
    private func requireFreshDisposalCompletionLocked(_ completion: FreshAdoptionDisposalCompletionV1,
        token: GenerationLeaseTokenV1?, handle: GenerationLeaseHandleV1?) throws {
        guard completion.token == token else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        if let token {
            guard freshAdoptionReleases[token.leaseID] == nil,
                  try !observeTemporalRegistryLocked().leases.contains(where: { $0.leaseID == token.leaseID }) else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
        }
        try handle?.requireRecordedFreshAdoptionRelease(registry: self)
    }
    @MainActor
    fileprivate func closeFreshAdoptionWriter(_ allocation: GenerationWriterAllocationAttemptV1,
        proof: EraseFreshAdoptionDrainWitnessV1) throws {
        guard allocation.registry === self, allocation.sealedForRetirement else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try proof.requireDrained(registry: self, writerAllocation: allocation)
        try withExclusiveGenerationMutationLock {
            try proof.requireDrained(registry: self, writerAllocation: allocation)
            if let completed = allocation.freshDisposalCompletion {
                guard freshWriterPublications[ObjectIdentifier(allocation)] == nil else { throw Self.identityFailure() }
                try requireFreshDisposalCompletionLocked(completed, token: allocation.token, handle: allocation.handle)
                return
            }
            if let retained = freshWriterPublications[ObjectIdentifier(allocation)], retained.closeUncertain {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            var published = allocation.handle != nil
            if let insertion = freshWriterPublications[ObjectIdentifier(allocation)]?.replacement {
                if insertion.renamed {
                    published = true
                    if allocation.handle == nil, freshAdoptionReleases[insertion.token.leaseID] == nil {
                        try finishTemporalReplacementLocked(insertion)
                    }
                } else { try abandonFreshAdoptionInsertionLocked(insertion) }
            }
            if published {
                guard let token = allocation.token else { throw Self.identityFailure() }
                try releaseFreshAdoptionTokenLocked(token)
                try finishFreshAdoptionRelease(token)
            } else if let token = allocation.token {
                guard try !observeTemporalRegistryLocked().leases.contains(where: { $0.leaseID == token.leaseID }) else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
            }
            if let insertion = freshWriterPublications[ObjectIdentifier(allocation)] {
                try insertion.closeOwnedDescriptorsChecked()
                freshWriterPublications.removeValue(forKey: ObjectIdentifier(allocation))
            }
            try allocation.handle?.recordFreshAdoptionRelease(registry: self)
            allocation.freshDisposalCompletion = .init(token: allocation.token)
            try proof.requireDrained(registry: self, writerAllocation: allocation)
        }
        try proof.requireDrained(registry: self, writerAllocation: allocation)
    }
    @MainActor
    fileprivate func closeFreshAdoptionReader(_ allocation: GenerationLeaseAllocationAttemptV1,
        proof: EraseFreshAdoptionDrainWitnessV1) throws {
        guard allocation.registry === self, allocation.sealedForRetirement else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try proof.requireDrained(registry: self, readerAllocation: allocation)
        try allocation.requireFreshAdoptionDisposalEligibility()
        try withExclusiveGenerationMutationLock {
            try proof.requireDrained(registry: self, readerAllocation: allocation)
            guard temporalReaderAllocations[ObjectIdentifier(allocation)] == nil else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            if let completed = allocation.freshDisposalCompletion {
                guard freshReaderPublications[ObjectIdentifier(allocation)] == nil else { throw Self.identityFailure() }
                try requireFreshDisposalCompletionLocked(completed, token: allocation.token, handle: allocation.handle)
                return
            }
            if let retained = freshReaderPublications[ObjectIdentifier(allocation)], retained.closeUncertain {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            var published = allocation.handle != nil
            if let insertion = freshReaderPublications[ObjectIdentifier(allocation)]?.replacement {
                if insertion.renamed {
                    published = true
                    if allocation.handle == nil, freshAdoptionReleases[insertion.token.leaseID] == nil {
                        try finishTemporalReplacementLocked(insertion)
                    }
                } else { try abandonFreshAdoptionInsertionLocked(insertion) }
            }
            if published {
                guard let token = allocation.token else { throw Self.identityFailure() }
                try releaseFreshAdoptionTokenLocked(token)
                try finishFreshAdoptionRelease(token)
            } else if let token = allocation.token {
                guard try !observeTemporalRegistryLocked().leases.contains(where: { $0.leaseID == token.leaseID }) else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
            }
            if let insertion = freshReaderPublications[ObjectIdentifier(allocation)] {
                try insertion.closeOwnedDescriptorsChecked()
                freshReaderPublications.removeValue(forKey: ObjectIdentifier(allocation))
            }
            try allocation.handle?.recordFreshAdoptionRelease(registry: self)
            allocation.freshDisposalCompletion = .init(token: allocation.token)
            try proof.requireDrained(registry: self, readerAllocation: allocation)
        }
        try proof.requireDrained(registry: self, readerAllocation: allocation)
    }
}

/// Lexical G ownership, minted only by the fixed Registry executor. It cannot
/// outlive the synchronous mutation interval and accepts no caller callback.
@MainActor
final class TemporalNormalizationMutationScopeV1 {
    private let registry: GenerationLeaseRegistryV1
    private let activity: GenerationTemporalActivityHandleV1
    private var active = true
    fileprivate init(registry: GenerationLeaseRegistryV1, activity: GenerationTemporalActivityHandleV1) {
        self.registry = registry; self.activity = activity
    }
    fileprivate func revoke() { active = false }
    func require(registry expected: GenerationLeaseRegistryV1,
                 activity expectedActivity: GenerationTemporalActivityHandleV1) throws {
        guard active, registry === expected, activity === expectedActivity else {
            throw GenerationLeaseRegistryFailureV1.uncertainOwner
        }
        try activity.validateSharedNormalizationRegistry(registry)
        try registry.requireOriginalAbandonmentPolicyLocked()
    }
}

extension GenerationLeaseRegistryV1 {
    @MainActor
    func executeTemporalOriginalAbandonment(sourceSet: TemporalNormalizationRetainedSourceSetV1,
        activity: GenerationTemporalActivityHandleV1,
        originalAccess: TemporalNormalizationOriginalAccessScopeV1) throws -> OrphanFileCleanupSummary {
        try withTemporalNormalizationMutationLock(activity: activity) {
            try requireNoMigrationReservationLocked()
            try activity.validate(for: self, exclusive: true)
            let scope = TemporalNormalizationMutationScopeV1(registry: self, activity: activity)
            defer { scope.revoke() }
            return try sourceSet.publishOriginalAbandonment(mutationScope: scope, originalAccess: originalAccess)
        }
    }
}


extension GenerationLeaseRegistryV1 {
    /// Read-only effect preflight, called only through the actual lexical G
    /// scope. It never adopts pending registry/prune publication or repairs policy.
    fileprivate func requireOriginalAbandonmentPolicyLocked() throws {
        try verify()
        for name in [Self.registryTemporaryName, Self.pruneIntentName,
                     Self.pruneIntentTemporaryName, Self.pruneReceiptTemporaryName] {
            guard try !itemExistsLocked(name) else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        }
        let directories: [(URL, Int32, Identity)] = [
            (operationsURL, operationsDescriptor, operationsIdentity),
            (leaseURL, leaseDescriptor, leaseIdentity), (ownersURL, ownersDescriptor, ownersIdentity)]
        for (url, descriptor, expected) in directories {
            let policy = try ProtectedFilePolicyV1.observeTemporalPolicy(.generationLeaseDirectory, at: url)
            guard policy.state == .strictComplete,
                  policy.device == UInt64(expected.device), policy.inode == UInt64(expected.inode),
                  try Self.directoryIdentity(descriptor) == expected else { throw Self.identityFailure() }
        }
        for (url, descriptor, expected, kind) in [
            (leaseURL.appendingPathComponent(Self.mutationLockName), mutationLockDescriptor, mutationLockIdentity, OwnedFileKindV1.generationLeaseControl),
            (ownersURL.appendingPathComponent(Self.ownerLockName(ownerID)), ownerLockDescriptor, ownerLockIdentity, OwnedFileKindV1.generationLeaseOwnerLock)] {
            let policy = try ProtectedFilePolicyV1.observeTemporalPolicy(kind, at: url)
            guard policy.state == .strictComplete,
                  policy.device == UInt64(expected.device), policy.inode == UInt64(expected.inode),
                  try Self.regularFileIdentity(descriptor) == expected else { throw Self.identityFailure() }
        }
        let observed = try observeTemporalRegistryLocked()
        guard observed.registryPolicy.state == .strictComplete,
              observed.directoryPolicy.state == .strictComplete else { throw Self.identityFailure() }
        try verify()
    }
}


extension GenerationLeaseRegistryV1 {
    @MainActor
    fileprivate func publishPreparationReader(_ allocation: GenerationLeaseAllocationAttemptV1,
        operation: EraseRouterOperationV1) throws -> GenerationLeaseHandleV1 {
        guard allocation.registry === self else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try allocation.requirePreparationAcquiring(operation)
        let handle = try withExclusiveGenerationMutationLock {
            try allocation.requirePreparationAcquiring(operation)
            try requireNoMigrationReservationLocked()
            let observed = try observeTemporalRegistryLocked()
            try operation.requirePreparationLeaseCensus(observed.leases, registry: self)
            guard observed.leases.count < Self.maximumActiveLeaseCount else {
                throw GenerationLeaseRegistryFailureV1.registryLimitExceeded
            }
            let owners = Set(observed.leases.map(\.ownerID))
            guard owners.contains(ownerID) || owners.count < Self.maximumOwnerCount else {
                throw GenerationLeaseRegistryFailureV1.registryLimitExceeded
            }
            let token = try GenerationLeaseTokenV1(leaseID: makeLeaseID(), ownerID: ownerID,
                epoch: allocation.epoch, role: .reader, acquiredAt: now())
            guard !observed.leases.contains(where: { $0.leaseID == token.leaseID }), allocation.token == nil else {
                throw GenerationLeaseRegistryFailureV1.duplicateLease
            }
            allocation.token = token
            let record = FreshAdoptionReplacement(token: token)
            let id = ObjectIdentifier(allocation)
            guard preparationReaderPublications[id] == nil else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            preparationReaderPublications[id] = record
            try captureFreshAdoptionReplacementLocked(record, observed: observed,
                replacement: RegistryStateV1(leases: observed.leases + [token]))
            guard let attempt = record.replacement else { throw Self.identityFailure() }
            try finishTemporalReplacementLocked(attempt)
            let current = try observeTemporalRegistryLocked()
            try operation.requirePreparationLeaseCensus(current.leases, registry: self)
            guard current.leases.filter({ $0.leaseID == token.leaseID }) == [token] else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            let handle = try GenerationLeaseHandleV1(registry: self, publishedReaderToken: token)
            allocation.handle = handle // before outer G/post-admission can throw
            try allocation.requirePreparationAcquiring(operation)
            return handle
        }
        try allocation.requirePreparationAcquiring(operation)
        try withExclusiveGenerationMutationLock {
            try allocation.requirePreparationAcquiring(operation)
            guard let record = preparationReaderPublications[ObjectIdentifier(allocation)] else { throw Self.identityFailure() }
            let observed = try observeTemporalRegistryLocked()
            try operation.requirePreparationLeaseCensus(observed.leases, registry: self)
            guard observed.leases.filter({ $0.leaseID == handle.token.leaseID }) == [handle.token] else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try record.closeOwnedDescriptorsChecked()
            preparationReaderPublications.removeValue(forKey: ObjectIdentifier(allocation))
        }
        try allocation.requirePreparationAcquiring(operation)
        return handle
    }

    @MainActor
    fileprivate func closePreparationReader(_ allocation: GenerationLeaseAllocationAttemptV1,
        proof: ErasePreparationFailureDrainWitnessV1) throws {
        guard allocation.registry === self, allocation.sealedForRetirement else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try proof.requireDrained(registry: self, readerAllocation: allocation)
        try allocation.requirePreparationDisposalEligibility()
        try withExclusiveGenerationMutationLock {
            try proof.requireDrained(registry: self, readerAllocation: allocation)
            guard temporalReaderAllocations[ObjectIdentifier(allocation)] == nil else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            if let completed = allocation.freshDisposalCompletion {
                guard preparationReaderPublications[ObjectIdentifier(allocation)] == nil else { throw Self.identityFailure() }
                try requireFreshDisposalCompletionLocked(completed, token: allocation.token, handle: allocation.handle)
                return
            }
            if let retained = preparationReaderPublications[ObjectIdentifier(allocation)], retained.closeUncertain {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            var published = allocation.handle != nil
            if let insertion = preparationReaderPublications[ObjectIdentifier(allocation)]?.replacement {
                if insertion.renamed {
                    published = true
                    if allocation.handle == nil, freshAdoptionReleases[insertion.token.leaseID] == nil {
                        try finishTemporalReplacementLocked(insertion)
                    }
                } else { try abandonFreshAdoptionInsertionLocked(insertion) }
            }
            if published {
                guard let token = allocation.token else { throw Self.identityFailure() }
                try releaseFreshAdoptionTokenLocked(token)
                try finishFreshAdoptionRelease(token)
            } else if let token = allocation.token {
                guard try !observeTemporalRegistryLocked().leases.contains(where: { $0.leaseID == token.leaseID }) else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
            }
            if let insertion = preparationReaderPublications[ObjectIdentifier(allocation)] {
                try insertion.closeOwnedDescriptorsChecked()
                preparationReaderPublications.removeValue(forKey: ObjectIdentifier(allocation))
            }
            try allocation.handle?.recordFreshAdoptionRelease(registry: self)
            allocation.freshDisposalCompletion = .init(token: allocation.token)
            try proof.requireDrained(registry: self, readerAllocation: allocation)
        }
        try proof.requireDrained(registry: self, readerAllocation: allocation)
    }

    @MainActor
    fileprivate func publishPreparationWriter(_ allocation: GenerationWriterAllocationAttemptV1,
        operation: EraseRouterOperationV1) throws -> GenerationLeaseHandleV1 {
        guard allocation.registry === self else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try allocation.requirePreparationAcquiring(operation)
        let handle = try withExclusiveGenerationMutationLock {
            try allocation.requirePreparationAcquiring(operation)
            try requireNoMigrationReservationLocked()
            let observed = try observeTemporalRegistryLocked()
            try operation.requirePreparationLeaseCensus(observed.leases, registry: self)
            guard observed.leases.count < Self.maximumActiveLeaseCount else {
                throw GenerationLeaseRegistryFailureV1.registryLimitExceeded
            }
            let owners = Set(observed.leases.map(\.ownerID))
            guard owners.contains(ownerID) || owners.count < Self.maximumOwnerCount else {
                throw GenerationLeaseRegistryFailureV1.registryLimitExceeded
            }
            let token = try GenerationLeaseTokenV1(leaseID: makeLeaseID(), ownerID: ownerID,
                epoch: allocation.generationEpoch, role: .writer, acquiredAt: now())
            guard !observed.leases.contains(where: { $0.leaseID == token.leaseID }), allocation.token == nil else {
                throw GenerationLeaseRegistryFailureV1.duplicateLease
            }
            allocation.token = token
            let record = FreshAdoptionReplacement(token: token)
            let id = ObjectIdentifier(allocation)
            guard preparationWriterPublications[id] == nil else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            preparationWriterPublications[id] = record
            try captureFreshAdoptionReplacementLocked(record, observed: observed,
                replacement: RegistryStateV1(leases: observed.leases + [token]))
            guard let attempt = record.replacement else { throw Self.identityFailure() }
            try finishTemporalReplacementLocked(attempt)
            let current = try observeTemporalRegistryLocked()
            try operation.requirePreparationLeaseCensus(current.leases, registry: self)
            guard current.leases.filter({ $0.leaseID == token.leaseID }) == [token] else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            let handle = try GenerationLeaseHandleV1(registry: self, publishedWriterToken: token)
            allocation.handle = handle // before outer G/post-admission can throw
            try allocation.requirePreparationAcquiring(operation)
            return handle
        }
        try allocation.requirePreparationAcquiring(operation)
        try withExclusiveGenerationMutationLock {
            try allocation.requirePreparationAcquiring(operation)
            guard let record = preparationWriterPublications[ObjectIdentifier(allocation)] else { throw Self.identityFailure() }
            let observed = try observeTemporalRegistryLocked()
            try operation.requirePreparationLeaseCensus(observed.leases, registry: self)
            guard observed.leases.filter({ $0.leaseID == handle.token.leaseID }) == [handle.token] else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try record.closeOwnedDescriptorsChecked()
            preparationWriterPublications.removeValue(forKey: ObjectIdentifier(allocation))
        }
        try allocation.requirePreparationAcquiring(operation)
        return handle
    }

    @MainActor
    fileprivate func closePreparationWriter(_ allocation: GenerationWriterAllocationAttemptV1,
        proof: ErasePreparationFailureDrainWitnessV1) throws {
        guard allocation.registry === self, allocation.sealedForRetirement else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try allocation.requirePreparationDisposalEligibility()
        try proof.requireDrained(registry: self, writerAllocation: allocation)
        try withExclusiveGenerationMutationLock {
            try proof.requireDrained(registry: self, writerAllocation: allocation)
            if let completed = allocation.freshDisposalCompletion {
                guard preparationWriterPublications[ObjectIdentifier(allocation)] == nil else { throw Self.identityFailure() }
                try requireFreshDisposalCompletionLocked(completed, token: allocation.token, handle: allocation.handle)
                return
            }
            if let retained = preparationWriterPublications[ObjectIdentifier(allocation)], retained.closeUncertain {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            var published = allocation.handle != nil
            if let insertion = preparationWriterPublications[ObjectIdentifier(allocation)]?.replacement {
                if insertion.renamed {
                    published = true
                    if allocation.handle == nil, freshAdoptionReleases[insertion.token.leaseID] == nil {
                        try finishTemporalReplacementLocked(insertion)
                    }
                } else { try abandonFreshAdoptionInsertionLocked(insertion) }
            }
            if published {
                guard let token = allocation.token else { throw Self.identityFailure() }
                try releaseFreshAdoptionTokenLocked(token)
                try finishFreshAdoptionRelease(token)
            } else if let token = allocation.token {
                guard try !observeTemporalRegistryLocked().leases.contains(where: { $0.leaseID == token.leaseID }) else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
            }
            if let insertion = preparationWriterPublications[ObjectIdentifier(allocation)] {
                try insertion.closeOwnedDescriptorsChecked()
                preparationWriterPublications.removeValue(forKey: ObjectIdentifier(allocation))
            }
            try allocation.handle?.recordFreshAdoptionRelease(registry: self)
            allocation.freshDisposalCompletion = .init(token: allocation.token)
            try proof.requireDrained(registry: self, writerAllocation: allocation)
        }
        try proof.requireDrained(registry: self, writerAllocation: allocation)
    }
}

extension GenerationLeaseRegistryV1 {
    @MainActor
    fileprivate func preparationPublishedToken(reader: GenerationLeaseAllocationAttemptV1) -> GenerationLeaseTokenV1? {
        guard reader.registry === self else { return nil }
        if let handle = reader.handle { return handle.token }
        guard preparationReaderPublications[ObjectIdentifier(reader)]?.replacement?.renamed == true else { return nil }
        return reader.token
    }
    @MainActor
    fileprivate func preparationPublishedToken(writer: GenerationWriterAllocationAttemptV1) -> GenerationLeaseTokenV1? {
        guard writer.registry === self else { return nil }
        if let handle = writer.handle { return handle.token }
        guard preparationWriterPublications[ObjectIdentifier(writer)]?.replacement?.renamed == true else { return nil }
        return writer.token
    }
}

// Distinct genuine startup preparation ownership; never a borrowed Erase ticket.
extension GenerationLeaseRegistryV1 {
    @MainActor
    fileprivate func publishColdPreparationReader(_ allocation: GenerationLeaseAllocationAttemptV1,
        operation: EraseColdPreparationOperationV1) throws -> GenerationLeaseHandleV1 {
        guard allocation.registry === self else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try allocation.requireColdPreparationAcquiring(operation)
        let handle = try withExclusiveGenerationMutationLock {
            try allocation.requireColdPreparationAcquiring(operation)
            try requireNoMigrationReservationLocked()
            let observed = try observeTemporalRegistryLocked()
            guard observed.leases.allSatisfy({ $0.role == .reader }) else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            try operation.requireColdPreparationLeaseCensus(observed.leases, registry: self)
            guard observed.leases.count < Self.maximumActiveLeaseCount else {
                throw GenerationLeaseRegistryFailureV1.registryLimitExceeded
            }
            let owners = Set(observed.leases.map(\.ownerID))
            guard owners.contains(ownerID) || owners.count < Self.maximumOwnerCount else {
                throw GenerationLeaseRegistryFailureV1.registryLimitExceeded
            }
            let token = try GenerationLeaseTokenV1(leaseID: makeLeaseID(), ownerID: ownerID,
                epoch: allocation.epoch, role: .reader, acquiredAt: now())
            guard !observed.leases.contains(where: { $0.leaseID == token.leaseID }), allocation.token == nil else {
                throw GenerationLeaseRegistryFailureV1.duplicateLease
            }
            allocation.token = token
            let record = FreshAdoptionReplacement(token: token)
            let id = ObjectIdentifier(allocation)
            guard coldPreparationReaderPublications[id] == nil else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            coldPreparationReaderPublications[id] = record
            try captureFreshAdoptionReplacementLocked(record, observed: observed,
                replacement: RegistryStateV1(leases: observed.leases + [token]))
            guard let attempt = record.replacement else { throw Self.identityFailure() }
            try finishTemporalReplacementLocked(attempt)
            let current = try observeTemporalRegistryLocked()
            guard current.leases.allSatisfy({ $0.role == .reader }) else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            try operation.requireColdPreparationLeaseCensus(current.leases, registry: self)
            guard current.leases.filter({ $0.leaseID == token.leaseID }) == [token] else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            let handle = try GenerationLeaseHandleV1(registry: self, publishedReaderToken: token)
            allocation.handle = handle // before outer G/post-admission can throw
            try allocation.requireColdPreparationAcquiring(operation)
            return handle
        }
        try allocation.requireColdPreparationAcquiring(operation)
        try withExclusiveGenerationMutationLock {
            try allocation.requireColdPreparationAcquiring(operation)
            guard let record = coldPreparationReaderPublications[ObjectIdentifier(allocation)] else { throw Self.identityFailure() }
            let observed = try observeTemporalRegistryLocked()
            guard observed.leases.allSatisfy({ $0.role == .reader }) else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
            try operation.requireColdPreparationLeaseCensus(observed.leases, registry: self)
            guard observed.leases.filter({ $0.leaseID == handle.token.leaseID }) == [handle.token] else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            try record.closeOwnedDescriptorsChecked()
            coldPreparationReaderPublications.removeValue(forKey: ObjectIdentifier(allocation))
        }
        try allocation.requireColdPreparationAcquiring(operation)
        return handle
    }

    @MainActor
    fileprivate func closeColdPreparationReader(_ allocation: GenerationLeaseAllocationAttemptV1,
        proof: EraseColdPreparationFailureDrainWitnessV1) throws {
        guard allocation.registry === self, allocation.sealedForRetirement else { throw GenerationLeaseRegistryFailureV1.uncertainOwner }
        try proof.requireDrained(registry: self, readerAllocation: allocation)
        try allocation.requireColdPreparationDisposalEligibility()
        try withExclusiveGenerationMutationLock {
            try proof.requireDrained(registry: self, readerAllocation: allocation)
            guard temporalReaderAllocations[ObjectIdentifier(allocation)] == nil else {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            if let completed = allocation.freshDisposalCompletion {
                guard coldPreparationReaderPublications[ObjectIdentifier(allocation)] == nil else { throw Self.identityFailure() }
                try requireFreshDisposalCompletionLocked(completed, token: allocation.token, handle: allocation.handle)
                return
            }
            if let retained = coldPreparationReaderPublications[ObjectIdentifier(allocation)], retained.closeUncertain {
                throw GenerationLeaseRegistryFailureV1.uncertainOwner
            }
            var published = allocation.handle != nil
            if let insertion = coldPreparationReaderPublications[ObjectIdentifier(allocation)]?.replacement {
                if insertion.renamed {
                    published = true
                    if allocation.handle == nil, freshAdoptionReleases[insertion.token.leaseID] == nil {
                        try finishTemporalReplacementLocked(insertion)
                    }
                } else { try abandonFreshAdoptionInsertionLocked(insertion) }
            }
            if published {
                guard let token = allocation.token else { throw Self.identityFailure() }
                try releaseFreshAdoptionTokenLocked(token)
                try finishFreshAdoptionRelease(token)
            } else if let token = allocation.token {
                guard try !observeTemporalRegistryLocked().leases.contains(where: { $0.leaseID == token.leaseID }) else {
                    throw GenerationLeaseRegistryFailureV1.uncertainOwner
                }
            }
            if let insertion = coldPreparationReaderPublications[ObjectIdentifier(allocation)] {
                try insertion.closeOwnedDescriptorsChecked()
                coldPreparationReaderPublications.removeValue(forKey: ObjectIdentifier(allocation))
            }
            try allocation.handle?.recordFreshAdoptionRelease(registry: self)
            allocation.freshDisposalCompletion = .init(token: allocation.token)
            try proof.requireDrained(registry: self, readerAllocation: allocation)
        }
        try proof.requireDrained(registry: self, readerAllocation: allocation)
    }

}

extension GenerationLeaseRegistryV1 {
    @MainActor
    fileprivate func coldPreparationPublishedToken(reader: GenerationLeaseAllocationAttemptV1) -> GenerationLeaseTokenV1? {
        guard reader.registry === self else { return nil }
        if let handle = reader.handle { return handle.token }
        guard coldPreparationReaderPublications[ObjectIdentifier(reader)]?.replacement?.renamed == true else { return nil }
        return reader.token
    }
}

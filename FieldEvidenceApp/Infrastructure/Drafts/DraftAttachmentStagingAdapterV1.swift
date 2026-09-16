import CryptoKit
import Darwin
import Foundation

/// Each acquisition opens a distinct file description, including acquisitions
/// from other adapter instances. No lock is retained across an actor hop.
fileprivate final class DraftStagingRootOwnerV1: @unchecked Sendable {
    let rootURL: URL
    let descriptor: Int32
    private let identity: stat

    init(rootURL: URL) throws {
        guard rootURL.isFileURL, !rootURL.path.utf8.contains(0) else {
            throw DraftAttachmentStagingFailureV1.invalidRoot
        }
        self.rootURL = rootURL
        descriptor = open(rootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw DraftAttachmentStagingFailureV1.unsafePath }
        var value = stat()
        guard fstat(descriptor, &value) == 0 else {
            close(descriptor); throw DraftAttachmentStagingFailureV1.unsafePath
        }
        identity = value
    }
    deinit { close(descriptor) }

    final class Lock {
        private var descriptor: Int32
        init(_ descriptor: Int32) { self.descriptor = descriptor }
        func release() {
            if descriptor >= 0 { flock(descriptor, LOCK_UN); close(descriptor); descriptor = -1 }
        }
        deinit { release() }
    }
    func acquire() throws -> Lock {
        let fd = open(rootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw DraftAttachmentStagingFailureV1.unsafePath }
        var value = stat()
        guard fstat(fd, &value) == 0, value.st_dev == identity.st_dev, value.st_ino == identity.st_ino,
              flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd); throw DraftAttachmentStagingFailureV1.staleStage
        }
        return Lock(fd)
    }
    func requireNamedRoot() throws {
        var named = stat()
        guard lstat(rootURL.path, &named) == 0, named.st_mode & S_IFMT == S_IFDIR,
              named.st_dev == identity.st_dev, named.st_ino == identity.st_ino else {
            throw DraftAttachmentStagingFailureV1.staleStage
        }
    }
    final class Directory {
        let descriptor: Int32
        let components: [String]
        let owner: DraftStagingRootOwnerV1
        let identity: stat
        var url: URL { components.reduce(owner.rootURL) { $0.appendingPathComponent($1, isDirectory: true) } }
        init(descriptor: Int32, components: [String], owner: DraftStagingRootOwnerV1) throws {
            self.descriptor = descriptor; self.components = components; self.owner = owner
            var value = stat()
            guard fstat(descriptor, &value) == 0, value.st_mode & S_IFMT == S_IFDIR else {
                close(descriptor); throw DraftAttachmentStagingFailureV1.unsafePath
            }
            identity = value
        }
        deinit { close(descriptor) }
        func verifyNamed() throws {
            let current = try owner.directory(components)
            guard current.identity.st_dev == identity.st_dev, current.identity.st_ino == identity.st_ino else {
                throw DraftAttachmentStagingFailureV1.staleStage
            }
        }
        func exists(_ name: String) throws -> Bool {
            try DraftStagingRootOwnerV1.component(name)
            var value = stat()
            if fstatat(descriptor, name, &value, AT_SYMLINK_NOFOLLOW) == 0 { return true }
            guard errno == ENOENT else { throw DraftAttachmentStagingFailureV1.unsafePath }
            return false
        }
        func openFile(_ name: String) throws -> Int32 {
            try DraftStagingRootOwnerV1.component(name)
            let fd = openat(descriptor, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw DraftAttachmentStagingFailureV1.stageNotFound }
            do { _ = try DraftStagingRootOwnerV1.regular(fd); return fd }
            catch { close(fd); throw error }
        }
        func names() throws -> Set<String> {
            try verifyNamed()
            let duplicate = openat(descriptor, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard duplicate >= 0 else { throw DraftAttachmentStagingFailureV1.unsafePath }
            guard let stream = fdopendir(duplicate) else {
                close(duplicate); throw DraftAttachmentStagingFailureV1.unsafePath
            }
            defer { closedir(stream) }
            var result = Set<String>()
            errno = 0
            while let entry = readdir(stream) {
                let capacity = MemoryLayout.size(ofValue: entry.pointee.d_name)
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: capacity) {
                        String(cString: $0)
                    }
                }
                if name != "." && name != ".." {
                    try DraftStagingRootOwnerV1.component(name)
                    guard result.insert(name).inserted else { throw DraftAttachmentStagingFailureV1.unsafePath }
                }
                errno = 0
            }
            guard errno == 0 else { throw DraftAttachmentStagingFailureV1.unsafePath }
            try verifyNamed()
            return result
        }
        func verifyFile(_ fd: Int32, name: String) throws {
            let opened = try openFile(name)
            defer { close(opened) }
            let a = try DraftStagingRootOwnerV1.regular(fd), b = try DraftStagingRootOwnerV1.regular(opened)
            guard a.st_dev == b.st_dev, a.st_ino == b.st_ino else {
                throw DraftAttachmentStagingFailureV1.staleStage
            }
        }

        /// A retained, previously admitted file is stale when its named
        /// binding is lost. Initial open/type admission keeps its own errors.
        func verifyPinnedFile(_ fd: Int32, name: String, facts: stat) throws {
            try DraftStagingRootOwnerV1.component(name)
            try DraftStagingRootOwnerV1.unchanged(fd, facts)
            let current = openat(descriptor, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            guard current >= 0 else { throw DraftAttachmentStagingFailureV1.staleStage }
            defer { close(current) }
            try DraftStagingRootOwnerV1.unchanged(current, facts)
            try verifyNamed()
            try DraftStagingRootOwnerV1.unchanged(fd, facts)
        }
    }
    static func component(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"),
              !name.utf8.contains(0) else { throw DraftAttachmentStagingFailureV1.unsafePath }
    }
    func directory(_ components: [String], create: Bool = false) throws -> Directory {
        try requireNamedRoot()
        var current = dup(descriptor)
        guard current >= 0 else { throw DraftAttachmentStagingFailureV1.unsafePath }
        do {
            for component in components {
                try Self.component(component)
                if create {
                    guard mkdirat(current, component, mode_t(0o700)) == 0 || errno == EEXIST else {
                        throw DraftAttachmentStagingFailureV1.cleanupFailed
                    }
                }
                let next = openat(current, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw DraftAttachmentStagingFailureV1.unsafePath }
                close(current); current = next
            }
            // Directory owns the descriptor after construction, including failure.
            let owned = current; current = -1
            return try Directory(descriptor: owned, components: components, owner: self)
        } catch { if current >= 0 { close(current) }; throw error }
    }
    final class ManifestSnapshot {
        let descriptor: Int32
        let facts: stat
        let manifest: DraftAttachmentStagingManifestV1
        init(owner: DraftStagingRootOwnerV1) throws {
            let fd = openat(owner.descriptor, DraftAttachmentStagingAdapterV1.manifestName,
                                O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw DraftAttachmentStagingFailureV1.corruptManifest }
            do {
                let facts = try DraftStagingRootOwnerV1.regular(fd)
                guard facts.st_size > 0, facts.st_size <= Int64(FieldDraftLimitsV1.maximumCanonicalBytes),
                      let count = Int(exactly: facts.st_size) else {
                    throw DraftAttachmentStagingFailureV1.corruptManifest
                }
                let bytes = try DraftStagingRootOwnerV1.read(fd, count: count)
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
                let manifest = try decoder.decode(DraftAttachmentStagingManifestV1.self, from: bytes)
                try manifest.validate()
                try DraftStagingRootOwnerV1.unchanged(fd, facts)
                try owner.directory([]).verifyFile(fd, name: DraftAttachmentStagingAdapterV1.manifestName)
                try ProtectedFilePolicyV1.verify(.stagingFile, at: owner.rootURL.appendingPathComponent(
                    DraftAttachmentStagingAdapterV1.manifestName))
                self.descriptor = fd; self.facts = facts; self.manifest = manifest
            } catch { close(fd); throw error }
        }
        deinit { close(descriptor) }
        func requireCurrent(_ owner: DraftStagingRootOwnerV1) throws {
            try owner.directory([]).verifyPinnedFile(descriptor,
                name: DraftAttachmentStagingAdapterV1.manifestName, facts: facts)
        }
    }
    static func pathExists(_ url: URL) -> Bool {
        var value = stat()
        return lstat(url.path, &value) == 0 || errno != ENOENT
    }
    static func regular(_ fd: Int32) throws -> stat {
        var value = stat()
        guard fstat(fd, &value) == 0, value.st_mode & S_IFMT == S_IFREG, value.st_nlink == 1 else {
            throw DraftAttachmentStagingFailureV1.unsafePath
        }
        return value
    }
    static func unchanged(_ fd: Int32, _ prior: stat) throws {
        var now = stat()
        guard fstat(fd, &now) == 0, now.st_mode & S_IFMT == S_IFREG, now.st_nlink == 1,
              now.st_dev == prior.st_dev, now.st_ino == prior.st_ino, now.st_size == prior.st_size,
              now.st_mtimespec.tv_sec == prior.st_mtimespec.tv_sec,
              now.st_mtimespec.tv_nsec == prior.st_mtimespec.tv_nsec,
              now.st_ctimespec.tv_sec == prior.st_ctimespec.tv_sec,
              now.st_ctimespec.tv_nsec == prior.st_ctimespec.tv_nsec else {
            throw DraftAttachmentStagingFailureV1.staleStage
        }
    }
    static func read(_ fd: Int32, count: Int) throws -> Data {
        var result = Data(count: count)
        try result.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < count {
                let size = pread(fd, buffer.baseAddress!.advanced(by: offset), count - offset, off_t(offset))
                guard size > 0 else { throw DraftAttachmentStagingFailureV1.byteLengthMismatch }
                offset += size
            }
        }
        return result
    }
    static func write(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < data.count {
                let size = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), data.count - offset)
                guard size > 0 else { throw DraftAttachmentStagingFailureV1.insufficientStorage }
                offset += size
            }
        }
    }
    /// Protect and sync the private inode before replacement; never modify a
    /// manifest inode in place, because prepared operations retain its facts.
    static func replaceFile(_ data: Data, at url: URL, directory anchored: Directory) throws {
        let directory = url.deletingLastPathComponent()
        try anchored.verifyNamed()
        guard directory.standardizedFileURL == anchored.url.standardizedFileURL else {
            throw DraftAttachmentStagingFailureV1.unsafePath
        }
        let parent = dup(anchored.descriptor)
        guard parent >= 0 else { throw DraftAttachmentStagingFailureV1.unsafePath }
        defer { close(parent) }
        let name = ".manifest-\(UUID().uuidString.lowercased())"
        let fd = openat(parent, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw DraftAttachmentStagingFailureV1.cleanupFailed }
        defer {
            var opened = stat(), named = stat()
            if fstat(fd, &opened) == 0, fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
               opened.st_dev == named.st_dev, opened.st_ino == named.st_ino { unlinkat(parent, name, 0) }
            close(fd)
        }
        try write(data, to: fd)
        try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, relativePath: name, within: directory,
            authorityCheck: {
                try anchored.verifyNamed()
                try anchored.verifyFile(fd, name: name)
            })
        let written = try regular(fd)
        var named = stat(), namedParent = stat(), openedParent = stat()
        guard fstat(parent, &openedParent) == 0, lstat(directory.path, &namedParent) == 0,
              openedParent.st_dev == namedParent.st_dev, openedParent.st_ino == namedParent.st_ino,
              fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              named.st_dev == written.st_dev, named.st_ino == written.st_ino else {
            throw DraftAttachmentStagingFailureV1.unsafePath
        }
        guard fsync(fd) == 0, renameat(parent, name, parent, url.lastPathComponent) == 0,
              fsync(parent) == 0 else { throw DraftAttachmentStagingFailureV1.cleanupFailed }
    }
}

/// Only the adapter can construct this physical operation. The application's
/// retained publication authority consumes it once, synchronously under G then R.
/// File descriptors and raw bytes remain private to this operation.
final class DraftPreparedRawPhotoPublicationV1: @unchecked Sendable {
    let rawReady: CheckRunnerPhotoRawReadyV1
    let applicationSupportURL: URL
    let adapterIdentity: ObjectIdentifier
    private let owner: DraftStagingRootOwnerV1
    private let parent: DraftStagingRootOwnerV1.Directory
    private let directory: DraftStagingRootOwnerV1.Directory
    private let base: DraftStagingRootOwnerV1.ManifestSnapshot
    private let payloadDescriptor: Int32
    private let payloadFacts: stat
    private let witnessDescriptor: Int32
    private let witnessFacts: stat
    private let candidateBytes: Data
    private let candidateManifest: DraftAttachmentStagingManifestV1
    private let finalName: String
    private let privateName: String?
    private let consumption = NSLock()
    private var consumed = false
    private var directoryVisible: Bool

    private init(rawReady: CheckRunnerPhotoRawReadyV1, applicationSupportURL: URL,
        adapterIdentity: ObjectIdentifier, owner: DraftStagingRootOwnerV1,
        parent: DraftStagingRootOwnerV1.Directory, directory: DraftStagingRootOwnerV1.Directory,
        base: DraftStagingRootOwnerV1.ManifestSnapshot, payloadDescriptor: Int32, payloadFacts: stat,
        witnessDescriptor: Int32, witnessFacts: stat, candidateManifest: DraftAttachmentStagingManifestV1,
        candidateBytes: Data, finalName: String, privateName: String?) {
        self.rawReady = rawReady; self.applicationSupportURL = applicationSupportURL
        self.adapterIdentity = adapterIdentity; self.owner = owner; self.parent = parent
        self.directory = directory; self.base = base; self.payloadDescriptor = payloadDescriptor
        self.payloadFacts = payloadFacts; self.witnessDescriptor = witnessDescriptor
        self.witnessFacts = witnessFacts; self.candidateManifest = candidateManifest
        self.candidateBytes = candidateBytes; self.finalName = finalName; self.privateName = privateName
        directoryVisible = privateName == nil
    }

    deinit {
        // A failed canonical transaction leaves visible bytes available for
        // exact adoption. Only our still-private, identity-proven inode is removed.
        if !directoryVisible, let privateName, let lock = try? owner.acquire() {
            Self.removePrivate(owner: owner, directory: directory, name: privateName,
                payloadIdentity: payloadFacts, witnessIdentity: witnessFacts)
            lock.release()
        }
        close(payloadDescriptor); close(witnessDescriptor)
    }

    func withPublicationLock<T>(_ body: (_ publish: () throws -> Void) throws -> T) throws -> T {
        guard consumption.try() else { throw DraftAttachmentStagingFailureV1.staleStage }
        defer { consumption.unlock() }
        guard !consumed else { throw DraftAttachmentStagingFailureV1.staleStage }
        consumed = true
        let lock = try owner.acquire()
        defer { lock.release() }
        try base.requireCurrent(owner)
        try parent.verifyNamed()
        try directory.verifyNamed()
        try directory.verifyPinnedFile(payloadDescriptor,
            name: DraftAttachmentStagingAdapterV1.payloadName, facts: payloadFacts)
        try directory.verifyPinnedFile(witnessDescriptor, name: Self.witnessName, facts: witnessFacts)
        try DraftStagingRootOwnerV1.unchanged(payloadDescriptor, payloadFacts)
        try DraftStagingRootOwnerV1.unchanged(witnessDescriptor, witnessFacts)
        if privateName != nil, try parent.exists(finalName) {
            throw DraftAttachmentStagingFailureV1.stageAlreadyExists
        }
        var published = false
        let result = try body {
            guard !published else { throw DraftAttachmentStagingFailureV1.invalidTransition }
            // This closure cannot escape. No await or caller-owned byte work
            // separates physical publication from the authority's canonical write.
            try self.base.requireCurrent(self.owner)
            try self.parent.verifyNamed()
            try self.directory.verifyNamed()
            try DraftStagingRootOwnerV1.unchanged(self.payloadDescriptor, self.payloadFacts)
            try DraftStagingRootOwnerV1.unchanged(self.witnessDescriptor, self.witnessFacts)
            if let privateName = self.privateName {
                guard renameatx_np(self.owner.descriptor, privateName,
                    self.parent.descriptor, self.finalName, UInt32(RENAME_EXCL)) == 0 else {
                    throw DraftAttachmentStagingFailureV1.stageAlreadyExists
                }
                // Mark immediately: later fsync/manifest/canonical failures must
                // never delete the now-visible directory.
                self.directoryVisible = true
            }
            // Adoption also completes a prior interrupted directory fsync.
            guard fsync(self.parent.descriptor) == 0, fsync(self.owner.descriptor) == 0 else {
                throw DraftAttachmentStagingFailureV1.cleanupFailed
            }
            if self.base.manifest != self.candidateManifest {
                try DraftStagingRootOwnerV1.replaceFile(self.candidateBytes,
                    at: self.owner.rootURL.appendingPathComponent(DraftAttachmentStagingAdapterV1.manifestName),
                    directory: self.owner.directory([]))
            }
            let readBack = try DraftStagingRootOwnerV1.ManifestSnapshot(owner: self.owner).manifest
            guard try readBack.canonicalBytes() == self.candidateBytes else {
                throw DraftAttachmentStagingFailureV1.corruptManifest
            }
            let visible = try self.owner.directory(self.parent.components + [self.finalName])
            guard visible.identity.st_dev == self.directory.identity.st_dev,
                  visible.identity.st_ino == self.directory.identity.st_ino else {
                throw DraftAttachmentStagingFailureV1.staleStage
            }
            try visible.verifyPinnedFile(self.payloadDescriptor,
                name: DraftAttachmentStagingAdapterV1.payloadName, facts: self.payloadFacts)
            try visible.verifyPinnedFile(self.witnessDescriptor,
                name: Self.witnessName, facts: self.witnessFacts)
            published = true
        }
        guard published else { throw DraftAttachmentStagingFailureV1.invalidTransition }
        return result
    }

    private static let witnessName = "raw-publication.json"

    fileprivate static func prepare(sourceURL: URL?, payload: CheckRunnerPhotoDraftPayloadV1,
        publishedRawReady: CheckRunnerPhotoRawReadyV1?, applicationSupportURL: URL,
        adapterIdentity: ObjectIdentifier, owner: DraftStagingRootOwnerV1) throws
        -> DraftPreparedRawPhotoPublicationV1? {
        try Task.checkCancellation()
        try payload.validate()
        guard case .awaitingRawStage = payload.phase else {
            throw DraftAttachmentStagingFailureV1.invalidTransition
        }
        let intent = payload.phase.intent
        let path = DraftAttachmentStagingAdapterV1.relativeStageDirectory(
            draftID: payload.childDraftID, stageID: intent.stageID).split(separator: "/").map(String.init)
        let lock = try owner.acquire()
        var lockHeld = true
        defer { if lockHeld { lock.release() } }
        let base = try DraftStagingRootOwnerV1.ManifestSnapshot(owner: owner)
        if sourceURL == nil, try !owner.directory([]).exists(path[0]) {
            guard publishedRawReady == nil,
                  !base.manifest.entries.contains(where: { $0.item.stageID == intent.stageID }) else {
                throw DraftAttachmentStagingFailureV1.staleStage
            }
            return nil
        }
        let parent = try owner.directory([path[0]], create: sourceURL != nil && publishedRawReady == nil)
        if sourceURL == nil { try ProtectedFilePolicyV1.verify(.stagingDirectory, at: parent.url) }
        else { try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: parent.url) }
        try parent.verifyNamed()
        let existing = try parent.exists(path[1])
        if publishedRawReady != nil, !existing {
            throw DraftAttachmentStagingFailureV1.stageNotFound
        }
        if sourceURL == nil, !existing {
            guard !base.manifest.entries.contains(where: { $0.item.stageID == intent.stageID }) else {
                throw DraftAttachmentStagingFailureV1.staleStage
            }
            return nil
        }
        let directory: DraftStagingRootOwnerV1.Directory
        let privateName: String?
        let existingWitness: CheckRunnerPhotoRawReadyV1?
        var payloadFD: Int32 = -1
        var witnessFD: Int32 = -1
        var ownedPayload: stat?
        var ownedWitness: stat?
        var originalWitnessFacts: stat?
        var transferred = false
        if existing {
            privateName = nil
            directory = try owner.directory(path)
            witnessFD = try directory.openFile(witnessName)
            do {
                let facts = try DraftStagingRootOwnerV1.regular(witnessFD)
                guard facts.st_size > 0, facts.st_size <= Int64(FieldDraftLimitsV1.maximumCanonicalBytes) else {
                    throw DraftAttachmentStagingFailureV1.corruptManifest
                }
                existingWitness = try FieldDraftCanonicalCodecV1.decode(CheckRunnerPhotoRawReadyV1.self,
                    from: DraftStagingRootOwnerV1.read(witnessFD, count: Int(facts.st_size)))
                try DraftStagingRootOwnerV1.unchanged(witnessFD, facts)
                originalWitnessFacts = facts
                guard let witness = existingWitness,
                      witness.intent == intent, witness.readyItem.workspaceID == payload.workspaceID,
                      witness.readyItem.draftID == payload.childDraftID,
                      witness.originalProvenance.origin == payload.origin,
                      publishedRawReady == nil || publishedRawReady == witness else {
                    throw DraftAttachmentStagingFailureV1.staleStage
                }
                payloadFD = try directory.openFile(DraftAttachmentStagingAdapterV1.payloadName)
                try ProtectedFilePolicyV1.verify(.stagingFile, at: directory.url.appendingPathComponent(witnessName))
                try ProtectedFilePolicyV1.verify(.stagingFile,
                    at: directory.url.appendingPathComponent(DraftAttachmentStagingAdapterV1.payloadName))
            } catch { close(witnessFD); if payloadFD >= 0 { close(payloadFD) }; throw error }
        } else {
            guard !base.manifest.entries.contains(where: { $0.item.stageID == intent.stageID }) else {
                throw DraftAttachmentStagingFailureV1.staleStage
            }
            existingWitness = nil
            let name = ".raw-private-\(UUID().uuidString.lowercased())"
            guard mkdirat(owner.descriptor, name, mode_t(0o700)) == 0 else {
                throw DraftAttachmentStagingFailureV1.cleanupFailed
            }
            privateName = name
            // A failed open supplies no descriptor proof for cleanup.
            directory = try owner.directory([name])
        }
        defer {
            if !transferred {
                if payloadFD >= 0 { close(payloadFD) }
                if witnessFD >= 0 { close(witnessFD) }
                if let privateName {
                    // We have not published any directory. An independent owner
                    // cannot address this private name through the generic API.
                    if lockHeld { removePrivate(owner: owner, directory: directory, name: privateName,
                        payloadIdentity: ownedPayload, witnessIdentity: ownedWitness) }
                    else if let cleanupLock = try? owner.acquire() {
                        removePrivate(owner: owner, directory: directory, name: privateName,
                            payloadIdentity: ownedPayload, witnessIdentity: ownedWitness)
                        cleanupLock.release()
                    }
                }
            }
        }
        if existing { try ProtectedFilePolicyV1.verify(.stagingDirectory, at: directory.url) }
        else { try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: directory.url) }
        try directory.verifyNamed()
        lock.release(); lockHeld = false
        // Existing publication wins before sourceURL is even inspected/opened.
        var copiedDigest: ContentDigestV1?
        if !existing {
            guard let sourceURL else { throw DraftAttachmentStagingFailureV1.stageNotFound }
            let copied = try copySource(sourceURL, expectedCount: intent.expectedSourceByteCount,
                into: directory, ownedIdentity: &ownedPayload)
            payloadFD = copied.descriptor; copiedDigest = copied.digest
        }
        let initialFacts = try DraftStagingRootOwnerV1.regular(payloadFD)
        guard initialFacts.st_size == intent.expectedSourceByteCount,
              initialFacts.st_size > 0, initialFacts.st_size <= Int64(MediaContractV1.sourceByteCountMaximum) else {
            throw DraftAttachmentStagingFailureV1.byteLengthMismatch
        }
        let digest: ContentDigestV1
        if let copiedDigest { digest = copiedDigest }
        else { digest = try hash(payloadFD, count: Int(initialFacts.st_size)) }
        try Task.checkCancellation()
        let facts = try inspect(payloadFD, count: Int(initialFacts.st_size))
        try Task.checkCancellation()
        try DraftStagingRootOwnerV1.unchanged(payloadFD, initialFacts)
        guard try hash(payloadFD, count: Int(initialFacts.st_size)) == digest else {
            throw DraftAttachmentStagingFailureV1.digestMismatch
        }
        let inspection = try CheckRunnerPhotoSourceInspectionV1(facts: facts, sourceSHA256: digest,
            workspaceID: payload.workspaceID, provenanceID: intent.provenanceID)
        let item = try AttachmentStagingItemV1(stageID: intent.stageID, draftID: payload.childDraftID,
            workspaceID: payload.workspaceID, attachmentKind: .photo, scratchLeaseID: intent.stageID,
            expectedByteCount: intent.expectedSourceByteCount, actualByteCount: inspection.sourceByteCount,
            contentDigest: digest, contentReference: nil, processingJobID: nil, retryClass: .none,
            state: .readyLocal, protectionState: .available, revision: 1, mutationID: intent.stageMutationID)
        let provenance = try ContentOriginalProvenanceV1(provenanceID: intent.provenanceID,
            workspaceID: payload.workspaceID.rawValue.uuidString.lowercased(), contentID: inspection.rawContentID,
            contentDigest: digest, origin: payload.origin,
            recordedAt: CheckRunnerPhotoRawReadyV1.formatOriginalRecordedAt(intent.stageCreatedAt))
        let raw = try CheckRunnerPhotoRawReadyV1(intent: intent, inspection: inspection, readyItem: item,
            stagePublicationMutationID: intent.stageMutationID, originalProvenance: provenance)
        guard existingWitness == nil || existingWitness == raw else {
            throw DraftAttachmentStagingFailureV1.digestMismatch
        }
        if !existing {
            let bytes = try FieldDraftCanonicalCodecV1.encode(raw)
            let fd = openat(directory.descriptor, witnessName,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
            guard fd >= 0 else { throw DraftAttachmentStagingFailureV1.cleanupFailed }
            do {
                ownedWitness = try DraftStagingRootOwnerV1.regular(fd)
                try DraftStagingRootOwnerV1.write(bytes, to: fd)
                try ProtectedFilePolicyV1.applyAndVerify(.stagingFile,
                    at: directory.url.appendingPathComponent(witnessName))
                guard fsync(fd) == 0, fsync(directory.descriptor) == 0 else {
                    throw DraftAttachmentStagingFailureV1.cleanupFailed
                }
                close(fd)
            } catch { close(fd); throw error }
            witnessFD = try directory.openFile(witnessName)
            let witnessFacts = try DraftStagingRootOwnerV1.regular(witnessFD)
            guard try DraftStagingRootOwnerV1.read(witnessFD, count: Int(witnessFacts.st_size)) == bytes else {
                throw DraftAttachmentStagingFailureV1.digestMismatch
            }
            originalWitnessFacts = witnessFacts
        }
        let entry = try DraftAttachmentStagingEntryV1(item: item,
            relativeDataPath: DraftAttachmentStagingAdapterV1.relativeDataPath(
                draftID: payload.childDraftID, stageID: intent.stageID),
            mediaType: inspection.sourceMediaType, updatedAt: intent.stageCreatedAt)
        let prior = base.manifest.entries.first(where: { $0.item.stageID == intent.stageID })
        guard prior == nil || prior == entry else { throw DraftAttachmentStagingFailureV1.staleStage }
        // A receipt-backed retry must retain both operational membership and
        // its exact immutable witness; partial canonical joins are not repaired.
        if publishedRawReady != nil, prior != entry { throw DraftAttachmentStagingFailureV1.staleStage }
        let candidate = try DraftAttachmentStagingManifestV1(entries:
            base.manifest.entries.filter { $0.item.stageID != intent.stageID } + [entry])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let candidateBytes = try encoder.encode(candidate)
        try Task.checkCancellation()
        try DraftStagingRootOwnerV1.unchanged(payloadFD, initialFacts)
        guard let witnessFacts = originalWitnessFacts else { throw DraftAttachmentStagingFailureV1.corruptManifest }
        try DraftStagingRootOwnerV1.unchanged(witnessFD, witnessFacts)
        guard fsync(payloadFD) == 0, fsync(witnessFD) == 0, fsync(directory.descriptor) == 0 else {
            throw DraftAttachmentStagingFailureV1.cleanupFailed
        }
        let result = DraftPreparedRawPhotoPublicationV1(rawReady: raw, applicationSupportURL: applicationSupportURL,
            adapterIdentity: adapterIdentity, owner: owner, parent: parent, directory: directory, base: base,
            payloadDescriptor: payloadFD, payloadFacts: initialFacts, witnessDescriptor: witnessFD,
            witnessFacts: witnessFacts, candidateManifest: candidate,
            candidateBytes: candidateBytes, finalName: path[1], privateName: privateName)
        transferred = true
        return result
    }

    private static func copySource(_ url: URL, expectedCount: Int64,
        into directory: DraftStagingRootOwnerV1.Directory, ownedIdentity: inout stat?) throws
        -> (descriptor: Int32, digest: ContentDigestV1) {
        guard url.isFileURL, !url.path.utf8.contains(0) else {
            throw DraftAttachmentStagingFailureV1.invalidAttachment
        }
        let source = open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard source >= 0 else { throw DraftAttachmentStagingFailureV1.stageNotFound }
        defer { close(source) }
        let sourceFacts = try DraftStagingRootOwnerV1.regular(source)
        guard sourceFacts.st_size == expectedCount, expectedCount > 0,
              expectedCount <= Int64(MediaContractV1.sourceByteCountMaximum) else {
            throw DraftAttachmentStagingFailureV1.byteLengthMismatch
        }
        let destination = openat(directory.descriptor, DraftAttachmentStagingAdapterV1.payloadName,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard destination >= 0 else { throw DraftAttachmentStagingFailureV1.cleanupFailed }
        defer { close(destination) }
        ownedIdentity = try DraftStagingRootOwnerV1.regular(destination)
        var hasher = SHA256()
        var offset = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while offset < Int(expectedCount) {
            try Task.checkCancellation()
            let wanted = min(buffer.count, Int(expectedCount) - offset)
            let count = buffer.withUnsafeMutableBytes { pread(source, $0.baseAddress, wanted, off_t(offset)) }
            guard count > 0 else { throw DraftAttachmentStagingFailureV1.byteLengthMismatch }
            let chunk = Data(buffer.prefix(count))
            hasher.update(data: chunk)
            try DraftStagingRootOwnerV1.write(chunk, to: destination)
            offset += count
        }
        var extra: UInt8 = 0
        guard pread(source, &extra, 1, off_t(offset)) == 0 else {
            throw DraftAttachmentStagingFailureV1.byteLengthMismatch
        }
        try DraftStagingRootOwnerV1.unchanged(source, sourceFacts)
        try ProtectedFilePolicyV1.applyAndVerify(.stagingFile,
            at: directory.url.appendingPathComponent(DraftAttachmentStagingAdapterV1.payloadName))
        guard fsync(destination) == 0 else { throw DraftAttachmentStagingFailureV1.cleanupFailed }
        try directory.verifyFile(destination, name: DraftAttachmentStagingAdapterV1.payloadName)
        let digest = try ContentDigestV1(algorithm: .sha256,
            hexadecimalValue: hasher.finalize().map { String(format: "%02x", $0) }.joined())
        return (try directory.openFile(DraftAttachmentStagingAdapterV1.payloadName), digest)
    }

    fileprivate static func hash(_ fd: Int32, count: Int) throws -> ContentDigestV1 {
        var hasher = SHA256(), offset = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while offset < count {
            try Task.checkCancellation()
            let wanted = min(buffer.count, count - offset)
            let size = buffer.withUnsafeMutableBytes { pread(fd, $0.baseAddress, wanted, off_t(offset)) }
            guard size > 0 else { throw DraftAttachmentStagingFailureV1.byteLengthMismatch }
            hasher.update(data: Data(buffer.prefix(size))); offset += size
        }
        return try ContentDigestV1(algorithm: .sha256,
            hexadecimalValue: hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }

    fileprivate static func inspect(_ fd: Int32, count: Int) throws -> MediaSourceFactsV1 {
        let mapped = mmap(nil, count, PROT_READ, MAP_PRIVATE, fd, 0)
        guard let mapped, mapped != MAP_FAILED else { throw DraftAttachmentStagingFailureV1.invalidAttachment }
        defer { munmap(mapped, count) }
        // ImageIO and the no-copy Data end their lifetimes before unmapping.
        // Cancellation is checked around this synchronous inspection, not inside it.
        return try autoreleasepool {
            let bytes = Data(bytesNoCopy: mapped, count: count, deallocator: .none)
            return try MediaNormalizerV1().inspectSource(bytes)
        }
    }

    private static func removePrivate(owner: DraftStagingRootOwnerV1,
        directory: DraftStagingRootOwnerV1.Directory, name: String,
        payloadIdentity: stat?, witnessIdentity: stat?) {
        guard (try? directory.verifyNamed()) != nil else { return }
        // No traversal or recursive deletion: only the two private leaves this
        // operation creates, followed by its still-exact empty directory.
        for (leaf, identity) in [(DraftAttachmentStagingAdapterV1.payloadName, payloadIdentity),
                                 (witnessName, witnessIdentity)] {
            guard let identity else { continue }
            if let fd = try? directory.openFile(leaf) {
                defer { close(fd) }
                if let current = try? DraftStagingRootOwnerV1.regular(fd),
                   current.st_dev == identity.st_dev, current.st_ino == identity.st_ino,
                   (try? directory.verifyFile(fd, name: leaf)) != nil { unlinkat(directory.descriptor, leaf, 0) }
            }
        }
        if (try? directory.verifyNamed()) != nil { unlinkat(owner.descriptor, name, AT_REMOVEDIR) }
    }
}

/// An opened raw witness is only a physical snapshot. Application capabilities
/// still authenticate the original checkpoint and receipt before it is used.
/// No mapped source bytes or descriptors are exposed to the main actor.
fileprivate final class DraftRawPhotoReadSnapshotV1: @unchecked Sendable {
    let rawReady: CheckRunnerPhotoRawReadyV1
    let owner: DraftStagingRootOwnerV1
    let base: DraftStagingRootOwnerV1.ManifestSnapshot
    let directory: DraftStagingRootOwnerV1.Directory
    let entry: DraftAttachmentStagingEntryV1
    private let payloadDescriptor: Int32
    private let payloadFacts: stat
    private let witnessDescriptor: Int32
    private let witnessFacts: stat

    private init(rawReady: CheckRunnerPhotoRawReadyV1, owner: DraftStagingRootOwnerV1,
        base: DraftStagingRootOwnerV1.ManifestSnapshot, directory: DraftStagingRootOwnerV1.Directory,
        entry: DraftAttachmentStagingEntryV1, payloadDescriptor: Int32, payloadFacts: stat,
        witnessDescriptor: Int32, witnessFacts: stat) {
        self.rawReady = rawReady; self.owner = owner; self.base = base; self.directory = directory
        self.entry = entry; self.payloadDescriptor = payloadDescriptor; self.payloadFacts = payloadFacts
        self.witnessDescriptor = witnessDescriptor; self.witnessFacts = witnessFacts
    }

    deinit { close(payloadDescriptor); close(witnessDescriptor) }

    static func open(raw: CheckRunnerPhotoRawReadyV1, owner: DraftStagingRootOwnerV1,
        committedEntry: DraftAttachmentStagingEntryV1? = nil) throws -> DraftRawPhotoReadSnapshotV1 {
        try Task.checkCancellation()
        try raw.validate()
        let ready = try DraftAttachmentStagingEntryV1(item: raw.readyItem,
            relativeDataPath: DraftAttachmentStagingAdapterV1.relativeDataPath(
                draftID: raw.readyItem.draftID, stageID: raw.intent.stageID),
            mediaType: raw.inspection.sourceMediaType, updatedAt: raw.intent.stageCreatedAt)
        let lock = try owner.acquire()
        defer { lock.release() }
        let base = try DraftStagingRootOwnerV1.ManifestSnapshot(owner: owner)
        guard let entry = base.manifest.entries.first(where: { $0.item.stageID == raw.intent.stageID }),
              entry == ready || entry == committedEntry else {
            throw DraftAttachmentStagingFailureV1.staleStage
        }
        let parts = DraftAttachmentStagingAdapterV1.relativeStageDirectory(
            draftID: raw.readyItem.draftID, stageID: raw.intent.stageID).split(separator: "/").map(String.init)
        let directory = try owner.directory(parts)
        let witness = try directory.openFile("raw-publication.json")
        var payload: Int32 = -1
        var transferred = false
        do {
            let witnessFacts = try DraftStagingRootOwnerV1.regular(witness)
            guard witnessFacts.st_size > 0,
                  witnessFacts.st_size <= Int64(FieldDraftLimitsV1.maximumCanonicalBytes),
                  let count = Int(exactly: witnessFacts.st_size) else {
                throw DraftAttachmentStagingFailureV1.corruptManifest
            }
            let witnessBytes = try DraftStagingRootOwnerV1.read(witness, count: count)
            guard try FieldDraftCanonicalCodecV1.decode(CheckRunnerPhotoRawReadyV1.self,
                from: witnessBytes) == raw else { throw DraftAttachmentStagingFailureV1.digestMismatch }
            payload = try directory.openFile(DraftAttachmentStagingAdapterV1.payloadName)
            let payloadFacts = try DraftStagingRootOwnerV1.regular(payload)
            guard payloadFacts.st_size == raw.inspection.sourceByteCount,
                  payloadFacts.st_size > 0,
                  payloadFacts.st_size <= Int64(MediaContractV1.sourceByteCountMaximum) else {
                throw DraftAttachmentStagingFailureV1.byteLengthMismatch
            }
            try ProtectedFilePolicyV1.verify(.stagingDirectory, at: directory.url)
            try ProtectedFilePolicyV1.verify(.stagingFile,
                at: directory.url.appendingPathComponent("raw-publication.json"))
            try ProtectedFilePolicyV1.verify(.stagingFile,
                at: directory.url.appendingPathComponent(DraftAttachmentStagingAdapterV1.payloadName))
            let result = DraftRawPhotoReadSnapshotV1(rawReady: raw, owner: owner, base: base,
                directory: directory, entry: entry, payloadDescriptor: payload, payloadFacts: payloadFacts,
                witnessDescriptor: witness, witnessFacts: witnessFacts)
            transferred = true
            try result.requireCurrent()
            return result
        } catch {
            if !transferred { close(witness); if payload >= 0 { close(payload) } }
            throw error
        }
    }

    /// Called while R is held for a final publication. It performs only bounded
    /// descriptor/stat checks; hashing and ImageIO run before this critical section.
    func requireCurrent() throws {
        try owner.requireNamedRoot()
        try base.requireCurrent(owner)
        try directory.verifyNamed()
        try directory.verifyPinnedFile(payloadDescriptor,
            name: DraftAttachmentStagingAdapterV1.payloadName, facts: payloadFacts)
        try directory.verifyPinnedFile(witnessDescriptor, name: "raw-publication.json", facts: witnessFacts)
        try DraftStagingRootOwnerV1.unchanged(payloadDescriptor, payloadFacts)
        try DraftStagingRootOwnerV1.unchanged(witnessDescriptor, witnessFacts)
    }

    func verifyBytesAndInspection() throws {
        try Task.checkCancellation()
        try requireCurrent()
        let count = Int(payloadFacts.st_size)
        let digest = try DraftPreparedRawPhotoPublicationV1.hash(payloadDescriptor, count: count)
        guard digest == rawReady.inspection.sourceSHA256 else {
            throw DraftAttachmentStagingFailureV1.digestMismatch
        }
        let facts = try DraftPreparedRawPhotoPublicationV1.inspect(payloadDescriptor, count: count)
        let inspection = try CheckRunnerPhotoSourceInspectionV1(facts: facts, sourceSHA256: digest,
            workspaceID: rawReady.readyItem.workspaceID, provenanceID: rawReady.intent.provenanceID)
        guard inspection == rawReady.inspection else {
            throw DraftAttachmentStagingFailureV1.digestMismatch
        }
        try Task.checkCancellation()
        try requireCurrent()
    }

    func backupSnapshot() throws -> DraftPhotoRawBackupSnapshotV1 {
        try requireCurrent()
        var rootFacts = stat()
        guard fstat(owner.descriptor, &rootFacts) == 0 else { throw DraftAttachmentStagingFailureV1.invalidRoot }
        return .init(raw: rawReady, physicalEntry: try .init(entry: entry),
            rootURL: owner.rootURL,
            rootIdentity: .init(device: UInt64(rootFacts.st_dev), inode: UInt64(rootFacts.st_ino)),
            manifestSHA256: base.manifest.manifestSHA256,
            payloadFacts: DraftPhotoRawBackupSnapshotV1.facts(payloadFacts),
            witnessFacts: DraftPhotoRawBackupSnapshotV1.facts(witnessFacts))
    }

    private func mappedBytes() throws -> Data {
        try requireCurrent()
        let count = Int(payloadFacts.st_size)
        let mapped = mmap(nil, count, PROT_READ, MAP_PRIVATE, payloadDescriptor, 0)
        guard let mapped, mapped != MAP_FAILED else { throw DraftAttachmentStagingFailureV1.invalidAttachment }
        // Data owns the map through the complete async C05 call. A receiving
        // owner retaining a Data copy cannot outlive the map's storage.
        return Data(bytesNoCopy: mapped, count: count, deallocator: .custom { address, length in
            _ = munmap(address, length)
        })
    }

    func normalize() throws -> NormalizedMediaWithSourceFactsV1 {
        try verifyBytesAndInspection()
        let bytes = try mappedBytes()
        let normalized = try autoreleasepool { try MediaNormalizerV1().normalizeWithSourceFacts(bytes) }
        guard normalized.sourceFacts == MediaSourceFactsV1(
            sourceTypeIdentifier: rawReady.inspection.detectedUTI,
            pixelWidth: rawReady.inspection.pixelWidth, pixelHeight: rawReady.inspection.pixelHeight,
            byteCount: Int(rawReady.inspection.sourceByteCount)) else {
            throw DraftAttachmentStagingFailureV1.digestMismatch
        }
        try verifyBytesAndInspection()
        let lock = try owner.acquire()
        defer { lock.release() }
        try requireCurrent()
        return normalized
    }

    func writeImmutable(using writer: any DraftImmutableContentWriterV1,
        request: DraftImmutableContentWriteRequestV1) async throws -> DraftImmutableContentWriteReceiptV1 {
        try verifyBytesAndInspection()
        let bytes = try mappedBytes()
        let receipt = try await writer.persistImmutableOriginal(bytes: bytes, request: request)
        try Task.checkCancellation()
        try receipt.validate(request: request, bytes: bytes)
        try verifyBytesAndInspection()
        return receipt
    }
}

/// Retains the already-inspected raw descriptors through the pair-ready CAS.
/// The application can hold G, then this raw-stage lock, then the media lock;
/// only bounded named-identity/stat checks execute inside this critical path.
final class DraftPreparedRawPhotoVerificationV1: @unchecked Sendable {
    let rawReady: CheckRunnerPhotoRawReadyV1
    let applicationSupportURL: URL
    let adapterIdentity: ObjectIdentifier
    private let snapshot: DraftRawPhotoReadSnapshotV1
    private let consumption = NSLock()
    private var consumed = false

    fileprivate init(rawReady: CheckRunnerPhotoRawReadyV1, applicationSupportURL: URL,
        adapterIdentity: ObjectIdentifier, snapshot: DraftRawPhotoReadSnapshotV1) {
        self.rawReady = rawReady
        self.applicationSupportURL = applicationSupportURL
        self.adapterIdentity = adapterIdentity
        self.snapshot = snapshot
    }

    /// Rechecks the retained snapshot after application validation and before
    /// this capability leaves the adapter actor.
    fileprivate func recheckBeforeReturn() throws {
        let lock = try snapshot.owner.acquire()
        defer { lock.release() }
        try snapshot.requireCurrent()
    }

    func withVerificationLock<T>(_ body: () throws -> T) throws -> T {
        guard consumption.try() else { throw DraftAttachmentStagingFailureV1.staleStage }
        defer { consumption.unlock() }
        guard !consumed else { throw DraftAttachmentStagingFailureV1.invalidTransition }
        consumed = true
        let lock = try snapshot.owner.acquire()
        defer { lock.release() }
        try snapshot.requireCurrent()
        let result = try body()
        try snapshot.requireCurrent()
        return result
    }
}

/// Bounded value facts: a backup does not retain one descriptor pair per child.
struct DraftPhotoRawBackupSnapshotV1: Equatable, Sendable {
    let raw: CheckRunnerPhotoRawReadyV1
    let physicalEntry: CheckRunnerPhotoBackupPhysicalEntryV1
    let rootURL: URL
    let rootIdentity: StreamingArchiveRootIdentityV1
    let manifestSHA256: String
    let payloadFacts: StreamingArchiveSourceSnapshotV1
    let witnessFacts: StreamingArchiveSourceSnapshotV1

    fileprivate static func facts(_ value: stat) -> StreamingArchiveSourceSnapshotV1 {
        .init(device: UInt64(value.st_dev), inode: UInt64(value.st_ino), linkCount: UInt64(value.st_nlink),
              byteCount: value.st_size, modifiedSeconds: Int64(value.st_mtimespec.tv_sec),
              modifiedNanoseconds: Int64(value.st_mtimespec.tv_nsec), changedSeconds: Int64(value.st_ctimespec.tv_sec),
              changedNanoseconds: Int64(value.st_ctimespec.tv_nsec))
    }
}

enum DraftPhotoBackupRootObservationV1: Sendable {
    case existing(DraftAttachmentStagingAdapterV1)
    case absent(DraftPhotoBackupAbsentRootVerificationV1)
}

/// Retains the incumbent data-directory identity without creating the global
/// staging root. An empty canonical inventory is required while that root is
/// absent; child intents may still describe photos that have not staged bytes.
final class DraftPhotoBackupAbsentRootVerificationV1: @unchecked Sendable {
    private let parent: DraftStagingRootOwnerV1
    private let workspaceID: WorkspaceID
    private static let zero = UUID(uuid: (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    ))

    fileprivate init(parent: DraftStagingRootOwnerV1, workspaceID: WorkspaceID) {
        self.parent = parent
        self.workspaceID = workspaceID
    }

    func preparePhotoBackupVerification(canonicalStages: [AttachmentStagingItemV1],
        childStageIDs: [UUID: UUID]) throws -> DraftPhotoBackupAbsentRootPreparedVerificationV1 {
        guard canonicalStages.isEmpty,
              childStageIDs.count <= FieldDraftLimitsV1.maximumStageItems,
              Set(childStageIDs.values).count == childStageIDs.count else {
            throw DraftAttachmentStagingFailureV1.staleStage
        }
        for (childID, stageID) in childStageIDs {
            guard childID != Self.zero, stageID != Self.zero else {
                throw DraftAttachmentStagingFailureV1.staleStage
            }
        }
        let lock = try parent.acquire()
        defer { lock.release() }
        try Self.requireAbsent(parent)
        return DraftPhotoBackupAbsentRootPreparedVerificationV1(
            parent: parent, workspaceID: workspaceID, childStageIDs: childStageIDs)
    }

    fileprivate static func requireAbsent(_ parent: DraftStagingRootOwnerV1) throws {
        try Task.checkCancellation()
        try parent.requireNamedRoot()
        guard try !parent.directory([]).exists(DraftAttachmentStagingAdapterV1.directoryName) else {
            throw DraftAttachmentStagingFailureV1.staleStage
        }
    }
}

/// Holds the data-parent lock while the archive finalizer consumes the proven
/// empty raw inventory, then rechecks both the parent identity and leaf absence.
final class DraftPhotoBackupAbsentRootPreparedVerificationV1: @unchecked Sendable {
    private let parent: DraftStagingRootOwnerV1
    let workspaceID: WorkspaceID
    let childStageIDs: [UUID: UUID]

    fileprivate init(parent: DraftStagingRootOwnerV1, workspaceID: WorkspaceID,
        childStageIDs: [UUID: UUID]) {
        self.parent = parent
        self.workspaceID = workspaceID
        self.childStageIDs = childStageIDs
    }

    func withVerificationLock<T>(_ body: () throws -> T) throws -> T {
        let lock = try parent.acquire()
        defer { lock.release() }
        try DraftPhotoBackupAbsentRootVerificationV1.requireAbsent(parent)
        let value = try body()
        try DraftPhotoBackupAbsentRootVerificationV1.requireAbsent(parent)
        return value
    }
}

/// The actor already hashed and inspected these originals off the UI actor.
/// Final validation holds R only for manifest, namespace and descriptor facts.
final class DraftPhotoBackupPreparedVerificationV1: @unchecked Sendable {
    let snapshots: [DraftPhotoRawBackupSnapshotV1]
    fileprivate let owner: DraftStagingRootOwnerV1
    private let canonicalStages: [AttachmentStagingItemV1]
    private let childStageIDs: [UUID: UUID]
    private let manifestSHA256: String
    fileprivate let namespaceFacts: [String: StreamingArchiveSourceSnapshotV1]

    fileprivate init(snapshots: [DraftPhotoRawBackupSnapshotV1], owner: DraftStagingRootOwnerV1,
                     canonicalStages: [AttachmentStagingItemV1], childStageIDs: [UUID: UUID],
                     committingCheckpoints: [UUID: FieldDraftCheckpointV1]) throws {
        self.snapshots = snapshots; self.owner = owner
        self.canonicalStages = canonicalStages
        self.childStageIDs = childStageIDs
        // The durable raw write can precede its canonical acknowledgement.
        // Permit only the exact COMMITTING-derived physical successor while
        // retaining the original ready row, never an arbitrary phase mismatch.
        for snapshot in snapshots {
            let promotion = try committingCheckpoints[snapshot.raw.readyItem.draftID].map {
                try DraftPhotoRawPromotionValuesV1(checkpoint: $0)
            }
            let canonical = canonicalStages.first { $0.stageID == snapshot.raw.intent.stageID }
            guard promotion.map({ $0.rawReady == snapshot.raw }) ?? true,
                  canonical == snapshot.raw.readyItem || canonical == promotion?.committedStage,
                  snapshot.physicalEntry.entry.item == canonical
                    || (canonical == snapshot.raw.readyItem
                        && snapshot.physicalEntry.entry == promotion?.committedEntry) else {
                throw DraftAttachmentStagingFailureV1.staleStage
            }
        }
        let held = try owner.acquire(); defer { held.release() }
        let manifest = try DraftStagingRootOwnerV1.ManifestSnapshot(owner: owner).manifest
        manifestSHA256 = manifest.manifestSHA256
        namespaceFacts = try Self.census(owner: owner, canonicalStages: canonicalStages,
            childStageIDs: childStageIDs, snapshots: snapshots, manifest: manifest, hashGenericPayloads: true)
        try requireCurrent()
    }

    func withVerificationLock<T>(_ body: () throws -> T) throws -> T {
        let lock = try owner.acquire()
        defer { lock.release() }
        try requireCurrent()
        let value = try body()
        try requireCurrent()
        return value
    }

    /// Restore changes the namespace only after recording this exact before
    /// census. Its owner must verify the resulting closed operation census;
    /// the unchanged backup census is deliberately not reusable afterwards.
    fileprivate func withRestorePreparationLock<T>(_ body: () throws -> T) throws -> T {
        let lock = try owner.acquire()
        defer { lock.release() }
        try requireCurrent()
        return try body()
    }

    private func requireCurrent() throws {
        try Task.checkCancellation()
        try owner.requireNamedRoot()
        let manifest = try DraftStagingRootOwnerV1.ManifestSnapshot(owner: owner).manifest
        guard manifest.manifestSHA256 == manifestSHA256,
              try Self.census(owner: owner, canonicalStages: canonicalStages,
                childStageIDs: childStageIDs, snapshots: snapshots, manifest: manifest) == namespaceFacts else {
            throw DraftAttachmentStagingFailureV1.staleStage
        }
        var rootFacts = stat()
        guard fstat(owner.descriptor, &rootFacts) == 0 else { throw DraftAttachmentStagingFailureV1.invalidRoot }
        let rootIdentity = StreamingArchiveRootIdentityV1(device: UInt64(rootFacts.st_dev), inode: UInt64(rootFacts.st_ino))
        for snapshot in snapshots {
            guard snapshot.rootURL == owner.rootURL, snapshot.rootIdentity == rootIdentity,
                  snapshot.manifestSHA256 == manifest.manifestSHA256,
                  manifest.entries.first(where: { $0.item.stageID == snapshot.raw.intent.stageID })
                    == snapshot.physicalEntry.entry else { throw DraftAttachmentStagingFailureV1.staleStage }
            let parts = DraftAttachmentStagingAdapterV1.relativeStageDirectory(
                draftID: snapshot.raw.readyItem.draftID, stageID: snapshot.raw.intent.stageID).split(separator: "/").map(String.init)
            let directory = try owner.directory(parts)
            for (name, expected) in [(DraftAttachmentStagingAdapterV1.payloadName, snapshot.payloadFacts),
                                     ("raw-publication.json", snapshot.witnessFacts)] {
                let file = try directory.openFile(name)
                defer { close(file) }
                guard try DraftPhotoRawBackupSnapshotV1.facts(DraftStagingRootOwnerV1.regular(file)) == expected else {
                    throw DraftAttachmentStagingFailureV1.staleStage
                }
            }
            try directory.verifyNamed()
        }
    }

    private static func census(owner: DraftStagingRootOwnerV1,
        canonicalStages: [AttachmentStagingItemV1], childStageIDs: [UUID: UUID],
        snapshots: [DraftPhotoRawBackupSnapshotV1], manifest: DraftAttachmentStagingManifestV1,
        hashGenericPayloads: Bool = false) throws
        -> [String: StreamingArchiveSourceSnapshotV1] {
        let rawByChild = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.raw.readyItem.draftID, $0) })
        let rawByStage = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.raw.intent.stageID, $0) })
        let canonicalByStage = Dictionary(uniqueKeysWithValues: canonicalStages.map { ($0.stageID, $0) })
        let manifestByStage = Dictionary(uniqueKeysWithValues: manifest.entries.map { ($0.item.stageID, $0) })
        guard rawByChild.count == snapshots.count,
              rawByStage.count == snapshots.count,
              canonicalByStage.count == canonicalStages.count,
              manifestByStage.count == manifest.entries.count,
              manifest.entries.count == canonicalStages.count,
              Set(rawByChild.keys).isSubset(of: Set(childStageIDs.keys)),
              manifest.entries.allSatisfy({ entry in
                  let expected = rawByStage[entry.item.stageID]?.physicalEntry.entry.item
                    ?? canonicalByStage[entry.item.stageID]
                  return expected == entry.item
              }),
              snapshots.allSatisfy({ snapshot in
                  childStageIDs[snapshot.raw.readyItem.draftID] == snapshot.raw.intent.stageID
                    && manifestByStage[snapshot.raw.intent.stageID] == snapshot.physicalEntry.entry
              }) else {
            throw DraftAttachmentStagingFailureV1.staleStage
        }
        let root = try owner.directory([])
        let quarantine = try owner.directory([DraftAttachmentStagingAdapterV1.quarantineName])
        var facts: [String: StreamingArchiveSourceSnapshotV1] = [
            "directory:.": DraftPhotoRawBackupSnapshotV1.facts(root.identity),
            "directory:\(DraftAttachmentStagingAdapterV1.quarantineName)":
                DraftPhotoRawBackupSnapshotV1.facts(quarantine.identity)
        ]

        let manifestFile = try root.openFile(DraftAttachmentStagingAdapterV1.manifestName)
        do {
            defer { close(manifestFile) }
            facts["file:\(DraftAttachmentStagingAdapterV1.manifestName)"] =
                try DraftPhotoRawBackupSnapshotV1.facts(DraftStagingRootOwnerV1.regular(manifestFile))
            try root.verifyFile(manifestFile, name: DraftAttachmentStagingAdapterV1.manifestName)
        }

        var stagesByParent: [String: [String: DraftAttachmentStagingEntryV1]] = [:]
        var requiredParents = Set<String>()
        var optionalParents = Set<String>()
        for entry in manifest.entries {
            try Task.checkCancellation()
            if entry.item.state == .orphanQuarantined {
                let stageName = "stage-\(entry.item.stageID.uuidString.lowercased())"
                guard entry.relativeDataPath == "\(DraftAttachmentStagingAdapterV1.quarantineName)/\(stageName)/\(DraftAttachmentStagingAdapterV1.payloadName)",
                      try quarantine.exists(stageName) else {
                    throw DraftAttachmentStagingFailureV1.staleStage
                }
                let stageDirectory = try owner.directory([DraftAttachmentStagingAdapterV1.quarantineName, stageName])
                try recordStageDirectory(stageDirectory, relativePath:
                    "\(DraftAttachmentStagingAdapterV1.quarantineName)/\(stageName)",
                    expectedNames: [DraftAttachmentStagingAdapterV1.payloadName], item: entry.item, facts: &facts)
                continue
            }
            let parts = DraftAttachmentStagingAdapterV1.relativeStageDirectory(
                draftID: entry.item.draftID, stageID: entry.item.stageID)
                .split(separator: "/").map(String.init)
            guard parts.count == 2,
                  entry.relativeDataPath == DraftAttachmentStagingAdapterV1.relativeDataPath(
                    draftID: entry.item.draftID, stageID: entry.item.stageID),
                  stagesByParent[parts[0], default: [:]].updateValue(entry, forKey: parts[1]) == nil else {
                throw DraftAttachmentStagingFailureV1.staleStage
            }
            requiredParents.insert(parts[0])
        }

        for (child, stage) in childStageIDs {
            try Task.checkCancellation()
            let parts = DraftAttachmentStagingAdapterV1.relativeStageDirectory(draftID: child, stageID: stage)
                .split(separator: "/").map(String.init)
            let expected = rawByChild[child]
            let entries = manifest.entries.filter { $0.item.draftID == child }
            guard entries == (expected.map({ [$0.physicalEntry.entry] }) ?? []) else {
                throw DraftAttachmentStagingFailureV1.staleStage
            }
            if expected == nil { optionalParents.insert(parts[0]) }
        }

        var presentOptionalParents = Set<String>()
        for parentName in optionalParents where !requiredParents.contains(parentName) {
            if try root.exists(parentName) { presentOptionalParents.insert(parentName) }
        }
        let expectedRootNames: Set<String> = [
            DraftAttachmentStagingAdapterV1.manifestName,
            DraftAttachmentStagingAdapterV1.quarantineName
        ]
        guard try root.names() == expectedRootNames.union(requiredParents).union(presentOptionalParents) else {
            throw DraftAttachmentStagingFailureV1.staleStage
        }

        for parentName in requiredParents.union(presentOptionalParents) {
            try Task.checkCancellation()
            let parent = try owner.directory([parentName])
            facts["directory:\(parentName)"] = DraftPhotoRawBackupSnapshotV1.facts(parent.identity)
            let expectedStages = stagesByParent[parentName] ?? [:]
            guard try parent.names() == Set(expectedStages.keys) else {
                throw DraftAttachmentStagingFailureV1.staleStage
            }
            for (stageName, entry) in expectedStages {
                let relativeStage = "\(parentName)/\(stageName)"
                let stageDirectory = try owner.directory([parentName, stageName])
                let isPhoto = rawByStage[entry.item.stageID] != nil
                let expectedNames: Set<String> = isPhoto
                    ? [DraftAttachmentStagingAdapterV1.payloadName, "raw-publication.json"]
                    : [DraftAttachmentStagingAdapterV1.payloadName]
                try recordStageDirectory(stageDirectory, relativePath: relativeStage,
                    expectedNames: expectedNames, item: entry.item, facts: &facts,
                    hashGenericPayload: hashGenericPayloads && !isPhoto)
            }
        }
        return facts
    }

    private static func recordStageDirectory(_ directory: DraftStagingRootOwnerV1.Directory,
        relativePath: String, expectedNames: Set<String>, item: AttachmentStagingItemV1,
        facts: inout [String: StreamingArchiveSourceSnapshotV1], hashGenericPayload: Bool = false) throws {
        guard try directory.names() == expectedNames else {
            throw DraftAttachmentStagingFailureV1.staleStage
        }
        facts["directory:\(relativePath)"] = DraftPhotoRawBackupSnapshotV1.facts(directory.identity)
        for name in expectedNames {
            let file = try directory.openFile(name)
            let fileFacts: stat
            do {
                defer { close(file) }
                fileFacts = try DraftStagingRootOwnerV1.regular(file)
                if hashGenericPayload, name == DraftAttachmentStagingAdapterV1.payloadName,
                   item.state == .readyLocal || item.state == .committed {
                    guard let count = item.actualByteCount, count > 0,
                          count <= Int64(FieldDraftLimitsV1.maximumPayloadBytes),
                          fileFacts.st_size == count, let digest = item.contentDigest,
                          digest.algorithm == .sha256 else {
                        throw DraftAttachmentStagingFailureV1.byteLengthMismatch
                    }
                    var hash = SHA256(), offset: Int64 = 0
                    var chunk = [UInt8](repeating: 0, count: 64 * 1024)
                    while offset < count {
                        try Task.checkCancellation()
                        let wanted = Int(min(Int64(chunk.count), count - offset))
                        let read = chunk.withUnsafeMutableBytes {
                            pread(file, $0.baseAddress, wanted, off_t(offset))
                        }
                        if read < 0 && errno == EINTR { continue }
                        guard read > 0 else { throw DraftAttachmentStagingFailureV1.byteLengthMismatch }
                        hash.update(data: Data(chunk.prefix(read)))
                        offset += Int64(read)
                    }
                    guard hash.finalize().map({ String(format: "%02x", $0) }).joined()
                            == digest.hexadecimalValue else {
                        throw DraftAttachmentStagingFailureV1.digestMismatch
                    }
                }
                try directory.verifyPinnedFile(file, name: name, facts: fileFacts)
            }
            if name == DraftAttachmentStagingAdapterV1.payloadName,
               let expectedByteCount = item.actualByteCount,
               fileFacts.st_size != expectedByteCount {
                throw DraftAttachmentStagingFailureV1.byteLengthMismatch
            }
            facts["file:\(relativePath)/\(name)"] = DraftPhotoRawBackupSnapshotV1.facts(fileFacts)
        }
        try directory.verifyNamed()
    }
}

/// Pure reconstruction shared by promotion and backup's physical phase proof.
/// These values supply no file publication or canonical mutation authority.
struct DraftPhotoRawPromotionValuesV1: Equatable, Sendable {
    let rawReady: CheckRunnerPhotoRawReadyV1
    let plan: DraftCommitPlanV1
    let attempt: CheckRunnerPhotoCommitAttemptV1
    let request: DraftImmutableContentWriteRequestV1
    let reservation: DraftContentReservationV1
    let committedStage: AttachmentStagingItemV1
    let contentReference: ContentReferenceV1
    let committedEntry: DraftAttachmentStagingEntryV1

    init(checkpoint: FieldDraftCheckpointV1) throws {
        let reconstruction = try CheckRunnerPhotoDraftCodecV1.reconstructPhotoCommit(from: checkpoint)
        let payload = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(checkpoint)
        guard case let .preparedCommit(pair, attempt) = payload.phase else {
            throw DraftAttachmentStagingFailureV1.invalidTransition
        }
        let raw = pair.raw, ready = raw.readyItem, plan = reconstruction.draftCommit.plan
        let request = try DraftImmutableContentWriteRequestV1(workspaceID: ready.workspaceID,
            contentID: raw.inspection.rawContentID, digest: raw.inspection.sourceSHA256,
            byteLength: raw.inspection.sourceByteCount, mediaType: raw.inspection.sourceMediaType,
            mutationID: attempt.reservationMutationID,
            createdAt: CheckRunnerPhotoRawReadyV1.formatOriginalRecordedAt(attempt.promotionAt))
        let reference = try ContentReferenceV1(workspaceID: ready.workspaceID.rawValue.uuidString.lowercased(),
            contentID: request.contentID, byteLength: request.byteLength, mediaType: request.mediaType,
            digests: .init([request.digest]), byteRole: .immutableOriginal, createdAt: request.createdAt)
        let locator = try ContentLocatorV1(locatorID: request.locatorID, workspaceID: reference.workspaceID,
            contentID: request.contentID, locatorRevision: 0, contentDigest: request.digest,
            expectedByteLength: request.byteLength)
        let reservation = try DraftContentReservationV1(reservationID: DraftAttachmentStagingAdapterV1.deterministicUUID(
            "reservation\u{1f}\(plan.planSHA256)\u{1f}\(ready.stageID.uuidString.lowercased())"),
            workspaceID: ready.workspaceID, draftID: ready.draftID, stageID: ready.stageID,
            commitPlanSHA256: plan.planSHA256, mutationID: attempt.reservationMutationID,
            contentDigest: request.digest, locator: locator, createdAt: attempt.promotionAt,
            reviewAfter: attempt.reservationReviewAfter, reconciliationState: .reserved, revision: 1)
        let committed = try AttachmentStagingItemV1(stageID: ready.stageID, draftID: ready.draftID,
            workspaceID: ready.workspaceID, attachmentKind: ready.attachmentKind,
            scratchLeaseID: ready.scratchLeaseID, expectedByteCount: ready.expectedByteCount,
            actualByteCount: ready.actualByteCount, contentDigest: ready.contentDigest,
            contentReference: reference, processingJobID: ready.processingJobID, retryClass: ready.retryClass,
            state: .committed, protectionState: ready.protectionState, revision: ready.revision + 1,
            mutationID: .init(rawValue: DraftAttachmentStagingAdapterV1.deterministicUUID(
                "stage-mutation\u{1f}\(ready.stageID.uuidString.lowercased())\u{1f}\(ready.revision + 1)\u{1f}COMMITTED\u{1f}\(request.digest.hexadecimalValue)")))
        let committedEntry = try DraftAttachmentStagingEntryV1(item: committed,
            relativeDataPath: DraftAttachmentStagingAdapterV1.relativeDataPath(draftID: ready.draftID, stageID: ready.stageID),
            mediaType: request.mediaType, updatedAt: attempt.promotionAt)
        rawReady = raw; self.plan = plan; self.attempt = attempt; self.request = request
        self.reservation = reservation; committedStage = committed
        contentReference = reference; self.committedEntry = committedEntry
    }
}

/// The root service can inspect frozen metadata but cannot manufacture a
/// successful physical promotion. Only this adapter can construct/finish it.
final class DraftPreparedRawPhotoPromotionV1: @unchecked Sendable {
    let rawReady: CheckRunnerPhotoRawReadyV1
    let plan: DraftCommitPlanV1
    let attempt: CheckRunnerPhotoCommitAttemptV1
    let request: DraftImmutableContentWriteRequestV1
    let reservation: DraftContentReservationV1
    let committedStage: AttachmentStagingItemV1
    let contentReference: ContentReferenceV1
    let applicationSupportURL: URL
    let adapterIdentity: ObjectIdentifier
    private let snapshot: DraftRawPhotoReadSnapshotV1
    private let candidate: DraftAttachmentStagingManifestV1
    private let candidateBytes: Data
    private let stateLock = NSLock()
    private var writing = false
    private var verifiedReceipt: DraftImmutableContentWriteReceiptV1?
    private var consumed = false

    private init(rawReady: CheckRunnerPhotoRawReadyV1, plan: DraftCommitPlanV1,
        attempt: CheckRunnerPhotoCommitAttemptV1, request: DraftImmutableContentWriteRequestV1,
        reservation: DraftContentReservationV1, committedStage: AttachmentStagingItemV1,
        contentReference: ContentReferenceV1, applicationSupportURL: URL,
        adapterIdentity: ObjectIdentifier, snapshot: DraftRawPhotoReadSnapshotV1,
        candidate: DraftAttachmentStagingManifestV1, candidateBytes: Data) {
        self.rawReady = rawReady; self.plan = plan; self.attempt = attempt; self.request = request
        self.reservation = reservation; self.committedStage = committedStage; self.contentReference = contentReference
        self.applicationSupportURL = applicationSupportURL; self.adapterIdentity = adapterIdentity
        self.snapshot = snapshot; self.candidate = candidate; self.candidateBytes = candidateBytes
    }

    fileprivate static func prepare(checkpoint: FieldDraftCheckpointV1, applicationSupportURL: URL,
        adapterIdentity: ObjectIdentifier, owner: DraftStagingRootOwnerV1) throws -> DraftPreparedRawPhotoPromotionV1 {
        let values = try DraftPhotoRawPromotionValuesV1(checkpoint: checkpoint)
        let raw = values.rawReady, ready = raw.readyItem, plan = values.plan
        let attempt = values.attempt, request = values.request, reference = values.contentReference
        let reservation = values.reservation, committed = values.committedStage
        let committedEntry = values.committedEntry
        let snapshot = try DraftRawPhotoReadSnapshotV1.open(raw: raw, owner: owner, committedEntry: committedEntry)
        try snapshot.verifyBytesAndInspection()
        let candidate = try DraftAttachmentStagingManifestV1(entries:
            snapshot.base.manifest.entries.filter { $0.item.stageID != ready.stageID } + [committedEntry])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return DraftPreparedRawPhotoPromotionV1(rawReady: raw, plan: plan, attempt: attempt,
            request: request, reservation: reservation, committedStage: committed, contentReference: reference,
            applicationSupportURL: applicationSupportURL, adapterIdentity: adapterIdentity,
            snapshot: snapshot, candidate: candidate, candidateBytes: try encoder.encode(candidate))
    }

    private func beginWrite() throws {
        guard stateLock.try() else { throw DraftAttachmentStagingFailureV1.staleStage }
        defer { stateLock.unlock() }
        guard !writing, verifiedReceipt == nil, !consumed else { throw DraftAttachmentStagingFailureV1.invalidTransition }
        writing = true
    }

    private func finishWrite(_ receipt: DraftImmutableContentWriteReceiptV1) throws {
        guard stateLock.try() else { throw DraftAttachmentStagingFailureV1.staleStage }
        defer { stateLock.unlock() }
        guard writing, verifiedReceipt == nil, !consumed else { throw DraftAttachmentStagingFailureV1.invalidTransition }
        verifiedReceipt = receipt; writing = false
    }

    fileprivate func persist(using writer: any DraftImmutableContentWriterV1) async throws {
        try beginWrite()
        let receipt = try await snapshot.writeImmutable(using: writer, request: request)
        // The actual C05 receipt retains its reuse flag. No synthetic persisted
        // C05 journal receipt is introduced by the reservation projection.
        try finishWrite(receipt)
    }

    func withPublicationLock<T>(_ body: (_ publish: () throws -> Void) throws -> T) throws -> T {
        guard stateLock.try() else { throw DraftAttachmentStagingFailureV1.staleStage }
        defer { stateLock.unlock() }
        guard !writing, verifiedReceipt != nil, !consumed else { throw DraftAttachmentStagingFailureV1.invalidTransition }
        consumed = true
        let lock = try snapshot.owner.acquire()
        defer { lock.release() }
        try snapshot.requireCurrent()
        var published = false
        let result = try body {
            guard !published else { throw DraftAttachmentStagingFailureV1.invalidTransition }
            try self.snapshot.requireCurrent()
            if self.candidate != self.snapshot.base.manifest {
                try DraftStagingRootOwnerV1.replaceFile(self.candidateBytes,
                    at: self.snapshot.owner.rootURL.appendingPathComponent(DraftAttachmentStagingAdapterV1.manifestName),
                    directory: self.snapshot.owner.directory([]))
            }
            let readback = try DraftStagingRootOwnerV1.ManifestSnapshot(owner: self.snapshot.owner)
            guard try readback.manifest.canonicalBytes() == self.candidateBytes else {
                throw DraftAttachmentStagingFailureV1.corruptManifest
            }
            published = true
        }
        guard published else { throw DraftAttachmentStagingFailureV1.invalidTransition }
        return result
    }
}

/// Device-local failures are deliberately kept separate from the canonical
/// draft errors.  A staging failure must never be presented as a successful
/// save or as a committed EvidenceID.
enum DraftAttachmentStagingFailureV1: Error, Equatable, Sendable {
    case invalidRoot
    case wrongWorkspace
    case invalidAttachment
    case stageAlreadyExists
    case stageNotFound
    case staleStage
    case invalidTransition
    case corruptManifest
    case unsafePath
    case protectedDataUnavailable
    case permissionDenied
    case insufficientStorage
    case cancelled
    case digestMismatch
    case byteLengthMismatch
    case promotionRequiresReady
    case reservationMismatch
    case contentWriterUnavailable
    case contentWriterRejected
    case cleanupFailed
}

/// The byte location is intentionally a draft/stage path.  It carries no
/// EvidenceID and is never a public content association.
struct DraftAttachmentStagingEntryV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let item: AttachmentStagingItemV1
    let relativeDataPath: String
    let mediaType: String
    let updatedAt: Date

    init(
        item: AttachmentStagingItemV1,
        relativeDataPath: String,
        mediaType: String,
        updatedAt: Date
    ) throws {
        guard item.schemaVersion == AttachmentStagingItemV1.schemaVersion,
              !relativeDataPath.isEmpty,
              !relativeDataPath.hasPrefix("/"),
              !relativeDataPath.hasPrefix("\\"),
              !relativeDataPath.contains("\\"),
              relativeDataPath.split(separator: "/", omittingEmptySubsequences: false)
                .allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              ContentContractValidationV1.validMediaType(mediaType),
              updatedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw DraftAttachmentStagingFailureV1.invalidAttachment
        }
        self.schemaVersion = Self.schemaVersion
        self.item = item
        self.relativeDataPath = relativeDataPath
        self.mediaType = mediaType
        self.updatedAt = updatedAt
    }
}

struct DraftAttachmentStagingManifestV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumEntries = FieldDraftLimitsV1.maximumStageItems

    let schemaVersion: Int
    let entries: [DraftAttachmentStagingEntryV1]
    let manifestSHA256: String

    init(entries: [DraftAttachmentStagingEntryV1]) throws {
        let ordered = entries.sorted { $0.item.stageID.uuidString.lowercased()
            < $1.item.stageID.uuidString.lowercased() }
        guard ordered.count <= Self.maximumEntries,
              Set(ordered.map { $0.item.stageID }).count == ordered.count else {
            throw DraftAttachmentStagingFailureV1.corruptManifest
        }
        schemaVersion = Self.schemaVersion
        self.entries = ordered
        manifestSHA256 = try FieldDraftCanonicalCodecV1.sha256(
            Basis(schemaVersion: Self.schemaVersion, entries: ordered)
        )
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              entries.count <= Self.maximumEntries,
              entries == entries.sorted(by: {
                  $0.item.stageID.uuidString.lowercased()
                      < $1.item.stageID.uuidString.lowercased()
              }),
              Set(entries.map { $0.item.stageID }).count == entries.count,
              manifestSHA256 == (try FieldDraftCanonicalCodecV1.sha256(
                  Basis(schemaVersion: schemaVersion, entries: entries)
              )) else {
            throw DraftAttachmentStagingFailureV1.corruptManifest
        }
        for entry in entries {
            try entry.item.validate()
            guard entry == (try DraftAttachmentStagingEntryV1(item: entry.item,
                relativeDataPath: entry.relativeDataPath, mediaType: entry.mediaType, updatedAt: entry.updatedAt)) else {
                throw DraftAttachmentStagingFailureV1.corruptManifest
            }
        }
    }

    /// The wire representation is the persistence equality boundary. Date can
    /// change one floating-point ULP across JSON's epoch conversion while these
    /// canonical bytes remain identical; never round the domain instant.
    func canonicalBytes() throws -> Data { try FieldDraftCanonicalCodecV1.encode(self) }

    private struct Basis: Codable {
        let schemaVersion: Int
        let entries: [DraftAttachmentStagingEntryV1]
    }
}

struct DraftAttachmentStagingRemovalReceiptV1: Codable, Equatable, Sendable {
    let stageID: UUID
    let draftID: UUID
    let workspaceID: WorkspaceID
    let priorRevision: UInt64
    let removedAt: Date
    let bytesRemoved: Int64

    init(
        stageID: UUID,
        draftID: UUID,
        workspaceID: WorkspaceID,
        priorRevision: UInt64,
        removedAt: Date,
        bytesRemoved: Int64
    ) throws {
        guard stageID != Self.zero, draftID != Self.zero,
              workspaceID.rawValue != Self.zero, priorRevision > 0,
              removedAt.timeIntervalSinceReferenceDate.isFinite,
              bytesRemoved >= 0 else {
            throw DraftAttachmentStagingFailureV1.invalidAttachment
        }
        self.stageID = stageID
        self.draftID = draftID
        self.workspaceID = workspaceID
        self.priorRevision = priorRevision
        self.removedAt = removedAt
        self.bytesRemoved = bytesRemoved
    }

    private static let zero = UUID(uuid: (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    ))
}

/// Durable per-item staging adapter.  Capture/import bytes first pass through
/// the disposable scratch lease when one is supplied; only the exact verified
/// bytes are then copied into the draft-owned stage directory.  The manifest
/// is operational recovery state and the canonical item remains the
/// `AttachmentStagingItemV1` written by the workspace writer.
actor DraftAttachmentStagingAdapterV1: DraftContentPromotionPortV1 {
    typealias Clock = @Sendable () -> Date

    static let directoryName = "draft-attachments-v1"
    static let manifestName = "manifest.json"
    static let payloadName = "payload.bin"
    static let quarantineName = "quarantine"

    /// Observes the process-global raw staging root without invoking the
    /// ordinary initializer's directory or manifest publication effects.
    static func observePhotoBackupRoot(applicationSupportURL: URL, workspaceID: WorkspaceID,
        fileManager: FileManager = .default, clock: @escaping Clock = { Date() }) throws
        -> DraftPhotoBackupRootObservationV1 {
        guard applicationSupportURL.isFileURL, workspaceID.rawValue != Self.zero else {
            throw DraftAttachmentStagingFailureV1.invalidRoot
        }
        let support = applicationSupportURL.standardizedFileURL
        let dataRoot = support.appendingPathComponent(OwnedStorageRootKindV1.data.rawValue, isDirectory: true)
        let parent = try DraftStagingRootOwnerV1(rootURL: dataRoot)
        let exists: Bool
        do {
            let lock = try parent.acquire()
            defer { lock.release() }
            try parent.requireNamedRoot()
            exists = try parent.directory([]).exists(Self.directoryName)
        }
        if exists {
            return .existing(try DraftAttachmentStagingAdapterV1(
                photoBackupExistingRoot: support, workspaceID: workspaceID,
                fileManager: fileManager, clock: clock))
        }
        return .absent(DraftPhotoBackupAbsentRootVerificationV1(
            parent: parent, workspaceID: workspaceID))
    }

    private let fileManager: FileManager
    private let applicationSupportURL: URL
    private let rootURL: URL
    private let quarantineURL: URL
    private let workspaceScope: WorkspaceID?
    private let scratchStore: (any ScratchDataLeasePortV1)?
    private let storageLedger: OwnedStorageLedgerV1?
    private let immutableContentWriter: (any DraftImmutableContentWriterV1)?
    private let clock: Clock
    private var manifest: DraftAttachmentStagingManifestV1
    private var operationInFlight = false
    private let rootOwner: DraftStagingRootOwnerV1
    private let initialPublicationReceipt: DraftAttachmentRestorePublicationReceiptV1?

    struct RestorePublicationInput: Sendable {
        let sourceRootURL: URL
        let entries: [DraftAttachmentStagingEntryV1]
        let workspaceID: WorkspaceID
        let sourceManifestSHA256: String
        let restoreID: UUID
    }

    private var publicationKernel: RestorePublicationKernel {
        RestorePublicationKernel(
            fileManager: fileManager, rootURL: rootURL,
            workspaceScope: workspaceScope, clock: clock, owner: rootOwner
        )
    }

    /// Opens an incumbent photo root without the ordinary initializer's
    /// directory, protection, or empty-manifest publication effects.
    init(photoBackupExistingRoot applicationSupportURL: URL, workspaceID: WorkspaceID,
         fileManager: FileManager = .default, clock: @escaping Clock = { Date() }) throws {
        guard applicationSupportURL.isFileURL, workspaceID.rawValue != Self.zero else {
            throw DraftAttachmentStagingFailureV1.invalidRoot
        }
        let support = applicationSupportURL.standardizedFileURL
        let root = support.appendingPathComponent(OwnedStorageRootKindV1.data.rawValue, isDirectory: true)
            .appendingPathComponent(Self.directoryName, isDirectory: true)
        self.fileManager = fileManager; self.applicationSupportURL = support
        rootURL = root; quarantineURL = root.appendingPathComponent(Self.quarantineName, isDirectory: true)
        workspaceScope = workspaceID; scratchStore = nil; storageLedger = nil
        immutableContentWriter = nil; self.clock = clock
        let owner = try DraftStagingRootOwnerV1(rootURL: root)
        rootOwner = owner
        let held = try owner.acquire(); defer { held.release() }
        try owner.requireNamedRoot()
        try ProtectedFilePolicyV1.verify(.stagingDirectory, at: root)
        let quarantine = try owner.directory([Self.quarantineName])
        try quarantine.verifyNamed()
        try ProtectedFilePolicyV1.verify(.stagingDirectory, at: quarantineURL)
        manifest = try DraftStagingRootOwnerV1.ManifestSnapshot(owner: owner).manifest
        initialPublicationReceipt = nil
    }

    init(
        applicationSupportURL: URL,
        workspaceID: WorkspaceID? = nil,
        scratchStore: (any ScratchDataLeasePortV1)? = nil,
        storageLedger: OwnedStorageLedgerV1? = nil,
        immutableContentWriter: (any DraftImmutableContentWriterV1)? = nil,
        fileManager: FileManager = .default,
        clock: @escaping Clock = { Date() },
        restorePublication: RestorePublicationInput? = nil
    ) throws {
        guard applicationSupportURL.isFileURL else {
            throw DraftAttachmentStagingFailureV1.invalidRoot
        }
        if let workspaceID,
           workspaceID.rawValue == Self.zero {
            throw DraftAttachmentStagingFailureV1.wrongWorkspace
        }
        self.fileManager = fileManager
        self.applicationSupportURL = applicationSupportURL.standardizedFileURL
        let dataRoot = applicationSupportURL.standardizedFileURL
            .appendingPathComponent(OwnedStorageRootKindV1.data.rawValue, isDirectory: true)
        let root = dataRoot.appendingPathComponent(Self.directoryName, isDirectory: true)
        self.rootURL = root
        self.quarantineURL = root.appendingPathComponent(Self.quarantineName, isDirectory: true)
        self.workspaceScope = workspaceID
        self.scratchStore = scratchStore
        self.storageLedger = storageLedger
        self.immutableContentWriter = immutableContentWriter
        self.clock = clock

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        let owner = try DraftStagingRootOwnerV1(rootURL: root)
        self.rootOwner = owner
        let initialLock = try owner.acquire()
        defer { initialLock.release() }

        do {
            try fileManager.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let quarantine = try owner.directory([Self.quarantineName], create: true)
            try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: root)
            try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: quarantineURL)
            try quarantine.verifyNamed()
        } catch let failure as ProtectedFilePolicyError
            where failure == .protectedDataUnavailable {
            throw DraftAttachmentStagingFailureV1.protectedDataUnavailable
        } catch {
            throw DraftAttachmentStagingFailureV1.invalidRoot
        }
        var localManifest: DraftAttachmentStagingManifestV1
        let manifestURL = root.appendingPathComponent(Self.manifestName)
        if try owner.directory([]).exists(Self.manifestName) {
            do {
                localManifest = try DraftStagingRootOwnerV1.ManifestSnapshot(owner: owner).manifest
            } catch let failure as DraftAttachmentStagingFailureV1 {
                throw failure
            } catch let failure as ProtectedFilePolicyError
                where failure == .protectedDataUnavailable {
                throw DraftAttachmentStagingFailureV1.protectedDataUnavailable
            } catch {
                throw DraftAttachmentStagingFailureV1.corruptManifest
            }
        } else {
            localManifest = try DraftAttachmentStagingManifestV1(entries: [])
            try Self.writeManifest(
                localManifest,
                to: manifestURL,
                fileManager: fileManager, owner: owner
            )
        }
        let initialReceipt: DraftAttachmentRestorePublicationReceiptV1?
        if let restorePublication {
            // Keep the mutable working manifest local until the synchronous
            // operation has persisted its result. The actor is not published.
            let kernel = RestorePublicationKernel(
                fileManager: fileManager, rootURL: root,
                workspaceScope: workspaceID, clock: clock, owner: owner
            )
            initialReceipt = try kernel.adopt(
                from: restorePublication.sourceRootURL,
                entries: restorePublication.entries,
                workspaceID: restorePublication.workspaceID,
                sourceManifestSHA256: restorePublication.sourceManifestSHA256,
                restoreID: restorePublication.restoreID,
                manifest: &localManifest
            )
        } else {
            initialReceipt = nil
        }
        self.manifest = localManifest
        self.initialPublicationReceipt = initialReceipt
    }

    /// Prepares raw bytes off-actor, then passes a descriptor-owned operation
    /// to the application's retained generation/session authority.
    func readPhotoBackupSnapshot(raw: CheckRunnerPhotoRawReadyV1,
                                committingCheckpoint: FieldDraftCheckpointV1?) async throws -> DraftPhotoRawBackupSnapshotV1 {
        try validateScope(workspaceID: raw.readyItem.workspaceID, draftID: raw.readyItem.draftID, stageID: raw.intent.stageID)
        try beginOperation()
        defer { operationInFlight = false }
        let owner = rootOwner
        let task = Task.detached(priority: .userInitiated) {
            let values = try committingCheckpoint.map { try DraftPhotoRawPromotionValuesV1(checkpoint: $0) }
            guard values.map({ $0.rawReady == raw }) ?? true else { throw DraftAttachmentStagingFailureV1.staleStage }
            let snapshot = try DraftRawPhotoReadSnapshotV1.open(raw: raw, owner: owner, committedEntry: values?.committedEntry)
            try snapshot.verifyBytesAndInspection()
            return try snapshot.backupSnapshot()
        }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }

    /// A clone can retain only an exactly empty incumbent namespace. This
    /// read-only proof uses the existing root owner and census without entering
    /// the actor or creating a staging root during synchronous cold recovery.
    nonisolated func prepareEmptyPhotoBackupVerification() throws
        -> DraftPhotoBackupPreparedVerificationV1 {
        try DraftPhotoBackupPreparedVerificationV1(snapshots: [], owner: rootOwner,
            canonicalStages: [], childStageIDs: [:], committingCheckpoints: [:])
    }

    func preparePhotoBackupVerification(_ snapshots: [DraftPhotoRawBackupSnapshotV1],
        committingCheckpoints: [UUID: FieldDraftCheckpointV1],
        canonicalStages: [AttachmentStagingItemV1], childStageIDs: [UUID: UUID]) async throws
        -> DraftPhotoBackupPreparedVerificationV1 {
        guard snapshots.count <= FieldDraftLimitsV1.maximumStageItems,
              Set(snapshots.map { $0.raw.intent.stageID }).count == snapshots.count,
              Set(snapshots.map { $0.raw.readyItem.draftID }).count == snapshots.count,
              canonicalStages.count <= FieldDraftLimitsV1.maximumStageItems,
              Set(canonicalStages.map(\.stageID)).count == canonicalStages.count,
              childStageIDs.count <= FieldDraftLimitsV1.maximumStageItems,
              Set(childStageIDs.values).count == childStageIDs.count,
              snapshots.allSatisfy({
                  childStageIDs[$0.raw.readyItem.draftID] == $0.raw.intent.stageID
              }),
              Set(committingCheckpoints.keys).isSubset(of: Set(snapshots.map { $0.raw.readyItem.draftID })) else {
            throw DraftAttachmentStagingFailureV1.staleStage
        }
        for (childID, stageID) in childStageIDs {
            guard childID != Self.zero, stageID != Self.zero else {
                throw DraftAttachmentStagingFailureV1.staleStage
            }
        }
        for stage in canonicalStages {
            try stage.validate()
            try validateScope(workspaceID: stage.workspaceID, draftID: stage.draftID, stageID: stage.stageID)
        }
        for snapshot in snapshots {
            try validateScope(workspaceID: snapshot.raw.readyItem.workspaceID,
                draftID: snapshot.raw.readyItem.draftID, stageID: snapshot.raw.intent.stageID)
        }
        try beginOperation()
        defer { operationInFlight = false }
        let owner = rootOwner
        let task = Task.detached(priority: .userInitiated) {
            for expected in snapshots {
                try Task.checkCancellation()
                let values = try committingCheckpoints[expected.raw.readyItem.draftID].map {
                    try DraftPhotoRawPromotionValuesV1(checkpoint: $0)
                }
                guard values.map({ $0.rawReady == expected.raw }) ?? true else { throw DraftAttachmentStagingFailureV1.staleStage }
                let observed = try DraftRawPhotoReadSnapshotV1.open(raw: expected.raw, owner: owner,
                                                                   committedEntry: values?.committedEntry)
                try observed.verifyBytesAndInspection()
                guard try observed.backupSnapshot() == expected else { throw DraftAttachmentStagingFailureV1.staleStage }
            }
            return try DraftPhotoBackupPreparedVerificationV1(snapshots: snapshots, owner: owner,
                canonicalStages: canonicalStages, childStageIDs: childStageIDs,
                committingCheckpoints: committingCheckpoints)
        }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }

    @discardableResult
    func stageRawPhoto(sourceURL: URL, authority: CheckRunnerPhotoRawPublicationAuthorityV1)
        async throws -> FieldDraftCommittedEvidenceV1 {
        guard !authority.adoptsExistingOnly,
              let value = try await performRawPhotoPublication(sourceURL: sourceURL, authority: authority) else {
            throw DraftAttachmentStagingFailureV1.stageNotFound
        }
        return value
    }

    func adoptExistingRawPhoto(authority: CheckRunnerPhotoRawPublicationAuthorityV1)
        async throws -> FieldDraftCommittedEvidenceV1? {
        guard authority.adoptsExistingOnly else { throw DraftAttachmentStagingFailureV1.staleStage }
        return try await performRawPhotoPublication(sourceURL: nil, authority: authority)
    }

    private func performRawPhotoPublication(sourceURL: URL?, authority: CheckRunnerPhotoRawPublicationAuthorityV1)
        async throws -> FieldDraftCommittedEvidenceV1? {
        guard authority.applicationSupportURL.standardizedFileURL == applicationSupportURL else {
            throw DraftAttachmentStagingFailureV1.invalidRoot
        }
        let payload = authority.payload
        try validateScope(workspaceID: payload.workspaceID, draftID: payload.childDraftID,
                          stageID: payload.phase.intent.stageID)
        try beginOperation()
        defer { operationInFlight = false }
        let owner = rootOwner
        let support = applicationSupportURL
        let identity = ObjectIdentifier(self)
        let published = authority.publishedRawReady
        let preparation = Task.detached(priority: .userInitiated) {
            try DraftPreparedRawPhotoPublicationV1.prepare(sourceURL: sourceURL, payload: payload,
                publishedRawReady: published, applicationSupportURL: support,
                adapterIdentity: identity, owner: owner)
        }
        do {
            let prepared = try await withTaskCancellationHandler(operation: {
                try await preparation.value
            }, onCancel: { preparation.cancel() })
            try Task.checkCancellation()
            guard let prepared else { return nil }
            let evidence = try await authority.publish(prepared)
            let lock = try rootOwner.acquire()
            defer { lock.release() }
            try reloadManifest()
            return evidence
        } catch {
            // Physical publication may have succeeded before the canonical
            // write/acknowledgement failed. Re-read durable operational state;
            // never fabricate a receipt or remove those recoverable bytes.
            if let lock = try? rootOwner.acquire() {
                try? reloadManifest()
                lock.release()
            }
            if error is CancellationError { throw DraftAttachmentStagingFailureV1.cancelled }
            throw error
        }
    }

    /// This read capability is issued only for authenticated rawReady with no
    /// existing marked pair. The source URL/picker is never consulted again.
    func normalizeRawPhoto(authority: CheckRunnerPhotoRawReadAuthorityV1)
        async throws -> NormalizedMediaWithSourceFactsV1 {
        guard authority.normalizationAllowed else { throw DraftAttachmentStagingFailureV1.invalidTransition }
        guard let result = try await readRawPhoto(authority: authority, normalize: true) else {
            throw DraftAttachmentStagingFailureV1.invalidTransition
        }
        return result
    }

    /// Reproves the raw publication after a pair-store suspension without
    /// generating outputs or allocating a replacement normalization attempt.
    func verifyRawPhoto(authority: CheckRunnerPhotoRawReadAuthorityV1) async throws {
        let prepared = try await prepareRawPhotoVerification(authority: authority)
        try prepared.withVerificationLock {}
    }

    /// Keeps the exact raw stage and witness open until the application performs
    /// its final G -> raw R -> media R pair-ready publication.
    func prepareRawPhotoVerification(authority: CheckRunnerPhotoRawReadAuthorityV1)
        async throws -> DraftPreparedRawPhotoVerificationV1 {
        guard authority.applicationSupportURL.standardizedFileURL == applicationSupportURL else {
            throw DraftAttachmentStagingFailureV1.invalidRoot
        }
        let raw = authority.rawReady
        try validateScope(workspaceID: raw.readyItem.workspaceID, draftID: raw.readyItem.draftID,
                          stageID: raw.intent.stageID)
        try beginOperation()
        defer { operationInFlight = false }
        let identity = ObjectIdentifier(self), owner = rootOwner, support = applicationSupportURL
        try await authority.validate(adapterIdentity: identity)
        try Task.checkCancellation()
        let preparation = Task.detached(priority: .userInitiated) {
            let snapshot = try DraftRawPhotoReadSnapshotV1.open(raw: raw, owner: owner)
            try snapshot.verifyBytesAndInspection()
            return DraftPreparedRawPhotoVerificationV1(rawReady: raw,
                applicationSupportURL: support, adapterIdentity: identity, snapshot: snapshot)
        }
        do {
            let prepared = try await withTaskCancellationHandler(operation: {
                try await preparation.value
            }, onCancel: { preparation.cancel() })
            try Task.checkCancellation()
            try await authority.validate(adapterIdentity: identity)
            try prepared.recheckBeforeReturn()
            return prepared
        } catch {
            if error is CancellationError { throw DraftAttachmentStagingFailureV1.cancelled }
            throw error
        }
    }

    private func readRawPhoto(authority: CheckRunnerPhotoRawReadAuthorityV1, normalize: Bool)
        async throws -> NormalizedMediaWithSourceFactsV1? {
        guard authority.applicationSupportURL.standardizedFileURL == applicationSupportURL else {
            throw DraftAttachmentStagingFailureV1.invalidRoot
        }
        let raw = authority.rawReady
        try validateScope(workspaceID: raw.readyItem.workspaceID, draftID: raw.readyItem.draftID,
                          stageID: raw.intent.stageID)
        try beginOperation()
        defer { operationInFlight = false }
        let identity = ObjectIdentifier(self), owner = rootOwner
        try await authority.validate(adapterIdentity: identity)
        try Task.checkCancellation()
        let preparation = Task.detached(priority: .userInitiated) { () throws -> NormalizedMediaWithSourceFactsV1? in
            let snapshot = try DraftRawPhotoReadSnapshotV1.open(raw: raw, owner: owner)
            if normalize { return try snapshot.normalize() }
            try snapshot.verifyBytesAndInspection()
            let lock = try owner.acquire()
            defer { lock.release() }
            try snapshot.requireCurrent()
            return nil
        }
        do {
            let normalized = try await withTaskCancellationHandler(operation: {
                try await preparation.value
            }, onCancel: { preparation.cancel() })
            try Task.checkCancellation()
            try await authority.validate(adapterIdentity: identity)
            return normalized
        } catch {
            if error is CancellationError { throw DraftAttachmentStagingFailureV1.cancelled }
            throw error
        }
    }

    /// Photo promotion retains the generic writer and manifest format while
    /// taking every durable time/identity from the original COMMITTING payload.
    func promoteRawPhoto(authority: CheckRunnerPhotoRawPromotionAuthorityV1)
        async throws -> DraftContentReservationV1 {
        guard authority.applicationSupportURL.standardizedFileURL == applicationSupportURL else {
            throw DraftAttachmentStagingFailureV1.invalidRoot
        }
        let checkpoint = authority.committingCheckpoint
        let payload = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(checkpoint)
        try validateScope(workspaceID: payload.workspaceID, draftID: payload.childDraftID,
                          stageID: payload.phase.intent.stageID)
        guard let immutableContentWriter else { throw DraftAttachmentStagingFailureV1.contentWriterUnavailable }
        try beginOperation()
        defer { operationInFlight = false }
        let owner = rootOwner, support = applicationSupportURL, identity = ObjectIdentifier(self)
        let preparation = Task.detached(priority: .userInitiated) {
            try DraftPreparedRawPhotoPromotionV1.prepare(checkpoint: checkpoint,
                applicationSupportURL: support, adapterIdentity: identity, owner: owner)
        }
        do {
            let prepared = try await withTaskCancellationHandler(operation: {
                try await preparation.value
            }, onCancel: { preparation.cancel() })
            try Task.checkCancellation()
            try await authority.validateBeforeImmutableWrite(prepared)
            let writing = Task.detached(priority: .userInitiated) {
                try await prepared.persist(using: immutableContentWriter)
            }
            try await withTaskCancellationHandler(operation: {
                try await writing.value
            }, onCancel: { writing.cancel() })
            try Task.checkCancellation()
            let reservation = try await authority.publish(prepared)
            guard reservation == prepared.reservation else { throw DraftAttachmentStagingFailureV1.reservationMismatch }
            let lock = try rootOwner.acquire()
            defer { lock.release() }
            try reloadManifest()
            return reservation
        } catch {
            // C05 or physical manifest publication can precede failed canonical
            // work/acknowledgement. Keep both for the same frozen attempt's retry.
            if let lock = try? rootOwner.acquire() { try? reloadManifest(); lock.release() }
            if error is CancellationError { throw DraftAttachmentStagingFailureV1.cancelled }
            throw error
        }
    }

    /// Stages a generic attachment without assigning an EvidenceID. The
    /// default mutation identity remains deterministic for the stage.
    @discardableResult
    func stage(
        data: Data,
        draftID: UUID,
        workspaceID: WorkspaceID,
        attachmentKind: DraftAttachmentKindV1,
        stageID: UUID = UUID(),
        mutationID suppliedMutationID: MutationIDV1? = nil,
        mediaType: String? = nil,
        createdAt: Date? = nil
    ) async throws -> AttachmentStagingItemV1 {
        try beginOperation()
        defer { operationInFlight = false }
        do {
            let lock = try rootOwner.acquire()
            defer { lock.release() }
            try reloadManifest()
        }
        try validateScope(workspaceID: workspaceID, draftID: draftID, stageID: stageID)
        guard !data.isEmpty, data.count <= FieldDraftLimitsV1.maximumPayloadBytes else {
            throw DraftAttachmentStagingFailureV1.invalidAttachment
        }
        guard manifest.entries.first(where: { $0.item.stageID == stageID }) == nil else {
            throw DraftAttachmentStagingFailureV1.stageAlreadyExists
        }
        let now = createdAt ?? clock()
        guard now.timeIntervalSinceReferenceDate.isFinite else {
            throw DraftAttachmentStagingFailureV1.invalidAttachment
        }
        let mutationID = try suppliedMutationID ?? MutationIDV1(rawValue: stageID)
        let scratch = try await copyThroughScratch(
            data,
            draftID: draftID,
            stageID: stageID,
            mutationID: mutationID,
            now: now
        )
        var reservation: OwnedStorageReservationV1?
        if let storageLedger {
            let attempt = try OwnedStorageAttemptIDV1(
                workspaceID: workspaceID,
                generationID: draftID,
                mutationID: mutationID
            )
            do {
                reservation = try storageLedger.reserve(
                    attemptID: attempt,
                    requiredBytes: Int64(data.count)
                )
            } catch OwnedStorageLedgerFailureV1.insufficientCapacity {
                throw DraftAttachmentStagingFailureV1.insufficientStorage
            } catch OwnedStorageLedgerFailureV1.capacityUnavailable {
                throw DraftAttachmentStagingFailureV1.insufficientStorage
            }
        }
        defer {
            if let reservation, let storageLedger { storageLedger.release(reservation: reservation) }
        }

        let digest = sha256(scratch.bytes)
        guard digest == sha256(data), scratch.bytes.count == data.count else {
            throw DraftAttachmentStagingFailureV1.digestMismatch
        }
        let rootLock = try rootOwner.acquire()
        defer { rootLock.release() }
        try reloadManifest()
        guard !manifest.entries.contains(where: { $0.item.stageID == stageID }) else {
            throw DraftAttachmentStagingFailureV1.stageAlreadyExists
        }
        let relativePath = Self.relativeDataPath(draftID: draftID, stageID: stageID)
        let directory = rootURL.appendingPathComponent(
            Self.relativeStageDirectory(draftID: draftID, stageID: stageID),
            isDirectory: true
        )
        try Task.checkCancellation()
        guard !DraftStagingRootOwnerV1.pathExists(directory) else {
            throw DraftAttachmentStagingFailureV1.stageAlreadyExists
        }
        let components = Self.relativeStageDirectory(draftID: draftID, stageID: stageID)
            .split(separator: "/").map(String.init)
        let parent = try rootOwner.directory([components[0]], create: true)
        try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: parent.url)
        try parent.verifyNamed()
        guard mkdirat(parent.descriptor, components[1], mode_t(0o700)) == 0 else {
            throw DraftAttachmentStagingFailureV1.stageAlreadyExists
        }
        let createdDirectory = try rootOwner.directory(components)
        var manifestPublicationAttempted = false
        do {
            try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: directory)
            try createdDirectory.verifyNamed()
            let payloadURL = rootURL.appendingPathComponent(relativePath)
            try DraftStagingRootOwnerV1.replaceFile(scratch.bytes, at: payloadURL, directory: createdDirectory)
            let payloadFD = try createdDirectory.openFile(Self.payloadName)
            defer { close(payloadFD) }
            let readBack = try DraftStagingRootOwnerV1.read(payloadFD, count: scratch.bytes.count)
            try createdDirectory.verifyNamed()
            try createdDirectory.verifyFile(payloadFD, name: Self.payloadName)
            guard readBack == scratch.bytes else {
                throw DraftAttachmentStagingFailureV1.digestMismatch
            }
            let digestValue = try ContentDigestV1(
                algorithm: .sha256,
                hexadecimalValue: digest
            )
            let item = try AttachmentStagingItemV1(
                stageID: stageID,
                draftID: draftID,
                workspaceID: workspaceID,
                attachmentKind: attachmentKind,
                scratchLeaseID: scratch.leaseID,
                expectedByteCount: Int64(data.count),
                actualByteCount: Int64(readBack.count),
                contentDigest: digestValue,
                contentReference: nil,
                processingJobID: nil,
                retryClass: .none,
                state: .readyLocal,
                protectionState: .available,
                revision: 1,
                mutationID: mutationID
            )
            let entry = try DraftAttachmentStagingEntryV1(
                item: item,
                relativeDataPath: relativePath,
                mediaType: mediaType ?? Self.defaultMediaType(for: attachmentKind),
                updatedAt: now
            )
            manifest = try replacing(entry)
            manifestPublicationAttempted = true
            try persistManifest()
            return item
        } catch let failure as DraftAttachmentStagingFailureV1 {
            if !manifestPublicationAttempted { try? publicationKernel.removeDirectory(directory, expectedIdentity: createdDirectory.identity) }
            throw failure
        } catch let failure as ProtectedFilePolicyError
            where failure == .protectedDataUnavailable {
            if !manifestPublicationAttempted { try? publicationKernel.removeDirectory(directory, expectedIdentity: createdDirectory.identity) }
            throw DraftAttachmentStagingFailureV1.protectedDataUnavailable
        } catch {
            if !manifestPublicationAttempted { try? publicationKernel.removeDirectory(directory, expectedIdentity: createdDirectory.identity) }
            throw DraftAttachmentStagingFailureV1.cleanupFailed
        }
    }

    @discardableResult
    func stageAttachment(
        _ data: Data,
        draftID: UUID,
        workspaceID: WorkspaceID,
        kind: DraftAttachmentKindV1,
        stageID: UUID = UUID(),
        mutationID: MutationIDV1? = nil,
        mediaType: String? = nil,
        createdAt: Date? = nil
    ) async throws -> AttachmentStagingItemV1 {
        try await stage(
            data: data,
            draftID: draftID,
            workspaceID: workspaceID,
            attachmentKind: kind,
            stageID: stageID,
            mutationID: mutationID,
            mediaType: mediaType,
            createdAt: createdAt
        )
    }

    func item(stageID: UUID) throws -> AttachmentStagingItemV1? {
        let rootLock = try lockAndReload()
        defer { rootLock.release() }
        return manifest.entries.first(where: { $0.item.stageID == stageID })?.item
    }

    func entries(
        workspaceID: WorkspaceID? = nil,
        draftID: UUID? = nil
    ) throws -> [DraftAttachmentStagingEntryV1] {
        let rootLock = try lockAndReload()
        defer { rootLock.release() }
        if let workspaceID, workspaceID.rawValue == Self.zero {
            throw DraftAttachmentStagingFailureV1.wrongWorkspace
        }
        return manifest.entries.filter { entry in
            (workspaceID == nil || entry.item.workspaceID == workspaceID)
                && (draftID == nil || entry.item.draftID == draftID)
        }
    }

    func data(stageID: UUID) throws -> Data {
        let rootLock = try lockAndReload()
        defer { rootLock.release() }
        guard let entry = manifest.entries.first(where: { $0.item.stageID == stageID }) else {
            throw DraftAttachmentStagingFailureV1.stageNotFound
        }
        try denyPhotoOwnership(entry)
        return try verifiedBytes(for: entry)
    }

    func verify(stageID: UUID) throws -> AttachmentStagingItemV1 {
        let rootLock = try lockAndReload()
        defer { rootLock.release() }
        guard let entry = manifest.entries.first(where: { $0.item.stageID == stageID }) else {
            throw DraftAttachmentStagingFailureV1.stageNotFound
        }
        _ = try verifiedBytes(for: entry)
        return entry.item
    }

    /// Removes one item using a durable REMOVE_PENDING edge.  If physical
    /// cleanup is interrupted, the manifest remains nonterminal and recovery
    /// can retry it instead of claiming that bytes were removed.
    @discardableResult
    func remove(
        stageID: UUID,
        expectedRevision: UInt64
    ) throws -> DraftAttachmentStagingRemovalReceiptV1 {
        let rootLock = try lockAndReload()
        defer { rootLock.release() }
        guard let entry = manifest.entries.first(where: { $0.item.stageID == stageID }) else {
            throw DraftAttachmentStagingFailureV1.stageNotFound
        }
        guard entry.item.revision == expectedRevision else {
            throw DraftAttachmentStagingFailureV1.staleStage
        }
        try denyPhotoOwnership(entry)
        try denyPhotoOwnership(entry)
        let pending = try successor(entry.item, state: .removePending)
        manifest = try replacing(try DraftAttachmentStagingEntryV1(
            item: pending,
            relativeDataPath: entry.relativeDataPath,
            mediaType: entry.mediaType,
            updatedAt: clock()
        ))
        try persistManifest()
        let bytes = (try? verifiedBytes(for: entry).count) ?? 0
        let directory = rootURL.appendingPathComponent(entry.relativeDataPath).deletingLastPathComponent()
        do {
            try removeDirectory(directory)
            manifest = try DraftAttachmentStagingManifestV1(entries: manifest.entries
                .filter { $0.item.stageID != stageID })
            try persistManifest()
        } catch {
            throw DraftAttachmentStagingFailureV1.cleanupFailed
        }
        return try DraftAttachmentStagingRemovalReceiptV1(
            stageID: stageID,
            draftID: pending.draftID,
            workspaceID: pending.workspaceID,
            priorRevision: expectedRevision,
            removedAt: clock(),
            bytesRemoved: Int64(bytes)
        )
    }

    /// Moves staged bytes to an app-owned quarantine directory and records the
    /// ORPHAN_QUARANTINED state.  No content association is created.
    @discardableResult
    func quarantine(stageID: UUID, expectedRevision: UInt64) throws -> AttachmentStagingItemV1 {
        let rootLock = try lockAndReload()
        defer { rootLock.release() }
        return try quarantineUnderLock(stageID: stageID, expectedRevision: expectedRevision)
    }

    private func quarantineUnderLock(stageID: UUID, expectedRevision: UInt64) throws -> AttachmentStagingItemV1 {
        guard let entry = manifest.entries.first(where: { $0.item.stageID == stageID }) else {
            throw DraftAttachmentStagingFailureV1.stageNotFound
        }
        guard entry.item.revision == expectedRevision else {
            throw DraftAttachmentStagingFailureV1.staleStage
        }
        let quarantined = try successor(entry.item, state: .orphanQuarantined)
        try denyPhotoOwnership(entry)
        let source = rootURL.appendingPathComponent(entry.relativeDataPath).deletingLastPathComponent()
        let destinationName = "stage-\(stageID.uuidString.lowercased())"
        let destination = quarantineURL.appendingPathComponent(destinationName, isDirectory: true)
        guard !DraftStagingRootOwnerV1.pathExists(destination) else {
            throw DraftAttachmentStagingFailureV1.staleStage
        }
        do {
            if fileManager.fileExists(atPath: source.path) {
                let parts = entry.relativeDataPath.split(separator: "/").dropLast().map(String.init)
                let sourceParent = try rootOwner.directory(Array(parts.dropLast()))
                let sourceDirectory = try rootOwner.directory(parts)
                let destinationParent = try rootOwner.directory([Self.quarantineName])
                guard !(try sourceDirectory.exists("raw-publication.json")) else {
                    throw DraftAttachmentStagingFailureV1.invalidTransition
                }
                guard Set(try fileManager.contentsOfDirectory(atPath: source.path))
                    .isSubset(of: [Self.payloadName]) else {
                    throw DraftAttachmentStagingFailureV1.cleanupFailed
                }
                try sourceDirectory.verifyNamed()
                guard let sourceName = parts.last,
                      renameatx_np(sourceParent.descriptor, sourceName, destinationParent.descriptor,
                                   destinationName, UInt32(RENAME_EXCL)) == 0,
                      fsync(sourceParent.descriptor) == 0, fsync(destinationParent.descriptor) == 0 else {
                    throw DraftAttachmentStagingFailureV1.cleanupFailed
                }
                try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: destination)
            }
            let entry = try DraftAttachmentStagingEntryV1(
                item: quarantined,
                relativeDataPath: "quarantine/\(destinationName)/\(Self.payloadName)",
                mediaType: entry.mediaType,
                updatedAt: clock()
            )
            manifest = try replacing(entry)
            try persistManifest()
            return quarantined
        } catch let failure as DraftAttachmentStagingFailureV1 {
            throw failure
        } catch {
            throw DraftAttachmentStagingFailureV1.cleanupFailed
        }
    }

    /// C36's content port. Exact staged bytes are first handed to the sole
    /// C05 writer and read back there; only that writer receipt may seed the
    /// immutable reservation and private-manifest transition.
    func promote(
        plan: DraftCommitPlanV1,
        items: [AttachmentStagingItemV1],
        reservationMutationIDs: [UUID: MutationIDV1]
    ) async throws -> [DraftContentReservationV1] {
        try beginOperation()
        defer { operationInFlight = false }
        try plan.validate()
        let stageIDs = Set(items.map(\.stageID))
        let mutationIDs = Array(reservationMutationIDs.values)
        guard !items.isEmpty,
              items.count <= FieldDraftLimitsV1.maximumStageItems,
              stageIDs.count == items.count,
              items.allSatisfy({ $0.workspaceID == plan.workspaceID
                  && $0.draftID == plan.draftID
                  && $0.state == .readyLocal
                  && $0.stageSHA256 != "" }) else {
            throw DraftAttachmentStagingFailureV1.promotionRequiresReady
        }
        guard reservationMutationIDs.count == items.count,
              Set(reservationMutationIDs.keys) == stageIDs,
              Set(mutationIDs).count == mutationIDs.count,
              mutationIDs.allSatisfy({ $0 != plan.mutationID }) else {
            throw DraftAttachmentStagingFailureV1.reservationMismatch
        }
        guard let immutableContentWriter else {
            throw DraftAttachmentStagingFailureV1.contentWriterUnavailable
        }
        let snapshotLock = try rootOwner.acquire()
        let current: [(entry: DraftAttachmentStagingEntryV1, bytes: Data)]
        do {
        try reloadManifest()
        current = try items.map { item -> (entry: DraftAttachmentStagingEntryV1, bytes: Data) in
            guard let entry = manifest.entries.first(where: { $0.item.stageID == item.stageID }),
                  entry.item == item else {
                throw DraftAttachmentStagingFailureV1.staleStage
            }
            try denyPhotoOwnership(entry)
            let bytes = try verifiedBytes(for: entry)
            return (entry: entry, bytes: bytes)
        }
        snapshotLock.release()
        } catch { snapshotLock.release(); throw error }
        guard Set(current.map { $0.entry.item.stageSHA256 }).sorted() == plan.stageDigests else {
            throw DraftAttachmentStagingFailureV1.reservationMismatch
        }
        let now = clock()
        var reservations: [DraftContentReservationV1] = []
        var referenceByStageID: [UUID: ContentReferenceV1] = [:]
        for currentItem in current.sorted(by: {
            $0.entry.item.stageID.uuidString.lowercased()
                < $1.entry.item.stageID.uuidString.lowercased()
        }) {
            let entry = currentItem.entry
            let bytes = currentItem.bytes
            guard let digest = entry.item.contentDigest else {
                throw DraftAttachmentStagingFailureV1.digestMismatch
            }
            guard let reservationMutationID = reservationMutationIDs[entry.item.stageID] else {
                throw DraftAttachmentStagingFailureV1.reservationMismatch
            }
            let contentID = Self.contentID(
                workspaceID: plan.workspaceID,
                digest: digest
            )
            let request: DraftImmutableContentWriteRequestV1
            do {
                request = try DraftImmutableContentWriteRequestV1(
                    workspaceID: plan.workspaceID,
                    contentID: contentID,
                    digest: digest,
                    byteLength: Int64(bytes.count),
                    mediaType: entry.mediaType,
                    mutationID: reservationMutationID,
                    createdAt: Self.iso8601(now)
                )
            } catch {
                throw DraftAttachmentStagingFailureV1.contentWriterRejected
            }
            let writerReceipt: DraftImmutableContentWriteReceiptV1
            do {
                writerReceipt = try await immutableContentWriter.persistImmutableOriginal(
                    bytes: bytes,
                    request: request
                )
                try writerReceipt.validate(request: request, bytes: bytes)
            } catch let failure as DraftImmutableContentWriterFailureV1 {
                switch failure {
                case .byteLengthMismatch:
                    throw DraftAttachmentStagingFailureV1.byteLengthMismatch
                case .digestMismatch:
                    throw DraftAttachmentStagingFailureV1.digestMismatch
                default:
                    throw DraftAttachmentStagingFailureV1.contentWriterRejected
                }
            }
            guard writerReceipt.mutationID == reservationMutationID else {
                throw DraftAttachmentStagingFailureV1.reservationMismatch
            }
            let reference = try ContentReferenceV1(
                workspaceID: writerReceipt.workspaceID.rawValue.uuidString.lowercased(),
                contentID: writerReceipt.contentID,
                byteLength: writerReceipt.byteLength,
                mediaType: writerReceipt.mediaType,
                digests: try ContentDigestSetV1([writerReceipt.digest]),
                byteRole: writerReceipt.byteRole,
                createdAt: writerReceipt.createdAt
            )
            referenceByStageID[entry.item.stageID] = reference
            let locator = try ContentLocatorV1(
                locatorID: writerReceipt.locatorID,
                workspaceID: reference.workspaceID,
                contentID: writerReceipt.contentID,
                locatorRevision: 0,
                contentDigest: writerReceipt.digest,
                expectedByteLength: reference.byteLength
            )
            reservations.append(try DraftContentReservationV1(
                reservationID: Self.deterministicUUID(
                    "reservation\u{1f}\(plan.planSHA256)\u{1f}\(entry.item.stageID.uuidString.lowercased())"
                ),
                workspaceID: plan.workspaceID,
                draftID: plan.draftID,
                stageID: entry.item.stageID,
                commitPlanSHA256: plan.planSHA256,
                mutationID: writerReceipt.mutationID,
                contentDigest: writerReceipt.digest,
                locator: locator,
                createdAt: now,
                reviewAfter: now.addingTimeInterval(3_600),
                reconciliationState: .reserved,
                revision: 1
            ))
        }
        let reservationByStage = Dictionary(uniqueKeysWithValues: reservations.map {
            ($0.stageID, $0)
        })
        try Task.checkCancellation()
        let rootLock = try rootOwner.acquire()
        defer { rootLock.release() }
        try reloadManifest()
        for prior in current {
            guard manifest.entries.first(where: { $0.item.stageID == prior.entry.item.stageID }) == prior.entry else {
                throw DraftAttachmentStagingFailureV1.staleStage
            }
            try denyPhotoOwnership(prior.entry)
            guard try verifiedBytes(for: prior.entry) == prior.bytes else {
                throw DraftAttachmentStagingFailureV1.digestMismatch
            }
        }
        var nextEntries = manifest.entries
        for index in nextEntries.indices {
            guard let reservation = reservationByStage[nextEntries[index].item.stageID] else {
                continue
            }
            let old = nextEntries[index]
            guard let contentReference = referenceByStageID[old.item.stageID] else {
                throw DraftAttachmentStagingFailureV1.contentWriterRejected
            }
            let committed = try successor(
                old.item,
                state: .committed,
                contentDigest: reservation.contentDigest,
                contentReference: contentReference
            )
            nextEntries[index] = try DraftAttachmentStagingEntryV1(
                item: committed,
                relativeDataPath: old.relativeDataPath,
                mediaType: old.mediaType,
                updatedAt: now
            )
        }
        let nextManifest = try DraftAttachmentStagingManifestV1(entries: nextEntries)
        try Self.writeManifest(
            nextManifest,
            to: rootURL.appendingPathComponent(Self.manifestName),
            fileManager: fileManager, owner: rootOwner
        )
        try reloadManifest()
        guard try manifest.canonicalBytes() == nextManifest.canonicalBytes() else {
            throw DraftAttachmentStagingFailureV1.corruptManifest
        }
        return reservations
    }

    func quarantine(
        reservations: [DraftContentReservationV1],
        for plan: DraftDiscardPlanV1
    ) async throws {
        let rootLock = try lockAndReload()
        defer { rootLock.release() }
        try plan.validate()
        guard reservations.allSatisfy({ $0.workspaceID == plan.workspaceID
            && $0.draftID == plan.draftID
            && plan.reservationIDs.contains($0.reservationID) }) else {
            throw DraftAttachmentStagingFailureV1.reservationMismatch
        }
        for reservation in reservations {
            guard let entry = manifest.entries.first(where: { $0.item.stageID == reservation.stageID }) else {
                throw DraftAttachmentStagingFailureV1.stageNotFound
            }
            try denyPhotoOwnership(entry)
        }
        for reservation in reservations {
            guard let entry = manifest.entries.first(where: { $0.item.stageID == reservation.stageID }) else {
                throw DraftAttachmentStagingFailureV1.stageNotFound
            }
            _ = try quarantineUnderLock(stageID: entry.item.stageID, expectedRevision: entry.item.revision)
        }
    }

    /// Recovery is bounded and fail-closed: missing/tampered bytes become a
    /// retryable/final state, never READY_LOCAL.
    @discardableResult
    func reconcile() throws -> [AttachmentStagingItemV1] {
        let rootLock = try lockAndReload()
        defer { rootLock.release() }
        var updated = manifest.entries
        for index in updated.indices {
            let entry = updated[index]
            if hasPhotoOwnership(entry) { continue }
            do {
                _ = try verifiedBytes(for: entry)
            } catch {
                let state: AttachmentStagingStateV1 =
                    entry.item.state == .removePending ? .removePending : .failedFinal
                let retry: DraftStageRetryClassV1 = state == .failedFinal ? .final : entry.item.retryClass
                let item = try successor(entry.item, state: state, retryClass: retry, actualByteCount: nil)
                updated[index] = try DraftAttachmentStagingEntryV1(
                    item: item,
                    relativeDataPath: entry.relativeDataPath,
                    mediaType: entry.mediaType,
                    updatedAt: clock()
                )
            }
        }
        manifest = try DraftAttachmentStagingManifestV1(entries: updated)
        try persistManifest()
        return manifest.entries.map(\.item)
    }

    func erase(workspaceID: WorkspaceID? = nil) throws {
        let rootLock = try lockAndReload()
        defer { rootLock.release() }
        let retained = manifest.entries.filter { entry in
            guard let workspaceID else { return false }
            return entry.item.workspaceID != workspaceID
        }
        let removed = manifest.entries.filter { entry in
            guard let workspaceID else { return true }
            return entry.item.workspaceID == workspaceID
        }
        try removed.forEach(denyPhotoOwnership)
        for entry in removed {
            let directory = rootURL.appendingPathComponent(entry.relativeDataPath).deletingLastPathComponent()
            try removeDirectory(directory)
        }
        manifest = try DraftAttachmentStagingManifestV1(entries: retained)
        try persistManifest()
    }
}

// MARK: - C36 restore publication seam

/// Durable before/after values for the existing global raw owner. This value
/// grants no filesystem effect. The restore owner must persist it with the
/// original generation/operation binding before preparing any new raw bytes.
struct DraftPhotoRestoreRawTransitionV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let before: DraftAttachmentStagingManifestV1
    let after: DraftAttachmentStagingManifestV1
    let newStageIDs: [UUID]
    let reusedStageIDs: [UUID]
    /// Exact generic ready/committed destination stages. These have only a
    /// payload file; all other transitioned stages retain the raw witness.
    let genericStageIDs: [UUID]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, before, after, newStageIDs, reusedStageIDs, genericStageIDs
    }

    fileprivate init(before: DraftAttachmentStagingManifestV1,
        sourcePlan: CheckRunnerPhotoBackupRestorePlanV1,
        sourceHistory: CheckRunnerPhotoBackupHistoryV1,
        currentSnapshots: [DraftPhotoRawBackupSnapshotV1],
        retainedCurrentStageIDs: Set<UUID>,
        genericEntries: [DraftAttachmentStagingEntryV1] = []) throws {
        let failure = DraftAttachmentStagingFailureV1.staleStage
        try before.validate()
        do {
            let binding = try CheckRunnerPhotoRestoreMemberBindingV1(plan: sourcePlan)
            guard try binding.resolve(history: sourceHistory) == sourcePlan else { throw failure }
        } catch { throw failure }
        guard sourcePlan.source == sourceHistory.source,
              Set(sourcePlan.rawPublications.map { $0.physicalEntry.entry.item.stageID }).count
                == sourcePlan.rawPublications.count,
              Set(currentSnapshots.map { $0.raw.intent.stageID }).count == currentSnapshots.count,
              Set(sourceHistory.children.map { $0.payload.phase.intent.stageID }).count
                == sourceHistory.children.count,
              currentSnapshots.allSatisfy({ $0.manifestSHA256 == before.manifestSHA256 }) else { throw failure }
        let old = Dictionary(uniqueKeysWithValues: before.entries.map { ($0.item.stageID, $0) })
        let current = Dictionary(uniqueKeysWithValues: currentSnapshots.map { ($0.raw.intent.stageID, $0) })
        let sourceChildren = Dictionary(uniqueKeysWithValues: sourceHistory.children.map {
            ($0.payload.phase.intent.stageID, $0)
        })
        let sourceIDs = Set(sourcePlan.rawPublications.map { $0.physicalEntry.entry.item.stageID })
        guard retainedCurrentStageIDs == Set(old.keys).subtracting(sourceIDs),
              Set(current.keys).isSubset(of: Set(old.keys)) else { throw failure }
        var updated = old
        var added: [UUID] = [], reused: [UUID] = []
        for publication in sourcePlan.rawPublications {
            let entry = publication.physicalEntry.entry
            let stageID = entry.item.stageID
            guard let child = sourceChildren[stageID], let raw = child.raw,
                  raw.readyItem.draftID == entry.item.draftID,
                  raw.readyItem.workspaceID == entry.item.workspaceID,
                  try FieldDraftCanonicalCodecV1.decode(CheckRunnerPhotoRawReadyV1.self,
                    from: publication.witnessBytes) == raw else { throw failure }
            let ready = try DraftAttachmentStagingEntryV1(item: raw.readyItem,
                relativeDataPath: DraftAttachmentStagingAdapterV1.relativeDataPath(
                    draftID: raw.readyItem.draftID, stageID: stageID),
                mediaType: raw.inspection.sourceMediaType, updatedAt: raw.intent.stageCreatedAt)
            let promotion = try child.committingCheckpoint.map {
                try DraftPhotoRawPromotionValuesV1(checkpoint: $0)
            }
            func admitted(_ candidate: DraftAttachmentStagingEntryV1) -> Bool {
                candidate == ready || promotion.map { candidate == $0.committedEntry } == true
            }
            guard admitted(entry), promotion.map({ $0.rawReady == raw }) ?? true else { throw failure }
            if let previous = old[stageID] {
                guard let observed = current[stageID], observed.raw == raw,
                      observed.physicalEntry.entry == previous, admitted(previous) else { throw failure }
                // The exact original witness and payload remain reusable. The
                // bound after image restores the archive's physical phase/time;
                // the persisted before image makes that transition reversible.
                reused.append(stageID)
            } else {
                guard current[stageID] == nil else { throw failure }
                added.append(stageID)
            }
            updated[stageID] = entry
        }
        let genericIDs = Set(genericEntries.map { $0.item.stageID })
        guard genericIDs.count == genericEntries.count,
              genericIDs.isDisjoint(with: sourceIDs),
              genericIDs.isDisjoint(with: Set(current.keys)) else { throw failure }
        for requested in genericEntries {
            let item = requested.item
            let path = DraftAttachmentStagingAdapterV1.relativeDataPath(draftID: item.draftID, stageID: item.stageID)
            guard requested.relativeDataPath == path,
                  item.state == .readyLocal || item.state == .committed,
                  let count = item.actualByteCount, count > 0,
                  count <= Int64(FieldDraftLimitsV1.maximumPayloadBytes),
                  item.contentDigest?.algorithm == .sha256 else { throw failure }
            if let previous = old[item.stageID] {
                // Exact incumbent metadata/time are retained. Reuse never
                // rebases an older or different canonical generic stage.
                guard previous.item == item, previous.relativeDataPath == path else { throw failure }
                reused.append(item.stageID)
                updated[item.stageID] = previous
            } else {
                added.append(item.stageID)
                updated[item.stageID] = requested
            }
        }
        schemaVersion = 1
        self.before = before
        genericStageIDs = genericIDs.sorted { $0.uuidString < $1.uuidString }
        after = try DraftAttachmentStagingManifestV1(entries: Array(updated.values))
        newStageIDs = added.sorted { $0.uuidString < $1.uuidString }
        reusedStageIDs = reused.sorted { $0.uuidString < $1.uuidString }
        try validate()
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        before = try values.decode(DraftAttachmentStagingManifestV1.self, forKey: .before)
        after = try values.decode(DraftAttachmentStagingManifestV1.self, forKey: .after)
        newStageIDs = try values.decode([UUID].self, forKey: .newStageIDs)
        reusedStageIDs = try values.decode([UUID].self, forKey: .reusedStageIDs)
        genericStageIDs = try values.decodeIfPresent([UUID].self, forKey: .genericStageIDs) ?? []
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(before, forKey: .before); try values.encode(after, forKey: .after)
        try values.encode(newStageIDs, forKey: .newStageIDs)
        try values.encode(reusedStageIDs, forKey: .reusedStageIDs)
        // Preserve the original all-photo canonical representation.
        if !genericStageIDs.isEmpty { try values.encode(genericStageIDs, forKey: .genericStageIDs) }
    }

    func validate() throws {
        try before.validate(); try after.validate()
        let failure = DraftAttachmentStagingFailureV1.corruptManifest
        let old = Dictionary(uniqueKeysWithValues: before.entries.map { ($0.item.stageID, $0) })
        let new = Dictionary(uniqueKeysWithValues: after.entries.map { ($0.item.stageID, $0) })
        let added = Set(newStageIDs), reused = Set(reusedStageIDs)
        guard schemaVersion == 1,
              newStageIDs == newStageIDs.sorted(by: { $0.uuidString < $1.uuidString }),
              reusedStageIDs == reusedStageIDs.sorted(by: { $0.uuidString < $1.uuidString }),
              added.count == newStageIDs.count, reused.count == reusedStageIDs.count,
              added.isDisjoint(with: reused),
              Set(old.keys).isSubset(of: Set(new.keys)),
              added == Set(new.keys).subtracting(old.keys),
              reused.isSubset(of: Set(old.keys)),
              old.allSatisfy({ reused.contains($0.key) || new[$0.key] == $0.value }),
              genericStageIDs == genericStageIDs.sorted(by: { $0.uuidString < $1.uuidString }),
              Set(genericStageIDs).count == genericStageIDs.count,
              Set(genericStageIDs).isSubset(of: added.union(reused)),
              added.union(reused).subtracting(genericStageIDs)
                .allSatisfy({ new[$0]?.item.attachmentKind == .photo }) else { throw failure }
        for id in genericStageIDs {
            guard let entry = new[id], let count = entry.item.actualByteCount,
                  count > 0, count <= Int64(FieldDraftLimitsV1.maximumPayloadBytes),
                  entry.item.state == .readyLocal || entry.item.state == .committed,
                  entry.item.contentDigest?.algorithm == .sha256,
                  entry.relativeDataPath == DraftAttachmentStagingAdapterV1.relativeDataPath(
                    draftID: entry.item.draftID, stageID: id),
                  !reused.contains(id) || entry == old[id] else { throw failure }
        }
    }
}

/// The durable inode census of one restore operation. Paths inside the private
/// container and their possible public placements are derived from the exact
/// raw transition. A decoded receipt alone grants no filesystem authority.
struct DraftPhotoRestoreRawOwnershipV1: Codable, Equatable, Sendable {
    struct Node: Codable, Equatable, Sendable {
        let path: String
        let directory: Bool
        let device: UInt64
        let inode: UInt64
        let linkCount: UInt64
        let byteCount: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64
        let sha256: String?
        let claimPath: String?

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case path, directory, device, inode, linkCount, byteCount
            case modifiedSeconds, modifiedNanoseconds, changedSeconds, changedNanoseconds, sha256, claimPath
        }

        fileprivate init(path: String, directory: Bool, facts: StreamingArchiveSourceSnapshotV1,
            sha256: String? = nil, claimPath: String? = nil) {
            self.path = path; self.directory = directory; device = facts.device; inode = facts.inode
            linkCount = facts.linkCount; byteCount = facts.byteCount
            modifiedSeconds = facts.modifiedSeconds; modifiedNanoseconds = facts.modifiedNanoseconds
            changedSeconds = facts.changedSeconds; changedNanoseconds = facts.changedNanoseconds
            self.sha256 = sha256; self.claimPath = claimPath
        }

        init(from decoder: Decoder) throws {
            try ClosedContractDecodingV1.rejectUnknownKeys(decoder,
                allowed: Set(CodingKeys.allCases.map(\.rawValue)))
            let c = try decoder.container(keyedBy: CodingKeys.self)
            path = try c.decode(String.self, forKey: .path)
            directory = try c.decode(Bool.self, forKey: .directory)
            device = try c.decode(UInt64.self, forKey: .device); inode = try c.decode(UInt64.self, forKey: .inode)
            linkCount = try c.decode(UInt64.self, forKey: .linkCount)
            byteCount = try c.decode(Int64.self, forKey: .byteCount)
            modifiedSeconds = try c.decode(Int64.self, forKey: .modifiedSeconds)
            modifiedNanoseconds = try c.decode(Int64.self, forKey: .modifiedNanoseconds)
            changedSeconds = try c.decode(Int64.self, forKey: .changedSeconds)
            changedNanoseconds = try c.decode(Int64.self, forKey: .changedNanoseconds)
            sha256 = try c.decodeIfPresent(String.self, forKey: .sha256)
            claimPath = try c.decodeIfPresent(String.self, forKey: .claimPath)
        }

        fileprivate func matches(_ value: stat) -> Bool {
            guard device == UInt64(value.st_dev), inode == UInt64(value.st_ino),
                  value.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG) else { return false }
            // A named directory's own children change during this operation.
            // Its exact child census is checked separately; its inode never rebases.
            if directory { return true }
            return value.st_nlink == 1 && linkCount == 1 && byteCount == value.st_size
                && modifiedSeconds == Int64(value.st_mtimespec.tv_sec)
                && modifiedNanoseconds == Int64(value.st_mtimespec.tv_nsec)
                && changedSeconds == Int64(value.st_ctimespec.tv_sec)
                && changedNanoseconds == Int64(value.st_ctimespec.tv_nsec)
        }

        fileprivate func reservingClaim(restoreID: UUID) -> Self {
            let components = path.split(separator: "/").map(String.init)
            let parent = components.dropLast().joined(separator: "/")
            let basename = ".photo-restore-claim-\(restoreID.uuidString.lowercased())-"
                + "\(String(device, radix: 16))-\(String(inode, radix: 16))-\(directory ? "d" : "f")"
            let claim = parent.isEmpty ? basename : "\(parent)/\(basename)"
            return .init(path: path, directory: directory,
                facts: .init(device: device, inode: inode, linkCount: linkCount, byteCount: byteCount,
                    modifiedSeconds: modifiedSeconds, modifiedNanoseconds: modifiedNanoseconds,
                    changedSeconds: changedSeconds, changedNanoseconds: changedNanoseconds),
                sha256: sha256, claimPath: claim)
        }

        /// A rename may change ctime. The original inode, type, link count,
        /// length and mtime plus the recorded digest authenticate a cold claim;
        /// its current complete facts are then frozen for the final named check.
        fileprivate func admitsClaim(_ candidate: Self) -> Bool {
            guard claimPath == candidate.path, candidate.claimPath == nil,
                  directory == candidate.directory, device == candidate.device, inode == candidate.inode else {
                return false
            }
            if directory { return candidate.sha256 == nil }
            return linkCount == 1 && candidate.linkCount == 1 && byteCount == candidate.byteCount
                && modifiedSeconds == candidate.modifiedSeconds
                && modifiedNanoseconds == candidate.modifiedNanoseconds
                && sha256 != nil && sha256 == candidate.sha256
        }

        fileprivate func strictlyMatches(_ value: stat) -> Bool {
            device == UInt64(value.st_dev) && inode == UInt64(value.st_ino)
                && value.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG)
                && linkCount == UInt64(value.st_nlink) && byteCount == value.st_size
                && modifiedSeconds == Int64(value.st_mtimespec.tv_sec)
                && modifiedNanoseconds == Int64(value.st_mtimespec.tv_nsec)
                && changedSeconds == Int64(value.st_ctimespec.tv_sec)
                && changedNanoseconds == Int64(value.st_ctimespec.tv_nsec)
        }

        /// The final unlink/rmdir changes link count and ctime. A retained
        /// descriptor proves that the exact admitted inode lost its last name;
        /// a swapped-aside inode would remain linked and fail this check.
        fileprivate func provesUnlinked(_ value: stat) -> Bool {
            device == UInt64(value.st_dev) && inode == UInt64(value.st_ino)
                && value.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG)
                && value.st_nlink == 0
        }
    }

    let schemaVersion: Int
    let restoreID: UUID
    let plannedBindingSHA256: String
    let transition: DraftPhotoRestoreRawTransitionV1
    let beforeNodes: [Node]
    let createdNodes: [Node]
    var privateName: String { ".photo-restore-\(restoreID.uuidString.lowercased())" }
    var sha256: String { get throws { CanonicalJSONV1.sha256(try FieldDraftCanonicalCodecV1.encode(self)) } }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, restoreID, plannedBindingSHA256, transition, beforeNodes, createdNodes
    }

    fileprivate init(restoreID: UUID, plannedBindingSHA256: String,
        transition: DraftPhotoRestoreRawTransitionV1, beforeNodes: [Node], createdNodes: [Node]) throws {
        schemaVersion = 1; self.restoreID = restoreID; self.plannedBindingSHA256 = plannedBindingSHA256
        self.transition = transition; self.beforeNodes = beforeNodes.sorted { $0.path < $1.path }
        self.createdNodes = createdNodes.map { $0.reservingClaim(restoreID: restoreID) }
            .sorted { $0.path < $1.path }
        try validate()
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        restoreID = try c.decode(UUID.self, forKey: .restoreID)
        plannedBindingSHA256 = try c.decode(String.self, forKey: .plannedBindingSHA256)
        transition = try c.decode(DraftPhotoRestoreRawTransitionV1.self, forKey: .transition)
        beforeNodes = try c.decode([Node].self, forKey: .beforeNodes)
        createdNodes = try c.decode([Node].self, forKey: .createdNodes)
        try validate()
    }

    func validate() throws {
        let failure = DraftAttachmentStagingFailureV1.corruptManifest
        try transition.validate()
        guard schemaVersion == 1, restoreID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(plannedBindingSHA256),
              beforeNodes.count <= FieldDraftLimitsV1.maximumStageItems * 5 + 3,
              createdNodes.count <= FieldDraftLimitsV1.maximumStageItems * 4 + 1,
              beforeNodes == beforeNodes.sorted(by: { $0.path < $1.path }),
              createdNodes == createdNodes.sorted(by: { $0.path < $1.path }),
              Set(beforeNodes.map(\.path)).count == beforeNodes.count,
              Set(createdNodes.map(\.path)).count == createdNodes.count,
              beforeNodes.contains(where: { $0.path == "." && $0.directory }),
              beforeNodes.contains(where: { $0.path == DraftAttachmentStagingAdapterV1.manifestName && !$0.directory }),
              beforeNodes.allSatisfy({ $0.sha256 == nil && $0.claimPath == nil }),
              createdNodes.allSatisfy({ $0.claimPath != nil }),
              Set(createdNodes.compactMap(\.claimPath)).count == createdNodes.count else { throw failure }
        for node in beforeNodes + createdNodes {
            guard node.inode != 0, node.byteCount >= 0,
                  (node.directory || node.linkCount == 1),
                  (0..<1_000_000_000).contains(node.modifiedNanoseconds),
                  (0..<1_000_000_000).contains(node.changedNanoseconds) else { throw failure }
            if node.path != "." {
                let components = node.path.split(separator: "/", omittingEmptySubsequences: false)
                guard components.count <= 4 else { throw failure }
                for component in components { try DraftStagingRootOwnerV1.component(String(component)) }
            }
            if let claimPath = node.claimPath {
                let claim = claimPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
                let original = node.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
                guard claim.count == original.count, claim.dropLast() == original.dropLast(),
                      node.reservingClaim(restoreID: restoreID).claimPath == claimPath else { throw failure }
                for component in claim { try DraftStagingRootOwnerV1.component(component) }
            }
        }
        let allOriginalPaths = Set((beforeNodes + createdNodes).map(\.path))
        guard Set(createdNodes.compactMap(\.claimPath)).isDisjoint(with: allOriginalPaths) else { throw failure }
        var expected: [String: Bool] = [privateName: true]
        let added = Set(transition.newStageIDs)
        for entry in transition.after.entries where added.contains(entry.item.stageID) {
            let relative = DraftAttachmentStagingAdapterV1.relativeStageDirectory(
                draftID: entry.item.draftID, stageID: entry.item.stageID)
            let parent = String(relative.split(separator: "/")[0])
            expected["\(privateName)/\(parent)"] = true
            expected["\(privateName)/\(relative)"] = true
            expected["\(privateName)/\(relative)/payload.bin"] = false
            if !transition.genericStageIDs.contains(entry.item.stageID) {
                expected["\(privateName)/\(relative)/raw-publication.json"] = false
            }
        }
        guard Set(createdNodes.map(\.path)) == Set(expected.keys),
              createdNodes.allSatisfy({ node in
                  node.directory == expected[node.path]
                    && (node.directory ? node.sha256 == nil
                        : node.sha256.map(StoreMigrationCanonicalJSONV1.isLowercaseSHA256) == true)
              }),
              !beforeNodes.contains(where: { $0.path == privateName || $0.path.hasPrefix(privateName + "/") }) else {
            throw failure
        }
        let old = Dictionary(uniqueKeysWithValues: beforeNodes.map { ($0.path, $0) })
        for node in beforeNodes where node.path != "." {
            let parts = node.path.split(separator: "/")
            let parent = parts.count == 1 ? "." : parts.dropLast().joined(separator: "/")
            guard old[parent]?.directory == true else { throw failure }
        }
    }
}

/// Immutable proof of the incumbent staging namespace that a configuration
/// clone will physically retire. The plan contains no arbitrary root path:
/// every placement is relative to the adapter's descriptor-anchored root.
struct DraftConfigurationCloneRetirementPlanV1: Codable, Equatable, Sendable {
    typealias Node = DraftPhotoRestoreRawOwnershipV1.Node

    static let schemaVersion = 1
    fileprivate static let replacementQuarantineName = ".replacement-quarantine"
    private static let zero = UUID(uuid: (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    ))

    let schemaVersion: Int
    let restoreID: UUID
    let workspaceID: WorkspaceID
    let before: DraftAttachmentStagingManifestV1
    let beforeNodes: [Node]
    let movedRoots: [String]

    var privateName: String {
        ".clone-retirement-\(restoreID.uuidString.lowercased())"
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, restoreID, workspaceID, before, beforeNodes, movedRoots
    }

    fileprivate init(restoreID: UUID, workspaceID: WorkspaceID,
        before: DraftAttachmentStagingManifestV1, beforeNodes: [Node], movedRoots: [String]) throws {
        schemaVersion = Self.schemaVersion
        self.restoreID = restoreID; self.workspaceID = workspaceID; self.before = before
        self.beforeNodes = beforeNodes.sorted { $0.path < $1.path }
        self.movedRoots = movedRoots.sorted()
        try validate()
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        restoreID = try values.decode(UUID.self, forKey: .restoreID)
        workspaceID = try values.decode(WorkspaceID.self, forKey: .workspaceID)
        before = try values.decode(DraftAttachmentStagingManifestV1.self, forKey: .before)
        beforeNodes = try values.decode([Node].self, forKey: .beforeNodes)
        movedRoots = try values.decode([String].self, forKey: .movedRoots)
        try validate()
    }

    func validate() throws {
        let failure = DraftAttachmentStagingFailureV1.corruptManifest
        try before.validate()
        guard schemaVersion == Self.schemaVersion,
              restoreID != Self.zero,
              workspaceID.rawValue != Self.zero,
              !before.entries.isEmpty || movedRoots.contains(where: {
                $0 != DraftAttachmentStagingAdapterV1.quarantineName
              }),
              before.entries.allSatisfy({ $0.item.workspaceID == workspaceID }),
              beforeNodes.count <= FieldDraftLimitsV1.maximumStageItems * 5 + 3,
              beforeNodes == beforeNodes.sorted(by: { $0.path < $1.path }),
              Set(beforeNodes.map(\.path)).count == beforeNodes.count,
              Set(beforeNodes.map({ "\($0.device):\($0.inode)" })).count == beforeNodes.count,
              movedRoots == movedRoots.sorted(), Set(movedRoots).count == movedRoots.count,
              movedRoots.contains(DraftAttachmentStagingAdapterV1.quarantineName),
              !movedRoots.contains(privateName), !movedRoots.contains(Self.replacementQuarantineName),
              beforeNodes.first(where: { $0.path == "." })?.directory == true,
              beforeNodes.first(where: { $0.path == DraftAttachmentStagingAdapterV1.manifestName })?.directory == false,
              beforeNodes.allSatisfy({ $0.claimPath == nil && ($0.directory ? $0.sha256 == nil
                : $0.sha256.map(StoreMigrationCanonicalJSONV1.isLowercaseSHA256) == true) }) else {
            throw failure
        }

        let nodes = Dictionary(uniqueKeysWithValues: beforeNodes.map { ($0.path, $0) })
        let rootChildren = Set(beforeNodes.compactMap { node -> String? in
            guard node.path != ".", !node.path.contains("/") else { return nil }
            return node.path
        })
        guard rootChildren == Set(movedRoots).union([DraftAttachmentStagingAdapterV1.manifestName]),
              movedRoots.allSatisfy({ nodes[$0]?.directory == true }) else { throw failure }

        var entriesByPath = [String: DraftAttachmentStagingEntryV1]()
        for entry in before.entries {
            let expectedPath = entry.item.state == .orphanQuarantined
                ? "\(DraftAttachmentStagingAdapterV1.quarantineName)/stage-\(entry.item.stageID.uuidString.lowercased())/\(DraftAttachmentStagingAdapterV1.payloadName)"
                : DraftAttachmentStagingAdapterV1.relativeDataPath(
                    draftID: entry.item.draftID, stageID: entry.item.stageID)
            guard entry.relativeDataPath == expectedPath,
                  entriesByPath.updateValue(entry, forKey: entry.relativeDataPath) == nil else { throw failure }
        }
        let manifestBytes = try before.canonicalBytes()
        guard let manifestNode = nodes[DraftAttachmentStagingAdapterV1.manifestName],
              manifestNode.byteCount == Int64(manifestBytes.count),
              manifestNode.sha256 == CanonicalJSONV1.sha256(manifestBytes) else { throw failure }
        var observedPayloads = Set<String>()
        for node in beforeNodes {
            guard node.inode != 0, node.byteCount >= 0,
                  (node.directory || node.linkCount == 1),
                  (0..<1_000_000_000).contains(node.modifiedNanoseconds),
                  (0..<1_000_000_000).contains(node.changedNanoseconds) else { throw failure }
            if node.path == "." { continue }
            let parts = node.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard (1...3).contains(parts.count) else { throw failure }
            for part in parts { try DraftStagingRootOwnerV1.component(part) }
            let parent = parts.count == 1 ? "." : parts.dropLast().joined(separator: "/")
            guard nodes[parent]?.directory == true else { throw failure }

            if node.directory {
                if parts.count == 1 {
                    guard parts[0] == DraftAttachmentStagingAdapterV1.quarantineName
                        || Self.canonicalComponent(parts[0], prefix: "draft-") else { throw failure }
                } else if parts.count == 2 {
                    guard (parts[0] == DraftAttachmentStagingAdapterV1.quarantineName
                            && Self.canonicalComponent(parts[1], prefix: "stage-"))
                        || (Self.canonicalComponent(parts[0], prefix: "draft-")
                            && Self.canonicalComponent(parts[1], prefix: "stage-")),
                          nodes[node.path + "/" + DraftAttachmentStagingAdapterV1.payloadName]?.directory == false
                    else { throw failure }
                } else { throw failure }
                continue
            }

            guard node.byteCount > 0 else { throw failure }
            if node.path == DraftAttachmentStagingAdapterV1.manifestName {
                guard node.byteCount <= Int64(FieldDraftLimitsV1.maximumCanonicalBytes) else { throw failure }
                continue
            }
            guard parts.count == 3 else { throw failure }
            if parts[2] == "raw-publication.json" {
                let payload = parts.dropLast().joined(separator: "/") + "/" + DraftAttachmentStagingAdapterV1.payloadName
                guard node.byteCount <= Int64(FieldDraftLimitsV1.maximumCanonicalBytes),
                      parts[0] != DraftAttachmentStagingAdapterV1.quarantineName,
                      nodes[payload]?.directory == false,
                      entriesByPath[payload]?.item.attachmentKind == .photo,
                      entriesByPath[payload].map({ $0.item.state == .readyLocal
                        || $0.item.state == .committed }) == true else { throw failure }
                continue
            }
            guard parts[2] == DraftAttachmentStagingAdapterV1.payloadName,
                  let entry = entriesByPath[node.path] else { throw failure }
            observedPayloads.insert(node.path)
            let witness = parts.dropLast().joined(separator: "/") + "/raw-publication.json"
            let maximum = nodes[witness] == nil
                ? Int64(FieldDraftLimitsV1.maximumPayloadBytes)
                : Int64(MediaContractV1.sourceByteCountMaximum)
            guard node.byteCount <= maximum,
                  entry.relativeDataPath == node.path,
                  entry.item.actualByteCount.map({ $0 == node.byteCount }) ?? true else { throw failure }
            if entry.item.state == .readyLocal || entry.item.state == .committed {
                guard let digest = entry.item.contentDigest, digest.algorithm == .sha256,
                      node.sha256 == digest.hexadecimalValue else { throw failure }
            }
        }
        guard observedPayloads == Set(entriesByPath.keys) else { throw failure }
    }

    func sha256() throws -> String {
        try validate()
        return CanonicalJSONV1.sha256(try FieldDraftCanonicalCodecV1.encode(self))
    }

    private static func canonicalComponent(_ value: String, prefix: String) -> Bool {
        guard value.hasPrefix(prefix), let id = UUID(uuidString: String(value.dropFirst(prefix.count))) else {
            return false
        }
        return value == prefix + id.uuidString.lowercased()
    }
}

/// Exact exclusive scaffold created for one retirement. Original incumbent
/// nodes remain solely in `plan.beforeNodes`; created nodes are never promoted
/// into that before-image census.
struct DraftConfigurationCloneRetirementOwnershipV1: Codable, Equatable, Sendable {
    typealias Node = DraftPhotoRestoreRawOwnershipV1.Node

    static let schemaVersion = 1
    let schemaVersion: Int
    let plan: DraftConfigurationCloneRetirementPlanV1
    let createdNodes: [Node]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, plan, createdNodes
    }

    fileprivate init(plan: DraftConfigurationCloneRetirementPlanV1,
        privateRoot: Node, replacementQuarantine: Node) throws {
        schemaVersion = Self.schemaVersion; self.plan = plan
        createdNodes = [privateRoot, replacementQuarantine].sorted { $0.path < $1.path }
        try validate()
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        plan = try values.decode(DraftConfigurationCloneRetirementPlanV1.self, forKey: .plan)
        createdNodes = try values.decode([Node].self, forKey: .createdNodes)
        try validate()
    }

    func validate() throws {
        try plan.validate()
        let failure = DraftAttachmentStagingFailureV1.corruptManifest
        let privatePath = plan.privateName
        let replacementPath = "\(privatePath)/\(DraftConfigurationCloneRetirementPlanV1.replacementQuarantineName)"
        guard schemaVersion == Self.schemaVersion, createdNodes.count == 2,
              createdNodes == createdNodes.sorted(by: { $0.path < $1.path }),
              Set(createdNodes.map(\.path)) == Set([privatePath, replacementPath]),
              createdNodes.allSatisfy({ $0.directory && $0.inode != 0 && $0.sha256 == nil }),
              let privateRoot = createdNodes.first(where: { $0.path == privatePath }),
              let replacement = createdNodes.first(where: { $0.path == replacementPath }),
              privateRoot.claimPath == privateRoot.reservingClaim(restoreID: plan.restoreID).claimPath,
              replacement.claimPath == DraftAttachmentStagingAdapterV1.quarantineName,
              Set(createdNodes.compactMap(\.claimPath)).count == 2,
              createdNodes.allSatisfy({ $0.linkCount > 0 && $0.byteCount >= 0
                && (0..<1_000_000_000).contains($0.modifiedNanoseconds)
                && (0..<1_000_000_000).contains($0.changedNanoseconds) }),
              Set(createdNodes.map({ "\($0.device):\($0.inode)" })).count == createdNodes.count,
              Set(createdNodes.map({ "\($0.device):\($0.inode)" })).isDisjoint(with:
                Set(plan.beforeNodes.map({ "\($0.device):\($0.inode)" }))),
              Set(createdNodes.compactMap(\.claimPath)).isDisjoint(with: Set(plan.beforeNodes.map(\.path))) == false,
              !plan.beforeNodes.contains(where: { $0.path == privatePath || $0.path.hasPrefix(privatePath + "/") }) else {
            throw failure
        }
        // The only intentional created/original placement overlap is the
        // replacement quarantine's eventual public name.
        guard Set(createdNodes.compactMap(\.claimPath)).intersection(Set(plan.beforeNodes.map(\.path)))
                == Set([DraftAttachmentStagingAdapterV1.quarantineName]) else { throw failure }
    }

    func sha256() throws -> String {
        try validate()
        return CanonicalJSONV1.sha256(try FieldDraftCanonicalCodecV1.encode(self))
    }
}

/// Descriptor-relative incumbent retirement. Every instance is one-shot;
/// recovery opens a new instance from the immutable ownership value.
final class DraftConfigurationCloneRetirementPreparedV1: @unchecked Sendable {
    typealias Node = DraftPhotoRestoreRawOwnershipV1.Node

    let ownership: DraftConfigurationCloneRetirementOwnershipV1
#if DEBUG
    var failAfterStepForTesting: String?
    var beforeClaimForTesting: ((URL, Bool) throws -> Void)?
    var observationForTesting: ((String) throws -> Void)?
    private func observeForTesting(_ label: String) throws {
        try observationForTesting?(label)
        if failAfterStepForTesting == label { throw DraftAttachmentStagingFailureV1.cleanupFailed }
    }
#endif

    private static let failure = DraftAttachmentStagingFailureV1.staleStage
    private let owner: DraftStagingRootOwnerV1
    private let bindingSHA256: String
    private let useLock = NSLock()
    private var consumed = false
    private var admittedClaims: [String: Node] = [:]

    private final class ClaimSource {
        let directory: DraftStagingRootOwnerV1.Directory?
        private(set) var file: Int32
        init(directory: DraftStagingRootOwnerV1.Directory) { self.directory = directory; file = -1 }
        init(file: Int32) { directory = nil; self.file = file }
        deinit { if file >= 0 { close(file) } }
    }

    private init(owner: DraftStagingRootOwnerV1,
        ownership: DraftConfigurationCloneRetirementOwnershipV1, bindingSHA256: String) {
        self.owner = owner; self.ownership = ownership; self.bindingSHA256 = bindingSHA256
    }

    fileprivate static func prepare(authority: DraftConfigurationCloneRetirementAuthorityV1,
        verification: DraftPhotoBackupPreparedVerificationV1) throws -> Self {
        try requireAuthority(authority, rootURL: verification.owner.rootURL)
        let owner = verification.owner
        return try verification.withRestorePreparationLock {
            try DraftConfigurationCloneRetirementFilesystemV1.requireBefore(
                authority.plan, owner: owner, strictManifestFacts: true)
            let root = try owner.directory([])
            guard try !root.exists(authority.plan.privateName),
                  mkdirat(root.descriptor, authority.plan.privateName, mode_t(0o700)) == 0 else { throw failure }
            let privateRoot = try owner.directory([authority.plan.privateName])
            do {
                try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: privateRoot.url,
                    authorityCheck: { try privateRoot.verifyNamed() })
                let replacementName = DraftConfigurationCloneRetirementPlanV1.replacementQuarantineName
                guard mkdirat(privateRoot.descriptor, replacementName, mode_t(0o700)) == 0 else { throw failure }
                let replacement = try owner.directory([authority.plan.privateName, replacementName])
                try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: replacement.url,
                    authorityCheck: { try replacement.verifyNamed() })
                guard fsync(privateRoot.descriptor) == 0, fsync(root.descriptor) == 0 else { throw failure }
                var privateNode = Node(path: authority.plan.privateName, directory: true,
                    facts: DraftPhotoRawBackupSnapshotV1.facts(try owner.directory(
                        [authority.plan.privateName]).identity))
                privateNode = Node(path: privateNode.path, directory: true,
                    facts: DraftConfigurationCloneRetirementFilesystemV1.facts(privateNode),
                    claimPath: privateNode.reservingClaim(restoreID: authority.plan.restoreID).claimPath)
                let protectedReplacement = try owner.directory([authority.plan.privateName, replacementName])
                let replacementNode = Node(path: "\(authority.plan.privateName)/\(replacementName)",
                    directory: true, facts: DraftPhotoRawBackupSnapshotV1.facts(protectedReplacement.identity),
                    claimPath: DraftAttachmentStagingAdapterV1.quarantineName)
                let receipt = try DraftConfigurationCloneRetirementOwnershipV1(plan: authority.plan,
                    privateRoot: privateNode, replacementQuarantine: replacementNode)
                let value = Self(owner: owner, ownership: receipt,
                    bindingSHA256: authority.bindingSHA256)
                try value.requireMovement(hashFiles: false)
                return value
            } catch {
                // A process crash leaves the unproved exclusive scaffold for
                // explicit recovery. A caught construction failure preserves
                // the same preclaim uncertainty; no absent ownership receipt
                // is inferred into cleanup authority.
                throw error
            }
        }
    }

    fileprivate static func reopen(authority: DraftConfigurationCloneRetirementAuthorityV1,
        ownership: DraftConfigurationCloneRetirementOwnershipV1,
        owner: DraftStagingRootOwnerV1) throws -> Self {
        try requireAuthority(authority, rootURL: owner.rootURL)
        try ownership.validate()
        guard authority.plan == ownership.plan else { throw failure }
        let value = Self(owner: owner, ownership: ownership,
            bindingSHA256: authority.bindingSHA256)
        let held = try owner.acquire(); defer { held.release() }
        if (try? value.requireRestored()) != nil { return value }
        if (try? value.requireMovement(hashFiles: true)) != nil { return value }
        if (try? value.requireRollbackScaffoldCleanup()) != nil { return value }
        try value.requireRetiring(hashFiles: true)
        return value
    }

    func quarantine(permit: DraftConfigurationCloneRetirementPermitV1,
        publishingPointer: () throws -> Void) throws {
        try consume()
        try requirePermit(permit, operation: .quarantine)
        let held = try owner.acquire(); defer { held.release() }
        try requireMovement(hashFiles: true)
        for rootName in ownership.plan.movedRoots.sorted() {
            let publicPath = rootName, privatePath = "\(ownership.plan.privateName)/\(rootName)"
            if try exists(publicPath) {
                guard try !exists(privatePath) else { throw Self.failure }
                try move(from: publicPath, to: privatePath,
                    expected: ownership.plan.beforeNodes.first(where: { $0.path == rootName }))
#if DEBUG
                try observeForTesting("after-moved-root")
#endif
            }
        }
        let replacement = replacementNode
        if try exists(replacement.path) {
            try move(from: replacement.path, to: DraftAttachmentStagingAdapterV1.quarantineName,
                expected: replacement)
#if DEBUG
            try observeForTesting("after-replacement-quarantine")
#endif
        }
        try requireMovement(hashFiles: false)
        try replaceManifest(try DraftAttachmentStagingManifestV1(entries: []))
#if DEBUG
        try observeForTesting("after-empty-manifest")
#endif
        try requireQuarantined(hashFiles: false)
        try publishingPointer()
        try requireQuarantined(hashFiles: false)
    }

    func rollback(permit: DraftConfigurationCloneRetirementPermitV1) throws {
        try consume()
        try requirePermit(permit, operation: .rollback)
        let held = try owner.acquire(); defer { held.release() }
        if (try? requireRestored()) != nil { return }
        if (try? requireRollbackScaffoldCleanup()) != nil {
            try removeRollbackScaffoldIfPresent()
            try requireRestored()
            return
        }
        try requireMovement(hashFiles: true)
        try replaceManifest(ownership.plan.before)
#if DEBUG
        try observeForTesting("after-rollback-manifest")
#endif
        let replacement = replacementNode
        if try exists(DraftAttachmentStagingAdapterV1.quarantineName),
           let publicNode = try nodeAt(DraftAttachmentStagingAdapterV1.quarantineName, hashFile: false),
           DraftConfigurationCloneRetirementFilesystemV1.sameDirectoryIdentity(publicNode, replacement) {
            try move(from: DraftAttachmentStagingAdapterV1.quarantineName, to: replacement.path,
                expected: replacement)
        }
        for rootName in ownership.plan.movedRoots.sorted() {
            let privatePath = "\(ownership.plan.privateName)/\(rootName)"
            if try exists(privatePath) {
                guard try !exists(rootName) else { throw Self.failure }
                try move(from: privatePath, to: rootName,
                    expected: ownership.plan.beforeNodes.first(where: { $0.path == rootName }))
#if DEBUG
                try observeForTesting("after-restored-root")
#endif
            }
        }
        try requireMovement(hashFiles: false)
        try removeRollbackScaffoldIfPresent()
        try requireRestored()
    }

    func finish(permit: DraftConfigurationCloneRetirementPermitV1) throws {
        try consume()
        try requirePermit(permit, operation: .retire)
        let held = try owner.acquire(); defer { held.release() }
        try requireRetiring(hashFiles: true)
        var nodes = privateBeforeNodes
        nodes.append(privateRootNode)
        nodes.sort {
            let lhs = $0.path.split(separator: "/").count, rhs = $1.path.split(separator: "/").count
            return lhs == rhs ? $0.path > $1.path : lhs > rhs
        }
        for expected in nodes { try claimAndRemove(expected) }
        try requireRetiredTerminal()
    }

    func withQuarantinedVerificationLock<T>(permit: DraftConfigurationCloneRetirementPermitV1,
        _ body: () throws -> T) throws -> T {
        try consume()
        try requirePermit(permit, operation: .quarantinedVerification)
        let held = try owner.acquire(); defer { held.release() }
        try requireQuarantined(hashFiles: true)
        let value = try body()
        try requireQuarantined(hashFiles: false)
        return value
    }

    func withTerminalVerificationLock<T>(permit: DraftConfigurationCloneRetirementPermitV1,
        _ body: () throws -> T) throws -> T {
        try consume()
        let operation = try terminalOperation(permit)
        let held = try owner.acquire(); defer { held.release() }
        switch operation {
        case .rollback: try requireRestored()
        case .retire: try requireRetiredTerminal()
        default: throw Self.failure
        }
        let value = try body()
        switch operation {
        case .rollback: try requireRestored()
        case .retire: try requireRetiredTerminal()
        default: throw Self.failure
        }
        return value
    }

    private enum Operation { case quarantine, rollback, retire, quarantinedVerification }

    private func consume() throws {
        useLock.lock(); defer { useLock.unlock() }
        guard !consumed else { throw Self.failure }
        consumed = true
    }

    private static func requireAuthority(_ authority: DraftConfigurationCloneRetirementAuthorityV1,
        rootURL: URL) throws {
        try authority.plan.validate()
        let expectedRoot = authority.applicationSupportURL.standardizedFileURL
            .appendingPathComponent(OwnedStorageRootKindV1.data.rawValue, isDirectory: true)
            .appendingPathComponent(DraftAttachmentStagingAdapterV1.directoryName, isDirectory: true)
            .standardizedFileURL
        guard expectedRoot == rootURL.standardizedFileURL,
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(authority.bindingSHA256) else { throw failure }
    }

    private func requirePermit(_ permit: DraftConfigurationCloneRetirementPermitV1,
        operation: Operation) throws {
        try Self.requireAuthority(permit.authority, rootURL: owner.rootURL)
        guard permit.authority.plan == ownership.plan,
              permit.authority.bindingSHA256 == bindingSHA256,
              permit.ownershipSHA256 == (try ownership.sha256()) else { throw Self.failure }
        switch (operation, permit.disposition) {
        case (.quarantine, .quarantine), (.rollback, .rollback), (.retire, .retire),
             (.quarantinedVerification, .quarantine), (.quarantinedVerification, .retire): return
        default: throw Self.failure
        }
    }

    private func terminalOperation(_ permit: DraftConfigurationCloneRetirementPermitV1) throws -> Operation {
        switch permit.disposition {
        case .rollback:
            try requirePermit(permit, operation: .rollback); return .rollback
        case .retire:
            try requirePermit(permit, operation: .retire); return .retire
        case .quarantine: throw Self.failure
        }
    }

    private var privateRootNode: Node {
        ownership.createdNodes.first(where: { $0.path == ownership.plan.privateName })!
    }

    private var replacementNode: Node {
        ownership.createdNodes.first(where: { $0.path != ownership.plan.privateName })!
    }

    private var privateBeforeNodes: [Node] {
        ownership.plan.beforeNodes.compactMap { node in
            guard node.path != ".", node.path != DraftAttachmentStagingAdapterV1.manifestName else { return nil }
            return Node(path: "\(ownership.plan.privateName)/\(node.path)", directory: node.directory,
                facts: DraftConfigurationCloneRetirementFilesystemV1.facts(node), sha256: node.sha256)
                .reservingClaim(restoreID: ownership.plan.restoreID)
        }
    }

    private func requireMovement(hashFiles: Bool) throws {
        try ownership.validate()
        let actualManifest = try DraftStagingRootOwnerV1.ManifestSnapshot(owner: owner).manifest
        let before = try ownership.plan.before.canonicalBytes()
        let empty = try DraftAttachmentStagingManifestV1(entries: []).canonicalBytes()
        let actualBytes = try actualManifest.canonicalBytes()
        guard actualBytes == before || actualBytes == empty else { throw Self.failure }

        let actual = try DraftConfigurationCloneRetirementFilesystemV1.scan(owner: owner,
            manifest: actualManifest, hashFiles: hashFiles)
        let byPath = Dictionary(uniqueKeysWithValues: actual.map { ($0.path, $0) })
        guard matches(byPath["."], ownership.plan.beforeNodes.first(where: { $0.path == "." }), hash: false),
              byPath[ownership.plan.privateName].map({
                DraftConfigurationCloneRetirementFilesystemV1.sameDirectoryIdentity($0, privateRootNode)
              }) == true else { throw Self.failure }

        var expected: [String: Node] = [".": ownership.plan.beforeNodes.first(where: { $0.path == "." })!,
            ownership.plan.privateName: privateRootNode]
        var allPrivate = true
        for rootName in ownership.plan.movedRoots {
            let original = ownership.plan.beforeNodes.first(where: { $0.path == rootName })!
            let privatePath = "\(ownership.plan.privateName)/\(rootName)"
            let publicMatches = matches(byPath[rootName], original, hash: hashFiles)
            let privateMatches = matches(byPath[privatePath], translated(original, to: privatePath), hash: hashFiles)
            guard publicMatches != privateMatches else { throw Self.failure }
            let prefix = privateMatches ? ownership.plan.privateName + "/" : ""
            allPrivate = allPrivate && privateMatches
            for node in ownership.plan.beforeNodes where node.path == rootName || node.path.hasPrefix(rootName + "/") {
                let path = prefix + node.path
                expected[path] = translated(node, to: path)
            }
        }

        let replacementInitial = replacementNode.path
        let replacementPublic = DraftAttachmentStagingAdapterV1.quarantineName
        let oldQuarantinePrivate = expected["\(ownership.plan.privateName)/\(replacementPublic)"] != nil
        let initialMatches = matches(byPath[replacementInitial], replacementNode, hash: false)
        let publicMatches = matches(byPath[replacementPublic], translated(replacementNode, to: replacementPublic), hash: false)
        guard initialMatches != publicMatches, oldQuarantinePrivate || initialMatches else { throw Self.failure }
        expected[initialMatches ? replacementInitial : replacementPublic] = translated(
            replacementNode, to: initialMatches ? replacementInitial : replacementPublic)

        // The manifest inode is intentionally replaced, so content is the
        // state boundary after preparation. It remains the only unmatched file.
        expected[DraftAttachmentStagingAdapterV1.manifestName] = byPath[DraftAttachmentStagingAdapterV1.manifestName]
        guard Set(expected.keys) == Set(byPath.keys), expected.allSatisfy({ path, node in
            path == DraftAttachmentStagingAdapterV1.manifestName || matches(byPath[path], node, hash: hashFiles)
        }) else { throw Self.failure }
        if actualBytes == empty { guard allPrivate && publicMatches else { throw Self.failure } }
    }

    private func requireQuarantined(hashFiles: Bool) throws {
        try requireMovement(hashFiles: hashFiles)
        let manifest = try DraftStagingRootOwnerV1.ManifestSnapshot(owner: owner).manifest
        guard try manifest.canonicalBytes() == DraftAttachmentStagingManifestV1(entries: []).canonicalBytes(),
              ownership.plan.movedRoots.allSatisfy({ (try? exists("\(ownership.plan.privateName)/\($0)")) == true }),
              try exists(DraftAttachmentStagingAdapterV1.quarantineName),
              try !exists(replacementNode.path) else { throw Self.failure }
    }

    private func requireRestored() throws {
        guard try !requireRollbackScaffoldCleanup() else { throw Self.failure }
    }

    /// Exact before image with only the receipt-owned empty scaffold possibly
    /// remaining. This admits both crash points in bottom-up rollback cleanup.
    @discardableResult
    private func requireRollbackScaffoldCleanup() throws -> Bool {
        let manifest = try DraftStagingRootOwnerV1.ManifestSnapshot(owner: owner).manifest
        guard try manifest.canonicalBytes() == ownership.plan.before.canonicalBytes() else { throw Self.failure }
        let actual = try DraftConfigurationCloneRetirementFilesystemV1.scan(owner: owner,
            manifest: manifest, hashFiles: true)
        let byPath = Dictionary(uniqueKeysWithValues: actual.map { ($0.path, $0) })
        for expected in ownership.plan.beforeNodes {
            guard let node = byPath[expected.path] else { throw Self.failure }
            if expected.path == DraftAttachmentStagingAdapterV1.manifestName {
                guard node.byteCount == expected.byteCount, node.sha256 == expected.sha256 else { throw Self.failure }
            } else {
                guard matches(node, expected, hash: true) else { throw Self.failure }
            }
        }
        var allowed = Set(ownership.plan.beforeNodes.map(\.path))
        let privateExists = byPath[privateRootNode.path] != nil
        let replacementExists = byPath[replacementNode.path] != nil
        if privateExists {
            guard matches(byPath[privateRootNode.path], privateRootNode, hash: false) else { throw Self.failure }
            allowed.insert(privateRootNode.path)
            if replacementExists {
                guard matches(byPath[replacementNode.path], replacementNode, hash: false) else { throw Self.failure }
                allowed.insert(replacementNode.path)
            }
        } else {
            guard !replacementExists else { throw Self.failure }
        }
        guard Set(byPath.keys) == allowed else { throw Self.failure }
        return privateExists
    }

    private func requireRetiring(hashFiles: Bool) throws {
        try ownership.validate()
        let manifest = try DraftStagingRootOwnerV1.ManifestSnapshot(owner: owner).manifest
        guard try manifest.canonicalBytes() == DraftAttachmentStagingManifestV1(entries: []).canonicalBytes() else {
            throw Self.failure
        }
        let actual = try DraftConfigurationCloneRetirementFilesystemV1.scan(owner: owner,
            manifest: manifest, hashFiles: hashFiles)
        let byPath = Dictionary(uniqueKeysWithValues: actual.map { ($0.path, $0) })
        let root = ownership.plan.beforeNodes.first(where: { $0.path == "." })!
        guard matches(byPath["."], root, hash: false),
              matches(byPath[DraftAttachmentStagingAdapterV1.quarantineName],
                translated(replacementNode, to: DraftAttachmentStagingAdapterV1.quarantineName), hash: false),
              try owner.directory([DraftAttachmentStagingAdapterV1.quarantineName]).names().isEmpty else {
            throw Self.failure
        }
        let manifestPath = DraftAttachmentStagingAdapterV1.manifestName
        let allowedSpecial = Set([".", manifestPath, DraftAttachmentStagingAdapterV1.quarantineName])
        var allowedNormal = Dictionary(uniqueKeysWithValues: privateBeforeNodes.map { ($0.path, $0) })
        allowedNormal[privateRootNode.path] = privateRootNode
        var allowedClaims = [String: Node]()
        for node in privateBeforeNodes + [privateRootNode] {
            guard let claim = node.claimPath, allowedClaims.updateValue(node, forKey: claim) == nil else {
                throw Self.failure
            }
        }
        admittedClaims = admittedClaims.filter { byPath[$0.key] != nil }
        for node in actual where !allowedSpecial.contains(node.path) {
            if let expected = allowedNormal[node.path] {
                guard matches(node, expected, hash: hashFiles) else { throw Self.failure }
                if let claim = expected.claimPath, byPath[claim] != nil { throw Self.failure }
                continue
            }
            guard let expected = allowedClaims[node.path], byPath[expected.path] == nil,
                  hashFiles else { throw Self.failure }
            let frozen = try admitClaim(actual: node, expected: expected)
            admittedClaims[node.path] = frozen
        }
        if let privateClaim = privateRootNode.claimPath, byPath[privateClaim] != nil {
            guard byPath[privateRootNode.path] == nil,
                  actual.allSatisfy({ allowedSpecial.contains($0.path) || $0.path == privateClaim }) else {
                throw Self.failure
            }
        } else if byPath[privateRootNode.path] == nil {
            guard actual.allSatisfy({ allowedSpecial.contains($0.path) }) else { throw Self.failure }
        }
    }

    private func requireRetiredTerminal() throws {
        try requireRetiring(hashFiles: true)
        let manifest = try DraftStagingRootOwnerV1.ManifestSnapshot(owner: owner).manifest
        let actual = try DraftConfigurationCloneRetirementFilesystemV1.scan(owner: owner,
            manifest: manifest, hashFiles: false)
        guard Set(actual.map(\.path)) == Set([".", DraftAttachmentStagingAdapterV1.manifestName,
                DraftAttachmentStagingAdapterV1.quarantineName]) else { throw Self.failure }
    }

    private func removeRollbackScaffoldIfPresent() throws {
        if try exists(replacementNode.path) {
            let parts = replacementNode.path.split(separator: "/").map(String.init)
            let parent = try owner.directory(Array(parts.dropLast()))
            let directory = try owner.directory(parts)
            guard replacementNode.matches(directory.identity), try directory.names().isEmpty,
                  unlinkat(parent.descriptor, parts.last!, AT_REMOVEDIR) == 0,
                  fsync(parent.descriptor) == 0 else { throw Self.failure }
        }
        if try exists(privateRootNode.path) {
            let root = try owner.directory([]), directory = try owner.directory([privateRootNode.path])
            guard privateRootNode.matches(directory.identity), try directory.names().isEmpty,
                  unlinkat(root.descriptor, privateRootNode.path, AT_REMOVEDIR) == 0,
                  fsync(root.descriptor) == 0 else { throw Self.failure }
        }
    }

    private func claimAndRemove(_ expected: Node) throws {
        guard let claimPath = expected.claimPath else { throw Self.failure }
        let original = try namedLocation(expected.path), claim = try namedLocation(claimPath)
        let originalExists = try original.map { try $0.parent.exists($0.name) } ?? false
        let claimExists = try claim.map { try $0.parent.exists($0.name) } ?? false
        guard !(originalExists && claimExists) else { throw Self.failure }
        if claimExists {
            guard let claim, let frozen = admittedClaims[claimPath] else { throw Self.failure }
            try removeClaim(expected: expected, frozen: frozen, parent: claim.parent, name: claim.name)
            return
        }
        guard originalExists, let original, let claim else { return }
        let source = try requireOriginalForClaim(expected, parent: original.parent, name: original.name)
#if DEBUG
        try beforeClaimForTesting?(original.parent.url.appendingPathComponent(original.name,
            isDirectory: expected.directory), expected.directory)
#endif
        try original.parent.verifyNamed(); try claim.parent.verifyNamed()
        guard renameatx_np(original.parent.descriptor, original.name,
                claim.parent.descriptor, claim.name, UInt32(RENAME_EXCL)) == 0,
              fsync(original.parent.descriptor) == 0 else { throw Self.failure }
        let frozen = try freezeClaim(expected, source: source, parent: claim.parent, name: claim.name)
        admittedClaims[claimPath] = frozen
#if DEBUG
        try observeForTesting("after-retire-claim")
#endif
        try removeClaim(expected: expected, frozen: frozen, parent: claim.parent, name: claim.name)
#if DEBUG
        try observeForTesting(expected == privateRootNode ? "after-scaffold-delete" : "after-retire-delete")
#endif
    }

    private func move(from: String, to: String, expected: Node?) throws {
        guard let expected else { throw Self.failure }
        let sourceParts = from.split(separator: "/").map(String.init)
        let targetParts = to.split(separator: "/").map(String.init)
        guard let sourceName = sourceParts.last, let targetName = targetParts.last else { throw Self.failure }
        let sourceParent = try owner.directory(Array(sourceParts.dropLast()))
        let targetParent = try owner.directory(Array(targetParts.dropLast()))
        let source = try owner.directory(sourceParts)
        guard expected.matches(source.identity), try !targetParent.exists(targetName) else { throw Self.failure }
        try sourceParent.verifyNamed(); try targetParent.verifyNamed()
        guard renameatx_np(sourceParent.descriptor, sourceName,
                targetParent.descriptor, targetName, UInt32(RENAME_EXCL)) == 0,
              fsync(sourceParent.descriptor) == 0, fsync(targetParent.descriptor) == 0 else {
            throw Self.failure
        }
        guard expected.matches(try owner.directory(targetParts).identity) else { throw Self.failure }
    }

    private func replaceManifest(_ manifest: DraftAttachmentStagingManifestV1) throws {
        let bytes = try manifest.canonicalBytes()
        if try DraftStagingRootOwnerV1.ManifestSnapshot(owner: owner).manifest.canonicalBytes() != bytes {
            try DraftStagingRootOwnerV1.replaceFile(bytes,
                at: owner.rootURL.appendingPathComponent(DraftAttachmentStagingAdapterV1.manifestName),
                directory: owner.directory([]))
        }
        guard try DraftStagingRootOwnerV1.ManifestSnapshot(owner: owner).manifest.canonicalBytes() == bytes else {
            throw Self.failure
        }
    }

    private func exists(_ path: String) throws -> Bool {
        let parts = path.split(separator: "/").map(String.init)
        guard let name = parts.last else { throw Self.failure }
        var parent = try owner.directory([])
        for component in parts.dropLast() {
            guard try parent.exists(component) else { return false }
            parent = try owner.directory(parent.components + [component])
        }
        return try parent.exists(name)
    }

    private func nodeAt(_ path: String, hashFile: Bool) throws -> Node? {
        let manifest = try DraftStagingRootOwnerV1.ManifestSnapshot(owner: owner).manifest
        return try DraftConfigurationCloneRetirementFilesystemV1.scan(owner: owner,
            manifest: manifest, hashFiles: hashFile).first(where: { $0.path == path })
    }

    private func translated(_ node: Node, to path: String) -> Node {
        Node(path: path, directory: node.directory,
            facts: DraftConfigurationCloneRetirementFilesystemV1.facts(node), sha256: node.sha256,
            claimPath: node.claimPath)
    }

    private func matches(_ actual: Node?, _ expected: Node?, hash: Bool) -> Bool {
        guard let actual, let expected, actual.path == expected.path,
              actual.directory == expected.directory,
              (expected.directory
                ? actual.device == expected.device && actual.inode == expected.inode
                : DraftConfigurationCloneRetirementFilesystemV1.sameFacts(actual, expected)),
              !hash || expected.directory || actual.sha256 == expected.sha256 else { return false }
        return true
    }

    private func namedLocation(_ path: String) throws
        -> (parent: DraftStagingRootOwnerV1.Directory, name: String)? {
        let parts = path.split(separator: "/").map(String.init)
        guard let name = parts.last else { throw Self.failure }
        var parent = try owner.directory([])
        for component in parts.dropLast() {
            if try !parent.exists(component) { return nil }
            parent = try owner.directory(parent.components + [component])
        }
        return (parent, name)
    }

    private func requireOriginalForClaim(_ expected: Node,
        parent: DraftStagingRootOwnerV1.Directory, name: String) throws -> ClaimSource {
        if expected.directory {
            let directory = try owner.directory(parent.components + [name])
            guard expected.matches(directory.identity), try directory.names().isEmpty else { throw Self.failure }
            return ClaimSource(directory: directory)
        }
        let file = try parent.openFile(name)
        do {
            let facts = try DraftStagingRootOwnerV1.regular(file)
            guard expected.matches(facts), let digest = expected.sha256,
                  try DraftConfigurationCloneRetirementFilesystemV1.digest(file, facts: facts) == digest else {
                throw Self.failure
            }
            try parent.verifyPinnedFile(file, name: name, facts: facts)
            return ClaimSource(file: file)
        } catch { close(file); throw error }
    }

    private func freezeClaim(_ expected: Node, source: ClaimSource,
        parent: DraftStagingRootOwnerV1.Directory, name: String) throws -> Node {
        guard let path = expected.claimPath else { throw Self.failure }
        if expected.directory {
            guard let sourceDirectory = source.directory else { throw Self.failure }
            var facts = stat()
            guard fstat(sourceDirectory.descriptor, &facts) == 0 else { throw Self.failure }
            let claimed = try owner.directory(parent.components + [name])
            var current = stat()
            guard fstat(claimed.descriptor, &current) == 0,
                  current.st_dev == facts.st_dev, current.st_ino == facts.st_ino,
                  try claimed.names().isEmpty else { throw Self.failure }
            let frozen = Node(path: path, directory: true,
                facts: DraftPhotoRawBackupSnapshotV1.facts(current))
            guard expected.admitsClaim(frozen) else { throw Self.failure }
            return frozen
        }
        guard source.file >= 0 else { throw Self.failure }
        let facts = try DraftStagingRootOwnerV1.regular(source.file)
        let digest = try DraftConfigurationCloneRetirementFilesystemV1.digest(source.file, facts: facts)
        let frozen = Node(path: path, directory: false,
            facts: DraftPhotoRawBackupSnapshotV1.facts(facts), sha256: digest)
        guard expected.admitsClaim(frozen) else { throw Self.failure }
        try parent.verifyPinnedFile(source.file, name: name, facts: facts)
        return frozen
    }

    private func admitClaim(actual: Node, expected: Node) throws -> Node {
        guard expected.admitsClaim(actual) else { throw Self.failure }
        if expected.directory {
            guard try owner.directory(actual.path.split(separator: "/").map(String.init)).names().isEmpty else {
                throw Self.failure
            }
        }
        return actual
    }

    private func removeClaim(expected: Node, frozen: Node,
        parent: DraftStagingRootOwnerV1.Directory, name: String) throws {
        guard expected.claimPath == frozen.path, try parent.exists(name) else { throw Self.failure }
        if expected.directory {
            let directory = try owner.directory(parent.components + [name])
            var facts = stat()
            guard try directory.names().isEmpty, fstat(directory.descriptor, &facts) == 0,
                  frozen.strictlyMatches(facts) else { throw Self.failure }
            var after = stat()
            guard unlinkat(parent.descriptor, name, AT_REMOVEDIR) == 0,
                  fstat(directory.descriptor, &after) == 0, frozen.provesUnlinked(after),
                  fsync(parent.descriptor) == 0 else { throw Self.failure }
        } else {
            let file = try parent.openFile(name); defer { close(file) }
            let facts = try DraftStagingRootOwnerV1.regular(file)
            guard frozen.strictlyMatches(facts) else { throw Self.failure }
            try parent.verifyPinnedFile(file, name: name, facts: facts)
            var after = stat()
            guard unlinkat(parent.descriptor, name, 0) == 0,
                  fstat(file, &after) == 0, frozen.provesUnlinked(after),
                  fsync(parent.descriptor) == 0 else { throw Self.failure }
        }
        admittedClaims.removeValue(forKey: frozen.path)
    }
}

/// Shared closed census and streamed hashing used by live preparation and cold
/// plan verification. It never creates, renames, unlinks or rewrites a node.
fileprivate enum DraftConfigurationCloneRetirementFilesystemV1 {
    typealias Node = DraftPhotoRestoreRawOwnershipV1.Node
    static let failure = DraftAttachmentStagingFailureV1.staleStage

    static func capturePlan(restoreID: UUID, workspaceID: WorkspaceID,
        verification: DraftPhotoBackupPreparedVerificationV1) throws
        -> DraftConfigurationCloneRetirementPlanV1 {
        try verification.withRestorePreparationLock {
            let owner = verification.owner
            let before = try DraftStagingRootOwnerV1.ManifestSnapshot(owner: owner).manifest
            let nodes = try scan(owner: owner, manifest: before, hashFiles: true)
            let expected = verification.namespaceFacts.map { key, value in
                let directory = key.hasPrefix("directory:")
                return Node(path: String(key.dropFirst(directory ? 10 : 5)), directory: directory, facts: value)
            }
            guard Set(nodes.map(\.path)) == Set(expected.map(\.path)),
                  expected.allSatisfy({ item in
                    nodes.first(where: { $0.path == item.path }).map({ sameFacts($0, item) }) == true
                  }) else { throw failure }
            let moved = nodes.filter { $0.directory && $0.path != "." && !$0.path.contains("/") }.map(\.path)
            return try DraftConfigurationCloneRetirementPlanV1(restoreID: restoreID,
                workspaceID: workspaceID, before: before, beforeNodes: nodes, movedRoots: moved)
        }
    }

    static func requireBefore(_ plan: DraftConfigurationCloneRetirementPlanV1,
        owner: DraftStagingRootOwnerV1, strictManifestFacts: Bool) throws {
        try plan.validate()
        let manifest = try DraftStagingRootOwnerV1.ManifestSnapshot(owner: owner).manifest
        guard try manifest.canonicalBytes() == plan.before.canonicalBytes() else { throw failure }
        let actual = try scan(owner: owner, manifest: manifest, hashFiles: true)
        let expected = Dictionary(uniqueKeysWithValues: plan.beforeNodes.map { ($0.path, $0) })
        guard Set(actual.map(\.path)) == Set(expected.keys) else { throw failure }
        for node in actual {
            guard let expectedNode = expected[node.path] else { throw failure }
            let physicalMatch = strictManifestFacts
                ? sameFacts(node, expectedNode)
                : (expectedNode.directory
                    ? node.device == expectedNode.device && node.inode == expectedNode.inode
                    : sameFacts(node, expectedNode))
            guard physicalMatch || (!strictManifestFacts
                    && node.path == DraftAttachmentStagingAdapterV1.manifestName
                    && node.byteCount == expectedNode.byteCount),
                  node.directory || node.sha256 == expectedNode.sha256 else { throw failure }
        }
    }

    static func scan(owner: DraftStagingRootOwnerV1,
        manifest: DraftAttachmentStagingManifestV1, hashFiles: Bool) throws -> [Node] {
        try owner.requireNamedRoot(); try manifest.validate()
        var result = [Node(path: ".", directory: true,
            facts: DraftPhotoRawBackupSnapshotV1.facts(try owner.directory([]).identity))]
        try scanDirectory(owner: owner, components: [], manifest: manifest,
            hashFiles: hashFiles, result: &result)
        guard result.count <= FieldDraftLimitsV1.maximumStageItems * 5 + 8 else { throw failure }
        return result.sorted { $0.path < $1.path }
    }

    private static func scanDirectory(owner: DraftStagingRootOwnerV1, components: [String],
        manifest: DraftAttachmentStagingManifestV1, hashFiles: Bool, result: inout [Node]) throws {
        guard components.count <= 5 else { throw failure }
        let directory = try owner.directory(components)
        try ProtectedFilePolicyV1.verify(.stagingDirectory, at: directory.url)
        let names = try directory.names()
        guard names.count <= FieldDraftLimitsV1.maximumStageItems * 2 + 4 else { throw failure }
        for name in names.sorted() {
            try Task.checkCancellation()
            var value = stat()
            guard fstatat(directory.descriptor, name, &value, AT_SYMLINK_NOFOLLOW) == 0 else { throw failure }
            let path = (components + [name]).joined(separator: "/")
            if value.st_mode & S_IFMT == S_IFDIR {
                result.append(Node(path: path, directory: true,
                    facts: DraftPhotoRawBackupSnapshotV1.facts(value)))
                try scanDirectory(owner: owner, components: components + [name], manifest: manifest,
                    hashFiles: hashFiles, result: &result)
            } else if value.st_mode & S_IFMT == S_IFREG {
                let file = try directory.openFile(name); defer { close(file) }
                let fileFacts = try DraftStagingRootOwnerV1.regular(file)
                try ProtectedFilePolicyV1.verify(.stagingFile, at: directory.url.appendingPathComponent(name))
                let maximum = maximumBytes(path: path, manifest: manifest)
                guard fileFacts.st_size > 0, fileFacts.st_size <= maximum else { throw failure }
                let digestValue = hashFiles ? try digest(file, facts: fileFacts) : nil
                try directory.verifyPinnedFile(file, name: name, facts: fileFacts)
                result.append(Node(path: path, directory: false,
                    facts: DraftPhotoRawBackupSnapshotV1.facts(fileFacts), sha256: digestValue))
            } else { throw failure }
            guard result.count <= FieldDraftLimitsV1.maximumStageItems * 5 + 8 else { throw failure }
        }
        try directory.verifyNamed()
    }

    private static func maximumBytes(path: String,
        manifest: DraftAttachmentStagingManifestV1) -> Int64 {
        _ = manifest
        if path == DraftAttachmentStagingAdapterV1.manifestName || path.hasSuffix("/raw-publication.json") {
            return Int64(FieldDraftLimitsV1.maximumCanonicalBytes)
        }
        if path.hasSuffix("/" + DraftAttachmentStagingAdapterV1.payloadName) {
            // The actual sibling is admitted by the closed scan/plan. Use the
            // photo maximum provisionally; plan validation lowers every
            // witness-free payload to the generic2MiB bound.
            return Int64(MediaContractV1.sourceByteCountMaximum)
        }
        return Int64(MediaContractV1.sourceByteCountMaximum)
    }

    static func digest(_ file: Int32, facts: stat) throws -> String {
        guard facts.st_size > 0, facts.st_size <= Int64(MediaContractV1.sourceByteCountMaximum) else {
            throw failure
        }
        var hash = SHA256(), offset: Int64 = 0
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while offset < facts.st_size {
            try Task.checkCancellation()
            let wanted = Int(min(Int64(chunk.count), facts.st_size - offset))
            let count = chunk.withUnsafeMutableBytes { pread(file, $0.baseAddress, wanted, off_t(offset)) }
            if count < 0 && errno == EINTR { continue }
            guard count > 0, count <= wanted else { throw DraftAttachmentStagingFailureV1.byteLengthMismatch }
            hash.update(data: Data(chunk.prefix(count))); offset += Int64(count)
        }
        try DraftStagingRootOwnerV1.unchanged(file, facts)
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func facts(_ node: Node) -> StreamingArchiveSourceSnapshotV1 {
        .init(device: node.device, inode: node.inode, linkCount: node.linkCount,
            byteCount: node.byteCount, modifiedSeconds: node.modifiedSeconds,
            modifiedNanoseconds: node.modifiedNanoseconds, changedSeconds: node.changedSeconds,
            changedNanoseconds: node.changedNanoseconds)
    }

    static func sameFacts(_ lhs: Node, _ rhs: Node) -> Bool {
        lhs.directory == rhs.directory && lhs.device == rhs.device && lhs.inode == rhs.inode
            && lhs.linkCount == rhs.linkCount && lhs.byteCount == rhs.byteCount
            && lhs.modifiedSeconds == rhs.modifiedSeconds && lhs.modifiedNanoseconds == rhs.modifiedNanoseconds
            && lhs.changedSeconds == rhs.changedSeconds && lhs.changedNanoseconds == rhs.changedNanoseconds
    }

    static func sameDirectoryIdentity(_ lhs: Node, _ rhs: Node) -> Bool {
        lhs.directory && rhs.directory && lhs.device == rhs.device && lhs.inode == rhs.inode
    }
}

/// One physical kernel for private preparation, publication and reversal. It
/// retains no payload buffers and never deletes unknown or replaced paths.
/// The generation owner holds G outside its synchronous visibility methods;
/// this kernel acquires R and performs no actor hop inside either lock.
final class DraftPhotoRestorePreparedPublicationV1: @unchecked Sendable {
    let ownership: DraftPhotoRestoreRawOwnershipV1
#if DEBUG
    var failAfterStepForTesting: String?
    var beforeClaimForTesting: ((URL, Bool) throws -> Void)?
    private func observeForTesting(_ step: String) throws {
        if failAfterStepForTesting == step { throw DraftAttachmentStagingFailureV1.cleanupFailed }
    }
#endif
    private let owner: DraftStagingRootOwnerV1
    private let useLock = NSLock()
    private var consumed = false
    private var admittedClaimNodes: [String: Node] = [:]
    private typealias Node = DraftPhotoRestoreRawOwnershipV1.Node
    private static let failure = DraftAttachmentStagingFailureV1.staleStage

    private final class ClaimSource {
        let directory: DraftStagingRootOwnerV1.Directory?
        private(set) var file: Int32
        init(directory: DraftStagingRootOwnerV1.Directory) { self.directory = directory; file = -1 }
        init(file: Int32) { directory = nil; self.file = file }
        deinit { if file >= 0 { close(file) } }
    }

    private init(owner: DraftStagingRootOwnerV1, ownership: DraftPhotoRestoreRawOwnershipV1) {
        self.owner = owner; self.ownership = ownership
    }

    fileprivate static func prepare(authority: CheckRunnerPhotoRestoreRawAuthorityV1,
        verification: DraftPhotoBackupPreparedVerificationV1) throws -> Self {
        let owner = verification.owner
        return try verification.withRestorePreparationLock {
            try authority.transition.validate()
            guard authority.applicationSupportURL
                .appendingPathComponent(OwnedStorageRootKindV1.data.rawValue, isDirectory: true).appendingPathComponent(
                DraftAttachmentStagingAdapterV1.directoryName, isDirectory: true).standardizedFileURL
                    == owner.rootURL.standardizedFileURL,
                  authority.plan.source.workspaceID == authority.workspaceID.rawValue,
                  StoreMigrationCanonicalJSONV1.isLowercaseSHA256(authority.plannedBindingSHA256),
                  try DraftStagingRootOwnerV1.ManifestSnapshot(owner: owner).manifest.canonicalBytes()
                    == authority.transition.before.canonicalBytes(),
                  Set(authority.plan.rawPublications.map { $0.physicalEntry.entry.item.stageID })
                    .union(authority.transition.genericStageIDs)
                    == Set(authority.transition.newStageIDs + authority.transition.reusedStageIDs),
                  Set(authority.genericPayloads.keys)
                    == Set(authority.transition.genericStageIDs).intersection(authority.transition.newStageIDs),
                  authority.plan.rawPublications.allSatisfy({
                      authority.transition.after.entries.contains($0.physicalEntry.entry)
                  }) else {
                throw failure
            }
            let before = verification.namespaceFacts.map { key, facts in
                Node(path: String(key.dropFirst(key.hasPrefix("directory:") ? 10 : 5)),
                    directory: key.hasPrefix("directory:"), facts: facts)
            }
            let privateName = ".photo-restore-\(authority.restoreID.uuidString.lowercased())"
            let root = try owner.directory([])
            guard try !root.exists(privateName),
                  mkdirat(root.descriptor, privateName, 0o700) == 0 else { throw failure }
            // From here, failure retains the exclusive private bytes. Only a
            // durably saved ownership receipt may authorize later cleanup.
            var directories = Set([privateName])
            var expectedFiles: [String: V4BackupEntryV1] = [:]
            let added = Set(authority.transition.newStageIDs)
            for publication in authority.plan.rawPublications where added.contains(publication.physicalEntry.entry.item.stageID) {
                try Task.checkCancellation()
                let entry = publication.physicalEntry.entry
                guard authority.transition.after.entries.contains(entry),
                      entry.item.workspaceID == authority.workspaceID else { throw failure }
                let relative = DraftAttachmentStagingAdapterV1.relativeStageDirectory(
                    draftID: entry.item.draftID, stageID: entry.item.stageID)
                let parts = relative.split(separator: "/").map(String.init)
                guard parts.count == 2 else { throw failure }
                var components = [privateName]
                for part in parts {
                    let parent = try owner.directory(components)
                    components.append(part)
                    let path = components.joined(separator: "/")
                    if directories.insert(path).inserted {
                        guard mkdirat(parent.descriptor, part, 0o700) == 0 else { throw failure }
                    }
                }
                let directory = try owner.directory(components)
                expectedFiles["\(privateName)/\(relative)/payload.bin"] = publication.payload
                expectedFiles["\(privateName)/\(relative)/raw-publication.json"] = publication.witness
                try write(publication.payload, named: "payload.bin", directory: directory,
                    memberSource: authority.memberSource)
                try write(publication.witness, named: "raw-publication.json", directory: directory,
                    memberSource: authority.memberSource)
                let witness = try directory.openFile("raw-publication.json")
                do {
                    defer { close(witness) }
                    let facts = try DraftStagingRootOwnerV1.regular(witness)
                    guard facts.st_size == publication.witnessBytes.count,
                          try DraftStagingRootOwnerV1.read(witness, count: publication.witnessBytes.count)
                            == publication.witnessBytes else { throw failure }
                }
            }
            for stageID in authority.genericPayloads.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                try Task.checkCancellation()
                guard let payload = authority.genericPayloads[stageID],
                      let entry = authority.transition.after.entries.first(where: { $0.item.stageID == stageID }),
                      entry.item.workspaceID == authority.workspaceID,
                      payload == (try CheckRunnerPhotoRestoreGenericStageV1.payloadEntry(entry.item)) else { throw failure }
                let relative = DraftAttachmentStagingAdapterV1.relativeStageDirectory(
                    draftID: entry.item.draftID, stageID: stageID)
                var components = [privateName]
                for part in relative.split(separator: "/").map(String.init) {
                    let parent = try owner.directory(components)
                    components.append(part)
                    if directories.insert(components.joined(separator: "/")).inserted {
                        guard mkdirat(parent.descriptor, part, 0o700) == 0 else { throw failure }
                    }
                }
                let directory = try owner.directory(components)
                expectedFiles["\(privateName)/\(relative)/payload.bin"] = payload
                try write(payload, named: "payload.bin", directory: directory, memberSource: authority.memberSource,
                    maximumByteCount: Int64(FieldDraftLimitsV1.maximumPayloadBytes))
            }
            // Protect directories before their facts are frozen. No later
            // protection setter is permitted to silently replace these facts.
            for path in directories.sorted(by: { $0.count > $1.count }) {
                let directory = try owner.directory(path.split(separator: "/").map(String.init))
                try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: directory.url,
                    authorityCheck: { try directory.verifyNamed() })
                guard fsync(directory.descriptor) == 0 else { throw failure }
            }
            guard fsync(root.descriptor) == 0 else { throw failure }
            let created = try scan(owner: owner, beneath: [privateName], hashFiles: true)
            guard created.filter({ !$0.directory }).count == expectedFiles.count,
                  created.filter({ !$0.directory }).allSatisfy({ node in
                      guard let entry = expectedFiles[node.path] else { return false }
                      return node.byteCount == Int64(entry.byteCount) && node.sha256 == entry.sha256
                  }) else { throw failure }
            let receipt = try DraftPhotoRestoreRawOwnershipV1(restoreID: authority.restoreID,
                plannedBindingSHA256: authority.plannedBindingSHA256, transition: authority.transition,
                beforeNodes: before, createdNodes: created)
            let prepared = Self(owner: owner, ownership: receipt)
            try prepared.requireCurrent(mode: .prepared, hashFiles: false)
            return prepared
        }
    }

    private static func write(_ entry: V4BackupEntryV1, named name: String,
        directory: DraftStagingRootOwnerV1.Directory, memberSource: CheckRunnerPhotoRestoreMemberSourceV1,
        maximumByteCount: Int64 = Int64(MediaContractV1.sourceByteCountMaximum)) throws {
        let file = openat(directory.descriptor, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard file >= 0 else { throw failure }
        defer { close(file) }
        try memberSource.read(entry, maximumByteCount: maximumByteCount) { bytes in
            try Task.checkCancellation()
            try directory.verifyNamed()
            try DraftStagingRootOwnerV1.write(bytes, to: file)
        }
        try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, relativePath: name, within: directory.url,
            authorityCheck: { try directory.verifyNamed(); try directory.verifyFile(file, name: name) })
        guard fsync(file) == 0 else { throw failure }
        try directory.verifyFile(file, name: name)
    }

    private static func digest(_ fd: Int32, facts: stat) throws -> String {
        var hash = SHA256(), offset: Int64 = 0
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while offset < facts.st_size {
            try Task.checkCancellation()
            let wanted = Int(min(Int64(chunk.count), facts.st_size - offset))
            let count = chunk.withUnsafeMutableBytes { pread(fd, $0.baseAddress, wanted, off_t(offset)) }
            guard count > 0, count <= wanted else { throw failure }
            hash.update(data: Data(chunk.prefix(count))); offset += Int64(count)
        }
        try DraftStagingRootOwnerV1.unchanged(fd, facts)
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func scan(owner: DraftStagingRootOwnerV1, beneath components: [String],
        hashFiles: Bool) throws -> [Node] {
        var result: [Node] = []
        func walk(_ parts: [String]) throws {
            try Task.checkCancellation()
            guard parts.count <= 4, result.count <= FieldDraftLimitsV1.maximumStageItems * 9 + 4 else { throw failure }
            let directory = try owner.directory(parts)
            try ProtectedFilePolicyV1.verify(.stagingDirectory, at: directory.url)
            let path = parts.isEmpty ? "." : parts.joined(separator: "/")
            result.append(.init(path: path, directory: true, facts: DraftPhotoRawBackupSnapshotV1.facts(directory.identity)))
            let names = try directory.names()
            guard names.count <= FieldDraftLimitsV1.maximumStageItems * 2 + 3 else { throw failure }
            for name in names.sorted() {
                var facts = stat()
                guard fstatat(directory.descriptor, name, &facts, AT_SYMLINK_NOFOLLOW) == 0 else { throw failure }
                if facts.st_mode & S_IFMT == S_IFDIR { try walk(parts + [name]) }
                else {
                    let file = try directory.openFile(name)
                    defer { close(file) }
                    let opened = try DraftStagingRootOwnerV1.regular(file)
                    guard opened.st_dev == facts.st_dev, opened.st_ino == facts.st_ino else { throw failure }
                    try ProtectedFilePolicyV1.verify(.stagingFile, at: directory.url.appendingPathComponent(name))
                    let digest = hashFiles ? try digest(file, facts: opened) : nil
                    result.append(.init(path: (parts + [name]).joined(separator: "/"), directory: false,
                        facts: DraftPhotoRawBackupSnapshotV1.facts(opened), sha256: digest))
                    guard result.count <= FieldDraftLimitsV1.maximumStageItems * 9 + 4 else { throw failure }
                    try directory.verifyPinnedFile(file, name: name, facts: opened)
                }
            }
            guard try directory.names() == names else { throw failure }
        }
        try walk(components)
        return result.sorted { $0.path < $1.path }
    }

    private enum Mode: Equatable { case prepared, publishing, committed, rollingBack }

    /// Finds each entire parent or individual stage in exactly one possible
    /// location. A rollback may have already removed an owned private group.
    private func placements(mode: Mode) throws -> [String: String?] {
        let old = Set(ownership.beforeNodes.filter(\.directory).map(\.path))
        var roots = Set<String>()
        for entry in ownership.transition.after.entries where ownership.transition.newStageIDs.contains(entry.item.stageID) {
            let stage = DraftAttachmentStagingAdapterV1.relativeStageDirectory(
                draftID: entry.item.draftID, stageID: entry.item.stageID)
            let parent = String(stage.split(separator: "/")[0])
            roots.insert(old.contains(parent) ? stage : parent)
        }
        var result: [String: String?] = [:]
        for relative in roots {
            let privatePath = "\(ownership.privateName)/\(relative)"
            func exists(_ path: String) throws -> Bool {
                let parts = path.split(separator: "/").map(String.init)
                var directory = try owner.directory([])
                for part in parts.dropLast() {
                    guard try directory.exists(part) else { return false }
                    directory = try owner.directory(directory.components + [part])
                }
                return try directory.exists(parts.last!)
            }
            let hidden = try exists(privatePath), visible = try exists(relative)
            guard !(hidden && visible) else { throw Self.failure }
            switch mode {
            case .prepared: guard hidden && !visible else { throw Self.failure }
            case .publishing: guard hidden || visible else { throw Self.failure }
            case .committed: guard visible && !hidden else { throw Self.failure }
            case .rollingBack: break
            }
            // updateValue preserves an explicit nil value in this dictionary.
            result.updateValue(hidden ? privatePath : (visible ? relative : nil), forKey: relative)
        }
        return result
    }

    private func requireCurrent(mode: Mode, hashFiles: Bool) throws {
        try ownership.validate()
        let actualManifest = try DraftStagingRootOwnerV1.ManifestSnapshot(owner: owner).manifest.canonicalBytes()
        let before = try ownership.transition.before.canonicalBytes(), after = try ownership.transition.after.canonicalBytes()
        switch mode {
        case .prepared: guard actualManifest == before else { throw Self.failure }
        case .committed: guard actualManifest == after else { throw Self.failure }
        case .publishing, .rollingBack: guard actualManifest == before || actualManifest == after else { throw Self.failure }
        }
        // An old-pointer recovery may first encounter the complete after image.
        // Claims are admitted only after rollback has restored the before image.
        let placementMode: Mode = mode == .rollingBack && actualManifest == after && before != after
            ? .committed : mode
        let claimsAllowed = (mode == .rollingBack && actualManifest == before)
            || (mode == .committed && actualManifest == after)
        let locations = try placements(mode: placementMode)
        var expected = Dictionary(uniqueKeysWithValues: ownership.beforeNodes.map { ($0.path, $0) })
        var required = Set(expected.keys)
        var claimExpected: [String: Node] = [:]
        var normalForClaim: [String: String] = [:]
        for node in ownership.createdNodes {
            let suffix = String(node.path.dropFirst(ownership.privateName.count + 1))
            let group = locations.keys.first { suffix == $0 || suffix.hasPrefix($0 + "/") }
            var path = node.path
            if let group {
                guard let wrapped = locations[group], let location = wrapped else {
                    if claimsAllowed, mode == .rollingBack, let claim = node.claimPath {
                        guard claimExpected.updateValue(node, forKey: claim) == nil else { throw Self.failure }
                    }
                    continue
                }
                path = location + suffix.dropFirst(group.count)
                if location == group || placementMode != .rollingBack { required.insert(path) }
            } else if placementMode == .prepared || placementMode == .publishing { required.insert(path) }
            guard expected[path] == nil else { throw Self.failure }
            expected[path] = node
            if claimsAllowed, let claim = node.claimPath,
               mode == .rollingBack || (mode == .committed && node.directory && group == nil) {
                guard claimExpected.updateValue(node, forKey: claim) == nil else { throw Self.failure }
                normalForClaim[claim] = path
            }
        }
        let observed = try Self.scan(owner: owner, beneath: [], hashFiles: false)
        let genericIDs = Set(ownership.transition.genericStageIDs)
        let incumbentGenericDigests = Dictionary(uniqueKeysWithValues:
            ownership.transition.before.entries.compactMap { entry -> (String, String)? in
                guard genericIDs.contains(entry.item.stageID),
                      let digest = entry.item.contentDigest, digest.algorithm == .sha256 else { return nil }
                return (entry.relativeDataPath, digest.hexadecimalValue)
            })
        let observedPaths = Set(observed.map(\.path))
        guard observedPaths.isSubset(of: Set(expected.keys).union(claimExpected.keys)),
              required.isSubset(of: observedPaths),
              normalForClaim.allSatisfy({ claim, normal in
                  !(observedPaths.contains(claim) && observedPaths.contains(normal))
              }) else { throw Self.failure }
        admittedClaimNodes = admittedClaimNodes.filter { observedPaths.contains($0.key) }
        for node in observed {
            if let expectedClaim = claimExpected[node.path] {
                let parts = node.path.split(separator: "/").map(String.init)
                let parent = try owner.directory(Array(parts.dropLast()))
                let name = parts.last!
                let frozen: Node
                if expectedClaim.directory {
                    let directory = try owner.directory(parts)
                    guard try directory.names().isEmpty else { throw Self.failure }
                    var facts = stat()
                    guard fstat(directory.descriptor, &facts) == 0 else { throw Self.failure }
                    let candidate = Node(path: node.path, directory: true,
                        facts: DraftPhotoRawBackupSnapshotV1.facts(facts))
                    if let admitted = admittedClaimNodes[node.path] {
                        guard admitted.strictlyMatches(facts) else { throw Self.failure }
                        frozen = admitted
                    } else {
                        guard hashFiles, expectedClaim.admitsClaim(candidate) else { throw Self.failure }
                        frozen = candidate
                    }
                    try directory.verifyNamed()
                } else {
                    let file = try parent.openFile(name)
                    defer { close(file) }
                    let facts = try DraftStagingRootOwnerV1.regular(file)
                    if let admitted = admittedClaimNodes[node.path] {
                        guard admitted.strictlyMatches(facts) else { throw Self.failure }
                        frozen = admitted
                    } else {
                        guard hashFiles, let digest = expectedClaim.sha256 else { throw Self.failure }
                        let candidate = Node(path: node.path, directory: false,
                            facts: DraftPhotoRawBackupSnapshotV1.facts(facts),
                            sha256: try Self.digest(file, facts: facts))
                        guard candidate.sha256 == digest, expectedClaim.admitsClaim(candidate) else {
                            throw Self.failure
                        }
                        frozen = candidate
                    }
                    try parent.verifyPinnedFile(file, name: name, facts: facts)
                }
                admittedClaimNodes[node.path] = frozen
                continue
            }
            if node.path == DraftAttachmentStagingAdapterV1.manifestName, placementMode != .prepared { continue }
            guard let expected = expected[node.path] else { throw Self.failure }
            let parts = node.path == "." ? [] : node.path.split(separator: "/").map(String.init)
            if expected.directory {
                let directory = try owner.directory(parts)
                guard expected.matches(directory.identity) else { throw Self.failure }
            } else {
                let directory = try owner.directory(Array(parts.dropLast()))
                let name = parts.last!, file = try directory.openFile(name)
                defer { close(file) }
                let facts = try DraftStagingRootOwnerV1.regular(file)
                guard expected.matches(facts) else { throw Self.failure }
                if hashFiles, let expectedDigest = expected.sha256 ?? incumbentGenericDigests[node.path] {
                    guard try Self.digest(file, facts: facts) == expectedDigest else { throw Self.failure }
                }
                try directory.verifyPinnedFile(file, name: name, facts: facts)
            }
        }
    }

    private func requirePermit(_ permit: CheckRunnerPhotoRestoreRawPublicationPermitV1) throws {
        guard permit.restoreID == ownership.restoreID,
              permit.plannedBindingSHA256 == ownership.plannedBindingSHA256,
              try permit.ownershipSHA256 == ownership.sha256 else { throw Self.failure }
    }

    fileprivate static func reopen(owner: DraftStagingRootOwnerV1,
        ownership: DraftPhotoRestoreRawOwnershipV1, permit: CheckRunnerPhotoRestoreRawPublicationPermitV1,
        rollback: Bool) throws -> Self {
        let value = Self(owner: owner, ownership: ownership)
        try value.requirePermit(permit)
        let lock = try owner.acquire(); defer { lock.release() }
        try value.requireCurrent(mode: rollback ? .rollingBack : .committed, hashFiles: true)
        return value
    }

    private func consume() throws {
        useLock.lock(); defer { useLock.unlock() }
        guard !consumed else { throw Self.failure }
        consumed = true
    }

    func publish(permit: CheckRunnerPhotoRestoreRawPublicationPermitV1,
        publishingPointer: () throws -> Void) throws {
        try consume()
        try requirePermit(permit)
        let lock = try owner.acquire(); defer { lock.release() }
        try requireCurrent(mode: .prepared, hashFiles: false)
        let locations = try placements(mode: .prepared)
        for relative in locations.keys.sorted() {
            guard let wrapped = locations[relative], let location = wrapped else { throw Self.failure }
            if location == relative { continue }
            try move(from: location, to: relative)
#if DEBUG
            try observeForTesting("public-group")
#endif
        }
        try requireCurrent(mode: .publishing, hashFiles: false)
        try replaceManifest(ownership.transition.after)
#if DEBUG
        try observeForTesting("after-manifest")
#endif
        try requireCurrent(mode: .committed, hashFiles: false)
        try publishingPointer()
        try requireCurrent(mode: .committed, hashFiles: false)
    }

    private func move(from: String, to: String) throws {
        let a = from.split(separator: "/").map(String.init), b = to.split(separator: "/").map(String.init)
        let source = try owner.directory(Array(a.dropLast())), target = try owner.directory(Array(b.dropLast()))
        try source.verifyNamed(); try target.verifyNamed()
        let privatePath = from.hasPrefix(ownership.privateName + "/") ? from : to
        guard let expected = ownership.createdNodes.first(where: { $0.path == privatePath && $0.directory }),
              expected.matches(try owner.directory(a).identity) else { throw Self.failure }
        guard renameatx_np(source.descriptor, a.last!, target.descriptor, b.last!, UInt32(RENAME_EXCL)) == 0,
              fsync(source.descriptor) == 0, fsync(target.descriptor) == 0 else { throw Self.failure }
        guard expected.matches(try owner.directory(b).identity) else { throw Self.failure }
    }

    /// Called only while the incumbent restore owner proves the old generation
    /// is still active. The before manifest is restored before any owned group
    /// is moved back under the private container and removed.
    func rollback(permit: CheckRunnerPhotoRestoreRawPublicationPermitV1) throws {
        try consume()
        try requirePermit(permit)
        let lock = try owner.acquire(); defer { lock.release() }
        try requireCurrent(mode: .rollingBack, hashFiles: false)
        try replaceManifest(ownership.transition.before)
        let locations = try placements(mode: .rollingBack)
        for relative in locations.keys.sorted() {
            guard let wrapped = locations[relative], let location = wrapped else { continue }
            if location == relative {
                try move(from: relative, to: "\(ownership.privateName)/\(relative)")
#if DEBUG
                try observeForTesting("private-group")
#endif
            }
        }
        try requireCurrent(mode: .rollingBack, hashFiles: false)
        try removePrivateTree()
        try requireCurrent(mode: .rollingBack, hashFiles: false)
        guard try placements(mode: .rollingBack).values.allSatisfy({ $0 == nil }) else { throw Self.failure }
    }

    /// The new pointer and canonical destination must be verified by the
    /// restore owner first. Only empty, inode-proven private scaffolding remains.
    func finish(permit: CheckRunnerPhotoRestoreRawPublicationPermitV1) throws {
        try consume()
        try requirePermit(permit)
        let lock = try owner.acquire(); defer { lock.release() }
        try requireCurrent(mode: .committed, hashFiles: false)
        try removePrivateTree()
        try requireCurrent(mode: .committed, hashFiles: false)
    }

    private func removePrivateTree() throws {
        // The whole operation census was checked immediately before this
        // method. Each node is first claimed under its exact receipt-reserved
        // private name. A crash may leave that one claim; cold recovery hashes
        // and freezes it before deletion. A mismatched claim is preserved.
        for expected in ownership.createdNodes.sorted(by: {
            let a = $0.path.split(separator: "/").count, b = $1.path.split(separator: "/").count
            return a == b ? $0.path > $1.path : a > b
        }) {
            guard let claimPath = expected.claimPath else { throw Self.failure }
            let original = try namedLocation(expected.path), claim = try namedLocation(claimPath)
            let originalExists = try original.map { try $0.parent.exists($0.name) } ?? false
            let claimExists = try claim.map { try $0.parent.exists($0.name) } ?? false
            guard !(originalExists && claimExists) else { throw Self.failure }
            if claimExists {
                guard let claim, let frozen = admittedClaimNodes[claimPath] else { throw Self.failure }
                try removeClaim(expected: expected, frozen: frozen, parent: claim.parent, name: claim.name)
            } else if originalExists {
                guard let original, let claim else { throw Self.failure }
                let source = try requireOriginalForClaim(expected, parent: original.parent, name: original.name)
#if DEBUG
                try beforeClaimForTesting?(original.parent.url.appendingPathComponent(original.name,
                    isDirectory: expected.directory), expected.directory)
#endif
                try original.parent.verifyNamed(); try claim.parent.verifyNamed()
                guard renameatx_np(original.parent.descriptor, original.name,
                        claim.parent.descriptor, claim.name, UInt32(RENAME_EXCL)) == 0,
                      fsync(original.parent.descriptor) == 0 else { throw Self.failure }
                let frozen = try freezeOwnedClaim(expected, source: source,
                    parent: claim.parent, name: claim.name)
                admittedClaimNodes[claimPath] = frozen
#if DEBUG
                try observeForTesting("after-claim")
#endif
                try removeClaim(expected: expected, frozen: frozen, parent: claim.parent, name: claim.name)
            }
#if DEBUG
            if !expected.directory { try observeForTesting("private-file-deletion") }
#endif
        }
    }

    private func namedLocation(_ path: String) throws
        -> (parent: DraftStagingRootOwnerV1.Directory, name: String)? {
        let parts = path.split(separator: "/").map(String.init)
        guard let name = parts.last else { throw Self.failure }
        var parent = try owner.directory([])
        for component in parts.dropLast() {
            if try !parent.exists(component) { return nil }
            parent = try owner.directory(parent.components + [component])
        }
        return (parent, name)
    }

    private func requireOriginalForClaim(_ expected: Node,
        parent: DraftStagingRootOwnerV1.Directory, name: String) throws -> ClaimSource {
        if expected.directory {
            let directory = try owner.directory(parent.components + [name])
            guard expected.matches(directory.identity), try directory.names().isEmpty else { throw Self.failure }
            try directory.verifyNamed()
            return ClaimSource(directory: directory)
        }
        let file = try parent.openFile(name)
        do {
            let facts = try DraftStagingRootOwnerV1.regular(file)
            guard expected.matches(facts) else { throw Self.failure }
            try parent.verifyPinnedFile(file, name: name, facts: facts)
            return ClaimSource(file: file)
        } catch { close(file); throw error }
    }

    /// Called immediately after this operation's exclusive rename. The old
    /// ctime is not reused: exact causal post-claim facts are frozen instead.
    private func freezeOwnedClaim(_ expected: Node, source: ClaimSource,
        parent: DraftStagingRootOwnerV1.Directory, name: String) throws -> Node {
        guard let path = expected.claimPath else { throw Self.failure }
        if expected.directory {
            guard let sourceDirectory = source.directory else { throw Self.failure }
            var sourceFacts = stat()
            guard fstat(sourceDirectory.descriptor, &sourceFacts) == 0 else { throw Self.failure }
            let directory = try owner.directory(parent.components + [name])
            guard directory.identity.st_dev == sourceFacts.st_dev,
                  directory.identity.st_ino == sourceFacts.st_ino,
                  try directory.names().isEmpty else { throw Self.failure }
            var claimedFacts = stat()
            guard fstat(directory.descriptor, &claimedFacts) == 0,
                  claimedFacts.st_dev == sourceFacts.st_dev,
                  claimedFacts.st_ino == sourceFacts.st_ino else { throw Self.failure }
            let frozen = Node(path: path, directory: true,
                facts: DraftPhotoRawBackupSnapshotV1.facts(claimedFacts))
            guard expected.admitsClaim(frozen) else { throw Self.failure }
            try directory.verifyNamed()
            return frozen
        }
        guard source.file >= 0 else { throw Self.failure }
        let facts = try DraftStagingRootOwnerV1.regular(source.file)
        let frozen = Node(path: path, directory: false,
            facts: DraftPhotoRawBackupSnapshotV1.facts(facts), sha256: expected.sha256)
        guard expected.admitsClaim(frozen) else { throw Self.failure }
        try parent.verifyPinnedFile(source.file, name: name, facts: facts)
        return frozen
    }

    private func removeClaim(expected: Node, frozen: Node,
        parent: DraftStagingRootOwnerV1.Directory, name: String) throws {
        guard expected.claimPath == frozen.path, try parent.exists(name) else { throw Self.failure }
        if expected.directory {
            let directory = try owner.directory(parent.components + [name])
            guard try directory.names().isEmpty else {
                throw Self.failure
            }
            var facts = stat()
            guard fstat(directory.descriptor, &facts) == 0, frozen.strictlyMatches(facts) else {
                throw Self.failure
            }
            try directory.verifyNamed(); try parent.verifyNamed()
            var after = stat()
            guard unlinkat(parent.descriptor, name, AT_REMOVEDIR) == 0,
                  fstat(directory.descriptor, &after) == 0, frozen.provesUnlinked(after),
                  fsync(parent.descriptor) == 0 else {
                throw Self.failure
            }
        } else {
            let file = try parent.openFile(name)
            defer { close(file) }
            let facts = try DraftStagingRootOwnerV1.regular(file)
            guard frozen.strictlyMatches(facts) else { throw Self.failure }
            try parent.verifyPinnedFile(file, name: name, facts: facts)
            var after = stat()
            guard unlinkat(parent.descriptor, name, 0) == 0,
                  fstat(file, &after) == 0, frozen.provesUnlinked(after),
                  fsync(parent.descriptor) == 0 else { throw Self.failure }
        }
        admittedClaimNodes.removeValue(forKey: frozen.path)
    }

    private func replaceManifest(_ manifest: DraftAttachmentStagingManifestV1) throws {
        let bytes = try manifest.canonicalBytes()
        if try DraftStagingRootOwnerV1.ManifestSnapshot(owner: owner).manifest.canonicalBytes() != bytes {
            try DraftStagingRootOwnerV1.replaceFile(bytes,
                at: owner.rootURL.appendingPathComponent(DraftAttachmentStagingAdapterV1.manifestName),
                directory: owner.directory([]))
        }
        guard try DraftStagingRootOwnerV1.ManifestSnapshot(owner: owner).manifest.canonicalBytes() == bytes else {
            throw Self.failure
        }
    }
}

extension DraftAttachmentStagingAdapterV1 {
    func preparePhotoRestoreRawPublication(authority: CheckRunnerPhotoRestoreRawAuthorityV1,
        currentVerification: DraftPhotoBackupPreparedVerificationV1) async throws
        -> DraftPhotoRestorePreparedPublicationV1 {
        guard authority.applicationSupportURL.standardizedFileURL == applicationSupportURL,
              authority.workspaceID == workspaceScope,
              currentVerification.owner.rootURL.standardizedFileURL == rootURL.standardizedFileURL else {
            throw DraftAttachmentStagingFailureV1.wrongWorkspace
        }
        try beginOperation(); defer { operationInFlight = false }
        let task = Task.detached(priority: .userInitiated) {
            try DraftPhotoRestorePreparedPublicationV1.prepare(authority: authority, verification: currentVerification)
        }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }

    func reopenPhotoRestoreRawPublication(ownership: DraftPhotoRestoreRawOwnershipV1,
        permit: CheckRunnerPhotoRestoreRawPublicationPermitV1, rollback: Bool) async throws
        -> DraftPhotoRestorePreparedPublicationV1 {
        guard let workspaceScope,
              ownership.transition.after.entries.allSatisfy({ $0.item.workspaceID == workspaceScope }) else {
            throw DraftAttachmentStagingFailureV1.wrongWorkspace
        }
        try beginOperation(); defer { operationInFlight = false }
        let owner = rootOwner
        let task = Task.detached(priority: .userInitiated) {
            try DraftPhotoRestorePreparedPublicationV1.reopen(owner: owner, ownership: ownership,
                permit: permit, rollback: rollback)
        }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }

    /// The complete old-root census is checked through the existing backup
    /// verifier before freezing reversible values. No stage or manifest changes.
    func preparePhotoRestoreRawTransition(sourcePlan: CheckRunnerPhotoBackupRestorePlanV1,
        sourceHistory: CheckRunnerPhotoBackupHistoryV1,
        currentSnapshots: [DraftPhotoRawBackupSnapshotV1],
        currentCommittingCheckpoints: [UUID: FieldDraftCheckpointV1],
        currentCanonicalStages: [AttachmentStagingItemV1],
        currentChildStageIDs: [UUID: UUID], retainedCurrentStageIDs: Set<UUID>,
        genericEntries: [DraftAttachmentStagingEntryV1] = []) async throws
        -> DraftPhotoRestoreRawTransitionV1 {
        guard let workspaceScope, sourceHistory.sourceWorkspaceID == workspaceScope,
              sourceHistory.source.workspaceID == workspaceScope.rawValue,
              sourcePlan.source.workspaceID == workspaceScope.rawValue else {
            throw DraftAttachmentStagingFailureV1.wrongWorkspace
        }
        let proof = try await preparePhotoBackupVerification(currentSnapshots,
            committingCheckpoints: currentCommittingCheckpoints,
            canonicalStages: currentCanonicalStages, childStageIDs: currentChildStageIDs)
        return try proof.withVerificationLock {
            let before = try DraftStagingRootOwnerV1.ManifestSnapshot(owner: rootOwner).manifest
            return try DraftPhotoRestoreRawTransitionV1(before: before, sourcePlan: sourcePlan,
                sourceHistory: sourceHistory, currentSnapshots: currentSnapshots,
                retainedCurrentStageIDs: retainedCurrentStageIDs, genericEntries: genericEntries)
        }
    }
}

extension DraftAttachmentStagingAdapterV1 {
    /// Freezes the exact populated incumbent namespace. This read-only step
    /// creates no private scaffold and supplies the plan that the restore
    /// service commits before it mints filesystem authority.
    func prepareConfigurationCloneRetirementPlan(restoreID: UUID,
        currentVerification: DraftPhotoBackupPreparedVerificationV1) throws
        -> DraftConfigurationCloneRetirementPlanV1 {
        guard let workspaceScope,
              currentVerification.owner.rootURL.standardizedFileURL == rootURL.standardizedFileURL else {
            throw DraftAttachmentStagingFailureV1.wrongWorkspace
        }
        return try DraftConfigurationCloneRetirementFilesystemV1.capturePlan(
            restoreID: restoreID, workspaceID: workspaceScope, verification: currentVerification)
    }

    /// Reproves a durably planned before image without creating or claiming
    /// any path. Cold recovery uses this before an ownership record exists.
    nonisolated func verifyConfigurationCloneRetirementPlan(
        authority: DraftConfigurationCloneRetirementAuthorityV1) throws {
        guard let workspaceScope, authority.plan.workspaceID == workspaceScope,
              authority.applicationSupportURL.standardizedFileURL == applicationSupportURL,
              currentRoot(for: authority.applicationSupportURL) == rootURL.standardizedFileURL,
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(authority.bindingSHA256) else {
            throw DraftAttachmentStagingFailureV1.wrongWorkspace
        }
        let held = try rootOwner.acquire(); defer { held.release() }
        try DraftConfigurationCloneRetirementFilesystemV1.requireBefore(
            authority.plan, owner: rootOwner, strictManifestFacts: true)
    }

    /// Creates only the exclusive protected scaffold after the restore owner
    /// has durably bound the exact plan. Incumbent bytes remain in place.
    func prepareConfigurationCloneRetirement(
        authority: DraftConfigurationCloneRetirementAuthorityV1,
        currentVerification: DraftPhotoBackupPreparedVerificationV1) throws
        -> DraftConfigurationCloneRetirementPreparedV1 {
        guard let workspaceScope, authority.plan.workspaceID == workspaceScope,
              authority.applicationSupportURL.standardizedFileURL == applicationSupportURL,
              currentVerification.owner.rootURL.standardizedFileURL == rootURL.standardizedFileURL else {
            throw DraftAttachmentStagingFailureV1.wrongWorkspace
        }
        return try DraftConfigurationCloneRetirementPreparedV1.prepare(
            authority: authority, verification: currentVerification)
    }

    /// Opens immutable ownership without actor isolation or filesystem effects.
    /// The returned one-shot kernel still takes R for every observation or
    /// mutation and requires a fresh opaque permit for the chosen operation.
    nonisolated func reopenConfigurationCloneRetirement(
        authority: DraftConfigurationCloneRetirementAuthorityV1,
        ownership: DraftConfigurationCloneRetirementOwnershipV1) throws
        -> DraftConfigurationCloneRetirementPreparedV1 {
        guard let workspaceScope, authority.plan.workspaceID == workspaceScope,
              authority.applicationSupportURL.standardizedFileURL == applicationSupportURL,
              currentRoot(for: authority.applicationSupportURL) == rootURL.standardizedFileURL else {
            throw DraftAttachmentStagingFailureV1.wrongWorkspace
        }
        return try DraftConfigurationCloneRetirementPreparedV1.reopen(
            authority: authority, ownership: ownership, owner: rootOwner)
    }

    private nonisolated func currentRoot(for support: URL) -> URL {
        support.standardizedFileURL
            .appendingPathComponent(OwnedStorageRootKindV1.data.rawValue, isDirectory: true)
            .appendingPathComponent(Self.directoryName, isDirectory: true)
            .standardizedFileURL
    }
}

/// Receipt for adopting staged bytes from a backup restore staging root.  The
/// destination draft root and the generation root are separate authorities;
/// therefore this receipt explicitly refuses to claim a cross-root atomic
/// transaction.  The canonical draft commit must still reconcile the adopted
/// rows before they can become user-visible content.
struct DraftAttachmentRestorePublicationReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let restoreID: UUID
    let workspaceID: WorkspaceID
    let sourceManifestSHA256: String
    let adoptedStageIDs: [UUID]
    let reusedStageIDs: [UUID]
    let atomicAcrossRoots: Bool
    let canonicalCommitRequired: Bool
    let publishedAt: Date

    init(
        restoreID: UUID,
        workspaceID: WorkspaceID,
        sourceManifestSHA256: String,
        adoptedStageIDs: [UUID],
        reusedStageIDs: [UUID],
        publishedAt: Date
    ) throws {
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0,
                               0, 0, 0, 0, 0, 0, 0, 0))
        guard restoreID != zero, workspaceID.rawValue != zero,
              KernelCanonicalHashV1.validSHA256(sourceManifestSHA256),
              adoptedStageIDs == adoptedStageIDs.sorted(by: Self.uuidLess),
              reusedStageIDs == reusedStageIDs.sorted(by: Self.uuidLess),
              Set(adoptedStageIDs).isDisjoint(with: Set(reusedStageIDs)),
              Set(adoptedStageIDs).count == adoptedStageIDs.count,
              Set(reusedStageIDs).count == reusedStageIDs.count,
              publishedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw DraftAttachmentStagingFailureV1.invalidAttachment
        }
        schemaVersion = Self.schemaVersion
        self.restoreID = restoreID
        self.workspaceID = workspaceID
        self.sourceManifestSHA256 = sourceManifestSHA256
        self.adoptedStageIDs = adoptedStageIDs
        self.reusedStageIDs = reusedStageIDs
        atomicAcrossRoots = false
        canonicalCommitRequired = true
        self.publishedAt = publishedAt
    }

    func validate() throws {
        let value = try Self(
            restoreID: restoreID,
            workspaceID: workspaceID,
            sourceManifestSHA256: sourceManifestSHA256,
            adoptedStageIDs: adoptedStageIDs,
            reusedStageIDs: reusedStageIDs,
            publishedAt: publishedAt
        )
        guard schemaVersion == Self.schemaVersion,
              atomicAcrossRoots == false,
              canonicalCommitRequired,
              value == self else {
            throw DraftAttachmentStagingFailureV1.corruptManifest
        }
    }

    fileprivate static func uuidLess(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString.lowercased() < rhs.uuidString.lowercased()
    }
}

extension DraftAttachmentStagingAdapterV1 {
    /// Adopts backup-restored staging bytes into the draft-owned operational
    /// root.  The source may be either the adapter-relative layout or the
    /// backup package's `draft-staging/<draft>/<stage>.bin` layout; all
    /// candidates are constrained beneath `sourceRootURL` and verified by
    /// digest/length before a destination write.  No generation pointer or
    /// cross-filesystem atomicity is asserted.
    @discardableResult
    func adoptRestoredStaging(
        from sourceRootURL: URL,
        entries: [DraftAttachmentStagingEntryV1],
        workspaceID: WorkspaceID,
        sourceManifestSHA256: String,
        restoreID: UUID
    ) throws -> DraftAttachmentRestorePublicationReceiptV1 {
        let rootLock = try lockAndReload()
        defer { rootLock.release() }
        let kernel = publicationKernel
        return try kernel.adopt(
            from: sourceRootURL, entries: entries, workspaceID: workspaceID,
            sourceManifestSHA256: sourceManifestSHA256, restoreID: restoreID,
            manifest: &manifest
        )
    }

    /// Completes the existing publication operation while its new adapter is
    /// still being initialized. No actor reference escapes into the operation.
    static func publishRestoredStagingSynchronously(
        applicationSupportURL: URL,
        from sourceRootURL: URL,
        entries: [DraftAttachmentStagingEntryV1],
        workspaceID: WorkspaceID,
        sourceManifestSHA256: String,
        restoreID: UUID,
        fileManager: FileManager = .default,
        clock: @escaping Clock = { Date() }
    ) throws -> DraftAttachmentRestorePublicationReceiptV1 {
        let adapter = try Self(
            applicationSupportURL: applicationSupportURL,
            workspaceID: workspaceID,
            fileManager: fileManager,
            clock: clock,
            restorePublication: RestorePublicationInput(
                sourceRootURL: sourceRootURL, entries: entries,
                workspaceID: workspaceID, sourceManifestSHA256: sourceManifestSHA256,
                restoreID: restoreID
            )
        )
        guard let receipt = adapter.initialPublicationReceipt else {
            throw DraftAttachmentStagingFailureV1.corruptManifest
        }
        return receipt
    }
}

// These canonical path projections are shared by the backup adapter when it
// enumerates the same draft-owned staging root.  They do not expose a mutable
// writer or a filesystem handle.
extension DraftAttachmentStagingAdapterV1 {
    /// The existing promotion identity projection, also used for receipt readback.
    static func deterministicUUID(_ material: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(material.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
            bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Shared pure identity for inspected raw content and the existing stage promotion.
    static func contentID(workspaceID: WorkspaceID, digest: ContentDigestV1) -> String {
        "draft-content-\(workspaceID.rawValue.uuidString.lowercased())-\(digest.hexadecimalValue)"
    }

    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func relativeStageDirectory(draftID: UUID, stageID: UUID) -> String {
        "draft-\(draftID.uuidString.lowercased())/stage-\(stageID.uuidString.lowercased())"
    }

    static func relativeDataPath(draftID: UUID, stageID: UUID) -> String {
        relativeStageDirectory(draftID: draftID, stageID: stageID) + "/" + payloadName
    }
}

private extension DraftAttachmentStagingAdapterV1 {
    func beginOperation() throws {
        guard !operationInFlight else { throw DraftAttachmentStagingFailureV1.staleStage }
        operationInFlight = true
    }

    func lockAndReload() throws -> DraftStagingRootOwnerV1.Lock {
        guard !operationInFlight else { throw DraftAttachmentStagingFailureV1.staleStage }
        let lock = try rootOwner.acquire()
        do { try reloadManifest(); return lock }
        catch { lock.release(); throw error }
    }

    func reloadManifest() throws {
        manifest = try DraftStagingRootOwnerV1.ManifestSnapshot(owner: rootOwner).manifest
    }

    func hasPhotoOwnership(_ entry: DraftAttachmentStagingEntryV1) -> Bool {
        let components = entry.relativeDataPath.split(separator: "/").dropLast().map(String.init)
        do {
            let directory = try rootOwner.directory(components)
            return try directory.exists("raw-publication.json")
        } catch {
            // An unsafe/unreadable directory never grants generic cleanup
            // authority. An actually absent directory is handled by recovery.
            let url = rootURL.appendingPathComponent(entry.relativeDataPath).deletingLastPathComponent()
            return DraftStagingRootOwnerV1.pathExists(url)
        }
    }

    func denyPhotoOwnership(_ entry: DraftAttachmentStagingEntryV1) throws {
        guard !hasPhotoOwnership(entry) else { throw DraftAttachmentStagingFailureV1.invalidTransition }
    }

    struct ScratchCopy: Sendable {
        let bytes: Data
        let leaseID: UUID
    }

    static let zero = UUID(uuid: (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    ))

    func validateScope(workspaceID: WorkspaceID, draftID: UUID, stageID: UUID) throws {
        try publicationKernel.validateScope(workspaceID: workspaceID, draftID: draftID, stageID: stageID)
    }

    func copyThroughScratch(
        _ data: Data,
        draftID: UUID,
        stageID: UUID,
        mutationID: MutationIDV1,
        now: Date
    ) async throws -> ScratchCopy {
        try Task.checkCancellation()
        guard data.count > 0, data.count <= FieldDraftLimitsV1.maximumPayloadBytes else {
            throw DraftAttachmentStagingFailureV1.invalidAttachment
        }
        if let scratchStore {
            let request = try ScratchDataLeaseRequestV1(
                leaseID: stageID,
                purpose: .capture,
                owner: .capture,
                ownerOperationID: mutationID.rawValue,
                requestedByteCount: UInt64(data.count),
                createdAt: now,
                expiresAt: now.addingTimeInterval(7_200)
            )
            let lease: ScratchDataLeaseV1
            do {
                lease = try await scratchStore.acquireScratchLease(request)
                let scratchURL = try await scratchStore.writeScratchData(
                    data,
                    named: "source-\(stageID.uuidString.lowercased())",
                    lease: lease
                )
                let bytes = try Data(contentsOf: scratchURL, options: .mappedIfSafe)
                try Task.checkCancellation()
                try await scratchStore.releaseScratchLease(lease, terminal: .completed)
                return ScratchCopy(bytes: bytes, leaseID: lease.request.leaseID)
            } catch let failure as ScratchDataLeaseStoreFailureV1 {
                throw Self.mapScratchFailure(failure)
            } catch is CancellationError {
                throw DraftAttachmentStagingFailureV1.cancelled
            } catch let failure as DraftAttachmentStagingFailureV1 {
                throw failure
            } catch {
                throw DraftAttachmentStagingFailureV1.protectedDataUnavailable
            }
        }

        // A test/in-process caller may omit the shared scratch actor.  Keep a
        // disposable file boundary nevertheless; it is removed before return.
        let temporary = fileManager.temporaryDirectory
            .appendingPathComponent("c36-scratch-\(stageID.uuidString.lowercased())")
        do {
            try data.write(to: temporary, options: [.atomic])
            let bytes = try Data(contentsOf: temporary, options: .mappedIfSafe)
            try fileManager.removeItem(at: temporary)
            return ScratchCopy(bytes: bytes, leaseID: stageID)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw DraftAttachmentStagingFailureV1.cleanupFailed
        }
    }

    static func mapScratchFailure(_ failure: ScratchDataLeaseStoreFailureV1)
        -> DraftAttachmentStagingFailureV1 {
        switch failure {
        case .protectedDataUnavailable: return .protectedDataUnavailable
        case .insufficientCapacity: return .insufficientStorage
        case .leaseExpired: return .cancelled
        case .invalidRoot, .invalidLease, .leaseCollision, .sizeLimitExceeded:
            return .invalidAttachment
        }
    }

    func persistManifest() throws {
        let expected = try manifest.canonicalBytes()
        try Self.writeManifest(manifest, to: rootURL.appendingPathComponent(Self.manifestName),
                               fileManager: fileManager, owner: rootOwner)
        try reloadManifest()
        guard try manifest.canonicalBytes() == expected else { throw DraftAttachmentStagingFailureV1.corruptManifest }
    }

    static func writeManifest(
        _ value: DraftAttachmentStagingManifestV1,
        to url: URL,
        fileManager: FileManager,
        owner: DraftStagingRootOwnerV1
    ) throws {
        try value.validate()
        let data = try value.canonicalBytes()
        try DraftStagingRootOwnerV1.replaceFile(data, at: url, directory: owner.directory([]))
        do {
            try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: url)
        } catch let failure as ProtectedFilePolicyError
            where failure == .protectedDataUnavailable {
            throw DraftAttachmentStagingFailureV1.protectedDataUnavailable
        } catch {
            throw DraftAttachmentStagingFailureV1.cleanupFailed
        }
        _ = fileManager
    }

    func replacing(_ entry: DraftAttachmentStagingEntryV1)
        throws -> DraftAttachmentStagingManifestV1 {
        var entries = manifest.entries.filter { $0.item.stageID != entry.item.stageID }
        entries.append(entry)
        return try DraftAttachmentStagingManifestV1(entries: entries)
    }

    func successor(
        _ prior: AttachmentStagingItemV1,
        state: AttachmentStagingStateV1,
        retryClass: DraftStageRetryClassV1? = nil,
        actualByteCount: Int64? = nil,
        contentDigest: ContentDigestV1? = nil,
        contentReference: ContentReferenceV1? = nil
    ) throws -> AttachmentStagingItemV1 {
        guard prior.revision < UInt64.max else {
            throw DraftAttachmentStagingFailureV1.staleStage
        }
        let nextMutation = try MutationIDV1(rawValue: Self.deterministicUUID(
            "stage-mutation\u{1f}\(prior.stageID.uuidString.lowercased())\u{1f}\(prior.revision + 1)\u{1f}\(state.rawValue)\u{1f}\(contentDigest?.hexadecimalValue ?? prior.contentDigest?.hexadecimalValue ?? "")"
        ))
        return try AttachmentStagingItemV1(
            stageID: prior.stageID,
            draftID: prior.draftID,
            workspaceID: prior.workspaceID,
            attachmentKind: prior.attachmentKind,
            scratchLeaseID: prior.scratchLeaseID,
            expectedByteCount: prior.expectedByteCount,
            actualByteCount: actualByteCount ?? prior.actualByteCount,
            contentDigest: contentDigest ?? prior.contentDigest,
            contentReference: contentReference ?? prior.contentReference,
            processingJobID: prior.processingJobID,
            retryClass: retryClass ?? prior.retryClass,
            state: state,
            protectionState: prior.protectionState,
            revision: prior.revision + 1,
            mutationID: nextMutation
        )
    }

    func verifiedBytes(for entry: DraftAttachmentStagingEntryV1) throws -> Data {
        try publicationKernel.verifiedBytes(for: entry)
    }

    func removeDirectory(_ url: URL) throws {
        try publicationKernel.removeDirectory(url)
    }

    static func defaultMediaType(for kind: DraftAttachmentKindV1) -> String {
        switch kind {
        case .photo: return "image/jpeg"
        case .audio: return "audio/mpeg"
        case .video: return "video/mp4"
        case .file: return "application/octet-stream"
        }
    }

    func sha256(_ data: Data) -> String {
        publicationKernel.sha256(data)
    }
}

enum C34SceneRestorationAttachmentStagingBoundaryV1 {
    static let createsStage = false
    static let promotesStage = false
    static let claimsStagingOwnership = false
    static func validate(anchor: DraftResumeAnchorV1) -> Bool { !createsStage && !promotesStage && !claimsStagingOwnership && C34DraftResumeNavigationBoundaryV1.validate(anchor: anchor) }
}

private extension DraftAttachmentStagingAdapterV1 {
    /// A synchronous operation on caller-owned state, never an independently
    /// retained manifest or writer. Initialization and the actor API use the
    /// same publication checks and filesystem implementation.
    struct RestorePublicationKernel {
        let fileManager: FileManager
        let rootURL: URL
        let workspaceScope: WorkspaceID?
        let clock: Clock
        let owner: DraftStagingRootOwnerV1

        func adopt(
            from sourceRootURL: URL,
            entries: [DraftAttachmentStagingEntryV1],
            workspaceID: WorkspaceID,
            sourceManifestSHA256: String,
            restoreID: UUID,
            manifest: inout DraftAttachmentStagingManifestV1
        ) throws -> DraftAttachmentRestorePublicationReceiptV1 {
            let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0,
                                   0, 0, 0, 0, 0, 0, 0, 0))
            guard sourceRootURL.isFileURL, restoreID != zero,
                  workspaceID.rawValue != zero,
                  sourceRootURL.standardizedFileURL != rootURL.standardizedFileURL else {
                throw DraftAttachmentStagingFailureV1.invalidRoot
            }
            let sourceManifest = try DraftAttachmentStagingManifestV1(entries: entries)
            try sourceManifest.validate()
            guard sourceManifest.manifestSHA256 == sourceManifestSHA256 else {
                throw DraftAttachmentStagingFailureV1.digestMismatch
            }
            guard entries.allSatisfy({ $0.item.workspaceID == workspaceID }) else {
                throw DraftAttachmentStagingFailureV1.wrongWorkspace
            }

            let ordered = entries.sorted {
                $0.item.stageID.uuidString.lowercased()
                    < $1.item.stageID.uuidString.lowercased()
            }
            var nextEntries = manifest.entries
            var adopted = [UUID]()
            var reused = [UUID]()
            var createdDirectories = [DraftStagingRootOwnerV1.Directory]()
            var manifestPublicationAttempted = false

            do {
                for entry in ordered {
                    let item = entry.item
                    let destination = rootURL.appendingPathComponent(
                        DraftAttachmentStagingAdapterV1.relativeStageDirectory(draftID: item.draftID, stageID: item.stageID))
                    guard !DraftStagingRootOwnerV1.pathExists(destination.appendingPathComponent("raw-publication.json")),
                          !DraftStagingRootOwnerV1.pathExists(sourceRootURL.appendingPathComponent(entry.relativeDataPath)
                            .deletingLastPathComponent().appendingPathComponent("raw-publication.json")) else {
                        throw DraftAttachmentStagingFailureV1.invalidTransition
                    }
                    guard item.state == .readyLocal || item.state == .committed,
                          item.actualByteCount != nil,
                          item.contentDigest != nil else {
                        throw DraftAttachmentStagingFailureV1.invalidTransition
                    }
                    try validateScope(
                        workspaceID: item.workspaceID,
                        draftID: item.draftID,
                        stageID: item.stageID
                    )
                    let sourceURL = try restoreSourceURL(
                        sourceRootURL: sourceRootURL,
                        entry: entry
                    )
                    let bytes = try verifiedRestoreBytes(bytesURL: sourceURL, item: item)

                    if let index = nextEntries.firstIndex(where: {
                        $0.item.stageID == item.stageID
                    }) {
                        let existing = nextEntries[index].item
                        guard existing.workspaceID == item.workspaceID,
                              existing.draftID == item.draftID,
                              existing.expectedByteCount == item.expectedByteCount,
                              existing.actualByteCount == item.actualByteCount,
                              existing.contentDigest == item.contentDigest else {
                            throw DraftAttachmentStagingFailureV1.staleStage
                        }
                        _ = try verifiedBytes(for: nextEntries[index])
                        reused.append(item.stageID)
                        continue
                    }

                    let destinationDirectory = rootURL.appendingPathComponent(
                        DraftAttachmentStagingAdapterV1.relativeStageDirectory(
                            draftID: item.draftID,
                            stageID: item.stageID
                        ),
                        isDirectory: true
                    )
                    guard !DraftStagingRootOwnerV1.pathExists(destinationDirectory) else {
                        throw DraftAttachmentStagingFailureV1.staleStage
                    }
                    let parts = DraftAttachmentStagingAdapterV1.relativeStageDirectory(
                        draftID: item.draftID, stageID: item.stageID).split(separator: "/").map(String.init)
                    let parent = try owner.directory([parts[0]], create: true)
                    try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: parent.url)
                    try parent.verifyNamed()
                    guard mkdirat(parent.descriptor, parts[1], mode_t(0o700)) == 0 else {
                        throw DraftAttachmentStagingFailureV1.staleStage
                    }
                    let created = try owner.directory(parts)
                    createdDirectories.append(created)
                    try ProtectedFilePolicyV1.applyAndVerify(
                        .stagingDirectory,
                        at: destinationDirectory
                    )
                    try created.verifyNamed()
                    // The source relative path can belong to the source draft in
                    // a clone/fork restore.  Always publish into the target's
                    // canonical adapter path; source layout is only an input.
                    let destinationRelativePath = DraftAttachmentStagingAdapterV1.relativeDataPath(
                        draftID: item.draftID,
                        stageID: item.stageID
                    )
                    let destinationURL = rootURL.appendingPathComponent(
                        destinationRelativePath
                    )
                    try DraftStagingRootOwnerV1.replaceFile(bytes, at: destinationURL, directory: created)
                    let adoptedEntry = try DraftAttachmentStagingEntryV1(
                        item: item,
                        relativeDataPath: destinationRelativePath,
                        mediaType: entry.mediaType,
                        updatedAt: clock()
                    )
                    guard try verifiedBytes(for: adoptedEntry) == bytes else {
                        throw DraftAttachmentStagingFailureV1.digestMismatch
                    }
                    nextEntries.append(adoptedEntry)
                    adopted.append(item.stageID)
                }

                let updated = try DraftAttachmentStagingManifestV1(entries: nextEntries)
                manifest = updated
                manifestPublicationAttempted = true
                try DraftAttachmentStagingAdapterV1.writeManifest(
                    manifest, to: rootURL.appendingPathComponent(DraftAttachmentStagingAdapterV1.manifestName),
                    fileManager: fileManager, owner: owner
                )
                manifest = try DraftStagingRootOwnerV1.ManifestSnapshot(owner: owner).manifest
                guard try manifest.canonicalBytes() == updated.canonicalBytes() else {
                    throw DraftAttachmentStagingFailureV1.corruptManifest
                }
                return try DraftAttachmentRestorePublicationReceiptV1(
                    restoreID: restoreID,
                    workspaceID: workspaceID,
                    sourceManifestSHA256: sourceManifestSHA256,
                    adoptedStageIDs: adopted.sorted(by: DraftAttachmentRestorePublicationReceiptV1.uuidLess),
                    reusedStageIDs: reused.sorted(by: DraftAttachmentRestorePublicationReceiptV1.uuidLess),
                    publishedAt: clock()
                )
            } catch let failure as DraftAttachmentStagingFailureV1 {
                for directory in (manifestPublicationAttempted ? [] : Array(createdDirectories.reversed())) {
                    try? removeDirectory(directory.url, expectedIdentity: directory.identity)
                }
                throw failure
            } catch let failure as ProtectedFilePolicyError
                where failure == .protectedDataUnavailable {
                for directory in (manifestPublicationAttempted ? [] : Array(createdDirectories.reversed())) {
                    try? removeDirectory(directory.url, expectedIdentity: directory.identity)
                }
                throw DraftAttachmentStagingFailureV1.protectedDataUnavailable
            } catch {
                for directory in (manifestPublicationAttempted ? [] : Array(createdDirectories.reversed())) {
                    try? removeDirectory(directory.url, expectedIdentity: directory.identity)
                }
                throw DraftAttachmentStagingFailureV1.cleanupFailed
            }
        }

        func validateScope(workspaceID: WorkspaceID, draftID: UUID, stageID: UUID) throws {
            guard workspaceID.rawValue != DraftAttachmentStagingAdapterV1.zero,
                  draftID != DraftAttachmentStagingAdapterV1.zero, stageID != DraftAttachmentStagingAdapterV1.zero else {
                throw DraftAttachmentStagingFailureV1.invalidAttachment
            }
            if let workspaceScope, workspaceScope != workspaceID {
                throw DraftAttachmentStagingFailureV1.wrongWorkspace
            }
        }

        func verifiedBytes(for entry: DraftAttachmentStagingEntryV1) throws -> Data {
            let target = rootURL.appendingPathComponent(entry.relativeDataPath).standardizedFileURL
            guard target.path.hasPrefix(rootURL.path + "/") else {
                throw DraftAttachmentStagingFailureV1.unsafePath
            }
            do {
                let components = entry.relativeDataPath.split(separator: "/").map(String.init)
                guard let name = components.last else { throw DraftAttachmentStagingFailureV1.unsafePath }
                let directory = try owner.directory(Array(components.dropLast()))
                guard !(try directory.exists("raw-publication.json")) else {
                    throw DraftAttachmentStagingFailureV1.invalidTransition
                }
                let fd = try directory.openFile(name)
                defer { close(fd) }
                let facts = try DraftStagingRootOwnerV1.regular(fd)
                guard facts.st_size > 0, facts.st_size <= Int64(FieldDraftLimitsV1.maximumPayloadBytes),
                      facts.st_size == entry.item.actualByteCount else {
                    throw DraftAttachmentStagingFailureV1.byteLengthMismatch
                }
                try ProtectedFilePolicyV1.verify(.stagingFile, at: target)
                let data = try DraftStagingRootOwnerV1.read(fd, count: Int(facts.st_size))
                try DraftStagingRootOwnerV1.unchanged(fd, facts)
                try directory.verifyNamed()
                try directory.verifyFile(fd, name: name)
                guard Int64(data.count) == entry.item.actualByteCount,
                      let digest = entry.item.contentDigest,
                      sha256(data) == digest.hexadecimalValue else {
                    throw DraftAttachmentStagingFailureV1.digestMismatch
                }
                return data
            } catch let failure as DraftAttachmentStagingFailureV1 {
                throw failure
            } catch let failure as ProtectedFilePolicyError
                where failure == .protectedDataUnavailable {
                throw DraftAttachmentStagingFailureV1.protectedDataUnavailable
            } catch {
                throw DraftAttachmentStagingFailureV1.stageNotFound
            }
        }

        func restoreSourceURL(
            sourceRootURL: URL,
            entry: DraftAttachmentStagingEntryV1
        ) throws -> URL {
            let root = sourceRootURL.standardizedFileURL
            let sourceOwner = try DraftStagingRootOwnerV1(rootURL: root)
            let item = entry.item
            let candidates = [
                entry.relativeDataPath,
                "\(item.draftID.uuidString.lowercased())/\(item.stageID.uuidString.lowercased()).bin",
                "draft-\(item.draftID.uuidString.lowercased())/stage-\(item.stageID.uuidString.lowercased()).bin",
            ]
            for relativePath in candidates {
                let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
                guard candidate.path.hasPrefix(root.path + "/") else {
                    throw DraftAttachmentStagingFailureV1.unsafePath
                }
                guard fileManager.fileExists(atPath: candidate.path) else { continue }
                let parts = relativePath.split(separator: "/").map(String.init)
                let parent = try sourceOwner.directory(Array(parts.dropLast()))
                guard !(try parent.exists("raw-publication.json")), let name = parts.last else {
                    throw DraftAttachmentStagingFailureV1.invalidTransition
                }
                let fd = try parent.openFile(name)
                close(fd)
                return candidate
            }
            throw DraftAttachmentStagingFailureV1.stageNotFound
        }

        func verifiedRestoreBytes(
            bytesURL: URL,
            item: AttachmentStagingItemV1
        ) throws -> Data {
            let data: Data
            do {
                let fd = open(bytesURL.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
                guard fd >= 0 else { throw DraftAttachmentStagingFailureV1.stageNotFound }
                defer { close(fd) }
                let facts = try DraftStagingRootOwnerV1.regular(fd)
                guard facts.st_size > 0, facts.st_size <= Int64(FieldDraftLimitsV1.maximumPayloadBytes) else {
                    throw DraftAttachmentStagingFailureV1.invalidAttachment
                }
                data = try DraftStagingRootOwnerV1.read(fd, count: Int(facts.st_size))
                try DraftStagingRootOwnerV1.unchanged(fd, facts)
            } catch {
                throw DraftAttachmentStagingFailureV1.stageNotFound
            }
            guard let expectedLength = item.actualByteCount,
                  let expectedDigest = item.contentDigest,
                  Int64(data.count) == expectedLength,
                  sha256(data) == expectedDigest.hexadecimalValue else {
                throw DraftAttachmentStagingFailureV1.digestMismatch
            }
            return data
        }

        func removeDirectory(_ url: URL, expectedIdentity: stat? = nil) throws {
            guard url.standardizedFileURL.path.hasPrefix(rootURL.path + "/") else {
                throw DraftAttachmentStagingFailureV1.unsafePath
            }
            guard fileManager.fileExists(atPath: url.path) else { return }
            let relative = String(url.standardizedFileURL.path.dropFirst(rootURL.path.count + 1))
            let components = relative.split(separator: "/").map(String.init)
            guard let name = components.last else { throw DraftAttachmentStagingFailureV1.unsafePath }
            let parent = try owner.directory(Array(components.dropLast()))
            let directory = try owner.directory(components)
            if let expectedIdentity {
                guard directory.identity.st_dev == expectedIdentity.st_dev,
                      directory.identity.st_ino == expectedIdentity.st_ino else {
                    throw DraftAttachmentStagingFailureV1.staleStage
                }
            }
            guard !(try directory.exists("raw-publication.json")) else {
                throw DraftAttachmentStagingFailureV1.invalidTransition
            }
            let leaves = try fileManager.contentsOfDirectory(atPath: url.path)
            guard Set(leaves).isSubset(of: [DraftAttachmentStagingAdapterV1.payloadName]) else {
                throw DraftAttachmentStagingFailureV1.cleanupFailed
            }
            try directory.verifyNamed()
            if try directory.exists(DraftAttachmentStagingAdapterV1.payloadName) {
                let fd = try directory.openFile(DraftAttachmentStagingAdapterV1.payloadName)
                defer { close(fd) }
                try directory.verifyFile(fd, name: DraftAttachmentStagingAdapterV1.payloadName)
                guard unlinkat(directory.descriptor, DraftAttachmentStagingAdapterV1.payloadName, 0) == 0 else {
                    throw DraftAttachmentStagingFailureV1.cleanupFailed
                }
            }
            try directory.verifyNamed()
            guard unlinkat(parent.descriptor, name, AT_REMOVEDIR) == 0, fsync(parent.descriptor) == 0 else {
                throw DraftAttachmentStagingFailureV1.cleanupFailed
            }
        }

        func sha256(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }
}

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
        func verifyFile(_ fd: Int32, name: String) throws {
            let opened = try openFile(name)
            defer { close(opened) }
            let a = try DraftStagingRootOwnerV1.regular(fd), b = try DraftStagingRootOwnerV1.regular(opened)
            guard a.st_dev == b.st_dev, a.st_ino == b.st_ino else {
                throw DraftAttachmentStagingFailureV1.staleStage
            }
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
            try DraftStagingRootOwnerV1.unchanged(descriptor, facts)
            let current = openat(owner.descriptor, DraftAttachmentStagingAdapterV1.manifestName,
                                 O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            guard current >= 0 else { throw DraftAttachmentStagingFailureV1.corruptManifest }
            defer { close(current) }
            let value = try DraftStagingRootOwnerV1.regular(current)
            guard value.st_dev == facts.st_dev, value.st_ino == facts.st_ino else {
                throw DraftAttachmentStagingFailureV1.staleStage
            }
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
        let now = try regular(fd)
        guard now.st_dev == prior.st_dev, now.st_ino == prior.st_ino, now.st_size == prior.st_size,
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
        try directory.verifyFile(payloadDescriptor, name: DraftAttachmentStagingAdapterV1.payloadName)
        try directory.verifyFile(witnessDescriptor, name: Self.witnessName)
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
            guard readBack == self.candidateManifest else {
                throw DraftAttachmentStagingFailureV1.corruptManifest
            }
            let visible = try self.owner.directory(self.parent.components + [self.finalName])
            guard visible.identity.st_dev == self.directory.identity.st_dev,
                  visible.identity.st_ino == self.directory.identity.st_ino else {
                throw DraftAttachmentStagingFailureV1.staleStage
            }
            try visible.verifyFile(self.payloadDescriptor, name: DraftAttachmentStagingAdapterV1.payloadName)
            try visible.verifyFile(self.witnessDescriptor, name: Self.witnessName)
            published = true
        }
        guard published else { throw DraftAttachmentStagingFailureV1.invalidTransition }
        return result
    }

    private static let witnessName = "raw-publication.json"

    fileprivate static func prepare(sourceURL: URL, payload: CheckRunnerPhotoDraftPayloadV1,
        publishedRawReady: CheckRunnerPhotoRawReadyV1?, applicationSupportURL: URL,
        adapterIdentity: ObjectIdentifier, owner: DraftStagingRootOwnerV1) throws
        -> DraftPreparedRawPhotoPublicationV1 {
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
        let parent = try owner.directory([path[0]], create: publishedRawReady == nil)
        try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: parent.url)
        try parent.verifyNamed()
        let existing = try parent.exists(path[1])
        if publishedRawReady != nil, !existing {
            throw DraftAttachmentStagingFailureV1.stageNotFound
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

    private static func hash(_ fd: Int32, count: Int) throws -> ContentDigestV1 {
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

    private static func inspect(_ fd: Int32, count: Int) throws -> MediaSourceFactsV1 {
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
    @discardableResult
    func stageRawPhoto(sourceURL: URL, authority: CheckRunnerPhotoRawPublicationAuthorityV1)
        async throws -> FieldDraftCommittedEvidenceV1 {
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
        guard manifest == nextManifest else { throw DraftAttachmentStagingFailureV1.corruptManifest }
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
        try Self.writeManifest(manifest, to: rootURL.appendingPathComponent(Self.manifestName),
                               fileManager: fileManager, owner: rootOwner)
        let expected = manifest
        try reloadManifest()
        guard manifest == expected else { throw DraftAttachmentStagingFailureV1.corruptManifest }
    }

    static func writeManifest(
        _ value: DraftAttachmentStagingManifestV1,
        to url: URL,
        fileManager: FileManager,
        owner: DraftStagingRootOwnerV1
    ) throws {
        try value.validate()
        var encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(value)
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
                guard manifest == updated else { throw DraftAttachmentStagingFailureV1.corruptManifest }
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

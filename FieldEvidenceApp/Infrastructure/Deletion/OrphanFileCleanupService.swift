import Darwin
import Foundation

struct OrphanFileCleanupSummary: Equatable, Sendable {
    let inspectedFileCount: Int
    let removedFileCount: Int
    let removedByteCount: Int64
    let removedDirectoryCount: Int
}

enum OrphanFileCleanupServiceError: Error, Equatable, Sendable {
    case invalidGeneration
    case invalidReference
    case inventoryLimitExceeded
    case byteLimitExceeded
    case invalidOwnedLayout
    case identityChanged
    case cleanupFailed
}

final class OrphanFileCleanupReplacementInjection {
    private let lock = NSLock()
    private var operation: ((URL) throws -> Void)?

    init(runOnce operation: @escaping (URL) throws -> Void) {
        self.operation = operation
    }

    fileprivate func runIfPresent(at url: URL) throws {
        lock.lock()
        let current = operation
        operation = nil
        lock.unlock()
        try current?(url)
    }
}

/// Removes only unreferenced files from the three durable, row-owned content
/// roots. This type deliberately has no database or deletion-ledger handle:
/// callers provide a complete referenced-path projection and tombstones remain
/// outside this file-only authority boundary.
final class OrphanFileCleanupService {
    static let maximumEntriesPerRoot = 100_000
    static let maximumInspectedBytes: Int64 = 16 * 1_024 * 1_024 * 1_024

    private let generationRootURL: URL
    private let generationID: UUID
    private let rootIdentity: Identity
    private let fileManager: FileManager
    private let replacementInjection: OrphanFileCleanupReplacementInjection?

    init(
        generationRootURL: URL,
        fileManager: FileManager = .default,
        replacementInjection: OrphanFileCleanupReplacementInjection? = nil
    ) throws {
        let root = generationRootURL.standardizedFileURL
        let generations = root.deletingLastPathComponent()
        let data = generations.deletingLastPathComponent()
        guard root.isFileURL,
              generations.lastPathComponent == "generations",
              data.lastPathComponent == "FieldEvidenceData",
              let generationID = UUID(uuidString: root.lastPathComponent),
              generationID.uuidString.lowercased() == root.lastPathComponent else {
            throw OrphanFileCleanupServiceError.invalidGeneration
        }
        let descriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw OrphanFileCleanupServiceError.invalidGeneration
        }
        defer { Darwin.close(descriptor) }
        self.generationRootURL = root
        self.generationID = generationID
        self.fileManager = fileManager
        self.replacementInjection = replacementInjection
        rootIdentity = try Self.identity(descriptor, directory: true)
    }

    func reconcile(
        referencedRelativePaths: [String]
    ) throws -> OrphanFileCleanupSummary {
        guard Set(referencedRelativePaths).count == referencedRelativePaths.count,
              referencedRelativePaths.allSatisfy(
                DeletionIntentEncoderV1.validRelativePath
              ),
              validEvidencePairs(referencedRelativePaths) else {
            throw OrphanFileCleanupServiceError.invalidReference
        }
        try validateKernelOrphanMappings()
        let summary = try reconcile(references: Set(referencedRelativePaths))
        try purgeDerivedSearchProjection()
        return summary
    }

    /// The local search projection is derived and has no canonical row-owned
    /// path. Orphan maintenance may therefore drop it wholesale for rebuild.
    func purgeDerivedSearchProjection() throws {
        do {
            try KernelDeletionEraseRegistryV4.validateSearchLifecycle()
            let applicationSupportURL = generationRootURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            try LocalSearchIndexStoreV1.synchronouslyEraseAll(
                applicationSupportURL: applicationSupportURL,
                fileManager: fileManager
            )
        } catch {
            throw OrphanFileCleanupServiceError.cleanupFailed
        }
    }

    /// Package-aware callers must prove the file projection belongs to the
    /// same workspace/generation before any pinned-FD cleanup is allowed. The
    /// overload is main-actor isolated because the shared query dependency is
    /// deliberately main-actor bound; the historical file-only entry point
    /// above remains available for synthetic XCTest stores.
    @MainActor
    func reconcile(
        referencedRelativePaths: [String],
        packageLifecycleDependencies dependencies: WorkspacePackageLifecycleDependenciesV1
    ) throws -> OrphanFileCleanupSummary {
        guard Set(referencedRelativePaths).count == referencedRelativePaths.count,
              referencedRelativePaths.allSatisfy(
                  DeletionIntentEncoderV1.validRelativePath
              ),
              validEvidencePairs(referencedRelativePaths) else {
            throw OrphanFileCleanupServiceError.invalidReference
        }
        try validateKernelOrphanMappings()
        let identities = try evidenceIdentities(in: referencedRelativePaths)
        try validatePackageLifecycleScope(
            dependencies,
            identities: identities
        )
        let summary = try reconcile(references: Set(referencedRelativePaths))
        try purgeDerivedSearchProjection()
        return summary
    }

    private func reconcile(
        references: Set<String>
    ) throws -> OrphanFileCleanupSummary {
        let sortedReferences = references.sorted()
        guard sortedReferences.allSatisfy(
                DeletionIntentEncoderV1.validRelativePath
              ),
              validEvidencePairs(sortedReferences) else {
            throw OrphanFileCleanupServiceError.invalidReference
        }

        let root = try openPinnedRoot()
        defer { Darwin.close(root) }
        var inventory = Inventory()
        try inventoryEvidence(
            root: root,
            references: references,
            inventory: &inventory
        )
        try inventoryFlatRoot(
            root: root,
            rootName: "snapshots",
            pathExtension: "json",
            references: references,
            inventory: &inventory
        )
        try inventoryFlatRoot(
            root: root,
            rootName: "pdfs",
            pathExtension: "pdf",
            references: references,
            inventory: &inventory
        )

        // Retain the injected FileManager as part of the initializer's
        // authority surface, but perform mutation only through pinned FDs.
        _ = fileManager
        var removedFiles = 0
        var removedBytes: Int64 = 0
        var removedDirectories = 0
        for candidate in inventory.candidates {
            try remove(candidate)
            removedFiles += candidate.leaves.count
            removedBytes += candidate.leaves.reduce(0) { $0 + $1.byteCount }
            if candidate.directoryIdentity != nil { removedDirectories += 1 }
        }
        return OrphanFileCleanupSummary(
            inspectedFileCount: inventory.inspectedFileCount,
            removedFileCount: removedFiles,
            removedByteCount: removedBytes,
            removedDirectoryCount: removedDirectories
        )
    }
}

private extension OrphanFileCleanupService {
    func validateKernelOrphanMappings() throws {
        do {
            let ownedContent = try KernelDeletionEraseRegistryV4.registration(
                for: .contentReference
            )
            let evidence = try KernelDeletionEraseRegistryV4.registration(
                for: .evidenceFile
            )
            let report = try KernelDeletionEraseRegistryV4.registration(
                for: .report
            )
            let completedSnapshot = try KernelDeletionEraseRegistryV4.registration(
                for: .completedActivitySnapshot
            )
            guard ownedContent.orphanCleanup == .removeOwnedBytesWhenUnreferenced,
                  evidence.orphanCleanup == .removeOwnedBytesWhenUnreferenced,
                  report.orphanCleanup == .preserveCanonicalRecord,
                  completedSnapshot.orphanCleanup == .removeDerivedProjection,
                  !ownedContent.clearsTombstonesOnDelete,
                  !evidence.clearsTombstonesOnDelete,
                  !report.clearsTombstonesOnDelete,
                  !completedSnapshot.clearsTombstonesOnDelete else {
                throw OrphanFileCleanupServiceError.invalidOwnedLayout
            }
        } catch let error as OrphanFileCleanupServiceError {
            throw error
        } catch {
            throw OrphanFileCleanupServiceError.invalidOwnedLayout
        }
    }

    @MainActor
    func evidenceIdentities(
        in paths: [String]
    ) throws -> [WorkspaceEntityIdentityV1] {
        let values = paths.compactMap { path -> UUID? in
            let components = path.split(separator: "/").map(String.init)
            guard components.count == 3,
                  components[0] == "evidence",
                  components[2] == "original.jpg"
                      || components[2] == "thumbnail.jpg",
                  let id = UUID(uuidString: components[1]),
                  id.uuidString.lowercased() == components[1] else {
                return nil
            }
            return id
        }
        guard Set(values).count * 2 == paths.filter({ $0.hasPrefix("evidence/") }).count
                || paths.filter({ $0.hasPrefix("evidence/") }).isEmpty else {
            throw OrphanFileCleanupServiceError.invalidReference
        }
        return try Set(values).sorted { $0.uuidString < $1.uuidString }.map {
            try WorkspaceEntityIdentityV1(kind: .evidenceFile, id: $0)
        }
    }

    @MainActor
    func validatePackageLifecycleScope(
        _ dependencies: WorkspacePackageLifecycleDependenciesV1,
        identities: [WorkspaceEntityIdentityV1]
    ) throws {
        guard dependencies.generationID == generationID,
              dependencies.generationRootURL.standardizedFileURL == generationRootURL,
              dependencies.generationRootURL.isFileURL else {
            throw OrphanFileCleanupServiceError.invalidGeneration
        }
        do {
            let request = try WorkspacePackageLifecycleQueryRequestV1(
                workspaceID: dependencies.workspaceID,
                generationID: dependencies.generationID,
                operation: .delete,
                identities: identities
            )
            let result = try dependencies.queryClient.query(request)
            guard result.workspaceID == dependencies.workspaceID,
                  result.generationID == generationID,
                  result.operation == .delete,
                  Set(result.existingIdentities) == Set(request.identities),
                  try dependencies.queryClient.currentRevision() == result.revision else {
                throw OrphanFileCleanupServiceError.identityChanged
            }
        } catch let error as OrphanFileCleanupServiceError {
            throw error
        } catch {
            throw OrphanFileCleanupServiceError.identityChanged
        }
    }

    struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    struct Leaf {
        let name: String
        let identity: Identity
        let byteCount: Int64
    }

    struct Candidate {
        let rootName: String
        let rootIdentity: Identity
        let directoryName: String?
        let directoryIdentity: Identity?
        let leaves: [Leaf]
    }

    struct Inventory {
        var candidates = [Candidate]()
        var inspectedFileCount = 0
        var inspectedBytes: Int64 = 0

        mutating func inspect(byteCount: Int64) throws {
            guard byteCount >= 0,
                  inspectedFileCount < OrphanFileCleanupService.maximumEntriesPerRoot * 3,
                  inspectedBytes <= OrphanFileCleanupService.maximumInspectedBytes - byteCount else {
                if byteCount < 0 {
                    throw OrphanFileCleanupServiceError.invalidOwnedLayout
                }
                if inspectedFileCount >= OrphanFileCleanupService.maximumEntriesPerRoot * 3 {
                    throw OrphanFileCleanupServiceError.inventoryLimitExceeded
                }
                throw OrphanFileCleanupServiceError.byteLimitExceeded
            }
            inspectedFileCount += 1
            inspectedBytes += byteCount
        }
    }

    func validEvidencePairs(_ paths: [String]) -> Bool {
        var names = [String: Set<String>]()
        for path in paths where path.hasPrefix("evidence/") {
            let components = path.split(separator: "/").map(String.init)
            guard components.count == 3 else { return false }
            names[components[1], default: []].insert(components[2])
        }
        return names.values.allSatisfy {
            $0 == Set(["original.jpg", "thumbnail.jpg"])
        }
    }

    func inventoryEvidence(
        root: Int32,
        references: Set<String>,
        inventory: inout Inventory
    ) throws {
        guard let evidence = try openRootIfPresent(parent: root, name: "evidence") else {
            return
        }
        defer { Darwin.close(evidence.descriptor) }
        let bundleNames = try boundedNames(in: evidence.descriptor)
        for bundleName in bundleNames {
            guard canonicalUUID(bundleName) else {
                throw OrphanFileCleanupServiceError.invalidOwnedLayout
            }
            let bundle = Darwin.openat(
                evidence.descriptor,
                bundleName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard bundle >= 0 else {
                throw OrphanFileCleanupServiceError.invalidOwnedLayout
            }
            do {
                let bundleIdentity = try Self.identity(bundle, directory: true)
                let names = try boundedNames(in: bundle)
                guard Set(names).isSubset(of: Set(["original.jpg", "thumbnail.jpg"])) else {
                    throw OrphanFileCleanupServiceError.invalidOwnedLayout
                }
                var leaves = [Leaf]()
                for name in names {
                    let leaf = try inspectLeaf(parent: bundle, name: name)
                    try inventory.inspect(byteCount: leaf.byteCount)
                    leaves.append(leaf)
                }
                let prefix = "evidence/\(bundleName)/"
                let referenced = references.contains(prefix + "original.jpg")
                    || references.contains(prefix + "thumbnail.jpg")
                if !referenced {
                    inventory.candidates.append(Candidate(
                        rootName: "evidence",
                        rootIdentity: evidence.identity,
                        directoryName: bundleName,
                        directoryIdentity: bundleIdentity,
                        leaves: leaves.sorted { $0.name < $1.name }
                    ))
                }
                Darwin.close(bundle)
            } catch {
                Darwin.close(bundle)
                throw error
            }
        }
    }

    func inventoryFlatRoot(
        root: Int32,
        rootName: String,
        pathExtension: String,
        references: Set<String>,
        inventory: inout Inventory
    ) throws {
        guard let ownedRoot = try openRootIfPresent(parent: root, name: rootName) else {
            return
        }
        defer { Darwin.close(ownedRoot.descriptor) }
        for name in try boundedNames(in: ownedRoot.descriptor) {
            guard canonicalUUIDFilename(name, pathExtension: pathExtension) else {
                throw OrphanFileCleanupServiceError.invalidOwnedLayout
            }
            let leaf = try inspectLeaf(parent: ownedRoot.descriptor, name: name)
            try inventory.inspect(byteCount: leaf.byteCount)
            if !references.contains("\(rootName)/\(name)") {
                inventory.candidates.append(Candidate(
                    rootName: rootName,
                    rootIdentity: ownedRoot.identity,
                    directoryName: nil,
                    directoryIdentity: nil,
                    leaves: [leaf]
                ))
            }
        }
    }

    func remove(_ candidate: Candidate) throws {
        let root = try openPinnedRoot()
        defer { Darwin.close(root) }
        guard let ownedRoot = try openRootIfPresent(
            parent: root,
            name: candidate.rootName
        ) else {
            throw OrphanFileCleanupServiceError.identityChanged
        }
        guard ownedRoot.identity == candidate.rootIdentity else {
            Darwin.close(ownedRoot.descriptor)
            throw OrphanFileCleanupServiceError.identityChanged
        }
        defer { Darwin.close(ownedRoot.descriptor) }

        if let directoryName = candidate.directoryName,
           let expectedDirectory = candidate.directoryIdentity {
            let directory = Darwin.openat(
                ownedRoot.descriptor,
                directoryName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard directory >= 0,
                  try Self.identity(directory, directory: true) == expectedDirectory else {
                if directory >= 0 { Darwin.close(directory) }
                throw OrphanFileCleanupServiceError.identityChanged
            }
            defer { Darwin.close(directory) }
            for leaf in candidate.leaves {
                try removeLeaf(
                    parent: directory,
                    expectedParent: expectedDirectory,
                    leaf: leaf,
                    relativePath: "\(candidate.rootName)/\(directoryName)/\(leaf.name)"
                )
            }
            let relativeDirectory = "\(candidate.rootName)/\(directoryName)"
            try replacementInjection?.runIfPresent(
                at: generationRootURL.appendingPathComponent(
                    relativeDirectory,
                    isDirectory: true
                )
            )
            var namedDirectory = stat()
            guard try boundedNames(in: directory).isEmpty,
                  Darwin.fstatat(
                    ownedRoot.descriptor,
                    directoryName,
                    &namedDirectory,
                    AT_SYMLINK_NOFOLLOW
                  ) == 0,
                  (namedDirectory.st_mode & S_IFMT) == S_IFDIR,
                  Identity(
                    device: namedDirectory.st_dev,
                    inode: namedDirectory.st_ino
                  ) == expectedDirectory,
                  Darwin.unlinkat(ownedRoot.descriptor, directoryName, AT_REMOVEDIR) == 0,
                  Self.entryIsAbsent(parent: ownedRoot.descriptor, name: directoryName),
                  try Self.identity(ownedRoot.descriptor, directory: true)
                    == candidate.rootIdentity,
                  Darwin.fsync(ownedRoot.descriptor) == 0 else {
                throw OrphanFileCleanupServiceError.identityChanged
            }
        } else {
            guard candidate.leaves.count == 1, let leaf = candidate.leaves.first else {
                throw OrphanFileCleanupServiceError.invalidOwnedLayout
            }
            try removeLeaf(
                parent: ownedRoot.descriptor,
                expectedParent: candidate.rootIdentity,
                leaf: leaf,
                relativePath: "\(candidate.rootName)/\(leaf.name)"
            )
        }
    }

    func removeLeaf(
        parent: Int32,
        expectedParent: Identity,
        leaf: Leaf,
        relativePath: String
    ) throws {
        let descriptor = Darwin.openat(parent, leaf.name, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw OrphanFileCleanupServiceError.identityChanged
        }
        defer { Darwin.close(descriptor) }
        var info = stat()
        try replacementInjection?.runIfPresent(
            at: generationRootURL.appendingPathComponent(relativePath)
        )
        var named = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              try Self.identity(parent, directory: true) == expectedParent,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1,
              Identity(device: info.st_dev, inode: info.st_ino) == leaf.identity,
              Int64(info.st_size) == leaf.byteCount,
              Darwin.fstatat(parent, leaf.name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              (named.st_mode & S_IFMT) == S_IFREG,
              named.st_nlink == 1,
              Identity(device: named.st_dev, inode: named.st_ino) == leaf.identity,
              Int64(named.st_size) == leaf.byteCount,
              Darwin.unlinkat(parent, leaf.name, 0) == 0,
              Self.entryIsAbsent(parent: parent, name: leaf.name),
              try Self.identity(parent, directory: true) == expectedParent,
              Darwin.fsync(parent) == 0 else {
            throw OrphanFileCleanupServiceError.identityChanged
        }
    }

    func inspectLeaf(parent: Int32, name: String) throws -> Leaf {
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw OrphanFileCleanupServiceError.invalidOwnedLayout
        }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1,
              info.st_size >= 0 else {
            throw OrphanFileCleanupServiceError.invalidOwnedLayout
        }
        return Leaf(
            name: name,
            identity: Identity(device: info.st_dev, inode: info.st_ino),
            byteCount: Int64(info.st_size)
        )
    }

    func openPinnedRoot() throws -> Int32 {
        let descriptor = Darwin.open(
            generationRootURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0,
              try Self.identity(descriptor, directory: true) == rootIdentity,
              generationRootURL.lastPathComponent == generationID.uuidString.lowercased() else {
            if descriptor >= 0 { Darwin.close(descriptor) }
            throw OrphanFileCleanupServiceError.invalidGeneration
        }
        return descriptor
    }

    func openRootIfPresent(
        parent: Int32,
        name: String
    ) throws -> (descriptor: Int32, identity: Identity)? {
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        if descriptor < 0, errno == ENOENT { return nil }
        guard descriptor >= 0 else {
            throw OrphanFileCleanupServiceError.invalidOwnedLayout
        }
        do {
            return (descriptor, try Self.identity(descriptor, directory: true))
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    func boundedNames(in descriptor: Int32) throws -> [String] {
        let duplicate = Darwin.dup(descriptor)
        guard duplicate >= 0, let directory = Darwin.fdopendir(duplicate) else {
            if duplicate >= 0 { Darwin.close(duplicate) }
            throw OrphanFileCleanupServiceError.invalidOwnedLayout
        }
        defer { Darwin.closedir(directory) }
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
            if name != "." && name != ".." {
                guard result.count < Self.maximumEntriesPerRoot else {
                    throw OrphanFileCleanupServiceError.inventoryLimitExceeded
                }
                result.append(name)
            }
            errno = 0
        }
        guard errno == 0 else {
            throw OrphanFileCleanupServiceError.invalidOwnedLayout
        }
        return result.sorted()
    }

    func canonicalUUIDFilename(_ filename: String, pathExtension: String) -> Bool {
        let suffix = ".\(pathExtension)"
        guard filename.hasSuffix(suffix) else { return false }
        return canonicalUUID(String(filename.dropLast(suffix.count)))
    }

    func canonicalUUID(_ value: String) -> Bool {
        guard let identifier = UUID(uuidString: value) else { return false }
        return identifier.uuidString.lowercased() == value
    }

    static func identity(_ descriptor: Int32, directory: Bool) throws -> Identity {
        var info = stat()
        let expected = directory ? S_IFDIR : S_IFREG
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == expected else {
            throw OrphanFileCleanupServiceError.invalidOwnedLayout
        }
        return Identity(device: info.st_dev, inode: info.st_ino)
    }

    static func entryIsAbsent(parent: Int32, name: String) -> Bool {
        var info = stat()
        guard Darwin.fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) != 0 else {
            return false
        }
        return errno == ENOENT
    }
}

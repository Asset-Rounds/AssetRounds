import CryptoKit
import Darwin
import Foundation
import SwiftData

enum GuidedSurveyRenderServiceBoundaryV1 {
    static func admit(_ snapshot: ReportSnapshotV1) throws {
        try snapshot.surveyPublication?.validate()
    }
    static let mutatesSurveyPublication = false
}

enum ReportRenderServiceError: Error, Equatable {
    case invalidGeneration
    case reportNotFound
    case reportNotPending
    case contextHasChanges
    case invalidStorageAuthority
    case writeFailed
    case bytesMismatch
    case saveFailed
    case cleanupFailed
    case injectedFailure
    case failedStateSaveFailed
}

enum ReportRenderAccessibleDocumentBoundaryV1{
    static func bind(bytes:Data,mediaType:String,rendererID:String,rendererVersion:String)throws->AccessibleDocumentRenderOutputV1{try .init(bytes:bytes,mediaType:mediaType,rendererID:rendererID,rendererVersion:rendererVersion)}
    static let secondRendererIntroduced=false
}

/// Uses no-follow directory descriptors and non-recursive `unlinkat` for
/// report-owned PDF descendants. Ancestor replacement cannot redirect a read
/// or deletion outside the opened generation tree.
enum ReportPDFAnchoredFile {
    enum Failure: Error {
        case invalidAuthority
        case cleanupFailed
    }

    struct RootIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    static func rootIdentity(at rootURL: URL) throws -> RootIdentity {
        let descriptor = try openGenerationRootDescriptor(rootURL)
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR else {
            throw Failure.invalidAuthority
        }
        return RootIdentity(device: info.st_dev, inode: info.st_ino)
    }

    static func readRegularFile(
        at url: URL,
        within rootURL: URL,
        rootIdentity: RootIdentity
    ) throws -> Data {
        try withParentDescriptor(
            of: url,
            within: rootURL,
            rootIdentity: rootIdentity
        ) { parent, leaf in
            let descriptor = Darwin.openat(parent, leaf, O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else { throw Failure.invalidAuthority }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            let expectedParent = try directoryIdentity(parent)
            var info = stat()
            guard Darwin.fstat(descriptor, &info) == 0,
                  (info.st_mode & S_IFMT) == S_IFREG,
                  info.st_nlink == 1 else {
                try? handle.close()
                throw Failure.invalidAuthority
            }
            let expected = RootIdentity(device: info.st_dev, inode: info.st_ino)
            try ProtectedFilePolicyV1.verify(
                inferredRegularFileKind(for: url),
                at: url
            )
            guard try directoryIdentity(parent) == expectedParent,
                  try regularFileIdentity(parent: parent, name: leaf) == expected else {
                try? handle.close()
                throw Failure.invalidAuthority
            }
            do {
                let data = try handle.readToEnd() ?? Data()
                var after = stat()
                guard Darwin.fstat(descriptor, &after) == 0,
                      (after.st_mode & S_IFMT) == S_IFREG,
                      after.st_nlink == 1,
                      after.st_dev == info.st_dev,
                      after.st_ino == info.st_ino,
                      try directoryIdentity(parent) == expectedParent,
                      try regularFileIdentity(parent: parent, name: leaf) == expected,
                      after.st_size == info.st_size,
                      data.count == Int(after.st_size) else {
                    throw Failure.invalidAuthority
                }
                return data
            } catch {
                throw Failure.invalidAuthority
            }
        }
    }

    static func removeRegularFile(
        at url: URL,
        quarantineAt quarantineURL: URL,
        within rootURL: URL,
        rootIdentity: RootIdentity
    ) throws {
        try withParentDescriptor(
            of: url,
            within: rootURL,
            rootIdentity: rootIdentity
        ) { parent, leaf in
            let descriptor = Darwin.openat(parent, leaf, O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else { throw Failure.invalidAuthority }
            defer { Darwin.close(descriptor) }
            let expectedParent = try directoryIdentity(parent)
            let identity = try regularFileIdentity(descriptor)
            try ProtectedFilePolicyV1.verify(
                inferredRegularFileKind(for: url),
                at: url
            )
            guard try directoryIdentity(parent) == expectedParent,
                  try regularFileIdentity(parent: parent, name: leaf) == identity else {
                throw Failure.invalidAuthority
            }
            try withParentDescriptor(
                of: quarantineURL,
                within: rootURL,
                rootIdentity: rootIdentity
            ) { quarantineParent, quarantineLeaf in
                try quarantineAndRemove(
                    sourceParent: parent,
                    sourceLeaf: leaf,
                    quarantineParent: quarantineParent,
                    quarantineLeaf: quarantineLeaf,
                    expectedIdentity: identity
                )
            }
        }
    }

    static func removeMatchingRegularFile(
        at url: URL,
        expectedData: Data,
        quarantineAt quarantineURL: URL,
        within rootURL: URL,
        rootIdentity: RootIdentity
    ) throws {
        try withParentDescriptor(
            of: url,
            within: rootURL,
            rootIdentity: rootIdentity
        ) { parent, leaf in
            let descriptor = Darwin.openat(parent, leaf, O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else { throw Failure.cleanupFailed }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            let expectedParent = try directoryIdentity(parent)
            let identity: RootIdentity
            do {
                identity = try regularFileIdentity(descriptor)
            } catch {
                try? handle.close()
                throw Failure.cleanupFailed
            }
            do {
                try ProtectedFilePolicyV1.verify(
                    inferredRegularFileKind(for: url),
                    at: url
                )
                guard try directoryIdentity(parent) == expectedParent,
                      try regularFileIdentity(parent: parent, name: leaf) == identity else {
                    throw Failure.cleanupFailed
                }
            } catch {
                try? handle.close()
                throw Failure.cleanupFailed
            }
            let bytes: Data
            do {
                bytes = try handle.readToEnd() ?? Data()
            } catch {
                throw Failure.cleanupFailed
            }
            guard bytes == expectedData else { throw Failure.cleanupFailed }
            guard try directoryIdentity(parent) == expectedParent,
                  try regularFileIdentity(parent: parent, name: leaf) == identity else {
                throw Failure.cleanupFailed
            }
            try withParentDescriptor(
                of: quarantineURL,
                within: rootURL,
                rootIdentity: rootIdentity
            ) { quarantineParent, quarantineLeaf in
                try quarantineAndRemove(
                    sourceParent: parent,
                    sourceLeaf: leaf,
                    quarantineParent: quarantineParent,
                    quarantineLeaf: quarantineLeaf,
                    expectedIdentity: identity
                )
            }
        }
    }

    static func applyAndVerifyRegularFilePolicy(
        _ kind: OwnedFileKindV1,
        at url: URL,
        within rootURL: URL,
        rootIdentity: RootIdentity
    ) throws {
        try withParentDescriptor(
            of: url,
            within: rootURL,
            rootIdentity: rootIdentity
        ) { parent, leaf in
            let descriptor = Darwin.openat(parent, leaf, O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else { throw Failure.invalidAuthority }
            defer { _ = Darwin.close(descriptor) }
            let expected = try regularFileIdentity(descriptor)
            let expectedParent = try directoryIdentity(parent)
            try ProtectedFilePolicyV1.applyAndVerify(
                kind,
                at: url,
                authorityCheck: {
                    guard try directoryIdentity(parent) == expectedParent,
                          try regularFileIdentity(descriptor) == expected,
                          try regularFileIdentity(parent: parent, name: leaf) == expected,
                          try Self.rootIdentity(at: rootURL) == rootIdentity else {
                        throw Failure.invalidAuthority
                    }
                }
            )
            guard Darwin.fsync(descriptor) == 0,
                  Darwin.fsync(parent) == 0 else {
                throw Failure.invalidAuthority
            }
        }
    }

    static func ensureDirectory(
        relativePath: String,
        policyKind: OwnedFileKindV1,
        within rootURL: URL,
        rootIdentity: RootIdentity
    ) throws {
        let components = try validatedComponents(relativePath)
        try withRootDescriptor(rootURL, identity: rootIdentity) { root in
            var current = Darwin.dup(root)
            var policyURL = rootURL.standardizedFileURL
            guard current >= 0 else { throw Failure.invalidAuthority }
            defer { Darwin.close(current) }
            for component in components {
                var next = Darwin.openat(
                    current,
                    component,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                )
                if next < 0, errno == ENOENT {
                    guard Darwin.mkdirat(current, component, 0o700) == 0 else {
                        throw Failure.invalidAuthority
                    }
                    guard Darwin.fsync(current) == 0 else {
                        throw Failure.invalidAuthority
                    }
                    next = Darwin.openat(
                        current,
                        component,
                        O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                    )
                }
                guard next >= 0 else { throw Failure.invalidAuthority }
                policyURL.appendPathComponent(component, isDirectory: true)
                do {
                    let expectedParent = try directoryIdentity(current)
                    let expected = try directoryIdentity(next)
                    try ProtectedFilePolicyV1.applyAndVerify(
                        policyKind,
                        at: policyURL,
                        authorityCheck: {
                            guard try directoryIdentity(current) == expectedParent,
                                  try directoryIdentity(next) == expected,
                                  try directoryIdentity(at: policyURL) == expected,
                                  try Self.rootIdentity(at: rootURL) == rootIdentity else {
                                throw Failure.invalidAuthority
                            }
                        }
                    )
                    guard Darwin.fsync(next) == 0,
                          Darwin.fsync(current) == 0 else {
                        throw Failure.invalidAuthority
                    }
                } catch {
                    Darwin.close(next)
                    throw error
                }
                Darwin.close(current)
                current = next
            }
        }
    }

    // Compatibility for the recovery owner that predates the explicit policy
    // parameter. The canonical path determines the closed policy kind; callers
    // cannot accidentally classify durable PDFs as staging data.
    static func ensureDirectory(
        relativePath: String,
        within rootURL: URL,
        rootIdentity: RootIdentity
    ) throws {
        let policyKind: OwnedFileKindV1 =
            relativePath == ".staging" || relativePath.hasPrefix(".staging/")
                ? .stagingDirectory
                : .durableDirectory
        try ensureDirectory(
            relativePath: relativePath,
            policyKind: policyKind,
            within: rootURL,
            rootIdentity: rootIdentity
        )
    }

    static func createRegularFile(
        _ data: Data,
        at url: URL,
        cleanupAt cleanupURL: URL,
        within rootURL: URL,
        rootIdentity: RootIdentity
    ) throws {
        try withParentDescriptor(
            of: url,
            within: rootURL,
            rootIdentity: rootIdentity
        ) { parent, leaf in
            let descriptor = Darwin.openat(
                parent,
                leaf,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
                0o600
            )
            guard descriptor >= 0 else { throw Failure.invalidAuthority }
            let createdIdentity: RootIdentity
            do {
                createdIdentity = try regularFileIdentity(descriptor)
            } catch {
                _ = Darwin.close(descriptor)
                throw Failure.cleanupFailed
            }
            do {
                try ProtectedFilePolicyV1.applyAndVerify(
                    .stagingFile,
                    at: url,
                    authorityCheck: {
                        guard try regularFileIdentity(descriptor) == createdIdentity,
                              try regularFileIdentity(at: url) == createdIdentity,
                              try Self.rootIdentity(at: rootURL) == rootIdentity else {
                            throw Failure.invalidAuthority
                        }
                    }
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
                        } else if count < 0, errno == EINTR {
                            continue
                        } else {
                            throw Failure.invalidAuthority
                        }
                    }
                }
                guard Darwin.fsync(descriptor) == 0,
                      Darwin.fsync(parent) == 0 else {
                    throw Failure.invalidAuthority
                }
            } catch {
                do {
                    try withParentDescriptor(
                        of: cleanupURL,
                        within: rootURL,
                        rootIdentity: rootIdentity
                    ) { cleanupParent, cleanupLeaf in
                        try quarantineAndRemove(
                            sourceParent: parent,
                            sourceLeaf: leaf,
                            quarantineParent: cleanupParent,
                            quarantineLeaf: cleanupLeaf,
                            expectedIdentity: createdIdentity
                        )
                    }
                } catch {
                    _ = Darwin.close(descriptor)
                    throw Failure.cleanupFailed
                }
                _ = Darwin.close(descriptor)
                throw Failure.invalidAuthority
            }
            guard Darwin.close(descriptor) == 0 else {
                throw Failure.cleanupFailed
            }
        }
    }

    static func promoteNoReplace(
        from sourceURL: URL,
        to destinationURL: URL,
        within rootURL: URL,
        rootIdentity: RootIdentity
    ) throws {
        try withParentDescriptor(
            of: sourceURL,
            within: rootURL,
            rootIdentity: rootIdentity
        ) { sourceParent, sourceLeaf in
            try withParentDescriptor(
                of: destinationURL,
                within: rootURL,
                rootIdentity: rootIdentity
            ) { destinationParent, destinationLeaf in
                guard Darwin.renameatx_np(
                    sourceParent,
                    sourceLeaf,
                    destinationParent,
                    destinationLeaf,
                    UInt32(RENAME_EXCL)
                ) == 0 else {
                    throw Failure.invalidAuthority
                }
                guard Darwin.fsync(sourceParent) == 0,
                      Darwin.fsync(destinationParent) == 0 else {
                    throw Failure.invalidAuthority
                }
            }
        }
    }

    private static func withParentDescriptor<T>(
        of url: URL,
        within rootURL: URL,
        rootIdentity: RootIdentity,
        _ body: (Int32, String) throws -> T
    ) throws -> T {
        let root = rootURL.standardizedFileURL
        let target = url.standardizedFileURL
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard target.path.hasPrefix(prefix) else { throw Failure.invalidAuthority }
        let relative = String(target.path.dropFirst(prefix.count))
        let components = try validatedComponents(relative)
        return try withRootDescriptor(root, identity: rootIdentity) { rootDescriptor in
            var descriptor = Darwin.dup(rootDescriptor)
            guard descriptor >= 0 else { throw Failure.invalidAuthority }
            defer { Darwin.close(descriptor) }
            for component in components.dropLast() {
                let next = Darwin.openat(
                    descriptor,
                    component,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                )
                guard next >= 0 else { throw Failure.invalidAuthority }
                Darwin.close(descriptor)
                descriptor = next
            }
            guard let leaf = components.last else { throw Failure.invalidAuthority }
            return try body(descriptor, leaf)
        }
    }

    private static func withRootDescriptor<T>(
        _ rootURL: URL,
        identity: RootIdentity,
        _ body: (Int32) throws -> T
    ) throws -> T {
        let descriptor = try openGenerationRootDescriptor(rootURL)
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              RootIdentity(device: info.st_dev, inode: info.st_ino) == identity else {
            throw Failure.invalidAuthority
        }
        return try body(descriptor)
    }

    /// Trust the OS-provided application-support ancestry, then no-follow every
    /// app-owned storage component. This permits Darwin's legitimate
    /// `/var` -> `/private/var` indirection without accepting a linked
    /// `FieldEvidenceData`, `generations`, or generation UUID directory.
    private static func openGenerationRootDescriptor(_ rootURL: URL) throws -> Int32 {
        let root = rootURL.standardizedFileURL
        let generations = root.deletingLastPathComponent()
        let dataRoot = generations.deletingLastPathComponent()
        guard generations.lastPathComponent == "generations",
              dataRoot.lastPathComponent == "FieldEvidenceData",
              let generationID = UUID(uuidString: root.lastPathComponent),
              generationID.uuidString.lowercased() == root.lastPathComponent else {
            throw Failure.invalidAuthority
        }

        let dataDescriptor = Darwin.open(
            dataRoot.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard dataDescriptor >= 0 else { throw Failure.invalidAuthority }
        defer { Darwin.close(dataDescriptor) }

        let generationsDescriptor = Darwin.openat(
            dataDescriptor,
            "generations",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard generationsDescriptor >= 0 else { throw Failure.invalidAuthority }
        defer { Darwin.close(generationsDescriptor) }

        let rootDescriptor = Darwin.openat(
            generationsDescriptor,
            root.lastPathComponent,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard rootDescriptor >= 0 else { throw Failure.invalidAuthority }
        return rootDescriptor
    }

    private static func regularFileIdentity(_ descriptor: Int32) throws -> RootIdentity {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1 else {
            throw Failure.invalidAuthority
        }
        return RootIdentity(device: info.st_dev, inode: info.st_ino)
    }

    private static func regularFileIdentity(
        parent: Int32,
        name: String
    ) throws -> RootIdentity {
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw Failure.invalidAuthority }
        defer { _ = Darwin.close(descriptor) }
        return try regularFileIdentity(descriptor)
    }

    static func regularFileIdentity(at url: URL) throws -> RootIdentity {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw Failure.invalidAuthority }
        defer { _ = Darwin.close(descriptor) }
        return try regularFileIdentity(descriptor)
    }

    private static func directoryIdentity(_ descriptor: Int32) throws -> RootIdentity {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR else {
            throw Failure.invalidAuthority
        }
        return RootIdentity(device: info.st_dev, inode: info.st_ino)
    }

    private static func directoryIdentity(at url: URL) throws -> RootIdentity {
        let descriptor = Darwin.open(
            url.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else { throw Failure.invalidAuthority }
        defer { _ = Darwin.close(descriptor) }
        return try directoryIdentity(descriptor)
    }

    /// Move the exact opened inode to the report's other canonical crash-window
    /// path before unlinking it. A process death therefore leaves stage-only or
    /// final-only authority that the bounded startup matrix already reconciles.
    /// A replacement at the source path is never removed; a raced object is
    /// restored when possible and otherwise leaves both canonical paths for
    /// fail-closed maintenance.
    private static func quarantineAndRemove(
        sourceParent: Int32,
        sourceLeaf: String,
        quarantineParent: Int32,
        quarantineLeaf: String,
        expectedIdentity: RootIdentity
    ) throws {
        guard Darwin.renameatx_np(
            sourceParent,
            sourceLeaf,
            quarantineParent,
            quarantineLeaf,
            UInt32(RENAME_EXCL)
        ) == 0 else {
            throw Failure.cleanupFailed
        }
        guard Darwin.fsync(sourceParent) == 0,
              Darwin.fsync(quarantineParent) == 0 else {
            restoreQuarantined(
                quarantineParent: quarantineParent,
                quarantineLeaf: quarantineLeaf,
                sourceParent: sourceParent,
                sourceLeaf: sourceLeaf
            )
            throw Failure.cleanupFailed
        }

        var quarantined = stat()
        guard Darwin.fstatat(
            quarantineParent,
            quarantineLeaf,
            &quarantined,
            AT_SYMLINK_NOFOLLOW
        ) == 0,
              (quarantined.st_mode & S_IFMT) == S_IFREG,
              RootIdentity(
                  device: quarantined.st_dev,
                  inode: quarantined.st_ino
              ) == expectedIdentity else {
            restoreQuarantined(
                quarantineParent: quarantineParent,
                quarantineLeaf: quarantineLeaf,
                sourceParent: sourceParent,
                sourceLeaf: sourceLeaf
            )
            throw Failure.cleanupFailed
        }

        guard Darwin.unlinkat(quarantineParent, quarantineLeaf, 0) == 0 else {
            restoreQuarantined(
                quarantineParent: quarantineParent,
                quarantineLeaf: quarantineLeaf,
                sourceParent: sourceParent,
                sourceLeaf: sourceLeaf
            )
            throw Failure.cleanupFailed
        }
        guard Darwin.fsync(quarantineParent) == 0 else {
            throw Failure.cleanupFailed
        }
        var after = stat()
        guard Darwin.fstatat(
            quarantineParent,
            quarantineLeaf,
            &after,
            AT_SYMLINK_NOFOLLOW
        ) == -1,
              errno == ENOENT else {
            throw Failure.cleanupFailed
        }
    }

    private static func restoreQuarantined(
        quarantineParent: Int32,
        quarantineLeaf: String,
        sourceParent: Int32,
        sourceLeaf: String
    ) {
        _ = Darwin.renameatx_np(
            quarantineParent,
            quarantineLeaf,
            sourceParent,
            sourceLeaf,
            UInt32(RENAME_EXCL)
        )
        _ = Darwin.fsync(quarantineParent)
        _ = Darwin.fsync(sourceParent)
    }

    private static func validatedComponents(_ relativePath: String) throws -> [String] {
        let components = relativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw Failure.invalidAuthority
        }
        return components
    }

    private static func inferredRegularFileKind(for url: URL) -> OwnedFileKindV1 {
        url.standardizedFileURL.pathComponents.contains(".staging")
            ? .stagingFile
            : .reportPDF
    }
}

struct ReportRenderResult: Equatable, Sendable {
    let reportID: UUID
    let pdfRelativePath: String
    let pdfSHA256: String
    let pageCount: Int
    let requirementAssuranceSnapshotSHA256: String?
    let requirementExplanations: [RequirementExplanationItemV1]
}

enum ReportRenderAttemptResult: Equatable, Sendable {
    case ready(ReportRenderResult)
    case failed(reportID: UUID)
}

enum ReportRenderFailurePoint: Equatable, Sendable {
    case render
    case stageWrite
    case promotion
    case reread
    case readySave
    case failedStateSave
}

@MainActor
final class ReportRenderFailureInjection {
    private var pending: ReportRenderFailurePoint?

    init(failOnceAt point: ReportRenderFailurePoint) {
        pending = point
    }

    func consume(_ point: ReportRenderFailurePoint) -> Bool {
        guard pending == point else { return false }
        pending = nil
        return true
    }
}

@MainActor
final class ReportRenderService {
    private let modelContext: ModelContext
    private let generationRootURL: URL
    private let storagePreflight: StoragePreflightService
    private let fileManager: FileManager
    private let validator: SnapshotValidatorV1
    private let renderer: WorklightPDFRendererV1
    private let rootIdentity: ReportPDFAnchoredFile.RootIdentity
    private var failNextRenderAttempt: Bool
    private let failureInjection: ReportRenderFailureInjection?
    private let offMainWorker = DeterministicOffMainWorkerV1()

    convenience init(
        modelContext: ModelContext,
        generationRootURL: URL,
        storagePreflight: StoragePreflightService = StoragePreflightService(),
        fileManager: FileManager = .default,
        signPack: SignPack = .illuminatedSignV1,
        failNextRenderAttempt: Bool = false,
        failureInjection: ReportRenderFailureInjection? = nil
    ) throws {
        let profile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(
            package: signPack
        )
        try self.init(
            modelContext: modelContext,
            generationRootURL: generationRootURL,
            storagePreflight: storagePreflight,
            fileManager: fileManager,
            lifecycleRoute: .expiringCompatibility(
                profile: profile,
                posture: WorkspacePackageLifecycleCompatibilityV1.expiration
            ),
            failNextRenderAttempt: failNextRenderAttempt,
            failureInjection: failureInjection
        )
    }

    convenience init(
        modelContext: ModelContext,
        lifecycleDependencies: WorkspacePackageLifecycleDependenciesV1,
        lifecycleProfile: WorkspacePackageLifecycleProfileV1,
        storagePreflight: StoragePreflightService = StoragePreflightService(),
        fileManager: FileManager = .default,
        failNextRenderAttempt: Bool = false,
        failureInjection: ReportRenderFailureInjection? = nil
    ) throws {
        try self.init(
            modelContext: modelContext,
            generationRootURL: lifecycleDependencies.generationRootURL,
            storagePreflight: storagePreflight,
            fileManager: fileManager,
            lifecycleRoute: .live(
                dependencies: lifecycleDependencies,
                profile: lifecycleProfile
            ),
            failNextRenderAttempt: failNextRenderAttempt,
            failureInjection: failureInjection
        )
    }

    private init(
        modelContext: ModelContext,
        generationRootURL: URL,
        storagePreflight: StoragePreflightService,
        fileManager: FileManager,
        lifecycleRoute: ReportingPackageLifecycleRouteV1,
        failNextRenderAttempt: Bool,
        failureInjection: ReportRenderFailureInjection?
    ) throws {
        let root = generationRootURL.standardizedFileURL
        try lifecycleRoute.validate(generationRootURL: root)
        let lifecycleProfile = lifecycleRoute.profile
        guard root.deletingLastPathComponent().lastPathComponent == "generations",
              root.deletingLastPathComponent().deletingLastPathComponent()
                .lastPathComponent == "FieldEvidenceData",
              let generationID = UUID(uuidString: root.lastPathComponent),
              generationID.uuidString.lowercased() == root.lastPathComponent,
              try Self.itemType(at: root, fileManager: fileManager) == .typeDirectory,
              !Self.isSymbolicLink(root, fileManager: fileManager) else {
            throw ReportRenderServiceError.invalidGeneration
        }
        self.modelContext = modelContext
        self.generationRootURL = root
        do {
            self.rootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: root)
        } catch {
            throw ReportRenderServiceError.invalidGeneration
        }
        self.storagePreflight = storagePreflight
        self.fileManager = fileManager
        switch lifecycleRoute {
        case .live(let lifecycleDependencies, _):
            self.validator = try SnapshotValidatorV1(
                modelContext: modelContext,
                generationRootURL: root,
                fileManager: fileManager,
                lifecycleProfile: lifecycleProfile,
                lifecycleDependencies: lifecycleDependencies
            )
        case .expiringCompatibility:
            self.validator = try SnapshotValidatorV1(
                modelContext: modelContext,
                generationRootURL: root,
                fileManager: fileManager,
                signPack: lifecycleProfile.package
            )
        }
        self.renderer = WorklightPDFRendererV1()
        self.failNextRenderAttempt = failNextRenderAttempt
        self.failureInjection = failureInjection
    }

    /// Performs one bounded pending delivery attempt. Ordinary generation failures
    /// preserve the immutable report authority and durably leave only `failed`.
    func attemptPendingReport(id reportID: UUID) throws -> ReportRenderAttemptResult {
        do {
            return .ready(try renderPendingReport(id: reportID))
        } catch {
            guard Self.isRetryableRenderFailure(error) else { throw error }
            try persistFailed(reportID: reportID)
            return .failed(reportID: reportID)
        }
    }

    /// Captures and validates the immutable input for a resumable render job.
    /// Publication remains owned by this MainActor service; the job may only
    /// return bytes and digests for subsequent read-back/reproof.
    func validatedSnapshotForResumableJob(
        id reportID: UUID
    ) throws -> ValidatedReportSnapshotV1 {
        guard !modelContext.hasChanges else {
            throw ReportRenderServiceError.contextHasChanges
        }
        let reports = try modelContext.fetch(FetchDescriptor<Report>()).filter {
            $0.id == reportID
        }
        guard reports.count == 1, let report = reports.first,
              report.pdfState == ReportPDFState.pending.rawValue,
              report.pdfRelativePath == nil, report.pdfSHA256 == nil else {
            throw reports.isEmpty
                ? ReportRenderServiceError.reportNotFound
                : ReportRenderServiceError.reportNotPending
        }
        try requireAttemptPathsAbsent(for: reportID)
        let validated = try validator.validate(report: report)
        guard SnapshotIntegrityDiagnosticsV1.snapshotReportDivergenceFindings(
            snapshotSHA256: validated.snapshotSHA256,
            reportSHA256: report.snapshotSHA256
        ).isEmpty else {
            throw ReportRenderServiceError.bytesMismatch
        }
        try storagePreflight.checkPDFGeneration(
            referencedImageByteCount: validated.referencedImageByteCount,
            onVolumeContaining: generationRootURL
        )
        return validated
    }

    func resumableRenderJob(
        id reportID: UUID,
        workspaceID: UUID,
        generationEpoch: GenerationEpochV1,
        createdAt: Date
    ) throws -> ResumableLocalJobV1 {
        guard !modelContext.hasChanges else {
            throw ReportRenderServiceError.contextHasChanges
        }
        let reports = try modelContext.fetch(FetchDescriptor<Report>()).filter {
            $0.id == reportID
        }
        guard reports.count == 1, let report = reports.first,
              report.pdfState == ReportPDFState.pending.rawValue,
              report.pdfRelativePath == nil, report.pdfSHA256 == nil,
              Self.isLowercaseSHA256(report.snapshotSHA256) else {
            throw reports.isEmpty
                ? ReportRenderServiceError.reportNotFound
                : ReportRenderServiceError.reportNotPending
        }
        try requireAttemptPathsAbsent(for: reportID)
        let jobID = LocalJobIDV1.deterministic(
            kind: .render,
            workspaceID: workspaceID,
            immutableInputSHA256: report.snapshotSHA256
        )
        return try ResumableLocalJobV1(
            id: jobID,
            workspaceID: workspaceID,
            kind: .render,
            immutableInputSHA256: report.snapshotSHA256,
            stagingRelativePath: "report-render/\(jobID.rawValue.uuidString.lowercased())",
            generationEpoch: generationEpoch,
            createdAt: createdAt,
            checkpoint: LocalJobCheckpointV1(
                nextChunkIndex: 0,
                completedUnitCount: 0,
                totalUnitCount: 3
            )
        )
    }

    /// CPU-only provisional kernel boundary. It cannot publish a PDF or mutate
    /// canonical report state, so cancellation leaves no partial artifact.
    func renderOffMainForResumableJob(
        _ validated: ValidatedReportSnapshotV1
    ) async throws -> RenderedPDFV1 {
        try await offMainWorker.run {
            try WorklightPDFRendererV1().render(validated)
        }
    }

    func renderPendingReport(id reportID: UUID) throws -> ReportRenderResult {
        guard !modelContext.hasChanges else {
            throw ReportRenderServiceError.contextHasChanges
        }
        let reports = try modelContext.fetch(FetchDescriptor<Report>()).filter {
            $0.id == reportID
        }
        guard reports.count == 1 else {
            throw reports.isEmpty
                ? ReportRenderServiceError.reportNotFound
                : ReportRenderServiceError.invalidStorageAuthority
        }
        let report = reports[0]
        guard report.pdfState == ReportPDFState.pending.rawValue,
              report.pdfRelativePath == nil,
              report.pdfSHA256 == nil else {
            throw ReportRenderServiceError.reportNotPending
        }
        try requireAttemptPathsAbsent(for: reportID)

        let validated = try validator.validate(report: report)
        try storagePreflight.checkPDFGeneration(
            referencedImageByteCount: validated.referencedImageByteCount,
            onVolumeContaining: generationRootURL
        )
        if failNextRenderAttempt || failureInjection?.consume(.render) == true {
            failNextRenderAttempt = false
            throw ReportRenderServiceError.injectedFailure
        }
        let rendered = try renderer.render(validated)
        guard !rendered.data.isEmpty,
              rendered.pageCount > 0,
              Self.isLowercaseSHA256(rendered.sha256),
              Self.sha256(rendered.data) == rendered.sha256 else {
            throw ReportRenderServiceError.bytesMismatch
        }
        let paths = try preparePaths(for: reportID)
        var ownsStage = false
        var ownsFinal = false
        do {
            do {
                try ReportPDFAnchoredFile.createRegularFile(
                    rendered.data,
                    at: paths.stageURL,
                    cleanupAt: paths.finalURL,
                    within: generationRootURL,
                    rootIdentity: rootIdentity
                )
            } catch ReportPDFAnchoredFile.Failure.cleanupFailed {
                throw ReportRenderServiceError.cleanupFailed
            } catch {
                throw ReportRenderServiceError.writeFailed
            }
            ownsStage = true
            if failureInjection?.consume(.stageWrite) == true {
                throw ReportRenderServiceError.writeFailed
            }
            try applyPolicy(.stagingFile, at: paths.stageURL)
            try verify(
                paths.stageURL,
                expectedData: rendered.data,
                expectedSHA256: rendered.sha256
            )
            do {
                if failureInjection?.consume(.promotion) == true {
                    throw ReportRenderServiceError.writeFailed
                }
                try ReportPDFAnchoredFile.promoteNoReplace(
                    from: paths.stageURL,
                    to: paths.finalURL,
                    within: generationRootURL,
                    rootIdentity: rootIdentity
                )
            } catch {
                throw ReportRenderServiceError.writeFailed
            }
            ownsStage = false
            ownsFinal = true
            if failureInjection?.consume(.reread) == true {
                throw ReportRenderServiceError.bytesMismatch
            }
            try applyPolicy(.reportPDF, at: paths.finalURL)
            try verify(
                paths.finalURL,
                expectedData: rendered.data,
                expectedSHA256: rendered.sha256
            )

            report.pdfState = ReportPDFState.ready.rawValue
            report.pdfRelativePath = paths.finalRelativePath
            report.pdfSHA256 = rendered.sha256
            do {
                if failureInjection?.consume(.readySave) == true {
                    throw ReportRenderServiceError.saveFailed
                }
                try modelContext.save()
            } catch {
                modelContext.rollback()
                report.pdfState = ReportPDFState.pending.rawValue
                report.pdfRelativePath = nil
                report.pdfSHA256 = nil
                do {
                    try modelContext.save()
                } catch {
                    modelContext.rollback()
                    throw ReportRenderServiceError.failedStateSaveFailed
                }
                throw ReportRenderServiceError.saveFailed
            }
            ownsFinal = false
            return ReportRenderResult(
                reportID: report.id,
                pdfRelativePath: paths.finalRelativePath,
                pdfSHA256: rendered.sha256,
                pageCount: rendered.pageCount,
                requirementAssuranceSnapshotSHA256:
                    validated.snapshot.requirementAssurance?.snapshotSHA256,
                requirementExplanations: validated.requirementExplanations
            )
        } catch {
            do {
                if ownsStage {
                    let stageType = try Self.itemType(
                        at: paths.stageURL,
                        fileManager: fileManager
                    )
                    let finalType = try Self.itemType(
                        at: paths.finalURL,
                        fileManager: fileManager
                    )
                    guard !(stageType != nil && finalType != nil) else {
                        throw ReportRenderServiceError.cleanupFailed
                    }
                    if stageType != nil {
                        try removeAttemptOwned(
                            paths.stageURL,
                            quarantineAt: paths.finalURL,
                            expectedData: rendered.data
                        )
                    } else if finalType != nil {
                        try removeAttemptOwned(
                            paths.finalURL,
                            quarantineAt: paths.stageURL,
                            expectedData: rendered.data
                        )
                    }
                }
                if ownsFinal {
                    guard try Self.itemType(
                        at: paths.stageURL,
                        fileManager: fileManager
                    ) == nil else {
                        throw ReportRenderServiceError.cleanupFailed
                    }
                    if try Self.itemType(
                        at: paths.finalURL,
                        fileManager: fileManager
                    ) != nil {
                        try removeAttemptOwned(
                            paths.finalURL,
                            quarantineAt: paths.stageURL,
                            expectedData: rendered.data
                        )
                    }
                }
            } catch {
                throw ReportRenderServiceError.cleanupFailed
            }
            throw error
        }
    }

    private func removeAttemptOwned(
        _ url: URL,
        quarantineAt quarantineURL: URL,
        expectedData: Data
    ) throws {
        do {
            try ReportPDFAnchoredFile.removeMatchingRegularFile(
                at: url,
                expectedData: expectedData,
                quarantineAt: quarantineURL,
                within: generationRootURL,
                rootIdentity: rootIdentity
            )
        } catch {
            throw ReportRenderServiceError.cleanupFailed
        }
        guard try Self.itemType(at: url, fileManager: fileManager) == nil else {
            throw ReportRenderServiceError.cleanupFailed
        }
    }

    private func applyPolicy(
        _ kind: OwnedFileKindV1,
        at url: URL
    ) throws {
        do {
            try ReportPDFAnchoredFile.applyAndVerifyRegularFilePolicy(
                kind,
                at: url,
                within: generationRootURL,
                rootIdentity: rootIdentity
            )
        } catch let error as ReportRenderServiceError {
            throw error
        } catch {
            throw ReportRenderServiceError.writeFailed
        }
    }

    private func persistFailed(reportID: UUID) throws {
        guard !modelContext.hasChanges else {
            throw ReportRenderServiceError.contextHasChanges
        }
        let matches = try modelContext.fetch(FetchDescriptor<Report>()).filter {
            $0.id == reportID
        }
        guard matches.count == 1 else {
            throw matches.isEmpty
                ? ReportRenderServiceError.reportNotFound
                : ReportRenderServiceError.invalidStorageAuthority
        }
        let report = matches[0]
        guard report.pdfState == ReportPDFState.pending.rawValue,
              report.pdfRelativePath == nil,
              report.pdfSHA256 == nil else {
            throw ReportRenderServiceError.reportNotPending
        }
        report.pdfState = ReportPDFState.failed.rawValue
        do {
            if failureInjection?.consume(.failedStateSave) == true {
                throw ReportRenderServiceError.failedStateSaveFailed
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            report.pdfState = ReportPDFState.pending.rawValue
            report.pdfRelativePath = nil
            report.pdfSHA256 = nil
            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
            }
            throw ReportRenderServiceError.failedStateSaveFailed
        }
    }

    private func requireAttemptPathsAbsent(for reportID: UUID) throws {
        let id = reportID.uuidString.lowercased()
        let stage = generationRootURL.appendingPathComponent(
            ".staging/pdfs/\(id).pdf",
            isDirectory: false
        )
        let final = generationRootURL.appendingPathComponent(
            "pdfs/\(id).pdf",
            isDirectory: false
        )
        let stageType = try Self.itemType(at: stage, fileManager: fileManager)
        let finalType = try Self.itemType(at: final, fileManager: fileManager)
        guard stageType == nil, finalType == nil else {
            throw ReportRenderServiceError.invalidStorageAuthority
        }
    }

    private static func isRetryableRenderFailure(_ error: Error) -> Bool {
        if error is SnapshotValidationErrorV1
            || error is StoragePreflightError
            || error is WorklightPDFRendererErrorV1 {
            return true
        }
        guard let error = error as? ReportRenderServiceError else { return false }
        switch error {
        case .writeFailed, .bytesMismatch, .saveFailed, .injectedFailure:
            return true
        case .invalidGeneration, .reportNotFound, .reportNotPending,
             .contextHasChanges, .invalidStorageAuthority, .cleanupFailed,
             .failedStateSaveFailed:
            return false
        }
    }

    private struct Paths {
        let stageURL: URL
        let finalURL: URL
        let finalRelativePath: String
    }

    private func preparePaths(for reportID: UUID) throws -> Paths {
        let canonicalID = reportID.uuidString.lowercased()
        let stagingRoot = generationRootURL.appendingPathComponent(
            ".staging",
            isDirectory: true
        )
        let stagingPDFsRoot = stagingRoot.appendingPathComponent(
            "pdfs",
            isDirectory: true
        )
        do {
            try ReportPDFAnchoredFile.ensureDirectory(
                relativePath: ".staging",
                policyKind: .stagingDirectory,
                within: generationRootURL,
                rootIdentity: rootIdentity
            )
            try ReportPDFAnchoredFile.ensureDirectory(
                relativePath: ".staging/pdfs",
                policyKind: .stagingDirectory,
                within: generationRootURL,
                rootIdentity: rootIdentity
            )
            try ReportPDFAnchoredFile.ensureDirectory(
                relativePath: "pdfs",
                policyKind: .durableDirectory,
                within: generationRootURL,
                rootIdentity: rootIdentity
            )
        } catch {
            throw ReportRenderServiceError.invalidStorageAuthority
        }

        let stageURL = stagingPDFsRoot.appendingPathComponent(
            "\(canonicalID).pdf",
            isDirectory: false
        )
        let finalRelativePath = "pdfs/\(canonicalID).pdf"
        let finalURL = generationRootURL.appendingPathComponent(finalRelativePath)
        guard try Self.itemType(at: stageURL, fileManager: fileManager) == nil,
              try Self.itemType(at: finalURL, fileManager: fileManager) == nil else {
            throw ReportRenderServiceError.invalidStorageAuthority
        }
        return Paths(
            stageURL: stageURL,
            finalURL: finalURL,
            finalRelativePath: finalRelativePath
        )
    }

    private func verify(
        _ url: URL,
        expectedData: Data,
        expectedSHA256: String
    ) throws {
        let bytes: Data
        do {
            bytes = try ReportPDFAnchoredFile.readRegularFile(
                at: url,
                within: generationRootURL,
                rootIdentity: rootIdentity
            )
        } catch {
            throw ReportRenderServiceError.invalidStorageAuthority
        }
        guard bytes == expectedData,
              Self.sha256(bytes) == expectedSHA256 else {
            throw ReportRenderServiceError.bytesMismatch
        }
    }

    private static func itemType(
        at url: URL,
        fileManager: FileManager
    ) throws -> FileAttributeType? {
        do {
            return try fileManager.attributesOfItem(atPath: url.path)[.type]
                as? FileAttributeType
        } catch let error as CocoaError where
            error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw ReportRenderServiceError.invalidStorageAuthority
        }
    }

    private static func isSymbolicLink(
        _ url: URL,
        fileManager: FileManager
    ) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - C23 version-bound field-reference rendering

enum FieldReferenceReportRenderPolicyV1 {
    static let metadataOnly = true
    static let historicalBindingsAreImmutable = true
    static let silentReleaseReplacementAllowed = false
    static let excludesReferenceBytes = true
    static let excludesPrivateLocators = true
    static let excludesLicenseSecrets = true
    static let excludesSubjectIdentity = true

    static func validate(
        _ projection: FieldReferenceReportProjectionV1,
        format: ReportProjectionFormatV1
    ) throws -> FieldReferenceReportProjectionV1 {
        try FieldReferenceReportProjectionPolicyV1.validate(projection, format: format)
        guard metadataOnly,
              historicalBindingsAreImmutable,
              !silentReleaseReplacementAllowed,
              excludesReferenceBytes,
              excludesPrivateLocators,
              excludesLicenseSecrets,
              excludesSubjectIdentity else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        return projection
    }
}

extension ReportRenderService {
    static func validateFieldReferenceRenderInputs(
        projection: FieldReferenceReportProjectionV1,
        format: ReportProjectionFormatV1
    ) throws -> FieldReferenceReportProjectionV1 {
        try FieldReferenceReportRenderPolicyV1.validate(projection, format: format)
    }

    static func renderFieldReferenceOpenJSON(
        projection: FieldReferenceReportProjectionV1
    ) throws -> ReportProjectionOutputV1 {
        try validateFieldReferenceRenderInputs(projection: projection, format: .openJSON)
        return try DeterministicOpenJSONRendererV1.renderFieldReference(projection)
    }
}

extension ReportRenderService {
    static func renderAdvancedScheduleOpenJSON(
        _ projection: AdvancedScheduleReportProjectionV1
    ) throws -> ReportProjectionOutputV1 {
        try AdvancedScheduleReportProjectionPolicyV1.validate(projection)
        return try DeterministicOpenJSONRendererV1.renderAdvancedSchedule(projection)
    }

    static func advancedSchedulePDFMetadataLines(
        _ projection: AdvancedScheduleReportProjectionV1
    ) throws -> [String] {
        try DeterministicPDFRendererV1.advancedScheduleTextLines(projection)
    }
}

enum C48PortableReviewReportRenderBoundaryV1 {
    static let existingReportRenderServiceIsSoleRoute = true
    static let rendersDerivedMetadataOnly = true
    static let capabilityBytesRendered = false
    static let capabilityProofBytesRendered = false
    static let responseBodyRendered = false
    static let rawRequestResponseBytesRendered = false
    static let workspaceAndReplicaIdentityRendered = false

    static func validate(_ projection: C48PortableReviewDerivedHistoryProjectionV1) throws {
        try C48PortableReviewReportProjectionBoundaryV1.validate(projection)
    }
}

extension ReportRenderService {
    /// Report rendering may consume a package only after the non-activating
    /// sandbox has passed. The render service receives the immutable projection
    /// and never reaches into draft or package-byte storage.
    static func validatePackageEvolutionRenderInputs(
        report: PackageEvolutionReportProjectionV1,
        sandboxRun: PackageSandboxRunV1
    ) throws -> PackageEvolutionReportProjectionV1 {
        try PackageEvolutionReportConsumerPolicyV1.validateSandbox(sandboxRun)
        try report.validate()
        return report
    }

    /// Renderers consume the already-frozen C19 projection. This gate keeps
    /// exact values and typed units intact and prevents a renderer from
    /// looking up mutable calibration, serial, operator, or evidence state.
    static func validateMeasurementIntegrityRenderInputs(
        projection: MeasurementIntegrityReportProjectionV1,
        format: ReportProjectionFormatV1
    ) throws -> MeasurementIntegrityReportProjectionV1 {
        try ReportProjectionRegistryV1.validateMeasurementIntegrityConsumer(
            projection,
            format: format
        )
        return projection
    }

    /// C20 render/share consumers accept only the already-approved derivative
    /// projection. Original-content access is deliberately a separate caller
    /// authorization and is never implied by rendering or sharing.
    static func validatePrivacyTransformRenderInputs(
        projection: PrivacyTransformReportProjectionV1,
        format: ReportProjectionFormatV1
    ) throws -> PrivacyTransformReportProjectionV1 {
        try PrivacyTransformReportConsumerPolicyV1.validate(projection, format: format)
        return projection
    }

    static func validatePrivacyTransformShareInputs(
        projection: PrivacyTransformReportProjectionV1
    ) throws -> PrivacyTransformReportProjectionV1 {
        try PrivacyTransformReportConsumerPolicyV1.validate(projection, format: .media)
        guard projection.derivativeOnly,
              projection.originalReferenceExcluded,
              projection.redactionDeclared else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        return projection
    }

    /// C21 rendering consumes the frozen local admission/lifecycle projection
    /// only. A blocked admission may still be displayed as a recorded state,
    /// while the operation gate below prevents unsafe or write execution.
    static func validateClientCapabilityRenderInputs(
        projection: ClientCapabilityReportProjectionV1,
        format: ReportProjectionFormatV1
    ) throws -> ClientCapabilityReportProjectionV1 {
        try ClientCapabilityReportConsumerPolicyV1.validate(projection, format: format)
        return projection
    }

    static func validateClientCapabilityOperationInputs(
        projection: ClientCapabilityReportProjectionV1,
        operation: PackageLifecycleOperationV1,
        allowsWrite: Bool
    ) throws -> ClientCapabilityReportProjectionV1 {
        try ClientCapabilityReportConsumerPolicyV1.validate(projection, format: .structuredText)
        try ClientCapabilityReportConsumerPolicyV1.require(
            projection,
            operation: operation,
            allowsWrite: allowsWrite
        )
        return projection
    }

    static func validateClientCapabilityHistoricExportInputs(
        projection: ClientCapabilityReportProjectionV1
    ) throws -> ClientCapabilityReportProjectionV1 {
        try ClientCapabilityReportConsumerPolicyV1.validate(projection, format: .openJSON)
        guard ClientCapabilityReportConsumerPolicyV1.allowsHistoricExport(projection) else {
            throw ClientCapabilityReportProjectionFailureV1.admissionDenied
        }
        try ClientCapabilityReportConsumerPolicyV1.require(
            projection,
            operation: .export,
            allowsWrite: false
        )
        return projection
    }
}

// MARK: - C25 survey-definition rendering boundary

extension ReportRenderService {
    static func renderSurveyDefinitionOpenJSON(
        _ projection: SurveyDefinitionReportProjectionV1
    ) throws -> ReportProjectionOutputV1 {
        try SnapshotValidatorV1.validateSurveyDefinitionProjection(
            projection,
            format: .openJSON
        )
        return try DeterministicOpenJSONRendererV1.renderSurveyDefinition(projection)
    }

    static func surveyDefinitionPDFMetadataLines(
        _ projection: SurveyDefinitionReportProjectionV1
    ) throws -> [String] {
        try SnapshotValidatorV1.validateSurveyDefinitionProjection(
            projection,
            format: .pdf
        )
        return try WorklightPDFRendererV1.surveyDefinitionMetadataLines(projection)
    }

    static let surveyDefinitionHistoricExportUsesPinnedRelease = true
    static let surveyDefinitionReportDoesNotUpgradeDrafts = true
}

// MARK: - C27 asset-locator rendering boundary

enum AssetLocatorReportRenderPolicyV1 {
    static let metadataOnly = true
    static let historicDisplayUsesRecordedBinding = true
    static let localOfflineResolutionOnly = true
    static let excludesOpaqueInput = true
    static let excludesPrivateKeyMaterial = true
    static let excludesSecrets = true
    static let excludesVendorIdentifiers = true
    static let excludesPermissionClaims = true
    static let excludesNetworkResolutionClaims = true

    static func validate(
        _ projection: AssetLocatorReportProjectionV1,
        format: ReportProjectionFormatV1 = .openJSON
    ) throws -> AssetLocatorReportProjectionV1 {
        try projection.validate(format: format)
        guard metadataOnly, historicDisplayUsesRecordedBinding,
              localOfflineResolutionOnly, excludesOpaqueInput,
              excludesPrivateKeyMaterial, excludesSecrets,
              excludesVendorIdentifiers, excludesPermissionClaims,
              excludesNetworkResolutionClaims else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        return projection
    }
}

extension ReportRenderService {
    static func renderAssetLocatorOpenJSON(
        _ projection: AssetLocatorReportProjectionV1
    ) throws -> ReportProjectionOutputV1 {
        try AssetLocatorReportRenderPolicyV1.validate(projection)
        return try DeterministicOpenJSONRendererV1.renderAssetLocator(projection)
    }

    static func validateAssetLocatorRenderInputs(
        _ projection: AssetLocatorReportProjectionV1,
        format: ReportProjectionFormatV1 = .openJSON
    ) throws -> AssetLocatorReportProjectionV1 {
        try AssetLocatorReportRenderPolicyV1.validate(projection, format: format)
    }
}

// MARK: - C28 schedule rendering boundary

enum ScheduleReportRenderPolicyV1 {
    static let metadataOnly = true
    static let historicDisplayUsesRecordedBasis = true
    static let localProjectionOnly = true
    static let notificationDeliveryIsTruth = false
    static let excludesNotificationPayload = true
    static let excludesActorIdentity = true
    static let excludesWorkInstanceIdentity = true

    static func validate(
        _ projection: ScheduleReportProjectionV1,
        format: ReportProjectionFormatV1 = .openJSON
    ) throws -> ScheduleReportProjectionV1 {
        guard metadataOnly, historicDisplayUsesRecordedBasis,
              localProjectionOnly, !notificationDeliveryIsTruth,
              excludesNotificationPayload, excludesActorIdentity,
              excludesWorkInstanceIdentity else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        return try ScheduleReportProjectionPolicyV1.validate(
            projection,
            format: format
        )
    }
}

extension ReportRenderService {
    static func renderScheduleOpenJSON(
        _ projection: ScheduleReportProjectionV1
    ) throws -> ReportProjectionOutputV1 {
        try ScheduleReportRenderPolicyV1.validate(projection, format: .openJSON)
        return try DeterministicOpenJSONRendererV1.renderSchedule(projection)
    }

    static func schedulePDFMetadataLines(
        _ projection: ScheduleReportProjectionV1
    ) throws -> [String] {
        try ScheduleReportRenderPolicyV1.validate(projection, format: .pdf)
        return try DeterministicPDFRendererV1.scheduleTextLines(projection)
    }
}

// MARK: - C29 plan/rebase rendering boundary

enum PlanReportRenderPolicyV1 {
    static let metadataOnly = true
    static let normalizedPlacementsOnly = true
    static let historicDisplayIsFrozen = true
    static let previewIsNotApplied = true
    static let localProjectionOnly = true
    static let excludesSourceBytes = true
    static let excludesPrivateLocator = true
    static let excludesActorIdentity = true

    static func validate(
        _ projection: PlanReportProjectionV1,
        format: ReportProjectionFormatV1
    ) throws -> PlanReportProjectionV1 {
        guard metadataOnly, normalizedPlacementsOnly,
              historicDisplayIsFrozen, previewIsNotApplied,
              localProjectionOnly, excludesSourceBytes,
              excludesPrivateLocator, excludesActorIdentity else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        return try PlanReportProjectionPolicyV1.validate(
            projection,
            format: format
        )
    }
}

extension ReportRenderService {
    static func renderPlanOpenJSON(
        _ projection: PlanReportProjectionV1
    ) throws -> ReportProjectionOutputV1 {
        try PlanReportRenderPolicyV1.validate(projection, format: .openJSON)
        return try DeterministicOpenJSONRendererV1.renderPlan(projection)
    }

    static func planPDFMetadataLines(
        _ projection: PlanReportProjectionV1
    ) throws -> [String] {
        try PlanReportRenderPolicyV1.validate(projection, format: .pdf)
        return try DeterministicPDFRendererV1.planTextLines(projection)
    }
}

// MARK: - C37 reference-framed pose rendering

enum C37PoseReportRenderPolicyV1 {
    static let metadataOnly = true
    static let historicDisplayIsFrozen = true
    static let rebasePreviewIsNotApplied = true
    static let localProjectionOnly = true
    static let excludesSensorCollection = true
    static let excludesBareDirectionClaims = true
    static let excludesComplianceClaims = true

    static func validate(
        _ projection: C37PlacementPoseReportProjectionV1
    ) throws -> C37PlacementPoseReportProjectionV1 {
        guard metadataOnly, historicDisplayIsFrozen,
              rebasePreviewIsNotApplied, localProjectionOnly,
              excludesSensorCollection, excludesBareDirectionClaims,
              excludesComplianceClaims else {
            throw SnapshotProjectionFailureV1.privacyViolation
        }
        try C37PoseReportProjectionPolicyV1.validate(projection)
        return projection
    }
}

extension ReportRenderService {
    static func renderPlacementPoseOpenJSON(
        _ projection: C37PlacementPoseReportProjectionV1
    ) throws -> ReportProjectionOutputV1 {
        try C37PoseReportRenderPolicyV1.validate(projection)
        return try DeterministicOpenJSONRendererV1.renderPlacementPose(projection)
    }

    static func placementPosePDFMetadataLines(
        _ projection: C37PlacementPoseReportProjectionV1
    ) throws -> [String] {
        try C37PoseReportRenderPolicyV1.validate(projection)
        return try DeterministicPDFRendererV1.placementPoseTextLines(projection)
    }
}
// MARK: - C30 operating-context rendering

extension ReportRenderService {
    static func renderOperatingContextOpenJSON(
        _ projection: C30EvidenceContextReportReferenceV1,
        locale: String = "en"
    ) throws -> ReportProjectionOutputV1 {
        try DeterministicOpenJSONRendererV1.renderOperatingContext(
            projection,
            locale: locale
        )
    }

    static func renderOperatingContextPDFLines(
        _ projection: C30EvidenceContextReportReferenceV1
    ) throws -> [String] {
        try DeterministicPDFRendererV1.operatingContextTextLines(projection)
    }

    static let c30OperatingContextRenderingIsLocalOnly = true
    static let c30OperatingContextUsesFrozenProjection = true
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Infrastructure_Reporting_ReportRenderService {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/Reporting/ReportRenderService.swift", role: .report)
}

// MARK: - C31 lighting rendering

extension ReportRenderService {
    static func renderLightingOpenJSON(
        _ projection: C31LightingReportProjectionV1,
        locale: String = "en"
    ) throws -> ReportProjectionOutputV1 {
        try C31LightingProjectionPolicyV1.validate(projection)
        return try DeterministicOpenJSONRendererV1.renderLighting(
            projection,
            locale: locale
        )
    }

    static func lightingPDFMetadataLines(
        _ projection: C31LightingReportProjectionV1
    ) throws -> [String] {
        try C31LightingProjectionPolicyV1.validate(projection)
        return try DeterministicPDFRendererV1.lightingLines(projection)
    }

    static let c31LightingUsesFrozenMetadataOnlyProjection = true
    static let c31LightingPreservesManualOfflinePath = true
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Reporting_ReportRenderService {
    enum ProposalDispositionV1: Sendable {
        case nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
    }

    enum AcceptanceDispositionV1: Sendable {
        case durableThroughExistingCanonicalWriter
    }

    static func disposition(
        for proposal: AssistanceProposalV1
    ) throws -> ProposalDispositionV1 {
        try proposal.validate()
        guard !AssistancePersistenceEnrollmentV1.proposalIsPersistent,
              !AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent else {
            throw AssistanceContractFailureV1.nonCanonicalData
        }
        switch proposal.verificationState {
        case .unverified:
            return .nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
        }
    }

    static func disposition(
        for receipt: AssistanceAcceptanceReceiptV1
    ) throws -> AcceptanceDispositionV1 {
        try receipt.validate()
        guard AssistancePersistenceEnrollmentV1.durableModelCount == 1 else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
        return .durableThroughExistingCanonicalWriter
    }

    static let capabilityScratchIsDiscardedOnTerminalReview = true
    static let manualFallbackRemainsAvailable = true
    static let interruptionNeverPromotesAProposal = true
    static let createsParallelStoreOrWriter = false
}

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Infrastructure_Reporting_ReportRenderService_swift {
    static let durableFamilyCount = TemporalEvidencePersistenceEnrollmentV1.durableModelCount
    static func validate(clip: TemporalEvidenceClipV1,
                         anchor: TimecodedEvidenceAnchorV1) throws {
        try clip.validateIntrinsic()
        try anchor.validate(clip: clip)
        guard durableFamilyCount == 2 else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
    }
}

/// C45 label generation extends the existing renderer and bounded report job lane.
enum C45AssetLabelBoundary_ReportRenderServiceV1 {
    static func validate(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws { try snapshot.validate() }
    static let createsParallelCSVEngine = false
}

enum C46OperationalContactBoundary_30{static let defaultProjection="EXCLUDED";static let rawPhoneOrEmailEmitted=false;static let platformOutcomeClaimEmitted=false}

enum C47ActivityContractConformance_FieldEvidenceApp_Infrastructure_Reporting_ReportRenderService_swift {
    static let integrationRole = "SOLE_RENDER_SERVICE"
    static let sharedReceipt = SharedActivityEnvelopeReceiptV1.self
    static let installationReceipt = InstallationActivityContractReceiptV1.self
    static let punchReceipt = PunchActivityContractReceiptV1.self
    static let noPlanFallback = NoPlanFallbackV1.self
    static let usesExistingReportInfrastructure = true
    static let createsSecondRendererWriterOrStore = false
    static func validateReadable(_ value: ActivitySessionEnvelopeV2) throws { try value.validateForRead() }
}

extension ReportRenderService {
    func renderActivityContract(
        _ projection: ActivityContractReportProjectionV2,
        manifest: ContractManifestV1,
        reportProfile: ReportLayoutProfileV1,
        exportProfile: ExportProfileV1
    ) throws -> ReportProjectionBundleV1 {
        _ = try projection.canonicalCompletedSnapshotBytes()
        return try ReportProjectionRegistryV1().renderActivityContract(
            projection, manifest: manifest,
            reportProfile: reportProfile, exportProfile: exportProfile
        )
    }
}

// MARK: - C49 work-resource report rendering

extension ReportRenderService {
    static func renderWorkResourceOpenJSON(
        _ projection: C49WorkResourceReportProjectionV1
    ) throws -> Data {
        try DeterministicOpenJSONRendererV1.renderWorkResource(projection)
    }

    static func renderWorkResourcePDF(
        _ projection: C49WorkResourceReportProjectionV1
    ) throws -> Data {
        try DeterministicPDFRendererV1.renderWorkResourceData(projection)
    }

    static func renderWorkResourceFormulaSafeCSV(
        _ projection: C49WorkResourceReportProjectionV1
    ) throws -> Data {
        try C49WorkResourceReportSnapshotEncoderBoundaryV1.encodeFormulaSafeCSV(projection)
    }
}

enum C49WorkResourceReportRenderBoundaryV1 {
    static let rendererConsumesValidatedProjection = true
    static let openJSONAndPDFShareProjectionDigest = true
    static let csvUsesFormulaSafeEscaping = true
    static let rawStockAndLiveInventoryClaimsRendered = false
}

/// Rendering is a pure, repeatable projection step. C50 source bytes and
/// external callback status never become report truth or a customer-safe field.
enum C50IncumbentFileExchangeRenderServiceBoundaryV1 {
    static let rendererConsumesValidatedProjection = true
    static let repeatedOpenJSONAndPDFBytesMatch = true
    static let sourceAndQuarantineBytesExcluded = true
    static let directCostProjectionIsAbsent = C50IncumbentFileExchangeLifecycleBoundaryV1.directCostProjectionIsAbsent
    static let formulaSafeDelimitedExportRequired = true
    static let rawStockAndLiveInventoryClaimsExcluded = true
    static let externalAvailabilityIsNotReportTruth = true

    static func validate() -> Bool {
        rendererConsumesValidatedProjection
            && repeatedOpenJSONAndPDFBytesMatch
            && sourceAndQuarantineBytesExcluded
            && directCostProjectionIsAbsent
            && formulaSafeDelimitedExportRequired
            && rawStockAndLiveInventoryClaimsExcluded
            && externalAvailabilityIsNotReportTruth
    }
}

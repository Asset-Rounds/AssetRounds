import CryptoKit
import Darwin
import Foundation

enum EvidenceBundleScheduleBoundaryV1 { static let reminderProjectionWritesEvidence = false }

enum C51ScheduleEvidenceBundleBoundaryV1 {
    static let scheduleGenerationWritesNoEvidence = true
    static let scheduleCarriesNoMediaBytes = true
    static let evidenceBundleStoreRemainsSoleMediaAuthority = true
}

enum AssetLocatorEvidenceBundleBoundaryV1 {
    static let locatorPayloadIsEvidenceMember = false
    static let resolutionWritesEvidence = false
}

struct EvidenceBundleInput: Sendable {
    let originalJPEG: Data
    let thumbnailJPEG: Data
}

extension EvidenceBundleStore {
    func persistFieldReferenceItem(
        _ item: FieldReferenceImportItemV1,
        workspaceID: WorkspaceID,
        mutationID: MutationIDV1
    ) async throws -> DraftImmutableContentWriteReceiptV1 {
        guard item.reference.workspaceID == workspaceID.rawValue.uuidString.lowercased(),
              let digest = item.reference.digests.digest(for: .sha256) else {
            throw ContentIntegrityFailureV1.wrongWorkspace
        }
        let request = try DraftImmutableContentWriteRequestV1(
            workspaceID: workspaceID,
            contentID: item.reference.contentID,
            digest: digest,
            byteLength: item.reference.byteLength,
            mediaType: item.reference.mediaType,
            mutationID: mutationID,
            createdAt: item.reference.createdAt
        )
        return try await persistImmutableOriginal(bytes: item.bytes, request: request)
    }
}

struct StagedEvidenceBundle: Equatable, Sendable {
    let evidenceID: UUID
    let stagingDirectoryRelativePath: String
    let originalRelativePath: String
    let thumbnailRelativePath: String
    let originalByteCount: Int
    let thumbnailByteCount: Int
    let originalSHA256: String
    let thumbnailSHA256: String
}

struct PromotedEvidenceBundle: Equatable, Sendable {
    let evidenceID: UUID
    let originalRelativePath: String
    let thumbnailRelativePath: String
    let originalByteCount: Int
    let thumbnailByteCount: Int
    let originalSHA256: String
    let thumbnailSHA256: String
}

struct EvidenceBundleAuthority: Equatable, Sendable {
    let schemaVersion: Int
    let id: UUID
    let recordID: UUID
    let purposeKey: String
    let relativePath: String
    let mimeType: String
    let byteCount: Int
    let sha256: String
    let thumbnailRelativePath: String
    let thumbnailByteCount: Int
    let thumbnailSHA256: String
}

enum EvidenceBundleStoreError: Error, Equatable {
    case generationRootInvalid
    case unsafePath
    case stagingBundleAlreadyExists
    case promotedBundleAlreadyExists
    case bundleMissing
    case bundleShapeInvalid
    case fileTypeInvalid
    case canonicalJPEGInvalid
    case bundleFactsMismatch
    case promotedBundleNotOwned
    case fileOperationFailed
}

enum EvidenceBundleStoreFailurePoint: Equatable, Sendable {
    case stagingWrite
    case atomicPromotionMove
    case assetLabelPublicationBeforeMarkerCommit
    case derivativeStagingWrite
    case derivativeAtomicPublicationMove
}

final class EvidenceBundleStoreFailureInjection: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingFailure: EvidenceBundleStoreFailurePoint?

    init(failOnceAt failurePoint: EvidenceBundleStoreFailurePoint) {
        pendingFailure = failurePoint
    }

    func removeFailure() {
        lock.lock()
        pendingFailure = nil
        lock.unlock()
    }

    fileprivate func consume(_ failurePoint: EvidenceBundleStoreFailurePoint) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard pendingFailure == failurePoint else { return false }
        pendingFailure = nil
        return true
    }
}

struct AssetLabelPublishedContentReadbackV1: Equatable, Sendable {
    let plan: AssetLabelGenerationPlanV1
    let projection: LabelProjectionResultV1
    let publishedArtifacts: [AssetLabelPublishedArtifactContentV1]
}

private struct AssetLabelContentPublicationMarkerV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let jobID: LocalJobIDV1
    let plan: AssetLabelGenerationPlanV1
    let manifest: LabelArtifactManifestV1
    let nativeTextEnvironment: AssetLabelNativeTextEnvironmentV1
    let publishedArtifacts: [AssetLabelPublishedArtifactContentV1]
    let outputSHA256: String

    init(
        jobID: LocalJobIDV1,
        plan: AssetLabelGenerationPlanV1,
        projection: LabelProjectionResultV1,
        publishedArtifacts: [AssetLabelPublishedArtifactContentV1]
    ) throws {
        schemaVersion = Self.schemaVersion
        self.jobID = jobID
        self.plan = plan
        manifest = projection.manifest
        nativeTextEnvironment = projection.nativeTextEnvironment
        self.publishedArtifacts = publishedArtifacts.sorted { $0.kind.rawValue < $1.kind.rawValue }
        outputSHA256 = projection.manifest.manifestSHA256
        try validate()
    }

    func validate() throws {
        try plan.validate()
        try manifest.validate()
        try nativeTextEnvironment.validate(planSHA256: plan.planSHA256)
        try publishedArtifacts.forEach { $0.validate() }
        let workspace = plan.workspaceID.rawValue.uuidString.lowercased()
        guard schemaVersion == Self.schemaVersion,
              manifest.planSHA256 == plan.planSHA256,
              outputSHA256 == manifest.manifestSHA256,
              publishedArtifacts.count == LabelArtifactKindV1.allCases.count,
              publishedArtifacts.map(\.kind) == LabelArtifactKindV1.allCases.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(publishedArtifacts.map { $0.reference.contentID }).count == publishedArtifacts.count,
              publishedArtifacts.allSatisfy({ $0.reference.workspaceID == workspace }) else {
            throw EvidenceBundleStoreError.bundleShapeInvalid
        }
        for (published, entry) in zip(publishedArtifacts, manifest.entries) {
            try published.validate(entry: entry, workspaceID: plan.workspaceID)
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, jobID, plan, manifest, nativeTextEnvironment, publishedArtifacts, outputSHA256
    }

    init(from decoder: Decoder) throws {
        try KernelClosedCodingV1.require(decoder, keys: CodingKeys.allCases.map(\.stringValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        jobID = try c.decode(LocalJobIDV1.self, forKey: .jobID)
        plan = try c.decode(AssetLabelGenerationPlanV1.self, forKey: .plan)
        manifest = try c.decode(LabelArtifactManifestV1.self, forKey: .manifest)
        nativeTextEnvironment = try c.decode(AssetLabelNativeTextEnvironmentV1.self, forKey: .nativeTextEnvironment)
        publishedArtifacts = try c.decode([AssetLabelPublishedArtifactContentV1].self, forKey: .publishedArtifacts)
        outputSHA256 = try c.decode(String.self, forKey: .outputSHA256)
        try validate()
    }
}

/// Synchronous marker authority retained by the one EvidenceBundleStore.
/// The resumable job's generation fence surrounds these calls, while the
/// marker rename is the atomic visibility point for the three immutable files.
private final class EvidenceBundleStoreAssetLabelPublicationV1: @unchecked Sendable {
    private let rootURL: URL
    private let fileManager: FileManager
    private let failureInjection: EvidenceBundleStoreFailureInjection?
    private let lock = NSLock()

    init(rootURL: URL, fileManager: FileManager, failureInjection: EvidenceBundleStoreFailureInjection?) {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
        self.failureInjection = failureInjection
    }

    func publishOrAdopt(
        job: ResumableLocalJobV1,
        plan: AssetLabelGenerationPlanV1,
        projection: LabelProjectionResultV1
    ) throws -> AssetLabelPublishedContentReadbackV1 {
        lock.lock(); defer { lock.unlock() }
        try validate(job: job, plan: plan, projection: projection)
        if let existing = try readbackLocked(jobID: job.id) {
            guard existing.plan == plan, existing.projection == projection else {
                throw EvidenceBundleStoreError.promotedBundleAlreadyExists
            }
            return existing
        }

        let published = try makeBindings(job: job, plan: plan, projection: projection)
        let marker = try AssetLabelContentPublicationMarkerV1(
            jobID: job.id, plan: plan, projection: projection, publishedArtifacts: published
        )
        var createdArtifacts: [AssetLabelPublishedArtifactContentV1] = []
        do {
            for (binding, artifact) in zip(published, projection.artifacts) {
                let directory = contentDirectory(binding.reference)
                let target = directory.appendingPathComponent("original.bin")
                try ensureDirectory(directory, kind: .durableDirectory)
                let components = ["content", binding.reference.workspaceID, binding.reference.contentID]
                if let existing = try readFile(components: components, name: "original.bin",
                                               maximumBytes: Int(binding.reference.byteLength)) {
                    guard existing == artifact.bytes else {
                        throw EvidenceBundleStoreError.promotedBundleAlreadyExists
                    }
                } else {
                    try writeFileExclusively(artifact.bytes, components: components, name: "original.bin")
                    try ProtectedFilePolicyV1.applyAndVerify(.mediaOriginal, at: target)
                    createdArtifacts.append(binding)
                }
            }
            if failureInjection?.consume(.assetLabelPublicationBeforeMarkerCommit) == true {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            let markerURL = self.markerURL(jobID: job.id, workspaceID: plan.workspaceID)
            try ensureDirectory(markerURL.deletingLastPathComponent(), kind: .durableDirectory)
            try writeFileExclusively(
                AssetLabelCanonicalCodecV1.encode(marker),
                components: markerComponents(jobID: job.id, workspaceID: plan.workspaceID),
                name: "publication.json"
            )
            try ProtectedFilePolicyV1.applyAndVerify(.reportSnapshot, at: markerURL)
            guard let readback = try readbackLocked(jobID: job.id),
                  readback.plan == plan, readback.projection == projection else {
                throw EvidenceBundleStoreError.bundleFactsMismatch
            }
            return readback
        } catch {
            if !fileManager.fileExists(atPath: markerURL(jobID: job.id, workspaceID: plan.workspaceID).path) {
                for published in createdArtifacts.reversed() {
                    try? removeExact(published)
                }
            }
            throw error
        }
    }

    func adoptOnly(
        jobID: LocalJobIDV1,
        planSHA256: String,
        outputSHA256: String
    ) throws -> AssetLabelPublishedContentReadbackV1? {
        lock.lock(); defer { lock.unlock() }
        guard let value = try readbackLocked(jobID: jobID) else { return nil }
        guard value.plan.planSHA256 == planSHA256,
              value.projection.manifest.manifestSHA256 == outputSHA256 else {
            throw EvidenceBundleStoreError.bundleFactsMismatch
        }
        return value
    }

    func readback(jobID: LocalJobIDV1) throws -> AssetLabelPublishedContentReadbackV1? {
        lock.lock(); defer { lock.unlock() }
        return try readbackLocked(jobID: jobID)
    }

    func remove(binding: AssetLabelRenderPublicationBindingV1) throws {
        lock.lock(); defer { lock.unlock() }
        try binding.validate()
        if let marker = try markerLocked(jobID: binding.jobID, workspaceID: binding.workspaceID) {
            guard marker.plan.workspaceID == binding.workspaceID,
                  marker.plan.planSHA256 == binding.planSHA256,
                  marker.manifest.manifestSHA256 == binding.manifestSHA256,
                  marker.outputSHA256 == binding.outputSHA256,
                  marker.publishedArtifacts == binding.publishedArtifacts else {
                throw EvidenceBundleStoreError.promotedBundleNotOwned
            }
        }
        for published in binding.publishedArtifacts {
            try removeExact(published)
        }
        try removeMarker(jobID: binding.jobID, workspaceID: binding.workspaceID)
    }

    func discardUncommitted(
        job: ResumableLocalJobV1,
        plan: AssetLabelGenerationPlanV1,
        projection: LabelProjectionResultV1
    ) throws {
        lock.lock(); defer { lock.unlock() }
        try validate(job: job, plan: plan, projection: projection)
        // A marker is the sole commit point. Once present, terminal cleanup
        // must preserve the published output for acceptance/readback.
        guard try markerLocked(jobID: job.id, workspaceID: plan.workspaceID) == nil else { return }
        for published in try makeBindings(job: job, plan: plan, projection: projection) {
            try removeExact(published)
        }
    }

    func removeWorkspace(_ workspaceID: WorkspaceID) throws {
        lock.lock(); defer { lock.unlock() }
        let directory = markerWorkspaceURL(workspaceID)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        for child in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            guard let raw = UUID(uuidString: child.lastPathComponent) else { continue }
            let jobID = LocalJobIDV1(rawValue: raw)
            if let marker = try markerLocked(jobID: jobID, workspaceID: workspaceID) {
                for published in marker.publishedArtifacts { try removeExact(published) }
                try removeMarker(jobID: jobID, workspaceID: workspaceID)
            }
        }
    }

    func eraseAll() throws {
        lock.lock(); defer { lock.unlock() }
        let content = rootURL.appendingPathComponent("content", isDirectory: true)
        guard fileManager.fileExists(atPath: content.path) else { return }
        for workspace in try fileManager.contentsOfDirectory(at: content, includingPropertiesForKeys: nil) {
            let markerRoot = workspace.appendingPathComponent(".asset-label-publications", isDirectory: true)
            guard fileManager.fileExists(atPath: markerRoot.path) else { continue }
            for child in try fileManager.contentsOfDirectory(at: markerRoot, includingPropertiesForKeys: nil) {
                guard let raw = UUID(uuidString: child.lastPathComponent),
                      let workspaceRaw = UUID(uuidString: workspace.lastPathComponent) else { continue }
                let workspaceID = WorkspaceID(rawValue: workspaceRaw)
                let jobID = LocalJobIDV1(rawValue: raw)
                if let marker = try markerLocked(jobID: jobID, workspaceID: workspaceID) {
                    for published in marker.publishedArtifacts { try removeExact(published) }
                    try removeMarker(jobID: jobID, workspaceID: workspaceID)
                }
            }
        }
    }

    private func validate(job: ResumableLocalJobV1, plan: AssetLabelGenerationPlanV1,
                          projection: LabelProjectionResultV1) throws {
        try job.validate()
        try projection.validate(plan: plan)
        guard job.kind == .render, job.workspaceID == plan.workspaceID.rawValue,
              job.immutableInputSHA256 == plan.planSHA256,
              projection.manifest.manifestSHA256 == job.checkpoint.rollingOutputSHA256 else {
            throw EvidenceBundleStoreError.bundleFactsMismatch
        }
    }

    private func makeBindings(job: ResumableLocalJobV1, plan: AssetLabelGenerationPlanV1,
                              projection: LabelProjectionResultV1) throws -> [AssetLabelPublishedArtifactContentV1] {
        let workspace = plan.workspaceID.rawValue.uuidString.lowercased()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let createdAt = formatter.string(from: job.createdAt)
        return try projection.artifacts.map { artifact in
            let suffix: String
            switch artifact.entry.kind { case .pdf: suffix = "pdf"; case .formulaSafeCSV: suffix = "csv"; case .structuredText: suffix = "text" }
            let contentID = "asset-label-\(job.id.rawValue.uuidString.lowercased())-\(suffix)"
            let digest = try ContentDigestV1(algorithm: .sha256, hexadecimalValue: artifact.entry.sha256)
            let reference = try ContentReferenceV1(
                workspaceID: workspace, contentID: contentID, byteLength: artifact.entry.byteCount,
                mediaType: artifact.entry.mediaType, digests: ContentDigestSetV1([digest]),
                byteRole: .derivative, createdAt: createdAt
            )
            let locator = try ContentLocatorV1(
                locatorID: "c05-\(contentID)", workspaceID: workspace, contentID: contentID,
                locatorRevision: 1, contentDigest: digest, expectedByteLength: artifact.entry.byteCount
            )
            return try AssetLabelPublishedArtifactContentV1(kind: artifact.entry.kind, reference: reference, locator: locator)
        }.sorted { $0.kind.rawValue < $1.kind.rawValue }
    }

    private func readbackLocked(jobID: LocalJobIDV1) throws -> AssetLabelPublishedContentReadbackV1? {
        let content = rootURL.appendingPathComponent("content", isDirectory: true)
        guard fileManager.fileExists(atPath: content.path) else { return nil }
        let workspaces = try fileManager.contentsOfDirectory(at: content, includingPropertiesForKeys: nil)
        let matches = workspaces.filter {
            fileManager.fileExists(atPath: $0.appendingPathComponent(".asset-label-publications/\(jobID.rawValue.uuidString.lowercased())/publication.json").path)
        }
        guard matches.count <= 1 else { throw EvidenceBundleStoreError.bundleShapeInvalid }
        guard let workspace = matches.first, let raw = UUID(uuidString: workspace.lastPathComponent) else { return nil }
        let workspaceID = WorkspaceID(rawValue: raw)
        guard let marker = try markerLocked(jobID: jobID, workspaceID: workspaceID) else { return nil }
        let artifacts = try zip(marker.publishedArtifacts, marker.manifest.entries).map { published, entry in
            guard let bytes = try readFile(
                components: ["content", published.reference.workspaceID, published.reference.contentID],
                name: "original.bin", maximumBytes: Int(published.reference.byteLength)
            ) else { throw EvidenceBundleStoreError.bundleMissing }
            return try LabelProjectedArtifactV1(kind: entry.kind, safeFilename: entry.safeFilename,
                                                mediaType: entry.mediaType, bytes: bytes, itemCount: entry.itemCount)
        }
        let projection = try LabelProjectionResultV1(
            plan: marker.plan,
            artifacts: artifacts,
            nativeTextEnvironment: marker.nativeTextEnvironment
        )
        guard projection.manifest == marker.manifest else { throw EvidenceBundleStoreError.bundleFactsMismatch }
        return AssetLabelPublishedContentReadbackV1(plan: marker.plan, projection: projection,
                                                    publishedArtifacts: marker.publishedArtifacts)
    }

    private func markerLocked(jobID: LocalJobIDV1, workspaceID: WorkspaceID) throws -> AssetLabelContentPublicationMarkerV1? {
        let url = markerURL(jobID: jobID, workspaceID: workspaceID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        guard let bytes = try readFile(
            components: markerComponents(jobID: jobID, workspaceID: workspaceID),
            name: "publication.json", maximumBytes: AssetLabelCanonicalCodecV1.maximumCanonicalByteCount
        ) else { return nil }
        guard bytes.count <= AssetLabelCanonicalCodecV1.maximumCanonicalByteCount else { throw EvidenceBundleStoreError.bundleShapeInvalid }
        let value = try AssetLabelCanonicalCodecV1.decode(AssetLabelContentPublicationMarkerV1.self, from: bytes)
        try value.validate()
        return value
    }

    private func removeExact(_ published: AssetLabelPublishedArtifactContentV1) throws {
        try published.validate()
        let url = contentURL(published.reference)
        guard fileManager.fileExists(atPath: url.path) else { return }
        guard let bytes = try readFile(
            components: ["content", published.reference.workspaceID, published.reference.contentID],
            name: "original.bin", maximumBytes: Int(published.reference.byteLength)
        ) else { return }
        guard Int64(bytes.count) == published.reference.byteLength,
              KernelCanonicalHashV1.sha256(bytes) == published.reference.digests.digest(for: .sha256)?.hexadecimalValue else {
            throw EvidenceBundleStoreError.promotedBundleNotOwned
        }
        try removeSingleFileDirectory(
            parentComponents: ["content", published.reference.workspaceID],
            directoryName: published.reference.contentID,
            fileName: "original.bin"
        )
    }

    private func removeMarker(jobID: LocalJobIDV1, workspaceID: WorkspaceID) throws {
        let directory = markerURL(jobID: jobID, workspaceID: workspaceID).deletingLastPathComponent()
        if fileManager.fileExists(atPath: directory.path) {
            try removeSingleFileDirectory(
                parentComponents: markerComponents(jobID: jobID, workspaceID: workspaceID).dropLast().map(String.init),
                directoryName: jobID.rawValue.uuidString.lowercased(),
                fileName: "publication.json"
            )
        }
    }

    private func contentDirectory(_ reference: ContentReferenceV1) -> URL {
        rootURL.appendingPathComponent("content/\(reference.workspaceID)/\(reference.contentID)", isDirectory: true)
    }
    private func contentURL(_ reference: ContentReferenceV1) -> URL { contentDirectory(reference).appendingPathComponent("original.bin") }
    private func markerWorkspaceURL(_ workspaceID: WorkspaceID) -> URL {
        rootURL.appendingPathComponent("content/\(workspaceID.rawValue.uuidString.lowercased())/.asset-label-publications", isDirectory: true)
    }
    private func markerURL(jobID: LocalJobIDV1, workspaceID: WorkspaceID) -> URL {
        markerWorkspaceURL(workspaceID).appendingPathComponent(jobID.rawValue.uuidString.lowercased(), isDirectory: true).appendingPathComponent("publication.json")
    }
    private func markerComponents(jobID: LocalJobIDV1, workspaceID: WorkspaceID) -> [String] {
        ["content", workspaceID.rawValue.uuidString.lowercased(), ".asset-label-publications",
         jobID.rawValue.uuidString.lowercased()]
    }

    private func withDirectoryDescriptor<T>(
        components: [String],
        create: Bool = false,
        _ body: (Int32) throws -> T
    ) throws -> T {
        guard rootURL.isFileURL,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") && !$0.contains("\\") }) else {
            throw EvidenceBundleStoreError.unsafePath
        }
        var descriptor = Darwin.open(rootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw EvidenceBundleStoreError.generationRootInvalid }
        defer { _ = Darwin.close(descriptor) }
        for component in components {
            if create && Darwin.mkdirat(descriptor, component, 0o700) != 0 && errno != EEXIST {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            let next = Darwin.openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard next >= 0 else { throw EvidenceBundleStoreError.unsafePath }
            var information = stat()
            guard Darwin.fstat(next, &information) == 0,
                  information.st_mode & S_IFMT == S_IFDIR else {
                _ = Darwin.close(next)
                throw EvidenceBundleStoreError.unsafePath
            }
            _ = Darwin.close(descriptor)
            descriptor = next
        }
        return try body(descriptor)
    }

    private func readFile(components: [String], name: String, maximumBytes: Int) throws -> Data? {
        try withDirectoryDescriptor(components: components) { parent in
            let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NOFOLLOW)
            if descriptor < 0 && errno == ENOENT { return nil }
            guard descriptor >= 0 else { throw EvidenceBundleStoreError.unsafePath }
            defer { _ = Darwin.close(descriptor) }
            var information = stat()
            guard Darwin.fstat(descriptor, &information) == 0,
                  information.st_mode & S_IFMT == S_IFREG,
                  information.st_nlink == 1,
                  information.st_size >= 0,
                  information.st_size <= maximumBytes else {
                throw EvidenceBundleStoreError.fileTypeInvalid
            }
            var result = Data()
            result.reserveCapacity(Int(information.st_size))
            var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
            while true {
                let count = Darwin.read(descriptor, &buffer, buffer.count)
                guard count >= 0 else { throw EvidenceBundleStoreError.fileOperationFailed }
                if count == 0 { break }
                result.append(contentsOf: buffer.prefix(count))
                guard result.count <= maximumBytes else { throw EvidenceBundleStoreError.bundleShapeInvalid }
            }
            guard result.count == Int(information.st_size) else { throw EvidenceBundleStoreError.bundleFactsMismatch }
            return result
        }
    }

    private func writeFileExclusively(_ bytes: Data, components: [String], name: String) throws {
        try withDirectoryDescriptor(components: components, create: true) { parent in
            let temporary = ".asset-label-\(UUID().uuidString.lowercased()).tmp"
            let descriptor = Darwin.openat(parent, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { throw EvidenceBundleStoreError.fileOperationFailed }
            var shouldUnlink = true
            defer {
                _ = Darwin.close(descriptor)
                if shouldUnlink { _ = Darwin.unlinkat(parent, temporary, 0) }
            }
            try bytes.withUnsafeBytes { raw in
                var offset = 0
                while offset < raw.count {
                    let count = Darwin.write(descriptor, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                    guard count > 0 else { throw EvidenceBundleStoreError.fileOperationFailed }
                    offset += count
                }
            }
            guard Darwin.fsync(descriptor) == 0,
                  Darwin.linkat(parent, temporary, parent, name, 0) == 0,
                  Darwin.unlinkat(parent, temporary, 0) == 0,
                  Darwin.fsync(parent) == 0 else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            shouldUnlink = false
        }
    }

    private func removeSingleFileDirectory(
        parentComponents: [String], directoryName: String, fileName: String
    ) throws {
        try withDirectoryDescriptor(components: parentComponents) { parent in
            let child = Darwin.openat(parent, directoryName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            if child < 0 && errno == ENOENT { return }
            guard child >= 0 else { throw EvidenceBundleStoreError.unsafePath }
            defer { _ = Darwin.close(child) }
            let file = Darwin.openat(child, fileName, O_RDONLY | O_NOFOLLOW)
            if file >= 0 {
                var information = stat()
                let valid = Darwin.fstat(file, &information) == 0
                    && information.st_mode & S_IFMT == S_IFREG && information.st_nlink == 1
                _ = Darwin.close(file)
                guard valid, Darwin.unlinkat(child, fileName, 0) == 0 else {
                    throw EvidenceBundleStoreError.promotedBundleNotOwned
                }
            } else if errno != ENOENT {
                throw EvidenceBundleStoreError.unsafePath
            }
            guard Darwin.fsync(child) == 0,
                  Darwin.unlinkat(parent, directoryName, AT_REMOVEDIR) == 0 || errno == ENOENT,
                  Darwin.fsync(parent) == 0 else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
        }
    }
    private func ensureDirectory(_ url: URL, kind: OwnedFileKindV1) throws {
        guard url.standardizedFileURL.path.hasPrefix(rootURL.path + "\\") || url.standardizedFileURL.path.hasPrefix(rootURL.path + "/") else {
            throw EvidenceBundleStoreError.unsafePath
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try ProtectedFilePolicyV1.applyAndVerify(kind, at: url)
    }
}

actor EvidenceBundleStore: DraftImmutableContentWriterV1 {
    private struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private let generationRootURL: URL
    private let fileManager: FileManager
    private let failureInjection: EvidenceBundleStoreFailureInjection?
    nonisolated private let assetLabelPublications: EvidenceBundleStoreAssetLabelPublicationV1

    init(
        generationRootURL: URL,
        fileManager: FileManager = .default,
        failureInjection: EvidenceBundleStoreFailureInjection? = nil
    ) {
        self.generationRootURL = generationRootURL.standardizedFileURL
        self.fileManager = fileManager
        self.failureInjection = failureInjection
        assetLabelPublications = EvidenceBundleStoreAssetLabelPublicationV1(
            rootURL: generationRootURL,
            fileManager: fileManager,
            failureInjection: failureInjection
        )
    }

    nonisolated func publishOrAdoptAssetLabelArtifacts(
        job: ResumableLocalJobV1,
        plan: AssetLabelGenerationPlanV1,
        projection: LabelProjectionResultV1
    ) throws -> AssetLabelPublishedContentReadbackV1 {
        try assetLabelPublications.publishOrAdopt(job: job, plan: plan, projection: projection)
    }

    nonisolated func adoptAssetLabelArtifacts(
        jobID: LocalJobIDV1,
        planSHA256: String,
        outputSHA256: String
    ) throws -> AssetLabelPublishedContentReadbackV1? {
        try assetLabelPublications.adoptOnly(jobID: jobID, planSHA256: planSHA256, outputSHA256: outputSHA256)
    }

    nonisolated func readAssetLabelArtifacts(jobID: LocalJobIDV1) throws -> AssetLabelPublishedContentReadbackV1? {
        try assetLabelPublications.readback(jobID: jobID)
    }

    nonisolated func removeAssetLabelPublishedOutput(_ binding: AssetLabelRenderPublicationBindingV1) throws {
        try assetLabelPublications.remove(binding: binding)
    }

    nonisolated func discardUncommittedAssetLabelArtifacts(
        job: ResumableLocalJobV1,
        plan: AssetLabelGenerationPlanV1,
        projection: LabelProjectionResultV1
    ) throws {
        try assetLabelPublications.discardUncommitted(job: job, plan: plan, projection: projection)
    }

    nonisolated func removeAssetLabelPublishedWorkspace(_ workspaceID: WorkspaceID) throws {
        try assetLabelPublications.removeWorkspace(workspaceID)
    }

    nonisolated func eraseAllAssetLabelPublishedArtifacts() throws {
        try assetLabelPublications.eraseAll()
    }

    /// Persists a C36 immutable original through the existing C05 generation
    /// root.  The content namespace is intentionally separate from the
    /// evidence-ID bundle namespace: attachments do not receive an
    /// EvidenceID, while all descriptor-safe writing, protection, and
    /// read-back still belong to this one store.
    func persistImmutableOriginal(
        bytes: Data,
        request: DraftImmutableContentWriteRequestV1
    ) async throws -> DraftImmutableContentWriteReceiptV1 {
        try request.validate()
        guard Int64(bytes.count) == request.byteLength else {
            throw DraftImmutableContentWriterFailureV1.byteLengthMismatch
        }
        do {
            let observed = try ContentIntegrityV1.observe(
                workspaceID: request.workspaceID.rawValue.uuidString.lowercased(),
                contentID: request.contentID,
                data: bytes,
                mediaType: request.mediaType,
                algorithms: [.sha256]
            )
            guard observed.digests.digest(for: request.digest.algorithm) == request.digest else {
                throw DraftImmutableContentWriterFailureV1.digestMismatch
            }
        } catch let failure as DraftImmutableContentWriterFailureV1 {
            throw failure
        } catch {
            throw DraftImmutableContentWriterFailureV1.invalidRequest
        }

        try validateGenerationRoot()
        let workspaceComponent = request.workspaceID.rawValue.uuidString.lowercased()
        let components = ["content", workspaceComponent, request.contentID]
        try ensureDirectory(
            relativeComponents: components,
            policyKind: .durableDirectory
        )
        let target = generationRootURL.appendingPathComponent(request.relativePath)

        if let existingType = try itemType(at: target) {
            guard existingType == .typeRegular else {
                throw DraftImmutableContentWriterFailureV1.immutableConflict
            }
            do {
                let existing = try withParentDescriptor(of: target) { parent, leaf in
                    try readProtectedRegularFile(
                        .mediaOriginal,
                        at: target,
                        parent: parent,
                        name: leaf
                    )
                }
                guard existing == bytes else {
                    throw DraftImmutableContentWriterFailureV1.immutableConflict
                }
                let receipt = try DraftImmutableContentWriteReceiptV1(
                    request: request,
                    relativePath: request.relativePath,
                    reusedExistingBytes: true
                )
                try receipt.validate(request: request, bytes: existing)
                return receipt
            } catch let failure as DraftImmutableContentWriterFailureV1 {
                throw failure
            } catch {
                throw DraftImmutableContentWriterFailureV1.immutableConflict
            }
        }

        do {
            try writeProtectedImmutableFile(bytes, to: target)
            let verified = try withParentDescriptor(of: target) { parent, leaf in
                try readProtectedRegularFile(
                    .mediaOriginal,
                    at: target,
                    parent: parent,
                    name: leaf
                )
            }
            guard verified == bytes else {
                throw DraftImmutableContentWriterFailureV1.digestMismatch
            }
            let receipt = try DraftImmutableContentWriteReceiptV1(
                request: request,
                relativePath: request.relativePath,
                reusedExistingBytes: false
            )
            try receipt.validate(request: request, bytes: verified)
            return receipt
        } catch let failure as DraftImmutableContentWriterFailureV1 {
            throw failure
        } catch let failure as EvidenceBundleStoreError {
            throw failure
        } catch {
            throw EvidenceBundleStoreError.fileOperationFailed
        }
    }

    func resolveContentReference(
        _ reference: ContentReferenceV1
    ) throws -> ContentReferenceV1? {
        guard reference.byteLength >= 0,
              reference.byteLength <= EvidenceCurationLimitsV1.maximumSourceBytes else {
            throw EvidenceDerivativeServiceFailureV1.limitExceeded
        }
        try validateGenerationRoot()
        let workspace = reference.workspaceID
        let target = generationRootURL
            .appendingPathComponent("content", isDirectory: true)
            .appendingPathComponent(workspace, isDirectory: true)
            .appendingPathComponent(reference.contentID, isDirectory: true)
            .appendingPathComponent("original.bin", isDirectory: false)
        guard let type = try itemType(at: target) else { return nil }
        guard type == .typeRegular else { throw EvidenceBundleStoreError.fileTypeInvalid }
        guard let expected = reference.digests.digest(for: .sha256) else {
            throw EvidenceDerivativeServiceFailureV1.missingSource
        }
        let observed = try withParentDescriptor(of: target) { parent, leaf in
            try verifyProtectedRegularFile(
                .mediaOriginal,
                at: target,
                parent: parent,
                name: leaf,
                expectedByteCount: reference.byteLength
            )
        }
        guard observed == expected.hexadecimalValue else {
            throw EvidenceDerivativeServiceFailureV1.missingSource
        }
        return reference
    }

    /// Reads only a digest-verified, descriptor-owned still-image source for
    /// the bounded C02 renderer. The encoded-byte ceiling is checked before
    /// any Data allocation; decoded pixel bounds are enforced by the renderer
    /// before ImageIO is allowed to materialize pixels.
    func readEvidenceDerivativeSource(
        _ reference: ContentReferenceV1
    ) throws -> Data {
        guard reference.byteLength > 0,
              reference.byteLength <= Int64(MediaContractV1.sourceByteCountMaximum),
              let expected = reference.digests.digest(for: .sha256) else {
            throw EvidenceDerivativeServiceFailureV1.limitExceeded
        }
        try validateGenerationRoot()
        let target = generationRootURL
            .appendingPathComponent("content", isDirectory: true)
            .appendingPathComponent(reference.workspaceID, isDirectory: true)
            .appendingPathComponent(reference.contentID, isDirectory: true)
            .appendingPathComponent("original.bin", isDirectory: false)
        guard try itemType(at: target) == .typeRegular else {
            throw EvidenceDerivativeServiceFailureV1.missingSource
        }
        let bytes = try withParentDescriptor(of: target) { parent, leaf in
            try readProtectedRegularFile(
                .mediaOriginal,
                at: target,
                parent: parent,
                name: leaf,
                maximumBytes: reference.byteLength
            )
        }
        guard Int64(bytes.count) == reference.byteLength,
              KernelCanonicalHashV1.sha256(bytes) == expected.hexadecimalValue else {
            throw EvidenceDerivativeServiceFailureV1.missingSource
        }
        return bytes
    }

    func publishOrAdoptEvidenceDerivative(
        _ package: EvidenceDerivativeStorePackageV1,
        cancellation: EvidenceDerivativeCancellationV1
    ) throws -> EvidenceDerivativeContentPublicationReceiptV1 {
        let workspace = package.workspaceID.rawValue.uuidString.lowercased()
        let derivative = package.result.derivative
        guard derivative.workspaceID == workspace,
              package.orderedSources.count <= ContentContractLimitsV1.maximumProvenanceSources,
              Int64(package.derivativeBytes.count) == derivative.byteLength,
              derivative.byteLength <= Int64(EvidenceDerivativeMediaBoundsV1.maximumDerivativeBytes),
              package.derivativeBytes.count <= EvidenceDerivativeMediaBoundsV1.maximumDerivativeBytes else {
            throw EvidenceDerivativeServiceFailureV1.invalidRequest
        }
        let marker = try EvidenceDerivativePublicationMarkerV1(package: package)
        let markerData = try EvidenceCurationCanonicalCodecV1.encode(marker)
        guard markerData.count <= ContentContractLimitsV1.maximumCanonicalBytes else {
            throw EvidenceDerivativeServiceFailureV1.limitExceeded
        }
        try validateGenerationRoot()
        let stagingComponents = [
            ".staging", "evidence-derivatives", workspace, package.operationID
        ]
        let finalComponents = ["content", workspace, derivative.contentID]
        let staging = stagingComponents.reduce(generationRootURL) {
            $0.appendingPathComponent($1, isDirectory: true)
        }
        let final = finalComponents.reduce(generationRootURL) {
            $0.appendingPathComponent($1, isDirectory: true)
        }

        if try itemType(at: final) != nil {
            return try adoptEvidenceDerivative(
                marker: marker,
                markerData: markerData,
                derivativeBytes: package.derivativeBytes,
                finalDirectory: final,
                disposition: .adopted
            )
        }
        try cleanupMatchingDerivativeStaging(
            at: staging,
            markerData: markerData,
            derivativeBytes: package.derivativeBytes
        )
        if cancellation.isCancelled {
            throw EvidenceDerivativeServiceFailureV1.interrupted
        }
        try ensureDirectory(relativeComponents: Array(stagingComponents.dropLast()))
        try ensureDirectory(
            relativeComponents: stagingComponents,
            policyKind: .stagingDirectory
        )
        let stagedBytes = staging.appendingPathComponent("original.bin")
        let stagedMarker = staging.appendingPathComponent("derivative-publication.json")
        var didPublish = false
        do {
            guard failureInjection?.consume(.derivativeStagingWrite) != true else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            try writeProtectedStagingFile(package.derivativeBytes, to: stagedBytes)
            try writeProtectedStagingFile(markerData, to: stagedMarker)
            guard try withParentDescriptor(of: stagedBytes, { parent, leaf in
                try readProtectedRegularFile(
                    .stagingFile,
                    at: stagedBytes,
                    parent: parent,
                    name: leaf,
                    maximumBytes: derivative.byteLength
                )
            }) == package.derivativeBytes,
                  try withParentDescriptor(of: stagedMarker, { parent, leaf in
                    try readProtectedRegularFile(
                        .stagingFile,
                        at: stagedMarker,
                        parent: parent,
                        name: leaf,
                        maximumBytes: Int64(ContentContractLimitsV1.maximumCanonicalBytes)
                    )
                  }) == markerData else {
                throw EvidenceBundleStoreError.bundleFactsMismatch
            }
            if cancellation.isCancelled {
                throw EvidenceDerivativeServiceFailureV1.interrupted
            }
            try applyPromotedMediaPolicy(.mediaOriginal, at: stagedBytes)
            try applyPromotedMediaPolicy(.reportSnapshot, at: stagedMarker)
            try applyDirectoryPolicy(.durableDirectory, at: staging)
            try ensureDirectory(relativeComponents: Array(finalComponents.dropLast()))
            guard failureInjection?.consume(.derivativeAtomicPublicationMove) != true else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            try moveDirectoryNoReplace(from: staging, to: final, didMove: &didPublish)
            return try adoptEvidenceDerivative(
                marker: marker,
                markerData: markerData,
                derivativeBytes: package.derivativeBytes,
                finalDirectory: final,
                disposition: .published
            )
        } catch {
            if !didPublish {
                do {
                    try removeExactDirectoryIfPresent(staging)
                } catch {
                    throw EvidenceBundleStoreError.fileOperationFailed
                }
            }
            throw error
        }
    }

    func evidenceDerivativePublicationExists(
        workspaceID: WorkspaceID,
        contentID: String
    ) throws -> Bool {
        guard ContentContractValidationV1.validID(contentID) else {
            throw EvidenceDerivativeServiceFailureV1.invalidRequest
        }
        let workspace = workspaceID.rawValue.uuidString.lowercased()
        let directory = generationRootURL
            .appendingPathComponent("content", isDirectory: true)
            .appendingPathComponent(workspace, isDirectory: true)
            .appendingPathComponent(contentID, isDirectory: true)
        guard let type = try itemType(at: directory) else { return false }
        guard type == .typeDirectory else { throw EvidenceBundleStoreError.fileTypeInvalid }
        let names = try withOwnedDirectory(at: directory, directoryNames)
        return names.contains("derivative-publication.json")
    }

    private func adoptEvidenceDerivative(
        marker: EvidenceDerivativePublicationMarkerV1,
        markerData: Data,
        derivativeBytes: Data,
        finalDirectory: URL,
        disposition: EvidenceDerivativePublicationDispositionV1
    ) throws -> EvidenceDerivativeContentPublicationReceiptV1 {
        guard try itemType(at: finalDirectory) == .typeDirectory else {
            throw EvidenceDerivativeServiceFailureV1.replayDiverged
        }
        let names = try withOwnedDirectory(at: finalDirectory, directoryNames)
        guard names == ["derivative-publication.json", "original.bin"] else {
            throw EvidenceDerivativeServiceFailureV1.replayDiverged
        }
        let bytesURL = finalDirectory.appendingPathComponent("original.bin")
        let markerURL = finalDirectory.appendingPathComponent("derivative-publication.json")
        let observedBytes = try withParentDescriptor(of: bytesURL) { parent, leaf in
            try readProtectedRegularFile(
                .mediaOriginal,
                at: bytesURL,
                parent: parent,
                name: leaf,
                maximumBytes: marker.result.derivative.byteLength
            )
        }
        let observedMarker = try withParentDescriptor(of: markerURL) { parent, leaf in
            try readProtectedRegularFile(
                .reportSnapshot,
                at: markerURL,
                parent: parent,
                name: leaf,
                maximumBytes: Int64(ContentContractLimitsV1.maximumCanonicalBytes)
            )
        }
        guard observedBytes == derivativeBytes, observedMarker == markerData else {
            throw EvidenceDerivativeServiceFailureV1.replayDiverged
        }
        try marker.validate()
        return EvidenceDerivativeContentPublicationReceiptV1(
            disposition: disposition,
            result: marker.result
        )
    }

    private func cleanupMatchingDerivativeStaging(
        at directory: URL,
        markerData: Data,
        derivativeBytes: Data
    ) throws {
        guard let type = try itemType(at: directory) else { return }
        guard type == .typeDirectory else {
            throw EvidenceDerivativeServiceFailureV1.replayDiverged
        }
        let names = try withOwnedDirectory(at: directory, directoryNames)
        guard Set(names).isSubset(of: Set(["derivative-publication.json", "original.bin"])) else {
            throw EvidenceDerivativeServiceFailureV1.replayDiverged
        }
        let bytesURL = directory.appendingPathComponent("original.bin")
        if names.contains("original.bin") {
            let observed = try readDerivativeStagingFile(
                at: bytesURL,
                temporaryKind: .stagingFile,
                promotedKind: .mediaOriginal,
                maximumBytes: Int64(derivativeBytes.count)
            )
            guard observed == derivativeBytes else {
                throw EvidenceDerivativeServiceFailureV1.replayDiverged
            }
        }
        let markerURL = directory.appendingPathComponent("derivative-publication.json")
        if names.contains("derivative-publication.json") {
            let observed = try readDerivativeStagingFile(
                at: markerURL,
                temporaryKind: .stagingFile,
                promotedKind: .reportSnapshot,
                maximumBytes: Int64(ContentContractLimitsV1.maximumCanonicalBytes)
            )
            guard observed == markerData else {
                throw EvidenceDerivativeServiceFailureV1.replayDiverged
            }
        }
        try removeExactDirectoryIfPresent(directory)
    }

    private func readDerivativeStagingFile(
        at url: URL,
        temporaryKind: OwnedFileKindV1,
        promotedKind: OwnedFileKindV1,
        maximumBytes: Int64
    ) throws -> Data {
        do {
            return try withParentDescriptor(of: url) { parent, leaf in
                try readProtectedRegularFile(
                    temporaryKind,
                    at: url,
                    parent: parent,
                    name: leaf,
                    maximumBytes: maximumBytes
                )
            }
        } catch {
            return try withParentDescriptor(of: url) { parent, leaf in
                try readProtectedRegularFile(
                    promotedKind,
                    at: url,
                    parent: parent,
                    name: leaf,
                    maximumBytes: maximumBytes
                )
            }
        }
    }

    func stage(
        evidenceID: UUID,
        input: EvidenceBundleInput
    ) throws -> StagedEvidenceBundle {
        try validateCanonicalJPEG(input.originalJPEG, kind: .original)
        try validateCanonicalJPEG(input.thumbnailJPEG, kind: .thumbnail)

        let paths = paths(for: evidenceID)
        try validateGenerationRoot()
        try ensureDirectory(relativeComponents: [".staging"])
        try ensureDirectory(relativeComponents: [".staging", "evidence"])

        guard try itemType(at: paths.stagingDirectoryURL) == nil else {
            throw EvidenceBundleStoreError.stagingBundleAlreadyExists
        }
        guard try itemType(at: paths.promotedDirectoryURL) == nil else {
            throw EvidenceBundleStoreError.promotedBundleAlreadyExists
        }

        do {
            try ensureDirectory(
                relativeComponents: [
                    ".staging",
                    "evidence",
                    evidenceID.uuidString.lowercased()
                ],
                policyKind: .stagingDirectory
            )
            guard failureInjection?.consume(.stagingWrite) != true else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            try writeProtectedStagingFile(
                input.originalJPEG,
                to: paths.stagingOriginalURL
            )
            try writeProtectedStagingFile(
                input.thumbnailJPEG,
                to: paths.stagingThumbnailURL
            )

            let facts = try verifyBundle(
                directoryURL: paths.stagingDirectoryURL,
                evidenceID: evidenceID,
                paths: paths
            )
            guard facts.originalByteCount == input.originalJPEG.count,
                  facts.thumbnailByteCount == input.thumbnailJPEG.count else {
                throw EvidenceBundleStoreError.bundleFactsMismatch
            }
            return StagedEvidenceBundle(
                evidenceID: evidenceID,
                stagingDirectoryRelativePath: paths.stagingDirectoryRelativePath,
                originalRelativePath: paths.originalRelativePath,
                thumbnailRelativePath: paths.thumbnailRelativePath,
                originalByteCount: facts.originalByteCount,
                thumbnailByteCount: facts.thumbnailByteCount,
                originalSHA256: facts.originalSHA256,
                thumbnailSHA256: facts.thumbnailSHA256
            )
        } catch {
            do {
                try removeExactStagingDirectoryIfPresent(paths.stagingDirectoryURL)
            } catch {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            if let failure = error as? EvidenceBundleStoreError {
                throw failure
            }
            throw EvidenceBundleStoreError.fileOperationFailed
        }
    }

    func stage(
        evidenceID: UUID,
        normalized: NormalizedMediaV1
    ) throws -> StagedEvidenceBundle {
        try stage(
            evidenceID: evidenceID,
            input: EvidenceBundleInput(
                originalJPEG: normalized.originalJPEG,
                thumbnailJPEG: normalized.thumbnailJPEG
            )
        )
    }

    func promote(_ staged: StagedEvidenceBundle) throws -> PromotedEvidenceBundle {
        let paths = paths(for: staged.evidenceID)
        try validateGenerationRoot()
        try ensureDirectory(relativeComponents: ["evidence"])
        guard try itemType(at: paths.promotedDirectoryURL) == nil else {
            throw EvidenceBundleStoreError.promotedBundleAlreadyExists
        }

        try verifyBundlePolicy(paths: paths, isStaging: true)
        let stagedFacts = try verifyBundle(
            directoryURL: paths.stagingDirectoryURL,
            evidenceID: staged.evidenceID,
            paths: paths
        )
        guard staged.stagingDirectoryRelativePath == paths.stagingDirectoryRelativePath,
              staged.originalRelativePath == paths.originalRelativePath,
              staged.thumbnailRelativePath == paths.thumbnailRelativePath,
              staged.originalByteCount == stagedFacts.originalByteCount,
              staged.thumbnailByteCount == stagedFacts.thumbnailByteCount,
              staged.originalSHA256 == stagedFacts.originalSHA256,
              staged.thumbnailSHA256 == stagedFacts.thumbnailSHA256 else {
            throw EvidenceBundleStoreError.bundleFactsMismatch
        }

        var didPromote = false
        do {
            if failureInjection?.consume(.atomicPromotionMove) == true {
                // Staged facts were proven immediately above, so this cleanup
                // is bounded to the exact active mutation and cannot touch a
                // previously promoted bundle.
                try removeExactStagingDirectoryIfPresent(paths.stagingDirectoryURL)
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            // Both directories are in the same immutable generation, so this is
            // one atomic publication of the verified original+thumbnail pair.
            try moveDirectoryNoReplace(
                from: paths.stagingDirectoryURL,
                to: paths.promotedDirectoryURL,
                didMove: &didPromote
            )
            try applyDirectoryPolicy(
                .durableDirectory,
                at: paths.promotedDirectoryURL
            )
            try applyPromotedMediaPolicy(
                .mediaOriginal,
                at: paths.promotedOriginalURL
            )
            try applyPromotedMediaPolicy(
                .mediaThumbnail,
                at: paths.promotedThumbnailURL
            )
            let verifiedPromotedFacts = try verifyBundle(
                directoryURL: paths.promotedDirectoryURL,
                evidenceID: staged.evidenceID,
                paths: paths
            )
            guard verifiedPromotedFacts == stagedFacts else {
                throw EvidenceBundleStoreError.bundleFactsMismatch
            }
            return PromotedEvidenceBundle(
                evidenceID: staged.evidenceID,
                originalRelativePath: paths.originalRelativePath,
                thumbnailRelativePath: paths.thumbnailRelativePath,
                originalByteCount: verifiedPromotedFacts.originalByteCount,
                thumbnailByteCount: verifiedPromotedFacts.thumbnailByteCount,
                originalSHA256: verifiedPromotedFacts.originalSHA256,
                thumbnailSHA256: verifiedPromotedFacts.thumbnailSHA256
            )
        } catch {
            // The final path was absent immediately before our rename. If this
            // attempt created it but verification failed, it is still unowned.
            if didPromote {
                do {
                    try removeExactDirectoryIfPresent(paths.promotedDirectoryURL)
                } catch {
                    throw EvidenceBundleStoreError.fileOperationFailed
                }
            }
            if let failure = error as? EvidenceBundleStoreError {
                throw failure
            }
            throw EvidenceBundleStoreError.fileOperationFailed
        }
    }

    func discardStaging(evidenceID: UUID) throws {
        let target = paths(for: evidenceID).stagingDirectoryURL
        try validateGenerationRoot()
        guard let type = try itemType(at: target) else {
            return
        }
        guard type == .typeDirectory else {
            throw EvidenceBundleStoreError.bundleShapeInvalid
        }
        try verifyOwnedPolicy(.stagingDirectory, at: target)
        try removeExactDirectoryIfPresent(target)
    }

    func removePromotedBundleIfOwned(_ promoted: PromotedEvidenceBundle) throws {
        let paths = paths(for: promoted.evidenceID)
        try validateGenerationRoot()
        guard try itemType(at: paths.promotedDirectoryURL) != nil else {
            return
        }
        let facts = try verifyBundle(
            directoryURL: paths.promotedDirectoryURL,
            evidenceID: promoted.evidenceID,
            paths: paths
        )
        guard promoted.originalRelativePath == paths.originalRelativePath,
              promoted.thumbnailRelativePath == paths.thumbnailRelativePath,
              promoted.originalByteCount == facts.originalByteCount,
              promoted.thumbnailByteCount == facts.thumbnailByteCount,
              promoted.originalSHA256 == facts.originalSHA256,
              promoted.thumbnailSHA256 == facts.thumbnailSHA256 else {
            throw EvidenceBundleStoreError.promotedBundleNotOwned
        }
        try removeExactDirectoryIfPresent(paths.promotedDirectoryURL)
    }

    func verifyPromoted(
        _ promoted: PromotedEvidenceBundle
    ) throws -> PromotedEvidenceBundle {
        let bundlePaths = paths(for: promoted.evidenceID)
        try validateGenerationRoot()
        let facts = try verifyBundle(
            directoryURL: bundlePaths.promotedDirectoryURL,
            evidenceID: promoted.evidenceID,
            paths: bundlePaths
        )
        guard promoted.originalRelativePath == bundlePaths.originalRelativePath,
              promoted.thumbnailRelativePath == bundlePaths.thumbnailRelativePath,
              promoted.originalByteCount == facts.originalByteCount,
              promoted.thumbnailByteCount == facts.thumbnailByteCount,
              promoted.originalSHA256 == facts.originalSHA256,
              promoted.thumbnailSHA256 == facts.thumbnailSHA256,
              isLowercaseSHA256(promoted.originalSHA256),
              isLowercaseSHA256(promoted.thumbnailSHA256) else {
            throw EvidenceBundleStoreError.bundleFactsMismatch
        }
        return promoted
    }

    func reconcile(authorities: [EvidenceBundleAuthority]) throws {
        try validateGenerationRoot()

        var authorityByID: [UUID: EvidenceBundleAuthority] = [:]
        for authority in authorities {
            guard authorityByID.updateValue(authority, forKey: authority.id) == nil else {
                throw EvidenceBundleStoreError.bundleFactsMismatch
            }
        }

        let stagingIDs = try bundleIDs(
            parentComponents: [".staging"],
            bundleDirectoryName: "evidence"
        )
        let promotedIDs = try bundleIDs(
            parentComponents: [],
            bundleDirectoryName: "evidence"
        )
        let allIDs = Set(authorityByID.keys)
            .union(stagingIDs)
            .union(promotedIDs)
            .sorted { $0.uuidString < $1.uuidString }

        var stagingCleanup: [URL] = []
        var promotedCleanup: [URL] = []

        for evidenceID in allIDs {
            let bundlePaths = paths(for: evidenceID)
            let hasStaging = stagingIDs.contains(evidenceID)
            let hasPromoted = promotedIDs.contains(evidenceID)
            if hasStaging {
                try verifyBundlePolicy(paths: bundlePaths, isStaging: true)
            }
            if hasPromoted {
                try verifyBundlePolicy(paths: bundlePaths, isStaging: false)
            }

            guard let authority = authorityByID[evidenceID] else {
                if hasStaging {
                    stagingCleanup.append(bundlePaths.stagingDirectoryURL)
                }
                if hasPromoted {
                    promotedCleanup.append(bundlePaths.promotedDirectoryURL)
                }
                continue
            }

            guard hasPromoted else {
                throw EvidenceBundleStoreError.bundleMissing
            }
            let facts = try verifyBundle(
                directoryURL: bundlePaths.promotedDirectoryURL,
                evidenceID: evidenceID,
                paths: bundlePaths
            )
            guard authority.schemaVersion == 1,
                  authority.id == evidenceID,
                  authority.mimeType == "image/jpeg",
                  authority.relativePath == bundlePaths.originalRelativePath,
                  authority.thumbnailRelativePath == bundlePaths.thumbnailRelativePath,
                  authority.byteCount == facts.originalByteCount,
                  authority.thumbnailByteCount == facts.thumbnailByteCount,
                  authority.sha256 == facts.originalSHA256,
                  authority.thumbnailSHA256 == facts.thumbnailSHA256,
                  isLowercaseSHA256(authority.sha256),
                  isLowercaseSHA256(authority.thumbnailSHA256) else {
                throw EvidenceBundleStoreError.bundleFactsMismatch
            }
            if hasStaging {
                stagingCleanup.append(bundlePaths.stagingDirectoryURL)
            }
        }

        // Do not remove anything until every row and bundle is proven
        // unambiguous. Cleanup then stays bounded to exact canonical UUID paths.
        for url in stagingCleanup {
            try removeExactDirectoryIfPresent(url)
        }
        for url in promotedCleanup {
            try removeExactDirectoryIfPresent(url)
        }
    }

    private struct BundlePaths {
        let stagingDirectoryRelativePath: String
        let originalRelativePath: String
        let thumbnailRelativePath: String
        let stagingDirectoryURL: URL
        let stagingOriginalURL: URL
        let stagingThumbnailURL: URL
        let promotedDirectoryURL: URL
        let promotedOriginalURL: URL
        let promotedThumbnailURL: URL
    }

    private struct BundleFacts: Equatable {
        let originalByteCount: Int
        let thumbnailByteCount: Int
        let originalSHA256: String
        let thumbnailSHA256: String
    }

    private func paths(for evidenceID: UUID) -> BundlePaths {
        let canonicalID = evidenceID.uuidString.lowercased()
        let stagingDirectoryRelativePath = ".staging/evidence/\(canonicalID)"
        let originalRelativePath = "evidence/\(canonicalID)/original.jpg"
        let thumbnailRelativePath = "evidence/\(canonicalID)/thumbnail.jpg"
        let stagingDirectoryURL = generationRootURL
            .appendingPathComponent(".staging", isDirectory: true)
            .appendingPathComponent("evidence", isDirectory: true)
            .appendingPathComponent(canonicalID, isDirectory: true)
        let promotedDirectoryURL = generationRootURL
            .appendingPathComponent("evidence", isDirectory: true)
            .appendingPathComponent(canonicalID, isDirectory: true)
        return BundlePaths(
            stagingDirectoryRelativePath: stagingDirectoryRelativePath,
            originalRelativePath: originalRelativePath,
            thumbnailRelativePath: thumbnailRelativePath,
            stagingDirectoryURL: stagingDirectoryURL,
            stagingOriginalURL: stagingDirectoryURL.appendingPathComponent("original.jpg"),
            stagingThumbnailURL: stagingDirectoryURL.appendingPathComponent("thumbnail.jpg"),
            promotedDirectoryURL: promotedDirectoryURL,
            promotedOriginalURL: promotedDirectoryURL.appendingPathComponent("original.jpg"),
            promotedThumbnailURL: promotedDirectoryURL.appendingPathComponent("thumbnail.jpg")
        )
    }

    private func bundleIDs(
        parentComponents: [String],
        bundleDirectoryName: String
    ) throws -> Set<UUID> {
        guard validPathComponent(bundleDirectoryName),
              parentComponents.allSatisfy(validPathComponent) else {
            throw EvidenceBundleStoreError.unsafePath
        }
        guard let result = try withOptionalDirectoryDescriptor(
            relativeComponents: parentComponents + [bundleDirectoryName]
        ) { descriptor in
            var result: Set<UUID> = []
            for name in try directoryNames(descriptor) {
                guard let id = UUID(uuidString: name),
                      id.uuidString.lowercased() == name,
                      result.insert(id).inserted else {
                    throw EvidenceBundleStoreError.bundleShapeInvalid
                }
                var info = stat()
                guard Darwin.fstatat(
                    descriptor,
                    name,
                    &info,
                    AT_SYMLINK_NOFOLLOW
                ) == 0,
                      (info.st_mode & S_IFMT) == S_IFDIR else {
                    throw EvidenceBundleStoreError.bundleShapeInvalid
                }
            }
            return result
        } else {
            return []
        }
        return result
    }

    private func verifyBundle(
        directoryURL: URL,
        evidenceID: UUID,
        paths: BundlePaths
    ) throws -> BundleFacts {
        let isStaging = directoryURL.standardizedFileURL == paths.stagingDirectoryURL
        let originalURL = isStaging ? paths.stagingOriginalURL : paths.promotedOriginalURL
        let thumbnailURL = isStaging ? paths.stagingThumbnailURL : paths.promotedThumbnailURL
        let directoryKind: OwnedFileKindV1 = isStaging
            ? .stagingDirectory
            : .durableDirectory
        let originalKind: OwnedFileKindV1 = isStaging
            ? .stagingFile
            : .mediaOriginal
        let thumbnailKind: OwnedFileKindV1 = isStaging
            ? .stagingFile
            : .mediaThumbnail
        guard try itemType(at: directoryURL) == .typeDirectory else {
            throw EvidenceBundleStoreError.bundleMissing
        }

        let (original, thumbnail): (Data, Data) = try withOwnedDirectory(
            at: directoryURL
        ) { descriptor in
            let expected = try directoryIdentity(descriptor)
            do {
                try ProtectedFilePolicyV1.verify(directoryKind, at: directoryURL)
            } catch {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            guard try directoryIdentity(descriptor) == expected,
                  try directoryIdentity(at: directoryURL) == expected else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            let names = Set(try directoryNames(descriptor))
            guard names == ["original.jpg", "thumbnail.jpg"] else {
                throw EvidenceBundleStoreError.bundleShapeInvalid
            }
            let original = try readProtectedRegularFile(
                originalKind,
                at: originalURL,
                parent: descriptor,
                name: "original.jpg"
            )
            let thumbnail = try readProtectedRegularFile(
                thumbnailKind,
                at: thumbnailURL,
                parent: descriptor,
                name: "thumbnail.jpg"
            )
            return (original, thumbnail)
        }
        try validateCanonicalJPEG(original, kind: .original)
        try validateCanonicalJPEG(thumbnail, kind: .thumbnail)
        return BundleFacts(
            originalByteCount: original.count,
            thumbnailByteCount: thumbnail.count,
            originalSHA256: sha256(original),
            thumbnailSHA256: sha256(thumbnail)
        )
    }

    private func validateCanonicalJPEG(
        _ data: Data,
        kind: MediaContractV1.OutputKind
    ) throws {
        let facts: CanonicalJPEGFactsV1
        do {
            facts = try MediaNormalizerV1().validateCanonicalJPEG(data, kind: kind)
        } catch {
            throw EvidenceBundleStoreError.canonicalJPEGInvalid
        }
        guard facts.byteCount == data.count,
              facts.pixelWidth >= 1,
              facts.pixelHeight >= 1,
              facts.pixelWidth <= kind.longestEdgeMaximum,
              facts.pixelHeight <= kind.longestEdgeMaximum else {
            throw EvidenceBundleStoreError.canonicalJPEGInvalid
        }
    }

    private struct GenerationRootAuthority {
        let applicationSupportDescriptor: Int32
        let dataRootDescriptor: Int32
        let generationsDescriptor: Int32
        let generationDescriptor: Int32
        let generationName: String
        let applicationSupportURL: URL
        let dataRootURL: URL
        let generationsURL: URL
        let generationRootURL: URL
        let applicationSupportIdentity: FileIdentity
        let dataRootIdentity: FileIdentity
        let generationsIdentity: FileIdentity
        let generationIdentity: FileIdentity
    }

    private func openGenerationRootAuthority() throws -> GenerationRootAuthority {
        let root = generationRootURL.standardizedFileURL
        let generationsURL = root.deletingLastPathComponent()
        let dataRootURL = generationsURL.deletingLastPathComponent()
        let applicationSupportURL = dataRootURL.deletingLastPathComponent()
        let generationName = root.lastPathComponent
        guard generationsURL.lastPathComponent == "generations",
              dataRootURL.lastPathComponent == "FieldEvidenceData",
              let generationID = UUID(uuidString: generationName),
              generationID.uuidString.lowercased() == generationName,
              !applicationSupportURL.path.isEmpty else {
            throw EvidenceBundleStoreError.generationRootInvalid
        }

        var retained: [Int32] = []
        var succeeded = false
        defer {
            if !succeeded {
                retained.reversed().forEach { _ = Darwin.close($0) }
            }
        }

        let applicationSupportDescriptor = Darwin.open(
            applicationSupportURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard applicationSupportDescriptor >= 0 else {
            throw EvidenceBundleStoreError.generationRootInvalid
        }
        retained.append(applicationSupportDescriptor)

        let dataRootDescriptor = Darwin.openat(
            applicationSupportDescriptor,
            "FieldEvidenceData",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard dataRootDescriptor >= 0 else {
            throw EvidenceBundleStoreError.generationRootInvalid
        }
        retained.append(dataRootDescriptor)

        let generationsDescriptor = Darwin.openat(
            dataRootDescriptor,
            "generations",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard generationsDescriptor >= 0 else {
            throw EvidenceBundleStoreError.generationRootInvalid
        }
        retained.append(generationsDescriptor)

        let generationDescriptor = Darwin.openat(
            generationsDescriptor,
            generationName,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard generationDescriptor >= 0 else {
            throw EvidenceBundleStoreError.generationRootInvalid
        }
        retained.append(generationDescriptor)

        let authority = GenerationRootAuthority(
            applicationSupportDescriptor: applicationSupportDescriptor,
            dataRootDescriptor: dataRootDescriptor,
            generationsDescriptor: generationsDescriptor,
            generationDescriptor: generationDescriptor,
            generationName: generationName,
            applicationSupportURL: applicationSupportURL,
            dataRootURL: dataRootURL,
            generationsURL: generationsURL,
            generationRootURL: root,
            applicationSupportIdentity: try directoryIdentity(applicationSupportDescriptor),
            dataRootIdentity: try directoryIdentity(dataRootDescriptor),
            generationsIdentity: try directoryIdentity(generationsDescriptor),
            generationIdentity: try directoryIdentity(generationDescriptor)
        )
        try reproveGenerationRoot(authority)
        succeeded = true
        return authority
    }

    private func closeGenerationRootAuthority(_ authority: GenerationRootAuthority) {
        _ = Darwin.close(authority.generationDescriptor)
        _ = Darwin.close(authority.generationsDescriptor)
        _ = Darwin.close(authority.dataRootDescriptor)
        _ = Darwin.close(authority.applicationSupportDescriptor)
    }

    private func reproveGenerationRoot(_ authority: GenerationRootAuthority) throws {
        guard try directoryIdentity(authority.applicationSupportDescriptor)
                == authority.applicationSupportIdentity,
              try directoryIdentity(authority.dataRootDescriptor)
                == authority.dataRootIdentity,
              try directoryIdentity(authority.generationsDescriptor)
                == authority.generationsIdentity,
              try directoryIdentity(authority.generationDescriptor)
                == authority.generationIdentity,
              try directoryIdentity(
                parent: authority.applicationSupportDescriptor,
                name: "FieldEvidenceData"
              ) == authority.dataRootIdentity,
              try directoryIdentity(
                parent: authority.dataRootDescriptor,
                name: "generations"
              ) == authority.generationsIdentity,
              try directoryIdentity(
                parent: authority.generationsDescriptor,
                name: authority.generationName
              ) == authority.generationIdentity,
              try directoryIdentity(at: authority.applicationSupportURL)
                == authority.applicationSupportIdentity,
              try directoryIdentity(at: authority.dataRootURL)
                == authority.dataRootIdentity,
              try directoryIdentity(at: authority.generationsURL)
                == authority.generationsIdentity,
              try directoryIdentity(at: authority.generationRootURL)
                == authority.generationIdentity else {
            throw EvidenceBundleStoreError.generationRootInvalid
        }
    }

    private func withGenerationRootAuthority<T>(
        _ body: (GenerationRootAuthority) throws -> T
    ) throws -> T {
        let authority = try openGenerationRootAuthority()
        defer { closeGenerationRootAuthority(authority) }
        try reproveGenerationRoot(authority)
        let result = try body(authority)
        try reproveGenerationRoot(authority)
        return result
    }

    private func validateGenerationRoot() throws {
        try withGenerationRootAuthority { _ in }
    }

    private func ensureDirectory(
        relativeComponents: [String],
        policyKind: OwnedFileKindV1? = nil
    ) throws {
        guard !relativeComponents.isEmpty else {
            throw EvidenceBundleStoreError.unsafePath
        }
        let resolvedPolicyKind = policyKind ?? (
            relativeComponents.first == ".staging"
                ? .stagingDirectory
                : .durableDirectory
        )
        try withDirectoryDescriptor(relativeComponents: []) { root in
            let rootExpected = try directoryIdentity(root)
            var current = root
            var currentURL = generationRootURL
            var ownsCurrent = false
            defer {
                if ownsCurrent {
                    _ = Darwin.close(current)
                }
            }

            for component in relativeComponents {
                guard validPathComponent(component) else {
                    throw EvidenceBundleStoreError.unsafePath
                }
                let parentExpected = try directoryIdentity(current)
                var next = Darwin.openat(
                    current,
                    component,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                )
                if next < 0, errno == ENOENT {
                    guard Darwin.mkdirat(current, component, mode_t(0o700)) == 0 else {
                        throw EvidenceBundleStoreError.fileOperationFailed
                    }
                    guard Darwin.fsync(current) == 0 else {
                        throw EvidenceBundleStoreError.fileOperationFailed
                    }
                    next = Darwin.openat(
                        current,
                        component,
                        O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                    )
                }
                guard next >= 0 else {
                    throw EvidenceBundleStoreError.fileOperationFailed
                }
                currentURL.appendPathComponent(component, isDirectory: true)
                do {
                    let expected = try directoryIdentity(next)
                    try ProtectedFilePolicyV1.applyAndVerify(
                        resolvedPolicyKind,
                        at: currentURL,
                        authorityCheck: {
                            guard try directoryIdentity(current) == parentExpected,
                                  try directoryIdentity(next) == expected,
                                  try directoryIdentity(at: currentURL) == expected,
                                  try directoryIdentity(root) == rootExpected else {
                                throw EvidenceBundleStoreError.fileOperationFailed
                            }
                        }
                    )
                    guard Darwin.fsync(next) == 0,
                          Darwin.fsync(current) == 0 else {
                        throw EvidenceBundleStoreError.fileOperationFailed
                    }
                } catch {
                    _ = Darwin.close(next)
                    throw error
                }
                if ownsCurrent {
                    _ = Darwin.close(current)
                }
                current = next
                ownsCurrent = true
            }
        }
    }

    private func applyDirectoryPolicy(
        _ kind: OwnedFileKindV1,
        at url: URL
    ) throws {
        do {
            try withParentDescriptor(of: url) { parent, leaf in
                let descriptor = Darwin.openat(
                    parent,
                    leaf,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                )
                guard descriptor >= 0 else {
                    throw EvidenceBundleStoreError.fileOperationFailed
                }
                defer { _ = Darwin.close(descriptor) }
                let expected = try directoryIdentity(descriptor)
                let parentExpected = try directoryIdentity(parent)
                try ProtectedFilePolicyV1.applyAndVerify(
                    kind,
                    at: url,
                    authorityCheck: {
                        try validateGenerationRoot()
                        guard try directoryIdentity(descriptor) == expected,
                              try directoryIdentity(parent) == parentExpected,
                              try directoryIdentity(at: url) == expected,
                              try directoryIdentity(parent: parent, name: leaf) == expected else {
                            throw EvidenceBundleStoreError.fileOperationFailed
                        }
                    }
                )
                guard Darwin.fsync(descriptor) == 0,
                      Darwin.fsync(parent) == 0 else {
                    throw EvidenceBundleStoreError.fileOperationFailed
                }
            }
        } catch {
            throw EvidenceBundleStoreError.fileOperationFailed
        }
    }

    private func writeProtectedFile(
        _ data: Data,
        to url: URL,
        policy: OwnedFileKindV1
    ) throws {
        let temporaryName = ".\(url.lastPathComponent).\(UUID().uuidString.lowercased()).tmp"
        let temporaryURL = url
            .deletingLastPathComponent()
            .appendingPathComponent(temporaryName, isDirectory: false)
        try withParentDescriptor(of: url) { parent, leaf in
            let descriptor = Darwin.openat(
                parent,
                temporaryName,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
                mode_t(0o600)
            )
            guard descriptor >= 0 else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            defer { _ = Darwin.close(descriptor) }
            let expected = try regularIdentity(descriptor)
            var published = false
            do {
                try applyLeafPolicy(
                    policy,
                    at: temporaryURL,
                    parent: parent,
                    name: temporaryName,
                    descriptor: descriptor,
                    expected: expected
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
                            throw EvidenceBundleStoreError.fileOperationFailed
                        }
                    }
                }
                guard Darwin.fsync(descriptor) == 0 else {
                    throw EvidenceBundleStoreError.fileOperationFailed
                }
                guard Darwin.renameatx_np(
                    parent,
                    temporaryName,
                    parent,
                    leaf,
                    UInt32(RENAME_EXCL)
                ) == 0 else {
                    throw EvidenceBundleStoreError.fileOperationFailed
                }
                published = true
                guard Darwin.fsync(parent) == 0 else {
                    throw EvidenceBundleStoreError.fileOperationFailed
                }
                try applyLeafPolicy(
                    policy,
                    at: url,
                    parent: parent,
                    name: leaf,
                    descriptor: descriptor,
                    expected: expected
                )
                guard Darwin.fsync(descriptor) == 0,
                      Darwin.fsync(parent) == 0 else {
                    throw EvidenceBundleStoreError.fileOperationFailed
                }
            } catch {
                let writeError = error
                do {
                    try quarantineRegularFileAndRemove(
                        parent: parent,
                        name: published ? leaf : temporaryName,
                        expectedIdentity: expected
                    )
                } catch {
                    throw EvidenceBundleStoreError.fileOperationFailed
                }
                throw writeError
            }
        }
    }

    private func writeProtectedStagingFile(
        _ data: Data,
        to url: URL
    ) throws {
        try writeProtectedFile(data, to: url, policy: .stagingFile)
    }

    private func writeProtectedImmutableFile(
        _ data: Data,
        to url: URL
    ) throws {
        try writeProtectedFile(data, to: url, policy: .mediaOriginal)
    }

    private func applyPromotedMediaPolicy(
        _ kind: OwnedFileKindV1,
        at url: URL
    ) throws {
        try withParentDescriptor(of: url) { parent, leaf in
            let descriptor = Darwin.openat(parent, leaf, O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            defer { _ = Darwin.close(descriptor) }
            let expected = try regularIdentity(descriptor)
            try applyLeafPolicy(
                kind,
                at: url,
                parent: parent,
                name: leaf,
                descriptor: descriptor,
                expected: expected
            )
            guard Darwin.fsync(descriptor) == 0,
                  Darwin.fsync(parent) == 0 else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
        }
    }

    private func verifyBundlePolicy(
        paths: BundlePaths,
        isStaging: Bool
    ) throws {
        try verifyOwnedPolicy(
            isStaging ? .stagingDirectory : .durableDirectory,
            at: isStaging ? paths.stagingDirectoryURL : paths.promotedDirectoryURL
        )
        try verifyOwnedPolicy(
            isStaging ? .stagingFile : .mediaOriginal,
            at: isStaging ? paths.stagingOriginalURL : paths.promotedOriginalURL
        )
        try verifyOwnedPolicy(
            isStaging ? .stagingFile : .mediaThumbnail,
            at: isStaging ? paths.stagingThumbnailURL : paths.promotedThumbnailURL
        )
    }

    private func verifyOwnedPolicy(
        _ kind: OwnedFileKindV1,
        at url: URL
    ) throws {
        do {
            try validateGenerationRoot()
            let disposition = ProtectedFilePolicyV1.disposition(for: kind)
            if disposition.expectsDirectory {
                try withOwnedDirectory(at: url) { descriptor in
                    let expected = try directoryIdentity(descriptor)
                    try ProtectedFilePolicyV1.verify(kind, at: url)
                    guard try directoryIdentity(descriptor) == expected,
                          try directoryIdentity(at: url) == expected else {
                        throw EvidenceBundleStoreError.fileOperationFailed
                    }
                }
            } else {
                try withParentDescriptor(of: url) { parent, leaf in
                    let descriptor = Darwin.openat(parent, leaf, O_RDONLY | O_NOFOLLOW)
                    guard descriptor >= 0 else {
                        throw EvidenceBundleStoreError.fileOperationFailed
                    }
                    defer { _ = Darwin.close(descriptor) }
                    let expected = try regularIdentity(descriptor)
                    let parentExpected = try directoryIdentity(parent)
                    try ProtectedFilePolicyV1.verify(kind, at: url)
                    guard try directoryIdentity(parent) == parentExpected,
                          try regularIdentity(descriptor) == expected,
                          try regularIdentity(parent: parent, name: leaf) == expected,
                          try regularIdentity(at: url) == expected else {
                        throw EvidenceBundleStoreError.fileOperationFailed
                    }
                }
            }
            try validateGenerationRoot()
        } catch let error as EvidenceBundleStoreError {
            throw error
        } catch {
            throw EvidenceBundleStoreError.fileOperationFailed
        }
    }

    private func applyLeafPolicy(
        _ kind: OwnedFileKindV1,
        at url: URL,
        parent: Int32,
        name: String,
        descriptor: Int32,
        expected: FileIdentity
    ) throws {
        let parentExpected = try directoryIdentity(parent)
        try ProtectedFilePolicyV1.applyAndVerify(kind, at: url) {
            try validateGenerationRoot()
            guard try directoryIdentity(parent) == parentExpected,
                  try regularIdentity(descriptor) == expected,
                  try regularIdentity(parent: parent, name: name) == expected,
                  try regularIdentity(at: url) == expected else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
        }
    }

    private func moveDirectoryNoReplace(
        from sourceURL: URL,
        to destinationURL: URL,
        didMove: inout Bool
    ) throws {
        try withParentDescriptor(of: sourceURL) { sourceParent, sourceLeaf in
            try withParentDescriptor(of: destinationURL) { destinationParent, destinationLeaf in
                let sourceParentExpected = try directoryIdentity(sourceParent)
                let destinationParentExpected = try directoryIdentity(destinationParent)
                let sourceExpected = try directoryIdentity(
                    parent: sourceParent,
                    name: sourceLeaf
                )
                guard try itemType(parent: destinationParent, name: destinationLeaf) == nil,
                      try directoryIdentity(sourceParent) == sourceParentExpected,
                      try directoryIdentity(destinationParent) == destinationParentExpected,
                      try directoryIdentity(parent: sourceParent, name: sourceLeaf)
                        == sourceExpected else {
                    throw EvidenceBundleStoreError.fileOperationFailed
                }
                guard Darwin.renameatx_np(
                    sourceParent,
                    sourceLeaf,
                    destinationParent,
                    destinationLeaf,
                    UInt32(RENAME_EXCL)
                ) == 0 else {
                    throw EvidenceBundleStoreError.fileOperationFailed
                }
                didMove = true
                guard Darwin.fsync(sourceParent) == 0,
                      Darwin.fsync(destinationParent) == 0 else {
                    throw EvidenceBundleStoreError.fileOperationFailed
                }
            }
        }
    }

    private func withDirectoryDescriptor<T>(
        relativeComponents: [String],
        _ body: (Int32) throws -> T
    ) throws -> T {
        guard relativeComponents.allSatisfy(validPathComponent) else {
            throw EvidenceBundleStoreError.unsafePath
        }
        return try withGenerationRootAuthority { authority in
            var descriptor = Darwin.dup(authority.generationDescriptor)
            guard descriptor >= 0 else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            defer { _ = Darwin.close(descriptor) }
            for component in relativeComponents {
                let next = Darwin.openat(
                    descriptor,
                    component,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                )
                guard next >= 0 else {
                    throw EvidenceBundleStoreError.fileOperationFailed
                }
                _ = Darwin.close(descriptor)
                descriptor = next
            }
            return try body(descriptor)
        }
    }

    private func withOptionalDirectoryDescriptor<T>(
        relativeComponents: [String],
        _ body: (Int32) throws -> T
    ) throws -> T? {
        guard relativeComponents.allSatisfy(validPathComponent) else {
            throw EvidenceBundleStoreError.unsafePath
        }
        return try withGenerationRootAuthority { authority in
            var descriptor = Darwin.dup(authority.generationDescriptor)
            guard descriptor >= 0 else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            defer { _ = Darwin.close(descriptor) }
            for component in relativeComponents {
                let next = Darwin.openat(
                    descriptor,
                    component,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                )
                if next < 0, errno == ENOENT {
                    return nil
                }
                guard next >= 0 else {
                    throw EvidenceBundleStoreError.fileOperationFailed
                }
                _ = Darwin.close(descriptor)
                descriptor = next
            }
            return try body(descriptor)
        }
    }

    private func withOwnedDirectory<T>(
        at url: URL,
        _ body: (Int32) throws -> T
    ) throws -> T {
        try withParentDescriptor(of: url) { parent, leaf in
            let descriptor = Darwin.openat(
                parent,
                leaf,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard descriptor >= 0 else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            defer { _ = Darwin.close(descriptor) }
            return try body(descriptor)
        }
    }

    private func directoryNames(_ descriptor: Int32) throws -> [String] {
        let duplicate = Darwin.dup(descriptor)
        guard duplicate >= 0, let directory = Darwin.fdopendir(duplicate) else {
            if duplicate >= 0 { _ = Darwin.close(duplicate) }
            throw EvidenceBundleStoreError.fileOperationFailed
        }
        defer { _ = Darwin.closedir(directory) }
        var names: [String] = []
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
            if name != "." && name != ".." {
                names.append(name)
            }
            errno = 0
        }
        guard errno == 0 else {
            throw EvidenceBundleStoreError.fileOperationFailed
        }
        return names.sorted()
    }

    private func readProtectedRegularFile(
        _ kind: OwnedFileKindV1,
        at url: URL,
        parent: Int32,
        name: String,
        maximumBytes: Int64? = nil
    ) throws -> Data {
        do {
            let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            defer { _ = Darwin.close(descriptor) }
            var before = stat()
            guard Darwin.fstat(descriptor, &before) == 0,
                   (before.st_mode & S_IFMT) == S_IFREG,
                   before.st_nlink == 1,
                   before.st_size >= 0,
                   maximumBytes.map({ before.st_size <= $0 }) ?? true else {
                throw EvidenceBundleStoreError.fileTypeInvalid
            }
            let expected = FileIdentity(device: before.st_dev, inode: before.st_ino)
            let parentExpected = try directoryIdentity(parent)
            try ProtectedFilePolicyV1.verify(kind, at: url)
            guard try directoryIdentity(parent) == parentExpected,
                  try regularIdentity(descriptor) == expected,
                  try regularIdentity(parent: parent, name: name) == expected,
                  try regularIdentity(at: url) == expected else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }

            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let count = buffer.withUnsafeMutableBytes { raw in
                    Darwin.read(descriptor, raw.baseAddress, raw.count)
                }
                if count > 0 {
                    data.append(contentsOf: buffer.prefix(count))
                } else if count == 0 {
                    break
                } else if errno != EINTR {
                    throw EvidenceBundleStoreError.fileOperationFailed
                }
            }
            var after = stat()
            guard Darwin.fstat(descriptor, &after) == 0,
                  (after.st_mode & S_IFMT) == S_IFREG,
                  after.st_nlink == 1,
                  FileIdentity(device: after.st_dev, inode: after.st_ino) == expected,
                  before.st_size == after.st_size,
                  data.count == Int(after.st_size) else {
                throw EvidenceBundleStoreError.bundleFactsMismatch
            }
            return data
        } catch let error as EvidenceBundleStoreError {
            throw error
        } catch {
            throw EvidenceBundleStoreError.fileOperationFailed
        }
    }

    /// Descriptor-pinned, fixed-buffer verification used before derivative
    /// rendering. It proves exact source bytes without allocating the source.
    private func verifyProtectedRegularFile(
        _ kind: OwnedFileKindV1,
        at url: URL,
        parent: Int32,
        name: String,
        expectedByteCount: Int64
    ) throws -> String {
        guard expectedByteCount >= 0,
              expectedByteCount <= EvidenceCurationLimitsV1.maximumSourceBytes else {
            throw EvidenceDerivativeServiceFailureV1.limitExceeded
        }
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw EvidenceBundleStoreError.fileOperationFailed }
        defer { _ = Darwin.close(descriptor) }
        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1,
              before.st_size == expectedByteCount else {
            throw EvidenceBundleStoreError.bundleFactsMismatch
        }
        let expectedIdentity = FileIdentity(device: before.st_dev, inode: before.st_ino)
        let parentIdentity = try directoryIdentity(parent)
        try ProtectedFilePolicyV1.verify(kind, at: url)
        var hasher = SHA256()
        var total: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while total < expectedByteCount {
            let requested = Int(min(Int64(buffer.count), expectedByteCount - total))
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, requested)
            }
            if count > 0 {
                hasher.update(data: Data(buffer.prefix(count)))
                total += Int64(count)
            } else if count == 0 {
                throw EvidenceBundleStoreError.bundleFactsMismatch
            } else if errno != EINTR {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
        }
        var trailing: UInt8 = 0
        guard Darwin.read(descriptor, &trailing, 1) == 0 else {
            throw EvidenceBundleStoreError.bundleFactsMismatch
        }
        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              after.st_size == before.st_size,
              try regularIdentity(descriptor) == expectedIdentity,
              try regularIdentity(parent: parent, name: name) == expectedIdentity,
              try regularIdentity(at: url) == expectedIdentity,
              try directoryIdentity(parent) == parentIdentity else {
            throw EvidenceBundleStoreError.bundleFactsMismatch
        }
        return Data(hasher.finalize()).map { String(format: "%02x", $0) }.joined()
    }

    private func withParentDescriptor<T>(
        of url: URL,
        _ body: (Int32, String) throws -> T
    ) throws -> T {
        let components = try relativeComponents(for: url)
        guard let leaf = components.last else {
            throw EvidenceBundleStoreError.unsafePath
        }
        return try withDirectoryDescriptor(
            relativeComponents: Array(components.dropLast())
        ) { descriptor in
            try body(descriptor, leaf)
        }
    }

    private func relativeComponents(for url: URL) throws -> [String] {
        let root = generationRootURL.standardizedFileURL
        let target = url.standardizedFileURL
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard target.path.hasPrefix(prefix) else {
            throw EvidenceBundleStoreError.unsafePath
        }
        let components = String(target.path.dropFirst(prefix.count))
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard !components.isEmpty,
              components.allSatisfy(validPathComponent) else {
            throw EvidenceBundleStoreError.unsafePath
        }
        return components
    }

    private func validPathComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".."
            && !value.contains("/") && !value.contains("\\")
    }

    private func directoryIdentity(at url: URL) throws -> FileIdentity {
        let descriptor = Darwin.open(
            url.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw EvidenceBundleStoreError.fileOperationFailed
        }
        defer { _ = Darwin.close(descriptor) }
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR else {
            throw EvidenceBundleStoreError.fileOperationFailed
        }
        return FileIdentity(device: info.st_dev, inode: info.st_ino)
    }

    private func directoryIdentity(_ descriptor: Int32) throws -> FileIdentity {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR else {
            throw EvidenceBundleStoreError.fileOperationFailed
        }
        return FileIdentity(device: info.st_dev, inode: info.st_ino)
    }

    private func directoryIdentity(parent: Int32, name: String) throws -> FileIdentity {
        let child = Darwin.openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard child >= 0 else {
            throw EvidenceBundleStoreError.fileOperationFailed
        }
        defer { _ = Darwin.close(child) }
        return try directoryIdentity(child)
    }

    private func regularIdentity(at url: URL) throws -> FileIdentity {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw EvidenceBundleStoreError.fileOperationFailed
        }
        defer { _ = Darwin.close(descriptor) }
        return try regularIdentity(descriptor)
    }

    private func regularIdentity(
        parent: Int32,
        name: String
    ) throws -> FileIdentity {
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw EvidenceBundleStoreError.fileOperationFailed
        }
        defer { _ = Darwin.close(descriptor) }
        return try regularIdentity(descriptor)
    }

    private func regularIdentity(_ descriptor: Int32) throws -> FileIdentity {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1 else {
            throw EvidenceBundleStoreError.fileOperationFailed
        }
        return FileIdentity(device: info.st_dev, inode: info.st_ino)
    }

    private func requireRegularNonsymlinkFile(_ url: URL) throws {
        guard try itemType(at: url) == .typeRegular else {
            throw EvidenceBundleStoreError.fileTypeInvalid
        }
    }

    private func itemType(at url: URL) throws -> FileAttributeType? {
        guard isInsideGeneration(url) else {
            throw EvidenceBundleStoreError.unsafePath
        }
        let target = url.standardizedFileURL
        if target.path == generationRootURL.path {
            return try withDirectoryDescriptor(relativeComponents: []) { _ in
                .typeDirectory
            }
        }
        let components = try relativeComponents(for: target)
        return try withOptionalDirectoryDescriptor(
            relativeComponents: Array(components.dropLast())
        ) { parent in
            try itemType(parent: parent, name: components[components.count - 1])
        } ?? nil
    }

    private func itemType(parent: Int32, name: String) throws -> FileAttributeType? {
        guard validPathComponent(name) else {
            throw EvidenceBundleStoreError.unsafePath
        }
        var info = stat()
        guard Darwin.fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT { return nil }
            throw EvidenceBundleStoreError.fileOperationFailed
        }
        return fileAttributeType(info.st_mode & S_IFMT)
    }

    private func fileAttributeType(_ mode: mode_t) -> FileAttributeType {
        switch mode {
        case S_IFDIR:
            return .typeDirectory
        case S_IFREG:
            return .typeRegular
        case S_IFLNK:
            return .typeSymbolicLink
        default:
            return .typeUnknown
        }
    }

    private func isInsideGeneration(_ url: URL) -> Bool {
        let root = generationRootURL.standardizedFileURL.path
        let candidate = url.standardizedFileURL.path
        return candidate == root || candidate.hasPrefix(root + "/")
    }

    private func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }

    private func removeExactStagingDirectoryIfPresent(_ url: URL) throws {
        guard let type = try itemType(at: url) else { return }
        guard type == .typeDirectory else {
            throw EvidenceBundleStoreError.bundleShapeInvalid
        }
        try removeDirectoryTree(at: url)
    }

    private func removeExactDirectoryIfPresent(_ url: URL) throws {
        guard let type = try itemType(at: url) else { return }
        guard type == .typeDirectory else {
            throw EvidenceBundleStoreError.bundleShapeInvalid
        }
        try removeDirectoryTree(at: url)
    }

    private func removeDirectoryTree(at url: URL) throws {
        try withParentDescriptor(of: url) { parent, leaf in
            let descriptor = Darwin.openat(
                parent,
                leaf,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard descriptor >= 0 else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            let expected = try directoryIdentity(descriptor)
            _ = Darwin.close(descriptor)
            try quarantineDirectoryAndRemove(
                parent: parent,
                name: leaf,
                expectedIdentity: expected
            )
        }
    }

    private func quarantineDirectoryAndRemove(
        parent: Int32,
        name: String,
        expectedIdentity: FileIdentity
    ) throws {
        let quarantine = ".remove-\(UUID().uuidString.lowercased()).directory"
        guard validPathComponent(quarantine),
              Darwin.renameatx_np(
                  parent,
                  name,
                  parent,
                  quarantine,
                  UInt32(RENAME_EXCL)
              ) == 0 else {
            throw EvidenceBundleStoreError.fileOperationFailed
        }

        var quarantineDescriptor: Int32 = -1
        var quarantinePresent = true
        do {
            guard Darwin.fsync(parent) == 0 else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            quarantineDescriptor = Darwin.openat(
                parent,
                quarantine,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard quarantineDescriptor >= 0 else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            guard try directoryIdentity(quarantineDescriptor) == expectedIdentity else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            try removeDirectoryContents(quarantineDescriptor)
            guard (try directoryNames(quarantineDescriptor)).isEmpty else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            _ = Darwin.close(quarantineDescriptor)
            quarantineDescriptor = -1
            guard Darwin.unlinkat(parent, quarantine, AT_REMOVEDIR) == 0 else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            quarantinePresent = false
            guard Darwin.fsync(parent) == 0 else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            var after = stat()
            guard Darwin.fstatat(
                parent,
                quarantine,
                &after,
                AT_SYMLINK_NOFOLLOW
            ) == -1, errno == ENOENT else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
        } catch {
            if quarantineDescriptor >= 0 {
                _ = Darwin.close(quarantineDescriptor)
            }
            if quarantinePresent {
                _ = restoreQuarantinedItem(
                    parent: parent,
                    quarantine: quarantine,
                    name: name,
                    expectedIdentity: expectedIdentity,
                    expectsDirectory: true
                )
            }
            throw error
        }
    }

    private func quarantineRegularFileAndRemove(
        parent: Int32,
        name: String,
        expectedIdentity: FileIdentity
    ) throws {
        let quarantine = ".remove-\(UUID().uuidString.lowercased()).file"
        guard validPathComponent(quarantine),
              Darwin.renameatx_np(
                  parent,
                  name,
                  parent,
                  quarantine,
                  UInt32(RENAME_EXCL)
              ) == 0 else {
            throw EvidenceBundleStoreError.fileOperationFailed
        }

        var quarantineDescriptor: Int32 = -1
        var quarantinePresent = true
        do {
            guard Darwin.fsync(parent) == 0 else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            quarantineDescriptor = Darwin.openat(
                parent,
                quarantine,
                O_RDONLY | O_NOFOLLOW
            )
            guard quarantineDescriptor >= 0 else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            guard try regularIdentity(quarantineDescriptor) == expectedIdentity else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            _ = Darwin.close(quarantineDescriptor)
            quarantineDescriptor = -1
            guard Darwin.unlinkat(parent, quarantine, 0) == 0 else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            quarantinePresent = false
            guard Darwin.fsync(parent) == 0 else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            var after = stat()
            guard Darwin.fstatat(
                parent,
                quarantine,
                &after,
                AT_SYMLINK_NOFOLLOW
            ) == -1, errno == ENOENT else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
        } catch {
            if quarantineDescriptor >= 0 {
                _ = Darwin.close(quarantineDescriptor)
            }
            if quarantinePresent {
                _ = restoreQuarantinedItem(
                    parent: parent,
                    quarantine: quarantine,
                    name: name,
                    expectedIdentity: expectedIdentity,
                    expectsDirectory: false
                )
            }
            throw error
        }
    }

    private func restoreQuarantinedItem(
        parent: Int32,
        quarantine: String,
        name: String,
        expectedIdentity: FileIdentity,
        expectsDirectory: Bool
    ) -> Bool {
        let flags = O_RDONLY | O_NOFOLLOW
            | (expectsDirectory ? O_DIRECTORY : 0)
        let descriptor = Darwin.openat(parent, quarantine, flags)
        guard descriptor >= 0 else { return false }
        let identity: FileIdentity?
        if expectsDirectory {
            identity = try? directoryIdentity(descriptor)
        } else {
            identity = try? regularIdentity(descriptor)
        }
        _ = Darwin.close(descriptor)
        guard identity == expectedIdentity,
              Darwin.renameatx_np(
                  parent,
                  quarantine,
                  parent,
                  name,
                  UInt32(RENAME_EXCL)
              ) == 0 else {
            return false
        }
        return Darwin.fsync(parent) == 0
    }

    private func removeDirectoryContents(_ directory: Int32) throws {
        for name in try directoryNames(directory) {
            var info = stat()
            guard Darwin.fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
            let mode = info.st_mode & S_IFMT
            if mode == S_IFDIR {
                let child = Darwin.openat(
                    directory,
                    name,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                )
                guard child >= 0 else {
                    throw EvidenceBundleStoreError.fileOperationFailed
                }
                let expected: FileIdentity
                do {
                    expected = try directoryIdentity(child)
                } catch {
                    _ = Darwin.close(child)
                    throw error
                }
                _ = Darwin.close(child)
                try quarantineDirectoryAndRemove(
                    parent: directory,
                    name: name,
                    expectedIdentity: expected
                )
            } else if mode == S_IFREG {
                guard info.st_nlink == 1 else {
                    throw EvidenceBundleStoreError.fileOperationFailed
                }
                let child = Darwin.openat(directory, name, O_RDONLY | O_NOFOLLOW)
                guard child >= 0 else {
                    throw EvidenceBundleStoreError.fileOperationFailed
                }
                let expected: FileIdentity
                do {
                    expected = try regularIdentity(child)
                } catch {
                    _ = Darwin.close(child)
                    throw error
                }
                _ = Darwin.close(child)
                try quarantineRegularFileAndRemove(
                    parent: directory,
                    name: name,
                    expectedIdentity: expected
                )
            } else {
                throw EvidenceBundleStoreError.fileOperationFailed
            }
        }
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}


// MARK: - C33 legacy JPEG bundle exclusion

/// EvidenceBundleStore retains its existing still-image compatibility role.
/// Temporal originals use DraftImmutableContentWriterV1 through the canonical
/// content root; they are never represented as original.jpg/thumbnail.jpg.
enum TemporalEvidenceLegacyBundleExclusionV1 {
    static let evidenceBundleStoreIsTemporalClipStore = false
    static let temporalClipUsesEvidenceFileIdentity = false
    static let canonicalWriter = "DraftImmutableContentWriterV1"
}

// MARK: - C36 draft/media boundary

/// The legacy media store remains the post-commit EvidenceID store.  C36
/// capture/import bytes must use DraftAttachmentStagingAdapterV1 until the
/// draft coordinator has obtained a canonical commit receipt.
enum DraftMediaPromotionBoundaryV1: Equatable, Sendable {
    case stagedWithoutEvidenceID(stageID: UUID, draftID: UUID)
    case committed(contentID: String, locatorID: String)

    var exposesEvidenceID: Bool {
        switch self {
        case .stagedWithoutEvidenceID: false
        case .committed: false
        }
    }

    var isCanonical: Bool {
        switch self {
        case .stagedWithoutEvidenceID: false
        case .committed: true
        }
    }
}

enum EvidenceBundleStoreC36GuardV1 {
    static let prePromotionRequiresNoEvidenceID = true
    static let stagingExcludedFromBackup = true
    static let stagingExcludedFromPortableExport = true

    static func validatePrePromotion(
        stageID: UUID,
        draftID: UUID,
        evidenceID: UUID? = nil
    ) throws {
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0,
                               0, 0, 0, 0, 0, 0, 0, 0))
        guard stageID != zero, draftID != zero, evidenceID == nil else {
            throw EvidenceBundleStoreError.bundleShapeInvalid
        }
    }
}

// MARK: - C24 accessible-document content boundary

extension EvidenceBundleStore {
    /// Accessible-document summaries never read or write the evidence bundle.
    /// This seam exists so callers can prove the audience/privacy boundary at
    /// the existing media owner without creating a second store.
    static func validateAccessibleDocumentProjection(
        _ tree: AccessibleDocumentSemanticTreeV1,
        assessment: AccessibleDocumentAssessmentReceiptV1? = nil
    ) throws {
        try AccessibleDocumentPrivacyTransformBoundaryV1
            .validateAudienceSafeProjection(tree, assessment: assessment)
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Infrastructure_Media_EvidenceBundleStore {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Infrastructure_Media_EvidenceBundleStore_swift {
    /// Typed C37 boundary: inherited owners may retain an immutable pose
    /// reference, but cannot infer pose, compliance, or current-state truth.
    static func validate(reference: AssetPoseEventReferenceV1,
                         in workspaceID: WorkspaceID) throws {
        try reference.validate()
        guard reference.workspaceID == workspaceID else {
            throw PlacementPoseFailureV1.wrongWorkspace
        }
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Infrastructure_Media_EvidenceBundleStore {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/Media/EvidenceBundleStore.swift", role: .media)
}

enum C31LightingEvidenceBundleBoundaryV1 {
    static let lightingRecordsReferenceExistingContent = true
    static let noSecondByteStore = true
    static let reportAndSearchConsumersReceiveMetadataOnly = true
    static let photoTimestampDoesNotEstablishLightingState = true

    static func validate(
        records: [V31BackupLightingRecordV1],
        workspaceID: WorkspaceID
    ) throws {
        try C31LightingWorkflowBoundaryV1.validate(
            records: records,
            workspaceID: workspaceID
        )
        guard lightingRecordsReferenceExistingContent,
              noSecondByteStore,
              reportAndSearchConsumersReceiveMetadataOnly,
              photoTimestampDoesNotEstablishLightingState else {
            throw LightingContractFailureV1.invalidValue
        }
    }
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Media_EvidenceBundleStore {
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

/// C45 legacy evidence files never become label artifact identity.
enum C45AssetLabelBoundary_EvidenceBundleStoreV1 {
    static func validate(_ plan: AssetLabelGenerationPlanV1) throws { try plan.validate() }
    static let legacyEvidenceFileIsLabelIdentity = false
}
enum C46OperationalContactConformance_FieldEvidenceApp_Infrastructure_Media_EvidenceBundleStore_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noContactProjectionOrNetworkDelivery = true
}

// MARK: - C48 portable-review evidence boundary

enum C48PortableReviewEvidenceBundleBoundaryV1 {
    static let portableReviewResponseBytesRemainExchangeOwned = true
    static let capabilityBytesBecomeEvidence = false
    static let capabilityProofBytesBecomeEvidence = false
    static let rawRequestResponseBytesBecomeEvidence = false
    static let derivedHistoryMayReferenceExistingEvidenceOnly = true
    static let createsSecondByteStore = false

    static func validateDerivedHistory(
        _ projection: C48PortableReviewDerivedHistoryProjectionV1
    ) throws {
        try projection.validate()
    }
}

// MARK: - C49 work-resource evidence boundary

/// EvidenceBundleStore remains a byte authority for immutable content. C49
/// work-resource records and direct costs are metadata-only canonical rows;
/// private cost values never become customer-safe evidence by default.
enum C49WorkResourceEvidenceBundleBoundaryV1 {
    static let canonicalRecordType = "WorkResourceEntryV1"
    static let directCostType = "DirectCostEntryV1"
    static let localPartReferenceType = "LocalPartReferenceSnapshotV1"
    static let usesExistingEvidenceByteAuthority = true
    static let directCostDefaultVisibility = "INTERNAL_ONLY"
    static let customerSafeCostRequiresExplicitPreview = true
    static let localPartReferenceIsSnapshotOnly = true
    static let liveInventoryLookup = false
    static let createsSecondByteStore = false
    static let formulaFieldsAreRejected = true
}

/// C50 file exchange input and quarantine are leased scratch.  The evidence
/// byte authority remains the existing store after a separate canonical
/// acceptance; no source file or external output is silently made evidence.
enum C50IncumbentFileExchangeBundleBoundaryV1 {
    static let sourceScratchIsNotEvidence = true
    static let quarantineScratchIsNotEvidence = true
    static let acceptedCanonicalContentUsesExistingEvidenceAuthority = true
    static let diagnosticsAndReportsReceiveNoRawExchangeBytes = true
    static let externalOutputAvailabilityIsNotEvidenceTruth = true
    static let directCostAndPrivateFieldsRemainExcludedByDefault = true

    static func validate() -> Bool {
        sourceScratchIsNotEvidence
            && quarantineScratchIsNotEvidence
            && acceptedCanonicalContentUsesExistingEvidenceAuthority
            && diagnosticsAndReportsReceiveNoRawExchangeBytes
            && externalOutputAvailabilityIsNotEvidenceTruth
            && directCostAndPrivateFieldsRemainExcludedByDefault
    }
}

enum C34SceneRestorationMediaWriterBoundaryV1 {
    static let writesEvidenceBytes = false
    static let promotesMedia = false
    static let ownsSceneState = false
    static func validate(anchor: DraftResumeAnchorV1) -> Bool { !writesEvidenceBytes && !promotesMedia && !ownsSceneState && C34DraftResumeNavigationBoundaryV1.validate(anchor: anchor) }
}

// MARK: - C52 lifecycle and privacy boundary
enum C52ServiceRequestBoundary_FieldEvidenceApp_Infrastructure_Media_EvidenceBundleStore_swift {
    static let acceptedCanonicalRecordPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let acceptedEventPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let duplicateProjectionPersistence: ServiceRequestPersistenceClassV1 = .nonpersistentDerived
    static let rawCapabilityPersistence: ServiceRequestPersistenceClassV1 = .prohibitedPersistent
    static let acceptedLifecycleEnrollment: ServiceRequestPersistenceEnrollmentV1.Type = ServiceRequestPersistenceEnrollmentV1.self
    static let cloneOrForkInvalidatesActiveCapabilities: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.cloneOrForkInvalidatesOutstandingCapabilities
    static let duplicateProjectionIsRebuildable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.derivedProjectionIsRebuildable &&
        !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityIsExcludedFromReportsAndDiagnostics: Bool =
        !ServiceRequestLifecycleRegistrationBoundaryV1.rawCapabilityAppearsInReportsOrDiagnostics
    static let sharedPortableFilesAreRecallable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.escapedPortableFilesCanBeRecalled
    static let unverifiedAssertionsAreVerified: Bool = false
    static let automaticWorkNetworkSLAOrAIClaimsPermitted: Bool = false
}

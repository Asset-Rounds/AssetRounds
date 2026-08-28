import Darwin
import Foundation

enum OwnedStorageRootKindV1: String, CaseIterable, Hashable, Sendable {
    case data = "FieldEvidenceData"
    case restore = "FieldEvidenceRestore"
    case operations = "FieldEvidenceOperations"
    case erase = "FieldEvidenceErase"
    case diagnostics = "FieldEvidenceDiagnostics"
    case commerce = "FieldEvidenceCommerce"
    case localJobs = "local-jobs-v1"
}

struct OwnedStorageRootV1: Equatable, Sendable {
    let kind: OwnedStorageRootKindV1
    let url: URL

    init(kind: OwnedStorageRootKindV1, url: URL) throws {
        guard url.isFileURL,
              url.standardizedFileURL.lastPathComponent == kind.rawValue else {
            throw OwnedStorageLedgerFailureV1.invalidRoot
        }
        self.kind = kind
        self.url = url.standardizedFileURL
    }

    static func closedSet(
        applicationSupportURL: URL
    ) throws -> [OwnedStorageRootV1] {
        guard applicationSupportURL.isFileURL else {
            throw OwnedStorageLedgerFailureV1.invalidRoot
        }
        let parent = applicationSupportURL.standardizedFileURL
        return try OwnedStorageRootKindV1.allCases.map { kind in
            try OwnedStorageRootV1(
                kind: kind,
                url: parent.appendingPathComponent(
                    kind.rawValue,
                    isDirectory: true
                )
            )
        }
    }
}

struct OwnedStorageSnapshotV1: Equatable, Sendable {
    let volumeIdentity: OwnedStorageVolumeIdentityV1
    let ownedByteCount: Int64
    let reservedByteCount: Int64
    let activeReservationCount: Int
    let scannedEntryCount: Int
}

enum OwnedStorageLedgerFailureV1: Error, Equatable, Sendable {
    case invalidRoot
    case duplicateRoot
    case volumeMismatch
    case accountingOverflow
    case entryLimitExceeded
    case reservationLimitExceeded
    case depthLimitExceeded
    case unsupportedEntry
    case capacityUnavailable
    case insufficientCapacity(requiredBytes: Int64, availableBytes: Int64)
    case attemptCollision
}

/// Process-local admission ledger. Reservations are never canonical or backed
/// up; relaunch reconstructs owned bytes and adopts only explicitly supplied
/// active attempts. Storage pressure never authorizes deletion.
/// `@unchecked Sendable` is confined to this type because `NSLock` is not
/// Sendable; every mutable field is accessed only while that lock is held.
final class OwnedStorageLedgerV1: WorkspaceStorageAdmissionPortV1, @unchecked Sendable {
    typealias CapacityProvider = @Sendable (URL) throws -> Int64?

    static let maximumScannedEntryCount = 100_000
    static let maximumDirectoryDepth = 64
    static let maximumActiveReservationCount = 10_000

    private let roots: [OwnedStorageRootV1]
    private let capacityURL: URL
    private let capacityProvider: CapacityProvider
    private let storagePreflight: StoragePreflightService
    private let lock = NSLock()

    private var volumeIdentity: OwnedStorageVolumeIdentityV1
    private var capacityRootInode: UInt64
    private var ownedByteCount: Int64
    private var scannedEntryCount: Int
    private var reservations: [OwnedStorageAttemptIDV1: OwnedStorageReservationV1]

    init(
        rootURLs: [OwnedStorageRootV1],
        capacityProvider: @escaping CapacityProvider = { url in
            try url.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            ).volumeAvailableCapacityForImportantUsage
        }
    ) throws {
        let requiredKinds = Set(OwnedStorageRootKindV1.allCases)
        let suppliedKinds = Set(rootURLs.map(\.kind))
        guard suppliedKinds.count == rootURLs.count,
              Set(rootURLs.map { $0.url.path }).count == rootURLs.count else {
            throw OwnedStorageLedgerFailureV1.duplicateRoot
        }
        guard rootURLs.count == requiredKinds.count,
              suppliedKinds == requiredKinds else {
            throw OwnedStorageLedgerFailureV1.invalidRoot
        }
        let ordered = rootURLs.sorted { $0.kind.rawValue < $1.kind.rawValue }
        let parent = ordered[0].url.deletingLastPathComponent()
        guard ordered.allSatisfy({ $0.url.deletingLastPathComponent() == parent }) else {
            throw OwnedStorageLedgerFailureV1.invalidRoot
        }
        roots = ordered
        capacityURL = parent
        self.capacityProvider = capacityProvider
        storagePreflight = StoragePreflightService(capacityProvider: capacityProvider)
        let rootIdentity = try Self.rootIdentity(at: parent)
        volumeIdentity = rootIdentity.volume
        capacityRootInode = rootIdentity.inode
        ownedByteCount = 0
        scannedEntryCount = 0
        reservations = [:]
        _ = try reconcile(activeReservations: [])
    }

    convenience init(
        applicationSupportURL: URL,
        capacityProvider: @escaping CapacityProvider = { url in
            try url.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            ).volumeAvailableCapacityForImportantUsage
        }
    ) throws {
        try self.init(
            rootURLs: OwnedStorageRootV1.closedSet(
                applicationSupportURL: applicationSupportURL
            ),
            capacityProvider: capacityProvider
        )
    }

    func snapshot() -> OwnedStorageSnapshotV1 {
        lock.withLock { makeSnapshot() }
    }

    func reserve(
        attemptID: OwnedStorageAttemptIDV1,
        requiredBytes: Int64
    ) throws -> OwnedStorageReservationV1 {
        guard requiredBytes >= 0 else {
            throw OwnedStorageLedgerFailureV1.accountingOverflow
        }
        let beforeCapacity = try Self.rootIdentity(at: capacityURL)
        if let existing = try lock.withLock({
            guard beforeCapacity.volume == volumeIdentity,
                  beforeCapacity.inode == capacityRootInode else {
                throw OwnedStorageLedgerFailureV1.volumeMismatch
            }
            if let existing = reservations[attemptID] {
                guard existing.requiredBytes == requiredBytes,
                      existing.volumeIdentity == volumeIdentity else {
                    throw OwnedStorageLedgerFailureV1.attemptCollision
                }
                return existing
            }
            return nil
        }) {
            return existing
        }

        let available: Int64
        do {
            guard let capacity = try capacityProvider(capacityURL) else {
                throw OwnedStorageLedgerFailureV1.capacityUnavailable
            }
            available = capacity
        } catch let failure as OwnedStorageLedgerFailureV1 {
            throw failure
        } catch {
            throw OwnedStorageLedgerFailureV1.capacityUnavailable
        }
        let afterCapacity = try Self.rootIdentity(at: capacityURL)
        guard afterCapacity == beforeCapacity else {
            throw OwnedStorageLedgerFailureV1.volumeMismatch
        }

        return try lock.withLock {
            guard beforeCapacity.volume == volumeIdentity,
                  beforeCapacity.inode == capacityRootInode else {
                throw OwnedStorageLedgerFailureV1.volumeMismatch
            }
            // A concurrent caller may have installed this attempt while the
            // external capacity provider was running. Re-check so an exact
            // retry remains idempotent and a collision remains fail-closed.
            if let existing = reservations[attemptID] {
                guard existing.requiredBytes == requiredBytes,
                      existing.volumeIdentity == volumeIdentity else {
                    throw OwnedStorageLedgerFailureV1.attemptCollision
                }
                return existing
            }
            guard reservations.count < Self.maximumActiveReservationCount else {
                throw OwnedStorageLedgerFailureV1.reservationLimitExceeded
            }
            let reserved = try Self.sum(reservations.values.map(\.requiredBytes))
            let required: Int64
            do {
                required = try storagePreflight.storageAdmissionRequiredBytes(
                    requestedBytes: requiredBytes,
                    alreadyReservedBytes: reserved
                )
            } catch StoragePreflightError.capacityEstimateOverflow {
                throw OwnedStorageLedgerFailureV1.accountingOverflow
            } catch {
                throw OwnedStorageLedgerFailureV1.accountingOverflow
            }
            guard available >= required else {
                throw OwnedStorageLedgerFailureV1.insufficientCapacity(
                    requiredBytes: required,
                    availableBytes: available
                )
            }
            let reservation = OwnedStorageReservationV1(
                attemptID: attemptID,
                requiredBytes: requiredBytes,
                volumeIdentity: volumeIdentity
            )
            reservations[attemptID] = reservation
            return reservation
        }
    }

    func release(reservation: OwnedStorageReservationV1) {
        lock.withLock {
            guard reservations[reservation.attemptID] == reservation else { return }
            reservations.removeValue(forKey: reservation.attemptID)
        }
    }

    @discardableResult
    func reconcile(
        activeReservations: [OwnedStorageReservationV1]
    ) throws -> OwnedStorageSnapshotV1 {
        // Reconciliation is a single bounded, linearizable ledger operation.
        // Holding the lock across its descriptor-safe scan prevents a reserve
        // or release from being overwritten by the authoritative adoption.
        try lock.withLock {
            let scan = try Self.scan(roots: roots)
            let rootIdentity = try Self.rootIdentity(at: capacityURL)
            guard scan.volumeIdentity == rootIdentity.volume,
                  scan.capacityRootInode == rootIdentity.inode else {
                throw OwnedStorageLedgerFailureV1.volumeMismatch
            }
            guard activeReservations.count <= Self.maximumActiveReservationCount else {
                throw OwnedStorageLedgerFailureV1.reservationLimitExceeded
            }
            var adopted: [OwnedStorageAttemptIDV1: OwnedStorageReservationV1] = [:]
            for reservation in activeReservations {
                guard reservation.requiredBytes >= 0,
                      reservation.volumeIdentity == rootIdentity.volume else {
                    throw OwnedStorageLedgerFailureV1.volumeMismatch
                }
                if let prior = adopted[reservation.attemptID], prior != reservation {
                    throw OwnedStorageLedgerFailureV1.attemptCollision
                }
                adopted[reservation.attemptID] = reservation
            }
            _ = try Self.sum(adopted.values.map(\.requiredBytes))
            volumeIdentity = rootIdentity.volume
            capacityRootInode = rootIdentity.inode
            ownedByteCount = scan.byteCount
            scannedEntryCount = scan.entryCount
            reservations = adopted
            return makeSnapshot()
        }
    }

    private func makeSnapshot() -> OwnedStorageSnapshotV1 {
        let reserved = (try? Self.sum(reservations.values.map(\.requiredBytes))) ?? .max
        return OwnedStorageSnapshotV1(
            volumeIdentity: volumeIdentity,
            ownedByteCount: ownedByteCount,
            reservedByteCount: reserved,
            activeReservationCount: reservations.count,
            scannedEntryCount: scannedEntryCount
        )
    }
}

private extension OwnedStorageLedgerV1 {
    struct ScanResult {
        let volumeIdentity: OwnedStorageVolumeIdentityV1
        let capacityRootInode: UInt64
        let byteCount: Int64
        let entryCount: Int
    }

    static func scan(roots: [OwnedStorageRootV1]) throws -> ScanResult {
        let parentURL = roots[0].url.deletingLastPathComponent()
        let parent = Darwin.open(parentURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parent >= 0 else { throw OwnedStorageLedgerFailureV1.invalidRoot }
        defer { _ = Darwin.close(parent) }
        var parentInfo = stat()
        guard Darwin.fstat(parent, &parentInfo) == 0,
              (parentInfo.st_mode & S_IFMT) == S_IFDIR else {
            throw OwnedStorageLedgerFailureV1.invalidRoot
        }
        let volume = OwnedStorageVolumeIdentityV1(device: UInt64(parentInfo.st_dev))
        var byteCount: Int64 = 0
        var entryCount = 0
        for root in roots {
            var info = stat()
            if Darwin.fstatat(parent, root.url.lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) != 0 {
                if errno == ENOENT { continue }
                throw OwnedStorageLedgerFailureV1.invalidRoot
            }
            guard (info.st_mode & S_IFMT) == S_IFDIR,
                  UInt64(info.st_dev) == volume.device else {
                throw OwnedStorageLedgerFailureV1.volumeMismatch
            }
            let descriptor = Darwin.openat(
                parent,
                root.url.lastPathComponent,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard descriptor >= 0 else { throw OwnedStorageLedgerFailureV1.invalidRoot }
            do {
                defer { _ = Darwin.close(descriptor) }
                var opened = stat()
                guard Darwin.fstat(descriptor, &opened) == 0,
                      (opened.st_mode & S_IFMT) == S_IFDIR,
                      opened.st_dev == info.st_dev,
                      opened.st_ino == info.st_ino else {
                    throw OwnedStorageLedgerFailureV1.unsupportedEntry
                }
                try scanDirectory(
                    descriptor,
                    depth: 0,
                    volume: volume,
                    byteCount: &byteCount,
                    entryCount: &entryCount
                )
            }
        }
        return ScanResult(
            volumeIdentity: volume,
            capacityRootInode: UInt64(parentInfo.st_ino),
            byteCount: byteCount,
            entryCount: entryCount
        )
    }

    static func scanDirectory(
        _ descriptor: Int32,
        depth: Int,
        volume: OwnedStorageVolumeIdentityV1,
        byteCount: inout Int64,
        entryCount: inout Int
    ) throws {
        guard depth <= maximumDirectoryDepth else {
            throw OwnedStorageLedgerFailureV1.depthLimitExceeded
        }
        let duplicate = Darwin.dup(descriptor)
        guard duplicate >= 0, let directory = Darwin.fdopendir(duplicate) else {
            if duplicate >= 0 { _ = Darwin.close(duplicate) }
            throw OwnedStorageLedgerFailureV1.invalidRoot
        }
        defer { _ = Darwin.closedir(directory) }
        errno = 0
        while let entry = Darwin.readdir(directory) {
            var tuple = entry.pointee.d_name
            let capacity = MemoryLayout.size(ofValue: tuple)
            let name = withUnsafePointer(to: &tuple) {
                $0.withMemoryRebound(to: CChar.self, capacity: capacity) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            entryCount += 1
            guard entryCount <= maximumScannedEntryCount else {
                throw OwnedStorageLedgerFailureV1.entryLimitExceeded
            }
            var info = stat()
            guard Darwin.fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0,
                  UInt64(info.st_dev) == volume.device else {
                throw OwnedStorageLedgerFailureV1.invalidRoot
            }
            switch info.st_mode & S_IFMT {
            case S_IFREG:
                let file = Darwin.openat(descriptor, name, O_RDONLY | O_NOFOLLOW)
                guard file >= 0 else { throw OwnedStorageLedgerFailureV1.invalidRoot }
                do {
                    defer { _ = Darwin.close(file) }
                    var pinned = stat()
                    guard Darwin.fstat(file, &pinned) == 0,
                          (pinned.st_mode & S_IFMT) == S_IFREG,
                          pinned.st_nlink == 1,
                          pinned.st_size >= 0,
                          pinned.st_dev == info.st_dev,
                          pinned.st_ino == info.st_ino else {
                        throw OwnedStorageLedgerFailureV1.unsupportedEntry
                    }
                    var after = stat()
                    guard Darwin.fstatat(
                        descriptor,
                        name,
                        &after,
                        AT_SYMLINK_NOFOLLOW
                    ) == 0,
                          after.st_dev == pinned.st_dev,
                          after.st_ino == pinned.st_ino,
                          after.st_size == pinned.st_size,
                          after.st_nlink == pinned.st_nlink else {
                        throw OwnedStorageLedgerFailureV1.unsupportedEntry
                    }
                    byteCount = try add(byteCount, Int64(pinned.st_size))
                }
            case S_IFDIR:
                let child = Darwin.openat(
                    descriptor,
                    name,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                )
                guard child >= 0 else { throw OwnedStorageLedgerFailureV1.invalidRoot }
                do {
                    defer { _ = Darwin.close(child) }
                    var opened = stat()
                    guard Darwin.fstat(child, &opened) == 0,
                          (opened.st_mode & S_IFMT) == S_IFDIR,
                          opened.st_dev == info.st_dev,
                          opened.st_ino == info.st_ino else {
                        throw OwnedStorageLedgerFailureV1.unsupportedEntry
                    }
                    try scanDirectory(
                        child,
                        depth: depth + 1,
                        volume: volume,
                        byteCount: &byteCount,
                        entryCount: &entryCount
                    )
                }
            default:
                throw OwnedStorageLedgerFailureV1.unsupportedEntry
            }
        }
        guard errno == 0 else { throw OwnedStorageLedgerFailureV1.invalidRoot }
    }

    struct RootIdentity: Equatable {
        let volume: OwnedStorageVolumeIdentityV1
        let inode: UInt64
    }

    static func rootIdentity(at url: URL) throws -> RootIdentity {
        var info = stat()
        guard Darwin.lstat(url.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR else {
            throw OwnedStorageLedgerFailureV1.invalidRoot
        }
        return RootIdentity(
            volume: OwnedStorageVolumeIdentityV1(device: UInt64(info.st_dev)),
            inode: UInt64(info.st_ino)
        )
    }

    static func add(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow, value >= 0 else {
            throw OwnedStorageLedgerFailureV1.accountingOverflow
        }
        return value
    }

    static func sum<S: Sequence>(_ values: S) throws -> Int64 where S.Element == Int64 {
        try values.reduce(0) { partial, value in
            try add(partial, value)
        }
    }
}

// MARK: - C36 draft attachment admission

enum DraftStorageReservationPurposeV1: String, Codable, CaseIterable, Hashable, Sendable {
    case attachmentScratch = "ATTACHMENT_SCRATCH"
    case attachmentStaging = "ATTACHMENT_STAGING"
    case contentPromotion = "CONTENT_PROMOTION"
}

struct DraftStorageReservationRequestV1: Codable, Equatable, Sendable {
    let purpose: DraftStorageReservationPurposeV1
    let workspaceID: WorkspaceID
    let draftID: UUID
    let stageID: UUID
    let mutationID: MutationIDV1
    let byteCount: Int64

    init(
        purpose: DraftStorageReservationPurposeV1,
        workspaceID: WorkspaceID,
        draftID: UUID,
        stageID: UUID,
        mutationID: MutationIDV1,
        byteCount: Int64
    ) throws {
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0,
                               0, 0, 0, 0, 0, 0, 0, 0))
        guard workspaceID.rawValue != zero, draftID != zero, stageID != zero,
              byteCount > 0 else {
            throw OwnedStorageLedgerFailureV1.accountingOverflow
        }
        self.purpose = purpose
        self.workspaceID = workspaceID
        self.draftID = draftID
        self.stageID = stageID
        self.mutationID = mutationID
        self.byteCount = byteCount
    }
}

struct DraftStorageReservationV1: Equatable, Sendable {
    let request: DraftStorageReservationRequestV1
    let reservation: OwnedStorageReservationV1
}

extension OwnedStorageLedgerV1 {
    /// Reserves bytes for one draft/stage attempt.  The attempt identity is
    /// deterministic and therefore an idempotent retry adopts the existing
    /// reservation instead of double-counting capacity.
    func reserveDraftAttachment(
        _ request: DraftStorageReservationRequestV1
    ) throws -> DraftStorageReservationV1 {
        let attemptID = try OwnedStorageAttemptIDV1(
            workspaceID: request.workspaceID,
            generationID: request.stageID,
            mutationID: request.mutationID
        )
        return DraftStorageReservationV1(
            request: request,
            reservation: try reserve(
                attemptID: attemptID,
                requiredBytes: request.byteCount
            )
        )
    }

    func releaseDraftAttachment(_ reservation: DraftStorageReservationV1) {
        release(reservation: reservation.reservation)
    }

    static let c36StagingExcludedFromBackup = true
    static let c36PressureNeverAuthorizesDeletion = true
}

enum ScratchDataLeaseStoreFailureV1: Error, Equatable, Sendable {
    case invalidRoot
    case invalidLease
    case leaseCollision
    case leaseExpired
    case sizeLimitExceeded
    case protectedDataUnavailable
    case insufficientCapacity
}

private final class PinnedScratchRootV1: @unchecked Sendable {
    let operationsDescriptor: Int32
    let rootDescriptor: Int32
    let operationsDevice: UInt64
    let operationsInode: UInt64
    let rootDevice: UInt64
    let rootInode: UInt64

    init(operationsURL: URL, rootName: String) throws {
        operationsDescriptor = Darwin.open(
            operationsURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard operationsDescriptor >= 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        var operations = stat()
        guard Darwin.fstat(operationsDescriptor, &operations) == 0,
              (operations.st_mode & S_IFMT) == S_IFDIR else {
            _ = Darwin.close(operationsDescriptor)
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        operationsDevice = UInt64(operations.st_dev)
        operationsInode = UInt64(operations.st_ino)
        rootDescriptor = Darwin.openat(
            operationsDescriptor,
            rootName,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard rootDescriptor >= 0 else {
            _ = Darwin.close(operationsDescriptor)
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        var root = stat()
        guard Darwin.fstat(rootDescriptor, &root) == 0,
              (root.st_mode & S_IFMT) == S_IFDIR,
              root.st_dev == operations.st_dev else {
            _ = Darwin.close(rootDescriptor)
            _ = Darwin.close(operationsDescriptor)
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        rootDevice = UInt64(root.st_dev)
        rootInode = UInt64(root.st_ino)
    }

    deinit {
        _ = Darwin.close(rootDescriptor)
        _ = Darwin.close(operationsDescriptor)
    }

    func verify(rootName: String) throws {
        var operations = stat()
        var root = stat()
        var child = stat()
        guard Darwin.fstat(operationsDescriptor, &operations) == 0,
              UInt64(operations.st_dev) == operationsDevice,
              UInt64(operations.st_ino) == operationsInode,
              Darwin.fstat(rootDescriptor, &root) == 0,
              UInt64(root.st_dev) == rootDevice,
              UInt64(root.st_ino) == rootInode,
              Darwin.fstatat(
                operationsDescriptor,
                rootName,
                &child,
                AT_SYMLINK_NOFOLLOW
              ) == 0,
              UInt64(child.st_dev) == rootDevice,
              UInt64(child.st_ino) == rootInode else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
    }
}

/// Sole process adapter for the shared, noncanonical scratch root. Every byte
/// remains under `FieldEvidenceOperations`, so the closed owned-storage ledger
/// accounts for it while purpose-separated leases prevent support export from
/// reading capture/import/source scratch.
actor ScratchDataLeaseStoreV1: ScratchDataLeasePortV1 {
    typealias Clock = @Sendable () -> Date

    private static let rootName = "ScratchDataV1"
    private static let metadataName = "lease.json"
    private static let deletionPrefix = ".deleting-"

    private let rootURL: URL
    private let clock: Clock
    private let storagePreflight: StoragePreflightService
    private let authority: PinnedScratchRootV1
    private var active: [UUID: ScratchDataLeaseV1] = [:]

    init(
        applicationSupportURL: URL,
        fileManager: FileManager = .default,
        clock: @escaping Clock,
        capacityProvider: @escaping StoragePreflightService.CapacityProvider = {
            try $0.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            ).volumeAvailableCapacityForImportantUsage
        }
    ) throws {
        let operations = applicationSupportURL.standardizedFileURL
            .appendingPathComponent(
                OwnedStorageRootKindV1.operations.rawValue,
                isDirectory: true
            )
        rootURL = operations.appendingPathComponent(Self.rootName, isDirectory: true)
        _ = fileManager // Source-compatible injection; descriptor I/O is authoritative.
        self.clock = clock
        storagePreflight = StoragePreflightService(capacityProvider: capacityProvider)
        try Self.prepareRoot(rootURL)
        authority = try PinnedScratchRootV1(
            operationsURL: operations,
            rootName: Self.rootName
        )
        try ProtectedFilePolicyV1.applyAndVerify(
            .stagingDirectory,
            at: rootURL,
            authorityCheck: {
                try authority.verify(rootName: Self.rootName)
            }
        )
    }

    func acquireScratchLease(
        _ request: ScratchDataLeaseRequestV1
    ) async throws -> ScratchDataLeaseV1 {
        try request.validate()
        let current = clock()
        guard request.createdAt <= current, current < request.expiresAt else {
            throw ScratchDataLeaseStoreFailureV1.invalidLease
        }
        _ = try recoverScratchLeaseState()
        if let existing = active[request.leaseID] {
            guard existing.request == request else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            return existing
        }
        do {
            try storagePreflight.checkScratchLease(
                requestedByteCount: request.requestedByteCount,
                onVolumeContaining: rootURL
            )
        } catch StoragePreflightError.insufficientCapacity {
            throw ScratchDataLeaseStoreFailureV1.insufficientCapacity
        } catch StoragePreflightError.capacityUnavailable {
            throw ScratchDataLeaseStoreFailureV1.insufficientCapacity
        } catch {
            throw ScratchDataLeaseStoreFailureV1.invalidLease
        }
        let name = Self.leaseDirectoryName(for: request)
        let lease = try ScratchDataLeaseV1(
            request: request,
            relativeDirectory: name
        )
        let directory = rootURL.appendingPathComponent(name, isDirectory: true)
        var createdDirectory = false
        do {
            try verifyRoot()
            guard Darwin.mkdirat(authority.rootDescriptor, name, 0o700) == 0 else {
                if errno == EEXIST {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            createdDirectory = true
            let leaseDescriptor = try openLeaseDirectory(name)
            defer { _ = Darwin.close(leaseDescriptor) }
            try ProtectedFilePolicyV1.applyAndVerify(
                .stagingDirectory,
                at: directory,
                authorityCheck: {
                    try verifyLeaseDirectory(name, descriptor: leaseDescriptor)
                }
            )
            let metadata = try canonicalData(lease)
            let metadataURL = directory.appendingPathComponent(Self.metadataName)
            try publishDurably(
                metadata,
                named: Self.metadataName,
                directoryDescriptor: leaseDescriptor,
                directoryURL: directory,
                finalURL: metadataURL,
                leaseName: name
            )
            active[request.leaseID] = lease
            return lease
        } catch let failure as ProtectedFilePolicyError
            where failure == .protectedDataUnavailable {
            if createdDirectory { try? removeLeaseDirectory(named: name) }
            throw ScratchDataLeaseStoreFailureV1.protectedDataUnavailable
        } catch let failure as ScratchDataLeaseStoreFailureV1 {
            if createdDirectory { try? removeLeaseDirectory(named: name) }
            throw failure
        } catch {
            if createdDirectory { try? removeLeaseDirectory(named: name) }
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
    }

    func writeScratchData(
        _ data: Data,
        named: String,
        lease: ScratchDataLeaseV1
    ) async throws -> URL {
        guard OperationalDiagnosticsBoundsV1.validRelativeName(named),
              named != Self.metadataName,
              active[lease.request.leaseID] == lease else {
            throw ScratchDataLeaseStoreFailureV1.invalidLease
        }
        guard clock() < lease.request.expiresAt else {
            try await releaseScratchLease(lease, terminal: .recoveredExpired)
            throw ScratchDataLeaseStoreFailureV1.leaseExpired
        }
        let directory = rootURL.appendingPathComponent(
            lease.relativeDirectory,
            isDirectory: true
        )
        let leaseDescriptor = try openLeaseDirectory(lease.relativeDirectory)
        defer { _ = Darwin.close(leaseDescriptor) }
        let destination = directory.appendingPathComponent(named, isDirectory: false)
        let currentBytes = try payloadByteCount(
            directoryDescriptor: leaseDescriptor,
            directoryURL: directory
        )
        guard currentBytes <= lease.request.requestedByteCount else {
            throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
        }
        do {
            if try adoptExistingFileIfIdentical(
                data,
                named: named,
                directoryDescriptor: leaseDescriptor,
                finalURL: destination,
                leaseName: lease.relativeDirectory
            ) {
                return destination
            }
        } catch let failure as ProtectedFilePolicyError
            where failure == .protectedDataUnavailable {
            throw ScratchDataLeaseStoreFailureV1.protectedDataUnavailable
        } catch let failure as ScratchDataLeaseStoreFailureV1 {
            throw failure
        } catch {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        let (nextBytes, overflow) = currentBytes.addingReportingOverflow(
            UInt64(data.count)
        )
        guard !overflow, nextBytes <= lease.request.requestedByteCount else {
            throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
        }
        do {
            try verifyRoot()
            try publishDurably(
                data,
                named: named,
                directoryDescriptor: leaseDescriptor,
                directoryURL: directory,
                finalURL: destination,
                leaseName: lease.relativeDirectory
            )
            // The durable directory state, rather than the caller's buffer size,
            // is authoritative for the lease ceiling.
            let durableBytes = try payloadByteCount(
                directoryDescriptor: leaseDescriptor,
                directoryURL: directory
            )
            guard durableBytes <= lease.request.requestedByteCount else {
                throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
            }
            return destination
        } catch let failure as ProtectedFilePolicyError
            where failure == .protectedDataUnavailable {
            throw ScratchDataLeaseStoreFailureV1.protectedDataUnavailable
        } catch let failure as ScratchDataLeaseStoreFailureV1 {
            throw failure
        } catch {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
    }

    func releaseScratchLease(
        _ lease: ScratchDataLeaseV1,
        terminal: ScratchDataLeaseTerminalV1
    ) async throws {
        if active[lease.request.leaseID] != lease {
            // Relaunch retries first reconstruct authoritative on-disk state.
            _ = try recoverScratchLeaseState()
            if active[lease.request.leaseID] == nil {
                var information = stat()
                if Darwin.fstatat(
                    authority.rootDescriptor,
                    lease.relativeDirectory,
                    &information,
                    AT_SYMLINK_NOFOLLOW
                ) != 0, errno == ENOENT {
                    return
                }
                throw ScratchDataLeaseStoreFailureV1.invalidLease
            }
            guard active[lease.request.leaseID] == lease else {
                throw ScratchDataLeaseStoreFailureV1.invalidLease
            }
        }
        _ = terminal
        try removeLeaseDirectory(named: lease.relativeDirectory)
        active.removeValue(forKey: lease.request.leaseID)
    }

    func recoverScratchLeases() async throws -> ScratchDataLeaseRecoverySummaryV1 {
        let result = try recoverScratchLeaseState()
        return try ScratchDataLeaseRecoverySummaryV1(
            recoveredExpiredLeaseCount: result.expiredCount,
            removedByteCount: result.removedByteCount
        )
    }

    private func recoverScratchLeaseState() throws -> (
        active: [ScratchDataLeaseV1],
        expiredCount: Int,
        removedByteCount: UInt64
    ) {
        try verifyRoot()
        let children = try directoryNames(authority.rootDescriptor)
        let childSet = Set(children)
        for tombstone in children where Self.isDeletionTombstone(tombstone) {
            let original = String(
                tombstone.dropFirst(Self.deletionPrefix.count)
            )
            guard !childSet.contains(original) else {
                // Atomic rename can never create both names. Seeing both is a
                // collision or substitution, so recovery deletes neither.
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        }
        var recovered: [UUID: ScratchDataLeaseV1] = [:]
        var expiredCount = 0
        var removedByteCount: UInt64 = 0
        for childName in children {
            if Self.isDeletionTombstone(childName) {
                try removeDeletionTombstone(named: childName)
                continue
            }
            guard Self.isLeaseDirectoryName(childName) else {
                throw ScratchDataLeaseStoreFailureV1.invalidLease
            }
            let child = rootURL.appendingPathComponent(childName, isDirectory: true)
            let leaseDescriptor = try openLeaseDirectory(childName)
            let lease: ScratchDataLeaseV1
            let expiredBytes: UInt64?
            do {
                let metadataURL = child.appendingPathComponent(Self.metadataName)
                let data = try readRegularFile(
                    named: Self.metadataName,
                    directoryDescriptor: leaseDescriptor,
                    maximumBytes: 65_536
                )
                try ProtectedFilePolicyV1.verify(.temporaryFile, at: metadataURL)
                lease = try JSONDecoder().decode(
                    ScratchDataLeaseV1.self,
                    from: data
                )
                try lease.request.validate()
                guard lease.schemaVersion == ScratchDataLeaseV1.schemaVersion,
                      lease.request.schemaVersion
                        == ScratchDataLeaseRequestV1.schemaVersion,
                      lease.request.protection == .complete,
                      lease.request.backupPolicy == .excluded,
                      lease.request.createdAt <= clock(),
                      try canonicalData(lease) == data,
                      lease.relativeDirectory == childName,
                      childName == Self.leaseDirectoryName(
                          for: lease.request
                      ) else {
                    throw ScratchDataLeaseStoreFailureV1.invalidLease
                }
                // Only valid, canonical lease authority may authorize cleanup
                // of an interrupted publication inside this directory.
                try removeInterruptedPublications(
                    directoryDescriptor: leaseDescriptor
                )
                if clock() >= lease.request.expiresAt {
                    expiredBytes = try allByteCount(
                        directoryDescriptor: leaseDescriptor,
                        directoryURL: child
                    )
                } else {
                    _ = try payloadByteCount(
                        directoryDescriptor: leaseDescriptor,
                        directoryURL: child
                    )
                    expiredBytes = nil
                }
            } catch let failure as ProtectedFilePolicyError
                where failure == .protectedDataUnavailable {
                _ = Darwin.close(leaseDescriptor)
                throw ScratchDataLeaseStoreFailureV1.protectedDataUnavailable
            } catch {
                _ = Darwin.close(leaseDescriptor)
                throw ScratchDataLeaseStoreFailureV1.invalidLease
            }
            _ = Darwin.close(leaseDescriptor)
            if let bytes = expiredBytes {
                let (next, overflow) = removedByteCount.addingReportingOverflow(bytes)
                guard !overflow else {
                    throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
                }
                removedByteCount = next
                expiredCount += 1
                try removeLeaseDirectory(named: childName)
                continue
            }
            if let prior = recovered[lease.request.leaseID], prior != lease {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            recovered[lease.request.leaseID] = lease
        }
        active = recovered
        return (recovered.values.sorted {
            $0.relativeDirectory < $1.relativeDirectory
        }, expiredCount, removedByteCount)
    }

    func resetScratchData() async throws {
        try verifyRoot()
        for child in try directoryNames(authority.rootDescriptor) {
            if Self.isDeletionTombstone(child) {
                try removeDeletionTombstone(named: child)
            } else {
                try removeLeaseDirectory(named: child)
            }
        }
        active.removeAll(keepingCapacity: false)
    }

    func eraseScratchData() async throws {
        try await resetScratchData()
        try verifyRoot()
        guard Darwin.unlinkat(
            authority.operationsDescriptor,
            Self.rootName,
            AT_REMOVEDIR
        ) == 0,
        Darwin.fsync(authority.operationsDescriptor) == 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        active.removeAll(keepingCapacity: false)
    }

    private func payloadByteCount(
        directoryDescriptor: Int32,
        directoryURL: URL
    ) throws -> UInt64 {
        var total: UInt64 = 0
        for name in try directoryNames(directoryDescriptor)
        where name != Self.metadataName {
            let information = try regularFileInformation(
                named: name,
                directoryDescriptor: directoryDescriptor
            )
            try ProtectedFilePolicyV1.verify(
                .temporaryFile,
                at: directoryURL.appendingPathComponent(name)
            )
            let (next, overflow) = total.addingReportingOverflow(
                UInt64(information.st_size)
            )
            guard !overflow else {
                throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
            }
            total = next
        }
        return total
    }

    private func allByteCount(
        directoryDescriptor: Int32,
        directoryURL: URL
    ) throws -> UInt64 {
        var total: UInt64 = 0
        for name in try directoryNames(directoryDescriptor) {
            let information = try regularFileInformation(
                named: name,
                directoryDescriptor: directoryDescriptor
            )
            try ProtectedFilePolicyV1.verify(
                .temporaryFile,
                at: directoryURL.appendingPathComponent(name)
            )
            let (next, overflow) = total.addingReportingOverflow(
                UInt64(information.st_size)
            )
            guard !overflow else {
                throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
            }
            total = next
        }
        return total
    }

    private func removeLeaseDirectory(named name: String) throws {
        guard Self.isLeaseDirectoryName(name) else {
            throw ScratchDataLeaseStoreFailureV1.invalidLease
        }
        try verifyRoot()
        let tombstone = Self.deletionTombstoneName(for: name)
        if try directoryInformationIfPresent(named: name) == nil {
            guard try directoryInformationIfPresent(named: tombstone) != nil else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            try removeDeletionTombstone(named: tombstone)
            return
        }
        guard try directoryInformationIfPresent(named: tombstone) == nil else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        let descriptor = try openLeaseDirectory(name)
        defer { _ = Darwin.close(descriptor) }
        var pinned = stat()
        guard Darwin.fstat(descriptor, &pinned) == 0,
              Darwin.renameat(
                  authority.rootDescriptor,
                  name,
                  authority.rootDescriptor,
                  tombstone
              ) == 0,
              Darwin.fsync(authority.rootDescriptor) == 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        var oldEntry = stat()
        guard Darwin.fstatat(
            authority.rootDescriptor,
            name,
            &oldEntry,
            AT_SYMLINK_NOFOLLOW
        ) != 0,
              errno == ENOENT else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        try verifyLeaseDirectory(tombstone, descriptor: descriptor)
        var linked = stat()
        guard Darwin.fstatat(
            authority.rootDescriptor,
            tombstone,
            &linked,
            AT_SYMLINK_NOFOLLOW
        ) == 0,
              linked.st_dev == pinned.st_dev,
              linked.st_ino == pinned.st_ino else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        try deletePinnedDirectory(named: tombstone, descriptor: descriptor)
    }

    private func removeDeletionTombstone(named name: String) throws {
        guard Self.isDeletionTombstone(name) else {
            throw ScratchDataLeaseStoreFailureV1.invalidLease
        }
        let descriptor = try openLeaseDirectory(name)
        defer { _ = Darwin.close(descriptor) }
        do {
            try validateDeletionTombstone(named: name, descriptor: descriptor)
        } catch let failure as ProtectedFilePolicyError
            where failure == .protectedDataUnavailable {
            throw ScratchDataLeaseStoreFailureV1.protectedDataUnavailable
        } catch {
            throw ScratchDataLeaseStoreFailureV1.invalidLease
        }
        try deletePinnedDirectory(named: name, descriptor: descriptor)
    }

    private func validateDeletionTombstone(
        named name: String,
        descriptor: Int32
    ) throws {
        guard Self.isDeletionTombstone(name) else {
            throw ScratchDataLeaseStoreFailureV1.invalidLease
        }
        let originalName = String(name.dropFirst(Self.deletionPrefix.count))
        let directory = rootURL.appendingPathComponent(name, isDirectory: true)
        let metadataURL = directory.appendingPathComponent(Self.metadataName)
        try verifyLeaseDirectory(name, descriptor: descriptor)
        let data = try readRegularFile(
            named: Self.metadataName,
            directoryDescriptor: descriptor,
            maximumBytes: 65_536
        )
        try ProtectedFilePolicyV1.verify(.temporaryFile, at: metadataURL)
        let lease = try JSONDecoder().decode(ScratchDataLeaseV1.self, from: data)
        try lease.request.validate()
        guard lease.schemaVersion == ScratchDataLeaseV1.schemaVersion,
              lease.request.schemaVersion
                == ScratchDataLeaseRequestV1.schemaVersion,
              lease.request.protection == .complete,
              lease.request.backupPolicy == .excluded,
              lease.request.createdAt <= clock(),
              try canonicalData(lease) == data,
              lease.relativeDirectory == originalName,
              originalName == Self.leaseDirectoryName(for: lease.request) else {
            throw ScratchDataLeaseStoreFailureV1.invalidLease
        }
        try verifyLeaseDirectory(name, descriptor: descriptor)
        guard try readRegularFile(
            named: Self.metadataName,
            directoryDescriptor: descriptor,
            maximumBytes: 65_536
        ) == data else {
            throw ScratchDataLeaseStoreFailureV1.invalidLease
        }
    }

    private func deletePinnedDirectory(
        named name: String,
        descriptor: Int32
    ) throws {
        try verifyLeaseDirectory(name, descriptor: descriptor)
        try removeInterruptedPublications(directoryDescriptor: descriptor)
        for child in try directoryNames(descriptor) {
            _ = try regularFileInformation(
                named: child,
                directoryDescriptor: descriptor
            )
            guard Darwin.unlinkat(descriptor, child, 0) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        try verifyLeaseDirectory(name, descriptor: descriptor)
        guard Darwin.unlinkat(authority.rootDescriptor, name, AT_REMOVEDIR) == 0,
              Darwin.fsync(authority.rootDescriptor) == 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        var absent = stat()
        guard Darwin.fstatat(
            authority.rootDescriptor,
            name,
            &absent,
            AT_SYMLINK_NOFOLLOW
        ) != 0,
              errno == ENOENT else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        try verifyRoot()
    }

    private func directoryInformationIfPresent(named name: String) throws -> stat? {
        try verifyRoot()
        var information = stat()
        if Darwin.fstatat(
            authority.rootDescriptor,
            name,
            &information,
            AT_SYMLINK_NOFOLLOW
        ) == 0 {
            guard (information.st_mode & S_IFMT) == S_IFDIR,
                  UInt64(information.st_dev) == authority.rootDevice else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            return information
        }
        guard errno == ENOENT else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        return nil
    }

    private func openLeaseDirectory(_ name: String) throws -> Int32 {
        guard OperationalDiagnosticsBoundsV1.validRelativeName(name) else {
            throw ScratchDataLeaseStoreFailureV1.invalidLease
        }
        try verifyRoot()
        var before = stat()
        guard Darwin.fstatat(
            authority.rootDescriptor,
            name,
            &before,
            AT_SYMLINK_NOFOLLOW
        ) == 0,
        (before.st_mode & S_IFMT) == S_IFDIR,
        UInt64(before.st_dev) == authority.rootDevice else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        let descriptor = Darwin.openat(
            authority.rootDescriptor,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        var pinned = stat()
        guard Darwin.fstat(descriptor, &pinned) == 0,
              (pinned.st_mode & S_IFMT) == S_IFDIR,
              pinned.st_dev == before.st_dev,
              pinned.st_ino == before.st_ino else {
            _ = Darwin.close(descriptor)
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        return descriptor
    }

    private func verifyLeaseDirectory(
        _ name: String,
        descriptor: Int32
    ) throws {
        try verifyRoot()
        var linked = stat()
        var pinned = stat()
        guard Darwin.fstatat(
            authority.rootDescriptor,
            name,
            &linked,
            AT_SYMLINK_NOFOLLOW
        ) == 0,
        Darwin.fstat(descriptor, &pinned) == 0,
        (linked.st_mode & S_IFMT) == S_IFDIR,
        linked.st_dev == pinned.st_dev,
        linked.st_ino == pinned.st_ino else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
    }

    private func directoryNames(_ descriptor: Int32) throws -> [String] {
        let duplicate = Darwin.dup(descriptor)
        guard duplicate >= 0, let directory = Darwin.fdopendir(duplicate) else {
            if duplicate >= 0 { _ = Darwin.close(duplicate) }
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        defer { _ = Darwin.closedir(directory) }
        var names: [String] = []
        errno = 0
        while let entry = Darwin.readdir(directory) {
            var tuple = entry.pointee.d_name
            let capacity = MemoryLayout.size(ofValue: tuple)
            let name = withUnsafePointer(to: &tuple) {
                $0.withMemoryRebound(to: CChar.self, capacity: capacity) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            guard OperationalDiagnosticsBoundsV1.validRelativeName(name) else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            names.append(name)
        }
        guard errno == 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        return names.sorted()
    }

    private func regularFileInformation(
        named name: String,
        directoryDescriptor: Int32
    ) throws -> stat {
        guard let information = try regularFileInformationIfPresent(
            named: name,
            directoryDescriptor: directoryDescriptor
        ) else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        return information
    }

    private func regularFileInformationIfPresent(
        named name: String,
        directoryDescriptor: Int32
    ) throws -> stat? {
        var information = stat()
        if Darwin.fstatat(
            directoryDescriptor,
            name,
            &information,
            AT_SYMLINK_NOFOLLOW
        ) != 0 {
            guard errno == ENOENT else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            return nil
        }
        guard (information.st_mode & S_IFMT) == S_IFREG,
              information.st_nlink == 1,
              information.st_size >= 0,
              UInt64(information.st_dev) == authority.rootDevice else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        return information
    }

    private func adoptExistingFileIfIdentical(
        _ data: Data,
        named name: String,
        directoryDescriptor: Int32,
        finalURL: URL,
        leaseName: String?
    ) throws -> Bool {
        guard let existing = try regularFileInformationIfPresent(
            named: name,
            directoryDescriptor: directoryDescriptor
        ) else {
            return false
        }
        guard existing.st_size == Int64(data.count),
              try readRegularFile(
                  named: name,
                  directoryDescriptor: directoryDescriptor,
                  maximumBytes: data.count
              ) == data else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try ProtectedFilePolicyV1.verify(.temporaryFile, at: finalURL)
        if let leaseName {
            try verifyLeaseDirectory(
                leaseName,
                descriptor: directoryDescriptor
            )
        } else {
            try verifyRoot()
        }
        guard try readRegularFile(
            named: name,
            directoryDescriptor: directoryDescriptor,
            maximumBytes: data.count
        ) == data else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        return true
    }

    private func readRegularFile(
        named name: String,
        directoryDescriptor: Int32,
        maximumBytes: Int
    ) throws -> Data {
        let expected = try regularFileInformation(
            named: name,
            directoryDescriptor: directoryDescriptor
        )
        guard expected.st_size <= Int64(maximumBytes) else {
            throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
        }
        let descriptor = Darwin.openat(
            directoryDescriptor,
            name,
            O_RDONLY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        defer { _ = Darwin.close(descriptor) }
        var pinned = stat()
        guard Darwin.fstat(descriptor, &pinned) == 0,
              pinned.st_dev == expected.st_dev,
              pinned.st_ino == expected.st_ino,
              pinned.st_size == expected.st_size else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        var result = Data(count: Int(pinned.st_size))
        var offset = 0
        while offset < result.count {
            let count = result.withUnsafeMutableBytes { bytes -> Int in
                guard let base = bytes.baseAddress else { return 0 }
                return Darwin.read(
                    descriptor,
                    base.advanced(by: offset),
                    result.count - offset
                )
            }
            guard count > 0 else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            offset += count
        }
        var after = stat()
        var linked = stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              after.st_dev == pinned.st_dev,
              after.st_ino == pinned.st_ino,
              after.st_nlink == 1,
              after.st_size == pinned.st_size,
              Darwin.fstatat(
                  directoryDescriptor,
                  name,
                  &linked,
                  AT_SYMLINK_NOFOLLOW
              ) == 0,
              linked.st_dev == pinned.st_dev,
              linked.st_ino == pinned.st_ino,
              linked.st_nlink == 1,
              linked.st_size == pinned.st_size else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        return result
    }

    private func publishDurably(
        _ data: Data,
        named name: String,
        directoryDescriptor: Int32,
        directoryURL: URL,
        finalURL: URL,
        leaseName: String? = nil
    ) throws {
        let temporaryName = ".partial-\(UUID().uuidString.lowercased())"
        let descriptor = Darwin.openat(
            directoryDescriptor,
            temporaryName,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            0o600
        )
        guard descriptor >= 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        var published = false
        defer {
            _ = Darwin.close(descriptor)
            if !published {
                _ = Darwin.unlinkat(directoryDescriptor, temporaryName, 0)
            }
        }
        var offset = 0
        while offset < data.count {
            let count = data.withUnsafeBytes { bytes -> Int in
                guard let base = bytes.baseAddress else { return 0 }
                return Darwin.write(
                    descriptor,
                    base.advanced(by: offset),
                    data.count - offset
                )
            }
            guard count > 0 else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            offset += count
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        let temporaryURL = directoryURL.appendingPathComponent(temporaryName)
        try ProtectedFilePolicyV1.applyAndVerify(
            .temporaryFile,
            at: temporaryURL,
            authorityCheck: {
                if let leaseName {
                    try verifyLeaseDirectory(
                        leaseName,
                        descriptor: directoryDescriptor
                    )
                } else {
                    try verifyRoot()
                }
            }
        )
        // linkat supplies no-replace publication. The temporary hard link is
        // removed before policy verification so the published file has nlink 1.
        let publicationResult = Darwin.linkat(
            directoryDescriptor,
            temporaryName,
            directoryDescriptor,
            name,
            0
        )
        if publicationResult != 0 {
            if errno == EEXIST {
                guard try adoptExistingFileIfIdentical(
                    data,
                    named: name,
                    directoryDescriptor: directoryDescriptor,
                    finalURL: finalURL,
                    leaseName: leaseName
                ) else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                guard Darwin.unlinkat(
                    directoryDescriptor,
                    temporaryName,
                    0
                ) == 0,
                      Darwin.fsync(directoryDescriptor) == 0 else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                published = true
                return
            }
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        guard Darwin.unlinkat(directoryDescriptor, temporaryName, 0) == 0,
              Darwin.fsync(directoryDescriptor) == 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        published = true
        _ = try regularFileInformation(
            named: name,
            directoryDescriptor: directoryDescriptor
        )
        try ProtectedFilePolicyV1.verify(.temporaryFile, at: finalURL)
        if let leaseName {
            try verifyLeaseDirectory(
                leaseName,
                descriptor: directoryDescriptor
            )
        } else {
            try verifyRoot()
        }
        guard try readRegularFile(
            named: name,
            directoryDescriptor: directoryDescriptor,
            maximumBytes: data.count
        ) == data else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
    }

    private func removeInterruptedPublications(
        directoryDescriptor: Int32
    ) throws {
        var removed = false
        for name in try directoryNames(directoryDescriptor)
        where name.hasPrefix(".partial-") {
            var information = stat()
            guard Darwin.fstatat(
                directoryDescriptor,
                name,
                &information,
                AT_SYMLINK_NOFOLLOW
            ) == 0,
            (information.st_mode & S_IFMT) == S_IFREG,
            information.st_nlink == 1 || information.st_nlink == 2,
            UInt64(information.st_dev) == authority.rootDevice,
            Darwin.unlinkat(directoryDescriptor, name, 0) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            removed = true
        }
        if removed, Darwin.fsync(directoryDescriptor) != 0 {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
    }

    private func verifyRoot() throws {
        try authority.verify(rootName: Self.rootName)
    }

    private static func leaseDirectoryName(
        for request: ScratchDataLeaseRequestV1
    ) -> String {
        "\(request.purpose.rawValue.lowercased())-\(request.leaseID.uuidString.lowercased())"
    }

    private static func deletionTombstoneName(for leaseName: String) -> String {
        deletionPrefix + leaseName
    }

    private static func isDeletionTombstone(_ name: String) -> Bool {
        guard name.hasPrefix(deletionPrefix) else { return false }
        return isLeaseDirectoryName(String(name.dropFirst(deletionPrefix.count)))
    }

    private static func isLeaseDirectoryName(_ name: String) -> Bool {
        for purpose in ScratchDataPurposeV1.allCases {
            let prefix = purpose.rawValue.lowercased() + "-"
            guard name.hasPrefix(prefix) else { continue }
            let identifier = String(name.dropFirst(prefix.count))
            guard let uuid = UUID(uuidString: identifier) else { return false }
            return identifier == uuid.uuidString.lowercased()
        }
        return false
    }

    private func canonicalData<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func prepareRoot(_ root: URL) throws {
        let operations = root.deletingLastPathComponent()
        let applicationSupport = operations.deletingLastPathComponent()
        let applicationSupportDescriptor = Darwin.open(
            applicationSupport.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard applicationSupportDescriptor >= 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        defer { _ = Darwin.close(applicationSupportDescriptor) }
        var applicationSupportInformation = stat()
        guard Darwin.fstat(
            applicationSupportDescriptor,
            &applicationSupportInformation
        ) == 0,
        (applicationSupportInformation.st_mode & S_IFMT) == S_IFDIR else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        let operationsName = operations.lastPathComponent
        guard OperationalDiagnosticsBoundsV1.validRelativeName(operationsName),
              Darwin.mkdirat(
                  applicationSupportDescriptor,
                  operationsName,
                  0o700
              ) == 0 || errno == EEXIST else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        let operationsDescriptor = Darwin.openat(
            applicationSupportDescriptor,
            operationsName,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard operationsDescriptor >= 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        defer { _ = Darwin.close(operationsDescriptor) }
        var operationsInformation = stat()
        guard Darwin.fstat(operationsDescriptor, &operationsInformation) == 0,
              (operationsInformation.st_mode & S_IFMT) == S_IFDIR,
              operationsInformation.st_dev == applicationSupportInformation.st_dev,
              Darwin.mkdirat(operationsDescriptor, root.lastPathComponent, 0o700) == 0
                || errno == EEXIST,
              Darwin.fsync(operationsDescriptor) == 0,
              Darwin.fsync(applicationSupportDescriptor) == 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
    }
}

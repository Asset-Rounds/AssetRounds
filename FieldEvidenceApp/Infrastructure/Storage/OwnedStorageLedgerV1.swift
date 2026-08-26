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

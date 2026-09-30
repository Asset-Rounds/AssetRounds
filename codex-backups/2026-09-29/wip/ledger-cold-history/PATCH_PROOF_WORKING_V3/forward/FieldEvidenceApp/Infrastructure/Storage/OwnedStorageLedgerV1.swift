import Darwin
import CryptoKit
import Foundation

/// Keep the original owner's checked descriptor lifetime on the main actor.
/// The callback performs synchronous owner reproofs; it cannot cross an await.
@MainActor private extension EraseAbortCheckedSnapshotIOV1 {
    func withOriginalEraseMainActorOpen<Value>(parent: Int32, name: String,
        flags: Int32, _ body: (Int32) throws -> Value) throws -> Value {
        try requireSettled()
        let descriptor = Darwin.openat(parent, name,
            flags | O_NOFOLLOW | O_CLOEXEC, 0)
        guard descriptor >= 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        var closeAttempted = false
        do {
            let result = try body(descriptor)
            closeAttempted = true
            guard Darwin.close(descriptor) == 0 else {
                retainUncertainDescriptor(descriptor)
                throw StoreGenerationFailure.dataPointerInvalid
            }
            return result
        } catch {
            if !closeAttempted, Darwin.close(descriptor) != 0 {
                retainUncertainDescriptor(descriptor)
            }
            throw error
        }
    }
}

/// Darwin readdir returns variable-length records, not a full Swift dirent value.
/// Read only the advertised name bytes while the directory entry is still valid.
enum OwnedStorageDirectoryEntryNameV1 {
    static func decode(_ entry: UnsafePointer<dirent>) -> String? {
        guard let nameOffset = MemoryLayout<dirent>.offset(of: \.d_name) else {
            return nil
        }
        let recordLength = Int(entry.pointee.d_reclen)
        let nameLength = Int(entry.pointee.d_namlen)
        let nameCapacity = MemoryLayout.size(ofValue: dirent().d_name)
        guard nameLength > 0, nameLength < nameCapacity,
              recordLength > nameOffset,
              nameLength < recordLength - nameOffset else { return nil }
        let bytes = UnsafeRawPointer(entry).advanced(by: nameOffset)
            .assumingMemoryBound(to: UInt8.self)
        guard bytes[nameLength] == 0 else { return nil }
        let nameBytes = UnsafeBufferPointer(start: bytes, count: nameLength)
        guard !nameBytes.contains(0), !nameBytes.contains(UInt8(ascii: "/")) else {
            return nil
        }
        return String(bytes: nameBytes, encoding: .utf8)
    }
}

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

/// Internal C16 recovery-test seam. Production defaults to `.none`; no
/// payload is surfaced and only the three durable state-machine boundaries
/// may be interrupted.
enum C16IngressHygieneFailureInjectionV1: Equatable, Sendable {
    case none
    case afterPrepare
    case afterEffect
    case afterReceipt

    func interruptIfTriggered(_ boundary: Self) throws {
        guard self == boundary, self != .none else { return }
        throw OwnedStorageLedgerFailureV1.attemptCollision
    }
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
    private let ingressHygieneFailureInjection: C16IngressHygieneFailureInjectionV1
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
        },
        ingressHygieneFailureInjection: C16IngressHygieneFailureInjectionV1 = .none
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
        self.ingressHygieneFailureInjection = ingressHygieneFailureInjection
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
        },
        ingressHygieneFailureInjection: C16IngressHygieneFailureInjectionV1 = .none
    ) throws {
        try self.init(
            rootURLs: OwnedStorageRootV1.closedSet(
                applicationSupportURL: applicationSupportURL
            ),
            capacityProvider: capacityProvider,
            ingressHygieneFailureInjection: ingressHygieneFailureInjection
        )
    }

    func snapshot() -> OwnedStorageSnapshotV1 {
        lock.withLock { makeSnapshot() }
    }

    /// Observation only. Use the live ledger, including its current reservations;
    /// a preflight must never reserve, reconcile, or create another ledger.
    func observeOfflineReadiness(
        expectedApplicationSupportURL: URL
    ) throws -> OfflineReadinessStorageObservationV1 {
        guard expectedApplicationSupportURL.isFileURL,
              expectedApplicationSupportURL.standardizedFileURL == capacityURL.standardizedFileURL else {
            throw OwnedStorageLedgerFailureV1.invalidRoot
        }
        let before = try Self.rootIdentity(at: capacityURL)
        try lock.withLock {
            guard before.volume == volumeIdentity, before.inode == capacityRootInode else {
                throw OwnedStorageLedgerFailureV1.volumeMismatch
            }
        }
        let capacity: Int64?
        do { capacity = try capacityProvider(capacityURL) }
        catch { capacity = nil }
        let after = try Self.rootIdentity(at: capacityURL)
        guard after == before else { throw OwnedStorageLedgerFailureV1.volumeMismatch }
        return try lock.withLock {
            guard after.volume == volumeIdentity, after.inode == capacityRootInode else {
                throw OwnedStorageLedgerFailureV1.volumeMismatch
            }
            let available = capacity.flatMap { $0 >= 0 ? $0 : nil }
            return try OfflineReadinessStorageObservationV1(
                capacityState: available == nil ? .unavailable : .checked,
                availableBytes: available,
                reservedBytes: Self.sum(reservations.values.map(\.requiredBytes)),
                operationReserveBytes: StoragePreflightService.reserveBytes
            )
        }
    }

    func purgeConfidentlyOwnedExpiredScratchMetadata(now: Date, operationID: UUID, minimumAge: TimeInterval = 24 * 60 * 60) throws -> ProtectedIngressStartupHygieneReceiptV1 {
        try scratchOwnerForHygiene().purgeConfidentlyOwnedExpiredScratchMetadata(now: now, operationID: operationID, minimumAge: minimumAge)
    }

    func reconcileProtectedIngressHygiene(now: Date, operationID: UUID, minimumAge: TimeInterval = 24 * 60 * 60) throws -> ProtectedIngressStartupHygieneReceiptV1 {
        try scratchOwnerForHygiene().reconcileProtectedIngressHygiene(now: now, operationID: operationID, minimumAge: minimumAge)
    }

    func readProtectedIngressHygieneReceipt(operationID: UUID) throws -> ProtectedIngressStartupHygieneReceiptV1? {
        try scratchOwnerForHygiene().readProtectedIngressHygieneReceipt(operationID: operationID)
    }

    func writeProtectedIngressHygieneReceipt(_ value: ProtectedIngressStartupHygieneReceiptV1) throws {
        try scratchOwnerForHygiene().writeProtectedIngressHygieneReceipt(value)
    }

    fileprivate func scratchOwnerForHygiene() throws -> ScratchDataLeaseStoreV1 {
        try lock.withLock {
            let identity = try Self.rootIdentity(at: capacityURL)
            guard identity.volume == volumeIdentity, identity.inode == capacityRootInode else {
                throw OwnedStorageLedgerFailureV1.volumeMismatch
            }
        }
        return try ScratchDataLeaseStoreV1(
            applicationSupportURL: capacityURL, clock: { Date() },
            capacityProvider: capacityProvider,
            ingressHygieneFailureInjection: ingressHygieneFailureInjection
        )
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
    static func isConfidentScratchLeaseDirectoryName(_ value: String) -> Bool {
        ScratchDataPurposeV1.allCases.contains { purpose in
            let prefix = purpose.rawValue.lowercased() + "-"
            guard value.hasPrefix(prefix) else { return false }
            let suffix = String(value.dropFirst(prefix.count))
            return UUID(uuidString: suffix)?.uuidString.lowercased() == suffix
        }
    }
}

private struct C16IngressHygieneRequestV1: Codable, Equatable {
    let operationID: UUID
    let requestedAt: Date
    let minimumAge: TimeInterval
}

fileprivate struct C16IngressHygieneFileIdentityV1: Codable, Equatable {
    let name: String
    let device: UInt64
    let inode: UInt64
    let byteCount: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64

    init(_ value: OriginalEraseC16FileFactV1) {
        name = value.name; device = value.device; inode = value.inode
        byteCount = value.byteCount; modifiedSeconds = value.modifiedSeconds
        modifiedNanoseconds = value.modifiedNanoseconds
    }

    init(name: String, information: stat) {
        self.name = name
        device = UInt64(information.st_dev)
        inode = UInt64(information.st_ino)
        byteCount = Int64(information.st_size)
        modifiedSeconds = Int64(information.st_mtimespec.tv_sec)
        modifiedNanoseconds = Int64(information.st_mtimespec.tv_nsec)
    }
}

private struct C16IngressHygieneTargetV1: Codable, Equatable, Comparable {
    let directoryName: String
    let modifiedAt: Date
    let device: UInt64
    let inode: UInt64
    let files: [C16IngressHygieneFileIdentityV1]

    init(directoryName: String, modifiedAt: Date, information: stat, files: [C16IngressHygieneFileIdentityV1]) throws {
        guard OwnedStorageLedgerV1.isConfidentScratchLeaseDirectoryName(directoryName),
              modifiedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        self.directoryName = directoryName
        self.modifiedAt = modifiedAt
        device = UInt64(information.st_dev)
        inode = UInt64(information.st_ino)
        self.files = files
    }

    init(directoryName: String, modifiedAt: Date, device: UInt64, inode: UInt64,
        files: [C16IngressHygieneFileIdentityV1]) throws {
        guard OwnedStorageLedgerV1.isConfidentScratchLeaseDirectoryName(directoryName),
              modifiedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        self.directoryName = directoryName; self.modifiedAt = modifiedAt
        self.device = device; self.inode = inode; self.files = files
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.directoryName < rhs.directoryName }
}

private struct C16IngressHygienePrepareV1: Codable, Equatable {
    static let schemaVersion = 2
    let schemaVersion: Int
    let request: C16IngressHygieneRequestV1
    let requestDigest: String
    let targets: [C16IngressHygieneTargetV1]
    let rootDevice: UInt64
    let rootInode: UInt64
    let retainedValidCount: Int
    let deferredAmbiguousCount: Int
    let finalized: Bool

    init(
        request: C16IngressHygieneRequestV1,
        requestDigest: String,
        targets: [C16IngressHygieneTargetV1],
        rootDevice: UInt64,
        rootInode: UInt64,
        retainedValidCount: Int,
        deferredAmbiguousCount: Int,
        finalized: Bool
    ) throws {
        schemaVersion = Self.schemaVersion
        self.request = request
        self.requestDigest = requestDigest
        self.targets = targets.sorted()
        self.rootDevice = rootDevice
        self.rootInode = rootInode
        self.retainedValidCount = retainedValidCount
        self.deferredAmbiguousCount = deferredAmbiguousCount
        self.finalized = finalized
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              request.operationID != SettingsValidationV1.zeroUUID,
              request.requestedAt.timeIntervalSinceReferenceDate.isFinite,
              request.minimumAge > 0, request.minimumAge.isFinite,
              CompatibilityCanonicalV1.validSHA256(requestDigest),
              (0...128).contains(retainedValidCount), (0...128).contains(deferredAmbiguousCount),
              targets.count <= ProtectedIngressStartupHygieneReceiptV1.maximumInspectedCount,
              targets == targets.sorted(), Set(targets.map(\.directoryName)).count == targets.count else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let expected = try CompatibilityCanonicalV1.sha256(
            CompatibilityCanonicalV1.encode(request)
        )
        guard requestDigest == expected else { throw AppAccessContractFailureV1.configurationUnknown }
        for target in targets {
            guard OwnedStorageLedgerV1.isConfidentScratchLeaseDirectoryName(target.directoryName),
                  target.device == rootDevice,
                  target.modifiedAt.timeIntervalSinceReferenceDate.isFinite,
                  target.modifiedAt <= request.requestedAt.addingTimeInterval(-request.minimumAge),
                  target.files.count <= 128,
                  target.files.map(\.name) == target.files.map(\.name).sorted(),
                  Set(target.files.map(\.name)).count == target.files.count,
                  target.files.allSatisfy({ OperationalDiagnosticsBoundsV1.validRelativeName($0.name)
                      && $0.device == rootDevice && $0.byteCount >= 0
                      && $0.modifiedNanoseconds >= 0 && $0.modifiedNanoseconds < 1_000_000_000 }) else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        }
        _ = try receipt()
    }

    func receipt() throws -> ProtectedIngressStartupHygieneReceiptV1 {
        try ProtectedIngressStartupHygieneReceiptV1(
            operationID: request.operationID,
            inspectedCount: targets.count + retainedValidCount + deferredAmbiguousCount,
            removedKnownOwnedCount: targets.count, retainedValidCount: retainedValidCount,
            deferredAmbiguousCount: deferredAmbiguousCount, contentRead: false
        )
    }

    func finalizing() throws -> Self {
        try Self(request: request, requestDigest: requestDigest, targets: targets,
                 rootDevice: rootDevice, rootInode: rootInode,
                 retainedValidCount: retainedValidCount, deferredAmbiguousCount: deferredAmbiguousCount,
                 finalized: true)
    }
}

enum C16IngressMutationFailureInjectionV1: Equatable, Sendable {
    case none, afterPrepare, afterClaim, afterOpaqueCopy, afterPublication, afterPending
    case afterRemovalPrepare, afterRemovalEffect, afterErasePrepare, afterUnpublishedRemoval
    case afterScratchControlErasePublication, afterScratchControlErasePrepare, afterScratchControlEraseFile
    case afterPreparedDirectoryFileDeletion
    func interruptIfTriggered(_ boundary: Self) throws {
        if self == boundary && self != .none { throw OwnedStorageLedgerFailureV1.attemptCollision }
    }
}

private struct C16IngressPreparedStageV1: Codable, Equatable {
    static let supportedKinds: [LockedIngressKindV1] = [.backupFile, .csvFile, .document, .reviewFile, .shareFile, .thirdPartyAdapterFile]
    let intent: PendingLockedExternalIntentV1
    let lease: ScratchDataLeaseV1
    let rootDevice: UInt64
    let rootInode: UInt64

    func validate() throws {
        try intent.validate()
        try lease.request.validate()
        guard Self.supportedKinds.contains(intent.kind),
              intent.disposition == .stagedProtectedPendingAuthentication,
              lease.schemaVersion == ScratchDataLeaseV1.schemaVersion,
              lease.request.leaseID == intent.intentID,
              lease.request.ownerOperationID == intent.operationID,
              lease.request.purpose == .importData, lease.request.owner == .importData,
              lease.request.protection == .complete, lease.request.backupPolicy == .excluded,
              lease.request.requestedByteCount == intent.byteCount,
              lease.request.createdAt == intent.receivedAt, lease.request.expiresAt == intent.expiresAt,
              lease.relativeDirectory == "import-" + intent.intentID.uuidString.lowercased(),
              intent.opaqueStagingID == "opaque-" + intent.intentID.uuidString.lowercased() else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
    }
}

private struct C16IngressDirectoryClaimV1: Codable, Equatable {
    let preparation: C16IngressPreparedStageV1
    let device: UInt64
    let inode: UInt64
}

private struct C16IngressPublicationV1: Codable, Equatable {
    let claim: C16IngressDirectoryClaimV1
    let metadata: C16IngressHygieneFileIdentityV1
    let payload: C16IngressHygieneFileIdentityV1
    let intent: PendingLockedExternalIntentV1

    func validate() throws {
        try claim.preparation.validate()
        try intent.validate()
        guard claim.device == claim.preparation.rootDevice,
              metadata.name == "lease.json", payload.name == "opaque-data",
              metadata.device == claim.device, payload.device == claim.device,
              metadata.byteCount > 0, metadata.byteCount <= 65_536,
              payload.byteCount >= 0, UInt64(payload.byteCount) == intent.byteCount,
              intent.disposition == .stagedProtectedPendingAuthentication
                || intent.disposition == .readyForAuthenticatedValidation,
              try claim.preparation.intent.advancing(to: intent.disposition) == intent else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
    }

    func replacingIntent(_ replacement: PendingLockedExternalIntentV1) throws -> Self {
        let value = Self(claim: claim, metadata: metadata, payload: payload, intent: replacement)
        try value.validate()
        return value
    }
}

private struct C16IngressRemovalV1: Codable, Equatable {
    let expected: C16IngressPublicationV1
    let disposition: LockedIngressDispositionV1
    func validate() throws {
        try expected.validate()
        guard disposition == .consumed || disposition == .expiredDeleted || disposition == .erased else {
            throw AppAccessContractFailureV1.invalidTransition
        }
    }
}

private struct C16IngressUnpublishedEraseTargetV1: Codable, Equatable {
    let preparation: C16IngressPreparedStageV1
    let directory: C16IngressHygieneTargetV1?

    var claim: C16IngressDirectoryClaimV1? {
        directory.map { .init(preparation: preparation, device: $0.device, inode: $0.inode) }
    }

    func validate() throws {
        try preparation.validate()
        if let directory {
            let names = directory.files.map(\.name)
            guard directory.directoryName == preparation.lease.relativeDirectory,
                  directory.device == preparation.rootDevice, directory.inode != 0,
                  directory.modifiedAt.timeIntervalSinceReferenceDate.isFinite,
                  names == names.sorted(), Set(names).count == names.count,
                  Set(names).isSubset(of: ["lease.json", "opaque-data"]),
                  directory.files.allSatisfy({
                      $0.device == directory.device && $0.inode != 0 && $0.byteCount >= 0
                        && UInt64($0.byteCount) <= PendingLockedExternalIntentV1.maximumByteCount
                        && (0..<1_000_000_000).contains($0.modifiedNanoseconds)
                  }) else { throw AppAccessContractFailureV1.configurationUnknown }
        }
    }
}

private struct C16IngressAbortedStageV1: Codable, Equatable {
    let operationID: UUID
    let expected: C16IngressUnpublishedEraseTargetV1
    func validate() throws {
        guard operationID != SettingsValidationV1.zeroUUID else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try expected.validate()
    }
}

private struct C16ScratchControlEraseV1: Codable, Equatable {
    let schemaVersion: Int
    let rootDevice: UInt64
    let rootInode: UInt64
    let controlDevice: UInt64
    let controlInode: UInt64
    let files: [C16IngressHygieneFileIdentityV1]
}

private struct C16IngressEraseV1: Codable, Equatable {
    let operationID: UUID
    let rootDevice: UInt64
    let rootInode: UInt64
    let targets: [C16IngressPublicationV1]
    let unpublishedTargets: [C16IngressUnpublishedEraseTargetV1]
    func validate() throws {
        let unpublishedIDs = unpublishedTargets.map { $0.preparation.intent.intentID }
        guard operationID != SettingsValidationV1.zeroUUID,
              targets.count + unpublishedTargets.count <= ProtectedIngressCoordinatorV1.maximumPendingIntentCount,
              targets.map({ $0.intent.intentID.uuidString }) == targets.map({ $0.intent.intentID.uuidString }).sorted(),
              Set(targets.map({ $0.intent.intentID })).count == targets.count,
              unpublishedIDs.map(\.uuidString) == unpublishedIDs.map(\.uuidString).sorted(),
              Set(unpublishedIDs).count == unpublishedIDs.count,
              Set(unpublishedIDs).isDisjoint(with: targets.map { $0.intent.intentID }) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try targets.forEach { target in
            try target.validate()
            guard target.claim.preparation.rootDevice == rootDevice, target.claim.preparation.rootInode == rootInode else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        }
        try unpublishedTargets.forEach { target in
            try target.validate()
            guard target.preparation.rootDevice == rootDevice,
                  target.preparation.rootInode == rootInode else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        }
    }
}

/// Device-local durable ingress and blind hygiene share the existing scratch
/// owner. No canonical workspace is opened by construction or opaque staging.
actor OwnedStorageLedgerProtectedIngressEffectV1: ProtectedIngressDurableEffectPortV1 {
    private let ledger: OwnedStorageLedgerV1?
    private var scratch: ScratchDataLeaseStoreV1?

    init(ledger: OwnedStorageLedgerV1) { self.ledger = ledger }

    init(applicationSupportURL: URL, clock: @escaping ScratchDataLeaseStoreV1.Clock = { Date() },
         failureInjection: C16IngressMutationFailureInjectionV1 = .none) throws {
        ledger = nil
        scratch = try ScratchDataLeaseStoreV1(applicationSupportURL: applicationSupportURL, clock: clock,
            ingressMutationFailureInjection: failureInjection)
    }

    #if DEBUG
    init(applicationSupportURL: URL, clock: @escaping ScratchDataLeaseStoreV1.Clock = { Date() },
         failureInjection: C16IngressMutationFailureInjectionV1 = .none,
         testingIngressControlInventoryObserver: @escaping ScratchDataLeaseStoreV1.IngressControlInventoryObserver,
         testingBeforeIngressControlFinalInventory: @escaping ScratchDataLeaseStoreV1.BeforeIngressControlFinalInventory) throws {
        ledger = nil
        scratch = try ScratchDataLeaseStoreV1(applicationSupportURL: applicationSupportURL, clock: clock,
            ingressMutationFailureInjection: failureInjection,
            testingIngressControlInventoryObserver: testingIngressControlInventoryObserver,
            testingBeforeIngressControlFinalInventory: testingBeforeIngressControlFinalInventory)
    }
    #endif

    private func scratchOwner() throws -> ScratchDataLeaseStoreV1 {
        if let scratch { return scratch }
        guard let ledger else { throw AppAccessContractFailureV1.configurationUnknown }
        let owner = try ledger.scratchOwnerForHygiene()
        scratch = owner
        return owner
    }

    func performBlindStartupHygieneEffect(now: Date, operationID: UUID) throws -> ProtectedIngressStartupHygieneReceiptV1 {
        try scratchOwner().reconcileProtectedIngressHygiene(now: now, operationID: operationID)
    }

    func readBlindStartupHygieneReceiptEffect(operationID: UUID) throws -> ProtectedIngressStartupHygieneReceiptV1 {
        guard let value = try scratchOwner().readProtectedIngressHygieneReceipt(operationID: operationID) else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        return value
    }

    func loadPendingIntentsEffect() throws -> [PendingLockedExternalIntentV1] {
        try scratchOwner().pendingProtectedIngress()
    }
    func stageContentBlindEffect(_ request: ProtectedIngressStageRequestV1, source: URL) throws -> PendingLockedExternalIntentV1 {
        try scratchOwner().stageProtectedIngress(request, source: source)
    }
    func replacePendingIntentEffect(expected: PendingLockedExternalIntentV1, replacement: PendingLockedExternalIntentV1) throws {
        try scratchOwner().replaceProtectedIngress(expected: expected, replacement: replacement)
    }
    func removePendingIntentEffect(expected: PendingLockedExternalIntentV1, disposition: LockedIngressDispositionV1) throws {
        try scratchOwner().removeProtectedIngress(expected: expected, disposition: disposition)
    }
    func erasePendingIntentsEffect(operationID: UUID) throws {
        try scratchOwner().eraseProtectedIngress(operationID: operationID)
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
            guard let name = OwnedStorageDirectoryEntryNameV1.decode(entry) else {
                throw OwnedStorageLedgerFailureV1.invalidRoot
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

/// Startup before authentication may only remove confidently owned expired
/// scratch by metadata. It must never decode, traverse, index, or render
/// payloads; authenticated lifecycle recovery owns every richer operation.
enum WorkspaceExperiencePreAuthenticationScratchPolicyV1 {
    static let permitsBlindMetadataExpiryPurge = true
    static let permitsPayloadDecode = false
    static let permitsPayloadTraversal = false
    static let permitsPayloadIndexing = false
}

/// A close failure leaves the integer's kernel ownership uncertain. Keep the
/// attempted descriptor recorded for process life; never retry or use it as a
/// newly acquired descriptor. The original Erase EX/G owner also stays fenced.
private final class ScratchUncertainCloseQuarantineV1: @unchecked Sendable {
    static let shared = ScratchUncertainCloseQuarantineV1()
    private let lock = NSLock()
    private var attempted: [UUID: Int32] = [:]

    func begin(_ descriptor: Int32) -> UUID {
        let id = UUID()
        lock.withLock { attempted[id] = descriptor }
        return id
    }

    func complete(_ id: UUID) {
        lock.withLock { attempted.removeValue(forKey: id) }
    }
}

private final class PinnedScratchRootV1: @unchecked Sendable {
    private let operationsURL: URL
    private(set) var operationsDescriptor: Int32
    private(set) var rootDescriptor: Int32
    private var rootCloseAttempted = false
    private var operationsCloseAttempted = false
    let operationsDevice: UInt64
    let operationsInode: UInt64
    let rootDevice: UInt64
    let rootInode: UInt64

    init(operationsURL: URL, rootName: String) throws {
        self.operationsURL = operationsURL.standardizedFileURL
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
            let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(operationsDescriptor)
            if Darwin.close(operationsDescriptor) == 0 {
                ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
            }
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
            let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(operationsDescriptor)
            if Darwin.close(operationsDescriptor) == 0 {
                ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
            }
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        var root = stat()
        guard Darwin.fstat(rootDescriptor, &root) == 0,
              (root.st_mode & S_IFMT) == S_IFDIR,
              root.st_dev == operations.st_dev else {
            let rootAttempt = ScratchUncertainCloseQuarantineV1.shared.begin(rootDescriptor)
            if Darwin.close(rootDescriptor) == 0 {
                ScratchUncertainCloseQuarantineV1.shared.complete(rootAttempt)
            }
            let operationsAttempt = ScratchUncertainCloseQuarantineV1.shared.begin(operationsDescriptor)
            if Darwin.close(operationsDescriptor) == 0 {
                ScratchUncertainCloseQuarantineV1.shared.complete(operationsAttempt)
            }
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        rootDevice = UInt64(root.st_dev)
        rootInode = UInt64(root.st_ino)
    }

    deinit {
        if rootDescriptor >= 0 && !rootCloseAttempted { _ = Darwin.close(rootDescriptor) }
        if operationsDescriptor >= 0 && !operationsCloseAttempted { _ = Darwin.close(operationsDescriptor) }
    }

    func closeCheckedForExclusiveOriginalEraseRead(
        verifyBeforeClose: Bool = true,
        rootName: String = "ScratchDataV1"
    ) throws {
        if verifyBeforeClose { try verify(rootName: rootName) }
        let root = rootDescriptor
        rootCloseAttempted = true
        let rootAttempt = ScratchUncertainCloseQuarantineV1.shared.begin(root)
        var failed = false
        if Darwin.close(root) == 0 {
            ScratchUncertainCloseQuarantineV1.shared.complete(rootAttempt)
            rootDescriptor = -1
        } else {
            failed = true
        }
        let operations = operationsDescriptor
        operationsCloseAttempted = true
        let operationsAttempt = ScratchUncertainCloseQuarantineV1.shared.begin(operations)
        if Darwin.close(operations) == 0 {
            ScratchUncertainCloseQuarantineV1.shared.complete(operationsAttempt)
            operationsDescriptor = -1
        } else {
            failed = true
        }
        if failed { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
    }

    @MainActor func closeCheckedForSchema2BorrowedScope(
        verifyBeforeClose: Bool, rootName: String,
        requireHeld: @MainActor () throws -> Void
    ) throws {
        guard !rootCloseAttempted, !operationsCloseAttempted,
              rootDescriptor >= 0, operationsDescriptor >= 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        try requireHeld()
        if verifyBeforeClose { try verify(rootName: rootName) }
        try requireHeld()
        let root = rootDescriptor
        rootCloseAttempted = true
        let rootAttempt = ScratchUncertainCloseQuarantineV1.shared.begin(root)
        let rootResult = Darwin.close(root)
        // The retired numeric alias is never inspected or retried, including
        // a close whose result is ambiguous. Quarantine retains its receipt.
        rootDescriptor = -1
        guard rootResult == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        ScratchUncertainCloseQuarantineV1.shared.complete(rootAttempt)
        try requireHeld()
        let operations = operationsDescriptor
        operationsCloseAttempted = true
        let operationsAttempt = ScratchUncertainCloseQuarantineV1.shared.begin(operations)
        try requireHeld()
        let operationsResult = Darwin.close(operations)
        operationsDescriptor = -1
        guard operationsResult == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        ScratchUncertainCloseQuarantineV1.shared.complete(operationsAttempt)
        try requireHeld()
    }

    /// A failed postimage proof cannot allow deinit to silently close a live
    /// descriptor. Keep both aliases recorded and open for process life while
    /// the original operation remains poisoned under its retained owner.
    func quarantineUnclosedForOriginalErase() {
        if rootDescriptor >= 0 && !rootCloseAttempted {
            rootCloseAttempted = true
            _ = ScratchUncertainCloseQuarantineV1.shared.begin(rootDescriptor)
        }
        if operationsDescriptor >= 0 && !operationsCloseAttempted {
            operationsCloseAttempted = true
            _ = ScratchUncertainCloseQuarantineV1.shared.begin(operationsDescriptor)
        }
    }

    func verify(rootName: String) throws {
        guard !rootCloseAttempted, !operationsCloseAttempted,
              rootDescriptor >= 0, operationsDescriptor >= 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        var operations = stat()
        var linkedOperations = stat()
        var root = stat()
        var child = stat()
        guard Darwin.fstat(operationsDescriptor, &operations) == 0,
              UInt64(operations.st_dev) == operationsDevice,
              UInt64(operations.st_ino) == operationsInode,
              Darwin.lstat(operationsURL.path, &linkedOperations) == 0,
              (linkedOperations.st_mode & S_IFMT) == S_IFDIR,
              UInt64(linkedOperations.st_dev) == operationsDevice,
              UInt64(linkedOperations.st_ino) == operationsInode,
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

enum AppLockNotificationControlFailurePointV1: Equatable, Sendable {
    case none, afterPreferenceWrite, afterPendingWriteBeforeSync, afterReminderPreferenceWrite
}

/// Sole descriptor-pinned notification control and private correlation owner.
/// Authentication and OS observation remain the concrete effect's responsibility.
#if DEBUG
struct ErasePostRetiredNotificationSnapshotV1: Equatable {
    let rootDigest: String
}

struct EraseOriginalNotificationPhysicalSnapshotV1: Equatable {
    let rootDevice: UInt64?
    let rootInode: UInt64?
    let rootMetadata: String?
    let names: [String]
    let unchangedLeavesDigest: String?
    let eraseBytes: Data?
    let eraseIdentity: String?
}
#endif

/// A complete checked cut of the cold notification root. The first cut is
/// retained by Manifest; each owned effect produces a separate checked cut
/// and may project only its exact stage-specific difference.
struct EraseSchema2ColdNotificationCheckedCutV1: Equatable {
    let rootFact: EraseColdControlLeafFactV1?
    let names: [String]
    let leafBytes: [String: Data]
    let leafFacts: [String: EraseColdControlLeafFactV1]
}

/// Storage constructs this only after its exact syscall, fsync, policy
/// readback and every transient checked close. Manifest independently scans
/// the same held root before accepting a one-way projection.
@MainActor final class EraseSchema2ColdNotificationMutationReceiptV1 {
    let token: EraseSchema2ColdNotificationMutationTokenV1
    let stage: EraseSchema2ColdNotificationMutationStageV1
    let before: EraseSchema2ColdNotificationCheckedCutV1
    let after: EraseSchema2ColdNotificationCheckedCutV1
    let temporaryFact: EraseColdControlLeafFactV1?
    /// Non-nil only when the first held empty/canonical-prefix temp was
    /// checked-unlinked, fsynced and proved absent before O_EXCL rewrite.
    let settledCapturedTemporaryFact: EraseColdControlLeafFactV1?
    let policyDisposition: ProtectedFileVerificationDispositionV1?
    let checkedSettled: Bool

    fileprivate init(token: EraseSchema2ColdNotificationMutationTokenV1,
        before: EraseSchema2ColdNotificationCheckedCutV1,
        after: EraseSchema2ColdNotificationCheckedCutV1,
        temporaryFact: EraseColdControlLeafFactV1?,
        settledCapturedTemporaryFact:
            EraseColdControlLeafFactV1? = nil,
        policyDisposition: ProtectedFileVerificationDispositionV1?) {
        self.token = token
        stage = token.stage
        self.before = before
        self.after = after
        self.temporaryFact = temporaryFact
        self.settledCapturedTemporaryFact =
            settledCapturedTemporaryFact
        self.policyDisposition = policyDisposition
        checkedSettled = true
    }
}

final class AppLockNotificationControlStoreV1: @unchecked Sendable {
    static let rootName = "AppLockNotificationControlV1"
    static let recordName = "control.json"
    static let pendingName = "control.pending.json"
    static let maximumRecordBytes = 1_048_576
    static let mappingName = "mapping.json"
    static let mappingPendingName = "mapping.pending.json"
    static let eraseName = "notification-erase.json"
    static let erasePendingName = "notification-erase.pending.json"
    private let preferences: PreferencesAdapterV1
    private let supportURL: URL
    private let supportDescriptor: Int32
    private let supportDevice: UInt64
    private let supportInode: UInt64
    private let authority: PinnedScratchRootV1
    private let failurePoint: AppLockNotificationControlFailurePointV1
    private let originalErasePolicyIO: EraseAbortCheckedSnapshotIOV1?
    private var originalEraseSupportCloseAttempted = false
    private(set) var originalEraseCheckedCloseComplete = false

    /// Minted from a live, exact predecessor before the first publication
    /// effect. Disk bytes alone cannot register a scheduling owner.
    final class NotificationSchedulingPublicationOwner {
        let request: NotificationSystemRequestV1
        let admissionID: UUID
        let activity: OwnedStorageProducerActivityV1
        let rootIdentity: String
        fileprivate weak var store: AppLockNotificationControlStoreV1?
        fileprivate let predecessor: NotificationPrivateMappingV1
        fileprivate let admitted: NotificationPrivateMappingV1
        fileprivate let present: NotificationPrivateMappingV1
        fileprivate let absent: NotificationPrivateMappingV1
        fileprivate let p: Data, a: Data, t: Data, f: Data
        fileprivate var canonicalFact: stat
        fileprivate var stage: SchedulingStage?
        fileprivate var uncertainClose = false
        fileprivate(set) var addAttempted = false
        fileprivate var retired = false

        fileprivate init(store: AppLockNotificationControlStoreV1,
            predecessor: NotificationPrivateMappingV1,
            admitted: NotificationPrivateMappingV1,
            present: NotificationPrivateMappingV1,
            absent: NotificationPrivateMappingV1,
            request: NotificationSystemRequestV1, admissionID: UUID,
            activity: OwnedStorageProducerActivityV1,
            bytes: [Data], canonicalFact: stat) {
            self.store = store; self.predecessor = predecessor
            self.admitted = admitted; self.present = present; self.absent = absent
            self.request = request; self.admissionID = admissionID
            self.activity = activity; rootIdentity = store.notificationRootIdentity
            p = bytes[0]; a = bytes[1]; t = bytes[2]; f = bytes[3]
            self.canonicalFact = canonicalFact
        }
    }

    fileprivate final class SchedulingStage {
        let descriptor: Int32
        let bytes: Data
        let predecessor: Data
        // These are recorded immediately after actual effects, before reproof.
        var prefixCount = 0
        var positiveWriteCounts: [Int] = []
        var fact: stat?
        var anchor: stat?
        var postEffectSamplePending = false
        var name = AppLockNotificationControlStoreV1.mappingPendingName
        var policyRequested = false
        var initialPolicyVerified = false
        var initialPolicyDisposition: ProtectedFileVerificationDispositionV1?
        var finalPolicyVerified = false
        var fileSynced = false
        var renamed = false
        var parentSynced = false
        var renameAttempted = false
        var unlinkAttempted = false
        var fileSyncAttempted = false
        var parentSyncAttempted = false
        var removed = false
        var closeAttempted = false
        init(descriptor: Int32, bytes: Data, predecessor: Data) {
            self.descriptor = descriptor; self.bytes = bytes
            self.predecessor = predecessor
        }
    }

#if DEBUG
    enum NotificationSchedulingPublicationPhaseForTesting: Equatable {
        case admission, finishPresent, finishAbsent
    }
    enum NotificationSchedulingPublicationCutForTesting: Equatable {
        case afterStageOpenBeforeFirstFact
        case beforeInitialPolicyEffect
        case afterInitialPolicyEffectBeforeVerification
        case afterInitialPolicyVerificationBeforeWrite
        case afterPositivePrefix(Int)
        case afterFullWriteBeforeFinalPolicy
        case afterFinalPolicyBeforeFileSync
        case beforeRename
        case afterRenameBeforeParentSync
        case afterParentSyncBeforeReadback
        case beforeCheckedStageClose
    }
    struct NotificationSchedulingPublicationFaultForTesting {
        let phase: NotificationSchedulingPublicationPhaseForTesting
        let cut: NotificationSchedulingPublicationCutForTesting
    }
    struct NotificationSchedulingPublicationFaultObservationForTesting {
        let phase: NotificationSchedulingPublicationPhaseForTesting
        let cut: NotificationSchedulingPublicationCutForTesting
        let admissionID: UUID
        let requestID: String
        let actualWrittenPrefixCount: Int
        let initialPolicyVerified: Bool
        let finalPolicyVerified: Bool
        let renamed: Bool
    }
#endif

    // Access is exclusively under the existing synchronous transaction fence.
    // This is a process writer claim, never a content authorization or disk owner.
    private final class SchedulingOwners: @unchecked Sendable {
        var live: [String: NotificationSchedulingPublicationOwner] = [:]
#if DEBUG
        var faults: [String: NotificationSchedulingPublicationFaultForTesting] = [:]
        var faultObservations: [String: NotificationSchedulingPublicationFaultObservationForTesting] = [:]
#endif
    }
    private static let schedulingOwners = SchedulingOwners()

    private static func retainOriginalEraseUncertainPolicyDescriptor(
        _ descriptor: Int32, io: EraseAbortCheckedSnapshotIOV1
    ) {
        io.retainUncertainDescriptor(descriptor)
        _ = ScratchUncertainCloseQuarantineV1.shared.begin(descriptor)
    }
#if DEBUG
    private let postRetiredIO = EraseAbortCheckedSnapshotIOV1()
#endif

    init(applicationSupportURL: URL, preferences: PreferencesAdapterV1,
         failurePoint: AppLockNotificationControlFailurePointV1 = .none,
         mustExistForOriginalErase: Bool = false) throws {
        guard applicationSupportURL.isFileURL else { throw AppAccessContractFailureV1.configurationUnknown }
        self.preferences = preferences
        supportURL = applicationSupportURL.standardizedFileURL
        self.failurePoint = failurePoint
        let policyIO = mustExistForOriginalErase
            ? EraseAbortCheckedSnapshotIOV1() : nil
        originalErasePolicyIO = policyIO
        let opened = try AppLockNotificationTransactionFenceV1.perform {
            try Self.openRoot(applicationSupportURL.standardizedFileURL,
                mustExistForOriginalErase: mustExistForOriginalErase,
                originalErasePolicyIO: policyIO)
        }
        supportDescriptor = opened.support
        supportDevice = opened.device
        supportInode = opened.inode
        authority = opened.authority
    }

    deinit {
        if !originalEraseSupportCloseAttempted {
            if originalErasePolicyIO == nil {
                _ = Darwin.close(supportDescriptor)
            } else {
                let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(
                    supportDescriptor)
                if Darwin.close(supportDescriptor) == 0 {
                    ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
                }
            }
        }
    }

    /// The notification scheduling owner retains this child SH only across
    /// its reconcile admission, OS add, readback and settlement. This Store
    /// itself never owns a lifetime producer SH; original Erase EX is a
    /// separate route and cannot request a scheduling child.
    func acquireNotificationSchedulingActivity() throws
        -> OwnedStorageProducerActivityV1 {
        try AppLockNotificationTransactionFenceV1.perform {
            guard originalErasePolicyIO == nil else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            try verifyRoot()
            var supportBefore = stat(), namedSupportBefore = stat()
            guard Darwin.fstat(supportDescriptor, &supportBefore) == 0,
                  Darwin.lstat(supportURL.path,
                    &namedSupportBefore) == 0,
                  Self.sameOriginalEraseRootFact(
                    supportBefore, namedSupportBefore) else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            let rootBefore = try Self.originalEraseHeldNamedRootFact(
                authority: authority, url: rootURL)
            let child = try OwnedStorageProducerActivityV1.acquire(
                applicationSupportURL: supportURL)
            do {
                try child.requireApplicationSupport(supportURL)
                try verifyRoot()
                var supportAfter = stat(), namedSupportAfter = stat()
                guard Darwin.fstat(supportDescriptor, &supportAfter) == 0,
                      Darwin.lstat(supportURL.path,
                        &namedSupportAfter) == 0,
                      Self.sameOriginalEraseRootFact(
                        supportBefore, supportAfter),
                      Self.sameOriginalEraseRootFact(
                        supportBefore, namedSupportAfter),
                      Self.sameOriginalEraseRootFact(rootBefore,
                        try Self.originalEraseHeldNamedRootFact(
                            authority: authority, url: rootURL)) else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
                return child
            } catch {
                child.close()
                throw error
            }
        }
    }

    /// The original owner must call this before releasing its retained EX.
    /// A failed close is quarantined and cannot be retried using its number.
    func closeCheckedForOriginalErase() throws {
        guard let originalErasePolicyIO,
              !originalEraseSupportCloseAttempted else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try verifyRoot()
        try originalErasePolicyIO.requireSettled()
        try authority.closeCheckedForExclusiveOriginalEraseRead(
            verifyBeforeClose: false)
        originalEraseSupportCloseAttempted = true
        let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(
            supportDescriptor)
        guard Darwin.close(supportDescriptor) == 0 else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
        originalEraseCheckedCloseComplete = true
    }

#if DEBUG
    /// Pre-deletion Erase retains the typed revocation marker after OS absence
    /// readback. Completed-Erase adoption separately requires all six leaves
    /// absent after the Operations namespace is removed.
    func postRetiredSnapshot(subject: EraseAllOperationSubjectV1) throws
        -> ErasePostRetiredNotificationSnapshotV1 {
        try AppLockNotificationTransactionFenceV1.perform {
            guard subject.applicationSupportURL.standardizedFileURL == supportURL,
                  let expectedDevice = UInt64(exactly: subject.applicationSupportDevice),
                  expectedDevice == supportDevice,
                  subject.applicationSupportInode == supportInode else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            let revocation = NotificationEraseRevocationV1(schemaVersion: 1,
                operationID: subject.eraseID, rootIdentity: notificationRootIdentity)
            try revocation.validate()
            let expectedBytes = try CompatibilityCanonicalV1.encode(revocation)
            let before = try originalErasePhysicalSnapshotForTesting()
            guard before.names == [Self.eraseName],
                  before.eraseBytes == expectedBytes,
                  before.eraseIdentity != nil else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            let digest = try postRetiredIO.postRetiredTree(
                parent: authority.operationsDescriptor, name: Self.rootName)
            guard try originalErasePhysicalSnapshotForTesting() == before,
                  try postRetiredIO.postRetiredTree(
                      parent: authority.operationsDescriptor,
                      name: Self.rootName) == digest else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            return ErasePostRetiredNotificationSnapshotV1(rootDigest: digest)
        }
    }

    /// Nonrepairing six-leaf observation of the exact original Operations
    /// owner. The revocation leaf is separate so its one typed create edge can
    /// be proved without accepting changes to the other five leaves.
    static func originalErasePhysicalSnapshotForTesting(
        operationsDescriptor: Int32,
        io: EraseAbortCheckedSnapshotIOV1
    ) throws -> EraseOriginalNotificationPhysicalSnapshotV1 {
        var named = stat()
        let found = Darwin.fstatat(operationsDescriptor, Self.rootName,
            &named, AT_SYMLINK_NOFOLLOW)
        if found != 0, errno == ENOENT {
            return EraseOriginalNotificationPhysicalSnapshotV1(
                rootDevice: nil, rootInode: nil, rootMetadata: nil,
                names: [],
                unchangedLeavesDigest: nil, eraseBytes: nil,
                eraseIdentity: nil)
        }
        guard found == 0, named.st_mode & S_IFMT == S_IFDIR else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        return try io.withOpen(parent: operationsDescriptor,
                               name: Self.rootName,
                               flags: O_RDONLY | O_DIRECTORY) { root in
            var held = stat(), after = stat(), renamed = stat()
            guard Darwin.fstat(root, &held) == 0,
                  held.st_dev == named.st_dev, held.st_ino == named.st_ino
            else { throw AppAccessContractFailureV1.configurationUnknown }
            let names = try io.names(in: root)
            let allowed = Set([
                Self.recordName, Self.pendingName,
                Self.mappingName, Self.mappingPendingName,
                Self.eraseName, Self.erasePendingName
            ])
            guard Set(names).isSubset(of: allowed),
                  !names.contains(Self.pendingName),
                  !names.contains(Self.mappingPendingName),
                  !names.contains(Self.erasePendingName) else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            let erase = names.contains(Self.eraseName)
                ? try io.control(parent: root, name: Self.eraseName) : nil
            let unchanged = try io.postRetiredTree(
                parent: operationsDescriptor, name: Self.rootName,
                excluding: [Self.eraseName],
                ignoringDirectoryMetadata: [""])
            guard try io.names(in: root) == names,
                  Darwin.fstat(root, &after) == 0,
                  Darwin.fstatat(operationsDescriptor, Self.rootName,
                    &renamed, AT_SYMLINK_NOFOLLOW) == 0,
                  held.st_dev == after.st_dev,
                  held.st_ino == after.st_ino,
                  held.st_dev == renamed.st_dev,
                  held.st_ino == renamed.st_ino,
                  held.st_mode == after.st_mode,
                  held.st_nlink == after.st_nlink,
                  held.st_size == after.st_size,
                  held.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
                  held.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
                  held.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
                  held.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            let rootMetadata = "\(held.st_dev)|\(held.st_ino)|\(held.st_mode)|\(held.st_nlink)|\(held.st_size)|\(held.st_mtimespec.tv_sec)|\(held.st_mtimespec.tv_nsec)|\(held.st_ctimespec.tv_sec)|\(held.st_ctimespec.tv_nsec)"
            return EraseOriginalNotificationPhysicalSnapshotV1(
                rootDevice: UInt64(held.st_dev),
                rootInode: UInt64(held.st_ino),
                rootMetadata: rootMetadata,
                names: names,
                unchangedLeavesDigest: unchanged,
                eraseBytes: erase?.0,
                eraseIdentity: erase?.1)
        }
    }

    func originalErasePhysicalSnapshotForTesting() throws
        -> EraseOriginalNotificationPhysicalSnapshotV1 {
        try verifyRoot()
        let value = try Self.originalErasePhysicalSnapshotForTesting(
            operationsDescriptor: authority.operationsDescriptor,
            io: postRetiredIO)
        guard value.rootDevice == UInt64(authority.rootDevice),
              value.rootInode == UInt64(authority.rootInode) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try verifyRoot()
        return value
    }
#endif

    var notificationRootIdentity: String {
        "\(supportDevice):\(supportInode):\(authority.rootDevice):\(authority.rootInode)"
    }

    func verifyNotificationStorage() throws {
        try AppLockNotificationTransactionFenceV1.perform { try verifyRoot() }
    }

    func requireEmptyForCompletedErase(subject: EraseAllOperationSubjectV1) throws {
        try AppLockNotificationTransactionFenceV1.perform {
            guard subject.applicationSupportURL.standardizedFileURL == supportURL,
                  let expectedDevice = UInt64(exactly: subject.applicationSupportDevice),
                  expectedDevice == supportDevice,
                  subject.applicationSupportInode == supportInode else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            try verifyRoot()
            for name in [Self.recordName, Self.pendingName, Self.mappingName,
                         Self.mappingPendingName, Self.eraseName, Self.erasePendingName] {
                guard try information(name) == nil else {
                    throw AppAccessContractFailureV1.notificationReconciliationRequired
                }
            }
            try verifyRoot()
        }
    }

    func requireNotificationPublicationAllowed() throws {
        try AppLockNotificationTransactionFenceV1.perform {
            try verifyRoot()
            guard try information(Self.eraseName) == nil,
                  try information(Self.erasePendingName) == nil else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
        }
    }

    /// Only the effect may call this after validating its original proof, or
    /// during explicitly authorized destructive erase. Bootstrap never calls it.
    func loadPrivateNotificationMapping() throws -> NotificationPrivateMappingV1? {
        try AppLockNotificationTransactionFenceV1.perform {
            guard let bytes = try readFile(Self.mappingName, kind: .journal) else { return nil }
            let value = try Self.decodeAuxiliary(NotificationPrivateMappingV1.self, bytes: bytes)
            try value.validate()
            return value
        }
    }

    func replacePrivateNotificationMapping(_ value: NotificationPrivateMappingV1,
                                           expected: NotificationPrivateMappingV1?) throws {
        try AppLockNotificationTransactionFenceV1.perform {
            guard Self.schedulingOwners.live[notificationRootIdentity] == nil else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            try requireNotificationPublicationAllowed()
            try value.validate()
            guard try loadPrivateNotificationMapping() == expected else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            try publishBytes(CompatibilityCanonicalV1.encode(value), recordName: Self.mappingName,
                pendingName: Self.mappingPendingName,
                expected: expected.map { try CompatibilityCanonicalV1.encode($0) })
        }
    }

    func makeNotificationSchedulingPublicationOwner(
        predecessor: NotificationPrivateMappingV1,
        request: NotificationSystemRequestV1, admissionID: UUID,
        activity: OwnedStorageProducerActivityV1
    ) throws -> NotificationSchedulingPublicationOwner {
        try AppLockNotificationTransactionFenceV1.perform {
            guard originalErasePolicyIO == nil else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            try requireNotificationPublicationAllowed()
            try activity.requireApplicationSupport(supportURL)
            try predecessor.validate(); try request.validate()
            guard Self.schedulingOwners.live[notificationRootIdentity] == nil,
                  admissionID != SettingsValidationV1.zeroUUID,
                  predecessor.entries.allSatisfy({ $0.admissionID == nil }),
                  let index = predecessor.entries.firstIndex(where: { $0.request == request }),
                  try schedulingRawInformation(Self.mappingPendingName) == nil
            else { throw AppAccessContractFailureV1.notificationReconciliationRequired }
            var admitted = predecessor
            admitted.entries[index].admissionID = admissionID
            admitted.entries[index].acknowledged = false
            var present = admitted, absent = admitted
            present.entries[index].admissionID = nil
            present.entries[index].acknowledged = true
            absent.entries[index].admissionID = nil
            absent.entries[index].acknowledged = false
            try admitted.validate(); try present.validate(); try absent.validate()
            let bytes = try [predecessor, admitted, present, absent].map {
                try CompatibilityCanonicalV1.encode($0)
            }
            guard let current = try schedulingReadCanonical(), current.0 == bytes[0]
            else { throw AppAccessContractFailureV1.effectMismatch }
            let owner = NotificationSchedulingPublicationOwner(store: self,
                predecessor: predecessor, admitted: admitted, present: present,
                absent: absent, request: request, admissionID: admissionID,
                activity: activity, bytes: bytes, canonicalFact: current.1)
            Self.schedulingOwners.live[notificationRootIdentity] = owner
            return owner
        }
    }

    func requireNotificationSchedulingState(_ owner: NotificationSchedulingPublicationOwner) throws {
        try AppLockNotificationTransactionFenceV1.perform {
            _ = try schedulingState(owner)
        }
    }

    func publishNotificationSchedulingAdmission(_ owner: NotificationSchedulingPublicationOwner) throws {
        try AppLockNotificationTransactionFenceV1.perform {
            try requireNotificationPublicationAllowed()
            guard try schedulingState(owner) == owner.p, owner.stage == nil,
                  !owner.addAttempted else { throw AppAccessContractFailureV1.effectMismatch }
            try publishBytes(owner.a, recordName: Self.mappingName,
                pendingName: Self.mappingPendingName, expected: owner.p,
                schedulingOwner: owner)
        }
    }

    /// Called synchronously immediately before entering the actual OS add.
    /// Minting and publishing admission are deliberately not add attempts.
    func noteNotificationSchedulingAddAttempt(_ owner: NotificationSchedulingPublicationOwner) throws {
        try AppLockNotificationTransactionFenceV1.perform {
            try requireNotificationPublicationAllowed()
            guard try schedulingState(owner) == owner.a, owner.stage == nil,
                  !owner.addAttempted else { throw AppAccessContractFailureV1.effectMismatch }
            owner.addAttempted = true
        }
    }

    func finishNotificationSchedulingAdd(_ owner: NotificationSchedulingPublicationOwner,
        verifiedPresent: Bool) throws {
        try AppLockNotificationTransactionFenceV1.perform {
            if verifiedPresent {
                guard owner.addAttempted else { throw AppAccessContractFailureV1.effectMismatch }
            }
            guard try schedulingState(owner) == owner.a, owner.stage == nil
            else { throw AppAccessContractFailureV1.effectMismatch }
            try publishBytes(verifiedPresent ? owner.t : owner.f,
                recordName: Self.mappingName, pendingName: Self.mappingPendingName,
                expected: owner.a, schedulingOwner: owner)
        }
    }

    /// The concrete Workflow first removes only this request and observes real
    /// pending/delivered absence. This source-free tail cannot add or renew consent.
    func settleNotificationSchedulingAbsent(_ owner: NotificationSchedulingPublicationOwner) throws {
        try AppLockNotificationTransactionFenceV1.perform {
            var current = try schedulingState(owner)
            if let stage = owner.stage {
                if !stage.renamed && !stage.removed {
                    _ = try schedulingState(owner)
                    stage.unlinkAttempted = true
                    guard Darwin.unlinkat(authority.rootDescriptor,
                        Self.mappingPendingName, 0) == 0 else {
                        throw AppAccessContractFailureV1.notificationReconciliationRequired
                    }
                    stage.removed = true
                    schedulingRecordFact(stage)
                    stage.parentSyncAttempted = true
                    guard Darwin.fsync(authority.rootDescriptor) == 0 else {
                        throw AppAccessContractFailureV1.notificationReconciliationRequired
                    }
                    stage.parentSynced = true
                }
                try schedulingCompleteStage(owner)
                current = try schedulingState(owner)
            }
            if current != owner.f {
                try publishBytes(owner.f, recordName: Self.mappingName,
                    pendingName: Self.mappingPendingName, expected: current,
                    schedulingOwner: owner)
            }
            try requireNotificationSchedulingTerminal(owner, verifiedPresent: false)
        }
    }

    func requireNotificationSchedulingTerminal(_ owner: NotificationSchedulingPublicationOwner,
        verifiedPresent: Bool) throws {
        try AppLockNotificationTransactionFenceV1.perform {
            guard try schedulingState(owner) == (verifiedPresent ? owner.t : owner.f),
                  owner.stage == nil else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            // A terminal byte observation does not substitute for durability.
            let file = Darwin.openat(authority.rootDescriptor, Self.mappingName,
                O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard file >= 0 else { throw AppAccessContractFailureV1.configurationUnknown }
            var closeAttempted = false
            do {
                var held = stat()
                guard Darwin.fstat(file, &held) == 0,
                      Self.sameFile(held, owner.canonicalFact) else {
                    throw AppAccessContractFailureV1.effectMismatch
                }
                _ = try schedulingState(owner)
                guard Darwin.fsync(file) == 0,
                      Darwin.fsync(authority.rootDescriptor) == 0 else {
                    throw AppAccessContractFailureV1.notificationReconciliationRequired
                }
                _ = try schedulingState(owner)
                closeAttempted = true
                try schedulingClose(file, owner: owner)
            } catch {
                if !closeAttempted { try? schedulingClose(file, owner: owner) }
                throw error
            }
        }
    }

    /// Retires the process writer claim only. It is not a checked SH-release
    /// receipt; that resource belongs to the concrete Workflow owner.
    func retireNotificationSchedulingPublicationOwner(_ owner: NotificationSchedulingPublicationOwner,
        verifiedPresent: Bool) throws {
        try AppLockNotificationTransactionFenceV1.perform {
            try requireNotificationSchedulingTerminal(owner, verifiedPresent: verifiedPresent)
            owner.retired = true
            Self.schedulingOwners.live.removeValue(forKey: owner.rootIdentity)
        }
    }

    private func requireSchedulingOwner(_ owner: NotificationSchedulingPublicationOwner) throws {
        guard owner.store === self, !owner.retired, !owner.uncertainClose,
              owner.rootIdentity == notificationRootIdentity,
              Self.schedulingOwners.live[notificationRootIdentity] === owner else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        try owner.activity.requireApplicationSupport(supportURL)
        try verifyRoot()
        _ = try Self.originalEraseHeldNamedRootFact(authority: authority, url: rootURL)
        for name in [Self.pendingName, Self.erasePendingName] {
            guard try schedulingRawInformation(name) == nil else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
        }
    }

    // Unlike ordinary information(), zero length is a valid known open cut.
    private func schedulingRawInformation(_ name: String) throws -> stat? {
        var fact = stat()
        if Darwin.fstatat(authority.rootDescriptor, name, &fact, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else { throw AppAccessContractFailureV1.configurationUnknown }
            return nil
        }
        guard fact.st_mode & S_IFMT == S_IFREG, fact.st_nlink == 1,
              fact.st_uid == Darwin.geteuid(), UInt64(fact.st_dev) == authority.rootDevice,
              fact.st_size >= 0, fact.st_size <= Int64(Self.maximumRecordBytes) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        return fact
    }

    private func schedulingClose(_ file: Int32,
        owner: NotificationSchedulingPublicationOwner?) throws {
        let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(file)
        guard Darwin.close(file) == 0 else {
            owner?.uncertainClose = true
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
    }

    private func schedulingBytes(_ file: Int32, count: Int) throws -> Data {
        var bytes = Data(count: count), offset = 0
        while offset < count {
            let read = bytes.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return 0 }
                return Darwin.pread(file, base.advanced(by: offset), count - offset, off_t(offset))
            }
            if read < 0, errno == EINTR { continue }
            guard read > 0 else { throw AppAccessContractFailureV1.configurationUnknown }
            offset += read
        }
        return bytes
    }

    private func schedulingReadCanonical(_ owner: NotificationSchedulingPublicationOwner? = nil)
        throws -> (Data, stat)? {
        guard let named = try schedulingRawInformation(Self.mappingName) else { return nil }
        guard named.st_size > 0 else { throw AppAccessContractFailureV1.effectMismatch }
        let file = Darwin.openat(authority.rootDescriptor, Self.mappingName,
            O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard file >= 0 else { throw AppAccessContractFailureV1.configurationUnknown }
        var closeAttempted = false
        do {
            var held = stat(), after = stat()
            guard Darwin.fstat(file, &held) == 0, Self.sameFile(named, held) else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            let bytes = try schedulingBytes(file, count: Int(held.st_size))
            guard Darwin.fstat(file, &after) == 0, Self.sameFile(held, after),
                  let final = try schedulingRawInformation(Self.mappingName),
                  Self.sameFile(held, final) else { throw AppAccessContractFailureV1.effectMismatch }
            let observed = try ProtectedFilePolicyV1.observeTemporalPolicyWithCheckedClose(
                .journal, at: rootURL.appendingPathComponent(Self.mappingName),
                retainUncertainDescriptor: { descriptor in
                    owner?.uncertainClose = true
                    _ = ScratchUncertainCloseQuarantineV1.shared.begin(descriptor)
                })
            guard observed.device == UInt64(held.st_dev), observed.inode == UInt64(held.st_ino),
                  observed.backupExcluded == true,
                  observed.state == .strictComplete || observed.state == .pendingSimulatorRequest else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            guard Darwin.fstat(file, &after) == 0, Self.sameFile(held, after),
                  let final = try schedulingRawInformation(Self.mappingName),
                  Self.sameFile(held, final), owner?.uncertainClose != true else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            closeAttempted = true
            try schedulingClose(file, owner: owner)
            return (bytes, held)
        } catch {
            if !closeAttempted { try? schedulingClose(file, owner: owner) }
            throw error
        }
    }

    private func schedulingState(_ owner: NotificationSchedulingPublicationOwner) throws -> Data {
        try requireSchedulingOwner(owner)
        guard let canonical = try schedulingReadCanonical(owner),
              [owner.p, owner.a, owner.t, owner.f].contains(canonical.0) else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        let pending = try schedulingRawInformation(Self.mappingPendingName)
        if let stage = owner.stage {
            guard !stage.closeAttempted else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            var held = stat()
            guard Darwin.fstat(stage.descriptor, &held) == 0,
                  held.st_mode & S_IFMT == S_IFREG,
                  held.st_uid == Darwin.geteuid(), UInt64(held.st_dev) == authority.rootDevice,
                  held.st_size == Int64(stage.prefixCount),
                  try schedulingBytes(stage.descriptor, count: stage.prefixCount)
                    == Data(stage.bytes.prefix(stage.prefixCount)) else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            var afterRead = stat()
            guard Darwin.fstat(stage.descriptor, &afterRead) == 0,
                  Self.sameFile(held, afterRead) else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            // A failed first sample cannot permit a write. The actual retained
            // O_EXCL descriptor may acquire its positive creation anchor only
            // before any subsequent effect, with its empty held/named leaf.
            if stage.anchor == nil {
                guard stage.prefixCount == 0, !stage.policyRequested,
                      !stage.fileSyncAttempted, !stage.renameAttempted,
                      !stage.unlinkAttempted, let pending,
                      held.st_nlink == 1, Self.sameFile(held, pending) else {
                    throw AppAccessContractFailureV1.notificationReconciliationRequired
                }
                stage.anchor = held; stage.fact = held
            }
            guard let anchor = stage.anchor,
                  held.st_dev == anchor.st_dev, held.st_ino == anchor.st_ino,
                  held.st_mode == anchor.st_mode, held.st_uid == anchor.st_uid,
                  held.st_gid == anchor.st_gid,
                  held.st_nlink == (stage.removed ? 0 : anchor.st_nlink),
                  anchor.st_nlink == 1 else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            // Only an actually recorded write/policy/namespace effect can
            // account for its size/time transition when immediate sampling
            // failed. It cannot account for owner/mode/link or byte drift.
            if stage.postEffectSamplePending {
                stage.fact = held; stage.postEffectSamplePending = false
            }
            guard let recorded = stage.fact, Self.sameFile(held, recorded) else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            if !stage.renamed {
                guard Self.sameFile(canonical.1, owner.canonicalFact) else {
                    throw AppAccessContractFailureV1.effectMismatch
                }
            }
            if stage.removed {
                guard pending == nil, held.st_nlink == 0,
                      canonical.0 == stage.predecessor else {
                    throw AppAccessContractFailureV1.effectMismatch
                }
            } else if stage.renamed {
                guard pending == nil, Self.sameFile(held, canonical.1),
                      canonical.0 == stage.bytes, stage.prefixCount == stage.bytes.count else {
                    throw AppAccessContractFailureV1.effectMismatch
                }
                owner.canonicalFact = canonical.1
            } else {
                guard let pending, Self.sameFile(held, pending),
                      canonical.0 == stage.predecessor,
                      (canonical.0 == owner.p && stage.bytes == owner.a)
                        || (canonical.0 == owner.a && (stage.bytes == owner.t || stage.bytes == owner.f))
                        || ([owner.p, owner.t, owner.f].contains(canonical.0) && stage.bytes == owner.f)
                else { throw AppAccessContractFailureV1.effectMismatch }
            }
        } else {
            guard pending == nil, Self.sameFile(canonical.1, owner.canonicalFact) else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
        }
        try requireSchedulingOwner(owner)
        return canonical.0
    }

    private func schedulingRecordFact(_ stage: SchedulingStage,
        afterOwnedEffect: Bool = true) {
        // Retain the last positive fact on failed sampling. A subsequent
        // reproof must explicitly resolve the actual known effect's cut.
        stage.postEffectSamplePending = afterOwnedEffect
        var fact = stat()
        if Darwin.fstat(stage.descriptor, &fact) == 0 {
            if !afterOwnedEffect, let previous = stage.fact,
               !Self.sameFile(previous, fact) { return }
            stage.fact = fact
            if stage.anchor == nil, !afterOwnedEffect { stage.anchor = fact }
            stage.postEffectSamplePending = false
        }
    }

#if DEBUG
    /// A one-shot DEBUG cut on the real same-process publisher. Configuration
    /// binds the existing pinned root and cannot alter a live owner's inputs.
    func setNotificationSchedulingPublicationFaultForTesting(
        _ fault: NotificationSchedulingPublicationFaultForTesting?
    ) throws {
        try AppLockNotificationTransactionFenceV1.perform {
            try verifyRoot()
            guard originalErasePolicyIO == nil,
                  Self.schedulingOwners.live[notificationRootIdentity] == nil else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            if let fault, case .afterPositivePrefix(let count) = fault.cut {
                guard count > 0, count < Self.maximumRecordBytes else {
                    throw AppAccessContractFailureV1.invalidValue
                }
            }
            Self.schedulingOwners.faults[notificationRootIdentity] = fault
            Self.schedulingOwners.faultObservations.removeValue(forKey: notificationRootIdentity)
        }
    }

    func notificationSchedulingPublicationFaultObservationForTesting() throws
        -> NotificationSchedulingPublicationFaultObservationForTesting? {
        try AppLockNotificationTransactionFenceV1.perform {
            try verifyRoot()
            return Self.schedulingOwners.faultObservations[notificationRootIdentity]
        }
    }

    private func schedulingPhaseForTesting(_ owner: NotificationSchedulingPublicationOwner,
        stage: SchedulingStage) -> NotificationSchedulingPublicationPhaseForTesting {
        if stage.bytes == owner.a { return .admission }
        if stage.bytes == owner.t { return .finishPresent }
        return .finishAbsent
    }

    private func schedulingTestingCut(_ owner: NotificationSchedulingPublicationOwner,
        stage: SchedulingStage, cut: NotificationSchedulingPublicationCutForTesting) throws {
        let phase = schedulingPhaseForTesting(owner, stage: stage)
        guard let fault = Self.schedulingOwners.faults[owner.rootIdentity],
              fault.phase == phase, fault.cut == cut else { return }
        // Consumption/observation precede the deterministic throw. Recovery
        // cannot repeatedly hit this cut or discard any unknown disk leaf.
        Self.schedulingOwners.faults.removeValue(forKey: owner.rootIdentity)
        Self.schedulingOwners.faultObservations[owner.rootIdentity] = .init(
            phase: phase, cut: cut, admissionID: owner.admissionID,
            requestID: owner.request.notification.requestID,
            actualWrittenPrefixCount: stage.prefixCount,
            initialPolicyVerified: stage.initialPolicyVerified,
            finalPolicyVerified: stage.finalPolicyVerified, renamed: stage.renamed)
        throw AppAccessContractFailureV1.effectMismatch
    }

    private func schedulingWriteCountForTesting(_ owner: NotificationSchedulingPublicationOwner?,
        stage: SchedulingStage?, remaining: Int) -> Int {
        guard let owner, let stage,
              let fault = Self.schedulingOwners.faults[owner.rootIdentity],
              fault.phase == schedulingPhaseForTesting(owner, stage: stage),
              case .afterPositivePrefix(let count) = fault.cut,
              count > stage.prefixCount else { return remaining }
        // The syscall still writes actual bytes and the real positive count is
        // recorded. This only bounds that call to expose a deterministic cut.
        return min(remaining, count - stage.prefixCount)
    }
#endif

    /// Reuses the publisher's existing checked policy request on its actual
    /// live stage. Zero is accepted only for this captured O_EXCL descriptor;
    /// no disk-derived empty leaf can reach this boundary.
    private func schedulingApplyStagePolicy(_ owner: NotificationSchedulingPublicationOwner,
        stage: SchedulingStage, expectedPrefixCount: Int
    ) throws -> ProtectedFileVerificationDispositionV1 {
        guard owner.stage === stage, !stage.renamed, !stage.removed,
              expectedPrefixCount == stage.prefixCount,
              expectedPrefixCount == 0 || expectedPrefixCount == stage.bytes.count else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        _ = try schedulingState(owner)
        var enteredEffect = false
        let result: ProtectedFileVerificationDispositionV1
        do {
            // A policy attempt can mutate resource metadata before returning
            // an error. Capture that cut without losing the positive anchor.
            defer { schedulingRecordFact(stage, afterOwnedEffect: enteredEffect) }
            result = try ProtectedFilePolicyV1.applyAndVerifyEraseColdPrivateWithCheckedClose(
                .journalTemporary, at: rootURL.appendingPathComponent(Self.mappingPendingName),
                retainUncertainDescriptor: { descriptor in
                    owner.uncertainClose = true
                    _ = ScratchUncertainCloseQuarantineV1.shared.begin(descriptor)
                }, authorityCheck: {
                    try self.requireSchedulingOwner(owner)
                    var held = stat(), afterPrefix = stat()
                    guard owner.stage === stage, !stage.renamed, !stage.removed,
                          let anchor = stage.anchor,
                          Darwin.fstat(stage.descriptor, &held) == 0,
                          let named = try self.schedulingRawInformation(Self.mappingPendingName),
                          Self.sameFile(held, named),
                          held.st_dev == anchor.st_dev, held.st_ino == anchor.st_ino,
                          held.st_mode == anchor.st_mode,
                          held.st_uid == anchor.st_uid, held.st_gid == anchor.st_gid,
                          held.st_nlink == anchor.st_nlink, anchor.st_nlink == 1,
                          stage.prefixCount == expectedPrefixCount,
                          held.st_size == Int64(expectedPrefixCount),
                          enteredEffect || (stage.fact.map { Self.sameFile(held, $0) } == true),
                          try self.schedulingBytes(stage.descriptor, count: expectedPrefixCount)
                            == Data(stage.bytes.prefix(expectedPrefixCount)),
                          let canonical = try self.schedulingReadCanonical(owner),
                          canonical.0 == stage.predecessor,
                          Self.sameFile(canonical.1, owner.canonicalFact),
                          Darwin.fstat(stage.descriptor, &afterPrefix) == 0,
                          Self.sameFile(held, afterPrefix),
                          let finalNamed = try self.schedulingRawInformation(Self.mappingPendingName),
                          Self.sameFile(held, finalNamed) else {
                        throw AppAccessContractFailureV1.effectMismatch
                    }
#if DEBUG
                    if expectedPrefixCount == 0, enteredEffect {
                        try self.schedulingTestingCut(owner, stage: stage,
                            cut: .afterInitialPolicyEffectBeforeVerification)
                    }
#endif
                }, beforeFirstEffect: {
#if DEBUG
                    if expectedPrefixCount == 0 {
                        try self.schedulingTestingCut(owner, stage: stage, cut: .beforeInitialPolicyEffect)
                    }
#endif
                    enteredEffect = true
                    stage.policyRequested = true
                })
        }
        _ = try schedulingState(owner)
        // Per-kind readback is separate from byte/mode ownership. Its checked
        // helper preserves descriptor uncertainty and never authorizes a write
        // based on the Darwin 0600 mode or inherited directory policy alone.
        let observed = try ProtectedFilePolicyV1.observeTemporalPolicyWithCheckedClose(
            .journalTemporary, at: rootURL.appendingPathComponent(Self.mappingPendingName),
            retainUncertainDescriptor: { descriptor in
                owner.uncertainClose = true
                _ = ScratchUncertainCloseQuarantineV1.shared.begin(descriptor)
            })
        guard let anchor = stage.anchor,
              observed.device == UInt64(anchor.st_dev), observed.inode == UInt64(anchor.st_ino),
              observed.mode == UInt16(anchor.st_mode), observed.linkCount == UInt64(anchor.st_nlink),
              observed.isDirectory == false, observed.backupExcluded == true,
              observed.state == .strictComplete || observed.state == .pendingSimulatorRequest else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        _ = try schedulingState(owner)
        return result
    }

    private func schedulingCompleteStage(_ owner: NotificationSchedulingPublicationOwner) throws {
        guard let stage = owner.stage else { return }
        _ = try schedulingState(owner)
        if stage.renamed && !stage.fileSynced {
            stage.fileSyncAttempted = true
            guard Darwin.fsync(stage.descriptor) == 0 else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            stage.fileSynced = true
            schedulingRecordFact(stage)
        }
        if !stage.parentSynced {
            _ = try schedulingState(owner)
            stage.parentSyncAttempted = true
            guard Darwin.fsync(authority.rootDescriptor) == 0 else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            stage.parentSynced = true
        }
        _ = try schedulingState(owner)
        guard stage.renamed || stage.removed else { throw AppAccessContractFailureV1.effectMismatch }
#if DEBUG
        try schedulingTestingCut(owner, stage: stage, cut: .beforeCheckedStageClose)
#endif
        stage.closeAttempted = true
        try schedulingClose(stage.descriptor, owner: owner)
        owner.stage = nil
    }

    /// A late add completion may clear only its own durable admission. This
    /// cannot re-enable publication or change policy/source/correlation data.
    func finishNotificationAdd(admissionID: UUID, requestID: String, verifiedPresent: Bool) throws {
        try AppLockNotificationTransactionFenceV1.perform {
            guard Self.schedulingOwners.live[notificationRootIdentity] == nil else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            guard var value = try loadPrivateNotificationMapping(),
                  let index = value.entries.firstIndex(where: {
                      $0.admissionID == admissionID && $0.request.notification.requestID == requestID
                  }) else { throw AppAccessContractFailureV1.effectMismatch }
            let old = value
            value.entries[index].admissionID = nil
            value.entries[index].acknowledged = verifiedPresent
            try value.validate()
            try publishBytes(CompatibilityCanonicalV1.encode(value), recordName: Self.mappingName,
                pendingName: Self.mappingPendingName, expected: CompatibilityCanonicalV1.encode(old))
        }
    }

    func beginNotificationErase(operationID: UUID) throws -> NotificationEraseRevocationV1 {
        try AppLockNotificationTransactionFenceV1.perform {
            let value = NotificationEraseRevocationV1(schemaVersion: 1, operationID: operationID,
                rootIdentity: notificationRootIdentity)
            try value.validate()
            if let bytes = try readFile(Self.eraseName, kind: .journal) {
                let current = try Self.decodeAuxiliary(NotificationEraseRevocationV1.self, bytes: bytes)
                guard current == value else { throw AppAccessContractFailureV1.effectMismatch }
                return current
            }
            try publishBytes(CompatibilityCanonicalV1.encode(value), recordName: Self.eraseName,
                pendingName: Self.erasePendingName, expected: nil)
            return value
        }
    }

    /// Publishes the original owner's revocation under its already-held
    /// Notification fence, EX, and checked G. An interrupted pending leaf is
    /// retained for explicit recovery; its bytes never become authority for
    /// this invocation. The lexical permit cannot be used by ordinary callers.
    @MainActor
    func publishOriginalEraseNotificationMarker(
        operationID: UUID,
        operation: EraseRouterOperationV1,
        store: EraseIntentStore,
        registry: GenerationLeaseRegistryV1,
        exclusion: StoreTemporalNormalizationExclusionV1,
        activity: GenerationTemporalActivityHandleV1,
        policyReceipt: OriginalEraseNotificationRootPolicyReceiptV1,
        firstNodes: [EraseSchema2ColdAuxiliaryFirstObserverV1.ControlNode],
        firstStableTreeDigest: String,
        retainedIO: EraseAbortCheckedSnapshotIOV1,
        permit: OriginalEraseNotificationMarkerPermitV1,
        reproveUnaffectedBranches: () throws -> Void
    ) throws -> OriginalEraseNotificationMarkerPublicationReceiptV1 {
        guard let originalErasePolicyIO else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        try originalErasePolicyIO.requireSettled()
        try policyReceipt.requireBound(operation: operation, store: store,
            registry: registry, exclusion: exclusion, activity: activity)
        let revocation = NotificationEraseRevocationV1(schemaVersion: 1,
            operationID: operationID, rootIdentity: notificationRootIdentity)
        try revocation.validate()
        let bytes = try CompatibilityCanonicalV1.encode(revocation)
        guard !bytes.isEmpty, bytes.count <= Self.maximumRecordBytes,
              try Self.decodeAuxiliary(NotificationEraseRevocationV1.self,
                  bytes: bytes) == revocation else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        let firstChildren = firstNodes.filter { !$0.path.isEmpty }
        let firstNames = firstChildren.map(\.path).sorted()
        guard firstNodes.count == firstNames.count + 1,
              Set(firstNames).count == firstNames.count,
              firstNames.allSatisfy({ !$0.contains("/") }),
              !firstNames.contains(Self.eraseName),
              !firstNames.contains(Self.erasePendingName),
              firstNodes.first(where: { $0.path.isEmpty })?.fullFact
                == policyReceipt.firstRootFact else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        let io = retainedIO
        let root = authority.rootDescriptor
        let operations = authority.operationsDescriptor
        guard Set(firstNodes.map(\.path)).count == firstNodes.count else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        func fact(_ value: stat) -> String {
            "\(value.st_dev)|\(value.st_ino)|\(value.st_mode)|\(value.st_uid)|\(value.st_gid)|\(value.st_nlink)|\(value.st_size)|\(value.st_mtimespec.tv_sec)|\(value.st_mtimespec.tv_nsec)|\(value.st_ctimespec.tv_sec)|\(value.st_ctimespec.tv_nsec)"
        }
        func sameRootOwner(_ first: String, _ projected: String) -> Bool {
            let a = first.split(separator: "|", omittingEmptySubsequences: false)
            let b = projected.split(separator: "|", omittingEmptySubsequences: false)
            return a.count == 11 && b.count == 11 &&
                Array(a.prefix(6)) == Array(b.prefix(6))
        }
        func requireRoot(_ expected: String, names: [String]) throws -> stat {
            try permit.requireHeld()
            try verifyRoot()
            try reproveUnaffectedBranches()
            var held = stat(), named = stat()
            guard Darwin.fstat(root, &held) == 0,
                  Darwin.fstatat(operations, Self.rootName, &named,
                      AT_SYMLINK_NOFOLLOW) == 0,
                  fact(held) == expected, fact(named) == expected,
                  try io.names(in: root) == names else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            for node in firstChildren {
                try io.withOpen(parent: root, name: node.path,
                    flags: O_RDONLY | O_NONBLOCK) { child in
                    var heldChild = stat(), namedChild = stat()
                    guard Darwin.fstat(child, &heldChild) == 0,
                          Darwin.fstatat(root, node.path, &namedChild,
                              AT_SYMLINK_NOFOLLOW) == 0,
                          fact(heldChild) == node.fullFact,
                          fact(namedChild) == node.fullFact,
                          heldChild.st_mode & S_IFMT == S_IFREG,
                          heldChild.st_nlink == 1 else {
                        throw AppAccessContractFailureV1
                            .notificationReconciliationRequired
                    }
                    let kind: OwnedFileKindV1 =
                        node.path.hasSuffix(".pending.json")
                            ? .journalTemporary : .journal
                    let observed = try ProtectedFilePolicyV1
                        .observeTemporalPolicyWithCheckedClose(kind,
                            at: rootURL.appendingPathComponent(node.path),
                            retainUncertainDescriptor: {
                                io.retainUncertainDescriptor($0)
                                permit.poisonOnUncertainEffect()
                            })
                    guard observed == node.policy,
                          Darwin.fstat(child, &heldChild) == 0,
                          Darwin.fstatat(root, node.path, &namedChild,
                              AT_SYMLINK_NOFOLLOW) == 0,
                          fact(heldChild) == node.fullFact,
                          fact(namedChild) == node.fullFact else {
                        throw AppAccessContractFailureV1
                            .notificationReconciliationRequired
                    }
                }
            }
            guard try io.postRetiredTree(parent: operations,
                    name: Self.rootName,
                    excluding: [Self.eraseName, Self.erasePendingName],
                    ignoringDirectoryMetadata: Set([""]))
                    == firstStableTreeDigest else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            try reproveUnaffectedBranches()
            try permit.requireHeld()
            return held
        }
        func requireLeaf(_ name: String, expected: String) throws -> stat {
            var named = stat()
            guard Darwin.fstatat(root, name, &named,
                    AT_SYMLINK_NOFOLLOW) == 0,
                  fact(named) == expected,
                  named.st_mode & S_IFMT == S_IFREG,
                  named.st_nlink == 1 else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            return named
        }
        var effectStarted = false
        do {
            let first = try requireRoot(policyReceipt.projectedRootFact,
                names: firstNames)
            guard try io.postRetiredTree(parent: operations,
                    name: Self.rootName)
                    == policyReceipt.projectedTreeDigest else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            _ = try requireRoot(policyReceipt.projectedRootFact,
                names: firstNames)
            let firstLinks = UInt64(first.st_nlink)
            let firstCount = UInt64(firstNames.count)
            guard firstLinks == 2 ||
                    firstLinks == firstCount + 2 else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            effectStarted = true
            let written = try io.withOpen(parent: root,
                name: Self.erasePendingName,
                flags: O_WRONLY | O_CREAT | O_EXCL, mode: 0o600) {
                descriptor -> stat in
                var opened = stat(), named = stat(), currentRoot = stat()
                guard Darwin.fstat(descriptor, &opened) == 0,
                      Darwin.fstatat(root, Self.erasePendingName,
                          &named, AT_SYMLINK_NOFOLLOW) == 0,
                      opened.st_dev == named.st_dev,
                      opened.st_ino == named.st_ino,
                      opened.st_mode & S_IFMT == S_IFREG,
                      opened.st_nlink == 1,
                      opened.st_uid == geteuid(),
                      opened.st_gid == ((first.st_mode & S_ISGID) != 0
                          ? first.st_gid : getegid()),
                      opened.st_size == 0,
                      Darwin.fstat(root, &currentRoot) == 0,
                      (firstNames.isEmpty
                        ? (UInt64(currentRoot.st_nlink) == 2 ||
                            UInt64(currentRoot.st_nlink) == 3)
                        : firstLinks == 2
                            ? UInt64(currentRoot.st_nlink) == 2
                            : UInt64(currentRoot.st_nlink)
                                == firstLinks + 1) else {
                    throw AppAccessContractFailureV1
                        .notificationReconciliationRequired
                }
                guard fact(opened) == fact(named) else {
                    throw AppAccessContractFailureV1
                        .notificationReconciliationRequired
                }
                let createdRootFact = fact(currentRoot)
                _ = try requireRoot(createdRootFact,
                    names: (firstNames + [Self.erasePendingName]).sorted())
                _ = try requireLeaf(Self.erasePendingName,
                    expected: fact(opened))
                var offset = 0
                while offset < bytes.count {
                    let count = bytes.withUnsafeBytes { raw -> Int in
                        guard let base = raw.baseAddress else { return 0 }
                        return Darwin.write(descriptor,
                            base.advanced(by: offset), raw.count - offset)
                    }
                    if count < 0, errno == EINTR { continue }
                    guard count > 0 else {
                        throw AppAccessContractFailureV1
                            .notificationReconciliationRequired
                    }
                    offset += count
                }
                _ = try requireRoot(createdRootFact,
                    names: (firstNames + [Self.erasePendingName]).sorted())
                // This new inode is owned by the current O_EXCL attempt. Its
                // policy request is included in the same sticky effect window.
                try ProtectedFilePolicyV1.applyAndVerify(.journalTemporary,
                    at: rootURL.appendingPathComponent(Self.erasePendingName),
                    authorityCheck: {
                        try permit.requireHeld()
                        _ = try requireRoot(createdRootFact,
                            names: (firstNames +
                                [Self.erasePendingName]).sorted())
                        var held = stat(), linked = stat()
                        guard Darwin.fstat(descriptor, &held) == 0,
                              Darwin.fstatat(root, Self.erasePendingName,
                                  &linked, AT_SYMLINK_NOFOLLOW) == 0,
                              held.st_dev == opened.st_dev,
                              held.st_ino == opened.st_ino,
                              fact(held) == fact(linked),
                              held.st_mode & S_IFMT == S_IFREG,
                              held.st_nlink == 1 else {
                            throw AppAccessContractFailureV1
                                .notificationReconciliationRequired
                        }
                    })
                guard Darwin.fsync(descriptor) == 0,
                      Darwin.fstat(descriptor, &opened) == 0,
                      Darwin.fstatat(root, Self.erasePendingName,
                          &named, AT_SYMLINK_NOFOLLOW) == 0,
                      fact(opened) == fact(named) else {
                    throw AppAccessContractFailureV1
                        .notificationReconciliationRequired
                }
                return opened
            }
            let temporaryFact = fact(written)
            _ = try requireLeaf(Self.erasePendingName,
                expected: temporaryFact)
            let createdRoot = try io.withOpen(parent: root,
                name: Self.erasePendingName,
                flags: O_RDONLY | O_NONBLOCK) { descriptor -> String in
                var held = stat(), named = stat()
                guard Darwin.fstat(descriptor, &held) == 0,
                      Darwin.fstatat(root, Self.erasePendingName,
                          &named, AT_SYMLINK_NOFOLLOW) == 0,
                      fact(held) == temporaryFact,
                      fact(named) == temporaryFact,
                      try readFile(Self.erasePendingName,
                          kind: .journalTemporary) == bytes else {
                    throw AppAccessContractFailureV1
                        .notificationReconciliationRequired
                }
                var current = stat()
                guard Darwin.fstat(root, &current) == 0 else {
                    throw AppAccessContractFailureV1
                        .notificationReconciliationRequired
                }
                return fact(current)
            }
            _ = try requireRoot(createdRoot,
                names: (firstNames + [Self.erasePendingName]).sorted())
            _ = try requireLeaf(Self.erasePendingName,
                expected: temporaryFact)
            guard try readFile(Self.erasePendingName,
                    kind: .journalTemporary) == bytes else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            _ = try requireLeaf(Self.erasePendingName,
                expected: temporaryFact)
            _ = try requireRoot(createdRoot,
                names: (firstNames + [Self.erasePendingName]).sorted())
            // No pending byte match or orphan temp is accepted from a prior
            // invocation. The held O_EXCL inode is the sole rename source.
            guard Darwin.renameatx_np(root, Self.erasePendingName,
                    root, Self.eraseName, UInt32(RENAME_EXCL)) == 0 else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            var renamedRoot = stat(), canonical = stat()
            guard Darwin.fstat(root, &renamedRoot) == 0,
                  Darwin.fstatat(root, Self.eraseName,
                      &canonical, AT_SYMLINK_NOFOLLOW) == 0,
                  canonical.st_dev == written.st_dev,
                  canonical.st_ino == written.st_ino,
                  canonical.st_uid == written.st_uid,
                  canonical.st_gid == written.st_gid,
                  canonical.st_mode == written.st_mode,
                  canonical.st_nlink == written.st_nlink,
                  canonical.st_size == written.st_size,
                  canonical.st_mtimespec.tv_sec
                    == written.st_mtimespec.tv_sec,
                  canonical.st_mtimespec.tv_nsec
                    == written.st_mtimespec.tv_nsec,
                  Darwin.fsync(root) == 0 else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            let canonicalRootFact = fact(renamedRoot)
            guard sameRootOwner(createdRoot, canonicalRootFact) else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            _ = try requireRoot(canonicalRootFact,
                names: (firstNames + [Self.eraseName]).sorted())
            let canonicalFact = fact(canonical)
            _ = try requireLeaf(Self.eraseName, expected: canonicalFact)
            guard try readFile(Self.eraseName,
                    kind: .journal) == bytes else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            _ = try requireRoot(canonicalRootFact,
                names: (firstNames + [Self.eraseName]).sorted())
            try io.requireSettled()
            let finalTree = try io.postRetiredTree(
                parent: operations, name: Self.rootName)
            guard try io.postRetiredTree(parent: operations,
                    name: Self.rootName) == finalTree else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            try io.requireSettled()
            return OriginalEraseNotificationMarkerPublicationReceiptV1(
                control: self, operation: operation, store: store,
                registry: registry, exclusion: exclusion,
                activity: activity, revocation: revocation,
                canonicalBytes: bytes,
                firstRootFact: policyReceipt.projectedRootFact,
                projectedRootFact: canonicalRootFact,
                firstTreeDigest: policyReceipt.projectedTreeDigest,
                projectedTreeDigest: finalTree,
                canonicalLeafFact: canonicalFact)
        } catch {
            if effectStarted { permit.poisonOnUncertainEffect() }
            throw error
        }
    }

    /// The OS absence witness is produced after the real system readback.
    /// Remove only the two canonical predecessor leaves proved by the first
    /// Notification tree and the marker receipt. No ordinary unlink helper is
    /// borrowed while the original operation holds EX/G.
    @MainActor
    func removeOriginalEraseNotificationRecordsAfterOSAbsence(
        _ absence: OriginalEraseNotificationOSAbsenceReceiptV1,
        marker: OriginalEraseNotificationMarkerPublicationReceiptV1,
        firstNodes: [EraseSchema2ColdAuxiliaryFirstObserverV1.ControlNode],
        retainedIO: EraseAbortCheckedSnapshotIOV1,
        permit: OriginalEraseNotificationRemovalPermitV1,
        reproveUnaffectedBranches: () throws -> Void
    ) throws -> OriginalEraseNotificationRecordRemovalReceiptV1 {
        guard originalErasePolicyIO != nil else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        try absence.requireBound(control: self,
            revocation: marker.revocation)
        guard Set(firstNodes.map(\.path)).count == firstNodes.count else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        let io = retainedIO
        let root = authority.rootDescriptor
        let operations = authority.operationsDescriptor
        func fact(_ value: stat) -> String {
            "\(value.st_dev)|\(value.st_ino)|\(value.st_mode)|\(value.st_uid)|\(value.st_gid)|\(value.st_nlink)|\(value.st_size)|\(value.st_mtimespec.tv_sec)|\(value.st_mtimespec.tv_nsec)|\(value.st_ctimespec.tv_sec)|\(value.st_ctimespec.tv_nsec)"
        }
        func sameRootOwner(_ first: String, _ projected: String) -> Bool {
            let a = first.split(separator: "|", omittingEmptySubsequences: false)
            let b = projected.split(separator: "|", omittingEmptySubsequences: false)
            return a.count == 11 && b.count == 11 &&
                Array(a.prefix(5)) == Array(b.prefix(5))
        }
        let byName = Dictionary(uniqueKeysWithValues: firstNodes
            .filter { !$0.path.isEmpty }.map { ($0.path, $0) })
        var expectedNames = (Array(byName.keys) + [Self.eraseName]).sorted()
        func sameRootExceptCtime(_ first: String,
            _ projected: String) -> Bool {
            let a = first.split(separator: "|",
                omittingEmptySubsequences: false)
            let b = projected.split(separator: "|",
                omittingEmptySubsequences: false)
            return a.count == 11 && b.count == 11 &&
                Array(a.prefix(9)) == Array(b.prefix(9))
        }
        guard Set(expectedNames).count == expectedNames.count,
              !expectedNames.contains(Self.erasePendingName),
              !expectedNames.contains(Self.pendingName),
              !expectedNames.contains(Self.mappingPendingName),
              let rootNode = firstNodes.first(where: { $0.path.isEmpty }),
              sameRootExceptCtime(rootNode.fullFact,
                  marker.firstRootFact) else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        var expectedRoot = marker.projectedRootFact
        var expectedTree = marker.projectedTreeDigest
        var removed = Set<String>()
        func requireCut() throws -> stat {
            try permit.requireHeld()
            try verifyRoot()
            try reproveUnaffectedBranches()
            var held = stat(), named = stat()
            var observedRegularSHA: [String: String] = [:]
            let observedTree = try io.postRetiredTree(parent: operations,
                name: Self.rootName, observeTypedNode: { node, _ in
                    if let sha = node.sha256 {
                        observedRegularSHA[node.path] = sha
                    }
                })
            guard Darwin.fstat(root, &held) == 0,
                  Darwin.fstatat(operations, Self.rootName,
                      &named, AT_SYMLINK_NOFOLLOW) == 0,
                  fact(held) == expectedRoot,
                  fact(named) == expectedRoot,
                  try io.names(in: root) == expectedNames,
                  observedTree == expectedTree,
                  observedRegularSHA.count == expectedNames.count,
                  try readFile(Self.eraseName,
                      kind: .journal) == marker.canonicalBytes else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            var markerHeld = stat(), markerNamed = stat()
            try io.withOpen(parent: root, name: Self.eraseName,
                flags: O_RDONLY | O_NONBLOCK) { descriptor in
                guard Darwin.fstat(descriptor, &markerHeld) == 0,
                      Darwin.fstatat(root, Self.eraseName, &markerNamed,
                          AT_SYMLINK_NOFOLLOW) == 0,
                      fact(markerHeld) == marker.canonicalLeafFact,
                      fact(markerNamed) == marker.canonicalLeafFact else {
                    throw AppAccessContractFailureV1
                        .notificationReconciliationRequired
                }
            }
            for name in expectedNames where name != Self.eraseName {
                guard let node = byName[name] else {
                    throw AppAccessContractFailureV1
                        .notificationReconciliationRequired
                }
                guard node.contentSHA256 != nil,
                      observedRegularSHA[name] == node.contentSHA256 else {
                    throw AppAccessContractFailureV1
                        .notificationReconciliationRequired
                }
                try io.withOpen(parent: root, name: name,
                    flags: O_RDONLY | O_NONBLOCK) { descriptor in
                    var child = stat(), linked = stat()
                    guard Darwin.fstat(descriptor, &child) == 0,
                          Darwin.fstatat(root, name, &linked,
                              AT_SYMLINK_NOFOLLOW) == 0,
                          fact(child) == node.fullFact,
                          fact(linked) == node.fullFact,
                          child.st_mode & S_IFMT == S_IFREG,
                          child.st_nlink == 1 else {
                        throw AppAccessContractFailureV1
                            .notificationReconciliationRequired
                    }
                    let policy = try ProtectedFilePolicyV1
                        .observeTemporalPolicyWithCheckedClose(.journal,
                            at: rootURL.appendingPathComponent(name),
                            retainUncertainDescriptor: {
                                io.retainUncertainDescriptor($0)
                                permit.poisonOnUncertainEffect()
                            })
                    guard policy == node.policy,
                          Darwin.fstat(descriptor, &child) == 0,
                          Darwin.fstatat(root, name, &linked,
                              AT_SYMLINK_NOFOLLOW) == 0,
                          fact(child) == node.fullFact,
                          fact(linked) == node.fullFact else {
                        throw AppAccessContractFailureV1
                            .notificationReconciliationRequired
                    }
                }
            }
            try reproveUnaffectedBranches()
            try permit.requireHeld()
            return held
        }
        var effectStarted = false
        do {
            _ = try requireCut()
            guard try loadPrivateNotificationMapping()
                    == absence.mapping,
                  try loadControl()?.journal == absence.journal else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            for name in [Self.mappingName, Self.recordName]
                where expectedNames.contains(name) {
                guard let node = byName[name] else {
                    throw AppAccessContractFailureV1
                        .notificationReconciliationRequired
                }
                let before = try requireCut()
                effectStarted = true
                try io.withOpen(parent: root, name: name,
                    flags: O_RDONLY | O_NONBLOCK) { descriptor in
                    var held = stat(), named = stat()
                    guard Darwin.fstat(descriptor, &held) == 0,
                          Darwin.fstatat(root, name, &named,
                              AT_SYMLINK_NOFOLLOW) == 0,
                          fact(held) == node.fullFact,
                          fact(named) == node.fullFact else {
                        throw AppAccessContractFailureV1
                            .notificationReconciliationRequired
                    }
                    _ = try requireCut()
                    guard Darwin.unlinkat(root, name, 0) == 0,
                          Darwin.fsync(root) == 0,
                          Darwin.fstat(descriptor, &held) == 0,
                          held.st_dev == named.st_dev,
                          held.st_ino == named.st_ino,
                          held.st_nlink == 0 else {
                        throw AppAccessContractFailureV1
                            .notificationReconciliationRequired
                    }
                    removed.insert(name)
                    expectedNames.removeAll { $0 == name }
                    var afterRoot = stat(), afterNamed = stat(), gone = stat()
                    guard Darwin.fstat(root, &afterRoot) == 0,
                          Darwin.fstatat(operations, Self.rootName,
                              &afterNamed, AT_SYMLINK_NOFOLLOW) == 0,
                          fact(afterRoot) == fact(afterNamed),
                          sameRootOwner(fact(before), fact(afterRoot)),
                          Darwin.fstatat(root, name, &gone,
                              AT_SYMLINK_NOFOLLOW) != 0,
                          errno == ENOENT,
                          (before.st_nlink == 2
                            ? afterRoot.st_nlink == 2
                            : before.st_nlink > 2 &&
                                afterRoot.st_nlink
                                    == before.st_nlink - 1),
                          try io.names(in: root) == expectedNames else {
                        throw AppAccessContractFailureV1
                            .notificationReconciliationRequired
                    }
                    expectedRoot = fact(afterRoot)
                    expectedTree = try io.postRetiredTree(
                        parent: operations, name: Self.rootName)
                    _ = try requireCut()
                }
                _ = try requireCut()
            }
            guard expectedNames == [Self.eraseName],
                  removed == Set(byName.keys).intersection(
                    [Self.mappingName, Self.recordName]),
                  try io.names(in: root) == [Self.eraseName] else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            _ = try requireCut()
            try io.requireSettled()
            return OriginalEraseNotificationRecordRemovalReceiptV1(
                control: self, absence: absence, marker: marker,
                finalRootFact: expectedRoot,
                finalTreeDigest: expectedTree,
                removedNames: removed)
        } catch {
            if effectStarted { permit.poisonOnUncertainEffect() }
            throw error
        }
    }

    /// Called only after the system owner has drained admissions and observed
    /// owned pending/delivered request absence. Retain the revocation marker.
    func removeNotificationRecordsAfterErase(_ revocation: NotificationEraseRevocationV1) throws {
        try AppLockNotificationTransactionFenceV1.perform {
            guard Self.schedulingOwners.live[notificationRootIdentity] == nil else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            // The original EX owner uses a separately receipted unlink path.
            // This ordinary helper cannot settle its descriptor/policy cuts.
            guard originalErasePolicyIO == nil else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            guard let bytes = try readFile(Self.eraseName, kind: .journal),
                  try Self.decodeAuxiliary(NotificationEraseRevocationV1.self, bytes: bytes) == revocation,
                  revocation.rootIdentity == notificationRootIdentity else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            if let mapping = try loadPrivateNotificationMapping() {
                guard mapping.entries.allSatisfy({ $0.admissionID == nil }) else {
                    throw AppAccessContractFailureV1.notificationReconciliationRequired
                }
            }
            // Unknown interrupted publication bytes are never silently erased.
            guard try information(Self.pendingName) == nil,
                  try information(Self.mappingPendingName) == nil,
                  try information(Self.erasePendingName) == nil else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            for name in [Self.mappingName, Self.recordName] {
                if let expected = try information(name) {
                    try verifyRoot()
                    guard let linked = try information(name), Self.sameFile(expected, linked),
                          Darwin.unlinkat(authority.rootDescriptor, name, 0) == 0,
                          Darwin.fsync(authority.rootDescriptor) == 0 else {
                        throw AppAccessContractFailureV1.configurationUnknown
                    }
                }
            }
        }
    }

    /// Pure post-effect check used when a caller needs a typed Erase drain
    /// receipt. The ordinary erase entry retains its existing call sequence.
    func requireNotificationEraseRevocation(
        _ revocation: NotificationEraseRevocationV1
    ) throws {
        try AppLockNotificationTransactionFenceV1.perform {
            try verifyRoot()
            guard revocation.rootIdentity == notificationRootIdentity,
                  let bytes = try readFile(Self.eraseName,
                    kind: .journal),
                  try Self.decodeAuxiliary(
                    NotificationEraseRevocationV1.self,
                    bytes: bytes) == revocation else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            for name in [Self.recordName, Self.pendingName,
                         Self.mappingName, Self.mappingPendingName,
                         Self.erasePendingName] {
                guard try information(name) == nil else {
                    throw AppAccessContractFailureV1
                        .notificationReconciliationRequired
                }
            }
            try verifyRoot()
        }
    }

    private static func decodeAuxiliary<T: Codable>(_ type: T.Type, bytes: Data) throws -> T {
        let value = try JSONDecoder().decode(type, from: bytes)
        guard try CompatibilityCanonicalV1.encode(value) == bytes else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        return value
    }

    func requirePreferencesOwner(_ candidate: PreferencesAdapterV1) throws {
        guard candidate === preferences else { throw AppAccessContractFailureV1.effectMismatch }
    }

    /// Settles only metadata for an already completed Preferences effect. It
    /// never writes policy, changes AppLock, or claims an OS projection occurred.
    func readyControlForReminderPolicy() throws -> AppLockNotificationControlV1? {
        try AppLockNotificationTransactionFenceV1.perform {
            guard Self.schedulingOwners.live[notificationRootIdentity] == nil else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            try requireNotificationPublicationAllowed()
            let setting = try preferences.readAppLockSettingSnapshot()
            guard let current = try loadControl() else {
                guard try readFile(Self.pendingName, kind: .journalTemporary) == nil,
                      try setting.setting?.isEnabled != true,
                      try preferences.completedReminderControlEdit() == nil else {
                    throw AppAccessContractFailureV1.notificationReconciliationRequired
                }
                return nil
            }
            guard current.phase == .settingCommitted, setting == current.settingWrite.successor,
                  current.journal.targetEnabled || current.journal.disposition == .priorPolicyRebuilt else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            guard let policy = try preferences.readStoredReminderPolicy() else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            let evidence = try preferences.completedReminderControlEdit()
            if policy == current.currentReminderPolicy {
                if let continuation = current.reminderPolicyContinuation {
                    guard continuation.rootIdentity == notificationRootIdentity, evidence == continuation else {
                        throw AppAccessContractFailureV1.effectMismatch
                    }
                }
                guard try readFile(Self.pendingName, kind: .journalTemporary) == nil else {
                    throw AppAccessContractFailureV1.notificationReconciliationRequired
                }
                return current
            }
            guard let evidence, evidence.rootIdentity == notificationRootIdentity,
                  evidence.settingWrite == current.settingWrite,
                  evidence.expectedPolicy == current.currentReminderPolicy,
                  policy == evidence.successorPolicy,
                  evidence.expectedControlSHA256 == (try CompatibilityCanonicalV1.sha256(
                    CompatibilityCanonicalV1.encode(current))) else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            let continued = try AppLockNotificationControlV1(journal: current.journal,
                priorReminderPolicy: current.priorReminderPolicy, settingWrite: current.settingWrite,
                phase: current.phase, reminderPolicyContinuation: evidence)
            try publish(continued, expected: current)
            guard try loadControl() == continued else { throw AppAccessContractFailureV1.effectMismatch }
            return continued
        }
    }

    func reminderPolicyEditStamp(for request: ReminderPolicyEditRequestV1,
                                 expected: AppLockNotificationControlV1?) throws -> AppLockReminderPolicyEditStampV1? {
        try AppLockNotificationTransactionFenceV1.perform {
            guard try readyControlForReminderPolicy() == expected,
                  try preferences.readStoredReminderPolicy() == request.expected else {
                throw SettingsContractFailureV1.staleRevision
            }
            guard let expected else { return nil }
            guard expected.currentReminderPolicy == request.expected,
                  request.expected.revision < UInt64.max else {
                throw SettingsContractFailureV1.staleRevision
            }
            let successor = try DeviceLocalReminderPolicyV1(instanceID: request.expected.instanceID,
                revision: request.expected.revision + 1, isEnabled: request.isEnabled, detail: request.detail)
            return try .init(rootIdentity: notificationRootIdentity,
                expectedControlSHA256: CompatibilityCanonicalV1.sha256(CompatibilityCanonicalV1.encode(expected)),
                settingWrite: expected.settingWrite, operationID: request.operationID,
                expectedPolicy: request.expected, successorPolicy: successor)
        }
    }

    func afterReminderPolicyWrite() throws {
        if failurePoint == .afterReminderPreferenceWrite { throw AppAccessContractFailureV1.effectMismatch }
    }

    func loadControl() throws -> AppLockNotificationControlV1? {
        try AppLockNotificationTransactionFenceV1.perform {
            guard let bytes = try readFile(Self.recordName, kind: .journal) else { return nil }
            return try Self.decode(bytes)
        }
    }

    func prepareControl(journal: AppLockNotificationJournalV1,
        priorReminderPolicy: DeviceLocalReminderPolicyV1,
        settingWrite: AppLockSettingWritePlanV1,
        expectedPredecessor: AppLockNotificationControlV1?) throws -> AppLockNotificationControlV1 {
        try AppLockNotificationTransactionFenceV1.perform {
            guard Self.schedulingOwners.live[notificationRootIdentity] == nil else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            try requireNotificationPublicationAllowed()
            let candidate = try AppLockNotificationControlV1(journal: journal,
                priorReminderPolicy: priorReminderPolicy, settingWrite: settingWrite)
            let current = try loadControl()
            try requirePolicy(settingWrite)
            let setting = try preferences.readAppLockSettingSnapshot()
            if current == candidate {
                guard setting == settingWrite.expectedSetting || setting == settingWrite.successor else {
                    throw SettingsContractFailureV1.staleRevision
                }
                return candidate
            }
            guard current == expectedPredecessor, setting == settingWrite.expectedSetting else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            if let current {
                guard current.phase == .settingCommitted,
                      current.journal.operationID != journal.operationID else {
                    throw AppAccessContractFailureV1.effectMismatch
                }
            }
            if !journal.targetEnabled, let current {
                guard priorReminderPolicy == current.priorReminderPolicy else {
                    throw AppAccessContractFailureV1.effectMismatch
                }
            } else {
                guard priorReminderPolicy == settingWrite.expectedReminderPolicy else {
                    throw AppAccessContractFailureV1.effectMismatch
                }
            }
            try publish(candidate, expected: current)
            return candidate
        }
    }

    func completeSetting(expected: AppLockNotificationControlV1) throws -> AppLockNotificationControlV1 {
        try AppLockNotificationTransactionFenceV1.perform {
            guard Self.schedulingOwners.live[notificationRootIdentity] == nil else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            // This public mutator writes Preferences before its journal
            // publication. The read-only original owner cannot borrow it.
            guard originalErasePolicyIO == nil else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            try requireNotificationPublicationAllowed()
            let completed = try expected.committingSetting()
            let current = try loadControl()
            try requirePolicy(expected.settingWrite)
            if current == completed {
                guard try preferences.readAppLockSettingSnapshot() == completed.settingWrite.successor else {
                    throw SettingsContractFailureV1.staleRevision
                }
                return completed
            }
            guard expected.phase == .prepared, current == expected else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            if let pending = try readFile(Self.pendingName, kind: .journalTemporary) {
                guard pending == (try CompatibilityCanonicalV1.encode(completed)) else {
                    throw AppAccessContractFailureV1.effectMismatch
                }
            }
            _ = try preferences.applyAppLockSettingWrite(expected.settingWrite)
            // Exact control stays prepared if this boundary is interrupted.
            if failurePoint == .afterPreferenceWrite { throw AppAccessContractFailureV1.effectMismatch }
            try publish(completed, expected: expected)
            return completed
        }
    }

    /// Records an actual same-operation journal result supplied by the future
    /// OS owner. No private/generic projection is performed or inferred here.
    func recordJournal(_ journal: AppLockNotificationJournalV1,
        expected: AppLockNotificationControlV1) throws -> AppLockNotificationControlV1 {
        try AppLockNotificationTransactionFenceV1.perform {
            guard Self.schedulingOwners.live[notificationRootIdentity] == nil else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            try requireNotificationPublicationAllowed()
            let old = expected.journal
            guard journal.operationID == old.operationID, journal.targetEnabled == old.targetEnabled,
                  journal.priorPolicy == old.priorPolicy, journal.projections == old.projections else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            let same = journal == old
            let advancesEnable = old.targetEnabled && expected.phase == .prepared
                && ((old.disposition == .enablingPrepared
                     && journal.disposition == .interruptedRecoveryRequired)
                    || ((old.disposition == .enablingPrepared || old.disposition == .interruptedRecoveryRequired)
                        && (journal.disposition == .genericProjectionApplied || journal.disposition == .genericProjectionAdopted)))
            let advancesDisable = !old.targetEnabled && expected.phase == .settingCommitted
                && old.disposition == .disablingPrepared && journal.disposition == .priorPolicyRebuilt
            guard same || advancesEnable || advancesDisable else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            let successor = try AppLockNotificationControlV1(journal: journal,
                priorReminderPolicy: expected.priorReminderPolicy, settingWrite: expected.settingWrite,
                phase: expected.phase)
            try requirePolicy(expected.settingWrite)
            let setting = try preferences.readAppLockSettingSnapshot()
            guard expected.phase == .prepared
                    ? (setting == expected.settingWrite.expectedSetting || setting == expected.settingWrite.successor)
                    : setting == expected.settingWrite.successor else {
                throw SettingsContractFailureV1.staleRevision
            }
            let current = try loadControl()
            if current == successor { return successor }
            guard current == expected else { throw AppAccessContractFailureV1.effectMismatch }
            try publish(successor, expected: expected)
            return successor
        }
    }

    private func requirePolicy(_ plan: AppLockSettingWritePlanV1) throws {
        guard try preferences.readStoredReminderPolicy() == plan.expectedReminderPolicy else {
            throw SettingsContractFailureV1.staleRevision
        }
    }

    private static func decode(_ bytes: Data) throws -> AppLockNotificationControlV1 {
        guard !bytes.isEmpty, bytes.count <= maximumRecordBytes else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let value = try JSONDecoder().decode(AppLockNotificationControlV1.self, from: bytes)
        guard try CompatibilityCanonicalV1.encode(value) == bytes else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        return value
    }

    private var rootURL: URL {
        supportURL.appendingPathComponent(OwnedStorageRootKindV1.operations.rawValue)
            .appendingPathComponent(Self.rootName)
    }

    private static func sameOriginalEraseRootFact(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino &&
            a.st_mode == b.st_mode && a.st_uid == b.st_uid &&
            a.st_gid == b.st_gid && a.st_nlink == b.st_nlink &&
            a.st_size == b.st_size &&
            a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec &&
            a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
            a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec &&
            a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }

    private static func originalEraseHeldNamedRootFact(
        authority: PinnedScratchRootV1, url: URL
    ) throws -> stat {
        var held = stat(), named = stat(), path = stat()
        guard Darwin.fstat(authority.rootDescriptor, &held) == 0,
              Darwin.fstatat(authority.operationsDescriptor,
                  Self.rootName, &named, AT_SYMLINK_NOFOLLOW) == 0,
              Darwin.lstat(url.path, &path) == 0,
              held.st_mode & S_IFMT == S_IFDIR,
              sameOriginalEraseRootFact(held, named),
              sameOriginalEraseRootFact(held, path),
              UInt64(held.st_dev) == authority.rootDevice,
              UInt64(held.st_ino) == authority.rootInode else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        return held
    }

    private func verifyRoot() throws {
        try Self.verifySupport(supportURL, descriptor: supportDescriptor,
            device: supportDevice, inode: supportInode, authority: authority)
        if let originalErasePolicyIO {
            let firstRoot = try Self.originalEraseHeldNamedRootFact(
                authority: authority, url: rootURL)
            let observed = try ProtectedFilePolicyV1
                .observeTemporalPolicyWithCheckedClose(.stagingDirectory,
                    at: rootURL, retainUncertainDescriptor: {
                        Self.retainOriginalEraseUncertainPolicyDescriptor(
                            $0, io: originalErasePolicyIO)
                    })
            guard observed.device == authority.rootDevice,
                  observed.inode == authority.rootInode,
                  observed.mode == UInt16(firstRoot.st_mode),
                  observed.linkCount == UInt64(firstRoot.st_nlink),
                  observed.isDirectory == true,
                  observed.backupExcluded == true,
                  observed.state == .strictComplete ||
                    observed.state == .pendingSimulatorRequest else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            let finalRoot = try Self.originalEraseHeldNamedRootFact(
                authority: authority, url: rootURL)
            guard Self.sameOriginalEraseRootFact(firstRoot, finalRoot) else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            try originalErasePolicyIO.requireSettled()
        } else {
            try ProtectedFilePolicyV1.verify(.stagingDirectory, at: rootURL)
        }
        try authority.verify(rootName: Self.rootName)
    }

    private static func verifySupport(_ url: URL, descriptor: Int32,
        device: UInt64, inode: UInt64, authority: PinnedScratchRootV1) throws {
        var opened = stat(), linked = stat(), operations = stat()
        guard Darwin.fstat(descriptor, &opened) == 0, Darwin.lstat(url.path, &linked) == 0,
              (linked.st_mode & S_IFMT) == S_IFDIR,
              UInt64(opened.st_dev) == device, UInt64(opened.st_ino) == inode,
              linked.st_dev == opened.st_dev, linked.st_ino == opened.st_ino,
              Darwin.fstatat(descriptor, OwnedStorageRootKindV1.operations.rawValue,
                  &operations, AT_SYMLINK_NOFOLLOW) == 0,
              (operations.st_mode & S_IFMT) == S_IFDIR,
              UInt64(operations.st_dev) == authority.operationsDevice,
              UInt64(operations.st_ino) == authority.operationsInode else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try authority.verify(rootName: rootName)
    }

    private static func openRoot(_ supportURL: URL,
        mustExistForOriginalErase: Bool = false,
        originalErasePolicyIO: EraseAbortCheckedSnapshotIOV1? = nil) throws
        -> (support: Int32, device: UInt64, inode: UInt64, authority: PinnedScratchRootV1) {
        let support = Darwin.open(supportURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard support >= 0 else { throw AppAccessContractFailureV1.configurationUnknown }
        var keep = false
        defer {
            if !keep {
                if let originalErasePolicyIO {
                    let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(support)
                    if Darwin.close(support) == 0 {
                        ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
                    } else {
                        originalErasePolicyIO.retainUncertainDescriptor(support)
                    }
                } else {
                    _ = Darwin.close(support)
                }
            }
        }
        var information = stat(), linked = stat()
        guard Darwin.fstat(support, &information) == 0,
              Darwin.lstat(supportURL.path, &linked) == 0,
              (linked.st_mode & S_IFMT) == S_IFDIR,
              information.st_dev == linked.st_dev, information.st_ino == linked.st_ino else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let operationsName = OwnedStorageRootKindV1.operations.rawValue
        if !mustExistForOriginalErase {
            guard Darwin.mkdirat(support, operationsName, 0o700) == 0
                    || errno == EEXIST else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        }
        let operations = Darwin.openat(support, operationsName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard operations >= 0 else { throw AppAccessContractFailureV1.configurationUnknown }
        var operationsCloseAttempted = false
        defer {
            if !operationsCloseAttempted {
                if let originalErasePolicyIO {
                    let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(operations)
                    if Darwin.close(operations) == 0 {
                        ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
                    } else {
                        originalErasePolicyIO.retainUncertainDescriptor(operations)
                    }
                } else {
                    _ = Darwin.close(operations)
                }
            }
        }
        var operationsInfo = stat()
        guard Darwin.fstat(operations, &operationsInfo) == 0,
              operationsInfo.st_dev == information.st_dev else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let created: Bool
        if mustExistForOriginalErase {
            created = false
        } else {
            created = Darwin.mkdirat(operations, rootName, 0o700) == 0
            guard created || errno == EEXIST else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        }
        let operationsURL = supportURL.appendingPathComponent(operationsName)
        let pinned = try PinnedScratchRootV1(operationsURL: operationsURL, rootName: rootName)
        var keepPinned = false
        defer {
            if mustExistForOriginalErase && !keepPinned {
                try? pinned.closeCheckedForExclusiveOriginalEraseRead(
                    verifyBeforeClose: false)
            }
        }
        guard UInt64(operationsInfo.st_dev) == pinned.operationsDevice,
              UInt64(operationsInfo.st_ino) == pinned.operationsInode else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let check = {
            try verifySupport(supportURL, descriptor: support, device: UInt64(information.st_dev),
                inode: UInt64(information.st_ino), authority: pinned)
        }
        try check()
        let root = operationsURL.appendingPathComponent(rootName)
        if mustExistForOriginalErase, let originalErasePolicyIO {
            let firstRoot = try originalEraseHeldNamedRootFact(
                authority: pinned, url: root)
            let observed = try ProtectedFilePolicyV1
                .observeTemporalPolicyWithCheckedClose(.stagingDirectory,
                    at: root, retainUncertainDescriptor: {
                        retainOriginalEraseUncertainPolicyDescriptor(
                            $0, io: originalErasePolicyIO)
                    })
            guard observed.device == pinned.rootDevice,
                  observed.inode == pinned.rootInode,
                  observed.mode == UInt16(firstRoot.st_mode),
                  observed.linkCount == UInt64(firstRoot.st_nlink),
                  observed.isDirectory == true,
                  observed.backupExcluded == true,
                  observed.state == .strictComplete ||
                    observed.state == .pendingSimulatorRequest else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            let finalRoot = try originalEraseHeldNamedRootFact(
                authority: pinned, url: root)
            guard sameOriginalEraseRootFact(firstRoot, finalRoot) else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        } else if created {
            try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: root, authorityCheck: check)
        } else {
            try ProtectedFilePolicyV1.verify(.stagingDirectory, at: root)
        }
        try check()
        if !mustExistForOriginalErase {
            guard Darwin.fsync(pinned.rootDescriptor) == 0,
                  Darwin.fsync(operations) == 0,
                  Darwin.fsync(support) == 0 else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        }
        if let originalErasePolicyIO {
            operationsCloseAttempted = true
            let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(
                operations)
            guard Darwin.close(operations) == 0 else {
                originalErasePolicyIO.retainUncertainDescriptor(operations)
                throw AppAccessContractFailureV1.configurationUnknown
            }
            ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
        }
        try originalErasePolicyIO?.requireSettled()
        keepPinned = true
        keep = true
        return (support, UInt64(information.st_dev), UInt64(information.st_ino), pinned)
    }

    private func information(_ name: String) throws -> stat? {
        try verifyRoot()
        var value = stat()
        if Darwin.fstatat(authority.rootDescriptor, name, &value, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else { throw AppAccessContractFailureV1.configurationUnknown }
            return nil
        }
        guard (value.st_mode & S_IFMT) == S_IFREG, value.st_nlink == 1,
              value.st_uid == Darwin.geteuid(), UInt64(value.st_dev) == authority.rootDevice,
              value.st_size > 0, value.st_size <= Int64(Self.maximumRecordBytes) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        return value
    }

    private static func sameFile(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_size == b.st_size
            && a.st_nlink == b.st_nlink && a.st_mode == b.st_mode
            && a.st_uid == b.st_uid && a.st_gid == b.st_gid
            && a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec
            && a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }

    private func readFile(_ name: String, kind: OwnedFileKindV1) throws -> Data? {
        guard let before = try information(name) else { return nil }
        func readOpened(_ file: Int32) throws -> Data {
            var opened = stat()
            guard Darwin.fstat(file, &opened) == 0,
                  Self.sameFile(before, opened) else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            if let originalErasePolicyIO {
                let observed = try ProtectedFilePolicyV1
                    .observeTemporalPolicyWithCheckedClose(kind,
                        at: rootURL.appendingPathComponent(name),
                        retainUncertainDescriptor: {
                            Self.retainOriginalEraseUncertainPolicyDescriptor(
                                $0, io: originalErasePolicyIO)
                        })
                guard observed.device == UInt64(opened.st_dev),
                      observed.inode == UInt64(opened.st_ino),
                      observed.mode == UInt16(opened.st_mode),
                      observed.linkCount == UInt64(opened.st_nlink),
                      observed.backupExcluded == true,
                      observed.state == .strictComplete ||
                        observed.state == .pendingSimulatorRequest else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
                try originalErasePolicyIO.requireSettled()
            } else {
                try ProtectedFilePolicyV1.verify(kind,
                    at: rootURL.appendingPathComponent(name))
            }
            var bytes = Data(count: Int(opened.st_size))
            var offset = 0
            while offset < bytes.count {
                let count = bytes.withUnsafeMutableBytes { raw -> Int in
                    guard let base = raw.baseAddress else { return 0 }
                    return Darwin.read(file, base.advanced(by: offset),
                        raw.count - offset)
                }
                if count < 0, errno == EINTR { continue }
                guard count > 0 else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
                offset += count
            }
            var after = stat()
            guard Darwin.fstat(file, &after) == 0,
                  Self.sameFile(opened, after),
                  let linked = try information(name),
                  Self.sameFile(after, linked) else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            return bytes
        }
        if let originalErasePolicyIO {
            return try originalErasePolicyIO.withOpen(
                parent: authority.rootDescriptor, name: name,
                flags: O_RDONLY | O_NONBLOCK) { file in
                try readOpened(file)
            }
        }
        let file = Darwin.openat(authority.rootDescriptor, name,
            O_RDONLY | O_NOFOLLOW)
        guard file >= 0 else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        defer { _ = Darwin.close(file) }
        return try readOpened(file)
    }

    private func publish(_ value: AppLockNotificationControlV1,
        expected: AppLockNotificationControlV1?) throws {
        let bytes = try CompatibilityCanonicalV1.encode(value)
        guard try Self.decode(bytes) == value, try loadControl() == expected else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        try publishBytes(bytes, recordName: Self.recordName, pendingName: Self.pendingName,
            expected: expected.map { try CompatibilityCanonicalV1.encode($0) })
    }

    private func publishBytes(_ bytes: Data, recordName: String, pendingName: String,
        expected: Data?, schedulingOwner: NotificationSchedulingPublicationOwner? = nil) throws {
        // Original-mode publication uses its separately checked EX route.
        guard originalErasePolicyIO == nil else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        if schedulingOwner == nil, recordName != Self.eraseName,
           Self.schedulingOwners.live[notificationRootIdentity] != nil {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        if let owner = schedulingOwner {
            guard recordName == Self.mappingName, pendingName == Self.mappingPendingName,
                  expected != nil, try schedulingState(owner) == expected,
                  owner.stage == nil else { throw AppAccessContractFailureV1.effectMismatch }
        }
        guard !bytes.isEmpty, bytes.count <= Self.maximumRecordBytes,
              try (schedulingOwner.map { try schedulingState($0) }
                ?? readFile(recordName, kind: .journal)) == expected else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        let pending = schedulingOwner == nil
            ? try readFile(pendingName, kind: .journalTemporary) : nil
        if let pending {
            // The ordinary route is unchanged. A new live owner never adopts
            // any preexisting stage, even one with exact successor bytes.
            guard pending == bytes else { throw AppAccessContractFailureV1.effectMismatch }
        } else {
            let file = Darwin.openat(authority.rootDescriptor, pendingName,
                (schedulingOwner == nil ? O_WRONLY : O_RDWR)
                    | O_CREAT | O_EXCL | O_NOFOLLOW
                    | (schedulingOwner == nil ? 0 : O_CLOEXEC), 0o600)
            guard file >= 0 else { throw AppAccessContractFailureV1.configurationUnknown }
            // Register the actual FD before any write, callback or throw.
            let stage = try schedulingOwner.map { owner -> SchedulingStage in
                let value = SchedulingStage(descriptor: file, bytes: bytes,
                    predecessor: expected!)
                owner.stage = value
#if DEBUG
                try schedulingTestingCut(owner, stage: value, cut: .afterStageOpenBeforeFirstFact)
#endif
                schedulingRecordFact(value, afterOwnedEffect: false)
                return value
            }
            defer { if schedulingOwner == nil { _ = Darwin.close(file) } }
            if let owner = schedulingOwner, let stage {
                _ = try schedulingState(owner)
                // INITIAL_CREATE: prove the actual same owned inode empty and
                // COMPLETE before writing any private mapping payload byte.
                stage.initialPolicyDisposition = try schedulingApplyStagePolicy(
                    owner, stage: stage, expectedPrefixCount: 0)
                stage.initialPolicyVerified = true
                _ = try schedulingState(owner)
#if DEBUG
                try schedulingTestingCut(owner, stage: stage, cut: .afterInitialPolicyVerificationBeforeWrite)
#endif
            }
            var offset = 0
            while offset < bytes.count {
                if let owner = schedulingOwner {
                    guard let stage, stage.initialPolicyVerified else {
                        throw AppAccessContractFailureV1.notificationReconciliationRequired
                    }
                    _ = try schedulingState(owner)
                }
#if DEBUG
                let requestedWriteCount = schedulingWriteCountForTesting(schedulingOwner,
                    stage: stage, remaining: bytes.count - offset)
#else
                let requestedWriteCount = bytes.count - offset
#endif
                let count = bytes.withUnsafeBytes { raw -> Int in
                    guard let base = raw.baseAddress else { return 0 }
                    return Darwin.write(file, base.advanced(by: offset), requestedWriteCount)
                }
                if count > 0 {
                    offset += count
                    stage?.prefixCount = offset
                    stage?.positiveWriteCounts.append(count)
                    if let stage { schedulingRecordFact(stage) }
#if DEBUG
                    if let owner = schedulingOwner, let stage {
                        try schedulingTestingCut(owner, stage: stage, cut: .afterPositivePrefix(offset))
                    }
#endif
                }
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw AppAccessContractFailureV1.configurationUnknown }
            }
            if let owner = schedulingOwner, let stage {
#if DEBUG
                try schedulingTestingCut(owner, stage: stage, cut: .afterFullWriteBeforeFinalPolicy)
#endif
                _ = try schedulingApplyStagePolicy(owner, stage: stage,
                    expectedPrefixCount: bytes.count)
                stage.finalPolicyVerified = true
#if DEBUG
                try schedulingTestingCut(owner, stage: stage, cut: .afterFinalPolicyBeforeFileSync)
#endif
            } else {
                // Existing ordinary publication remains under its established
                // final policy request. Only the live owner adds the initial
                // empty-stage checked policy boundary in this successor.
                let pinned = try information(pendingName)
                try ProtectedFilePolicyV1.applyAndVerify(.journalTemporary,
                    at: rootURL.appendingPathComponent(pendingName), authorityCheck: {
                        try self.verifyRoot()
                        var opened = stat()
                        guard Darwin.fstat(file, &opened) == 0,
                              let linked = try self.information(pendingName),
                              let pinned, opened.st_dev == pinned.st_dev, opened.st_ino == pinned.st_ino,
                              opened.st_dev == linked.st_dev, opened.st_ino == linked.st_ino else {
                            throw AppAccessContractFailureV1.configurationUnknown
                        }
                    })
            }
            if failurePoint == .afterPendingWriteBeforeSync {
                throw AppAccessContractFailureV1.effectMismatch
            }
        }
        if let owner = schedulingOwner {
            guard try schedulingState(owner) == expected,
                  let stage = owner.stage, stage.prefixCount == bytes.count,
                  stage.initialPolicyVerified, stage.finalPolicyVerified else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            stage.fileSyncAttempted = true
            guard Darwin.fsync(stage.descriptor) == 0 else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            stage.fileSynced = true
            schedulingRecordFact(stage)
            _ = try schedulingState(owner)
        } else {
            guard try readFile(pendingName, kind: .journalTemporary) == bytes,
                  try readFile(recordName, kind: .journal) == expected else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            try syncPendingFile(pendingName)
            try verifyRoot()
        }
#if DEBUG
        if let owner = schedulingOwner, let stage = owner.stage {
            try schedulingTestingCut(owner, stage: stage, cut: .beforeRename)
        }
#endif
        schedulingOwner?.stage?.renameAttempted = true
        let result: Int32
        if expected == nil {
            result = Darwin.renameatx_np(authority.rootDescriptor, pendingName,
                authority.rootDescriptor, recordName, UInt32(RENAME_EXCL))
        } else {
            result = Darwin.renameat(authority.rootDescriptor, pendingName,
                authority.rootDescriptor, recordName)
        }
        // Record successful namespace mutation before any durability check.
        if result == 0, let stage = schedulingOwner?.stage {
            stage.renamed = true; stage.name = recordName
            schedulingRecordFact(stage)
            if let fact = stage.fact { schedulingOwner?.canonicalFact = fact }
        }
        guard result == 0 else { throw AppAccessContractFailureV1.effectMismatch }
#if DEBUG
        if let owner = schedulingOwner, let stage = owner.stage {
            try schedulingTestingCut(owner, stage: stage, cut: .afterRenameBeforeParentSync)
        }
#endif
        if let owner = schedulingOwner {
            _ = try schedulingState(owner)
            owner.stage?.parentSyncAttempted = true
            guard Darwin.fsync(authority.rootDescriptor) == 0 else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            owner.stage?.parentSynced = true
#if DEBUG
            if let stage = owner.stage {
                try schedulingTestingCut(owner, stage: stage, cut: .afterParentSyncBeforeReadback)
            }
#endif
            guard try schedulingState(owner) == bytes else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            try schedulingCompleteStage(owner)
        } else {
            guard Darwin.fsync(authority.rootDescriptor) == 0,
                  try readFile(recordName, kind: .journal) == bytes else {
                throw AppAccessContractFailureV1.effectMismatch
            }
        }
    }

    private func syncPendingFile(_ pendingName: String) throws {
        guard let before = try information(pendingName) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let descriptor = Darwin.openat(authority.rootDescriptor, pendingName, O_RDWR | O_NOFOLLOW)
        guard descriptor >= 0 else { throw AppAccessContractFailureV1.configurationUnknown }
        defer { _ = Darwin.close(descriptor) }
        var opened = stat()
        guard Darwin.fstat(descriptor, &opened) == 0, Self.sameFile(before, opened) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try ProtectedFilePolicyV1.verify(.journalTemporary, at: rootURL.appendingPathComponent(pendingName))
        try verifyRoot()
        guard Darwin.fsync(descriptor) == 0,
              let linked = try information(pendingName), Self.sameFile(opened, linked) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
    }
}

/// Sole process adapter for the shared, noncanonical scratch root. Every byte
/// remains under `FieldEvidenceOperations`, so the closed owned-storage ledger
/// accounts for it while purpose-separated leases prevent support export from
/// reading capture/import/source scratch.
/// Mutable lease state and filesystem transactions are confined to this lock.
/// Async protocol entry points never suspend while holding it.
@MainActor final class OriginalEraseNotificationRootPolicyReceiptV1 {
    let firstRootFact: String
    let firstTreeDigest: String
    let projectedRootFact: String
    let projectedTreeDigest: String
    let disposition: ProtectedFileVerificationDispositionV1
    let didRequestCompleteProtection: Bool
    let checkedSettled: Bool
    private weak var operation: EraseRouterOperationV1?
    private weak var store: EraseIntentStore?
    private weak var registry: GenerationLeaseRegistryV1?
    private weak var exclusion: StoreTemporalNormalizationExclusionV1?
    private weak var activity: GenerationTemporalActivityHandleV1?

    fileprivate init(operation: EraseRouterOperationV1,
        store: EraseIntentStore, registry: GenerationLeaseRegistryV1,
        exclusion: StoreTemporalNormalizationExclusionV1,
        activity: GenerationTemporalActivityHandleV1,
        firstRootFact: String, firstTreeDigest: String,
        projectedRootFact: String, projectedTreeDigest: String,
        disposition: ProtectedFileVerificationDispositionV1,
        didRequestCompleteProtection: Bool) {
        self.operation = operation
        self.store = store
        self.registry = registry
        self.exclusion = exclusion
        self.activity = activity
        self.firstRootFact = firstRootFact
        self.firstTreeDigest = firstTreeDigest
        self.projectedRootFact = projectedRootFact
        self.projectedTreeDigest = projectedTreeDigest
        self.disposition = disposition
        self.didRequestCompleteProtection = didRequestCompleteProtection
        checkedSettled = true
    }

    func requireBound(operation: EraseRouterOperationV1,
        store: EraseIntentStore, registry: GenerationLeaseRegistryV1,
        exclusion: StoreTemporalNormalizationExclusionV1,
        activity: GenerationTemporalActivityHandleV1) throws {
        guard self.operation === operation, self.store === store,
              self.registry === registry, self.exclusion === exclusion,
              self.activity === activity, checkedSettled else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
    }
}

@MainActor final class OriginalEraseNotificationMarkerPublicationReceiptV1 {
    let revocation: NotificationEraseRevocationV1
    let canonicalBytes: Data
    let firstRootFact: String
    let projectedRootFact: String
    let firstTreeDigest: String
    let projectedTreeDigest: String
    let canonicalLeafFact: String
    let checkedSettled: Bool
    private weak var control: AppLockNotificationControlStoreV1?
    private weak var operation: EraseRouterOperationV1?
    private weak var store: EraseIntentStore?
    private weak var registry: GenerationLeaseRegistryV1?
    private weak var exclusion: StoreTemporalNormalizationExclusionV1?
    private weak var activity: GenerationTemporalActivityHandleV1?

    fileprivate init(control: AppLockNotificationControlStoreV1,
        operation: EraseRouterOperationV1, store: EraseIntentStore,
        registry: GenerationLeaseRegistryV1,
        exclusion: StoreTemporalNormalizationExclusionV1,
        activity: GenerationTemporalActivityHandleV1,
        revocation: NotificationEraseRevocationV1,
        canonicalBytes: Data, firstRootFact: String,
        projectedRootFact: String, firstTreeDigest: String,
        projectedTreeDigest: String, canonicalLeafFact: String) {
        self.control = control
        self.operation = operation
        self.store = store
        self.registry = registry
        self.exclusion = exclusion
        self.activity = activity
        self.revocation = revocation
        self.canonicalBytes = canonicalBytes
        self.firstRootFact = firstRootFact
        self.projectedRootFact = projectedRootFact
        self.firstTreeDigest = firstTreeDigest
        self.projectedTreeDigest = projectedTreeDigest
        self.canonicalLeafFact = canonicalLeafFact
        checkedSettled = true
    }

    func requireBound(control: AppLockNotificationControlStoreV1,
        operation: EraseRouterOperationV1, store: EraseIntentStore,
        registry: GenerationLeaseRegistryV1,
        exclusion: StoreTemporalNormalizationExclusionV1,
        activity: GenerationTemporalActivityHandleV1) throws {
        guard self.control === control, self.operation === operation,
              self.store === store, self.registry === registry,
              self.exclusion === exclusion, self.activity === activity,
              checkedSettled else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
    }
}

@MainActor final class OriginalEraseNotificationRecordRemovalReceiptV1 {
    let finalRootFact: String
    let finalTreeDigest: String
    let removedNames: Set<String>
    let checkedSettled = true
    private weak var control: AppLockNotificationControlStoreV1?
    private weak var absence: OriginalEraseNotificationOSAbsenceReceiptV1?
    private weak var marker: OriginalEraseNotificationMarkerPublicationReceiptV1?

    fileprivate init(control: AppLockNotificationControlStoreV1,
        absence: OriginalEraseNotificationOSAbsenceReceiptV1,
        marker: OriginalEraseNotificationMarkerPublicationReceiptV1,
        finalRootFact: String, finalTreeDigest: String,
        removedNames: Set<String>) {
        self.control = control
        self.absence = absence
        self.marker = marker
        self.finalRootFact = finalRootFact
        self.finalTreeDigest = finalTreeDigest
        self.removedNames = removedNames
    }

    func requireBound(control: AppLockNotificationControlStoreV1,
        absence: OriginalEraseNotificationOSAbsenceReceiptV1,
        marker: OriginalEraseNotificationMarkerPublicationReceiptV1
    ) throws {
        guard self.control === control, self.absence === absence,
              self.marker === marker, checkedSettled else {
            throw AppAccessContractFailureV1
                .notificationReconciliationRequired
        }
    }
}

@MainActor final class OriginalEraseScratchControlPolicyReceiptV1 {
    let firstRootFact: String?
    let firstTreeDigest: String?
    let projectedRootFact: String?
    let projectedTreeDigest: String?
    let disposition: ProtectedFileVerificationDispositionV1?
    let checkedSettled: Bool
    private weak var operation: EraseRouterOperationV1?
    private weak var store: EraseIntentStore?
    private weak var registry: GenerationLeaseRegistryV1?
    private weak var exclusion: StoreTemporalNormalizationExclusionV1?
    private weak var activity: GenerationTemporalActivityHandleV1?

    fileprivate init(operation: EraseRouterOperationV1,
        store: EraseIntentStore, registry: GenerationLeaseRegistryV1,
        exclusion: StoreTemporalNormalizationExclusionV1,
        activity: GenerationTemporalActivityHandleV1,
        firstRootFact: String?, firstTreeDigest: String?,
        projectedRootFact: String?, projectedTreeDigest: String?,
        disposition: ProtectedFileVerificationDispositionV1?) {
        self.operation = operation
        self.store = store
        self.registry = registry
        self.exclusion = exclusion
        self.activity = activity
        self.firstRootFact = firstRootFact
        self.firstTreeDigest = firstTreeDigest
        self.projectedRootFact = projectedRootFact
        self.projectedTreeDigest = projectedTreeDigest
        self.disposition = disposition
        checkedSettled = true
    }

    func requireBound(operation: EraseRouterOperationV1,
        store: EraseIntentStore,
        registry: GenerationLeaseRegistryV1,
        exclusion: StoreTemporalNormalizationExclusionV1,
        activity: GenerationTemporalActivityHandleV1) throws {
        guard self.operation === operation, self.store === store,
              self.registry === registry, self.exclusion === exclusion,
              self.activity === activity, checkedSettled else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
    }
}

enum OriginalEraseC16PartialDirectoryV1: Codable, Equatable {
    case control
    case lease(String)
}

/// One deterministic sidecar ordinal. The Router binds every associated ID
/// and first-P fact to its immutable roster before passing a step here.
enum OriginalEraseC16StepV1: Codable, Equatable {
    case settleFirstPPartial(directory: OriginalEraseC16PartialDirectoryV1,
        name: String, device: UInt64, inode: UInt64, byteCount: Int64)
    case resumeControlTail
    case resumeHygiene(operationID: UUID)
    case resumeIngressErase(operationID: UUID)
    case recoverIngressPointer(intentID: UUID)
    case eraseIngress
    case eraseFinalControl
}

struct OriginalEraseC16FileFactV1: Codable, Equatable {
    let name: String
    let device: UInt64
    let inode: UInt64
    let byteCount: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64

    fileprivate init(name: String, device: UInt64, inode: UInt64,
        byteCount: Int64, modifiedSeconds: Int64, modifiedNanoseconds: Int64) {
        self.name = name; self.device = device; self.inode = inode
        self.byteCount = byteCount; self.modifiedSeconds = modifiedSeconds
        self.modifiedNanoseconds = modifiedNanoseconds
    }

    fileprivate init(_ value: C16IngressHygieneFileIdentityV1) {
        name = value.name
        device = value.device
        inode = value.inode
        byteCount = value.byteCount
        modifiedSeconds = value.modifiedSeconds
        modifiedNanoseconds = value.modifiedNanoseconds
    }
}

struct OriginalEraseC16TargetFactV1: Codable, Equatable {
    let directoryName: String
    let device: UInt64
    let inode: UInt64
    let files: [OriginalEraseC16FileFactV1]

    fileprivate init(directoryName: String, device: UInt64, inode: UInt64,
        files: [C16IngressHygieneFileIdentityV1]) {
        self.directoryName = directoryName
        self.device = device
        self.inode = inode
        self.files = files.map(OriginalEraseC16FileFactV1.init)
    }

    fileprivate init(_ value: C16IngressHygieneTargetV1) {
        directoryName = value.directoryName
        device = value.device
        inode = value.inode
        files = value.files.map(OriginalEraseC16FileFactV1.init)
    }

    fileprivate init(_ value: C16IngressPublicationV1) {
        directoryName = value.claim.preparation.lease.relativeDirectory
        device = value.claim.device
        inode = value.claim.inode
        files = [value.metadata, value.payload]
            .sorted { $0.name < $1.name }
            .map(OriginalEraseC16FileFactV1.init)
    }
}

struct OriginalEraseC16MarkerBindingV1: Codable, Equatable {
    let name: String
    let sha256: String
    /// The exact semantic target order decoded from canonical first-P bytes.
    /// Empty for markers whose target mapping is retained by their paired
    /// prepare or publication marker.
    let targets: [OriginalEraseC16TargetFactV1]
    /// Parallel to `targets` for an erase prepare: unpublished targets first,
    /// then published targets, retaining the exact two C16 group orders.
    /// A published ingress marker carries its sole intent ID as well.
    let targetIntentIDs: [UUID]
    let unpublishedTargetCount: Int
    /// Only `scratch-erase.json` carries this sorted control-tail roster.
    let controlFiles: [OriginalEraseC16FileFactV1]
}

struct OriginalEraseC16PlannedTargetV1: Codable, Equatable {
    let intentID: UUID
    /// Nil is the prepared-only ingress with no published claim directory.
    let directory: OriginalEraseC16TargetFactV1?
}

struct OriginalEraseC16PlanV1: Codable, Equatable {
    static let maximumEncodedBytes = 96 * 1_024 * 1_024
    let steps: [OriginalEraseC16StepV1]
    /// Both a lease's original name and any observed `.deleting-*` name are
    /// excluded from generic lease ordinals by the Router.
    let ownedLeaseNames: [String]
    let markerBindings: [OriginalEraseC16MarkerBindingV1]
    /// Semantic projection for the one post-P original-operation C16 erase
    /// prepare. The first list is published, the second unpublished; each is
    /// sorted by intent ID in its own C16 group order.
    let freshPublishedTargets: [OriginalEraseC16PlannedTargetV1]
    let freshUnpublishedTargets: [OriginalEraseC16PlannedTargetV1]

    func validate() throws {
        guard steps.count <= 100_000,
              ownedLeaseNames == ownedLeaseNames.sorted(),
              Set(ownedLeaseNames).count == ownedLeaseNames.count,
              markerBindings.count <= 100_000,
              markerBindings.map(\.name) == markerBindings.map(\.name).sorted(),
              Set(markerBindings.map(\.name)).count == markerBindings.count else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        for group in [freshPublishedTargets, freshUnpublishedTargets] {
            guard group.map({ $0.intentID.uuidString })
                    == group.map({ $0.intentID.uuidString }).sorted(),
                  Set(group.map(\.intentID)).count == group.count else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        }
        guard Set(freshPublishedTargets.map(\.intentID))
                .isDisjoint(with: freshUnpublishedTargets.map(\.intentID)) else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        for marker in markerBindings {
            guard OperationalDiagnosticsBoundsV1.validRelativeName(marker.name),
                  CompatibilityCanonicalV1.validSHA256(marker.sha256),
                  marker.targets.count <= 100_000,
                  marker.targetIntentIDs.count <= marker.targets.count,
                  marker.unpublishedTargetCount >= 0,
                  marker.unpublishedTargetCount <= marker.targetIntentIDs.count,
                  Set(marker.targetIntentIDs).count == marker.targetIntentIDs.count,
                  marker.controlFiles.count <= 100_000 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        }
        guard try CompatibilityCanonicalV1.encode(self).count
            <= Self.maximumEncodedBytes else {
            throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
        }
    }
}

/// Router derives this value solely from the canonical current sidecar and
/// the immutable mixed target list. It is read input, never an EX/G capability.
/// The full `.c16` subsequence must equal `plan.steps` before constructing it.
struct OriginalEraseC16ReferenceProgressV1: Equatable {
    let completedC16PrefixCount: Int
    let activeC16Ordinal: Int?
    let recordStage: OriginalScratchLifecycleRecordV1.Stage

    func validate(plan: OriginalEraseC16PlanV1) throws {
        guard completedC16PrefixCount >= 0,
              completedC16PrefixCount <= plan.steps.count,
              recordStage == .prepared || recordStage == .preparing
                || recordStage == .preparingCaptured || recordStage == .completed else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        if let activeC16Ordinal {
            guard activeC16Ordinal == completedC16PrefixCount,
                  activeC16Ordinal < plan.steps.count,
                  recordStage == .preparing || recordStage == .preparingCaptured else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        }
    }
}

enum OriginalEraseC16CutV1: Codable, Equatable {
    case preimage
    case intermediate
    case terminal
}

enum OriginalEraseC16ControlMarkerStateV1: Equatable {
    case notYetCaptured
    case capturedPublished
}

enum OriginalEraseC16IngressMarkerStateV1: Equatable {
    case notYetCaptured
    case capturedPublished
}

enum OriginalEraseC16TargetLocationV1: Equatable {
    case original
    case tombstone(removedChildCount: Int)
    case absent
}

struct OriginalEraseC16ObservedTargetV1: Equatable {
    let source: OriginalEraseC16TargetFactV1
    let location: OriginalEraseC16TargetLocationV1
}

/// Authenticated semantic cut observations. The FirstObserver applies these
/// to immutable first-P full facts and Store-captured post-P birth facts; none
/// of these observed names or locations becomes authority by itself.
struct OriginalEraseC16ObservedProjectionV1: Equatable {
    let currentCut: OriginalEraseC16CutV1
    let targets: [OriginalEraseC16ObservedTargetV1]
    let controlRootPresent: Bool
    let observedControlNames: [String]
    /// Present only for a durable control-tail marker. The marker's canonical
    /// ordered files are authority only when its first-P binding or Store's
    /// captured post-P birth fact has been independently proved by Router.
    let controlTail: OriginalEraseC16ControlTailProjectionV1?
}

struct OriginalEraseC16ControlTailProjectionV1: Equatable {
    let markerFileNames: [String]
    let removedPrefixNames: [String]
    let expectedControlNames: [String]
}

struct OriginalEraseC16CapturedBirthV1: Equatable {
    let name: String
    let fullFact: String
    let sha256: String
}

enum OriginalEraseC16ExpectedFileSourceV1: Equatable {
    case firstP(sourcePath: String, allowOneLinkSettlement: Bool)
    case postPDeterministic(role: String, fullFact: String,
        sha256: String)
}

struct OriginalEraseC16ExpectedFileV1: Equatable {
    let path: String
    let source: OriginalEraseC16ExpectedFileSourceV1
}

struct OriginalEraseC16ExpectedDirectoryV1: Equatable {
    let path: String
    let firstPSourcePath: String
    let expectedMembers: [String]
    let expectedLinkCount: UInt64
}

struct OriginalEraseC16ExpectedTreeV1: Equatable {
    let currentOrdinal: Int
    let currentCut: OriginalEraseC16CutV1
    let files: [OriginalEraseC16ExpectedFileV1]
    let directories: [OriginalEraseC16ExpectedDirectoryV1]
    let consumedFirstPPaths: [String]
}

struct OriginalEraseC16BornSourceObservationV1: Equatable {
    let role: String
    let path: String
    let bytes: Data
    let fullFact: String
    let sha256: String
}

@MainActor final class OriginalEraseC16BoundaryObservationV1 {
    enum Purpose: String { case inspection, bornSource }
    let boundaryID: UUID
    let planSHA256: String
    let stepSHA256: String
    let ordinal: Int
    let purpose: Purpose
    let projection: OriginalEraseC16ExpectedTreeV1
    let bornSource: OriginalEraseC16BornSourceObservationV1?
    fileprivate init(planSHA256: String, stepSHA256: String, ordinal: Int,
        projection: OriginalEraseC16ExpectedTreeV1,
        bornSource: OriginalEraseC16BornSourceObservationV1?) {
        boundaryID = UUID(); self.planSHA256 = planSHA256
        self.stepSHA256 = stepSHA256; self.ordinal = ordinal
        purpose = bornSource == nil ? .inspection : .bornSource
        self.projection = projection; self.bornSource = bornSource
    }
}

struct OriginalEraseC16CurrentPairV1: Equatable {
    let finalURL: URL
    let partialURL: URL
    let bytes: Data
    let expectedDevice: UInt64
    let finalFullFact: String
    let partialFullFact: String
}

struct OriginalEraseC16CurrentZeroV1: Equatable {
    let finalURL: URL
    let temporaryURL: URL
    let expectedDevice: UInt64
    let temporaryFullFact: String
}

struct OriginalEraseC16CurrentPrefixV1: Equatable {
    let finalURL: URL
    let temporaryURL: URL
    let expectedBytes: Data
    let observedBytes: Data
    let expectedDevice: UInt64
    let temporaryFullFact: String
}

enum OriginalEraseC16CurrentPathRoleV1: Equatable {
    case ordinary
    case pair(OriginalEraseC16CurrentPairV1)
    case firstPPair(OriginalEraseC16FirstPPairV1)
    case unacceptedEmptyPublication(OriginalEraseC16CurrentZeroV1)
    case publicationPrefix(OriginalEraseC16CurrentPrefixV1)
}

/// Observation-only capability. Only the Ledger's actual fixed publication
/// role may issue it; there is no raw link-count exemption or success flag.
@MainActor final class OriginalEraseC16CurrentObservationScopeV1 {
    let operationID: UUID
    let planSHA256: String
    let ordinal: Int
    private let roles: [String: OriginalEraseC16CurrentPathRoleV1]
    private let firstPObservationScope: OriginalEraseC16FirstPObservationScopeV1
    private let requireBinding: @MainActor () throws -> Void
    private let poison: @MainActor () -> Void
    private var retainedAttempts: [OriginalEraseC16CurrentTemporalObservationAttemptV1] = []
    fileprivate init(operationID: UUID, planSHA256: String, ordinal: Int,
        roles: [String: OriginalEraseC16CurrentPathRoleV1],
        firstPObservationScope: OriginalEraseC16FirstPObservationScopeV1,
        requireBinding: @escaping @MainActor () throws -> Void,
        poison: @escaping @MainActor () -> Void) {
        self.operationID = operationID; self.planSHA256 = planSHA256
        self.ordinal = ordinal; self.roles = roles
        self.firstPObservationScope = firstPObservationScope
        self.requireBinding = requireBinding; self.poison = poison
    }
    func requireCurrentBinding() throws { try requireBinding() }
    func requireFirstPObservationScope() throws -> OriginalEraseC16FirstPObservationScopeV1 {
        try requireCurrentBinding(); try firstPObservationScope.requireCurrentBinding()
        return firstPObservationScope
    }
    func requirePair(finalURL: URL, partialURL: URL) throws -> OriginalEraseC16CurrentPairV1 {
        try requireCurrentBinding()
        for role in roles.values {
            if case let .pair(pair) = role,
               pair.finalURL.standardizedFileURL == finalURL.standardizedFileURL,
               pair.partialURL.standardizedFileURL == partialURL.standardizedFileURL {
                try requireCurrentBinding(); return pair
            }
        }
        throw ScratchDataLeaseStoreFailureV1.leaseCollision
    }
    /// Factory visits both exceptional paths in the complete closed tree.
    /// All unassigned paths retain the ordinary strict predicates.
    func roleFor(path: String, fullFact: String, sha256: String) throws -> OriginalEraseC16CurrentPathRoleV1 {
        try requireCurrentBinding()
        guard let role = roles[path] else { return .ordinary }
        switch role {
        case .ordinary: return .ordinary
        case let .pair(pair):
            guard fullFact == pair.finalFullFact || fullFact == pair.partialFullFact,
                  try CompatibilityCanonicalV1.sha256(pair.bytes) == sha256 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        case let .firstPPair(pair):
            guard fullFact == pair.finalFullFact || fullFact == pair.partialFullFact,
                  sha256 == pair.expectedSHA256 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        case let .unacceptedEmptyPublication(zero):
            guard fullFact == zero.temporaryFullFact,
                  try CompatibilityCanonicalV1.sha256(Data()) == sha256 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        case let .publicationPrefix(prefix):
            guard fullFact == prefix.temporaryFullFact,
                  prefix.expectedBytes.starts(with: prefix.observedBytes),
                  try CompatibilityCanonicalV1.sha256(prefix.observedBytes) == sha256 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        }
        try requireCurrentBinding(); return role
    }
    func retainObservationAttempt(_ attempt: OriginalEraseC16CurrentTemporalObservationAttemptV1) {
        retainedAttempts.append(attempt)
    }
    func poisonOnUncertainObservation() { poison() }
}

struct OriginalEraseC16FirstPPairV1: Equatable {
    let finalURL: URL
    let partialURL: URL
    let finalOriginalFact: String
    let partialOriginalFact: String
    let expectedSHA256: String
    let expectedByteCount: Int64
    let expectedDevice: UInt64
    let finalFullFact: String
    let partialFullFact: String
    let assignedSettlementOrdinal: Int
    let planSHA256: String
    let currentOrdinal: Int
}

@MainActor final class OriginalEraseC16FirstPObservationScopeV1 {
    let operationID: UUID
    let planSHA256: String
    let currentOrdinal: Int
    private let pairs: [OriginalEraseC16FirstPPairV1]
    private let requireBinding: @MainActor () throws -> Void
    private let poison: @MainActor () -> Void
    private var retainedAttempts: [OriginalEraseC16CurrentTemporalObservationAttemptV1] = []
    fileprivate init(operationID: UUID, planSHA256: String, currentOrdinal: Int,
        pairs: [OriginalEraseC16FirstPPairV1],
        requireBinding: @escaping @MainActor () throws -> Void,
        poison: @escaping @MainActor () -> Void) {
        self.operationID = operationID; self.planSHA256 = planSHA256
        self.currentOrdinal = currentOrdinal; self.pairs = pairs
        self.requireBinding = requireBinding; self.poison = poison
    }
    func requireCurrentBinding() throws { try requireBinding() }
    func requirePair(finalURL: URL, partialURL: URL) throws -> OriginalEraseC16FirstPPairV1 {
        try requireCurrentBinding()
        guard let pair = pairs.first(where: { $0.finalURL == finalURL && $0.partialURL == partialURL }) else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try requireCurrentBinding(); return pair
    }
    func roleFor(path: String, fullFact: String, sha256: String) throws -> OriginalEraseC16FirstPPairV1? {
        try requireCurrentBinding()
        guard let pair = pairs.first(where: {
            let suffix = "/" + OwnedStorageRootKindV1.operations.rawValue + "/" + path
            return $0.finalURL.path.hasSuffix(suffix) || $0.partialURL.path.hasSuffix(suffix)
        }) else { return nil }
        guard fullFact == pair.finalFullFact || fullFact == pair.partialFullFact,
              sha256 == pair.expectedSHA256 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        try requireCurrentBinding(); return pair
    }
    func retainObservationAttempt(_ attempt: OriginalEraseC16CurrentTemporalObservationAttemptV1) {
        retainedAttempts.append(attempt)
    }
    func poisonOnUncertainObservation() { poison() }
}

struct OriginalEraseFrozenLeaseCutV1: Equatable {
    let tombstoned: Bool
    let removedChildCount: Int
    let leaseRootRemoved: Bool
}

struct OriginalEraseFrozenLeaseAdmissionV1 {
    let originalName: String
    let expectedDevice: UInt64
    let expectedInode: UInt64
    let orderedChildren: [String]
    /// The Router must prove the same-op preparing sidecar ordinal and exact
    /// immutable first-P whole-tree prefix before metadata-free admission.
    let requirePrefix: @MainActor (Bool, Int, Bool) throws -> Void
}

final class ScratchDataLeaseStoreV1: ScratchDataLeasePortV1, @unchecked Sendable {
    private static let filesystemLock = NSRecursiveLock()
    private var lock: NSRecursiveLock { Self.filesystemLock }
    private let ingressHygieneFailureInjection: C16IngressHygieneFailureInjectionV1
    private let ingressMutationFailureInjection: C16IngressMutationFailureInjectionV1
    typealias Clock = @Sendable () -> Date
    #if DEBUG
    typealias IngressControlInventoryObserver = @Sendable () -> Void
    typealias BeforeIngressControlFinalInventory = @Sendable () throws -> Void
    #endif

    private static let rootName = "ScratchDataV1"
    private static let metadataName = "lease.json"
    private static let deletionPrefix = ".deleting-"
    private static let controlEraseName = "scratch-erase.json"

    private let rootURL: URL
    private let clock: Clock
    private let storagePreflight: StoragePreflightService
    private let authority: PinnedScratchRootV1
    #if DEBUG
    private var ingressControlInventoryObserver: IngressControlInventoryObserver = {}
    private var beforeIngressControlFinalInventory: BeforeIngressControlFinalInventory = {}
    #endif
    private var active: [UUID: ScratchDataLeaseV1] = [:]
    private var exclusiveNoRepairRead = false
    // Retained by the already-owned exclusive Store before the first receipt
    // scan. An ambiguous checked close cannot escape with a local IO value.
    private var originalEraseSourceReceiptIO: EraseAbortCheckedSnapshotIOV1?

    private func applySourceReadPolicy(
        _ kind: OwnedFileKindV1, at url: URL,
        authorityCheck: () throws -> Void = {}
    ) throws {
        try requireScratchDescriptorAccess()
        if exclusiveNoRepairRead {
            try ProtectedFilePolicyV1.applyAndVerifyEraseColdPrivateWithCheckedClose(
                kind, at: url,
                retainUncertainDescriptor: {
                    _ = ScratchUncertainCloseQuarantineV1.shared.begin($0)
                }, authorityCheck: authorityCheck)
        } else {
            try ProtectedFilePolicyV1.applyAndVerify(
                kind, at: url, authorityCheck: authorityCheck)
        }
    }

    private func verifySourceReadPolicy(
        _ kind: OwnedFileKindV1, at url: URL
    ) throws {
        try requireScratchDescriptorAccess()
        if exclusiveNoRepairRead {
            if originalEraseBorrowedExclusiveCheck != nil,
               (try originalEraseC16VerifyScopedPairPolicy(at: url)
                || originalEraseC16VerifyFirstPPairPolicy(at: url)) { return }
            try ProtectedFilePolicyV1.verifyEraseColdPrivateWithCheckedClose(
                kind, at: url, retainUncertainDescriptor: {
                    _ = ScratchUncertainCloseQuarantineV1.shared.begin($0)
                })
        } else {
            try ProtectedFilePolicyV1.verify(kind, at: url)
        }
    }
    // Populated only by real returned in-process acquisitions, never by cold
    // metadata recovery. A serializable lease is not a live producer proof.
    private var producerActivities: [UUID: OwnedStorageProducerActivityV1] = [:]
    // Installed only for the lexical original-Erase EX/G scope. Nested
    // hygiene and ingress settlement reuse the same owner rather than opening
    // a new producer SH against its retained Support EX.
    // Ordinary primitives prove local held descriptor/Operations lineage.
    // Actual Registry/Support authority stays on the MainActor controller;
    // this local closure never reconstructs an EX/G permit from snapshots.
    private var originalEraseBorrowedExclusiveCheck: (() throws -> Void)?
    @MainActor private var originalEraseBorrowedOwnerCheck:
        (@MainActor () throws -> Void)?
    private var originalEraseOperationID: UUID?
    private enum OriginalEraseBorrowedLifetimeV1 { case ordinary, active, closed, uncertain }
    private var originalEraseBorrowedLifetime: OriginalEraseBorrowedLifetimeV1 = .ordinary

    private func requireScratchDescriptorAccess() throws {
        switch originalEraseBorrowedLifetime {
        case .ordinary: return
        case .active:
            guard originalEraseBorrowedExclusiveCheck != nil else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
        case .closed, .uncertain: throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
    }

    private var originalEraseBorrowedAdmitting = false
    private var originalEraseRootRemovalProved = false
    private var originalEraseControlRemovalProved = false
    // Installed only around one Router-prepared C16 sidecar ordinal. Every
    // C16 writer below checks the exact current physical cut through it.
    @MainActor private var originalEraseC16CutCheck:
        (@MainActor (OriginalEraseC16BoundaryObservationV1) throws -> OriginalEraseC16BoundaryReceiptV1)?
    // Immutable sidecar input, installed before cold admission. Nil is only
    // the initial first-P source-proof scope; it is never a replay fallback.
    private var originalEraseC16ReferencePlan: OriginalEraseC16PlanV1?
    private var originalEraseC16AdmissionProgress: OriginalEraseC16ReferenceProgressV1?
    private var originalEraseC16InitialSourceProof = false
    private var originalEraseC16CurrentOrdinal: Int?
    private var originalEraseC16CurrentControlMarkerState: OriginalEraseC16ControlMarkerStateV1?
    private var originalEraseC16CurrentIngressMarkerState: OriginalEraseC16IngressMarkerStateV1?
    // Immutable data inputs are retained separately from the persisted plan.
    // They never cache authority: the real permit reauthenticates the transfer
    // and current physical cut at every MainActor engine boundary.
    private struct OriginalEraseC16SourceInputV1 {
        let bytes: Data
        let fullFact: String
    }
    private var originalEraseC16SourceInputs: [String: OriginalEraseC16SourceInputV1] = [:]
    private var originalEraseC16BornSourceInputs: [String: OriginalEraseC16SourceInputV1] = [:]
    private var originalEraseC16FirstPFacts: [String: String] = [:]
    private var originalEraseC16FirstPAbsentPaths = Set<String>()
    @MainActor private var originalEraseColdPermit: EraseSchema2ColdScratchLifecyclePermitV1?

    private var originalEraseC16Planning = false
    private var originalEraseC16Classifying = false
    private var originalEraseFrozenLeaseAdmission:
        OriginalEraseFrozenLeaseAdmissionV1?

    private static func originalEraseC16SourceMaximum(name: String) -> Int {
        if name == controlEraseName || name.hasPrefix(".partial-") { return 32 * 1_024 * 1_024 }
        if name.hasPrefix("hygiene-"), name.hasSuffix(".json"),
           !name.hasSuffix(".prepare.json"), !name.hasSuffix(".prepare.json.finalizing") { return 4_096 }
        return 262_144
    }

    private struct OriginalEraseC16PhysicalFactV1 {
        let device: UInt64
        let inode: UInt64
        let mode: UInt64
        let uid: UInt64?
        let gid: UInt64?
        let linkCount: UInt64
        let byteCount: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        init(_ text: String) throws {
            let fields = text.split(separator: "|", omittingEmptySubsequences: false)
            // Node.fact is the unchanged persisted nine-field roster format.
            // A transferred source's real held full fact has eleven fields.
            // Missing uid/gid are never synthesized into an original-P fact.
            guard fields.count == 9 || fields.count == 11 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            let offset = fields.count == 11 ? 2 : 0
            guard let device = UInt64(fields[0]), let inode = UInt64(fields[1]),
                  let mode = UInt64(fields[2]), let links = UInt64(fields[3 + offset]),
                  let bytes = Int64(fields[4 + offset]), let seconds = Int64(fields[5 + offset]),
                  let nanos = Int64(fields[6 + offset]), Int64(fields[7 + offset]) != nil,
                  Int64(fields[8 + offset]) != nil, inode != 0, nanos >= 0,
                  nanos < 1_000_000_000 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            self.device = device; self.inode = inode; self.mode = mode
            uid = fields.count == 11 ? UInt64(fields[3]) : nil
            gid = fields.count == 11 ? UInt64(fields[4]) : nil
            guard fields.count == 9 || (uid != nil && gid != nil) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            linkCount = links; byteCount = bytes
            modifiedSeconds = seconds; modifiedNanoseconds = nanos
        }
        func matches(_ file: OriginalEraseC16FileFactV1, allowPair: Bool = false) -> Bool {
            device == file.device && inode == file.inode && byteCount == file.byteCount
                && modifiedSeconds == file.modifiedSeconds
                && modifiedNanoseconds == file.modifiedNanoseconds
                && mode & UInt64(S_IFMT) == UInt64(S_IFREG) && (linkCount == 1 || (allowPair && linkCount == 2))
                && (uid == nil || uid == UInt64(Darwin.geteuid()))
                && (gid == nil || gid == UInt64(Darwin.getegid()))
        }
        var modifiedAt: Date {
            Date(timeIntervalSince1970: TimeInterval(modifiedSeconds)
                + TimeInterval(modifiedNanoseconds) / 1_000_000_000)
        }
    }

    private static func originalEraseC16NineFieldFact(_ value: stat) -> String {
        "\(value.st_dev)|\(value.st_ino)|\(value.st_mode)|\(value.st_nlink)|\(value.st_size)|\(value.st_mtimespec.tv_sec)|\(value.st_mtimespec.tv_nsec)|\(value.st_ctimespec.tv_sec)|\(value.st_ctimespec.tv_nsec)"
    }

    @MainActor private func primeOriginalEraseC16ImmutableInputs(
        plan: OriginalEraseC16PlanV1?
    ) throws {
        try requireScratchDescriptorAccess()
        guard let permit = originalEraseColdPermit else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try permit.requireObservationBinding()
        var inputs: [String: OriginalEraseC16SourceInputV1] = [:]
        let names: [String]
        if let plan { names = plan.markerBindings.map(\.name) }
        else if try hasExistingIngressControl() { names = try directoryNames(ingressControlDescriptor()) }
        else { names = [] }
        guard names.count <= 100_000, names == names.sorted(), Set(names).count == names.count else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        var bytesTotal = 0
        for name in names {
            guard !name.hasPrefix(".partial-") else { continue }
            try permit.requireObservationBinding()
            let path = "ProtectedIngressReceiptsV1/" + name
            let input: OriginalEraseC16SourceInputV1
            if let plan {
                let transfer = try permit.canonicalTransferredSource(path: path)
                guard let binding = plan.markerBindings.first(where: { $0.name == name }),
                      try CompatibilityCanonicalV1.sha256(transfer.bytes) == binding.sha256 else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                try permit.requireTransferredSource(path: path, bytes: transfer.bytes, fullFact: transfer.fullFact)
                input = .init(bytes: transfer.bytes, fullFact: transfer.fullFact)
            } else {
                guard let originalFact = try permit.originalPPhysicalFact(path: path),
                      let leaf = try readOriginalErasePublicationLeaf(named: name,
                        parent: ingressControlDescriptor(), maximumBytes: Self.originalEraseC16SourceMaximum(name: name)),
                      Self.originalEraseC16NineFieldFact(leaf.0) == originalFact else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                input = .init(bytes: leaf.1, fullFact: Self.originalEraseSourceFullFact(leaf.0))
            }
            guard input.bytes.count <= Self.originalEraseC16SourceMaximum(name: name) else {
                throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
            }
            let charge = bytesTotal.addingReportingOverflow(input.bytes.count)
            guard !charge.overflow, charge.partialValue <= 1_024 * 1_024 * 1_024 else {
                throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
            }
            bytesTotal = charge.partialValue; inputs[name] = input
            try permit.requireObservationBinding()
        }
        originalEraseC16SourceInputs = inputs
        var targets: [OriginalEraseC16TargetFactV1] = plan?.markerBindings.flatMap(\.targets) ?? []
        targets += plan?.freshPublishedTargets.compactMap(\.directory) ?? []
        targets += plan?.freshUnpublishedTargets.compactMap(\.directory) ?? []
        var preparationNames = Set<String>()
        for name in names {
            guard !name.hasPrefix(".partial-") else { continue }
            if name.hasPrefix("hygiene-"), name.hasSuffix(".prepare.json") {
                let value = try originalEraseC16ReferenceValue(C16IngressHygienePrepareV1.self, name: name)
                try value.validate(); targets += value.targets.map(OriginalEraseC16TargetFactV1.init)
            } else if name.hasPrefix("erase-"), name.hasSuffix(".prepare.json") {
                let value = try originalEraseC16ReferenceValue(C16IngressEraseV1.self, name: name)
                try value.validate()
                targets += value.targets.map(OriginalEraseC16TargetFactV1.init)
                targets += value.unpublishedTargets.compactMap { $0.directory.map(OriginalEraseC16TargetFactV1.init) }
            } else if name.hasPrefix("ingress-"), name.hasSuffix(".published.json") {
                let value = try originalEraseC16ReferenceValue(C16IngressPublicationV1.self, name: name)
                try value.validate(); targets.append(.init(value))
            } else if name.hasPrefix("ingress-"), name.hasSuffix(".prepare.json") {
                let value = try originalEraseC16ReferenceValue(C16IngressPreparedStageV1.self, name: name)
                try value.validate(); preparationNames.insert(value.lease.relativeDirectory)
            }
        }
        var paths = Set(names.map { "ProtectedIngressReceiptsV1/" + $0 })
        for target in targets {
            for name in [target.directoryName, Self.deletionTombstoneName(for: target.directoryName)] {
                let path = "ScratchDataV1/" + name
                paths.insert(path)
                for child in target.files { paths.insert(path + "/" + child.name) }
            }
        }
        for name in preparationNames {
            for location in [name, Self.deletionTombstoneName(for: name)] {
                let path = "ScratchDataV1/" + location
                paths.insert(path)
                for child in [Self.metadataName, "opaque-data"] { paths.insert(path + "/" + child) }
                // Only the positive immutable-P scope may discover initial
                // claimed-only children. Replay uses the fixed plan/H/E source.
                if plan == nil, try directoryInformationIfPresent(named: location) != nil {
                    let descriptor = try openLeaseDirectory(location)
                    let children = try withObservedScratchDescriptor(descriptor) { try directoryNames($0) }
                    for child in children { paths.insert(path + "/" + child) }
                }
            }
        }
        if let plan {
            for step in plan.steps {
                if case let .settleFirstPPartial(directory, name, _, _, _) = step {
                    switch directory {
                    case .control: paths.insert("ProtectedIngressReceiptsV1/" + name)
                    case let .lease(lease): paths.insert("ScratchDataV1/" + lease + "/" + name)
                    }
                }
            }
        }
        guard paths.count <= 100_000 else { throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded }
        for path in paths.sorted() {
            try permit.requireObservationBinding()
            if let fact = try permit.originalPPhysicalFact(path: path) {
                _ = try OriginalEraseC16PhysicalFactV1(fact)
                originalEraseC16FirstPFacts[path] = fact
            } else { originalEraseC16FirstPAbsentPaths.insert(path) }
            try permit.requireObservationBinding()
        }
        if let plan, let progress = originalEraseC16AdmissionProgress {
            for (step, role, name) in [
                (OriginalEraseC16StepV1.eraseIngress, "freshIngressErasePrepare", "erase-" + originalEraseOperationID!.uuidString.lowercased() + ".prepare.json"),
                (OriginalEraseC16StepV1.eraseFinalControl, "scratchControlErase", Self.controlEraseName)
            ] {
                guard let ordinal = plan.steps.firstIndex(of: step) else { continue }
                if ordinal < progress.completedC16PrefixCount || (progress.activeC16Ordinal == ordinal && progress.recordStage == .preparingCaptured) {
                    try permit.requireObservationBinding()
                    let source = try permit.canonicalBornTransferredSource(path: "ProtectedIngressReceiptsV1/" + name, role: role)
                    guard source.bytes.count <= Self.originalEraseC16SourceMaximum(name: name) else {
                        throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
                    }
                    try permit.requireTransferredSource(path: "ProtectedIngressReceiptsV1/" + name,
                        bytes: source.bytes, fullFact: source.fullFact)
                    originalEraseC16BornSourceInputs[role + "|" + name] = .init(bytes: source.bytes, fullFact: source.fullFact)
                    try permit.requireObservationBinding()
                }
            }
        }
        try permit.requireObservationBinding()
    }

    @MainActor private func requireOriginalEraseC16TransferredInputs() throws {
        try requireScratchDescriptorAccess()
        guard !originalEraseC16InitialSourceProof, let permit = originalEraseColdPermit else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        // Reproof is intentionally fresh. Cached bytes are only immutable
        // semantic inputs, never an authorization or readback receipt.
        for (name, source) in originalEraseC16SourceInputs.sorted(by: { $0.key < $1.key }) {
            try permit.requireObservationBinding()
            try permit.requireTransferredSource(path: "ProtectedIngressReceiptsV1/" + name,
                bytes: source.bytes, fullFact: source.fullFact)
            try permit.requireObservationBinding()
        }
        for (key, source) in originalEraseC16BornSourceInputs.sorted(by: { $0.key < $1.key }) {
            guard let separator = key.firstIndex(of: "|") else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            let name = String(key[key.index(after: separator)...])
            try permit.requireTransferredSource(path: "ProtectedIngressReceiptsV1/" + name,
                bytes: source.bytes, fullFact: source.fullFact)
            try permit.requireObservationBinding()
        }
    }

    private func originalEraseC16FirstPFact(path: String) throws -> OriginalEraseC16PhysicalFactV1? {
        try requireScratchDescriptorAccess()
        if let fact = originalEraseC16FirstPFacts[path] { return try .init(fact) }
        guard originalEraseC16FirstPAbsentPaths.contains(path) else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        return nil
    }

    private func originalEraseC16FirstPAllowsOneLinkSettlement(
        path: String, plan: OriginalEraseC16PlanV1
    ) throws -> Bool {
        try requireScratchDescriptorAccess()
        guard let raw = originalEraseC16FirstPFacts[path],
              try OriginalEraseC16PhysicalFactV1(raw).linkCount == 2 else { return false }
        for step in plan.steps {
            guard case let .settleFirstPPartial(location, name, _, _, _) = step else { continue }
            let partialPath: String
            switch location {
            case .control: partialPath = "ProtectedIngressReceiptsV1/" + name
            case let .lease(lease): partialPath = "ScratchDataV1/" + lease + "/" + name
            }
            guard partialPath != path,
                  URL(fileURLWithPath: partialPath).deletingLastPathComponent()
                    == URL(fileURLWithPath: path).deletingLastPathComponent() else { continue }
            if originalEraseC16FirstPFacts[partialPath] == raw { return true }
        }
        return false
    }

    private func originalEraseC16InitialTargetCut(
        _ target: OriginalEraseC16TargetFactV1
    ) throws -> OriginalEraseC16TargetCutV1 {
        try requireScratchDescriptorAccess()
        let originalPath = "ScratchDataV1/" + target.directoryName
        let tombstonePath = "ScratchDataV1/" + Self.deletionTombstoneName(for: target.directoryName)
        let original = try originalEraseC16FirstPFact(path: originalPath)
        let tombstone = try originalEraseC16FirstPFact(path: tombstonePath)
        guard original == nil || tombstone == nil else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        guard let directory = original ?? tombstone else { return .absent }
        guard directory.device == target.device, directory.inode == target.inode,
              directory.mode & UInt64(S_IFMT) == UInt64(S_IFDIR) else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let path = tombstone == nil ? originalPath : tombstonePath
        var missing = 0, sawPresent = false
        for file in target.files {
            if let fact = try originalEraseC16FirstPFact(path: path + "/" + file.name) {
                let paired = try originalEraseC16ReferencePlan.map {
                    try originalEraseC16FirstPAllowsOneLinkSettlement(path: path + "/" + file.name, plan: $0)
                } ?? false
                guard fact.matches(file, allowPair: paired) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                sawPresent = true
            } else {
                guard !sawPresent else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                missing += 1
            }
        }
        guard tombstone != nil || missing == 0 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        return tombstone == nil ? .original : .tombstone(removedChildren: missing)
    }

    private func originalEraseC16InitialHygieneOwner(
        target: OriginalEraseC16TargetFactV1, excluding operationID: UUID
    ) throws -> Bool {
        try requireScratchDescriptorAccess()
        for name in try originalEraseC16ReferenceNames()
            where name.hasPrefix("hygiene-") && name.hasSuffix(".prepare.json") {
            let prepare = try originalEraseC16ReferenceValue(C16IngressHygienePrepareV1.self, name: name)
            guard prepare.request.operationID != operationID,
                  prepare.targets.contains(where: { OriginalEraseC16TargetFactV1($0) == target }) else { continue }
            var sawLive = false, valid = true
            for value in prepare.targets {
                switch try originalEraseC16InitialTargetCut(.init(value)) {
                case .absent: if sawLive { valid = false }
                case .tombstone: if sawLive { valid = false }; sawLive = true
                case .original: sawLive = true
                }
            }
            let receiptName = "hygiene-" + prepare.request.operationID.uuidString.lowercased() + ".json"
            if originalEraseC16SourceInputs[receiptName] != nil {
                let receipt = try originalEraseC16ReferenceValue(ProtectedIngressStartupHygieneReceiptV1.self, name: receiptName)
                guard receipt == (try prepare.receipt()), !sawLive else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            }
            if valid { return true }
        }
        return false
    }

    /// Deletion order is evaluated over the immutable initial projection.
    /// Another exact H may already have consumed a later target in first P;
    /// that absence is a fixed input, not a claimed earlier effect by this H.
    private func originalEraseC16HygieneGroupCut(
        _ prepare: C16IngressHygienePrepareV1
    ) throws -> OriginalEraseC16CutV1 {
        try requireScratchDescriptorAccess()
        var initialSawLive = false, changed = false, sawUntouched = false, sawActive = false
        var allAbsent = true
        for value in prepare.targets {
            let target = OriginalEraseC16TargetFactV1(value)
            let initial = try originalEraseC16InitialTargetCut(target)
            let current = try originalEraseC16TargetCut(target)
            if initial != .original,
               try originalEraseC16InitialHygieneOwner(target: target, excluding: prepare.request.operationID) {
                // Exact other-H original sources prove this independent cut.
            } else {
                switch initial {
                case .absent: guard !initialSawLive else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                case .tombstone: guard !initialSawLive else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }; initialSawLive = true
                case .original: initialSawLive = true
                }
            }
            if current != .absent { allAbsent = false }
            if initial == .absent {
                guard current == .absent else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                continue
            }
            if current == initial { sawUntouched = true; continue }
            guard !sawUntouched, !sawActive else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            changed = true
            switch current {
            case .absent: break
            case let .tombstone(removedChildren):
                if case let .tombstone(initialRemoved) = initial {
                    guard removedChildren >= initialRemoved else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                }
                sawActive = true
            case .original: throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        }
        let receipt = try protectedIngressReceiptFile(operationID: prepare.request.operationID)
        if try ingressControlFileExists(receipt) {
            guard allAbsent, try readProtectedIngressReceipt(at: receipt,
                operationID: prepare.request.operationID) == prepare.receipt() else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            return prepare.finalized ? .terminal : .intermediate
        }
        guard !prepare.finalized else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        return changed ? .intermediate : .preimage
    }

    private struct OriginalEraseC16ScopedPairPolicyV1 {
        let pair: OriginalEraseC16CurrentPairV1
        let observations: [TemporalPolicyObservationV1]
    }
    private var originalEraseC16ScopedPairPolicies: [String: OriginalEraseC16ScopedPairPolicyV1] = [:]
    @MainActor private var originalEraseC16ObservationScope: OriginalEraseC16CurrentObservationScopeV1?
    @MainActor private static var retainedFailedC16ObservationScopes: [OriginalEraseC16CurrentObservationScopeV1] = []

    private struct OriginalEraseC16FirstPPairPolicyV1 {
        let pair: OriginalEraseC16FirstPPairV1
        let observations: [TemporalPolicyObservationV1]
    }
    private var originalEraseC16FirstPPairPolicies: [String: OriginalEraseC16FirstPPairPolicyV1] = [:]
    @MainActor private var originalEraseC16FirstPPairScope: OriginalEraseC16FirstPObservationScopeV1?
    @MainActor private static var retainedFailedC16FirstPScopes: [OriginalEraseC16FirstPObservationScopeV1] = []

    @MainActor private func originalEraseC16IssueFirstPPairs(
        plan: OriginalEraseC16PlanV1, currentOrdinal: Int,
        planSHA256: String, recordBinding: String
    ) throws -> [String: OriginalEraseC16CurrentPathRoleV1] {
        try requireScratchDescriptorAccess()
        guard let permit = originalEraseColdPermit, let operationID = originalEraseOperationID else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        originalEraseC16FirstPPairPolicies.removeAll()
        var pairs: [OriginalEraseC16FirstPPairV1] = []
        for (assigned, step) in plan.steps.enumerated() where assigned >= currentOrdinal {
            guard case let .settleFirstPPartial(location, name, device, inode, byteCount) = step else { continue }
            let prefix: String, parentURL: URL, parent: Int32, needsClose: Bool
            switch location {
            case .control:
                prefix = "ProtectedIngressReceiptsV1/"; parentURL = try protectedIngressReceiptDirectory()
                parent = try ingressControlDescriptor(); needsClose = false
            case let .lease(lease):
                prefix = "ScratchDataV1/" + lease + "/"; parentURL = rootURL.appendingPathComponent(lease)
                parent = try openLeaseDirectory(lease); needsClose = true
            }
            let inspect = { (parent: Int32) throws -> OriginalEraseC16FirstPPairV1? in
                var partial = stat()
                if Darwin.fstatat(parent, name, &partial, AT_SYMLINK_NOFOLLOW) != 0 {
                    guard errno == ENOENT else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }; return nil
                }
                guard partial.st_mode & S_IFMT == S_IFREG,
                      UInt64(partial.st_dev) == device, UInt64(partial.st_ino) == inode,
                      Int64(partial.st_size) == byteCount else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                guard partial.st_nlink == 2 else { return nil }
                guard let original = self.originalEraseC16FirstPFacts[prefix + name],
                      Self.originalEraseC16NineFieldFact(partial) == original else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                let aliasPaths = self.originalEraseC16FirstPFacts.filter {
                    $0.key.hasPrefix(prefix) && !$0.key.dropFirst(prefix.count).contains("/")
                        && $0.key != prefix + name && $0.value == original
                }.map(\.key)
                guard aliasPaths.count == 1, let finalPath = aliasPaths.first,
                      !finalPath.dropFirst(prefix.count).hasPrefix(".partial-") else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                let finalName = String(finalPath.dropFirst(prefix.count))
                var final = stat(), parentFact = stat()
                guard Darwin.fstatat(parent, finalName, &final, AT_SYMLINK_NOFOLLOW) == 0,
                      Darwin.fstat(parent, &parentFact) == 0,
                      Self.originalEraseC16NineFieldFact(final) == original,
                      Self.originalEraseSourceFullFact(final) == Self.originalEraseSourceFullFact(partial) else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                let group = parentFact.st_mode & S_ISGID == 0 ? Darwin.getegid() : parentFact.st_gid
                guard partial.st_uid == Darwin.geteuid(), partial.st_gid == group,
                      partial.st_mode & 0o7777 == 0o600,
                      byteCount >= 0, byteCount <= 1_024 * 1_024 * 1_024 else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                return .init(finalURL: parentURL.appendingPathComponent(finalName),
                    partialURL: parentURL.appendingPathComponent(name), finalOriginalFact: original,
                    partialOriginalFact: original, expectedSHA256: "", expectedByteCount: byteCount,
                    expectedDevice: device, finalFullFact: Self.originalEraseSourceFullFact(final),
                    partialFullFact: Self.originalEraseSourceFullFact(partial), assignedSettlementOrdinal: assigned,
                    planSHA256: planSHA256, currentOrdinal: currentOrdinal)
            }
            let pair = needsClose ? try withObservedScratchDescriptor(parent, inspect) : try inspect(parent)
            if let pair {
                let finalPath = prefix + pair.finalURL.lastPathComponent
                let partialPath = prefix + name
                let finalSHA = try permit.originalPPhysicalSHA256(path: finalPath)
                let partialSHA = try permit.originalPPhysicalSHA256(path: partialPath)
                guard finalSHA == partialSHA, CompatibilityCanonicalV1.validSHA256(finalSHA) else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                pairs.append(.init(finalURL: pair.finalURL, partialURL: pair.partialURL,
                    finalOriginalFact: pair.finalOriginalFact, partialOriginalFact: pair.partialOriginalFact,
                    expectedSHA256: finalSHA, expectedByteCount: pair.expectedByteCount, expectedDevice: pair.expectedDevice,
                    finalFullFact: pair.finalFullFact, partialFullFact: pair.partialFullFact,
                    assignedSettlementOrdinal: assigned, planSHA256: planSHA256, currentOrdinal: currentOrdinal))
            }
        }
        let scope = OriginalEraseC16FirstPObservationScopeV1(operationID: operationID,
            planSHA256: planSHA256, currentOrdinal: currentOrdinal, pairs: pairs,
            requireBinding: { [self] in
                try requireScratchDescriptorAccess()
                guard try permit.requireC16ObservationBinding(planSHA256: planSHA256, ordinal: currentOrdinal) == recordBinding else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                try originalEraseBorrowedLocalLineageCheck()
            }, poison: { [self] in
                originalEraseBorrowedLifetime = .uncertain; permit.poisonOnUncertainEffect()
                if let scope = originalEraseC16FirstPPairScope { Self.retainedFailedC16FirstPScopes.append(scope) }
            })
        originalEraseC16FirstPPairScope = scope
        var roles: [String: OriginalEraseC16CurrentPathRoleV1] = [:]
        for pair in pairs {
            let observations = try ProtectedFilePolicyV1.observeEraseC16FirstPTemporalPairWithCheckedClose(
                finalURL: pair.finalURL, partialURL: pair.partialURL, scope: scope,
                retainUncertainDescriptor: { _ = ScratchUncertainCloseQuarantineV1.shared.begin($0) })
            let value = OriginalEraseC16FirstPPairPolicyV1(pair: pair, observations: observations)
            for url in [pair.finalURL, pair.partialURL] {
                originalEraseC16FirstPPairPolicies[url.path] = value
                guard let range = url.path.range(of: "/" + OwnedStorageRootKindV1.operations.rawValue + "/", options: .backwards) else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                roles[String(url.path[range.upperBound...])] = .firstPPair(pair)
            }
        }
        try scope.requireCurrentBinding(); return roles
    }

    private func originalEraseC16VerifyFirstPPairPolicy(at url: URL) throws -> Bool {
        try requireScratchDescriptorAccess()
        guard let value = originalEraseC16FirstPPairPolicies[url.path] else { return false }
        guard !value.observations.isEmpty else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        try originalEraseBorrowedExclusiveCheck?()
        var final = stat(), partial = stat()
        guard Darwin.lstat(value.pair.finalURL.path, &final) == 0,
              Darwin.lstat(value.pair.partialURL.path, &partial) == 0,
              Self.originalEraseSourceFullFact(final) == value.pair.finalFullFact,
              Self.originalEraseSourceFullFact(partial) == value.pair.partialFullFact,
              final.st_nlink == 2, partial.st_nlink == 2 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        try originalEraseBorrowedExclusiveCheck?(); return true
    }

    @MainActor
    func originalEraseC16CurrentObservationScope(
        plan: OriginalEraseC16PlanV1, currentOrdinal: Int,
        controlMarkerState: OriginalEraseC16ControlMarkerStateV1?,
        ingressMarkerState: OriginalEraseC16IngressMarkerStateV1?
    ) throws -> OriginalEraseC16CurrentObservationScopeV1 {
        try requireScratchDescriptorAccess()
        guard let permit = originalEraseColdPermit, let operationID = originalEraseOperationID,
              originalEraseC16ReferencePlan == plan,
              currentOrdinal >= 0, currentOrdinal < plan.steps.count else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let planSHA = try CompatibilityCanonicalV1.sha256(CompatibilityCanonicalV1.encode(plan))
        let recordBinding = try permit.requireC16ObservationBinding(planSHA256: planSHA, ordinal: currentOrdinal)
        try originalEraseBorrowedLocalLineageCheck()
        originalEraseC16ScopedPairPolicies.removeAll()
        var candidates = try originalEraseC16CanonicalRoles(plan: plan, through: currentOrdinal)
        if currentOrdinal > 0 {
            let earlier = try originalEraseC16CanonicalRoles(plan: plan, through: currentOrdinal - 1)
            candidates = candidates.filter { earlier[$0.key]?.bytes != $0.value.bytes }
        }
        if let marker = try originalEraseC16MaterializedControlRole(plan: plan, ordinal: currentOrdinal) {
            candidates[Self.controlEraseName] = marker
        }
        var roles = try originalEraseC16IssueFirstPPairs(plan: plan, currentOrdinal: currentOrdinal,
            planSHA256: planSHA, recordBinding: recordBinding)
        var pairs: [OriginalEraseC16CurrentPairV1] = []
        if try hasExistingIngressControl() {
            let parent = try ingressControlDescriptor(), directory = try protectedIngressReceiptDirectory()
            var parentFact = stat()
            guard Darwin.fstat(parent, &parentFact) == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            let expectedGroup = parentFact.st_mode & S_ISGID == 0 ? Darwin.getegid() : parentFact.st_gid
            var exceptionalRoleCount = 0
            for (name, candidate) in candidates.sorted(by: { $0.key < $1.key }) {
                let temporary = try Self.originalErasePublicationTemporaryName(operationID: operationID, finalName: name, leaseName: nil)
                guard let temp = try readOriginalErasePublicationLeaf(named: temporary, parent: parent,
                    maximumBytes: candidate.bytes.count) else { continue }
                exceptionalRoleCount += 1
                let final = try readOriginalErasePublicationLeaf(named: name, parent: parent, maximumBytes: candidate.bytes.count)
                let finalURL = directory.appendingPathComponent(name), tempURL = directory.appendingPathComponent(temporary)
                guard temp.0.st_uid == Darwin.geteuid(), temp.0.st_gid == expectedGroup,
                      temp.0.st_mode & 0o7777 == 0o600,
                      UInt64(temp.0.st_dev) == authority.rootDevice else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                if let final {
                    guard name != Self.controlEraseName, final.1 == candidate.bytes, temp.1 == candidate.bytes,
                          final.0.st_nlink == 2, temp.0.st_nlink == 2,
                          Self.originalEraseSourceFullFact(final.0) == Self.originalEraseSourceFullFact(temp.0) else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                    let pair = OriginalEraseC16CurrentPairV1(finalURL: finalURL, partialURL: tempURL,
                        bytes: candidate.bytes, expectedDevice: authority.rootDevice,
                        finalFullFact: Self.originalEraseSourceFullFact(final.0), partialFullFact: Self.originalEraseSourceFullFact(temp.0))
                    roles["ProtectedIngressReceiptsV1/" + name] = .pair(pair)
                    roles["ProtectedIngressReceiptsV1/" + temporary] = .pair(pair); pairs.append(pair)
                } else {
                    guard temp.0.st_nlink == 1, candidate.bytes.starts(with: temp.1) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    if temp.1.isEmpty {
                        roles["ProtectedIngressReceiptsV1/" + temporary] = .unacceptedEmptyPublication(.init(
                            finalURL: finalURL, temporaryURL: tempURL, expectedDevice: authority.rootDevice,
                            temporaryFullFact: Self.originalEraseSourceFullFact(temp.0)))
                    } else {
                        roles["ProtectedIngressReceiptsV1/" + temporary] = .publicationPrefix(.init(
                            finalURL: finalURL, temporaryURL: tempURL, expectedBytes: candidate.bytes, observedBytes: temp.1,
                            expectedDevice: authority.rootDevice, temporaryFullFact: Self.originalEraseSourceFullFact(temp.0)))
                    }
                }
            }
            guard exceptionalRoleCount <= 1 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        }
        guard let firstPScope = originalEraseC16FirstPPairScope else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        let scope = OriginalEraseC16CurrentObservationScopeV1(operationID: operationID,
            planSHA256: planSHA, ordinal: currentOrdinal,
            roles: roles, firstPObservationScope: firstPScope, requireBinding: { [self] in
                try requireScratchDescriptorAccess()
                guard try permit.requireC16ObservationBinding(planSHA256: planSHA, ordinal: currentOrdinal) == recordBinding else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                try originalEraseBorrowedLocalLineageCheck()
            }, poison: { [self] in
                originalEraseBorrowedLifetime = .uncertain
                permit.poisonOnUncertainEffect()
                if let scope = originalEraseC16ObservationScope {
                    Self.retainedFailedC16ObservationScopes.append(scope)
                }
            })
        originalEraseC16ObservationScope = scope
        for pair in pairs {
            let observed = try ProtectedFilePolicyV1.observeEraseC16CurrentTemporalPairWithCheckedClose(
                finalURL: pair.finalURL, partialURL: pair.partialURL, scope: scope,
                retainUncertainDescriptor: { _ = ScratchUncertainCloseQuarantineV1.shared.begin($0) })
            originalEraseC16ScopedPairPolicies[pair.finalURL.path] = .init(pair: pair, observations: observed)
            originalEraseC16ScopedPairPolicies[pair.partialURL.path] = .init(pair: pair, observations: observed)
        }
        try scope.requireCurrentBinding()
        return scope
    }

    /// A policy observation is local data for one synchronous engine boundary,
    /// never cached authorization. The actor controller reobserves the pair
    /// before/after every advance; primitives recheck exact full facts/bytes
    /// under the held local lineage before consuming that observed data.
    private func originalEraseC16VerifyScopedPairPolicy(at url: URL) throws -> Bool {
        try requireScratchDescriptorAccess()
        guard let observed = originalEraseC16ScopedPairPolicies[url.path] else { return false }
        try originalEraseBorrowedExclusiveCheck?()
        let pair = observed.pair
        guard !observed.observations.isEmpty,
              let parent = ingressControlAuthority?.rootDescriptor,
              let first = try readOriginalErasePublicationLeaf(named: pair.finalURL.lastPathComponent,
                parent: parent, maximumBytes: pair.bytes.count),
              let second = try readOriginalErasePublicationLeaf(named: pair.partialURL.lastPathComponent,
                parent: parent, maximumBytes: pair.bytes.count),
              Self.originalEraseSourceFullFact(first.0) == pair.finalFullFact,
              Self.originalEraseSourceFullFact(second.0) == pair.partialFullFact,
              first.0.st_nlink == 2, second.0.st_nlink == 2,
              first.1 == pair.bytes, second.1 == pair.bytes else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try originalEraseBorrowedExclusiveCheck?(); return true
    }

    private enum OriginalEraseC16TargetCutV1: Equatable {
        case original
        case tombstone(removedChildren: Int)
        case absent
    }

    /// Reads only the current generic lease cut. The Router's first-P tree
    /// proof supplies the immutable inode and full child facts; this adapter
    /// enforces the single original/tombstone name and contiguous child suffix.
    func originalEraseFrozenLeaseCut(
        name: String, orderedChildren: [String]
    ) throws -> OriginalEraseFrozenLeaseCutV1 {
        try requireScratchDescriptorAccess()
        guard originalEraseBorrowedExclusiveCheck != nil,
              Self.isLeaseDirectoryName(name),
              !orderedChildren.isEmpty,
              orderedChildren == orderedChildren.sorted(),
              Set(orderedChildren).count == orderedChildren.count,
              orderedChildren.count <= 128 else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try originalEraseBorrowedExclusiveCheck?()
        let tombstoneName = Self.deletionTombstoneName(for: name)
        let original = try directoryInformationIfPresent(named: name)
        let tombstone = try directoryInformationIfPresent(named: tombstoneName)
        guard original == nil || tombstone == nil else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        guard original != nil || tombstone != nil else {
            try originalEraseBorrowedExclusiveCheck?()
            return .init(tombstoned: true,
                removedChildCount: orderedChildren.count,
                leaseRootRemoved: true)
        }
        let currentName = tombstone == nil ? name : tombstoneName
        let descriptor = try openLeaseDirectory(currentName)
        return try withObservedScratchDescriptor(descriptor) { descriptor in
            let children = try directoryNames(descriptor)
            let removed = orderedChildren.count - children.count
            guard removed >= 0,
                  children == Array(orderedChildren.suffix(children.count)),
                  (tombstone != nil || removed == 0) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            try verifyLeaseDirectory(currentName, descriptor: descriptor)
            try originalEraseBorrowedExclusiveCheck?()
            return .init(tombstoned: tombstone != nil,
                removedChildCount: removed,
                leaseRootRemoved: false)
        }
    }

    private func originalEraseC16TargetCut(
        _ target: OriginalEraseC16TargetFactV1
    ) throws -> OriginalEraseC16TargetCutV1 {
        try requireScratchDescriptorAccess()
        guard Self.isLeaseDirectoryName(target.directoryName),
              target.device == authority.rootDevice,
              target.inode != 0,
              target.files.count <= 128,
              target.files.map(\.name) == target.files.map(\.name).sorted() else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let original = try directoryInformationIfPresent(
            named: target.directoryName)
        let tombstoneName = Self.deletionTombstoneName(
            for: target.directoryName)
        let tombstone = try directoryInformationIfPresent(
            named: tombstoneName)
        guard original == nil || tombstone == nil else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        guard original != nil || tombstone != nil else { return .absent }
        let name = tombstone == nil ? target.directoryName : tombstoneName
        let descriptor = try openLeaseDirectory(name)
        return try withObservedScratchDescriptor(descriptor) { descriptor in
            var held = stat()
            guard Darwin.fstat(descriptor, &held) == 0,
                  UInt64(held.st_dev) == target.device,
                  UInt64(held.st_ino) == target.inode else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            try verifySourceReadPolicy(.stagingDirectory,
                at: rootURL.appendingPathComponent(name))
            let physicalNames = try directoryNames(descriptor)
            let extras = physicalNames.filter { !target.files.map(\.name).contains($0) }
            for child in extras {
                guard tombstone == nil, child.hasPrefix(".partial-"),
                      let plan = originalEraseC16ReferencePlan,
                      let partialOrdinal = plan.steps.firstIndex(where: {
                          if case let .settleFirstPPartial(.lease(lease), partial, _, _, _) = $0 {
                              return lease == name && partial == child
                          }; return false
                      }), partialOrdinal >= (originalEraseC16CurrentOrdinal
                        ?? originalEraseC16AdmissionProgress?.completedC16PrefixCount ?? 0),
                      let first = originalEraseC16FirstPFacts["ScratchDataV1/" + name + "/" + child] else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                var value = stat()
                guard Darwin.fstatat(descriptor, child, &value, AT_SYMLINK_NOFOLLOW) == 0,
                      value.st_mode & S_IFMT == S_IFREG,
                      value.st_nlink == 1 || value.st_nlink == 2,
                      Self.originalEraseC16NineFieldFact(value) == first else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
            }
            let names = physicalNames.filter { !extras.contains($0) }
            let removed = target.files.count - names.count
            guard removed >= 0,
                  (tombstone != nil || removed == 0),
                  names == Array(target.files.map(\.name)
                    .suffix(names.count)) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            for (index, child) in names.enumerated() {
                let current = try regularFileInformation(named: child,
                    directoryDescriptor: descriptor)
                let value = OriginalEraseC16FileFactV1(
                    C16IngressHygieneFileIdentityV1(
                        name: child, information: current))
                guard value == target.files[removed + index] else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                try verifySourceReadPolicy(.temporaryFile,
                    at: rootURL.appendingPathComponent(name)
                        .appendingPathComponent(child))
            }
            try verifyLeaseDirectory(name, descriptor: descriptor)
            return tombstone == nil
                ? .original : .tombstone(removedChildren: removed)
        }
    }

    /// A claimed-only directory may have been consumed by an exact earlier
    /// H. Its unchanged preparation/claim remains an E dependency; absence
    /// is a proved initial E input, not an invented E deletion receipt.
    private func originalEraseC16ClaimHasCompletedHygieneOwner(
        _ target: C16IngressUnpublishedEraseTargetV1
    ) throws -> Bool {
        try requireScratchDescriptorAccess()
        guard let directory = target.directory else { return false }
        for name in try originalEraseC16ReferenceNames()
            where name.hasPrefix("hygiene-") && name.hasSuffix(".prepare.json") {
            let reference = try originalEraseC16ReferenceHygiene(name: name)
            guard reference.initial.targets.contains(where: {
                $0.directoryName == directory.directoryName && $0.device == directory.device
                    && $0.inode == directory.inode
                    && $0.files.filter({ !$0.name.hasPrefix(".partial-") }) == directory.files
            }) else { continue }
            if let plan = originalEraseC16ReferencePlan,
               let ordinal = plan.steps.firstIndex(of: .resumeHygiene(operationID: reference.initial.request.operationID)) {
                guard ordinal < (originalEraseC16CurrentOrdinal
                    ?? originalEraseC16AdmissionProgress?.completedC16PrefixCount ?? 0) else { continue }
            }
            guard try originalEraseC16HygieneGroupCut(reference.current) == .terminal,
                  try originalEraseC16TargetCut(.init(directory)) == .absent else { continue }
            return true
        }
        return false
    }

    private enum OriginalEraseC16GroupCutV1 {
        case complete, active, untouched
    }

    private func originalEraseC16IngressEraseCut(
        operationID: UUID, binding: OriginalEraseC16MarkerBindingV1
    ) throws -> OriginalEraseC16CutV1 {
        try requireScratchDescriptorAccess()
        let directory = try protectedIngressReceiptDirectory()
        let markerName = "erase-" + operationID.uuidString.lowercased()
            + ".prepare.json"
        guard binding.name == markerName else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let markerData = try readIngressControlFile(
            directory.appendingPathComponent(markerName),
            maximumBytes: 262_144)
        let marker = try CompatibilityCanonicalV1.decode(
            C16IngressEraseV1.self, from: markerData)
        try marker.validate()
        guard try CompatibilityCanonicalV1.encode(marker) == markerData,
              marker.operationID == operationID,
              marker.rootDevice == authority.rootDevice,
              marker.rootInode == authority.rootInode,
              try CompatibilityCanonicalV1.sha256(markerData)
                == binding.sha256,
              marker.unpublishedTargets.compactMap({
                  $0.directory.map(OriginalEraseC16TargetFactV1.init)
              }) + marker.targets.map(OriginalEraseC16TargetFactV1.init)
                == binding.targets else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        var phase = 0 // completed prefix, one active group, untouched suffix
        var sawProgress = false
        func accept(_ group: OriginalEraseC16GroupCutV1) throws {
            switch group {
            case .complete:
                guard phase == 0 else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                sawProgress = true
            case .active:
                guard phase == 0 else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                phase = 1
                sawProgress = true
            case .untouched:
                phase = 2
            }
        }
        for target in marker.unpublishedTargets {
            let id = target.preparation.intent.intentID
            let aborted = try readIngressControl(
                C16IngressAbortedStageV1.self,
                at: ingressControlURL(id, ".aborted.json"))
            let physical = try target.directory.map {
                try originalEraseC16TargetCut(
                    OriginalEraseC16TargetFactV1($0))
            } ?? .absent
            if let aborted {
                guard aborted == C16IngressAbortedStageV1(
                    operationID: operationID, expected: target),
                    physical == .absent else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                try accept(.complete)
            } else {
                switch physical {
                case .original:
                    try accept(.untouched)
                case .absent where target.directory == nil:
                    try accept(.untouched)
                case .absent where try originalEraseC16ClaimHasCompletedHygieneOwner(target):
                    try accept(.untouched)
                case .tombstone, .absent:
                    try accept(.active)
                default:
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
            }
        }
        for target in marker.targets {
            let id = target.intent.intentID
            let terminal = try readIngressControl(
                C16IngressRemovalV1.self,
                at: ingressControlURL(id, ".terminal.json"))
            let pending = try readIngressControl(
                C16IngressPublicationV1.self,
                at: ingressControlURL(id, ".pending.json"))
            let physical = try originalEraseC16TargetCut(
                OriginalEraseC16TargetFactV1(target))
            let recipe = try originalEraseC16IngressRecipe(for: target)
            let hygieneOwned = !recipe.hygiene.isEmpty
            if let terminal {
                guard terminal == C16IngressRemovalV1(
                    expected: target, disposition: .erased),
                    recipe.removal == terminal,
                    pending == nil || pending == target,
                    pending != nil || physical == .absent || hygieneOwned else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                if physical == .absent && pending == nil {
                    try accept(.complete)
                } else if hygieneOwned {
                    // The earlier immutable H ordinal owns physical deletion
                    // and preterminal publication. This E group has not yet
                    // cleared its pointer; multiple such groups are a lawful
                    // untouched suffix, not several simultaneous E effects.
                    try accept(.untouched)
                } else {
                    try accept(.active)
                }
            } else {
                guard (physical == .original && pending == target)
                    || (hygieneOwned && recipe.removal == C16IngressRemovalV1(
                        expected: target, disposition: .erased)) else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                try accept(.untouched)
            }
        }
        let completeName = "erase-" + operationID.uuidString.lowercased()
            + ".complete.json"
        if let complete = try readIngressControl(C16IngressEraseV1.self,
            at: directory.appendingPathComponent(completeName)) {
            guard complete == marker, phase == 0 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            return .terminal
        }
        return sawProgress ? .intermediate : .preimage
    }

    private func originalEraseC16PointerCut(
        intentID: UUID, binding: OriginalEraseC16MarkerBindingV1
    ) throws -> OriginalEraseC16CutV1 {
        try requireScratchDescriptorAccess()
        let name = "ingress-" + intentID.uuidString.lowercased()
            + ".published.json"
        guard binding.name == name,
              binding.targetIntentIDs == [intentID],
              binding.targets.count == 1 else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let file = try protectedIngressReceiptDirectory()
            .appendingPathComponent(name)
        let bytes = try readIngressControlFile(file, maximumBytes: 262_144)
        let published = try CompatibilityCanonicalV1.decode(
            C16IngressPublicationV1.self, from: bytes)
        try published.validate()
        guard try CompatibilityCanonicalV1.encode(published) == bytes,
              published.intent.intentID == intentID,
              try CompatibilityCanonicalV1.sha256(bytes) == binding.sha256,
              OriginalEraseC16TargetFactV1(published)
                == binding.targets[0] else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let targetCut = try originalEraseC16TargetCut(binding.targets[0])
        let terminal = try readIngressControl(
            C16IngressRemovalV1.self,
            at: ingressControlURL(intentID, ".terminal.json"))
        let pending = try readIngressControl(
            C16IngressPublicationV1.self,
            at: ingressControlURL(intentID, ".pending.json"))
        let recipe = try originalEraseC16IngressRecipe(for: pending ?? terminal?.expected ?? published)
        if let terminal {
            try terminal.validate()
            guard try published.replacingIntent(terminal.expected.intent)
                == terminal.expected,
                recipe.removal == terminal,
                pending == nil || pending == terminal.expected,
                pending != nil || targetCut == .absent || !recipe.hygiene.isEmpty else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            _ = try validatedIngressSnapshot(
                applyingRecoveryEffects: false)
            return targetCut == .absent && pending == nil
                ? .terminal : .intermediate
        }
        if let pending {
            guard try published.replacingIntent(pending.intent) == pending,
                  targetCut == .original || !recipe.hygiene.isEmpty else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            _ = try validatedIngressSnapshot(applyingRecoveryEffects: false)
            return recipe.removal == nil ? .terminal : .intermediate
        }
        _ = try validatedIngressSnapshot(applyingRecoveryEffects: false)
        switch targetCut {
        case .original:
            return .preimage
        case .absent:
            // A completed prepared hygiene receipt can precede the
            // pointer's terminal publication; the snapshot proves it.
            return .intermediate
        case .tombstone:
            guard !recipe.hygiene.isEmpty else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            return .intermediate
        }
    }

    private func originalEraseC16FreshEraseCut(
        plan: OriginalEraseC16PlanV1,
        markerState: OriginalEraseC16IngressMarkerStateV1
    ) throws -> OriginalEraseC16CutV1 {
        try requireScratchDescriptorAccess()
        guard let operationID = originalEraseOperationID else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let markerName = "erase-" + operationID.uuidString.lowercased()
            + ".prepare.json"
        let directory = try protectedIngressReceiptDirectory()
        let markerFile = directory.appendingPathComponent(markerName)
        let completeFile = directory.appendingPathComponent(
            "erase-" + operationID.uuidString.lowercased()
                + ".complete.json")
        guard !plan.markerBindings.contains(where: {
            $0.name == markerName
        }) else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        if try !ingressControlFileExists(markerFile) {
            guard markerState == .notYetCaptured,
                  try !ingressControlFileExists(completeFile) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            let snapshot = try validatedIngressSnapshot(
                applyingRecoveryEffects: false)
            guard snapshot.pending.map({ $0.intent.intentID })
                    == plan.freshPublishedTargets.map(\.intentID) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            for target in plan.freshPublishedTargets {
                guard let directory = target.directory,
                      try originalEraseC16TargetCut(directory)
                        == .original else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
            }
            for target in plan.freshUnpublishedTargets {
                guard let preparation = snapshot.unresolvedPreparations
                    .first(where: {
                        $0.intent.intentID == target.intentID
                    }),
                    try readIngressControl(C16IngressPublicationV1.self,
                        at: ingressControlURL(target.intentID,
                            ".published.json")) == nil else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                let claim = try readIngressControl(
                    C16IngressDirectoryClaimV1.self,
                    at: ingressControlURL(target.intentID, ".claim.json"))
                if let targetDirectory = target.directory {
                    guard let claim, claim.preparation == preparation else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    let source = try originalEraseC16ClaimOnlySource(preparation: preparation, claim: claim)
                    let physical = try originalEraseC16TargetCut(targetDirectory)
                    guard try physical == .original
                            || (physical == .absent && originalEraseC16ClaimHasCompletedHygieneOwner(source)) else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                } else {
                    let name = preparation.lease.relativeDirectory
                    guard claim == nil,
                          try directoryInformationIfPresent(named: name)
                            == nil,
                          try directoryInformationIfPresent(named:
                            Self.deletionTombstoneName(for: name))
                            == nil else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                }
            }
            let publishedIDs = Set(snapshot.pending.map {
                $0.intent.intentID
            })
            let unpublished = try snapshot.unresolvedPreparations
                .filter { !publishedIDs.contains($0.intent.intentID) }
                .map(makeUnpublishedIngressEraseTarget)
            guard unpublished.map({
                OriginalEraseC16PlannedTargetV1(
                    intentID: $0.preparation.intent.intentID,
                    directory: $0.directory.map(
                        OriginalEraseC16TargetFactV1.init))
            }) == plan.freshUnpublishedTargets else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            let temporaryName = try Self
                .originalErasePublicationTemporaryName(
                    operationID: operationID, finalName: markerName,
                    leaseName: nil)
            let control = try ingressControlDescriptor()
            let partials = try directoryNames(control)
                .filter { $0.hasPrefix(".partial-") }
            if !partials.isEmpty {
                guard partials == [temporaryName] else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                let predicted = C16IngressEraseV1(
                    operationID: operationID,
                    rootDevice: authority.rootDevice,
                    rootInode: authority.rootInode,
                    targets: snapshot.pending,
                    unpublishedTargets: unpublished)
                try predicted.validate()
                let expected = try CompatibilityCanonicalV1.encode(
                    predicted)
                guard let leaf = try readOriginalErasePublicationLeaf(
                    named: temporaryName, parent: control,
                    maximumBytes: expected.count),
                    leaf.0.st_nlink == 1,
                    expected.starts(with: leaf.1) else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                if leaf.1.count == expected.count {
                    try verifySourceReadPolicy(.temporaryFile,
                        at: directory.appendingPathComponent(temporaryName))
                }
                return .intermediate
            }
            return .preimage
        }
        let bytes = try readIngressControlFile(markerFile,
            maximumBytes: 262_144)
        let control = try ingressControlDescriptor()
        let temporaryName = try Self.originalErasePublicationTemporaryName(
            operationID: operationID, finalName: markerName,
            leaseName: nil)
        let partials = try directoryNames(control)
            .filter { $0.hasPrefix(".partial-") }
        guard partials.isEmpty || partials == [temporaryName],
              let finalLeaf = try readOriginalErasePublicationLeaf(
                named: markerName, parent: control,
                maximumBytes: bytes.count),
              finalLeaf.1 == bytes else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        if partials.isEmpty {
            guard finalLeaf.0.st_nlink == 1 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        } else {
            guard markerState == .notYetCaptured,
                  let temporary = try readOriginalErasePublicationLeaf(
                    named: temporaryName, parent: control,
                    maximumBytes: bytes.count),
                  temporary.1 == bytes,
                  temporary.0.st_dev == finalLeaf.0.st_dev,
                  temporary.0.st_ino == finalLeaf.0.st_ino,
                  temporary.0.st_nlink == 2,
                  finalLeaf.0.st_nlink == 2 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        }
        let marker = try CompatibilityCanonicalV1.decode(
            C16IngressEraseV1.self, from: bytes)
        try marker.validate()
        guard try CompatibilityCanonicalV1.encode(marker) == bytes,
              marker.operationID == operationID,
              marker.rootDevice == authority.rootDevice,
              marker.rootInode == authority.rootInode,
              marker.targets.map({
                  OriginalEraseC16PlannedTargetV1(
                    intentID: $0.intent.intentID,
                    directory: OriginalEraseC16TargetFactV1($0))
              }) == plan.freshPublishedTargets,
              marker.unpublishedTargets.map({
                  OriginalEraseC16PlannedTargetV1(
                    intentID: $0.preparation.intent.intentID,
                    directory: $0.directory.map(
                        OriginalEraseC16TargetFactV1.init))
              }) == plan.freshUnpublishedTargets else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let binding = OriginalEraseC16MarkerBindingV1(
            name: markerName,
            sha256: try CompatibilityCanonicalV1.sha256(bytes),
            targets: marker.unpublishedTargets.compactMap {
                $0.directory.map(OriginalEraseC16TargetFactV1.init)
            } + marker.targets.map(OriginalEraseC16TargetFactV1.init),
            targetIntentIDs: marker.unpublishedTargets.compactMap {
                $0.directory == nil ? nil : $0.preparation.intent.intentID
            } + marker.targets.map { $0.intent.intentID },
            unpublishedTargetCount: marker.unpublishedTargets
                .compactMap(\.directory).count,
            controlFiles: [])
        let cut = try originalEraseC16IngressEraseCut(
            operationID: operationID, binding: binding)
        if markerState == .notYetCaptured {
            guard cut == .preimage else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            return .intermediate
        }
        return cut == .preimage ? .intermediate : cut
    }

    /// Semantic read-only half of the Router's mandatory cut proof. The
    /// Router additionally checks immutable roster held/named facts,
    /// unaffected siblings, sidecar ordinal and EX/G on every invocation.
    @MainActor
    func requireOriginalEraseC16PhysicalCut(
        step: OriginalEraseC16StepV1, ordinal: Int,
        plan: OriginalEraseC16PlanV1,
        controlMarkerState: OriginalEraseC16ControlMarkerStateV1? = nil,
        ingressMarkerState: OriginalEraseC16IngressMarkerStateV1? = nil
    ) throws -> OriginalEraseC16CutV1 {
        try requireScratchDescriptorAccess()
        try requireOriginalEraseBorrowedOwner()
        let result = Result { try originalEraseC16PhysicalCutPrimitive(
            step: step, ordinal: ordinal, plan: plan,
            controlMarkerState: controlMarkerState,
            ingressMarkerState: ingressMarkerState) }
        try requireOriginalEraseBorrowedOwner()
        return try result.get()
    }

    private func originalEraseC16PhysicalCutPrimitive(
        step: OriginalEraseC16StepV1, ordinal: Int,
        plan: OriginalEraseC16PlanV1,
        controlMarkerState: OriginalEraseC16ControlMarkerStateV1?,
        ingressMarkerState: OriginalEraseC16IngressMarkerStateV1?
    ) throws -> OriginalEraseC16CutV1 {
        try requireScratchDescriptorAccess()
        guard originalEraseBorrowedExclusiveCheck != nil,
              originalEraseC16ReferencePlan == plan,
              !originalEraseC16InitialSourceProof,
              ordinal >= 0, ordinal < plan.steps.count,
              plan.steps[ordinal] == step,
              !originalEraseC16Classifying else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        originalEraseC16Classifying = true
        defer { originalEraseC16Classifying = false }
        if step == .eraseFinalControl {
            guard controlMarkerState != nil else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        } else if controlMarkerState != nil {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        if step == .eraseIngress {
            guard ingressMarkerState != nil else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        } else if ingressMarkerState != nil {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try originalEraseBorrowedExclusiveCheck?()
        switch step {
        case let .settleFirstPPartial(directory, name, device, inode,
                byteCount):
            let parent: Int32
            let closeParent: Bool
            switch directory {
            case .control:
                _ = try protectedIngressReceiptDirectory()
                guard let control = ingressControlAuthority else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                parent = control.rootDescriptor
                closeParent = false
            case let .lease(directoryName):
                parent = try openLeaseDirectory(directoryName)
                closeParent = true
            }
            let inspect = { (parent: Int32) throws -> OriginalEraseC16CutV1 in
                var named = stat()
                if Darwin.fstatat(parent, name, &named,
                    AT_SYMLINK_NOFOLLOW) != 0 {
                    guard errno == ENOENT else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                    return .terminal
                }
                guard named.st_mode & S_IFMT == S_IFREG,
                      UInt64(named.st_dev) == device,
                      UInt64(named.st_ino) == inode,
                      named.st_size == byteCount,
                      named.st_nlink == 1 || named.st_nlink == 2 else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                return .preimage
            }
            let result = closeParent
                ? try withObservedScratchDescriptor(parent, inspect)
                : try inspect(parent)
            try originalEraseBorrowedExclusiveCheck?()
            return result
        case .resumeControlTail, .eraseFinalControl:
            guard try hasExistingIngressControl() else { return .terminal }
            guard let control = ingressControlAuthority else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            let names = try directoryNames(control.rootDescriptor)
            if names.contains(Self.controlEraseName) {
                try originalEraseValidateInterruptedControlEraseNoRepair(
                    control: control)
                if step == .eraseFinalControl,
                   controlMarkerState == .notYetCaptured {
                    let bytes = try readIngressControlFile(
                        protectedIngressReceiptDirectory()
                            .appendingPathComponent(Self.controlEraseName),
                        maximumBytes: 32 * 1_024 * 1_024)
                    let marker = try CompatibilityCanonicalV1.decode(
                        C16ScratchControlEraseV1.self, from: bytes)
                    guard try CompatibilityCanonicalV1.encode(marker)
                            == bytes,
                          names == (marker.files.map(\.name)
                            + [Self.controlEraseName]).sorted() else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                }
                if step == .resumeControlTail {
                    guard let binding = plan.markerBindings.first(where: {
                        $0.name == Self.controlEraseName
                    }),
                    let data = try readOriginalErasePublicationLeaf(
                        named: Self.controlEraseName,
                        parent: control.rootDescriptor,
                        maximumBytes: 32 * 1_024 * 1_024)?.1,
                    try CompatibilityCanonicalV1.sha256(data)
                        == binding.sha256 else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                }
                return .intermediate
            }
            if names.isEmpty {
                return step == .eraseFinalControl
                    && controlMarkerState == .notYetCaptured
                    ? .preimage : .intermediate
            }
            guard step == .eraseFinalControl else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            guard controlMarkerState == .notYetCaptured else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            if let originalEraseOperationID {
                let temporary = try Self
                    .originalErasePublicationTemporaryName(
                        operationID: originalEraseOperationID,
                        finalName: Self.controlEraseName,
                        leaseName: nil)
                let partials = names.filter { $0.hasPrefix(".partial-") }
                if !partials.isEmpty {
                    guard partials == [temporary] else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                    let roleNames = try originalEraseC16FinalControlRoleNames(plan: plan)
                    guard names.filter({ $0 != temporary }) == roleNames else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                    let expectedFiles = try roleNames.map { name -> C16IngressHygieneFileIdentityV1 in
                        try validateIngressControlSnapshotName(name)
                        let information = try regularFileInformation(
                            named: name,
                            directoryDescriptor: control.rootDescriptor)
                        try verifySourceReadPolicy(.temporaryFile,
                            at: protectedIngressReceiptDirectory()
                                .appendingPathComponent(name))
                        return .init(name: name, information: information)
                    }
                    let marker = C16ScratchControlEraseV1(
                        schemaVersion: 1,
                        rootDevice: authority.rootDevice,
                        rootInode: authority.rootInode,
                        controlDevice: control.rootDevice,
                        controlInode: control.rootInode,
                        files: expectedFiles)
                    let expected = try CompatibilityCanonicalV1.encode(marker)
                    guard let leaf = try readOriginalErasePublicationLeaf(
                        named: temporary, parent: control.rootDescriptor,
                        maximumBytes: expected.count),
                        leaf.0.st_nlink == 1,
                        expected.starts(with: leaf.1) else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                    if leaf.1.count == expected.count {
                        try verifySourceReadPolicy(.temporaryFile,
                            at: protectedIngressReceiptDirectory()
                                .appendingPathComponent(temporary))
                    }
                    return .intermediate
                }
            }
            guard names == (try originalEraseC16FinalControlRoleNames(plan: plan)) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            _ = try validatedIngressSnapshot(
                applyingRecoveryEffects: false)
            return .preimage
        case let .resumeHygiene(operationID):
            let markerName = "hygiene-"
                + operationID.uuidString.lowercased() + ".prepare.json"
            guard let binding = plan.markerBindings.first(where: {
                $0.name == markerName }) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            let file = try protectedIngressPrepareFile(
                operationID: operationID)
            let prepare = try readProtectedIngressPrepare(at: file)
            let firstPPrepare = try C16IngressHygienePrepareV1(
                request: prepare.request,
                requestDigest: prepare.requestDigest,
                targets: prepare.targets,
                rootDevice: prepare.rootDevice,
                rootInode: prepare.rootInode,
                retainedValidCount: prepare.retainedValidCount,
                deferredAmbiguousCount: prepare.deferredAmbiguousCount,
                finalized: false)
            guard prepare.request.operationID == operationID,
                  try CompatibilityCanonicalV1.sha256(
                    CompatibilityCanonicalV1.encode(firstPPrepare))
                    == binding.sha256,
                  prepare.targets.map(
                    OriginalEraseC16TargetFactV1.init) == binding.targets else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            let staged = file.deletingLastPathComponent()
                .appendingPathComponent(file.lastPathComponent + ".finalizing")
            let stagedPresent = try ingressControlFileExists(staged)
            if stagedPresent {
                let stagedBytes = try readIngressControlFile(
                    staged, maximumBytes: 262_144)
                guard !prepare.finalized,
                      stagedBytes == (try CompatibilityCanonicalV1.encode(
                        prepare.finalizing())) else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
            }
            let groupCut = try originalEraseC16HygieneGroupCut(prepare)
            let receipt = try protectedIngressReceiptFile(
                operationID: operationID)
            if try ingressControlFileExists(receipt) {
                guard groupCut != .preimage,
                      try readProtectedIngressReceipt(at: receipt,
                        operationID: operationID) == prepare.receipt() else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                return prepare.finalized ? .terminal : .intermediate
            }
            guard !prepare.finalized, !stagedPresent else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            return groupCut
        case let .resumeIngressErase(operationID):
            let markerName = "erase-" + operationID.uuidString.lowercased()
                + ".prepare.json"
            guard let binding = plan.markerBindings.first(where: {
                $0.name == markerName
            }) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            return try originalEraseC16IngressEraseCut(
                operationID: operationID, binding: binding)
        case let .recoverIngressPointer(intentID):
            let name = "ingress-" + intentID.uuidString.lowercased()
                + ".published.json"
            guard let binding = plan.markerBindings.first(where: {
                $0.name == name
            }) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            return try originalEraseC16PointerCut(
                intentID: intentID, binding: binding)
        case .eraseIngress:
            guard let ingressMarkerState else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            return try originalEraseC16FreshEraseCut(plan: plan,
                markerState: ingressMarkerState)
        }
    }

    /// Checks every completed semantic group still retained before the final
    /// control tail plus the active group. Future groups can depend on effects
    /// of earlier groups, so only the Router's immutable first-P whole-tree
    /// projection can prove that all future branches remain unchanged.
    @MainActor
    func requireOriginalEraseC16GlobalPrefix(
        plan: OriginalEraseC16PlanV1,
        currentOrdinal: Int,
        controlMarkerState: OriginalEraseC16ControlMarkerStateV1? = nil,
        ingressMarkerState: OriginalEraseC16IngressMarkerStateV1? = nil
    ) throws -> OriginalEraseC16CutV1 {
        try requireScratchDescriptorAccess()
        guard currentOrdinal >= 0,
              currentOrdinal < plan.steps.count else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let current = plan.steps[currentOrdinal]
        // A C16 control erase destroys the earlier markers only after their
        // ordinals are complete. Its canonical `scratch-erase.json` suffix
        // proof takes over the control inventory for this final ordinal.
        let controlTail = current == .resumeControlTail
            || current == .eraseFinalControl
        if !controlTail {
            for ordinal in 0..<currentOrdinal {
                let step = plan.steps[ordinal]
                let cut = try requireOriginalEraseC16PhysicalCut(
                    step: step, ordinal: ordinal, plan: plan,
                    ingressMarkerState: step == .eraseIngress
                        ? .capturedPublished : nil)
                guard cut == .terminal else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
            }
        }
        let active = try requireOriginalEraseC16PhysicalCut(
            step: current, ordinal: currentOrdinal, plan: plan,
            controlMarkerState: controlMarkerState,
            ingressMarkerState: ingressMarkerState)
        return active
    }

    @MainActor
    func requireOriginalEraseC16ObservedProjection(
        plan: OriginalEraseC16PlanV1,
        currentOrdinal: Int,
        controlMarkerState: OriginalEraseC16ControlMarkerStateV1? = nil,
        ingressMarkerState: OriginalEraseC16IngressMarkerStateV1? = nil
    ) throws -> OriginalEraseC16ObservedProjectionV1 {
        try requireScratchDescriptorAccess()
        let current = try requireOriginalEraseC16GlobalPrefix(
            plan: plan, currentOrdinal: currentOrdinal,
            controlMarkerState: controlMarkerState,
            ingressMarkerState: ingressMarkerState)
        var targetByName: [String: OriginalEraseC16TargetFactV1] = [:]
        for target in plan.markerBindings.flatMap(\.targets)
            + plan.freshPublishedTargets.compactMap(\.directory)
            + plan.freshUnpublishedTargets.compactMap(\.directory) {
            if let previous = targetByName[target.directoryName] {
                guard previous.device == target.device, previous.inode == target.inode else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                let previousSemantic = previous.files.filter { !$0.name.hasPrefix(".partial-") }
                let targetSemantic = target.files.filter { !$0.name.hasPrefix(".partial-") }
                guard previousSemantic == targetSemantic,
                      previous.files == target.files
                        || previous.files.allSatisfy({ target.files.contains($0) })
                        || target.files.allSatisfy({ previous.files.contains($0) }) else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                if target.files.count > previous.files.count { targetByName[target.directoryName] = target }
            } else {
                targetByName[target.directoryName] = target
            }
        }
        var targets: [OriginalEraseC16ObservedTargetV1] = []
        for name in targetByName.keys.sorted() {
            guard let source = targetByName[name] else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            let observed = try originalEraseC16TargetCut(source)
            let location: OriginalEraseC16TargetLocationV1
            switch observed {
            case .original: location = .original
            case let .tombstone(removed):
                location = .tombstone(removedChildCount: removed)
            case .absent: location = .absent
            }
            targets.append(.init(source: source,
                location: location))
        }
        let controlPresent = try hasExistingIngressControl()
        let names = controlPresent
            ? try directoryNames(ingressControlDescriptor()) : []
        var tail: OriginalEraseC16ControlTailProjectionV1?
        let step = plan.steps[currentOrdinal]
        if (step == .resumeControlTail || step == .eraseFinalControl),
           controlPresent, names.contains(Self.controlEraseName) {
            let bytes = try readIngressControlFile(
                protectedIngressReceiptDirectory()
                    .appendingPathComponent(Self.controlEraseName),
                maximumBytes: 32 * 1_024 * 1_024)
            let marker = try CompatibilityCanonicalV1.decode(
                C16ScratchControlEraseV1.self, from: bytes)
            guard try CompatibilityCanonicalV1.encode(marker) == bytes else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            let markerNames = marker.files.map(\.name)
            let survivors = names.filter {
                $0 != Self.controlEraseName
            }
            let removed = markerNames.count - survivors.count
            guard removed >= 0,
                  survivors == Array(markerNames.suffix(
                    survivors.count)) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            tail = .init(markerFileNames: markerNames,
                removedPrefixNames: Array(markerNames.prefix(removed)),
                expectedControlNames: (survivors
                    + [Self.controlEraseName]).sorted())
        }
        try originalEraseBorrowedExclusiveCheck?()
        return .init(currentCut: current, targets: targets,
            controlRootPresent: controlPresent,
            observedControlNames: names, controlTail: tail)
    }

    /// Returns a stable, canonical post-P marker birth only after its final
    /// name has one link. The Router must first prove the marker's semantic
    /// projection against the immutable plan, then atomically bind this full
    /// fact/SHA in Store before authorizing any dependent target deletion.
    @MainActor
    func originalEraseCurrentC16MarkerBirth(
        step: OriginalEraseC16StepV1
    ) throws -> (fullFact: String, sha256: String)? {
        try requireScratchDescriptorAccess()
        guard originalEraseBorrowedExclusiveCheck != nil,
              let operationID = originalEraseOperationID,
              step == .eraseIngress || step == .eraseFinalControl else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try requireOriginalEraseBorrowedOwner()
        try originalEraseBorrowedExclusiveCheck?()
        guard try hasExistingIngressControl(),
              let control = ingressControlAuthority else {
            return nil
        }
        let name: String
        let maximum: Int
        if step == .eraseIngress {
            name = "erase-" + operationID.uuidString.lowercased()
                + ".prepare.json"
            maximum = 262_144
        } else {
            name = Self.controlEraseName
            maximum = 32 * 1_024 * 1_024
        }
        guard let leaf = try readOriginalErasePublicationLeaf(
            named: name, parent: control.rootDescriptor,
            maximumBytes: maximum) else {
            return nil
        }
        // linkat publication temporarily has two names. Only its checked,
        // one-link postimage is a stable birth fact to capture durably.
        guard leaf.0.st_nlink == 1 else { return nil }
        let file = try protectedIngressReceiptDirectory()
            .appendingPathComponent(name)
        try verifySourceReadPolicy(.temporaryFile, at: file)
        if step == .eraseIngress {
            let marker = try CompatibilityCanonicalV1.decode(
                C16IngressEraseV1.self, from: leaf.1)
            try marker.validate()
            guard marker.operationID == operationID,
                  marker.rootDevice == authority.rootDevice,
                  marker.rootInode == authority.rootInode,
                  try CompatibilityCanonicalV1.encode(marker)
                    == leaf.1 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        } else {
            let marker = try CompatibilityCanonicalV1.decode(
                C16ScratchControlEraseV1.self, from: leaf.1)
            guard marker.schemaVersion == 1,
                  marker.rootDevice == authority.rootDevice,
                  marker.rootInode == authority.rootInode,
                  marker.controlDevice == control.rootDevice,
                  marker.controlInode == control.rootInode,
                  try CompatibilityCanonicalV1.encode(marker)
                    == leaf.1 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        }
        var named = stat()
        guard Darwin.fstatat(control.rootDescriptor, name, &named,
                AT_SYMLINK_NOFOLLOW) == 0,
              named.st_dev == leaf.0.st_dev,
              named.st_ino == leaf.0.st_ino,
              named.st_mode == leaf.0.st_mode,
              named.st_nlink == leaf.0.st_nlink,
              named.st_size == leaf.0.st_size,
              named.st_mtimespec.tv_sec
                == leaf.0.st_mtimespec.tv_sec,
              named.st_mtimespec.tv_nsec
                == leaf.0.st_mtimespec.tv_nsec,
              named.st_ctimespec.tv_sec
                == leaf.0.st_ctimespec.tv_sec,
              named.st_ctimespec.tv_nsec
                == leaf.0.st_ctimespec.tv_nsec else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try requireOriginalEraseBorrowedOwner()
        try originalEraseBorrowedExclusiveCheck?()
        let fact = "\(named.st_dev)|\(named.st_ino)|\(named.st_mode)|\(named.st_nlink)|\(named.st_size)|\(named.st_mtimespec.tv_sec)|\(named.st_mtimespec.tv_nsec)|\(named.st_ctimespec.tv_sec)|\(named.st_ctimespec.tv_nsec)"
        return (fact, try CompatibilityCanonicalV1.sha256(leaf.1))
    }

    /// Shared semantic continuations carry no actor callback. A read/plan
    /// continuation may enqueue further work; an effect advances one physical
    /// cut. Both controllers consume this exact engine and its canonical models.
    private enum C16SemanticStepV1 {
        case plan((C16SemanticSessionV1) throws -> [C16SemanticStepV1])
        case effect(() throws -> Void)
        case publication(PublicationSessionV1)
        case captureBornSource(path: String, bytes: Data, fullFact: String)
    }

    private final class C16SemanticSessionV1 {
        private let store: ScratchDataLeaseStoreV1
        private let borrowed: Bool
        private var pending: [C16SemanticStepV1]
        // Keep a failed advance alive: its publication may own an open temp FD.
        private var currentStep: C16SemanticStepV1?
        private var descriptors: [Int32] = []
        private var failurePublications: [PublicationSessionV1]?
        private var failurePublicationIndex = 0
        private var captureAuthorized = false
        var nextCapture: (path: String, bytes: Data, fullFact: String)? {
            guard case let .captureBornSource(path, bytes, fullFact)? = pending.last else { return nil }
            return (path, bytes, fullFact)
        }
        func authorizeCaptureAdvance() throws {
            guard borrowed, nextCapture != nil, !captureAuthorized else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            captureAuthorized = true
        }
        init(store: ScratchDataLeaseStoreV1, steps: [C16SemanticStepV1]) {
            self.store = store
            borrowed = store.originalEraseBorrowedExclusiveCheck != nil
            pending = Array(steps.reversed())
        }
        func retain(_ descriptor: Int32) { descriptors.append(descriptor) }
        func close(_ descriptor: Int32) throws {
            guard let index = descriptors.firstIndex(of: descriptor) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            // One close attempt; an uncertain descriptor remains quarantined.
            descriptors.remove(at: index)
            try store.closeObservedScratchDescriptor(descriptor)
        }
        func advanceFailureSettlement() throws -> Bool {
            try store.requireScratchDescriptorAccess()
            if failurePublications == nil {
                // Never discard pending/current owners before explicit close.
                // Planning closures have not run; only publication steps can
                // own temp FDs independent of the retained target FD roster.
                var owners: [PublicationSessionV1] = []
                var seen = Set<ObjectIdentifier>()
                for step in (currentStep.map { [$0] } ?? []) + Array(pending.reversed()) {
                    if case let .publication(owner) = step,
                       seen.insert(ObjectIdentifier(owner)).inserted {
                        owners.append(owner)
                    }
                }
                failurePublications = owners
            }
            while let owners = failurePublications,
                  failurePublicationIndex < owners.count {
                let owner = owners[failurePublicationIndex]
                if try owner.advanceFailureSettlement() { return true }
                failurePublicationIndex += 1
            }
            if let descriptor = descriptors.popLast() {
                try store.closeObservedScratchDescriptor(descriptor)
                return true
            }
            // Publication settlement has completed. Releasing closures here
            // cannot invoke an unattempted descriptor close in deinit.
            pending.removeAll()
            currentStep = nil
            failurePublications = nil
            return false
        }
        deinit {
            for descriptor in descriptors {
                if borrowed {
                    // A failed proof never authorizes a last-chance close.
                    _ = ScratchUncertainCloseQuarantineV1.shared.begin(descriptor)
                } else { _ = Darwin.close(descriptor) }
            }
        }
        func advance() throws -> Bool {
            try store.requireScratchDescriptorAccess()
            guard currentStep == nil else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            guard let step = pending.popLast() else {
                guard descriptors.isEmpty else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                return false
            }
            currentStep = step
            switch step {
            case let .plan(plan):
                pending.append(contentsOf: try plan(self).reversed())
            case let .effect(effect): try effect()
            case let .publication(publication):
                if try publication.advance() { pending.append(.publication(publication)) }
            case .captureBornSource:
                guard borrowed, captureAuthorized else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                captureAuthorized = false
            }
            currentStep = nil
            return true
        }
    }

    // Retain failed lexical owners if fresh proof/checked close cannot settle
    // them. The outer original-Erase scope poisons and retains its EX/G owner.
    @MainActor private static var retainedFailedOriginalEraseC16Sessions:
        [C16SemanticSessionV1] = []

    private func runC16SemanticSession(_ steps: [C16SemanticStepV1]) throws {
        try requireScratchDescriptorAccess()
        guard originalEraseBorrowedExclusiveCheck == nil else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let session = C16SemanticSessionV1(store: self, steps: steps)
        do { while try session.advance() {} }
        catch {
            let failure = error
            while try session.advanceFailureSettlement() {}
            throw failure
        }
    }

    @MainActor private func runOriginalEraseC16SemanticSession(
        _ steps: [C16SemanticStepV1]
    ) throws {
        try requireScratchDescriptorAccess()
        let session = C16SemanticSessionV1(store: self, steps: steps)
        do {
            while true {
                try requireOriginalEraseC16Cut()
                if let capture = session.nextCapture {
                    guard let permit = originalEraseColdPermit else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    try permit.requireObservationBinding()
                    guard let plan = originalEraseC16ReferencePlan, let ordinal = originalEraseC16CurrentOrdinal else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                    var roles = try originalEraseC16CanonicalRoles(plan: plan, through: ordinal)
                    if let marker = try originalEraseC16MaterializedControlRole(plan: plan, ordinal: ordinal) { roles[Self.controlEraseName] = marker }
                    let name = String(capture.path.dropFirst("ProtectedIngressReceiptsV1/".count))
                    guard let role = roles[name], role.bytes == capture.bytes else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    try requireOriginalEraseC16Cut(explicitlyCapturing: .init(role: role.role,
                        path: capture.path, bytes: capture.bytes, fullFact: capture.fullFact,
                        sha256: try CompatibilityCanonicalV1.sha256(capture.bytes)))
                    try session.authorizeCaptureAdvance()
                }
                let outcome = Result { try session.advance() }
                // Check the actual physical cut even when an effect throws
                // after its syscall/fsync (including failure injection).
                try requireOriginalEraseC16Cut()
                if try !outcome.get() { break }
            }
        } catch {
            let failure = error
            do {
                while true {
                    try requireOriginalEraseC16Cut()
                    let outcome = Result { try session.advanceFailureSettlement() }
                    try requireOriginalEraseC16Cut()
                    if try !outcome.get() { break }
                }
            } catch {
                Self.retainedFailedOriginalEraseC16Sessions.append(session)
                throw error
            }
            throw failure
        }
    }

    private func c16PublicationSteps(_ data: Data, to file: URL,
                                     atomicExclusiveRename: Bool = false)
        throws -> [C16SemanticStepV1] {
        try requireScratchDescriptorAccess()
        guard data.count <= (atomicExclusiveRename ? 32 * 1_024 * 1_024 : 262_144),
              file.deletingLastPathComponent() == (try protectedIngressReceiptDirectory()) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        var work: [C16SemanticStepV1] = [.publication(try PublicationSessionV1(store: self, data: data,
            finalName: file.lastPathComponent, parent: ingressControlDescriptor(),
            directoryURL: file.deletingLastPathComponent(), finalURL: file,
            leaseName: nil, atomicExclusiveRename: atomicExclusiveRename,
            authorityCheck: { _ = try self.protectedIngressReceiptDirectory() },
            borrowedOperationID: originalEraseOperationID))]
        if originalEraseBorrowedExclusiveCheck != nil { work += c16CaptureBornSourceSteps(data, at: file) }
        return work
    }

    private func c16CaptureBornSourceSteps(_ bytes: Data, at file: URL) -> [C16SemanticStepV1] {
        [.plan { [self] _ in
            guard originalEraseBorrowedExclusiveCheck != nil,
                  file.deletingLastPathComponent() == (try protectedIngressReceiptDirectory()),
                  bytes.count <= Self.originalEraseC16SourceMaximum(name: file.lastPathComponent),
                  let leaf = try readOriginalErasePublicationLeaf(named: file.lastPathComponent,
                    parent: ingressControlDescriptor(), maximumBytes: bytes.count),
                  leaf.0.st_nlink == 1, leaf.1 == bytes else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            try verifySourceReadPolicy(.temporaryFile, at: file)
            let fact = Self.originalEraseSourceFullFact(leaf.0)
            if let initial = originalEraseC16SourceInputs[file.lastPathComponent],
               initial.bytes == bytes, initial.fullFact == fact { return [] }
            return [.captureBornSource(path: "ProtectedIngressReceiptsV1/" + file.lastPathComponent,
                bytes: bytes, fullFact: fact)]
        }]
    }

    private func originalEraseBorrowedLocalLineageCheck() throws {
        try requireScratchDescriptorAccess()
        var operations = stat(), namedOperations = stat(), root = stat()
        guard Darwin.fstat(authority.operationsDescriptor, &operations) == 0,
              Darwin.lstat(rootURL.deletingLastPathComponent().path, &namedOperations) == 0,
              operations.st_mode & S_IFMT == S_IFDIR,
              namedOperations.st_mode & S_IFMT == S_IFDIR,
              UInt64(operations.st_dev) == authority.operationsDevice,
              UInt64(namedOperations.st_dev) == authority.operationsDevice,
              UInt64(operations.st_ino) == authority.operationsInode,
              UInt64(namedOperations.st_ino) == authority.operationsInode,
              Darwin.fstat(authority.rootDescriptor, &root) == 0,
              root.st_mode & S_IFMT == S_IFDIR,
              UInt64(root.st_dev) == authority.rootDevice,
              UInt64(root.st_ino) == authority.rootInode else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        // Named-root presence/absence is the controller's finite physical cut,
        // including the successful rmdir before rootRemovalProved is set.
    }

    @MainActor private func requireOriginalEraseBorrowedOwner() throws {
        try requireScratchDescriptorAccess()
        guard let check = originalEraseBorrowedOwnerCheck,
              originalEraseBorrowedExclusiveCheck != nil else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try check()
    }

    @MainActor private func requireOriginalEraseC16Cut(
        explicitlyCapturing explicit: OriginalEraseC16BornSourceObservationV1? = nil
    ) throws {
        try requireScratchDescriptorAccess()
        guard originalEraseBorrowedExclusiveCheck != nil else { return }
        guard let permit = originalEraseColdPermit, let check = originalEraseC16CutCheck,
              let plan = originalEraseC16ReferencePlan, let ordinal = originalEraseC16CurrentOrdinal else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try permit.requireObservationBinding()
        try requireOriginalEraseC16TransferredInputs()
        var explicitBirth = explicit
        // Every genuine active canonical birth is transferred before the next
        // semantic advance. Fresh-owner pre-capture cuts use the same typed
        // request; a retained exact tuple is an authenticated no-effect retry.
        while true {
            _ = try originalEraseC16CurrentObservationScope(plan: plan, currentOrdinal: ordinal,
                controlMarkerState: originalEraseC16CurrentControlMarkerState,
                ingressMarkerState: originalEraseC16CurrentIngressMarkerState)
            let projection = try originalEraseC16ExpectedTree(plan: plan, currentOrdinal: ordinal,
                controlMarkerState: originalEraseC16CurrentControlMarkerState,
                ingressMarkerState: originalEraseC16CurrentIngressMarkerState, capturedBirths: [])
            var candidates = try originalEraseC16CanonicalRoles(plan: plan, through: ordinal)
            if ordinal > 0 {
                let earlier = try originalEraseC16CanonicalRoles(plan: plan, through: ordinal - 1)
                candidates = candidates.filter { earlier[$0.key]?.bytes != $0.value.bytes }
            }
            if let marker = try originalEraseC16MaterializedControlRole(plan: plan, ordinal: ordinal) {
                candidates[Self.controlEraseName] = marker
            }
            var birth = explicitBirth
            if birth == nil, try hasExistingIngressControl() {
                for (name, role) in candidates.sorted(by: { $0.key < $1.key }) {
                    guard let leaf = try readOriginalErasePublicationLeaf(named: name,
                        parent: ingressControlDescriptor(), maximumBytes: role.bytes.count),
                        leaf.0.st_nlink == 1, leaf.1 == role.bytes else { continue }
                    let fact = Self.originalEraseSourceFullFact(leaf.0)
                    if let original = originalEraseC16SourceInputs[name], original.bytes == leaf.1,
                       original.fullFact == fact { continue }
                    if let captured = originalEraseC16BornSourceInputs[role.role + "|" + name],
                       captured.bytes == leaf.1, captured.fullFact == fact { continue }
                    birth = .init(role: role.role, path: "ProtectedIngressReceiptsV1/" + name,
                        bytes: leaf.1, fullFact: fact, sha256: try CompatibilityCanonicalV1.sha256(leaf.1))
                    break
                }
            }
            if let birth {
                let name = String(birth.path.dropFirst("ProtectedIngressReceiptsV1/".count))
                guard birth.path == "ProtectedIngressReceiptsV1/" + name,
                      let role = candidates[name], role.role == birth.role, role.bytes == birth.bytes,
                      try CompatibilityCanonicalV1.sha256(birth.bytes) == birth.sha256 else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
            }
            let observation = OriginalEraseC16BoundaryObservationV1(
                planSHA256: try CompatibilityCanonicalV1.sha256(CompatibilityCanonicalV1.encode(plan)),
                stepSHA256: try CompatibilityCanonicalV1.sha256(CompatibilityCanonicalV1.encode(plan.steps[ordinal])),
                ordinal: ordinal, projection: projection, bornSource: birth)
            let receipt = try check(observation)
            try receipt.requireBound(to: observation)
            try permit.requireObservationBinding()
            try originalEraseBorrowedExclusiveCheck?()
            if let birth {
                try permit.requireTransferredSource(path: birth.path, bytes: birth.bytes, fullFact: birth.fullFact)
                let name = String(birth.path.dropFirst("ProtectedIngressReceiptsV1/".count))
                originalEraseC16BornSourceInputs[birth.role + "|" + name] = .init(bytes: birth.bytes, fullFact: birth.fullFact)
                if birth.role == "freshIngressErasePrepare" { originalEraseC16CurrentIngressMarkerState = .capturedPublished }
                if birth.role == "scratchControlErase" { originalEraseC16CurrentControlMarkerState = .capturedPublished }
                _ = try originalEraseC16CurrentObservationScope(plan: plan, currentOrdinal: ordinal,
                    controlMarkerState: originalEraseC16CurrentControlMarkerState,
                    ingressMarkerState: originalEraseC16CurrentIngressMarkerState)
                try permit.requireHeld()
                explicitBirth = nil
                continue
            }
            try permit.requireHeld()
            try requireOriginalEraseC16TransferredInputs()
            return
        }
    }

    /// The callback must prove the held EX/G, the matching sidecar preparing
    /// ordinal, complete immutable first-P survivor prefix, affected named
    /// facts and every unaffected sibling. A failed cut poisons the lexical
    /// borrowed owner through `withSchema2ColdBorrowedExistingRoot`.
    @MainActor
    func performOriginalEraseC16Step(
        _ step: OriginalEraseC16StepV1,
        controlMarkerState: OriginalEraseC16ControlMarkerStateV1? = nil,
        ingressMarkerState: OriginalEraseC16IngressMarkerStateV1? = nil,
        requireCut: @escaping @MainActor (OriginalEraseC16BoundaryObservationV1) throws -> OriginalEraseC16BoundaryReceiptV1
    ) throws {
        try requireScratchDescriptorAccess()
        guard let plan = originalEraseC16ReferencePlan,
              let ordinal = plan.steps.firstIndex(of: step),
              plan.steps.filter({ $0 == step }).count == 1 else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try performOriginalEraseC16Step(step, ordinal: ordinal, plan: plan,
            controlMarkerState: controlMarkerState,
            ingressMarkerState: ingressMarkerState, requireCut: requireCut)
    }

    @MainActor
    func performOriginalEraseC16Step(
        _ step: OriginalEraseC16StepV1,
        ordinal: Int,
        plan: OriginalEraseC16PlanV1,
        controlMarkerState: OriginalEraseC16ControlMarkerStateV1? = nil,
        ingressMarkerState: OriginalEraseC16IngressMarkerStateV1? = nil,
        requireCut: @escaping @MainActor (OriginalEraseC16BoundaryObservationV1) throws -> OriginalEraseC16BoundaryReceiptV1
    ) throws {
        try requireScratchDescriptorAccess()
        guard originalEraseBorrowedExclusiveCheck != nil,
              originalEraseOperationID != nil,
              exclusiveNoRepairRead,
              originalEraseC16CutCheck == nil,
              originalEraseC16ReferencePlan == plan,
              let admissionProgress = originalEraseC16AdmissionProgress,
              ordinal >= admissionProgress.completedC16PrefixCount,
              ordinal < plan.steps.count,
              plan.steps[ordinal] == step,
              originalEraseC16CurrentOrdinal == nil,
              !originalEraseC16InitialSourceProof else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try plan.validate()
        originalEraseC16CurrentOrdinal = ordinal
        originalEraseC16CurrentControlMarkerState = controlMarkerState
        originalEraseC16CurrentIngressMarkerState = ingressMarkerState
        defer {
            originalEraseC16CurrentOrdinal = nil
            originalEraseC16CurrentControlMarkerState = nil
            originalEraseC16CurrentIngressMarkerState = nil
        }
        if step == .eraseFinalControl {
            guard controlMarkerState != nil else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        } else {
            guard controlMarkerState == nil else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        }
        if step == .eraseIngress {
            guard ingressMarkerState != nil else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        } else if ingressMarkerState != nil {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        originalEraseC16CutCheck = requireCut
        defer { originalEraseC16CutCheck = nil }
        try requireOriginalEraseC16Cut()
        switch step {
        case let .settleFirstPPartial(directory, name, device, inode, byteCount):
            try settleOriginalEraseFirstPPartial(directory: directory, name: name,
                device: device, inode: inode, byteCount: byteCount)
        case .resumeControlTail:
            if try hasExistingIngressControl() {
                try runOriginalEraseC16SemanticSession(c16ControlEraseSteps(resumeOnly: true))
            }
        case let .resumeHygiene(operationID):
            let file = try protectedIngressPrepareFile(operationID: operationID)
            let prepare = try readProtectedIngressPrepare(at: file)
            guard prepare.request.operationID == operationID else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            try runOriginalEraseC16SemanticSession(c16HygieneSteps(now: prepare.request.requestedAt,
                operationID: operationID, minimumAge: prepare.request.minimumAge,
                beforeRemainingTargets: originalEraseC16HygieneTerminalSteps(
                    operationID: operationID, ordinal: ordinal)))
        case let .resumeIngressErase(operationID):
            guard operationID != SettingsValidationV1.zeroUUID,
                  let marker = try readIngressControl(C16IngressEraseV1.self,
                      at: protectedIngressReceiptDirectory().appendingPathComponent(
                          "erase-" + operationID.uuidString.lowercased() + ".prepare.json")),
                  marker.operationID == operationID else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            try runOriginalEraseC16SemanticSession(c16EraseIngressSteps(operationID: operationID))
        case let .recoverIngressPointer(intentID):
            guard intentID != SettingsValidationV1.zeroUUID else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            try runOriginalEraseC16SemanticSession(
                originalEraseC16PointerRecoverySteps(intentID: intentID))
            _ = try validatedIngressSnapshot(applyingRecoveryEffects: false)
        case .eraseIngress:
            guard let originalEraseOperationID else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            try runOriginalEraseC16SemanticSession(c16EraseIngressSteps(operationID: originalEraseOperationID))
        case .eraseFinalControl:
            try runOriginalEraseC16SemanticSession(c16ControlEraseSteps(resumeOnly: false,
                capturedMarkerPublication: controlMarkerState == .capturedPublished))
        }
        try requireOriginalEraseC16Cut()
    }

    /// Called once against the Router-proved immutable first-P image, before
    /// the Scratch sidecar is published. Never call this on a Q survivor: the
    /// returned canonical plan is what the sidecar binds for all cold replay.
    @MainActor
    func originalEraseC16PlanFromFirstP(
        firstPPartials: [OriginalEraseC16StepV1]
    ) throws -> OriginalEraseC16PlanV1 {
        try requireScratchDescriptorAccess()
        guard originalEraseBorrowedExclusiveCheck != nil,
              originalEraseOperationID != nil,
              exclusiveNoRepairRead,
              originalEraseC16CutCheck == nil,
              !originalEraseC16Planning,
              originalEraseC16InitialSourceProof,
              originalEraseC16ReferencePlan == nil,
              firstPPartials.count <= 100_000 else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try requireOriginalEraseBorrowedOwner()
        try originalEraseBorrowedExclusiveCheck?()
        originalEraseC16Planning = true
        defer { originalEraseC16Planning = false }
        var partialPaths: [String] = []
        for step in firstPPartials {
            guard case let .settleFirstPPartial(directory, name, _, _, _) = step,
                  name.hasPrefix(".partial-") else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            switch directory {
            case .control:
                partialPaths.append("ProtectedIngressReceiptsV1/" + name)
            case let .lease(directoryName):
                guard Self.isLeaseDirectoryName(directoryName)
                    || Self.isDeletionTombstone(directoryName) else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                partialPaths.append("ScratchDataV1/" + directoryName + "/" + name)
            }
        }
        guard partialPaths == partialPaths.sorted(),
              Set(partialPaths).count == partialPaths.count else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        var steps = firstPPartials
        var owned = Set<String>()
        var bindings: [OriginalEraseC16MarkerBindingV1] = []
        guard try hasExistingIngressControl() else {
            guard !partialPaths.contains(where: {
                $0.hasPrefix("ProtectedIngressReceiptsV1/")
            }) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            try requireOriginalEraseBorrowedOwner()
            try originalEraseBorrowedExclusiveCheck?()
            let plan = OriginalEraseC16PlanV1(
                steps: steps, ownedLeaseNames: [], markerBindings: [],
                freshPublishedTargets: [], freshUnpublishedTargets: [])
            try plan.validate()
            return plan
        }
        guard let control = ingressControlAuthority else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        let directory = try protectedIngressReceiptDirectory()
        let names = try directoryNames(control.rootDescriptor)
        guard names.count <= 100_000 else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let listedControlPartials = partialPaths.compactMap { path in
            path.hasPrefix("ProtectedIngressReceiptsV1/")
                ? String(path.dropFirst(
                    "ProtectedIngressReceiptsV1/".count)) : nil
        }
        guard names.filter({ $0.hasPrefix(".partial-") })
            == listedControlPartials else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        var retainedEncodedBytes = 0
        for name in names {
            var named = stat()
            guard Darwin.fstatat(control.rootDescriptor, name, &named,
                    AT_SYMLINK_NOFOLLOW) == 0,
                  named.st_mode & S_IFMT == S_IFREG,
                  named.st_size >= 0,
                  named.st_size <= (name.hasPrefix(".partial-") ? 1_024 * 1_024 * 1_024
                    : Int64(Self.originalEraseC16SourceMaximum(name: name))),
                  named.st_nlink == 1 || named.st_nlink == 2 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            if name.hasPrefix(".partial-") {
                guard let permit = originalEraseColdPermit else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                try permit.requireHeld()
                let sha = try permit.originalPPhysicalSHA256(path: "ProtectedIngressReceiptsV1/" + name)
                guard CompatibilityCanonicalV1.validSHA256(sha) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                let binding = OriginalEraseC16MarkerBindingV1(name: name, sha256: sha,
                    targets: [], targetIntentIDs: [], unpublishedTargetCount: 0, controlFiles: [])
                let charge = retainedEncodedBytes.addingReportingOverflow(try CompatibilityCanonicalV1.encode(binding).count)
                guard !charge.overflow, charge.partialValue <= OriginalEraseC16PlanV1.maximumEncodedBytes else {
                    throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
                }
                retainedEncodedBytes = charge.partialValue; bindings.append(binding)
                try permit.requireHeld()
                continue
            }
            let data: Data
            if name == Self.controlEraseName || name.hasPrefix(".partial-") {
                guard let leaf = try readOriginalErasePublicationLeaf(
                    named: name, parent: control.rootDescriptor,
                    maximumBytes: 32 * 1_024 * 1_024) else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                data = leaf.1
            } else {
                try validateIngressControlSnapshotName(name)
                data = try readIngressControlFile(
                    directory.appendingPathComponent(name), maximumBytes: 262_144)
            }
            var targets: [OriginalEraseC16TargetFactV1] = []
            var targetIntentIDs: [UUID] = []
            var unpublishedTargetCount = 0
            var controlFiles: [OriginalEraseC16FileFactV1] = []
            if name == Self.controlEraseName {
                let marker = try CompatibilityCanonicalV1.decode(
                    C16ScratchControlEraseV1.self, from: data)
                guard try CompatibilityCanonicalV1.encode(marker) == data,
                      marker.schemaVersion == 1 else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                controlFiles = marker.files.map(
                    OriginalEraseC16FileFactV1.init)
            } else if name.hasPrefix("hygiene-")
                && (name.hasSuffix(".prepare.json")
                    || name.hasSuffix(".prepare.json.finalizing")) {
                let marker = try CompatibilityCanonicalV1.decode(
                    C16IngressHygienePrepareV1.self, from: data)
                try marker.validate()
                guard try CompatibilityCanonicalV1.encode(marker) == data else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                if name.hasSuffix(".prepare.json") {
                    targets = marker.targets.map(
                        OriginalEraseC16TargetFactV1.init)
                }
            } else if name.hasPrefix("erase-")
                && name.hasSuffix(".prepare.json") {
                let marker = try CompatibilityCanonicalV1.decode(
                    C16IngressEraseV1.self, from: data)
                try marker.validate()
                guard try CompatibilityCanonicalV1.encode(marker) == data else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                targets = marker.unpublishedTargets.compactMap {
                    $0.directory.map(OriginalEraseC16TargetFactV1.init)
                } + marker.targets.map(OriginalEraseC16TargetFactV1.init)
                targetIntentIDs = marker.unpublishedTargets.compactMap {
                    $0.directory == nil ? nil : $0.preparation.intent.intentID
                } + marker.targets.map { $0.intent.intentID }
                unpublishedTargetCount = marker.unpublishedTargets.compactMap {
                    $0.directory
                }.count
            } else if name.hasPrefix("erase-")
                && name.hasSuffix(".complete.json") {
                let marker = try CompatibilityCanonicalV1.decode(
                    C16IngressEraseV1.self, from: data)
                try marker.validate()
                guard try CompatibilityCanonicalV1.encode(marker) == data else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
            } else if name.hasPrefix("hygiene-")
                && name.hasSuffix(".json") {
                let marker = try CompatibilityCanonicalV1.decode(
                    ProtectedIngressStartupHygieneReceiptV1.self,
                    from: data)
                guard try CompatibilityCanonicalV1.encode(marker) == data else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
            } else if name.hasPrefix("ingress-")
                && name.hasSuffix(".prepare.json") {
                let marker = try CompatibilityCanonicalV1.decode(
                    C16IngressPreparedStageV1.self, from: data)
                try marker.validate()
                guard try CompatibilityCanonicalV1.encode(marker) == data else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
            } else if name.hasPrefix("ingress-")
                && name.hasSuffix(".claim.json") {
                let marker = try CompatibilityCanonicalV1.decode(
                    C16IngressDirectoryClaimV1.self, from: data)
                try marker.preparation.validate()
                guard try CompatibilityCanonicalV1.encode(marker) == data else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
            } else if name.hasPrefix("ingress-")
                && name.hasSuffix(".terminal.json") {
                let marker = try CompatibilityCanonicalV1.decode(
                    C16IngressRemovalV1.self, from: data)
                try marker.validate()
                guard try CompatibilityCanonicalV1.encode(marker) == data else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                // The published marker and any erase prepare retain this
                // target identity in the immutable plan.
            } else if name.hasPrefix("ingress-")
                && (name.hasSuffix(".published.json")
                    || name.hasSuffix(".pending.json")
                    || name.hasSuffix(".pending.json.replacement")) {
                let marker = try CompatibilityCanonicalV1.decode(
                    C16IngressPublicationV1.self, from: data)
                try marker.validate()
                guard try CompatibilityCanonicalV1.encode(marker) == data else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                if name.hasSuffix(".published.json") {
                    targets = [OriginalEraseC16TargetFactV1(marker)]
                    targetIntentIDs = [marker.intent.intentID]
                }
            } else if name.hasPrefix("ingress-")
                && name.hasSuffix(".aborted.json") {
                let marker = try CompatibilityCanonicalV1.decode(
                    C16IngressAbortedStageV1.self, from: data)
                try marker.validate()
                guard try CompatibilityCanonicalV1.encode(marker) == data else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                // Aborted is tied to its erase prepare; avoid a second copy
                // of that immutable target roster in the plan.
            } else if !name.hasPrefix(".partial-") {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            let binding = OriginalEraseC16MarkerBindingV1(
                name: name, sha256: try CompatibilityCanonicalV1.sha256(data),
                targets: targets, targetIntentIDs: targetIntentIDs,
                unpublishedTargetCount: unpublishedTargetCount,
                controlFiles: controlFiles)
            let charge = try CompatibilityCanonicalV1.encode(binding).count
            let added = retainedEncodedBytes.addingReportingOverflow(charge)
            guard !added.overflow,
                  added.partialValue
                    <= OriginalEraseC16PlanV1.maximumEncodedBytes else {
                throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
            }
            retainedEncodedBytes = added.partialValue
            bindings.append(binding)
        }
        // A canonical prepared C16 target can itself contain a protected
        // `.partial-*` leaf. That leaf belongs to the target's ordered
        // tombstone deletion, not an earlier independent cleanup ordinal.
        // Otherwise cleanup would mutate the original directory before the
        // C16 prepare's required same-file pre-rename proof.
        var c16OwnedPartialFacts: [String: OriginalEraseC16FileFactV1] = [:]
        for binding in bindings {
            for target in binding.targets {
                for file in target.files where file.name.hasPrefix(
                    ".partial-") {
                    for leaseName in [target.directoryName,
                        Self.deletionTombstoneName(
                            for: target.directoryName)] {
                        let path = "ScratchDataV1/" + leaseName
                            + "/" + file.name
                        if let previous = c16OwnedPartialFacts[path],
                           previous != file {
                            throw ScratchDataLeaseStoreFailureV1
                                .leaseCollision
                        }
                        c16OwnedPartialFacts[path] = file
                    }
                }
            }
        }
        steps = try steps.filter { step in
            guard case let .settleFirstPPartial(directory, name,
                device, inode, byteCount) = step,
                case let .lease(leaseName) = directory,
                let expected = c16OwnedPartialFacts[
                    "ScratchDataV1/" + leaseName + "/" + name] else {
                return true
            }
            guard expected.device == device,
                  expected.inode == inode,
                  expected.byteCount == byteCount else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            return false
        }
        if names.contains(Self.controlEraseName) {
            try originalEraseValidateInterruptedControlEraseNoRepair(control: control)
            steps.append(.resumeControlTail)
            try requireOriginalEraseBorrowedOwner()
            try originalEraseBorrowedExclusiveCheck?()
            let plan = OriginalEraseC16PlanV1(steps: steps,
                ownedLeaseNames: [], markerBindings: bindings,
                freshPublishedTargets: [], freshUnpublishedTargets: [])
            try plan.validate()
            return plan
        }
        var hygieneTargets: [C16IngressHygieneTargetV1] = []
        var resumedEraseIntentIDs = Set<UUID>()
        for name in names where name.hasPrefix("hygiene-")
            && name.hasSuffix(".prepare.json") {
            let marker = try readProtectedIngressPrepare(
                at: directory.appendingPathComponent(name))
            hygieneTargets.append(contentsOf: marker.targets)
            if !marker.finalized {
                steps.append(.resumeHygiene(
                    operationID: marker.request.operationID))
                marker.targets.forEach { owned.insert($0.directoryName) }
            }
        }
        for name in names where name.hasPrefix("erase-")
            && name.hasSuffix(".prepare.json") {
            let id = try ingressControlIdentifier(name, prefix: "erase-",
                suffixes: [".prepare.json"])
            let markerFile = directory.appendingPathComponent(name)
            guard let marker = try readIngressControl(
                C16IngressEraseV1.self, at: markerFile) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            try marker.validate()
            let complete = directory.appendingPathComponent(
                "erase-" + id.uuidString.lowercased() + ".complete.json")
            if try !ingressControlFileExists(complete) {
                steps.append(.resumeIngressErase(operationID: id))
                marker.targets.forEach {
                    owned.insert($0.claim.preparation.lease.relativeDirectory)
                    resumedEraseIntentIDs.insert($0.intent.intentID)
                }
                marker.unpublishedTargets.forEach {
                    owned.insert($0.preparation.lease.relativeDirectory)
                    resumedEraseIntentIDs.insert(
                        $0.preparation.intent.intentID)
                }
            }
        }
        let snapshot = try validatedIngressSnapshot(applyingRecoveryEffects: false)
        for preparation in snapshot.preparations {
            let id = preparation.intent.intentID
            let published = try readIngressControl(C16IngressPublicationV1.self,
                at: ingressControlURL(id, ".published.json"))
            let pending = try readIngressControl(C16IngressPublicationV1.self,
                at: ingressControlURL(id, ".pending.json"))
            let terminal = try readIngressControl(C16IngressRemovalV1.self,
                at: ingressControlURL(id, ".terminal.json"))
            let leaseName = preparation.lease.relativeDirectory
            let exists = try directoryInformationIfPresent(named: leaseName) != nil
                || directoryInformationIfPresent(
                    named: Self.deletionTombstoneName(for: leaseName)) != nil
            let predictedHygiene: Bool
            if let published {
                let recipe = try originalEraseC16IngressRecipe(for: pending ?? terminal?.expected ?? published)
                predictedHygiene = !recipe.hygiene.isEmpty
            } else {
                predictedHygiene = false
            }
            if !resumedEraseIntentIDs.contains(id), published != nil
                && ((terminal != nil && (pending != nil || exists))
                || (terminal == nil && (pending == nil || predictedHygiene))) {
                steps.append(.recoverIngressPointer(intentID: id))
            }
            if snapshot.pending.contains(where: { $0.intent.intentID == id })
                || snapshot.unresolvedPreparations.contains(where: {
                    $0.intent.intentID == id }) {
                owned.insert(leaseName)
            }
        }
        let originalOperationID = originalEraseOperationID!
        let originalMarkerName = "erase-"
            + originalOperationID.uuidString.lowercased()
            + ".prepare.json"
        let hasOriginalMarker = names.contains(originalMarkerName)
        let freshPublishedTargets: [OriginalEraseC16PlannedTargetV1] =
            snapshot.pending.filter { value in
                return !resumedEraseIntentIDs.contains(value.intent.intentID)
                    && !hygieneTargets.contains(where: {
                        OriginalEraseC16TargetFactV1($0) == OriginalEraseC16TargetFactV1(value)
                    })
            }.map { value in
                .init(intentID: value.intent.intentID,
                    directory: OriginalEraseC16TargetFactV1(value))
            }
        let freshPublishedIDs = Set(freshPublishedTargets.map(\.intentID))
        var freshUnpublishedTargets: [OriginalEraseC16PlannedTargetV1] = []
        for preparation in snapshot.unresolvedPreparations {
            let id = preparation.intent.intentID
            if resumedEraseIntentIDs.contains(id)
                || freshPublishedIDs.contains(id) { continue }
            if try readIngressControl(C16IngressPublicationV1.self,
                at: ingressControlURL(id, ".published.json")) != nil {
                // A published target consumed by hygiene or an older erase
                // remains outside this new C16 marker's unpublished group.
                continue
            }
            let claim = try readIngressControl(C16IngressDirectoryClaimV1.self,
                at: ingressControlURL(id, ".claim.json"))
            guard let claim else {
                freshUnpublishedTargets.append(.init(intentID: id,
                    directory: nil))
                continue
            }
            guard claim.preparation == preparation else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            let fixedTarget = try originalEraseC16ClaimOnlySource(preparation: preparation, claim: claim)
            guard let directory = fixedTarget.directory else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            let target = OriginalEraseC16TargetFactV1(directory)
            freshUnpublishedTargets.append(.init(intentID: id,
                directory: target))
        }
        freshUnpublishedTargets.sort {
            $0.intentID.uuidString < $1.intentID.uuidString
        }
        // A first-P original-operation prepare is handled by its resumed
        // ordinal; a complete pair is already terminal. Creating it twice
        // would make the fresh ordinal a no-op and rebase target selection.
        if !hasOriginalMarker {
            steps.append(.eraseIngress)
        }
        steps.append(.eraseFinalControl)
        try requireOriginalEraseBorrowedOwner()
        try originalEraseBorrowedExclusiveCheck?()
        let plan = OriginalEraseC16PlanV1(steps: steps,
            ownedLeaseNames: owned.sorted(), markerBindings: bindings,
            freshPublishedTargets: freshPublishedTargets,
            freshUnpublishedTargets: freshUnpublishedTargets)
        try plan.validate()
        return plan
    }

    /// A first-P partial is disposed of only as its own sidecar ordinal. The
    /// caller's mandatory cut proof binds its exact bytes/policy and all
    /// unaffected names; this adapter additionally pins the named inode and
    /// checks the parent around the single unlink.
    @MainActor private func settleOriginalEraseFirstPPartial(
        directory: OriginalEraseC16PartialDirectoryV1,
        name: String, device: UInt64, inode: UInt64, byteCount: Int64
    ) throws {
        try requireScratchDescriptorAccess()
        guard name.hasPrefix(".partial-"),
              let id = UUID(uuidString: String(name.dropFirst(".partial-".count))),
              id.uuidString.lowercased() == String(name.dropFirst(".partial-".count)),
              device == authority.rootDevice, inode != 0,
              byteCount >= 0 else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let descriptor: Int32
        let leaseName: String?
        switch directory {
        case .control:
            _ = try protectedIngressReceiptDirectory()
            guard let control = ingressControlAuthority else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            descriptor = control.rootDescriptor
            leaseName = nil
        case let .lease(name):
            guard Self.isLeaseDirectoryName(name)
                || Self.isDeletionTombstone(name) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            descriptor = try openLeaseDirectory(name)
            leaseName = name
        }
        let settle: @MainActor (Int32) throws -> Void = { parent in
            try self.requireOriginalEraseC16Cut()
            var before = stat()
            if Darwin.fstatat(parent, name, &before, AT_SYMLINK_NOFOLLOW) != 0 {
                guard errno == ENOENT else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                // A preparing ordinal may already have performed its one
                // unlink before a cold restart. Only the caller's complete
                // postimage proof can turn that absence into a receipt.
                try self.requireOriginalEraseC16Cut()
                return
            }
            guard
                  before.st_mode & S_IFMT == S_IFREG,
                  before.st_nlink == 1 || before.st_nlink == 2,
                  UInt64(before.st_dev) == device,
                  UInt64(before.st_ino) == inode,
                  Int64(before.st_size) == byteCount else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            if let leaseName { try self.verifyLeaseDirectory(leaseName, descriptor: parent) }
            try self.requireOriginalEraseC16Cut()
            guard Darwin.unlinkat(parent, name, 0) == 0,
                  Darwin.fsync(parent) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            var after = stat()
            guard Darwin.fstatat(parent, name, &after, AT_SYMLINK_NOFOLLOW) != 0,
                  errno == ENOENT else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            if let leaseName { try self.verifyLeaseDirectory(leaseName, descriptor: parent) }
            try self.requireOriginalEraseC16Cut()
        }
        if leaseName != nil {
            let result = Result { try settle(descriptor) }
            try closeObservedScratchDescriptor(descriptor)
            try result.get()
        } else {
            try settle(descriptor)
            try ingressControlAuthority?.verify(rootName: "ProtectedIngressReceiptsV1")
        }
    }

    private var producerApplicationSupportURL: URL {
        rootURL.deletingLastPathComponent().deletingLastPathComponent()
    }

    private func withProducerFilesystemLock<Value>(_ body: () throws -> Value) throws -> Value {
        try requireScratchDescriptorAccess()
        guard originalEraseBorrowedLifetime == .ordinary else {
            // Public legacy operations never become alternate EX writers.
            // The sole typed borrowed controller calls the shared primitives.
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let activity = try OwnedStorageProducerActivityV1.acquire(
            applicationSupportURL: producerApplicationSupportURL)
        defer { activity.close() }
        return try Self.filesystemLock.withLock {
            try activity.requireApplicationSupport(producerApplicationSupportURL)
            return try body()
        }
    }

    /// A no-repair original observation cannot let an ambiguous descriptor
    /// close escape through an ordinary `defer { close }`. Keep the descriptor
    /// quarantined and poison the lexical original owner on the thrown close.
    private func closeObservedScratchDescriptor(_ descriptor: Int32) throws {
        try requireScratchDescriptorAccess()
        if exclusiveNoRepairRead {
            let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(
                descriptor)
            guard Darwin.close(descriptor) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
        } else {
            _ = Darwin.close(descriptor)
        }
    }

    private func withObservedScratchDescriptor<Value>(
        _ descriptor: Int32, _ body: (Int32) throws -> Value
    ) throws -> Value {
        try requireScratchDescriptorAccess()
        let outcome = Result { try body(descriptor) }
        try closeObservedScratchDescriptor(descriptor)
        return try outcome.get()
    }
    private var ingressControlAuthority: PinnedScratchRootV1?

    init(
        applicationSupportURL: URL,
        fileManager: FileManager = .default,
        clock: @escaping Clock,
        capacityProvider: @escaping StoragePreflightService.CapacityProvider = {
            try $0.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            ).volumeAvailableCapacityForImportantUsage
        },
        ingressHygieneFailureInjection: C16IngressHygieneFailureInjectionV1 = .none,
        ingressMutationFailureInjection: C16IngressMutationFailureInjectionV1 = .none
    ) throws {
        let constructionActivity = try OwnedStorageProducerActivityV1.acquire(
            applicationSupportURL: applicationSupportURL)
        defer { constructionActivity.close() }
        Self.filesystemLock.lock()
        defer { Self.filesystemLock.unlock() }
        let operations = applicationSupportURL.standardizedFileURL
            .appendingPathComponent(
                OwnedStorageRootKindV1.operations.rawValue,
                isDirectory: true
            )
        rootURL = operations.appendingPathComponent(Self.rootName, isDirectory: true)
        _ = fileManager // Source-compatible injection; descriptor I/O is authoritative.
        self.clock = clock
        self.ingressHygieneFailureInjection = ingressHygieneFailureInjection
        self.ingressMutationFailureInjection = ingressMutationFailureInjection
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

    private init(verifiedExistingTemporalRootAt applicationSupportURL: URL,
                 clock: @escaping Clock,
                 capacityProvider: @escaping StoragePreflightService.CapacityProvider = { _ in nil },
                 checkedClose: Bool = false) throws {
        let operations = applicationSupportURL.standardizedFileURL.appendingPathComponent(
            OwnedStorageRootKindV1.operations.rawValue, isDirectory: true)
        rootURL = operations.appendingPathComponent(Self.rootName, isDirectory: true)
        self.clock = clock
        ingressHygieneFailureInjection = .none
        ingressMutationFailureInjection = .none
        storagePreflight = StoragePreflightService(capacityProvider: capacityProvider)
        authority = try PinnedScratchRootV1(operationsURL: operations, rootName: Self.rootName)
        do {
            try authority.verify(rootName: Self.rootName)
            if checkedClose {
                _ = try ProtectedFilePolicyV1.observeTemporalPolicyWithCheckedClose(
                    .stagingDirectory, at: operations,
                    retainUncertainDescriptor: {
                        _ = ScratchUncertainCloseQuarantineV1.shared.begin($0)
                    })
                _ = try ProtectedFilePolicyV1.observeTemporalPolicyWithCheckedClose(
                    .stagingDirectory, at: rootURL,
                    retainUncertainDescriptor: {
                        _ = ScratchUncertainCloseQuarantineV1.shared.begin($0)
                    })
            } else {
                _ = try ProtectedFilePolicyV1.observeTemporalPolicy(.stagingDirectory, at: operations)
                _ = try ProtectedFilePolicyV1.observeTemporalPolicy(.stagingDirectory, at: rootURL)
            }
            try authority.verify(rootName: Self.rootName)
        } catch {
            // A failed checked close is quarantined by the pinned owner; the
            // exclusive caller poisons its original Erase operation as well.
            try? authority.closeCheckedForExclusiveOriginalEraseRead(verifyBeforeClose: false)
            throw error
        }
    }

    /// The original Erase operation already retains the only Support EX and
    /// Registry G. All nested calls into this adapter stay inside that same
    /// synchronous scope; the ordinary producer entry points remain unchanged.
    /// This constructor observes only an existing Scratch root and performs
    /// no ordinary root preparation or repair.
    @MainActor
    static func withSchema2ColdBorrowedExistingRoot<Value>(
        applicationSupportURL: URL,
        operationID: UUID,
        permit: EraseSchema2ColdScratchLifecyclePermitV1,
        frozenGenericLeaseAdmission:
            OriginalEraseFrozenLeaseAdmissionV1? = nil,
        referencePlan: OriginalEraseC16PlanV1? = nil,
        referenceProgress: OriginalEraseC16ReferenceProgressV1? = nil,
        verifyPostimageBeforeClose: @MainActor (Bool, Bool) throws -> Void,
        _ body: @MainActor (ScratchDataLeaseStoreV1) throws -> Value
    ) throws -> Value {
        try permit.requireObservationBinding()
        try referencePlan?.validate()
        if let referencePlan {
            guard let referenceProgress else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            try referenceProgress.validate(plan: referencePlan)
        } else if referenceProgress != nil {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        guard operationID != SettingsValidationV1.zeroUUID else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        let store: ScratchDataLeaseStoreV1
        do {
            store = try ScratchDataLeaseStoreV1(
                verifiedExistingTemporalRootAt: applicationSupportURL,
                clock: Date.init, checkedClose: true)
        } catch {
            permit.poisonOnUncertainEffect()
            throw error
        }
        return try Self.filesystemLock.withLock {
            store.originalEraseBorrowedLifetime = .active
            store.originalEraseBorrowedOwnerCheck = { try permit.requireObservationBinding() }
            store.originalEraseBorrowedExclusiveCheck = {
                try store.originalEraseBorrowedLocalLineageCheck()
            }
            store.originalEraseOperationID = operationID
            store.originalEraseColdPermit = permit
            store.originalEraseC16ReferencePlan = referencePlan
            store.originalEraseC16AdmissionProgress = referenceProgress
            store.originalEraseC16InitialSourceProof = referencePlan == nil
            store.exclusiveNoRepairRead = true
            store.originalEraseFrozenLeaseAdmission =
                frozenGenericLeaseAdmission
            defer {
                if store.originalEraseBorrowedLifetime == .active {
                    store.originalEraseBorrowedLifetime = .uncertain
                }
                store.originalEraseBorrowedExclusiveCheck = nil
                store.originalEraseBorrowedOwnerCheck = nil
                store.originalEraseOperationID = nil
                store.originalEraseColdPermit = nil
                store.originalEraseC16SourceInputs.removeAll()
                store.originalEraseC16BornSourceInputs.removeAll()
                store.originalEraseC16ObservationScope = nil
                store.originalEraseC16FirstPPairScope = nil
                store.originalEraseC16FirstPPairPolicies.removeAll()
                store.originalEraseC16ScopedPairPolicies.removeAll()
                store.originalEraseC16FirstPFacts.removeAll()
                store.originalEraseC16FirstPAbsentPaths.removeAll()
                store.originalEraseC16ReferencePlan = nil
                store.originalEraseC16AdmissionProgress = nil
                store.originalEraseC16InitialSourceProof = false
                store.originalEraseC16CurrentOrdinal = nil
                store.originalEraseFrozenLeaseAdmission = nil
            }
            var outcome: Result<Value, Error>
            do {
                try permit.requireObservationBinding()
                if let frozenGenericLeaseAdmission {
                    let cut = try store.originalEraseFrozenLeaseCut(
                        name: frozenGenericLeaseAdmission.originalName,
                        orderedChildren:
                            frozenGenericLeaseAdmission.orderedChildren)
                    guard frozenGenericLeaseAdmission.expectedDevice
                            == store.authority.rootDevice,
                          frozenGenericLeaseAdmission.expectedInode != 0 else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                    try frozenGenericLeaseAdmission.requirePrefix(
                        cut.tombstoned, cut.removedChildCount,
                        cut.leaseRootRemoved)
                    try permit.requireHeld()
                }
                try store.primeOriginalEraseC16ImmutableInputs(plan: referencePlan)
                if let plan = referencePlan, let progress = referenceProgress, !plan.steps.isEmpty {
                    let current = min(progress.completedC16PrefixCount, plan.steps.count - 1)
                    let captured = progress.activeC16Ordinal == current && progress.recordStage == .preparingCaptured
                    _ = try store.originalEraseC16CurrentObservationScope(plan: plan, currentOrdinal: current,
                        controlMarkerState: plan.steps[current] == .eraseFinalControl ? (captured ? .capturedPublished : .notYetCaptured) : nil,
                        ingressMarkerState: plan.steps[current] == .eraseIngress ? (captured ? .capturedPublished : .notYetCaptured) : nil)
                }
                try permit.requireHeld()
                store.originalEraseBorrowedAdmitting = true
                try store.originalEraseNoRepairSemanticAdmission()
                try permit.requireHeld()
                store.originalEraseBorrowedAdmitting = false
                outcome = Result { try body(store) }
                try permit.requireHeld()
            } catch {
                store.originalEraseBorrowedAdmitting = false
                outcome = .failure(error)
            }
            do {
                // A named ENOENT alone is never a deletion receipt. The
                // Router's operation-bound physical proof must classify the
                // complete Scratch/control cut while EX and G remain held.
                try permit.requireHeld()
                try verifyPostimageBeforeClose(
                    store.originalEraseRootRemovalProved,
                    store.originalEraseControlRemovalProved)
                try permit.requireHeld()
                store.originalEraseBorrowedLifetime = .closed
                if let control = store.ingressControlAuthority {
                    try control.closeCheckedForSchema2BorrowedScope(
                        verifyBeforeClose: !store.originalEraseControlRemovalProved,
                        rootName: "ProtectedIngressReceiptsV1", requireHeld: { try permit.requireObservationBinding() })
                    store.ingressControlAuthority = nil
                }
                try store.authority.closeCheckedForSchema2BorrowedScope(
                    verifyBeforeClose: !store.originalEraseRootRemovalProved,
                    rootName: "ScratchDataV1", requireHeld: { try permit.requireObservationBinding() })
                try permit.requireObservationBinding()
                store.originalEraseBorrowedLifetime = .closed
            } catch {
                store.originalEraseBorrowedLifetime = .uncertain
                store.ingressControlAuthority?
                    .quarantineUnclosedForOriginalErase()
                store.authority.quarantineUnclosedForOriginalErase()
                permit.poisonOnUncertainEffect()
                throw error
            }
            do { return try outcome.get() }
            catch {
                permit.poisonOnUncertainEffect()
                throw error
            }
        }
    }

    /// Classify the real control graph without invoking any recovery writer.
    /// Physical first-P equality and unchanged siblings are proved by the
    /// caller's retained original observer on both sides of this admission.
    private struct OriginalEraseC16TombstoneAuthorityV1 {
        let device: UInt64
        let inode: UInt64
        let files: [C16IngressHygieneFileIdentityV1]
    }

    private func originalEraseC16TombstoneAuthoritiesNoRepair()
        throws -> [String: OriginalEraseC16TombstoneAuthorityV1] {
        try requireScratchDescriptorAccess()
        guard try hasExistingIngressControl(),
              let control = ingressControlAuthority else { return [:] }
        if try regularFileInformationIfPresent(named: Self.controlEraseName,
            directoryDescriptor: control.rootDescriptor) != nil {
            return [:] // All C16 lease effects precede the control tail.
        }
        let directory = try protectedIngressReceiptDirectory()
        let names = try directoryNames(control.rootDescriptor)
        var result: [String: OriginalEraseC16TombstoneAuthorityV1] = [:]
        func add(_ name: String, device: UInt64, inode: UInt64,
                 files: [C16IngressHygieneFileIdentityV1]) throws {
            guard Self.isLeaseDirectoryName(name),
                  device == authority.rootDevice,
                  inode != 0,
                  files == files.sorted(by: { $0.name < $1.name }) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            let value = OriginalEraseC16TombstoneAuthorityV1(
                device: device, inode: inode, files: files)
            if let existing = result[name] {
                guard existing.device == value.device,
                      existing.inode == value.inode,
                      existing.files == value.files else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
            } else { result[name] = value }
        }
        for name in names where name.hasPrefix("hygiene-")
            && name.hasSuffix(".prepare.json") {
            let prepare = try readProtectedIngressPrepare(
                at: directory.appendingPathComponent(name))
            guard !prepare.finalized else { continue }
            for target in prepare.targets {
                try add(target.directoryName, device: target.device,
                    inode: target.inode, files: target.files)
            }
        }
        for name in names where name.hasPrefix("ingress-")
            && name.hasSuffix(".terminal.json") {
            let file = directory.appendingPathComponent(name)
            guard let terminal = try readIngressControl(
                C16IngressRemovalV1.self, at: file),
                  try CompatibilityCanonicalV1.encode(terminal)
                    == readIngressControlFile(file, maximumBytes: 262_144) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            try terminal.validate()
            let value = terminal.expected
            try add(value.claim.preparation.lease.relativeDirectory,
                device: value.claim.device, inode: value.claim.inode,
                files: [value.metadata, value.payload].sorted {
                    $0.name < $1.name
                })
        }
        for name in names where name.hasPrefix("erase-")
            && name.hasSuffix(".prepare.json") {
            let id = try ingressControlIdentifier(name, prefix: "erase-",
                suffixes: [".prepare.json"])
            let complete = directory.appendingPathComponent(
                "erase-" + id.uuidString.lowercased() + ".complete.json")
            guard try !ingressControlFileExists(complete) else { continue }
            let file = directory.appendingPathComponent(name)
            guard let erase = try readIngressControl(C16IngressEraseV1.self,
                    at: file),
                  try CompatibilityCanonicalV1.encode(erase)
                    == readIngressControlFile(file, maximumBytes: 262_144) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            try erase.validate()
            for target in erase.unpublishedTargets {
                if let leaf = target.directory {
                    try add(leaf.directoryName, device: leaf.device,
                        inode: leaf.inode, files: leaf.files)
                }
            }
        }
        return result
    }

    private func originalEraseNoRepairLeaseContents(
        named directoryName: String, descriptor: Int32,
        lease: ScratchDataLeaseV1
    ) throws {
        try requireScratchDescriptorAccess()
        var durableBytes: UInt64 = 0
        for child in try directoryNames(descriptor)
            where child != Self.metadataName {
            if child.hasPrefix(".partial-") {
                let raw = String(child.dropFirst(".partial-".count))
                var value = stat()
                guard UUID(uuidString: raw)?.uuidString.lowercased() == raw,
                      Darwin.fstatat(descriptor, child, &value,
                          AT_SYMLINK_NOFOLLOW) == 0,
                      value.st_mode & S_IFMT == S_IFREG,
                      value.st_nlink == 1 || value.st_nlink == 2,
                      value.st_uid == Darwin.geteuid(),
                      UInt64(value.st_dev) == authority.rootDevice,
                      value.st_size >= 0,
                      UInt64(value.st_size)
                        <= PendingLockedExternalIntentV1.maximumByteCount else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                // A pre-policy zero or partial write is opaque at admission.
                // Router's immutable first-P roster must prove its exact
                // bytes/policy; its own ordinal settles the name later.
                continue
            }
            let information = try regularFileInformation(named: child,
                directoryDescriptor: descriptor)
            try verifySourceReadPolicy(.temporaryFile,
                at: rootURL.appendingPathComponent(directoryName)
                    .appendingPathComponent(child))
            let next = durableBytes.addingReportingOverflow(
                UInt64(information.st_size))
            guard !next.overflow else {
                throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
            }
            durableBytes = next.partialValue
        }
        guard durableBytes <= lease.request.requestedByteCount else {
            throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
        }
    }

    @MainActor private func originalEraseNoRepairSemanticAdmission() throws {
        try requireScratchDescriptorAccess()
        try requireOriginalEraseBorrowedOwner()
        try originalEraseBorrowedExclusiveCheck?()
        try verifyRoot()
        if try hasExistingIngressControl() {
            _ = try protectedIngressReceiptDirectory()
            guard let control = ingressControlAuthority else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            if try regularFileInformationIfPresent(
                named: Self.controlEraseName,
                directoryDescriptor: control.rootDescriptor) != nil {
                try originalEraseValidateInterruptedControlEraseNoRepair(
                    control: control)
            } else {
                _ = try validatedIngressSnapshot(
                    applyingRecoveryEffects: false)
            }
        }
        let c16Tombstones = try originalEraseC16TombstoneAuthoritiesNoRepair()
        let children = try directoryNames(authority.rootDescriptor)
        for name in children {
            guard Self.isLeaseDirectoryName(name)
                || Self.isDeletionTombstone(name) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            let descriptor = try openLeaseDirectory(name)
            let closeAttempt = ScratchUncertainCloseQuarantineV1.shared.begin(
                descriptor)
            do {
                guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                let metadataURL = rootURL.appendingPathComponent(name)
                    .appendingPathComponent(Self.metadataName)
                let metadataPresent = try regularFileInformationIfPresent(
                    named: Self.metadataName,
                    directoryDescriptor: descriptor) != nil
                if !metadataPresent, Self.isDeletionTombstone(name) {
                    let originalName = String(name.dropFirst(
                        Self.deletionPrefix.count))
                    if let c16 = c16Tombstones[originalName] {
                        guard originalEraseFrozenLeaseAdmission?.originalName
                            != originalName else {
                            throw ScratchDataLeaseStoreFailureV1.leaseCollision
                        }
                        var held = stat()
                        guard Darwin.fstat(descriptor, &held) == 0,
                              UInt64(held.st_dev) == c16.device,
                              UInt64(held.st_ino) == c16.inode else {
                            throw ScratchDataLeaseStoreFailureV1.leaseCollision
                        }
                        try verifySourceReadPolicy(.stagingDirectory,
                            at: rootURL.appendingPathComponent(name))
                        let survivors = try ingressHygieneFileIdentities(
                            name: name, descriptor: descriptor)
                        guard survivors == Array(c16.files.suffix(
                            survivors.count)) else {
                            throw ScratchDataLeaseStoreFailureV1.leaseCollision
                        }
                        try verifyLeaseDirectory(name,
                            descriptor: descriptor)
                    } else if let frozen = originalEraseFrozenLeaseAdmission,
                        frozen.originalName == originalName {
                        var held = stat()
                        let survivors = try directoryNames(descriptor)
                        let removed = frozen.orderedChildren.count
                            - survivors.count
                        guard Darwin.fstat(descriptor, &held) == 0,
                              UInt64(held.st_dev)
                                == frozen.expectedDevice,
                              UInt64(held.st_ino)
                                == frozen.expectedInode,
                              removed >= 0,
                              let metadataIndex = frozen.orderedChildren
                                .firstIndex(of: Self.metadataName),
                              removed > metadataIndex,
                              survivors == Array(frozen.orderedChildren
                                .suffix(survivors.count)) else {
                            throw ScratchDataLeaseStoreFailureV1.leaseCollision
                        }
                        try verifySourceReadPolicy(.stagingDirectory,
                            at: rootURL.appendingPathComponent(name))
                        for child in survivors {
                            _ = try regularFileInformation(named: child,
                                directoryDescriptor: descriptor)
                            try verifySourceReadPolicy(.temporaryFile,
                                at: rootURL.appendingPathComponent(name)
                                    .appendingPathComponent(child))
                        }
                        try frozen.requirePrefix(true, removed, false)
                        try verifyLeaseDirectory(name,
                            descriptor: descriptor)
                    } else {
                        throw ScratchDataLeaseStoreFailureV1.invalidLease
                    }
                } else {
                let data = try readRegularFile(named: Self.metadataName,
                    directoryDescriptor: descriptor, maximumBytes: 65_536)
                try ProtectedFilePolicyV1
                    .verifyEraseColdPrivateWithCheckedClose(.temporaryFile,
                        at: metadataURL, retainUncertainDescriptor: {
                            _ = ScratchUncertainCloseQuarantineV1.shared.begin($0)
                        })
                let lease = try JSONDecoder().decode(
                    ScratchDataLeaseV1.self, from: data)
                try lease.request.validate()
                let leaseName = Self.isDeletionTombstone(name)
                    ? String(name.dropFirst(Self.deletionPrefix.count))
                    : name
                guard lease.schemaVersion == ScratchDataLeaseV1.schemaVersion,
                      lease.relativeDirectory == leaseName,
                      leaseName == Self.leaseDirectoryName(for: lease.request),
                      try canonicalData(lease) == data else {
                    throw ScratchDataLeaseStoreFailureV1.invalidLease
                }
                try originalEraseNoRepairLeaseContents(named: name,
                    descriptor: descriptor, lease: lease)
                try verifyLeaseDirectory(name, descriptor: descriptor)
                }
            } catch {
                if Darwin.close(descriptor) == 0 {
                    ScratchUncertainCloseQuarantineV1.shared.complete(
                        closeAttempt)
                }
                throw error
            }
            guard Darwin.close(descriptor) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            ScratchUncertainCloseQuarantineV1.shared.complete(closeAttempt)
        }
        try verifyRoot()
        try originalEraseBorrowedExclusiveCheck?()
    }

    /// A preexisting `scratch-erase.json` means the ordinary C16 control
    /// deletion already crossed its own durable prepare cut. The remaining
    /// control files must be the exact suffix of that marker's sorted file
    /// order. The ordinary deleter unlinks from the front with a parent fsync
    /// after each leaf; an arbitrary subset is a hostile hole, not replay.
    private func originalEraseValidateInterruptedControlEraseNoRepair(
        control: PinnedScratchRootV1
    ) throws {
        try requireScratchDescriptorAccess()
        try originalEraseBorrowedExclusiveCheck?()
        let directory = try protectedIngressReceiptDirectory()
        let descriptor = control.rootDescriptor
        let maximumMarkerBytes = 32 * 1_024 * 1_024
        let bytes = try readRegularFile(named: Self.controlEraseName,
            directoryDescriptor: descriptor,
            maximumBytes: maximumMarkerBytes)
        try verifySourceReadPolicy(.temporaryFile,
            at: directory.appendingPathComponent(Self.controlEraseName))
        let marker = try CompatibilityCanonicalV1.decode(
            C16ScratchControlEraseV1.self, from: bytes)
        guard try CompatibilityCanonicalV1.encode(marker) == bytes,
              marker.schemaVersion == 1,
              marker.rootDevice == authority.rootDevice,
              marker.rootInode == authority.rootInode,
              marker.controlDevice == control.rootDevice,
              marker.controlInode == control.rootInode,
              marker.files.count <= 100_000,
              marker.files.map(\.name) == marker.files.map(\.name).sorted(),
              Set(marker.files.map(\.name)).count == marker.files.count else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        for file in marker.files {
            try validateIngressControlSnapshotName(file.name)
            guard file.device == control.rootDevice,
                  file.byteCount >= 0,
                  file.modifiedNanoseconds >= 0,
                  file.modifiedNanoseconds < 1_000_000_000 else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        }
        let expected = Dictionary(uniqueKeysWithValues:
            marker.files.map { ($0.name, $0) })
        let remaining = try directoryNames(descriptor)
        guard remaining.contains(Self.controlEraseName) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let survivors = remaining.filter { $0 != Self.controlEraseName }
        guard survivors == Array(marker.files.map(\.name)
                .suffix(survivors.count)) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        for name in remaining where name != Self.controlEraseName {
            try validateIngressControlSnapshotName(name)
            let current = try C16IngressHygieneFileIdentityV1(
                name: name, information: regularFileInformation(
                    named: name, directoryDescriptor: descriptor))
            guard expected[name] == current else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            try verifySourceReadPolicy(.temporaryFile,
                at: directory.appendingPathComponent(name))
        }
        try control.verify(rootName: "ProtectedIngressReceiptsV1")
        guard try readRegularFile(named: Self.controlEraseName,
            directoryDescriptor: descriptor,
            maximumBytes: maximumMarkerBytes) == bytes else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try originalEraseBorrowedExclusiveCheck?()
    }

    #if DEBUG
    convenience init(
        applicationSupportURL: URL,
        fileManager: FileManager = .default,
        clock: @escaping Clock,
        capacityProvider: @escaping StoragePreflightService.CapacityProvider = {
            try $0.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            ).volumeAvailableCapacityForImportantUsage
        },
        ingressHygieneFailureInjection: C16IngressHygieneFailureInjectionV1 = .none,
        ingressMutationFailureInjection: C16IngressMutationFailureInjectionV1 = .none,
        testingIngressControlInventoryObserver: @escaping IngressControlInventoryObserver,
        testingBeforeIngressControlFinalInventory: @escaping BeforeIngressControlFinalInventory
    ) throws {
        try self.init(applicationSupportURL: applicationSupportURL, fileManager: fileManager,
            clock: clock, capacityProvider: capacityProvider,
            ingressHygieneFailureInjection: ingressHygieneFailureInjection,
            ingressMutationFailureInjection: ingressMutationFailureInjection)
        ingressControlInventoryObserver = testingIngressControlInventoryObserver
        beforeIngressControlFinalInventory = testingBeforeIngressControlFinalInventory
    }
    #endif

    /// C16 pre-authentication cleanup reads only immediate directory metadata
    /// under the sole scratch root. It never opens `lease.json` or any payload
    /// file. Valid fresh entries are retained; uncertain entries are deferred
    /// to authenticated recovery. Only prepared filesystem identities are removed.
    func purgeConfidentlyOwnedExpiredScratchMetadata(
        now: Date,
        operationID: UUID,
        minimumAge: TimeInterval = 24 * 60 * 60
    ) throws -> ProtectedIngressStartupHygieneReceiptV1 {
        try requireScratchDescriptorAccess()
        try reconcileProtectedIngressHygiene(
            now: now, operationID: operationID, minimumAge: minimumAge
        )
    }

    /// Crash-safe C16 startup hygiene. Preparation is durable before a target
    /// is removed; the prepared metadata is sufficient to recreate the exact
    /// final receipt after interruption without opening any payload bytes.
    func reconcileProtectedIngressHygiene(
        now: Date, operationID: UUID,
        minimumAge: TimeInterval = 24 * 60 * 60
    ) throws -> ProtectedIngressStartupHygieneReceiptV1 {
        try requireScratchDescriptorAccess()
        try Self.validateC16HygieneRequest(now: now, operationID: operationID,
            minimumAge: minimumAge)
        return try withProducerFilesystemLock {
            try runC16SemanticSession(c16HygieneSteps(now: now,
                operationID: operationID, minimumAge: minimumAge))
            let receipt = try protectedIngressReceiptFile(operationID: operationID)
            return try readProtectedIngressReceipt(at: receipt, operationID: operationID)
        }
    }

    private static func validateC16HygieneRequest(now: Date, operationID: UUID,
                                                 minimumAge: TimeInterval) throws {
        guard operationID != SettingsValidationV1.zeroUUID,
              now.timeIntervalSinceReferenceDate.isFinite,
              minimumAge > 0, minimumAge.isFinite else {
            throw AppAccessContractFailureV1.invalidValue
        }
    }

    private func c16HygieneSteps(now: Date, operationID: UUID,
                                minimumAge: TimeInterval,
                                beforeRemainingTargets: [C16SemanticStepV1] = []) -> [C16SemanticStepV1] {
        [.plan { _ in
            try Self.validateC16HygieneRequest(now: now, operationID: operationID,
                minimumAge: minimumAge)
            let request = C16IngressHygieneRequestV1(operationID: operationID,
                requestedAt: now, minimumAge: minimumAge)
            let digest = try CompatibilityCanonicalV1.sha256(CompatibilityCanonicalV1.encode(request))
            _ = try self.protectedIngressReceiptDirectory()
            let prepareFile = try self.protectedIngressPrepareFile(operationID: operationID)
            let receiptFile = try self.protectedIngressReceiptFile(operationID: operationID)
            let prepare: C16IngressHygienePrepareV1
            var steps: [C16SemanticStepV1] = []
            if try self.ingressControlFileExists(prepareFile) {
                prepare = try self.readProtectedIngressPrepare(at: prepareFile)
                guard prepare.requestDigest == digest else { throw AppAccessContractFailureV1.effectMismatch }
            } else {
                guard try !self.ingressControlFileExists(receiptFile) else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
                prepare = try self.makeProtectedIngressPrepare(request: request, requestDigest: digest)
                steps += try self.c16PublicationSteps(CompatibilityCanonicalV1.encode(prepare), to: prepareFile)
                steps.append(.effect { try self.ingressHygieneFailureInjection.interruptIfTriggered(.afterPrepare) })
            }
            steps.append(.plan { _ in
                guard prepare.rootDevice == self.authority.rootDevice,
                      prepare.rootInode == self.authority.rootInode else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
                let expected = try prepare.receipt()
                if try self.ingressControlFileExists(receiptFile) {
                    guard try self.readProtectedIngressReceipt(at: receiptFile, operationID: operationID) == expected else {
                        throw AppAccessContractFailureV1.effectMismatch
                    }
                    return beforeRemainingTargets
                        + (prepare.finalized ? [] : self.c16FinalizeHygieneSteps(prepare, at: prepareFile))
                }
                guard !prepare.finalized else { throw AppAccessContractFailureV1.configurationUnknown }
                var work = beforeRemainingTargets
                    + prepare.targets.flatMap(self.c16PreparedTargetSteps)
                work.append(.effect { try self.ingressHygieneFailureInjection.interruptIfTriggered(.afterEffect) })
                work.append(.plan { _ in
                    try self.c16PublicationSteps(CompatibilityCanonicalV1.encode(expected), to: receiptFile)
                })
                work.append(.effect { try self.ingressHygieneFailureInjection.interruptIfTriggered(.afterReceipt) })
                work += self.c16FinalizeHygieneSteps(prepare, at: prepareFile)
                work.append(.effect {
                    guard try self.readProtectedIngressReceipt(at: receiptFile, operationID: operationID) == expected else {
                        throw AppAccessContractFailureV1.effectMismatch
                    }
                })
                return work
            })
            return steps
        }]
    }

    /// Device-local, metadata-only completion receipt. It is deliberately
    /// outside canonical workspace storage and contains neither a path nor
    /// any staged/payload bytes. The closed operation-ID filename prevents
    /// directory traversal and gives interrupted startup an exact readback.
    func readProtectedIngressHygieneReceipt(
        operationID: UUID
    ) throws -> ProtectedIngressStartupHygieneReceiptV1? {
        try requireScratchDescriptorAccess()
        guard operationID != SettingsValidationV1.zeroUUID else {
            throw AppAccessContractFailureV1.invalidValue
        }
        return try withProducerFilesystemLock {
            let file = try protectedIngressReceiptFile(operationID: operationID)
            guard try ingressControlFileExists(file) else { return nil }
            let data = try readIngressControlFile(file, maximumBytes: 4_096)
            let decoded = try JSONDecoder().decode(ProtectedIngressStartupHygieneReceiptV1.self, from: data)
            let validated = try ProtectedIngressStartupHygieneReceiptV1(
                operationID: decoded.operationID,
                inspectedCount: decoded.inspectedCount,
                removedKnownOwnedCount: decoded.removedKnownOwnedCount,
                retainedValidCount: decoded.retainedValidCount,
                deferredAmbiguousCount: decoded.deferredAmbiguousCount,
                contentRead: decoded.contentRead
            )
            guard validated == decoded,
                  decoded.operationID == operationID,
                  try CompatibilityCanonicalV1.encode(decoded) == data else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            return decoded
        }
    }

    func writeProtectedIngressHygieneReceipt(
        _ value: ProtectedIngressStartupHygieneReceiptV1
    ) throws {
        try requireScratchDescriptorAccess()
        let validated = try ProtectedIngressStartupHygieneReceiptV1(
            operationID: value.operationID,
            inspectedCount: value.inspectedCount,
            removedKnownOwnedCount: value.removedKnownOwnedCount,
            retainedValidCount: value.retainedValidCount,
            deferredAmbiguousCount: value.deferredAmbiguousCount,
            contentRead: value.contentRead
        )
        guard validated == value, !value.contentRead else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let data = try CompatibilityCanonicalV1.encode(value)
        guard data.count <= 4_096 else { throw AppAccessContractFailureV1.configurationUnknown }
        try withProducerFilesystemLock {
            let file = try protectedIngressReceiptFile(operationID: value.operationID)
            try writeProtectedIngressCanonical(data, to: file)
        }
        guard try readProtectedIngressHygieneReceipt(operationID: value.operationID) == value else {
            throw AppAccessContractFailureV1.effectMismatch
        }
    }

    private func protectedIngressReceiptDirectory() throws -> URL {
        try requireScratchDescriptorAccess()
        try verifyRoot()
        let name = "ProtectedIngressReceiptsV1"
        let directory = rootURL.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
        if ingressControlAuthority == nil {
            if originalEraseBorrowedExclusiveCheck != nil {
                // No first observation is authorized by a failed mkdir, and
                // this getter must never create or repair during EX admission.
                var existing = stat()
                guard Darwin.fstatat(authority.operationsDescriptor, name,
                    &existing, AT_SYMLINK_NOFOLLOW) == 0,
                    existing.st_mode & S_IFMT == S_IFDIR else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
            } else {
                try Self.prepareRoot(directory)
            }
            let pinned = try PinnedScratchRootV1(operationsURL: directory.deletingLastPathComponent(), rootName: name)
            if originalEraseBorrowedExclusiveCheck != nil {
                try ProtectedFilePolicyV1.verifyEraseColdPrivateWithCheckedClose(
                    .stagingDirectory, at: directory,
                    retainUncertainDescriptor: {
                        _ = ScratchUncertainCloseQuarantineV1.shared.begin($0)
                    })
                try pinned.verify(rootName: name)
            } else {
                try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: directory, authorityCheck: {
                    try self.verifyRoot()
                    try pinned.verify(rootName: name)
                })
            }
            ingressControlAuthority = pinned
        }
        try ingressControlAuthority?.verify(rootName: name)
        if originalEraseBorrowedExclusiveCheck != nil {
            try ProtectedFilePolicyV1.verifyEraseColdPrivateWithCheckedClose(
                .stagingDirectory, at: directory,
                retainUncertainDescriptor: {
                    _ = ScratchUncertainCloseQuarantineV1.shared.begin($0)
                })
        } else {
            try ProtectedFilePolicyV1.verify(.stagingDirectory, at: directory)
        }
        try ingressControlAuthority?.verify(rootName: name)
        return directory
    }

    private func ingressControlDescriptor() throws -> Int32 {
        try requireScratchDescriptorAccess()
        _ = try protectedIngressReceiptDirectory()
        guard let ingressControlAuthority else { throw AppAccessContractFailureV1.configurationUnknown }
        guard try regularFileInformationIfPresent(named: Self.controlEraseName,
            directoryDescriptor: ingressControlAuthority.rootDescriptor) == nil else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        // Settle the existing no-replace publisher's temporary hard link before
        // opening a completed control file; this reads metadata only.
        observeIngressControlInventoryForTesting()
        if !originalEraseBorrowedAdmitting {
            if originalEraseBorrowedExclusiveCheck == nil {
                // Only the ordinary owner repairs interrupted publications.
                // The borrowed getter is read-only even when a .partial name
                // is present; its actor-isolated effect step proves that cut.
                try removeInterruptedPublications(
                    directoryDescriptor: ingressControlAuthority.rootDescriptor)
            }
        }
        try ingressControlAuthority.verify(rootName: "ProtectedIngressReceiptsV1")
        return ingressControlAuthority.rootDescriptor
    }

    private func ingressControlFileExists(_ file: URL) throws -> Bool {
        try requireScratchDescriptorAccess()
        guard file.deletingLastPathComponent() == (try protectedIngressReceiptDirectory()) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        return try regularFileInformationIfPresent(named: file.lastPathComponent,
            directoryDescriptor: ingressControlDescriptor()) != nil
    }

    private func readIngressControlFile(_ file: URL, maximumBytes: Int) throws -> Data {
        try requireScratchDescriptorAccess()
        guard file.deletingLastPathComponent() == (try protectedIngressReceiptDirectory()) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let data: Data
        if originalEraseBorrowedExclusiveCheck != nil {
            guard let leaf = try readOriginalErasePublicationLeaf(named: file.lastPathComponent,
                parent: ingressControlDescriptor(), maximumBytes: maximumBytes) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            data = leaf.1
        } else {
            data = try readRegularFile(named: file.lastPathComponent,
                directoryDescriptor: ingressControlDescriptor(), maximumBytes: maximumBytes)
        }
        try verifySourceReadPolicy(.temporaryFile, at: file)
        _ = try protectedIngressReceiptDirectory()
        return data
    }

    private func protectedIngressScratchDirectory() throws -> URL {
        try requireScratchDescriptorAccess()
        try verifyRoot()
        return rootURL
    }

    private func protectedIngressReceiptFile(operationID: UUID) throws -> URL {
        try requireScratchDescriptorAccess()
        guard operationID != SettingsValidationV1.zeroUUID else {
            throw AppAccessContractFailureV1.invalidValue
        }
        return try protectedIngressReceiptDirectory().appendingPathComponent(
            "hygiene-" + operationID.uuidString.lowercased() + ".json",
            isDirectory: false
        )
    }

    private func protectedIngressPrepareFile(operationID: UUID) throws -> URL {
        try requireScratchDescriptorAccess()
        guard operationID != SettingsValidationV1.zeroUUID else {
            throw AppAccessContractFailureV1.invalidValue
        }
        return try protectedIngressReceiptDirectory().appendingPathComponent(
            "hygiene-" + operationID.uuidString.lowercased() + ".prepare.json",
            isDirectory: false
        )
    }

    private func makeProtectedIngressPrepare(
        request: C16IngressHygieneRequestV1,
        requestDigest: String
    ) throws -> C16IngressHygienePrepareV1 {
        try requireScratchDescriptorAccess()
        try verifyRoot()
        let names = try directoryNames(authority.rootDescriptor)
        guard names.count <= ProtectedIngressStartupHygieneReceiptV1.maximumInspectedCount else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        var targets: [C16IngressHygieneTargetV1] = []
        var retained = 0
        var deferred = 0
        for name in names {
            do {
                guard Self.isLeaseDirectoryName(name) else {
                    deferred += 1
                    continue
                }
                let descriptor = try openLeaseDirectory(name)
                defer { _ = Darwin.close(descriptor) }
                let directory = rootURL.appendingPathComponent(name, isDirectory: true)
                try ProtectedFilePolicyV1.verify(.stagingDirectory, at: directory)
                let files = try ingressHygieneFileIdentities(name: name, descriptor: descriptor)
                var information = stat()
                guard Darwin.fstat(descriptor, &information) == 0 else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
                let modified = Date(timeIntervalSince1970: TimeInterval(information.st_mtimespec.tv_sec)
                    + TimeInterval(information.st_mtimespec.tv_nsec) / 1_000_000_000)
                try verifyLeaseDirectory(name, descriptor: descriptor)
                if modified > request.requestedAt || files.contains(where: {
                    TimeInterval($0.modifiedSeconds) + TimeInterval($0.modifiedNanoseconds) / 1_000_000_000
                        > request.requestedAt.timeIntervalSince1970
                }) {
                    deferred += 1
                } else if modified > request.requestedAt.addingTimeInterval(-request.minimumAge)
                    || files.contains(where: {
                        TimeInterval($0.modifiedSeconds) + TimeInterval($0.modifiedNanoseconds) / 1_000_000_000
                            > request.requestedAt.addingTimeInterval(-request.minimumAge).timeIntervalSince1970
                    }) {
                    retained += 1
                } else {
                    targets.append(try .init(directoryName: name, modifiedAt: modified,
                        information: information, files: files))
                }
            } catch {
                // Metadata that cannot prove ownership is left for authenticated recovery.
                try verifyRoot()
                deferred += 1
            }
        }
        return try .init(request: request, requestDigest: requestDigest, targets: targets,
            rootDevice: authority.rootDevice, rootInode: authority.rootInode,
            retainedValidCount: retained, deferredAmbiguousCount: deferred, finalized: false)
    }

    private func ingressHygieneFileIdentities(name: String, descriptor: Int32) throws -> [C16IngressHygieneFileIdentityV1] {
        try requireScratchDescriptorAccess()
        try verifyLeaseDirectory(name, descriptor: descriptor)
        let names = try directoryNames(descriptor)
        guard names.count <= 128 else { throw AppAccessContractFailureV1.configurationUnknown }
        return try names.map { child in
            let before = try regularFileInformation(named: child, directoryDescriptor: descriptor)
            try verifySourceReadPolicy(.temporaryFile,
                at: rootURL.appendingPathComponent(name).appendingPathComponent(child))
            let after = try regularFileInformation(named: child, directoryDescriptor: descriptor)
            let identity = C16IngressHygieneFileIdentityV1(name: child, information: before)
            guard identity == C16IngressHygieneFileIdentityV1(name: child, information: after) else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            try verifyLeaseDirectory(name, descriptor: descriptor)
            return identity
        }
    }

    /// Read-only admission for a target in an already durable original erase.
    /// The same removal owner may have renamed or removed it before interruption.
    /// Preserve every remaining identity before any target effect resumes.
    private func validatePreparedIngressTargetForRecovery(_ target: C16IngressHygieneTargetV1) throws {
        try requireScratchDescriptorAccess()
        let tombstone = Self.deletionTombstoneName(for: target.directoryName)
        let original = try directoryInformationIfPresent(named: target.directoryName)
        let deleting = try directoryInformationIfPresent(named: tombstone)
        if originalEraseBorrowedExclusiveCheck != nil,
           original != nil, deleting != nil {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        if original == nil && deleting == nil { return }
        let name = deleting == nil ? target.directoryName : tombstone
        let descriptor = try openLeaseDirectory(name)
        try withObservedScratchDescriptor(descriptor) { descriptor in
        var pinned = stat()
        guard Darwin.fstat(descriptor, &pinned) == 0,
              UInt64(pinned.st_dev) == target.device, UInt64(pinned.st_ino) == target.inode else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try verifySourceReadPolicy(.stagingDirectory,
            at: rootURL.appendingPathComponent(name))
        let actual = try ingressHygieneFileIdentities(name: name, descriptor: descriptor)
        if deleting == nil {
            let modified = Date(timeIntervalSince1970: TimeInterval(pinned.st_mtimespec.tv_sec)
                + TimeInterval(pinned.st_mtimespec.tv_nsec) / 1_000_000_000)
            guard modified == target.modifiedAt, actual == target.files else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        } else {
            let allowed = originalEraseBorrowedExclusiveCheck != nil
                ? actual == Array(target.files.suffix(actual.count))
                : actual.allSatisfy({ target.files.contains($0) })
            guard allowed else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        }
        try verifyLeaseDirectory(name, descriptor: descriptor)
        }
    }

    private func removePreparedIngressTarget(_ target: C16IngressHygieneTargetV1) throws {
        try requireScratchDescriptorAccess()
        try runC16SemanticSession(c16PreparedTargetSteps(target))
    }

    private func c16PreparedTargetSteps(_ target: C16IngressHygieneTargetV1)
        -> [C16SemanticStepV1] {
        c16OwnedTargetSteps(originalName: target.directoryName,
            device: target.device, inode: target.inode, files: target.files,
            modifiedAt: target.modifiedAt)
    }

    private func c16OwnedTargetSteps(originalName: String, device: UInt64,
        inode: UInt64, files: [C16IngressHygieneFileIdentityV1],
        modifiedAt: Date? = nil) -> [C16SemanticStepV1] {
        [.plan { session in
            try self.requireScratchDescriptorAccess()
            let tombstone = Self.deletionTombstoneName(for: originalName)
            let original = try self.directoryInformationIfPresent(named: originalName)
            let deleting = try self.directoryInformationIfPresent(named: tombstone)
            if self.originalEraseBorrowedExclusiveCheck != nil,
               original != nil, deleting != nil {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            if original == nil && deleting == nil { return [] }
            let name = deleting == nil ? originalName : tombstone
            let descriptor = try self.openLeaseDirectory(name)
            session.retain(descriptor)
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            var pinned = stat()
            guard Darwin.fstat(descriptor, &pinned) == 0,
                  UInt64(pinned.st_dev) == device,
                  UInt64(pinned.st_ino) == inode else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            try self.verifySourceReadPolicy(.stagingDirectory,
                at: self.rootURL.appendingPathComponent(name))
            let actual = try self.ingressHygieneFileIdentities(name: name, descriptor: descriptor)
            var steps: [C16SemanticStepV1] = []
            if deleting == nil {
                let modified = Date(timeIntervalSince1970: TimeInterval(pinned.st_mtimespec.tv_sec)
                    + TimeInterval(pinned.st_mtimespec.tv_nsec) / 1_000_000_000)
                guard (modifiedAt == nil || modified == modifiedAt), actual == files else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
                steps.append(.effect {
                    try self.verifyLeaseDirectory(name, descriptor: descriptor)
                    guard try self.ingressHygieneFileIdentities(name: name, descriptor: descriptor) == files,
                          Darwin.renameat(self.authority.rootDescriptor, name,
                            self.authority.rootDescriptor, tombstone) == 0,
                          Darwin.fsync(self.authority.rootDescriptor) == 0 else {
                        throw AppAccessContractFailureV1.configurationUnknown
                    }
                })
            } else {
                let allowed = self.originalEraseBorrowedExclusiveCheck != nil
                    ? actual == Array(files.suffix(actual.count))
                    : actual.allSatisfy({ files.contains($0) })
                guard allowed else { throw AppAccessContractFailureV1.configurationUnknown }
            }
            steps.append(contentsOf: self.c16DeletePinnedDirectorySteps(named: tombstone,
                descriptor: descriptor, expectedFiles: files))
            steps.append(.effect { try session.close(descriptor) })
            return steps
        }]
    }

    private func readProtectedIngressPrepare(at file: URL) throws -> C16IngressHygienePrepareV1 {
        try requireScratchDescriptorAccess()
        let data = try readIngressControlFile(file, maximumBytes: 262_144)
        let value = try JSONDecoder().decode(C16IngressHygienePrepareV1.self, from: data)
        try value.validate()
        guard try CompatibilityCanonicalV1.encode(value) == data else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        return value
    }

    private func readProtectedIngressReceipt(
        at file: URL,
        operationID: UUID
    ) throws -> ProtectedIngressStartupHygieneReceiptV1 {
        try requireScratchDescriptorAccess()
        let data = try readIngressControlFile(file, maximumBytes: 4_096)
        let decoded = try JSONDecoder().decode(ProtectedIngressStartupHygieneReceiptV1.self, from: data)
        let validated = try ProtectedIngressStartupHygieneReceiptV1(
            operationID: decoded.operationID, inspectedCount: decoded.inspectedCount,
            removedKnownOwnedCount: decoded.removedKnownOwnedCount,
            retainedValidCount: decoded.retainedValidCount,
            deferredAmbiguousCount: decoded.deferredAmbiguousCount, contentRead: decoded.contentRead
        )
        guard decoded == validated, decoded.operationID == operationID,
              try CompatibilityCanonicalV1.encode(decoded) == data else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        return decoded
    }

    private func writeProtectedIngressCanonical(_ data: Data, to file: URL) throws {
        try requireScratchDescriptorAccess()
        guard data.count <= 262_144,
              file.deletingLastPathComponent() == (try protectedIngressReceiptDirectory()) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try publishDurably(data, named: file.lastPathComponent,
            directoryDescriptor: ingressControlDescriptor(), directoryURL: file.deletingLastPathComponent(),
            finalURL: file, directoryAuthorityCheck: { _ = try self.protectedIngressReceiptDirectory() })
    }

    private func finalizeProtectedIngressPrepare(_ prepare: C16IngressHygienePrepareV1, at file: URL) throws {
        try requireScratchDescriptorAccess()
        try runC16SemanticSession(c16FinalizeHygieneSteps(prepare, at: file))
    }

    private func c16FinalizeHygieneSteps(_ prepare: C16IngressHygienePrepareV1, at file: URL)
        -> [C16SemanticStepV1] {
        [.plan { _ in
            try self.requireScratchDescriptorAccess()
            let finalized = try prepare.finalizing()
            let current = try self.readProtectedIngressPrepare(at: file)
            if current == finalized { return [] }
            guard current == prepare else { throw AppAccessContractFailureV1.effectMismatch }
            let staged = file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + ".finalizing")
            var steps = try self.c16PublicationSteps(CompatibilityCanonicalV1.encode(finalized), to: staged)
            steps.append(.effect {
                guard try self.readProtectedIngressPrepare(at: file) == prepare else {
                    throw AppAccessContractFailureV1.effectMismatch
                }
                let descriptor = try self.ingressControlDescriptor()
                guard Darwin.renameat(descriptor, staged.lastPathComponent, descriptor, file.lastPathComponent) == 0,
                      Darwin.fsync(descriptor) == 0,
                      try self.readProtectedIngressPrepare(at: file) == finalized else {
                    throw AppAccessContractFailureV1.effectMismatch
                }
            })
            if originalEraseBorrowedExclusiveCheck != nil {
                steps += c16CaptureBornSourceSteps(try CompatibilityCanonicalV1.encode(finalized), at: file)
            }
            return steps
        }]
    }

    private struct C16ValidatedIngressSnapshotV1 {
        let preparations: [C16IngressPreparedStageV1]
        let pending: [C16IngressPublicationV1]
        let unresolvedPreparations: [C16IngressPreparedStageV1]
    }

    /// One complete control-root admission owns this inventory only while the
    /// process-wide filesystem lock is held. Individual file reads still pin
    /// and recheck file identity; the final name comparison proves membership,
    /// not unchanged contents or metadata.
    private struct C16IngressControlInventoryV1 {
        let descriptor: Int32
        var expectedNames: Set<String>
    }

    func pendingProtectedIngress() throws -> [PendingLockedExternalIntentV1] {
        try requireScratchDescriptorAccess()
        return try withProducerFilesystemLock { try pendingIngressPublications().map(\.intent) }
    }

    private func pendingIngressPublications() throws -> [C16IngressPublicationV1] {
        try requireScratchDescriptorAccess()
        return try validatedIngressSnapshot(
            applyingRecoveryEffects: originalEraseBorrowedExclusiveCheck == nil).pending
    }

    /// Reconstructs the complete ingress control state under the caller's
    /// filesystem lock. The classification is intentionally post-hygiene: a
    /// completed hygiene removal is terminal before a later stage/erase uses
    /// the result for admission.
    private func validatedIngressSnapshot(
        frozenErase: C16IngressEraseV1? = nil,
        applyingRecoveryEffects: Bool = true,
        recoveryIntentID: UUID? = nil,
        plannedRecovery: (([C16SemanticStepV1]) -> Void)? = nil
    ) throws -> C16ValidatedIngressSnapshotV1 {
        try requireScratchDescriptorAccess()
        if originalEraseBorrowedExclusiveCheck != nil,
           applyingRecoveryEffects {
            guard let recoveryIntentID,
                  originalEraseOperationID != nil else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            // The borrowed dispatcher has already checked the preparing
            // ordinal. This routine only plans/reads until the nested
            // publication and removal effect primitives take their own cuts.
            try originalEraseBorrowedExclusiveCheck?()
            guard recoveryIntentID != SettingsValidationV1.zeroUUID else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        }
        if let frozenErase {
            try frozenErase.validate()
            guard frozenErase.rootDevice == authority.rootDevice,
                  frozenErase.rootInode == authority.rootInode else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        }
        let frozenEraseTargets = Dictionary(uniqueKeysWithValues:
            (frozenErase?.targets ?? []).map { ($0.intent.intentID, $0) })
        let frozenUnpublishedTargets = Dictionary(uniqueKeysWithValues:
            (frozenErase?.unpublishedTargets ?? []).map { ($0.preparation.intent.intentID, $0) })
        var inventory = try beginIngressControlInventory()
        let preparations = try ingressPreparations(inventory: &inventory)
        var borrowedUnpublished: [UUID: (
            target: C16IngressUnpublishedEraseTargetV1,
            operationID: UUID)] = [:]
        if originalEraseBorrowedExclusiveCheck != nil {
            for name in inventory.expectedNames.sorted()
                where name.hasPrefix("erase-")
                    && name.hasSuffix(".prepare.json") {
                let id = try ingressControlIdentifier(name,
                    prefix: "erase-", suffixes: [".prepare.json"])
                let complete = try protectedIngressReceiptDirectory()
                    .appendingPathComponent("erase-"
                        + id.uuidString.lowercased() + ".complete.json")
                guard !inventory.expectedNames.contains(
                    complete.lastPathComponent) else { continue }
                let file = try protectedIngressReceiptDirectory()
                    .appendingPathComponent(name)
                guard let erase = try readIngressControl(
                    C16IngressEraseV1.self, at: file,
                    inventory: &inventory) else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
                for target in erase.unpublishedTargets {
                    let targetID = target.preparation.intent.intentID
                    guard borrowedUnpublished[targetID] == nil else {
                        throw AppAccessContractFailureV1.configurationUnknown
                    }
                    borrowedUnpublished[targetID] = (target, id)
                }
            }
        }
        let preparationIDs = Set(preparations.map { $0.intent.intentID })
        guard Set(frozenEraseTargets.keys).isSubset(of: preparationIDs),
              Set(frozenUnpublishedTargets.keys).isSubset(of: preparationIDs),
              Set(borrowedUnpublished.keys).isSubset(of: preparationIDs) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        var pending: [C16IngressPublicationV1] = []
        var unresolvedPreparations: [C16IngressPreparedStageV1] = []
        var preparedCount = 0
        for preparation in preparations {
            let id = preparation.intent.intentID
            let applyThisRecovery = applyingRecoveryEffects
                && (recoveryIntentID == nil || recoveryIntentID == id)
            let claim = try readIngressControl(C16IngressDirectoryClaimV1.self,
                at: ingressControlURL(id, ".claim.json"), inventory: &inventory)
            let published = try readIngressControl(C16IngressPublicationV1.self,
                at: ingressControlURL(id, ".published.json"), inventory: &inventory)
            let current = try readIngressControl(C16IngressPublicationV1.self,
                at: ingressControlURL(id, ".pending.json"), inventory: &inventory)
            let terminal = try readIngressControl(C16IngressRemovalV1.self,
                at: ingressControlURL(id, ".terminal.json"), inventory: &inventory)
            let frozenUnpublishedTarget = frozenUnpublishedTargets[id]
                ?? borrowedUnpublished[id]?.target
            if let target = frozenUnpublishedTarget {
                guard target.preparation == preparation, target.claim == claim,
                      published == nil, current == nil, terminal == nil else {
                    throw AppAccessContractFailureV1.effectMismatch
                }
                if target.directory == nil {
                    let name = preparation.lease.relativeDirectory
                    guard try directoryInformationIfPresent(named: name) == nil,
                          try directoryInformationIfPresent(named: Self.deletionTombstoneName(for: name)) == nil else {
                        throw AppAccessContractFailureV1.configurationUnknown
                    }
                }
            }
            if let aborted = try readIngressControl(C16IngressAbortedStageV1.self,
                at: ingressControlURL(id, ".aborted.json"), inventory: &inventory) {
                guard published == nil, current == nil, terminal == nil else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
                try validateAbortedIngress(aborted, preparation: preparation, claim: claim)
                if let target = frozenUnpublishedTarget {
                    guard aborted.expected == target,
                          aborted.operationID == (frozenErase?.operationID
                            ?? borrowedUnpublished[id]?.operationID) else {
                        throw AppAccessContractFailureV1.effectMismatch
                    }
                }
                continue
            }
            if terminal == nil {
                preparedCount += 1
                guard preparedCount <= ProtectedIngressCoordinatorV1.maximumPendingIntentCount else {
                    throw AppAccessContractFailureV1.ingressLimitExceeded
                }
            }
            guard let claim else {
                guard published == nil, current == nil, terminal == nil,
                      try directoryInformationIfPresent(named: preparation.lease.relativeDirectory) == nil else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
                if terminal == nil { unresolvedPreparations.append(preparation) }
                continue // Prepared only: no file effect was published.
            }
            guard claim.preparation == preparation, claim.device == authority.rootDevice else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            guard let published else {
                guard current == nil, terminal == nil else { throw AppAccessContractFailureV1.configurationUnknown }
                if let target = frozenUnpublishedTarget {
                    guard let directory = target.directory else {
                        throw AppAccessContractFailureV1.effectMismatch
                    }
                    // Only this immutable, original erase may admit its own
                    // interrupted deletion before the aborted marker exists.
                    try validatePreparedIngressTargetForRecovery(directory)
                } else if originalEraseBorrowedExclusiveCheck != nil {
                    _ = try originalEraseC16ClaimOnlySource(preparation: preparation, claim: claim)
                } else {
                    let descriptor = try validateIngressClaim(claim)
                    try closeObservedScratchDescriptor(descriptor)
                }
                unresolvedPreparations.append(preparation)
                continue // Claimed incomplete copy remains owned, but is not a pending intent.
            }
            try published.validate()
            guard published.claim == claim, published.intent == preparation.intent else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            let borrowedRecipe = originalEraseBorrowedExclusiveCheck != nil
                ? try originalEraseC16IngressRecipe(for: current ?? terminal?.expected ?? published) : nil
            if let terminal {
                try terminal.validate()
                guard try published.replacingIntent(terminal.expected.intent) == terminal.expected else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
                if let frozenTarget = frozenEraseTargets[id] {
                    let expectedRemoval = C16IngressRemovalV1(expected: frozenTarget, disposition: .erased)
                    try expectedRemoval.validate()
                    guard terminal == expectedRemoval else { throw AppAccessContractFailureV1.effectMismatch }
                }
                if applyThisRecovery, let plannedRecovery {
                    try validateIngressRemovalWithoutEffects(terminal)
                    plannedRecovery(c16IngressRemovalSteps(terminal))
                } else {
                    try settleIngressRemoval(terminal, applyingEffects: applyThisRecovery)
                    if applyThisRecovery {
                        inventory.expectedNames.remove(try ingressControlName(id, ".pending.json"))
                    }
                }
                continue
            }
            let value = current ?? published
            guard try published.replacingIntent(value.intent) == value else { throw AppAccessContractFailureV1.configurationUnknown }
            if let frozenTarget = frozenEraseTargets[id] {
                guard value == frozenTarget else { throw AppAccessContractFailureV1.effectMismatch }
            }
            let frozenRemoval = frozenEraseTargets[id].map {
                C16IngressRemovalV1(expected: $0, disposition: .erased)
            }
            if let recipe = borrowedRecipe, let removal = recipe.removal {
                if let frozenRemoval, frozenRemoval != removal {
                    throw AppAccessContractFailureV1.effectMismatch
                }
                if !recipe.hygiene.isEmpty {
                    try validatePreparedIngressTargetForRecovery(recipe.hygiene[0])
                } else {
                    try validateIngressPublication(value, hashPayload: false)
                }
                // This is read-only scoped admission. Effects run only through
                // the exact prepared ordinal in the shared semantic engine.
                guard !applyThisRecovery else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                unresolvedPreparations.append(preparation)
                continue
            }
            if try adoptCompletedIngressHygieneRemoval(value, applyingEffects: applyThisRecovery,
                                                      expectedRemoval: frozenRemoval,
                                                      plannedRecovery: plannedRecovery) {
                if applyThisRecovery && plannedRecovery == nil {
                    guard inventory.expectedNames.insert(try ingressControlName(id, ".terminal.json")).inserted else {
                        throw AppAccessContractFailureV1.configurationUnknown
                    }
                    inventory.expectedNames.remove(try ingressControlName(id, ".pending.json"))
                }
                continue
            }
            if originalEraseBorrowedExclusiveCheck != nil,
               !applyThisRecovery,
               let hygieneTarget = try originalEraseUnfinishedHygieneTarget(
                    for: value) {
                try validatePreparedIngressTargetForRecovery(
                    hygieneTarget)
                unresolvedPreparations.append(preparation)
                continue
            }
            try validateIngressPublication(value, hashPayload: false)
            if current == nil {
                // Exact publication is durable; only its pending pointer was interrupted.
                try validateIngressPublication(value, hashPayload: true)
                if applyThisRecovery {
                    let file = try ingressControlURL(id, ".pending.json")
                    if let plannedRecovery {
                        plannedRecovery(try c16PublicationSteps(CompatibilityCanonicalV1.encode(value), to: file))
                    } else {
                        try writeProtectedIngressCanonical(try CompatibilityCanonicalV1.encode(value), to: file)
                        guard inventory.expectedNames.insert(try ingressControlName(id, ".pending.json")).inserted else {
                            throw AppAccessContractFailureV1.configurationUnknown
                        }
                    }
                }
            }
            pending.append(value)
            unresolvedPreparations.append(preparation)
        }
        try finishIngressControlInventory(&inventory)
        return .init(preparations: preparations,
                     pending: pending.sorted { $0.intent.intentID.uuidString < $1.intent.intentID.uuidString },
                     unresolvedPreparations: unresolvedPreparations.sorted {
                         $0.intent.intentID.uuidString < $1.intent.intentID.uuidString
                     })
    }

    /// A lossless executable reference recipe. These values are observations
    /// of authenticated, fixed source roles, not a second persisted journal.
    /// The sidecar already retains their source hashes and semantic step order.
    private func originalEraseC16ClaimOnlySource(
        preparation: C16IngressPreparedStageV1,
        claim: C16IngressDirectoryClaimV1
    ) throws -> C16IngressUnpublishedEraseTargetV1 {
        try requireScratchDescriptorAccess()
        guard originalEraseBorrowedExclusiveCheck != nil,
              claim.preparation == preparation, claim.device == authority.rootDevice else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let directoryName = preparation.lease.relativeDirectory
        var selected: C16IngressHygieneTargetV1?
        for name in try originalEraseC16ReferenceNames()
            where name.hasPrefix("hygiene-") && name.hasSuffix(".prepare.json") {
            let prepare = try originalEraseC16ReferenceValue(C16IngressHygienePrepareV1.self, name: name)
            for target in prepare.targets where target.directoryName == directoryName {
                guard target.device == claim.device, target.inode == claim.inode,
                      selected == nil || selected == target else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                _ = try originalEraseC16HygieneGroupCut(prepare)
                selected = target
            }
        }
        // A fixed older E may be the lossless owner of an unfinished claim
        // even after its H source has completed. Never select a Q directory.
        for name in try originalEraseC16ReferenceNames()
            where name.hasPrefix("erase-") && name.hasSuffix(".prepare.json") {
            let erase = try originalEraseC16ReferenceValue(C16IngressEraseV1.self, name: name)
            for target in erase.unpublishedTargets where target.preparation == preparation {
                guard target.claim == claim else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                if let directory = target.directory {
                    if let selected {
                        guard selected.directoryName == directory.directoryName,
                              selected.device == directory.device, selected.inode == directory.inode,
                              selected.modifiedAt == directory.modifiedAt,
                              selected.files.filter({ !$0.name.hasPrefix(".partial-") }) == directory.files else {
                            throw ScratchDataLeaseStoreFailureV1.leaseCollision
                        }
                    } else { selected = directory }
                }
            }
        }
        if let selected {
            // H retains every early partial file and performs its fixed
            // deletion first. The aborted/E record remains the unchanged
            // unpublished schema containing only lease.json/opaque-data.
            _ = try originalEraseC16TargetCut(.init(selected))
            let directory = try C16IngressHygieneTargetV1(directoryName: directoryName,
                modifiedAt: selected.modifiedAt, device: selected.device, inode: selected.inode,
                files: selected.files.filter { !$0.name.hasPrefix(".partial-") })
            let result = C16IngressUnpublishedEraseTargetV1(preparation: preparation, directory: directory)
            try result.validate(); return result
        }
        let originalPath = "ScratchDataV1/" + directoryName
        guard let directory = try originalEraseC16FirstPFact(path: originalPath),
              try originalEraseC16FirstPFact(path: "ScratchDataV1/" + Self.deletionTombstoneName(for: directoryName)) == nil,
              directory.device == claim.device, directory.inode == claim.inode else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let fixedFiles: [OriginalEraseC16FileFactV1]
        if let plan = originalEraseC16ReferencePlan {
            guard let target = plan.freshUnpublishedTargets.first(where: { $0.intentID == preparation.intent.intentID }),
                  let fact = target.directory, fact.directoryName == directoryName,
                  fact.device == claim.device, fact.inode == claim.inode else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            fixedFiles = fact.files
        } else {
            guard originalEraseC16InitialSourceProof else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            fixedFiles = try [Self.metadataName, "opaque-data"].compactMap { name in
                guard let fact = try originalEraseC16FirstPFact(path: originalPath + "/" + name) else { return nil }
                return OriginalEraseC16FileFactV1(name: name, device: fact.device, inode: fact.inode,
                    byteCount: fact.byteCount, modifiedSeconds: fact.modifiedSeconds,
                    modifiedNanoseconds: fact.modifiedNanoseconds)
            }.sorted { $0.name < $1.name }
        }
        let modifiedAt: Date
        if !originalEraseC16InitialSourceProof,
           let actual = try directoryInformationIfPresent(named: directoryName) {
            guard UInt64(actual.st_dev) == claim.device, UInt64(actual.st_ino) == claim.inode else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            modifiedAt = Date(timeIntervalSince1970: TimeInterval(actual.st_mtimespec.tv_sec)
                + TimeInterval(actual.st_mtimespec.tv_nsec) / 1_000_000_000)
        } else { modifiedAt = directory.modifiedAt }
        let target = try C16IngressHygieneTargetV1(directoryName: directoryName,
            modifiedAt: modifiedAt, device: claim.device, inode: claim.inode,
            files: fixedFiles.map(C16IngressHygieneFileIdentityV1.init))
        let result = C16IngressUnpublishedEraseTargetV1(preparation: preparation, directory: target)
        try result.validate()
        _ = try originalEraseC16TargetCut(.init(target))
        return result
    }

    private struct OriginalEraseC16IngressRecipeV1 {
        let expected: C16IngressPublicationV1
        let removal: C16IngressRemovalV1?
        let hygiene: [C16IngressHygieneTargetV1]
        let expirationReceiptOperationID: UUID?
        let terminalBeforeHygieneOrdinal: Int?
        let initialTerminal: Bool
    }

    private func originalEraseC16ReferenceNames() throws -> [String] {
        try requireScratchDescriptorAccess()
        if let plan = originalEraseC16ReferencePlan {
            guard let progress = originalEraseC16AdmissionProgress else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            try progress.validate(plan: plan)
            return plan.markerBindings.map(\.name)
        }
        guard originalEraseC16InitialSourceProof,
              originalEraseBorrowedExclusiveCheck != nil,
              originalEraseC16CurrentOrdinal == nil else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        return try directoryNames(ingressControlDescriptor())
    }

    private func originalEraseC16ReferenceValue<Value: Codable>(
        _ type: Value.Type, name: String
    ) throws -> Value {
        try requireScratchDescriptorAccess()
        guard let source = originalEraseC16SourceInputs[name],
              source.bytes.count <= Self.originalEraseC16SourceMaximum(name: name) else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let value = try CompatibilityCanonicalV1.decode(type, from: source.bytes)
        guard try CompatibilityCanonicalV1.encode(value) == source.bytes else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        if let plan = originalEraseC16ReferencePlan {
            guard let binding = plan.markerBindings.first(where: { $0.name == name }),
                  try CompatibilityCanonicalV1.sha256(source.bytes) == binding.sha256 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        } else if !originalEraseC16InitialSourceProof {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        return value
    }

    /// Finalization changes only one canonical flag. Authenticate the exact
    /// inverse against the first-P SHA; never treat a Q survivor as a new plan.
    private func originalEraseC16ReferenceHygiene(
        name: String
    ) throws -> (initial: C16IngressHygienePrepareV1,
                 current: C16IngressHygienePrepareV1) {
        try requireScratchDescriptorAccess()
        let initial = try originalEraseC16ReferenceValue(C16IngressHygienePrepareV1.self, name: name)
        try initial.validate()
        let file = try protectedIngressReceiptDirectory().appendingPathComponent(name)
        guard try ingressControlFileExists(file) else { return (initial, initial) }
        let current = try readProtectedIngressPrepare(at: file)
        guard current == initial || (!initial.finalized && current == initial.finalizing()) else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        return (initial, current)
    }

    private func originalEraseC16FixedIngressRecipeData(
        intentID: UUID
    ) throws -> OriginalEraseC16IngressRecipeV1 {
        try requireScratchDescriptorAccess()
        let names = try originalEraseC16ReferenceNames()
        let published = try originalEraseC16ReferenceValue(C16IngressPublicationV1.self,
            name: ingressControlName(intentID, ".published.json"))
        let pendingName = try ingressControlName(intentID, ".pending.json")
        let terminalName = try ingressControlName(intentID, ".terminal.json")
        let initialTerminal = names.contains(terminalName)
        let terminal = initialTerminal ? try originalEraseC16ReferenceValue(C16IngressRemovalV1.self, name: terminalName) : nil
        let expected: C16IngressPublicationV1
        if let terminal { expected = terminal.expected }
        else if names.contains(pendingName) {
            expected = try originalEraseC16ReferenceValue(C16IngressPublicationV1.self, name: pendingName)
        } else { expected = published }
        try expected.validate()
        guard try published.replacingIntent(expected.intent) == expected else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        var eraseExpected: C16IngressPublicationV1?
        for name in names where name.hasPrefix("erase-") && name.hasSuffix(".prepare.json") {
            let id = try ingressControlIdentifier(name, prefix: "erase-", suffixes: [".prepare.json"])
            let incomplete = originalEraseC16ReferencePlan.map { $0.steps.contains(.resumeIngressErase(operationID: id)) }
                ?? !names.contains("erase-" + id.uuidString.lowercased() + ".complete.json")
            guard incomplete else { continue }
            let erase = try originalEraseC16ReferenceValue(C16IngressEraseV1.self, name: name)
            try erase.validate()
            if let value = erase.targets.first(where: { $0.intent.intentID == intentID }) {
                guard value == expected, eraseExpected == nil || eraseExpected == value else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                eraseExpected = value
            }
        }
        struct Association {
            let target: C16IngressHygieneTargetV1
            let operationID: UUID
            let initiallyCompleted: Bool
            let expired: Bool
            let ordinal: Int?
        }
        var associations: [Association] = [], initialOrdinal = 0
        for name in names where name.hasPrefix("hygiene-") && name.hasSuffix(".prepare.json") {
            let prepare = try originalEraseC16ReferenceValue(C16IngressHygienePrepareV1.self, name: name)
            try prepare.validate()
            guard prepare.rootDevice == authority.rootDevice, prepare.rootInode == authority.rootInode else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            let ordinal: Int?
            let receiptName = "hygiene-" + prepare.request.operationID.uuidString.lowercased() + ".json"
            let completed = names.contains(receiptName)
            if completed {
                let receipt = try originalEraseC16ReferenceValue(ProtectedIngressStartupHygieneReceiptV1.self, name: receiptName)
                guard receipt == (try prepare.receipt()) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            }
            if prepare.finalized || completed { ordinal = nil }
            else if let plan = originalEraseC16ReferencePlan {
                guard let index = plan.steps.firstIndex(of: .resumeHygiene(operationID: prepare.request.operationID)) else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                ordinal = index
            } else { ordinal = initialOrdinal; initialOrdinal += 1 }
            guard let target = prepare.targets.first(where: { OriginalEraseC16TargetFactV1($0) == OriginalEraseC16TargetFactV1(expected) }) else { continue }
            associations.append(.init(target: target, operationID: prepare.request.operationID,
                initiallyCompleted: completed, expired: prepare.request.requestedAt >= expected.intent.expiresAt, ordinal: ordinal))
        }
        let removal: C16IngressRemovalV1?
        let expirationReceipt: UUID?
        let terminalOrdinal: Int?
        if let eraseExpected {
            removal = .init(expected: eraseExpected, disposition: .erased)
            expirationReceipt = nil; terminalOrdinal = associations.compactMap(\.ordinal).min()
        } else if let terminal {
            removal = terminal; expirationReceipt = nil; terminalOrdinal = nil
        } else if let completed = associations.first(where: { $0.initiallyCompleted && $0.expired }) {
            removal = .init(expected: expected, disposition: .expiredDeleted)
            expirationReceipt = completed.operationID; terminalOrdinal = nil
        } else if associations.contains(where: { $0.initiallyCompleted }) {
            removal = .init(expected: expected, disposition: .erased)
            expirationReceipt = nil; terminalOrdinal = nil
        } else if let first = associations.filter({ $0.ordinal != nil }).min(by: { $0.ordinal! < $1.ordinal! }) {
            removal = .init(expected: expected, disposition: first.expired ? .expiredDeleted : .erased)
            expirationReceipt = first.expired ? first.operationID : nil
            terminalOrdinal = first.expired ? nil : first.ordinal
        } else { removal = nil; expirationReceipt = nil; terminalOrdinal = nil }
        if let removal { try removal.validate() }
        if let terminal, let removal { guard terminal == removal else { throw ScratchDataLeaseStoreFailureV1.leaseCollision } }
        return .init(expected: expected, removal: removal, hygiene: associations.map(\.target),
            expirationReceiptOperationID: expirationReceipt,
            terminalBeforeHygieneOrdinal: initialTerminal ? nil : terminalOrdinal, initialTerminal: initialTerminal)
    }

    private func originalEraseC16IngressRecipe(
        for observed: C16IngressPublicationV1
    ) throws -> OriginalEraseC16IngressRecipeV1 {
        try requireScratchDescriptorAccess()
        let source = try originalEraseC16FixedIngressRecipeData(intentID: observed.intent.intentID)
        guard observed == source.expected else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        let pending = try readIngressControl(C16IngressPublicationV1.self, at: ingressControlURL(observed.intent.intentID, ".pending.json"))
        let terminal = try readIngressControl(C16IngressRemovalV1.self, at: ingressControlURL(observed.intent.intentID, ".terminal.json"))
        guard pending == nil || pending == source.expected else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        for name in try originalEraseC16ReferenceNames() where name.hasPrefix("hygiene-") && name.hasSuffix(".prepare.json") {
            let value = try originalEraseC16ReferenceHygiene(name: name)
            _ = try originalEraseC16HygieneGroupCut(value.current)
        }
        var removal = source.removal
        if removal == nil, terminal != nil,
           originalEraseC16ReferencePlan?.freshPublishedTargets.contains(where: {
               $0.intentID == observed.intent.intentID && $0.directory == OriginalEraseC16TargetFactV1(observed)
           }) == true { removal = .init(expected: source.expected, disposition: .erased) }
        if let terminal {
            try terminal.validate()
            guard terminal == removal else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            if let id = source.expirationReceiptOperationID, !source.initialTerminal {
                let prepare = try originalEraseC16ReferenceValue(C16IngressHygienePrepareV1.self,
                    name: "hygiene-" + id.uuidString.lowercased() + ".prepare.json")
                guard try readProtectedIngressReceipt(at: protectedIngressReceiptFile(operationID: id),
                    operationID: id) == prepare.receipt(),
                    originalEraseC16TargetCut(.init(observed)) == .absent else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
            }
        }
        if source.removal?.disposition == .erased, source.hygiene.isEmpty,
           !source.initialTerminal, terminal == nil {
            guard pending == source.expected, try originalEraseC16TargetCut(.init(observed)) == .original else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        }
        return .init(expected: source.expected, removal: removal, hygiene: source.hygiene,
            expirationReceiptOperationID: source.expirationReceiptOperationID,
            terminalBeforeHygieneOrdinal: source.terminalBeforeHygieneOrdinal, initialTerminal: source.initialTerminal)
    }

    private func originalEraseC16HygieneTerminalSteps(
        operationID: UUID, ordinal: Int
    ) throws -> [C16SemanticStepV1] {
        try requireScratchDescriptorAccess()
        guard let plan = originalEraseC16ReferencePlan,
              plan.steps[ordinal] == .resumeHygiene(operationID: operationID) else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        return [.plan { [self] _ in
            var work: [C16SemanticStepV1] = []
            for binding in plan.markerBindings where binding.name.hasPrefix("ingress-")
                && binding.name.hasSuffix(".published.json") {
                let published = try originalEraseC16ReferenceValue(
                    C16IngressPublicationV1.self, name: binding.name)
                let id = published.intent.intentID
                let pending = try readIngressControl(C16IngressPublicationV1.self, at: ingressControlURL(id, ".pending.json"))
                let terminal = try readIngressControl(C16IngressRemovalV1.self, at: ingressControlURL(id, ".terminal.json"))
                let recipe = try originalEraseC16IngressRecipe(for: pending ?? terminal?.expected ?? published)
                guard recipe.terminalBeforeHygieneOrdinal == ordinal else { continue }
                guard let removal = recipe.removal, removal.disposition == .erased else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                if terminal == nil {
                    work += try c16PublicationSteps(CompatibilityCanonicalV1.encode(removal),
                        to: ingressControlURL(id, ".terminal.json"))
                }
            }
            return work
        }]
    }

    private func originalEraseC16PointerRecoverySteps(intentID: UUID) -> [C16SemanticStepV1] {
        [.plan { [self] _ in
            guard let plan = originalEraseC16ReferencePlan,
                  let ordinal = originalEraseC16CurrentOrdinal,
                  plan.steps[ordinal] == .recoverIngressPointer(intentID: intentID) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            let published = try originalEraseC16ReferenceValue(C16IngressPublicationV1.self,
                name: ingressControlName(intentID, ".published.json"))
            let pending = try readIngressControl(C16IngressPublicationV1.self, at: ingressControlURL(intentID, ".pending.json"))
            let terminal = try readIngressControl(C16IngressRemovalV1.self, at: ingressControlURL(intentID, ".terminal.json"))
            let recipe = try originalEraseC16IngressRecipe(for: pending ?? terminal?.expected ?? published)
            if let removal = recipe.removal {
                if let operationID = recipe.expirationReceiptOperationID {
                    let source = try originalEraseC16ReferenceHygiene(name: "hygiene-"
                        + operationID.uuidString.lowercased() + ".prepare.json").initial
                    guard try readProtectedIngressReceipt(at: protectedIngressReceiptFile(operationID: operationID),
                            operationID: operationID) == source.receipt(),
                          try originalEraseC16TargetCut(OriginalEraseC16TargetFactV1(recipe.expected)) == .absent else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                }
                try validateIngressRemovalWithoutEffects(removal)
                return (terminal == nil ? try c16PublicationSteps(CompatibilityCanonicalV1.encode(removal),
                    to: ingressControlURL(intentID, ".terminal.json")) : [])
                    + c16IngressRemovalSteps(removal)
            }
            try validateIngressPublication(recipe.expected, hashPayload: pending == nil)
            return pending == nil ? try c16PublicationSteps(CompatibilityCanonicalV1.encode(recipe.expected),
                to: ingressControlURL(intentID, ".pending.json")) : []
        }]
    }

    private func adoptCompletedIngressHygieneRemoval(
        _ value: C16IngressPublicationV1,
        applyingEffects: Bool = true,
        expectedRemoval: C16IngressRemovalV1? = nil,
        plannedRecovery: (([C16SemanticStepV1]) -> Void)? = nil
    ) throws -> Bool {
        try requireScratchDescriptorAccess()
        let name = value.claim.preparation.lease.relativeDirectory
        // An original Erase binds completed hygiene to its durable request
        // timestamp below. A fresh process must not change the classification
        // merely because wall time advanced after first-P admission.
        guard (originalEraseBorrowedExclusiveCheck != nil
                || clock() >= value.intent.expiresAt),
              try directoryInformationIfPresent(named: name) == nil,
              try directoryInformationIfPresent(named: Self.deletionTombstoneName(for: name)) == nil else { return false }
        // Blind hygiene never opens pending metadata. Explicit ingress recovery
        // can recognize its completed, exactly pinned deletion afterward.
        for fileName in try directoryNames(ingressControlDescriptor())
        where fileName.hasPrefix("hygiene-") && fileName.hasSuffix(".prepare.json") {
            let directory = try protectedIngressReceiptDirectory()
            let prepare = try readProtectedIngressPrepare(at: directory.appendingPathComponent(fileName))
            guard prepare.rootDevice == value.claim.preparation.rootDevice,
                  prepare.rootInode == value.claim.preparation.rootInode,
                  prepare.request.requestedAt >= value.intent.expiresAt,
                  prepare.targets.contains(where: { target in
                      target.directoryName == name && target.device == value.claim.device && target.inode == value.claim.inode
                          && target.files == [value.metadata, value.payload].sorted(by: { $0.name < $1.name })
                  }) else { continue }
            let receiptFile = try protectedIngressReceiptFile(operationID: prepare.request.operationID)
            guard try ingressControlFileExists(receiptFile),
                  try readProtectedIngressReceipt(at: receiptFile, operationID: prepare.request.operationID) == prepare.receipt() else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            let removal = C16IngressRemovalV1(expected: value, disposition: .expiredDeleted)
            if let expectedRemoval, removal != expectedRemoval {
                throw AppAccessContractFailureV1.effectMismatch
            }
            if applyingEffects, let plannedRecovery {
                let file = try ingressControlURL(value.intent.intentID, ".terminal.json")
                plannedRecovery(try c16PublicationSteps(CompatibilityCanonicalV1.encode(removal), to: file)
                    + c16IngressRemovalSteps(removal))
                try validateIngressRemovalWithoutEffects(removal)
            } else {
                if applyingEffects {
                    try writeProtectedIngressCanonical(try CompatibilityCanonicalV1.encode(removal),
                        to: ingressControlURL(value.intent.intentID, ".terminal.json"))
                }
                try settleIngressRemoval(removal, applyingEffects: applyingEffects)
            }
            return true
        }
        return false
    }

    private func originalEraseUnfinishedHygieneTarget(
        for value: C16IngressPublicationV1
    ) throws -> C16IngressHygieneTargetV1? {
        try requireScratchDescriptorAccess()
        guard originalEraseBorrowedExclusiveCheck != nil else { return nil }
        let directory = try protectedIngressReceiptDirectory()
        for name in try directoryNames(ingressControlDescriptor())
            where name.hasPrefix("hygiene-")
                && name.hasSuffix(".prepare.json") {
            let prepare = try readProtectedIngressPrepare(
                at: directory.appendingPathComponent(name))
            guard !prepare.finalized else { continue }
            let receipt = try protectedIngressReceiptFile(
                operationID: prepare.request.operationID)
            if let target = prepare.targets.first(where: {
                $0.directoryName
                    == value.claim.preparation.lease.relativeDirectory
                    && $0.device == value.claim.device
                    && $0.inode == value.claim.inode
                    && $0.files == [value.metadata, value.payload].sorted {
                        $0.name < $1.name
                    }
            }) {
                guard try !ingressControlFileExists(receipt) else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
                return target
            }
        }
        return nil
    }

    func stageProtectedIngress(_ request: ProtectedIngressStageRequestV1, source: URL) throws -> PendingLockedExternalIntentV1 {
        try requireScratchDescriptorAccess()
        return try withProducerFilesystemLock {
            guard source.isFileURL, C16IngressPreparedStageV1.supportedKinds.contains(request.kind),
                  request.receivedAt <= clock(), clock() < request.expiresAt else {
                throw AppAccessContractFailureV1.invalidValue
            }
            let scope = source.startAccessingSecurityScopedResource()
            defer { if scope { source.stopAccessingSecurityScopedResource() } }
            let sourceDescriptor = Darwin.open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            guard sourceDescriptor >= 0 else { throw AppAccessContractFailureV1.configurationUnknown }
            defer { _ = Darwin.close(sourceDescriptor) }
            let sourceHash = try opaqueSHA256(descriptor: sourceDescriptor, byteCount: request.byteCount)
            var sourceIdentity = stat()
            guard Darwin.fstat(sourceDescriptor, &sourceIdentity) == 0 else { throw AppAccessContractFailureV1.configurationUnknown }
            let intent = try PendingLockedExternalIntentV1(intentID: request.intentID, operationID: request.operationID,
                kind: request.kind, opaqueStagingID: "opaque-" + request.intentID.uuidString.lowercased(),
                byteCount: request.byteCount, sha256: sourceHash, receivedAt: request.receivedAt,
                expiresAt: request.expiresAt, disposition: .stagedProtectedPendingAuthentication)
            let leaseRequest = try ScratchDataLeaseRequestV1(leaseID: request.intentID, purpose: .importData,
                owner: .importData, ownerOperationID: request.operationID, requestedByteCount: request.byteCount,
                createdAt: request.receivedAt, expiresAt: request.expiresAt)
            let lease = try ScratchDataLeaseV1(request: leaseRequest, relativeDirectory: Self.leaseDirectoryName(for: leaseRequest))
            let preparation = C16IngressPreparedStageV1(intent: intent, lease: lease,
                rootDevice: authority.rootDevice, rootInode: authority.rootInode)
            try validateIngressPreparation(preparation, intentID: request.intentID)
            let snapshot = try validatedIngressSnapshot()
            let pending = snapshot.pending
            if let existing = pending.first(where: { $0.intent.intentID == request.intentID }) {
                guard existing.claim.preparation == preparation else { throw AppAccessContractFailureV1.effectMismatch }
                try validateIngressPublication(existing, hashPayload: true)
                try validateOpaqueSourceLink(source, expected: sourceIdentity)
                return existing.intent
            }
            let terminalFile = try ingressControlURL(request.intentID, ".terminal.json")
            let abortedFile = try ingressControlURL(request.intentID, ".aborted.json")
            guard try !ingressControlFileExists(terminalFile),
                  try !ingressControlFileExists(abortedFile) else { throw AppAccessContractFailureV1.invalidTransition }
            let prepareFile = try ingressControlURL(request.intentID, ".prepare.json")
            if let existing = try readIngressControl(C16IngressPreparedStageV1.self, at: prepareFile) {
                guard existing == preparation else { throw AppAccessContractFailureV1.effectMismatch }
            } else {
                guard snapshot.unresolvedPreparations.count < ProtectedIngressCoordinatorV1.maximumPendingIntentCount else {
                    throw AppAccessContractFailureV1.ingressLimitExceeded
                }
                try storagePreflight.checkScratchLease(requestedByteCount: request.byteCount, onVolumeContaining: rootURL)
                try writeProtectedIngressCanonical(try CompatibilityCanonicalV1.encode(preparation), to: prepareFile)
                try ingressMutationFailureInjection.interruptIfTriggered(.afterPrepare)
            }
            let name = lease.relativeDirectory
            let directory = rootURL.appendingPathComponent(name, isDirectory: true)
            let claimFile = try ingressControlURL(request.intentID, ".claim.json")
            let claim: C16IngressDirectoryClaimV1
            if let existing = try readIngressControl(C16IngressDirectoryClaimV1.self, at: claimFile) {
                guard existing.preparation == preparation else { throw AppAccessContractFailureV1.effectMismatch }
                claim = existing
            } else {
                try verifyRoot()
                guard try directoryInformationIfPresent(named: name) == nil,
                      Darwin.mkdirat(authority.rootDescriptor, name, 0o700) == 0,
                      Darwin.fsync(authority.rootDescriptor) == 0 else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
                let descriptor = try openLeaseDirectory(name)
                defer { _ = Darwin.close(descriptor) }
                var information = stat()
                guard Darwin.fstat(descriptor, &information) == 0 else { throw AppAccessContractFailureV1.configurationUnknown }
                try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: directory, authorityCheck: {
                    try self.verifyLeaseDirectory(name, descriptor: descriptor)
                })
                claim = .init(preparation: preparation, device: UInt64(information.st_dev), inode: UInt64(information.st_ino))
                try writeProtectedIngressCanonical(try CompatibilityCanonicalV1.encode(claim), to: claimFile)
            }
            let descriptor = try validateIngressClaim(claim)
            defer { _ = Darwin.close(descriptor) }
            try ingressMutationFailureInjection.interruptIfTriggered(.afterClaim)
            try removeInterruptedPublications(directoryDescriptor: descriptor)
            try publishDurably(try canonicalData(lease), named: Self.metadataName, directoryDescriptor: descriptor,
                directoryURL: directory, finalURL: directory.appendingPathComponent(Self.metadataName), leaseName: name)
            let payload = try publishOpaqueIngress(sourceDescriptor: sourceDescriptor, preparation: preparation,
                directoryDescriptor: descriptor)
            try ingressMutationFailureInjection.interruptIfTriggered(.afterOpaqueCopy)
            try validateOpaqueSourceLink(source, expected: sourceIdentity)
            let publication = C16IngressPublicationV1(claim: claim,
                metadata: .init(name: Self.metadataName, information: try regularFileInformation(named: Self.metadataName, directoryDescriptor: descriptor)),
                payload: payload, intent: intent)
            try validateIngressPublication(publication, hashPayload: true)
            try writeProtectedIngressCanonical(try CompatibilityCanonicalV1.encode(publication),
                to: ingressControlURL(request.intentID, ".published.json"))
            try ingressMutationFailureInjection.interruptIfTriggered(.afterPublication)
            try writeProtectedIngressCanonical(try CompatibilityCanonicalV1.encode(publication),
                to: ingressControlURL(request.intentID, ".pending.json"))
            try ingressMutationFailureInjection.interruptIfTriggered(.afterPending)
            guard try pendingIngressPublications().first(where: { $0.intent.intentID == request.intentID }) == publication else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            return intent
        }
    }

    func replaceProtectedIngress(expected: PendingLockedExternalIntentV1, replacement: PendingLockedExternalIntentV1) throws {
        try requireScratchDescriptorAccess()
        try withProducerFilesystemLock {
            try expected.validate()
            try replacement.validate()
            guard replacement.disposition == .readyForAuthenticatedValidation,
                  expected.disposition == .stagedProtectedPendingAuthentication || expected.disposition == .readyForAuthenticatedValidation,
                  try expected.advancing(to: replacement.disposition) == replacement,
                  clock() < expected.expiresAt else { throw AppAccessContractFailureV1.invalidTransition }
            guard let current = try pendingIngressPublications().first(where: { $0.intent.intentID == expected.intentID }),
                  current.intent == expected else { throw AppAccessContractFailureV1.effectMismatch }
            try validateIngressPublication(current, hashPayload: true)
            let updated = try current.replacingIntent(replacement)
            let file = try ingressControlURL(expected.intentID, ".pending.json")
            try replaceIngressControlBytes(expected: CompatibilityCanonicalV1.encode(current),
                replacement: CompatibilityCanonicalV1.encode(updated), at: file)
            guard try readIngressControl(C16IngressPublicationV1.self, at: file) == updated else {
                throw AppAccessContractFailureV1.effectMismatch
            }
        }
    }

    private func replaceIngressControlBytes(expected: Data, replacement: Data, at file: URL) throws {
        try requireScratchDescriptorAccess()
        guard try readIngressControlFile(file, maximumBytes: 262_144) == expected else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        if expected == replacement { return }
        let temporary = file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + ".replacement")
        try writeProtectedIngressCanonical(replacement, to: temporary)
        guard try readIngressControlFile(file, maximumBytes: 262_144) == expected else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        let descriptor = try ingressControlDescriptor()
        guard Darwin.renameat(descriptor, temporary.lastPathComponent, descriptor, file.lastPathComponent) == 0,
              Darwin.fsync(descriptor) == 0,
              try readIngressControlFile(file, maximumBytes: 262_144) == replacement else {
            throw AppAccessContractFailureV1.effectMismatch
        }
    }

    func removeProtectedIngress(expected: PendingLockedExternalIntentV1, disposition: LockedIngressDispositionV1) throws {
        try requireScratchDescriptorAccess()
        try withProducerFilesystemLock {
            try expected.validate()
            guard disposition == .erased || (disposition == .expiredDeleted && clock() >= expected.expiresAt)
                || (disposition == .consumed && expected.disposition == .readyForAuthenticatedValidation) else {
                throw AppAccessContractFailureV1.invalidTransition
            }
            let file = try ingressControlURL(expected.intentID, ".terminal.json")
            if let recorded = try readIngressControl(C16IngressRemovalV1.self, at: file) {
                guard recorded.expected.intent == expected, recorded.disposition == disposition else {
                    throw AppAccessContractFailureV1.effectMismatch
                }
                try settleIngressRemoval(recorded)
                return
            }
            guard let current = try pendingIngressPublications().first(where: { $0.intent.intentID == expected.intentID }),
                  current.intent == expected else { throw AppAccessContractFailureV1.effectMismatch }
            let removal = C16IngressRemovalV1(expected: current, disposition: disposition)
            try removal.validate()
            try validateIngressPublication(current, hashPayload: false)
            try writeProtectedIngressCanonical(try CompatibilityCanonicalV1.encode(removal), to: file)
            try ingressMutationFailureInjection.interruptIfTriggered(.afterRemovalPrepare)
            try settleIngressRemoval(removal)
        }
    }

    private func settleIngressRemoval(_ removal: C16IngressRemovalV1,
                                      applyingEffects: Bool = true) throws {
        try requireScratchDescriptorAccess()
        if !applyingEffects {
            try validateIngressRemovalWithoutEffects(removal)
            return
        }
        try runC16SemanticSession(c16IngressRemovalSteps(removal))
    }

    private func validateIngressRemovalWithoutEffects(_ removal: C16IngressRemovalV1) throws {
        try requireScratchDescriptorAccess()
        try removal.validate()
        let value = removal.expected
        try validateIngressPreparation(value.claim.preparation, intentID: value.intent.intentID)
        let pending = try ingressControlURL(value.intent.intentID, ".pending.json")
        if let current = try readIngressControl(C16IngressPublicationV1.self, at: pending), current != value {
            throw AppAccessContractFailureV1.effectMismatch
        }
        let originalName = value.claim.preparation.lease.relativeDirectory
        let tombstone = Self.deletionTombstoneName(for: originalName)
        let original = try directoryInformationIfPresent(named: originalName)
        let deleting = try directoryInformationIfPresent(named: tombstone)
        if originalEraseBorrowedExclusiveCheck != nil, original != nil, deleting != nil {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        guard original != nil || deleting != nil else { return }
        let name = deleting == nil ? originalName : tombstone
        let descriptor = try openLeaseDirectory(name)
        try withObservedScratchDescriptor(descriptor) { descriptor in
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            var information = stat()
            guard Darwin.fstat(descriptor, &information) == 0,
                  UInt64(information.st_dev) == value.claim.device,
                  UInt64(information.st_ino) == value.claim.inode else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            try verifySourceReadPolicy(.stagingDirectory, at: rootURL.appendingPathComponent(name))
            let files = try ingressHygieneFileIdentities(name: name, descriptor: descriptor)
            let expected = [value.metadata, value.payload].sorted { $0.name < $1.name }
            let valid = deleting == nil ? files == expected
                : (originalEraseBorrowedExclusiveCheck != nil
                    ? files == Array(expected.suffix(files.count))
                    : files.allSatisfy({ expected.contains($0) }))
            guard valid else { throw AppAccessContractFailureV1.effectMismatch }
            try verifyLeaseDirectory(name, descriptor: descriptor)
        }
    }

    private func c16IngressRemovalSteps(_ removal: C16IngressRemovalV1) -> [C16SemanticStepV1] {
        [.plan { _ in
            try self.requireScratchDescriptorAccess()
            try self.validateIngressRemovalWithoutEffects(removal)
            let value = removal.expected
            var steps = self.c16OwnedTargetSteps(originalName: value.claim.preparation.lease.relativeDirectory,
                device: value.claim.device, inode: value.claim.inode,
                files: [value.metadata, value.payload].sorted { $0.name < $1.name })
            steps.append(.effect {
                if self.active[value.intent.intentID] == value.claim.preparation.lease {
                    self.active.removeValue(forKey: value.intent.intentID)
                }
                try self.ingressMutationFailureInjection.interruptIfTriggered(.afterRemovalEffect)
            })
            steps.append(.plan { _ in
                let pending = try self.ingressControlURL(value.intent.intentID, ".pending.json")
                guard try self.ingressControlFileExists(pending) else { return [] }
                return [.effect {
                    guard try self.readIngressControl(C16IngressPublicationV1.self, at: pending) == value else {
                        throw AppAccessContractFailureV1.effectMismatch
                    }
                    let descriptor = try self.ingressControlDescriptor()
                    guard Darwin.unlinkat(descriptor, pending.lastPathComponent, 0) == 0,
                          Darwin.fsync(descriptor) == 0 else {
                        throw AppAccessContractFailureV1.configurationUnknown
                    }
                }]
            })
            return steps
        }]
    }

    private func makeUnpublishedIngressEraseTarget(
        _ preparation: C16IngressPreparedStageV1
    ) throws -> C16IngressUnpublishedEraseTargetV1 {
        try requireScratchDescriptorAccess()
        let id = preparation.intent.intentID
        try validateIngressPreparation(preparation, intentID: id)
        for suffix in [".published.json", ".pending.json", ".terminal.json", ".aborted.json"] {
            guard try !ingressControlFileExists(ingressControlURL(id, suffix)) else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        }
        if originalEraseBorrowedExclusiveCheck != nil,
           let claim = try readIngressControl(C16IngressDirectoryClaimV1.self,
               at: ingressControlURL(id, ".claim.json")) {
            return try originalEraseC16ClaimOnlySource(preparation: preparation, claim: claim)
        }
        let name = preparation.lease.relativeDirectory
        guard try directoryInformationIfPresent(named: Self.deletionTombstoneName(for: name)) == nil else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        guard let claim = try readIngressControl(C16IngressDirectoryClaimV1.self,
            at: ingressControlURL(id, ".claim.json")) else {
            guard try directoryInformationIfPresent(named: name) == nil else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            return .init(preparation: preparation, directory: nil)
        }
        guard claim.preparation == preparation else { throw AppAccessContractFailureV1.configurationUnknown }
        let descriptor = try validateIngressClaim(claim)
        return try withObservedScratchDescriptor(descriptor) { descriptor in
        let children = try directoryNames(descriptor)
        guard children.count <= 128, children.allSatisfy({ child in
            if child == Self.metadataName || child == "opaque-data" { return true }
            guard child.hasPrefix(".partial-") else { return false }
            let raw = String(child.dropFirst(".partial-".count))
            return UUID(uuidString: raw)?.uuidString.lowercased() == raw
        }) else { throw AppAccessContractFailureV1.configurationUnknown }
        try removeInterruptedPublications(directoryDescriptor: descriptor)
        let files = try ingressHygieneFileIdentities(name: name, descriptor: descriptor)
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              UInt64(information.st_dev) == claim.device, UInt64(information.st_ino) == claim.inode else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let modified = Date(timeIntervalSince1970: TimeInterval(information.st_mtimespec.tv_sec)
            + TimeInterval(information.st_mtimespec.tv_nsec) / 1_000_000_000)
        let directory = try C16IngressHygieneTargetV1(directoryName: name, modifiedAt: modified,
            information: information, files: files)
        let target = C16IngressUnpublishedEraseTargetV1(preparation: preparation, directory: directory)
        try target.validate()
        guard target.claim == claim else { throw AppAccessContractFailureV1.configurationUnknown }
        return target
        }
    }

    private func validateAbortedIngress(
        _ aborted: C16IngressAbortedStageV1,
        preparation: C16IngressPreparedStageV1,
        claim: C16IngressDirectoryClaimV1?
    ) throws {
        try requireScratchDescriptorAccess()
        try aborted.validate()
        try validateIngressPreparation(preparation, intentID: preparation.intent.intentID)
        guard aborted.expected.preparation == preparation, aborted.expected.claim == claim else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let file = try protectedIngressReceiptDirectory().appendingPathComponent(
            "erase-" + aborted.operationID.uuidString.lowercased() + ".prepare.json")
        guard let erase = try readIngressControl(C16IngressEraseV1.self, at: file) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try erase.validate()
        guard erase.operationID == aborted.operationID, erase.rootDevice == authority.rootDevice,
              erase.rootInode == authority.rootInode, erase.unpublishedTargets.contains(aborted.expected) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
    }

    private func removeUnpublishedIngress(_ target: C16IngressUnpublishedEraseTargetV1, operationID: UUID) throws {
        try requireScratchDescriptorAccess()
        try runC16SemanticSession(c16UnpublishedRemovalSteps(target, operationID: operationID))
    }

    private func c16UnpublishedRemovalSteps(_ target: C16IngressUnpublishedEraseTargetV1,
                                            operationID: UUID) -> [C16SemanticStepV1] {
        [.plan { [self] _ in
        try target.validate()
        let id = target.preparation.intent.intentID
        guard let preparation = try readIngressControl(C16IngressPreparedStageV1.self,
            at: ingressControlURL(id, ".prepare.json")), preparation == target.preparation else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try validateIngressPreparation(preparation, intentID: id)
        let claim = try readIngressControl(C16IngressDirectoryClaimV1.self, at: ingressControlURL(id, ".claim.json"))
        guard claim == target.claim else { throw AppAccessContractFailureV1.configurationUnknown }
        for suffix in [".published.json", ".pending.json", ".terminal.json"] {
            guard try !ingressControlFileExists(ingressControlURL(id, suffix)) else {
                throw AppAccessContractFailureV1.effectMismatch
            }
        }
        let file = try ingressControlURL(id, ".aborted.json")
        let aborted = C16IngressAbortedStageV1(operationID: operationID, expected: target)
        if let recorded = try readIngressControl(C16IngressAbortedStageV1.self, at: file) {
            guard recorded == aborted else { throw AppAccessContractFailureV1.effectMismatch }
            try validateAbortedIngress(recorded, preparation: preparation, claim: claim)
            return []
        }
        var work: [C16SemanticStepV1] = []
        if let directory = target.directory {
            work += c16PreparedTargetSteps(directory)
        } else {
            let name = preparation.lease.relativeDirectory
            guard try directoryInformationIfPresent(named: name) == nil,
                  try directoryInformationIfPresent(named: Self.deletionTombstoneName(for: name)) == nil else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        }
        work.append(.effect { [self] in
            try ingressMutationFailureInjection.interruptIfTriggered(.afterUnpublishedRemoval)
        })
        work.append(.plan { [self] _ in
            try c16PublicationSteps(CompatibilityCanonicalV1.encode(aborted), to: file)
        })
        work.append(.effect { [self] in
            guard try readIngressControl(C16IngressAbortedStageV1.self, at: file) == aborted else {
                throw AppAccessContractFailureV1.effectMismatch
            }
        })
        return work
        }]
    }

    func eraseProtectedIngress(operationID: UUID) throws {
        try requireScratchDescriptorAccess()
        try withProducerFilesystemLock {
            try runC16SemanticSession(c16EraseIngressSteps(operationID: operationID))
        }
    }

    private func c16EraseIngressSteps(operationID: UUID) -> [C16SemanticStepV1] {
        [.plan { [self] _ in
            guard operationID != SettingsValidationV1.zeroUUID else { throw AppAccessContractFailureV1.invalidValue }
            let directory = try protectedIngressReceiptDirectory()
            let file = directory.appendingPathComponent("erase-" + operationID.uuidString.lowercased() + ".prepare.json")
            let complete = directory.appendingPathComponent("erase-" + operationID.uuidString.lowercased() + ".complete.json")
            let erase: C16IngressEraseV1
            let resumedErase: C16IngressEraseV1?
            var work: [C16SemanticStepV1] = []
            if let existing = try readIngressControl(C16IngressEraseV1.self, at: file) {
                try existing.validate()
                guard existing.operationID == operationID, existing.rootDevice == authority.rootDevice,
                      existing.rootInode == authority.rootInode else { throw AppAccessContractFailureV1.configurationUnknown }
                erase = existing
                resumedErase = existing
            } else {
                guard try !ingressControlFileExists(complete) else { throw AppAccessContractFailureV1.configurationUnknown }
                _ = try validatedIngressSnapshot(applyingRecoveryEffects: false)
                let entry = try validatedIngressSnapshot(applyingRecoveryEffects: originalEraseBorrowedExclusiveCheck == nil)
                let published: [C16IngressPublicationV1]
                let unfinished: [C16IngressPreparedStageV1]
                if originalEraseBorrowedExclusiveCheck != nil {
                    guard let plan = originalEraseC16ReferencePlan,
                          operationID == originalEraseOperationID,
                          let ordinal = originalEraseC16CurrentOrdinal,
                          plan.steps[ordinal] == .eraseIngress,
                          entry.pending.map({ $0.intent.intentID }) == plan.freshPublishedTargets.map(\.intentID) else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                    published = try plan.freshPublishedTargets.map { reference in
                        guard let value = entry.pending.first(where: { $0.intent.intentID == reference.intentID }),
                              reference.directory == OriginalEraseC16TargetFactV1(value) else {
                            throw ScratchDataLeaseStoreFailureV1.leaseCollision
                        }
                        return value
                    }
                    unfinished = try plan.freshUnpublishedTargets.map { reference in
                        guard let value = entry.unresolvedPreparations.first(where: {
                            $0.intent.intentID == reference.intentID
                        }) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                        return value
                    }
                    guard Set(entry.unresolvedPreparations.map({ $0.intent.intentID }))
                        == Set(published.map({ $0.intent.intentID }) + unfinished.map({ $0.intent.intentID })) else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                } else {
                    published = entry.pending
                    let publishedIDs = Set(published.map { $0.intent.intentID })
                    unfinished = entry.unresolvedPreparations.filter { !publishedIDs.contains($0.intent.intentID) }
                }
                erase = .init(operationID: operationID, rootDevice: authority.rootDevice, rootInode: authority.rootInode,
                    targets: published, unpublishedTargets: try unfinished.map(makeUnpublishedIngressEraseTarget))
                try erase.validate()
                if let plan = originalEraseC16ReferencePlan {
                    guard erase.unpublishedTargets.map({ target in
                        OriginalEraseC16PlannedTargetV1(intentID: target.preparation.intent.intentID,
                            directory: target.directory.map(OriginalEraseC16TargetFactV1.init))
                    }) == plan.freshUnpublishedTargets else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                }
                work += try c16PublicationSteps(CompatibilityCanonicalV1.encode(erase), to: file)
                work.append(.effect { [self] in try ingressMutationFailureInjection.interruptIfTriggered(.afterErasePrepare) })
                resumedErase = nil
            }
            work.append(.plan { [self] _ in
                if let recorded = try readIngressControl(C16IngressEraseV1.self, at: complete) {
                    guard recorded == erase else { throw AppAccessContractFailureV1.effectMismatch }
                    return []
                }
                _ = try validatedIngressSnapshot(frozenErase: resumedErase, applyingRecoveryEffects: false)
                _ = try validatedIngressSnapshot(frozenErase: resumedErase,
                    applyingRecoveryEffects: originalEraseBorrowedExclusiveCheck == nil)
                var effects = erase.unpublishedTargets.flatMap { c16UnpublishedRemovalSteps($0, operationID: operationID) }
                effects += erase.targets.flatMap(c16FrozenIngressTargetSteps)
                effects.append(.plan { [self] _ in
                    _ = try validatedIngressSnapshot(applyingRecoveryEffects: originalEraseBorrowedExclusiveCheck == nil)
                    return try c16PublicationSteps(CompatibilityCanonicalV1.encode(erase), to: complete)
                })
                effects.append(.effect { [self] in
                    guard try readIngressControl(C16IngressEraseV1.self, at: complete) == erase else {
                        throw AppAccessContractFailureV1.effectMismatch
                    }
                })
                return effects
            })
            return work
        }]
    }

    /// Settles one target from an already durable erase record. This helper is
    /// called only while eraseProtectedIngress holds filesystemLock after a
    /// complete root admission. It never supplies a cache to another operation.
    private func removeFrozenIngressTarget(_ target: C16IngressPublicationV1) throws {
        try requireScratchDescriptorAccess()
        try runC16SemanticSession(c16FrozenIngressTargetSteps(target))
    }

    private func c16FrozenIngressTargetSteps(_ target: C16IngressPublicationV1) -> [C16SemanticStepV1] {
        [.plan { [self] _ in
        try target.validate()
        let id = target.intent.intentID
        let prepareFile = try ingressControlURL(id, ".prepare.json")
        let claimFile = try ingressControlURL(id, ".claim.json")
        let publishedFile = try ingressControlURL(id, ".published.json")
        let pendingFile = try ingressControlURL(id, ".pending.json")
        let terminalFile = try ingressControlURL(id, ".terminal.json")
        let abortedFile = try ingressControlURL(id, ".aborted.json")
        guard try readIngressControl(C16IngressPreparedStageV1.self, at: prepareFile)
                == target.claim.preparation,
              try readIngressControl(C16IngressDirectoryClaimV1.self, at: claimFile) == target.claim,
              let published = try readIngressControl(C16IngressPublicationV1.self, at: publishedFile),
              try readIngressControl(C16IngressAbortedStageV1.self, at: abortedFile) == nil else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        try published.validate()
        guard published.claim == target.claim,
              published.intent == target.claim.preparation.intent,
              try published.replacingIntent(target.intent) == target else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        let removal = C16IngressRemovalV1(expected: target, disposition: .erased)
        try removal.validate()
        if let terminal = try readIngressControl(C16IngressRemovalV1.self, at: terminalFile) {
            try terminal.validate()
            guard terminal == removal else { throw AppAccessContractFailureV1.effectMismatch }
            return c16IngressRemovalSteps(terminal)
        }
        guard try readIngressControl(C16IngressPublicationV1.self, at: pendingFile) == target else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        if originalEraseBorrowedExclusiveCheck != nil {
            let recipe = try originalEraseC16IngressRecipe(for: target)
            if !recipe.hygiene.isEmpty {
                guard recipe.removal == removal else {
                    throw AppAccessContractFailureV1.effectMismatch
                }
                try validatePreparedIngressTargetForRecovery(recipe.hygiene[0])
            } else {
                try validateIngressPublication(target, hashPayload: false)
            }
        } else {
            try validateIngressPublication(target, hashPayload: false)
        }
        var work = try c16PublicationSteps(CompatibilityCanonicalV1.encode(removal), to: terminalFile)
        work.append(.effect { [self] in
            guard try readIngressControl(C16IngressRemovalV1.self, at: terminalFile) == removal else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            try ingressMutationFailureInjection.interruptIfTriggered(.afterRemovalPrepare)
        })
        work += c16IngressRemovalSteps(removal)
        return work
        }]
    }

    private func ingressControlURL(_ intentID: UUID, _ suffix: String) throws -> URL {
        try requireScratchDescriptorAccess()
        guard intentID != SettingsValidationV1.zeroUUID else { throw AppAccessContractFailureV1.invalidValue }
        return try protectedIngressReceiptDirectory().appendingPathComponent(
            try ingressControlName(intentID, suffix))
    }

    private func ingressControlName(_ intentID: UUID, _ suffix: String) throws -> String {
        try requireScratchDescriptorAccess()
        guard intentID != SettingsValidationV1.zeroUUID,
              [".prepare.json", ".claim.json", ".published.json", ".pending.json",
               ".terminal.json", ".aborted.json"].contains(suffix) else {
            throw AppAccessContractFailureV1.invalidValue
        }
        return "ingress-" + intentID.uuidString.lowercased() + suffix
    }

    private func readIngressControl<Value: Codable>(_ type: Value.Type, at file: URL) throws -> Value? {
        try requireScratchDescriptorAccess()
        guard try ingressControlFileExists(file) else { return nil }
        return try CompatibilityCanonicalV1.decode(type, from: readIngressControlFile(file, maximumBytes: 262_144))
    }

    private func beginIngressControlInventory() throws -> C16IngressControlInventoryV1 {
        try requireScratchDescriptorAccess()
        let descriptor = try ingressControlDescriptor()
        observeIngressControlInventoryForTesting()
        let names = try directoryNames(descriptor)
        return .init(descriptor: descriptor, expectedNames: Set(names))
    }

    private func finishIngressControlInventory(
        _ inventory: inout C16IngressControlInventoryV1
    ) throws {
        try requireScratchDescriptorAccess()
        try mutateBeforeIngressControlFinalInventoryForTesting()
        _ = try protectedIngressReceiptDirectory()
        observeIngressControlInventoryForTesting()
        let finalNames = try directoryNames(inventory.descriptor)
        // This proves exact membership only. Each descriptor-local read above
        // retains the existing before/after file identity and metadata checks.
        guard Set(finalNames) == inventory.expectedNames else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        _ = try protectedIngressReceiptDirectory()
    }

    private func readIngressControl<Value: Codable>(
        _ type: Value.Type,
        at file: URL,
        inventory: inout C16IngressControlInventoryV1
    ) throws -> Value? {
        try requireScratchDescriptorAccess()
        guard file.deletingLastPathComponent() == (try protectedIngressReceiptDirectory()) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let name = file.lastPathComponent
        guard inventory.expectedNames.contains(name) else { return nil }
        let data = try readIngressControlFile(file, maximumBytes: 262_144)
        try verifySourceReadPolicy(.temporaryFile, at: file)
        _ = try protectedIngressReceiptDirectory()
        return try CompatibilityCanonicalV1.decode(type, from: data)
    }

    private func observeIngressControlInventoryForTesting() {
        #if DEBUG
        ingressControlInventoryObserver()
        #endif
    }

    private func mutateBeforeIngressControlFinalInventoryForTesting() throws {
        try requireScratchDescriptorAccess()
        #if DEBUG
        try beforeIngressControlFinalInventory()
        #endif
    }

    private func validateIngressPreparation(_ value: C16IngressPreparedStageV1, intentID: UUID) throws {
        try requireScratchDescriptorAccess()
        try verifyRoot()
        try value.validate()
        guard value.intent.intentID == intentID, value.rootDevice == authority.rootDevice,
              value.rootInode == authority.rootInode else { throw AppAccessContractFailureV1.configurationUnknown }
    }

    private func ingressPreparations(
        inventory: inout C16IngressControlInventoryV1
    ) throws -> [C16IngressPreparedStageV1] {
        try requireScratchDescriptorAccess()
        let names = inventory.expectedNames.sorted()
        guard names.count <= 100_000 else { throw AppAccessContractFailureV1.configurationUnknown }
        var ids = Set<UUID>()
        var eraseIDs = Set<UUID>()
        let suffixes = [".prepare.json", ".claim.json", ".published.json", ".pending.json",
                        ".pending.json.replacement", ".terminal.json", ".aborted.json"]
        for name in names {
            if name.hasPrefix("ingress-") {
                ids.insert(try ingressControlIdentifier(name, prefix: "ingress-", suffixes: suffixes))
            } else if name.hasPrefix("erase-") {
                eraseIDs.insert(try ingressControlIdentifier(name, prefix: "erase-", suffixes: [".prepare.json", ".complete.json"]))
            } else if name.hasPrefix("hygiene-") {
                _ = try ingressControlIdentifier(name, prefix: "hygiene-", suffixes: [".prepare.json.finalizing", ".prepare.json", ".json"])
            } else if name.hasPrefix(".partial-") {
                _ = try ingressControlIdentifier(name, prefix: ".partial-", suffixes: [""])
            } else { throw AppAccessContractFailureV1.configurationUnknown }
        }
        for id in eraseIDs {
            let file = try protectedIngressReceiptDirectory().appendingPathComponent("erase-" + id.uuidString.lowercased() + ".prepare.json")
            guard let value = try readIngressControl(C16IngressEraseV1.self, at: file,
                inventory: &inventory) else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            try value.validate()
            guard value.operationID == id, value.rootDevice == authority.rootDevice, value.rootInode == authority.rootInode else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            let complete = try protectedIngressReceiptDirectory().appendingPathComponent("erase-" + id.uuidString.lowercased() + ".complete.json")
            if let recorded = try readIngressControl(C16IngressEraseV1.self, at: complete,
                inventory: &inventory), recorded != value {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        }
        return try ids.sorted { $0.uuidString < $1.uuidString }.map { id in
            guard let value = try readIngressControl(C16IngressPreparedStageV1.self,
                at: ingressControlURL(id, ".prepare.json"), inventory: &inventory) else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            try validateIngressPreparation(value, intentID: id)
            return value
        }
    }

    private func ingressPreparations() throws -> [C16IngressPreparedStageV1] {
        try requireScratchDescriptorAccess()
        var inventory = try beginIngressControlInventory()
        let result = try ingressPreparations(inventory: &inventory)
        try finishIngressControlInventory(&inventory)
        return result
    }

    private func ingressControlIdentifier(_ name: String, prefix: String, suffixes: [String]) throws -> UUID {
        try requireScratchDescriptorAccess()
        guard name.hasPrefix(prefix), let suffix = suffixes.first(where: { name.hasSuffix($0) }) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let raw = String(name.dropFirst(prefix.count).dropLast(suffix.count))
        guard let id = UUID(uuidString: raw), id.uuidString.lowercased() == raw,
              id != SettingsValidationV1.zeroUUID else { throw AppAccessContractFailureV1.configurationUnknown }
        return id
    }

    private func hasExistingIngressControl() throws -> Bool {
        try requireScratchDescriptorAccess()
        try verifyRoot()
        var information = stat()
        if Darwin.fstatat(authority.operationsDescriptor, "ProtectedIngressReceiptsV1", &information, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT, ingressControlAuthority == nil else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            return false
        }
        guard (information.st_mode & S_IFMT) == S_IFDIR else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        _ = try protectedIngressReceiptDirectory()
        return true
    }

    private func resumeIngressErasesForScratchLifecycle() throws {
        try requireScratchDescriptorAccess()
        guard try hasExistingIngressControl() else { return }
        _ = try ingressPreparations()
        for name in try directoryNames(ingressControlDescriptor())
        where name.hasPrefix("erase-") && name.hasSuffix(".prepare.json") {
            let id = try ingressControlIdentifier(name, prefix: "erase-", suffixes: [".prepare.json"])
            let complete = try protectedIngressReceiptDirectory().appendingPathComponent("erase-" + id.uuidString.lowercased() + ".complete.json")
            if try !ingressControlFileExists(complete) { try eraseProtectedIngress(operationID: id) }
        }
        _ = try pendingIngressPublications()
    }

    private func eraseUnpublishedIngressForScratchLifecycle(_ target: C16IngressUnpublishedEraseTargetV1) throws {
        try requireScratchDescriptorAccess()
        let operationID: UUID
        if let originalEraseOperationID {
            // The sidecar's preparing transition binds this exact derived
            // marker name before publication. A fresh process can then find
            // only this original operation's unpublished-ingress erase.
            operationID = try originalEraseDerivedIngressOperationID(
                eraseID: originalEraseOperationID,
                intentID: target.preparation.intent.intentID)
        } else {
            operationID = UUID()
        }
        let erase = C16IngressEraseV1(operationID: operationID, rootDevice: authority.rootDevice,
            rootInode: authority.rootInode, targets: [], unpublishedTargets: [target])
        try erase.validate()
        let file = try protectedIngressReceiptDirectory().appendingPathComponent("erase-" + operationID.uuidString.lowercased() + ".prepare.json")
        try writeProtectedIngressCanonical(try CompatibilityCanonicalV1.encode(erase), to: file)
        try eraseProtectedIngress(operationID: operationID)
    }

    private func originalEraseDerivedIngressOperationID(
        eraseID: UUID, intentID: UUID
    ) throws -> UUID {
        try requireScratchDescriptorAccess()
        let input = Data((eraseID.uuidString.lowercased() + "|" +
            intentID.uuidString.lowercased()).utf8)
        let hex = SHA256.hash(data: input).map {
            String(format: "%02x", $0)
        }.joined()
        let raw = String(hex.prefix(32))
        let groups = [8, 4, 4, 4, 12]
        var cursor = raw.startIndex
        var pieces: [String] = []
        for width in groups {
            let end = raw.index(cursor, offsetBy: width)
            pieces.append(String(raw[cursor..<end]))
            cursor = end
        }
        guard let value = UUID(uuidString: pieces.joined(separator: "-")),
              value != SettingsValidationV1.zeroUUID else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        return value
    }

    private func recoverUnpublishedIngressForScratchLifecycle() throws -> (retainedNames: Set<String>, expiredCount: Int, removedBytes: UInt64) {
        try requireScratchDescriptorAccess()
        guard try hasExistingIngressControl() else { return ([], 0, 0) }
        try resumeIngressErasesForScratchLifecycle()
        var retainedNames = Set<String>()
        var expiredCount = 0
        var removedBytes: UInt64 = 0
        for preparation in try ingressPreparations() {
            let id = preparation.intent.intentID
            if try ingressControlFileExists(ingressControlURL(id, ".published.json"))
                || ingressControlFileExists(ingressControlURL(id, ".aborted.json")) { continue }
            let target = try makeUnpublishedIngressEraseTarget(preparation)
            if clock() < preparation.intent.expiresAt {
                if let directory = target.directory { retainedNames.insert(directory.directoryName) }
                continue
            }
            var bytes: UInt64 = 0
            for file in target.directory?.files ?? [] {
                let sum = bytes.addingReportingOverflow(UInt64(file.byteCount))
                guard !sum.overflow else { throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded }
                bytes = sum.partialValue
            }
            let sum = removedBytes.addingReportingOverflow(bytes)
            guard !sum.overflow else { throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded }
            try eraseUnpublishedIngressForScratchLifecycle(target)
            if target.directory != nil { expiredCount += 1; removedBytes = sum.partialValue }
        }
        return (retainedNames, expiredCount, removedBytes)
    }

    private func resumePreparedScratchHygiene() throws {
        try requireScratchDescriptorAccess()
        guard try hasExistingIngressControl() else { return }
        _ = try ingressPreparations()
        let directory = try protectedIngressReceiptDirectory()
        let names = try directoryNames(ingressControlDescriptor())
        for name in names where name.hasPrefix("hygiene-") && name.hasSuffix(".prepare.json") {
            let prepare = try readProtectedIngressPrepare(at: directory.appendingPathComponent(name))
            _ = try reconcileProtectedIngressHygiene(now: prepare.request.requestedAt,
                operationID: prepare.request.operationID, minimumAge: prepare.request.minimumAge)
        }
    }

    private func requireNoUnfinishedHygieneTarget(named name: String) throws {
        try requireScratchDescriptorAccess()
        guard try hasExistingIngressControl() else { return }
        let directory = try protectedIngressReceiptDirectory()
        for fileName in try directoryNames(ingressControlDescriptor())
        where fileName.hasPrefix("hygiene-") && fileName.hasSuffix(".prepare.json") {
            let prepare = try readProtectedIngressPrepare(at: directory.appendingPathComponent(fileName))
            guard prepare.finalized || !prepare.targets.contains(where: { $0.directoryName == name }) else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        }
    }

    private func removeIngressScratchLeaseIfOwned(
        named name: String, expectedLease: ScratchDataLeaseV1? = nil
    ) throws -> Bool {
        try requireScratchDescriptorAccess()
        guard try hasExistingIngressControl() else { return false }
        guard let preparation = try ingressPreparations().first(where: { $0.lease.relativeDirectory == name }) else { return false }
        if let expectedLease, preparation.lease != expectedLease {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let values = try pendingIngressPublications()
        if let value = values.first(where: { $0.claim.preparation == preparation }) {
            try removeProtectedIngress(expected: value.intent,
                disposition: clock() >= value.intent.expiresAt ? .expiredDeleted : .erased)
        } else {
            let id = preparation.intent.intentID
            if try ingressControlFileExists(ingressControlURL(id, ".terminal.json"))
                || ingressControlFileExists(ingressControlURL(id, ".aborted.json")) {
                guard try directoryInformationIfPresent(named: name) == nil,
                      try directoryInformationIfPresent(named: Self.deletionTombstoneName(for: name)) == nil else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
            } else {
                try eraseUnpublishedIngressForScratchLifecycle(makeUnpublishedIngressEraseTarget(preparation))
            }
        }
        return true
    }

    private func validateIngressControlSnapshotName(_ name: String) throws {
        try requireScratchDescriptorAccess()
        if name.hasPrefix("ingress-") {
            _ = try ingressControlIdentifier(name, prefix: "ingress-", suffixes:
                [".prepare.json", ".claim.json", ".published.json", ".pending.json", ".pending.json.replacement", ".terminal.json", ".aborted.json"])
        } else if name.hasPrefix("erase-") {
            _ = try ingressControlIdentifier(name, prefix: "erase-", suffixes: [".prepare.json", ".complete.json"])
        } else if name.hasPrefix("hygiene-") {
            _ = try ingressControlIdentifier(name, prefix: "hygiene-", suffixes: [".prepare.json.finalizing", ".prepare.json", ".json"])
        } else { throw AppAccessContractFailureV1.configurationUnknown }
    }

    /// The marker is written only after all ingress effects have terminated.
    /// It remains until every original control file has been removed, so a
    /// partial deletion never needs to decode an incomplete receipt graph.
    private func eraseScratchIngressControl(resumeOnly: Bool,
        capturedMarkerPublication: Bool = false) throws {
        try requireScratchDescriptorAccess()
        try runC16SemanticSession(c16ControlEraseSteps(resumeOnly: resumeOnly,
            capturedMarkerPublication: capturedMarkerPublication))
    }

    private func c16ControlRootRemovalSteps(_ pinned: PinnedScratchRootV1) -> [C16SemanticStepV1] {
        [.effect { [self] in
            try self.requireScratchDescriptorAccess()
            try pinned.verify(rootName: "ProtectedIngressReceiptsV1")
            guard try directoryNames(pinned.rootDescriptor).isEmpty,
                  Darwin.unlinkat(authority.operationsDescriptor, "ProtectedIngressReceiptsV1", AT_REMOVEDIR) == 0,
                  Darwin.fsync(authority.operationsDescriptor) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            if originalEraseBorrowedExclusiveCheck != nil {
                try originalEraseBorrowedExclusiveCheck?()
                var named = stat()
                guard Darwin.fstatat(authority.operationsDescriptor, "ProtectedIngressReceiptsV1",
                    &named, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                originalEraseControlRemovalProved = true
            } else { ingressControlAuthority = nil }
        }]
    }

    private struct OriginalEraseC16CanonicalRoleV1 {
        let role: String
        let bytes: Data
    }

    private func originalEraseC16FixedFreshEraseMarker(
        plan: OriginalEraseC16PlanV1
    ) throws -> C16IngressEraseV1 {
        try requireScratchDescriptorAccess()
        guard let operationID = originalEraseOperationID else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        let name = "erase-" + operationID.uuidString.lowercased() + ".prepare.json"
        if let born = originalEraseC16BornSourceInputs["freshIngressErasePrepare|" + name] {
            let marker = try CompatibilityCanonicalV1.decode(C16IngressEraseV1.self, from: born.bytes)
            try marker.validate()
            guard marker.operationID == operationID, marker.rootDevice == authority.rootDevice,
                  marker.rootInode == authority.rootInode,
                  marker.targets.map({ OriginalEraseC16PlannedTargetV1(intentID: $0.intent.intentID, directory: .init($0)) }) == plan.freshPublishedTargets,
                  marker.unpublishedTargets.map({ OriginalEraseC16PlannedTargetV1(intentID: $0.preparation.intent.intentID,
                    directory: $0.directory.map(OriginalEraseC16TargetFactV1.init)) }) == plan.freshUnpublishedTargets,
                  try CompatibilityCanonicalV1.encode(marker) == born.bytes else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            return marker
        }
        let published = try plan.freshPublishedTargets.map { target -> C16IngressPublicationV1 in
            let value = try originalEraseC16FixedIngressRecipeData(intentID: target.intentID).expected
            guard target.directory == OriginalEraseC16TargetFactV1(value) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            return value
        }
        let unpublished = try plan.freshUnpublishedTargets.map { target -> C16IngressUnpublishedEraseTargetV1 in
            let preparation = try originalEraseC16ReferenceValue(C16IngressPreparedStageV1.self,
                name: ingressControlName(target.intentID, ".prepare.json"))
            if target.directory == nil {
                guard originalEraseC16SourceInputs[try ingressControlName(target.intentID, ".claim.json")] == nil else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                return .init(preparation: preparation, directory: nil)
            }
            let claim = try originalEraseC16ReferenceValue(C16IngressDirectoryClaimV1.self,
                name: ingressControlName(target.intentID, ".claim.json"))
            let value = try originalEraseC16ClaimOnlySource(preparation: preparation, claim: claim)
            guard value.directory.map(OriginalEraseC16TargetFactV1.init) == target.directory else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            return value
        }
        let value = C16IngressEraseV1(operationID: operationID, rootDevice: authority.rootDevice,
            rootInode: authority.rootInode, targets: published, unpublishedTargets: unpublished)
        try value.validate(); return value
    }

    /// Exact canonical outputs of the sole semantic engine through this
    /// ordinal. This selects fixed roles, never currently surviving IDs.
    private func originalEraseC16CanonicalRoles(
        plan: OriginalEraseC16PlanV1, through ordinal: Int
    ) throws -> [String: OriginalEraseC16CanonicalRoleV1] {
        try requireScratchDescriptorAccess()
        guard ordinal >= 0, ordinal < plan.steps.count else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        var roles: [String: OriginalEraseC16CanonicalRoleV1] = [:]
        func add<Value: Encodable>(_ value: Value, name: String, role: String) throws {
            let bytes = try CompatibilityCanonicalV1.encode(value)
            guard bytes.count <= Self.originalEraseC16SourceMaximum(name: name) else {
                throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
            }
            if let existing = roles[name], existing.bytes != bytes {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            roles[name] = .init(role: role, bytes: bytes)
        }
        func addErase(_ marker: C16IngressEraseV1) throws {
            try add(marker, name: "erase-" + marker.operationID.uuidString.lowercased() + ".complete.json", role: "ingressEraseComplete")
            for target in marker.targets {
                try add(C16IngressRemovalV1(expected: target, disposition: .erased),
                    name: ingressControlName(target.intent.intentID, ".terminal.json"), role: "ingressTerminal")
            }
            for target in marker.unpublishedTargets {
                try add(C16IngressAbortedStageV1(operationID: marker.operationID, expected: target),
                    name: ingressControlName(target.preparation.intent.intentID, ".aborted.json"), role: "ingressAborted")
            }
        }
        for index in 0...ordinal {
            switch plan.steps[index] {
            case .settleFirstPPartial, .resumeControlTail, .eraseFinalControl: break
            case let .resumeHygiene(operationID):
                let name = "hygiene-" + operationID.uuidString.lowercased() + ".prepare.json"
                let prepare = try originalEraseC16ReferenceValue(C16IngressHygienePrepareV1.self, name: name)
                try add(prepare.receipt(), name: "hygiene-" + operationID.uuidString.lowercased() + ".json", role: "hygieneReceipt")
                try add(prepare.finalizing(), name: name + ".finalizing", role: "hygieneFinalizing")
                try add(prepare.finalizing(), name: name, role: "finalizedHygienePrepare")
                for binding in plan.markerBindings where binding.name.hasPrefix("ingress-") && binding.name.hasSuffix(".published.json") {
                    let published = try originalEraseC16ReferenceValue(C16IngressPublicationV1.self, name: binding.name)
                    let recipe = try originalEraseC16FixedIngressRecipeData(intentID: published.intent.intentID)
                    if recipe.terminalBeforeHygieneOrdinal == index, let removal = recipe.removal {
                        try add(removal, name: ingressControlName(published.intent.intentID, ".terminal.json"), role: "ingressTerminal")
                    }
                }
            case let .resumeIngressErase(operationID):
                let marker = try originalEraseC16ReferenceValue(C16IngressEraseV1.self,
                    name: "erase-" + operationID.uuidString.lowercased() + ".prepare.json")
                try addErase(marker)
            case let .recoverIngressPointer(intentID):
                let recipe = try originalEraseC16FixedIngressRecipeData(intentID: intentID)
                if let removal = recipe.removal {
                    try add(removal, name: ingressControlName(intentID, ".terminal.json"), role: "ingressTerminal")
                } else {
                    try add(recipe.expected, name: ingressControlName(intentID, ".pending.json"), role: "ingressPending")
                }
            case .eraseIngress:
                let marker = try originalEraseC16FixedFreshEraseMarker(plan: plan)
                try add(marker, name: "erase-" + marker.operationID.uuidString.lowercased() + ".prepare.json", role: "freshIngressErasePrepare")
                try addErase(marker)
            }
        }
        return roles
    }

    private func originalEraseC16MayConsumePending(id: UUID, plan: OriginalEraseC16PlanV1, through ordinal: Int) throws -> Bool {
        try requireScratchDescriptorAccess()
        for index in 0...ordinal {
            switch plan.steps[index] {
            case let .recoverIngressPointer(intentID) where intentID == id:
                if try originalEraseC16FixedIngressRecipeData(intentID: id).removal != nil { return true }
            case let .resumeIngressErase(operationID):
                let marker = try originalEraseC16ReferenceValue(C16IngressEraseV1.self,
                    name: "erase-" + operationID.uuidString.lowercased() + ".prepare.json")
                if marker.targets.contains(where: { $0.intent.intentID == id }) { return true }
            case .eraseIngress: if plan.freshPublishedTargets.contains(where: { $0.intentID == id }) { return true }
            default: break
            }
        }
        return false
    }

    @MainActor private func originalEraseC16MaterializedControlRole(
        plan: OriginalEraseC16PlanV1, ordinal: Int
    ) throws -> OriginalEraseC16CanonicalRoleV1? {
        try requireScratchDescriptorAccess()
        let step = plan.steps[ordinal]
        guard step == .eraseFinalControl || step == .resumeControlTail else { return nil }
        if let source = originalEraseC16SourceInputs[Self.controlEraseName] {
            return .init(role: "scratchControlErase", bytes: source.bytes)
        }
        if let born = originalEraseC16BornSourceInputs["scratchControlErase|" + Self.controlEraseName] {
            return .init(role: "scratchControlErase", bytes: born.bytes)
        }
        guard try hasExistingIngressControl(), let control = ingressControlAuthority else { return nil }
        let names = try originalEraseC16FinalControlRoleNames(plan: plan)
        let files = try names.map { name -> C16IngressHygieneFileIdentityV1 in
            let info = try regularFileInformation(named: name, directoryDescriptor: control.rootDescriptor)
            try verifySourceReadPolicy(.temporaryFile, at: protectedIngressReceiptDirectory().appendingPathComponent(name))
            return .init(name: name, information: info)
        }
        let marker = C16ScratchControlEraseV1(schemaVersion: 1, rootDevice: authority.rootDevice,
            rootInode: authority.rootInode, controlDevice: control.rootDevice, controlInode: control.rootInode, files: files)
        let bytes = try CompatibilityCanonicalV1.encode(marker)
        guard bytes.count <= 32 * 1_024 * 1_024 else { throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded }
        return .init(role: "scratchControlErase", bytes: bytes)
    }

    /// Ordered publication roles of one fixed semantic ordinal. A current
    /// publication can be absent, a single deterministic prefix/pair, or a
    /// completed prefix of this list. Names are never selected from survivors.
    private func originalEraseC16PublicationRoleSequence(
        plan: OriginalEraseC16PlanV1, ordinal: Int
    ) throws -> [String] {
        try requireScratchDescriptorAccess()
        var names: [String] = []
        func erase(_ marker: C16IngressEraseV1, fresh: Bool) throws {
            let prefix = "erase-" + marker.operationID.uuidString.lowercased()
            if fresh { names.append(prefix + ".prepare.json") }
            for target in marker.unpublishedTargets {
                names.append(try ingressControlName(target.preparation.intent.intentID, ".aborted.json"))
            }
            for target in marker.targets { names.append(try ingressControlName(target.intent.intentID, ".terminal.json")) }
            names.append(prefix + ".complete.json")
        }
        switch plan.steps[ordinal] {
        case let .resumeHygiene(operationID):
            for binding in plan.markerBindings where binding.name.hasPrefix("ingress-") && binding.name.hasSuffix(".published.json") {
                let published = try originalEraseC16ReferenceValue(C16IngressPublicationV1.self, name: binding.name)
                let recipe = try originalEraseC16FixedIngressRecipeData(intentID: published.intent.intentID)
                if recipe.terminalBeforeHygieneOrdinal == ordinal {
                    names.append(try ingressControlName(published.intent.intentID, ".terminal.json"))
                }
            }
            let prefix = "hygiene-" + operationID.uuidString.lowercased()
            names += [prefix + ".json", prefix + ".prepare.json.finalizing", prefix + ".prepare.json"]
        case let .resumeIngressErase(operationID):
            try erase(originalEraseC16ReferenceValue(C16IngressEraseV1.self,
                name: "erase-" + operationID.uuidString.lowercased() + ".prepare.json"), fresh: false)
        case let .recoverIngressPointer(intentID):
            let recipe = try originalEraseC16FixedIngressRecipeData(intentID: intentID)
            names.append(try ingressControlName(intentID, recipe.removal == nil ? ".pending.json" : ".terminal.json"))
        case .eraseIngress: try erase(originalEraseC16FixedFreshEraseMarker(plan: plan), fresh: true)
        case .eraseFinalControl: names = [Self.controlEraseName]
        case .settleFirstPPartial, .resumeControlTail: break
        }
        guard Set(names).count == names.count else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        return names
    }

    private func originalEraseC16RequireControlPublicationPrefix(
        plan: OriginalEraseC16PlanV1, ordinal: Int,
        roles: [String: OriginalEraseC16CanonicalRoleV1],
        controlNames: [String]
    ) throws {
        try requireScratchDescriptorAccess()
        guard try hasExistingIngressControl() else { return }
        let parent = try ingressControlDescriptor()
        let step = plan.steps[ordinal]
        if step == .resumeControlTail || step == .eraseFinalControl { return }
        // All completed prior outputs remain until the final control tail.
        if ordinal > 0 {
            let previous = try originalEraseC16CanonicalRoles(plan: plan, through: ordinal - 1)
            for (name, role) in previous where role.role != "hygieneFinalizing" {
                let consumedPending: Bool
                if name.hasSuffix(".pending.json") {
                    let id = try ingressControlIdentifier(name, prefix: "ingress-", suffixes: [".pending.json"])
                    consumedPending = try originalEraseC16MayConsumePending(id: id, plan: plan, through: ordinal)
                        && !controlNames.contains(name)
                } else { consumedPending = false }
                if consumedPending { continue }
                guard let leaf = try readOriginalErasePublicationLeaf(named: name, parent: parent,
                    maximumBytes: role.bytes.count), leaf.1 == role.bytes, leaf.0.st_nlink == 1 else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
            }
        }
        let sequence = try originalEraseC16PublicationRoleSequence(plan: plan, ordinal: ordinal)
        var sawIncomplete = false, sawActive = false
        for name in sequence {
            guard let role = roles[name] else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            let leaf = try readOriginalErasePublicationLeaf(named: name, parent: parent, maximumBytes: role.bytes.count)
            let completed: Bool
            if role.role == "hygieneFinalizing" {
                let finalizedName = String(name.dropLast(".finalizing".count))
                let renamed = try readOriginalErasePublicationLeaf(named: finalizedName, parent: parent,
                    maximumBytes: role.bytes.count)
                completed = leaf?.1 == role.bytes || renamed?.1 == role.bytes
            } else { completed = leaf?.1 == role.bytes }
            let temporary = try Self.originalErasePublicationTemporaryName(operationID: originalEraseOperationID!,
                finalName: name, leaseName: nil)
            let temp = try readOriginalErasePublicationLeaf(named: temporary, parent: parent, maximumBytes: role.bytes.count)
            if completed {
                // A role that already existed exactly in original P is an
                // immutable initial input, not a claimed effect of this step.
                let initial = originalEraseC16SourceInputs[name]?.bytes == role.bytes
                guard initial || (!sawIncomplete && !sawActive) else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                if temp != nil { sawActive = true }
            } else {
                if temp != nil {
                    guard !sawIncomplete, !sawActive else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    sawActive = true
                }
                sawIncomplete = true
            }
        }
    }

    @MainActor
    func originalEraseC16ExpectedTree(
        plan: OriginalEraseC16PlanV1, currentOrdinal: Int,
        controlMarkerState: OriginalEraseC16ControlMarkerStateV1?,
        ingressMarkerState: OriginalEraseC16IngressMarkerStateV1?,
        capturedBirths: [OriginalEraseC16CapturedBirthV1]
    ) throws -> OriginalEraseC16ExpectedTreeV1 {
        try requireScratchDescriptorAccess()
        try requireOriginalEraseBorrowedOwner()
        guard originalEraseC16ReferencePlan == plan, currentOrdinal >= 0,
              currentOrdinal < plan.steps.count, capturedBirths.count <= 100_000 else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let observed = try requireOriginalEraseC16ObservedProjection(plan: plan, currentOrdinal: currentOrdinal,
            controlMarkerState: controlMarkerState, ingressMarkerState: ingressMarkerState)
        var roles = try originalEraseC16CanonicalRoles(plan: plan, through: currentOrdinal)
        if let marker = try originalEraseC16MaterializedControlRole(plan: plan, ordinal: currentOrdinal) {
            roles[Self.controlEraseName] = marker
        }
        try originalEraseC16RequireControlPublicationPrefix(plan: plan, ordinal: currentOrdinal,
            roles: roles, controlNames: observed.observedControlNames)
        var files: [OriginalEraseC16ExpectedFileV1] = [], directories: [OriginalEraseC16ExpectedDirectoryV1] = []
        var consumed = Set<String>(), seen = Set<String>()
        let controlPrefix = "ProtectedIngressReceiptsV1/"
        let tailStep = plan.steps[currentOrdinal] == .eraseFinalControl || plan.steps[currentOrdinal] == .resumeControlTail
        let tailMarker: C16ScratchControlEraseV1?
        if tailStep, let marker = roles[Self.controlEraseName] {
            tailMarker = try CompatibilityCanonicalV1.decode(C16ScratchControlEraseV1.self, from: marker.bytes)
        } else { tailMarker = nil }
        let tailRemoved: Set<String>
        if let tailMarker {
            let surviving = observed.observedControlNames.filter { $0 != Self.controlEraseName }
            let order = tailMarker.files.map(\.name)
            guard surviving == Array(order.suffix(surviving.count)) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            tailRemoved = Set(order.prefix(order.count - surviving.count))
        } else { tailRemoved = [] }
        if observed.controlRootPresent {
            let parent = try ingressControlDescriptor()
            var exceptionalCount = 0
            for name in observed.observedControlNames {
                let path = controlPrefix + name; seen.insert(name)
                if let binding = plan.markerBindings.first(where: { $0.name == name }), name.hasPrefix(".partial-") {
                    let stepIndex = plan.steps.firstIndex { step in
                        if case let .settleFirstPPartial(.control, expected, _, _, _) = step { return expected == name }; return false
                    }
                    guard let stepIndex, stepIndex >= currentOrdinal else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    files.append(.init(path: path, source: .firstP(sourcePath: path, allowOneLinkSettlement: true)))
                    guard CompatibilityCanonicalV1.validSHA256(binding.sha256) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    continue
                }
                if name.hasPrefix(".partial-") {
                    var selected: OriginalEraseC16CanonicalRoleV1?
                    for (finalName, role) in roles {
                        if try Self.originalErasePublicationTemporaryName(operationID: originalEraseOperationID!, finalName: finalName, leaseName: nil) == name {
                            guard selected == nil else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }; selected = role
                        }
                    }
                    guard let role = selected,
                          let leaf = try readOriginalErasePublicationLeaf(named: name, parent: parent, maximumBytes: role.bytes.count),
                          role.bytes.starts(with: leaf.1) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    exceptionalCount += 1
                    files.append(.init(path: path, source: .postPDeterministic(role: "publicationPrefix:" + role.role,
                        fullFact: Self.originalEraseSourceFullFact(leaf.0), sha256: try CompatibilityCanonicalV1.sha256(leaf.1))))
                    continue
                }
                guard let leaf = try readOriginalErasePublicationLeaf(named: name, parent: parent,
                    maximumBytes: Self.originalEraseC16SourceMaximum(name: name)) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                let sha = try CompatibilityCanonicalV1.sha256(leaf.1)
                if let binding = plan.markerBindings.first(where: { $0.name == name }), sha == binding.sha256 {
                    files.append(.init(path: path, source: .firstP(sourcePath: path,
                        allowOneLinkSettlement: try originalEraseC16FirstPAllowsOneLinkSettlement(path: path, plan: plan))))
                } else {
                    guard let role = roles[name], role.bytes == leaf.1 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    let fact = Self.originalEraseSourceFullFact(leaf.0)
                    if let captured = capturedBirths.first(where: { $0.name == name }) {
                        guard captured.fullFact == fact, captured.sha256 == sha else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    }
                    files.append(.init(path: path, source: .postPDeterministic(role: role.role, fullFact: fact, sha256: sha)))
                }
            }
            guard exceptionalCount <= 1 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            directories.append(.init(path: "ProtectedIngressReceiptsV1", firstPSourcePath: "ProtectedIngressReceiptsV1",
                expectedMembers: observed.observedControlNames, expectedLinkCount: 2))
        }
        for binding in plan.markerBindings where !seen.contains(binding.name) {
            let name = binding.name, path = controlPrefix + name
            if tailRemoved.contains(name) || (tailStep && observed.observedControlNames.isEmpty && tailMarker != nil) {
                consumed.insert(path); continue
            }
            if name.hasPrefix(".partial-") {
                guard plan.steps.prefix(currentOrdinal + 1).contains(where: {
                    if case let .settleFirstPPartial(.control, expected, _, _, _) = $0 { return expected == name }; return false
                }) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                consumed.insert(path); continue
            }
            if name.hasPrefix("ingress-"), name.hasSuffix(".pending.json") {
                let id = try ingressControlIdentifier(name, prefix: "ingress-", suffixes: [".pending.json"])
                guard try originalEraseC16MayConsumePending(id: id, plan: plan, through: currentOrdinal),
                      let terminal = try readIngressControl(C16IngressRemovalV1.self, at: ingressControlURL(id, ".terminal.json")),
                      originalEraseC16TargetCut(.init(terminal.expected)) == .absent else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                consumed.insert(path); continue
            }
            if name.hasSuffix(".prepare.json.finalizing") {
                let base = String(name.dropLast(".finalizing".count))
                let initial = try originalEraseC16ReferenceValue(C16IngressHygienePrepareV1.self, name: base)
                let current = try readProtectedIngressPrepare(at: protectedIngressReceiptDirectory().appendingPathComponent(base))
                guard current == initial.finalizing() else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                consumed.insert(path); continue
            }
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        for target in observed.targets {
            let sourceName = target.source.directoryName
            let originalPath = "ScratchDataV1/" + sourceName
            let tombstonePath = "ScratchDataV1/" + Self.deletionTombstoneName(for: sourceName)
            let initial = try originalEraseC16InitialTargetCut(target.source)
            let firstPPath: String
            switch initial { case .tombstone: firstPPath = tombstonePath; default: firstPPath = originalPath }
            let path: String, removed: Int
            switch target.location {
            case .absent:
                for source in originalEraseC16FirstPFacts.keys where source == firstPPath || source.hasPrefix(firstPPath + "/") { consumed.insert(source) }
                continue
            case .original: path = originalPath; removed = 0
            case let .tombstone(count): path = tombstonePath; removed = count
            }
            let children = Array(target.source.files.dropFirst(removed))
            for file in children {
                files.append(.init(path: path + "/" + file.name,
                    source: .firstP(sourcePath: firstPPath + "/" + file.name,
                        allowOneLinkSettlement: try originalEraseC16FirstPAllowsOneLinkSettlement(
                            path: firstPPath + "/" + file.name, plan: plan))))
            }
            for file in target.source.files.prefix(removed) { consumed.insert(firstPPath + "/" + file.name) }
            var members = children.map(\.name)
            for (partialOrdinal, step) in plan.steps.enumerated() {
                guard case let .settleFirstPPartial(.lease(lease), name, _, _, _) = step,
                      lease == sourceName, !target.source.files.map(\.name).contains(name) else { continue }
                let partialPath = firstPPath + "/" + name
                if partialOrdinal < currentOrdinal || (partialOrdinal == currentOrdinal && observed.currentCut == .terminal) {
                    consumed.insert(partialPath)
                } else {
                    guard path == originalPath else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    files.append(.init(path: path + "/" + name,
                        source: .firstP(sourcePath: partialPath, allowOneLinkSettlement: true)))
                    members.append(name)
                }
            }
            directories.append(.init(path: path, firstPSourcePath: firstPPath,
                expectedMembers: members.sorted(), expectedLinkCount: 2))
        }
        guard files.count + directories.count <= 100_000,
              Set(files.map(\.path)).count == files.count,
              Set(directories.map(\.path)).count == directories.count else { throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded }
        try requireOriginalEraseBorrowedOwner()
        return .init(currentOrdinal: currentOrdinal, currentCut: observed.currentCut,
            files: files.sorted { $0.path < $1.path }, directories: directories.sorted { $0.path < $1.path },
            consumedFirstPPaths: consumed.sorted())
    }

    private func originalEraseC16FinalControlRoleNames(
        plan: OriginalEraseC16PlanV1
    ) throws -> [String] {
        try requireScratchDescriptorAccess()
        guard plan.steps.contains(.eraseFinalControl),
              !plan.steps.contains(.resumeControlTail),
              let originalEraseOperationID else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        var roles = Set(plan.markerBindings.map(\.name).filter {
            !$0.hasPrefix(".partial-") && !$0.hasSuffix(".prepare.json.finalizing")
        })
        for binding in plan.markerBindings where binding.name.hasPrefix("ingress-")
            && binding.name.hasSuffix(".published.json") {
            let id = try ingressControlIdentifier(binding.name, prefix: "ingress-", suffixes: [".published.json"])
            roles.remove(try ingressControlName(id, ".pending.json"))
            roles.insert(try ingressControlName(id, ".terminal.json"))
        }
        for step in plan.steps {
            switch step {
            case let .resumeHygiene(operationID):
                roles.insert("hygiene-" + operationID.uuidString.lowercased() + ".json")
            case let .resumeIngressErase(operationID):
                let prefix = "erase-" + operationID.uuidString.lowercased()
                roles.insert(prefix + ".complete.json")
                let erase = try originalEraseC16ReferenceValue(C16IngressEraseV1.self,
                    name: prefix + ".prepare.json")
                for target in erase.unpublishedTargets {
                    roles.insert(try ingressControlName(target.preparation.intent.intentID, ".aborted.json"))
                }
            case .eraseIngress:
                let prefix = "erase-" + originalEraseOperationID.uuidString.lowercased()
                roles.insert(prefix + ".prepare.json")
                roles.insert(prefix + ".complete.json")
                for target in plan.freshUnpublishedTargets {
                    roles.insert(try ingressControlName(target.intentID, ".aborted.json"))
                }
            default: break
            }
        }
        guard roles.count <= 100_000 else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        return roles.sorted()
    }

    private func c16ControlEraseSteps(resumeOnly: Bool,
        capturedMarkerPublication: Bool = false) -> [C16SemanticStepV1] {
        [.plan { [self] _ in
            try self.requireScratchDescriptorAccess()
        if originalEraseBorrowedExclusiveCheck != nil, originalEraseControlRemovalProved { return [] }
        guard try hasExistingIngressControl() else { return [] }
        let directory = try protectedIngressReceiptDirectory()
        guard let pinned = ingressControlAuthority else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        let descriptor = pinned.rootDescriptor
        let markerPresent = try regularFileInformationIfPresent(named: Self.controlEraseName,
            directoryDescriptor: descriptor) != nil
        if capturedMarkerPublication && !markerPresent {
            guard originalEraseBorrowedExclusiveCheck != nil,
                  try directoryNames(descriptor).isEmpty else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            return c16ControlRootRemovalSteps(pinned)
        }
        if resumeOnly && !markerPresent {
            guard originalEraseBorrowedExclusiveCheck != nil,
                  try directoryNames(descriptor).isEmpty else { return [] }
            return c16ControlRootRemovalSteps(pinned)
        }
        if !markerPresent, originalEraseBorrowedExclusiveCheck == nil {
            try removeInterruptedPublications(directoryDescriptor: descriptor)
        }
        var work: [C16SemanticStepV1] = []
        let maximumMarkerBytes = 32 * 1_024 * 1_024
        let markerURL = directory.appendingPathComponent(Self.controlEraseName)
        let marker: C16ScratchControlEraseV1
        if markerPresent {
            let data = try readRegularFile(named: Self.controlEraseName, directoryDescriptor: descriptor, maximumBytes: maximumMarkerBytes)
            try ProtectedFilePolicyV1.verify(.temporaryFile, at: markerURL)
            marker = try CompatibilityCanonicalV1.decode(C16ScratchControlEraseV1.self, from: data)
        } else {
            _ = try ingressPreparations()
            guard try pendingIngressPublications().isEmpty else { throw AppAccessContractFailureV1.effectMismatch }
            for preparation in try ingressPreparations() {
                let id = preparation.intent.intentID
                guard try ingressControlFileExists(ingressControlURL(id, ".terminal.json"))
                    || ingressControlFileExists(ingressControlURL(id, ".aborted.json")) else {
                    throw AppAccessContractFailureV1.effectMismatch
                }
            }
            let expectedTemporary: String?
            if let originalEraseOperationID {
                expectedTemporary = try Self.originalErasePublicationTemporaryName(
                    operationID: originalEraseOperationID,
                    finalName: Self.controlEraseName, leaseName: nil)
            } else {
                expectedTemporary = nil
            }
            let inventoryNames = try directoryNames(descriptor)
            guard inventoryNames.filter({ $0.hasPrefix(".partial-") })
                == (expectedTemporary.flatMap { inventoryNames.contains($0)
                    ? [$0] : nil } ?? []) else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            let roleNames: [String]
            if let plan = originalEraseC16ReferencePlan {
                roleNames = try originalEraseC16FinalControlRoleNames(plan: plan)
                guard inventoryNames.filter({ $0 != expectedTemporary }) == roleNames else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
            } else {
                guard originalEraseBorrowedExclusiveCheck == nil else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                roleNames = inventoryNames.filter { $0 != expectedTemporary }
            }
            let files = try roleNames.map { name -> C16IngressHygieneFileIdentityV1 in
                try validateIngressControlSnapshotName(name)
                try ProtectedFilePolicyV1.verify(.temporaryFile, at: directory.appendingPathComponent(name))
                return try .init(name: name, information: regularFileInformation(named: name, directoryDescriptor: descriptor))
            }
            marker = .init(schemaVersion: 1, rootDevice: authority.rootDevice, rootInode: authority.rootInode,
                controlDevice: pinned.rootDevice, controlInode: pinned.rootInode, files: files)
            let data = try CompatibilityCanonicalV1.encode(marker)
            guard data.count <= maximumMarkerBytes else { throw AppAccessContractFailureV1.configurationUnknown }
            work += try c16PublicationSteps(data, to: markerURL, atomicExclusiveRename: true)
            work.append(.effect { [self] in
                try ingressMutationFailureInjection.interruptIfTriggered(.afterScratchControlErasePrepare)
            })
        }
        work.append(.plan { [self] _ in
        guard marker.schemaVersion == 1, marker.rootDevice == authority.rootDevice, marker.rootInode == authority.rootInode,
              marker.controlDevice == pinned.rootDevice, marker.controlInode == pinned.rootInode,
              marker.files.count <= 100_000, marker.files.map(\.name) == marker.files.map(\.name).sorted(),
              Set(marker.files.map(\.name)).count == marker.files.count else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        var expectedFiles: [String: C16IngressHygieneFileIdentityV1] = [:]
        for file in marker.files {
            try validateIngressControlSnapshotName(file.name)
            guard file.device == pinned.rootDevice, file.byteCount >= 0, file.modifiedNanoseconds >= 0,
                  file.modifiedNanoseconds < 1_000_000_000 else { throw AppAccessContractFailureV1.configurationUnknown }
            expectedFiles[file.name] = file
        }
        let remaining = try directoryNames(descriptor).filter { $0 != Self.controlEraseName }
        for name in remaining {
            let current = try C16IngressHygieneFileIdentityV1(name: name,
                information: regularFileInformation(named: name, directoryDescriptor: descriptor))
            guard expectedFiles[name] == current else { throw AppAccessContractFailureV1.configurationUnknown }
            try ProtectedFilePolicyV1.verify(.temporaryFile, at: directory.appendingPathComponent(name))
        }
        var effects: [C16SemanticStepV1] = []
        for name in remaining {
            effects.append(.effect { [self] in
                _ = try protectedIngressReceiptDirectory()
                let current = try C16IngressHygieneFileIdentityV1(name: name,
                    information: regularFileInformation(named: name, directoryDescriptor: descriptor))
                guard expectedFiles[name] == current,
                      Darwin.unlinkat(descriptor, name, 0) == 0,
                      Darwin.fsync(descriptor) == 0 else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
            })
            effects.append(.effect { [self] in
                try ingressMutationFailureInjection.interruptIfTriggered(.afterScratchControlEraseFile)
            })
        }
        effects.append(.effect { [self] in
            _ = try protectedIngressReceiptDirectory()
            guard try directoryNames(descriptor) == [Self.controlEraseName],
                  try readRegularFile(named: Self.controlEraseName,
                    directoryDescriptor: descriptor, maximumBytes: maximumMarkerBytes)
                    == CompatibilityCanonicalV1.encode(marker),
                  Darwin.unlinkat(descriptor, Self.controlEraseName, 0) == 0,
                  Darwin.fsync(descriptor) == 0 else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        })
        effects += c16ControlRootRemovalSteps(pinned)
        return effects
        })
        return work
        }]
    }

    private func validateIngressClaim(_ claim: C16IngressDirectoryClaimV1) throws -> Int32 {
        try requireScratchDescriptorAccess()
        try validateIngressPreparation(claim.preparation, intentID: claim.preparation.intent.intentID)
        let name = claim.preparation.lease.relativeDirectory
        let descriptor: Int32
        do {
            descriptor = try openLeaseDirectory(name)
        } catch ScratchDataLeaseStoreFailureV1.invalidRoot {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        do {
            var information = stat()
            guard Darwin.fstat(descriptor, &information) == 0,
                  UInt64(information.st_dev) == claim.device, UInt64(information.st_ino) == claim.inode else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            try verifySourceReadPolicy(.stagingDirectory,
                at: rootURL.appendingPathComponent(name))
            try verifyLeaseDirectory(name, descriptor: descriptor)
            return descriptor
        } catch {
            try closeObservedScratchDescriptor(descriptor)
            throw error
        }
    }

    private func validateIngressPublication(_ value: C16IngressPublicationV1, hashPayload: Bool) throws {
        try requireScratchDescriptorAccess()
        try value.validate()
        let descriptor = try validateIngressClaim(value.claim)
        try withObservedScratchDescriptor(descriptor) { descriptor in
            let name = value.claim.preparation.lease.relativeDirectory
            let files = try ingressHygieneFileIdentities(name: name,
                descriptor: descriptor)
            guard files == [value.metadata, value.payload].sorted(by: {
                $0.name < $1.name
            }) else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            if hashPayload {
                let payload = Darwin.openat(descriptor, value.payload.name,
                    O_RDONLY | O_NOFOLLOW)
                guard payload >= 0 else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
                try withObservedScratchDescriptor(payload) { payload in
                    var information = stat()
                    guard Darwin.fstat(payload, &information) == 0,
                          C16IngressHygieneFileIdentityV1(
                            name: value.payload.name, information: information)
                            == value.payload,
                          try opaqueSHA256(descriptor: payload,
                            byteCount: value.intent.byteCount)
                            == value.intent.sha256 else {
                        throw AppAccessContractFailureV1.effectMismatch
                    }
                    try verifyLeaseDirectory(name, descriptor: descriptor)
                    guard try C16IngressHygieneFileIdentityV1(
                        name: value.payload.name,
                        information: regularFileInformation(
                            named: value.payload.name,
                            directoryDescriptor: descriptor))
                            == value.payload else {
                        throw AppAccessContractFailureV1.effectMismatch
                    }
                }
            }
        }
    }

    private func validateOpaqueSourceLink(_ source: URL, expected: stat) throws {
        try requireScratchDescriptorAccess()
        var linked = stat()
        guard Darwin.lstat(source.path, &linked) == 0, (linked.st_mode & S_IFMT) == S_IFREG,
              linked.st_nlink == 1,
              C16IngressHygieneFileIdentityV1(name: "source", information: linked)
                == C16IngressHygieneFileIdentityV1(name: "source", information: expected) else {
            throw AppAccessContractFailureV1.effectMismatch
        }
    }

    private func opaqueSHA256(descriptor: Int32, byteCount: UInt64) throws -> String {
        try requireScratchDescriptorAccess()
        guard byteCount > 0, byteCount <= PendingLockedExternalIntentV1.maximumByteCount else {
            throw AppAccessContractFailureV1.invalidValue
        }
        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0, (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1, before.st_size >= 0, UInt64(before.st_size) == byteCount else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        var hash = SHA256()
        var offset: UInt64 = 0
        while offset < byteCount {
            let count = Int(min(UInt64(1_048_576), byteCount - offset))
            var data = Data(count: count)
            let read = data.withUnsafeMutableBytes { bytes in
                Darwin.pread(descriptor, bytes.baseAddress!, count, off_t(offset))
            }
            guard read > 0 else { throw AppAccessContractFailureV1.effectMismatch }
            data.count = read
            hash.update(data: data)
            offset += UInt64(read)
        }
        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0, after.st_nlink == 1,
              C16IngressHygieneFileIdentityV1(name: "source", information: before)
                == C16IngressHygieneFileIdentityV1(name: "source", information: after) else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func publishOpaqueIngress(sourceDescriptor: Int32, preparation: C16IngressPreparedStageV1,
                                      directoryDescriptor: Int32) throws -> C16IngressHygieneFileIdentityV1 {
        try requireScratchDescriptorAccess()
        let sinkActivity = try OwnedStorageProducerActivityV1.acquire(
            applicationSupportURL: producerApplicationSupportURL)
        var activityTransferred = false
        defer { if !activityTransferred { sinkActivity.close() } }
        let name = preparation.lease.relativeDirectory
        let directory = rootURL.appendingPathComponent(name, isDirectory: true)
        let finalName = "opaque-data"
        let finalURL = directory.appendingPathComponent(finalName)
        try removeInterruptedPublications(directoryDescriptor: directoryDescriptor)
        if let existing = try regularFileInformationIfPresent(named: finalName, directoryDescriptor: directoryDescriptor) {
            let descriptor = Darwin.openat(directoryDescriptor, finalName, O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else { throw AppAccessContractFailureV1.configurationUnknown }
            defer { _ = Darwin.close(descriptor) }
            var pinned = stat()
            guard Darwin.fstat(descriptor, &pinned) == 0, pinned.st_dev == existing.st_dev, pinned.st_ino == existing.st_ino,
                  try opaqueSHA256(descriptor: descriptor, byteCount: preparation.intent.byteCount) == preparation.intent.sha256 else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            try ProtectedFilePolicyV1.verify(.temporaryFile, at: finalURL)
            try verifyLeaseDirectory(name, descriptor: directoryDescriptor)
            return .init(name: finalName, information: try regularFileInformation(named: finalName, directoryDescriptor: directoryDescriptor))
        }
        try storagePreflight.checkScratchLease(requestedByteCount: preparation.intent.byteCount, onVolumeContaining: rootURL)
        let temporaryName = ".partial-" + UUID().uuidString.lowercased()
        let temporaryURL = directory.appendingPathComponent(temporaryName)
        let descriptor = Darwin.openat(directoryDescriptor, temporaryName, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw AppAccessContractFailureV1.configurationUnknown }
        let sink = try EncryptedPortableEnvelopeProtectedFileScratchV1(url: temporaryURL,
            pinnedDescriptor: descriptor, maximumByteCount: preparation.intent.byteCount,
            producerActivity: sinkActivity)
        activityTransferred = true
        defer { sink.closeResource() }
        var temporaryIdentity = stat()
        guard Darwin.fstat(descriptor, &temporaryIdentity) == 0 else { throw AppAccessContractFailureV1.configurationUnknown }
        // The existing opaque descriptor sink owns this descriptor and never interprets bytes.
        try ProtectedFilePolicyV1.applyAndVerify(.temporaryFile, at: temporaryURL, authorityCheck: {
            try self.verifyLeaseDirectory(name, descriptor: directoryDescriptor)
            let linked = try self.regularFileInformation(named: temporaryName, directoryDescriptor: directoryDescriptor)
            guard linked.st_dev == temporaryIdentity.st_dev, linked.st_ino == temporaryIdentity.st_ino else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        })
        try sink.prepareForStreamingWrite(expectedByteCount: preparation.intent.byteCount)
        var offset: UInt64 = 0
        var copiedHash = SHA256()
        while offset < preparation.intent.byteCount {
            let count = Int(min(UInt64(1_048_576), preparation.intent.byteCount - offset))
            var bytes = Data(count: count)
            let read = bytes.withUnsafeMutableBytes { raw in
                Darwin.pread(sourceDescriptor, raw.baseAddress!, count, off_t(offset))
            }
            guard read > 0 else { throw AppAccessContractFailureV1.effectMismatch }
            bytes.count = read
            try sink.appendStreamingBytes(bytes)
            copiedHash.update(data: bytes)
            offset += UInt64(read)
        }
        try sink.synchronizeStreamingWrite()
        guard copiedHash.finalize().map({ String(format: "%02x", $0) }).joined() == preparation.intent.sha256,
              try opaqueSHA256(descriptor: sourceDescriptor, byteCount: preparation.intent.byteCount) == preparation.intent.sha256,
              try opaqueSHA256(descriptor: descriptor, byteCount: preparation.intent.byteCount) == preparation.intent.sha256 else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        try verifyLeaseDirectory(name, descriptor: directoryDescriptor)
        guard Darwin.linkat(directoryDescriptor, temporaryName, directoryDescriptor, finalName, 0) == 0,
              Darwin.unlinkat(directoryDescriptor, temporaryName, 0) == 0,
              Darwin.fsync(directoryDescriptor) == 0 else { throw AppAccessContractFailureV1.configurationUnknown }
        try ProtectedFilePolicyV1.verify(.temporaryFile, at: finalURL)
        try verifyLeaseDirectory(name, descriptor: directoryDescriptor)
        let final = try regularFileInformation(named: finalName, directoryDescriptor: directoryDescriptor)
        guard final.st_dev == temporaryIdentity.st_dev, final.st_ino == temporaryIdentity.st_ino else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        return .init(name: finalName, information: final)
    }

    /// Synchronous SOURCE inspection uses the existing lease, root and cleanup
    /// owner. Callers acquire their generation authority BEFORE entering here;
    /// neither this scope nor its nonescaping body may suspend.
    @MainActor
    final class SourceReadDirectory {
        fileprivate let store: ScratchDataLeaseStoreV1
        fileprivate let lease: ScratchDataLeaseV1
        fileprivate var descriptor: Int32
        fileprivate let readerIsDrained: @MainActor () -> Bool
        private var unlocked = false
        private var descriptorCloseAttempted = false
        private let producerActivity: OwnedStorageProducerActivityV1?
        private let exclusivePermit: ExclusiveEraseSourceReadPermit?
        private var exclusiveOwnedInodes: [String: (device: UInt64, inode: UInt64)] = [:]
        private static let sqliteNames: Set<String> = ["model.sqlite", "model.sqlite-wal", "model.sqlite-shm"]
        var modelURL: URL { directoryURL.appendingPathComponent("model.sqlite") }
        private var directoryURL: URL { store.rootURL.appendingPathComponent(lease.relativeDirectory) }

        fileprivate init(store: ScratchDataLeaseStoreV1, lease: ScratchDataLeaseV1,
                         readerIsDrained: @escaping @MainActor () -> Bool,
                         exclusivePermit: ExclusiveEraseSourceReadPermit? = nil) throws {
            try exclusivePermit?.requireHeld()
            let retainedActivity: OwnedStorageProducerActivityV1?
            if exclusivePermit == nil {
                retainedActivity = try OwnedStorageProducerActivityV1.acquire(
                    applicationSupportURL: store.producerApplicationSupportURL)
            } else {
                retainedActivity = nil
            }
            let fd: Int32
            do { fd = try store.openLeaseDirectory(lease.relativeDirectory) }
            catch { retainedActivity?.close(); throw error }
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
                retainedActivity?.close()
                let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(fd)
                if Darwin.close(fd) == 0 {
                    ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
                }
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            self.store = store; self.lease = lease; descriptor = fd
            producerActivity = retainedActivity
            self.exclusivePermit = exclusivePermit
            self.readerIsDrained = readerIsDrained
        }
        deinit {
            if descriptor >= 0 {
                if !descriptorCloseAttempted { _ = Darwin.close(descriptor) }
            }
        }

        /// The freshly allocated lease owns only its canonical metadata.
        /// Record its actual inode before any SQLite file is created.
        func establishExclusiveOwnedMetadata() throws {
            guard exclusivePermit != nil, exclusiveOwnedInodes.isEmpty else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            try verify()
            guard Set(try store.directoryNames(descriptor))
                    == Set([ScratchDataLeaseStoreV1.metadataName]) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            let value = try store.regularFileInformation(
                named: ScratchDataLeaseStoreV1.metadataName,
                directoryDescriptor: descriptor)
            exclusiveOwnedInodes[ScratchDataLeaseStoreV1.metadataName] =
                (UInt64(value.st_dev), UInt64(value.st_ino))
        }

        private func requireExactExclusiveOwnedFiles() throws -> [C16IngressHygieneFileIdentityV1] {
            guard exclusivePermit != nil, !exclusiveOwnedInodes.isEmpty else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            let names = try store.directoryNames(descriptor)
            guard Set(names) == Set(exclusiveOwnedInodes.keys) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            return try names.map { name in
                guard let expected = exclusiveOwnedInodes[name] else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                let value = try store.regularFileInformation(
                    named: name, directoryDescriptor: descriptor)
                guard UInt64(value.st_dev) == expected.device,
                      UInt64(value.st_ino) == expected.inode,
                      value.st_nlink == 1 else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                return C16IngressHygieneFileIdentityV1(name: name, information: value)
            }
        }

        /// Called immediately before SwiftData sees the private directory.
        /// A hostile same-name SHM supplied by a fixture is rejected here.
        func requireExclusiveOwnedFilesBeforeContainer() throws {
            try verify()
            _ = try requireExactExclusiveOwnedFiles()
        }

        /// If the authenticated source had no SHM, create a zero-length one
        /// with O_EXCL before SwiftData sees this private directory. SQLite
        /// may grow this owned inode; it may never create or substitute one.
        func prepareExclusiveOwnedSHMForContainer() throws {
            try verify()
            guard exclusivePermit != nil else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            _ = try requireExactExclusiveOwnedFiles()
            guard exclusiveOwnedInodes["model.sqlite"] != nil else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            if exclusiveOwnedInodes["model.sqlite-shm"] == nil {
                let fd = Darwin.openat(descriptor, "model.sqlite-shm",
                    O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                    mode_t(0o600))
                guard fd >= 0 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                var closeAttempted = false
                defer {
                    if !closeAttempted {
                        let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(fd)
                        if Darwin.close(fd) == 0 {
                            ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
                        }
                    }
                }
                var owned = stat()
                guard Darwin.fstat(fd, &owned) == 0,
                      owned.st_mode & S_IFMT == S_IFREG,
                      owned.st_nlink == 1,
                      owned.st_size == 0 else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                try store.applySourceReadPolicy(.temporaryFile,
                    at: directoryURL.appendingPathComponent("model.sqlite-shm")) {
                    try self.store.verifyLeaseDirectory(
                        self.lease.relativeDirectory, descriptor: self.descriptor)
                    let named = try self.store.regularFileInformation(
                        named: "model.sqlite-shm",
                        directoryDescriptor: self.descriptor)
                    var held = stat()
                    guard Darwin.fstat(fd, &held) == 0,
                          named.st_dev == owned.st_dev,
                          named.st_ino == owned.st_ino,
                          held.st_dev == owned.st_dev,
                          held.st_ino == owned.st_ino else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                }
                guard Darwin.fsync(fd) == 0,
                      Darwin.fsync(descriptor) == 0 else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                exclusiveOwnedInodes["model.sqlite-shm"] =
                    (UInt64(owned.st_dev), UInt64(owned.st_ino))
                closeAttempted = true
                let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(fd)
                guard Darwin.close(fd) == 0 else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
            }
            _ = try requireExactExclusiveOwnedFiles()
        }

        func requireExclusiveContainerKeptOwnedFiles() throws {
            try verify()
            _ = try requireExactExclusiveOwnedFiles()
        }

        func verify() throws {
            if let exclusivePermit { try exclusivePermit.requireHeld() }
            else if let producerActivity {
                try producerActivity.requireApplicationSupport(store.producerApplicationSupportURL)
            } else { throw ScratchDataLeaseStoreFailureV1.invalidLease }
            guard !unlocked, store.clock() < lease.request.expiresAt else {
                throw ScratchDataLeaseStoreFailureV1.leaseExpired
            }
            try store.requireExpectedScratchLease(lease, named: lease.relativeDirectory, descriptor: descriptor)
            let names = try store.directoryNames(descriptor)
            guard Set(names).isSubset(of: Self.sqliteNames.union([ScratchDataLeaseStoreV1.metadataName])) else {
                throw ScratchDataLeaseStoreFailureV1.invalidLease
            }
            for name in names { _ = try store.regularFileInformation(named: name, directoryDescriptor: descriptor) }
            guard try store.payloadByteCount(directoryDescriptor: descriptor, directoryURL: directoryURL)
                    <= lease.request.requestedByteCount else { throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded }
        }

        /// The caller streams from its independently authenticated source FD;
        /// no whole-file Data buffer or arbitrary destination path is admitted.
        func copySQLiteFile(named name: String, byteCount: UInt64, write: (Int32) throws -> Void) throws {
            try verify()
            guard Self.sqliteNames.contains(name) else { throw ScratchDataLeaseStoreFailureV1.invalidLease }
            let current = try store.payloadByteCount(directoryDescriptor: descriptor, directoryURL: directoryURL)
            let (total, overflow) = current.addingReportingOverflow(byteCount)
            guard !overflow, total <= lease.request.requestedByteCount else {
                throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
            }
            let fd = Darwin.openat(descriptor, name, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
            guard fd >= 0 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            var terminalFD = fd
            var closeAttempted = false
            defer {
                if terminalFD >= 0 && !closeAttempted {
                    if exclusivePermit != nil {
                        let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(terminalFD)
                        if Darwin.close(terminalFD) == 0 {
                            ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
                        }
                    } else { _ = Darwin.close(terminalFD) }
                }
            }
            var owned = stat()
            guard Darwin.fstat(fd, &owned) == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            func reprove() throws {
                try self.store.verifyLeaseDirectory(self.lease.relativeDirectory, descriptor: self.descriptor)
                let named = try self.store.regularFileInformation(named: name, directoryDescriptor: self.descriptor)
                var held = stat()
                guard Darwin.fstat(fd, &held) == 0, named.st_dev == owned.st_dev, named.st_ino == owned.st_ino,
                      held.st_dev == owned.st_dev, held.st_ino == owned.st_ino, held.st_nlink == 1 else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
            }
            try store.applySourceReadPolicy(.temporaryFile,
                at: directoryURL.appendingPathComponent(name), authorityCheck: reprove)
            try write(fd)
            try reprove()
            var final = stat()
            guard Darwin.fstat(fd, &final) == 0, final.st_size >= 0, UInt64(final.st_size) == byteCount,
                  Darwin.fsync(fd) == 0, Darwin.fsync(descriptor) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            try verify()
            if exclusivePermit != nil {
                exclusiveOwnedInodes[name] =
                    (UInt64(owned.st_dev), UInt64(owned.st_ino))
                closeAttempted = true
                let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(fd)
                guard Darwin.close(fd) == 0 else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
                terminalFD = -1
            }
        }

        struct FileProof: Equatable {
            let device: UInt64
            let inode: UInt64
            let byteCount: UInt64
            let sha256: String
            let modifiedSeconds: Int64
            let modifiedNanoseconds: Int64
            let changedSeconds: Int64
            let changedNanoseconds: Int64
        }

        func verifySQLiteFile(named name: String, matches expected: FileProof) throws {
            try verify()
            guard Self.sqliteNames.contains(name) else { throw ScratchDataLeaseStoreFailureV1.invalidLease }
            let named = try store.regularFileInformation(named: name, directoryDescriptor: descriptor)
            let fd = Darwin.openat(descriptor, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            var terminalFD = fd
            var closeAttempted = false
            defer {
                if terminalFD >= 0 && !closeAttempted {
                    if exclusivePermit != nil {
                        let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(terminalFD)
                        if Darwin.close(terminalFD) == 0 {
                            ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
                        }
                    } else { _ = Darwin.close(terminalFD) }
                }
            }
            var held = stat()
            guard Darwin.fstat(fd, &held) == 0,
                  C16IngressHygieneFileIdentityV1(name: name, information: named)
                    == C16IngressHygieneFileIdentityV1(name: name, information: held),
                  UInt64(held.st_dev) == expected.device, UInt64(held.st_ino) == expected.inode,
                  UInt64(held.st_size) == expected.byteCount,
                  Int64(held.st_mtimespec.tv_sec) == expected.modifiedSeconds,
                  Int64(held.st_mtimespec.tv_nsec) == expected.modifiedNanoseconds,
                  Int64(held.st_ctimespec.tv_sec) == expected.changedSeconds,
                  Int64(held.st_ctimespec.tv_nsec) == expected.changedNanoseconds else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            if exclusivePermit != nil {
                closeAttempted = true
                let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(fd)
                guard Darwin.close(fd) == 0 else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
                terminalFD = -1
            }
        }

        func sqliteFileNames() throws -> Set<String> {
            try verify()
            return Set(try store.directoryNames(descriptor)).subtracting([ScratchDataLeaseStoreV1.metadataName])
        }

        func sqliteFileProof(named name: String) throws -> FileProof {
            try verify()
            guard Self.sqliteNames.contains(name) else { throw ScratchDataLeaseStoreFailureV1.invalidLease }
            let before = try store.regularFileInformation(named: name, directoryDescriptor: descriptor)
            let fd = Darwin.openat(descriptor, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            var terminalFD = fd
            var closeAttempted = false
            defer {
                if terminalFD >= 0 && !closeAttempted {
                    if exclusivePermit != nil {
                        let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(terminalFD)
                        if Darwin.close(terminalFD) == 0 {
                            ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
                        }
                    } else { _ = Darwin.close(terminalFD) }
                }
            }
            var held = stat()
            guard Darwin.fstat(fd, &held) == 0, held.st_dev == before.st_dev, held.st_ino == before.st_ino else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            var hash = SHA256(), count: UInt64 = 0
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while true {
                let read = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
                if read == 0 { break }
                if read < 0, errno == EINTR { continue }
                guard read > 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                let (next, overflow) = count.addingReportingOverflow(UInt64(read))
                guard !overflow, next <= UInt64(before.st_size) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                count = next; hash.update(data: Data(buffer.prefix(read)))
            }
            let after = try store.regularFileInformation(named: name, directoryDescriptor: descriptor)
            guard count == UInt64(before.st_size), Darwin.fstat(fd, &held) == 0,
                  C16IngressHygieneFileIdentityV1(name: name, information: before)
                    == C16IngressHygieneFileIdentityV1(name: name, information: after),
                  C16IngressHygieneFileIdentityV1(name: name, information: before)
                    == C16IngressHygieneFileIdentityV1(name: name, information: held) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            if exclusivePermit != nil {
                closeAttempted = true
                let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(fd)
                guard Darwin.close(fd) == 0 else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
                terminalFD = -1
            }
            return FileProof(device: UInt64(before.st_dev), inode: UInt64(before.st_ino),
                byteCount: count, sha256: hash.finalize().map { String(format: "%02x", $0) }.joined(),
                modifiedSeconds: Int64(before.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(before.st_mtimespec.tv_nsec),
                changedSeconds: Int64(before.st_ctimespec.tv_sec), changedNanoseconds: Int64(before.st_ctimespec.tv_nsec))
        }

        fileprivate func closeReaderScope() throws -> [C16IngressHygieneFileIdentityV1]? {
            try exclusivePermit?.requireHeld()
            guard readerIsDrained() else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            // SQLite-created auxiliary files inherit protection, but apply and
            // verify the shared temporary-file policy before terminal cleanup.
            try store.requireExpectedScratchLease(lease, named: lease.relativeDirectory, descriptor: descriptor)
            let names = try store.directoryNames(descriptor)
            guard Set(names).isSubset(of: Self.sqliteNames.union([ScratchDataLeaseStoreV1.metadataName])) else {
                throw ScratchDataLeaseStoreFailureV1.invalidLease
            }
            let exclusiveFiles = exclusivePermit != nil
                ? try requireExactExclusiveOwnedFiles() : nil
            for name in names where name != ScratchDataLeaseStoreV1.metadataName {
                let before = try store.regularFileInformation(named: name, directoryDescriptor: descriptor)
                try store.applySourceReadPolicy(.temporaryFile,
                    at: directoryURL.appendingPathComponent(name)) {
                    try self.store.verifyLeaseDirectory(self.lease.relativeDirectory, descriptor: self.descriptor)
                    let now = try self.store.regularFileInformation(named: name, directoryDescriptor: self.descriptor)
                    guard now.st_dev == before.st_dev, now.st_ino == before.st_ino else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                }
            }
            guard flock(descriptor, LOCK_UN) == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            unlocked = true
            if exclusivePermit != nil {
                let owned = descriptor
                descriptorCloseAttempted = true
                let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(owned)
                guard Darwin.close(owned) == 0 else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
                descriptor = -1
            }
            producerActivity?.close()
            return exclusiveFiles
        }
    }

    // An unexpectedly retained reader keeps its directory lock until it drains
    // or the process ends. Existing cold lease recovery remains the sole owner.
    @MainActor private static var retainedSourceReaders: [SourceReadDirectory] = []
    @MainActor private static var retainedExclusiveSourceStores: [ScratchDataLeaseStoreV1] = []

    @MainActor
    struct OriginalEraseExclusiveSourceReadReceiptV1 {
        let ownerOperationID: UUID
        let leaseID: UUID
        let leaseName: String
        let operationsFact: String
        let operationsNames: [String]
        let beforeScratchRootFact: String
        let beforeScratchDigest: String
        let afterScratchRootFact: String
        let afterScratchDigest: String
        private let checkedSettled: Bool

        fileprivate init(request: ScratchDataLeaseRequestV1,
                         leaseName: String,
                         before: OriginalEraseExclusiveSourceCutV1,
                         after: OriginalEraseExclusiveSourceCutV1) {
            ownerOperationID = request.ownerOperationID
            leaseID = request.leaseID
            self.leaseName = leaseName
            operationsFact = before.operationsFact
            operationsNames = before.operationsNames
            beforeScratchRootFact = before.scratchRootFact
            beforeScratchDigest = before.scratchDigest
            afterScratchRootFact = after.scratchRootFact
            afterScratchDigest = after.scratchDigest
            checkedSettled = true
        }

        func requireCheckedSettlement() throws {
            guard checkedSettled, !leaseName.isEmpty,
                  StoreMigrationCanonicalJSONV1
                    .isLowercaseSHA256(beforeScratchDigest),
                  StoreMigrationCanonicalJSONV1
                    .isLowercaseSHA256(afterScratchDigest) else {
                throw ScratchDataLeaseStoreFailureV1.invalidLease
            }
        }
    }

    fileprivate struct OriginalEraseExclusiveSourceCutV1 {
        let scratch: stat
        let operationsFact: String
        let operationsNames: [String]
        let scratchRootFact: String
        let scratchDigest: String
    }

    private static func originalEraseSourceFullFact(_ value: stat) -> String {
        "\(value.st_dev)|\(value.st_ino)|\(value.st_mode)|\(value.st_uid)|\(value.st_gid)|\(value.st_nlink)|\(value.st_size)|\(value.st_mtimespec.tv_sec)|\(value.st_mtimespec.tv_nsec)|\(value.st_ctimespec.tv_sec)|\(value.st_ctimespec.tv_nsec)"
    }

    @MainActor
    private func checkedOriginalEraseSourceCut()
        throws -> OriginalEraseExclusiveSourceCutV1 {
        try requireScratchDescriptorAccess()
        guard exclusiveNoRepairRead, let io = originalEraseSourceReceiptIO else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        try io.requireSettled()
        try authority.verify(rootName: Self.rootName)
        let operationsFD = authority.operationsDescriptor
        let rootFD = authority.rootDescriptor
        let operationsURL = rootURL.deletingLastPathComponent()
        var operations = stat(), namedOperations = stat(),
            scratch = stat(), namedScratch = stat()
        guard Darwin.fstat(operationsFD, &operations) == 0,
              Darwin.lstat(operationsURL.path, &namedOperations) == 0,
              Darwin.fstat(rootFD, &scratch) == 0,
              Darwin.fstatat(operationsFD, Self.rootName,
                  &namedScratch, AT_SYMLINK_NOFOLLOW) == 0,
              operations.st_mode & S_IFMT == S_IFDIR,
              scratch.st_mode & S_IFMT == S_IFDIR,
              Self.originalEraseSourceFullFact(operations)
                == Self.originalEraseSourceFullFact(namedOperations),
              Self.originalEraseSourceFullFact(scratch)
                == Self.originalEraseSourceFullFact(namedScratch) else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        let operationsNames = try io.names(in: operationsFD)
        guard operationsNames.contains(Self.rootName),
              try io.names(in: rootFD).isEmpty else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        let digest = try io.postRetiredTree(
            parent: operationsFD, name: Self.rootName)
        var operationsAfter = stat(), namedOperationsAfter = stat(),
            scratchAfter = stat(), namedScratchAfter = stat()
        guard Darwin.fstat(operationsFD, &operationsAfter) == 0,
              Darwin.lstat(operationsURL.path,
                  &namedOperationsAfter) == 0,
              Darwin.fstat(rootFD, &scratchAfter) == 0,
              Darwin.fstatat(operationsFD, Self.rootName,
                  &namedScratchAfter, AT_SYMLINK_NOFOLLOW) == 0,
              Self.originalEraseSourceFullFact(operationsAfter)
                == Self.originalEraseSourceFullFact(operations),
              Self.originalEraseSourceFullFact(namedOperationsAfter)
                == Self.originalEraseSourceFullFact(operations),
              Self.originalEraseSourceFullFact(scratchAfter)
                == Self.originalEraseSourceFullFact(scratch),
              Self.originalEraseSourceFullFact(namedScratchAfter)
                == Self.originalEraseSourceFullFact(scratch),
              try io.names(in: operationsFD) == operationsNames,
              try io.names(in: rootFD).isEmpty else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        try io.requireSettled()
        return OriginalEraseExclusiveSourceCutV1(
            scratch: scratch,
            operationsFact: Self.originalEraseSourceFullFact(operations),
            operationsNames: operationsNames,
            scratchRootFact: Self.originalEraseSourceFullFact(scratch),
            scratchDigest: digest)
    }

    /// Data-only admission for the original operation before any Scratch
    /// lifecycle effect. The already-held Support FD and checked Registry G
    /// are borrowed synchronously. This entry opens an existing root and
    /// observes policy; it never calls the ordinary repair-capable getters,
    /// creates a producer activity, or mints a deletion receipt.
    @MainActor
    static func requireOriginalEraseAuxiliaryScratchNoRepairFirstImage(
        applicationSupportURL: URL,
        support: Int32,
        expectedSupportFact: String,
        expectedOperationsFact: String,
        expectedOperationsNames: [String],
        expectedScratchRootFact: String,
        expectedScratchDigest: String,
        permit: OriginalEraseAuxiliaryScratchNoRepairPermitV1
    ) throws {
        try permit.requireHeld()
        var retainedStore: ScratchDataLeaseStoreV1?
        do {
            let store = try ScratchDataLeaseStoreV1(
                verifiedExistingTemporalRootAt: applicationSupportURL,
                clock: Date.init, checkedClose: true)
            retainedStore = store
            let io = EraseAbortCheckedSnapshotIOV1()
            store.originalEraseSourceReceiptIO = io
            try Self.filesystemLock.withLock {
                try permit.requireHeld()
                try io.requireSettled()
                try store.authority.verify(rootName: Self.rootName)
                let operations = store.authority.operationsDescriptor
                let scratch = store.authority.rootDescriptor
                func requireExactParents() throws {
                    var heldSupport = stat(), namedSupport = stat(),
                        heldOperations = stat(), namedOperations = stat(),
                        heldScratch = stat(), namedScratch = stat()
                    guard Darwin.fstat(support, &heldSupport) == 0,
                          Darwin.lstat(applicationSupportURL.path,
                              &namedSupport) == 0,
                          Darwin.fstat(operations, &heldOperations) == 0,
                          Darwin.fstatat(support,
                              OwnedStorageRootKindV1.operations.rawValue,
                              &namedOperations, AT_SYMLINK_NOFOLLOW) == 0,
                          Darwin.fstat(scratch, &heldScratch) == 0,
                          Darwin.fstatat(operations, Self.rootName,
                              &namedScratch, AT_SYMLINK_NOFOLLOW) == 0,
                          Self.originalEraseSourceFullFact(heldSupport)
                              == expectedSupportFact,
                          Self.originalEraseSourceFullFact(namedSupport)
                              == expectedSupportFact,
                          Self.originalEraseSourceFullFact(heldOperations)
                              == expectedOperationsFact,
                          Self.originalEraseSourceFullFact(namedOperations)
                              == expectedOperationsFact,
                          Self.originalEraseSourceFullFact(heldScratch)
                              == expectedScratchRootFact,
                          Self.originalEraseSourceFullFact(namedScratch)
                              == expectedScratchRootFact,
                          try io.names(in: operations)
                              == expectedOperationsNames else {
                        throw ScratchDataLeaseStoreFailureV1.invalidRoot
                    }
                }
                try requireExactParents()
                guard try io.postRetiredTree(parent: operations,
                        name: Self.rootName) == expectedScratchDigest else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                try requireExactParents()
                guard try io.postRetiredTree(parent: operations,
                        name: Self.rootName) == expectedScratchDigest else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                try requireExactParents()
                try io.requireSettled()
                try permit.requireHeld()
                store.originalEraseBorrowedLifetime = .closed
                try store.authority.closeCheckedForExclusiveOriginalEraseRead()
                try io.requireSettled()
            }
            retainedStore = nil
            try permit.requireHeld()
        } catch {
            if let retainedStore {
                Self.retainedExclusiveSourceStores.append(retainedStore)
            }
            permit.poisonOnUncertainCleanup()
            throw error
        }
    }

    /// One policy boundary for an already rostered ingress-control root. The
    /// caller's lexical permit comes from the original operation under its
    /// retained EX and checked G; the branch reproof excludes only this one
    /// root's setter-owned ctime, never a sibling or a new inode. No ordinary
    /// repair-capable getter is called here.
    @MainActor
    static func settleOriginalEraseAuxiliaryExistingControlPolicy(
        applicationSupportURL: URL,
        support: Int32,
        operations: Int32,
        expectedSupportFact: String,
        expectedOperationsFact: String,
        expectedOperationsNames: [String],
        firstControlFact: String?,
        firstControlDigest: String?,
        firstControlNodes:
            [EraseSchema2ColdAuxiliaryFirstObserverV1.ControlNode]?,
        retainedIO: EraseAbortCheckedSnapshotIOV1,
        operation: EraseRouterOperationV1,
        store: EraseIntentStore,
        registry: GenerationLeaseRegistryV1,
        exclusion: StoreTemporalNormalizationExclusionV1,
        activity: GenerationTemporalActivityHandleV1,
        permit: OriginalEraseAuxiliaryScratchControlPolicyPermitV1,
        reproveUnchangedBranches: () throws -> Void
    ) throws -> OriginalEraseScratchControlPolicyReceiptV1 {
        let name = "ProtectedIngressReceiptsV1"
        // The original Router operation must retain this owner before the
        // first open. A failed checked close may leave a live descriptor in it.
        let io = retainedIO
        let controlURL = applicationSupportURL
            .appendingPathComponent(OwnedStorageRootKindV1.operations.rawValue,
                isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        func requireParents() throws {
            try permit.requireHeld()
            var heldSupport = stat(), namedSupport = stat(),
                heldOperations = stat(), namedOperations = stat()
            guard Darwin.fstat(support, &heldSupport) == 0,
                  Darwin.lstat(applicationSupportURL.path, &namedSupport) == 0,
                  Darwin.fstat(operations, &heldOperations) == 0,
                  Darwin.fstatat(support,
                      OwnedStorageRootKindV1.operations.rawValue,
                      &namedOperations, AT_SYMLINK_NOFOLLOW) == 0,
                  originalEraseSourceFullFact(heldSupport) == expectedSupportFact,
                  originalEraseSourceFullFact(namedSupport) == expectedSupportFact,
                  originalEraseSourceFullFact(heldOperations) == expectedOperationsFact,
                  originalEraseSourceFullFact(namedOperations) == expectedOperationsFact,
                  try io.names(in: operations) == expectedOperationsNames else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            try reproveUnchangedBranches()
        }
        do {
            try requireParents()
            guard (firstControlFact == nil) == (firstControlDigest == nil),
                  (firstControlFact == nil) == (firstControlNodes == nil) else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            guard let firstControlFact, let firstControlDigest else {
                var absent = stat()
                guard Darwin.fstatat(operations, name, &absent,
                        AT_SYMLINK_NOFOLLOW) != 0,
                      errno == ENOENT else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                try requireParents()
                try io.requireSettled()
                return OriginalEraseScratchControlPolicyReceiptV1(
                    operation: operation, store: store, registry: registry,
                    exclusion: exclusion, activity: activity,
                    firstRootFact: nil, firstTreeDigest: nil,
                    projectedRootFact: nil, projectedTreeDigest: nil,
                    disposition: nil)
            }
            guard let firstControlNodes,
                  let firstRootNode = firstControlNodes.first(where: {
                      $0.path.isEmpty
                  }),
                  firstRootNode.fullFact == firstControlFact,
                  Set(firstControlNodes.map(\.path)).count
                    == firstControlNodes.count else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            func childFactsAndPolicies() throws
                -> [String: (String, TemporalPolicyObservationV1)] {
                var nodes: [EraseAbortCheckedSnapshotIOV1.CheckedTreeNode] = []
                _ = try io.postRetiredTree(parent: operations,
                    name: name, observeTypedNode: { node, _ in
                        nodes.append(node)
                    })
                var values: [String: (String,
                    TemporalPolicyObservationV1)] = [:]
                for node in nodes where !node.path.isEmpty {
                    let kind: OwnedFileKindV1 = node.sha256 == nil
                        ? .stagingDirectory : .temporaryFile
                    let url = controlURL.appendingPathComponent(node.path)
                    let observed = try ProtectedFilePolicyV1
                        .observeTemporalPolicyWithCheckedClose(
                            kind, at: url,
                            retainUncertainDescriptor: {
                                io.retainUncertainDescriptor($0)
                                permit.poisonOnUncertainEffect()
                            })
                    guard observed.device == UInt64(node.fact.st_dev),
                          observed.inode == UInt64(node.fact.st_ino),
                          observed.mode == UInt16(node.fact.st_mode),
                          observed.linkCount == UInt64(node.fact.st_nlink),
                          observed.backupExcluded == true,
                          observed.state == .strictComplete ||
                            observed.state == .pendingSimulatorRequest else {
                        throw ScratchDataLeaseStoreFailureV1.invalidRoot
                    }
                    values[node.path] = (
                        originalEraseSourceFullFact(node.fact), observed)
                }
                guard values.count + 1 == nodes.count else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                return values
            }
            let projected = try io.withOriginalEraseMainActorOpen(parent: operations, name: name,
                    flags: O_RDONLY | O_DIRECTORY)
                    { root -> (String, String,
                        ProtectedFileVerificationDispositionV1,
                        [String: (String,
                            TemporalPolicyObservationV1)], stat) in
                var requestWindow = false
                // Derive this projection only after the full immutable P tree
                // has been proved. It removes root metadata from the digest
                // solely for this setter-owned root ctime transition; every
                // descendant and the exact root names remain checked.
                guard try io.postRetiredTree(parent: operations, name: name)
                        == firstControlDigest else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                let stableControlDigest = try io.postRetiredTree(
                    parent: operations, name: name,
                    ignoringDirectoryMetadata: Set([""]))
                // These facts were frozen by the authentic P observer before
                // any auxiliary effect. No current child can become first.
                let firstChildren = try childFactsAndPolicies()
                guard firstChildren.count + 1 == firstControlNodes.count else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                for firstNode in firstControlNodes where !firstNode.path.isEmpty {
                    guard let current = firstChildren[firstNode.path],
                          current.0 == firstNode.fullFact,
                          current.1 == firstNode.policy else {
                        throw ScratchDataLeaseStoreFailureV1.invalidRoot
                    }
                }
                let firstRootPolicy = try ProtectedFilePolicyV1
                    .observeTemporalPolicyWithCheckedClose(
                        .stagingDirectory, at: controlURL,
                        retainUncertainDescriptor: {
                            io.retainUncertainDescriptor($0)
                            permit.poisonOnUncertainEffect()
                        })
                guard firstRootPolicy == firstRootNode.policy else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                @MainActor func requireRoot() throws -> (stat, String) {
                    try requireParents()
                    var held = stat(), named = stat()
                    guard Darwin.fstat(root, &held) == 0,
                          Darwin.fstatat(operations, name, &named,
                              AT_SYMLINK_NOFOLLOW) == 0,
                          held.st_mode & S_IFMT == S_IFDIR,
                          originalEraseSourceFullFact(held)
                            == originalEraseSourceFullFact(named),
                          held.st_dev == named.st_dev,
                          held.st_ino == named.st_ino else {
                        throw ScratchDataLeaseStoreFailureV1.invalidRoot
                    }
                    let fact = originalEraseSourceFullFact(held)
                    if !requestWindow && fact != firstControlFact {
                        throw ScratchDataLeaseStoreFailureV1.invalidRoot
                    }
                    if !requestWindow,
                       try io.postRetiredTree(parent: operations,
                            name: name) != firstControlDigest {
                        throw ScratchDataLeaseStoreFailureV1.invalidRoot
                    }
                    guard try io.postRetiredTree(parent: operations,
                            name: name,
                            ignoringDirectoryMetadata: Set([""]))
                            == stableControlDigest else {
                        throw ScratchDataLeaseStoreFailureV1.invalidRoot
                    }
                    let currentChildren = try childFactsAndPolicies()
                    guard currentChildren.count == firstChildren.count else {
                        throw ScratchDataLeaseStoreFailureV1.invalidRoot
                    }
                    for (path, firstChild) in firstChildren {
                        guard let current = currentChildren[path],
                              current.0 == firstChild.0,
                              current.1 == firstChild.1 else {
                            throw ScratchDataLeaseStoreFailureV1.invalidRoot
                        }
                    }
                    var heldAfter = stat(), namedAfter = stat()
                    guard Darwin.fstat(root, &heldAfter) == 0,
                          Darwin.fstatat(operations, name,
                              &namedAfter, AT_SYMLINK_NOFOLLOW) == 0,
                          originalEraseSourceFullFact(heldAfter) == fact,
                          originalEraseSourceFullFact(namedAfter) == fact else {
                        throw ScratchDataLeaseStoreFailureV1.invalidRoot
                    }
                    return (held, fact)
                }
                let (first, _) = try requireRoot()
                @MainActor func stableWitness() throws -> String {
                    let (current, _) = try requireRoot()
                    guard current.st_dev == first.st_dev,
                          current.st_ino == first.st_ino,
                          current.st_mode == first.st_mode,
                          current.st_uid == first.st_uid,
                          current.st_gid == first.st_gid,
                          current.st_nlink == first.st_nlink,
                          current.st_size == first.st_size,
                          current.st_mtimespec.tv_sec
                            == first.st_mtimespec.tv_sec,
                          current.st_mtimespec.tv_nsec
                            == first.st_mtimespec.tv_nsec else {
                        throw ScratchDataLeaseStoreFailureV1.invalidRoot
                    }
                    return "\(first.st_dev)|\(first.st_ino)|\(first.st_mode)|\(first.st_uid)|\(first.st_gid)|\(first.st_nlink)|\(first.st_size)|\(first.st_mtimespec.tv_sec)|\(first.st_mtimespec.tv_nsec)|\(stableControlDigest)"
                }
                let disposition = try ProtectedFilePolicyV1
                    .verifyEraseColdTemporalPolicyWithCheckedRequest(
                        .stagingDirectory, at: controlURL,
                        retainUncertainDescriptor: {
                            io.retainUncertainDescriptor($0)
                            permit.poisonOnUncertainEffect()
                        }, willRequestCompleteProtection: {
                            _ = try requireRoot()
                            requestWindow = true
                        }, unchangedWitness: stableWitness)
                let (final, finalFact) = try requireRoot()
                let finalDigest = try io.postRetiredTree(
                    parent: operations, name: name)
                try io.requireSettled()
                return (finalFact, finalDigest, disposition,
                    firstChildren, final)
            }
            // Reopen after the first checked close. A path replacement or
            // change following policy readback cannot become the receipt.
            func requireProjectedPostClose() throws {
            try io.withOriginalEraseMainActorOpen(parent: operations, name: name,
                    flags: O_RDONLY | O_DIRECTORY) { root in
                try requireParents()
                var held = stat(), named = stat()
                guard Darwin.fstat(root, &held) == 0,
                      Darwin.fstatat(operations, name, &named,
                          AT_SYMLINK_NOFOLLOW) == 0,
                      originalEraseSourceFullFact(held) == projected.0,
                      originalEraseSourceFullFact(named) == projected.0,
                      try io.postRetiredTree(parent: operations,
                          name: name) == projected.1 else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                let children = try childFactsAndPolicies()
                guard children.count == projected.3.count else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                for (path, firstChild) in projected.3 {
                    guard let current = children[path],
                          current.0 == firstChild.0,
                          current.1 == firstChild.1 else {
                        throw ScratchDataLeaseStoreFailureV1.invalidRoot
                    }
                }
                var heldAfter = stat(), namedAfter = stat()
                guard Darwin.fstat(root, &heldAfter) == 0,
                      Darwin.fstatat(operations, name,
                          &namedAfter, AT_SYMLINK_NOFOLLOW) == 0,
                      originalEraseSourceFullFact(heldAfter) == projected.0,
                      originalEraseSourceFullFact(namedAfter) == projected.0 else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
            }
            }
            try requireProjectedPostClose()
            let policy = try ProtectedFilePolicyV1
                .observeTemporalPolicyWithCheckedClose(
                    .stagingDirectory, at: controlURL,
                    retainUncertainDescriptor: {
                        io.retainUncertainDescriptor($0)
                        permit.poisonOnUncertainEffect()
                    })
            guard policy.device == UInt64(projected.4.st_dev),
                  policy.inode == UInt64(projected.4.st_ino),
                  policy.linkCount == UInt64(projected.4.st_nlink),
                  policy.mode == UInt16(projected.4.st_mode),
                  policy.isDirectory == true,
                  policy.backupExcluded == true,
                  policy.state == .strictComplete ||
                    (projected.2 == .simulatorFileProtectionUnsupported &&
                     policy.state == .pendingSimulatorRequest) else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            try requireProjectedPostClose()
            try requireParents()
            try io.requireSettled()
            return OriginalEraseScratchControlPolicyReceiptV1(
                operation: operation, store: store, registry: registry,
                exclusion: exclusion, activity: activity,
                firstRootFact: firstControlFact,
                firstTreeDigest: firstControlDigest,
                projectedRootFact: projected.0,
                projectedTreeDigest: projected.1,
                disposition: projected.2)
        } catch {
            permit.poisonOnUncertainEffect()
            throw error
        }
    }

    /// One policy boundary for the original first-P Notification root. The
    /// caller's lexical permit comes from the original operation under its
    /// retained EX and checked G; the branch reproof excludes only this one
    /// root's setter-owned ctime, never a sibling or a new inode. No ordinary
    /// repair-capable getter is called here.
    @MainActor
    static func settleOriginalEraseNotificationExistingRootPolicy(
        applicationSupportURL: URL,
        support: Int32,
        operations: Int32,
        expectedSupportFact: String,
        expectedOperationsFact: String,
        expectedOperationsNames: [String],
        firstControlFact: String?,
        firstControlDigest: String?,
        firstControlNodes:
            [EraseSchema2ColdAuxiliaryFirstObserverV1.ControlNode]?,
        retainedIO: EraseAbortCheckedSnapshotIOV1,
        operation: EraseRouterOperationV1,
        store: EraseIntentStore,
        registry: GenerationLeaseRegistryV1,
        exclusion: StoreTemporalNormalizationExclusionV1,
        activity: GenerationTemporalActivityHandleV1,
        permit: OriginalEraseNotificationRootPolicyPermitV1,
        reproveUnchangedBranches: (Bool) throws -> Void
    ) throws -> OriginalEraseNotificationRootPolicyReceiptV1 {
        let name = AppLockNotificationControlStoreV1.rootName
        // The original Router operation must retain this owner before the
        // first open. A failed checked close may leave a live descriptor in it.
        let io = retainedIO
        let controlURL = applicationSupportURL
            .appendingPathComponent(OwnedStorageRootKindV1.operations.rawValue,
                isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        var requestWindow = false
        func requireParents() throws {
            try permit.requireHeld()
            var heldSupport = stat(), namedSupport = stat(),
                heldOperations = stat(), namedOperations = stat()
            guard Darwin.fstat(support, &heldSupport) == 0,
                  Darwin.lstat(applicationSupportURL.path, &namedSupport) == 0,
                  Darwin.fstat(operations, &heldOperations) == 0,
                  Darwin.fstatat(support,
                      OwnedStorageRootKindV1.operations.rawValue,
                      &namedOperations, AT_SYMLINK_NOFOLLOW) == 0,
                  originalEraseSourceFullFact(heldSupport) == expectedSupportFact,
                  originalEraseSourceFullFact(namedSupport) == expectedSupportFact,
                  originalEraseSourceFullFact(heldOperations) == expectedOperationsFact,
                  originalEraseSourceFullFact(namedOperations) == expectedOperationsFact,
                  try io.names(in: operations) == expectedOperationsNames else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            try reproveUnchangedBranches(requestWindow)
        }
        do {
            try requireParents()
            guard (firstControlFact == nil) == (firstControlDigest == nil),
                  (firstControlFact == nil) == (firstControlNodes == nil) else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            guard let firstControlFact, let firstControlDigest else {
                // The absent-root creation protocol is a separate typed
                // effect; no observed empty namespace authorizes mkdir.
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            guard let firstControlNodes,
                  let firstRootNode = firstControlNodes.first(where: {
                      $0.path.isEmpty
                  }),
                  firstRootNode.fullFact == firstControlFact,
                  Set(firstControlNodes.map(\.path)).count
                    == firstControlNodes.count else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            func childFactsAndPolicies(root: Int32) throws
                -> [String: (String, TemporalPolicyObservationV1)] {
                var heldRoot = stat(), namedRoot = stat()
                guard Darwin.fstat(root, &heldRoot) == 0,
                      Darwin.fstatat(operations, name, &namedRoot,
                          AT_SYMLINK_NOFOLLOW) == 0,
                      originalEraseSourceFullFact(heldRoot)
                        == originalEraseSourceFullFact(namedRoot),
                      heldRoot.st_mode & S_IFMT == S_IFDIR,
                      UInt64(heldRoot.st_dev)
                        == firstRootNode.policy.device,
                      UInt64(heldRoot.st_ino)
                        == firstRootNode.policy.inode else {
                    throw AppAccessContractFailureV1
                        .notificationReconciliationRequired
                }
                let heldFact = originalEraseSourceFullFact(heldRoot)
                if !requestWindow && heldFact != firstControlFact {
                    throw AppAccessContractFailureV1
                        .notificationReconciliationRequired
                }
                if requestWindow {
                    let firstFields = firstControlFact.split(separator: "|",
                        omittingEmptySubsequences: false)
                    let heldFields = heldFact.split(separator: "|",
                        omittingEmptySubsequences: false)
                    guard firstFields.count == 11, heldFields.count == 11,
                          Array(firstFields.prefix(9))
                            == Array(heldFields.prefix(9)) else {
                        throw AppAccessContractFailureV1
                            .notificationReconciliationRequired
                    }
                }
                var nodes: [EraseAbortCheckedSnapshotIOV1.CheckedTreeNode] = []
                _ = try io.postRetiredTree(parent: operations,
                    name: name, observeTypedNode: { node, _ in
                        nodes.append(node)
                    })
                var values: [String: (String,
                    TemporalPolicyObservationV1)] = [:]
                for node in nodes where !node.path.isEmpty {
                    // The first-P Notification grammar permits only direct
                    // regular leaves. Keep the child FD pinned while its
                    // URL policy is observed, with full held/named facts on
                    // both sides of that separate checked policy read.
                    guard !node.path.contains("/"), node.sha256 != nil else {
                        throw AppAccessContractFailureV1
                            .notificationReconciliationRequired
                    }
                    let kind: OwnedFileKindV1 =
                        node.path.hasSuffix(".pending.json")
                            ? .journalTemporary : .journal
                    let url = controlURL.appendingPathComponent(node.path)
                    values[node.path] = try io.withOpen(parent: root,
                        name: node.path, flags: O_RDONLY | O_NONBLOCK) {
                        descriptor in
                        func requireChild() throws {
                            var held = stat(), named = stat()
                            guard Darwin.fstat(descriptor, &held) == 0,
                                  Darwin.fstatat(root, node.path,
                                      &named, AT_SYMLINK_NOFOLLOW) == 0,
                                  originalEraseSourceFullFact(held)
                                    == originalEraseSourceFullFact(node.fact),
                                  originalEraseSourceFullFact(named)
                                    == originalEraseSourceFullFact(node.fact),
                                  held.st_mode & S_IFMT == S_IFREG,
                                  held.st_nlink == 1 else {
                                throw AppAccessContractFailureV1
                                    .notificationReconciliationRequired
                            }
                        }
                        try requireChild()
                        let observed = try ProtectedFilePolicyV1
                            .observeTemporalPolicyWithCheckedClose(
                                kind, at: url,
                                retainUncertainDescriptor: {
                                    io.retainUncertainDescriptor($0)
                                    permit.poisonOnUncertainEffect()
                                })
                        guard observed.device == UInt64(node.fact.st_dev),
                              observed.inode == UInt64(node.fact.st_ino),
                              observed.mode == UInt16(node.fact.st_mode),
                              observed.linkCount == UInt64(node.fact.st_nlink),
                              observed.backupExcluded == true,
                              observed.state == .strictComplete ||
                                observed.state == .pendingSimulatorRequest else {
                            throw AppAccessContractFailureV1
                                .notificationReconciliationRequired
                        }
                        try requireChild()
                        return (originalEraseSourceFullFact(node.fact),
                            observed)
                    }
                }
                guard values.count + 1 == nodes.count else {
                    throw AppAccessContractFailureV1.notificationReconciliationRequired
                }
                var finalRoot = stat(), finalNamedRoot = stat()
                guard Darwin.fstat(root, &finalRoot) == 0,
                      Darwin.fstatat(operations, name, &finalNamedRoot,
                          AT_SYMLINK_NOFOLLOW) == 0,
                      originalEraseSourceFullFact(finalRoot) == heldFact,
                      originalEraseSourceFullFact(finalNamedRoot)
                        == heldFact else {
                    throw AppAccessContractFailureV1
                        .notificationReconciliationRequired
                }
                return values
            }
            let projected = try io.withOriginalEraseMainActorOpen(parent: operations, name: name,
                    flags: O_RDONLY | O_DIRECTORY)
                    { root -> (String, String,
                        ProtectedFileVerificationDispositionV1,
                        [String: (String,
                            TemporalPolicyObservationV1)], stat) in
                // Derive this projection only after the full immutable P tree
                // has been proved. It removes root metadata from the digest
                // solely for this setter-owned root ctime transition; every
                // descendant and the exact root names remain checked.
                guard try io.postRetiredTree(parent: operations, name: name)
                        == firstControlDigest else {
                    throw AppAccessContractFailureV1.notificationReconciliationRequired
                }
                let stableControlDigest = try io.postRetiredTree(
                    parent: operations, name: name,
                    ignoringDirectoryMetadata: Set([""]))
                // These facts were frozen by the authentic P observer before
                // any auxiliary effect. No current child can become first.
                let firstChildren = try childFactsAndPolicies(root: root)
                guard firstChildren.count + 1 == firstControlNodes.count else {
                    throw AppAccessContractFailureV1.notificationReconciliationRequired
                }
                for firstNode in firstControlNodes where !firstNode.path.isEmpty {
                    guard let current = firstChildren[firstNode.path],
                          current.0 == firstNode.fullFact,
                          current.1 == firstNode.policy else {
                        throw AppAccessContractFailureV1.notificationReconciliationRequired
                    }
                }
                let firstRootPolicy = try ProtectedFilePolicyV1
                    .observeTemporalPolicyWithCheckedClose(
                        .stagingDirectory, at: controlURL,
                        retainUncertainDescriptor: {
                            io.retainUncertainDescriptor($0)
                            permit.poisonOnUncertainEffect()
                        })
                guard firstRootPolicy == firstRootNode.policy else {
                    throw AppAccessContractFailureV1.notificationReconciliationRequired
                }
                @MainActor func requireRoot() throws -> (stat, String) {
                    try requireParents()
                    var held = stat(), named = stat()
                    guard Darwin.fstat(root, &held) == 0,
                          Darwin.fstatat(operations, name, &named,
                              AT_SYMLINK_NOFOLLOW) == 0,
                          held.st_mode & S_IFMT == S_IFDIR,
                          originalEraseSourceFullFact(held)
                            == originalEraseSourceFullFact(named),
                          held.st_dev == named.st_dev,
                          held.st_ino == named.st_ino else {
                        throw AppAccessContractFailureV1.notificationReconciliationRequired
                    }
                    let fact = originalEraseSourceFullFact(held)
                    if !requestWindow && fact != firstControlFact {
                        throw AppAccessContractFailureV1.notificationReconciliationRequired
                    }
                    if !requestWindow,
                       try io.postRetiredTree(parent: operations,
                            name: name) != firstControlDigest {
                        throw AppAccessContractFailureV1.notificationReconciliationRequired
                    }
                    guard try io.postRetiredTree(parent: operations,
                            name: name,
                            ignoringDirectoryMetadata: Set([""]))
                            == stableControlDigest else {
                        throw AppAccessContractFailureV1.notificationReconciliationRequired
                    }
                    let currentChildren = try childFactsAndPolicies(
                        root: root)
                    guard currentChildren.count == firstChildren.count else {
                        throw AppAccessContractFailureV1.notificationReconciliationRequired
                    }
                    for (path, firstChild) in firstChildren {
                        guard let current = currentChildren[path],
                              current.0 == firstChild.0,
                              current.1 == firstChild.1 else {
                            throw AppAccessContractFailureV1.notificationReconciliationRequired
                        }
                    }
                    var heldAfter = stat(), namedAfter = stat()
                    guard Darwin.fstat(root, &heldAfter) == 0,
                          Darwin.fstatat(operations, name,
                              &namedAfter, AT_SYMLINK_NOFOLLOW) == 0,
                          originalEraseSourceFullFact(heldAfter) == fact,
                          originalEraseSourceFullFact(namedAfter) == fact else {
                        throw AppAccessContractFailureV1.notificationReconciliationRequired
                    }
                    return (held, fact)
                }
                let (first, _) = try requireRoot()
                @MainActor func stableWitness() throws -> String {
                    let (current, _) = try requireRoot()
                    guard current.st_dev == first.st_dev,
                          current.st_ino == first.st_ino,
                          current.st_mode == first.st_mode,
                          current.st_uid == first.st_uid,
                          current.st_gid == first.st_gid,
                          current.st_nlink == first.st_nlink,
                          current.st_size == first.st_size,
                          current.st_mtimespec.tv_sec
                            == first.st_mtimespec.tv_sec,
                          current.st_mtimespec.tv_nsec
                            == first.st_mtimespec.tv_nsec else {
                        throw AppAccessContractFailureV1.notificationReconciliationRequired
                    }
                    return "\(first.st_dev)|\(first.st_ino)|\(first.st_mode)|\(first.st_uid)|\(first.st_gid)|\(first.st_nlink)|\(first.st_size)|\(first.st_mtimespec.tv_sec)|\(first.st_mtimespec.tv_nsec)|\(stableControlDigest)"
                }
                let disposition = try ProtectedFilePolicyV1
                    .verifyEraseColdTemporalPolicyWithCheckedRequest(
                        .stagingDirectory, at: controlURL,
                        retainUncertainDescriptor: {
                            io.retainUncertainDescriptor($0)
                            permit.poisonOnUncertainEffect()
                        }, willRequestCompleteProtection: {
                            _ = try requireRoot()
                            requestWindow = true
                        }, unchangedWitness: stableWitness)
                let (final, finalFact) = try requireRoot()
                let finalDigest = try io.postRetiredTree(
                    parent: operations, name: name)
                try io.requireSettled()
                return (finalFact, finalDigest, disposition,
                    firstChildren, final)
            }
            // Reopen after the first checked close. A path replacement or
            // change following policy readback cannot become the receipt.
            func requireProjectedPostClose() throws {
            try io.withOriginalEraseMainActorOpen(parent: operations, name: name,
                    flags: O_RDONLY | O_DIRECTORY) { root in
                try requireParents()
                var held = stat(), named = stat()
                guard Darwin.fstat(root, &held) == 0,
                      Darwin.fstatat(operations, name, &named,
                          AT_SYMLINK_NOFOLLOW) == 0,
                      originalEraseSourceFullFact(held) == projected.0,
                      originalEraseSourceFullFact(named) == projected.0,
                      try io.postRetiredTree(parent: operations,
                          name: name) == projected.1 else {
                    throw AppAccessContractFailureV1.notificationReconciliationRequired
                }
                let children = try childFactsAndPolicies(root: root)
                guard children.count == projected.3.count else {
                    throw AppAccessContractFailureV1.notificationReconciliationRequired
                }
                for (path, firstChild) in projected.3 {
                    guard let current = children[path],
                          current.0 == firstChild.0,
                          current.1 == firstChild.1 else {
                        throw AppAccessContractFailureV1.notificationReconciliationRequired
                    }
                }
                var heldAfter = stat(), namedAfter = stat()
                guard Darwin.fstat(root, &heldAfter) == 0,
                      Darwin.fstatat(operations, name,
                          &namedAfter, AT_SYMLINK_NOFOLLOW) == 0,
                      originalEraseSourceFullFact(heldAfter) == projected.0,
                      originalEraseSourceFullFact(namedAfter) == projected.0 else {
                    throw AppAccessContractFailureV1.notificationReconciliationRequired
                }
            }
            }
            try requireProjectedPostClose()
            let policy = try ProtectedFilePolicyV1
                .observeTemporalPolicyWithCheckedClose(
                    .stagingDirectory, at: controlURL,
                    retainUncertainDescriptor: {
                        io.retainUncertainDescriptor($0)
                        permit.poisonOnUncertainEffect()
                    })
            guard policy.device == UInt64(projected.4.st_dev),
                  policy.inode == UInt64(projected.4.st_ino),
                  policy.linkCount == UInt64(projected.4.st_nlink),
                  policy.mode == UInt16(projected.4.st_mode),
                  policy.isDirectory == true,
                  policy.backupExcluded == true,
                  policy.state == .strictComplete ||
                    (projected.2 == .simulatorFileProtectionUnsupported &&
                     policy.state == .pendingSimulatorRequest) else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            try requireProjectedPostClose()
            try requireParents()
            try io.requireSettled()
            return OriginalEraseNotificationRootPolicyReceiptV1(
                operation: operation, store: store, registry: registry,
                exclusion: exclusion, activity: activity,
                firstRootFact: firstControlFact,
                firstTreeDigest: firstControlDigest,
                projectedRootFact: projected.0,
                projectedTreeDigest: projected.1,
                disposition: projected.2,
                didRequestCompleteProtection: requestWindow)
        } catch {
            permit.poisonOnUncertainEffect()
            throw error
        }
    }

    /// Used only within the original Erase Registry's synchronous G scope and
    /// already-held Support-root EX. No new producer SH or scratch recovery is
    /// permitted; any existing scratch member makes this read fail closed.
    // Only this file can erase the distinction after a typed entry point.
    // These cases retain the original revocable operation scope, not a new permit.
    @MainActor
    fileprivate enum ExclusiveEraseSourceReadPermit {
        case original(OriginalEraseExclusiveScratchPermitV1)
        case completedAbort(CompletedAbortExclusiveScratchPermitV1)

        func requireHeld() throws {
            switch self {
            case .original(let permit): try permit.requireHeld()
            case .completedAbort(let permit): try permit.requireHeld()
            }
        }

        func poisonOnUncertainCleanup() {
            switch self {
            case .original(let permit): permit.poisonOnUncertainCleanup()
            case .completedAbort(let permit): permit.poisonOnUncertainCleanup()
            }
        }
    }

    @MainActor
    static func withExclusiveOriginalEraseSourceRead<Value>(
        applicationSupportURL: URL,
        request: ScratchDataLeaseRequestV1,
        permit: OriginalEraseExclusiveScratchPermitV1,
        requireProtectedIngressUnchanged: @escaping @MainActor () throws -> Void,
        readerIsDrained: @escaping @MainActor () -> Bool,
        onCheckedSettlement: (@MainActor (
            OriginalEraseExclusiveSourceReadReceiptV1) -> Void)? = nil,
        diagnosticPhase: (@MainActor (String) -> Void)? = nil,
        _ read: (SourceReadDirectory) throws -> Value
    ) throws -> Value {
        try withExclusiveEraseSourceRead(
            applicationSupportURL: applicationSupportURL,
            request: request, permit: .original(permit),
            requireProtectedIngressUnchanged: requireProtectedIngressUnchanged,
            readerIsDrained: readerIsDrained,
            onCheckedSettlement: onCheckedSettlement,
            diagnosticPhase: diagnosticPhase, read)
    }

    @MainActor
    static func withExclusiveCompletedAbortSourceRead<Value>(
        applicationSupportURL: URL,
        request: ScratchDataLeaseRequestV1,
        permit: CompletedAbortExclusiveScratchPermitV1,
        requireProtectedIngressUnchanged: @escaping @MainActor () throws -> Void,
        readerIsDrained: @escaping @MainActor () -> Bool,
        _ read: (SourceReadDirectory) throws -> Value
    ) throws -> Value {
        try withExclusiveEraseSourceRead(
            applicationSupportURL: applicationSupportURL,
            request: request, permit: .completedAbort(permit),
            requireProtectedIngressUnchanged: requireProtectedIngressUnchanged,
            readerIsDrained: readerIsDrained, read)
    }

    @MainActor
    private static func withExclusiveEraseSourceRead<Value>(
        applicationSupportURL: URL,
        request: ScratchDataLeaseRequestV1,
        permit: ExclusiveEraseSourceReadPermit,
        requireProtectedIngressUnchanged: @escaping @MainActor () throws -> Void,
        readerIsDrained: @escaping @MainActor () -> Bool,
        onCheckedSettlement: (@MainActor (
            OriginalEraseExclusiveSourceReadReceiptV1) -> Void)? = nil,
        diagnosticPhase: (@MainActor (String) -> Void)? = nil,
        _ read: (SourceReadDirectory) throws -> Value
    ) throws -> Value {
#if DEBUG
        diagnosticPhase?("recovery.original.old.scratch.permit-enter")
#endif
        try permit.requireHeld()
        guard request.purpose == .source, request.owner == .source else {
            throw ScratchDataLeaseStoreFailureV1.invalidLease
        }
        try request.validate()
#if DEBUG
        diagnosticPhase?("recovery.original.old.scratch.permit-complete")
#endif
        if onCheckedSettlement != nil {
            guard case .original = permit else {
                throw ScratchDataLeaseStoreFailureV1.invalidLease
            }
        }
        // The sibling is owned by the original pre-authentication ingress
        // lifecycle. Its exact tree was sealed by the original Erase Service
        // before the fault; this read neither opens an ingress Store nor
        // requires a valid preexisting sibling to be absent.
#if DEBUG
        diagnosticPhase?("recovery.original.old.scratch.ingress-enter")
#endif
        try requireProtectedIngressUnchanged()
#if DEBUG
        diagnosticPhase?("recovery.original.old.scratch.ingress-complete")
#endif
        let store: ScratchDataLeaseStoreV1
        do {
#if DEBUG
        diagnosticPhase?("recovery.original.old.scratch.store-enter")
#endif
            store = try ScratchDataLeaseStoreV1(
                verifiedExistingTemporalRootAt: applicationSupportURL,
                clock: Date.init,
                capacityProvider: {
                    try $0.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                        .volumeAvailableCapacityForImportantUsage
                }, checkedClose: true)
        } catch {
            permit.poisonOnUncertainCleanup()
            throw error
        }
#if DEBUG
        diagnosticPhase?("recovery.original.old.scratch.store-complete")
#endif
        store.exclusiveNoRepairRead = true
        if onCheckedSettlement != nil {
            store.originalEraseSourceReceiptIO = EraseAbortCheckedSnapshotIOV1()
        }
        var directory: SourceReadDirectory?
        var cleanupProved = false
        do {
#if DEBUG
        diagnosticPhase?("recovery.original.old.scratch.lock-enter")
#endif
            return try Self.filesystemLock.withLock {
                try permit.requireHeld()
                try requireProtectedIngressUnchanged()
#if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.lock-complete")
#endif
#if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.first-cut-enter")
#endif
                let firstCut = try onCheckedSettlement.map { _ in
                    try store.checkedOriginalEraseSourceCut()
                }
#if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.first-cut-complete")
#endif
#if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.lease-enter")
#endif
                let lease = try store.acquireScratchLeaseSynchronously(
                    request, recoverExisting: false)
#if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.lease-complete")
#endif
#if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.directory-enter")
#endif
                directory = try SourceReadDirectory(
                    store: store, lease: lease,
                    readerIsDrained: readerIsDrained,
                    exclusivePermit: permit)
                guard let directory else { throw ScratchDataLeaseStoreFailureV1.invalidLease }
#if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.directory-complete")
#endif
#if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.metadata-enter")
#endif
                try directory.establishExclusiveOwnedMetadata()
#if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.metadata-complete")
#endif
#if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.callback-enter")
#endif
                let result = Result { try read(directory) }
#if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.callback-returned")
#endif
#if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.drain-enter")
#endif
                guard readerIsDrained() else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
#if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.drain-complete")
#endif
#if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.reader-close-enter")
#endif
                guard let ownedFiles = try directory.closeReaderScope() else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
#if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.reader-close-complete")
#endif
                let terminal: ScratchDataLeaseTerminalV1
                switch result {
                case .success: terminal = .completed
                case .failure: terminal = .failed
                }
#if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.release-enter")
#endif
                try store.releaseScratchLeaseSynchronously(
                    lease, terminal: terminal, exclusiveNoRepair: true,
                    exclusiveExpectedFiles: ownedFiles)
#if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.release-complete")
#endif
                try permit.requireHeld()
                guard store.active.isEmpty else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
#if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.final-cut-enter")
#endif
                let finalCut = try firstCut.map { _ in
                    try store.checkedOriginalEraseSourceCut()
                }
                if let firstCut, let finalCut {
                    guard firstCut.operationsFact == finalCut.operationsFact,
                          firstCut.operationsNames == finalCut.operationsNames,
                          firstCut.scratch.st_dev == finalCut.scratch.st_dev,
                          firstCut.scratch.st_ino == finalCut.scratch.st_ino,
                          firstCut.scratch.st_mode == finalCut.scratch.st_mode,
                          firstCut.scratch.st_uid == finalCut.scratch.st_uid,
                          firstCut.scratch.st_gid == finalCut.scratch.st_gid,
                          firstCut.scratch.st_nlink == finalCut.scratch.st_nlink else {
                        throw ScratchDataLeaseStoreFailureV1.invalidRoot
                    }
                }
#if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.final-cut-complete")
#endif
#if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.authority-close-enter")
#endif
                try store.authority.closeCheckedForExclusiveOriginalEraseRead()
#if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.authority-close-complete")
#endif
#if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.io-settle-enter")
#endif
                try store.originalEraseSourceReceiptIO?.requireSettled()
#if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.io-settle-complete")
#endif
                #if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.final-ingress-enter")
#endif
                try requireProtectedIngressUnchanged()
#if DEBUG
                diagnosticPhase?("recovery.original.old.scratch.final-ingress-complete")
#endif
                cleanupProved = true
                if case .success = result,
                   let firstCut, let finalCut, let onCheckedSettlement {
#if DEBUG
                    diagnosticPhase?("recovery.original.old.scratch.receipt-enter")
#endif
                    onCheckedSettlement(OriginalEraseExclusiveSourceReadReceiptV1(
                        request: request, leaseName: lease.relativeDirectory,
                        before: firstCut, after: finalCut))
                }
#if DEBUG
                if case .failure = result {
                    diagnosticPhase?("recovery.original.old.scratch.callback-failed")
                } else {
                    diagnosticPhase?("recovery.original.old.scratch.receipt-complete")
                }
#endif
                return try result.get()
            }
        } catch {
            // An uncertain close or cleanup remains pinned for process life;
            // the caller's original EX/G owner must also fail closed.
            if !cleanupProved {
                if let directory { Self.retainedSourceReaders.append(directory) }
                Self.retainedExclusiveSourceStores.append(store)
                permit.poisonOnUncertainCleanup()
            }
            throw error
        }
    }

    @MainActor
    func withSourceReadScratch<Value>(request: ScratchDataLeaseRequestV1,
        readerIsDrained: @escaping @MainActor () -> Bool,
        _ read: (SourceReadDirectory) throws -> Value) throws -> Value {
        try requireScratchDescriptorAccess()
        guard request.purpose == .source, request.owner == .source else {
            throw ScratchDataLeaseStoreFailureV1.invalidLease
        }
        try request.validate()
        return try withProducerFilesystemLock {
            for prior in Self.retainedSourceReaders where prior.readerIsDrained() {
                _ = try prior.closeReaderScope()
                try prior.store.releaseScratchLeaseSynchronously(prior.lease, terminal: .failed)
            }
            Self.retainedSourceReaders.removeAll { $0.readerIsDrained() }
            let lease = try acquireScratchLeaseSynchronously(request)
            let directory: SourceReadDirectory
            do { directory = try SourceReadDirectory(store: self, lease: lease, readerIsDrained: readerIsDrained) }
            catch { try releaseScratchLeaseSynchronously(lease, terminal: .failed); throw error }
            let result = Result { try read(directory) }
            guard readerIsDrained() else {
                Self.retainedSourceReaders.append(directory)
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            _ = try directory.closeReaderScope()
            let terminal: ScratchDataLeaseTerminalV1
            switch result { case .success: terminal = .completed; case .failure: terminal = .failed }
            try releaseScratchLeaseSynchronously(lease, terminal: terminal)
            return try result.get()
        }
    }

    func acquireScratchLease(
        _ request: ScratchDataLeaseRequestV1
    ) async throws -> ScratchDataLeaseV1 {
        try requireScratchDescriptorAccess()
        return try withProducerFilesystemLock {
            let lease = try acquireScratchLeaseSynchronously(request)
            if producerActivities[lease.request.leaseID] == nil {
                producerActivities[lease.request.leaseID] = try OwnedStorageProducerActivityV1.acquire(
                    applicationSupportURL: producerApplicationSupportURL)
            }
            return lease
        }
    }

    private func acquireScratchLeaseSynchronously(
        _ request: ScratchDataLeaseRequestV1,
        recoverExisting: Bool = true
    ) throws -> ScratchDataLeaseV1 {
        try requireScratchDescriptorAccess()
        try request.validate()
        let current = clock()
        guard request.createdAt <= current, current < request.expiresAt else {
            throw ScratchDataLeaseStoreFailureV1.invalidLease
        }
        if recoverExisting {
            _ = try recoverScratchLeaseState()
        } else {
            try verifyRoot()
            guard active.isEmpty,
                  try directoryNames(authority.rootDescriptor).isEmpty else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        }
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
            var leaseDescriptor = try openLeaseDirectory(name)
            var closeAttempted = false
            defer {
                if leaseDescriptor >= 0 && !closeAttempted {
                    if recoverExisting { _ = Darwin.close(leaseDescriptor) }
                    else {
                        let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(leaseDescriptor)
                        if Darwin.close(leaseDescriptor) == 0 {
                            ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
                        }
                    }
                }
            }
            try applySourceReadPolicy(
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
            if !recoverExisting {
                let owned = leaseDescriptor
                closeAttempted = true
                let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(owned)
                guard Darwin.close(owned) == 0 else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
                leaseDescriptor = -1
            }
            return lease
        } catch let failure as ProtectedFilePolicyError
            where failure == .protectedDataUnavailable {
            if createdDirectory && recoverExisting { try? removeLeaseDirectory(named: name) }
            throw ScratchDataLeaseStoreFailureV1.protectedDataUnavailable
        } catch let failure as ScratchDataLeaseStoreFailureV1 {
            if createdDirectory && recoverExisting { try? removeLeaseDirectory(named: name) }
            throw failure
        } catch {
            if createdDirectory && recoverExisting { try? removeLeaseDirectory(named: name) }
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
    }

    func writeScratchData(
        _ data: Data,
        named: String,
        lease: ScratchDataLeaseV1
    ) async throws -> URL {
        try requireScratchDescriptorAccess()
        return try withProducerFilesystemLock {
            try writeScratchDataSynchronously(data, named: named, lease: lease)
        }
    }

    private func writeScratchDataSynchronously(
        _ data: Data,
        named: String,
        lease: ScratchDataLeaseV1
    ) throws -> URL {
        try requireScratchDescriptorAccess()
        guard OperationalDiagnosticsBoundsV1.validRelativeName(named),
              named != Self.metadataName,
              active[lease.request.leaseID] == lease else {
            throw ScratchDataLeaseStoreFailureV1.invalidLease
        }
        guard clock() < lease.request.expiresAt else {
            try releaseScratchLeaseSynchronously(lease, terminal: .recoveredExpired)
            throw ScratchDataLeaseStoreFailureV1.leaseExpired
        }
        let directory = rootURL.appendingPathComponent(
            lease.relativeDirectory,
            isDirectory: true
        )
        let leaseDescriptor = try openLeaseDirectory(lease.relativeDirectory)
        defer { _ = Darwin.close(leaseDescriptor) }
        try requireExpectedScratchLease(lease, named: lease.relativeDirectory, descriptor: leaseDescriptor)
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
        try requireScratchDescriptorAccess()
        try withProducerFilesystemLock {
            try releaseScratchLeaseSynchronously(lease, terminal: terminal)
            producerActivities.removeValue(forKey: lease.request.leaseID)?.close()
        }
    }

    private func releaseScratchLeaseSynchronously(
        _ lease: ScratchDataLeaseV1,
        terminal: ScratchDataLeaseTerminalV1,
        exclusiveNoRepair: Bool = false,
        exclusiveExpectedFiles: [C16IngressHygieneFileIdentityV1]? = nil
    ) throws {
        try requireScratchDescriptorAccess()
        try verifyRoot()
        try lease.request.validate()
        guard lease.schemaVersion == ScratchDataLeaseV1.schemaVersion,
              lease.relativeDirectory == Self.leaseDirectoryName(for: lease.request) else {
            throw ScratchDataLeaseStoreFailureV1.invalidLease
        }
        // A different owner may have removed and reused a cached lease's ID.
        // Release is bound to the caller's value before any recovery can mutate it.
        if !exclusiveNoRepair,
           try removeIngressScratchLeaseIfOwned(named: lease.relativeDirectory, expectedLease: lease) {
            active.removeValue(forKey: lease.request.leaseID)
            return
        }
        if exclusiveNoRepair {
            guard exclusiveExpectedFiles != nil,
                  try directoryInformationIfPresent(named: lease.relativeDirectory) != nil else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        }
        if try directoryInformationIfPresent(named: lease.relativeDirectory) == nil,
           try directoryInformationIfPresent(named: Self.deletionTombstoneName(for: lease.relativeDirectory)) == nil {
            active.removeValue(forKey: lease.request.leaseID)
            return
        }
        _ = terminal
        try removeLeaseDirectory(named: lease.relativeDirectory,
            expectedLease: lease, exclusiveNoRepair: exclusiveNoRepair,
            exclusiveExpectedFiles: exclusiveExpectedFiles)
        active.removeValue(forKey: lease.request.leaseID)
    }

    func recoverScratchLeases() async throws -> ScratchDataLeaseRecoverySummaryV1 {
        try requireScratchDescriptorAccess()
        return try withProducerFilesystemLock {
            try recoverScratchLeasesSynchronously()
        }
    }

    private func recoverScratchLeasesSynchronously() throws -> ScratchDataLeaseRecoverySummaryV1 {
        try requireScratchDescriptorAccess()
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
        try requireScratchDescriptorAccess()
        try verifyRoot()
        try resumePreparedScratchHygiene()
        let ingressRecovery = try recoverUnpublishedIngressForScratchLifecycle()
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
        var expiredCount = ingressRecovery.expiredCount
        var removedByteCount = ingressRecovery.removedBytes
        for childName in children {
            if ingressRecovery.retainedNames.contains(childName) { continue }
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
                guard flock(leaseDescriptor, LOCK_SH | LOCK_NB) == 0 else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
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
        try requireScratchDescriptorAccess()
        try withProducerFilesystemLock {
            try resetScratchDataSynchronously()
        }
    }

    private func resetScratchDataSynchronously() throws {
        try requireScratchDescriptorAccess()
        try settleScratchIngressAndHygieneBeforeLeaseDeletion()
        for child in try directoryNames(authority.rootDescriptor) {
            if Self.isDeletionTombstone(child) {
                try removeDeletionTombstone(named: child)
            } else {
                try removeLeaseDirectory(named: child)
            }
        }
        active.removeAll(keepingCapacity: false)
    }

    /// The ordinary reset and the retained original route share exactly this
    /// C16 ordering. The original route supplies its own durable prefix proof
    /// before using the semantic continuation; no lease deletion is selected
    /// by a fresh survivor scan during original replay.
    private func settleScratchIngressAndHygieneBeforeLeaseDeletion() throws {
        try requireScratchDescriptorAccess()
        try verifyRoot()
        try eraseScratchIngressControl(resumeOnly: true)
        if try hasExistingIngressControl() {
            try resumePreparedScratchHygiene()
            try resumeIngressErasesForScratchLifecycle()
            try eraseProtectedIngress(
                operationID: originalEraseOperationID ?? UUID())
        }
    }

    func eraseScratchData() async throws {
        try requireScratchDescriptorAccess()
        try withProducerFilesystemLock {
            try eraseScratchDataSynchronously()
        }
    }

    private func eraseScratchDataSynchronously() throws {
        try requireScratchDescriptorAccess()
        try resetScratchDataSynchronously()
        try eraseScratchIngressControl(resumeOnly: false)
        try verifyRoot()
        guard Darwin.unlinkat(
            authority.operationsDescriptor,
            Self.rootName,
            AT_REMOVEDIR
        ) == 0,
        Darwin.fsync(authority.operationsDescriptor) == 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        if originalEraseBorrowedExclusiveCheck != nil {
            try originalEraseBorrowedExclusiveCheck?()
            var named = stat()
            guard Darwin.fstatat(authority.operationsDescriptor, Self.rootName,
                &named, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            originalEraseRootRemovalProved = true
        }
        active.removeAll(keepingCapacity: false)
    }

    private func payloadByteCount(
        directoryDescriptor: Int32,
        directoryURL: URL
    ) throws -> UInt64 {
        try requireScratchDescriptorAccess()
        var total: UInt64 = 0
        for name in try directoryNames(directoryDescriptor)
        where name != Self.metadataName {
            let information = try regularFileInformation(
                named: name,
                directoryDescriptor: directoryDescriptor
            )
            try verifySourceReadPolicy(
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
        try requireScratchDescriptorAccess()
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

    private func requireExpectedScratchLease(
        _ expected: ScratchDataLeaseV1, named name: String, descriptor: Int32
    ) throws {
        try requireScratchDescriptorAccess()
        try verifyLeaseDirectory(name, descriptor: descriptor)
        let metadata = rootURL.appendingPathComponent(name).appendingPathComponent(Self.metadataName)
        try verifySourceReadPolicy(.temporaryFile, at: metadata)
        let before = try regularFileInformation(named: Self.metadataName, directoryDescriptor: descriptor)
        let data = try readRegularFile(named: Self.metadataName, directoryDescriptor: descriptor, maximumBytes: 65_536)
        let after = try regularFileInformation(named: Self.metadataName, directoryDescriptor: descriptor)
        guard try canonicalData(expected) == data,
              C16IngressHygieneFileIdentityV1(name: Self.metadataName, information: before)
                == C16IngressHygieneFileIdentityV1(name: Self.metadataName, information: after) else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try verifyLeaseDirectory(name, descriptor: descriptor)
    }

    private func removeLeaseDirectory(
        named name: String, expectedLease: ScratchDataLeaseV1? = nil,
        exclusiveNoRepair: Bool = false,
        exclusiveExpectedFiles: [C16IngressHygieneFileIdentityV1]? = nil
    ) throws {
        try requireScratchDescriptorAccess()
        guard Self.isLeaseDirectoryName(name) else {
            throw ScratchDataLeaseStoreFailureV1.invalidLease
        }
        try verifyRoot()
        if !exclusiveNoRepair,
           try removeIngressScratchLeaseIfOwned(named: name, expectedLease: expectedLease) { return }
        try requireNoUnfinishedHygieneTarget(named: name)
        let tombstone = Self.deletionTombstoneName(for: name)
        if try directoryInformationIfPresent(named: name) == nil {
            if exclusiveNoRepair { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            guard try directoryInformationIfPresent(named: tombstone) != nil else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            try removeDeletionTombstone(named: tombstone, expectedLease: expectedLease)
            return
        }
        guard try directoryInformationIfPresent(named: tombstone) == nil else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        let descriptor = try openLeaseDirectory(name)
        var closeAttempted = false
        defer {
            if !closeAttempted {
                if exclusiveNoRepair {
                    let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(descriptor)
                    if Darwin.close(descriptor) == 0 {
                        ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
                    }
                } else { _ = Darwin.close(descriptor) }
            }
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        if let expectedLease {
            try requireExpectedScratchLease(expectedLease, named: name, descriptor: descriptor)
        }
        if exclusiveNoRepair {
            guard let exclusiveExpectedFiles else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            try requireExclusiveExpectedChildren(
                exclusiveExpectedFiles, descriptor: descriptor)
        }
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
        try deletePinnedDirectory(named: tombstone, descriptor: descriptor,
            expectedFiles: exclusiveExpectedFiles,
            exclusiveNoRepair: exclusiveNoRepair)
        if exclusiveNoRepair {
            closeAttempted = true
            let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(descriptor)
            guard Darwin.close(descriptor) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
        }
    }

    /// An original-Erase lease transaction starts only after the retained
    /// first-P roster and sidecar have frozen this exact lease, child order and
    /// operation. The callback proves every *current* cut against those
    /// immutable facts under the same EX/G; this adapter performs the sole
    /// physical mutation. A fresh process may resume a contiguous tombstone
    /// prefix even after `lease.json` was already unlinked.
    @MainActor
    func eraseOriginalFrozenLease(
        originalName: String,
        expectedDevice: UInt64,
        expectedInode: UInt64,
        orderedChildren: [String],
        requirePrefix: @MainActor (Bool, Int, Bool) throws -> Void
    ) throws {
        try requireScratchDescriptorAccess()
        guard originalEraseBorrowedExclusiveCheck != nil,
              exclusiveNoRepairRead,
              Self.isLeaseDirectoryName(originalName),
              expectedDevice == authority.rootDevice,
              expectedInode > 0,
              !orderedChildren.isEmpty,
              orderedChildren.count <= 128,
              orderedChildren == orderedChildren.sorted(),
              Set(orderedChildren).count == orderedChildren.count,
              orderedChildren.allSatisfy({
                  OperationalDiagnosticsBoundsV1.validRelativeName($0)
              }) else {
            throw ScratchDataLeaseStoreFailureV1.invalidLease
        }
        let tombstone = Self.deletionTombstoneName(for: originalName)
        try originalEraseBorrowedExclusiveCheck?()
        try verifyRoot()
        let original = try directoryInformationIfPresent(named: originalName)
        let deleting = try directoryInformationIfPresent(named: tombstone)
        guard original == nil || deleting == nil else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        guard original != nil || deleting != nil else {
            try requireOriginalEraseBorrowedOwner()
            try requirePrefix(true, orderedChildren.count, true)
            try requireOriginalEraseBorrowedOwner()
            return
        }
        let name = deleting == nil ? originalName : tombstone
        let descriptor = try openLeaseDirectory(name)
        try withObservedScratchDescriptor(descriptor) { descriptor in
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            var held = stat()
            guard Darwin.fstat(descriptor, &held) == 0,
                  UInt64(held.st_dev) == expectedDevice,
                  UInt64(held.st_ino) == expectedInode else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            try verifySourceReadPolicy(.stagingDirectory,
                at: rootURL.appendingPathComponent(name))
            var removedCount = 0
            if deleting == nil {
                guard try directoryNames(descriptor) == orderedChildren else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                try requireOriginalEraseBorrowedOwner()
                try requirePrefix(false, 0, false)
                try requireOriginalEraseBorrowedOwner()
                try originalEraseBorrowedExclusiveCheck?()
                try verifyLeaseDirectory(originalName,
                    descriptor: descriptor)
                guard Darwin.renameat(authority.rootDescriptor,
                    originalName, authority.rootDescriptor, tombstone) == 0,
                    Darwin.fsync(authority.rootDescriptor) == 0 else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                try verifyLeaseDirectory(tombstone,
                    descriptor: descriptor)
                try requireOriginalEraseBorrowedOwner()
                try requirePrefix(true, 0, false)
                try requireOriginalEraseBorrowedOwner()
            } else {
                let survivors = try directoryNames(descriptor)
                guard survivors.count <= orderedChildren.count else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                removedCount = orderedChildren.count - survivors.count
                guard survivors == Array(orderedChildren.dropFirst(removedCount)) else {
                    // A hole is never an interrupted prefix of this lease.
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                try requireOriginalEraseBorrowedOwner()
                try requirePrefix(true, removedCount, false)
                try requireOriginalEraseBorrowedOwner()
            }
            while removedCount < orderedChildren.count {
                let child = orderedChildren[removedCount]
                guard try directoryNames(descriptor)
                        == Array(orderedChildren.dropFirst(removedCount)) else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                try requireOriginalEraseBorrowedOwner()
                try requirePrefix(true, removedCount, false)
                try requireOriginalEraseBorrowedOwner()
                let target = try regularFileInformation(named: child,
                    directoryDescriptor: descriptor)
                guard target.st_nlink == 1 else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                try verifySourceReadPolicy(.temporaryFile,
                    at: rootURL.appendingPathComponent(tombstone)
                        .appendingPathComponent(child))
                try verifyLeaseDirectory(tombstone,
                    descriptor: descriptor)
                try originalEraseBorrowedExclusiveCheck?()
                guard Darwin.unlinkat(descriptor, child, 0) == 0,
                      Darwin.fsync(descriptor) == 0 else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                removedCount += 1
                try requireOriginalEraseBorrowedOwner()
                try requirePrefix(true, removedCount, false)
                try requireOriginalEraseBorrowedOwner()
            }
            guard try directoryNames(descriptor).isEmpty else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            try requireOriginalEraseBorrowedOwner()
            try requirePrefix(true, orderedChildren.count, false)
            try requireOriginalEraseBorrowedOwner()
            try verifyLeaseDirectory(tombstone, descriptor: descriptor)
            try originalEraseBorrowedExclusiveCheck?()
            guard Darwin.unlinkat(authority.rootDescriptor, tombstone,
                AT_REMOVEDIR) == 0,
                Darwin.fsync(authority.rootDescriptor) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            try requireOriginalEraseBorrowedOwner()
            try requirePrefix(true, orderedChildren.count, true)
            try requireOriginalEraseBorrowedOwner()
        }
    }

    /// Final borrowed original-Erase ordinal. No ordinary reset or survivor
    /// scan runs here: the Router proves every earlier C16 and lease ordinal
    /// complete, then this adapter removes only the pinned empty Scratch root.
    @MainActor
    func eraseOriginalFrozenEmptyRoot(
        expectedFirstDevice: UInt64,
        expectedFirstInode: UInt64,
        requireCut: @MainActor () throws -> Void
    ) throws {
        try requireScratchDescriptorAccess()
        guard originalEraseBorrowedExclusiveCheck != nil,
              exclusiveNoRepairRead,
              expectedFirstDevice == authority.rootDevice,
              expectedFirstInode == authority.rootInode,
              expectedFirstInode != 0 else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try originalEraseBorrowedExclusiveCheck?()
        try requireOriginalEraseBorrowedOwner()
        try requireCut()
        try requireOriginalEraseBorrowedOwner()
        if originalEraseRootRemovalProved {
            var absent = stat()
            guard Darwin.fstatat(authority.operationsDescriptor,
                    Self.rootName, &absent, AT_SYMLINK_NOFOLLOW) != 0,
                  errno == ENOENT else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            try requireOriginalEraseBorrowedOwner()
            try requireCut()
            try requireOriginalEraseBorrowedOwner()
            return
        }
        var held = stat(), named = stat()
        guard Darwin.fstat(authority.rootDescriptor, &held) == 0,
              Darwin.fstatat(authority.operationsDescriptor,
                  Self.rootName, &named, AT_SYMLINK_NOFOLLOW) == 0,
              held.st_mode & S_IFMT == S_IFDIR,
              named.st_mode & S_IFMT == S_IFDIR,
              UInt64(held.st_dev) == expectedFirstDevice,
              UInt64(named.st_dev) == expectedFirstDevice,
              UInt64(held.st_ino) == expectedFirstInode,
              UInt64(named.st_ino) == expectedFirstInode,
              try directoryNames(authority.rootDescriptor).isEmpty else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try verifySourceReadPolicy(.stagingDirectory, at: rootURL)
        try requireOriginalEraseBorrowedOwner()
        try requireCut()
        try requireOriginalEraseBorrowedOwner()
        guard Darwin.unlinkat(authority.operationsDescriptor,
                Self.rootName, AT_REMOVEDIR) == 0,
              Darwin.fsync(authority.operationsDescriptor) == 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        try requireOriginalEraseBorrowedOwner()
        try requireCut()
        try requireOriginalEraseBorrowedOwner()
        var absent = stat()
        guard Darwin.fstatat(authority.operationsDescriptor,
                Self.rootName, &absent, AT_SYMLINK_NOFOLLOW) != 0,
              errno == ENOENT else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        originalEraseRootRemovalProved = true
        try originalEraseBorrowedExclusiveCheck?()
    }

    private func removeDeletionTombstone(
        named name: String, expectedLease: ScratchDataLeaseV1? = nil
    ) throws {
        try requireScratchDescriptorAccess()
        guard Self.isDeletionTombstone(name) else {
            throw ScratchDataLeaseStoreFailureV1.invalidLease
        }
        try requireNoUnfinishedHygieneTarget(named: String(name.dropFirst(Self.deletionPrefix.count)))
        let descriptor = try openLeaseDirectory(name)
        defer { _ = Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        if let expectedLease {
            try requireExpectedScratchLease(expectedLease, named: name, descriptor: descriptor)
        }
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
        try requireScratchDescriptorAccess()
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

    /// Exact children of this freshly allocated exclusive lease. The witness
    /// is captured while its source-reader directory is still locked; it is
    /// rechecked before the tombstone rename and again before any child unlink.
    private func requireExclusiveExpectedChildren(
        _ expected: [C16IngressHygieneFileIdentityV1],
        descriptor: Int32
    ) throws {
        try requireScratchDescriptorAccess()
        let names = try directoryNames(descriptor)
        guard !expected.isEmpty,
              Set(names) == Set(expected.map(\.name)),
              expected.count == names.count else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        for child in expected {
            let current = try regularFileInformation(
                named: child.name, directoryDescriptor: descriptor)
            guard current.st_nlink == 1,
                  C16IngressHygieneFileIdentityV1(
                    name: child.name, information: current) == child else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        }
    }

    private func deletePinnedDirectory(
        named name: String, descriptor: Int32,
        expectedFiles: [C16IngressHygieneFileIdentityV1]? = nil,
        exclusiveNoRepair: Bool = false
    ) throws {
        try requireScratchDescriptorAccess()
        try runC16SemanticSession(c16DeletePinnedDirectorySteps(named: name,
            descriptor: descriptor, expectedFiles: expectedFiles,
            exclusiveNoRepair: exclusiveNoRepair))
    }

    private func c16DeletePinnedDirectorySteps(
        named name: String, descriptor: Int32,
        expectedFiles: [C16IngressHygieneFileIdentityV1]? = nil,
        exclusiveNoRepair: Bool = false
    ) -> [C16SemanticStepV1] {
        [.plan { _ in
            try self.requireScratchDescriptorAccess()
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            try self.verifyLeaseDirectory(name, descriptor: descriptor)
            if expectedFiles == nil && !exclusiveNoRepair {
                try self.removeInterruptedPublications(directoryDescriptor: descriptor)
            }
            let names = try self.directoryNames(descriptor)
            if let expectedFiles {
                if exclusiveNoRepair {
                    try self.requireExclusiveExpectedChildren(expectedFiles, descriptor: descriptor)
                }
                let survivors = try self.ingressHygieneFileIdentities(name: name, descriptor: descriptor)
                let valid = exclusiveNoRepair || self.originalEraseBorrowedExclusiveCheck != nil
                    ? survivors == Array(expectedFiles.suffix(survivors.count))
                    : survivors.allSatisfy({ expectedFiles.contains($0) })
                guard survivors.map(\.name) == names, valid else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
            }
            var remaining = Set(expectedFiles?.map(\.name) ?? [])
            var steps: [C16SemanticStepV1] = []
            for child in names {
                steps.append(.effect {
                    if exclusiveNoRepair {
                        guard Set(try self.directoryNames(descriptor)) == remaining else {
                            throw ScratchDataLeaseStoreFailureV1.leaseCollision
                        }
                    }
                    let information = try self.regularFileInformation(named: child, directoryDescriptor: descriptor)
                    if let expectedFiles {
                        let current = C16IngressHygieneFileIdentityV1(name: child, information: information)
                        guard expectedFiles.contains(current) else {
                            throw AppAccessContractFailureV1.configurationUnknown
                        }
                        try self.verifySourceReadPolicy(.temporaryFile,
                            at: self.rootURL.appendingPathComponent(name).appendingPathComponent(child))
                        try self.verifyLeaseDirectory(name, descriptor: descriptor)
                        guard try C16IngressHygieneFileIdentityV1(name: child,
                            information: self.regularFileInformation(named: child, directoryDescriptor: descriptor)) == current else {
                            throw AppAccessContractFailureV1.configurationUnknown
                        }
                    }
                    guard Darwin.unlinkat(descriptor, child, 0) == 0 else {
                        throw ScratchDataLeaseStoreFailureV1.invalidRoot
                    }
                    if exclusiveNoRepair { remaining.remove(child) }
                    if expectedFiles != nil {
                        guard Darwin.fsync(descriptor) == 0 else {
                            throw ScratchDataLeaseStoreFailureV1.invalidRoot
                        }
                    }
                })
                if expectedFiles != nil {
                    steps.append(.effect {
                        try self.ingressMutationFailureInjection.interruptIfTriggered(.afterPreparedDirectoryFileDeletion)
                    })
                }
            }
            steps.append(.effect {
                if exclusiveNoRepair {
                    guard remaining.isEmpty, try self.directoryNames(descriptor).isEmpty else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                }
                guard Darwin.fsync(descriptor) == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                try self.verifyLeaseDirectory(name, descriptor: descriptor)
                guard Darwin.unlinkat(self.authority.rootDescriptor, name, AT_REMOVEDIR) == 0,
                      Darwin.fsync(self.authority.rootDescriptor) == 0 else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                var absent = stat()
                guard Darwin.fstatat(self.authority.rootDescriptor, name, &absent, AT_SYMLINK_NOFOLLOW) != 0,
                      errno == ENOENT else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                try self.verifyRoot()
            })
            return steps
        }]
    }

    private func directoryInformationIfPresent(named name: String) throws -> stat? {
        try requireScratchDescriptorAccess()
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
        try requireScratchDescriptorAccess()
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
            if exclusiveNoRepairRead {
                let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(descriptor)
                if Darwin.close(descriptor) == 0 {
                    ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
                }
            } else { _ = Darwin.close(descriptor) }
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        return descriptor
    }

    private func verifyLeaseDirectory(
        _ name: String,
        descriptor: Int32
    ) throws {
        try requireScratchDescriptorAccess()
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
        try requireScratchDescriptorAccess()
        let duplicate = Darwin.dup(descriptor)
        guard duplicate >= 0, let directory = Darwin.fdopendir(duplicate) else {
            if duplicate >= 0 {
                if exclusiveNoRepairRead {
                    let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(duplicate)
                    if Darwin.close(duplicate) == 0 {
                        ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
                    }
                } else { _ = Darwin.close(duplicate) }
            }
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        var closeAttempted = false
        defer {
            if !closeAttempted {
                if exclusiveNoRepairRead {
                    let held = Darwin.dirfd(directory)
                    let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(held)
                    if Darwin.closedir(directory) == 0 {
                        ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
                    }
                } else { _ = Darwin.closedir(directory) }
            }
        }
        // dup shares the directory offset with the retained descriptor. Every
        // independently fenced snapshot must start at the beginning.
        Darwin.rewinddir(directory)
        var names: [String] = []
        errno = 0
        while let entry = Darwin.readdir(directory) {
            guard let name = OwnedStorageDirectoryEntryNameV1.decode(entry) else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
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
        if exclusiveNoRepairRead {
            closeAttempted = true
            let held = Darwin.dirfd(directory)
            let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(held)
            guard Darwin.closedir(directory) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
        }
        return names.sorted()
    }

    private func regularFileInformation(
        named name: String,
        directoryDescriptor: Int32
    ) throws -> stat {
        try requireScratchDescriptorAccess()
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
        try requireScratchDescriptorAccess()
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
        if information.st_nlink == 2, originalEraseBorrowedExclusiveCheck != nil {
            for (path, value) in originalEraseC16FirstPPairPolicies
                where URL(fileURLWithPath: path).lastPathComponent == name {
                let url = URL(fileURLWithPath: path)
                var heldParent = stat(), namedParent = stat()
                guard Darwin.fstat(directoryDescriptor, &heldParent) == 0,
                      Darwin.lstat(url.deletingLastPathComponent().path, &namedParent) == 0,
                      heldParent.st_dev == namedParent.st_dev, heldParent.st_ino == namedParent.st_ino else { continue }
                guard Self.originalEraseSourceFullFact(information) == value.pair.finalFullFact
                    || Self.originalEraseSourceFullFact(information) == value.pair.partialFullFact,
                      try originalEraseC16VerifyFirstPPairPolicy(at: url) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                return information
            }
        }
        if information.st_nlink == 2, originalEraseBorrowedExclusiveCheck != nil,
           ingressControlAuthority?.rootDescriptor == directoryDescriptor,
           try originalEraseC16VerifyScopedPairPolicy(at: rootURL.deletingLastPathComponent()
               .appendingPathComponent("ProtectedIngressReceiptsV1").appendingPathComponent(name)) {
            return information
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
        try requireScratchDescriptorAccess()
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
        try requireScratchDescriptorAccess()
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
        var closeAttempted = false
        defer {
            if !closeAttempted {
                if exclusiveNoRepairRead {
                    let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(descriptor)
                    if Darwin.close(descriptor) == 0 {
                        ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
                    }
                } else { _ = Darwin.close(descriptor) }
            }
        }
        var pinned = stat()
        guard Darwin.fstat(descriptor, &pinned) == 0,
              pinned.st_dev == expected.st_dev,
              pinned.st_ino == expected.st_ino,
              pinned.st_size == expected.st_size else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        let byteCount = Int(pinned.st_size)
        var result = Data(count: byteCount)
        var offset = 0
        while offset < byteCount {
            let count = result.withUnsafeMutableBytes { bytes -> Int in
                guard let base = bytes.baseAddress else { return 0 }
                return Darwin.read(
                    descriptor,
                    base.advanced(by: offset),
                    byteCount - offset
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
        if exclusiveNoRepairRead {
            closeAttempted = true
            let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(descriptor)
            guard Darwin.close(descriptor) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
        }
        return result
    }

    private func readOriginalErasePublicationLeaf(
        named name: String, parent: Int32, maximumBytes: Int
    ) throws -> (stat, Data)? {
        try requireScratchDescriptorAccess()
        var parentBefore = stat()
        guard Darwin.fstat(parent, &parentBefore) == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        let expectedGroup = parentBefore.st_mode & S_ISGID == 0 ? Darwin.getegid() : parentBefore.st_gid
        var namedBefore = stat()
        if Darwin.fstatat(parent, name, &namedBefore, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            return nil
        }
        guard namedBefore.st_mode & S_IFMT == S_IFREG,
              namedBefore.st_nlink == 1 || namedBefore.st_nlink == 2,
              namedBefore.st_uid == Darwin.geteuid(),
              namedBefore.st_gid == expectedGroup,
              UInt64(namedBefore.st_dev) == authority.rootDevice,
              namedBefore.st_size >= 0,
              namedBefore.st_size <= Int64(maximumBytes) else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        var closeAttempted = false
        defer {
            if !closeAttempted {
                let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(descriptor)
                if Darwin.close(descriptor) == 0 {
                    ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
                }
            }
        }
        var heldBefore = stat()
        guard Darwin.fstat(descriptor, &heldBefore) == 0,
              Self.originalEraseSourceFullFact(heldBefore) == Self.originalEraseSourceFullFact(namedBefore),
              heldBefore.st_uid == namedBefore.st_uid,
              heldBefore.st_gid == namedBefore.st_gid else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        var bytes = Data(count: Int(heldBefore.st_size))
        let byteCount = bytes.count
        var offset = 0
        while offset < byteCount {
            let count = bytes.withUnsafeMutableBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return 0 }
                return Darwin.read(descriptor, base.advanced(by: offset), byteCount - offset)
            }
            guard count > 0 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            offset += count
        }
        var heldAfter = stat(), namedAfter = stat()
        guard Darwin.fstat(descriptor, &heldAfter) == 0,
              Darwin.fstatat(parent, name, &namedAfter, AT_SYMLINK_NOFOLLOW) == 0,
              Self.originalEraseSourceFullFact(heldAfter) == Self.originalEraseSourceFullFact(heldBefore),
              Self.originalEraseSourceFullFact(namedAfter) == Self.originalEraseSourceFullFact(heldBefore),
              heldAfter.st_uid == heldBefore.st_uid, heldAfter.st_gid == heldBefore.st_gid,
              namedAfter.st_uid == heldBefore.st_uid, namedAfter.st_gid == heldBefore.st_gid else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        closeAttempted = true
        let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(descriptor)
        guard Darwin.close(descriptor) == 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
        return (heldBefore, bytes)
    }

    private enum OriginalErasePublicationCutV1 {
        case absent
        case temporaryPrefix(Int)
        case temporaryFull
        case finalAndTemporary
        case finalOnly
    }

    /// One read-only publication classifier shared by the ordinary writer's
    /// borrowed branch and the actor-isolated original controller. A present
    /// name is never authority by itself: exact bytes, inode links, and the
    /// held/named policy are checked before returning a finite cut.
    private func originalErasePublicationCut(
        data: Data, temporaryName: String, finalName: String,
        parent: Int32, directoryURL: URL, finalURL: URL,
        atomicExclusiveRename: Bool
    ) throws -> OriginalErasePublicationCutV1 {
        try requireScratchDescriptorAccess()
        let temporary = try readOriginalErasePublicationLeaf(
            named: temporaryName, parent: parent, maximumBytes: data.count)
        let final = try readOriginalErasePublicationLeaf(
            named: finalName, parent: parent, maximumBytes: data.count)
        if let final {
            guard final.1 == data else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            try verifySourceReadPolicy(.temporaryFile, at: finalURL)
            if let temporary {
                guard !atomicExclusiveRename,
                      temporary.1 == data,
                      temporary.0.st_dev == final.0.st_dev,
                      temporary.0.st_ino == final.0.st_ino,
                      temporary.0.st_nlink == 2,
                      final.0.st_nlink == 2 else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                return .finalAndTemporary
            }
            guard final.0.st_nlink == 1 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            return .finalOnly
        }
        guard let temporary else { return .absent }
        guard temporary.0.st_nlink == 1,
              data.starts(with: temporary.1) else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        if !temporary.1.isEmpty {
            try verifySourceReadPolicy(.temporaryFile,
                at: directoryURL.appendingPathComponent(temporaryName))
        }
        if temporary.1.count == data.count { return .temporaryFull }
        return .temporaryPrefix(temporary.1.count)
    }

    /// One durable namespace effect used by either publication controller.
    private func unlinkPublicationTemporary(
        named temporaryName: String, parent: Int32
    ) throws {
        try requireScratchDescriptorAccess()
        guard Darwin.unlinkat(parent, temporaryName, 0) == 0,
              Darwin.fsync(parent) == 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
    }

    private func createPublicationTemporary(
        named temporaryName: String, parent: Int32
    ) throws -> Int32 {
        try requireScratchDescriptorAccess()
        let descriptor = Darwin.openat(parent, temporaryName,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        return descriptor
    }

    private func writePublicationChunk(
        _ data: Data, at offset: Int, descriptor: Int32
    ) throws -> Int {
        try requireScratchDescriptorAccess()
        guard offset >= 0, offset < data.count else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        let count = data.withUnsafeBytes { bytes -> Int in
            guard let base = bytes.baseAddress else { return 0 }
            return Darwin.write(descriptor, base.advanced(by: offset),
                data.count - offset)
        }
        guard count > 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        return count
    }

    private func publishPublicationTemporary(
        named temporaryName: String, finalName: String,
        parent: Int32, atomicExclusiveRename: Bool,
        leaseName: String?
    ) throws -> Int32 {
        try requireScratchDescriptorAccess()
        if atomicExclusiveRename {
            guard finalName == Self.controlEraseName,
                  leaseName == nil else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            return Darwin.renameatx_np(parent, temporaryName,
                parent, finalName, UInt32(RENAME_EXCL))
        }
        return Darwin.linkat(parent, temporaryName,
            parent, finalName, 0)
    }

    /// One publication state machine for ordinary and borrowed controllers.
    /// `advance` performs at most one namespace/write/policy effect and never
    /// calls an actor. The ordinary controller runs it under its existing SH;
    /// the borrowed controller brackets each advance with EX/G cut proof.
    private final class PublicationSessionV1 {
        private enum Stage {
            case initial
            case clearExisting(doneAfter: Bool)
            case unlinkExisting(doneAfter: Bool)
            case closeExisting(doneAfter: Bool)
            case create
            case write
            case syncTemporary
            case applyPolicy
            case publish
            case clearLinked
            case syncParent
            case verifyFinal
            case close
            case done
        }

        private let store: ScratchDataLeaseStoreV1
        private let data: Data
        private let finalName: String
        private let temporaryName: String
        private let parent: Int32
        private let directoryURL: URL
        private let finalURL: URL
        private let leaseName: String?
        private let atomicExclusiveRename: Bool
        private let authorityCheck: (() throws -> Void)?
        private let borrowed: Bool
        private var stage: Stage = .initial
        private var descriptor: Int32?
        private var closeAttempted = false
        private var offset = 0
        private var published = false
        private var capturedTemporaryFact: String?
        private var capturedTemporaryBytes: Data?

        init(store: ScratchDataLeaseStoreV1, data: Data,
             finalName: String, parent: Int32, directoryURL: URL,
             finalURL: URL, leaseName: String?,
             atomicExclusiveRename: Bool,
             authorityCheck: (() throws -> Void)?,
             borrowedOperationID: UUID?) throws {
            self.store = store
            self.data = data
            self.finalName = finalName
            self.parent = parent
            self.directoryURL = directoryURL
            self.finalURL = finalURL
            self.leaseName = leaseName
            self.atomicExclusiveRename = atomicExclusiveRename
            self.authorityCheck = authorityCheck
            borrowed = borrowedOperationID != nil
            if let borrowedOperationID {
                temporaryName = try ScratchDataLeaseStoreV1
                    .originalErasePublicationTemporaryName(
                        operationID: borrowedOperationID,
                        finalName: finalName, leaseName: leaseName)
            } else {
                temporaryName = ".partial-\(UUID().uuidString.lowercased())"
            }
        }

        private var failureCleanupAttempted = false

        private func closeOwnedDescriptor() throws {
            guard let descriptor, !closeAttempted else { return }
            closeAttempted = true
            if borrowed {
                let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(descriptor)
                guard Darwin.close(descriptor) == 0 else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
            } else { _ = Darwin.close(descriptor) }
            self.descriptor = nil
        }

        /// One explicit close or ordinary legacy temp cleanup. Borrowed
        /// settlement never removes a replayable interrupted temp name.
        func advanceFailureSettlement() throws -> Bool {
            try store.requireScratchDescriptorAccess()
            if descriptor != nil && !closeAttempted {
                try closeOwnedDescriptor()
                return true
            }
            if !borrowed && !published && !failureCleanupAttempted {
                failureCleanupAttempted = true
                _ = Darwin.unlinkat(parent, temporaryName, 0)
                return true
            }
            return false
        }

        deinit {
            if let descriptor, !closeAttempted {
                if borrowed {
                    // No fresh cut is available in deinit. Preserve this FD
                    // as unclosed, without attempting an unauthorized close.
                    _ = ScratchUncertainCloseQuarantineV1.shared.begin(descriptor)
                } else { _ = Darwin.close(descriptor) }
            }
            if !published && !borrowed && !failureCleanupAttempted {
                _ = Darwin.unlinkat(parent, temporaryName, 0)
            }
        }

        /// Re-evaluate both names immediately at each replay settlement
        /// boundary. The continuation flag describes an expected cut; it is
        /// never evidence that the final name is still present or absent.
        private func requireExistingReplayCut(doneAfter: Bool) throws {
            let cut = try store.originalErasePublicationCut(data: data,
                temporaryName: temporaryName, finalName: finalName,
                parent: parent, directoryURL: directoryURL, finalURL: finalURL,
                atomicExclusiveRename: atomicExclusiveRename)
            switch (doneAfter, cut) {
            case (false, .temporaryPrefix), (false, .temporaryFull),
                 (true, .finalAndTemporary): return
            default: throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        }

        func advance() throws -> Bool {
            try store.requireScratchDescriptorAccess()
            switch stage {
            case .initial:
                try authorityCheck?()
                if borrowed {
                    let cut = try store.originalErasePublicationCut(
                        data: data, temporaryName: temporaryName,
                        finalName: finalName, parent: parent,
                        directoryURL: directoryURL, finalURL: finalURL,
                        atomicExclusiveRename: atomicExclusiveRename)
                    switch cut {
                    case .absent: stage = .create
                    case .temporaryPrefix, .temporaryFull:
                        stage = .clearExisting(doneAfter: false)
                    case .finalAndTemporary:
                        stage = .clearExisting(doneAfter: true)
                    case .finalOnly: stage = .done
                    }
                } else {
                    stage = .create
                }
                return true
            case let .clearExisting(doneAfter):
                if !borrowed {
                    try store.unlinkPublicationTemporary(named: temporaryName, parent: parent)
                    stage = doneAfter ? .close : .create
                    return true
                }
                try authorityCheck?()
                try requireExistingReplayCut(doneAfter: doneAfter)
                let opened = Darwin.openat(parent, temporaryName,
                    O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
                guard opened >= 0 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                // Install ownership before any read or validation can throw.
                descriptor = opened
                closeAttempted = false
                var held = stat(), named = stat()
                guard Darwin.fstat(opened, &held) == 0,
                      Darwin.fstatat(parent, temporaryName, &named, AT_SYMLINK_NOFOLLOW) == 0,
                      held.st_mode & S_IFMT == S_IFREG,
                      held.st_uid == geteuid(), held.st_gid == getegid(),
                      UInt64(held.st_dev) == store.authority.rootDevice,
                      held.st_nlink == (doneAfter ? 2 : 1),
                      held.st_size >= 0, held.st_size <= Int64(data.count),
                      ScratchDataLeaseStoreV1.originalEraseSourceFullFact(held)
                        == ScratchDataLeaseStoreV1.originalEraseSourceFullFact(named) else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                guard let leaf = try store.readOriginalErasePublicationLeaf(named: temporaryName,
                    parent: parent, maximumBytes: data.count),
                    ScratchDataLeaseStoreV1.originalEraseSourceFullFact(leaf.0)
                        == ScratchDataLeaseStoreV1.originalEraseSourceFullFact(held),
                    data.starts(with: leaf.1) else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                if leaf.1.isEmpty {
                    guard held.st_nlink == 1, held.st_mode & 0o7777 == 0o600, !doneAfter else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                }
                if !leaf.1.isEmpty && leaf.0.st_nlink == 1 {
                    try store.verifySourceReadPolicy(.temporaryFile,
                        at: directoryURL.appendingPathComponent(temporaryName))
                }
                // Empty pre-policy is an unaccepted unpublished role, not
                // valid protection or a canonical record. No bytes are used.
                capturedTemporaryFact = ScratchDataLeaseStoreV1.originalEraseSourceFullFact(held)
                capturedTemporaryBytes = leaf.1
                try authorityCheck?()
                stage = .unlinkExisting(doneAfter: doneAfter)
                return true
            case let .unlinkExisting(doneAfter):
                guard let descriptor, let capturedTemporaryFact,
                      let capturedTemporaryBytes else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                try authorityCheck?()
                var held = stat(), named = stat()
                guard Darwin.fstat(descriptor, &held) == 0,
                      Darwin.fstatat(parent, temporaryName, &named, AT_SYMLINK_NOFOLLOW) == 0,
                      ScratchDataLeaseStoreV1.originalEraseSourceFullFact(held) == capturedTemporaryFact,
                      ScratchDataLeaseStoreV1.originalEraseSourceFullFact(named) == capturedTemporaryFact,
                      held.st_uid == geteuid(), named.st_uid == geteuid(),
                      held.st_gid == getegid(), named.st_gid == getegid(),
                      let leaf = try store.readOriginalErasePublicationLeaf(named: temporaryName,
                        parent: parent, maximumBytes: data.count),
                      leaf.1 == capturedTemporaryBytes,
                      ScratchDataLeaseStoreV1.originalEraseSourceFullFact(leaf.0) == capturedTemporaryFact else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                try requireExistingReplayCut(doneAfter: doneAfter)
                try store.unlinkPublicationTemporary(named: temporaryName, parent: parent)
                var absent = stat()
                guard Darwin.fstatat(parent, temporaryName, &absent, AT_SYMLINK_NOFOLLOW) != 0,
                      errno == ENOENT else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                try authorityCheck?()
                stage = .closeExisting(doneAfter: doneAfter)
                return true
            case let .closeExisting(doneAfter):
                try closeOwnedDescriptor()
                capturedTemporaryFact = nil
                capturedTemporaryBytes = nil
                // A future exclusive create installs a distinct descriptor;
                // resetting is allowed only after this close succeeded.
                closeAttempted = false
                stage = doneAfter ? .verifyFinal : .create
                return true
            case .create:
                descriptor = try store.createPublicationTemporary(
                    named: temporaryName, parent: parent)
                stage = .applyPolicy
                return true
            case .write:
                guard let descriptor else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                if offset < data.count {
                    offset += try store.writePublicationChunk(data,
                        at: offset, descriptor: descriptor)
                } else {
                    stage = .syncTemporary
                }
                return true
            case .syncTemporary:
                guard let descriptor,
                      Darwin.fsync(descriptor) == 0 else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                stage = .publish
                return true
            case .applyPolicy:
                try store.applySourceReadPolicy(.temporaryFile,
                    at: directoryURL.appendingPathComponent(temporaryName),
                    authorityCheck: {
                        try self.authorityCheck?()
                        if let leaseName = self.leaseName {
                            try self.store.verifyLeaseDirectory(leaseName,
                                descriptor: self.parent)
                        } else {
                            try self.store.verifyRoot()
                        }
                    })
                stage = .write
                return true
            case .publish:
                let result = try store.publishPublicationTemporary(
                    named: temporaryName, finalName: finalName,
                    parent: parent,
                    atomicExclusiveRename: atomicExclusiveRename,
                    leaseName: leaseName)
                if result != 0 {
                    guard errno == EEXIST, !borrowed,
                          try store.adoptExistingFileIfIdentical(data,
                              named: finalName,
                              directoryDescriptor: parent,
                              finalURL: finalURL,
                              leaseName: leaseName) else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                    stage = .clearExisting(doneAfter: true)
                    return true
                }
                if atomicExclusiveRename {
                    // A one-link marker is capturable only after this parent
                    // sync. The borrowed controller's next proof observes the
                    // durable, canonical published name.
                    guard Darwin.fsync(parent) == 0 else {
                        throw ScratchDataLeaseStoreFailureV1.invalidRoot
                    }
                    try store.ingressMutationFailureInjection
                        .interruptIfTriggered(
                            .afterScratchControlErasePublication)
                    stage = .verifyFinal
                } else {
                    // The controller observes the two-link cut here, before
                    // the temp is removed at its next checked advance.
                    stage = .clearLinked
                }
                return true
            case .clearLinked:
                try store.unlinkPublicationTemporary(
                    named: temporaryName, parent: parent)
                stage = .syncParent
                return true
            case .syncParent:
                guard Darwin.fsync(parent) == 0 else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                stage = .verifyFinal
                return true
            case .verifyFinal:
                try authorityCheck?()
                _ = try store.regularFileInformation(named: finalName,
                    directoryDescriptor: parent)
                try store.verifySourceReadPolicy(.temporaryFile,
                    at: finalURL)
                if let leaseName {
                    try store.verifyLeaseDirectory(leaseName,
                        descriptor: parent)
                } else {
                    try store.verifyRoot()
                }
                guard try store.readRegularFile(named: finalName,
                    directoryDescriptor: parent,
                    maximumBytes: data.count) == data else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                try authorityCheck?()
                stage = .close
                published = true
                return true
            case .close:
                try closeOwnedDescriptor()
                stage = .done
                return true
            case .done:
                return false
            }
        }
    }

    private func publishDurably(
        _ data: Data,
        named name: String,
        directoryDescriptor: Int32,
        directoryURL: URL,
        finalURL: URL,
        leaseName: String? = nil,
        atomicExclusiveRename: Bool = false,
        directoryAuthorityCheck: (() throws -> Void)? = nil
    ) throws {
        try requireScratchDescriptorAccess()
        // Borrowed publication is driven by the actor-isolated C16 controller
        // so that no ordinary synchronous helper can skip a physical cut.
        guard originalEraseOperationID == nil else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let session = try PublicationSessionV1(store: self, data: data,
            finalName: name, parent: directoryDescriptor,
            directoryURL: directoryURL, finalURL: finalURL,
            leaseName: leaseName,
            atomicExclusiveRename: atomicExclusiveRename,
            authorityCheck: directoryAuthorityCheck,
            borrowedOperationID: nil)
        do { while try session.advance() {} }
        catch {
            let failure = error
            while try session.advanceFailureSettlement() {}
            throw failure
        }
    }

    @MainActor private func publishOriginalEraseControlDurably(
        _ data: Data, named name: String,
        directoryDescriptor: Int32, directoryURL: URL, finalURL: URL,
        atomicExclusiveRename: Bool
    ) throws {
        try requireScratchDescriptorAccess()
        guard originalEraseBorrowedExclusiveCheck != nil,
              exclusiveNoRepairRead,
              let originalEraseOperationID,
              originalEraseC16CutCheck != nil else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        _ = try protectedIngressReceiptDirectory()
        guard let control = ingressControlAuthority,
              control.rootDescriptor == directoryDescriptor,
              directoryURL == rootURL.deletingLastPathComponent()
                .appendingPathComponent("ProtectedIngressReceiptsV1",
                    isDirectory: true),
              finalURL == directoryURL.appendingPathComponent(name) else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let session = try PublicationSessionV1(store: self, data: data,
            finalName: name, parent: directoryDescriptor,
            directoryURL: directoryURL, finalURL: finalURL,
            leaseName: nil,
            atomicExclusiveRename: atomicExclusiveRename,
            authorityCheck: {
                _ = try self.protectedIngressReceiptDirectory()
            }, borrowedOperationID: originalEraseOperationID)
        try runOriginalEraseC16SemanticSession([.publication(session)])
    }

    /// Shared pure naming rule for the producer and the Router's sidecar
    /// target-order builder. Length framing keeps arbitrary valid leaf names
    /// injective; it does not grant authority to create or settle the temp.
    static func originalErasePublicationTemporaryName(
        operationID: UUID, finalName: String, leaseName: String?
    ) throws -> String {
        guard operationID != SettingsValidationV1.zeroUUID,
              OperationalDiagnosticsBoundsV1.validRelativeName(finalName),
              leaseName.map(OperationalDiagnosticsBoundsV1.validRelativeName)
                ?? true else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        let framed = operationID.uuidString.lowercased() + "|"
            + String(finalName.utf8.count) + ":" + finalName + "|"
            + (leaseName.map { String($0.utf8.count) + ":" + $0 }
                ?? "nil")
        let hex = SHA256.hash(data: Data(framed.utf8)).map {
            String(format: "%02x", $0)
        }.joined()
        let raw = String(hex.prefix(32))
        let groups = [8, 4, 4, 4, 12]
        var cursor = raw.startIndex
        var pieces: [String] = []
        for width in groups {
            let end = raw.index(cursor, offsetBy: width)
            pieces.append(String(raw[cursor..<end]))
            cursor = end
        }
        guard let id = UUID(uuidString: pieces.joined(separator: "-")),
              id != SettingsValidationV1.zeroUUID else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        return ".partial-" + id.uuidString.lowercased()
    }

    private func removeInterruptedPublications(
        directoryDescriptor: Int32
    ) throws {
        try requireScratchDescriptorAccess()
        if originalEraseBorrowedExclusiveCheck != nil,
           try directoryNames(directoryDescriptor).contains(where: {
               $0.hasPrefix(".partial-")
           }) {
            // Original cleanup must settle each first-P partial under its
            // own durable ordinal and exact inode/content projection. A
            // read-like ordinary getter may never erase it implicitly.
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        var removed = false
        for name in try directoryNames(directoryDescriptor)
        where name.hasPrefix(".partial-") {
            let suffix = String(name.dropFirst(".partial-".count))
            guard UUID(uuidString: suffix)?.uuidString.lowercased() == suffix else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
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
        try requireScratchDescriptorAccess()
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
        try requireScratchDescriptorAccess()
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

// MARK: - C34 scene-navigation storage enrollment proof

enum C34SceneNavigationOwnedStorageBoundaryV1 {
    static let snapshotType: Any.Type = SceneNavigationSnapshotV1.self
    static let persistenceClass = "DEVICE_OPERATIONAL_NONCANONICAL"
    static let canonicalWorkspaceLedgerEnrollmentCount = 0
    static let backupEnrollmentCount = 0
    static let journalEnrollmentCount = 0
    static let reportEnrollmentCount = 0
    static let searchEnrollmentCount = 0
    static let eraseClears = true

    static func validate(_ lifecycle: SceneNavigationLifecycleDispositionV1 = .init()) -> Bool {
        lifecycle.persistenceClass == persistenceClass
            && !lifecycle.workspaceTruth
            && !lifecycle.backupIncluded
            && !lifecycle.journalIncluded
            && !lifecycle.reportIncluded
            && !lifecycle.searchIncluded
            && lifecycle.eraseClears
            && canonicalWorkspaceLedgerEnrollmentCount == 0
    }
}

// MARK: - C54 encrypted portable envelope reservations

enum EncryptedPortableEnvelopeScratchNamespaceV1 {
    private static let prefix: (UInt8, UInt8, UInt8, UInt8) = (0xc5, 0x54, 0x00, 0x01)

    static func leaseID(for attemptID: UUID, slot: UInt8 = 0) -> UUID {
        var source = attemptID.uuid
        var sourceData = withUnsafeBytes(of: &source) { Data($0) }
        sourceData.append(slot)
        let digest = Array(SHA256.hash(data: sourceData))
        return UUID(uuid: (
            prefix.0, prefix.1, prefix.2, prefix.3,
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11]
        ))
    }

    static func contains(_ leaseID: UUID) -> Bool {
        let bytes = leaseID.uuid
        return bytes.0 == prefix.0 && bytes.1 == prefix.1
            && bytes.2 == prefix.2 && bytes.3 == prefix.3
    }
}

protocol EncryptedPortableEnvelopeScratchRecoveringV1: ScratchDataLeasePortV1 {
    func recoverEncryptedPortableEnvelopeScratch() async throws
        -> ScratchDataLeaseRecoverySummaryV1
}

protocol EncryptedPortableEnvelopeStreamingScratchPortV1: ScratchDataLeasePortV1 {
    /// Real provider identity, never a caller-selected capacity-root surrogate.
    func acquireOwnedStorageProducerActivity() async throws -> OwnedStorageProducerActivityV1
    func makeEncryptedPortableEnvelopeStreamingScratch(
        named: String,
        lease: ScratchDataLeaseV1,
        maximumByteCount: UInt64
    ) async throws -> any EncryptedPortableEnvelopeTerminalScratchV1
}

final class EncryptedPortableEnvelopeProtectedFileScratchV1:
    EncryptedPortableEnvelopeTerminalScratchV1,
    @unchecked Sendable {
    static let maximumAppendByteCount = 1_048_604

    let protectionClass = EncryptedEnvelopeProtectionClassV1.complete
    let isExcludedFromBackup = true

    private let url: URL
    private let maximumByteCount: UInt64
    private var descriptor: Int32
    private let device: UInt64
    private let inode: UInt64
    private let lock = NSLock()
    private let producerActivity: OwnedStorageProducerActivityV1
    private var expectedByteCount: UInt64?
    private var writtenByteCount: UInt64 = 0

    fileprivate init(url: URL, pinnedDescriptor: Int32, maximumByteCount: UInt64,
                     producerActivity: OwnedStorageProducerActivityV1) throws {
        guard url.isFileURL,
              pinnedDescriptor >= 0,
              maximumByteCount <= EncryptedPortableEnvelopeResourceLimitsV1
                .maximumOperationalScratchByteCount else {
            if pinnedDescriptor >= 0 { _ = Darwin.close(pinnedDescriptor) }
            throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
        }
        self.producerActivity = producerActivity
        self.url = url.standardizedFileURL
        self.maximumByteCount = maximumByteCount
        var status = stat()
        guard Darwin.fstat(pinnedDescriptor, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              status.st_nlink == 1 else {
            _ = Darwin.close(pinnedDescriptor)
            throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
        }
        descriptor = pinnedDescriptor
        device = UInt64(status.st_dev)
        inode = UInt64(status.st_ino)
    }

    deinit { closeResource() }

    /// Invalidates the writable FD under its I/O lock, without renewing access.
    /// The outer operation must separately await its worker/catch-tail drain.
    func closeResource() {
        lock.withLock {
            guard descriptor >= 0 else { return }
            Darwin.close(descriptor)
            descriptor = -1
            producerActivity.close()
        }
    }

    func prepareForStreamingWrite(expectedByteCount: UInt64) throws {
        try lock.withLock {
            guard expectedByteCount <= maximumByteCount else {
                throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
            }
            try verifyPinnedDescriptor()
            guard Darwin.ftruncate(descriptor, 0) == 0 else {
                throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
            }
            self.expectedByteCount = expectedByteCount
            writtenByteCount = 0
        }
    }

    func appendStreamingBytes(_ bytes: Data) throws {
        try lock.withLock {
            guard let expectedByteCount,
                  bytes.count <= Self.maximumAppendByteCount else {
                throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
            }
            let (next, overflow) = writtenByteCount.addingReportingOverflow(
                UInt64(bytes.count)
            )
            guard !overflow, next <= expectedByteCount else {
                throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
            }
            try verifyPinnedDescriptor()
            var consumed = 0
            try bytes.withUnsafeBytes { raw in
                while consumed < bytes.count {
                    let count = Darwin.pwrite(
                        descriptor,
                        raw.baseAddress!.advanced(by: consumed),
                        bytes.count - consumed,
                        off_t(writtenByteCount) + off_t(consumed)
                    )
                    guard count > 0 else {
                        throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
                    }
                    consumed += count
                }
            }
            writtenByteCount = next
        }
    }

    func synchronizeStreamingWrite() throws {
        try lock.withLock {
            guard let expectedByteCount, writtenByteCount == expectedByteCount else {
                throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
            }
            try verifyPinnedDescriptor()
            guard Darwin.fsync(descriptor) == 0 else {
                throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
            }
            try ProtectedFilePolicyV1.verify(.temporaryFile, at: url)
        }
    }

    func encryptedEnvelopeByteCount() throws -> UInt64 {
        try lock.withLock {
            let status = try pinnedStatus()
            guard status.st_size >= 0 else {
                throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
            }
            return UInt64(status.st_size)
        }
    }

    func readExactly(atOffset: UInt64, byteCount: Int) throws -> Data {
        try lock.withLock {
            guard byteCount >= 0,
                  byteCount <= Self.maximumAppendByteCount,
                  atOffset <= maximumByteCount,
                  UInt64(byteCount) <= maximumByteCount - atOffset else {
                throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
            }
            try verifyPinnedDescriptor()
            var bytes = Data(count: byteCount)
            var consumed = 0
            try bytes.withUnsafeMutableBytes { raw in
                while consumed < byteCount {
                    let count = Darwin.pread(
                        descriptor,
                        raw.baseAddress!.advanced(by: consumed),
                        byteCount - consumed,
                        off_t(atOffset) + off_t(consumed)
                    )
                    guard count > 0 else {
                        throw EncryptedPortableEnvelopeFailureV1.invalidFrameLayout
                    }
                    consumed += count
                }
            }
            return bytes
        }
    }

    func discardStreamingBytes() throws {
        try lock.withLock {
            try verifyPinnedDescriptor()
            guard Darwin.ftruncate(descriptor, 0) == 0,
                  Darwin.fsync(descriptor) == 0 else {
                throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
            }
            expectedByteCount = nil
            writtenByteCount = 0
        }
    }

    private func pinnedStatus() throws -> stat {
        var status = stat()
        try producerActivity.requireApplicationSupport(producerActivity.applicationSupportURL)
        guard descriptor >= 0, Darwin.fstat(descriptor, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              status.st_nlink == 1,
              UInt64(status.st_dev) == device,
              UInt64(status.st_ino) == inode else {
            throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
        }
        return status
    }

    private func verifyPinnedDescriptor() throws { _ = try pinnedStatus() }
}

struct EncryptedPortableEnvelopeStorageReservationRequestV1: Equatable, Sendable {
    let purpose: EncryptedPortableEnvelopeStoragePurposeV1
    let workspaceID: WorkspaceID
    let attemptID: UUID
    let mutationID: MutationIDV1
    let requiredBytes: Int64

    init(
        purpose: EncryptedPortableEnvelopeStoragePurposeV1,
        workspaceID: WorkspaceID,
        attemptID: UUID,
        mutationID: MutationIDV1,
        requiredBytes: Int64
    ) throws {
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0,
                               0, 0, 0, 0, 0, 0, 0, 0))
        guard workspaceID.rawValue != zero,
              attemptID != zero,
              requiredBytes > 0 else {
            throw OwnedStorageLedgerFailureV1.accountingOverflow
        }
        self.purpose = purpose
        self.workspaceID = workspaceID
        self.attemptID = attemptID
        self.mutationID = mutationID
        self.requiredBytes = requiredBytes
    }
}

struct EncryptedPortableEnvelopeStorageReservationV1: Equatable, Sendable {
    let request: EncryptedPortableEnvelopeStorageReservationRequestV1
    let reservation: OwnedStorageReservationV1
}

extension OwnedStorageLedgerV1 {
    /// Reuses the closed set of app-owned roots and the process-local ledger.
    /// Exact retries adopt their reservation; no envelope store or root exists.
    func reserveEncryptedPortableEnvelope(
        _ request: EncryptedPortableEnvelopeStorageReservationRequestV1
    ) throws -> EncryptedPortableEnvelopeStorageReservationV1 {
        let identity = try OwnedStorageAttemptIDV1(
            workspaceID: request.workspaceID,
            generationID: request.attemptID,
            mutationID: request.mutationID
        )
        return EncryptedPortableEnvelopeStorageReservationV1(
            request: request,
            reservation: try reserve(
                attemptID: identity,
                requiredBytes: request.requiredBytes
            )
        )
    }

    func releaseEncryptedPortableEnvelope(
        _ reservation: EncryptedPortableEnvelopeStorageReservationV1
    ) {
        release(reservation: reservation.reservation)
    }

    static let c54UsesExistingOwnedScratchRoot = true
    static let c54CreatesParallelStoreOrRoot = false
    static let c54PressureNeverAuthorizesDeletion = true
}

extension ScratchDataLeaseStoreV1: EncryptedPortableEnvelopeScratchRecoveringV1 {
    /// Deletes only C54's reserved lease namespace after relaunch. Other
    /// resumable scratch families retain their established recovery policy.
    func recoverEncryptedPortableEnvelopeScratch() async throws
        -> ScratchDataLeaseRecoverySummaryV1 {
        try withProducerFilesystemLock {
            try recoverEncryptedPortableEnvelopeScratchSynchronously()
        }
    }

    private func recoverEncryptedPortableEnvelopeScratchSynchronously() throws
        -> ScratchDataLeaseRecoverySummaryV1 {
        let recovered = try recoverScratchLeaseState()
        let interrupted = recovered.active.filter {
            EncryptedPortableEnvelopeScratchNamespaceV1.contains($0.request.leaseID)
        }
        var removedBytes: UInt64 = 0
        for lease in interrupted {
            let directory = rootURL.appendingPathComponent(
                lease.relativeDirectory,
                isDirectory: true
            )
            let descriptor = try openLeaseDirectory(lease.relativeDirectory)
            let actualBytes: UInt64
            do {
                actualBytes = try payloadByteCount(
                    directoryDescriptor: descriptor,
                    directoryURL: directory
                )
            } catch {
                _ = Darwin.close(descriptor)
                throw error
            }
            _ = Darwin.close(descriptor)
            let (next, overflow) = removedBytes.addingReportingOverflow(
                actualBytes
            )
            guard !overflow else {
                throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
            }
            removedBytes = next
            try releaseScratchLeaseSynchronously(lease, terminal: .recoveredExpired)
        }
        return try ScratchDataLeaseRecoverySummaryV1(
            recoveredExpiredLeaseCount: interrupted.count,
            removedByteCount: removedBytes
        )
    }
}

extension ScratchDataLeaseStoreV1: EncryptedPortableEnvelopeStreamingScratchPortV1 {
    func acquireOwnedStorageProducerActivity() async throws -> OwnedStorageProducerActivityV1 {
        try requireScratchDescriptorAccess()
        guard originalEraseBorrowedLifetime == .ordinary else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        let activity = try OwnedStorageProducerActivityV1.acquire(
            applicationSupportURL: producerApplicationSupportURL)
        do {
            try authority.verify(rootName: Self.rootName)
            try activity.requireApplicationSupport(producerApplicationSupportURL)
            return activity
        } catch { activity.close(); throw error }
    }

    func makeEncryptedPortableEnvelopeStreamingScratch(
        named: String,
        lease: ScratchDataLeaseV1,
        maximumByteCount: UInt64
    ) async throws -> any EncryptedPortableEnvelopeTerminalScratchV1 {
        try requireScratchDescriptorAccess()
        return try withProducerFilesystemLock {
            try makeEncryptedPortableEnvelopeStreamingScratchSynchronously(named: named, lease: lease, maximumByteCount: maximumByteCount)
        }
    }

    private func makeEncryptedPortableEnvelopeStreamingScratchSynchronously(
        named: String,
        lease: ScratchDataLeaseV1,
        maximumByteCount: UInt64
    ) throws -> any EncryptedPortableEnvelopeTerminalScratchV1 {
        try requireScratchDescriptorAccess()
        guard originalEraseBorrowedLifetime == .ordinary else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        let sinkActivity = try OwnedStorageProducerActivityV1.acquire(
            applicationSupportURL: producerApplicationSupportURL)
        var activityTransferred = false
        defer { if !activityTransferred { sinkActivity.close() } }
        guard maximumByteCount <= lease.request.requestedByteCount else {
            throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
        }
        let url = try writeScratchDataSynchronously(Data(), named: named, lease: lease)
        guard !named.isEmpty,
              !named.contains("/"),
              !named.contains("\\"),
              url.lastPathComponent == named else {
            throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
        }
        let directoryDescriptor = try openLeaseDirectory(lease.relativeDirectory)
        defer { _ = Darwin.close(directoryDescriptor) }
        let descriptor = Darwin.openat(directoryDescriptor, named, O_RDWR | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
        }
        do {
            try ProtectedFilePolicyV1.verify(.temporaryFile, at: url)
            var linked = stat()
            var pinned = stat()
            guard Darwin.fstatat(directoryDescriptor, named, &linked, AT_SYMLINK_NOFOLLOW) == 0,
                  Darwin.fstat(descriptor, &pinned) == 0,
                  (linked.st_mode & S_IFMT) == S_IFREG,
                  linked.st_nlink == 1,
                  linked.st_dev == pinned.st_dev,
                  linked.st_ino == pinned.st_ino else {
                throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
            }
        } catch {
            _ = Darwin.close(descriptor)
            throw error
        }
        let sink = try EncryptedPortableEnvelopeProtectedFileScratchV1(
            url: url,
            pinnedDescriptor: descriptor,
            maximumByteCount: maximumByteCount,
            producerActivity: sinkActivity
        )
        activityTransferred = true
        return sink
    }
}


/// Invocation-wide accounting. Counts include lease.json and each hardlink
/// name. The encoded byte budget measures the actual retained JSON records,
/// plus lease metadata, rather than an estimated in-memory object size.
struct TemporalScratchCensusBudgetV1: Sendable {
    static let maximumMembersPerLease = 4_096
    static let maximumTotalMembers = 65_536
    static let maximumEncodedBytes = 32 * 1_048_576
    private(set) var totalMembers = 0
    private(set) var encodedBytes = 0

    fileprivate mutating func reserveMember(leaseCount: Int) throws {
        let (local, localOverflow) = leaseCount.addingReportingOverflow(1)
        let (total, totalOverflow) = totalMembers.addingReportingOverflow(1)
        guard !localOverflow, !totalOverflow, local <= Self.maximumMembersPerLease,
              total <= Self.maximumTotalMembers else {
            throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
        }
        totalMembers = total
    }

    fileprivate mutating func reserveEncodedBytes(_ count: Int) throws {
        let (next, overflow) = encodedBytes.addingReportingOverflow(count)
        guard count >= 0, !overflow, next <= Self.maximumEncodedBytes else {
            throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
        }
        encodedBytes = next
    }
}

private struct TemporalScratchMemberObservationV1: Codable, Equatable, Sendable {
    let name: String
    let device: UInt64
    let inode: UInt64
    let mode: UInt16
    let links: UInt64
    let byteCount: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64

    init(name: String, information: stat) throws {
        guard (information.st_mode & S_IFMT) == S_IFREG,
              information.st_size >= 0, (1...2).contains(information.st_nlink) else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        self.name = name; device = UInt64(information.st_dev); inode = UInt64(information.st_ino)
        mode = UInt16(information.st_mode); links = UInt64(information.st_nlink)
        byteCount = Int64(information.st_size)
        modifiedSeconds = Int64(information.st_mtimespec.tv_sec)
        modifiedNanoseconds = Int64(information.st_mtimespec.tv_nsec)
        changedSeconds = Int64(information.st_ctimespec.tv_sec)
        changedNanoseconds = Int64(information.st_ctimespec.tv_nsec)
    }
}

extension ScratchDataLeaseStoreV1 {
    /// The temporal caller has already proved the existing application and
    /// Operations root. This initializer cannot create or repair a target.
    private convenience init(existingTemporalRootAt applicationSupportURL: URL,
                             clock: @escaping Clock) throws {
        try self.init(verifiedExistingTemporalRootAt: applicationSupportURL, clock: clock)
    }

    private func temporalMemberCensus(directory: Int32, directoryURL: URL,
                                     budget: inout TemporalScratchCensusBudgetV1)
        throws -> [TemporalScratchMemberObservationV1] {
        // dup(directory) shares its open-description offset and is unsuitable.
        let cursorFD = Darwin.openat(directory, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard cursorFD >= 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        guard let cursor = Darwin.fdopendir(cursorFD) else {
            _ = Darwin.close(cursorFD)
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        defer { _ = Darwin.closedir(cursor) }
        var values: [TemporalScratchMemberObservationV1] = []
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try budget.reserveEncodedBytes(2) // retained census array brackets
        while true {
            errno = 0
            guard let entry = Darwin.readdir(cursor) else {
                guard errno == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                break
            }
            guard let name = OwnedStorageDirectoryEntryNameV1.decode(entry) else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            if name == "." || name == ".." { continue }
            try budget.reserveMember(leaseCount: values.count)
            guard OperationalDiagnosticsBoundsV1.validRelativeName(name) else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            var before = stat()
            guard Darwin.fstatat(directory, name, &before, AT_SYMLINK_NOFOLLOW) == 0,
                  UInt64(before.st_dev) == authority.rootDevice else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            let value = try TemporalScratchMemberObservationV1(name: name, information: before)
            var after = stat()
            guard Darwin.fstatat(directory, name, &after, AT_SYMLINK_NOFOLLOW) == 0,
                  try TemporalScratchMemberObservationV1(name: name, information: after) == value else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            let encoded = try encoder.encode(value)
            try budget.reserveEncodedBytes(encoded.count)
            if !values.isEmpty { try budget.reserveEncodedBytes(1) }
            values.append(value)
        }
        let ordered = values.sorted { $0.name.utf8.lexicographicallyPrecedes($1.name.utf8) }
        guard Set(ordered.map(\.name)).count == ordered.count else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        // A two-link inode is lawful only as one exact final/partial pair
        // wholly contained in this same lease. Third and external links fail.
        let groups = Dictionary(grouping: ordered) { "\($0.device):\($0.inode)" }
        for members in groups.values {
            if members.count == 1 {
                guard members[0].links == 1 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                _ = try ProtectedFilePolicyV1.observeTemporalPolicy(.temporaryFile,
                    at: directoryURL.appendingPathComponent(members[0].name))
            } else {
                guard members.count == 2, members.allSatisfy({ $0.links == 2 }),
                      members.filter({ Self.isTemporalPartialName($0.name) }).count == 1,
                      members.filter({ !$0.name.hasPrefix(".partial-") }).count == 1,
                      members[0].byteCount == members[1].byteCount,
                      members[0].mode == members[1].mode,
                      members[0].modifiedSeconds == members[1].modifiedSeconds,
                      members[0].modifiedNanoseconds == members[1].modifiedNanoseconds,
                      members[0].changedSeconds == members[1].changedSeconds,
                      members[0].changedNanoseconds == members[1].changedNanoseconds else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                let partial = members.first { Self.isTemporalPartialName($0.name) }!
                let final = members.first { !Self.isTemporalPartialName($0.name) }!
                _ = try ProtectedFilePolicyV1.observeTemporalScratchPair(
                    finalURL: directoryURL.appendingPathComponent(final.name),
                    partialURL: directoryURL.appendingPathComponent(partial.name))
            }
        }
        for member in ordered where member.name.hasPrefix(".partial-") {
            guard Self.isTemporalPartialName(member.name) else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        }
        for member in ordered {
            var current = stat()
            guard Darwin.fstatat(directory, member.name, &current, AT_SYMLINK_NOFOLLOW) == 0,
                  try TemporalScratchMemberObservationV1(name: member.name, information: current) == member else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
        }
        return ordered
    }

    private static func isTemporalPartialName(_ name: String) -> Bool {
        guard name.hasPrefix(".partial-"), let id = UUID(uuidString: String(name.dropFirst(9))) else { return false }
        return name == ".partial-" + id.uuidString.lowercased()
    }
}

/// Physical activity only: this proves a real shared lock on the existing
/// Application Support root. It never grants content access, writer or recovery rights.
/// Every retained child owns a distinct open description. Closing one child
/// cannot release another worker's lock or turn cancellation into drainage.
final class OwnedStorageProducerActivityV1: @unchecked Sendable {
    let applicationSupportURL: URL
    private let supportDescriptor: Int32
    private let supportDevice: dev_t
    private let supportInode: ino_t
    private let lock = NSLock()
    private var closed = false

    private init(applicationSupportURL: URL) throws {
        guard applicationSupportURL.isFileURL,
              !applicationSupportURL.path.utf8.contains(0) else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        let root = applicationSupportURL.standardizedFileURL
        let support = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard support >= 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        var supportInfo = stat()
        guard Darwin.fstat(support, &supportInfo) == 0,
              supportInfo.st_mode & S_IFMT == S_IFDIR,
              flock(support, LOCK_SH | LOCK_NB) == 0 else {
            Darwin.close(support)
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        self.applicationSupportURL = root
        supportDescriptor = support
        supportDevice = supportInfo.st_dev; supportInode = supportInfo.st_ino
        do { try verifyLocked() }
        catch { close(); throw error }
    }

    static func acquire(applicationSupportURL: URL) throws -> OwnedStorageProducerActivityV1 {
        try .init(applicationSupportURL: applicationSupportURL)
    }

    /// Ordinary installed-generation producers only. Restore, clone and
    /// source-recovery constructors retain their own distinct owner routes.
    static func acquireInstalledGeneration(generationRootURL: URL) throws -> OwnedStorageProducerActivityV1 {
        let generation = generationRootURL.standardizedFileURL
        let generations = generation.deletingLastPathComponent()
        let data = generations.deletingLastPathComponent()
        guard generationRootURL.isFileURL,
              let id = UUID(uuidString: generation.lastPathComponent),
              id.uuidString.lowercased() == generation.lastPathComponent,
              generations.lastPathComponent == "generations",
              data.lastPathComponent == OwnedStorageRootKindV1.data.rawValue else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        let activity = try acquire(applicationSupportURL: data.deletingLastPathComponent())
        do { try activity.requireInstalledGeneration(generationRootURL: generation) }
        catch { activity.close(); throw error }
        return activity
    }

    func retain() throws -> OwnedStorageProducerActivityV1 {
        try lock.withLock {
            try verifyLocked()
            let child = try Self.acquire(applicationSupportURL: applicationSupportURL)
            guard child.supportDevice == supportDevice, child.supportInode == supportInode else {
                child.close()
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            return child
        }
    }

    func requireApplicationSupport(_ expected: URL) throws {
        try lock.withLock {
            guard expected.standardizedFileURL == applicationSupportURL else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            try verifyLocked()
        }
    }

    func requireInstalledGeneration(generationRootURL: URL) throws {
        try lock.withLock {
            try verifyLocked()
            let value = generationRootURL.standardizedFileURL
            guard let id = UUID(uuidString: value.lastPathComponent),
                  id.uuidString.lowercased() == value.lastPathComponent,
                  value == applicationSupportURL.appendingPathComponent("FieldEvidenceData")
                    .appendingPathComponent("generations").appendingPathComponent(value.lastPathComponent) else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            var current = supportDescriptor
            var descriptors: [Int32] = []
            defer { descriptors.reversed().forEach { Darwin.close($0) } }
            for component in ["FieldEvidenceData", "generations", value.lastPathComponent] {
                let next = Darwin.openat(current, component,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                descriptors.append(next)
                var held = stat(), named = stat()
                guard Darwin.fstat(next, &held) == 0,
                      Darwin.fstatat(current, component, &named, AT_SYMLINK_NOFOLLOW) == 0,
                      held.st_mode & S_IFMT == S_IFDIR, held.st_dev == supportDevice,
                      held.st_dev == named.st_dev, held.st_ino == named.st_ino,
                      held.st_mode == named.st_mode else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                current = next
            }
            try verifyLocked()
        }
    }

    private func verifyLocked() throws {
        var support = stat(), namedSupport = stat()
        guard !closed,
              Darwin.fstat(supportDescriptor, &support) == 0,
              Darwin.lstat(applicationSupportURL.path, &namedSupport) == 0,
              [support, namedSupport].allSatisfy({
                  $0.st_dev == supportDevice && $0.st_ino == supportInode && $0.st_mode & S_IFMT == S_IFDIR
              }) else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
    }

    /// Resource shutdown needs no renewed content access. A caller must retain
    /// its own child until actual work and its cleanup tail have settled.
    func close() {
        lock.withLock {
            guard !closed else { return }
            closed = true
            flock(supportDescriptor, LOCK_UN)
            Darwin.close(supportDescriptor)
        }
    }

    deinit { close() }
}

/// Private SOURCE allocation for an actual normalization owner already holding
/// support EX. It never reacquires SH, recovers an older lease, renames another
/// owner's directory, or accepts a caller-selected request/root.
@MainActor
final class TemporalNormalizationSourceAllocationV1 {
    private let owner: TemporalNormalizationSourceOwnerV1
    let lease: ScratchDataLeaseV1
    private let supportURL: URL
    private let operationsURL: URL
    private let rootURL: URL
    let directoryURL: URL
    var modelURL: URL { directoryURL.appendingPathComponent("model.sqlite") }
    private var support: Int32 = -1
    private var operations: Int32 = -1
    private var root: Int32 = -1
    private var directory: Int32 = -1
    private var directoryIdentity: (dev_t, ino_t)?
    private var rootIdentity: (dev_t, ino_t)?
    private var supportIdentity: (dev_t, ino_t)?
    private var operationsIdentity: (dev_t, ino_t)?
    private var createdRoot = false
    private var createdDirectory = false
    private var closed = false
    private var rootNeedsSync = false
    private var operationsNeedsSync = false
    private(set) var observedExistingRootPolicy: TemporalPolicyObservationV1?
    private var ownedFiles: [String: TemporalNormalizationSourceTargetV1] = [:]

    private init(owner: TemporalNormalizationSourceOwnerV1, request: ScratchDataLeaseRequestV1) throws {
        self.owner = owner
        supportURL = owner.applicationSupportURL
        operationsURL = supportURL.appendingPathComponent("FieldEvidenceOperations")
        rootURL = operationsURL.appendingPathComponent("ScratchDataV1")
        let name = "source-" + request.leaseID.uuidString.lowercased()
        lease = try ScratchDataLeaseV1(request: request, relativeDirectory: name)
        directoryURL = rootURL.appendingPathComponent(name)
    }

    static func allocate(owner: TemporalNormalizationSourceOwnerV1,
                         scope: TemporalNormalizationOriginalAccessScopeV1) throws
        -> TemporalNormalizationSourceAllocationV1 {
        let request = try owner.requirePrivateSourceAllocationRequest(scope: scope)
        let value = try TemporalNormalizationSourceAllocationV1(owner: owner, request: request)
        try owner.registerPrivateSourceAllocation(value, scope: scope)
        // Registration precedes the first mkdir. A partial creation failure
        // remains held by the concrete owner until exact cleanup succeeds.
        try value.create(scope: scope)
        return value
    }

    private func create(scope: TemporalNormalizationOriginalAccessScopeV1) throws {
        try owner.revalidatePrivateSourceAllocation(self, scope: scope)
        support = Darwin.open(supportURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard support >= 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        supportIdentity = try Self.identity(support)
        try owner.requirePrivateSourceSupportDescriptor(support, allocation: self)
        operations = Darwin.openat(support, "FieldEvidenceOperations", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard operations >= 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        operationsIdentity = try Self.identity(operations)
        try verifyParents()
        var named = stat()
        if Darwin.fstatat(operations, "ScratchDataV1", &named, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT,
                  Darwin.mkdirat(operations, "ScratchDataV1", mode_t(0o700)) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            createdRoot = true
        }
        root = Darwin.openat(operations, "ScratchDataV1", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        rootIdentity = try Self.identity(root)
        try verifyParents()
        if createdRoot {
            try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: rootURL,
                authorityCheck: { try self.verifyParents() })
            guard Darwin.fsync(root) == 0, Darwin.fsync(operations) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
        } else {
            observedExistingRootPolicy = try ProtectedFilePolicyV1.observeTemporalPolicy(.stagingDirectory, at: rootURL)
        }
        try StoragePreflightService().checkScratchLease(
            requestedByteCount: lease.request.requestedByteCount, onVolumeContaining: rootURL)
        try owner.revalidatePrivateSourceAllocation(self, scope: scope)
        guard Darwin.mkdirat(root, lease.relativeDirectory, mode_t(0o700)) == 0 else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        createdDirectory = true
        directory = Darwin.openat(root, lease.relativeDirectory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        directoryIdentity = try Self.identity(directory)
        guard flock(directory, LOCK_EX | LOCK_NB) == 0 else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try verifyDirectory()
        try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: directoryURL,
            authorityCheck: { try self.verifyDirectory() })
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let metadata = try encoder.encode(lease)
        let target = try makeOwnedTarget(name: "lease.json", expectedBytes: UInt64(metadata.count))
        try target.append(metadata)
        try target.finish()
        guard Darwin.fsync(directory) == 0, Darwin.fsync(root) == 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        try owner.revalidatePrivateSourceAllocation(self, scope: scope)
    }

    func createSQLiteTarget(named name: String,
                            scope: TemporalNormalizationOriginalAccessScopeV1) throws
        -> TemporalNormalizationSourceTargetV1 {
        try owner.revalidatePrivateSourceAllocation(self, scope: scope)
        let byteCount = try owner.expectedPrivateSQLiteByteCount(named: name, allocation: self)
        return try makeOwnedTarget(name: name, expectedBytes: byteCount)
    }

    private func makeOwnedTarget(name: String, expectedBytes: UInt64) throws -> TemporalNormalizationSourceTargetV1 {
        try verifyDirectory()
        guard ["lease.json", "model.sqlite", "model.sqlite-wal", "model.sqlite-shm"].contains(name),
              ownedFiles[name] == nil else { throw ScratchDataLeaseStoreFailureV1.invalidLease }
        let fd = Darwin.openat(directory, name, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        let target: TemporalNormalizationSourceTargetV1
        do {
            target = try TemporalNormalizationSourceTargetV1(descriptor: fd, parent: directory,
                name: name, expectedBytes: expectedBytes)
        } catch { _ = Darwin.close(fd); throw error }
        ownedFiles[name] = target
        try ProtectedFilePolicyV1.applyAndVerify(.temporaryFile,
            at: directoryURL.appendingPathComponent(name), authorityCheck: {
                try self.verifyDirectory(); try target.revalidate()
            })
        return target
    }

    func verifyForRead() throws {
        try verifyDirectory()
        for (name, target) in ownedFiles {
            if name == "model.sqlite-shm", owner.hasActualPrivateReaderAttempt(allocation: self) {
                continue // the actual private SQLite connection owns this auxiliary only
            }
            try target.revalidate()
        }
    }

    /// Only called after the owner's actual worker joined and weak container
    /// and context references disappeared. This does not require renewed read
    /// permission and does not touch any preexisting scratch lease.
    func closeAfterReaderDrain() throws {
        guard !closed else { return }
        try owner.requirePrivateSourceWorkersAndReadersDrained(allocation: self)
        try owner.revalidateSourceCleanupScope(allocation: self)
        if createdDirectory {
            try verifyDirectory()
            let names = try StoreRestoreGenerationAuthority.names(in: directory)
            let allowed = Set(["lease.json", "model.sqlite", "model.sqlite-wal", "model.sqlite-shm"])
            guard Set(names).isSubset(of: allowed) else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            // SQLite may introduce only its own wal-index inside this newly
            // created directory. Other newly observed names are never adopted.
            for name in names where ownedFiles[name] == nil {
                guard name == "model.sqlite-shm" else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                try owner.requireActualPrivateReaderAttempt(allocation: self)
                let fd = Darwin.openat(directory, name, O_RDWR | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
                guard fd >= 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                do {
                    var info = stat()
                    guard Darwin.fstat(fd, &info) == 0, info.st_size >= 0,
                          UInt64(info.st_size) <= lease.request.requestedByteCount else {
                        throw ScratchDataLeaseStoreFailureV1.invalidRoot
                    }
                    ownedFiles[name] = try TemporalNormalizationSourceTargetV1(descriptor: fd,
                        parent: directory, name: name, expectedBytes: UInt64(info.st_size), initiallyComplete: true)
                } catch { _ = Darwin.close(fd); throw error }
            }
            guard Set(names) == Set(ownedFiles.keys) else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            if let index = ownedFiles["model.sqlite-shm"], owner.hasActualPrivateReaderAttempt(allocation: self) {
                try index.settlePrivateReaderIndex(maximumBytes: lease.request.requestedByteCount)
            }
            for name in names.sorted() {
                guard let target = ownedFiles[name] else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                try target.revalidate()
                guard Darwin.unlinkat(directory, name, 0) == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                target.close()
                ownedFiles.removeValue(forKey: name)
            }
            guard Darwin.fsync(directory) == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            try verifyDirectory()
            guard Darwin.unlinkat(root, lease.relativeDirectory, AT_REMOVEDIR) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            createdDirectory = false; rootNeedsSync = true
        }
        if rootNeedsSync {
            guard Darwin.fsync(root) == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            rootNeedsSync = false
        }
        if createdRoot {
            try verifyParents()
            guard try StoreRestoreGenerationAuthority.names(in: root).isEmpty,
                  Darwin.unlinkat(operations, "ScratchDataV1", AT_REMOVEDIR) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            createdRoot = false; operationsNeedsSync = true
        }
        if operationsNeedsSync {
            guard Darwin.fsync(operations) == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            operationsNeedsSync = false
        }
        for fd in [directory, root, operations, support] where fd >= 0 { _ = Darwin.close(fd) }
        directory = -1; root = -1; operations = -1; support = -1
        closed = true
    }

    func requireClosed() throws {
        guard closed, directory < 0, root < 0, operations < 0, support < 0,
              ownedFiles.isEmpty, !rootNeedsSync, !operationsNeedsSync else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
    }

    private static func identity(_ fd: Int32) throws -> (dev_t, ino_t) {
        var value = stat()
        guard Darwin.fstat(fd, &value) == 0, value.st_mode & S_IFMT == S_IFDIR else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        return (value.st_dev, value.st_ino)
    }
    private func verifyParents() throws {
        guard !closed, let supportIdentity, let operationsIdentity,
              try Self.identity(support) == supportIdentity,
              try Self.identity(operations) == operationsIdentity,
              operationsIdentity.0 == supportIdentity.0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        try owner.requirePrivateSourceSupportDescriptor(support, allocation: self)
        var named = stat()
        guard Darwin.lstat(supportURL.path, &named) == 0, named.st_mode & S_IFMT == S_IFDIR,
              (named.st_dev, named.st_ino) == supportIdentity,
              Darwin.fstatat(support, "FieldEvidenceOperations", &named, AT_SYMLINK_NOFOLLOW) == 0,
              named.st_mode & S_IFMT == S_IFDIR,
              (named.st_dev, named.st_ino) == operationsIdentity else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        if let rootIdentity {
            guard try Self.identity(root) == rootIdentity, rootIdentity.0 == supportIdentity.0,
                  Darwin.fstatat(operations, "ScratchDataV1", &named, AT_SYMLINK_NOFOLLOW) == 0,
                  named.st_mode & S_IFMT == S_IFDIR,
                  (named.st_dev, named.st_ino) == rootIdentity else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        }
    }
    private func verifyDirectory() throws {
        try verifyParents()
        guard createdDirectory, let directoryIdentity, let rootIdentity,
              directoryIdentity.0 == rootIdentity.0,
              try Self.identity(directory) == directoryIdentity else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        var named = stat()
        guard Darwin.fstatat(root, lease.relativeDirectory, &named, AT_SYMLINK_NOFOLLOW) == 0,
              named.st_mode & S_IFMT == S_IFDIR,
              (named.st_dev, named.st_ino) == directoryIdentity else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
    }
}

/// A held descriptor for one newly allocated private file. It cannot be
/// constructed outside this ledger file and never names an original input.
final class TemporalNormalizationSourceTargetV1: @unchecked Sendable {
    private var descriptor: Int32
    private let parent: Int32
    private let name: String
    private let device: dev_t, inode: ino_t
    private let expectedBytes: UInt64
    private var written: UInt64
    private var complete: Bool
    private var completedTimes: [Int64]?
    private let lock = NSLock()
    fileprivate init(descriptor: Int32, parent: Int32, name: String, expectedBytes: UInt64,
                     initiallyComplete: Bool = false) throws {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_nlink == 1, info.st_size >= 0,
              UInt64(info.st_size) == (initiallyComplete ? expectedBytes : 0) else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        self.descriptor = descriptor; self.parent = parent; self.name = name
        device = info.st_dev; inode = info.st_ino; self.expectedBytes = expectedBytes
        written = initiallyComplete ? expectedBytes : 0; complete = initiallyComplete
        completedTimes = initiallyComplete ? Self.times(info) : nil
    }
    private func verifyLocked() throws {
        var held = stat(), named = stat()
        guard descriptor >= 0, Darwin.fstat(descriptor, &held) == 0,
              Darwin.fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              [held, named].allSatisfy({ $0.st_mode & S_IFMT == S_IFREG && $0.st_nlink == 1 &&
                  $0.st_dev == device && $0.st_ino == inode && $0.st_size >= 0 && UInt64($0.st_size) == written }) else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        if complete {
            guard let completedTimes, Self.times(held) == completedTimes,
                  Self.times(named) == completedTimes else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        }
    }
    private static func times(_ value: stat) -> [Int64] {
        [Int64(value.st_mtimespec.tv_sec), Int64(value.st_mtimespec.tv_nsec),
         Int64(value.st_ctimespec.tv_sec), Int64(value.st_ctimespec.tv_nsec)]
    }
    fileprivate func settlePrivateReaderIndex(maximumBytes: UInt64) throws {
        try lock.withLock {
            var held = stat(), named = stat()
            guard name == "model.sqlite-shm", descriptor >= 0,
                  Darwin.fstat(descriptor, &held) == 0,
                  Darwin.fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
                  [held, named].allSatisfy({ $0.st_mode & S_IFMT == S_IFREG && $0.st_nlink == 1 &&
                      $0.st_dev == device && $0.st_ino == inode && $0.st_size >= 0 && UInt64($0.st_size) <= maximumBytes }),
                  held.st_size == named.st_size, Self.times(held) == Self.times(named) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            written = UInt64(held.st_size); completedTimes = Self.times(held); complete = true
        }
    }
    func revalidate() throws { try lock.withLock { try verifyLocked() } }
    var fileName: String { name }
    var expectedByteCount: UInt64 { expectedBytes }
    func readChunk(offset: UInt64, maximumCount: Int = 65_536) throws -> Data {
        try lock.withLock {
            try verifyLocked()
            guard complete, maximumCount > 0, maximumCount <= 65_536,
                  offset <= expectedBytes else { throw ScratchDataLeaseStoreFailureV1.invalidLease }
            let count = min(UInt64(maximumCount), expectedBytes - offset)
            var data = Data(count: Int(count))
            try data.withUnsafeMutableBytes { bytes in
                var done = 0
                while done < bytes.count {
                    let amount = Darwin.pread(descriptor, bytes.baseAddress!.advanced(by: done),
                        bytes.count - done, off_t(offset + UInt64(done)))
                    if amount < 0, errno == EINTR { continue }
                    guard amount > 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                    done += amount
                }
            }
            try verifyLocked()
            return data
        }
    }
    func append(_ data: Data) throws {
        try lock.withLock {
            try verifyLocked()
            let (total, overflow) = written.addingReportingOverflow(UInt64(data.count))
            guard !complete, !overflow, total <= expectedBytes, data.count <= 65_536 else {
                throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
            }
            try data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if count < 0, errno == EINTR { continue }
                    guard count > 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                    offset += count; written += UInt64(count)
                }
            }
            try verifyLocked()
        }
    }
    func finish() throws {
        try lock.withLock {
            try verifyLocked()
            guard written == expectedBytes, Darwin.fsync(descriptor) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            var information = stat()
            guard Darwin.fstat(descriptor, &information) == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            completedTimes = Self.times(information)
            complete = true
            try verifyLocked()
        }
    }
    func close() { lock.withLock { if descriptor >= 0 { _ = Darwin.close(descriptor); descriptor = -1 } } }
    deinit { close() }
}

/// Read-only cold observer. Manifest supplies the retained root FD and
/// re-proves its first/projected facts around this synchronous callback.
/// Every child and policy probe descriptor has checked, sticky close state.
@MainActor final class EraseSchema2ColdNotificationCheckedReadV1 {
    private let source: EraseSchema2ColdNotificationSourceV1
    private let io = EraseAbortCheckedSnapshotIOV1()
    private var uncertainPolicyDescriptors: [Int32] = []

    init(source: EraseSchema2ColdNotificationSourceV1) {
        self.source = source
    }

    func requireSettled() throws {
        try io.requireSettled()
        guard uncertainPolicyDescriptors.isEmpty else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
    }

    func cut() throws -> EraseSchema2ColdNotificationCheckedCutV1 {
        return try source.withHeldRoot { rootFD, rootURL in
            try cutBorrowed(rootFD: rootFD, rootURL: rootURL)
        }
    }

    /// The Manifest's mutation scope supplies this exact retained root FD;
    /// it is never returned or used after the scoped callback.
    func cutBorrowed(rootFD: Int32, rootURL: URL)
        throws -> EraseSchema2ColdNotificationCheckedCutV1 {
        try requireSettled()
            var beforeRoot = stat(), afterRoot = stat()
            guard Darwin.fstat(rootFD, &beforeRoot) == 0,
                  beforeRoot.st_mode & S_IFMT == S_IFDIR else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            let firstPolicy = try ProtectedFilePolicyV1
                .observeTemporalPolicyWithCheckedClose(
                    .stagingDirectory, at: rootURL,
                    retainUncertainDescriptor: { value in
                        self.uncertainPolicyDescriptors.append(value)
                    })
            guard firstPolicy.device == UInt64(beforeRoot.st_dev),
                  firstPolicy.inode == UInt64(beforeRoot.st_ino),
                  firstPolicy.linkCount == UInt64(beforeRoot.st_nlink),
                  firstPolicy.state == .strictComplete ||
                    firstPolicy.state == .pendingSimulatorRequest else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            let names = try io.names(in: rootFD)
            let allowed: Set<String> = [
                AppLockNotificationControlStoreV1.recordName,
                AppLockNotificationControlStoreV1.pendingName,
                AppLockNotificationControlStoreV1.mappingName,
                AppLockNotificationControlStoreV1.mappingPendingName,
                AppLockNotificationControlStoreV1.eraseName,
                AppLockNotificationControlStoreV1.erasePendingName,
                EraseSchema2ColdNotificationSourceV1.ownedIDsName,
                EraseSchema2ColdNotificationSourceV1
                    .ownedIDsTemporaryName,
                EraseSchema2ColdNotificationSourceV1.drainName,
                EraseSchema2ColdNotificationSourceV1.drainTemporaryName,
            ]
            guard Set(names).isSubset(of: allowed) else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            var bytes: [String: Data] = [:]
            var facts: [String: EraseColdControlLeafFactV1] = [:]
            for name in names {
                let value = try checkedLeaf(
                    rootFD: rootFD, rootURL: rootURL, name: name)
                bytes[name] = value.bytes
                facts[name] = value.fact
            }
            let secondPolicy = try ProtectedFilePolicyV1
                .observeTemporalPolicyWithCheckedClose(
                    .stagingDirectory, at: rootURL,
                    retainUncertainDescriptor: { value in
                        self.uncertainPolicyDescriptors.append(value)
                    })
            guard firstPolicy == secondPolicy,
                  try io.names(in: rootFD) == names,
                  Darwin.fstat(rootFD, &afterRoot) == 0,
                  EraseColdControlLeafFactV1(beforeRoot)
                    == EraseColdControlLeafFactV1(afterRoot) else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            try requireSettled()
            return EraseSchema2ColdNotificationCheckedCutV1(
                rootFact: EraseColdControlLeafFactV1(afterRoot),
                names: names, leafBytes: bytes, leafFacts: facts)
    }

    private func checkedLeaf(
        rootFD: Int32, rootURL: URL, name: String
    ) throws -> (bytes: Data, fact: EraseColdControlLeafFactV1) {
        try io.withOpen(parent: rootFD, name: name,
            flags: O_RDONLY | O_NONBLOCK) { fd in
            var before = stat(), after = stat(), named = stat()
            guard Darwin.fstat(fd, &before) == 0,
                  before.st_mode & S_IFMT == S_IFREG,
                  before.st_nlink == 1,
                  before.st_size >= 0,
                  (before.st_size > 0 ||
                    [AppLockNotificationControlStoreV1.pendingName,
                     AppLockNotificationControlStoreV1.mappingPendingName,
                     AppLockNotificationControlStoreV1.erasePendingName,
                     EraseSchema2ColdNotificationSourceV1
                        .ownedIDsTemporaryName,
                     EraseSchema2ColdNotificationSourceV1
                        .drainTemporaryName].contains(name)),
                  before.st_size <= off_t(
                    AppLockNotificationControlStoreV1.maximumRecordBytes),
                  Darwin.fstatat(rootFD, name, &named,
                    AT_SYMLINK_NOFOLLOW) == 0,
                  EraseColdControlLeafFactV1(before)
                    == EraseColdControlLeafFactV1(named) else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            let firstFact = EraseColdControlLeafFactV1(before)
            let kind: OwnedFileKindV1 =
                [AppLockNotificationControlStoreV1.pendingName,
                 AppLockNotificationControlStoreV1.mappingPendingName,
                 AppLockNotificationControlStoreV1.erasePendingName,
                 EraseSchema2ColdNotificationSourceV1
                    .ownedIDsTemporaryName,
                 EraseSchema2ColdNotificationSourceV1.drainTemporaryName]
                    .contains(name) ? .journalTemporary : .journal
            let url = rootURL.appendingPathComponent(name)
            let reservedTemporary = kind == .journalTemporary
            let firstPolicy: TemporalPolicyObservationV1?
            do {
                firstPolicy = try ProtectedFilePolicyV1
                    .observeTemporalPolicyWithCheckedClose(kind,
                        at: url, retainUncertainDescriptor: { value in
                            self.uncertainPolicyDescriptors.append(value)
                        })
            } catch ProtectedFilePolicyError.resourceValueMismatch {
                // O_EXCL creation and a prefix write precede the checked
                // policy setter. This exact reserved temp remains opaque
                // data; only publishCanonical may request complete policy
                // under the retained operation before any unlink/adoption.
                guard reservedTemporary,
                      before.st_mode & 0o777 == 0o600 else {
                    throw ProtectedFilePolicyError.resourceValueMismatch
                }
                firstPolicy = nil
            }
            if let firstPolicy {
                guard firstPolicy.device == UInt64(before.st_dev),
                      firstPolicy.inode == UInt64(before.st_ino),
                      firstPolicy.linkCount == 1,
                      firstPolicy.state == .strictComplete ||
                        firstPolicy.state == .pendingSimulatorRequest else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
            }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            while true {
                let count = buffer.withUnsafeMutableBytes {
                    Darwin.read(fd, $0.baseAddress, $0.count)
                }
                if count > 0 {
                    guard data.count <= Int(before.st_size) - count else {
                        throw AppAccessContractFailureV1.configurationUnknown
                    }
                    data.append(contentsOf: buffer.prefix(count))
                } else if count == 0 { break }
                else if errno != EINTR {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
            }
            let secondPolicy: TemporalPolicyObservationV1?
            do {
                secondPolicy = try ProtectedFilePolicyV1
                    .observeTemporalPolicyWithCheckedClose(kind,
                        at: url, retainUncertainDescriptor: { value in
                            self.uncertainPolicyDescriptors.append(value)
                        })
            } catch ProtectedFilePolicyError.resourceValueMismatch {
                guard reservedTemporary,
                      before.st_mode & 0o777 == 0o600 else {
                    throw ProtectedFilePolicyError.resourceValueMismatch
                }
                secondPolicy = nil
            }
            guard data.count == Int(before.st_size),
                  Darwin.fstat(fd, &after) == 0,
                  Darwin.fstatat(rootFD, name, &named,
                    AT_SYMLINK_NOFOLLOW) == 0,
                  firstFact == EraseColdControlLeafFactV1(after),
                  firstFact == EraseColdControlLeafFactV1(named),
                  firstPolicy == secondPolicy else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            return (data, firstFact)
        }
    }
}

/// Cold-only notification control. Construction retains the operation and
/// Manifest source without opening a second application-support owner. Every
/// read remains scoped to the held root and uses checked transient IO.
#if DEBUG
enum EraseSchema2ColdNotificationTemporaryFaultCutV1 {
    case afterCreateBeforePolicy
    case afterStrictPrefixBeforePolicy
}
#endif

@MainActor final class EraseSchema2ColdNotificationControlV1:
    Schema2ColdNotificationEraseControlV1 {
    private let source: EraseSchema2ColdNotificationSourceV1
    private let operation: EraseColdPreparationOperationV1
    private let checkedRead: EraseSchema2ColdNotificationCheckedReadV1
    private let mutationIO = EraseAbortCheckedSnapshotIOV1()
    private var uncertainPolicyDescriptors: [Int32] = []
    private var rootIdentityValue: String
    private var rootPolicyDisposition:
        ProtectedFileVerificationDispositionV1?
    private var canonicalCreationSettled = false
    private var reservedProvenance:
        NotificationEraseOwnedIDsProvenanceV1?
    private var osAbsence: EraseSchema2ColdNotificationOSAbsenceReceiptV1?

    #if DEBUG
    var temporaryFaultForTesting:
        (@MainActor (EraseSchema2ColdNotificationMutationStageV1,
            EraseSchema2ColdNotificationTemporaryFaultCutV1)
            throws -> Void)?
    #endif

    init(source: EraseSchema2ColdNotificationSourceV1,
         operation: EraseColdPreparationOperationV1) {
        self.source = source
        self.operation = operation
        checkedRead = EraseSchema2ColdNotificationCheckedReadV1(
            source: source)
        rootIdentityValue = source.rootIdentity ?? ""
    }

    var notificationRootIdentity: String { rootIdentityValue }

    func requireCheckedSettled() throws {
        try checkedRead.requireSettled()
        try mutationIO.requireSettled()
        guard uncertainPolicyDescriptors.isEmpty else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
    }

    private func ensureRoot() throws {
        try requireCheckedSettled()
        if source.rootIdentity == nil && rootIdentityValue.isEmpty {
            let created = try source.createRootFromFirstAbsence()
            guard created.source === source,
                  created.checkedSettled else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            rootIdentityValue = created.rootIdentity
            rootPolicyDisposition = created.policyDisposition
        }
        if source.rootIdentity != nil,
           source.hasAuthenticatedCreationRecord,
           source.names.isEmpty,
           !canonicalCreationSettled {
            let settled = try source.settleCanonicalCreationAfterReplay()
            guard settled.source === source,
                  settled.rootIdentity == rootIdentityValue,
                  settled.checkedSettled else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            rootPolicyDisposition = settled.policyDisposition
            canonicalCreationSettled = true
        }
        // A raw first-present canonical root has no proof that this Erase
        // created it. It remains data-only until a separate creation-record
        // replay proves provenance; ordinary policy repair is not authority.
        if source.rootIdentity != nil, source.rootPolicy == nil,
           !canonicalCreationSettled {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        guard !rootIdentityValue.isEmpty,
              try source.requireCurrentRootIdentity()
                == rootIdentityValue else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        if rootPolicyDisposition == nil {
            let url = try source.withHeldRoot { _, rootURL in rootURL }
            rootPolicyDisposition = try ProtectedFilePolicyV1
                .verifyEraseColdTemporalPolicyWithCheckedRequest(
                    .stagingDirectory, at: url,
                    retainUncertainDescriptor: { value in
                        self.uncertainPolicyDescriptors.append(value)
                    }, unchangedWitness: {
                        try self.checkedRead.cut()
                    })
        } else {
            let cut = try checkedRead.cut()
            let url = try source.withHeldRoot { _, rootURL in rootURL }
            let observed = try ProtectedFilePolicyV1
                .observeTemporalPolicyWithCheckedClose(
                    .stagingDirectory, at: url,
                    retainUncertainDescriptor: { value in
                        self.uncertainPolicyDescriptors.append(value)
                    })
            guard let fact = cut.rootFact,
                  observed.device == UInt64(fact.device),
                  observed.inode == UInt64(fact.inode),
                  observed.linkCount == UInt64(fact.links),
                  observed.state == .strictComplete ||
                    observed.state == .pendingSimulatorRequest,
                  try checkedRead.cut() == cut else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        }
        try requireCheckedSettled()
    }

    private func requireLeafPolicy(
        _ name: String, kind: OwnedFileKindV1
    ) throws {
        try ensureRoot()
        let url = try source.withHeldRoot { _, rootURL in
            rootURL.appendingPathComponent(name)
        }
        let initial = try checkedRead.cut()
        guard initial.leafFacts[name] != nil else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        _ = try ProtectedFilePolicyV1
            .verifyEraseColdTemporalPolicyWithCheckedRequest(
                kind, at: url,
                retainUncertainDescriptor: { value in
                    self.uncertainPolicyDescriptors.append(value)
                }, unchangedWitness: {
                    let current = try self.checkedRead.cut()
                    guard current == initial else {
                        throw AppAccessContractFailureV1.configurationUnknown
                    }
                    return current.leafFacts[name]
                })
        guard try checkedRead.cut() == initial else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try requireCheckedSettled()
    }

    private func decodeCanonical<Value: Codable>(
        _ type: Value.Type, bytes: Data
    ) throws -> Value {
        guard !bytes.isEmpty,
              bytes.count <= AppLockNotificationControlStoreV1
                .maximumRecordBytes else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let value = try JSONDecoder().decode(type, from: bytes)
        guard try CompatibilityCanonicalV1.encode(value) == bytes else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        return value
    }

    private func decodeCanonicalControl(
        _ bytes: Data
    ) throws -> AppLockNotificationControlV1 {
        let value = try decodeCanonical(
            AppLockNotificationControlV1.self, bytes: bytes)
        let checked = try AppLockNotificationControlV1(
            journal: value.journal,
            priorReminderPolicy: value.priorReminderPolicy,
            settingWrite: value.settingWrite,
            phase: value.phase,
            reminderPolicyContinuation:
                value.reminderPolicyContinuation)
        guard checked == value else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        return checked
    }

    func verifyNotificationStorage() throws {
        try ensureRoot()
        _ = try checkedRead.cut()
    }

    func loadPrivateNotificationMapping()
        throws -> NotificationPrivateMappingV1? {
        try ensureRoot()
        let before = try checkedRead.cut()
        guard let bytes = before.leafBytes[
            AppLockNotificationControlStoreV1.mappingName] else {
            return nil
        }
        try requireLeafPolicy(
            AppLockNotificationControlStoreV1.mappingName,
            kind: .journal)
        guard try checkedRead.cut() == before else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let value = try decodeCanonical(
            NotificationPrivateMappingV1.self, bytes: bytes)
        try value.validate()
        return value
    }

    func loadControl() throws -> AppLockNotificationControlV1? {
        try ensureRoot()
        let before = try checkedRead.cut()
        guard let bytes = before.leafBytes[
            AppLockNotificationControlStoreV1.recordName] else {
            return nil
        }
        try requireLeafPolicy(
            AppLockNotificationControlStoreV1.recordName,
            kind: .journal)
        guard try checkedRead.cut() == before else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        return try decodeCanonicalControl(bytes)
    }

    func requireSchema2ColdRevocation(
        _ revocation: NotificationEraseRevocationV1
    ) throws {
        try ensureRoot()
        try revocation.validate()
        guard revocation.operationID == source.eraseID,
              revocation.rootIdentity == rootIdentityValue else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        try requireLeafPolicy(
            AppLockNotificationControlStoreV1.eraseName,
            kind: .journal)
        let cut = try checkedRead.cut()
        guard let bytes = cut.leafBytes[
                AppLockNotificationControlStoreV1.eraseName],
              try decodeCanonical(
                NotificationEraseRevocationV1.self, bytes: bytes)
                == revocation else {
            throw AppAccessContractFailureV1.effectMismatch
        }
    }

    func requireNotificationEraseRevocation(
        _ revocation: NotificationEraseRevocationV1
    ) throws {
        try requireSchema2ColdRevocation(revocation)
        let cut = try checkedRead.cut()
        let remaining: Set<String> = [
            AppLockNotificationControlStoreV1.eraseName,
            EraseSchema2ColdNotificationSourceV1.ownedIDsName,
            EraseSchema2ColdNotificationSourceV1.drainName]
        guard Set(cut.names) == remaining,
              cut.leafBytes[
                EraseSchema2ColdNotificationSourceV1.drainName] != nil else {
            throw AppAccessContractFailureV1
                .notificationReconciliationRequired
        }
    }

    func loadSchema2ColdDrainRecord(
        revocation: NotificationEraseRevocationV1
    ) throws -> NotificationEraseDrainRecordV1? {
        try requireSchema2ColdRevocation(revocation)
        let cut = try checkedRead.cut()
        guard let bytes = cut.leafBytes[
            EraseSchema2ColdNotificationSourceV1.drainName] else {
            // A first-captured marker with no surviving mapping or control
            // has lost its owned-ID witness. Do not reinterpret that legacy
            // cut as an empty owned set on fresh recovery.
            if source.names.contains(
                    AppLockNotificationControlStoreV1.eraseName),
               !source.names.contains(
                    AppLockNotificationControlStoreV1.mappingName),
               !source.names.contains(
                    AppLockNotificationControlStoreV1.recordName),
               !source.names.contains(
                    EraseSchema2ColdNotificationSourceV1.ownedIDsName) {
                throw AppAccessContractFailureV1
                    .notificationReconciliationRequired
            }
            return nil
        }
        try requireLeafPolicy(
            EraseSchema2ColdNotificationSourceV1.drainName,
            kind: .journal)
        guard try checkedRead.cut() == cut else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let record = try decodeCanonical(
            NotificationEraseDrainRecordV1.self, bytes: bytes)
        try record.validate(revocation: revocation)
        return record
    }

    func requireSchema2ColdDrainRecord(
        _ record: NotificationEraseDrainRecordV1,
        revocation: NotificationEraseRevocationV1
    ) throws {
        guard try loadSchema2ColdDrainRecord(
                revocation: revocation) == record else {
            throw AppAccessContractFailureV1.effectMismatch
        }
    }

    func retainSchema2ColdOSAbsence(
        _ receipt: EraseSchema2ColdNotificationOSAbsenceReceiptV1
    ) throws {
        if let prior = osAbsence {
            try prior.requireRetained(to: self,
                operationID: source.eraseID)
            guard prior.drainRecord == receipt.drainRecord else {
                throw AppAccessContractFailureV1.effectMismatch
            }
        }
        try receipt.requireBound(to: self,
            operationID: source.eraseID, drainPublished: false)
        osAbsence = receipt
    }

    func requireSchema2ColdOSAbsence(
        stage: EraseSchema2ColdNotificationMutationStageV1
    ) throws {
        guard let osAbsence,
              stage == .publishDrainReceipt || stage == .removeMapping
                || stage == .removeControl else {
            throw AppAccessContractFailureV1
                .notificationReconciliationRequired
        }
        // Manifest independently checks the exact stage's physical cut. A
        // generic source re-entry here would demand pre-effect root metadata.
        try osAbsence.requireRetained(to: self,
            operationID: source.eraseID)
    }

    func beginNotificationErase(
        operationID: UUID
    ) throws -> NotificationEraseRevocationV1 {
        guard operationID == source.eraseID else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        try ensureRoot()
        guard let reservedProvenance else {
            throw AppAccessContractFailureV1
                .notificationReconciliationRequired
        }
        try requireSchema2ColdOwnedIDs(reservedProvenance)
        let value = NotificationEraseRevocationV1(schemaVersion: 1,
            operationID: operationID, rootIdentity: rootIdentityValue)
        try value.validate()
        let cut = try checkedRead.cut()
        if let bytes = cut.leafBytes[
            AppLockNotificationControlStoreV1.eraseName] {
            try requireLeafPolicy(
                AppLockNotificationControlStoreV1.eraseName,
                kind: .journal)
            guard try decodeCanonical(
                    NotificationEraseRevocationV1.self, bytes: bytes)
                    == value,
                  try checkedRead.cut() == cut else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            return value
        }
        try publishCanonical(
            try CompatibilityCanonicalV1.encode(value),
            name: AppLockNotificationControlStoreV1.eraseName,
            temporary: AppLockNotificationControlStoreV1.erasePendingName,
            stage: .publishRevocation)
        try requireSchema2ColdRevocation(value)
        return value
    }

    func reserveSchema2ColdOwnedIDs(
        operationID: UUID
    ) throws -> NotificationEraseOwnedIDsProvenanceV1 {
        guard operationID == source.eraseID else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        try ensureRoot()
        let cut = try checkedRead.cut()
        let ownedName = EraseSchema2ColdNotificationSourceV1
            .ownedIDsName
        let ownedTemporary = EraseSchema2ColdNotificationSourceV1
            .ownedIDsTemporaryName
        let markerName = AppLockNotificationControlStoreV1.eraseName
        let markerTemporary =
            AppLockNotificationControlStoreV1.erasePendingName
        let drainName = EraseSchema2ColdNotificationSourceV1.drainName
        let drainTemporary = EraseSchema2ColdNotificationSourceV1
            .drainTemporaryName
        for pending in [AppLockNotificationControlStoreV1.pendingName,
            AppLockNotificationControlStoreV1.mappingPendingName,
            markerTemporary, ownedTemporary, drainTemporary]
            where cut.leafBytes[pending] != nil {
            // Only a temp in the exact next stage is data-only admissible.
            // Its canonical prefix is checked below before any OS effect;
            // publishCanonical later makes the checked policy request before
            // unlink/adoption. Unknown and crossed stages still refuse.
            if pending == ownedTemporary {
                guard cut.leafBytes[ownedName] == nil,
                      cut.leafBytes[markerName] == nil,
                      cut.leafBytes[markerTemporary] == nil,
                      cut.leafBytes[drainName] == nil,
                      cut.leafBytes[drainTemporary] == nil else {
                    throw AppAccessContractFailureV1
                        .notificationReconciliationRequired
                }
            } else if pending == markerTemporary {
                guard cut.leafBytes[ownedName] != nil,
                      cut.leafBytes[ownedTemporary] == nil,
                      cut.leafBytes[markerName] == nil,
                      cut.leafBytes[drainName] == nil,
                      cut.leafBytes[drainTemporary] == nil else {
                    throw AppAccessContractFailureV1
                        .notificationReconciliationRequired
                }
            } else if pending == drainTemporary {
                guard cut.leafBytes[ownedName] != nil,
                      cut.leafBytes[ownedTemporary] == nil,
                      cut.leafBytes[markerName] != nil,
                      cut.leafBytes[markerTemporary] == nil,
                      cut.leafBytes[drainName] == nil else {
                    throw AppAccessContractFailureV1
                        .notificationReconciliationRequired
                }
            } else {
                throw AppAccessContractFailureV1
                    .notificationReconciliationRequired
            }
        }
        let mappingBytes = cut.leafBytes[
            AppLockNotificationControlStoreV1.mappingName]
        let controlBytes = cut.leafBytes[
            AppLockNotificationControlStoreV1.recordName]
        if mappingBytes != nil {
            try requireLeafPolicy(
                AppLockNotificationControlStoreV1.mappingName,
                kind: .journal)
        }
        if controlBytes != nil {
            try requireLeafPolicy(
                AppLockNotificationControlStoreV1.recordName,
                kind: .journal)
        }
        guard try checkedRead.cut() == cut else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let mapping: NotificationPrivateMappingV1? = try mappingBytes
            .map { try decodeCanonical(
                NotificationPrivateMappingV1.self, bytes: $0) }
        try mapping?.validate()
        guard mapping?.entries.allSatisfy({ $0.admissionID == nil })
                ?? true else {
            throw AppAccessContractFailureV1
                .notificationReconciliationRequired
        }
        let control: AppLockNotificationControlV1? = try controlBytes
            .map { try decodeCanonicalControl($0) }
        let owned = Set((mapping?.ownedRequestIDs ?? []) +
            (control?.journal.projections.map(\.requestID) ?? []))
        if let bytes = cut.leafBytes[
            EraseSchema2ColdNotificationSourceV1.ownedIDsName] {
            guard cut.leafBytes[
                EraseSchema2ColdNotificationSourceV1
                    .ownedIDsTemporaryName] == nil else {
                throw AppAccessContractFailureV1
                    .notificationReconciliationRequired
            }
            try requireLeafPolicy(
                EraseSchema2ColdNotificationSourceV1.ownedIDsName,
                kind: .journal)
            let current = try decodeCanonical(
                NotificationEraseOwnedIDsProvenanceV1.self,
                bytes: bytes)
            try current.validate()
            var completedDrain: NotificationEraseDrainRecordV1?
            if let drainBytes = cut.leafBytes[
                EraseSchema2ColdNotificationSourceV1.drainName] {
                let revocation = NotificationEraseRevocationV1(
                    schemaVersion: 1, operationID: operationID,
                    rootIdentity: rootIdentityValue)
                guard cut.leafBytes[
                    AppLockNotificationControlStoreV1.eraseName]
                    == (try CompatibilityCanonicalV1.encode(revocation))
                    else {
                    throw AppAccessContractFailureV1.effectMismatch
                }
                try requireLeafPolicy(
                    EraseSchema2ColdNotificationSourceV1.drainName,
                    kind: .journal)
                let parsed = try decodeCanonical(
                    NotificationEraseDrainRecordV1.self,
                    bytes: drainBytes)
                try parsed.validate(revocation: revocation)
                completedDrain = parsed
            }
            let mappingSHA = try mappingBytes.map {
                try CompatibilityCanonicalV1.sha256($0)
            }
            let controlSHA = try controlBytes.map {
                try CompatibilityCanonicalV1.sha256($0)
            }
            guard current.operationID == operationID,
                  current.rootIdentity == rootIdentityValue,
                  (completedDrain != nil ||
                    ((mappingBytes != nil)
                        == (current.mappingSHA256 != nil)
                     && (controlBytes != nil)
                        == (current.controlSHA256 != nil))),
                  (mappingBytes == nil ||
                    current.mappingSHA256 == mappingSHA),
                  (mappingBytes == nil || current.mappingFact ==
                    cut.leafFacts[
                        AppLockNotificationControlStoreV1.mappingName]
                        .map(NotificationEraseOwnedLeafFactV1.init)),
                  (controlBytes == nil ||
                    current.controlSHA256 == controlSHA),
                  (controlBytes == nil || current.controlFact ==
                    cut.leafFacts[
                        AppLockNotificationControlStoreV1.recordName]
                        .map(NotificationEraseOwnedLeafFactV1.init)),
                  (completedDrain == nil
                    ? owned == Set(current.ownedRequestIDs)
                    : completedDrain?.ownedRequestIDs
                        == current.ownedRequestIDs),
                  try checkedRead.cut() == cut else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            if let prefix = cut.leafBytes[markerTemporary] {
                let revocation = NotificationEraseRevocationV1(
                    schemaVersion: 1, operationID: operationID,
                    rootIdentity: rootIdentityValue)
                let expected = try CompatibilityCanonicalV1
                    .encode(revocation)
                guard prefix.count <= expected.count,
                      expected.starts(with: prefix) else {
                    throw AppAccessContractFailureV1.effectMismatch
                }
            }
            if let prefix = cut.leafBytes[drainTemporary] {
                let revocation = NotificationEraseRevocationV1(
                    schemaVersion: 1, operationID: operationID,
                    rootIdentity: rootIdentityValue)
                let expected = try CompatibilityCanonicalV1.encode(
                    NotificationEraseDrainRecordV1(
                        revocation: revocation,
                        ownedRequestIDs: Set(current.ownedRequestIDs)))
                guard prefix.count <= expected.count,
                      expected.starts(with: prefix) else {
                    throw AppAccessContractFailureV1.effectMismatch
                }
            }
            guard try checkedRead.cut() == cut else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            reservedProvenance = current
            return current
        }
        // A first-captured marker without durable ID provenance may be an
        // older partial cleanup. One surviving predecessor proves only a
        // subset of the IDs that could have been removed with the other.
        guard !(source.names.contains(
                AppLockNotificationControlStoreV1.eraseName)
            && (mappingBytes == nil || controlBytes == nil)) else {
            throw AppAccessContractFailureV1
                .notificationReconciliationRequired
        }
        let provenance = try NotificationEraseOwnedIDsProvenanceV1(
            operationID: operationID,
            rootIdentity: rootIdentityValue,
            mappingBytes: mappingBytes,
            mappingFact: cut.leafFacts[
                AppLockNotificationControlStoreV1.mappingName],
            controlBytes: controlBytes,
            controlFact: cut.leafFacts[
                AppLockNotificationControlStoreV1.recordName],
            ownedRequestIDs: owned)
        try publishCanonical(
            try CompatibilityCanonicalV1.encode(provenance),
            name: EraseSchema2ColdNotificationSourceV1.ownedIDsName,
            temporary:
                EraseSchema2ColdNotificationSourceV1
                    .ownedIDsTemporaryName,
            stage: .publishOwnedIDs)
        try requireSchema2ColdOwnedIDs(provenance)
        reservedProvenance = provenance
        return provenance
    }

    func requireSchema2ColdOwnedIDs(
        _ provenance: NotificationEraseOwnedIDsProvenanceV1
    ) throws {
        try provenance.validate()
        try ensureRoot()
        try requireLeafPolicy(
            EraseSchema2ColdNotificationSourceV1.ownedIDsName,
            kind: .journal)
        let cut = try checkedRead.cut()
        guard provenance.operationID == source.eraseID,
              provenance.rootIdentity == rootIdentityValue,
              cut.leafBytes[
                EraseSchema2ColdNotificationSourceV1
                    .ownedIDsTemporaryName] == nil,
              cut.leafBytes[
                EraseSchema2ColdNotificationSourceV1.ownedIDsName]
                == (try CompatibilityCanonicalV1.encode(provenance)) else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        if cut.leafBytes[
                EraseSchema2ColdNotificationSourceV1.drainName]
                == nil {
            guard (cut.leafBytes[
                    AppLockNotificationControlStoreV1.mappingName] != nil)
                    == (provenance.mappingFact != nil),
                  (cut.leafBytes[
                    AppLockNotificationControlStoreV1.recordName] != nil)
                    == (provenance.controlFact != nil) else {
                throw AppAccessContractFailureV1.effectMismatch
            }
        } else {
            let revocation = NotificationEraseRevocationV1(
                schemaVersion: 1, operationID: source.eraseID,
                rootIdentity: rootIdentityValue)
            guard try loadSchema2ColdDrainRecord(
                    revocation: revocation)?.ownedRequestIDs
                    == provenance.ownedRequestIDs else {
                throw AppAccessContractFailureV1.effectMismatch
            }
        }
        if let mappingBytes = cut.leafBytes[
            AppLockNotificationControlStoreV1.mappingName] {
            guard provenance.mappingSHA256 ==
                    (try CompatibilityCanonicalV1.sha256(mappingBytes)),
                  provenance.mappingFact == cut.leafFacts[
                    AppLockNotificationControlStoreV1.mappingName]
                    .map(NotificationEraseOwnedLeafFactV1.init)
                else {
                throw AppAccessContractFailureV1.effectMismatch
            }
        }
        if let controlBytes = cut.leafBytes[
            AppLockNotificationControlStoreV1.recordName] {
            guard provenance.controlSHA256 ==
                    (try CompatibilityCanonicalV1.sha256(controlBytes)),
                  provenance.controlFact == cut.leafFacts[
                    AppLockNotificationControlStoreV1.recordName]
                    .map(NotificationEraseOwnedLeafFactV1.init)
                else {
                throw AppAccessContractFailureV1.effectMismatch
            }
        }
    }

    func publishSchema2ColdDrainRecord(
        _ record: NotificationEraseDrainRecordV1,
        revocation: NotificationEraseRevocationV1
    ) throws {
        try record.validate(revocation: revocation)
        try requireSchema2ColdRevocation(revocation)
        try requireSchema2ColdOSAbsence(
            stage: .publishDrainReceipt)
        if let existing = try loadSchema2ColdDrainRecord(
            revocation: revocation) {
            guard existing == record else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            return
        }
        try publishCanonical(
            try CompatibilityCanonicalV1.encode(record),
            name: EraseSchema2ColdNotificationSourceV1.drainName,
            temporary:
                EraseSchema2ColdNotificationSourceV1.drainTemporaryName,
            stage: .publishDrainReceipt)
        try requireSchema2ColdDrainRecord(
            record, revocation: revocation)
    }

    /// Only an exact reserved temporary can be adopted. Unknown bytes,
    /// prefixes, type, link or policy remain retained and refuse this cut.
    private func publishCanonical(
        _ canonical: Data, name: String, temporary: String,
        stage: EraseSchema2ColdNotificationMutationStageV1
    ) throws {
        try ensureRoot()
        guard !canonical.isEmpty,
              canonical.count <= AppLockNotificationControlStoreV1
                .maximumRecordBytes else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let token = try source.beginMutation(stage: stage)
        let receipt = try source.withHeldRootForMutation(
            token: token) { rootFD, rootURL in
            let before = try checkedRead.cutBorrowed(
                rootFD: rootFD, rootURL: rootURL)
            var settledCapturedTemporaryFact:
                EraseColdControlLeafFactV1?
            guard before.leafBytes[name] == nil,
                  before.leafBytes[temporary].map({
                    $0.count <= canonical.count &&
                        canonical.starts(with: $0)
                  })
                    ?? true else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            if let prefix = before.leafBytes[temporary],
               prefix != canonical {
                guard let firstFact = before.leafFacts[temporary],
                      prefix.count < canonical.count else {
                    throw AppAccessContractFailureV1.effectMismatch
                }
                let policyCut = try requestCheckedTemporaryPolicy(
                    temporary, rootFD: rootFD, rootURL: rootURL,
                    before: before)
                var linked = stat()
                guard Darwin.fstatat(rootFD, temporary,
                        &linked, AT_SYMLINK_NOFOLLOW) == 0,
                      EraseColdControlLeafFactV1(linked)
                        == policyCut.leafFacts[temporary],
                      try checkedRead.cutBorrowed(
                        rootFD: rootFD, rootURL: rootURL) == policyCut,
                      Darwin.unlinkat(rootFD, temporary, 0) == 0,
                      Darwin.fsync(rootFD) == 0 else {
                    throw AppAccessContractFailureV1
                        .configurationUnknown
                }
                let removed = try checkedRead.cutBorrowed(
                    rootFD: rootFD, rootURL: rootURL)
                guard removed.leafBytes[temporary] == nil,
                      sameRootIdentity(before, removed),
                      unchangedLeaves(before, removed,
                        changing: [temporary]),
                      Set(removed.names) == Set(before.names)
                        .subtracting([temporary]) else {
                    throw AppAccessContractFailureV1
                        .configurationUnknown
                }
                settledCapturedTemporaryFact = firstFact
            }
            if before.leafBytes[temporary] == nil ||
                before.leafBytes[temporary] != canonical {
                try mutationIO.withOpen(parent: rootFD,
                    name: temporary,
                    flags: O_WRONLY | O_CREAT | O_EXCL,
                    mode: 0o600) { fd in
                    var offset = 0
                    #if DEBUG
                    if let temporaryFaultForTesting {
                        // The fault observes an actual durable O_EXCL cut.
                        // The operation retains the stage and every checked
                        // descriptor when the callback throws.
                        guard Darwin.fsync(rootFD) == 0 else {
                            throw AppAccessContractFailureV1
                                .configurationUnknown
                        }
                        try temporaryFaultForTesting(stage,
                            .afterCreateBeforePolicy)
                        if canonical.count > 1 {
                            while true {
                                let count = canonical.withUnsafeBytes {
                                    raw -> Int in
                                    guard let base = raw.baseAddress else {
                                        return 0
                                    }
                                    return Darwin.write(fd, base, 1)
                                }
                                if count < 0 && errno == EINTR { continue }
                                guard count == 1 else {
                                    throw AppAccessContractFailureV1
                                        .configurationUnknown
                                }
                                break
                            }
                            offset = 1
                            guard Darwin.fsync(fd) == 0,
                                  Darwin.fsync(rootFD) == 0 else {
                                throw AppAccessContractFailureV1
                                    .configurationUnknown
                            }
                            try temporaryFaultForTesting(stage,
                                .afterStrictPrefixBeforePolicy)
                        }
                    }
                    #endif
                    while offset < canonical.count {
                        let count = canonical.withUnsafeBytes {
                            raw -> Int in
                            guard let base = raw.baseAddress else {
                                return 0
                            }
                            return Darwin.write(fd,
                                base.advanced(by: offset),
                                raw.count - offset)
                        }
                        if count < 0 && errno == EINTR { continue }
                        guard count > 0 else {
                            throw AppAccessContractFailureV1
                                .configurationUnknown
                        }
                        offset += count
                    }
                    guard Darwin.fsync(fd) == 0 else {
                        throw AppAccessContractFailureV1
                            .configurationUnknown
                    }
                }
            }
            let written = try checkedRead.cutBorrowed(
                rootFD: rootFD, rootURL: rootURL)
            guard written.leafBytes[temporary] == canonical,
                  written.leafBytes[name] == nil,
                  unchangedLeaves(before, written,
                    changing: [temporary]),
                  sameRootIdentity(before, written),
                  written.leafFacts[temporary] != nil else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            let policyWritten = try requestCheckedTemporaryPolicy(
                temporary, rootFD: rootFD, rootURL: rootURL,
                before: written)
            guard let protectedTemporaryFact =
                policyWritten.leafFacts[temporary] else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            try mutationIO.withOpen(parent: rootFD,
                name: temporary, flags: O_RDWR) { fd in
                var held = stat(), named = stat()
                guard Darwin.fstat(fd, &held) == 0,
                      Darwin.fstatat(rootFD, temporary,
                        &named, AT_SYMLINK_NOFOLLOW) == 0,
                      EraseColdControlLeafFactV1(held)
                        == protectedTemporaryFact,
                      EraseColdControlLeafFactV1(named)
                        == protectedTemporaryFact,
                      Darwin.fsync(fd) == 0 else {
                    throw AppAccessContractFailureV1
                        .configurationUnknown
                }
            }
            guard Darwin.fsync(rootFD) == 0,
                  try checkedRead.cutBorrowed(
                    rootFD: rootFD, rootURL: rootURL) == policyWritten,
                  Darwin.renameatx_np(rootFD, temporary,
                    rootFD, name, UInt32(RENAME_EXCL)) == 0,
                  Darwin.fsync(rootFD) == 0 else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            let after = try checkedRead.cutBorrowed(
                rootFD: rootFD, rootURL: rootURL)
            guard after.leafBytes[name] == canonical,
                  after.leafBytes[temporary] == nil,
                  sameRootIdentity(before, after),
                  unchangedLeaves(before, after,
                    changing: [name, temporary]) else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            let publishedURL = rootURL.appendingPathComponent(name)
            let disposition = try ProtectedFilePolicyV1
                .verifyEraseColdTemporalPolicyWithCheckedRequest(
                    .journal, at: publishedURL,
                    retainUncertainDescriptor: { value in
                        self.uncertainPolicyDescriptors.append(value)
                    }, unchangedWitness: {
                        let current = try self.checkedRead.cutBorrowed(
                            rootFD: rootFD, rootURL: rootURL)
                        guard current == after else {
                            throw AppAccessContractFailureV1
                                .configurationUnknown
                        }
                        return current.leafFacts[name]
                    })
            guard try checkedRead.cutBorrowed(
                    rootFD: rootFD, rootURL: rootURL) == after else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            try requireCheckedSettled()
            return EraseSchema2ColdNotificationMutationReceiptV1(
                token: token, before: before, after: after,
                temporaryFact: protectedTemporaryFact,
                settledCapturedTemporaryFact:
                    settledCapturedTemporaryFact,
                policyDisposition: disposition)
        }
        try source.finishMutation(token: token, receipt: receipt)
        try requireCheckedSettled()
    }

    private func sameRootIdentity(
        _ before: EraseSchema2ColdNotificationCheckedCutV1,
        _ after: EraseSchema2ColdNotificationCheckedCutV1
    ) -> Bool {
        guard let lhs = before.rootFact,
              let rhs = after.rootFact else { return false }
        guard lhs.device == rhs.device, lhs.inode == rhs.inode,
              lhs.mode == rhs.mode,
              Set(before.names).count == before.names.count,
              Set(after.names).count == after.names.count else {
            return false
        }
        // The closed child vocabulary contains regular files only. Some
        // filesystems keep a directory at two links for file entry changes;
        // APFS can count each entry. Bind both cuts to the same one of those
        // laws and the exact observed name-count transition. No observed
        // link count is adopted as a fresh baseline.
        let stableDirectoryLinks = lhs.links == 2 && rhs.links == 2
        guard before.names.count <= Int.max - 2,
              after.names.count <= Int.max - 2 else { return false }
        let entryCountedLinks =
            UInt64(lhs.links) == UInt64(2 + before.names.count)
            && UInt64(rhs.links) == UInt64(2 + after.names.count)
        return stableDirectoryLinks || entryCountedLinks
    }

    /// A reserved temp may be captured after its O_EXCL create or prefix
    /// write but before the writer's policy request. That first observation
    /// is opaque data. Only this retained mutation may complete its policy,
    /// and the request may project the temp's ctime without replacing its
    /// inode, bytes, name, or any sibling fact.
    private func requestCheckedTemporaryPolicy(
        _ temporary: String, rootFD: Int32, rootURL: URL,
        before: EraseSchema2ColdNotificationCheckedCutV1
    ) throws -> EraseSchema2ColdNotificationCheckedCutV1 {
        guard let firstFact = before.leafFacts[temporary],
              let firstBytes = before.leafBytes[temporary],
              [AppLockNotificationControlStoreV1.pendingName,
               AppLockNotificationControlStoreV1.mappingPendingName,
               AppLockNotificationControlStoreV1.erasePendingName,
               EraseSchema2ColdNotificationSourceV1
                .ownedIDsTemporaryName,
               EraseSchema2ColdNotificationSourceV1
                .drainTemporaryName].contains(temporary) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let url = rootURL.appendingPathComponent(temporary)
        let initialPolicy: TemporalPolicyObservationV1?
        do {
            initialPolicy = try ProtectedFilePolicyV1
                .observeTemporalPolicyWithCheckedClose(
                    .journalTemporary, at: url,
                    retainUncertainDescriptor: { value in
                        self.uncertainPolicyDescriptors.append(value)
                    })
        } catch ProtectedFilePolicyError.resourceValueMismatch {
            initialPolicy = nil
        }
        guard try checkedRead.cutBorrowed(rootFD: rootFD,
            rootURL: rootURL) == before else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        if initialPolicy == nil {
            var firstEffectStarted = false
            _ = try ProtectedFilePolicyV1
                .applyAndVerifyEraseColdPrivateWithCheckedClose(
                    .journalTemporary, at: url,
                    retainUncertainDescriptor: { value in
                        self.uncertainPolicyDescriptors.append(value)
                    }, authorityCheck: {
                        guard try self.source.requireCurrentRootIdentity()
                            == self.rootIdentityValue else {
                            throw AppAccessContractFailureV1
                                .configurationUnknown
                        }
                        let current = try self.checkedRead.cutBorrowed(
                            rootFD: rootFD, rootURL: rootURL)
                        guard current.rootFact == before.rootFact,
                              current.names == before.names,
                              self.unchangedLeaves(before, current,
                                changing: [temporary]),
                              current.leafBytes[temporary] == firstBytes,
                              let fact = current.leafFacts[temporary],
                              self.sameLeafExceptChangedTime(firstFact,
                                fact),
                              firstEffectStarted || current == before else {
                            throw AppAccessContractFailureV1
                                .configurationUnknown
                        }
                    }, beforeFirstEffect: {
                        guard try self.source.requireCurrentRootIdentity()
                            == self.rootIdentityValue,
                              try self.checkedRead.cutBorrowed(
                            rootFD: rootFD, rootURL: rootURL) == before else {
                            throw AppAccessContractFailureV1
                                .configurationUnknown
                        }
                        firstEffectStarted = true
                    })
        } else {
            _ = try ProtectedFilePolicyV1
                .verifyEraseColdTemporalPolicyWithCheckedRequest(
                    .journalTemporary, at: url,
                    retainUncertainDescriptor: { value in
                        self.uncertainPolicyDescriptors.append(value)
                    }, unchangedWitness: {
                        let current = try self.checkedRead.cutBorrowed(
                            rootFD: rootFD, rootURL: rootURL)
                        guard current == before else {
                            throw AppAccessContractFailureV1
                                .configurationUnknown
                        }
                        return current.leafFacts[temporary]
                    })
        }
        let after = try checkedRead.cutBorrowed(rootFD: rootFD,
            rootURL: rootURL)
        guard after.rootFact == before.rootFact,
              after.names == before.names,
              unchangedLeaves(before, after, changing: [temporary]),
              after.leafBytes[temporary] == firstBytes,
              let afterFact = after.leafFacts[temporary],
              sameLeafExceptChangedTime(firstFact, afterFact) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        return after
    }

    private func sameLeafExceptChangedTime(
        _ first: EraseColdControlLeafFactV1,
        _ next: EraseColdControlLeafFactV1
    ) -> Bool {
        first.device == next.device && first.inode == next.inode
            && first.mode == next.mode && first.links == next.links
            && first.size == next.size
            && first.modifiedSeconds == next.modifiedSeconds
            && first.modifiedNanoseconds == next.modifiedNanoseconds
    }

    private func unchangedLeaves(
        _ before: EraseSchema2ColdNotificationCheckedCutV1,
        _ after: EraseSchema2ColdNotificationCheckedCutV1,
        changing: Set<String>
    ) -> Bool {
        for name in Set(before.names).union(after.names)
            where !changing.contains(name) {
            guard before.leafBytes[name] == after.leafBytes[name],
                  before.leafFacts[name] == after.leafFacts[name] else {
                return false
            }
        }
        return true
    }

    func removeNotificationRecordsAfterErase(
        _ revocation: NotificationEraseRevocationV1
    ) throws {
        try requireSchema2ColdRevocation(revocation)
        guard let record = try loadSchema2ColdDrainRecord(
                revocation: revocation),
              let osAbsence else {
            throw AppAccessContractFailureV1
                .notificationReconciliationRequired
        }
        try osAbsence.requireBound(to: self,
            operationID: source.eraseID, drainPublished: true)
        try record.validate(revocation: revocation)
        let first = try checkedRead.cut()
        for pending in [AppLockNotificationControlStoreV1.pendingName,
            AppLockNotificationControlStoreV1.mappingPendingName,
            AppLockNotificationControlStoreV1.erasePendingName,
            EraseSchema2ColdNotificationSourceV1
                .ownedIDsTemporaryName,
            EraseSchema2ColdNotificationSourceV1.drainTemporaryName] {
            guard first.leafBytes[pending] == nil else {
                throw AppAccessContractFailureV1
                    .notificationReconciliationRequired
            }
        }
        if first.leafBytes[
            AppLockNotificationControlStoreV1.mappingName] != nil {
            try removeCanonical(
                AppLockNotificationControlStoreV1.mappingName,
                stage: .removeMapping)
        }
        if (try checkedRead.cut()).leafBytes[
            AppLockNotificationControlStoreV1.recordName] != nil {
            try removeCanonical(
                AppLockNotificationControlStoreV1.recordName,
                stage: .removeControl)
        }
        try requireNotificationEraseRevocation(revocation)
    }

    private func removeCanonical(
        _ name: String,
        stage: EraseSchema2ColdNotificationMutationStageV1
    ) throws {
        try ensureRoot()
        try requireSchema2ColdOSAbsence(stage: stage)
        let token = try source.beginMutation(stage: stage)
        let receipt = try source.withHeldRootForMutation(
            token: token) { rootFD, rootURL in
            let before = try checkedRead.cutBorrowed(
                rootFD: rootFD, rootURL: rootURL)
            guard let expected = before.leafFacts[name],
                  before.leafBytes[name] != nil else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            var linked = stat()
            guard Darwin.fstatat(rootFD, name,
                    &linked, AT_SYMLINK_NOFOLLOW) == 0,
                  EraseColdControlLeafFactV1(linked) == expected,
                  try checkedRead.cutBorrowed(
                    rootFD: rootFD, rootURL: rootURL) == before,
                  Darwin.unlinkat(rootFD, name, 0) == 0,
                  Darwin.fsync(rootFD) == 0 else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            let after = try checkedRead.cutBorrowed(
                rootFD: rootFD, rootURL: rootURL)
            guard after.leafBytes[name] == nil,
                  sameRootIdentity(before, after),
                  unchangedLeaves(before, after,
                    changing: [name]),
                  Set(after.names) == Set(before.names)
                    .subtracting([name]) else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            try requireCheckedSettled()
            return EraseSchema2ColdNotificationMutationReceiptV1(
                token: token, before: before, after: after,
                temporaryFact: nil, policyDisposition: nil)
        }
        try source.finishMutation(token: token, receipt: receipt)
        try requireCheckedSettled()
    }
}

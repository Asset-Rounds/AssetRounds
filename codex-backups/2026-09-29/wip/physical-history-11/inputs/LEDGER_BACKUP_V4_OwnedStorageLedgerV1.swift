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

/// Fixed DEBUG classification only; absence never authorizes an effect.
enum OriginalEraseNotificationFirstPresenceV1: String {
    case absent, present, unavailable
}

#if DEBUG
private func reportOriginalNotificationRootDiagnostic(_ stage: String,
    syscallErrno: Int32? = nil) {
    if let syscallErrno {
        print("V23_C05_ORIGINAL_NOTIFICATION_ROOT_DIAG_V1 stage=\(stage) errno=\(syscallErrno)")
    } else {
        print("V23_C05_ORIGINAL_NOTIFICATION_ROOT_DIAG_V1 stage=\(stage)")
    }
}
#endif

private final class PinnedScratchRootV1: @unchecked Sendable {
    private let operationsURL: URL
    private(set) var operationsDescriptor: Int32
    private(set) var rootDescriptor: Int32
    private var rootCloseAttempted = false
    private var operationsCloseAttempted = false
    private let originalCleanupBorrowCheck: (() throws -> Void)?
    let operationsDevice: UInt64
    let operationsInode: UInt64
    let rootDevice: UInt64
    let rootInode: UInt64

    init(operationsURL: URL, rootName: String,
        originalEraseNotificationDiagnostic: Bool = false,
        retainedOriginalEraseIO: EraseAbortCheckedSnapshotIOV1? = nil) throws {
        self.operationsURL = operationsURL.standardizedFileURL
        originalCleanupBorrowCheck = nil
        operationsDescriptor = Darwin.open(
            operationsURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard operationsDescriptor >= 0 else {
#if DEBUG
            if originalEraseNotificationDiagnostic {
                reportOriginalNotificationRootDiagnostic("pinned.open-operations.failed",
                    syscallErrno: errno)
            }
#endif
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        var operations = stat()
        let operationsStatResult = Darwin.fstat(operationsDescriptor, &operations)
        guard operationsStatResult == 0,
              (operations.st_mode & S_IFMT) == S_IFDIR else {
#if DEBUG
            if originalEraseNotificationDiagnostic {
                if operationsStatResult != 0 {
                    reportOriginalNotificationRootDiagnostic("pinned.stat-operations.failed", syscallErrno: errno)
                } else {
                    reportOriginalNotificationRootDiagnostic("pinned.stat-operations.wrong-kind")
                }
            }
#endif
            let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(operationsDescriptor)
            if Darwin.close(operationsDescriptor) == 0 {
                ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
            } else {
                retainedOriginalEraseIO?.retainUncertainDescriptor(operationsDescriptor)
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
#if DEBUG
            if originalEraseNotificationDiagnostic {
                reportOriginalNotificationRootDiagnostic("pinned.open-root.failed",
                    syscallErrno: errno)
            }
#endif
            let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(operationsDescriptor)
            if Darwin.close(operationsDescriptor) == 0 {
                ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
            } else {
                retainedOriginalEraseIO?.retainUncertainDescriptor(operationsDescriptor)
            }
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        var root = stat()
        let rootStatResult = Darwin.fstat(rootDescriptor, &root)
        guard rootStatResult == 0,
              (root.st_mode & S_IFMT) == S_IFDIR,
              root.st_dev == operations.st_dev else {
#if DEBUG
            if originalEraseNotificationDiagnostic {
                if rootStatResult != 0 {
                    reportOriginalNotificationRootDiagnostic("pinned.stat-root.failed", syscallErrno: errno)
                } else if (root.st_mode & S_IFMT) != S_IFDIR {
                    reportOriginalNotificationRootDiagnostic("pinned.stat-root.wrong-kind")
                } else {
                    reportOriginalNotificationRootDiagnostic("pinned.stat-root.different-device")
                }
            }
#endif
            let rootAttempt = ScratchUncertainCloseQuarantineV1.shared.begin(rootDescriptor)
            if Darwin.close(rootDescriptor) == 0 {
                ScratchUncertainCloseQuarantineV1.shared.complete(rootAttempt)
            } else {
                retainedOriginalEraseIO?.retainUncertainDescriptor(rootDescriptor)
            }
            let operationsAttempt = ScratchUncertainCloseQuarantineV1.shared.begin(operationsDescriptor)
            if Darwin.close(operationsDescriptor) == 0 {
                ScratchUncertainCloseQuarantineV1.shared.complete(operationsAttempt)
            } else {
                retainedOriginalEraseIO?.retainUncertainDescriptor(operationsDescriptor)
            }
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        rootDevice = UInt64(root.st_dev)
        rootInode = UInt64(root.st_ino)
    }

    /// These descriptors belong to the retained live cleanup attempt. This
    /// pin cannot close them, including during initialization failure/deinit.
    init(originalCleanupOperationsURL: URL, operations: Int32, root: Int32,
        operationsInformation: stat, rootInformation: stat,
        requireBorrow: @escaping () throws -> Void) throws {
        try requireBorrow()
        operationsURL = originalCleanupOperationsURL.standardizedFileURL
        operationsDescriptor = operations; rootDescriptor = root
        operationsDevice = UInt64(operationsInformation.st_dev)
        operationsInode = UInt64(operationsInformation.st_ino)
        rootDevice = UInt64(rootInformation.st_dev); rootInode = UInt64(rootInformation.st_ino)
        originalCleanupBorrowCheck = requireBorrow
        rootCloseAttempted = true; operationsCloseAttempted = true
        try requireBorrow()
    }

    deinit {
        if originalCleanupBorrowCheck != nil { return }
        if rootDescriptor >= 0 && !rootCloseAttempted { _ = Darwin.close(rootDescriptor) }
        if operationsDescriptor >= 0 && !operationsCloseAttempted { _ = Darwin.close(operationsDescriptor) }
    }

    func closeCheckedForExclusiveOriginalEraseRead(
        verifyBeforeClose: Bool = true
    ) throws {
        guard originalCleanupBorrowCheck == nil else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        if verifyBeforeClose { try verify(rootName: "ScratchDataV1") }
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

    func verify(rootName: String) throws {
        try originalCleanupBorrowCheck?()
        func observed(_ body: () -> Int32) throws -> Int32 {
            guard let check = originalCleanupBorrowCheck else { return body() }
            let incomingErrno = errno
            try check(); errno = incomingErrno
            let result = body(); let actualErrno = errno
            try check(); errno = actualErrno
            return result
        }
        var operations = stat()
        var linkedOperations = stat()
        var root = stat()
        var child = stat()
        guard try observed({ Darwin.fstat(operationsDescriptor, &operations) }) == 0,
              UInt64(operations.st_dev) == operationsDevice,
              UInt64(operations.st_ino) == operationsInode,
              try observed({ Darwin.lstat(operationsURL.path, &linkedOperations) }) == 0,
              (linkedOperations.st_mode & S_IFMT) == S_IFDIR,
              UInt64(linkedOperations.st_dev) == operationsDevice,
              UInt64(linkedOperations.st_ino) == operationsInode,
              try observed({ Darwin.fstat(rootDescriptor, &root) }) == 0,
              UInt64(root.st_dev) == rootDevice,
              UInt64(root.st_ino) == rootInode,
              try observed({ Darwin.fstatat(
                operationsDescriptor,
                rootName,
                &child,
                AT_SYMLINK_NOFOLLOW
              ) }) == 0,
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
         mustExistForOriginalErase: Bool = false,
         originalFirstNotificationPresence:
            OriginalEraseNotificationFirstPresenceV1? = nil,
         retainedOriginalEraseIO: EraseAbortCheckedSnapshotIOV1? = nil) throws {
        guard retainedOriginalEraseIO == nil || mustExistForOriginalErase else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        guard applicationSupportURL.isFileURL else { throw AppAccessContractFailureV1.configurationUnknown }
        self.preferences = preferences
        supportURL = applicationSupportURL.standardizedFileURL
        self.failurePoint = failurePoint
        let policyIO = mustExistForOriginalErase
            ? (retainedOriginalEraseIO ?? EraseAbortCheckedSnapshotIOV1()) : nil
        originalErasePolicyIO = policyIO
#if DEBUG
        if mustExistForOriginalErase {
            let presence = originalFirstNotificationPresence ?? .unavailable
            print("V23_C05_ORIGINAL_NOTIFICATION_ROOT_DIAG_V1 firstP=\(presence.rawValue)")
        }
#endif
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

    /// A no-repair constructor must pin the exact physically settled root
    /// before an original publisher can use it. No receipt authorizes mkdir.
    @MainActor
    func requireOriginalEraseRootPolicyBinding(
        _ receipt: OriginalEraseNotificationRootPolicyReceiptV1,
        operation: EraseRouterOperationV1, store: EraseIntentStore,
        registry: GenerationLeaseRegistryV1,
        exclusion: StoreTemporalNormalizationExclusionV1,
        activity: GenerationTemporalActivityHandleV1
    ) throws {
        func fullFact(_ value: stat) -> String {
            "\(value.st_dev)|\(value.st_ino)|\(value.st_mode)|\(value.st_uid)|\(value.st_gid)|\(value.st_nlink)|\(value.st_size)|\(value.st_mtimespec.tv_sec)|\(value.st_mtimespec.tv_nsec)|\(value.st_ctimespec.tv_sec)|\(value.st_ctimespec.tv_nsec)"
        }
        try receipt.requireBound(operation: operation, store: store,
            registry: registry, exclusion: exclusion, activity: activity)
        guard let io = originalErasePolicyIO,
              !originalEraseSupportCloseAttempted,
              !originalEraseCheckedCloseComplete else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        try io.requireSettled()
        try verifyRoot()
        let url = supportURL
            .appendingPathComponent(OwnedStorageRootKindV1.operations.rawValue)
            .appendingPathComponent(Self.rootName)
        let first = try Self.originalEraseHeldNamedRootFact(authority: authority, url: url)
        guard fullFact(first) == receipt.projectedRootFact,
              try io.postRetiredTree(parent: authority.operationsDescriptor,
                name: Self.rootName) == receipt.projectedTreeDigest else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        let final = try Self.originalEraseHeldNamedRootFact(authority: authority, url: url)
        guard fullFact(final) == receipt.projectedRootFact else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        try verifyRoot()
        try io.requireSettled()
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
        let sourceRootFields = policyReceipt.projectedRootFact.split(
            separator: "|", omittingEmptySubsequences: false)
        guard sourceRootFields.count == 11,
              let sourceRootLinks = UInt64(sourceRootFields[5]) else {
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
            // This invocation adds one O_EXCL pending name, then renames
            // that same inode to the canonical name. Some filesystems count
            // the regular child in directory nlink; retain the complete actual
            // root fact while projecting only this proved single-name edge.
            let ownedMarkerNames = Set(names).subtracting(firstNames)
            guard Set(firstNames).isSubset(of: Set(names)),
                  ownedMarkerNames.count <= 1,
                  ownedMarkerNames.isSubset(of:
                    Set([Self.eraseName, Self.erasePendingName])) else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            let currentRootLinks = UInt64(held.st_nlink)
            let normalizeAddedMarker: UInt64?
            if currentRootLinks == sourceRootLinks {
                normalizeAddedMarker = nil
            } else {
                guard ownedMarkerNames.count == 1,
                      sourceRootLinks < UInt64.max,
                      currentRootLinks == sourceRootLinks + 1 else {
                    throw AppAccessContractFailureV1.notificationReconciliationRequired
                }
                normalizeAddedMarker = sourceRootLinks
            }
            guard try io.postRetiredTree(parent: operations,
                    name: Self.rootName,
                    excluding: ownedMarkerNames,
                    ignoringDirectoryMetadata: Set([""]),
                    normalizingSingleTargetManifestRootLinksFrom:
                        normalizeAddedMarker)
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
        var diagnosticStage = "open-root.support-open"
        do {
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
        diagnosticStage = "open-root.support-stat-and-name"
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
        diagnosticStage = "open-root.operations-open"
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
        diagnosticStage = "open-root.operations-stat"
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
        diagnosticStage = "open-root.pinned-root"
        let pinned = try PinnedScratchRootV1(operationsURL: operationsURL,
            rootName: rootName,
            originalEraseNotificationDiagnostic: mustExistForOriginalErase,
            retainedOriginalEraseIO: originalErasePolicyIO)
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
        diagnosticStage = "open-root.support-and-root-verify"
        try check()
        let root = operationsURL.appendingPathComponent(rootName)
        if mustExistForOriginalErase, let originalErasePolicyIO {
            let firstRoot = try originalEraseHeldNamedRootFact(
                authority: pinned, url: root)
        diagnosticStage = "open-root.policy-observation"
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
        diagnosticStage = "open-root.policy-postimage"
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
        diagnosticStage = "open-root.checked-operations-close"
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
        diagnosticStage = "open-root.checked-io-settled"
        try originalErasePolicyIO?.requireSettled()
        keepPinned = true
        keep = true
        return (support, UInt64(information.st_dev), UInt64(information.st_ino), pinned)
        } catch {
#if DEBUG
            if mustExistForOriginalErase {
                reportOriginalNotificationRootDiagnostic(diagnosticStage)
            }
#endif
            throw error
        }
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
/// The only Notification anchor admitted when immutable first P was absent.
/// Its issuer below owns the actual checked mkdir/policy/sync/close readback;
/// the same retained first observer validates the exact namespace projection.
@MainActor final class OriginalEraseNotificationRootCreationReceiptV1 {
    let before: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot
    let after: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot
    let outsideDigest: String
    let checkedSettled: Bool
    private weak var operation: EraseRouterOperationV1?
    private weak var store: EraseIntentStore?
    private weak var registry: GenerationLeaseRegistryV1?
    private weak var exclusion: StoreTemporalNormalizationExclusionV1?
    private weak var activity: GenerationTemporalActivityHandleV1?
    private weak var observer: EraseSchema2ColdAuxiliaryFirstObserverV1?

    fileprivate init(operation: EraseRouterOperationV1,
        store: EraseIntentStore, registry: GenerationLeaseRegistryV1,
        exclusion: StoreTemporalNormalizationExclusionV1,
        activity: GenerationTemporalActivityHandleV1,
        observer: EraseSchema2ColdAuxiliaryFirstObserverV1,
        before: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot,
        after: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot,
        outsideDigest: String) {
        self.operation = operation
        self.store = store
        self.registry = registry
        self.exclusion = exclusion
        self.activity = activity
        self.observer = observer
        self.before = before
        self.after = after
        self.outsideDigest = outsideDigest
        checkedSettled = true
    }

    func requireBound(operation: EraseRouterOperationV1,
        store: EraseIntentStore, registry: GenerationLeaseRegistryV1,
        exclusion: StoreTemporalNormalizationExclusionV1,
        activity: GenerationTemporalActivityHandleV1) throws {
        guard self.operation === operation, self.store === store,
              self.registry === registry, self.exclusion === exclusion,
              self.activity === activity, checkedSettled,
              let observer else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        try requireObserver(observer)
    }

    func requireObserver(_ observer: EraseSchema2ColdAuxiliaryFirstObserverV1) throws {
        guard self.observer === observer, operation != nil, store != nil,
              registry != nil, exclusion != nil, activity != nil, checkedSettled else {
            throw AppAccessContractFailureV1.notificationReconciliationRequired
        }
        try observer.requireOriginalNotificationCreationAdmission(before: before)
    }
}

@MainActor final class OriginalEraseNotificationRootPolicyReceiptV1 {
    let firstRootFact: String
    let firstTreeDigest: String
    let projectedRootFact: String
    let projectedTreeDigest: String
    let disposition: ProtectedFileVerificationDispositionV1
    let didRequestCompleteProtection: Bool
    let checkedSettled: Bool
    let creationReceipt: OriginalEraseNotificationRootCreationReceiptV1?
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
        didRequestCompleteProtection: Bool,
        creationReceipt: OriginalEraseNotificationRootCreationReceiptV1? = nil) {
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
        self.creationReceipt = creationReceipt
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
        try creationReceipt?.requireBound(operation: operation, store: store,
            registry: registry, exclusion: exclusion, activity: activity)
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

struct OriginalEraseScratchCleanupImageV1: Equatable {
    struct Node: Equatable {
        let path: String // Relative to this root; empty only for the root node.
        let fullFact: String // Actual eleven-field held/named fact.
        let contentSHA256: String?
        let policy: TemporalPolicyObservationV1?
        // nil only for the exact active O_EXCL temporary prior to its actual
        // checked policy request; never for an existing or unassigned node.
    }
    struct Root: Equatable {
        let fullFact: String
        let digest: String
        let nodes: [Node] // Complete canonical path order, including root.
    }
    let operationsFullFact: String
    let operationsNames: [String]
    let scratch: Root?
    let ingress: Root?
}

@MainActor
final class OriginalEraseScratchCleanupPrimitiveIntentV1 {
    enum Root: String { case scratch = "ScratchDataV1", ingress = "ProtectedIngressReceiptsV1" }
    enum Kind {
        // All paths below are canonical Operations-relative paths. Only the
        // fixed cleanup engine creates an intent; caller DATA cannot mint it.
        case createTemporary(path: String, finalPath: String, bytes: Data,
            sha256: String, mode: mode_t, exclusiveFinalRename: Bool)
        case writeTemporary(path: String, offset: Int, requestedByteCount: Int)
        case requestPolicy(path: String, kind: OwnedFileKindV1)
        case linkPublication(temporaryPath: String, finalPath: String)
        case renamePublication(sourcePath: String, finalPath: String, exclusive: Bool)
        case renameLeaseDirectory(originalPath: String, tombstonePath: String)
        case removeLeaf(path: String)
        case removeDirectory(path: String)
        case synchronize(path: String)
        case lockOwnedDirectory(path: String)
        case closeOwnedResource(path: String, resourceID: UUID)
    }
    let requestID: UUID
    let attemptID: UUID
    let operationID: UUID
    let sequence: UInt64
    let before: OriginalEraseScratchCleanupImageV1
    let kind: Kind
    fileprivate init(attemptID: UUID, operationID: UUID, sequence: UInt64,
        before: OriginalEraseScratchCleanupImageV1, kind: Kind) {
        requestID = UUID(); self.attemptID = attemptID
        self.operationID = operationID; self.sequence = sequence
        self.before = before; self.kind = kind
    }
}

@MainActor
final class OriginalEraseScratchCleanupPrimitiveOutcomeV1 {
    let intent: OriginalEraseScratchCleanupPrimitiveIntentV1
    let result: Int64 // Actual syscall count/result or checked policy success0.
    let syscallErrno: Int32 // Saved immediately before any callback/close.
    fileprivate init(intent: OriginalEraseScratchCleanupPrimitiveIntentV1,
        result: Int64, syscallErrno: Int32) {
        self.intent = intent; self.result = result; self.syscallErrno = syscallErrno
    }
}


struct OriginalEraseScratchCleanupCanonicalSourceV1 {
    let path: String
    let bytes: Data
    let fullFact: String
    let sha256: String
}

struct OriginalEraseScratchCleanupDirectorySourceV1 {
    enum Metadata {
        case validatedLease(bytes: Data, fullFact: String, sha256: String)
        case ownedOrphan
    }
    let originalPath: String
    let originalFullFact: String
    let metadata: Metadata
}

/// Retained by the actual original operation before any open. Its public
/// surface exposes DATA and checked settlement only, never a Store or raw FD.
@MainActor
final class OriginalEraseScratchCleanupAttemptV1 {
    enum Lifetime { case active, closing, closed, uncertain }
    fileprivate enum ResourceState { case open, closeEntered, closed, uncertain }
    fileprivate enum ResourceRole {
        case cleanupPin
        case engineRead
        case publication(requestID: UUID)
        case catalog(OriginalEraseScratchCanonicalSourceCatalogSessionV1)
    }
    fileprivate final class Resource {
        let resourceID = UUID()
        let descriptor: Int32
        var path: String
        var state = ResourceState.open
        let role: ResourceRole
        var catalogSession: OriginalEraseScratchCanonicalSourceCatalogSessionV1? {
            if case .catalog(let session) = role { return session }; return nil
        }
        var close: () -> Int32
        init(descriptor: Int32, path: String,
            role: ResourceRole,
            close: @escaping () -> Int32) {
            self.descriptor = descriptor; self.path = path; self.close = close
            self.role = role
        }
    }
    let attemptID = UUID()
    let operationID: UUID
    let initialImage: OriginalEraseScratchCleanupImageV1
    fileprivate let permit: OriginalEraseScratchCleanupEffectPermitV1
    fileprivate let retainedIO: EraseAbortCheckedSnapshotIOV1
    fileprivate private(set) var lifetime = Lifetime.active
    fileprivate private(set) var image: OriginalEraseScratchCleanupImageV1
    fileprivate var store: ScratchDataLeaseStoreV1?
    fileprivate var resources: [Int32: Resource] = [:]
    fileprivate var borrowedPaths: [Int32: String] = [:]
    fileprivate var resourceOrder: [Resource] = []
    fileprivate var sequence: UInt64 = 0
    fileprivate var sourcesCaptured = false
    fileprivate var canonicalSources: [String: OriginalEraseScratchCleanupCanonicalSourceV1] = [:]
    fileprivate var directorySources: [String: OriginalEraseScratchCleanupDirectorySourceV1] = [:]
    fileprivate var directoryMappings: [String: String] = [:]
    fileprivate var publications: [String: OriginalEraseScratchCleanupPrimitiveIntentV1] = [:]
    fileprivate var activeIntent: OriginalEraseScratchCleanupPrimitiveIntentV1?
    fileprivate var activeOutcome: OriginalEraseScratchCleanupPrimitiveOutcomeV1?
    fileprivate var catalogSession: OriginalEraseScratchCanonicalSourceCatalogSessionV1?
    fileprivate var completedCatalogSessions: [OriginalEraseScratchCanonicalSourceCatalogSessionV1] = []
    var checkedPrimitiveSequence: UInt64 { sequence } // DATA, never permission.

    fileprivate init(operationID: UUID, image: OriginalEraseScratchCleanupImageV1,
        retainedIO: EraseAbortCheckedSnapshotIOV1,
        permit: OriginalEraseScratchCleanupEffectPermitV1) {
        self.operationID = operationID; initialImage = image; self.image = image
        self.retainedIO = retainedIO; self.permit = permit
    }

    fileprivate func requireActive() throws {
        guard lifetime == .active else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        try permit.requireHeld()
        try catalogSession?.requireHeld(attempt: self)
    }

    func requireCanonicalCatalogFrame(session: OriginalEraseScratchCanonicalSourceCatalogSessionV1) throws {
        guard lifetime == .active, catalogSession === session, !sourcesCaptured else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        if let intent = activeIntent {
            guard case .closeOwnedResource = intent.kind else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        }
        for resource in resourceOrder where resource.state == .open {
            switch resource.role {
            case .cleanupPin: break
            case .catalog(let value): guard value === session else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            case .engineRead, .publication: throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
        }
        try permit.requireHeld()
    }

    func requireCatalogResourcesCheckedClosed(session: OriginalEraseScratchCanonicalSourceCatalogSessionV1) throws {
        // Pure retained settlement data, also callable after lexical G release.
        // Actual Session finish independently brackets this with its held owner.
        guard lifetime != .uncertain,
              catalogSession === session || completedCatalogSessions.contains(where: { $0 === session }),
              activeIntent == nil, activeOutcome == nil,
              resourceOrder.filter({ $0.catalogSession === session }).allSatisfy({ $0.state == .closed }) else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        try retainedIO.requireSettled()
    }

    /// Nonrecursive actual EX/G/frame proof. Physical policy readers use only
    /// this retained active request/outcome, before the complete readback exists.
    func requireObservationFrame(
        intent: OriginalEraseScratchCleanupPrimitiveIntentV1,
        outcome: OriginalEraseScratchCleanupPrimitiveOutcomeV1?
    ) throws {
        guard lifetime == .active || lifetime == .closing,
              activeIntent === intent, intent.attemptID == attemptID,
              intent.operationID == operationID,
              activeOutcome === outcome else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        try permit.requireHeld()
    }

    func retainedCanonicalSources() throws -> [OriginalEraseScratchCleanupCanonicalSourceV1] {
        try requireActive()
        guard sourcesCaptured, catalogSession == nil else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        let value = canonicalSources.values.sorted { $0.path < $1.path }
        try permit.requireHeld()
        return value
    }

    func retainedDirectorySources() throws -> [OriginalEraseScratchCleanupDirectorySourceV1] {
        try requireActive()
        guard sourcesCaptured, catalogSession == nil else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        let value = directorySources.values.sorted { $0.originalPath < $1.originalPath }
        try permit.requireHeld()
        return value
    }

    /// Pure exact owner identity/state, never an inspection of its old FD.
    func requireOwnedCloseRequest(intent: OriginalEraseScratchCleanupPrimitiveIntentV1,
        outcome: OriginalEraseScratchCleanupPrimitiveOutcomeV1?) throws {
        try requireObservationFrame(intent: intent, outcome: outcome)
        guard case .closeOwnedResource(let path, let resourceID) = intent.kind,
              let resource = resourceOrder.first(where: { $0.resourceID == resourceID }),
              resource.path == path else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        if let session = catalogSession {
            guard resource.catalogSession === session else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        }
        if let outcome {
            guard outcome.intent === intent,
                  (outcome.result == 0 ? resource.state == .closed : resource.state == .uncertain) else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
        } else {
            guard resource.state == .open else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        }
    }

    func retainedPublicationIntent(temporaryPath: String)
        throws -> OriginalEraseScratchCleanupPrimitiveIntentV1? {
        guard lifetime == .active || lifetime == .closing else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        try permit.requireHeld()
        let value = publications[temporaryPath]
        try permit.requireHeld()
        return value // DATA lookup only; nil grants no absence/effect permission.
    }

    fileprivate func retainCanonicalSource(path: String, bytes: Data, fullFact: String) throws {
        try requireActive()
        guard !sourcesCaptured else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        try permit.requireCanonicalSource(path: path, bytes: bytes, fullFact: fullFact)
        let sha = try CompatibilityCanonicalV1.sha256(bytes)
        if let old = canonicalSources[path] {
            guard old.bytes == bytes, old.fullFact == fullFact, old.sha256 == sha else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
        } else {
            canonicalSources[path] = .init(path: path, bytes: bytes, fullFact: fullFact, sha256: sha)
        }
        try permit.requireHeld()
    }

    fileprivate func observe<Value>(_ body: () throws -> Value) throws -> Value {
        let incomingErrno = errno
        do {
            try requireActive()
            errno = incomingErrno
            let value = Result { try body() }
            let actualErrno = errno
            try permit.requireHeld()
            errno = actualErrno
            return try value.get()
        } catch { poison(); throw error }
    }

    fileprivate func retainDescriptor(_ descriptor: Int32, path: String, role: ResourceRole) throws {
        guard lifetime == .active, descriptor >= 0, resources[descriptor] == nil else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        let resource = Resource(descriptor: descriptor, path: path,
            role: role,
            close: { Darwin.close(descriptor) })
        resources[descriptor] = resource; resourceOrder.append(resource)
    }

    fileprivate func path(for descriptor: Int32) throws -> String {
        try requireActive()
        if let resource = resources[descriptor], resource.state == .open { return resource.path }
        guard let path = borrowedPaths[descriptor] else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        return path
    }

    fileprivate func childPath(parent: Int32, name: String) throws -> String {
        guard OperationalDiagnosticsBoundsV1.validRelativeName(name) else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        let parentPath = try path(for: parent)
        return parentPath.isEmpty ? name : parentPath + "/" + name
    }

    fileprivate func open(parent: Int32, name: String, flags: Int32, role: ResourceRole? = nil) throws -> Int32 {
        let path = try childPath(parent: parent, name: name)
        // Select the actual private role before the open syscall. A filename or
        // successful close is never used to retroactively classify ownership.
        let selectedRole = role ?? catalogSession.map { .catalog($0) } ?? .engineRead
        let incomingErrno = errno
        try requireActive()
        errno = incomingErrno
        let descriptor = Darwin.openat(parent, name, flags | O_NOFOLLOW | O_CLOEXEC)
        let actualErrno = errno
        // Ownership precedes the first callback or validation after open.
        if descriptor >= 0 { try retainDescriptor(descriptor, path: path, role: selectedRole) }
        do { try permit.requireHeld() }
        catch { poison(); errno = actualErrno; throw error }
        errno = actualErrno
        return descriptor
    }

    fileprivate func requireDescriptor(_ descriptor: Int32) throws -> Resource {
        try requireActive()
        guard let resource = resources[descriptor], resource.state == .open else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        return resource
    }

    fileprivate func perform(_ kind: OriginalEraseScratchCleanupPrimitiveIntentV1.Kind,
        _ syscall: () throws -> Int64) throws -> Int64 {
        let incomingErrno = errno
        do {
            let isClose: Bool
            if case .closeOwnedResource = kind { isClose = true } else { isClose = false }
            if isClose, lifetime == .closing { try permit.requireHeld() }
            else { try requireActive() }
            guard (sourcesCaptured || isClose), activeIntent == nil, activeOutcome == nil else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            let next = sequence.addingReportingOverflow(1)
            guard !next.overflow else { throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded }
            let intent = OriginalEraseScratchCleanupPrimitiveIntentV1(attemptID: attemptID,
                operationID: operationID, sequence: next.partialValue, before: image, kind: kind)
            // These exact producer bytes and nonce path precede the first syscall.
            if case .createTemporary(let path, _, let bytes, let sha, _, _) = kind {
                guard publications[path] == nil,
                      try CompatibilityCanonicalV1.sha256(bytes) == sha else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                publications[path] = intent
            }
            activeIntent = intent
            try permit.willPerform(intent)
            errno = incomingErrno
            let actualCall = Result { try syscall() }
            let actualErrno = errno
            let result = (try? actualCall.get()) ?? -1
            let outcome = OriginalEraseScratchCleanupPrimitiveOutcomeV1(intent: intent,
                result: result, syscallErrno: actualErrno)
            activeOutcome = outcome
            let readback = try permit.didPerform(outcome)
            try readback.requireBound(to: outcome)
            image = readback.after
            sequence = next.partialValue
            activeOutcome = nil; activeIntent = nil
            try permit.requireHeld()
            errno = actualErrno
            return try actualCall.get()
        } catch { poison(); throw error }
    }

    fileprivate func closeResource(_ resource: Resource, terminalCleanup: Bool) throws {
        guard resource.state == .open else { return }
        func closeOnce() -> Int64 {
            // Detach before close. A postproof must never inspect this alias.
            resource.state = .closeEntered
            resources.removeValue(forKey: resource.descriptor)
            let result = resource.close()
            let actualErrno = errno
            if result == 0 { resource.state = .closed }
            else {
                resource.state = .uncertain
                retainedIO.retainUncertainDescriptor(resource.descriptor)
            }
            errno = actualErrno
            return Int64(result)
        }
        if lifetime == .active || lifetime == .closing {
            do {
                let result: Int64
                if let session = catalogSession, resource.catalogSession === session, !sourcesCaptured {
                    try session.requireHeld(attempt: self)
                    guard activeIntent == nil, activeOutcome == nil else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                    let next = sequence.addingReportingOverflow(1)
                    guard !next.overflow else { throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded }
                    let intent = OriginalEraseScratchCleanupPrimitiveIntentV1(attemptID: attemptID,
                        operationID: operationID, sequence: next.partialValue, before: image,
                        kind: .closeOwnedResource(path: resource.path, resourceID: resource.resourceID))
                    activeIntent = intent
                    try session.retainCloseIntent(intent, attempt: self)
                    result = closeOnce()
                    let actualErrno = errno
                    let outcome = OriginalEraseScratchCleanupPrimitiveOutcomeV1(intent: intent,
                        result: result, syscallErrno: actualErrno)
                    activeOutcome = outcome
                    try session.recordCloseOutcome(outcome, attempt: self)
                    sequence = next.partialValue
                    activeOutcome = nil; activeIntent = nil
                    try session.requireHeld(attempt: self)
                    errno = actualErrno
                    // No per-close whole image is minted. The catalog finish
                    // proves the complete unchanged namespace independently.
                } else {
                    result = try perform(.closeOwnedResource(path: resource.path,
                        resourceID: resource.resourceID), closeOnce)
                }
                guard result == 0 else { poison(); throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            } catch {
                let failure = error
                poison()
                // A rejected before-proof still leaves this exact retained
                // owner to settle. An entered close is never retried.
                if resource.state == .open { _ = closeOnce() }
                throw failure
            }
        } else {
            // Exact already-retained owners drain once after the memory fence,
            // even when proof failed. This never permits another filesystem
            // mutation or a read of an old numeric descriptor.
            _ = terminalCleanup
            let result = closeOnce()
            guard result == 0 else { poison(); throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        }
    }

    fileprivate func drainOwnedResources() throws {
        if lifetime == .active { lifetime = .closing }
        var failure: Error?
        for resource in resourceOrder.reversed() where resource.state == .open {
            do { try closeResource(resource, terminalCleanup: true) }
            catch { if failure == nil { failure = error } }
        }
        guard failure == nil, resourceOrder.allSatisfy({ $0.state == .closed }) else {
            poison(); throw failure ?? ScratchDataLeaseStoreFailureV1.invalidRoot
        }
    }

    fileprivate func markClosed() throws {
        guard lifetime == .closing,
              resources.isEmpty, resourceOrder.allSatisfy({ $0.state == .closed }),
              activeIntent == nil, activeOutcome == nil,
              image.scratch == nil, image.ingress == nil else {
            poison(); throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        try retainedIO.requireSettled()
        lifetime = .closed
        store = nil
    }

    func requireCheckedSettlement() throws {
        guard lifetime == .closed, resources.isEmpty,
              resourceOrder.allSatisfy({ $0.state == .closed }),
              activeIntent == nil, activeOutcome == nil,
              image.scratch == nil, image.ingress == nil else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        try retainedIO.requireSettled()
    }

    fileprivate func poison() {
        if lifetime != .uncertain {
            lifetime = .uncertain
            store?.fenceOriginalCleanup(uncertain: true)
            permit.poisonOnUncertainCleanup()
        }
    }
}

@MainActor
final class OriginalEraseScratchCleanupReceiptV1 {
    let operationID: UUID
    let attempt: OriginalEraseScratchCleanupAttemptV1
    let initialImage: OriginalEraseScratchCleanupImageV1
    let finalImage: OriginalEraseScratchCleanupImageV1
    private weak var permit: OriginalEraseScratchCleanupEffectPermitV1?
    fileprivate init(attempt: OriginalEraseScratchCleanupAttemptV1) throws {
        try attempt.requireCheckedSettlement()
        operationID = attempt.operationID; self.attempt = attempt
        initialImage = attempt.initialImage; finalImage = attempt.image
        permit = attempt.permit
    }
    func requireCheckedSettlement() throws { try attempt.requireCheckedSettlement() }
    func requireBound(operationID: UUID,
        attempt: OriginalEraseScratchCleanupAttemptV1,
        finalImage: OriginalEraseScratchCleanupImageV1) throws {
        guard self.operationID == operationID, self.attempt === attempt,
              self.finalImage == finalImage, permit != nil else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        try requireCheckedSettlement()
    }
    func requireBound(operation: EraseRouterOperationV1, store: EraseIntentStore,
        registry: GenerationLeaseRegistryV1,
        exclusion: StoreTemporalNormalizationExclusionV1,
        activity: GenerationTemporalActivityHandleV1) throws {
        guard let permit else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        try permit.requireOrigin(operation: operation, store: store,
            registry: registry, exclusion: exclusion, activity: activity)
        try requireCheckedSettlement()
    }
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
    private enum OriginalCleanupLifetime { case ordinary, active, closed, uncertain }
    private var originalCleanupLifetime = OriginalCleanupLifetime.ordinary
    private var originalCleanupAttempt: OriginalEraseScratchCleanupAttemptV1?

    fileprivate func fenceOriginalCleanup(uncertain: Bool) {
        guard originalCleanupLifetime != .ordinary else { return }
        originalCleanupLifetime = uncertain ? .uncertain : .closed
    }

    /// Permanent memory fence precedes any old numeric descriptor or actor
    /// callback. Clearing the borrowed fields cannot restore ordinary access.
    private func requireOriginalCleanupDescriptorAccess() throws {
        switch originalCleanupLifetime {
        case .ordinary: return
        case .active:
            guard Thread.isMainThread, let attempt = originalCleanupAttempt else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            try MainActor.assumeIsolated { try attempt.requireActive() }
        case .closed, .uncertain: throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
    }

    private func originalCleanupObserve<Value>(_ body: () throws -> Value) throws -> Value {
        try requireOriginalCleanupDescriptorAccess()
        guard originalCleanupLifetime == .active else { return try body() }
        guard Thread.isMainThread, let attempt = originalCleanupAttempt else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        return try MainActor.assumeIsolated { try attempt.observe(body) }
    }

    private func originalCleanupFstat(_ fd: Int32, _ value: UnsafeMutablePointer<stat>) throws -> Int32 {
        try originalCleanupObserve { Darwin.fstat(fd, value) }
    }
    private func originalCleanupFstatat(_ fd: Int32, _ name: String,
        _ value: UnsafeMutablePointer<stat>, _ flags: Int32) throws -> Int32 {
        try originalCleanupObserve { Darwin.fstatat(fd, name, value, flags) }
    }
    private func originalCleanupOpenat(_ parent: Int32, _ name: String, _ flags: Int32) throws -> Int32 {
        try requireOriginalCleanupDescriptorAccess()
        guard originalCleanupLifetime == .active else { return Darwin.openat(parent, name, flags) }
        guard flags & (O_CREAT | O_TRUNC) == 0, Thread.isMainThread,
              let attempt = originalCleanupAttempt else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        return try MainActor.assumeIsolated { try attempt.open(parent: parent, name: name, flags: flags) }
    }
    private func originalCleanupSync(_ fd: Int32) throws -> Int32 {
        try requireOriginalCleanupDescriptorAccess()
        guard originalCleanupLifetime == .active else { return Darwin.fsync(fd) }
        guard Thread.isMainThread, let attempt = originalCleanupAttempt else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        return try MainActor.assumeIsolated {
            Int32(try attempt.perform(.synchronize(path: attempt.path(for: fd))) { Int64(Darwin.fsync(fd)) })
        }
    }
    private func originalCleanupUnlink(_ parent: Int32, _ name: String, _ flags: Int32) throws -> Int32 {
        try requireOriginalCleanupDescriptorAccess()
        guard originalCleanupLifetime == .active else { return Darwin.unlinkat(parent, name, flags) }
        guard flags == 0 || flags == AT_REMOVEDIR, Thread.isMainThread,
              let attempt = originalCleanupAttempt else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        return try MainActor.assumeIsolated {
            let path = try attempt.childPath(parent: parent, name: name)
            let kind: OriginalEraseScratchCleanupPrimitiveIntentV1.Kind = flags == 0
                ? .removeLeaf(path: path) : .removeDirectory(path: path)
            return Int32(try attempt.perform(kind) { Int64(Darwin.unlinkat(parent, name, flags)) })
        }
    }
    private func originalCleanupRename(_ source: Int32, _ name: String,
        _ destination: Int32, _ newName: String) throws -> Int32 {
        try requireOriginalCleanupDescriptorAccess()
        guard originalCleanupLifetime == .active else { return Darwin.renameat(source, name, destination, newName) }
        guard Thread.isMainThread, let attempt = originalCleanupAttempt else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        return try MainActor.assumeIsolated {
            let before = try attempt.childPath(parent: source, name: name)
            let after = try attempt.childPath(parent: destination, name: newName)
            let kind: OriginalEraseScratchCleanupPrimitiveIntentV1.Kind
            if source == authority.rootDescriptor && destination == source,
               Self.isLeaseDirectoryName(name), newName == Self.deletionTombstoneName(for: name) {
                kind = .renameLeaseDirectory(originalPath: before, tombstonePath: after)
            } else { kind = .renamePublication(sourcePath: before, finalPath: after, exclusive: false) }
            let result = try attempt.perform(kind) { Int64(Darwin.renameat(source, name, destination, newName)) }
            if result == 0 {
                if case .renameLeaseDirectory = kind {
                    attempt.directoryMappings[after] = attempt.directoryMappings[before] ?? before
                }
                for resource in attempt.resourceOrder where resource.state == .open {
                    if resource.path == before { resource.path = after }
                    else if resource.path.hasPrefix(before + "/") {
                        resource.path = after + String(resource.path.dropFirst(before.count))
                    }
                }
            }
            return Int32(result)
        }
    }
    private func originalCleanupLock(_ fd: Int32, _ flags: Int32) throws -> Int32 {
        try requireOriginalCleanupDescriptorAccess()
        guard originalCleanupLifetime == .active else { return flock(fd, flags) }
        guard flags == (LOCK_EX | LOCK_NB), Thread.isMainThread,
              let attempt = originalCleanupAttempt else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        return try MainActor.assumeIsolated {
            Int32(try attempt.perform(.lockOwnedDirectory(path: attempt.path(for: fd))) { Int64(flock(fd, flags)) })
        }
    }
    private func originalCleanupClose(_ fd: Int32) throws {
        try requireOriginalCleanupDescriptorAccess()
        guard originalCleanupLifetime == .active else { _ = Darwin.close(fd); return }
        guard Thread.isMainThread, let attempt = originalCleanupAttempt else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        try MainActor.assumeIsolated { try attempt.closeResource(attempt.requireDescriptor(fd), terminalCleanup: false) }
    }
    private func originalCleanupCloseAfterBody(_ fd: Int32) {
        if originalCleanupLifetime == .ordinary { _ = Darwin.close(fd); return }
        guard Thread.isMainThread, let attempt = originalCleanupAttempt else { return }
        MainActor.assumeIsolated {
            guard let resource = attempt.resources[fd], resource.state == .open else { return }
            do { try attempt.closeResource(resource, terminalCleanup: false) }
            catch { attempt.poison() }
        }
    }

    private func originalCleanupCloseResult(_ fd: Int32) -> Int32 {
        if originalCleanupLifetime == .ordinary { return Darwin.close(fd) }
        guard originalCleanupLifetime == .active, Thread.isMainThread,
              let attempt = originalCleanupAttempt else { errno = EBADF; return -1 }
        return MainActor.assumeIsolated {
            do {
                let resource = try attempt.requireDescriptor(fd)
                try attempt.closeResource(resource, terminalCleanup: false)
                return 0
            } catch { attempt.poison(); return -1 }
        }
    }

    private func originalCleanupDeferredClose(_ fd: Int32) -> () -> Void {
        if originalCleanupLifetime == .ordinary { return { _ = Darwin.close(fd) } }
        guard Thread.isMainThread, let attempt = originalCleanupAttempt else { return {} }
        // Retain this exact owner object now. A later reused integer can never
        // select another resource in an error/defer path.
        let resource = MainActor.assumeIsolated { attempt.resources[fd] }
        return {
            guard Thread.isMainThread, let resource else { return }
            MainActor.assumeIsolated {
                do { try attempt.closeResource(resource, terminalCleanup: attempt.lifetime != .active) }
                catch { attempt.poison() }
            }
        }
    }

    // Retained by the already-owned exclusive Store before the first receipt
    // scan. An ambiguous checked close cannot escape with a local IO value.
    private var originalEraseSourceReceiptIO: EraseAbortCheckedSnapshotIOV1?

    private func applySourceReadPolicy(
        _ kind: OwnedFileKindV1, at url: URL,
        authorityCheck: () throws -> Void = {}
    ) throws {
        try requireOriginalCleanupDescriptorAccess()
        if originalCleanupLifetime == .active {
            guard Thread.isMainThread, let attempt = originalCleanupAttempt else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            try MainActor.assumeIsolated {
                try authorityCheck()
                let path = try originalCleanupRelativePath(url)
                let before = try originalCleanupImageNode(path)
                _ = try attempt.perform(.requestPolicy(path: path, kind: kind)) {
                    guard let intent = attempt.activeIntent else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                    let scope = try attempt.permit.requirePolicyEffectScope(intent: intent)
                    _ = try ProtectedFilePolicyV1.applyOriginalEraseScratchPublicationPolicyWithCheckedClose(
                        kind, at: url, initialFullFact: before.fullFact, scope: scope,
                        retainUncertainDescriptor: { attempt.retainedIO.retainUncertainDescriptor($0) })
                    return 0
                }
                try authorityCheck(); try attempt.requireActive()
            }
            return
        }
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
        try requireOriginalCleanupDescriptorAccess()
        if originalCleanupLifetime == .active {
            guard Thread.isMainThread, let attempt = originalCleanupAttempt else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            try MainActor.assumeIsolated {
                try attempt.requireActive()
                let relative = try originalCleanupRelativePath(url)
                let node = try originalCleanupImageNode(relative)
                let fields = node.fullFact.split(separator: "|", omittingEmptySubsequences: false)
                guard fields.count == 11 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                if fields[5] == "2", kind == .temporaryFile {
                    _ = try originalCleanupPairPolicy(path: relative)
                    try attempt.requireActive()
                    return
                }
                let scope = try attempt.permit.currentTemporalObservationScope()
                _ = try ProtectedFilePolicyV1.observeOriginalEraseScratchTemporalPolicyWithCheckedClose(
                    kind, at: url, fullFact: node.fullFact, scope: scope,
                    retainUncertainDescriptor: { attempt.retainedIO.retainUncertainDescriptor($0) })
                try attempt.requireActive()
            }
            return
        }
        if exclusiveNoRepairRead {
            try ProtectedFilePolicyV1.verifyEraseColdPrivateWithCheckedClose(
                kind, at: url, retainUncertainDescriptor: {
                    _ = ScratchUncertainCloseQuarantineV1.shared.begin($0)
                })
        } else {
            try ProtectedFilePolicyV1.verify(kind, at: url)
        }
    }

    /// Preserve the old direct verify call for all ordinary instances.
    private func originalCleanupVerifyPolicy(_ kind: OwnedFileKindV1, at url: URL) throws {
        try requireOriginalCleanupDescriptorAccess()
        if originalCleanupLifetime == .active { try verifySourceReadPolicy(kind, at: url) }
        else { try ProtectedFilePolicyV1.verify(kind, at: url) }
    }

    private func originalCleanupRelativePath(_ url: URL) throws -> String {
        let operationsURL = rootURL.deletingLastPathComponent()
        guard url.standardizedFileURL == url,
              url.path.hasPrefix(operationsURL.path + "/") else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        let path = String(url.path.dropFirst(operationsURL.path.count + 1))
        guard path.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy({ OperationalDiagnosticsBoundsV1.validRelativeName(String($0)) }) else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        return path
    }

    @MainActor private func originalCleanupImageNode(_ path: String)
        throws -> OriginalEraseScratchCleanupImageV1.Node {
        guard let value = try originalCleanupImageNodeIfPresent(path) else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        return value
    }

    @MainActor private func originalCleanupImageNodeIfPresent(_ path: String)
        throws -> OriginalEraseScratchCleanupImageV1.Node? {
        guard let attempt = originalCleanupAttempt else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        try attempt.requireActive()
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard let first = parts.first else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        let root: OriginalEraseScratchCleanupImageV1.Root?
        if first == Self.rootName { root = attempt.image.scratch }
        else if first == "ProtectedIngressReceiptsV1" { root = attempt.image.ingress }
        else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        let local = parts.dropFirst().joined(separator: "/")
        return root?.nodes.first(where: { $0.path == local }) // DATA in a complete checked current image.
    }

    @MainActor private func originalCleanupPairPolicy(path: String)
        throws -> [TemporalPolicyObservationV1] {
        guard let attempt = originalCleanupAttempt else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        let selected = try originalCleanupImageNode(path)
        let fields = selected.fullFact.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count == 11, fields[5] == "2" else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        let roots = [(Self.rootName, attempt.image.scratch), ("ProtectedIngressReceiptsV1", attempt.image.ingress)]
        var members = [String]()
        for (rootName, root) in roots {
            for node in root?.nodes ?? [] where !node.path.isEmpty {
                let fact = node.fullFact.split(separator: "|", omittingEmptySubsequences: false)
                if fact.count == 11, fact[0] == fields[0], fact[1] == fields[1], fact[5] == "2" {
                    members.append(rootName + "/" + node.path)
                }
            }
        }
        members.sort { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        guard members.count == 2, members.contains(path) else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        let scope = try attempt.permit.currentTemporalObservationScope()
        let urls = members.map { rootURL.deletingLastPathComponent().appendingPathComponent($0) }
        // The selected facts only locate the exact candidate aliases. The
        // private scope supplies positive actual publication/original role;
        // an inode coincidence alone never authorizes the pair.
        return try ProtectedFilePolicyV1.observeOriginalEraseScratchTemporalPairWithCheckedClose(
            aliasURLs: urls, scope: scope,
            retainUncertainDescriptor: { attempt.retainedIO.retainUncertainDescriptor($0) })
    }

    private func originalCleanupPermitsRegularLinkCount(_ information: stat,
        parent: Int32, name: String) throws -> Bool {
        try requireOriginalCleanupDescriptorAccess()
        if information.st_nlink == 1 { return true }
        guard originalCleanupLifetime == .active, information.st_nlink == 2,
              Thread.isMainThread, let attempt = originalCleanupAttempt else { return false }
        return try MainActor.assumeIsolated {
            let path = try attempt.childPath(parent: parent, name: name)
            guard try originalCleanupImageNode(path).fullFact == Self.originalEraseSourceFullFact(information) else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            _ = try originalCleanupPairPolicy(path: path)
            try attempt.requireActive()
            return true
        }
    }

    @MainActor private func originalCleanupDirectoryNames(_ descriptor: Int32) throws -> [String] {
        guard let attempt = originalCleanupAttempt else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        let path = try attempt.path(for: descriptor)
        let role: OriginalEraseScratchCleanupAttemptV1.ResourceRole = attempt.catalogSession.map { .catalog($0) } ?? .engineRead
        let incomingErrno = errno
        try attempt.requireActive()
        errno = incomingErrno
        let fd = Darwin.openat(descriptor, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        let actualErrno = errno
        if fd >= 0 { try attempt.retainDescriptor(fd, path: path, role: role) }
        try attempt.requireActive(); errno = actualErrno
        guard fd >= 0, let resource = attempt.resources[fd] else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        do {
            let directory = try attempt.observe {
                let directory = Darwin.fdopendir(fd)
                if let directory { resource.close = { Darwin.closedir(directory) } }
                return directory
            }
            guard let directory else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            var names = [String]()
            errno = 0
            while let entry = try attempt.observe({ Darwin.readdir(directory) }) {
                guard let name = OwnedStorageDirectoryEntryNameV1.decode(entry) else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                if name != "." && name != ".." {
                    guard OperationalDiagnosticsBoundsV1.validRelativeName(name) else {
                        throw ScratchDataLeaseStoreFailureV1.invalidRoot
                    }
                    names.append(name)
                }
                errno = 0
            }
            guard errno == 0, Set(names).count == names.count else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            try attempt.closeResource(resource, terminalCleanup: false)
            return names.sorted()
        } catch {
            let failure = error
            attempt.poison()
            try? attempt.closeResource(resource, terminalCleanup: true)
            throw failure
        }
    }

    @MainActor private func originalCleanupReadRegularFile(named name: String,
        directoryDescriptor: Int32, maximumBytes: Int) throws -> Data {
        guard let attempt = originalCleanupAttempt, maximumBytes >= 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        let expected = try regularFileInformation(named: name, directoryDescriptor: directoryDescriptor)
        let path = try attempt.childPath(parent: directoryDescriptor, name: name)
        let expectedNode = try originalCleanupImageNode(path)
        guard expectedNode.fullFact == Self.originalEraseSourceFullFact(expected),
              let expectedSHA = expectedNode.contentSHA256 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        guard expected.st_size <= Int64(maximumBytes) else { throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded }
        let descriptor = try attempt.open(parent: directoryDescriptor, name: name, flags: O_RDONLY | O_NONBLOCK)
        guard descriptor >= 0, let resource = attempt.resources[descriptor] else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        do {
            var pinned = stat()
            guard try attempt.observe({ Darwin.fstat(descriptor, &pinned) }) == 0,
                  Self.originalEraseSourceFullFact(pinned) == Self.originalEraseSourceFullFact(expected) else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            var bytes = Data(count: Int(pinned.st_size))
            var offset = 0
            while offset < bytes.count {
                let read = try bytes.withUnsafeMutableBytes { buffer in
                    try attempt.observe { Darwin.read(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset) }
                }
                guard read > 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                offset += read
            }
            var after = stat(), named = stat()
            guard try attempt.observe({ Darwin.fstat(descriptor, &after) }) == 0,
                  try attempt.observe({ Darwin.fstatat(directoryDescriptor, name, &named, AT_SYMLINK_NOFOLLOW) }) == 0,
                  Self.originalEraseSourceFullFact(after) == Self.originalEraseSourceFullFact(pinned),
                  Self.originalEraseSourceFullFact(named) == Self.originalEraseSourceFullFact(pinned) else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            guard try CompatibilityCanonicalV1.sha256(bytes) == expectedSHA else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            try attempt.closeResource(resource, terminalCleanup: false)
            return bytes
        } catch {
            let failure = error
            attempt.poison(); try? attempt.closeResource(resource, terminalCleanup: true)
            throw failure
        }
    }
    // Populated only by real returned in-process acquisitions, never by cold
    // metadata recovery. A serializable lease is not a live producer proof.
    private var producerActivities: [UUID: OwnedStorageProducerActivityV1] = [:]

    private var producerApplicationSupportURL: URL {
        rootURL.deletingLastPathComponent().deletingLastPathComponent()
    }

    private func withProducerFilesystemLock<Value>(_ body: () throws -> Value) throws -> Value {
        try requireOriginalCleanupDescriptorAccess()
        if originalCleanupLifetime == .active {
            guard Thread.isMainThread, let attempt = originalCleanupAttempt else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            return try MainActor.assumeIsolated {
                try Self.filesystemLock.withLock {
                    try attempt.requireActive()
                    let value = Result { try body() }
                    try attempt.requireActive()
                    return try value.get()
                }
            }
        }
        let activity = try OwnedStorageProducerActivityV1.acquire(
            applicationSupportURL: producerApplicationSupportURL)
        defer { activity.close() }
        return try Self.filesystemLock.withLock {
            try activity.requireApplicationSupport(producerApplicationSupportURL)
            return try body()
        }
    }
    private var ingressControlAuthority: PinnedScratchRootV1?

    /// The sole live original cleanup entry. No ordinary producer activity or
    /// root preparation is entered while the original owner retains its EX.
    @MainActor static func eraseForOriginalRetainedOwner(
        applicationSupportURL: URL, operationID: UUID, support: Int32, operations: Int32,
        initialImage: OriginalEraseScratchCleanupImageV1,
        retainedIO: EraseAbortCheckedSnapshotIOV1,
        permit: OriginalEraseScratchCleanupEffectPermitV1
    ) throws -> OriginalEraseScratchCleanupReceiptV1 {
        guard operationID == permit.operationID,
              operationID != SettingsValidationV1.zeroUUID else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        _ = support // Actual parent membership is proven by the private issuer.
        try retainedIO.requireSettled()
        try permit.requireInitialImage(initialImage)
        let attempt = OriginalEraseScratchCleanupAttemptV1(operationID: operationID,
            image: initialImage, retainedIO: retainedIO, permit: permit)
        try permit.retainAttempt(attempt)
        attempt.borrowedPaths[operations] = ""
        Self.filesystemLock.lock()
        defer { Self.filesystemLock.unlock() }
        do {
            // An absent root is not created solely to erase it. The separate
            // control-only origin needs a genuine historical Scratch identity.
            guard let expectedScratch = initialImage.scratch else {
                guard initialImage.ingress == nil else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                attempt.sourcesCaptured = true
                try attempt.drainOwnedResources(); try attempt.markClosed()
                return try OriginalEraseScratchCleanupReceiptV1(attempt: attempt)
            }
            var operationsInformation = stat()
            guard try attempt.observe({ Darwin.fstat(operations, &operationsInformation) }) == 0,
                  originalEraseSourceFullFact(operationsInformation) == initialImage.operationsFullFact else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            let operationsURL = applicationSupportURL.standardizedFileURL
                .appendingPathComponent(OwnedStorageRootKindV1.operations.rawValue, isDirectory: true)
            func openPin(name: String, expected: OriginalEraseScratchCleanupImageV1.Root) throws -> PinnedScratchRootV1 {
                let fd = try attempt.open(parent: operations, name: name, flags: O_RDONLY | O_DIRECTORY, role: .cleanupPin)
                guard fd >= 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                var information = stat(), named = stat()
                guard try attempt.observe({ Darwin.fstat(fd, &information) }) == 0,
                      try attempt.observe({ Darwin.fstatat(operations, name, &named, AT_SYMLINK_NOFOLLOW) }) == 0,
                      originalEraseSourceFullFact(information) == expected.fullFact,
                      originalEraseSourceFullFact(named) == expected.fullFact,
                      information.st_mode & S_IFMT == S_IFDIR else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                return try PinnedScratchRootV1(originalCleanupOperationsURL: operationsURL,
                    operations: operations, root: fd, operationsInformation: operationsInformation,
                    rootInformation: information, requireBorrow: { try attempt.requireActive() })
            }
            let scratchPin = try openPin(name: Self.rootName, expected: expectedScratch)
            let ingressPin = try initialImage.ingress.map { try openPin(name: "ProtectedIngressReceiptsV1", expected: $0) }
            let store = try ScratchDataLeaseStoreV1(
                originalCleanupRootURL: operationsURL.appendingPathComponent(Self.rootName, isDirectory: true),
                clock: { Date() }, scratchAuthority: scratchPin, ingressAuthority: ingressPin, attempt: attempt)
            attempt.store = store
            let catalog = try permit.beginCanonicalSourceCatalog(attempt: attempt)
            attempt.catalogSession = catalog
            try catalog.requireHeld(attempt: attempt)
            try store.captureOriginalCleanupCanonicalSources()
            try permit.finishCanonicalSourceCatalog(catalog, attempt: attempt)
            try catalog.requireCompleted(attempt: attempt)
            attempt.completedCatalogSessions.append(catalog)
            attempt.catalogSession = nil
            attempt.sourcesCaptured = true
            // This existing synchronous engine includes every nested hygiene,
            // ingress removal, lease rename, publication and marker tail.
            try store.withProducerFilesystemLock { try store.eraseScratchDataSynchronously() }
            // No instance primitive may inspect its old FDs after admission to
            // final close. Private retained resource owners drain separately.
            store.fenceOriginalCleanup(uncertain: false)
            try attempt.drainOwnedResources(); try attempt.markClosed()
            return try OriginalEraseScratchCleanupReceiptV1(attempt: attempt)
        } catch {
            let failure = error
            attempt.poison()
            do { try attempt.drainOwnedResources() } catch { throw error }
            throw failure
        }
    }

    @MainActor private func captureOriginalCleanupCanonicalSources() throws {
        guard let attempt = originalCleanupAttempt, !attempt.sourcesCaptured else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        // Select roles from the authenticated initial image, never from a
        // surviving directory scan after dependencies have disappeared.
        for node in attempt.initialImage.scratch?.nodes ?? [] {
            let parts = node.path.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, parts[1] == Self.metadataName else { continue }
            let directoryName = String(parts[0])
            guard Self.isLeaseDirectoryName(directoryName) || Self.isDeletionTombstone(directoryName) else {
                throw ScratchDataLeaseStoreFailureV1.invalidLease
            }
            let descriptor = try openLeaseDirectory(directoryName)
            guard let resource = attempt.resources[descriptor] else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            do {
                let bytes = try readRegularFile(named: Self.metadataName, directoryDescriptor: descriptor, maximumBytes: 65_536)
                let lease = try JSONDecoder().decode(ScratchDataLeaseV1.self, from: bytes)
                try lease.request.validate()
                let originalName = Self.isDeletionTombstone(directoryName)
                    ? String(directoryName.dropFirst(Self.deletionPrefix.count)) : directoryName
                guard lease.schemaVersion == ScratchDataLeaseV1.schemaVersion,
                      lease.request.schemaVersion == ScratchDataLeaseRequestV1.schemaVersion,
                      lease.request.protection == .complete,
                      lease.request.backupPolicy == .excluded,
                      lease.request.createdAt <= clock(),
                      lease.relativeDirectory == originalName,
                      originalName == Self.leaseDirectoryName(for: lease.request),
                      try canonicalData(lease) == bytes else { throw ScratchDataLeaseStoreFailureV1.invalidLease }
                try attempt.retainCanonicalSource(path: Self.rootName + "/" + node.path,
                    bytes: bytes, fullFact: node.fullFact)
                try attempt.closeResource(resource, terminalCleanup: false)
            } catch {
                let failure = error
                attempt.poison(); try? attempt.closeResource(resource, terminalCleanup: true)
                throw failure
            }
        }
        for node in attempt.initialImage.scratch?.nodes ?? []
        where !node.path.isEmpty && !node.path.contains("/") {
            let fields = node.fullFact.split(separator: "|", omittingEmptySubsequences: false)
            guard fields.count == 11, let mode = UInt32(fields[2]), mode & UInt32(S_IFMT) == UInt32(S_IFDIR),
                  Self.isLeaseDirectoryName(node.path) || Self.isDeletionTombstone(node.path) else {
                throw ScratchDataLeaseStoreFailureV1.invalidLease
            }
            let path = Self.rootName + "/" + node.path
            let metadataPath = path + "/" + Self.metadataName
            let metadata: OriginalEraseScratchCleanupDirectorySourceV1.Metadata
            if let source = attempt.canonicalSources[metadataPath] {
                metadata = .validatedLease(bytes: source.bytes, fullFact: source.fullFact, sha256: source.sha256)
            } else {
                // Positive complete original-image absence, not a present
                // corrupt lease converted into an orphan or a live lease.
                guard !(attempt.initialImage.scratch?.nodes.contains(where: {
                    $0.path == node.path + "/" + Self.metadataName
                }) ?? true) else { throw ScratchDataLeaseStoreFailureV1.invalidLease }
                metadata = .ownedOrphan
            }
            attempt.directorySources[path] = .init(originalPath: path,
                originalFullFact: node.fullFact, metadata: metadata)
            attempt.directoryMappings[path] = path
        }
        if let ingress = attempt.initialImage.ingress {
            guard let pinned = ingressControlAuthority else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            for node in ingress.nodes where !node.path.isEmpty && !node.path.hasPrefix(".partial-") {
                guard !node.path.contains("/") else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                if node.path != Self.controlEraseName { try validateIngressControlSnapshotName(node.path) }
                let maximum = node.path == Self.controlEraseName ? 32 * 1_024 * 1_024 : 262_144
                let bytes = try readRegularFile(named: node.path, directoryDescriptor: pinned.rootDescriptor, maximumBytes: maximum)
                try attempt.retainCanonicalSource(path: "ProtectedIngressReceiptsV1/" + node.path,
                    bytes: bytes, fullFact: node.fullFact)
            }
        }
        try attempt.requireActive()
    }

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

    /// No root preparation, policy repair, producer activity or FD ownership.
    /// Both real existing roots were admitted/opened by the retained attempt.
    private init(originalCleanupRootURL: URL, clock: @escaping Clock,
        scratchAuthority: PinnedScratchRootV1,
        ingressAuthority: PinnedScratchRootV1?,
        attempt: OriginalEraseScratchCleanupAttemptV1) throws {
        rootURL = originalCleanupRootURL
        self.clock = clock
        ingressHygieneFailureInjection = .none; ingressMutationFailureInjection = .none
        storagePreflight = StoragePreflightService(capacityProvider: { _ in nil })
        authority = scratchAuthority
        ingressControlAuthority = ingressAuthority
        originalCleanupLifetime = .active; originalCleanupAttempt = attempt
        exclusiveNoRepairRead = true
        try requireOriginalCleanupDescriptorAccess()
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
        try reconcileProtectedIngressHygiene(
            now: now, operationID: operationID, minimumAge: minimumAge
        )
    }

    /// Crash-safe C16 startup hygiene. Preparation is durable before a target
    /// is removed; the prepared metadata is sufficient to recreate the exact
    /// final receipt after interruption without opening any payload bytes.
    func reconcileProtectedIngressHygiene(
        now: Date,
        operationID: UUID,
        minimumAge: TimeInterval = 24 * 60 * 60
    ) throws -> ProtectedIngressStartupHygieneReceiptV1 {
        guard operationID != SettingsValidationV1.zeroUUID,
              now.timeIntervalSinceReferenceDate.isFinite,
              minimumAge > 0, minimumAge.isFinite else {
            throw AppAccessContractFailureV1.invalidValue
        }
        return try withProducerFilesystemLock {
            let request = C16IngressHygieneRequestV1(
                operationID: operationID, requestedAt: now, minimumAge: minimumAge
            )
            let requestDigest = try CompatibilityCanonicalV1.sha256(
                CompatibilityCanonicalV1.encode(request)
            )
            _ = try protectedIngressReceiptDirectory()
            let prepareFile = try protectedIngressPrepareFile(operationID: operationID)
            let receiptFile = try protectedIngressReceiptFile(operationID: operationID)
            let prepare: C16IngressHygienePrepareV1
            if try ingressControlFileExists(prepareFile) {
                prepare = try readProtectedIngressPrepare(at: prepareFile)
                guard prepare.requestDigest == requestDigest else {
                    throw AppAccessContractFailureV1.effectMismatch
                }
            } else {
                guard try !ingressControlFileExists(receiptFile) else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
                prepare = try makeProtectedIngressPrepare(
                    request: request, requestDigest: requestDigest
                )
                try writeProtectedIngressCanonical(
                    try CompatibilityCanonicalV1.encode(prepare), to: prepareFile
                )
                try ingressHygieneFailureInjection.interruptIfTriggered(.afterPrepare)
            }
            guard prepare.rootDevice == authority.rootDevice,
                  prepare.rootInode == authority.rootInode else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            let expected = try prepare.receipt()
            if try ingressControlFileExists(receiptFile) {
                let existing = try readProtectedIngressReceipt(at: receiptFile, operationID: operationID)
                guard existing == expected else { throw AppAccessContractFailureV1.effectMismatch }
                if !prepare.finalized {
                    try finalizeProtectedIngressPrepare(prepare, at: prepareFile)
                }
                return existing
            }
            guard !prepare.finalized else { throw AppAccessContractFailureV1.configurationUnknown }
            for target in prepare.targets {
                try removePreparedIngressTarget(target)
            }
            try ingressHygieneFailureInjection.interruptIfTriggered(.afterEffect)
            try writeProtectedIngressCanonical(
                try CompatibilityCanonicalV1.encode(expected), to: receiptFile
            )
            try ingressHygieneFailureInjection.interruptIfTriggered(.afterReceipt)
            try finalizeProtectedIngressPrepare(prepare, at: prepareFile)
            guard try readProtectedIngressReceipt(at: receiptFile, operationID: operationID) == expected else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            return expected
        }
    }

    /// Device-local, metadata-only completion receipt. It is deliberately
    /// outside canonical workspace storage and contains neither a path nor
    /// any staged/payload bytes. The closed operation-ID filename prevents
    /// directory traversal and gives interrupted startup an exact readback.
    func readProtectedIngressHygieneReceipt(
        operationID: UUID
    ) throws -> ProtectedIngressStartupHygieneReceiptV1? {
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
        try requireOriginalCleanupDescriptorAccess()
        try verifyRoot()
        let name = "ProtectedIngressReceiptsV1"
        let directory = rootURL.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
        if originalCleanupLifetime == .active {
            guard let pinned = ingressControlAuthority else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            try pinned.verify(rootName: name)
            try verifySourceReadPolicy(.stagingDirectory, at: directory)
            try pinned.verify(rootName: name)
            return directory
        }
        if ingressControlAuthority == nil {
            try Self.prepareRoot(directory)
            let pinned = try PinnedScratchRootV1(operationsURL: directory.deletingLastPathComponent(), rootName: name)
            try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: directory, authorityCheck: {
                try self.verifyRoot()
                try pinned.verify(rootName: name)
            })
            ingressControlAuthority = pinned
        }
        try ingressControlAuthority?.verify(rootName: name)
        try ProtectedFilePolicyV1.verify(.stagingDirectory, at: directory)
        try ingressControlAuthority?.verify(rootName: name)
        return directory
    }

    private func ingressControlDescriptor() throws -> Int32 {
        _ = try protectedIngressReceiptDirectory()
        guard let ingressControlAuthority else { throw AppAccessContractFailureV1.configurationUnknown }
        guard try regularFileInformationIfPresent(named: Self.controlEraseName,
            directoryDescriptor: ingressControlAuthority.rootDescriptor) == nil else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        // Settle the existing no-replace publisher's temporary hard link before
        // opening a completed control file; this reads metadata only.
        observeIngressControlInventoryForTesting()
        try removeInterruptedPublications(directoryDescriptor: ingressControlAuthority.rootDescriptor)
        try ingressControlAuthority.verify(rootName: "ProtectedIngressReceiptsV1")
        return ingressControlAuthority.rootDescriptor
    }

    private func ingressControlFileExists(_ file: URL) throws -> Bool {
        guard file.deletingLastPathComponent() == (try protectedIngressReceiptDirectory()) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        return try regularFileInformationIfPresent(named: file.lastPathComponent,
            directoryDescriptor: ingressControlDescriptor()) != nil
    }

    private func readIngressControlFile(_ file: URL, maximumBytes: Int) throws -> Data {
        guard file.deletingLastPathComponent() == (try protectedIngressReceiptDirectory()) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let data = try readRegularFile(named: file.lastPathComponent,
            directoryDescriptor: ingressControlDescriptor(), maximumBytes: maximumBytes)
        try ProtectedFilePolicyV1.verify(.temporaryFile, at: file)
        _ = try protectedIngressReceiptDirectory()
        return data
    }

    private func protectedIngressScratchDirectory() throws -> URL {
        try verifyRoot()
        return rootURL
    }

    private func protectedIngressReceiptFile(operationID: UUID) throws -> URL {
        guard operationID != SettingsValidationV1.zeroUUID else {
            throw AppAccessContractFailureV1.invalidValue
        }
        return try protectedIngressReceiptDirectory().appendingPathComponent(
            "hygiene-" + operationID.uuidString.lowercased() + ".json",
            isDirectory: false
        )
    }

    private func protectedIngressPrepareFile(operationID: UUID) throws -> URL {
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
        let tombstone = Self.deletionTombstoneName(for: target.directoryName)
        let original = try directoryInformationIfPresent(named: target.directoryName)
        let deleting = try directoryInformationIfPresent(named: tombstone)
        if original == nil && deleting == nil { return }
        let name = deleting == nil ? target.directoryName : tombstone
        let descriptor = try openLeaseDirectory(name)
        let deferredClose_descriptor = originalCleanupDeferredClose(descriptor)
        defer { deferredClose_descriptor() }
        var pinned = stat()
        guard try originalCleanupFstat(descriptor, &pinned) == 0,
              UInt64(pinned.st_dev) == target.device, UInt64(pinned.st_ino) == target.inode else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try originalCleanupVerifyPolicy(.stagingDirectory, at: rootURL.appendingPathComponent(name))
        let actual = try ingressHygieneFileIdentities(name: name, descriptor: descriptor)
        if deleting == nil {
            let modified = Date(timeIntervalSince1970: TimeInterval(pinned.st_mtimespec.tv_sec)
                + TimeInterval(pinned.st_mtimespec.tv_nsec) / 1_000_000_000)
            guard modified == target.modifiedAt, actual == target.files else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        } else {
            guard actual.allSatisfy({ target.files.contains($0) }) else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        }
        try verifyLeaseDirectory(name, descriptor: descriptor)
    }

    private func removePreparedIngressTarget(_ target: C16IngressHygieneTargetV1) throws {
        let tombstone = Self.deletionTombstoneName(for: target.directoryName)
        let original = try directoryInformationIfPresent(named: target.directoryName)
        let deleting = try directoryInformationIfPresent(named: tombstone)
        if original == nil && deleting == nil { return }
        // A new original beside the prepared tombstone belongs to a later operation.
        let name = deleting == nil ? target.directoryName : tombstone
        let descriptor = try openLeaseDirectory(name)
        let deferredClose_descriptor = originalCleanupDeferredClose(descriptor)
        defer { deferredClose_descriptor() }
        guard try originalCleanupLock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        var pinned = stat()
        guard try originalCleanupFstat(descriptor, &pinned) == 0,
              UInt64(pinned.st_dev) == target.device, UInt64(pinned.st_ino) == target.inode else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try originalCleanupVerifyPolicy(.stagingDirectory, at: rootURL.appendingPathComponent(name))
        let actual = try ingressHygieneFileIdentities(name: name, descriptor: descriptor)
        if deleting == nil {
            let modified = Date(timeIntervalSince1970: TimeInterval(pinned.st_mtimespec.tv_sec)
                + TimeInterval(pinned.st_mtimespec.tv_nsec) / 1_000_000_000)
            guard modified == target.modifiedAt, actual == target.files else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            try verifyLeaseDirectory(name, descriptor: descriptor)
            guard try originalCleanupRename(authority.rootDescriptor, name, authority.rootDescriptor, tombstone) == 0,
                  try originalCleanupSync(authority.rootDescriptor) == 0 else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        } else {
            guard actual.allSatisfy({ target.files.contains($0) }) else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        }
        try verifyLeaseDirectory(tombstone, descriptor: descriptor)
        try deletePinnedDirectory(named: tombstone, descriptor: descriptor, expectedFiles: target.files)
    }

    private func readProtectedIngressPrepare(at file: URL) throws -> C16IngressHygienePrepareV1 {
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
        guard data.count <= 262_144,
              file.deletingLastPathComponent() == (try protectedIngressReceiptDirectory()) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try publishDurably(data, named: file.lastPathComponent,
            directoryDescriptor: ingressControlDescriptor(), directoryURL: file.deletingLastPathComponent(),
            finalURL: file, directoryAuthorityCheck: { _ = try self.protectedIngressReceiptDirectory() })
    }

    private func finalizeProtectedIngressPrepare(_ prepare: C16IngressHygienePrepareV1, at file: URL) throws {
        let finalized = try prepare.finalizing()
        let current = try readProtectedIngressPrepare(at: file)
        if current == finalized { return }
        guard current == prepare else { throw AppAccessContractFailureV1.effectMismatch }
        let staged = file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + ".finalizing")
        try writeProtectedIngressCanonical(try CompatibilityCanonicalV1.encode(finalized), to: staged)
        guard try readProtectedIngressPrepare(at: file) == prepare else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        let descriptor = try ingressControlDescriptor()
        guard try originalCleanupRename(descriptor, staged.lastPathComponent, descriptor, file.lastPathComponent) == 0,
              try originalCleanupSync(descriptor) == 0,
              try readProtectedIngressPrepare(at: file) == finalized else {
            throw AppAccessContractFailureV1.effectMismatch
        }
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
        try withProducerFilesystemLock { try pendingIngressPublications().map(\.intent) }
    }

    private func pendingIngressPublications() throws -> [C16IngressPublicationV1] {
        try validatedIngressSnapshot().pending
    }

    /// Reconstructs the complete ingress control state under the caller's
    /// filesystem lock. The classification is intentionally post-hygiene: a
    /// completed hygiene removal is terminal before a later stage/erase uses
    /// the result for admission.
    private func validatedIngressSnapshot(
        frozenErase: C16IngressEraseV1? = nil,
        applyingRecoveryEffects: Bool = true
    ) throws -> C16ValidatedIngressSnapshotV1 {
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
        let preparationIDs = Set(preparations.map { $0.intent.intentID })
        guard Set(frozenEraseTargets.keys).isSubset(of: preparationIDs),
              Set(frozenUnpublishedTargets.keys).isSubset(of: preparationIDs) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        var pending: [C16IngressPublicationV1] = []
        var unresolvedPreparations: [C16IngressPreparedStageV1] = []
        var preparedCount = 0
        for preparation in preparations {
            let id = preparation.intent.intentID
            let claim = try readIngressControl(C16IngressDirectoryClaimV1.self,
                at: ingressControlURL(id, ".claim.json"), inventory: &inventory)
            let published = try readIngressControl(C16IngressPublicationV1.self,
                at: ingressControlURL(id, ".published.json"), inventory: &inventory)
            let current = try readIngressControl(C16IngressPublicationV1.self,
                at: ingressControlURL(id, ".pending.json"), inventory: &inventory)
            let terminal = try readIngressControl(C16IngressRemovalV1.self,
                at: ingressControlURL(id, ".terminal.json"), inventory: &inventory)
            let frozenUnpublishedTarget = frozenUnpublishedTargets[id]
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
                          aborted.operationID == frozenErase?.operationID else {
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
                } else {
                    let descriptor = try validateIngressClaim(claim)
                    _ = originalCleanupCloseResult(descriptor)
                }
                unresolvedPreparations.append(preparation)
                continue // Claimed incomplete copy remains owned, but is not a pending intent.
            }
            try published.validate()
            guard published.claim == claim, published.intent == preparation.intent else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
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
                try settleIngressRemoval(terminal, applyingEffects: applyingRecoveryEffects)
                if applyingRecoveryEffects {
                    inventory.expectedNames.remove(try ingressControlName(id, ".pending.json"))
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
            if try adoptCompletedIngressHygieneRemoval(value, applyingEffects: applyingRecoveryEffects,
                                                      expectedRemoval: frozenRemoval) {
                if applyingRecoveryEffects {
                    guard inventory.expectedNames.insert(try ingressControlName(id, ".terminal.json")).inserted else {
                        throw AppAccessContractFailureV1.configurationUnknown
                    }
                    inventory.expectedNames.remove(try ingressControlName(id, ".pending.json"))
                }
                continue
            }
            try validateIngressPublication(value, hashPayload: false)
            if current == nil {
                // Exact publication is durable; only its pending pointer was interrupted.
                try validateIngressPublication(value, hashPayload: true)
                if applyingRecoveryEffects {
                    try writeProtectedIngressCanonical(try CompatibilityCanonicalV1.encode(value),
                        to: ingressControlURL(id, ".pending.json"))
                    guard inventory.expectedNames.insert(try ingressControlName(id, ".pending.json")).inserted else {
                        throw AppAccessContractFailureV1.configurationUnknown
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

    private func adoptCompletedIngressHygieneRemoval(
        _ value: C16IngressPublicationV1,
        applyingEffects: Bool = true,
        expectedRemoval: C16IngressRemovalV1? = nil
    ) throws -> Bool {
        let name = value.claim.preparation.lease.relativeDirectory
        guard clock() >= value.intent.expiresAt,
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
            if applyingEffects {
                try writeProtectedIngressCanonical(try CompatibilityCanonicalV1.encode(removal),
                    to: ingressControlURL(value.intent.intentID, ".terminal.json"))
            }
            try settleIngressRemoval(removal, applyingEffects: applyingEffects)
            return true
        }
        return false
    }

    func stageProtectedIngress(_ request: ProtectedIngressStageRequestV1, source: URL) throws -> PendingLockedExternalIntentV1 {
        try withProducerFilesystemLock {
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

    private func settleIngressRemoval(
        _ removal: C16IngressRemovalV1,
        applyingEffects: Bool = true
    ) throws {
        try removal.validate()
        let value = removal.expected
        try validateIngressPreparation(value.claim.preparation, intentID: value.intent.intentID)
        let pendingFile = try ingressControlURL(value.intent.intentID, ".pending.json")
        if let current = try readIngressControl(C16IngressPublicationV1.self, at: pendingFile), current != value {
            throw AppAccessContractFailureV1.effectMismatch
        }
        let originalName = value.claim.preparation.lease.relativeDirectory
        let tombstone = Self.deletionTombstoneName(for: originalName)
        let original = try directoryInformationIfPresent(named: originalName)
        let deleting = try directoryInformationIfPresent(named: tombstone)
        if original != nil || deleting != nil {
            let name = deleting == nil ? originalName : tombstone
            let descriptor = try openLeaseDirectory(name)
            let deferredClose_descriptor = originalCleanupDeferredClose(descriptor)
        defer { deferredClose_descriptor() }
            guard try originalCleanupLock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            var information = stat()
            guard try originalCleanupFstat(descriptor, &information) == 0,
                  UInt64(information.st_dev) == value.claim.device, UInt64(information.st_ino) == value.claim.inode else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            try originalCleanupVerifyPolicy(.stagingDirectory, at: rootURL.appendingPathComponent(name))
            let files = try ingressHygieneFileIdentities(name: name, descriptor: descriptor)
            let expectedFiles = [value.metadata, value.payload].sorted { $0.name < $1.name }
            guard deleting == nil ? files == expectedFiles : files.allSatisfy({ expectedFiles.contains($0) }) else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            if applyingEffects {
                if deleting == nil {
                    try verifyLeaseDirectory(name, descriptor: descriptor)
                    guard try originalCleanupRename(authority.rootDescriptor, name, authority.rootDescriptor, tombstone) == 0,
                          try originalCleanupSync(authority.rootDescriptor) == 0 else { throw AppAccessContractFailureV1.configurationUnknown }
                }
                try verifyLeaseDirectory(tombstone, descriptor: descriptor)
                try deletePinnedDirectory(named: tombstone, descriptor: descriptor, expectedFiles: expectedFiles)
            } else {
                try verifyLeaseDirectory(name, descriptor: descriptor)
            }
        }
        guard applyingEffects else { return }
        if active[value.intent.intentID] == value.claim.preparation.lease { active.removeValue(forKey: value.intent.intentID) }
        try ingressMutationFailureInjection.interruptIfTriggered(.afterRemovalEffect)
        if try ingressControlFileExists(pendingFile) {
            guard try readIngressControl(C16IngressPublicationV1.self, at: pendingFile) == value else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            let descriptor = try ingressControlDescriptor()
            guard try originalCleanupUnlink(descriptor, pendingFile.lastPathComponent, 0) == 0,
                  try originalCleanupSync(descriptor) == 0 else { throw AppAccessContractFailureV1.configurationUnknown }
        }
    }

    private func makeUnpublishedIngressEraseTarget(
        _ preparation: C16IngressPreparedStageV1
    ) throws -> C16IngressUnpublishedEraseTargetV1 {
        let id = preparation.intent.intentID
        try validateIngressPreparation(preparation, intentID: id)
        for suffix in [".published.json", ".pending.json", ".terminal.json", ".aborted.json"] {
            guard try !ingressControlFileExists(ingressControlURL(id, suffix)) else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
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
        let deferredClose_descriptor = originalCleanupDeferredClose(descriptor)
        defer { deferredClose_descriptor() }
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
        guard try originalCleanupFstat(descriptor, &information) == 0,
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

    private func validateAbortedIngress(
        _ aborted: C16IngressAbortedStageV1,
        preparation: C16IngressPreparedStageV1,
        claim: C16IngressDirectoryClaimV1?
    ) throws {
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

    private func removeUnpublishedIngress(
        _ target: C16IngressUnpublishedEraseTargetV1, operationID: UUID
    ) throws {
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
            return
        }
        if let directory = target.directory {
            try removePreparedIngressTarget(directory)
        } else {
            let name = preparation.lease.relativeDirectory
            guard try directoryInformationIfPresent(named: name) == nil,
                  try directoryInformationIfPresent(named: Self.deletionTombstoneName(for: name)) == nil else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        }
        try ingressMutationFailureInjection.interruptIfTriggered(.afterUnpublishedRemoval)
        try writeProtectedIngressCanonical(try CompatibilityCanonicalV1.encode(aborted), to: file)
        guard try readIngressControl(C16IngressAbortedStageV1.self, at: file) == aborted else {
            throw AppAccessContractFailureV1.effectMismatch
        }
    }

    func eraseProtectedIngress(operationID: UUID) throws {
        try withProducerFilesystemLock {
            guard operationID != SettingsValidationV1.zeroUUID else { throw AppAccessContractFailureV1.invalidValue }
            let directory = try protectedIngressReceiptDirectory()
            let file = directory.appendingPathComponent("erase-" + operationID.uuidString.lowercased() + ".prepare.json")
            let complete = directory.appendingPathComponent("erase-" + operationID.uuidString.lowercased() + ".complete.json")
            let erase: C16IngressEraseV1
            let resumedErase: C16IngressEraseV1?
            if let existing = try readIngressControl(C16IngressEraseV1.self, at: file) {
                try existing.validate()
                guard existing.operationID == operationID, existing.rootDevice == authority.rootDevice,
                      existing.rootInode == authority.rootInode else { throw AppAccessContractFailureV1.configurationUnknown }
                erase = existing
                resumedErase = existing
            } else {
                guard try !ingressControlFileExists(complete) else { throw AppAccessContractFailureV1.configurationUnknown }
                _ = try validatedIngressSnapshot(applyingRecoveryEffects: false)
                let entry = try validatedIngressSnapshot()
                let published = entry.pending
                let publishedIDs = Set(published.map { $0.intent.intentID })
                let unfinished = entry.unresolvedPreparations.filter {
                    !publishedIDs.contains($0.intent.intentID)
                }
                erase = .init(operationID: operationID, rootDevice: authority.rootDevice, rootInode: authority.rootInode,
                    targets: published, unpublishedTargets: try unfinished.map(makeUnpublishedIngressEraseTarget))
                try erase.validate()
                try writeProtectedIngressCanonical(try CompatibilityCanonicalV1.encode(erase), to: file)
                try ingressMutationFailureInjection.interruptIfTriggered(.afterErasePrepare)
                resumedErase = nil
            }
            if let recorded = try readIngressControl(C16IngressEraseV1.self, at: complete) {
                guard recorded == erase else { throw AppAccessContractFailureV1.effectMismatch }
                return
            }
            // Every incomplete erase must admit the whole root before the first
            // target effect. A resumed record is immutable, but unrelated
            // malformed control state must still fail before deletion.
            _ = try validatedIngressSnapshot(frozenErase: resumedErase, applyingRecoveryEffects: false)
            _ = try validatedIngressSnapshot(frozenErase: resumedErase)
            for target in erase.unpublishedTargets {
                try removeUnpublishedIngress(target, operationID: operationID)
            }
            for target in erase.targets {
                try removeFrozenIngressTarget(target)
            }
            // This is a distinct post-effect proof. It validates later intents
            // without adding them to the immutable erase target set.
            _ = try validatedIngressSnapshot()
            try writeProtectedIngressCanonical(try CompatibilityCanonicalV1.encode(erase), to: complete)
            guard try readIngressControl(C16IngressEraseV1.self, at: complete) == erase else {
                throw AppAccessContractFailureV1.effectMismatch
            }
        }
    }

    /// Settles one target from an already durable erase record. This helper is
    /// called only while eraseProtectedIngress holds filesystemLock after a
    /// complete root admission. It never supplies a cache to another operation.
    private func removeFrozenIngressTarget(_ target: C16IngressPublicationV1) throws {
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
            // A terminal replay can legitimately have no payload directory.
            // Settle it before any publication/payload validation.
            try settleIngressRemoval(terminal)
            return
        }
        guard try readIngressControl(C16IngressPublicationV1.self, at: pendingFile) == target else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        try validateIngressPublication(target, hashPayload: false)
        try writeProtectedIngressCanonical(try CompatibilityCanonicalV1.encode(removal), to: terminalFile)
        guard try readIngressControl(C16IngressRemovalV1.self, at: terminalFile) == removal else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        try ingressMutationFailureInjection.interruptIfTriggered(.afterRemovalPrepare)
        try settleIngressRemoval(removal)
    }

    private func ingressControlURL(_ intentID: UUID, _ suffix: String) throws -> URL {
        guard intentID != SettingsValidationV1.zeroUUID else { throw AppAccessContractFailureV1.invalidValue }
        return try protectedIngressReceiptDirectory().appendingPathComponent(
            try ingressControlName(intentID, suffix))
    }

    private func ingressControlName(_ intentID: UUID, _ suffix: String) throws -> String {
        guard intentID != SettingsValidationV1.zeroUUID,
              [".prepare.json", ".claim.json", ".published.json", ".pending.json",
               ".terminal.json", ".aborted.json"].contains(suffix) else {
            throw AppAccessContractFailureV1.invalidValue
        }
        return "ingress-" + intentID.uuidString.lowercased() + suffix
    }

    private func readIngressControl<Value: Codable>(_ type: Value.Type, at file: URL) throws -> Value? {
        guard try ingressControlFileExists(file) else { return nil }
        return try CompatibilityCanonicalV1.decode(type, from: readIngressControlFile(file, maximumBytes: 262_144))
    }

    private func beginIngressControlInventory() throws -> C16IngressControlInventoryV1 {
        let descriptor = try ingressControlDescriptor()
        observeIngressControlInventoryForTesting()
        let names = try directoryNames(descriptor)
        return .init(descriptor: descriptor, expectedNames: Set(names))
    }

    private func finishIngressControlInventory(
        _ inventory: inout C16IngressControlInventoryV1
    ) throws {
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
        guard file.deletingLastPathComponent() == (try protectedIngressReceiptDirectory()) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let name = file.lastPathComponent
        guard inventory.expectedNames.contains(name) else { return nil }
        let data = try readRegularFile(named: name, directoryDescriptor: inventory.descriptor,
            maximumBytes: 262_144)
        try ProtectedFilePolicyV1.verify(.temporaryFile, at: file)
        _ = try protectedIngressReceiptDirectory()
        return try CompatibilityCanonicalV1.decode(type, from: data)
    }

    private func observeIngressControlInventoryForTesting() {
        #if DEBUG
        ingressControlInventoryObserver()
        #endif
    }

    private func mutateBeforeIngressControlFinalInventoryForTesting() throws {
        #if DEBUG
        try beforeIngressControlFinalInventory()
        #endif
    }

    private func validateIngressPreparation(_ value: C16IngressPreparedStageV1, intentID: UUID) throws {
        try verifyRoot()
        try value.validate()
        guard value.intent.intentID == intentID, value.rootDevice == authority.rootDevice,
              value.rootInode == authority.rootInode else { throw AppAccessContractFailureV1.configurationUnknown }
    }

    private func ingressPreparations(
        inventory: inout C16IngressControlInventoryV1
    ) throws -> [C16IngressPreparedStageV1] {
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
        var inventory = try beginIngressControlInventory()
        let result = try ingressPreparations(inventory: &inventory)
        try finishIngressControlInventory(&inventory)
        return result
    }

    private func ingressControlIdentifier(_ name: String, prefix: String, suffixes: [String]) throws -> UUID {
        guard name.hasPrefix(prefix), let suffix = suffixes.first(where: { name.hasSuffix($0) }) else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        let raw = String(name.dropFirst(prefix.count).dropLast(suffix.count))
        guard let id = UUID(uuidString: raw), id.uuidString.lowercased() == raw,
              id != SettingsValidationV1.zeroUUID else { throw AppAccessContractFailureV1.configurationUnknown }
        return id
    }

    private func hasExistingIngressControl() throws -> Bool {
        try verifyRoot()
        var information = stat()
        if try originalCleanupFstatat(authority.operationsDescriptor, "ProtectedIngressReceiptsV1", &information, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT, ingressControlAuthority == nil else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            return false
        }
        guard (information.st_mode & S_IFMT) == S_IFDIR else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        _ = try protectedIngressReceiptDirectory()
        return true
    }

    private func resumeIngressErasesForScratchLifecycle() throws {
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
        let operationID = UUID()
        let erase = C16IngressEraseV1(operationID: operationID, rootDevice: authority.rootDevice,
            rootInode: authority.rootInode, targets: [], unpublishedTargets: [target])
        try erase.validate()
        let file = try protectedIngressReceiptDirectory().appendingPathComponent("erase-" + operationID.uuidString.lowercased() + ".prepare.json")
        try writeProtectedIngressCanonical(try CompatibilityCanonicalV1.encode(erase), to: file)
        try eraseProtectedIngress(operationID: operationID)
    }

    private func recoverUnpublishedIngressForScratchLifecycle() throws -> (retainedNames: Set<String>, expiredCount: Int, removedBytes: UInt64) {
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
    private func eraseScratchIngressControl(resumeOnly: Bool) throws {
        guard try hasExistingIngressControl() else { return }
        let directory = try protectedIngressReceiptDirectory()
        guard let pinned = ingressControlAuthority else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        let descriptor = pinned.rootDescriptor
        let markerPresent = try regularFileInformationIfPresent(named: Self.controlEraseName, directoryDescriptor: descriptor) != nil
        if resumeOnly && !markerPresent { return }
        if !markerPresent {
            try removeInterruptedPublications(directoryDescriptor: descriptor)
        }
        let maximumMarkerBytes = 32 * 1_024 * 1_024
        let markerURL = directory.appendingPathComponent(Self.controlEraseName)
        let marker: C16ScratchControlEraseV1
        if markerPresent {
            let data = try readRegularFile(named: Self.controlEraseName, directoryDescriptor: descriptor, maximumBytes: maximumMarkerBytes)
            try originalCleanupVerifyPolicy(.temporaryFile, at: markerURL)
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
            let files = try directoryNames(descriptor).map { name -> C16IngressHygieneFileIdentityV1 in
                try validateIngressControlSnapshotName(name)
                try originalCleanupVerifyPolicy(.temporaryFile, at: directory.appendingPathComponent(name))
                return try .init(name: name, information: regularFileInformation(named: name, directoryDescriptor: descriptor))
            }
            marker = .init(schemaVersion: 1, rootDevice: authority.rootDevice, rootInode: authority.rootInode,
                controlDevice: pinned.rootDevice, controlInode: pinned.rootInode, files: files)
            let data = try CompatibilityCanonicalV1.encode(marker)
            guard data.count <= maximumMarkerBytes else { throw AppAccessContractFailureV1.configurationUnknown }
            try publishDurably(data, named: Self.controlEraseName, directoryDescriptor: descriptor,
                directoryURL: directory, finalURL: markerURL, atomicExclusiveRename: true,
                directoryAuthorityCheck: { _ = try self.protectedIngressReceiptDirectory() })
            try ingressMutationFailureInjection.interruptIfTriggered(.afterScratchControlErasePrepare)
        }
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
            try originalCleanupVerifyPolicy(.temporaryFile, at: directory.appendingPathComponent(name))
        }
        for name in remaining {
            _ = try protectedIngressReceiptDirectory()
            let current = try C16IngressHygieneFileIdentityV1(name: name,
                information: regularFileInformation(named: name, directoryDescriptor: descriptor))
            guard expectedFiles[name] == current, try originalCleanupUnlink(descriptor, name, 0) == 0,
                  try originalCleanupSync(descriptor) == 0 else { throw AppAccessContractFailureV1.configurationUnknown }
            try ingressMutationFailureInjection.interruptIfTriggered(.afterScratchControlEraseFile)
        }
        _ = try protectedIngressReceiptDirectory()
        guard try directoryNames(descriptor) == [Self.controlEraseName],
              try readRegularFile(named: Self.controlEraseName, directoryDescriptor: descriptor, maximumBytes: maximumMarkerBytes)
                == CompatibilityCanonicalV1.encode(marker),
              try originalCleanupUnlink(descriptor, Self.controlEraseName, 0) == 0, try originalCleanupSync(descriptor) == 0 else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try pinned.verify(rootName: "ProtectedIngressReceiptsV1")
        guard try originalCleanupUnlink(authority.operationsDescriptor, "ProtectedIngressReceiptsV1", AT_REMOVEDIR) == 0,
              try originalCleanupSync(authority.operationsDescriptor) == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        ingressControlAuthority = nil
    }

    private func validateIngressClaim(_ claim: C16IngressDirectoryClaimV1) throws -> Int32 {
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
            guard try originalCleanupFstat(descriptor, &information) == 0,
                  UInt64(information.st_dev) == claim.device, UInt64(information.st_ino) == claim.inode else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            try originalCleanupVerifyPolicy(.stagingDirectory, at: rootURL.appendingPathComponent(name))
            try verifyLeaseDirectory(name, descriptor: descriptor)
            return descriptor
        } catch {
            _ = originalCleanupCloseResult(descriptor)
            throw error
        }
    }

    private func validateIngressPublication(_ value: C16IngressPublicationV1, hashPayload: Bool) throws {
        try value.validate()
        let descriptor = try validateIngressClaim(value.claim)
        let deferredClose_descriptor = originalCleanupDeferredClose(descriptor)
        defer { deferredClose_descriptor() }
        let name = value.claim.preparation.lease.relativeDirectory
        let files = try ingressHygieneFileIdentities(name: name, descriptor: descriptor)
        guard files == [value.metadata, value.payload].sorted(by: { $0.name < $1.name }) else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        if hashPayload {
            let payload = try originalCleanupOpenat(descriptor, value.payload.name, O_RDONLY | O_NOFOLLOW)
            guard payload >= 0 else { throw AppAccessContractFailureV1.configurationUnknown }
            let deferredClose_payload = originalCleanupDeferredClose(payload)
        defer { deferredClose_payload() }
            var information = stat()
            guard try originalCleanupFstat(payload, &information) == 0,
                  C16IngressHygieneFileIdentityV1(name: value.payload.name, information: information) == value.payload,
                  try opaqueSHA256(descriptor: payload, byteCount: value.intent.byteCount) == value.intent.sha256 else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            try verifyLeaseDirectory(name, descriptor: descriptor)
            guard try C16IngressHygieneFileIdentityV1(name: value.payload.name,
                information: regularFileInformation(named: value.payload.name, directoryDescriptor: descriptor)) == value.payload else {
                throw AppAccessContractFailureV1.effectMismatch
            }
        }
    }

    private func validateOpaqueSourceLink(_ source: URL, expected: stat) throws {
        var linked = stat()
        guard Darwin.lstat(source.path, &linked) == 0, (linked.st_mode & S_IFMT) == S_IFREG,
              linked.st_nlink == 1,
              C16IngressHygieneFileIdentityV1(name: "source", information: linked)
                == C16IngressHygieneFileIdentityV1(name: "source", information: expected) else {
            throw AppAccessContractFailureV1.effectMismatch
        }
    }

    private func opaqueSHA256(descriptor: Int32, byteCount: UInt64) throws -> String {
        try requireOriginalCleanupDescriptorAccess()
        guard byteCount > 0, byteCount <= PendingLockedExternalIntentV1.maximumByteCount else {
            throw AppAccessContractFailureV1.invalidValue
        }
        var before = stat()
        guard try originalCleanupFstat(descriptor, &before) == 0, (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1, before.st_size >= 0, UInt64(before.st_size) == byteCount else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        var hash = SHA256()
        var offset: UInt64 = 0
        while offset < byteCount {
            let count = Int(min(UInt64(1_048_576), byteCount - offset))
            var data = Data(count: count)
            let read = try data.withUnsafeMutableBytes { bytes in
                try originalCleanupObserve { Darwin.pread(descriptor, bytes.baseAddress!, count, off_t(offset)) }
            }
            guard read > 0 else { throw AppAccessContractFailureV1.effectMismatch }
            data.count = read
            hash.update(data: data)
            offset += UInt64(read)
        }
        var after = stat()
        guard try originalCleanupFstat(descriptor, &after) == 0, after.st_nlink == 1,
              C16IngressHygieneFileIdentityV1(name: "source", information: before)
                == C16IngressHygieneFileIdentityV1(name: "source", information: after) else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func publishOpaqueIngress(sourceDescriptor: Int32, preparation: C16IngressPreparedStageV1,
                                      directoryDescriptor: Int32) throws -> C16IngressHygieneFileIdentityV1 {
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
    /// One creation effect for an immutable-P-absent Notification root.
    /// Ordinary constructors and the existing-root policy permit cannot mint
    /// this receipt. All transient descriptors remain in the actual operation's
    /// retained checked owner; no cleanup is attempted after an uncertain cut.
    @MainActor
    static func createOriginalEraseNotificationAbsentRoot(
        applicationSupportURL: URL, support: Int32, operations: Int32,
        before: EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot,
        observer: EraseSchema2ColdAuxiliaryFirstObserverV1,
        retainedIO io: EraseAbortCheckedSnapshotIOV1,
        operation: EraseRouterOperationV1, store: EraseIntentStore,
        registry: GenerationLeaseRegistryV1,
        exclusion: StoreTemporalNormalizationExclusionV1,
        activity: GenerationTemporalActivityHandleV1,
        permit: OriginalEraseNotificationRootCreationPermitV1,
        reproveOutside: (String, Bool, String?) throws -> String,
        readCreatedPostimage: (String, String, String, String,
            ProtectedFileVerificationDispositionV1) throws
            -> EraseSchema2ColdAuxiliaryFirstObserverV1.Snapshot
    ) throws -> OriginalEraseNotificationRootPolicyReceiptV1 {
        let name = AppLockNotificationControlStoreV1.rootName
        let operationsName = OwnedStorageRootKindV1.operations.rawValue
        let rootURL = applicationSupportURL
            .appendingPathComponent(operationsName, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        func sameStable(_ a: String, _ b: String, fields: Int) -> Bool {
            let x = a.split(separator: "|", omittingEmptySubsequences: false)
            let y = b.split(separator: "|", omittingEmptySubsequences: false)
            return x.count == 11 && y.count == 11 &&
                Array(x.prefix(fields)) == Array(y.prefix(fields))
        }
        do {
            try permit.requireBound(operation: operation, store: store,
                registry: registry, exclusion: exclusion, activity: activity,
                observer: observer, before: before)
            try observer.requireOriginalNotificationCreationAdmission(before: before)
            guard case .present(let firstOperationsFact, _) = before.operations else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            let firstNames = Array(before.operationsChildren.keys).sorted()
            let createdNames = (firstNames + [name]).sorted()
            func requireParents(_ operationsFact: String, created: Bool) throws {
                try permit.requireHeld()
                var heldSupport = stat(), namedSupport = stat(),
                    heldOperations = stat(), namedOperations = stat()
                guard Darwin.fstat(support, &heldSupport) == 0,
                      Darwin.lstat(applicationSupportURL.path, &namedSupport) == 0,
                      Darwin.fstat(operations, &heldOperations) == 0,
                      Darwin.fstatat(support, operationsName, &namedOperations,
                        AT_SYMLINK_NOFOLLOW) == 0,
                      heldSupport.st_mode & S_IFMT == S_IFDIR,
                      heldOperations.st_mode & S_IFMT == S_IFDIR,
                      heldOperations.st_dev == heldSupport.st_dev,
                      originalEraseSourceFullFact(heldSupport) == before.supportFact,
                      originalEraseSourceFullFact(namedSupport) == before.supportFact,
                      originalEraseSourceFullFact(heldOperations) == operationsFact,
                      originalEraseSourceFullFact(namedOperations) == operationsFact,
                      sameStable(operationsFact, firstOperationsFact, fields: 5),
                      try io.names(in: operations) == (created ? createdNames : firstNames) else {
                    throw AppAccessContractFailureV1.notificationReconciliationRequired
                }
                if !created {
                    var missing = stat()
                    guard Darwin.fstatat(operations, name, &missing,
                        AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else {
                        throw AppAccessContractFailureV1.notificationReconciliationRequired
                    }
                }
            }
            try requireParents(firstOperationsFact, created: false)
            let outside = try reproveOutside(firstOperationsFact, false, nil)
            try requireParents(firstOperationsFact, created: false)
            guard try reproveOutside(firstOperationsFact, false, outside) == outside else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            try requireParents(firstOperationsFact, created: false)
            // The admission and owner are already retained before this first
            // effect. EEXIST is a refusal, never adoption of a replacement.
            guard Darwin.mkdirat(operations, name, 0o700) == 0 else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            var createdNamedRoot = stat()
            guard Darwin.fstatat(operations, name, &createdNamedRoot,
                    AT_SYMLINK_NOFOLLOW) == 0,
                  createdNamedRoot.st_mode & S_IFMT == S_IFDIR,
                  createdNamedRoot.st_mode & 0o7777 == 0o700,
                  createdNamedRoot.st_uid == Darwin.geteuid(),
                  createdNamedRoot.st_gid == Darwin.getegid() else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            var createdOperations = stat(), namedOperations = stat()
            guard Darwin.fstat(operations, &createdOperations) == 0,
                  Darwin.fstatat(support, operationsName, &namedOperations,
                    AT_SYMLINK_NOFOLLOW) == 0,
                  originalEraseSourceFullFact(createdOperations)
                    == originalEraseSourceFullFact(namedOperations),
                  sameStable(originalEraseSourceFullFact(createdOperations),
                    firstOperationsFact, fields: 5) else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            let operationsFact = originalEraseSourceFullFact(createdOperations)
            try requireParents(operationsFact, created: true)
            // The optional policy callback runs synchronously and never stores
            // this borrowed reproof. Keep its public parameter nonescaping,
            // and enforce that lifetime through the checked root close.
            let physical = try withoutActuallyEscaping(reproveOutside) { reproveOutside in
                return try io.withOriginalEraseMainActorOpen(parent: operations,
                    name: name, flags: O_RDONLY | O_DIRECTORY) { root
                    -> (String, String, String, ProtectedFileVerificationDispositionV1) in
                    var initial = stat(), named = stat()
                    guard Darwin.fstat(root, &initial) == 0,
                          Darwin.fstatat(operations, name, &named,
                            AT_SYMLINK_NOFOLLOW) == 0,
                          originalEraseSourceFullFact(initial) == originalEraseSourceFullFact(named),
                          originalEraseSourceFullFact(initial)
                            == originalEraseSourceFullFact(createdNamedRoot),
                          initial.st_mode & S_IFMT == S_IFDIR,
                          initial.st_mode & 0o7777 == 0o700,
                          initial.st_uid == Darwin.geteuid(),
                          initial.st_gid == Darwin.getegid(),
                          initial.st_dev == createdOperations.st_dev,
                          try io.names(in: root).isEmpty else {
                        throw AppAccessContractFailureV1.notificationReconciliationRequired
                    }
                    let initialFact = originalEraseSourceFullFact(initial)
                    var policyWindow = false
                    @MainActor func requireRoot() throws {
                        try requireParents(operationsFact, created: true)
                        guard try reproveOutside(operationsFact, true, outside) == outside else {
                            throw AppAccessContractFailureV1.notificationReconciliationRequired
                        }
                        var held = stat(), named = stat()
                        guard Darwin.fstat(root, &held) == 0,
                              Darwin.fstatat(operations, name, &named,
                                AT_SYMLINK_NOFOLLOW) == 0,
                              originalEraseSourceFullFact(held) == originalEraseSourceFullFact(named),
                              sameStable(originalEraseSourceFullFact(held), initialFact, fields: 9),
                              policyWindow || originalEraseSourceFullFact(held) == initialFact,
                              try io.names(in: root).isEmpty else {
                            throw AppAccessContractFailureV1.notificationReconciliationRequired
                        }
                    }
                    try requireRoot()
                    let disposition = try ProtectedFilePolicyV1
                        .applyAndVerifyEraseColdPrivateWithCheckedClose(
                            .stagingDirectory, at: rootURL,
                            retainUncertainDescriptor: {
                                io.retainUncertainDescriptor($0)
                                permit.poisonOnUncertainEffect()
                            }, authorityCheck: requireRoot,
                            beforeFirstEffect: {
                                try requireRoot()
                                policyWindow = true
                            })
                    try requireRoot()
                    guard Darwin.fsync(root) == 0,
                          Darwin.fsync(operations) == 0,
                          Darwin.fsync(support) == 0 else {
                        throw AppAccessContractFailureV1.notificationReconciliationRequired
                    }
                    try requireRoot()
                    var final = stat()
                    guard Darwin.fstat(root, &final) == 0 else {
                        throw AppAccessContractFailureV1.notificationReconciliationRequired
                    }
                    let fact = originalEraseSourceFullFact(final)
                    let digest = try io.postRetiredTree(parent: operations, name: name)
                    let stable = try io.postRetiredTree(parent: operations, name: name,
                        ignoringDirectoryMetadata: Set([""]))
                    var finalNamed = stat(), heldAfter = stat()
                    guard Darwin.fstat(root, &heldAfter) == 0,
                          Darwin.fstatat(operations, name, &finalNamed,
                            AT_SYMLINK_NOFOLLOW) == 0,
                          originalEraseSourceFullFact(heldAfter) == fact,
                          originalEraseSourceFullFact(finalNamed) == fact else {
                        throw AppAccessContractFailureV1.notificationReconciliationRequired
                    }
                    return (fact, digest, stable, disposition)
                }
            }
            // A failed first close prevents receipt issuance. Reopen twice and
            // observe policy without repair while binding every full fact.
            func requirePostClose() throws {
                try io.withOriginalEraseMainActorOpen(parent: operations,
                    name: name, flags: O_RDONLY | O_DIRECTORY) { root in
                    try requireParents(operationsFact, created: true)
                    guard try reproveOutside(operationsFact, true, outside) == outside else {
                        throw AppAccessContractFailureV1.notificationReconciliationRequired
                    }
                    func requireFull() throws {
                        var held = stat(), named = stat()
                        guard Darwin.fstat(root, &held) == 0,
                              Darwin.fstatat(operations, name, &named,
                                AT_SYMLINK_NOFOLLOW) == 0,
                              originalEraseSourceFullFact(held) == physical.0,
                              originalEraseSourceFullFact(named) == physical.0,
                              try io.names(in: root).isEmpty,
                              try io.postRetiredTree(parent: operations, name: name) == physical.1,
                              try io.postRetiredTree(parent: operations, name: name,
                                ignoringDirectoryMetadata: Set([""])) == physical.2 else {
                            throw AppAccessContractFailureV1.notificationReconciliationRequired
                        }
                    }
                    try requireFull()
                    let policy = try ProtectedFilePolicyV1.observeTemporalPolicyWithCheckedClose(
                        .stagingDirectory, at: rootURL, retainUncertainDescriptor: {
                            io.retainUncertainDescriptor($0)
                            permit.poisonOnUncertainEffect()
                        })
                    var held = stat()
                    guard Darwin.fstat(root, &held) == 0,
                          policy.device == UInt64(held.st_dev),
                          policy.inode == UInt64(held.st_ino),
                          policy.mode == UInt16(held.st_mode),
                          policy.linkCount == UInt64(held.st_nlink),
                          policy.isDirectory == true, policy.backupExcluded == true,
                          policy.state == .strictComplete ||
                            (physical.3 == .simulatorFileProtectionUnsupported &&
                             policy.state == .pendingSimulatorRequest) else {
                        throw AppAccessContractFailureV1.notificationReconciliationRequired
                    }
                    try requireFull()
                }
            }
            try io.requireSettled()
            try requirePostClose()
            let after = try readCreatedPostimage(operationsFact,
                physical.0, physical.1, physical.2, physical.3)
            try requirePostClose()
            guard try readCreatedPostimage(operationsFact,
                    physical.0, physical.1, physical.2, physical.3) == after,
                  try reproveOutside(operationsFact, true, outside) == outside else {
                throw AppAccessContractFailureV1.notificationReconciliationRequired
            }
            try requireParents(operationsFact, created: true)
            try permit.requireBound(operation: operation, store: store,
                registry: registry, exclusion: exclusion, activity: activity,
                observer: observer, before: before)
            try io.requireSettled()
            let creation = OriginalEraseNotificationRootCreationReceiptV1(
                operation: operation, store: store, registry: registry,
                exclusion: exclusion, activity: activity, observer: observer,
                before: before, after: after, outsideDigest: outside)
            return OriginalEraseNotificationRootPolicyReceiptV1(
                operation: operation, store: store, registry: registry,
                exclusion: exclusion, activity: activity,
                firstRootFact: physical.0, firstTreeDigest: physical.1,
                projectedRootFact: physical.0, projectedTreeDigest: physical.1,
                disposition: physical.3, didRequestCompleteProtection: false,
                creationReceipt: creation)
        } catch {
            permit.poisonOnUncertainEffect()
            throw error
        }
    }

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
        try withProducerFilesystemLock {
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
        try withProducerFilesystemLock {
            try writeScratchDataSynchronously(data, named: named, lease: lease)
        }
    }

    private func writeScratchDataSynchronously(
        _ data: Data,
        named: String,
        lease: ScratchDataLeaseV1
    ) throws -> URL {
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
        try withProducerFilesystemLock {
            try recoverScratchLeasesSynchronously()
        }
    }

    private func recoverScratchLeasesSynchronously() throws -> ScratchDataLeaseRecoverySummaryV1 {
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
        try withProducerFilesystemLock {
            try resetScratchDataSynchronously()
        }
    }

    private func resetScratchDataSynchronously() throws {
        try verifyRoot()
        try eraseScratchIngressControl(resumeOnly: true)
        if try hasExistingIngressControl() {
            try resumePreparedScratchHygiene()
            try resumeIngressErasesForScratchLifecycle()
            try eraseProtectedIngress(operationID: UUID())
        }
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
        try withProducerFilesystemLock {
            try eraseScratchDataSynchronously()
        }
    }

    private func eraseScratchDataSynchronously() throws {
        try resetScratchDataSynchronously()
        try eraseScratchIngressControl(resumeOnly: false)
        try verifyRoot()
        guard try originalCleanupUnlink(
            authority.operationsDescriptor,
            Self.rootName,
            AT_REMOVEDIR
        ) == 0,
        try originalCleanupSync(authority.operationsDescriptor) == 0 else {
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
        var total: UInt64 = 0
        for name in try directoryNames(directoryDescriptor) {
            let information = try regularFileInformation(
                named: name,
                directoryDescriptor: directoryDescriptor
            )
            try originalCleanupVerifyPolicy(
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
                    if originalCleanupCloseResult(descriptor) == 0 {
                        ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
                    }
                } else { _ = originalCleanupCloseResult(descriptor) }
            }
        }
        guard try originalCleanupLock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
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
        guard try originalCleanupFstat(descriptor, &pinned) == 0,
              try originalCleanupRename(
                  authority.rootDescriptor,
                  name,
                  authority.rootDescriptor,
                  tombstone
              ) == 0,
              try originalCleanupSync(authority.rootDescriptor) == 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        var oldEntry = stat()
        guard try originalCleanupFstatat(
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
        guard try originalCleanupFstatat(
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
            guard originalCleanupCloseResult(descriptor) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
        }
    }

    private func removeDeletionTombstone(
        named name: String, expectedLease: ScratchDataLeaseV1? = nil
    ) throws {
        guard Self.isDeletionTombstone(name) else {
            throw ScratchDataLeaseStoreFailureV1.invalidLease
        }
        try requireNoUnfinishedHygieneTarget(named: String(name.dropFirst(Self.deletionPrefix.count)))
        let descriptor = try openLeaseDirectory(name)
        let deferredClose_descriptor = originalCleanupDeferredClose(descriptor)
        defer { deferredClose_descriptor() }
        guard try originalCleanupLock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
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
        try requireOriginalCleanupDescriptorAccess()
        if originalCleanupLifetime == .active {
            guard Thread.isMainThread, let attempt = originalCleanupAttempt else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            try MainActor.assumeIsolated {
                guard Self.isDeletionTombstone(name) else { throw ScratchDataLeaseStoreFailureV1.invalidLease }
                let current = Self.rootName + "/" + name
                guard let original = attempt.directoryMappings[current],
                      let source = attempt.directorySources[original] else { throw ScratchDataLeaseStoreFailureV1.invalidLease }
                try verifyLeaseDirectory(name, descriptor: descriptor)
                switch source.metadata {
                case .ownedOrphan:
                    guard try regularFileInformationIfPresent(named: Self.metadataName, directoryDescriptor: descriptor) == nil else {
                        throw ScratchDataLeaseStoreFailureV1.invalidLease
                    }
                case .validatedLease(let bytes, _, let sha):
                    guard try CompatibilityCanonicalV1.sha256(bytes) == sha,
                          try readRegularFile(named: Self.metadataName, directoryDescriptor: descriptor, maximumBytes: 65_536) == bytes else {
                        throw ScratchDataLeaseStoreFailureV1.invalidLease
                    }
                    try verifySourceReadPolicy(.temporaryFile, at: rootURL.appendingPathComponent(name).appendingPathComponent(Self.metadataName))
                }
                try verifyLeaseDirectory(name, descriptor: descriptor); try attempt.requireActive()
            }
            return
        }
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
        try originalCleanupVerifyPolicy(.temporaryFile, at: metadataURL)
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
        named name: String,
        descriptor: Int32,
        expectedFiles: [C16IngressHygieneFileIdentityV1]? = nil,
        exclusiveNoRepair: Bool = false
    ) throws {
        guard try originalCleanupLock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        try verifyLeaseDirectory(name, descriptor: descriptor)
        if expectedFiles == nil && !exclusiveNoRepair {
            try removeInterruptedPublications(directoryDescriptor: descriptor)
        }
        let names = try directoryNames(descriptor)
        if let expectedFiles {
            if exclusiveNoRepair {
                try requireExclusiveExpectedChildren(
                    expectedFiles, descriptor: descriptor)
            }
            let survivors = try ingressHygieneFileIdentities(name: name, descriptor: descriptor)
            guard survivors.map(\.name) == names,
                  survivors.allSatisfy({ expectedFiles.contains($0) }) else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        }
        var exclusiveRemaining = Set(expectedFiles?.map(\.name) ?? [])
        for child in names {
            if exclusiveNoRepair {
                guard Set(try directoryNames(descriptor)) == exclusiveRemaining else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
            }
            let information = try regularFileInformation(
                named: child,
                directoryDescriptor: descriptor
            )
            if let expectedFiles {
                let current = C16IngressHygieneFileIdentityV1(name: child, information: information)
                guard expectedFiles.contains(current) else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
                try verifySourceReadPolicy(.temporaryFile,
                    at: rootURL.appendingPathComponent(name).appendingPathComponent(child))
                try verifyLeaseDirectory(name, descriptor: descriptor)
                guard try C16IngressHygieneFileIdentityV1(name: child,
                    information: regularFileInformation(named: child, directoryDescriptor: descriptor)) == current else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
            }
            guard try originalCleanupUnlink(descriptor, child, 0) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            if exclusiveNoRepair { exclusiveRemaining.remove(child) }
            if expectedFiles != nil {
                guard try originalCleanupSync(descriptor) == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                try ingressMutationFailureInjection.interruptIfTriggered(.afterPreparedDirectoryFileDeletion)
            }
        }
        if exclusiveNoRepair {
            guard exclusiveRemaining.isEmpty,
                  try directoryNames(descriptor).isEmpty else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        }
        guard try originalCleanupSync(descriptor) == 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        try verifyLeaseDirectory(name, descriptor: descriptor)
        guard try originalCleanupUnlink(authority.rootDescriptor, name, AT_REMOVEDIR) == 0,
              try originalCleanupSync(authority.rootDescriptor) == 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        var absent = stat()
        guard try originalCleanupFstatat(
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
        if try originalCleanupFstatat(
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
        guard try originalCleanupFstatat(
            authority.rootDescriptor,
            name,
            &before,
            AT_SYMLINK_NOFOLLOW
        ) == 0,
        (before.st_mode & S_IFMT) == S_IFDIR,
        UInt64(before.st_dev) == authority.rootDevice else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        let descriptor = try originalCleanupOpenat(
            authority.rootDescriptor,
            name,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        var pinned = stat()
        guard try originalCleanupFstat(descriptor, &pinned) == 0,
              (pinned.st_mode & S_IFMT) == S_IFDIR,
              pinned.st_dev == before.st_dev,
              pinned.st_ino == before.st_ino else {
            if exclusiveNoRepairRead {
                let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(descriptor)
                if originalCleanupCloseResult(descriptor) == 0 {
                    ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
                }
            } else { _ = originalCleanupCloseResult(descriptor) }
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
        guard try originalCleanupFstatat(
            authority.rootDescriptor,
            name,
            &linked,
            AT_SYMLINK_NOFOLLOW
        ) == 0,
        try originalCleanupFstat(descriptor, &pinned) == 0,
        (linked.st_mode & S_IFMT) == S_IFDIR,
        linked.st_dev == pinned.st_dev,
        linked.st_ino == pinned.st_ino else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
    }

    private func directoryNames(_ descriptor: Int32) throws -> [String] {
        try requireOriginalCleanupDescriptorAccess()
        if originalCleanupLifetime == .active {
            guard Thread.isMainThread else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            return try MainActor.assumeIsolated { try originalCleanupDirectoryNames(descriptor) }
        }
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
        try requireOriginalCleanupDescriptorAccess()
        var information = stat()
        if try originalCleanupFstatat(
            directoryDescriptor,
            name,
            &information,
            AT_SYMLINK_NOFOLLOW
        ) != 0 {
            guard errno == ENOENT else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            if originalCleanupLifetime == .active {
                guard Thread.isMainThread, let attempt = originalCleanupAttempt else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                try MainActor.assumeIsolated {
                    let path = try attempt.childPath(parent: directoryDescriptor, name: name)
                    guard try originalCleanupImageNodeIfPresent(path) == nil else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                }
            }
            return nil
        }
        guard (information.st_mode & S_IFMT) == S_IFREG,
              try originalCleanupPermitsRegularLinkCount(information, parent: directoryDescriptor, name: name),
              information.st_size >= 0,
              UInt64(information.st_dev) == authority.rootDevice else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        if originalCleanupLifetime == .active {
            guard Thread.isMainThread, let attempt = originalCleanupAttempt else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            try MainActor.assumeIsolated {
                let path = try attempt.childPath(parent: directoryDescriptor, name: name)
                guard try originalCleanupImageNode(path).fullFact == Self.originalEraseSourceFullFact(information) else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
            }
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
        try requireOriginalCleanupDescriptorAccess()
        if originalCleanupLifetime == .active {
            guard Thread.isMainThread else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            return try MainActor.assumeIsolated {
                try originalCleanupReadRegularFile(named: name, directoryDescriptor: directoryDescriptor, maximumBytes: maximumBytes)
            }
        }
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
        try requireOriginalCleanupDescriptorAccess()
        if originalCleanupLifetime == .active {
            guard Thread.isMainThread else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            try MainActor.assumeIsolated {
                try publishOriginalCleanupDurably(data, named: name,
                    directoryDescriptor: directoryDescriptor, directoryURL: directoryURL,
                    finalURL: finalURL, leaseName: leaseName,
                    atomicExclusiveRename: atomicExclusiveRename,
                    directoryAuthorityCheck: directoryAuthorityCheck)
            }
            return
        }
        try directoryAuthorityCheck?()
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
        var descriptorCloseAttempted = false
        defer {
            if !descriptorCloseAttempted {
                if exclusiveNoRepairRead {
                    let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(descriptor)
                    if Darwin.close(descriptor) == 0 {
                        ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
                    }
                } else { _ = Darwin.close(descriptor) }
            }
            if !published {
                _ = Darwin.unlinkat(directoryDescriptor, temporaryName, 0)
            }
        }
        func closeExclusivePublicationDescriptor() throws {
            guard exclusiveNoRepairRead else { return }
            descriptorCloseAttempted = true
            let attempt = ScratchUncertainCloseQuarantineV1.shared.begin(descriptor)
            guard Darwin.close(descriptor) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
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
        try applySourceReadPolicy(
            .temporaryFile,
            at: temporaryURL,
            authorityCheck: {
                try directoryAuthorityCheck?()
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
        // The Erase marker must never expose a two-link crash state: its
        // recovery cannot distinguish a later link from a publication link.
        // Other existing callers retain their original linkat publication.
        let publicationResult: Int32
        if atomicExclusiveRename {
            guard name == Self.controlEraseName, leaseName == nil else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            publicationResult = Darwin.renameatx_np(directoryDescriptor, temporaryName,
                directoryDescriptor, name, UInt32(RENAME_EXCL))
        } else {
            publicationResult = Darwin.linkat(directoryDescriptor, temporaryName, directoryDescriptor, name, 0)
        }
        if publicationResult != 0 {
            if errno == EEXIST {
                // A newly allocated exclusive lease has no prior final file.
                // Matching bytes cannot turn an unowned collision into proof.
                if exclusiveNoRepairRead {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
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
                try directoryAuthorityCheck?()
                try closeExclusivePublicationDescriptor()
                return
            }
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        if !atomicExclusiveRename && Darwin.unlinkat(directoryDescriptor, temporaryName, 0) != 0 {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        guard Darwin.fsync(directoryDescriptor) == 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        published = true
        if atomicExclusiveRename {
            try ingressMutationFailureInjection.interruptIfTriggered(.afterScratchControlErasePublication)
        }
        try directoryAuthorityCheck?()
        _ = try regularFileInformation(
            named: name,
            directoryDescriptor: directoryDescriptor
        )
        try verifySourceReadPolicy(.temporaryFile, at: finalURL)
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
        try directoryAuthorityCheck?()
        try closeExclusivePublicationDescriptor()
    }

    @MainActor private func publishOriginalCleanupDurably(_ data: Data,
        named name: String, directoryDescriptor: Int32, directoryURL: URL,
        finalURL: URL, leaseName: String?, atomicExclusiveRename: Bool,
        directoryAuthorityCheck: (() throws -> Void)?) throws {
        guard let attempt = originalCleanupAttempt,
              leaseName == nil, let control = ingressControlAuthority,
              control.rootDescriptor == directoryDescriptor,
              directoryURL == rootURL.deletingLastPathComponent().appendingPathComponent("ProtectedIngressReceiptsV1", isDirectory: true),
              finalURL == directoryURL.appendingPathComponent(name),
              OperationalDiagnosticsBoundsV1.validRelativeName(name),
              !atomicExclusiveRename || name == Self.controlEraseName else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        try directoryAuthorityCheck?()
        let temporaryName = ".partial-" + UUID().uuidString.lowercased()
        let temporaryPath = try attempt.childPath(parent: directoryDescriptor, name: temporaryName)
        let finalPath = try attempt.childPath(parent: directoryDescriptor, name: name)
        let sha = try CompatibilityCanonicalV1.sha256(data)
        let opened = try attempt.perform(.createTemporary(path: temporaryPath, finalPath: finalPath,
            bytes: data, sha256: sha, mode: 0o600, exclusiveFinalRename: atomicExclusiveRename)) {
            guard let intent = attempt.activeIntent else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            let fd = Darwin.openat(directoryDescriptor, temporaryName,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
            let actualErrno = errno
            if fd >= 0 { try attempt.retainDescriptor(fd, path: temporaryPath, role: .publication(requestID: intent.requestID)) }
            errno = actualErrno
            return Int64(fd)
        }
        guard opened >= 0, let resource = attempt.resources[Int32(opened)] else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        let descriptor = Int32(opened)
        do {
            var offset = 0
            while offset < data.count {
                let requested = data.count - offset
                let count = try attempt.perform(.writeTemporary(path: temporaryPath,
                    offset: offset, requestedByteCount: requested)) {
                    data.withUnsafeBytes { raw in
                        Int64(Darwin.write(descriptor, raw.baseAddress!.advanced(by: offset), requested))
                    }
                }
                guard count > 0, count <= Int64(requested) else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                offset += Int(count)
            }
            guard try originalCleanupSync(descriptor) == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            try applySourceReadPolicy(.temporaryFile, at: directoryURL.appendingPathComponent(temporaryName),
                authorityCheck: { try directoryAuthorityCheck?(); try self.verifyRoot() })
            let result: Int64
            if atomicExclusiveRename {
                result = try attempt.perform(.renamePublication(sourcePath: temporaryPath, finalPath: finalPath, exclusive: true)) {
                    Int64(Darwin.renameatx_np(directoryDescriptor, temporaryName,
                        directoryDescriptor, name, UInt32(RENAME_EXCL)))
                }
            } else {
                result = try attempt.perform(.linkPublication(temporaryPath: temporaryPath, finalPath: finalPath)) {
                    Int64(Darwin.linkat(directoryDescriptor, temporaryName, directoryDescriptor, name, 0))
                }
            }
            // Matching bytes are never a collision/adoption capability here.
            guard result == 0 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            if atomicExclusiveRename { resource.path = finalPath }
            else { guard try originalCleanupUnlink(directoryDescriptor, temporaryName, 0) == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot } }
            guard try originalCleanupSync(directoryDescriptor) == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            try directoryAuthorityCheck?()
            _ = try regularFileInformation(named: name, directoryDescriptor: directoryDescriptor)
            try verifySourceReadPolicy(.temporaryFile, at: finalURL)
            guard try readRegularFile(named: name, directoryDescriptor: directoryDescriptor, maximumBytes: data.count) == data else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            try directoryAuthorityCheck?()
            try attempt.closeResource(resource, terminalCleanup: false)
        } catch {
            let failure = error
            // Retain the exact producer request/image/temp on uncertainty.
            // There is no unproved defer-unlink or second close attempt.
            attempt.poison(); try? attempt.closeResource(resource, terminalCleanup: true)
            throw failure
        }
    }

    private func removeInterruptedPublications(
        directoryDescriptor: Int32
    ) throws {
        try requireOriginalCleanupDescriptorAccess()
        var removed = false
        for name in try directoryNames(directoryDescriptor)
        where name.hasPrefix(".partial-") {
            let suffix = String(name.dropFirst(".partial-".count))
            guard UUID(uuidString: suffix)?.uuidString.lowercased() == suffix else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            var information = stat()
            if originalCleanupLifetime == .active {
                guard try originalCleanupFstatat(directoryDescriptor, name, &information, AT_SYMLINK_NOFOLLOW) == 0,
                      try originalCleanupPermitsRegularLinkCount(information, parent: directoryDescriptor, name: name) else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                guard Thread.isMainThread, let attempt = originalCleanupAttempt else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                let path = try MainActor.assumeIsolated { try attempt.childPath(parent: directoryDescriptor, name: name) }
                try verifySourceReadPolicy(.temporaryFile, at: rootURL.deletingLastPathComponent().appendingPathComponent(path))
            }
            guard try originalCleanupFstatat(
                directoryDescriptor,
                name,
                &information,
                AT_SYMLINK_NOFOLLOW
            ) == 0,
            (information.st_mode & S_IFMT) == S_IFREG,
            information.st_nlink == 1 || information.st_nlink == 2,
            UInt64(information.st_dev) == authority.rootDevice,
            try originalCleanupUnlink(directoryDescriptor, name, 0) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            removed = true
        }
        if removed, try originalCleanupSync(directoryDescriptor) != 0 {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
    }

    private func verifyRoot() throws {
        try requireOriginalCleanupDescriptorAccess()
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
        try withProducerFilesystemLock {
            try makeEncryptedPortableEnvelopeStreamingScratchSynchronously(named: named, lease: lease, maximumByteCount: maximumByteCount)
        }
    }

    private func makeEncryptedPortableEnvelopeStreamingScratchSynchronously(
        named: String,
        lease: ScratchDataLeaseV1,
        maximumByteCount: UInt64
    ) throws -> any EncryptedPortableEnvelopeTerminalScratchV1 {
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

import Darwin
import CryptoKit
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

private struct C16IngressHygieneFileIdentityV1: Codable, Equatable {
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

/// Startup before authentication may only remove confidently owned expired
/// scratch by metadata. It must never decode, traverse, index, or render
/// payloads; authenticated lifecycle recovery owns every richer operation.
enum WorkspaceExperiencePreAuthenticationScratchPolicyV1 {
    static let permitsBlindMetadataExpiryPurge = true
    static let permitsPayloadDecode = false
    static let permitsPayloadTraversal = false
    static let permitsPayloadIndexing = false
}

private final class PinnedScratchRootV1: @unchecked Sendable {
    private let operationsURL: URL
    let operationsDescriptor: Int32
    let rootDescriptor: Int32
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

/// Sole process adapter for the shared, noncanonical scratch root. Every byte
/// remains under `FieldEvidenceOperations`, so the closed owned-storage ledger
/// accounts for it while purpose-separated leases prevent support export from
/// reading capture/import/source scratch.
/// Mutable lease state and filesystem transactions are confined to this lock.
/// Async protocol entry points never suspend while holding it.
final class ScratchDataLeaseStoreV1: ScratchDataLeasePortV1, @unchecked Sendable {
    private static let filesystemLock = NSRecursiveLock()
    private var lock: NSRecursiveLock { Self.filesystemLock }
    private let ingressHygieneFailureInjection: C16IngressHygieneFailureInjectionV1
    private let ingressMutationFailureInjection: C16IngressMutationFailureInjectionV1
    typealias Clock = @Sendable () -> Date

    private static let rootName = "ScratchDataV1"
    private static let metadataName = "lease.json"
    private static let deletionPrefix = ".deleting-"
    private static let controlEraseName = "scratch-erase.json"

    private let rootURL: URL
    private let clock: Clock
    private let storagePreflight: StoragePreflightService
    private let authority: PinnedScratchRootV1
    private var active: [UUID: ScratchDataLeaseV1] = [:]
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
        return try lock.withLock {
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
        return try lock.withLock {
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
        try lock.withLock {
            let file = try protectedIngressReceiptFile(operationID: value.operationID)
            try writeProtectedIngressCanonical(data, to: file)
        }
        guard try readProtectedIngressHygieneReceipt(operationID: value.operationID) == value else {
            throw AppAccessContractFailureV1.effectMismatch
        }
    }

    private func protectedIngressReceiptDirectory() throws -> URL {
        try verifyRoot()
        let name = "ProtectedIngressReceiptsV1"
        let directory = rootURL.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
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
            try ProtectedFilePolicyV1.verify(.temporaryFile,
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

    private func removePreparedIngressTarget(_ target: C16IngressHygieneTargetV1) throws {
        let tombstone = Self.deletionTombstoneName(for: target.directoryName)
        let original = try directoryInformationIfPresent(named: target.directoryName)
        let deleting = try directoryInformationIfPresent(named: tombstone)
        if original == nil && deleting == nil { return }
        // A new original beside the prepared tombstone belongs to a later operation.
        let name = deleting == nil ? target.directoryName : tombstone
        let descriptor = try openLeaseDirectory(name)
        defer { _ = Darwin.close(descriptor) }
        var pinned = stat()
        guard Darwin.fstat(descriptor, &pinned) == 0,
              UInt64(pinned.st_dev) == target.device, UInt64(pinned.st_ino) == target.inode else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try ProtectedFilePolicyV1.verify(.stagingDirectory, at: rootURL.appendingPathComponent(name))
        let actual = try ingressHygieneFileIdentities(name: name, descriptor: descriptor)
        if deleting == nil {
            let modified = Date(timeIntervalSince1970: TimeInterval(pinned.st_mtimespec.tv_sec)
                + TimeInterval(pinned.st_mtimespec.tv_nsec) / 1_000_000_000)
            guard modified == target.modifiedAt, actual == target.files else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            try verifyLeaseDirectory(name, descriptor: descriptor)
            guard Darwin.renameat(authority.rootDescriptor, name, authority.rootDescriptor, tombstone) == 0,
                  Darwin.fsync(authority.rootDescriptor) == 0 else {
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
        guard Darwin.renameat(descriptor, staged.lastPathComponent, descriptor, file.lastPathComponent) == 0,
              Darwin.fsync(descriptor) == 0,
              try readProtectedIngressPrepare(at: file) == finalized else {
            throw AppAccessContractFailureV1.effectMismatch
        }
    }

    func pendingProtectedIngress() throws -> [PendingLockedExternalIntentV1] {
        try Self.filesystemLock.withLock { try pendingIngressPublications().map(\.intent) }
    }

    private func pendingIngressPublications() throws -> [C16IngressPublicationV1] {
        var pending: [C16IngressPublicationV1] = []
        var preparedCount = 0
        for preparation in try ingressPreparations() {
            let id = preparation.intent.intentID
            let claim = try readIngressControl(C16IngressDirectoryClaimV1.self, at: ingressControlURL(id, ".claim.json"))
            let published = try readIngressControl(C16IngressPublicationV1.self, at: ingressControlURL(id, ".published.json"))
            let current = try readIngressControl(C16IngressPublicationV1.self, at: ingressControlURL(id, ".pending.json"))
            let terminal = try readIngressControl(C16IngressRemovalV1.self, at: ingressControlURL(id, ".terminal.json"))
            if let aborted = try readIngressControl(C16IngressAbortedStageV1.self, at: ingressControlURL(id, ".aborted.json")) {
                guard published == nil, current == nil, terminal == nil else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
                try validateAbortedIngress(aborted, preparation: preparation, claim: claim)
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
                continue // Prepared only: no file effect was published.
            }
            guard claim.preparation == preparation, claim.device == authority.rootDevice else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            guard let published else {
                guard current == nil, terminal == nil else { throw AppAccessContractFailureV1.configurationUnknown }
                let descriptor = try validateIngressClaim(claim)
                _ = Darwin.close(descriptor)
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
                try settleIngressRemoval(terminal)
                continue
            }
            let value = current ?? published
            guard try published.replacingIntent(value.intent) == value else { throw AppAccessContractFailureV1.configurationUnknown }
            if try adoptCompletedIngressHygieneRemoval(value) { continue }
            try validateIngressPublication(value, hashPayload: false)
            if current == nil {
                // Exact publication is durable; only its pending pointer was interrupted.
                try validateIngressPublication(value, hashPayload: true)
                try writeProtectedIngressCanonical(try CompatibilityCanonicalV1.encode(value),
                    to: ingressControlURL(id, ".pending.json"))
            }
            pending.append(value)
        }
        return pending.sorted { $0.intent.intentID.uuidString < $1.intent.intentID.uuidString }
    }

    private func adoptCompletedIngressHygieneRemoval(_ value: C16IngressPublicationV1) throws -> Bool {
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
            try writeProtectedIngressCanonical(try CompatibilityCanonicalV1.encode(removal),
                to: ingressControlURL(value.intent.intentID, ".terminal.json"))
            try settleIngressRemoval(removal)
            return true
        }
        return false
    }

    func stageProtectedIngress(_ request: ProtectedIngressStageRequestV1, source: URL) throws -> PendingLockedExternalIntentV1 {
        try Self.filesystemLock.withLock {
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
            let pending = try pendingIngressPublications()
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
                let unresolved = try ingressPreparations().filter {
                    try !ingressControlFileExists(ingressControlURL($0.intent.intentID, ".terminal.json"))
                        && !ingressControlFileExists(ingressControlURL($0.intent.intentID, ".aborted.json"))
                }
                guard unresolved.count < ProtectedIngressCoordinatorV1.maximumPendingIntentCount else {
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
        try Self.filesystemLock.withLock {
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
        try Self.filesystemLock.withLock {
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

    private func settleIngressRemoval(_ removal: C16IngressRemovalV1) throws {
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
            defer { _ = Darwin.close(descriptor) }
            var information = stat()
            guard Darwin.fstat(descriptor, &information) == 0,
                  UInt64(information.st_dev) == value.claim.device, UInt64(information.st_ino) == value.claim.inode else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            try ProtectedFilePolicyV1.verify(.stagingDirectory, at: rootURL.appendingPathComponent(name))
            let files = try ingressHygieneFileIdentities(name: name, descriptor: descriptor)
            let expectedFiles = [value.metadata, value.payload].sorted { $0.name < $1.name }
            guard deleting == nil ? files == expectedFiles : files.allSatisfy({ expectedFiles.contains($0) }) else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            if deleting == nil {
                try verifyLeaseDirectory(name, descriptor: descriptor)
                guard Darwin.renameat(authority.rootDescriptor, name, authority.rootDescriptor, tombstone) == 0,
                      Darwin.fsync(authority.rootDescriptor) == 0 else { throw AppAccessContractFailureV1.configurationUnknown }
            }
            try verifyLeaseDirectory(tombstone, descriptor: descriptor)
            try deletePinnedDirectory(named: tombstone, descriptor: descriptor, expectedFiles: expectedFiles)
        }
        if active[value.intent.intentID] == value.claim.preparation.lease { active.removeValue(forKey: value.intent.intentID) }
        try ingressMutationFailureInjection.interruptIfTriggered(.afterRemovalEffect)
        if try ingressControlFileExists(pendingFile) {
            guard try readIngressControl(C16IngressPublicationV1.self, at: pendingFile) == value else {
                throw AppAccessContractFailureV1.effectMismatch
            }
            let descriptor = try ingressControlDescriptor()
            guard Darwin.unlinkat(descriptor, pendingFile.lastPathComponent, 0) == 0,
                  Darwin.fsync(descriptor) == 0 else { throw AppAccessContractFailureV1.configurationUnknown }
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
        defer { _ = Darwin.close(descriptor) }
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
        try Self.filesystemLock.withLock {
            guard operationID != SettingsValidationV1.zeroUUID else { throw AppAccessContractFailureV1.invalidValue }
            let directory = try protectedIngressReceiptDirectory()
            let file = directory.appendingPathComponent("erase-" + operationID.uuidString.lowercased() + ".prepare.json")
            let complete = directory.appendingPathComponent("erase-" + operationID.uuidString.lowercased() + ".complete.json")
            let erase: C16IngressEraseV1
            if let existing = try readIngressControl(C16IngressEraseV1.self, at: file) {
                try existing.validate()
                guard existing.operationID == operationID, existing.rootDevice == authority.rootDevice,
                      existing.rootInode == authority.rootInode else { throw AppAccessContractFailureV1.configurationUnknown }
                erase = existing
            } else {
                guard try !ingressControlFileExists(complete) else { throw AppAccessContractFailureV1.configurationUnknown }
                let published = try pendingIngressPublications()
                let publishedIDs = Set(published.map { $0.intent.intentID })
                let unfinished = try ingressPreparations().filter {
                    try !publishedIDs.contains($0.intent.intentID)
                        && !ingressControlFileExists(ingressControlURL($0.intent.intentID, ".terminal.json"))
                        && !ingressControlFileExists(ingressControlURL($0.intent.intentID, ".aborted.json"))
                }
                erase = .init(operationID: operationID, rootDevice: authority.rootDevice, rootInode: authority.rootInode,
                    targets: published, unpublishedTargets: try unfinished.map(makeUnpublishedIngressEraseTarget))
                try erase.validate()
                try writeProtectedIngressCanonical(try CompatibilityCanonicalV1.encode(erase), to: file)
                try ingressMutationFailureInjection.interruptIfTriggered(.afterErasePrepare)
            }
            if let recorded = try readIngressControl(C16IngressEraseV1.self, at: complete) {
                guard recorded == erase else { throw AppAccessContractFailureV1.effectMismatch }
                return
            }
            for target in erase.unpublishedTargets {
                try removeUnpublishedIngress(target, operationID: operationID)
            }
            for target in erase.targets {
                try removeProtectedIngress(expected: target.intent, disposition: .erased)
            }
            try writeProtectedIngressCanonical(try CompatibilityCanonicalV1.encode(erase), to: complete)
            guard try readIngressControl(C16IngressEraseV1.self, at: complete) == erase else {
                throw AppAccessContractFailureV1.effectMismatch
            }
        }
    }

    private func ingressControlURL(_ intentID: UUID, _ suffix: String) throws -> URL {
        guard intentID != SettingsValidationV1.zeroUUID else { throw AppAccessContractFailureV1.invalidValue }
        return try protectedIngressReceiptDirectory().appendingPathComponent(
            "ingress-" + intentID.uuidString.lowercased() + suffix)
    }

    private func readIngressControl<Value: Codable>(_ type: Value.Type, at file: URL) throws -> Value? {
        guard try ingressControlFileExists(file) else { return nil }
        return try CompatibilityCanonicalV1.decode(type, from: readIngressControlFile(file, maximumBytes: 262_144))
    }

    private func validateIngressPreparation(_ value: C16IngressPreparedStageV1, intentID: UUID) throws {
        try verifyRoot()
        try value.validate()
        guard value.intent.intentID == intentID, value.rootDevice == authority.rootDevice,
              value.rootInode == authority.rootInode else { throw AppAccessContractFailureV1.configurationUnknown }
    }

    private func ingressPreparations() throws -> [C16IngressPreparedStageV1] {
        let names = try directoryNames(ingressControlDescriptor())
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
            guard let value = try readIngressControl(C16IngressEraseV1.self, at: file) else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            try value.validate()
            guard value.operationID == id, value.rootDevice == authority.rootDevice, value.rootInode == authority.rootInode else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            let complete = try protectedIngressReceiptDirectory().appendingPathComponent("erase-" + id.uuidString.lowercased() + ".complete.json")
            if let recorded = try readIngressControl(C16IngressEraseV1.self, at: complete), recorded != value {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        }
        return try ids.sorted { $0.uuidString < $1.uuidString }.map { id in
            guard let value = try readIngressControl(C16IngressPreparedStageV1.self,
                at: ingressControlURL(id, ".prepare.json")) else { throw AppAccessContractFailureV1.configurationUnknown }
            try validateIngressPreparation(value, intentID: id)
            return value
        }
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
        if Darwin.fstatat(authority.operationsDescriptor, "ProtectedIngressReceiptsV1", &information, AT_SYMLINK_NOFOLLOW) != 0 {
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
            let files = try directoryNames(descriptor).map { name -> C16IngressHygieneFileIdentityV1 in
                try validateIngressControlSnapshotName(name)
                try ProtectedFilePolicyV1.verify(.temporaryFile, at: directory.appendingPathComponent(name))
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
            try ProtectedFilePolicyV1.verify(.temporaryFile, at: directory.appendingPathComponent(name))
        }
        for name in remaining {
            _ = try protectedIngressReceiptDirectory()
            let current = try C16IngressHygieneFileIdentityV1(name: name,
                information: regularFileInformation(named: name, directoryDescriptor: descriptor))
            guard expectedFiles[name] == current, Darwin.unlinkat(descriptor, name, 0) == 0,
                  Darwin.fsync(descriptor) == 0 else { throw AppAccessContractFailureV1.configurationUnknown }
            try ingressMutationFailureInjection.interruptIfTriggered(.afterScratchControlEraseFile)
        }
        _ = try protectedIngressReceiptDirectory()
        guard try directoryNames(descriptor) == [Self.controlEraseName],
              try readRegularFile(named: Self.controlEraseName, directoryDescriptor: descriptor, maximumBytes: maximumMarkerBytes)
                == CompatibilityCanonicalV1.encode(marker),
              Darwin.unlinkat(descriptor, Self.controlEraseName, 0) == 0, Darwin.fsync(descriptor) == 0 else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        try pinned.verify(rootName: "ProtectedIngressReceiptsV1")
        guard Darwin.unlinkat(authority.operationsDescriptor, "ProtectedIngressReceiptsV1", AT_REMOVEDIR) == 0,
              Darwin.fsync(authority.operationsDescriptor) == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        ingressControlAuthority = nil
    }

    private func validateIngressClaim(_ claim: C16IngressDirectoryClaimV1) throws -> Int32 {
        try validateIngressPreparation(claim.preparation, intentID: claim.preparation.intent.intentID)
        let name = claim.preparation.lease.relativeDirectory
        let descriptor = try openLeaseDirectory(name)
        do {
            var information = stat()
            guard Darwin.fstat(descriptor, &information) == 0,
                  UInt64(information.st_dev) == claim.device, UInt64(information.st_ino) == claim.inode else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
            try ProtectedFilePolicyV1.verify(.stagingDirectory, at: rootURL.appendingPathComponent(name))
            try verifyLeaseDirectory(name, descriptor: descriptor)
            return descriptor
        } catch {
            _ = Darwin.close(descriptor)
            throw error
        }
    }

    private func validateIngressPublication(_ value: C16IngressPublicationV1, hashPayload: Bool) throws {
        try value.validate()
        let descriptor = try validateIngressClaim(value.claim)
        defer { _ = Darwin.close(descriptor) }
        let name = value.claim.preparation.lease.relativeDirectory
        let files = try ingressHygieneFileIdentities(name: name, descriptor: descriptor)
        guard files == [value.metadata, value.payload].sorted(by: { $0.name < $1.name }) else {
            throw AppAccessContractFailureV1.effectMismatch
        }
        if hashPayload {
            let payload = Darwin.openat(descriptor, value.payload.name, O_RDONLY | O_NOFOLLOW)
            guard payload >= 0 else { throw AppAccessContractFailureV1.configurationUnknown }
            defer { _ = Darwin.close(payload) }
            var information = stat()
            guard Darwin.fstat(payload, &information) == 0,
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
            pinnedDescriptor: descriptor, maximumByteCount: preparation.intent.byteCount)
        defer { withExtendedLifetime(sink) {} }
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

    func acquireScratchLease(
        _ request: ScratchDataLeaseRequestV1
    ) async throws -> ScratchDataLeaseV1 {
        try Self.filesystemLock.withLock {
            try acquireScratchLeaseSynchronously(request)
        }
    }

    private func acquireScratchLeaseSynchronously(
        _ request: ScratchDataLeaseRequestV1
    ) throws -> ScratchDataLeaseV1 {
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
        try Self.filesystemLock.withLock {
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
        try Self.filesystemLock.withLock {
            try releaseScratchLeaseSynchronously(lease, terminal: terminal)
        }
    }

    private func releaseScratchLeaseSynchronously(
        _ lease: ScratchDataLeaseV1,
        terminal: ScratchDataLeaseTerminalV1
    ) throws {
        try verifyRoot()
        try lease.request.validate()
        guard lease.schemaVersion == ScratchDataLeaseV1.schemaVersion,
              lease.relativeDirectory == Self.leaseDirectoryName(for: lease.request) else {
            throw ScratchDataLeaseStoreFailureV1.invalidLease
        }
        // A different owner may have removed and reused a cached lease's ID.
        // Release is bound to the caller's value before any recovery can mutate it.
        if try removeIngressScratchLeaseIfOwned(named: lease.relativeDirectory, expectedLease: lease) {
            active.removeValue(forKey: lease.request.leaseID)
            return
        }
        if try directoryInformationIfPresent(named: lease.relativeDirectory) == nil,
           try directoryInformationIfPresent(named: Self.deletionTombstoneName(for: lease.relativeDirectory)) == nil {
            active.removeValue(forKey: lease.request.leaseID)
            return
        }
        _ = terminal
        try removeLeaseDirectory(named: lease.relativeDirectory, expectedLease: lease)
        active.removeValue(forKey: lease.request.leaseID)
    }

    func recoverScratchLeases() async throws -> ScratchDataLeaseRecoverySummaryV1 {
        try Self.filesystemLock.withLock {
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
        try Self.filesystemLock.withLock {
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
        try Self.filesystemLock.withLock {
            try eraseScratchDataSynchronously()
        }
    }

    private func eraseScratchDataSynchronously() throws {
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

    private func requireExpectedScratchLease(
        _ expected: ScratchDataLeaseV1, named name: String, descriptor: Int32
    ) throws {
        try verifyLeaseDirectory(name, descriptor: descriptor)
        let metadata = rootURL.appendingPathComponent(name).appendingPathComponent(Self.metadataName)
        try ProtectedFilePolicyV1.verify(.temporaryFile, at: metadata)
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
        named name: String, expectedLease: ScratchDataLeaseV1? = nil
    ) throws {
        guard Self.isLeaseDirectoryName(name) else {
            throw ScratchDataLeaseStoreFailureV1.invalidLease
        }
        try verifyRoot()
        if try removeIngressScratchLeaseIfOwned(named: name, expectedLease: expectedLease) { return }
        try requireNoUnfinishedHygieneTarget(named: name)
        let tombstone = Self.deletionTombstoneName(for: name)
        if try directoryInformationIfPresent(named: name) == nil {
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
        defer { _ = Darwin.close(descriptor) }
        if let expectedLease {
            try requireExpectedScratchLease(expectedLease, named: name, descriptor: descriptor)
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
        try deletePinnedDirectory(named: tombstone, descriptor: descriptor)
    }

    private func removeDeletionTombstone(
        named name: String, expectedLease: ScratchDataLeaseV1? = nil
    ) throws {
        guard Self.isDeletionTombstone(name) else {
            throw ScratchDataLeaseStoreFailureV1.invalidLease
        }
        try requireNoUnfinishedHygieneTarget(named: String(name.dropFirst(Self.deletionPrefix.count)))
        let descriptor = try openLeaseDirectory(name)
        defer { _ = Darwin.close(descriptor) }
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
        descriptor: Int32,
        expectedFiles: [C16IngressHygieneFileIdentityV1]? = nil
    ) throws {
        try verifyLeaseDirectory(name, descriptor: descriptor)
        if expectedFiles == nil {
            try removeInterruptedPublications(directoryDescriptor: descriptor)
        }
        let names = try directoryNames(descriptor)
        if let expectedFiles {
            let survivors = try ingressHygieneFileIdentities(name: name, descriptor: descriptor)
            guard survivors.map(\.name) == names,
                  survivors.allSatisfy({ expectedFiles.contains($0) }) else {
                throw AppAccessContractFailureV1.configurationUnknown
            }
        }
        for child in names {
            let information = try regularFileInformation(
                named: child,
                directoryDescriptor: descriptor
            )
            if let expectedFiles {
                let current = C16IngressHygieneFileIdentityV1(name: child, information: information)
                guard expectedFiles.contains(current) else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
                try ProtectedFilePolicyV1.verify(.temporaryFile,
                    at: rootURL.appendingPathComponent(name).appendingPathComponent(child))
                try verifyLeaseDirectory(name, descriptor: descriptor)
                guard try C16IngressHygieneFileIdentityV1(name: child,
                    information: regularFileInformation(named: child, directoryDescriptor: descriptor)) == current else {
                    throw AppAccessContractFailureV1.configurationUnknown
                }
            }
            guard Darwin.unlinkat(descriptor, child, 0) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            if expectedFiles != nil {
                guard Darwin.fsync(descriptor) == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
                try ingressMutationFailureInjection.interruptIfTriggered(.afterPreparedDirectoryFileDeletion)
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
        // dup shares the directory offset with the retained descriptor. Every
        // independently fenced snapshot must start at the beginning.
        Darwin.rewinddir(directory)
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
        try directoryAuthorityCheck?()
    }

    private func removeInterruptedPublications(
        directoryDescriptor: Int32
    ) throws {
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
    func makeEncryptedPortableEnvelopeStreamingScratch(
        named: String,
        lease: ScratchDataLeaseV1,
        maximumByteCount: UInt64
    ) async throws -> any EncryptedEnvelopeProtectedScratchSinkV1
}

final class EncryptedPortableEnvelopeProtectedFileScratchV1:
    EncryptedEnvelopeProtectedScratchSinkV1,
    @unchecked Sendable {
    static let maximumAppendByteCount = 1_048_604

    let protectionClass = EncryptedEnvelopeProtectionClassV1.complete
    let isExcludedFromBackup = true

    private let url: URL
    private let maximumByteCount: UInt64
    private let descriptor: Int32
    private let device: UInt64
    private let inode: UInt64
    private let lock = NSLock()
    private var expectedByteCount: UInt64?
    private var writtenByteCount: UInt64 = 0

    init(url: URL, pinnedDescriptor: Int32, maximumByteCount: UInt64) throws {
        guard url.isFileURL,
              pinnedDescriptor >= 0,
              maximumByteCount <= EncryptedPortableEnvelopeResourceLimitsV1
                .maximumOperationalScratchByteCount else {
            if pinnedDescriptor >= 0 { _ = Darwin.close(pinnedDescriptor) }
            throw EncryptedPortableEnvelopeFailureV1.resourceLimitExceeded
        }
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

    deinit { _ = Darwin.close(descriptor) }

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
        guard Darwin.fstat(descriptor, &status) == 0,
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
        try Self.filesystemLock.withLock {
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
    func makeEncryptedPortableEnvelopeStreamingScratch(
        named: String,
        lease: ScratchDataLeaseV1,
        maximumByteCount: UInt64
    ) async throws -> any EncryptedEnvelopeProtectedScratchSinkV1 {
        try Self.filesystemLock.withLock {
            try makeEncryptedPortableEnvelopeStreamingScratchSynchronously(named: named, lease: lease, maximumByteCount: maximumByteCount)
        }
    }

    private func makeEncryptedPortableEnvelopeStreamingScratchSynchronously(
        named: String,
        lease: ScratchDataLeaseV1,
        maximumByteCount: UInt64
    ) throws -> any EncryptedEnvelopeProtectedScratchSinkV1 {
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
        return try EncryptedPortableEnvelopeProtectedFileScratchV1(
            url: url,
            pinnedDescriptor: descriptor,
            maximumByteCount: maximumByteCount
        )
    }
}

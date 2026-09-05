import CryptoKit
import Foundation

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
    private let rootURL: URL
    private let quarantineURL: URL
    private let workspaceScope: WorkspaceID?
    private let scratchStore: (any ScratchDataLeasePortV1)?
    private let storageLedger: OwnedStorageLedgerV1?
    private let immutableContentWriter: (any DraftImmutableContentWriterV1)?
    private let clock: Clock
    private var manifest: DraftAttachmentStagingManifestV1

    init(
        applicationSupportURL: URL,
        workspaceID: WorkspaceID? = nil,
        scratchStore: (any ScratchDataLeasePortV1)? = nil,
        storageLedger: OwnedStorageLedgerV1? = nil,
        immutableContentWriter: (any DraftImmutableContentWriterV1)? = nil,
        fileManager: FileManager = .default,
        clock: @escaping Clock = { Date() }
    ) throws {
        guard applicationSupportURL.isFileURL else {
            throw DraftAttachmentStagingFailureV1.invalidRoot
        }
        if let workspaceID,
           workspaceID.rawValue == Self.zero {
            throw DraftAttachmentStagingFailureV1.wrongWorkspace
        }
        self.fileManager = fileManager
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

        do {
            try fileManager.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.createDirectory(
                at: quarantineURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: root)
            try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: quarantineURL)
        } catch let failure as ProtectedFilePolicyError
            where failure == .protectedDataUnavailable {
            throw DraftAttachmentStagingFailureV1.protectedDataUnavailable
        } catch {
            throw DraftAttachmentStagingFailureV1.invalidRoot
        }
        let manifestURL = root.appendingPathComponent(Self.manifestName)
        if fileManager.fileExists(atPath: manifestURL.path) {
            do {
                let data = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
                var decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .millisecondsSince1970
                let value = try decoder.decode(
                    DraftAttachmentStagingManifestV1.self,
                    from: data
                )
                try value.validate()
                self.manifest = value
                try ProtectedFilePolicyV1.verify(.stagingFile, at: manifestURL)
            } catch let failure as DraftAttachmentStagingFailureV1 {
                throw failure
            } catch let failure as ProtectedFilePolicyError
                where failure == .protectedDataUnavailable {
                throw DraftAttachmentStagingFailureV1.protectedDataUnavailable
            } catch {
                throw DraftAttachmentStagingFailureV1.corruptManifest
            }
        } else {
            self.manifest = try DraftAttachmentStagingManifestV1(entries: [])
            try Self.writeManifest(
                self.manifest,
                to: manifestURL,
                fileManager: fileManager
            )
        }
    }

    /// Stages one attachment without assigning an EvidenceID.  The default
    /// mutation identity is deterministic for the stage, which makes retrying
    /// a crashed capture idempotent.
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
        let relativePath = Self.relativeDataPath(draftID: draftID, stageID: stageID)
        let directory = rootURL.appendingPathComponent(
            Self.relativeStageDirectory(draftID: draftID, stageID: stageID),
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: directory)
            let payloadURL = rootURL.appendingPathComponent(relativePath)
            try scratch.bytes.write(to: payloadURL, options: [.atomic])
            try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: payloadURL)
            let readBack = try Data(contentsOf: payloadURL, options: .mappedIfSafe)
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
            try persistManifest()
            return item
        } catch let failure as DraftAttachmentStagingFailureV1 {
            try? removeDirectory(directory)
            throw failure
        } catch let failure as ProtectedFilePolicyError
            where failure == .protectedDataUnavailable {
            try? removeDirectory(directory)
            throw DraftAttachmentStagingFailureV1.protectedDataUnavailable
        } catch {
            try? removeDirectory(directory)
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
        manifest.entries.first(where: { $0.item.stageID == stageID })?.item
    }

    func entries(
        workspaceID: WorkspaceID? = nil,
        draftID: UUID? = nil
    ) throws -> [DraftAttachmentStagingEntryV1] {
        if let workspaceID, workspaceID.rawValue == Self.zero {
            throw DraftAttachmentStagingFailureV1.wrongWorkspace
        }
        return manifest.entries.filter { entry in
            (workspaceID == nil || entry.item.workspaceID == workspaceID)
                && (draftID == nil || entry.item.draftID == draftID)
        }
    }

    func data(stageID: UUID) throws -> Data {
        guard let entry = manifest.entries.first(where: { $0.item.stageID == stageID }) else {
            throw DraftAttachmentStagingFailureV1.stageNotFound
        }
        return try verifiedBytes(for: entry)
    }

    func verify(stageID: UUID) throws -> AttachmentStagingItemV1 {
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
        guard let entry = manifest.entries.first(where: { $0.item.stageID == stageID }) else {
            throw DraftAttachmentStagingFailureV1.stageNotFound
        }
        guard entry.item.revision == expectedRevision else {
            throw DraftAttachmentStagingFailureV1.staleStage
        }
        let pending = try successor(entry.item, state: .removePending)
        manifest = try replacing(try DraftAttachmentStagingEntryV1(
            item: pending,
            relativeDataPath: entry.relativeDataPath,
            mediaType: entry.mediaType,
            updatedAt: clock()
        ))
        try persistManifest()
        let bytes = (try? verifiedBytes(for: entry).count) ?? 0
        let directory = rootURL.appendingPathComponent(
            Self.relativeStageDirectory(
                draftID: pending.draftID,
                stageID: pending.stageID
            ),
            isDirectory: true
        )
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
        guard let entry = manifest.entries.first(where: { $0.item.stageID == stageID }) else {
            throw DraftAttachmentStagingFailureV1.stageNotFound
        }
        guard entry.item.revision == expectedRevision else {
            throw DraftAttachmentStagingFailureV1.staleStage
        }
        let quarantined = try successor(entry.item, state: .orphanQuarantined)
        let source = rootURL.appendingPathComponent(
            Self.relativeStageDirectory(draftID: entry.item.draftID, stageID: stageID),
            isDirectory: true
        )
        let destinationName = "stage-\(stageID.uuidString.lowercased())"
        let destination = quarantineURL.appendingPathComponent(destinationName, isDirectory: true)
        do {
            if fileManager.fileExists(atPath: source.path) {
                if fileManager.fileExists(atPath: destination.path) {
                    try removeDirectory(destination)
                }
                try fileManager.moveItem(at: source, to: destination)
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
        let current = try items.map { item -> (entry: DraftAttachmentStagingEntryV1, bytes: Data) in
            guard let entry = manifest.entries.first(where: { $0.item.stageID == item.stageID }),
                  entry.item == item else {
                throw DraftAttachmentStagingFailureV1.staleStage
            }
            let bytes = try verifiedBytes(for: entry)
            return (entry: entry, bytes: bytes)
        }
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
            fileManager: fileManager
        )
        manifest = nextManifest
        return reservations
    }

    func quarantine(
        reservations: [DraftContentReservationV1],
        for plan: DraftDiscardPlanV1
    ) async throws {
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
            _ = try quarantine(stageID: entry.item.stageID, expectedRevision: entry.item.revision)
        }
    }

    /// Recovery is bounded and fail-closed: missing/tampered bytes become a
    /// retryable/final state, never READY_LOCAL.
    @discardableResult
    func reconcile() throws -> [AttachmentStagingItemV1] {
        var updated = manifest.entries
        for index in updated.indices {
            let entry = updated[index]
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
        let retained = manifest.entries.filter { entry in
            guard let workspaceID else { return false }
            return entry.item.workspaceID != workspaceID
        }
        let removed = manifest.entries.filter { entry in
            guard let workspaceID else { return true }
            return entry.item.workspaceID == workspaceID
        }
        for entry in removed {
            let directory = rootURL.appendingPathComponent(
                Self.relativeStageDirectory(draftID: entry.item.draftID, stageID: entry.item.stageID),
                isDirectory: true
            )
            try? removeDirectory(directory)
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

    private static func uuidLess(_ lhs: UUID, _ rhs: UUID) -> Bool {
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
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0,
                               0, 0, 0, 0, 0, 0, 0, 0))
        guard sourceRootURL.isFileURL, restoreID != zero,
              workspaceID.rawValue != zero,
              sourceRootURL.standardizedFileURL != rootURL.standardizedFileURL else {
            throw DraftAttachmentStagingFailureV1.invalidRoot
        }
        let sourceManifest = try DraftAttachmentStagingManifestV1(entries: entries)
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
        var createdDirectories = [URL]()

        do {
            for entry in ordered {
                let item = entry.item
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
                    Self.relativeStageDirectory(
                        draftID: item.draftID,
                        stageID: item.stageID
                    ),
                    isDirectory: true
                )
                try fileManager.createDirectory(
                    at: destinationDirectory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                try ProtectedFilePolicyV1.applyAndVerify(
                    .stagingDirectory,
                    at: destinationDirectory
                )
                createdDirectories.append(destinationDirectory)
                // The source relative path can belong to the source draft in
                // a clone/fork restore.  Always publish into the target's
                // canonical adapter path; source layout is only an input.
                let destinationRelativePath = Self.relativeDataPath(
                    draftID: item.draftID,
                    stageID: item.stageID
                )
                let destinationURL = rootURL.appendingPathComponent(
                    destinationRelativePath
                )
                try bytes.write(to: destinationURL, options: [.atomic])
                try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: destinationURL)
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
            try persistManifest()
            return try DraftAttachmentRestorePublicationReceiptV1(
                restoreID: restoreID,
                workspaceID: workspaceID,
                sourceManifestSHA256: sourceManifestSHA256,
                adoptedStageIDs: adopted.sorted(by: Self.uuidLess),
                reusedStageIDs: reused.sorted(by: Self.uuidLess),
                publishedAt: clock()
            )
        } catch let failure as DraftAttachmentStagingFailureV1 {
            for directory in createdDirectories.reversed() {
                try? removeDirectory(directory)
            }
            throw failure
        } catch let failure as ProtectedFilePolicyError
            where failure == .protectedDataUnavailable {
            for directory in createdDirectories.reversed() {
                try? removeDirectory(directory)
            }
            throw DraftAttachmentStagingFailureV1.protectedDataUnavailable
        } catch {
            for directory in createdDirectories.reversed() {
                try? removeDirectory(directory)
            }
            throw DraftAttachmentStagingFailureV1.cleanupFailed
        }
    }
}

// These canonical path projections are shared by the backup adapter when it
// enumerates the same draft-owned staging root.  They do not expose a mutable
// writer or a filesystem handle.
extension DraftAttachmentStagingAdapterV1 {
    static func relativeStageDirectory(draftID: UUID, stageID: UUID) -> String {
        "draft-\(draftID.uuidString.lowercased())/stage-\(stageID.uuidString.lowercased())"
    }

    static func relativeDataPath(draftID: UUID, stageID: UUID) -> String {
        relativeStageDirectory(draftID: draftID, stageID: stageID) + "/" + payloadName
    }
}

private extension DraftAttachmentStagingAdapterV1 {
    struct ScratchCopy: Sendable {
        let bytes: Data
        let leaseID: UUID
    }

    static let zero = UUID(uuid: (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    ))

    func validateScope(workspaceID: WorkspaceID, draftID: UUID, stageID: UUID) throws {
        guard workspaceID.rawValue != Self.zero,
              draftID != Self.zero, stageID != Self.zero else {
            throw DraftAttachmentStagingFailureV1.invalidAttachment
        }
        if let workspaceScope, workspaceScope != workspaceID {
            throw DraftAttachmentStagingFailureV1.wrongWorkspace
        }
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
        try Self.writeManifest(manifest, to: rootURL.appendingPathComponent(Self.manifestName), fileManager: fileManager)
    }

    static func writeManifest(
        _ value: DraftAttachmentStagingManifestV1,
        to url: URL,
        fileManager: FileManager
    ) throws {
        try value.validate()
        var encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
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
        let target = rootURL.appendingPathComponent(entry.relativeDataPath).standardizedFileURL
        guard target.path.hasPrefix(rootURL.path + "/") else {
            throw DraftAttachmentStagingFailureV1.unsafePath
        }
        do {
            try ProtectedFilePolicyV1.verify(.stagingFile, at: target)
            let data = try Data(contentsOf: target, options: .mappedIfSafe)
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
            let values = try candidate.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw DraftAttachmentStagingFailureV1.unsafePath
            }
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
            data = try Data(contentsOf: bytesURL, options: .mappedIfSafe)
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

    func removeDirectory(_ url: URL) throws {
        guard url.standardizedFileURL.path.hasPrefix(rootURL.path + "/") else {
            throw DraftAttachmentStagingFailureV1.unsafePath
        }
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    static func defaultMediaType(for kind: DraftAttachmentKindV1) -> String {
        switch kind {
        case .photo: return "image/jpeg"
        case .audio: return "audio/mpeg"
        case .video: return "video/mp4"
        case .file: return "application/octet-stream"
        }
    }

    static func contentID(workspaceID: WorkspaceID, digest: ContentDigestV1) -> String {
        "draft-content-\(workspaceID.rawValue.uuidString.lowercased())-\(digest.hexadecimalValue)"
    }

    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

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

    func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum C34SceneRestorationAttachmentStagingBoundaryV1 {
    static let createsStage = false
    static let promotesStage = false
    static let claimsStagingOwnership = false
    static func validate(anchor: DraftResumeAnchorV1) -> Bool { !createsStage && !promotesStage && !claimsStagingOwnership && C34DraftResumeNavigationBoundaryV1.validate(anchor: anchor) }
}

import Darwin
import Foundation

enum FunctionalRelationshipEraseIntentStorePolicyV1 {
    static func validate() throws {
        guard FunctionalRelationshipEraseBoundaryV1.validate() else {
            throw EraseIntentStoreError.invalidAuthority
        }
    }
}

enum EvidenceAssuranceEraseIntentStorePolicyV1 {
    static func validate() throws {
        guard EvidenceAssuranceEraseBoundaryV1.immutableHistoryClearedOnlyByWorkspaceErase,
              EvidenceAssuranceEraseBoundaryV1.ordinaryDeletionIsZeroWrite else {
            throw EraseIntentStoreError.invalidAuthority
        }
    }
}

enum InspectionReviewEraseIntentStorePolicyV1 {
    static func validate() throws {
        guard InspectionReviewEraseBoundaryV1.immutableReviewAndCorrectiveActionHistoryClearedOnlyByWorkspaceErase,
              InspectionReviewEraseBoundaryV1.ordinaryDeletionPreservesAcceptedFinalizedAndActionHistory else {
            throw EraseIntentStoreError.invalidAuthority
        }
    }
}

enum WorkPacketEraseIntentStorePolicyV1{static func validate()throws{guard WorkPacketEraseBoundaryV1.immutableManifestClaimLeaseReleaseAndHandoffHistoryClearedOnlyByWorkspaceErase,WorkPacketEraseBoundaryV1.ordinaryDeletionPreservesReplayHistory else{throw EraseIntentStoreError.invalidAuthority}}}
enum FieldDraftEraseIntentStorePolicyV1{static func validate()throws{guard FieldDraftEraseBoundaryV1.operationalStateClearedOnlyByWorkspaceErase,FieldDraftEraseBoundaryV1.ordinaryDeletionPreservesLiveAndRecoveryRequiredDrafts,FieldDraftEraseBoundaryV1.byteCleanupRequiresTerminalDiscardOrOrphanQuarantine else{throw EraseIntentStoreError.invalidAuthority}}}
enum PackageEvolutionEraseIntentStorePolicyV1{static func validate()throws{guard PackageEvolutionEraseBoundaryV1.atomicFamilyCount==4,PackageEvolutionEraseBoundaryV1.ordinaryDeletionPreservesPromotedHistory,PackageEvolutionEraseBoundaryV1.workspaceEraseClearsEntireClosure else{throw EraseIntentStoreError.invalidAuthority}}}
enum MeasurementIntegrityEraseIntentStorePolicyV1{static func validate()throws{guard MeasurementIntegrityEraseBoundaryV1.atomicFamilyCount==5,MeasurementIntegrityEraseBoundaryV1.ordinaryDeletionPreservesFrozenHistory,MeasurementIntegrityEraseBoundaryV1.workspaceEraseClearsEntireClosure else{throw EraseIntentStoreError.invalidAuthority}}}
enum PrivacyTransformEraseIntentStorePolicyV1{static func validate()throws{guard PrivacyTransformEraseBoundaryV1.atomicFamilyCount==4,PrivacyTransformEraseBoundaryV1.ordinaryDeletionPreservesOriginalsDerivativesAndImmutableHistory,PrivacyTransformEraseBoundaryV1.workspaceEraseClearsEntireClosure,PrivacyTransformEraseBoundaryV1.escapedFilesCannotBeRecalled else{throw EraseIntentStoreError.invalidAuthority}}}
enum ClientCapabilityEraseIntentStorePolicyV1{static func validate()throws{guard ClientCapabilityEraseBoundaryV1.atomicFamilyCount==4,ClientCapabilityEraseBoundaryV1.ordinaryDeletionPreservesReadableHistory,ClientCapabilityEraseBoundaryV1.workspaceEraseClearsEntireClosure,ClientCapabilityEraseBoundaryV1.escapedArchivesCannotBeRecalled else{throw EraseIntentStoreError.invalidAuthority}}}
enum FieldReferenceEraseIntentStorePolicyV1{static func validate()throws{guard FieldReferenceEraseBoundaryV1.atomicFamilyCount==2,FieldReferenceEraseBoundaryV1.ordinaryDeletionRetainsBoundAndFinalizedReleaseBytes,FieldReferenceEraseBoundaryV1.unboundReleaseMayBeDiscarded,FieldReferenceEraseBoundaryV1.workspaceEraseClearsRowsAndOwnedBytes,FieldReferenceEraseBoundaryV1.readinessProjectionIsNonpersistent else{throw EraseIntentStoreError.invalidAuthority}}}

enum EraseIntentStoreError: Error, Equatable {
    case invalidAuthority
    case invalidIntent
    case invalidPreparation
    case intentAlreadyExists
    case intentMissing
    case intentMismatch
    case preparationAlreadyExists
    case preparationMissing
    case preparationMismatch
    case writeFailed
    case cleanupFailed
}

struct ErasePreparationV2: Equatable, Sendable {
    let oldPointer: RestorePointerIdentityV1
    let sourceLedger: DeletionLedgerProofV2
    let targetGenerationID: UUID
    let targetWorkspaceID: UUID
    let targetReplicaID: UUID
    let targetPointer: RestorePointerIdentityV1?

    func binding(targetPointer: RestorePointerIdentityV1) -> ErasePreparationV2 {
        ErasePreparationV2(
            oldPointer: oldPointer,
            sourceLedger: sourceLedger,
            targetGenerationID: targetGenerationID,
            targetWorkspaceID: targetWorkspaceID,
            targetReplicaID: targetReplicaID,
            targetPointer: targetPointer
        )
    }

    func matches(_ intent: EraseIntentV1) -> Bool {
        intent.schemaVersion == 2
            && intent.oldPointer == oldPointer
            && intent.sourceLedger == sourceLedger
            && intent.newGenerationID == targetGenerationID
            && intent.targetPointer == targetPointer
            && targetPointer != nil
            && intent.targetPointer?.workspaceID == targetWorkspaceID
            && intent.targetPointer?.replicaID == targetReplicaID
    }
}

private enum ErasePreparationCodecV2 {
    private static let keys = Set([
        "oldPointer",
        "schemaVersion",
        "sourceLedger",
        "targetGenerationID",
        "targetPointer",
        "targetReplicaID",
        "targetWorkspaceID",
    ])
    private static let pointerKeys = Set([
        "generationID",
        "generationManifestSHA256",
        "knownReplicaIDs",
        "replicaID",
        "workspaceID",
    ])
    private static let ledgerKeys = Set([
        "canonicalSHA256",
        "entryCount",
    ])

    static func encode(_ value: ErasePreparationV2) throws -> Data {
        guard valid(value) else {
            throw EraseIntentStoreError.invalidPreparation
        }
        return try CanonicalJSONV1.encode(.object([
            "oldPointer": pointerJSON(value.oldPointer),
            "schemaVersion": .integer(2),
            "sourceLedger": .object([
                "canonicalSHA256": .string(value.sourceLedger.canonicalSHA256),
                "entryCount": .integer(value.sourceLedger.entryCount),
            ]),
            "targetGenerationID": .string(canonical(value.targetGenerationID)),
            "targetPointer": value.targetPointer.map(pointerJSON) ?? .null,
            "targetReplicaID": .string(canonical(value.targetReplicaID)),
            "targetWorkspaceID": .string(canonical(value.targetWorkspaceID)),
        ]))
    }

    static func decode(_ data: Data) throws -> ErasePreparationV2 {
        guard let object = try JSONSerialization.jsonObject(
            with: data,
            options: [.fragmentsAllowed]
        ) as? [String: Any],
              Set(object.keys) == keys,
              object.count == keys.count,
              let schemaVersion = canonicalInt(object["schemaVersion"]),
              schemaVersion == 2,
              let oldPointer = decodePointer(object["oldPointer"]),
              let sourceLedger = decodeLedger(object["sourceLedger"]),
              let targetGenerationID = canonicalUUID(
                  object["targetGenerationID"]
              ),
              let targetReplicaID = canonicalUUID(object["targetReplicaID"]),
              let targetWorkspaceID = canonicalUUID(
                  object["targetWorkspaceID"]
              ) else {
            throw EraseIntentStoreError.invalidPreparation
        }
        let targetPointer: RestorePointerIdentityV1?
        if object["targetPointer"] is NSNull {
            targetPointer = nil
        } else {
            guard let value = decodePointer(object["targetPointer"]) else {
                throw EraseIntentStoreError.invalidPreparation
            }
            targetPointer = value
        }
        let value = ErasePreparationV2(
            oldPointer: oldPointer,
            sourceLedger: sourceLedger,
            targetGenerationID: targetGenerationID,
            targetWorkspaceID: targetWorkspaceID,
            targetReplicaID: targetReplicaID,
            targetPointer: targetPointer
        )
        guard try encode(value) == data else {
            throw EraseIntentStoreError.invalidPreparation
        }
        return value
    }

    static func valid(_ value: ErasePreparationV2) -> Bool {
        let unavailable = Set(
            value.oldPointer.knownReplicaIDs + [
                value.oldPointer.generationID,
                value.oldPointer.workspaceID,
                value.oldPointer.replicaID,
            ]
        )
        guard validPointer(value.oldPointer),
              (try? value.sourceLedger.validate()) != nil,
              value.sourceLedger.entryCount
                <= DeletionLedgerV2.maximumEntryCount,
              value.targetGenerationID != zero,
              value.targetWorkspaceID != zero,
              value.targetReplicaID != zero,
              value.targetGenerationID != value.targetWorkspaceID,
              value.targetGenerationID != value.targetReplicaID,
              value.targetWorkspaceID != value.targetReplicaID,
              !unavailable.contains(value.targetGenerationID),
              !unavailable.contains(value.targetWorkspaceID),
              !unavailable.contains(value.targetReplicaID) else {
            return false
        }
        guard let targetPointer = value.targetPointer else { return true }
        return validPointer(targetPointer)
            && targetPointer.generationID == value.targetGenerationID
            && targetPointer.workspaceID == value.targetWorkspaceID
            && targetPointer.replicaID == value.targetReplicaID
            && targetPointer.knownReplicaIDs == [value.targetReplicaID]
    }

    private static func pointerJSON(
        _ value: RestorePointerIdentityV1
    ) -> CanonicalJSONValueV1 {
        .object([
            "generationID": .string(canonical(value.generationID)),
            "generationManifestSHA256": .string(
                value.generationManifestSHA256
            ),
            "knownReplicaIDs": .array(value.knownReplicaIDs.map {
                .string(canonical($0))
            }),
            "replicaID": .string(canonical(value.replicaID)),
            "workspaceID": .string(canonical(value.workspaceID)),
        ])
    }

    private static func decodePointer(
        _ raw: Any?
    ) -> RestorePointerIdentityV1? {
        guard let object = exactObject(raw, keys: pointerKeys),
              let generationID = canonicalUUID(object["generationID"]),
              let digest = object["generationManifestSHA256"] as? String,
              let rawHistory = object["knownReplicaIDs"] as? [Any],
              let history = canonicalUUIDs(rawHistory),
              history == history.sorted(by: idOrder),
              Set(history).count == history.count,
              let replicaID = canonicalUUID(object["replicaID"]),
              let workspaceID = canonicalUUID(object["workspaceID"]) else {
            return nil
        }
        return RestorePointerIdentityV1(
            generationID: generationID,
            generationManifestSHA256: digest,
            knownReplicaIDs: Set(history),
            workspaceID: workspaceID,
            replicaID: replicaID
        )
    }

    private static func decodeLedger(_ raw: Any?) -> DeletionLedgerProofV2? {
        guard let object = exactObject(raw, keys: ledgerKeys),
              let entryCount = canonicalInt(object["entryCount"]),
              entryCount >= 0,
              let digest = object["canonicalSHA256"] as? String else {
            return nil
        }
        return try? DeletionLedgerProofV2(
            entryCount: entryCount,
            canonicalSHA256: digest
        )
    }

    private static func validPointer(_ value: RestorePointerIdentityV1) -> Bool {
        value.generationID != zero
            && value.workspaceID != zero
            && value.replicaID != zero
            && value.generationID != value.workspaceID
            && value.generationID != value.replicaID
            && value.workspaceID != value.replicaID
            && !value.knownReplicaIDs.isEmpty
            && value.knownReplicaIDs.count <= 64
            && value.knownReplicaIDs == value.knownReplicaIDs.sorted(by: idOrder)
            && Set(value.knownReplicaIDs).count == value.knownReplicaIDs.count
            && value.knownReplicaIDs.contains(value.replicaID)
            && validSHA256(value.generationManifestSHA256)
    }

    private static func exactObject(
        _ raw: Any?,
        keys: Set<String>
    ) -> [String: Any]? {
        guard let value = raw as? [String: Any],
              Set(value.keys) == keys,
              value.count == keys.count else {
            return nil
        }
        return value
    }

    private static func canonicalInt(_ raw: Any?) -> Int? {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue == Double(number.intValue) else {
            return nil
        }
        return number.intValue
    }

    private static func canonicalUUIDs(_ values: [Any]) -> [UUID]? {
        var result: [UUID] = []
        for value in values {
            guard let identifier = canonicalUUID(value) else { return nil }
            result.append(identifier)
        }
        return result
    }

    private static func canonicalUUID(_ raw: Any?) -> UUID? {
        guard let value = raw as? String,
              value == value.lowercased(),
              let identifier = UUID(uuidString: value),
              canonical(identifier) == value else {
            return nil
        }
        return identifier
    }

    private static func validSHA256(_ value: String) -> Bool {
        value.count == 64
            && value.unicodeScalars.allSatisfy {
                (48...57).contains(Int($0.value))
                    || (97...102).contains(Int($0.value))
            }
    }

    private static func canonical(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }

    private static func idOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        canonical(lhs) < canonical(rhs)
    }

    private static let zero = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )
}

/// Descriptor-pinned authority for the erase preparation and intent journals.
/// Canonical leaves are never followed through symbolic links; replacement is
/// an atomic exchange whose displaced bytes must equal the expected value.
final class EraseIntentStore {
    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private static let directoryName = "FieldEvidenceErase"
    private static let intentName = "erase.json"
    private static let nextName = ".erase.json.next"
    private static let preparationName = "preparation.json"
    private static let preparationNextName = ".preparation.json.next"

    private let applicationSupportURL: URL
    private let applicationSupportDescriptor: Int32
    private let applicationSupportIdentity: Identity
    private let eraseDescriptor: Int32
    private let eraseIdentity: Identity

    init(
        applicationSupportURL: URL,
        fileManager: FileManager = .default,
        expectedApplicationSupportIdentity: StoreApplicationSupportIdentity? = nil
    ) throws {
        try FunctionalRelationshipEraseIntentStorePolicyV1.validate()
        try EvidenceAssuranceEraseIntentStorePolicyV1.validate()
        try InspectionReviewEraseIntentStorePolicyV1.validate()
        try WorkPacketEraseIntentStorePolicyV1.validate()
        try FieldDraftEraseIntentStorePolicyV1.validate()
        try PackageEvolutionEraseIntentStorePolicyV1.validate()
        try ClientCapabilityEraseIntentStorePolicyV1.validate()
        try PrivacyTransformEraseIntentStorePolicyV1.validate()
        try MeasurementIntegrityEraseIntentStorePolicyV1.validate()
        try FieldReferenceEraseIntentStorePolicyV1.validate()
        let root = applicationSupportURL.standardizedFileURL
        guard root.isFileURL else { throw EraseIntentStoreError.invalidAuthority }
        if expectedApplicationSupportIdentity == nil {
            try fileManager.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
        }
        let appDescriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard appDescriptor >= 0 else {
            throw EraseIntentStoreError.invalidAuthority
        }
        var ownsAppDescriptor = true
        defer {
            if ownsAppDescriptor { _ = Darwin.close(appDescriptor) }
        }
        let appIdentity = try Self.directoryIdentity(appDescriptor)
        if let expectedApplicationSupportIdentity {
            guard appIdentity.device == expectedApplicationSupportIdentity.device,
                  appIdentity.inode == expectedApplicationSupportIdentity.inode else {
                throw EraseIntentStoreError.invalidAuthority
            }
        }

        var eraseDescriptor = Darwin.openat(
            appDescriptor,
            Self.directoryName,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        if eraseDescriptor < 0, errno == ENOENT {
            guard Darwin.mkdirat(
                appDescriptor,
                Self.directoryName,
                mode_t(0o700)
            ) == 0 || errno == EEXIST else {
                throw EraseIntentStoreError.invalidAuthority
            }
            eraseDescriptor = Darwin.openat(
                appDescriptor,
                Self.directoryName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
        }
        guard eraseDescriptor >= 0 else {
            throw EraseIntentStoreError.invalidAuthority
        }
        var ownsEraseDescriptor = true
        defer {
            if ownsEraseDescriptor { _ = Darwin.close(eraseDescriptor) }
        }
        let eraseIdentity = try Self.directoryIdentity(eraseDescriptor)
        do {
            try ProtectedFilePolicyV1.applyAndVerify(
                .stagingDirectory,
                relativePath: Self.directoryName,
                within: root
            ) {
                guard try Self.directoryIdentity(appDescriptor) == appIdentity,
                      try Self.directoryIdentity(eraseDescriptor) == eraseIdentity else {
                    throw EraseIntentStoreError.invalidAuthority
                }
            }
        } catch {
            throw EraseIntentStoreError.invalidAuthority
        }

        self.applicationSupportURL = root
        self.applicationSupportDescriptor = appDescriptor
        self.applicationSupportIdentity = appIdentity
        self.eraseDescriptor = eraseDescriptor
        self.eraseIdentity = eraseIdentity
        ownsAppDescriptor = false
        ownsEraseDescriptor = false
    }

    deinit {
        _ = Darwin.close(eraseDescriptor)
        _ = Darwin.close(applicationSupportDescriptor)
    }

    func load() throws -> EraseIntentV1? {
        try verifyAuthority()
        try verifyExistingPolicy(.journal, name: Self.intentName)
        try verifyExistingPolicy(.journalTemporary, name: Self.nextName)
        let canonical = try readIfPresent(Self.intentName)
        let pending = try readIfPresent(Self.nextName)

        switch (canonical, pending) {
        case (nil, nil):
            return nil
        case (nil, let pending?):
            let value = try decode(pending.data)
            guard value.phase == .emptyGenerationPrepared,
                  Darwin.renameatx_np(
                    eraseDescriptor,
                    Self.nextName,
                    eraseDescriptor,
                    Self.intentName,
                    UInt32(RENAME_EXCL)
                  ) == 0,
                  Darwin.fsync(eraseDescriptor) == 0 else {
                throw EraseIntentStoreError.invalidIntent
            }
            try verifyPublishedPolicy(
                .journal,
                name: Self.intentName,
                failure: .invalidIntent,
                expectedIdentity: pending.identity
            )
            guard let promoted = try readIfPresent(Self.intentName),
                  promoted.identity == pending.identity,
                  promoted.data == pending.data else {
                throw EraseIntentStoreError.invalidIntent
            }
            try verifyAuthority()
            return value
        case (let canonical?, nil):
            return try decode(canonical.data)
        case (let canonical?, let pending?):
            let current = try decode(canonical.data)
            let next = try decode(pending.data)
            guard sameOperation(current, next),
                  next.phase == nextPhase(after: current.phase)
                    || current.phase == nextPhase(after: next.phase) else {
                throw EraseIntentStoreError.invalidIntent
            }
            try removeExact(Self.nextName, expected: pending)
            return current
        }
    }

    func loadPreparation() throws -> ErasePreparationV2? {
        try verifyAuthority()
        try verifyExistingPolicy(.journal, name: Self.preparationName)
        try verifyExistingPolicy(
            .journalTemporary,
            name: Self.preparationNextName
        )
        let canonical = try readIfPresent(Self.preparationName)
        let pending = try readIfPresent(Self.preparationNextName)

        switch (canonical, pending) {
        case (nil, nil):
            return nil
        case (nil, let pending?):
            let value = try decodePreparation(pending.data)
            guard Darwin.renameatx_np(
                eraseDescriptor,
                Self.preparationNextName,
                eraseDescriptor,
                Self.preparationName,
                UInt32(RENAME_EXCL)
            ) == 0,
                  Darwin.fsync(eraseDescriptor) == 0 else {
                throw EraseIntentStoreError.invalidPreparation
            }
            try verifyPublishedPolicy(
                .journal,
                name: Self.preparationName,
                failure: .invalidPreparation,
                expectedIdentity: pending.identity
            )
            guard let promoted = try readIfPresent(Self.preparationName),
                  promoted.identity == pending.identity,
                  promoted.data == pending.data else {
                throw EraseIntentStoreError.invalidPreparation
            }
            try verifyAuthority()
            return value
        case (let canonical?, nil):
            return try decodePreparation(canonical.data)
        case (let canonical?, let pending?):
            let current = try decodePreparation(canonical.data)
            let next = try decodePreparation(pending.data)
            guard isPreparationTransition(current, next)
                    || isPreparationTransition(next, current) else {
                throw EraseIntentStoreError.invalidPreparation
            }
            try removeExact(Self.preparationNextName, expected: pending)
            return current
        }
    }

    func createPreparation(_ value: ErasePreparationV2) throws {
        try verifyAuthority()
        try verifyExistingPolicy(.journal, name: Self.preparationName)
        try verifyExistingPolicy(
            .journalTemporary,
            name: Self.preparationNextName
        )
        guard try readIfPresent(Self.preparationName) == nil,
              try readIfPresent(Self.preparationNextName) == nil else {
            throw EraseIntentStoreError.preparationAlreadyExists
        }
        let data = try encodePreparation(value)
        let temporaryIdentity = try createLeaf(
            Self.preparationNextName,
            data: data
        )
        var published = false
        do {
            guard Darwin.renameatx_np(
                eraseDescriptor,
                Self.preparationNextName,
                eraseDescriptor,
                Self.preparationName,
                UInt32(RENAME_EXCL)
            ) == 0 else {
                throw EraseIntentStoreError.writeFailed
            }
            published = true
            guard Darwin.fsync(eraseDescriptor) == 0 else {
                throw EraseIntentStoreError.writeFailed
            }
            try verifyPublishedPolicy(
                .journal,
                name: Self.preparationName,
                failure: .writeFailed,
                expectedIdentity: temporaryIdentity
            )
            guard let written = try readIfPresent(Self.preparationName),
                  written.identity == temporaryIdentity,
                  written.data == data else {
                throw EraseIntentStoreError.writeFailed
            }
            try verifyAuthority()
        } catch {
            if published {
                try? removeExact(
                    Self.preparationName,
                    expected: (data: data, identity: temporaryIdentity)
                )
            }
            throw error
        }
    }

    func replacePreparation(
        expected: ErasePreparationV2,
        with replacement: ErasePreparationV2
    ) throws {
        try verifyAuthority()
        try verifyExistingPolicy(.journal, name: Self.preparationName)
        try verifyExistingPolicy(
            .journalTemporary,
            name: Self.preparationNextName
        )
        let expectedData = try encodePreparation(expected)
        let replacementData = try encodePreparation(replacement)
        guard isPreparationTransition(expected, replacement),
              let current = try readIfPresent(Self.preparationName),
              current.data == expectedData,
              try readIfPresent(Self.preparationNextName) == nil else {
            throw EraseIntentStoreError.preparationMismatch
        }
        let replacementIdentity = try createLeaf(
            Self.preparationNextName,
            data: replacementData
        )
        var swapped = false
        do {
            guard Darwin.renameatx_np(
                eraseDescriptor,
                Self.preparationNextName,
                eraseDescriptor,
                Self.preparationName,
                UInt32(RENAME_SWAP)
            ) == 0 else {
                throw EraseIntentStoreError.writeFailed
            }
            swapped = true
            guard Darwin.fsync(eraseDescriptor) == 0 else {
                throw EraseIntentStoreError.writeFailed
            }
            try verifyPublishedPolicy(
                .journal,
                name: Self.preparationName,
                failure: .writeFailed,
                expectedIdentity: replacementIdentity
            )
            try verifyPublishedPolicy(
                .journalTemporary,
                name: Self.preparationNextName,
                failure: .writeFailed,
                expectedIdentity: current.identity
            )
            guard let published = try readIfPresent(Self.preparationName),
                  let displaced = try readIfPresent(Self.preparationNextName),
                  published.identity == replacementIdentity,
                  published.data == replacementData,
                  displaced.identity == current.identity,
                  displaced.data == expectedData else {
                throw EraseIntentStoreError.writeFailed
            }
            try removeExact(Self.preparationNextName, expected: displaced)
            swapped = false
            try verifyAuthority()
        } catch {
            if swapped {
                do {
                    if let published = try readIfPresent(Self.preparationName),
                       let displaced = try readIfPresent(Self.preparationNextName),
                       published.identity == replacementIdentity,
                       published.data == replacementData,
                       displaced.identity == current.identity,
                       displaced.data == expectedData {
                        _ = Darwin.renameatx_np(
                            eraseDescriptor,
                            Self.preparationNextName,
                            eraseDescriptor,
                            Self.preparationName,
                            UInt32(RENAME_SWAP)
                        )
                        _ = Darwin.fsync(eraseDescriptor)
                    }
                } catch {
                    // Preserve uncertain state for recovery.
                }
            }
            try? removeIfExact(
                Self.preparationNextName,
                expected: replacementIdentity
            )
            throw error
        }
    }

    func removePreparation(expected: ErasePreparationV2) throws {
        try verifyAuthority()
        try verifyExistingPolicy(.journal, name: Self.preparationName)
        let data = try encodePreparation(expected)
        guard let current = try readIfPresent(Self.preparationName) else {
            throw EraseIntentStoreError.preparationMissing
        }
        guard current.data == data else {
            throw EraseIntentStoreError.preparationMismatch
        }
        try removeExact(Self.preparationName, expected: current)
        try verifyAuthority()
    }

    func create(_ value: EraseIntentV1) throws {
        try verifyAuthority()
        try verifyExistingPolicy(.journal, name: Self.intentName)
        try verifyExistingPolicy(.journalTemporary, name: Self.nextName)
        guard try readIfPresent(Self.intentName) == nil,
              try readIfPresent(Self.nextName) == nil else {
            throw EraseIntentStoreError.intentAlreadyExists
        }
        let data = try encode(value)
        let temporaryIdentity = try createLeaf(Self.nextName, data: data)
        var published = false
        do {
            guard Darwin.renameatx_np(
                eraseDescriptor,
                Self.nextName,
                eraseDescriptor,
                Self.intentName,
                UInt32(RENAME_EXCL)
            ) == 0 else {
                throw EraseIntentStoreError.writeFailed
            }
            published = true
            guard Darwin.fsync(eraseDescriptor) == 0 else {
                throw EraseIntentStoreError.writeFailed
            }
            try verifyPublishedPolicy(
                .journal,
                name: Self.intentName,
                failure: .writeFailed,
                expectedIdentity: temporaryIdentity
            )
            guard let publishedValue = try readIfPresent(Self.intentName),
                  publishedValue.identity == temporaryIdentity,
                  publishedValue.data == data else {
                throw EraseIntentStoreError.writeFailed
            }
            try verifyAuthority()
        } catch {
            if published {
                try? removeExact(
                    Self.intentName,
                    expected: (data: data, identity: temporaryIdentity)
                )
            }
            throw error
        }
    }

    func replace(
        expected: EraseIntentV1,
        with replacement: EraseIntentV1
    ) throws {
        try verifyAuthority()
        try verifyExistingPolicy(.journal, name: Self.intentName)
        try verifyExistingPolicy(.journalTemporary, name: Self.nextName)
        let expectedData = try encode(expected)
        let replacementData = try encode(replacement)
        guard sameOperation(expected, replacement),
              replacement.phase == nextPhase(after: expected.phase),
              let current = try readIfPresent(Self.intentName),
              current.data == expectedData,
              try readIfPresent(Self.nextName) == nil else {
            throw EraseIntentStoreError.intentMismatch
        }
        let replacementIdentity = try createLeaf(
            Self.nextName,
            data: replacementData
        )
        var swapped = false
        do {
            guard Darwin.renameatx_np(
                eraseDescriptor,
                Self.nextName,
                eraseDescriptor,
                Self.intentName,
                UInt32(RENAME_SWAP)
            ) == 0 else {
                throw EraseIntentStoreError.writeFailed
            }
            swapped = true
            guard Darwin.fsync(eraseDescriptor) == 0 else {
                throw EraseIntentStoreError.writeFailed
            }
            try verifyPublishedPolicy(
                .journal,
                name: Self.intentName,
                failure: .writeFailed,
                expectedIdentity: replacementIdentity
            )
            try verifyPublishedPolicy(
                .journalTemporary,
                name: Self.nextName,
                failure: .writeFailed,
                expectedIdentity: current.identity
            )
            guard
                  let published = try readIfPresent(Self.intentName),
                  let displaced = try readIfPresent(Self.nextName),
                  published.identity == replacementIdentity,
                  published.data == replacementData,
                  displaced.identity == current.identity,
                  displaced.data == expectedData else {
                throw EraseIntentStoreError.writeFailed
            }
            try removeExact(Self.nextName, expected: displaced)
            swapped = false
            try verifyAuthority()
        } catch {
            if swapped {
                do {
                    if let published = try readIfPresent(Self.intentName),
                       let displaced = try readIfPresent(Self.nextName),
                       published.identity == replacementIdentity,
                       published.data == replacementData,
                       displaced.identity == current.identity,
                       displaced.data == expectedData {
                        _ = Darwin.renameatx_np(
                            eraseDescriptor,
                            Self.nextName,
                            eraseDescriptor,
                            Self.intentName,
                            UInt32(RENAME_SWAP)
                        )
                        _ = Darwin.fsync(eraseDescriptor)
                    }
                } catch {
                    // Preserve the exact failure and leave uncertain state for recovery.
                }
            }
            try? removeIfExact(
                Self.nextName,
                expected: replacementIdentity
            )
            throw error
        }
    }

    func remove(expected: EraseIntentV1) throws {
        try verifyAuthority()
        try verifyExistingPolicy(.journal, name: Self.intentName)
        let data = try encode(expected)
        guard let current = try readIfPresent(Self.intentName) else {
            throw EraseIntentStoreError.intentMissing
        }
        guard current.data == data else {
            throw EraseIntentStoreError.intentMismatch
        }
        try removeExact(Self.intentName, expected: current)
        try verifyAuthority()
    }
}

private extension EraseIntentStore {
    func policyRelativePath(_ name: String) -> String {
        "\(Self.directoryName)/\(name)"
    }

    func verifyExistingPolicy(
        _ kind: OwnedFileKindV1,
        name: String
    ) throws {
        do {
            try verifyAuthority()
            let descriptor = Darwin.openat(
                eraseDescriptor,
                name,
                O_RDONLY | O_NOFOLLOW
            )
            if descriptor < 0, errno == ENOENT { return }
            guard descriptor >= 0 else {
                throw EraseIntentStoreError.invalidAuthority
            }
            defer { _ = Darwin.close(descriptor) }
            let expected = try Self.fileIdentity(descriptor)
            try ProtectedFilePolicyV1.applyAndVerify(
                kind,
                relativePath: policyRelativePath(name),
                within: applicationSupportURL
            ) {
                try verifyAuthority()
                try verifyLeaf(
                    name,
                    descriptor: descriptor,
                    expected: expected
                )
            }
        } catch {
            throw EraseIntentStoreError.invalidAuthority
        }
    }

    func applyTemporaryPolicy(
        _ kind: OwnedFileKindV1,
        name: String,
        descriptor: Int32
    ) throws {
        do {
            let expected = try Self.fileIdentity(descriptor)
            try ProtectedFilePolicyV1.applyAndVerify(
                kind,
                relativePath: policyRelativePath(name),
                within: applicationSupportURL
            ) {
                try verifyAuthority()
                try verifyLeaf(
                    name,
                    descriptor: descriptor,
                    expected: expected
                )
            }
        } catch {
            throw EraseIntentStoreError.writeFailed
        }
    }

    func verifyLeaf(
        _ name: String,
        descriptor: Int32,
        expected: Identity
    ) throws {
        guard try Self.fileIdentity(descriptor) == expected else {
            throw EraseIntentStoreError.invalidAuthority
        }
        var info = stat()
        guard Darwin.fstatat(
            eraseDescriptor,
            name,
            &info,
            AT_SYMLINK_NOFOLLOW
        ) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1,
              Identity(device: info.st_dev, inode: info.st_ino) == expected else {
            throw EraseIntentStoreError.invalidAuthority
        }
    }

    func verifyPublishedPolicy(
        _ kind: OwnedFileKindV1,
        name: String,
        failure: EraseIntentStoreError,
        expectedIdentity: Identity
    ) throws {
        let descriptor = Darwin.openat(
            eraseDescriptor,
            name,
            O_RDONLY | O_NOFOLLOW
        )
        guard descriptor >= 0 else { throw failure }
        defer { _ = Darwin.close(descriptor) }
        do {
            try verifyAuthority()
            try verifyLeaf(
                name,
                descriptor: descriptor,
                expected: expectedIdentity
            )
            try ProtectedFilePolicyV1.verify(
                kind,
                at: applicationSupportURL
                    .appendingPathComponent(Self.directoryName, isDirectory: true)
                    .appendingPathComponent(name)
            )
            try verifyAuthority()
            try verifyLeaf(
                name,
                descriptor: descriptor,
                expected: expectedIdentity
            )
        } catch {
            throw failure
        }
    }

    func verifyAuthority() throws {
        try Self.requireDirectory(
            applicationSupportDescriptor,
            identity: applicationSupportIdentity
        )
        try Self.requireDirectory(eraseDescriptor, identity: eraseIdentity)
        let reopenedApp = Darwin.open(
            applicationSupportURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard reopenedApp >= 0 else {
            throw EraseIntentStoreError.invalidAuthority
        }
        defer { _ = Darwin.close(reopenedApp) }
        guard try Self.directoryIdentity(reopenedApp) == applicationSupportIdentity else {
            throw EraseIntentStoreError.invalidAuthority
        }
        let reopenedErase = Darwin.openat(
            reopenedApp,
            Self.directoryName,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard reopenedErase >= 0 else {
            throw EraseIntentStoreError.invalidAuthority
        }
        defer { _ = Darwin.close(reopenedErase) }
        guard try Self.directoryIdentity(reopenedErase) == eraseIdentity else {
            throw EraseIntentStoreError.invalidAuthority
        }
    }

    func encode(_ value: EraseIntentV1) throws -> Data {
        do { return try EraseIntentCodecV1.encode(value) }
        catch { throw EraseIntentStoreError.invalidIntent }
    }

    func decode(_ data: Data) throws -> EraseIntentV1 {
        do { return try EraseIntentCodecV1.decode(data) }
        catch { throw EraseIntentStoreError.invalidIntent }
    }

    func encodePreparation(_ value: ErasePreparationV2) throws -> Data {
        do { return try ErasePreparationCodecV2.encode(value) }
        catch { throw EraseIntentStoreError.invalidPreparation }
    }

    func decodePreparation(_ data: Data) throws -> ErasePreparationV2 {
        do { return try ErasePreparationCodecV2.decode(data) }
        catch { throw EraseIntentStoreError.invalidPreparation }
    }

    func isPreparationTransition(
        _ current: ErasePreparationV2,
        _ next: ErasePreparationV2
    ) -> Bool {
        current.oldPointer == next.oldPointer
            && current.sourceLedger == next.sourceLedger
            && current.targetGenerationID == next.targetGenerationID
            && current.targetWorkspaceID == next.targetWorkspaceID
            && current.targetReplicaID == next.targetReplicaID
            && current.targetPointer == nil
            && next.targetPointer != nil
    }

    func sameOperation(_ lhs: EraseIntentV1, _ rhs: EraseIntentV1) -> Bool {
        lhs.auxiliaryRoots == rhs.auxiliaryRoots
            && lhs.eraseID == rhs.eraseID
            && lhs.generationIDsToDelete == rhs.generationIDsToDelete
            && lhs.newGenerationID == rhs.newGenerationID
            && lhs.oldGenerationID == rhs.oldGenerationID
            && lhs.oldPointer == rhs.oldPointer
            && lhs.schemaVersion == rhs.schemaVersion
            && lhs.sourceLedger == rhs.sourceLedger
            && lhs.targetEmptyProof == rhs.targetEmptyProof
            && lhs.targetPointer == rhs.targetPointer
    }

    func nextPhase(after phase: EraseIntentPhaseV1) -> EraseIntentPhaseV1? {
        switch phase {
        case .emptyGenerationPrepared: .pointerSwitched
        case .pointerSwitched: .sessionActivated
        case .sessionActivated: .cleanupComplete
        case .cleanupComplete: nil
        }
    }

    private func readIfPresent(
        _ name: String
    ) throws -> (data: Data, identity: Identity)? {
        let descriptor = Darwin.openat(
            eraseDescriptor,
            name,
            O_RDONLY | O_NOFOLLOW
        )
        if descriptor < 0, errno == ENOENT { return nil }
        guard descriptor >= 0 else {
            throw EraseIntentStoreError.invalidAuthority
        }
        defer { _ = Darwin.close(descriptor) }
        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1 else {
            throw EraseIntentStoreError.invalidAuthority
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count > 0 {
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                break
            } else if errno != EINTR {
                throw EraseIntentStoreError.invalidAuthority
            }
        }
        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              data.count == Int(after.st_size) else {
            throw EraseIntentStoreError.invalidAuthority
        }
        return (
            data,
            Identity(device: after.st_dev, inode: after.st_ino)
        )
    }

    func createLeaf(_ name: String, data: Data) throws -> Identity {
        let descriptor = Darwin.openat(
            eraseDescriptor,
            name,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard descriptor >= 0 else {
            throw EraseIntentStoreError.writeFailed
        }
        defer { _ = Darwin.close(descriptor) }
        let expectedIdentity = try Self.fileIdentity(descriptor)
        do {
            try applyTemporaryPolicy(
                .journalTemporary,
                name: name,
                descriptor: descriptor
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
                    } else if errno != EINTR {
                        throw EraseIntentStoreError.writeFailed
                    }
                }
            }
            guard Darwin.fsync(descriptor) == 0 else {
                throw EraseIntentStoreError.writeFailed
            }
            guard let written = try readIfPresent(name),
                  written.identity == expectedIdentity,
                  written.data == data else {
                throw EraseIntentStoreError.writeFailed
            }
            return written.identity
        } catch {
            try? removeIfExact(name, expected: expectedIdentity)
            throw error
        }
    }

    func removeIfExact(_ name: String, expected: Identity) throws {
        guard let current = try readIfPresent(name),
              current.identity == expected,
              Darwin.unlinkat(eraseDescriptor, name, 0) == 0,
              Darwin.fsync(eraseDescriptor) == 0,
              case nil = try readIfPresent(name) else {
            throw EraseIntentStoreError.cleanupFailed
        }
    }

    private func removeExact(
        _ name: String,
        expected: (data: Data, identity: Identity)
    ) throws {
        guard let current = try readIfPresent(name),
              current.identity == expected.identity,
              current.data == expected.data,
              Darwin.unlinkat(eraseDescriptor, name, 0) == 0,
              Darwin.fsync(eraseDescriptor) == 0 else {
            throw EraseIntentStoreError.cleanupFailed
        }
        guard case nil = try readIfPresent(name) else {
            throw EraseIntentStoreError.cleanupFailed
        }
    }

    private static func directoryIdentity(_ descriptor: Int32) throws -> Identity {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR else {
            throw EraseIntentStoreError.invalidAuthority
        }
        return Identity(device: info.st_dev, inode: info.st_ino)
    }

    private static func fileIdentity(_ descriptor: Int32) throws -> Identity {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1 else {
            throw EraseIntentStoreError.invalidAuthority
        }
        return Identity(device: info.st_dev, inode: info.st_ino)
    }

    private static func requireDirectory(
        _ descriptor: Int32,
        identity: Identity
    ) throws {
        guard try directoryIdentity(descriptor) == identity else {
            throw EraseIntentStoreError.invalidAuthority
        }
    }
}

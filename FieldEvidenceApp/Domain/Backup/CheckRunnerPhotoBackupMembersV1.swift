import Foundation

/// Closed transport names. Recognizing a name supplies no ownership: the
/// package validator must also prove its complete canonical/physical plan.
struct CheckRunnerPhotoBackupMemberKeyV1: Equatable, Hashable, Sendable {
    enum Role: String, CaseIterable, Hashable, Sendable {
        case rawBytes = "bin"
        case rawPublication = "raw-publication.json"
        case physicalEntry = "staging-entry.json"
        case stagedOriginal = "pair-staged-original.jpg"
        case stagedThumbnail = "pair-staged-thumbnail.jpg"
        case stagedPublication = "pair-staged-publication.json"
        case promotedOriginal = "pair-promoted-original.jpg"
        case promotedThumbnail = "pair-promoted-thumbnail.jpg"

        var mimeType: String {
            switch self {
            case .rawBytes: "application/octet-stream"
            case .rawPublication, .physicalEntry, .stagedPublication: "application/json"
            case .stagedOriginal, .stagedThumbnail, .promotedOriginal, .promotedThumbnail: "image/jpeg"
            }
        }

        var maximumByteCount: Int64 {
            switch self {
            case .rawBytes: Int64(MediaContractV1.sourceByteCountMaximum)
            case .rawPublication, .physicalEntry, .stagedPublication: Int64(FieldDraftLimitsV1.maximumCanonicalBytes)
            case .stagedOriginal, .promotedOriginal: Int64(MediaContractV1.OutputKind.original.byteCountMaximum)
            case .stagedThumbnail, .promotedThumbnail: Int64(MediaContractV1.OutputKind.thumbnail.byteCountMaximum)
            }
        }
    }

    let childDraftID: UUID
    let stageID: UUID
    let role: Role

    init(childDraftID: UUID, stageID: UUID, role: Role) {
        self.childDraftID = childDraftID
        self.stageID = stageID
        self.role = role
    }

    init?(path: String) {
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count == 3, components[0] == "draft-staging",
              let child = UUID(uuidString: components[1]), child.uuidString.lowercased() == components[1],
              let dot = components[2].firstIndex(of: ".") else { return nil }
        let stem = String(components[2][..<dot])
        let suffix = String(components[2][components[2].index(after: dot)...])
        guard let stage = UUID(uuidString: stem), stage.uuidString.lowercased() == stem,
              let role = Role(rawValue: suffix) else { return nil }
        self.init(childDraftID: child, stageID: stage, role: role)
        guard self.path == path else { return nil }
    }

    var path: String {
        "draft-staging/\(childDraftID.uuidString.lowercased())/\(stageID.uuidString.lowercased()).\(role.rawValue)"
    }

    func validate(_ entry: V4BackupEntryV1) throws {
        guard entry.path == path, entry.mimeType == role.mimeType,
              entry.byteCount > 0, Int64(entry.byteCount) <= role.maximumByteCount else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
    }
}

/// The physical manifest entry has its own phase and timestamp. Transport its
/// exact existing encoding, independently of the canonical staging row.
struct CheckRunnerPhotoBackupPhysicalEntryV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    let entry: DraftAttachmentStagingEntryV1

    init(entry: DraftAttachmentStagingEntryV1) throws {
        self.entry = entry
        try validate()
    }

    func validate() throws {
        try entry.item.validate()
        guard entry.item.attachmentKind == .photo,
              entry == (try DraftAttachmentStagingEntryV1(item: entry.item,
                relativeDataPath: entry.relativeDataPath, mediaType: entry.mediaType, updatedAt: entry.updatedAt)),
              entry.relativeDataPath == DraftAttachmentStagingAdapterV1.relativeDataPath(
                draftID: entry.item.draftID, stageID: entry.item.stageID) else {
            throw FieldDraftFailureV1.digestMismatch
        }
    }

    func encode(to encoder: Encoder) throws { try entry.encode(to: encoder) }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, item, relativeDataPath, mediaType, updatedAt
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == DraftAttachmentStagingEntryV1.schemaVersion else {
            throw FieldDraftFailureV1.invalidValue
        }
        let itemDecoder = try values.superDecoder(forKey: .item)
        try ClosedContractDecodingV1.rejectUnknownKeys(itemDecoder, allowed: [
            "schemaVersion", "stageID", "draftID", "workspaceID", "attachmentKind", "scratchLeaseID",
            "expectedByteCount", "actualByteCount", "contentDigest", "contentReference", "processingJobID",
            "retryClass", "protectionState", "state", "revision", "mutationID", "stageSHA256"
        ])
        try self.init(entry: DraftAttachmentStagingEntryV1(
            item: AttachmentStagingItemV1(from: itemDecoder),
            relativeDataPath: values.decode(String.self, forKey: .relativeDataPath),
            mediaType: values.decode(String.self, forKey: .mediaType),
            updatedAt: values.decode(Date.self, forKey: .updatedAt)))
    }
}

/// Value-only correspondence between authenticated history and actual archive
/// membership. Byte inspection and live root authority remain the caller's job.
struct CheckRunnerPhotoBackupPhysicalPlanV1: Equatable, Sendable {
    enum PairLocation: Equatable, Sendable {
        case absent
        case staged(markerPresent: Bool)
        case promoted
        case targetOwned
    }

    let childDraftID: UUID
    let stageID: UUID
    let physicalEntry: CheckRunnerPhotoBackupPhysicalEntryV1?
    let pairLocation: PairLocation
    let immutableRawPath: String?
    let entries: [V4BackupEntryV1]

    static func resolve(child: CheckRunnerPhotoBackupHistoryChildV1,
        descriptors: [String: V4BackupEntryV1], metadata: (String) throws -> Data) throws -> Self {
        let failure = BackupPackageValidationErrorV1.invalidPackage
        let payload = child.payload, intent = payload.phase.intent
        let childID = payload.childDraftID, stageID = intent.stageID
        func key(_ role: CheckRunnerPhotoBackupMemberKeyV1.Role) -> CheckRunnerPhotoBackupMemberKeyV1 {
            .init(childDraftID: childID, stageID: stageID, role: role)
        }
        let owned = descriptors.values.filter {
            CheckRunnerPhotoBackupMemberKeyV1(path: $0.path)?.childDraftID == childID
        }
        guard owned.allSatisfy({ CheckRunnerPhotoBackupMemberKeyV1(path: $0.path)?.stageID == stageID }) else {
            throw failure
        }
        for entry in owned {
            guard let member = CheckRunnerPhotoBackupMemberKeyV1(path: entry.path) else { throw failure }
            try member.validate(entry)
        }
        if let discard = child.discardHistory {
            // A pending cleanup can contain an interrupted subset of its original
            // files. It is not a complete backup until that transport is qualified.
            guard let terminal = discard.terminal,
                  terminal.checkpoint == child.currentCheckpoint,
                  terminal.receipt.disposedStageIDs == child.currentCheckpoint.stageIDs,
                  owned.isEmpty, child.target == nil, child.committingCheckpoint == nil else { throw failure }
            return .init(childDraftID: childID, stageID: stageID, physicalEntry: nil,
                         pairLocation: .absent, immutableRawPath: nil, entries: [])
        }
        guard let raw = child.raw else {
            guard case .awaitingRawStage = payload.phase, owned.isEmpty,
                  child.currentStage == nil, child.pair == nil, child.target == nil else { throw failure }
            return .init(childDraftID: childID, stageID: stageID, physicalEntry: nil,
                         pairLocation: .absent, immutableRawPath: nil, entries: [])
        }
        try raw.validate()
        var selected: [String: V4BackupEntryV1] = [:]
        func require(_ path: String, count: Int64? = nil, digest: String? = nil,
                     mime: String, maximum: Int64) throws -> V4BackupEntryV1 {
            guard let entry = descriptors[path], entry.path == path, entry.mimeType == mime,
                  entry.byteCount > 0, Int64(entry.byteCount) <= maximum,
                  count == nil || Int64(entry.byteCount) == count,
                  digest == nil || entry.sha256 == digest else { throw failure }
            selected[path] = entry
            return entry
        }
        func readMetadata(_ role: CheckRunnerPhotoBackupMemberKeyV1.Role) throws -> Data {
            let entry = try require(key(role).path, mime: role.mimeType, maximum: role.maximumByteCount)
            let bytes = try metadata(entry.path)
            guard bytes.count == entry.byteCount, CanonicalJSONV1.sha256(bytes) == entry.sha256 else { throw failure }
            return bytes
        }
        _ = try require(key(.rawBytes).path, count: raw.inspection.sourceByteCount,
            digest: raw.inspection.sourceSHA256.hexadecimalValue, mime: "application/octet-stream",
            maximum: CheckRunnerPhotoBackupMemberKeyV1.Role.rawBytes.maximumByteCount)
        let witness = try FieldDraftCanonicalCodecV1.decode(CheckRunnerPhotoRawReadyV1.self,
            from: readMetadata(.rawPublication))
        guard witness == raw else { throw failure }
        let physical = try FieldDraftCanonicalCodecV1.decode(CheckRunnerPhotoBackupPhysicalEntryV1.self,
            from: readMetadata(.physicalEntry))
        let readyEntry = try DraftAttachmentStagingEntryV1(item: raw.readyItem,
            relativeDataPath: DraftAttachmentStagingAdapterV1.relativeDataPath(draftID: childID, stageID: stageID),
            mediaType: raw.inspection.sourceMediaType, updatedAt: raw.intent.stageCreatedAt)
        let promotion = try child.committingCheckpoint.map { try DraftPhotoRawPromotionValuesV1(checkpoint: $0) }
        let physicalCommitted = promotion.map { physical.entry == $0.committedEntry } ?? false
        guard physical.entry == readyEntry || physicalCommitted else { throw failure }
        guard let currentStage = child.currentStage else { throw failure }
        let canonicalCommitted = promotion.map { currentStage == $0.committedStage } ?? false
        guard currentStage == raw.readyItem || canonicalCommitted,
              !canonicalCommitted || physicalCommitted else { throw failure }

        let rawPath = "content/\(raw.readyItem.workspaceID.rawValue.uuidString.lowercased())/\(raw.inspection.rawContentID)/original.bin"
        let hasImmutableRaw = descriptors[rawPath] != nil
        // A different child can already own this content-addressed original.
        // Only this child's authenticated COMMITTING request associates it with
        // this physical plan; global exact-member closure still requires an owner.
        let ownsImmutableRaw = hasImmutableRaw && promotion != nil
        if ownsImmutableRaw {
            guard let promotion, promotion.rawReady == raw else { throw failure }
            _ = try require(rawPath, count: promotion.request.byteLength,
                digest: promotion.request.digest.hexadecimalValue, mime: "application/octet-stream",
                maximum: CheckRunnerPhotoBackupMemberKeyV1.Role.rawBytes.maximumByteCount)
        }
        guard !(physicalCommitted || canonicalCommitted) || hasImmutableRaw else { throw failure }
        let contentPromoted = child.sagas.contains { $0.state == .contentPromotedUnbound }
        if contentPromoted {
            guard canonicalCommitted, hasImmutableRaw, let promotion,
                  child.reservations == [promotion.reservation] else { throw failure }
        }

        let location: PairLocation
        if let pair = child.pair {
            try pair.validate(childDraftID: childID, parentDraftID: payload.parentDraftID)
            guard pair.raw == raw else { throw failure }
            let normalized = pair.normalizedPair
            let originalPath: String, thumbnailPath: String
            if child.target != nil {
                guard contentPromoted, canonicalCommitted, physicalCommitted, hasImmutableRaw else { throw failure }
                location = .targetOwned
                originalPath = "media/\(normalized.evidenceID.uuidString.lowercased()).jpg"
                thumbnailPath = "thumbnails/\(normalized.evidenceID.uuidString.lowercased()).jpg"
            } else if descriptors[key(.promotedOriginal).path] != nil
                        || descriptors[key(.promotedThumbnail).path] != nil {
                guard contentPromoted, canonicalCommitted, physicalCommitted, hasImmutableRaw else { throw failure }
                location = .promoted
                originalPath = key(.promotedOriginal).path
                thumbnailPath = key(.promotedThumbnail).path
            } else {
                let markerPresent = descriptors[key(.stagedPublication).path] != nil
                guard markerPresent || (contentPromoted && canonicalCommitted && physicalCommitted && hasImmutableRaw) else {
                    throw failure
                }
                if markerPresent {
                    let bytes = try readMetadata(.stagedPublication)
                    let actual = try FieldDraftCanonicalCodecV1.decode(CheckRunnerPhotoPairPublicationMarkerV1.self, from: bytes)
                    let expected = try CheckRunnerPhotoPairPublicationMarkerV1(childDraftID: childID,
                        parentDraftID: payload.parentDraftID, raw: raw, normalizedPair: normalized)
                    guard actual == expected, CanonicalJSONV1.sha256(bytes) == pair.pairPublicationMarkerSHA256 else { throw failure }
                }
                location = .staged(markerPresent: markerPresent)
                originalPath = key(.stagedOriginal).path
                thumbnailPath = key(.stagedThumbnail).path
            }
            _ = try require(originalPath, count: normalized.originalByteCount, digest: normalized.originalSHA256,
                mime: "image/jpeg", maximum: CheckRunnerPhotoBackupMemberKeyV1.Role.stagedOriginal.maximumByteCount)
            _ = try require(thumbnailPath, count: normalized.thumbnailByteCount, digest: normalized.thumbnailSHA256,
                mime: "image/jpeg", maximum: CheckRunnerPhotoBackupMemberKeyV1.Role.stagedThumbnail.maximumByteCount)
        } else {
            guard case .rawReady = payload.phase, promotion == nil, !ownsImmutableRaw else { throw failure }
            location = .absent
        }
        let selectedDraftPaths = Set(selected.keys.filter { CheckRunnerPhotoBackupMemberKeyV1(path: $0) != nil })
        guard selectedDraftPaths == Set(owned.map(\.path)) else { throw failure }
        return .init(childDraftID: childID, stageID: stageID, physicalEntry: physical,
            pairLocation: location, immutableRawPath: ownsImmutableRaw ? rawPath : nil,
            entries: selected.values.sorted { $0.path < $1.path })
    }
}

/// The same-workspace restore projection preserves the source's physical
/// phases. Its paths describe owner operations; they grant no write authority.
struct CheckRunnerPhotoBackupRestorePlanV1: Equatable, Sendable {
    struct RawPublication: Equatable, Sendable {
        let physicalEntry: CheckRunnerPhotoBackupPhysicalEntryV1
        let payload: V4BackupEntryV1
        let witness: V4BackupEntryV1
        let witnessBytes: Data
    }

    struct GenerationMember: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case original, thumbnail, staging
            var protection: OwnedFileKindV1 {
                switch self {
                case .original: .mediaOriginal
                case .thumbnail: .mediaThumbnail
                case .staging: .stagingFile
                }
            }
        }
        let entry: V4BackupEntryV1
        let relativePath: String
        let kind: Kind
    }

    let source: V4BackupSourceV1
    let children: [CheckRunnerPhotoBackupPhysicalPlanV1]
    let rawPublications: [RawPublication]
    let generationMembers: [GenerationMember]
    let metadata: [String: Data]

    static func resolve(history: CheckRunnerPhotoBackupHistoryV1,
        entries: [V4BackupEntryV1], metadata read: (String) throws -> Data) throws -> Self {
        try resolve(source: history.source, children: history.children,
            entries: entries, metadata: read)
    }

    static func resolve(sourceSelection: CheckRunnerPhotoRestoreSourceSelectionV1,
        entries: [V4BackupEntryV1], metadata read: (String) throws -> Data) throws -> Self {
        try resolve(source: sourceSelection.source, children: sourceSelection.children,
            entries: entries, metadata: read)
    }

    fileprivate static func resolve(source: V4BackupSourceV1,
        children selectedChildren: [CheckRunnerPhotoBackupHistoryChildV1],
        entries: [V4BackupEntryV1], metadata read: (String) throws -> Data) throws -> Self {
        let failure = BackupPackageValidationErrorV1.invalidPackage
        guard Set(entries.map(\.path)).count == entries.count else { throw failure }
        let descriptors = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })
        var children: [CheckRunnerPhotoBackupPhysicalPlanV1] = []
        var rawPublications: [RawPublication] = []
        var generations: [String: GenerationMember] = [:]
        var metadata: [String: Data] = [:]
        func readMetadata(_ path: String) throws -> Data {
            if let existing = metadata[path] { return existing }
            let bytes = try read(path)
            guard let descriptor = descriptors[path], descriptor.byteCount == bytes.count,
                  descriptor.sha256 == CanonicalJSONV1.sha256(bytes),
                  bytes.count <= FieldDraftLimitsV1.maximumCanonicalBytes else { throw failure }
            metadata[path] = bytes
            return bytes
        }
        func include(_ entry: V4BackupEntryV1, at path: String,
            kind: GenerationMember.Kind) throws {
            let value = GenerationMember(entry: entry, relativePath: path, kind: kind)
            if let existing = generations[path], existing != value { throw failure }
            generations[path] = value
        }
        for child in selectedChildren {
            let plan = try CheckRunnerPhotoBackupPhysicalPlanV1.resolve(
                child: child, descriptors: descriptors, metadata: readMetadata)
            children.append(plan)
            func key(_ role: CheckRunnerPhotoBackupMemberKeyV1.Role) -> String {
                CheckRunnerPhotoBackupMemberKeyV1(childDraftID: plan.childDraftID,
                    stageID: plan.stageID, role: role).path
            }
            func entry(_ path: String) throws -> V4BackupEntryV1 {
                guard let value = plan.entries.first(where: { $0.path == path }) else { throw failure }
                return value
            }
            if let physical = plan.physicalEntry {
                rawPublications.append(.init(physicalEntry: physical,
                    payload: try entry(key(.rawBytes)), witness: try entry(key(.rawPublication)),
                    witnessBytes: try readMetadata(key(.rawPublication))))
            }
            if let path = plan.immutableRawPath {
                try include(entry(path), at: path, kind: .original)
            }
            let evidenceID = child.payload.phase.intent.evidenceID.uuidString.lowercased()
            switch plan.pairLocation {
            case .absent: break
            case .staged(let markerPresent):
                let directory = ".staging/evidence/\(evidenceID)"
                try include(entry(key(.stagedOriginal)), at: "\(directory)/original.jpg", kind: .staging)
                try include(entry(key(.stagedThumbnail)), at: "\(directory)/thumbnail.jpg", kind: .staging)
                if markerPresent {
                    try include(entry(key(.stagedPublication)),
                        at: "\(directory)/pair-publication.json", kind: .staging)
                }
            case .promoted:
                try include(entry(key(.promotedOriginal)),
                    at: "evidence/\(evidenceID)/original.jpg", kind: .original)
                try include(entry(key(.promotedThumbnail)),
                    at: "evidence/\(evidenceID)/thumbnail.jpg", kind: .thumbnail)
            case .targetOwned:
                guard let target = child.targetRecords?.evidence,
                      target.id == child.payload.phase.intent.evidenceID,
                      target.relativePath == "evidence/\(evidenceID)/original.jpg",
                      target.thumbnailRelativePath == "evidence/\(evidenceID)/thumbnail.jpg" else { throw failure }
                // The authenticated target retains the same immutable bundle
                // location as promotion; the archive uses its final row names.
                try include(entry("media/\(evidenceID).jpg"),
                    at: target.relativePath, kind: .original)
                try include(entry("thumbnails/\(evidenceID).jpg"),
                    at: target.thumbnailRelativePath, kind: .thumbnail)
            }
        }
        return .init(source: source, children: children,
            rawPublications: rawPublications.sorted {
                $0.physicalEntry.entry.item.stageID.uuidString < $1.physicalEntry.entry.item.stageID.uuidString
            }, generationMembers: generations.values.sorted { $0.relativePath < $1.relativePath },
            metadata: metadata)
    }
}

extension CheckRunnerPhotoBackupRestorePlanV1 {
    /// The current side of replacement uses the same closed member resolver as
    /// an archive. All physical values come from the incumbent read-only owners;
    /// this projection does not create an archive or normalize a photo.
    static func observed(history: CheckRunnerPhotoBackupHistoryV1,
        raw: [DraftPhotoRawBackupSnapshotV1], media: [CheckRunnerPhotoMediaBackupChildSnapshotV1]) throws -> Self {
        let failure = BackupPackageValidationErrorV1.invalidPackage
        guard Set(raw.map { $0.raw.readyItem.draftID }).count == raw.count,
              Set(media.map(\.childDraftID)).count == media.count,
              Set(raw.map { $0.raw.readyItem.draftID }) == Set(history.children.compactMap { $0.raw?.readyItem.draftID }),
              Set(media.map(\.childDraftID)) == Set(history.children.map { $0.payload.childDraftID }) else { throw failure }
        var entries: [String: V4BackupEntryV1] = [:], metadata: [String: Data] = [:]
        func include(_ entry: V4BackupEntryV1) throws {
            if let prior = entries[entry.path], prior != entry { throw failure }
            entries[entry.path] = entry
        }
        func includeMetadata(_ bytes: Data, key: CheckRunnerPhotoBackupMemberKeyV1) throws {
            guard metadata.updateValue(bytes, forKey: key.path) == nil else { throw failure }
            try include(.init(byteCount: bytes.count, mimeType: "application/json", path: key.path,
                sha256: CanonicalJSONV1.sha256(bytes)))
        }
        for snapshot in raw {
            let raw = snapshot.raw
            func key(_ role: CheckRunnerPhotoBackupMemberKeyV1.Role) -> CheckRunnerPhotoBackupMemberKeyV1 {
                .init(childDraftID: raw.readyItem.draftID, stageID: raw.intent.stageID, role: role)
            }
            guard let count = Int(exactly: raw.inspection.sourceByteCount) else { throw failure }
            try include(.init(byteCount: count, mimeType: "application/octet-stream", path: key(.rawBytes).path,
                sha256: raw.inspection.sourceSHA256.hexadecimalValue))
            try includeMetadata(FieldDraftCanonicalCodecV1.encode(raw), key: key(.rawPublication))
            try includeMetadata(FieldDraftCanonicalCodecV1.encode(snapshot.physicalEntry), key: key(.physicalEntry))
        }
        for snapshot in media {
            if let bytes = snapshot.markerBytes {
                let key = CheckRunnerPhotoBackupMemberKeyV1(childDraftID: snapshot.childDraftID,
                    stageID: snapshot.stageID, role: .stagedPublication)
                // Its file descriptor below is the same bounded physical marker.
                guard metadata.updateValue(bytes, forKey: key.path) == nil else { throw failure }
            }
            for file in snapshot.files { try include(file.entry) }
        }
        return try resolve(history: history, entries: entries.values.sorted { $0.path < $1.path }) { path in
            guard let bytes = metadata[path] else { throw failure }
            return bytes
        }
    }
}

/// Durable values in the incumbent restore publication binding. They describe
/// the exact source photo subset; only a fresh complete canonical history proof
/// can resolve them into a restore plan. Decoding this value grants no effects.
struct CheckRunnerPhotoRestoreMemberBindingV1: Codable, Equatable, Sendable {
    struct Metadata: Codable, Equatable, Sendable {
        let path: String
        let bytes: Data

        private enum CodingKeys: String, CodingKey { case path, bytes }

        init(path: String, bytes: Data) { self.path = path; self.bytes = bytes }

        init(from decoder: Decoder) throws {
            try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: ["path", "bytes"])
            let values = try decoder.container(keyedBy: CodingKeys.self)
            path = try values.decode(String.self, forKey: .path)
            bytes = try values.decode(Data.self, forKey: .bytes)
        }
    }

    let schemaVersion: Int
    let source: V4BackupSourceV1
    let childDraftIDs: [UUID]
    let entries: [V4BackupEntryV1]
    let metadata: [Metadata]

    private enum CodingKeys: String, CodingKey { case schemaVersion, source, childDraftIDs, entries, metadata }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder,
            allowed: ["schemaVersion", "source", "childDraftIDs", "entries", "metadata"])
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        source = try values.decode(V4BackupSourceV1.self, forKey: .source)
        childDraftIDs = try values.decode([UUID].self, forKey: .childDraftIDs)
        entries = try values.decode([V4BackupEntryV1].self, forKey: .entries)
        metadata = try values.decode([Metadata].self, forKey: .metadata)
    }

    init(plan: CheckRunnerPhotoBackupRestorePlanV1) throws {
        schemaVersion = 1
        source = plan.source
        childDraftIDs = plan.children.map(\.childDraftID).sorted { $0.uuidString < $1.uuidString }
        guard Set(childDraftIDs).count == childDraftIDs.count else {
            throw BackupPackageValidationErrorV1.invalidPackage
        }
        var byPath: [String: V4BackupEntryV1] = [:]
        for entry in plan.children.flatMap(\.entries) {
            if let existing = byPath[entry.path], existing != entry {
                throw BackupPackageValidationErrorV1.invalidPackage
            }
            byPath[entry.path] = entry
        }
        entries = byPath.values.sorted { $0.path < $1.path }
        metadata = plan.metadata.keys.sorted().map { .init(path: $0, bytes: plan.metadata[$0]!) }
    }

    func resolve(history: CheckRunnerPhotoBackupHistoryV1) throws -> CheckRunnerPhotoBackupRestorePlanV1 {
        try resolve(source: history.source, children: history.children)
    }

    func resolve(sourceSelection: CheckRunnerPhotoRestoreSourceSelectionV1) throws
        -> CheckRunnerPhotoBackupRestorePlanV1 {
        try resolve(source: sourceSelection.source, children: sourceSelection.children)
    }

    private func resolve(source expectedSource: V4BackupSourceV1,
        children: [CheckRunnerPhotoBackupHistoryChildV1]) throws -> CheckRunnerPhotoBackupRestorePlanV1 {
        let failure = BackupPackageValidationErrorV1.invalidPackage
        guard schemaVersion == 1, source == expectedSource,
              childDraftIDs == children.map({ $0.payload.childDraftID }).sorted(by: { $0.uuidString < $1.uuidString }),
              Set(childDraftIDs).count == childDraftIDs.count,
              entries == entries.sorted(by: { $0.path < $1.path }),
              Set(entries.map(\.path)).count == entries.count,
              metadata == metadata.sorted(by: { $0.path < $1.path }),
              Set(metadata.map(\.path)).count == metadata.count,
              metadata.allSatisfy({ value in
                  guard let key = CheckRunnerPhotoBackupMemberKeyV1(path: value.path) else { return false }
                  return [.rawPublication, .physicalEntry, .stagedPublication].contains(key.role)
                    && !value.bytes.isEmpty
                    && Int64(value.bytes.count) <= key.role.maximumByteCount
              }) else { throw failure }
        let bytes = Dictionary(uniqueKeysWithValues: metadata.map { ($0.path, $0.bytes) })
        let plan = try CheckRunnerPhotoBackupRestorePlanV1.resolve(source: source, children: children, entries: entries) {
            guard let value = bytes[$0] else { throw failure }
            return value
        }
        // No unused member or metadata survives a decode/recovery boundary.
        guard try Self(plan: plan) == self else { throw failure }
        return plan
    }
}

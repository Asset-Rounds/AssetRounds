import Foundation

enum KernelPersistenceV4Failure: Error, Equatable, Sendable {
    case invalidValue
    case hostileText
    case unknownField
    case incompleteCoverage
    case duplicateIdentity
    case unmappedRelationship
    case incompatibleSourceVersion
    case futureVersion
    case invalidTransition
    case digestMismatch
    case downgradeProhibited
    case partialActivation
    case forwardFixRequired
}

private struct KernelPersistenceV4AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

enum KernelPersistenceV4Validation {
    static let schemaID = "KERNEL_PERSISTENCE_V4"
    static let schemaVersion = 4
    static let predecessorSchemaVersion = 3

    static func validText(_ value: String, maximumUTF8Bytes: Int = 256) -> Bool {
        guard !value.isEmpty, value.utf8.count <= maximumUTF8Bytes,
              value == value.precomposedStringWithCanonicalMapping else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return value >= 0x20
                && value != 0x7f
                && !(0x80...0x9f).contains(value)
                && ![0x202a, 0x202b, 0x202c, 0x202d, 0x202e, 0x2066, 0x2067, 0x2068, 0x2069].contains(value)
                && (value & 0xffff) != 0xfffe
                && (value & 0xffff) != 0xffff
        }
    }

    static func validID(_ value: String) -> Bool {
        validText(value, maximumUTF8Bytes: 160) && value.utf8.allSatisfy {
            (0x41...0x5a).contains($0) || (0x61...0x7a).contains($0)
                || (0x30...0x39).contains($0) || [0x2d, 0x2e, 0x3a, 0x5f].contains($0)
        }
    }

    static func rejectUnknownKeys<K: CodingKey & CaseIterable>(
        _ decoder: Decoder,
        keys: K.Type
    ) throws where K.AllCases: Collection {
        let allowed = Set(K.allCases.map(\.stringValue))
        let observed = Set(try decoder.container(keyedBy: KernelPersistenceV4AnyCodingKey.self).allKeys.map(\.stringValue))
        guard observed.isSubset(of: allowed) else { throw KernelPersistenceV4Failure.unknownField }
    }

    static func decodeAbsentOrValue<T: Decodable, K: CodingKey>(
        _ type: T.Type,
        from values: KeyedDecodingContainer<K>,
        forKey key: K
    ) throws -> T? {
        guard values.contains(key) else { return nil }
        guard try !values.decodeNil(forKey: key) else {
            throw KernelPersistenceV4Failure.invalidValue
        }
        return try values.decode(T.self, forKey: key)
    }

    static func canonicalDigest<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return KernelCanonicalHashV1.sha256(try encoder.encode(value))
    }
}

enum KernelPersistenceV4RecordKind: String, Codable, CaseIterable, Hashable, Comparable, Sendable {
    case asset = "Asset"
    case completedActivitySnapshot = "CompletedActivitySnapshotV1"
    case contentReference = "ContentReferenceV1"
    case contractSchemaDerivationReceipt = "ContractSchemaDerivationReceiptV1"
    case controlledAmendmentSupersession = "ControlledAmendmentSupersessionV1"
    case deletionLedgerRow = "DeletionLedgerRow"
    case entityMutationRevisionRow = "EntityMutationRevisionRow"
    case evidenceFile = "EvidenceFile"
    case issue = "Issue"
    case mutationQuarantineRow = "MutationQuarantineRow"
    case mutationReceiptRow = "MutationReceiptRow"
    case observationAndTimeRow = "ObservationAndTimeRow"
    case openJSONSchemaProjection = "OpenJSONSchemaProjectionV1"
    case packet = "Packet"
    case persistentSchemaReleaseMarker = "PersistentSchemaReleaseMarker"
    case report = "Report"
    case site = "Site"
    case workflowRecord = "WorkflowRecord"
    case workspaceMutationStateRow = "WorkspaceMutationStateRow"

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum KernelPersistenceV4RelationshipKind: String, Codable, CaseIterable, Hashable, Comparable, Sendable {
    case assetSite = "Asset.siteID->Site"
    case completedSnapshotSupersedes = "CompletedActivitySnapshotV1.supersedesSnapshotID->CompletedActivitySnapshotV1"
    case controlledAmendmentOriginal = "ControlledAmendmentSupersessionV1.originalSnapshotID->CompletedActivitySnapshotV1"
    case controlledAmendmentSuccessor = "ControlledAmendmentSupersessionV1.successorSnapshotID->CompletedActivitySnapshotV1"
    case evidenceRecord = "EvidenceFile.recordID->WorkflowRecord"
    case issueAsset = "Issue.assetID->Asset"
    case issueOpenedBy = "Issue.openedByRecordID->WorkflowRecord"
    case issueResolvedBy = "Issue.resolvedByRecordID->WorkflowRecord"
    case packetCurrentRecord = "Packet.currentRecordID->WorkflowRecord"
    case packetStableRoot = "Packet.stableRootID->Packet"
    case reportPacket = "Report.packetID->Packet"
    case reportReplaces = "Report.replacesReportID->Report"
    case reportSourceRecord = "Report.sourceRecordID->WorkflowRecord"
    case workflowAsset = "WorkflowRecord.assetID->Asset"
    case workflowEvidenceSource = "WorkflowRecord.evidenceSourceRecordID->WorkflowRecord"
    case workflowIssue = "WorkflowRecord.issueID->Issue"
    case workflowPacket = "WorkflowRecord.packetID->Packet"
    case workflowParent = "WorkflowRecord.parentRecordID->WorkflowRecord"
    case workflowRevisionRoot = "WorkflowRecord.recordRevisionRootID->WorkflowRecord"
    case workflowRevises = "WorkflowRecord.revisesRecordID->WorkflowRecord"

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum KernelPersistenceV4Classification: String, Codable, CaseIterable, Sendable {
    case canonicalWorkspace = "CANONICAL_WORKSPACE"
    case immutableContentMetadata = "IMMUTABLE_CONTENT_METADATA"
    case appendOnlyReceipt = "APPEND_ONLY_RECEIPT"
    case deviceLocalOperational = "DEVICE_LOCAL_OPERATIONAL"
    case recoveryJournal = "RECOVERY_JOURNAL"
    case dormantContractDeclaration = "DORMANT_CONTRACT_DECLARATION"
}

enum KernelPersistenceV4LifecycleRequirement: String, Codable, CaseIterable, Hashable, Comparable, Sendable {
    case archive = "ARCHIVE"
    case backup = "BACKUP"
    case canonicalMutation = "CANONICAL_MUTATION"
    case classification = "CLASSIFICATION"
    case clone = "CLONE"
    case conflictPolicy = "CONFLICT_POLICY"
    case controlledAmendment = "CONTROLLED_AMENDMENT"
    case delete = "DELETE"
    case erase = "ERASE"
    case export = "EXPORT"
    case fork = "FORK"
    case mutationEnvelope = "MUTATION_ENVELOPE"
    case mutationReceipt = "MUTATION_RECEIPT"
    case orphanCleanup = "ORPHAN_CLEANUP"
    case readRecovery = "READ_RECOVERY"
    case rebuild = "REBUILD"
    case replay = "REPLAY"
    case replicationPolicy = "REPLICATION_POLICY"
    case restore = "RESTORE"
    case search = "SEARCH"
    case syncClassification = "SYNC_CLASSIFICATION"
    case writerRegistration = "WRITER_REGISTRATION"

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum KernelPersistenceV4DeleteRule: String, Codable, CaseIterable, Sendable {
    case preserveUnlessExplicit = "PRESERVE_UNLESS_EXPLICIT"
    case deleteAfterDependents = "DELETE_AFTER_DEPENDENTS"
    case deleteWithOwner = "DELETE_WITH_OWNER"
    case tombstoneWhenCounted = "TOMBSTONE_WHEN_COUNTED"
    case appendEraseOnly = "APPEND_ERASE_ONLY"
    case clearOnErase = "CLEAR_ON_ERASE"
}

struct KernelPersistenceV4RecordDescriptor: Codable, Equatable, Comparable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, classification, deleteRule, requirements, canonicalMutationEffectID
        case contentReferenceMapped, controlledAmendmentMapped
    }

    let kind: KernelPersistenceV4RecordKind
    let classification: KernelPersistenceV4Classification
    let deleteRule: KernelPersistenceV4DeleteRule
    let requirements: [KernelPersistenceV4LifecycleRequirement]
    let canonicalMutationEffectID: String
    let contentReferenceMapped: Bool
    let controlledAmendmentMapped: Bool

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.kind < rhs.kind }

    init(
        kind: KernelPersistenceV4RecordKind,
        classification: KernelPersistenceV4Classification,
        deleteRule: KernelPersistenceV4DeleteRule,
        canonicalMutationEffectID: String,
        contentReferenceMapped: Bool,
        controlledAmendmentMapped: Bool,
        requirements: [KernelPersistenceV4LifecycleRequirement] = KernelPersistenceV4LifecycleRequirement.allCases.sorted()
    ) throws {
        self.kind = kind
        self.classification = classification
        self.deleteRule = deleteRule
        self.requirements = requirements
        self.canonicalMutationEffectID = canonicalMutationEffectID
        self.contentReferenceMapped = contentReferenceMapped
        self.controlledAmendmentMapped = controlledAmendmentMapped
        try validate()
    }

    init(from decoder: Decoder) throws {
        try KernelPersistenceV4Validation.rejectUnknownKeys(decoder, keys: CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = try values.decode(KernelPersistenceV4RecordKind.self, forKey: .kind)
        classification = try values.decode(KernelPersistenceV4Classification.self, forKey: .classification)
        deleteRule = try values.decode(KernelPersistenceV4DeleteRule.self, forKey: .deleteRule)
        requirements = try values.decode([KernelPersistenceV4LifecycleRequirement].self, forKey: .requirements)
        canonicalMutationEffectID = try values.decode(String.self, forKey: .canonicalMutationEffectID)
        contentReferenceMapped = try values.decode(Bool.self, forKey: .contentReferenceMapped)
        controlledAmendmentMapped = try values.decode(Bool.self, forKey: .controlledAmendmentMapped)
        try validate()
    }

    func validate() throws {
        guard requirements == KernelPersistenceV4LifecycleRequirement.allCases.sorted(),
              Set(requirements).count == requirements.count,
              KernelPersistenceV4Validation.validID(canonicalMutationEffectID) else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}

struct KernelPersistenceV4RelationshipDescriptor: Codable, Equatable, Comparable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, source, fieldName, target, optional, scalarUUID, deleteRule
    }

    let kind: KernelPersistenceV4RelationshipKind
    let source: KernelPersistenceV4RecordKind
    let fieldName: String
    let target: KernelPersistenceV4RecordKind
    let optional: Bool
    let scalarUUID: Bool
    let deleteRule: KernelPersistenceV4DeleteRule

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.kind < rhs.kind }

    init(
        kind: KernelPersistenceV4RelationshipKind,
        source: KernelPersistenceV4RecordKind,
        fieldName: String,
        target: KernelPersistenceV4RecordKind,
        optional: Bool,
        deleteRule: KernelPersistenceV4DeleteRule
    ) throws {
        self.kind = kind
        self.source = source
        self.fieldName = fieldName
        self.target = target
        self.optional = optional
        scalarUUID = true
        self.deleteRule = deleteRule
        try validate()
    }

    init(from decoder: Decoder) throws {
        try KernelPersistenceV4Validation.rejectUnknownKeys(decoder, keys: CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = try values.decode(KernelPersistenceV4RelationshipKind.self, forKey: .kind)
        source = try values.decode(KernelPersistenceV4RecordKind.self, forKey: .source)
        fieldName = try values.decode(String.self, forKey: .fieldName)
        target = try values.decode(KernelPersistenceV4RecordKind.self, forKey: .target)
        optional = try values.decode(Bool.self, forKey: .optional)
        scalarUUID = try values.decode(Bool.self, forKey: .scalarUUID)
        deleteRule = try values.decode(KernelPersistenceV4DeleteRule.self, forKey: .deleteRule)
        try validate()
    }

    func validate() throws {
        guard KernelPersistenceV4Validation.validID(fieldName), scalarUUID,
              kind.rawValue == "\(source.rawValue).\(fieldName)->\(target.rawValue)" else {
            throw KernelPersistenceV4Failure.unmappedRelationship
        }
    }
}

enum KernelPersistenceV4RuntimePosture: String, Codable, Sendable {
    case dormantStatic = "DORMANT_STATIC_UNTIL_S10_6"
}

enum KernelPersistenceV4DowngradePolicy: String, Codable, Sendable {
    case preactivationDiscardOnly = "PREACTIVATION_DISCARD_ONLY"
    case forwardFixReadExportOnly = "FORWARD_FIX_READ_EXPORT_ONLY_AFTER_PUBLICATION_OR_WRITE"
}

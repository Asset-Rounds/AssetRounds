import Foundation

enum SyncClassificationV1: String, Codable, CaseIterable, Sendable {
    case replicated = "REPLICATED"
    case localOnly = "LOCAL_ONLY"
    case derivedRebuildable = "DERIVED_REBUILDABLE"
    case contentBlob = "CONTENT_BLOB"
    case privateDeviceOnly = "PRIVATE_DEVICE_ONLY"
}

enum SyncSubjectCategoryV1: String, Codable, CaseIterable, Sendable {
    case persistentModel = "PERSISTENT_MODEL"
    case ownedFileClass = "OWNED_FILE_CLASS"
    case journal = "JOURNAL"
    case index = "INDEX"
    case projection = "PROJECTION"
    case diagnostic = "DIAGNOSTIC"
    case secret = "SECRET"
}

struct SyncSubjectIdentityV1: Codable, Equatable, Hashable, Sendable {
    let category: SyncSubjectCategoryV1
    let stableName: String

    init(category: SyncSubjectCategoryV1, stableName: String) throws {
        guard ReplicationContractValidationV1.validToken(stableName) else {
            throw SyncClassificationRegistryFailureV1.invalidSubject
        }
        self.category = category
        self.stableName = stableName
    }

    var canonicalKey: String { category.rawValue + ":" + stableName }

    private enum CodingKeys: String, CodingKey { case category, stableName }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            category: container.decode(SyncSubjectCategoryV1.self, forKey: .category),
            stableName: container.decode(String.self, forKey: .stableName)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(category, forKey: .category)
        try container.encode(stableName, forKey: .stableName)
    }
}

struct SyncClassificationRegistrationV1: Codable, Equatable, Sendable {
    let subject: SyncSubjectIdentityV1
    let classification: SyncClassificationV1
    let replicationPolicy: ReplicationPolicyV1
    let conflictPolicy: ConflictPolicyV1

    init(
        subject: SyncSubjectIdentityV1,
        classification: SyncClassificationV1,
        replicationPolicy: ReplicationPolicyV1,
        conflictPolicy: ConflictPolicyV1
    ) throws {
        self.subject = subject
        self.classification = classification
        self.replicationPolicy = replicationPolicy
        self.conflictPolicy = conflictPolicy
        try validate()
    }

    func validate() throws {
        try replicationPolicy.validate()
        try conflictPolicy.validate()
        switch classification {
        case .replicated:
            guard replicationPolicy.transport == .futureAcceptedMutationEligible,
                  conflictPolicy.rule != .localOnly,
                  conflictPolicy.rule != .derivedRebuild else {
                throw SyncClassificationRegistryFailureV1.conflictingPolicy
            }
        case .contentBlob:
            guard replicationPolicy.transport == .futureBoundedBlobEligible,
                  replicationPolicy.persistence == .ownedFile,
                  conflictPolicy.rule == .immutableVersion else {
                throw SyncClassificationRegistryFailureV1.conflictingPolicy
            }
        case .localOnly:
            guard replicationPolicy.transport == .excluded,
                  conflictPolicy.rule == .localOnly else {
                throw SyncClassificationRegistryFailureV1.conflictingPolicy
            }
        case .derivedRebuildable:
            guard replicationPolicy.transport == .excluded,
                  conflictPolicy.rule == .derivedRebuild else {
                throw SyncClassificationRegistryFailureV1.conflictingPolicy
            }
        case .privateDeviceOnly:
            guard replicationPolicy.transport == .excluded,
                  replicationPolicy.export == .exclude,
                  conflictPolicy.rule == .localOnly else {
                throw SyncClassificationRegistryFailureV1.conflictingPolicy
            }
        }
    }
}

enum SyncClassificationRegistryV1 {
    static let schemaVersion = 1
    static let schemaID = "SYNC_REPLICATION_CONFLICT_POLICY_V1"
    static let maximumRegistrationCount = 128

    /// Declaration-only inventory. A throwing getter keeps malformed policy
    /// construction fail-closed instead of installing a permissive default.
    static var registrations: [SyncClassificationRegistrationV1] {
        get throws { try makeRegistrations() }
    }

    /// There are no application-owned secret artifacts at this release. The
    /// empty inventory is asserted explicitly by registry validation/tests.
    static let declaredSecretSubjects: [SyncSubjectIdentityV1] = []

    static func registration(
        for subject: SyncSubjectIdentityV1
    ) throws -> SyncClassificationRegistrationV1 {
        let matches = try registrations.filter { $0.subject == subject }
        guard matches.count == 1, let value = matches.first else {
            throw SyncClassificationRegistryFailureV1.unregisteredOrDuplicateSubject
        }
        return value
    }

    static func validate() throws {
        let values = try registrations
        guard !values.isEmpty, values.count <= maximumRegistrationCount else {
            throw SyncClassificationRegistryFailureV1.invalidRegistrationCount
        }
        let keys = values.map(\.subject.canonicalKey)
        guard keys == keys.sorted(), Set(keys).count == keys.count else {
            throw SyncClassificationRegistryFailureV1.unregisteredOrDuplicateSubject
        }
        try values.forEach { try $0.validate() }
        guard declaredSecretSubjects.isEmpty,
              Set(values.filter { $0.subject.category == .persistentModel }.map { $0.subject.stableName })
                == Set(persistentModelNames),
              Set(values.filter { $0.subject.category == .ownedFileClass }.map { $0.subject.stableName })
                == Set(ownedFileClassNames) else {
            throw SyncClassificationRegistryFailureV1.incompleteInventory
        }
    }

    static let persistentModelNames = [
        "Asset", "DeletionLedgerRow", "EntityMutationRevisionRow", "EvidenceFile",
        "Issue", "MutationQuarantineRow", "MutationReceiptRow", "Packet",
        "PersistentSchemaReleaseMarker", "Report", "Site", "WorkflowRecord",
        "WorkspaceMutationStateRow",
    ]

    static let ownedFileClassNames = [
        "cache", "commerceEntitlementCache", "database", "databaseSHM", "databaseWAL",
        "diagnostics", "durableDirectory", "generationPointer", "generationPointerTemporary",
        "journal", "journalTemporary", "mediaOriginal", "mediaThumbnail", "reportPDF",
        "reportSnapshot", "restoreStaging", "scratch", "stagingDirectory", "stagingFile",
        "temporaryFile",
    ]

    private static func makeRegistrations() throws -> [SyncClassificationRegistrationV1] {
        var values: [SyncClassificationRegistrationV1] = []

        for name in persistentModelNames {
            let disposition = try persistentModelDisposition(forStableName: name)
            values.append(try registration(
                category: .persistentModel,
                name: name,
                classification: disposition.classification,
                rule: disposition.conflictRule,
                persistence: .swiftDataRecord
            ))
        }

        for name in ownedFileClassNames {
            let disposition = try ownedFileDisposition(forStableName: name)
            values.append(try registration(
                category: .ownedFileClass,
                name: name,
                classification: disposition.classification,
                rule: disposition.conflictRule,
                persistence: .ownedFile
            ))
        }

        for name in [
            "deletionIntent", "eraseIntent", "finalizationIntent", "mutationReceipt",
            "restoreIntent", "storeMigration",
        ] {
            values.append(try registration(
                category: .journal, name: name, classification: .localOnly,
                rule: .localOnly, persistence: .ownedFile
            ))
        }

        for name in ["reportHistoryChronology"] {
            values.append(try registration(
                category: .index, name: name, classification: .derivedRebuildable,
                rule: .derivedRebuild, persistence: .nonpersistent
            ))
        }
        for name in ["entityMutationRevision", "workspaceMutationState"] {
            values.append(try registration(
                category: .projection, name: name, classification: .derivedRebuildable,
                rule: .derivedRebuild, persistence: .swiftDataRecord
            ))
        }
        values.append(try registration(
            category: .diagnostic, name: "diagnosticCounters",
            classification: .privateDeviceOnly, rule: .localOnly, persistence: .ownedFile
        ))
        return values.sorted { $0.subject.canonicalKey < $1.subject.canonicalKey }
    }

    /// Exact current-schema mapping seam for hostile completeness tests. It is
    /// deliberately immutable and throws for every name outside the V4 list.
    static func persistentModelDisposition(
        forStableName name: String
    ) throws -> (classification: SyncClassificationV1, conflictRule: ConflictRuleV1) {
        switch name {
        case "DeletionLedgerRow": return (.replicated, .deleteWins)
        case "MutationReceiptRow": return (.replicated, .stableIDAppendUnion)
        case "EntityMutationRevisionRow": return (.derivedRebuildable, .derivedRebuild)
        case "MutationQuarantineRow", "WorkspaceMutationStateRow", "PersistentSchemaReleaseMarker":
            return (.localOnly, .localOnly)
        case "Asset", "EvidenceFile", "Issue", "Packet", "Report", "Site", "WorkflowRecord":
            return (.replicated, .exactRevisionManual)
        default:
            throw SyncClassificationRegistryFailureV1.incompleteInventory
        }
    }

    /// Exact current owned-file mapping seam; unknown future file classes are
    /// rejected until the closed registry is explicitly versioned.
    static func ownedFileDisposition(
        forStableName name: String
    ) throws -> (classification: SyncClassificationV1, conflictRule: ConflictRuleV1) {
        switch name {
        case "mediaOriginal", "reportPDF", "reportSnapshot":
            return (.contentBlob, .immutableVersion)
        case "mediaThumbnail", "cache", "scratch":
            return (.derivedRebuildable, .derivedRebuild)
        case "diagnostics", "commerceEntitlementCache":
            return (.privateDeviceOnly, .localOnly)
        case "database", "databaseSHM", "databaseWAL", "durableDirectory",
             "generationPointer", "generationPointerTemporary", "journal",
             "journalTemporary", "restoreStaging", "stagingDirectory", "stagingFile",
             "temporaryFile":
            return (.localOnly, .localOnly)
        default:
            throw SyncClassificationRegistryFailureV1.incompleteInventory
        }
    }

    private static func registration(
        category: SyncSubjectCategoryV1,
        name: String,
        classification: SyncClassificationV1,
        rule: ConflictRuleV1,
        persistence: ReplicationPersistenceV1
    ) throws -> SyncClassificationRegistrationV1 {
        let subject = try SyncSubjectIdentityV1(category: category, stableName: name)
        let transport: ReplicationTransportV1
        switch classification {
        case .replicated: transport = .futureAcceptedMutationEligible
        case .contentBlob: transport = .futureBoundedBlobEligible
        case .localOnly, .derivedRebuildable, .privateDeviceOnly: transport = .excluded
        }
        let privacy: ReplicationPrivacyV1
        switch classification {
        case .contentBlob: privacy = .workspaceContentBlob
        case .privateDeviceOnly:
            privacy = category == .diagnostic ? .noncustomerDiagnostic : .privateDeviceData
        case .replicated, .localOnly, .derivedRebuildable:
            privacy = .workspaceData
        }
        let policy = try ReplicationPolicyV1(
            policyID: "policy." + subject.canonicalKey.replacingOccurrences(of: ":", with: "."),
            authority: authority(for: classification),
            persistence: persistence,
            transport: transport,
            bootstrap: bootstrap(for: classification),
            privacy: privacy,
            retention: retention(for: classification),
            codec: try ReplicationCodecV1(
                codecID: "codec." + name,
                readableVersions: [1],
                currentWriteVersion: 1
            ),
            sizeLimit: classification == .contentBlob ? .boundedBytes(1_073_741_824) : .boundedBytes(16_777_216),
            dependencies: [],
            backup: backup(for: classification),
            export: export(for: classification),
            deletion: deletion(for: classification, rule: rule),
            erase: erase(for: classification)
        )
        return try SyncClassificationRegistrationV1(
            subject: subject,
            classification: classification,
            replicationPolicy: policy,
            conflictPolicy: try ConflictPolicyV1(
                policyID: "conflict." + subject.canonicalKey.replacingOccurrences(of: ":", with: "."),
                rule: rule
            )
        )
    }

    private static func authority(for classification: SyncClassificationV1) -> ReplicationAuthorityV1 {
        switch classification {
        case .replicated: return .workspaceWriter
        case .contentBlob: return .immutableContentWriter
        case .derivedRebuildable: return .derivedFromCanonicalInputs
        case .localOnly, .privateDeviceOnly: return .localDevice
        }
    }

    private static func bootstrap(for classification: SyncClassificationV1) -> ReplicationBootstrapV1 {
        switch classification {
        case .replicated: return .canonicalSnapshot
        case .contentBlob: return .immutableHistory
        case .derivedRebuildable: return .rebuildFromDependencies
        case .localOnly, .privateDeviceOnly: return .destinationLocal
        }
    }

    private static func retention(for classification: SyncClassificationV1) -> ReplicationRetentionV1 {
        switch classification {
        case .replicated: return .untilCanonicalDeleteOrErase
        case .contentBlob: return .immutableHistoryUntilErase
        case .derivedRebuildable: return .rebuildable
        case .localOnly: return .operationScoped
        case .privateDeviceOnly: return .localDeviceRetained
        }
    }

    private static func backup(for classification: SyncClassificationV1) -> ReplicationBackupDispositionV1 {
        switch classification {
        case .replicated: return .includeCanonical
        case .contentBlob: return .includeImmutableHistory
        case .derivedRebuildable: return .rebuildAfterRestore
        case .localOnly, .privateDeviceOnly: return .exclude
        }
    }

    private static func export(for classification: SyncClassificationV1) -> ReplicationExportDispositionV1 {
        switch classification {
        case .replicated: return .portableCanonical
        case .contentBlob: return .portableImmutableHistory
        case .localOnly, .derivedRebuildable, .privateDeviceOnly: return .exclude
        }
    }

    private static func deletion(
        for classification: SyncClassificationV1,
        rule: ConflictRuleV1
    ) -> ReplicationDeleteDispositionV1 {
        if rule == .deleteWins { return .appendTombstone }
        switch classification {
        case .replicated, .contentBlob: return .canonicalDelete
        case .derivedRebuildable: return .rebuild
        case .localOnly, .privateDeviceOnly: return .localAuthority
        }
    }

    private static func erase(for classification: SyncClassificationV1) -> ReplicationEraseDispositionV1 {
        switch classification {
        case .replicated, .contentBlob: return .clearWithWorkspace
        case .derivedRebuildable: return .rebuildAfterErase
        case .localOnly: return .recreateEmpty
        case .privateDeviceOnly: return .localAuthority
        }
    }
}

enum SyncClassificationRegistryFailureV1: Error, Equatable {
    case invalidSubject
    case invalidRegistrationCount
    case unregisteredOrDuplicateSubject
    case conflictingPolicy
    case incompleteInventory
}

import Foundation

enum KernelCanonicalWriterV4: String, Codable, CaseIterable, Sendable {
    case workspaceTransaction = "WORKSPACE_TRANSACTION"
    case immutableContentWriter = "IMMUTABLE_CONTENT_WRITER"
    case appendOnlyReceiptWriter = "APPEND_ONLY_RECEIPT_WRITER"
    case deviceLocalOperationalWriter = "DEVICE_LOCAL_OPERATIONAL_WRITER"
    case recoveryJournalWriter = "RECOVERY_JOURNAL_WRITER"
    case dormantContractWriter = "DORMANT_CONTRACT_WRITER"
}

enum KernelSyncClassificationV4: String, Codable, Sendable {
    case replicatedCanonical = "REPLICATED_CANONICAL"
    case immutableContent = "IMMUTABLE_CONTENT"
    case appendOnlyHistory = "APPEND_ONLY_HISTORY"
    case localOnly = "LOCAL_ONLY"
    case recoveryOnly = "RECOVERY_ONLY"
    case excludedDormant = "EXCLUDED_DORMANT"
}

enum KernelReplicationDispositionV4: String, Codable, Sendable {
    case futureAcceptedMutationEligible = "FUTURE_ACCEPTED_MUTATION_ELIGIBLE"
    case futureBoundedBlobEligible = "FUTURE_BOUNDED_BLOB_ELIGIBLE"
    case excludedNoTransport = "EXCLUDED_NO_TRANSPORT"
}

enum KernelConflictDispositionV4: String, Codable, Sendable {
    case exactRevisionManual = "EXACT_REVISION_MANUAL"
    case immutableIdentity = "IMMUTABLE_IDENTITY"
    case stableIDAppendUnion = "STABLE_ID_APPEND_UNION"
    case localAuthority = "LOCAL_AUTHORITY"
    case recoveryStateMachine = "RECOVERY_STATE_MACHINE"
    case notApplicable = "NOT_APPLICABLE"
}

enum KernelSearchDispositionV4: String, Codable, Sendable {
    case boundedCanonicalFields = "BOUNDED_CANONICAL_FIELDS"
    case excluded = "EXCLUDED"
}

enum KernelRebuildDispositionV4: String, Codable, Sendable {
    case canonicalSource = "CANONICAL_SOURCE"
    case rebuildFromCanonicalDependencies = "REBUILD_FROM_CANONICAL_DEPENDENCIES"
    case replayJournal = "REPLAY_JOURNAL"
    case notApplicable = "NOT_APPLICABLE"
}

enum KernelJournalDispositionV4: String, Codable, Sendable {
    case canonicalMutationEnvelope = "CANONICAL_MUTATION_ENVELOPE"
    case immutableEffectReceipt = "IMMUTABLE_EFFECT_RECEIPT"
    case operationRecovery = "OPERATION_RECOVERY"
    case notApplicable = "NOT_APPLICABLE"
}

enum KernelReplayDispositionV4: String, Codable, Sendable {
    case idempotentCanonicalMutation = "IDEMPOTENT_CANONICAL_MUTATION"
    case immutableHistory = "IMMUTABLE_HISTORY"
    case recoveryStateMachine = "RECOVERY_STATE_MACHINE"
    case rebuildProjection = "REBUILD_PROJECTION"
    case notApplicable = "NOT_APPLICABLE"
}

enum KernelOpenExportDispositionV4: String, Codable, Sendable {
    case canonicalPortable = "CANONICAL_PORTABLE"
    case immutableHistoryPortable = "IMMUTABLE_HISTORY_PORTABLE"
    case readOnlyContractProjection = "READ_ONLY_CONTRACT_PROJECTION"
    case excluded = "EXCLUDED"
}

struct KernelRecordRegistrationV4: Codable, Equatable, Comparable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case descriptor, writer, syncClassification, replication, conflict
        case search, rebuild, journal, replay, openExport
    }

    let descriptor: KernelPersistenceV4RecordDescriptor
    let writer: KernelCanonicalWriterV4
    let syncClassification: KernelSyncClassificationV4
    let replication: KernelReplicationDispositionV4
    let conflict: KernelConflictDispositionV4
    let search: KernelSearchDispositionV4
    let rebuild: KernelRebuildDispositionV4
    let journal: KernelJournalDispositionV4
    let replay: KernelReplayDispositionV4
    let openExport: KernelOpenExportDispositionV4

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.descriptor < rhs.descriptor }

    init(
        descriptor: KernelPersistenceV4RecordDescriptor,
        writer: KernelCanonicalWriterV4,
        syncClassification: KernelSyncClassificationV4,
        replication: KernelReplicationDispositionV4,
        conflict: KernelConflictDispositionV4,
        search: KernelSearchDispositionV4,
        rebuild: KernelRebuildDispositionV4,
        journal: KernelJournalDispositionV4,
        replay: KernelReplayDispositionV4,
        openExport: KernelOpenExportDispositionV4
    ) throws {
        self.descriptor = descriptor
        self.writer = writer
        self.syncClassification = syncClassification
        self.replication = replication
        self.conflict = conflict
        self.search = search
        self.rebuild = rebuild
        self.journal = journal
        self.replay = replay
        self.openExport = openExport
        try validate()
    }

    init(from decoder: Decoder) throws {
        try KernelPersistenceV4Validation.rejectUnknownKeys(decoder, keys: CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            descriptor: values.decode(KernelPersistenceV4RecordDescriptor.self, forKey: .descriptor),
            writer: values.decode(KernelCanonicalWriterV4.self, forKey: .writer),
            syncClassification: values.decode(KernelSyncClassificationV4.self, forKey: .syncClassification),
            replication: values.decode(KernelReplicationDispositionV4.self, forKey: .replication),
            conflict: values.decode(KernelConflictDispositionV4.self, forKey: .conflict),
            search: values.decode(KernelSearchDispositionV4.self, forKey: .search),
            rebuild: values.decode(KernelRebuildDispositionV4.self, forKey: .rebuild),
            journal: values.decode(KernelJournalDispositionV4.self, forKey: .journal),
            replay: values.decode(KernelReplayDispositionV4.self, forKey: .replay),
            openExport: values.decode(KernelOpenExportDispositionV4.self, forKey: .openExport)
        )
    }

    func validate() throws {
        try descriptor.validate()
        guard descriptor == (try KernelPersistenceV4Schema.recordDescriptor(for: descriptor.kind)),
              replication == .excludedNoTransport else {
            throw KernelPersistenceV4Failure.invalidValue
        }
        switch descriptor.classification {
        case .canonicalWorkspace:
            guard writer == .workspaceTransaction,
                  syncClassification == .replicatedCanonical,
                  conflict == .exactRevisionManual,
                  search == .boundedCanonicalFields,
                  rebuild == .canonicalSource,
                  journal == .canonicalMutationEnvelope,
                  replay == .idempotentCanonicalMutation,
                  openExport == .canonicalPortable else {
                throw KernelPersistenceV4Failure.invalidValue
            }
        case .immutableContentMetadata:
            guard writer == .immutableContentWriter,
                  syncClassification == .immutableContent,
                  conflict == .immutableIdentity,
                  search == .boundedCanonicalFields,
                  rebuild == .canonicalSource,
                  journal == .notApplicable,
                  replay == .immutableHistory,
                  openExport == .immutableHistoryPortable else {
                throw KernelPersistenceV4Failure.invalidValue
            }
        case .appendOnlyReceipt:
            guard writer == .appendOnlyReceiptWriter,
                  syncClassification == .appendOnlyHistory,
                  conflict == .stableIDAppendUnion,
                  search == .excluded,
                  rebuild == .canonicalSource,
                  journal == .immutableEffectReceipt,
                  replay == .immutableHistory,
                  openExport == .immutableHistoryPortable else {
                throw KernelPersistenceV4Failure.invalidValue
            }
        case .deviceLocalOperational:
            guard writer == .deviceLocalOperationalWriter,
                  syncClassification == .localOnly,
                  conflict == .localAuthority,
                  search == .excluded,
                  rebuild == .canonicalSource,
                  journal == .notApplicable,
                  replay == .notApplicable,
                  openExport == .excluded else {
                throw KernelPersistenceV4Failure.invalidValue
            }
        case .recoveryJournal:
            guard writer == .recoveryJournalWriter,
                  syncClassification == .recoveryOnly,
                  conflict == .recoveryStateMachine,
                  search == .excluded,
                  rebuild == .replayJournal,
                  journal == .operationRecovery,
                  replay == .recoveryStateMachine,
                  openExport == .excluded else {
                throw KernelPersistenceV4Failure.invalidValue
            }
        case .dormantContractDeclaration:
            guard writer == .dormantContractWriter,
                  syncClassification == .excludedDormant,
                  conflict == .notApplicable,
                  search == .excluded,
                  rebuild == .rebuildFromCanonicalDependencies,
                  journal == .notApplicable,
                  replay == .rebuildProjection,
                  openExport == .readOnlyContractProjection else {
                throw KernelPersistenceV4Failure.invalidValue
            }
        }
    }
}

enum KernelRecordRegistryV4 {
    static let registrations: [KernelRecordRegistrationV4] = {
        do {
            try KernelPersistenceV4Schema.validate()
            return try KernelPersistenceV4RecordKind.allCases.map(makeRegistration).sorted()
        }
        catch { preconditionFailure("Invalid KERNEL_PERSISTENCE_V4 record registry: \(error)") }
    }()

    static var canonicalDigest: String {
        get throws { try KernelPersistenceV4Validation.canonicalDigest(registrations) }
    }

    static func registration(for kind: KernelPersistenceV4RecordKind) throws -> KernelRecordRegistrationV4 {
        let matches = registrations.filter { $0.descriptor.kind == kind }
        guard matches.count == 1, let value = matches.first else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
        return value
    }

    static func validate() throws {
        try validate(registrations)
    }

    static func validate(_ candidate: [KernelRecordRegistrationV4]) throws {
        let schema = try KernelPersistenceV4Schema.descriptor()
        try schema.validate()
        guard schema.runtimePosture == .dormantStatic, !schema.activationEnabled else {
            throw KernelPersistenceV4Failure.partialActivation
        }
        try candidate.forEach { try $0.validate() }
        let expected = KernelPersistenceV4RecordKind.allCases.sorted()
        let observed = candidate.map(\.descriptor.kind)
        guard candidate == candidate.sorted(), observed == expected,
              Set(observed).count == observed.count,
              Set(candidate.map(\.descriptor.canonicalMutationEffectID)).count == candidate.count else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}

private extension KernelRecordRegistryV4 {
    static func makeRegistration(_ kind: KernelPersistenceV4RecordKind) throws -> KernelRecordRegistrationV4 {
        let descriptor = try KernelPersistenceV4Schema.recordDescriptor(for: kind)
        let classification = descriptor.classification
        let writer: KernelCanonicalWriterV4
        let sync: KernelSyncClassificationV4
        let conflict: KernelConflictDispositionV4
        let search: KernelSearchDispositionV4
        let rebuild: KernelRebuildDispositionV4
        let journal: KernelJournalDispositionV4
        let replay: KernelReplayDispositionV4
        let export: KernelOpenExportDispositionV4
        switch classification {
        case .canonicalWorkspace:
            (writer, sync, conflict, search, rebuild, journal, replay, export) =
                (.workspaceTransaction, .replicatedCanonical, .exactRevisionManual, .boundedCanonicalFields,
                 .canonicalSource, .canonicalMutationEnvelope, .idempotentCanonicalMutation, .canonicalPortable)
        case .immutableContentMetadata:
            (writer, sync, conflict, search, rebuild, journal, replay, export) =
                (.immutableContentWriter, .immutableContent, .immutableIdentity, .boundedCanonicalFields,
                 .canonicalSource, .notApplicable, .immutableHistory, .immutableHistoryPortable)
        case .appendOnlyReceipt:
            (writer, sync, conflict, search, rebuild, journal, replay, export) =
                (.appendOnlyReceiptWriter, .appendOnlyHistory, .stableIDAppendUnion, .excluded,
                 .canonicalSource, .immutableEffectReceipt, .immutableHistory, .immutableHistoryPortable)
        case .deviceLocalOperational:
            (writer, sync, conflict, search, rebuild, journal, replay, export) =
                (.deviceLocalOperationalWriter, .localOnly, .localAuthority, .excluded,
                 .canonicalSource, .notApplicable, .notApplicable, .excluded)
        case .recoveryJournal:
            (writer, sync, conflict, search, rebuild, journal, replay, export) =
                (.recoveryJournalWriter, .recoveryOnly, .recoveryStateMachine, .excluded,
                 .replayJournal, .operationRecovery, .recoveryStateMachine, .excluded)
        case .dormantContractDeclaration:
            (writer, sync, conflict, search, rebuild, journal, replay, export) =
                (.dormantContractWriter, .excludedDormant, .notApplicable, .excluded,
                 .rebuildFromCanonicalDependencies, .notApplicable, .rebuildProjection, .readOnlyContractProjection)
        }
        return try KernelRecordRegistrationV4(
            descriptor: descriptor,
            writer: writer,
            syncClassification: sync,
            replication: .excludedNoTransport,
            conflict: conflict,
            search: search,
            rebuild: rebuild,
            journal: journal,
            replay: replay,
            openExport: export
        )
    }

}

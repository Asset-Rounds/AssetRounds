import Foundation
import SwiftData

/// C12 owns durable plans, attestations, acknowledgements, and receipts only.
/// Queue items are rebuilt from a required canonical source provider.
@MainActor
struct ReinspectionExceptionQueueLifecycleAdapterV1 {
    struct Snapshot: Sendable {
        let plans: [ReinspectionPlanV1]
        let attestations: [UnchangedAttestationV1]
        let acknowledgements: [ExceptionQueueAcknowledgementV1]
        let receipts: [ReinspectionExceptionMutationReceiptV1]
    }

    let modelContext: ModelContext
    let workspaceID: WorkspaceID
    let sourceProviders: [any ExceptionQueueCanonicalSourceProvidingV1]
    /// Reinspection rows and queue sources use distinct resolver contracts.
    /// Keeping both existential dependencies explicit avoids erasing a concrete
    /// dual-conforming resolver to the wrong protocol at the queue boundary.
    let sourceResolver: (any ReinspectionCanonicalSourceResolvingV1)?
    let exceptionSourceResolver: (any ExceptionQueueCanonicalSourceResolvingV1)?
    private let submit: (@MainActor (ReinspectionExceptionMutationCommandV1) throws -> ReinspectionExceptionMutationReceiptV1)?
    private let receiptLookup: (@MainActor (ReinspectionExceptionMutationCommandV1) throws -> ReinspectionExceptionMutationReceiptV1?)?

    init(modelContext: ModelContext, workspaceID: WorkspaceID,
         sourceProviders: [any ExceptionQueueCanonicalSourceProvidingV1],
         sourceResolver: any ReinspectionCanonicalSourceResolvingV1,
         exceptionSourceResolver: any ExceptionQueueCanonicalSourceResolvingV1) {
        self.modelContext = modelContext; self.workspaceID = workspaceID
        self.sourceProviders = sourceProviders
        self.sourceResolver = sourceResolver
        self.exceptionSourceResolver = exceptionSourceResolver
        self.submit = nil; self.receiptLookup = nil
    }

    /// Production replay binding uses the one canonical writer transaction;
    /// read/query composition remains this concrete SwiftData adapter.
    init(workspaceWriter: WorkspaceWriterV1, modelContext: ModelContext, workspaceID: WorkspaceID,
         sourceProviders: [any ExceptionQueueCanonicalSourceProvidingV1],
         sourceResolver: any ReinspectionCanonicalSourceResolvingV1,
         exceptionSourceResolver: any ExceptionQueueCanonicalSourceResolvingV1) {
        self.modelContext = modelContext; self.workspaceID = workspaceID
        self.sourceProviders = sourceProviders
        self.sourceResolver = sourceResolver
        self.exceptionSourceResolver = exceptionSourceResolver
        self.submit = { try workspaceWriter.commitReinspectionException($0) }
        self.receiptLookup = { try workspaceWriter.reinspectionExceptionReceipt(for: $0) }
    }

    /// Backup/physical replace restore need no live source resolution. Queries
    /// still fail closed because their required providers/resolver are absent.
    init(modelContext: ModelContext, workspaceID: WorkspaceID) {
        self.modelContext = modelContext; self.workspaceID = workspaceID
        self.sourceProviders = []
        self.sourceResolver = nil
        self.exceptionSourceResolver = nil
        self.submit = nil; self.receiptLookup = nil
    }

    /// Physical snapshots are for backup/replace restore only. They validate
    /// durable row shape and links, but deliberately do not resolve live
    /// canonical sources because export must remain available offline.
    private func physicalSnapshot() throws -> Snapshot {
        let plans = try modelContext.fetch(FetchDescriptor<ReinspectionPlanRowV1>())
            .filter { $0.workspaceID == workspaceID.rawValue }.map { try $0.value() }
        let planByRevision = Dictionary(grouping: plans) { "\($0.planID.uuidString)|\($0.revision)" }
        let attestations = try modelContext.fetch(FetchDescriptor<UnchangedAttestationRowV1>())
            .filter { $0.workspaceID == workspaceID.rawValue }.map { row -> UnchangedAttestationV1 in
                let value = try row.value()
                guard let plan = planByRevision["\(value.planID.uuidString)|\(value.planRevision)"]?.first else { throw ReinspectionExceptionFailureV1.missingSource }
                return try row.value(plan: plan)
            }
        let acknowledgements = try modelContext.fetch(FetchDescriptor<ExceptionQueueAcknowledgementRowV1>())
            .filter { $0.workspaceID == workspaceID.rawValue }.map { try $0.value() }
        let receipts = try modelContext.fetch(FetchDescriptor<ReinspectionExceptionMutationReceiptRowV1>())
            .filter { $0.workspaceID == workspaceID.rawValue }.map { try $0.value() }
        let ids = receipts.map(\.mutationID)
        guard Set(ids).count == ids.count else { throw ReinspectionExceptionFailureV1.duplicateIdentity }
        return .init(plans: plans, attestations: attestations, acknowledgements: acknowledgements, receipts: receipts)
    }

    /// Every production read of source-bound C12 state re-resolves the source
    /// truth. This prevents a stale plan or attestation from becoming visible
    /// merely because its physical row remains internally well-formed.
    func snapshot() throws -> Snapshot {
        guard let sourceResolver, let exceptionSourceResolver else {
            throw ReinspectionExceptionFailureV1.missingSource
        }

        let planRows = try modelContext.fetch(FetchDescriptor<ReinspectionPlanRowV1>())
            .filter { $0.workspaceID == workspaceID.rawValue }
        let rawPlans = try planRows.map { (row: $0, value: try $0.value()) }
        var plans: [ReinspectionPlanV1] = []
        for (_, chain) in Dictionary(grouping: rawPlans, by: { $0.value.planID }) {
            let ordered = chain.sorted { $0.value.revision < $1.value.revision }
            var predecessor: ReinspectionPlanV1?
            for pair in ordered {
                try pair.value.validate(predecessor: predecessor)
                let value = try pair.row.value(predecessor: predecessor, resolver: sourceResolver)
                plans.append(value)
                predecessor = value
            }
        }
        guard Set(plans.map(\.planEventID)).count == plans.count,
              Set(plans.map { "\($0.planID.uuidString)|\($0.revision)" }).count == plans.count else {
            throw ReinspectionExceptionFailureV1.duplicateIdentity
        }

        let attestationRows = try modelContext.fetch(FetchDescriptor<UnchangedAttestationRowV1>())
            .filter { $0.workspaceID == workspaceID.rawValue }
        let attestations = try attestationRows.map { row -> UnchangedAttestationV1 in
            let raw = try row.value()
            guard let plan = plans.first(where: {
                $0.planID == raw.planID && $0.revision == raw.planRevision
            }) else { throw ReinspectionExceptionFailureV1.missingSource }
            return try row.value(plan: plan, resolver: sourceResolver)
        }
        guard Set(attestations.map(\.attestationID)).count == attestations.count else {
            throw ReinspectionExceptionFailureV1.duplicateIdentity
        }

        let acknowledgementRows = try modelContext.fetch(FetchDescriptor<ExceptionQueueAcknowledgementRowV1>())
            .filter { $0.workspaceID == workspaceID.rawValue }
        let rawAcknowledgements = try acknowledgementRows.map { (row: $0, value: try $0.value()) }
        var acknowledgements: [ExceptionQueueAcknowledgementV1] = []
        for (_, chain) in Dictionary(grouping: rawAcknowledgements, by: { $0.value.logicalExceptionKey }) {
            let ordered = chain.sorted { $0.value.revision < $1.value.revision }
            var predecessor: ExceptionQueueAcknowledgementV1?
            for pair in ordered {
                let source = try exceptionSourceResolver.resolveExceptionQueueSource(
                    workspaceID: workspaceID, kind: pair.value.sourceKind,
                    sourceID: pair.value.sourceID, revision: pair.value.sourceRevision
                )
                try source.validateResolved(by: exceptionSourceResolver)
                try pair.value.validate(source: source, predecessor: predecessor)
                let value = try pair.row.value(
                    source: source, predecessor: predecessor, resolver: exceptionSourceResolver
                )
                acknowledgements.append(value)
                predecessor = value
            }
        }
        guard Set(acknowledgements.map(\.acknowledgementID)).count == acknowledgements.count,
              Set(acknowledgements.map { "\($0.logicalExceptionKey)|\($0.revision)" }).count == acknowledgements.count else {
            throw ReinspectionExceptionFailureV1.duplicateIdentity
        }

        let receipts = try modelContext.fetch(FetchDescriptor<ReinspectionExceptionMutationReceiptRowV1>())
            .filter { $0.workspaceID == workspaceID.rawValue }.map { try $0.value() }
        let ids = receipts.map(\.mutationID)
        guard Set(ids).count == ids.count else { throw ReinspectionExceptionFailureV1.duplicateIdentity }
        return .init(plans: plans, attestations: attestations,
                     acknowledgements: acknowledgements, receipts: receipts)
    }

    func query(_ query: ReinspectionExceptionQueryV1) throws -> ReinspectionExceptionQueryResultV1 {
        guard query.workspaceID == workspaceID else { throw ReinspectionExceptionFailureV1.wrongWorkspace }
        let state = try snapshot()
        switch query.target {
        case let .plan(id): return state.plans.first { $0.planID == id }.map(ReinspectionExceptionQueryResultV1.plan) ?? .notFound(query)
        case let .attestation(id): return state.attestations.first { $0.attestationID == id }.map(ReinspectionExceptionQueryResultV1.attestation) ?? .notFound(query)
        case let .acknowledgement(key): return state.acknowledgements.filter { $0.logicalExceptionKey == key }.sorted { $0.revision > $1.revision }.first.map(ReinspectionExceptionQueryResultV1.acknowledgement) ?? .notFound(query)
        case let .queue(filter):
            guard let exceptionSourceResolver else {
                throw ReinspectionExceptionFailureV1.missingSource
            }
            let providerKinds = sourceProviders.map(\.registeredSourceKind)
            guard sourceProviders.count == ExceptionQueueSourceKindV1.allCases.count,
                  Set(providerKinds) == Set(ExceptionQueueSourceKindV1.allCases) else {
                throw ReinspectionExceptionFailureV1.missingSource
            }
            var sources: [ExceptionQueueSourceSnapshotV1] = []
            for provider in sourceProviders {
                let provided = try provider.unresolvedExceptionSources(workspaceID: workspaceID)
                guard provided.allSatisfy({ $0.kind == provider.registeredSourceKind }) else {
                    throw ReinspectionExceptionFailureV1.forgedSource
                }
                sources += provided
            }
            try sources.forEach { try $0.validate() }
            guard sources.allSatisfy({ $0.workspaceID == workspaceID && providerKinds.contains($0.kind) }) else { throw ReinspectionExceptionFailureV1.wrongWorkspace }
            let registry = try ExceptionQueueSourceRegistryV1(registeredKinds: providerKinds.sorted { $0.rawValue < $1.rawValue })
            let projection = try ExceptionQueueProjectionV1(workspaceID: workspaceID, registry: registry,
                                                             sources: sources, acknowledgements: state.acknowledgements,
                                                             resolver: exceptionSourceResolver)
            return .queue(Array(projection.items.filter(filter.includes).prefix(query.maximumResults)))
        }
    }

    /// Rebuild is source-provider dependent and fails closed when source truth
    /// (including any related-work source) is unavailable.
    func rebuild(_ filter: ExceptionQueueFilterV1) throws -> [ExceptionQueueItemV1] {
        let query = try ReinspectionExceptionQueryV1(workspaceID: workspaceID, target: .queue(filter), maximumResults: ReinspectionExceptionLimitsV1.maximumQueryResults)
        guard case let .queue(values) = try self.query(query) else { throw ReinspectionExceptionFailureV1.missingSource }
        return values
    }

    /// The physical backup contains only C12's four durable families. Queue
    /// items are intentionally absent because they are source-derived.
    func backupSnapshot(
        effectProvenance: [ReinspectionExceptionBackupEffectProvenanceV1]
    ) throws -> ReinspectionExceptionQueueBackupSnapshotV1 {
        let state = try physicalSnapshot()
        return try .init(plans: state.plans, attestations: state.attestations,
                         acknowledgements: state.acknowledgements, receipts: state.receipts,
                         effectProvenance: effectProvenance)
    }

    /// Export and restore carry physical provenance per effect; no queue item
    /// or canonical-source body is serialized.
    func backup() throws -> ReinspectionExceptionQueueBackupSnapshotV1 {
        let plans = try modelContext.fetch(FetchDescriptor<ReinspectionPlanRowV1>())
            .filter { $0.workspaceID == workspaceID.rawValue }
            .map { try ReinspectionExceptionBackupEffectProvenanceV1(
                mutationID: $0.mutationID, semanticSHA256: $0.canonicalSHA256,
                writerInstanceID: $0.writerInstanceID
            ) }
        let attestations = try modelContext.fetch(FetchDescriptor<UnchangedAttestationRowV1>())
            .filter { $0.workspaceID == workspaceID.rawValue }
            .map { try ReinspectionExceptionBackupEffectProvenanceV1(
                mutationID: $0.mutationID, semanticSHA256: $0.canonicalSHA256,
                writerInstanceID: $0.writerInstanceID
            ) }
        let acknowledgements = try modelContext.fetch(FetchDescriptor<ExceptionQueueAcknowledgementRowV1>())
            .filter { $0.workspaceID == workspaceID.rawValue }
            .map { try ReinspectionExceptionBackupEffectProvenanceV1(
                mutationID: $0.mutationID, semanticSHA256: $0.canonicalSHA256,
                writerInstanceID: $0.writerInstanceID
            ) }
        return try backupSnapshot(effectProvenance: plans + attestations + acknowledgements)
    }

    func exportCanonical() throws -> Data { try WorkspaceMutationCanonicalV1.data(try backup()) }

    func decodeBackup(_ data: Data) throws -> ReinspectionExceptionQueueBackupSnapshotV1 {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(ReinspectionExceptionQueueBackupSnapshotV1.self, from: data)
        try ReinspectionExceptionQueueBackupEnrollmentV1.validate(value)
        return value
    }

    /// V49 is additive: V48 transports an intentionally empty C12 history.
    func migrate(_ data: Data, from schemaVersion: Int) throws -> Data {
        switch schemaVersion {
        case ReinspectionAndExceptionSchemaV1.predecessorSchemaVersion:
            return try WorkspaceMutationCanonicalV1.data(
                ReinspectionExceptionQueueBackupSnapshotV1(
                    plans: [], attestations: [], acknowledgements: [], receipts: [], effectProvenance: []
                )
            )
        case ReinspectionAndExceptionSchemaV1.schemaVersion:
            _ = try decodeBackup(data); return data
        default:
            throw ReinspectionExceptionFailureV1.incompatibleVersion
        }
    }

    /// Replace restore is intentionally resolver-free: snapshot closure is
    /// checked before any dictionary construction, then rows are rebuilt only
    /// through the receipt-bound restoring initializers.
    func replaceRestore(_ backup: ReinspectionExceptionQueueBackupSnapshotV1) throws {
        try ReinspectionExceptionQueueBackupEnrollmentV1.validate(backup)
        let provenanceKeys = backup.effectProvenance.map {
            "\($0.mutationID.uuidString.lowercased())|\($0.semanticSHA256)"
        }
        let receiptIDs = backup.receipts.map(\.mutationID)
        guard Set(provenanceKeys).count == provenanceKeys.count,
              Set(receiptIDs).count == receiptIDs.count else {
            throw ReinspectionExceptionFailureV1.duplicateIdentity
        }
        let receipts = Dictionary(uniqueKeysWithValues: backup.receipts.map { ($0.mutationID, $0) })
        let writers = Dictionary(uniqueKeysWithValues: backup.effectProvenance.map {
            ("\($0.mutationID.uuidString.lowercased())|\($0.semanticSHA256)", $0.writerInstanceID)
        })
        func receiptAndWriter(_ mutationID: MutationIDV1, _ semantic: String) throws
            -> (ReinspectionExceptionMutationReceiptV1, UUID) {
            guard let receipt = receipts[mutationID],
                  let writer = writers["\(mutationID.rawValue.uuidString.lowercased())|\(semantic)"] else {
                throw ReinspectionExceptionFailureV1.receiptMismatch
            }
            return (receipt, writer)
        }
        try modelContext.delete(model: ReinspectionPlanRowV1.self)
        try modelContext.delete(model: UnchangedAttestationRowV1.self)
        try modelContext.delete(model: ExceptionQueueAcknowledgementRowV1.self)
        try modelContext.delete(model: ReinspectionExceptionMutationReceiptRowV1.self)
        for value in backup.plans.sorted(by: { $0.revision < $1.revision }) {
            let (receipt, writer) = try receiptAndWriter(value.mutationID, value.planSHA256)
            modelContext.insert(try ReinspectionPlanRowV1(
                restoring: value, receipt: receipt, writerInstanceID: writer
            ))
        }
        let plans = Dictionary(grouping: backup.plans, by: \.planID)
        for value in backup.attestations {
            guard let plan = plans[value.planID]?.first(where: { $0.revision == value.planRevision }) else {
                throw ReinspectionExceptionFailureV1.missingSource
            }
            let (receipt, writer) = try receiptAndWriter(value.mutationID, value.attestationSHA256)
            modelContext.insert(try UnchangedAttestationRowV1(
                restoring: value, receipt: receipt, writerInstanceID: writer
            ))
            try value.validate(plan: plan)
        }
        for value in backup.acknowledgements {
            let (receipt, writer) = try receiptAndWriter(value.mutationID, value.acknowledgementSHA256)
            modelContext.insert(try ExceptionQueueAcknowledgementRowV1(
                restoring: value, receipt: receipt, writerInstanceID: writer
            ))
        }
        for receipt in backup.receipts {
            modelContext.insert(try ReinspectionExceptionMutationReceiptRowV1(receipt))
        }
    }

    /// Replay never inserts directly: it recovers or commits through the one
    /// workspace writer and validates the original command/typed receipt pair.
    func replay(_ command: ReinspectionExceptionMutationCommandV1) throws
        -> ReinspectionExceptionMutationReceiptV1 {
        try command.validate()
        guard command.workspaceID == workspaceID, let submit, let receiptLookup else {
            throw ReinspectionExceptionFailureV1.wrongWorkspace
        }
        if let receipt = try receiptLookup(command) {
            try receipt.validate(command: command); return receipt
        }
        let receipt = try submit(command)
        try receipt.validate(command: command)
        return receipt
    }

    /// Ordinary sign deletion preserves append-only C12 history and never
    /// implies that an acknowledgement resolved the canonical source.
    func delete(assetID: UUID, using service: WholeSignDeletionService) async throws
        -> WholeSignDeletionOutcome {
        try ReinspectionExceptionKernelDeletionEraseEnrollmentV1.validate()
        return try await service.delete(assetID: assetID)
    }

    /// Whole-workspace Erase is delegated to the incumbent generation swap;
    /// its publication check verifies every V49 C12 row family is empty.
    func erase(
        confirmation: String,
        using service: EraseAllService,
        coordinator: StoreSessionCoordinator,
        diagnosticsStore: DiagnosticsStore,
        activate: @escaping @MainActor (StoreGenerationSession) async -> Void,
        lifecycleDependencies: WorkspacePackageLifecycleDependenciesV1
    ) async throws -> EraseAllOutcome {
        try ReinspectionExceptionKernelDeletionEraseEnrollmentV1.validate()
        return try await service.erase(
            confirmation: confirmation, coordinator: coordinator,
            diagnosticsStore: diagnosticsStore, activate: activate,
            lifecycleDependencies: lifecycleDependencies
        )
    }

    /// C12 reports only bounded durable counts. It exposes neither source
    /// details nor a queue completeness/outcome contribution.
    struct Report: Equatable, Sendable {
        let planCount: Int; let attestationCount: Int; let acknowledgementCount: Int
        let queueIsDerived: Bool; let sourceDetailsExcluded: Bool
    }

    func report() throws -> Report {
        let state = try snapshot()
        return .init(planCount: state.plans.count, attestationCount: state.attestations.count,
                     acknowledgementCount: state.acknowledgements.count,
                     queueIsDerived: true, sourceDetailsExcluded: true)
    }

    func search(_ query: ReinspectionExceptionQueryV1) throws -> ReinspectionExceptionQueryResultV1 {
        try self.query(query)
    }
}

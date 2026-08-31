import Foundation
import SwiftData

/// Integration-only lifecycle facade for C10. It serializes typed snapshots
/// and forwards commands to the incumbent workspace writer; it owns no store,
/// media bytes, or canonical mutation implementation.
struct EvidenceQualityLifecycleAdapterV1 {
    struct Snapshot: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let ruleSets: [EvidenceQualityRuleSetV1]
        let assessments: [EvidenceQualityAssessmentV1]
        let waivers: [EvidenceQualityWaiverV1]
        let receipts: [EvidenceQualityMutationReceiptV1]

        init(ruleSets: [EvidenceQualityRuleSetV1], assessments: [EvidenceQualityAssessmentV1],
             waivers: [EvidenceQualityWaiverV1], receipts: [EvidenceQualityMutationReceiptV1]) {
            schemaVersion = EvidenceQualitySchemaV1.schemaVersion
            self.ruleSets = ruleSets.sorted { $0.ruleSetSHA256 < $1.ruleSetSHA256 }
            self.assessments = assessments.sorted { $0.assessmentSHA256 < $1.assessmentSHA256 }
            self.waivers = waivers.sorted { $0.waiverSHA256 < $1.waiverSHA256 }
            self.receipts = receipts.sorted { $0.receiptSHA256 < $1.receiptSHA256 }
        }
    }

    enum DeleteDisposition: String, Codable, Sendable { case delete, erase }

    struct Report: Equatable, Sendable {
        struct Provenance: Equatable, Sendable {
            let assessmentID: UUID
            let assessmentRevision: UInt64
            let assessmentSHA256: String
            let evidenceID: String
            let evidenceRevision: UInt64
            let evidenceSHA256: String
            let ruleSetID: UUID
            let ruleSetRevision: UInt64
            let ruleSetSHA256: String
            let waiverReasons: [EvidenceQualityWaiverReasonV1]
            let waiverLimitations: [String]
            let remainingWarningRuleIDs: [String]
        }
        let assessmentCount: Int
        let advisoryWarningCount: Int
        let waiverEventCount: Int
        let receiptCount: Int
        let provenance: [Provenance]
    }

    typealias Submit = @MainActor (EvidenceQualityMutationCommandV1) throws -> EvidenceQualityMutationReceiptV1
    typealias Query = @MainActor (EvidenceQualityQueryV1) throws -> EvidenceQualityQueryResultV1
    typealias ReceiptLookup = @MainActor (MutationIDV1) throws -> EvidenceQualityMutationReceiptV1?
    typealias SnapshotLoader = @MainActor () throws -> Snapshot
    typealias SnapshotRestorer = @MainActor (Snapshot, Bool) throws -> Void
    typealias DeleteExecutor = @MainActor (DeleteDisposition) throws -> Void

    private let submit: Submit
    private let query: Query
    private let receiptLookup: ReceiptLookup
    private let snapshotLoader: SnapshotLoader
    private let snapshotRestorer: SnapshotRestorer
    private let deleteExecutor: DeleteExecutor

    @MainActor
    init(submit: @escaping Submit, query: @escaping Query, receiptLookup: @escaping ReceiptLookup,
         snapshotLoader: @escaping SnapshotLoader, snapshotRestorer: @escaping SnapshotRestorer,
         deleteExecutor: @escaping DeleteExecutor) {
        self.submit = submit
        self.query = query
        self.receiptLookup = receiptLookup
        self.snapshotLoader = snapshotLoader
        self.snapshotRestorer = snapshotRestorer
        self.deleteExecutor = deleteExecutor
    }

    /// Production binding for the incumbent store. Querying and snapshot reads
    /// are concrete SwiftData reads; mutations still enter WorkspaceWriterV1.
    @MainActor
    init(workspaceWriter: WorkspaceWriterV1, modelContext: ModelContext, workspaceID: WorkspaceID,
         snapshotRestorer: @escaping SnapshotRestorer,
         deleteExecutor: @escaping DeleteExecutor) {
        let source = EvidenceQualitySwiftDataQuerySourceV1(
            modelContext: modelContext, workspaceID: workspaceID
        )
        self.init(
            submit: { try workspaceWriter.commitEvidenceQuality($0) },
            query: { try source.result(for: $0) },
            receiptLookup: { mutationID in
                // Receipt queries must preserve the original command binding;
                // replay supplies that validation before exposing a receipt.
                let snapshot = try source.snapshot()
                return snapshot.receipts.first { $0.mutationID == mutationID }
            },
            snapshotLoader: { try source.snapshot() },
            snapshotRestorer: snapshotRestorer,
            deleteExecutor: deleteExecutor
        )
    }

    @MainActor
    func replay(_ command: EvidenceQualityMutationCommandV1) throws -> EvidenceQualityMutationReceiptV1 {
        try command.validate()
        if let receipt = try receiptLookup(command.mutationID) {
            try receipt.validate(command: command)
            return receipt
        }
        let receipt = try submit(command)
        try receipt.validate(command: command)
        return receipt
    }

    @MainActor
    func search(_ request: EvidenceQualityQueryV1) throws -> EvidenceQualityQueryResultV1 {
        let result = try query(request)
        try result.validate(for: request)
        return result
    }

    @MainActor
    func backup() throws -> Data {
        let snapshot = try snapshotLoader()
        try Self.validate(snapshot)
        return try WorkspaceMutationCanonicalV1.data(snapshot)
    }

    /// Explicit C10 export surface. The enclosing backup package owns paths,
    /// encryption, and manifests; this returns only validated canonical facts.
    @MainActor
    func exportCanonical() throws -> Data { try backup() }

    @MainActor
    func decodeBackup(_ data: Data) throws -> Snapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let snapshot = try decoder.decode(Snapshot.self, from: data)
        try Self.validate(snapshot)
        return snapshot
    }

    @MainActor
    func replaceRestore(_ data: Data) throws {
        try snapshotRestorer(try decodeBackup(data), true)
    }

    /// V47 is additive.  A V46 workspace has no C10 records, so conversion is
    /// the deterministic empty C10 snapshot; historic C10 snapshots are never
    /// rewritten or silently reinterpreted.
    @MainActor
    func migrate(_ data: Data, from schemaVersion: Int) throws -> Data {
        switch schemaVersion {
        case EvidenceQualitySchemaV1.predecessorSchemaVersion:
            return try WorkspaceMutationCanonicalV1.data(Snapshot(ruleSets: [], assessments: [], waivers: [], receipts: []))
        case EvidenceQualitySchemaV1.schemaVersion:
            _ = try decodeBackup(data)
            return data
        default:
            throw EvidenceQualityFailureV1.incompatibleVersion
        }
    }

    @MainActor
    func delete() throws {
        // C10 owns no ordinary asset row to delete. The incumbent whole-sign
        // service performs the asset/site cascade and this durable history is
        // intentionally retained as immutable advisory provenance.
        try EvidenceQualityWholeSignDeletionPolicyV1.validate()
    }

    @MainActor
    func erase() throws {
        try EvidenceQualityKernelDeletionEraseEnrollmentV1.validate()
        try deleteExecutor(.erase)
    }

    /// Concrete production ordinary-deletion route. WholeSignDeletionService
    /// owns the cascade; C10 validates its explicit historic-preservation
    /// policy before delegating and never creates a parallel delete store.
    @MainActor
    func delete(assetID: UUID, using service: WholeSignDeletionService) async throws
        -> WholeSignDeletionOutcome {
        try delete()
        return try await service.delete(assetID: assetID)
    }

    /// Concrete production workspace-Erase route. EraseAllService performs
    /// the generation swap that clears C10 rows, including the post-erase
    /// closure check already enrolled for all four C10 families.
    @MainActor
    func erase(
        confirmation: String,
        using service: EraseAllService,
        coordinator: StoreSessionCoordinator,
        diagnosticsStore: DiagnosticsStore,
        activate: @escaping @MainActor (StoreGenerationSession) async -> Void,
        lifecycleDependencies: WorkspacePackageLifecycleDependenciesV1
    ) async throws -> EraseAllOutcome {
        try EvidenceQualityKernelDeletionEraseEnrollmentV1.validate()
        return try await service.erase(
            confirmation: confirmation, coordinator: coordinator,
            diagnosticsStore: diagnosticsStore, activate: activate,
            lifecycleDependencies: lifecycleDependencies
        )
    }

    @MainActor
    func report() throws -> Report {
        let snapshot = try snapshotLoader()
        try Self.validate(snapshot)
        let provenance = snapshot.assessments.map { assessment in
            let waivers = snapshot.waivers.filter { $0.assessmentID == assessment.assessmentID }
            return Report.Provenance(
                assessmentID: assessment.assessmentID,
                assessmentRevision: assessment.revision,
                assessmentSHA256: assessment.assessmentSHA256,
                evidenceID: assessment.evidence.evidenceID,
                evidenceRevision: assessment.evidence.evidenceRevision,
                evidenceSHA256: assessment.evidence.contentSHA256,
                ruleSetID: assessment.ruleSetID,
                ruleSetRevision: assessment.ruleSetRevision,
                ruleSetSHA256: assessment.ruleSetSHA256,
                waiverReasons: waivers.map(\.reason).sorted { $0.rawValue < $1.rawValue },
                waiverLimitations: waivers.compactMap(\.limitation).sorted(),
                remainingWarningRuleIDs: assessment.warningFindings.map(\.ruleID).sorted()
            )
        }.sorted { $0.assessmentSHA256 < $1.assessmentSHA256 }
        return .init(assessmentCount: snapshot.assessments.count,
                     advisoryWarningCount: snapshot.assessments.reduce(0) { $0 + $1.warningFindings.count },
                     waiverEventCount: snapshot.waivers.count, receiptCount: snapshot.receipts.count,
                     provenance: provenance)
    }

    static func validate(_ snapshot: Snapshot) throws {
        guard snapshot.schemaVersion == EvidenceQualitySchemaV1.schemaVersion else {
            throw EvidenceQualityFailureV1.incompatibleVersion
        }
        let ruleSetIDs = snapshot.ruleSets.map(\.ruleSetID)
        guard Set(ruleSetIDs).count == ruleSetIDs.count else { throw EvidenceQualityFailureV1.duplicateIdentity }
        let rules = Dictionary(uniqueKeysWithValues: snapshot.ruleSets.map { ($0.ruleSetID, $0) })
        for ruleSet in snapshot.ruleSets {
            if let predecessorID = ruleSet.supersedesRuleSetID {
                guard let predecessor = rules[predecessorID] else {
                    throw EvidenceQualityFailureV1.invalidSupersession
                }
                try ruleSet.validateSuccessor(of: predecessor)
            }
        }
        for assessment in snapshot.assessments {
            guard let ruleSet = rules[assessment.ruleSetID] else { throw EvidenceQualityFailureV1.unknownRule }
            try assessment.validate(ruleSet: ruleSet)
        }
        let assessmentIDs = snapshot.assessments.map(\.assessmentID)
        guard Set(assessmentIDs).count == assessmentIDs.count else { throw EvidenceQualityFailureV1.duplicateIdentity }
        let assessments = Dictionary(uniqueKeysWithValues: snapshot.assessments.map { ($0.assessmentID, $0) })
        for waiver in snapshot.waivers {
            guard let assessment = assessments[waiver.assessmentID] else { throw EvidenceQualityFailureV1.invalidValue }
            try waiver.validate(assessment: assessment)
        }
        let waiverEventIDs = snapshot.waivers.map(\.waiverEventID)
        guard Set(waiverEventIDs).count == waiverEventIDs.count else { throw EvidenceQualityFailureV1.duplicateIdentity }
        for history in Dictionary(grouping: snapshot.waivers, by: \.waiverID).values {
            let ordered = history.sorted { $0.revision < $1.revision }
            guard ordered.first?.revision == 1, ordered.count <= 2,
                  Set(ordered.map(\.revision)).count == ordered.count else {
                throw EvidenceQualityFailureV1.invalidSupersession
            }
            if ordered.count == 2 { try ordered[1].validateSuccessor(of: ordered[0]) }
        }
        let receiptMutationIDs = snapshot.receipts.map(\.mutationID)
        guard Set(receiptMutationIDs).count == receiptMutationIDs.count else {
            throw EvidenceQualityFailureV1.duplicateIdentity
        }
        try snapshot.receipts.forEach { try $0.validate() }
        let receipts = Dictionary(uniqueKeysWithValues: snapshot.receipts.map { ($0.mutationID, $0) })
        func validateReceipt(_ mutationID: MutationIDV1, semanticSHA256: String) throws {
            guard let receipt = receipts[mutationID], receipt.semanticSHA256 == semanticSHA256,
                  receipt.recoveryState == .receiptCommitted else {
                throw EvidenceQualityFailureV1.receiptMismatch
            }
        }
        try snapshot.ruleSets.forEach { try validateReceipt($0.mutationID, semanticSHA256: $0.ruleSetSHA256) }
        try snapshot.assessments.forEach { try validateReceipt($0.mutationID, semanticSHA256: $0.assessmentSHA256) }
        try snapshot.waivers.forEach { try validateReceipt($0.mutationID, semanticSHA256: $0.waiverSHA256) }
    }
}

/// Read-only C10 source over the one incumbent SwiftData store. It owns no
/// persistence and always builds a fully validated snapshot before answering
/// a closed query result.
@MainActor
final class EvidenceQualitySwiftDataQuerySourceV1 {
    private let modelContext: ModelContext
    private let workspaceID: WorkspaceID

    init(modelContext: ModelContext, workspaceID: WorkspaceID) {
        self.modelContext = modelContext
        self.workspaceID = workspaceID
    }

    func snapshot() throws -> EvidenceQualityLifecycleAdapterV1.Snapshot {
        let ruleRows = try modelContext.fetch(FetchDescriptor<EvidenceQualityRuleSetRowV1>())
            .filter { $0.workspaceID == workspaceID.rawValue }
        let rules = try ruleRows.map { try $0.value() }
        guard Set(rules.map(\.ruleSetID)).count == rules.count else {
            throw EvidenceQualityPersistenceFailureV1.duplicateIdentity
        }
        let byRuleID = Dictionary(uniqueKeysWithValues: rules.map { ($0.ruleSetID, $0) })
        let assessmentRows = try modelContext.fetch(FetchDescriptor<EvidenceQualityAssessmentRowV1>())
            .filter { $0.workspaceID == workspaceID.rawValue }
        let assessments = try assessmentRows.map { row -> EvidenceQualityAssessmentV1 in
            let values = try byRuleID.values.compactMap { try? row.value(ruleSet: $0) }
            guard values.count == 1, let value = values.first else {
                throw EvidenceQualityPersistenceFailureV1.corruptRow
            }
            return value
        }
        guard Set(assessments.map(\.assessmentID)).count == assessments.count else {
            throw EvidenceQualityPersistenceFailureV1.duplicateIdentity
        }
        let byAssessmentID = Dictionary(uniqueKeysWithValues: assessments.map { ($0.assessmentID, $0) })
        let waiverRows = try modelContext.fetch(FetchDescriptor<EvidenceQualityWaiverRowV1>())
            .filter { $0.workspaceID == workspaceID.rawValue }
        let waivers = try waiverRows.map { row -> EvidenceQualityWaiverV1 in
            let values = try byAssessmentID.values.compactMap { try? row.value(assessment: $0) }
            guard values.count == 1, let value = values.first else {
                throw EvidenceQualityPersistenceFailureV1.corruptRow
            }
            return value
        }
        let receipts = try modelContext.fetch(FetchDescriptor<EvidenceQualityMutationReceiptRowV1>())
            .filter { $0.workspaceID == workspaceID.rawValue }
            .map { try $0.value() }
        let snapshot = EvidenceQualityLifecycleAdapterV1.Snapshot(
            ruleSets: rules, assessments: assessments, waivers: waivers, receipts: receipts
        )
        try EvidenceQualityLifecycleAdapterV1.validate(snapshot)
        return snapshot
    }

    func result(for query: EvidenceQualityQueryV1) throws -> EvidenceQualityQueryResultV1 {
        try query.validate()
        guard query.workspaceID == workspaceID else { throw EvidenceQualityFailureV1.wrongWorkspace }
        let snapshot = try snapshot()
        let result: EvidenceQualityQueryResultV1
        switch query.target {
        case .currentRuleSet:
            let superseded = Set(snapshot.ruleSets.compactMap(\.supersedesRuleSetID))
            let leaves = snapshot.ruleSets.filter { !superseded.contains($0.ruleSetID) }
            guard leaves.count <= 1 else { throw EvidenceQualityFailureV1.invalidSupersession }
            result = leaves.first.map(EvidenceQualityQueryResultV1.currentRuleSet) ?? .notFound(query)
        case let .exactAssessment(evidenceID, evidenceRevision, assessmentID):
            guard let assessment = snapshot.assessments.first(where: {
                $0.assessmentID == assessmentID && $0.evidence.evidenceID == evidenceID
                    && $0.evidence.evidenceRevision == evidenceRevision
            }), let ruleSet = snapshot.ruleSets.first(where: {
                $0.ruleSetID == assessment.ruleSetID && $0.revision == assessment.ruleSetRevision
                    && $0.ruleSetSHA256 == assessment.ruleSetSHA256
            }) else {
                result = .notFound(query)
                break
            }
            result = try projectionResult(assessment: assessment, ruleSet: ruleSet, snapshot: snapshot)
        case let .evidenceHistory(evidenceID):
            let candidates = snapshot.assessments.filter { $0.evidence.evidenceID == evidenceID }
                .sorted {
                    ($0.evidence.evidenceRevision, $0.revision, $0.assessedAt, $0.assessmentID.uuidString)
                        > ($1.evidence.evidenceRevision, $1.revision, $1.assessedAt, $1.assessmentID.uuidString)
                }
            guard let assessment = candidates.first,
                  let ruleSet = snapshot.ruleSets.first(where: {
                      $0.ruleSetID == assessment.ruleSetID && $0.revision == assessment.ruleSetRevision
                          && $0.ruleSetSHA256 == assessment.ruleSetSHA256
                  }) else {
                result = .notFound(query)
                break
            }
            result = try projectionResult(assessment: assessment, ruleSet: ruleSet, snapshot: snapshot)
        }
        try result.validate(for: query)
        return result
    }

    private func projectionResult(
        assessment: EvidenceQualityAssessmentV1,
        ruleSet: EvidenceQualityRuleSetV1,
        snapshot: EvidenceQualityLifecycleAdapterV1.Snapshot
    ) throws -> EvidenceQualityQueryResultV1 {
        let projection = try EvidenceQualityProjectionV1(
            workspaceID: workspaceID, assessment: assessment,
            waiverHistory: snapshot.waivers.filter { $0.assessmentID == assessment.assessmentID }
        )
        return .assessmentProjection(try EvidenceQualityAssessmentProjectionResultV1(
            ruleSet: ruleSet, projection: projection
        ))
    }
}

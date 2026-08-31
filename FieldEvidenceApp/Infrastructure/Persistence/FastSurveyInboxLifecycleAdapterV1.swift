import Foundation
import SwiftData

/// Concrete C11 read/lifecycle composition over the incumbent workspace store.
/// It owns neither a second store nor any original-media bytes.
struct FastSurveyInboxLifecycleAdapterV1 {
    struct Snapshot: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let inboxItems: [CaptureInboxItemV1]
        let promotions: [CapturePromotionV1]
        let snippets: [SnippetV1]
        let snippetInsertions: [SnippetInsertionV1]
        let receipts: [FastSurveyInboxMutationReceiptV1]

        init(inboxItems: [CaptureInboxItemV1], promotions: [CapturePromotionV1],
             snippets: [SnippetV1], snippetInsertions: [SnippetInsertionV1],
             receipts: [FastSurveyInboxMutationReceiptV1]) {
            schemaVersion = FastSurveyInboxSchemaV1.schemaVersion
            self.inboxItems = inboxItems.sorted { $0.itemSHA256 < $1.itemSHA256 }
            self.promotions = promotions.sorted { $0.promotionSHA256 < $1.promotionSHA256 }
            self.snippets = snippets.sorted { $0.snippetSHA256 < $1.snippetSHA256 }
            self.snippetInsertions = snippetInsertions.sorted { $0.insertionSHA256 < $1.insertionSHA256 }
            self.receipts = receipts.sorted { $0.receiptSHA256 < $1.receiptSHA256 }
        }
    }

    nonisolated static func validate(_ snapshot: Snapshot) throws {
        guard snapshot.schemaVersion == FastSurveyInboxSchemaV1.schemaVersion else {
            throw FastSurveyInboxFailureV1.incompatibleVersion
        }
        let inboxEvents = snapshot.inboxItems.map(\.inboxEventID)
        guard Set(inboxEvents).count == inboxEvents.count else { throw FastSurveyInboxFailureV1.duplicateIdentity }
        try snapshot.inboxItems.forEach { try $0.validate() }
        for history in Dictionary(grouping: snapshot.inboxItems, by: \.inboxItemID).values {
            let ordered = history.sorted { $0.revision < $1.revision }
            guard ordered.count <= 2, ordered.first?.revision == 1,
                  Set(ordered.map(\.revision)).count == ordered.count else {
                throw FastSurveyInboxFailureV1.invalidSupersession
            }
            if ordered.count == 2 { try ordered[1].validateSuccessor(of: ordered[0]) }
        }
        let promotionIDs = snapshot.promotions.map(\.promotionID)
        guard Set(promotionIDs).count == promotionIDs.count else { throw FastSurveyInboxFailureV1.duplicateIdentity }
        let byInboxID = Dictionary(grouping: snapshot.inboxItems, by: \.inboxItemID)
        for promotion in snapshot.promotions {
            guard let source = byInboxID[promotion.sourceInboxItemID]?.first(where: { $0.revision == 1 }),
                  let promoted = byInboxID[promotion.sourceInboxItemID]?.first(where: {
                      $0.revision == promotion.promotedInboxRevision && $0.promotionID == promotion.promotionID
                  }) else { throw FastSurveyInboxFailureV1.invalidPromotion }
            try promotion.validate(source: source, promotedItem: promoted)
        }
        let snippetEvents = snapshot.snippets.map(\.snippetEventID)
        guard Set(snippetEvents).count == snippetEvents.count else { throw FastSurveyInboxFailureV1.duplicateIdentity }
        try snapshot.snippets.forEach { try $0.validate() }
        for history in Dictionary(grouping: snapshot.snippets, by: \.snippetID).values {
            let ordered = history.sorted { $0.revision < $1.revision }
            guard ordered.first?.revision == 1,
                  Set(ordered.map(\.revision)).count == ordered.count else {
                throw FastSurveyInboxFailureV1.invalidSupersession
            }
            for (predecessor, successor) in zip(ordered, ordered.dropFirst()) {
                try successor.validateSuccessor(of: predecessor)
            }
        }
        let insertionIDs = snapshot.snippetInsertions.map(\.insertionEventID)
        guard Set(insertionIDs).count == insertionIDs.count else { throw FastSurveyInboxFailureV1.duplicateIdentity }
        let snippetsByRevision = Dictionary(grouping: snapshot.snippets) { "\($0.snippetID.uuidString.lowercased())|\($0.revision)" }
        for insertion in snapshot.snippetInsertions {
            guard let snippet = snippetsByRevision["\(insertion.snippetID.uuidString.lowercased())|\(insertion.snippetRevision)"]?.first else {
                throw FastSurveyInboxFailureV1.invalidValue
            }
            try insertion.validate(snippet: snippet)
        }
        let receiptIDs = snapshot.receipts.map(\.mutationID)
        guard Set(receiptIDs).count == receiptIDs.count else { throw FastSurveyInboxFailureV1.duplicateIdentity }
        try snapshot.receipts.forEach { try $0.validate() }
        let receipts = Dictionary(uniqueKeysWithValues: snapshot.receipts.map { ($0.mutationID, $0) })
        var effectSemantics: [MutationIDV1: Set<String>] = [:]
        for item in snapshot.inboxItems { effectSemantics[item.mutationID, default: []].insert(item.itemSHA256) }
        for promotion in snapshot.promotions { effectSemantics[promotion.mutationID, default: []].insert(promotion.promotionSHA256) }
        for snippet in snapshot.snippets { effectSemantics[snippet.mutationID, default: []].insert(snippet.snippetSHA256) }
        for insertion in snapshot.snippetInsertions { effectSemantics[insertion.mutationID, default: []].insert(insertion.insertionSHA256) }
        guard Set(effectSemantics.keys) == Set(receipts.keys) else { throw FastSurveyInboxFailureV1.receiptMismatch }
        for (mutationID, semantics) in effectSemantics {
            guard receipts[mutationID]?.recoveryState == .receiptCommitted,
                  receipts[mutationID]?.semanticSHA256s == semantics.sorted() else {
                throw FastSurveyInboxFailureV1.receiptMismatch
            }
        }
    }

    private let source: FastSurveyInboxSwiftDataQuerySourceV1
    private let submit: (@MainActor (FastSurveyInboxMutationCommandV1) throws -> FastSurveyInboxMutationReceiptV1)?
    private let receiptLookup: (@MainActor (FastSurveyInboxMutationCommandV1) throws -> FastSurveyInboxMutationReceiptV1?)?

    @MainActor init(modelContext: ModelContext, workspaceID: WorkspaceID) {
        source = .init(modelContext: modelContext, workspaceID: workspaceID)
        submit = nil; receiptLookup = nil
    }

    /// Production binding for replay: commands use the one incumbent writer
    /// transaction, while reads remain concrete SwiftData composition.
    @MainActor init(workspaceWriter: WorkspaceWriterV1, modelContext: ModelContext, workspaceID: WorkspaceID) {
        source = .init(modelContext: modelContext, workspaceID: workspaceID)
        submit = { try workspaceWriter.commitFastSurveyInbox($0) }
        receiptLookup = { try workspaceWriter.fastSurveyInboxReceipt(for: $0) }
    }

    @MainActor func snapshot() throws -> Snapshot { try source.snapshot() }
    @MainActor func search(_ query: FastSurveyInboxQueryV1) throws -> FastSurveyInboxQueryResultV1 {
        try source.result(for: query)
    }

    /// Explicit C11 export contains bounded canonical text and immutable
    /// content references only; it never serializes original media bytes.
    @MainActor func backup() throws -> Data {
        try WorkspaceMutationCanonicalV1.data(try snapshot())
    }

    @MainActor func exportCanonical() throws -> Data { try backup() }

    @MainActor func decodeBackup(_ data: Data) throws -> Snapshot {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let snapshot = try decoder.decode(Snapshot.self, from: data)
        try Self.validate(snapshot)
        return snapshot
    }

    /// V48 is additive: V47 becomes a deterministically empty inbox state.
    @MainActor func migrate(_ data: Data, from schemaVersion: Int) throws -> Data {
        switch schemaVersion {
        case FastSurveyInboxSchemaV1.predecessorSchemaVersion:
            return try WorkspaceMutationCanonicalV1.data(Snapshot(inboxItems: [], promotions: [], snippets: [], snippetInsertions: [], receipts: []))
        case FastSurveyInboxSchemaV1.schemaVersion:
            _ = try decodeBackup(data); return data
        default: throw FastSurveyInboxFailureV1.incompatibleVersion
        }
    }

    @MainActor func replaceRestore(_ snapshot: FastSurveyInboxBackupSnapshotV1) throws {
        try snapshot.validate(); try source.replaceRestore(snapshot)
    }

    /// Replay validates the original command binding before returning a durable
    /// receipt, and never duplicates a promotion's paired effects.
    @MainActor func replay(_ command: FastSurveyInboxMutationCommandV1) throws -> FastSurveyInboxMutationReceiptV1 {
        try command.validate()
        guard let submit, let receiptLookup else { throw FastSurveyInboxFailureV1.invalidValue }
        if let receipt = try receiptLookup(command) { try receipt.validate(command: command); return receipt }
        let receipt = try submit(command); try receipt.validate(command: command); return receipt
    }

    /// C11 owns no asset/site row. Ordinary deletion remains the incumbent
    /// whole-sign cascade and intentionally retains this reviewable immutable
    /// inbox history; the concrete overload below executes that one route.
    @MainActor func delete() throws {
        try FastSurveyInboxWholeSignDeletionPolicyV1.validate()
    }

    @MainActor func delete(assetID: UUID, using service: WholeSignDeletionService) async throws
        -> WholeSignDeletionOutcome {
        try delete()
        return try await service.delete(assetID: assetID)
    }

    /// Whole-workspace Erase is the sole destructive C11 lifecycle route. It
    /// delegates the generation swap to EraseAllService, whose publication
    /// policy verifies all five V48 families are absent in the new generation.
    @MainActor func erase(
        confirmation: String,
        using service: EraseAllService,
        coordinator: StoreSessionCoordinator,
        diagnosticsStore: DiagnosticsStore,
        activate: @escaping @MainActor (StoreGenerationSession) async -> Void,
        lifecycleDependencies: WorkspacePackageLifecycleDependenciesV1
    ) async throws -> EraseAllOutcome {
        try FastSurveyInboxKernelDeletionEraseEnrollmentV1.validate()
        return try await service.erase(
            confirmation: confirmation, coordinator: coordinator,
            diagnosticsStore: diagnosticsStore, activate: activate,
            lifecycleDependencies: lifecycleDependencies
        )
    }

    struct Report: Equatable, Sendable {
        let unassignedInboxCount: Int
        let promotedInboxCount: Int
        let promotionCount: Int
        let activeSnippetCount: Int
        /// C11 never contributes a completed inspection/finding/report count.
        let completedInspectionContribution: Int
    }

    @MainActor func report() throws -> Report {
        let values = try snapshot()
        return .init(unassignedInboxCount: values.inboxItems.filter(\.isUnassigned).count,
                     promotedInboxCount: values.inboxItems.filter { $0.state == .promoted }.count,
                     promotionCount: values.promotions.count,
                     activeSnippetCount: values.snippets.filter { $0.state == .active }.count,
                     completedInspectionContribution: 0)
    }
}

@MainActor
final class FastSurveyInboxSwiftDataQuerySourceV1 {
    private let modelContext: ModelContext
    private let workspaceID: WorkspaceID

    init(modelContext: ModelContext, workspaceID: WorkspaceID) {
        self.modelContext = modelContext
        self.workspaceID = workspaceID
    }

    func snapshot() throws -> FastSurveyInboxLifecycleAdapterV1.Snapshot {
        let itemRows = try modelContext.fetch(FetchDescriptor<CaptureInboxItemRowV1>())
            .filter { $0.workspaceID == workspaceID.rawValue }
        let items = try itemRows.map { try $0.value() }
        guard Set(items.map(\.inboxEventID)).count == items.count else {
            throw FastSurveyInboxPersistenceFailureV1.duplicateIdentity
        }
        let itemsByID = Dictionary(grouping: items, by: \.inboxItemID)
        let promotionRows = try modelContext.fetch(FetchDescriptor<CapturePromotionRowV1>())
            .filter { $0.workspaceID == workspaceID.rawValue }
        let promotions = try promotionRows.map { row -> CapturePromotionV1 in
            guard let source = itemsByID[row.sourceInboxItemID]?.first(where: { $0.revision == 1 }),
                  let promoted = itemsByID[row.sourceInboxItemID]?.first(where: { $0.revision == 2 }) else {
                throw FastSurveyInboxPersistenceFailureV1.corruptRow
            }
            return try row.value(source: source, promotedItem: promoted)
        }
        guard Set(promotions.map(\.promotionID)).count == promotions.count else {
            throw FastSurveyInboxPersistenceFailureV1.duplicateIdentity
        }
        let snippets = try modelContext.fetch(FetchDescriptor<SnippetRowV1>())
            .filter { $0.workspaceID == workspaceID.rawValue }.map { try $0.value() }
        guard Set(snippets.map(\.snippetEventID)).count == snippets.count else {
            throw FastSurveyInboxPersistenceFailureV1.duplicateIdentity
        }
        let snippetsByRevision = Dictionary(grouping: snippets) {
            "\($0.snippetID.uuidString.lowercased())|\($0.revision)"
        }
        let insertions = try modelContext.fetch(FetchDescriptor<SnippetInsertionHistoryRowV1>())
            .filter { $0.workspaceID == workspaceID.rawValue }.map { row -> SnippetInsertionV1 in
                let value = try row.value()
                guard let snippet = snippetsByRevision["\(value.snippetID.uuidString.lowercased())|\(value.snippetRevision)"]?.first else {
                    throw FastSurveyInboxPersistenceFailureV1.corruptRow
                }
                return try row.value(snippet: snippet)
            }
        guard Set(insertions.map(\.insertionEventID)).count == insertions.count else {
            throw FastSurveyInboxPersistenceFailureV1.duplicateIdentity
        }
        let receipts = try modelContext.fetch(FetchDescriptor<FastSurveyInboxMutationReceiptRowV1>())
            .filter { $0.workspaceID == workspaceID.rawValue }.map { try $0.value() }
        let snapshot = FastSurveyInboxLifecycleAdapterV1.Snapshot(
            inboxItems: items, promotions: promotions, snippets: snippets, snippetInsertions: insertions, receipts: receipts
        )
        try FastSurveyInboxLifecycleAdapterV1.validate(snapshot)
        return snapshot
    }

    func result(for query: FastSurveyInboxQueryV1) throws -> FastSurveyInboxQueryResultV1 {
        guard query.workspaceID == workspaceID else { throw FastSurveyInboxFailureV1.wrongWorkspace }
        let snapshot = try snapshot()
        let latestItems = Dictionary(grouping: snapshot.inboxItems, by: \.inboxItemID).values.compactMap {
            $0.max { $0.revision < $1.revision }
        }
        let latestSnippets = Dictionary(grouping: snapshot.snippets, by: \.snippetID).values.compactMap {
            $0.max { $0.revision < $1.revision }
        }
        func projection(_ item: CaptureInboxItemV1) throws -> CaptureInboxItemProjectionV1 {
            if item.state == .unassigned { return .unassigned(item) }
            guard let promotionID = item.promotionID,
                  let promotion = snapshot.promotions.first(where: { $0.promotionID == promotionID }) else {
                throw FastSurveyInboxFailureV1.invalidPromotion
            }
            guard let source = snapshot.inboxItems.first(where: {
                $0.inboxItemID == item.inboxItemID && $0.revision == 1
            }) else { throw FastSurveyInboxFailureV1.invalidPromotion }
            return .promoted(try .init(sourceItem: source, promotedItem: item, promotion: promotion))
        }
        switch query.target {
        case let .inboxItem(id):
            guard let item = latestItems.first(where: { $0.inboxItemID == id }) else { return .notFound(query) }
            return .inboxItem(try projection(item))
        case .unassignedItems:
            let values = try latestItems.filter(\.isUnassigned).sorted {
                ($0.temporalContext.recordedAtUTC, $0.inboxItemID.uuidString)
                    < ($1.temporalContext.recordedAtUTC, $1.inboxItemID.uuidString)
            }.prefix(query.maximumResults).map(projection)
            return .inboxItems(values)
        case let .promotion(id):
            guard let promotion = snapshot.promotions.first(where: { $0.promotionID == id }),
                  let source = snapshot.inboxItems.first(where: {
                      $0.inboxItemID == promotion.sourceInboxItemID && $0.revision == 1
                  }), let promoted = snapshot.inboxItems.first(where: {
                      $0.inboxItemID == promotion.sourceInboxItemID && $0.revision == promotion.promotedInboxRevision
                  }) else { return .notFound(query) }
            return .promotion(try .init(sourceItem: source, promotedItem: promoted, promotion: promotion))
        case let .snippet(id):
            return latestSnippets.first(where: { $0.snippetID == id }).map(FastSurveyInboxQueryResultV1.snippet) ?? .notFound(query)
        case let .applicableSnippets(applicability):
            let values = latestSnippets.filter { $0.state == .active && ($0.applicability == applicability || $0.applicability.scope == .allLocalSurveys) }
                .sorted { ($0.editedAt, $0.snippetID.uuidString) < ($1.editedAt, $1.snippetID.uuidString) }
            return .snippets(Array(values.prefix(query.maximumResults)))
        case let .snippetInsertion(id):
            guard let insertion = snapshot.snippetInsertions.first(where: { $0.insertionEventID == id }) else {
                return .notFound(query)
            }
            return .snippetInsertion(try .init(insertion: insertion))
        case let .snippetInsertions(target):
            let values = snapshot.snippetInsertions.filter { $0.target == target }
                .sorted { ($0.insertedAt, $0.insertionEventID.uuidString) < ($1.insertedAt, $1.insertionEventID.uuidString) }
                .prefix(query.maximumResults)
            return .snippetInsertions(try values.map { try .init(insertion: $0) })
        }
    }

    func replaceRestore(_ backup: FastSurveyInboxBackupSnapshotV1) throws {
        try backup.validate()
        let provenanceKeys = backup.effectProvenance.map {
            "\($0.mutationID.uuidString.lowercased())|\($0.semanticSHA256)"
        }
        guard Set(provenanceKeys).count == provenanceKeys.count else {
            throw FastSurveyInboxPersistenceFailureV1.duplicateIdentity
        }
        let receiptIDs = backup.receipts.map(\.mutationID)
        guard Set(receiptIDs).count == receiptIDs.count else {
            throw FastSurveyInboxPersistenceFailureV1.duplicateIdentity
        }
        let provenance = Dictionary(uniqueKeysWithValues: backup.effectProvenance.map {
            ("\($0.mutationID.uuidString.lowercased())|\($0.semanticSHA256)", $0.writerInstanceID)
        })
        let receipts = Dictionary(uniqueKeysWithValues: backup.receipts.map { ($0.mutationID, $0) })
        let inboxByID = Dictionary(grouping: backup.inboxItems, by: \.inboxItemID)
        func receiptAndWriter(_ mutationID: MutationIDV1, _ semantic: String) throws -> (FastSurveyInboxMutationReceiptV1, UUID) {
            guard let receipt = receipts[mutationID],
                  let writer = provenance["\(mutationID.rawValue.uuidString.lowercased())|\(semantic)"] else {
                throw FastSurveyInboxPersistenceFailureV1.receiptMismatch
            }
            return (receipt, writer)
        }
        try modelContext.delete(model: CaptureInboxItemRowV1.self)
        try modelContext.delete(model: CapturePromotionRowV1.self)
        try modelContext.delete(model: SnippetRowV1.self)
        try modelContext.delete(model: SnippetInsertionHistoryRowV1.self)
        try modelContext.delete(model: FastSurveyInboxMutationReceiptRowV1.self)
        for item in backup.inboxItems.sorted(by: { $0.revision < $1.revision }) {
            let promotion = item.promotionID.flatMap { id in backup.promotions.first { $0.promotionID == id } }
            let (receipt, writer) = try receiptAndWriter(item.mutationID, item.itemSHA256)
            modelContext.insert(try CaptureInboxItemRowV1(restoring: item, promotion: promotion,
                                                           receipt: receipt, writerInstanceID: writer))
        }
        for promotion in backup.promotions {
            guard let source = inboxByID[promotion.sourceInboxItemID]?.first(where: { $0.revision == 1 }),
                  let promoted = inboxByID[promotion.sourceInboxItemID]?.first(where: { $0.revision == 2 }) else {
                throw FastSurveyInboxPersistenceFailureV1.corruptRow
            }
            let (receipt, writer) = try receiptAndWriter(promotion.mutationID, promotion.promotionSHA256)
            modelContext.insert(try CapturePromotionRowV1(restoring: promotion, source: source,
                                                           promotedItem: promoted, receipt: receipt,
                                                           writerInstanceID: writer))
        }
        for snippet in backup.snippets {
            let (receipt, writer) = try receiptAndWriter(snippet.mutationID, snippet.snippetSHA256)
            modelContext.insert(try SnippetRowV1(restoring: snippet, receipt: receipt, writerInstanceID: writer))
        }
        let restoredSnippets = Dictionary(grouping: backup.snippets) {
            "\($0.snippetID.uuidString.lowercased())|\($0.revision)"
        }
        for insertion in backup.snippetInsertions {
            guard let snippet = restoredSnippets["\(insertion.snippetID.uuidString.lowercased())|\(insertion.snippetRevision)"]?.first else {
                throw FastSurveyInboxPersistenceFailureV1.corruptRow
            }
            let (receipt, writer) = try receiptAndWriter(insertion.mutationID, insertion.insertionSHA256)
            modelContext.insert(try SnippetInsertionHistoryRowV1(restoring: insertion, receipt: receipt, writerInstanceID: writer))
            try insertion.validate(snippet: snippet)
        }
        for receipt in backup.receipts { modelContext.insert(try FastSurveyInboxMutationReceiptRowV1(receipt)) }
    }
}

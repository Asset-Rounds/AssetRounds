import Foundation

/// C44 composes incumbent catalog persistence, replay, and the work-resource
/// atomic writer. It owns no store, durable draft, route, or second writer.
@MainActor final class PartsStockWorkflowCoordinatorV1 {
    private let stock: PartsStockCoordinatorV1
    private let workResources: ManualWorkResourceWorkflowCoordinatorV1
    private let lifecycle: PartsStockLifecycleAdapterV1
    let featurePolicy: LocalStockFeaturePolicyV1

    init(stock: PartsStockCoordinatorV1, workResources: ManualWorkResourceWorkflowCoordinatorV1, lifecycle: PartsStockLifecycleAdapterV1, featurePolicy: LocalStockFeaturePolicyV1 = .enabled) {
        self.stock = stock; self.workResources = workResources; self.lifecycle = lifecycle; self.featurePolicy = featurePolicy
    }

    func catalog(workspaceID: WorkspaceID) throws -> [LocalPartDefinitionV1] {
        try validatedCatalogRows(lifecycle.search(workspaceID: workspaceID, query: ""), workspaceID: workspaceID)
    }

    /// Both typed and stock-namespaced scan lookup are queries. They do not
    /// change stock or create a scan history.
    func lookup(workspaceID: WorkspaceID, request: PartsStockWorkflowLookupV1) throws -> [LocalPartDefinitionV1] {
        try request.validate()
        return try validatedCatalogRows(lifecycle.search(workspaceID: workspaceID, query: request.queryText), workspaceID: workspaceID)
    }

    func detail(workspaceID: WorkspaceID, partID: UUID) throws -> PartsStockWorkflowCatalogDetailV1 {
        guard let part = try catalog(workspaceID: workspaceID).first(where: { $0.partID == partID }) else { throw PartsStockFailureV1.invalidValue }
        let attention = try lowStock(workspaceID: workspaceID).filter { $0.partID == partID }
        return try PartsStockWorkflowCatalogDetailV1(part: part, attention: attention)
    }

    func lowStock(workspaceID: WorkspaceID) throws -> [StockAttentionProjectionV1] {
        let parts = try catalog(workspaceID: workspaceID).filter { !$0.archived && $0.preferredMinimum != nil }
        let balances = try lifecycle.replay(workspaceID: workspaceID)
        return try attention(parts: parts, balances: balances)
    }

    /// A caller that knows the active locations must use this path. It asks the
    /// incumbent projection for every active catalog/location pair, retaining
    /// UNKNOWN for never-counted stock rather than manufacturing a zero.
    func lowStock(workspaceID: WorkspaceID, locations: [StockStorageLocationV1]) throws -> [StockAttentionProjectionV1] {
        guard Set(locations.map(\.locationID)).count == locations.count else { throw PartsStockFailureV1.invalidValue }
        try locations.forEach { try $0.validate() }
        guard locations.allSatisfy({ $0.workspaceID == workspaceID }) else { throw PartsStockFailureV1.crossWorkspace }
        let parts = try catalog(workspaceID: workspaceID).filter { !$0.archived && $0.preferredMinimum != nil }
        let activeLocations = locations.filter { !$0.archived }
        let balances = try parts.flatMap { part in
            try activeLocations.map { try lifecycle.projection(workspaceID: workspaceID, partID: part.partID, locationID: $0.locationID, unit: part.canonicalUnit) }
        }
        return try attention(parts: parts, balances: balances)
    }

    private func attention(parts: [LocalPartDefinitionV1], balances: [StockBalanceProjectionV1]) throws -> [StockAttentionProjectionV1] {
        guard Set(balances.map { "\($0.partID.uuidString)|\($0.locationID.uuidString)" }).count == balances.count else { throw PartsStockFailureV1.staleRevision }
        return try balances.compactMap { balance in
            guard let part = parts.first(where: { $0.partID == balance.partID }), let minimum = part.preferredMinimum else { return nil }
            try balance.validate()
            guard balance.workspaceID == part.workspaceID else { throw PartsStockFailureV1.crossWorkspace }
            guard balance.unit == part.canonicalUnit else { throw PartsStockFailureV1.invalidValue }
            let below: Bool
            switch balance.balance {
            case .unknown: below = false
            case let .known(value):
                try value.validate(for: part.canonicalUnit)
                try minimum.validate(for: part.canonicalUnit)
                below = try value.isLessThan(minimum)
            }
            return StockAttentionProjectionV1(partID: balance.partID, locationID: balance.locationID, isBelowPreferred: below, balance: balance.balance)
        }.sorted { ($0.partID.uuidString, $0.locationID.uuidString) < ($1.partID.uuidString, $1.locationID.uuidString) }
    }

    func report(workspaceID: WorkspaceID, reviewedPartIDs: Set<UUID>) throws -> PartsStockReportV1 {
        try lifecycle.report(workspaceID: workspaceID, reviewedPartIDs: reviewedPartIDs)
    }

    @discardableResult func count(movementID: UUID = UUID(), part: LocalPartDefinitionV1, location: StockStorageLocationV1, observed: StockQuantityV1, current: StockBalanceProjectionV1, opening: Bool, actor: ActorSnapshotV1, occurredAt: Date, recordedAt: Date) throws -> (StockMovementEventV1, PartsStockMutationReceiptV1) {
        try requireWrites(); return try stock.count(movementID: movementID, part: part, location: location, observed: observed, current: current, opening: opening, actor: actor, occurredAt: occurredAt, recordedAt: recordedAt)
    }

    @discardableResult func adjust(movementID: UUID = UUID(), part: LocalPartDefinitionV1, location: StockStorageLocationV1, magnitude: StockQuantityV1, increase: Bool, reason: String, current: StockBalanceProjectionV1, actor: ActorSnapshotV1, occurredAt: Date, recordedAt: Date) throws -> (StockMovementEventV1, PartsStockMutationReceiptV1) {
        try requireWrites(); return try stock.adjust(movementID: movementID, part: part, location: location, magnitude: magnitude, increase: increase, reason: reason, current: current, actor: actor, occurredAt: occurredAt, recordedAt: recordedAt)
    }

    @discardableResult func transfer(outboundID: UUID = UUID(), inboundID: UUID = UUID(), part: LocalPartDefinitionV1, source: StockStorageLocationV1, destination: StockStorageLocationV1, quantity: StockQuantityV1, sourceBalance: StockBalanceProjectionV1, destinationBalance: StockBalanceProjectionV1, actor: ActorSnapshotV1, occurredAt: Date, recordedAt: Date) throws -> (StockTransferReceiptV1, PartsStockMutationReceiptV1) {
        try requireWrites(); return try stock.transfer(outboundID: outboundID, inboundID: inboundID, part: part, source: source, destination: destination, quantity: quantity, sourceBalance: sourceBalance, destinationBalance: destinationBalance, actor: actor, occurredAt: occurredAt, recordedAt: recordedAt)
    }

    @discardableResult func archive(predecessor: LocalPartDefinitionV1, completeBalances: [StockBalanceProjectionV1]) throws -> (StockPartRetirementReceiptV1, PartsStockMutationReceiptV1) {
        try requireWrites(); return try stock.retirePart(predecessor: predecessor, completeBalances: completeBalances)
    }

    /// The only C44 path that consumes stock delegates to the existing
    /// .useFromStock workflow command, which appends stock and its work
    /// successor in one incumbent writer transaction.
    @discardableResult func use(_ input: ManualWorkResourceUseStockCommandV1, context: ManualWorkResourceWorkflowContextV1) throws -> (StockUseOnWorkReceiptV1, PartsStockMutationReceiptV1) {
        try requireWrites(); try C44ManualWorkResourceBoundaryV1.validateExplicitUse(input, context: context)
        guard case let .stockUsed(use, receipt) = try workResources.execute(.useFromStock(input), context: context) else { throw PartsStockFailureV1.invalidTransition }
        return (use, receipt)
    }

    /// Returns are never standalone: the incumbent workflow validates the
    /// source use, ordered frontier, outstanding quantity, and successor.
    @discardableResult func `return`(_ input: ManualWorkResourceReturnStockCommandV1, context: ManualWorkResourceWorkflowContextV1) throws -> (StockReturnAgainstUseReceiptV1, PartsStockMutationReceiptV1) {
        try requireWrites(); try C44ManualWorkResourceBoundaryV1.validateReturn(input, context: context)
        guard case let .stockReturned(receipt, mutation) = try workResources.execute(.returnToStock(input), context: context) else { throw PartsStockFailureV1.invalidTransition }
        return (receipt, mutation)
    }

    func exportCSV(workspaceID: WorkspaceID) throws -> Data {
        try PartsStockWorkflowCSVCodecV1.export(catalog(workspaceID: workspaceID))
    }

    func previewCSVImport(workspaceID: WorkspaceID, csvBytes: Data) throws -> PartsStockWorkflowCSVImportPlanV1 {
        try PartsStockWorkflowCSVCodecV1.preview(workspaceID: workspaceID, csvBytes: csvBytes)
    }

    /// Each row is an existing receipt-first .upsertPart command. This is a
    /// closed create-only import: any occupied part ID or stock SKU collision
    /// is rejected before writes. Replaying from row zero passes the same row
    /// MutationIDs to the incumbent journal and returns its original receipts.
    func importCSV(_ plan: PartsStockWorkflowCSVImportPlanV1, cancellingAfter committedRowCount: Int? = nil) throws -> PartsStockWorkflowCSVImportResultV1 {
        try requireWrites()
        guard committedRowCount.map({ $0 >= 0 && $0 <= plan.rows.count }) ?? true else { throw PartsStockFailureV1.invalidValue }
        let limit = committedRowCount ?? plan.rows.count
        if limit == 0, !plan.rows.isEmpty {
            return try PartsStockWorkflowCSVImportResultV1(plan: plan, disposition: .cancelled, committedReceipts: [])
        }
        let existing = try catalog(workspaceID: plan.workspaceID)
        let expected = try plan.rows.map { try $0.part(workspaceID: plan.workspaceID) }
        for value in expected {
            if let existingValue = existing.first(where: { $0.partID == value.partID }) {
                // The sole allowed occupied ID is the exact prior receipt-first
                // postimage for this same deterministic row MutationID.
                guard existingValue == value else { throw PartsStockFailureV1.duplicateMutation }
            }
        }
        for value in expected {
            for identity in value.productIdentities {
                let matchingPartIDs = try existing.filter { part in
                    try part.productIdentities.contains { try $0.locatorKey == identity.locatorKey }
                }.map(\.partID)
                guard matchingPartIDs.isEmpty || Set(matchingPartIDs) == Set([value.partID]) else { throw PartsStockFailureV1.duplicateMutation }
            }
        }
        var receipts: [PartsStockMutationReceiptV1] = []
        for row in plan.rows.prefix(limit) {
            do { receipts.append(try stock.c44UpsertImportedPart(row.part(workspaceID: plan.workspaceID))) }
            catch {
                return try PartsStockWorkflowCSVImportResultV1(plan: plan, disposition: .incomplete, committedReceipts: receipts, incompleteAtRowIndex: receipts.count)
            }
        }
        let disposition: PartsStockWorkflowCSVDispositionV1 = limit == plan.rows.count ? .complete : .cancelled
        return try PartsStockWorkflowCSVImportResultV1(plan: plan, disposition: disposition, committedReceipts: receipts)
    }

    private func requireWrites() throws { guard featurePolicy.allowsWrites else { throw PartsStockFailureV1.writesDisabled } }

    private func validatedCatalogRows(_ parts: [LocalPartDefinitionV1], workspaceID: WorkspaceID) throws -> [LocalPartDefinitionV1] {
        try parts.forEach { try $0.validate() }
        guard parts.allSatisfy({ $0.workspaceID == workspaceID }) else { throw PartsStockFailureV1.crossWorkspace }
        guard Set(parts.map(\.partID)).count == parts.count else { throw PartsStockFailureV1.staleRevision }
        return parts
    }
}

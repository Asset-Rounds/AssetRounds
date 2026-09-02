import Foundation

/// Implemented by the existing workspace writer composition. One call is one
/// CAS-protected canonical transaction; the C55 lane owns no parallel store.
@MainActor protocol PartsStockCanonicalWriterPortV1: AnyObject {
    func makeMutationID() throws -> MutationIDV1
    func commitPartsStock(_ mutation: PartsStockMutationV1) throws -> PartsStockMutationReceiptV1
}

private enum PartsStockExactMathV1 {
    static func power10(_ exponent: Int) throws -> Int64 {
        guard (0...3).contains(exponent) else { throw PartsStockFailureV1.invalidValue }
        return [1, 10, 100, 1_000][exponent]
    }
    static func scaled(_ value: StockQuantityV1, to scale: Int) throws -> Int64 {
        guard scale >= value.scale else { throw PartsStockFailureV1.invalidValue }
        let (difference, differenceOverflow) = scale.subtractingReportingOverflow(value.scale)
        guard !differenceOverflow else { throw PartsStockFailureV1.invalidValue }
        let factor = try power10(difference); let (result, overflow) = value.mantissa.multipliedReportingOverflow(by: factor)
        guard !overflow else { throw PartsStockFailureV1.invalidValue }; return result
    }
    static func applying(_ magnitude: StockQuantityV1, to current: StockQuantityV1, unit: StockUnitV1, subtract: Bool) throws -> StockQuantityV1 {
        try current.validate(for: unit); try magnitude.validate(for: unit)
        let scale = max(current.scale, magnitude.scale), lhs = try scaled(current, to: scale), rhs = try scaled(magnitude, to: scale)
        let result: Int64; let overflow: Bool
        if subtract { (result, overflow) = lhs.subtractingReportingOverflow(rhs) } else { (result, overflow) = lhs.addingReportingOverflow(rhs) }
        guard !overflow, result >= 0 else { throw PartsStockFailureV1.insufficientStock }
        return try StockQuantityV1(mantissa: result, scale: scale, unit: unit)
    }
}

@MainActor final class PartsStockCoordinatorV1 {
    private let writer: any PartsStockCanonicalWriterPortV1
    private let featurePolicy: PartsStockFeaturePolicyV1
    init(writer: any PartsStockCanonicalWriterPortV1, featurePolicy: PartsStockFeaturePolicyV1 = .enabled) {
        self.writer = writer; self.featurePolicy = featurePolicy
    }

    @discardableResult func createPart(partID: UUID = UUID(), workspaceID: WorkspaceID, displayName: String, canonicalUnit: StockUnitV1, productIdentities: [StockProductIdentityV1] = [], preferredMinimum: StockQuantityV1? = nil) throws -> (LocalPartDefinitionV1, PartsStockMutationReceiptV1) {
        try requireWritesEnabled()
        let mutationID = try writer.makeMutationID()
        let value = try LocalPartDefinitionV1(partID: partID, workspaceID: workspaceID, displayName: displayName, canonicalUnit: canonicalUnit, productIdentities: productIdentities, preferredMinimum: preferredMinimum, revision: 1, mutationID: mutationID)
        return (value, try commit(.upsertPart(value)))
    }

    /// C44 CSV import supplies a deterministic row MutationID. Keeping this
    /// raw command here preserves the incumbent receipt-first journal retry;
    /// the workflow layer preflights only create-only IDs and product keys.
    @discardableResult func c44UpsertImportedPart(_ value: LocalPartDefinitionV1) throws -> PartsStockMutationReceiptV1 {
        try requireWritesEnabled(); try value.validate()
        guard value.revision == 1, !value.archived else { throw PartsStockFailureV1.invalidTransition }
        return try commit(.upsertPart(value))
    }

    @discardableResult func revisePart(predecessor: LocalPartDefinitionV1, displayName: String, canonicalUnit: StockUnitV1, productIdentities: [StockProductIdentityV1], preferredMinimum: StockQuantityV1?, hasMovementHistory: Bool) throws -> (LocalPartDefinitionV1, PartsStockMutationReceiptV1) {
        try requireWritesEnabled()
        try predecessor.validate(); guard !predecessor.archived, !hasMovementHistory || canonicalUnit == predecessor.canonicalUnit else { throw PartsStockFailureV1.invalidTransition }
        let (next, overflow) = predecessor.revision.addingReportingOverflow(1); guard !overflow else { throw PartsStockFailureV1.invalidValue }
        let mutationID = try writer.makeMutationID()
        let value = try LocalPartDefinitionV1(partID: predecessor.partID, workspaceID: predecessor.workspaceID, displayName: displayName, canonicalUnit: canonicalUnit, productIdentities: productIdentities, preferredMinimum: preferredMinimum, archived: false, revision: next, mutationID: mutationID)
        return (value, try commit(.upsertPart(value)))
    }

    @discardableResult func retirePart(predecessor: LocalPartDefinitionV1, completeBalances: [StockBalanceProjectionV1]) throws -> (StockPartRetirementReceiptV1, PartsStockMutationReceiptV1) {
        try requireWritesEnabled()
        try predecessor.validate(); let (next, overflow) = predecessor.revision.addingReportingOverflow(1); guard !overflow else { throw PartsStockFailureV1.invalidValue }
        let mutationID = try writer.makeMutationID()
        let archived = try LocalPartDefinitionV1(partID: predecessor.partID, workspaceID: predecessor.workspaceID, displayName: predecessor.displayName, canonicalUnit: predecessor.canonicalUnit, productIdentities: predecessor.productIdentities, preferredMinimum: predecessor.preferredMinimum, archived: true, revision: next, mutationID: mutationID)
        let receipt = try StockPartRetirementReceiptV1(archivedPartSuccessor: archived, predecessor: predecessor, verifiedBalances: completeBalances)
        return (receipt, try commit(.retirePart(receipt)))
    }

    @discardableResult func saveLocation(_ value: StockStorageLocationV1) throws -> PartsStockMutationReceiptV1 {
        try requireWritesEnabled()
        return try commit(.upsertLocation(value, mutationID: writer.makeMutationID()))
    }

    @discardableResult func count(movementID: UUID = UUID(), part: LocalPartDefinitionV1, location: StockStorageLocationV1, observed: StockQuantityV1, current: StockBalanceProjectionV1, opening: Bool, actor: ActorSnapshotV1, occurredAt: Date, recordedAt: Date) throws -> (StockMovementEventV1, PartsStockMutationReceiptV1) {
        try requireWritesEnabled()
        try require(part: part, location: location, current: current); try observed.validate(for: part.canonicalUnit)
        let mutationID = try writer.makeMutationID()
        let movement = try StockMovementEventV1(movementID: movementID, workspaceID: part.workspaceID, part: part.frozenReference(), locationID: location.locationID, kind: opening ? .openingCount : .physicalCount, quantity: observed, unit: part.canonicalUnit, preBalance: current.balance, postBalance: observed, actor: actor, occurredAt: occurredAt, recordedAt: recordedAt, expectedLocationRevision: current.locationRevision, mutationID: mutationID)
        return (movement, try commit(.appendMovement(movement)))
    }

    @discardableResult func adjust(movementID: UUID = UUID(), part: LocalPartDefinitionV1, location: StockStorageLocationV1, magnitude: StockQuantityV1, increase: Bool, reason: String, current: StockBalanceProjectionV1, actor: ActorSnapshotV1, occurredAt: Date, recordedAt: Date) throws -> (StockMovementEventV1, PartsStockMutationReceiptV1) {
        try requireWritesEnabled()
        try require(part: part, location: location, current: current)
        guard case .known(let known) = current.balance, magnitude.mantissa > 0 else { throw PartsStockFailureV1.unknownBalance }
        let post = try PartsStockExactMathV1.applying(magnitude, to: known, unit: part.canonicalUnit, subtract: !increase), mutationID = try writer.makeMutationID()
        let movement = try StockMovementEventV1(movementID: movementID, workspaceID: part.workspaceID, part: part.frozenReference(), locationID: location.locationID, kind: increase ? .adjustmentIncrease : .adjustmentDecrease, quantity: magnitude, unit: part.canonicalUnit, preBalance: current.balance, postBalance: post, reason: reason, actor: actor, occurredAt: occurredAt, recordedAt: recordedAt, expectedLocationRevision: current.locationRevision, mutationID: mutationID)
        return (movement, try commit(.appendMovement(movement)))
    }

    @discardableResult func transfer(outboundID: UUID = UUID(), inboundID: UUID = UUID(), part: LocalPartDefinitionV1, source: StockStorageLocationV1, destination: StockStorageLocationV1, quantity: StockQuantityV1, sourceBalance: StockBalanceProjectionV1, destinationBalance: StockBalanceProjectionV1, actor: ActorSnapshotV1, occurredAt: Date, recordedAt: Date) throws -> (StockTransferReceiptV1, PartsStockMutationReceiptV1) {
        try requireWritesEnabled()
        try require(part: part, location: source, current: sourceBalance); try require(part: part, location: destination, current: destinationBalance)
        guard source.locationID != destination.locationID, case .known(let from) = sourceBalance.balance, case .known(let to) = destinationBalance.balance, quantity.mantissa > 0 else { throw PartsStockFailureV1.unknownBalance }
        let sourcePost = try PartsStockExactMathV1.applying(quantity, to: from, unit: part.canonicalUnit, subtract: true)
        let destinationPost = try PartsStockExactMathV1.applying(quantity, to: to, unit: part.canonicalUnit, subtract: false)
        let mutationID = try writer.makeMutationID(), frozen = try part.frozenReference()
        let outbound = try StockMovementEventV1(movementID: outboundID, workspaceID: part.workspaceID, part: frozen, locationID: source.locationID, kind: .transferOut, quantity: quantity, unit: part.canonicalUnit, preBalance: sourceBalance.balance, postBalance: sourcePost, relatedMovementID: inboundID, actor: actor, occurredAt: occurredAt, recordedAt: recordedAt, expectedLocationRevision: sourceBalance.locationRevision, mutationID: mutationID)
        let inbound = try StockMovementEventV1(movementID: inboundID, workspaceID: part.workspaceID, part: frozen, locationID: destination.locationID, kind: .transferIn, quantity: quantity, unit: part.canonicalUnit, preBalance: destinationBalance.balance, postBalance: destinationPost, relatedMovementID: outboundID, actor: actor, occurredAt: occurredAt, recordedAt: recordedAt, expectedLocationRevision: destinationBalance.locationRevision, mutationID: mutationID)
        let transfer = StockTransferReceiptV1(workspaceID: part.workspaceID, outbound: outbound, inbound: inbound, mutationID: mutationID); try transfer.validate()
        return (transfer, try commit(.transfer(transfer)))
    }

    @discardableResult func use(receiptID: UUID = UUID(), movementID: UUID = UUID(), frozenMaterialLineID: UUID, part: LocalPartDefinitionV1, source: StockStorageLocationV1, quantity: StockQuantityV1, sourceBalance: StockBalanceProjectionV1, actor: ActorSnapshotV1, occurredAt: Date, recordedAt: Date, mutationID suppliedMutationID: MutationIDV1? = nil, workResourceSuccessor: (MutationIDV1) throws -> WorkResourceEntryV1) throws -> (StockUseOnWorkReceiptV1, PartsStockMutationReceiptV1) {
        try requireWritesEnabled()
        try require(part: part, location: source, current: sourceBalance)
        guard case .known(let known) = sourceBalance.balance, quantity.mantissa > 0 else { throw PartsStockFailureV1.unknownBalance }
        let post = try PartsStockExactMathV1.applying(quantity, to: known, unit: part.canonicalUnit, subtract: true)
        let mutationID: MutationIDV1
        if let suppliedMutationID { mutationID = try MutationIDV1(rawValue: suppliedMutationID.rawValue) }
        else { mutationID = try writer.makeMutationID() }
        let movement = try StockMovementEventV1(movementID: movementID, workspaceID: part.workspaceID, part: part.frozenReference(), locationID: source.locationID, kind: .useOnWork, quantity: quantity, unit: part.canonicalUnit, preBalance: sourceBalance.balance, postBalance: post, actor: actor, occurredAt: occurredAt, recordedAt: recordedAt, expectedLocationRevision: sourceBalance.locationRevision, mutationID: mutationID)
        let use = try StockUseOnWorkReceiptV1(receiptID: receiptID, movement: movement, workResourceSuccessor: workResourceSuccessor(mutationID), frozenMaterialLineID: frozenMaterialLineID, mutationID: mutationID)
        return (use, try commit(.use(use)))
    }

    @discardableResult func reverseUse(receiptID: UUID = UUID(), movementID: UUID = UUID(), sourceUse: StockUseOnWorkReceiptV1, destination: StockStorageLocationV1, destinationBalance: StockBalanceProjectionV1, actor: ActorSnapshotV1, reason: String, occurredAt: Date, recordedAt: Date, workResourceSuccessor: (MutationIDV1) throws -> WorkResourceEntryV1) throws -> (StockUseReversalReceiptV1, PartsStockMutationReceiptV1) {
        try requireWritesEnabled()
        try sourceUse.validate(); guard sourceUse.workspaceID == destination.workspaceID, sourceUse.workspaceID == destinationBalance.workspaceID, sourceUse.movement.part.partID == destinationBalance.partID, destination.locationID == destinationBalance.locationID, case .known(let known) = destinationBalance.balance else { throw PartsStockFailureV1.unknownBalance }
        let post = try PartsStockExactMathV1.applying(sourceUse.movement.quantity, to: known, unit: sourceUse.movement.unit, subtract: false), mutationID = try writer.makeMutationID()
        let movement = try StockMovementEventV1(movementID: movementID, workspaceID: sourceUse.workspaceID, part: sourceUse.movement.part, locationID: destination.locationID, kind: .reverseUse, quantity: sourceUse.movement.quantity, unit: sourceUse.movement.unit, preBalance: destinationBalance.balance, postBalance: post, relatedMovementID: sourceUse.movement.movementID, reason: reason, actor: actor, occurredAt: occurredAt, recordedAt: recordedAt, expectedLocationRevision: destinationBalance.locationRevision, mutationID: mutationID)
        let value = try StockUseReversalReceiptV1(receiptID: receiptID, sourceUse: sourceUse, reversalMovement: movement, workResourceSuccessor: workResourceSuccessor(mutationID), reason: reason, mutationID: mutationID)
        return (value, try commit(.reverseUse(value)))
    }

    @discardableResult func returnAgainstUse(receiptID: UUID = UUID(), movementID: UUID = UUID(), sourceUse: StockUseOnWorkReceiptV1, predecessorFrontier: StockReturnFrontierSnapshotV1?, workResourcePredecessor: WorkResourceEntryV1, destination: StockStorageLocationV1, quantity: StockQuantityV1, destinationBalance: StockBalanceProjectionV1, actor: ActorSnapshotV1, occurredAt: Date, recordedAt: Date, mutationID suppliedMutationID: MutationIDV1? = nil, workResourceSuccessor: (MutationIDV1) throws -> WorkResourceEntryV1) throws -> (StockReturnAgainstUseReceiptV1, PartsStockMutationReceiptV1) {
        try requireWritesEnabled()
        try sourceUse.validate(); guard sourceUse.workspaceID == destination.workspaceID, sourceUse.workspaceID == destinationBalance.workspaceID, destination.locationID == destinationBalance.locationID, sourceUse.movement.part.partID == destinationBalance.partID, case .known(let known) = destinationBalance.balance, quantity.mantissa > 0 else { throw PartsStockFailureV1.unknownBalance }
        let post = try PartsStockExactMathV1.applying(quantity, to: known, unit: sourceUse.movement.unit, subtract: false)
        let mutationID: MutationIDV1
        if let suppliedMutationID { mutationID = try MutationIDV1(rawValue: suppliedMutationID.rawValue) }
        else { mutationID = try writer.makeMutationID() }
        let movement = try StockMovementEventV1(movementID: movementID, workspaceID: sourceUse.workspaceID, part: sourceUse.movement.part, locationID: destination.locationID, kind: .returnAgainstUse, quantity: quantity, unit: sourceUse.movement.unit, preBalance: destinationBalance.balance, postBalance: post, relatedMovementID: sourceUse.movement.movementID, actor: actor, occurredAt: occurredAt, recordedAt: recordedAt, expectedLocationRevision: destinationBalance.locationRevision, mutationID: mutationID)
        let value = try StockReturnAgainstUseReceiptV1(receiptID: receiptID, sourceUse: sourceUse, predecessorFrontier: predecessorFrontier, returnMovement: movement, workResourcePredecessor: workResourcePredecessor, workResourceSuccessor: workResourceSuccessor(mutationID), mutationID: mutationID)
        return (value, try commit(.returnAgainstUse(value)))
    }

    @discardableResult func abandonUnknown(part: LocalPartDefinitionV1, affected: [(location: StockStorageLocationV1, current: StockBalanceProjectionV1)], actor: ActorSnapshotV1, reason: String, recordedAt: Date) throws -> (StockAbandonmentReceiptV1, PartsStockMutationReceiptV1) {
        try requireWritesEnabled()
        guard !affected.isEmpty, Set(affected.map { $0.location.locationID }).count == affected.count else { throw PartsStockFailureV1.invalidValue }
        try affected.forEach { try require(part: part, location: $0.location, current: $0.current); guard case .unknown = $0.current.balance else { throw PartsStockFailureV1.invalidTransition } }
        let mutationID = try writer.makeMutationID()
        let dispositions = try affected.map { value in
            try AbandonUnverifiedStockDispositionV1(dispositionID: UUID(), workspaceID: part.workspaceID, partID: part.partID, locationID: value.location.locationID, actor: actor, reason: reason, lastMovementID: value.current.lastMovementID, lastLocationRevision: value.current.locationRevision, recordedAt: recordedAt, mutationID: mutationID, currentBalance: value.current.balance)
        }
        let (next, overflow) = part.revision.addingReportingOverflow(1); guard !overflow else { throw PartsStockFailureV1.invalidValue }
        let archived = try LocalPartDefinitionV1(partID: part.partID, workspaceID: part.workspaceID, displayName: part.displayName, canonicalUnit: part.canonicalUnit, productIdentities: part.productIdentities, preferredMinimum: part.preferredMinimum, archived: true, revision: next, mutationID: mutationID)
        let value = try StockAbandonmentReceiptV1(dispositions: dispositions, archivedPartSuccessor: archived, predecessor: part)
        return (value, try commit(.abandon(value)))
    }

    private func commit(_ mutation: PartsStockMutationV1) throws -> PartsStockMutationReceiptV1 {
        try requireWritesEnabled()
        try mutation.validate(); let receipt = try writer.commitPartsStock(mutation); try receipt.validate()
        guard receipt.workspaceID == mutation.workspaceID, receipt.mutationID == mutation.mutationID, receipt.mutationSHA256 == (try PartsStockCanonicalCodecV1.sha256(mutation)) else { throw PartsStockFailureV1.invalidDigest }
        return receipt
    }

    private func requireWritesEnabled() throws {
        guard featurePolicy.allowsWrites else { throw PartsStockFailureV1.writesDisabled }
    }

    private func require(part: LocalPartDefinitionV1, location: StockStorageLocationV1, current: StockBalanceProjectionV1) throws {
        try part.validate(); try location.validate(); try current.validate()
        guard !part.archived, !location.archived, part.workspaceID == location.workspaceID, current.workspaceID == part.workspaceID, current.partID == part.partID, current.locationID == location.locationID, current.unit == part.canonicalUnit else { throw PartsStockFailureV1.crossWorkspace }
    }
}

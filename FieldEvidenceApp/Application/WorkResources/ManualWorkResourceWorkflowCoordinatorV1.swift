import Foundation

enum ManualWorkResourceWorkflowFailureV1: Error, Equatable, Sendable {
    case invalidContext
    case stockDisabled
    case stockUnavailable
    case invalidStockUse
    case invalidStockReturn
}

enum ManualWorkResourceStockCapabilityV1: String, Codable, CaseIterable, Sendable {
    case available = "AVAILABLE"
    case disabled = "DISABLED"
    case unavailable = "UNAVAILABLE"
    case manualOnly = "MANUAL_ONLY"
}

struct ManualWorkResourceSuccessorDraftV1: Equatable, Sendable {
    let entryID: UUID
    let workspaceID: WorkspaceID
    let subject: WorkResourceSubjectV1
    let actor: ActorSnapshotV1
    let duration: ManualDurationV1?
    let materials: [ManualMaterialLineV1]
    let directCost: DirectCostEntryV1?
    let visibility: WorkResourceVisibilityV1
    let disposition: WorkResourceDispositionV1
    let voidReason: String?
    let recordedAt: Date
    let predecessor: WorkResourceEntryV1?

    init(
        entryID: UUID = UUID(),
        workspaceID: WorkspaceID,
        subject: WorkResourceSubjectV1,
        actor: ActorSnapshotV1,
        duration: ManualDurationV1? = nil,
        materials: [ManualMaterialLineV1] = [],
        directCost: DirectCostEntryV1? = nil,
        visibility: WorkResourceVisibilityV1 = .internalOnly,
        disposition: WorkResourceDispositionV1 = .active,
        voidReason: String? = nil,
        recordedAt: Date,
        predecessor: WorkResourceEntryV1? = nil
    ) throws {
        try subject.validate(); try actor.validate(); try duration?.validate()
        try materials.forEach { try $0.validate() }; try directCost?.validate()
        guard subject.workspaceID == workspaceID, actor.workspaceID == workspaceID else {
            throw ManualWorkResourceWorkflowFailureV1.invalidContext
        }
        if let predecessor {
            guard predecessor.workspaceID == workspaceID, predecessor.subject == subject else {
                throw ManualWorkResourceWorkflowFailureV1.invalidContext
            }
        }
        try predecessor?.validate()
        self.entryID = entryID; self.workspaceID = workspaceID; self.subject = subject
        self.actor = actor; self.duration = duration; self.materials = materials
        self.directCost = directCost; self.visibility = visibility; self.disposition = disposition
        self.voidReason = voidReason; self.recordedAt = recordedAt; self.predecessor = predecessor
    }

    func entry(mutationID: MutationIDV1) throws -> WorkResourceEntryV1 {
        let expectedRevision = predecessor?.revision ?? 0
        let (revision, overflow) = expectedRevision.addingReportingOverflow(1)
        guard !overflow else { throw WorkResourceContractFailureV1.invalidRevision }
        let value = try WorkResourceEntryV1(
            entryID: entryID,
            workspaceID: workspaceID,
            subject: subject,
            actor: actor,
            duration: duration,
            materials: materials,
            directCost: directCost,
            visibility: visibility,
            disposition: disposition,
            voidReason: voidReason,
            recordedAt: recordedAt,
            expectedRevision: expectedRevision,
            revision: revision,
            supersedesEntryID: predecessor?.entryID,
            supersedesEntrySHA256: predecessor?.entrySHA256,
            mutationID: mutationID
        )
        if let predecessor { try value.validateSuccessor(of: predecessor) }
        return value
    }
}

struct ManualWorkResourceWorkflowContextV1: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let subject: WorkResourceSubjectV1
    let actor: ActorSnapshotV1
    let draftDuration: ManualDurationV1?
    let draftMaterials: [ManualMaterialLineV1]
    let draftDirectCost: DirectCostEntryV1?
    let predecessor: WorkResourceEntryV1?

    init(
        workspaceID: WorkspaceID,
        subject: WorkResourceSubjectV1,
        actor: ActorSnapshotV1,
        draftDuration: ManualDurationV1? = nil,
        draftMaterials: [ManualMaterialLineV1] = [],
        draftDirectCost: DirectCostEntryV1? = nil,
        predecessor: WorkResourceEntryV1? = nil
    ) throws {
        try subject.validate(); try actor.validate(); try draftDuration?.validate()
        try draftMaterials.forEach { try $0.validate() }; try draftDirectCost?.validate()
        try predecessor?.validate()
        guard subject.workspaceID == workspaceID,
              actor.workspaceID == workspaceID,
              Set(draftMaterials.map(\.lineID)).count == draftMaterials.count else {
            throw ManualWorkResourceWorkflowFailureV1.invalidContext
        }
        if let predecessor {
            guard predecessor.workspaceID == workspaceID, predecessor.subject == subject else {
                throw ManualWorkResourceWorkflowFailureV1.invalidContext
            }
        }
        self.workspaceID = workspaceID; self.subject = subject; self.actor = actor
        self.draftDuration = draftDuration; self.draftMaterials = draftMaterials
        self.draftDirectCost = draftDirectCost; self.predecessor = predecessor
    }
}

struct ManualWorkResourceWorkflowProjectionV1: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let duration: ManualDurationV1?
    let materials: [ManualMaterialLineV1]
    let directCost: DirectCostEntryV1?
    let stockCapability: ManualWorkResourceStockCapabilityV1
    let hasDraft: Bool
    let canSaveManualEntry: Bool
    let editingChangesStock: Bool
    let saved: Bool
    let stockChanged: Bool
    let accountingClaimed: Bool
    let invoiceClaimed: Bool
    let availabilityClaimed: Bool
    let approvalOrDeliveryClaimed: Bool
}

struct ManualWorkResourceUseStockCommandV1: Sendable {
    let mutationID: MutationIDV1
    let receiptID: UUID
    let movementID: UUID
    let frozenMaterialLineID: UUID
    let part: LocalPartDefinitionV1
    let source: StockStorageLocationV1
    let quantity: StockQuantityV1
    let sourceBalance: StockBalanceProjectionV1
    let actor: ActorSnapshotV1
    let occurredAt: Date
    let recordedAt: Date
    let workResourceSuccessor: ManualWorkResourceSuccessorDraftV1
}

struct ManualWorkResourceReturnStockCommandV1: Sendable {
    let mutationID: MutationIDV1
    let receiptID: UUID
    let movementID: UUID
    let sourceUse: StockUseOnWorkReceiptV1
    let predecessorFrontier: StockReturnFrontierSnapshotV1?
    let workResourcePredecessor: WorkResourceEntryV1
    let destination: StockStorageLocationV1
    let quantity: StockQuantityV1
    let destinationBalance: StockBalanceProjectionV1
    let actor: ActorSnapshotV1
    let occurredAt: Date
    let recordedAt: Date
    let workResourceSuccessor: ManualWorkResourceSuccessorDraftV1
}

enum ManualWorkResourceWorkflowCommandV1: Sendable {
    case saveManual(WorkResourceEntryV1)
    case useFromStock(ManualWorkResourceUseStockCommandV1)
    case returnToStock(ManualWorkResourceReturnStockCommandV1)
}

enum ManualWorkResourceWorkflowOutcomeV1: Sendable {
    case manualSaved(WorkResourceMutationReceiptV1)
    case stockUsed(StockUseOnWorkReceiptV1, PartsStockMutationReceiptV1)
    case stockReturned(StockReturnAgainstUseReceiptV1, PartsStockMutationReceiptV1)
}

enum ManualWorkResourceWorkflowClaimsV1 {
    static let editingChangesStock = false
    static let createsAccountingTruth = false
    static let createsInvoiceTruth = false
    static let establishesCatalogAvailability = false
    static let establishesApproval = false
    static let establishesDelivery = false
    static let establishesIdentity = false
}

enum C44ManualWorkResourceBoundaryV1 {
    static let typingOrScanningMaterialChangesStock = false
    static let explicitUseCommandIsRequired = true
    static let standaloneReturnIsAllowed = false

    static func validateExplicitUse(_ input: ManualWorkResourceUseStockCommandV1, context: ManualWorkResourceWorkflowContextV1) throws {
        guard input.part.workspaceID == context.workspaceID,
              input.source.workspaceID == context.workspaceID,
              input.sourceBalance.workspaceID == context.workspaceID else {
            throw ManualWorkResourceWorkflowFailureV1.invalidStockUse
        }
    }

    static func validateReturn(_ input: ManualWorkResourceReturnStockCommandV1, context: ManualWorkResourceWorkflowContextV1) throws {
        guard input.sourceUse.workspaceID == context.workspaceID,
              input.destination.workspaceID == context.workspaceID,
              input.destinationBalance.workspaceID == context.workspaceID,
              input.quantity.mantissa > 0 else {
            throw ManualWorkResourceWorkflowFailureV1.invalidStockReturn
        }
    }
}

@MainActor
final class ManualWorkResourceWorkflowCoordinatorV1 {
    private let workResources: WorkResourceCoordinatorV1
    private let stock: PartsStockCoordinatorV1?
    let stockCapability: ManualWorkResourceStockCapabilityV1

    init(
        workResources: WorkResourceCoordinatorV1,
        stock: PartsStockCoordinatorV1? = nil,
        stockCapability: ManualWorkResourceStockCapabilityV1 = .manualOnly
    ) throws {
        guard stockCapability != .available || stock != nil else {
            throw ManualWorkResourceWorkflowFailureV1.stockUnavailable
        }
        self.workResources = workResources; self.stock = stock; self.stockCapability = stockCapability
    }

    func projection(
        context: ManualWorkResourceWorkflowContextV1
    ) -> ManualWorkResourceWorkflowProjectionV1 {
        let hasDraft = context.draftDuration != nil || !context.draftMaterials.isEmpty
            || context.draftDirectCost != nil
        return ManualWorkResourceWorkflowProjectionV1(
            workspaceID: context.workspaceID,
            duration: context.draftDuration,
            materials: context.draftMaterials,
            directCost: context.draftDirectCost,
            stockCapability: stockCapability,
            hasDraft: hasDraft,
            canSaveManualEntry: hasDraft,
            editingChangesStock: false,
            saved: false,
            stockChanged: false,
            accountingClaimed: false,
            invoiceClaimed: false,
            availabilityClaimed: false,
            approvalOrDeliveryClaimed: false
        )
    }

    func execute(
        _ command: ManualWorkResourceWorkflowCommandV1,
        context: ManualWorkResourceWorkflowContextV1
    ) throws -> ManualWorkResourceWorkflowOutcomeV1 {
        switch command {
        case let .saveManual(entry):
            try validate(entry: entry, context: context)
            return .manualSaved(try workResources.append(entry))
        case let .useFromStock(input):
            let stock = try requireStock()
            try validate(use: input, context: context)
            let result = try stock.use(
                receiptID: input.receiptID,
                movementID: input.movementID,
                frozenMaterialLineID: input.frozenMaterialLineID,
                part: input.part,
                source: input.source,
                quantity: input.quantity,
                sourceBalance: input.sourceBalance,
                actor: input.actor,
                occurredAt: input.occurredAt,
                recordedAt: input.recordedAt,
                mutationID: input.mutationID,
                workResourceSuccessor: { mutationID in
                    try input.workResourceSuccessor.entry(mutationID: mutationID)
                }
            )
            return .stockUsed(result.0, result.1)
        case let .returnToStock(input):
            let stock = try requireStock()
            try validate(return: input, context: context)
            let result = try stock.returnAgainstUse(
                receiptID: input.receiptID,
                movementID: input.movementID,
                sourceUse: input.sourceUse,
                predecessorFrontier: input.predecessorFrontier,
                workResourcePredecessor: input.workResourcePredecessor,
                destination: input.destination,
                quantity: input.quantity,
                destinationBalance: input.destinationBalance,
                actor: input.actor,
                occurredAt: input.occurredAt,
                recordedAt: input.recordedAt,
                mutationID: input.mutationID,
                workResourceSuccessor: { mutationID in
                    try input.workResourceSuccessor.entry(mutationID: mutationID)
                }
            )
            return .stockReturned(result.0, result.1)
        }
    }

    private func validate(
        entry: WorkResourceEntryV1,
        context: ManualWorkResourceWorkflowContextV1
    ) throws {
        try entry.validate()
        guard entry.workspaceID == context.workspaceID,
              entry.subject == context.subject,
              entry.actor == context.actor,
              entry.duration == context.draftDuration,
              entry.materials == context.draftMaterials.sorted(by: { $0.lineID.uuidString < $1.lineID.uuidString }),
              entry.directCost == context.draftDirectCost else {
            throw ManualWorkResourceWorkflowFailureV1.invalidContext
        }
        if let predecessor = context.predecessor { try entry.validateSuccessor(of: predecessor) }
    }

    private func validate(
        use input: ManualWorkResourceUseStockCommandV1,
        context: ManualWorkResourceWorkflowContextV1
    ) throws {
        try input.part.validate(); try input.source.validate()
        try input.quantity.validate(for: input.part.canonicalUnit)
        try input.sourceBalance.validate(); try input.actor.validate()
        let successor = try input.workResourceSuccessor.entry(mutationID: input.mutationID)
        guard input.part.workspaceID == context.workspaceID,
              input.source.workspaceID == context.workspaceID,
              input.sourceBalance.workspaceID == context.workspaceID,
              input.actor.workspaceID == context.workspaceID,
              successor.workspaceID == context.workspaceID,
              successor.subject == context.subject,
              successor.materials.contains(where: { line in
                  line.lineID == input.frozenMaterialLineID
                      && line.localPartReference == (try? input.part.frozenReference())
                      && line.quantity.mantissa == input.quantity.mantissa
                      && line.quantity.scale == input.quantity.scale
                      && line.unit == input.part.canonicalUnit.rawValue
              }) else { throw ManualWorkResourceWorkflowFailureV1.invalidStockUse }
    }

    private func validate(
        return input: ManualWorkResourceReturnStockCommandV1,
        context: ManualWorkResourceWorkflowContextV1
    ) throws {
        try input.sourceUse.validate(); try input.predecessorFrontier?.validate()
        try input.workResourcePredecessor.validate(); try input.destination.validate()
        try input.quantity.validate(for: input.sourceUse.movement.unit)
        try input.destinationBalance.validate(); try input.actor.validate()
        let alreadyReturned = input.predecessorFrontier?.resultingReturnedMantissa ?? 0
        let (outstanding, overflow) = input.sourceUse.movement.quantity.mantissa
            .subtractingReportingOverflow(alreadyReturned)
        guard !overflow, outstanding >= input.quantity.mantissa,
              input.quantity.mantissa > 0,
              input.sourceUse.workspaceID == context.workspaceID,
              input.sourceUse.movement.quantity.scale == input.quantity.scale,
              input.sourceUse.movement.part.partID == input.destinationBalance.partID,
              input.sourceUse.movement.part == input.workResourcePredecessor.materials.first(where: {
                  $0.lineID == input.sourceUse.frozenMaterialLineID
              })?.localPartReference,
              input.workResourceSuccessor.predecessor == input.workResourcePredecessor else {
            throw ManualWorkResourceWorkflowFailureV1.invalidStockReturn
        }
    }

    private func requireStock() throws -> PartsStockCoordinatorV1 {
        guard stockCapability != .disabled else {
            throw ManualWorkResourceWorkflowFailureV1.stockDisabled
        }
        guard stockCapability == .available, let stock else {
            throw ManualWorkResourceWorkflowFailureV1.stockUnavailable
        }
        return stock
    }
}

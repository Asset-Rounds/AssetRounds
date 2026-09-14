import Foundation

enum PartsStockReplacementValueProjectionFailureV1: Error, Equatable, Sendable {
    case sameWorkspace
    case invalidSource
    case invalidBinding
    case missingDependency
    case invalidOrder
    case incompleteProjection
}

/// Pure value projection for cross-workspace C55 replacement.
///
/// This type deliberately owns no journal, replica, generation, receipt, row,
/// store, or writer behavior. Restore orchestration supplies already-proven
/// identity bindings and uses the returned genuine domain values when it
/// reissues global history.
enum PartsStockReplacementValueProjectionV1 {
    enum OriginalCatalogBaseline: Equatable, Sendable {
        case part(
            entityRevision: MutationHistoryEntityRevisionV1,
            value: LocalPartDefinitionV1
        )
        case location(
            entityRevision: MutationHistoryEntityRevisionV1,
            value: StockStorageLocationV1
        )
    }

    struct Source: Equatable, Sendable {
        let snapshot: PartsStockBackupSnapshotV1
        let orderedMutations: [PartsStockMutationV1]
        let originalCatalogBaselines: [OriginalCatalogBaseline]

        init(
            snapshot: PartsStockBackupSnapshotV1,
            orderedMutations: [PartsStockMutationV1],
            originalCatalogBaselines: [OriginalCatalogBaseline] = []
        ) {
            self.snapshot = snapshot
            self.orderedMutations = orderedMutations
            self.originalCatalogBaselines = originalCatalogBaselines
        }
    }

    struct ExternalWorkPredecessorRequirement: Equatable, Hashable, Sendable {
        let entryID: UUID
        let revision: UInt64
        let sourceEntrySHA256: String
    }

    struct Requirements: Equatable, Sendable {
        let mutationIDs: [MutationIDV1]
        let workSubjects: [WorkResourceSubjectV1]
        let externalWorkPredecessors: [ExternalWorkPredecessorRequirement]
    }

    struct MutationIDBinding: Equatable, Sendable {
        let source: MutationIDV1
        let target: MutationIDV1
    }

    struct WorkSubjectBinding: Equatable, Sendable {
        let source: WorkResourceSubjectV1
        let target: WorkResourceSubjectV1
    }

    struct ExternalWorkPredecessorBinding: Equatable, Sendable {
        let requirement: ExternalWorkPredecessorRequirement
        let targetEntrySHA256: String
    }

    struct Bindings: Equatable, Sendable {
        let targetWorkspaceID: WorkspaceID
        let mutationIDs: [MutationIDBinding]
        let workSubjects: [WorkSubjectBinding]
        let externalWorkPredecessors: [ExternalWorkPredecessorBinding]

        init(
            targetWorkspaceID: WorkspaceID,
            mutationIDs: [MutationIDBinding],
            workSubjects: [WorkSubjectBinding],
            externalWorkPredecessors: [ExternalWorkPredecessorBinding] = []
        ) {
            self.targetWorkspaceID = targetWorkspaceID
            self.mutationIDs = mutationIDs
            self.workSubjects = workSubjects
            self.externalWorkPredecessors = externalWorkPredecessors
        }
    }

    struct MutationProjection: Equatable, Sendable {
        let source: PartsStockMutationV1
        let target: PartsStockMutationV1
        let sourcePostImages: [MutationPostImageV1]
        let targetPostImages: [MutationPostImageV1]
    }

    struct PartProjection: Equatable, Sendable {
        let source: LocalPartDefinitionV1
        let target: LocalPartDefinitionV1
    }

    struct LocationProjection: Equatable, Sendable {
        let source: StockStorageLocationV1
        let target: StockStorageLocationV1
    }

    struct ActorProjection: Equatable, Sendable {
        let source: ActorSnapshotV1
        let target: ActorSnapshotV1
    }

    struct WorkResourceProjection: Equatable, Sendable {
        let source: WorkResourceEntryV1
        let target: WorkResourceEntryV1
    }

    struct Result: Equatable, Sendable {
        let sourceSnapshotSHA256: String
        let targetSnapshot: PartsStockBackupSnapshotV1
        let mutations: [MutationProjection]
        let parts: [PartProjection]
        let locations: [LocationProjection]
        let actors: [ActorProjection]
        let workResources: [WorkResourceProjection]
    }

    /// Immutable continuation used when root must interleave C49 and C55
    /// projections. Exactly one source mutation is consumed by projectNext.
    struct Cursor: Equatable, Sendable {
        fileprivate let source: Source
        fileprivate let targetWorkspaceID: WorkspaceID
        fileprivate let inventory: Inventory
        fileprivate let targetMutationIDBySourceID: [UUID: MutationIDV1]
        fileprivate let targetSubjectBySource: [WorkResourceSubjectV1: WorkResourceSubjectV1]
        fileprivate var externalBindingByRequirement: [
            ExternalWorkPredecessorRequirement: ExternalWorkPredecessorBinding
        ]
        fileprivate var consumedExternalRequirements: Set<ExternalWorkPredecessorRequirement>
        fileprivate var nextMutationIndex: Int
        fileprivate var mutationProjections: [MutationProjection]
        fileprivate var targetPartByKey: [PartKey: LocalPartDefinitionV1]
        fileprivate var targetLocationByKey: [LocationKey: StockStorageLocationV1]
        fileprivate var targetActorBySource: [ActorSnapshotV1: ActorSnapshotV1]
        fileprivate var targetMovementByKey: [MovementKey: StockMovementEventV1]
        fileprivate var targetUseByKey: [ReceiptKey: StockUseOnWorkReceiptV1]
        fileprivate var targetReversalByKey: [ReceiptKey: StockUseReversalReceiptV1]
        fileprivate var targetReturnByKey: [ReceiptKey: StockReturnAgainstUseReceiptV1]
        fileprivate var targetAbandonmentByKey: [AbandonmentKey: AbandonUnverifiedStockDispositionV1]
        fileprivate var targetWorkByKey: [WorkKey: WorkResourceEntryV1]
    }

    struct Step: Equatable, Sendable {
        let cursor: Cursor
        let projection: MutationProjection
    }

    static func requirements(for source: Source) throws -> Requirements {
        let inventory = try makeInventory(source)
        return inventory.requirements
    }

    static func begin(_ source: Source, bindings: Bindings) throws -> Cursor {
        let inventory = try makeInventory(source)
        guard source.snapshot.workspaceID != bindings.targetWorkspaceID else {
            throw PartsStockReplacementValueProjectionFailureV1.sameWorkspace
        }

        let targetMutationIDBySourceID = try mutationBindings(
            bindings.mutationIDs,
            requirements: inventory.requirements.mutationIDs
        )
        let targetSubjectBySource = try subjectBindings(
            bindings.workSubjects,
            requirements: inventory.requirements.workSubjects,
            targetWorkspaceID: bindings.targetWorkspaceID
        )
        let externalBindingByRequirement = try externalBindings(
            bindings.externalWorkPredecessors,
            requirements: inventory.requirements.externalWorkPredecessors
        )

        var targetActorBySource: [ActorSnapshotV1: ActorSnapshotV1] = [:]
        for actor in inventory.actors.sorted(by: actorLessThan) {
            let reference = try LocalActorReferenceV1(
                actorReferenceID: actor.actor.actorReferenceID,
                workspaceID: bindings.targetWorkspaceID,
                partyID: actor.actor.partyID,
                displayName: actor.actor.displayName
            )
            let target = try ActorSnapshotV1(
                snapshotID: actor.snapshotID,
                workspaceID: bindings.targetWorkspaceID,
                actor: reference,
                responsibility: actor.responsibility,
                displayNameAtTime: actor.displayNameAtTime,
                capturedAt: actor.capturedAt
            )
            guard targetActorBySource.updateValue(target, forKey: actor) == nil else {
                throw PartsStockReplacementValueProjectionFailureV1.invalidSource
            }
        }

        var targetPartByKey: [PartKey: LocalPartDefinitionV1] = [:]
        for sourcePart in inventory.parts.values.sorted(by: partLessThan) {
            guard let mutationID = targetMutationIDBySourceID[sourcePart.mutationID.rawValue] else {
                throw PartsStockReplacementValueProjectionFailureV1.missingDependency
            }
            let target = try LocalPartDefinitionV1(
                partID: sourcePart.partID,
                workspaceID: bindings.targetWorkspaceID,
                displayName: sourcePart.displayName,
                canonicalUnit: sourcePart.canonicalUnit,
                productIdentities: sourcePart.productIdentities,
                preferredMinimum: sourcePart.preferredMinimum,
                archived: sourcePart.archived,
                revision: sourcePart.revision,
                mutationID: mutationID
            )
            targetPartByKey[PartKey(sourcePart)] = target
        }

        var targetLocationByKey: [LocationKey: StockStorageLocationV1] = [:]
        for sourceLocation in inventory.locations.values.sorted(by: locationLessThan) {
            let target = try StockStorageLocationV1(
                locationID: sourceLocation.locationID,
                workspaceID: bindings.targetWorkspaceID,
                kind: sourceLocation.kind,
                label: sourceLocation.label,
                binLabel: sourceLocation.binLabel,
                revision: sourceLocation.revision,
                archived: sourceLocation.archived
            )
            targetLocationByKey[try LocationKey(sourceLocation)] = target
        }

        return Cursor(
            source: source,
            targetWorkspaceID: bindings.targetWorkspaceID,
            inventory: inventory,
            targetMutationIDBySourceID: targetMutationIDBySourceID,
            targetSubjectBySource: targetSubjectBySource,
            externalBindingByRequirement: externalBindingByRequirement,
            consumedExternalRequirements: [],
            nextMutationIndex: 0,
            mutationProjections: [],
            targetPartByKey: targetPartByKey,
            targetLocationByKey: targetLocationByKey,
            targetActorBySource: targetActorBySource,
            targetMovementByKey: [:],
            targetUseByKey: [:],
            targetReversalByKey: [:],
            targetReturnByKey: [:],
            targetAbandonmentByKey: [:],
            targetWorkByKey: [:]
        )
    }

    static func projectNext(
        _ input: Cursor,
        externalWorkPredecessors: [ExternalWorkPredecessorBinding] = []
    ) throws -> Step {
        guard input.nextMutationIndex < input.source.orderedMutations.count else {
            throw PartsStockReplacementValueProjectionFailureV1.incompleteProjection
        }
        var cursor = input
        let supplied = try addExternalBindings(externalWorkPredecessors, to: &cursor)
        let consumedBefore = cursor.consumedExternalRequirements
        let sourceMutation = cursor.source.orderedMutations[cursor.nextMutationIndex]
        let targetMutation = try projectMutation(
            sourceMutation,
            index: cursor.nextMutationIndex,
            cursor: &cursor
        )
        let newlyConsumed = cursor.consumedExternalRequirements.subtracting(consumedBefore)
        guard supplied.isSubset(of: newlyConsumed) else {
            throw PartsStockReplacementValueProjectionFailureV1.invalidBinding
        }
        try targetMutation.validate()
        let projection = MutationProjection(
            source: sourceMutation,
            target: targetMutation,
            sourcePostImages: try sourceMutation.mutationPostImages,
            targetPostImages: try targetMutation.mutationPostImages
        )
        cursor.mutationProjections.append(projection)
        cursor.nextMutationIndex += 1
        return Step(cursor: cursor, projection: projection)
    }

    static func finish(_ cursor: Cursor) throws -> Result {
        guard cursor.nextMutationIndex == cursor.source.orderedMutations.count,
              cursor.mutationProjections.count == cursor.source.orderedMutations.count,
              cursor.consumedExternalRequirements
                == Set(cursor.inventory.requirements.externalWorkPredecessors),
              Set(cursor.externalBindingByRequirement.keys)
                == Set(cursor.inventory.requirements.externalWorkPredecessors) else {
            throw PartsStockReplacementValueProjectionFailureV1.incompleteProjection
        }

        func targetPart(_ source: LocalPartDefinitionV1) throws -> LocalPartDefinitionV1 {
            guard let value = cursor.targetPartByKey[PartKey(source)] else {
                throw PartsStockReplacementValueProjectionFailureV1.missingDependency
            }
            return value
        }
        func targetLocation(_ source: StockStorageLocationV1) throws -> StockStorageLocationV1 {
            guard let value = cursor.targetLocationByKey[try LocationKey(source)] else {
                throw PartsStockReplacementValueProjectionFailureV1.missingDependency
            }
            return value
        }
        func targetMovement(_ source: StockMovementEventV1) throws -> StockMovementEventV1 {
            guard let value = cursor.targetMovementByKey[MovementKey(source)] else {
                throw PartsStockReplacementValueProjectionFailureV1.missingDependency
            }
            return value
        }
        func targetUse(_ source: StockUseOnWorkReceiptV1) throws -> StockUseOnWorkReceiptV1 {
            guard let value = cursor.targetUseByKey[ReceiptKey(source.receiptID, source.receiptSHA256)] else {
                throw PartsStockReplacementValueProjectionFailureV1.missingDependency
            }
            return value
        }
        func targetReversal(_ source: StockUseReversalReceiptV1) throws -> StockUseReversalReceiptV1 {
            guard let value = cursor.targetReversalByKey[ReceiptKey(source.receiptID, source.receiptSHA256)] else {
                throw PartsStockReplacementValueProjectionFailureV1.missingDependency
            }
            return value
        }
        func targetReturn(_ source: StockReturnAgainstUseReceiptV1) throws -> StockReturnAgainstUseReceiptV1 {
            guard let value = cursor.targetReturnByKey[ReceiptKey(source.receiptID, source.receiptSHA256)] else {
                throw PartsStockReplacementValueProjectionFailureV1.missingDependency
            }
            return value
        }
        func targetAbandonment(
            _ source: AbandonUnverifiedStockDispositionV1
        ) throws -> AbandonUnverifiedStockDispositionV1 {
            let key = try AbandonmentKey(source)
            guard let value = cursor.targetAbandonmentByKey[key] else {
                throw PartsStockReplacementValueProjectionFailureV1.missingDependency
            }
            return value
        }

        let targetSnapshot = try PartsStockBackupSnapshotV1(
            workspaceID: cursor.targetWorkspaceID,
            parts: try cursor.source.snapshot.parts.map(targetPart),
            locations: try cursor.source.snapshot.locations.map(targetLocation),
            movements: try cursor.source.snapshot.movements.map(targetMovement),
            uses: try cursor.source.snapshot.uses.map(targetUse),
            reversals: try cursor.source.snapshot.reversals.map(targetReversal),
            returns: try cursor.source.snapshot.returns.map(targetReturn),
            abandonments: try cursor.source.snapshot.abandonments.map(targetAbandonment)
        )
        try targetSnapshot.validate()

        let partProjections = try cursor.inventory.parts.values.sorted(by: partLessThan).map {
            PartProjection(source: $0, target: try targetPart($0))
        }
        let locationProjections = try cursor.inventory.locations.values.sorted(by: locationLessThan).map {
            LocationProjection(source: $0, target: try targetLocation($0))
        }
        let actorProjections = try cursor.inventory.actors.sorted(by: actorLessThan).map { source in
            guard let target = cursor.targetActorBySource[source] else {
                throw PartsStockReplacementValueProjectionFailureV1.missingDependency
            }
            return ActorProjection(source: source, target: target)
        }
        let workProjections = try cursor.inventory.ownedWorkEntries.sorted(by: workLessThan).map { source in
            guard let target = cursor.targetWorkByKey[WorkKey(source)] else {
                throw PartsStockReplacementValueProjectionFailureV1.missingDependency
            }
            return WorkResourceProjection(source: source, target: target)
        }
        return Result(
            sourceSnapshotSHA256: cursor.source.snapshot.snapshotSHA256,
            targetSnapshot: targetSnapshot,
            mutations: cursor.mutationProjections,
            parts: partProjections,
            locations: locationProjections,
            actors: actorProjections,
            workResources: workProjections
        )
    }

    static func project(_ source: Source, bindings: Bindings) throws -> Result {
        var cursor = try begin(source, bindings: bindings)
        while cursor.nextMutationIndex < source.orderedMutations.count {
            cursor = try projectNext(cursor).cursor
        }
        return try finish(cursor)
    }
}

fileprivate extension PartsStockReplacementValueProjectionV1 {
    struct PartKey: Hashable, Sendable {
        let partID: UUID
        let revision: UInt64
        let digest: String
        init(_ value: LocalPartDefinitionV1) {
            partID = value.partID; revision = value.revision; digest = value.partSHA256
        }
        init(_ value: LocalPartReferenceSnapshotV1) {
            partID = value.partID; revision = value.partRevision; digest = value.partSHA256
        }
    }

    struct LocationKey: Hashable, Sendable {
        let locationID: UUID
        let revision: UInt64
        let digest: String
        init(_ value: StockStorageLocationV1) throws {
            locationID = value.locationID; revision = value.revision
            digest = try PartsStockCanonicalCodecV1.sha256(value)
        }
    }

    struct MovementKey: Hashable, Sendable {
        let movementID: UUID
        let digest: String
        init(_ value: StockMovementEventV1) {
            movementID = value.movementID; digest = value.eventSHA256
        }
    }

    struct ReceiptKey: Hashable, Sendable {
        let receiptID: UUID
        let digest: String
        init(_ receiptID: UUID, _ digest: String) {
            self.receiptID = receiptID; self.digest = digest
        }
    }

    struct AbandonmentKey: Hashable, Sendable {
        let dispositionID: UUID
        let digest: String
        init(_ value: AbandonUnverifiedStockDispositionV1) throws {
            dispositionID = value.dispositionID
            digest = try PartsStockCanonicalCodecV1.sha256(value)
        }
    }

    struct WorkKey: Hashable, Sendable {
        let entryID: UUID
        let digest: String
        init(_ value: WorkResourceEntryV1) {
            entryID = value.entryID; digest = value.entrySHA256
        }
    }

    struct Inventory: Equatable, Sendable {
        let requirements: Requirements
        let parts: [String: LocalPartDefinitionV1]
        let locations: [String: StockStorageLocationV1]
        let actors: [ActorSnapshotV1]
        let workEntriesByID: [UUID: WorkResourceEntryV1]
        let ownedWorkEntries: [WorkResourceEntryV1]
        let workOwnerIndexByID: [UUID: Int]
    }

    static func insertUnique<Value: Hashable>(
        _ value: Value,
        into values: inout Set<Value>
    ) throws {
        guard values.insert(value).inserted else {
            throw PartsStockReplacementValueProjectionFailureV1.invalidSource
        }
    }

    static func makeInventory(_ source: Source) throws -> Inventory {
        try source.snapshot.validate()
        let workspaceID = source.snapshot.workspaceID
        var baselinePartByID: [UUID: LocalPartDefinitionV1] = [:]
        var baselineLocationByID: [UUID: StockStorageLocationV1] = [:]
        for baseline in source.originalCatalogBaselines {
            switch baseline {
            case let .part(entityRevision, value):
                try value.validate()
                guard let digest = entityRevision.externalProjectionSHA256,
                      MutationEnvelopeV1.isSHA256(digest),
                      value.workspaceID == workspaceID,
                      entityRevision.identity.kind == .localPartDefinition,
                      entityRevision.identity.id == value.partID,
                      entityRevision.revision == value.revision,
                      digest == value.partSHA256,
                      source.snapshot.parts.contains(value),
                      baselinePartByID.updateValue(value, forKey: value.partID) == nil else {
                    throw PartsStockReplacementValueProjectionFailureV1.invalidSource
                }
            case let .location(entityRevision, value):
                try value.validate()
                let digest = try PartsStockCanonicalCodecV1.sha256(value)
                guard let externalDigest = entityRevision.externalProjectionSHA256,
                      MutationEnvelopeV1.isSHA256(externalDigest),
                      value.workspaceID == workspaceID,
                      entityRevision.identity.kind == .stockStorageLocation,
                      entityRevision.identity.id == value.locationID,
                      entityRevision.revision == value.revision,
                      externalDigest == digest,
                      source.snapshot.locations.contains(value),
                      baselineLocationByID.updateValue(value, forKey: value.locationID) == nil else {
                    throw PartsStockReplacementValueProjectionFailureV1.invalidSource
                }
            }
        }
        var parts: [String: LocalPartDefinitionV1] = [:]
        var locations: [String: StockStorageLocationV1] = [:]
        var actors: [ActorSnapshotV1: ActorSnapshotV1] = [:]
        var workEntries: [UUID: WorkResourceEntryV1] = [:]
        var ownedWorkEntries: [UUID: WorkResourceEntryV1] = [:]
        var workOwnerIndexByID: [UUID: Int] = [:]
        var mutationIDs = Set<MutationIDV1>()
        var subjects = Set<WorkResourceSubjectV1>()
        var movementByID: [UUID: StockMovementEventV1] = [:]
        var useByID: [UUID: StockUseOnWorkReceiptV1] = [:]
        var reversalByID: [UUID: StockUseReversalReceiptV1] = [:]
        var returnByID: [UUID: StockReturnAgainstUseReceiptV1] = [:]
        var abandonmentByID: [UUID: AbandonUnverifiedStockDispositionV1] = [:]
        var subjectByIdentity: [String: WorkResourceSubjectV1] = [:]
        var observedMovements = Set<MovementKey>()
        var observedUses = Set<ReceiptKey>()
        var observedReversals = Set<ReceiptKey>()
        var observedReturns = Set<ReceiptKey>()
        var observedAbandonments = Set<AbandonmentKey>()
        var ownedParts = Set<PartKey>()
        var ownedLocations = Set<LocationKey>()
        var ownedMovements = Set<MovementKey>()
        var ownedUses = Set<ReceiptKey>()
        var ownedReversals = Set<ReceiptKey>()
        var ownedReturns = Set<ReceiptKey>()
        var ownedAbandonments = Set<AbandonmentKey>()

        func requireWorkspace(_ value: WorkspaceID) throws {
            guard value == workspaceID else {
                throw PartsStockReplacementValueProjectionFailureV1.invalidSource
            }
        }
        func addMutationID(_ value: MutationIDV1) { mutationIDs.insert(value) }
        func addPart(_ value: LocalPartDefinitionV1) throws {
            try value.validate(); try requireWorkspace(value.workspaceID); addMutationID(value.mutationID)
            let key = "\(value.partID.uuidString.lowercased())|\(value.revision)"
            if let prior = parts[key], prior != value {
                throw PartsStockReplacementValueProjectionFailureV1.invalidSource
            }
            parts[key] = value
        }
        func addLocation(_ value: StockStorageLocationV1) throws {
            try value.validate(); try requireWorkspace(value.workspaceID)
            let key = "\(value.locationID.uuidString.lowercased())|\(value.revision)"
            if let prior = locations[key], prior != value {
                throw PartsStockReplacementValueProjectionFailureV1.invalidSource
            }
            locations[key] = value
        }
        func addActor(_ value: ActorSnapshotV1) throws {
            try value.validate(); try requireWorkspace(value.workspaceID)
            if let prior = actors.keys.first(where: { $0.snapshotID == value.snapshotID }), prior != value {
                throw PartsStockReplacementValueProjectionFailureV1.invalidSource
            }
            actors[value] = value
        }
        func addWork(_ value: WorkResourceEntryV1) throws {
            try PartsStockDateValidationV1.requireWorkResource(value)
            try requireWorkspace(value.workspaceID); try addActor(value.actor)
            addMutationID(value.mutationID)
            let subjectKey = "\(value.subject.kind.rawValue)|\(value.subject.subjectID)|\(value.subject.subjectRevision)"
            if let prior = subjectByIdentity[subjectKey], prior != value.subject {
                throw PartsStockReplacementValueProjectionFailureV1.invalidSource
            }
            subjectByIdentity[subjectKey] = value.subject
            subjects.insert(value.subject)
            if let prior = workEntries[value.entryID], prior != value {
                throw PartsStockReplacementValueProjectionFailureV1.invalidSource
            }
            workEntries[value.entryID] = value
        }
        func addMovement(_ value: StockMovementEventV1) throws {
            try value.validate(); try requireWorkspace(value.workspaceID)
            addMutationID(value.mutationID); try addActor(value.actor)
            if let prior = movementByID[value.movementID], prior != value {
                throw PartsStockReplacementValueProjectionFailureV1.invalidSource
            }
            movementByID[value.movementID] = value
            observedMovements.insert(MovementKey(value))
        }
        func addUse(_ value: StockUseOnWorkReceiptV1) throws {
            try value.validate(); try requireWorkspace(value.workspaceID)
            addMutationID(value.mutationID); try addMovement(value.movement)
            try addWork(value.workResourceSuccessor)
            if let prior = useByID[value.receiptID], prior != value {
                throw PartsStockReplacementValueProjectionFailureV1.invalidSource
            }
            useByID[value.receiptID] = value
            observedUses.insert(ReceiptKey(value.receiptID, value.receiptSHA256))
        }
        func addReversal(_ value: StockUseReversalReceiptV1) throws {
            try value.validate(); try requireWorkspace(value.workspaceID)
            addMutationID(value.mutationID); try addUse(value.sourceUse)
            try addMovement(value.reversalMovement); try addWork(value.workResourceSuccessor)
            if let prior = reversalByID[value.receiptID], prior != value {
                throw PartsStockReplacementValueProjectionFailureV1.invalidSource
            }
            reversalByID[value.receiptID] = value
            observedReversals.insert(ReceiptKey(value.receiptID, value.receiptSHA256))
        }
        func addReturn(_ value: StockReturnAgainstUseReceiptV1) throws {
            try value.validate(); try requireWorkspace(value.workspaceID)
            addMutationID(value.mutationID); try addUse(value.sourceUse)
            try addMovement(value.returnMovement); try addWork(value.workResourcePredecessor)
            try addWork(value.workResourceSuccessor)
            if let prior = returnByID[value.receiptID], prior != value {
                throw PartsStockReplacementValueProjectionFailureV1.invalidSource
            }
            returnByID[value.receiptID] = value
            observedReturns.insert(ReceiptKey(value.receiptID, value.receiptSHA256))
        }
        func addAbandonment(_ value: AbandonUnverifiedStockDispositionV1) throws {
            try value.validate(); try requireWorkspace(value.workspaceID)
            addMutationID(value.mutationID); try addActor(value.actor)
            if let prior = abandonmentByID[value.dispositionID], prior != value {
                throw PartsStockReplacementValueProjectionFailureV1.invalidSource
            }
            abandonmentByID[value.dispositionID] = value
            observedAbandonments.insert(try AbandonmentKey(value))
        }
        func ownWork(_ value: WorkResourceEntryV1, at index: Int) throws {
            try addWork(value)
            if ownedWorkEntries.updateValue(value, forKey: value.entryID).map({ $0 != value }) == true
                || workOwnerIndexByID.updateValue(index, forKey: value.entryID) != nil {
                throw PartsStockReplacementValueProjectionFailureV1.invalidSource
            }
        }

        try source.snapshot.parts.forEach(addPart)
        try source.snapshot.locations.forEach(addLocation)
        try source.snapshot.movements.forEach(addMovement)
        try source.snapshot.uses.forEach(addUse)
        try source.snapshot.reversals.forEach(addReversal)
        try source.snapshot.returns.forEach(addReturn)
        try source.snapshot.abandonments.forEach(addAbandonment)

        var commandMutationIDs = Set<MutationIDV1>()
        for (index, mutation) in source.orderedMutations.enumerated() {
            try mutation.validate(); try requireWorkspace(mutation.workspaceID)
            guard commandMutationIDs.insert(mutation.mutationID).inserted else {
                throw PartsStockReplacementValueProjectionFailureV1.invalidSource
            }
            addMutationID(mutation.mutationID)
            switch mutation {
            case let .upsertPart(value):
                try addPart(value); try insertUnique(PartKey(value), into: &ownedParts)
            case let .upsertLocation(value, _):
                try addLocation(value); try insertUnique(try LocationKey(value), into: &ownedLocations)
            case let .appendMovement(value):
                try addMovement(value); try insertUnique(MovementKey(value), into: &ownedMovements)
            case let .transfer(value):
                try addMovement(value.outbound); try addMovement(value.inbound)
                try insertUnique(MovementKey(value.outbound), into: &ownedMovements)
                try insertUnique(MovementKey(value.inbound), into: &ownedMovements)
            case let .use(value):
                try addUse(value); try ownWork(value.workResourceSuccessor, at: index)
                try insertUnique(MovementKey(value.movement), into: &ownedMovements)
                try insertUnique(ReceiptKey(value.receiptID, value.receiptSHA256), into: &ownedUses)
            case let .reverseUse(value):
                try addReversal(value); try ownWork(value.workResourceSuccessor, at: index)
                try insertUnique(MovementKey(value.reversalMovement), into: &ownedMovements)
                try insertUnique(
                    ReceiptKey(value.receiptID, value.receiptSHA256), into: &ownedReversals
                )
            case let .returnAgainstUse(value):
                try addReturn(value); try ownWork(value.workResourceSuccessor, at: index)
                try insertUnique(MovementKey(value.returnMovement), into: &ownedMovements)
                try insertUnique(
                    ReceiptKey(value.receiptID, value.receiptSHA256), into: &ownedReturns
                )
            case let .retirePart(value):
                try addPart(value.predecessorPart); try addPart(value.archivedPartSuccessor)
                try value.verifiedBalances.forEach { try requireWorkspace($0.workspaceID) }
                try insertUnique(PartKey(value.archivedPartSuccessor), into: &ownedParts)
            case let .abandon(value):
                try addPart(value.predecessorPart); try addPart(value.archivedPartSuccessor)
                try value.dispositions.forEach(addAbandonment)
                try insertUnique(PartKey(value.archivedPartSuccessor), into: &ownedParts)
                try value.dispositions.forEach {
                    try insertUnique(try AbandonmentKey($0), into: &ownedAbandonments)
                }
            }
            guard try mutation.mutationPostImages.map({ try $0.identity }).count
                    == mutation.affectedIdentities.count else {
                throw PartsStockReplacementValueProjectionFailureV1.invalidSource
            }
        }

        guard ownedMovements == observedMovements,
              ownedUses == observedUses,
              ownedReversals == observedReversals,
              ownedReturns == observedReturns,
              ownedAbandonments == observedAbandonments else {
            throw PartsStockReplacementValueProjectionFailureV1.incompleteProjection
        }

        let partsByID = Dictionary(grouping: parts.values, by: \.partID)
        let locationsByID = Dictionary(grouping: locations.values, by: \.locationID)
        for (partID, revisions) in partsByID {
            let actual = revisions.map(\.revision).sorted()
            let owned = ownedParts.filter { $0.partID == partID }
            if let baseline = baselinePartByID[partID] {
                let expected = baseline.revision == 1
                    ? [UInt64(1)]
                    : Array(UInt64(2)...baseline.revision)
                guard actual == expected,
                      revisions.max(by: { $0.revision < $1.revision }) == baseline,
                      owned == Set(revisions.filter { $0.revision > 1 }.map(PartKey.init)) else {
                    throw PartsStockReplacementValueProjectionFailureV1.incompleteProjection
                }
            } else if actual != (1...revisions.count).map(UInt64.init)
                || owned != Set(revisions.map(PartKey.init)) {
                throw PartsStockReplacementValueProjectionFailureV1.incompleteProjection
            }
        }
        for (locationID, revisions) in locationsByID {
            let actual = revisions.map(\.revision).sorted()
            let owned = ownedLocations.filter { $0.locationID == locationID }
            if let baseline = baselineLocationByID[locationID] {
                let expected = baseline.revision == 1
                    ? [UInt64(1)]
                    : Array(UInt64(2)...baseline.revision)
                guard actual == expected,
                      revisions.max(by: { $0.revision < $1.revision }) == baseline,
                      owned == Set(try revisions.filter { $0.revision > 1 }.map(LocationKey.init)) else {
                    throw PartsStockReplacementValueProjectionFailureV1.incompleteProjection
                }
            } else if try actual != (1...revisions.count).map(UInt64.init)
                || owned != Set(try revisions.map(LocationKey.init)) {
                throw PartsStockReplacementValueProjectionFailureV1.incompleteProjection
            }
        }
        let terminalParts = partsByID.values.compactMap {
            $0.max { lhs, rhs in lhs.revision < rhs.revision }
        }
        let terminalLocations = locationsByID.values.compactMap {
            $0.max { lhs, rhs in lhs.revision < rhs.revision }
        }
        guard Set(source.snapshot.parts.map(PartKey.init)) == Set(terminalParts.map(PartKey.init)),
              Set(try source.snapshot.locations.map(LocationKey.init))
                == Set(try terminalLocations.map(LocationKey.init)),
              Set(source.snapshot.movements.map(MovementKey.init)) == observedMovements,
              Set(source.snapshot.uses.map { ReceiptKey($0.receiptID, $0.receiptSHA256) })
                == observedUses,
              Set(source.snapshot.reversals.map { ReceiptKey($0.receiptID, $0.receiptSHA256) })
                == observedReversals,
              Set(source.snapshot.returns.map { ReceiptKey($0.receiptID, $0.receiptSHA256) })
                == observedReturns,
              Set(try source.snapshot.abandonments.map(AbandonmentKey.init))
                == observedAbandonments else {
            throw PartsStockReplacementValueProjectionFailureV1.incompleteProjection
        }

        for value in workEntries.values {
            for line in value.materials {
                if let reference = line.localPartReference,
                   !parts.values.contains(where: {
                       $0.partID == reference.partID && $0.revision == reference.partRevision
                           && $0.partSHA256 == reference.partSHA256
                   }) {
                    throw PartsStockReplacementValueProjectionFailureV1.missingDependency
                }
            }
        }

        var external = Set<ExternalWorkPredecessorRequirement>()
        var externalByEntryID: [UUID: ExternalWorkPredecessorRequirement] = [:]
        for value in ownedWorkEntries.values {
            guard let predecessorID = value.supersedesEntryID,
                  let predecessorSHA256 = value.supersedesEntrySHA256 else { continue }
            if let predecessor = ownedWorkEntries[predecessorID] {
                guard predecessor.entrySHA256 == predecessorSHA256,
                      workOwnerIndexByID[predecessorID].map({ $0 < (workOwnerIndexByID[value.entryID] ?? 0) }) == true else {
                    throw PartsStockReplacementValueProjectionFailureV1.invalidOrder
                }
            } else {
                let requirement = ExternalWorkPredecessorRequirement(
                    entryID: predecessorID,
                    revision: value.expectedRevision,
                    sourceEntrySHA256: predecessorSHA256
                )
                if let prior = externalByEntryID[predecessorID], prior != requirement {
                    throw PartsStockReplacementValueProjectionFailureV1.invalidSource
                }
                externalByEntryID[predecessorID] = requirement
                external.insert(requirement)
            }
        }

        let requirements = Requirements(
            mutationIDs: mutationIDs.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString },
            workSubjects: subjects.sorted(by: subjectLessThan),
            externalWorkPredecessors: external.sorted(by: externalRequirementLessThan)
        )
        return Inventory(
            requirements: requirements,
            parts: parts,
            locations: locations,
            actors: actors.keys.sorted(by: actorLessThan),
            workEntriesByID: workEntries,
            ownedWorkEntries: ownedWorkEntries.values.sorted(by: workLessThan),
            workOwnerIndexByID: workOwnerIndexByID
        )
    }

    static func mutationBindings(
        _ bindings: [MutationIDBinding],
        requirements: [MutationIDV1]
    ) throws -> [UUID: MutationIDV1] {
        let required = Set(requirements)
        guard bindings.count == requirements.count,
              Set(bindings.map(\.source)) == required,
              Set(bindings.map(\.target)).count == bindings.count,
              bindings.allSatisfy({ $0.source != $0.target }) else {
            throw PartsStockReplacementValueProjectionFailureV1.invalidBinding
        }
        var result: [UUID: MutationIDV1] = [:]
        for binding in bindings {
            guard result.updateValue(binding.target, forKey: binding.source.rawValue) == nil else {
                throw PartsStockReplacementValueProjectionFailureV1.invalidBinding
            }
        }
        return result
    }

    static func subjectBindings(
        _ bindings: [WorkSubjectBinding],
        requirements: [WorkResourceSubjectV1],
        targetWorkspaceID: WorkspaceID
    ) throws -> [WorkResourceSubjectV1: WorkResourceSubjectV1] {
        guard bindings.count == requirements.count,
              Set(bindings.map(\.source)) == Set(requirements),
              Set(bindings.map { $0.target.subjectSHA256 }).count == bindings.count else {
            throw PartsStockReplacementValueProjectionFailureV1.invalidBinding
        }
        var result: [WorkResourceSubjectV1: WorkResourceSubjectV1] = [:]
        for binding in bindings {
            try binding.source.validate(); try binding.target.validate()
            guard binding.target.workspaceID == targetWorkspaceID,
                  binding.target.kind == binding.source.kind,
                  binding.target.subjectID == binding.source.subjectID,
                  binding.target.subjectRevision == binding.source.subjectRevision,
                  binding.target.subjectSHA256 != binding.source.subjectSHA256,
                  result.updateValue(binding.target, forKey: binding.source) == nil else {
                throw PartsStockReplacementValueProjectionFailureV1.invalidBinding
            }
        }
        return result
    }

    static func externalBindings(
        _ bindings: [ExternalWorkPredecessorBinding],
        requirements: [ExternalWorkPredecessorRequirement]
    ) throws -> [ExternalWorkPredecessorRequirement: ExternalWorkPredecessorBinding] {
        let required = Set(requirements)
        guard Set(bindings.map(\.targetEntrySHA256)).count == bindings.count else {
            throw PartsStockReplacementValueProjectionFailureV1.invalidBinding
        }
        var result: [ExternalWorkPredecessorRequirement: ExternalWorkPredecessorBinding] = [:]
        for binding in bindings {
            guard required.contains(binding.requirement),
                  PartsStockCanonicalCodecV1.isDigest(binding.targetEntrySHA256),
                  binding.targetEntrySHA256 != binding.requirement.sourceEntrySHA256,
                  result.updateValue(binding, forKey: binding.requirement) == nil else {
                throw PartsStockReplacementValueProjectionFailureV1.invalidBinding
            }
        }
        return result
    }

    static func addExternalBindings(
        _ bindings: [ExternalWorkPredecessorBinding],
        to cursor: inout Cursor
    ) throws -> Set<ExternalWorkPredecessorRequirement> {
        let required = Set(cursor.inventory.requirements.externalWorkPredecessors)
        var supplied = Set<ExternalWorkPredecessorRequirement>()
        for binding in bindings {
            guard required.contains(binding.requirement),
                  PartsStockCanonicalCodecV1.isDigest(binding.targetEntrySHA256),
                  binding.targetEntrySHA256 != binding.requirement.sourceEntrySHA256,
                  !cursor.externalBindingByRequirement.values.contains(where: {
                      $0.targetEntrySHA256 == binding.targetEntrySHA256
                  }),
                  !cursor.consumedExternalRequirements.contains(binding.requirement),
                  cursor.externalBindingByRequirement[binding.requirement] == nil,
                  supplied.insert(binding.requirement).inserted else {
                throw PartsStockReplacementValueProjectionFailureV1.invalidBinding
            }
            cursor.externalBindingByRequirement[binding.requirement] = binding
        }
        return supplied
    }

    static func projectMutation(
        _ source: PartsStockMutationV1,
        index: Int,
        cursor: inout Cursor
    ) throws -> PartsStockMutationV1 {
        guard let targetMutationID = cursor.targetMutationIDBySourceID[source.mutationID.rawValue] else {
            throw PartsStockReplacementValueProjectionFailureV1.missingDependency
        }
        switch source {
        case let .upsertPart(value): return .upsertPart(try targetPart(value, cursor: cursor))
        case let .upsertLocation(value, _):
            return .upsertLocation(try targetLocation(value, cursor: cursor), mutationID: targetMutationID)
        case let .appendMovement(value):
            return .appendMovement(try projectMovement(value, cursor: &cursor))
        case let .transfer(value):
            let target = StockTransferReceiptV1(
                workspaceID: cursor.targetWorkspaceID,
                outbound: try projectMovement(value.outbound, cursor: &cursor),
                inbound: try projectMovement(value.inbound, cursor: &cursor),
                mutationID: targetMutationID
            )
            try target.validate(); return .transfer(target)
        case let .use(value): return .use(try projectUse(value, index: index, cursor: &cursor))
        case let .reverseUse(value):
            let sourceUse = try existingTargetUse(value.sourceUse, cursor: cursor)
            let successor = try projectWork(value.workResourceSuccessor, index: index, cursor: &cursor)
            let target = try StockUseReversalReceiptV1(
                receiptID: value.receiptID,
                sourceUse: sourceUse,
                reversalMovement: try projectMovement(value.reversalMovement, cursor: &cursor),
                workResourceSuccessor: successor,
                reason: value.reason,
                mutationID: targetMutationID
            )
            cursor.targetReversalByKey[ReceiptKey(value.receiptID, value.receiptSHA256)] = target
            return .reverseUse(target)
        case let .returnAgainstUse(value):
            let sourceUse = try existingTargetUse(value.sourceUse, cursor: cursor)
            let predecessor = try existingTargetWork(value.workResourcePredecessor, cursor: cursor)
            let successor = try projectWork(value.workResourceSuccessor, index: index, cursor: &cursor)
            let frontier: StockReturnFrontierSnapshotV1?
            if let sourceFrontier = value.predecessorFrontier {
                guard let predecessorReturn = cursor.targetReturnByKey[
                    ReceiptKey(sourceFrontier.returnReceiptID, sourceFrontier.returnReceiptSHA256)
                ] else {
                    throw PartsStockReplacementValueProjectionFailureV1.invalidOrder
                }
                frontier = try predecessorReturn.frontierSnapshot()
            } else {
                frontier = nil
            }
            let target = try StockReturnAgainstUseReceiptV1(
                receiptID: value.receiptID,
                sourceUse: sourceUse,
                predecessorFrontier: frontier,
                returnMovement: try projectMovement(value.returnMovement, cursor: &cursor),
                workResourcePredecessor: predecessor,
                workResourceSuccessor: successor,
                mutationID: targetMutationID
            )
            cursor.targetReturnByKey[ReceiptKey(value.receiptID, value.receiptSHA256)] = target
            return .returnAgainstUse(target)
        case let .retirePart(value):
            let balances = try value.verifiedBalances.map {
                let target = StockBalanceProjectionV1(
                    workspaceID: cursor.targetWorkspaceID,
                    partID: $0.partID,
                    locationID: $0.locationID,
                    unit: $0.unit,
                    balance: $0.balance,
                    locationRevision: $0.locationRevision,
                    lastMovementID: $0.lastMovementID
                )
                try target.validate(); return target
            }
            return .retirePart(try StockPartRetirementReceiptV1(
                archivedPartSuccessor: targetPart(value.archivedPartSuccessor, cursor: cursor),
                predecessor: targetPart(value.predecessorPart, cursor: cursor),
                verifiedBalances: balances
            ))
        case let .abandon(value):
            let dispositions = try value.dispositions.map {
                try projectAbandonment($0, cursor: &cursor)
            }
            return .abandon(try StockAbandonmentReceiptV1(
                dispositions: dispositions,
                archivedPartSuccessor: targetPart(value.archivedPartSuccessor, cursor: cursor),
                predecessor: targetPart(value.predecessorPart, cursor: cursor)
            ))
        }
    }

    static func targetPart(
        _ source: LocalPartDefinitionV1,
        cursor: Cursor
    ) throws -> LocalPartDefinitionV1 {
        guard let target = cursor.targetPartByKey[PartKey(source)] else {
            throw PartsStockReplacementValueProjectionFailureV1.missingDependency
        }
        return target
    }

    static func targetLocation(
        _ source: StockStorageLocationV1,
        cursor: Cursor
    ) throws -> StockStorageLocationV1 {
        guard let target = cursor.targetLocationByKey[try LocationKey(source)] else {
            throw PartsStockReplacementValueProjectionFailureV1.missingDependency
        }
        return target
    }

    static func targetPartReference(
        _ source: LocalPartReferenceSnapshotV1,
        cursor: Cursor
    ) throws -> LocalPartReferenceSnapshotV1 {
        guard let part = cursor.targetPartByKey[PartKey(source)] else {
            throw PartsStockReplacementValueProjectionFailureV1.missingDependency
        }
        return try part.frozenReference()
    }

    static func targetActor(_ source: ActorSnapshotV1, cursor: Cursor) throws -> ActorSnapshotV1 {
        guard let target = cursor.targetActorBySource[source] else {
            throw PartsStockReplacementValueProjectionFailureV1.missingDependency
        }
        return target
    }

    static func projectMovement(
        _ source: StockMovementEventV1,
        cursor: inout Cursor
    ) throws -> StockMovementEventV1 {
        let key = MovementKey(source)
        if let target = cursor.targetMovementByKey[key] { return target }
        guard let mutationID = cursor.targetMutationIDBySourceID[source.mutationID.rawValue] else {
            throw PartsStockReplacementValueProjectionFailureV1.missingDependency
        }
        let target = try StockMovementEventV1(
            movementID: source.movementID,
            workspaceID: cursor.targetWorkspaceID,
            part: targetPartReference(source.part, cursor: cursor),
            locationID: source.locationID,
            kind: source.kind,
            quantity: source.quantity,
            unit: source.unit,
            preBalance: source.preBalance,
            postBalance: source.postBalance,
            relatedMovementID: source.relatedMovementID,
            reason: source.reason,
            actor: targetActor(source.actor, cursor: cursor),
            occurredAt: source.occurredAt,
            recordedAt: source.recordedAt,
            expectedLocationRevision: source.expectedLocationRevision,
            mutationID: mutationID
        )
        cursor.targetMovementByKey[key] = target
        return target
    }

    static func projectUse(
        _ source: StockUseOnWorkReceiptV1,
        index: Int,
        cursor: inout Cursor
    ) throws -> StockUseOnWorkReceiptV1 {
        let key = ReceiptKey(source.receiptID, source.receiptSHA256)
        if let target = cursor.targetUseByKey[key] { return target }
        guard cursor.inventory.workOwnerIndexByID[source.workResourceSuccessor.entryID] == index,
              let mutationID = cursor.targetMutationIDBySourceID[source.mutationID.rawValue] else {
            throw PartsStockReplacementValueProjectionFailureV1.invalidOrder
        }
        let target = try StockUseOnWorkReceiptV1(
            receiptID: source.receiptID,
            movement: projectMovement(source.movement, cursor: &cursor),
            workResourceSuccessor: projectWork(
                source.workResourceSuccessor, index: index, cursor: &cursor
            ),
            frozenMaterialLineID: source.frozenMaterialLineID,
            mutationID: mutationID
        )
        cursor.targetUseByKey[key] = target
        return target
    }

    static func existingTargetUse(
        _ source: StockUseOnWorkReceiptV1,
        cursor: Cursor
    ) throws -> StockUseOnWorkReceiptV1 {
        guard let target = cursor.targetUseByKey[ReceiptKey(source.receiptID, source.receiptSHA256)] else {
            throw PartsStockReplacementValueProjectionFailureV1.invalidOrder
        }
        return target
    }

    static func existingTargetWork(
        _ source: WorkResourceEntryV1,
        cursor: Cursor
    ) throws -> WorkResourceEntryV1 {
        guard let target = cursor.targetWorkByKey[WorkKey(source)] else {
            throw PartsStockReplacementValueProjectionFailureV1.invalidOrder
        }
        return target
    }

    static func projectWork(
        _ source: WorkResourceEntryV1,
        index: Int,
        cursor: inout Cursor
    ) throws -> WorkResourceEntryV1 {
        let key = WorkKey(source)
        if let target = cursor.targetWorkByKey[key] { return target }
        guard cursor.inventory.workOwnerIndexByID[source.entryID] == index,
              let subject = cursor.targetSubjectBySource[source.subject],
              let mutationID = cursor.targetMutationIDBySourceID[source.mutationID.rawValue] else {
            throw PartsStockReplacementValueProjectionFailureV1.invalidOrder
        }

        let predecessorDigest: String?
        if let predecessorID = source.supersedesEntryID,
           let sourcePredecessorDigest = source.supersedesEntrySHA256 {
            if let ownerIndex = cursor.inventory.workOwnerIndexByID[predecessorID] {
                guard ownerIndex < index,
                      let sourcePredecessor = cursor.inventory.workEntriesByID[predecessorID],
                      sourcePredecessor.entrySHA256 == sourcePredecessorDigest,
                      let targetPredecessor = cursor.targetWorkByKey[WorkKey(sourcePredecessor)] else {
                    throw PartsStockReplacementValueProjectionFailureV1.invalidOrder
                }
                predecessorDigest = targetPredecessor.entrySHA256
            } else {
                let requirement = ExternalWorkPredecessorRequirement(
                    entryID: predecessorID,
                    revision: source.expectedRevision,
                    sourceEntrySHA256: sourcePredecessorDigest
                )
                guard let binding = cursor.externalBindingByRequirement[requirement] else {
                    throw PartsStockReplacementValueProjectionFailureV1.missingDependency
                }
                cursor.consumedExternalRequirements.insert(requirement)
                predecessorDigest = binding.targetEntrySHA256
            }
        } else {
            predecessorDigest = nil
        }

        let materials = try source.materials.map { line in
            try ManualMaterialLineV1(
                lineID: line.lineID,
                description: line.description,
                quantity: line.quantity,
                unit: line.unit,
                localPartReference: try line.localPartReference.map {
                    try targetPartReference($0, cursor: cursor)
                }
            )
        }
        let target = try WorkResourceEntryV1(
            entryID: source.entryID,
            workspaceID: cursor.targetWorkspaceID,
            subject: subject,
            actor: targetActor(source.actor, cursor: cursor),
            duration: source.duration,
            materials: materials,
            directCost: source.directCost,
            visibility: source.visibility,
            disposition: source.disposition,
            voidReason: source.voidReason,
            recordedAt: source.recordedAt,
            expectedRevision: source.expectedRevision,
            revision: source.revision,
            supersedesEntryID: source.supersedesEntryID,
            supersedesEntrySHA256: predecessorDigest,
            mutationID: mutationID
        )
        cursor.targetWorkByKey[key] = target
        return target
    }

    static func projectAbandonment(
        _ source: AbandonUnverifiedStockDispositionV1,
        cursor: inout Cursor
    ) throws -> AbandonUnverifiedStockDispositionV1 {
        let key = try AbandonmentKey(source)
        if let target = cursor.targetAbandonmentByKey[key] { return target }
        guard let mutationID = cursor.targetMutationIDBySourceID[source.mutationID.rawValue] else {
            throw PartsStockReplacementValueProjectionFailureV1.missingDependency
        }
        let target = try AbandonUnverifiedStockDispositionV1(
            dispositionID: source.dispositionID,
            workspaceID: cursor.targetWorkspaceID,
            partID: source.partID,
            locationID: source.locationID,
            actor: targetActor(source.actor, cursor: cursor),
            reason: source.reason,
            lastMovementID: source.lastMovementID,
            lastLocationRevision: source.lastLocationRevision,
            recordedAt: source.recordedAt,
            mutationID: mutationID,
            currentBalance: .unknown
        )
        cursor.targetAbandonmentByKey[key] = target
        return target
    }

    static func actorLessThan(_ lhs: ActorSnapshotV1, _ rhs: ActorSnapshotV1) -> Bool {
        (lhs.snapshotID.uuidString, lhs.snapshotSHA256) < (rhs.snapshotID.uuidString, rhs.snapshotSHA256)
    }
    static func partLessThan(_ lhs: LocalPartDefinitionV1, _ rhs: LocalPartDefinitionV1) -> Bool {
        (lhs.partID.uuidString, lhs.revision, lhs.partSHA256)
            < (rhs.partID.uuidString, rhs.revision, rhs.partSHA256)
    }
    static func locationLessThan(
        _ lhs: StockStorageLocationV1,
        _ rhs: StockStorageLocationV1
    ) -> Bool {
        (lhs.locationID.uuidString, lhs.revision) < (rhs.locationID.uuidString, rhs.revision)
    }
    static func workLessThan(_ lhs: WorkResourceEntryV1, _ rhs: WorkResourceEntryV1) -> Bool {
        (lhs.revision, lhs.entryID.uuidString, lhs.entrySHA256)
            < (rhs.revision, rhs.entryID.uuidString, rhs.entrySHA256)
    }
    static func subjectLessThan(
        _ lhs: WorkResourceSubjectV1,
        _ rhs: WorkResourceSubjectV1
    ) -> Bool {
        (lhs.kind.rawValue, lhs.subjectID, lhs.subjectRevision, lhs.subjectSHA256)
            < (rhs.kind.rawValue, rhs.subjectID, rhs.subjectRevision, rhs.subjectSHA256)
    }
    static func externalRequirementLessThan(
        _ lhs: ExternalWorkPredecessorRequirement,
        _ rhs: ExternalWorkPredecessorRequirement
    ) -> Bool {
        (lhs.entryID.uuidString, lhs.revision, lhs.sourceEntrySHA256)
            < (rhs.entryID.uuidString, rhs.revision, rhs.sourceEntrySHA256)
    }
}

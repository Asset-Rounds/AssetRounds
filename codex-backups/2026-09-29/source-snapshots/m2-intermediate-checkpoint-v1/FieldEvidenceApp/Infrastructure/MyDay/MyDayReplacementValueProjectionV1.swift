import Foundation

enum MyDayReplacementValueProjectionFailureV1: Error, Equatable, Sendable {
    case invalidSource
    case invalidBinding
    case sameWorkspaceBindings
    case incompleteProjection
}

/// Pure C57 value reconstruction for replacement into an incumbent workspace.
///
/// The caller supplies exact correspondences proven by the root restore. This
/// type owns no record discovery, journal, generation, replica, store, writer,
/// clock, identifier generation, or restore-disposition behavior.
enum MyDayReplacementValueProjectionV1 {
    struct Source: Equatable, Sendable {
        let snapshot: MyDayBackupSnapshotV1
    }

    struct Requirements: Equatable, Sendable {
        let eligibleReferences: [MyDayEligibleReferenceV1]
        let mutationIDs: [MutationIDV1]
    }

    struct EligibleReferenceBinding: Equatable, Sendable {
        let source: MyDayEligibleReferenceV1
        let target: MyDayEligibleReferenceV1
    }

    struct MutationIDBinding: Equatable, Sendable {
        let source: MutationIDV1
        let target: MutationIDV1
    }

    struct Bindings: Equatable, Sendable {
        let targetWorkspaceID: WorkspaceID
        let eligibleReferences: [EligibleReferenceBinding]
        let mutationIDs: [MutationIDBinding]

        init(
            targetWorkspaceID: WorkspaceID,
            eligibleReferences: [EligibleReferenceBinding] = [],
            mutationIDs: [MutationIDBinding] = []
        ) {
            self.targetWorkspaceID = targetWorkspaceID
            self.eligibleReferences = eligibleReferences
            self.mutationIDs = mutationIDs
        }
    }

    struct PlanProjection: Equatable, Sendable {
        let source: MyDayPlanV1
        let target: MyDayPlanV1
    }

    struct CarryoverProjection: Equatable, Sendable {
        let sourceCommandPlan: MyDayCarryoverPlanV1
        let targetCommandPlan: MyDayCarryoverPlanV1
        let source: MyDayCarryoverReceiptV1
        let target: MyDayCarryoverReceiptV1
    }

    struct Result: Equatable, Sendable {
        let sourceSnapshotSHA256: String
        let targetSnapshot: MyDayBackupSnapshotV1
        let plans: [PlanProjection]
        let carryovers: [CarryoverProjection]
    }

    static func requirements(for source: Source) throws -> Requirements {
        try inventory(for: source).requirements
    }

    static func project(_ source: Source, bindings: Bindings) throws -> Result {
        let inventory = try inventory(for: source)
        do {
            try MyDayLimitsV1.workspace(bindings.targetWorkspaceID)
        } catch {
            throw MyDayReplacementValueProjectionFailureV1.invalidBinding
        }

        if bindings.targetWorkspaceID == source.snapshot.workspaceID {
            guard bindings.eligibleReferences.isEmpty, bindings.mutationIDs.isEmpty else {
                throw MyDayReplacementValueProjectionFailureV1.sameWorkspaceBindings
            }
            return Result(
                sourceSnapshotSHA256: source.snapshot.snapshotSHA256,
                targetSnapshot: source.snapshot,
                plans: source.snapshot.plans.map { PlanProjection(source: $0, target: $0) },
                carryovers: inventory.carryovers.map {
                    CarryoverProjection(
                        sourceCommandPlan: $0.commandPlan,
                        targetCommandPlan: $0.commandPlan,
                        source: $0.receipt,
                        target: $0.receipt
                    )
                }
            )
        }

        let referenceMap = try validatedReferenceBindings(
            bindings.eligibleReferences,
            requirements: inventory.requirements.eligibleReferences,
            sourceWorkspaceID: source.snapshot.workspaceID,
            targetWorkspaceID: bindings.targetWorkspaceID
        )
        let mutationMap = try validatedMutationBindings(
            bindings.mutationIDs,
            requirements: inventory.requirements.mutationIDs
        )

        do {
            var targetPredecessorByPlanID: [UUID: MyDayPlanV1] = [:]
            var targetBySourceReference: [MyDayPlanReferenceV1: MyDayPlanV1] = [:]
            var planProjections: [PlanProjection] = []
            for sourcePlan in source.snapshot.plans {
                let sourceReference = try MyDayPlanReferenceV1(sourcePlan)
                let targetItems = try sourcePlan.items.map { sourceItem in
                    guard let targetReference = referenceMap[sourceItem.reference] else {
                        throw MyDayReplacementValueProjectionFailureV1.incompleteProjection
                    }
                    return try MyDayItemV1(
                        membershipID: sourceItem.membershipID,
                        reference: targetReference,
                        manualOrder: sourceItem.manualOrder,
                        estimate: sourceItem.estimate
                    )
                }
                guard let targetMutationID = mutationMap[sourcePlan.mutationID] else {
                    throw MyDayReplacementValueProjectionFailureV1.incompleteProjection
                }
                let targetPlan = try MyDayPlanV1(
                    planID: sourcePlan.planID,
                    key: sourcePlan.key.rebound(to: bindings.targetWorkspaceID),
                    items: targetItems,
                    predecessor: targetPredecessorByPlanID[sourcePlan.planID],
                    revision: sourcePlan.revision,
                    mutationID: targetMutationID,
                    authoredBy: reboundActor(
                        sourcePlan.authoredBy,
                        sourceWorkspaceID: source.snapshot.workspaceID,
                        targetWorkspaceID: bindings.targetWorkspaceID
                    ),
                    authoredAt: sourcePlan.authoredAt
                )
                guard targetBySourceReference.updateValue(
                    targetPlan,
                    forKey: sourceReference
                ) == nil else {
                    throw MyDayReplacementValueProjectionFailureV1.incompleteProjection
                }
                targetPredecessorByPlanID[sourcePlan.planID] = targetPlan
                planProjections.append(.init(source: sourcePlan, target: targetPlan))
            }

            var carryoverProjections: [CarryoverProjection] = []
            for sourceCarryover in inventory.carryovers {
                guard let targetSource = targetBySourceReference[
                    sourceCarryover.receipt.sourcePlan
                ], let targetTarget = targetBySourceReference[
                    sourceCarryover.receipt.targetPlan
                ] else {
                    throw MyDayReplacementValueProjectionFailureV1.incompleteProjection
                }
                let targetExpected: MyDayPlanV1?
                if let sourceExpected = sourceCarryover.commandPlan.expectedTargetPlan {
                    guard let value = targetBySourceReference[sourceExpected] else {
                        throw MyDayReplacementValueProjectionFailureV1.incompleteProjection
                    }
                    targetExpected = value
                } else {
                    targetExpected = nil
                }
                let targetCommandPlan = try MyDayCarryoverPlanV1(
                    sourcePlan: targetSource,
                    targetKey: targetTarget.key,
                    membershipIDs: sourceCarryover.receipt.carriedMembershipIDs,
                    expectedTargetPlan: targetExpected
                )
                let targetReceipt = try MyDayCarryoverReceiptV1(
                    plan: targetCommandPlan,
                    source: targetSource,
                    target: targetTarget,
                    mutationID: targetTarget.mutationID,
                    committedAt: sourceCarryover.receipt.committedAt
                )
                carryoverProjections.append(.init(
                    sourceCommandPlan: sourceCarryover.commandPlan,
                    targetCommandPlan: targetCommandPlan,
                    source: sourceCarryover.receipt,
                    target: targetReceipt
                ))
            }

            let targetPlans = planProjections.map(\.target)
            let targetNonactive = try C57MyDayBackupEnrollmentV1
                .exactNonactiveReferences(for: targetPlans)
            let targetSnapshot = try MyDayBackupSnapshotV1(
                workspaceID: bindings.targetWorkspaceID,
                plans: targetPlans,
                carryoverReceipts: carryoverProjections.map(\.target),
                nonactivePlanReferences: targetNonactive
            )
            try targetSnapshot.validate()
            guard targetSnapshot.plans.count == source.snapshot.plans.count,
                  targetSnapshot.carryoverReceipts.count
                    == source.snapshot.carryoverReceipts.count,
                  targetSnapshot.nonactivePlanReferences == targetNonactive,
                  targetBySourceReference.count == source.snapshot.plans.count else {
                throw MyDayReplacementValueProjectionFailureV1.incompleteProjection
            }
            return Result(
                sourceSnapshotSHA256: source.snapshot.snapshotSHA256,
                targetSnapshot: targetSnapshot,
                plans: planProjections,
                carryovers: carryoverProjections
            )
        } catch let failure as MyDayReplacementValueProjectionFailureV1 {
            throw failure
        } catch {
            throw MyDayReplacementValueProjectionFailureV1.incompleteProjection
        }
    }
}

fileprivate extension MyDayReplacementValueProjectionV1 {
    struct SourceCarryover: Equatable, Sendable {
        let commandPlan: MyDayCarryoverPlanV1
        let receipt: MyDayCarryoverReceiptV1
    }

    struct Inventory: Equatable, Sendable {
        let requirements: Requirements
        let carryovers: [SourceCarryover]
    }

    static func inventory(for source: Source) throws -> Inventory {
        do {
            try source.snapshot.validate()
            let exactNonactive = try C57MyDayBackupEnrollmentV1
                .exactNonactiveReferences(for: source.snapshot.plans)
            guard source.snapshot.nonactivePlanReferences == exactNonactive,
                  Set(source.snapshot.plans.map(\.mutationID)).count
                    == source.snapshot.plans.count,
                  Set(source.snapshot.carryoverReceipts.map(\.mutationID)).count
                    == source.snapshot.carryoverReceipts.count else {
                throw MyDayReplacementValueProjectionFailureV1.invalidSource
            }

            var plansByReference: [MyDayPlanReferenceV1: MyDayPlanV1] = [:]
            var eligibleReferencesByRevisionKey: [String: MyDayEligibleReferenceV1] = [:]
            for plan in source.snapshot.plans {
                let reference = try MyDayPlanReferenceV1(plan)
                guard plansByReference.updateValue(plan, forKey: reference) == nil else {
                    throw MyDayReplacementValueProjectionFailureV1.invalidSource
                }
                for eligibleReference in plan.items.map(\.reference) {
                    let key = referenceRevisionKey(eligibleReference)
                    if let prior = eligibleReferencesByRevisionKey[key],
                       prior != eligibleReference {
                        throw MyDayReplacementValueProjectionFailureV1.invalidSource
                    }
                    eligibleReferencesByRevisionKey[key] = eligibleReference
                }
            }

            var carryovers: [SourceCarryover] = []
            for receipt in source.snapshot.carryoverReceipts {
                guard let sourcePlan = plansByReference[receipt.sourcePlan],
                      let targetPlan = plansByReference[receipt.targetPlan] else {
                    throw MyDayReplacementValueProjectionFailureV1.invalidSource
                }
                let expectedTarget: MyDayPlanV1?
                if targetPlan.revision == 1 {
                    expectedTarget = nil
                } else {
                    let matches = source.snapshot.plans.filter {
                        $0.planID == targetPlan.planID
                            && $0.revision == targetPlan.revision - 1
                            && $0.planSHA256 == targetPlan.predecessorPlanSHA256
                    }
                    guard matches.count == 1 else {
                        throw MyDayReplacementValueProjectionFailureV1.invalidSource
                    }
                    expectedTarget = matches[0]
                }
                let commandPlan = try MyDayCarryoverPlanV1(
                    sourcePlan: sourcePlan,
                    targetKey: targetPlan.key,
                    membershipIDs: receipt.carriedMembershipIDs,
                    expectedTargetPlan: expectedTarget
                )
                guard commandPlan.planSHA256 == receipt.carryoverPlanSHA256 else {
                    throw MyDayReplacementValueProjectionFailureV1.invalidSource
                }
                try receipt.validate(
                    plan: commandPlan,
                    source: sourcePlan,
                    target: targetPlan
                )
                carryovers.append(.init(commandPlan: commandPlan, receipt: receipt))
            }

            return Inventory(
                requirements: Requirements(
                    eligibleReferences: try orderedReferences(
                        Array(eligibleReferencesByRevisionKey.values)
                    ),
                    mutationIDs: Set(source.snapshot.plans.map(\.mutationID)).sorted {
                        $0.rawValue.uuidString < $1.rawValue.uuidString
                    }
                ),
                carryovers: carryovers
            )
        } catch let failure as MyDayReplacementValueProjectionFailureV1 {
            throw failure
        } catch {
            throw MyDayReplacementValueProjectionFailureV1.invalidSource
        }
    }

    static func orderedReferences(
        _ values: [MyDayEligibleReferenceV1]
    ) throws -> [MyDayEligibleReferenceV1] {
        let keyed = try values.map { value in
            (value: value, canonicalSHA256: try MyDayCanonicalCodecV1.sha256(value))
        }
        return keyed.sorted { lhs, rhs in
            if lhs.value.stableKey != rhs.value.stableKey {
                return lhs.value.stableKey < rhs.value.stableKey
            }
            if lhs.value.sourceRevision != rhs.value.sourceRevision {
                return lhs.value.sourceRevision < rhs.value.sourceRevision
            }
            if lhs.value.sourceSHA256 != rhs.value.sourceSHA256 {
                return lhs.value.sourceSHA256 < rhs.value.sourceSHA256
            }
            return lhs.canonicalSHA256 < rhs.canonicalSHA256
        }.map(\.value)
    }

    static func validatedReferenceBindings(
        _ bindings: [EligibleReferenceBinding],
        requirements: [MyDayEligibleReferenceV1],
        sourceWorkspaceID: WorkspaceID,
        targetWorkspaceID: WorkspaceID
    ) throws -> [MyDayEligibleReferenceV1: MyDayEligibleReferenceV1] {
        do {
            let required = Set(requirements)
            guard bindings.count == requirements.count else {
                throw MyDayReplacementValueProjectionFailureV1.invalidBinding
            }
            var result: [MyDayEligibleReferenceV1: MyDayEligibleReferenceV1] = [:]
            var targetValues = Set<MyDayEligibleReferenceV1>()
            var targetRevisionKeys = Set<String>()
            for binding in bindings {
                try binding.source.validate()
                try binding.target.validate()
                guard required.contains(binding.source),
                      binding.source.workspaceID == sourceWorkspaceID,
                      binding.target.workspaceID == targetWorkspaceID,
                      binding.source.stableKey == binding.target.stableKey,
                      binding.source.sourceRevision == binding.target.sourceRevision,
                      binding.source.sourceSHA256 != binding.target.sourceSHA256,
                      exactIdentityCorresponds(
                        source: binding.source,
                        target: binding.target
                      ),
                      result.updateValue(binding.target, forKey: binding.source) == nil,
                      targetValues.insert(binding.target).inserted,
                      targetRevisionKeys.insert(
                        referenceRevisionKey(binding.target)
                      ).inserted else {
                    throw MyDayReplacementValueProjectionFailureV1.invalidBinding
                }
            }
            guard result.count == required.count, Set(result.keys) == required else {
                throw MyDayReplacementValueProjectionFailureV1.invalidBinding
            }
            return result
        } catch let failure as MyDayReplacementValueProjectionFailureV1 {
            throw failure
        } catch {
            throw MyDayReplacementValueProjectionFailureV1.invalidBinding
        }
    }

    static func validatedMutationBindings(
        _ bindings: [MutationIDBinding],
        requirements: [MutationIDV1]
    ) throws -> [MutationIDV1: MutationIDV1] {
        let required = Set(requirements)
        guard bindings.count == requirements.count else {
            throw MyDayReplacementValueProjectionFailureV1.invalidBinding
        }
        var result: [MutationIDV1: MutationIDV1] = [:]
        var targets = Set<MutationIDV1>()
        for binding in bindings {
            guard required.contains(binding.source),
                  !required.contains(binding.target),
                  result.updateValue(binding.target, forKey: binding.source) == nil,
                  targets.insert(binding.target).inserted else {
                throw MyDayReplacementValueProjectionFailureV1.invalidBinding
            }
        }
        guard result.count == required.count, Set(result.keys) == required else {
            throw MyDayReplacementValueProjectionFailureV1.invalidBinding
        }
        return result
    }

    static func exactIdentityCorresponds(
        source: MyDayEligibleReferenceV1,
        target: MyDayEligibleReferenceV1
    ) -> Bool {
        switch (source, target) {
        case let (.workPacket(lhs), .workPacket(rhs)):
            return lhs.manifestID == rhs.manifestID
                && lhs.packetID == rhs.packetID
                && lhs.packetVersion == rhs.packetVersion
        case let (
            .roundSession(_, lhsID, lhsRevision, _),
            .roundSession(_, rhsID, rhsRevision, _)
        ):
            return lhsID == rhsID && lhsRevision == rhsRevision
        case let (
            .scheduleOccurrence(lhs, _),
            .scheduleOccurrence(rhs, _)
        ):
            return lhs.schedule.scheduleDefinitionID == rhs.schedule.scheduleDefinitionID
                && lhs.schedule.scheduleReleaseID == rhs.schedule.scheduleReleaseID
                && lhs.schedule.expectedScheduleRevision
                    == rhs.schedule.expectedScheduleRevision
                && lhs.occurrenceID == rhs.occurrenceID
                && lhs.expectedOccurrenceRevision == rhs.expectedOccurrenceRevision
        case let (
            .resumableDraft(_, lhsID, lhsRevision, _, lhsAnchor),
            .resumableDraft(_, rhsID, rhsRevision, _, rhsAnchor)
        ):
            return lhsID == rhsID && lhsRevision == rhsRevision
                && lhsAnchor == rhsAnchor
        default:
            return false
        }
    }

    static func referenceRevisionKey(_ value: MyDayEligibleReferenceV1) -> String {
        "\(value.stableKey)|\(value.sourceRevision)"
    }

    static func reboundActor(
        _ source: ActorSnapshotV1,
        sourceWorkspaceID: WorkspaceID,
        targetWorkspaceID: WorkspaceID
    ) throws -> ActorSnapshotV1 {
        try source.validate()
        guard source.workspaceID == sourceWorkspaceID else {
            throw MyDayReplacementValueProjectionFailureV1.invalidSource
        }
        let actor = try LocalActorReferenceV1(
            actorReferenceID: source.actor.actorReferenceID,
            workspaceID: targetWorkspaceID,
            partyID: source.actor.partyID,
            displayName: source.actor.displayName
        )
        return try ActorSnapshotV1(
            snapshotID: source.snapshotID,
            workspaceID: targetWorkspaceID,
            actor: actor,
            responsibility: source.responsibility,
            displayNameAtTime: source.displayNameAtTime,
            capturedAt: source.capturedAt
        )
    }
}

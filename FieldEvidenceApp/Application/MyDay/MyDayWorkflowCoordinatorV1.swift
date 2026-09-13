import Foundation

enum MyDayWorkflowCommandV1: Equatable, Sendable {
    case save(MyDaySavePreviewV1)
    case recoverSave(MyDaySavePreviewV1)
    case carryover(MyDayCarryoverPreviewV1)
    case recoverCarryover(MyDayCarryoverPreviewV1)
}

enum MyDayWorkflowOutcomeV1: Equatable, Sendable {
    case saved(MyDayCommandResultV1)
    case carriedOver(MyDayCommandResultV1)
}

@MainActor
final class MyDayWorkflowCoordinatorV1 {
    private let canonical: MyDayCoordinatorV1
    private let clock: any ApplicationClock

    init(canonical: MyDayCoordinatorV1, clock: any ApplicationClock) {
        self.canonical = canonical
        self.clock = clock
    }

    func draft(
        key: MyDayKeyV1,
        selectedItems: [MyDayDraftItemV1],
        eligibleReferences: [MyDayEligibleReferenceV1],
        predecessor: MyDayPlanV1? = nil
    ) throws -> MyDayPlanDraftV1 {
        try Self.projectDraft(key: key, selectedItems: selectedItems,
                              eligibleReferences: eligibleReferences, predecessor: predecessor)
    }

    static func projectDraft(
        key: MyDayKeyV1,
        selectedItems: [MyDayDraftItemV1],
        eligibleReferences: [MyDayEligibleReferenceV1],
        predecessor: MyDayPlanV1? = nil
    ) throws -> MyDayPlanDraftV1 {
        try key.validate()
        try predecessor?.validate()
        try eligibleReferences.forEach { try $0.validate() }
        guard predecessor == nil || predecessor?.key == key,
              eligibleReferences.allSatisfy({ $0.workspaceID == key.workspaceID }),
              Set(eligibleReferences.map(\.stableKey)).count == eligibleReferences.count else {
            throw MyDayWorkflowFailureV1.ineligibleReference
        }
        let retained = Dictionary(uniqueKeysWithValues: (predecessor?.items ?? []).map {
            ($0.membershipID, $0.reference)
        })
        var projectedEligibility = Dictionary(uniqueKeysWithValues: eligibleReferences.map {
            ($0.stableKey, $0)
        })
        for selected in selectedItems {
            guard retained[selected.membershipID] == selected.reference
                    || eligibleReferences.contains(selected.reference) else {
                throw MyDayWorkflowFailureV1.ineligibleReference
            }
            // This projection supports editing a historical membership; it
            // does not replace the canonical writer's current-source check.
            projectedEligibility[selected.reference.stableKey] = selected.reference
        }
        return try .init(
            key: key,
            items: selectedItems,
            eligibleReferences: Array(projectedEligibility.values)
        )
    }

    /// Projection-only accessible movement. It has no canonical effect until
    /// the returned draft is explicitly previewed and saved.
    func move(
        _ draft: MyDayPlanDraftV1,
        action: MyDayAccessibleMoveV1
    ) throws -> MyDayPlanDraftV1 {
        try Self.projectMove(draft, action: action)
    }

    static func projectMove(
        _ draft: MyDayPlanDraftV1,
        action: MyDayAccessibleMoveV1
    ) throws -> MyDayPlanDraftV1 {
        var items = draft.items
        let membershipID: UUID
        let requestedIndex: Int
        switch action {
        case .up(let id):
            membershipID = id
            guard let index = items.firstIndex(where: { $0.membershipID == id }) else {
                throw MyDayWorkflowFailureV1.invalidManualOrder
            }
            requestedIndex = index - 1
        case .down(let id):
            membershipID = id
            guard let index = items.firstIndex(where: { $0.membershipID == id }) else {
                throw MyDayWorkflowFailureV1.invalidManualOrder
            }
            requestedIndex = index + 1
        case let .toIndex(id, index):
            membershipID = id
            requestedIndex = index
        }
        guard let sourceIndex = items.firstIndex(where: { $0.membershipID == membershipID }),
              items.indices.contains(requestedIndex) else {
            throw MyDayWorkflowFailureV1.invalidManualOrder
        }
        let item = items.remove(at: sourceIndex)
        items.insert(item, at: requestedIndex)
        return try .init(
            key: draft.key,
            items: items,
            eligibleReferences: draft.eligibleReferences
        )
    }

    func previewSave(
        draft: MyDayPlanDraftV1,
        predecessor: MyDayPlanV1?,
        planID: UUID,
        mutationID: MutationIDV1,
        actor: ActorSnapshotV1
    ) throws -> MyDaySavePreviewV1 {
        try actor.validate()
        guard predecessor?.key == draft.key || predecessor == nil,
              predecessor?.planID == planID || predecessor == nil,
              actor.workspaceID == draft.key.workspaceID else {
            throw MyDayWorkflowFailureV1.invalidContext
        }
        let revision: UInt64
        if let predecessor {
            let (next, overflow) = predecessor.revision.addingReportingOverflow(1)
            guard !overflow else { throw MyDayWorkflowFailureV1.invalidContext }
            revision = next
        } else {
            revision = 1
        }
        let items = try draft.items.enumerated().map { index, item in
            try MyDayItemV1(
                membershipID: item.membershipID,
                reference: item.reference,
                manualOrder: index,
                estimate: item.estimate
            )
        }
        let successor = try MyDayPlanV1(
            planID: planID,
            key: draft.key,
            items: items,
            predecessor: predecessor,
            revision: revision,
            mutationID: mutationID,
            authoredBy: actor,
            authoredAt: clock.now()
        )
        return try .init(successor: successor, predecessor: predecessor)
    }

    func summary(
        plan: MyDayPlanV1,
        dueQueue: OccurrenceDueQueueStateV1,
        exceptionQueue: ExceptionQueueProjectionV1
    ) throws -> MyDaySummaryProjectionV1 {
        let readiness = try canonical.readinessProjection(
            for: plan,
            evaluatedAt: dueQueue.evaluatedAt
        )
        return try .init(
            plan: plan,
            readiness: readiness,
            dueQueue: dueQueue,
            exceptionQueue: exceptionQueue
        )
    }

    func routeIntent(
        from summary: MyDaySummaryProjectionV1,
        membershipID: UUID
    ) throws -> MyDayExistingRouteIntentV1 {
        try MyDayLimitsV1.id(membershipID)
        guard let item = summary.items.first(where: {
            $0.item.membershipID == membershipID
        }), let intent = item.routeIntent else {
            throw MyDayWorkflowFailureV1.routeUnavailable
        }
        return intent
    }

    func previewCarryover(
        source: MyDayPlanV1,
        sourceSummary: MyDaySummaryProjectionV1,
        targetKey: MyDayKeyV1,
        targetPredecessor: MyDayPlanV1?,
        membershipIDs: [UUID],
        targetPlanID: UUID,
        mutationID: MutationIDV1,
        actor: ActorSnapshotV1
    ) throws -> MyDayCarryoverPreviewV1 {
        try sourceSummary.validate(plan: source)
        let command = try Self.makeCarryover(
            source: source,
            eligibleMembershipIDs: sourceSummary.carryoverEligibleMembershipIDs,
            targetKey: targetKey,
            targetPredecessor: targetPredecessor,
            membershipIDs: membershipIDs,
            targetPlanID: targetPlanID,
            mutationID: mutationID,
            actor: actor,
            authoredAt: { clock.now() }
        )
        guard case let .carryover(plan, commandSource, target, receipt) = command,
              commandSource == source else {
            throw MyDayWorkflowFailureV1.invalidContext
        }
        return try .init(
            plan: plan,
            source: source,
            target: target,
            receipt: receipt,
            sourceSummary: sourceSummary
        )
    }

    static func prepareCarryover(
        source: MyDayPlanV1,
        readiness: MyDayReadinessProjectionV1,
        targetKey: MyDayKeyV1,
        targetPredecessor: MyDayPlanV1?,
        membershipIDs: [UUID],
        targetPlanID: UUID,
        mutationID: MutationIDV1,
        actor: ActorSnapshotV1,
        authoredAt: Date
    ) throws -> MyDayCommandV1 {
        try readiness.validate(plan: source)
        let eligible = zip(source.items, readiness.frontiers).compactMap { item, frontier in
            MyDaySummaryItemV1.isCarryoverEligible(
                plannedReference: item.reference,
                currentReference: frontier.currentReference,
                state: frontier.state
            ) ? item.membershipID : nil
        }
        return try makeCarryover(
            source: source,
            eligibleMembershipIDs: eligible,
            targetKey: targetKey,
            targetPredecessor: targetPredecessor,
            membershipIDs: membershipIDs,
            targetPlanID: targetPlanID,
            mutationID: mutationID,
            actor: actor,
            authoredAt: { authoredAt }
        )
    }

    private static func makeCarryover(
        source: MyDayPlanV1,
        eligibleMembershipIDs: [UUID],
        targetKey: MyDayKeyV1,
        targetPredecessor: MyDayPlanV1?,
        membershipIDs: [UUID],
        targetPlanID: UUID,
        mutationID: MutationIDV1,
        actor: ActorSnapshotV1,
        authoredAt: () -> Date
    ) throws -> MyDayCommandV1 {
        try source.validate()
        try targetKey.validate()
        try actor.validate()
        guard !membershipIDs.isEmpty,
              Set(membershipIDs).count == membershipIDs.count,
              membershipIDs.allSatisfy(eligibleMembershipIDs.contains),
              targetKey.workspaceID == source.key.workspaceID,
              targetKey != source.key,
              targetPredecessor?.key == targetKey || targetPredecessor == nil,
              targetPredecessor?.planID == targetPlanID || targetPredecessor == nil,
              actor.workspaceID == source.key.workspaceID else {
            throw MyDayWorkflowFailureV1.carryoverIneligible
        }
        let selectedSet = Set(membershipIDs)
        let selected = source.items.filter { selectedSet.contains($0.membershipID) }
        guard selected.map(\.membershipID) == membershipIDs else {
            throw MyDayWorkflowFailureV1.invalidManualOrder
        }
        let existing = targetPredecessor?.items ?? []
        guard Set(existing.map(\.membershipID)).isDisjoint(with: selectedSet),
              Set(existing.map { $0.reference.stableKey }).isDisjoint(
                with: Set(selected.map { $0.reference.stableKey })
              ),
              existing.count + selected.count <= MyDayLimitsV1.maximumItems else {
            throw MyDayWorkflowFailureV1.carryoverIneligible
        }
        let targetItems = try (existing + selected).enumerated().map { index, item in
            try MyDayItemV1(
                membershipID: item.membershipID,
                reference: item.reference,
                manualOrder: index,
                estimate: item.estimate
            )
        }
        let revision: UInt64
        if let targetPredecessor {
            let (next, overflow) = targetPredecessor.revision.addingReportingOverflow(1)
            guard !overflow else { throw MyDayWorkflowFailureV1.invalidContext }
            revision = next
        } else {
            revision = 1
        }
        let target = try MyDayPlanV1(
            planID: targetPlanID,
            key: targetKey,
            items: targetItems,
            predecessor: targetPredecessor,
            revision: revision,
            mutationID: mutationID,
            authoredBy: actor,
            authoredAt: authoredAt()
        )
        let plan = try MyDayCarryoverPlanV1(
            sourcePlan: source,
            targetKey: targetKey,
            membershipIDs: membershipIDs,
            expectedTargetPlan: targetPredecessor
        )
        let receipt = try MyDayCarryoverReceiptV1(
            plan: plan,
            source: source,
            target: target,
            mutationID: mutationID,
            committedAt: target.authoredAt
        )
        return .carryover(plan: plan, source: source, target: target, receipt: receipt)
    }

    func execute(_ command: MyDayWorkflowCommandV1) throws -> MyDayWorkflowOutcomeV1 {
        switch command {
        case .save(let preview):
            guard preview.zeroWrite else { throw MyDayWorkflowFailureV1.invalidContext }
            return .saved(try canonical.save(
                successor: preview.successor,
                predecessor: preview.predecessor
            ))
        case .recoverSave(let preview):
            guard preview.zeroWrite else { throw MyDayWorkflowFailureV1.invalidContext }
            return .saved(try canonical.recoverSave(
                successor: preview.successor,
                predecessor: preview.predecessor
            ))
        case .carryover(let preview):
            try preview.sourceSummary.validate(plan: preview.source)
            guard preview.zeroWrite,
                  preview.eligibleMembershipIDs
                    == preview.sourceSummary.carryoverEligibleMembershipIDs,
                  preview.plan.membershipIDs.allSatisfy(
                    preview.eligibleMembershipIDs.contains
                  ) else {
                throw MyDayWorkflowFailureV1.carryoverIneligible
            }
            return .carriedOver(try canonical.carryover(
                plan: preview.plan,
                source: preview.source,
                target: preview.target,
                receipt: preview.receipt
            ))
        case .recoverCarryover(let preview):
            try preview.sourceSummary.validate(plan: preview.source)
            guard preview.zeroWrite,
                  preview.eligibleMembershipIDs
                    == preview.sourceSummary.carryoverEligibleMembershipIDs,
                  preview.plan.membershipIDs.allSatisfy(
                    preview.eligibleMembershipIDs.contains
                  ) else {
                throw MyDayWorkflowFailureV1.carryoverIneligible
            }
            return .carriedOver(try canonical.recoverCarryover(
                plan: preview.plan,
                source: preview.source,
                target: preview.target,
                receipt: preview.receipt
            ))
        }
    }
}

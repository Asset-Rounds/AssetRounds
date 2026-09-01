import Foundation

/// Read-only source projection used for preview and post-write reconciliation.
/// Implementations must derive these values from the incumbent work-packet,
/// round-session, schedule-occurrence, and draft sources. Nothing returned by
/// this protocol is My Day persistence truth.
@MainActor protocol MyDaySourceFrontierReadingV1: AnyObject {
    func sourceFrontiers(
        for plan: MyDayPlanV1,
        evaluatedAt: Date
    ) throws -> [MyDaySourceFrontierV1]
}

/// Sole-writer application boundary for My Day canonical mutations.
///
/// `commit` must execute in the incumbent WorkspaceWriter transaction. Before
/// changing My Day rows it must re-resolve every eligible source reference and
/// require its exact workspace, stable identity, revision, and digest to equal
/// the command reference. It must also compare the command predecessor(s) with
/// the live plan frontier and commit the plan, carryover receipt, journal entry,
/// and mutation receipt atomically. A repeated MutationID may return the prior
/// result only when its canonical command digest is identical.
@MainActor protocol MyDayWritingV1: AnyObject {
    func currentPlan(for key: MyDayKeyV1) throws -> MyDayPlanV1?
    func result(
        workspaceID: WorkspaceID,
        mutationID: MutationIDV1
    ) throws -> MyDayCommandResultV1?
    func commit(_ command: MyDayCommandV1) throws -> MyDayCommandResultV1
}

@MainActor final class MyDayCoordinatorV1 {
    private let writer: any MyDayWritingV1
    private let sourceReader: any MyDaySourceFrontierReadingV1

    init(
        writer: any MyDayWritingV1,
        sourceReader: any MyDaySourceFrontierReadingV1
    ) {
        self.writer = writer
        self.sourceReader = sourceReader
    }

    /// Saves one canonical plan generation. The predecessor is an exact CAS
    /// token; callers cannot create a second plan for the same natural key or
    /// replace a newer generation.
    func save(
        successor: MyDayPlanV1,
        predecessor: MyDayPlanV1?
    ) throws -> MyDayCommandResultV1 {
        let command = MyDayCommandV1.save(
            successor: successor,
            predecessor: predecessor
        )
        try command.validate()
        try validateNaturalKey(successor.key)

        if let replay = try replay(for: command) {
            guard replay.plan == successor else {
                throw MyDayFailureV1.divergentMutation
            }
            return replay
        }

        let live = try writer.currentPlan(for: successor.key)
        try requireExactPlanFrontier(live, expected: predecessor)
        try requireLiveSources(for: successor, evaluatedAt: successor.authoredAt)

        return try commit(command, expectedPlan: successor)
    }

    /// Atomically carries explicitly selected memberships into another
    /// canonical natural key. The source plan is read-only history, while the
    /// target plan uses its own exact predecessor CAS token.
    func carryover(
        plan: MyDayCarryoverPlanV1,
        source: MyDayPlanV1,
        target: MyDayPlanV1,
        receipt: MyDayCarryoverReceiptV1
    ) throws -> MyDayCommandResultV1 {
        let command = MyDayCommandV1.carryover(
            plan: plan,
            source: source,
            target: target,
            receipt: receipt
        )
        try command.validate()
        try validateNaturalKey(source.key)
        try validateNaturalKey(target.key)
        try validateCarriedMemberships(plan: plan, source: source, target: target)

        if let replay = try replay(for: command) {
            guard replay.plan == target else {
                throw MyDayFailureV1.divergentMutation
            }
            return replay
        }

        let liveSource = try writer.currentPlan(for: source.key)
        try requireExactPlanFrontier(liveSource, expected: source)

        let liveTarget = try writer.currentPlan(for: target.key)
        let expectedTarget: MyDayPlanV1?
        if plan.expectedTargetPlan == nil {
            expectedTarget = nil
        } else {
            guard let liveTarget,
                  plan.expectedTargetPlan == (try MyDayPlanReferenceV1(liveTarget)) else {
                throw MyDayFailureV1.staleRevision
            }
            expectedTarget = liveTarget
        }
        try requireExactPlanFrontier(liveTarget, expected: expectedTarget)
        try target.validate(predecessor: expectedTarget)
        try requireLiveSources(for: target, evaluatedAt: target.authoredAt)

        return try commit(command, expectedPlan: target)
    }

    /// Rebuilds status, due, readiness, and source reconciliation from current
    /// source truth. The returned projection is never written as My Day state.
    func readinessProjection(
        for plan: MyDayPlanV1,
        evaluatedAt: Date
    ) throws -> MyDayReadinessProjectionV1 {
        try plan.validate()
        try MyDayLimitsV1.millisecondInstant(evaluatedAt)
        let frontiers = try validatedFrontiers(for: plan, evaluatedAt: evaluatedAt)
        return try MyDayReadinessProjectionV1(
            plan: plan,
            evaluatedAt: evaluatedAt,
            frontiers: frontiers
        )
    }

    /// Builds Today/Work sections from the canonical due projection and exact
    /// My Day source frontiers. A missing source frontier is represented as
    /// partial readiness instead of being filled from a latest-value fallback.
    func recurringRoundExperience(
        for plan: MyDayPlanV1,
        dueQueue: OccurrenceDueQueueStateV1
    ) throws -> MyDayRecurringRoundExperienceV1 {
        let readiness = try readinessProjection(for: plan, evaluatedAt: dueQueue.evaluatedAt)
        return try MyDayRecurringRoundExperienceV1(queue: dueQueue, readiness: readiness)
    }

    /// Reminder reconciliation is intentionally a parallel device-local
    /// result. It is never an input to `recurringRoundExperience`.
    func reconcileLocalReminders(
        projection: ReminderProjectionV1,
        observedReminderEntries: [ReminderEntryV1],
        authorization: LocalReminderAuthorizationV1
    ) throws -> LocalReminderReconciliationV1 {
        try LocalReminderReconciliationV1(
            projection: projection,
            observedReminderEntries: observedReminderEntries,
            authorization: authorization
        )
    }

    private func replay(for command: MyDayCommandV1) throws -> MyDayCommandResultV1? {
        guard let result = try writer.result(
            workspaceID: command.workspaceID,
            mutationID: command.mutationID
        ) else { return nil }
        do {
            try result.validate()
            _ = try MyDayCommandReplayResolutionV1.resolve(
                command: command,
                priorReceipt: result.receipt
            )
            return result
        } catch {
            throw MyDayFailureV1.divergentMutation
        }
    }

    private func commit(
        _ command: MyDayCommandV1,
        expectedPlan: MyDayPlanV1
    ) throws -> MyDayCommandResultV1 {
        let result = try writer.commit(command)
        try result.validate()
        try result.receipt.validate(command: command)
        guard result.plan == expectedPlan else {
            throw MyDayFailureV1.divergentMutation
        }
        return result
    }

    private func validateNaturalKey(_ key: MyDayKeyV1) throws {
        try key.validate()
        guard key.stableKey == "\(key.workspaceID.rawValue.uuidString.lowercased())|\(key.civilDate.canonicalString)|\(key.ianaTimeZoneIdentifier)" else {
            throw MyDayFailureV1.invalidDigest
        }
    }

    private func requireExactPlanFrontier(
        _ live: MyDayPlanV1?,
        expected: MyDayPlanV1?
    ) throws {
        try live?.validate()
        try expected?.validate()
        guard live == expected else { throw MyDayFailureV1.staleRevision }
    }

    private func requireLiveSources(
        for plan: MyDayPlanV1,
        evaluatedAt: Date
    ) throws {
        let frontiers = try validatedFrontiers(for: plan, evaluatedAt: evaluatedAt)
        guard zip(frontiers, plan.items).allSatisfy({ pair in
            pair.0.currentReference == pair.1.reference
                && pair.0.state != .missing
                && pair.0.state != .retired
                && pair.0.state != .stale
        }) else { throw MyDayFailureV1.staleRevision }
    }

    private func validatedFrontiers(
        for plan: MyDayPlanV1,
        evaluatedAt: Date
    ) throws -> [MyDaySourceFrontierV1] {
        let frontiers = try sourceReader.sourceFrontiers(
            for: plan,
            evaluatedAt: evaluatedAt
        )
        try frontiers.forEach { try $0.validate() }
        guard frontiers.count == plan.items.count,
              zip(frontiers, plan.items).allSatisfy({ pair in
                  pair.0.membershipID == pair.1.membershipID
                      && pair.0.plannedReference == pair.1.reference
                      && pair.0.evaluatedAt == evaluatedAt
                      && pair.0.plannedReference.workspaceID == plan.key.workspaceID
              }) else { throw MyDayFailureV1.staleRevision }
        return frontiers
    }

    private func validateCarriedMemberships(
        plan: MyDayCarryoverPlanV1,
        source: MyDayPlanV1,
        target: MyDayPlanV1
    ) throws {
        let sourceByMembership = Dictionary(
            uniqueKeysWithValues: source.items.map { ($0.membershipID, $0) }
        )
        let targetByMembership = Dictionary(
            uniqueKeysWithValues: target.items.map { ($0.membershipID, $0) }
        )
        guard plan.membershipIDs.allSatisfy({ membershipID in
            guard let sourceItem = sourceByMembership[membershipID],
                  let targetItem = targetByMembership[membershipID] else {
                return false
            }
            return targetItem.reference == sourceItem.reference
                && targetItem.estimate == sourceItem.estimate
        }) else { throw MyDayFailureV1.invalidCarryover }
    }
}

/// Lifecycle ownership stays outside the application coordinator: replace
/// restore preserves exact canonical plans, configuration clone omits them,
/// workspace fork filters to nonactive history, and Erase removes them through
/// the incumbent persistence lifecycle registry.
enum C57MyDayCoordinatorLifecycleBoundaryV1 {
    static let applicationLifecycleCommandCount = 0
    static let lifecycleIsInfrastructureOwned = true
    static let sourceMutationCount = 0
    static let storedDerivedProjectionCount = 0
}

enum C22RecurringRoundMyDayBoundaryV1 {
    static let storedQueueProjectionCount = 0
    static let storedReminderReconciliationCount = 0
    static let reminderDeliveryChangesCanonicalDueTruth = false
    static let missingFrontierUsesLatestFallback = false
}

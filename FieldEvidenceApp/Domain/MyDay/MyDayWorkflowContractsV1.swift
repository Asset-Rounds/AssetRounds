import Foundation

enum MyDayWorkflowFailureV1: Error, Equatable, Sendable {
    case invalidContext
    case ineligibleReference
    case invalidManualOrder
    case staleProjection
    case carryoverIneligible
    case routeUnavailable
    case receiptMismatch
}

struct MyDayDraftItemV1: Codable, Equatable, Hashable, Sendable {
    let membershipID: UUID
    let reference: MyDayEligibleReferenceV1
    let estimate: MyDayEstimateV1?

    init(
        membershipID: UUID,
        reference: MyDayEligibleReferenceV1,
        estimate: MyDayEstimateV1? = nil
    ) throws {
        try MyDayLimitsV1.id(membershipID)
        try reference.validate()
        try estimate?.validate()
        self.membershipID = membershipID
        self.reference = reference
        self.estimate = estimate
    }
}

/// Array position is the sole ordering authority. No due, readiness, duration,
/// or exception value is allowed to reorder this draft.
struct MyDayPlanDraftV1: Codable, Equatable, Sendable {
    let key: MyDayKeyV1
    let items: [MyDayDraftItemV1]
    let eligibleReferences: [MyDayEligibleReferenceV1]
    let zeroWrite: Bool

    /// Structural draft construction for decode/migration and hostile-input
    /// validation. Product selection should use the workflow coordinator's
    /// eligibility-bound `draft` entry point.
    init(key: MyDayKeyV1, items: [MyDayDraftItemV1]) throws {
        try self.init(
            key: key,
            items: items,
            eligibleReferences: items.map(\.reference)
        )
    }

    init(
        key: MyDayKeyV1,
        items: [MyDayDraftItemV1],
        eligibleReferences: [MyDayEligibleReferenceV1]
    ) throws {
        try key.validate()
        try items.forEach { try $0.reference.validate(); try $0.estimate?.validate() }
        try eligibleReferences.forEach { try $0.validate() }
        let orderedEligible = eligibleReferences.sorted { $0.stableKey < $1.stableKey }
        guard items.count <= MyDayLimitsV1.maximumItems,
              items.allSatisfy({ $0.reference.workspaceID == key.workspaceID }),
              orderedEligible.allSatisfy({ $0.workspaceID == key.workspaceID }),
              Set(items.map(\.membershipID)).count == items.count,
              Set(items.map { $0.reference.stableKey }).count == items.count,
              Set(orderedEligible.map(\.stableKey)).count == orderedEligible.count,
              items.allSatisfy({ orderedEligible.contains($0.reference) }) else {
            throw MyDayWorkflowFailureV1.invalidManualOrder
        }
        self.key = key
        self.items = items
        self.eligibleReferences = orderedEligible
        zeroWrite = true
    }
}

enum MyDayAccessibleMoveV1: Equatable, Sendable {
    case up(membershipID: UUID)
    case down(membershipID: UUID)
    case toIndex(membershipID: UUID, index: Int)
}

enum MyDayExistingRouteActionV1: String, Codable, Equatable, Hashable, Sendable {
    case start = "START"
    case resume = "RESUME"
}

/// A typed handoff to incumbent work navigation. It is not a route engine and
/// does not claim that the destination was opened or that work began.
struct MyDayExistingRouteIntentV1: Codable, Equatable, Hashable, Sendable {
    let reference: MyDayEligibleReferenceV1
    let action: MyDayExistingRouteActionV1
    let routeRequested: Bool
    let workStarted: Bool

    init(reference: MyDayEligibleReferenceV1, action: MyDayExistingRouteActionV1) throws {
        try reference.validate()
        self.reference = reference
        self.action = action
        routeRequested = false
        workStarted = false
    }
}

enum MyDayDueCueV1: String, Codable, Equatable, Hashable, Sendable {
    case none = "NONE"
    case upcoming = "UPCOMING"
    case ready = "READY"
    case due = "DUE"
    case overdue = "OVERDUE"
    case deferred = "DEFERRED"
    case started = "STARTED"
    case history = "HISTORY"
}

enum MyDayWorkflowItemStatusV1: String, Codable, Equatable, Hashable, Sendable {
    case actionable = "ACTIONABLE"
    case reopened = "REOPENED"
    case completed = "COMPLETED"
    case cancelled = "CANCELLED"
    case unavailable = "UNAVAILABLE"
}

struct MyDaySummaryItemV1: Codable, Equatable, Hashable, Sendable {
    let item: MyDayItemV1
    let currentReference: MyDayEligibleReferenceV1?
    let sourceState: MyDaySourceStateV1
    let status: MyDayWorkflowItemStatusV1
    let readiness: MyDayReadinessV1
    let dueAt: Date?
    let dueCue: MyDayDueCueV1
    let routeIntent: MyDayExistingRouteIntentV1?
    let carryoverEligible: Bool

    init(
        item: MyDayItemV1,
        frontier: MyDaySourceFrontierV1,
        dueReason: OccurrenceDueReasonV1?
    ) throws {
        try item.validate()
        try frontier.validate()
        guard frontier.membershipID == item.membershipID,
              frontier.plannedReference == item.reference else {
            throw MyDayWorkflowFailureV1.staleProjection
        }
        self.item = item
        currentReference = frontier.currentReference
        sourceState = frontier.state
        readiness = frontier.readiness
        dueAt = frontier.dueAt
        dueCue = Self.cue(dueReason)
        let exactCurrentReference = frontier.currentReference == item.reference
        if !exactCurrentReference,
           frontier.state == .active || frontier.state == .reopened {
            status = .unavailable
        } else {
            switch frontier.state {
            case .active:
                status = .actionable
            case .reopened:
                status = .reopened
            case .completed:
                status = .completed
            case .cancelled:
                status = .cancelled
            case .retired, .missing, .stale:
                status = .unavailable
            }
        }
        let mayAct = exactCurrentReference
            && (frontier.state == .active || frontier.state == .reopened)
        if mayAct, let current = frontier.currentReference {
            let resumes = frontier.state == .reopened
                || dueReason == .started
                || Self.isResumableDraft(current)
            routeIntent = try .init(
                reference: current,
                action: resumes ? .resume : .start
            )
        } else {
            routeIntent = nil
        }
        carryoverEligible = mayAct
    }

    func validate() throws {
        try item.validate()
        try currentReference?.validate()
        try routeIntent?.reference.validate()
        let expectedStatus: MyDayWorkflowItemStatusV1
        let exactCurrentReference = currentReference == item.reference
        if !exactCurrentReference,
           sourceState == .active || sourceState == .reopened {
            expectedStatus = .unavailable
        } else {
            switch sourceState {
            case .active: expectedStatus = .actionable
            case .reopened: expectedStatus = .reopened
            case .completed: expectedStatus = .completed
            case .cancelled: expectedStatus = .cancelled
            case .retired, .missing, .stale: expectedStatus = .unavailable
            }
        }
        let expectedEligible = exactCurrentReference
            && (sourceState == .active || sourceState == .reopened)
        guard status == expectedStatus,
              carryoverEligible == expectedEligible,
              (routeIntent != nil) == expectedEligible,
              (!expectedEligible || routeIntent?.reference == currentReference),
              routeIntent?.workStarted == false,
              routeIntent?.routeRequested == false,
              (!expectedEligible || sourceState != .reopened || routeIntent?.action == .resume) else {
            throw MyDayWorkflowFailureV1.staleProjection
        }
    }

    private static func isResumableDraft(_ value: MyDayEligibleReferenceV1) -> Bool {
        if case .resumableDraft = value { return true }
        return false
    }

    private static func cue(_ reason: OccurrenceDueReasonV1?) -> MyDayDueCueV1 {
        switch reason {
        case .none: return .none
        case .beforeReadyWindow: return .upcoming
        case .readyWindowOpen: return .ready
        case .dueWithinGrace: return .due
        case .overdueAfterGrace: return .overdue
        case .explicitlyDeferred: return .deferred
        case .started: return .started
        case .explicitlyMissed, .explicitlySkipped, .explicitlyCancelled, .completed:
            return .history
        }
    }
}

/// C41's contract-ref projection. It is deterministic, nonpersistent, and
/// rebuildable from C57 plan/readiness, C22 due truth, and C12 exception truth.
struct MyDaySummaryProjectionV1: Codable, Equatable, Sendable {
    let plan: MyDayPlanReferenceV1
    let evaluatedAt: Date
    let items: [MyDaySummaryItemV1]
    let totalEstimatedMinutes: Int?
    let dueQueueSHA256: String
    let unresolvedExceptionCount: Int
    let hasPartialReadiness: Bool
    let derived: Bool
    let rebuildable: Bool
    let automaticPrioritizationApplied: Bool
    let scheduleTruthMutated: Bool
    let projectionSHA256: String

    init(
        plan: MyDayPlanV1,
        readiness: MyDayReadinessProjectionV1,
        dueQueue: OccurrenceDueQueueStateV1,
        exceptionQueue: ExceptionQueueProjectionV1
    ) throws {
        try plan.validate()
        try readiness.validate(plan: plan)
        try dueQueue.validate()
        try exceptionQueue.validate()
        guard dueQueue.workspaceID == plan.key.workspaceID,
              exceptionQueue.workspaceID == plan.key.workspaceID,
              dueQueue.evaluatedAt == readiness.evaluatedAt else {
            throw MyDayWorkflowFailureV1.invalidContext
        }
        var dueReasons: [OccurrenceIDV1: OccurrenceDueReasonV1] = [:]
        for due in dueQueue.items {
            guard dueReasons.updateValue(due.reason, forKey: due.entry.occurrenceID) == nil else {
                throw MyDayWorkflowFailureV1.staleProjection
            }
        }
        let built = try zip(plan.items, readiness.frontiers).map { item, frontier in
            let reason: OccurrenceDueReasonV1?
            if case let .scheduleOccurrence(anchor, _) = item.reference {
                reason = dueReasons[anchor.occurrenceID]
            } else {
                reason = nil
            }
            return try MyDaySummaryItemV1(item: item, frontier: frontier, dueReason: reason)
        }
        let estimates = built.compactMap { $0.item.estimate?.wholeMinutes }
        let total = estimates.reduce(0, +)
        self.plan = try .init(plan)
        evaluatedAt = readiness.evaluatedAt
        items = built
        totalEstimatedMinutes = estimates.isEmpty ? nil : total
        dueQueueSHA256 = dueQueue.stateSHA256
        unresolvedExceptionCount = exceptionQueue.unresolvedCount
        hasPartialReadiness = built.contains { $0.readiness != .ready || $0.status == .unavailable }
        derived = true
        rebuildable = true
        automaticPrioritizationApplied = false
        scheduleTruthMutated = false
        projectionSHA256 = try MyDayCanonicalCodecV1.sha256(Basis(
            plan: self.plan,
            evaluatedAt: evaluatedAt,
            items: built,
            totalEstimatedMinutes: totalEstimatedMinutes,
            dueQueueSHA256: dueQueueSHA256,
            unresolvedExceptionCount: unresolvedExceptionCount,
            hasPartialReadiness: hasPartialReadiness,
            derived: true,
            rebuildable: true,
            automaticPrioritizationApplied: false,
            scheduleTruthMutated: false
        ))
    }

    var carryoverEligibleMembershipIDs: [UUID] {
        items.filter(\.carryoverEligible).map(\.item.membershipID)
    }

    func validate() throws {
        try plan.validate()
        try MyDayLimitsV1.millisecondInstant(evaluatedAt)
        try items.forEach { try $0.validate() }
        try MyDayLimitsV1.digest(dueQueueSHA256)
        try MyDayLimitsV1.digest(projectionSHA256)
        let estimates = items.compactMap { $0.item.estimate?.wholeMinutes }
        guard items.count <= MyDayLimitsV1.maximumItems,
              items.allSatisfy({ $0.item.reference.workspaceID == plan.key.workspaceID }),
              items.map(\.item.manualOrder) == Array(0..<items.count),
              Set(items.map(\.item.membershipID)).count == items.count,
              totalEstimatedMinutes == (estimates.isEmpty ? nil : estimates.reduce(0, +)),
              unresolvedExceptionCount >= 0,
              hasPartialReadiness == items.contains(where: {
                  $0.readiness != .ready || $0.status == .unavailable
              }),
              derived, rebuildable,
              !automaticPrioritizationApplied,
              !scheduleTruthMutated,
              projectionSHA256 == (try MyDayCanonicalCodecV1.sha256(basis)) else {
            throw MyDayWorkflowFailureV1.staleProjection
        }
    }

    func validate(plan value: MyDayPlanV1) throws {
        try validate()
        try value.validate()
        guard plan == (try MyDayPlanReferenceV1(value)),
              items.map(\.item) == value.items else {
            throw MyDayWorkflowFailureV1.staleProjection
        }
    }

    private var basis: Basis { .init(
        plan: plan,
        evaluatedAt: evaluatedAt,
        items: items,
        totalEstimatedMinutes: totalEstimatedMinutes,
        dueQueueSHA256: dueQueueSHA256,
        unresolvedExceptionCount: unresolvedExceptionCount,
        hasPartialReadiness: hasPartialReadiness,
        derived: derived,
        rebuildable: rebuildable,
        automaticPrioritizationApplied: automaticPrioritizationApplied,
        scheduleTruthMutated: scheduleTruthMutated
    ) }

    private struct Basis: Codable {
        let plan: MyDayPlanReferenceV1
        let evaluatedAt: Date
        let items: [MyDaySummaryItemV1]
        let totalEstimatedMinutes: Int?
        let dueQueueSHA256: String
        let unresolvedExceptionCount: Int
        let hasPartialReadiness: Bool
        let derived: Bool
        let rebuildable: Bool
        let automaticPrioritizationApplied: Bool
        let scheduleTruthMutated: Bool
    }
}

struct MyDaySavePreviewV1: Equatable, Sendable {
    let successor: MyDayPlanV1
    let predecessor: MyDayPlanV1?
    let zeroWrite: Bool

    init(successor: MyDayPlanV1, predecessor: MyDayPlanV1?) throws {
        try successor.validate(predecessor: predecessor)
        self.successor = successor
        self.predecessor = predecessor
        zeroWrite = true
    }
}

struct MyDayCarryoverPreviewV1: Equatable, Sendable {
    let plan: MyDayCarryoverPlanV1
    let source: MyDayPlanV1
    let target: MyDayPlanV1
    let receipt: MyDayCarryoverReceiptV1
    let sourceSummary: MyDaySummaryProjectionV1
    let eligibleMembershipIDs: [UUID]
    let zeroWrite: Bool


    init(
        plan: MyDayCarryoverPlanV1,
        source: MyDayPlanV1,
        target: MyDayPlanV1,
        receipt: MyDayCarryoverReceiptV1,
        sourceSummary: MyDaySummaryProjectionV1
    ) throws {
        try receipt.validate(plan: plan, source: source, target: target)
        try sourceSummary.validate(plan: source)
        guard plan.membershipIDs.allSatisfy(
            sourceSummary.carryoverEligibleMembershipIDs.contains
        ) else {
            throw MyDayWorkflowFailureV1.carryoverIneligible
        }
        self.plan = plan
        self.source = source
        self.target = target
        self.receipt = receipt
        self.sourceSummary = sourceSummary
        eligibleMembershipIDs = sourceSummary.carryoverEligibleMembershipIDs
        zeroWrite = true
    }
}

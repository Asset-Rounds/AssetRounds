import Foundation
import XCTest

@testable import FieldEvidenceApp

final class V23MyDayPlanningProjectionTests: XCTestCase {
    @MainActor
    func testProjectDraftRetainsExactHistoricalReferenceWhenCurrentSourceIsChangedOrMissing() throws {
        let key = try Self.key()
        let historical = Self.reference(1)
        let membershipID = Self.id(101)
        let predecessor = try Self.plan(key: key, membershipID: membershipID,
                                        reference: historical)
        let retained = try Self.draftItem(membershipID, reference: historical, estimate: 45)

        let changedCurrent = Self.reference(1, revision: 2, digest: "b")
        let changedProjection = try MyDayWorkflowCoordinatorV1.projectDraft(
            key: key, selectedItems: [retained], eligibleReferences: [changedCurrent],
            predecessor: predecessor)
        XCTAssertEqual(changedProjection.items, [retained])
        XCTAssertEqual(changedProjection.eligibleReferences, [historical])

        let missingProjection = try MyDayWorkflowCoordinatorV1.projectDraft(
            key: key, selectedItems: [retained], eligibleReferences: [],
            predecessor: predecessor)
        XCTAssertEqual(missingProjection.items, [retained])
        XCTAssertEqual(missingProjection.eligibleReferences, [historical])

        let changedSelection = try Self.draftItem(membershipID, reference: changedCurrent, estimate: 45)
        XCTAssertThrowsError(try MyDayWorkflowCoordinatorV1.projectDraft(
            key: key, selectedItems: [changedSelection], eligibleReferences: [],
            predecessor: predecessor)) {
            XCTAssertEqual($0 as? MyDayWorkflowFailureV1, .ineligibleReference)
        }
        let newMembership = try Self.draftItem(Self.id(102), reference: historical)
        XCTAssertThrowsError(try MyDayWorkflowCoordinatorV1.projectDraft(
            key: key, selectedItems: [newMembership], eligibleReferences: [],
            predecessor: predecessor)) {
            XCTAssertEqual($0 as? MyDayWorkflowFailureV1, .ineligibleReference)
        }
    }

    @MainActor
    func testProjectDraftAcceptsOnlyEligibleWorkspaceValuesAndPreservesBoundedStableIDs() throws {
        let key = try Self.key()
        let values = try (0..<MyDayLimitsV1.maximumItems).map { index in
            try Self.draftItem(Self.id(1_000 + index), reference: Self.reference(2_000 + index),
                               estimate: index.isMultiple(of: 2) ? nil : 30)
        }
        let projected = try MyDayWorkflowCoordinatorV1.projectDraft(
            key: key, selectedItems: values, eligibleReferences: values.map(\.reference))
        XCTAssertEqual(projected.items, values)
        XCTAssertEqual(projected.items.map(\.membershipID), values.map(\.membershipID))
        XCTAssertEqual(projected.items.map(\.reference), values.map(\.reference))
        XCTAssertEqual(projected.items.map(\.estimate), values.map(\.estimate))

        let extra = try Self.draftItem(Self.id(9_999), reference: Self.reference(9_999))
        XCTAssertThrowsError(try MyDayWorkflowCoordinatorV1.projectDraft(
            key: key, selectedItems: values + [extra],
            eligibleReferences: (values + [extra]).map(\.reference))) {
            XCTAssertEqual($0 as? MyDayWorkflowFailureV1, .invalidManualOrder)
        }

        let unavailable = try Self.draftItem(Self.id(10_001), reference: Self.reference(10_001))
        XCTAssertThrowsError(try MyDayWorkflowCoordinatorV1.projectDraft(
            key: key, selectedItems: [unavailable], eligibleReferences: [])) {
            XCTAssertEqual($0 as? MyDayWorkflowFailureV1, .ineligibleReference)
        }
        let foreignReference = Self.reference(10_002, workspaceID: Self.otherWorkspace)
        let foreign = try Self.draftItem(Self.id(10_002), reference: foreignReference)
        XCTAssertThrowsError(try MyDayWorkflowCoordinatorV1.projectDraft(
            key: key, selectedItems: [foreign], eligibleReferences: [foreignReference])) {
            XCTAssertEqual($0 as? MyDayWorkflowFailureV1, .ineligibleReference)
        }
    }

    @MainActor
    func testProjectMoveMatchesAccessibleManualOrderAndPreservesItemValues() throws {
        let key = try Self.key()
        let first = try Self.draftItem(Self.id(201), reference: Self.reference(201))
        let second = try Self.draftItem(Self.id(202), reference: Self.reference(202), estimate: 20)
        let third = try Self.draftItem(Self.id(203), reference: Self.reference(203), estimate: 40)
        let draft = try MyDayWorkflowCoordinatorV1.projectDraft(
            key: key, selectedItems: [first, second, third],
            eligibleReferences: [first.reference, second.reference, third.reference])

        let movedByButton = try MyDayWorkflowCoordinatorV1.projectMove(
            draft, action: .up(membershipID: third.membershipID))
        let movedByIndex = try MyDayWorkflowCoordinatorV1.projectMove(
            draft, action: .toIndex(membershipID: third.membershipID, index: 1))
        XCTAssertEqual(movedByButton, movedByIndex)
        XCTAssertEqual(movedByButton.items, [first, third, second])
        XCTAssertEqual(movedByButton.eligibleReferences, draft.eligibleReferences)

        let movedDown = try MyDayWorkflowCoordinatorV1.projectMove(
            draft, action: .down(membershipID: first.membershipID))
        XCTAssertEqual(movedDown.items, [second, first, third])
        XCTAssertThrowsError(try MyDayWorkflowCoordinatorV1.projectMove(
            draft, action: .up(membershipID: first.membershipID))) {
            XCTAssertEqual($0 as? MyDayWorkflowFailureV1, .invalidManualOrder)
        }
    }

    @MainActor
    func testPrepareCarryoverMatchesExistingFullSummaryPreviewAndSamplesClockOnce() throws {
        let sourceKey = try Self.key("2026-09-11")
        let targetKey = try Self.key("2026-09-12")
        let first = try Self.planItem(Self.id(501), reference: Self.reference(501), estimate: 15)
        let second = try Self.planItem(Self.id(502), reference: Self.reference(502), estimate: 30,
                                       manualOrder: 1)
        let source = try Self.plan(key: sourceKey, items: [first, second],
                                   planID: Self.id(503), mutation: 504)
        let readiness = try Self.readiness(for: source, states: [.active, .paused])
        let summary = try MyDaySummaryProjectionV1(plan: source, readiness: readiness,
            dueQueue: Self.emptyDue(), exceptionQueue: Self.emptyExceptions())
        let clock = ProjectionCountingClock(Self.instant)
        let coordinator = MyDayWorkflowCoordinatorV1(
            canonical: .init(writer: ProjectionUnusedWriter(), sourceReader: ProjectionUnusedSources()),
            clock: clock)
        let mutation = try MutationIDV1(rawValue: Self.id(505))
        let preview = try coordinator.previewCarryover(source: source, sourceSummary: summary,
            targetKey: targetKey, targetPredecessor: nil,
            membershipIDs: [first.membershipID, second.membershipID],
            targetPlanID: Self.id(506), mutationID: mutation, actor: Self.actor())
        let prepared = try MyDayWorkflowCoordinatorV1.prepareCarryover(source: source,
            readiness: readiness, targetKey: targetKey, targetPredecessor: nil,
            membershipIDs: [first.membershipID, second.membershipID],
            targetPlanID: Self.id(506), mutationID: mutation, actor: Self.actor(),
            authoredAt: Self.instant)

        XCTAssertEqual(prepared, .carryover(plan: preview.plan, source: preview.source,
                                             target: preview.target, receipt: preview.receipt))
        XCTAssertEqual(clock.readCount, 1)
        XCTAssertEqual(source.items, [first, second])
    }

    @MainActor
    func testPrepareCarryoverPreservesSourceOrderIntoExistingTargetAndRejectsInvalidSelections() throws {
        let sourceKey = try Self.key("2026-09-11")
        let targetKey = try Self.key("2026-09-12")
        let first = try Self.planItem(Self.id(601), reference: Self.reference(601), estimate: 15)
        let terminal = try Self.planItem(Self.id(602), reference: Self.reference(602), estimate: 20,
                                          manualOrder: 1)
        let third = try Self.planItem(Self.id(603), reference: Self.reference(603), estimate: 45,
                                      manualOrder: 2)
        let source = try Self.plan(key: sourceKey, items: [first, terminal, third],
                                   planID: Self.id(604), mutation: 605)
        let readiness = try Self.readiness(for: source, states: [.active, .completed, .paused])
        let existing = try Self.planItem(Self.id(606), reference: Self.reference(606), estimate: 10)
        let predecessor = try Self.plan(key: targetKey, items: [existing],
                                        planID: Self.id(607), mutation: 608)
        let command = try MyDayWorkflowCoordinatorV1.prepareCarryover(source: source,
            readiness: readiness, targetKey: targetKey, targetPredecessor: predecessor,
            membershipIDs: [first.membershipID, third.membershipID],
            targetPlanID: predecessor.planID, mutationID: .init(rawValue: Self.id(609)),
            actor: Self.actor(), authoredAt: Self.instant)
        guard case let .carryover(plan, commandSource, target, receipt) = command else {
            return XCTFail("Expected carryover command")
        }
        XCTAssertEqual(commandSource, source)
        XCTAssertEqual(plan.membershipIDs, [first.membershipID, third.membershipID])
        XCTAssertEqual(target.items.map(\.membershipID),
                       [existing.membershipID, first.membershipID, third.membershipID])
        XCTAssertEqual(target.items.map(\.manualOrder), [0, 1, 2])
        XCTAssertEqual(target.items.map(\.estimate), [existing.estimate, first.estimate, third.estimate])
        XCTAssertEqual(receipt.targetPlan, try MyDayPlanReferenceV1(target))

        XCTAssertThrowsError(try MyDayWorkflowCoordinatorV1.prepareCarryover(source: source,
            readiness: readiness, targetKey: targetKey, targetPredecessor: predecessor,
            membershipIDs: [first.membershipID, first.membershipID],
            targetPlanID: predecessor.planID, mutationID: .init(rawValue: Self.id(610)),
            actor: Self.actor(), authoredAt: Self.instant)) {
            XCTAssertEqual($0 as? MyDayWorkflowFailureV1, .carryoverIneligible)
        }
        XCTAssertThrowsError(try MyDayWorkflowCoordinatorV1.prepareCarryover(source: source,
            readiness: readiness, targetKey: targetKey, targetPredecessor: predecessor,
            membershipIDs: [third.membershipID, first.membershipID],
            targetPlanID: predecessor.planID, mutationID: .init(rawValue: Self.id(611)),
            actor: Self.actor(), authoredAt: Self.instant)) {
            XCTAssertEqual($0 as? MyDayWorkflowFailureV1, .invalidManualOrder)
        }
        XCTAssertThrowsError(try MyDayWorkflowCoordinatorV1.prepareCarryover(source: source,
            readiness: readiness, targetKey: targetKey, targetPredecessor: predecessor,
            membershipIDs: [terminal.membershipID], targetPlanID: predecessor.planID,
            mutationID: .init(rawValue: Self.id(612)), actor: Self.actor(), authoredAt: Self.instant)) {
            XCTAssertEqual($0 as? MyDayWorkflowFailureV1, .carryoverIneligible)
        }
        XCTAssertThrowsError(try MyDayWorkflowCoordinatorV1.prepareCarryover(source: source,
            readiness: readiness, targetKey: Self.key("2026-09-12", workspaceID: Self.otherWorkspace),
            targetPredecessor: nil, membershipIDs: [first.membershipID],
            targetPlanID: Self.id(613), mutationID: .init(rawValue: Self.id(614)),
            actor: Self.actor(), authoredAt: Self.instant)) {
            XCTAssertEqual($0 as? MyDayWorkflowFailureV1, .carryoverIneligible)
        }
    }

    @MainActor
    func testPrepareCarryoverEnforcesFiftyItemTargetLimit() throws {
        let sourceKey = try Self.key("2026-09-11")
        let targetKey = try Self.key("2026-09-12")
        let first = try Self.planItem(Self.id(701), reference: Self.reference(701))
        let second = try Self.planItem(Self.id(702), reference: Self.reference(702), manualOrder: 1)
        let source = try Self.plan(key: sourceKey, items: [first, second],
                                   planID: Self.id(703), mutation: 704)
        let readiness = try Self.readiness(for: source, states: [.active, .active])
        let existing = try (0..<(MyDayLimitsV1.maximumItems - 1)).map { index in
            try Self.planItem(Self.id(800 + index), reference: Self.reference(800 + index),
                              manualOrder: index)
        }
        let predecessor = try Self.plan(key: targetKey, items: existing,
                                        planID: Self.id(750), mutation: 751)
        let accepted = try MyDayWorkflowCoordinatorV1.prepareCarryover(source: source,
            readiness: readiness, targetKey: targetKey, targetPredecessor: predecessor,
            membershipIDs: [first.membershipID], targetPlanID: predecessor.planID,
            mutationID: .init(rawValue: Self.id(752)), actor: Self.actor(), authoredAt: Self.instant)
        guard case let .carryover(_, _, target, _) = accepted else {
            return XCTFail("Expected carryover command")
        }
        XCTAssertEqual(target.items.count, MyDayLimitsV1.maximumItems)

        XCTAssertThrowsError(try MyDayWorkflowCoordinatorV1.prepareCarryover(source: source,
            readiness: readiness, targetKey: targetKey, targetPredecessor: predecessor,
            membershipIDs: [first.membershipID, second.membershipID],
            targetPlanID: predecessor.planID, mutationID: .init(rawValue: Self.id(753)),
            actor: Self.actor(), authoredAt: Self.instant)) {
            XCTAssertEqual($0 as? MyDayWorkflowFailureV1, .carryoverIneligible)
        }
    }

    @MainActor
    func testPrepareCarryoverRejectsStaleReadinessAndChangedCurrentReference() throws {
        let sourceKey = try Self.key("2026-09-11")
        let targetKey = try Self.key("2026-09-12")
        let item = try Self.planItem(Self.id(901), reference: Self.reference(901))
        let source = try Self.plan(key: sourceKey, items: [item],
                                   planID: Self.id(902), mutation: 903)
        let readiness = try Self.readiness(for: source, states: [.active])
        let successor = try MyDayPlanV1(planID: source.planID, key: source.key, items: source.items,
            predecessor: source, revision: 2, mutationID: .init(rawValue: Self.id(904)),
            authoredBy: Self.actor(), authoredAt: Self.instant)
        XCTAssertThrowsError(try MyDayWorkflowCoordinatorV1.prepareCarryover(source: successor,
            readiness: readiness, targetKey: targetKey, targetPredecessor: nil,
            membershipIDs: [item.membershipID], targetPlanID: Self.id(905),
            mutationID: .init(rawValue: Self.id(906)), actor: Self.actor(), authoredAt: Self.instant)) {
            XCTAssertEqual($0 as? MyDayFailureV1, .staleRevision)
        }

        let changed = Self.reference(901, revision: 2, digest: "c")
        let changedReadiness = try Self.readiness(for: source, states: [.active], current: [changed])
        XCTAssertFalse(MyDaySummaryItemV1.isCarryoverEligible(plannedReference: item.reference,
            currentReference: changed, state: .active))
        XCTAssertThrowsError(try MyDayWorkflowCoordinatorV1.prepareCarryover(source: source,
            readiness: changedReadiness, targetKey: targetKey, targetPredecessor: nil,
            membershipIDs: [item.membershipID], targetPlanID: Self.id(907),
            mutationID: .init(rawValue: Self.id(908)), actor: Self.actor(), authoredAt: Self.instant)) {
            XCTAssertEqual($0 as? MyDayWorkflowFailureV1, .carryoverIneligible)
        }

        let missingReadiness = try Self.readiness(for: source, states: [.missing], current: [nil])
        XCTAssertFalse(MyDaySummaryItemV1.isCarryoverEligible(plannedReference: item.reference,
            currentReference: nil, state: .missing))
        XCTAssertThrowsError(try MyDayWorkflowCoordinatorV1.prepareCarryover(source: source,
            readiness: missingReadiness, targetKey: targetKey, targetPredecessor: nil,
            membershipIDs: [item.membershipID], targetPlanID: Self.id(909),
            mutationID: .init(rawValue: Self.id(910)), actor: Self.actor(), authoredAt: Self.instant)) {
            XCTAssertEqual($0 as? MyDayWorkflowFailureV1, .carryoverIneligible)
        }
    }

    private static let workspace = WorkspaceID(rawValue: id(1))
    private static let otherWorkspace = WorkspaceID(rawValue: id(2))
    private static let instant = Date(timeIntervalSince1970: 1_789_084_800)

    private static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "73000000-0000-4000-8000-%012d", value))!
    }

    private static func key(_ day: String = "2026-09-12",
                            workspaceID: WorkspaceID = workspace) throws -> MyDayKeyV1 {
        try .init(workspaceID: workspaceID, civilDate: .init(day),
                  ianaTimeZoneIdentifier: "America/New_York")
    }

    private static func reference(_ value: Int, workspaceID: WorkspaceID = workspace,
                                  revision: UInt64 = 1,
                                  digest: Character = "a") -> MyDayEligibleReferenceV1 {
        .roundSession(workspaceID: workspaceID, sessionID: id(20_000 + value),
                      revision: revision, sessionSHA256: String(repeating: String(digest), count: 64))
    }

    private static func draftItem(_ membershipID: UUID, reference: MyDayEligibleReferenceV1,
                                  estimate: Int? = nil) throws -> MyDayDraftItemV1 {
        try .init(membershipID: membershipID, reference: reference,
                  estimate: try estimate.map { try MyDayEstimateV1(wholeMinutes: $0) })
    }

    private static func actor() throws -> ActorSnapshotV1 {
        let reference = try LocalActorReferenceV1(actorReferenceID: id(30_001),
            workspaceID: workspace, displayName: "Projection recorder")
        return try .init(snapshotID: id(30_002), workspaceID: workspace, actor: reference,
                         responsibility: .recordedBy,
                         displayNameAtTime: reference.displayName, capturedAt: instant)
    }

    private static func plan(key: MyDayKeyV1, membershipID: UUID,
                             reference: MyDayEligibleReferenceV1) throws -> MyDayPlanV1 {
        let item = try MyDayItemV1(membershipID: membershipID, reference: reference,
                                   manualOrder: 0, estimate: .init(wholeMinutes: 45))
        return try plan(key: key, items: [item], planID: id(40_001), mutation: 40_002)
    }

    private static func planItem(_ membershipID: UUID, reference: MyDayEligibleReferenceV1,
                                 estimate: Int? = nil, manualOrder: Int = 0) throws -> MyDayItemV1 {
        try .init(membershipID: membershipID, reference: reference, manualOrder: manualOrder,
                  estimate: try estimate.map { try MyDayEstimateV1(wholeMinutes: $0) })
    }

    private static func plan(key: MyDayKeyV1, items: [MyDayItemV1], planID: UUID,
                             mutation: Int) throws -> MyDayPlanV1 {
        try .init(planID: planID, key: key, items: items, predecessor: nil,
                  revision: 1, mutationID: .init(rawValue: id(mutation)),
                  authoredBy: actor(), authoredAt: instant)
    }

    private static func readiness(for plan: MyDayPlanV1, states: [MyDaySourceStateV1],
                                  current: [MyDayEligibleReferenceV1?]? = nil) throws
        -> MyDayReadinessProjectionV1 {
        XCTAssertEqual(states.count, plan.items.count)
        XCTAssertEqual(current?.count ?? plan.items.count, plan.items.count)
        let frontiers = try plan.items.enumerated().map { index, item in
            let currentReference: MyDayEligibleReferenceV1?
            if let current { currentReference = current[index] }
            else { currentReference = item.reference }
            return try MyDaySourceFrontierV1(membershipID: item.membershipID,
                plannedReference: item.reference,
                currentReference: currentReference,
                state: states[index], readiness: currentReference == nil ? .unavailable : .ready,
                dueAt: nil, evaluatedAt: instant)
        }
        return try .init(plan: plan, evaluatedAt: instant, frontiers: frontiers)
    }

    private static func emptyDue() throws -> OccurrenceDueQueueStateV1 {
        try DueQueueProjectionV1(workspaceID: workspace, evaluatedAt: instant,
                                 definitions: [], history: []).recurringRoundState()
    }

    private static func emptyExceptions() throws -> ExceptionQueueProjectionV1 {
        try .init(workspaceID: workspace,
            registry: .init(registeredKinds: ExceptionQueueSourceKindV1.allCases.sorted {
                $0.rawValue < $1.rawValue
            }), sources: [], evaluatedAt: instant, resolver: ProjectionEmptyExceptionResolver())
    }
}

private final class ProjectionCountingClock: ApplicationClock, @unchecked Sendable {
    private let lock = NSLock()
    private let instant: Date
    private var reads = 0
    init(_ instant: Date) { self.instant = instant }
    func now() -> Date { lock.withLock { reads += 1; return instant } }
    var readCount: Int { lock.withLock { reads } }
}

@MainActor private final class ProjectionUnusedWriter: MyDayWritingV1 {
    func currentPlan(for key: MyDayKeyV1) throws -> MyDayPlanV1? {
        throw MyDayFailureV1.invalidValue
    }
    func result(workspaceID: WorkspaceID, mutationID: MutationIDV1) throws -> MyDayCommandResultV1? {
        throw MyDayFailureV1.invalidValue
    }
    func commit(_ command: MyDayCommandV1) throws -> MyDayCommandResultV1 {
        throw MyDayFailureV1.invalidValue
    }
}

@MainActor private final class ProjectionUnusedSources: MyDaySourceFrontierReadingV1 {
    func sourceFrontiers(for plan: MyDayPlanV1,
                         evaluatedAt: Date) throws -> [MyDaySourceFrontierV1] {
        throw MyDayFailureV1.invalidValue
    }
}

private struct ProjectionEmptyExceptionResolver: ExceptionQueueCanonicalSourceResolvingV1 {
    func resolveExceptionQueueSource(workspaceID: WorkspaceID, kind: ExceptionQueueSourceKindV1,
        sourceID: String, revision: UInt64,
        evaluatedAt: Date) throws -> ExceptionQueueSourceSnapshotV1 {
        throw ReinspectionExceptionFailureV1.missingSource
    }
}

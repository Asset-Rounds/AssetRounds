import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

private struct C57MyDayCorpusV1: Decodable {
    let cardID: String
    let schema: String
    let schemaVersion: Int
    let evidenceIDs: [String]
    let selectors: [String]
    let workspaceID: String
    let civilDate: String
    let ianaTimeZoneIdentifier: String
    let maximumItems: Int
    let minimumEstimateMinutes: Int
    let maximumEstimateMinutes: Int
    let eligibleReferenceKinds: [String]
    let coveredReferenceKinds: [String]
    let sourceStates: [String]
    let readinessStates: [String]
    let temporalCases: TemporalCases
    let hostileCases: [String]
    let recoveryRules: [String]
    let canonicalRowKinds: [String]
    let persistentSchemaVersion: Int
    let recordsSchemaVersion: Int
    let lifecycle: Lifecycle
    let forbiddenEffects: [String]

    struct TemporalCases: Decodable {
        let preMidnightDate: String
        let dstGapDate: String
        let postDSTDate: String
        let zone: String
        let alternateZone: String
    }

    struct Lifecycle: Decodable {
        let readinessSourceStateDueNonpersistent: Bool
        let removalMutatesSource: Bool
        let automaticCarryover: Bool
        let dispatchesOrSchedules: Bool
        let storesActualDuration: Bool
        let replaceRestorePreservesExactPlans: Bool
        let configurationCloneOmitsPlans: Bool
        let workspaceForkRetainsNonactiveHistoryOnly: Bool
        let erasePurgesMyDayTruth: Bool
    }
}

@MainActor
private final class C57MyDaySourceProbe: MyDaySourceFrontierReadingV1 {
    var states: [UUID: MyDaySourceStateV1] = [:]
    var readiness: [UUID: MyDayReadinessV1] = [:]
    var currentReferences: [UUID: MyDayEligibleReferenceV1] = [:]

    func sourceFrontiers(
        for plan: MyDayPlanV1,
        evaluatedAt: Date
    ) throws -> [MyDaySourceFrontierV1] {
        try plan.items.map { item in
            let state = states[item.membershipID] ?? .active
            let current = state == .missing
                ? nil
                : (currentReferences[item.membershipID] ?? item.reference)
            let itemReadiness = current == nil
                ? .unavailable
                : (readiness[item.membershipID] ?? .ready)
            return try MyDaySourceFrontierV1(
                membershipID: item.membershipID,
                plannedReference: item.reference,
                currentReference: current,
                state: state,
                readiness: itemReadiness,
                dueAt: state == .missing ? nil : evaluatedAt.addingTimeInterval(3_600),
                evaluatedAt: evaluatedAt
            )
        }
    }
}

@MainActor
private final class C57MyDayWriterProbe: MyDayWritingV1 {
    var plans: [String: MyDayPlanV1] = [:]
    var results: [UUID: MyDayCommandResultV1] = [:]
    var commitCount = 0
    var failNextCommit = false

    func currentPlan(for key: MyDayKeyV1) throws -> MyDayPlanV1? {
        plans[key.stableKey]
    }

    func result(
        workspaceID: WorkspaceID,
        mutationID: MutationIDV1
    ) throws -> MyDayCommandResultV1? {
        guard let result = results[mutationID.rawValue] else { return nil }
        guard result.plan.key.workspaceID == workspaceID else {
            throw MyDayFailureV1.wrongWorkspace
        }
        return result
    }

    func commit(_ command: MyDayCommandV1) throws -> MyDayCommandResultV1 {
        commitCount += 1
        try command.validate()
        if failNextCommit {
            failNextCommit = false
            throw MyDayFailureV1.divergentMutation
        }

        let plan: MyDayPlanV1
        let carryoverReceipt: MyDayCarryoverReceiptV1?
        let committedAt: Date
        switch command {
        case .save(let successor, _):
            plan = successor
            carryoverReceipt = nil
            committedAt = successor.authoredAt
        case .carryover(_, _, let target, let receipt):
            plan = target
            carryoverReceipt = receipt
            committedAt = receipt.committedAt
        }

        let receipt = try MyDayMutationReceiptV1(
            command: command,
            resultingPlan: plan,
            carryoverReceipt: carryoverReceipt,
            disposition: .committed,
            committedAt: committedAt
        )
        let result = MyDayCommandResultV1(plan: plan, receipt: receipt)
        try result.validate()
        plans[plan.key.stableKey] = plan
        results[command.mutationID.rawValue] = result
        return result
    }
}

private enum C57MyDayTestSupport {
    static let workspace = WorkspaceID(rawValue: id(1))
    static let otherWorkspace = WorkspaceID(rawValue: id(2))
    static let instant = Date(timeIntervalSince1970: 1_801_000_000)

    static func id(_ seed: Int) -> UUID {
        UUID(uuidString: String(format: "c5700000-0000-4000-8000-%012x", seed))!
    }

    static func digest(_ value: Character) -> String {
        String(repeating: value, count: 64)
    }

    static func key(
        _ civilDate: String = "2026-08-30",
        zone: String = "America/New_York",
        workspaceID: WorkspaceID = C57MyDayTestSupport.workspace
    ) throws -> MyDayKeyV1 {
        try MyDayKeyV1(
            workspaceID: workspaceID,
            civilDate: try ScheduleLocalDateV1(civilDate),
            ianaTimeZoneIdentifier: zone
        )
    }

    static func actor(
        _ seed: Int,
        workspaceID: WorkspaceID,
        at: Date = instant
    ) throws -> ActorSnapshotV1 {
        let reference = try LocalActorReferenceV1(
            actorReferenceID: id(10_000 + seed),
            workspaceID: workspaceID,
            displayName: "C57 recorder"
        )
        return try ActorSnapshotV1(
            snapshotID: id(20_000 + seed),
            workspaceID: workspaceID,
            actor: reference,
            responsibility: .recordedBy,
            displayNameAtTime: reference.displayName,
            capturedAt: at
        )
    }

    static func roundReference(
        _ seed: Int,
        workspaceID: WorkspaceID = C57MyDayTestSupport.workspace,
        revision: UInt64 = 1,
        digestCharacter: Character = "a"
    ) -> MyDayEligibleReferenceV1 {
        .roundSession(
            workspaceID: workspaceID,
            sessionID: id(30_000 + seed),
            revision: revision,
            sessionSHA256: digest(digestCharacter)
        )
    }

    static func draftReference(
        _ seed: Int,
        workspaceID: WorkspaceID = C57MyDayTestSupport.workspace,
        revision: UInt64 = 1,
        digestCharacter: Character = "b"
    ) -> MyDayEligibleReferenceV1 {
        .resumableDraft(
            workspaceID: workspaceID,
            draftID: id(40_000 + seed),
            revision: revision,
            checkpointSHA256: digest(digestCharacter),
            anchor: try! DraftResumeAnchorV1(
                sectionID: "c57-section",
                fieldID: "c57-field",
                selectedStableID: "c57-selected",
                boundedPosition: 1
            )
        )
    }

    static func maximumReference(_ index: Int) -> MyDayEligibleReferenceV1 {
        switch index % 2 {
        case 0:
            return roundReference(
                1_000 + index,
                digestCharacter: index.isMultiple(of: 4) ? "d" : "e"
            )
        default:
            return draftReference(
                1_000 + index,
                digestCharacter: index.isMultiple(of: 3) ? "f" : "g"
            )
        }
    }

    static func workPacketReference(
        _ seed: Int,
        workspaceID: WorkspaceID = C57MyDayTestSupport.workspace,
        itemDigestCharacter: Character = "c"
    ) throws -> MyDayEligibleReferenceV1 {
        let creator = try actor(500 + seed, workspaceID: workspaceID)
        let item = try WorkPacketItemV1(
            itemID: "c57-item-\(seed)",
            kind: .inspection,
            expectedRevision: 1,
            itemSHA256: digest(itemDigestCharacter)
        )
        let manifest = try WorkPacketManifestV1(
            manifestID: id(50_000 + seed),
            packetID: id(60_000 + seed),
            packetVersion: 1,
            workspaceID: workspaceID,
            items: [item],
            packageReleases: [],
            creationBasis: .explicitLocalSelection,
            creator: creator,
            createdAt: instant
        )
        return .workPacket(try WorkPacketManifestReferenceV1(manifest))
    }

    static func item(
        _ seed: Int,
        reference: MyDayEligibleReferenceV1,
        order: Int,
        estimate: Int? = nil,
        membershipSeed: Int? = nil
    ) throws -> MyDayItemV1 {
        try MyDayItemV1(
            membershipID: id(membershipSeed ?? (70_000 + seed)),
            reference: reference,
            manualOrder: order,
            estimate: try estimate.map { try MyDayEstimateV1(wholeMinutes: $0) }
        )
    }

    static func plan(
        key: MyDayKeyV1,
        items: [MyDayItemV1],
        seed: Int,
        revision: UInt64 = 1,
        predecessor: MyDayPlanV1? = nil,
        authoredAt: Date = instant
    ) throws -> MyDayPlanV1 {
        try MyDayPlanV1(
            planID: id(80_000 + seed),
            key: key,
            items: items,
            predecessor: predecessor,
            revision: revision,
            mutationID: try MutationIDV1(rawValue: id(90_000 + seed)),
            authoredBy: try actor(seed, workspaceID: key.workspaceID, at: authoredAt),
            authoredAt: authoredAt
        )
    }

    static func expectedRevision(
        for plan: MyDayPlanV1,
        predecessor: MyDayPlanV1? = nil,
        workspaceRevision: UInt64 = 0
    ) throws -> WorkspaceExpectedRevisionV1 {
        try WorkspaceExpectedRevisionV1(
            workspaceID: plan.key.workspaceID,
            generationID: id(100_000),
            writerInstanceID: id(100_001),
            workspaceRevision: workspaceRevision,
            entityRevisions: [
                .init(
                    identity: try .init(kind: .myDayPlan, id: plan.planID),
                    revision: predecessor?.revision ?? 0
                )
            ]
        )
    }

    static func expectedCarryoverRevision(
        for plan: MyDayPlanV1,
        receiptID: UUID,
        workspaceRevision: UInt64 = 0
    ) throws -> WorkspaceExpectedRevisionV1 {
        try WorkspaceExpectedRevisionV1(
            workspaceID: plan.key.workspaceID,
            generationID: id(100_000),
            writerInstanceID: id(100_001),
            workspaceRevision: workspaceRevision,
            entityRevisions: [
                .init(identity: try .init(kind: .myDayPlan, id: plan.planID), revision: 0),
                .init(identity: try .init(kind: .myDayCarryoverReceipt, id: receiptID), revision: 0)
            ]
        )
    }
}

private func assertC57Failure(
    _ body: () throws -> Void,
    expected: MyDayFailureV1? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertThrowsError(try body(), file: file, line: line) { error in
        if let expected {
            XCTAssertEqual(error as? MyDayFailureV1, expected, file: file, line: line)
        }
    }
}

@MainActor
final class V9_65MyDayPlanTests: XCTestCase {
    private func corpus() throws -> C57MyDayCorpusV1 {
        let name = "V22P03C57MyDayPlanCorpusV1"
        let bundled = Bundle(for: V9_65MyDayPlanTests.self)
            .url(forResource: name, withExtension: "json", subdirectory: "Fixtures/V22/MyDay")
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V22/MyDay/\(name).json")
        let url = bundled ?? source
        return try JSONDecoder().decode(
            C57MyDayCorpusV1.self,
            from: Data(contentsOf: url)
        )
    }

    private func lifecycleContainer(_ name: String) throws -> ModelContainer {
        let schema = Schema(
            PersistentSchemaV42.models,
            version: PersistentSchemaV42.versionIdentifier
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                name,
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                cloudKitDatabase: .none
            )]
        )
    }

    func testV23P03C57G01GoldenPlanMembershipOrderEstimateAndReadiness() throws {
        let corpus = try corpus()
        XCTAssertEqual(corpus.cardID, "V23-P03-C57")
        XCTAssertEqual(corpus.schema, "V22P03C57MyDayPlanCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.evidenceIDs, [
            "V23-P03-C57-G01", "V23-P03-C57-A01", "V23-P03-C57-H01",
            "V23-P03-C57-I01", "V23-P03-C57-R01",
        ])
        XCTAssertEqual(corpus.selectors, ["G01", "A01", "H01", "I01", "R01"])
        XCTAssertEqual(corpus.maximumItems, MyDayLimitsV1.maximumItems)
        XCTAssertEqual(corpus.minimumEstimateMinutes, MyDayLimitsV1.minimumEstimateMinutes)
        XCTAssertEqual(corpus.maximumEstimateMinutes, MyDayLimitsV1.maximumEstimateMinutes)
        XCTAssertEqual(corpus.eligibleReferenceKinds, [
            "WORK_PACKET", "ROUND_SESSION", "SCHEDULE_OCCURRENCE", "RESUMABLE_DRAFT",
        ])
        XCTAssertTrue(corpus.coveredReferenceKinds.contains("WORK_PACKET"))
        XCTAssertTrue(corpus.coveredReferenceKinds.contains("ROUND_SESSION"))
        XCTAssertTrue(corpus.coveredReferenceKinds.contains("RESUMABLE_DRAFT"))
        XCTAssertEqual(corpus.sourceStates, MyDaySourceStateV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.readinessStates, MyDayReadinessV1.allCases.map(\.rawValue))

        let key = try C57MyDayTestSupport.key(
            corpus.civilDate,
            zone: corpus.ianaTimeZoneIdentifier
        )
        XCTAssertEqual(key.workspaceID.rawValue.uuidString.lowercased(), corpus.workspaceID)
        let references: [MyDayEligibleReferenceV1] = [
            try C57MyDayTestSupport.workPacketReference(1),
            C57MyDayTestSupport.roundReference(2),
            C57MyDayTestSupport.draftReference(3),
        ]
        let items = try references.enumerated().map { index, reference in
            try C57MyDayTestSupport.item(
                index,
                reference: reference,
                order: index,
                estimate: index == 0 ? corpus.minimumEstimateMinutes : (index == 1 ? 45 : nil)
            )
        }
        let plan = try C57MyDayTestSupport.plan(key: key, items: items, seed: 1)
        try plan.validate()
        XCTAssertEqual(plan.items.map(\.manualOrder), Array(0..<items.count))
        XCTAssertEqual(plan.items[0].estimate?.wholeMinutes, corpus.minimumEstimateMinutes)
        XCTAssertEqual(
            try MyDayEstimateV1(wholeMinutes: corpus.maximumEstimateMinutes).wholeMinutes,
            corpus.maximumEstimateMinutes
        )

        let maximumItems = try (0..<corpus.maximumItems).map { index in
            try C57MyDayTestSupport.item(
                index + 100,
                reference: C57MyDayTestSupport.maximumReference(index),
                order: index,
                estimate: index == corpus.maximumItems - 1
                    ? corpus.maximumEstimateMinutes
                    : nil,
                membershipSeed: 110_000 + index
            )
        }
        let maximumPlan = try C57MyDayTestSupport.plan(
            key: key,
            items: maximumItems,
            seed: 2
        )
        XCTAssertEqual(maximumPlan.items.count, corpus.maximumItems)
        try maximumPlan.validate()

        let sourceReader = C57MyDaySourceProbe()
        let writer = C57MyDayWriterProbe()
        let coordinator = MyDayCoordinatorV1(writer: writer, sourceReader: sourceReader)
        let readiness = try coordinator.readinessProjection(
            for: plan,
            evaluatedAt: C57MyDayTestSupport.instant
        )
        XCTAssertEqual(readiness.frontiers.map(\.membershipID), plan.items.map(\.membershipID))
        XCTAssertTrue(readiness.frontiers.allSatisfy { $0.state == .active && $0.readiness == .ready })

        let report = try C57MyDayReportProjectionRegistryV1.projection(
            plan: plan,
            readiness: readiness
        )
        try C57MyDayContractManifestBoundaryV1.validate(report)
        try C57MyDaySnapshotValidatorBoundaryV1.validate(
            report,
            plan: plan,
            readiness: readiness
        )
        let search = try C57MyDaySearchProjectionBoundaryV1.records(from: report)
        let envelope = try C57MyDaySearchPersistenceBoundaryV1.envelope(
            report: report,
            plan: plan,
            readiness: readiness
        )
        XCTAssertEqual(search.count, plan.items.count)
        XCTAssertEqual(envelope.records, search)
        XCTAssertEqual(envelope.lifecycle, C57MyDaySearchPersistenceEnvelopeV1.expectedLifecycle)

        let command = MyDayCommandV1.save(successor: plan, predecessor: nil)
        let mutation = try MyDayMutationV1(
            command: command,
            expectedRevision: C57MyDayTestSupport.expectedRevision(for: plan)
        )
        let request = try mutation.canonicalWorkspaceMutationRequest()
        XCTAssertEqual(request.mutationID, mutation.mutationID)
        XCTAssertEqual(WorkspaceCommandV1.applyMyDay(mutation).kind, .applyMyDay)
        XCTAssertEqual(try mutation.mutationPostImages.count, 1)

        let first = try coordinator.save(successor: plan, predecessor: nil)
        let second = try coordinator.save(successor: plan, predecessor: nil)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.receipt.disposition, .committed)
        XCTAssertEqual(writer.commitCount, 1)
        let replay = try MyDayCommandReplayResolutionV1.resolve(
            command: command,
            priorReceipt: first.receipt
        )
        XCTAssertEqual(replay.disposition, .idempotentReplay)
    }

    func testV23P03C57A01MidnightDSTZoneCarryoverAndSourceReconciliation() throws {
        let corpus = try corpus()
        let sourceKey = try C57MyDayTestSupport.key(
            corpus.temporalCases.preMidnightDate,
            zone: corpus.temporalCases.zone
        )
        let targetKey = try C57MyDayTestSupport.key(
            corpus.temporalCases.postDSTDate,
            zone: corpus.temporalCases.zone
        )
        let alternateKey = try C57MyDayTestSupport.key(
            corpus.temporalCases.dstGapDate,
            zone: corpus.temporalCases.alternateZone
        )
        XCTAssertNotEqual(sourceKey, targetKey)
        XCTAssertNotEqual(targetKey, alternateKey)
        XCTAssertEqual(sourceKey.ianaTimeZoneIdentifier, corpus.temporalCases.zone)
        XCTAssertEqual(alternateKey.ianaTimeZoneIdentifier, corpus.temporalCases.alternateZone)

        let sourceReferences: [MyDayEligibleReferenceV1] = [
            C57MyDayTestSupport.roundReference(11),
            C57MyDayTestSupport.draftReference(12),
        ]
        let sourceItems = try sourceReferences.enumerated().map { index, reference in
            try C57MyDayTestSupport.item(
                200 + index,
                reference: reference,
                order: index,
                estimate: index == 0 ? 20 : nil,
                membershipSeed: 120_000 + index
            )
        }
        let source = try C57MyDayTestSupport.plan(
            key: sourceKey,
            items: sourceItems,
            seed: 11
        )
        let targetItems = try source.items.map { item in
            try MyDayItemV1(
                membershipID: item.membershipID,
                reference: item.reference,
                manualOrder: item.manualOrder,
                estimate: item.estimate
            )
        }
        let target = try C57MyDayTestSupport.plan(
            key: targetKey,
            items: targetItems,
            seed: 12,
            authoredAt: C57MyDayTestSupport.instant.addingTimeInterval(1)
        )
        let carryoverPlan = try MyDayCarryoverPlanV1(
            sourcePlan: source,
            targetKey: targetKey,
            membershipIDs: source.items.map(\.membershipID)
        )
        XCTAssertEqual(carryoverPlan.selectedSourceItems, source.items)
        let carryoverReceipt = try MyDayCarryoverReceiptV1(
            plan: carryoverPlan,
            source: source,
            target: target,
            mutationID: target.mutationID,
            committedAt: C57MyDayTestSupport.instant.addingTimeInterval(2)
        )

        let sourceReader = C57MyDaySourceProbe()
        let writer = C57MyDayWriterProbe()
        writer.plans[source.key.stableKey] = source
        let coordinator = MyDayCoordinatorV1(writer: writer, sourceReader: sourceReader)
        let result = try coordinator.carryover(
            plan: carryoverPlan,
            source: source,
            target: target,
            receipt: carryoverReceipt
        )
        XCTAssertEqual(result.plan, target)
        XCTAssertEqual(result.receipt.carryoverReceiptSHA256, carryoverReceipt.receiptSHA256)
        XCTAssertEqual(writer.plans[source.key.stableKey], source)
        XCTAssertEqual(writer.commitCount, 1)

        sourceReader.states[source.items[0].membershipID] = .completed
        sourceReader.readiness[source.items[0].membershipID] = .notReady
        sourceReader.states[source.items[1].membershipID] = .reopened
        sourceReader.readiness[source.items[1].membershipID] = .ready
        let reconciled = try coordinator.readinessProjection(
            for: source,
            evaluatedAt: C57MyDayTestSupport.instant
        )
        XCTAssertEqual(reconciled.frontiers.map(\.state), [.completed, .reopened])
        XCTAssertEqual(reconciled.frontiers.map(\.readiness), [.notReady, .ready])

        sourceReader.states[source.items[0].membershipID] = .cancelled
        sourceReader.readiness[source.items[0].membershipID] = .blocked
        let cancelled = try coordinator.readinessProjection(
            for: source,
            evaluatedAt: C57MyDayTestSupport.instant
        )
        XCTAssertEqual(cancelled.frontiers[0].state, .cancelled)
        XCTAssertEqual(cancelled.frontiers[0].readiness, .blocked)

        sourceReader.states[source.items[1].membershipID] = .missing
        let missing = try coordinator.readinessProjection(
            for: source,
            evaluatedAt: C57MyDayTestSupport.instant
        )
        XCTAssertNil(missing.frontiers[1].currentReference)
        XCTAssertEqual(missing.frontiers[1].readiness, .unavailable)

        sourceReader.states[source.items[1].membershipID] = .retired
        sourceReader.readiness[source.items[1].membershipID] = .unavailable
        let retired = try coordinator.readinessProjection(
            for: source,
            evaluatedAt: C57MyDayTestSupport.instant
        )
        XCTAssertEqual(retired.frontiers[1].state, .retired)
        XCTAssertEqual(retired.frontiers[1].currentReference, source.items[1].reference)
        XCTAssertTrue(C57MyDayLifecycleBoundaryV1.automaticallyCarriesAcrossDateOrZone == false)
        XCTAssertTrue(C57MyDayLifecycleBoundaryV1.removalMutatesSourceWork == false)
    }

    func testV23P03C57H01HostileIdentityBoundsFrontierAndReplay() throws {
        let corpus = try corpus()
        let expectedHostiles = [
            "DUPLICATE_NATURAL_KEY", "CROSS_WORKSPACE_REFERENCE", "DUPLICATE_REFERENCE",
            "NONCONTIGUOUS_ORDER", "OVER_CAPACITY", "ESTIMATE_BELOW_MINIMUM",
            "ESTIMATE_ABOVE_MAXIMUM", "STALE_SOURCE_FRONTIER", "FORGED_SOURCE_DIGEST",
            "BAD_CARRYOVER_MEMBERSHIP", "CORRUPT_CANONICAL_BYTES", "DIVERGENT_MUTATION_REPLAY",
            "FOREIGN_EXPECTED_REVISION", "SCHEMA_40_MY_DAY_ROWS",
        ]
        XCTAssertEqual(Set(expectedHostiles), Set(corpus.hostileCases))

        let key = try C57MyDayTestSupport.key(corpus.civilDate, zone: corpus.ianaTimeZoneIdentifier)
        let firstReference = C57MyDayTestSupport.roundReference(21)
        let secondReference = C57MyDayTestSupport.draftReference(22)
        let firstItem = try C57MyDayTestSupport.item(21, reference: firstReference, order: 0, estimate: 30)
        let secondItem = try C57MyDayTestSupport.item(22, reference: secondReference, order: 1)
        let plan = try C57MyDayTestSupport.plan(key: key, items: [firstItem, secondItem], seed: 21)

        assertC57Failure({ _ = try MyDayEstimateV1(wholeMinutes: corpus.minimumEstimateMinutes - 1) }, expected: .limitExceeded)
        assertC57Failure({ _ = try MyDayEstimateV1(wholeMinutes: corpus.maximumEstimateMinutes + 1) }, expected: .limitExceeded)
        assertC57Failure({ _ = try MyDayEstimateV1(wholeMinutes: Int.max) }, expected: .limitExceeded)
        assertC57Failure({ _ = try MyDayItemV1(membershipID: C57MyDayTestSupport.id(130_001), reference: firstReference, manualOrder: corpus.maximumItems) }, expected: .limitExceeded)

        let duplicateItems = [
            try C57MyDayTestSupport.item(31, reference: firstReference, order: 0),
            try C57MyDayTestSupport.item(32, reference: firstReference, order: 1),
        ]
        assertC57Failure({ _ = try C57MyDayTestSupport.plan(key: key, items: duplicateItems, seed: 31) })

        let foreignItem = try C57MyDayTestSupport.item(
            33,
            reference: C57MyDayTestSupport.roundReference(33, workspaceID: C57MyDayTestSupport.otherWorkspace),
            order: 0
        )
        assertC57Failure({ _ = try C57MyDayTestSupport.plan(key: key, items: [foreignItem], seed: 33) })

        assertC57Failure({
            _ = try C57MyDayTestSupport.plan(
                key: key,
                items: [firstItem],
                seed: 34,
                revision: 2,
                predecessor: nil
            )
        })
        assertC57Failure({
            _ = try C57MyDayTestSupport.plan(
                key: key,
                items: [firstItem],
                seed: 35,
                revision: UInt64.max,
                predecessor: nil
            )
        })

        assertC57Failure({
            _ = try MyDaySourceFrontierV1(
                membershipID: firstItem.membershipID,
                plannedReference: firstReference,
                currentReference: firstReference,
                state: .missing,
                readiness: .unavailable,
                dueAt: C57MyDayTestSupport.instant,
                evaluatedAt: C57MyDayTestSupport.instant
            )
        })

        let staleReader = C57MyDaySourceProbe()
        staleReader.currentReferences[firstItem.membershipID] = C57MyDayTestSupport.roundReference(
            21,
            revision: 2,
            digestCharacter: "z"
        )
        let staleCoordinator = MyDayCoordinatorV1(
            writer: C57MyDayWriterProbe(),
            sourceReader: staleReader
        )
        assertC57Failure({
            _ = try staleCoordinator.save(successor: plan, predecessor: nil)
        }, expected: .staleRevision)

        let duplicateWriter = C57MyDayWriterProbe()
        duplicateWriter.plans[key.stableKey] = plan
        let duplicateCoordinator = MyDayCoordinatorV1(
            writer: duplicateWriter,
            sourceReader: C57MyDaySourceProbe()
        )
        let alternate = try C57MyDayTestSupport.plan(key: key, items: plan.items, seed: 36)
        assertC57Failure({
            _ = try duplicateCoordinator.save(successor: alternate, predecessor: nil)
        }, expected: .staleRevision)

        assertC57Failure({
            _ = try MyDayCarryoverPlanV1(
                sourcePlan: plan,
                targetKey: try C57MyDayTestSupport.key("2026-08-31", zone: corpus.ianaTimeZoneIdentifier),
                membershipIDs: [C57MyDayTestSupport.id(199_999)]
            )
        }, expected: .invalidCarryover)

        let changedItem = try MyDayItemV1(
            membershipID: firstItem.membershipID,
            reference: firstItem.reference,
            manualOrder: firstItem.manualOrder,
            estimate: try MyDayEstimateV1(wholeMinutes: 31)
        )
        let divergentPlan = try MyDayPlanV1(
            planID: plan.planID,
            key: plan.key,
            items: [changedItem, secondItem],
            revision: plan.revision,
            mutationID: plan.mutationID,
            authoredBy: plan.authoredBy,
            authoredAt: plan.authoredAt
        )
        let command = MyDayCommandV1.save(successor: plan, predecessor: nil)
        let divergentCommand = MyDayCommandV1.save(successor: divergentPlan, predecessor: nil)
        let receipt = try MyDayMutationReceiptV1(
            command: command,
            resultingPlan: plan,
            disposition: .committed,
            committedAt: plan.authoredAt
        )
        XCTAssertNotEqual(try command.canonicalSHA256(), try divergentCommand.canonicalSHA256())
        assertC57Failure({
            _ = try MyDayCommandReplayResolutionV1.resolve(
                command: divergentCommand,
                priorReceipt: receipt
            )
        }, expected: .divergentMutation)

        let foreignExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: C57MyDayTestSupport.otherWorkspace,
            generationID: C57MyDayTestSupport.id(140_000),
            writerInstanceID: C57MyDayTestSupport.id(140_001),
            workspaceRevision: 0,
            entityRevisions: [
                .init(
                    identity: try .init(kind: .myDayPlan, id: plan.planID),
                    revision: 0
                )
            ]
        )
        assertC57Failure({
            _ = try MyDayMutationV1(
                command: command,
                expectedRevision: foreignExpected
            )
        })

        var bytes = try MyDayCanonicalCodecV1.data(plan)
        bytes[bytes.startIndex] = bytes[bytes.startIndex] ^ 0x01
        assertC57Failure({
            _ = try MyDayCanonicalCodecV1.decode(MyDayPlanV1.self, from: bytes)
        })

        let schema40 = V4BackupRecordsV1(
            assets: [], evidenceFiles: [], issues: [], packets: [],
            recordsSchemaVersion: 40, reports: [], sites: [], workflowRecords: [],
            myDayPlans: [plan]
        )
        assertC57Failure({ try C57MyDayBackupEnrollmentV1.validate(schema40) })
    }

    func testV23P03C57I01InterruptedMutationEffectBeforeReceiptAndRelaunch() throws {
        let corpus = try corpus()
        let key = try C57MyDayTestSupport.key(corpus.civilDate, zone: corpus.ianaTimeZoneIdentifier)
        let reference = C57MyDayTestSupport.roundReference(41)
        let item = try C57MyDayTestSupport.item(41, reference: reference, order: 0, estimate: 60)
        let plan = try C57MyDayTestSupport.plan(key: key, items: [item], seed: 41)
        let command = MyDayCommandV1.save(successor: plan, predecessor: nil)
        let mutation = try MyDayMutationV1(
            command: command,
            expectedRevision: C57MyDayTestSupport.expectedRevision(for: plan)
        )
        XCTAssertEqual(try mutation.affectedIdentities.count, 1)
        XCTAssertEqual(try mutation.concurrencyIdentities.count, 1)
        XCTAssertEqual(try mutation.mutationPostImages.count, 1)
        XCTAssertEqual(WorkspaceCommandV1.applyMyDay(mutation).kind, .applyMyDay)

        let planRow = try MyDayPlanRowV1(plan)
        XCTAssertEqual(try planRow.value(), plan)
        var corruptPlanRow = try MyDayPlanRowV1(plan)
        corruptPlanRow.revision = plan.revision + 1
        assertC57Failure({ _ = try corruptPlanRow.value() })

        let sourceReader = C57MyDaySourceProbe()
        let writer = C57MyDayWriterProbe()
        writer.failNextCommit = true
        let coordinator = MyDayCoordinatorV1(writer: writer, sourceReader: sourceReader)
        assertC57Failure({ _ = try coordinator.save(successor: plan, predecessor: nil) })
        XCTAssertTrue(writer.plans.isEmpty)
        XCTAssertTrue(writer.results.isEmpty)
        XCTAssertEqual(writer.commitCount, 1)

        let committed = try coordinator.save(successor: plan, predecessor: nil)
        let replay = try coordinator.save(successor: plan, predecessor: nil)
        XCTAssertEqual(committed, replay)
        XCTAssertEqual(writer.commitCount, 2)
        XCTAssertEqual(committed.receipt.committedAt, plan.authoredAt)

        let resultBytes = try MyDayCanonicalCodecV1.data(committed)
        let relaunched = try MyDayCanonicalCodecV1.decode(
            MyDayCommandResultV1.self,
            from: resultBytes
        )
        XCTAssertEqual(relaunched, committed)
        XCTAssertEqual(try MyDayCanonicalCodecV1.data(relaunched), resultBytes)

        let existing = try C57MyDayExistingSuiteFixtureV1.make()
        let carryoverRow = try MyDayCarryoverReceiptRowV1(existing.carryoverReceipt)
        XCTAssertEqual(try carryoverRow.value(), existing.carryoverReceipt)
        var corruptCarryoverRow = try MyDayCarryoverReceiptRowV1(existing.carryoverReceipt)
        corruptCarryoverRow.receiptSHA256 = C57MyDayTestSupport.digest("f")
        assertC57Failure({ _ = try corruptCarryoverRow.value() })

        for rule in corpus.recoveryRules {
            XCTAssertFalse(rule.isEmpty)
        }
        XCTAssertTrue(corpus.recoveryRules.contains("EFFECT_BEFORE_RECEIPT"))
        XCTAssertTrue(corpus.recoveryRules.contains("IDEMPOTENT_RETRY"))
        XCTAssertTrue(corpus.recoveryRules.contains("RELAUNCH_CANONICAL_DECODE"))
    }

    func testV23P03C57R01RestoreCloneForkEraseSearchAndReportClosure() throws {
        let corpus = try corpus()
        let existing = try C57MyDayExistingSuiteFixtureV1.make()
        let sourceSuccessor = try MyDayPlanV1(
            planID: existing.sourcePlan.planID,
            key: existing.sourcePlan.key,
            items: existing.sourcePlan.items,
            predecessor: existing.sourcePlan,
            revision: 2,
            mutationID: try MutationIDV1(
                rawValue: C57MyDayTestSupport.id(160_000)
            ),
            authoredBy: existing.sourcePlan.authoredBy,
            authoredAt: existing.sourcePlan.authoredAt.addingTimeInterval(1)
        )
        let nonactiveSource = try MyDayPlanReferenceV1(existing.sourcePlan)
        let snapshot = try MyDayBackupSnapshotV1(
            workspaceID: existing.workspaceID,
            plans: [existing.sourcePlan, sourceSuccessor, existing.targetPlan],
            carryoverReceipts: [existing.carryoverReceipt],
            nonactivePlanReferences: [nonactiveSource]
        )
        try snapshot.validate()
        let snapshotBytes = try MyDayCanonicalCodecV1.data(snapshot)
        let reopenedSnapshot = try MyDayCanonicalCodecV1.decode(
            MyDayBackupSnapshotV1.self,
            from: snapshotBytes
        )
        XCTAssertEqual(reopenedSnapshot, snapshot)

        let forkTargetReference: MyDayEligibleReferenceV1
        switch existing.sourcePlan.items[0].reference {
        case .roundSession(_, let sessionID, let revision, _):
            forkTargetReference = .roundSession(
                workspaceID: C57MyDayTestSupport.otherWorkspace,
                sessionID: sessionID,
                revision: revision + 1,
                sessionSHA256: C57MyDayTestSupport.digest("z")
            )
        default:
            throw MyDayFailureV1.invalidValue
        }
        let rebind = try MyDayRebindContextV1(
            sourceWorkspaceID: existing.workspaceID,
            targetWorkspaceID: C57MyDayTestSupport.otherWorkspace,
            operationID: C57MyDayTestSupport.id(150_000),
            targetReferences: [forkTargetReference]
        )
        let forked = try existing.sourcePlan.rebound(using: rebind, predecessor: nil)
        XCTAssertEqual(forked.key.workspaceID, C57MyDayTestSupport.otherWorkspace)
        XCTAssertEqual(forked.items[0].reference, forkTargetReference)
        XCTAssertNotEqual(forked.mutationID, existing.sourcePlan.mutationID)

        let replaceContainer = try lifecycleContainer("C57-Replace")
        let replaceAdapter = MyDayLifecycleAdapterV1(modelContext: replaceContainer.mainContext)
        try replaceAdapter.materializeRestoreStaging(
            snapshot,
            targetWorkspaceID: existing.workspaceID,
            disposition: .replaceExact,
            operationID: C57MyDayTestSupport.id(150_010),
            targetReferences: []
        )
        let replaced = try replaceAdapter.snapshotForBackup(
            workspaceID: existing.workspaceID,
            nonactivePlanReferences: [nonactiveSource]
        )
        XCTAssertEqual(replaced, snapshot)

        let cloneContainer = try lifecycleContainer("C57-Clone")
        let cloneAdapter = MyDayLifecycleAdapterV1(modelContext: cloneContainer.mainContext)
        try cloneAdapter.materializeRestoreStaging(
            snapshot,
            targetWorkspaceID: existing.workspaceID,
            disposition: .configurationCloneOmit,
            operationID: C57MyDayTestSupport.id(150_011),
            targetReferences: []
        )
        let cloned = try cloneAdapter.snapshotForBackup(
            workspaceID: existing.workspaceID,
            nonactivePlanReferences: []
        )
        XCTAssertTrue(cloned.plans.isEmpty)
        XCTAssertTrue(cloned.carryoverReceipts.isEmpty)

        let forkContainer = try lifecycleContainer("C57-Fork")
        let forkAdapter = MyDayLifecycleAdapterV1(modelContext: forkContainer.mainContext)
        try forkAdapter.materializeRestoreStaging(
            snapshot,
            targetWorkspaceID: C57MyDayTestSupport.otherWorkspace,
            disposition: .workspaceForkNonactiveHistory,
            operationID: C57MyDayTestSupport.id(150_012),
            targetReferences: [forkTargetReference]
        )
        let forkedSnapshot = try forkAdapter.snapshotForBackup(
            workspaceID: C57MyDayTestSupport.otherWorkspace,
            nonactivePlanReferences: [try MyDayPlanReferenceV1(forked)]
        )
        XCTAssertEqual(forkedSnapshot.plans, [forked])
        XCTAssertTrue(forkedSnapshot.carryoverReceipts.isEmpty)
        try forkAdapter.erase(workspaceID: C57MyDayTestSupport.otherWorkspace)
        let erasedSnapshot = try forkAdapter.snapshotForBackup(
            workspaceID: C57MyDayTestSupport.otherWorkspace,
            nonactivePlanReferences: []
        )
        XCTAssertTrue(erasedSnapshot.plans.isEmpty)
        XCTAssertTrue(erasedSnapshot.carryoverReceipts.isEmpty)

        let records = V4BackupRecordsV1(
            assets: [], evidenceFiles: [], issues: [], packets: [],
            recordsSchemaVersion: corpus.recordsSchemaVersion,
            reports: [], sites: [], workflowRecords: [],
            myDayPlans: snapshot.plans,
            myDayCarryoverReceipts: snapshot.carryoverReceipts,
            nonactivePlanReferences: [nonactiveSource]
        )
        try C57MyDayBackupEnrollmentV1.validate(records)
        try C57MyDayKernelBackupRestoreEnrollmentV1.validate()
        XCTAssertEqual(corpus.canonicalRowKinds, C57MyDayBackupEnrollmentV1.canonicalRowKinds)
        XCTAssertEqual(corpus.persistentSchemaVersion, C57MyDayPersistentLifecycleBoundaryV1.persistentSchemaVersion)
        XCTAssertEqual(corpus.recordsSchemaVersion, C57MyDayPersistentLifecycleBoundaryV1.recordsSchemaVersion)
        XCTAssertEqual(PersistentSchemaV42.models.count, PersistentSchemaV41.models.count + 2)
        let modelNames = PersistentSchemaV42.models.map { String(describing: $0) }
        XCTAssertTrue(modelNames.contains { $0.contains("MyDayPlanRowV1") })
        XCTAssertTrue(modelNames.contains { $0.contains("MyDayCarryoverReceiptRowV1") })

        let duplicateRecords = V4BackupRecordsV1(
            assets: [], evidenceFiles: [], issues: [], packets: [],
            recordsSchemaVersion: corpus.recordsSchemaVersion,
            reports: [], sites: [], workflowRecords: [],
            myDayPlans: [existing.sourcePlan, existing.sourcePlan]
        )
        assertC57Failure({ try C57MyDayBackupEnrollmentV1.validate(duplicateRecords) })

        assertC57Failure({
            _ = try MyDayRebindContextV1(
                sourceWorkspaceID: existing.workspaceID,
                targetWorkspaceID: C57MyDayTestSupport.otherWorkspace,
                operationID: C57MyDayTestSupport.id(150_001),
                targetReferences: []
            ).reference(rebinding: existing.sourcePlan.items[0].reference)
        }, expected: .missingSource)

        let reader = C57MyDaySourceProbe()
        let coordinator = MyDayCoordinatorV1(
            writer: C57MyDayWriterProbe(),
            sourceReader: reader
        )
        let readiness = try coordinator.readinessProjection(
            for: existing.sourcePlan,
            evaluatedAt: C57MyDayTestSupport.instant
        )
        let report = try C57MyDayReportProjectionRegistryV1.projection(
            plan: existing.sourcePlan,
            readiness: readiness
        )
        let searchBytes = try C57MyDaySearchPersistenceBoundaryV1.encode(
            report: report,
            plan: existing.sourcePlan,
            readiness: readiness
        )
        XCTAssertFalse(searchBytes.isEmpty)
        let searchRecords = try C57MyDaySearchRebuildBoundaryV1.records(
            plans: [existing.sourcePlan],
            readiness: [readiness]
        )
        XCTAssertEqual(searchRecords.count, existing.sourcePlan.items.count)
        XCTAssertEqual(
            try C57MyDayOpenJSONRendererV1.reopen(
                C57MyDayOpenJSONRendererV1.render(
                    report,
                    plan: existing.sourcePlan,
                    readiness: readiness
                )
            ).itemCount,
            existing.sourcePlan.items.count
        )
        try C57MyDaySnapshotValidatorBoundaryV1.validate(
            report,
            plan: existing.sourcePlan,
            readiness: readiness
        )

        XCTAssertTrue(C57MyDayPersistentLifecycleBoundaryV1.replaceIsExact)
        XCTAssertTrue(C57MyDayPersistentLifecycleBoundaryV1.cloneOmitsPlans)
        XCTAssertTrue(C57MyDayPersistentLifecycleBoundaryV1.forkRetainsNonactiveHistoryOnly)
        XCTAssertTrue(C57MyDayPersistentLifecycleBoundaryV1.eraseRemovesWorkspaceRows)
        XCTAssertTrue(C57MyDayCoordinatorLifecycleBoundaryV1.lifecycleIsInfrastructureOwned)
        XCTAssertEqual(C57MyDayCoordinatorLifecycleBoundaryV1.applicationLifecycleCommandCount, 0)
        XCTAssertEqual(C57MyDayCoordinatorLifecycleBoundaryV1.sourceMutationCount, 0)
        XCTAssertEqual(C57MyDayCoordinatorLifecycleBoundaryV1.storedDerivedProjectionCount, 0)
        XCTAssertEqual(MyDayRestoreDispositionV1.allCases.map(\.rawValue), [
            MyDayRestoreDispositionV1.replaceExact.rawValue,
            MyDayRestoreDispositionV1.configurationCloneOmit.rawValue,
            MyDayRestoreDispositionV1.workspaceForkNonactiveHistory.rawValue,
        ])
        XCTAssertTrue(corpus.lifecycle.readinessSourceStateDueNonpersistent)
        XCTAssertFalse(corpus.lifecycle.removalMutatesSource)
        XCTAssertFalse(corpus.lifecycle.automaticCarryover)
        XCTAssertFalse(corpus.lifecycle.dispatchesOrSchedules)
        XCTAssertFalse(corpus.lifecycle.storesActualDuration)
        XCTAssertTrue(corpus.lifecycle.replaceRestorePreservesExactPlans)
        XCTAssertTrue(corpus.lifecycle.configurationCloneOmitsPlans)
        XCTAssertTrue(corpus.lifecycle.workspaceForkRetainsNonactiveHistoryOnly)
        XCTAssertTrue(corpus.lifecycle.erasePurgesMyDayTruth)
        XCTAssertEqual(corpus.forbiddenEffects, [
            "AUTO_SCHEDULING", "ROUTE_OPTIMIZATION", "DUE_DATE_MUTATION",
            "DISPATCH", "NOTIFICATION_DELIVERY", "SECOND_WORK_LEDGER",
        ])
        XCTAssertTrue(C57MyDayReportProjectionBoundaryV1.projectionCannotBeUsedAsWriterInput)
    }
}

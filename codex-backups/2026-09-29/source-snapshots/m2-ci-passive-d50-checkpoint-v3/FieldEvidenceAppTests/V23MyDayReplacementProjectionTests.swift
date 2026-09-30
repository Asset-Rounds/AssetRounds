import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class V23MyDayReplacementProjectionTests: XCTestCase {
    private typealias Projector = MyDayReplacementValueProjectionV1

    func testReplacementCommandsRetainEverySavePredecessorAndExistingTargetCarryover() throws {
        let fixture = try Fixture.make()
        let result = try MyDayReplacementCommandProjectionV1.project(.init(snapshot: fixture.snapshot), bindings: fixture.validBindings())
        let carryoverPlan = try MyDayCarryoverPlanV1(sourcePlan: fixture.sourcePlanRevisionTwo,
            targetKey: fixture.targetPlanRevisionTwo.key,
            membershipIDs: fixture.snapshot.carryoverReceipts[0].carriedMembershipIDs,
            expectedTargetPlan: fixture.targetPlanRevisionOne)
        let originals: [MyDayCommandV1] = [
            .save(successor: fixture.sourcePlanRevisionOne, predecessor: nil),
            .save(successor: fixture.sourcePlanRevisionTwo, predecessor: fixture.sourcePlanRevisionOne),
            .save(successor: fixture.targetPlanRevisionOne, predecessor: nil),
            .carryover(plan: carryoverPlan, source: fixture.sourcePlanRevisionTwo,
                target: fixture.targetPlanRevisionTwo, receipt: fixture.snapshot.carryoverReceipts[0])
        ]
        XCTAssertEqual(Set(result.commands.map(\.source)), Set(originals))
        XCTAssertEqual(result.commands.count, 4)
        for original in originals {
            let command = try result.targetCommand(for: original)
            let sourceMutation = try MyDayMutationV1(command: original, expectedRevision: commandExpected(original))
            let expected = try commandExpected(command)
            let target = try result.targetMutation(for: sourceMutation, expectedRevision: expected)
            XCTAssertEqual(target.command, command)
            XCTAssertEqual(target.expectedRevision, expected)
            XCTAssertEqual(target.workspaceID, fixture.targetWorkspaceID)
            XCTAssertNotEqual(target.mutationID, sourceMutation.mutationID)
            XCTAssertEqual(try target.concurrencyIdentities, expected.entityRevisions.map(\.identity))
            try target.validate()
            guard let projected = result.values.plans.first(where: { $0.source == sourceMutation.resultingPlan }) else {
                return XCTFail("Missing exact projected original plan")
            }
            XCTAssertEqual(target.resultingPlan, projected.target)
            switch target.command {
            case let .save(successor, predecessor):
                XCTAssertEqual(predecessor?.revision, successor.revision == 1 ? nil : successor.revision - 1)
                XCTAssertEqual(predecessor?.planSHA256, successor.predecessorPlanSHA256)
            case let .carryover(plan, source, targetPlan, receipt):
                XCTAssertEqual(plan.expectedTargetPlan?.revision, 1)
                XCTAssertEqual(plan.expectedTargetPlan?.planSHA256, targetPlan.predecessorPlanSHA256)
                XCTAssertEqual(plan.sourcePlan, try MyDayPlanReferenceV1(source))
                XCTAssertEqual(receipt.targetPlan, try MyDayPlanReferenceV1(targetPlan))
                XCTAssertEqual(receipt.committedAt, fixture.snapshot.carryoverReceipts[0].committedAt)
                XCTAssertEqual(expected.entityRevisions.count, 3)
                XCTAssertEqual(expected.entityRevisions.first(where: { $0.identity.kind == .myDayCarryoverReceipt })?.identity.id,
                               target.mutationID.rawValue)
            }
        }
    }

    func testReplacementCommandsRejectAlteredOriginalAndForeignOrIncompleteExpectedRevision() throws {
        let fixture = try Fixture.make()
        let result = try MyDayReplacementCommandProjectionV1.project(.init(snapshot: fixture.snapshot), bindings: fixture.validBindings())
        let original = MyDayCommandV1.save(successor: fixture.sourcePlanRevisionOne, predecessor: nil)
        let mutation = try MyDayMutationV1(command: original, expectedRevision: commandExpected(original))
        let target = try result.targetCommand(for: original)
        XCTAssertThrowsError(try result.targetMutation(for: mutation, expectedRevision: commandExpected(original)))
        let validExpected = try commandExpected(target)
        let emptyExpected = try WorkspaceExpectedRevisionV1(workspaceID: fixture.targetWorkspaceID,
            generationID: validExpected.generationID, writerInstanceID: validExpected.writerInstanceID,
            workspaceRevision: validExpected.workspaceRevision, entityRevisions: [])
        XCTAssertThrowsError(try result.targetMutation(for: mutation, expectedRevision: emptyExpected))
        let targetEntity = try XCTUnwrap(validExpected.entityRevisions.first)
        let wrongRevision = try WorkspaceExpectedRevisionV1(workspaceID: fixture.targetWorkspaceID,
            generationID: validExpected.generationID, writerInstanceID: validExpected.writerInstanceID,
            workspaceRevision: validExpected.workspaceRevision,
            entityRevisions: [.init(identity: targetEntity.identity, revision: targetEntity.revision + 1)])
        XCTAssertThrowsError(try result.targetMutation(for: mutation, expectedRevision: wrongRevision))
        let extraEntity = try WorkspaceEntityRevisionV1(identity: .init(kind: .myDayPlan,
            id: Fixture.id(98_114)), revision: 0)
        let extraExpected = try WorkspaceExpectedRevisionV1(workspaceID: fixture.targetWorkspaceID,
            generationID: validExpected.generationID, writerInstanceID: validExpected.writerInstanceID,
            workspaceRevision: validExpected.workspaceRevision,
            entityRevisions: (validExpected.entityRevisions + [extraEntity]).sorted {
                $0.identity.stableKey < $1.identity.stableKey
            })
        XCTAssertThrowsError(try result.targetMutation(for: mutation, expectedRevision: extraExpected))
        let base = fixture.sourcePlanRevisionOne
        let altered = try Fixture.plan(planID: base.planID, key: base.key, items: base.items,
            revision: base.revision, mutationID: base.mutationID, actor: base.authoredBy,
            authoredAt: base.authoredAt.addingTimeInterval(1))
        let changed = MyDayCommandV1.save(successor: altered, predecessor: nil)
        try changed.validate()
        XCTAssertEqual(changed.mutationID, original.mutationID)
        XCTAssertNotEqual(changed, original)
        XCTAssertThrowsError(try result.targetCommand(for: changed))
        let unknown = try Fixture.plan(planID: base.planID, key: base.key, items: base.items,
            revision: base.revision, mutationID: Fixture.mutation(98_111), actor: base.authoredBy,
            authoredAt: base.authoredAt)
        XCTAssertThrowsError(try result.targetCommand(for: .save(successor: unknown, predecessor: nil)))
        XCTAssertThrowsError(try result.targetCommand(for: target))
    }

    func testReplacementCommandsPreserveSameWorkspaceBytesAndEmptyProjection() throws {
        let fixture = try Fixture.make()
        let result = try MyDayReplacementCommandProjectionV1.project(.init(snapshot: fixture.snapshot),
            bindings: .init(targetWorkspaceID: fixture.sourceWorkspaceID))
        XCTAssertEqual(result.commands.count, 4)
        for pair in result.commands {
            XCTAssertEqual(try MyDayCanonicalCodecV1.data(pair.source), try MyDayCanonicalCodecV1.data(pair.target))
            let original = try MyDayMutationV1(command: pair.source, expectedRevision: commandExpected(pair.source))
            XCTAssertEqual(try result.targetMutation(for: original, expectedRevision: original.expectedRevision), original)
        }
        let empty = try MyDayBackupSnapshotV1(workspaceID: fixture.sourceWorkspaceID, plans: [],
            carryoverReceipts: [], nonactivePlanReferences: [])
        let projected = try MyDayReplacementCommandProjectionV1.project(.init(snapshot: empty),
            bindings: .init(targetWorkspaceID: fixture.targetWorkspaceID))
        XCTAssertTrue(projected.commands.isEmpty)
        XCTAssertEqual(projected.values.targetSnapshot.workspaceID, fixture.targetWorkspaceID)
    }

    private func commandExpected(_ command: MyDayCommandV1) throws -> WorkspaceExpectedRevisionV1 {
        var entities: [WorkspaceEntityRevisionV1]
        switch command {
        case let .save(successor, _):
            entities = [try .init(identity: .init(kind: .myDayPlan, id: successor.planID), revision: successor.revision - 1)]
        case let .carryover(_, source, target, _):
            entities = [
                try .init(identity: .init(kind: .myDayPlan, id: source.planID), revision: source.revision),
                try .init(identity: .init(kind: .myDayPlan, id: target.planID), revision: target.revision - 1),
                try .init(identity: .init(kind: .myDayCarryoverReceipt, id: target.mutationID.rawValue), revision: 0)
            ]
        }
        entities.sort { $0.identity.stableKey < $1.identity.stableKey }
        return try .init(workspaceID: command.workspaceID, generationID: Fixture.id(98_112),
            writerInstanceID: Fixture.id(98_113), workspaceRevision: 10, entityRevisions: entities)
    }


    @MainActor
    func testReplacementLifecyclePreparationUsesCompleteProjectedHistory() throws {
        let fixture = try Fixture.make()
        let bindings = try fixture.validBindings()
        let expected = try Projector.project(.init(snapshot: fixture.snapshot), bindings: bindings)
        let actual = try MyDayLifecycleAdapterV1.preparedRestoreSnapshot(
            fixture.snapshot, targetWorkspaceID: fixture.targetWorkspaceID,
            disposition: .replaceExact, operationID: Fixture.id(990),
            replacementBindings: bindings
        )
        XCTAssertEqual(actual, expected.targetSnapshot)
        XCTAssertEqual(actual.plans.count, fixture.snapshot.plans.count)
        XCTAssertEqual(actual.carryoverReceipts.count, fixture.snapshot.carryoverReceipts.count)
        XCTAssertEqual(try MyDayCanonicalCodecV1.data(actual), try MyDayCanonicalCodecV1.data(expected.targetSnapshot))
        XCTAssertThrowsError(try MyDayLifecycleAdapterV1.preparedRestoreSnapshot(
            fixture.snapshot, targetWorkspaceID: fixture.targetWorkspaceID,
            disposition: .replaceExact, operationID: Fixture.id(990)
        )) {
            XCTAssertEqual($0 as? MyDayFailureV1, .wrongWorkspace)
        }
        XCTAssertThrowsError(try MyDayLifecycleAdapterV1.preparedRestoreSnapshot(
            fixture.snapshot, targetWorkspaceID: Fixture.workspace(999),
            disposition: .replaceExact, operationID: Fixture.id(990),
            replacementBindings: bindings
        )) {
            XCTAssertEqual($0 as? MyDayFailureV1, .wrongWorkspace)
        }
        let incomplete = MyDayReplacementValueProjectionV1.Bindings(
            targetWorkspaceID: fixture.targetWorkspaceID,
            eligibleReferences: bindings.eligibleReferences,
            mutationIDs: Array(bindings.mutationIDs.dropLast())
        )
        XCTAssertThrowsError(try MyDayLifecycleAdapterV1.preparedRestoreSnapshot(
            fixture.snapshot, targetWorkspaceID: fixture.targetWorkspaceID,
            disposition: .replaceExact, operationID: Fixture.id(990),
            replacementBindings: incomplete
        )) {
            XCTAssertEqual($0 as? MyDayReplacementValueProjectionFailureV1, .invalidBinding)
        }
    }

    @MainActor
    func testReplacementLifecyclePreservesSameWorkspaceAndEmptyTargetSemantics() throws {
        let fixture = try Fixture.make()
        let same = try MyDayLifecycleAdapterV1.preparedRestoreSnapshot(
            fixture.snapshot, targetWorkspaceID: fixture.sourceWorkspaceID,
            disposition: .replaceExact, operationID: Fixture.id(991)
        )
        XCTAssertEqual(try MyDayCanonicalCodecV1.data(same), try MyDayCanonicalCodecV1.data(fixture.snapshot))
        let empty = try MyDayBackupSnapshotV1(
            workspaceID: fixture.sourceWorkspaceID, plans: [],
            carryoverReceipts: [], nonactivePlanReferences: []
        )
        let target = try MyDayLifecycleAdapterV1.preparedRestoreSnapshot(
            empty, targetWorkspaceID: fixture.targetWorkspaceID,
            disposition: .replaceExact, operationID: Fixture.id(991)
        )
        XCTAssertEqual(target.workspaceID, fixture.targetWorkspaceID)
        XCTAssertTrue(target.plans.isEmpty)
        XCTAssertTrue(target.carryoverReceipts.isEmpty)
        XCTAssertThrowsError(try MyDayLifecycleAdapterV1.preparedRestoreSnapshot(
            fixture.snapshot, targetWorkspaceID: fixture.sourceWorkspaceID,
            disposition: .replaceExact, operationID: Fixture.id(991),
            replacementBindings: MyDayReplacementValueProjectionV1.Bindings(
                targetWorkspaceID: fixture.sourceWorkspaceID
            )
        )) {
            XCTAssertEqual($0 as? MyDayFailureV1, .invalidValue)
        }
        for disposition in [MyDayRestoreDispositionV1.configurationCloneOmit, .workspaceForkNonactiveHistory] {
            XCTAssertThrowsError(try MyDayLifecycleAdapterV1.preparedRestoreSnapshot(
                fixture.snapshot, targetWorkspaceID: fixture.targetWorkspaceID,
                disposition: disposition, operationID: Fixture.id(991),
                replacementBindings: fixture.validBindings()
            )) {
                XCTAssertEqual($0 as? MyDayFailureV1, .invalidValue)
            }
        }
    }

    @MainActor
    func testCrossWorkspaceMaterializationPersistsExactProjectionAndRejectionsHaveNoEffect() throws {
        let fixture = try Fixture.make()
        let bindings = try fixture.validBindings()
        let expected = try Projector.project(
            .init(snapshot: fixture.snapshot), bindings: bindings
        ).targetSnapshot
        // MyDayPlanRowV1.rowID is store-global (planID|revision) and the
        // projection preserves planIDs, so the replaced source plans cannot
        // coexist in one store with their own target projection. The seeded
        // source-workspace rows therefore use distinct plan identities; any
        // write, erase or rewrite of source-workspace rows fails the checks.
        let bystander = try fixture.sourceWorkspaceBystanderSnapshot()
        let bystanderBytes = try MyDayCanonicalCodecV1.data(bystander)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V23-C57-replacement-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = root.appendingPathComponent("model.sqlite")

        do {
            let container = try Self.materializationContainer(storeURL: storeURL)
            let context = container.mainContext
            context.autosaveEnabled = false
            let adapter = MyDayLifecycleAdapterV1(modelContext: context)
            try adapter.materializeRestoreStaging(
                bystander, targetWorkspaceID: fixture.sourceWorkspaceID,
                disposition: .replaceExact, operationID: Fixture.id(995)
            )
            try assertSourceBystanderUnchanged(
                adapter, context: context, fixture: fixture, bystander: bystander,
                bystanderBytes: bystanderBytes, projectedPlanRows: 0, projectedReceiptRows: 0
            )

            let incomplete = MyDayReplacementValueProjectionV1.Bindings(
                targetWorkspaceID: fixture.targetWorkspaceID,
                eligibleReferences: Array(bindings.eligibleReferences.dropLast()),
                mutationIDs: bindings.mutationIDs
            )
            let foreignTarget = MyDayReplacementValueProjectionV1.Bindings(
                targetWorkspaceID: Fixture.workspace(998),
                eligibleReferences: bindings.eligibleReferences,
                mutationIDs: bindings.mutationIDs
            )
            XCTAssertThrowsError(try adapter.materializeRestoreStaging(
                fixture.snapshot, targetWorkspaceID: fixture.targetWorkspaceID,
                disposition: .replaceExact, operationID: Fixture.id(992)
            )) {
                XCTAssertEqual($0 as? MyDayFailureV1, .wrongWorkspace)
            }
            XCTAssertThrowsError(try adapter.materializeRestoreStaging(
                fixture.snapshot, targetWorkspaceID: fixture.targetWorkspaceID,
                disposition: .replaceExact, operationID: Fixture.id(992),
                replacementBindings: incomplete
            )) {
                XCTAssertEqual($0 as? MyDayReplacementValueProjectionFailureV1, .invalidBinding)
            }
            XCTAssertThrowsError(try adapter.materializeRestoreStaging(
                fixture.snapshot, targetWorkspaceID: fixture.targetWorkspaceID,
                disposition: .replaceExact, operationID: Fixture.id(992),
                replacementBindings: foreignTarget
            )) {
                XCTAssertEqual($0 as? MyDayFailureV1, .wrongWorkspace)
            }
            for disposition in [MyDayRestoreDispositionV1.configurationCloneOmit, .workspaceForkNonactiveHistory] {
                XCTAssertThrowsError(try adapter.materializeRestoreStaging(
                    fixture.snapshot, targetWorkspaceID: fixture.targetWorkspaceID,
                    disposition: disposition, operationID: Fixture.id(992),
                    replacementBindings: bindings
                )) {
                    XCTAssertEqual($0 as? MyDayFailureV1, .invalidValue)
                }
            }
            let emptyTarget = try adapter.snapshotForBackup(
                workspaceID: fixture.targetWorkspaceID, nonactivePlanReferences: []
            )
            XCTAssertTrue(emptyTarget.plans.isEmpty)
            XCTAssertTrue(emptyTarget.carryoverReceipts.isEmpty)
            try assertSourceBystanderUnchanged(
                adapter, context: context, fixture: fixture, bystander: bystander,
                bystanderBytes: bystanderBytes, projectedPlanRows: 0, projectedReceiptRows: 0
            )

            try adapter.materializeRestoreStaging(
                fixture.snapshot, targetWorkspaceID: fixture.targetWorkspaceID,
                disposition: .replaceExact, operationID: Fixture.id(993),
                replacementBindings: bindings
            )
            let materialized = try adapter.snapshotForBackup(
                workspaceID: fixture.targetWorkspaceID,
                nonactivePlanReferences: expected.nonactivePlanReferences
            )
            XCTAssertEqual(materialized, expected)
            XCTAssertEqual(
                try MyDayCanonicalCodecV1.data(materialized),
                try MyDayCanonicalCodecV1.data(expected)
            )
            XCTAssertEqual(materialized.plans.count, fixture.snapshot.plans.count)
            XCTAssertEqual(
                materialized.carryoverReceipts.count,
                fixture.snapshot.carryoverReceipts.count
            )
            try assertSourceBystanderUnchanged(
                adapter, context: context, fixture: fixture, bystander: bystander,
                bystanderBytes: bystanderBytes,
                projectedPlanRows: expected.plans.count,
                projectedReceiptRows: expected.carryoverReceipts.count
            )

            XCTAssertThrowsError(try adapter.materializeRestoreStaging(
                fixture.snapshot, targetWorkspaceID: fixture.targetWorkspaceID,
                disposition: .replaceExact, operationID: Fixture.id(994),
                replacementBindings: bindings
            )) {
                XCTAssertEqual($0 as? MyDayFailureV1, .divergentMutation)
            }
            XCTAssertEqual(
                try adapter.snapshotForBackup(
                    workspaceID: fixture.targetWorkspaceID,
                    nonactivePlanReferences: expected.nonactivePlanReferences
                ),
                expected
            )
            try assertSourceBystanderUnchanged(
                adapter, context: context, fixture: fixture, bystander: bystander,
                bystanderBytes: bystanderBytes,
                projectedPlanRows: expected.plans.count,
                projectedReceiptRows: expected.carryoverReceipts.count
            )
        }

        // Cold reopen: the first container, context and adapter are out of
        // scope; a new ModelContainer reads the same on-disk store.
        let reopenedContainer = try Self.materializationContainer(storeURL: storeURL)
        let reopenedContext = reopenedContainer.mainContext
        reopenedContext.autosaveEnabled = false
        let reopened = MyDayLifecycleAdapterV1(modelContext: reopenedContext)
        let coldTarget = try reopened.snapshotForBackup(
            workspaceID: fixture.targetWorkspaceID,
            nonactivePlanReferences: expected.nonactivePlanReferences
        )
        XCTAssertEqual(coldTarget, expected)
        XCTAssertEqual(
            try MyDayCanonicalCodecV1.data(coldTarget),
            try MyDayCanonicalCodecV1.data(expected)
        )
        try assertSourceBystanderUnchanged(
            reopened, context: reopenedContext, fixture: fixture, bystander: bystander,
            bystanderBytes: bystanderBytes,
            projectedPlanRows: expected.plans.count,
            projectedReceiptRows: expected.carryoverReceipts.count
        )
    }

    private static func materializationContainer(storeURL: URL) throws -> ModelContainer {
        let schema = Schema(
            PersistentSchemaV53.models,
            version: PersistentSchemaV53.versionIdentifier
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                "C57-Replacement-Materialize",
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )]
        )
    }

    /// Source-workspace rows must be byte-identical and the store must hold
    /// exactly those rows plus the projected target rows.
    @MainActor
    private func assertSourceBystanderUnchanged(
        _ adapter: MyDayLifecycleAdapterV1,
        context: ModelContext,
        fixture: Fixture,
        bystander: MyDayBackupSnapshotV1,
        bystanderBytes: Data,
        projectedPlanRows: Int,
        projectedReceiptRows: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let current = try adapter.snapshotForBackup(
            workspaceID: fixture.sourceWorkspaceID,
            nonactivePlanReferences: bystander.nonactivePlanReferences
        )
        XCTAssertEqual(current, bystander, file: file, line: line)
        XCTAssertEqual(
            try MyDayCanonicalCodecV1.data(current), bystanderBytes, file: file, line: line
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<MyDayPlanRowV1>()).count,
            bystander.plans.count + projectedPlanRows,
            file: file, line: line
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<MyDayCarryoverReceiptRowV1>()).count,
            bystander.carryoverReceipts.count + projectedReceiptRows,
            file: file, line: line
        )
        XCTAssertFalse(context.hasChanges, file: file, line: line)
    }

    func testSameWorkspaceReplacementIsByteExactAndRejectsBindings() throws {
        let fixture = try Fixture.make()
        let source = Projector.Source(snapshot: fixture.snapshot)
        let before = try MyDayCanonicalCodecV1.data(fixture.snapshot)
        let result = try Projector.project(
            source,
            bindings: .init(targetWorkspaceID: fixture.sourceWorkspaceID)
        )

        XCTAssertEqual(result.sourceSnapshotSHA256, fixture.snapshot.snapshotSHA256)
        XCTAssertEqual(result.targetSnapshot, fixture.snapshot)
        XCTAssertEqual(try MyDayCanonicalCodecV1.data(result.targetSnapshot), before)
        XCTAssertEqual(result.plans.map(\.source), result.plans.map(\.target))
        XCTAssertEqual(result.carryovers.map(\.source), result.carryovers.map(\.target))
        XCTAssertEqual(
            result.carryovers.map(\.sourceCommandPlan),
            result.carryovers.map(\.targetCommandPlan)
        )

        let crossWorkspaceBindings = try fixture.validBindings()
        XCTAssertThrowsError(
            try Projector.project(
                source,
                bindings: .init(
                    targetWorkspaceID: fixture.sourceWorkspaceID,
                    eligibleReferences: crossWorkspaceBindings.eligibleReferences,
                    mutationIDs: crossWorkspaceBindings.mutationIDs
                )
            )
        ) {
            XCTAssertEqual(
                $0 as? MyDayReplacementValueProjectionFailureV1,
                .sameWorkspaceBindings
            )
        }
    }

    func testEmptyCrossWorkspaceReplacementBuildsCanonicalTargetEmptySnapshot() throws {
        let sourceWorkspaceID = Fixture.workspace(20)
        let targetWorkspaceID = Fixture.workspace(21)
        let snapshot = try MyDayBackupSnapshotV1(
            workspaceID: sourceWorkspaceID,
            plans: [],
            carryoverReceipts: [],
            nonactivePlanReferences: []
        )
        let source = Projector.Source(snapshot: snapshot)
        XCTAssertEqual(
            try Projector.requirements(for: source),
            .init(eligibleReferences: [], mutationIDs: [])
        )

        let result = try Projector.project(
            source,
            bindings: .init(targetWorkspaceID: targetWorkspaceID)
        )
        let expected = try MyDayBackupSnapshotV1(
            workspaceID: targetWorkspaceID,
            plans: [],
            carryoverReceipts: [],
            nonactivePlanReferences: []
        )
        XCTAssertEqual(result.targetSnapshot, expected)
        XCTAssertEqual(result.sourceSnapshotSHA256, snapshot.snapshotSHA256)
        XCTAssertNotEqual(result.targetSnapshot.snapshotSHA256, snapshot.snapshotSHA256)
        XCTAssertTrue(result.plans.isEmpty)
        XCTAssertTrue(result.carryovers.isEmpty)
    }

    func testCrossWorkspaceReplacementPreservesAllHistoryAndCarryoverPredecessor() throws {
        let fixture = try Fixture.make()
        let source = Projector.Source(snapshot: fixture.snapshot)
        let sourceBytes = try MyDayCanonicalCodecV1.data(fixture.snapshot)
        let requirements = try Projector.requirements(for: source)
        XCTAssertEqual(requirements.eligibleReferences.count, 4)
        XCTAssertEqual(requirements.mutationIDs.count, 4)
        XCTAssertEqual(Set(requirements.eligibleReferences), Set(fixture.sourceReferences))
        XCTAssertTrue(Self.coversAllReferenceKinds(requirements.eligibleReferences))

        let bindings = try fixture.validBindings()
        let first = try Projector.project(source, bindings: bindings)
        let second = try Projector.project(
            source,
            bindings: .init(
                targetWorkspaceID: fixture.targetWorkspaceID,
                eligibleReferences: Array(bindings.eligibleReferences.reversed()),
                mutationIDs: Array(bindings.mutationIDs.reversed())
            )
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(try MyDayCanonicalCodecV1.data(fixture.snapshot), sourceBytes)
        XCTAssertEqual(fixture.snapshot.snapshotSHA256, first.sourceSnapshotSHA256)
        XCTAssertEqual(first.targetSnapshot.workspaceID, fixture.targetWorkspaceID)
        XCTAssertNotEqual(
            first.targetSnapshot.snapshotSHA256,
            fixture.snapshot.snapshotSHA256
        )
        XCTAssertEqual(first.plans.count, fixture.snapshot.plans.count)
        XCTAssertEqual(first.carryovers.count, fixture.snapshot.carryoverReceipts.count)
        try first.targetSnapshot.validate()
        XCTAssertEqual(
            first.targetSnapshot.nonactivePlanReferences,
            try C57MyDayBackupEnrollmentV1.exactNonactiveReferences(
                for: first.targetSnapshot.plans
            )
        )

        let referenceMap = Dictionary(uniqueKeysWithValues: bindings.eligibleReferences.map {
            ($0.source, $0.target)
        })
        let mutationMap = Dictionary(uniqueKeysWithValues: bindings.mutationIDs.map {
            ($0.source, $0.target)
        })
        for projection in first.plans {
            XCTAssertEqual(projection.target.planID, projection.source.planID)
            XCTAssertEqual(projection.target.revision, projection.source.revision)
            XCTAssertEqual(projection.target.authoredAt, projection.source.authoredAt)
            XCTAssertEqual(projection.target.key.civilDate, projection.source.key.civilDate)
            XCTAssertEqual(
                projection.target.key.ianaTimeZoneIdentifier,
                projection.source.key.ianaTimeZoneIdentifier
            )
            XCTAssertEqual(projection.target.key.workspaceID, fixture.targetWorkspaceID)
            XCTAssertNotEqual(projection.target.key.keySHA256, projection.source.key.keySHA256)
            XCTAssertEqual(
                projection.target.mutationID,
                try XCTUnwrap(mutationMap[projection.source.mutationID])
            )
            XCTAssertEqual(
                projection.target.items.map(\.membershipID),
                projection.source.items.map(\.membershipID)
            )
            XCTAssertEqual(
                projection.target.items.map(\.manualOrder),
                projection.source.items.map(\.manualOrder)
            )
            XCTAssertEqual(
                projection.target.items.map(\.estimate),
                projection.source.items.map(\.estimate)
            )
            XCTAssertEqual(
                projection.target.items.map(\.reference),
                projection.source.items.compactMap { referenceMap[$0.reference] }
            )
            XCTAssertEqual(
                projection.target.authoredBy.snapshotID,
                projection.source.authoredBy.snapshotID
            )
            XCTAssertEqual(
                projection.target.authoredBy.actor.actorReferenceID,
                projection.source.authoredBy.actor.actorReferenceID
            )
            XCTAssertEqual(
                projection.target.authoredBy.actor.partyID,
                projection.source.authoredBy.actor.partyID
            )
            XCTAssertEqual(
                projection.target.authoredBy.displayNameAtTime,
                projection.source.authoredBy.displayNameAtTime
            )
            XCTAssertEqual(
                projection.target.authoredBy.capturedAt,
                projection.source.authoredBy.capturedAt
            )
            XCTAssertEqual(
                projection.target.authoredBy.workspaceID,
                fixture.targetWorkspaceID
            )
            XCTAssertNotEqual(
                projection.target.authoredBy.snapshotSHA256,
                projection.source.authoredBy.snapshotSHA256
            )
            XCTAssertNotEqual(projection.target.planSHA256, projection.source.planSHA256)
        }

        let carryover = try XCTUnwrap(first.carryovers.first)
        XCTAssertEqual(
            carryover.sourceCommandPlan.expectedTargetPlan,
            try MyDayPlanReferenceV1(fixture.targetPlanRevisionOne)
        )
        let targetPredecessor = try XCTUnwrap(first.plans.first {
            $0.source == fixture.targetPlanRevisionOne
        })
        XCTAssertEqual(
            carryover.targetCommandPlan.expectedTargetPlan,
            try MyDayPlanReferenceV1(targetPredecessor.target)
        )
        XCTAssertEqual(
            carryover.targetCommandPlan.membershipIDs,
            carryover.sourceCommandPlan.membershipIDs
        )
        XCTAssertEqual(carryover.target.committedAt, carryover.source.committedAt)
        XCTAssertEqual(
            carryover.target.carriedMembershipIDs,
            carryover.source.carriedMembershipIDs
        )
        XCTAssertEqual(
            carryover.target.mutationID,
            try XCTUnwrap(mutationMap[fixture.targetPlanRevisionTwo.mutationID])
        )
        XCTAssertNotEqual(carryover.target.receiptSHA256, carryover.source.receiptSHA256)
    }

    func testCrossWorkspaceReplacementRejectsHostileAndUnusedBindings() throws {
        let fixture = try Fixture.make()
        let source = Projector.Source(snapshot: fixture.snapshot)
        let valid = try fixture.validBindings()
        func assertInvalid(
            _ references: [Projector.EligibleReferenceBinding],
            _ mutations: [Projector.MutationIDBinding],
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertThrowsError(
                try Projector.project(
                    source,
                    bindings: .init(
                        targetWorkspaceID: fixture.targetWorkspaceID,
                        eligibleReferences: references,
                        mutationIDs: mutations
                    )
                ),
                file: file,
                line: line
            ) {
                XCTAssertEqual(
                    $0 as? MyDayReplacementValueProjectionFailureV1,
                    .invalidBinding,
                    file: file,
                    line: line
                )
            }
        }

        assertInvalid(Array(valid.eligibleReferences.dropLast()), valid.mutationIDs)
        var duplicateSource = valid.eligibleReferences
        let firstReferenceBinding = duplicateSource[0]
        duplicateSource[duplicateSource.count - 1] = firstReferenceBinding
        assertInvalid(duplicateSource, valid.mutationIDs)

        var foreign = valid.eligibleReferences
        let foreignSource = foreign[0].source
        foreign[0] = .init(source: foreignSource, target: foreignSource)
        assertInvalid(foreign, valid.mutationIDs)

        let roundIndex = try XCTUnwrap(valid.eligibleReferences.firstIndex {
            if case .roundSession = $0.source { return true }
            return false
        })
        guard case let .roundSession(_, sessionID, revision, digest) =
            valid.eligibleReferences[roundIndex].source else {
            XCTFail("missing round-session requirement")
            return
        }
        var staleRevision = valid.eligibleReferences
        let staleSource = staleRevision[roundIndex].source
        staleRevision[roundIndex] = .init(
            source: staleSource,
            target: .roundSession(
                workspaceID: fixture.targetWorkspaceID,
                sessionID: sessionID,
                revision: revision + 1,
                sessionSHA256: Fixture.digest("e")
            )
        )
        assertInvalid(staleRevision, valid.mutationIDs)

        var unchangedDigest = valid.eligibleReferences
        let unchangedSource = unchangedDigest[roundIndex].source
        unchangedDigest[roundIndex] = .init(
            source: unchangedSource,
            target: .roundSession(
                workspaceID: fixture.targetWorkspaceID,
                sessionID: sessionID,
                revision: revision,
                sessionSHA256: digest
            )
        )
        assertInvalid(unchangedDigest, valid.mutationIDs)

        let draftTarget = try XCTUnwrap(valid.eligibleReferences.first {
            if case .resumableDraft = $0.target { return true }
            return false
        }).target
        var wrongFamily = valid.eligibleReferences
        let wrongFamilySource = wrongFamily[roundIndex].source
        wrongFamily[roundIndex] = .init(
            source: wrongFamilySource,
            target: draftTarget
        )
        assertInvalid(wrongFamily, valid.mutationIDs)

        assertInvalid(valid.eligibleReferences, Array(valid.mutationIDs.dropLast()))
        var duplicateTarget = valid.mutationIDs
        let finalSource = duplicateTarget[duplicateTarget.count - 1].source
        duplicateTarget[duplicateTarget.count - 1] = .init(
            source: finalSource,
            target: duplicateTarget[0].target
        )
        assertInvalid(valid.eligibleReferences, duplicateTarget)

        var sourceEqual = valid.mutationIDs
        let equalMutationSource = sourceEqual[0].source
        sourceEqual[0] = .init(source: equalMutationSource, target: equalMutationSource)
        assertInvalid(valid.eligibleReferences, sourceEqual)

        let extraReference = Projector.EligibleReferenceBinding(
                source: .roundSession(
                    workspaceID: fixture.sourceWorkspaceID,
                    sessionID: Fixture.id(9_900),
                    revision: 1,
                    sessionSHA256: Fixture.digest("1")
                ),
                target: .roundSession(
                    workspaceID: fixture.targetWorkspaceID,
                    sessionID: Fixture.id(9_900),
                    revision: 1,
                    sessionSHA256: Fixture.digest("2")
                )
            )
        assertInvalid(
            valid.eligibleReferences + [extraReference],
            valid.mutationIDs
        )
        let extraMutation = Projector.MutationIDBinding(
            source: try Fixture.mutation(9_901),
            target: try Fixture.mutation(9_902)
        )
        assertInvalid(
            valid.eligibleReferences,
            valid.mutationIDs + [extraMutation]
        )

        // Isolated exactIdentityCorresponds cases. Each hostile target is a
        // valid target-workspace reference with the source's stable key and
        // source revision and a digest different from the source; it replaces
        // the valid binding at the same index, so every uniqueness guard
        // holds. It differs from the valid target only in the named identity
        // field, so only exactIdentityCorresponds can reject it.
        func assertOnlyIdentityDiffers(
            _ index: Int,
            _ hostile: MyDayEligibleReferenceV1,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            let binding = valid.eligibleReferences[index]
            XCTAssertNoThrow(try hostile.validate(), file: file, line: line)
            XCTAssertEqual(hostile.workspaceID, fixture.targetWorkspaceID, file: file, line: line)
            XCTAssertEqual(hostile.stableKey, binding.source.stableKey, file: file, line: line)
            XCTAssertEqual(
                hostile.sourceRevision, binding.source.sourceRevision, file: file, line: line
            )
            XCTAssertNotEqual(
                hostile.sourceSHA256, binding.source.sourceSHA256, file: file, line: line
            )
            XCTAssertNotEqual(hostile, binding.target, file: file, line: line)
            var references = valid.eligibleReferences
            references[index] = .init(source: binding.source, target: hostile)
            assertInvalid(references, valid.mutationIDs, file: file, line: line)
        }

        // Work packet: only manifestID differs (packetID and packetVersion match).
        let packetIndex = try XCTUnwrap(valid.eligibleReferences.firstIndex {
            if case .workPacket = $0.source { return true }
            return false
        })
        let targetActor = try Fixture.actor(10, workspaceID: fixture.targetWorkspaceID)
        let manifestChanged = try Fixture.workPacketReference(
            100,
            workspaceID: fixture.targetWorkspaceID,
            actor: targetActor,
            mutationID: try Fixture.mutation(7_100),
            manifestID: Fixture.id(4_999)
        )
        guard case let .workPacket(validPacket) = valid.eligibleReferences[packetIndex].target,
              case let .workPacket(changedPacket) = manifestChanged else {
            XCTFail("missing work-packet references")
            return
        }
        XCTAssertNotEqual(changedPacket.manifestID, validPacket.manifestID)
        XCTAssertEqual(changedPacket.packetID, validPacket.packetID)
        XCTAssertEqual(changedPacket.packetVersion, validPacket.packetVersion)
        assertOnlyIdentityDiffers(packetIndex, manifestChanged)

        // Schedule: only scheduleReleaseID, then only expectedScheduleRevision, differs.
        let scheduleIndex = try XCTUnwrap(valid.eligibleReferences.firstIndex {
            if case .scheduleOccurrence = $0.source { return true }
            return false
        })
        let validSchedule = valid.eligibleReferences[scheduleIndex].target
        let releaseChanged = try Self.scheduleReference(
            validSchedule,
            replacingScheduleField: "scheduleReleaseID",
            with: Fixture.id(9_950).uuidString
        )
        let revisionChanged = try Self.scheduleReference(
            validSchedule,
            replacingScheduleField: "expectedScheduleRevision",
            with: 2
        )
        guard case let .scheduleOccurrence(validAnchor, _) = validSchedule,
              case let .scheduleOccurrence(releaseAnchor, _) = releaseChanged,
              case let .scheduleOccurrence(revisionAnchor, _) = revisionChanged else {
            XCTFail("missing schedule references")
            return
        }
        XCTAssertNotEqual(releaseAnchor.schedule.scheduleReleaseID, validAnchor.schedule.scheduleReleaseID)
        XCTAssertEqual(
            releaseAnchor.schedule.expectedScheduleRevision,
            validAnchor.schedule.expectedScheduleRevision
        )
        XCTAssertEqual(revisionAnchor.schedule.scheduleReleaseID, validAnchor.schedule.scheduleReleaseID)
        XCTAssertNotEqual(
            revisionAnchor.schedule.expectedScheduleRevision,
            validAnchor.schedule.expectedScheduleRevision
        )
        for changed in [releaseAnchor, revisionAnchor] {
            XCTAssertEqual(changed.schedule.workspaceID, validAnchor.schedule.workspaceID)
            XCTAssertEqual(
                changed.schedule.scheduleDefinitionID,
                validAnchor.schedule.scheduleDefinitionID
            )
            XCTAssertEqual(changed.occurrenceID, validAnchor.occurrenceID)
            XCTAssertEqual(changed.expectedOccurrenceRevision, validAnchor.expectedOccurrenceRevision)
        }
        assertOnlyIdentityDiffers(scheduleIndex, releaseChanged)
        assertOnlyIdentityDiffers(scheduleIndex, revisionChanged)

        // Resumable draft: only the resume anchor differs.
        let draftIndex = try XCTUnwrap(valid.eligibleReferences.firstIndex {
            if case .resumableDraft = $0.source { return true }
            return false
        })
        guard case let .resumableDraft(_, draftID, draftRevision, checkpointSHA256, draftAnchor) =
            valid.eligibleReferences[draftIndex].target else {
            XCTFail("missing resumable-draft reference")
            return
        }
        let changedAnchor = try DraftResumeAnchorV1(
            sectionID: draftAnchor.sectionID,
            fieldID: draftAnchor.fieldID,
            selectedStableID: draftAnchor.selectedStableID,
            boundedPosition: 18
        )
        XCTAssertNotEqual(changedAnchor, draftAnchor)
        let anchorChanged: MyDayEligibleReferenceV1 = .resumableDraft(
            workspaceID: fixture.targetWorkspaceID,
            draftID: draftID,
            revision: draftRevision,
            checkpointSHA256: checkpointSHA256,
            anchor: changedAnchor
        )
        assertOnlyIdentityDiffers(draftIndex, anchorChanged)

        // Isolates the target-workspace guard: same session ID and revision
        // (so exactIdentityCorresponds holds), same stable key and source
        // revision, and a fresh valid digest different from the source, but
        // in a third workspace.
        let thirdWorkspaceID = Fixture.workspace(3)
        XCTAssertNotEqual(thirdWorkspaceID, fixture.sourceWorkspaceID)
        XCTAssertNotEqual(thirdWorkspaceID, fixture.targetWorkspaceID)
        let roundSource = valid.eligibleReferences[roundIndex].source
        let thirdTarget: MyDayEligibleReferenceV1 = .roundSession(
            workspaceID: thirdWorkspaceID,
            sessionID: sessionID,
            revision: revision,
            sessionSHA256: Fixture.digest("7")
        )
        XCTAssertNoThrow(try thirdTarget.validate())
        XCTAssertEqual(thirdTarget.stableKey, roundSource.stableKey)
        XCTAssertEqual(thirdTarget.sourceRevision, roundSource.sourceRevision)
        XCTAssertNotEqual(thirdTarget.sourceSHA256, roundSource.sourceSHA256)
        var thirdWorkspace = valid.eligibleReferences
        thirdWorkspace[roundIndex] = .init(source: roundSource, target: thirdTarget)
        assertInvalid(thirdWorkspace, valid.mutationIDs)
    }

    /// Re-encodes a schedule-occurrence anchor with exactly one schedule
    /// field replaced; every other anchor field keeps its decoded value.
    private static func scheduleReference(
        _ reference: MyDayEligibleReferenceV1,
        replacingScheduleField field: String,
        with value: Any
    ) throws -> MyDayEligibleReferenceV1 {
        guard case let .scheduleOccurrence(anchor, sourceEventSHA256) = reference else {
            throw MyDayFailureV1.invalidValue
        }
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(anchor)) as? [String: Any]
        )
        var schedule = try XCTUnwrap(object["schedule"] as? [String: Any])
        XCTAssertNotNil(schedule[field])
        schedule[field] = value
        object["schedule"] = schedule
        let changed = try JSONDecoder().decode(
            C34OccurrenceNavigationAnchorV1.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        return .scheduleOccurrence(changed, sourceEventSHA256: sourceEventSHA256)
    }

    func testSourceValidationRejectsPartialCarryoverAndNonactiveClosure() throws {
        let fixture = try Fixture.make()
        let exactNonactive = try C57MyDayBackupEnrollmentV1.exactNonactiveReferences(
            for: fixture.snapshot.plans
        )

        let staleCommand = try MyDayCarryoverPlanV1(
            sourcePlan: fixture.sourcePlanRevisionTwo,
            targetKey: fixture.targetPlanRevisionTwo.key,
            membershipIDs: fixture.sourcePlanRevisionTwo.items.map(\.membershipID),
            expectedTargetPlan: nil
        )
        let staleReceipt = try MyDayCarryoverReceiptV1(
            plan: staleCommand,
            source: fixture.sourcePlanRevisionTwo,
            target: fixture.targetPlanRevisionTwo,
            mutationID: fixture.targetPlanRevisionTwo.mutationID,
            committedAt: fixture.committedAt
        )
        let staleSnapshot = try MyDayBackupSnapshotV1(
            workspaceID: fixture.sourceWorkspaceID,
            plans: fixture.snapshot.plans,
            carryoverReceipts: [staleReceipt],
            nonactivePlanReferences: exactNonactive
        )
        try staleSnapshot.validate()
        XCTAssertThrowsError(
            try Projector.requirements(for: .init(snapshot: staleSnapshot))
        ) {
            XCTAssertEqual(
                $0 as? MyDayReplacementValueProjectionFailureV1,
                .invalidSource
            )
        }

        let orphanKey = try Fixture.key(
            workspaceID: fixture.sourceWorkspaceID,
            date: "2026-09-12"
        )
        let orphanTarget = try Fixture.plan(
            planID: Fixture.id(7_700),
            key: orphanKey,
            items: fixture.sourcePlanRevisionTwo.items,
            revision: 1,
            mutationID: try Fixture.mutation(7_701),
            actor: fixture.sourcePlanRevisionTwo.authoredBy,
            authoredAt: fixture.committedAt
        )
        let orphanCommand = try MyDayCarryoverPlanV1(
            sourcePlan: fixture.sourcePlanRevisionTwo,
            targetKey: orphanTarget.key,
            membershipIDs: fixture.sourcePlanRevisionTwo.items.map(\.membershipID)
        )
        let orphanReceipt = try MyDayCarryoverReceiptV1(
            plan: orphanCommand,
            source: fixture.sourcePlanRevisionTwo,
            target: orphanTarget,
            mutationID: orphanTarget.mutationID,
            committedAt: fixture.committedAt.addingTimeInterval(1)
        )
        let orphanSnapshot = try MyDayBackupSnapshotV1(
            workspaceID: fixture.sourceWorkspaceID,
            plans: fixture.snapshot.plans,
            carryoverReceipts: [orphanReceipt],
            nonactivePlanReferences: exactNonactive
        )
        try orphanSnapshot.validate()
        XCTAssertThrowsError(
            try Projector.requirements(for: .init(snapshot: orphanSnapshot))
        ) {
            XCTAssertEqual(
                $0 as? MyDayReplacementValueProjectionFailureV1,
                .invalidSource
            )
        }

        let incompleteNonactive = try MyDayBackupSnapshotV1(
            workspaceID: fixture.sourceWorkspaceID,
            plans: fixture.snapshot.plans,
            carryoverReceipts: fixture.snapshot.carryoverReceipts,
            nonactivePlanReferences: []
        )
        try incompleteNonactive.validate()
        XCTAssertThrowsError(
            try Projector.requirements(for: .init(snapshot: incompleteNonactive))
        ) {
            XCTAssertEqual(
                $0 as? MyDayReplacementValueProjectionFailureV1,
                .invalidSource
            )
        }

        let validCommand = try MyDayCarryoverPlanV1(
            sourcePlan: fixture.sourcePlanRevisionTwo,
            targetKey: fixture.targetPlanRevisionTwo.key,
            membershipIDs: fixture.sourcePlanRevisionTwo.items.map(\.membershipID),
            expectedTargetPlan: fixture.targetPlanRevisionOne
        )
        let duplicateMutationReceipt = try MyDayCarryoverReceiptV1(
            plan: validCommand,
            source: fixture.sourcePlanRevisionTwo,
            target: fixture.targetPlanRevisionTwo,
            mutationID: fixture.targetPlanRevisionTwo.mutationID,
            committedAt: fixture.committedAt.addingTimeInterval(2)
        )
        let duplicateMutationSnapshot = try MyDayBackupSnapshotV1(
            workspaceID: fixture.sourceWorkspaceID,
            plans: fixture.snapshot.plans,
            carryoverReceipts: fixture.snapshot.carryoverReceipts + [duplicateMutationReceipt],
            nonactivePlanReferences: exactNonactive
        )
        try duplicateMutationSnapshot.validate()
        XCTAssertThrowsError(
            try Projector.requirements(for: .init(snapshot: duplicateMutationSnapshot))
        ) {
            XCTAssertEqual(
                $0 as? MyDayReplacementValueProjectionFailureV1,
                .invalidSource
            )
        }

        let sourcePlanRevisionOne = fixture.sourcePlanRevisionOne
        let ambiguousItems = try sourcePlanRevisionOne.items.map { item in
            guard case let .roundSession(workspaceID, sessionID, revision, _) =
                item.reference else { return item }
            return try MyDayItemV1(
                membershipID: item.membershipID,
                reference: .roundSession(
                    workspaceID: workspaceID,
                    sessionID: sessionID,
                    revision: revision,
                    sessionSHA256: Fixture.digest("f")
                ),
                manualOrder: item.manualOrder,
                estimate: item.estimate
            )
        }
        let ambiguousSuccessor = try Fixture.plan(
            planID: sourcePlanRevisionOne.planID,
            key: sourcePlanRevisionOne.key,
            items: ambiguousItems,
            predecessor: sourcePlanRevisionOne,
            revision: 2,
            mutationID: try Fixture.mutation(7_800),
            actor: fixture.sourcePlanRevisionTwo.authoredBy,
            authoredAt: fixture.committedAt
        )
        let ambiguousPlans = [sourcePlanRevisionOne, ambiguousSuccessor]
        let ambiguousSnapshot = try MyDayBackupSnapshotV1(
            workspaceID: fixture.sourceWorkspaceID,
            plans: ambiguousPlans,
            carryoverReceipts: [],
            nonactivePlanReferences: C57MyDayBackupEnrollmentV1
                .exactNonactiveReferences(for: ambiguousPlans)
        )
        try ambiguousSnapshot.validate()
        XCTAssertThrowsError(
            try Projector.requirements(for: .init(snapshot: ambiguousSnapshot))
        ) {
            XCTAssertEqual(
                $0 as? MyDayReplacementValueProjectionFailureV1,
                .invalidSource
            )
        }
    }

    private static func coversAllReferenceKinds(
        _ values: [MyDayEligibleReferenceV1]
    ) -> Bool {
        var workPacket = false
        var roundSession = false
        var scheduleOccurrence = false
        var resumableDraft = false
        for value in values {
            switch value {
            case .workPacket: workPacket = true
            case .roundSession: roundSession = true
            case .scheduleOccurrence: scheduleOccurrence = true
            case .resumableDraft: resumableDraft = true
            }
        }
        return workPacket && roundSession && scheduleOccurrence && resumableDraft
    }
}

private extension V23MyDayReplacementProjectionTests {
    struct Fixture {
        let sourceWorkspaceID: WorkspaceID
        let targetWorkspaceID: WorkspaceID
        let sourceReferences: [MyDayEligibleReferenceV1]
        let targetReferences: [MyDayEligibleReferenceV1]
        let sourcePlanRevisionOne: MyDayPlanV1
        let sourcePlanRevisionTwo: MyDayPlanV1
        let targetPlanRevisionOne: MyDayPlanV1
        let targetPlanRevisionTwo: MyDayPlanV1
        let committedAt: Date
        let snapshot: MyDayBackupSnapshotV1

        static let instant = Date(timeIntervalSince1970: 1_810_000_000)

        static func make() throws -> Self {
            let sourceWorkspaceID = workspace(1)
            let targetWorkspaceID = workspace(2)
            let sourceActorOne = try actor(10, workspaceID: sourceWorkspaceID)
            let sourceActorTwo = try actor(
                11,
                workspaceID: sourceWorkspaceID,
                at: instant.addingTimeInterval(1)
            )
            let targetActorOne = try actor(10, workspaceID: targetWorkspaceID)

            let sourcePacket = try workPacketReference(
                100,
                workspaceID: sourceWorkspaceID,
                actor: sourceActorOne,
                mutationID: try mutation(6_100)
            )
            let targetPacket = try workPacketReference(
                100,
                workspaceID: targetWorkspaceID,
                actor: targetActorOne,
                mutationID: try mutation(7_100)
            )
            let sourceRound: MyDayEligibleReferenceV1 = .roundSession(
                workspaceID: sourceWorkspaceID,
                sessionID: id(200),
                revision: 3,
                sessionSHA256: digest("a")
            )
            let targetRound: MyDayEligibleReferenceV1 = .roundSession(
                workspaceID: targetWorkspaceID,
                sessionID: id(200),
                revision: 3,
                sessionSHA256: digest("b")
            )
            let sourceSchedule = try C41MyDayScheduleFixtureV1.make(
                workspaceID: sourceWorkspaceID,
                actor: sourceActorOne
            ).reference
            let targetSchedule = try C41MyDayScheduleFixtureV1.make(
                workspaceID: targetWorkspaceID,
                actor: targetActorOne
            ).reference
            let anchor = try DraftResumeAnchorV1(
                sectionID: "replacement-section",
                fieldID: "replacement-field",
                selectedStableID: "replacement-selection",
                boundedPosition: 17
            )
            let sourceDraft: MyDayEligibleReferenceV1 = .resumableDraft(
                workspaceID: sourceWorkspaceID,
                draftID: id(300),
                revision: 5,
                checkpointSHA256: digest("c"),
                anchor: anchor
            )
            let targetDraft: MyDayEligibleReferenceV1 = .resumableDraft(
                workspaceID: targetWorkspaceID,
                draftID: id(300),
                revision: 5,
                checkpointSHA256: digest("d"),
                anchor: anchor
            )
            let sourceReferences = [sourcePacket, sourceRound, sourceSchedule, sourceDraft]
            let targetReferences = [targetPacket, targetRound, targetSchedule, targetDraft]
            XCTAssertEqual(
                sourceReferences.map(\.stableKey),
                targetReferences.map(\.stableKey)
            )
            XCTAssertEqual(
                sourceReferences.map(\.sourceRevision),
                targetReferences.map(\.sourceRevision)
            )
            XCTAssertTrue(zip(sourceReferences, targetReferences).allSatisfy { pair in
                pair.0.sourceSHA256 != pair.1.sourceSHA256
            })

            let items = try sourceReferences.enumerated().map { index, reference in
                try MyDayItemV1(
                    membershipID: id(400 + index),
                    reference: reference,
                    manualOrder: index,
                    estimate: try MyDayEstimateV1(wholeMinutes: 15 + index * 10)
                )
            }
            let sourceKey = try key(
                workspaceID: sourceWorkspaceID,
                date: "2026-09-10"
            )
            let sourcePlanRevisionOne = try plan(
                planID: id(500),
                key: sourceKey,
                items: items,
                revision: 1,
                mutationID: try mutation(600),
                actor: sourceActorOne,
                authoredAt: instant
            )
            let sourcePlanRevisionTwo = try plan(
                planID: sourcePlanRevisionOne.planID,
                key: sourceKey,
                items: items,
                predecessor: sourcePlanRevisionOne,
                revision: 2,
                mutationID: try mutation(601),
                actor: sourceActorTwo,
                authoredAt: instant.addingTimeInterval(1)
            )
            let targetKey = try key(
                workspaceID: sourceWorkspaceID,
                date: "2026-09-11"
            )
            let targetPlanRevisionOne = try plan(
                planID: id(501),
                key: targetKey,
                items: items,
                revision: 1,
                mutationID: try mutation(602),
                actor: sourceActorOne,
                authoredAt: instant.addingTimeInterval(2)
            )
            let targetPlanRevisionTwo = try plan(
                planID: targetPlanRevisionOne.planID,
                key: targetKey,
                items: items,
                predecessor: targetPlanRevisionOne,
                revision: 2,
                mutationID: try mutation(603),
                actor: sourceActorTwo,
                authoredAt: instant.addingTimeInterval(3)
            )
            let commandPlan = try MyDayCarryoverPlanV1(
                sourcePlan: sourcePlanRevisionTwo,
                targetKey: targetKey,
                membershipIDs: items.map(\.membershipID),
                expectedTargetPlan: targetPlanRevisionOne
            )
            let committedAt = instant.addingTimeInterval(4)
            let receipt = try MyDayCarryoverReceiptV1(
                plan: commandPlan,
                source: sourcePlanRevisionTwo,
                target: targetPlanRevisionTwo,
                mutationID: targetPlanRevisionTwo.mutationID,
                committedAt: committedAt
            )
            let plans = [
                sourcePlanRevisionOne, sourcePlanRevisionTwo,
                targetPlanRevisionOne, targetPlanRevisionTwo,
            ]
            let snapshot = try MyDayBackupSnapshotV1(
                workspaceID: sourceWorkspaceID,
                plans: plans,
                carryoverReceipts: [receipt],
                nonactivePlanReferences: C57MyDayBackupEnrollmentV1
                    .exactNonactiveReferences(for: plans)
            )
            return Self(
                sourceWorkspaceID: sourceWorkspaceID,
                targetWorkspaceID: targetWorkspaceID,
                sourceReferences: sourceReferences,
                targetReferences: targetReferences,
                sourcePlanRevisionOne: sourcePlanRevisionOne,
                sourcePlanRevisionTwo: sourcePlanRevisionTwo,
                targetPlanRevisionOne: targetPlanRevisionOne,
                targetPlanRevisionTwo: targetPlanRevisionTwo,
                committedAt: committedAt,
                snapshot: snapshot
            )
        }

        func validBindings() throws -> MyDayReplacementValueProjectionV1.Bindings {
            let requirements = try MyDayReplacementValueProjectionV1.requirements(
                for: .init(snapshot: snapshot)
            )
            let targets = Dictionary(uniqueKeysWithValues: targetReferences.map {
                ($0.stableKey, $0)
            })
            return MyDayReplacementValueProjectionV1.Bindings(
                targetWorkspaceID: targetWorkspaceID,
                eligibleReferences: try requirements.eligibleReferences.map { source in
                    MyDayReplacementValueProjectionV1.EligibleReferenceBinding(
                        source: source,
                        target: try XCTUnwrap(targets[source.stableKey])
                    )
                },
                mutationIDs: try requirements.mutationIDs.enumerated().map { index, source in
                    MyDayReplacementValueProjectionV1.MutationIDBinding(
                        source: source,
                        target: try Fixture.mutation(8_000 + index)
                    )
                }
            )
        }

        /// Unrelated source-workspace history (distinct plan identities) with
        /// a carryover receipt, used to prove replacement leaves it untouched.
        func sourceWorkspaceBystanderSnapshot() throws -> MyDayBackupSnapshotV1 {
            let items = sourcePlanRevisionOne.items
            let origin = try Fixture.plan(
                planID: Fixture.id(7_900),
                key: try Fixture.key(workspaceID: sourceWorkspaceID, date: "2026-09-20"),
                items: items,
                revision: 1,
                mutationID: try Fixture.mutation(7_901),
                actor: sourcePlanRevisionOne.authoredBy,
                authoredAt: committedAt
            )
            let destination = try Fixture.plan(
                planID: Fixture.id(7_902),
                key: try Fixture.key(workspaceID: sourceWorkspaceID, date: "2026-09-21"),
                items: items,
                revision: 1,
                mutationID: try Fixture.mutation(7_903),
                actor: sourcePlanRevisionOne.authoredBy,
                authoredAt: committedAt.addingTimeInterval(1)
            )
            let carryover = try MyDayCarryoverPlanV1(
                sourcePlan: origin,
                targetKey: destination.key,
                membershipIDs: items.map(\.membershipID)
            )
            let receipt = try MyDayCarryoverReceiptV1(
                plan: carryover,
                source: origin,
                target: destination,
                mutationID: destination.mutationID,
                committedAt: committedAt.addingTimeInterval(2)
            )
            let plans = [origin, destination]
            return try MyDayBackupSnapshotV1(
                workspaceID: sourceWorkspaceID,
                plans: plans,
                carryoverReceipts: [receipt],
                nonactivePlanReferences: C57MyDayBackupEnrollmentV1
                    .exactNonactiveReferences(for: plans)
            )
        }

        static func workspace(_ value: Int) -> WorkspaceID {
            WorkspaceID(rawValue: id(value))
        }

        static func id(_ value: Int) -> UUID {
            UUID(uuidString: String(format: "c5720000-0000-4000-8000-%012x", value))!
        }

        static func digest(_ value: Character) -> String {
            String(repeating: String(value), count: 64)
        }

        static func mutation(_ value: Int) throws -> MutationIDV1 {
            try MutationIDV1(rawValue: id(value))
        }

        static func actor(
            _ value: Int,
            workspaceID: WorkspaceID,
            at: Date = Fixture.instant
        ) throws -> ActorSnapshotV1 {
            let actor = try LocalActorReferenceV1(
                actorReferenceID: id(1_000 + value),
                workspaceID: workspaceID,
                partyID: id(2_000 + value),
                displayName: "C57 replacement recorder \(value)"
            )
            return try ActorSnapshotV1(
                snapshotID: id(3_000 + value),
                workspaceID: workspaceID,
                actor: actor,
                responsibility: .recordedBy,
                displayNameAtTime: actor.displayName,
                capturedAt: at
            )
        }

        static func key(workspaceID: WorkspaceID, date: String) throws -> MyDayKeyV1 {
            try MyDayKeyV1(
                workspaceID: workspaceID,
                civilDate: try ScheduleLocalDateV1(date),
                ianaTimeZoneIdentifier: "America/New_York"
            )
        }

        static func plan(
            planID: UUID,
            key: MyDayKeyV1,
            items: [MyDayItemV1],
            predecessor: MyDayPlanV1? = nil,
            revision: UInt64,
            mutationID: MutationIDV1,
            actor: ActorSnapshotV1,
            authoredAt: Date
        ) throws -> MyDayPlanV1 {
            try MyDayPlanV1(
                planID: planID,
                key: key,
                items: items,
                predecessor: predecessor,
                revision: revision,
                mutationID: mutationID,
                authoredBy: actor,
                authoredAt: authoredAt
            )
        }

        static func workPacketReference(
            _ value: Int,
            workspaceID: WorkspaceID,
            actor: ActorSnapshotV1,
            mutationID: MutationIDV1,
            manifestID: UUID? = nil
        ) throws -> MyDayEligibleReferenceV1 {
            let item = try WorkPacketItemV1(
                itemID: "replacement-item-\(value)",
                kind: .inspection,
                expectedRevision: 1,
                itemSHA256: digest("9")
            )
            let manifest = try WorkPacketManifestV1(
                manifestID: manifestID ?? id(4_000 + value),
                packetID: id(5_000 + value),
                packetVersion: 2,
                workspaceID: workspaceID,
                items: [item],
                packageReleases: [],
                creationBasis: .explicitLocalSelection,
                creator: actor,
                createdAt: instant,
                mutationID: mutationID
            )
            return .workPacket(try WorkPacketManifestReferenceV1(manifest))
        }
    }
}

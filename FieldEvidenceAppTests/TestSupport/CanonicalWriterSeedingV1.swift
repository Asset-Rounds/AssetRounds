import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

/// Shared fixture seeding through the sole canonical writer.
///
/// Revisioned rows inserted straight into a context before the mutation
/// journal exists have no entity-revision rows, so the journal's bootstrap
/// semantic checkpoint correctly rejects them (`receiptHistoryCorrupt`).
/// Fixtures seed such rows only through the writer and its lifecycle
/// adapters, after the empty journal initializes, exactly as production does.
@MainActor
enum CanonicalWriterSeedingV1 {
    struct PromotionIDs {
        let releaseRecordID: UUID
        let sandboxRunID: UUID
        let pointerID: UUID
        let receiptID: UUID
        let mutationID: MutationIDV1
        let actorMutationID: MutationIDV1

        static func fresh() throws -> PromotionIDs {
            try PromotionIDs(releaseRecordID: UUID(), sandboxRunID: UUID(), pointerID: UUID(),
                receiptID: UUID(), mutationID: MutationIDV1(rawValue: UUID()),
                actorMutationID: MutationIDV1(rawValue: UUID()))
        }
    }

    /// Accepts `actor` and promotes `release` as the initial activation of its
    /// package through the production publisher output, sandbox runner and
    /// `PackageEvolutionLifecycleAdapterV1`. Returns the accepted promotion.
    @discardableResult
    static func promotePackage(
        _ release: InspectionPackageReleaseV1,
        workspaceID: WorkspaceID,
        actor: ActorSnapshotV1,
        writer: WorkspaceWriterV1,
        journal: MutationJournalStoreV1,
        context: ModelContext,
        promotedAt: Date,
        ids: PromotionIDs,
        appendActor: Bool = true
    ) async throws -> PromotedPackageReleaseV1 {
        if appendActor {
            _ = try writer.execute(.applyPartyAccountability(.appendActorSnapshot(actor)),
                mutationID: ids.actorMutationID)
        }
        let diff = try PackageSemanticDifferV1.diff(source: release, target: release)
        let adapter = PackageEvolutionLifecycleAdapterV1(writer: writer, journal: journal, modelContext: context)
        let runner = PackageSandboxRunnerV1(activationObserver: SeedingPackageObserver(adapter: adapter))
        let sandbox = try await runner.run(runID: ids.sandboxRunID, workspaceID: workspaceID,
            release: release, semanticDiff: diff,
            exactHead: "f09909cc0f929b55d0079190294f32f623eae718",
            fixtures: try sandboxFixtures(), mutationID: ids.mutationID)
        guard sandbox.disposition == .completePass else {
            throw SeedingFailure.sandboxDidNotPass
        }
        let promoted = try PromotedPackageReleaseV1(releaseRecordID: ids.releaseRecordID,
            workspaceID: workspaceID, packageRelease: release, mutationID: ids.mutationID,
            promotedAt: promotedAt)
        let pointer = try ActivePackageRegistryPointerV1(pointerID: ids.pointerID, workspaceID: workspaceID,
            packageID: release.packageID, activeReleaseRecordID: promoted.releaseRecordID,
            promotionReceiptID: ids.receiptID, activePackageReleaseID: release.packageReleaseID,
            activeReleaseRecordSHA256: promoted.releaseRecordSHA256, revision: 1, mutationID: ids.mutationID)
        let receipt = try PackagePromotionReceiptV1(receiptID: ids.receiptID, workspaceID: workspaceID,
            promotedRelease: promoted, sandboxRun: sandbox, diff: diff, predecessorPointer: nil,
            resultingPointer: pointer, actor: actor, exactHead: sandbox.exactHead,
            operation: .initialActivation, rollbackCompatibility: .activatedForwardFixRequired,
            mutationID: ids.mutationID, recordedAt: promotedAt)
        let bundle = PackagePromotionAtomicBundleV1(promotedRelease: promoted, sandboxRun: sandbox,
            semanticDiff: diff, predecessorPointer: nil, resultingPointer: pointer, actor: actor,
            receipt: receipt)
        guard try adapter.applyPromotion(bundle) == receipt else {
            throw SeedingFailure.promotionReceiptMismatch
        }
        return promoted
    }

    /// Appends every distinct actor, promotes `package`, then commits the survey
    /// definition, provisional subject and draft session through the writer,
    /// in the order production requires.
    static func seedSurveySession(
        definition: SurveyDefinitionReleaseV1,
        package: InspectionPackageReleaseV1,
        provisional: ProvisionalSubjectV1,
        session: SurveySessionV1,
        promotionActor: ActorSnapshotV1,
        writer: WorkspaceWriterV1,
        journal: MutationJournalStoreV1,
        context: ModelContext,
        promotedAt: Date
    ) async throws {
        var actors: [UUID: ActorSnapshotV1] = [:]
        for value in [promotionActor, definition.authoredBy, provisional.createdBy,
                      session.startedBy, session.lastTransitionBy] {
            if let prior = actors[value.snapshotID], prior != value { throw SeedingFailure.conflictingActor }
            actors[value.snapshotID] = value
        }
        for value in actors.values.sorted(by: { $0.snapshotID.uuidString < $1.snapshotID.uuidString }) {
            _ = try writer.execute(.applyPartyAccountability(.appendActorSnapshot(value)),
                mutationID: MutationIDV1(rawValue: UUID()))
        }
        try await promotePackage(package, workspaceID: session.workspaceID, actor: promotionActor,
            writer: writer, journal: journal, context: context, promotedAt: promotedAt,
            ids: .fresh(), appendActor: false)
        try commitSurveyDefinitionDraft(definition, writer: writer)
        _ = try writer.commitSurveySession(.init(workspaceID: session.workspaceID,
            mutationID: provisional.mutationID, payload: .applyProvisionalSubject(provisional)))
        _ = try writer.commitSurveySession(.init(workspaceID: session.workspaceID,
            mutationID: session.mutationID, payload: .applySession(session, definition: definition, publication: nil)))
    }

    /// Appends every distinct actor, promotes the system's package release,
    /// then appends the lighting system (no topology relationships) and its
    /// observations through the writer.
    static func seedLightingSystem(
        _ system: LightingSystemV1,
        package: InspectionPackageReleaseV1,
        observations: [LightingObservationV1],
        promotionActor: ActorSnapshotV1,
        writer: WorkspaceWriterV1,
        journal: MutationJournalStoreV1,
        context: ModelContext,
        promotedAt: Date,
        additionalActors: [ActorSnapshotV1] = []
    ) async throws {
        try appendActors([promotionActor, system.recordedBy] + observations.map(\.recordedBy) + additionalActors,
            writer: writer)
        try await promotePackage(package, workspaceID: system.workspaceID, actor: promotionActor,
            writer: writer, journal: journal, context: context, promotedAt: promotedAt,
            ids: .fresh(), appendActor: false)
        _ = try writer.execute(.applyLighting(.appendSystem(value: system, predecessor: nil,
            admission: .init(descriptors: [], relationshipEvents: []))), mutationID: system.mutationID)
        for observation in observations {
            _ = try writer.execute(.applyLighting(.appendObservation(value: observation, predecessor: nil,
                system: system)), mutationID: observation.mutationID)
        }
    }

    /// Seeds everything a C17 night workflow admits against, through the writer:
    /// actors, package promotion, lighting system, day and night observations,
    /// the schedule release and occurrence, the work-packet manifest, and the
    /// night-follow-up planned day. The night workflow itself is left to the test.
    static func seedLightingNightPrerequisites(
        _ fixture: CanonicalLightingFixtureV1.Fixture,
        promotionActor: ActorSnapshotV1,
        writer: WorkspaceWriterV1,
        journal: MutationJournalStoreV1,
        context: ModelContext
    ) async throws {
        try await seedLightingSystem(fixture.system, package: fixture.package,
            observations: [fixture.dayObservation, fixture.nightObservation], promotionActor: promotionActor,
            writer: writer, journal: journal, context: context,
            promotedAt: max(promotionActor.capturedAt, fixture.system.recordedAt),
            additionalActors: [fixture.definition.authoredBy, fixture.schedule.authoredBy,
                               fixture.occurrence.recordedBy, fixture.workPacket.creator,
                               fixture.plannedDay.recordedBy])
        let workspaceID = fixture.system.workspaceID
        try commitSurveyDefinitionDraft(fixture.definition, writer: writer)
        _ = try writer.execute(.applySchedule(ScheduleMutationV1(workspaceID: workspaceID,
            mutationID: fixture.schedule.mutationID, payload: .appendRelease(fixture.schedule, predecessor: nil))),
            mutationID: fixture.schedule.mutationID)
        _ = try writer.execute(.applySchedule(ScheduleMutationV1(workspaceID: workspaceID,
            mutationID: fixture.occurrence.mutationID,
            payload: .appendOccurrenceEvent(fixture.occurrence, predecessor: nil, release: fixture.schedule))),
            mutationID: fixture.occurrence.mutationID)
        let packet = try WorkPacketMutationV1(workspaceID: workspaceID, expectedRevision: 0,
            mutationID: fixture.workPacket.mutationID, postImage: .appendManifest(fixture.workPacket))
        _ = try writer.execute(.applyWorkPacket(packet), mutationID: packet.mutationID)
        _ = try writer.commitLightingDayInventory(.appendWorkflow(value: fixture.plannedDay, predecessor: nil,
            admission: fixture.plannedDayAdmission))
    }

    /// Commits `definition` as a new draft survey definition through the writer.
    static func commitSurveyDefinitionDraft(_ definition: SurveyDefinitionReleaseV1, writer: WorkspaceWriterV1) throws {
        let event = try SurveyDefinitionLifecycleEventV1(eventID: UUID(), workspaceID: definition.workspaceID,
            definitionID: definition.definitionID, action: .createDraft, priorState: nil,
            resultingState: .draft, release: .init(definition), actor: definition.authoredBy,
            recordedAt: definition.authoredAt, revision: 1, mutationID: definition.mutationID)
        let identity = try SurveyDefinitionIdentityV1(definitionID: definition.definitionID,
            workspaceID: definition.workspaceID, activityKind: definition.activityKind, lifecycleState: .draft,
            currentRelease: .init(definition), latestLifecycleEventID: event.eventID,
            latestLifecycleEventSHA256: event.eventSHA256, createdBy: definition.authoredBy,
            createdAt: definition.authoredAt, revision: 1, mutationID: definition.mutationID)
        _ = try writer.commitSurveyDefinition(.init(identity: identity, release: definition, event: event))
    }

    /// Appends each distinct actor snapshot once, in a stable order.
    static func appendActors(_ values: [ActorSnapshotV1], writer: WorkspaceWriterV1) throws {
        var actors: [UUID: ActorSnapshotV1] = [:]
        for value in values {
            if let prior = actors[value.snapshotID], prior != value { throw SeedingFailure.conflictingActor }
            actors[value.snapshotID] = value
        }
        for value in actors.values.sorted(by: { $0.snapshotID.uuidString < $1.snapshotID.uuidString }) {
            _ = try writer.execute(.applyPartyAccountability(.appendActorSnapshot(value)),
                mutationID: MutationIDV1(rawValue: UUID()))
        }
    }

    enum SeedingFailure: Error { case sandboxDidNotPass, promotionReceiptMismatch, conflictingActor }

    private static func sandboxFixtures() throws -> PackageSandboxFixtureMatrixV1 {
        func fixtures(for shape: PackageSandboxFixtureShapeV1) throws -> [PackageSandboxCheckKindV1: PackageSandboxFixtureV1] {
            var values: [PackageSandboxCheckKindV1: PackageSandboxFixtureV1] = [:]
            for kind in PackageSandboxCheckKindV1.allCases {
                let fixtureID = "canonical.seeding.\(shape.rawValue.lowercased()).\(kind.rawValue.lowercased())"
                values[kind] = try PackageSandboxFixtureV1(fixtureID: fixtureID,
                    fixtureSHA256: KernelCanonicalHashV1.sha256(Data(fixtureID.utf8)))
            }
            return values
        }
        return try PackageSandboxFixtureMatrixV1(minimal: fixtures(for: .minimal),
            representative: fixtures(for: .representative))
    }
}

@MainActor
private final class SeedingPackageObserver: PackageSandboxActivationObservingV1 {
    let adapter: PackageEvolutionLifecycleAdapterV1

    init(adapter: PackageEvolutionLifecycleAdapterV1) { self.adapter = adapter }

    func activePointerStateSHA256(workspaceID: WorkspaceID, packageID: String) async throws -> String {
        if let pointer = try adapter.activePointer(workspaceID: workspaceID, packageID: packageID) {
            return pointer.pointerSHA256
        }
        return KernelCanonicalHashV1.sha256(Data("C18_NO_ACTIVE_POINTER".utf8))
    }
}

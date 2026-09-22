import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

/// Exercises only the completed-file SOURCE READ stage. These tests do not
/// publish a completed file, finalize an activity, or exercise rendering.
@MainActor
final class V23ActivityCompletedProductionTests: XCTestCase {
    func testRealWriterReadsPopulatedInstallationAndEntireSelectedProfileWithoutEffects() async throws {
        let h = try CompletedSourceHarness(diagnoseFailures: true)
        defer { h.removeFiles() }
        try await h.populate()
        let before = try h.snapshot()
        let revision = try h.writer.currentRevision()

        let frame = try h.read()
        XCTAssertEqual(frame.expectedRevision, WorkspaceExpectedRevisionV1(snapshot: revision))
        XCTAssertEqual(frame.predecessor, h.activity)
        XCTAssertEqual(frame.transitions, h.transitions)
        XCTAssertEqual(frame.installationBasisHistory, [try XCTUnwrap(h.basis)])
        XCTAssertEqual(frame.taskHistory, h.tasks.sorted())
        XCTAssertEqual(frame.asBuiltHistory, [try XCTUnwrap(h.asBuilt)])
        XCTAssertTrue(frame.punchBasisHistory.isEmpty)
        XCTAssertEqual(frame.shopProfileHistory, [try XCTUnwrap(h.profile)])
        XCTAssertEqual(try frame.shopProfile, h.profile)
        XCTAssertEqual(try frame.shopProfile.brand.orderedBrandLines, ["Field records", "Selected whole profile"])
        XCTAssertEqual(try frame.shopProfile.exportProfile.formats.count, 4)
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<ShopReportProfileRowV1>()), 2)
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<ActivitySessionEnvelopeRow>()), 2)

        // These are actual accepted writer commands, not manufactured receipts.
        let rows = try h.context.fetch(FetchDescriptor<MutationReceiptRow>())
        XCTAssertEqual(rows.count, h.committedMutationIDs.count)
        for mutationID in h.committedMutationIDs {
            let receipt = try XCTUnwrap(h.journal.receipt(mutationID: mutationID))
            XCTAssertEqual(receipt.mutationID, mutationID)
        }
        try ActivityCompletedFileCaptureV1.validateSourceStillCurrent(frame, writer: h.writer)
        XCTAssertEqual(try h.writer.currentRevision(), revision)
        XCTAssertEqual(try h.snapshot(), before)
        XCTAssertFalse(h.context.hasChanges)
    }

    func testCaptureFreezesExactPromotedPackageAndSourceWorkflow() async throws {
        let h = try CompletedSourceHarness(diagnoseFailures: true)
        defer { h.removeFiles() }
        try await h.populate()
        let before = try h.snapshot()
        let frame = try h.read()
        let rows = try h.context.fetch(FetchDescriptor<PromotedPackageReleaseRow>())
        let promoted = try XCTUnwrap(rows.first).value()
        XCTAssertEqual(frame.packageRelease, promoted.packageRelease)
        XCTAssertEqual(frame.packageRelease.state, .published)
        XCTAssertEqual(KernelCanonicalHashV1.sha256(frame.packageRelease.canonicalPackageBytes),
                       frame.packageRelease.packageSHA256)
        XCTAssertEqual(KernelCanonicalHashV1.sha256(frame.packageRelease.canonicalWorkflowBytes),
                       frame.packageRelease.workflowSHA256)
        let package = try InspectionPackageCanonicalCodecV2.decode(frame.packageRelease.canonicalPackageBytes)
        guard case let .installation(source, target) = frame.workflowSource else {
            return XCTFail("Expected actual installation workflow source")
        }
        let reference = try XCTUnwrap(h.basis).workflowReleaseReference
        try reference.validateSource(installation: source, package: package)
        try reference.validateTarget(installation: target, package: package)
        XCTAssertEqual(source, target)
        XCTAssertEqual(try h.snapshot(), before)
    }

    func testHistoricalCompletionRetainsRecordedPackageWithoutCurrentStartPointer() async throws {
        let h = try CompletedSourceHarness(diagnoseFailures: true)
        defer { h.removeFiles() }
        try await h.populate()
        let frame = try h.read()
        for row in try h.context.fetch(FetchDescriptor<ActivePackageRegistryPointerRow>()) {
            h.context.delete(row)
        }
        try h.context.save()
        let before = try h.snapshot()
        let reference = try XCTUnwrap(h.basis).workflowReleaseReference
        XCTAssertThrowsError(try PackageEvolutionLifecycleAdapterV1.resolveActivityWorkflowRelease(
            reference: reference, kind: .installation, forStart: true, modelContext: h.context
        ))
        let historical = try h.read()
        XCTAssertEqual(historical, frame)
        try ActivityCompletedFileCaptureV1.validateSourceStillCurrent(frame, writer: h.writer)
        XCTAssertEqual(try h.snapshot(), before)
    }

    func testMissingRecordedPackageRejectsCaptureAndOldFrameWithoutEffects() async throws {
        let h = try CompletedSourceHarness(diagnoseFailures: true)
        defer { h.removeFiles() }
        try await h.populate()
        let frame = try h.read()
        for row in try h.context.fetch(FetchDescriptor<PromotedPackageReleaseRow>()) {
            h.context.delete(row)
        }
        try h.context.save()
        let before = try h.snapshot()
        XCTAssertThrowsError(try h.read())
        XCTAssertThrowsError(try ActivityCompletedFileCaptureV1.validateSourceStillCurrent(frame, writer: h.writer))
        XCTAssertEqual(try h.snapshot(), before)
        XCTAssertFalse(h.context.hasChanges)
    }

    func testCaptureUsesActualActivityRevisionTransitionsIncludingTaskAndAsBuiltGaps() async throws {
        let h = try CompletedSourceHarness(diagnoseFailures: true)
        defer { h.removeFiles() }
        try await h.populate()
        let frame = try h.read()
        let before = try h.snapshot()
        XCTAssertEqual(frame.transitions.first?.revision, 2)
        XCTAssertEqual(frame.transitions.map(\.revision), [2, 3, 4, 7, 8])
        let transition = try ActivityStateTransitionV2(
            transitionID: CompletedSourceHarness.id(800), workspaceID: h.workspaceID,
            activityID: h.activityID, kind: .installation,
            fromState: .readyForReview, toState: .finalized, actor: h.actor,
            occurredAt: CompletedSourceHarness.date.addingTimeInterval(300),
            revision: frame.predecessor.revision + 1,
            mutationID: CompletedSourceHarness.mutation(801)
        )
        let capture = try ActivityCompletedFileCaptureV1.makeActivityCapture(
            from: frame, completionTransition: transition,
            capturedAt: CompletedSourceHarness.date.addingTimeInterval(250),
            generatedAt: CompletedSourceHarness.date.addingTimeInterval(310)
        )
        XCTAssertEqual(capture.transitionHistory, frame.transitions)
        XCTAssertEqual(capture.resultingActivityRevision, 9)
        XCTAssertEqual(capture.source, try MutationPortableExpectedRevisionV1(frame.expectedRevision))
        let encoded = try JSONEncoder().encode(capture.source)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["writerInstanceID"])
        XCTAssertEqual(try h.snapshot(), before)
    }

    func testWrongWorkspaceMissingActivityAndUnavailableSelectedProfileRejectWithoutEffects() async throws {
        let h = try CompletedSourceHarness(diagnoseFailures: true)
        defer { h.removeFiles() }
        try await h.populate()
        let before = try h.snapshot()
        let revision = try h.writer.currentRevision()
        let selected = try XCTUnwrap(h.profile).reference
        XCTAssertThrowsError(try ActivityCompletedFileCaptureV1.readSource(
            writer: h.writer, workspaceID: WorkspaceID(rawValue: CompletedSourceHarness.id(999)),
            activityID: h.activityID, profile: selected
        )) { XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .wrongWorkspace) }
        XCTAssertThrowsError(try ActivityCompletedFileCaptureV1.readSource(
            writer: h.writer, workspaceID: h.workspaceID,
            activityID: CompletedSourceHarness.id(998), profile: selected
        ))
        let missingProfile = try ShopReportProfileReferenceV1(
            profileID: CompletedSourceHarness.id(997), revision: 1,
            profileSHA256: selected.profileSHA256
        )
        XCTAssertThrowsError(try h.read(profile: missingProfile))
        XCTAssertThrowsError(try h.read(profile: try XCTUnwrap(h.inactiveProfile).reference))
        XCTAssertEqual(try h.writer.currentRevision(), revision)
        XCTAssertEqual(try h.snapshot(), before)
        XCTAssertFalse(h.context.hasChanges)
    }

    func testCommittedProfileChangeRejectsOldSelectionAndFrameWithoutAdoptingNewProfile() async throws {
        let h = try CompletedSourceHarness(diagnoseFailures: true)
        defer { h.removeFiles() }
        try await h.populate()
        let oldFrame = try h.read()
        let oldProfile = try XCTUnwrap(h.profile)
        let next = try h.makeProfile(predecessor: oldProfile, brandName: "Changed shop")
        try h.saveProfile(next)
        h.profile = next
        let before = try h.snapshot()
        let revision = try h.writer.currentRevision()
        XCTAssertThrowsError(try h.read(profile: oldProfile.reference))
        XCTAssertThrowsError(try ActivityCompletedFileCaptureV1.validateSourceStillCurrent(oldFrame, writer: h.writer))
        let current = try h.read()
        XCTAssertEqual(current.shopProfileHistory, [oldProfile, next])
        XCTAssertEqual(try current.shopProfile, next)
        XCTAssertEqual(try h.writer.currentRevision(), revision)
        XCTAssertEqual(try h.snapshot(), before)
    }

    func testWriterInvalidationAndGenerationChangeRejectPreviouslyReadFrameWithoutEffects() async throws {
        for changeGeneration in [false, true] {
            let h = try CompletedSourceHarness(diagnoseFailures: true)
            defer { h.removeFiles() }
            try await h.populate()
            let frame = try h.read()
            let before = try h.snapshot()
            if changeGeneration {
                h.epoch.value = try GenerationEpochV1(
                    generationID: UUID(), generationManifestSHA256: String(repeating: "b", count: 64)
                )
            } else {
                h.writer.invalidate()
            }
            XCTAssertThrowsError(try ActivityCompletedFileCaptureV1.validateSourceStillCurrent(frame, writer: h.writer))
            XCTAssertThrowsError(try h.read())
            XCTAssertEqual(try h.snapshot(), before)
            XCTAssertFalse(h.context.hasChanges)
        }
    }

    func testSameFrontierTaskReplacementAndFamilyInsertionOrRemovalRejectWithoutEffects() async throws {
        for attack in CompletedSourceRowAttack.allCases {
            let h = try CompletedSourceHarness(diagnoseFailures: true)
            defer { h.removeFiles() }
            try await h.populate()
            let frame = try h.read()
            let revision = try h.writer.currentRevision()
            try h.apply(attack)
            let before = try h.snapshot()
            XCTAssertEqual(try h.writer.currentRevision(), revision)
            XCTAssertThrowsError(try h.read(), "Attack: \(attack)")
            XCTAssertThrowsError(try ActivityCompletedFileCaptureV1.validateSourceStillCurrent(frame, writer: h.writer))
            XCTAssertEqual(try h.writer.currentRevision(), revision)
            XCTAssertEqual(try h.snapshot(), before)
            XCTAssertFalse(h.context.hasChanges)
        }
    }

    func testSameFrontierAcceptedReceiptTamperRejectsWithoutEffects() async throws {
        let h = try CompletedSourceHarness(diagnoseFailures: true)
        defer { h.removeFiles() }
        try await h.populate()
        let frame = try h.read()
        let revision = try h.writer.currentRevision()
        let activityMutationID = try XCTUnwrap(h.activity).mutationID.rawValue
        let rows = try h.context.fetch(FetchDescriptor<MutationReceiptRow>())
        let row = try XCTUnwrap(rows.first { $0.mutationID == activityMutationID })
        row.receiptSHA256 = String(repeating: "0", count: 64)
        try h.context.save()
        let before = try h.snapshot()
        XCTAssertEqual(try h.writer.currentRevision(), revision)
        XCTAssertThrowsError(try h.read())
        XCTAssertThrowsError(try ActivityCompletedFileCaptureV1.validateSourceStillCurrent(frame, writer: h.writer))
        XCTAssertEqual(try h.snapshot(), before)
        XCTAssertFalse(h.context.hasChanges)
    }

    func testSameRevisionRehashedProfileCannotReplaceAcceptedBytesEvenWhenSelectedByNewReference() async throws {
        let h = try CompletedSourceHarness(diagnoseFailures: true)
        defer { h.removeFiles() }
        try await h.populate()
        let frame = try h.read()
        let revision = try h.writer.currentRevision()
        let original = try XCTUnwrap(h.profile)
        let replacement = try h.makeProfile(brandName: "Unreceipted shop")
        XCTAssertEqual(replacement.profileID, original.profileID)
        XCTAssertEqual(replacement.revision, original.revision)
        XCTAssertEqual(replacement.mutationID, original.mutationID)
        XCTAssertNotEqual(replacement.profileSHA256, original.profileSHA256)
        let rows = try h.context.fetch(FetchDescriptor<ShopReportProfileRowV1>())
        let row = try XCTUnwrap(rows.first { $0.profileID == original.profileID })
        row.canonicalData = try ShopReportProfileCanonicalCodecV1.encode(replacement)
        row.profileSHA256 = replacement.profileSHA256
        try h.context.save()
        XCTAssertEqual(try row.value(), replacement)
        let before = try h.snapshot()
        XCTAssertEqual(try h.writer.currentRevision(), revision)
        XCTAssertThrowsError(try h.read(profile: replacement.reference))
        XCTAssertThrowsError(try ActivityCompletedFileCaptureV1.validateSourceStillCurrent(frame, writer: h.writer))
        XCTAssertEqual(try h.snapshot(), before)
        XCTAssertFalse(h.context.hasChanges)
    }

    func testQuarantinedActivityOrProfileReceiptCannotAuthorizeSourceRead() async throws {
        for quarantineProfile in [false, true] {
            let h = try CompletedSourceHarness(diagnoseFailures: true)
            defer { h.removeFiles() }
            try await h.populate()
            let frame = try h.read()
            let revision = try h.writer.currentRevision()
            let mutationID: MutationIDV1
            if quarantineProfile { mutationID = try XCTUnwrap(h.profile).mutationID }
            else { mutationID = try XCTUnwrap(h.activity).mutationID }
            let receipt = try XCTUnwrap(h.journal.receipt(mutationID: mutationID))
            h.context.insert(MutationQuarantineRow(workspaceID: h.workspaceID,
                mutationID: mutationID, identityDomain: .mutationEnvelope,
                acceptedIdentitySHA256: receipt.envelopeSHA256,
                conflictingIdentitySHA256: String(repeating: "0", count: 64),
                detectedAt: CompletedSourceHarness.date.addingTimeInterval(300)))
            try h.context.save()
            let before = try h.snapshot()
            XCTAssertEqual(try h.writer.currentRevision(), revision)
            XCTAssertThrowsError(try h.read())
            XCTAssertThrowsError(try ActivityCompletedFileCaptureV1.validateSourceStillCurrent(frame, writer: h.writer))
            XCTAssertEqual(try h.snapshot(), before)
            XCTAssertFalse(h.context.hasChanges)
        }
    }
}

private enum CompletedSourceRowAttack: CaseIterable {
    case changedTask, insertedTask, removedTask, removedAsBuilt, removedTransition, duplicateActivity
}

@MainActor
private final class CompletedSourceEpoch {
    var value: GenerationEpochV1
    init(_ value: GenerationEpochV1) { self.value = value }
}

@MainActor
private final class CompletedSourceHarness {
    static let date = Date(timeIntervalSince1970: 1_800_000_000)
    let root: URL
    let container: ModelContainer
    let context: ModelContext
    let workspaceID: WorkspaceID
    let activityID = CompletedSourceHarness.id(10)
    let actor: ActorSnapshotV1
    let registry: GenerationLeaseRegistryV1
    let lease: GenerationLeaseTokenV1
    let epoch: CompletedSourceEpoch
    let diagnostics: CompletedSourceDiagnostics
    let journal: MutationJournalStoreV1
    let writer: WorkspaceWriterV1
    var activity: ActivitySessionEnvelopeV2?
    var basis: InstallationBasisSnapshotV1?
    var tasks: [InstallationTaskResultV1] = []
    var asBuilt: InstallationAsBuiltSnapshotV1?
    var transitions: [ActivityStateTransitionV2] = []
    var profile: ShopReportProfileV1?
    var inactiveProfile: ShopReportProfileV1?
    var committedMutationIDs: [MutationIDV1] = []

    init(diagnoseFailures: Bool = false) throws {
        let trace = CompletedSourceDiagnostics(enabled: diagnoseFailures)
        diagnostics = trace
        do {
            trace.phase = "init.root"
            root = FileManager.default.temporaryDirectory.appendingPathComponent("completed-source-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            trace.phase = "init.schema"
            let schema = try PersistentSchemaReleaseRegistryV1.activeSchema()
            let configuration = ModelConfiguration("CompletedSource", schema: schema,
                isStoredInMemoryOnly: true, allowsSave: true, cloudKitDatabase: .none)
            trace.phase = "init.container"
            container = try ModelContainer(for: schema, migrationPlan: nil, configurations: [configuration])
            context = container.mainContext
            context.autosaveEnabled = false
            trace.phase = "init.identity"
            workspaceID = WorkspaceID(rawValue: Self.id(1))
            let localActor = try LocalActorReferenceV1(actorReferenceID: Self.id(2), workspaceID: workspaceID, displayName: "Field recorder")
            actor = try ActorSnapshotV1(snapshotID: Self.id(3), workspaceID: workspaceID,
                actor: localActor, responsibility: .recordedBy, displayNameAtTime: "Field recorder", capturedAt: Self.date)
            let identity = try WorkspaceReplicaIdentityV1(workspaceID: workspaceID, replicaID: ReplicaID(rawValue: Self.id(4)))
            let generationID = UUID()
            let initialEpoch = try GenerationEpochV1(generationID: generationID, generationManifestSHA256: String(repeating: "a", count: 64))
            let epochBox = CompletedSourceEpoch(initialEpoch)
            epoch = epochBox
            trace.phase = "init.leaseRegistry"
            registry = try GenerationLeaseRegistryV1(applicationSupportURL: root)
            trace.phase = "init.acquireLease"
            lease = try registry.acquire(epoch: initialEpoch, role: .writer)
            trace.phase = "init.fence"
            let fence = try StaleWriterFenceV1(expectedGenerationEpoch: initialEpoch,
                writerLeaseToken: lease, registry: registry, currentGenerationEpoch: { epochBox.value })
            trace.phase = "init.seedPublishedPackage"
            try Self.seedPublishedPackage(in: context, workspaceID: workspaceID)
            trace.phase = "init.journal"
            journal = try MutationJournalStoreV1(modelContext: context, identity: identity,
                generationID: generationID, staleWriterFence: fence)
            trace.phase = "init.writer"
            let writerID = Self.id(5)
            writer = try WorkspaceWriterV1(identity: identity, generationID: generationID,
                initialRevision: journal.currentRevision(writerInstanceID: writerID), clock: CompletedSourceClock(),
                idSource: CompletedSourceIDs(value: writerID), fileAuthority: CompletedSourceFiles(),
                adapter: WorkspaceWriterAdapterV1(modelContext: context), journalStore: journal)
        } catch {
            trace.record(error)
            throw error
        }
    }

    private static func seedPublishedPackage(in context: ModelContext, workspaceID: WorkspaceID) throws {
        let package = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        // Pre-existing package authority is fixture setup. Use the actual
        // shipping workflow and publisher; no test-only approval receipt.
        let workflow = try ShippingIlluminatedSignAdapterV1.finalizationWorkflow(from: .illuminatedSignV1, stage: .check)
        let draft = try InspectionPackageReleaseV1.makeDraft(package: package, workflow: workflow)
        let published = try InspectionPackageReleasePublisherV1.publish(InspectionPackageReleasePublisherV1.test(draft)).release
        let promoted = try PromotedPackageReleaseV1(releaseRecordID: Self.id(20), workspaceID: workspaceID,
            packageRelease: published, mutationID: Self.mutation(21), promotedAt: Self.date)
        let pointer = try ActivePackageRegistryPointerV1(pointerID: Self.id(22), workspaceID: workspaceID,
            packageID: published.packageID, activeReleaseRecordID: promoted.releaseRecordID,
            promotionReceiptID: Self.id(23), activePackageReleaseID: published.packageReleaseID,
            activeReleaseRecordSHA256: promoted.releaseRecordSHA256, revision: 1, mutationID: Self.mutation(21))
        context.insert(try PromotedPackageReleaseRow(promoted))
        context.insert(try ActivePackageRegistryPointerRow(pointer))
        try context.save()
    }

    func populate() async throws {
        do {
            diagnostics.phase = "populate.package"
            let package = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
            let packages = try InspectionPackageRegistryV2(packages: [package])
            let selection = try packages.bundledActivityWorkflowRelease(kind: .installation,
                packageID: package.packageID, workspaceID: workspaceID)
            guard case let .installation(release) = selection.release else {
                throw InspectionPackageFailureV2.incompatiblePackage
            }
            diagnostics.phase = "populate.initialBasisAndActivity"
            let seedID = try Self.mutation(100)
            let fallback = try NoPlanFallbackV1(limitation: "Manual subject selection was recorded.")
            let initialBasis = try InstallationBasisSnapshotV1(basisID: Self.id(30), workspaceID: workspaceID,
                activityID: activityID, subjectID: Self.id(11),
                workflowReleaseReference: .init(installation: release, package: package), source: .noPlan(fallback),
                capturedAt: Self.date, revision: 1, mutationID: seedID)
            basis = initialBasis
            var readiness: [ActivityReadinessFacetV1] = []
            for facet in release.readinessPolicy.requiredFacets {
                readiness.append(try .init(facetID: "ready-\(facet.rawValue.lowercased())", kind: facet, disposition: .ready))
            }
            let seed = try ActivitySessionEnvelopeV2(activityID: activityID, workspaceID: workspaceID,
                kind: .installation, state: .draft, reviewState: .notRequested, subjectID: Self.id(11),
                title: "Recorded installation", readiness: readiness, readinessPolicy: .installation(release.readinessPolicy),
                currentBasisReference: .installation(try InstallationBasisReferenceV1(initialBasis)), revision: 1, mutationID: seedID)
            diagnostics.phase = "populate.acceptInitialActivity"
            try await accept(successor: seed, basis: initialBasis)
            diagnostics.phase = "populate.preflightRequired"
            try await move(to: .preflightRequired, slot: 101)
            diagnostics.phase = "populate.ready"
            try await move(to: .ready, slot: 102)
            diagnostics.phase = "populate.inProgress"
            try await move(to: .inProgress, slot: 103)
            diagnostics.phase = "populate.taskValues"
            let taskID = try Self.mutation(104)
            for (index, task) in release.tasks.sorted().enumerated() {
                tasks.append(try InstallationTaskResultV1(resultID: Self.id(200 + index), workspaceID: workspaceID,
                    activityID: activityID, taskID: task.taskID, outcome: .completed,
                    note: "Recorded task \(task.taskID)", revision: 1, mutationID: taskID))
            }
            diagnostics.phase = "populate.acceptTasks"
            try await accept(successor: successor(state: .inProgress, mutationID: taskID), taskResults: tasks)
            diagnostics.phase = "populate.asBuiltValue"
            let asBuiltID = try Self.mutation(105)
            let snapshot = try InstallationAsBuiltSnapshotV1(snapshotID: Self.id(300), workspaceID: workspaceID,
                activityID: activityID, basisReference: InstallationBasisReferenceV1(initialBasis),
                taskResultSHA256s: tasks.map(\.resultSHA256), completion: .completedAsRecorded,
                revision: 1, mutationID: asBuiltID)
            asBuilt = snapshot
            diagnostics.phase = "populate.acceptAsBuilt"
            try await accept(successor: successor(state: .inProgress, mutationID: asBuiltID), asBuilt: snapshot)
            diagnostics.phase = "populate.fieldComplete"
            try await move(to: .fieldComplete, slot: 106)
            diagnostics.phase = "populate.readyForReview"
            try await move(to: .readyForReview, slot: 107)

            // A real unrelated draft and a different inactive profile prove that
            // capture selects the requested activity/profile, not every stored row.
            diagnostics.phase = "populate.unrelatedDraftValue"
            let other = try ActivitySessionEnvelopeV2(activityID: Self.id(400), workspaceID: workspaceID,
                kind: .installation, state: .draft, reviewState: .notRequested, subjectID: Self.id(401),
                title: "Unrelated draft", readiness: [], revision: 1, mutationID: Self.mutation(402))
            let otherMutation = try ActivityContractMutationV2(workspaceID: workspaceID,
                expectedRevision: expected(adding: [.init(kind: .activitySessionEnvelope, id: other.activityID)]),
                mutationID: other.mutationID, successorEnvelope: other)
            diagnostics.phase = "populate.acceptUnrelatedDraft"
            _ = try await writer.commitActivityContract(otherMutation)
            committedMutationIDs.append(other.mutationID)
            diagnostics.phase = "populate.selectedProfileValue"
            let selectedProfile = try makeProfile()
            diagnostics.phase = "populate.acceptSelectedProfile"
            try saveProfile(selectedProfile)
            profile = selectedProfile
            diagnostics.phase = "populate.inactiveProfileValue"
            let inactive = try makeProfile(profileID: Self.id(501), activation: .off)
            diagnostics.phase = "populate.acceptInactiveProfile"
            try saveProfile(inactive)
            inactiveProfile = inactive
        } catch {
            diagnostics.record(error)
            throw error
        }
    }

    func read(profile selection: ShopReportProfileReferenceV1? = nil) throws -> ActivityCompletionSourceFrameV1 {
        diagnostics.phase = "capture.selectedProfileAndSource"
        do {
            let selected: ShopReportProfileReferenceV1
            if let selection { selected = selection }
            else { selected = try XCTUnwrap(profile).reference }
            return try ActivityCompletedFileCaptureV1.readSource(writer: writer, workspaceID: workspaceID,
                activityID: activityID, profile: selected)
        } catch {
            diagnostics.record(error)
            throw error
        }
    }

    func saveProfile(_ value: ShopReportProfileV1) throws {
        let mutation = try ShopReportProfileMutationV1(workspaceID: workspaceID,
            expectedRevision: value.revision - 1, mutationID: value.mutationID, profile: value)
        _ = try writer.commitShopReportProfile(mutation)
        committedMutationIDs.append(value.mutationID)
    }

    func makeProfile(predecessor: ShopReportProfileV1? = nil, profileID suppliedProfileID: UUID? = nil,
                     activation: ShopReportProfileActivationV1 = .on,
                     brandName: String = "Selected shop") throws -> ShopReportProfileV1 {
        let profileID = suppliedProfileID ?? Self.id(500)
        let formats: [ReportProjectionFormatV1] = [.formulaSafeCSV, .openJSON, .pdf, .structuredText]
        var sections: [ReportSectionDefinitionV1] = []
        for (index, sectionID) in ["summary", "evidence", "limitations"].enumerated() {
            sections.append(try ReportSectionDefinitionV1(sectionID: sectionID, version: 1, required: true,
                supportedFormats: formats, privacyClass: .mandatoryPublicTruth, requiresHeading: true,
                requiresTextAlternative: true, order: index))
        }
        let registry = try ReportSectionRegistryV1(registryID: "completed-source-registry", registryVersion: 1, sections: sections)
        let layout = try ReportLayoutProfileV1(profileID: "completed-source-layout", profileRelease: 1,
            audience: .customerSafe, detail: .complete, sectionIDs: sections.map(\.sectionID),
            mediaLayout: .standardGrid, orientation: .portrait, localeIdentifier: "en_US",
            unitsProfileID: "units-si-v1", displayProfileID: "display-v1", registry: registry)
        let export = try ExportProfileV1(exportProfileID: "completed-source-export", exportProfileRelease: 1,
            formats: formats, packaging: .separatePerWorkItem, privacyTransformID: "customer-safe-v1",
            maximumMediaItems: 16, maximumArchiveBytes: 1_024_000)
        let policy = try AudiencePrivacyPolicyV1(policyID: "completed-source-policy", policyVersion: 1,
            audience: .customerSafe, prohibitedCanaries: ["INTERNAL-CANARY"])
        let detail = try EvidenceDetailCardProfileV1(profileID: "completed-source-detail", profileRelease: 1,
            audience: .customerSafe, outputScopeID: "completed-source-output", privacyTransformID: "customer-safe-v1",
            privacyTransformVersion: 1, markupProfileID: "completed-source-markup", markupProfileVersion: 1,
            localeIdentifier: "en_US", displayProfileID: "display-v1", rendererVersion: ReportSemanticProjectorV1.rendererVersion,
            audiencePrivacyPolicy: policy, includedFieldIDs: ["service_request", "service_status"],
            limitationsText: "Recorded facts do not verify capture time, location, or person.")
        let revision = (predecessor?.revision ?? 0) + 1
        let mutationSlot = profileID == Self.id(500) ? 510 + Int(revision) : 520 + Int(revision)
        return try ShopReportProfileV1(workspaceID: workspaceID, profileID: profileID, predecessor: predecessor,
            revision: revision, mutationID: Self.mutation(mutationSlot), activation: activation,
            brand: .init(shopDisplayName: brandName, orderedBrandLines: ["Field records", "Selected whole profile"], accentHexRGB: "#204060"),
            reportLayoutProfile: layout, exportProfile: export, evidenceDetailProfile: detail,
            sectionRegistry: registry, rendererVersion: ReportSemanticProjectorV1.rendererVersion,
            packaging: .separateFiles, recordedBy: actor, recordedAt: Self.date.addingTimeInterval(TimeInterval(revision)))
    }

    private func expected(adding identities: [WorkspaceEntityIdentityV1]) throws -> WorkspaceExpectedRevisionV1 {
        let current = try writer.currentRevision()
        var entities = current.entityRevisions
        for identity in identities where !entities.contains(where: { $0.identity == identity }) {
            entities.append(WorkspaceEntityRevisionV1(identity: identity, revision: 0))
        }
        return try WorkspaceExpectedRevisionV1(workspaceID: current.workspaceID, generationID: current.generationID,
            writerInstanceID: current.writerInstanceID, workspaceRevision: current.revision, entityRevisions: entities)
    }

    private func accept(successor: ActivitySessionEnvelopeV2, transition: ActivityStateTransitionV2? = nil,
                        basis: InstallationBasisSnapshotV1? = nil, taskResults: [InstallationTaskResultV1] = [],
                        asBuilt: InstallationAsBuiltSnapshotV1? = nil) async throws {
        var identities = [try WorkspaceEntityIdentityV1(kind: .activitySessionEnvelope, id: successor.activityID)]
        if let transition { identities.append(try .init(kind: .activityStateTransition, id: transition.transitionID)) }
        for task in taskResults { identities.append(try .init(kind: .installationTaskResult, id: task.resultID)) }
        if let asBuilt { identities.append(try .init(kind: .installationAsBuiltSnapshot, id: asBuilt.snapshotID)) }
        let mutation = try ActivityContractMutationV2(workspaceID: workspaceID, expectedRevision: expected(adding: identities),
            mutationID: successor.mutationID, predecessorEnvelope: activity, successorEnvelope: successor,
            transition: transition, installationBasisSnapshot: basis, installationTaskResults: taskResults,
            installationAsBuiltSnapshot: asBuilt)
        let receipt = try await writer.commitActivityContract(mutation)
        XCTAssertEqual(receipt.mutationID, mutation.mutationID)
        committedMutationIDs.append(mutation.mutationID)
        activity = successor
        if let transition { transitions.append(transition) }
    }

    private func successor(state: ActivityStateV2, mutationID: MutationIDV1) throws -> ActivitySessionEnvelopeV2 {
        let prior = try XCTUnwrap(activity)
        return try ActivitySessionEnvelopeV2(activityID: activityID, workspaceID: workspaceID, kind: .installation,
            state: state, reviewState: state == .readyForReview ? .pending : .notRequested,
            subjectID: prior.subjectID, title: prior.title, readiness: prior.readiness, readinessPolicy: prior.readinessPolicy,
            currentBasisReference: prior.currentBasisReference,
            startedAt: prior.startedAt ?? (state.hasStarted ? Self.date.addingTimeInterval(3) : nil),
            revision: prior.revision + 1, mutationID: mutationID, predecessorEnvelopeSHA256: prior.envelopeSHA256)
    }

    private func move(to state: ActivityStateV2, slot: Int) async throws {
        let prior = try XCTUnwrap(activity)
        let next = try successor(state: state, mutationID: Self.mutation(slot))
        let transition = try ActivityStateTransitionV2(transitionID: Self.id(slot + 1000), workspaceID: workspaceID,
            activityID: activityID, kind: .installation, fromState: prior.state, toState: state,
            actor: actor, occurredAt: Self.date.addingTimeInterval(TimeInterval(next.revision)),
            revision: next.revision, mutationID: next.mutationID)
        try await accept(successor: next, transition: transition)
    }

    func apply(_ attack: CompletedSourceRowAttack) throws {
        switch attack {
        case .changedTask:
            let old = try XCTUnwrap(tasks.first)
            let changed = try InstallationTaskResultV1(resultID: old.resultID, workspaceID: old.workspaceID,
                activityID: old.activityID, taskID: old.taskID, outcome: old.outcome,
                note: "Unreceipted replacement", revision: old.revision, mutationID: old.mutationID)
            let rows = try context.fetch(FetchDescriptor<InstallationTaskResultRow>())
            let row = try XCTUnwrap(rows.first { $0.resultID == old.resultID })
            row.canonicalData = try InstallationTaskResultRow(changed).canonicalData
            row.resultSHA256 = changed.resultSHA256
            XCTAssertEqual(try row.value(), changed)
        case .insertedTask:
            let extra = try InstallationTaskResultV1(resultID: Self.id(900), workspaceID: workspaceID,
                activityID: activityID, taskID: "unreceipted-task", outcome: .completed,
                revision: 1, mutationID: Self.mutation(901))
            context.insert(try InstallationTaskResultRow(extra))
        case .removedTask:
            context.delete(try XCTUnwrap(context.fetch(FetchDescriptor<InstallationTaskResultRow>()).first))
        case .removedAsBuilt:
            context.delete(try XCTUnwrap(context.fetch(FetchDescriptor<InstallationAsBuiltSnapshotRow>()).first))
        case .removedTransition:
            context.delete(try XCTUnwrap(context.fetch(FetchDescriptor<ActivityStateTransitionRow>()).first))
        case .duplicateActivity:
            let row = try ActivitySessionEnvelopeRow(XCTUnwrap(activity))
            // Distinct unique storage key retains duplicate requested identity.
            row.stableIdentity += "-duplicate"
            context.insert(row)
        }
        try context.save()
    }

    /// Byte/index snapshots remain readable even after deliberately corrupting
    /// a row; no validation or writer method is substituted to assert no effect.
    func snapshot() throws -> [[String]] {
        var groups: [[String]] = []
        groups.append(try context.fetch(FetchDescriptor<ActivitySessionEnvelopeRow>()).map { $0.stableIdentity + "|" + $0.envelopeSHA256 + "|" + $0.canonicalData.base64EncodedString() })
        groups.append(try context.fetch(FetchDescriptor<ActivityStateTransitionRow>()).map { $0.transitionSHA256 + "|" + $0.canonicalData.base64EncodedString() })
        groups.append(try context.fetch(FetchDescriptor<InstallationTaskResultRow>()).map { $0.resultSHA256 + "|" + $0.canonicalData.base64EncodedString() })
        groups.append(try context.fetch(FetchDescriptor<InstallationAsBuiltSnapshotRow>()).map { $0.snapshotSHA256 + "|" + $0.canonicalData.base64EncodedString() })
        groups.append(try context.fetch(FetchDescriptor<PunchReviewBasisSnapshotRow>()).map { $0.basisSHA256 + "|" + $0.canonicalData.base64EncodedString() })
        groups.append(try context.fetch(FetchDescriptor<ShopReportProfileRowV1>()).map { $0.rowID + "|" + $0.profileSHA256 + "|" + $0.canonicalData.base64EncodedString() })
        groups.append(try context.fetch(FetchDescriptor<PromotedPackageReleaseRow>()).map { $0.canonicalSHA256 + "|" + $0.canonicalData.base64EncodedString() })
        groups.append(try context.fetch(FetchDescriptor<ActivePackageRegistryPointerRow>()).map { $0.canonicalSHA256 + "|" + $0.canonicalData.base64EncodedString() })
        let receipts = try context.fetch(FetchDescriptor<MutationReceiptRow>())
        var receiptRows: [String] = []
        for row in receipts {
            let values = [row.workspaceMutationKey, row.receiptIdentity, row.commandKind, row.envelopeSHA256,
                row.receiptSHA256, row.envelopeData.base64EncodedString(), row.receiptData.base64EncodedString()]
            receiptRows.append(values.joined(separator: "|"))
        }
        groups.append(receiptRows)
        groups.append(try context.fetch(FetchDescriptor<MutationQuarantineRow>()).map {
            "\($0.workspaceMutationKey)|\($0.identityDomain)|\($0.acceptedIdentitySHA256)|\($0.conflictingIdentitySHA256)"
        })
        groups.append(try context.fetch(FetchDescriptor<EntityMutationRevisionRow>()).map { "\($0.stableIdentity)|\($0.revision)" })
        groups.append(try context.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).map { "\($0.workspaceID)|\($0.generationID)|\($0.workspaceRevision)|\($0.lastLocalSequence)|\($0.mutableSemanticSHA256 ?? "")" })
        let reports = try context.fetchCount(FetchDescriptor<Report>())
        let evidence = try context.fetchCount(FetchDescriptor<EvidenceFile>())
        groups.append(["reports=\(reports)", "evidence=\(evidence)"])
        return groups.map { $0.sorted() }
    }

    func removeFiles() {
        try? registry.release(lease)
        try? FileManager.default.removeItem(at: root)
    }

    static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "c0600000-0000-4000-8000-%012d", slot))!
    }
    static func mutation(_ slot: Int) throws -> MutationIDV1 { try MutationIDV1(rawValue: id(slot)) }
}

private struct CompletedSourceClock: ApplicationClock {
    func now() -> Date { Date(timeIntervalSince1970: 1_800_000_200) }
}
private struct CompletedSourceIDs: ApplicationIDSource {
    let value: UUID
    func makeID() -> UUID { value }
}
private struct CompletedSourceFiles: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String {
        "completed-source/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

/// Test-only provenance. Disabled unless the affected native case opts in.
/// Recording neither changes the error nor supplies file-protection authority.
@MainActor
private final class CompletedSourceDiagnostics {
    let enabled: Bool
    var phase: String = "notStarted"

    init(enabled: Bool) { self.enabled = enabled }

    func record(_ error: Error) {
        guard enabled else { return }
        let failure = error as NSError
        let errorType: String = String(reflecting: type(of: error))
        let facts: String = "CompletedSourceDiagnostic phase=\(phase)"
            + " type=\(errorType) domain=\(failure.domain) code=\(failure.code)"
            + " error=\(String(describing: error))"
        FileHandle.standardError.write(Data((facts + "\n").utf8))
        XCTContext.runActivity(named: "Completed source failure provenance") { activity in
            let attachment = XCTAttachment(string: facts)
            attachment.name = "completed-source-failure-provenance"
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }
}

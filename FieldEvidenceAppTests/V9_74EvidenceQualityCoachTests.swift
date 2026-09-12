import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V9_74EvidenceQualityCoachTests: XCTestCase {
    func testBackupEnrollmentPreservesOptionalBoundaryAndRejectsDecodedProvenanceTampering() throws {
        let fixture = try C10ProductionFixture()
        let populated = try fixture.physicalBackupSnapshot()
        XCTAssertEqual(populated.ruleSets.count, 1)
        let empty = try EvidenceQualityBackupSnapshotV1(ruleSets: [], assessments: [], waivers: [],
            receipts: [], effectProvenance: [])
        func records(_ version: Int, _ snapshot: EvidenceQualityBackupSnapshotV1?) -> V4BackupRecordsV1 {
            V4BackupRecordsV1(assets: [], deletionLedger: .empty, evidenceFiles: [], issues: [],
                packets: [], partyAccountability: [], recordsSchemaVersion: version,
                reports: [], sites: [], workflowRecords: [], evidenceQuality: snapshot)
        }
        for version in [45, 46, 52] {
            XCTAssertNoThrow(try EvidenceQualityBackupEnrollmentV1.validate(records(version, nil)))
        }
        for value in [empty, populated] {
            XCTAssertThrowsError(try EvidenceQualityBackupEnrollmentV1.validate(records(45, value)))
            XCTAssertNoThrow(try EvidenceQualityBackupEnrollmentV1.validate(records(46, value)))
            XCTAssertNoThrow(try EvidenceQualityBackupEnrollmentV1.validate(records(52, value)))
        }
        XCTAssertEqual(EvidenceQualityBackupEnrollmentV1.durableFamilyCount, 4)
        let original = try JSONEncoder().encode(populated)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var provenance = try XCTUnwrap(object["effectProvenance"] as? [[String: Any]])
        provenance[0]["writerInstanceID"] = "00000000-0000-0000-0000-000000000000"
        object["effectProvenance"] = provenance
        let zeroWriter = try JSONDecoder().decode(EvidenceQualityBackupSnapshotV1.self, from:
            JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        XCTAssertThrowsError(try zeroWriter.validate()) {
            XCTAssertEqual($0 as? EvidenceQualityPersistenceFailureV1, .corruptRow)
        }
        object["effectProvenance"] = []
        let missing = try JSONDecoder().decode(EvidenceQualityBackupSnapshotV1.self, from:
            JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        XCTAssertThrowsError(try missing.validate()) {
            XCTAssertEqual($0 as? EvidenceQualityPersistenceFailureV1, .receiptMismatch)
        }
        XCTAssertEqual(try fixture.physicalBackupSnapshot(), populated)
    }

    func testEveryUnavailableCoachStateRendersWithoutAcceptingOrRetakingEvidence() throws {
        let states: [EvidenceQualityCoachView.UnavailableState] = [
            .unavailable, .corrupt, .stale, .cancelled, .protectedData, .offline, .storage
        ]
        var actionCount = 0
        for state in states {
            let view = EvidenceQualityCoachView(
                state: .unavailable(state),
                onRetake: { actionCount += 1 },
                onAcceptWithReason: { _ in actionCount += 1 },
                onCancel: { actionCount += 1 }
            )
            // These OS-owned accessibility preferences require separate runtime evidence.
            .environment(\.dynamicTypeSize, .accessibility3)
            let controller = UIHostingController(rootView: view)
            controller.loadViewIfNeeded()
            let size = controller.sizeThatFits(in: CGSize(width: 390, height: 1_000))
            XCTAssertTrue(size.width.isFinite && size.height.isFinite)
            XCTAssertGreaterThan(size.width, 0)
            XCTAssertGreaterThan(size.height, 0)
            XCTAssertEqual(actionCount, 0)
        }
        // This is native view construction/layout, not pixel or AX acceptance.
    }

    func testWriterBoundConvenienceReplaysExactRequestAndRejectsChangedMutationWithoutEffects() throws {
        let f = try C10ProductionFixture(useActiveSchema: true)
        let verifier: EvidenceQualityCoordinatorV1.ContentIntegrityVerifier = { binding, data in
            !data.isEmpty && binding.contentSHA256 == KernelCanonicalHashV1.sha256(data)
        }
        let coordinator = EvidenceQualityCoordinatorV1(workspaceWriter: f.writer,
            query: { try f.querySource.result(for: $0) }, contentIntegrityVerifier: verifier)
        let primary = f.capture(id: "writer-bound")
        let comparison = f.capture(id: "writer-bound-comparison", bytes: [81, 82, 83, 84])
        let request = try f.request(revision: 1, primary: primary,
            comparison: comparison, collection: [primary, comparison])
        guard case let .assessed(assessment, receipt) = try coordinator.assess(request) else {
            return XCTFail("Actual writer-bound coordinator must persist the assessment")
        }
        let originalRevision = try f.writer.currentRevision()
        let originalSnapshot = try f.querySource.snapshot()
        let originalReceipt = try XCTUnwrap(try f.journal.receipt(mutationID: request.mutationID))
        let rows = try f.context.fetch(FetchDescriptor<MutationReceiptRow>())
        let envelopeBytes = try XCTUnwrap(rows.first { $0.mutationID == request.mutationID.rawValue }).envelopeData
        let envelope = try MutationEnvelopeV1.decodeCanonical(from: envelopeBytes)
        guard case .applyEvidenceQuality(let command) = envelope.command else {
            return XCTFail("Durable envelope must contain the real quality command")
        }
        XCTAssertEqual(command.commandID, request.mutationID.rawValue)
        XCTAssertEqual(command.expectedRevision, request.expectedRevision)
        XCTAssertEqual(command.submittedAt, request.assessedAt)
        XCTAssertEqual(command.payload, .recordAssessment(assessment))
        XCTAssertEqual(try f.writer.evidenceQualityReceipt(for: command), receipt)
        // Both public convenience bindings must recover the same immutable
        // receipt, including a newly constructed model-context coordinator.
        let reopened = EvidenceQualityCoordinatorV1(workspaceWriter: f.writer,
            modelContext: f.context, workspaceID: f.workspaceID,
            contentIntegrityVerifier: verifier)
        for current in [coordinator, reopened] {
            guard case let .assessed(replayedAssessment, replayedReceipt) = try current.assess(request) else {
                return XCTFail("Exact request retry must replay the original assessment")
            }
            XCTAssertEqual(replayedAssessment, assessment)
            XCTAssertEqual(replayedReceipt, receipt)
            let changed = f.capture(id: "writer-bound", bytes: [10, 20, 30, 40])
            let divergent = EvidenceQualityCoordinatorV1.AssessmentRequest(
                assessmentID: request.assessmentID, workspaceID: request.workspaceID,
                primary: changed, duplicateComparison: comparison, collection: [changed, comparison],
                ruleSet: request.ruleSet, assessmentRevision: request.assessmentRevision,
                mutationID: request.mutationID, expectedRevision: request.expectedRevision,
                assessedAt: request.assessedAt)
            XCTAssertThrowsError(try current.assess(divergent))
        }
        XCTAssertEqual(try f.writer.currentRevision(), originalRevision)
        XCTAssertEqual(try f.querySource.snapshot(), originalSnapshot)
        XCTAssertEqual(try f.journal.receipt(mutationID: request.mutationID), originalReceipt)
        let finalRows = try f.context.fetch(FetchDescriptor<MutationReceiptRow>())
        XCTAssertEqual(finalRows.count, 2) // One rule-set publication, one assessment.
        XCTAssertEqual(try XCTUnwrap(finalRows.first { $0.mutationID == request.mutationID.rawValue }).envelopeData, envelopeBytes)
        XCTAssertEqual(try f.context.fetch(FetchDescriptor<EvidenceQualityAssessmentRowV1>()).count, 1)
        XCTAssertFalse(f.context.hasChanges)
    }

    func testV23P04C10G01ClearlyFramedCaptureProducesExactRuleIDsAndThresholdBoundaryResults() throws {
        let f = try C10ProductionFixture()
        let request = try f.request(revision: 1, primary: f.capture(), comparison: f.capture(id: "comparison", bytes: [80, 81, 82, 83]), collection: [f.capture(), f.capture(id: "collection", bytes: [90, 91, 92, 93])])
        XCTAssertFalse(request.expectedRevision.entityRevisions.isEmpty)
        XCTAssertEqual(request.expectedRevision.entityRevisions.last?.identity, try WorkspaceEntityIdentityV1(kind: .evidenceQualityAssessment, id: request.assessmentID))
        XCTAssertEqual(request.expectedRevision.entityRevisions.last?.revision, 0)
        guard case let .assessed(assessment, receipt) = try f.coordinator.assess(request) else { return XCTFail("production assessment expected") }
        XCTAssertEqual(assessment.orderedFindings.map(\.ruleID), ["evidence.quality.blur", "evidence.quality.darkness", "evidence.quality.duplicate", "evidence.quality.framing_reference_sequence", "evidence.quality.required_count", "evidence.quality.resolution"])
        XCTAssertEqual(assessment.orderedFindings.map(\.disposition), Array(repeating: .withinConfiguredBoundary, count: 6))
        XCTAssertTrue(assessment.advisoryOnly); XCTAssertFalse(assessment.altersRequirementComplianceSafetyOrInspectionOutcome)
        for rule in f.ruleSet.orderedRules {
            XCTAssertTrue(rule.comparator.includes(rule.threshold, threshold: rule.threshold))
            XCTAssertFalse(rule.comparator.includes(rule.comparator == .atLeast ? rule.threshold - 1 : rule.threshold + 1, threshold: rule.threshold))
        }
        XCTAssertEqual(receipt.semanticSHA256, assessment.assessmentSHA256)
        XCTAssertNotNil(try f.journal.receipt(mutationID: assessment.mutationID))
        XCTAssertEqual(try f.context.fetch(FetchDescriptor<MutationReceiptRow>()).count, 2)
        XCTAssertEqual(try f.context.fetch(FetchDescriptor<EvidenceQualityRuleSetRowV1>()).count, 1)
        XCTAssertEqual(try f.context.fetch(FetchDescriptor<EvidenceQualityAssessmentRowV1>()).count, 1)
        XCTAssertEqual(try f.context.fetch(FetchDescriptor<EvidenceQualityMutationReceiptRowV1>()).count, 2)
        let query = try EvidenceQualityQueryV1(workspaceID: f.workspaceID, target: .exactAssessment(evidenceID: assessment.evidence.evidenceID, evidenceRevision: assessment.evidence.evidenceRevision, assessmentID: assessment.assessmentID))
        guard case let .assessmentProjection(found) = try f.lifecycle.search(query) else { return XCTFail("real query result expected") }
        XCTAssertEqual(found.projection.assessment, assessment); XCTAssertEqual(found.ruleSet, f.ruleSet)
        let portrait = f.capture(id: "orientation", bytes: [70, 71, 72, 73]), landscape = f.capture(id: "orientation", bytes: [70, 71, 72, 73])
        XCTAssertEqual(portrait.canonicalBytes, landscape.canonicalBytes); XCTAssertEqual(portrait.evidence.contentSHA256, landscape.evidence.contentSHA256)
    }

    func testV23P04C10A01RetakeAcceptWithReasonWaiverBindsExactRevisionAndPreservesEvidence() throws {
        let f = try C10ProductionFixture(), original = f.capture(id: "original", bytes: [100, 101, 102, 103])
        guard case let .assessed(first, _) = try f.coordinator.assess(try f.request(revision: 1, primary: original, comparison: f.capture(id: "first-other"), collection: [original, f.capture(id: "first-extra")])) else { return XCTFail("first assessment expected") }
        XCTAssertEqual(f.coordinator.cancel(), .cancelled)
        let retake = f.capture(id: "original", revision: 2, bytes: [104, 105, 106, 107], blur: 249_999)
        guard case let .retaken(second, _) = try f.coordinator.retake(try f.request(revision: 2, primary: retake, comparison: f.capture(id: "retake-other"), collection: [retake, f.capture(id: "retake-extra")])) else { return XCTFail("retake expected") }
        XCTAssertNotEqual(first.evidence, second.evidence)
        let waiverID = UUID(), waiverEventID = UUID(), mutationID = try f.mutation()
        let request = EvidenceQualityCoordinatorV1.WaiverRequest(waiverEventID: waiverEventID, waiverID: waiverID, assessment: second, selectedRuleIDs: [EvidenceQualityRuleIDV1.blur.rawValue], reason: .retakeNotPossible, limitation: "Access conditions changed before an additional retake.", actor: try f.actor(), recordedAt: f.date.addingTimeInterval(3), predecessor: nil, revision: 1, mutationID: mutationID, expectedRevision: try f.expected(kind: .evidenceQualityWaiverEvent, id: waiverEventID))
        guard case let .acceptedWithReason(waiver, receipt) = try f.coordinator.acceptWithReason(request) else { return XCTFail("reasoned waiver expected") }
        XCTAssertEqual(waiver.assessmentRevision, second.revision); XCTAssertEqual(waiver.assessmentSHA256, second.assessmentSHA256)
        XCTAssertEqual(waiver.evidence, retake.evidence); XCTAssertEqual(waiver.selectedRuleIDs, [EvidenceQualityRuleIDV1.blur.rawValue])
        XCTAssertFalse(waiver.erasesWarnings); XCTAssertFalse(waiver.automaticallyPassesEvidence)
        XCTAssertEqual(receipt.semanticSHA256, waiver.waiverSHA256); XCTAssertNotNil(try f.journal.receipt(mutationID: mutationID))
        XCTAssertEqual(try f.context.fetch(FetchDescriptor<EvidenceQualityWaiverRowV1>()).count, 1)
        XCTAssertEqual(original.canonicalBytes, Data([100, 101, 102, 103])); XCTAssertEqual(f.coordinator.cancel(), .cancelled)
    }

    func testV23P04C10H01ChangedDuplicateCorruptEvidenceInvalidatesAssessmentAndWaiverWithoutAutoPass() throws {
        let f = try C10ProductionFixture(), primary = f.capture(id: "hostile", bytes: [32, 33, 34, 35], blur: 249_999)
        guard case let .assessed(assessment, _) = try f.coordinator.assess(try f.request(revision: 1, primary: primary, comparison: f.capture(id: "hostile-other"), collection: [primary, f.capture(id: "hostile-extra")])) else { return XCTFail("assessment expected") }
        let waiver = try f.waiver(for: assessment), accepted = try f.lifecycle.backup()
        let changed = f.capture(id: "hostile", revision: 2, bytes: [32, 33, 34, 36], blur: 249_999)
        XCTAssertThrowsError(try assessment.validateCurrentEvidence(changed.evidence)); XCTAssertThrowsError(try waiver.validateCurrentEvidence(changed.evidence))
        XCTAssertThrowsError(try f.coordinator.isCurrent(assessment, for: f.capture(id: "hostile", bytes: [32, 33, 34, 36]), ruleSet: f.ruleSet))
        XCTAssertFalse(try f.coordinator.isCurrent(assessment, for: primary, ruleSet: f.successorRuleSet()))
        XCTAssertThrowsError(try f.coordinator.preview(try f.request(revision: 2, primary: primary, comparison: primary, collection: [primary])))
        XCTAssertThrowsError(try f.coordinator.isCurrent(assessment, for: f.capture(id: "hostile", bytes: []), ruleSet: f.ruleSet))
        XCTAssertThrowsError(try f.lifecycle.search(EvidenceQualityQueryV1(workspaceID: WorkspaceID(), target: .currentRuleSet)))
        XCTAssertThrowsError(try f.ruleSet.rule(id: "evidence.quality.unknown", version: "1.0.0")); XCTAssertThrowsError(try f.ruleSet.rule(id: EvidenceQualityRuleIDV1.blur.rawValue, version: "9.9.9"))
        XCTAssertThrowsError(try EvidenceQualityRuleInputV1(rule: f.ruleSet.orderedRules[0], measuredValue: EvidenceQualityLimitsV1.maximumMetricValue + 1, subject: primary.evidence))
        XCTAssertThrowsError(try f.lifecycle.replaceRestore(Data("corrupt".utf8))); XCTAssertEqual(try f.lifecycle.backup(), accepted)
        XCTAssertFalse(assessment.altersRequirementComplianceSafetyOrInspectionOutcome); XCTAssertFalse(waiver.automaticallyPassesEvidence)
    }

    func testV23P04C10I01InterruptedAssessmentOrRetakePreservesOriginalWithoutPartialWaiver() throws {
        let interrupted = try C10ProductionFixture(failOnceAt: .afterEffectBeforeReceipt), interruptedPrimary = interrupted.capture(id: "effect-before-receipt", bytes: [35, 36, 37, 38], blur: 249_999)
        let interruptedRequest = try interrupted.request(revision: 1, primary: interruptedPrimary, comparison: interrupted.capture(id: "effect-other"), collection: [interruptedPrimary, interrupted.capture(id: "effect-extra")])
        XCTAssertThrowsError(try interrupted.lifecycle.replay(try interrupted.assessmentCommand(for: interruptedRequest)))
        try MutationReceiptRecoveryServiceV1(store: interrupted.journal).recoverEvidenceQualityEffectsBeforeWriterActivation()
        XCTAssertEqual(try interrupted.context.fetch(FetchDescriptor<EvidenceQualityAssessmentRowV1>()).count, 0)
        XCTAssertEqual(try interrupted.context.fetch(FetchDescriptor<EvidenceQualityWaiverRowV1>()).count, 0)

        let f = try C10ProductionFixture(failOnceAt: .afterSaveBeforeReturn), primary = f.capture(id: "interrupted", bytes: [40, 41, 42, 43], blur: 249_999)
        let request = try f.request(revision: 1, primary: primary, comparison: f.capture(id: "interrupt-other"), collection: [primary, f.capture(id: "interrupt-extra")])
        XCTAssertEqual(f.coordinator.cancel(), .cancelled)
        let command = try f.assessmentCommand(for: request)
        XCTAssertThrowsError(try f.lifecycle.replay(command))
        try MutationReceiptRecoveryServiceV1(store: f.journal).recoverEvidenceQualityEffectsBeforeWriterActivation()
        let recovered = try f.lifecycle.replay(command)
        XCTAssertEqual(recovered.recoveryState, .receiptCommitted); XCTAssertNotNil(try f.journal.receipt(mutationID: command.mutationID))
        XCTAssertEqual(try f.context.fetch(FetchDescriptor<EvidenceQualityAssessmentRowV1>()).count, 1)
        XCTAssertEqual(try f.context.fetch(FetchDescriptor<EvidenceQualityWaiverRowV1>()).count, 0)
        XCTAssertEqual(primary.canonicalBytes, Data([40, 41, 42, 43])); XCTAssertEqual(primary.evidence.evidenceRevision, 1)
    }

    func testV23P04C10R01RebuiltAssessmentAndRestorePreserveExactFindingsAndWaiverProvenance() throws {
        let f = try C10ProductionFixture(), primary = f.capture(id: "recovery", bytes: [51, 52, 53, 54], blur: 249_999)
        let request = try f.request(revision: 1, primary: primary, comparison: f.capture(id: "recovery-other"), collection: [primary, f.capture(id: "recovery-extra")])
        guard case let .assessed(assessment, _) = try f.coordinator.assess(request) else { return XCTFail("assessment expected") }
        let waiver = try f.waiver(for: assessment)
        guard case let .rebuilt(rebuilt) = try f.coordinator.rebuild(request) else { return XCTFail("rebuild expected") }
        XCTAssertEqual(rebuilt.orderedFindings, assessment.orderedFindings); XCTAssertEqual(rebuilt.assessmentSHA256, assessment.assessmentSHA256)
        let backup = try f.lifecycle.backup(), decoded = try f.lifecycle.decodeBackup(backup)
        XCTAssertEqual(try f.lifecycle.exportCanonical(), backup); XCTAssertEqual(decoded.ruleSets, [f.ruleSet]); XCTAssertEqual(decoded.assessments, [assessment]); XCTAssertEqual(decoded.waivers, [waiver]); XCTAssertEqual(decoded.receipts.count, 3)
        XCTAssertEqual(try f.lifecycle.migrate(backup, from: EvidenceQualitySchemaV1.schemaVersion), backup)
        let v4 = try EvidenceQualityBackupSnapshotV1(ruleSets: decoded.ruleSets, assessments: decoded.assessments, waivers: decoded.waivers, receipts: decoded.receipts, effectProvenance: [f.ruleSet.mutationID, assessment.mutationID, waiver.mutationID].map { try EvidenceQualityBackupEffectProvenanceV1(mutationID: $0.rawValue, writerInstanceID: UUID()) })
        try v4.validate()
        let migrated = try f.lifecycle.migrate(Data(), from: EvidenceQualitySchemaV1.predecessorSchemaVersion)
        XCTAssertEqual(try f.lifecycle.decodeBackup(migrated), .init(ruleSets: [], assessments: [], waivers: [], receipts: []))
        try f.removeRows(); try f.lifecycle.replaceRestore(backup); XCTAssertEqual(try f.querySource.snapshot(), decoded)
        XCTAssertEqual(try f.context.fetch(FetchDescriptor<EvidenceQualityRuleSetRowV1>()).count, 1); XCTAssertEqual(try f.context.fetch(FetchDescriptor<EvidenceQualityAssessmentRowV1>()).count, 1); XCTAssertEqual(try f.context.fetch(FetchDescriptor<EvidenceQualityWaiverRowV1>()).count, 1); XCTAssertEqual(try f.context.fetch(FetchDescriptor<EvidenceQualityMutationReceiptRowV1>()).count, 3)
        let query = try EvidenceQualityQueryV1(workspaceID: f.workspaceID, target: .exactAssessment(evidenceID: primary.evidence.evidenceID, evidenceRevision: 1, assessmentID: assessment.assessmentID))
        guard case let .assessmentProjection(found) = try f.lifecycle.search(query) else { return XCTFail("restored search expected") }
        XCTAssertEqual(found.projection.assessment, assessment); XCTAssertEqual(found.projection.waiverHistory, [waiver])
        let report = try f.lifecycle.report(); XCTAssertEqual(report.assessmentCount, 1); XCTAssertEqual(report.waiverEventCount, 1); XCTAssertEqual(report.receiptCount, 3); XCTAssertEqual(report.provenance.first?.waiverReasons, [.retakeNotPossible])
        let replayRule = try f.successorRuleSet(), replayCommand = try f.ruleCommand(replayRule)
        XCTAssertEqual(try f.lifecycle.replay(replayCommand), try f.lifecycle.replay(replayCommand))
        XCTAssertEqual(EvidenceQualitySchemaV1.modelTypes.count, 4); XCTAssertTrue(EvidenceQualitySchemaMigrationBoundaryV1.validate())
        try EvidenceQualityWholeSignDeletionPolicyV1.validate(); try EvidenceQualityKernelDeletionEraseEnrollmentV1.validate(); try f.lifecycle.delete(); try f.lifecycle.erase()
        XCTAssertEqual(f.deleteDispositions, [.erase])
    }
}

private struct C10Clock: ApplicationClock { func now() -> Date { Date(timeIntervalSince1970: 1_700_000_100) } }
private struct C10IDSource: ApplicationIDSource { func makeID() -> UUID { UUID() } }
private struct C10FileAuthority: ApplicationFileAuthorityV1 { func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String { "mutation-staging/\(mutationID.rawValue.uuidString.lowercased())/\(component)" } }

/// Test composition of the same current-generation lease, fence and journal
/// APIs used by StoreSessionCoordinator. It never bootstraps a second store.
@MainActor
final class C10C11CurrentWriterBinding {
    let journal: MutationJournalStoreV1
    let writer: WorkspaceWriterV1
    let destinationResolver: C11PersistedAssetDestinationResolver?
    private let lease: GenerationLeaseHandleV1
    private var closed = false

    init(session: StoreGenerationSession, applicationSupportURL: URL,
         destinationAssetID: UUID? = nil) throws {
        let factory = StoreGenerationFactory(applicationSupportURL: applicationSupportURL)
        guard session.storeSchemaRelease == PersistentSchemaReleaseRegistryV1.activeRelease,
              factory.installedGenerationURL(id: session.generationID).standardizedFileURL
                == session.generationRootURL.standardizedFileURL,
              try factory.currentGenerationID() == session.generationID,
              let epoch = session.generationEpoch else {
            throw GenerationLeaseRegistryFailureV1.staleGeneration
        }
        let registry = try factory.makeGenerationLeaseRegistry()
        let handle = try registry.acquireHandle(epoch: epoch, role: .writer)
        do {
            let fence = try factory.makeWriterFence(expectedGenerationEpoch: epoch,
                writerLeaseToken: handle.token, registry: registry)
            let boundJournal = try MutationJournalStoreV1(modelContext: session.modelContext,
                identity: session.workspaceIdentity, generationID: session.generationID,
                allowStateBootstrap: false, staleWriterFence: fence)
            try MutationReceiptRecoveryServiceV1(store: boundJournal).recoverBeforeWriterActivation()
            let resolver = try destinationAssetID.map {
                try C11PersistedAssetDestinationResolver(modelContext: session.modelContext,
                    workspaceID: session.workspaceID, journal: boundJournal, assetID: $0)
            }
            let boundWriter = try WorkspaceWriterV1(identity: session.workspaceIdentity,
                generationID: session.generationID,
                initialRevision: boundJournal.currentRevision(writerInstanceID: UUID()),
                clock: C10Clock(), idSource: C10IDSource(), fileAuthority: C10FileAuthority(),
                adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext,
                    capturePromotionDestinationResolver: resolver), journalStore: boundJournal,
                searchIndexInvalidation: { source in
                    try LocalSearchIndexStoreV1.synchronouslyInvalidateAfterCanonicalCommit(
                        source: source, applicationSupportURL: applicationSupportURL)
                })
            journal = boundJournal; writer = boundWriter
            destinationResolver = resolver; lease = handle
        } catch {
            try handle.close()
            throw error
        }
    }

    func close() throws {
        guard !closed else { return }
        writer.invalidate()
        try lease.close()
        closed = true
    }

    func packageLifecycleDependencies(session: StoreGenerationSession,
        profileRegistry: WorkspacePackageLifecycleProfileRegistryV1) throws -> WorkspacePackageLifecycleDependenciesV1 {
        try .init(workspaceID: session.workspaceID, generationID: session.generationID,
            generationRootURL: session.generationRootURL, writer: writer,
            clock: C10Clock(), idSource: C10IDSource(), fileAuthority: C10FileAuthority(),
            profileRegistry: profileRegistry)
    }
}
@MainActor private final class C10DeletionSink { var values: [EvidenceQualityLifecycleAdapterV1.DeleteDisposition] = [] }

@MainActor
final class C10ProductionFixture {
    let workspaceID: WorkspaceID
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let context: ModelContext
    let journal: MutationJournalStoreV1
    let writer: WorkspaceWriterV1
    let querySource: EvidenceQualitySwiftDataQuerySourceV1
    let lifecycle: EvidenceQualityLifecycleAdapterV1
    let coordinator: EvidenceQualityCoordinatorV1
    let ruleSet: EvidenceQualityRuleSetV1
    private let deletionSink: C10DeletionSink
    private let currentBinding: C10C11CurrentWriterBinding?
    var deleteDispositions: [EvidenceQualityLifecycleAdapterV1.DeleteDisposition] { deletionSink.values }

    init(failOnceAt boundary: MutationJournalFaultBoundaryV1? = nil, useActiveSchema: Bool = false,
         session: StoreGenerationSession? = nil, applicationSupportURL: URL? = nil) throws {
        let modelContext: ModelContext
        let generationID: UUID, identity: WorkspaceReplicaIdentityV1
        let baseJournal: MutationJournalStoreV1, baseWriter: WorkspaceWriterV1
        if let session {
            guard boundary == nil else { throw EvidenceQualityFailureV1.invalidValue }
            let binding = try C10C11CurrentWriterBinding(session: session,
                applicationSupportURL: XCTUnwrap(applicationSupportURL))
            currentBinding = binding
            workspaceID = session.workspaceID; modelContext = session.modelContext
            generationID = session.generationID; identity = session.workspaceIdentity
            baseJournal = binding.journal; baseWriter = binding.writer
        } else {
            currentBinding = nil
            workspaceID = WorkspaceID()
            let schema = try useActiveSchema ? PersistentSchemaReleaseRegistryV1.activeSchema()
                : Schema(PersistentSchemaV47.models, version: PersistentSchemaV47.versionIdentifier)
            let container = try ModelContainer(for: schema, migrationPlan: nil, configurations: [ModelConfiguration("C10Production", schema: schema, isStoredInMemoryOnly: true, allowsSave: true, cloudKitDatabase: .none)])
            modelContext = container.mainContext
            generationID = UUID()
            identity = try WorkspaceReplicaIdentityV1(workspaceID: workspaceID, replicaID: ReplicaID(rawValue: UUID()))
            baseJournal = try MutationJournalStoreV1(modelContext: modelContext, identity: identity, generationID: generationID)
            baseWriter = try WorkspaceWriterV1(identity: identity, generationID: generationID, initialRevision: baseJournal.currentRevision(writerInstanceID: UUID()), clock: C10Clock(), idSource: C10IDSource(), fileAuthority: C10FileAuthority(), adapter: WorkspaceWriterAdapterV1(modelContext: modelContext), journalStore: baseJournal)
        }
        modelContext.autosaveEnabled = false
        let generatedRuleSet = try Self.makeRuleSet(workspaceID: workspaceID, date: date)
        let baseRevision = try baseWriter.currentRevision(), target = try WorkspaceEntityIdentityV1(kind: .evidenceQualityRuleSet, id: generatedRuleSet.ruleSetID)
        let ruleExpected = try WorkspaceExpectedRevisionV1(workspaceID: baseRevision.workspaceID, generationID: baseRevision.generationID, writerInstanceID: baseRevision.writerInstanceID, workspaceRevision: baseRevision.revision, entityRevisions: baseRevision.entityRevisions + [.init(identity: target, revision: 0)])
        let bootstrap = try EvidenceQualityMutationCommandV1(commandID: UUID(), workspaceID: workspaceID, expectedRevision: ruleExpected, mutationID: generatedRuleSet.mutationID, payload: .putRuleSet(generatedRuleSet), submittedAt: date)
        let bootstrapSource = EvidenceQualitySwiftDataQuerySourceV1(modelContext: modelContext, workspaceID: workspaceID)
        let bootstrapLifecycle = EvidenceQualityLifecycleAdapterV1(workspaceWriter: baseWriter, modelContext: modelContext, workspaceID: workspaceID, snapshotRestorer: { _, _ in throw EvidenceQualityFailureV1.invalidValue }, deleteExecutor: { _ in })
        _ = try bootstrapLifecycle.replay(bootstrap)

        let selectedJournal: MutationJournalStoreV1, selectedWriter: WorkspaceWriterV1
        if let boundary {
            selectedJournal = try MutationJournalStoreV1(modelContext: modelContext, identity: identity, generationID: generationID, failureInjection: MutationJournalFailureInjectionV1(failOnceAt: boundary), allowStateBootstrap: false)
            selectedWriter = try WorkspaceWriterV1(identity: identity, generationID: generationID, initialRevision: selectedJournal.currentRevision(writerInstanceID: UUID()), clock: C10Clock(), idSource: C10IDSource(), fileAuthority: C10FileAuthority(), adapter: WorkspaceWriterAdapterV1(modelContext: modelContext), journalStore: selectedJournal)
        } else {
            selectedJournal = baseJournal; selectedWriter = baseWriter
        }
        context = modelContext; journal = selectedJournal; writer = selectedWriter; ruleSet = generatedRuleSet
        querySource = bootstrapSource
        let sink = C10DeletionSink()
        deletionSink = sink
        let productionLifecycle = EvidenceQualityLifecycleAdapterV1(workspaceWriter: selectedWriter, modelContext: modelContext, workspaceID: workspaceID, snapshotRestorer: { [modelContext] snapshot, replace in guard replace else { throw EvidenceQualityFailureV1.invalidValue }; try Self.restore(snapshot, into: modelContext) }, deleteExecutor: { sink.values.append($0) })
        lifecycle = productionLifecycle
        coordinator = EvidenceQualityCoordinatorV1(submit: { [productionLifecycle] in try productionLifecycle.replay($0) }, query: { [productionLifecycle] in try productionLifecycle.search($0) }, receiptLookup: { [modelContext] command in try modelContext.fetch(FetchDescriptor<EvidenceQualityMutationReceiptRowV1>()).map { try $0.value() }.first { $0.mutationID == command.mutationID } }, contentIntegrityVerifier: { binding, data in !data.isEmpty && binding.contentSHA256 == KernelCanonicalHashV1.sha256(data) })
    }

    func capture(id: String = "golden", revision: UInt64 = 1, bytes: [UInt8] = [64, 65, 66, 67], blur: Int64 = 250_000) -> EvidenceQualityCoordinatorV1.CanonicalCapture {
        let data = Data(bytes), binding = try! EvidenceQualityEvidenceBindingV1(workspaceID: workspaceID, evidenceID: id, evidenceRevision: revision, contentID: "content-\(id)-\(revision)", contentSHA256: KernelCanonicalHashV1.sha256(data))
        return .init(evidence: binding, canonicalBytes: data, pixelWidth: 2_000, pixelHeight: 1_000, declaredLumaMillionths: 500_000, declaredLaplacianVarianceMillionths: blur, declaredPerceptualHash: UInt64(revision), declaredReferenceCoverageMillionths: 900_000, referenceSequenceSHA256: String(repeating: "a", count: 64))
    }

    func request(revision: UInt64, primary: EvidenceQualityCoordinatorV1.CanonicalCapture, comparison: EvidenceQualityCoordinatorV1.CanonicalCapture, collection: [EvidenceQualityCoordinatorV1.CanonicalCapture]) throws -> EvidenceQualityCoordinatorV1.AssessmentRequest {
        let id = UUID(), mutationID = try mutation()
        return .init(assessmentID: id, workspaceID: workspaceID, primary: primary, duplicateComparison: comparison, collection: collection, ruleSet: ruleSet, assessmentRevision: revision, mutationID: mutationID, expectedRevision: try expected(kind: .evidenceQualityAssessment, id: id), assessedAt: date.addingTimeInterval(TimeInterval(revision)))
    }

    func expected(kind: WorkspaceEntityKindV1, id: UUID) throws -> WorkspaceExpectedRevisionV1 {
        let current = try writer.currentRevision(), target = try WorkspaceEntityIdentityV1(kind: kind, id: id)
        return try .init(workspaceID: current.workspaceID, generationID: current.generationID, writerInstanceID: current.writerInstanceID, workspaceRevision: current.revision, entityRevisions: current.entityRevisions + [.init(identity: target, revision: 0)])
    }

    func waiver(for assessment: EvidenceQualityAssessmentV1) throws -> EvidenceQualityWaiverV1 {
        let waiverID = UUID(), request = EvidenceQualityCoordinatorV1.WaiverRequest(waiverEventID: UUID(), waiverID: waiverID, assessment: assessment, selectedRuleIDs: [EvidenceQualityRuleIDV1.blur.rawValue], reason: .retakeNotPossible, limitation: "Retake unavailable due to changed access.", actor: try actor(), recordedAt: date.addingTimeInterval(10), predecessor: nil, revision: 1, mutationID: try mutation(), expectedRevision: try expected(kind: .evidenceQualityWaiverEvent, id: waiverID))
        guard case let .acceptedWithReason(value, _) = try coordinator.acceptWithReason(request) else { throw EvidenceQualityFailureV1.invalidValue }
        return value
    }

    func actor() throws -> ActorSnapshotV1 { let actor = try LocalActorReferenceV1(actorReferenceID: UUID(), workspaceID: workspaceID, displayName: "C10 operator"); return try .init(snapshotID: UUID(), workspaceID: workspaceID, actor: actor, responsibility: .recordedBy, displayNameAtTime: "C10 operator", capturedAt: date) }
    func mutation() throws -> MutationIDV1 { try .init(rawValue: UUID()) }
    func closeCurrentWriter() throws { try currentBinding?.close() }

    func capture(evidence: EvidenceFile, generationRootURL: URL, blur: Int64 = 249_999) throws
        -> EvidenceQualityCoordinatorV1.CanonicalCapture {
        let bytes = try Data(contentsOf: generationRootURL.appendingPathComponent(evidence.relativePath))
        guard bytes.count == evidence.byteCount, KernelCanonicalHashV1.sha256(bytes) == evidence.sha256,
              let image = UIImage(data: bytes), let cgImage = image.cgImage else {
            throw EvidenceQualityFailureV1.invalidValue
        }
        let binding = try EvidenceQualityEvidenceBindingV1(workspaceID: workspaceID,
            evidenceID: evidence.id.uuidString.lowercased(), evidenceRevision: 1,
            contentID: evidence.id.uuidString.lowercased(), contentSHA256: evidence.sha256)
        return .init(evidence: binding, canonicalBytes: bytes,
            pixelWidth: cgImage.width, pixelHeight: cgImage.height,
            declaredLumaMillionths: 500_000, declaredLaplacianVarianceMillionths: blur,
            declaredPerceptualHash: 1, declaredReferenceCoverageMillionths: 900_000,
            referenceSequenceSHA256: KernelCanonicalHashV1.sha256(bytes))
    }

    func physicalBackupSnapshot() throws -> EvidenceQualityBackupSnapshotV1 {
        try Self.physicalBackupSnapshot(in: context, workspaceID: workspaceID)
    }

    static func physicalBackupSnapshot(in context: ModelContext, workspaceID: WorkspaceID) throws
        -> EvidenceQualityBackupSnapshotV1 {
        let values = try EvidenceQualitySwiftDataQuerySourceV1(modelContext: context, workspaceID: workspaceID).snapshot()
        let ruleProvenance = try context.fetch(FetchDescriptor<EvidenceQualityRuleSetRowV1>()).map {
            try EvidenceQualityBackupEffectProvenanceV1(mutationID: $0.mutationID, writerInstanceID: $0.writerInstanceID)
        }
        let assessmentProvenance = try context.fetch(FetchDescriptor<EvidenceQualityAssessmentRowV1>()).map {
            try EvidenceQualityBackupEffectProvenanceV1(mutationID: $0.mutationID, writerInstanceID: $0.writerInstanceID)
        }
        let waiverProvenance = try context.fetch(FetchDescriptor<EvidenceQualityWaiverRowV1>()).map {
            try EvidenceQualityBackupEffectProvenanceV1(mutationID: $0.mutationID, writerInstanceID: $0.writerInstanceID)
        }
        return try .init(ruleSets: values.ruleSets, assessments: values.assessments,
            waivers: values.waivers, receipts: values.receipts,
            effectProvenance: ruleProvenance + assessmentProvenance + waiverProvenance)
    }
    func successorRuleSet() throws -> EvidenceQualityRuleSetV1 { try .init(ruleSetID: UUID(), workspaceID: workspaceID, policyVersion: "1.0.1", orderedRules: ruleSet.orderedRules, predecessor: ruleSet, revision: 2, mutationID: try mutation(), recordedAt: date.addingTimeInterval(20)) }
    func ruleCommand(_ value: EvidenceQualityRuleSetV1) throws -> EvidenceQualityMutationCommandV1 { try command(payload: .putRuleSet(value), mutationID: value.mutationID, kind: .evidenceQualityRuleSet, id: value.ruleSetID) }

    func assessmentCommand(for request: EvidenceQualityCoordinatorV1.AssessmentRequest) throws -> EvidenceQualityMutationCommandV1 {
        guard case let .preview(value) = try coordinator.preview(request) else { throw EvidenceQualityFailureV1.invalidValue }
        return try .init(commandID: request.assessmentID, workspaceID: workspaceID, expectedRevision: request.expectedRevision, mutationID: request.mutationID, payload: .recordAssessment(value), submittedAt: request.assessedAt)
    }

    func removeRows() throws {
        try context.fetch(FetchDescriptor<EvidenceQualityRuleSetRowV1>()).forEach { context.delete($0) }; try context.fetch(FetchDescriptor<EvidenceQualityAssessmentRowV1>()).forEach { context.delete($0) }; try context.fetch(FetchDescriptor<EvidenceQualityWaiverRowV1>()).forEach { context.delete($0) }; try context.fetch(FetchDescriptor<EvidenceQualityMutationReceiptRowV1>()).forEach { context.delete($0) }; try context.save()
    }

    private func command(payload: EvidenceQualityMutationPayloadV1, mutationID: MutationIDV1, kind: WorkspaceEntityKindV1, id: UUID) throws -> EvidenceQualityMutationCommandV1 { try .init(commandID: UUID(), workspaceID: workspaceID, expectedRevision: try expected(kind: kind, id: id), mutationID: mutationID, payload: payload, submittedAt: date) }

    private static func restore(_ snapshot: EvidenceQualityLifecycleAdapterV1.Snapshot, into context: ModelContext) throws {
        try EvidenceQualityLifecycleAdapterV1.validate(snapshot)
        try context.fetch(FetchDescriptor<EvidenceQualityRuleSetRowV1>()).forEach { context.delete($0) }; try context.fetch(FetchDescriptor<EvidenceQualityAssessmentRowV1>()).forEach { context.delete($0) }; try context.fetch(FetchDescriptor<EvidenceQualityWaiverRowV1>()).forEach { context.delete($0) }; try context.fetch(FetchDescriptor<EvidenceQualityMutationReceiptRowV1>()).forEach { context.delete($0) }
        let receipts = Dictionary(uniqueKeysWithValues: snapshot.receipts.map { ($0.mutationID, $0) }), writerID = UUID()
        for value in snapshot.ruleSets { context.insert(try EvidenceQualityRuleSetRowV1(restoring: value, receipt: receipts[value.mutationID]!, writerInstanceID: writerID)) }
        let rules = Dictionary(uniqueKeysWithValues: snapshot.ruleSets.map { ($0.ruleSetID, $0) })
        for value in snapshot.assessments { context.insert(try EvidenceQualityAssessmentRowV1(restoring: value, ruleSet: rules[value.ruleSetID]!, receipt: receipts[value.mutationID]!, writerInstanceID: writerID)) }
        let assessments = Dictionary(uniqueKeysWithValues: snapshot.assessments.map { ($0.assessmentID, $0) })
        for value in snapshot.waivers { context.insert(try EvidenceQualityWaiverRowV1(restoring: value, assessment: assessments[value.assessmentID]!, receipt: receipts[value.mutationID]!, writerInstanceID: writerID)) }
        for receipt in snapshot.receipts { context.insert(try EvidenceQualityMutationReceiptRowV1(receipt)) }; try context.save()
    }

    private static func makeRuleSet(workspaceID: WorkspaceID, date: Date) throws -> EvidenceQualityRuleSetV1 {
        let definitions: [(EvidenceQualityRuleKindV1, EvidenceQualityThresholdComparatorV1, Int64, EvidenceQualityMetricUnitV1, EvidenceQualitySeverityV1, EvidenceQualityApplicabilityV1)] = [(.darkness, .atLeast, 500_000, .normalizedLumaMillionths, .caution, .individualCapture), (.blur, .atLeast, 250_000, .laplacianVarianceMillionths, .caution, .individualCapture), (.resolution, .atLeast, 2_000_000, .pixelCount, .strongCaution, .individualCapture), (.duplicate, .atMost, 4, .perceptualHashDistanceBits, .strongCaution, .capturePair), (.framingReferenceSequence, .atLeast, 900_000, .referenceCoverageMillionths, .caution, .referenceSequence), (.requiredCount, .atLeast, 2, .evidenceCount, .notice, .evidenceCollection)]
        let rules = try definitions.map { kind, comparator, threshold, unit, severity, applicability in try EvidenceQualityRuleV1(ruleID: EvidenceQualityRuleIDV1(kind: kind).rawValue, kind: kind, ruleVersion: "1.0.0", comparator: comparator, threshold: threshold, unit: unit, severity: severity, explanationKey: "evidence.quality.explanation.\(kind.rawValue.lowercased())", remedyKey: "evidence.quality.remedy.\(kind.rawValue.lowercased())", applicability: applicability) }
        return try .init(ruleSetID: UUID(), workspaceID: workspaceID, policyVersion: "1.0.0", orderedRules: rules, revision: 1, mutationID: MutationIDV1(rawValue: UUID()), recordedAt: date)
    }
}

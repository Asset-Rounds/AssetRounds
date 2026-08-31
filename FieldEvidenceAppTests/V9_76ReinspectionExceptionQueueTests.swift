import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V9_76ReinspectionExceptionQueueTests: XCTestCase {
    func testV23P04C12G01ChangedOpenExpiredItemsRequireFreshEvidenceAndQueueClearsOnlyOnResolution() throws {
        let f = try C12Fixture()
        let plan = try f.plan(matrix: true)
        let command = try f.command(.putPlan(plan, nil), mutationID: plan.mutationID)
        let receipt = try f.writer.commitReinspectionException(command)
        XCTAssertEqual(receipt.semanticSHA256s, [plan.planSHA256])
        XCTAssertEqual(plan.items.flatMap(\.reasons).sorted { $0.rawValue < $1.rawValue }, ReinspectionSelectionReasonV1.allCases.sorted { $0.rawValue < $1.rawValue })
        XCTAssertTrue(plan.items.filter { !$0.reasons.contains(.policy) }.allSatisfy { $0.completionRequirement != .currentObservationOrAttestation })
        let all = try f.lifecycle.rebuild(try .init())
        XCTAssertEqual(all.count, ExceptionQueueSourceKindV1.allCases.count)
        XCTAssertEqual(Set(all.map { $0.source.kind }), Set(ExceptionQueueSourceKindV1.allCases))
        XCTAssertEqual(all.map { $0.source.severity.rawValue }, all.map { $0.source.severity.rawValue }.sorted(by: >))
        XCTAssertEqual(try f.context.fetch(FetchDescriptor<ReinspectionPlanRowV1>()).map { try $0.value() }, [plan])
        XCTAssertEqual(try f.context.fetch(FetchDescriptor<ReinspectionExceptionMutationReceiptRowV1>()).map { try $0.value() }, [receipt])
        guard case let .plan(queriedPlan) = try f.writer.reinspectionExceptionQuery(
            try .init(workspaceID: f.workspaceID, target: .plan(plan.planID)), providers: f.providers
        ) else { return XCTFail("canonical writer plan query expected") }
        XCTAssertEqual(queriedPlan, plan)
        f.providers.first { $0.registeredSourceKind == .integrityFinding }?.isResolved = true
        XCTAssertEqual(try f.lifecycle.rebuild(try .init()).count, all.count - 1, "only canonical source resolution clears an item")
        XCTAssertEqual(try f.writer.reinspectionExceptionReceipt(for: command), receipt)
    }

    func testV23P04C12A01UnchangedAttestationBindsExactPriorCurrentRevisionsAndPolicy() throws {
        let f = try C12Fixture(), plan = try f.plan(matrix: false)
        _ = try f.commit(.putPlan(plan, nil), mutationID: plan.mutationID)
        let item = try XCTUnwrap(plan.items.first)
        let attestation = try UnchangedAttestationV1(attestationID: UUID(), plan: plan, planItemID: item.itemID,
            reason: .conditionObservedUnchanged, currentObservationBasis: try f.observation(), attestedBy: try f.actor(),
            attestedAt: f.date.addingTimeInterval(1), mutationID: f.mutation())
        let receipt = try f.commit(.recordAttestation(attestation, plan), mutationID: attestation.mutationID)
        XCTAssertEqual(attestation.prior, item.prior); XCTAssertEqual(attestation.current, item.current)
        XCTAssertEqual(attestation.planRevision, plan.revision); XCTAssertEqual(attestation.planSHA256, plan.planSHA256)
        XCTAssertEqual(attestation.policyVersion, plan.policyVersion); XCTAssertEqual(attestation.policySHA256, plan.policySHA256)
        XCTAssertFalse(attestation.createsFreshObservation); XCTAssertFalse(ReinspectionExceptionLifecycleV1.priorEvidenceCreatesFreshObservation)
        XCTAssertEqual(receipt.semanticSHA256s, [attestation.attestationSHA256])
        guard case let .attestation(found) = try f.lifecycle.query(try .init(workspaceID: f.workspaceID, target: .attestation(attestation.attestationID))) else { return XCTFail("typed attestation expected") }
        XCTAssertEqual(found, attestation)
    }

    func testV23P04C12H01ChangedIdentityMissingEvidenceStaleAttestationDuplicateAndForgedDismissalFailClosed() throws {
        let f = try C12Fixture(), plan = try f.plan(matrix: false)
        let exactRetry = try f.command(.putPlan(plan, nil), mutationID: plan.mutationID)
        _ = try f.writer.commitReinspectionException(exactRetry)
        XCTAssertEqual(try f.writer.commitReinspectionException(exactRetry), try f.writer.commitReinspectionException(exactRetry))
        let item = try XCTUnwrap(plan.items.first), otherIdentity = try ReinspectionSourceIdentityV1(workspaceID: f.workspaceID, kind: .finding, sourceID: "changed-identity")
        let wrong = try ReinspectionSourceSnapshotV1(identity: otherIdentity, revision: item.current.revision, sourceSHA256: item.current.sourceSHA256, evidenceSHA256: item.current.evidenceSHA256)
        XCTAssertThrowsError(try wrong.validateResolved(by: f.authority))
        let missingEvidence = try ReinspectionSourceSnapshotV1(identity: item.current.identity, revision: item.current.revision, sourceSHA256: item.current.sourceSHA256, evidenceSHA256: String(repeating: "f", count: 64))
        XCTAssertThrowsError(try missingEvidence.validateResolved(by: f.authority))
        let stalePlan = try f.plan(matrix: false, currentRevision: 99)
        XCTAssertThrowsError(try f.commit(.putPlan(stalePlan, nil), mutationID: stalePlan.mutationID))
        let source = try XCTUnwrap(f.authority.queueSources.first)
        let forgedSource = try ExceptionQueueSourceSnapshotV1(workspaceID: f.workspaceID, kind: source.kind,
            sourceID: source.sourceID, sourceRevision: source.sourceRevision, sourceSHA256: source.sourceSHA256,
            evidenceSHA256: String(repeating: "e", count: 64), severity: source.severity, reasons: source.reasons, deepLink: source.deepLink)
        let forgedAck = try ExceptionQueueAcknowledgementV1(acknowledgementID: UUID(), source: forgedSource,
            disposition: .locallyResolvedProjection, revision: 1, actor: try f.actor(), recordedAt: f.date,
            mutationID: f.mutation())
        XCTAssertThrowsError(try f.commit(.recordAcknowledgement(forgedAck, forgedSource, nil), mutationID: forgedAck.mutationID))
        let acknowledgement = try ExceptionQueueAcknowledgementV1(acknowledgementID: UUID(), source: source,
            disposition: .acknowledged, revision: 1, actor: try f.actor(), recordedAt: f.date, mutationID: f.mutation())
        _ = try f.commit(.recordAcknowledgement(acknowledgement, source, nil), mutationID: acknowledgement.mutationID)
        let duplicate = try ExceptionQueueAcknowledgementV1(acknowledgementID: UUID(), source: source,
            disposition: .acknowledged, revision: 1, actor: try f.actor(), recordedAt: f.date, mutationID: f.mutation())
        XCTAssertThrowsError(try f.commit(.recordAcknowledgement(duplicate, source, nil), mutationID: duplicate.mutationID))
        let capture = try XCTUnwrap(f.authority.queueSources.first { $0.kind == .captureInboxItem })
        XCTAssertThrowsError(try f.authority.resolveExceptionQueueSource(workspaceID: f.workspaceID,
            kind: .relatedWorkSuggestion, sourceID: capture.sourceID, revision: capture.sourceRevision),
            "a reversed related-work pair cannot resolve")
        let missingRelatedWork = ReinspectionExceptionQueueLifecycleAdapterV1(modelContext: f.context,
            workspaceID: f.workspaceID, sourceProviders: f.providers.filter { $0.registeredSourceKind != .relatedWorkSuggestion },
            sourceResolver: f.authority, exceptionSourceResolver: f.authority)
        XCTAssertThrowsError(try missingRelatedWork.rebuild(try .init()), "missing registered related-work authority fails closed")
        XCTAssertEqual(try f.lifecycle.rebuild(try .init(sourceKinds: [.relatedWorkSuggestion])).count, 1)
        XCTAssertEqual(try f.context.fetch(FetchDescriptor<ReinspectionPlanRowV1>()).count, 1)
    }

    func testV23P04C12I01InterruptedPlanQueueRebuildOrAttestationCommitPreservesCanonicalSources() throws {
        for boundary in MutationJournalFaultBoundaryV1.allCases {
            let f = try C12Fixture(failOnceAt: boundary), before = f.authority.queueSources
            let plan = try f.plan(matrix: false), command = try f.command(.putPlan(plan, nil), mutationID: plan.mutationID)
            XCTAssertThrowsError(try f.writer.commitReinspectionException(command))
            XCTAssertEqual(f.authority.queueSources, before)
            try MutationReceiptRecoveryServiceV1(store: f.journal).recoverBeforeWriterActivation()
            XCTAssertEqual(try f.writer.commitReinspectionException(command).recoveryState, .receiptCommitted)
            try f.assertReceiptParity(command)
        }
        for boundary in MutationJournalFaultBoundaryV1.allCases {
            let f = try C12Fixture(), plan = try f.plan(matrix: false)
            _ = try f.commit(.putPlan(plan, nil), mutationID: plan.mutationID)
            let runtime = try f.runtime(failOnceAt: boundary), item = try XCTUnwrap(plan.items.first)
            let attestation = try UnchangedAttestationV1(attestationID: UUID(), plan: plan, planItemID: item.itemID,
                reason: .noRelevantChangeObserved, currentObservationBasis: try f.observation(), attestedBy: try f.actor(),
                attestedAt: f.date.addingTimeInterval(2), mutationID: f.mutation())
            let command = try f.command(.recordAttestation(attestation, plan), mutationID: attestation.mutationID, writer: runtime.writer)
            XCTAssertThrowsError(try runtime.writer.commitReinspectionException(command))
            try MutationReceiptRecoveryServiceV1(store: runtime.journal).recoverBeforeWriterActivation()
            XCTAssertEqual(try runtime.writer.commitReinspectionException(command).recoveryState, .receiptCommitted)
            try f.assertReceiptParity(command, journal: runtime.journal)
            XCTAssertEqual(try runtime.lifecycle.rebuild(try .init()).map(\.source), f.authority.queueSources.sorted(by: C12Fixture.queueOrder))
        }
        let interrupted = try C12Fixture(), related = try XCTUnwrap(interrupted.providers.first { $0.registeredSourceKind == .relatedWorkSuggestion })
        related.failRead = true
        XCTAssertThrowsError(try interrupted.lifecycle.rebuild(try .init()))
        XCTAssertEqual(interrupted.authority.queueSources.count, 9)
        related.failRead = false
        XCTAssertEqual(try interrupted.lifecycle.rebuild(try .init()).count, 9)
    }

    func testV23P04C12R01RestoredCanonicalSourcesRebuildExactQueueDecisionsReasonsAndUnresolvedCounts() throws {
        let f = try C12Fixture(), plan = try f.plan(matrix: false)
        let planReceipt = try f.commit(.putPlan(plan, nil), mutationID: plan.mutationID)
        let source = try XCTUnwrap(f.authority.queueSources.first)
        let acknowledgement = try ExceptionQueueAcknowledgementV1(acknowledgementID: UUID(), source: source,
            disposition: .acknowledged, revision: 1, actor: try f.actor(), recordedAt: f.date, mutationID: f.mutation())
        let acknowledgementReceipt = try f.commit(.recordAcknowledgement(acknowledgement, source, nil), mutationID: acknowledgement.mutationID)
        let rebuilt = try f.lifecycle.rebuild(try .init())
        XCTAssertEqual(rebuilt.count, 9); XCTAssertEqual(rebuilt.first { $0.source == source }?.acknowledgement, acknowledgement)
        let filtered = try f.lifecycle.rebuild(try .init(severities: [.blocking], reasons: [.integrity]))
        XCTAssertTrue(filtered.allSatisfy { $0.source.severity == .blocking && $0.source.reasons.contains(.integrity) })

        let physicalWriterID = UUID()
        let backup = try f.lifecycle.backupSnapshot(effectProvenance: [
            try .init(mutationID: plan.mutationID.rawValue, semanticSHA256: plan.planSHA256, writerInstanceID: physicalWriterID),
            try .init(mutationID: acknowledgement.mutationID.rawValue, semanticSHA256: acknowledgement.acknowledgementSHA256, writerInstanceID: physicalWriterID)
        ])
        try ReinspectionExceptionQueueBackupEnrollmentV1.validate(backup)
        try f.context.delete(model: ReinspectionPlanRowV1.self)
        try f.context.delete(model: ExceptionQueueAcknowledgementRowV1.self)
        try f.context.delete(model: ReinspectionExceptionMutationReceiptRowV1.self)
        try f.context.save()
        XCTAssertTrue(try f.lifecycle.snapshot().plans.isEmpty)
        try f.lifecycle.replaceRestore(backup); try f.context.save()
        let restoredState = try f.lifecycle.snapshot()
        XCTAssertEqual(restoredState.plans, [plan]); XCTAssertEqual(restoredState.acknowledgements, [acknowledgement])
        XCTAssertEqual(try f.lifecycle.rebuild(try .init()).map(\.queueItemID), rebuilt.map(\.queueItemID))
        XCTAssertEqual(ReinspectionAndExceptionSchemaV1.modelTypes.count, 4)
        XCTAssertEqual(ReinspectionAndExceptionSchemaV1.totalSchemaModelCount, 162)
        XCTAssertEqual(PersistentSchemaMigrationPlanV48.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV48.stages.count, 1)
        XCTAssertFalse(ReinspectionExceptionLifecycleV1.queueItemsArePersistent)
        XCTAssertTrue(ReinspectionExceptionLifecycleV1.queueIsRebuiltFromRegisteredCanonicalSources)
        try ReinspectionExceptionKernelDeletionEraseEnrollmentV1.validate()
        try f.context.delete(model: ReinspectionPlanRowV1.self)
        try f.context.delete(model: UnchangedAttestationRowV1.self)
        try f.context.delete(model: ExceptionQueueAcknowledgementRowV1.self)
        try f.context.delete(model: ReinspectionExceptionMutationReceiptRowV1.self)
        try f.context.save()
        try ReinspectionExceptionEraseAllPolicyV1.validatePublishedEmptyGeneration(f.context)
    }
}

private struct C12Clock: ApplicationClock { func now() -> Date { Date(timeIntervalSince1970: 1_700_200_000) } }
private struct C12IDs: ApplicationIDSource { func makeID() -> UUID { UUID() } }
private struct C12Files: ApplicationFileAuthorityV1 { func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String { "mutation-staging/\(mutationID.rawValue.uuidString.lowercased())/\(component)" } }

private final class C12Provider: ExceptionQueueCanonicalSourceProvidingV1 {
    let registeredSourceKind: ExceptionQueueSourceKindV1
    let source: ExceptionQueueSourceSnapshotV1
    var isResolved = false
    var failRead = false
    init(_ source: ExceptionQueueSourceSnapshotV1) { registeredSourceKind = source.kind; self.source = source }
    func unresolvedExceptionSources(workspaceID: WorkspaceID) throws -> [ExceptionQueueSourceSnapshotV1] {
        guard workspaceID == source.workspaceID else { throw ReinspectionExceptionFailureV1.wrongWorkspace }
        if failRead { throw ReinspectionExceptionFailureV1.missingSource }
        return isResolved ? [] : [source]
    }
}

private struct C12ExactAuthority: ReinspectionCanonicalSourceResolvingV1, ExceptionQueueCanonicalSourceResolvingV1 {
    let reinspectionSources: [ReinspectionSourceSnapshotV1]
    let queueSources: [ExceptionQueueSourceSnapshotV1]
    func resolveReinspectionSource(_ identity: ReinspectionSourceIdentityV1, revision: UInt64) throws -> ReinspectionSourceSnapshotV1 {
        guard let exact = reinspectionSources.first(where: { $0.identity == identity && $0.revision == revision }) else { throw ReinspectionExceptionFailureV1.missingSource }
        return exact
    }
    func resolveExceptionQueueSource(workspaceID: WorkspaceID, kind: ExceptionQueueSourceKindV1, sourceID: String, revision: UInt64) throws -> ExceptionQueueSourceSnapshotV1 {
        guard let exact = queueSources.first(where: { $0.workspaceID == workspaceID && $0.kind == kind && $0.sourceID == sourceID && $0.sourceRevision == revision }) else { throw ReinspectionExceptionFailureV1.missingSource }
        return exact
    }
}

@MainActor
private final class C12Fixture {
    let workspaceID: WorkspaceID, date = Date(timeIntervalSince1970: 1_700_200_000)
    let identity: WorkspaceReplicaIdentityV1, generationID: UUID
    let context: ModelContext, journal: MutationJournalStoreV1, writer: WorkspaceWriterV1
    let authority: C12ExactAuthority, providers: [C12Provider]
    let lifecycle: ReinspectionExceptionQueueLifecycleAdapterV1

    init(workspaceID requestedWorkspaceID: WorkspaceID? = nil,
         failOnceAt boundary: MutationJournalFaultBoundaryV1? = nil) throws {
        let workspace = requestedWorkspaceID ?? WorkspaceID(), schema = Schema(PersistentSchemaV49.models, version: PersistentSchemaV49.versionIdentifier)
        let container = try ModelContainer(for: schema, migrationPlan: nil, configurations: [ModelConfiguration("C12Production", schema: schema, isStoredInMemoryOnly: true, allowsSave: true, cloudKitDatabase: .none)])
        let modelContext = container.mainContext; modelContext.autosaveEnabled = false
        var reinspection: [ReinspectionSourceSnapshotV1] = []
        for offset in 0..<ReinspectionSelectionReasonV1.allCases.count {
            let kind = ReinspectionSourceKindV1.allCases[offset % ReinspectionSourceKindV1.allCases.count]
            let priorCharacter = Array("1234567")[offset], currentCharacter = Array("89abcde")[offset]
            let identity = try ReinspectionSourceIdentityV1(workspaceID: workspace, kind: kind, sourceID: "source-\(offset)")
            reinspection.append(try .init(identity: identity, revision: 1, sourceSHA256: String(repeating: priorCharacter, count: 64), evidenceSHA256: String(repeating: "a", count: 64)))
            reinspection.append(try .init(identity: identity, revision: 2, sourceSHA256: String(repeating: currentCharacter, count: 64), evidenceSHA256: String(repeating: "b", count: 64)))
        }
        let queue = try ExceptionQueueSourceKindV1.allCases.enumerated().map { offset, kind in
            try ExceptionQueueSourceSnapshotV1(workspaceID: workspace, kind: kind, sourceID: "exception-\(offset)", sourceRevision: 1,
                sourceSHA256: String(repeating: "c", count: 64), evidenceSHA256: String(repeating: "d", count: 64),
                severity: ExceptionQueueSeverityV1.allCases[offset % ExceptionQueueSeverityV1.allCases.count],
                reasons: [ExceptionQueueReasonV1.allCases[offset % ExceptionQueueReasonV1.allCases.count]],
                deepLink: ExceptionQueueDeepLinkV1.allCases[offset % ExceptionQueueDeepLinkV1.allCases.count])
        }
        let exact = C12ExactAuthority(reinspectionSources: reinspection, queueSources: queue)
        let exactProviders = queue.map(C12Provider.init)
        let generation = UUID(), replica = try WorkspaceReplicaIdentityV1(workspaceID: workspace, replicaID: ReplicaID(rawValue: UUID()))
        let store = try MutationJournalStoreV1(modelContext: modelContext, identity: replica, generationID: generation,
            failureInjection: boundary.map { MutationJournalFailureInjectionV1(failOnceAt: $0) })
        let canonical = try WorkspaceWriterV1(identity: replica, generationID: generation,
            initialRevision: store.currentRevision(writerInstanceID: UUID()), clock: C12Clock(), idSource: C12IDs(), fileAuthority: C12Files(),
            adapter: WorkspaceWriterAdapterV1(modelContext: modelContext, reinspectionCanonicalSourceResolver: exact,
                exceptionQueueCanonicalSourceResolver: exact, exceptionQueueSourceProviders: exactProviders), journalStore: store)
        workspaceID = workspace; identity = replica; generationID = generation; context = modelContext
        journal = store; writer = canonical; authority = exact; providers = exactProviders
        lifecycle = ReinspectionExceptionQueueLifecycleAdapterV1(modelContext: modelContext, workspaceID: workspace,
            sourceProviders: exactProviders, sourceResolver: exact, exceptionSourceResolver: exact)
    }

    func mutation() throws -> MutationIDV1 { try .init(rawValue: UUID()) }
    func actor() throws -> ActorSnapshotV1 { let local = try LocalActorReferenceV1(actorReferenceID: UUID(), workspaceID: workspaceID, displayName: "C12 inspector"); return try .init(snapshotID: UUID(), workspaceID: workspaceID, actor: local, responsibility: .recordedBy, displayNameAtTime: local.displayName, capturedAt: date) }
    func observation() throws -> ObservationBasisV1 { try .init(kind: .directlyObserved, method: try .init(key: "C12_REINSPECTION"), source: try .init(kind: .observer)) }
    func command(_ payload: ReinspectionExceptionMutationPayloadV1, mutationID: MutationIDV1, writer authority: WorkspaceWriterV1? = nil) throws -> ReinspectionExceptionMutationCommandV1 {
        let selected = authority ?? writer
        return try .init(commandID: UUID(), workspaceID: workspaceID, expectedRevision: WorkspaceExpectedRevisionV1(snapshot: try selected.currentRevision()), mutationID: mutationID, payload: payload, submittedAt: date)
    }
    func commit(_ payload: ReinspectionExceptionMutationPayloadV1, mutationID: MutationIDV1) throws -> ReinspectionExceptionMutationReceiptV1 { try writer.commitReinspectionException(try command(payload, mutationID: mutationID)) }
    func plan(matrix: Bool, currentRevision: UInt64 = 2) throws -> ReinspectionPlanV1 {
        let reasons: [[ReinspectionSelectionReasonV1]] = matrix ? ReinspectionSelectionReasonV1.allCases.map { [$0] } : [[.policy]]
        let items = try reasons.enumerated().map { offset, values -> ReinspectionPlanItemV1 in
            let sourcePair = Array(authority.reinspectionSources.dropFirst(offset * 2).prefix(2))
            let prior = sourcePair[0]
            let current: ReinspectionSourceSnapshotV1
            if !matrix && currentRevision == 2 { current = prior }
            else if currentRevision == 2 { current = sourcePair[1] }
            else { current = try ReinspectionSourceSnapshotV1(identity: prior.identity, revision: currentRevision, sourceSHA256: String(repeating: "9", count: 64), evidenceSHA256: String(repeating: "b", count: 64)) }
            let requirement: ReinspectionCompletionRequirementV1 = values.contains(.fullReview) ? .fullReview : (values == [.policy] ? .currentObservationOrAttestation : .freshEvidence)
            return try .init(itemID: UUID(), prior: prior, current: current, reasons: values, completionRequirement: requirement)
        }.sorted { ($0.current.identity.canonicalKey, $0.itemID.uuidString) < ($1.current.identity.canonicalKey, $1.itemID.uuidString) }
        return try .init(planEventID: UUID(), planID: UUID(), workspaceID: workspaceID, revision: 1,
            policyVersion: 7, policySHA256: String(repeating: "7", count: 64), items: items,
            plannedBy: try actor(), plannedAt: date, mutationID: mutation())
    }
    func runtime(failOnceAt boundary: MutationJournalFaultBoundaryV1) throws -> (journal: MutationJournalStoreV1, writer: WorkspaceWriterV1, lifecycle: ReinspectionExceptionQueueLifecycleAdapterV1) {
        let store = try MutationJournalStoreV1(modelContext: context, identity: identity, generationID: generationID, failureInjection: .init(failOnceAt: boundary))
        let authorityWriter = try WorkspaceWriterV1(identity: identity, generationID: generationID,
            initialRevision: store.currentRevision(writerInstanceID: UUID()), clock: C12Clock(), idSource: C12IDs(), fileAuthority: C12Files(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context, reinspectionCanonicalSourceResolver: authority,
                exceptionQueueCanonicalSourceResolver: authority, exceptionQueueSourceProviders: providers), journalStore: store)
        return (store, authorityWriter, ReinspectionExceptionQueueLifecycleAdapterV1(modelContext: context,
            workspaceID: workspaceID, sourceProviders: providers, sourceResolver: authority,
            exceptionSourceResolver: authority))
    }
    func assertReceiptParity(_ command: ReinspectionExceptionMutationCommandV1, journal selected: MutationJournalStoreV1? = nil) throws {
        let selected = selected ?? journal
        let pairs = try selected.reinspectionExceptionRecoveryPairs().filter { $0.command.mutationID == command.mutationID }
        let typed = try context.fetch(FetchDescriptor<ReinspectionExceptionMutationReceiptRowV1>()).map { try $0.value() }.filter { $0.mutationID == command.mutationID }
        XCTAssertEqual(pairs.count, 1); XCTAssertEqual(typed.count, 1); XCTAssertEqual(pairs.first?.receipt, typed.first)
        XCTAssertEqual(typed.first?.semanticSHA256s, try selected.receipt(mutationID: command.mutationID)?.postImages.map(\.semanticSHA256).sorted())
    }
    static func queueOrder(_ lhs: ExceptionQueueSourceSnapshotV1, _ rhs: ExceptionQueueSourceSnapshotV1) -> Bool {
        lhs.severity == rhs.severity ? lhs.logicalExceptionKey < rhs.logicalExceptionKey : lhs.severity.rawValue > rhs.severity.rawValue
    }
}

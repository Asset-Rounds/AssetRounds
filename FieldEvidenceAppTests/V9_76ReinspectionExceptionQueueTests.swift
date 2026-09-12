import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V9_76ReinspectionExceptionQueueTests: XCTestCase {
    func testExceptionQueueProjectionSelectsLatestAcknowledgementAndRejectsDuplicateRevisions() throws {
        let fixture = try C12Fixture()
        let source = try XCTUnwrap(fixture.authority.queueSources.first)
        let first = try fixture.intent(
            source: source,
            acknowledgementID: UUID(uuidString: "8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5761")!
        ).acknowledgement(recordedAt: fixture.date)
        let latest = try fixture.intent(
            source: source,
            predecessor: first,
            disposition: .reopened,
            acknowledgementID: UUID(uuidString: "8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5762")!
        ).acknowledgement(recordedAt: fixture.date.addingTimeInterval(1))

        let projection = try ExceptionQueueProjectionV1(
            workspaceID: fixture.workspaceID,
            registry: try .init(registeredKinds: ExceptionQueueSourceKindV1.allCases.sorted { $0.rawValue < $1.rawValue }),
            sources: fixture.authority.queueSources,
            acknowledgements: [latest, first],
            evaluatedAt: fixture.date.addingTimeInterval(2),
            resolver: fixture.authority
        )
        XCTAssertEqual(
            projection.items.first(where: { $0.source == source })?.acknowledgement,
            latest
        )

        let duplicateLatest = try fixture.intent(
            source: source,
            predecessor: first,
            acknowledgementID: UUID(uuidString: "8B5F1E6D-0A24-4C3F-9F91-7E0D6B2A5763")!
        ).acknowledgement(recordedAt: fixture.date.addingTimeInterval(2))
        XCTAssertThrowsError(try ExceptionQueueProjectionV1(
            workspaceID: fixture.workspaceID,
            registry: try .init(registeredKinds: ExceptionQueueSourceKindV1.allCases.sorted { $0.rawValue < $1.rawValue }),
            sources: fixture.authority.queueSources,
            acknowledgements: [first, latest, duplicateLatest],
            evaluatedAt: fixture.date.addingTimeInterval(3),
            resolver: fixture.authority
        )) { error in
            XCTAssertEqual(error as? ReinspectionExceptionFailureV1, .duplicateIdentity)
        }
    }

    func testV23P04C12G01ChangedOpenExpiredItemsRequireFreshEvidenceAndQueueClearsOnlyOnResolution() throws {
        let f = try C12Fixture()
        let plan = try f.plan(matrix: true)
        let command = try f.command(.putPlan(plan, nil), mutationID: plan.mutationID)
        let receipt = try f.writer.commitReinspectionException(command)
        XCTAssertEqual(receipt.semanticSHA256s, [plan.planSHA256])
        XCTAssertEqual(plan.items.flatMap(\.reasons).sorted { $0.rawValue < $1.rawValue }, ReinspectionSelectionReasonV1.allCases.sorted { $0.rawValue < $1.rawValue })
        XCTAssertTrue(plan.items.filter { !$0.reasons.contains(.policy) }.allSatisfy { $0.completionRequirement != .currentObservationOrAttestation })
        let all = try f.lifecycle.rebuild(try .init(), evaluatedAt: f.date)
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
        XCTAssertEqual(try f.lifecycle.rebuild(try .init(), evaluatedAt: f.date).count, all.count - 1, "only canonical source resolution clears an item")
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
        guard case let .attestation(found) = try f.lifecycle.query(try .init(workspaceID: f.workspaceID, target: .attestation(attestation.attestationID)), evaluatedAt: f.date) else { return XCTFail("typed attestation expected") }
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
        let forgedIntent = try f.intent(source: forgedSource, disposition: .locallyResolvedProjection)
        XCTAssertThrowsError(try f.writer.commitExceptionQueueAcknowledgement(forgedIntent, providers: f.providers))
        let first = try f.writer.commitExceptionQueueAcknowledgement(
            try f.intent(source: source), providers: f.providers
        )
        let duplicate = try f.intent(source: source)
        XCTAssertThrowsError(try f.writer.commitExceptionQueueAcknowledgement(duplicate, providers: f.providers))
        XCTAssertEqual(first.acknowledgement.recordedAt, f.date)
        let capture = try XCTUnwrap(f.authority.queueSources.first { $0.kind == .captureInboxItem })
        XCTAssertThrowsError(try f.authority.resolveExceptionQueueSource(workspaceID: f.workspaceID,
            kind: .relatedWorkSuggestion, sourceID: capture.sourceID, revision: capture.sourceRevision,
            evaluatedAt: f.date),
            "a reversed related-work pair cannot resolve")
        let missingRelatedWork = ReinspectionExceptionQueueLifecycleAdapterV1(modelContext: f.context,
            workspaceID: f.workspaceID, sourceProviders: f.providers.filter { $0.registeredSourceKind != .relatedWorkSuggestion },
            sourceResolver: f.authority, exceptionSourceResolver: f.authority)
        XCTAssertThrowsError(try missingRelatedWork.rebuild(try .init(), evaluatedAt: f.date), "missing registered related-work authority fails closed")
        XCTAssertEqual(try f.lifecycle.rebuild(try .init(sourceKinds: [.relatedWorkSuggestion]), evaluatedAt: f.date).count, 1)
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
            XCTAssertEqual(try runtime.lifecycle.rebuild(try .init(), evaluatedAt: f.date).map(\.source), f.authority.queueSources.sorted(by: C12Fixture.queueOrder))
        }
        let interrupted = try C12Fixture(), related = try XCTUnwrap(interrupted.providers.first { $0.registeredSourceKind == .relatedWorkSuggestion })
        related.failRead = true
        XCTAssertThrowsError(try interrupted.lifecycle.rebuild(try .init(), evaluatedAt: interrupted.date))
        XCTAssertEqual(interrupted.authority.queueSources.count, 9)
        related.failRead = false
        XCTAssertEqual(try interrupted.lifecycle.rebuild(try .init(), evaluatedAt: interrupted.date).count, 9)
    }

    func testV23P04C12R01RestoredCanonicalSourcesRebuildExactQueueDecisionsReasonsAndUnresolvedCounts() throws {
        let f = try C12Fixture(), plan = try f.plan(matrix: false)
        let planReceipt = try f.commit(.putPlan(plan, nil), mutationID: plan.mutationID)
        let source = try XCTUnwrap(f.authority.queueSources.first)
        let acknowledgementResult = try f.writer.commitExceptionQueueAcknowledgement(
            try f.intent(source: source), providers: f.providers
        )
        let acknowledgement = acknowledgementResult.acknowledgement
        let acknowledgementReceipt = acknowledgementResult.receipt
        let rebuilt = try f.lifecycle.rebuild(try .init(), evaluatedAt: f.date)
        XCTAssertEqual(rebuilt.count, 9); XCTAssertEqual(rebuilt.first { $0.source == source }?.acknowledgement, acknowledgement)
        let filtered = try f.lifecycle.rebuild(try .init(severities: [.blocking], reasons: [.integrity]), evaluatedAt: f.date)
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
        XCTAssertEqual(try f.lifecycle.rebuild(try .init(), evaluatedAt: f.date).map(\.queueItemID), rebuilt.map(\.queueItemID))
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

    func testLifecycleSearchRequiresCallerEvaluationTimeForLiveSources() throws {
        let f = try C12Fixture()
        let boundary = f.date.addingTimeInterval(1)
        f.providers[0].availableAt = boundary
        let query = try ReinspectionExceptionQueryV1(workspaceID: f.workspaceID, target: .queue(try .init()))
        for instant in [f.date, boundary.addingTimeInterval(1)] {
            f.authority.trace.provider.removeAll(); f.authority.trace.resolver.removeAll()
            guard case let .queue(values) = try f.lifecycle.search(query, evaluatedAt: instant) else {
                return XCTFail("queue expected")
            }
            let expectedCount = ExceptionQueueSourceKindV1.allCases.count - (instant < boundary ? 1 : 0)
            XCTAssertEqual(values.count, expectedCount)
            XCTAssertEqual(Set(f.authority.trace.provider), Set([instant]))
            XCTAssertEqual(Set(f.authority.trace.resolver), Set([instant]))
        }
        f.authority.trace.provider.removeAll(); f.authority.trace.resolver.removeAll()
        XCTAssertThrowsError(try f.lifecycle.search(query, evaluatedAt: Date(timeIntervalSince1970: .nan)))
        XCTAssertTrue(f.authority.trace.provider.isEmpty)
        XCTAssertTrue(f.authority.trace.resolver.isEmpty)
    }

    func testV23P04C12T01WriterUsesOneEvaluationInstantPerQueryWithoutCaching() throws {
        let f = try C12Fixture()
        let boundary = f.date.addingTimeInterval(1)
        f.providers[0].availableAt = boundary
        f.authority.trace.provider.removeAll(); f.authority.trace.resolver.removeAll()

        f.clock.value = f.date
        let beforeCalls = f.clock.callCount
        guard case let .queue(before) = try f.writer.reinspectionExceptionQuery(
            try .init(workspaceID: f.workspaceID, target: .queue(try .init())), providers: f.providers
        ) else { return XCTFail("queue expected") }
        XCTAssertEqual(before.count, ExceptionQueueSourceKindV1.allCases.count - 1)
        XCTAssertEqual(f.clock.callCount, beforeCalls + 1)
        XCTAssertEqual(Set(f.authority.trace.provider), Set([f.date]))
        XCTAssertEqual(Set(f.authority.trace.resolver), Set([f.date]))

        let after = boundary.addingTimeInterval(1)
        f.authority.trace.provider.removeAll(); f.authority.trace.resolver.removeAll()
        f.clock.value = after
        guard case let .queue(current) = try f.writer.reinspectionExceptionQuery(
            try .init(workspaceID: f.workspaceID, target: .queue(try .init())), providers: f.providers
        ) else { return XCTFail("queue expected") }
        XCTAssertEqual(current.count, ExceptionQueueSourceKindV1.allCases.count)
        XCTAssertEqual(f.clock.callCount, beforeCalls + 2)
        XCTAssertEqual(Set(f.authority.trace.provider), Set([after]))
        XCTAssertEqual(Set(f.authority.trace.resolver), Set([after]))
    }

    func testV23P04C12T02WriterOwnsFirstSeenAcknowledgementAdmissionAndExactIntentReplay() throws {
        let f = try C12Fixture(), source = try XCTUnwrap(f.authority.queueSources.first)
        let bypassMutation = try f.mutation()
        let bypassIntent = try f.intent(source: source, mutationID: bypassMutation)
        let backdated = f.date.addingTimeInterval(-60)
        let prebuilt = try bypassIntent.acknowledgement(recordedAt: backdated)
        let prebuiltCommand = try ReinspectionExceptionMutationCommandV1(
            commandID: UUID(), workspaceID: f.workspaceID,
            expectedRevision: bypassIntent.expectedRevision, mutationID: bypassMutation,
            payload: .recordAcknowledgement(prebuilt, source, nil), submittedAt: backdated
        )
        XCTAssertThrowsError(try f.writer.commitReinspectionException(prebuiltCommand))
        XCTAssertThrowsError(try f.writer.execute(.init(
            mutationID: bypassMutation, expectedRevision: bypassIntent.expectedRevision,
            command: .applyReinspectionException(prebuiltCommand)
        )))
        XCTAssertNil(try f.journal.receipt(mutationID: bypassMutation))
        XCTAssertTrue(try f.context.fetch(FetchDescriptor<ExceptionQueueAcknowledgementRowV1>()).isEmpty)

        let driftIntent = try f.intent(source: source)
        guard case let .queue(preview) = try f.writer.reinspectionExceptionQuery(
            try .init(workspaceID: f.workspaceID, target: .queue(try .init())), providers: f.providers
        ) else { return XCTFail("queue preview expected") }
        XCTAssertTrue(preview.contains { $0.source == source })
        let provider = try XCTUnwrap(f.providers.first { $0.registeredSourceKind == source.kind })
        provider.isResolved = true
        XCTAssertThrowsError(try f.writer.commitExceptionQueueAcknowledgement(driftIntent, providers: f.providers))
        XCTAssertNil(try f.journal.receipt(mutationID: driftIntent.mutationID))
        provider.isResolved = false

        let intent = try f.intent(source: source)
        let accepted = try f.writer.commitExceptionQueueAcknowledgement(intent, providers: f.providers)
        XCTAssertEqual(accepted.acknowledgement.recordedAt, f.date)
        let callsAfterCommit = f.clock.callCount
        let evolved = try ExceptionQueueSourceSnapshotV1(
            workspaceID: source.workspaceID, kind: source.kind, sourceID: source.sourceID,
            sourceRevision: source.sourceRevision + 1,
            sourceSHA256: String(repeating: "d", count: 64),
            evidenceSHA256: String(repeating: "e", count: 64),
            severity: source.severity, reasons: source.reasons, deepLink: source.deepLink
        )
        f.authority.queueSources.append(evolved)
        provider.source = evolved
        f.clock.value = f.date.addingTimeInterval(3_600)
        let replay = try f.writer.commitExceptionQueueAcknowledgement(intent, providers: f.providers)
        XCTAssertEqual(replay, accepted)
        XCTAssertEqual(f.clock.callCount, callsAfterCommit, "durable retry must precede time and source reads")

        let changed = try ExceptionQueueAcknowledgementIntentV1(
            acknowledgementID: intent.acknowledgementID, source: intent.source,
            predecessor: intent.predecessor, disposition: .reopened, actor: intent.actor,
            expectedRevision: intent.expectedRevision, mutationID: intent.mutationID
        )
        let beforeChanged = try f.journal.exportSnapshot()
        XCTAssertThrowsError(try f.writer.commitExceptionQueueAcknowledgement(changed, providers: f.providers))
        let afterChanged = try f.journal.exportSnapshot()
        XCTAssertEqual(afterChanged.receipts, beforeChanged.receipts)
        XCTAssertEqual(afterChanged.quarantines, beforeChanged.quarantines)
        XCTAssertEqual(try f.context.fetch(FetchDescriptor<ExceptionQueueAcknowledgementRowV1>()).count, 1)
        XCTAssertEqual(try f.journal.receipt(mutationID: intent.mutationID)?.postImages.map(\.semanticSHA256),
                       Optional([accepted.acknowledgement.acknowledgementSHA256]))

        f.authority.trace.resolver.removeAll()
        guard case let .acknowledgement(historic) = try f.writer.reinspectionExceptionQuery(
            try .init(workspaceID: f.workspaceID,
                      target: .acknowledgement(accepted.acknowledgement.logicalExceptionKey)),
            providers: f.providers
        ) else { return XCTFail("historical acknowledgement expected") }
        XCTAssertEqual(historic, accepted.acknowledgement)
        XCTAssertEqual(Set(f.authority.trace.resolver), Set([accepted.acknowledgement.recordedAt]))
        guard case let .queue(current) = try f.writer.reinspectionExceptionQuery(
            try .init(workspaceID: f.workspaceID, target: .queue(try .init())), providers: f.providers
        ) else { return XCTFail("current queue expected") }
        XCTAssertTrue(current.contains { $0.source == evolved })
    }

    func testV23P04C12T03InterruptedAcknowledgementRecoversThroughExistingJournalPair() throws {
        for boundary in MutationJournalFaultBoundaryV1.allCases {
            let f = try C12Fixture(failOnceAt: boundary)
            let source = try XCTUnwrap(f.authority.queueSources.first)
            let intent = try f.intent(source: source)
            XCTAssertThrowsError(try f.writer.commitExceptionQueueAcknowledgement(intent, providers: f.providers))
            try MutationReceiptRecoveryServiceV1(store: f.journal).recoverBeforeWriterActivation()
            let restarted = try f.runtime()
            let recovered: ExceptionQueueAcknowledgementCommitResultV1
            if try f.journal.receipt(mutationID: intent.mutationID) != nil {
                f.providers.forEach { $0.isResolved = true }
                let callsBeforeReplay = f.clock.callCount
                recovered = try restarted.writer.commitExceptionQueueAcknowledgement(
                    intent, providers: f.providers
                )
                XCTAssertEqual(f.clock.callCount, callsBeforeReplay)
            } else {
                XCTAssertThrowsError(try restarted.writer.commitExceptionQueueAcknowledgement(
                    intent, providers: f.providers
                ), "an aborted attempt's process-local writer token is not replay authority")
                let refreshed = try ExceptionQueueAcknowledgementIntentV1(
                    acknowledgementID: intent.acknowledgementID, source: intent.source,
                    predecessor: intent.predecessor, disposition: intent.disposition, actor: intent.actor,
                    expectedRevision: WorkspaceExpectedRevisionV1(snapshot: try restarted.writer.currentRevision()),
                    mutationID: intent.mutationID
                )
                recovered = try restarted.writer.commitExceptionQueueAcknowledgement(
                    refreshed, providers: f.providers
                )
            }
            XCTAssertEqual(recovered.acknowledgement.acknowledgementID, intent.acknowledgementID)
            XCTAssertEqual(recovered.receipt.recoveryState, .receiptCommitted)
            XCTAssertEqual(try f.context.fetch(FetchDescriptor<ExceptionQueueAcknowledgementRowV1>()).count, 1)
            XCTAssertTrue(try f.journal.exportSnapshot().quarantines.isEmpty)
        }
    }

    func testV23P04C12T04ValidatedImportPreservesHistoricalAcknowledgementBytesWithoutCurrentFrontier() throws {
        let sourceRuntime = try C12Fixture()
        let source = try XCTUnwrap(sourceRuntime.authority.queueSources.first)
        let accepted = try sourceRuntime.writer.commitExceptionQueueAcknowledgement(
            try sourceRuntime.intent(source: source), providers: sourceRuntime.providers
        )
        let change = try c12JournalChange(
            sourceRuntime.journal.exportSnapshot(), mutationID: accepted.acknowledgement.mutationID
        )
        guard case let .applyReinspectionException(sourceCommand) = change.envelope.command,
              case let .recordAcknowledgement(sourceAcknowledgement, _, _) = sourceCommand.payload else {
            return XCTFail("source acknowledgement command expected")
        }

        let destination = try C12Fixture(workspaceID: sourceRuntime.workspaceID)
        destination.providers.forEach { $0.isResolved = true }
        let first = try destination.writer.executeImported(change)
        let receiptCount = try destination.journal.exportSnapshot().receipts.count
        let restarted = try destination.runtime()
        let exactReplay = try restarted.writer.executeImported(change)
        XCTAssertEqual(exactReplay.mutationID, first.mutationID)
        XCTAssertEqual(exactReplay.commandDigest, first.commandDigest)
        XCTAssertEqual(exactReplay.occurredAt, first.occurredAt)
        XCTAssertEqual(exactReplay.effect, first.effect)
        XCTAssertEqual(exactReplay.before.revision, first.before.revision)
        XCTAssertEqual(exactReplay.before.entityRevisions, first.before.entityRevisions)
        XCTAssertEqual(exactReplay.after.revision, first.after.revision)
        XCTAssertEqual(exactReplay.after.entityRevisions, first.after.entityRevisions)
        XCTAssertNotEqual(exactReplay.before.writerInstanceID, first.before.writerInstanceID)
        XCTAssertEqual(try destination.journal.exportSnapshot().receipts.count, receiptCount)
        XCTAssertTrue(try destination.journal.exportSnapshot().quarantines.isEmpty)
        let rows = try destination.context.fetch(FetchDescriptor<ExceptionQueueAcknowledgementRowV1>())
        XCTAssertEqual(try rows.map { try $0.value() }, [sourceAcknowledgement])
        XCTAssertEqual(sourceAcknowledgement.recordedAt, accepted.acknowledgement.recordedAt)
        XCTAssertEqual(sourceAcknowledgement.acknowledgementSHA256, accepted.acknowledgement.acknowledgementSHA256)
        let destinationPair = try XCTUnwrap(destination.journal.reinspectionExceptionRecoveryPairs().first)
        XCTAssertEqual(destinationPair.command.commandID, sourceCommand.commandID)
        XCTAssertEqual(destinationPair.command.payload, sourceCommand.payload)
        XCTAssertEqual(destinationPair.command.submittedAt, sourceCommand.submittedAt)
        XCTAssertEqual(destinationPair.command.expectedRevision.generationID, destination.generationID)
        XCTAssertEqual(sourceCommand.expectedRevision.generationID, sourceRuntime.generationID)
        let destinationReceipt = try XCTUnwrap(destination.journal.receipt(
            mutationID: sourceAcknowledgement.mutationID
        ))
        XCTAssertEqual(destinationReceipt.sourceKind, .importedHistory)
        XCTAssertEqual(try MutationPortableExpectedRevisionV1(destinationPair.command.expectedRevision),
                       destinationReceipt.expectedRevision)
        XCTAssertEqual(try MutationPortableExpectedRevisionV1(sourceCommand.expectedRevision),
                       change.envelope.expectedRevision)
        XCTAssertNotEqual(destinationPair.command.expectedRevision.writerInstanceID,
                          exactReplay.before.writerInstanceID)
        XCTAssertTrue(destination.providers.allSatisfy(\.isResolved),
                      "accepted historical import must not require today's unresolved frontier")
    }

    func testV23P04C12T05CanonicalExpectedRevisionEnrollsOnlyAbsentTargetAndRetainsFullSnapshotCAS() throws {
        let f = try C12Fixture()
        let plan = try f.plan(matrix: false)
        _ = try f.commit(.putPlan(plan, nil), mutationID: plan.mutationID)
        let source = try XCTUnwrap(f.authority.queueSources.first)
        let before = try f.writer.currentRevision()
        let rawExpected = WorkspaceExpectedRevisionV1(snapshot: before)
        let target = try ReinspectionExceptionMutationCommandV1.acknowledgementTarget(
            logicalExceptionKey: source.logicalExceptionKey
        )
        XCTAssertFalse(rawExpected.entityRevisions.contains { $0.identity == target })
        let explicitZero = try WorkspaceExpectedRevisionV1(
            workspaceID: rawExpected.workspaceID, generationID: rawExpected.generationID,
            writerInstanceID: rawExpected.writerInstanceID, workspaceRevision: rawExpected.workspaceRevision,
            entityRevisions: rawExpected.entityRevisions + [.init(identity: target, revision: 0)]
        )
        let acknowledgementID = UUID(), mutationID = try f.mutation(), actor = try f.actor()
        let normalized = try ExceptionQueueAcknowledgementIntentV1(
            acknowledgementID: acknowledgementID, source: source, disposition: .acknowledged,
            actor: actor, expectedRevision: rawExpected, mutationID: mutationID
        )
        let explicit = try ExceptionQueueAcknowledgementIntentV1(
            acknowledgementID: acknowledgementID, source: source, disposition: .acknowledged,
            actor: actor, expectedRevision: explicitZero, mutationID: mutationID
        )
        XCTAssertEqual(normalized, explicit, "missing and explicit zero normalize before an intent exists")
        XCTAssertEqual(normalized.expectedRevision.entityRevisions.first { $0.identity == target }?.revision, 0)
        let first = try f.writer.commitExceptionQueueAcknowledgement(normalized, providers: f.providers)

        let successor = try f.intent(
            source: source, predecessor: first.acknowledgement, disposition: .reopened
        )
        let second = try f.writer.commitExceptionQueueAcknowledgement(successor, providers: f.providers)
        XCTAssertEqual(second.acknowledgement.revision, 2)
        let current = try f.writer.currentRevision()
        XCTAssertEqual(current.entityRevisions.first { $0.identity == target }?.revision, 2)
        let baseline = try f.journal.exportSnapshot()

        func expected(
            entities: [WorkspaceEntityRevisionV1],
            workspaceID: WorkspaceID? = nil,
            workspaceRevision: UInt64? = nil,
            generationID: UUID? = nil,
            writerInstanceID: UUID? = nil
        ) throws -> WorkspaceExpectedRevisionV1 {
            try .init(
                workspaceID: workspaceID ?? current.workspaceID,
                generationID: generationID ?? current.generationID,
                writerInstanceID: writerInstanceID ?? current.writerInstanceID,
                workspaceRevision: workspaceRevision ?? current.revision,
                entityRevisions: entities
            )
        }
        func successorIntent(
            source candidateSource: ExceptionQueueSourceSnapshotV1,
            predecessor: ExceptionQueueAcknowledgementV1?,
            expectedRevision: WorkspaceExpectedRevisionV1
        ) throws -> ExceptionQueueAcknowledgementIntentV1 {
            try .init(
                acknowledgementID: UUID(), source: candidateSource, predecessor: predecessor,
                disposition: .acknowledged, actor: try f.actor(), expectedRevision: expectedRevision,
                mutationID: try f.mutation()
            )
        }

        let planIdentity = try XCTUnwrap(current.entityRevisions.first {
            $0.identity.kind == .reinspectionPlan
        }).identity
        let omittedIncumbent = try expected(entities: current.entityRevisions.filter {
            $0.identity != planIdentity
        })
        XCTAssertThrowsError(try f.writer.commitExceptionQueueAcknowledgement(
            try successorIntent(source: source, predecessor: second.acknowledgement,
                                expectedRevision: omittedIncumbent), providers: f.providers
        ))

        let extraneousIdentity = try WorkspaceEntityIdentityV1(kind: .reinspectionPlan, id: UUID())
        let extraneous = try expected(entities: current.entityRevisions + [
            .init(identity: extraneousIdentity, revision: 0)
        ])
        XCTAssertThrowsError(try f.writer.commitExceptionQueueAcknowledgement(
            try successorIntent(source: source, predecessor: second.acknowledgement,
                                expectedRevision: extraneous), providers: f.providers
        ))

        let freshSource = try XCTUnwrap(f.authority.queueSources.dropFirst().first)
        let freshTarget = try ReinspectionExceptionMutationCommandV1.acknowledgementTarget(
            logicalExceptionKey: freshSource.logicalExceptionKey
        )
        let inventedNonzero = try expected(entities: current.entityRevisions + [
            .init(identity: freshTarget, revision: 1)
        ])
        XCTAssertThrowsError(try f.writer.commitExceptionQueueAcknowledgement(
            try successorIntent(source: freshSource, predecessor: nil, expectedRevision: inventedNonzero),
            providers: f.providers
        ))

        let staleGlobal = try expected(
            entities: current.entityRevisions, workspaceRevision: current.revision - 1
        )
        XCTAssertThrowsError(try f.writer.commitExceptionQueueAcknowledgement(
            try successorIntent(source: source, predecessor: second.acknowledgement,
                                expectedRevision: staleGlobal), providers: f.providers
        ))
        let wrongWorkspace = try expected(
            entities: current.entityRevisions, workspaceID: WorkspaceID(rawValue: UUID())
        )
        XCTAssertThrowsError(try successorIntent(
            source: source, predecessor: second.acknowledgement, expectedRevision: wrongWorkspace
        ))
        let wrongGeneration = try expected(entities: current.entityRevisions, generationID: UUID())
        XCTAssertThrowsError(try f.writer.commitExceptionQueueAcknowledgement(
            try successorIntent(source: source, predecessor: second.acknowledgement,
                                expectedRevision: wrongGeneration), providers: f.providers
        ))
        let wrongWriter = try expected(entities: current.entityRevisions, writerInstanceID: UUID())
        XCTAssertThrowsError(try f.writer.commitExceptionQueueAcknowledgement(
            try successorIntent(source: source, predecessor: second.acknowledgement,
                                expectedRevision: wrongWriter), providers: f.providers
        ))

        let after = try f.journal.exportSnapshot()
        XCTAssertEqual(after.receipts, baseline.receipts)
        XCTAssertEqual(after.quarantines, baseline.quarantines)
        XCTAssertEqual(after.entityRevisions, baseline.entityRevisions)
    }
}

private final class C12Clock: ApplicationClock, @unchecked Sendable {
    var value: Date
    private(set) var callCount = 0
    init(_ value: Date = Date(timeIntervalSince1970: 1_700_200_000)) { self.value = value }
    func now() -> Date { callCount += 1; return value }
}
private struct C12IDs: ApplicationIDSource { func makeID() -> UUID { UUID() } }
private struct C12Files: ApplicationFileAuthorityV1 { func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String { "mutation-staging/\(mutationID.rawValue.uuidString.lowercased())/\(component)" } }

private final class C12TimeTrace {
    var provider: [Date] = []
    var resolver: [Date] = []
}

private final class C12Provider: ExceptionQueueCanonicalSourceProvidingV1 {
    let registeredSourceKind: ExceptionQueueSourceKindV1
    var source: ExceptionQueueSourceSnapshotV1
    var isResolved = false
    var failRead = false
    var availableAt: Date?
    let trace: C12TimeTrace
    init(_ source: ExceptionQueueSourceSnapshotV1, trace: C12TimeTrace) {
        registeredSourceKind = source.kind; self.source = source; self.trace = trace
    }
    func unresolvedExceptionSources(workspaceID: WorkspaceID, evaluatedAt: Date) throws -> [ExceptionQueueSourceSnapshotV1] {
        trace.provider.append(evaluatedAt)
        guard workspaceID == source.workspaceID else { throw ReinspectionExceptionFailureV1.wrongWorkspace }
        if failRead { throw ReinspectionExceptionFailureV1.missingSource }
        if let availableAt, evaluatedAt < availableAt { return [] }
        return isResolved ? [] : [source]
    }
}

private final class C12ExactAuthority: ReinspectionCanonicalSourceResolvingV1, ExceptionQueueCanonicalSourceResolvingV1 {
    let reinspectionSources: [ReinspectionSourceSnapshotV1]
    var queueSources: [ExceptionQueueSourceSnapshotV1]
    let trace: C12TimeTrace
    init(reinspectionSources: [ReinspectionSourceSnapshotV1], queueSources: [ExceptionQueueSourceSnapshotV1], trace: C12TimeTrace) {
        self.reinspectionSources = reinspectionSources; self.queueSources = queueSources; self.trace = trace
    }
    func resolveReinspectionSource(_ identity: ReinspectionSourceIdentityV1, revision: UInt64) throws -> ReinspectionSourceSnapshotV1 {
        guard let exact = reinspectionSources.first(where: { $0.identity == identity && $0.revision == revision }) else { throw ReinspectionExceptionFailureV1.missingSource }
        return exact
    }
    func resolveExceptionQueueSource(workspaceID: WorkspaceID, kind: ExceptionQueueSourceKindV1, sourceID: String, revision: UInt64, evaluatedAt: Date) throws -> ExceptionQueueSourceSnapshotV1 {
        trace.resolver.append(evaluatedAt)
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
    let clock: C12Clock

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
        let trace = C12TimeTrace()
        let exact = C12ExactAuthority(reinspectionSources: reinspection, queueSources: queue, trace: trace)
        let exactProviders = queue.map { C12Provider($0, trace: trace) }
        let testClock = C12Clock()
        let generation = UUID(), replica = try WorkspaceReplicaIdentityV1(workspaceID: workspace, replicaID: ReplicaID(rawValue: UUID()))
        let store = try MutationJournalStoreV1(modelContext: modelContext, identity: replica, generationID: generation,
            failureInjection: boundary.map { MutationJournalFailureInjectionV1(failOnceAt: $0) })
        let canonical = try WorkspaceWriterV1(identity: replica, generationID: generation,
            initialRevision: store.currentRevision(writerInstanceID: UUID()), clock: testClock, idSource: C12IDs(), fileAuthority: C12Files(),
            adapter: WorkspaceWriterAdapterV1(modelContext: modelContext, reinspectionCanonicalSourceResolver: exact,
                exceptionQueueCanonicalSourceResolver: exact), journalStore: store)
        workspaceID = workspace; identity = replica; generationID = generation; context = modelContext
        journal = store; writer = canonical; authority = exact; providers = exactProviders; clock = testClock
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
    func intent(source: ExceptionQueueSourceSnapshotV1,
                predecessor: ExceptionQueueAcknowledgementV1? = nil,
                disposition: ExceptionQueueAcknowledgementDispositionV1 = .acknowledged,
                acknowledgementID: UUID = UUID(),
                mutationID: MutationIDV1? = nil,
                writer authority: WorkspaceWriterV1? = nil) throws -> ExceptionQueueAcknowledgementIntentV1 {
        let selected = authority ?? writer
        return try .init(
            acknowledgementID: acknowledgementID, source: source, predecessor: predecessor,
            disposition: disposition, actor: try actor(),
            expectedRevision: WorkspaceExpectedRevisionV1(snapshot: try selected.currentRevision()),
            mutationID: try mutationID ?? mutation()
        )
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
    func runtime(failOnceAt boundary: MutationJournalFaultBoundaryV1? = nil) throws -> (journal: MutationJournalStoreV1, writer: WorkspaceWriterV1, lifecycle: ReinspectionExceptionQueueLifecycleAdapterV1) {
        let store = try MutationJournalStoreV1(modelContext: context, identity: identity, generationID: generationID,
            failureInjection: boundary.map { .init(failOnceAt: $0) })
        let authorityWriter = try WorkspaceWriterV1(identity: identity, generationID: generationID,
            initialRevision: store.currentRevision(writerInstanceID: UUID()), clock: clock, idSource: C12IDs(), fileAuthority: C12Files(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context, reinspectionCanonicalSourceResolver: authority,
                exceptionQueueCanonicalSourceResolver: authority), journalStore: store)
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

@MainActor
private func c12JournalChange(
    _ history: MutationHistorySnapshotV1,
    mutationID: MutationIDV1
) throws -> JournalChangeV1 {
    let record = try XCTUnwrap(history.receipts.first { record in
        guard let envelope = try? MutationEnvelopeV1.decodeCanonical(from: record.envelopeData) else {
            return false
        }
        return envelope.mutationID == mutationID
    })
    let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
    let receipt = try MutationReceiptV1.decodeCanonical(from: record.receiptData)
    let policy = try ConflictPolicyV1(policyID: "c12.import.exact-revision", rule: .exactRevisionManual)
    return try JournalChangeV1(
        envelope: envelope,
        receipt: receipt,
        entityChanges: try receipt.postImages.map {
            try EntityChangeV1(postImage: $0, conflictPolicy: policy, conflictIdentity: nil)
        },
        reversalBasis: nil,
        portableReversalPlan: nil,
        semanticReversalReceipt: nil,
        contentReferences: []
    )
}

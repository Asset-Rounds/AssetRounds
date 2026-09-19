import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V23MutationReceiptSafetyTests: XCTestCase {
    func testPrivacyPublicationLostAcknowledgmentReplaysThroughFreshAuthority() async throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        let harness = try ReceiptSafetyHarness(workspaceID: fixture.workspace) { context in
            context.insert(try PrivacyTransformPolicyRow(fixture.policy))
            context.insert(try ActorSnapshotRow(fixture.author))
        }
        defer { harness.removeFiles() }
        let content = EvidenceBundleStore(generationRootURL: harness.root)
        let interrupted = try WorkspacePrivacyTransformPublicationAuthorityV1(
            contentWriter: content, workspaceWriter: harness.writer,
            interruptionHook: { point in
                if point == .afterCanonicalCommitBeforeLocalReceipt { throw point }
            }
        )
        let before = try harness.writer.currentRevision()
        do {
            _ = try await interrupted.publish(fixture.bundle)
            XCTFail("Expected interruption after the durable canonical commit")
        } catch {
            XCTAssertEqual(error as? PrivacyTransformPublicationInterruptionV1,
                           .afterCanonicalCommitBeforeLocalReceipt)
        }
        let original = try XCTUnwrap(harness.store.receipt(mutationID: fixture.mutationID))
        XCTAssertEqual(original.expectedRevision.workspaceRevision, before.revision)
        XCTAssertEqual(original.resultingRevision.workspaceRevision, before.revision + 1)
        let freshWriter = try harness.reopenWriter()
        let freshAuthority = try WorkspacePrivacyTransformPublicationAuthorityV1(
            contentWriter: content, workspaceWriter: freshWriter
        )
        let receipt = try await PrivacyTransformLifecycleAdapterV1(authority: freshAuthority)
            .resume(bundle: fixture.bundle)
        XCTAssertEqual(receipt.canonicalMutationReceiptSHA256, try original.canonicalSHA256())
        XCTAssertEqual(try freshWriter.privacyTransformReceipt(for: .publish(
            policy: fixture.policy, regions: fixture.regions, manifest: fixture.manifest
        )), original)
        let repeated = try await freshAuthority.publish(fixture.bundle)
        XCTAssertEqual(repeated, receipt)
        XCTAssertEqual(try freshWriter.currentRevision().revision, before.revision + 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<PrivacyTransformManifestRow>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<PrivacyRegionRow>()), fixture.regions.count)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationQuarantineRow>()), 0)
        let bytes = harness.root.appendingPathComponent(
            "content/\(fixture.derivative.workspaceID)/\(fixture.derivative.contentID)/original.bin"
        )
        XCTAssertEqual(try Data(contentsOf: bytes), fixture.derivativeBytes)
        try harness.store.validateAll()
    }

    func testValidChangedPrivacyPublicationQuarantinesAndCachedReceiptFailsClosed() async throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        let harness = try ReceiptSafetyHarness(workspaceID: fixture.workspace) { context in
            context.insert(try PrivacyTransformPolicyRow(fixture.policy))
            context.insert(try ActorSnapshotRow(fixture.author))
        }
        defer { harness.removeFiles() }
        let authority = try WorkspacePrivacyTransformPublicationAuthorityV1(
            contentWriter: EvidenceBundleStore(generationRootURL: harness.root),
            workspaceWriter: harness.writer
        )
        _ = try await authority.publish(fixture.bundle)
        let original = try XCTUnwrap(harness.store.receipt(mutationID: fixture.mutationID))
        let manifest = fixture.manifest
        let changed = try PrivacyTransformManifestV1(
            manifestID: manifest.manifestID, workspaceID: manifest.workspaceID,
            original: manifest.original, sourceRevision: manifest.sourceRevision,
            sourceSHA256: manifest.sourceSHA256, derivative: manifest.derivative,
            derivativeSHA256: manifest.derivativeSHA256, policy: fixture.policy,
            orderedRegions: manifest.orderedRegions, rendererID: manifest.rendererID,
            rendererVersion: "valid-retry-version", metadataSanitation: manifest.metadataSanitation,
            staleState: manifest.staleState, renderedAt: manifest.renderedAt,
            supersedesManifestID: manifest.supersedesManifestID, revision: manifest.revision,
            mutationID: manifest.mutationID
        )
        let mutation = PrivacyTransformMutationV1.publish(
            policy: fixture.policy, regions: fixture.regions, manifest: changed
        )
        try mutation.validate()
        let provenance = fixture.provenance
        let changedProvenance = try ContentDerivativeProvenanceV1(
            provenanceID: provenance.provenanceID, workspaceID: provenance.workspaceID,
            sources: provenance.sources, derivativeContentID: provenance.derivativeContentID,
            derivativeDigest: provenance.derivativeDigest,
            transform: .privacy(try PrivacyDerivativeV1(privacyManifestID: changed.manifestID,
                privacyManifestSHA256: changed.manifestSHA256, rendererID: changed.rendererID,
                rendererVersion: changed.rendererVersion)),
            metadataSanitizerID: provenance.metadataSanitizerID,
            metadataSanitizerVersion: provenance.metadataSanitizerVersion, createdAt: provenance.createdAt
        )
        let changedBundle = PrivacyTransformPublicationBundleV1(policy: fixture.policy, manifest: changed,
            derivativeBytes: fixture.derivativeBytes, derivativeLocator: fixture.locator,
            provenance: changedProvenance)
        try changedBundle.validate()
        do {
            _ = try await authority.publish(changedBundle)
            XCTFail("A valid changed command must reach durable conflict quarantine")
        } catch { XCTAssertEqual(error as? WorkspaceMutationFailureV1, .mutationIDQuarantined) }
        XCTAssertThrowsError(try harness.writer.commitPrivacyTransform(.publish(
            policy: fixture.policy, regions: fixture.regions, manifest: fixture.manifest
        ))) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        do {
            _ = try await authority.receipt(for: fixture.mutationID)
            XCTFail("Cached receipt must not bypass durable quarantine")
        } catch { XCTAssertEqual(error as? WorkspaceMutationFailureV1, .mutationIDQuarantined) }
        XCTAssertEqual(try harness.store.receipt(mutationID: fixture.mutationID), original)
        XCTAssertEqual(try harness.writer.currentRevision().revision, original.resultingRevision.workspaceRevision)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationQuarantineRow>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<PrivacyTransformManifestRow>()), 1)
    }

    func testCachedPrivacyReceiptDeniesRevokedLeaseAndUnrelatedCorruptJournal() async throws {
        for revoke in [false, true] {
            let fixture = try C20PrivacyTransformTestSupport.makeFixture()
            let harness = try ReceiptSafetyHarness(workspaceID: fixture.workspace) { context in
                context.insert(try PrivacyTransformPolicyRow(fixture.policy))
                context.insert(try ActorSnapshotRow(fixture.author))
            }
            defer { harness.removeFiles() }
            let authority = try WorkspacePrivacyTransformPublicationAuthorityV1(
                contentWriter: EvidenceBundleStore(generationRootURL: harness.root),
                workspaceWriter: harness.writer
            )
            _ = try await authority.publish(fixture.bundle)
            if revoke {
                try harness.registry.release(harness.lease)
            } else {
                // Corrupt a different accepted mutation, leaving the requested
                // publication row intact. Per-row validation cannot detect it.
                _ = try harness.writer.execute(.applyPartyAccountability(.appendActorSnapshot(fixture.reviewer)),
                    mutationID: try MutationIDV1(rawValue: UUID()))
                let rows = try harness.context.fetch(FetchDescriptor<MutationReceiptRow>())
                let other = try XCTUnwrap(rows.first { $0.mutationID != fixture.mutationID.rawValue })
                other.envelopeSHA256 = String(repeating: "0", count: 64)
                try harness.context.save()
            }
            do {
                _ = try await authority.publish(fixture.bundle)
                XCTFail("Cached publication must revalidate the live writer and complete journal")
            } catch {
                XCTAssertEqual(error as? WorkspaceMutationFailureV1,
                               revoke ? .wrongGeneration : .receiptHistoryCorrupt)
            }
        }
    }

    func testTemporalCommittedReceiptCannotAuthorizeCleanupAfterRevocationOrQuarantine() async throws {
        for revoke in [false, true] {
            let seed = try ReceiptSafetyTemporalSeed()
            let harness = try ReceiptSafetyHarness(workspaceID: seed.clip.workspaceID, seed: seed.persist)
            defer { harness.removeFiles() }
            let expected = try C33TemporalEvidenceTestSupport.expectedRevision(
                for: seed.clip, generationID: harness.generationID,
                writerInstanceID: harness.writerInstanceID
            )
            _ = try harness.writer.commitTemporalEvidence(.init(
                workspaceID: seed.clip.workspaceID, expectedRevision: expected,
                mutationID: seed.clip.mutationID,
                payload: .acceptClip(seed.clip, review: C33TemporalEvidenceTestSupport.review(for: seed.clip),
                                     predecessor: nil)
            ))
            let current = try harness.writer.currentRevision()
            let removalExpected = try C33TemporalEvidenceTestSupport.expectedRevision(
                for: seed.clip, generationID: current.generationID,
                writerInstanceID: current.writerInstanceID, workspaceRevision: current.revision,
                entityRevision: seed.clip.revision
            )
            let event = try seed.removalEvent()
            let removal = try TemporalEvidenceMutationV1(
                workspaceID: seed.clip.workspaceID, expectedRevision: removalExpected,
                mutationID: event.mutationID,
                payload: .removeClip(event: event, clips: [seed.clip], anchors: [], derivatives: [], predecessorEvent: nil)
            )
            let original = try harness.writer.commitTemporalEvidence(removal)
            XCTAssertEqual(try harness.writer.commitTemporalEvidence(removal), original)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<TemporalEvidenceClipRow>()), 0)
            if revoke {
                try harness.registry.release(harness.lease)
            } else {
                let changedEvent = try seed.removalEvent(policySHA256: String(repeating: "e", count: 64),
                                                        mutationID: event.mutationID)
                let changed = try TemporalEvidenceMutationV1(
                    workspaceID: seed.clip.workspaceID, expectedRevision: removalExpected,
                    mutationID: event.mutationID,
                    payload: .removeClip(event: changedEvent, clips: [seed.clip], anchors: [], derivatives: [], predecessorEvent: nil)
                )
                XCTAssertThrowsError(try harness.writer.commitTemporalEvidence(changed)) {
                    XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
                }
            }
            XCTAssertThrowsError(try harness.writer.temporalEvidenceReceipt(mutationID: event.mutationID)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1,
                               revoke ? .wrongGeneration : .mutationIDQuarantined)
            }
            XCTAssertThrowsError(try harness.writer.commitTemporalEvidence(removal)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1,
                               revoke ? .wrongGeneration : .mutationIDQuarantined)
            }
            let unused = ReceiptSafetyUnusedTemporalPorts()
            let cleanup = ReceiptSafetyCleanupSpy()
            let coordinator = TemporalEvidenceCoordinatorV1(writer: harness.writer, content: unused,
                scratch: unused, admission: unused, recovery: unused, cleanupRecovery: unused,
                contentCleanup: cleanup)
            do {
                _ = try await coordinator.removeClip(event, clips: [seed.clip], anchors: [], derivatives: [],
                    predecessorEvent: nil, expectedRevision: removalExpected)
                XCTFail("Denied canonical authority must not authorize content cleanup")
            } catch {
                XCTAssertEqual(error as? WorkspaceMutationFailureV1,
                               revoke ? .wrongGeneration : .mutationIDQuarantined)
            }
            XCTAssertEqual(cleanup.calls, 0)
            let marked = await unused.markedCount
            XCTAssertEqual(marked, 0)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 2)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationQuarantineRow>()), revoke ? 0 : 1)
        }
    }

    func testOperationalContactReplayBindsOriginalRequestAndCurrentJournalAuthority() async throws {
        for revoke in [false, true] {
            let workspace = C46OperationalContactTestSupport.workspace(revoke ? 90_102 : 90_101)
            let party = try C46OperationalContactTestSupport.party(slot: revoke ? 90_104 : 90_103,
                                                                     workspaceID: workspace)
            let harness = try ReceiptSafetyHarness(workspaceID: workspace) { context in
                context.insert(try ServicePartyRow(party))
            }
            defer { harness.removeFiles() }
            let current = try harness.writer.currentRevision()
            let mutationID = try C46OperationalContactTestSupport.mutation(revoke ? 90_106 : 90_105)
            let contact = try ServiceContactPointV1(
                contactPointID: C46OperationalContactTestSupport.id(revoke ? 90_108 : 90_107),
                workspaceID: workspace, party: party, kind: .email, label: .office,
                displayValue: "replay@example.invalid", preferred: true, provenance: .manual,
                lifecycle: .effective,
                effectiveAt: C46OperationalContactTestSupport.date(revoke ? 90_108 : 90_107),
                revision: 1, mutationID: mutationID
            )
            let intent = try C46OperationalContactTestSupport.intent(
                slot: revoke ? 90_110 : 90_109, kind: .email, contact: contact
            )
            let expected = try WorkspaceExpectedRevisionV1(
                workspaceID: current.workspaceID, generationID: current.generationID,
                writerInstanceID: current.writerInstanceID, workspaceRevision: current.revision,
                entityRevisions: current.entityRevisions + [
                    .init(identity: try .init(kind: .serviceContactPoint, id: contact.contactPointID), revision: 0),
                    .init(identity: try .init(kind: .systemHandoffIntent, id: intent.intentID), revision: 0),
                ]
            )
            let mutation = try OperationalContactMutationV1(
                workspaceID: workspace, mutationID: mutationID, expectedRevision: expected,
                successors: [contact],
                preferredScopes: [.init(partyID: party.partyID, kind: .email,
                                        activeContactPointIDs: [contact.contactPointID],
                                        preferredContactPointID: contact.contactPointID)],
                handoffIntents: [intent]
            )
            let original = try await harness.writer.commitOperationalContact(mutation)
            let replay = try await harness.writer.commitOperationalContact(mutation)
            XCTAssertEqual(replay, original)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)

            if revoke {
                try harness.registry.release(harness.lease)
                do {
                    _ = try await harness.writer.commitOperationalContact(mutation)
                    XCTFail("A revoked writer must not return a cached receipt")
                } catch { XCTAssertEqual(error as? WorkspaceMutationFailureV1, .wrongGeneration) }
            } else {
                let changedContact = try ServiceContactPointV1(
                    contactPointID: contact.contactPointID, workspaceID: workspace, party: party,
                    kind: .email, label: .work, displayValue: "changed@example.invalid",
                    preferred: true, provenance: .manual, lifecycle: .effective,
                    effectiveAt: contact.effectiveAt, revision: contact.revision,
                    mutationID: mutationID
                )
                let changedIntent = try C46OperationalContactTestSupport.intent(
                    slot: revoke ? 90_110 : 90_109, kind: .email, contact: changedContact
                )
                let changed = try OperationalContactMutationV1(
                    workspaceID: workspace, mutationID: mutationID, expectedRevision: expected,
                    successors: [changedContact],
                    preferredScopes: [.init(partyID: party.partyID, kind: .email,
                                            activeContactPointIDs: [changedContact.contactPointID],
                                            preferredContactPointID: changedContact.contactPointID)],
                    handoffIntents: [changedIntent]
                )
                do {
                    _ = try await harness.writer.commitOperationalContact(changed)
                    XCTFail("A changed request must quarantine the reused mutation ID")
                } catch {
                    XCTAssertEqual(error as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
                }
                do {
                    _ = try await harness.writer.commitOperationalContact(mutation)
                    XCTFail("A quarantined receipt must remain unavailable")
                } catch {
                    XCTAssertEqual(error as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
                }
            }
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
        }
    }

    func testDayAndNightWorkflowReplayBindsOriginalRequestAndLiveJournalAuthority() throws {
        for night in [false, true] {
            for denial in 0..<3 {
                let fixture = try ReceiptSafetyLighting.makeFixture(slot: (night ? 10 : 0) + denial)
                let harness = try ReceiptSafetyHarness(workspaceID: fixture.day.workspaceID) { context in
                    context.insert(try LightingSystemRow(fixture.system))
                    context.insert(try LightingObservationRow(fixture.dayObservation))
                    if night {
                        context.insert(try LightingDayInventoryWorkflowRowV1(fixture.plannedDay))
                        context.insert(try LightingObservationRow(fixture.nightObservation))
                    }
                }
                defer { harness.removeFiles() }
                let dayOperation = LightingDayInventoryWriteOperationV1.appendWorkflow(
                    value: fixture.day, predecessor: nil, admission: fixture.dayAdmission)
                let nightOperation = LightingNightWorkflowWriteOperationV1.appendWorkflow(
                    value: fixture.night, predecessor: nil, admission: fixture.nightAdmission)
                let commit: (WorkspaceWriterV1) throws -> MutationReceiptV1 = { writer in
                    if night { return try writer.commitLightingNightWorkflow(nightOperation) }
                    return try writer.commitLightingDayInventory(dayOperation)
                }
                let before = try harness.writer.currentRevision()
                let first = try commit(harness.writer)
                let mutationID = night ? fixture.night.mutationID : fixture.day.mutationID
                XCTAssertEqual(first.expectedRevision.workspaceRevision, before.revision)
                XCTAssertEqual(try harness.writer.currentRevision().revision, before.revision + 1)
                XCTAssertEqual(try commit(harness.writer), first)
                let reopened = try harness.reopenWriter()
                XCTAssertEqual(try commit(reopened), first)
                XCTAssertEqual(try harness.writer.durableReceipt(mutationID: mutationID), first)
                XCTAssertEqual(try reopened.durableReceipt(mutationID: mutationID), first)
                let receipts = try harness.context.fetch(FetchDescriptor<MutationReceiptRow>())
                let receiptRow = try XCTUnwrap(receipts.first)
                XCTAssertEqual(receipts.count, 1)
                let expected: WorkspaceMutationFailureV1
                switch denial {
                case 0:
                    // A different typed command with this committed ID must
                    // quarantine the key before either receipt can be replayed.
                    let substituted = try ReceiptSafetyEvidenceContext.operation(
                        workspaceID: fixture.day.workspaceID,
                        assetID: fixture.system.luminaires[0].assetID,
                        mutationID: night ? fixture.night.mutationID : fixture.day.mutationID,
                        observationCode: night ? "WRONG_TYPED_NIGHT" : "WRONG_TYPED_DAY")
                    XCTAssertThrowsError(try harness.writer.commitEvidenceContext(substituted)) {
                        XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
                    }
                    expected = .mutationIDQuarantined
                case 1:
                    try harness.registry.release(harness.lease)
                    expected = .wrongGeneration
                default:
                    receiptRow.envelopeSHA256 = String(repeating: "0", count: 64)
                    try harness.context.save()
                    expected = .receiptHistoryCorrupt
                }
                XCTAssertThrowsError(try commit(harness.writer)) {
                    XCTAssertEqual($0 as? WorkspaceMutationFailureV1, expected,
                                   "night=\(night), denial=\(denial)")
                }
                XCTAssertThrowsError(try commit(harness.reopenWriter())) {
                    XCTAssertEqual($0 as? WorkspaceMutationFailureV1, expected)
                }
                XCTAssertThrowsError(try harness.writer.durableReceipt(mutationID: mutationID)) {
                    XCTAssertEqual($0 as? WorkspaceMutationFailureV1, expected)
                }
                XCTAssertThrowsError(try harness.reopenWriter().durableReceipt(mutationID: mutationID)) {
                    XCTAssertEqual($0 as? WorkspaceMutationFailureV1, expected)
                }
                if night {
                    let rows = try harness.context.fetch(FetchDescriptor<LightingNightWorkflowRowV1>())
                    XCTAssertEqual(rows.count, 1)
                    XCTAssertEqual(try XCTUnwrap(rows.first).value(), fixture.night)
                } else {
                    let rows = try harness.context.fetch(FetchDescriptor<LightingDayInventoryWorkflowRowV1>())
                    XCTAssertEqual(rows.count, 1)
                    XCTAssertEqual(try XCTUnwrap(rows.first).value(), fixture.day)
                }
                XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
            }
        }
    }

    func testMyDayBridgeReplayRetainsOriginalRevisionAndRequiresLiveAuthorityAndSavedPlan() throws {
        for denial in 0..<5 {
            let workspace = WorkspaceID(rawValue: UUID())
            let date = ReceiptSafetyClock().now()
            let actorReference = try LocalActorReferenceV1(actorReferenceID: UUID(),
                workspaceID: workspace, displayName: "Receipt safety planner")
            let actor = try ActorSnapshotV1(snapshotID: UUID(), workspaceID: workspace,
                actor: actorReference, responsibility: .recordedBy,
                displayNameAtTime: actorReference.displayName, capturedAt: date)
            let harness = try ReceiptSafetyHarness(workspaceID: workspace) { context in
                context.insert(try ActorSnapshotRow(actor))
            }
            defer { harness.removeFiles() }
            let key = try MyDayKeyV1(workspaceID: workspace,
                civilDate: ScheduleLocalDateV1(year: 2026, month: 9, day: 12),
                ianaTimeZoneIdentifier: "America/New_York")
            let plan = try MyDayPlanV1(planID: UUID(), key: key, items: [], revision: 1,
                mutationID: MutationIDV1(rawValue: UUID()), authoredBy: actor, authoredAt: date)
            let command = MyDayCommandV1.save(successor: plan, predecessor: nil)
            let before = try harness.writer.currentRevision()
            let first = try harness.writer.commit(command)
            let original = try XCTUnwrap(harness.store.myDayMutation(mutationID: plan.mutationID))
            XCTAssertEqual(original.expectedRevision.workspaceRevision, before.revision)
            XCTAssertEqual(first.plan, plan)
            XCTAssertEqual(try harness.writer.currentPlan(for: key), plan)

            // A later independent save advances the writer without changing
            // the original request or its immutable saved-plan history.
            let laterKey = try MyDayKeyV1(workspaceID: workspace,
                civilDate: ScheduleLocalDateV1(year: 2026, month: 9, day: 13),
                ianaTimeZoneIdentifier: "America/New_York")
            let later = try MyDayPlanV1(planID: UUID(), key: laterKey, items: [], revision: 1,
                mutationID: MutationIDV1(rawValue: UUID()), authoredBy: actor, authoredAt: date)
            _ = try harness.writer.commit(MyDayCommandV1.save(successor: later, predecessor: nil))
            let after = try harness.writer.currentRevision()
            XCTAssertEqual(after.revision, before.revision + 2)
            let sourceReader = ReceiptSafetyEmptyMyDaySources()
            let coordinator = MyDayCoordinatorV1(writer: harness.writer, sourceReader: sourceReader)
            XCTAssertEqual(try coordinator.save(successor: plan, predecessor: nil), first)
            XCTAssertEqual(try harness.writer.commit(command), first)
            XCTAssertEqual(try harness.writer.commitMyDay(original), first.receipt)
            XCTAssertEqual(try harness.writer.result(workspaceID: workspace, mutationID: plan.mutationID), first)
            let cold = try harness.reopenWriter()
            XCTAssertEqual(try cold.commit(command), first)
            XCTAssertEqual(try cold.commitMyDay(original), first.receipt)
            XCTAssertEqual(try cold.result(workspaceID: workspace, mutationID: plan.mutationID), first)
            XCTAssertEqual(try harness.writer.currentRevision(), after)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MyDayPlanRowV1>()), 2)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 2)

            let expected: WorkspaceMutationFailureV1
            switch denial {
            case 0, 4:
                let changed = try MyDayPlanV1(planID: denial == 4 ? UUID() : plan.planID, key: key, items: [], revision: 1,
                    mutationID: plan.mutationID, authoredBy: actor,
                    authoredAt: date.addingTimeInterval(1))
                XCTAssertThrowsError(try harness.writer.commit(
                    MyDayCommandV1.save(successor: changed, predecessor: nil))) {
                    XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
                }
                expected = .mutationIDQuarantined
            case 1:
                try harness.registry.release(harness.lease)
                XCTAssertThrowsError(try harness.writer.currentPlan(for: key)) {
                    XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .wrongGeneration)
                }
                expected = .wrongGeneration
            case 2:
                let rows = try harness.context.fetch(FetchDescriptor<MutationReceiptRow>())
                let unrelatedKey = MutationWorkspaceKeyV1.value(workspaceID: workspace,
                    mutationID: later.mutationID)
                let unrelated = try XCTUnwrap(rows.first { $0.workspaceMutationKey == unrelatedKey })
                unrelated.envelopeSHA256 = String(repeating: "0", count: 64)
                try harness.context.save()
                expected = .receiptHistoryCorrupt
            default:
                let rows = try harness.context.fetch(FetchDescriptor<MyDayPlanRowV1>())
                harness.context.delete(try XCTUnwrap(rows.first { $0.planID == plan.planID }))
                try harness.context.save()
                expected = .receiptHistoryCorrupt
            }
            XCTAssertThrowsError(try coordinator.save(successor: plan, predecessor: nil)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, expected)
            }
            XCTAssertThrowsError(try harness.writer.commit(command)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, expected)
            }
            XCTAssertThrowsError(try harness.writer.commitMyDay(original)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, expected)
            }
            XCTAssertThrowsError(try harness.writer.result(workspaceID: workspace, mutationID: plan.mutationID)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, expected)
            }
            // Reopen after the durable denial; do not rely on refreshing
            // another ModelContext's previously registered cached objects.
            XCTAssertThrowsError(try harness.reopenWriter().commit(command)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, expected)
            }
            XCTAssertThrowsError(try harness.reopenWriter().commitMyDay(original)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, expected)
            }
            XCTAssertThrowsError(try harness.reopenWriter().result(
                workspaceID: workspace, mutationID: plan.mutationID)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, expected)
            }
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MyDayPlanRowV1>()), denial == 3 ? 1 : 2)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 2)
        }
    }

    func testMyDayCoordinatorQuarantinesAnIDAlreadyUsedByAnotherCommandKind() throws {
        let workspace = WorkspaceID(rawValue: UUID())
        let assetID = UUID()
        let harness = try ReceiptSafetyHarness(workspaceID: workspace) { context in
            let site = Site(label: "My Day collision site", timeZoneID: "UTC")
            context.insert(site)
            context.insert(Asset(id: assetID, siteID: site.id, packID: "receipt-safety",
                packSchemaVersion: 1, packContentVersion: 1, label: "My Day collision asset"))
        }
        defer { harness.removeFiles() }
        let mutationID = try MutationIDV1(rawValue: UUID())
        let original = try ReceiptSafetyEvidenceContext.operation(workspaceID: workspace,
            assetID: assetID, mutationID: mutationID, observationCode: "ORIGINAL_OTHER_KIND")
        _ = try harness.writer.commitEvidenceContext(original)
        let date = ReceiptSafetyClock().now()
        let actorReference = try LocalActorReferenceV1(actorReferenceID: UUID(),
            workspaceID: workspace, displayName: "My Day collision planner")
        let actor = try ActorSnapshotV1(snapshotID: UUID(), workspaceID: workspace,
            actor: actorReference, responsibility: .recordedBy,
            displayNameAtTime: actorReference.displayName, capturedAt: date)
        let key = try MyDayKeyV1(workspaceID: workspace,
            civilDate: ScheduleLocalDateV1(year: 2026, month: 9, day: 12),
            ianaTimeZoneIdentifier: "America/New_York")
        let plan = try MyDayPlanV1(planID: UUID(), key: key, items: [], revision: 1,
            mutationID: mutationID, authoredBy: actor, authoredAt: date)
        let cold = try harness.reopenWriter()
        XCTAssertNil(try cold.result(workspaceID: workspace, mutationID: mutationID))
        let coordinator = MyDayCoordinatorV1(writer: cold, sourceReader: ReceiptSafetyEmptyMyDaySources())
        XCTAssertThrowsError(try coordinator.save(successor: plan, predecessor: nil)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertThrowsError(try harness.reopenWriter().commitEvidenceContext(original)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertThrowsError(try harness.reopenWriter().commit(
            MyDayCommandV1.save(successor: plan, predecessor: nil))) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MyDayPlanRowV1>()), 0)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<EvidenceContextRow>()), 1)
    }

    func testWorkResourceReplayBindsOriginalRequestAndLiveJournalAuthority() throws {
        for denial in [false, true] {
            let fixture = try ReceiptSafetyWorkResource.makeFixture(slot: denial ? 2 : 1)
            let harness = try ReceiptSafetyHarness(workspaceID: fixture.workspaceID) { context in
                context.insert(try ActorSnapshotRow(fixture.actor))
                context.insert(try WorkPacketManifestRow(fixture.manifest))
                let site = Site(label: "Receipt safety work-resource site", timeZoneID: "UTC")
                context.insert(site)
                context.insert(Asset(id: fixture.assetID, siteID: site.id, packID: "receipt-safety",
                                     packSchemaVersion: 1, packContentVersion: 1,
                                     label: "Receipt safety work-resource asset"))
            }
            defer { harness.removeFiles() }
            let before = try harness.writer.currentRevision()
            let first = try harness.writer.commitWorkResource(fixture.mutation, expectedRevision: fixture.expected(before))
            let afterFirst = try harness.writer.currentRevision()
            XCTAssertEqual(first.mutationReceipt.expectedRevision.workspaceRevision, before.revision)
            XCTAssertEqual(afterFirst.revision, before.revision + 1)
            XCTAssertEqual(try harness.writer.commitWorkResource(fixture.mutation, expectedRevision: fixture.expected(before)), first)
            let cold = try harness.reopenWriter()
            XCTAssertEqual(try cold.commitWorkResource(fixture.mutation, expectedRevision: fixture.expected(before)), first)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<ManualWorkResourceRecordRow>()), 1)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)

            let substituted = try ReceiptSafetyEvidenceContext.operation(
                workspaceID: fixture.workspaceID, assetID: fixture.assetID,
                mutationID: fixture.mutation.mutationID, observationCode: "WRONG_TYPED_C49"
            )
            XCTAssertThrowsError(try harness.writer.commitEvidenceContext(substituted)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
            }
            XCTAssertThrowsError(try harness.writer.commitWorkResource(fixture.mutation, expectedRevision: fixture.expected(before))) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
            }

            // Start a separate valid commit before exercising live-authority denial;
            // the quarantined C49 ID above must not mask lease or full-journal checks.
            let fresh = try ReceiptSafetyWorkResource.makeFixture(slot: denial ? 4 : 3)
            let freshHarness = try ReceiptSafetyHarness(workspaceID: fresh.workspaceID) { context in
                context.insert(try ActorSnapshotRow(fresh.actor))
                context.insert(try WorkPacketManifestRow(fresh.manifest))
            }
            defer { freshHarness.removeFiles() }
            let freshBefore = try freshHarness.writer.currentRevision()
            _ = try freshHarness.writer.commitWorkResource(fresh.mutation, expectedRevision: fresh.expected(freshBefore))
            if denial {
                try freshHarness.registry.release(freshHarness.lease)
            } else {
                let rows = try freshHarness.context.fetch(FetchDescriptor<MutationReceiptRow>())
                let row = try XCTUnwrap(rows.first)
                row.envelopeSHA256 = String(repeating: "0", count: 64)
                try freshHarness.context.save()
            }
            XCTAssertThrowsError(try freshHarness.writer.commitWorkResource(
                fresh.mutation, expectedRevision: fresh.expected(freshBefore)
            )) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1,
                               denial ? .wrongGeneration : .receiptHistoryCorrupt)
            }
            XCTAssertEqual(try freshHarness.context.fetchCount(FetchDescriptor<ManualWorkResourceRecordRow>()), 1)
        }
    }

    func testServiceReliabilityReplayBindsOriginalRequestAfterRevisionAdvances() throws {
        let workspace = WorkspaceID(rawValue: UUID())
        let assetID = UUID()
        let harness = try ReceiptSafetyHarness(workspaceID: workspace) { context in
            let site = Site(label: "Receipt safety reliability site", timeZoneID: "UTC")
            context.insert(site)
            context.insert(Asset(id: assetID, siteID: site.id, packID: "receipt-safety",
                                 packSchemaVersion: 1, packContentVersion: 1,
                                 label: "Receipt safety reliability asset"))
        }
        defer { harness.removeFiles() }
        let before = try harness.writer.currentRevision()
        let fixture = try ReceiptSafetyServiceReliability.makeBundle(
            workspaceID: workspace, assetID: assetID, current: before
        )
        let first = try harness.writer.commitServiceReliability(fixture.bundle)
        let afterFirst = try harness.writer.currentRevision()
        XCTAssertEqual(first.mutationReceipt.expectedRevision,
                       try MutationPortableExpectedRevisionV1(fixture.bundle.expectedRevision))
        XCTAssertEqual(afterFirst.revision, before.revision + 1)
        XCTAssertEqual(try harness.writer.commitServiceReliability(fixture.bundle), first)
        let cold = try harness.reopenWriter()
        XCTAssertEqual(try cold.commitServiceReliability(fixture.bundle), first)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<QualifiedServiceExposureRow>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)

        let substituted = try ReceiptSafetyEvidenceContext.operation(
            workspaceID: workspace, assetID: assetID, mutationID: fixture.bundle.mutationID,
            observationCode: "WRONG_TYPED_C53"
        )
        XCTAssertThrowsError(try harness.writer.commitEvidenceContext(substituted)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertThrowsError(try cold.commitServiceReliability(fixture.bundle)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<QualifiedServiceExposureRow>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationQuarantineRow>()), 1)
    }

    func testEvidenceContextReplayUsesCommittedRevisionBeforeLiveRevisionAndRejectsSubstitution() throws {
        let workspace = WorkspaceID(rawValue: UUID())
        let assetID = UUID()
        let harness = try ReceiptSafetyHarness(workspaceID: workspace) { context in
            let site = Site(label: "Receipt safety context", timeZoneID: "UTC")
            context.insert(site)
            context.insert(Asset(id: assetID, siteID: site.id, packID: "receipt-safety",
                                 packSchemaVersion: 1, packContentVersion: 1,
                                 label: "Receipt safety asset"))
        }
        defer { harness.removeFiles() }
        let operation = try ReceiptSafetyEvidenceContext.operation(workspaceID: workspace, assetID: assetID)
        let first = try harness.writer.commitEvidenceContext(operation)
        let afterFirst = try harness.writer.currentRevision()
        XCTAssertEqual(afterFirst.revision, first.resultingRevision.workspaceRevision)
        XCTAssertEqual(try harness.writer.commitEvidenceContext(operation), first)
        let coldReplay = try harness.reopenWriter().commitEvidenceContext(operation)
        XCTAssertEqual(coldReplay, first)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<EvidenceContextRow>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)

        let changed = try ReceiptSafetyEvidenceContext.operation(
            workspaceID: workspace, assetID: assetID, mutationID: operation.mutationID,
            observationCode: "RECEIPT_SAFETY_CHANGED"
        )
        XCTAssertThrowsError(try harness.writer.commitEvidenceContext(changed)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertThrowsError(try harness.writer.commitEvidenceContext(operation)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
    }
}

@MainActor
private final class ReceiptSafetyHarness {
    let root: URL
    let container: ModelContainer
    let context: ModelContext
    let registry: GenerationLeaseRegistryV1
    let lease: GenerationLeaseTokenV1
    let fence: StaleWriterFenceV1
    let identity: WorkspaceReplicaIdentityV1
    let generationID: UUID
    let writerInstanceID: UUID
    let store: MutationJournalStoreV1
    let writer: WorkspaceWriterV1

    init(workspaceID: WorkspaceID, seed: (ModelContext) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-receipt-safety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root
        let schema = Schema(PersistentSchemaV53.models, version: PersistentSchemaV53.versionIdentifier)
        container = try ModelContainer(for: schema, migrationPlan: nil,
            configurations: [ModelConfiguration("ReceiptSafety", schema: schema,
                isStoredInMemoryOnly: true, allowsSave: true, cloudKitDatabase: .none)])
        context = container.mainContext
        context.autosaveEnabled = false
        try seed(context)
        try context.save()
        generationID = UUID()
        writerInstanceID = UUID()
        identity = try .init(workspaceID: workspaceID, replicaID: .init(rawValue: UUID()))
        let epoch = try GenerationEpochV1(generationID: generationID,
                                         generationManifestSHA256: String(repeating: "a", count: 64))
        registry = try GenerationLeaseRegistryV1(applicationSupportURL: root)
        lease = try registry.acquire(epoch: epoch, role: .writer)
        fence = try StaleWriterFenceV1(expectedGenerationEpoch: epoch, writerLeaseToken: lease,
                                      registry: registry, currentGenerationEpoch: { epoch })
        store = try MutationJournalStoreV1(modelContext: context, identity: identity,
            generationID: generationID, staleWriterFence: fence)
        writer = try WorkspaceWriterV1(identity: identity, generationID: generationID,
            initialRevision: store.currentRevision(writerInstanceID: writerInstanceID),
            clock: ReceiptSafetyClock(), idSource: ReceiptSafetyIDs(value: writerInstanceID),
            fileAuthority: ReceiptSafetyFiles(), adapter: WorkspaceWriterAdapterV1(modelContext: context),
            journalStore: store)
    }

    func reopenWriter() throws -> WorkspaceWriterV1 {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let store = try MutationJournalStoreV1(modelContext: context, identity: identity,
            generationID: generationID, allowStateBootstrap: false, staleWriterFence: fence)
        let id = UUID()
        return try WorkspaceWriterV1(identity: identity, generationID: generationID,
            initialRevision: store.currentRevision(writerInstanceID: id), clock: ReceiptSafetyClock(),
            idSource: ReceiptSafetyIDs(value: id), fileAuthority: ReceiptSafetyFiles(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context), journalStore: store)
    }

    func removeFiles() { try? FileManager.default.removeItem(at: root) }
}

@MainActor
private final class ReceiptSafetyJournalNodeV1 {
    let root: URL
    let identity: WorkspaceReplicaIdentityV1
    let session: StoreGenerationSession
    let coordinator: StoreSessionCoordinator
    let journal: LocalChangeJournalV1

    init(workspaceID: WorkspaceID, replicaID: ReplicaID) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V23-receipt-safety-journal-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        identity = try .init(workspaceID: workspaceID, replicaID: replicaID)
        session = try StoreGenerationFactory(
            applicationSupportURL: root, pointerEnrichmentIdentity: identity
        ).openOrBootstrapCurrent()
        let profiles = try WorkspacePackageLifecycleCompatibilityV1.shippingRegistry()
        coordinator = try StoreSessionCoordinator(
            validatingSession: session, lifecycleProfileRegistry: profiles
        )
        let dependencies = try coordinator.packageLifecycleDependencies(profileRegistry: profiles)
        let backup = BackupExportService(
            modelContext: session.modelContext, generationRootURL: session.generationRootURL,
            lifecycleDependencies: dependencies,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max })
        )
        let catalog = try CurrentSyncClassificationCatalogV1.current
        let subject = try SyncSubjectIdentityV1(
            category: .persistentModel, stableName: "FieldDraftCheckpointRow"
        )
        let fieldDraftPolicy = try catalog.registration(for: subject).conflictPolicy
        journal = try coordinator.localChangeJournal(
            backupExport: backup,
            policyResolver: { identity, _ in
                guard identity.kind == .fieldDraftCheckpoint else {
                    throw ChangeJournalFailureV1.tamperedBatch
                }
                return fieldDraftPolicy
            },
            contentReferenceResolver: { _ in throw ContentContractFailureV1.missingContent },
            contentEntryResolver: { _ in throw ContentContractFailureV1.missingContent }
        )
    }

    var context: ModelContext { coordinator.modelContext }
    var writer: WorkspaceWriterV1 { coordinator.workspaceWriter }

    func removeFiles() { try? FileManager.default.removeItem(at: root) }
}

@MainActor
private final class ReceiptSafetyEmptyMyDaySources: MyDaySourceFrontierReadingV1 {
    func sourceFrontiers(for plan: MyDayPlanV1, evaluatedAt: Date) throws -> [MyDaySourceFrontierV1] {
        guard plan.items.isEmpty else { throw MyDayFailureV1.invalidValue }
        return []
    }
}

private struct ReceiptSafetyClock: ApplicationClock {
    func now() -> Date { C33TemporalEvidenceTestSupport.fixedDate.addingTimeInterval(120) }
}
private struct ReceiptSafetyIDs: ApplicationIDSource {
    let value: UUID
    func makeID() -> UUID { value }
}
private struct ReceiptSafetyFiles: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String {
        "receipt-safety/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

private enum ReceiptSafetyEvidenceContext {
    static func operation(
        workspaceID: WorkspaceID,
        assetID: UUID,
        mutationID: MutationIDV1? = nil,
        observationCode: String = "RECEIPT_SAFETY_CONTEXT"
    ) throws -> EvidenceContextWriteOperationV1 {
        let actor = try LocalActorReferenceV1(actorReferenceID: UUID(), workspaceID: workspaceID,
                                              displayName: "Receipt safety recorder")
        let recordedBy = try ActorSnapshotV1(snapshotID: UUID(), workspaceID: workspaceID, actor: actor,
                                             responsibility: .recordedBy,
                                             displayNameAtTime: actor.displayName,
                                             capturedAt: ReceiptSafetyClock().now())
        let temporal = try TemporalContextV1(
            occurredAtUTC: ReceiptSafetyClock().now(), recordedAtUTC: ReceiptSafetyClock().now(),
            localDate: "2027-01-15", localTime: "08:00:00", utcOffsetSeconds: 0,
            ianaTimeZoneIdentifier: "UTC", localTimeDisposition: .unambiguous
        )
        let resolvedMutationID = try mutationID ?? MutationIDV1(rawValue: UUID())
        let value = try EvidenceContextV1(
            contextID: UUID(), workspaceID: workspaceID, evidenceID: "receipt.safety.context",
            evidenceSHA256: String(repeating: "a", count: 64), evidenceRevision: 1,
            assetID: assetID, assetRevision: 1, temporalContext: temporal,
            userObserved: .init(condition: .unknown, observationNoteCode: observationCode),
            derivedSolar: nil, controlExpectation: nil, predecessor: nil, revision: 1,
            mutationID: resolvedMutationID,
            recordedBy: recordedBy, recordedAt: ReceiptSafetyClock().now()
        )
        return .appendContext(value: value, predecessor: nil)
    }
}

private enum ReceiptSafetyWorkResource {
    struct Fixture {
        let workspaceID: WorkspaceID
        let assetID: UUID
        let actor: ActorSnapshotV1
        let manifest: WorkPacketManifestV1
        let mutation: WorkResourceMutationV1

        func expected(_ current: WorkspaceRevisionV1) throws -> WorkspaceExpectedRevisionV1 {
            try WorkspaceExpectedRevisionV1(
                workspaceID: current.workspaceID, generationID: current.generationID,
                writerInstanceID: current.writerInstanceID, workspaceRevision: current.revision,
                entityRevisions: [.init(identity: try mutation.concurrencyIdentity, revision: 0)]
            )
        }
    }

    static func makeFixture(slot: Int) throws -> Fixture {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let date = ReceiptSafetyClock().now()
        let local = try LocalActorReferenceV1(actorReferenceID: UUID(), workspaceID: workspaceID,
                                              displayName: "Receipt safety work recorder")
        let actor = try ActorSnapshotV1(snapshotID: UUID(), workspaceID: workspaceID, actor: local,
                                        responsibility: .recordedBy, displayNameAtTime: local.displayName,
                                        capturedAt: date)
        let item = try WorkPacketItemV1(itemID: "receipt-safety-work-\(slot)", kind: .inspection,
                                        expectedRevision: 1, itemSHA256: String(repeating: "a", count: 64))
        let manifest = try WorkPacketManifestV1(
            manifestID: UUID(), packetID: UUID(), packetVersion: 1, workspaceID: workspaceID,
            items: [item], packageReleases: [], creationBasis: .explicitLocalSelection,
            creator: actor, createdAt: date, mutationID: .init(rawValue: UUID())
        )
        let mutationID = try MutationIDV1(rawValue: UUID())
        let subject = try WorkResourceSubjectV1(workspaceID: workspaceID, kind: .workPacket,
                                                subjectID: manifest.manifestID.uuidString,
                                                subjectRevision: manifest.revision,
                                                subjectSHA256: manifest.manifestSHA256)
        let entry = try WorkResourceEntryV1(
            entryID: UUID(), workspaceID: workspaceID, subject: subject, actor: actor,
            duration: try ManualDurationV1(minutes: 20), recordedAt: date,
            expectedRevision: 0, revision: 1, mutationID: mutationID
        )
        return try Fixture(workspaceID: workspaceID, assetID: UUID(), actor: actor, manifest: manifest,
                           mutation: .init(workspaceID: workspaceID, mutationID: mutationID, postImage: entry))
    }
}

private enum ReceiptSafetyServiceReliability {
    struct Fixture { let bundle: ServiceReliabilityAtomicBundleV1 }

    static func makeBundle(workspaceID: WorkspaceID, assetID: UUID,
                           current: WorkspaceRevisionV1) throws -> Fixture {
        let date = ReceiptSafetyClock().now()
        let actorReference = try LocalActorReferenceV1(actorReferenceID: UUID(), workspaceID: workspaceID,
                                                        displayName: "Receipt safety reliability recorder")
        let actor = try ActorSnapshotV1(snapshotID: UUID(), workspaceID: workspaceID, actor: actorReference,
                                        responsibility: .recordedBy, displayNameAtTime: actorReference.displayName,
                                        capturedAt: date)
        let package = try PackageReleaseIdentityV1(packageID: "receipt.safety.reliability",
                                                   schemaVersion: 1, contentVersion: 1)
        let binding = try WorkSubjectSemanticBindingSnapshotV1(
            assetID: assetID, kindBindingEventID: UUID(), kindBindingRevision: 1,
            catalogRelease: .init(releaseID: UUID(), packageRelease: package,
                                  catalogSHA256: String(repeating: "a", count: 64)),
            semanticID: "receipt.safety.reliability", workflowPackageReleases: [package]
        )
        let asset = WorkSubjectReferenceV1(kind: .asset, subjectID: assetID, revision: 1, ownerAssetID: nil)
        let scope = try WorkSubjectScopeSnapshotV1(snapshotID: UUID(), workspaceID: workspaceID, siteID: UUID(),
                                                    subjects: [asset], semanticBindings: [binding],
                                                    workspaceRevision: 1, recordedAt: date)
        let subject = ServiceReliabilitySubjectV1(asset: asset, frozenScope: scope, function: nil,
                                                   reliabilityIdentityEpochID: UUID())
        let instant = ServiceReliabilityInstantV1(millisecondsSince1970: Int64(date.timeIntervalSince1970 * 1_000))
        let interval = try ServiceReliabilityClosedIntervalV1(lowerBound: instant,
                                                               upperBound: .init(millisecondsSince1970: instant.millisecondsSince1970 + 60_000))
        let observation = try ObservationBasisV1(kind: .directlyObserved,
                                                  method: try .init(key: "RECEIPT_SAFETY_C53"),
                                                  source: try .init(kind: .observer))
        let temporal = try TemporalContextV1(occurredAtUTC: date, recordedAtUTC: date,
                                             localDate: nil, localTime: nil, utcOffsetSeconds: nil,
                                             ianaTimeZoneIdentifier: nil, localTimeDisposition: .unknown)
        let mutationID = try MutationIDV1(rawValue: UUID())
        let exposure = try QualifiedServiceExposureV1(
            eventID: UUID(), exposureID: UUID(), workspaceID: workspaceID, subject: subject,
            interval: interval, declaredCoverageWindow: interval, coverage: .complete,
            plannedNonserviceExclusions: [], source: .acceptedRecord, observationBasis: observation,
            timeBasis: temporal, sourceNote: "Receipt safety C53", recordedBy: actor,
            revision: 1, mutationID: mutationID
        )
        let identity = try WorkspaceEntityIdentityV1(kind: .qualifiedServiceExposure, id: exposure.eventID)
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: workspaceID, generationID: current.generationID,
            writerInstanceID: current.writerInstanceID, workspaceRevision: current.revision,
            entityRevisions: [.init(identity: identity, revision: 0)]
        )
        return try Fixture(bundle: .init(workspaceID: workspaceID, expectedRevision: expected,
                                         mutationID: mutationID, payloads: [.exposure(exposure)]))
    }
}

@MainActor
private struct ReceiptSafetyTemporalSeed {
    let definition: SurveyDefinitionReleaseV1
    let session: SurveySessionV1
    let promoted: PromotedPackageReleaseV1
    let pointer: ActivePackageRegistryPointerV1
    let clip: TemporalEvidenceClipV1

    init() throws {
        let fixture = try C33TemporalEvidenceTestSupport.clip()
        let workspace = fixture.clip.workspaceID
        definition = try C26SurveySessionTestSupport.release(releaseSlot: 330, workspaceID: workspace)
        let package = try C26SurveySessionTestSupport.packageRelease()
        let provisional = try C26SurveySessionTestSupport.provisional(workspaceID: workspace)
        session = try C26SurveySessionTestSupport.session(
            authority: C26SurveySessionTestSupport.authority(for: definition, package: package),
            workspaceID: workspace, subject: .provisional(provisional.reference),
            state: .draft, transition: .create, revision: 1, actorSlot: 601)
        promoted = try C26SurveySessionTestSupport.promotedPackage(package, workspaceID: workspace, slot: 8001)
        pointer = try ActivePackageRegistryPointerV1(pointerID: UUID(), workspaceID: workspace,
            packageID: package.packageID, activeReleaseRecordID: promoted.releaseRecordID,
            promotionReceiptID: UUID(), activePackageReleaseID: package.packageReleaseID,
            activeReleaseRecordSHA256: promoted.releaseRecordSHA256, revision: 1,
            mutationID: .init(rawValue: UUID()))
        let value = fixture.clip
        clip = try TemporalEvidenceClipV1(clipID: value.clipID, workspaceID: workspace,
            target: .init(workspaceID: workspace, sessionID: session.sessionID,
                sessionRevision: session.revision, sessionSHA256: session.sessionSHA256,
                definitionRelease: fixture.profile.definitionRelease, factID: "fact-a", repeatCoordinates: []),
            original: value.original, originalProvenance: value.originalProvenance, locator: value.locator,
            facts: value.facts, profile: fixture.profile, accessibleDescription: value.accessibleDescription,
            manualTranscript: value.manualTranscript, recordedBy: value.recordedBy,
            capturedAt: value.capturedAt, acceptedAt: value.acceptedAt, revision: value.revision,
            mutationID: value.mutationID)
    }

    func persist(_ context: ModelContext) throws {
        context.insert(try SurveyDefinitionReleaseRow(definition))
        context.insert(try SurveySessionRow(session))
        context.insert(try PromotedPackageReleaseRow(promoted))
        context.insert(try ActivePackageRegistryPointerRow(pointer))
    }

    func removalEvent(policySHA256: String = String(repeating: "f", count: 64),
                      mutationID: MutationIDV1? = nil) throws -> TemporalEvidenceRetentionEventV1 {
        try TemporalEvidenceRetentionEventV1(eventID: C33TemporalEvidenceTestSupport.id(9461),
            clip: clip, disposition: .deleteClip, policySHA256: policySHA256,
            actor: C26SurveySessionTestSupport.actor(workspaceID: clip.workspaceID, slot: 9462,
                                                    responsibility: .reviewedBy),
            occurredAt: C33TemporalEvidenceTestSupport.fixedDate.addingTimeInterval(60), revision: 1,
            mutationID: mutationID ?? C33TemporalEvidenceTestSupport.mutation(9463))
    }
}

@MainActor
private final class ReceiptSafetyCleanupSpy: TemporalEvidenceRetentionContentCleaningV1 {
    private(set) var calls = 0
    func removeCommittedContent(for mutation: TemporalEvidenceMutationV1,
                                receipt: TemporalEvidenceMutationReceiptV1) async throws { calls += 1 }
}

private enum ReceiptSafetyUnexpectedCall: Error { case unusedPort }

private actor ReceiptSafetyUnusedTemporalPorts: TemporalEvidenceImmutableContentPromotingV1,
    TemporalEvidenceScratchLifecycleV1, TemporalEvidenceAdmissionResolvingV1,
    TemporalEvidencePromotionRecoveryPortV1, TemporalEvidenceRetentionCleanupRecoveryPortV1 {
    private(set) var markedCount = 0
    func promote(bytes: Data, clip: TemporalEvidenceClipV1) throws -> DraftImmutableContentWriteReceiptV1 { throw ReceiptSafetyUnexpectedCall.unusedPort }
    func acquire(_ request: CapabilityScratchLeaseRequestV1) throws -> CapabilityScratchLeaseV1 { throw ReceiptSafetyUnexpectedCall.unusedPort }
    func write(_ data: Data, named: String, lease: CapabilityScratchLeaseV1) throws -> URL { throw ReceiptSafetyUnexpectedCall.unusedPort }
    func finish(lease: CapabilityScratchLeaseV1, disposition: ScratchPublicationDispositionV1, immutableContentReceiptDigest: String?) throws -> ScratchPublicationLinkageReceiptV1 { throw ReceiptSafetyUnexpectedCall.unusedPort }
    func recoverAfterInterruption() throws -> ScratchDataLeaseRecoverySummaryV1 { throw ReceiptSafetyUnexpectedCall.unusedPort }
    func currentAdmission(for clip: TemporalEvidenceClipV1) throws -> TemporalEvidenceAdmissionSnapshotV1 { throw ReceiptSafetyUnexpectedCall.unusedPort }
    func prepare(_ reservation: TemporalEvidencePromotionReservationV1) throws { throw ReceiptSafetyUnexpectedCall.unusedPort }
    func transition(_ reservation: TemporalEvidencePromotionReservationV1, to: TemporalEvidencePromotionRecoveryStateV1) throws { throw ReceiptSafetyUnexpectedCall.unusedPort }
    func reservation(workspaceID: WorkspaceID, mutationID: MutationIDV1) throws -> TemporalEvidencePromotionReservationV1? { throw ReceiptSafetyUnexpectedCall.unusedPort }
    func recoverPending() throws -> [TemporalEvidencePromotionReservationV1] { throw ReceiptSafetyUnexpectedCall.unusedPort }
    func promotedContentExists(_ reservation: TemporalEvidencePromotionReservationV1) throws -> Bool { throw ReceiptSafetyUnexpectedCall.unusedPort }
    func adoptCommittedContent(_ reservation: TemporalEvidencePromotionReservationV1, receiptSHA256: String) throws { throw ReceiptSafetyUnexpectedCall.unusedPort }
    func removeUncommittedContent(_ reservation: TemporalEvidencePromotionReservationV1) throws { throw ReceiptSafetyUnexpectedCall.unusedPort }
    func remove(_ reservation: TemporalEvidencePromotionReservationV1) throws { throw ReceiptSafetyUnexpectedCall.unusedPort }
    func prepareCleanup(_ reservation: TemporalEvidenceRetentionCleanupReservationV1) {}
    func markCleanupCommitted(_ reservation: TemporalEvidenceRetentionCleanupReservationV1, receiptSHA256: String) { markedCount += 1 }
    func pendingCleanups() throws -> [TemporalEvidenceRetentionCleanupReservationV1] { throw ReceiptSafetyUnexpectedCall.unusedPort }
    func finishCleanup(_ reservation: TemporalEvidenceRetentionCleanupReservationV1) throws { throw ReceiptSafetyUnexpectedCall.unusedPort }
}

private enum ReceiptSafetyLighting {
    struct Fixture {
        let system: LightingSystemV1
        let dayObservation: LightingObservationV1
        let nightObservation: LightingObservationV1
        let day: LightingDayInventoryWorkflowV1
        let plannedDay: LightingDayInventoryWorkflowV1
        let night: LightingNightWorkflowV1
        let dayAdmission: LightingDayInventoryAdmissionClosureV1
        let nightAdmission: LightingNightWorkflowAdmissionClosureV1
    }

    static func makeFixture(slot: Int) throws -> Fixture {
        let packetFixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 290_000 + slot)
        let workspace = packetFixture.workspaceID
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let actor = try C26SurveySessionTestSupport.actor(workspaceID: workspace)
        let package = try C26SurveySessionTestSupport.packageRelease(workflowID: "c17.report.workflow")
        let packageIdentity = try PackageReleaseIdentityV1(packageID: package.packageID, schemaVersion: 1,
                                                          contentVersion: package.packageContentVersion)
        let assetID = id(202), zoneID = id(203), groupID = id(204), luminaireID = id(205)
        let binding = try WorkSubjectSemanticBindingSnapshotV1(assetID: assetID,
            kindBindingEventID: id(206), kindBindingRevision: 1,
            catalogRelease: .init(releaseID: id(207), packageRelease: packageIdentity, catalogSHA256: digest("a")),
            semanticID: "luminaire.exterior", workflowPackageReleases: [packageIdentity])
        let zone = LightingZoneV1(zoneID: zoneID, displayName: "Day inventory",
            workSubject: .init(kind: .locationNode, subjectID: zoneID, revision: 1, ownerAssetID: nil),
            declaredActivityClass: "PARKING", declaredSecurityClass: "GENERAL")
        let group = ControlGroupV1(controlGroupID: groupID, semanticID: "lighting.primary",
            expectation: try .init(controlGroupID: groupID.uuidString.lowercased(), expectedState: .noExpectation,
                policyID: "C17_LOCAL_POLICY", policyVersion: 1, policySHA256: digest("b")))
        let luminaire = LuminaireAssetV1(luminaireID: luminaireID, assetID: assetID, assetRevision: 1,
            semanticBinding: binding, zoneIDs: [zoneID], controlGroupIDs: [groupID],
            maintenanceDisposition: .independentlyMaintained)
        let system = try LightingSystemV1(recordID: id(208), systemID: id(209), workspaceID: workspace,
            siteID: id(210), packageRelease: .init(package), zones: [zone], controlGroups: [group],
            luminaires: [luminaire], revision: 1, mutationID: .init(rawValue: id(211)),
            recordedBy: actor, recordedAt: date)
        let temporal = try TemporalContextV1(occurredAtUTC: date, recordedAtUTC: date,
            localDate: "2027-01-15", localTime: "08:00:00", utcOffsetSeconds: 0,
            ianaTimeZoneIdentifier: "UTC", localTimeDisposition: .unambiguous)
        let context = try EvidenceContextV1(contextID: id(212), workspaceID: workspace,
            evidenceID: "c17-original", evidenceSHA256: digest("c"), evidenceRevision: 1,
            assetID: assetID, assetRevision: 1, temporalContext: temporal,
            userObserved: .init(condition: .daylight, observationNoteCode: "DAY_NOT_NIGHT_TEST"),
            derivedSolar: nil, controlExpectation: nil, predecessor: nil, revision: 1,
            mutationID: .init(rawValue: id(213)), recordedBy: actor, recordedAt: date)
        let observation = try LightingObservationV1(recordID: id(214), observationID: id(215),
            workspaceID: workspace, system: system, luminaireID: luminaireID, zoneID: zoneID,
            controlGroupID: groupID, evidenceContext: context,
            observationBasis: .init(kind: .directlyObserved, method: .init(key: "c17.manual"),
                source: .init(kind: .observer), limitations: []), issueKinds: [], revision: 1,
            mutationID: .init(rawValue: id(216)), recordedBy: actor, recordedAt: date)
        let path = try LocationPathSnapshotV1(siteID: system.siteID, siteDisplay: "Fixture site", nodes: [])
        let safety = try LightingSafetyIntakeV1(intakeID: id(217), workspaceID: workspace,
            systemID: system.systemID, systemRevision: system.revision, systemSHA256: system.systemSHA256,
            area: zone.workSubject, route: path, timeContext: temporal, siteAuthority: .confirmed,
            requiredPPE: [], confirmedPPE: [], emergencyReadiness: .confirmed,
            trafficSafety: .noTrafficExposure, observerSafety: .authorizedAccessibleVantage,
            recordedBy: actor, recordedAt: date)
        let condition = try LightingDayConditionSnapshotV1(luminaireID: luminaireID, assetID: assetID,
            assetRevision: 1, zoneID: zoneID, controlGroupID: groupID, observation: .init(observation),
            poseDisposition: .notDeclared, poseEvent: nil,
            facts: [.init(aspect: .lens, state: .notObserved, issueKind: nil)], contextualMedia: [])
        let day = try LightingDayInventoryWorkflowV1(recordID: id(223), workflowID: id(224),
            workspaceID: workspace, system: system, safetyIntake: safety, conditionSnapshots: [condition],
            state: .dayInventoryRecorded, revision: 1, mutationID: .init(rawValue: id(225)),
            recordedBy: actor, recordedAt: date)
        let dayAdmission = LightingDayInventoryAdmissionClosureV1(system: system, observations: [observation],
            poseEvents: [], occurrence: nil, workPacket: nil, readiness: nil)
        try dayAdmission.validate(day)

        let nightDate = Date(timeIntervalSince1970: 1_800_046_800)
        let definition = try C26SurveySessionTestSupport.release(workspaceID: workspace)
        let timeBasis = try FrozenScheduleTimeBasisV1(
            ianaTimeZoneIdentifier: "UTC", timeZoneRuleSetVersion: "test-frozen-v1",
            timeZoneRuleSetSHA256: digest("a"), ambiguousTimePolicy: .earlierOffset,
            nonexistentTimePolicy: .shiftForwardByGap, calendarBasisSHA256: digest("b")
        )
        let anchor = ScheduleLocalAnchorV1(
            year: nil, month: nil, day: nil, weekday: nil, weekdayOrdinal: nil,
            hour: 21, minute: 0, second: 0
        )
        let schedule = try ScheduleDefinitionReleaseV1(
            scheduleDefinitionID: id(8_101), releaseID: id(8_102), workspaceID: workspace,
            occurrenceIdentityNamespaceID: id(8_103), action: .create, lifecycleState: .active,
            recurrence: .fixedCalendar(.init(cadence: .daily, interval: 1, anchor: anchor)),
            timeBasis: timeBasis, startsAtUTC: nightDate, generationHorizonDays: 30,
            maximumGeneratedOccurrences: 8, readyLeadSeconds: 0, overdueGraceSeconds: 0,
            subject: WorkSubjectReferenceV1(kind: .asset, subjectID: id(8_104),
                                            revision: 1, ownerAssetID: nil),
            workDefinition: ScheduledWorkDefinitionReferenceV1(
                kind: .workPacket, definition: definition, packageRelease: package
            ),
            revision: 1, mutationID: MutationIDV1(rawValue: id(8_105)),
            authoredBy: actor, authoredAt: nightDate
        )
        let basis = ResolvedOccurrenceBasisV1(
            nominalLocalDate: "2027-01-15", nominalLocalTime: "21:00:00",
            resolvedAtUTC: nightDate, utcOffsetSeconds: 0, disposition: .unambiguous,
            timeBasisSHA256: try timeBasis.canonicalSHA256(), adjustmentProvenanceSHA256: nil
        )
        let occurrenceID = try OccurrenceIDV1(
            scheduleDefinitionID: schedule.scheduleDefinitionID,
            identityNamespaceID: schedule.occurrenceIdentityNamespaceID, nominalKey: basis.nominalKey
        )
        let event = try OccurrenceHistoryEventV1(
            eventID: id(8_106), workspaceID: workspace, occurrenceID: occurrenceID,
            scheduleRelease: ScheduleDefinitionReleaseReferenceV1(schedule),
            action: .generated, nominalBasis: basis, effectiveBasis: basis,
            predecessor: nil, revision: 1, mutationID: MutationIDV1(rawValue: id(8_107)),
            recordedBy: actor, recordedAt: nightDate
        )
        let plan = try LightingNightFollowupPlanV1(planID: id(310), workspaceID: workspace,
            sourceSystemID: system.systemID, sourceSystemRevision: system.revision,
            sourceSystemSHA256: system.systemSHA256, sourceDayInventoryContentSHA256: day.dayInventoryContentSHA256,
            selectedLuminaireIDs: [luminaireID], occurrence: .init(event),
            workPacket: .init(packetFixture.manifest), offlineReadinessSourceSHA256: digest("e"),
            offlineReadinessManifestSHA256: digest("f"), readinessCheckedAt: nightDate,
            createdBy: actor, createdAt: nightDate)
        let plannedDay = try LightingDayInventoryWorkflowV1(recordID: id(311), workflowID: id(312),
            workspaceID: workspace, system: system, safetyIntake: safety, conditionSnapshots: [condition],
            state: .nightFollowupPrepared, nightFollowupPlan: plan, revision: 1,
            mutationID: .init(rawValue: id(313)), recordedBy: actor, recordedAt: nightDate)
        let nightTime = try TemporalContextV1(occurredAtUTC: nightDate, recordedAtUTC: nightDate,
            localDate: "2027-01-15", localTime: "21:00:00", utcOffsetSeconds: 0,
            ianaTimeZoneIdentifier: "UTC", localTimeDisposition: .unambiguous)
        let nightContext = try EvidenceContextV1(contextID: id(314), workspaceID: workspace,
            evidenceID: "receipt-safety-night", evidenceSHA256: digest("8"), evidenceRevision: 1,
            assetID: assetID, assetRevision: 1, temporalContext: nightTime,
            userObserved: .init(condition: .night, observationNoteCode: "NIGHT_INVENTORY"),
            derivedSolar: nil, controlExpectation: nil, predecessor: nil, revision: 1,
            mutationID: .init(rawValue: id(315)), recordedBy: actor, recordedAt: nightDate)
        let nightObservation = try LightingObservationV1(recordID: id(316), observationID: id(317),
            workspaceID: workspace, system: system, luminaireID: luminaireID, zoneID: zoneID,
            controlGroupID: groupID, evidenceContext: nightContext,
            observationBasis: .init(kind: .directlyObserved, method: .init(key: "receipt.night.manual"),
                source: .init(kind: .observer), limitations: []), issueKinds: [], revision: 1,
            mutationID: .init(rawValue: id(318)), recordedBy: actor, recordedAt: nightDate)
        let nightSafety = try LightingSafetyIntakeV1(intakeID: id(319), workspaceID: workspace,
            systemID: system.systemID, systemRevision: system.revision, systemSHA256: system.systemSHA256,
            area: zone.workSubject, route: path, timeContext: nightTime, siteAuthority: .confirmed,
            requiredPPE: [], confirmedPPE: [], emergencyReadiness: .confirmed,
            trafficSafety: .noTrafficExposure, observerSafety: .authorizedAccessibleVantage,
            recordedBy: actor, recordedAt: nightDate)
        let comparableMedia = try ContentReferenceV1(
            workspaceID: workspace.rawValue.uuidString.lowercased(),
            contentID: nightContext.evidenceID, byteLength: 1, mediaType: "image/jpeg",
            digests: .init([.init(algorithm: .sha256,
                hexadecimalValue: nightContext.evidenceSHA256)]),
            byteRole: .immutableOriginal, createdAt: ISO8601DateFormatter().string(from: nightDate))
        let delta = try LightingNightDeltaV1(luminaireID: luminaireID, assetID: assetID, assetRevision: 1,
            zoneID: zoneID, controlGroupID: groupID, observation: .init(nightObservation),
            expectedControl: .noDeclaredExpectation, observedControl: .appearedOn,
            issueKinds: [], comparableMedia: [comparableMedia], temporaryLight: .notObserved,
            weatherContext: .notObserved, surfaceContext: .notObserved, measurement: nil,
            cameraBandingRecordedWithoutFlickerClaim: false)
        let night = try LightingNightWorkflowV1(recordID: id(320), workflowID: id(321),
            workspaceID: workspace, system: system, dayWorkflow: plannedDay,
            safety: .init(intake: nightSafety, nightPlan: plan), deltas: [delta], repairPolicy: .init(),
            state: .nightInventoryRecorded, revision: 1, mutationID: .init(rawValue: id(322)),
            recordedBy: actor, recordedAt: nightDate)
        let nightAdmission = LightingNightWorkflowAdmissionClosureV1(system: system,
            dayWorkflow: plannedDay, observations: [nightObservation], issues: [],
            admittedMeasurementSHA256s: [], patrolSessions: [])
        try nightAdmission.validate(night)
        return .init(system: system, dayObservation: observation, nightObservation: nightObservation,
            day: day, plannedDay: plannedDay, night: night, dayAdmission: dayAdmission,
            nightAdmission: nightAdmission)
    }

    private static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "d1800000-0000-4000-8000-%012x", slot))!
    }
    private static func digest(_ character: Character) -> String {
        String(repeating: String(character), count: 64)
    }
}

// Actual C36 adapter retries retain the original journal envelope even after
// another checkpoint revision and later saga effects advance the workspace.
extension V23MutationReceiptSafetyTests {
    func testFieldDraftAdapterReplaysCheckpointsAndSagasAfterLaterEffectsHotAndCold() throws {
        let workspace = WorkspaceID(rawValue: UUID())
        let harness = try ReceiptSafetyHarness(workspaceID: workspace) { _ in }
        defer { harness.removeFiles() }
        let adapter = FieldDraftLifecycleAdapterV1(writer: harness.writer,
            journal: harness.store, modelContext: harness.context)
        let initial = try ReceiptSafetyFieldDraft.checkpoint(workspaceID: workspace)
        let first = try adapter.compareAndSwap(checkpoint: initial,
            expectedDraftRevision: 0, expectedBaseRevision: 0)
        let committing = try ReceiptSafetyFieldDraft.checkpoint(workspaceID: workspace,
            draftID: initial.draftID, revision: 2, state: .committing)
        let second = try adapter.compareAndSwap(checkpoint: committing,
            expectedDraftRevision: 1, expectedBaseRevision: 0)
        let plan = try DraftCommitPlanV1(planID: UUID(), workspaceID: workspace,
            draftID: committing.draftID, draftRevision: 2, baseCanonicalRevision: 0,
            payloadSHA256: committing.payloadSHA256, stageDigests: [],
            targetCommandKind: .applyMyDay, expectedTargetRevision: 0,
            mutationID: MutationIDV1(rawValue: UUID()), outputKeys: ["fixture-plan"])
        let prepared = try DraftCommitSagaV1(sagaID: UUID(), workspaceID: workspace,
            draftID: committing.draftID, plan: plan, state: .prepared,
            revision: 1, mutationID: MutationIDV1(rawValue: UUID()),
            updatedAt: ReceiptSafetyClock().now())
        let third = try adapter.append(saga: prepared, expectedRevision: 0)
        let promoted = try DraftCommitSagaV1(sagaID: UUID(), workspaceID: workspace,
            draftID: committing.draftID, plan: plan, state: .contentPromotedUnbound,
            predecessorSagaID: prepared.sagaID, revision: 2,
            mutationID: MutationIDV1(rawValue: UUID()), updatedAt: ReceiptSafetyClock().now())
        let fourth = try adapter.append(saga: promoted, expectedRevision: 1)
        let after = try harness.writer.currentRevision()
        XCTAssertEqual(after.revision, first.expectedRevision.workspaceRevision + 4)
        XCTAssertEqual(try adapter.compareAndSwap(checkpoint: initial,
            expectedDraftRevision: 0, expectedBaseRevision: 0), first)
        XCTAssertEqual(try adapter.compareAndSwap(checkpoint: committing,
            expectedDraftRevision: 1, expectedBaseRevision: 0), second)
        XCTAssertEqual(try adapter.append(saga: prepared, expectedRevision: 0), third)
        XCTAssertEqual(try adapter.append(saga: promoted, expectedRevision: 1), fourth)
        let cold = try harness.reopenFieldDraftAuthority()
        XCTAssertNotEqual(try cold.writer.currentRevision().writerInstanceID, after.writerInstanceID)
        XCTAssertEqual(try cold.adapter.compareAndSwap(checkpoint: initial,
            expectedDraftRevision: 0, expectedBaseRevision: 0), first)
        XCTAssertEqual(try cold.adapter.compareAndSwap(checkpoint: committing,
            expectedDraftRevision: 1, expectedBaseRevision: 0), second)
        XCTAssertEqual(try cold.adapter.append(saga: prepared, expectedRevision: 0), third)
        XCTAssertEqual(try cold.adapter.append(saga: promoted, expectedRevision: 1), fourth)
        XCTAssertEqual(try cold.adapter.currentCheckpoint(workspaceID: workspace,
            draftID: initial.draftID), committing)
        XCTAssertEqual(try cold.writer.currentRevision().revision, after.revision)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<DraftCommitSagaRow>()), 2)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 4)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationQuarantineRow>()), 0)
        XCTAssertFalse(harness.context.hasChanges)
        try harness.store.validateAll()
    }

    func testFieldDraftValidDivergentRetriesQuarantineBeforeReturningOriginalReceipt() throws {
        for changeIdentity in [false, true] {
            let workspace = WorkspaceID(rawValue: UUID())
            let harness = try ReceiptSafetyHarness(workspaceID: workspace) { _ in }
            defer { harness.removeFiles() }
            let initial = try ReceiptSafetyFieldDraft.checkpoint(workspaceID: workspace)
            let original = try ReceiptSafetyFieldDraft.mutation(initial)
            let first = try harness.writer.commitFieldDraft(original)
            let changed = try ReceiptSafetyFieldDraft.checkpoint(workspaceID: workspace,
                draftID: changeIdentity ? UUID() : initial.draftID,
                mutationID: initial.mutationID, text: "valid-changed-payload")
            let incoming = try ReceiptSafetyFieldDraft.mutation(changed)
            try incoming.validate()
            let cold = try harness.reopenFieldDraftAuthority()
            XCTAssertThrowsError(try cold.adapter.compareAndSwap(checkpoint: changed,
                expectedDraftRevision: 0, expectedBaseRevision: 0)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
            }
            XCTAssertThrowsError(try cold.writer.fieldDraftReceipt(for: original)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
            }
            XCTAssertThrowsError(try harness.reopenWriter().commitFieldDraft(original)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
            }
            XCTAssertEqual(try cold.adapter.currentCheckpoint(workspaceID: workspace,
                draftID: initial.draftID), initial)
            XCTAssertEqual(try cold.writer.currentRevision().revision,
                first.resultingRevision.workspaceRevision)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()), 1)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationQuarantineRow>()), 1)
        }
    }

    func testFieldDraftCrossKindRetryQuarantinesWithoutCreatingCheckpoint() throws {
        let workspace = WorkspaceID(rawValue: UUID())
        let assetID = UUID()
        let harness = try ReceiptSafetyHarness(workspaceID: workspace) { context in
            let site = Site(label: "Draft collision site", timeZoneID: "UTC")
            context.insert(site)
            context.insert(Asset(id: assetID, siteID: site.id, packID: "receipt-safety",
                packSchemaVersion: 1, packContentVersion: 1, label: "Draft collision asset"))
        }
        defer { harness.removeFiles() }
        let checkpoint = try ReceiptSafetyFieldDraft.checkpoint(workspaceID: workspace)
        let original = try ReceiptSafetyEvidenceContext.operation(workspaceID: workspace,
            assetID: assetID, mutationID: checkpoint.mutationID)
        let first = try harness.writer.commitEvidenceContext(original)
        let cold = try harness.reopenFieldDraftAuthority()
        XCTAssertThrowsError(try cold.adapter.compareAndSwap(checkpoint: checkpoint,
            expectedDraftRevision: 0, expectedBaseRevision: 0)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertThrowsError(try harness.reopenWriter().commitEvidenceContext(original)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertEqual(try cold.writer.currentRevision().revision, first.resultingRevision.workspaceRevision)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()), 0)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationQuarantineRow>()), 1)
    }

    func testFieldDraftRetryRequiresCurrentWriterLeaseAndUncorruptedReceipt() throws {
        for denial in 0..<3 {
            let workspace = WorkspaceID(rawValue: UUID())
            let harness = try ReceiptSafetyHarness(workspaceID: workspace) { _ in }
            defer { harness.removeFiles() }
            let initial = try ReceiptSafetyFieldDraft.checkpoint(workspaceID: workspace)
            let mutation = try ReceiptSafetyFieldDraft.mutation(initial)
            _ = try harness.writer.commitFieldDraft(mutation)
            switch denial {
            case 0: harness.writer.invalidate()
            case 1: try harness.registry.release(harness.lease)
            default:
                let row = try XCTUnwrap(harness.context.fetch(FetchDescriptor<MutationReceiptRow>()).first)
                row.envelopeSHA256 = String(repeating: "0", count: 64)
                try harness.context.save()
            }
            let adapter = FieldDraftLifecycleAdapterV1(writer: harness.writer,
                journal: harness.store, modelContext: harness.context)
            XCTAssertThrowsError(try adapter.compareAndSwap(checkpoint: initial,
                expectedDraftRevision: 0, expectedBaseRevision: 0))
            XCTAssertThrowsError(try harness.writer.fieldDraftReceipt(for: mutation))
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()), 1)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
        }
    }

    func testFieldDraftFirstWriteStillRejectsStaleAndWrongWorkspaceCommands() throws {
        let workspace = WorkspaceID(rawValue: UUID())
        let harness = try ReceiptSafetyHarness(workspaceID: workspace) { _ in }
        defer { harness.removeFiles() }
        let initial = try ReceiptSafetyFieldDraft.checkpoint(workspaceID: workspace)
        _ = try harness.writer.commitFieldDraft(ReceiptSafetyFieldDraft.mutation(initial))
        let stale = try ReceiptSafetyFieldDraft.checkpoint(workspaceID: workspace, draftID: initial.draftID)
        XCTAssertThrowsError(try harness.writer.commitFieldDraft(ReceiptSafetyFieldDraft.mutation(stale))) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .staleWorkspaceRevision)
        }
        let foreign = try ReceiptSafetyFieldDraft.checkpoint(workspaceID: .init(rawValue: UUID()))
        XCTAssertThrowsError(try harness.writer.commitFieldDraft(ReceiptSafetyFieldDraft.mutation(foreign))) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .wrongWorkspace)
        }
        XCTAssertNil(try harness.writer.durableReceipt(mutationID: stale.mutationID))
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationQuarantineRow>()), 0)
    }
}

@MainActor
private extension ReceiptSafetyHarness {
    func reopenFieldDraftAuthority() throws -> (writer: WorkspaceWriterV1, adapter: FieldDraftLifecycleAdapterV1) {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let store = try MutationJournalStoreV1(modelContext: context, identity: identity,
            generationID: generationID, allowStateBootstrap: false, staleWriterFence: fence)
        let id = UUID()
        let writer = try WorkspaceWriterV1(identity: identity, generationID: generationID,
            initialRevision: store.currentRevision(writerInstanceID: id), clock: ReceiptSafetyClock(),
            idSource: ReceiptSafetyIDs(value: id), fileAuthority: ReceiptSafetyFiles(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context), journalStore: store)
        return (writer, FieldDraftLifecycleAdapterV1(writer: writer, journal: store, modelContext: context))
    }
}

private enum ReceiptSafetyFieldDraft {
    /// Explicit test-only codec. This tests the existing C36 writer without
    /// inventing an application purpose registry or a My Day production codec.
    static func checkpoint(workspaceID: WorkspaceID, draftID: UUID = UUID(),
                           revision: UInt64 = 1, state: FieldDraftStateV1 = .active,
                           mutationID: MutationIDV1? = nil, text: String = "draft-replay") throws -> FieldDraftCheckpointV1 {
        try FieldDraftCheckpointV1(draftID: draftID, workspaceID: workspaceID,
            scope: .init(scopeKind: "RECEIPT_SAFETY", stableComponentIDs: ["draft"]),
            purpose: .inspectionReview,
            codec: .init(codecID: "receipt-safety.draft", codecVersion: 1,
                releaseSHA256: String(repeating: "d", count: 64)),
            baseCanonicalRevision: 0, draftRevision: revision, payloadData: Data(text.utf8),
            stageIDs: [], resumeAnchor: .init(sectionID: "draft"), state: state,
            updatedAt: ReceiptSafetyClock().now(), mutationID: mutationID ?? MutationIDV1(rawValue: UUID()))
    }

    static func mutation(_ checkpoint: FieldDraftCheckpointV1) throws -> FieldDraftMutationV1 {
        try .init(workspaceID: checkpoint.workspaceID, expectedRevision: checkpoint.draftRevision - 1,
            expectedBaseCanonicalRevision: checkpoint.baseCanonicalRevision,
            mutationID: checkpoint.mutationID,
            postImage: checkpoint.draftRevision == 1 ? .createCheckpoint(checkpoint) : .reviseCheckpoint(checkpoint))
    }
}


extension V23MutationReceiptSafetyTests {
    func testReviewedDraftRebaseCommitsOneCheckpointAndRetainsOriginalEvidenceHotAndCold() throws {
        for existing in [false, true] {
            let fixture = try ReviewedResolutionTestFixtureV1(now: ReceiptSafetyClock().now())
            let harness = try ReceiptSafetyHarness(workspaceID: fixture.workspaceID) {
                $0.insert(try ActorSnapshotRow(fixture.actor))
            }
            defer { harness.removeFiles() }
            _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.initial))
            if existing {
                _ = try harness.writer.commit(MyDayCommandV1.save(successor: fixture.target, predecessor: nil))
            }
            _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.conflicted))
            let before = try harness.writer.currentRevision()
            let mutation = try fixture.resolution(target: existing ? fixture.target : nil,
                workspaceRevision: before.revision)
            let receipt = try harness.writer.commitFieldDraft(mutation)
            let evidence = try XCTUnwrap(harness.writer.fieldDraftEvidence(mutationID: mutation.mutationID))
            XCTAssertEqual(evidence.mutation, mutation)
            XCTAssertEqual(evidence.receipt, receipt)
            XCTAssertEqual(evidence.envelopeSHA256, try evidence.envelope.canonicalSHA256())
            XCTAssertEqual(receipt.expectedRevision.workspaceRevision, before.revision)
            XCTAssertEqual(receipt.resultingRevision.workspaceRevision, before.revision + 1)
            XCTAssertEqual(receipt.expectedRevision.entityRevisions.count, existing ? 2 : 1)
            XCTAssertEqual(receipt.postImages.count, 1)
            XCTAssertEqual(try receipt.postImages[0].identity.kind, .fieldDraftCheckpoint)
            XCTAssertEqual(try harness.writer.currentPlan(for: fixture.key), existing ? fixture.target : nil)
            guard case let .resolveConflict(resolution) = mutation.postImage else { return XCTFail("Wrong command") }
            let successor = resolution.successorCheckpoint
            let later = try FieldDraftCheckpointV1(draftID: successor.draftID, workspaceID: successor.workspaceID,
                scope: successor.scope, purpose: successor.purpose, codec: successor.codec,
                baseCanonicalRevision: successor.baseCanonicalRevision, draftRevision: 4,
                payloadData: successor.payloadData, stageIDs: successor.stageIDs,
                resumeAnchor: successor.resumeAnchor, state: .active, updatedAt: fixture.now,
                mutationID: .init(rawValue: UUID()))
            _ = try harness.writer.commitFieldDraft(fixture.ordinary(later))
            let after = try harness.writer.currentRevision()
            XCTAssertEqual(try harness.writer.commitFieldDraft(mutation), receipt)
            XCTAssertEqual(try harness.writer.fieldDraftEvidence(mutationID: mutation.mutationID), evidence)
            let cold = try harness.reopenFieldDraftAuthority()
            XCTAssertEqual(try cold.writer.commitFieldDraft(mutation), receipt)
            XCTAssertEqual(try cold.writer.fieldDraftEvidence(mutationID: mutation.mutationID), evidence)
            XCTAssertEqual(try cold.adapter.currentCheckpoint(workspaceID: fixture.workspaceID,
                draftID: later.draftID), later)
            XCTAssertEqual(try cold.writer.currentRevision().revision, after.revision)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()), 1)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MyDayPlanRowV1>()), existing ? 1 : 0)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), existing ? 5 : 4)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationQuarantineRow>()), 0)
            XCTAssertNil(try cold.writer.fieldDraftEvidence(mutationID: .init(rawValue: UUID())))
            XCTAssertFalse(harness.context.hasChanges)
            try harness.store.validateAll()
        }
    }

    func testReviewedDraftRejectsChangedTargetAndRacedAbsenceWithoutEffects() throws {
        for existing in [false, true] {
            let fixture = try ReviewedResolutionTestFixtureV1(now: ReceiptSafetyClock().now())
            let harness = try ReceiptSafetyHarness(workspaceID: fixture.workspaceID) {
                $0.insert(try ActorSnapshotRow(fixture.actor))
            }
            defer { harness.removeFiles() }
            _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.initial))
            if existing { _ = try harness.writer.commit(MyDayCommandV1.save(successor: fixture.target, predecessor: nil)) }
            _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.conflicted))
            let reviewed = try fixture.resolution(target: existing ? fixture.target : nil,
                workspaceRevision: harness.writer.currentRevision().revision)
            if existing {
                let changed = try MyDayPlanV1(planID: fixture.target.planID, key: fixture.key,
                    items: [], predecessor: fixture.target, revision: 2,
                    mutationID: .init(rawValue: UUID()), authoredBy: fixture.actor, authoredAt: fixture.now)
                _ = try harness.writer.commit(MyDayCommandV1.save(successor: changed, predecessor: fixture.target))
            } else {
                _ = try harness.writer.commitFieldDraft(ReceiptSafetyFieldDraft.mutation(
                    ReceiptSafetyFieldDraft.checkpoint(workspaceID: fixture.workspaceID)))
            }
            let beforeDenied = try harness.writer.currentRevision()
            let beforeReceipts = try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>())
            XCTAssertThrowsError(try harness.writer.commitFieldDraft(reviewed))
            XCTAssertEqual(try harness.writer.currentRevision(), beforeDenied)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), beforeReceipts)
            let cold = try harness.reopenFieldDraftAuthority()
            XCTAssertEqual(try cold.adapter.currentCheckpoint(workspaceID: fixture.workspaceID,
                draftID: fixture.conflicted.draftID), fixture.conflicted)
            XCTAssertNil(try cold.writer.fieldDraftEvidence(mutationID: reviewed.mutationID))
            XCTAssertFalse(harness.context.hasChanges)
        }
    }

    func testReviewedDraftAbsentBasisChecksActualTargetInsideWriterTransaction() throws {
        let fixture = try ReviewedResolutionTestFixtureV1(now: ReceiptSafetyClock().now())
        let harness = try ReceiptSafetyHarness(workspaceID: fixture.workspaceID) {
            $0.insert(try ActorSnapshotRow(fixture.actor))
        }
        defer { harness.removeFiles() }
        _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.initial))
        _ = try harness.writer.commit(MyDayCommandV1.save(successor: fixture.target, predecessor: nil))
        _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.conflicted))
        let before = try harness.writer.currentRevision()
        // The workspace CAS is current, but this key is not absent.
        let falseAbsence = try fixture.resolution(target: nil, workspaceRevision: before.revision)
        XCTAssertThrowsError(try harness.writer.commitFieldDraft(falseAbsence)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidCommand)
        }
        XCTAssertEqual(try harness.writer.currentRevision(), before)
        XCTAssertEqual(try harness.writer.currentPlan(for: fixture.key), fixture.target)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 3)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()), 1)
        XCTAssertFalse(harness.context.hasChanges)
    }

    func testReviewedDraftOriginalEvidenceRequiresLiveLeaseFullJournalAndNoQuarantine() throws {
        for denial in 0..<4 {
            let fixture = try ReviewedResolutionTestFixtureV1(now: ReceiptSafetyClock().now())
            let harness = try ReceiptSafetyHarness(workspaceID: fixture.workspaceID) {
                $0.insert(try ActorSnapshotRow(fixture.actor))
            }
            defer { harness.removeFiles() }
            _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.initial))
            _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.conflicted))
            let mutation = try fixture.resolution(target: nil,
                workspaceRevision: harness.writer.currentRevision().revision)
            _ = try harness.writer.commitFieldDraft(mutation)
            XCTAssertNotNil(try harness.writer.fieldDraftEvidence(mutationID: mutation.mutationID))
            switch denial {
            case 0: harness.writer.invalidate()
            case 1: try harness.registry.release(harness.lease)
            case 2:
                let row = try XCTUnwrap(harness.context.fetch(FetchDescriptor<MutationReceiptRow>()).first {
                    $0.mutationID == fixture.initial.mutationID.rawValue
                })
                row.envelopeSHA256 = String(repeating: "0", count: 64)
                try harness.context.save()
            default:
                let changed = try fixture.resolution(target: nil, workspaceRevision: 99,
                    mutationID: mutation.mutationID)
                XCTAssertThrowsError(try harness.writer.commitFieldDraft(changed)) {
                    XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
                }
            }
            XCTAssertThrowsError(try harness.writer.fieldDraftEvidence(mutationID: mutation.mutationID))
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 3)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()), 1)
        }
    }
}


extension V23MutationReceiptSafetyTests {
    func testReviewedDraftAdapterDeniesPreparedConflictWithoutClassificationProof() throws {
        let fixture = try ReviewedResolutionTestFixtureV1.preparedConflictResolution()
        let harness = try ReceiptSafetyHarness(workspaceID: fixture.checkpoint.workspaceID) {
            $0.insert(try FieldDraftCheckpointRow(fixture.checkpoint))
        }
        defer { harness.removeFiles() }
        XCTAssertEqual(try MyDayPlanningDraftCodecV1.validateCheckpointPayload(fixture.checkpoint).phase,
                       .preparedCommit)
        let before = try harness.writer.currentRevision()
        let adapter = WorkspaceWriterAdapterV1(modelContext: harness.context)
        XCTAssertThrowsError(try adapter.apply(.applyFieldDraft(fixture.mutation),
            occurredAt: fixture.checkpoint.updatedAt, temporaryRelativePath: "reviewed-denial")) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidCommand)
        }
        let row = try XCTUnwrap(harness.context.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).first)
        XCTAssertEqual(try row.value(), fixture.checkpoint)
        XCTAssertEqual(try harness.writer.currentRevision(), before)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 0)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MyDayPlanRowV1>()), 0)
        XCTAssertFalse(harness.context.hasChanges)
    }
}


extension V23MutationReceiptSafetyTests {
    func testReviewedResolutionClosureRecoversOriginalAfterLaterDraftAndTargetReceipts() throws {
        for existing in [false, true] {
            let fixture = try ReviewedResolutionTestFixtureV1(now: ReceiptSafetyClock().now())
            let harness = try ReceiptSafetyHarness(workspaceID: fixture.workspaceID) {
                $0.insert(try ActorSnapshotRow(fixture.actor))
            }
            defer { harness.removeFiles() }
            _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.initial))
            if existing { _ = try harness.writer.commit(MyDayCommandV1.save(successor: fixture.target, predecessor: nil)) }
            _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.conflicted))
            let mutation = try fixture.resolution(target: existing ? fixture.target : nil,
                workspaceRevision: harness.writer.currentRevision().revision)
            let receipt = try harness.writer.commitFieldDraft(mutation)
            let evidence = try XCTUnwrap(harness.writer.reviewedFieldDraftResolutionEvidence(mutationID: mutation.mutationID))
            XCTAssertEqual(evidence.original.receipt, receipt)
            XCTAssertEqual(evidence.original.mutation, mutation)
            let laterPlan = try MyDayPlanV1(planID: fixture.target.planID, key: fixture.key,
                items: [], predecessor: existing ? fixture.target : nil, revision: existing ? 2 : 1,
                mutationID: .init(rawValue: UUID()), authoredBy: fixture.actor, authoredAt: fixture.now)
            _ = try harness.writer.commit(MyDayCommandV1.save(successor: laterPlan,
                predecessor: existing ? fixture.target : nil))
            let later = try ReviewedResolutionHistoryFixtureV1.next(evidence.resolution.successorCheckpoint)
            _ = try harness.writer.commitFieldDraft(fixture.ordinary(later))
            let beforeRecovery = try harness.writer.currentRevision()
            let beforeRows = try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>())
            XCTAssertEqual(try harness.writer.reviewedFieldDraftResolutionEvidence(mutationID: mutation.mutationID), evidence)
            XCTAssertEqual(try harness.writer.commitFieldDraft(mutation), receipt)
            let cold = try harness.reopenFieldDraftAuthority()
            XCTAssertEqual(try cold.writer.reviewedFieldDraftResolutionEvidence(mutationID: mutation.mutationID), evidence)
            XCTAssertEqual(try cold.adapter.reviewedFieldDraftResolutionEvidence(mutationID: mutation.mutationID), evidence)
            XCTAssertEqual(try cold.adapter.currentCheckpoint(workspaceID: fixture.workspaceID,
                draftID: later.draftID), later)
            XCTAssertEqual(try cold.writer.currentPlan(for: fixture.key), laterPlan)
            XCTAssertEqual(try cold.writer.currentRevision().revision, beforeRecovery.revision)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), beforeRows)
            XCTAssertNil(try cold.writer.reviewedFieldDraftResolutionEvidence(mutationID: .init(rawValue: UUID())))
            XCTAssertFalse(harness.context.hasChanges)
        }
    }

    func testReviewedResolutionClosureRejectsExternalDraftOrTargetBaselines() throws {
        for missingDraftHistory in [false, true] {
            let fixture = try ReviewedResolutionTestFixtureV1(now: ReceiptSafetyClock().now())
            let harness = try ReceiptSafetyHarness(workspaceID: fixture.workspaceID) { context in
                context.insert(try ActorSnapshotRow(fixture.actor))
                if missingDraftHistory { context.insert(try FieldDraftCheckpointRow(fixture.conflicted)) }
                else { context.insert(try MyDayPlanRowV1(fixture.target)) }
            }
            defer { harness.removeFiles() }
            if !missingDraftHistory {
                _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.initial))
                _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.conflicted))
            }
            let mutation = try fixture.resolution(target: missingDraftHistory ? nil : fixture.target,
                workspaceRevision: harness.writer.currentRevision().revision)
            // The generic external baseline remains valid, but it supplies
            // no authenticated local history for a new reviewed resolution.
            try harness.store.validateAll()
            let before = try harness.writer.currentRevision()
            let counts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
            XCTAssertThrowsError(try harness.writer.commitFieldDraft(mutation))
            XCTAssertNil(try harness.writer.fieldDraftEvidence(mutationID: mutation.mutationID))
            XCTAssertNil(try harness.writer.reviewedFieldDraftResolutionEvidence(mutationID: mutation.mutationID))
            let cold = try harness.reopenFieldDraftAuthority()
            XCTAssertThrowsError(try cold.writer.commitFieldDraft(mutation))
            XCTAssertNil(try cold.adapter.reviewedFieldDraftResolutionEvidence(mutationID: mutation.mutationID))
            XCTAssertEqual(try harness.writer.currentRevision(), before)
            XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), counts)
            XCTAssertFalse(harness.context.hasChanges)
        }
    }

    func testReviewedResolutionClosureRejectsClassificationThatChangesPreservedDraftFields() throws {
        let fixture = try ReviewedResolutionTestFixtureV1(now: ReceiptSafetyClock().now())
        let harness = try ReceiptSafetyHarness(workspaceID: fixture.workspaceID) {
            $0.insert(try ActorSnapshotRow(fixture.actor))
        }
        defer { harness.removeFiles() }
        _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.initial))
        let classified = try ReviewedResolutionHistoryFixtureV1.next(fixture.initial,
            state: .conflicted, anchor: .init(sectionID: "changed-during-classification"))
        _ = try harness.writer.commitFieldDraft(fixture.ordinary(classified))
        let basisMutation = try fixture.resolution(target: nil,
            workspaceRevision: harness.writer.currentRevision().revision)
        guard case let .resolveConflict(basis) = basisMutation.postImage else { return XCTFail("Wrong fixture") }
        let successor = try ReviewedResolutionHistoryFixtureV1.next(classified)
        let myDayBasis = try XCTUnwrap(basis.reviewedTargetBasis.myDayBasis)
        let resolution = try ReviewedDraftConflictResolutionV1(plan: .reviewAndRebase,
            expectedCheckpoint: classified, reviewedTargetBasis: myDayBasis,
            successorCheckpoint: successor)
        let mutation = try FieldDraftMutationV1(workspaceID: fixture.workspaceID,
            expectedRevision: classified.draftRevision, expectedBaseCanonicalRevision: 0,
            mutationID: successor.mutationID, postImage: .resolveConflict(resolution))
        try harness.store.validateAll()
        let before = try harness.writer.currentRevision()
        let counts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
        XCTAssertThrowsError(try harness.writer.commitFieldDraft(mutation))
        XCTAssertNil(try harness.writer.fieldDraftEvidence(mutationID: mutation.mutationID))
        XCTAssertEqual(try harness.writer.currentRevision(), before)
        XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), counts)
        XCTAssertFalse(harness.context.hasChanges)
    }

    func testReviewedResolutionClosureRejectsLaterConflictWithoutReviewedResolution() throws {
        let fixture = try ReviewedResolutionTestFixtureV1(now: ReceiptSafetyClock().now())
        let harness = try ReceiptSafetyHarness(workspaceID: fixture.workspaceID) {
            $0.insert(try ActorSnapshotRow(fixture.actor))
        }
        defer { harness.removeFiles() }
        _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.initial))
        _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.conflicted))
        let mutation = try fixture.resolution(target: nil,
            workspaceRevision: harness.writer.currentRevision().revision)
        _ = try harness.writer.commitFieldDraft(mutation)
        let evidence = try XCTUnwrap(harness.writer.reviewedFieldDraftResolutionEvidence(mutationID: mutation.mutationID))
        let conflicted = try ReviewedResolutionHistoryFixtureV1.next(evidence.resolution.successorCheckpoint, state: .conflicted)
        _ = try harness.writer.commitFieldDraft(fixture.ordinary(conflicted))
        let unreviewed = try ReviewedResolutionHistoryFixtureV1.next(conflicted)
        _ = try harness.writer.commitFieldDraft(fixture.ordinary(unreviewed))
        try harness.store.validateAll()
        XCTAssertThrowsError(try harness.writer.reviewedFieldDraftResolutionEvidence(mutationID: mutation.mutationID))
        XCTAssertEqual(try harness.writer.fieldDraftEvidence(mutationID: mutation.mutationID)?.receipt, evidence.original.receipt)
        XCTAssertFalse(harness.context.hasChanges)
    }

    func testReviewedResolutionClosureRequiresLiveUnquarantinedOriginalAndCompleteJournal() throws {
        for denial in 0..<4 {
            let fixture = try ReviewedResolutionTestFixtureV1(now: ReceiptSafetyClock().now())
            let harness = try ReceiptSafetyHarness(workspaceID: fixture.workspaceID) {
                $0.insert(try ActorSnapshotRow(fixture.actor))
            }
            defer { harness.removeFiles() }
            _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.initial))
            // An ordinary creation remains valid, but is not a resolution.
            XCTAssertThrowsError(try harness.writer.reviewedFieldDraftResolutionEvidence(mutationID: fixture.initial.mutationID))
            _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.conflicted))
            let mutation = try fixture.resolution(target: nil,
                workspaceRevision: harness.writer.currentRevision().revision)
            _ = try harness.writer.commitFieldDraft(mutation)
            XCTAssertNotNil(try harness.writer.reviewedFieldDraftResolutionEvidence(mutationID: mutation.mutationID))
            switch denial {
            case 0: harness.writer.invalidate()
            case 1: try harness.registry.release(harness.lease)
            case 2:
                let row = try XCTUnwrap(harness.context.fetch(FetchDescriptor<MutationReceiptRow>()).first {
                    $0.mutationID == fixture.initial.mutationID.rawValue
                })
                row.envelopeSHA256 = String(repeating: "0", count: 64)
                try harness.context.save()
            default:
                let changed = try fixture.resolution(target: nil, workspaceRevision: 99,
                    mutationID: mutation.mutationID)
                XCTAssertThrowsError(try harness.writer.commitFieldDraft(changed))
            }
            XCTAssertThrowsError(try harness.writer.reviewedFieldDraftResolutionEvidence(mutationID: mutation.mutationID))
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 3)
        }
    }
}

private enum ReviewedResolutionHistoryFixtureV1 {
    static func next(_ previous: FieldDraftCheckpointV1, state: FieldDraftStateV1 = .active,
                     anchor: DraftResumeAnchorV1? = nil) throws -> FieldDraftCheckpointV1 {
        try .init(draftID: previous.draftID, workspaceID: previous.workspaceID,
            scope: previous.scope, purpose: previous.purpose, codec: previous.codec,
            baseCanonicalRevision: previous.baseCanonicalRevision,
            draftRevision: previous.draftRevision + 1, payloadData: previous.payloadData,
            stageIDs: previous.stageIDs, resumeAnchor: anchor ?? previous.resumeAnchor,
            state: state, updatedAt: previous.updatedAt, mutationID: .init(rawValue: UUID()))
    }
}


extension V23MutationReceiptSafetyTests {
    func testReviewedResolutionClosureDefersPendingDiscardUntilDispositionProofExists() throws {
        let fixture = try ReviewedResolutionTestFixtureV1(now: ReceiptSafetyClock().now())
        let harness = try ReceiptSafetyHarness(workspaceID: fixture.workspaceID) {
            $0.insert(try ActorSnapshotRow(fixture.actor))
        }
        defer { harness.removeFiles() }
        _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.initial))
        _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.conflicted))
        let mutation = try fixture.resolution(target: nil,
            workspaceRevision: harness.writer.currentRevision().revision)
        let receipt = try harness.writer.commitFieldDraft(mutation)
        let evidence = try XCTUnwrap(harness.writer.reviewedFieldDraftResolutionEvidence(mutationID: mutation.mutationID))
        let pending = try ReviewedResolutionHistoryFixtureV1.next(
            evidence.resolution.successorCheckpoint, state: .discardPending)
        _ = try harness.writer.commitFieldDraft(fixture.ordinary(pending))
        try harness.store.validateAll()
        XCTAssertEqual(try harness.writer.fieldDraftEvidence(mutationID: mutation.mutationID)?.receipt, receipt)
        XCTAssertThrowsError(try harness.writer.reviewedFieldDraftResolutionEvidence(mutationID: mutation.mutationID))
        XCTAssertFalse(harness.context.hasChanges)
    }
}


extension V23MutationReceiptSafetyTests {
    func testImportedHistoryCannotAdmitReviewedResolutionOrNewLocalPendingResolution() throws {
        let fixture = try ReviewedResolutionTestFixtureV1(now: ReceiptSafetyClock().now())
        let source = try ReceiptSafetyJournalNodeV1(
            workspaceID: fixture.workspaceID, replicaID: .init(rawValue: UUID())
        )
        let target = try ReceiptSafetyJournalNodeV1(
            workspaceID: fixture.workspaceID, replicaID: .init(rawValue: UUID())
        )
        defer {
            source.removeFiles()
            target.removeFiles()
        }
        source.context.insert(try ActorSnapshotRow(fixture.actor))
        try source.context.save()
        XCTAssertEqual(source.coordinator.workspaceIdentity, source.identity)
        XCTAssertEqual(target.coordinator.workspaceIdentity, target.identity)
        XCTAssertEqual(source.identity.workspaceID, target.identity.workspaceID)
        XCTAssertNotEqual(source.coordinator.generationID, target.coordinator.generationID)

        // Export an actual producer sequence from the production journal. The
        // target receives the emitted LocalChangeJournal page, never a fixture
        // constructed as imported history.
        let preparation = try source.journal.prepareCheckpoint(
            supplement: .init(contentEntries: [], reversalEligibility: [])
        )
        _ = try source.journal.activatePreparedCheckpoint(preparation)
        _ = try source.writer.commitFieldDraft(fixture.ordinary(fixture.initial))
        _ = try source.writer.commitFieldDraft(fixture.ordinary(fixture.conflicted))
        let sourceConflict = try source.writer.pendingReviewedMyDayConflictEvidence(draftID: fixture.conflicted.draftID)
        XCTAssertEqual(sourceConflict.conflictedCheckpoint, fixture.conflicted)
        XCTAssertEqual(sourceConflict.editingCheckpoint, fixture.initial)
        let importedResolution = try fixture.resolution(
            target: nil, workspaceRevision: source.writer.currentRevision().revision
        )
        let sourceReceipt = try source.writer.commitFieldDraft(importedResolution)
        let sourceEvidence = try XCTUnwrap(source.writer.reviewedFieldDraftResolutionEvidence(
            mutationID: importedResolution.mutationID
        ))
        XCTAssertEqual(sourceEvidence.original.receipt, sourceReceipt)
        XCTAssertEqual(sourceEvidence.original.mutation, importedResolution)
        let cursor = try source.journal.initialCursor(consumerReplicaID: target.identity.replicaID)
        let batch = try source.journal.page(after: cursor)
        XCTAssertEqual(batch.changes.map(\.envelope.mutationID), [
            fixture.initial.mutationID, fixture.conflicted.mutationID, importedResolution.mutationID,
        ])
        for change in batch.changes {
            _ = try target.writer.executeImported(change)
        }
        // sourceMutationHistorySnapshot exports through MutationJournalStore's
        // validateAll gate, so this validates the actual target journal before
        // exercising either specialized admission path.
        let targetSnapshot = try target.writer.sourceMutationHistorySnapshot()
        XCTAssertEqual(targetSnapshot.receipts.count, 3)

        // Generic imported evidence remains a valid durable receipt, but it
        // cannot become specialized local reviewed-resolution provenance.
        let importedEvidence = try XCTUnwrap(
            target.writer.fieldDraftEvidence(mutationID: importedResolution.mutationID)
        )
        XCTAssertEqual(importedEvidence.receipt.sourceKind, .importedHistory)
        let importedReaderRevision = try target.writer.currentRevision()
        let importedReaderCounts = try PendingReviewedResolutionTestSupportV1.counts(target.context)
        XCTAssertThrowsError(
            try target.writer.reviewedFieldDraftResolutionEvidence(
                mutationID: importedResolution.mutationID
            )
        ) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        XCTAssertEqual(try target.writer.currentRevision(), importedReaderRevision)
        XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(target.context), importedReaderCounts)
        XCTAssertFalse(target.context.hasChanges)

        // Add a real local conflict after that imported prefix, then attempt a
        // new reviewed resolution. The specialized admission must reject it
        // before any receipt, checkpoint, or revision changes are written.
        guard case let .resolveConflict(imported) = importedResolution.postImage else {
            return XCTFail("Wrong imported fixture")
        }
        let localConflict = try ReviewedResolutionHistoryFixtureV1.next(
            imported.successorCheckpoint, state: .conflicted
        )
        _ = try target.writer.commitFieldDraft(fixture.ordinary(localConflict))
        let localSuccessor = try ReviewedResolutionHistoryFixtureV1.next(localConflict)
        let localResolution = try ReviewedDraftConflictResolutionV1(
            plan: .reviewAndRebase,
            expectedCheckpoint: localConflict,
            reviewedTargetBasis: .absent(
                key: fixture.key,
                expectedWorkspaceRevision: target.writer.currentRevision().revision
            ),
            successorCheckpoint: localSuccessor
        )
        let localMutation = try FieldDraftMutationV1(
            workspaceID: fixture.workspaceID,
            expectedRevision: localConflict.draftRevision,
            expectedBaseCanonicalRevision: localConflict.baseCanonicalRevision,
            mutationID: localSuccessor.mutationID,
            postImage: .resolveConflict(localResolution)
        )
        let before = try target.writer.currentRevision()
        let counts = try PendingReviewedResolutionTestSupportV1.counts(target.context)
        XCTAssertThrowsError(try target.writer.pendingReviewedMyDayConflictEvidence(draftID: localConflict.draftID)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        XCTAssertThrowsError(try target.writer.commitFieldDraft(localMutation)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        XCTAssertNil(try target.writer.fieldDraftEvidence(mutationID: localMutation.mutationID))
        XCTAssertEqual(try target.writer.currentRevision(), before)
        XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(target.context), counts)
        XCTAssertFalse(target.context.hasChanges)
    }

    func testPendingReviewedResolutionGenericEntryAndOriginalReplayUseRealReceipts() throws {
        for existing in [false, true] {
            let fixture = try ReviewedResolutionTestFixtureV1(now: ReceiptSafetyClock().now())
            let harness = try ReceiptSafetyHarness(workspaceID: fixture.workspaceID) {
                $0.insert(try ActorSnapshotRow(fixture.actor))
            }
            defer { harness.removeFiles() }
            _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.initial))
            var reviewedTarget: MyDayPlanV1?
            if existing {
                _ = try harness.writer.commit(MyDayCommandV1.save(successor: fixture.target, predecessor: nil))
                let second = try MyDayPlanV1(planID: fixture.target.planID, key: fixture.key,
                    items: [], predecessor: fixture.target, revision: 2,
                    mutationID: .init(rawValue: UUID()), authoredBy: fixture.actor, authoredAt: fixture.now)
                _ = try harness.writer.commit(MyDayCommandV1.save(successor: second, predecessor: fixture.target))
                reviewedTarget = second
            }
            _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.conflicted))
            let mutation = try fixture.resolution(target: reviewedTarget,
                workspaceRevision: harness.writer.currentRevision().revision)
            let request = try PendingReviewedResolutionTestSupportV1.request(mutation, writer: harness.writer)
            let before = try harness.writer.currentRevision()
            _ = try harness.writer.execute(request)
            let original = try XCTUnwrap(harness.writer.fieldDraftEvidence(mutationID: mutation.mutationID))
            XCTAssertEqual(original.mutation, mutation)
            XCTAssertEqual(original.receipt.resultingRevision.workspaceRevision, before.revision + 1)
            XCTAssertEqual(original.receipt.postImages.count, 1)
            XCTAssertEqual(try original.receipt.postImages[0].identity.kind, .fieldDraftCheckpoint)
            guard case let .resolveConflict(resolution) = mutation.postImage else { return XCTFail("Wrong fixture") }
            let later = try ReviewedResolutionHistoryFixtureV1.next(resolution.successorCheckpoint)
            _ = try harness.writer.commitFieldDraft(fixture.ordinary(later))
            let laterPlan = try MyDayPlanV1(planID: fixture.target.planID, key: fixture.key,
                items: [], predecessor: reviewedTarget, revision: existing ? 3 : 1,
                mutationID: .init(rawValue: UUID()), authoredBy: fixture.actor, authoredAt: fixture.now)
            _ = try harness.writer.commit(MyDayCommandV1.save(successor: laterPlan,
                predecessor: reviewedTarget))
            let after = try harness.writer.currentRevision()
            let counts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
            _ = try harness.writer.execute(request)
            XCTAssertEqual(try harness.writer.commitFieldDraft(mutation), original.receipt)
            let cold = try harness.reopenFieldDraftAuthority()
            _ = try cold.writer.execute(request)
            XCTAssertEqual(try cold.writer.fieldDraftEvidence(mutationID: mutation.mutationID), original)
            XCTAssertEqual(try cold.writer.reviewedFieldDraftResolutionEvidence(mutationID: mutation.mutationID)?.original, original)
            XCTAssertEqual(try cold.writer.currentRevision().revision, after.revision)
            XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), counts)
            XCTAssertFalse(harness.context.hasChanges)
        }
    }

    func testPendingReviewedResolutionGenericEntryRejectsExternalHistoryWithoutEffects() throws {
        for missingDraftHistory in [false, true] {
            let fixture = try ReviewedResolutionTestFixtureV1(now: ReceiptSafetyClock().now())
            let harness = try ReceiptSafetyHarness(workspaceID: fixture.workspaceID) { context in
                context.insert(try ActorSnapshotRow(fixture.actor))
                if missingDraftHistory { context.insert(try FieldDraftCheckpointRow(fixture.conflicted)) }
                else { context.insert(try MyDayPlanRowV1(fixture.target)) }
            }
            defer { harness.removeFiles() }
            if !missingDraftHistory {
                _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.initial))
                _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.conflicted))
            }
            try harness.store.validateAll()
            let mutation = try fixture.resolution(target: missingDraftHistory ? nil : fixture.target,
                workspaceRevision: harness.writer.currentRevision().revision)
            let request = try PendingReviewedResolutionTestSupportV1.request(mutation, writer: harness.writer)
            let before = try harness.writer.currentRevision()
            let counts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
            XCTAssertThrowsError(try harness.writer.execute(request))
            XCTAssertEqual(try harness.writer.currentRevision(), before)
            XCTAssertNil(try harness.writer.fieldDraftEvidence(mutationID: mutation.mutationID))
            XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), counts)
            let cold = try harness.reopenFieldDraftAuthority()
            XCTAssertEqual(try cold.adapter.currentCheckpoint(workspaceID: fixture.workspaceID,
                draftID: fixture.conflicted.draftID), fixture.conflicted)
            XCTAssertFalse(harness.context.hasChanges)
        }
    }

    func testPendingReviewedResolutionGenericEntryRequiresLiveAuthorityAndFullJournal() throws {
        for denial in 0..<3 {
            let fixture = try ReviewedResolutionTestFixtureV1(now: ReceiptSafetyClock().now())
            let harness = try ReceiptSafetyHarness(workspaceID: fixture.workspaceID) {
                $0.insert(try ActorSnapshotRow(fixture.actor))
            }
            defer { harness.removeFiles() }
            _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.initial))
            _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.conflicted))
            let mutation = try fixture.resolution(target: nil,
                workspaceRevision: harness.writer.currentRevision().revision)
            let request = try PendingReviewedResolutionTestSupportV1.request(mutation, writer: harness.writer)
            let counts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
            switch denial {
            case 0: harness.writer.invalidate()
            case 1: try harness.registry.release(harness.lease)
            default:
                let row = try XCTUnwrap(harness.context.fetch(FetchDescriptor<MutationReceiptRow>()).first {
                    $0.mutationID == fixture.initial.mutationID.rawValue
                })
                row.envelopeSHA256 = String(repeating: "0", count: 64)
                try harness.context.save()
            }
            XCTAssertThrowsError(try harness.writer.execute(request))
            XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), counts)
            let row = try XCTUnwrap(harness.context.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).first)
            XCTAssertEqual(try row.value(), fixture.conflicted)
            XCTAssertFalse(harness.context.hasChanges)
        }
    }

    func testPendingReviewedResolutionCannotWriteThroughAdapterWithoutJournal() throws {
        let fixture = try ReviewedResolutionTestFixtureV1(now: ReceiptSafetyClock().now())
        let harness = try ReceiptSafetyHarness(workspaceID: fixture.workspaceID) {
            $0.insert(try ActorSnapshotRow(fixture.actor))
        }
        defer { harness.removeFiles() }
        _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.initial))
        _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.conflicted))
        let current = try harness.writer.currentRevision()
        let withoutJournal = try WorkspaceWriterV1(identity: harness.identity,
            generationID: harness.generationID, initialRevision: current,
            clock: ReceiptSafetyClock(), idSource: ReceiptSafetyIDs(value: current.writerInstanceID),
            fileAuthority: ReceiptSafetyFiles(), adapter: WorkspaceWriterAdapterV1(modelContext: harness.context))
        let mutation = try fixture.resolution(target: nil, workspaceRevision: current.revision)
        let request = try PendingReviewedResolutionTestSupportV1.request(mutation, writer: withoutJournal)
        let counts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
        XCTAssertThrowsError(try withoutJournal.execute(request)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        XCTAssertEqual(try withoutJournal.currentRevision(), current)
        XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), counts)
        let row = try XCTUnwrap(harness.context.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).first)
        XCTAssertEqual(try row.value(), fixture.conflicted)
        XCTAssertFalse(harness.context.hasChanges)
    }
}

@MainActor
private enum PendingReviewedResolutionTestSupportV1 {
    static func request(_ mutation: FieldDraftMutationV1, writer: WorkspaceWriterV1) throws -> WorkspaceMutationRequestV1 {
        let current = try writer.currentRevision()
        let expected = try WorkspaceExpectedRevisionV1(workspaceID: current.workspaceID,
            generationID: current.generationID, writerInstanceID: current.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: try mutation.concurrencyIdentities.map {
                .init(identity: $0, revision: try mutation.expectedRevision(for: $0))
            })
        return try .init(mutationID: mutation.mutationID, expectedRevision: expected,
            command: .applyFieldDraft(mutation))
    }

    static func counts(_ context: ModelContext) throws -> [Int] {
        try [context.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()),
             context.fetchCount(FetchDescriptor<DraftCommitSagaRow>()),
             context.fetchCount(FetchDescriptor<MyDayPlanRowV1>()),
             context.fetchCount(FetchDescriptor<MutationReceiptRow>()),
             context.fetchCount(FetchDescriptor<EntityMutationRevisionRow>())]
    }
}

@MainActor
private struct ReceiptSafetyPreparedReviewFixtureV1 {
    let base: ReviewedResolutionTestFixtureV1
    let harness: ReceiptSafetyHarness
    let conflicted: FieldDraftCheckpointV1
    let resolution: FieldDraftMutationV1

    init() throws {
        let base = try ReviewedResolutionTestFixtureV1(now: ReceiptSafetyClock().now())
        let harness = try ReceiptSafetyHarness(workspaceID: base.workspaceID) {
            $0.insert(try ActorSnapshotRow(base.actor))
        }
        self.base = base
        self.harness = harness
        _ = try harness.writer.commitFieldDraft(base.ordinary(base.initial))
        let editing = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(base.initial)
        guard case let .plan(draft, predecessor)? = editing.editingIntent else {
            throw FieldDraftFailureV1.invalidValue
        }
        let workflow = MyDayWorkflowCoordinatorV1(
            canonical: MyDayCoordinatorV1(writer: harness.writer, sourceReader: ReceiptSafetyEmptyMyDaySources()),
            clock: ReceiptSafetyClock()
        )
        let preview = try workflow.previewSave(
            draft: draft, predecessor: predecessor, planID: UUID(),
            mutationID: .init(rawValue: UUID()), actor: base.actor
        )
        let attempt = try MyDayPlanningCommitAttemptInputsV1(
            command: .save(successor: preview.successor, predecessor: preview.predecessor),
            fieldDraftPlanID: UUID(), preparedSagaID: UUID(), contentPromotedSagaID: UUID(),
            targetCommittedSagaID: UUID(), draftRetirePendingSagaID: UUID(), draftRetiredSagaID: UUID(),
            preparedSagaMutationID: .init(rawValue: UUID()),
            contentPromotedSagaMutationID: .init(rawValue: UUID()),
            targetCommittedSagaMutationID: .init(rawValue: UUID()),
            draftRetirePendingSagaMutationID: .init(rawValue: UUID()),
            terminalBundleMutationID: .init(rawValue: UUID()), commitReceiptID: UUID(),
            preparedSagaUpdatedAt: base.now, contentPromotedSagaUpdatedAt: base.now,
            targetCommittedSagaUpdatedAt: base.now, draftRetirePendingSagaUpdatedAt: base.now,
            draftRetiredSagaUpdatedAt: base.now, terminalCheckpointUpdatedAt: base.now
        )
        let prepared = try MyDayPlanningDraftPayloadV1(prepared: attempt)
        let committing = try Self.successor(of: base.initial, state: .committing,
            payload: MyDayPlanningDraftCodecV1.encode(prepared))
        _ = try harness.writer.commitFieldDraft(base.ordinary(committing))
        let reconstruction = try MyDayPlanningDraftCodecV1.reconstructCommit(from: committing)
        _ = try harness.writer.commitFieldDraft(.init(
            workspaceID: base.workspaceID, expectedRevision: 0, expectedBaseCanonicalRevision: 0,
            mutationID: attempt.preparedSagaMutationID, postImage: .appendCommitSaga(reconstruction.prepared)
        ))
        _ = try harness.writer.commitFieldDraft(.init(
            workspaceID: base.workspaceID, expectedRevision: reconstruction.prepared.revision,
            expectedBaseCanonicalRevision: 0, mutationID: attempt.contentPromotedSagaMutationID,
            postImage: .advanceCommitSaga(reconstruction.contentPromoted)
        ))
        let conflict = try Self.successor(of: committing, state: .conflicted, payload: committing.payloadData)
        _ = try harness.writer.commitFieldDraft(base.ordinary(conflict))
        conflicted = conflict
        let successor = try Self.successor(of: conflict, state: .active, payload: base.initial.payloadData)
        resolution = try .init(
            workspaceID: base.workspaceID, expectedRevision: conflict.draftRevision,
            expectedBaseCanonicalRevision: conflict.baseCanonicalRevision, mutationID: successor.mutationID,
            postImage: .resolveConflict(.init(plan: .reviewAndRebase, expectedCheckpoint: conflict,
                reviewedTargetBasis: .absent(key: base.key,
                    expectedWorkspaceRevision: harness.writer.currentRevision().revision),
                successorCheckpoint: successor))
        )
    }

    private static func successor(
        of predecessor: FieldDraftCheckpointV1, state: FieldDraftStateV1, payload: Data
    ) throws -> FieldDraftCheckpointV1 {
        try .init(draftID: predecessor.draftID, workspaceID: predecessor.workspaceID,
            scope: predecessor.scope, purpose: predecessor.purpose, codec: predecessor.codec,
            baseCanonicalRevision: predecessor.baseCanonicalRevision,
            draftRevision: predecessor.draftRevision + 1, payloadData: payload,
            stageIDs: predecessor.stageIDs, resumeAnchor: predecessor.resumeAnchor, state: state,
            lastDurableMutationID: predecessor.lastDurableMutationID,
            lastReceiptSHA256: predecessor.lastReceiptSHA256, updatedAt: predecessor.updatedAt,
            mutationID: .init(rawValue: UUID()))
    }

    func mintProof() throws -> PreparedReviewedFieldDraftApplyProofV1 {
        try XCTUnwrap(harness.store.validatePendingReviewedFieldDraftResolution(
            resolution, expectedWorkspaceRevision: harness.writer.currentRevision().revision
        ))
    }

    func changedMutation() throws -> FieldDraftMutationV1 {
        let successor = try Self.successor(of: conflicted, state: .active, payload: base.initial.payloadData)
        return try .init(workspaceID: base.workspaceID, expectedRevision: conflicted.draftRevision,
            expectedBaseCanonicalRevision: conflicted.baseCanonicalRevision, mutationID: successor.mutationID,
            postImage: .resolveConflict(.init(plan: .reviewAndRebase, expectedCheckpoint: conflicted,
                reviewedTargetBasis: .absent(key: base.key,
                    expectedWorkspaceRevision: harness.writer.currentRevision().revision),
                successorCheckpoint: successor)))
    }

    func physicalCheckpoint(in context: ModelContext? = nil) throws -> FieldDraftCheckpointV1 {
        let draftID = conflicted.draftID
        let rows = try (context ?? harness.context).fetch(FetchDescriptor<FieldDraftCheckpointRow>(
            predicate: #Predicate { $0.draftID == draftID }
        ))
        guard rows.count == 1, let row = rows.first else { throw FieldDraftFailureV1.invalidValue }
        return try row.value()
    }
}

extension V23MutationReceiptSafetyTests {
    func testPreparedReviewedProofBindsCommandContextAndConsumesEveryAttempt() throws {
        for crossContext in [false, true] {
            let fixture = try ReceiptSafetyPreparedReviewFixtureV1()
            let harness = fixture.harness
            defer { harness.removeFiles() }
            let proof = try fixture.mintProof()
            let before = try harness.writer.currentRevision()
            let counts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
            let otherContext = ModelContext(harness.container)
            otherContext.autosaveEnabled = false
            let selectedContext = crossContext ? otherContext : harness.context
            let selectedMutation = try crossContext ? fixture.resolution : fixture.changedMutation()
            let adapter = WorkspaceWriterAdapterV1(modelContext: selectedContext)
            XCTAssertThrowsError(try adapter.applyPreparedReviewedFieldDraftResolution(
                selectedMutation, proof: proof, occurredAt: fixture.base.now,
                temporaryRelativePath: "prepared-proof-denial"
            )) { XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt) }
            XCTAssertThrowsError(try proof.validateForApply(fixture.resolution, in: harness.context)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
            }
            XCTAssertThrowsError(try WorkspaceWriterAdapterV1(modelContext: harness.context).apply(
                .applyFieldDraft(fixture.resolution), occurredAt: fixture.base.now,
                temporaryRelativePath: "prepared-generic-denial"
            )) { XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidCommand) }
            XCTAssertEqual(try fixture.physicalCheckpoint(), fixture.conflicted)
            XCTAssertEqual(try fixture.physicalCheckpoint(in: otherContext), fixture.conflicted)
            XCTAssertEqual(try harness.writer.currentRevision(), before)
            XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), counts)
            XCTAssertFalse(harness.context.hasChanges)
            XCTAssertFalse(otherContext.hasChanges)
        }
    }

    func testPreparedReviewedProofRechecksRevisionLeaseAndFullJournalBeforeEffects() throws {
        for denial in 0..<3 {
            let fixture = try ReceiptSafetyPreparedReviewFixtureV1()
            let harness = fixture.harness
            defer { harness.removeFiles() }
            let proof = try fixture.mintProof()
            switch denial {
            case 0:
                let unrelated = try ReviewedResolutionTestFixtureV1(
                    workspaceID: fixture.base.workspaceID, now: fixture.base.now
                )
                _ = try harness.writer.commitFieldDraft(unrelated.ordinary(unrelated.initial))
            case 1:
                try harness.registry.release(harness.lease)
            default:
                let row = try XCTUnwrap(harness.context.fetch(FetchDescriptor<MutationReceiptRow>()).first {
                    $0.mutationID == fixture.base.initial.mutationID.rawValue
                })
                row.envelopeSHA256 = String(repeating: "0", count: 64)
                try harness.context.save()
            }
            let states = try harness.context.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
            let workspaceRevision = try XCTUnwrap(states.first).workspaceRevision
            let counts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
            XCTAssertThrowsError(try WorkspaceWriterAdapterV1(modelContext: harness.context)
                .applyPreparedReviewedFieldDraftResolution(fixture.resolution, proof: proof,
                    occurredAt: fixture.base.now, temporaryRelativePath: "prepared-live-authority-denial"))
            XCTAssertThrowsError(try proof.validateForApply(fixture.resolution, in: harness.context)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
            }
            XCTAssertEqual(try fixture.physicalCheckpoint(), fixture.conflicted)
            XCTAssertEqual(try XCTUnwrap(harness.context.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).first)
                .workspaceRevision, workspaceRevision)
            XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), counts)
            XCTAssertFalse(harness.context.hasChanges)
        }
    }

    func testPreparedReviewedProofIsSingleUseAfterAdapterEffectRollbackAndWriterCanRetry() throws {
        let fixture = try ReceiptSafetyPreparedReviewFixtureV1()
        let harness = fixture.harness
        defer { harness.removeFiles() }
        let proof = try fixture.mintProof()
        let before = try harness.writer.currentRevision()
        let counts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
        let adapter = WorkspaceWriterAdapterV1(modelContext: harness.context)
        let effect = try adapter.applyPreparedReviewedFieldDraftResolution(
            fixture.resolution, proof: proof, occurredAt: fixture.base.now,
            temporaryRelativePath: "prepared-proof-unsaved-effect"
        )
        XCTAssertEqual(effect.affectedEntities, try fixture.resolution.affectedIdentities)
        guard case let .resolveConflict(resolution) = fixture.resolution.postImage else {
            return XCTFail("Expected explicit prepared rebase")
        }
        XCTAssertEqual(try fixture.physicalCheckpoint(), resolution.successorCheckpoint)
        XCTAssertTrue(harness.context.hasChanges)
        adapter.rollback()
        XCTAssertEqual(try fixture.physicalCheckpoint(), fixture.conflicted)
        XCTAssertEqual(try harness.writer.currentRevision(), before)
        XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), counts)
        XCTAssertThrowsError(try adapter.applyPreparedReviewedFieldDraftResolution(
            fixture.resolution, proof: proof, occurredAt: fixture.base.now,
            temporaryRelativePath: "prepared-proof-reuse-denial"
        )) { XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt) }
        XCTAssertFalse(harness.context.hasChanges)
        let receipt = try harness.writer.commitFieldDraft(fixture.resolution)
        let original = try XCTUnwrap(harness.writer.reviewedFieldDraftResolutionEvidence(
            mutationID: fixture.resolution.mutationID
        ))
        XCTAssertEqual(original.original.receipt, receipt)
        XCTAssertEqual(original.original.mutation, fixture.resolution)
        XCTAssertEqual(try harness.writer.currentRevision().revision, before.revision + 1)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<DraftCommitSagaRow>()), 2)
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MyDayPlanRowV1>()), 0)
        XCTAssertEqual(try harness.writer.commitFieldDraft(fixture.resolution), receipt)
        XCTAssertEqual(try harness.writer.currentRevision().revision, before.revision + 1)
    }

    func testPreparedReviewedProofCannotBeMintedByMaintenanceJournal() throws {
        let fixture = try ReceiptSafetyPreparedReviewFixtureV1()
        let harness = fixture.harness
        defer { harness.removeFiles() }
        let maintenance = try MutationJournalStoreV1(modelContext: harness.context,
            identity: harness.identity, generationID: harness.generationID, allowStateBootstrap: false)
        let before = try harness.writer.currentRevision()
        let counts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
        XCTAssertThrowsError(try maintenance.validatePendingReviewedFieldDraftResolution(
            fixture.resolution, expectedWorkspaceRevision: before.revision
        ))
        XCTAssertEqual(try fixture.physicalCheckpoint(), fixture.conflicted)
        XCTAssertEqual(try harness.writer.currentRevision(), before)
        XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), counts)
        XCTAssertFalse(harness.context.hasChanges)
    }
}

extension V23MutationReceiptSafetyTests {
    func testPendingConflictReadReturnsActualEditingAndPreparedOriginalsWithoutEffects() throws {
        do {
            let fixture = try ReviewedResolutionTestFixtureV1(now: ReceiptSafetyClock().now())
            let harness = try ReceiptSafetyHarness(workspaceID: fixture.workspaceID) {
                $0.insert(try ActorSnapshotRow(fixture.actor))
            }
            defer { harness.removeFiles() }
            _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.initial))
            _ = try harness.writer.commitFieldDraft(fixture.ordinary(fixture.conflicted))
            let before = try harness.writer.currentRevision()
            let counts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
            let evidence = try harness.writer.pendingReviewedMyDayConflictEvidence(draftID: fixture.initial.draftID)
            XCTAssertEqual(evidence.conflictedCheckpoint, fixture.conflicted)
            XCTAssertEqual(evidence.editingCheckpoint, fixture.initial)
            XCTAssertEqual(evidence.conflict, try harness.writer.fieldDraftEvidence(mutationID: fixture.conflicted.mutationID))
            XCTAssertEqual(evidence.editing, try harness.writer.fieldDraftEvidence(mutationID: fixture.initial.mutationID))
            XCTAssertNil(evidence.preparedEpoch)
            XCTAssertEqual(try harness.store.pendingReviewedMyDayConflictEvidence(draftID: fixture.initial.draftID), evidence)
            XCTAssertEqual(try harness.writer.currentRevision(), before)
            XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), counts)
            XCTAssertFalse(harness.context.hasChanges)
        }
        do {
            let fixture = try ReceiptSafetyPreparedReviewFixtureV1()
            let harness = fixture.harness
            defer { harness.removeFiles() }
            let proof = try fixture.mintProof()
            let before = try harness.writer.currentRevision()
            let counts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
            let evidence = try harness.writer.pendingReviewedMyDayConflictEvidence(draftID: fixture.conflicted.draftID)
            XCTAssertEqual(evidence.conflictedCheckpoint, fixture.conflicted)
            XCTAssertEqual(evidence.editingCheckpoint, fixture.base.initial)
            XCTAssertEqual(evidence.editing, try harness.writer.fieldDraftEvidence(mutationID: fixture.base.initial.mutationID))
            let epoch = try XCTUnwrap(evidence.preparedEpoch)
            let reconstruction = try MyDayPlanningDraftCodecV1.reconstructCommit(from: epoch.committingCheckpoint)
            XCTAssertEqual(epoch.sagaPrefix.map(\.mutation.mutationID), [reconstruction.prepared.mutationID,
                reconstruction.contentPromoted.mutationID])
            for original in [evidence.conflict, epoch.committing] + epoch.sagaPrefix {
                XCTAssertEqual(try harness.writer.fieldDraftEvidence(mutationID: original.mutation.mutationID), original)
            }
            XCTAssertEqual(try harness.writer.pendingReviewedMyDayConflictEvidence(draftID: fixture.conflicted.draftID), evidence)
            // A read must not consume an already minted same-context proof.
            try proof.validateForApply(fixture.resolution, in: harness.context)
            XCTAssertEqual(try fixture.physicalCheckpoint(), fixture.conflicted)
            XCTAssertEqual(try harness.writer.currentRevision(), before)
            XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), counts)
            XCTAssertFalse(harness.context.hasChanges)
        }
    }

    func testPendingConflictReadDeniesBrokenHistoryNonCanonicalAndNonConflictTipsWithoutEffects() throws {
        for denial in 0..<6 {
            let fixture = try ReceiptSafetyPreparedReviewFixtureV1()
            let harness = fixture.harness
            defer { harness.removeFiles() }
            switch denial {
            case 0:
                let row = try XCTUnwrap(harness.context.fetch(FetchDescriptor<MutationReceiptRow>()).first {
                    $0.mutationID == fixture.conflicted.mutationID.rawValue
                })
                harness.context.delete(row)
                try harness.context.save()
            case 1:
                let valid = try harness.writer.pendingReviewedMyDayConflictEvidence(draftID: fixture.conflicted.draftID)
                let committing = try XCTUnwrap(valid.preparedEpoch).committingCheckpoint
                let reconstruction = try MyDayPlanningDraftCodecV1.reconstructCommit(from: committing)
                harness.context.insert(try DraftCommitSagaRow(reconstruction.targetCommitted))
                try harness.context.save()
            case 2:
                let row = try XCTUnwrap(harness.context.fetch(FetchDescriptor<MutationReceiptRow>()).first {
                    $0.mutationID == fixture.base.initial.mutationID.rawValue
                })
                row.envelopeSHA256 = String(repeating: "0", count: 64)
                try harness.context.save()
            case 3:
                try harness.registry.release(harness.lease)
            case 5:
                _ = try harness.writer.commitFieldDraft(fixture.resolution)
            default:
                break
            }
            let before = try XCTUnwrap(harness.context.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).first).workspaceRevision
            let counts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
            let checkpoint = try fixture.physicalCheckpoint()
            if denial == 4 {
                let maintenance = try MutationJournalStoreV1(modelContext: harness.context,
                    identity: harness.identity, generationID: harness.generationID, allowStateBootstrap: false)
                XCTAssertThrowsError(try maintenance.pendingReviewedMyDayConflictEvidence(draftID: fixture.conflicted.draftID)) {
                    XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
                }
            } else {
                XCTAssertThrowsError(try harness.writer.pendingReviewedMyDayConflictEvidence(draftID: fixture.conflicted.draftID))
            }
            XCTAssertEqual(try XCTUnwrap(harness.context.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).first).workspaceRevision, before)
            XCTAssertEqual(try fixture.physicalCheckpoint(), checkpoint)
            XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), counts)
            XCTAssertFalse(harness.context.hasChanges)
        }
    }
}

extension V23MutationReceiptSafetyTests {
    func testPendingConflictReadRejectsActualRelatedQuarantineAndPreservesUnrelatedQuarantine() throws {
        for related in [true, false] {
            let fixture = try ReceiptSafetyPreparedReviewFixtureV1()
            let harness = fixture.harness
            defer { harness.removeFiles() }
            let pending = try harness.writer.pendingReviewedMyDayConflictEvidence(draftID: fixture.conflicted.draftID)
            let selectedMutation: FieldDraftMutationV1
            if related {
                selectedMutation = try fixture.base.ordinary(fixture.base.initial)
            } else {
                let initial = fixture.base.initial
                let unrelated = try FieldDraftCheckpointV1(draftID: UUID(), workspaceID: initial.workspaceID,
                    scope: initial.scope, purpose: initial.purpose, codec: initial.codec,
                    baseCanonicalRevision: initial.baseCanonicalRevision, draftRevision: 1,
                    payloadData: initial.payloadData, stageIDs: [], resumeAnchor: initial.resumeAnchor,
                    state: .active, updatedAt: initial.updatedAt, mutationID: .init(rawValue: UUID()))
                selectedMutation = try fixture.base.ordinary(unrelated)
                _ = try harness.writer.commitFieldDraft(selectedMutation)
            }
            let changedRequest = try PendingReviewedResolutionTestSupportV1.request(selectedMutation, writer: harness.writer)
            let changedEnvelope = try MutationEnvelopeV1(request: changedRequest,
                identity: harness.identity, correlationID: UUID())
            XCTAssertThrowsError(try harness.store.resolveReplay(envelope: changedEnvelope, detectedAt: fixture.base.now)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
            }
            // A valid retained quarantine passes generic integrity validation.
            // Only a matching original makes this specialized read unavailable.
            try harness.store.validateAll()
            let before = try harness.writer.currentRevision()
            let counts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
            let quarantineCount = try harness.context.fetchCount(FetchDescriptor<MutationQuarantineRow>())
            XCTAssertEqual(quarantineCount, 1)
            if related {
                XCTAssertThrowsError(try harness.writer.pendingReviewedMyDayConflictEvidence(draftID: fixture.conflicted.draftID)) {
                    XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
                }
            } else {
                XCTAssertEqual(try harness.writer.pendingReviewedMyDayConflictEvidence(draftID: fixture.conflicted.draftID), pending)
            }
            XCTAssertEqual(try fixture.physicalCheckpoint(), fixture.conflicted)
            XCTAssertEqual(try harness.writer.currentRevision(), before)
            XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), counts)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationQuarantineRow>()), quarantineCount)
            XCTAssertFalse(harness.context.hasChanges)
        }
    }
}

extension V23MutationReceiptSafetyTests {
    func testClassifiableReadAuthenticatesLatestActualEditingWithoutEffects() throws {
        let base = try ReviewedResolutionTestFixtureV1(now: ReceiptSafetyClock().now())
        let harness = try ReceiptSafetyHarness(workspaceID: base.workspaceID) {
            $0.insert(try ActorSnapshotRow(base.actor))
        }
        defer { harness.removeFiles() }
        _ = try harness.writer.commitFieldDraft(base.ordinary(base.initial))
        let latest = try ReviewedResolutionHistoryFixtureV1.next(base.initial)
        _ = try harness.writer.commitFieldDraft(base.ordinary(latest))
        let before = try harness.writer.currentRevision()
        let counts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
        let original = try XCTUnwrap(harness.writer.fieldDraftEvidence(mutationID: latest.mutationID))
        let evidence = try harness.writer.classifiableMyDayPlanEvidence(draftID: latest.draftID)
        XCTAssertEqual(evidence.editing, original)
        XCTAssertEqual(evidence.editingCheckpoint, latest)
        XCTAssertEqual(evidence.currentCheckpoint, latest)
        XCTAssertNil(evidence.preparedEpoch)
        XCTAssertEqual(try harness.store.classifiableMyDayPlanEvidence(draftID: latest.draftID), evidence)
        XCTAssertEqual(try harness.writer.currentRevision(), before)
        XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), counts)
        XCTAssertFalse(harness.context.hasChanges)
    }

    func testClassifiableReadDeniesMissingCorruptAndUnavailableAuthorityWithoutEffects() throws {
        for denial in 0..<5 {
            let base = try ReviewedResolutionTestFixtureV1(now: ReceiptSafetyClock().now())
            let harness = try ReceiptSafetyHarness(workspaceID: base.workspaceID) {
                $0.insert(try ActorSnapshotRow(base.actor))
            }
            defer { harness.removeFiles() }
            _ = try harness.writer.commitFieldDraft(base.ordinary(base.initial))
            XCTAssertEqual(try harness.writer.classifiableMyDayPlanEvidence(draftID: base.initial.draftID).currentCheckpoint, base.initial)
            switch denial {
            case 0:
                let row = try XCTUnwrap(harness.context.fetch(FetchDescriptor<MutationReceiptRow>()).first {
                    $0.mutationID == base.initial.mutationID.rawValue
                })
                harness.context.delete(row)
                try harness.context.save()
            case 1:
                let row = try XCTUnwrap(harness.context.fetch(FetchDescriptor<MutationReceiptRow>()).first {
                    $0.mutationID == base.initial.mutationID.rawValue
                })
                row.envelopeSHA256 = String(repeating: "0", count: 64)
                try harness.context.save()
            case 2: try harness.registry.release(harness.lease)
            case 3: harness.writer.invalidate()
            default: break
            }
            let before = try XCTUnwrap(harness.context.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).first).workspaceRevision
            let counts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
            if denial == 4 {
                let maintenance = try MutationJournalStoreV1(modelContext: harness.context,
                    identity: harness.identity, generationID: harness.generationID, allowStateBootstrap: false)
                XCTAssertThrowsError(try maintenance.classifiableMyDayPlanEvidence(draftID: base.initial.draftID))
            } else {
                XCTAssertThrowsError(try harness.writer.classifiableMyDayPlanEvidence(draftID: base.initial.draftID))
            }
            XCTAssertEqual(try XCTUnwrap(harness.context.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).first).workspaceRevision, before)
            XCTAssertEqual(try XCTUnwrap(harness.context.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).first).value(), base.initial)
            XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), counts)
            XCTAssertFalse(harness.context.hasChanges)
        }
    }

    func testClassifiableReadRejectsActualImportedEditingOriginalWithoutEffects() throws {
        let base = try ReviewedResolutionTestFixtureV1(now: ReceiptSafetyClock().now())
        let source = try ReceiptSafetyJournalNodeV1(workspaceID: base.workspaceID, replicaID: .init(rawValue: UUID()))
        let target = try ReceiptSafetyJournalNodeV1(workspaceID: base.workspaceID, replicaID: .init(rawValue: UUID()))
        defer { source.removeFiles(); target.removeFiles() }
        source.context.insert(try ActorSnapshotRow(base.actor))
        try source.context.save()
        let preparation = try source.journal.prepareCheckpoint(supplement: .init(contentEntries: [], reversalEligibility: []))
        _ = try source.journal.activatePreparedCheckpoint(preparation)
        _ = try source.writer.commitFieldDraft(base.ordinary(base.initial))
        XCTAssertEqual(try source.writer.classifiableMyDayPlanEvidence(draftID: base.initial.draftID).currentCheckpoint, base.initial)
        let cursor = try source.journal.initialCursor(consumerReplicaID: target.identity.replicaID)
        let batch = try source.journal.page(after: cursor)
        XCTAssertEqual(batch.changes.map(\.envelope.mutationID), [base.initial.mutationID])
        for change in batch.changes { _ = try target.writer.executeImported(change) }
        XCTAssertEqual(try target.writer.sourceMutationHistorySnapshot().receipts.count, 1)
        let original = try XCTUnwrap(target.writer.fieldDraftEvidence(mutationID: base.initial.mutationID))
        XCTAssertEqual(original.receipt.sourceKind, .importedHistory)
        let before = try target.writer.currentRevision()
        let counts = try PendingReviewedResolutionTestSupportV1.counts(target.context)
        XCTAssertThrowsError(try target.writer.classifiableMyDayPlanEvidence(draftID: base.initial.draftID)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        XCTAssertEqual(try target.writer.fieldDraftEvidence(mutationID: base.initial.mutationID), original)
        XCTAssertEqual(try target.writer.currentRevision(), before)
        XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(target.context), counts)
        XCTAssertFalse(target.context.hasChanges)
    }

    func testPreparedTargetReplayCollisionDeniesBothConflictReadersWithoutEffects() throws {
        for preclassified in [false, true] {
            for prefixCount in 0...2 {
                let fixture = try ReceiptSafetyClassifiablePreparedFixtureV1(prefixCount: prefixCount, preclassified: preclassified)
                let harness = fixture.harness
                defer { harness.removeFiles() }
                if preclassified {
                    XCTAssertEqual(try harness.writer.pendingReviewedMyDayConflictEvidence(draftID: fixture.tip.draftID).conflictedCheckpoint, fixture.tip)
                } else {
                    let evidence = try harness.writer.classifiableMyDayPlanEvidence(draftID: fixture.tip.draftID)
                    XCTAssertEqual(evidence.currentCheckpoint, fixture.tip)
                    XCTAssertEqual(evidence.editingCheckpoint, fixture.base.initial)
                    XCTAssertEqual(try XCTUnwrap(evidence.preparedEpoch).sagaPrefix.count, prefixCount)
                }
                let reconstruction = try MyDayPlanningDraftCodecV1.reconstructCommit(from: fixture.committing)
                // An unrelated accepted field-draft command can occupy this
                // unreserved target ID. The actual My Day replay path then
                // persists its quarantine without an applyMyDay receipt.
                let initial = fixture.base.initial
                let unrelated = try FieldDraftCheckpointV1(draftID: UUID(), workspaceID: initial.workspaceID,
                    scope: initial.scope, purpose: initial.purpose, codec: initial.codec,
                    baseCanonicalRevision: 0, draftRevision: 1, payloadData: initial.payloadData,
                    stageIDs: [], resumeAnchor: initial.resumeAnchor, state: .active,
                    updatedAt: initial.updatedAt, mutationID: reconstruction.command.mutationID)
                _ = try harness.writer.commitFieldDraft(fixture.base.ordinary(unrelated))
                XCTAssertThrowsError(try harness.writer.commit(reconstruction.command)) {
                    XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
                }
                try harness.store.validateAll()
                XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MyDayPlanRowV1>()), 0)
                let quarantines = try harness.context.fetch(FetchDescriptor<MutationQuarantineRow>())
                XCTAssertEqual(quarantines.map(\.mutationID), [reconstruction.command.mutationID.rawValue])
                let before = try harness.writer.currentRevision()
                let counts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
                if preclassified {
                    XCTAssertThrowsError(try harness.writer.pendingReviewedMyDayConflictEvidence(draftID: fixture.tip.draftID)) {
                        XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
                    }
                } else {
                    XCTAssertThrowsError(try harness.writer.classifiableMyDayPlanEvidence(draftID: fixture.tip.draftID)) {
                        XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
                    }
                }
                let physical = try XCTUnwrap(harness.context.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).first {
                    $0.draftID == fixture.tip.draftID
                })
                XCTAssertEqual(try physical.value(), fixture.tip)
                XCTAssertEqual(try harness.writer.currentRevision(), before)
                XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), counts)
                XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MutationQuarantineRow>()), 1)
                XCTAssertFalse(harness.context.hasChanges)
            }
        }
    }
}

@MainActor
private struct ReceiptSafetyClassifiablePreparedFixtureV1 {
    let base: ReviewedResolutionTestFixtureV1
    let harness: ReceiptSafetyHarness
    let committing: FieldDraftCheckpointV1
    let tip: FieldDraftCheckpointV1

    init(prefixCount: Int, preclassified: Bool) throws {
        let base = try ReviewedResolutionTestFixtureV1(now: ReceiptSafetyClock().now())
        let harness = try ReceiptSafetyHarness(workspaceID: base.workspaceID) {
            $0.insert(try ActorSnapshotRow(base.actor))
        }
        self.base = base
        self.harness = harness
        _ = try harness.writer.commitFieldDraft(base.ordinary(base.initial))
        let editing = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(base.initial)
        guard (0...2).contains(prefixCount), case let .plan(draft, predecessor)? = editing.editingIntent else {
            throw FieldDraftFailureV1.invalidValue
        }
        let workflow = MyDayWorkflowCoordinatorV1(
            canonical: MyDayCoordinatorV1(writer: harness.writer, sourceReader: ReceiptSafetyEmptyMyDaySources()),
            clock: ReceiptSafetyClock())
        let preview = try workflow.previewSave(draft: draft, predecessor: predecessor,
            planID: UUID(), mutationID: .init(rawValue: UUID()), actor: base.actor)
        let attempt = try MyDayPlanningCommitAttemptInputsV1(
            command: .save(successor: preview.successor, predecessor: preview.predecessor),
            fieldDraftPlanID: UUID(), preparedSagaID: UUID(), contentPromotedSagaID: UUID(),
            targetCommittedSagaID: UUID(), draftRetirePendingSagaID: UUID(), draftRetiredSagaID: UUID(),
            preparedSagaMutationID: .init(rawValue: UUID()), contentPromotedSagaMutationID: .init(rawValue: UUID()),
            targetCommittedSagaMutationID: .init(rawValue: UUID()), draftRetirePendingSagaMutationID: .init(rawValue: UUID()),
            terminalBundleMutationID: .init(rawValue: UUID()), commitReceiptID: UUID(),
            preparedSagaUpdatedAt: base.now, contentPromotedSagaUpdatedAt: base.now,
            targetCommittedSagaUpdatedAt: base.now, draftRetirePendingSagaUpdatedAt: base.now,
            draftRetiredSagaUpdatedAt: base.now, terminalCheckpointUpdatedAt: base.now)
        let payload = try MyDayPlanningDraftCodecV1.encode(.init(prepared: attempt))
        let committing = try Self.successor(base.initial, state: .committing, payload: payload)
        self.committing = committing
        _ = try harness.writer.commitFieldDraft(base.ordinary(committing))
        let reconstruction = try MyDayPlanningDraftCodecV1.reconstructCommit(from: committing)
        if prefixCount >= 1 {
            _ = try harness.writer.commitFieldDraft(.init(workspaceID: base.workspaceID,
                expectedRevision: 0, expectedBaseCanonicalRevision: 0,
                mutationID: attempt.preparedSagaMutationID, postImage: .appendCommitSaga(reconstruction.prepared)))
        }
        if prefixCount >= 2 {
            _ = try harness.writer.commitFieldDraft(.init(workspaceID: base.workspaceID,
                expectedRevision: reconstruction.prepared.revision, expectedBaseCanonicalRevision: 0,
                mutationID: attempt.contentPromotedSagaMutationID, postImage: .advanceCommitSaga(reconstruction.contentPromoted)))
        }
        if preclassified {
            let conflict = try Self.successor(committing, state: .conflicted, payload: committing.payloadData)
            _ = try harness.writer.commitFieldDraft(base.ordinary(conflict))
            tip = conflict
        } else { tip = committing }
    }

    private static func successor(_ prior: FieldDraftCheckpointV1, state: FieldDraftStateV1, payload: Data) throws -> FieldDraftCheckpointV1 {
        try .init(draftID: prior.draftID, workspaceID: prior.workspaceID,
            scope: prior.scope, purpose: prior.purpose, codec: prior.codec,
            baseCanonicalRevision: prior.baseCanonicalRevision, draftRevision: prior.draftRevision + 1,
            payloadData: payload, stageIDs: prior.stageIDs, resumeAnchor: prior.resumeAnchor, state: state,
            lastDurableMutationID: prior.lastDurableMutationID, lastReceiptSHA256: prior.lastReceiptSHA256,
            updatedAt: prior.updatedAt, mutationID: .init(rawValue: UUID()))
    }
}

extension V23MutationReceiptSafetyTests {
    func testCarryoverEvidenceRejectsGenuineImportedActiveHistoryWhileGenericHistoryRemainsValid() throws {
        let fixture = try CarryoverEvidenceBoundaryFixtureV1()
        let source = try CarryoverEvidenceJournalNodeV1(workspaceID: fixture.base.workspaceID, replicaID: .init(rawValue: UUID()))
        let target = try CarryoverEvidenceJournalNodeV1(workspaceID: fixture.base.workspaceID, replicaID: .init(rawValue: UUID()))
        defer { source.removeFiles(); target.removeFiles() }
        for node in [source, target] {
            node.context.insert(try ActorSnapshotRow(fixture.base.actor))
            try node.context.save()
            try fixture.seedSource(in: node.writer)
        }
        let preparation = try source.journal.prepareCheckpoint(supplement: .init(contentEntries: [], reversalEligibility: []))
        _ = try source.journal.activatePreparedCheckpoint(preparation)
        _ = try source.writer.commitFieldDraft(fixture.base.ordinary(fixture.editing))
        let local = try source.writer.classifiableMyDayCarryoverEvidence(draftID: fixture.editing.draftID)
        XCTAssertEqual(local.currentCheckpoint, fixture.editing)
        let cursor = try source.journal.initialCursor(consumerReplicaID: target.identity.replicaID)
        let batch = try source.journal.page(after: cursor)
        XCTAssertEqual(batch.changes.map(\.envelope.mutationID), [fixture.editing.mutationID])
        for change in batch.changes { _ = try target.writer.executeImported(change) }
        let history = try target.writer.sourceMutationHistorySnapshot()
        XCTAssertEqual(history.receipts.count, 3)
        let imported = try XCTUnwrap(target.writer.fieldDraftEvidence(mutationID: fixture.editing.mutationID))
        XCTAssertEqual(imported.receipt.sourceKind, .importedHistory)
        let revision = try target.writer.currentRevision()
        let counts = try PendingReviewedResolutionTestSupportV1.counts(target.context)
        XCTAssertThrowsError(try target.writer.classifiableMyDayCarryoverEvidence(draftID: fixture.editing.draftID)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        XCTAssertEqual(try target.writer.fieldDraftEvidence(mutationID: fixture.editing.mutationID), imported)
        XCTAssertEqual(try target.writer.currentPlan(for: fixture.source.key), fixture.source)
        XCTAssertEqual(try target.writer.currentRevision(), revision)
        XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(target.context), counts)
        XCTAssertFalse(target.context.hasChanges)
    }

    func testCarryoverEvidenceRejectsActualPlanOriginalAndCannotUseItAsCarryoverShape() throws {
        let base = try ReviewedResolutionTestFixtureV1(now: ReceiptSafetyClock().now())
        let harness = try ReceiptSafetyHarness(workspaceID: base.workspaceID) {
            $0.insert(try ActorSnapshotRow(base.actor))
        }
        defer { harness.removeFiles() }
        _ = try harness.writer.commitFieldDraft(base.ordinary(base.initial))
        let original = try XCTUnwrap(harness.writer.fieldDraftEvidence(mutationID: base.initial.mutationID))
        let revision = try harness.writer.currentRevision()
        let counts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
        XCTAssertThrowsError(try ClassifiableMyDayCarryoverEvidenceV1(editing: original, preparedEpoch: nil))
        XCTAssertThrowsError(try harness.writer.classifiableMyDayCarryoverEvidence(draftID: base.initial.draftID))
        XCTAssertEqual(try harness.writer.classifiableMyDayPlanEvidence(draftID: base.initial.draftID).currentCheckpoint, base.initial)
        XCTAssertEqual(try harness.writer.currentRevision(), revision)
        XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), counts)
        XCTAssertFalse(harness.context.hasChanges)
    }

    func testCarryoverPreparedDeclaredTargetQuarantineRejectsEveryPreTargetPrefixWithoutEffects() throws {
        for prefix in 0...2 {
            let fixture = try CarryoverEvidenceBoundaryFixtureV1()
            let harness = try ReceiptSafetyHarness(workspaceID: fixture.base.workspaceID) {
                $0.insert(try ActorSnapshotRow(fixture.base.actor))
            }
            defer { harness.removeFiles() }
            try fixture.seedSource(in: harness.writer)
            let prepared = try fixture.prepare(in: harness.writer, prefixCount: prefix)
            let valid = try harness.writer.classifiableMyDayCarryoverEvidence(draftID: fixture.editing.draftID)
            XCTAssertEqual(valid.currentCheckpoint, prepared.checkpoint)
            XCTAssertEqual(try XCTUnwrap(valid.preparedEpoch).sagaPrefix.count, prefix)
            let old = fixture.work
            let unrelated = try FieldDraftCheckpointV1(draftID: UUID(), workspaceID: old.workspaceID,
                scope: old.scope, purpose: old.purpose, codec: old.codec,
                baseCanonicalRevision: 0, draftRevision: 1, payloadData: old.payloadData,
                stageIDs: [], resumeAnchor: old.resumeAnchor, state: .active,
                updatedAt: old.updatedAt, mutationID: prepared.command.mutationID)
            _ = try harness.writer.commitFieldDraft(fixture.base.ordinary(unrelated))
            XCTAssertThrowsError(try harness.writer.commit(prepared.command)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
            }
            try harness.store.validateAll()
            XCTAssertEqual(try harness.context.fetch(FetchDescriptor<MutationQuarantineRow>()).map(\.mutationID),
                           [prepared.command.mutationID.rawValue])
            let revision = try harness.writer.currentRevision()
            let counts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
            XCTAssertThrowsError(try harness.writer.classifiableMyDayCarryoverEvidence(draftID: fixture.editing.draftID)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
            }
            XCTAssertEqual(try harness.writer.currentRevision(), revision)
            XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), counts)
            XCTAssertEqual(try harness.writer.currentPlan(for: fixture.source.key), fixture.source)
            XCTAssertNil(try harness.writer.currentPlan(for: fixture.base.key))
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MyDayCarryoverReceiptRowV1>()), 0)
            let physical = try XCTUnwrap(harness.context.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).first {
                $0.draftID == fixture.editing.draftID
            })
            XCTAssertEqual(try physical.value(), prepared.checkpoint)
            XCTAssertFalse(harness.context.hasChanges)
        }
    }

    func testCarryoverEvidenceRequiresTheActualRetainedSourceReceiptWithoutInventingHistory() throws {
        let fixture = try CarryoverEvidenceBoundaryFixtureV1()
        let harness = try ReceiptSafetyHarness(workspaceID: fixture.base.workspaceID) {
            $0.insert(try ActorSnapshotRow(fixture.base.actor))
        }
        defer { harness.removeFiles() }
        try fixture.seedSource(in: harness.writer)
        _ = try harness.writer.commitFieldDraft(fixture.base.ordinary(fixture.editing))
        let valid = try harness.writer.classifiableMyDayCarryoverEvidence(draftID: fixture.editing.draftID)
        XCTAssertEqual(valid.currentCheckpoint, fixture.editing)
        let sourceReceipt = try XCTUnwrap(harness.context.fetch(FetchDescriptor<MutationReceiptRow>()).first {
            $0.mutationID == fixture.source.mutationID.rawValue
        })
        harness.context.delete(sourceReceipt)
        try harness.context.save()
        let revision = try harness.writer.currentRevision()
        let counts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
        XCTAssertThrowsError(try harness.writer.classifiableMyDayCarryoverEvidence(draftID: fixture.editing.draftID))
        XCTAssertEqual(try harness.writer.currentRevision(), revision)
        XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), counts)
        XCTAssertEqual(try harness.context.fetch(FetchDescriptor<MyDayPlanRowV1>()).map { try $0.value() }, [fixture.source])
        XCTAssertFalse(harness.context.hasChanges)
    }
}


extension V23MutationReceiptSafetyTests {
    func testPendingCarryoverConflictReadAuthenticatesActualActiveAndPreparedPrefixesWithoutEffects() throws {
        for prefixCount in 0...2 {
            let fixture = try CarryoverEvidenceBoundaryFixtureV1()
            let harness = try ReceiptSafetyHarness(workspaceID: fixture.base.workspaceID) {
                $0.insert(try ActorSnapshotRow(fixture.base.actor))
            }
            defer { harness.removeFiles() }
            try fixture.seedSource(in: harness.writer)

            _ = try harness.writer.commitFieldDraft(fixture.base.ordinary(fixture.editing))
            let activeConflict = try ReviewedResolutionHistoryFixtureV1.next(
                fixture.editing, state: .conflicted
            )
            _ = try harness.writer.commitFieldDraft(fixture.base.ordinary(activeConflict))
            let active = try harness.writer.pendingReviewedMyDayCarryoverConflictEvidence(
                draftID: fixture.editing.draftID
            )
            let activeBefore = try harness.writer.currentRevision()
            let activeCounts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
            XCTAssertEqual(try harness.writer.pendingReviewedMyDayCarryoverConflictEvidence(
                draftID: fixture.editing.draftID
            ), active)
            XCTAssertEqual(active.conflictedCheckpoint, activeConflict)
            XCTAssertEqual(active.editingCheckpoint, fixture.editing)
            XCTAssertNil(active.preparedEpoch)
            XCTAssertThrowsError(try harness.writer.pendingReviewedMyDayConflictEvidence(
                draftID: fixture.editing.draftID
            ))
            XCTAssertEqual(try harness.writer.currentRevision(), activeBefore)
            XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), activeCounts)
            XCTAssertFalse(harness.context.hasChanges)

            // Use a separate genuine draft for the committing sequence, so an
            // active conflict never stands in for a prepared epoch.
            let preparedFixture = try CarryoverEvidenceBoundaryFixtureV1()
            let preparedHarness = try ReceiptSafetyHarness(workspaceID: preparedFixture.base.workspaceID) {
                $0.insert(try ActorSnapshotRow(preparedFixture.base.actor))
            }
            defer { preparedHarness.removeFiles() }
            try preparedFixture.seedSource(in: preparedHarness.writer)
            let prepared = try preparedFixture.prepare(in: preparedHarness.writer, prefixCount: prefixCount)
            let conflict = try ReviewedResolutionHistoryFixtureV1.next(
                prepared.checkpoint, state: .conflicted
            )
            _ = try preparedHarness.writer.commitFieldDraft(preparedFixture.base.ordinary(conflict))
            let first = try preparedHarness.writer.pendingReviewedMyDayCarryoverConflictEvidence(
                draftID: preparedFixture.editing.draftID
            )
            let before = try preparedHarness.writer.currentRevision()
            let counts = try PendingReviewedResolutionTestSupportV1.counts(preparedHarness.context)
            let second = try preparedHarness.writer.pendingReviewedMyDayCarryoverConflictEvidence(
                draftID: preparedFixture.editing.draftID
            )
            XCTAssertEqual(first, second)
            XCTAssertEqual(first.conflictedCheckpoint, conflict)
            XCTAssertEqual(first.editingCheckpoint, preparedFixture.editing)
            XCTAssertEqual(try XCTUnwrap(first.preparedEpoch).committingCheckpoint, prepared.checkpoint)
            XCTAssertEqual(try XCTUnwrap(first.preparedEpoch).sagaPrefix.count, prefixCount)
            XCTAssertThrowsError(try preparedHarness.writer.pendingReviewedMyDayConflictEvidence(
                draftID: preparedFixture.editing.draftID
            ))
            XCTAssertEqual(try preparedHarness.writer.currentRevision(), before)
            XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(preparedHarness.context), counts)
            XCTAssertEqual(try preparedHarness.writer.currentPlan(for: preparedFixture.source.key), preparedFixture.source)
            XCTAssertNil(try preparedHarness.writer.currentPlan(for: preparedFixture.base.key))
            XCTAssertFalse(preparedHarness.context.hasChanges)
        }
    }

    func testPendingCarryoverConflictReadRejectsActualSourceAdvanceButAllowsTargetAdvance() throws {
        // The authenticated source reference must still be current.
        do {
            let fixture = try CarryoverEvidenceBoundaryFixtureV1()
            let harness = try ReceiptSafetyHarness(workspaceID: fixture.base.workspaceID) {
                $0.insert(try ActorSnapshotRow(fixture.base.actor))
            }
            defer { harness.removeFiles() }
            try fixture.seedSource(in: harness.writer)
            _ = try harness.writer.commitFieldDraft(fixture.base.ordinary(fixture.editing))
            let conflict = try ReviewedResolutionHistoryFixtureV1.next(fixture.editing, state: .conflicted)
            _ = try harness.writer.commitFieldDraft(fixture.base.ordinary(conflict))
            _ = try harness.writer.pendingReviewedMyDayCarryoverConflictEvidence(draftID: fixture.editing.draftID)
            let advancedSource = try fixture.successorPlan(fixture.source, predecessor: fixture.source)
            _ = try harness.writer.commit(.save(successor: advancedSource, predecessor: fixture.source))
            let before = try harness.writer.currentRevision()
            let counts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
            XCTAssertThrowsError(try harness.writer.pendingReviewedMyDayCarryoverConflictEvidence(
                draftID: fixture.editing.draftID
            )) { XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt) }
            XCTAssertEqual(try harness.writer.currentPlan(for: fixture.source.key), advancedSource)
            XCTAssertEqual(try harness.writer.currentRevision(), before)
            XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), counts)
            XCTAssertFalse(harness.context.hasChanges)
        }

        // A retained target predecessor is historical evidence, so a later
        // target save is permitted while the source remains unchanged.
        do {
            let fixture = try CarryoverEvidenceBoundaryFixtureV1()
            let harness = try ReceiptSafetyHarness(workspaceID: fixture.base.workspaceID) {
                $0.insert(try ActorSnapshotRow(fixture.base.actor))
            }
            defer { harness.removeFiles() }
            try fixture.seedSource(in: harness.writer)
            let target = try fixture.targetPlan()
            _ = try harness.writer.commit(.save(successor: target, predecessor: nil))
            let editing = try fixture.editing(targetPredecessor: target)
            _ = try harness.writer.commitFieldDraft(fixture.base.ordinary(editing))
            let conflict = try ReviewedResolutionHistoryFixtureV1.next(editing, state: .conflicted)
            _ = try harness.writer.commitFieldDraft(fixture.base.ordinary(conflict))
            let expected = try harness.writer.pendingReviewedMyDayCarryoverConflictEvidence(draftID: editing.draftID)
            let advancedTarget = try fixture.successorPlan(target, predecessor: target)
            _ = try harness.writer.commit(.save(successor: advancedTarget, predecessor: target))
            let before = try harness.writer.currentRevision()
            let counts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
            XCTAssertEqual(try harness.writer.pendingReviewedMyDayCarryoverConflictEvidence(
                draftID: editing.draftID
            ), expected)
            XCTAssertEqual(try harness.writer.currentPlan(for: fixture.source.key), fixture.source)
            XCTAssertEqual(try harness.writer.currentPlan(for: fixture.base.key), advancedTarget)
            XCTAssertEqual(try harness.writer.currentRevision(), before)
            XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), counts)
            XCTAssertFalse(harness.context.hasChanges)
        }
    }

    func testPendingCarryoverConflictReadDeniesAfterActualPreparedTargetCommitWithoutEffects() throws {
        for prefixCount in 0...2 {
            let fixture = try CarryoverEvidenceBoundaryFixtureV1()
            let harness = try ReceiptSafetyHarness(workspaceID: fixture.base.workspaceID) {
                $0.insert(try ActorSnapshotRow(fixture.base.actor))
            }
            defer { harness.removeFiles() }
            try fixture.seedSource(in: harness.writer)
            let prepared = try fixture.prepare(in: harness.writer, prefixCount: prefixCount)
            let conflict = try ReviewedResolutionHistoryFixtureV1.next(prepared.checkpoint, state: .conflicted)
            _ = try harness.writer.commitFieldDraft(fixture.base.ordinary(conflict))
            let pending = try harness.writer.pendingReviewedMyDayCarryoverConflictEvidence(
                draftID: fixture.editing.draftID
            )
            XCTAssertEqual(pending.conflictedCheckpoint, conflict)
            XCTAssertEqual(try XCTUnwrap(pending.preparedEpoch).sagaPrefix.count, prefixCount)
            let original = try XCTUnwrap(harness.writer.fieldDraftEvidence(
                mutationID: fixture.editing.mutationID
            ))
            guard case let .carryover(_, _, expectedTarget, _) = prepared.command else {
                return XCTFail("Expected carryover command")
            }

            _ = try harness.writer.commit(prepared.command)
            try harness.store.validateAll()
            let before = try harness.writer.currentRevision()
            let counts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
            XCTAssertThrowsError(try harness.writer.pendingReviewedMyDayCarryoverConflictEvidence(
                draftID: fixture.editing.draftID
            )) { XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt) }
            XCTAssertEqual(try harness.writer.fieldDraftEvidence(mutationID: fixture.editing.mutationID), original)
            XCTAssertEqual(try harness.writer.currentPlan(for: fixture.source.key), fixture.source)
            XCTAssertEqual(try harness.writer.currentPlan(for: fixture.base.key), expectedTarget)
            let physical = try XCTUnwrap(harness.context.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).first {
                $0.draftID == fixture.editing.draftID
            })
            XCTAssertEqual(try physical.value(), conflict)
            XCTAssertEqual(try harness.writer.currentRevision(), before)
            XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), counts)
            XCTAssertFalse(harness.context.hasChanges)
        }
    }

    func testPendingCarryoverConflictReadRejectsDeclaredTargetReplayQuarantineWithoutEffects() throws {
        for prefixCount in 0...2 {
            let fixture = try CarryoverEvidenceBoundaryFixtureV1()
            let harness = try ReceiptSafetyHarness(workspaceID: fixture.base.workspaceID) {
                $0.insert(try ActorSnapshotRow(fixture.base.actor))
            }
            defer { harness.removeFiles() }
            try fixture.seedSource(in: harness.writer)
            let prepared = try fixture.prepare(in: harness.writer, prefixCount: prefixCount)
            let conflict = try ReviewedResolutionHistoryFixtureV1.next(prepared.checkpoint, state: .conflicted)
            _ = try harness.writer.commitFieldDraft(fixture.base.ordinary(conflict))
            let old = fixture.work
            let collision = try FieldDraftCheckpointV1(draftID: UUID(), workspaceID: old.workspaceID,
                scope: old.scope, purpose: old.purpose, codec: old.codec,
                baseCanonicalRevision: 0, draftRevision: 1, payloadData: old.payloadData,
                stageIDs: [], resumeAnchor: old.resumeAnchor, state: .active,
                updatedAt: old.updatedAt, mutationID: prepared.command.mutationID)
            _ = try harness.writer.commitFieldDraft(fixture.base.ordinary(collision))
            XCTAssertThrowsError(try harness.writer.commit(prepared.command)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
            }
            try harness.store.validateAll()
            let before = try harness.writer.currentRevision()
            let counts = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
            XCTAssertThrowsError(try harness.writer.pendingReviewedMyDayCarryoverConflictEvidence(
                draftID: fixture.editing.draftID
            )) { XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined) }
            XCTAssertEqual(try harness.context.fetch(FetchDescriptor<MutationQuarantineRow>()).map(\.mutationID),
                           [prepared.command.mutationID.rawValue])
            XCTAssertEqual(try harness.writer.currentRevision(), before)
            XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), counts)
            XCTAssertFalse(harness.context.hasChanges)
        }
    }

    func testPendingCarryoverConflictReadRejectsGenuineImportedConflictWhileGenericHistoryRemainsValid() throws {
        let fixture = try CarryoverEvidenceBoundaryFixtureV1()
        let source = try CarryoverEvidenceJournalNodeV1(workspaceID: fixture.base.workspaceID, replicaID: .init(rawValue: UUID()))
        let target = try CarryoverEvidenceJournalNodeV1(workspaceID: fixture.base.workspaceID, replicaID: .init(rawValue: UUID()))
        defer { source.removeFiles(); target.removeFiles() }
        for node in [source, target] {
            node.context.insert(try ActorSnapshotRow(fixture.base.actor))
            try node.context.save()
            try fixture.seedSource(in: node.writer)
        }
        let preparation = try source.journal.prepareCheckpoint(supplement: .init(contentEntries: [], reversalEligibility: []))
        _ = try source.journal.activatePreparedCheckpoint(preparation)
        _ = try source.writer.commitFieldDraft(fixture.base.ordinary(fixture.editing))
        let conflict = try ReviewedResolutionHistoryFixtureV1.next(fixture.editing, state: .conflicted)
        _ = try source.writer.commitFieldDraft(fixture.base.ordinary(conflict))
        let cursor = try source.journal.initialCursor(consumerReplicaID: target.identity.replicaID)
        let batch = try source.journal.page(after: cursor)
        XCTAssertEqual(batch.changes.map(\.envelope.mutationID), [fixture.editing.mutationID, conflict.mutationID])
        for change in batch.changes { _ = try target.writer.executeImported(change) }
        XCTAssertEqual(try target.writer.sourceMutationHistorySnapshot().receipts.count, 4)
        let imported = try XCTUnwrap(target.writer.fieldDraftEvidence(mutationID: conflict.mutationID))
        XCTAssertEqual(imported.receipt.sourceKind, .importedHistory)
        let before = try target.writer.currentRevision()
        let counts = try PendingReviewedResolutionTestSupportV1.counts(target.context)
        XCTAssertThrowsError(try target.writer.pendingReviewedMyDayCarryoverConflictEvidence(
            draftID: fixture.editing.draftID
        )) { XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt) }
        XCTAssertEqual(try target.writer.fieldDraftEvidence(mutationID: conflict.mutationID), imported)
        XCTAssertEqual(try target.writer.currentRevision(), before)
        XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(target.context), counts)
        XCTAssertFalse(target.context.hasChanges)
    }
}

private extension CarryoverEvidenceBoundaryFixtureV1 {
    func successorPlan(_ plan: MyDayPlanV1, predecessor: MyDayPlanV1) throws -> MyDayPlanV1 {
        try MyDayPlanV1(planID: plan.planID, key: plan.key, items: plan.items, predecessor: predecessor,
            revision: plan.revision + 1, mutationID: .init(rawValue: UUID()), authoredBy: base.actor, authoredAt: base.now)
    }

    func targetPlan() throws -> MyDayPlanV1 {
        try MyDayPlanV1(planID: UUID(), key: base.key, items: [], revision: 1,
            mutationID: .init(rawValue: UUID()), authoredBy: base.actor, authoredAt: base.now)
    }

    func editing(targetPredecessor: MyDayPlanV1) throws -> FieldDraftCheckpointV1 {
        let context = try MyDayPlanningConfirmedContextV1(key: base.key, recordedBy: base.actor,
            keyWasExplicitlyConfirmed: true, recordedByWasExplicitlySelectedOrCaptured: true)
        let payload = try MyDayPlanningDraftPayloadV1(editing: context,
            intent: .carryover(sourcePlan: MyDayPlanReferenceV1(source),
                selectedMembershipIDs: source.items.map(\.membershipID), targetKey: base.key,
                targetPredecessor: MyDayPlanReferenceV1(targetPredecessor)))
        return try FieldDraftCheckpointV1(draftID: UUID(), workspaceID: base.workspaceID,
            scope: MyDayPlanningDraftCodecV1.scope(for: base.key), purpose: .myDayPlanning,
            codec: MyDayPlanningDraftCodecV1.release(), baseCanonicalRevision: targetPredecessor.revision,
            draftRevision: 1, payloadData: MyDayPlanningDraftCodecV1.encode(payload), stageIDs: [],
            resumeAnchor: .init(sectionID: "carryover-target"), state: .active,
            updatedAt: base.now, mutationID: .init(rawValue: UUID()))
    }
}

@MainActor
private final class CarryoverEvidenceJournalNodeV1 {
    let root: URL
    let identity: WorkspaceReplicaIdentityV1
    let session: StoreGenerationSession
    let coordinator: StoreSessionCoordinator
    let journal: LocalChangeJournalV1

    init(workspaceID: WorkspaceID, replicaID: ReplicaID) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V23-carryover-evidence-journal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        identity = try .init(workspaceID: workspaceID, replicaID: replicaID)
        session = try StoreGenerationFactory(applicationSupportURL: root,
            pointerEnrichmentIdentity: identity).openOrBootstrapCurrent()
        let profiles = try WorkspacePackageLifecycleCompatibilityV1.shippingRegistry()
        coordinator = try StoreSessionCoordinator(validatingSession: session, lifecycleProfileRegistry: profiles)
        let dependencies = try coordinator.packageLifecycleDependencies(profileRegistry: profiles)
        let backup = BackupExportService(modelContext: session.modelContext,
            generationRootURL: session.generationRootURL, lifecycleDependencies: dependencies,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in Int64.max }))
        let catalog = try CurrentSyncClassificationCatalogV1.current
        let draftPolicy = try catalog.registration(for: .init(category: .persistentModel,
            stableName: "FieldDraftCheckpointRow")).conflictPolicy
        let planPolicy = try catalog.registration(for: .init(category: .persistentModel,
            stableName: "MyDayPlanRowV1")).conflictPolicy
        journal = try coordinator.localChangeJournal(backupExport: backup,
            policyResolver: { identity, _ in
                switch identity.kind {
                case .fieldDraftCheckpoint: return draftPolicy
                case .myDayPlan: return planPolicy
                default: throw ChangeJournalFailureV1.tamperedBatch
                }
            },
            contentReferenceResolver: { _ in throw ContentContractFailureV1.missingContent },
            contentEntryResolver: { _ in throw ContentContractFailureV1.missingContent })
    }

    var context: ModelContext { coordinator.modelContext }
    var writer: WorkspaceWriterV1 { coordinator.workspaceWriter }
    func removeFiles() {
        try? coordinator.invalidateAndReleaseWriter()
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private struct CarryoverEvidenceBoundaryFixtureV1 {
    let base: ReviewedResolutionTestFixtureV1
    let work: FieldDraftCheckpointV1
    let source: MyDayPlanV1
    let editing: FieldDraftCheckpointV1

    init() throws {
        let base = try ReviewedResolutionTestFixtureV1(now: ReceiptSafetyClock().now())
        self.base = base
        let work = try FieldDraftCheckpointV1(draftID: UUID(), workspaceID: base.workspaceID,
            scope: .init(scopeKind: "V23_MY_DAY_COMMIT_SOURCE", stableComponentIDs: ["source"]),
            purpose: .assetFieldEdit,
            codec: .init(codecID: "v23.my-day.commit-source.v1", codecVersion: 1,
                         releaseSHA256: String(repeating: "a", count: 64)),
            baseCanonicalRevision: 0, draftRevision: 1, payloadData: Data("source-revision-1".utf8),
            stageIDs: [], resumeAnchor: .init(sectionID: "source"), state: .active,
            updatedAt: base.now, mutationID: .init(rawValue: UUID()))
        self.work = work
        let reference = MyDayEligibleReferenceV1.resumableDraft(workspaceID: base.workspaceID,
            draftID: work.draftID, revision: work.draftRevision,
            checkpointSHA256: work.checkpointSHA256, anchor: work.resumeAnchor)
        let sourceKey = try MyDayKeyV1(workspaceID: base.workspaceID, civilDate: .init("2026-09-09"),
                                      ianaTimeZoneIdentifier: "America/New_York")
        let source = try MyDayPlanV1(planID: UUID(), key: sourceKey,
            items: [.init(membershipID: UUID(), reference: reference, manualOrder: 0)],
            revision: 1, mutationID: .init(rawValue: UUID()), authoredBy: base.actor, authoredAt: base.now)
        self.source = source
        let context = try MyDayPlanningConfirmedContextV1(key: base.key, recordedBy: base.actor,
            keyWasExplicitlyConfirmed: true, recordedByWasExplicitlySelectedOrCaptured: true)
        let payload = try MyDayPlanningDraftPayloadV1(editing: context,
            intent: .carryover(sourcePlan: MyDayPlanReferenceV1(source),
                selectedMembershipIDs: source.items.map(\.membershipID), targetKey: base.key,
                targetPredecessor: nil))
        editing = try FieldDraftCheckpointV1(draftID: UUID(), workspaceID: base.workspaceID,
            scope: MyDayPlanningDraftCodecV1.scope(for: base.key), purpose: .myDayPlanning,
            codec: MyDayPlanningDraftCodecV1.release(), baseCanonicalRevision: 0, draftRevision: 1,
            payloadData: MyDayPlanningDraftCodecV1.encode(payload), stageIDs: [],
            resumeAnchor: .init(sectionID: "carryover"), state: .active,
            updatedAt: base.now, mutationID: .init(rawValue: UUID()))
    }

    func seedSource(in writer: WorkspaceWriterV1) throws {
        _ = try writer.commitFieldDraft(base.ordinary(work))
        _ = try writer.commit(MyDayCommandV1.save(successor: source, predecessor: nil))
    }

    func prepare(in writer: WorkspaceWriterV1, prefixCount: Int) throws
        -> (checkpoint: FieldDraftCheckpointV1, command: MyDayCommandV1) {
        guard (0...2).contains(prefixCount) else { throw FieldDraftFailureV1.invalidValue }
        _ = try writer.commitFieldDraft(base.ordinary(editing))
        let plan = try MyDayCarryoverPlanV1(sourcePlan: source, targetKey: base.key,
            membershipIDs: source.items.map(\.membershipID))
        let target = try MyDayPlanV1(planID: UUID(), key: base.key, items: source.items,
            revision: 1, mutationID: .init(rawValue: UUID()), authoredBy: base.actor, authoredAt: base.now)
        let receipt = try MyDayCarryoverReceiptV1(plan: plan, source: source, target: target,
            mutationID: target.mutationID, committedAt: base.now)
        let command = MyDayCommandV1.carryover(plan: plan, source: source, target: target, receipt: receipt)
        let attempt = try MyDayPlanningCommitAttemptInputsV1(command: command,
            fieldDraftPlanID: UUID(), preparedSagaID: UUID(), contentPromotedSagaID: UUID(),
            targetCommittedSagaID: UUID(), draftRetirePendingSagaID: UUID(), draftRetiredSagaID: UUID(),
            preparedSagaMutationID: .init(rawValue: UUID()), contentPromotedSagaMutationID: .init(rawValue: UUID()),
            targetCommittedSagaMutationID: .init(rawValue: UUID()), draftRetirePendingSagaMutationID: .init(rawValue: UUID()),
            terminalBundleMutationID: .init(rawValue: UUID()), commitReceiptID: UUID(),
            preparedSagaUpdatedAt: base.now, contentPromotedSagaUpdatedAt: base.now,
            targetCommittedSagaUpdatedAt: base.now, draftRetirePendingSagaUpdatedAt: base.now,
            draftRetiredSagaUpdatedAt: base.now, terminalCheckpointUpdatedAt: base.now)
        let prepared = try FieldDraftCheckpointV1(draftID: editing.draftID, workspaceID: base.workspaceID,
            scope: editing.scope, purpose: editing.purpose, codec: editing.codec,
            baseCanonicalRevision: 0, draftRevision: 2,
            payloadData: MyDayPlanningDraftCodecV1.encode(.init(prepared: attempt)), stageIDs: [],
            resumeAnchor: editing.resumeAnchor, state: .committing,
            updatedAt: base.now, mutationID: .init(rawValue: UUID()))
        _ = try writer.commitFieldDraft(base.ordinary(prepared))
        let reconstruction = try MyDayPlanningDraftCodecV1.reconstructCommit(from: prepared)
        if prefixCount >= 1 {
            _ = try writer.commitFieldDraft(.init(workspaceID: base.workspaceID, expectedRevision: 0,
                expectedBaseCanonicalRevision: 0, mutationID: reconstruction.prepared.mutationID,
                postImage: .appendCommitSaga(reconstruction.prepared)))
        }
        if prefixCount >= 2 {
            _ = try writer.commitFieldDraft(.init(workspaceID: base.workspaceID,
                expectedRevision: reconstruction.prepared.revision, expectedBaseCanonicalRevision: 0,
                mutationID: reconstruction.contentPromoted.mutationID,
                postImage: .advanceCommitSaga(reconstruction.contentPromoted)))
        }
        return (prepared, command)
    }
}


extension V23MutationReceiptSafetyTests {
    func testCarryoverReviewedResolutionAuthenticatesActiveAndPreparedOriginalsAcrossColdRead() throws {
        for prefix in -1...2 {
            let fixture = try CarryoverEvidenceBoundaryFixtureV1()
            let harness = try ReceiptSafetyHarness(workspaceID: fixture.base.workspaceID) {
                $0.insert(try ActorSnapshotRow(fixture.base.actor))
            }
            defer { harness.removeFiles() }
            let chain = try fixture.seedReviewedCarryover(in: harness.writer, prefixCount: prefix)
            let before = try harness.writer.currentRevision()
            let receipt = try harness.writer.commitFieldDraft(chain.mutation)
            let original = try XCTUnwrap(harness.writer.reviewedFieldDraftResolutionEvidence(
                mutationID: chain.mutation.mutationID))
            XCTAssertEqual(original.original.mutation, chain.mutation)
            XCTAssertEqual(original.original.receipt, receipt)
            XCTAssertEqual(original.resolution.expectedCheckpoint, chain.conflict)
            XCTAssertEqual(try harness.writer.currentRevision().revision, before.revision + 1)
            let payload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(original.resolution.successorCheckpoint)
            guard case let .carryover(source, selected, key, target)? = payload.editingIntent else {
                return XCTFail("Expected original carryover selection")
            }
            XCTAssertEqual(source, try MyDayPlanReferenceV1(fixture.source))
            XCTAssertEqual(selected, fixture.source.items.map(\.membershipID))
            XCTAssertEqual(key, fixture.base.key)
            XCTAssertEqual(target, try MyDayPlanReferenceV1(chain.target))
            let rows = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
            let revision = try harness.writer.currentRevision()
            XCTAssertEqual(try harness.writer.commitFieldDraft(chain.mutation), receipt)
            let cold = try harness.reopenFieldDraftAuthority()
            XCTAssertEqual(try cold.writer.reviewedFieldDraftResolutionEvidence(
                mutationID: chain.mutation.mutationID), original)
            XCTAssertEqual(try cold.adapter.currentCheckpoint(workspaceID: fixture.base.workspaceID,
                draftID: fixture.editing.draftID), original.resolution.successorCheckpoint)
            XCTAssertEqual(try cold.writer.currentPlan(for: fixture.source.key), fixture.source)
            XCTAssertEqual(try cold.writer.currentPlan(for: fixture.base.key), chain.target)
            XCTAssertNotEqual(try cold.writer.currentRevision().writerInstanceID, revision.writerInstanceID)
            XCTAssertEqual(try cold.writer.currentRevision().revision, revision.revision)
            XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), rows)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MyDayCarryoverReceiptRowV1>()), 0)
            XCTAssertFalse(harness.context.hasChanges)
        }
    }

    func testCarryoverReviewedResolutionRejectsChangedSourceOrSelectionBeforeAnyEffect() throws {
        for prefix in -1...2 {
            for changedSource in [false, true] {
                let fixture = try CarryoverEvidenceBoundaryFixtureV1()
                let harness = try ReceiptSafetyHarness(workspaceID: fixture.base.workspaceID) {
                    $0.insert(try ActorSnapshotRow(fixture.base.actor))
                }
                defer { harness.removeFiles() }
                let chain = try fixture.seedReviewedCarryover(in: harness.writer, prefixCount: prefix)
                let source = changedSource
                    ? try MyDayPlanReferenceV1(fixture.successorPlan(fixture.source, predecessor: fixture.source))
                    : try MyDayPlanReferenceV1(fixture.source)
                let selected = changedSource ? fixture.source.items.map(\.membershipID) : [UUID()]
                let invalid = try fixture.reviewedCarryoverMutation(conflict: chain.conflict,
                    target: chain.target, source: source, selected: selected)
                let before = try harness.writer.currentRevision()
                let rows = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
                XCTAssertThrowsError(try harness.writer.commitFieldDraft(invalid))
                XCTAssertNil(try harness.writer.fieldDraftEvidence(mutationID: invalid.mutationID))
                XCTAssertEqual(try harness.context.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).first {
                    $0.draftID == fixture.editing.draftID
                }?.value(), chain.conflict)
                XCTAssertEqual(try harness.writer.currentPlan(for: fixture.source.key), fixture.source)
                XCTAssertEqual(try harness.writer.currentPlan(for: fixture.base.key), chain.target)
                XCTAssertEqual(try harness.writer.currentRevision(), before)
                XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), rows)
                XCTAssertFalse(harness.context.hasChanges)
            }
        }
    }

    func testCarryoverReviewedResolutionReadDeniesMissingOrCorruptOriginalEvidenceWithoutEffects() throws {
        for denial in 0..<4 {
            let fixture = try CarryoverEvidenceBoundaryFixtureV1()
            let harness = try ReceiptSafetyHarness(workspaceID: fixture.base.workspaceID) {
                $0.insert(try ActorSnapshotRow(fixture.base.actor))
            }
            defer { harness.removeFiles() }
            let chain = try fixture.seedReviewedCarryover(in: harness.writer, prefixCount: 2)
            _ = try harness.writer.commitFieldDraft(chain.mutation)
            XCTAssertNotNil(try harness.writer.reviewedFieldDraftResolutionEvidence(mutationID: chain.mutation.mutationID))
            let affectedID = [fixture.editing.mutationID, fixture.source.mutationID,
                chain.conflict.mutationID, chain.mutation.mutationID][denial]
            let row = try XCTUnwrap(harness.context.fetch(FetchDescriptor<MutationReceiptRow>()).first {
                $0.mutationID == affectedID.rawValue
            })
            if denial == 0 { harness.context.delete(row) }
            else { row.envelopeSHA256 = String(repeating: "0", count: 64) }
            try harness.context.save()
            let revision = try XCTUnwrap(harness.context.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).first).workspaceRevision
            let rows = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
            let checkpoint = try XCTUnwrap(harness.context.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).first {
                $0.draftID == fixture.editing.draftID
            }).value()
            XCTAssertThrowsError(try harness.writer.reviewedFieldDraftResolutionEvidence(mutationID: chain.mutation.mutationID))
            XCTAssertEqual(try XCTUnwrap(harness.context.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).first).workspaceRevision, revision)
            XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), rows)
            XCTAssertEqual(try XCTUnwrap(harness.context.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).first {
                $0.draftID == fixture.editing.draftID
            }).value(), checkpoint)
            XCTAssertFalse(harness.context.hasChanges)
        }
    }
}

private extension CarryoverEvidenceBoundaryFixtureV1 {
    func seedReviewedCarryover(in writer: WorkspaceWriterV1, prefixCount: Int) throws
        -> (conflict: FieldDraftCheckpointV1, target: MyDayPlanV1, mutation: FieldDraftMutationV1) {
        try seedSource(in: writer)
        let previous: FieldDraftCheckpointV1
        if prefixCount < 0 {
            _ = try writer.commitFieldDraft(base.ordinary(editing))
            previous = editing
        } else { previous = try prepare(in: writer, prefixCount: prefixCount).checkpoint }
        let target = try targetPlan()
        _ = try writer.commit(MyDayCommandV1.save(successor: target, predecessor: nil))
        let conflict = try ReviewedResolutionHistoryFixtureV1.next(previous, state: .conflicted)
        _ = try writer.commitFieldDraft(base.ordinary(conflict))
        XCTAssertEqual(try writer.pendingReviewedMyDayCarryoverConflictEvidence(draftID: editing.draftID)
            .conflictedCheckpoint, conflict)
        return (conflict, target, try reviewedCarryoverMutation(conflict: conflict, target: target,
            source: MyDayPlanReferenceV1(source), selected: source.items.map(\.membershipID)))
    }

    func reviewedCarryoverMutation(conflict: FieldDraftCheckpointV1, target: MyDayPlanV1,
        source: MyDayPlanReferenceV1, selected: [UUID]) throws -> FieldDraftMutationV1 {
        let originalPayload = try MyDayPlanningDraftCodecV1.validateCheckpointPayload(editing)
        let context = try XCTUnwrap(originalPayload.confirmedContext)
        let payload = try MyDayPlanningDraftPayloadV1(editing: context,
            intent: .carryover(sourcePlan: source, selectedMembershipIDs: selected,
                targetKey: base.key, targetPredecessor: MyDayPlanReferenceV1(target)))
        let mutationID = try MutationIDV1(rawValue: UUID())
        let successor = try FieldDraftCheckpointV1(draftID: conflict.draftID, workspaceID: conflict.workspaceID,
            scope: conflict.scope, purpose: conflict.purpose, codec: conflict.codec,
            baseCanonicalRevision: target.revision, draftRevision: conflict.draftRevision + 1,
            payloadData: MyDayPlanningDraftCodecV1.encode(payload), stageIDs: [],
            resumeAnchor: conflict.resumeAnchor, state: .active, updatedAt: base.now, mutationID: mutationID)
        let basis = ReviewedMyDayTargetBasisV1.existing(identity: try .init(kind: .myDayPlan, id: target.planID),
            key: target.key, revision: target.revision, canonicalSHA256: target.planSHA256)
        let resolution = try ReviewedDraftConflictResolutionV1(plan: .reviewAndRebase,
            expectedCheckpoint: conflict, reviewedTargetBasis: basis, successorCheckpoint: successor)
        return try FieldDraftMutationV1(workspaceID: conflict.workspaceID,
            expectedRevision: conflict.draftRevision, expectedBaseCanonicalRevision: conflict.baseCanonicalRevision,
            mutationID: mutationID, postImage: .resolveConflict(resolution))
    }
}


extension V23MutationReceiptSafetyTests {
    func testResolvedCarryoverHistoryRejectsQuarantinedAbandonedTargetCommandWithoutEffects() throws {
        for prefix in 0...2 {
            let fixture = try CarryoverEvidenceBoundaryFixtureV1()
            let harness = try ReceiptSafetyHarness(workspaceID: fixture.base.workspaceID) {
                $0.insert(try ActorSnapshotRow(fixture.base.actor))
            }
            defer { harness.removeFiles() }
            let chain = try fixture.seedReviewedCarryover(in: harness.writer, prefixCount: prefix)
            _ = try harness.writer.commitFieldDraft(chain.mutation)
            let original = try XCTUnwrap(harness.writer.reviewedFieldDraftResolutionEvidence(mutationID: chain.mutation.mutationID))
            let command = try XCTUnwrap(MyDayPlanningDraftCodecV1.validateCheckpointPayload(chain.conflict).commitAttempt).command
            let work = fixture.work
            let collision = try FieldDraftCheckpointV1(draftID: UUID(), workspaceID: work.workspaceID,
                scope: work.scope, purpose: work.purpose, codec: work.codec,
                baseCanonicalRevision: 0, draftRevision: 1, payloadData: work.payloadData,
                stageIDs: [], resumeAnchor: work.resumeAnchor, state: .active,
                updatedAt: work.updatedAt, mutationID: command.mutationID)
            _ = try harness.writer.commitFieldDraft(fixture.base.ordinary(collision))
            XCTAssertThrowsError(try harness.writer.commit(command)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
            }
            try harness.store.validateAll()
            let before = try harness.writer.currentRevision()
            let rows = try PendingReviewedResolutionTestSupportV1.counts(harness.context)
            XCTAssertThrowsError(try harness.writer.reviewedFieldDraftResolutionEvidence(mutationID: chain.mutation.mutationID)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
            }
            XCTAssertEqual(try harness.writer.fieldDraftEvidence(mutationID: chain.mutation.mutationID), original.original)
            XCTAssertEqual(try harness.writer.currentRevision(), before)
            XCTAssertEqual(try PendingReviewedResolutionTestSupportV1.counts(harness.context), rows)
            XCTAssertEqual(try harness.writer.currentPlan(for: fixture.source.key), fixture.source)
            XCTAssertEqual(try harness.writer.currentPlan(for: fixture.base.key), chain.target)
            XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<MyDayCarryoverReceiptRowV1>()), 0)
            XCTAssertFalse(harness.context.hasChanges)
        }
    }
}

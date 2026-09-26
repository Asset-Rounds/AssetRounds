import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V9_75FastSurveyInboxTests: XCTestCase {
    func testFastSurveyExpectedRevisionEnrollsOnlyAbsentTargetsAndRetainsFullSnapshotCAS() throws {
        let f = try C11Fixture()
        let initial = try f.snippet(title: "Incumbent", body: "Retain its revision")
        let firstCommand = try f.command(.putSnippet(initial), mutationID: initial.mutationID)
        let initialTarget = try XCTUnwrap(firstCommand.affectedIdentitiesForCanonicalWriter().first)
        XCTAssertEqual(firstCommand.expectedRevision.entityRevisions,
                       [.init(identity: initialTarget, revision: 0)])
        _ = try f.lifecycle.replay(firstCommand)
        let current = try f.writer.currentRevision()
        let candidate = try f.snippet(title: "New target", body: "Explicit zero admission")
        let commandID = UUID()
        func expected(_ entities: [WorkspaceEntityRevisionV1]) throws -> WorkspaceExpectedRevisionV1 {
            try .init(workspaceID: current.workspaceID, generationID: current.generationID,
                writerInstanceID: current.writerInstanceID, workspaceRevision: current.revision,
                entityRevisions: entities)
        }
        func command(_ snapshot: WorkspaceExpectedRevisionV1) throws -> FastSurveyInboxMutationCommandV1 {
            try .init(commandID: commandID, workspaceID: f.workspaceID, expectedRevision: snapshot,
                mutationID: candidate.mutationID, payload: .putSnippet(candidate), submittedAt: f.date)
        }
        let implicit = try command(WorkspaceExpectedRevisionV1(snapshot: current))
        let target = try XCTUnwrap(implicit.affectedIdentitiesForCanonicalWriter().first)
        let explicit = try command(expected(current.entityRevisions + [.init(identity: target, revision: 0)]))
        XCTAssertEqual(implicit, explicit, "normalization precedes the immutable command digest")
        XCTAssertEqual(try JSONDecoder().decode(FastSurveyInboxMutationCommandV1.self,
                                               from: JSONEncoder().encode(implicit)), implicit)
        let unknown = try WorkspaceEntityIdentityV1(kind: .snippet, id: UUID())
        let invalidSnapshots = try [
            expected([]), // missing incumbent that is not the target
            expected(current.entityRevisions + [.init(identity: target, revision: 1)]),
            expected(current.entityRevisions + [.init(identity: unknown, revision: 0)]),
            expected([.init(identity: initialTarget, revision: 0)])
        ]
        let before = try f.journal.exportSnapshot()
        for invalid in invalidSnapshots {
            XCTAssertThrowsError(try f.writer.commitFastSurveyInbox(command(invalid))) {
                XCTAssertEqual($0 as? FastSurveyInboxFailureV1, .staleRevision)
            }
        }
        let after = try f.journal.exportSnapshot()
        XCTAssertEqual(after.receipts, before.receipts)
        XCTAssertEqual(after.entityRevisions, before.entityRevisions)
        XCTAssertEqual(after.quarantines, before.quarantines)
        let accepted = try f.lifecycle.replay(implicit)
        XCTAssertEqual(try f.lifecycle.replay(implicit), accepted)
        XCTAssertEqual(try f.context.fetch(FetchDescriptor<SnippetRowV1>()).count, 2)
        XCTAssertNoThrow(try f.journal.validateAll())
    }

    func testBackupEnrollmentPreservesOptionalBoundaryAndRejectsDecodedProvenanceTampering() throws {
        let fixture = try C11Fixture()
        let snippet = try fixture.snippet(title: "Backup provenance", body: "Exact persisted effect")
        _ = try fixture.commit(.putSnippet(snippet), mutationID: snippet.mutationID)
        let populated = try fixture.physicalBackupSnapshot()
        XCTAssertEqual(populated.snippets, [snippet])
        let empty = try FastSurveyInboxBackupSnapshotV1(inboxItems: [], promotions: [], snippets: [],
            snippetInsertions: [], receipts: [], effectProvenance: [])
        func records(_ version: Int, _ snapshot: FastSurveyInboxBackupSnapshotV1?) -> V4BackupRecordsV1 {
            V4BackupRecordsV1(assets: [], deletionLedger: .empty, evidenceFiles: [], issues: [],
                packets: [], partyAccountability: [], recordsSchemaVersion: version,
                reports: [], sites: [], workflowRecords: [], fastSurveyInbox: snapshot)
        }
        for version in [46, 47, 52] {
            XCTAssertNoThrow(try FastSurveyInboxBackupEnrollmentV1.validate(records(version, nil)))
        }
        for value in [empty, populated] {
            XCTAssertThrowsError(try FastSurveyInboxBackupEnrollmentV1.validate(records(46, value)))
            XCTAssertNoThrow(try FastSurveyInboxBackupEnrollmentV1.validate(records(47, value)))
            XCTAssertNoThrow(try FastSurveyInboxBackupEnrollmentV1.validate(records(52, value)))
        }
        let original = try JSONEncoder().encode(populated)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var provenance = try XCTUnwrap(object["effectProvenance"] as? [[String: Any]])
        provenance[0]["writerInstanceID"] = "00000000-0000-0000-0000-000000000000"
        object["effectProvenance"] = provenance
        let zeroWriter = try JSONDecoder().decode(FastSurveyInboxBackupSnapshotV1.self, from:
            JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        XCTAssertThrowsError(try zeroWriter.validate()) {
            XCTAssertEqual($0 as? FastSurveyInboxPersistenceFailureV1, .corruptRow)
        }
        object["effectProvenance"] = []
        let missing = try JSONDecoder().decode(FastSurveyInboxBackupSnapshotV1.self, from:
            JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        XCTAssertThrowsError(try missing.validate()) {
            XCTAssertEqual($0 as? FastSurveyInboxPersistenceFailureV1, .receiptMismatch)
        }
        XCTAssertEqual(try fixture.physicalBackupSnapshot(), populated)
    }

    func testV23P04C11G01RapidOfflineCaptureReviewAndTypedPromotionPreserveOriginalProvenance() async throws {
        let f = try C11Fixture()
        let context = try await f.item(label: "context", role: .context), detail = try await f.item(label: "detail", role: .detail), closeup = try await f.item(label: "closeup", role: .closeup)
        XCTAssertEqual([context.captureRole, detail.captureRole, closeup.captureRole], [.context, .detail, .closeup])
        XCTAssertNotNil(UUID(uuidString: context.content.contentID)); XCTAssertTrue(FileManager.default.fileExists(atPath: f.contentURL(context).path))
        for item in [context, detail, closeup] {
            _ = try f.commit(.putInboxItem(item), mutationID: item.mutationID)
            XCTAssertEqual(try f.journal.receipt(mutationID: item.mutationID)?.postImages.map(\.semanticSHA256), [item.itemSHA256])
        }
        let (promotion, promoted) = try f.promotion(source: context, kind: .assetEvidence)
        let promotionCommand = try f.command(.promote(promotion, promoted), mutationID: promotion.mutationID)
        let promotionTarget = try WorkspaceEntityIdentityV1(kind: .capturePromotion, id: promotion.promotionID)
        let inboxTarget = try WorkspaceEntityIdentityV1(kind: .captureInboxItem, id: context.inboxItemID)
        XCTAssertEqual(promotionCommand.expectedRevision.entityRevisions.first { $0.identity == promotionTarget }?.revision, 0)
        XCTAssertEqual(promotionCommand.expectedRevision.entityRevisions.first { $0.identity == inboxTarget }?.revision, 1)
        let receipt = try f.lifecycle.replay(promotionCommand)
        XCTAssertEqual(receipt.semanticSHA256s, [promotion.promotionSHA256, promoted.itemSHA256].sorted())
        XCTAssertEqual(promoted.content, context.content); XCTAssertEqual(promoted.originalProvenance, context.originalProvenance)
        XCTAssertEqual(promotion.destination.kind, .assetEvidence); XCTAssertEqual(promotion.destination.destinationRevision, 7)
        let destinations = try CapturePromotionDestinationKindV1.allCases.map { try f.destinationResolver.resolveCapturePromotionDestination(workspaceID: f.workspaceID, kind: $0, destinationID: f.destinationResolver.id(for: $0)) }
        XCTAssertEqual(destinations.map(\.kind), CapturePromotionDestinationKindV1.allCases)
        XCTAssertEqual(try f.journal.receipt(mutationID: promotion.mutationID)?.postImages.map(\.semanticSHA256).sorted(), receipt.semanticSHA256s)
        XCTAssertEqual(try f.context.fetch(FetchDescriptor<CaptureInboxItemRowV1>()).count, 4)
        XCTAssertEqual(try f.context.fetch(FetchDescriptor<CapturePromotionRowV1>()).count, 1)
        XCTAssertEqual(try f.context.fetch(FetchDescriptor<FastSurveyInboxMutationReceiptRowV1>()).count, 4)
        guard case let .promotion(projection) = try f.lifecycle.search(try .init(workspaceID: f.workspaceID, target: .promotion(promotion.promotionID))) else { return XCTFail("typed promotion projection expected") }
        XCTAssertEqual(projection.sourceItem.content, context.content); XCTAssertEqual(projection.promotedItem.originalProvenance, context.originalProvenance); XCTAssertEqual(projection.promotion.destination, promotion.destination)
        guard case let .inboxItems(unassigned) = try f.lifecycle.search(try .init(workspaceID: f.workspaceID, target: .unassignedItems)) else { return XCTFail("unassigned projection expected") }
        XCTAssertEqual(unassigned.count, 2)
        let selection = try FastSurveyInboxReviewSelectionV1(workspaceID: f.workspaceID, items: [detail, closeup], action: .reviewIndividually)
        try selection.validate(items: [detail, closeup]); XCTAssertEqual(selection.disposition, .requiresPerItemValidation)
        XCTAssertFalse(FastSurveyInboxReviewSelectionV1.permitsBulkPromotion); XCTAssertFalse(FastSurveyInboxReviewSelectionV1.permitsBulkDeletion)
        XCTAssertTrue(FastSurveyInboxLifecycleV1.canonicalPersistence); XCTAssertFalse(FastSurveyInboxLifecycleV1.createsSecondStore)
        let admitted = try f.captureAdmission(taps: 2, elapsed: 5_000, protectedData: .available); try admitted.requireAdmission()
        XCTAssertEqual(admitted.disposition, .admitted)
        XCTAssertThrowsError(try f.captureAdmission(taps: 3, elapsed: 5_000, protectedData: .available).requireAdmission())
        XCTAssertThrowsError(try f.captureAdmission(taps: 2, elapsed: 5_001, protectedData: .available).requireAdmission())
        XCTAssertThrowsError(try f.captureAdmission(taps: 2, elapsed: 5_000, protectedData: .unavailableLocked).requireAdmission())
    }

    func testV23P04C11A01UnassignedItemAndEditedSnippetRemainExplicitWithoutChangingFrozenRecords() async throws {
        let f = try C11Fixture(), item = try await f.item(label: "unassigned")
        _ = try f.commit(.putInboxItem(item), mutationID: item.mutationID)
        let first = try f.snippet(title: "Valve note", body: "Inspect valve body.")
        _ = try f.commit(.putSnippet(first), mutationID: first.mutationID)
        XCTAssertEqual(try f.journal.receipt(mutationID: first.mutationID)?.postImages.map(\.semanticSHA256), [first.snippetSHA256])
        let insertion = try f.insertion(snippet: first)
        let insertionReceipt = try f.commit(.insertSnippet(insertion, first), mutationID: insertion.mutationID)
        let edited = try f.snippet(title: "Valve note", body: "Inspect valve body and seal.", predecessor: first)
        _ = try f.commit(.putSnippet(edited), mutationID: edited.mutationID)
        XCTAssertEqual(try f.lifecycle.report().activeSnippetCount, 1, "an edit replaces the current snippet view")
        let retired = try f.snippet(title: edited.title, body: edited.body, state: .retired, predecessor: edited)
        _ = try f.commit(.putSnippet(retired), mutationID: retired.mutationID)
        XCTAssertEqual(try f.lifecycle.report().activeSnippetCount, 0, "retirement leaves no active current snippet")
        guard case let .insertionPreview(preview) = try f.coordinator.previewInsertion(snippet: edited, targetDraftID: UUID(), targetDraftRevision: 3) else { return XCTFail("explicit preview expected") }
        XCTAssertEqual(preview.snippetRevision, 2); XCTAssertEqual(preview.insertionText, edited.body)
        XCTAssertFalse(preview.automaticallyAnswers); XCTAssertFalse(preview.createsDirectObservation); XCTAssertTrue(preview.requiresExplicitBasisAndSave)
        XCTAssertEqual(insertionReceipt.semanticSHA256s, [insertion.insertionSHA256])
        XCTAssertEqual(try f.journal.receipt(mutationID: insertion.mutationID)?.postImages.map(\.semanticSHA256).sorted(), [insertion.insertionSHA256])
        let insertionRows = try f.context.fetch(FetchDescriptor<SnippetInsertionHistoryRowV1>())
        XCTAssertEqual(insertionRows.count, 1)
        let frozen = try XCTUnwrap(insertionRows.first?.value(snippet: first))
        XCTAssertEqual(frozen.insertedText, first.body); XCTAssertEqual(frozen.insertedTextSHA256, insertion.insertedTextSHA256)
        XCTAssertEqual(frozen.observationBasis, insertion.observationBasis); XCTAssertEqual(frozen.target, insertion.target)
        XCTAssertNotEqual(frozen.snippetSHA256, edited.snippetSHA256); XCTAssertEqual(try SnippetInsertionProjectionV1(insertion: frozen).laterSnippetChangesAffectInsertion, false)
        guard case let .snippetInsertion(saved) = try f.lifecycle.search(try .init(workspaceID: f.workspaceID, target: .snippetInsertion(insertion.insertionEventID))) else { return XCTFail("saved insertion expected") }
        XCTAssertEqual(saved.insertion, insertion)
        XCTAssertEqual(try f.context.fetch(FetchDescriptor<SnippetRowV1>()).count, 3)
        XCTAssertEqual(try f.context.fetch(FetchDescriptor<FastSurveyInboxMutationReceiptRowV1>()).count, 5)
        XCTAssertEqual(try f.context.fetch(FetchDescriptor<SnippetRowV1>()).map { try $0.value() }.sorted { $0.revision < $1.revision }, [first, edited, retired])
        guard case let .inboxItems(items) = try f.lifecycle.search(try .init(workspaceID: f.workspaceID, target: .unassignedItems)) else { return XCTFail("unassigned item expected") }
        XCTAssertEqual(items, [.unassigned(item)]); XCTAssertEqual(f.coordinator.cancel(), .cancelled)
        let retained = try FastSurveyInboxReviewSelectionV1(workspaceID: f.workspaceID, items: [item], action: .retainUnassigned)
        XCTAssertEqual(retained.disposition, .noMutation); XCTAssertFalse(FastSurveyInboxReviewSelectionV1.isPersistent)
        XCTAssertNoThrow(try f.journal.validateAll())
        let predecessor = try XCTUnwrap(try f.context.fetch(FetchDescriptor<SnippetRowV1>())
            .first { $0.snippetEventID == edited.snippetEventID })
        f.context.delete(predecessor)
        try f.context.save()
        XCTAssertThrowsError(try f.journal.checkpointV2ForTesting(),
                             "a terminal snippet cannot hide a missing intermediate revision")
        XCTAssertThrowsError(try f.journal.validateAll())
    }

    func testV23P04C11H01DuplicatePromotionStaleDestinationMissingContentAndSnippetSubstitutionFailClosed() async throws {
        let f = try C11Fixture(), source = try await f.item(label: "hostile")
        _ = try f.commit(.putInboxItem(source), mutationID: source.mutationID)
        let stale = try f.writer.currentRevision()
        let (promotion, promoted) = try f.promotion(source: source, kind: .findingEvidence)
        let exact = try f.command(.promote(promotion, promoted), mutationID: promotion.mutationID)
        XCTAssertEqual(try f.lifecycle.replay(exact), try f.lifecycle.replay(exact), "exact retry is idempotent")
        let (duplicate, duplicateItem) = try f.promotion(source: source, kind: .findingEvidence)
        XCTAssertThrowsError(try f.commit(.promote(duplicate, duplicateItem), mutationID: duplicate.mutationID))
        XCTAssertThrowsError(try CapturePromotionDestinationV1(workspaceID: f.workspaceID, kind: .findingEvidence, destinationID: UUID(), destinationRevision: 0, destinationSHA256: String(repeating: "d", count: 64)))
        let current = try f.destinationResolver.resolveCapturePromotionDestination(workspaceID: f.workspaceID, kind: .findingEvidence, destinationID: f.destinationResolver.id(for: .findingEvidence))
        let staleDestination = try CapturePromotionDestinationV1(workspaceID: f.workspaceID, kind: current.kind, destinationID: current.destinationID, destinationRevision: current.destinationRevision + 1, destinationSHA256: current.destinationSHA256)
        XCTAssertThrowsError(try staleDestination.validate(resolver: f.destinationResolver))
        let changedSHA = try CapturePromotionDestinationV1(workspaceID: f.workspaceID, kind: current.kind, destinationID: current.destinationID, destinationRevision: current.destinationRevision, destinationSHA256: String(repeating: "f", count: 64))
        XCTAssertThrowsError(try changedSHA.validate(resolver: f.destinationResolver))
        XCTAssertThrowsError(try f.destinationResolver.resolveCapturePromotionDestination(workspaceID: f.workspaceID, kind: .assetEvidence, destinationID: UUID()))
        XCTAssertThrowsError(try f.destinationResolver.resolveCapturePromotionDestination(workspaceID: f.workspaceID, kind: .assetEvidence, destinationID: f.destinationResolver.id(for: .findingEvidence)))
        XCTAssertThrowsError(try f.destinationResolver.resolveCapturePromotionDestination(workspaceID: WorkspaceID(), kind: .findingEvidence, destinationID: current.destinationID))
        let noAuthority = try C11Fixture(hasDestinationAuthority: false), noAuthorityItem = try await noAuthority.item(label: "no-authority")
        _ = try noAuthority.commit(.putInboxItem(noAuthorityItem), mutationID: noAuthorityItem.mutationID)
        let (unownedPromotion, unownedPromoted) = try noAuthority.promotion(source: noAuthorityItem, kind: .assetEvidence)
        XCTAssertThrowsError(try noAuthority.commit(.promote(unownedPromotion, unownedPromoted), mutationID: unownedPromotion.mutationID))
        let extra = try await f.item(label: "revision-advance"); _ = try f.commit(.putInboxItem(extra), mutationID: extra.mutationID)
        let staleItem = try await f.item(label: "stale")
        XCTAssertThrowsError(try f.writer.commitFastSurveyInbox(try .init(commandID: UUID(), workspaceID: f.workspaceID, expectedRevision: WorkspaceExpectedRevisionV1(snapshot: stale), mutationID: staleItem.mutationID, payload: .putInboxItem(staleItem), admission: .capture(try f.captureAdmission()), submittedAt: f.date)))
        do { _ = try await f.item(label: "missing", bytes: Data()); XCTFail("empty content must fail") } catch {}
        XCTAssertThrowsError(try f.lifecycle.search(try .init(workspaceID: WorkspaceID(), target: .unassignedItems)))
        XCTAssertThrowsError(try FastSurveyInboxStoragePressureV1(workspaceID: f.workspaceID, currentBytes: Int64.max, proposedAdditionalBytes: 1))
        let snippet = try f.snippet(title: "Pinned", body: "Original text"), edited = try f.snippet(title: "Pinned", body: "Substituted text", predecessor: snippet)
        let preview = try SnippetInsertionPreviewV1(snippet: snippet, targetDraftID: UUID(), targetDraftRevision: 1)
        XCTAssertEqual(preview.insertionText, "Original text"); XCTAssertNotEqual(preview.snippetSHA256, edited.snippetSHA256)
        XCTAssertEqual(try f.context.fetch(FetchDescriptor<CapturePromotionRowV1>()).count, 1)
    }

    func testV23P04C11I01InterruptedCaptureOrPromotionPreservesBytesAndRecoverableInbox() async throws {
        for boundary in MutationJournalFaultBoundaryV1.allCases {
            let f = try C11Fixture(failOnceAt: boundary), item = try await f.item(label: "capture-\(boundary.rawValue)")
            let command = try f.command(.putInboxItem(item), mutationID: item.mutationID)
            XCTAssertThrowsError(try f.lifecycle.replay(command)) { error in
                XCTAssertEqual(error as? MutationJournalFailureV1, .injected(boundary),
                    "C11.capture.\(boundary.rawValue): \(String(reflecting: type(of: error))) \(error)")
            }
            XCTAssertEqual(try Data(contentsOf: f.contentURL(item)), Data([1, 2, 3, 4]))
            let savedBeforeRecovery = boundary == .afterSaveBeforeReturn
            XCTAssertEqual(try f.context.fetch(FetchDescriptor<CaptureInboxItemRowV1>()).count, savedBeforeRecovery ? 1 : 0)
            XCTAssertEqual(try f.context.fetch(FetchDescriptor<FastSurveyInboxMutationReceiptRowV1>()).count, savedBeforeRecovery ? 1 : 0)
            XCTAssertEqual(try f.journal.receipt(mutationID: item.mutationID) != nil, savedBeforeRecovery)
            try MutationReceiptRecoveryServiceV1(store: f.journal).recoverBeforeWriterActivation()
            XCTAssertEqual(try f.lifecycle.replay(command).recoveryState, .receiptCommitted)
            try assertReceiptParity(command: command, journal: f.journal, context: f.context)
            XCTAssertEqual(try f.context.fetch(FetchDescriptor<CaptureInboxItemRowV1>()).count, 1)
            guard case let .inboxItem(.unassigned(visible)) = try f.lifecycle.search(try .init(workspaceID: f.workspaceID, target: .inboxItem(item.inboxItemID))) else { return XCTFail("recovered capture must remain visible") }
            XCTAssertEqual(visible, item); XCTAssertEqual(try Data(contentsOf: f.contentURL(item)), Data([1, 2, 3, 4]))
        }

        for boundary in MutationJournalFaultBoundaryV1.allCases {
            let f = try C11Fixture(), source = try await f.item(label: "promotion-\(boundary.rawValue)")
            _ = try f.commit(.putInboxItem(source), mutationID: source.mutationID)
            let runtime = try f.runtime(failOnceAt: boundary)
            let (promotion, promoted) = try f.promotion(source: source, kind: .correctiveWorkEvidence)
            let command = try f.command(.promote(promotion, promoted), mutationID: promotion.mutationID, using: runtime.writer)
            XCTAssertThrowsError(try runtime.lifecycle.replay(command)) { error in
                XCTAssertEqual(error as? MutationJournalFailureV1, .injected(boundary),
                    "C11.promotion.\(boundary.rawValue): \(String(reflecting: type(of: error))) \(error)")
            }
            XCTAssertEqual(try Data(contentsOf: f.contentURL(source)), Data([1, 2, 3, 4]))
            let savedBeforeRecovery = boundary == .afterSaveBeforeReturn
            XCTAssertEqual(try f.context.fetch(FetchDescriptor<CapturePromotionRowV1>()).count, savedBeforeRecovery ? 1 : 0)
            XCTAssertEqual(try f.context.fetch(FetchDescriptor<CaptureInboxItemRowV1>()).count, savedBeforeRecovery ? 2 : 1)
            guard case let .inboxItem(before) = try f.lifecycle.search(try .init(workspaceID: f.workspaceID, target: .inboxItem(source.inboxItemID))) else { return XCTFail("source must never be hidden") }
            if savedBeforeRecovery { guard case .promoted = before else { return XCTFail("saved journal truth must be visible") } }
            else { XCTAssertEqual(before, .unassigned(source)) }
            try MutationReceiptRecoveryServiceV1(store: runtime.journal).recoverBeforeWriterActivation()
            XCTAssertEqual(try runtime.lifecycle.replay(command).recoveryState, .receiptCommitted)
            try assertReceiptParity(command: command, journal: runtime.journal, context: f.context)
            XCTAssertEqual(try f.context.fetch(FetchDescriptor<CapturePromotionRowV1>()).count, 1)
            XCTAssertEqual(try f.context.fetch(FetchDescriptor<CaptureInboxItemRowV1>()).count, 2)
            guard case let .promotion(recovered) = try f.lifecycle.search(try .init(workspaceID: f.workspaceID, target: .promotion(promotion.promotionID))) else { return XCTFail("promotion must recover exactly once") }
            XCTAssertEqual(recovered.sourceItem, source); XCTAssertEqual(recovered.promotedItem, promoted); XCTAssertEqual(recovered.promotion, promotion)
            XCTAssertEqual(try Data(contentsOf: f.contentURL(source)), Data([1, 2, 3, 4]))
        }

        let missingTyped = try C11Fixture(), missingItem = try await missingTyped.item(label: "missing-typed-receipt")
        _ = try missingTyped.commit(.putInboxItem(missingItem), mutationID: missingItem.mutationID)
        let missingRow = try XCTUnwrap(try missingTyped.context.fetch(FetchDescriptor<FastSurveyInboxMutationReceiptRowV1>()).first)
        missingTyped.context.delete(missingRow); try missingTyped.context.save()
        XCTAssertThrowsError(try MutationReceiptRecoveryServiceV1(store: missingTyped.journal).recoverBeforeWriterActivation())
    }

    private func assertReceiptParity(command: FastSurveyInboxMutationCommandV1,
        journal: MutationJournalStoreV1, context: ModelContext) throws {
        let pairs = try journal.fastSurveyInboxRecoveryPairs().filter { $0.command.mutationID == command.mutationID }
        XCTAssertEqual(pairs.count, 1); XCTAssertEqual(pairs.first?.command, command)
        let typed = try context.fetch(FetchDescriptor<FastSurveyInboxMutationReceiptRowV1>()).map { try $0.value() }
            .filter { $0.mutationID == command.mutationID }
        XCTAssertEqual(typed.count, 1); XCTAssertEqual(pairs.first?.receipt, typed.first)
        let generic = try XCTUnwrap(try journal.receipt(mutationID: command.mutationID))
        XCTAssertEqual(typed.first?.semanticSHA256s, generic.postImages.map(\.semanticSHA256).sorted())
    }

    func testV23P04C11R01RestoreReplayRebuildsInboxPromotionLinksSnippetVersionsAndUnresolvedItemsWithoutDoubleInsertion() async throws {
        let f = try C11Fixture(), source = try await f.item(label: "restore"), unresolved = try await f.item(label: "unresolved")
        _ = try f.commit(.putInboxItem(source), mutationID: source.mutationID); _ = try f.commit(.putInboxItem(unresolved), mutationID: unresolved.mutationID)
        let (promotion, promoted) = try f.promotion(source: source, kind: .responseEvidence); _ = try f.commit(.promote(promotion, promoted), mutationID: promotion.mutationID)
        let snippet = try f.snippet(title: "Restore", body: "Preserved snippet"); _ = try f.commit(.putSnippet(snippet), mutationID: snippet.mutationID)
        let insertion = try f.insertion(snippet: snippet); _ = try f.commit(.insertSnippet(insertion, snippet), mutationID: insertion.mutationID)
        let snapshot = try f.lifecycle.snapshot(), bytes = try f.lifecycle.backup()
        XCTAssertEqual(try f.lifecycle.exportCanonical(), bytes); XCTAssertEqual(try f.lifecycle.decodeBackup(bytes), snapshot)
        XCTAssertEqual(try f.lifecycle.migrate(bytes, from: FastSurveyInboxSchemaV1.schemaVersion), bytes)
        let writerID = UUID(), effects = snapshot.inboxItems.map { ($0.mutationID, $0.itemSHA256) } + snapshot.promotions.map { ($0.mutationID, $0.promotionSHA256) } + snapshot.snippets.map { ($0.mutationID, $0.snippetSHA256) } + snapshot.snippetInsertions.map { ($0.mutationID, $0.insertionSHA256) }
        let backup = try FastSurveyInboxBackupSnapshotV1(inboxItems: snapshot.inboxItems, promotions: snapshot.promotions, snippets: snapshot.snippets, snippetInsertions: snapshot.snippetInsertions, receipts: snapshot.receipts, effectProvenance: effects.map { try FastSurveyInboxBackupEffectProvenanceV1(mutationID: $0.0.rawValue, semanticSHA256: $0.1, writerInstanceID: writerID) })
        try f.removeTypedRows(); try f.lifecycle.replaceRestore(backup)
        XCTAssertEqual(try f.lifecycle.snapshot(), snapshot)
        XCTAssertEqual(try f.context.fetch(FetchDescriptor<CaptureInboxItemRowV1>()).count, 3); XCTAssertEqual(try f.context.fetch(FetchDescriptor<CapturePromotionRowV1>()).count, 1); XCTAssertEqual(try f.context.fetch(FetchDescriptor<SnippetRowV1>()).count, 1); XCTAssertEqual(try f.context.fetch(FetchDescriptor<SnippetInsertionHistoryRowV1>()).count, 1); XCTAssertEqual(try f.context.fetch(FetchDescriptor<FastSurveyInboxMutationReceiptRowV1>()).count, 5)
        guard case let .inboxItems(items) = try f.lifecycle.search(try .init(workspaceID: f.workspaceID, target: .unassignedItems)) else { return XCTFail("rebuilt unresolved inbox expected") }
        XCTAssertEqual(items, [.unassigned(unresolved)])
        guard case let .snippetInsertions(insertions) = try f.lifecycle.search(try .init(workspaceID: f.workspaceID, target: .snippetInsertions(insertion.target))) else { return XCTFail("rebuilt insertion history expected") }
        XCTAssertEqual(insertions.map(\.insertion), [insertion])
        let report = try f.lifecycle.report(); XCTAssertEqual(report.completedInspectionContribution, 0); XCTAssertEqual(report.unassignedInboxCount, 1); XCTAssertEqual(report.promotionCount, 1)
        XCTAssertTrue(FastSurveyInboxSchemaMigrationBoundaryV1.validate()); XCTAssertEqual(FastSurveyInboxSchemaV1.modelTypes.count, 5); XCTAssertEqual(FastSurveyInboxSchemaV1.totalSchemaModelCount, 158)
        try f.lifecycle.delete(); try FastSurveyInboxKernelDeletionEraseEnrollmentV1.validate()
        XCTAssertEqual(try f.lifecycle.snapshot(), snapshot, "ordinary deletion policy retains immutable inbox history")
        XCTAssertEqual(try f.lifecycle.report(), report)
        XCTAssertEqual(report.promotedInboxCount, 1)
        XCTAssertEqual(report.activeSnippetCount, 1)
        XCTAssertNoThrow(try f.journal.validateAll())
        let empty = try C11Fixture(); try FastSurveyInboxEraseAllPolicyV1.validatePublishedEmptyGeneration(empty.context)
        let replaySnippet = try empty.snippet(title: "Replay", body: "Once")
        let replay = try empty.command(.putSnippet(replaySnippet), mutationID: replaySnippet.mutationID)
        XCTAssertEqual(try empty.lifecycle.replay(replay), try empty.lifecycle.replay(replay))
        try f.removeTypedRows()
        let freshContext = ModelContext(f.context.container)
        let retainedCounts = [try f.context.fetchCount(FetchDescriptor<CaptureInboxItemRowV1>()),
            try f.context.fetchCount(FetchDescriptor<FastSurveyInboxMutationReceiptRowV1>())]
        let freshCounts = [try freshContext.fetchCount(FetchDescriptor<CaptureInboxItemRowV1>()),
            try freshContext.fetchCount(FetchDescriptor<FastSurveyInboxMutationReceiptRowV1>())]
        print("C11.rawDeletion retained=\(retainedCounts) fresh=\(freshCounts)")
        XCTAssertEqual(freshCounts, [0, 0], "the hostile operation must actually remove persisted typed rows")
        XCTAssertThrowsError(try MutationJournalStoreV1(modelContext: freshContext,
            identity: f.identity, generationID: f.generationID).validateAll(),
            "actual out-of-writer row deletion invalidates retained receipts on a fresh read")
    }
}

private struct C11Clock: ApplicationClock { func now() -> Date { Date(timeIntervalSince1970: 1_700_100_000) } }
private struct C11IDs: ApplicationIDSource { func makeID() -> UUID { UUID() } }
private struct C11Files: ApplicationFileAuthorityV1 { func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String { "mutation-staging/\(mutationID.rawValue.uuidString.lowercased())/\(component)" } }

@MainActor
final class C11Fixture {
    let workspaceID: WorkspaceID
    let date = Date(timeIntervalSince1970: 1_700_100_000)
    let identity: WorkspaceReplicaIdentityV1, generationID: UUID
    let context: ModelContext, journal: MutationJournalStoreV1, writer: WorkspaceWriterV1
    let lifecycle: FastSurveyInboxLifecycleAdapterV1, coordinator: FastSurveyInboxCoordinatorV1
    let generationRoot: URL, evidenceStore: EvidenceBundleStore
    let destinationResolver: C11StrictDestinationResolver
    private let currentBinding: C10C11CurrentWriterBinding?
    private let retainedContainer: ModelContainer?

    init(failOnceAt boundary: MutationJournalFaultBoundaryV1? = nil, hasDestinationAuthority: Bool = true,
         session: StoreGenerationSession? = nil, applicationSupportURL: URL? = nil,
         destinationAssetID: UUID? = nil) throws {
        let modelContext: ModelContext, generation: UUID, replicaIdentity: WorkspaceReplicaIdentityV1
        let root: URL, store: MutationJournalStoreV1, canonicalWriter: WorkspaceWriterV1
        if let session {
            retainedContainer = nil
            guard boundary == nil, hasDestinationAuthority else { throw FastSurveyInboxFailureV1.invalidValue }
            workspaceID = session.workspaceID; modelContext = session.modelContext
            generation = session.generationID; replicaIdentity = session.workspaceIdentity
            root = session.generationRootURL
            let binding = try C10C11CurrentWriterBinding(session: session,
                applicationSupportURL: XCTUnwrap(applicationSupportURL),
                destinationAssetID: XCTUnwrap(destinationAssetID))
            currentBinding = binding; store = binding.journal; canonicalWriter = binding.writer
        } else {
            currentBinding = nil; workspaceID = WorkspaceID()
            let schema = try PersistentSchemaReleaseRegistryV1.activeSchema()
            let container = try ModelContainer(for: schema, migrationPlan: nil, configurations: [ModelConfiguration("C11Production", schema: schema, isStoredInMemoryOnly: true, allowsSave: true, cloudKitDatabase: .none)])
            retainedContainer = container
            modelContext = container.mainContext
            generation = UUID()
            replicaIdentity = try WorkspaceReplicaIdentityV1(workspaceID: workspaceID, replicaID: ReplicaID(rawValue: UUID()))
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("c11-production-\(UUID().uuidString.lowercased())", isDirectory: true)
                .appendingPathComponent("FieldEvidenceData/generations/\(generation.uuidString.lowercased())", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let resolver = try C11StrictDestinationResolver(workspaceID: workspaceID)
            store = try MutationJournalStoreV1(modelContext: modelContext, identity: replicaIdentity, generationID: generation, failureInjection: boundary.map { MutationJournalFailureInjectionV1(failOnceAt: $0) })
            canonicalWriter = try WorkspaceWriterV1(identity: replicaIdentity, generationID: generation, initialRevision: store.currentRevision(writerInstanceID: UUID()), clock: C11Clock(), idSource: C11IDs(), fileAuthority: C11Files(), adapter: WorkspaceWriterAdapterV1(modelContext: modelContext, capturePromotionDestinationResolver: hasDestinationAuthority ? resolver : nil), journalStore: store)
        }
        modelContext.autosaveEnabled = false
        generationRoot = root; evidenceStore = EvidenceBundleStore(generationRootURL: root)
        let resolver = try C11StrictDestinationResolver(workspaceID: workspaceID)
        let adapter = FastSurveyInboxLifecycleAdapterV1(workspaceWriter: canonicalWriter, modelContext: modelContext, workspaceID: workspaceID)
        identity = replicaIdentity; generationID = generation
        context = modelContext; journal = store; writer = canonicalWriter; lifecycle = adapter; destinationResolver = resolver
        coordinator = FastSurveyInboxCoordinatorV1(workspaceWriter: canonicalWriter, query: { [adapter] in try adapter.search($0) })
    }

    func mutation() throws -> MutationIDV1 { try .init(rawValue: UUID()) }
    func closeCurrentWriter() throws { try currentBinding?.close() }

    func currentDestination() throws -> CapturePromotionDestinationV1 {
        let resolver = try XCTUnwrap(currentBinding?.destinationResolver)
        let reloaded = try C11PersistedAssetDestinationResolver(modelContext: context,
            workspaceID: workspaceID, journal: journal, assetID: resolver.destination.destinationID)
        guard reloaded.destination == resolver.destination else { throw FastSurveyInboxFailureV1.staleRevision }
        return resolver.destination
    }
    func expected(using authority: WorkspaceWriterV1? = nil) throws -> WorkspaceExpectedRevisionV1 { WorkspaceExpectedRevisionV1(snapshot: try (authority ?? writer).currentRevision()) }
    func command(_ payload: FastSurveyInboxMutationPayloadV1, mutationID: MutationIDV1, using authority: WorkspaceWriterV1? = nil) throws -> FastSurveyInboxMutationCommandV1 {
        let admission: FastSurveyInboxMutationAdmissionV1
        if case let .putInboxItem(item) = payload {
            if currentBinding != nil {
                var retained: [String: Int64] = [:]
                for existing in try lifecycle.snapshot().inboxItems {
                    if let prior = retained[existing.content.contentID], prior != existing.content.byteLength {
                        throw FastSurveyInboxFailureV1.invalidValue
                    }
                    retained[existing.content.contentID] = existing.content.byteLength
                }
                let currentBytes = try retained.values.reduce(Int64.zero) { total, bytes in
                    let (next, overflow) = total.addingReportingOverflow(bytes)
                    guard !overflow else { throw FastSurveyInboxFailureV1.arithmeticOverflow }
                    return next
                }
                // References retain existing immutable media; count each
                // unique content once in the inbox's actual byte budget.
                let additional = retained[item.content.contentID] == nil ? item.content.byteLength : 0
                admission = .capture(try .init(workspaceID: workspaceID,
                    budget: .init(tapCount: 2, elapsedMilliseconds: 5_000), protectedDataState: .available,
                    storagePressure: .init(workspaceID: workspaceID, currentBytes: currentBytes,
                        proposedAdditionalBytes: additional)))
            } else { admission = .capture(try captureAdmission()) }
        } else { admission = .notApplicable }
        return try .init(commandID: UUID(), workspaceID: workspaceID, expectedRevision: try expected(using: authority), mutationID: mutationID, payload: payload, admission: admission, submittedAt: date)
    }
    private func diagnosing<T>(_ step: String, _ operation: () throws -> T) throws -> T {
        do { return try operation() }
        catch {
            print("C11.\(step): \(String(reflecting: type(of: error))) \(String(reflecting: error))")
            throw error
        }
    }
    func commit(_ payload: FastSurveyInboxMutationPayloadV1, mutationID: MutationIDV1) throws -> FastSurveyInboxMutationReceiptV1 {
        let prepared = try diagnosing("command.prepare") { try command(payload, mutationID: mutationID) }
        return try diagnosing("command.commit") { try lifecycle.replay(prepared) }
    }
    func captureAdmission(taps: Int = 2, elapsed: UInt64 = 5_000, protectedData: FastSurveyInboxProtectedDataStateV1 = .available) throws -> FastSurveyInboxCaptureAdmissionV1 {
        try .init(workspaceID: workspaceID, budget: .init(tapCount: taps, elapsedMilliseconds: elapsed), protectedDataState: protectedData, storagePressure: .init(workspaceID: workspaceID, currentBytes: 0, proposedAdditionalBytes: 4))
    }

    func runtime(failOnceAt boundary: MutationJournalFaultBoundaryV1) throws
        -> (journal: MutationJournalStoreV1, writer: WorkspaceWriterV1, lifecycle: FastSurveyInboxLifecycleAdapterV1) {
        let store = try MutationJournalStoreV1(modelContext: context, identity: identity, generationID: generationID,
            failureInjection: MutationJournalFailureInjectionV1(failOnceAt: boundary))
        let authority = try WorkspaceWriterV1(identity: identity, generationID: generationID,
            initialRevision: store.currentRevision(writerInstanceID: UUID()), clock: C11Clock(), idSource: C11IDs(),
            fileAuthority: C11Files(), adapter: WorkspaceWriterAdapterV1(modelContext: context,
                capturePromotionDestinationResolver: destinationResolver), journalStore: store)
        return (store, authority, FastSurveyInboxLifecycleAdapterV1(workspaceWriter: authority,
            modelContext: context, workspaceID: workspaceID))
    }

    func item(label: String, role: CaptureInboxRoleV1 = .context, bytes data: Data = Data([1, 2, 3, 4])) async throws -> CaptureInboxItemV1 {
        guard !data.isEmpty else { throw FastSurveyInboxFailureV1.missingContent }
        let contentUUID = UUID(), contentID = contentUUID.uuidString.lowercased(), digest = try ContentDigestV1(algorithm: .sha256, hexadecimalValue: KernelCanonicalHashV1.sha256(data))
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let createdAt = formatter.string(from: date)
        let reference = try ContentReferenceV1(workspaceID: workspaceID.rawValue.uuidString.lowercased(), contentID: contentID, byteLength: Int64(data.count), mediaType: "image/jpeg", digests: ContentDigestSetV1([digest]), byteRole: .immutableOriginal, createdAt: createdAt)
        let provenance = try ContentOriginalProvenanceV1(provenanceID: "provenance-\(contentID)", workspaceID: reference.workspaceID, contentID: contentID, contentDigest: digest, origin: .humanCapture, recordedAt: reference.createdAt)
        let request = try DraftImmutableContentWriteRequestV1(workspaceID: workspaceID, contentID: contentID, digest: digest, byteLength: Int64(data.count), mediaType: reference.mediaType, mutationID: try mutation(), createdAt: reference.createdAt)
        let receipt = try await evidenceStore.persistImmutableOriginal(bytes: data, request: request)
        try receipt.validate(request: request, bytes: data)
        try seedOriginalEvidence(contentID: contentUUID, role: role, relativePath: receipt.relativePath,
            mediaType: receipt.mediaType, byteLength: Int(receipt.byteLength), sha256: receipt.digest.hexadecimalValue)
        return try .init(inboxEventID: UUID(), inboxItemID: UUID(), workspaceID: workspaceID, mediaKind: .photo, content: reference, captureRole: role, originalProvenance: provenance, observationBasis: try observation(), temporalContext: try temporal(), capturedBy: try actor(), revision: 1, mutationID: try mutation())
    }

    /// Prerequisites use the same journal protocol, without consuming the
    /// capture operation's fault injection. No model is inserted behind the
    /// mutable-content checkpoint after writer activation.
    private func seedOriginalEvidence(contentID: UUID, role: CaptureInboxRoleV1,
        relativePath: String, mediaType: String, byteLength: Int, sha256: String) throws {
        guard currentBinding == nil else { throw FastSurveyInboxFailureV1.invalidValue }
        let seedJournal = try MutationJournalStoreV1(modelContext: context, identity: identity,
            generationID: generationID)
        let seedWriter = try WorkspaceWriterV1(identity: identity, generationID: generationID,
            initialRevision: seedJournal.currentRevision(writerInstanceID: UUID()),
            clock: C11Clock(), idSource: C11IDs(), fileAuthority: C11Files(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context), journalStore: seedJournal)
        let siteID = UUID(), assetID = UUID(), recordID = UUID(), placementMutationID = try mutation()
        _ = try diagnosing("seed.first-sign") { try seedWriter.execute(.createFirstSign(.init(siteID: siteID,
            newSite: .init(id: siteID, label: "Capture source", address: nil, timeZoneID: nil),
            assetID: assetID, assetLabel: "Capture source", packID: "c11.fixture",
            packSchemaVersion: 1, packContentVersion: 1, createdAt: date,
            initialPlacementMutationID: placementMutationID, initialPlacementEventID: UUID(),
            initialPhysicalEpisodeID: try .init(rawValue: UUID()))), mutationID: placementMutationID) }
        _ = try diagnosing("seed.check-draft") { try seedWriter.execute(.createCheckDraft(.init(recordID: recordID, assetID: assetID,
            issueID: nil, parentRecordID: nil, stage: WorkflowStage.check.rawValue,
            draftStepKey: WorkflowDraftStep.wide.rawValue, startedAt: date, observedAtUTC: date,
            timeZoneID: nil, utcOffsetMinutes: nil, localDate: nil, localTime: nil,
            afterDarkAcknowledgementKey: nil, afterDarkAcknowledgementCopy: nil,
            afterDarkAcknowledgementVersion: nil, afterDarkAcknowledgementAccepted: nil,
            safePositionAcknowledgementKey: nil, safePositionAcknowledgementCopy: nil,
            safePositionAcknowledgementVersion: nil, safePositionAcknowledgementAccepted: nil,
            packID: "c11.fixture", packSchemaVersion: 1, packContentVersion: 1,
            pdfTemplateID: "c11.fixture", pdfTemplateVersion: 1,
            observationBasis: try observation(), temporalContext: try temporal())), mutationID: mutation()) }
        _ = try diagnosing("seed.evidence") { try seedWriter.execute(.acceptCheckEvidence(.init(evidenceID: contentID,
            draftID: recordID, purposeKey: role.rawValue.lowercased(), relativePath: relativePath,
            mimeType: mediaType, byteCount: byteLength, sha256: sha256,
            thumbnailRelativePath: relativePath, thumbnailByteCount: byteLength,
            thumbnailSHA256: sha256, nextDraftStepKey: WorkflowDraftStep.wide.rawValue,
            createdAt: date)), mutationID: mutation()) }
    }

    func contentURL(_ item: CaptureInboxItemV1) -> URL {
        generationRoot.appendingPathComponent("content/\(workspaceID.rawValue.uuidString.lowercased())/\(item.content.contentID)/original.bin")
    }

    func item(evidence: EvidenceFile, label: String) throws -> CaptureInboxItemV1 {
        guard currentBinding != nil else { throw FastSurveyInboxFailureV1.invalidValue }
        let bytes = try Data(contentsOf: generationRoot.appendingPathComponent(evidence.relativePath))
        guard bytes.count == evidence.byteCount, KernelCanonicalHashV1.sha256(bytes) == evidence.sha256 else {
            throw FastSurveyInboxFailureV1.missingContent
        }
        let digest = try ContentDigestV1(algorithm: .sha256, hexadecimalValue: evidence.sha256)
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let reference = try ContentReferenceV1(workspaceID: workspaceID.rawValue.uuidString.lowercased(),
            contentID: evidence.id.uuidString.lowercased(), byteLength: Int64(evidence.byteCount),
            mediaType: evidence.mimeType, digests: ContentDigestSetV1([digest]), byteRole: .immutableOriginal,
            createdAt: formatter.string(from: evidence.createdAt))
        let provenance = try ContentOriginalProvenanceV1(provenanceID: "persisted-\(label)",
            workspaceID: reference.workspaceID, contentID: reference.contentID,
            contentDigest: digest, origin: .localImport, recordedAt: reference.createdAt)
        return try .init(inboxEventID: UUID(), inboxItemID: UUID(), workspaceID: workspaceID,
            mediaKind: .photo, content: reference, captureRole: .context, originalProvenance: provenance,
            observationBasis: observation(), temporalContext: temporal(), capturedBy: actor(),
            revision: 1, mutationID: mutation())
    }

    func physicalBackupSnapshot() throws -> FastSurveyInboxBackupSnapshotV1 {
        try Self.physicalBackupSnapshot(in: context, workspaceID: workspaceID)
    }

    static func physicalBackupSnapshot(in context: ModelContext, workspaceID: WorkspaceID) throws
        -> FastSurveyInboxBackupSnapshotV1 {
        let values = try FastSurveyInboxLifecycleAdapterV1(modelContext: context, workspaceID: workspaceID).snapshot()
        let itemProvenance = try context.fetch(FetchDescriptor<CaptureInboxItemRowV1>()).map {
            try FastSurveyInboxBackupEffectProvenanceV1(mutationID: $0.mutationID,
                semanticSHA256: $0.canonicalSHA256, writerInstanceID: $0.writerInstanceID)
        }
        let promotionProvenance = try context.fetch(FetchDescriptor<CapturePromotionRowV1>()).map {
            try FastSurveyInboxBackupEffectProvenanceV1(mutationID: $0.mutationID,
                semanticSHA256: $0.canonicalSHA256, writerInstanceID: $0.writerInstanceID)
        }
        let snippetProvenance = try context.fetch(FetchDescriptor<SnippetRowV1>()).map {
            try FastSurveyInboxBackupEffectProvenanceV1(mutationID: $0.mutationID,
                semanticSHA256: $0.canonicalSHA256, writerInstanceID: $0.writerInstanceID)
        }
        let insertionProvenance = try context.fetch(FetchDescriptor<SnippetInsertionHistoryRowV1>()).map {
            try FastSurveyInboxBackupEffectProvenanceV1(mutationID: $0.mutationID,
                semanticSHA256: $0.canonicalSHA256, writerInstanceID: $0.writerInstanceID)
        }
        return try .init(inboxItems: values.inboxItems, promotions: values.promotions,
            snippets: values.snippets, snippetInsertions: values.snippetInsertions,
            receipts: values.receipts,
            effectProvenance: itemProvenance + promotionProvenance + snippetProvenance + insertionProvenance)
    }

    func promotion(source: CaptureInboxItemV1, kind: CapturePromotionDestinationKindV1) throws -> (CapturePromotionV1, CaptureInboxItemV1) {
        let promotionID = UUID(), mutationID = try mutation()
        let promoted = try CaptureInboxItemV1(inboxEventID: UUID(), inboxItemID: source.inboxItemID, workspaceID: workspaceID, mediaKind: source.mediaKind, content: source.content, captureRole: source.captureRole, originalProvenance: source.originalProvenance, text: source.text, observationBasis: source.observationBasis, temporalContext: source.temporalContext, capturedBy: source.capturedBy, state: .promoted, promotionID: promotionID, predecessor: source, revision: 2, mutationID: mutationID)
        let destination: CapturePromotionDestinationV1
        if currentBinding != nil {
            destination = try currentDestination()
            guard kind == destination.kind else { throw FastSurveyInboxFailureV1.invalidValue }
        } else {
            destination = try destinationResolver.resolveCapturePromotionDestination(workspaceID: workspaceID, kind: kind, destinationID: destinationResolver.id(for: kind))
        }
        let promotion = try CapturePromotionV1(promotionID: promotionID, source: source, promotedItem: promoted, destination: destination, promotedBy: try actor(), promotedAt: date.addingTimeInterval(10), mutationID: mutationID)
        return (promotion, promoted)
    }

    func snippet(title: String, body: String, state: SnippetStateV1 = .active, predecessor: SnippetV1? = nil) throws -> SnippetV1 {
        try .init(snippetEventID: UUID(), snippetID: predecessor?.snippetID ?? UUID(), workspaceID: workspaceID, title: title, body: body, tags: ["field", "survey"], applicability: try .init(scope: .allLocalSurveys), state: state, predecessor: predecessor, revision: (predecessor?.revision ?? 0) + 1, mutationID: try mutation(), editedBy: try actor(), editedAt: date.addingTimeInterval(TimeInterval((predecessor?.revision ?? 0) + 1)))
    }

    func insertion(snippet: SnippetV1) throws -> SnippetInsertionV1 {
        let destination: CapturePromotionDestinationV1
        if currentBinding != nil { destination = try currentDestination() }
        else {
            destination = try destinationResolver.resolveCapturePromotionDestination(workspaceID: workspaceID,
                kind: .assetEvidence, destinationID: destinationResolver.id(for: .assetEvidence))
        }
        let target = try SnippetInsertionTargetV1(workspaceID: workspaceID, kind: .assetNoteDraft,
            targetID: destination.destinationID, targetRevision: destination.destinationRevision,
            targetSHA256: destination.destinationSHA256)
        return try .init(insertionEventID: UUID(), snippet: snippet, target: target,
            observationBasis: try observation(), saveIntent: .explicitUserSave, insertedBy: try actor(),
            insertedAt: date.addingTimeInterval(20), mutationID: try mutation())
    }

    func actor() throws -> ActorSnapshotV1 { let local = try LocalActorReferenceV1(actorReferenceID: UUID(), workspaceID: workspaceID, displayName: "C11 operator"); return try .init(snapshotID: UUID(), workspaceID: workspaceID, actor: local, responsibility: .recordedBy, displayNameAtTime: local.displayName, capturedAt: date) }
    func observation() throws -> ObservationBasisV1 { try .init(kind: .directlyObserved, method: try .init(key: "c11_fast_survey"), source: try .init(kind: .observer)) }
    func temporal() throws -> TemporalContextV1 { try .init(occurredAtUTC: date, recordedAtUTC: date, localDate: nil, localTime: nil, utcOffsetSeconds: nil, ianaTimeZoneIdentifier: nil, localTimeDisposition: .unknown) }
    func removeTypedRows() throws {
        // SwiftData's bulk delete did not remove these in-memory fixture rows
        // on the local runtime. Delete actual fetched instances so restore and
        // hostile-deletion witnesses prove a real persisted state transition.
        for row in try context.fetch(FetchDescriptor<CaptureInboxItemRowV1>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<CapturePromotionRowV1>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<SnippetRowV1>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<SnippetInsertionHistoryRowV1>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<FastSurveyInboxMutationReceiptRowV1>()) { context.delete(row) }
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CaptureInboxItemRowV1>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CapturePromotionRowV1>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SnippetRowV1>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SnippetInsertionHistoryRowV1>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FastSurveyInboxMutationReceiptRowV1>()), 0)
    }
}

/// This test resolver has no canned digest: its immutable answer is derived
/// from a real persisted asset, its exact creation envelope/post-image, and the
/// terminal journal revision. The fixture re-proves it before each use.
struct C11PersistedAssetDestinationResolver: CapturePromotionDestinationResolvingV1 {
    let destination: CapturePromotionDestinationV1

    @MainActor
    init(modelContext: ModelContext, workspaceID: WorkspaceID,
         journal: MutationJournalStoreV1, assetID: UUID) throws {
        let rows = try modelContext.fetch(FetchDescriptor<Asset>()).filter { $0.id == assetID }
        guard rows.count == 1, let asset = rows.first else { throw FastSurveyInboxFailureV1.missingContent }
        let history = try journal.exportSnapshot()
        let identity = try WorkspaceEntityIdentityV1(kind: .asset, id: assetID)
        let revisions = history.entityRevisions.filter { $0.identity == identity }
        guard revisions.count == 1, let revision = revisions.first else { throw FastSurveyInboxFailureV1.staleRevision }
        var candidates: [MutationPostImageV1] = []
        for record in history.receipts {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
            let receipt = try MutationReceiptV1.decodeCanonical(from: record.receiptData)
            guard envelope.workspaceID == workspaceID else { throw FastSurveyInboxFailureV1.wrongWorkspace }
            if case let .createFirstSign(created) = envelope.command, created.assetID == assetID {
                guard asset.siteID == created.siteID, asset.label == created.assetLabel,
                      asset.packID == created.packID, asset.packSchemaVersion == created.packSchemaVersion,
                      asset.packContentVersion == created.packContentVersion, asset.createdAt == created.createdAt else {
                    throw FastSurveyInboxFailureV1.staleRevision
                }
                candidates += try receipt.postImages.filter { try $0.identity == identity && $0.revision == revision.revision }
            }
        }
        guard candidates.count == 1, let postImage = candidates.first else { throw FastSurveyInboxFailureV1.staleRevision }
        destination = try .init(workspaceID: workspaceID, kind: .assetEvidence, destinationID: assetID,
            destinationRevision: revision.revision, destinationSHA256: postImage.semanticSHA256)
    }

    func resolveCapturePromotionDestination(workspaceID: WorkspaceID,
        kind: CapturePromotionDestinationKindV1, destinationID: UUID) throws -> CapturePromotionDestinationV1 {
        guard workspaceID == destination.workspaceID else { throw FastSurveyInboxFailureV1.wrongWorkspace }
        guard kind == destination.kind, destinationID == destination.destinationID else { throw FastSurveyInboxFailureV1.invalidValue }
        return destination
    }
}

struct C11StrictDestinationResolver: CapturePromotionDestinationResolvingV1 {
    private let workspaceID: WorkspaceID
    private let asset: CapturePromotionDestinationV1
    private let response: CapturePromotionDestinationV1
    private let finding: CapturePromotionDestinationV1
    private let correctiveWork: CapturePromotionDestinationV1

    init(workspaceID: WorkspaceID) throws {
        self.workspaceID = workspaceID
        asset = try .init(workspaceID: workspaceID, kind: .assetEvidence,
            destinationID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!, destinationRevision: 7,
            destinationSHA256: String(repeating: "1", count: 64))
        response = try .init(workspaceID: workspaceID, kind: .responseEvidence,
            destinationID: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!, destinationRevision: 11,
            destinationSHA256: String(repeating: "2", count: 64))
        finding = try .init(workspaceID: workspaceID, kind: .findingEvidence,
            destinationID: UUID(uuidString: "30000000-0000-4000-8000-000000000003")!, destinationRevision: 13,
            destinationSHA256: String(repeating: "3", count: 64))
        correctiveWork = try .init(workspaceID: workspaceID, kind: .correctiveWorkEvidence,
            destinationID: UUID(uuidString: "40000000-0000-4000-8000-000000000004")!, destinationRevision: 17,
            destinationSHA256: String(repeating: "4", count: 64))
    }

    func id(for kind: CapturePromotionDestinationKindV1) -> UUID {
        switch kind {
        case .assetEvidence: return asset.destinationID
        case .responseEvidence: return response.destinationID
        case .findingEvidence: return finding.destinationID
        case .correctiveWorkEvidence: return correctiveWork.destinationID
        }
    }

    func resolveCapturePromotionDestination(workspaceID: WorkspaceID,
        kind: CapturePromotionDestinationKindV1, destinationID: UUID) throws -> CapturePromotionDestinationV1 {
        guard workspaceID == self.workspaceID else { throw FastSurveyInboxFailureV1.wrongWorkspace }
        let exact: CapturePromotionDestinationV1
        switch kind { case .assetEvidence: exact = asset; case .responseEvidence: exact = response; case .findingEvidence: exact = finding; case .correctiveWorkEvidence: exact = correctiveWork }
        guard destinationID == exact.destinationID else { throw FastSurveyInboxFailureV1.invalidValue }
        return exact
    }
}

import CryptoKit
import Foundation
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V30P03C02OfflineSyncLocalizationTests: XCTestCase {
    func testSyncStateRegistryContainsEveryTypedKeyOnceWithItsExactEnglishDefault() throws {
        let fixture = try loadFixture()
        let registry = try BundledLocalizationCatalogV1.syncStateRegistry()
        try registry.validate()
        XCTAssertEqual(fixture.schemaVersion, 1)
        XCTAssertEqual(fixture.cardID, "V30-P03-C02")
        XCTAssertEqual(fixture.messageKeys.count, 55)
        XCTAssertEqual(fixture.messageKeys.map(\.key), LocalizedSyncStateMessageKeyV1.allCases.map(\.rawValue))
        XCTAssertEqual(Set(fixture.messageKeys.map(\.key)).count, fixture.messageKeys.count)

        for expected in fixture.messageKeys {
            let key = try XCTUnwrap(LocalizedSyncStateMessageKeyV1(rawValue: expected.key))
            let definition = try registry.definition(for: key.localizationKey)
            XCTAssertEqual(definition.key, key.localizationKey)
            XCTAssertEqual(definition.englishDefaultValue, expected.english)
            XCTAssertEqual(BundledLocalizationCatalogV1.syncStateEnglish(key), expected.english)
        }
    }

    func testDraftDurabilityMapperPreservesEveryExistingOutcomeBeforeLocalization() throws {
        let fixture = try loadFixture()
        let durable = try C36FieldDraftTestSupportV1.makeFixture()
        let inputs: [(DraftDurabilityPresentationStateV1, DraftDurabilityPresentationStateV1)] = [
            (DraftDurabilityPresentationMapperV1.state(checkpoint: durable.activeCheckpoint, hasDirtyChanges: true, writeInFlight: false, writeBlocked: false, receiptReadBack: false), .unsavedChanges),
            (DraftDurabilityPresentationMapperV1.state(checkpoint: durable.activeCheckpoint, hasDirtyChanges: true, writeInFlight: true, writeBlocked: false, receiptReadBack: false), .savingOnThisIPhone),
            (DraftDurabilityPresentationMapperV1.state(checkpoint: durable.activeCheckpoint, hasDirtyChanges: false, writeInFlight: false, writeBlocked: false, receiptReadBack: true), .savedOnThisIPhone),
            (DraftDurabilityPresentationMapperV1.state(checkpoint: durable.activeCheckpoint, hasDirtyChanges: false, writeInFlight: false, writeBlocked: true, receiptReadBack: false), .saveBlocked),
            (DraftDurabilityPresentationMapperV1.state(checkpoint: durable.committingCheckpoint, hasDirtyChanges: false, writeInFlight: false, writeBlocked: false, receiptReadBack: false), .committing),
            (DraftDurabilityPresentationMapperV1.state(checkpoint: try checkpoint(durable, state: .conflicted), hasDirtyChanges: false, writeInFlight: false, writeBlocked: false, receiptReadBack: false), .conflicted),
            (DraftDurabilityPresentationMapperV1.state(checkpoint: try checkpoint(durable, state: .recoveryRequired), hasDirtyChanges: false, writeInFlight: false, writeBlocked: false, receiptReadBack: false), .recoveryRequired),
            (DraftDurabilityPresentationMapperV1.state(checkpoint: durable.committedCheckpoint, hasDirtyChanges: false, writeInFlight: false, writeBlocked: false, receiptReadBack: true), .committed),
            (DraftDurabilityPresentationMapperV1.state(checkpoint: try checkpoint(durable, state: .discardPending), hasDirtyChanges: false, writeInFlight: false, writeBlocked: false, receiptReadBack: false), .discarding),
            (DraftDurabilityPresentationMapperV1.state(checkpoint: try checkpoint(durable, state: .discarded), hasDirtyChanges: false, writeInFlight: false, writeBlocked: false, receiptReadBack: true), .discarded),
        ]
        XCTAssertEqual(inputs.map(\.0), inputs.map(\.1))
        XCTAssertEqual(
            DraftDurabilityPresentationMapperV1.state(
                checkpoint: durable.committedCheckpoint, hasDirtyChanges: false,
                writeInFlight: false, writeBlocked: false, receiptReadBack: false
            ),
            .committing
        )
        XCTAssertEqual(inputs.map { $0.0.rawValue }, fixture.draftPresentation.map(\.input))
        for (state, expected) in zip(inputs.map(\.0), fixture.draftPresentation) {
            assertPresentation(.draft(state), equals: expected)
        }
    }

    func testUnicodeAttachmentStageRetainsExactBytesAcrossUILocalesAndReceiptReadback() throws {
        let fixture = try loadFixture()
        let bytes = Data(fixture.unicodeAttachment.text.utf8)
        XCTAssertEqual(fixture.unicodeAttachment.sourceLanguage, "en")
        XCTAssertEqual(bytes.count, fixture.unicodeAttachment.utf8ByteCount)
        XCTAssertEqual(sha256(bytes), fixture.unicodeAttachment.sha256)
        XCTAssertNotEqual(
            bytes, Data(fixture.unicodeAttachment.text.precomposedStringWithCanonicalMapping.utf8)
        )

        let durable = try C36FieldDraftTestSupportV1.makeFixture()
        let digest = try ContentDigestV1(algorithm: .sha256, hexadecimalValue: fixture.unicodeAttachment.sha256)
        let staged = try AttachmentStagingItemV1(
            stageID: durable.readyItem.stageID, draftID: durable.draftID, workspaceID: durable.workspaceID,
            attachmentKind: .file, scratchLeaseID: durable.readyItem.scratchLeaseID,
            expectedByteCount: Int64(bytes.count), actualByteCount: Int64(bytes.count), contentDigest: digest,
            retryClass: .none, state: .readyLocal, protectionState: .available, revision: 1,
            mutationID: try C36FieldDraftTestSupportV1.mutation(230_001)
        )
        try staged.validate()
        XCTAssertEqual(staged.actualByteCount, Int64(bytes.count))
        XCTAssertEqual(staged.contentDigest?.hexadecimalValue, fixture.unicodeAttachment.sha256)
        let canonicalStageBytes = try FieldDraftCanonicalCodecV1.encode(staged)
        let beforeReadBack = try LocalizedSyncStatePresentationV1.attachment(staged, durableReceiptReadBack: false)
        let afterReadBack = try LocalizedSyncStatePresentationV1.attachment(staged, durableReceiptReadBack: true)
        assertPresentation(beforeReadBack, equals: try fixture.attachment("STAGED_LOCAL"))
        assertPresentation(afterReadBack, equals: try fixture.attachment("READY"))

        let bundle = Bundle(for: Self.self)
        for identifier in fixture.uiLocales {
            let locale = Locale(identifier: identifier)
            let visible = LocalizedSyncStateRendererV1.text(beforeReadBack, bundle: bundle, locale: locale)
            let accessibility = LocalizedSyncStateRendererV1.text(beforeReadBack.messageKey, bundle: bundle, locale: locale)
            XCTAssertEqual(visible, accessibility, identifier)
            XCTAssertEqual(visible, BundledLocalizationCatalogV1.syncStateEnglish(beforeReadBack.messageKey), identifier)
            XCTAssertEqual(bytes, Data(fixture.unicodeAttachment.text.utf8), identifier)
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(staged), canonicalStageBytes, identifier)
        }

        let protected = try AttachmentStagingItemV1(
            stageID: durable.alternateReadyItem.stageID, draftID: durable.draftID, workspaceID: durable.workspaceID,
            attachmentKind: .audio, scratchLeaseID: durable.alternateReadyItem.scratchLeaseID,
            expectedByteCount: Int64(bytes.count), actualByteCount: Int64(bytes.count), contentDigest: digest,
            retryClass: .none, state: .readyLocal, protectionState: .protectedDataUnavailable, revision: 1,
            mutationID: try C36FieldDraftTestSupportV1.mutation(230_002)
        )
        assertPresentation(try .attachment(protected, durableReceiptReadBack: true), equals: .init(input: "blocked", state: "failed", key: "v30.sync-state.attachment-protected-data", success: false))
    }

    func testAttachmentRestoreRecoveryAndStartupKeepFailureAndPartialStatesDistinct() throws {
        let fixture = try loadFixture()
        XCTAssertEqual(DraftAttachmentPresentationStateV1.allCases.map(\.rawValue), fixture.attachmentPresentation.map(\.input))
        for expected in fixture.attachmentPresentation {
            let input = try XCTUnwrap(DraftAttachmentPresentationStateV1(rawValue: expected.input))
            assertPresentation(.attachment(input), equals: expected)
        }
        XCTAssertEqual(LocalizedRestoreStateV1.allCases.map { $0.descriptionKey }, fixture.restorePresentation.map(\.input))
        for expected in fixture.restorePresentation {
            let input = try XCTUnwrap(LocalizedRestoreStateV1(descriptionKey: expected.input))
            assertPresentation(.restore(input), equals: expected)
        }
        XCTAssertEqual(RecoveryCenterStateV1.allCases.map(\.rawValue), fixture.recoveryPresentation.map(\.input))
        for expected in fixture.recoveryPresentation {
            let input = try XCTUnwrap(RecoveryCenterStateV1(rawValue: expected.input))
            assertPresentation(.recovery(input), equals: expected)
        }
        XCTAssertFalse(LocalizedSyncStatePresentationV1.recovery(.partialSafe).permitsSuccessAnnouncement)
        XCTAssertFalse(LocalizedSyncStatePresentationV1.recovery(.validationFailed).permitsSuccessAnnouncement)
        XCTAssertEqual(Set(fixture.recoveryPresentation.map(\.key)).count, RecoveryCenterStateV1.allCases.count)

        XCTAssertEqual(StartupMaintenanceReason.allCases.map { $0.v30MessageKey.rawValue }, fixture.startupMaintenance.map(\.key))
        let bootstrap: [StartupRecoveryBootstrapStateV1] = [
            .checking, .ready, .eraseCleanupPending, .maintenance(.dataPointerInvalid),
        ]
        XCTAssertEqual(bootstrap.map { $0.v30MessageKey.rawValue }, fixture.startupBootstrap.map(\.key))
    }

    func testRemoteStatusAndRegistryDoNotClaimRemoteSynchronizationOrNotificationTruth() throws {
        let fixture = try loadFixture()
        for expected in fixture.remoteStatuses {
            let status = try remoteStatus(expected.input)
            assertPresentation(.remoteStatus(status), equals: expected)
        }
        let registryPresentation = try SyncClassificationRegistryV1.v30RemoteSyncState()
        XCTAssertEqual(registryPresentation, .remoteSyncUnavailable)
        XCTAssertNil(registryPresentation.state)
        XCTAssertFalse(registryPresentation.permitsSuccessAnnouncement)
        XCTAssertFalse(registryPresentation.claimsRemoteSynchronization)
        XCTAssertFalse(ScheduleNotificationCapabilityBoundaryV1.permissionIsCanonicalScheduleTruth)
        try ScheduleRestoreIdentityPolicyV1.validate()
        XCTAssertFalse(ScheduleRestoreIdentityPolicyV1.notificationStateRestoredAsTruth)
    }

    func testReplayPresentationKeepsRejectedDeferredConflictAndNoChangeStatesNonSuccessful() throws {
        let applied = try replayPresentation([.applied])
        XCTAssertEqual(applied.state, .recovered)
        XCTAssertTrue(applied.permitsSuccessAnnouncement)

        let rejected = try replayPresentation([.applied, .rejected])
        XCTAssertEqual(rejected.state, .failed)
        XCTAssertFalse(rejected.permitsSuccessAnnouncement)

        let deferredGap = try replayPresentation([.deferredGap])
        XCTAssertEqual(deferredGap.state, .pending)
        XCTAssertFalse(deferredGap.permitsSuccessAnnouncement)
        let deferredContent = try replayPresentation([.deferredContent])
        XCTAssertEqual(deferredContent.state, .pending)
        XCTAssertFalse(deferredContent.permitsSuccessAnnouncement)
        let externallyDeferred = try replayPresentation([.applied], isDeferred: true)
        XCTAssertEqual(externallyDeferred.state, .pending)
        XCTAssertFalse(externallyDeferred.permitsSuccessAnnouncement)

        let conflicted = try replayPresentation([.unresolvedConflict])
        XCTAssertEqual(conflicted.state, .conflicted)
        XCTAssertFalse(conflicted.permitsSuccessAnnouncement)
        let empty = try replayPresentation([])
        XCTAssertNil(empty.state)
        XCTAssertFalse(empty.permitsSuccessAnnouncement)
        let exclusionOnly = try replayPresentation([.localOnlyExcluded])
        XCTAssertNil(exclusionOnly.state)
        XCTAssertFalse(exclusionOnly.permitsSuccessAnnouncement)
    }

    private func replayPresentation(
        _ kinds: [ChangeReplayDispositionV1], isDeferred: Bool = false
    ) throws -> LocalizedSyncStatePresentationV1 {
        let limits = try ChangeJournalLimitsV1(
            maximumChangesPerBatch: 8, maximumBatchBytes: 1_024,
            maximumEntitiesPerCheckpoint: 8, maximumContentEntriesPerCheckpoint: 8,
            maximumReplicaFrontiers: 2, maximumConflicts: 2
        )
        let workspaceID = WorkspaceID(
            rawValue: UUID(uuidString: "c0230000-0000-4000-8000-000000000001")!
        )
        let destinationReplicaID = ReplicaID(
            rawValue: UUID(uuidString: "c0230000-0000-4000-8000-000000000002")!
        )
        let frontier = try ChangeJournalFrontierV1(
            workspaceRevision: 1,
            replicas: [try ReplicaRevisionFrontierV1(replicaID: destinationReplicaID, localSequence: 1)],
            entityRevisionSHA256: String(repeating: "a", count: 64),
            observedMutationSetSHA256: String(repeating: "b", count: 64), limits: limits
        )
        let conflict = try ConflictIdentityV1.derive(
            subject: .workspace(workspaceID),
            policy: ConflictPolicyV1(policyID: "v30-p03-c02-replay", rule: .exactRevisionManual),
            competitors: [try ConflictCompetitorV1(
                mutationID: try MutationIDV1(rawValue: UUID(uuidString: "c0230000-0000-4000-8000-000000000100")!),
                canonicalInputSHA256: String(repeating: "c", count: 64)
            )]
        )
        let dispositions = try kinds.enumerated().map { offset, kind in
            try MutationReplayDispositionV1(
                mutationID: try MutationIDV1(rawValue: UUID(uuidString: String(
                    format: "c0230000-0000-4000-8000-%012d", offset + 10
                ))!),
                disposition: kind,
                missingContentIDs: kind == .deferredContent ? ["content-c023"] : [],
                conflictIdentity: kind == .unresolvedConflict ? conflict : nil
            )
        }
        let receipt = try ChangeReplayReceiptV1(
            workspaceID: workspaceID, destinationReplicaID: destinationReplicaID,
            destinationGenerationID: UUID(uuidString: "c0230000-0000-4000-8000-000000000003")!,
            batchSHA256: String(repeating: "d", count: 64), resultingFrontier: frontier,
            dispositions: dispositions, semanticProjectionSHA256: String(repeating: "e", count: 64),
            limits: limits
        )
        return try LocalizedSyncStatePresentationV1.replay(
            receipt: receipt, isDeferred: isDeferred, limits: limits
        )
    }

    private func remoteStatus(_ value: String) throws -> LocalizedRemoteSyncStatusV1 {
        switch value {
        case "syncing": return .syncing
        case "synchronized": return .synchronized
        default: throw FixtureFailure.invalidValue
        }
    }

    private func checkpoint(
        _ fixture: C36FieldDraftTestSupportV1.Fixture, state: FieldDraftStateV1, revision: UInt64 = 4
    ) throws -> FieldDraftCheckpointV1 {
        let terminal = state == .committed || state == .discarded
        return try FieldDraftCheckpointV1(
            draftID: fixture.draftID, workspaceID: fixture.workspaceID, scope: fixture.scope,
            purpose: .inspectionReview, codec: fixture.codec, baseCanonicalRevision: fixture.activeCheckpoint.baseCanonicalRevision,
            draftRevision: revision, payloadData: fixture.payload, stageIDs: fixture.activeCheckpoint.stageIDs,
            resumeAnchor: fixture.anchor, state: state,
            lastDurableMutationID: terminal ? try C36FieldDraftTestSupportV1.mutation(230_100 + Int(revision)) : nil,
            lastReceiptSHA256: terminal ? C36FieldDraftTestSupportV1.digest : nil,
            updatedAt: C36FieldDraftTestSupportV1.fixedDate.addingTimeInterval(Double(revision)),
            mutationID: try C36FieldDraftTestSupportV1.mutation(230_200 + Int(revision))
        )
    }

    private func assertPresentation(
        _ actual: LocalizedSyncStatePresentationV1, equals expected: Fixture.Presentation
    ) {
        XCTAssertEqual(actual.state?.rawValue, expected.state)
        XCTAssertEqual(actual.messageKey.rawValue, expected.key)
        XCTAssertEqual(actual.permitsSuccessAnnouncement, expected.success)
        XCTAssertFalse(actual.claimsRemoteSynchronization)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func loadFixture() throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V30/SyncStates/localized-sync-state-cases-v1.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }
}

private struct Fixture: Decodable {
    struct UnicodeAttachment: Decodable { let sourceLanguage: String; let text: String; let utf8ByteCount: Int; let sha256: String }
    struct MessageKey: Decodable { let key: String; let english: String }
    struct Presentation: Decodable { let input: String; let state: String?; let key: String; let success: Bool }
    struct KeyedState: Decodable { let input: String; let key: String }
    let schemaVersion: Int
    let cardID: String
    let uiLocales: [String]
    let unicodeAttachment: UnicodeAttachment
    let messageKeys: [MessageKey]
    let draftPresentation: [Presentation]
    let attachmentPresentation: [Presentation]
    let restorePresentation: [Presentation]
    let recoveryPresentation: [Presentation]
    let startupBootstrap: [KeyedState]
    let startupMaintenance: [KeyedState]
    let remoteStatuses: [Presentation]

    func attachment(_ input: String) throws -> Presentation {
        try XCTUnwrap(attachmentPresentation.first { $0.input == input })
    }
}

private enum FixtureFailure: Error { case invalidValue }

private extension LocalizedRestoreStateV1 {
    var descriptionKey: String {
        switch self { case .checking: "checking"; case .restoring: "restoring"; case .failed: "failed"; case .complete: "complete" }
    }

    init?(descriptionKey: String) {
        switch descriptionKey { case "checking": self = .checking; case "restoring": self = .restoring; case "failed": self = .failed; case "complete": self = .complete; default: return nil }
    }
}

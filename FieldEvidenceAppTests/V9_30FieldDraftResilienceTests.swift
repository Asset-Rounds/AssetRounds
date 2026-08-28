import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private struct C36CorpusV1: Decodable {
    let schemaVersion: Int
    let cardID: String
    let phase: String
    let persistentSchemaVersion: Int
    let persistentModelCount: Int
    let recordsSchemaVersion: Int
    let records: Int
    let evidenceSelectors: [EvidenceSelector]
    let autosave: Autosave
    let limits: Limits
    let purposeDefinitions: [PurposeDefinition]
    let checkpointStates: [String]
    let presentationStates: [String]
    let attachmentPresentationStates: [String]
    let stagingStates: [String]
    let sagaStates: [String]
    let sagaEdges: [[String]]
    let rowMutationIDs: RowMutationIDs
    let terminalBundles: TerminalBundles
    let conflictPlans: [String]
    let reservationStates: [String]
    let recoveryStatuses: [String]
    let safeActions: [String]
    let lifecycleDispositions: [String]
    let backupRestore: BackupRestore
    let privacyExclusions: [String]
    let coverageAssertions: Coverage
    let singleAuthority: SingleAuthority
    let boundaryRefs: [String]

    struct EvidenceSelector: Decodable {
        let id: String
        let selector: String
        let focus: String
    }

    struct Autosave: Decodable {
        let trailingNanoseconds: UInt64
        let maximumDirtyNanoseconds: UInt64
        let forceFlushBoundaries: [String]
    }

    struct Limits: Decodable {
        let maximumPayloadBytes: Int
        let maximumStageItems: Int
        let maximumScopeComponents: Int
        let maximumAnchorComponents: Int
        let maximumTextBytes: Int
    }

    struct PurposeDefinition: Decodable {
        let purpose: String
        let codecID: String
        let codecVersion: UInt64
        let maximumPayloadBytes: Int
        let maximumStageItems: Int
        let targetCommand: String
        let retention: String
        let privacy: String
        let attachmentKinds: [String]
    }

    struct BackupRestore: Decodable {
        let fieldDraftKinds: [String]
        let restoresCheckpoint: Bool
        let restoresReadyLocal: Bool
        let restoresReservations: Bool
        let restoresPromotedUnbound: Bool
        let restoresStableSagaEdge: Bool
        let cloneDisposition: String
        let configurationCloneDisposition: String
    }

    struct Coverage: Decodable {
        let casDraftAndBaseRevision: Bool
        let perItemFailureIsolation: Bool
        let exactRetryReusesReservation: Bool
        let noSecondWriter: Bool
        let noSecondStore: Bool
        let noCloudStore: Bool
        let recordsAreCanonicalOnlyAfterCommit: Bool
    }

    struct RowMutationIDs: Decodable {
        let perStageReservationIDs: Bool
        let terminalBundleMutationIDDistinct: Bool
        let collisionRejected: Bool
        let promotionMapByStageID: Bool
    }

    struct TerminalBundles: Decodable {
        let commitUsesAtomicWriter: Bool
        let discardUsesAtomicWriter: Bool
        let commitDerivesTerminalCheckpoint: Bool
        let discardRequiresCurrentPendingCheckpoint: Bool
    }

    struct SingleAuthority: Decodable {
        let writerProtocol: String
        let coordinator: String
        let recoveryProjection: String
        let persistentRows: Int
        let secondWriter: Bool
        let secondStore: Bool
    }
}

@MainActor
private final class C36RecoverySourceV1: DraftRecoveryRecordSourceV1 {
    var values: [FieldDraftCheckpointV1]
    var items: [UUID: [AttachmentStagingItemV1]]
    var targetRevision: UInt64?

    init(
        values: [FieldDraftCheckpointV1],
        items: [UUID: [AttachmentStagingItemV1]],
        targetRevision: UInt64?
    ) {
        self.values = values
        self.items = items
        self.targetRevision = targetRevision
    }

    func checkpoints(workspaceID: WorkspaceID) throws -> [FieldDraftCheckpointV1] {
        values.filter { $0.workspaceID == workspaceID }
    }

    func stagingItems(workspaceID: WorkspaceID, draftID: UUID) throws -> [AttachmentStagingItemV1] {
        (items[draftID] ?? []).filter { $0.workspaceID == workspaceID }
    }

    func currentTargetRevision(
        workspaceID: WorkspaceID,
        scope: DraftScopeKeyV1,
        targetCommandKind: WorkspaceCommandKindV1
    ) throws -> UInt64? {
        targetRevision
    }
}

private actor C36PromotionMapProbeV1: DraftContentPromotionPortV1 {
    private var received: [UUID: MutationIDV1] = [:]

    func promote(
        plan: DraftCommitPlanV1,
        items: [AttachmentStagingItemV1],
        reservationMutationIDs: [UUID: MutationIDV1]
    ) async throws -> [DraftContentReservationV1] {
        _ = plan
        _ = items
        received = reservationMutationIDs
        return []
    }

    func quarantine(
        reservations: [DraftContentReservationV1],
        for plan: DraftDiscardPlanV1
    ) async throws {
        _ = reservations
        _ = plan
    }

    func receivedMap() -> [UUID: MutationIDV1] {
        received
    }
}

@MainActor
private final class C36TerminalWriterProbeV1: FieldDraftWritingV1 {
    private(set) var commitApplyCount = 0
    private(set) var discardApplyCount = 0
    private(set) var lastCommitBundle: DraftCommitTerminalBundleV1?
    private(set) var lastDiscardBundle: DraftDiscardTerminalBundleV1?

    func currentCheckpoint(
        workspaceID: WorkspaceID,
        draftID: UUID
    ) throws -> FieldDraftCheckpointV1? {
        _ = workspaceID
        _ = draftID
        throw FieldDraftFailureV1.invalidValue
    }

    func compareAndSwap(
        checkpoint: FieldDraftCheckpointV1,
        expectedDraftRevision: UInt64,
        expectedBaseRevision: UInt64
    ) throws -> MutationReceiptV1 {
        _ = checkpoint
        _ = expectedDraftRevision
        _ = expectedBaseRevision
        throw FieldDraftFailureV1.invalidValue
    }

    func append(
        stagingItem: AttachmentStagingItemV1,
        expectedRevision: UInt64
    ) throws -> MutationReceiptV1 {
        _ = stagingItem
        _ = expectedRevision
        throw FieldDraftFailureV1.invalidValue
    }

    func append(
        saga: DraftCommitSagaV1,
        expectedRevision: UInt64
    ) throws -> MutationReceiptV1 {
        _ = saga
        _ = expectedRevision
        throw FieldDraftFailureV1.invalidValue
    }

    func append(
        reservation: DraftContentReservationV1,
        expectedRevision: UInt64
    ) throws -> MutationReceiptV1 {
        _ = reservation
        _ = expectedRevision
        throw FieldDraftFailureV1.invalidValue
    }

    func apply(
        commitTerminalBundle: DraftCommitTerminalBundleV1,
        expectedDraftRevision: UInt64,
        expectedSagaRevision: UInt64
    ) throws -> MutationReceiptV1 {
        _ = expectedDraftRevision
        _ = expectedSagaRevision
        commitApplyCount += 1
        lastCommitBundle = commitTerminalBundle
        throw FieldDraftFailureV1.invalidValue
    }

    func apply(
        discardTerminalBundle: DraftDiscardTerminalBundleV1,
        expectedDraftRevision: UInt64
    ) throws -> MutationReceiptV1 {
        _ = expectedDraftRevision
        discardApplyCount += 1
        lastDiscardBundle = discardTerminalBundle
        throw FieldDraftFailureV1.invalidValue
    }
}

@MainActor
private final class C36TargetProbeV1: DraftCanonicalCommitPortV1 {
    func commit(
        plan: DraftCommitPlanV1,
        reservations: [DraftContentReservationV1]
    ) throws -> MutationReceiptV1 {
        _ = plan
        _ = reservations
        throw FieldDraftFailureV1.invalidValue
    }

    func readBackMatches(
        plan: DraftCommitPlanV1,
        receipt: MutationReceiptV1
    ) throws -> Bool {
        _ = plan
        _ = receipt
        throw FieldDraftFailureV1.invalidValue
    }
}

final class V9_30FieldDraftResilienceTests: XCTestCase {
    private func fixture() throws -> C36FieldDraftTestSupportV1.Fixture {
        try C36FieldDraftTestSupportV1.makeFixture()
    }

    private func corpus() throws -> C36CorpusV1 {
        let data = try Data(contentsOf: C36FieldDraftTestSupportV1.corpusURL())
        return try JSONDecoder().decode(C36CorpusV1.self, from: data)
    }

    private func checkpoint(
        _ fixture: C36FieldDraftTestSupportV1.Fixture,
        state: FieldDraftStateV1,
        revision: UInt64 = 4
    ) throws -> FieldDraftCheckpointV1 {
        let terminal = state == .committed || state == .discarded
        let durableMutationID: MutationIDV1? = terminal
            ? try C36FieldDraftTestSupportV1.mutation(136_500 + Int(revision))
            : nil
        return try FieldDraftCheckpointV1(
            draftID: fixture.draftID, workspaceID: fixture.workspaceID,
            scope: fixture.scope, purpose: .inspectionReview, codec: fixture.codec,
            baseCanonicalRevision: fixture.activeCheckpoint.baseCanonicalRevision,
            draftRevision: revision, payloadData: fixture.payload,
            stageIDs: fixture.activeCheckpoint.stageIDs, resumeAnchor: fixture.anchor,
            state: state, lastDurableMutationID: durableMutationID,
            lastReceiptSHA256: terminal ? C36FieldDraftTestSupportV1.digest : nil,
            updatedAt: C36FieldDraftTestSupportV1.fixedDate.addingTimeInterval(Double(revision)),
            mutationID: try C36FieldDraftTestSupportV1.mutation(136_600 + Int(revision))
        )
    }

    private func stagingItem(
        _ fixture: C36FieldDraftTestSupportV1.Fixture,
        state: AttachmentStagingStateV1,
        revision: UInt64 = 1
    ) throws -> AttachmentStagingItemV1 {
        let durable = state == .readyLocal || state == .committed
        return try AttachmentStagingItemV1(
            stageID: fixture.readyItem.stageID, draftID: fixture.draftID,
            workspaceID: fixture.workspaceID, attachmentKind: .photo,
            scratchLeaseID: fixture.readyItem.scratchLeaseID, expectedByteCount: 64,
            actualByteCount: durable ? 64 : nil,
            contentDigest: durable ? fixture.readyItem.contentDigest : nil,
            contentReference: state == .committed ? fixture.committedItem.contentReference : nil,
            retryClass: state == .failedRetryable ? .retryable : (state == .failedFinal ? .final : .none),
            state: state, protectionState: .available, revision: revision,
            mutationID: try C36FieldDraftTestSupportV1.mutation(136_700 + Int(revision))
        )
    }

    func testV9_30G01GoldenCheckpointAutosavePurposeAndPresentationTruth() throws {
        let fixture = try fixture()
        let corpus = try corpus()

        try fixture.activeCheckpoint.validate(registry: fixture.registry)
        try fixture.committingCheckpoint.validate(registry: fixture.registry)
        try fixture.committedCheckpoint.validate(registry: fixture.registry)
        XCTAssertEqual(corpus.evidenceSelectors.map(\.selector), ["G", "A", "H", "I", "R"])
        XCTAssertEqual(corpus.evidenceSelectors.map(\.id), [
            "V23-P03-C36-G01", "V23-P03-C36-A01", "V23-P03-C36-H01",
            "V23-P03-C36-I01", "V23-P03-C36-R01"
        ])
        XCTAssertEqual(FieldDraftStateV1.allCases.map(\.rawValue), corpus.checkpointStates)
        XCTAssertEqual(DraftDurabilityPresentationStateV1.allCases.map(\.rawValue), corpus.presentationStates)

        let policy = try DraftAutosavePolicyV1()
        XCTAssertEqual(policy.trailingNanoseconds, corpus.autosave.trailingNanoseconds)
        XCTAssertEqual(policy.maximumDirtyNanoseconds, corpus.autosave.maximumDirtyNanoseconds)
        XCTAssertEqual(policy.trailingNanoseconds, 750_000_000)
        XCTAssertEqual(policy.maximumDirtyNanoseconds, 5_000_000_000)
        XCTAssertEqual(corpus.autosave.forceFlushBoundaries, ["NAVIGATION", "BACKGROUND", "HANDOFF", "PROMOTION", "SHARE"])
        XCTAssertEqual(corpus.limits.maximumPayloadBytes, FieldDraftLimitsV1.maximumPayloadBytes)
        XCTAssertEqual(corpus.limits.maximumStageItems, FieldDraftLimitsV1.maximumStageItems)
        XCTAssertEqual(corpus.limits.maximumScopeComponents, FieldDraftLimitsV1.maximumScopeComponents)
        XCTAssertEqual(corpus.limits.maximumAnchorComponents, FieldDraftLimitsV1.maximumAnchorComponents)
        XCTAssertEqual(corpus.limits.maximumTextBytes, FieldDraftLimitsV1.maximumTextBytes)

        XCTAssertEqual(
            DraftDurabilityPresentationMapperV1.state(
                checkpoint: fixture.activeCheckpoint, hasDirtyChanges: true,
                writeInFlight: false, writeBlocked: false, receiptReadBack: false
            ), .unsavedChanges
        )
        XCTAssertEqual(
            DraftDurabilityPresentationMapperV1.state(
                checkpoint: fixture.activeCheckpoint, hasDirtyChanges: true,
                writeInFlight: true, writeBlocked: false, receiptReadBack: false
            ), .savingOnThisIPhone
        )
        XCTAssertEqual(
            DraftDurabilityPresentationMapperV1.state(
                checkpoint: fixture.activeCheckpoint, hasDirtyChanges: false,
                writeInFlight: false, writeBlocked: true, receiptReadBack: false
            ), .saveBlocked
        )
        XCTAssertEqual(
            DraftDurabilityPresentationMapperV1.state(
                checkpoint: fixture.activeCheckpoint, hasDirtyChanges: false,
                writeInFlight: false, writeBlocked: false, receiptReadBack: true
            ), .savedOnThisIPhone
        )
        XCTAssertEqual(
            DraftDurabilityPresentationMapperV1.state(
                checkpoint: fixture.committingCheckpoint, hasDirtyChanges: false,
                writeInFlight: false, writeBlocked: false, receiptReadBack: false
            ), .committing
        )
        XCTAssertEqual(
            DraftDurabilityPresentationMapperV1.state(
                checkpoint: try checkpoint(fixture, state: .conflicted), hasDirtyChanges: false,
                writeInFlight: false, writeBlocked: false, receiptReadBack: false
            ), .conflicted
        )
        XCTAssertEqual(
            DraftDurabilityPresentationMapperV1.state(
                checkpoint: try checkpoint(fixture, state: .recoveryRequired), hasDirtyChanges: false,
                writeInFlight: false, writeBlocked: false, receiptReadBack: false
            ), .recoveryRequired
        )
        XCTAssertEqual(
            DraftDurabilityPresentationMapperV1.state(
                checkpoint: fixture.committedCheckpoint, hasDirtyChanges: false,
                writeInFlight: false, writeBlocked: false, receiptReadBack: true
            ), .committed
        )
        XCTAssertEqual(
            DraftDurabilityPresentationMapperV1.state(
                checkpoint: fixture.committedCheckpoint, hasDirtyChanges: false,
                writeInFlight: false, writeBlocked: false, receiptReadBack: false
            ), .committing
        )
        XCTAssertEqual(
            DraftDurabilityPresentationMapperV1.state(
                checkpoint: try checkpoint(fixture, state: .discardPending), hasDirtyChanges: false,
                writeInFlight: false, writeBlocked: false, receiptReadBack: false
            ), .discarding
        )
        XCTAssertEqual(
            DraftDurabilityPresentationMapperV1.state(
                checkpoint: try checkpoint(fixture, state: .discarded), hasDirtyChanges: false,
                writeInFlight: false, writeBlocked: false, receiptReadBack: true
            ), .discarded
        )

        for definition in corpus.purposeDefinitions {
            guard let purpose = DraftPurposeV1(rawValue: definition.purpose) else {
                return XCTFail("unknown corpus purpose")
            }
            let codec = try C36FieldDraftTestSupportV1.codec(for: purpose)
            let resolved = try fixture.registry.require(purpose, codec: codec)
            XCTAssertEqual(resolved.maximumPayloadBytes, definition.maximumPayloadBytes)
            XCTAssertEqual(resolved.maximumStageItems, definition.maximumStageItems)
            XCTAssertEqual(resolved.codec.codecID, definition.codecID)
            XCTAssertEqual(resolved.codec.codecVersion, definition.codecVersion)
            XCTAssertEqual(resolved.targetCommandKind.rawValue, definition.targetCommand)
            XCTAssertEqual(resolved.retention.rawValue, definition.retention)
            XCTAssertEqual(resolved.privacyClass.rawValue, definition.privacy)
            XCTAssertEqual(resolved.attachmentKinds.map(\.rawValue), definition.attachmentKinds)
        }

        let encoded = try FieldDraftCanonicalCodecV1.encode(fixture.activeCheckpoint)
        XCTAssertEqual(try FieldDraftCanonicalCodecV1.decode(FieldDraftCheckpointV1.self, from: encoded), fixture.activeCheckpoint)
    }

    func testV9_30A01AlternatePerItemStagingAndExactRetryRemainIndependent() throws {
        let fixture = try fixture()
        let corpus = try corpus()

        XCTAssertEqual(AttachmentStagingStateV1.allCases.map(\.rawValue), corpus.stagingStates)
        XCTAssertEqual(DraftAttachmentPresentationStateV1.allCases.map(\.rawValue), corpus.attachmentPresentationStates)
        try fixture.readyItem.validate()
        try fixture.alternateReadyItem.validate()
        try fixture.failedItem.validate()

        XCTAssertNotEqual(fixture.readyItem.stageID, fixture.alternateReadyItem.stageID)
        XCTAssertNotEqual(fixture.failedItem.stageID, fixture.readyItem.stageID)
        XCTAssertEqual(fixture.activeCheckpoint.stageIDs.count, 3)
        XCTAssertTrue(fixture.activeCheckpoint.stageIDs.contains(fixture.failedItem.stageID))
        XCTAssertTrue(fixture.activeCheckpoint.stageIDs.contains(fixture.alternateReadyItem.stageID))

        try fixture.retryCapture.validateSuccessor(of: fixture.failedItem)
        try fixture.retryHashing.validateSuccessor(of: fixture.retryCapture)
        try fixture.retryProcessing.validateSuccessor(of: fixture.retryHashing)
        try fixture.retryReady.validateSuccessor(of: fixture.retryProcessing)
        try fixture.committedItem.validateSuccessor(of: fixture.readyItem)

        XCTAssertEqual(
            DraftAttachmentPresentationMapperV1.state(for: fixture.failedItem, durableReceiptReadBack: false),
            .retryableFailure
        )
        XCTAssertEqual(
            DraftAttachmentPresentationMapperV1.state(for: fixture.readyItem, durableReceiptReadBack: false),
            .stagedLocal
        )
        XCTAssertEqual(
            DraftAttachmentPresentationMapperV1.state(for: fixture.readyItem, durableReceiptReadBack: true),
            .ready
        )
        XCTAssertEqual(
            DraftAttachmentPresentationMapperV1.state(for: fixture.committedItem, durableReceiptReadBack: false),
            .ready
        )
        XCTAssertEqual(
            DraftAttachmentPresentationMapperV1.state(for: fixture.committedItem, durableReceiptReadBack: true),
            .promoted
        )
        XCTAssertEqual(
            DraftAttachmentPresentationMapperV1.state(for: try stagingItem(fixture, state: .capturing), durableReceiptReadBack: false),
            .selected
        )
        XCTAssertEqual(
            DraftAttachmentPresentationMapperV1.state(for: try stagingItem(fixture, state: .hashing), durableReceiptReadBack: false),
            .loading
        )
        XCTAssertEqual(
            DraftAttachmentPresentationMapperV1.state(for: try stagingItem(fixture, state: .processing), durableReceiptReadBack: false),
            .processing
        )
        XCTAssertEqual(
            DraftAttachmentPresentationMapperV1.state(for: try stagingItem(fixture, state: .failedFinal), durableReceiptReadBack: false),
            .blocked
        )
        XCTAssertEqual(
            DraftAttachmentPresentationMapperV1.state(for: try stagingItem(fixture, state: .removePending), durableReceiptReadBack: false),
            .removed
        )
        XCTAssertEqual(
            DraftAttachmentPresentationMapperV1.state(for: try stagingItem(fixture, state: .orphanQuarantined), durableReceiptReadBack: false),
            .blocked
        )
    }

    func testV9_30H01HostileCodecBudgetPrivacyAndCrossWorkspaceInputsFailClosed() throws {
        let fixture = try fixture()
        let hostileBidi = "c36-hostile\u{202E}codec"
        XCTAssertThrowsError(
            try DraftPayloadCodecReleaseV1(
                codecID: hostileBidi, codecVersion: 1,
                releaseSHA256: C36FieldDraftTestSupportV1.digest
            )
        )
        XCTAssertThrowsError(
            try DraftScopeKeyV1(scopeKind: "inspection-field", stableComponentIDs: ["safe", "bad\u{202E}id"])
        )
        XCTAssertThrowsError(try DraftPurposeRegistryV1([]))

        let wrongCodec = try DraftPayloadCodecReleaseV1(
            codecID: "c36.unknown", codecVersion: 1,
            releaseSHA256: C36FieldDraftTestSupportV1.digest
        )
        let wrongCodecCheckpoint = try FieldDraftCheckpointV1(
            draftID: fixture.draftID, workspaceID: fixture.workspaceID, scope: fixture.scope,
            purpose: .inspectionReview, codec: wrongCodec,
            baseCanonicalRevision: fixture.activeCheckpoint.baseCanonicalRevision,
            draftRevision: 1, payloadData: fixture.payload, stageIDs: fixture.activeCheckpoint.stageIDs,
            resumeAnchor: fixture.anchor, state: .active,
            updatedAt: C36FieldDraftTestSupportV1.fixedDate,
            mutationID: try C36FieldDraftTestSupportV1.mutation(136_900)
        )
        XCTAssertThrowsError(try wrongCodecCheckpoint.validate(registry: fixture.registry))

        let overBudget = Data(repeating: 0, count: FieldDraftLimitsV1.maximumPayloadBytes + 1)
        XCTAssertThrowsError(
            try FieldDraftCheckpointV1(
                draftID: fixture.draftID, workspaceID: fixture.workspaceID, scope: fixture.scope,
                purpose: .inspectionReview, codec: fixture.codec,
                baseCanonicalRevision: fixture.activeCheckpoint.baseCanonicalRevision,
                draftRevision: 1, payloadData: overBudget, stageIDs: fixture.activeCheckpoint.stageIDs,
                resumeAnchor: fixture.anchor, state: .active,
                updatedAt: C36FieldDraftTestSupportV1.fixedDate,
                mutationID: try C36FieldDraftTestSupportV1.mutation(136_901)
            )
        )

        let canonical = try FieldDraftCanonicalCodecV1.encode(fixture.activeCheckpoint)
        let tampered = Data(Array(canonical.dropLast()) + [UInt8(0)])
        XCTAssertThrowsError(try FieldDraftCanonicalCodecV1.decode(FieldDraftCheckpointV1.self, from: tampered))

        let wrongWorkspace = try AttachmentStagingItemV1(
            stageID: fixture.readyItem.stageID, draftID: fixture.draftID,
            workspaceID: fixture.otherWorkspaceID, attachmentKind: .photo,
            scratchLeaseID: fixture.readyItem.scratchLeaseID, expectedByteCount: 64,
            actualByteCount: 64, contentDigest: fixture.readyItem.contentDigest,
            retryClass: .none, state: .readyLocal, protectionState: .available,
            revision: 1, mutationID: try C36FieldDraftTestSupportV1.mutation(136_902)
        )
        XCTAssertNotEqual(wrongWorkspace.workspaceID, fixture.workspaceID)
        XCTAssertThrowsError(
            try wrongWorkspace.validateSuccessor(of: fixture.readyItem)
        )

        XCTAssertEqual(fixture.registry.definitions.count, DraftPurposeV1.allCases.count)
        XCTAssertEqual(
            fixture.registry.definitions[.evidenceCuration]?.privacyClass,
            .restrictedEvidence
        )
        XCTAssertEqual(
            fixture.registry.definitions[.inspectionReview]?.privacyClass,
            .workspacePrivate
        )
        XCTAssertTrue(corpus.rowMutationIDs.perStageReservationIDs)
        XCTAssertTrue(corpus.rowMutationIDs.terminalBundleMutationIDDistinct)
        XCTAssertTrue(corpus.rowMutationIDs.collisionRejected)
        XCTAssertTrue(corpus.rowMutationIDs.promotionMapByStageID)

        let readyReservationMutationID = try XCTUnwrap(
            fixture.rowMutationIDs.reservationByStageID[fixture.readyItem.stageID]
        )
        let duplicateReservationIDs = try? DraftCommitRowMutationIDsV1(
            reservationByStageID: [
                fixture.readyItem.stageID: readyReservationMutationID,
                fixture.alternateReadyItem.stageID: readyReservationMutationID
            ],
            terminalBundleMutationID: fixture.rowMutationIDs.terminalBundleMutationID
        )
        XCTAssertNil(duplicateReservationIDs)

        let collidingTerminalBundleMutationIDs = try DraftCommitRowMutationIDsV1(
            reservationByStageID: fixture.rowMutationIDs.reservationByStageID,
            terminalBundleMutationID: fixture.plan.mutationID
        )
        XCTAssertThrowsError(
            try collidingTerminalBundleMutationIDs.validate(
                stageIDs: [fixture.readyItem.stageID, fixture.alternateReadyItem.stageID],
                targetMutationID: fixture.plan.mutationID,
                sagaMutationIDs: [
                    fixture.preparedSaga.mutationID, fixture.promotedSaga.mutationID,
                    fixture.targetCommittedSaga.mutationID, fixture.retirePendingSaga.mutationID
                ]
            )
        )

        let missingStageReservationIDs = try DraftCommitRowMutationIDsV1(
            reservationByStageID: [fixture.readyItem.stageID: readyReservationMutationID],
            terminalBundleMutationID: fixture.rowMutationIDs.terminalBundleMutationID
        )
        XCTAssertThrowsError(
            try missingStageReservationIDs.validate(
                stageIDs: [fixture.readyItem.stageID, fixture.alternateReadyItem.stageID],
                targetMutationID: fixture.plan.mutationID,
                sagaMutationIDs: [
                    fixture.preparedSaga.mutationID, fixture.promotedSaga.mutationID,
                    fixture.targetCommittedSaga.mutationID, fixture.retirePendingSaga.mutationID
                ]
            )
        )

        let targetMismatchReceipt = try DraftCommitReceiptV1(
            receiptID: fixture.commitReceipt.receiptID,
            workspaceID: fixture.commitReceipt.workspaceID,
            draftID: fixture.commitReceipt.draftID,
            sagaID: fixture.commitReceipt.sagaID,
            commitPlanSHA256: fixture.commitReceipt.commitPlanSHA256,
            sagaEventSHA256Chain: fixture.commitReceipt.sagaEventSHA256Chain,
            targetMutationID: fixture.rowMutationIDs.terminalBundleMutationID,
            targetReceiptSHA256: fixture.commitReceipt.targetReceiptSHA256,
            consumedStageToContentID: fixture.commitReceipt.consumedStageToContentID,
            committedAt: fixture.commitReceipt.committedAt,
            mutationID: fixture.commitReceipt.mutationID
        )
        XCTAssertNotEqual(targetMismatchReceipt.targetMutationID, fixture.plan.mutationID)
        XCTAssertThrowsError(
            try DraftCommitTerminalBundleV1(
                retiredSaga: fixture.retiredSaga,
                committedCheckpoint: fixture.committedCheckpoint,
                receipt: targetMismatchReceipt
            )
        )
    }

    func testV9_30I01InterruptionEverySagaEdgeExactRetryAndCASConflictPlan() async throws {
        let fixture = try fixture()
        let corpus = try corpus()

        XCTAssertEqual(DraftCommitSagaStateV1.allCases.map(\.rawValue), corpus.sagaStates)
        XCTAssertEqual(DraftConflictResolutionPlanV1.allCases.map(\.rawValue), corpus.conflictPlans)
        XCTAssertTrue(corpus.rowMutationIDs.perStageReservationIDs)
        XCTAssertTrue(corpus.rowMutationIDs.terminalBundleMutationIDDistinct)
        XCTAssertTrue(corpus.rowMutationIDs.promotionMapByStageID)
        try fixture.rowMutationIDs.validate(
            stageIDs: [fixture.readyItem.stageID, fixture.alternateReadyItem.stageID],
            targetMutationID: fixture.plan.mutationID,
            sagaMutationIDs: [
                fixture.preparedSaga.mutationID, fixture.promotedSaga.mutationID,
                fixture.targetCommittedSaga.mutationID, fixture.retirePendingSaga.mutationID
            ]
        )
        XCTAssertEqual(
            Set(fixture.rowMutationIDs.reservationByStageID.keys),
            Set([fixture.readyItem.stageID, fixture.alternateReadyItem.stageID])
        )
        XCTAssertEqual(
            Set(fixture.rowMutationIDs.reservationByStageID.values.map(\.rawValue)).count,
            fixture.rowMutationIDs.reservationByStageID.count
        )
        let allCommitMutationIDs = [
            fixture.plan.mutationID.rawValue,
            fixture.preparedSaga.mutationID.rawValue,
            fixture.promotedSaga.mutationID.rawValue,
            fixture.targetCommittedSaga.mutationID.rawValue,
            fixture.retirePendingSaga.mutationID.rawValue,
            fixture.rowMutationIDs.terminalBundleMutationID.rawValue
        ] + fixture.rowMutationIDs.reservationByStageID.values.map(\.rawValue)
        XCTAssertEqual(fixture.retiredSaga.mutationID, fixture.rowMutationIDs.terminalBundleMutationID)
        XCTAssertEqual(Set(allCommitMutationIDs).count, allCommitMutationIDs.count)
        let promotionProbe = C36PromotionMapProbeV1()
        _ = try await promotionProbe.promote(
            plan: fixture.plan,
            items: [fixture.readyItem, fixture.alternateReadyItem],
            reservationMutationIDs: fixture.rowMutationIDs.reservationByStageID
        )
        let receivedPromotionMap = await promotionProbe.receivedMap()
        XCTAssertEqual(receivedPromotionMap, fixture.rowMutationIDs.reservationByStageID)
        XCTAssertEqual(corpus.sagaEdges.count, 16)
        for edge in corpus.sagaEdges {
            XCTAssertEqual(edge.count, 2)
            let from = try XCTUnwrap(DraftCommitSagaStateV1(rawValue: edge[0]))
            let to = try XCTUnwrap(DraftCommitSagaStateV1(rawValue: edge[1]))
            XCTAssertTrue(DraftCommitSagaV1.permits(from, to), "uncovered saga edge \(edge)")
        }

        try fixture.promotedSaga.validateSuccessor(of: fixture.preparedSaga)
        try fixture.targetCommittedSaga.validateSuccessor(of: fixture.promotedSaga)
        try fixture.retirePendingSaga.validateSuccessor(of: fixture.targetCommittedSaga)
        try fixture.retiredSaga.validateSuccessor(of: fixture.retirePendingSaga)
        try fixture.conflictedSaga.validateSuccessor(of: fixture.preparedSaga)
        try fixture.recoverySaga.validateSuccessor(of: fixture.promotedSaga)
        XCTAssertThrowsError(try fixture.retiredSaga.validateSuccessor(of: fixture.targetCommittedSaga))

        try fixture.reusedReservation.validateSuccessor(of: fixture.reservation)
        XCTAssertEqual(fixture.reusedReservation.reservationID, fixture.reservation.reservationID)
        XCTAssertEqual(fixture.reusedReservation.commitPlanSHA256, fixture.reservation.commitPlanSHA256)
        XCTAssertEqual(fixture.reusedReservation.contentDigest, fixture.reservation.contentDigest)

        try fixture.committedCheckpoint.validateSuccessor(
            of: fixture.committingCheckpoint,
            expectedDraftRevision: fixture.committingCheckpoint.draftRevision,
            expectedBaseRevision: fixture.committingCheckpoint.baseCanonicalRevision
        )
        XCTAssertThrowsError(
            try fixture.committingCheckpoint.validateSuccessor(
                of: fixture.activeCheckpoint, expectedDraftRevision: 99,
                expectedBaseRevision: fixture.activeCheckpoint.baseCanonicalRevision
            )
        )
        try fixture.commitTerminalBundle.validate()
        XCTAssertEqual(fixture.commitTerminalBundle.retiredSaga, fixture.retiredSaga)
        XCTAssertEqual(fixture.commitTerminalBundle.committedCheckpoint, fixture.committedCheckpoint)
        XCTAssertEqual(fixture.commitTerminalBundle.receipt, fixture.commitReceipt)
        XCTAssertEqual(
            fixture.commitTerminalBundle.committedCheckpoint.updatedAt,
            C36FieldDraftTestSupportV1.fixedDate.addingTimeInterval(10)
        )
        try fixture.discardPendingCheckpoint.validateSuccessor(
            of: fixture.activeCheckpoint,
            expectedDraftRevision: fixture.activeCheckpoint.draftRevision,
            expectedBaseRevision: fixture.activeCheckpoint.baseCanonicalRevision
        )
        XCTAssertEqual(fixture.discardPlan.expectedDraftRevision, fixture.discardPendingCheckpoint.draftRevision)
        try fixture.discardedCheckpoint.validateSuccessor(
            of: fixture.discardPendingCheckpoint,
            expectedDraftRevision: fixture.discardPendingCheckpoint.draftRevision,
            expectedBaseRevision: fixture.discardPendingCheckpoint.baseCanonicalRevision
        )
        try fixture.discardTerminalBundle.validate()
        XCTAssertEqual(fixture.discardTerminalBundle.discardedCheckpoint, fixture.discardedCheckpoint)
        XCTAssertEqual(fixture.discardTerminalBundle.receipt, fixture.discardReceipt)

        let createMutation = try FieldDraftMutationV1(
            workspaceID: fixture.workspaceID, expectedRevision: 0,
            expectedBaseCanonicalRevision: fixture.activeCheckpoint.baseCanonicalRevision,
            mutationID: fixture.activeCheckpoint.mutationID,
            postImage: .createCheckpoint(fixture.activeCheckpoint)
        )
        let reviseMutation = try FieldDraftMutationV1(
            workspaceID: fixture.workspaceID, expectedRevision: fixture.activeCheckpoint.draftRevision,
            expectedBaseCanonicalRevision: fixture.committingCheckpoint.baseCanonicalRevision,
            mutationID: fixture.committingCheckpoint.mutationID,
            postImage: .reviseCheckpoint(fixture.committingCheckpoint)
        )
        try createMutation.validate()
        try reviseMutation.validate()
        XCTAssertEqual(try createMutation.affectedIdentity.kind, .fieldDraftCheckpoint)
        XCTAssertEqual(try reviseMutation.concurrencyIdentity.kind, .fieldDraftCheckpoint)
        XCTAssertNotEqual(try createMutation.canonicalSHA256(), try reviseMutation.canonicalSHA256())
        XCTAssertEqual(fixture.commitReceipt.sagaEventSHA256Chain, [
            fixture.preparedSaga.sagaSHA256, fixture.promotedSaga.sagaSHA256,
            fixture.targetCommittedSaga.sagaSHA256, fixture.retirePendingSaga.sagaSHA256,
            fixture.retiredSaga.sagaSHA256
        ])
        try fixture.commitReceipt.validate()
    }

    @MainActor
    func testV9_30R01RecoveryReservationRetentionBackupRestoreAndOneAuthority() async throws {
        let fixture = try fixture()
        let corpus = try corpus()

        XCTAssertEqual(DraftReservationReconciliationStateV1.allCases.map(\.rawValue), corpus.reservationStates)
        XCTAssertEqual(DraftRecoveryStatusV1.allCases.map(\.rawValue), corpus.recoveryStatuses)
        XCTAssertEqual(DraftRecoverySafeActionV1.allCases.map(\.rawValue), corpus.safeActions)
        XCTAssertEqual(DraftLifecycleDispositionV1.allCases.map(\.rawValue), corpus.lifecycleDispositions)
        XCTAssertEqual(corpus.backupRestore.fieldDraftKinds, [
            "CHECKPOINT", "STAGING_ITEM", "COMMIT_SAGA", "CONTENT_RESERVATION", "COMMIT_RECEIPT", "DISCARD_RECEIPT"
        ])
        XCTAssertTrue(corpus.backupRestore.restoresCheckpoint)
        XCTAssertTrue(corpus.backupRestore.restoresReadyLocal)
        XCTAssertTrue(corpus.backupRestore.restoresReservations)
        XCTAssertTrue(corpus.backupRestore.restoresPromotedUnbound)
        XCTAssertTrue(corpus.backupRestore.restoresStableSagaEdge)
        XCTAssertEqual(corpus.backupRestore.cloneDisposition, "RESTORE_REQUIRES_USER_REVIEW")
        XCTAssertEqual(corpus.backupRestore.configurationCloneDisposition, "EXCLUDED_FROM_CONFIGURATION_CLONE")
        XCTAssertEqual(DraftConfigurationCloneDispositionV1.restoreRequiresUserReview.rawValue, "RESTORE_REQUIRES_USER_REVIEW")
        XCTAssertEqual(DraftConfigurationCloneDispositionV1.excludedFromConfigurationClone.rawValue, "EXCLUDED_FROM_CONFIGURATION_CLONE")

        XCTAssertFalse(fixture.reservation.mayDelete(hasLiveReference: false))
        XCTAssertFalse(fixture.reusedReservation.mayDelete(hasLiveReference: false))
        XCTAssertFalse(fixture.associatedReservation.mayDelete(hasLiveReference: false))
        XCTAssertTrue(fixture.quarantinedReservation.mayDelete(hasLiveReference: false))
        XCTAssertTrue(fixture.deletedReservation.mayDelete(hasLiveReference: false))
        XCTAssertFalse(fixture.quarantinedReservation.mayDelete(hasLiveReference: true))
        XCTAssertFalse(fixture.deletedReservation.mayDelete(hasLiveReference: true))
        try fixture.quarantinedReservation.validateSuccessor(of: fixture.reservation)
        try fixture.deletedReservation.validateSuccessor(of: fixture.quarantinedReservation)

        XCTAssertNoThrow(try V16FieldDraftImportBoundaryV1.validate(persistent: 16, records: 15))
        XCTAssertThrowsError(try V16FieldDraftImportBoundaryV1.validate(persistent: 15, records: 15))
        XCTAssertEqual(PersistentSchemaV16.versionIdentifier, Schema.Version(16, 0, 0))
        XCTAssertEqual(PersistentSchemaV16.models.count, 64)
        XCTAssertEqual(PersistentSchemaV15.models.count, 58)
        XCTAssertEqual(PersistentSchemaMigrationPlanV15.schemas.count, 2)
        XCTAssertEqual(PersistentSchemaMigrationPlanV15.stages.count, 1)

        let backupRecords: [V16BackupFieldDraftRecordV1] = [
            .init(kind: .checkpoint, id: fixture.activeCheckpoint.draftID,
                  workspaceID: fixture.workspaceID.rawValue, revision: fixture.activeCheckpoint.draftRevision,
                  canonicalData: try FieldDraftCanonicalCodecV1.encode(fixture.activeCheckpoint)),
            .init(kind: .stagingItem, id: fixture.readyItem.stageID,
                  workspaceID: fixture.workspaceID.rawValue, revision: fixture.readyItem.revision,
                  canonicalData: try FieldDraftCanonicalCodecV1.encode(fixture.readyItem)),
            .init(kind: .commitSaga, id: fixture.preparedSaga.sagaID,
                  workspaceID: fixture.workspaceID.rawValue, revision: fixture.preparedSaga.revision,
                  canonicalData: try FieldDraftCanonicalCodecV1.encode(fixture.preparedSaga)),
            .init(kind: .contentReservation, id: fixture.reservation.reservationID,
                  workspaceID: fixture.workspaceID.rawValue, revision: fixture.reservation.revision,
                  canonicalData: try FieldDraftCanonicalCodecV1.encode(fixture.reservation)),
            .init(kind: .commitReceipt, id: fixture.commitReceipt.receiptID,
                  workspaceID: fixture.workspaceID.rawValue, revision: fixture.commitReceipt.revision,
                  canonicalData: try FieldDraftCanonicalCodecV1.encode(fixture.commitReceipt)),
            .init(kind: .discardReceipt, id: fixture.discardReceipt.receiptID,
                  workspaceID: fixture.workspaceID.rawValue, revision: fixture.discardReceipt.revision,
                  canonicalData: try FieldDraftCanonicalCodecV1.encode(fixture.discardReceipt))
        ]
        XCTAssertEqual(backupRecords.count, V16BackupFieldDraftRecordV1.Kind.allCases.count)
        XCTAssertTrue(backupRecords.allSatisfy { !$0.canonicalData.isEmpty && $0.workspaceID == fixture.workspaceID.rawValue })

        let checkpointRow = try FieldDraftCheckpointRow(fixture.activeCheckpoint)
        let stagingRow = try AttachmentStagingItemRow(fixture.readyItem)
        let sagaRow = try DraftCommitSagaRow(fixture.preparedSaga)
        let reservationRow = try DraftContentReservationRow(fixture.reservation)
        let commitRow = try DraftCommitReceiptRow(fixture.commitReceipt)
        let discardRow = try DraftDiscardReceiptRow(fixture.discardReceipt)
        XCTAssertEqual(try checkpointRow.value(), fixture.activeCheckpoint)
        XCTAssertEqual(try stagingRow.value(), fixture.readyItem)
        XCTAssertEqual(try sagaRow.value(), fixture.preparedSaga)
        XCTAssertEqual(try reservationRow.value(), fixture.reservation)
        XCTAssertEqual(try commitRow.value(), fixture.commitReceipt)
        XCTAssertEqual(try discardRow.value(), fixture.discardReceipt)

        let targetWorkspaceID = C36FieldDraftTestSupportV1.workspace(137_000)
        let map = try DraftRestoreIdentityMapV1(
            targetWorkspaceID: targetWorkspaceID,
            draftIDs: [fixture.draftID: C36FieldDraftTestSupportV1.id(137_001)],
            stageIDs: [
                fixture.readyItem.stageID: C36FieldDraftTestSupportV1.id(137_010),
                fixture.alternateReadyItem.stageID: C36FieldDraftTestSupportV1.id(137_011),
                fixture.failedItem.stageID: C36FieldDraftTestSupportV1.id(137_012)
            ],
            sagaIDs: [
                fixture.preparedSaga.sagaID: C36FieldDraftTestSupportV1.id(137_020),
                fixture.promotedSaga.sagaID: C36FieldDraftTestSupportV1.id(137_021),
                fixture.targetCommittedSaga.sagaID: C36FieldDraftTestSupportV1.id(137_022),
                fixture.retirePendingSaga.sagaID: C36FieldDraftTestSupportV1.id(137_023),
                fixture.retiredSaga.sagaID: C36FieldDraftTestSupportV1.id(137_024)
            ],
            reservationIDs: [fixture.reservation.reservationID: C36FieldDraftTestSupportV1.id(137_030)],
            receiptIDs: [
                fixture.commitReceipt.receiptID: C36FieldDraftTestSupportV1.id(137_040),
                fixture.discardReceipt.receiptID: C36FieldDraftTestSupportV1.id(137_041)
            ]
        )
        let restoredCheckpoint = try fixture.activeCheckpoint.rebound(
            using: map, scope: fixture.scope,
            mutationID: try C36FieldDraftTestSupportV1.mutation(137_050)
        )
        XCTAssertEqual(restoredCheckpoint.workspaceID, targetWorkspaceID)
        XCTAssertEqual(restoredCheckpoint.state, .recoveryRequired)
        XCTAssertEqual(restoredCheckpoint.draftID, try map.draftID(fixture.draftID))
        XCTAssertEqual(Set(restoredCheckpoint.stageIDs), Set(map.stageIDs.values))
        XCTAssertNil(restoredCheckpoint.lastReceiptSHA256)

        let restoredPlan = try fixture.plan.rebound(
            using: map, planID: C36FieldDraftTestSupportV1.id(137_060),
            stageDigests: fixture.plan.stageDigests,
            expectedTargetRevision: fixture.plan.expectedTargetRevision,
            mutationID: try C36FieldDraftTestSupportV1.mutation(137_061),
            outputKeys: fixture.plan.outputKeys
        )
        let restoredPreparedSaga = try fixture.preparedSaga.rebound(
            using: map, plan: restoredPlan,
            mutationID: try C36FieldDraftTestSupportV1.mutation(137_062)
        )
        let restoredPromotedSaga = try fixture.promotedSaga.rebound(
            using: map, plan: restoredPlan,
            mutationID: try C36FieldDraftTestSupportV1.mutation(137_063)
        )
        let restoredTargetCommittedSaga = try fixture.targetCommittedSaga.rebound(
            using: map, plan: restoredPlan,
            mutationID: try C36FieldDraftTestSupportV1.mutation(137_064)
        )
        let restoredRetirePendingSaga = try fixture.retirePendingSaga.rebound(
            using: map, plan: restoredPlan,
            mutationID: try C36FieldDraftTestSupportV1.mutation(137_065)
        )
        let restoredRetiredSaga = try fixture.retiredSaga.rebound(
            using: map, plan: restoredPlan,
            mutationID: try C36FieldDraftTestSupportV1.mutation(137_066)
        )
        let restoredSagas = [
            restoredPreparedSaga, restoredPromotedSaga, restoredTargetCommittedSaga,
            restoredRetirePendingSaga, restoredRetiredSaga
        ]
        XCTAssertEqual(restoredPreparedSaga.workspaceID, targetWorkspaceID)
        XCTAssertEqual(restoredSagas.map(\.state), [
            .prepared, .contentPromotedUnbound, .targetCommitted,
            .draftRetirePending, .draftRetired
        ])
        XCTAssertTrue(restoredSagas.allSatisfy { $0.plan == restoredPlan })
        try restoredPromotedSaga.validateSuccessor(of: restoredPreparedSaga)
        try restoredTargetCommittedSaga.validateSuccessor(of: restoredPromotedSaga)
        try restoredRetirePendingSaga.validateSuccessor(of: restoredTargetCommittedSaga)
        try restoredRetiredSaga.validateSuccessor(of: restoredRetirePendingSaga)
        let restoredSagaChain = restoredSagas.map(\.sagaSHA256)

        let targetReference = try ContentReferenceV1(
            workspaceID: targetWorkspaceID.rawValue.uuidString.lowercased(),
            contentID: "c36-content-one", byteLength: 64, mediaType: "image/jpeg",
            digests: try ContentDigestSetV1([fixture.readyItem.contentDigest!]),
            byteRole: .immutableOriginal, createdAt: "2025-05-01T00:00:00.000Z"
        )
        let targetLocator = try ContentLocatorV1(
            locatorID: "c36-locator-one", workspaceID: targetWorkspaceID.rawValue.uuidString.lowercased(),
            contentID: "c36-content-one", locatorRevision: 1,
            contentDigest: fixture.readyItem.contentDigest!, expectedByteLength: 64
        )
        let restoredReservation = try fixture.reservation.rebound(
            using: map, commitPlanSHA256: restoredPlan.planSHA256,
            contentDigest: fixture.readyItem.contentDigest!, locator: targetLocator,
            mutationID: try C36FieldDraftTestSupportV1.mutation(137_067)
        )
        XCTAssertEqual(restoredReservation.workspaceID, targetWorkspaceID)
        XCTAssertEqual(restoredReservation.reconciliationState, .orphanQuarantined)
        XCTAssertEqual(restoredReservation.locator, targetLocator)
        _ = targetReference

        let restoredReceipt = try fixture.commitReceipt.rebound(
            using: map, commitPlanSHA256: restoredPlan.planSHA256,
            sagaEventSHA256Chain: restoredSagaChain,
            targetMutationID: try C36FieldDraftTestSupportV1.mutation(137_068),
            targetReceiptSHA256: C36FieldDraftTestSupportV1.digest,
            consumedStageToContentID: fixture.commitReceipt.consumedStageToContentID,
            mutationID: try C36FieldDraftTestSupportV1.mutation(137_069)
        )
        XCTAssertEqual(restoredReceipt.workspaceID, targetWorkspaceID)
        XCTAssertEqual(restoredReceipt.sagaID, try map.sagaID(fixture.retiredSaga.sagaID))
        XCTAssertEqual(restoredReceipt.sagaEventSHA256Chain, restoredSagaChain)
        try restoredReceipt.validate()

        XCTAssertEqual(corpus.singleAuthority.writerProtocol, "FieldDraftWritingV1")
        XCTAssertEqual(corpus.singleAuthority.coordinator, "FieldDraftCoordinatorV1")
        XCTAssertEqual(corpus.singleAuthority.recoveryProjection, "DraftRecoveryProjectionCoordinatorV1")
        XCTAssertEqual(corpus.singleAuthority.persistentRows, 6)
        XCTAssertFalse(corpus.singleAuthority.secondWriter)
        XCTAssertFalse(corpus.singleAuthority.secondStore)
        XCTAssertTrue(corpus.coverageAssertions.casDraftAndBaseRevision)
        XCTAssertTrue(corpus.coverageAssertions.perItemFailureIsolation)
        XCTAssertTrue(corpus.coverageAssertions.exactRetryReusesReservation)
        XCTAssertTrue(corpus.coverageAssertions.noSecondWriter)
        XCTAssertTrue(corpus.coverageAssertions.noSecondStore)
        XCTAssertTrue(corpus.coverageAssertions.noCloudStore)
        XCTAssertTrue(corpus.coverageAssertions.recordsAreCanonicalOnlyAfterCommit)
        XCTAssertTrue(corpus.terminalBundles.commitUsesAtomicWriter)
        XCTAssertTrue(corpus.terminalBundles.discardUsesAtomicWriter)
        XCTAssertTrue(corpus.terminalBundles.commitDerivesTerminalCheckpoint)
        XCTAssertTrue(corpus.terminalBundles.discardRequiresCurrentPendingCheckpoint)

        let writerProbe = C36TerminalWriterProbeV1()
        XCTAssertThrowsError(
            try writerProbe.apply(
                commitTerminalBundle: fixture.commitTerminalBundle,
                expectedDraftRevision: fixture.committingCheckpoint.draftRevision,
                expectedSagaRevision: fixture.retirePendingSaga.revision
            )
        )
        XCTAssertEqual(writerProbe.commitApplyCount, 1)
        XCTAssertEqual(writerProbe.lastCommitBundle, fixture.commitTerminalBundle)
        XCTAssertThrowsError(
            try writerProbe.apply(
                discardTerminalBundle: fixture.discardTerminalBundle,
                expectedDraftRevision: fixture.discardPendingCheckpoint.draftRevision
            )
        )
        XCTAssertEqual(writerProbe.discardApplyCount, 1)
        XCTAssertEqual(writerProbe.lastDiscardBundle, fixture.discardTerminalBundle)

        let coordinator = FieldDraftCoordinatorV1(
            registry: fixture.registry,
            writer: writerProbe,
            content: C36PromotionMapProbeV1(),
            target: C36TargetProbeV1()
        )
        do {
            _ = try await coordinator.commit(
                plan: fixture.plan,
                checkpoint: fixture.committingCheckpoint,
                items: [fixture.readyItem, fixture.alternateReadyItem],
                prepared: fixture.preparedSaga,
                contentPromoted: fixture.promotedSaga,
                targetCommitted: fixture.targetCommittedSaga,
                retirePending: fixture.retirePendingSaga,
                retired: fixture.retiredSaga,
                commitReceiptID: fixture.commitReceipt.receiptID,
                terminalCheckpointUpdatedAt: C36FieldDraftTestSupportV1.fixedDate.addingTimeInterval(10),
                rowMutationIDs: fixture.rowMutationIDs
            )
            XCTFail("the compile-probe writer must reject the non-terminal append")
        } catch {
            // The probe intentionally fails before the terminal apply; the call
            // above keeps the coordinator's complete terminal API type-checked.
        }
        XCTAssertEqual(writerProbe.commitApplyCount, 1)

        let discardWriterProbe = C36TerminalWriterProbeV1()
        let discardCoordinator = FieldDraftCoordinatorV1(
            registry: fixture.registry,
            writer: discardWriterProbe,
            content: C36PromotionMapProbeV1(),
            target: C36TargetProbeV1()
        )
        do {
            _ = try await discardCoordinator.discard(
                plan: fixture.discardPlan,
                checkpoint: fixture.discardPendingCheckpoint,
                reservations: [fixture.quarantinedReservation],
                disposedStageIDs: [fixture.failedItem.stageID],
                discardReceiptID: fixture.discardReceipt.receiptID,
                at: C36FieldDraftTestSupportV1.fixedDate.addingTimeInterval(12),
                mutationID: fixture.discardReceipt.mutationID
            )
            XCTFail("the compile-probe writer must reject the terminal discard apply")
        } catch {
            // The probe records the atomic bundle and then deliberately throws.
        }
        XCTAssertEqual(discardWriterProbe.discardApplyCount, 1)
        XCTAssertEqual(discardWriterProbe.lastDiscardBundle?.receipt, fixture.discardReceipt)

        let source = C36RecoverySourceV1(
            values: [fixture.activeCheckpoint],
            items: [fixture.draftID: [fixture.readyItem, fixture.alternateReadyItem, fixture.failedItem]],
            targetRevision: fixture.activeCheckpoint.baseCanonicalRevision + 1
        )
        let recovery = DraftRecoveryProjectionCoordinatorV1(source: source, registry: fixture.registry)
        let projection = try recovery.projections(workspaceID: fixture.workspaceID)
        XCTAssertEqual(projection.count, 1)
        XCTAssertEqual(projection[0].status, .staleTarget)
        XCTAssertEqual(projection[0].safeAction, .reviewConflict)
        XCTAssertEqual(projection[0].readyItemCount, 2)
        XCTAssertEqual(projection[0].failedItemCount, 1)
        XCTAssertEqual(projection[0].missingItemCount, 0)
    }
}

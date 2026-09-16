import Foundation
import Darwin
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private func assertStagingFailure(_ expected: DraftAttachmentStagingFailureV1,
    file: StaticString = #filePath, line: UInt = #line,
    _ operation: () async throws -> Void) async {
    do { try await operation(); XCTFail("Expected staging failure \(expected)", file: file, line: line) }
    catch { XCTAssertEqual(error as? DraftAttachmentStagingFailureV1, expected, file: file, line: line) }
}

/// Adds a finite phase and concrete error type to an otherwise unchanged
/// unexpected throw. The original error still escapes to XCTest.
private func stagingDiagnosticPhase<T>(_ phase: String,
    file: StaticString = #filePath, line: UInt = #line,
    _ operation: () throws -> T) throws -> T {
    do { return try operation() }
    catch {
        XCTFail("Unexpected staging error at \(phase): \(String(reflecting: type(of: error)))", file: file, line: line)
        throw error
    }
}

private func stagingDiagnosticPhase<T>(_ phase: String,
    file: StaticString = #filePath, line: UInt = #line,
    _ operation: () async throws -> T) async throws -> T {
    do { return try await operation() }
    catch {
        XCTFail("Unexpected staging error at \(phase): \(String(reflecting: type(of: error)))", file: file, line: line)
        throw error
    }
}

/// A controllable existing scratch boundary, not a production publication hook.
private actor C36StagingScratchGate: ScratchDataLeasePortV1 {
    let root: URL
    let entered: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Never>?
    private var resumed = false
    init(root: URL, entered: XCTestExpectation) { self.root = root; self.entered = entered }
    func acquireScratchLease(_ request: ScratchDataLeaseRequestV1) async throws -> ScratchDataLeaseV1 {
        entered.fulfill()
        if !resumed { await withCheckedContinuation { continuation = $0 } }
        try Task.checkCancellation()
        return try ScratchDataLeaseV1(request: request, relativeDirectory: request.leaseID.uuidString.lowercased())
    }
    func resume() {
        resumed = true
        continuation?.resume(); continuation = nil
    }
    func writeScratchData(_ data: Data, named: String, lease: ScratchDataLeaseV1) async throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(named)
        try data.write(to: url)
        return url
    }
    func releaseScratchLease(_ lease: ScratchDataLeaseV1, terminal: ScratchDataLeaseTerminalV1) async throws {
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }
    func recoverScratchLeases() async throws -> ScratchDataLeaseRecoverySummaryV1 {
        try .init(recoveredExpiredLeaseCount: 0, removedByteCount: 0)
    }
    func resetScratchData() async throws { resume() }
    func eraseScratchData() async throws { resume() }
}

/// Pause after the real C05 writer's durable receipt, before the adapter's
/// final manifest CAS, so a second adapter can change the staged owner.
private actor C36StagingContentGate: DraftImmutableContentWriterV1 {
    let writer: EvidenceBundleStore
    let entered: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Never>?
    private var resumed = false
    private var announcedFirstReceipt = false
    private var writerEnteredAt: UInt64?
    private var writerReturnedAt: UInt64?
    private var writerFailure: String?
    private var requests: [DraftImmutableContentWriteRequestV1] = []
    private var receipts: [DraftImmutableContentWriteReceiptV1] = []
    init(writer: EvidenceBundleStore, entered: XCTestExpectation) { self.writer = writer; self.entered = entered }
    func persistImmutableOriginal(bytes: Data, request: DraftImmutableContentWriteRequestV1)
        async throws -> DraftImmutableContentWriteReceiptV1 {
        writerEnteredAt = DispatchTime.now().uptimeNanoseconds
        let receipt: DraftImmutableContentWriteReceiptV1
        do {
            receipt = try await writer.persistImmutableOriginal(bytes: bytes, request: request)
            writerReturnedAt = DispatchTime.now().uptimeNanoseconds
        } catch {
            writerReturnedAt = DispatchTime.now().uptimeNanoseconds
            writerFailure = String(reflecting: error)
            throw error
        }
        requests.append(request); receipts.append(receipt)
        if !announcedFirstReceipt, !resumed {
            announcedFirstReceipt = true
            entered.fulfill()
        }
        try Task.checkCancellation()
        if !resumed { await withCheckedContinuation { continuation = $0 } }
        try Task.checkCancellation()
        return receipt
    }
    func resume() { resumed = true; continuation?.resume(); continuation = nil }
    func observed() -> ([DraftImmutableContentWriteRequestV1], [DraftImmutableContentWriteReceiptV1]) {
        (requests, receipts)
    }
    func reachedDurableBoundary() -> Bool { announcedFirstReceipt }
    func failureDiagnostic() -> String {
        "writerEnteredAt=\(String(describing: writerEnteredAt)) "
            + "writerReturnedAt=\(String(describing: writerReturnedAt)) "
            + "writerFailure=\(writerFailure ?? "none") receipts=\(receipts.count)"
    }
}

private enum C36PhotoReceiptFailure: Error { case savedThenLostAcknowledgement }

/// Records only real C05 results; the first acknowledgement can be lost after
/// the immutable write so a new adapter must adopt the same frozen request.
private actor C36PhotoReceiptWriter: DraftImmutableContentWriterV1 {
    let writer: EvidenceBundleStore
    private var loseAcknowledgement: Bool
    private var requests: [DraftImmutableContentWriteRequestV1] = []
    private var receipts: [DraftImmutableContentWriteReceiptV1] = []
    init(writer: EvidenceBundleStore, loseAcknowledgement: Bool) {
        self.writer = writer; self.loseAcknowledgement = loseAcknowledgement
    }
    func persistImmutableOriginal(bytes: Data, request: DraftImmutableContentWriteRequestV1)
        async throws -> DraftImmutableContentWriteReceiptV1 {
        let receipt = try await writer.persistImmutableOriginal(bytes: bytes, request: request)
        requests.append(request); receipts.append(receipt)
        if loseAcknowledgement {
            loseAcknowledgement = false
            throw C36PhotoReceiptFailure.savedThenLostAcknowledgement
        }
        return receipt
    }
    func observed() -> ([DraftImmutableContentWriteRequestV1], [DraftImmutableContentWriteReceiptV1]) {
        (requests, receipts)
    }
}

/// All authority comes from real Begin, PENDING, child and atomic raw receipts.
/// This fixture never constructs a service capability or an opaque promotion.
@MainActor
private struct C36PhotoPromotionFixture {
    let h: FrozenBeginFixture
    let adapter: DraftAttachmentStagingAdapterV1
    let service: ProductionCheckRunnerItemDraftServiceV1
    let parentID: UUID
    let childID: UUID
    let sourceBytes: Data
    let sourceURL: URL
    let raw: CheckRunnerPhotoRawReadyV1

    var rawDirectory: URL {
        h.root.appendingPathComponent("FieldEvidenceData/\(DraftAttachmentStagingAdapterV1.directoryName)")
            .appendingPathComponent(DraftAttachmentStagingAdapterV1.relativeStageDirectory(
                draftID: childID, stageID: raw.intent.stageID))
    }

    static func make(_ h: FrozenBeginFixture, writer: any DraftImmutableContentWriterV1)
        async throws -> C36PhotoPromotionFixture {
        let adapter = try DraftAttachmentStagingAdapterV1(applicationSupportURL: h.root,
            workspaceID: h.workspaceID, immutableContentWriter: writer,
            clock: { Date(timeIntervalSince1970: 2_000_000_000) })
        let service = try ProductionCheckRunnerItemDraftServiceV1(session: h.coordinator,
            progress: h.progress, coordinator: h.runner, publishedRelease: h.publishedRelease,
            clock: h.clock, ids: h.ids, attachmentStaging: adapter)
        let source = try h.captureSource()
        let initial = try service.create(source: source, preflight: .init(timeZoneID: "America/New_York",
            isTimeZoneConfirmed: true, confirmedTimeZoneID: "America/New_York",
            afterDarkAccepted: true, safePositionAccepted: true))
        let prepared = try service.prepareBegin(draftID: initial.draftID,
            expectedCheckpointSHA256: initial.checkpointSHA256,
            observedAtUTC: Date(timeIntervalSince1970: 1_789_323_456))
        let bound = try service.resumeInitialBegin(draftID: prepared.draftID)
        let parent = try CheckRunnerItemDraftCodecV1.validateCheckpoint(bound)
        let begin = try XCTUnwrap(parent.field.begin.attempt)
        h.runner.configureCapture(generationRootURL: h.session.generationRootURL)
        let bytes = try WorkCanonicalIntegrationTestSupportV1.makePNG(seed: 179)
        let childID = UUID()
        let intent = try CheckRunnerPhotoRawStageIntentV1(stageID: UUID(),
            stageMutationID: .init(rawValue: UUID()), stageCreatedAt: bound.updatedAt.addingTimeInterval(2),
            expectedSourceByteCount: Int64(bytes.count), provenanceID: "c36-photo-promotion-source",
            evidenceID: UUID(), evidenceCreatedAt: bound.updatedAt.addingTimeInterval(1))
        let proposal = try CheckRunnerPhotoDraftPayloadV1(workspaceID: h.workspaceID,
            childDraftID: childID, parentDraftID: bound.draftID, recordID: begin.recordCommand.recordID,
            assetID: source.assetID, sourceBinding: source, workflowStage: source.requestedEntry.stage,
            captureStep: .wide, purposeKey: "wide_context", origin: .humanCapture, phase: .awaitingRawStage(intent))
        _ = try service.prepareRawPhoto(parentDraftID: bound.draftID,
            expectedCheckpointSHA256: bound.checkpointSHA256, proposal: proposal)
        let sourceURL = h.root.appendingPathComponent("photo-picker-original.png")
        try bytes.write(to: sourceURL)
        let publication = try await service.publishRawPhoto(parentDraftID: bound.draftID,
            childDraftID: childID, sourceURL: sourceURL)
        guard case let .publishReadyStage(bundle) = publication.mutation.postImage,
              case let .rawReady(raw) = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(
                bundle.successorCheckpoint).phase else { throw FieldDraftFailureV1.missingReceipt }
        h.clock.value = intent.stageCreatedAt.addingTimeInterval(1)
        return .init(h: h, adapter: adapter, service: service, parentID: bound.draftID,
            childID: childID, sourceBytes: bytes, sourceURL: sourceURL, raw: raw)
    }

    func prepareCommit() async throws -> FieldDraftCheckpointV1 {
        let pair = try await service.preparePhotoPair(parentDraftID: parentID, childDraftID: childID)
        let payload = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(pair)
        let instant = pair.updatedAt.addingTimeInterval(1)
        let outputs = try [WorkspaceEntityIdentityV1(kind: .workflowRecord, id: payload.recordID).stableKey,
            WorkspaceEntityIdentityV1(kind: .evidenceFile, id: raw.intent.evidenceID).stableKey].sorted()
        let attempt = try CheckRunnerPhotoCommitAttemptV1(planID: UUID(), expectedWorkflowRecordRevision: 1,
            targetMutationID: .init(rawValue: raw.intent.evidenceID), outputKeys: outputs,
            reservationMutationID: .init(rawValue: UUID()), reservationReviewAfter: instant.addingTimeInterval(90),
            preparedSagaID: UUID(), preparedSagaMutationID: .init(rawValue: UUID()), preparedUpdatedAt: instant,
            contentPromotedSagaID: UUID(), contentPromotedSagaMutationID: .init(rawValue: UUID()),
            contentPromotedUpdatedAt: instant.addingTimeInterval(2), targetCommittedSagaID: UUID(),
            targetCommittedSagaMutationID: .init(rawValue: UUID()), targetCommittedUpdatedAt: instant.addingTimeInterval(3),
            draftRetirePendingSagaID: UUID(), draftRetirePendingSagaMutationID: .init(rawValue: UUID()),
            draftRetirePendingUpdatedAt: instant.addingTimeInterval(4), draftRetiredSagaID: UUID(),
            draftRetiredUpdatedAt: instant.addingTimeInterval(5), commitReceiptID: UUID(),
            terminalBundleMutationID: .init(rawValue: UUID()), terminalCheckpointUpdatedAt: instant.addingTimeInterval(6),
            promotionAt: instant.addingTimeInterval(1))
        h.clock.value = instant
        return try service.preparePhotoCommit(parentDraftID: parentID, childDraftID: childID,
            expectedCheckpointSHA256: pair.checkpointSHA256, proposal: attempt)
    }

    func reopened(writer: any DraftImmutableContentWriterV1) throws
        -> (DraftAttachmentStagingAdapterV1, ProductionCheckRunnerItemDraftServiceV1) {
        let adapter = try DraftAttachmentStagingAdapterV1(applicationSupportURL: h.root,
            workspaceID: h.workspaceID, immutableContentWriter: writer,
            clock: { Date(timeIntervalSince1970: 2_100_000_000) })
        let service = try ProductionCheckRunnerItemDraftServiceV1(session: h.coordinator,
            progress: h.progress, coordinator: h.runner, publishedRelease: h.publishedRelease,
            clock: h.clock, ids: h.ids, attachmentStaging: adapter)
        return (adapter, service)
    }
}

private enum C52ServiceRequestBoundary_V9_30FieldDraftResilienceTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

private final class C45FieldDraftCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityKeepsUnacceptedPlansAndResultsDerivedScratch() {
        XCTAssertEqual(Set(AssetLabelPersistenceEnrollmentV1.derivedFamilies), ["AssetLabelGenerationPlanV1", "LabelProjectionResultV1"])
        XCTAssertFalse(AssetLabelPersistenceEnrollmentV1.persistentFamilies.contains("AssetLabelGenerationPlanV1"))
        XCTAssertFalse(AssetLabelPersistenceEnrollmentV1.persistentFamilies.contains("LabelProjectionResultV1"))
    }
}

private final class C30EvidenceContextAnchorV9_30FieldDraftResilience: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

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

extension V9_30FieldDraftResilienceTests {
    func testV23P03C18DraftUpgradeKeepsExplicitVersionedPlanBoundary() throws {
        XCTAssertEqual(DraftUpgradePlanV1.schemaVersion, 1)
        XCTAssertEqual(DraftPurposeV1.inspectionReview.rawValue, "INSPECTION_REVIEW")
        XCTAssertTrue(PackageEvolutionLifecycleV1.migrationRequired)
        XCTAssertEqual(
            PackageEvolutionLifecycleV1.downgradePolicy,
            "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V17_WRITE"
        )
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
    func publish(readyStage bundle: FieldDraftStagePublicationBundleV1) throws -> MutationReceiptV1 {
        throw FieldDraftFailureV1.invalidValue
    }

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
    /// The timeout records a failure before opening a test-only rescue end.
    /// Thus a regression to blocking O_RDONLY cannot strand the suite in open.
    private func assertFIFORejected(_ expected: DraftAttachmentStagingFailureV1, at fifo: URL,
        file: StaticString = #filePath, line: UInt = #line,
        operation: @escaping @Sendable () async throws -> Void) async {
        var before = stat()
        XCTAssertEqual(lstat(fifo.path, &before), 0, file: file, line: line)
        XCTAssertEqual(before.st_mode & S_IFMT, S_IFIFO, file: file, line: line)
        let completed = expectation(description: "FIFO rejection completes without a writer")
        let task = Task.detached {
            await assertStagingFailure(expected, file: file, line: line, operation)
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 5)
        let rescue = open(fifo.path, O_RDWR | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        defer { if rescue >= 0 { close(rescue) } }
        await task.value
        var after = stat()
        XCTAssertEqual(lstat(fifo.path, &after), 0, file: file, line: line)
        XCTAssertEqual(after.st_mode & S_IFMT, S_IFIFO, file: file, line: line)
        XCTAssertEqual(after.st_dev, before.st_dev, file: file, line: line)
        XCTAssertEqual(after.st_ino, before.st_ino, file: file, line: line)
    }
    func testV23P03C37TypedPoseContractAnchor() throws {
        let axis = try PoseAxisDescriptorV1(
            axisID: PoseAxisID(rawValue: "axis.c37.anchor"),
            localizedLabelKey: "pose.c37.anchor",
            semanticRole: .otherDeclaredAxis,
            requiredComponents: .azimuthOnly,
            observationRequirement: .optional,
            applicability: .applicable
        )
        let registry = try PoseAxisDescriptorRegistryV1(descriptors: [axis])
        XCTAssertEqual(try registry.descriptor(for: axis.axisID), axis)
    }
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

    @MainActor
    private func terminalRecoveryContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: FieldDraftCheckpointRow.self,
            AttachmentStagingItemRow.self,
            DraftCommitSagaRow.self,
            DraftContentReservationRow.self,
            DraftCommitReceiptRow.self,
            DraftDiscardReceiptRow.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @MainActor
    private func insertCommitRecoveryFixture(
        _ fixture: C36FieldDraftTestSupportV1.Fixture,
        checkpoint: FieldDraftCheckpointV1,
        includeReceipt: Bool,
        into context: ModelContext
    ) throws {
        context.insert(try FieldDraftCheckpointRow(checkpoint))
        context.insert(try AttachmentStagingItemRow(fixture.committedItem))
        context.insert(try AttachmentStagingItemRow(fixture.alternateReadyItem))
        context.insert(try AttachmentStagingItemRow(fixture.failedItem))
        for saga in [
            fixture.preparedSaga,
            fixture.promotedSaga,
            fixture.targetCommittedSaga,
            fixture.retirePendingSaga,
            fixture.retiredSaga,
        ] {
            context.insert(try DraftCommitSagaRow(saga))
        }
        context.insert(try DraftContentReservationRow(fixture.reservation))
        context.insert(try DraftContentReservationRow(fixture.associatedReservation))
        if includeReceipt {
            context.insert(try DraftCommitReceiptRow(fixture.commitReceipt))
        }
        try context.save()
    }

    @MainActor
    private func insertDiscardRecoveryFixture(
        _ fixture: C36FieldDraftTestSupportV1.Fixture,
        includeReceipt: Bool,
        into context: ModelContext
    ) throws {
        context.insert(try FieldDraftCheckpointRow(fixture.discardedCheckpoint))
        context.insert(try AttachmentStagingItemRow(fixture.readyItem))
        context.insert(try AttachmentStagingItemRow(fixture.alternateReadyItem))
        context.insert(try AttachmentStagingItemRow(fixture.failedItem))
        if includeReceipt {
            context.insert(try DraftDiscardReceiptRow(fixture.discardReceipt))
        }
        try context.save()
    }

    @MainActor
    func testV23P03C36R02TerminalDraftReceiptsAreRequiredDuringRealModelRecovery() throws {
        let fixture = try fixture()

        let completeCommitContext = try terminalRecoveryContext()
        try insertCommitRecoveryFixture(
            fixture,
            checkpoint: fixture.committedCheckpoint,
            includeReceipt: true,
            into: completeCommitContext
        )
        XCTAssertNoThrow(
            try DraftCommitSagaRecoveryV1(modelContext: completeCommitContext).reconcile()
        )

        let missingCommittedCheckpointReceiptContext = try terminalRecoveryContext()
        try insertCommitRecoveryFixture(
            fixture,
            checkpoint: fixture.committedCheckpoint,
            includeReceipt: false,
            into: missingCommittedCheckpointReceiptContext
        )
        XCTAssertThrowsError(
            try DraftCommitSagaRecoveryV1(
                modelContext: missingCommittedCheckpointReceiptContext
            ).reconcile()
        ) { error in
            XCTAssertEqual(error as? FieldDraftFailureV1, .missingReceipt)
        }

        let missingRetiredSagaReceiptContext = try terminalRecoveryContext()
        try insertCommitRecoveryFixture(
            fixture,
            checkpoint: fixture.committingCheckpoint,
            includeReceipt: false,
            into: missingRetiredSagaReceiptContext
        )
        XCTAssertThrowsError(
            try DraftCommitSagaRecoveryV1(
                modelContext: missingRetiredSagaReceiptContext
            ).reconcile()
        ) { error in
            XCTAssertEqual(error as? FieldDraftFailureV1, .missingReceipt)
        }

        let completeDiscardContext = try terminalRecoveryContext()
        try insertDiscardRecoveryFixture(
            fixture,
            includeReceipt: true,
            into: completeDiscardContext
        )
        XCTAssertNoThrow(
            try DraftCommitSagaRecoveryV1(modelContext: completeDiscardContext).reconcile()
        )

        let missingDiscardReceiptContext = try terminalRecoveryContext()
        try insertDiscardRecoveryFixture(
            fixture,
            includeReceipt: false,
            into: missingDiscardReceiptContext
        )
        XCTAssertThrowsError(
            try DraftCommitSagaRecoveryV1(
                modelContext: missingDiscardReceiptContext
            ).reconcile()
        ) { error in
            XCTAssertEqual(error as? FieldDraftFailureV1, .missingReceipt)
        }
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

    func testV9_30A01AlternatePerItemStagingAndExactRetryRemainIndependent() async throws {
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

        let fm = FileManager.default
        let support = fm.temporaryDirectory.appendingPathComponent("staging-owners-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: support) }
        let first = try stagingDiagnosticPhase("A01.initialize-first") {
            try DraftAttachmentStagingAdapterV1(applicationSupportURL: support)
        }
        let second = try stagingDiagnosticPhase("A01.initialize-second") {
            try DraftAttachmentStagingAdapterV1(applicationSupportURL: support)
        }
        let bytes = Data("first owner bytes".utf8)
        let one = try await stagingDiagnosticPhase("A01.first-stage") {
            try await first.stage(data: bytes, draftID: fixture.draftID,
                workspaceID: fixture.workspaceID, attachmentKind: .file)
        }
        let secondSnapshot = try await stagingDiagnosticPhase("A01.second-read-after-first-stage") {
            try await second.entries()
        }
        XCTAssertEqual(secondSnapshot.map(\.item), [one])
        let two = try await stagingDiagnosticPhase("A01.second-stage") {
            try await second.stage(data: Data("second owner bytes".utf8), draftID: fixture.draftID,
                workspaceID: fixture.workspaceID, attachmentKind: .file)
        }
        let firstSnapshot = try await stagingDiagnosticPhase("A01.first-read-after-second-stage") {
            try await first.entries()
        }
        XCTAssertEqual(Set(firstSnapshot.map(\.item.stageID)), [one.stageID, two.stageID])
        await assertStagingFailure(.stageAlreadyExists) {
            _ = try await first.stage(data: Data("must not replace".utf8), draftID: fixture.draftID,
                workspaceID: fixture.workspaceID, attachmentKind: .file, stageID: two.stageID)
        }

        let maximum = Data(repeating: 0x53, count: FieldDraftLimitsV1.maximumPayloadBytes)
        let maximumItem = try await stagingDiagnosticPhase("A01.maximum-stage") {
            try await first.stage(data: maximum, draftID: fixture.draftID,
                workspaceID: fixture.workspaceID, attachmentKind: .file)
        }
        let maximumReadback = try await stagingDiagnosticPhase("A01.maximum-readback") {
            try await second.data(stageID: maximumItem.stageID)
        }
        XCTAssertEqual(maximumReadback, maximum)
        await assertStagingFailure(.invalidAttachment) {
            _ = try await second.stage(data: maximum + Data([0]), draftID: fixture.draftID,
                workspaceID: fixture.workspaceID, attachmentKind: .file)
        }

        // Foundation's millisecond strategy can preserve its canonical bytes
        // while changing the exact in-memory Date by one floating-point ULP.
        // Manifest publication must compare that wire truth, not Date equality.
        let nonRoundTrippingDate = Date(timeIntervalSinceReferenceDate:
            Double(bitPattern: 0x41c82d31d4461c57))
        let dateEncoder = JSONEncoder()
        dateEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        dateEncoder.dateEncodingStrategy = .millisecondsSince1970
        let originalDateBytes = try dateEncoder.encode(nonRoundTrippingDate)
        let dateDecoder = JSONDecoder()
        dateDecoder.dateDecodingStrategy = .millisecondsSince1970
        let decodedDate = try dateDecoder.decode(Date.self, from: originalDateBytes)
        XCTAssertNotEqual(decodedDate, nonRoundTrippingDate)
        XCTAssertEqual(try dateEncoder.encode(decodedDate), originalDateBytes)

        let dateSupport = fm.temporaryDirectory.appendingPathComponent(
            "staging-date-roundtrip-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: dateSupport) }
        let dateWriter = try DraftAttachmentStagingAdapterV1(applicationSupportURL: dateSupport)
        let datedItem = try await dateWriter.stage(data: Data("sub-millisecond manifest entry".utf8),
            draftID: fixture.draftID, workspaceID: fixture.workspaceID, attachmentKind: .file,
            createdAt: nonRoundTrippingDate)
        let dateManifestURL = dateSupport.appendingPathComponent(
            "FieldEvidenceData/\(DraftAttachmentStagingAdapterV1.directoryName)/manifest.json")
        let persistedManifestBytes = try Data(contentsOf: dateManifestURL)
        let dateReader = try DraftAttachmentStagingAdapterV1(applicationSupportURL: dateSupport)
        let persistedEntries = try await dateReader.entries()
        XCTAssertEqual(persistedEntries.map(\.item), [datedItem])
        XCTAssertEqual(persistedEntries.map(\.updatedAt), [decodedDate])
        let persistedManifest = try DraftAttachmentStagingManifestV1(entries: persistedEntries)
        XCTAssertEqual(try dateEncoder.encode(persistedManifest), persistedManifestBytes)

        var tamperedManifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: persistedManifestBytes) as? [String: Any])
        tamperedManifest["manifestSHA256"] = String(repeating: "0", count: 64)
        let tamperedManifestBytes = try JSONSerialization.data(
            withJSONObject: tamperedManifest, options: [.sortedKeys, .withoutEscapingSlashes])
        try tamperedManifestBytes.write(to: dateManifestURL, options: .atomic)
        try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: dateManifestURL)
        await assertStagingFailure(.corruptManifest) { _ = try await dateReader.entries() }

        let root = support.appendingPathComponent("FieldEvidenceData/\(DraftAttachmentStagingAdapterV1.directoryName)")
        let payloadURL = root.appendingPathComponent(DraftAttachmentStagingAdapterV1.relativeDataPath(
            draftID: one.draftID, stageID: one.stageID))
        let savedPayload = support.appendingPathComponent("retained-payload-for-fifo")
        let manifestURL = root.appendingPathComponent("manifest.json")
        let savedManifest = support.appendingPathComponent("retained-manifest-for-fifo")
        let manifestBeforeFIFO = try Data(contentsOf: manifestURL)
        try fm.moveItem(at: payloadURL, to: savedPayload)
        XCTAssertEqual(mkfifo(payloadURL.path, mode_t(0o600)), 0)
        await assertFIFORejected(.unsafePath, at: payloadURL) { _ = try await first.data(stageID: one.stageID) }
        let afterPayloadFIFO = try await stagingDiagnosticPhase("A01.read-after-payload-fifo") {
            try await second.entries()
        }
        XCTAssertTrue(afterPayloadFIFO.contains(where: { $0.item == one }))
        XCTAssertEqual(try Data(contentsOf: manifestURL), manifestBeforeFIFO)
        try fm.removeItem(at: payloadURL)
        try fm.moveItem(at: savedPayload, to: payloadURL)
        let payloadAfterFIFO = try await stagingDiagnosticPhase("A01.payload-fifo-recovery-read") {
            try await first.data(stageID: one.stageID)
        }
        XCTAssertEqual(payloadAfterFIFO, bytes)

        try fm.moveItem(at: manifestURL, to: savedManifest)
        XCTAssertEqual(mkfifo(manifestURL.path, mode_t(0o600)), 0)
        await assertFIFORejected(.unsafePath, at: manifestURL) { _ = try await second.entries() }
        await assertFIFORejected(.unsafePath, at: manifestURL) {
            _ = try await first.stage(data: bytes, draftID: fixture.draftID,
                workspaceID: fixture.workspaceID, attachmentKind: .file)
        }
        await assertFIFORejected(.unsafePath, at: manifestURL) {
            _ = try DraftAttachmentStagingAdapterV1(applicationSupportURL: support)
        }
        try fm.removeItem(at: manifestURL)
        try fm.moveItem(at: savedManifest, to: manifestURL)
        XCTAssertEqual(try Data(contentsOf: manifestURL), manifestBeforeFIFO)
        let afterManifestFIFO = try await stagingDiagnosticPhase("A01.manifest-fifo-recovery-read") {
            try await second.entries()
        }
        XCTAssertEqual(afterManifestFIFO, afterPayloadFIFO)
        let validAfterFIFO = try await stagingDiagnosticPhase("A01.stage-after-fifo-recovery") {
            try await first.stage(data: Data("valid after FIFO rejection".utf8),
                draftID: fixture.draftID, workspaceID: fixture.workspaceID, attachmentKind: .file)
        }
        let validAfterFIFOReadback = try await stagingDiagnosticPhase("A01.verify-after-fifo-recovery") {
            try await second.verify(stageID: validAfterFIFO.stageID)
        }
        XCTAssertEqual(validAfterFIFOReadback, validAfterFIFO)
        let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(fd, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        await assertStagingFailure(.staleStage) { _ = try await first.entries() }
        XCTAssertThrowsError(try DraftAttachmentStagingAdapterV1(applicationSupportURL: support)) {
            XCTAssertEqual($0 as? DraftAttachmentStagingFailureV1, .staleStage)
        }
        XCTAssertEqual(flock(fd, LOCK_UN), 0)

        // Unknown or divergent photo witnesses grant no generic cleanup or
        // two-MiB verification authority, even for a previously generic entry.
        let directory = root.appendingPathComponent(DraftAttachmentStagingAdapterV1.relativeStageDirectory(
            draftID: one.draftID, stageID: one.stageID))
        let witness = directory.appendingPathComponent("raw-publication.json")
        let witnessBytes = Data("unrecognized retained photo witness".utf8)
        try witnessBytes.write(to: witness)
        let before = try Data(contentsOf: root.appendingPathComponent("manifest.json"))
        await assertStagingFailure(.invalidTransition) { _ = try await second.remove(stageID: one.stageID, expectedRevision: one.revision) }
        await assertStagingFailure(.invalidTransition) { _ = try await first.quarantine(stageID: one.stageID, expectedRevision: one.revision) }
        await assertStagingFailure(.invalidTransition) { try await second.erase() }
        await assertStagingFailure(.invalidTransition) { _ = try await first.verify(stageID: one.stageID) }
        let reconciled = try await second.reconcile()
        XCTAssertEqual(reconciled.first(where: { $0.stageID == one.stageID }), one)
        XCTAssertEqual(try Data(contentsOf: witness), witnessBytes)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("payload.bin")), bytes)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("manifest.json")), before)

        // The actor must reject reentry while scratch is suspended, release R
        // across that suspension, and recheck another instance's publication.
        let entered = expectation(description: "scratch preparation entered")
        let gate = C36StagingScratchGate(root: support.appendingPathComponent("scratch"), entered: entered)
        let suspended = try DraftAttachmentStagingAdapterV1(applicationSupportURL: support, scratchStore: gate)
        let sharedStageID = UUID()
        let pending = Task {
            try await suspended.stage(data: Data("suspended capture".utf8), draftID: fixture.draftID,
                workspaceID: fixture.workspaceID, attachmentKind: .file, stageID: sharedStageID)
        }
        defer { pending.cancel(); Task { await gate.resume() } }
        await fulfillment(of: [entered], timeout: 5)
        await assertStagingFailure(.staleStage) { _ = try await suspended.entries() }
        let winnerBytes = Data("other adapter wins".utf8)
        let winner = try await second.stage(data: winnerBytes, draftID: fixture.draftID,
            workspaceID: fixture.workspaceID, attachmentKind: .file, stageID: sharedStageID)
        await gate.resume()
        await assertStagingFailure(.stageAlreadyExists) { _ = try await pending.value }
        let retainedWinner = try await suspended.data(stageID: winner.stageID)
        XCTAssertEqual(retainedWinner, winnerBytes)

        let cancelEntered = expectation(description: "cancelled preparation entered")
        let cancelGate = C36StagingScratchGate(root: support.appendingPathComponent("cancel-scratch"), entered: cancelEntered)
        let cancellable = try DraftAttachmentStagingAdapterV1(applicationSupportURL: support, scratchStore: cancelGate)
        let cancelledStageID = UUID()
        let cancelled = Task {
            try await cancellable.stage(data: bytes, draftID: fixture.draftID,
                workspaceID: fixture.workspaceID, attachmentKind: .file, stageID: cancelledStageID)
        }
        defer { cancelled.cancel(); Task { await cancelGate.resume() } }
        await fulfillment(of: [cancelEntered], timeout: 5)
        cancelled.cancel()
        await cancelGate.resume()
        await assertStagingFailure(.cancelled) { _ = try await cancelled.value }
        let afterCancellation = try await cancellable.item(stageID: cancelledStageID)
        XCTAssertNil(afterCancellation)
        let afterCancellationEntries = try await cancellable.entries()
        XCTAssertTrue(afterCancellationEntries.contains(where: { $0.item == winner }))

        try await withAsyncFrozenBeginFixture("photo-raw-retry", entry: .check,
            storedTimeZoneID: "America/New_York") { h in
            let writer = EvidenceBundleStore(generationRootURL: await h.session.generationRootURL)
            let photo = try await C36PhotoPromotionFixture.make(h, writer: writer)
            let payloadURL = await photo.rawDirectory.appendingPathComponent(DraftAttachmentStagingAdapterV1.payloadName)
            let savedURL = h.root.appendingPathComponent("retained-photo-raw")
            try fm.moveItem(at: payloadURL, to: savedURL)
            XCTAssertEqual(mkfifo(payloadURL.path, mode_t(0o600)), 0)
            try fm.removeItem(at: photo.sourceURL)
            await assertStagingFailure(.unsafePath) {
                _ = try await photo.service.preparePhotoPair(parentDraftID: photo.parentID,
                    childDraftID: photo.childID)
            }
            try fm.removeItem(at: payloadURL)
            try fm.moveItem(at: savedURL, to: payloadURL)

            var divergent = photo.sourceBytes
            divergent[divergent.startIndex] ^= 0xff
            try divergent.write(to: payloadURL, options: .atomic)
            try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: payloadURL)
            await assertStagingFailure(.digestMismatch) {
                _ = try await photo.service.preparePhotoPair(parentDraftID: photo.parentID,
                    childDraftID: photo.childID)
            }
            try photo.sourceBytes.write(to: payloadURL, options: .atomic)
            try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: payloadURL)
            let recovered = try await photo.service.preparePhotoPair(parentDraftID: photo.parentID,
                childDraftID: photo.childID)
            guard case let .pairReady(pair) = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(recovered).phase else {
                return XCTFail("expected pair-ready retry")
            }
            XCTAssertEqual(pair.raw, photo.raw)
            XCTAssertFalse(fm.fileExists(atPath: photo.sourceURL.path))
        }
    }

    func testV9_30H01HostileCodecBudgetPrivacyAndCrossWorkspaceInputsFailClosed() throws {
        let fixture = try fixture()
        let corpus = try corpus()
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

        let canonicalJSON = try XCTUnwrap(String(data: canonical, encoding: .utf8))
        let originalPayloadDigest = "\"payloadSHA256\":\"\(fixture.activeCheckpoint.payloadSHA256)\""
        let replacementDigest = fixture.activeCheckpoint.payloadSHA256 == String(repeating: "f", count: 64)
            ? String(repeating: "e", count: 64)
            : String(repeating: "f", count: 64)
        let payloadDigestRange = try XCTUnwrap(canonicalJSON.range(of: originalPayloadDigest))
        let semanticTamperJSON = canonicalJSON.replacingCharacters(
            in: payloadDigestRange,
            with: "\"payloadSHA256\":\"\(replacementDigest)\""
        )
        let semanticTamper = try XCTUnwrap(semanticTamperJSON.data(using: .utf8))
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: semanticTamper))
        XCTAssertThrowsError(
            try FieldDraftCanonicalCodecV1.decode(FieldDraftCheckpointV1.self, from: semanticTamper)
        ) { error in
            XCTAssertEqual(error as? FieldDraftFailureV1, .digestMismatch)
        }

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

        try await withAsyncFrozenBeginFixture("photo-manifest-race", entry: .check,
            storedTimeZoneID: "America/New_York") { h in
            let entered = expectation(description: "photo C05 write completed before manifest publication")
            let gate = C36StagingContentGate(
                writer: EvidenceBundleStore(generationRootURL: await h.session.generationRootURL), entered: entered)
            let photo = try await C36PhotoPromotionFixture.make(h, writer: gate)
            _ = try await photo.prepareCommit()
            let pending = Task {
                try await photo.service.resumePhotoCommit(parentDraftID: photo.parentID,
                    childDraftID: photo.childID)
            }
            defer { pending.cancel(); Task { await gate.resume() } }
            await fulfillment(of: [entered], timeout: 10)
            guard await gate.reachedDurableBoundary() else {
                pending.cancel()
                await gate.resume()
                _ = try? await pending.value
                return XCTFail("The unchanged timeout must not permit a manifest race before the real durable receipt")
            }
            let competitor = try DraftAttachmentStagingAdapterV1(applicationSupportURL: h.root,
                workspaceID: await h.workspaceID)
            let retained = try await competitor.stage(data: Data("unrelated manifest winner".utf8),
                draftID: UUID(), workspaceID: h.workspaceID, attachmentKind: .file)
            await gate.resume()
            await assertStagingFailure(.staleStage) { _ = try await pending.value }
            let retainedBytes = try await competitor.data(stageID: retained.stageID)
            XCTAssertEqual(retainedBytes, Data("unrelated manifest winner".utf8))

            let (reopenedAdapter, reopenedService) = try await photo.reopened(
                writer: EvidenceBundleStore(generationRootURL: h.session.generationRootURL))
            let completed = try await reopenedService.resumePhotoCommit(parentDraftID: photo.parentID,
                childDraftID: photo.childID)
            XCTAssertEqual(completed.state, .committed)
            let reopenedBytes = try await reopenedAdapter.data(stageID: retained.stageID)
            XCTAssertEqual(reopenedBytes, Data("unrelated manifest winner".utf8))
        }
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
        let quarantinePredecessor = try DraftContentReservationV1(
            reservationID: fixture.quarantinedReservation.reservationID,
            workspaceID: fixture.quarantinedReservation.workspaceID,
            draftID: fixture.quarantinedReservation.draftID,
            stageID: fixture.quarantinedReservation.stageID,
            commitPlanSHA256: fixture.quarantinedReservation.commitPlanSHA256,
            mutationID: fixture.reservation.mutationID,
            contentDigest: fixture.quarantinedReservation.contentDigest,
            locator: fixture.quarantinedReservation.locator,
            createdAt: fixture.quarantinedReservation.createdAt,
            reviewAfter: fixture.quarantinedReservation.reviewAfter,
            reconciliationState: .reserved,
            revision: 1
        )
        try fixture.quarantinedReservation.validateSuccessor(of: quarantinePredecessor)
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

        let fm = FileManager.default
        let support = fm.temporaryDirectory.appendingPathComponent("staging-promotion-cas-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: support) }
        let generation = support.appendingPathComponent("FieldEvidenceData/generations/\(UUID().uuidString.lowercased())")
        try fm.createDirectory(at: generation, withIntermediateDirectories: true)
        try ProtectedFilePolicyV1.applyAndVerify(.durableDirectory, at: generation)
        let entered = expectation(description: "real immutable writer completed")
        let gate = C36StagingContentGate(writer: EvidenceBundleStore(generationRootURL: generation), entered: entered)
        let staging = try DraftAttachmentStagingAdapterV1(applicationSupportURL: support,
            immutableContentWriter: gate)
        let competitor = try DraftAttachmentStagingAdapterV1(applicationSupportURL: support)
        let staged = try await staging.stage(data: Data("content reservation survives owner change".utf8),
            draftID: fixture.draftID, workspaceID: fixture.workspaceID, attachmentKind: .file)
        let plan = try DraftCommitPlanV1(planID: UUID(), workspaceID: fixture.workspaceID,
            draftID: fixture.draftID, draftRevision: fixture.plan.draftRevision,
            baseCanonicalRevision: fixture.plan.baseCanonicalRevision, payloadSHA256: fixture.plan.payloadSHA256,
            stageDigests: [staged.stageSHA256], targetCommandKind: fixture.plan.targetCommandKind,
            expectedTargetRevision: fixture.plan.expectedTargetRevision,
            mutationID: MutationIDV1(rawValue: UUID()), outputKeys: fixture.plan.outputKeys)
        let reservationMutation = try MutationIDV1(rawValue: UUID())
        let promotion = Task {
            try await staging.promote(plan: plan, items: [staged],
                reservationMutationIDs: [staged.stageID: reservationMutation])
        }
        defer { promotion.cancel(); Task { await gate.resume() } }
        await fulfillment(of: [entered], timeout: 10)
        guard await gate.reachedDurableBoundary() else {
            promotion.cancel()
            await gate.resume()
            _ = try? await promotion.value
            return XCTFail("The unchanged timeout must not permit quarantine before the real durable receipt")
        }
        await assertStagingFailure(.staleStage) { _ = try await staging.entries() }
        let quarantined = try await competitor.quarantine(stageID: staged.stageID, expectedRevision: staged.revision)
        await gate.resume()
        await assertStagingFailure(.staleStage) { _ = try await promotion.value }
        let afterPromotion = try await staging.item(stageID: staged.stageID)
        XCTAssertEqual(afterPromotion, quarantined)
        XCTAssertEqual(afterPromotion?.state, .orphanQuarantined)
        let quarantineBytes = try await staging.data(stageID: staged.stageID)
        XCTAssertEqual(quarantineBytes, Data("content reservation survives owner change".utf8))

        try await withAsyncFrozenBeginFixture("photo-c05-lost-ack", entry: .check,
            storedTimeZoneID: "America/New_York") { h in
            let writer = C36PhotoReceiptWriter(
                writer: EvidenceBundleStore(generationRootURL: h.session.generationRootURL),
                loseAcknowledgement: true)
            let photo = try await C36PhotoPromotionFixture.make(h, writer: writer)
            let committing = try await photo.prepareCommit()
            do {
                _ = try await photo.service.resumePhotoCommit(parentDraftID: photo.parentID,
                    childDraftID: photo.childID)
                XCTFail("expected lost C05 acknowledgement")
            } catch {
                XCTAssertEqual(error as? C36PhotoReceiptFailure, .savedThenLostAcknowledgement)
            }
            let first = await writer.observed()
            XCTAssertEqual(first.0.count, 1)
            XCTAssertEqual(first.1.count, 1)
            XCTAssertFalse(try XCTUnwrap(first.1.first).reusedExistingBytes)
            XCTAssertTrue(try h.context.fetch(FetchDescriptor<DraftContentReservationRow>()).isEmpty)

            h.clock.value = h.clock.value.addingTimeInterval(50_000)
            let (_, reopenedService) = try photo.reopened(writer: writer)
            let completed = try await reopenedService.resumePhotoCommit(parentDraftID: photo.parentID,
                childDraftID: photo.childID)
            XCTAssertEqual(completed.state, .committed)
            let observed = await writer.observed()
            XCTAssertEqual(observed.0.count, 2)
            XCTAssertEqual(observed.0[0], observed.0[1])
            XCTAssertEqual(observed.1.map(\.reusedExistingBytes), [false, true])
            let reconstruction = try CheckRunnerPhotoDraftCodecV1.reconstructPhotoCommit(from: committing)
            guard case let .preparedCommit(_, attempt) = try CheckRunnerPhotoDraftCodecV1
                .validateCheckpoint(committing).phase else { return XCTFail("expected frozen attempt") }
            let expected = try CheckRunnerPhotoContinuationEvidenceV1.reservation(raw: photo.raw,
                plan: reconstruction.draftCommit.plan, attempt: attempt)
            let reservations = try h.context.fetch(FetchDescriptor<DraftContentReservationRow>())
                .map { try $0.value() }
            XCTAssertEqual(reservations, [expected])
            XCTAssertEqual(expected.createdAt, attempt.promotionAt)
            XCTAssertEqual(expected.reviewAfter, attempt.reservationReviewAfter)
        }
    }
}

extension V9_30FieldDraftResilienceTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}
private final class C31LightingAnchorV930FieldDraftResilienceTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

private final class C33TemporalEvidenceAnchorV930FieldDraftResilience: XCTestCase {
    func testC33V930FieldDraftResilienceCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "draft.temporal-scratch-promotion",
            kind: .audio,
            reportProjection: .typedLinkWithDerivativePreview
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "draft.temporal-scratch-promotion",
            kind: .audio,
            reportProjection: .typedLinkWithDerivativePreview
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

private final class C32AssistanceAnchorV930FieldDraftResilience: XCTestCase {
    func testC32V930FieldDraftResilienceCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .fieldDraftCheckpoint,
            fieldID: "draft.preserve-user-text",
            value: .text("user-entered draft survives")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .fieldDraftCheckpoint,
            fieldID: "draft.preserve-user-text",
            valueKind: .text
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
private final class C46V930DraftCompatibilityTests: XCTestCase {
    func testC46DraftScratchCannotBecomeOperationalContact() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "field-draft",
            kind: .phone,
            handoff: .text,
            slot: 46030
        )
    }
}

extension V9_30FieldDraftResilienceTests {
    func testV23P03C34DraftResumeAnchorIsTypedAndFailClosedAtBounds() throws {
        let anchor = try DraftResumeAnchorV1(
            sectionID: "draft.section",
            fieldID: "draft.field",
            selectedStableID: "draft.selection",
            boundedPosition: 100_000
        )
        XCTAssertEqual(anchor.sectionID, "draft.section")
        XCTAssertEqual(anchor.fieldID, "draft.field")
        XCTAssertEqual(anchor.boundedPosition, 100_000)
        XCTAssertThrowsError(
            try DraftResumeAnchorV1(
                sectionID: "draft.section",
                fieldID: "draft.field",
                boundedPosition: 100_001
            )
        )
    }
}


extension V9_30FieldDraftResilienceTests {
    @MainActor
    func testRestoreInitializationMatchesActorPublicationAndReopensExactBytes() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("draft-publication-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let sourceSupport = root.appendingPathComponent("source")
        let actorSupport = root.appendingPathComponent("actor")
        let synchronousSupport = root.appendingPathComponent("synchronous")
        let workspace = WorkspaceID(rawValue: UUID())
        let draftID = UUID(), restoreID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let source = try DraftAttachmentStagingAdapterV1(
            applicationSupportURL: sourceSupport, workspaceID: workspace, clock: { now }
        )
        let firstBytes = Data("first restored attachment".utf8)
        let secondBytes = Data([0, 1, 2, 3, 0xff, 0x80])
        let first = try await source.stage(data: firstBytes, draftID: draftID,
            workspaceID: workspace, attachmentKind: .file)
        let second = try await source.stage(data: secondBytes, draftID: draftID,
            workspaceID: workspace, attachmentKind: .file)
        let entries = try await source.entries()
        let manifest = try DraftAttachmentStagingManifestV1(entries: entries)
        let sourceRoot = sourceSupport.appendingPathComponent(
            "FieldEvidenceData/\(DraftAttachmentStagingAdapterV1.directoryName)"
        )
        let actor = try DraftAttachmentStagingAdapterV1(
            applicationSupportURL: actorSupport, workspaceID: workspace, clock: { now }
        )
        let actorReceipt = try await actor.adoptRestoredStaging(from: sourceRoot,
            entries: entries, workspaceID: workspace,
            sourceManifestSHA256: manifest.manifestSHA256, restoreID: restoreID)
        let synchronousReceipt = try DraftAttachmentStagingAdapterV1.publishRestoredStagingSynchronously(
            applicationSupportURL: synchronousSupport, from: sourceRoot,
            entries: entries, workspaceID: workspace,
            sourceManifestSHA256: manifest.manifestSHA256, restoreID: restoreID, clock: { now })
        try actorReceipt.validate()
        try synchronousReceipt.validate()
        XCTAssertEqual(actorReceipt, synchronousReceipt)
        XCTAssertEqual(Set(synchronousReceipt.adoptedStageIDs), [first.stageID, second.stageID])
        XCTAssertTrue(synchronousReceipt.reusedStageIDs.isEmpty)
        XCTAssertFalse(synchronousReceipt.atomicAcrossRoots)
        XCTAssertTrue(synchronousReceipt.canonicalCommitRequired)
        let relativeManifest = "FieldEvidenceData/\(DraftAttachmentStagingAdapterV1.directoryName)/manifest.json"
        XCTAssertEqual(try Data(contentsOf: actorSupport.appendingPathComponent(relativeManifest)),
            try Data(contentsOf: synchronousSupport.appendingPathComponent(relativeManifest)))
        // Reconstruct the ordinary actor from the actual persisted manifest.
        let reopened = try DraftAttachmentStagingAdapterV1(
            applicationSupportURL: synchronousSupport, workspaceID: workspace, clock: { now }
        )
        let reopenedEntries = try await reopened.entries()
        let reopenedFirst = try await reopened.data(stageID: first.stageID)
        let reopenedSecond = try await reopened.data(stageID: second.stageID)
        XCTAssertEqual(reopenedEntries, entries)
        XCTAssertEqual(reopenedFirst, firstBytes)
        XCTAssertEqual(reopenedSecond, secondBytes)
        XCTAssertEqual(reopenedEntries.map(\.item.workspaceID), [workspace, workspace])
        let actorReplay = try await reopened.adoptRestoredStaging(from: sourceRoot,
            entries: entries, workspaceID: workspace,
            sourceManifestSHA256: manifest.manifestSHA256, restoreID: restoreID)
        let synchronousReplay = try DraftAttachmentStagingAdapterV1.publishRestoredStagingSynchronously(
            applicationSupportURL: actorSupport, from: sourceRoot,
            entries: entries, workspaceID: workspace,
            sourceManifestSHA256: manifest.manifestSHA256, restoreID: restoreID, clock: { now })
        XCTAssertEqual(actorReplay, synchronousReplay)
        XCTAssertTrue(actorReplay.adoptedStageIDs.isEmpty)
        XCTAssertEqual(Set(actorReplay.reusedStageIDs), [first.stageID, second.stageID])
        let verifiedFirst = try await reopened.verify(stageID: first.stageID)
        let verifiedSecond = try await reopened.verify(stageID: second.stageID)
        XCTAssertEqual(verifiedFirst, first)
        XCTAssertEqual(verifiedSecond, second)

        // The original actor's cached manifest predates this independent
        // mutation. Restore must preserve the new entry when it adopts/reuses.
        let companion = try DraftAttachmentStagingAdapterV1(applicationSupportURL: actorSupport,
            workspaceID: workspace, clock: { now })
        let companionBytes = Data("unrelated newer owner entry".utf8)
        let companionItem = try await companion.stage(data: companionBytes, draftID: UUID(),
            workspaceID: workspace, attachmentKind: .file)
        _ = try await actor.adoptRestoredStaging(from: sourceRoot, entries: entries,
            workspaceID: workspace, sourceManifestSHA256: manifest.manifestSHA256, restoreID: restoreID)
        let afterCompanion = try await actor.entries()
        XCTAssertEqual(Set(afterCompanion.map(\.item.stageID)), [first.stageID, second.stageID, companionItem.stageID])
        let companionReadback = try await actor.data(stageID: companionItem.stageID)
        XCTAssertEqual(companionReadback, companionBytes)

        try await withAsyncFrozenBeginFixture("photo-witness-race", entry: .check,
            storedTimeZoneID: "America/New_York") { h in
            let entered = expectation(description: "photo C05 bytes durable before witness replacement")
            let gate = C36StagingContentGate(
                writer: EvidenceBundleStore(generationRootURL: h.session.generationRootURL), entered: entered)
            let photo = try await C36PhotoPromotionFixture.make(h, writer: gate)
            _ = try await photo.prepareCommit()
            let witnessURL = photo.rawDirectory.appendingPathComponent("raw-publication.json")
            let witness = try Data(contentsOf: witnessURL)
            let resumeStartedAt = DispatchTime.now().uptimeNanoseconds
            var commitTrace: [String] = []
            photo.service.photoCommitObservationForTesting = { phase in
                commitTrace.append("\(phase)@\(DispatchTime.now().uptimeNanoseconds)")
            }
            defer { photo.service.photoCommitObservationForTesting = nil }
            var pendingFailure: String?
            let pending = Task {
                do {
                    return try await photo.service.resumePhotoCommit(parentDraftID: photo.parentID,
                        childDraftID: photo.childID)
                } catch {
                    pendingFailure = String(reflecting: error)
                    throw error
                }
            }
            defer { pending.cancel(); Task { await gate.resume() } }
            await fulfillment(of: [entered], timeout: 10)
            guard await gate.reachedDurableBoundary() else {
                let beforeCancellation = pendingFailure ?? "none"
                let writerDiagnostic = await gate.failureDiagnostic()
                let observedAt = DispatchTime.now().uptimeNanoseconds
                let prewriteTraceBeforeCancellation = commitTrace.joined(separator: ",")
                pending.cancel()
                await gate.resume()
                _ = try? await pending.value
                return XCTFail("The unchanged timeout must not permit witness replacement before the real durable receipt; "
                    + "resumeStartedAt=\(resumeStartedAt) observedAt=\(observedAt) "
                    + "pendingFailureBeforeCancellation=\(beforeCancellation) \(writerDiagnostic) "
                    + "prewriteTraceBeforeCancellation=\(prewriteTraceBeforeCancellation)")
            }
            try Data("replaced witness".utf8).write(to: witnessURL, options: .atomic)
            try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: witnessURL)
            await gate.resume()
            await assertStagingFailure(.staleStage) { _ = try await pending.value }
            let first = await gate.observed()
            XCTAssertEqual(first.0.count, 1)
            XCTAssertEqual(first.1.map(\.reusedExistingBytes), [false])
            let request = try XCTUnwrap(first.0.first)
            let immutableURL = h.session.generationRootURL.appendingPathComponent(request.relativePath)
            XCTAssertEqual(try Data(contentsOf: immutableURL), photo.sourceBytes)
            XCTAssertTrue(try h.context.fetch(FetchDescriptor<EvidenceFile>())
                .filter { $0.id == photo.raw.intent.evidenceID }.isEmpty)

            try witness.write(to: witnessURL, options: .atomic)
            try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: witnessURL)
            let (_, reopenedService) = try photo.reopened(writer: gate)
            let completed = try await reopenedService.resumePhotoCommit(parentDraftID: photo.parentID,
                childDraftID: photo.childID)
            XCTAssertEqual(completed.state, .committed)
            let retried = await gate.observed()
            XCTAssertEqual(retried.0, [request, request])
            XCTAssertEqual(retried.1.map(\.reusedExistingBytes), [false, true])
            XCTAssertEqual(try h.context.fetch(FetchDescriptor<EvidenceFile>())
                .filter { $0.id == photo.raw.intent.evidenceID }.count, 1)
        }
    }

    @MainActor
    func testRestoreInitializationRejectsHostileInputsWithoutPublishingEntries() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("draft-publication-hostile-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        var hostileRestorePhase = "hostile-restore.setup-source"
        do {
        let sourceSupport = root.appendingPathComponent("source")
        let workspace = WorkspaceID(rawValue: UUID())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let source = try DraftAttachmentStagingAdapterV1(
            applicationSupportURL: sourceSupport, clock: { now }
        )
        let bytes = Data("retained source attachment".utf8)
        let item = try await source.stage(data: bytes, draftID: UUID(),
            workspaceID: workspace, attachmentKind: .file)
        _ = try await source.stage(data: Data("another workspace".utf8), draftID: UUID(),
            workspaceID: WorkspaceID(rawValue: UUID()), attachmentKind: .file)
        let mixedEntries = try await source.entries()
        let entries = mixedEntries.filter { $0.item.stageID == item.stageID }
        let manifest = try DraftAttachmentStagingManifestV1(entries: entries)
        let mixedManifest = try DraftAttachmentStagingManifestV1(entries: mixedEntries)
        let sourceRoot = sourceSupport.appendingPathComponent(
            "FieldEvidenceData/\(DraftAttachmentStagingAdapterV1.directoryName)"
        )
        let sourceURL = sourceRoot.appendingPathComponent(try XCTUnwrap(entries.first).relativeDataPath)
        let witnessURL = sourceURL.deletingLastPathComponent().appendingPathComponent("raw-publication.json")
        let cases: [(String, WorkspaceID, [DraftAttachmentStagingEntryV1], String, DraftAttachmentStagingFailureV1)] = [
            ("manifest", workspace, entries, String(repeating: "0", count: 64), .digestMismatch),
            ("workspace", WorkspaceID(rawValue: UUID()), entries, manifest.manifestSHA256, .wrongWorkspace),
            ("mixed-workspaces", workspace, mixedEntries, mixedManifest.manifestSHA256, .wrongWorkspace),
            ("tampered", workspace, entries, manifest.manifestSHA256, .digestMismatch),
            ("missing", workspace, entries, manifest.manifestSHA256, .stageNotFound),
            ("photo-witness", workspace, entries, manifest.manifestSHA256, .invalidTransition),
        ]
        for (name, targetWorkspace, candidateEntries, digest, expected) in cases {
            hostileRestorePhase = "hostile-restore.\(name).arrange"
            try bytes.write(to: sourceURL, options: .atomic)
            if fm.fileExists(atPath: witnessURL.path) { try fm.removeItem(at: witnessURL) }
            if name == "tampered" { try Data(repeating: 0x78, count: bytes.count).write(to: sourceURL) }
            if name == "missing" { try fm.removeItem(at: sourceURL) }
            if name == "photo-witness" { try Data("unknown photo owner".utf8).write(to: witnessURL) }
            let support = root.appendingPathComponent(name)
            hostileRestorePhase = "hostile-restore.\(name).publish"
            XCTAssertThrowsError(try DraftAttachmentStagingAdapterV1.publishRestoredStagingSynchronously(
                applicationSupportURL: support, from: sourceRoot, entries: candidateEntries,
                workspaceID: targetWorkspace, sourceManifestSHA256: digest,
                restoreID: UUID(), clock: { now })) { error in
                XCTAssertEqual(error as? DraftAttachmentStagingFailureV1, expected, name)
            }
            hostileRestorePhase = "hostile-restore.\(name).reopen"
            let reopened = try DraftAttachmentStagingAdapterV1(
                applicationSupportURL: support, workspaceID: targetWorkspace
            )
            hostileRestorePhase = "hostile-restore.\(name).read-empty"
            let retained = try await reopened.entries()
            XCTAssertTrue(retained.isEmpty, name)
            let destination = support.appendingPathComponent(
                "FieldEvidenceData/\(DraftAttachmentStagingAdapterV1.directoryName)/"
                    + DraftAttachmentStagingAdapterV1.relativeDataPath(draftID: item.draftID, stageID: item.stageID)
            )
            XCTAssertFalse(fm.fileExists(atPath: destination.path), name)
        }
        hostileRestorePhase = "hostile-restore.fifo-arrange"
        try fm.removeItem(at: witnessURL)
        try bytes.write(to: sourceURL, options: .atomic)
        let sourceAfter = try Data(contentsOf: sourceURL)
        XCTAssertEqual(sourceAfter, bytes)

        let retainedSource = root.appendingPathComponent("retained-restore-source-for-fifo")
        try fm.moveItem(at: sourceURL, to: retainedSource)
        XCTAssertEqual(mkfifo(sourceURL.path, mode_t(0o600)), 0)
        let fifoSupport = root.appendingPathComponent("fifo-restore")
        hostileRestorePhase = "hostile-restore.fifo-initialize"
        let fifoDestination = try DraftAttachmentStagingAdapterV1(applicationSupportURL: fifoSupport)
        hostileRestorePhase = "hostile-restore.fifo-actor-reject"
        await assertFIFORejected(.unsafePath, at: sourceURL) {
            _ = try await fifoDestination.adoptRestoredStaging(from: sourceRoot, entries: entries,
                workspaceID: workspace, sourceManifestSHA256: manifest.manifestSHA256, restoreID: UUID())
        }
        hostileRestorePhase = "hostile-restore.fifo-sync-reject"
        await assertFIFORejected(.unsafePath, at: sourceURL) {
            _ = try DraftAttachmentStagingAdapterV1.publishRestoredStagingSynchronously(
                applicationSupportURL: fifoSupport, from: sourceRoot, entries: entries,
                workspaceID: workspace, sourceManifestSHA256: manifest.manifestSHA256, restoreID: UUID())
        }
        hostileRestorePhase = "hostile-restore.fifo-read-empty"
        let afterFIFOFailure = try await fifoDestination.entries()
        XCTAssertTrue(afterFIFOFailure.isEmpty)
        try fm.removeItem(at: sourceURL)
        try fm.moveItem(at: retainedSource, to: sourceURL)
        hostileRestorePhase = "hostile-restore.fifo-recover"
        let fifoRecovery = try await fifoDestination.adoptRestoredStaging(from: sourceRoot, entries: entries,
            workspaceID: workspace, sourceManifestSHA256: manifest.manifestSHA256, restoreID: UUID())
        XCTAssertEqual(fifoRecovery.adoptedStageIDs, [item.stageID])
        let fifoRecoveryBytes = try await fifoDestination.data(stageID: item.stageID)
        XCTAssertEqual(fifoRecoveryBytes, bytes)

        hostileRestorePhase = "hostile-restore.occupied-arrange"
        let occupiedSupport = root.appendingPathComponent("occupied")
        let occupied = try DraftAttachmentStagingAdapterV1(applicationSupportURL: occupiedSupport)
        let occupiedRoot = occupiedSupport.appendingPathComponent(
            "FieldEvidenceData/\(DraftAttachmentStagingAdapterV1.directoryName)")
        let foreignDirectory = occupiedRoot.appendingPathComponent(
            DraftAttachmentStagingAdapterV1.relativeStageDirectory(draftID: item.draftID, stageID: item.stageID))
        try fm.createDirectory(at: foreignDirectory, withIntermediateDirectories: true)
        let foreignPayload = foreignDirectory.appendingPathComponent("payload.bin")
        let foreignBytes = Data("unindexed foreign publication".utf8)
        try foreignBytes.write(to: foreignPayload)
        hostileRestorePhase = "hostile-restore.occupied-reject"
        await assertStagingFailure(.staleStage) {
            _ = try await occupied.adoptRestoredStaging(from: sourceRoot, entries: entries,
                workspaceID: workspace, sourceManifestSHA256: manifest.manifestSHA256, restoreID: UUID())
        }
        XCTAssertEqual(try Data(contentsOf: foreignPayload), foreignBytes)
        let occupiedEntries = try await occupied.entries()
        XCTAssertTrue(occupiedEntries.isEmpty)

        hostileRestorePhase = "hostile-restore.old-owner-arrange"
        let moved = root.appendingPathComponent("retained-old-owner")
        try fm.moveItem(at: occupiedRoot, to: moved)
        let replacement = try DraftAttachmentStagingAdapterV1(applicationSupportURL: occupiedSupport)
        hostileRestorePhase = "hostile-restore.old-owner-reject"
        await assertStagingFailure(.staleStage) { _ = try await occupied.entries() }
        await assertStagingFailure(.staleStage) { try await occupied.erase() }
        let replacementEntries = try await replacement.entries()
        XCTAssertTrue(replacementEntries.isEmpty)
        XCTAssertEqual(try Data(contentsOf: moved.appendingPathComponent(
            DraftAttachmentStagingAdapterV1.relativeDataPath(draftID: item.draftID, stageID: item.stageID))), foreignBytes)
        } catch {
            XCTFail("Unexpected staging error at \(hostileRestorePhase): \(String(reflecting: type(of: error)))")
            throw error
        }
    }
}

extension V9_30FieldDraftResilienceTests {
    func testV23ReviewedConflictTargetBasisRetainsOnlyExactTargetOrAbsenceLock() throws {
        let workspace = WorkspaceID(rawValue: UUID())
        let key = try MyDayKeyV1(
            workspaceID: workspace,
            civilDate: .init(year: 2026, month: 9, day: 12),
            ianaTimeZoneIdentifier: "UTC"
        )
        let identity = try WorkspaceEntityIdentityV1(kind: .myDayPlan, id: UUID())
        let digest = String(repeating: "a", count: 64)
        let existing = ReviewedMyDayTargetBasisV1.existing(
            identity: identity, key: key, revision: 7, canonicalSHA256: digest
        )
        let absent = ReviewedMyDayTargetBasisV1.absent(key: key, expectedWorkspaceRevision: 0)
        XCTAssertNoThrow(try existing.validate())
        XCTAssertNoThrow(try absent.validate())
        XCTAssertEqual(existing.key, key)
        XCTAssertEqual(existing.targetRevision, 7)
        XCTAssertEqual(existing.existingIdentity, identity)
        XCTAssertNil(existing.expectedWorkspaceRevision)
        XCTAssertEqual(absent.targetRevision, 0)
        XCTAssertNil(absent.existingIdentity)
        XCTAssertEqual(absent.expectedWorkspaceRevision, 0)
        XCTAssertTrue(FieldDraftCheckpointV1.permits(.active, .conflicted))
        XCTAssertTrue(FieldDraftCheckpointV1.permits(.recoveryRequired, .conflicted))
        XCTAssertFalse(FieldDraftCheckpointV1.permits(.discarded, .conflicted))
    }
}
extension V9_30FieldDraftResilienceTests {
    func testV23ReviewedConflictResolutionBindsFullMyDayCheckpointsAndTargetLocks() throws {
        let fixture = try V23ReviewedConflictDomainFixture.make()
        let existing = try ReviewedDraftConflictResolutionV1(
            plan: .reviewAndRebase, expectedCheckpoint: fixture.expected,
            reviewedTargetBasis: .existing(identity: fixture.targetIdentity, key: fixture.key,
                                           revision: fixture.target.revision, canonicalSHA256: fixture.target.planSHA256),
            successorCheckpoint: fixture.existingSuccessor
        )
        let absent = try ReviewedDraftConflictResolutionV1(
            plan: .reviewAndRebase, expectedCheckpoint: fixture.expected,
            reviewedTargetBasis: .absent(key: fixture.key, expectedWorkspaceRevision: 0),
            successorCheckpoint: fixture.absentSuccessor
        )
        XCTAssertEqual(try FieldDraftCanonicalCodecV1.decode(ReviewedDraftConflictResolutionV1.self,
            from: FieldDraftCanonicalCodecV1.encode(existing)), existing)
        XCTAssertEqual(try FieldDraftCanonicalCodecV1.decode(ReviewedDraftConflictResolutionV1.self,
            from: FieldDraftCanonicalCodecV1.encode(absent)), absent)
        XCTAssertThrowsError(try fixture.existingSuccessor.validateSuccessor(
            of: fixture.expected, expectedDraftRevision: fixture.expected.draftRevision,
            expectedBaseRevision: fixture.expected.baseCanonicalRevision
        ))

        XCTAssertThrowsError(try ReviewedDraftConflictResolutionV1(
            plan: .reviewAndRebase, expectedCheckpoint: fixture.expected,
            reviewedTargetBasis: .existing(identity: fixture.targetIdentity, key: fixture.key,
                                           revision: fixture.target.revision, canonicalSHA256: fixture.target.planSHA256),
            successorCheckpoint: fixture.absentSuccessor
        ))
        let foreignKey = try MyDayKeyV1(workspaceID: fixture.key.workspaceID,
            civilDate: .init(year: 2026, month: 9, day: 13), ianaTimeZoneIdentifier: "UTC")
        XCTAssertThrowsError(try ReviewedDraftConflictResolutionV1(
            plan: .reviewAndRebase, expectedCheckpoint: fixture.expected,
            reviewedTargetBasis: .absent(key: foreignKey, expectedWorkspaceRevision: 0),
            successorCheckpoint: fixture.absentSuccessor
        ))
        XCTAssertThrowsError(try ReviewedMyDayTargetBasisV1.existing(
            identity: try .init(kind: .serviceRequestRecord, id: UUID()), key: fixture.key,
            revision: fixture.target.revision, canonicalSHA256: fixture.target.planSHA256
        ).validate())
        let submillisecond = try fixture.checkpoint(payload: fixture.existingPayload,
            base: fixture.target.revision, revision: 2, state: .active,
            mutation: UUID(), at: fixture.now.addingTimeInterval(0.0005))
        XCTAssertThrowsError(try ReviewedDraftConflictResolutionV1(
            plan: .reviewAndRebase, expectedCheckpoint: fixture.expected,
            reviewedTargetBasis: .existing(identity: fixture.targetIdentity, key: fixture.key,
                                           revision: fixture.target.revision, canonicalSHA256: fixture.target.planSHA256),
            successorCheckpoint: submillisecond
        ))
        let prepared = try fixture.preparedConflict()
        XCTAssertThrowsError(try ReviewedDraftConflictResolutionV1(
            plan: .reviewAndRebase, expectedCheckpoint: prepared.expected,
            reviewedTargetBasis: .existing(identity: fixture.targetIdentity, key: fixture.key,
                                           revision: fixture.target.revision, canonicalSHA256: fixture.target.planSHA256),
            successorCheckpoint: prepared.successor
        ))
        for predecessor in try fixture.sameKeyRevisionSubstitutions() {
            let successor = try fixture.successor(payload: try fixture.planPayload(predecessor: predecessor))
            XCTAssertThrowsError(try ReviewedDraftConflictResolutionV1(plan: .reviewAndRebase, expectedCheckpoint: fixture.expected, reviewedTargetBasis: .existing(identity: fixture.targetIdentity, key: fixture.key, revision: fixture.target.revision, canonicalSHA256: fixture.target.planSHA256), successorCheckpoint: successor))
            let carryover = try fixture.successor(payload: try fixture.carryoverPayload(targetPredecessor: .init(predecessor)))
            XCTAssertThrowsError(try ReviewedDraftConflictResolutionV1(plan: .reviewAndRebase, expectedCheckpoint: fixture.expected, reviewedTargetBasis: .existing(identity: fixture.targetIdentity, key: fixture.key, revision: fixture.target.revision, canonicalSHA256: fixture.target.planSHA256), successorCheckpoint: carryover))
        }
        let absentWithReference = try fixture.successor(payload: try fixture.planPayload(predecessor: fixture.target))
        XCTAssertThrowsError(try ReviewedDraftConflictResolutionV1(plan: .reviewAndRebase, expectedCheckpoint: fixture.expected, reviewedTargetBasis: .absent(key: fixture.key, expectedWorkspaceRevision: 0), successorCheckpoint: absentWithReference))
        let absentCarryoverWithReference = try fixture.successor(payload: try fixture.carryoverPayload(targetPredecessor: .init(fixture.target)))
        XCTAssertThrowsError(try ReviewedDraftConflictResolutionV1(plan: .reviewAndRebase, expectedCheckpoint: fixture.expected, reviewedTargetBasis: .absent(key: fixture.key, expectedWorkspaceRevision: 0), successorCheckpoint: absentCarryoverWithReference))
        let encoded = try FieldDraftCanonicalCodecV1.encode(existing)
        let corruptHash = try XCTUnwrap(String(data: encoded, encoding: .utf8))
            .replacingOccurrences(of: fixture.expected.checkpointSHA256, with: String(repeating: "0", count: 64), options: [], range: nil)
        XCTAssertThrowsError(try FieldDraftCanonicalCodecV1.decode(ReviewedDraftConflictResolutionV1.self,
            from: Data(corruptHash.utf8)))
        XCTAssertThrowsError(try FieldDraftCanonicalCodecV1.decode(ReviewedDraftConflictResolutionV1.self,
            from: Data(repeating: 0x20, count: ReviewedDraftConflictResolutionV1.maximumCanonicalByteCount + 1)))
    }
}

private struct V23ReviewedConflictDomainFixture {
    let workspace: WorkspaceID; let key: MyDayKeyV1; let now: Date; let target: MyDayPlanV1
    let targetIdentity: WorkspaceEntityIdentityV1; let expected: FieldDraftCheckpointV1
    let existingPayload: MyDayPlanningDraftPayloadV1; let existingSuccessor: FieldDraftCheckpointV1
    let absentSuccessor: FieldDraftCheckpointV1

    static func make() throws -> Self {
        let workspace = WorkspaceID(rawValue: UUID()), now = Date(timeIntervalSince1970: 1_789_084_800)
        let key = try MyDayKeyV1(workspaceID: workspace, civilDate: .init(year: 2026, month: 9, day: 12), ianaTimeZoneIdentifier: "UTC")
        let actor = try LocalActorReferenceV1(actorReferenceID: UUID(), workspaceID: workspace, displayName: "Reviewer")
        let snapshot = try ActorSnapshotV1(snapshotID: UUID(), workspaceID: workspace, actor: actor, responsibility: .recordedBy, displayNameAtTime: "Reviewer", capturedAt: now)
        let target = try MyDayPlanV1(planID: UUID(), key: key, items: [], revision: 1, mutationID: .init(rawValue: UUID()), authoredBy: snapshot, authoredAt: now)
        let context = try MyDayPlanningConfirmedContextV1(key: key, recordedBy: snapshot, keyWasExplicitlyConfirmed: true, recordedByWasExplicitlySelectedOrCaptured: true)
        let stalePayload = try MyDayPlanningDraftPayloadV1(editing: context, intent: .plan(draft: .init(key: key, items: [], eligibleReferences: []), predecessor: nil))
        let existingPayload = try MyDayPlanningDraftPayloadV1(editing: context, intent: .plan(draft: .init(key: key, items: [], eligibleReferences: []), predecessor: target))
        let value = try Self(workspace: workspace, key: key, now: now, target: target, targetIdentity: .init(kind: .myDayPlan, id: target.planID), expected: try Self.checkpoint(workspace: workspace, key: key, payload: stalePayload, base: 0, revision: 1, state: .conflicted, mutation: UUID(), at: now), existingPayload: existingPayload, existingSuccessor: try Self.checkpoint(workspace: workspace, key: key, payload: existingPayload, base: 1, revision: 2, state: .active, mutation: UUID(), at: now.addingTimeInterval(1)), absentSuccessor: try Self.checkpoint(workspace: workspace, key: key, payload: stalePayload, base: 0, revision: 2, state: .active, mutation: UUID(), at: now.addingTimeInterval(1)))
        return value
    }

    func successor(payload: MyDayPlanningDraftPayloadV1) throws -> FieldDraftCheckpointV1 { try checkpoint(payload: payload, base: target.revision, revision: 2, state: .active, mutation: UUID(), at: now.addingTimeInterval(1)) }
    func planPayload(predecessor: MyDayPlanV1?) throws -> MyDayPlanningDraftPayloadV1 { let context = try XCTUnwrap(existingPayload.confirmedContext); return try .init(editing: context, intent: .plan(draft: .init(key: key, items: [], eligibleReferences: []), predecessor: predecessor)) }
    func carryoverPayload(targetPredecessor: MyDayPlanReferenceV1?) throws -> MyDayPlanningDraftPayloadV1 { let context = try XCTUnwrap(existingPayload.confirmedContext); let sourceKey = try MyDayKeyV1(workspaceID: workspace, civilDate: .init(year: 2026, month: 9, day: 11), ianaTimeZoneIdentifier: "UTC"); let source = try MyDayPlanV1(planID: UUID(), key: sourceKey, items: [], revision: 1, mutationID: .init(rawValue: UUID()), authoredBy: target.authoredBy, authoredAt: now); return try .init(editing: context, intent: .carryover(sourcePlan: .init(source), selectedMembershipIDs: [UUID()], targetKey: key, targetPredecessor: targetPredecessor)) }
    func sameKeyRevisionSubstitutions() throws -> [MyDayPlanV1] { [try .init(planID: UUID(), key: key, items: [], revision: 1, mutationID: .init(rawValue: UUID()), authoredBy: target.authoredBy, authoredAt: now), try .init(planID: target.planID, key: key, items: [], revision: 1, mutationID: .init(rawValue: UUID()), authoredBy: target.authoredBy, authoredAt: now)] }
    func preparedConflict() throws -> (expected: FieldDraftCheckpointV1, successor: FieldDraftCheckpointV1) {
        let commandSuccessor = try MyDayPlanV1(planID: target.planID, key: key, items: [], predecessor: target, revision: 2, mutationID: .init(rawValue: UUID()), authoredBy: target.authoredBy, authoredAt: now.addingTimeInterval(1))
        let attempt = try MyDayPlanningCommitAttemptInputsV1(command: .save(successor: commandSuccessor, predecessor: target), fieldDraftPlanID: UUID(), preparedSagaID: UUID(), contentPromotedSagaID: UUID(), targetCommittedSagaID: UUID(), draftRetirePendingSagaID: UUID(), draftRetiredSagaID: UUID(), preparedSagaMutationID: .init(rawValue: UUID()), contentPromotedSagaMutationID: .init(rawValue: UUID()), targetCommittedSagaMutationID: .init(rawValue: UUID()), draftRetirePendingSagaMutationID: .init(rawValue: UUID()), terminalBundleMutationID: .init(rawValue: UUID()), commitReceiptID: UUID(), preparedSagaUpdatedAt: now, contentPromotedSagaUpdatedAt: now.addingTimeInterval(1), targetCommittedSagaUpdatedAt: now.addingTimeInterval(2), draftRetirePendingSagaUpdatedAt: now.addingTimeInterval(3), draftRetiredSagaUpdatedAt: now.addingTimeInterval(4), terminalCheckpointUpdatedAt: now.addingTimeInterval(5))
        let expected = try checkpoint(payload: .init(prepared: attempt), base: target.revision, revision: 1, state: .conflicted, mutation: UUID(), at: now)
        let successor = try checkpoint(payload: existingPayload, base: target.revision, revision: 2, state: .active, mutation: attempt.terminalBundleMutationID.rawValue, at: now.addingTimeInterval(6))
        return (expected, successor)
    }

    func checkpoint(payload: MyDayPlanningDraftPayloadV1, base: UInt64, revision: UInt64, state: FieldDraftStateV1, mutation: UUID, at: Date) throws -> FieldDraftCheckpointV1 { try Self.checkpoint(workspace: workspace, key: key, payload: payload, base: base, revision: revision, state: state, mutation: mutation, at: at) }
    private static func checkpoint(workspace: WorkspaceID, key: MyDayKeyV1, payload: MyDayPlanningDraftPayloadV1, base: UInt64, revision: UInt64, state: FieldDraftStateV1, mutation: UUID, at: Date) throws -> FieldDraftCheckpointV1 { try .init(draftID: UUID(uuidString: "00000000-0000-0000-0000-000000000231")!, workspaceID: workspace, scope: try MyDayPlanningDraftCodecV1.scope(for: key), purpose: .myDayPlanning, codec: try MyDayPlanningDraftCodecV1.release(), baseCanonicalRevision: base, draftRevision: revision, payloadData: try MyDayPlanningDraftCodecV1.encode(payload), stageIDs: [], resumeAnchor: .init(sectionID: "review"), state: state, updatedAt: at, mutationID: .init(rawValue: mutation)) }
}

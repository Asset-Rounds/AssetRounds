import CryptoKit
import Foundation
import XCTest

@testable import FieldEvidenceApp

private struct C56VoiceCorpusV1: Decodable {
    let schema: String
    let schemaVersion: Int
    let cardID: String
    let contractRefs: [String]
    let journeyRefs: [String]
    let evidenceIDs: [String]
    let selectors: [String]
    let qualityStates: [String]
    let allowedProposalFields: [String]
    let forbiddenInferences: [String]
    let maximumProposalLifetimeSeconds: Int
    let maximumCaptureSeconds: Int
    let captureUIRuntimeOwnership: String
    let c56OwnsCaptureUIRuntime: Bool
    let p04C45OwnsCaptureUIRuntime: Bool
    let grammar: Grammar
    let golden: Golden
    let alternate: Alternate
    let hostileCases: [String]
    let lifecycleCases: [String]
    let persistence: Persistence
    let statusFlags: [String: Bool]

    struct Grammar: Decodable {
        let grammarID: String
        let version: UInt64
        let localeIdentifier: String
        let aliases: [Alias]
    }

    struct Alias: Decodable {
        let spokenAlias: String
        let fieldID: String
        let fieldKind: String
        let allowedEnumWords: [String]
    }

    struct Golden: Decodable {
        let transcript: String
        let fields: [GoldenField]
    }

    struct GoldenField: Decodable {
        let fieldID: String
        let kind: String
        let start: Int
        let length: Int
        let resolution: String
        let valueKind: String
        let value: String?
        let mantissa: Int64?
        let scale: Int?
        let unitCode: String?
        let durationSeconds: UInt64?
        let materialDescription: String?
        let quantityMantissa: Int64?
        let quantityScale: Int?
        let quantityUnitCode: String?
    }

    struct Alternate: Decodable {
        let ambiguousTranscript: String
        let unsupportedTranscript: String
        let unsupportedLocaleIdentifier: String
        let manualFallback: String
    }

    struct Persistence: Decodable {
        let mode: String
        let proposal: String
        let scratchAudio: String
        let acceptedFieldCheckpoint: String
        let persistentSchemaVersionUnchanged: Bool
        let recordsSchemaVersionUnchanged: Bool
        let durableFamilyCount: Int
        let durableFamilies: [String]
        let newPersistentModelCount: Int
        let backup: String
        let restore: String
        let cloneFork: String
        let importExport: String
        let journalReplay: String
        let search: String
        let report: String
        let deleteErase: String
        let retention: String
    }
}

private final class C56VoiceIDSource: @unchecked Sendable {
    private let lock = NSLock()
    private let ids: [UUID]
    private var index = 0

    init(_ ids: [UUID]) {
        self.ids = ids
    }

    func next() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        guard !ids.isEmpty else { return C56VoiceTestSupport.id(999_999) }
        let value = ids[min(index, ids.count - 1)]
        index += 1
        return value
    }
}

private enum C56VoiceTestSupport {
    static let fixedDate = Date(timeIntervalSince1970: 1_810_003_200.125)
    static let packageDigest = String(repeating: "d", count: 64)
    static let definitionDigest = String(repeating: "e", count: 64)

    static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "c5600000-0000-4000-8000-%012x", slot))!
    }

    static func workspace(_ slot: Int = 1) -> WorkspaceID {
        WorkspaceID(rawValue: id(slot))
    }

    static func rawTranscriptSHA256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func capability(locale: String = "en-US") throws -> AssistanceCapabilityReferenceV1 {
        try AssistanceCapabilityReferenceV1(
            capabilityID: "STRUCTURED_VOICE_PROPOSAL",
            version: "STRUCTURED_VOICE_V1",
            localeIdentifier: locale
        )
    }

    static func context(
        transcript: String,
        workspaceID: WorkspaceID = workspace(),
        locale: String = "en-US",
        targetRevision: UInt64 = 7,
        sourceID: String = "voice-c56-transcript"
    ) throws -> VoiceProposalContextV1 {
        try VoiceProposalContextV1(
            capability: capability(locale: locale),
            workspaceID: workspaceID,
            entity: try WorkspaceEntityIdentityV1(kind: .asset, id: id(20)),
            targetRevision: targetRevision,
            source: try AssistanceSourceReferenceV1(
                kind: .leasedScratch,
                sourceID: sourceID,
                revision: 1,
                contentSHA256: rawTranscriptSHA256(transcript)
            ),
            packageReleaseSHA256: packageDigest,
            definitionReleaseSHA256: definitionDigest
        )
    }

    static func grammar(
        _ corpus: C56VoiceCorpusV1,
        locale: String? = nil,
        version: UInt64? = nil
    ) throws -> VoiceStructuringGrammarReleaseV1 {
        let aliases = try corpus.grammar.aliases.map { item -> VoiceStructuringAliasV1 in
            guard let kind = VoiceStructuredFieldKindV1(rawValue: item.fieldKind) else {
                throw VoiceStructuringFailureV1.incompatibleGrammar
            }
            return try VoiceStructuringAliasV1(
                spokenAlias: item.spokenAlias,
                fieldID: item.fieldID,
                fieldKind: kind,
                allowedEnumWords: item.allowedEnumWords
            )
        }
        return try VoiceStructuringGrammarReleaseV1(
            grammarID: corpus.grammar.grammarID,
            version: version ?? corpus.grammar.version,
            localeIdentifier: locale ?? corpus.grammar.localeIdentifier,
            aliases: aliases,
            releasedAt: fixedDate
        )
    }

    static func registry(for grammar: VoiceStructuringGrammarReleaseV1) throws -> VoiceStructuringGrammarRegistryV1 {
        let semanticFields = try grammar.aliases.map { alias -> VoiceStructuringSemanticFieldV1 in
            guard let purpose = VoiceStructuringSemanticPurposeV1(rawValue: alias.fieldID) else {
                throw VoiceStructuringFailureV1.incompatibleGrammar
            }
            return VoiceStructuringSemanticFieldV1(purpose: purpose)
        }.sorted { $0.fieldID < $1.fieldID }
        return try VoiceStructuringGrammarRegistryV1(entries: [
            try VoiceStructuringGrammarRegistryEntryV1(
                release: grammar,
                semanticFields: semanticFields
            )
        ])
    }

    static func service(
        grammar: VoiceStructuringGrammarReleaseV1,
        ids: [UUID] = [id(100)]
    ) throws -> VoiceStructuringServiceV1 {
        let source = C56VoiceIDSource(ids)
        let registry = try registry(for: grammar)
        return try VoiceStructuringServiceV1(
            registry: registry,
            grammarID: grammar.grammarID,
            version: grammar.version,
            localeIdentifier: grammar.localeIdentifier,
            releaseSHA256: try grammar.releaseSHA256,
            now: { fixedDate },
            makeID: { source.next() }
        )
    }

    static func sortedSources(_ values: [AssistanceSourceReferenceV1]) -> [AssistanceSourceReferenceV1] {
        values.sorted {
            "\($0.kind.rawValue)|\($0.sourceID)|\($0.revision)|\($0.contentSHA256)"
                < "\($1.kind.rawValue)|\($1.sourceID)|\($1.revision)|\($1.contentSHA256)"
        }
    }

    static func audioScratch(proposalID: UUID) throws -> AssistanceCapabilityScratchV1 {
        try AssistanceCapabilityScratchV1(
            proposalID: proposalID,
            source: try AssistanceSourceReferenceV1(
                kind: .leasedScratch,
                sourceID: "voice-c56-audio",
                revision: 1,
                contentSHA256: rawTranscriptSHA256("separate-audio-scratch")
            )
        )
    }

    static func admission(
        proposal: StructuredVoiceProposalV1?,
        operation: VoiceStructuringLifecycleOperationV1,
        slot: Int
    ) throws -> VoiceStructuringLifecycleAdmissionV1 {
        try VoiceStructuringLifecycleAdmissionV1(
            workspaceID: proposal?.context.workspaceID ?? workspace(),
            proposalID: proposal?.proposalID,
            operation: operation,
            permissionGenerationID: id(10_000 + slot),
            audioGenerationID: id(20_000 + slot),
            applicationGenerationID: id(30_000 + slot),
            protectedDataGenerationID: id(40_000 + slot),
            eraseGenerationID: id(50_000 + slot)
        )
    }

    static func oneFieldProposal(
        grammar: VoiceStructuringGrammarReleaseV1,
        context: VoiceProposalContextV1,
        transcript: String,
        proposalID: UUID
    ) throws -> StructuredVoiceProposalV1 {
        let field = try StructuredVoiceFieldProposalV1(
            fieldID: "note",
            kind: .noteText,
            sourceSpan: try VoiceTranscriptUTF8SpanV1(
                start: 6,
                length: max(1, transcript.utf8.count - 6)
            ),
            resolution: .exact,
            proposedValue: .text(String(transcript.dropFirst(6)))
        )
        return try StructuredVoiceProposalV1(
            proposalID: proposalID,
            grammar: grammar,
            context: context,
            transcript: transcript,
            fields: [field],
            unmatchedClauses: [],
            createdAt: fixedDate,
            expiresAt: fixedDate.addingTimeInterval(1_800)
        )
    }
}

@MainActor
private final class C56VoiceFrontierStore {
    var frontier: VoiceProposalDraftCheckpointFrontierV1

    init(_ frontier: VoiceProposalDraftCheckpointFrontierV1) {
        self.frontier = frontier
    }
}

@MainActor
private final class C56VoiceAuthorityProbe: VoiceProposalReviewAuthorityV1 {
    let grammar: VoiceStructuringGrammarReleaseV1
    let frontierStore: C56VoiceFrontierStore
    var context: VoiceProposalContextV1
    var observedAt: Date
    var generationID: UUID
    var audioScratch: AssistanceCapabilityScratchV1?
    var pauseNextSnapshot = false
    var pauseAllSnapshots = false
    private(set) var snapshotPaused = false
    private(set) var pausedSnapshotCount = 0
    private var pausedContinuations: [CheckedContinuation<Void, Never>] = []

    init(
        grammar: VoiceStructuringGrammarReleaseV1,
        context: VoiceProposalContextV1,
        frontierStore: C56VoiceFrontierStore,
        observedAt: Date = C56VoiceTestSupport.fixedDate.addingTimeInterval(1),
        generationID: UUID = C56VoiceTestSupport.id(900)
    ) {
        self.grammar = grammar
        self.context = context
        self.frontierStore = frontierStore
        self.observedAt = observedAt
        self.generationID = generationID
    }

    func trustedSnapshot(
        for proposal: StructuredVoiceProposalV1
    ) async throws -> VoiceProposalTrustedSnapshotV1 {
        _ = proposal
        if pauseNextSnapshot || pauseAllSnapshots {
            pauseNextSnapshot = false
            pausedSnapshotCount += 1
            snapshotPaused = true
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                pausedContinuations.append(continuation)
            }
            snapshotPaused = false
        }
        return try makeSnapshot()
    }

    func trustedSnapshot(
        for terminal: VoiceProposalTerminalBindingV1
    ) async throws -> VoiceProposalTrustedSnapshotV1 {
        _ = terminal
        return try makeSnapshot()
    }

    func resumePausedSnapshots() {
        let waiting = pausedContinuations
        pausedContinuations.removeAll()
        waiting.forEach { $0.resume() }
    }

    private func makeSnapshot() throws -> VoiceProposalTrustedSnapshotV1 {
        let sources = C56VoiceTestSupport.sortedSources(
            [context.source] + (audioScratch.map { [$0.source] } ?? [])
        )
        return try VoiceProposalTrustedSnapshotV1(
            grammar: grammar,
            context: context,
            observedAt: observedAt,
            sourceReferences: sources,
            audioScratch: audioScratch,
            draftFrontier: frontierStore.frontier,
            generationID: generationID
        )
    }
}

private struct C56VoiceDraftPayloadV1: Codable, Equatable {
    var fields: [String: String]
}

@MainActor
private final class C56VoicePayloadApplyingProbe: VoiceReviewedFieldDraftPayloadApplyingV1 {
    enum Mode: Equatable { case normal, unchanged, wrongClaimedValue }

    let registeredCodec: DraftPayloadCodecReleaseV1
    var mode: Mode = .normal
    private(set) var applications: [VoiceReviewedFieldDraftPayloadApplicationV1] = []

    init(codec: DraftPayloadCodecReleaseV1) {
        registeredCodec = codec
    }

    func applyReviewedVoiceField(
        to predecessor: FieldDraftCheckpointV1,
        fieldID: String,
        fieldKind: VoiceStructuredFieldKindV1,
        value: VoiceStructuredFieldValueV1
    ) throws -> VoiceReviewedFieldDraftPayloadApplicationV1 {
        let payload = try FieldDraftCanonicalCodecV1.decode(
            C56VoiceDraftPayloadV1.self,
            from: predecessor.payloadData
        )
        var fields = payload.fields
        let claimedValue: VoiceStructuredFieldValueV1
        switch mode {
        case .wrongClaimedValue:
            claimedValue = .text("not-the-requested-value")
        case .normal, .unchanged:
            claimedValue = value
        }
        if mode != .unchanged {
            fields[fieldID] = encode(value)
        }
        let successorPayloadData = mode == .unchanged
            ? predecessor.payloadData
            : try FieldDraftCanonicalCodecV1.encode(C56VoiceDraftPayloadV1(fields: fields))
        let application = try VoiceReviewedFieldDraftPayloadApplicationV1(
            predecessor: predecessor,
            fieldID: fieldID,
            fieldKind: fieldKind,
            value: claimedValue,
            successorPayloadData: successorPayloadData
        )
        applications.append(application)
        return application
    }

    func decoded(_ checkpoint: FieldDraftCheckpointV1) throws -> C56VoiceDraftPayloadV1 {
        try FieldDraftCanonicalCodecV1.decode(
            C56VoiceDraftPayloadV1.self,
            from: checkpoint.payloadData
        )
    }

    private func encode(_ value: VoiceStructuredFieldValueV1) -> String {
        switch value {
        case .text(let text): return "TEXT|\(text)"
        case .allowedEnum(let text): return "ENUM|\(text)"
        case .exactNumber(let decimal):
            return "NUMBER|\(decimal.mantissa)|\(decimal.scale)|\(decimal.unit.rawValue)"
        case .durationSeconds(let seconds): return "DURATION|\(seconds)"
        case .material(let material):
            let quantity = material.quantity.map {
                "\($0.mantissa)|\($0.scale)|\($0.unit.rawValue)"
            } ?? "NONE"
            return "MATERIAL|\(material.description)|\(quantity)"
        }
    }
}

@MainActor
private final class C56VoiceDraftWriterProbe: FieldDraftWritingV1, VoiceReviewedFieldDraftReceiptReadingV1 {
    let generationID: UUID
    private(set) var checkpoint: FieldDraftCheckpointV1
    private(set) var receipts: [MutationIDV1: MutationReceiptV1] = [:]
    var frontierStore: C56VoiceFrontierStore?
    private var nextSequence: UInt64 = 1

    init(checkpoint: FieldDraftCheckpointV1, generationID: UUID) {
        self.checkpoint = checkpoint
        self.generationID = generationID
    }

    func currentCheckpoint(workspaceID: WorkspaceID, draftID: UUID) throws -> FieldDraftCheckpointV1? {
        guard checkpoint.workspaceID == workspaceID, checkpoint.draftID == draftID else { return nil }
        return checkpoint
    }

    func compareAndSwap(
        checkpoint successor: FieldDraftCheckpointV1,
        expectedDraftRevision: UInt64,
        expectedBaseRevision: UInt64
    ) throws -> MutationReceiptV1 {
        if let existing = receipts[successor.mutationID] { return existing }
        try successor.validateSuccessor(
            of: checkpoint,
            expectedDraftRevision: expectedDraftRevision,
            expectedBaseRevision: expectedBaseRevision
        )
        let mutation = try FieldDraftMutationV1(
            workspaceID: successor.workspaceID,
            expectedRevision: expectedDraftRevision,
            expectedBaseCanonicalRevision: expectedBaseRevision,
            mutationID: successor.mutationID,
            postImage: .reviseCheckpoint(successor)
        )
        let identity = try WorkspaceEntityIdentityV1(
            kind: .fieldDraftCheckpoint,
            id: checkpoint.draftID
        )
        let writerInstanceID = C56VoiceTestSupport.id(80_000)
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: successor.workspaceID,
            generationID: generationID,
            writerInstanceID: writerInstanceID,
            workspaceRevision: nextSequence - 1,
            entityRevisions: [WorkspaceEntityRevisionV1(
                identity: identity,
                revision: expectedDraftRevision
            )]
        )
        let replicaID = ReplicaID(rawValue: C56VoiceTestSupport.id(80_001))
        let replica = try WorkspaceReplicaIdentityV1(
            workspaceID: successor.workspaceID,
            replicaID: replicaID
        )
        let envelope = try MutationEnvelopeV1(
            request: WorkspaceMutationRequestV1(
                mutationID: mutation.mutationID,
                expectedRevision: expected,
                command: .applyFieldDraft(mutation)
            ),
            identity: replica
        )
        let resulting = try WorkspaceExpectedRevisionV1(
            workspaceID: successor.workspaceID,
            generationID: generationID,
            writerInstanceID: writerInstanceID,
            workspaceRevision: nextSequence,
            entityRevisions: [WorkspaceEntityRevisionV1(
                identity: identity,
                revision: successor.draftRevision
            )]
        )
        let receipt = try MutationReceiptV1(
            identity: MutationReceiptIdentityV1(
                workspaceID: successor.workspaceID,
                replicaID: replicaID,
                localSequence: nextSequence
            ),
            envelope: envelope,
            resultingRevision: try MutationPortableExpectedRevisionV1(resulting),
            postImages: try mutation.postImage.mutationPostImages,
            committedAt: successor.updatedAt
        )
        let successorFrontier = try VoiceProposalDraftCheckpointFrontierV1(checkpoint: successor)
        checkpoint = successor
        frontierStore?.frontier = successorFrontier
        receipts[mutation.mutationID] = receipt
        nextSequence += 1
        return receipt
    }

    func reviewedVoiceFieldReceipt(mutationID: MutationIDV1) throws -> MutationReceiptV1? {
        receipts[mutationID]
    }

    func advanceExternally(mutationID: UUID) throws {
        let successor = try FieldDraftCheckpointV1(
            draftID: checkpoint.draftID,
            workspaceID: checkpoint.workspaceID,
            scope: checkpoint.scope,
            purpose: checkpoint.purpose,
            codec: checkpoint.codec,
            baseCanonicalRevision: checkpoint.baseCanonicalRevision,
            draftRevision: checkpoint.draftRevision + 1,
            payloadData: checkpoint.payloadData,
            stageIDs: checkpoint.stageIDs,
            resumeAnchor: checkpoint.resumeAnchor,
            state: checkpoint.state,
            lastDurableMutationID: checkpoint.lastDurableMutationID,
            lastReceiptSHA256: checkpoint.lastReceiptSHA256,
            updatedAt: C56VoiceTestSupport.fixedDate.addingTimeInterval(60),
            mutationID: try MutationIDV1(rawValue: mutationID)
        )
        let successorFrontier = try VoiceProposalDraftCheckpointFrontierV1(checkpoint: successor)
        checkpoint = successor
        frontierStore?.frontier = successorFrontier
    }

    func append(stagingItem: AttachmentStagingItemV1, expectedRevision: UInt64) throws -> MutationReceiptV1 {
        _ = stagingItem; _ = expectedRevision
        throw WorkspaceMutationFailureV1.unsupportedCommand
    }

    func append(saga: DraftCommitSagaV1, expectedRevision: UInt64) throws -> MutationReceiptV1 {
        _ = saga; _ = expectedRevision
        throw WorkspaceMutationFailureV1.unsupportedCommand
    }

    func append(reservation: DraftContentReservationV1, expectedRevision: UInt64) throws -> MutationReceiptV1 {
        _ = reservation; _ = expectedRevision
        throw WorkspaceMutationFailureV1.unsupportedCommand
    }

    func apply(
        commitTerminalBundle: DraftCommitTerminalBundleV1,
        expectedDraftRevision: UInt64,
        expectedSagaRevision: UInt64
    ) throws -> MutationReceiptV1 {
        _ = commitTerminalBundle; _ = expectedDraftRevision; _ = expectedSagaRevision
        throw WorkspaceMutationFailureV1.unsupportedCommand
    }

    func apply(
        discardTerminalBundle: DraftDiscardTerminalBundleV1,
        expectedDraftRevision: UInt64
    ) throws -> MutationReceiptV1 {
        _ = discardTerminalBundle; _ = expectedDraftRevision
        throw WorkspaceMutationFailureV1.unsupportedCommand
    }
}

private struct C56VoiceNoopContentPromotion: DraftContentPromotionPortV1 {
    func promote(
        plan: DraftCommitPlanV1,
        items: [AttachmentStagingItemV1],
        reservationMutationIDs: [UUID: MutationIDV1]
    ) async throws -> [DraftContentReservationV1] {
        _ = plan; _ = items; _ = reservationMutationIDs
        return []
    }

    func quarantine(
        reservations: [DraftContentReservationV1],
        for plan: DraftDiscardPlanV1
    ) async throws {
        _ = reservations; _ = plan
    }
}

@MainActor
private final class C56VoiceNoopTarget: DraftCanonicalCommitPortV1 {
    func commit(
        plan: DraftCommitPlanV1,
        reservations: [DraftContentReservationV1]
    ) throws -> MutationReceiptV1 {
        _ = plan; _ = reservations
        throw WorkspaceMutationFailureV1.unsupportedCommand
    }

    func readBackMatches(plan: DraftCommitPlanV1, receipt: MutationReceiptV1) throws -> Bool {
        _ = plan; _ = receipt
        return false
    }
}

@MainActor
private final class C56VoiceDraftHarness {
    let fixture: C36FieldDraftTestSupportV1.Fixture
    let checkpoint: FieldDraftCheckpointV1
    let writer: C56VoiceDraftWriterProbe
    let payloadApplying: C56VoicePayloadApplyingProbe
    let drafts: FieldDraftCoordinatorV1
    let bridge: VoiceStructuringDraftCheckpointBridgeV1
    let frontierStore: C56VoiceFrontierStore

    init(seed: Int) throws {
        let fixture = try C36FieldDraftTestSupportV1.makeFixture(seed: seed)
        let payload = try FieldDraftCanonicalCodecV1.encode(
            C56VoiceDraftPayloadV1(fields: ["seed": "initial"])
        )
        let checkpoint = try FieldDraftCheckpointV1(
            draftID: fixture.activeCheckpoint.draftID,
            workspaceID: fixture.activeCheckpoint.workspaceID,
            scope: fixture.activeCheckpoint.scope,
            purpose: fixture.activeCheckpoint.purpose,
            codec: fixture.activeCheckpoint.codec,
            baseCanonicalRevision: fixture.activeCheckpoint.baseCanonicalRevision,
            draftRevision: 1,
            payloadData: payload,
            stageIDs: fixture.activeCheckpoint.stageIDs,
            resumeAnchor: fixture.activeCheckpoint.resumeAnchor,
            state: .active,
            updatedAt: C56VoiceTestSupport.fixedDate,
            mutationID: fixture.activeCheckpoint.mutationID
        )
        let writer = C56VoiceDraftWriterProbe(
            checkpoint: checkpoint,
            generationID: C56VoiceTestSupport.id(90_000 + seed)
        )
        let payloadApplying = C56VoicePayloadApplyingProbe(codec: checkpoint.codec)
        let drafts = FieldDraftCoordinatorV1(
            registry: fixture.registry,
            writer: writer,
            content: C56VoiceNoopContentPromotion(),
            target: C56VoiceNoopTarget()
        )
        self.fixture = fixture
        self.checkpoint = checkpoint
        self.writer = writer
        self.payloadApplying = payloadApplying
        self.drafts = drafts
        bridge = VoiceStructuringDraftCheckpointBridgeV1(
            drafts: drafts,
            payloadApplying: payloadApplying
        )
        frontierStore = C56VoiceFrontierStore(
            try VoiceProposalDraftCheckpointFrontierV1(checkpoint: checkpoint)
        )
        writer.frontierStore = frontierStore
    }
}

@MainActor
private final class C56VoiceScratchProbe: VoiceProposalScratchCleaningV1 {
    enum Failure: Error, Equatable { case interrupted }

    private(set) var calls: [(UUID, [AssistanceSourceReferenceV1])] = []
    var failuresRemaining = 0
    var pauseNextCall = false
    private(set) var scratchPaused = false
    private var pausedContinuations: [CheckedContinuation<Void, Never>] = []

    func discardVoiceProposalScratch(
        proposalID: UUID,
        sourceReferences: [AssistanceSourceReferenceV1]
    ) async throws {
        calls.append((proposalID, sourceReferences))
        if pauseNextCall {
            pauseNextCall = false
            scratchPaused = true
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                pausedContinuations.append(continuation)
            }
            scratchPaused = false
        }
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw Failure.interrupted
        }
    }

    func resumePausedCalls() {
        let waiting = pausedContinuations
        pausedContinuations.removeAll()
        waiting.forEach { $0.resume() }
    }
}

@MainActor
private final class C56VoiceAdmissionProbe: VoiceStructuringLifecycleAdmittingV1 {
    private(set) var calls: [VoiceStructuringLifecycleAdmissionV1] = []
    var failuresRemaining = 0

    func admitVoiceStructuringLifecycle(
        _ admission: VoiceStructuringLifecycleAdmissionV1
    ) async throws {
        calls.append(admission)
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw C56VoiceScratchProbe.Failure.interrupted
        }
    }
}

@MainActor
private final class C56VoicePendingResultProbe {
    private(set) var errors: [Error] = []

    func record(_ error: Error) {
        errors.append(error)
    }
}

@MainActor
final class V9_64StructuredVoiceProposalTests: XCTestCase {
    private func corpus() throws -> C56VoiceCorpusV1 {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "V22P03C56StructuredVoiceProposalCorpusV1",
                withExtension: "json",
                subdirectory: "Fixtures/V22/StructuredVoice"
            ) ?? bundle.url(
                forResource: "V22P03C56StructuredVoiceCorpusV1",
                withExtension: "json"
            )
        )
        return try JSONDecoder().decode(C56VoiceCorpusV1.self, from: Data(contentsOf: url))
    }

    private func grammar(_ corpus: C56VoiceCorpusV1) throws -> VoiceStructuringGrammarReleaseV1 {
        try C56VoiceTestSupport.grammar(corpus)
    }

    private func assertCorpusHeader(_ corpus: C56VoiceCorpusV1) throws {
        XCTAssertEqual(corpus.schema, "V22P03C56StructuredVoiceProposalCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.cardID, "V23-P03-C56")
        XCTAssertEqual(corpus.contractRefs, [
            "VoiceStructuringGrammarReleaseV1",
            "StructuredVoiceProposalV1",
            "VoiceProposalReviewPlanV1",
            "DirectPrerequisiteEvidenceSetV1",
            "CardAcceptanceInclusionProofV1",
            "CardAcceptanceInclusionProofRecoveryReceiptV1",
            "CandidateAcceptanceCompatibilityReceiptV1",
        ])
        XCTAssertEqual(corpus.journeyRefs, ["FJ14"])
        XCTAssertEqual(corpus.evidenceIDs, [
            "V23-P03-C56-G01", "V23-P03-C56-A01", "V23-P03-C56-H01",
            "V23-P03-C56-I01", "V23-P03-C56-R01",
        ])
        XCTAssertEqual(corpus.qualityStates, VoiceStructuringResolutionV1.allCases.map(\.rawValue))
        XCTAssertEqual(
            Set(corpus.allowedProposalFields),
            Set(VoiceStructuredFieldKindV1.allCases.map(\.rawValue))
        )
        XCTAssertEqual(corpus.maximumProposalLifetimeSeconds, 1_800)
        XCTAssertEqual(corpus.maximumCaptureSeconds, 60)
        XCTAssertEqual(corpus.captureUIRuntimeOwnership, "V23-P04-C45")
        XCTAssertFalse(corpus.c56OwnsCaptureUIRuntime)
        XCTAssertTrue(corpus.p04C45OwnsCaptureUIRuntime)
        XCTAssertTrue(corpus.statusFlags.values.allSatisfy { !$0 })
    }

    func testV23P03C56G01DeterministicGrammarSpansAndTypedC36Acceptance() async throws {
        let corpus = try corpus()
        try assertCorpusHeader(corpus)
        let grammar = try grammar(corpus)
        let context = try C56VoiceTestSupport.context(transcript: corpus.golden.transcript)
        XCTAssertEqual(
            context.source.contentSHA256,
            C56VoiceTestSupport.rawTranscriptSHA256(corpus.golden.transcript)
        )
        let service = try C56VoiceTestSupport.service(
            grammar: grammar,
            ids: [C56VoiceTestSupport.id(101)]
        )
        let proposal = try service.structure(
            transcript: corpus.golden.transcript,
            context: context
        )
        try proposal.validate(grammar: grammar)
        try service.validateDeterministicProposal(proposal)
        XCTAssertEqual(proposal.fields.count, corpus.golden.fields.count)
        XCTAssertTrue(proposal.unmatchedClauses.isEmpty)
        XCTAssertEqual(proposal.grammarReleaseSHA256, try grammar.releaseSHA256)

        for expected in corpus.golden.fields {
            let actual = try XCTUnwrap(proposal.fields.first { $0.fieldID == expected.fieldID })
            XCTAssertEqual(actual.kind.rawValue, expected.kind)
            XCTAssertEqual(actual.resolution.rawValue, expected.resolution)
            XCTAssertEqual(actual.sourceSpan.start, expected.start)
            XCTAssertEqual(actual.sourceSpan.length, expected.length)
            let value = try XCTUnwrap(actual.proposedValue)
            switch (expected.valueKind, value) {
            case ("TEXT", .text(let text)), ("ALLOWED_ENUM", .allowedEnum(let text)):
                XCTAssertEqual(text, expected.value)
            case ("EXACT_NUMBER", .exactNumber(let decimal)):
                XCTAssertEqual(decimal.mantissa, expected.mantissa)
                XCTAssertEqual(decimal.scale, expected.scale)
                XCTAssertEqual(decimal.unit.rawValue, expected.unitCode)
            case ("DURATION_SECONDS", .durationSeconds(let seconds)):
                XCTAssertEqual(seconds, expected.durationSeconds)
            case ("MATERIAL", .material(let material)):
                XCTAssertEqual(material.description, expected.materialDescription)
                XCTAssertEqual(material.quantity?.mantissa, expected.quantityMantissa)
                XCTAssertEqual(material.quantity?.scale, expected.quantityScale)
                XCTAssertEqual(material.quantity?.unit.rawValue, expected.quantityUnitCode)
            default:
                XCTFail("fixture value kind does not match \(expected.fieldID)")
            }
        }

        let proposalBytes = try VoiceStructuringCanonicalCodecV1.encode(proposal)
        let decodedProposal = try VoiceStructuringCanonicalCodecV1.decodeProposal(
            from: proposalBytes,
            registry: try C56VoiceTestSupport.registry(for: grammar),
            currentContext: context,
            at: C56VoiceTestSupport.fixedDate.addingTimeInterval(1)
        )
        XCTAssertEqual(decodedProposal, proposal)

        let harness = try C56VoiceDraftHarness(seed: 560_001)
        let authority = C56VoiceAuthorityProbe(
            grammar: grammar,
            context: context,
            frontierStore: harness.frontierStore,
            generationID: harness.writer.generationID
        )
        authority.audioScratch = try C56VoiceTestSupport.audioScratch(proposalID: proposal.proposalID)
        let scratch = C56VoiceScratchProbe()
        let coordinator = VoiceProposalReviewCoordinatorV1(
            authority: authority,
            draftCheckpointBridge: harness.bridge,
            scratchCleaner: scratch
        )
        let initialSnapshot = try await authority.trustedSnapshot(for: proposal)
        try await coordinator.begin(proposal: proposal)

        let values = Dictionary(uniqueKeysWithValues: proposal.fields.map { ($0.fieldID, $0) })
        let measurement = try VoiceExactDecimalV1(mantissa: 130, scale: 1, unit: .centimeter)
        let reviews: [VoiceProposalFieldReviewV1] = [
            try VoiceProposalFieldReviewV1(
                fieldID: "note", disposition: .accept, reviewedValue: values["note"]?.proposedValue
            ),
            try VoiceProposalFieldReviewV1(
                fieldID: "finding.title", disposition: .edit,
                reviewedValue: .text("Paint worn but dry")
            ),
            try VoiceProposalFieldReviewV1(
                fieldID: "finding.condition", disposition: .accept,
                reviewedValue: values["finding.condition"]?.proposedValue
            ),
            try VoiceProposalFieldReviewV1(
                fieldID: "explicit.numberAndUnit", disposition: .edit,
                reviewedValue: .exactNumber(measurement)
            ),
            try VoiceProposalFieldReviewV1(
                fieldID: "duration", disposition: .accept,
                reviewedValue: values["duration"]?.proposedValue
            ),
            try VoiceProposalFieldReviewV1(
                fieldID: "material.descriptionAndQuantity", disposition: .reject,
                reviewedValue: nil
            ),
        ]
        for review in reviews {
            _ = try await coordinator.reviewField(
                proposalID: proposal.proposalID,
                review: review
            )
        }
        let plan = try await coordinator.finalize(proposalID: proposal.proposalID)
        try plan.validate(against: proposal)
        XCTAssertEqual(harness.payloadApplying.applications.count, 5)
        XCTAssertEqual(harness.writer.receipts.count, 5)
        let persisted = try harness.payloadApplying.decoded(harness.writer.checkpoint)
        XCTAssertEqual(persisted.fields["note"], "TEXT|Safety verified")
        XCTAssertEqual(persisted.fields["finding.title"], "TEXT|Paint worn but dry")
        XCTAssertEqual(persisted.fields["finding.condition"], "ENUM|good")
        XCTAssertEqual(persisted.fields["explicit.numberAndUnit"], "NUMBER|130|1|CENTIMETER")
        XCTAssertEqual(persisted.fields["duration"], "DURATION|7200")
        XCTAssertNil(persisted.fields["material.descriptionAndQuantity"])
        XCTAssertEqual(scratch.calls.count, 1)
        let expectedSources = C56VoiceTestSupport.sortedSources(
            [context.source, try XCTUnwrap(authority.audioScratch?.source)]
        )
        XCTAssertEqual(scratch.calls[0].1, expectedSources)
        let planReplay = try await coordinator.reviewPlan(proposalID: proposal.proposalID)
        XCTAssertEqual(planReplay, plan)

        let firstField = try XCTUnwrap(proposal.fields.first)
        let firstReview = try XCTUnwrap(reviews.first)
        let firstUpdate = try VoiceProposalDraftCheckpointUpdateV1(
            proposal: proposal,
            field: firstField,
            review: firstReview,
            snapshot: initialSnapshot
        )
        XCTAssertNotNil(try harness.bridge.existingReviewedVoiceField(firstUpdate))
        let stored = try XCTUnwrap(harness.writer.receipts[firstUpdate.mutationID])
        XCTAssertEqual(stored.mutationID, firstUpdate.mutationID)

        let staleTranscript = "note: stale frontier"
        let staleContext = try C56VoiceTestSupport.context(transcript: staleTranscript)
        let staleProposal = try C56VoiceTestSupport.oneFieldProposal(
            grammar: grammar,
            context: staleContext,
            transcript: staleTranscript,
            proposalID: C56VoiceTestSupport.id(106)
        )
        let staleHarness = try C56VoiceDraftHarness(seed: 560_006)
        let staleScratch = C56VoiceScratchProbe()
        let staleCoordinator = VoiceProposalReviewCoordinatorV1(
            authority: C56VoiceAuthorityProbe(
                grammar: grammar,
                context: staleContext,
                frontierStore: staleHarness.frontierStore,
                generationID: staleHarness.writer.generationID
            ),
            draftCheckpointBridge: staleHarness.bridge,
            scratchCleaner: staleScratch
        )
        try await staleCoordinator.begin(proposal: staleProposal)
        _ = try await staleCoordinator.reviewField(
            proposalID: staleProposal.proposalID,
            review: try VoiceProposalFieldReviewV1(
                fieldID: "note",
                disposition: .accept,
                reviewedValue: staleProposal.fields[0].proposedValue
            )
        )
        let reviewedFrontier = staleHarness.frontierStore.frontier
        try staleHarness.writer.advanceExternally(mutationID: C56VoiceTestSupport.id(107))
        XCTAssertNotEqual(staleHarness.frontierStore.frontier, reviewedFrontier)
        do {
            _ = try await staleCoordinator.finalize(proposalID: staleProposal.proposalID)
            XCTFail("an externally advanced C36 frontier must block terminal closure")
        } catch {
            XCTAssertEqual(error as? VoiceProposalReviewCoordinatorFailureV1, .staleGeneration)
        }
        let stalePlan = try await staleCoordinator.reviewPlan(proposalID: staleProposal.proposalID)
        XCTAssertNil(stalePlan)
        XCTAssertEqual(staleHarness.writer.receipts.count, 1)
        XCTAssertEqual(staleScratch.calls.count, 1)

        let allRejectTranscript = "note: all reject"
        let allRejectContext = try C56VoiceTestSupport.context(transcript: allRejectTranscript)
        let allRejectProposal = try C56VoiceTestSupport.oneFieldProposal(
            grammar: grammar,
            context: allRejectContext,
            transcript: allRejectTranscript,
            proposalID: C56VoiceTestSupport.id(108)
        )
        let allRejectHarness = try C56VoiceDraftHarness(seed: 560_007)
        let allRejectScratch = C56VoiceScratchProbe()
        let allRejectCoordinator = VoiceProposalReviewCoordinatorV1(
            authority: C56VoiceAuthorityProbe(
                grammar: grammar,
                context: allRejectContext,
                frontierStore: allRejectHarness.frontierStore,
                generationID: allRejectHarness.writer.generationID
            ),
            draftCheckpointBridge: allRejectHarness.bridge,
            scratchCleaner: allRejectScratch
        )
        try await allRejectCoordinator.begin(proposal: allRejectProposal)
        _ = try await allRejectCoordinator.reviewField(
            proposalID: allRejectProposal.proposalID,
            review: try VoiceProposalFieldReviewV1(
                fieldID: "note",
                disposition: .reject,
                reviewedValue: nil
            )
        )
        let allRejectPlan = try await allRejectCoordinator.finalize(
            proposalID: allRejectProposal.proposalID
        )
        try allRejectPlan.validate(against: allRejectProposal)
        XCTAssertTrue(allRejectHarness.writer.receipts.isEmpty)
        XCTAssertEqual(allRejectScratch.calls.count, 1)
        let allRejectReplay = try await allRejectCoordinator.reviewPlan(
            proposalID: allRejectProposal.proposalID
        )
        XCTAssertEqual(allRejectReplay, allRejectPlan)
    }

    func testV23P03C56A01AmbiguityLocaleAndManualFallbackUseExplicitReview() async throws {
        let corpus = try corpus()
        let grammar = try grammar(corpus)
        let transcript = corpus.alternate.ambiguousTranscript
        let context = try C56VoiceTestSupport.context(transcript: transcript)
        let service = try C56VoiceTestSupport.service(
            grammar: grammar,
            ids: [C56VoiceTestSupport.id(201)]
        )
        let proposal = try service.structure(transcript: transcript, context: context)
        XCTAssertEqual(proposal.fields.count, 1)
        XCTAssertEqual(proposal.fields[0].fieldID, "material.descriptionAndQuantity")
        XCTAssertEqual(proposal.fields[0].resolution, .ambiguous)
        XCTAssertNil(proposal.fields[0].proposedValue)
        XCTAssertEqual(proposal.fields[0].alternatives.count, 1)

        let harness = try C56VoiceDraftHarness(seed: 560_101)
        let authority = C56VoiceAuthorityProbe(
            grammar: grammar,
            context: context,
            frontierStore: harness.frontierStore,
            generationID: harness.writer.generationID
        )
        let scratch = C56VoiceScratchProbe()
        let admission = C56VoiceAdmissionProbe()
        let adapter = VoiceStructuringLifecycleAdapterV1(
            trustedState: authority,
            drafts: harness.drafts,
            payloadApplying: harness.payloadApplying,
            scratchCleaner: scratch,
            admission: admission,
            authenticator: service
        )
        try await adapter.present(
            proposal,
            admission: try C56VoiceTestSupport.admission(
                proposal: proposal, operation: .present, slot: 1
            )
        )
        let edit = try VoiceProposalFieldReviewV1(
            fieldID: "material.descriptionAndQuantity",
            disposition: .edit,
            reviewedValue: .material(
                try VoiceMaterialProposalValueV1(description: "bolts", quantity: nil)
            )
        )
        _ = try await adapter.review(
            proposalID: proposal.proposalID,
            fieldReview: edit,
            admission: try C56VoiceTestSupport.admission(
                proposal: proposal, operation: .review, slot: 2
            )
        )
        let plan = try await adapter.finalizeReview(
            proposalID: proposal.proposalID,
            admission: try C56VoiceTestSupport.admission(
                proposal: proposal, operation: .finalize, slot: 3
            )
        )
        try plan.validate(against: proposal)
        let planReplay = try await adapter.reviewPlan(proposalID: proposal.proposalID)
        XCTAssertEqual(planReplay, plan)
        XCTAssertEqual(harness.payloadApplying.applications.count, 1)

        let unsupportedTranscript = corpus.alternate.unsupportedTranscript
        let unsupported = try service.structure(
            transcript: unsupportedTranscript,
            context: try C56VoiceTestSupport.context(transcript: unsupportedTranscript)
        )
        XCTAssertTrue(unsupported.fields.isEmpty)
        XCTAssertEqual(unsupported.unmatchedClauses.count, 1)
        XCTAssertEqual(unsupported.unmatchedClauses[0].resolution, .unsupported)
        XCTAssertEqual(unsupported.unmatchedClauses[0].reason.rawValue, VoiceUnmatchedClauseReasonV1.rejectedByFieldValidation.rawValue)

        let matrix = try CapabilityPermissionMatrixV1.current()
        let descriptor = try matrix.descriptor(for: .speechDictation)
        XCTAssertEqual(descriptor.manualFallback, .typeManually)
        XCTAssertEqual(corpus.alternate.manualFallback, ManualFallbackActionV1.typeManually.rawValue)
        let interrupted = try CapabilityStateV1(
            capabilityID: .speechDictation,
            permission: .authorized,
            runtime: .interrupted,
            observedAt: C56VoiceTestSupport.fixedDate
        )
        XCTAssertEqual(interrupted.runtime.rawValue, CapabilityRuntimeStateV1.interrupted.rawValue)

        let foreignLocale = corpus.alternate.unsupportedLocaleIdentifier
        let foreignGrammar = try C56VoiceTestSupport.grammar(
            corpus, locale: foreignLocale, version: 2
        )
        let foreignService = try C56VoiceTestSupport.service(grammar: foreignGrammar)
        let foreignTranscript = "note: manuel"
        XCTAssertThrowsError(
            try foreignService.structure(
                transcript: foreignTranscript,
                context: try C56VoiceTestSupport.context(
                    transcript: foreignTranscript, locale: foreignLocale
                )
            )
        ) { error in
            XCTAssertEqual(error as? VoiceStructuringFailureV1, .incompatibleGrammar)
        }
    }

    func testV23P03C56H01HostileRegistrySpansValuesReplayAndGenerationFailClosed() async throws {
        let corpus = try corpus()
        let grammar = try grammar(corpus)
        let releaseDigest = try grammar.releaseSHA256
        let registry = try C56VoiceTestSupport.registry(for: grammar)
        XCTAssertThrowsError(
            try registry.resolve(
                grammarID: grammar.grammarID,
                version: grammar.version + 1,
                localeIdentifier: grammar.localeIdentifier,
                releaseSHA256: releaseDigest
            )
        ) { error in
            XCTAssertEqual(error as? VoiceStructuringFailureV1, .incompatibleGrammar)
        }
        XCTAssertThrowsError(
            try VoiceStructuringServiceV1(
                registry: registry,
                grammarID: grammar.grammarID,
                version: grammar.version,
                localeIdentifier: grammar.localeIdentifier,
                releaseSHA256: String(repeating: "0", count: 64)
            )
        ) { error in
            XCTAssertEqual(error as? VoiceStructuringFailureV1, .incompatibleGrammar)
        }

        let forbiddenAlias = try VoiceStructuringAliasV1(
            spokenAlias: "command",
            fieldID: "canonical.command",
            fieldKind: .noteText
        )
        let forbiddenGrammar = try VoiceStructuringGrammarReleaseV1(
            grammarID: "C56_FORBIDDEN",
            version: 1,
            localeIdentifier: "en-US",
            aliases: [forbiddenAlias],
            releasedAt: C56VoiceTestSupport.fixedDate
        )
        XCTAssertThrowsError(
            try VoiceStructuringGrammarRegistryEntryV1(
                release: forbiddenGrammar,
                semanticFields: [VoiceStructuringSemanticFieldV1(purpose: .note)]
            )
        )

        let collisionA = try VoiceStructuringAliasV1(
            spokenAlias: "meter", fieldID: "note", fieldKind: .noteText
        )
        let collisionB = try VoiceStructuringAliasV1(
            spokenAlias: "meter", fieldID: "finding.title", fieldKind: .findingText
        )
        XCTAssertThrowsError(
            try VoiceStructuringGrammarReleaseV1(
                grammarID: "C56_COLLISION",
                version: 1,
                localeIdentifier: "en-US",
                aliases: [collisionA, collisionB],
                releasedAt: C56VoiceTestSupport.fixedDate
            )
        )
        XCTAssertThrowsError(
            try VoiceTranscriptUTF8SpanV1(start: Int.max, length: 1).validate(in: "x")
        )
        XCTAssertThrowsError(
            try VoiceTranscriptUTF8SpanV1(start: 1, length: 1).validate(in: "é")
        )

        let mixedTranscript = "note: Safe; unknown clause; duration: soon"
        let mixedService = try C56VoiceTestSupport.service(
            grammar: grammar,
            ids: [C56VoiceTestSupport.id(301)]
        )
        let mixed = try mixedService.structure(
            transcript: mixedTranscript,
            context: try C56VoiceTestSupport.context(transcript: mixedTranscript)
        )
        try mixed.validate(grammar: grammar)
        XCTAssertEqual(mixed.fields.map(\.fieldID), ["note"])
        XCTAssertEqual(mixed.unmatchedClauses.map(\.occurrenceID), ["clause-2", "clause-3"])
        XCTAssertEqual(
            mixed.unmatchedClauses.map { $0.reason.rawValue },
            [
                VoiceUnmatchedClauseReasonV1.noExplicitGrammarMatch.rawValue,
                VoiceUnmatchedClauseReasonV1.rejectedByFieldValidation.rawValue,
            ]
        )

        let goldenContext = try C56VoiceTestSupport.context(transcript: corpus.golden.transcript)
        let goldenService = try C56VoiceTestSupport.service(
            grammar: grammar,
            ids: [C56VoiceTestSupport.id(304)]
        )
        let goldenProposal = try goldenService.structure(
            transcript: corpus.golden.transcript,
            context: goldenContext
        )
        try goldenService.validateDeterministicProposal(goldenProposal)
        for index in goldenProposal.fields.indices {
            let original = goldenProposal.fields[index]
            let forgedValue: VoiceStructuredFieldValueV1
            switch original.kind {
            case .noteText, .findingText:
                forgedValue = .text("forged value")
            case .allowedEnum:
                forgedValue = .allowedEnum("poor")
            case .exactNumberAndUnit:
                forgedValue = .exactNumber(
                    try VoiceExactDecimalV1(mantissa: 999, scale: 0, unit: .meter)
                )
            case .duration:
                forgedValue = .durationSeconds(3)
            case .materialDescriptionAndQuantity:
                forgedValue = .material(
                    try VoiceMaterialProposalValueV1(
                        description: "forged material",
                        quantity: try VoiceExactDecimalV1(mantissa: 1, scale: 0, unit: .each)
                    )
                )
            }
            var forgedFields = goldenProposal.fields
            forgedFields[index] = try StructuredVoiceFieldProposalV1(
                fieldID: original.fieldID,
                kind: original.kind,
                sourceSpan: original.sourceSpan,
                resolution: original.resolution,
                proposedValue: forgedValue,
                alternatives: original.alternatives
            )
            let forgedProposal = try StructuredVoiceProposalV1(
                proposalID: goldenProposal.proposalID,
                grammar: grammar,
                context: goldenContext,
                transcript: goldenProposal.transcript,
                fields: forgedFields,
                unmatchedClauses: goldenProposal.unmatchedClauses,
                createdAt: goldenProposal.createdAt,
                expiresAt: goldenProposal.expiresAt
            )
            XCTAssertThrowsError(try goldenService.validateDeterministicProposal(forgedProposal))
        }
        let unsupportedTranscript = "note: Safe; unknown clause"
        let unsupportedProposal = try goldenService.structure(
            transcript: unsupportedTranscript,
            context: try C56VoiceTestSupport.context(transcript: unsupportedTranscript)
        )
        let omittedClause = try StructuredVoiceProposalV1(
            proposalID: unsupportedProposal.proposalID,
            grammar: grammar,
            context: unsupportedProposal.context,
            transcript: unsupportedProposal.transcript,
            fields: unsupportedProposal.fields,
            unmatchedClauses: [],
            createdAt: unsupportedProposal.createdAt,
            expiresAt: unsupportedProposal.expiresAt
        )
        XCTAssertThrowsError(try goldenService.validateDeterministicProposal(omittedClause))
        let twoUnmatchedTranscript = "unknown one; unknown two"
        let twoUnmatched = try goldenService.structure(
            transcript: twoUnmatchedTranscript,
            context: try C56VoiceTestSupport.context(transcript: twoUnmatchedTranscript)
        )
        let firstUnmatched = try XCTUnwrap(twoUnmatched.unmatchedClauses.first)
        var mutatedUnmatched = twoUnmatched.unmatchedClauses
        mutatedUnmatched[0] = try VoiceUnmatchedClauseV1(
            occurrenceID: "forged-clause",
            sourceSpan: firstUnmatched.sourceSpan,
            resolution: firstUnmatched.resolution,
            reason: firstUnmatched.reason
        )
        let mutatedUnmatchedProposal = try StructuredVoiceProposalV1(
            proposalID: twoUnmatched.proposalID,
            grammar: grammar,
            context: twoUnmatched.context,
            transcript: twoUnmatched.transcript,
            fields: twoUnmatched.fields,
            unmatchedClauses: mutatedUnmatched,
            createdAt: twoUnmatched.createdAt,
            expiresAt: twoUnmatched.expiresAt
        )
        XCTAssertThrowsError(
            try goldenService.validateDeterministicProposal(mutatedUnmatchedProposal)
        )

        let forbiddenTranscript = "note: diagnosis suspected"
        let forbidden = try mixedService.structure(
            transcript: forbiddenTranscript,
            context: try C56VoiceTestSupport.context(transcript: forbiddenTranscript)
        )
        XCTAssertEqual(forbidden.fields.map(\.fieldID), ["note"])
        XCTAssertTrue(forbidden.unmatchedClauses.isEmpty)
        if case .text(let transcription)? = forbidden.fields.first?.proposedValue {
            XCTAssertEqual(transcription, "diagnosis suspected")
        } else {
            XCTFail("allowed note grammar must preserve bounded transcription")
        }
        XCTAssertTrue(forbidden.fields.allSatisfy { $0.fieldID == "note" })
        let forbiddenCommandTranscript = "stock: decrement"
        let forbiddenCommand = try mixedService.structure(
            transcript: forbiddenCommandTranscript,
            context: try C56VoiceTestSupport.context(transcript: forbiddenCommandTranscript)
        )
        XCTAssertTrue(forbiddenCommand.fields.isEmpty)
        XCTAssertEqual(forbiddenCommand.unmatchedClauses.count, 1)
        XCTAssertEqual(
            forbiddenCommand.unmatchedClauses[0].reason.rawValue,
            VoiceUnmatchedClauseReasonV1.noExplicitGrammarMatch.rawValue
        )
        XCTAssertTrue(corpus.forbiddenInferences.contains("CANONICAL_COMMAND"))
        XCTAssertTrue(corpus.forbiddenInferences.contains("STOCK_DECREMENT"))

        for hostile in [
            "measurement: NaN cm",
            "measurement: 12,5 cm",
            "duration: 999999999999999999999 day",
            "material: -1 ea bolts",
        ] {
            let result = try mixedService.structure(
                transcript: hostile,
                context: try C56VoiceTestSupport.context(transcript: hostile)
            )
            XCTAssertTrue(result.fields.isEmpty)
            XCTAssertFalse(result.unmatchedClauses.isEmpty)
        }
        XCTAssertThrowsError(
            try mixedService.structure(
                transcript: "note: \u{200B}hidden",
                context: try C56VoiceTestSupport.context(transcript: "note: \u{200B}hidden")
            )
        ) { error in
            XCTAssertEqual(error as? VoiceStructuringFailureV1, .invalidValue)
        }
        XCTAssertThrowsError(
            try mixedService.structure(
                transcript: "note: Safe",
                context: try VoiceProposalContextV1(
                    capability: C56VoiceTestSupport.capability(),
                    workspaceID: C56VoiceTestSupport.workspace(),
                    entity: try WorkspaceEntityIdentityV1(kind: .asset, id: C56VoiceTestSupport.id(20)),
                    targetRevision: 7,
                    source: try AssistanceSourceReferenceV1(
                        kind: .leasedScratch,
                        sourceID: "voice-c56-transcript",
                        revision: 1,
                        contentSHA256: String(repeating: "0", count: 64)
                    )
                )
            )
        ) { error in
            XCTAssertEqual(error as? VoiceStructuringFailureV1, .invalidDigest)
        }

        let replayTranscript = "note: Safe"
        let replayContext = try C56VoiceTestSupport.context(transcript: replayTranscript)
        let replayService = try C56VoiceTestSupport.service(
            grammar: grammar, ids: [C56VoiceTestSupport.id(302)]
        )
        let proposal = try replayService.structure(
            transcript: replayTranscript,
            context: replayContext
        )
        let harness = try C56VoiceDraftHarness(seed: 560_201)
        let authority = C56VoiceAuthorityProbe(
            grammar: grammar, context: replayContext,
            frontierStore: harness.frontierStore,
            generationID: harness.writer.generationID
        )
        let scratch = C56VoiceScratchProbe()
        let coordinator = VoiceProposalReviewCoordinatorV1(
            authority: authority,
            draftCheckpointBridge: harness.bridge,
            scratchCleaner: scratch
        )
        try await coordinator.begin(proposal: proposal)
        try await coordinator.begin(proposal: proposal)
        let note = try XCTUnwrap(proposal.fields.first { $0.fieldID == "note" })
        let accept = try VoiceProposalFieldReviewV1(
            fieldID: "note", disposition: .accept, reviewedValue: note.proposedValue
        )
        _ = try await coordinator.reviewField(proposalID: proposal.proposalID, review: accept)
        _ = try await coordinator.reviewField(proposalID: proposal.proposalID, review: accept)
        XCTAssertEqual(harness.writer.receipts.count, 1)
        let divergent = try replayService.structure(
            transcript: "note: Changed",
            context: try C56VoiceTestSupport.context(transcript: "note: Changed")
        )
        do {
            try await coordinator.begin(proposal: divergent)
            XCTFail("same proposal ID with different bytes must be rejected")
        } catch {
            XCTAssertEqual(error as? VoiceProposalReviewCoordinatorFailureV1, .divergentProposalReplay)
        }
        do {
            _ = try await coordinator.reviewField(
                proposalID: proposal.proposalID,
                review: try VoiceProposalFieldReviewV1(
                    fieldID: "note", disposition: .edit, reviewedValue: .text("Different")
                )
            )
            XCTFail("same field ID with different review bytes must be rejected")
        } catch {
            XCTAssertEqual(error as? VoiceProposalReviewCoordinatorFailureV1, .divergentFieldReplay)
        }

        let casTranscript = "note: CAS"
        let casContext = try C56VoiceTestSupport.context(transcript: casTranscript)
        let casProposal = try C56VoiceTestSupport.oneFieldProposal(
            grammar: grammar,
            context: casContext,
            transcript: casTranscript,
            proposalID: C56VoiceTestSupport.id(305)
        )
        let casHarness = try C56VoiceDraftHarness(seed: 560_202)
        let casAuthority = C56VoiceAuthorityProbe(
            grammar: grammar, context: casContext,
            frontierStore: casHarness.frontierStore,
            generationID: casHarness.writer.generationID
        )
        let casCoordinator = VoiceProposalReviewCoordinatorV1(
            authority: casAuthority,
            draftCheckpointBridge: casHarness.bridge,
            scratchCleaner: C56VoiceScratchProbe()
        )
        try await casCoordinator.begin(proposal: casProposal)
        casHarness.payloadApplying.mode = .unchanged
        let casReview = try VoiceProposalFieldReviewV1(
            fieldID: "note", disposition: .accept, reviewedValue: .text("CAS")
        )
        do {
            _ = try await casCoordinator.reviewField(
                proposalID: casProposal.proposalID,
                review: casReview
            )
            XCTFail("unchanged payload must be rejected")
        } catch {
            XCTAssertNotNil(error)
        }
        casHarness.payloadApplying.mode = .normal
        _ = try await casCoordinator.reviewField(
            proposalID: casProposal.proposalID,
            review: casReview
        )
        XCTAssertEqual(casHarness.writer.receipts.count, 1)
        let casPersisted = try casHarness.payloadApplying.decoded(casHarness.writer.checkpoint)
        XCTAssertEqual(casPersisted.fields["note"], "TEXT|CAS")
        casHarness.payloadApplying.mode = .wrongClaimedValue
        let wrongTranscript = "note: wrong"
        let wrongContext = try C56VoiceTestSupport.context(transcript: wrongTranscript)
        let wrongProposal = try C56VoiceTestSupport.oneFieldProposal(
            grammar: grammar,
            context: wrongContext,
            transcript: wrongTranscript,
            proposalID: C56VoiceTestSupport.id(306)
        )
        let wrongAuthority = C56VoiceAuthorityProbe(
            grammar: grammar, context: wrongContext,
            frontierStore: casHarness.frontierStore,
            generationID: casHarness.writer.generationID
        )
        let wrongCoordinator = VoiceProposalReviewCoordinatorV1(
            authority: wrongAuthority,
            draftCheckpointBridge: casHarness.bridge,
            scratchCleaner: C56VoiceScratchProbe()
        )
        try await wrongCoordinator.begin(proposal: wrongProposal)
        do {
            _ = try await wrongCoordinator.reviewField(
                proposalID: wrongProposal.proposalID,
                review: try VoiceProposalFieldReviewV1(
                    fieldID: "note", disposition: .accept, reviewedValue: .text("wrong")
                )
            )
            XCTFail("claimed value mismatch must be rejected")
        } catch {
            XCTAssertNotNil(error)
        }

        let priorityAlias = try VoiceStructuringAliasV1(
            spokenAlias: "priority",
            fieldID: "finding.priority",
            fieldKind: .allowedEnum,
            allowedEnumWords: ["high", "low"]
        )
        let enumGrammar = try VoiceStructuringGrammarReleaseV1(
            grammarID: "C56_ENUM_HOSTILE",
            version: 1,
            localeIdentifier: grammar.localeIdentifier,
            aliases: grammar.aliases + [priorityAlias],
            releasedAt: C56VoiceTestSupport.fixedDate
        )
        let enumService = try C56VoiceTestSupport.service(
            grammar: enumGrammar,
            ids: [C56VoiceTestSupport.id(309)]
        )
        let enumTranscript = "condition: good"
        let enumContext = try C56VoiceTestSupport.context(transcript: enumTranscript)
        let enumProposal = try enumService.structure(
            transcript: enumTranscript,
            context: enumContext
        )
        let enumHarness = try C56VoiceDraftHarness(seed: 560_205)
        let enumCoordinator = VoiceProposalReviewCoordinatorV1(
            authority: C56VoiceAuthorityProbe(
                grammar: enumGrammar,
                context: enumContext,
                frontierStore: enumHarness.frontierStore,
                generationID: enumHarness.writer.generationID
            ),
            draftCheckpointBridge: enumHarness.bridge,
            scratchCleaner: C56VoiceScratchProbe()
        )
        try await enumCoordinator.begin(proposal: enumProposal)
        for hostileValue in ["invented_state", "high"] {
            do {
                _ = try await enumCoordinator.reviewField(
                    proposalID: enumProposal.proposalID,
                    review: try VoiceProposalFieldReviewV1(
                        fieldID: "finding.condition",
                        disposition: .edit,
                        reviewedValue: .allowedEnum(hostileValue)
                    )
                )
                XCTFail("enum edit outside the condition release must not reach C36")
            } catch {
                XCTAssertTrue(error is VoiceStructuringFailureV1)
            }
        }
        XCTAssertTrue(enumHarness.writer.receipts.isEmpty)
        XCTAssertTrue(enumHarness.payloadApplying.applications.isEmpty)
        _ = try await enumCoordinator.reviewField(
            proposalID: enumProposal.proposalID,
            review: try VoiceProposalFieldReviewV1(
                fieldID: "finding.condition",
                disposition: .edit,
                reviewedValue: .allowedEnum("poor")
            )
        )
        XCTAssertEqual(enumHarness.writer.receipts.count, 1)
        XCTAssertEqual(
            try enumHarness.payloadApplying.decoded(enumHarness.writer.checkpoint).fields[
                "finding.condition"
            ],
            "ENUM|poor"
        )

        let generationTranscript = "note: Generation"
        let generationContext = try C56VoiceTestSupport.context(transcript: generationTranscript)
        let generationProposal = try C56VoiceTestSupport.oneFieldProposal(
            grammar: grammar, context: generationContext,
            transcript: generationTranscript, proposalID: C56VoiceTestSupport.id(307)
        )
        let generationHarness = try C56VoiceDraftHarness(seed: 560_203)
        let generationAuthority = C56VoiceAuthorityProbe(
            grammar: grammar, context: generationContext,
            frontierStore: generationHarness.frontierStore,
            generationID: generationHarness.writer.generationID
        )
        let generationScratch = C56VoiceScratchProbe()
        let generationCoordinator = VoiceProposalReviewCoordinatorV1(
            authority: generationAuthority,
            draftCheckpointBridge: generationHarness.bridge,
            scratchCleaner: generationScratch
        )
        try await generationCoordinator.begin(proposal: generationProposal)
        generationAuthority.generationID = C56VoiceTestSupport.id(308)
        do {
            _ = try await generationCoordinator.reviewField(
                proposalID: generationProposal.proposalID,
                review: try VoiceProposalFieldReviewV1(
                    fieldID: "note", disposition: .accept, reviewedValue: .text("Generation")
                )
            )
            XCTFail("generation change must revoke the active proposal")
        } catch {
            XCTAssertEqual(error as? VoiceProposalReviewCoordinatorFailureV1, .staleGeneration)
        }
        XCTAssertEqual(generationScratch.calls.count, 1)

        let targetTranscript = "note: target revision"
        let targetContext = try C56VoiceTestSupport.context(transcript: targetTranscript)
        let targetProposal = try C56VoiceTestSupport.oneFieldProposal(
            grammar: grammar,
            context: targetContext,
            transcript: targetTranscript,
            proposalID: C56VoiceTestSupport.id(310)
        )
        let targetHarness = try C56VoiceDraftHarness(seed: 560_206)
        let targetAuthority = C56VoiceAuthorityProbe(
            grammar: grammar,
            context: targetContext,
            frontierStore: targetHarness.frontierStore,
            generationID: targetHarness.writer.generationID
        )
        let targetScratch = C56VoiceScratchProbe()
        let targetCoordinator = VoiceProposalReviewCoordinatorV1(
            authority: targetAuthority,
            draftCheckpointBridge: targetHarness.bridge,
            scratchCleaner: targetScratch
        )
        try await targetCoordinator.begin(proposal: targetProposal)
        let advancedTargetContext = try VoiceProposalContextV1(
            capability: targetContext.capability,
            workspaceID: targetContext.workspaceID,
            entity: targetContext.entity,
            targetRevision: targetContext.targetRevision + 1,
            source: targetContext.source,
            packageReleaseSHA256: targetContext.packageReleaseSHA256,
            definitionReleaseSHA256: targetContext.definitionReleaseSHA256
        )
        targetAuthority.context = advancedTargetContext
        do {
            _ = try await targetCoordinator.reviewField(
                proposalID: targetProposal.proposalID,
                review: try VoiceProposalFieldReviewV1(
                    fieldID: "note",
                    disposition: .accept,
                    reviewedValue: targetProposal.fields[0].proposedValue
                )
            )
            XCTFail("target revision drift must reject review")
        } catch {
            XCTAssertEqual(error as? VoiceStructuringFailureV1, .expired)
        }
        do {
            _ = try await targetCoordinator.finalize(proposalID: targetProposal.proposalID)
            XCTFail("target revision drift must reject finalize")
        } catch {
            XCTAssertEqual(error as? VoiceProposalReviewCoordinatorFailureV1, .proposalNotFound)
        }
        XCTAssertTrue(targetHarness.writer.receipts.isEmpty)
        XCTAssertTrue(targetHarness.payloadApplying.applications.isEmpty)
        XCTAssertEqual(targetScratch.calls.count, 1)
        XCTAssertEqual(targetScratch.calls[0].0, targetProposal.proposalID)
        XCTAssertEqual(targetScratch.calls[0].1, [targetContext.source])
        let targetPlan = try await targetCoordinator.reviewPlan(proposalID: targetProposal.proposalID)
        XCTAssertNil(targetPlan)
    }

    func testV23P03C56I01InterruptionAdmissionEraseAndNonpersistentLifecycleRemainClosed() async throws {
        let corpus = try corpus()
        let grammar = try grammar(corpus)
        let transcript = "note: lifecycle"
        let context = try C56VoiceTestSupport.context(transcript: transcript)
        let proposal = try C56VoiceTestSupport.oneFieldProposal(
            grammar: grammar, context: context,
            transcript: transcript, proposalID: C56VoiceTestSupport.id(401)
        )
        let service = try C56VoiceTestSupport.service(grammar: grammar)
        let harness = try C56VoiceDraftHarness(seed: 560_301)
        let authority = C56VoiceAuthorityProbe(
            grammar: grammar, context: context,
            frontierStore: harness.frontierStore,
            generationID: harness.writer.generationID
        )
        let scratch = C56VoiceScratchProbe()
        scratch.failuresRemaining = 1
        let admission = C56VoiceAdmissionProbe()
        let adapter = VoiceStructuringLifecycleAdapterV1(
            trustedState: authority,
            drafts: harness.drafts,
            payloadApplying: harness.payloadApplying,
            scratchCleaner: scratch,
            admission: admission,
            authenticator: service
        )
        try await adapter.present(
            proposal,
            admission: try C56VoiceTestSupport.admission(
                proposal: proposal, operation: .present, slot: 401
            )
        )
        do {
            try await adapter.cancel(
                proposalID: proposal.proposalID,
                admission: try C56VoiceTestSupport.admission(
                    proposal: proposal, operation: .cancel, slot: 402
                )
            )
            XCTFail("cleanup failure must remain observable")
        } catch {
            XCTAssertEqual(error as? C56VoiceScratchProbe.Failure, .interrupted)
        }
        try await adapter.cancel(
            proposalID: proposal.proposalID,
            admission: try C56VoiceTestSupport.admission(
                proposal: proposal, operation: .cancel, slot: 403
            )
        )
        XCTAssertEqual(scratch.calls.count, 2)
        XCTAssertTrue(scratch.calls.allSatisfy { $0.1 == [context.source] })
        XCTAssertTrue(harness.writer.receipts.isEmpty)

        let admissionFailureTranscript = "note: admission failure"
        let admissionFailureContext = try C56VoiceTestSupport.context(
            transcript: admissionFailureTranscript
        )
        let admissionFailureProposal = try C56VoiceTestSupport.oneFieldProposal(
            grammar: grammar,
            context: admissionFailureContext,
            transcript: admissionFailureTranscript,
            proposalID: C56VoiceTestSupport.id(408)
        )
        let admissionFailureHarness = try C56VoiceDraftHarness(seed: 560_305)
        let admissionFailureScratch = C56VoiceScratchProbe()
        let admissionFailureAdmission = C56VoiceAdmissionProbe()
        admissionFailureAdmission.failuresRemaining = 1
        let admissionFailureAdapter = VoiceStructuringLifecycleAdapterV1(
            trustedState: C56VoiceAuthorityProbe(
                grammar: grammar,
                context: admissionFailureContext,
                frontierStore: admissionFailureHarness.frontierStore,
                generationID: admissionFailureHarness.writer.generationID
            ),
            drafts: admissionFailureHarness.drafts,
            payloadApplying: admissionFailureHarness.payloadApplying,
            scratchCleaner: admissionFailureScratch,
            admission: admissionFailureAdmission,
            authenticator: service
        )
        do {
            try await admissionFailureAdapter.present(
                admissionFailureProposal,
                admission: try C56VoiceTestSupport.admission(
                    proposal: admissionFailureProposal,
                    operation: .present,
                    slot: 408
                )
            )
            XCTFail("admission failure must not retain a proposal")
        } catch {
            XCTAssertEqual(error as? C56VoiceScratchProbe.Failure, .interrupted)
        }
        XCTAssertTrue(admissionFailureHarness.writer.receipts.isEmpty)
        XCTAssertTrue(admissionFailureHarness.payloadApplying.applications.isEmpty)
        XCTAssertEqual(admissionFailureScratch.calls.count, 1)
        XCTAssertEqual(admissionFailureScratch.calls[0].0, admissionFailureProposal.proposalID)
        XCTAssertEqual(admissionFailureScratch.calls[0].1, [admissionFailureContext.source])
        try await admissionFailureAdapter.present(
            admissionFailureProposal,
            admission: try C56VoiceTestSupport.admission(
                proposal: admissionFailureProposal,
                operation: .present,
                slot: 409
            )
        )
        try await admissionFailureAdapter.cancel(
            proposalID: admissionFailureProposal.proposalID,
            admission: try C56VoiceTestSupport.admission(
                proposal: admissionFailureProposal,
                operation: .cancel,
                slot: 410
            )
        )
        XCTAssertEqual(admissionFailureScratch.calls.count, 2)
        XCTAssertTrue(admissionFailureHarness.writer.receipts.isEmpty)
        XCTAssertEqual(admissionFailureScratch.calls[1].0, admissionFailureProposal.proposalID)
        XCTAssertEqual(admissionFailureScratch.calls[1].1, [admissionFailureContext.source])

        let authenticatorFailureTranscript = "note: authenticator failure"
        let authenticatorFailureContext = try C56VoiceTestSupport.context(
            transcript: authenticatorFailureTranscript
        )
        let authenticatorFailureProposal = try C56VoiceTestSupport.oneFieldProposal(
            grammar: grammar,
            context: authenticatorFailureContext,
            transcript: authenticatorFailureTranscript,
            proposalID: C56VoiceTestSupport.id(411)
        )
        let forgedField = try StructuredVoiceFieldProposalV1(
            fieldID: "note",
            kind: .noteText,
            sourceSpan: authenticatorFailureProposal.fields[0].sourceSpan,
            resolution: .exact,
            proposedValue: .text("forged authenticator value")
        )
        let authenticatorFailureCandidate = try StructuredVoiceProposalV1(
            proposalID: authenticatorFailureProposal.proposalID,
            grammar: grammar,
            context: authenticatorFailureContext,
            transcript: authenticatorFailureTranscript,
            fields: [forgedField],
            unmatchedClauses: [],
            createdAt: authenticatorFailureProposal.createdAt,
            expiresAt: authenticatorFailureProposal.expiresAt
        )
        let authenticatorFailureHarness = try C56VoiceDraftHarness(seed: 560_306)
        let authenticatorFailureScratch = C56VoiceScratchProbe()
        let authenticatorFailureAdmission = C56VoiceAdmissionProbe()
        let authenticatorFailureAdapter = VoiceStructuringLifecycleAdapterV1(
            trustedState: C56VoiceAuthorityProbe(
                grammar: grammar,
                context: authenticatorFailureContext,
                frontierStore: authenticatorFailureHarness.frontierStore,
                generationID: authenticatorFailureHarness.writer.generationID
            ),
            drafts: authenticatorFailureHarness.drafts,
            payloadApplying: authenticatorFailureHarness.payloadApplying,
            scratchCleaner: authenticatorFailureScratch,
            admission: authenticatorFailureAdmission,
            authenticator: service
        )
        do {
            try await authenticatorFailureAdapter.present(
                authenticatorFailureCandidate,
                admission: try C56VoiceTestSupport.admission(
                    proposal: authenticatorFailureCandidate,
                    operation: .present,
                    slot: 411
                )
            )
            XCTFail("deterministic authentication failure must stop before C36")
        } catch {
            XCTAssertEqual(error as? VoiceStructuringFailureV1, .invalidDigest)
        }
        XCTAssertTrue(authenticatorFailureHarness.writer.receipts.isEmpty)
        XCTAssertTrue(authenticatorFailureHarness.payloadApplying.applications.isEmpty)
        XCTAssertEqual(authenticatorFailureScratch.calls.count, 1)
        XCTAssertEqual(
            authenticatorFailureScratch.calls[0].0,
            authenticatorFailureCandidate.proposalID
        )
        XCTAssertEqual(
            authenticatorFailureScratch.calls[0].1,
            [authenticatorFailureContext.source]
        )
        try await authenticatorFailureAdapter.present(
            authenticatorFailureProposal,
            admission: try C56VoiceTestSupport.admission(
                proposal: authenticatorFailureProposal,
                operation: .present,
                slot: 412
            )
        )
        try await authenticatorFailureAdapter.cancel(
            proposalID: authenticatorFailureProposal.proposalID,
            admission: try C56VoiceTestSupport.admission(
                proposal: authenticatorFailureProposal,
                operation: .cancel,
                slot: 413
            )
        )
        XCTAssertEqual(authenticatorFailureScratch.calls.count, 2)
        XCTAssertEqual(
            authenticatorFailureScratch.calls[1].0,
            authenticatorFailureProposal.proposalID
        )
        XCTAssertEqual(
            authenticatorFailureScratch.calls[1].1,
            [authenticatorFailureContext.source]
        )

        let raceTranscript = "note: finalize reset race"
        let raceContext = try C56VoiceTestSupport.context(transcript: raceTranscript)
        let raceProposal = try C56VoiceTestSupport.oneFieldProposal(
            grammar: grammar,
            context: raceContext,
            transcript: raceTranscript,
            proposalID: C56VoiceTestSupport.id(414)
        )
        let raceHarness = try C56VoiceDraftHarness(seed: 560_307)
        let raceAuthority = C56VoiceAuthorityProbe(
            grammar: grammar,
            context: raceContext,
            frontierStore: raceHarness.frontierStore,
            generationID: raceHarness.writer.generationID
        )
        let raceScratch = C56VoiceScratchProbe()
        let raceAdmission = C56VoiceAdmissionProbe()
        let raceAdapter = VoiceStructuringLifecycleAdapterV1(
            trustedState: raceAuthority,
            drafts: raceHarness.drafts,
            payloadApplying: raceHarness.payloadApplying,
            scratchCleaner: raceScratch,
            admission: raceAdmission,
            authenticator: service
        )
        try await raceAdapter.present(
            raceProposal,
            admission: try C56VoiceTestSupport.admission(
                proposal: raceProposal,
                operation: .present,
                slot: 414
            )
        )
        _ = try await raceAdapter.review(
            proposalID: raceProposal.proposalID,
            fieldReview: try VoiceProposalFieldReviewV1(
                fieldID: "note",
                disposition: .accept,
                reviewedValue: raceProposal.fields[0].proposedValue
            ),
            admission: try C56VoiceTestSupport.admission(
                proposal: raceProposal,
                operation: .review,
                slot: 415
            )
        )
        raceScratch.pauseNextCall = true
        let raceFinalizeResult = C56VoicePendingResultProbe()
        let raceResetResult = C56VoicePendingResultProbe()
        let raceFinalizeTask = Task { @MainActor in
            do {
                _ = try await raceAdapter.finalizeReview(
                    proposalID: raceProposal.proposalID,
                    admission: try C56VoiceTestSupport.admission(
                        proposal: raceProposal,
                        operation: .finalize,
                        slot: 416
                    )
                )
            } catch {
                raceFinalizeResult.record(error)
            }
        }
        for _ in 0..<128 where !raceScratch.scratchPaused {
            await Task.yield()
        }
        XCTAssertTrue(raceScratch.scratchPaused)
        let raceResetTask = Task { @MainActor in
            do {
                try await raceAdapter.handleWorkspaceEraseOrReset(
                    workspaceID: raceContext.workspaceID,
                    admission: try C56VoiceTestSupport.admission(
                        proposal: nil,
                        operation: .eraseOrReset,
                        slot: 417
                    )
                )
            } catch {
                raceResetResult.record(error)
            }
        }
        for _ in 0..<128 where raceAdmission.calls.count < 4 {
            await Task.yield()
        }
        XCTAssertGreaterThanOrEqual(raceAdmission.calls.count, 4)
        raceScratch.resumePausedCalls()
        await raceFinalizeTask.value
        await raceResetTask.value
        XCTAssertTrue(raceFinalizeResult.errors.contains {
            ($0 as? VoiceProposalReviewCoordinatorFailureV1) == .staleGeneration
        })
        XCTAssertTrue(raceResetResult.errors.isEmpty)
        XCTAssertEqual(raceScratch.calls.count, 1)
        XCTAssertEqual(raceScratch.calls[0].0, raceProposal.proposalID)
        XCTAssertEqual(raceScratch.calls[0].1, [raceContext.source])
        XCTAssertEqual(raceHarness.writer.receipts.count, 1)

        let resetTranscript = "note: reset"
        let resetContext = try C56VoiceTestSupport.context(transcript: resetTranscript)
        let resetProposal = try C56VoiceTestSupport.oneFieldProposal(
            grammar: grammar, context: resetContext,
            transcript: resetTranscript, proposalID: C56VoiceTestSupport.id(404)
        )
        let resetService = try C56VoiceTestSupport.service(grammar: grammar)
        let resetHarness = try C56VoiceDraftHarness(seed: 560_302)
        let resetScratch = C56VoiceScratchProbe()
        resetScratch.failuresRemaining = 1
        let resetAdmission = C56VoiceAdmissionProbe()
        let resetAdapter = VoiceStructuringLifecycleAdapterV1(
            trustedState: C56VoiceAuthorityProbe(
                grammar: grammar, context: resetContext,
                frontierStore: resetHarness.frontierStore,
                generationID: resetHarness.writer.generationID
            ),
            drafts: resetHarness.drafts,
            payloadApplying: resetHarness.payloadApplying,
            scratchCleaner: resetScratch,
            admission: resetAdmission,
            authenticator: resetService
        )
        try await resetAdapter.present(
            resetProposal,
            admission: try C56VoiceTestSupport.admission(
                proposal: resetProposal, operation: .present, slot: 404
            )
        )
        do {
            try await resetAdapter.handleWorkspaceEraseOrReset(
                workspaceID: resetContext.workspaceID,
                admission: try C56VoiceTestSupport.admission(
                    proposal: nil, operation: .eraseOrReset, slot: 405
                )
            )
            XCTFail("erase cleanup failure must be retryable")
        } catch {
            XCTAssertEqual(error as? C56VoiceScratchProbe.Failure, .interrupted)
        }
        try await resetAdapter.handleWorkspaceEraseOrReset(
            workspaceID: resetContext.workspaceID,
            admission: try C56VoiceTestSupport.admission(
                proposal: nil, operation: .eraseOrReset, slot: 406
            )
        )
        XCTAssertEqual(resetScratch.calls.count, 2)
        XCTAssertTrue(resetScratch.calls.allSatisfy { $0.1 == [resetContext.source] })

        let pendingTranscript = "note: pending"
        let pendingContext = try C56VoiceTestSupport.context(transcript: pendingTranscript)
        let pendingProposal = try C56VoiceTestSupport.oneFieldProposal(
            grammar: grammar, context: pendingContext,
            transcript: pendingTranscript, proposalID: C56VoiceTestSupport.id(407)
        )
        let pendingHarness = try C56VoiceDraftHarness(seed: 560_303)
        let pendingAuthority = C56VoiceAuthorityProbe(
            grammar: grammar, context: pendingContext,
            frontierStore: pendingHarness.frontierStore,
            generationID: pendingHarness.writer.generationID
        )
        pendingAuthority.pauseNextSnapshot = true
        let pendingScratch = C56VoiceScratchProbe()
        let pendingCoordinator = VoiceProposalReviewCoordinatorV1(
            authority: pendingAuthority,
            draftCheckpointBridge: pendingHarness.bridge,
            scratchCleaner: pendingScratch
        )
        let pendingResult = C56VoicePendingResultProbe()
        let pendingTask = Task { @MainActor in
            do {
                try await pendingCoordinator.begin(proposal: pendingProposal)
            } catch {
                pendingResult.record(error)
            }
        }
        for _ in 0..<64 where !pendingAuthority.snapshotPaused {
            await Task.yield()
        }
        XCTAssertTrue(pendingAuthority.snapshotPaused)
        try await pendingCoordinator.handleWorkspaceEraseOrReset(
            workspaceID: pendingContext.workspaceID
        )
        pendingAuthority.resumePausedSnapshots()
        await pendingTask.value
        XCTAssertTrue(pendingResult.errors.contains {
            ($0 as? VoiceProposalReviewCoordinatorFailureV1) == .staleGeneration
        })
        XCTAssertEqual(pendingScratch.calls.count, 1)

        let manyIDs = (0..<129).map { C56VoiceTestSupport.id(500 + $0) }
        let manyService = try C56VoiceTestSupport.service(grammar: grammar, ids: manyIDs)
        let manyTranscript = "note: admission"
        let manyContext = try C56VoiceTestSupport.context(transcript: manyTranscript)
        let manyHarness = try C56VoiceDraftHarness(seed: 560_304)
        let manyAuthority = C56VoiceAuthorityProbe(
            grammar: grammar, context: manyContext,
            frontierStore: manyHarness.frontierStore,
            generationID: manyHarness.writer.generationID
        )
        manyAuthority.pauseAllSnapshots = true
        let manyScratch = C56VoiceScratchProbe()
        let manyCoordinator = VoiceProposalReviewCoordinatorV1(
            authority: manyAuthority,
            draftCheckpointBridge: manyHarness.bridge,
            scratchCleaner: manyScratch
        )
        let manyResults = C56VoicePendingResultProbe()
        var manyTasks: [Task<Void, Never>] = []
        for slot in 0..<129 {
            let candidate = try manyService.structure(
                transcript: manyTranscript,
                context: manyContext
            )
            manyTasks.append(Task { @MainActor in
                do {
                    try await manyCoordinator.begin(proposal: candidate)
                } catch {
                    manyResults.record(error)
                }
            })
            _ = slot
        }
        for _ in 0..<256 where manyAuthority.pausedSnapshotCount < 128 {
            await Task.yield()
        }
        XCTAssertGreaterThanOrEqual(manyAuthority.pausedSnapshotCount, 128)
        XCTAssertTrue(manyResults.errors.contains {
            ($0 as? VoiceProposalReviewCoordinatorFailureV1) == .activeProposalLimitExceeded
        })
        manyAuthority.resumePausedSnapshots()
        for task in manyTasks { await task.value }
        try await manyCoordinator.handleWorkspaceEraseOrReset(workspaceID: manyContext.workspaceID)
        XCTAssertEqual(manyScratch.calls.count, 128)
        XCTAssertEqual(VoiceStructuringNonpersistentLifecycleV1.persistentFamilyCount, 0)
        XCTAssertFalse(VoiceStructuringNonpersistentLifecycleV1.canonicalWritePermitted)
        XCTAssertFalse(VoiceStructuringNonpersistentLifecycleV1.backupSearchReportJournalEnrollmentPermitted)
        XCTAssertTrue(VoiceStructuringNonpersistentLifecycleV1.scratchDeletedAfterReviewExpiryOrCancellation)
        XCTAssertTrue(VoiceStructuringNonpersistentLifecycleV1.reusesAssistanceContextAndLifecycleAuthority)
    }

    func testV23P03C56R01CanonicalRecoveryAndPersistenceClosureRemainDeterministic() async throws {
        let corpus = try corpus()
        try assertCorpusHeader(corpus)
        let grammar = try grammar(corpus)
        let registry = try C56VoiceTestSupport.registry(for: grammar)
        let registryBytes = try VoiceStructuringCanonicalCodecV1.encode(registry)
        let restoredRegistry = try VoiceStructuringCanonicalCodecV1.decode(
            VoiceStructuringGrammarRegistryV1.self,
            from: registryBytes
        )
        XCTAssertEqual(restoredRegistry, registry)
        XCTAssertEqual(
            try restoredRegistry.resolve(
                grammarID: grammar.grammarID,
                version: grammar.version,
                localeIdentifier: grammar.localeIdentifier,
                releaseSHA256: try grammar.releaseSHA256
            ),
            grammar
        )
        XCTAssertThrowsError(
            try restoredRegistry.resolve(
                grammarID: grammar.grammarID,
                version: grammar.version,
                localeIdentifier: grammar.localeIdentifier,
                releaseSHA256: String(repeating: "f", count: 64)
            )
        )

        let transcript = "note: Stable"
        let context = try C56VoiceTestSupport.context(transcript: transcript)
        let firstService = try C56VoiceTestSupport.service(
            grammar: grammar, ids: [C56VoiceTestSupport.id(501)]
        )
        let secondService = try C56VoiceTestSupport.service(
            grammar: grammar, ids: [C56VoiceTestSupport.id(501)]
        )
        let first = try firstService.structure(transcript: transcript, context: context)
        let second = try secondService.structure(transcript: transcript, context: context)
        XCTAssertEqual(first, second)
        XCTAssertEqual(try first.proposalSHA256, try second.proposalSHA256)
        let proposalBytes = try VoiceStructuringCanonicalCodecV1.encode(first)
        let recoveredProposal = try VoiceStructuringCanonicalCodecV1.decodeProposal(
            from: proposalBytes,
            registry: registry,
            currentContext: context,
            at: C56VoiceTestSupport.fixedDate.addingTimeInterval(1)
        )
        XCTAssertEqual(recoveredProposal, first)

        let harness = try C56VoiceDraftHarness(seed: 560_401)
        let authority = C56VoiceAuthorityProbe(
            grammar: grammar, context: context,
            frontierStore: harness.frontierStore,
            generationID: harness.writer.generationID
        )
        let scratch = C56VoiceScratchProbe()
        let coordinator = VoiceProposalReviewCoordinatorV1(
            authority: authority,
            draftCheckpointBridge: harness.bridge,
            scratchCleaner: scratch
        )
        try await coordinator.begin(proposal: first)
        let note = try XCTUnwrap(first.fields.first { $0.fieldID == "note" })
        _ = try await coordinator.reviewField(
            proposalID: first.proposalID,
            review: try VoiceProposalFieldReviewV1(
                fieldID: "note", disposition: .accept, reviewedValue: note.proposedValue
            )
        )
        let plan = try await coordinator.finalize(proposalID: first.proposalID)
        let planReplay = try await coordinator.reviewPlan(proposalID: first.proposalID)
        XCTAssertEqual(planReplay, plan)
        let planBytes = try VoiceStructuringCanonicalCodecV1.encode(plan)
        let recoveredPlan = try VoiceStructuringCanonicalCodecV1.decodeReviewPlan(
            from: planBytes,
            proposal: first,
            registry: registry,
            currentContext: context,
            at: C56VoiceTestSupport.fixedDate.addingTimeInterval(2)
        )
        XCTAssertEqual(recoveredPlan, plan)

        XCTAssertEqual(corpus.persistence.mode, "NONPERSISTENT_PROPOSAL_EXISTING_C36_DRAFT_ACCEPTANCE")
        XCTAssertEqual(corpus.persistence.proposal, "NONPERSISTENT")
        XCTAssertEqual(corpus.persistence.scratchAudio, "NONPERSISTENT_DELETE_ON_TERMINAL_DISPOSITION")
        XCTAssertEqual(corpus.persistence.acceptedFieldCheckpoint, "P03-C36_EXISTING_DRAFT_CHECKPOINT_AND_WRITER")
        XCTAssertTrue(corpus.persistence.persistentSchemaVersionUnchanged)
        XCTAssertTrue(corpus.persistence.recordsSchemaVersionUnchanged)
        XCTAssertEqual(corpus.persistence.durableFamilyCount, 0)
        XCTAssertTrue(corpus.persistence.durableFamilies.isEmpty)
        XCTAssertEqual(corpus.persistence.newPersistentModelCount, 0)
        XCTAssertEqual(corpus.persistence.backup, "PROPOSAL_EXCLUDED_ACCEPTED_DRAFT_USES_EXISTING_C36_LIFECYCLE")
        XCTAssertEqual(corpus.persistence.restore, corpus.persistence.backup)
        XCTAssertEqual(corpus.persistence.cloneFork, "PROPOSAL_INVALIDATED_DRAFT_AUTHORITY_REMAINS_C36")
        XCTAssertEqual(corpus.persistence.importExport, "NO_PROPOSAL_EXPORT")
        XCTAssertEqual(corpus.persistence.journalReplay, "NO_PROPOSAL_JOURNAL_ROW")
        XCTAssertEqual(corpus.persistence.search, "EXCLUDED")
        XCTAssertEqual(corpus.persistence.report, "EXCLUDED")
        XCTAssertEqual(corpus.persistence.deleteErase, "SCRATCH_DELETED_PROPOSAL_DISCARDED")
        XCTAssertEqual(corpus.persistence.retention, "NO_AUDIO_RETENTION")
        XCTAssertEqual(harness.payloadApplying.applications.count, 1)
        let persisted = try harness.payloadApplying.decoded(harness.writer.checkpoint)
        XCTAssertEqual(persisted.fields["note"], "TEXT|Stable")
        XCTAssertEqual(scratch.calls.count, 1)
        XCTAssertEqual(scratch.calls[0].1, [context.source])
    }
}

import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

private enum C02EvidenceCurationTestFailure: Error {
    case missingDigest
    case malformedFixture
}

private struct C02EvidenceCurationCorpusV1: Decodable {
    let schema: String
    let schemaVersion: Int
    let cardID: String
    let ordinal: Int
    let contentMode: String
    let selectors: [Selector]
    let limits: Limits
    let eligibleStates: [String]
    let previewStates: [String]
    let comparison: Comparison
    let privacy: Privacy
    let visual: Visual
    let hostileCases: [String]
    let interruptionBoundaries: [String]
    let recoveryCases: [String]
    let lifecycle: Lifecycle
    let forbidden: [String]
    let uiAdoptionEnabled: Bool

    struct Selector: Decodable {
        let id: String
        let selector: String
        let tier: String
    }

    struct Limits: Decodable {
        let maximumSelectionCount: Int
        let maximumComparisonCount: Int
        let maximumAnnotations: Int
        let maximumAnnotationTextBytes: Int
        let maximumSequenceFrames: Int
        let maximumContactSheetColumns: Int
        let maximumSourceBytes: Int64
        let maximumTotalSourceBytes: Int64
    }

    struct Comparison: Decodable {
        let modes: [String]
        let advisoryText: String
        let comparisonIsProof: Bool
    }

    struct Privacy: Decodable {
        let originalRole: String
        let derivativeRole: String
        let transformBeforeMarkup: Bool
        let confirmationRequiresExactBytes: Bool
        let detectorPass: String
        let detectorBlock: String
        let forbiddenAudienceFields: [String]
    }

    struct Visual: Decodable {
        let sourceMediaType: String
        let derivativeMediaType: String
        let flickerWidth: Int
        let flickerHeight: Int
        let contactSheetWidth: Int
        let contactSheetHeight: Int
        let contactSheetColumns: Int
        let flickerFrameCount: Int
        let maximumDerivativeBytes: Int
        let orientationAndColorCanonicalized: Bool
    }

    struct Lifecycle: Decodable {
        let persistence: String
        let plansAndProjectionsAreNonpersistent: Bool
        let schema: String
        let migration: String
        let backupRestore: String
        let cloneFork: String
        let journalReplay: String
        let searchRebuild: String
        let deleteErase: String
        let exportReport: String
        let comparisonIsProof: Bool
        let createsContentStore: Bool
    }
}

private func c02PNGDimensions(_ data: Data) -> (Int, Int)? {
    guard data.count >= 24,
          Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10] else {
        return nil
    }
    func uint32(_ offset: Int) -> Int {
        Int(data[offset]) << 24
            | Int(data[offset + 1]) << 16
            | Int(data[offset + 2]) << 8
            | Int(data[offset + 3])
    }
    guard uint32(8) == 13, String(decoding: data[12..<16], as: UTF8.self) == "IHDR" else {
        return nil
    }
    return (uint32(16), uint32(20))
}

private func c02PNGHasChunk(_ data: Data, _ expectedType: String) -> Bool {
    guard data.count >= 8,
          Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10] else {
        return false
    }
    var offset = 8
    while offset + 12 <= data.count {
        let length = Int(data[offset]) << 24
            | Int(data[offset + 1]) << 16
            | Int(data[offset + 2]) << 8
            | Int(data[offset + 3])
        guard length >= 0, offset + 12 + length <= data.count else { return false }
        let type = String(decoding: data[(offset + 4)..<(offset + 8)], as: UTF8.self)
        if type == expectedType { return true }
        offset += 12 + length
    }
    return false
}

private struct C02SourceFixture {
    let bytes: Data
    let reference: ContentReferenceV1
    let provenance: ContentOriginalProvenanceV1
}

private struct C02CurationFixture {
    let workspace: WorkspaceID
    let sources: [C02SourceFixture]
    let associations: [EvidenceAssociationV1]
    let sequenceHistory: [EvidenceSequenceV1]
    let currentSequence: EvidenceSequenceV1

    var references: [ContentReferenceV1] { sources.map(\.reference) }
    var originalProvenance: [ContentOriginalProvenanceV1] { sources.map(\.provenance) }
}

private func makeC02SequenceHistory(
    workspace: WorkspaceID,
    associations: [EvidenceAssociationV1]
) throws -> [EvidenceSequenceV1] {
    guard let target = associations.first?.target else {
        throw C02EvidenceCurationTestFailure.malformedFixture
    }
    let policy = try EvidenceCurationPolicyV1(
        policyID: UUID(uuidString: "c0200000-0000-4000-8000-0000000000b1")!,
        workspaceID: workspace
    )
    let actorReference = try LocalActorReferenceV1(
        actorReferenceID: UUID(uuidString: "c0200000-0000-4000-8000-0000000000b2")!,
        workspaceID: workspace,
        displayName: "C02 reviewer"
    )
    let reviewer = try ActorSnapshotV1(
        snapshotID: UUID(uuidString: "c0200000-0000-4000-8000-0000000000b3")!,
        workspaceID: workspace,
        actor: actorReference,
        responsibility: .reviewedBy,
        displayNameAtTime: "C02 reviewer",
        capturedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
    var history: [EvidenceSequenceV1] = []
    for (offset, association) in associations.enumerated() {
        guard let contentID = association.contentID,
              let mutationUUID = UUID(uuidString: association.mutationID) else {
            throw C02EvidenceCurationTestFailure.malformedFixture
        }
        var items = history.last?.orderedItems ?? []
        let item = try EvidenceSequenceItemV1(
            evidenceID: association.evidenceID,
            contentID: contentID,
            role: .context,
            caption: try EvidenceReviewedCaptionV1(
                text: "C02 source \(offset + 1)",
                provenance: .userAuthored,
                reviewer: reviewer,
                reviewedAt: Date(timeIntervalSince1970: 1_800_000_001 + Double(offset))
            ),
            ordinal: items.count,
            target: target,
            association: association
        )
        items.append(item)
        history.append(try EvidenceSequenceV1(
            sequenceID: UUID(uuidString: "c0200000-0000-4000-8000-0000000000b4")!,
            workspaceID: workspace,
            target: target,
            policy: policy,
            orderedItems: items,
            predecessor: history.last.map { try! $0.reference },
            revision: UInt64(offset + 1),
            mutationID: try MutationIDV1(rawValue: mutationUUID)
        ))
    }
    return history
}

private struct C02PresentationFixture {
    let privacy: C20PrivacyTransformTestSupport.Fixture
    let audiencePolicy: AudiencePrivacyPolicyV1
    let profile: EvidenceDetailCardProfileV1
    let card: EvidenceDetailCardV1
    let bundle: EvidenceDetailPreviewBundleV1
    let semanticTree: AccessibleDocumentSemanticTreeV1
    let accessibilityAssessment: AccessibleDocumentAssessmentReceiptV1
    let composedOutput: Data
    let sourceSnapshotSHA256: String
    let semanticSHA256: String
    let composedOutputSHA256: String
}

private struct C02NullContentResolver: EvidenceCurationContentResolvingV1 {
    func resolve(_ reference: ContentReferenceV1) async throws -> ContentReferenceV1? {
        nil
    }
}

private actor C02ContentResolver: EvidenceCurationContentResolvingV1 {
    private let values: [String: ContentReferenceV1]

    init(values: [String: ContentReferenceV1]) {
        self.values = Dictionary(uniqueKeysWithValues: values.map { ($0.contentID, $0) })
    }

    func resolve(_ reference: ContentReferenceV1) async throws -> ContentReferenceV1? {
        values[reference.contentID]
    }
}

private struct C02FixedClock: ApplicationClock {
    func now() -> Date { Date(timeIntervalSince1970: 1_800_000_100) }
}

private struct C02FixedIDSource: ApplicationIDSource {
    let value: UUID
    func makeID() -> UUID { value }
}

private struct C02FileAuthority: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String {
        "mutation-staging/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

@MainActor
private final class C02WriterBackedCommitter: EvidenceDerivativeCanonicalCommittingV1 {
    private let container: ModelContainer
    private let writer: WorkspaceWriterV1
    private let bridge: WorkspaceEvidenceDerivativeCanonicalCommitterV1
    private var firstCommitIDs = Set<MutationIDV1>()

    init(fixture: C02CurationFixture) throws {
        let schema = Schema(
            PersistentSchemaV43.models,
            version: PersistentSchemaV43.versionIdentifier
        )
        let builtContainer = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                "V23-P04-C02-derivative-writer",
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                cloudKitDatabase: .none
            )]
        )
        self.container = builtContainer
        let context = builtContainer.mainContext
        context.autosaveEnabled = false
        let replicaID = UUID(uuidString: "c0200000-0000-4000-8000-0000000000c0")!
        let generationID = UUID(uuidString: "c0200000-0000-4000-8000-0000000000c1")!
        let writerInstanceID = UUID(uuidString: "c0200000-0000-4000-8000-0000000000c2")!
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: fixture.workspace,
            replicaID: ReplicaID(rawValue: replicaID)
        )
        let journal = try MutationJournalStoreV1(
            modelContext: context,
            identity: identity,
            generationID: generationID
        )
        let builtWriter = try WorkspaceWriterV1(
            identity: identity,
            generationID: generationID,
            initialRevision: journal.currentRevision(writerInstanceID: writerInstanceID),
            clock: C02FixedClock(),
            idSource: C02FixedIDSource(value: writerInstanceID),
            fileAuthority: C02FileAuthority(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context),
            journalStore: journal
        )

        self.writer = builtWriter
        for (association, sequence) in zip(fixture.associations, fixture.sequenceHistory) {
            let mutation = try EvidenceMetadataMutationV1(
                workspaceID: fixture.workspace,
                mutationID: try MutationIDV1(
                    rawValue: XCTUnwrap(UUID(uuidString: association.mutationID))
                ),
                expectedSequenceRevision: sequence.revision - 1,
                associationEvent: association,
                sequenceSuccessor: sequence
            )
            _ = try builtWriter.commitEvidenceMetadata(mutation)
        }
        bridge = WorkspaceEvidenceDerivativeCanonicalCommitterV1(writer: builtWriter)
    }

    func commitDerivativeMetadata(
        _ mutation: EvidenceMetadataMutationV1
    ) async throws -> EvidenceMetadataMutationReceiptV1 {
        if try writer.evidenceMetadataReceipt(for: mutation) == nil {
            firstCommitIDs.insert(mutation.mutationID)
        }
        return try await bridge.commitDerivativeMetadata(mutation)
    }

    func receipt(
        for mutation: EvidenceMetadataMutationV1
    ) async throws -> EvidenceMetadataMutationReceiptV1? {
        try await bridge.receipt(for: mutation)
    }

    func committedCount() -> Int { firstCommitIDs.count }
}

private final class C02CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let threshold: Int
    private var calls = 0

    init(threshold: Int) {
        self.threshold = threshold
    }

    func isCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        calls += 1
        return calls >= threshold
    }
}

final class V9_67EvidenceCurationTests: XCTestCase {
    private static let workspaceUUID = UUID(uuidString: "c0200000-0000-4000-8000-000000000001")!
    private static let foreignWorkspaceUUID = UUID(uuidString: "c0200000-0000-4000-8000-000000000099")!
    private static let fixedInstant = "2026-08-30T00:00:00.000Z"

    func testV23P04C02G01EligibleSelectionAndAdmissionNegatives() throws {
        let corpus = try loadCorpus()
        assertCorpus(corpus, selector: "G01", tier: "GOLDEN")
        XCTAssertEqual(corpus.eligibleStates, ["ELIGIBLE"])
        XCTAssertTrue(corpus.hostileCases.contains("wrong-workspace"))
        XCTAssertTrue(corpus.hostileCases.contains("duplicate-reference"))

        let fixture = try makeFixture()
        let coordinator = EvidenceCurationCoordinatorV1(contentResolver: C02NullContentResolver())
        let selection = try coordinator.eligibleSelection(
            selectionID: "c02-selection-g01",
            workspaceID: fixture.workspace,
            currentSequence: fixture.currentSequence,
            associations: fixture.associations,
            references: fixture.references,
            originalProvenance: fixture.originalProvenance
        )

        XCTAssertEqual(selection.orderedCandidates.count, 2)
        XCTAssertEqual(selection.orderedCandidates.map(\.eligibility), [.eligible, .eligible])
        XCTAssertEqual(
            selection.orderedCandidates.map { $0.reference.contentID },
            ["c02-content-001", "c02-content-002"]
        )
        XCTAssertTrue(selection.orderedCandidates.allSatisfy { $0.reference.byteRole == .immutableOriginal })
        XCTAssertEqual(
            Set(selection.orderedCandidates.map { $0.reference.digests.digest(for: .sha256) }),
            Set(fixture.references.compactMap { $0.digests.digest(for: .sha256) })
        )
        XCTAssertEqual(try EvidenceCurationCanonicalCodecV1.decode(
            EvidenceCurationSelectionV1.self,
            from: EvidenceCurationCanonicalCodecV1.encode(selection)
        ), selection)

        let foreignWorkspace = WorkspaceID(rawValue: Self.foreignWorkspaceUUID)
        let foreignSource = try makeSource(index: 1, workspace: foreignWorkspace)
        let foreignAssociation = try makeAssociation(
            index: 1,
            workspace: foreignWorkspace,
            evidenceID: "c02-foreign-evidence",
            contentID: foreignSource.reference.contentID
        )
        XCTAssertThrowsError(try coordinator.eligibleSelection(
            selectionID: "c02-selection-foreign",
            workspaceID: fixture.workspace,
            currentSequence: fixture.currentSequence,
            associations: [foreignAssociation],
            references: [foreignSource.reference],
            originalProvenance: [foreignSource.provenance]
        )) { error in
            XCTAssertEqual(error as? EvidenceCurationFailureV1, .wrongWorkspace)
        }

        let duplicateAssociation = try makeAssociation(
            index: 3,
            workspace: fixture.workspace,
            evidenceID: "c02-evidence-duplicate",
            contentID: fixture.sources[0].reference.contentID
        )
        XCTAssertThrowsError(try coordinator.eligibleSelection(
            selectionID: "c02-selection-duplicate",
            workspaceID: fixture.workspace,
            currentSequence: fixture.currentSequence,
            associations: fixture.associations + [duplicateAssociation],
            references: fixture.references,
            originalProvenance: fixture.originalProvenance
        )) { error in
            XCTAssertEqual(error as? EvidenceCurationFailureV1, .duplicateReference)
        }

        let removedAssociation = try EvidenceAssociationV1(
            associationEventID: "c02-association-removed",
            workspaceID: fixture.sources[0].reference.workspaceID,
            evidenceID: fixture.associations[0].evidenceID,
            expectedEvidenceRevision: 1,
            resultingEvidenceRevision: 2,
            mutationID: "c02-mutation-remove",
            action: .removed,
            contentID: nil,
            target: nil,
            previousContentID: fixture.associations[0].contentID,
            previousTarget: fixture.associations[0].target,
            supersedesAssociationEventID: fixture.associations[0].associationEventID,
            actorID: "c02-actor",
            reason: "Remove from curation review.",
            effectiveAt: "2026-08-30T00:02:00.000Z"
        )
        XCTAssertThrowsError(try coordinator.eligibleSelection(
            selectionID: "c02-selection-removed",
            workspaceID: fixture.workspace,
            currentSequence: fixture.currentSequence,
            associations: [fixture.associations[0], removedAssociation, fixture.associations[1]],
            references: fixture.references,
            originalProvenance: fixture.originalProvenance
        ))

        let derivative = try makeSource(index: 9, workspace: fixture.workspace, role: .derivative)
        let derivativeAssociation = try makeAssociation(
            index: 9,
            workspace: fixture.workspace,
            evidenceID: "c02-evidence-derivative",
            contentID: derivative.reference.contentID
        )
        XCTAssertThrowsError(try coordinator.eligibleSelection(
            selectionID: "c02-selection-derivative",
            workspaceID: fixture.workspace,
            currentSequence: fixture.currentSequence,
            associations: [derivativeAssociation],
            references: [derivative.reference],
            originalProvenance: [derivative.provenance]
        )) { error in
            XCTAssertEqual(error as? EvidenceCurationFailureV1, .ineligibleReference)
        }

        let missingAssociation = try makeAssociation(
            index: 10,
            workspace: fixture.workspace,
            evidenceID: "c02-evidence-missing",
            contentID: "c02-content-not-present"
        )
        XCTAssertThrowsError(try coordinator.eligibleSelection(
            selectionID: "c02-selection-missing",
            workspaceID: fixture.workspace,
            currentSequence: fixture.currentSequence,
            associations: [missingAssociation],
            references: fixture.references,
            originalProvenance: fixture.originalProvenance
        ))

        let overSelection = Array(repeating: selection.orderedCandidates[0], count: corpus.limits.maximumSelectionCount + 1)
        XCTAssertThrowsError(try EvidenceCurationSelectionV1(
            selectionID: "c02-selection-over-limit",
            workspaceID: fixture.workspace,
            orderedCandidates: overSelection
        )) { error in
            XCTAssertEqual(error as? EvidenceCurationFailureV1, .limitExceeded)
        }
    }

    func testV23P04C02A01VersionPinnedComparisonAndMissingFallback() async throws {
        let corpus = try loadCorpus()
        assertCorpus(corpus, selector: "A01", tier: "ALTERNATE")
        XCTAssertEqual(corpus.previewStates, ["AVAILABLE", "MISSING"])
        XCTAssertEqual(corpus.comparison.comparisonIsProof, false)
        XCTAssertTrue(corpus.comparison.advisoryText.localizedCaseInsensitiveContains("not proof"))

        let fixture = try makeFixture()
        let coordinator = EvidenceCurationCoordinatorV1(
            contentResolver: C02ContentResolver(values: [fixture.references[0]])
        )
        let selection = try coordinator.eligibleSelection(
            selectionID: "c02-selection-a01",
            workspaceID: fixture.workspace,
            currentSequence: fixture.currentSequence,
            associations: fixture.associations,
            references: fixture.references,
            originalProvenance: fixture.originalProvenance
        )
        let derivative = try makeSource(index: 20, workspace: fixture.workspace, role: .derivative)
        let presentation = try makePresentation(
            evidenceID: selection.orderedCandidates[0].evidenceID,
            workspace: fixture.workspace,
            derivative: derivative.reference
        )
        let previews = try await coordinator.previews(
            for: selection,
            detailBundles: [selection.orderedCandidates[0].evidenceID: presentation.bundle],
            missingFallbackText: "Original evidence is unavailable on this device."
        )

        XCTAssertEqual(previews.count, 2)
        XCTAssertEqual(previews[0].availability, .available)
        XCTAssertEqual(previews[0].associationRevision, selection.orderedCandidates[0].associationRevision)
        XCTAssertEqual(previews[0].reference, selection.orderedCandidates[0].reference)
        XCTAssertEqual(previews[0].detailCard, presentation.card)
        XCTAssertEqual(previews[0].availableBundle, presentation.bundle)
        XCTAssertEqual(previews[1].availability, .missing)
        XCTAssertEqual(previews[1].missingFallbackText, "Original evidence is unavailable on this device.")
        XCTAssertNil(previews[1].detailCard)

        let comparison = try coordinator.comparison(
            comparisonID: "c02-comparison-a01",
            workspaceID: fixture.workspace,
            mode: .advisoryOverlay,
            orderedPreviews: previews,
            advisoryKey: .comparisonIsNotProof
        )
        XCTAssertEqual(comparison.mode, .advisoryOverlay)
        XCTAssertFalse(comparison.comparisonIsProof)
        XCTAssertEqual(comparison.orderedPreviews.map(\.associationRevision), [1, 1])
        XCTAssertTrue(KernelCanonicalHashV1.validSHA256(comparison.projectionSHA256))
        XCTAssertEqual(
            try EvidenceCurationCanonicalCodecV1.decode(
                EvidenceComparisonProjectionV1.self,
                from: EvidenceCurationCanonicalCodecV1.encode(comparison)
            ),
            comparison
        )

        let changed = try makeReference(
            workspaceID: fixture.references[0].workspaceID,
            contentID: fixture.references[0].contentID,
            data: Data("c02-content-001-changed".utf8),
            role: .immutableOriginal,
            createdAt: fixture.references[0].createdAt
        )
        let staleCoordinator = EvidenceCurationCoordinatorV1(
            contentResolver: C02ContentResolver(values: [changed])
        )
        do {
            _ = try await staleCoordinator.previews(
                for: selection,
                missingFallbackText: "Fallback"
            )
            XCTFail("A changed immutable reference must not produce a pinned preview")
        } catch {
            XCTAssertEqual(error as? EvidenceCurationFailureV1, .staleReference)
        }
    }

    func testV23P04C02H01PrivacyBeforeMarkupAndReversibleAnnotation() throws {
        let corpus = try loadCorpus()
        assertCorpus(corpus, selector: "H01", tier: "HOSTILE")
        XCTAssertTrue(corpus.privacy.transformBeforeMarkup)
        XCTAssertTrue(corpus.privacy.confirmationRequiresExactBytes)
        XCTAssertEqual(corpus.privacy.detectorPass, "PASS")
        XCTAssertEqual(corpus.privacy.detectorBlock, "BLOCKED")

        let privacy = try C20PrivacyTransformTestSupport.makeFixture()
        let coordinator = EvidenceCurationCoordinatorV1(contentResolver: C02NullContentResolver())
        let add = try EvidenceAnnotationV1(
            annotationID: "c02-annotation-add",
            action: .add,
            text: "Reviewed circle markup"
        )
        let remove = try EvidenceAnnotationV1(
            annotationID: "c02-annotation-remove",
            action: .remove,
            text: "Remove reviewed circle markup",
            supersedesAnnotationID: add.annotationID
        )
        let added = try coordinator.reviewedMarkup(
            markupID: "c02-markup-added",
            workspaceID: privacy.workspace,
            source: privacy.original,
            privacyPolicy: privacy.policy,
            privacyManifest: privacy.manifest,
            privacyReview: privacy.approvedReview,
            orderedAnnotations: [add]
        )
        let removed = try coordinator.reviewedMarkup(
            markupID: "c02-markup-removed",
            workspaceID: privacy.workspace,
            source: privacy.original,
            privacyPolicy: privacy.policy,
            privacyManifest: privacy.manifest,
            privacyReview: privacy.approvedReview,
            orderedAnnotations: [add, remove]
        )

        XCTAssertEqual(added.source, privacy.original)
        XCTAssertEqual(added.privacyReview.decision, .approved)
        XCTAssertEqual(added.privacyManifest.staleState, .current)
        XCTAssertEqual(added.privacyManifest.original.byteRole, .immutableOriginal)
        XCTAssertEqual(added.privacyManifest.derivative.byteRole, .derivative)
        XCTAssertEqual(added.reviewedMarkup.sourcePrivacyDigest, privacy.manifest.derivativeSHA256)
        XCTAssertEqual(added.reviewedMarkup.orderedAnnotations, [add.text])
        XCTAssertTrue(removed.reviewedMarkup.orderedAnnotations.isEmpty)
        XCTAssertEqual(removed.source, privacy.original)
        XCTAssertEqual(removed.privacyManifest.original, privacy.original)
        XCTAssertEqual(removed.privacyManifest.derivative, privacy.manifest.derivative)
        XCTAssertNotEqual(added.planSHA256, removed.planSHA256)

        let presentation = try makePresentation(
            evidenceID: "c02-evidence-h01",
            workspace: privacy.workspace,
            derivative: privacy.derivative
        )
        let detection = try EvidenceDetailComposerV1.detectPostMarkupPrivacy(
            card: presentation.card,
            policy: presentation.audiencePolicy,
            semanticText: "Reviewed evidence detail",
            composedOutput: presentation.composedOutput,
            detectorID: "c02-detector",
            detectorVersion: 1
        )
        XCTAssertEqual(detection.disposition, .pass)
        XCTAssertTrue(detection.findingKinds.isEmpty)
        let confirmation = try FinalAudiencePrivacyConfirmationV1(
            confirmationID: "c02-confirmation-h01",
            sourceSnapshotSHA256: presentation.sourceSnapshotSHA256,
            semanticSHA256: presentation.semanticSHA256,
            composedOutputSHA256: presentation.composedOutputSHA256,
            card: presentation.card,
            detection: detection,
            userConfirmedExactComposedBytes: true
        )
        XCTAssertTrue(confirmation.privacyTransformAppliedBeforeMarkup)
        XCTAssertTrue(confirmation.userConfirmedExactComposedBytes)
        let receipt = try EvidenceDetailCardRenderReceiptV1(
            receiptID: "c02-render-receipt-h01",
            snapshotID: "c02-snapshot-h01",
            sourceSnapshotSHA256: presentation.sourceSnapshotSHA256,
            semanticSHA256: presentation.semanticSHA256,
            card: presentation.card,
            composedOutputSHA256: presentation.composedOutputSHA256,
            confirmation: confirmation
        )
        try receipt.validate()
        XCTAssertTrue(receipt.limitationsPresented)
        XCTAssertEqual(receipt.profileSHA256, presentation.card.profileSHA256)
        XCTAssertEqual(receipt.reviewedMarkupSHA256, presentation.card.reviewedMarkupSHA256)

        let blocked = try EvidenceDetailComposerV1.detectPostMarkupPrivacy(
            card: presentation.card,
            policy: presentation.audiencePolicy,
            semanticText: "PRIVATE",
            composedOutput: Data("private output".utf8),
            detectorID: "c02-detector",
            detectorVersion: 1
        )
        XCTAssertEqual(blocked.disposition, .blocked)
        XCTAssertTrue(blocked.findingKinds.contains(.prohibitedSemanticText))
        XCTAssertThrowsError(try FinalAudiencePrivacyConfirmationV1(
            confirmationID: "c02-confirmation-blocked",
            sourceSnapshotSHA256: presentation.sourceSnapshotSHA256,
            semanticSHA256: presentation.semanticSHA256,
            composedOutputSHA256: KernelCanonicalHashV1.sha256(Data("private output".utf8)),
            card: presentation.card,
            detection: blocked,
            userConfirmedExactComposedBytes: true
        )) { error in
            XCTAssertEqual(error as? SnapshotProjectionFailureV1, .privacyViolation)
        }

        let originalReference = try OutputScopedContentReferenceV1(
            outputScopeID: presentation.card.profile.outputScopeID,
            ordinal: 0,
            reference: privacy.original
        )
        XCTAssertThrowsError(try EvidenceDetailComposerV1.compose(
            cardID: "c02-card-original",
            workspaceID: privacy.workspace.rawValue.uuidString.lowercased(),
            evidenceID: "c02-evidence-original",
            fields: [try EvidenceDetailFieldV1(
                fieldID: "caption",
                label: "Caption",
                value: "Original",
                sensitivity: .audienceSafe
            )],
            profile: presentation.card.profile,
            markupID: "c02-original-markup",
            annotations: [],
            referenceLabels: ["Original"],
            outputReferences: [originalReference]
        ))
    }

    func testV23P04C02I01HostileBoundsPathsDigestAndInterruptedReplay() async throws {
        let corpus = try loadCorpus()
        assertCorpus(corpus, selector: "I01", tier: "INTERRUPTION")
        XCTAssertEqual(corpus.limits.maximumSelectionCount, EvidenceCurationLimitsV1.maximumSelectionCount)
        XCTAssertEqual(corpus.limits.maximumAnnotationTextBytes, EvidenceCurationLimitsV1.maximumAnnotationTextBytes)
        XCTAssertEqual(corpus.limits.maximumSequenceFrames, EvidenceCurationLimitsV1.maximumSequenceFrames)
        XCTAssertTrue(corpus.interruptionBoundaries.contains("before-publication"))
        XCTAssertTrue(corpus.interruptionBoundaries.contains("after-staging"))

        let fixture = try makeFixture()
        let coordinator = EvidenceCurationCoordinatorV1(contentResolver: C02NullContentResolver())
        XCTAssertThrowsError(try EvidenceAnnotationV1(
            annotationID: "c02-annotation-over-limit",
            action: .add,
            text: String(repeating: "x", count: corpus.limits.maximumAnnotationTextBytes + 1)
        ))
        XCTAssertThrowsError(try EvidenceSequencePlanV1(
            metadataSequence: fixture.currentSequence,
            kind: .contactSheet,
            orderedSources: try makeFixture(count: corpus.limits.maximumSequenceFrames + 1).references,
            contactSheetColumns: 1,
            assemblerID: "c02-assembler",
            assemblerVersion: "1"
        ))
        XCTAssertThrowsError(try EvidenceSequencePlanV1(
            metadataSequence: fixture.currentSequence,
            kind: .contactSheet,
            orderedSources: fixture.references,
            contactSheetColumns: corpus.limits.maximumContactSheetColumns + 1,
            assemblerID: "c02-assembler",
            assemblerVersion: "1"
        ))
        XCTAssertThrowsError(try EvidenceSequencePlanV1(
            metadataSequence: fixture.currentSequence,
            kind: .flicker,
            orderedSources: fixture.references,
            frameDurationMilliseconds: 99,
            assemblerID: "c02-assembler",
            assemblerVersion: "1"
        ))
        XCTAssertThrowsError(try makeReference(
            workspaceID: fixture.references[0].workspaceID,
            contentID: "../escape",
            data: Data("bad".utf8),
            role: .immutableOriginal,
            createdAt: Self.fixedInstant
        ))

        let privacy = try C20PrivacyTransformTestSupport.makeFixture()
        let markup = try coordinator.reviewedMarkup(
            markupID: "c02-markup-i01",
            workspaceID: privacy.workspace,
            source: privacy.original,
            privacyPolicy: privacy.policy,
            privacyManifest: privacy.manifest,
            privacyReview: privacy.approvedReview,
            orderedAnnotations: [try EvidenceAnnotationV1(
                annotationID: "c02-annotation-i01",
                action: .add,
                text: "Markup"
            )]
        )
        let markupPlan = EvidenceDerivativePlanV1.markup(markup)
        XCTAssertEqual(markupPlan.renderSources, [privacy.manifest.derivative])
        XCTAssertEqual(markupPlan.associationSources, [privacy.original])
        XCTAssertTrue(EvidenceDerivativeServiceBoundaryV1.privacyTransformPrecedesMarkup)
        XCTAssertFalse(EvidenceDerivativeServiceBoundaryV1.mutatesOriginalBytes)

        let wrongWorkspace = WorkspaceID(rawValue: Self.foreignWorkspaceUUID)
        let foreignSources = try [
            makeSource(index: 1, workspace: wrongWorkspace),
            makeSource(index: 2, workspace: wrongWorkspace)
        ]
        XCTAssertThrowsError(try EvidenceSequencePlanV1(
            metadataSequence: fixture.currentSequence,
            kind: .flicker,
            orderedSources: foreignSources.map(\.reference),
            frameDurationMilliseconds: 500,
            assemblerID: "c02-assembler",
            assemblerVersion: "1"
        ))
        let sequence = try EvidenceSequencePlanV1(
            metadataSequence: fixture.currentSequence,
            kind: .flicker,
            orderedSources: fixture.references,
            frameDurationMilliseconds: 500,
            assemblerID: "c02-assembler",
            assemblerVersion: "1"
        )
        let derivativeBytes = try EvidenceDerivativeServiceV1.renderDeterministically(
            .sequence(sequence),
            sourceBytes: fixture.sources.map(\.bytes)
        )
        let flickerDimensions = try XCTUnwrap(c02PNGDimensions(derivativeBytes))
        XCTAssertEqual(flickerDimensions.0, 512)
        XCTAssertEqual(flickerDimensions.1, 512)
        XCTAssertLessThanOrEqual(derivativeBytes.count, corpus.visual.maximumDerivativeBytes)
        XCTAssertTrue(c02PNGHasChunk(derivativeBytes, "IDAT"))
        XCTAssertTrue(c02PNGHasChunk(derivativeBytes, "IEND"))
        XCTAssertTrue(c02PNGHasChunk(derivativeBytes, "acTL"))
        XCTAssertEqual(
            derivativeBytes,
            try EvidenceDerivativeServiceV1.renderDeterministically(
                .sequence(sequence),
                sourceBytes: fixture.sources.map(\.bytes)
            )
        )
        let reorderedDerivativeBytes = try EvidenceDerivativeServiceV1.renderDeterministically(
            .sequence(sequence),
            sourceBytes: fixture.sources.reversed().map(\.bytes)
        )
        XCTAssertNotEqual(derivativeBytes, reorderedDerivativeBytes)
        let derivativeSource = try makeReference(
            workspaceID: fixture.references[0].workspaceID,
            contentID: "c02-sequence-derivative",
            data: derivativeBytes,
            role: .derivative,
            createdAt: Self.fixedInstant,
            mediaType: "image/png"
        )
        XCTAssertEqual(
            KernelCanonicalHashV1.sha256(derivativeBytes),
            try requireDigest(derivativeSource).hexadecimalValue
        )
        let provenance = try makeSequenceProvenance(
            plan: sequence,
            derivative: derivativeSource,
            provenanceID: "c02-sequence-provenance"
        )
        let derivativeAssociation = try makeDerivativeAssociation(
            predecessor: fixture.associations[0],
            derivativeContentID: derivativeSource.contentID
        )
        let metadataMutation = try makeDerivativeMetadataMutation(
            fixture: fixture,
            derivativeAssociation: derivativeAssociation,
            derivative: derivativeSource
        )
        let command = try EvidenceDerivativePublicationCommandV1(
            operationID: "c02-operation-i01",
            plan: .sequence(sequence),
            derivativeBytes: derivativeBytes,
            derivative: derivativeSource,
            provenance: provenance,
            associationHistory: fixture.associations,
            currentSequence: fixture.currentSequence,
            metadataMutation: metadataMutation
        )
        try metadataMutation.validate()
        XCTAssertEqual(try metadataMutation.mutationPostImages.count, 2)
        let applicationSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("c02-derivative-service-i01", isDirectory: true)
        try? FileManager.default.removeItem(at: applicationSupport)
        let generationID = UUID(uuidString: "c0200000-0000-4000-8000-0000000000aa")!
        let root = applicationSupport
            .appendingPathComponent("FieldEvidenceData", isDirectory: true)
            .appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(generationID.uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: applicationSupport) }
        let store = EvidenceBundleStore(generationRootURL: root)
        for source in fixture.sources {
            guard let digest = source.reference.digests.digest(for: .sha256) else {
                throw C02EvidenceCurationTestFailure.missingDigest
            }
            let request = try DraftImmutableContentWriteRequestV1(
                workspaceID: fixture.workspace,
                contentID: source.reference.contentID,
                digest: digest,
                byteLength: source.reference.byteLength,
                mediaType: source.reference.mediaType,
                mutationID: try MutationIDV1(rawValue: UUID(uuidString: "c0200000-0000-4000-8000-0000000000\(source.reference.contentID.suffix(2))")!),
                createdAt: source.reference.createdAt
            )
            _ = try await store.persistImmutableOriginal(bytes: source.bytes, request: request)
        }

        let canonicalCommitter = try await MainActor.run {
            try C02WriterBackedCommitter(fixture: fixture)
        }
        let service = EvidenceDerivativeServiceV1(
            store: store,
            canonicalCommitter: canonicalCommitter
        )
        do {
            _ = try await service.publish(
                command,
                cancellation: EvidenceDerivativeCancellationV1 { true }
            )
            XCTFail("Cancellation before publication must not create a derivative")
        } catch {
            XCTAssertEqual(error as? EvidenceDerivativeServiceFailureV1, .interrupted)
        }
        let workspaceString = fixture.workspace.rawValue.uuidString.lowercased()
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("content/\(workspaceString)/c02-sequence-derivative").path
        ))

        let afterStagingProbe = C02CancellationProbe(threshold: 6)
        do {
            _ = try await service.publish(
                command,
                cancellation: EvidenceDerivativeCancellationV1 { afterStagingProbe.isCancelled() }
            )
            XCTFail("Cancellation after staging must not publish a partial derivative")
        } catch {
            XCTAssertEqual(error as? EvidenceDerivativeServiceFailureV1, .interrupted)
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("content/\(workspaceString)/c02-sequence-derivative").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(".staging/evidence-derivatives/\(workspaceString)/c02-operation-i01").path
        ))

        let published = try await service.publish(command)
        XCTAssertEqual(published.disposition, .published)
        let publishedPostImages = try XCTUnwrap(
            published.operation.metadataReceipt?.mutationReceipt.postImages
        )
        XCTAssertEqual(publishedPostImages.count, 2)
        XCTAssertEqual(
            Set(try publishedPostImages.map { try $0.identity.kind }),
            Set([.evidenceAssociationEvent, .evidenceSequenceRevision])
        )
        let adopted = try await service.publish(command)
        XCTAssertEqual(adopted.disposition, .adopted)
        XCTAssertEqual(adopted.operation, published.operation)
        XCTAssertEqual(adopted.result, published.result)
        let committedCount = await canonicalCommitter.committedCount()
        XCTAssertEqual(committedCount, 1)

        let divergentBytes = Data("{\"divergent\":true}".utf8)
        let divergentReference = try makeReference(
            workspaceID: fixture.references[0].workspaceID,
            contentID: "c02-sequence-derivative",
            data: divergentBytes,
            role: .derivative,
            createdAt: Self.fixedInstant,
            mediaType: "image/png"
        )
        let divergentProvenance = try makeSequenceProvenance(
            plan: sequence,
            derivative: divergentReference,
            provenanceID: "c02-sequence-provenance-divergent"
        )
        let divergentCommand = try EvidenceDerivativePublicationCommandV1(
            operationID: command.operationID,
            plan: command.plan,
            derivativeBytes: divergentBytes,
            derivative: divergentReference,
            provenance: divergentProvenance,
            associationHistory: fixture.associations,
            currentSequence: fixture.currentSequence,
            metadataMutation: metadataMutation
        )
        do {
            _ = try await service.publish(divergentCommand)
            XCTFail("A divergent replay must not adopt the prior derivative")
        } catch {
            XCTAssertEqual(error as? EvidenceDerivativeServiceFailureV1, .replayDiverged)
        }

        let wrongDigest = try ContentDerivativeProvenanceV1(
            provenanceID: "c02-provenance-wrong-digest",
            workspaceID: fixture.workspace.rawValue.uuidString.lowercased(),
            sources: try fixture.references.map {
                try ContentSourceBindingV1(
                    contentID: $0.contentID,
                    digest: try XCTUnwrap($0.digests.digest(for: .sha256))
                )
            },
            derivativeContentID: derivativeSource.contentID,
            derivativeDigest: try ContentDigestV1(
                algorithm: .sha256,
                hexadecimalValue: String(repeating: "f", count: 64)
            ),
            transform: .sequence(try SequenceDerivativeV1(
                assemblerID: sequence.assemblerID,
                assemblerVersion: sequence.assemblerVersion,
                orderedSourceCount: fixture.references.count
            )),
            metadataSanitizerID: "c02-sanitizer",
            metadataSanitizerVersion: "1",
            createdAt: Self.fixedInstant
        )
        XCTAssertThrowsError(try EvidenceCurationDerivativeResultV1(
            requestSHA256: sequence.planSHA256,
            derivative: derivativeSource,
            provenance: wrongDigest,
            orderedSources: fixture.references
        )) { error in
            XCTAssertEqual(error as? EvidenceCurationFailureV1, .invalidLineage)
        }

        let planned = try EvidenceCurationOperationReceiptV1(
            operationID: "c02-operation-planned",
            workspaceID: fixture.workspace,
            requestSHA256: sequence.planSHA256,
            state: .planned
        )
        XCTAssertEqual(try coordinator.replay(planned, requestSHA256: sequence.planSHA256), planned)
        XCTAssertThrowsError(try coordinator.replay(planned, requestSHA256: String(repeating: "e", count: 64))) { error in
            XCTAssertEqual(error as? EvidenceCurationFailureV1, .replayDiverged)
        }
        let interrupted = try EvidenceCurationOperationReceiptV1(
            operationID: "c02-operation-interrupted",
            workspaceID: fixture.workspace,
            requestSHA256: sequence.planSHA256,
            state: .interrupted
        )
        XCTAssertThrowsError(try coordinator.replay(interrupted, requestSHA256: sequence.planSHA256)) { error in
            XCTAssertEqual(error as? EvidenceCurationFailureV1, .interrupted)
        }
    }

    func testV23P04C02R01ImmutableOriginalAndRecoveryClosure() async throws {
        let corpus = try loadCorpus()
        assertCorpus(corpus, selector: "R01", tier: "RECOVERY")
        XCTAssertEqual(corpus.lifecycle.persistence, "CONTENT_ONLY")
        XCTAssertTrue(corpus.lifecycle.plansAndProjectionsAreNonpersistent)
        XCTAssertTrue(EvidenceCurationLifecycleV1.plansAndProjectionsAreNonpersistent)
        XCTAssertEqual(corpus.lifecycle.schema, "INCUMBENT_CONTENT_AUTHORITY_AND_C05_V43_METADATA")
        XCTAssertEqual(corpus.lifecycle.migration, "C05_METADATA_AUTHORITY")
        XCTAssertEqual(corpus.lifecycle.backupRestore, "REQUIRED_VIA_INCUMBENT_CONTENT_AND_C05_METADATA_AUTHORITIES")
        XCTAssertEqual(corpus.lifecycle.cloneFork, "INCUMBENT_CONTENT_AND_C05_METADATA_AUTHORITIES")
        XCTAssertEqual(corpus.lifecycle.journalReplay, "C05_METADATA_WRITER_REPLAY_AND_DETERMINISTIC_REPROJECTION")
        XCTAssertEqual(corpus.lifecycle.searchRebuild, "NOT_APPLICABLE")
        XCTAssertEqual(corpus.lifecycle.deleteErase, "REQUIRED_VIA_INCUMBENT_CONTENT_AND_C05_METADATA_AUTHORITIES")
        XCTAssertEqual(
            corpus.lifecycle.exportReport,
            "REQUIRED_VIA_INCUMBENT_CONTENT_C05_METADATA_AND_REPORT_AUTHORITIES"
        )
        XCTAssertFalse(corpus.lifecycle.comparisonIsProof)
        XCTAssertFalse(corpus.lifecycle.createsContentStore)
        XCTAssertFalse(corpus.uiAdoptionEnabled)

        let fixture = try makeFixture()
        let sourceHashes = fixture.references.map { $0.digests.digest(for: .sha256) }
        let sequence = try EvidenceSequencePlanV1(
            metadataSequence: fixture.currentSequence,
            kind: .contactSheet,
            orderedSources: fixture.references,
            contactSheetColumns: 2,
            assemblerID: "c02-assembler",
            assemblerVersion: "1"
        )
        let derivativeBytes = try EvidenceDerivativeServiceV1.renderDeterministically(
            .sequence(sequence),
            sourceBytes: fixture.sources.map(\.bytes)
        )
        let contactSheetDimensions = try XCTUnwrap(c02PNGDimensions(derivativeBytes))
        XCTAssertEqual(contactSheetDimensions.0, 1_024)
        XCTAssertEqual(contactSheetDimensions.1, 512)
        XCTAssertLessThanOrEqual(derivativeBytes.count, corpus.visual.maximumDerivativeBytes)
        XCTAssertTrue(c02PNGHasChunk(derivativeBytes, "IDAT"))
        XCTAssertTrue(c02PNGHasChunk(derivativeBytes, "IEND"))
        XCTAssertFalse(c02PNGHasChunk(derivativeBytes, "acTL"))
        XCTAssertEqual(
            derivativeBytes,
            try EvidenceDerivativeServiceV1.renderDeterministically(
                .sequence(sequence),
                sourceBytes: fixture.sources.map(\.bytes)
            )
        )
        let derivative = try makeReference(
            workspaceID: fixture.references[0].workspaceID,
            contentID: "c02-regenerated-derivative",
            data: derivativeBytes,
            role: .derivative,
            createdAt: Self.fixedInstant,
            mediaType: "image/png"
        )
        XCTAssertEqual(
            KernelCanonicalHashV1.sha256(derivativeBytes),
            try requireDigest(derivative).hexadecimalValue
        )
        let provenance = try makeSequenceProvenance(
            plan: sequence,
            derivative: derivative,
            provenanceID: "c02-regenerated-provenance"
        )
        let result = try EvidenceCurationDerivativeResultV1(
            requestSHA256: sequence.planSHA256,
            derivative: derivative,
            provenance: provenance,
            orderedSources: fixture.references
        )
        let derivativeAssociation = try makeDerivativeAssociation(
            predecessor: fixture.associations[0],
            derivativeContentID: derivative.contentID
        )
        let metadataMutation = try makeDerivativeMetadataMutation(
            fixture: fixture,
            derivativeAssociation: derivativeAssociation,
            derivative: derivative
        )
        let canonicalCommitter = try await MainActor.run {
            try C02WriterBackedCommitter(fixture: fixture)
        }
        let metadataReceipt = try await canonicalCommitter.commitDerivativeMetadata(metadataMutation)
        try metadataReceipt.validate()
        XCTAssertEqual(metadataReceipt.mutationReceipt.postImages.count, 2)
        let completed = try EvidenceCurationOperationReceiptV1(
            operationID: "c02-operation-r01",
            workspaceID: fixture.workspace,
            requestSHA256: sequence.planSHA256,
            state: .completed,
            resultSHA256: try EvidenceCurationCanonicalCodecV1.sha256(result),
            metadataReceipt: metadataReceipt
        )
        XCTAssertEqual(completed.resultSHA256, try EvidenceCurationCanonicalCodecV1.sha256(result))
        XCTAssertEqual(try EvidenceCurationCanonicalCodecV1.decode(
            EvidenceCurationDerivativeResultV1.self,
            from: EvidenceCurationCanonicalCodecV1.encode(result)
        ), result)

        let regeneratedGraphReferences = fixture.references + [derivative]
        try ContentProvenanceGraphV1.validate(
            references: regeneratedGraphReferences,
            originals: fixture.originalProvenance,
            derivatives: [provenance]
        )
        XCTAssertEqual(
            fixture.references.map { $0.digests.digest(for: .sha256) },
            sourceHashes
        )
        XCTAssertTrue(fixture.references.allSatisfy { $0.byteRole == .immutableOriginal })
        XCTAssertTrue(fixture.references.allSatisfy { $0.contentID.hasPrefix("c02-content-") })
        XCTAssertFalse(EvidenceDerivativeServiceBoundaryV1.createsContentStore)
        XCTAssertFalse(EvidenceDerivativeServiceBoundaryV1.mutatesOriginalBytes)
        XCTAssertTrue(EvidenceDerivativeServiceBoundaryV1.usesNetworkOrDiagnosis == false)

        let privacy = try C20PrivacyTransformTestSupport.makeFixture()
        try ContentProvenanceGraphV1.validate(
            references: [privacy.original, privacy.derivative],
            originals: [privacy.originalProvenance],
            derivatives: [privacy.provenance]
        )
        try privacy.original.validatePrivacyDerivative(privacy.derivative)
        XCTAssertEqual(privacy.original, privacy.manifest.original)
        XCTAssertEqual(privacy.original.digests.digest(for: .sha256), privacy.originalProvenance.contentDigest)
        XCTAssertNotEqual(privacy.original.contentID, privacy.derivative.contentID)
        XCTAssertNotEqual(
            privacy.original.digests.digest(for: .sha256),
            privacy.derivative.digests.digest(for: .sha256)
        )

        let publicLifecycle = [
            EvidenceCurationLifecycleV1.persistence,
            EvidenceCurationLifecycleV1.schema,
            EvidenceCurationLifecycleV1.migration,
            EvidenceCurationLifecycleV1.backupRestore,
            EvidenceCurationLifecycleV1.cloneFork,
            EvidenceCurationLifecycleV1.journalReplay,
            EvidenceCurationLifecycleV1.searchRebuild,
            EvidenceCurationLifecycleV1.deleteErase
        ]
        XCTAssertEqual(publicLifecycle, [
            "CONTENT_ONLY",
            "INCUMBENT_CONTENT_AUTHORITY_AND_C05_V43_METADATA",
            "C05_METADATA_AUTHORITY",
            "REQUIRED_VIA_INCUMBENT_CONTENT_AND_C05_METADATA_AUTHORITIES",
            "INCUMBENT_CONTENT_AND_C05_METADATA_AUTHORITIES",
            "C05_METADATA_WRITER_REPLAY_AND_DETERMINISTIC_REPROJECTION",
            "NOT_APPLICABLE",
            "REQUIRED_VIA_INCUMBENT_CONTENT_AND_C05_METADATA_AUTHORITIES"
        ])
    }

    private func loadCorpus() throws -> C02EvidenceCurationCorpusV1 {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent(
            "FieldEvidenceAppTests/Fixtures/V22/EvidenceCuration/V22P04C02EvidenceCurationCorpusV1.json"
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(C02EvidenceCurationCorpusV1.self, from: data)
    }

    private func assertCorpus(
        _ corpus: C02EvidenceCurationCorpusV1,
        selector: String,
        tier: String
    ) {
        XCTAssertEqual(corpus.schema, "V22P04C02EvidenceCurationCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.cardID, "V23-P04-C02")
        XCTAssertEqual(corpus.ordinal, 90)
        XCTAssertEqual(corpus.contentMode, "CONTENT_ONLY")
        XCTAssertEqual(corpus.selectors.map(\.id), ["G01", "A01", "H01", "I01", "R01"])
        XCTAssertEqual(corpus.visual.sourceMediaType, "image/png")
        XCTAssertEqual(corpus.visual.derivativeMediaType, "image/png")
        XCTAssertEqual(corpus.visual.flickerWidth, 512)
        XCTAssertEqual(corpus.visual.flickerHeight, 512)
        XCTAssertEqual(corpus.visual.contactSheetWidth, 1024)
        XCTAssertEqual(corpus.visual.contactSheetHeight, 512)
        XCTAssertEqual(corpus.visual.contactSheetColumns, 2)
        XCTAssertEqual(corpus.visual.flickerFrameCount, 2)
        XCTAssertEqual(corpus.visual.maximumDerivativeBytes, 25_165_824)
        XCTAssertTrue(corpus.visual.orientationAndColorCanonicalized)
        let row = corpus.selectors.first { $0.id == selector }
        XCTAssertEqual(row?.selector, "V23-P04-C02-\(selector)")
        XCTAssertEqual(row?.tier, tier)
    }

    private func makeFixture(count: Int = 2) throws -> C02CurationFixture {
        let workspace = WorkspaceID(rawValue: Self.workspaceUUID)
        let sources = try (1...count).map { try makeSource(index: $0, workspace: workspace) }
        let associations = try sources.enumerated().map { offset, source in
            try makeAssociation(
                index: offset + 1,
                workspace: workspace,
                evidenceID: "c02-evidence-\(String(format: "%03d", offset + 1))",
                contentID: source.reference.contentID
            )
        }
        let sequenceHistory = try makeC02SequenceHistory(
            workspace: workspace,
            associations: associations
        )
        return C02CurationFixture(
            workspace: workspace,
            sources: sources,
            associations: associations,
            sequenceHistory: sequenceHistory,
            currentSequence: try XCTUnwrap(sequenceHistory.last)
        )
    }

    private func makeSource(
        index: Int,
        workspace: WorkspaceID,
        role: ContentByteRoleV1 = .immutableOriginal
    ) throws -> C02SourceFixture {
        let contentID = "c02-content-\(String(format: "%03d", index))"
        let encoded = index.isMultiple(of: 2)
            ? "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP4z8DwHwAFAAH/VscvDQAAAABJRU5ErkJggg=="
            : "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNgaPj/HwAEggJ/OIZIfAAAAABJRU5ErkJggg=="
        guard let bytes = Data(base64Encoded: encoded) else {
            throw C02EvidenceCurationTestFailure.malformedFixture
        }
        let reference = try makeReference(
            workspaceID: workspace.rawValue.uuidString.lowercased(),
            contentID: contentID,
            data: bytes,
            role: role,
            createdAt: String(format: "2026-08-30T00:%02d:00.000Z", index)
        )
        let digest = try requireDigest(reference)
        let provenance = try ContentOriginalProvenanceV1(
            provenanceID: "c02-original-provenance-\(String(format: "%03d", index))",
            workspaceID: reference.workspaceID,
            contentID: reference.contentID,
            contentDigest: digest,
            origin: .humanCapture,
            recordedAt: reference.createdAt
        )
        return C02SourceFixture(bytes: bytes, reference: reference, provenance: provenance)
    }

    private func makeReference(
        workspaceID: String,
        contentID: String,
        data: Data,
        role: ContentByteRoleV1,
        createdAt: String,
        mediaType: String = "image/png"
    ) throws -> ContentReferenceV1 {
        let observed = try ContentIntegrityV1.observe(
            workspaceID: workspaceID,
            contentID: contentID,
            data: data,
            mediaType: mediaType
        )
        return try ContentReferenceV1(
            workspaceID: workspaceID,
            contentID: contentID,
            byteLength: Int64(data.count),
            mediaType: mediaType,
            digests: observed.digests,
            byteRole: role,
            createdAt: createdAt
        )
    }

    private func makeAssociation(
        index: Int,
        workspace: WorkspaceID,
        evidenceID: String,
        contentID: String
    ) throws -> EvidenceAssociationV1 {
        let workspaceString = workspace.rawValue.uuidString.lowercased()
        let target = try EvidenceAssociationTargetV1(
            workspaceID: workspaceString,
            kind: .inspectionNode,
            targetID: "c02-node-canonical",
            targetRevision: 1
        )
        return try EvidenceAssociationV1(
            associationEventID: "c02-association-\(String(format: "%03d", index))",
            workspaceID: workspaceString,
            evidenceID: evidenceID,
            expectedEvidenceRevision: 0,
            resultingEvidenceRevision: 1,
            mutationID: String(format: "c0200000-0000-4000-8000-%012x", 0xC00 + index),
            action: .assigned,
            contentID: contentID,
            target: target,
            actorID: "c02-actor",
            reason: "Attach immutable source evidence.",
            effectiveAt: String(format: "2026-08-30T00:%02d:30.000Z", index)
        )
    }

    private func makeDerivativeAssociation(
        predecessor: EvidenceAssociationV1,
        derivativeContentID: String
    ) throws -> EvidenceAssociationV1 {
        try EvidenceAssociationV1(
            associationEventID: "c02-association-derivative",
            workspaceID: predecessor.workspaceID,
            evidenceID: predecessor.evidenceID,
            expectedEvidenceRevision: predecessor.resultingEvidenceRevision,
            resultingEvidenceRevision: predecessor.resultingEvidenceRevision + 1,
            mutationID: "c0200000-0000-4000-8000-000000000d01",
            action: .reassigned,
            contentID: derivativeContentID,
            target: predecessor.target,
            previousContentID: predecessor.contentID,
            previousTarget: predecessor.target,
            supersedesAssociationEventID: predecessor.associationEventID,
            actorID: predecessor.actorID,
            reason: "Publish a reversible curation derivative.",
            effectiveAt: "2026-08-30T00:30:00.000Z"
        )
    }

    private func makeDerivativeMetadataMutation(
        fixture: C02CurationFixture,
        derivativeAssociation: EvidenceAssociationV1,
        derivative: ContentReferenceV1
    ) throws -> EvidenceMetadataMutationV1 {
        guard let mutationUUID = UUID(uuidString: derivativeAssociation.mutationID) else {
            throw C02EvidenceCurationTestFailure.malformedFixture
        }
        let predecessor = fixture.currentSequence
        let successorItems = try predecessor.orderedItems.map { item in
            guard item.evidenceID == derivativeAssociation.evidenceID else { return item }
            return try EvidenceSequenceItemV1(
                evidenceID: item.evidenceID,
                contentID: derivative.contentID,
                role: item.role,
                caption: item.caption,
                accessibilityDescription: item.accessibilityDescription,
                ordinal: item.ordinal,
                target: item.target,
                association: derivativeAssociation
            )
        }
        let mutationID = try MutationIDV1(rawValue: mutationUUID)
        let successor = try EvidenceSequenceV1(
            sequenceID: predecessor.sequenceID,
            workspaceID: predecessor.workspaceID,
            target: predecessor.target,
            policy: predecessor.policy,
            orderedItems: successorItems,
            predecessor: try predecessor.reference,
            revision: predecessor.revision + 1,
            mutationID: mutationID
        )
        return try EvidenceMetadataMutationV1(
            workspaceID: fixture.workspace,
            mutationID: mutationID,
            expectedSequenceRevision: predecessor.revision,
            associationEvent: derivativeAssociation,
            sequenceSuccessor: successor
        )
    }

    private func requireDigest(_ reference: ContentReferenceV1) throws -> ContentDigestV1 {
        guard let digest = reference.digests.digest(for: .sha256) else {
            throw C02EvidenceCurationTestFailure.missingDigest
        }
        return digest
    }

    private func makePresentation(
        evidenceID: String,
        workspace: WorkspaceID,
        derivative: ContentReferenceV1
    ) throws -> C02PresentationFixture {
        let audiencePolicy = try AudiencePrivacyPolicyV1(
            policyID: "c02-audience-policy",
            policyVersion: 1,
            audience: .customerSafe,
            prohibitedCanaries: ["c:\\", "private", "secret"]
        )
        let profile = try EvidenceDetailCardProfileV1(
            profileID: "c02-detail-profile",
            profileRelease: 1,
            audience: .customerSafe,
            outputScopeID: "c02-output-scope",
            privacyTransformID: "c02-privacy-transform",
            privacyTransformVersion: 1,
            markupProfileID: "c02-markup-profile",
            markupProfileVersion: 1,
            localeIdentifier: "en-US",
            displayProfileID: "c02-display-profile",
            rendererVersion: "c02-renderer-1",
            audiencePrivacyPolicy: audiencePolicy,
            includedFieldIDs: ["caption", "role"],
            limitationsText: "This detail does not verify capture time, location, or person."
        )
        let outputReference = try OutputScopedContentReferenceV1(
            outputScopeID: profile.outputScopeID,
            ordinal: 0,
            reference: derivative
        )
        let fields = try [
            EvidenceDetailFieldV1(
                fieldID: "caption",
                label: "Caption",
                value: "Reviewed evidence",
                sensitivity: .audienceSafe
            ),
            EvidenceDetailFieldV1(
                fieldID: "role",
                label: "Role",
                value: "Detail",
                sensitivity: .audienceSafe
            )
        ]
        let card = try EvidenceDetailComposerV1.compose(
            cardID: "c02-card-\(evidenceID)",
            workspaceID: workspace.rawValue.uuidString.lowercased(),
            evidenceID: evidenceID,
            fields: fields,
            profile: profile,
            markupID: "c02-card-markup-\(evidenceID)",
            annotations: ["Reviewed markup"],
            referenceLabels: ["Audience-safe derivative"],
            outputReferences: [outputReference]
        )
        let composedOutput = Data("Caption: Reviewed evidence\nRole: Detail\nReviewed markup".utf8)
        let snapshotID = "c02-snapshot-\(evidenceID)"
        let digest = String(repeating: "a", count: 64)
        let profileBinding = try FinalizedReportProfileBindingV1(
            workspaceID: workspace.rawValue.uuidString.lowercased(),
            snapshotID: snapshotID,
            outputScopeID: profile.outputScopeID,
            reportProfileID: profile.profileID,
            reportProfileRelease: profile.profileRelease,
            reportProfileSHA256: card.profileSHA256,
            exportProfileID: "c02-export-profile",
            exportProfileRelease: 1,
            exportProfileSHA256: digest,
            sectionRegistryID: "c02-section-registry",
            sectionRegistryVersion: 1,
            sectionRegistrySHA256: digest,
            contractManifestID: "c02-contract-manifest",
            contractManifestVersion: 1,
            contractManifestSHA256: digest,
            sectionIDs: ["evidence-detail"],
            audience: .customerSafe,
            detail: .complete,
            privacyTransformID: profile.privacyTransformID,
            localeIdentifier: profile.localeIdentifier,
            unitsProfileID: "c02-units-profile",
            displayProfileID: profile.displayProfileID,
            orientation: .portrait,
            mediaLayout: .standardGrid,
            rendererVersion: profile.rendererVersion,
            projectionVersion: "c02-projection"
        )
        let snapshotPayload = try CompletedActivitySnapshotPayloadV1(
            workspaceID: workspace.rawValue.uuidString.lowercased(),
            snapshotID: snapshotID,
            snapshotRevision: 1,
            sourceActivityID: "c02-activity-\(evidenceID)",
            sourceRevision: 1,
            reportID: "c02-report-\(evidenceID)",
            packageReleaseID: "c02-package-release",
            generatedAt: "2026-08-30T00:00:01.000Z",
            completedAt: "2026-08-30T00:00:00.000Z",
            supersedesSnapshotID: nil,
            supersededSnapshotSHA256: nil,
            amendmentReason: nil,
            profileBinding: profileBinding,
            serviceFacts: [],
            evidenceCards: [card],
            limitations: ["This detail does not verify capture time, location, or person."]
        )
        let snapshot = try CompletedActivitySnapshotV1.freezeOriginal(snapshotPayload)
        let derivativeDigest = try requireDigest(derivative)
        let publication = try AccessibleDocumentPublicationBindingV1(
            snapshotSHA256: snapshot.snapshotSHA256,
            manifestID: profileBinding.contractManifestID,
            manifestVersion: profileBinding.contractManifestVersion,
            manifestSHA256: profileBinding.contractManifestSHA256,
            localeIdentifier: profile.localeIdentifier,
            profileID: profile.profileID,
            profileRelease: profile.profileRelease,
            profileSHA256: card.profileSHA256,
            brandProfileID: "c02-brand-profile",
            brandProfileRelease: 1,
            brandProfileSHA256: digest
        )
        let semanticTree = try AccessibleDocumentSemanticTreeV1(
            treeID: UUID(uuidString: "c0200000-0000-4000-8000-0000000000b6")!,
            workspaceID: workspace,
            audience: .customerSafe,
            publication: publication,
            nodes: [
                try AccessibleDocumentNodeV1(
                    nodeID: "c02-document",
                    role: .document,
                    parentNodeID: nil,
                    order: 0,
                    localizedText: "Evidence detail",
                    sensitivity: .customerSafe
                ),
                try AccessibleDocumentNodeV1(
                    nodeID: "c02-derivative",
                    role: .figure,
                    parentNodeID: "c02-document",
                    order: 0,
                    localizedText: "Audience-safe derivative",
                    alternateText: "Audience-safe derivative",
                    alternateTextProvenance: .sourceCaption,
                    evidenceLinks: [try AccessibleEvidenceLinkV1(
                        evidenceID: card.evidenceID,
                        evidenceSHA256: derivativeDigest.hexadecimalValue,
                        mediaType: derivative.mediaType
                    )],
                    sensitivity: .customerSafe
                )
            ],
            projectionVersion: profileBinding.projectionVersion
        )
        let semanticSHA256 = KernelCanonicalHashV1.sha256(Data("c02-semantic".utf8))
        let composedOutputSHA256 = KernelCanonicalHashV1.sha256(composedOutput)
        let confirmation = try FinalAudiencePrivacyConfirmationV1(
            confirmationID: "c02-confirmation-\(evidenceID)",
            sourceSnapshotSHA256: snapshot.snapshotSHA256,
            semanticSHA256: semanticSHA256,
            composedOutputSHA256: composedOutputSHA256,
            card: card,
            detection: try EvidenceDetailComposerV1.detectPostMarkupPrivacy(
                card: card,
                policy: audiencePolicy,
                semanticText: "Reviewed evidence detail",
                composedOutput: composedOutput,
                detectorID: "c02-detector",
                detectorVersion: 1
            ),
            userConfirmedExactComposedBytes: true
        )
        let assessmentActorReference = try LocalActorReferenceV1(
            actorReferenceID: UUID(uuidString: "c0200000-0000-4000-8000-0000000000b7")!,
            workspaceID: workspace,
            displayName: "C02 accessibility reviewer"
        )
        let assessmentActor = try ActorSnapshotV1(
            snapshotID: UUID(uuidString: "c0200000-0000-4000-8000-0000000000b8")!,
            workspaceID: workspace,
            actor: assessmentActorReference,
            responsibility: .reviewedBy,
            displayNameAtTime: "C02 accessibility reviewer",
            capturedAt: Date(timeIntervalSince1970: 1_800_000_004)
        )
        let accessibilityAssessment = try AccessibleDocumentAssessmentReceiptV1(
            receiptID: UUID(uuidString: "c0200000-0000-4000-8000-0000000000b9")!,
            workspaceID: workspace,
            tree: semanticTree,
            outputSHA256: composedOutputSHA256,
            outputByteCount: Int64(composedOutput.count),
            outputMediaType: "text/plain",
            rendererID: "c02-accessibility-renderer",
            rendererVersion: "1",
            assessmentToolID: "c02-accessibility-tool",
            assessmentToolVersion: "1",
            assessor: assessmentActor,
            state: .internalPass,
            assessedAt: Date(timeIntervalSince1970: 1_800_000_005),
            mutationID: try MutationIDV1(rawValue: UUID(uuidString: "c0200000-0000-4000-8000-0000000000ba")!)
        )
        let renderReceipt = try EvidenceDetailCardRenderReceiptV1(
            receiptID: "c02-render-receipt-\(evidenceID)",
            snapshotID: snapshotID,
            sourceSnapshotSHA256: snapshot.snapshotSHA256,
            semanticSHA256: semanticSHA256,
            card: card,
            composedOutputSHA256: composedOutputSHA256,
            confirmation: confirmation
        )
        let bundle = try EvidenceDetailPreviewBundleV1(
            snapshot: snapshot,
            profile: profile,
            card: card,
            confirmation: confirmation,
            renderReceipt: renderReceipt,
            semanticTree: semanticTree,
            accessibilityAssessment: accessibilityAssessment
        )
        let privacy = try C20PrivacyTransformTestSupport.makeFixture()
        return C02PresentationFixture(
            privacy: privacy,
            audiencePolicy: audiencePolicy,
            profile: profile,
            card: card,
            bundle: bundle,
            semanticTree: semanticTree,
            accessibilityAssessment: accessibilityAssessment,
            composedOutput: composedOutput,
            sourceSnapshotSHA256: snapshot.snapshotSHA256,
            semanticSHA256: semanticSHA256,
            composedOutputSHA256: composedOutputSHA256
        )
    }

    private func makeSequenceProvenance(
        plan: EvidenceSequencePlanV1,
        derivative: ContentReferenceV1,
        provenanceID: String
    ) throws -> ContentDerivativeProvenanceV1 {
        let sources = try plan.orderedSources.map {
            try ContentSourceBindingV1(contentID: $0.contentID, digest: requireDigest($0))
        }
        return try ContentDerivativeProvenanceV1(
            provenanceID: provenanceID,
            workspaceID: plan.workspaceID.rawValue.uuidString.lowercased(),
            sources: sources,
            derivativeContentID: derivative.contentID,
            derivativeDigest: requireDigest(derivative),
            transform: .sequence(try SequenceDerivativeV1(
                assemblerID: plan.assemblerID,
                assemblerVersion: plan.assemblerVersion,
                orderedSourceCount: plan.orderedSources.count
            )),
            metadataSanitizerID: "c02-sanitizer",
            metadataSanitizerVersion: "1",
            createdAt: Self.fixedInstant
        )
    }
}

import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

/// Deterministic fixtures for the C22 recoverability evidence boundary.  The
/// fixture deliberately reuses the C21 capability decision instead of
/// introducing a second admission or writer contract.
enum C22RecoverabilityTestSupport {
    static let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "c2200000-0000-4000-8000-%012x", slot))!
    }

    static func mutation(_ slot: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(slot))
    }

    static func digest(_ byte: Character = "a") -> String {
        String(repeating: byte, count: 64)
    }

    static func workspace(_ slot: Int = 1) -> WorkspaceID {
        WorkspaceID(rawValue: id(slot))
    }

    static func capabilityBinding() throws -> RecoverabilityClientCapabilityBindingV1 {
        let fixture = try C21ClientCapabilityTestSupport.makeFixture()
        guard let decision = fixture.decisions[.view] else {
            throw RecoverabilityVerificationFailureV1.invalidValue
        }
        return try RecoverabilityClientCapabilityBindingV1(decision)
    }

    static func frontier(
        revision: UInt64 = 12,
        sequence: UInt64 = 12,
        checkpointByte: Character = "e",
        frontierByte: Character = "f"
    ) throws -> RecoveryPointFrontierV1 {
        try RecoveryPointFrontierV1(
            workspaceRevision: revision,
            lastLocalSequence: sequence,
            checkpointID: digest(checkpointByte),
            checkpointFrontierSHA256: digest(frontierByte)
        )
    }

    static func archive(
        workspaceID: WorkspaceID,
        frontier: RecoveryPointFrontierV1,
        generationSlot: Int = 2,
        archiveByteCount: Int64 = 4_096,
        archiveSHA256: String? = nil,
        recordsSHA256: String? = nil,
        contentManifestSHA256: String? = nil,
        persistentSchemaVersion: Int = 21,
        recordsSchemaVersion: Int = 20
    ) throws -> RecoverabilityArchiveIdentityV1 {
        try RecoverabilityArchiveIdentityV1(
            sourceWorkspaceID: workspaceID,
            sourceGenerationID: id(generationSlot),
            archiveByteCount: archiveByteCount,
            archiveSHA256: archiveSHA256 ?? digest("a"),
            archiveManifestSHA256: digest("b"),
            recordsSHA256: recordsSHA256 ?? digest("c"),
            contentManifestSHA256: contentManifestSHA256 ?? digest("d"),
            persistentSchemaVersion: persistentSchemaVersion,
            recordsSchemaVersion: recordsSchemaVersion,
            frontier: frontier,
            clientCapability: try capabilityBinding()
        )
    }

    static func plan(
        workspaceID: WorkspaceID,
        archive: RecoverabilityArchiveIdentityV1,
        mode: RecoverabilityVerificationModeV1,
        receiptSlot: Int,
        verificationSlot: Int,
        mutationSlot: Int,
        observedSourceFrontier: RecoveryPointFrontierV1? = nil,
        supersedesReceiptID: UUID? = nil,
        revision: UInt64 = 1
    ) throws -> RecoverabilityVerificationPlanV1 {
        try RecoverabilityVerificationPlanV1(
            verificationID: id(verificationSlot),
            receiptID: id(receiptSlot),
            workspaceID: workspaceID,
            archive: archive,
            mode: mode,
            observedSourceFrontier: observedSourceFrontier ?? archive.frontier,
            verifierBuild: try RecoverabilityVerifierBuildV1(
                semanticBuildID: "c22.verifier.v1",
                executableSHA256: digest("9")
            ),
            supersedesReceiptID: supersedesReceiptID,
            revision: revision,
            mutationID: try mutation(mutationSlot),
            plannedAt: fixedDate
        )
    }

    static func staging(
        for plan: RecoverabilityVerificationPlanV1,
        state: RecoverabilityStagingStateV1
    ) throws -> RecoverabilityVerificationStagingV1 {
        try RecoverabilityVerificationStagingV1(
            stagingID: id(500 + Int(plan.revision)),
            verificationID: plan.verificationID,
            workspaceID: plan.workspaceID,
            archive: plan.archive,
            mode: plan.mode,
            stagingLocatorToken: "c22-local-derived-staging",
            liveWorkspaceStateBeforeSHA256: digest("1"),
            sourceArchiveReadbackSHA256: plan.archive.archiveSHA256,
            state: state,
            createdAt: fixedDate.addingTimeInterval(1)
        )
    }

    static func replay(
        archive: RecoverabilityArchiveIdentityV1,
        restoredRecordsSHA256: String? = nil,
        replayedRecordsSHA256: String? = nil
    ) throws -> DeterministicRecoveryReplayReceiptV1 {
        try DeterministicRecoveryReplayReceiptV1(
            checkpointID: archive.frontier.checkpointID,
            orderedMutationCount: 3,
            orderedMutationDigestSHA256: digest("7"),
            restoredCanonicalStateSHA256: restoredRecordsSHA256 ?? archive.recordsSHA256,
            replayedCanonicalStateSHA256: replayedRecordsSHA256 ?? restoredRecordsSHA256 ?? archive.recordsSHA256
        )
    }

    static func reconciliation(
        archive: RecoverabilityArchiveIdentityV1,
        restoredManifestSHA256: String? = nil,
        missing: [String] = []
    ) throws -> RecoverabilityContentReconciliationV1 {
        try RecoverabilityContentReconciliationV1(
            expectedContentCount: 2,
            restoredContentCount: missing.isEmpty ? 2 : 1,
            expectedContentManifestSHA256: archive.contentManifestSHA256,
            restoredContentManifestSHA256: restoredManifestSHA256 ?? archive.contentManifestSHA256,
            missingContentSHA256s: missing
        )
    }

    static func cleanup(
        for staging: RecoverabilityVerificationStagingV1,
        stagingRemoved: Bool = true,
        liveAfterSHA256: String? = nil,
        sourceAfterSHA256: String? = nil,
        canonicalWorkspaceMutationCount: UInt64 = 0
    ) throws -> RecoverabilityCleanupProofV1 {
        try RecoverabilityCleanupProofV1(
            stagingID: staging.stagingID,
            verificationID: staging.verificationID,
            stagingRemoved: stagingRemoved,
            liveWorkspaceStateBeforeSHA256: staging.liveWorkspaceStateBeforeSHA256,
            liveWorkspaceStateAfterSHA256: liveAfterSHA256 ?? staging.liveWorkspaceStateBeforeSHA256,
            sourceArchiveSHA256Before: staging.archive.archiveSHA256,
            sourceArchiveSHA256After: sourceAfterSHA256 ?? staging.archive.archiveSHA256,
            canonicalWorkspaceMutationCount: canonicalWorkspaceMutationCount
        )
    }

    static func receipt(
        for plan: RecoverabilityVerificationPlanV1,
        staging: RecoverabilityVerificationStagingV1,
        disposition: RecoverabilityVerificationDispositionV1 = .passed,
        findings: [RecoverabilityFindingCodeV1] = [],
        restoredRecordsSHA256: String? = nil,
        contentReconciliation: RecoverabilityContentReconciliationV1? = nil,
        replayReceipt: DeterministicRecoveryReplayReceiptV1? = nil,
        cleanupProof: RecoverabilityCleanupProofV1? = nil,
        verifiedAtOffset: TimeInterval = 10
    ) throws -> RecoverabilityVerificationReceiptV1 {
        try RecoverabilityVerificationReceiptV1(
            receiptID: plan.receiptID,
            workspaceID: plan.workspaceID,
            verificationID: plan.verificationID,
            archive: plan.archive,
            mode: plan.mode,
            observedSourceFrontier: plan.observedSourceFrontier,
            freshness: plan.archive.frontier.freshness(relativeTo: plan.observedSourceFrontier),
            verifierBuild: plan.verifierBuild,
            restoredRecordsSHA256: restoredRecordsSHA256,
            contentReconciliation: contentReconciliation,
            replayReceipt: replayReceipt,
            cleanupProof: cleanupProof ?? cleanup(for: staging),
            disposition: disposition,
            findings: findings,
            verifiedAt: fixedDate.addingTimeInterval(verifiedAtOffset),
            supersedesReceiptID: plan.supersedesReceiptID,
            revision: plan.revision,
            mutationID: plan.mutationID
        )
    }

    static func lifecycleOperations(
        failMaterialization: Bool = false,
        cleanupObserver: C22RecoverabilityCleanupObserver? = nil
    ) -> RecoverabilityVerificationLifecycleOperationsV1 {
        RecoverabilityVerificationLifecycleOperationsV1(
            reserveStaging: { plan in
                try staging(for: plan, state: .cleanupRequired)
            },
            materializeStaging: { reservation in
                if failMaterialization {
                    throw RecoverabilityVerificationFailureV1.partialEffect
                }
                try reservation.advanced(to: .prepared)
            },
            validateStructure: { staging in
                try staging.advanced(to: .structureValidated)
            },
            dryRestore: { staging in
                let restored = try staging.advanced(to: .dryRestored)
                return try RecoverabilityDryRestoreArtifactsV1(
                    staging: restored,
                    restoredRecordsSHA256: staging.archive.recordsSHA256
                )
            },
            reconcileContent: { artifacts in
                let staging = try artifacts.staging.advanced(to: .contentReconciled)
                return (
                    staging: staging,
                    receipt: try reconciliation(archive: staging.archive)
                )
            },
            replay: { artifacts, staging in
                let replayed = try staging.advanced(to: .replayed)
                return (
                    staging: replayed,
                    receipt: try replay(archive: staging.archive, restoredRecordsSHA256: artifacts.restoredRecordsSHA256)
                )
            },
            cleanup: { staging in
                await cleanupObserver?.record(staging.stagingID)
                try cleanup(for: staging)
            },
            acceptedReceipt: { _ in nil },
            appendReceipt: { receipt in receipt }
        )
    }
}

extension V9_36RecoverabilityVerificationTests {
    func testC24AccessibleDocumentTypedAnchor() throws {
        XCTAssertEqual(AccessibleDocumentSemanticTreeV1.schemaVersion, 1)
        XCTAssertEqual(AccessibleDocumentRoleV1.allCases.count, 13)
        XCTAssertEqual(AccessibleDocumentAssessmentStateV1.allCases.count, 4)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
    }
}

actor C22RecoverabilityCleanupObserver {
    private var ids: [UUID] = []

    func record(_ id: UUID) { ids.append(id) }
    func numberOfCalls() -> Int { ids.count }
    func recordedIDs() -> [UUID] { ids }
}

actor C22RecoverabilityReceiptStore: RecoverabilityVerificationReceiptWritingV1 {
    private var values: [UUID: RecoverabilityVerificationReceiptV1] = [:]
    private var appendCount = 0

    func acceptedReceipt(for plan: RecoverabilityVerificationPlanV1) async throws
        -> RecoverabilityVerificationReceiptV1? {
        values[plan.receiptID]
    }

    func append(_ receipt: RecoverabilityVerificationReceiptV1) async throws
        -> RecoverabilityVerificationReceiptV1 {
        try receipt.validate()
        if let existing = values[receipt.receiptID] {
            guard existing == receipt else {
                throw RecoverabilityVerificationFailureV1.divergentRetry
            }
            return existing
        }
        values[receipt.receiptID] = receipt
        appendCount += 1
        return receipt
    }

    func numberOfAppends() -> Int { appendCount }
}

struct C22RecoverabilityCorpus: Decodable {
    struct Selector: Decodable {
        let id: String
        let selector: String
        let focus: String
    }

    let schema: String
    let schemaVersion: Int
    let corpusID: String
    let cardID: String
    let records: Int
    let recordsSchemaVersion: Int
    let persistentSchemaVersion: Int
    let persistentModelCount: Int
    let evidenceIDs: [String]
    let evidenceSelectors: [Selector]
    let modes: [String]
    let dispositions: [String]
    let freshness: [String]
    let stagingStates: [String]
    let findingCodes: [String]
    let coverage: [String]
    let interruptionBoundaries: [String]
    let recoveryDispositions: [String]
    let lifecycleConsumers: [String]
    let privacyExclusions: [String]
    let forbiddenClaims: [String]
    let immutableOriginals: Bool
    let externalCopyAvailabilityClaimed: Bool
    let liveRestorePermitted: Bool
    let receiptIncludedInVerifiedArchive: Bool
    let noSecondWriter: Bool
    let noSecondStore: Bool
}

@MainActor
final class V9_36RecoverabilityVerificationTests: XCTestCase {
    func testV23P03C22G01ValidArchiveDryRestoreReplayProducesExactReceipt() throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(corpus.schema, "V21P03C22RecoverabilityVerificationCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.cardID, "V23-P03-C22")
        XCTAssertEqual(corpus.records, 20)
        XCTAssertEqual(corpus.recordsSchemaVersion, 20)
        XCTAssertEqual(corpus.persistentSchemaVersion, 21)
        XCTAssertEqual(corpus.persistentModelCount, 82)
        XCTAssertEqual(corpus.evidenceSelectors.map(\.id), corpus.evidenceIDs)
        XCTAssertEqual(corpus.evidenceIDs, [
            "V23-P03-C22-G01", "V23-P03-C22-A01", "V23-P03-C22-H01",
            "V23-P03-C22-I01", "V23-P03-C22-R01"
        ])
        XCTAssertEqual(corpus.modes, RecoverabilityVerificationModeV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.dispositions, RecoverabilityVerificationDispositionV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.freshness, RecoveryPointFreshnessDispositionV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.stagingStates, RecoverabilityStagingStateV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.findingCodes, RecoverabilityFindingCodeV1.allCases.map(\.rawValue))
        XCTAssertTrue(corpus.immutableOriginals)
        XCTAssertFalse(corpus.externalCopyAvailabilityClaimed)
        XCTAssertFalse(corpus.liveRestorePermitted)
        XCTAssertFalse(corpus.receiptIncludedInVerifiedArchive)
        XCTAssertTrue(corpus.noSecondWriter)
        XCTAssertTrue(corpus.noSecondStore)

        XCTAssertEqual(PersistentSchemaV21.versionIdentifier, Schema.Version(21, 0, 0))
        XCTAssertEqual(PersistentSchemaV21.models.count, 82)
        XCTAssertEqual(PersistentSchemaMigrationPlanV20.schemas.count, 2)
        try V21RecoverabilityImportBoundaryV1.validate(
            persistentSchemaVersion: 21,
            recordsSchemaVersion: 20
        )
        XCTAssertThrowsError(try V21RecoverabilityImportBoundaryV1.validate(
            persistentSchemaVersion: 20,
            recordsSchemaVersion: 19
        ))

        let workspace = C22RecoverabilityTestSupport.workspace()
        let frontier = try C22RecoverabilityTestSupport.frontier()
        let archive = try C22RecoverabilityTestSupport.archive(workspaceID: workspace, frontier: frontier)
        let plan = try C22RecoverabilityTestSupport.plan(
            workspaceID: workspace,
            archive: archive,
            mode: .structureOnly,
            receiptSlot: 3,
            verificationSlot: 4,
            mutationSlot: 5
        )
        let staging = try C22RecoverabilityTestSupport.staging(for: plan, state: .prepared)
        try plan.validate()
        try staging.validate()
        XCTAssertEqual(staging.archive.archiveSHA256, staging.sourceArchiveReadbackSHA256)
        XCTAssertEqual(
            RecoverabilityVerificationLifecycleV1.stagingPersistence,
            "DERIVED_ONLY_DROP_AND_REBUILD"
        )
        XCTAssertEqual(
            RecoverabilityVerificationLifecycleV1.writer,
            "SOLE_CANONICAL_WORKSPACE_WRITER"
        )
    }

    func testV23P03C22A01CorruptTruncatedUnsupportedAndStaleArchivesFailClosed() throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(corpus.evidenceSelectors.map(\.selector), ["G01", "A01", "H01", "I01", "R01"])
        let workspace = C22RecoverabilityTestSupport.workspace()
        let frontier = try C22RecoverabilityTestSupport.frontier()
        let archive = try C22RecoverabilityTestSupport.archive(workspaceID: workspace, frontier: frontier)

        for (offset, mode) in RecoverabilityVerificationModeV1.allCases.enumerated() {
            let plan = try C22RecoverabilityTestSupport.plan(
                workspaceID: workspace,
                archive: archive,
                mode: mode,
                receiptSlot: 40 + offset,
                verificationSlot: 50 + offset,
                mutationSlot: 60 + offset
            )
            let staging = try C22RecoverabilityTestSupport.staging(for: plan, state: .replayed)
            let replay = mode == .structureOnly
                ? nil
                : try C22RecoverabilityTestSupport.replay(archive: archive)
            let content = mode == .fullContentReconciliation
                ? try C22RecoverabilityTestSupport.reconciliation(archive: archive)
                : nil
            let receipt = try C22RecoverabilityTestSupport.receipt(
                for: plan,
                staging: staging,
                restoredRecordsSHA256: mode == .structureOnly ? nil : archive.recordsSHA256,
                contentReconciliation: content,
                replayReceipt: replay
            )
            try receipt.validate()
            XCTAssertTrue(receipt.isPassingProof)
            XCTAssertFalse(receipt.receiptIncludedInVerifiedArchive)

            let encoded = try RecoverabilityVerificationCanonicalCodecV1.encode(receipt)
            XCTAssertEqual(
                try RecoverabilityVerificationCanonicalCodecV1.decode(
                    RecoverabilityVerificationReceiptV1.self,
                    from: encoded
                ),
                receipt
            )
            let row = try RecoverabilityVerificationReceiptRow(receipt)
            XCTAssertEqual(try row.value(), receipt)
        }

        let laterFrontier = try C22RecoverabilityTestSupport.frontier(
            revision: 13,
            sequence: 13,
            checkpointByte: "6",
            frontierByte: "8"
        )
        let historicPlan = try C22RecoverabilityTestSupport.plan(
            workspaceID: workspace,
            archive: archive,
            mode: .isolatedDryRestore,
            receiptSlot: 70,
            verificationSlot: 71,
            mutationSlot: 72,
            observedSourceFrontier: laterFrontier
        )
        let historicStaging = try C22RecoverabilityTestSupport.staging(for: historicPlan, state: .replayed)
        let historicReceipt = try C22RecoverabilityTestSupport.receipt(
            for: historicPlan,
            staging: historicStaging,
            restoredRecordsSHA256: archive.recordsSHA256,
            replayReceipt: try C22RecoverabilityTestSupport.replay(archive: archive)
        )
        XCTAssertEqual(historicReceipt.freshness, .historicAtVerification)
        try historicReceipt.validate()
        let currentProjection = try RecoverabilityFreshnessProjectionV1.derive(
            receipt: historicReceipt,
            currentArchiveSHA256: archive.archiveSHA256,
            currentSourceFrontier: laterFrontier
        )
        XCTAssertEqual(currentProjection.disposition, .historicAtVerification)
        XCTAssertTrue(currentProjection.remainsExactArchiveProof)

        let destination = C22RecoverabilityTestSupport.workspace(999)
        let rebound = try historicReceipt.rebound(to: destination)
        XCTAssertEqual(rebound.archive, historicReceipt.archive)
        XCTAssertEqual(rebound.freshness, .historicNoncurrent)
        try rebound.validate()
        XCTAssertFalse(
            try RecoverabilityFreshnessProjectionV1.derive(
                receipt: rebound,
                currentArchiveSHA256: archive.archiveSHA256,
                currentSourceFrontier: laterFrontier
            ).remainsExactArchiveProof
        )

        let successorPlan = try C22RecoverabilityTestSupport.plan(
            workspaceID: workspace,
            archive: archive,
            mode: .isolatedDryRestore,
            receiptSlot: 80,
            verificationSlot: 81,
            mutationSlot: 82,
            observedSourceFrontier: laterFrontier,
            supersedesReceiptID: historicReceipt.receiptID,
            revision: 2
        )
        let successor = try C22RecoverabilityTestSupport.receipt(
            for: successorPlan,
            staging: try C22RecoverabilityTestSupport.staging(for: successorPlan, state: .replayed),
            restoredRecordsSHA256: archive.recordsSHA256,
            replayReceipt: try C22RecoverabilityTestSupport.replay(archive: archive),
            verifiedAtOffset: 20
        )
        try successor.validateSuccessor(of: historicReceipt)
        XCTAssertEqual(successor.supersedesReceiptID, historicReceipt.receiptID)
        XCTAssertEqual(successor.revision, historicReceipt.revision + 1)
    }

    func testV23P03C22H01WrongBindingReplayDivergenceCancellationAndStorageFailClosed() throws {
        let workspace = C22RecoverabilityTestSupport.workspace()
        let frontier = try C22RecoverabilityTestSupport.frontier()
        let archive = try C22RecoverabilityTestSupport.archive(workspaceID: workspace, frontier: frontier)

        XCTAssertThrowsError(try RecoveryPointFrontierV1(
            workspaceRevision: 0,
            lastLocalSequence: 0,
            checkpointID: C22RecoverabilityTestSupport.digest(),
            checkpointFrontierSHA256: C22RecoverabilityTestSupport.digest()
        ))
        XCTAssertThrowsError(try RecoveryPointFrontierV1(
            workspaceRevision: 1,
            lastLocalSequence: 2,
            checkpointID: C22RecoverabilityTestSupport.digest(),
            checkpointFrontierSHA256: C22RecoverabilityTestSupport.digest()
        ))
        XCTAssertThrowsError(try C22RecoverabilityTestSupport.archive(
            workspaceID: workspace,
            frontier: frontier,
            archiveSHA256: "not-a-sha"
        ))
        XCTAssertThrowsError(try C22RecoverabilityTestSupport.archive(
            workspaceID: workspace,
            frontier: frontier,
            archiveByteCount: RecoverabilityValidationV1.maximumArchiveBytes + 1
        ))

        let plan = try C22RecoverabilityTestSupport.plan(
            workspaceID: workspace,
            archive: archive,
            mode: .isolatedDryRestore,
            receiptSlot: 100,
            verificationSlot: 101,
            mutationSlot: 102
        )
        let prepared = try C22RecoverabilityTestSupport.staging(for: plan, state: .prepared)
        let dryArtifacts = try RecoverabilityDryRestoreArtifactsV1(
            staging: try prepared.advanced(to: .dryRestored),
            restoredRecordsSHA256: archive.recordsSHA256
        )
        XCTAssertThrowsError(try RecoverabilityDryRestoreArtifactsV1(
            staging: prepared,
            restoredRecordsSHA256: archive.recordsSHA256
        ))
        XCTAssertThrowsError(try RecoverabilityVerificationStagingV1(
            stagingID: C22RecoverabilityTestSupport.id(111),
            verificationID: plan.verificationID,
            workspaceID: workspace,
            archive: archive,
            mode: plan.mode,
            stagingLocatorToken: "c22-local-derived-staging",
            liveWorkspaceStateBeforeSHA256: C22RecoverabilityTestSupport.digest("1"),
            sourceArchiveReadbackSHA256: C22RecoverabilityTestSupport.digest("z"),
            state: .dryRestored,
            createdAt: C22RecoverabilityTestSupport.fixedDate
        ))

        let replayDiverged = try C22RecoverabilityTestSupport.replay(
            archive: archive,
            replayedRecordsSHA256: C22RecoverabilityTestSupport.digest("x")
        )
        XCTAssertFalse(replayDiverged.reconciles)
        XCTAssertThrowsError(try C22RecoverabilityTestSupport.receipt(
            for: plan,
            staging: try prepared.advanced(to: .replayed),
            restoredRecordsSHA256: archive.recordsSHA256,
            replayReceipt: replayDiverged
        ))

        let incompleteContent = try C22RecoverabilityTestSupport.reconciliation(
            archive: archive,
            restoredManifestSHA256: C22RecoverabilityTestSupport.digest("x"),
            missing: [C22RecoverabilityTestSupport.digest("m")]
        )
        let fullPlan = try C22RecoverabilityTestSupport.plan(
            workspaceID: workspace,
            archive: archive,
            mode: .fullContentReconciliation,
            receiptSlot: 120,
            verificationSlot: 121,
            mutationSlot: 122
        )
        XCTAssertThrowsError(try C22RecoverabilityTestSupport.receipt(
            for: fullPlan,
            staging: try C22RecoverabilityTestSupport.staging(for: fullPlan, state: .replayed),
            restoredRecordsSHA256: archive.recordsSHA256,
            contentReconciliation: incompleteContent,
            replayReceipt: try C22RecoverabilityTestSupport.replay(archive: archive)
        ))

        let badCleanup = try C22RecoverabilityTestSupport.cleanup(
            for: prepared,
            stagingRemoved: false,
            liveAfterSHA256: C22RecoverabilityTestSupport.digest("2"),
            canonicalWorkspaceMutationCount: 1
        )
        XCTAssertThrowsError(try C22RecoverabilityTestSupport.receipt(
            for: plan,
            staging: prepared,
            cleanupProof: badCleanup
        ))

        let validReceipt = try C22RecoverabilityTestSupport.receipt(
            for: plan,
            staging: try prepared.advanced(to: .replayed),
            restoredRecordsSHA256: archive.recordsSHA256,
            replayReceipt: try C22RecoverabilityTestSupport.replay(archive: archive)
        )
        var forgedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: RecoverabilityVerificationCanonicalCodecV1.encode(validReceipt)
            ) as? [String: Any]
        )
        forgedObject["receiptIncludedInVerifiedArchive"] = true
        let forgedData = try JSONSerialization.data(
            withJSONObject: forgedObject,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let forgedReceipt = try RecoverabilityVerificationCanonicalCodecV1.decode(
            RecoverabilityVerificationReceiptV1.self,
            from: forgedData
        )
        XCTAssertThrowsError(try forgedReceipt.validate())

        forgedObject["schemaVersion"] = 2
        let unknownVersionData = try JSONSerialization.data(
            withJSONObject: forgedObject,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let unknownVersion = try RecoverabilityVerificationCanonicalCodecV1.decode(
            RecoverabilityVerificationReceiptV1.self,
            from: unknownVersionData
        )
        XCTAssertThrowsError(try unknownVersion.validate())

        XCTAssertThrowsError(try RecoverabilityVerificationLifecycleAdapterV1.disposition(
            forStaging: false,
            isCloneOrFork: false,
            includeInArchiveBeingVerified: true
        ))
        XCTAssertThrowsError(try V21RecoverabilityImportBoundaryV1.validate(
            persistentSchemaVersion: 22,
            recordsSchemaVersion: 21
        ))
        XCTAssertEqual(dryArtifacts.restoredRecordsSHA256, archive.recordsSHA256)
    }

    func testV23P03C22I01InterruptionAtEveryBoundaryLeavesNoPartialCanonicalSuccess() async throws {
        let workspace = C22RecoverabilityTestSupport.workspace()
        let frontier = try C22RecoverabilityTestSupport.frontier()
        let archive = try C22RecoverabilityTestSupport.archive(workspaceID: workspace, frontier: frontier)
        let plan = try C22RecoverabilityTestSupport.plan(
            workspaceID: workspace,
            archive: archive,
            mode: .fullContentReconciliation,
            receiptSlot: 200,
            verificationSlot: 201,
            mutationSlot: 202
        )

        let boundaries: [RecoverabilityVerificationInterruptionV1] = [
            .afterStagingPrepared,
            .afterStructureValidation,
            .afterDryRestore,
            .afterContentReconciliation,
            .afterReplay,
            .afterCleanupBeforeReceipt
        ]
        for boundary in boundaries {
            let adapter = RecoverabilityVerificationLifecycleAdapterV1(
                operations: C22RecoverabilityTestSupport.lifecycleOperations(),
                interruptionHook: { observed in
                    if observed == boundary { throw observed }
                }
            )
            let store = C22RecoverabilityReceiptStore()
            let coordinator = RecoverabilityVerificationCoordinatorV1(
                executor: adapter,
                receiptWriter: store
            )
            do {
                _ = try await coordinator.verify(plan, verifiedAt: C22RecoverabilityTestSupport.fixedDate)
                XCTFail("interruption (boundary) unexpectedly completed")
            } catch let error as RecoverabilityVerificationInterruptionV1 {
                XCTAssertEqual(error, boundary)
            } catch {
                XCTFail("unexpected interruption error: \(error)")
            }
        }

        let materializationCleanup = C22RecoverabilityCleanupObserver()
        let materializationAdapter = RecoverabilityVerificationLifecycleAdapterV1(
            operations: C22RecoverabilityTestSupport.lifecycleOperations(
                failMaterialization: true,
                cleanupObserver: materializationCleanup
            )
        )
        do {
            _ = try await materializationAdapter.prepare(plan)
            XCTFail("materialization failure unexpectedly completed")
        } catch let error as RecoverabilityVerificationFailureV1 {
            XCTAssertEqual(error, .partialEffect)
        }
        let materializationCleanupCount = await materializationCleanup.numberOfCalls()
        XCTAssertEqual(materializationCleanupCount, 1)

        let hookCleanup = C22RecoverabilityCleanupObserver()
        let hookAdapter = RecoverabilityVerificationLifecycleAdapterV1(
            operations: C22RecoverabilityTestSupport.lifecycleOperations(cleanupObserver: hookCleanup),
            interruptionHook: { boundary in
                if boundary == .afterStagingPrepared {
                    throw boundary
                }
            }
        )
        do {
            _ = try await hookAdapter.prepare(plan)
            XCTFail("post-materialization interruption unexpectedly completed")
        } catch let error as RecoverabilityVerificationInterruptionV1 {
            XCTAssertEqual(error, .afterStagingPrepared)
        }
        let hookCleanupCount = await hookCleanup.numberOfCalls()
        XCTAssertEqual(hookCleanupCount, 1)

        let store = C22RecoverabilityReceiptStore()
        let adapter = RecoverabilityVerificationLifecycleAdapterV1(
            operations: C22RecoverabilityTestSupport.lifecycleOperations()
        )
        let coordinator = RecoverabilityVerificationCoordinatorV1(
            executor: adapter,
            receiptWriter: store
        )
        let accepted = try await coordinator.verify(
            plan,
            verifiedAt: C22RecoverabilityTestSupport.fixedDate.addingTimeInterval(30)
        )
        try accepted.validate()
        XCTAssertEqual(accepted.mode, .fullContentReconciliation)
        XCTAssertEqual(accepted.archive, archive)
        XCTAssertEqual(accepted.restoredRecordsSHA256, archive.recordsSHA256)
        XCTAssertTrue(accepted.contentReconciliation?.isComplete == true)
        XCTAssertTrue(accepted.replayReceipt?.reconciles == true)
        let firstAppendCount = await store.numberOfAppends()
        XCTAssertEqual(firstAppendCount, 1)

        let retry = try await coordinator.verify(
            plan,
            verifiedAt: C22RecoverabilityTestSupport.fixedDate.addingTimeInterval(31)
        )
        XCTAssertEqual(retry, accepted)
        let retryAppendCount = await store.numberOfAppends()
        XCTAssertEqual(retryAppendCount, 1)

        let receiptBoundary = RecoverabilityVerificationInterruptionV1.afterReceiptCommitBeforeReturn
        let receiptAdapter = RecoverabilityVerificationLifecycleAdapterV1(
            operations: C22RecoverabilityTestSupport.lifecycleOperations(),
            interruptionHook: { observed in
                if observed == receiptBoundary { throw observed }
            }
        )
        let structurePlan = try C22RecoverabilityTestSupport.plan(
            workspaceID: workspace,
            archive: archive,
            mode: .structureOnly,
            receiptSlot: 210,
            verificationSlot: 211,
            mutationSlot: 212
        )
        let structureReceipt = try C22RecoverabilityTestSupport.receipt(
            for: structurePlan,
            staging: try C22RecoverabilityTestSupport.staging(for: structurePlan, state: .structureValidated)
        )
        do {
            _ = try await receiptAdapter.append(structureReceipt)
            XCTFail("receipt-return interruption unexpectedly completed")
        } catch let error as RecoverabilityVerificationInterruptionV1 {
            XCTAssertEqual(error, receiptBoundary)
        }
    }

    func testV23P03C22R01RecoveryDropsStagingAndPreservesAcceptedReceipt() throws {
        let workspace = C22RecoverabilityTestSupport.workspace()
        let frontier = try C22RecoverabilityTestSupport.frontier()
        let archive = try C22RecoverabilityTestSupport.archive(workspaceID: workspace, frontier: frontier)
        let plan = try C22RecoverabilityTestSupport.plan(
            workspaceID: workspace,
            archive: archive,
            mode: .isolatedDryRestore,
            receiptSlot: 300,
            verificationSlot: 301,
            mutationSlot: 302
        )
        let staging = try C22RecoverabilityTestSupport.staging(for: plan, state: .replayed)
        let receipt = try C22RecoverabilityTestSupport.receipt(
            for: plan,
            staging: staging,
            restoredRecordsSHA256: archive.recordsSHA256,
            replayReceipt: try C22RecoverabilityTestSupport.replay(archive: archive)
        )
        let canonicalReceipt = try RecoverabilityVerificationCanonicalCodecV1.encode(receipt)
        let backupRecord = V21BackupRecoverabilityReceiptRecordV1(
            id: receipt.receiptID,
            workspaceID: receipt.workspaceID.rawValue,
            revision: receipt.revision,
            canonicalData: canonicalReceipt
        )
        let records = V4BackupRecordsV1(
            recoverabilityReceipts: [backupRecord],
            assets: [],
            evidenceFiles: [],
            issues: [],
            packets: [],
            recordsSchemaVersion: 20,
            reports: [],
            sites: [],
            workflowRecords: []
        )
        let encoded = try BackupCanonicalEncoderV1().encodeRecords(records)
        let decoded = try BackupCanonicalDecoderV1().decodeRecords(encoded.data)
        XCTAssertEqual(decoded.recoverabilityReceipts, [backupRecord])

        let duplicateRecords = V4BackupRecordsV1(
            recoverabilityReceipts: [backupRecord, backupRecord],
            assets: [], evidenceFiles: [], issues: [], packets: [], recordsSchemaVersion: 20,
            reports: [], sites: [], workflowRecords: []
        )
        XCTAssertThrowsError(try BackupCanonicalEncoderV1().encodeRecords(duplicateRecords))

        let row = try RecoverabilityVerificationReceiptRow(receipt)
        XCTAssertEqual(try row.value(), receipt)
        row.canonicalData = Data("forged".utf8)
        XCTAssertThrowsError(try row.value())

        let clone = try receipt.rebound(to: C22RecoverabilityTestSupport.workspace(999))
        XCTAssertEqual(clone.archive.archiveSHA256, receipt.archive.archiveSHA256)
        XCTAssertEqual(clone.archive.sourceWorkspaceID, receipt.archive.sourceWorkspaceID)
        XCTAssertEqual(clone.freshness, .historicNoncurrent)
        XCTAssertFalse(clone.receiptIncludedInVerifiedArchive)
        try clone.validate()

        XCTAssertEqual(
            RecoverabilityVerificationLifecycleV1.backupEligibility,
            "SUBSEQUENT_BACKUPS_ONLY"
        )
        XCTAssertEqual(
            try RecoverabilityVerificationLifecycleAdapterV1.disposition(
                forStaging: true,
                isCloneOrFork: false,
                includeInArchiveBeingVerified: false
            ),
            .purgeDerivedStaging
        )
        XCTAssertEqual(
            try RecoverabilityVerificationLifecycleAdapterV1.disposition(
                forStaging: false,
                isCloneOrFork: true,
                includeInArchiveBeingVerified: false
            ),
            .preserveHistoricNoncurrentOnCloneOrFork
        )
        XCTAssertEqual(
            try RecoverabilityVerificationLifecycleAdapterV1.disposition(
                forStaging: false,
                isCloneOrFork: false,
                includeInArchiveBeingVerified: false
            ),
            .includeReceiptInSubsequentBackup
        )
        XCTAssertEqual(RecoverabilityVerificationLifecycleV1.receiptPersistence,
                       "RECOVERABILITY_VERIFICATION_RECEIPT_V1_IMMUTABLE_EVIDENCE")
        XCTAssertFalse(RecoverabilityVerificationLifecycleV1.externalCopyAvailabilityClaimed)
        XCTAssertFalse(RecoverabilityVerificationLifecycleV1.liveRestorePermitted)
        XCTAssertFalse(RecoverabilityVerificationLifecycleV1.receiptInsideVerifiedArchive)

        let changedArchiveProjection = try RecoverabilityFreshnessProjectionV1.derive(
            receipt: receipt,
            currentArchiveSHA256: C22RecoverabilityTestSupport.digest("z"),
            currentSourceFrontier: frontier
        )
        XCTAssertEqual(changedArchiveProjection.disposition, .historicNoncurrent)
        XCTAssertFalse(changedArchiveProjection.remainsExactArchiveProof)
    }

    private func loadCorpus() throws -> C22RecoverabilityCorpus {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "V21P03C22RecoverabilityVerificationCorpusV1",
                withExtension: "json",
                subdirectory: "Fixtures/V21/Recoverability"
            ) ?? bundle.url(
                forResource: "V21P03C22RecoverabilityVerificationCorpusV1",
                withExtension: "json"
            )
        )
        return try JSONDecoder().decode(C22RecoverabilityCorpus.self, from: Data(contentsOf: url))
    }
}

extension V9_36RecoverabilityVerificationTests {
    func testC23FieldReferencePackAnchor() throws {
        XCTAssertEqual(PersistentSchemaV22.versionIdentifier, Schema.Version(22, 0, 0))
        XCTAssertEqual(FieldReferencePackLifecycleV1.persistentFamilies.count, 2)
        XCTAssertNoThrow(try V22FieldReferenceImportBoundaryV1.validate(persistent: 22, records: 21))
    }
}

private final class C48PortableReviewV936RecoverabilityTests: XCTestCase {
    func testC48RecoverabilityPreservesExactExchangeBytesOutsideCanonicalSchema() {
        XCTAssertTrue(C48PortableExchangeMigrationBoundaryV2.preservesExactBytes)
        XCTAssertFalse(C48PortableExchangeMigrationBoundaryV2.canonicalSwiftDataSchemaChanged)
        XCTAssertTrue(C48PortableReviewPersistenceBoundaryV1.sessionStoreIsNonpersistent)
    }
}
private final class C49WorkResourceRecoverabilityBoundaryTests: XCTestCase {
    func testV23P03C49I01RecoveryContractUsesCanonicalPostimageAndRejectsDivergence() {
        XCTAssertTrue(C49WorkResourceContractBoundaryV1.appendOnly)
        XCTAssertEqual(C49WorkResourceRecoveryBoundaryV1.commandKind, .applyWorkResource)
        XCTAssertTrue(C49WorkResourceRecoveryBoundaryV1.effectBeforeReceiptRecoveryUsesCanonicalPostimage)
        XCTAssertTrue(C49WorkResourceRecoveryBoundaryV1.divergentSameMutationIsQuarantined)
    }
}

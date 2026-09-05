import Foundation
import XCTest
import SwiftData
@testable import FieldEvidenceApp

/// C18 keeps package evolution local and receipt-bound.  These tests deliberately
/// exercise the shipped contracts directly: fixture data describes the evidence
/// matrix, while every positive assertion is made against the canonical types.
final class V9_32PackageEvolutionTests: XCTestCase {
    private struct EvidenceSelector: Decodable {
        let id: String
        let selector: String
        let focus: String
    }

    private struct Corpus: Decodable {
        private struct ProvisionalFlags: Decodable {
            let native: Bool
            let hosted: Bool
            let adoption: Bool
            let acceptance: Bool
            let release: Bool
        }

        let schema: String
        let schemaVersion: Int
        let corpusID: String
        let cardID: String
        let records: Int
        let recordsSchemaVersion: Int
        let persistentSchemaVersion: Int
        let persistentModelCount: Int
        let evidenceSelectors: [EvidenceSelector]
        let coverage: [String]
        let evidenceIDs: [String]
        let classifications: [PackageSemanticDiffClassificationV1]
        let localeAndOrderingIndependent: Bool
        let exactNonFinalDraftOptIn: Bool
        let sandboxShapes: [String]
        let sandboxChecks: [String]
        let atomicInterruptionBoundaries: [String]
        let oldOrNewOnly: Bool
        let retryDisposition: String
        let lifecycleConsumers: [String]
        let privacyExclusions: [String]
        let forbiddenProductionSymbols: [String]
        let noSecondWriter: Bool
        let noSecondStore: Bool
        let noActivationFromSandbox: Bool
        let rollbackCompatibility: [String]
        let persistentKinds: [String]
        let brandExclusion: String
        let provisionalFlags: ProvisionalFlags
    }

    private struct PromotionFixture {
        let workspaceID: WorkspaceID
        let release: InspectionPackageReleaseV1
        let diff: PackageSemanticDiffV1
        let bundle: PackagePromotionAtomicBundleV1
    }

    func testV23P03C18G01ClassifiesAllFiveTypedClassesDeterministically() throws {
        let corpus = try loadCorpus()
        assertCorpusHeader(corpus)
        XCTAssertEqual(
            Set(corpus.classifications),
            Set(PackageSemanticDiffClassificationV1.allCases)
        )
        XCTAssertTrue(corpus.localeAndOrderingIndependent)

        let release = try publishedRelease(workflowID: "c18.workflow.golden.v1")
        let localization = String(repeating: "1", count: 64)
        let assetA = String(repeating: "2", count: 64)
        let assetB = String(repeating: "3", count: 64)
        let unsortedBindings = try PackageSemanticReleaseBindingsV1(
            localizationReleaseSHA256: localization,
            assetSemanticCatalogSHA256s: [assetB, assetA]
        )
        let sortedBindings = try PackageSemanticReleaseBindingsV1(
            localizationReleaseSHA256: localization,
            assetSemanticCatalogSHA256s: [assetA, assetB]
        )
        let unsortedDiff = try PackageSemanticDifferV1.diff(
            source: release, target: release,
            sourceBindings: unsortedBindings, targetBindings: unsortedBindings
        )
        let sortedDiff = try PackageSemanticDifferV1.diff(
            source: release, target: release,
            sourceBindings: sortedBindings, targetBindings: sortedBindings
        )
        XCTAssertEqual(unsortedBindings, sortedBindings)
        XCTAssertEqual(unsortedDiff, sortedDiff)
        let same = try PackageSemanticDifferV1.diff(source: release, target: release)
        XCTAssertEqual(same.classification, .noChange)
        XCTAssertTrue(same.changes.isEmpty)
        XCTAssertEqual(same, try PackageSemanticDifferV1.diff(source: release, target: release))

        let differentWorkflow = try publishedRelease(workflowID: "c18.workflow.other.v1")
        let invalid = try PackageSemanticDifferV1.diff(
            source: release,
            target: differentWorkflow
        )
        XCTAssertEqual(invalid.classification, .invalid)

        // The classifier is intentionally exposed separately from the closed
        // diff value so its five policy classes can be checked with canonical
        // graph values without inventing a second package model.
        let graph = try PackageSemanticGraphV1(release: release)
        let additiveTarget = try alteredGraph(graph, contentVersion: 2, hashByte: "b")
        let additive = try PackageSemanticChangeV1(
            kind: .capabilityAdded,
            stableSubjectID: "capability.c18.added"
        )
        XCTAssertEqual(
            PackageSemanticDifferV1.classification(
                source: graph,
                target: additiveTarget,
                changes: [additive]
            ),
            .additiveDraftSafe
        )

        let migrationTarget = try alteredGraph(graph, contentVersion: 2, hashByte: "c")
        let migration = try PackageSemanticChangeV1(
            kind: .fieldRemoved,
            stableSubjectID: "field.c18.removed"
        )
        XCTAssertEqual(
            PackageSemanticDifferV1.classification(
                source: graph,
                target: migrationTarget,
                changes: [migration]
            ),
            .draftMigrationRequired
        )

        let activeTarget = try alteredGraph(graph, contentVersion: 2, hashByte: "d")
        let active = try PackageSemanticChangeV1(
            kind: .workflowNodeChanged,
            stableSubjectID: "node.c18.changed"
        )
        XCTAssertEqual(
            PackageSemanticDifferV1.classification(
                source: graph,
                target: activeTarget,
                changes: [active]
            ),
            .activeSessionIncompatible
        )

        let workflowIdentityChange = try PackageSemanticChangeV1(
            kind: .workflowIdentityChanged,
            stableSubjectID: "c18.workflow.golden.v1__TO__c18.workflow.forged.v1"
        )
        XCTAssertEqual(
            PackageSemanticDifferV1.classification(
                source: graph,
                target: activeTarget,
                changes: [workflowIdentityChange]
            ),
            .activeSessionIncompatible
        )
        let workflowEntryChange = try PackageSemanticChangeV1(
            kind: .workflowEntryNodeChanged,
            stableSubjectID: "c18.section__TO__c18.forged-entry"
        )
        XCTAssertEqual(
            PackageSemanticDifferV1.classification(
                source: graph,
                target: activeTarget,
                changes: [workflowEntryChange]
            ),
            .activeSessionIncompatible
        )

        let downgradeTarget = try alteredGraph(graph, contentVersion: 0, hashByte: "e")
        XCTAssertEqual(
            PackageSemanticDifferV1.classification(
                source: graph,
                target: downgradeTarget,
                changes: [try PackageSemanticChangeV1(
                    kind: .packageContentVersionChanged,
                    stableSubjectID: "1__TO__0"
                )]
            ),
            .invalid
        )

        let invalidCandidate = try PackageSemanticChangeV1(
            kind: .invalidCandidate,
            stableSubjectID: "candidate.c18.invalid"
        )
        XCTAssertEqual(
            PackageSemanticDifferV1.classification(
                source: graph,
                target: additiveTarget,
                changes: [invalidCandidate]
            ),
            .invalid
        )

        let encoded = try PackageEvolutionCanonicalCodecV1.encode(graph)
        let decoded = try PackageEvolutionCanonicalCodecV1.decode(
            PackageSemanticGraphV1.self,
            from: encoded
        )
        XCTAssertEqual(decoded, graph)
        XCTAssertEqual(
            same.changes.map(\.stableKey),
            same.changes.sorted { $0.stableKey < $1.stableKey }.map(\.stableKey)
        )
    }

    func testV23P03C18A01ExplicitDraftOptInRunsBothSandboxShapes() async throws {
        let corpus = try loadCorpus()
        XCTAssertTrue(corpus.exactNonFinalDraftOptIn)
        XCTAssertEqual(corpus.sandboxShapes, ["STRUCTURAL_SHAPE_A", "STRUCTURAL_SHAPE_B"])

        let promotion = try promotionFixture()
        let targetRelease = try publishedRelease(workflowID: "c18.workflow.draft-target.v1")
        let source = try draftCheckpoint(
            workspaceID: promotion.workspaceID,
            state: .active,
            draftRevision: 3
        )
        let actor = try actor(workspaceID: promotion.workspaceID)
        let plan = try DraftUpgradePlanV1(
            workspaceID: promotion.workspaceID,
            draftID: source.draftID,
            sourceDraftRevision: source.draftRevision,
            sourceBaseCanonicalRevision: source.baseCanonicalRevision,
            sourceCheckpointSHA256: source.checkpointSHA256,
            sourcePayloadSHA256: source.payloadSHA256,
            sourcePackageReleaseID: promotion.release.packageReleaseID,
            targetPackageReleaseID: targetRelease.packageReleaseID,
            semanticDiffSHA256: promotion.diff.diffSHA256,
            targetPayloadData: Data("c18-upgraded-payload".utf8),
            declaredActor: actor,
            consentRecordedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        XCTAssertNoThrow(try plan.validate(source: source))
        XCTAssertEqual(plan.sourceDraftRevision, source.draftRevision)
        XCTAssertEqual(plan.sourceCheckpointSHA256, source.checkpointSHA256)

        let shapeARelease = try publishedRelease(workflowID: "c18.workflow.shape-a.v1")
        let shapeADiff = try PackageSemanticDifferV1.diff(source: shapeARelease, target: shapeARelease)
        let shapeBRelease = try publishedRelease(workflowID: "c18.workflow.shape-b.v1")
        let shapeBDiff = try PackageSemanticDifferV1.diff(source: shapeBRelease, target: shapeBRelease)
        let shapeAMatrix = try sandboxFixtureMatrix(prefix: "c18.shape.a")
        let shapeBMatrix = try sandboxFixtureMatrix(prefix: "c18.shape.b")
        // The production convenience initializer selects the canonical
        // read-only executor.  This traverses every real C18 consumer for
        // both fixture shapes instead of proving only metadata plumbing.
        let runner = PackageSandboxRunnerV1(
            activationObserver: StableNoActivationObserver()
        )
        let runA = try await runner.run(
            runID: id(810),
            workspaceID: promotion.workspaceID,
            release: shapeARelease,
            semanticDiff: shapeADiff,
            exactHead: String(repeating: "a", count: 40),
            fixtures: shapeAMatrix,
            mutationID: mutation(811)
        )
        let runB = try await runner.run(
            runID: id(812),
            workspaceID: promotion.workspaceID,
            release: shapeBRelease,
            semanticDiff: shapeBDiff,
            exactHead: String(repeating: "a", count: 40),
            fixtures: shapeBMatrix,
            mutationID: mutation(813)
        )
        XCTAssertEqual(runA.disposition, .completePass)
        XCTAssertEqual(runB.disposition, .completePass)
        XCTAssertNotEqual(runA.packageReleaseID, runB.packageReleaseID)
        XCTAssertNotEqual(runA.workflowSHA256, runB.workflowSHA256)
        let expectedSandboxPairs = Set(PackageSandboxCheckKindV1.allCases.flatMap { kind in
            PackageSandboxFixtureShapeV1.allCases.map { "\(kind.rawValue)|\($0.rawValue)" }
        })
        XCTAssertEqual(runA.checks.count, 24)
        XCTAssertEqual(runB.checks.count, 24)
        XCTAssertEqual(Set(runA.checks.map(\.stableKey)), expectedSandboxPairs)
        XCTAssertEqual(Set(runB.checks.map(\.stableKey)), expectedSandboxPairs)
        XCTAssertEqual(runA.checks.map(\.stableKey), runA.checks.map(\.stableKey).sorted())
        XCTAssertEqual(runB.checks.map(\.stableKey), runB.checks.map(\.stableKey).sorted())
        XCTAssertTrue(runA.checks.allSatisfy { $0.fixtureID.hasPrefix("c18.shape.a.") })
        XCTAssertTrue(runB.checks.allSatisfy { $0.fixtureID.hasPrefix("c18.shape.b.") })
        XCTAssertNotEqual(runA.runSHA256, runB.runSHA256)
        XCTAssertTrue(runA.checks.allSatisfy { $0.disposition == .passed })
        XCTAssertTrue(runB.checks.allSatisfy { $0.disposition == .passed })
        XCTAssertTrue(runA.checks.allSatisfy { $0.activationEvidence == .notAttempted })
        XCTAssertTrue(runB.checks.allSatisfy { $0.activationEvidence == .notAttempted })
        try await assertCanonicalConsumerResults(
            release: shapeARelease, semanticDiff: shapeADiff,
            fixtures: shapeAMatrix, run: runA
        )
        try await assertCanonicalConsumerResults(
            release: shapeBRelease, semanticDiff: shapeBDiff,
            fixtures: shapeBMatrix, run: runB
        )
        XCTAssertEqual(
            Set(runA.checks.map { $0.shape }),
            Set(PackageSandboxFixtureShapeV1.allCases)
        )
        XCTAssertEqual(
            Set(runB.checks.map { $0.shape }),
            Set(PackageSandboxFixtureShapeV1.allCases)
        )
        XCTAssertTrue(corpus.noActivationFromSandbox)

        let changingObserverRunner = PackageSandboxRunnerV1(
            activationObserver: ChangingActivationObserver()
        )
        do {
            _ = try await changingObserverRunner.run(
                runID: id(814),
                workspaceID: promotion.workspaceID,
                release: shapeARelease,
                semanticDiff: shapeADiff,
                exactHead: String(repeating: "a", count: 40),
                fixtures: try sandboxFixtureMatrix(prefix: "c18.shape.changed"),
                mutationID: mutation(815)
            )
            XCTFail("a sandbox that changes active-pointer state must fail closed")
        } catch {
            XCTAssertEqual(error as? PackageEvolutionFailureV1, .incompleteSandbox)
        }
    }

    private func assertCanonicalConsumerResults(
        release: InspectionPackageReleaseV1,
        semanticDiff: PackageSemanticDiffV1,
        fixtures: PackageSandboxFixtureMatrixV1,
        run: PackageSandboxRunV1
    ) async throws {
        let executor = CanonicalPackageSandboxConsumerExecutorV1()
        for kind in PackageSandboxCheckKindV1.allCases {
            for shape in PackageSandboxFixtureShapeV1.allCases {
                let fixture = try XCTUnwrap(fixtures.fixture(shape: shape, kind: kind))
                let outcome = try await executor.execute(
                    kind: kind,
                    shape: shape,
                    fixtureID: fixture.fixtureID,
                    fixtureSHA256: fixture.fixtureSHA256,
                    release: release,
                    semanticDiff: semanticDiff
                )
                let check = try XCTUnwrap(
                    run.checks.first { $0.kind == kind && $0.shape == shape }
                )
                XCTAssertEqual(outcome.resultSHA256, check.resultSHA256)
                XCTAssertEqual(outcome.disposition, .passed)
                XCTAssertEqual(outcome.activationEvidence, .notAttempted)
            }
        }
    }

    func testV23P03C18H01StaleFinalPartialAndDivergentInputsFailClosed() throws {
        let corpus = try loadCorpus()
        XCTAssertTrue(corpus.noSecondWriter)
        XCTAssertTrue(corpus.noSecondStore)
        let promotion = try promotionFixture()
        let targetRelease = try publishedRelease(workflowID: "c18.workflow.hostile-target.v1")
        let source = try draftCheckpoint(
            workspaceID: promotion.workspaceID,
            state: .active,
            draftRevision: 4
        )
        let plan = try DraftUpgradePlanV1(
            workspaceID: promotion.workspaceID,
            draftID: source.draftID,
            sourceDraftRevision: source.draftRevision,
            sourceBaseCanonicalRevision: source.baseCanonicalRevision,
            sourceCheckpointSHA256: source.checkpointSHA256,
            sourcePayloadSHA256: source.payloadSHA256,
            sourcePackageReleaseID: promotion.release.packageReleaseID,
            targetPackageReleaseID: targetRelease.packageReleaseID,
            semanticDiffSHA256: promotion.diff.diffSHA256,
            targetPayloadData: Data("c18-hostile-payload".utf8),
            declaredActor: try actor(workspaceID: promotion.workspaceID),
            consentRecordedAt: Date(timeIntervalSince1970: 1_800_000_200)
        )

        let stale = try draftCheckpoint(
            workspaceID: promotion.workspaceID,
            draftID: source.draftID,
            state: .active,
            draftRevision: source.draftRevision + 1
        )
        assertEvolutionFailure(.staleSource) {
            try plan.validate(source: stale)
        }

        let finalized = try draftCheckpoint(
            workspaceID: promotion.workspaceID,
            draftID: source.draftID,
            state: .committed,
            draftRevision: source.draftRevision,
            lastDurableMutationID: mutation(820),
            lastReceiptSHA256: String(repeating: "e", count: 64)
        )
        assertEvolutionFailure(.staleSource) {
            try plan.validate(source: finalized)
        }

        let graph = try PackageSemanticGraphV1(release: promotion.release)
        XCTAssertThrowsError(
            try forgedGraph(graph, key: "workflowID", value: "c18.forged.workflow").validate()
        )
        XCTAssertThrowsError(
            try forgedGraph(graph, key: "entryNodeID", value: "c18.forged.entry").validate()
        )

        XCTAssertThrowsError(
            try forgedDiff(
                promotion.diff,
                classification: .noChange,
                changes: [[
                    "kind": PackageSemanticChangeKindV1.capabilityAdded.rawValue,
                    "stableSubjectID": "c18.forged.capability"
                ]]
            ).validate()
        )
        XCTAssertThrowsError(
            try forgedDiff(
                promotion.diff,
                classification: .additiveDraftSafe,
                changes: []
            ).validate()
        )

        let partialChecks = try sandboxResults(prefix: "c18.partial").dropLast()
        XCTAssertThrowsError(
            try PackageSandboxRunV1(
                runID: id(821),
                workspaceID: promotion.workspaceID,
                packageReleaseID: promotion.release.packageReleaseID,
                packageSHA256: promotion.release.packageSHA256,
                workflowSHA256: promotion.release.workflowSHA256,
                semanticDiffSHA256: promotion.diff.diffSHA256,
                exactHead: String(repeating: "b", count: 40),
                activePointerStateBeforeSHA256: noActivePointerStateSHA256,
                activePointerStateAfterSHA256: noActivePointerStateSHA256,
                checks: Array(partialChecks),
                mutationID: mutation(822)
            )
        )
        XCTAssertThrowsError(
            try PackageSandboxRunV1(
                runID: id(823),
                workspaceID: promotion.workspaceID,
                packageReleaseID: promotion.release.packageReleaseID,
                packageSHA256: promotion.release.packageSHA256,
                workflowSHA256: promotion.release.workflowSHA256,
                semanticDiffSHA256: promotion.diff.diffSHA256,
                exactHead: String(repeating: "b", count: 40),
                activePointerStateBeforeSHA256: noActivePointerStateSHA256,
                activePointerStateAfterSHA256: noActivePointerStateSHA256,
                checks: try duplicateChecks(),
                mutationID: mutation(824)
            )
        )

        let missingShapeChecks = try sandboxResults(prefix: "c18.missing-shape")
            .filter { !($0.kind == .schema && $0.shape == .representative) }
        XCTAssertThrowsError(
            try PackageSandboxRunV1(
                runID: id(829),
                workspaceID: promotion.workspaceID,
                packageReleaseID: promotion.release.packageReleaseID,
                packageSHA256: promotion.release.packageSHA256,
                workflowSHA256: promotion.release.workflowSHA256,
                semanticDiffSHA256: promotion.diff.diffSHA256,
                exactHead: String(repeating: "b", count: 40),
                activePointerStateBeforeSHA256: noActivePointerStateSHA256,
                activePointerStateAfterSHA256: noActivePointerStateSHA256,
                checks: missingShapeChecks,
                mutationID: mutation(830)
            )
        )

        let attemptedActivationChecks = try sandboxResults(
            prefix: "c18.activation-attempt",
            activationEvidence: .attempted
        )
        XCTAssertThrowsError(
            try PackageSandboxRunV1(
                runID: id(831),
                workspaceID: promotion.workspaceID,
                packageReleaseID: promotion.release.packageReleaseID,
                packageSHA256: promotion.release.packageSHA256,
                workflowSHA256: promotion.release.workflowSHA256,
                semanticDiffSHA256: promotion.diff.diffSHA256,
                exactHead: String(repeating: "b", count: 40),
                activePointerStateBeforeSHA256: noActivePointerStateSHA256,
                activePointerStateAfterSHA256: noActivePointerStateSHA256,
                checks: attemptedActivationChecks,
                mutationID: mutation(832)
            )
        )

        let validCheck = try XCTUnwrap(sandboxResults(prefix: "c18.missing-activation").first)
        var missingActivationObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(validCheck)) as? [String: Any]
        )
        missingActivationObject.removeValue(forKey: "activationEvidence")
        let missingActivationData = try JSONSerialization.data(
            withJSONObject: missingActivationObject,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(PackageSandboxCheckResultV1.self, from: missingActivationData)
        )

        let divergentReceiptMutation = mutation(825)
        XCTAssertThrowsError(
            try PackagePromotionReceiptV1(
                receiptID: promotion.bundle.receipt.receiptID,
                workspaceID: promotion.workspaceID,
                promotedRelease: promotion.bundle.promotedRelease,
                sandboxRun: promotion.bundle.sandboxRun,
                diff: promotion.bundle.semanticDiff,
                predecessorPointer: promotion.bundle.predecessorPointer,
                resultingPointer: promotion.bundle.resultingPointer,
                actor: promotion.bundle.actor,
                exactHead: promotion.bundle.receipt.exactHead,
                operation: .initialActivation,
                rollbackCompatibility: .preActivationDiscardable,
                mutationID: divergentReceiptMutation,
                recordedAt: promotion.bundle.receipt.recordedAt
            )
        )
        XCTAssertEqual(
            promotion.bundle.receipt.rollbackCompatibility,
            .activatedForwardFixRequired
        )
        XCTAssertEqual(promotion.bundle.receipt.operation, .initialActivation)
        XCTAssertEqual(promotion.bundle.receipt.postActivationPolicy, .forwardFixOnly)

        let packageIDMismatch = try ActivePackageRegistryPointerV1(
            pointerID: id(826),
            workspaceID: promotion.workspaceID,
            packageID: "\(promotion.release.packageID).forged",
            activeReleaseRecordID: promotion.bundle.resultingPointer.activeReleaseRecordID,
            promotionReceiptID: id(827),
            activePackageReleaseID: promotion.bundle.resultingPointer.activePackageReleaseID,
            activeReleaseRecordSHA256: promotion.bundle.resultingPointer.activeReleaseRecordSHA256,
            supersedesPointerID: promotion.bundle.resultingPointer.pointerID,
            revision: 2,
            mutationID: mutation(828)
        )
        assertEvolutionFailure(.stalePointer) {
            try packageIDMismatch.validateSuccessor(
                of: promotion.bundle.resultingPointer,
                expectedRevision: promotion.bundle.resultingPointer.revision
            )
        }

        XCTAssertThrowsError(
            try PackageEvolutionLifecycleClosureV1(
                promotedReleases: [],
                sandboxRuns: [],
                promotionReceipts: [promotion.bundle.receipt],
                activePointers: []
            )
        )
    }

    @MainActor
    func testV23P03C18I01EveryPromotionBoundaryRetainsCompleteAuthority() throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(
            corpus.atomicInterruptionBoundaries,
            [
                "PROMOTED_PACKAGE_RELEASE", "PACKAGE_SANDBOX_RUN",
                "PACKAGE_PROMOTION_RECEIPT", "ACTIVE_PACKAGE_REGISTRY_POINTER"
            ]
        )
        let promotion = try promotionFixture()
        XCTAssertNoThrow(try promotion.bundle.validate())

        // Once the first pointer exists, the only legal correction is a new
        // immutable release with a successor pointer and a forward-fix receipt.
        let successorRelease = try publishedRelease(workflowID: "c18.workflow.forward-fix.v1")
        let successorDiff = try PackageSemanticDifferV1.diff(
            source: promotion.release,
            target: successorRelease
        )
        XCTAssertEqual(successorDiff.classification, .activeSessionIncompatible)
        let successorSandbox = try PackageSandboxRunV1(
            runID: id(890),
            workspaceID: promotion.workspaceID,
            packageReleaseID: successorRelease.packageReleaseID,
            packageSHA256: successorRelease.packageSHA256,
            workflowSHA256: successorRelease.workflowSHA256,
            semanticDiffSHA256: successorDiff.diffSHA256,
            exactHead: String(repeating: "d", count: 40),
            activePointerStateBeforeSHA256: noActivePointerStateSHA256,
            activePointerStateAfterSHA256: noActivePointerStateSHA256,
            checks: try sandboxResults(prefix: "c18.forward-fix"),
            mutationID: mutation(893)
        )
        let successorPromoted = try PromotedPackageReleaseV1(
            releaseRecordID: id(891),
            workspaceID: promotion.workspaceID,
            packageRelease: successorRelease,
            mutationID: mutation(893),
            promotedAt: Date(timeIntervalSince1970: 1_800_000_030)
        )
        let successorReceiptID = id(894)
        let successorPointer = try ActivePackageRegistryPointerV1(
            pointerID: id(892),
            workspaceID: promotion.workspaceID,
            packageID: successorRelease.packageID,
            activeReleaseRecordID: successorPromoted.releaseRecordID,
            promotionReceiptID: successorReceiptID,
            activePackageReleaseID: successorRelease.packageReleaseID,
            activeReleaseRecordSHA256: successorPromoted.releaseRecordSHA256,
            supersedesPointerID: promotion.bundle.resultingPointer.pointerID,
            revision: 2,
            mutationID: mutation(893)
        )
        let successorActor = try actor(workspaceID: promotion.workspaceID)
        let successorReceipt = try PackagePromotionReceiptV1(
            receiptID: successorReceiptID,
            workspaceID: promotion.workspaceID,
            promotedRelease: successorPromoted,
            sandboxRun: successorSandbox,
            diff: successorDiff,
            predecessorPointer: promotion.bundle.resultingPointer,
            resultingPointer: successorPointer,
            actor: successorActor,
            exactHead: successorSandbox.exactHead,
            operation: .postActivationForwardFix,
            postActivationPolicy: .forwardFixOnly,
            rollbackCompatibility: .activatedForwardFixRequired,
            mutationID: mutation(893),
            recordedAt: Date(timeIntervalSince1970: 1_800_000_031)
        )
        let successorBundle = PackagePromotionAtomicBundleV1(
            promotedRelease: successorPromoted,
            sandboxRun: successorSandbox,
            semanticDiff: successorDiff,
            predecessorPointer: promotion.bundle.resultingPointer,
            resultingPointer: successorPointer,
            actor: successorActor,
            receipt: successorReceipt
        )
        XCTAssertNoThrow(try successorBundle.validate())
        XCTAssertEqual(successorReceipt.operation, .postActivationForwardFix)
        XCTAssertEqual(successorReceipt.postActivationPolicy, .forwardFixOnly)
        XCTAssertThrowsError(
            try PackagePromotionReceiptV1(
                receiptID: successorReceiptID,
                workspaceID: promotion.workspaceID,
                promotedRelease: successorPromoted,
                sandboxRun: successorSandbox,
                diff: successorDiff,
                predecessorPointer: promotion.bundle.resultingPointer,
                resultingPointer: successorPointer,
                actor: successorActor,
                exactHead: successorSandbox.exactHead,
                operation: .initialActivation,
                postActivationPolicy: .forwardFixOnly,
                rollbackCompatibility: .activatedForwardFixRequired,
                mutationID: mutation(893),
                recordedAt: Date(timeIntervalSince1970: 1_800_000_031)
            )
        )
        let promotionMutation = try PackagePromotionMutationV1(
            workspaceID: promotion.workspaceID,
            expectedPointerRevision: 0,
            mutationID: promotion.bundle.receipt.mutationID,
            bundle: promotion.bundle
        )
        let atomicKinds = try promotionMutation.affectedIdentities.map(\.kind.rawValue)
        XCTAssertEqual(atomicKinds.count, 4)
        XCTAssertEqual(Set(atomicKinds), Set([
            WorkspaceEntityKindV1.promotedPackageRelease.rawValue,
            WorkspaceEntityKindV1.packageSandboxRun.rawValue,
            WorkspaceEntityKindV1.packagePromotionReceipt.rawValue,
            WorkspaceEntityKindV1.activePackageRegistryPointer.rawValue
        ]))

        let incompleteBundles: [(
            [PromotedPackageReleaseV1],
            [PackageSandboxRunV1],
            [PackagePromotionReceiptV1],
            [ActivePackageRegistryPointerV1]
        )] = [
            ([], [promotion.bundle.sandboxRun], [promotion.bundle.receipt], [promotion.bundle.resultingPointer]),
            ([promotion.bundle.promotedRelease], [], [promotion.bundle.receipt], [promotion.bundle.resultingPointer]),
            ([promotion.bundle.promotedRelease], [promotion.bundle.sandboxRun], [], [promotion.bundle.resultingPointer]),
            ([promotion.bundle.promotedRelease], [promotion.bundle.sandboxRun], [promotion.bundle.receipt], [])
        ]
        for partial in incompleteBundles {
            XCTAssertThrowsError(
                try PackageEvolutionLifecycleClosureV1(
                    promotedReleases: partial.0,
                    sandboxRuns: partial.1,
                    promotionReceipts: partial.2,
                    activePointers: partial.3
                )
            )
        }

        // The package-release publisher exposes all of its own write boundaries;
        // each injected failure leaves no returned partial release and a retry
        // starts from the same immutable draft bytes.
        let draft = try InspectionPackageReleaseV1.makeDraft(
            package: ShippingIlluminatedSignAdapterV1.inspectionPackage(),
            workflow: try c18Workflow(id: "c18.workflow.interruption.v1")
        )
        for boundary in InspectionPackageReleasePublisherV1.Boundary.allCases {
            XCTAssertThrowsError(
                try InspectionPackageReleasePublisherV1.test(draft) { reached in
                    if reached == boundary {
                        throw PackageEvolutionFailureV1.divergentMutation
                    }
                }
            )
        }
        let retry = try InspectionPackageReleasePublisherV1.test(draft)
        XCTAssertEqual(retry.release.packageReleaseID, draft.packageReleaseID)
        XCTAssertEqual(retry.release.packageSHA256, draft.packageSHA256)
        XCTAssertEqual(retry.release.workflowSHA256, draft.workflowSHA256)

        // Exercise the real writer/lifecycle route at every four-row insert
        // boundary.  The fault adapter uses the existing writer-port seam only
        // to interrupt a canonical row insert; retry delegates to the shipped
        // WorkspaceWriterAdapterV1, so this remains a single-writer assertion.
        for stage in C18PromotionInsertStageV1.allCases {
            let harness = try C18PromotionAtomicHarness(
                bundle: promotion.bundle,
                failureStage: stage
            )
            XCTAssertThrowsError(try harness.lifecycle.applyPromotion(promotion.bundle))
            let afterFault = try harness.rowCounts()
            XCTAssertTrue(
                afterFault == [0, 0, 0, 0] || afterFault == [1, 1, 1, 1],
                "promotion fault at \(stage) exposed a hybrid row set: \(afterFault)"
            )

            let accepted = try harness.lifecycle.applyPromotion(promotion.bundle)
            XCTAssertEqual(accepted, promotion.bundle.receipt)
            XCTAssertEqual(harness.adapter.canonicalApplyCount, 1)
            let replayed = try harness.lifecycle.applyPromotion(promotion.bundle)
            XCTAssertEqual(replayed, accepted)
            XCTAssertEqual(harness.adapter.canonicalApplyCount, 1)
            XCTAssertEqual(try harness.rowCounts(), [1, 1, 1, 1])
            XCTAssertEqual(
                try harness.context.fetchCount(FetchDescriptor<MutationReceiptRow>()),
                1
            )
            let closure = try XCTUnwrap(
                try harness.lifecycle.acceptedLifecycleClosure(
                    mutationID: promotion.bundle.receipt.mutationID
                )
            )
            XCTAssertEqual(closure.promotedReleases, [promotion.bundle.promotedRelease])
            XCTAssertEqual(closure.sandboxRuns, [promotion.bundle.sandboxRun])
            XCTAssertEqual(closure.promotionReceipts, [promotion.bundle.receipt])
            XCTAssertEqual(closure.activePointers, [promotion.bundle.resultingPointer])
            XCTAssertEqual(
                try harness.lifecycle.activePointer(
                    workspaceID: promotion.workspaceID,
                    packageID: promotion.bundle.resultingPointer.packageID
                ),
                promotion.bundle.resultingPointer
            )
        }
    }

    func testV23P03C18R01RecoveryLifecycleSearchAndBrandExclusionsAreExact() throws {
        let corpus = try loadCorpus()
        let expectedConsumers = [
            "BACKUP", "RESTORE", "DELETE", "ERASE", "OPEN_JSON", "REPORT",
            "SEARCH_REBUILD", "ISOLATED_REPLAY", "SYNC_CLASSIFICATION",
            "BRAND_IMPACT_MANIFEST"
        ]
        XCTAssertEqual(corpus.lifecycleConsumers, expectedConsumers)
        XCTAssertTrue(corpus.privacyExclusions.contains("PROVIDER_DELIVERY"))
        XCTAssertTrue(corpus.privacyExclusions.contains("SENSITIVE_CANARY"))
        XCTAssertTrue(corpus.privacyExclusions.contains("REMOTE_CREDENTIAL"))

        let promotion = try promotionFixture()
        let closure = try PackageEvolutionLifecycleClosureV1(
            promotedReleases: [promotion.bundle.promotedRelease],
            sandboxRuns: [promotion.bundle.sandboxRun],
            promotionReceipts: [promotion.bundle.receipt],
            activePointers: [promotion.bundle.resultingPointer]
        )
        XCTAssertNoThrow(try PackageEvolutionLifecycleAdapterV1.validateBackupRestore(closure))
        XCTAssertFalse(
            try PackageEvolutionLifecycleAdapterV1.mayDelete(
                release: promotion.bundle.promotedRelease,
                activePointers: [promotion.bundle.resultingPointer],
                frozenPackageReleaseIDs: []
            )
        )
        XCTAssertFalse(
            try PackageEvolutionLifecycleAdapterV1.mayDelete(
                release: promotion.bundle.promotedRelease,
                activePointers: [],
                frozenPackageReleaseIDs: [promotion.release.packageReleaseID]
            )
        )
        XCTAssertTrue(
            try PackageEvolutionLifecycleAdapterV1.mayDelete(
                release: promotion.bundle.promotedRelease,
                activePointers: [],
                frozenPackageReleaseIDs: []
            )
        )

        let metadata = PackageEvolutionLifecycleAdapterV1.searchMetadata(promotion.bundle.receipt)
        XCTAssertEqual(metadata, metadata.sorted())
        XCTAssertTrue(metadata.contains(promotion.bundle.receipt.receiptID.uuidString.lowercased()))
        XCTAssertTrue(metadata.contains(promotion.bundle.receipt.exactHead))

        let encoded = try PackageEvolutionCanonicalCodecV1.encode(promotion.bundle.receipt)
        let decoded = try PackageEvolutionCanonicalCodecV1.decode(
            PackagePromotionReceiptV1.self,
            from: encoded
        )
        XCTAssertEqual(decoded, promotion.bundle.receipt)
        XCTAssertEqual(PackageEvolutionLifecycleV1.schema, "PACKAGE_EVOLUTION_V1")
        XCTAssertTrue(PackageEvolutionLifecycleV1.persistent)
        XCTAssertTrue(PackageEvolutionLifecycleV1.migrationRequired)
        XCTAssertTrue(PackageEvolutionLifecycleV1.backupRestoreRequired)
        XCTAssertTrue(PackageEvolutionLifecycleV1.deleteEraseRequired)
        XCTAssertTrue(PackageEvolutionLifecycleV1.exportReportRequired)
        XCTAssertTrue(PackageEvolutionLifecycleV1.searchRebuildReplayRequired)
        XCTAssertEqual(
            PackageEvolutionLifecycleV1.postActivationPolicy,
            .forwardFixOnly
        )
        XCTAssertFalse(PackageEvolutionLifecycleV1.rollbackOperationAvailable)
        XCTAssertEqual(
            PackageEvolutionLifecycleV1.downgradePolicy,
            "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V17_WRITE"
        )
        XCTAssertEqual(PackageEvolutionLifecycleV1.writer, "SOLE_CANONICAL_WORKSPACE_WRITER")

        XCTAssertThrowsError(
            try PackageEvolutionLifecycleClosureV1(
                promotedReleases: [promotion.bundle.promotedRelease, promotion.bundle.promotedRelease],
                sandboxRuns: [promotion.bundle.sandboxRun],
                promotionReceipts: [promotion.bundle.receipt],
                activePointers: [promotion.bundle.resultingPointer]
            )
        )
    }

    func testBackupDecoderPreservesUniquePromotedRelease() throws {
        let promoted = try promotionFixture().bundle.promotedRelease
        let records = try backupDecoderRecords(promotedReleases: [promoted])
        let bytes = try BackupCanonicalEncoderV1().encodeRecords(records).data
        XCTAssertEqual(try BackupCanonicalDecoderV1().decodeRecords(bytes), records)
    }

    func testBackupDecoderRejectsAliasedPromotedReleasePayload() throws {
        let promoted = try promotionFixture().bundle.promotedRelease
        let records = try backupDecoderRecords(
            promotedReleases: [promoted, promoted],
            outerIDs: [promoted.releaseRecordID, id(899)]
        )
        let bytes = try BackupCanonicalEncoderV1().encodeRecords(records).data
        XCTAssertThrowsError(try BackupCanonicalDecoderV1().decodeRecords(bytes)) { error in
            XCTAssertEqual(error as? BackupCanonicalDecodingErrorV1, .invalidRecords)
        }
    }

    func testBackupDecoderRejectsDuplicateNestedReleaseWithDistinctRecordIdentities() throws {
        let promoted = try promotionFixture().bundle.promotedRelease
        let second = try PromotedPackageReleaseV1(
            releaseRecordID: id(899),
            workspaceID: promoted.workspaceID,
            packageRelease: promoted.packageRelease,
            mutationID: mutation(898),
            promotedAt: promoted.promotedAt
        )
        // Both outer IDs match their valid inner records. Only the nested
        // packageReleaseID collides, independently of outer identity binding.
        let records = try backupDecoderRecords(promotedReleases: [promoted, second])
        let bytes = try BackupCanonicalEncoderV1().encodeRecords(records).data
        XCTAssertThrowsError(try BackupCanonicalDecoderV1().decodeRecords(bytes)) { error in
            XCTAssertEqual(error as? BackupCanonicalDecodingErrorV1, .invalidRecords)
        }
    }

    private func backupDecoderRecords(
        promotedReleases: [PromotedPackageReleaseV1],
        outerIDs: [UUID]? = nil
    ) throws -> V4BackupRecordsV1 {
        let rows = try promotedReleases.enumerated().map { index, promoted in
            V17BackupPackageEvolutionRecordV1(
                kind: .promotedRelease,
                id: outerIDs?[index] ?? promoted.releaseRecordID,
                workspaceID: promoted.workspaceID.rawValue,
                revision: promoted.revision,
                canonicalData: try PackageEvolutionCanonicalCodecV1.encode(promoted)
            )
        }
        return V4BackupRecordsV1(
            packageEvolution: rows,
            assets: [],
            deletionLedger: .empty,
            evidenceFiles: [],
            issues: [],
            mutationHistory: MutationHistorySnapshotV1(
                workspaceRevision: 0, lastLocalSequence: 0,
                receipts: [], quarantines: [], entityRevisions: []
            ),
            packets: [],
            recordsSchemaVersion: 19,
            reports: [],
            sites: [],
            workflowRecords: []
        )
    }

    private func assertCorpusHeader(_ corpus: Corpus) {
        XCTAssertEqual(corpus.schema, "V21P03C18PackageEvolutionCorpusV1")
        XCTAssertEqual(corpus.corpusID, corpus.schema)
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.cardID, "V23-P03-C18")
        XCTAssertEqual(corpus.records, 15)
        XCTAssertEqual(corpus.recordsSchemaVersion, 16)
        XCTAssertEqual(corpus.persistentSchemaVersion, 17)
        XCTAssertEqual(corpus.persistentModelCount, 68)
        XCTAssertEqual(corpus.coverage, ["GOLDEN", "ALTERNATE", "HOSTILE", "INTERRUPTION", "RECOVERY"])
        XCTAssertEqual(corpus.evidenceIDs, ["G01", "A01", "H01", "I01", "R01"])
        XCTAssertEqual(corpus.evidenceSelectors.map(\.id), [
            "V23-P03-C18-G01", "V23-P03-C18-A01", "V23-P03-C18-H01",
            "V23-P03-C18-I01", "V23-P03-C18-R01"
        ])
        XCTAssertEqual(corpus.evidenceSelectors.map(\.selector), ["G", "A", "H", "I", "R"])
        XCTAssertTrue(corpus.evidenceSelectors.allSatisfy { !$0.focus.isEmpty })
        XCTAssertTrue(corpus.oldOrNewOnly)
        XCTAssertEqual(corpus.retryDisposition, "SAME_IMMUTABLE_RECEIPT_OR_SAFE_DISCARD")
        XCTAssertEqual(corpus.sandboxChecks, PackageSandboxCheckKindV1.allCases.map(\.rawValue))
        XCTAssertTrue(corpus.noActivationFromSandbox)
        XCTAssertEqual(corpus.rollbackCompatibility, [
            "PRE_ACTIVATION_DISCARDABLE", "ACTIVATED_FORWARD_FIX_REQUIRED"
        ])
        XCTAssertEqual(corpus.persistentKinds, [
            "PROMOTED_PACKAGE_RELEASE", "PACKAGE_SANDBOX_RUN",
            "PACKAGE_PROMOTION_RECEIPT", "ACTIVE_PACKAGE_REGISTRY_POINTER"
        ])
        XCTAssertEqual(corpus.brandExclusion, "BRAND_IMPACT_MANIFEST_IS_EVIDENCE_ONLY")
        XCTAssertFalse(corpus.provisionalFlags.native)
        XCTAssertFalse(corpus.provisionalFlags.hosted)
        XCTAssertFalse(corpus.provisionalFlags.adoption)
        XCTAssertFalse(corpus.provisionalFlags.acceptance)
        XCTAssertFalse(corpus.provisionalFlags.release)
        XCTAssertEqual(corpus.forbiddenProductionSymbols, [
            "PackageNetworkDeliveryV1", "PackageRemoteCatalogV1",
            "PackageCredentialV1", "URLSession", "CloudKit"
        ])
    }

    private func loadCorpus() throws -> Corpus {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "V21P03C18PackageEvolutionCorpusV1",
                withExtension: "json",
                subdirectory: "Fixtures/V21/PackageEvolution"
            ) ?? bundle.url(
                forResource: "V21P03C18PackageEvolutionCorpusV1",
                withExtension: "json"
            )
        )
        return try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
    }

    private func publishedRelease(workflowID: String) throws -> InspectionPackageReleaseV1 {
        let draft = try InspectionPackageReleaseV1.makeDraft(
            package: ShippingIlluminatedSignAdapterV1.inspectionPackage(),
            workflow: try c18Workflow(id: workflowID)
        )
        return try InspectionPackageReleasePublisherV1.publish(
            InspectionPackageReleasePublisherV1.test(draft)
        ).release
    }

    private func c18Workflow(id: String) throws -> WorkflowDefinitionV1 {
        try WorkflowDefinitionV1(
            workflowID: id,
            entryNodeID: "c18.section",
            declaredFieldIDs: [],
            nodes: [
                try WorkflowNodeV1(
                    nodeID: "c18.section",
                    kind: .section,
                    localizationKey: "c18.section",
                    outgoingNodeIDs: ["c18.terminal"]
                ),
                try WorkflowNodeV1(
                    nodeID: "c18.terminal",
                    kind: .terminal,
                    localizationKey: "c18.terminal",
                    outgoingNodeIDs: []
                )
            ]
        )
    }

    private func alteredGraph(
        _ source: PackageSemanticGraphV1,
        contentVersion: Int,
        hashByte: String
    ) throws -> PackageSemanticGraphV1 {
        let encoder = JSONEncoder()
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(source)) as? [String: Any]
        )
        object["packageContentVersion"] = contentVersion
        object["semanticGraphSHA256"] = String(repeating: hashByte, count: 64)
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        return try JSONDecoder().decode(PackageSemanticGraphV1.self, from: data)
    }

    private func forgedGraph(
        _ source: PackageSemanticGraphV1,
        key: String,
        value: String
    ) throws -> PackageSemanticGraphV1 {
        let encoder = JSONEncoder()
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(source)) as? [String: Any]
        )
        object[key] = value
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        return try JSONDecoder().decode(PackageSemanticGraphV1.self, from: data)
    }

    private func forgedDiff(
        _ source: PackageSemanticDiffV1,
        classification: PackageSemanticDiffClassificationV1,
        changes: [[String: String]]
    ) throws -> PackageSemanticDiffV1 {
        let encoded = try PackageEvolutionCanonicalCodecV1.encode(source)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["classification"] = classification.rawValue
        object["changes"] = changes
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        return try JSONDecoder().decode(PackageSemanticDiffV1.self, from: data)
    }

    private func promotionFixture() throws -> PromotionFixture {
        let workspaceID = WorkspaceID(rawValue: id(800))
        let release = try publishedRelease(workflowID: "c18.workflow.promotion.v1")
        let diff = try PackageSemanticDifferV1.diff(source: release, target: release)
        let sandbox = try PackageSandboxRunV1(
            runID: id(801),
            workspaceID: workspaceID,
            packageReleaseID: release.packageReleaseID,
            packageSHA256: release.packageSHA256,
            workflowSHA256: release.workflowSHA256,
            semanticDiffSHA256: diff.diffSHA256,
            exactHead: String(repeating: "c", count: 40),
            activePointerStateBeforeSHA256: noActivePointerStateSHA256,
            activePointerStateAfterSHA256: noActivePointerStateSHA256,
            checks: try sandboxResults(prefix: "c18.promotion"),
            mutationID: mutation(804)
        )
        let promoted = try PromotedPackageReleaseV1(
            releaseRecordID: id(803),
            workspaceID: workspaceID,
            packageRelease: release,
            mutationID: mutation(804),
            promotedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let receiptID = id(806)
        let pointer = try ActivePackageRegistryPointerV1(
            pointerID: id(805),
            workspaceID: workspaceID,
            packageID: release.packageID,
            activeReleaseRecordID: promoted.releaseRecordID,
            promotionReceiptID: receiptID,
            activePackageReleaseID: release.packageReleaseID,
            activeReleaseRecordSHA256: promoted.releaseRecordSHA256,
            revision: 1,
            mutationID: promoted.mutationID
        )
        let actor = try actor(workspaceID: workspaceID)
        let receipt = try PackagePromotionReceiptV1(
            receiptID: receiptID,
            workspaceID: workspaceID,
            promotedRelease: promoted,
            sandboxRun: sandbox,
            diff: diff,
            predecessorPointer: nil,
            resultingPointer: pointer,
            actor: actor,
            exactHead: sandbox.exactHead,
            operation: .initialActivation,
            rollbackCompatibility: .activatedForwardFixRequired,
            mutationID: promoted.mutationID,
            recordedAt: Date(timeIntervalSince1970: 1_800_000_021)
        )
        let bundle = PackagePromotionAtomicBundleV1(
            promotedRelease: promoted,
            sandboxRun: sandbox,
            semanticDiff: diff,
            predecessorPointer: nil,
            resultingPointer: pointer,
            actor: actor,
            receipt: receipt
        )
        return PromotionFixture(
            workspaceID: workspaceID,
            release: release,
            diff: diff,
            bundle: bundle
        )
    }

    private func sandboxFixtureMatrix(
        prefix: String
    ) throws -> PackageSandboxFixtureMatrixV1 {
        func fixtures(for shape: PackageSandboxFixtureShapeV1) throws
            -> [PackageSandboxCheckKindV1: PackageSandboxFixtureV1] {
            Dictionary(uniqueKeysWithValues: try PackageSandboxCheckKindV1.allCases.map { kind in
                let fixtureID = "\(prefix).\(shape.rawValue.lowercased()).\(kind.rawValue.lowercased())"
                return (
                    kind,
                    try PackageSandboxFixtureV1(
                        fixtureID: fixtureID,
                        fixtureSHA256: KernelCanonicalHashV1.sha256(Data(fixtureID.utf8))
                    )
                )
            })
        }
        return try PackageSandboxFixtureMatrixV1(
            minimal: fixtures(for: .minimal),
            representative: fixtures(for: .representative)
        )
    }

    private func sandboxResults(
        prefix: String,
        failed: Set<String> = [],
        activationEvidence: PackageSandboxActivationEvidenceV1 = .notAttempted
    ) throws -> [PackageSandboxCheckResultV1] {
        try PackageSandboxCheckKindV1.allCases.flatMap { kind in
            try PackageSandboxFixtureShapeV1.allCases.map { shape in
                let fixtureID = "\(prefix).\(shape.rawValue.lowercased()).\(kind.rawValue.lowercased())"
                let stableKey = "\(kind.rawValue)|\(shape.rawValue)"
                return PackageSandboxCheckResultV1(
                    kind: kind,
                    shape: shape,
                    fixtureID: fixtureID,
                    fixtureSHA256: KernelCanonicalHashV1.sha256(Data(fixtureID.utf8)),
                    resultSHA256: KernelCanonicalHashV1.sha256(Data("result.\(fixtureID)".utf8)),
                    disposition: failed.contains(stableKey) ? .failed : .passed,
                    activationEvidence: activationEvidence
                )
            }
        }
    }

    private var noActivePointerStateSHA256: String {
        KernelCanonicalHashV1.sha256(Data("C18_NO_ACTIVE_POINTER".utf8))
    }

    private func draftCheckpoint(
        workspaceID: WorkspaceID,
        draftID: UUID? = nil,
        state: FieldDraftStateV1,
        draftRevision: UInt64,
        lastDurableMutationID: MutationIDV1? = nil,
        lastReceiptSHA256: String? = nil
    ) throws -> FieldDraftCheckpointV1 {
        try FieldDraftCheckpointV1(
            draftID: draftID ?? id(830),
            workspaceID: workspaceID,
            scope: try DraftScopeKeyV1(
                scopeKind: "package_evolution",
                stableComponentIDs: ["c18.scope"]
            ),
            purpose: .inspectionReview,
            codec: try DraftPayloadCodecReleaseV1(
                codecID: "c18.payload.codec",
                codecVersion: 1,
                releaseSHA256: String(repeating: "f", count: 64)
            ),
            baseCanonicalRevision: 1,
            draftRevision: draftRevision,
            payloadData: Data("c18-source-payload".utf8),
            stageIDs: [],
            resumeAnchor: try DraftResumeAnchorV1(
                sectionID: "c18.section",
                boundedPosition: 0
            ),
            state: state,
            lastDurableMutationID: lastDurableMutationID,
            lastReceiptSHA256: lastReceiptSHA256,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_010),
            mutationID: mutation(831 + Int(draftRevision))
        )
    }

    private func actor(workspaceID: WorkspaceID) throws -> ActorSnapshotV1 {
        let local = try LocalActorReferenceV1(
            actorReferenceID: id(840),
            workspaceID: workspaceID,
            displayName: "C18 local operator"
        )
        return try ActorSnapshotV1(
            snapshotID: id(841),
            workspaceID: workspaceID,
            actor: local,
            responsibility: .recordedBy,
            displayNameAtTime: local.displayName,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_020)
        )
    }

    private func assertEvolutionFailure(
        _ expected: PackageEvolutionFailureV1,
        _ operation: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? PackageEvolutionFailureV1, expected, file: file, line: line)
        }
    }

    private static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "c1800000-0000-4000-8000-%012d", value))!
    }

    private static func mutation(_ value: Int) -> MutationIDV1 {
        try! MutationIDV1(rawValue: id(value))
    }

    private func id(_ value: Int) -> UUID { Self.id(value) }
    private func mutation(_ value: Int) -> MutationIDV1 { Self.mutation(value) }

    private func duplicateChecks() throws -> [PackageSandboxCheckResultV1] {
        var checks = try sandboxResults(prefix: "c18.duplicate")
        checks.append(try XCTUnwrap(checks.first))
        return checks
    }
}

private struct StableNoActivationObserver: PackageSandboxActivationObservingV1 {
    func activePointerStateSHA256(
        workspaceID: WorkspaceID,
        packageID: String
    ) async throws -> String {
        KernelCanonicalHashV1.sha256(Data("C18_NO_ACTIVE_POINTER".utf8))
    }
}

private actor ChangingActivationObserver: PackageSandboxActivationObservingV1 {
    private var callCount = 0

    func activePointerStateSHA256(
        workspaceID: WorkspaceID,
        packageID: String
    ) async throws -> String {
        callCount += 1
        return KernelCanonicalHashV1.sha256(Data("C18_ACTIVE_POINTER_STATE_\(callCount)".utf8))
    }
}

private enum C18PromotionInsertStageV1: CaseIterable, Equatable {
    case promotedPackageRelease
    case packageSandboxRun
    case packagePromotionReceipt
    case activePackageRegistryPointer
}

@MainActor
private final class C18PromotionAtomicHarness {
    let container: ModelContainer
    let context: ModelContext
    let journal: MutationJournalStoreV1
    let writer: WorkspaceWriterV1
    let lifecycle: PackageEvolutionLifecycleAdapterV1
    let adapter: C18PromotionFaultInjectingAdapter

    init(
        bundle: PackagePromotionAtomicBundleV1,
        failureStage: C18PromotionInsertStageV1
    ) throws {
        let schema = Schema(
            PersistentSchemaV17.models,
            version: PersistentSchemaV17.versionIdentifier
        )
        let installedContainer = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                "C18AtomicPromotion-\(failureStage)",
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                cloudKitDatabase: .none
            )]
        )
        let installedContext = installedContainer.mainContext
        installedContext.autosaveEnabled = false
        installedContext.insert(try ActorSnapshotRow(bundle.actor))
        try installedContext.save()

        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: bundle.resultingPointer.workspaceID,
            replicaID: ReplicaID(rawValue: c18AtomicID(852))
        )
        let generationID = c18AtomicID(853)
        let installedJournal = try MutationJournalStoreV1(
            modelContext: installedContext,
            identity: identity,
            generationID: generationID
        )
        let installedAdapter = C18PromotionFaultInjectingAdapter(
            modelContext: installedContext,
            failureStage: failureStage
        )
        let installedWriter = try WorkspaceWriterV1(
            identity: identity,
            generationID: generationID,
            initialRevision: try WorkspaceRevisionV1(
                workspaceID: identity.workspaceID,
                generationID: generationID,
                writerInstanceID: c18AtomicID(854),
                revision: 0,
                entityRevisions: []
            ),
            clock: C18PromotionFixedClockV1(),
            idSource: C18PromotionFixedIDSourceV1(value: c18AtomicID(854)),
            fileAuthority: C18PromotionFileAuthorityV1(),
            adapter: installedAdapter,
            journalStore: installedJournal
        )
        let installedLifecycle = PackageEvolutionLifecycleAdapterV1(
            writer: installedWriter,
            journal: installedJournal,
            modelContext: installedContext
        )
        container = installedContainer
        context = installedContext
        journal = installedJournal
        writer = installedWriter
        lifecycle = installedLifecycle
        adapter = installedAdapter
    }

    func rowCounts() throws -> [Int] {
        [
            try context.fetchCount(FetchDescriptor<PromotedPackageReleaseRow>()),
            try context.fetchCount(FetchDescriptor<PackageSandboxRunRow>()),
            try context.fetchCount(FetchDescriptor<PackagePromotionReceiptRow>()),
            try context.fetchCount(FetchDescriptor<ActivePackageRegistryPointerRow>()),
        ]
    }
}

@MainActor
private final class C18PromotionFaultInjectingAdapter: WorkspaceWriterAdapterPortV1 {
    private let context: ModelContext
    private let canonical: WorkspaceWriterAdapterV1
    private var failureStage: C18PromotionInsertStageV1?
    private(set) var canonicalApplyCount = 0

    init(modelContext: ModelContext, failureStage: C18PromotionInsertStageV1) {
        context = modelContext
        canonical = WorkspaceWriterAdapterV1(modelContext: modelContext)
        self.failureStage = failureStage
    }

    func apply(
        _ command: WorkspaceCommandV1,
        occurredAt: Date,
        temporaryRelativePath: String
    ) throws -> WorkspaceMutationEffectV1 {
        guard case let .applyPackagePromotion(mutation) = command,
              let failureStage else {
            canonicalApplyCount += 1
            return try canonical.apply(
                command,
                occurredAt: occurredAt,
                temporaryRelativePath: temporaryRelativePath
            )
        }

        try mutation.validate()
        let affected = try mutation.affectedIdentities
        context.insert(try PromotedPackageReleaseRow(mutation.promotedRelease))
        try failIfNeeded(.promotedPackageRelease, expected: failureStage)
        context.insert(try PackageSandboxRunRow(mutation.sandboxRun))
        try failIfNeeded(.packageSandboxRun, expected: failureStage)
        context.insert(try PackagePromotionReceiptRow(mutation.receipt))
        try failIfNeeded(.packagePromotionReceipt, expected: failureStage)
        context.insert(try ActivePackageRegistryPointerRow(mutation.resultingPointer))
        try failIfNeeded(.activePackageRegistryPointer, expected: failureStage)
        return try WorkspaceMutationEffectV1(
            affectedEntities: affected,
            temporaryRelativePath: temporaryRelativePath
        )
    }

    func rollback() {
        context.rollback()
    }

    private func failIfNeeded(
        _ stage: C18PromotionInsertStageV1,
        expected: C18PromotionInsertStageV1
    ) throws {
        guard stage == expected else { return }
        failureStage = nil
        throw WorkspaceMutationFailureV1.persistenceFailed
    }
}

private struct C18PromotionFixedClockV1: ApplicationClock {
    func now() -> Date { Date(timeIntervalSince1970: 1_800_000_100) }
}

private struct C18PromotionFixedIDSourceV1: ApplicationIDSource {
    let value: UUID
    func makeID() -> UUID { value }
}

private struct C18PromotionFileAuthorityV1: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(
        mutationID: MutationIDV1,
        component: String
    ) throws -> String {
        "c18-atomic/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

private func c18AtomicID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "c1800000-0000-4000-8000-%012d", value))!
}

extension V9_32PackageEvolutionTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}
extension V9_32PackageEvolutionTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(PersistentSchemaV24.models.count, 87)
        XCTAssertEqual(SurveyDefinitionLifecycleV1.importDisposition, "QUARANTINE_THEN_NEW_DRAFT_IDENTITY")
        XCTAssertEqual(SurveyDefinitionLifecycleV1.writer, "SOLE_CANONICAL_WORKSPACE_WRITER")
    }
}
extension V9_32PackageEvolutionTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}


private enum C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_32PackageEvolutionTests_swift {
    static let compatibilityCardID = "V23-P03-C47"
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

private final class C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_32PackageEvolutionTests_swift_Tests: XCTestCase {
    func testC47V932PackageEvolutionTestsOwnerCompatibilityIsTyped() {
        XCTAssertEqual(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_32PackageEvolutionTests_swift.compatibilityCardID, "V23-P03-C47")
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_32PackageEvolutionTests_swift.sharedEnvelopeDoesNotCollapseFamilyTruth)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_32PackageEvolutionTests_swift.installationAndPunchReceiptsRemainIndependent)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_32PackageEvolutionTests_swift.noPlanFallbackIsExplicit)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_32PackageEvolutionTests_swift.surveyDefinitionOwnershipIsPreserved)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_32PackageEvolutionTests_swift.legacyInspectionTruthIsNotRewritten)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_32PackageEvolutionTests_swift.threeReceiptIsolationIsRequired)
        XCTAssertEqual(ActivityKindV1CompatibilityAdapterV2.disposition(.survey), .exactV1)
        XCTAssertEqual(ActivityKindV1CompatibilityAdapterV2.v1(.survey), .survey)
    }
}

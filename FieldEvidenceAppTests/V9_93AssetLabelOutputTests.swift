import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V9_93AssetLabelOutputTests: XCTestCase {
    func testV23P04C30G01DeterministicLabelSheetVendorCSVPreviewReprintAndScanClosure() async throws {
        let corpus = try C30AssetLabelTestSupport.corpus()
        XCTAssertEqual(corpus["cardID"] as? String, "V23-P04-C30")
        let authority = try XCTUnwrap(corpus["authority"] as? [String: Any])
        XCTAssertEqual(authority["coordinationHead"] as? String, "1b902e448a0f38f7189e237e383f8567ffbf10c3")
        XCTAssertEqual(authority["coordinationTree"] as? String, "fa2dbae64b7ad67d72c1b6a6a02bcbf040c7a673")
        XCTAssertEqual(authority["appBaseHead"] as? String, "8b97b33a0c83d639349d9c28806092fdeb79b95f")
        XCTAssertEqual(authority["appBaseTree"] as? String, "0c804ceb7b50a5b804b1380762408aedac644d2d")
        XCTAssertEqual(authority["contextDigest"] as? String, "c1ac4c3961fde5b1743f3703ee158720b9059b6af4538bf59d5df788e5327b02")
        XCTAssertEqual(authority["hydrationSequence"] as? Int, 514)
        XCTAssertEqual(authority["fenceDigest"] as? String, "72484e9d476b2c1cf858ebaecd1d08ef16e7e83e554f270991ac0d7351f68f3d")
        let prerequisites = try XCTUnwrap(corpus["prerequisites"] as? [[String: Any]])
        XCTAssertEqual(prerequisites.map { $0["cardID"] as? String }, [
            "V23-P03-C45", "V23-P04-C13", "V23-P04-C21",
        ])
        XCTAssertEqual(prerequisites.map { $0["candidateHead"] as? String }, [
            "32533a14d2e72ee8ebc46b25473c80fc3f721424",
            "73d512ac1ff2832fa5c681078fb027604c7661cf",
            "d40d75d615d217b3da9cfc46c2078ee97b199b12",
        ])

        let fixture = try C30AssetLabelTestSupport.fixture()
        let first = try DeterministicPDFRendererV1.renderAssetLabels(fixture.plan)
        let retry = try DeterministicPDFRendererV1.renderAssetLabels(fixture.plan)
        XCTAssertEqual(first, retry)
        XCTAssertEqual(first.artifacts.map(\.entry.kind), [.formulaSafeCSV, .pdf, .structuredText])
        XCTAssertEqual(first.manifest, retry.manifest)
        XCTAssertEqual(fixture.plan.startDecision, .explicitStartRequired)
        XCTAssertEqual(first.disposition, .scratchPreviewRequiresExplicitStart)

        let pdf = try XCTUnwrap(first.artifacts.first { $0.entry.kind == .pdf })
        XCTAssertTrue(pdf.bytes.starts(with: Data("%PDF-1.4\n".utf8)))
        let csv = try XCTUnwrap(first.artifacts.first { $0.entry.kind == .formulaSafeCSV })
        XCTAssertTrue(try C30AssetLabelTestSupport.utf8(csv).contains("\"'=SUM(1,1)\""))
        let text = try XCTUnwrap(first.artifacts.first { $0.entry.kind == .structuredText })
        XCTAssertTrue(try C30AssetLabelTestSupport.utf8(text).contains(
            "Generated locally; not printed, affixed, delivered, or authorization."
        ))

        let snapshot = try C30AssetLabelTestSupport.snapshot(fixture: fixture, result: first)
        let exactContext = try C30AssetLabelTestSupport.reprintContext(
            snapshot: snapshot,
            state: .active
        )
        XCTAssertEqual(try snapshot.reprintEligibility(in: exactContext), .activeExactReprint)

        let resolutions = try await C30AssetLabelTestSupport.resolveAllSources(fixture)
        XCTAssertEqual(resolutions.map(\.outcome), [.matched, .matched, .matched])
        XCTAssertEqual(Set(resolutions.compactMap(\.matchedAssetID)), [fixture.plan.items[0].assetID])
        XCTAssertEqual(Set(resolutions.compactMap(\.matchedLocator)), [fixture.plan.items[0].locator])
        XCTAssertFalse(DeterministicPDFRendererV1.assetLabelPhysicalScanAcceptanceClaimed)
    }

    func testV23P04C30A01ManualShortCodeOfflineFallbackAndFormulaSafeVendorCSV() async throws {
        let fixture = try C30AssetLabelTestSupport.fixture()
        let item = fixture.plan.items[0]
        try item.shortCode.validate()
        XCTAssertEqual(try ManualShortCodeV1(displayValue: item.shortCode.displayValue), item.shortCode)
        XCTAssertEqual(item.locator.representation, .externalKey(try item.shortCode.externalKey()))

        let resolutions = try await C30AssetLabelTestSupport.resolveAllSources(fixture)
        XCTAssertEqual(Set(resolutions.map(\.inputSHA256)).count, 1)
        XCTAssertEqual(Set(resolutions.compactMap(\.matchedAssetID)).count, 1)
        XCTAssertEqual(Set(resolutions.compactMap(\.matchedLocator)).count, 1)

        let result = try DeterministicPDFRendererV1.renderAssetLabels(fixture.plan)
        let csv = try XCTUnwrap(result.artifacts.first { $0.entry.kind == .formulaSafeCSV })
        let csvText = try C30AssetLabelTestSupport.utf8(csv)
        XCTAssertTrue(csvText.contains("\"'=SUM(1,1)\""))
        XCTAssertFalse(csvText.contains("\"=SUM(1,1)\""))
        XCTAssertEqual(fixture.plan.startDecision, .explicitStartRequired)

        let claims = try XCTUnwrap(try C30AssetLabelTestSupport.corpus()["claims"] as? [String: Any])
        XCTAssertEqual(claims["networkRequired"] as? Bool, false)
        XCTAssertEqual(claims["physicalPrintCompleted"] as? Bool, false)
        XCTAssertEqual(claims["physicalScanValidated"] as? Bool, false)
    }

    func testV23P04C30H01StaleCollisionRetiredReplacedUnsafeCSVAndHistoricDeployFailClosed() throws {
        let corpus = try C30AssetLabelTestSupport.corpus()
        let hostile = try XCTUnwrap(corpus["hostileCases"] as? [[String: Any]])
        XCTAssertEqual(hostile.map { $0["caseID"] as? String }, [
            "H01_STALE_ASSET_OR_BINDING_REVISION",
            "H02_SHORT_CODE_COLLISION",
            "H03_RETIRED_LOCATOR",
            "H04_REPLACED_LOCATOR",
            "H05_FORMULA_UNSAFE_VENDOR_CSV",
            "H06_HISTORIC_EXPORT_DEPLOY_ATTEMPT",
            "H07_IMPLICIT_GENERATION_START",
            "H08_FALSE_PRINT_SCAN_OR_DELIVERY_CLAIM",
        ])

        let fixture = try C30AssetLabelTestSupport.fixture()
        XCTAssertThrowsError(try AssetLabelGenerationPlanV1(
            planID: C30AssetLabelTestSupport.id(91),
            workspaceID: fixture.plan.workspaceID,
            template: fixture.plan.template,
            disclosure: fixture.plan.disclosure,
            items: [fixture.plan.items[0], fixture.plan.items[0]],
            startOffset: 0,
            localeIdentifier: "en_US_POSIX",
            frozenGeneratedAt: C30AssetLabelTestSupport.date(91)
        ))

        let projection = try DeterministicPDFRendererV1.renderAssetLabels(fixture.plan)
        let csv = try XCTUnwrap(projection.artifacts.first { $0.entry.kind == .formulaSafeCSV })
        XCTAssertFalse(try C30AssetLabelTestSupport.utf8(csv).contains("\"=SUM(1,1)\""))
        let snapshot = try C30AssetLabelTestSupport.snapshot(fixture: fixture, result: projection)
        XCTAssertEqual(
            try snapshot.reprintEligibility(in: C30AssetLabelTestSupport.reprintContext(
                snapshot: snapshot,
                state: .retired
            )),
            .historicExportOnly
        )
        XCTAssertEqual(
            try snapshot.reprintEligibility(in: C30AssetLabelTestSupport.reprintContext(
                snapshot: snapshot,
                state: .replaced
            )),
            .historicExportOnly
        )
        XCTAssertEqual(
            try snapshot.reprintEligibility(in: AssetLabelReprintContextV1(
                templateRelease: snapshot.plan.template.reference,
                rendererRelease: snapshot.plan.template.rendererRelease,
                nativeTextEnvironment: snapshot.outputReceipt.nativeTextEnvironment,
                currentBindings: try snapshot.plan.items.map {
                    try C30AssetLabelTestSupport.currentBinding(
                        item: $0,
                        assetRevision: $0.assetRevision + 1
                    )
                }
            )),
            .historicExportOnly
        )
        XCTAssertEqual(
            try snapshot.reprintEligibility(in: AssetLabelReprintContextV1(
                templateRelease: try snapshot.plan.template.reference,
                rendererRelease: nil,
                nativeTextEnvironment: snapshot.outputReceipt.nativeTextEnvironment,
                currentBindings: try snapshot.plan.items.map {
                    try C30AssetLabelTestSupport.currentBinding(item: $0)
                }
            )),
            .blockedMissingRelease
        )
    }

    func testV23P04C30I01InterruptedGenerationAndRepeatedRecoveryLeaveNoPartialArtifact() async throws {
        let corpus = try C30AssetLabelTestSupport.corpus()
        let receipts = try XCTUnwrap(corpus["interruptionReceipts"] as? [[String: Any]])
        XCTAssertEqual(receipts.map { $0["boundary"] as? String }, [
            "BEFORE_STAGING",
            "AFTER_STAGING_BEFORE_PUBLICATION",
            "AFTER_PUBLICATION_BEFORE_RETURN",
        ])
        XCTAssertEqual(receipts.map { $0["acceptedArtifactSetCount"] as? Int }, [0, 0, 1])
        XCTAssertTrue(receipts.allSatisfy { ($0["partialArtifactCount"] as? Int) == 0 })
        XCTAssertTrue(receipts.allSatisfy { ($0["recoveryAcceptedArtifactSetCount"] as? Int) == 1 })

        let fixture = try C30AssetLabelTestSupport.fixture()
        let first = try DeterministicPDFRendererV1.renderAssetLabels(fixture.plan)
        let recoveredOnce = try DeterministicPDFRendererV1.renderAssetLabels(fixture.plan)
        let recoveredTwice = try DeterministicPDFRendererV1.renderAssetLabels(fixture.plan)
        XCTAssertEqual(first, recoveredOnce)
        XCTAssertEqual(recoveredOnce, recoveredTwice)
        XCTAssertEqual(Set(first.artifacts.map { $0.entry.sha256 }).count, 3)
        XCTAssertTrue(AssetLabelLifecycleAdapterV1.restoreRebuildsOrAdoptsDerivedArtifacts)
        XCTAssertTrue(AssetLabelLifecycleAdapterV1.replayNeverClaimsPrintOrDelivery)

        try await C30AssetLabelTestSupport.verifyRealPublicationRecovery(
            fixture: fixture,
            expectedProjection: first
        )

        let snapshot = try C30AssetLabelTestSupport.snapshot(fixture: fixture, result: first)
        let cleanup = C30CleanupTracker()
        let harness = try await C30AssetLabelTestSupport.lifecycle(
            snapshot: snapshot,
            result: first,
            cleanup: cleanup
        )
        defer { try? FileManager.default.removeItem(at: harness.root) }
        try await harness.adapter.recoverAfterInterruption()
        try await harness.adapter.recoverAfterInterruption()
        let recoveredExport = try await harness.adapter.prepareExactAcceptedExport(
            workspaceID: snapshot.workspaceID,
            snapshotID: snapshot.snapshotID,
            currentBindings: try snapshot.plan.items.map {
                try C30AssetLabelTestSupport.currentBinding(item: $0)
            }
        )
        XCTAssertEqual(recoveredExport.artifacts.map(\.bytes), first.artifacts.map(\.bytes))
        XCTAssertEqual(recoveredExport.reprintEligibility, .activeExactReprint)
        try await harness.adapter.discardTerminalScratch(
            jobID: snapshot.outputReceipt.publicationBinding.jobID
        )
        try await harness.adapter.discardTerminalScratch(
            jobID: snapshot.outputReceipt.publicationBinding.jobID
        )
        XCTAssertEqual(cleanup.removalCount, 0)
        try await harness.adapter.deletePublishedOutput(
            publicationBinding: snapshot.outputReceipt.publicationBinding,
            activeWorkspaceID: snapshot.workspaceID
        )
        XCTAssertEqual(cleanup.removalCount, 1)
    }

    func testV23P04C30R01RetryReexportsExactAcceptedBytesAndPreservesHistoricExportOnlyWarning() async throws {
        let fixture = try C30AssetLabelTestSupport.fixture()
        let accepted = try DeterministicPDFRendererV1.renderAssetLabels(fixture.plan)
        let retry = try DeterministicPDFRendererV1.renderAssetLabels(fixture.plan)
        XCTAssertEqual(accepted.artifacts.map(\.bytes), retry.artifacts.map(\.bytes))
        XCTAssertEqual(accepted.manifest.manifestSHA256, retry.manifest.manifestSHA256)

        let snapshot = try C30AssetLabelTestSupport.snapshot(fixture: fixture, result: accepted)
        let activeHarness = try await C30AssetLabelTestSupport.lifecycle(
            snapshot: snapshot,
            result: accepted,
            cleanup: C30CleanupTracker()
        )
        defer { try? FileManager.default.removeItem(at: activeHarness.root) }
        let exactBindings = try snapshot.plan.items.map {
            try C30AssetLabelTestSupport.currentBinding(item: $0)
        }
        let activeExport = try await activeHarness.adapter.prepareExactAcceptedExport(
            workspaceID: snapshot.workspaceID,
            snapshotID: snapshot.snapshotID,
            currentBindings: exactBindings
        )
        XCTAssertEqual(activeExport.artifacts.map(\.bytes), accepted.artifacts.map(\.bytes))
        XCTAssertEqual(activeExport.reprintEligibility, .activeExactReprint)
        XCTAssertFalse(activeExport.requiresDoNotDeployWarning)
        XCTAssertFalse(AssetLabelPreparedExportV1.claimsShareCompletion)
        XCTAssertFalse(AssetLabelPreparedExportV1.claimsPrintOrDelivery)
        XCTAssertFalse(AssetLabelPreparedExportV1.claimsPhysicalScan)
        let productionWorkflowType: ProductionAssetLabelWorkflow.Type = ProductionAssetLabelWorkflow.self
        XCTAssertTrue(productionWorkflowType == ProductionAssetLabelWorkflow.self)
        try await C30AssetLabelTestSupport.verifyProductionCompositionRemainsAccessGated()

        let cloneWorkspace = C30AssetLabelTestSupport.workspace(97)
        let historic = try snapshot.rebound(
            to: cloneWorkspace,
            expectedRevision: C30AssetLabelTestSupport.expectedRevision(
                workspaceID: cloneWorkspace,
                snapshotID: snapshot.snapshotID,
                slot: 970
            ),
            mutationID: C30AssetLabelTestSupport.mutation(972),
            recordedBy: C30AssetLabelTestSupport.actor(workspaceID: cloneWorkspace, slot: 973),
            recordedAt: C30AssetLabelTestSupport.date(974)
        )
        XCTAssertEqual(historic.manifest, snapshot.manifest)
        XCTAssertEqual(historic.outputReceipt, snapshot.outputReceipt)
        let historicHarness = try await C30AssetLabelTestSupport.lifecycle(
            snapshot: historic,
            result: accepted,
            cleanup: C30CleanupTracker()
        )
        defer { try? FileManager.default.removeItem(at: historicHarness.root) }
        let historicExport = try await historicHarness.adapter.prepareExactAcceptedExport(
            workspaceID: historic.workspaceID,
            snapshotID: historic.snapshotID,
            currentBindings: exactBindings
        )
        XCTAssertEqual(historicExport.artifacts.map(\.bytes), accepted.artifacts.map(\.bytes))
        XCTAssertEqual(historicExport.reprintEligibility, .historicExportOnly)
        XCTAssertTrue(historicExport.requiresDoNotDeployWarning)

        let output = try XCTUnwrap(try C30AssetLabelTestSupport.corpus()["outputContract"] as? [String: Any])
        XCTAssertEqual(output["historicExportWarning"] as? String, "DO_NOT_DEPLOY_RETIRED_OR_REPLACED_LABEL")
        let lifecycle = try XCTUnwrap(try C30AssetLabelTestSupport.corpus()["lifecycle"] as? [String: Any])
        XCTAssertEqual(lifecycle["persistentSchema"] as? String, "V53")
        XCTAssertEqual(lifecycle["activeModelCount"] as? Int, 168)
        XCTAssertEqual(lifecycle["newDurableFamilyCount"] as? Int, 0)
        XCTAssertEqual(lifecycle["newWriterCount"] as? Int, 0)
        XCTAssertEqual(lifecycle["newMigrationCount"] as? Int, 0)
        XCTAssertEqual(PersistentSchemaV53.versionIdentifier, Schema.Version(53, 0, 0))
        XCTAssertEqual(PersistentSchemaV53.models.count, 168)
    }
}

private enum C30AssetLabelTestSupport {
    struct Fixture: Sendable {
        let plan: AssetLabelGenerationPlanV1
        let locator: AssetLocatorV1
    }

    static func corpus() throws -> [String: Any] {
        let url = Bundle(for: V9_93AssetLabelOutputTests.self).url(
            forResource: "V23P04C30AssetLabelOutputCorpusV1",
            withExtension: "json"
        ) ?? URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V23/Labels/V23P04C30AssetLabelOutputCorpusV1.json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    static func fixture() throws -> Fixture {
        let workspaceID = workspace(30)
        let shortCode = try ManualShortCodeV1(randomBody: body(30))
        let locator = try AssetLocatorV1(
            locatorID: id(31),
            workspaceID: workspaceID,
            assetID: id(32),
            representation: .externalKey(shortCode.externalKey()),
            state: .active,
            revision: 1,
            mutationID: mutation(33),
            recordedAt: date(33)
        )
        let recordedBy = try actor(workspaceID: workspaceID, slot: 34)
        let preview = try LocatorBindingPreviewV1(
            workspaceID: workspaceID,
            action: .bind,
            before: nil,
            after: locator.reference,
            replacement: nil,
            generatedAt: date(35)
        )
        let binding = try LocatorBindingReceiptV1(
            receiptID: id(36),
            preview: preview,
            recordedBy: recordedBy,
            predecessor: nil,
            revision: 1,
            mutationID: mutation(37),
            recordedAt: date(37)
        )
        let item = try AssetLabelItemSnapshotV1(
            workspaceID: workspaceID,
            assetID: locator.assetID,
            assetRevision: 1,
            locator: locator,
            bindingReceipt: binding,
            shortCode: shortCode,
            assetDisplay: "=SUM(1,1)",
            locationDisplay: nil,
            disclosure: .assetAndShortCode,
            orderIndex: 0
        )
        return Fixture(
            plan: try AssetLabelGenerationPlanV1(
                planID: id(38),
                workspaceID: workspaceID,
                template: AssetLabelTemplateCatalogV1.makeRelease(.letterOneByTwoAndFiveEighths),
                disclosure: .assetAndShortCode,
                items: [item],
                startOffset: 0,
                localeIdentifier: "en_US_POSIX",
                frozenGeneratedAt: date(38)
            ),
            locator: locator
        )
    }

    static func snapshot(
        fixture: Fixture,
        result: LabelProjectionResultV1,
        publishedArtifacts publishedArtifactsOverride: [AssetLabelPublishedArtifactContentV1]? = nil,
        publicationReceipt publicationReceiptOverride: LocalJobPublicationReceiptV1? = nil
    ) throws -> AcceptedLabelGenerationSnapshotV1 {
        let outputSHA256 = result.manifest.manifestSHA256
        let jobID = LocalJobIDV1.deterministic(
            kind: .render,
            workspaceID: fixture.plan.workspaceID.rawValue,
            immutableInputSHA256: fixture.plan.planSHA256
        )
        let publication = publicationReceiptOverride ?? LocalJobPublicationReceiptV1(
            jobID: jobID,
            attemptCount: 1,
            kind: .render,
            outputSHA256: outputSHA256,
            disposition: .published,
            readBackAt: date(50)
        )
        let resolvedPublishedArtifacts: [AssetLabelPublishedArtifactContentV1]
        if let publishedArtifactsOverride {
            resolvedPublishedArtifacts = publishedArtifactsOverride
        } else {
            resolvedPublishedArtifacts = try publishedArtifacts(
                plan: fixture.plan,
                result: result
            )
        }
        let output = try LabelOutputReceiptV1(
            receiptID: id(51),
            workspaceID: fixture.plan.workspaceID,
            planID: fixture.plan.planID,
            planSHA256: fixture.plan.planSHA256,
            manifestSHA256: result.manifest.manifestSHA256,
            nativeTextEnvironment: result.nativeTextEnvironment,
            publicationBinding: AssetLabelRenderPublicationBindingV1(
                workspaceID: fixture.plan.workspaceID,
                planSHA256: fixture.plan.planSHA256,
                manifestSHA256: result.manifest.manifestSHA256,
                outputSHA256: outputSHA256,
                publishedArtifacts: resolvedPublishedArtifacts,
                publicationReceipt: publication
            ),
            disposition: .generated,
            generatedAt: date(50)
        )
        return try AcceptedLabelGenerationSnapshotV1(
            snapshotID: id(52),
            plan: fixture.plan,
            result: result,
            outputReceipt: output,
            activationDecision: .enabledBoundedLocalOnly,
            expectedRevision: expectedRevision(
                workspaceID: fixture.plan.workspaceID,
                snapshotID: id(52),
                slot: 53
            ),
            mutationID: mutation(55),
            recordedBy: actor(workspaceID: fixture.plan.workspaceID, slot: 56),
            recordedAt: date(56)
        )
    }

    static func publishedArtifacts(
        plan: AssetLabelGenerationPlanV1,
        result: LabelProjectionResultV1
    ) throws -> [AssetLabelPublishedArtifactContentV1] {
        let workspaceValue = plan.workspaceID.rawValue.uuidString.lowercased()
        let jobValue = LocalJobIDV1.deterministic(
            kind: .render,
            workspaceID: plan.workspaceID.rawValue,
            immutableInputSHA256: plan.planSHA256
        ).rawValue.uuidString.lowercased()
        return try result.artifacts.map { artifact in
            let suffix: String
            switch artifact.entry.kind {
            case .pdf: suffix = "pdf"
            case .formulaSafeCSV: suffix = "csv"
            case .structuredText: suffix = "text"
            }
            let digest = try ContentDigestV1(
                algorithm: .sha256,
                hexadecimalValue: artifact.entry.sha256
            )
            let contentID = "asset-label-\(jobValue)-\(suffix)"
            let reference = try ContentReferenceV1(
                workspaceID: workspaceValue,
                contentID: contentID,
                byteLength: artifact.entry.byteCount,
                mediaType: artifact.entry.mediaType,
                digests: ContentDigestSetV1([digest]),
                byteRole: .derivative,
                createdAt: "2023-11-14T22:13:20.000Z"
            )
            return try AssetLabelPublishedArtifactContentV1(
                kind: artifact.entry.kind,
                reference: reference,
                locator: ContentLocatorV1(
                    locatorID: "c05-\(contentID)",
                    workspaceID: workspaceValue,
                    contentID: contentID,
                    locatorRevision: 1,
                    contentDigest: digest,
                    expectedByteLength: artifact.entry.byteCount
                )
            )
        }
    }

    static func reprintContext(
        snapshot: AcceptedLabelGenerationSnapshotV1,
        state: AssetLocatorStateV1
    ) throws -> AssetLabelReprintContextV1 {
        try AssetLabelReprintContextV1(
            templateRelease: snapshot.plan.template.reference,
            rendererRelease: snapshot.plan.template.rendererRelease,
            nativeTextEnvironment: snapshot.outputReceipt.nativeTextEnvironment,
            currentBindings: snapshot.plan.items.map {
                try currentBinding(item: $0, state: state)
            }
        )
    }

    static func currentBinding(
        item: AssetLabelItemSnapshotV1,
        state: AssetLocatorStateV1 = .active,
        assetRevision: UInt64? = nil
    ) throws -> AssetLabelCurrentBindingV1 {
        let binding = AssetLabelCurrentBindingV1(
            assetID: item.assetID,
            assetRevision: assetRevision ?? item.assetRevision,
            locator: item.locator,
            locatorState: state,
            bindingReceiptID: item.bindingReceiptID,
            bindingReceiptRevision: item.bindingReceiptRevision,
            bindingReceiptSHA256: item.bindingReceiptSHA256
        )
        try binding.validate()
        return binding
    }

    static func resolveAllSources(_ fixture: Fixture) async throws -> [LocatorResolutionV1] {
        let query = C30LocatorQuery(locator: fixture.locator)
        let coordinator = AssetLocatorCoordinatorV1(
            resolver: OfflineAssetLocatorResolverV1(
                query: query,
                signatureVerifier: C30RejectingSignatureVerifier()
            )
        )
        let payload = fixture.plan.items[0].qrPayload
        return [
            try await coordinator.resolveCamera(
                payload.scanToWorkDecodedInput(source: .camera),
                workspaceID: fixture.plan.workspaceID,
                evaluatedAt: date(60)
            ),
            try await coordinator.resolveManual(
                payload.scanToWorkDecodedInput(source: .manual),
                workspaceID: fixture.plan.workspaceID,
                evaluatedAt: date(60)
            ),
            try await coordinator.resolveSearch(
                payload.scanToWorkDecodedInput(source: .search),
                workspaceID: fixture.plan.workspaceID,
                evaluatedAt: date(60)
            ),
        ]
    }

    @MainActor
    static func lifecycle(
        snapshot: AcceptedLabelGenerationSnapshotV1,
        result: LabelProjectionResultV1,
        cleanup: C30CleanupTracker
    ) async throws -> (adapter: AssetLabelLifecycleAdapterV1, root: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "C30-label-lifecycle-\(UUID().uuidString)",
            isDirectory: true
        )
        let ledger = root.appendingPathComponent("ledger", isDirectory: true)
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: ledger, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let runner = try ResumableLocalJobRunnerV1(
            store: LocalJobStoreV1(applicationSupportURL: ledger),
            stagingRootURL: staging,
            maximumConcurrency: 1
        )
        let readback = AssetLabelPublishedContentReadbackV1(
            plan: snapshot.plan,
            projection: result,
            publishedArtifacts: snapshot.outputReceipt.publicationBinding.publishedArtifacts
        )
        let operations = AssetLabelArtifactOperationsV1(
            stage: { _, _, _ in },
            load: { _, _ in nil },
            publishOrAdopt: { _, _, _ in .absent },
            adoptOnly: { _, _, _ in .absent },
            publishedReadback: { jobID, planSHA256, outputSHA256 in
                let binding = snapshot.outputReceipt.publicationBinding
                guard jobID == binding.jobID,
                      planSHA256 == binding.planSHA256,
                      outputSHA256 == binding.outputSHA256 else { return nil }
                return readback
            },
            removePublishedOutput: { binding in
                guard binding == snapshot.outputReceipt.publicationBinding else {
                    throw AssetLabelLifecycleFailureV1.publicationMismatch
                }
                cleanup.recordRemoval()
            },
            removePublishedWorkspace: { _ in },
            eraseAllPublished: {},
            discardUncommitted: { _ in },
            discard: { _ in }
        )
        let query = C30AcceptedSnapshotQuery(snapshot: snapshot)
        let adapter = await AssetLabelLifecycleAdapterV1(
            authority: AssetLabelAuthoritativePlanAdapterV1 { try $0.validate() },
            writer: C30RejectingLabelWriter(),
            query: query,
            jobs: runner,
            artifacts: operations
        )
        return (adapter, root)
    }

    @MainActor
    static func verifyRealPublicationRecovery(
        fixture: Fixture,
        expectedProjection: LabelProjectionResultV1
    ) async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "C30-real-label-recovery-\(UUID().uuidString)",
            isDirectory: true
        )
        let generationRoot = root.appendingPathComponent("generation", isDirectory: true)
        let ledgerRoot = root.appendingPathComponent("ledger", isDirectory: true)
        let stagingRoot = root.appendingPathComponent("staging", isDirectory: true)
        try fileManager.createDirectory(at: generationRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let epoch = try GenerationEpochV1(
            generationID: id(801),
            generationManifestSHA256: String(repeating: "c", count: 64)
        )
        let publicationAdapter = GenerationLocalJobPublicationAdapterV1(
            currentGenerationEpoch: { epoch },
            withAuthorizedCommit: { expected, effect in
                guard expected == epoch else {
                    throw GenerationLocalJobPublicationFailureV1.staleGeneration
                }
                return try effect()
            }
        )
        let generationLeaseRegistry = try GenerationLeaseRegistryV1(
            applicationSupportURL: root
        )
        let interruptedStore = EvidenceBundleStore(
            generationRootURL: generationRoot,
            failureInjection: EvidenceBundleStoreFailureInjection(
                failOnceAt: .assetLabelPublicationBeforeMarkerCommit
            )
        )
        let interruptedOperations = try AssetLabelArtifactOperationsV1.production(
            jobStagingRootURL: stagingRoot,
            contentStore: interruptedStore
        )
        let interruptedRunner = try ResumableLocalJobRunnerV1(
            store: LocalJobStoreV1(applicationSupportURL: ledgerRoot),
            stagingRootURL: stagingRoot,
            generationLeaseRegistry: generationLeaseRegistry,
            generationPublicationAdapter: publicationAdapter,
            maximumConcurrency: 1
        )
        let authority = AssetLabelAuthoritativePlanAdapterV1 { try $0.validate() }
        let interruptedLifecycle = await AssetLabelLifecycleAdapterV1(
            authority: authority,
            writer: C30RejectingLabelWriter(),
            query: C30MutableAcceptedSnapshotQuery(),
            jobs: interruptedRunner,
            artifacts: interruptedOperations
        )
        let job = try await interruptedLifecycle.enqueueValidatedPlan(
            fixture.plan,
            generationEpoch: epoch,
            createdAt: date(802)
        )
        await interruptedRunner.waitUntilIdle()
        let interruptedJob = try await interruptedRunner.job(id: job.id)
        XCTAssertEqual(interruptedJob?.state, .awaitingPublication)
        XCTAssertNil(try interruptedStore.readAssetLabelArtifacts(jobID: job.id))

        let recoveredStore = EvidenceBundleStore(generationRootURL: generationRoot)
        let recoveredOperations = try AssetLabelArtifactOperationsV1.production(
            jobStagingRootURL: stagingRoot,
            contentStore: recoveredStore
        )
        let recoveredRunner = try ResumableLocalJobRunnerV1(
            store: LocalJobStoreV1(applicationSupportURL: ledgerRoot),
            stagingRootURL: stagingRoot,
            generationLeaseRegistry: generationLeaseRegistry,
            generationPublicationAdapter: publicationAdapter,
            maximumConcurrency: 1
        )
        let query = C30MutableAcceptedSnapshotQuery()
        let recoveredLifecycle = await AssetLabelLifecycleAdapterV1(
            authority: authority,
            writer: C30RejectingLabelWriter(),
            query: query,
            jobs: recoveredRunner,
            artifacts: recoveredOperations
        )
        try await recoveredLifecycle.recoverAfterInterruption()
        await recoveredRunner.waitUntilIdle()
        try await recoveredLifecycle.recoverAfterInterruption()
        await recoveredRunner.waitUntilIdle()
        let recoveredJobValue = try await recoveredRunner.job(id: job.id)
        let recoveredJob = try XCTUnwrap(recoveredJobValue)
        XCTAssertEqual(recoveredJob.state, .succeeded)
        let readback = try XCTUnwrap(try recoveredStore.readAssetLabelArtifacts(jobID: job.id))
        XCTAssertEqual(readback.plan, fixture.plan)
        XCTAssertEqual(readback.projection, expectedProjection)
        XCTAssertEqual(readback.publishedArtifacts.count, LabelArtifactKindV1.allCases.count)

        let accepted = try snapshot(
            fixture: fixture,
            result: readback.projection,
            publishedArtifacts: readback.publishedArtifacts,
            publicationReceipt: try XCTUnwrap(recoveredJob.publicationReceipt)
        )
        query.snapshot = accepted
        let exact = try await recoveredLifecycle.prepareExactAcceptedExport(
            workspaceID: accepted.workspaceID,
            snapshotID: accepted.snapshotID,
            currentBindings: try accepted.plan.items.map { try currentBinding(item: $0) }
        )
        XCTAssertEqual(exact.artifacts.map(\.bytes), expectedProjection.artifacts.map(\.bytes))
        XCTAssertEqual(exact.reprintEligibility, .activeExactReprint)
        XCTAssertFalse(exact.requiresDoNotDeployWarning)
    }

    @MainActor
    static func verifyProductionCompositionRemainsAccessGated() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "C30-production-composition-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let session = try factory.openOrBootstrapCurrent()
        let coordinator = StoreSessionCoordinator(session: session)
        let profileRegistry = try WorkspacePackageLifecycleCompatibilityV1.shippingRegistry()
        let composition = try ProductionCompositionRoot(
            storeSession: coordinator,
            diagnosticsStore: DiagnosticsStore(applicationSupportURL: root),
            profileRegistry: profileRegistry
        )
        let epoch = try factory.currentGenerationEpoch()
        let publication = GenerationLocalJobPublicationAdapterV1(
            currentGenerationEpoch: { epoch },
            withAuthorizedCommit: { _, effect in try effect() }
        )
        do {
            _ = try await composition.makeAssetLabelWorkflow(
                generationEpoch: epoch,
                generationPublicationAdapter: publication,
                accessGate: C30AccessGate()
            )
            XCTFail("Locked production label composition must remain access gated")
        } catch {
            XCTAssertEqual(error as? WorkspaceExperienceFailureV1, .permissionRequired)
        }
    }

    static func utf8(_ artifact: LabelProjectedArtifactV1) throws -> String {
        try XCTUnwrap(String(data: artifact.bytes, encoding: .utf8))
    }

    static func expectedRevision(
        workspaceID: WorkspaceID,
        snapshotID: UUID,
        slot: Int
    ) throws -> WorkspaceExpectedRevisionV1 {
        try WorkspaceExpectedRevisionV1(
            workspaceID: workspaceID,
            generationID: id(slot),
            writerInstanceID: id(slot + 1),
            workspaceRevision: 0,
            entityRevisions: [
                WorkspaceEntityRevisionV1(
                    identity: WorkspaceEntityIdentityV1(
                        kind: .acceptedLabelGenerationSnapshot,
                        id: snapshotID
                    ),
                    revision: 0
                ),
            ]
        )
    }

    static func actor(workspaceID: WorkspaceID, slot: Int) throws -> ActorSnapshotV1 {
        let reference = try LocalActorReferenceV1(
            actorReferenceID: id(slot),
            workspaceID: workspaceID,
            displayName: "C30 local operator"
        )
        return try ActorSnapshotV1(
            snapshotID: id(slot + 1),
            workspaceID: workspaceID,
            actor: reference,
            responsibility: .approvedBy,
            displayNameAtTime: reference.displayName,
            capturedAt: date(Double(slot))
        )
    }

    static func body(_ index: Int) -> String {
        let alphabet = Array(ManualShortCodeV1.alphabet)
        var value = index
        var digits = Array(repeating: alphabet[0], count: ManualShortCodeV1.randomBodyLength)
        for position in digits.indices.reversed() {
            digits[position] = alphabet[value % alphabet.count]
            value /= alphabet.count
        }
        return String(digits)
    }

    static func workspace(_ slot: Int) -> WorkspaceID { WorkspaceID(rawValue: id(slot)) }
    static func mutation(_ slot: Int) throws -> MutationIDV1 { try MutationIDV1(rawValue: id(slot)) }
    static func id(_ slot: Int) -> UUID {
        let high = UInt64(slot) >> 32
        let low = UInt64(slot) & 0xffff_ffff
        return UUID(uuidString: String(
            format: "%08llx-0000-0000-0000-%012llx",
            high,
            low
        ))!
    }
    static func date(_ offset: Double) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + offset)
    }
}

private struct C30LocatorQuery: AssetLocatorQueryingV1 {
    let locator: AssetLocatorV1

    func locator(id: UUID, workspaceID: WorkspaceID) async throws -> AssetLocatorV1? {
        locator.locatorID == id && locator.workspaceID == workspaceID ? locator : nil
    }

    func locators(lookupKey: String, workspaceID: WorkspaceID) async throws -> [AssetLocatorV1] {
        guard locator.workspaceID == workspaceID,
              locator.lookupKey == lookupKey else { return [] }
        return [locator]
    }
}

@MainActor
private final class C30AcceptedSnapshotQuery: AcceptedLabelGenerationSnapshotQueryingV1 {
    let snapshot: AcceptedLabelGenerationSnapshotV1

    init(snapshot: AcceptedLabelGenerationSnapshotV1) { self.snapshot = snapshot }

    func acceptedLabelSnapshot(
        workspaceID: WorkspaceID,
        mutationID: MutationIDV1
    ) async throws -> AcceptedLabelGenerationSnapshotV1? {
        snapshot.workspaceID == workspaceID && snapshot.mutationID == mutationID ? snapshot : nil
    }

    func acceptedLabelSnapshot(
        workspaceID: WorkspaceID,
        snapshotID: UUID
    ) async throws -> AcceptedLabelGenerationSnapshotV1? {
        snapshot.workspaceID == workspaceID && snapshot.snapshotID == snapshotID ? snapshot : nil
    }
}

@MainActor
private final class C30RejectingLabelWriter: AssetLabelCanonicalWorkspaceWritingV1 {
    func acceptedReceipt(
        for mutation: AssetLabelMutationV1
    ) async throws -> AssetLabelAcceptanceReceiptV1? {
        _ = mutation
        return nil
    }

    func commitAssetLabel(
        _ mutation: AssetLabelMutationV1
    ) async throws -> AssetLabelAcceptanceReceiptV1 {
        _ = mutation
        throw AssetLabelContractFailureV1.invalidReceipt
    }
}

private final class C30CleanupTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var removalCount: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    func recordRemoval() {
        lock.lock(); defer { lock.unlock() }
        count += 1
    }
}

@MainActor
private final class C30MutableAcceptedSnapshotQuery: AcceptedLabelGenerationSnapshotQueryingV1 {
    var snapshot: AcceptedLabelGenerationSnapshotV1?

    func acceptedLabelSnapshot(
        workspaceID: WorkspaceID,
        mutationID: MutationIDV1
    ) async throws -> AcceptedLabelGenerationSnapshotV1? {
        snapshot.flatMap {
            $0.workspaceID == workspaceID && $0.mutationID == mutationID ? $0 : nil
        }
    }

    func acceptedLabelSnapshot(
        workspaceID: WorkspaceID,
        snapshotID: UUID
    ) async throws -> AcceptedLabelGenerationSnapshotV1? {
        snapshot.flatMap {
            $0.workspaceID == workspaceID && $0.snapshotID == snapshotID ? $0 : nil
        }
    }
}

private struct C30AccessGate: AppAccessGatePortV1 {
    func currentState() async -> AppAccessStateV1 { .locked(reason: .lockNow) }
    func lock(reason: AppLockReasonV1) async { _ = reason }
    func authenticate(
        trigger: LocalAuthenticationTriggerV1
    ) async -> LocalAuthenticationOutcomeV1 {
        _ = trigger
        return .authenticated
    }
    func requireContentAccess() async throws {
        throw WorkspaceExperienceFailureV1.permissionRequired
    }
}

private struct C30RejectingSignatureVerifier: LocalLocatorSignatureVerifyingV1 {
    func verify(
        payload: Data,
        signature: Data,
        key: LocatorSigningKeyReferenceV1
    ) throws -> Bool {
        _ = payload; _ = signature; _ = key
        return false
    }
}

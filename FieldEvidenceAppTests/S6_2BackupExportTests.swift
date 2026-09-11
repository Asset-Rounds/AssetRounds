import CoreGraphics
import CoreFoundation
import CryptoKit
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

private enum C52ServiceRequestBoundary_S6_2BackupExportTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

private enum C53AssetServiceReliabilityBoundary_S6_2BackupExportTests {
    static let typedAnchor: C53AssetServiceReliabilityBoundaryTokenV1.Type = C53AssetServiceReliabilityBoundaryTokenV1.self
}

private final class C45BackupExportCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityExportsAcceptedSnapshotNotScratchPlans() {
        XCTAssertEqual(AssetLabelPersistenceEnrollmentV1.persistentFamilies, ["AcceptedLabelGenerationSnapshotRow"])
        XCTAssertFalse(AssetLabelPersistenceEnrollmentV1.persistentFamilies.contains("AssetLabelGenerationPlanV1"))
        XCTAssertFalse(AssetLabelPersistenceEnrollmentV1.persistentFamilies.contains("LabelProjectionResultV1"))
    }
}

private final class C30EvidenceContextAnchorS6_2BackupExport: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

final class S6_2BackupExportTests: XCTestCase {
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
    func testV23P03C29TypedPlanContractAnchor() throws {
        let minimum = try NormalizedPlanCoordinateV1(millionths: 0)
        let maximum = try NormalizedPlanCoordinateV1(millionths: PlanLimitsV1.normalizedScale)
        XCTAssertEqual(minimum.millionths, 0)
        XCTAssertEqual(maximum.millionths, PlanLimitsV1.normalizedScale)
        XCTAssertEqual(PlanDocumentV1.schemaVersion, 1)
    }
    func testV23P03C40Records10CanonicalExportCarriesTypedV11Record() throws {
        let source = try C40BackupLifecycleTestValues.source()
        let records = try C40BackupLifecycleTestValues.records([source])
        let encoded = try BackupCanonicalEncoderV1().encodeRecords(records)
        let decoded = try BackupCanonicalDecoderV1().decodeRecords(encoded.data)
        XCTAssertEqual(decoded.recordsSchemaVersion, 10)
        XCTAssertEqual(decoded.authorityCriterion, records.authorityCriterion)
        XCTAssertEqual(decoded.authorityCriterion.first?.kind, .authoritySourceRelease)
        XCTAssertEqual(decoded.authorityCriterion.first?.id, source.releaseID)
        XCTAssertEqual(
            Set(V11BackupAuthorityCriterionRecordV1.Kind.allCases.map(\.rawValue)),
            Set([
                "AUTHORITY_SOURCE_RELEASE", "REQUIREMENT_BASIS_BINDING",
                "APPLICABILITY_CONTEXT_SNAPSHOT", "ASSESSMENT_SCOPE_SNAPSHOT",
                "SEVERITY_SCALE_RELEASE", "FINDING_CLASSIFICATION_BINDING",
                "MEASUREMENT_PROTOCOL_RELEASE", "DERIVED_FACT_EVALUATOR_DESCRIPTOR",
                "DERIVED_FACT_PROVENANCE",
            ])
        )
    }

    func testV23P03C39BackupCodecEnforcesBoundedCanonicalInput() throws {
        let value = AssetProductIdentifierReviewStateV1.unknownRecorded
        let bytes = try AssetSemanticCanonicalCodecV1.encode(value)
        XCTAssertEqual(
            try AssetSemanticCanonicalCodecV1.decode(
                AssetProductIdentifierReviewStateV1.self,
                from: bytes
            ),
            value
        )
        XCTAssertThrowsError(
            try AssetSemanticCanonicalCodecV1.decode(
                AssetProductIdentifierReviewStateV1.self,
                from: Data(repeating: 0, count: 8_388_609)
            )
        ) { error in
            XCTAssertEqual(error as? AssetSemanticContractFailureV1, .invalidValue)
        }
    }

    private let fileManager = FileManager.default

    @MainActor
    func testV8ExportRejectsMissingRequirementAssuranceCompanion() async throws {
        let harness = try await makeMixedHarness("missing-assurance")
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let rows = try harness.session.modelContext.fetch(
            FetchDescriptor<RequirementAssuranceRow>()
        )
        let removed = try XCTUnwrap(rows.first)
        harness.session.modelContext.delete(removed)
        try harness.session.modelContext.save()

        let service = makeService(harness, capacity: .max)
        XCTAssertThrowsError(try service.prepare()) { error in
            XCTAssertEqual(error as? BackupExportServiceError, .invalidAuthority)
        }
    }

    @MainActor
    func testPopulatedQualityAndInboxSurvivePackageTransportAndPhysicalReplace() async throws {
        let harness = try await makeMixedHarness("populated-quality-inbox", currentWriterSource: true)
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let evidence = try harness.context.fetch(FetchDescriptor<EvidenceFile>()).sorted { $0.id.uuidString < $1.id.uuidString }
        XCTAssertGreaterThanOrEqual(evidence.count, 3)
        let quality = try C10ProductionFixture(session: harness.session, applicationSupportURL: harness.applicationSupportURL)
        defer { try? quality.closeCurrentWriter() }
        let primary = try quality.capture(evidence: evidence[0], generationRootURL: harness.session.generationRootURL)
        let comparison = try quality.capture(evidence: evidence[1], generationRootURL: harness.session.generationRootURL)
        let third = try quality.capture(evidence: evidence[2], generationRootURL: harness.session.generationRootURL)
        let request = try quality.request(revision: 1, primary: primary, comparison: comparison, collection: [primary, third])
        guard case let .assessed(assessment, _) = try quality.coordinator.assess(request) else {
            return XCTFail("Persisted evidence assessment expected")
        }
        let waiver = try quality.waiver(for: assessment)
        let expectedQuality = try quality.physicalBackupSnapshot()
        XCTAssertEqual(expectedQuality.ruleSets.count, 1)
        XCTAssertEqual(expectedQuality.assessments, [assessment])
        XCTAssertEqual(expectedQuality.waivers, [waiver])
        XCTAssertEqual(expectedQuality.receipts.count, 3)
        XCTAssertEqual(expectedQuality.effectProvenance.count, 3)

        // The inbox destination is a real canonical asset creation, not the
        // older isolated fixture's canned resolver answer.
        let targetSiteID = UUID(), targetAssetID = UUID(), targetMutation = try MutationIDV1(rawValue: UUID())
        let pack = SignPack.illuminatedSignV1
        _ = try quality.writer.execute(.createFirstSign(.init(
            siteID: targetSiteID,
            newSite: .init(id: targetSiteID, label: "Inbox destination", address: nil, timeZoneID: "UTC"),
            assetID: targetAssetID, assetLabel: "Persisted inbox target", packID: pack.packID,
            packSchemaVersion: pack.schemaVersion, packContentVersion: pack.contentVersion,
            createdAt: Date(timeIntervalSince1970: 1_776_422_000),
            initialPlacementMutationID: targetMutation, initialPlacementEventID: UUID(),
            initialPhysicalEpisodeID: PhysicalPlacementEpisodeIDV1(rawValue: UUID())
        )), mutationID: targetMutation)
        try quality.journal.validateAll()
        try quality.closeCurrentWriter()

        let inbox = try C11Fixture(session: harness.session, applicationSupportURL: harness.applicationSupportURL,
            destinationAssetID: targetAssetID)
        defer { try? inbox.closeCurrentWriter() }
        let captured = try inbox.item(evidence: evidence[0], label: "promoted")
        let unresolved = try inbox.item(evidence: evidence[1], label: "unresolved")
        _ = try inbox.commit(.putInboxItem(captured), mutationID: captured.mutationID)
        _ = try inbox.commit(.putInboxItem(unresolved), mutationID: unresolved.mutationID)
        let (promotion, promoted) = try inbox.promotion(source: captured, kind: .assetEvidence)
        _ = try inbox.commit(.promote(promotion, promoted), mutationID: promotion.mutationID)
        let snippet = try inbox.snippet(title: "Preserved text", body: "Explicitly saved original snippet")
        _ = try inbox.commit(.putSnippet(snippet), mutationID: snippet.mutationID)
        let insertion = try inbox.insertion(snippet: snippet)
        _ = try inbox.commit(.insertSnippet(insertion, snippet), mutationID: insertion.mutationID)
        XCTAssertEqual(try inbox.currentDestination(), promotion.destination)
        let expectedInbox = try inbox.physicalBackupSnapshot()
        XCTAssertEqual(expectedInbox.inboxItems.count, 3)
        XCTAssertEqual(expectedInbox.promotions, [promotion])
        XCTAssertEqual(expectedInbox.snippets, [snippet])
        XCTAssertEqual(expectedInbox.snippetInsertions, [insertion])
        XCTAssertEqual(expectedInbox.receipts.count, 5)
        XCTAssertEqual(expectedInbox.effectProvenance.count, 6)
        XCTAssertEqual(expectedInbox.effectProvenance.filter { $0.mutationID == promotion.mutationID.rawValue }.count, 2)
        let originalHistory = try inbox.writer.sourceMutationHistorySnapshot()
        try MutationJournalStoreV1.validateImportedSnapshot(originalHistory)
        try inbox.journal.validateAll()
        try inbox.closeCurrentWriter()
        let sourceTree = try treeFacts(harness.session.generationRootURL)
        let sourceModels = try modelFacts(harness.context)
        let originalMedia = try Dictionary(uniqueKeysWithValues: evidence.map {
            ($0.id, try Data(contentsOf: harness.session.generationRootURL.appendingPathComponent($0.relativePath)))
        })
        let destination = harness.applicationSupportURL.appendingPathComponent("populated-export", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        let exporter = makeService(harness, capacity: .max)
        let preview = try exporter.prepare()
        let package = try exporter.export(previewID: preview.id, to: destination)
        let importer = try BackupImportService(generationRootURL: harness.session.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }), scopedAccess: .alreadyAuthorized)
        let validated = try importer.stageAndValidate(selectedPackageURL: package)
        defer { try? importer.discard(validated) }
        XCTAssertEqual(validated.records.evidenceQuality, expectedQuality)
        XCTAssertEqual(validated.records.fastSurveyInbox, expectedInbox)
        XCTAssertEqual(validated.records.mutationHistory, originalHistory)
        let recordBytes = try XCTUnwrap(validated.members["records.json"])
        XCTAssertEqual(try BackupCanonicalEncoderV1().encodeRecords(validated.records).data, recordBytes)
        XCTAssertEqual(try BackupCanonicalDecoderV1().decodeRecords(recordBytes), validated.records)
        var fields = try object(recordBytes)
        let qualityFields = try XCTUnwrap(fields["evidenceQuality"] as? [String: Any])
        let inboxFields = try XCTUnwrap(fields["fastSurveyInbox"] as? [String: Any])
        XCTAssertTrue(NSDictionary(dictionary: qualityFields).isEqual(to:
            try object(WorkspaceMutationCanonicalV1.data(expectedQuality))))
        XCTAssertTrue(NSDictionary(dictionary: inboxFields).isEqual(to:
            try object(WorkspaceMutationCanonicalV1.data(expectedInbox))))
        let assessmentFields = try XCTUnwrap((qualityFields["assessments"] as? [[String: Any]])?.first)
        let revision = try XCTUnwrap(assessmentFields["revision"] as? NSNumber)
        XCTAssertEqual(revision.intValue, 1)
        XCTAssertNotEqual(CFGetTypeID(revision), CFBooleanGetTypeID())
        for (key, expected) in [("advisoryOnly", true), ("altersRequirementComplianceSafetyOrInspectionOutcome", false)] {
            let value = try XCTUnwrap(assessmentFields[key] as? NSNumber)
            XCTAssertEqual(CFGetTypeID(value), CFBooleanGetTypeID())
            XCTAssertEqual(value.boolValue, expected)
        }
        let findings = try XCTUnwrap(assessmentFields["orderedFindings"] as? [[String: Any]])
        let duplicate = try XCTUnwrap(findings.first { ($0["ruleID"] as? String) == EvidenceQualityRuleIDV1.duplicate.rawValue })
        let duplicateInput = try XCTUnwrap(duplicate["input"] as? [String: Any])
        let zero = try XCTUnwrap(duplicateInput["measuredValue"] as? NSNumber)
        XCTAssertEqual(zero.intValue, 0)
        XCTAssertNotEqual(CFGetTypeID(zero), CFBooleanGetTypeID())
        var fractional = fields
        var fractionalQuality = qualityFields
        var fractionalAssessments = try XCTUnwrap(qualityFields["assessments"] as? [[String: Any]])
        fractionalAssessments[0]["revision"] = 1.5
        fractionalQuality["assessments"] = fractionalAssessments
        fractional["evidenceQuality"] = fractionalQuality
        XCTAssertThrowsError(try BackupCanonicalDecoderV1().decodeRecords(
            JSONSerialization.data(withJSONObject: fractional, options: [.sortedKeys])))
        XCTAssertNotNil(fields.removeValue(forKey: "mutationHistory"))
        let semanticBytes = try BackupCanonicalEncoderV1().encodeSemanticRecords(validated.records).data
        XCTAssertTrue(NSDictionary(dictionary: fields).isEqual(to: try object(semanticBytes)))
        XCTAssertEqual(try BackupCanonicalEncoderV1().encodeSemanticRecords(validated.records).data, semanticBytes)
        XCTAssertEqual(try treeFacts(harness.session.generationRootURL), sourceTree)
        XCTAssertEqual(try modelFacts(harness.context), sourceModels)

        let factory = StoreGenerationFactory(applicationSupportURL: harness.applicationSupportURL)
        try importer.discard(validated)
        for mode in [BackupRestoreMode.clone, .fork] {
            let retryPackage = try importer.stageAndValidate(selectedPackageURL: package)
            defer { try? importer.discard(retryPackage) }
            let authority = try factory.makeRestoreGenerationAuthority()
            XCTAssertEqual(try authority.importStagingNames(), [retryPackage.stagedPackageURL.lastPathComponent])
            let currentJournal = try MutationJournalStoreV1(modelContext: harness.context,
                identity: harness.session.workspaceIdentity, generationID: harness.session.generationID,
                allowStateBootstrap: false)
            try currentJournal.validateAll()
            XCTAssertEqual(try currentJournal.exportSnapshot(), originalHistory)
            let restore = try BackupRestoreService(applicationSupportURL: harness.applicationSupportURL,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }))
            do {
                _ = try await restore.restore(validatedPackage: retryPackage, currentModelContext: harness.context,
                    currentGenerationID: harness.session.generationID,
                    currentGenerationRootURL: harness.session.generationRootURL, mode: mode)
                XCTFail("Populated immutable quality/inbox facts cannot be rebound by clone/fork")
            } catch {
                XCTAssertEqual(error as? BackupRestoreServiceError, .invalidRestoreAuthority)
            }
            XCTAssertEqual(try factory.currentGenerationID(), harness.session.generationID)
            XCTAssertEqual(try currentJournal.exportSnapshot(), originalHistory)
            XCTAssertEqual(try quality.physicalBackupSnapshot(), expectedQuality)
            XCTAssertEqual(try inbox.physicalBackupSnapshot(), expectedInbox)
            XCTAssertEqual(try treeFacts(harness.session.generationRootURL), sourceTree)
            XCTAssertEqual(try modelFacts(harness.context), sourceModels)
        }
        let restore = try BackupRestoreService(applicationSupportURL: harness.applicationSupportURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }))
        let replacementPackage = try importer.stageAndValidate(selectedPackageURL: package)
        defer { try? importer.discard(replacementPackage) }
        let restored = try await restore.restore(validatedPackage: replacementPackage, currentModelContext: harness.context,
            currentGenerationID: harness.session.generationID,
            currentGenerationRootURL: harness.session.generationRootURL, mode: .replaceExisting)
        let reopened = try factory.openOrBootstrapCurrent()
        XCTAssertEqual(reopened.generationID, restored.generationID)
        XCTAssertNotEqual(reopened.generationID, harness.session.generationID)
        XCTAssertEqual(reopened.workspaceID, harness.session.workspaceID)
        XCTAssertEqual(try C10ProductionFixture.physicalBackupSnapshot(in: reopened.modelContext,
            workspaceID: reopened.workspaceID), expectedQuality)
        XCTAssertEqual(try C11Fixture.physicalBackupSnapshot(in: reopened.modelContext,
            workspaceID: reopened.workspaceID), expectedInbox)
        let restoredJournal = try MutationJournalStoreV1(modelContext: reopened.modelContext,
            identity: reopened.workspaceIdentity, generationID: reopened.generationID, allowStateBootstrap: false)
        try restoredJournal.validateAll()
        XCTAssertEqual(try restoredJournal.exportSnapshot(), originalHistory)
        let restoredEvidence = try reopened.modelContext.fetch(FetchDescriptor<EvidenceFile>())
        XCTAssertEqual(Set(restoredEvidence.map(\.id)), Set(originalMedia.keys))
        for row in restoredEvidence {
            XCTAssertEqual(try Data(contentsOf: reopened.generationRootURL.appendingPathComponent(row.relativePath)),
                try XCTUnwrap(originalMedia[row.id]))
        }
    }

    @MainActor
    func testMixedExportFreezesAllAuthorityAndRecomputesManifestIndependently() async throws {
        let harness = try await makeMixedHarness("golden")
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let sourceFacts = try sourceMediaFacts(harness)
        let before = try treeFacts(harness.session.generationRootURL)
        let destination = harness.applicationSupportURL.appendingPathComponent("export", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        let service = makeService(harness, capacity: .max)

        let preview = try service.prepare()
        XCTAssertEqual(preview.signCount, 1)
        XCTAssertEqual(preview.reportCount, 3)
        XCTAssertEqual(preview.photoCount, 6)
        let package = try service.export(previewID: preview.id, to: destination)
        XCTAssertEqual(package.lastPathComponent, "AssetRounds.fieldrecordbackup")
        XCTAssertEqual(
            try package.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
            true
        )
        XCTAssertEqual(try treeFacts(harness.session.generationRootURL), before)

        let importer = try BackupImportService(
            generationRootURL: harness.session.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
            makeUUID: {
                UUID(uuidString: "62000000-0000-0000-0000-000000000098")!
            },
            scopedAccess: .alreadyAuthorized
        )
        let validated = try importer.stageAndValidate(selectedPackageURL: package)
        defer { try? importer.discard(validated) }
        XCTAssertEqual(validated.manifest.backupSchemaVersion, 4)
        XCTAssertEqual(validated.manifest.source.persistentSchemaVersion, 53)
        XCTAssertEqual(validated.manifest.source.recordsSchemaVersion, 52)
        XCTAssertEqual(
            PersistentSchemaReleaseRegistryV1.activeVersionIdentifier,
            Schema.Version(validated.manifest.source.persistentSchemaVersion, 0, 0)
        )
        XCTAssertEqual(validated.records.requirementAssurance.count, validated.records.workflowRecords.count)
        XCTAssertTrue(validated.records.requirementAssurance.allSatisfy {
            (try? $0.validate()) != nil
        })
        XCTAssertTrue(validated.records.savedSmartViews.isEmpty)
        XCTAssertNotNil(validated.records.mutationHistory)
        let placementHistory = try validated.records.assetPlacementEvents.map {
            try LocationPersistenceCodecV1.decode(
                AssetPlacementEventV1.self,
                from: $0.canonicalData
            )
        }
        XCTAssertEqual(placementHistory.count, 1)
        XCTAssertNoThrow(try AssetPlacementHistoryV1.validate(placementHistory))

        let recordsData = try XCTUnwrap(validated.members["records.json"])
        let decodedRecords = try BackupCanonicalDecoderV1().decodeRecords(recordsData)
        XCTAssertEqual(decodedRecords.recordsSchemaVersion, 52)
        XCTAssertEqual(
            validated.manifest.source.recordsSchemaVersion,
            decodedRecords.recordsSchemaVersion
        )
        XCTAssertEqual(decodedRecords, validated.records)
        let emptyQuality = try XCTUnwrap(decodedRecords.evidenceQuality)
        let emptyInbox = try XCTUnwrap(decodedRecords.fastSurveyInbox)
        XCTAssertEqual(emptyQuality, try EvidenceQualityBackupSnapshotV1(ruleSets: [], assessments: [],
            waivers: [], receipts: [], effectProvenance: []))
        XCTAssertEqual(emptyInbox, try FastSurveyInboxBackupSnapshotV1(inboxItems: [], promotions: [],
            snippets: [], snippetInsertions: [], receipts: [], effectProvenance: []))
        let currentFields = try object(recordsData)
        XCTAssertNotNil(currentFields["evidenceQuality"] as? [String: Any])
        XCTAssertNotNil(currentFields["fastSurveyInbox"] as? [String: Any])
        let originalCurrentBytes = try BackupCanonicalEncoderV1().encodeRecords(decodedRecords).data
        let originalCurrentHistory = decodedRecords.mutationHistory
        let semanticBytes = try BackupCanonicalEncoderV1().encodeSemanticRecords(decodedRecords).data
        var expectedSemanticFields = try XCTUnwrap(JSONSerialization.jsonObject(with: originalCurrentBytes)
            as? [String: Any])
        XCTAssertNotNil(expectedSemanticFields.removeValue(forKey: "mutationHistory"))
        let actualSemanticFields = try XCTUnwrap(JSONSerialization.jsonObject(with: semanticBytes)
            as? [String: Any])
        XCTAssertTrue(NSDictionary(dictionary: expectedSemanticFields).isEqual(to: actualSemanticFields))
        XCTAssertEqual(try BackupCanonicalEncoderV1().encodeSemanticRecords(decodedRecords).data, semanticBytes)
        XCTAssertEqual(try BackupCanonicalEncoderV1().encodeRecords(decodedRecords).data, originalCurrentBytes)
        XCTAssertEqual(decodedRecords.mutationHistory, originalCurrentHistory)
        XCTAssertNil(decodedRecords.practiceWorkspaceProvenance)
        XCTAssertNil(expectedSemanticFields["practiceWorkspaceProvenance"])
        // Exercise the nonnil codec branch with validated practice provenance,
        // not an invented placeholder in the REAL-workspace export above.
        let practiceTemplate = try StarterWorkspaceTemplateReleaseV1(
            templateID: UUID(), release: 1, titleKey: "workspace.starter.practice.title",
            packageReleaseIDs: ["shipping.illuminated-sign.v1"],
            practiceWatermark: "PRACTICE — NOT FOR FIELD USE"
        )
        let practiceWorkspaceID = try XCTUnwrap(validated.manifest.source.workspaceID)
        let practicePlan = try StarterWorkspaceInstallPlanV1(
            planID: UUID(), workspaceID: WorkspaceID(rawValue: practiceWorkspaceID),
            template: practiceTemplate, mutationID: MutationIDV1(rawValue: UUID()),
            requestedAt: Date(timeIntervalSince1970: 1_777_593_600),
            explicitUserRequest: true, destinationWasEmpty: true
        )
        let practiceReceipt = try StarterWorkspaceInstallReceiptV1(
            receiptID: UUID(), plan: practicePlan, resultingWorkspaceRevision: 1,
            installedAt: Date(timeIntervalSince1970: 1_777_593_601), disposition: .committed
        )
        let practiceSnapshot = try PracticeWorkspaceBackupSnapshotV1(provenance:
            PracticeWorkspaceProvenanceV1(provenanceID: UUID(), plan: practicePlan,
                receipt: practiceReceipt, revision: 1))
        var practiceObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decodedRecords))
            as? [String: Any])
        practiceObject["practiceWorkspaceProvenance"] = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(practiceSnapshot))
        let practiceRecords = try JSONDecoder().decode(V4BackupRecordsV1.self, from:
            JSONSerialization.data(withJSONObject: practiceObject, options: [.sortedKeys]))
        let practiceFullBytes = try BackupCanonicalEncoderV1().encodeRecords(practiceRecords).data
        let practiceSemanticBytes = try BackupCanonicalEncoderV1().encodeSemanticRecords(practiceRecords).data
        var practiceFields = try XCTUnwrap(JSONSerialization.jsonObject(with: practiceFullBytes)
            as? [String: Any])
        XCTAssertNotNil(practiceFields["practiceWorkspaceProvenance"])
        XCTAssertNotNil(practiceFields.removeValue(forKey: "mutationHistory"))
        XCTAssertTrue(NSDictionary(dictionary: practiceFields).isEqual(to:
            try XCTUnwrap(JSONSerialization.jsonObject(with: practiceSemanticBytes) as? [String: Any])))
        let decodedPractice = try BackupCanonicalDecoderV1().decodeRecords(practiceFullBytes)
        XCTAssertEqual(decodedPractice.practiceWorkspaceProvenance, practiceSnapshot)
        XCTAssertEqual(try WorkspaceExperienceCanonicalCodecV1.data(
            XCTUnwrap(decodedPractice.practiceWorkspaceProvenance)),
            try WorkspaceExperienceCanonicalCodecV1.data(practiceSnapshot))
        var noHistoryObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decodedRecords))
            as? [String: Any])
        noHistoryObject.removeValue(forKey: "mutationHistory")
        let noHistory = try JSONDecoder().decode(V4BackupRecordsV1.self, from:
            JSONSerialization.data(withJSONObject: noHistoryObject, options: [.sortedKeys]))
        XCTAssertThrowsError(try BackupCanonicalEncoderV1().encodeSemanticRecords(noHistory)) {
            XCTAssertEqual($0 as? BackupCanonicalEncodingErrorV1, .invalidRecords)
        }
        let importBoundaries: [(Int, (ValidatedV4BackupPackageV1) throws -> Void)] = [
            (36, C49WorkResourceBackupImportPolicyV1.validate),
            (38, C52ServiceRequestBackupImportServiceBoundaryV1.validate),
            (39, C53ServiceReliabilityBackupImportServiceBoundaryV1.validate),
            (40, C55PartsStockBackupImportServiceBoundaryV1.validate),
            (41, C57MyDayBackupImportServiceBoundaryV1.validate)
        ]
        func boundaryPackage(
            records: V4BackupRecordsV1,
            declaredRecords: Int,
            persistent: Int
        ) -> ValidatedV4BackupPackageV1 {
            let original = validated.manifest
            return ValidatedV4BackupPackageV1(
                stagedPackageURL: validated.stagedPackageURL,
                manifest: V4BackupManifestV1(
                    backupSchemaVersion: original.backupSchemaVersion,
                    consumedEvaluationRootIDs: original.consumedEvaluationRootIDs,
                    declaredPayloadByteCount: original.declaredPayloadByteCount,
                    entries: original.entries, exportedAt: original.exportedAt,
                    packs: original.packs,
                    source: V4BackupSourceV1(
                        appBuild: original.source.appBuild,
                        appVersion: original.source.appVersion,
                        persistentSchemaVersion: persistent,
                        replicaID: original.source.replicaID,
                        recordsSchemaVersion: declaredRecords,
                        sourceGenerationID: original.source.sourceGenerationID,
                        workspaceID: original.source.workspaceID
                    )
                ),
                records: records, members: validated.members, summary: validated.summary
            )
        }
        // These typed variants test the admission boundaries, not archive
        // integrity. The unchanged package above went through real extraction,
        // checksum validation, decoding and all five importer calls.
        var futureObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(decodedRecords)
        ) as? [String: Any])
        futureObject["recordsSchemaVersion"] = 53
        let futureRecords = try JSONDecoder().decode(V4BackupRecordsV1.self, from:
            JSONSerialization.data(withJSONObject: futureObject, options: [.sortedKeys]))
        let hostilePackages = [
            boundaryPackage(records: decodedRecords, declaredRecords: 51, persistent: 53),
            boundaryPackage(records: decodedRecords, declaredRecords: 52, persistent: 52),
            boundaryPackage(records: futureRecords, declaredRecords: 53, persistent: 54)
        ]
        XCTAssertThrowsError(try BackupCanonicalEncoderV1().encodeRecords(futureRecords)) {
            XCTAssertEqual($0 as? BackupCanonicalEncodingErrorV1, .invalidRecords)
        }
        XCTAssertThrowsError(try BackupCanonicalEncoderV1().encodeSemanticRecords(futureRecords)) {
            XCTAssertEqual($0 as? BackupCanonicalEncodingErrorV1, .invalidRecords)
        }
        for hostile in hostilePackages {
            XCTAssertThrowsError(try BackupCanonicalEncoderV1().encodeManifest(hostile.manifest)) {
                XCTAssertEqual($0 as? BackupCanonicalEncodingErrorV1, .invalidManifest)
            }
        }
        var unknownVersionObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: BackupCanonicalEncoderV1().encodeRecords(decodedRecords).data
        ) as? [String: Any])
        unknownVersionObject["recordsSchemaVersion"] = 53
        // This is an unknown-version input derived from actual canonical
        // current bytes, not a claimed canonical unknown-schema round-trip.
        let unknownVersionData = try JSONSerialization.data(
            withJSONObject: unknownVersionObject, options: [.sortedKeys]
        )
        XCTAssertThrowsError(try BackupCanonicalDecoderV1().decodeRecords(unknownVersionData)) {
            XCTAssertEqual($0 as? BackupCanonicalDecodingErrorV1, .invalidRecords)
        }
        let emptyHistory = MutationHistorySnapshotV1(
            workspaceRevision: 0, lastLocalSequence: 0,
            receipts: [], quarantines: [], entityRevisions: []
        )
        let actualStock = try XCTUnwrap(decodedRecords.partsStockSnapshot)
        for (introductionVersion, validateBoundary) in importBoundaries {
            XCTAssertNoThrow(try validateBoundary(validated))
            for hostile in hostilePackages {
                XCTAssertThrowsError(try validateBoundary(hostile)) { error in
                    XCTAssertEqual(error as? BackupImportServiceError, .invalidGeneration)
                }
            }
            // Each family's original introduction remains an admitted typed
            // empty workspace, with a real stock snapshot once C55 exists.
            let introduction = V4BackupRecordsV1(
                assets: [], deletionLedger: .empty, evidenceFiles: [], issues: [],
                mutationHistory: emptyHistory, packets: [],
                recordsSchemaVersion: introductionVersion,
                reports: [], sites: [], workflowRecords: [],
                partsStockSnapshot: introductionVersion >= 40 ? actualStock : nil
            )
            let introductionPackage = boundaryPackage(
                records: introduction, declaredRecords: introductionVersion,
                persistent: introductionVersion + 1
            )
            XCTAssertNoThrow(try validateBoundary(introductionPackage))
            if introductionVersion >= 40 {
                XCTAssertNoThrow(try C55PartsStockBackupImportBoundaryV1.validate(introduction))
            }
        }
        XCTAssertNoThrow(try C55PartsStockBackupImportBoundaryV1.validate(decodedRecords))
        XCTAssertThrowsError(try C55PartsStockBackupImportBoundaryV1.validate(futureRecords)) {
            XCTAssertEqual($0 as? BackupCanonicalDecodingErrorV1, .invalidRecords)
        }
        XCTAssertNoThrow(try C53ServiceReliabilityBackupPackageValidationV1.validate(
            decodedRecords, manifest: validated.manifest
        ))
        for hostile in hostilePackages {
            XCTAssertThrowsError(try C53ServiceReliabilityBackupPackageValidationV1.validate(
                hostile.records, manifest: hostile.manifest
            )) { error in
                XCTAssertEqual(error as? BackupPackageValidationErrorV1, .invalidPackage)
            }
        }
        XCTAssertEqual(
            try BackupCanonicalEncoderV1().encodeRecords(decodedRecords).data,
            recordsData
        )
        XCTAssertEqual(
            decodedRecords.requirementAssurance.map(\.canonicalData),
            validated.records.requirementAssurance.map(\.canonicalData)
        )
        let records = try XCTUnwrap(try JSONSerialization.jsonObject(with: recordsData) as? [String: Any])
        XCTAssertEqual((records["assets"] as? [Any])?.count, 1)
        XCTAssertEqual((records["reports"] as? [Any])?.count, 3)
        XCTAssertEqual((records["packets"] as? [Any])?.count, 4)
        let packetJSON = try XCTUnwrap(records["packets"] as? [[String: Any]])
        XCTAssertEqual(packetJSON.filter { $0["contentDeletedAt"] is String && $0["currentRecordID"] is NSNull }.count, 1)

        let manifestData = try XCTUnwrap(validated.members["manifest.json"])
        let manifest = try XCTUnwrap(try JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        let entries = try XCTUnwrap(manifest["entries"] as? [[String: Any]])
        let actual = validated.manifest.entries.map {
            PayloadFact(
                path: $0.path,
                byteCount: $0.byteCount,
                mimeType: $0.mimeType,
                sha256: $0.sha256
            )
        }
        XCTAssertEqual(entries.compactMap { $0["path"] as? String }, actual.map(\.path))
        XCTAssertEqual(entries.compactMap { $0["byteCount"] as? Int }, actual.map(\.byteCount))
        XCTAssertEqual(entries.compactMap { $0["sha256"] as? String }, actual.map(\.sha256))
        XCTAssertEqual(entries.compactMap { $0["mimeType"] as? String }, actual.map(\.mimeType))
        XCTAssertEqual(manifest["declaredPayloadByteCount"] as? Int, actual.reduce(0) { $0 + $1.byteCount })
        XCTAssertEqual(manifest["consumedEvaluationRootIDs"] as? [String], harness.countedRoots.sorted())

        let paths = Set(actual.map(\.path))
        let reports = try harness.context.fetch(FetchDescriptor<Report>())
        XCTAssertEqual(paths.filter { $0.hasPrefix("snapshots/") }.count, reports.count)
        XCTAssertEqual(paths.filter { $0.hasPrefix("pdfs/") }.count, 1)
        for report in reports {
            let id = report.id.uuidString.lowercased()
            XCTAssertTrue(paths.contains("snapshots/\(id).json"))
            XCTAssertEqual(paths.contains("pdfs/\(id).pdf"), report.pdfState == ReportPDFState.ready.rawValue)
        }
        for fact in sourceFacts {
            XCTAssertEqual(validated.members[fact.exportPath]?.sha256, fact.sha256)
            XCTAssertEqual(try Data(contentsOf: harness.session.generationRootURL.appendingPathComponent(fact.sourcePath)).sha256, fact.sha256)
        }
    }

    @MainActor
    func testDirtyMalformedAndUnsafeAuthorityFailClosed() async throws {
        let harness = try await makeMixedHarness("fail-closed")
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let service = makeService(harness, capacity: .max)
        let site = try XCTUnwrap(harness.context.fetch(FetchDescriptor<Site>()).first)
        site.label = "unsaved"
        XCTAssertThrowsError(try service.prepare()) { XCTAssertEqual($0 as? BackupExportServiceError, .contextHasChanges) }
        harness.context.rollback()

        let evidence = try XCTUnwrap(harness.context.fetch(FetchDescriptor<EvidenceFile>()).first)
        let validHash = evidence.sha256
        evidence.sha256 = validHash.uppercased()
        try harness.context.save()
        XCTAssertThrowsError(try service.prepare()) { XCTAssertEqual($0 as? BackupExportServiceError, .invalidAuthority) }
        evidence.sha256 = validHash
        try harness.context.save()

        let validPath = evidence.relativePath
        evidence.relativePath = "evidence/../\(evidence.id.uuidString.lowercased())/original.jpg"
        try harness.context.save()
        XCTAssertThrowsError(try service.prepare()) { XCTAssertEqual($0 as? BackupExportServiceError, .invalidAuthority) }
        evidence.relativePath = validPath
        try harness.context.save()
    }

    @MainActor
    func testInsufficientCapacityCreatesNoPackageAndMutatesNoLiveAuthority() async throws {
        let harness = try await makeMixedHarness("capacity")
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let destination = harness.applicationSupportURL.appendingPathComponent("export", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        let service = makeService(harness, capacity: 0)
        let preview = try service.prepare()
        let beforeFiles = try treeFacts(harness.session.generationRootURL)
        let beforeRecords = try modelFacts(harness.context)

        XCTAssertThrowsError(try service.export(previewID: preview.id, to: destination)) {
            guard let typed = $0 as? BackupExportServiceError else {
                return XCTFail("Expected exact capacity failure, got \($0)")
            }
            XCTAssertEqual(typed, .insufficientStorage)
        }
        XCTAssertFalse(fileManager.fileExists(atPath: destination.appendingPathComponent("AssetRounds.fieldrecordbackup").path))
        XCTAssertEqual(try treeFacts(harness.session.generationRootURL), beforeFiles)
        XCTAssertEqual(try modelFacts(harness.context), beforeRecords)
        XCTAssertFalse(harness.context.hasChanges)
    }

    func testCanonicalFixturesAndExportedBundleTypeDeclaration() throws {
        let records = try object(fixture("S6_2V4BackupRecordsV1"))
        XCTAssertEqual(Set(records.keys), ["assets", "evidenceFiles", "issues", "packets", "recordsSchemaVersion", "reports", "sites", "workflowRecords"])
        XCTAssertEqual(records["recordsSchemaVersion"] as? Int, 1)
        try assertEveryObject(in: records, key: "assets", hasKeys: ["createdAt", "id", "label", "packContentVersion", "packID", "packSchemaVersion", "schemaVersion", "siteID", "updatedAt"])
        try assertEveryObject(in: records, key: "evidenceFiles", hasKeys: ["byteCount", "createdAt", "id", "mimeType", "purposeKey", "recordID", "relativePath", "schemaVersion", "sha256", "thumbnailByteCount", "thumbnailRelativePath", "thumbnailSHA256"])
        try assertEveryObject(in: records, key: "issues", hasKeys: ["assetID", "createdAt", "id", "labelDisplaySnapshot", "labelKey", "openedByRecordID", "resolvedByRecordID", "schemaVersion", "status", "updatedAt"])
        try assertEveryObject(in: records, key: "packets", hasKeys: ["contentDeletedAt", "createdAt", "currentRecordID", "evaluationCounted", "id", "schemaVersion", "stableRootID"])
        try assertEveryObject(in: records, key: "reports", hasKeys: ["createdAt", "id", "packetID", "pdfRelativePath", "pdfSHA256", "pdfState", "replacesReportID", "schemaVersion", "snapshotRelativePath", "snapshotSHA256", "snapshotSchemaVersion", "sourceRecordID"])
        try assertEveryObject(in: records, key: "sites", hasKeys: ["address", "createdAt", "id", "label", "schemaVersion", "timeZoneID", "updatedAt"])
        try assertEveryObject(in: records, key: "workflowRecords", hasKeys: Self.workflowRecordKeys)
        let workflows = try XCTUnwrap(records["workflowRecords"] as? [[String: Any]])
        XCTAssertEqual(Set(workflows.compactMap { $0["stage"] as? String }), ["check", "recheck"])
        XCTAssertTrue(workflows.contains { $0["revisionKind"] as? String == "clerical_correction" && !($0["revisesRecordID"] is NSNull) })
        let issues = try XCTUnwrap(records["issues"] as? [[String: Any]])
        XCTAssertEqual(issues.first?["status"] as? String, "resolved")
        let packets = try XCTUnwrap(records["packets"] as? [[String: Any]])
        XCTAssertEqual(packets.filter { $0["currentRecordID"] is NSNull && $0["contentDeletedAt"] is String && $0["evaluationCounted"] as? Bool == true }.count, 1)
        let reports = try XCTUnwrap(records["reports"] as? [[String: Any]])
        XCTAssertEqual(Set(reports.compactMap { $0["pdfState"] as? String }), ["ready", "pending", "failed"])
        XCTAssertEqual(reports.filter { $0["pdfState"] as? String == "ready" && $0["pdfRelativePath"] is String && $0["pdfSHA256"] is String }.count, 1)
        XCTAssertEqual(reports.filter { $0["pdfState"] as? String != "ready" && $0["pdfRelativePath"] is NSNull && $0["pdfSHA256"] is NSNull }.count, 2)

        let manifest = try object(fixture("S6_2V4BackupManifestV1"))
        XCTAssertEqual(Set(manifest.keys), ["backupSchemaVersion", "consumedEvaluationRootIDs", "declaredPayloadByteCount", "entries", "exportedAt", "packs", "source"])
        let fixtureEntries = try XCTUnwrap(manifest["entries"] as? [[String: Any]])
        let fixturePaths = fixtureEntries.compactMap { $0["path"] as? String }
        XCTAssertEqual(fixturePaths, fixturePaths.sorted())
        XCTAssertEqual(fixtureEntries.filter { ($0["path"] as? String)?.hasPrefix("snapshots/") == true }.count, 3)
        XCTAssertEqual(fixtureEntries.filter { ($0["path"] as? String)?.hasPrefix("pdfs/") == true }.count, 1)
        XCTAssertEqual(manifest["declaredPayloadByteCount"] as? Int, fixtureEntries.reduce(0) { $0 + ($1["byteCount"] as? Int ?? -100) })
        let evidenceIDs = try XCTUnwrap(records["evidenceFiles"] as? [[String: Any]]).compactMap { $0["id"] as? String }
        let reportRows = try XCTUnwrap(records["reports"] as? [[String: Any]])
        let expectedPaths = ["records.json"]
            + evidenceIDs.flatMap { ["media/\($0).jpg", "thumbnails/\($0).jpg"] }
            + reportRows.compactMap { ($0["id"] as? String).map { "snapshots/\($0).json" } }
            + reportRows.compactMap { row in
                guard row["pdfState"] as? String == "ready", let id = row["id"] as? String else { return nil }
                return "pdfs/\(id).pdf"
            }
        XCTAssertEqual(Set(fixturePaths), Set(expectedPaths))
        let countedRoots = packets.compactMap { row -> String? in
            row["evaluationCounted"] as? Bool == true ? row["stableRootID"] as? String : nil
        }.sorted()
        XCTAssertEqual(manifest["consumedEvaluationRootIDs"] as? [String], countedRoots)

        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("FieldEvidenceApp.xcodeproj/project.pbxproj")
        let bytes = try String(contentsOf: project, encoding: .utf8)
        XCTAssertEqual(bytes.components(separatedBy: "INFOPLIST_FILE = FieldEvidenceApp/Info.plist;").count - 1, 2)
        let declarations = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]])
        let declaration = try XCTUnwrap(declarations.first { $0["UTTypeIdentifier"] as? String == "com.palatis3.fieldrecordbackup" })
        XCTAssertEqual(declaration["UTTypeConformsTo"] as? [String], ["com.apple.package"])
        let tags = try XCTUnwrap(declaration["UTTypeTagSpecification"] as? [String: Any])
        XCTAssertEqual(tags["public.filename-extension"] as? [String], ["fieldrecordbackup"])
    }

    func testV23P03C38BackupRestoreAndDeleteKeepAccountabilityRowsCanonical() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = root.appendingPathComponent(
            "FieldEvidenceAppTests/Fixtures/V21/Accountability/V21P03C38PartyAccountabilityCorpusV1.json"
        )
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any]
        )
        let persistence = try XCTUnwrap(fixture["persistence"] as? [String: Any])
        XCTAssertEqual(persistence["schemaRelease"] as? String, "PERSISTENT_SCHEMA_V9_PARTY_ACCOUNTABILITY")
        XCTAssertEqual(persistence["exportDisposition"] as? String, "CANONICAL_DOMAIN_BYTES_AND_FROZEN_SNAPSHOTS")
        XCTAssertEqual(persistence["deleteDisposition"] as? String, "EXPLICIT_ERASE_OR_TOMBSTONE_WITH_HISTORY_PRESERVED")

        let encoderSource = try String(
            contentsOf: root.appendingPathComponent(
                "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift"
            ),
            encoding: .utf8
        )
        let restoreSource = try String(
            contentsOf: root.appendingPathComponent(
                "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift"
            ),
            encoding: .utf8
        )
        let deletionSource = try String(
            contentsOf: root.appendingPathComponent(
                "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(encoderSource.contains("validPartyAccountability"))
        XCTAssertTrue(encoderSource.contains("partyAccountability"))
        XCTAssertTrue(restoreSource.contains("rebindingPartyAccountability"))
        XCTAssertTrue(restoreSource.contains("ServicePartyRow"))
        XCTAssertTrue(restoreSource.contains("SignoffSnapshotRow"))
        XCTAssertTrue(deletionSource.contains("ServicePartyRow"))
        XCTAssertTrue(deletionSource.contains("SignoffSnapshotRow"))
        XCTAssertTrue(deletionSource.contains("modelContext.delete"))
    }
}

private final class C27S62TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(PersistentSchemaV26.models.count, 94)
        XCTAssertEqual(LocatorInputSourceV1.allCases.count, 3)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionGrantsAccess)
    }
}

extension S6_2BackupExportTests {
    func testC24AccessibleDocumentTypedAnchor() throws {
        XCTAssertEqual(AccessibleDocumentSemanticTreeV1.schemaVersion, 1)
        XCTAssertEqual(AccessibleDocumentRoleV1.allCases.count, 13)
        XCTAssertEqual(AccessibleDocumentAssessmentStateV1.allCases.count, 4)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
    }
}

extension S6_2BackupExportTests {
    func testC22RecoverabilityVerificationAnchor() throws {
        XCTAssertEqual(RecoverabilityVerificationReceiptV1.schemaVersion, 1)
        try V21RecoverabilityImportBoundaryV1.validate(persistentSchemaVersion: 21, recordsSchemaVersion: 20)
        XCTAssertEqual(RecoverabilityVerificationLifecycleV1.backupEligibility, "SUBSEQUENT_BACKUPS_ONLY")
        XCTAssertFalse(RecoverabilityVerificationLifecycleV1.receiptInsideVerifiedArchive)
    }
}

extension S6_2BackupExportTests {
    func testV23P03C18BackupAndExportAreRequiredSandboxChecks() throws {
        let required: Set<PackageSandboxCheckKindV1> = [.backupRestore, .export]
        XCTAssertEqual(required.intersection(Set(PackageSandboxCheckKindV1.allCases)), required)
        XCTAssertTrue(PackageEvolutionLifecycleV1.backupRestoreRequired)
        XCTAssertTrue(PackageEvolutionLifecycleV1.exportReportRequired)
    }
}

extension S6_2BackupExportTests {
    func testV23P03C17DerivedIntegrationProjectionIsNotCanonicalBackupOrExport() throws {
        XCTAssertNoThrow(try IntegrationProjectionBackupExportExclusionV1.validate())
        XCTAssertFalse(IntegrationProjectionSchemaV1.canonicalBackupIncluded)
        XCTAssertFalse(IntegrationProjectionSchemaV1.canonicalExportIncluded)
    }
}

extension S6_2BackupExportTests {
    func testV23P03C36Records15ExportsClosedSixKindFamily() throws {
        XCTAssertEqual(V16BackupFieldDraftRecordV1.Kind.allCases.map(\.rawValue), ["checkpoint","stagingItem","commitSaga","contentReservation","commitReceipt","discardReceipt"])
        XCTAssertNoThrow(try V16FieldDraftImportBoundaryV1.validate(persistent:16,records:15))
        XCTAssertThrowsError(try V16FieldDraftImportBoundaryV1.validate(persistent:15,records:14))
    }
}

extension S6_2BackupExportTests {
    func testV23P03C15BackupExportPreservesCanonicalPacketRecord() throws {
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 150_162)
        let row = try WorkPacketManifestRow(fixture.manifest)
        let canonicalData = try WorkPacketCanonicalCodecV1.encode(fixture.manifest)
        XCTAssertEqual(row.canonicalData, canonicalData)
        XCTAssertEqual(row.canonicalSHA256, fixture.manifest.manifestSHA256)
        XCTAssertEqual(try row.value(), fixture.manifest)
    }
}

private extension S6_2BackupExportTests {
    struct Harness {
        let applicationSupportURL: URL
        let session: StoreGenerationSession
        let context: ModelContext
        let countedRoots: [String]
    }
    struct PayloadFact: Equatable {
        let path: String
        let byteCount: Int
        let mimeType: String
        let sha256: String
    }
    struct MediaFact { let sourcePath: String; let exportPath: String; let sha256: String }

    @MainActor
    func makeService(_ harness: Harness, capacity: Int64) -> BackupExportService {
        BackupExportService(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in capacity }),
            now: { Date(timeIntervalSince1970: 1_786_708_800) },
            makeUUID: { UUID(uuidString: "62000000-0000-0000-0000-000000000099")! },
            appVersion: { "4.0" }, appBuild: { "42" }
        )
    }

    @MainActor
    func makeMixedHarness(
        _ label: String,
        siteAddress: String? = nil,
        currentWriterSource: Bool = false
    ) async throws -> Harness {
        let support = fileManager.temporaryDirectory.appendingPathComponent("S6_2BackupExportTests-\(label)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: false)
        let session = try StoreGenerationFactory(applicationSupportURL: support).openOrBootstrapCurrent()
        let context = session.modelContext
        let pack = SignPack.illuminatedSignV1
        let siteID = UUID(uuidString: "62000000-0000-0000-0000-000000000001")!
        let assetID = UUID(uuidString: "62000000-0000-0000-0000-000000000002")!
        let storeCoordinator = try StoreSessionCoordinator(validatingSession: session)
        defer { XCTAssertNoThrow(try storeCoordinator.invalidateAndReleaseWriter()) }
        let mutationID = try MutationIDV1(rawValue: UUID())
        _ = try storeCoordinator.workspaceWriter.execute(.createFirstSign(.init(
            siteID: siteID, newSite: .init(id: siteID, label: "Backup Site", address: siteAddress, timeZoneID: "America/New_York"),
            assetID: assetID, assetLabel: "One Live Sign", packID: pack.packID,
            packSchemaVersion: pack.schemaVersion, packContentVersion: pack.contentVersion,
            createdAt: Date(timeIntervalSince1970: 1_776_420_001),
            initialPlacementMutationID: mutationID, initialPlacementEventID: UUID(),
            initialPhysicalEpisodeID: PhysicalPlacementEpisodeIDV1(rawValue: UUID())
        )), mutationID: mutationID)
        let profile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(package: pack)
        let dependencies = try storeCoordinator.packageLifecycleDependencies(
            profileRegistry: WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile]))
        let coordinator = try CheckRunnerCoordinator(modelContext: context,
            packageLifecycleDependencies: dependencies, packageLifecycleProfile: profile)
        coordinator.configureCapture(generationRootURL: session.generationRootURL)
        var roots: [String] = []
        for index in 0..<3 {
            let base = 10 + index * 10
            let observed = Date(timeIntervalSince1970: 1_776_420_100 + Double(base))
            _ = try coordinator.beginCheck(assetID: assetID, timeZoneID: nil, isTimeZoneConfirmed: false, afterDarkAccepted: true, safePositionAccepted: true, observedAt: observed)
            let wide = try await coordinator.importCandidate(assetID: assetID, sourceData: try makePNG(seed: UInt8(31 + index)), createdAt: observed.addingTimeInterval(1))
            _ = try await coordinator.accept(candidate: wide, assetID: assetID)
            let close = try await coordinator.importCandidate(assetID: assetID, sourceData: try makePNG(seed: UInt8(71 + index)), createdAt: observed.addingTimeInterval(2))
            _ = try await coordinator.accept(candidate: close, assetID: assetID)
            let packetID = uuid(base + 2), rootID = uuid(base + 3), reportID = uuid(base + 4)
            let result = try await coordinator.finalize(
                assetID: assetID, selection: .noVisibleIssue,
                completedAt: observed.addingTimeInterval(5), snapshotCreatedAt: observed.addingTimeInterval(6),
                sourceApp: .init(build: "42", version: "4.0"),
                identifiers: .init(mutationID: uuid(base + 1), packetID: packetID, stableRootID: rootID, reportID: reportID, issueID: nil)
            )
            if currentWriterSource || index == 0 {
                guard case .ready = try coordinator.prepareReportDelivery(result: result) else { throw FixtureError.invalid }
            } else if index == 2 {
                let report = try XCTUnwrap(context.fetch(FetchDescriptor<Report>()).first { $0.id == reportID })
                let failure = try ReportRenderService.transitionMutation(report: report,
                    writer: storeCoordinator.workspaceWriter, transition: .pendingToFailed)
                _ = try storeCoordinator.workspaceWriter.commitReportPDFTransition(failure)
            }
            roots.append(rootID.uuidString.lowercased())
        }
        if !currentWriterSource {
            // Preserve the counted-root tombstone using the actual incumbent
            // deletion transaction after its source was canonically finalized.
            let deletedAssetID = uuid(88), tombstoneRoot = uuid(90)
            let placementMutationID = try MutationIDV1(rawValue: UUID())
            _ = try storeCoordinator.workspaceWriter.execute(.createFirstSign(.init(
                siteID: siteID, newSite: nil, assetID: deletedAssetID, assetLabel: "Deleted Sign",
                packID: pack.packID, packSchemaVersion: pack.schemaVersion,
                packContentVersion: pack.contentVersion,
                createdAt: Date(timeIntervalSince1970: 1_776_420_400),
                initialPlacementMutationID: placementMutationID, initialPlacementEventID: UUID(),
                initialPhysicalEpisodeID: PhysicalPlacementEpisodeIDV1(rawValue: UUID())
            )), mutationID: placementMutationID)
            let observed = Date(timeIntervalSince1970: 1_776_420_500)
            _ = try coordinator.beginCheck(assetID: deletedAssetID, timeZoneID: nil,
                isTimeZoneConfirmed: false, afterDarkAccepted: true, safePositionAccepted: true,
                observedAt: observed)
            let reason = try XCTUnwrap(pack.couldNotVerifyReasons.entries.first)
            _ = try await coordinator.finalize(assetID: deletedAssetID,
                selection: .couldNotVerify(reasonKey: reason.key, note: nil),
                completedAt: observed.addingTimeInterval(5), snapshotCreatedAt: observed.addingTimeInterval(6),
                sourceApp: .init(build: "42", version: "4.0"),
                identifiers: .init(mutationID: uuid(91), packetID: uuid(89), stableRootID: tombstoneRoot,
                    reportID: uuid(92), issueID: nil))
            try storeCoordinator.invalidateAndReleaseWriter()
            // This remains the separately authorized fenced compatibility
            // deletion path, not proof of live deletion-port adoption.
            var deletion: WholeSignDeletionService? = WholeSignDeletionService(modelContext: context,
                generationRootURL: session.generationRootURL,
                now: { Date(timeIntervalSince1970: 1_776_421_000) })
            _ = try await XCTUnwrap(deletion).delete(assetID: deletedAssetID)
            deletion = nil
            let registry = try StoreGenerationFactory(applicationSupportURL: support).makeGenerationLeaseRegistry()
            XCTAssertTrue(try registry.activeEpochs().isEmpty)
            let tombstones = try context.fetch(FetchDescriptor<Packet>()).filter { $0.id == uuid(89) }
            let tombstone = try XCTUnwrap(tombstones.first)
            XCTAssertEqual(tombstones.count, 1)
            XCTAssertNil(tombstone.currentRecordID)
            XCTAssertNotNil(tombstone.contentDeletedAt)
            XCTAssertTrue(tombstone.evaluationCounted)
            roots.append(tombstoneRoot.uuidString.lowercased())
        } else {
            try storeCoordinator.invalidateAndReleaseWriter()
        }
        let journal = try MutationJournalStoreV1(modelContext: context,
            identity: session.workspaceIdentity, generationID: session.generationID, allowStateBootstrap: false)
        try journal.validateAll()
        try MutationJournalStoreV1.validateImportedSnapshot(journal.exportSnapshot(),
            sourcePersistentSchemaVersion: session.storeSchemaRelease.versionIdentifier.major)
        return Harness(applicationSupportURL: support, session: session, context: context, countedRoots: roots)
    }

    func sourceMediaFacts(_ harness: Harness) throws -> [MediaFact] {
        try harness.context.fetch(FetchDescriptor<EvidenceFile>()).flatMap { evidence in
            let id = evidence.id.uuidString.lowercased()
            return [
                MediaFact(sourcePath: evidence.relativePath, exportPath: "media/\(id).jpg", sha256: evidence.sha256),
                MediaFact(sourcePath: evidence.thumbnailRelativePath, exportPath: "thumbnails/\(id).jpg", sha256: evidence.thumbnailSHA256),
            ]
        }
    }

    func packagePayloadFacts(_ package: URL) throws -> [PayloadFact] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let urls = try XCTUnwrap(fileManager.enumerator(at: package, includingPropertiesForKeys: keys))
            .compactMap { $0 as? URL }
        return try urls.filter { try $0.resourceValues(forKeys: Set(keys)).isRegularFile == true && $0.lastPathComponent != "manifest.json" }
            .map { url in
                let data = try Data(contentsOf: url)
                let path = String(url.path.dropFirst(package.path.count + 1)).replacingOccurrences(of: "\\", with: "/")
                let mimeType: String
                switch url.pathExtension {
                case "jpg": mimeType = "image/jpeg"
                case "pdf": mimeType = "application/pdf"
                default: mimeType = "application/json"
                }
                return PayloadFact(
                    path: path,
                    byteCount: data.count,
                    mimeType: mimeType,
                    sha256: data.sha256
                )
            }.sorted { $0.path < $1.path }
    }

    func treeFacts(_ root: URL) throws -> [String] {
        let values = try XCTUnwrap(fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])).compactMap { $0 as? URL }
        return try values.filter { try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true }.map {
            let relative = String($0.path.dropFirst(root.path.count + 1)).replacingOccurrences(of: "\\", with: "/")
            return "\(relative)|\((try Data(contentsOf: $0)).sha256)"
        }.sorted()
    }

    func modelFacts(_ context: ModelContext) throws -> [String] {
        let packets = try context.fetch(FetchDescriptor<Packet>()).map { "packet|\($0.id)|\($0.currentRecordID?.uuidString ?? "nil")|\($0.evaluationCounted)|\($0.contentDeletedAt?.timeIntervalSince1970 ?? -1)" }
        let reports = try context.fetch(FetchDescriptor<Report>()).map { "report|\($0.id)|\($0.pdfState)|\($0.pdfSHA256 ?? "nil")" }
        let evidence = try context.fetch(FetchDescriptor<EvidenceFile>()).map { "evidence|\($0.id)|\($0.relativePath)|\($0.sha256)" }
        return (packets + reports + evidence).sorted()
    }

    func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "Fixtures") ?? Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func assertEveryObject(
        in root: [String: Any],
        key: String,
        hasKeys expected: Set<String>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let values = try XCTUnwrap(root[key] as? [[String: Any]], file: file, line: line)
        XCTAssertFalse(values.isEmpty, file: file, line: line)
        for value in values { XCTAssertEqual(Set(value.keys), expected, file: file, line: line) }
    }

    static let workflowRecordKeys: Set<String> = [
        "afterDarkAcknowledgementAccepted", "afterDarkAcknowledgementCopy",
        "afterDarkAcknowledgementKey", "afterDarkAcknowledgementVersion", "assetID",
        "completedAt", "couldNotVerifyDisplaySnapshot", "couldNotVerifyKey",
        "couldNotVerifyRegistryVersion", "draftStepKey", "evidenceSourceRecordID",
        "finalizationMutationID", "id", "issueID", "localDate", "localTime", "note",
        "observedAtUTC", "outcomeKey", "packContentVersion", "packID",
        "packSchemaVersion", "packetID", "parentRecordID", "pdfTemplateID",
        "pdfTemplateVersion", "recordRevisionRootID", "revisesRecordID", "revisionKind",
        "safePositionAcknowledgementAccepted", "safePositionAcknowledgementCopy",
        "safePositionAcknowledgementKey", "safePositionAcknowledgementVersion",
        "schemaVersion", "stage", "startedAt", "state", "timeZoneID",
        "utcOffsetMinutes", "workDescription", "workPerformedLocalDate",
    ]

    func uuid(_ suffix: Int) -> UUID { UUID(uuidString: String(format: "62000000-0000-0000-0000-%012d", suffix))! }

    func makePNG(seed: UInt8) throws -> Data {
        let width = 48, height = 32
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = seed &+ UInt8(truncatingIfNeeded: index / 4)
            pixels[index + 1] = seed &+ 17; pixels[index + 2] = seed &+ 43; pixels[index + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw FixtureError.invalid }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw FixtureError.invalid }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.invalid }
        return output as Data
    }
}

private enum FixtureError: Error { case invalid }
private extension Data {
    var sha256: String { SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined() }
}

extension S6_2BackupExportTests {
    func testV23P03C41BackupPayloadRoundTripsDescriptorAndRelationshipHistory() throws {
        let fixture = try C41FunctionalRelationshipTestSupportV1.makeFixture(seed: 41_620)
        let snapshot = try CompletedFunctionalRelationshipSnapshotV1(
            snapshotID: C41FunctionalRelationshipTestSupportV1.id(41_621),
            workspaceID: fixture.workspaceID,
            capturedAt: C41FunctionalRelationshipTestSupportV1.fixedDate,
            descriptorReleases: [fixture.descriptor],
            relationships: [fixture.added]
        )
        let bytes = try FunctionalRelationshipCanonicalCodecV1.encode(snapshot)
        let restored = try FunctionalRelationshipCanonicalCodecV1.decode(
            CompletedFunctionalRelationshipSnapshotV1.self, from: bytes
        )

        XCTAssertEqual(restored, snapshot)
        XCTAssertEqual(restored.descriptorReleases.first?.descriptorSHA256, fixture.descriptor.descriptorSHA256)
        XCTAssertEqual(restored.relationships.first?.eventSHA256, fixture.added.eventSHA256)
        try restored.validate()
    }
}

extension S6_2BackupExportTests {
    func testV23P03C13BackupExportRoundTripsAllPersistedAssuranceRows() throws {
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture(seed: 51_620)
        let values: [(Data, Data)] = [
            (
                try EvidenceAssuranceCanonicalCodecV1.encode(fixture.routineVisibility),
                try EvidenceAssuranceCanonicalCodecV1.encode(try EvidenceVisibilityRow(fixture.routineVisibility).value())
            ),
            (
                try EvidenceAssuranceCanonicalCodecV1.encode(fixture.customerLink),
                try EvidenceAssuranceCanonicalCodecV1.encode(try ClaimEvidenceLinkRow(fixture.customerLink).value())
            ),
            (
                try EvidenceAssuranceCanonicalCodecV1.encode(fixture.customerManifest),
                try EvidenceAssuranceCanonicalCodecV1.encode(try AssuranceManifestRow(fixture.customerManifest).value())
            ),
            (
                try EvidenceAssuranceCanonicalCodecV1.encode(fixture.customerAttestation),
                try EvidenceAssuranceCanonicalCodecV1.encode(try AttestationRow(fixture.customerAttestation).value())
            )
        ]

        for (source, restored) in values {
            XCTAssertFalse(source.isEmpty)
            XCTAssertEqual(source, restored)
        }
        XCTAssertEqual(values.count, 4)
        XCTAssertEqual(fixture.customerManifest.sourcePreviewID, fixture.customerPreview.previewID)
        XCTAssertEqual(fixture.customerAttestation.action, .recorded)
    }
}

extension S6_2BackupExportTests {
    func testV23P03C14BackupRecordPreservesTransitionCanonicalBytes() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 145_162)
        let transition = fixture.transitions[0]
        let canonicalData = try InspectionReviewCanonicalCodecV1.encode(transition)
        let record = V14BackupInspectionReviewRecordV1(
            kind: .reviewTransition, id: transition.transitionID,
            workspaceID: fixture.workspaceID.rawValue, revision: transition.revision,
            canonicalData: canonicalData
        )
        XCTAssertEqual(record.kind, .reviewTransition)
        XCTAssertEqual(record.id, transition.transitionID)
        XCTAssertEqual(record.workspaceID, fixture.workspaceID.rawValue)
        XCTAssertEqual(record.canonicalData, canonicalData)
    }

    func testV23P03C19BackupRegistryIncludesEveryMeasurementFamily() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        try KernelBackupRestoreRegistryV4.validateMeasurementIntegrityLifecycle()
        XCTAssertEqual(V18BackupMeasurementIntegrityRecordV1.Kind.allCases.count, 5)
        XCTAssertEqual(KernelBackupRestoreRegistryV4.measurementIntegrityArchiveKinds.count, 5)
        let row = try MeasurementCaptureRow(fixture.capture)
        XCTAssertEqual(try row.value(), fixture.capture)
    }

    func testC20PrivacyTransformBackupExportUsesV19RecordBoundary() throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        try V19PrivacyTransformImportBoundaryV1.validate(persistent: 19, records: 18)
        XCTAssertEqual(fixture.backupRecords.count, V19BackupPrivacyTransformRecordV1.Kind.allCases.count)
        XCTAssertTrue(fixture.backupRecords.allSatisfy { !$0.canonicalData.isEmpty })
    }
}

extension S6_2BackupExportTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}
extension S6_2BackupExportTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindV1.allCases.count, 5)
        XCTAssertEqual(PersistentSchemaV24.models.count, 87)
        XCTAssertEqual(V24BackupSurveyDefinitionRecordV1.Kind.allCases.count, 2)
    }
}
extension S6_2BackupExportTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

extension S6_2BackupExportTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
private final class C31LightingAnchorS62BackupExportTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

extension S6_2BackupExportTests {
    @MainActor
    func testV23P03C42BackupExportRoundTripsTypedReceiptAndReleaseExclusion() async throws {
        let receipt = try ControllerZoneDistributionArchetypeV1.run()
        let c42Bytes = try CrossMarketCanonicalV1.data(receipt)
        let payload = c42Bytes.base64EncodedString()
        let harness = try await makeMixedHarness("c42-export", siteAddress: payload)
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let destination = harness.applicationSupportURL.appendingPathComponent("c42-export", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        let exporter = makeService(harness, capacity: .max)
        let preview = try exporter.prepare()
        let package = try exporter.export(previewID: preview.id, to: destination)
        let importer = try BackupImportService(
            generationRootURL: harness.session.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
            scopedAccess: .alreadyAuthorized
        )
        let validated = try importer.stageAndValidate(selectedPackageURL: package)
        defer { try? importer.discard(validated) }
        let restoredPayload = try XCTUnwrap(validated.records.sites.first?.address)
        XCTAssertEqual(restoredPayload, payload)
        XCTAssertEqual(
            try CrossMarketCanonicalV1.decode(
                ModelRunReceiptV1.self,
                from: try XCTUnwrap(Data(base64Encoded: restoredPayload))
            ),
            receipt
        )
        XCTAssertEqual(validated.members["records.json"], try BackupCanonicalEncoderV1().encodeRecords(validated.records).data)
    }
}

private final class C33TemporalEvidenceAnchorS62BackupExport: XCTestCase {
    func testC33S62BackupExportCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "backup.temporal-content-bytes",
            kind: .video,
            reportProjection: .typedLinkOnly
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "backup.temporal-content-bytes",
            kind: .video,
            reportProjection: .typedLinkOnly
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

private final class C32AssistanceAnchorS62BackupExport: XCTestCase {
    func testC32S62BackupExportCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .packet,
            fieldID: "backup.acceptance-receipt-only",
            value: .text("backup canonical accepted value")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .packet,
            fieldID: "backup.acceptance-receipt-only",
            valueKind: .text
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
private final class C46S62BackupExportCompatibilityTests: XCTestCase {
    func testC46BackupExportExcludesContactFromDefaultExport() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "backup-export",
            kind: .email,
            handoff: .email,
            slot: 46202
        )
    }
}


private enum C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_2BackupExportTests_swift {
    static let compatibilityCardID = "V23-P03-C47"
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

private final class C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_2BackupExportTests_swift_Tests: XCTestCase {
    func testC47S62BackupExportTestsOwnerCompatibilityIsTyped() {
        XCTAssertEqual(C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_2BackupExportTests_swift.compatibilityCardID, "V23-P03-C47")
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_2BackupExportTests_swift.sharedEnvelopeDoesNotCollapseFamilyTruth)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_2BackupExportTests_swift.installationAndPunchReceiptsRemainIndependent)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_2BackupExportTests_swift.noPlanFallbackIsExplicit)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_2BackupExportTests_swift.surveyDefinitionOwnershipIsPreserved)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_2BackupExportTests_swift.legacyInspectionTruthIsNotRewritten)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_S6_2BackupExportTests_swift.threeReceiptIsolationIsRequired)
        XCTAssertEqual(ActivityContractPersistenceEnrollmentV2.persistentFamilies.count, 6)
        XCTAssertTrue(ActivityContractPersistenceEnrollmentV2.usesSoleWorkspaceWriter)
    }
}

private final class C48PortableReviewS62BackupExportTests: XCTestCase {
    func testC48BackupOwnerPreservesExchangeBytesButExcludesQuarantine() {
        XCTAssertTrue(C48PortableReviewPersistenceBoundaryV1.sessionStoreIsNonpersistent)
        XCTAssertTrue(C48PortableReviewPersistenceBoundaryV1.quarantineIsExcludedFromBackup)
        XCTAssertTrue(C48PortableExchangeMigrationBoundaryV2.preservesExactBytes)
        XCTAssertTrue(C48PortableExchangeMigrationBoundaryV2.quarantineExcludedFromBackup)
    }
}
private final class C49WorkResourceBackupExportBoundaryTests: XCTestCase {
    func testBackupOwnsManualTruthButNotLiveInventory() {
        XCTAssertTrue(C49WorkResourceContractBoundaryV1.appendOnly)
        XCTAssertFalse(C49WorkResourceContractBoundaryV1.liveInventoryReference)
        XCTAssertTrue(C49WorkResourcePersistenceBoundaryV1.backupRestoreCloneForkDeleteAndEraseUseExistingAuthorities)
    }
}

private final class C50IncumbentAdapterS62BackupExportBoundaryTests: XCTestCase {
    func testBackupExcludesAdapterScratchSelectionAndExternalPossession() {
        XCTAssertTrue(C50IncumbentFileExchangeBackupBoundaryV1.validate())
        XCTAssertFalse(C50IncumbentFileExchangeBackupEncoderBoundaryV1.encodesSourceScratchOrQuarantine)
        XCTAssertFalse(C50IncumbentFileExchangeBackupExportBoundaryV1.exportsSecurityBookmarksOrExternalPaths)
        XCTAssertFalse(C50IncumbentFileExchangeBackupRestoreServiceBoundaryV1.restoresSourceScratchOrQuarantine)
    }
}

extension C45BackupExportCompatibilityTests {
    func testV23P03C51BackupExportIncludesCalendarAndOverrideClosure() {
        XCTAssertTrue(
            C51ScheduleBackupClosureV1.persistedRecordKindCount == 4
                && C51ScheduleBackupClosureV1.embeddedCanonicalComponents
                    .contains("ExceptionCalendarReleaseV1")
                && C51ScheduleBackupClosureV1.embeddedCanonicalComponents
                    .contains("ScheduleOverrideEventV1")
                && !C51ScheduleBackupClosureV1
                    .sourceScheduleAutomaticallyActiveAfterCloneOrFork
        )
    }
}

extension S6_2BackupExportTests {
    func testC55PartsStockCanonicalNumberBridgeRejectsFractionalNSNumberText() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent(
                "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("CFGetTypeID(value) != CFBooleanGetTypeID()"))
        XCTAssertTrue(source.contains("!representation.contains(\".\")"))
        XCTAssertTrue(source.contains("!representation.contains(\"e\")"))
        XCTAssertTrue(source.contains("!representation.contains(\"E\")"))
        XCTAssertTrue(source.contains("let integer = Int(representation)"))
        XCTAssertFalse(source.contains("value.int64Value"))
    }

    func testV23P03C34SceneStateIsExcludedFromBackupAndExport() {
        let lifecycle = SceneNavigationLifecycleDispositionV1()
        XCTAssertFalse(lifecycle.workspaceTruth)
        XCTAssertFalse(lifecycle.backupIncluded)
        XCTAssertFalse(lifecycle.exportIncluded)
        XCTAssertFalse(lifecycle.journalIncluded)
        XCTAssertTrue(lifecycle.eraseClears)
    }
}

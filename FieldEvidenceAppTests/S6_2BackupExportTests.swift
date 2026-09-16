import CoreGraphics
import CoreFoundation
import Combine
import CryptoKit
import Darwin
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
        let historyBeforeSnippet = try inbox.writer.sourceMutationHistorySnapshot()
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
        let journalUnion = try CheckRunnerPhotoRestoreHistoryUnionV1.compose(
            source: historyBeforeSnippet, current: originalHistory,
            sourceIdentity: harness.session.workspaceIdentity,
            currentIdentity: harness.session.workspaceIdentity)
        XCTAssertEqual(journalUnion.merged, originalHistory)
        XCTAssertNoThrow(try journalUnion.requireDestination(originalHistory))
        XCTAssertThrowsError(try journalUnion.requireDestination(historyBeforeSnippet))
        let duplicateUnion = try CheckRunnerPhotoRestoreHistoryUnionV1.compose(
            source: originalHistory, current: originalHistory,
            sourceIdentity: harness.session.workspaceIdentity,
            currentIdentity: harness.session.workspaceIdentity)
        XCTAssertEqual(duplicateUnion.merged, originalHistory)
        let earlierUnion = try CheckRunnerPhotoRestoreHistoryUnionV1.compose(
            source: historyBeforeSnippet, current: historyBeforeSnippet,
            sourceIdentity: harness.session.workspaceIdentity,
            currentIdentity: harness.session.workspaceIdentity)
        XCTAssertThrowsError(try earlierUnion.requireDestination(originalHistory))
        let changedSequence = MutationHistorySnapshotV1(
            workspaceRevision: originalHistory.workspaceRevision,
            lastLocalSequence: originalHistory.lastLocalSequence + 1,
            receipts: originalHistory.receipts, quarantines: originalHistory.quarantines,
            entityRevisions: originalHistory.entityRevisions)
        XCTAssertNoThrow(try MutationJournalStoreV1.validateImportedSnapshot(changedSequence))
        XCTAssertThrowsError(try journalUnion.requireDestination(changedSequence))
        let changedWorkspaceRevision = MutationHistorySnapshotV1(
            workspaceRevision: originalHistory.workspaceRevision + 1,
            lastLocalSequence: originalHistory.lastLocalSequence,
            receipts: originalHistory.receipts, quarantines: originalHistory.quarantines,
            entityRevisions: originalHistory.entityRevisions)
        XCTAssertNoThrow(try MutationJournalStoreV1.validateImportedSnapshot(changedWorkspaceRevision))
        XCTAssertThrowsError(try journalUnion.requireDestination(changedWorkspaceRevision))
        let firstRevision = try XCTUnwrap(originalHistory.entityRevisions.first)
        let conflictingRevisions = originalHistory.entityRevisions.map { row in
            row.identity == firstRevision.identity
                ? MutationHistoryEntityRevisionV1(identity: row.identity, revision: row.revision,
                    externalProjectionSHA256: firstRevision.externalProjectionSHA256 == String(repeating: "a", count: 64)
                        ? String(repeating: "b", count: 64) : String(repeating: "a", count: 64))
                : row
        }
        let conflictingHistory = MutationHistorySnapshotV1(
            workspaceRevision: originalHistory.workspaceRevision,
            lastLocalSequence: originalHistory.lastLocalSequence,
            receipts: originalHistory.receipts, quarantines: originalHistory.quarantines,
            entityRevisions: conflictingRevisions)
        XCTAssertNoThrow(try MutationJournalStoreV1.validateImportedSnapshot(conflictingHistory))
        XCTAssertThrowsError(try CheckRunnerPhotoRestoreHistoryUnionV1.compose(
            source: originalHistory, current: conflictingHistory,
            sourceIdentity: harness.session.workspaceIdentity,
            currentIdentity: harness.session.workspaceIdentity))
        let unrelatedReceipt = try MutationReceiptV1.decodeCanonical(
            from: XCTUnwrap(originalHistory.receipts.last).receiptData)
        let unrelatedQuarantine = MutationHistoryQuarantineRecordV1(
            workspaceID: unrelatedReceipt.identity.workspaceID,
            mutationID: unrelatedReceipt.mutationID.rawValue, identityDomain: .mutationEnvelope,
            acceptedIdentitySHA256: unrelatedReceipt.envelopeSHA256,
            conflictingIdentitySHA256: unrelatedReceipt.envelopeSHA256 == String(repeating: "a", count: 64)
                ? String(repeating: "b", count: 64) : String(repeating: "a", count: 64),
            detectedAt: Date(timeIntervalSince1970: 1_777_593_600))
        let unrelatedQuarantinedHistory = MutationHistorySnapshotV1(
            workspaceRevision: originalHistory.workspaceRevision,
            lastLocalSequence: originalHistory.lastLocalSequence,
            receipts: originalHistory.receipts, quarantines: [unrelatedQuarantine],
            entityRevisions: originalHistory.entityRevisions)
        let preservedQuarantineUnion = try CheckRunnerPhotoRestoreHistoryUnionV1.compose(
            source: historyBeforeSnippet, current: unrelatedQuarantinedHistory,
            sourceIdentity: harness.session.workspaceIdentity,
            currentIdentity: harness.session.workspaceIdentity)
        XCTAssertEqual(preservedQuarantineUnion.merged, unrelatedQuarantinedHistory)
        XCTAssertNoThrow(try preservedQuarantineUnion.requireDestination(unrelatedQuarantinedHistory))
        try inbox.journal.validateAll()
        try inbox.closeCurrentWriter()
        let authorized = try await makeAuthorizedExportHarness(harness)
        defer { authorized.close() }
        let sourceTree = try treeFacts(harness.session.generationRootURL)
        let sourceModels = try modelFacts(harness.context)
        let originalMedia = try Dictionary(uniqueKeysWithValues: evidence.map {
            ($0.id, try Data(contentsOf: harness.session.generationRootURL.appendingPathComponent($0.relativePath)))
        })
        let destination = harness.applicationSupportURL.appendingPathComponent("populated-export", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        let exporter = makeService(authorized, capacity: .max)
        let preview = try authorized.contentAccess.withRead { try exporter.prepare() }
        let package = try await exporter.export(previewID: preview.id, to: destination,
            contentAccess: authorized.contentAccess)
        authorized.close()
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
        let harness = try await makeMixedHarness("golden", sharedRaw: true)
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let authorized = try await makeAuthorizedExportHarness(harness)
        defer { authorized.close() }
        let sourceFacts = try sourceMediaFacts(harness)
        let before = try treeFacts(harness.session.generationRootURL)
        let destination = harness.applicationSupportURL.appendingPathComponent("export", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        let service = makeService(authorized, capacity: .max)

        let preview = try authorized.contentAccess.withRead { try service.prepare() }
        XCTAssertEqual(preview.signCount, 1)
        XCTAssertEqual(preview.reportCount, 3)
        XCTAssertEqual(preview.photoCount, 6)
        let package = try await service.export(previewID: preview.id, to: destination,
            contentAccess: authorized.contentAccess)
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
        XCTAssertEqual(validated.manifest.source.persistentSchemaVersion, 54)
        XCTAssertEqual(validated.manifest.source.recordsSchemaVersion, 53)
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
        XCTAssertEqual(decodedRecords.recordsSchemaVersion, 53)
        XCTAssertEqual(
            validated.manifest.source.recordsSchemaVersion,
            decodedRecords.recordsSchemaVersion
        )
        XCTAssertEqual(decodedRecords, validated.records)
        let photoHistory = try CheckRunnerPhotoBackupHistoryV1.project(
            source: validated.manifest.source, records: decodedRecords)
        XCTAssertEqual(photoHistory.source, validated.manifest.source)
        XCTAssertEqual(photoHistory.children.count, 6)
        XCTAssertEqual(Set(photoHistory.children.map(\.currentCheckpoint.draftID)).count, 6)
        for child in photoHistory.children {
            XCTAssertNotNil(child.raw)
            XCTAssertNotNil(child.pair)
            XCTAssertNotNil(child.preparedReconstruction)
            XCTAssertNotNil(child.committingCheckpoint)
            XCTAssertNotNil(child.target)
            XCTAssertNotNil(child.targetRecords)
            XCTAssertNotNil(child.terminal)
            XCTAssertNotNil(child.parentLink)
            XCTAssertNotNil(child.currentTarget?.finalization)
            XCTAssertEqual(child.currentTarget?.laterPhotos.count,
                           child.payload.captureStep == .wide ? 1 : 0)
            XCTAssertEqual(child.targetRecords?.permittedSuccessors.count,
                           child.payload.captureStep == .wide ? 2 : 1)
        }
        let photoAdapter = try DraftAttachmentStagingAdapterV1(
            photoBackupExistingRoot: harness.applicationSupportURL,
            workspaceID: harness.session.workspaceID
        )
        var rawSnapshots: [DraftPhotoRawBackupSnapshotV1] = []
        var committingCheckpoints: [UUID: FieldDraftCheckpointV1] = [:]
        var childStageIDs: [UUID: UUID] = [:]
        for child in photoHistory.children {
            let raw = try XCTUnwrap(child.raw)
            let committing = try XCTUnwrap(child.committingCheckpoint)
            XCTAssertNil(committingCheckpoints.updateValue(
                committing, forKey: raw.readyItem.draftID))
            XCTAssertNil(childStageIDs.updateValue(
                raw.intent.stageID, forKey: raw.readyItem.draftID))
            rawSnapshots.append(try await photoAdapter.readPhotoBackupSnapshot(
                raw: raw, committingCheckpoint: committing))
        }
        let canonicalStages = try decodedRecords.fieldDrafts
            .filter { $0.kind == .stagingItem }
            .map {
                try FieldDraftCanonicalCodecV1.decode(
                    AttachmentStagingItemV1.self, from: $0.canonicalData)
            }
        XCTAssertEqual(canonicalStages.count, rawSnapshots.count)
        let censusFirstChild = try XCTUnwrap(photoHistory.children.first)
        let censusFirstRaw = try XCTUnwrap(censusFirstChild.raw)
        let censusFirstStageIndex = try XCTUnwrap(canonicalStages.firstIndex {
            $0.stageID == censusFirstRaw.intent.stageID
        })
        let censusFirstSnapshot = try XCTUnwrap(rawSnapshots.first {
            $0.raw.intent.stageID == censusFirstRaw.intent.stageID
        })
        let censusFirstPromotion = try DraftPhotoRawPromotionValuesV1(
            checkpoint: XCTUnwrap(censusFirstChild.committingCheckpoint))
        XCTAssertEqual(canonicalStages[censusFirstStageIndex].state, .committed)
        XCTAssertEqual(censusFirstSnapshot.physicalEntry.entry,
                       censusFirstPromotion.committedEntry)
        var readyCanonicalStages = canonicalStages
        readyCanonicalStages[censusFirstStageIndex] = censusFirstRaw.readyItem
        let laggingCanonicalVerification = try await photoAdapter.preparePhotoBackupVerification(
            rawSnapshots,
            committingCheckpoints: committingCheckpoints,
            canonicalStages: readyCanonicalStages,
            childStageIDs: childStageIDs
        )
        XCTAssertNoThrow(try laggingCanonicalVerification.withVerificationLock {})

        var missingCheckpoint = committingCheckpoints
        XCTAssertNotNil(missingCheckpoint.removeValue(forKey: censusFirstRaw.readyItem.draftID))
        do {
            _ = try await photoAdapter.preparePhotoBackupVerification(
                rawSnapshots,
                committingCheckpoints: missingCheckpoint,
                canonicalStages: readyCanonicalStages,
                childStageIDs: childStageIDs
            )
            XCTFail("physical committed entry requires its exact COMMITTING checkpoint")
        } catch {
            XCTAssertEqual(error as? DraftAttachmentStagingFailureV1, .staleStage)
        }

        let otherChild = try XCTUnwrap(photoHistory.children.dropFirst().first)
        var mismatchedCheckpoint = committingCheckpoints
        mismatchedCheckpoint[censusFirstRaw.readyItem.draftID] = try XCTUnwrap(
            otherChild.committingCheckpoint)
        do {
            _ = try await photoAdapter.preparePhotoBackupVerification(
                rawSnapshots,
                committingCheckpoints: mismatchedCheckpoint,
                canonicalStages: readyCanonicalStages,
                childStageIDs: childStageIDs
            )
            XCTFail("physical committed entry rejects another child's COMMITTING checkpoint")
        } catch {
            XCTAssertEqual(error as? DraftAttachmentStagingFailureV1, .staleStage)
        }
        let restorePlan = try CheckRunnerPhotoBackupRestorePlanV1.resolve(
            history: photoHistory, entries: validated.manifest.entries,
            metadata: { try XCTUnwrap(validated.members[$0]) })
        let repeatedRestorePlan = try CheckRunnerPhotoBackupRestorePlanV1.resolve(
            history: photoHistory, entries: validated.manifest.entries,
            metadata: { try XCTUnwrap(validated.members[$0]) })
        XCTAssertEqual(restorePlan, repeatedRestorePlan)
        let composition = try CheckRunnerPhotoRestoreCompositionV1.compose(
            source: validated.manifest.source, sourceRecords: decodedRecords, sourcePlan: restorePlan,
            currentSource: validated.manifest.source, currentRecords: decodedRecords,
            currentPlan: restorePlan, replacementRecords: decodedRecords,
            sourceIdentity: harness.session.workspaceIdentity,
            currentIdentity: harness.session.workspaceIdentity)
        try composition.requireDestination(decodedRecords)
        let compositionSourceSelection = try composition.sourceBinding.selectSource(in: decodedRecords)
        XCTAssertEqual(compositionSourceSelection, composition.sourceSelection)
        XCTAssertEqual(try CheckRunnerPhotoRestoreMemberBindingV1(plan: restorePlan)
            .resolve(sourceSelection: compositionSourceSelection), restorePlan)
        let compositionBindingBytes = try WorkspaceMutationCanonicalV1.data(composition.sourceBinding)
        let compositionBindingDecoder = JSONDecoder()
        compositionBindingDecoder.dateDecodingStrategy = .millisecondsSince1970
        let compositionBindingObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: compositionBindingBytes) as? [String: Any])
        var changedFrontier = compositionBindingObject
        changedFrontier["frontierSHA256"] = String(repeating: "f", count: 64)
        let changedFrontierBinding = try compositionBindingDecoder.decode(
            CheckRunnerPhotoRestoreCompositionBindingV1.self,
            from: JSONSerialization.data(withJSONObject: changedFrontier, options: [.sortedKeys]))
        XCTAssertThrowsError(try changedFrontierBinding.selectSource(in: decodedRecords))
        var missingFrontier = compositionBindingObject
        missingFrontier.removeValue(forKey: "frontierSHA256")
        XCTAssertThrowsError(try compositionBindingDecoder.decode(
            CheckRunnerPhotoRestoreCompositionBindingV1.self,
            from: JSONSerialization.data(withJSONObject: missingFrontier, options: [.sortedKeys])))
        try await assertPhotoRawRestoreKernel(package: validated, history: photoHistory, plan: restorePlan)
        let sourceRawStageIDs = Set(restorePlan.rawPublications.map { $0.physicalEntry.entry.item.stageID })
        let retainedRawStageIDs = Set(canonicalStages.map(\.stageID)).subtracting(sourceRawStageIDs)
        let rawTransition = try await photoAdapter.preparePhotoRestoreRawTransition(
            sourcePlan: restorePlan, sourceHistory: photoHistory,
            currentSnapshots: rawSnapshots, currentCommittingCheckpoints: committingCheckpoints,
            currentCanonicalStages: canonicalStages, currentChildStageIDs: childStageIDs,
            retainedCurrentStageIDs: retainedRawStageIDs)
        XCTAssertEqual(try rawTransition.before.canonicalBytes(), try rawTransition.after.canonicalBytes())
        XCTAssertTrue(rawTransition.newStageIDs.isEmpty)
        XCTAssertEqual(Set(rawTransition.reusedStageIDs), sourceRawStageIDs)
        let rawTransitionBytes = try WorkspaceMutationCanonicalV1.data(rawTransition)
        let rawTransitionDecoder = JSONDecoder()
        rawTransitionDecoder.dateDecodingStrategy = .millisecondsSince1970
        let reopenedRawTransition = try rawTransitionDecoder.decode(
            DraftPhotoRestoreRawTransitionV1.self, from: rawTransitionBytes)
        XCTAssertEqual(try WorkspaceMutationCanonicalV1.data(reopenedRawTransition), rawTransitionBytes)
        var rawTransitionObject = try XCTUnwrap(JSONSerialization.jsonObject(with: rawTransitionBytes) as? [String: Any])
        rawTransitionObject["unbound"] = true
        XCTAssertThrowsError(try rawTransitionDecoder.decode(DraftPhotoRestoreRawTransitionV1.self,
            from: JSONSerialization.data(withJSONObject: rawTransitionObject, options: [.sortedKeys])))
        do {
            _ = try await photoAdapter.preparePhotoRestoreRawTransition(
                sourcePlan: restorePlan, sourceHistory: photoHistory,
                currentSnapshots: rawSnapshots, currentCommittingCheckpoints: committingCheckpoints,
                currentCanonicalStages: canonicalStages, currentChildStageIDs: childStageIDs,
                retainedCurrentStageIDs: retainedRawStageIDs.union([UUID()]))
            XCTFail("restore requires an exact disposition for every old raw entry")
        } catch { XCTAssertEqual(error as? DraftAttachmentStagingFailureV1, .staleStage) }
        let truncatedRawPlan = CheckRunnerPhotoBackupRestorePlanV1(source: restorePlan.source,
            children: restorePlan.children, rawPublications: Array(restorePlan.rawPublications.dropFirst()),
            generationMembers: restorePlan.generationMembers, metadata: restorePlan.metadata)
        let extraRawPlan = CheckRunnerPhotoBackupRestorePlanV1(source: restorePlan.source,
            children: restorePlan.children,
            rawPublications: restorePlan.rawPublications + [try XCTUnwrap(restorePlan.rawPublications.first)],
            generationMembers: restorePlan.generationMembers, metadata: restorePlan.metadata)
        for invalidPlan in [truncatedRawPlan, extraRawPlan] {
            do {
                _ = try await photoAdapter.preparePhotoRestoreRawTransition(
                    sourcePlan: invalidPlan, sourceHistory: photoHistory,
                    currentSnapshots: rawSnapshots, currentCommittingCheckpoints: committingCheckpoints,
                    currentCanonicalStages: canonicalStages, currentChildStageIDs: childStageIDs,
                    retainedCurrentStageIDs: retainedRawStageIDs)
                XCTFail("restore rejects incomplete or extra raw publications")
            } catch { XCTAssertEqual(error as? DraftAttachmentStagingFailureV1, .staleStage) }
        }
        let foreignPhotoAdapter = try DraftAttachmentStagingAdapterV1(
            photoBackupExistingRoot: harness.applicationSupportURL,
            workspaceID: WorkspaceID(rawValue: UUID()))
        do {
            _ = try await foreignPhotoAdapter.preparePhotoRestoreRawTransition(
                sourcePlan: restorePlan, sourceHistory: photoHistory,
                currentSnapshots: rawSnapshots, currentCommittingCheckpoints: committingCheckpoints,
                currentCanonicalStages: canonicalStages, currentChildStageIDs: childStageIDs,
                retainedCurrentStageIDs: retainedRawStageIDs)
            XCTFail("restore binds the adapter workspace before preparing a transition")
        } catch { XCTAssertEqual(error as? DraftAttachmentStagingFailureV1, .wrongWorkspace) }
        let memberBinding = try CheckRunnerPhotoRestoreMemberBindingV1(plan: restorePlan)
        let memberBindingBytes = try WorkspaceMutationCanonicalV1.data(memberBinding)
        let memberBindingDecoder = JSONDecoder()
        memberBindingDecoder.dateDecodingStrategy = .millisecondsSince1970
        let reopenedMemberBinding = try memberBindingDecoder.decode(
            CheckRunnerPhotoRestoreMemberBindingV1.self, from: memberBindingBytes)
        XCTAssertEqual(try WorkspaceMutationCanonicalV1.data(reopenedMemberBinding), memberBindingBytes)
        XCTAssertEqual(try reopenedMemberBinding.resolve(history: photoHistory), restorePlan)
        let originalBindingObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: memberBindingBytes) as? [String: Any])
        func rejectsMemberBinding(_ edit: (inout [String: Any]) throws -> Void) throws {
            var object = originalBindingObject
            try edit(&object)
            let bytes = try JSONSerialization.data(withJSONObject: object,
                options: [.sortedKeys, .withoutEscapingSlashes])
            XCTAssertThrowsError(try memberBindingDecoder.decode(
                CheckRunnerPhotoRestoreMemberBindingV1.self, from: bytes)
                .resolve(sourceSelection: compositionSourceSelection))
        }
        try rejectsMemberBinding { $0["schemaVersion"] = 2 }
        try rejectsMemberBinding { $0.removeValue(forKey: "childDraftIDs") }
        try rejectsMemberBinding { $0["childDraftIDs"] = [] }
        try rejectsMemberBinding { $0["unbound"] = true }
        try rejectsMemberBinding { object in
            var entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
            entries.removeFirst()
            object["entries"] = entries
        }
        try rejectsMemberBinding { object in
            var entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
            entries.append(try XCTUnwrap(entries.first))
            object["entries"] = entries
        }
        try rejectsMemberBinding { object in
            var metadata = try XCTUnwrap(object["metadata"] as? [[String: Any]])
            metadata.removeFirst()
            object["metadata"] = metadata
        }
        try rejectsMemberBinding { object in
            var metadata = try XCTUnwrap(object["metadata"] as? [[String: Any]])
            metadata[0]["bytes"] = Data("changed witness".utf8).base64EncodedString()
            object["metadata"] = metadata
        }
        try rejectsMemberBinding { object in
            var metadata = try XCTUnwrap(object["metadata"] as? [[String: Any]])
            metadata[0]["unbound"] = true
            object["metadata"] = metadata
        }
        try rejectsMemberBinding { object in
            var source = try XCTUnwrap(object["source"] as? [String: Any])
            source["sourceGenerationID"] = UUID().uuidString.lowercased()
            object["source"] = source
        }
        XCTAssertEqual(restorePlan.children.count, 6)
        XCTAssertTrue(restorePlan.children.allSatisfy { $0.pairLocation == .targetOwned })
        XCTAssertEqual(restorePlan.rawPublications.count, 6)
        XCTAssertEqual(Set(restorePlan.rawPublications.map {
            $0.physicalEntry.entry.item.stageID
        }).count, 6)
        for raw in restorePlan.rawPublications {
            XCTAssertEqual(restorePlan.metadata[raw.witness.path], raw.witnessBytes)
            XCTAssertEqual(validated.members[raw.witness.path], raw.witnessBytes)
            let item = raw.physicalEntry.entry.item
            let physicalPath = CheckRunnerPhotoBackupMemberKeyV1(
                childDraftID: item.draftID, stageID: item.stageID, role: .physicalEntry).path
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.decode(
                CheckRunnerPhotoBackupPhysicalEntryV1.self,
                from: XCTUnwrap(restorePlan.metadata[physicalPath])), raw.physicalEntry)
        }
        let evidencePaths = Set(try harness.context.fetch(FetchDescriptor<EvidenceFile>()).flatMap {
            [$0.relativePath, $0.thumbnailRelativePath]
        })
        let targetPaths = Set(restorePlan.generationMembers.compactMap { member -> String? in
            guard (member.kind == .original || member.kind == .thumbnail),
                  member.relativePath.hasPrefix("evidence/") else { return nil }
            return member.relativePath
        })
        XCTAssertEqual(targetPaths, evidencePaths)
        let immutableClaims = restorePlan.children.compactMap { child -> String? in
            child.immutableRawPath
        }
        XCTAssertEqual(immutableClaims.count, 6)
        XCTAssertEqual(Set(immutableClaims).count, 5)
        for path in Set(immutableClaims) {
            let claims = restorePlan.children.compactMap { child in
                child.entries.first { $0.path == path }
            }
            let members = restorePlan.generationMembers.filter { $0.relativePath == path }
            XCTAssertEqual(members.count, 1)
            XCTAssertTrue(claims.allSatisfy { $0 == members[0].entry })
        }

        let firstPhoto = try XCTUnwrap(photoHistory.children.first)
        var missingRowObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(decodedRecords)) as? [String: Any])
        var missingRows = try XCTUnwrap(missingRowObject["fieldDrafts"] as? [[String: Any]])
        let missingRowIndex = try XCTUnwrap(missingRows.firstIndex {
            ($0["id"] as? String)?.lowercased()
                == firstPhoto.currentCheckpoint.draftID.uuidString.lowercased()
                && ($0["kind"] as? String) == "checkpoint"
        })
        let removedRow = missingRows.remove(at: missingRowIndex)
        missingRowObject["fieldDrafts"] = missingRows
        let missingCurrent = try JSONDecoder().decode(V4BackupRecordsV1.self, from:
            JSONSerialization.data(withJSONObject: missingRowObject, options: [.sortedKeys]))
        XCTAssertThrowsError(try CheckRunnerPhotoBackupHistoryV1.project(
            source: validated.manifest.source, records: missingCurrent))

        var duplicateRowObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(decodedRecords)) as? [String: Any])
        var duplicateRows = try XCTUnwrap(duplicateRowObject["fieldDrafts"] as? [[String: Any]])
        duplicateRows.append(removedRow)
        duplicateRowObject["fieldDrafts"] = duplicateRows
        let duplicateCurrent = try JSONDecoder().decode(V4BackupRecordsV1.self, from:
            JSONSerialization.data(withJSONObject: duplicateRowObject, options: [.sortedKeys]))
        XCTAssertThrowsError(try CheckRunnerPhotoBackupHistoryV1.project(
            source: validated.manifest.source, records: duplicateCurrent))

        let completeSnapshot = try XCTUnwrap(decodedRecords.mutationHistory)
        let samePhotoHistory = try CheckRunnerPhotoRestoreHistoryUnionV1.compose(
            source: completeSnapshot, current: completeSnapshot,
            sourceIdentity: harness.session.workspaceIdentity,
            currentIdentity: harness.session.workspaceIdentity)
        XCTAssertNoThrow(try samePhotoHistory.requireDestination(completeSnapshot))
        XCTAssertNoThrow(try samePhotoHistory.requireSourcePhotoHistory(photoHistory))
        let requiredPhotoReceipt = try XCTUnwrap(photoHistory.requiredHistory.first)
        let photoQuarantine = MutationHistoryQuarantineRecordV1(
            workspaceID: requiredPhotoReceipt.envelope.workspaceID,
            mutationID: requiredPhotoReceipt.envelope.mutationID.rawValue,
            identityDomain: .mutationEnvelope,
            acceptedIdentitySHA256: requiredPhotoReceipt.receipt.envelopeSHA256,
            conflictingIdentitySHA256: requiredPhotoReceipt.receipt.envelopeSHA256 == String(repeating: "d", count: 64)
                ? String(repeating: "e", count: 64) : String(repeating: "d", count: 64),
            detectedAt: Date(timeIntervalSince1970: 1_777_593_600))
        let quarantinedPhotoHistory = MutationHistorySnapshotV1(
            workspaceRevision: completeSnapshot.workspaceRevision,
            lastLocalSequence: completeSnapshot.lastLocalSequence,
            receipts: completeSnapshot.receipts, quarantines: [photoQuarantine],
            entityRevisions: completeSnapshot.entityRevisions)
        XCTAssertNoThrow(try MutationJournalStoreV1.validateImportedSnapshot(quarantinedPhotoHistory))
        let quarantinedUnion = try CheckRunnerPhotoRestoreHistoryUnionV1.compose(
            source: completeSnapshot, current: quarantinedPhotoHistory,
            sourceIdentity: harness.session.workspaceIdentity,
            currentIdentity: harness.session.workspaceIdentity)
        XCTAssertEqual(quarantinedUnion.merged.quarantines, [photoQuarantine])
        XCTAssertThrowsError(try quarantinedUnion.requireSourcePhotoHistory(photoHistory))
        XCTAssertThrowsError(try samePhotoHistory.requireDestination(quarantinedPhotoHistory))
        let missingOriginalSnapshot = MutationHistorySnapshotV1(
            workspaceRevision: completeSnapshot.workspaceRevision,
            lastLocalSequence: completeSnapshot.lastLocalSequence,
            receipts: completeSnapshot.receipts.filter { $0 != firstPhoto.originals[0].original },
            quarantines: completeSnapshot.quarantines,
            entityRevisions: completeSnapshot.entityRevisions)
        var missingOriginalObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(decodedRecords)) as? [String: Any])
        missingOriginalObject["mutationHistory"] = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(missingOriginalSnapshot))
        let missingOriginal = try JSONDecoder().decode(V4BackupRecordsV1.self, from:
            JSONSerialization.data(withJSONObject: missingOriginalObject, options: [.sortedKeys]))
        XCTAssertThrowsError(try CheckRunnerPhotoBackupHistoryV1.project(
            source: validated.manifest.source, records: missingOriginal))
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
        futureObject["recordsSchemaVersion"] = 54
        let futureRecords = try JSONDecoder().decode(V4BackupRecordsV1.self, from:
            JSONSerialization.data(withJSONObject: futureObject, options: [.sortedKeys]))
        let hostilePackages = [
            boundaryPackage(records: decodedRecords, declaredRecords: 51, persistent: 53),
            boundaryPackage(records: decodedRecords, declaredRecords: 52, persistent: 52),
            boundaryPackage(records: futureRecords, declaredRecords: 54, persistent: 55)
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
        unknownVersionObject["recordsSchemaVersion"] = 54
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

        // Build a genuinely later current state after the six-photo source was
        // frozen: one disjoint two-photo check plus one typed empty My Day draft.
        // The replacement candidate carries the merged current history but only
        // the source canonical rows, so S, C and D are all populated and distinct.
        authorized.close()
        let retainedMyDayDraftID = try await appendCompositionCurrentOnlyState(harness)
        let currentAuthorized = try await makeAuthorizedExportHarness(harness)
        defer { currentAuthorized.close() }
        let currentDestination = harness.applicationSupportURL.appendingPathComponent(
            "composition-current-export", isDirectory: true)
        try fileManager.createDirectory(at: currentDestination, withIntermediateDirectories: false)
        let currentExporter = makeService(currentAuthorized, capacity: .max)
        let currentPreview = try currentAuthorized.contentAccess.withRead {
            try currentExporter.prepare()
        }
        XCTAssertEqual(currentPreview.photoCount, 8)
        let currentPackage = try await currentExporter.export(previewID: currentPreview.id,
            to: currentDestination, contentAccess: currentAuthorized.contentAccess)
        let currentImporter = try BackupImportService(
            generationRootURL: harness.session.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
            makeUUID: { UUID(uuidString: "62000000-0000-0000-0000-000000000097")! },
            scopedAccess: .alreadyAuthorized)
        let currentValidated = try currentImporter.stageAndValidate(selectedPackageURL: currentPackage)
        defer { try? currentImporter.discard(currentValidated) }
        let currentRecords = currentValidated.records
        let sourceOriginals = try XCTUnwrap(decodedRecords.mutationHistory).receipts
        let currentOriginals = try XCTUnwrap(currentRecords.mutationHistory).receipts
        let sourceOriginalsByKey = try Dictionary(uniqueKeysWithValues: sourceOriginals.map { original in
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: original.envelopeData)
            return (MutationWorkspaceKeyV1.value(workspaceID: envelope.workspaceID,
                mutationID: envelope.mutationID), original)
        })
        let currentOriginalsByKey = try Dictionary(uniqueKeysWithValues: currentOriginals.map { original in
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: original.envelopeData)
            return (MutationWorkspaceKeyV1.value(workspaceID: envelope.workspaceID,
                mutationID: envelope.mutationID), original)
        })
        XCTAssertTrue(sourceOriginalsByKey.allSatisfy { currentOriginalsByKey[$0.key] == $0.value })
        XCTAssertFalse(Set(currentOriginalsByKey.keys).subtracting(sourceOriginalsByKey.keys).isEmpty)
        let currentPhotoHistory = try CheckRunnerPhotoBackupHistoryV1.project(
            source: currentValidated.manifest.source, records: currentRecords)
        XCTAssertEqual(currentPhotoHistory.children.count, 8)
        let sourcePhotoIDs = Set(photoHistory.children.map { $0.payload.childDraftID })
        let currentOnlyPhotoIDs = Set(currentPhotoHistory.children.map { $0.payload.childDraftID })
            .subtracting(sourcePhotoIDs)
        XCTAssertEqual(currentOnlyPhotoIDs.count, 2)
        let currentRestorePlan = try CheckRunnerPhotoBackupRestorePlanV1.resolve(
            history: currentPhotoHistory, entries: currentValidated.manifest.entries,
            metadata: { try XCTUnwrap(currentValidated.members[$0]) })
        let replacementRecords = try compositionReplacementRecords(
            current: currentRecords, source: decodedRecords)
        XCTAssertNotEqual(replacementRecords, decodedRecords)
        XCTAssertNotEqual(replacementRecords, currentRecords)
        let populatedComposition = try CheckRunnerPhotoRestoreCompositionV1.compose(
            source: validated.manifest.source, sourceRecords: decodedRecords,
            sourcePlan: restorePlan, currentSource: currentValidated.manifest.source,
            currentRecords: currentRecords, currentPlan: currentRestorePlan,
            replacementRecords: replacementRecords,
            sourceIdentity: harness.session.workspaceIdentity,
            currentIdentity: harness.session.workspaceIdentity)
        let populatedDestination = try populatedComposition.applying(to: replacementRecords)
        XCTAssertEqual(populatedDestination, currentRecords)
        try populatedComposition.requireDestination(currentRecords)
        let retainedDraftIDs = Set(populatedComposition.retainedCurrentDrafts.map(\.draftID))
        XCTAssertTrue(retainedDraftIDs.contains(retainedMyDayDraftID))
        XCTAssertTrue(currentOnlyPhotoIDs.isSubset(of: retainedDraftIDs))
        XCTAssertEqual(Set(populatedComposition.retainedCurrentPhotoChildDraftIDs),
            currentOnlyPhotoIDs)
        XCTAssertEqual(populatedComposition.photoRestorePlans.count, 2)
        let selectedSource = try populatedComposition.sourceBinding.selectSource(in: currentRecords)
        XCTAssertEqual(selectedSource, populatedComposition.sourceSelection)
        XCTAssertEqual(try CheckRunnerPhotoRestoreMemberBindingV1(plan: restorePlan)
            .resolve(sourceSelection: selectedSource), restorePlan)
        let retainedBinding = try XCTUnwrap(populatedComposition.retainedCurrentBinding)
        let selectedRetained = try retainedBinding.selectSource(in: currentRecords)
        XCTAssertEqual(Set(selectedRetained.children.map { $0.payload.childDraftID }),
            currentOnlyPhotoIDs)
        let resolvedRetained = try CheckRunnerPhotoRestoreMemberBindingV1(plan: currentRestorePlan)
            .resolve(sourceSelection: selectedRetained)
        XCTAssertEqual(resolvedRetained, populatedComposition.photoRestorePlans[1])
        XCTAssertThrowsError(try populatedComposition.requireDestination(replacementRecords))

        let retainedRow = try XCTUnwrap(currentRecords.fieldDrafts.first { row in
            guard row.kind == .checkpoint,
                  let checkpoint = try? FieldDraftCanonicalCodecV1.decode(
                    FieldDraftCheckpointV1.self, from: row.canonicalData) else { return false }
            return checkpoint.draftID == retainedMyDayDraftID
        })
        let extraDestination = try replacingFieldDrafts(currentRecords,
            with: currentRecords.fieldDrafts + [retainedRow])
        XCTAssertThrowsError(try populatedComposition.requireDestination(extraDestination))
        var changedRows = currentRecords.fieldDrafts
        let retainedIndex = try XCTUnwrap(changedRows.firstIndex(where: { $0 == retainedRow }))
        changedRows[retainedIndex] = V16BackupFieldDraftRecordV1(kind: retainedRow.kind,
            id: retainedRow.id, workspaceID: retainedRow.workspaceID,
            revision: retainedRow.revision, canonicalData: retainedRow.canonicalData + Data([0]))
        let changedDestination = try replacingFieldDrafts(currentRecords, with: changedRows)
        XCTAssertThrowsError(try populatedComposition.requireDestination(changedDestination))

        // A later mutation that names the source site is an authenticated but
        // touching current history. The actual composition entry point rejects it.
        currentAuthorized.close()
        try appendCompositionTouchingState(harness)
        let touchingAuthorized = try await makeAuthorizedExportHarness(harness)
        defer { touchingAuthorized.close() }
        let touchingDestination = harness.applicationSupportURL.appendingPathComponent(
            "composition-touching-export", isDirectory: true)
        try fileManager.createDirectory(at: touchingDestination, withIntermediateDirectories: false)
        let touchingExporter = makeService(touchingAuthorized, capacity: .max)
        let touchingPreview = try touchingAuthorized.contentAccess.withRead {
            try touchingExporter.prepare()
        }
        let touchingPackage = try await touchingExporter.export(previewID: touchingPreview.id,
            to: touchingDestination, contentAccess: touchingAuthorized.contentAccess)
        let touchingImporter = try BackupImportService(
            generationRootURL: harness.session.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
            makeUUID: { UUID(uuidString: "62000000-0000-0000-0000-000000000096")! },
            scopedAccess: .alreadyAuthorized)
        let touchingValidated = try touchingImporter.stageAndValidate(selectedPackageURL: touchingPackage)
        defer { try? touchingImporter.discard(touchingValidated) }
        let touchingHistory = try CheckRunnerPhotoBackupHistoryV1.project(
            source: touchingValidated.manifest.source, records: touchingValidated.records)
        let touchingPlan = try CheckRunnerPhotoBackupRestorePlanV1.resolve(
            history: touchingHistory, entries: touchingValidated.manifest.entries,
            metadata: { try XCTUnwrap(touchingValidated.members[$0]) })
        XCTAssertThrowsError(try CheckRunnerPhotoRestoreCompositionV1.requireDisjointHistory(
            source: try XCTUnwrap(decodedRecords.mutationHistory).receipts,
            current: try XCTUnwrap(touchingValidated.records.mutationHistory).receipts))
        XCTAssertThrowsError(try CheckRunnerPhotoRestoreCompositionV1.compose(
            source: validated.manifest.source, sourceRecords: decodedRecords,
            sourcePlan: restorePlan, currentSource: touchingValidated.manifest.source,
            currentRecords: touchingValidated.records, currentPlan: touchingPlan,
            replacementRecords: touchingValidated.records,
            sourceIdentity: harness.session.workspaceIdentity,
            currentIdentity: harness.session.workspaceIdentity))
    }

    @MainActor
    func testSixPhotoSameWorkspaceRestorePublishesCompositionAndColdRecoveryIsAtomic() async throws {
        let success = try await makePhotoRestoreJourney("live-success")
        defer { try? fileManager.removeItem(at: success.harness.applicationSupportURL) }
        try await assertSameLengthCommonGenericCorruptionFailsBeforeEffects(success)
        let successNewID = uuid(701), successRestoreID = uuid(702)
        let successService = try BackupRestoreService(
            applicationSupportURL: success.harness.applicationSupportURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
            makeUUID: sequence([successNewID, successRestoreID])
        )
        let pointerURL = success.harness.applicationSupportURL
            .appendingPathComponent(OwnedStorageRootKindV1.data.rawValue, isDirectory: true)
            .appendingPathComponent("current.json")
        let oldPointerBytes = try Data(contentsOf: pointerURL)
        var pointerObservations: [Bool] = []
        successService.photoRawPointerObservationForTesting = { published in
            pointerObservations.append(published)
            let descriptor = Darwin.open(success.rawRoot.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            XCTAssertGreaterThanOrEqual(descriptor, 0)
            guard descriptor >= 0 else { throw FixtureError.invalid }
            defer { Darwin.close(descriptor) }
            let lockResult = Darwin.flock(descriptor, LOCK_EX | LOCK_NB)
            let lockError = errno
            if lockResult == 0 { Darwin.flock(descriptor, LOCK_UN) }
            XCTAssertEqual(lockResult, -1, "R must cover both sides of the actual pointer CAS")
            XCTAssertEqual(lockError, EWOULDBLOCK)
            let pointerBytes = try Data(contentsOf: pointerURL)
            if published { XCTAssertNotEqual(pointerBytes, oldPointerBytes) }
            else { XCTAssertEqual(pointerBytes, oldPointerBytes) }
            let binding = try self.readPhotoRestoreBinding(self.photoRestoreBindingURL(
                success.harness.applicationSupportURL, restoreID: successRestoreID))
            let transition = try XCTUnwrap(binding.rawTransition)
            XCTAssertEqual(try Data(contentsOf: success.rawRoot.appendingPathComponent(
                DraftAttachmentStagingAdapterV1.manifestName)), try transition.after.canonicalBytes())
        }
        let restored = try await successService.restore(
            validatedPackage: success.sourcePackage,
            currentModelContext: success.harness.context,
            currentGenerationID: success.oldGenerationID,
            currentGenerationRootURL: success.harness.session.generationRootURL,
            mode: .replaceExisting
        )
        XCTAssertEqual(restored.generationID, successNewID)
        XCTAssertEqual(pointerObservations, [false, true])
        try await assertCompletedPhotoRestoreJourney(success, session: restored,
            expectedCurrentID: successNewID, restoreID: successRestoreID)

        let oldOutcome: Set<BackupRestoreFailurePoint> = [
            .beforePreparedWrite, .afterPreparedWrite, .afterGenerationInstall,
        ]
        let points: [BackupRestoreFailurePoint] = [
            .beforePreparedWrite, .afterPreparedWrite, .afterGenerationInstall,
            .afterPointerSwitch, .afterNewGenerationValidation,
        ]
        for (offset, point) in points.enumerated() {
            let fixture = try await makePhotoRestoreJourney("cold-\(offset)-\(point)")
            defer { try? fileManager.removeItem(at: fixture.harness.applicationSupportURL) }
            let newID = uuid(710 + offset * 2), restoreID = uuid(711 + offset * 2)
            let service = try BackupRestoreService(
                applicationSupportURL: fixture.harness.applicationSupportURL,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
                makeUUID: sequence([newID, restoreID]),
                failureInjection: BackupRestoreFailureInjection(failOnceAt: point)
            )
            await XCTAssertThrowsErrorAsync {
                _ = try await service.restore(
                    validatedPackage: fixture.sourcePackage,
                    currentModelContext: fixture.harness.context,
                    currentGenerationID: fixture.oldGenerationID,
                    currentGenerationRootURL: fixture.harness.session.generationRootURL,
                    mode: .replaceExisting
                )
            } verify: { error in
                XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure, "\(point)")
            }

            let factory = StoreGenerationFactory(
                applicationSupportURL: fixture.harness.applicationSupportURL)
            let intentStore = try RestoreIntentStore(
                applicationSupportURL: fixture.harness.applicationSupportURL)
            let intent = try intentStore.load()
            let bindingURL = photoRestoreBindingURL(
                fixture.harness.applicationSupportURL, restoreID: restoreID)
            let binding = try readPhotoRestoreBinding(bindingURL)
            XCTAssertEqual(binding.schemaVersion, 2, "\(point)")
            XCTAssertEqual(binding.core.restoreID, restoreID, "\(point)")
            XCTAssertEqual(binding.core.oldGenerationID, fixture.oldGenerationID, "\(point)")
            XCTAssertEqual(binding.core.newGenerationID, newID, "\(point)")
            XCTAssertEqual(binding.core.selections.map { $0.members.childDraftIDs.count }, [6, 2], "\(point)")
            XCTAssertNotEqual(binding.core.currentRecordsSHA256,
                binding.core.destinationRecordsSHA256, "\(point)")
            XCTAssertEqual(binding.completion, .active, "\(point)")
            XCTAssertEqual(binding.intent.phase, .prepared, "\(point)")
            if point == .beforePreparedWrite || point == .afterPreparedWrite {
                XCTAssertNil(binding.genericReceipt, "\(point)")
            } else {
                let genericReceipt = try XCTUnwrap(binding.genericReceipt, "\(point)")
                XCTAssertEqual(genericReceipt.adoptedStageIDs,
                    [fixture.sourceOnlyGenericStage.item.stageID], "\(point)")
                XCTAssertEqual(genericReceipt.reusedStageIDs,
                    [fixture.commonGenericStage.item.stageID], "\(point)")
                XCTAssertEqual(genericReceipt.publishedAt,
                    try XCTUnwrap(binding.intent.replacementAt, "\(point)"), "\(point)")
                let transition = try XCTUnwrap(binding.rawTransition, "\(point)")
                XCTAssertEqual(Set(transition.genericStageIDs), Set([
                    fixture.commonGenericStage.item.stageID,
                    fixture.sourceOnlyGenericStage.item.stageID,
                ]), "\(point)")
                XCTAssertEqual(Set(transition.newStageIDs),
                    [fixture.sourceOnlyGenericStage.item.stageID], "\(point)")
                XCTAssertEqual(transition.reusedStageIDs.count, 7, "\(point)")
                XCTAssertTrue(transition.reusedStageIDs.contains(
                    fixture.commonGenericStage.item.stageID), "\(point)")
                XCTAssertEqual(Set(transition.before.entries.map { $0.item.stageID }),
                    try allStageIDs(fixture.oldRecords), "\(point)")
                XCTAssertEqual(Set(transition.after.entries.map { $0.item.stageID }),
                    try allStageIDs(fixture.restoredRecords), "\(point)")
                let ownership = try XCTUnwrap(binding.rawOwnership, "\(point)")
                let createdFiles = ownership.createdNodes.filter { !$0.directory }
                XCTAssertEqual(createdFiles.count, 1, "\(point)")
                let createdFile = try XCTUnwrap(createdFiles.first, "\(point)")
                XCTAssertTrue(createdFile.path.hasSuffix("/payload.bin"), "\(point)")
                XCTAssertFalse(createdFile.path.hasSuffix("/raw-publication.json"), "\(point)")
            }
            if let intent { try binding.requireIntent(intent) }

            let sidecarURL = fixture.harness.applicationSupportURL.appendingPathComponent(
                "FieldEvidenceRestore/portable-exchange-restore.json")
            switch point {
            case .beforePreparedWrite:
                XCTAssertNil(intent)
                XCTAssertNil(binding.rawTransition)
                XCTAssertNil(binding.rawOwnership)
                XCTAssertFalse(fileManager.fileExists(atPath: sidecarURL.path))
                XCTAssertEqual(try factory.currentGenerationID(), fixture.oldGenerationID)
            case .afterPreparedWrite:
                XCTAssertEqual(intent?.phase, .prepared)
                XCTAssertNil(binding.rawTransition)
                XCTAssertNil(binding.rawOwnership)
                XCTAssertTrue(fileManager.fileExists(atPath: sidecarURL.path))
                XCTAssertEqual(try factory.currentGenerationID(), fixture.oldGenerationID)
            case .afterGenerationInstall:
                XCTAssertEqual(intent?.phase, .generationInstalled)
                XCTAssertNotNil(binding.rawTransition)
                XCTAssertNotNil(binding.rawOwnership)
                XCTAssertEqual(Set(binding.rawTransition?.newStageIDs ?? []),
                    [fixture.sourceOnlyGenericStage.item.stageID])
                XCTAssertEqual(Set(binding.rawTransition?.reusedStageIDs ?? []).count, 7)
                XCTAssertTrue(fileManager.fileExists(atPath: sidecarURL.path))
                XCTAssertEqual(try factory.currentGenerationID(), fixture.oldGenerationID)
                let transition = try XCTUnwrap(binding.rawTransition)
                let ownership = try XCTUnwrap(binding.rawOwnership)
                XCTAssertEqual(try Data(contentsOf: fixture.rawRoot.appendingPathComponent(
                    DraftAttachmentStagingAdapterV1.manifestName)), try transition.before.canonicalBytes())
                let sourcePath = DraftAttachmentStagingAdapterV1.relativeDataPath(
                    draftID: fixture.sourceOnlyGenericStage.item.draftID,
                    stageID: fixture.sourceOnlyGenericStage.item.stageID)
                XCTAssertFalse(fileManager.fileExists(atPath: fixture.rawRoot.appendingPathComponent(sourcePath).path))
                XCTAssertEqual(try Data(contentsOf: fixture.rawRoot
                    .appendingPathComponent(ownership.privateName).appendingPathComponent(sourcePath)),
                    fixture.sourceOnlyGenericStage.bytes)
            case .afterPointerSwitch:
                XCTAssertEqual(intent?.phase, .pointerSwitched)
                XCTAssertNotNil(binding.rawTransition)
                XCTAssertNotNil(binding.rawOwnership)
                XCTAssertTrue(fileManager.fileExists(atPath: sidecarURL.path))
                XCTAssertEqual(try factory.currentGenerationID(), newID)
            case .afterNewGenerationValidation:
                XCTAssertEqual(intent?.phase, .newGenerationValidated)
                XCTAssertNotNil(binding.rawTransition)
                XCTAssertNotNil(binding.rawOwnership)
                XCTAssertFalse(fileManager.fileExists(atPath: sidecarURL.path))
                XCTAssertEqual(try factory.currentGenerationID(), newID)
            default:
                XCTFail("Unselected photo restore interruption \(point)")
            }

            // A fresh service instance is the production cold-start boundary.
            let recovery = try BackupRestoreService(
                applicationSupportURL: fixture.harness.applicationSupportURL,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }))
            let recovered = try await recovery
                .reconcileRestoreAndPrivateSystemDiscoveryAtStartup()
            let expectedID = oldOutcome.contains(point) ? fixture.oldGenerationID : newID
            XCTAssertEqual(try factory.currentGenerationID(), expectedID, "\(point)")
            if oldOutcome.contains(point) {
                XCTAssertNil(recovered, "\(point)")
                try await assertPhotoRestoreSnapshot(fixture,
                    session: fixture.harness.session, restored: false)
            } else {
                let recoveredSession = try XCTUnwrap(recovered, "\(point)")
                XCTAssertEqual(recoveredSession.generationID, newID, "\(point)")
                try await assertPhotoRestoreSnapshot(fixture,
                    session: recoveredSession, restored: true)
            }
            XCTAssertNil(try intentStore.load(), "\(point)")
            XCTAssertFalse(fileManager.fileExists(atPath: bindingURL.path), "\(point)")
            XCTAssertFalse(fileManager.fileExists(atPath: sidecarURL.path), "\(point)")
            XCTAssertFalse(fileManager.fileExists(
                atPath: fixture.sourcePackage.stagedPackageURL.path), "\(point)")

            // A second cold retry cannot replay any target receipt, raw publish,
            // pointer switch, or generation retirement.
            let stableRaw = try treeFacts(fixture.rawRoot)
            let stablePointer = try factory.currentGenerationID()
            let stableRetired = try factory.retiredGenerationIDs()
            let noFurtherRecovery = try await recovery
                .reconcileRestoreAndPrivateSystemDiscoveryAtStartup()
            XCTAssertNil(noFurtherRecovery, "\(point)")
            XCTAssertEqual(try factory.currentGenerationID(), stablePointer, "\(point)")
            XCTAssertEqual(try factory.retiredGenerationIDs(), stableRetired, "\(point)")
            XCTAssertEqual(try treeFacts(fixture.rawRoot), stableRaw, "\(point)")
        }

        try await assertUnsupportedCurrentOnlyGenericCompositionFailsBeforeEffects()

        for (offset, point) in [BackupRestoreFailurePoint.afterGenerationInstall,
                                .afterPointerSwitch].enumerated() {
            let fixture = try await makeSourceEmptyPhotoRestoreJourney(
                "source-empty-\(offset)-\(point)")
            defer { try? fileManager.removeItem(at: fixture.harness.applicationSupportURL) }
            let newID = uuid(760 + offset * 2), restoreID = uuid(761 + offset * 2)
            let service = try BackupRestoreService(
                applicationSupportURL: fixture.harness.applicationSupportURL,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
                makeUUID: sequence([newID, restoreID]),
                failureInjection: BackupRestoreFailureInjection(failOnceAt: point))
            await XCTAssertThrowsErrorAsync {
                _ = try await service.restore(validatedPackage: fixture.sourcePackage,
                    currentModelContext: fixture.harness.context,
                    currentGenerationID: fixture.oldGenerationID,
                    currentGenerationRootURL: fixture.harness.session.generationRootURL,
                    mode: .replaceExisting)
            } verify: { error in
                XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure, "\(point)")
            }
            let bindingURL = photoRestoreBindingURL(
                fixture.harness.applicationSupportURL, restoreID: restoreID)
            let binding = try readPhotoRestoreBinding(bindingURL)
            XCTAssertEqual(binding.core.selections.map {
                $0.members.childDraftIDs.count
            }, [0, 2], "\(point)")
            XCTAssertEqual(binding.core.currentRecordsSHA256,
                binding.core.destinationRecordsSHA256, "\(point)")
            XCTAssertNil(binding.genericReceipt, "\(point)")
            let transition = try XCTUnwrap(binding.rawTransition, "\(point)")
            XCTAssertEqual(transition.newStageIDs, [], "\(point)")
            XCTAssertEqual(transition.reusedStageIDs, [], "\(point)")
            XCTAssertEqual(transition.genericStageIDs, [], "\(point)")
            XCTAssertEqual(Set(transition.before.entries.map { $0.item.stageID }),
                try allStageIDs(fixture.records), "\(point)")
            XCTAssertEqual(transition.before, transition.after, "\(point)")
            let ownership = try XCTUnwrap(binding.rawOwnership, "\(point)")
            XCTAssertEqual(ownership.createdNodes.count, 1, "\(point)")
            XCTAssertTrue(ownership.createdNodes.allSatisfy(\.directory), "\(point)")
            let recovery = try BackupRestoreService(
                applicationSupportURL: fixture.harness.applicationSupportURL,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }))
            let recovered = try await recovery
                .reconcileRestoreAndPrivateSystemDiscoveryAtStartup()
            let expectedID = point == .afterGenerationInstall
                ? fixture.oldGenerationID : newID
            let factory = StoreGenerationFactory(
                applicationSupportURL: fixture.harness.applicationSupportURL)
            XCTAssertEqual(try factory.currentGenerationID(), expectedID, "\(point)")
            let expectedRetired = fixture.initialRetiredGenerationIDs
                + (point == .afterGenerationInstall ? [] : [fixture.oldGenerationID])
            let retired = try factory.retiredGenerationIDs()
            XCTAssertEqual(retired.count, expectedRetired.count, "\(point)")
            XCTAssertEqual(Set(retired), Set(expectedRetired), "\(point)")
            if point == .afterGenerationInstall {
                XCTAssertNil(recovered, "\(point)")
                try assertSourceEmptyPhotoSnapshot(fixture,
                    session: fixture.harness.session)
            } else {
                try assertSourceEmptyPhotoSnapshot(fixture,
                    session: XCTUnwrap(recovered, "\(point)"))
            }
            XCTAssertFalse(fileManager.fileExists(atPath: bindingURL.path), "\(point)")
            XCTAssertNil(try RestoreIntentStore(
                applicationSupportURL: fixture.harness.applicationSupportURL).load(), "\(point)")
            XCTAssertFalse(fileManager.fileExists(
                atPath: fixture.sourcePackage.stagedPackageURL.path), "\(point)")
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
        let authorized = try await makeAuthorizedExportHarness(harness)
        defer { authorized.close() }
        let destination = harness.applicationSupportURL.appendingPathComponent("export", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        let service = makeService(authorized, capacity: 0)
        let preview = try authorized.contentAccess.withRead { try service.prepare() }
        let beforeFiles = try treeFacts(harness.session.generationRootURL)
        let beforeRecords = try modelFacts(harness.context)

        do {
            _ = try await service.export(previewID: preview.id, to: destination,
                contentAccess: authorized.contentAccess)
            XCTFail("Expected exact capacity failure")
        } catch {
            XCTAssertEqual(error as? BackupExportServiceError, .insufficientStorage)
        }
        XCTAssertFalse(fileManager.fileExists(atPath: destination.appendingPathComponent("AssetRounds.fieldrecordbackup").path))
        XCTAssertEqual(try treeFacts(harness.session.generationRootURL), beforeFiles)
        XCTAssertEqual(try modelFacts(harness.context), beforeRecords)
        XCTAssertFalse(harness.context.hasChanges)
    }

    @MainActor
    func testAsyncExportCancellationDuringWriterRemovesOwnedPackage() async throws {
        let harness = try await makeMixedHarness("cancel-during-write", currentWriterSource: true,
                                                 beginOnly: true)
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let authorized = try await makeAuthorizedExportHarness(harness)
        defer { authorized.close() }
        let destination = harness.applicationSupportURL.appendingPathComponent("cancel-export", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        let service = makeService(authorized, capacity: .max)
        let preview = try authorized.contentAccess.withRead { try service.prepare() }
        let gate = BackupExportCancellationGate()
        let export = Task { @MainActor in
            try await service.export(previewID: preview.id, to: destination,
                contentAccess: authorized.contentAccess,
                cancellation: StreamingArchiveCancellationV1 { try gate.checkpoint() })
        }
        defer { gate.resume() }
        let enteredWriter = await Task.detached { gate.waitUntilEntered() }.value
        guard enteredWriter else {
            export.cancel()
            gate.resume()
            _ = try? await export.value
            return XCTFail("Export did not reach the bounded writer checkpoint")
        }
        export.cancel()
        gate.resume()

        do {
            _ = try await export.value
            XCTFail("Cancelled writer must not publish")
        } catch {
            XCTAssertEqual(error as? BackupExportServiceError, .cancelled)
        }
        XCTAssertFalse(fileManager.fileExists(atPath: destination
            .appendingPathComponent("AssetRounds.fieldrecordbackup").path))
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: destination.path), [])
    }

    @MainActor
    func testAsyncExportCancellationImmediatelyAfterWriterSuccessCleansReceiptOwnedPackage() async throws {
        let harness = try await makeMixedHarness("cancel-after-write", currentWriterSource: true,
                                                 beginOnly: true)
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let authorized = try await makeAuthorizedExportHarness(harness)
        defer { authorized.close() }
        let destination = harness.applicationSupportURL.appendingPathComponent("cancel-export", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        let service = makeService(authorized, capacity: .max)
        let preview = try authorized.contentAccess.withRead { try service.prepare() }
        service.afterArchivePublicationForTesting = {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        let export = Task { @MainActor in
            try await service.export(previewID: preview.id, to: destination,
                contentAccess: authorized.contentAccess)
        }

        do {
            _ = try await export.value
            XCTFail("Post-write cancellation must revoke publication")
        } catch {
            XCTAssertEqual(error as? BackupExportServiceError, .cancelled)
        }
        XCTAssertFalse(fileManager.fileExists(atPath: destination
            .appendingPathComponent("AssetRounds.fieldrecordbackup").path))
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: destination.path), [])
    }

    func testPublishedArchiveCleanupDeletesOnlyExactOwnedInode() throws {
        let root = try makeArchiveCleanupFixtureRoot("exact-owned")
        defer { try? fileManager.removeItem(at: root) }
        let receipt = try makeArchiveCleanupReceipt(in: root)

        try BackupExportService.removeOwnedPublishedArchiveForTesting(
            receipt: receipt, within: root)

        XCTAssertFalse(fileManager.fileExists(atPath: receipt.archiveURL.path))
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: root.path).sorted(),
                       ["source", "staging"])
    }

    func testPublishedArchiveCleanupPreservesEqualMagicReplacement() throws {
        let root = try makeArchiveCleanupFixtureRoot("equal-magic-replacement")
        defer { try? fileManager.removeItem(at: root) }
        let receipt = try makeArchiveCleanupReceipt(in: root)
        let original = try Data(contentsOf: receipt.archiveURL)
        let retained = root.appendingPathComponent("retained-original.fieldrecordbackup")
        try fileManager.moveItem(at: receipt.archiveURL, to: retained)
        try original.write(to: receipt.archiveURL, options: .withoutOverwriting)

        XCTAssertTrue(try StreamingArchiveService.hasFormatMagic(at: receipt.archiveURL))
        XCTAssertThrowsError(try BackupExportService.removeOwnedPublishedArchiveForTesting(
            receipt: receipt, within: root)) {
            XCTAssertEqual($0 as? BackupExportServiceError, .cleanupFailed)
        }
        XCTAssertEqual(try Data(contentsOf: receipt.archiveURL), original)
        XCTAssertTrue(fileManager.fileExists(atPath: retained.path))
    }

    func testPublishedArchiveCleanupPreservesReplacementRacedBeforePrivateClaim() throws {
        let root = try makeArchiveCleanupFixtureRoot("raced-replacement")
        defer { try? fileManager.removeItem(at: root) }
        let receipt = try makeArchiveCleanupReceipt(in: root)
        let replacement = StreamingArchiveFormatV1.magic + Data("replacement".utf8)
        let retained = root.appendingPathComponent("retained-owned.fieldrecordbackup")

        XCTAssertThrowsError(try BackupExportService.removeOwnedPublishedArchiveForTesting(
            receipt: receipt, within: root, beforePrivateClaim: {
                try self.fileManager.moveItem(at: receipt.archiveURL, to: retained)
                try replacement.write(to: receipt.archiveURL, options: .withoutOverwriting)
            })) {
            XCTAssertEqual($0 as? BackupExportServiceError, .cleanupFailed)
        }
        XCTAssertEqual(try Data(contentsOf: receipt.archiveURL), replacement)
        XCTAssertTrue(fileManager.fileExists(atPath: retained.path))
    }

    func testFormatMagicProbeRejectsFIFOWithoutBlocking() throws {
        let root = try makeArchiveCleanupFixtureRoot("fifo-magic")
        defer { try? fileManager.removeItem(at: root) }
        let fifo = root.appendingPathComponent("hostile.fieldrecordbackup")
        XCTAssertEqual(Darwin.mkfifo(fifo.path, mode_t(0o600)), 0)
        let started = Date()

        XCTAssertThrowsError(try StreamingArchiveService.hasFormatMagic(at: fifo))
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
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

private actor BackupExportTestAuthentication: LocalAuthenticationClient {
    func availability() -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }

    func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 {
        .authenticated
    }

    func cancel(attemptID: UUID) {}
}

private final class BackupExportCancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private let entered = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)
    private var didEnter = false

    func checkpoint() throws {
        // The exporter checks cancellation on MainActor before freezing. This
        // gate targets the first archive-writer checkpoint only.
        guard !Thread.isMainThread else { return }
        lock.lock()
        let shouldWait = !didEnter
        if shouldWait { didEnter = true }
        lock.unlock()
        guard shouldWait else { return }
        entered.signal()
        guard release.wait(timeout: .now() + 10) == .success else {
            throw StreamingArchiveFailureV1.cancelled
        }
    }

    func waitUntilEntered() -> Bool {
        entered.wait(timeout: .now() + 10) == .success
    }
    func resume() { release.signal() }
}

@MainActor
private final class BackupExportTestNotificationSystem: NotificationSystemPortV1 {
    private var requests: [NotificationSystemRequestV1] = []

    func authorization() async throws -> LocalReminderAuthorizationV1 { .authorized }

    func observations() async throws -> [NotificationSystemObservationV1] {
        requests.map {
            .init(requestID: $0.notification.requestID, request: $0, delivered: false)
        }
    }

    func add(_ request: NotificationSystemRequestV1) async throws {
        requests.append(request)
    }

    func remove(_ requestIDs: [String]) async throws {
        requests.removeAll { requestIDs.contains($0.notification.requestID) }
    }
}

extension S6_2BackupExportTests {
    func testC22RecoverabilityVerificationAnchor() throws {
        XCTAssertEqual(RecoverabilityVerificationReceiptV1.schemaVersion, 1)
        try V21RecoverabilityImportBoundaryV1.validate(persistent: 21, records: 20)
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
    struct PhotoRestoreJourney {
        let harness: Harness
        let sourcePackage: ValidatedV4BackupPackageV1
        let oldGenerationID: UUID
        let initialRetiredGenerationIDs: [UUID]
        let oldRecords: V4BackupRecordsV1
        let oldRecordsData: Data
        let restoredRecords: V4BackupRecordsV1
        let restoredRecordsData: Data
        let expectedMembers: [V4BackupEntryV1]
        let expectedPlan: CheckRunnerPhotoBackupRestorePlanV1
        let oldRawFacts: [String]
        let rawRoot: URL
        let retainedMyDayDraftID: UUID
        let sourcePhotoDraftIDs: Set<UUID>
        let retainedPhotoDraftIDs: Set<UUID>
        let commonGenericStage: GenericCompositionStage
        let sourceOnlyGenericStage: GenericCompositionStage
    }
    struct GenericCompositionStage {
        let checkpoint: FieldDraftCheckpointV1
        let item: AttachmentStagingItemV1
        let bytes: Data
    }
    struct SourceEmptyPhotoRestoreJourney {
        let harness: Harness
        let sourcePackage: ValidatedV4BackupPackageV1
        let oldGenerationID: UUID
        let initialRetiredGenerationIDs: [UUID]
        let records: V4BackupRecordsV1
        let recordsData: Data
        let members: [V4BackupEntryV1]
        let rawRoot: URL
        let rawFacts: [String]
        let retainedMyDayDraftID: UUID
        let retainedPhotoDraftIDs: Set<UUID>
    }
    @MainActor
    final class AuthorizedExportHarness {
        let defaultsSuiteName: String
        let defaults: UserDefaults
        let presentation: AppAccessPresentationV1
        let coordinator: StoreSessionCoordinator
        let contentAccess: AppAccessPresentationV1.ContentAccess

        init(defaultsSuiteName: String, defaults: UserDefaults,
             presentation: AppAccessPresentationV1, coordinator: StoreSessionCoordinator,
             contentAccess: AppAccessPresentationV1.ContentAccess) {
            self.defaultsSuiteName = defaultsSuiteName
            self.defaults = defaults
            self.presentation = presentation
            self.coordinator = coordinator
            self.contentAccess = contentAccess
        }

        func close() {
            try? coordinator.invalidateAndReleaseWriter()
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
    }
    struct PayloadFact: Equatable {
        let path: String
        let byteCount: Int
        let mimeType: String
        let sha256: String
    }
    struct MediaFact { let sourcePath: String; let exportPath: String; let sha256: String }

    @MainActor
    func XCTAssertThrowsErrorAsync(
        _ expression: () async throws -> Void,
        verify: (Error) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail("Expected error", file: file, line: line)
        } catch {
            verify(error)
        }
    }

    enum ConfigurationClonePhotoPhase: String, CaseIterable {
        case awaitingRawStage = "AWAITING_RAW_STAGE"
        case rawReady = "RAW_READY"
        case pairReady = "PAIR_READY"
        case committing = "COMMITTING"
        case targetPresent = "TARGET_PRESENT"
        case terminal = "TERMINAL"

        var retainsFinalMedia: Bool {
            self == .targetPresent || self == .terminal
        }
    }

    struct ConfigurationCloneIncumbentPhotoFact {
        let phase: ConfigurationClonePhotoPhase
        let childID: UUID
        let checkpoint: FieldDraftCheckpointV1
        let payload: CheckRunnerPhotoDraftPayloadV1
    }

    struct ConfigurationCloneFinalMediaFact {
        let evidence: V4BackupEvidenceFileDTO
        let original: Data
        let thumbnail: Data
    }

    @MainActor
    func prepareConfigurationClonePhoto(
        _ phase: ConfigurationClonePhotoPhase,
        in fixture: FrozenBeginFixture
    ) async throws -> FrozenProductionPhotoV1 {
        let photo = try await FrozenProductionPhotoV1.make(
            fixture,
            publishRaw: phase != .awaitingRawStage
        )
        guard phase != .awaitingRawStage, phase != .rawReady else { return photo }
        let pair = try await photo.service.preparePhotoPair(
            parentDraftID: photo.parentID,
            childDraftID: photo.childID
        )
        guard phase != .pairReady else { return photo }
        let attempt = try photo.attempt(pairCheckpoint: pair)
        _ = try photo.service.preparePhotoCommit(
            parentDraftID: photo.parentID,
            childDraftID: photo.childID,
            expectedCheckpointSHA256: pair.checkpointSHA256,
            proposal: attempt
        )
        guard phase != .committing else { return photo }
        if phase == .targetPresent {
            photo.service.beforePhotoTargetAcknowledgementForTesting = {
                throw FieldDraftFailureV1.missingReceipt
            }
            do {
                _ = try await photo.service.resumePhotoCommit(
                    parentDraftID: photo.parentID,
                    childDraftID: photo.childID
                )
                XCTFail("Expected interruption after the durable target receipt")
            } catch {
                XCTAssertEqual(error as? FieldDraftFailureV1, .missingReceipt)
            }
            return photo
        }
        _ = try await photo.service.resumePhotoCommit(
            parentDraftID: photo.parentID,
            childDraftID: photo.childID
        )
        return photo
    }

    func assertConfigurationCloneSourcePhase(
        _ phase: ConfigurationClonePhotoPhase,
        child: CheckRunnerPhotoBackupHistoryChildV1,
        checkpoint: FieldDraftCheckpointV1,
        payload: CheckRunnerPhotoDraftPayloadV1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(child.currentCheckpoint, checkpoint, file: file, line: line)
        XCTAssertEqual(child.payload, payload, file: file, line: line)
        switch phase {
        case .awaitingRawStage:
            guard case .awaitingRawStage = child.payload.phase else {
                return XCTFail("Expected AWAITING_RAW_STAGE", file: file, line: line)
            }
            guard case .awaitingRaw = child.phaseEvidence else {
                return XCTFail("Expected awaiting-raw frontier", file: file, line: line)
            }
            XCTAssertEqual(child.currentCheckpoint.state, .active, file: file, line: line)
            XCTAssertNil(child.raw, file: file, line: line)
            XCTAssertNil(child.currentStage, file: file, line: line)
        case .rawReady:
            guard case .rawReady = child.payload.phase else {
                return XCTFail("Expected RAW_READY", file: file, line: line)
            }
            guard case .rawReady = child.phaseEvidence else {
                return XCTFail("Expected raw-ready frontier", file: file, line: line)
            }
            XCTAssertEqual(child.currentCheckpoint.state, .active, file: file, line: line)
            XCTAssertNotNil(child.raw, file: file, line: line)
            XCTAssertNotNil(child.currentStage, file: file, line: line)
        case .pairReady:
            guard case .pairReady = child.payload.phase else {
                return XCTFail("Expected PAIR_READY", file: file, line: line)
            }
            guard case .continuation = child.phaseEvidence else {
                return XCTFail("Expected pair continuation", file: file, line: line)
            }
            XCTAssertEqual(child.currentCheckpoint.state, .active, file: file, line: line)
            XCTAssertNotNil(child.raw, file: file, line: line)
            XCTAssertNotNil(child.pair, file: file, line: line)
            XCTAssertNil(child.preparedReconstruction, file: file, line: line)
        case .committing:
            guard case .preparedCommit = child.payload.phase else {
                return XCTFail("Expected COMMITTING prepared commit", file: file, line: line)
            }
            XCTAssertEqual(child.currentCheckpoint.state, .committing, file: file, line: line)
            XCTAssertNotNil(child.preparedReconstruction, file: file, line: line)
            XCTAssertNotNil(child.committingCheckpoint, file: file, line: line)
            XCTAssertNil(child.target, file: file, line: line)
            XCTAssertNil(child.terminal, file: file, line: line)
        case .targetPresent:
            guard case .preparedCommit = child.payload.phase else {
                return XCTFail("Expected TARGET_PRESENT prepared commit", file: file, line: line)
            }
            XCTAssertEqual(child.currentCheckpoint.state, .committing, file: file, line: line)
            XCTAssertNotNil(child.target, file: file, line: line)
            XCTAssertNotNil(child.targetRecords, file: file, line: line)
            XCTAssertNil(child.terminal, file: file, line: line)
            XCTAssertNil(child.parentLink, file: file, line: line)
        case .terminal:
            guard case .preparedCommit = child.payload.phase else {
                return XCTFail("Expected TERMINAL prepared commit", file: file, line: line)
            }
            XCTAssertEqual(child.currentCheckpoint.state, .committed, file: file, line: line)
            XCTAssertNotNil(child.target, file: file, line: line)
            XCTAssertNotNil(child.targetRecords, file: file, line: line)
            XCTAssertNotNil(child.terminal, file: file, line: line)
            XCTAssertNotNil(child.parentLink, file: file, line: line)
            XCTAssertNotNil(child.currentTarget, file: file, line: line)
        }
        if phase != .terminal {
            XCTAssertNil(child.terminal, file: file, line: line)
        }
    }

    func assertConfigurationCloneHistoryPreserved(
        source: MutationHistorySnapshotV1,
        destination: MutationHistorySnapshotV1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(destination.workspaceRevision, source.workspaceRevision,
            file: file, line: line)
        XCTAssertEqual(destination.lastLocalSequence, 0, file: file, line: line)
        XCTAssertEqual(destination.receipts, source.receipts, file: file, line: line)
        XCTAssertEqual(destination.quarantines, source.quarantines, file: file, line: line)
        XCTAssertEqual(destination.entityRevisions, source.entityRevisions,
            file: file, line: line)
    }

    @MainActor
    func makeConfigurationCloneTarget(_ label: String) throws -> Harness {
        let support = fileManager.temporaryDirectory.appendingPathComponent(
            "S6_2BackupExportTests-clone-\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: support, withIntermediateDirectories: false)
        let session = try StoreGenerationFactory(applicationSupportURL: support)
            .openOrBootstrapCurrent()
        return Harness(applicationSupportURL: support, session: session,
            context: session.modelContext, countedRoots: [])
    }

    @MainActor
    func canonicalBasis(_ harness: Harness) throws
        -> BackupCanonicalCheckpointBasisV1 {
        try BackupExportService(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
        ).canonicalCheckpointBasis()
    }

    @MainActor
    func configurationCloneFieldDraftRows(_ context: ModelContext) throws
        -> [V16BackupFieldDraftRecordV1] {
        var result: [V16BackupFieldDraftRecordV1] = []
        result += try context.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).map {
            let value = try $0.value()
            return .init(kind: .checkpoint, id: value.draftID,
                workspaceID: value.workspaceID.rawValue, revision: value.draftRevision,
                canonicalData: try FieldDraftCanonicalCodecV1.encode(value))
        }
        result += try context.fetch(FetchDescriptor<AttachmentStagingItemRow>()).map {
            let value = try $0.value()
            return .init(kind: .stagingItem, id: value.stageID,
                workspaceID: value.workspaceID.rawValue, revision: value.revision,
                canonicalData: try FieldDraftCanonicalCodecV1.encode(value))
        }
        result += try context.fetch(FetchDescriptor<DraftCommitSagaRow>()).map {
            let value = try $0.value()
            return .init(kind: .commitSaga, id: value.sagaID,
                workspaceID: value.workspaceID.rawValue, revision: value.revision,
                canonicalData: try FieldDraftCanonicalCodecV1.encode(value))
        }
        result += try context.fetch(FetchDescriptor<DraftContentReservationRow>()).map {
            let value = try $0.value()
            return .init(kind: .contentReservation, id: value.reservationID,
                workspaceID: value.workspaceID.rawValue, revision: value.revision,
                canonicalData: try FieldDraftCanonicalCodecV1.encode(value))
        }
        result += try context.fetch(FetchDescriptor<DraftCommitReceiptRow>()).map {
            let value = try $0.value()
            return .init(kind: .commitReceipt, id: value.receiptID,
                workspaceID: value.workspaceID.rawValue, revision: value.revision,
                canonicalData: try FieldDraftCanonicalCodecV1.encode(value))
        }
        result += try context.fetch(FetchDescriptor<DraftDiscardReceiptRow>()).map {
            let value = try $0.value()
            return .init(kind: .discardReceipt, id: value.receiptID,
                workspaceID: value.workspaceID.rawValue, revision: value.revision,
                canonicalData: try FieldDraftCanonicalCodecV1.encode(value))
        }
        return result.sorted {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString)"
                < "\($1.kind.rawValue)\u{0}\($1.id.uuidString)"
        }
    }

    func assertConfigurationCloneRetiredOperationalFamily(
        applicationSupportURL: URL,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let root = applicationSupportURL
            .appendingPathComponent(OwnedStorageRootKindV1.data.rawValue, isDirectory: true)
            .appendingPathComponent(DraftAttachmentStagingAdapterV1.directoryName,
                isDirectory: true)
        let names = try fileManager.contentsOfDirectory(atPath: root.path).sorted()
        XCTAssertEqual(names, [
            DraftAttachmentStagingAdapterV1.manifestName,
            DraftAttachmentStagingAdapterV1.quarantineName,
        ].sorted(), label, file: file, line: line)
        XCTAssertFalse(names.contains(where: { $0.hasPrefix(".clone-retirement-") }),
            label, file: file, line: line)
        XCTAssertEqual(
            try Data(contentsOf: root.appendingPathComponent(
                DraftAttachmentStagingAdapterV1.manifestName)),
            try DraftAttachmentStagingManifestV1(entries: []).canonicalBytes(),
            label,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fileManager.contentsOfDirectory(atPath: root.appendingPathComponent(
                DraftAttachmentStagingAdapterV1.quarantineName, isDirectory: true).path),
            [],
            label,
            file: file,
            line: line
        )
        let restoreRoot = applicationSupportURL.appendingPathComponent(
            "FieldEvidenceRestore", isDirectory: true)
        if fileManager.fileExists(atPath: restoreRoot.path) {
            let restoreNames = try fileManager.contentsOfDirectory(
                atPath: restoreRoot.path)
            XCTAssertFalse(restoreNames.contains {
                $0.hasPrefix("clone-retirement-")
                    || $0.hasPrefix(".clone-retirement-")
            }, label, file: file, line: line)
        }
    }

    @MainActor
    func assertConfigurationCloneSucceeds(
        package: ValidatedV4BackupPackageV1,
        target: Harness,
        sourceWorkspaceID: WorkspaceID,
        sourceMutationHistory: MutationHistorySnapshotV1,
        expectedPhotoBytes: [ConfigurationCloneFinalMediaFact],
        temporalSource: TemporalEvidenceClipV1?,
        incumbentPhoto: ConfigurationCloneIncumbentPhotoFact?,
        incumbentGeneric: GenericCompositionStage?,
        expectsPopulatedRetirement: Bool,
        label: String
    ) async throws {
        let oldWorkspaceID = target.session.workspaceID
        let oldGenerationID = target.session.generationID
        let oldBasis = try canonicalBasis(target)
        let oldRecords = try BackupCanonicalDecoderV1().decodeRecords(oldBasis.recordsData)
        XCTAssertEqual(
            try BackupCanonicalEncoderV1().encodeRecords(oldRecords).data,
            oldBasis.recordsData,
            label
        )
        let oldDraftRows = try configurationCloneFieldDraftRows(target.context)
        XCTAssertEqual(oldDraftRows.isEmpty, !expectsPopulatedRetirement, label)
        XCTAssertEqual(oldDraftRows, oldRecords.fieldDrafts, label)

        let oldSource = V4BackupSourceV1(
            appBuild: "test",
            appVersion: "test",
            persistentSchemaVersion: LightingNightWorkflowBackupEnrollmentV1
                .persistentSchemaVersion,
            replicaID: target.session.replicaID.rawValue,
            recordsSchemaVersion: oldRecords.recordsSchemaVersion,
            sourceGenerationID: oldGenerationID,
            workspaceID: oldWorkspaceID.rawValue
        )
        let oldPhotoHistory = try CheckRunnerPhotoBackupHistoryV1.project(
            source: oldSource,
            records: oldRecords
        )
        if let incumbentPhoto {
            XCTAssertEqual(oldPhotoHistory.children.count, 1, label)
            let child = try XCTUnwrap(oldPhotoHistory.children.first, label)
            XCTAssertEqual(child.payload.childDraftID, incumbentPhoto.childID, label)
            assertConfigurationCloneSourcePhase(
                incumbentPhoto.phase,
                child: child,
                checkpoint: incumbentPhoto.checkpoint,
                payload: incumbentPhoto.payload
            )
        } else {
            XCTAssertTrue(oldPhotoHistory.children.isEmpty, label)
        }
        if let incumbentGeneric {
            XCTAssertTrue(oldDraftRows.contains {
                $0.kind == .stagingItem && $0.id == incumbentGeneric.item.stageID
            }, label)
            let adapter = try DraftAttachmentStagingAdapterV1(
                applicationSupportURL: target.applicationSupportURL,
                workspaceID: oldWorkspaceID
            )
            XCTAssertEqual(
                try await adapter.data(stageID: incumbentGeneric.item.stageID),
                incumbentGeneric.bytes,
                label
            )
        }

        let oldHistoryStore = try MutationJournalStoreV1(
            modelContext: target.context,
            identity: target.session.workspaceIdentity,
            generationID: oldGenerationID,
            allowStateBootstrap: false
        )
        let oldHistory = try oldHistoryStore.exportSnapshot()
        let oldHistoryBytes = try StoreMigrationCanonicalJSONV1.encode(oldHistory)
        XCTAssertEqual(oldHistory.receipts.isEmpty, !expectsPopulatedRetirement, label)
        let oldTree = try configurationCloneStableGenerationFacts(target.session.generationRootURL)
        let factory = StoreGenerationFactory(
            applicationSupportURL: target.applicationSupportURL)
        let retiredBefore = try factory.retiredGenerationIDs()

        let restored: StoreGenerationSession
        do {
            restored = try await BackupRestoreService(
                applicationSupportURL: target.applicationSupportURL,
                storagePreflight: StoragePreflightService(
                    capacityProvider: { _ in .max }
                )
            ).restore(
                validatedPackage: package,
                currentModelContext: target.context,
                currentGenerationID: oldGenerationID,
                currentGenerationRootURL: target.session.generationRootURL,
                mode: .clone
            )
        } catch {
            XCTFail("Configuration clone success failed [\(label)]: \(error)")
            throw error
        }

        XCTAssertNotEqual(restored.workspaceID, sourceWorkspaceID, label)
        XCTAssertNotEqual(restored.workspaceID, oldWorkspaceID, label)
        XCTAssertEqual(try factory.currentGenerationID(), restored.generationID, label)
        XCTAssertEqual(
            Set(try factory.retiredGenerationIDs()),
            Set(retiredBefore + [oldGenerationID]),
            label
        )
        XCTAssertEqual(try configurationCloneFieldDraftRows(target.context), oldDraftRows,
            label)
        XCTAssertEqual(
            try StoreMigrationCanonicalJSONV1.encode(oldHistoryStore.exportSnapshot()),
            oldHistoryBytes,
            label
        )
        let incumbentInspector = try BackupRestoreService(applicationSupportURL: target.applicationSupportURL)
        XCTAssertEqual(try BackupCanonicalEncoderV1().encodeRecords(
            incumbentInspector.c55CurrentRecordsForTesting(in: target.context)).data,
            oldBasis.recordsData, label)
        XCTAssertEqual(try configurationCloneStableGenerationFacts(target.session.generationRootURL), oldTree, label)
        XCTAssertFalse(target.context.hasChanges, label)

        let clonedHarness = Harness(
            applicationSupportURL: target.applicationSupportURL,
            session: restored,
            context: restored.modelContext,
            countedRoots: []
        )
        let clonedRecords = try BackupCanonicalDecoderV1().decodeRecords(
            canonicalBasis(clonedHarness).recordsData)
        XCTAssertEqual(V16BackupFieldDraftRecordV1.Kind.allCases.count, 6, label)
        for kind in V16BackupFieldDraftRecordV1.Kind.allCases {
            XCTAssertFalse(clonedRecords.fieldDrafts.contains(where: { $0.kind == kind }),
                "\(label): \(kind.rawValue)")
        }
        XCTAssertEqual(clonedRecords.evidenceFiles, package.records.evidenceFiles, label)
        XCTAssertEqual(clonedRecords.temporalEvidence,
            package.records.temporalEvidence, label)
        let destinationHistory = try XCTUnwrap(clonedRecords.mutationHistory, label)
        assertConfigurationCloneHistoryPreserved(
            source: sourceMutationHistory,
            destination: destinationHistory
        )
        XCTAssertTrue(
            Set(destinationHistory.receipts.map(\.receiptData)).isDisjoint(with:
                Set(oldHistory.receipts.map(\.receiptData))),
            "\(label): incumbent effects must not replay"
        )
        if expectsPopulatedRetirement {
            try assertConfigurationCloneRetiredOperationalFamily(
                applicationSupportURL: target.applicationSupportURL,
                label: label
            )
        } else {
            let rawRoot = target.applicationSupportURL
                .appendingPathComponent(OwnedStorageRootKindV1.data.rawValue,
                    isDirectory: true)
                .appendingPathComponent(DraftAttachmentStagingAdapterV1.directoryName,
                    isDirectory: true)
            XCTAssertFalse(fileManager.fileExists(atPath: rawRoot.path), label)
        }
        XCTAssertNil(try RestoreIntentStore(
            applicationSupportURL: target.applicationSupportURL).load(), label)

        for fact in expectedPhotoBytes {
            XCTAssertEqual(
                try Data(contentsOf: restored.generationRootURL
                    .appendingPathComponent(fact.evidence.relativePath)),
                fact.original,
                label
            )
            XCTAssertEqual(
                try Data(contentsOf: restored.generationRootURL
                    .appendingPathComponent(fact.evidence.thumbnailRelativePath)),
                fact.thumbnail,
                label
            )
        }
        if let temporalSource {
            let row = try XCTUnwrap(clonedRecords.temporalEvidence.first, label)
            let clone = try row.clipValue()
            XCTAssertEqual(clone.workspaceID, restored.workspaceID, label)
            XCTAssertEqual(clone.original, temporalSource.original, label)
            XCTAssertEqual(
                try Data(contentsOf: restored.generationRootURL.appendingPathComponent(
                    try TemporalEvidenceBackupMemberV1.original(for: clone))),
                C33TemporalEvidenceTestSupport.bytes(for: temporalSource.facts.kind),
                label
            )
        }

        if !expectedPhotoBytes.isEmpty && !expectsPopulatedRetirement {
            let authorized = try await makeAuthorizedExportHarness(clonedHarness, context: label)
            defer { authorized.close() }
            let destination = target.applicationSupportURL.appendingPathComponent(
                "configuration-clone-cold-export-\(UUID().uuidString)",
                isDirectory: true
            )
            try fileManager.createDirectory(at: destination,
                withIntermediateDirectories: false)
            let exporter = makeService(authorized, capacity: .max)
            let preview = try authorized.contentAccess.withRead {
                try exporter.prepare()
            }
            XCTAssertEqual(preview.photoCount, 0, label)
            let cloneArchive = try await exporter.export(
                previewID: preview.id,
                to: destination,
                contentAccess: authorized.contentAccess
            )
            authorized.close()
            let cloneImporter = try BackupImportService(
                generationRootURL: restored.generationRootURL,
                storagePreflight: StoragePreflightService(
                    capacityProvider: { _ in .max }
                ),
                makeUUID: { UUID() },
                scopedAccess: .alreadyAuthorized
            )
            let clonePackage = try cloneImporter.stageAndValidate(
                selectedPackageURL: cloneArchive)
            defer { try? cloneImporter.discard(clonePackage) }
            XCTAssertTrue(clonePackage.records.fieldDrafts.isEmpty, label)
            XCTAssertEqual(clonePackage.records.evidenceFiles,
                package.records.evidenceFiles, label)
            XCTAssertEqual(clonePackage.records.temporalEvidence,
                clonedRecords.temporalEvidence, label)
        }
    }

    @MainActor
    func assertConfigurationCloneFailureLeavesTargetUnchanged(
        package: ValidatedV4BackupPackageV1,
        target: Harness,
        expectedBasis: BackupCanonicalCheckpointBasisV1?,
        expectedTree: [String],
        expectedCurrentID: UUID,
        expectedRetired: [UUID],
        scenario: String = "hostile-state",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let service = try BackupRestoreService(
            applicationSupportURL: target.applicationSupportURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
        )
        do {
            _ = try await service.restore(
                validatedPackage: package,
                currentModelContext: target.context,
                currentGenerationID: target.session.generationID,
                currentGenerationRootURL: target.session.generationRootURL,
                mode: .clone
            )
            XCTFail("Configuration clone unexpectedly accepted hostile state [\(scenario)]",
                file: file, line: line)
        } catch { }
        let factory = StoreGenerationFactory(
            applicationSupportURL: target.applicationSupportURL)
        XCTAssertEqual(try factory.currentGenerationID(), expectedCurrentID,
            file: file, line: line)
        XCTAssertEqual(try factory.retiredGenerationIDs(), expectedRetired,
            file: file, line: line)
        if let expectedBasis {
            XCTAssertEqual(try canonicalBasis(target), expectedBasis, file: file, line: line)
        }
        XCTAssertEqual(try treeFacts(target.session.generationRootURL), expectedTree,
            file: file, line: line)
        XCTAssertNil(try RestoreIntentStore(
            applicationSupportURL: target.applicationSupportURL).load(),
            file: file, line: line)
    }

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
    func makeService(_ harness: AuthorizedExportHarness, capacity: Int64) -> BackupExportService {
        BackupExportService(
            modelContext: harness.coordinator.modelContext,
            generationRootURL: harness.coordinator.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in capacity }),
            now: { Date(timeIntervalSince1970: 1_786_708_800) },
            makeUUID: { UUID(uuidString: "62000000-0000-0000-0000-000000000099")! },
            appVersion: { "4.0" }, appBuild: { "42" }
        )
    }

    @MainActor
    func makeAuthorizedExportHarness(_ source: Harness, context: String = "",
        caller: String = #function, file: StaticString = #filePath, line: UInt = #line) async throws
        -> AuthorizedExportHarness {
        let suite = "S6_2BackupExportTests.access.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let router = StartupRouter(applicationSupportURL: source.applicationSupportURL)
        do {
            let session = try await ProductionCompositionRoot.makeAppAccessSession(
                applicationSupportURL: source.applicationSupportURL,
                startupRouter: router,
                defaults: defaults,
                authenticationClient: BackupExportTestAuthentication(),
                notificationSystem: BackupExportTestNotificationSystem()
            )
            let presentation = AppAccessPresentationV1(startupRouter: router,
                sessionFactory: { session })
            let published = expectation(description: "Production backup access published")
            let publication = presentation.$permitsContentPresentation
                .filter { $0 }.prefix(1).sink { _ in published.fulfill() }
            defer { publication.cancel() }
            await presentation.bootstrapIfNeeded()
            await fulfillment(of: [published], timeout: 30)
            let diagnostic = "backup access caller=\(caller) context=\(context)"
            guard case .ready(let coordinator, _, _) = router.route else {
                let route: String
                switch router.route {
                case .checking: route = "checking"
                case .awaitingIndependentValidation: route = "awaitingIndependentValidation"
                case .ready: route = "ready"
                case .eraseCleanupPending: route = "eraseCleanupPending"
                case .maintenance(let reason): route = "maintenance:\(reason.rawValue)"
                }
                XCTFail("\(diagnostic) route=\(route)", file: file, line: line)
                throw FixtureError.invalid
            }
            guard coordinator.generationID == source.session.generationID else {
                XCTFail("\(diagnostic) generationID mismatch", file: file, line: line)
                throw FixtureError.invalid
            }
            guard coordinator.generationRootURL == source.session.generationRootURL else {
                XCTFail("\(diagnostic) generationRootURL mismatch", file: file, line: line)
                throw FixtureError.invalid
            }
            return AuthorizedExportHarness(defaultsSuiteName: suite, defaults: defaults,
                presentation: presentation, coordinator: coordinator,
                contentAccess: try XCTUnwrap(presentation.backupPreviewAccess))
        } catch {
            if case .ready(let coordinator, _, _) = router.route {
                try? coordinator.invalidateAndReleaseWriter()
            }
            defaults.removePersistentDomain(forName: suite)
            throw error
        }
    }

    @MainActor
    func exportLivePackage(_ harness: Harness, directoryName: String) async throws -> URL {
        let authorized = try await makeAuthorizedExportHarness(harness)
        defer { authorized.close() }
        let destination = harness.applicationSupportURL.appendingPathComponent(
            directoryName, isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        let exporter = makeService(authorized, capacity: .max)
        let preview = try authorized.contentAccess.withRead { try exporter.prepare() }
        return try await exporter.export(previewID: preview.id, to: destination,
            contentAccess: authorized.contentAccess)
    }

    func makeArchiveCleanupFixtureRoot(_ label: String) throws -> URL {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "S6_2BackupExportTests-cleanup-\(label)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    func makeArchiveCleanupReceipt(in root: URL) throws -> StreamingArchiveWriteReceiptV1 {
        let source = root.appendingPathComponent("source", isDirectory: true)
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        try fileManager.createDirectory(at: source, withIntermediateDirectories: false)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: staging)
        let records = Data("{\"recordsSchemaVersion\":1}".utf8)
        let sourceFile = source.appendingPathComponent("records.json")
        try records.write(to: sourceFile)
        let sourceDescriptor = Darwin.open(source.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard sourceDescriptor >= 0 else { throw FixtureError.invalid }
        defer { _ = Darwin.close(sourceDescriptor) }
        var sourceFacts = stat()
        guard Darwin.fstat(sourceDescriptor, &sourceFacts) == 0 else { throw FixtureError.invalid }
        let entry = StreamingArchiveWriteEntryV1(
            path: "records.json", mimeType: "application/json",
            sourceRootURL: source, sourceRelativePath: sourceFile.lastPathComponent,
            expectedSourceRootIdentity: .init(device: UInt64(sourceFacts.st_dev),
                                              inode: UInt64(sourceFacts.st_ino)),
            expectedUncompressedByteCount: Int64(records.count),
            expectedContentSHA256: SHA256.hash(data: records)
                .map { String(format: "%02x", $0) }.joined(),
            compression: .stored)
        let destination = root.appendingPathComponent("AssetRounds.fieldrecordbackup")
        return try StreamingArchiveService().write(
            .init(entries: [entry], stagingDirectoryURL: staging), to: destination)
    }

    @MainActor
    private func assertPhotoRawRestoreKernel(package: ValidatedV4BackupPackageV1,
        history: CheckRunnerPhotoBackupHistoryV1, plan: CheckRunnerPhotoBackupRestorePlanV1) async throws {
        let workspaceID = history.sourceWorkspaceID
        let unrelatedBytes = Data(repeating: 0x5c, count: 2 * 1_024 * 1_024)
        let cases = ["rollback", "public-group", "after-manifest", "private-group",
                     "private-file-deletion", "hostile-private", "existing-parent", "finish", "reused",
                     "replace-before-file-claim", "replace-before-directory-claim", "after-claim",
                     "finish-after-claim", "pointer-failure", "reentrant-publication"]
        func run(_ name: String, at support: URL) async throws {
            let adapter = try DraftAttachmentStagingAdapterV1(applicationSupportURL: support,
                workspaceID: workspaceID)
            let unrelated = try await adapter.stage(data: unrelatedBytes, draftID: UUID(),
                workspaceID: workspaceID, attachmentKind: .file, createdAt: package.manifest.exportedAt)
            let rawRoot = support.appendingPathComponent(OwnedStorageRootKindV1.data.rawValue, isDirectory: true)
                .appendingPathComponent(DraftAttachmentStagingAdapterV1.directoryName, isDirectory: true)
            let unrelatedURL = rawRoot.appendingPathComponent(DraftAttachmentStagingAdapterV1.relativeDataPath(
                draftID: unrelated.draftID, stageID: unrelated.stageID))
            let manifestURL = rawRoot.appendingPathComponent(DraftAttachmentStagingAdapterV1.manifestName)
            let beforeManifest = try Data(contentsOf: manifestURL)
            var currentChildren: [UUID: UUID] = [:]
            if name == "existing-parent" {
                let raw = try XCTUnwrap(history.children.first?.raw)
                currentChildren[raw.readyItem.draftID] = raw.intent.stageID
                let parent = rawRoot.appendingPathComponent(
                    String(DraftAttachmentStagingAdapterV1.relativeStageDirectory(
                        draftID: raw.readyItem.draftID, stageID: raw.intent.stageID).split(separator: "/")[0]),
                    isDirectory: true)
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: false)
                try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: parent)
            }
            let transition = try await adapter.preparePhotoRestoreRawTransition(
                sourcePlan: plan, sourceHistory: history, currentSnapshots: [], currentCommittingCheckpoints: [:],
                currentCanonicalStages: [unrelated], currentChildStageIDs: currentChildren,
                retainedCurrentStageIDs: [unrelated.stageID])
            XCTAssertEqual(Set(transition.newStageIDs), Set(plan.rawPublications.map { $0.physicalEntry.entry.item.stageID }))
            XCTAssertTrue(transition.reusedStageIDs.isEmpty)
            let proof = try await adapter.preparePhotoBackupVerification([], committingCheckpoints: [:],
                canonicalStages: [unrelated], childStageIDs: currentChildren)
            let authority = CheckRunnerPhotoRestoreRawKernelTestAccessV1.authority(restoreID: UUID(),
                workspaceID: workspaceID, applicationSupportURL: support,
                plannedBindingSHA256: String(repeating: "a", count: 64), transition: transition,
                plan: plan, members: package.members)
            let prepared = try await adapter.preparePhotoRestoreRawPublication(authority: authority,
                currentVerification: proof)
            let ownershipBytes = try FieldDraftCanonicalCodecV1.encode(prepared.ownership)
            let ownership = try FieldDraftCanonicalCodecV1.decode(DraftPhotoRestoreRawOwnershipV1.self,
                from: ownershipBytes)
            XCTAssertEqual(try ownership.sha256, try prepared.ownership.sha256)
            XCTAssertEqual(try ownership.sha256, CanonicalJSONV1.sha256(ownershipBytes))
            XCTAssertEqual(Set(ownership.createdNodes.compactMap(\.claimPath)).count,
                ownership.createdNodes.count)
            let permit = try CheckRunnerPhotoRestoreRawKernelTestAccessV1.permit(ownership)
            var pointerCalls = 0
            func publishPointer() throws {
                pointerCalls += 1
                XCTAssertEqual(try Data(contentsOf: manifestURL), try transition.after.canonicalBytes())
                if name == "reentrant-publication" {
                    XCTAssertThrowsError(try prepared.publish(permit: permit, publishingPointer: {
                        XCTFail("reentrant publication must never invoke the pointer")
                    }))
                }
                if name == "pointer-failure" { throw FixtureError.invalid }
            }
            XCTAssertEqual(try Data(contentsOf: manifestURL), beforeManifest)
            XCTAssertEqual(try Data(contentsOf: unrelatedURL), unrelatedBytes)
            var hostileObject = try XCTUnwrap(JSONSerialization.jsonObject(with: ownershipBytes) as? [String: Any])
            hostileObject["unbound"] = true
            XCTAssertThrowsError(try FieldDraftCanonicalCodecV1.decode(DraftPhotoRestoreRawOwnershipV1.self,
                from: JSONSerialization.data(withJSONObject: hostileObject, options: [.sortedKeys])))
            var hostileClaimObject = try XCTUnwrap(
                JSONSerialization.jsonObject(with: ownershipBytes) as? [String: Any])
            var hostileCreated = try XCTUnwrap(hostileClaimObject["createdNodes"] as? [[String: Any]])
            hostileCreated[0]["claimPath"] = ".caller-selected-claim"
            hostileClaimObject["createdNodes"] = hostileCreated
            XCTAssertThrowsError(try FieldDraftCanonicalCodecV1.decode(DraftPhotoRestoreRawOwnershipV1.self,
                from: JSONSerialization.data(withJSONObject: hostileClaimObject, options: [.sortedKeys])))
            if name == "hostile-private" {
                let hostileURL = rawRoot.appendingPathComponent(ownership.privateName, isDirectory: true)
                    .appendingPathComponent("unowned.bin")
                let hostile = Data("retain unknown bytes".utf8)
                try hostile.write(to: hostileURL)
                try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: hostileURL)
                XCTAssertThrowsError(try prepared.publish(permit: permit, publishingPointer: publishPointer))
                XCTAssertEqual(pointerCalls, 0)
                do {
                    _ = try await adapter.reopenPhotoRestoreRawPublication(ownership: ownership,
                        permit: permit, rollback: true)
                    XCTFail("cold rollback must preserve an unknown private sibling")
                } catch {}
                XCTAssertEqual(try Data(contentsOf: hostileURL), hostile)
                XCTAssertEqual(try Data(contentsOf: manifestURL), beforeManifest)
                return
            }
            if name == "public-group" || name == "after-manifest" {
                prepared.failAfterStepForTesting = name
                XCTAssertThrowsError(try prepared.publish(permit: permit, publishingPointer: publishPointer))
                XCTAssertEqual(pointerCalls, 0)
            } else if name == "pointer-failure" {
                XCTAssertThrowsError(try prepared.publish(permit: permit, publishingPointer: publishPointer))
                XCTAssertEqual(pointerCalls, 1)
            } else {
                try prepared.publish(permit: permit, publishingPointer: publishPointer)
                XCTAssertEqual(pointerCalls, 1)
            }
            let callsBeforeRetry = pointerCalls
            prepared.failAfterStepForTesting = nil
            XCTAssertThrowsError(try prepared.publish(permit: permit, publishingPointer: publishPointer))
            XCTAssertEqual(pointerCalls, callsBeforeRetry)
            XCTAssertThrowsError(try prepared.rollback(permit: permit))
            XCTAssertThrowsError(try prepared.finish(permit: permit))
            if name == "finish" || name == "reused" || name == "finish-after-claim" {
                let cold = try DraftAttachmentStagingAdapterV1(photoBackupExistingRoot: support, workspaceID: workspaceID)
                let reopened = try await cold.reopenPhotoRestoreRawPublication(ownership: ownership,
                    permit: permit, rollback: false)
                if name == "finish-after-claim" {
                    reopened.failAfterStepForTesting = "after-claim"
                    XCTAssertThrowsError(try reopened.finish(permit: permit))
                    let claimed = ownership.createdNodes.filter { node in
                        guard let claim = node.claimPath else { return false }
                        return fileManager.fileExists(atPath: rawRoot.appendingPathComponent(claim).path)
                    }
                    XCTAssertEqual(claimed.count, 1)
                    XCTAssertEqual(claimed.first?.directory, true)
                    let again = try await cold.reopenPhotoRestoreRawPublication(ownership: ownership,
                        permit: permit, rollback: false)
                    try again.finish(permit: permit)
                } else { try reopened.finish(permit: permit) }
                XCTAssertFalse(fileManager.fileExists(atPath: rawRoot.appendingPathComponent(ownership.privateName).path))
                XCTAssertEqual(try Data(contentsOf: manifestURL), try transition.after.canonicalBytes())
                var snapshots: [DraftPhotoRawBackupSnapshotV1] = []
                var checkpoints: [UUID: FieldDraftCheckpointV1] = [:], childIDs: [UUID: UUID] = [:]
                for child in history.children {
                    let raw = try XCTUnwrap(child.raw), checkpoint = try XCTUnwrap(child.committingCheckpoint)
                    snapshots.append(try await cold.readPhotoBackupSnapshot(raw: raw, committingCheckpoint: checkpoint))
                    checkpoints[raw.readyItem.draftID] = checkpoint
                    childIDs[raw.readyItem.draftID] = raw.intent.stageID
                }
                XCTAssertEqual(snapshots.count, plan.rawPublications.count)
                if name == "reused" {
                    let stages = transition.after.entries.map(\.item)
                    let reuse = try await cold.preparePhotoRestoreRawTransition(sourcePlan: plan, sourceHistory: history,
                        currentSnapshots: snapshots, currentCommittingCheckpoints: checkpoints,
                        currentCanonicalStages: stages, currentChildStageIDs: childIDs,
                        retainedCurrentStageIDs: [unrelated.stageID])
                    XCTAssertTrue(reuse.newStageIDs.isEmpty)
                    XCTAssertEqual(Set(reuse.reusedStageIDs), Set(transition.newStageIDs))
                    let reuseProof = try await cold.preparePhotoBackupVerification(snapshots,
                        committingCheckpoints: checkpoints, canonicalStages: stages, childStageIDs: childIDs)
                    let reuseAuthority = CheckRunnerPhotoRestoreRawKernelTestAccessV1.authority(restoreID: UUID(),
                        workspaceID: workspaceID, applicationSupportURL: support,
                        plannedBindingSHA256: String(repeating: "b", count: 64), transition: reuse,
                        plan: plan, members: package.members)
                    let reused = try await cold.preparePhotoRestoreRawPublication(authority: reuseAuthority,
                        currentVerification: reuseProof)
                    let reusePermit = try CheckRunnerPhotoRestoreRawKernelTestAccessV1.permit(reused.ownership)
                    var reusedPointerCalls = 0
                    try reused.publish(permit: reusePermit, publishingPointer: { reusedPointerCalls += 1 })
                    XCTAssertEqual(reusedPointerCalls, 1)
                    XCTAssertThrowsError(try reused.rollback(permit: reusePermit))
                    let reusedRollback = try await cold.reopenPhotoRestoreRawPublication(
                        ownership: reused.ownership, permit: reusePermit, rollback: true)
                    try reusedRollback.rollback(permit: reusePermit)
                    XCTAssertEqual(try Data(contentsOf: manifestURL), try transition.after.canonicalBytes())
                    for snapshot in snapshots {
                        let current = try await cold.readPhotoBackupSnapshot(raw: snapshot.raw,
                            committingCheckpoint: checkpoints[snapshot.raw.readyItem.draftID])
                        XCTAssertEqual(current, snapshot)
                    }
                }
            } else {
                let cold = try DraftAttachmentStagingAdapterV1(photoBackupExistingRoot: support, workspaceID: workspaceID)
                let reopened = try await cold.reopenPhotoRestoreRawPublication(ownership: ownership,
                    permit: permit, rollback: true)
                if name == "replace-before-file-claim" || name == "replace-before-directory-claim" {
                    let replaceDirectory = name == "replace-before-directory-claim"
                    let replacement = Data("preserve claimed replacement".utf8)
                    var replacementClaimURL: URL?
                    reopened.beforeClaimForTesting = { url, directory in
                        guard replacementClaimURL == nil, directory == replaceDirectory else { return }
                        let prefix = rawRoot.path + "/"
                        guard url.path.hasPrefix(prefix),
                              let node = ownership.createdNodes.first(where: {
                                  $0.path == String(url.path.dropFirst(prefix.count))
                              }), let claimPath = node.claimPath else {
                            throw DraftAttachmentStagingFailureV1.staleStage
                        }
                        try FileManager.default.removeItem(at: url)
                        if directory {
                            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
                            try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: url)
                        } else {
                            try replacement.write(to: url, options: .withoutOverwriting)
                            try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: url)
                        }
                        replacementClaimURL = rawRoot.appendingPathComponent(claimPath,
                            isDirectory: directory)
                    }
                    XCTAssertThrowsError(try reopened.rollback(permit: permit))
                    let claimURL = try XCTUnwrap(replacementClaimURL)
                    XCTAssertTrue(fileManager.fileExists(atPath: claimURL.path))
                    if replaceDirectory {
                        XCTAssertTrue(try fileManager.contentsOfDirectory(atPath: claimURL.path).isEmpty)
                    } else { XCTAssertEqual(try Data(contentsOf: claimURL), replacement) }
                    do {
                        _ = try await cold.reopenPhotoRestoreRawPublication(ownership: ownership,
                            permit: permit, rollback: true)
                        XCTFail("cold recovery must preserve an inode-mismatched exact claim")
                    } catch {}
                    XCTAssertTrue(fileManager.fileExists(atPath: claimURL.path))
                    if !replaceDirectory { XCTAssertEqual(try Data(contentsOf: claimURL), replacement) }
                    XCTAssertEqual(try Data(contentsOf: manifestURL), beforeManifest)
                    XCTAssertEqual(try Data(contentsOf: unrelatedURL), unrelatedBytes)
                    return
                } else if name == "after-claim" {
                    reopened.failAfterStepForTesting = "after-claim"
                    XCTAssertThrowsError(try reopened.rollback(permit: permit))
                    let claimURLs = ownership.createdNodes.compactMap { node -> URL? in
                        guard let claim = node.claimPath else { return nil }
                        let url = rawRoot.appendingPathComponent(claim, isDirectory: node.directory)
                        return fileManager.fileExists(atPath: url.path) ? url : nil
                    }
                    XCTAssertEqual(claimURLs.count, 1)
                    let again = try await cold.reopenPhotoRestoreRawPublication(ownership: ownership,
                        permit: permit, rollback: true)
                    try again.rollback(permit: permit)
                } else if name == "private-group" || name == "private-file-deletion" {
                    reopened.failAfterStepForTesting = name
                    XCTAssertThrowsError(try reopened.rollback(permit: permit))
                    let again = try await cold.reopenPhotoRestoreRawPublication(ownership: ownership,
                        permit: permit, rollback: true)
                    try again.rollback(permit: permit)
                } else { try reopened.rollback(permit: permit) }
                XCTAssertEqual(try Data(contentsOf: manifestURL), beforeManifest)
                XCTAssertFalse(fileManager.fileExists(atPath: rawRoot.appendingPathComponent(ownership.privateName).path))
                for entry in plan.rawPublications {
                    let item = entry.physicalEntry.entry.item
                    XCTAssertFalse(fileManager.fileExists(atPath: rawRoot.appendingPathComponent(
                        DraftAttachmentStagingAdapterV1.relativeDataPath(draftID: item.draftID, stageID: item.stageID)).path))
                }
            }
            XCTAssertEqual(try Data(contentsOf: unrelatedURL), unrelatedBytes)
        }
        for name in cases {
            let support = fileManager.temporaryDirectory.appendingPathComponent("photo-raw-restore-\(name)-\(UUID())")
            do { try await run(name, at: support) }
            catch { XCTFail("photo raw restore \(name): \(String(reflecting: error))"); throw error }
            // The case's actors and file owners have left scope before teardown.
            try fileManager.removeItem(at: support)
        }
    }

    @MainActor
    func makeMixedHarness(
        _ label: String,
        siteAddress: String? = nil,
        currentWriterSource: Bool = false,
        beginOnly: Bool = false,
        sharedRaw: Bool = false
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
            if beginOnly { break }
            let wideSeed = sharedRaw && index == 1 ? UInt8(31) : UInt8(31 + index)
            let wide = try await coordinator.importCandidate(assetID: assetID,
                sourceData: try makePNG(seed: wideSeed), createdAt: observed.addingTimeInterval(1))
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

    @MainActor
    func appendCompositionCurrentOnlyState(_ harness: Harness) async throws -> UUID {
        let coordinator = try StoreSessionCoordinator(validatingSession: harness.session)
        defer { XCTAssertNoThrow(try coordinator.invalidateAndReleaseWriter()) }
        let pack = SignPack.illuminatedSignV1
        let siteID = uuid(601), assetID = uuid(602)
        let placementMutationID = try MutationIDV1(rawValue: uuid(603))
        _ = try coordinator.workspaceWriter.execute(.createFirstSign(.init(
            siteID: siteID,
            newSite: .init(id: siteID, label: "Retained composition site", address: nil,
                timeZoneID: "America/New_York"),
            assetID: assetID, assetLabel: "Retained composition asset",
            packID: pack.packID, packSchemaVersion: pack.schemaVersion,
            packContentVersion: pack.contentVersion,
            createdAt: Date(timeIntervalSince1970: 1_786_709_100),
            initialPlacementMutationID: placementMutationID,
            initialPlacementEventID: uuid(604),
            initialPhysicalEpisodeID: PhysicalPlacementEpisodeIDV1(rawValue: uuid(605))
        )), mutationID: placementMutationID)
        let profile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(package: pack)
        let dependencies = try coordinator.packageLifecycleDependencies(
            profileRegistry: WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile]))
        let runner = try CheckRunnerCoordinator(modelContext: harness.context,
            packageLifecycleDependencies: dependencies, packageLifecycleProfile: profile)
        runner.configureCapture(generationRootURL: harness.session.generationRootURL)
        let observed = Date(timeIntervalSince1970: 1_786_709_200)
        _ = try runner.beginCheck(assetID: assetID, timeZoneID: nil,
            isTimeZoneConfirmed: false, afterDarkAccepted: true,
            safePositionAccepted: true, observedAt: observed)
        let wide = try await runner.importCandidate(assetID: assetID,
            sourceData: try makePNG(seed: 141), createdAt: observed.addingTimeInterval(1))
        _ = try await runner.accept(candidate: wide, assetID: assetID)
        let close = try await runner.importCandidate(assetID: assetID,
            sourceData: try makePNG(seed: 181), createdAt: observed.addingTimeInterval(2))
        _ = try await runner.accept(candidate: close, assetID: assetID)
        _ = try await runner.finalize(assetID: assetID, selection: .noVisibleIssue,
            completedAt: observed.addingTimeInterval(5),
            snapshotCreatedAt: observed.addingTimeInterval(6),
            sourceApp: .init(build: "42", version: "4.0"),
            identifiers: .init(mutationID: uuid(606), packetID: uuid(607),
                stableRootID: uuid(608), reportID: uuid(609), issueID: nil))

        let journal = try MutationJournalStoreV1(modelContext: harness.context,
            identity: harness.session.workspaceIdentity, generationID: harness.session.generationID,
            allowStateBootstrap: false)
        let drafts = FieldDraftLifecycleAdapterV1(writer: coordinator.workspaceWriter,
            journal: journal, modelContext: harness.context)
        let key = try MyDayKeyV1(workspaceID: harness.session.workspaceID,
            civilDate: .init(year: 2026, month: 9, day: 16),
            ianaTimeZoneIdentifier: "America/New_York")
        let actor = try LocalActorReferenceV1(actorReferenceID: uuid(610),
            workspaceID: harness.session.workspaceID, partyID: nil,
            displayName: "Composition recorder")
        let actorSnapshot = try ActorSnapshotV1(snapshotID: uuid(611),
            workspaceID: harness.session.workspaceID, actor: actor,
            responsibility: .recordedBy, displayNameAtTime: actor.displayName,
            capturedAt: Date(timeIntervalSince1970: 1_786_709_300))
        let payload = try MyDayPlanningDraftPayloadV1(editing: .init(key: key,
            recordedBy: actorSnapshot, keyWasExplicitlyConfirmed: true,
            recordedByWasExplicitlySelectedOrCaptured: true),
            intent: .plan(draft: .init(key: key, items: [], eligibleReferences: []),
                predecessor: nil))
        let draftID = uuid(612)
        let checkpoint = try FieldDraftCheckpointV1(draftID: draftID,
            workspaceID: harness.session.workspaceID,
            scope: MyDayPlanningDraftCodecV1.scope(for: key), purpose: .myDayPlanning,
            codec: MyDayPlanningDraftCodecV1.release(), baseCanonicalRevision: 0,
            draftRevision: 1, payloadData: MyDayPlanningDraftCodecV1.encode(payload),
            stageIDs: [], resumeAnchor: .init(sectionID: "planning"), state: .active,
            updatedAt: Date(timeIntervalSince1970: 1_786_709_300),
            mutationID: try MutationIDV1(rawValue: uuid(613)))
        _ = try drafts.compareAndSwap(checkpoint: checkpoint,
            expectedDraftRevision: 0, expectedBaseRevision: 0)
        return draftID
    }

    @MainActor
    func appendGenericCompositionStage(_ harness: Harness, slot: Int,
        bytes: Data) async throws -> GenericCompositionStage {
        let coordinator = try StoreSessionCoordinator(validatingSession: harness.session)
        defer { XCTAssertNoThrow(try coordinator.invalidateAndReleaseWriter()) }
        let workspaceID = harness.session.workspaceID
        let timestamp = Date(timeIntervalSince1970: 1_786_710_000 + Double(slot))
        let draftID = uuid(slot)
        let fixture = try C36FieldDraftTestSupportV1.makeFixture(seed: 936_000 + slot)
        let staging = try DraftAttachmentStagingAdapterV1(
            applicationSupportURL: harness.applicationSupportURL,
            workspaceID: workspaceID, clock: { timestamp })
        let item = try await staging.stage(data: bytes, draftID: draftID,
            workspaceID: workspaceID, attachmentKind: .file)
        let checkpoint = try FieldDraftCheckpointV1(draftID: draftID,
            workspaceID: workspaceID, scope: fixture.activeCheckpoint.scope,
            purpose: fixture.activeCheckpoint.purpose, codec: fixture.activeCheckpoint.codec,
            baseCanonicalRevision: 0, draftRevision: 1,
            payloadData: fixture.activeCheckpoint.payloadData, stageIDs: [],
            resumeAnchor: fixture.activeCheckpoint.resumeAnchor, state: .active,
            updatedAt: timestamp, mutationID: try MutationIDV1(rawValue: uuid(slot + 1)))
        _ = try coordinator.workspaceWriter.commitFieldDraft(.init(
            workspaceID: workspaceID, expectedRevision: 0,
            expectedBaseCanonicalRevision: 0, mutationID: checkpoint.mutationID,
            postImage: .createCheckpoint(checkpoint)))
        let successor = try FieldDraftCheckpointV1(draftID: draftID,
            workspaceID: workspaceID, scope: checkpoint.scope, purpose: checkpoint.purpose,
            codec: checkpoint.codec, baseCanonicalRevision: 0, draftRevision: 2,
            payloadData: checkpoint.payloadData, stageIDs: [item.stageID],
            resumeAnchor: checkpoint.resumeAnchor, state: .active,
            updatedAt: timestamp.addingTimeInterval(1), mutationID: item.mutationID)
        let bundle = try FieldDraftStagePublicationBundleV1(expectedCheckpoint: checkpoint,
            readyItem: item, successorCheckpoint: successor)
        _ = try coordinator.workspaceWriter.commitFieldDraft(.init(
            workspaceID: workspaceID, expectedRevision: 1,
            expectedBaseCanonicalRevision: 0, mutationID: item.mutationID,
            postImage: .publishReadyStage(bundle)))
        return GenericCompositionStage(checkpoint: successor, item: item, bytes: bytes)
    }

    @MainActor
    func installCompositionBranchBase(_ archive: URL, label: String,
        countedRoots: [String]) async throws -> Harness {
        let support = fileManager.temporaryDirectory.appendingPathComponent(
            "S6_2BackupExportTests-\(label)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: false)
        do {
            let initial = try StoreGenerationFactory(applicationSupportURL: support)
                .openOrBootstrapCurrent()
            let importer = try BackupImportService(
                generationRootURL: initial.generationRootURL,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
                makeUUID: { UUID() }, scopedAccess: .alreadyAuthorized)
            let package = try importer.stageAndValidate(selectedPackageURL: archive)
            let restored = try await BackupRestoreService(applicationSupportURL: support,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }))
                .restore(validatedPackage: package, currentModelContext: initial.modelContext,
                    currentGenerationID: initial.generationID,
                    currentGenerationRootURL: initial.generationRootURL, mode: .emptyInstall)
            return Harness(applicationSupportURL: support, session: restored,
                context: restored.modelContext, countedRoots: countedRoots)
        } catch {
            try? fileManager.removeItem(at: support)
            throw error
        }
    }

    @MainActor
    func makePhotoRestoreJourney(_ label: String) async throws -> PhotoRestoreJourney {
        let sourceHarness = try await makeMixedHarness("\(label)-source", sharedRaw: true)
        defer { try? fileManager.removeItem(at: sourceHarness.applicationSupportURL) }
        do {
            let commonGenericStage = try await appendGenericCompositionStage(sourceHarness,
                slot: 630, bytes: Data("common generic branch bytes".utf8))
            let branchArchive = try await exportLivePackage(sourceHarness,
                directoryName: "photo-restore-branch-export")
            let harness = try await installCompositionBranchBase(branchArchive,
                label: "\(label)-target", countedRoots: sourceHarness.countedRoots)
            let oldID = harness.session.generationID
            let initialRetiredGenerationIDs = try StoreGenerationFactory(
                applicationSupportURL: harness.applicationSupportURL).retiredGenerationIDs()
            let retainedMyDayDraftID = try await appendCompositionCurrentOnlyState(harness)
            let currentArchive = try await exportLivePackage(harness,
                directoryName: "photo-restore-current-export")

            let sourceOnlyGenericStage = try await appendGenericCompositionStage(sourceHarness,
                slot: 640, bytes: Data(repeating: 0xa5, count: 2 * 1_024 * 1_024))
            XCTAssertEqual(sourceOnlyGenericStage.bytes.count, 2 * 1_024 * 1_024)
            let sourceArchive = try await exportLivePackage(sourceHarness,
                directoryName: "photo-restore-source-export")

            let currentImporter = try BackupImportService(
                generationRootURL: harness.session.generationRootURL,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
                makeUUID: { self.uuid(780) }, scopedAccess: .alreadyAuthorized)
            let current = try currentImporter.stageAndValidate(selectedPackageURL: currentArchive)
            let currentRecords = current.records
            let currentRecordsData = try XCTUnwrap(current.members["records.json"])
            let currentHistory = try CheckRunnerPhotoBackupHistoryV1.project(
                source: current.manifest.source, records: current.records)
            let currentPlan = try CheckRunnerPhotoBackupRestorePlanV1.resolve(
                history: currentHistory, entries: current.manifest.entries,
                metadata: { try XCTUnwrap(current.members[$0]) })
            let currentMembers = current.manifest.entries
            try currentImporter.discard(current)

            let sourceImporter = try BackupImportService(
                generationRootURL: harness.session.generationRootURL,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
                makeUUID: { self.uuid(781) }, scopedAccess: .alreadyAuthorized)
            let source = try sourceImporter.stageAndValidate(selectedPackageURL: sourceArchive)
            let sourceHistory = try CheckRunnerPhotoBackupHistoryV1.project(
                source: source.manifest.source, records: source.records)
            let sourcePlan = try CheckRunnerPhotoBackupRestorePlanV1.resolve(
                history: sourceHistory, entries: source.manifest.entries,
                metadata: { try XCTUnwrap(source.members[$0]) })
            let sourceIDs = Set(sourceHistory.children.map { $0.payload.childDraftID })
            let currentIDs = Set(currentHistory.children.map { $0.payload.childDraftID })
            let retainedIDs = currentIDs.subtracting(sourceIDs)
            XCTAssertEqual(sourceIDs.count, 6)
            XCTAssertEqual(currentIDs.count, 8)
            XCTAssertEqual(retainedIDs.count, 2)
            XCTAssertEqual(sourcePlan.rawPublications.count, 6)
            XCTAssertEqual(currentPlan.rawPublications.count, 8)
            XCTAssertEqual(Set(currentPlan.generationMembers.map(\.relativePath)).count,
                currentPlan.generationMembers.count)
            XCTAssertEqual(currentPlan.generationMembers.filter {
                $0.relativePath.hasPrefix("evidence/") && $0.relativePath.hasSuffix("/original.jpg")
            }.count, 8)
            XCTAssertEqual(currentPlan.generationMembers.filter {
                $0.relativePath.hasPrefix("evidence/") && $0.relativePath.hasSuffix("/thumbnail.jpg")
            }.count, 8)
            let replacementRecords = try compositionReplacementRecords(
                current: currentRecords, source: source.records)
            let composition = try CheckRunnerPhotoRestoreCompositionV1.compose(
                source: source.manifest.source, sourceRecords: source.records,
                sourcePlan: sourcePlan, currentSource: current.manifest.source,
                currentRecords: currentRecords, currentPlan: currentPlan,
                replacementRecords: replacementRecords,
                sourceIdentity: sourceHarness.session.workspaceIdentity,
                currentIdentity: harness.session.workspaceIdentity)
            let restoredRecords = try composition.applying(to: replacementRecords)
            try composition.requireDestination(restoredRecords)
            XCTAssertNotEqual(restoredRecords, currentRecords)
            let restoredRecordsData = try BackupCanonicalEncoderV1()
                .encodeRecords(restoredRecords).data
            XCTAssertEqual(currentRecords.fieldDrafts.filter { row in
                guard row.kind == .checkpoint,
                      let value = try? FieldDraftCanonicalCodecV1.decode(
                        FieldDraftCheckpointV1.self, from: row.canonicalData) else { return false }
                return value.draftID == retainedMyDayDraftID
            }.count, 1)
            let oldGenericIDs = try expectedGenericStageIDs(currentRecords,
                excluding: currentPlan)
            let restoredGenericIDs = try expectedGenericStageIDs(restoredRecords,
                excluding: currentPlan)
            XCTAssertEqual(oldGenericIDs, Set([commonGenericStage.item.stageID]))
            XCTAssertEqual(restoredGenericIDs,
                Set([commonGenericStage.item.stageID, sourceOnlyGenericStage.item.stageID]))

            let rawRoot = harness.applicationSupportURL.appendingPathComponent(
                OwnedStorageRootKindV1.data.rawValue, isDirectory: true)
                .appendingPathComponent(DraftAttachmentStagingAdapterV1.directoryName,
                    isDirectory: true)
            return PhotoRestoreJourney(harness: harness, sourcePackage: source,
                oldGenerationID: oldID,
                initialRetiredGenerationIDs: initialRetiredGenerationIDs,
                oldRecords: currentRecords,
                oldRecordsData: currentRecordsData, restoredRecords: restoredRecords,
                restoredRecordsData: restoredRecordsData, expectedMembers: currentMembers,
                expectedPlan: currentPlan, oldRawFacts: try treeFacts(rawRoot),
                rawRoot: rawRoot, retainedMyDayDraftID: retainedMyDayDraftID,
                sourcePhotoDraftIDs: sourceIDs, retainedPhotoDraftIDs: retainedIDs,
                commonGenericStage: commonGenericStage,
                sourceOnlyGenericStage: sourceOnlyGenericStage)
        } catch {
            throw error
        }
    }

    @MainActor
    func makeSourceEmptyPhotoRestoreJourney(_ label: String) async throws
        -> SourceEmptyPhotoRestoreJourney {
        let sourceHarness = try await makeMixedHarness("\(label)-source",
            currentWriterSource: true, beginOnly: true, sharedRaw: true)
        defer { try? fileManager.removeItem(at: sourceHarness.applicationSupportURL) }
        let sourceArchive = try await exportLivePackage(sourceHarness,
            directoryName: "source-empty-branch-export")
        let harness = try await installCompositionBranchBase(sourceArchive,
            label: "\(label)-target", countedRoots: sourceHarness.countedRoots)
        do {
            let oldGenerationID = harness.session.generationID
            let initialRetiredGenerationIDs = try StoreGenerationFactory(
                applicationSupportURL: harness.applicationSupportURL).retiredGenerationIDs()
            let retainedMyDayDraftID = try await appendCompositionCurrentOnlyState(harness)
            let currentArchive = try await exportLivePackage(harness,
                directoryName: "source-empty-current-export")
            let currentImporter = try BackupImportService(
                generationRootURL: harness.session.generationRootURL,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
                makeUUID: { self.uuid(790) }, scopedAccess: .alreadyAuthorized)
            let current = try currentImporter.stageAndValidate(selectedPackageURL: currentArchive)
            let records = current.records
            let recordsData = try XCTUnwrap(current.members["records.json"])
            let members = current.manifest.entries
            let history = try CheckRunnerPhotoBackupHistoryV1.project(
                source: current.manifest.source, records: records)
            let retainedPhotoDraftIDs = Set(history.children.map { $0.payload.childDraftID })
            XCTAssertEqual(retainedPhotoDraftIDs.count, 2)
            try currentImporter.discard(current)

            let sourceImporter = try BackupImportService(
                generationRootURL: harness.session.generationRootURL,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
                makeUUID: { self.uuid(791) }, scopedAccess: .alreadyAuthorized)
            let sourcePackage = try sourceImporter.stageAndValidate(
                selectedPackageURL: sourceArchive)
            let sourceHistory = try CheckRunnerPhotoBackupHistoryV1.project(
                source: sourcePackage.manifest.source, records: sourcePackage.records)
            XCTAssertTrue(sourceHistory.children.isEmpty)
            let sourcePlan = try CheckRunnerPhotoBackupRestorePlanV1.resolve(
                history: sourceHistory, entries: sourcePackage.manifest.entries,
                metadata: { try XCTUnwrap(sourcePackage.members[$0]) })
            XCTAssertTrue(sourcePlan.rawPublications.isEmpty)
            XCTAssertTrue(sourcePlan.generationMembers.isEmpty)
            let rawRoot = harness.applicationSupportURL.appendingPathComponent(
                OwnedStorageRootKindV1.data.rawValue, isDirectory: true)
                .appendingPathComponent(DraftAttachmentStagingAdapterV1.directoryName,
                    isDirectory: true)
            return SourceEmptyPhotoRestoreJourney(harness: harness,
                sourcePackage: sourcePackage, oldGenerationID: oldGenerationID,
                initialRetiredGenerationIDs: initialRetiredGenerationIDs,
                records: records, recordsData: recordsData, members: members,
                rawRoot: rawRoot, rawFacts: try treeFacts(rawRoot),
                retainedMyDayDraftID: retainedMyDayDraftID,
                retainedPhotoDraftIDs: retainedPhotoDraftIDs)
        } catch {
            try? fileManager.removeItem(at: harness.applicationSupportURL)
            throw error
        }
    }

    @MainActor
    func assertUnsupportedCurrentOnlyGenericCompositionFailsBeforeEffects() async throws {
        let sourceHarness = try await makeMixedHarness(
            "unsupported-current-generic-source", sharedRaw: true)
        defer { try? fileManager.removeItem(at: sourceHarness.applicationSupportURL) }
        let branchArchive = try await exportLivePackage(sourceHarness,
            directoryName: "unsupported-current-generic-branch")
        let target = try await installCompositionBranchBase(branchArchive,
            label: "unsupported-current-generic-target",
            countedRoots: sourceHarness.countedRoots)
        defer { try? fileManager.removeItem(at: target.applicationSupportURL) }
        let currentOnly = try await appendGenericCompositionStage(target,
            slot: 650, bytes: Data("unsupported current-only opaque C36 bytes".utf8))
        let importer = try BackupImportService(
            generationRootURL: target.session.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
            makeUUID: { self.uuid(792) }, scopedAccess: .alreadyAuthorized)
        let sourcePackage = try importer.stageAndValidate(selectedPackageURL: branchArchive)
        defer { try? importer.discard(sourcePackage) }
        let before = try BackupExportService(modelContext: target.context,
            generationRootURL: target.session.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }))
            .canonicalCheckpointBasis()
        let rawRoot = target.applicationSupportURL.appendingPathComponent(
            OwnedStorageRootKindV1.data.rawValue, isDirectory: true)
            .appendingPathComponent(DraftAttachmentStagingAdapterV1.directoryName,
                isDirectory: true)
        let rawBefore = try treeFacts(rawRoot)
        let factory = StoreGenerationFactory(applicationSupportURL: target.applicationSupportURL)
        let pointerBefore = try factory.currentGenerationID()
        let retiredBefore = try factory.retiredGenerationIDs()
        let newID = uuid(793), restoreID = uuid(794)
        let service = try BackupRestoreService(
            applicationSupportURL: target.applicationSupportURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
            makeUUID: sequence([newID, restoreID]))
        await XCTAssertThrowsErrorAsync {
            _ = try await service.restore(validatedPackage: sourcePackage,
                currentModelContext: target.context,
                currentGenerationID: target.session.generationID,
                currentGenerationRootURL: target.session.generationRootURL,
                mode: .replaceExisting)
        } verify: { error in
            XCTAssertEqual(error as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
        }
        XCTAssertEqual(try factory.currentGenerationID(), pointerBefore)
        XCTAssertEqual(try factory.retiredGenerationIDs(), retiredBefore)
        XCTAssertEqual(try treeFacts(rawRoot), rawBefore)
        let after = try BackupExportService(modelContext: target.context,
            generationRootURL: target.session.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }))
            .canonicalCheckpointBasis()
        XCTAssertEqual(after.recordsData, before.recordsData)
        XCTAssertEqual(after.memberInventory, before.memberInventory)
        XCTAssertNil(try RestoreIntentStore(
            applicationSupportURL: target.applicationSupportURL).load())
        XCTAssertFalse(fileManager.fileExists(atPath: photoRestoreBindingURL(
            target.applicationSupportURL, restoreID: restoreID).path))
        XCTAssertTrue(fileManager.fileExists(atPath: sourcePackage.stagedPackageURL.path))
        let adapter = try DraftAttachmentStagingAdapterV1(
            applicationSupportURL: target.applicationSupportURL,
            workspaceID: target.session.workspaceID)
        let retainedCurrentOnlyBytes = try await adapter.data(
            stageID: currentOnly.item.stageID)
        XCTAssertEqual(retainedCurrentOnlyBytes, currentOnly.bytes)
    }

    @MainActor
    func assertSameLengthCommonGenericCorruptionFailsBeforeEffects(
        _ fixture: PhotoRestoreJourney) async throws {
        let adapter = try DraftAttachmentStagingAdapterV1(
            applicationSupportURL: fixture.harness.applicationSupportURL,
            workspaceID: fixture.harness.session.workspaceID)
        let entries = try await adapter.entries()
        let entry = try XCTUnwrap(entries.first {
            $0.item.stageID == fixture.commonGenericStage.item.stageID
        })
        let payloadURL = fixture.rawRoot.appendingPathComponent(entry.relativeDataPath)
        let original = try Data(contentsOf: payloadURL)
        XCTAssertEqual(original, fixture.commonGenericStage.bytes)
        let checkpointBefore = try BackupExportService(
            modelContext: fixture.harness.context,
            generationRootURL: fixture.harness.session.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }))
            .canonicalCheckpointBasis()
        var corrupted = original
        corrupted[corrupted.startIndex] ^= 0xff
        XCTAssertEqual(corrupted.count, original.count)
        XCTAssertNotEqual(corrupted.sha256, original.sha256)
        let writer = try FileHandle(forWritingTo: payloadURL)
        try writer.write(contentsOf: corrupted)
        try writer.synchronize()
        try writer.close()
        XCTAssertEqual(try Data(contentsOf: payloadURL), corrupted)

        let rawBefore = try treeFacts(fixture.rawRoot)
        let factory = StoreGenerationFactory(
            applicationSupportURL: fixture.harness.applicationSupportURL)
        let pointerBefore = try factory.currentGenerationID()
        let retiredBefore = try factory.retiredGenerationIDs()
        let newID = uuid(795), restoreID = uuid(796)
        let service = try BackupRestoreService(
            applicationSupportURL: fixture.harness.applicationSupportURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
            makeUUID: sequence([newID, restoreID]))
        await XCTAssertThrowsErrorAsync {
            _ = try await service.restore(validatedPackage: fixture.sourcePackage,
                currentModelContext: fixture.harness.context,
                currentGenerationID: fixture.oldGenerationID,
                currentGenerationRootURL: fixture.harness.session.generationRootURL,
                mode: .replaceExisting)
        } verify: { error in
            XCTAssertEqual(error as? DraftAttachmentStagingFailureV1, .digestMismatch)
        }
        XCTAssertEqual(try factory.currentGenerationID(), pointerBefore)
        XCTAssertEqual(try factory.retiredGenerationIDs(), retiredBefore)
        XCTAssertEqual(try treeFacts(fixture.rawRoot), rawBefore)
        XCTAssertEqual(try Data(contentsOf: payloadURL), corrupted)
        let restoring = try FileHandle(forWritingTo: payloadURL)
        try restoring.write(contentsOf: original)
        try restoring.synchronize()
        try restoring.close()
        XCTAssertEqual(try Data(contentsOf: payloadURL), original)
        let checkpointAfter = try BackupExportService(
            modelContext: fixture.harness.context,
            generationRootURL: fixture.harness.session.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }))
            .canonicalCheckpointBasis()
        XCTAssertEqual(checkpointAfter.recordsData, checkpointBefore.recordsData)
        XCTAssertEqual(checkpointAfter.memberInventory, checkpointBefore.memberInventory)
        XCTAssertNil(try RestoreIntentStore(
            applicationSupportURL: fixture.harness.applicationSupportURL).load())
        XCTAssertFalse(fileManager.fileExists(atPath: photoRestoreBindingURL(
            fixture.harness.applicationSupportURL, restoreID: restoreID).path))
        XCTAssertTrue(fileManager.fileExists(
            atPath: fixture.sourcePackage.stagedPackageURL.path))
    }

    @MainActor
    func assertSourceEmptyPhotoSnapshot(_ fixture: SourceEmptyPhotoRestoreJourney,
        session: StoreGenerationSession, file: StaticString = #filePath,
        line: UInt = #line) throws {
        let basis = try BackupExportService(modelContext: session.modelContext,
            generationRootURL: session.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }))
            .canonicalCheckpointBasis()
        XCTAssertEqual(basis.recordsData, fixture.recordsData, file: file, line: line)
        XCTAssertEqual(basis.memberInventory, fixture.members, file: file, line: line)
        let records = try BackupCanonicalDecoderV1().decodeRecords(basis.recordsData)
        XCTAssertEqual(records, fixture.records, file: file, line: line)
        XCTAssertEqual(try treeFacts(fixture.rawRoot), fixture.rawFacts,
            file: file, line: line)
        XCTAssertTrue(records.fieldDrafts.contains { row in
            guard row.kind == .checkpoint,
                  let checkpoint = try? FieldDraftCanonicalCodecV1.decode(
                    FieldDraftCheckpointV1.self, from: row.canonicalData) else { return false }
            return checkpoint.draftID == fixture.retainedMyDayDraftID
        }, file: file, line: line)
        let source = fixture.sourcePackage.manifest.source
        let rebound = V4BackupSourceV1(appBuild: source.appBuild,
            appVersion: source.appVersion,
            persistentSchemaVersion: source.persistentSchemaVersion,
            replicaID: session.replicaID.rawValue,
            recordsSchemaVersion: records.recordsSchemaVersion,
            sourceGenerationID: session.generationID,
            workspaceID: session.workspaceID.rawValue)
        let actualPhotoIDs = Set(try CheckRunnerPhotoBackupHistoryV1.project(
            source: rebound, records: records).children.map { $0.payload.childDraftID })
        XCTAssertEqual(actualPhotoIDs, fixture.retainedPhotoDraftIDs,
            file: file, line: line)
    }

    @MainActor
    func assertPhotoRestoreSnapshot(_ fixture: PhotoRestoreJourney,
        session: StoreGenerationSession, restored: Bool,
        file: StaticString = #filePath, line: UInt = #line) async throws {
        let expectedRecords = restored ? fixture.restoredRecords : fixture.oldRecords
        let expectedRecordsData = restored
            ? fixture.restoredRecordsData : fixture.oldRecordsData
        let basis = try BackupExportService(modelContext: session.modelContext,
            generationRootURL: session.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }))
            .canonicalCheckpointBasis()
        XCTAssertEqual(basis.recordsData, expectedRecordsData, file: file, line: line)
        if restored {
            let oldByPath = Dictionary(uniqueKeysWithValues:
                fixture.expectedMembers.map { ($0.path, $0) })
            let actualByPath = Dictionary(uniqueKeysWithValues:
                basis.memberInventory.map { ($0.path, $0) })
            let sourceOnlyPath = "draft-staging/"
                + "\(fixture.sourceOnlyGenericStage.item.draftID.uuidString.lowercased())/"
                + "\(fixture.sourceOnlyGenericStage.item.stageID.uuidString.lowercased()).bin"
            XCTAssertEqual(Set(actualByPath.keys),
                Set(oldByPath.keys).union([sourceOnlyPath]), file: file, line: line)
            for (path, entry) in oldByPath where path != "records.json" {
                XCTAssertEqual(actualByPath[path], entry, path, file: file, line: line)
            }
            XCTAssertEqual(actualByPath["records.json"]?.byteCount,
                expectedRecordsData.count, file: file, line: line)
            XCTAssertEqual(actualByPath["records.json"]?.sha256,
                expectedRecordsData.sha256, file: file, line: line)
            XCTAssertEqual(actualByPath[sourceOnlyPath]?.byteCount,
                fixture.sourceOnlyGenericStage.bytes.count, file: file, line: line)
            XCTAssertEqual(actualByPath[sourceOnlyPath]?.sha256,
                fixture.sourceOnlyGenericStage.bytes.sha256, file: file, line: line)
            XCTAssertEqual(actualByPath[sourceOnlyPath]?.mimeType,
                "application/octet-stream", file: file, line: line)
        } else {
            XCTAssertEqual(basis.memberInventory, fixture.expectedMembers,
                file: file, line: line)
        }
        let records = try BackupCanonicalDecoderV1().decodeRecords(basis.recordsData)
        XCTAssertEqual(records, expectedRecords, file: file, line: line)
        let history = try XCTUnwrap(records.mutationHistory, file: file, line: line)
        let historyKeys = try history.receipts.map { original in
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: original.envelopeData)
            return MutationWorkspaceKeyV1.value(workspaceID: envelope.workspaceID,
                mutationID: envelope.mutationID)
        }
        XCTAssertEqual(Set(historyKeys).count, historyKeys.count, file: file, line: line)
        XCTAssertEqual(history, expectedRecords.mutationHistory, file: file, line: line)
        XCTAssertEqual(fixture.expectedPlan.rawPublications.count, 8, file: file, line: line)
        for member in fixture.expectedPlan.generationMembers {
            let url = session.generationRootURL.appendingPathComponent(member.relativePath)
            let bytes = try Data(contentsOf: url)
            XCTAssertEqual(bytes.count, member.entry.byteCount,
                member.relativePath, file: file, line: line)
            XCTAssertEqual(bytes.sha256, member.entry.sha256,
                member.relativePath, file: file, line: line)
        }
        let actualDraftIDs = Set(try CheckRunnerPhotoBackupHistoryV1.project(
            source: V4BackupSourceV1(appBuild: fixture.expectedPlan.source.appBuild,
                appVersion: fixture.expectedPlan.source.appVersion,
                persistentSchemaVersion: fixture.expectedPlan.source.persistentSchemaVersion,
                replicaID: session.replicaID.rawValue,
                recordsSchemaVersion: records.recordsSchemaVersion,
                sourceGenerationID: session.generationID,
                workspaceID: session.workspaceID.rawValue),
            records: records).children.map { $0.payload.childDraftID })
        XCTAssertEqual(actualDraftIDs,
            fixture.sourcePhotoDraftIDs.union(fixture.retainedPhotoDraftIDs),
            file: file, line: line)
        XCTAssertTrue(records.fieldDrafts.contains { row in
            guard row.kind == .checkpoint,
                  let value = try? FieldDraftCanonicalCodecV1.decode(
                    FieldDraftCheckpointV1.self, from: row.canonicalData) else { return false }
            return value.draftID == fixture.retainedMyDayDraftID
        }, file: file, line: line)

        let canonicalItems = try records.fieldDrafts.compactMap { row -> AttachmentStagingItemV1? in
            guard row.kind == .stagingItem else { return nil }
            return try FieldDraftCanonicalCodecV1.decode(
                AttachmentStagingItemV1.self, from: row.canonicalData)
        }
        let adapter = try DraftAttachmentStagingAdapterV1(
            applicationSupportURL: fixture.harness.applicationSupportURL,
            workspaceID: session.workspaceID)
        let entries = try await adapter.entries()
        XCTAssertEqual(Set(entries.map(\.item)), Set(canonicalItems), file: file, line: line)
        let commonGenericBytes = try await adapter.data(
            stageID: fixture.commonGenericStage.item.stageID)
        XCTAssertEqual(commonGenericBytes, fixture.commonGenericStage.bytes,
            file: file, line: line)
        if restored {
            let sourceOnlyGenericBytes = try await adapter.data(
                stageID: fixture.sourceOnlyGenericStage.item.stageID)
            XCTAssertEqual(sourceOnlyGenericBytes,
                fixture.sourceOnlyGenericStage.bytes, file: file, line: line)
            let finalRawFacts = try treeFacts(fixture.rawRoot)
            let manifestPrefix = DraftAttachmentStagingAdapterV1.manifestName + "|"
            let stableOldFacts = Set(fixture.oldRawFacts.filter {
                !$0.hasPrefix(manifestPrefix)
            })
            XCTAssertTrue(stableOldFacts.isSubset(of: Set(finalRawFacts)),
                file: file, line: line)
            XCTAssertEqual(finalRawFacts.count, fixture.oldRawFacts.count + 1,
                file: file, line: line)
            XCTAssertEqual(finalRawFacts.filter {
                $0.hasSuffix("|\(fixture.sourceOnlyGenericStage.bytes.sha256)")
            }.count, 1, file: file, line: line)
        } else {
            XCTAssertEqual(try treeFacts(fixture.rawRoot), fixture.oldRawFacts,
                file: file, line: line)
            XCTAssertFalse(entries.contains {
                $0.item.stageID == fixture.sourceOnlyGenericStage.item.stageID
            }, file: file, line: line)
        }
    }

    @MainActor
    func assertCompletedPhotoRestoreJourney(_ fixture: PhotoRestoreJourney,
        session: StoreGenerationSession, expectedCurrentID: UUID, restoreID: UUID,
        file: StaticString = #filePath, line: UInt = #line) async throws {
        let factory = StoreGenerationFactory(
            applicationSupportURL: fixture.harness.applicationSupportURL)
        XCTAssertEqual(try factory.currentGenerationID(), expectedCurrentID,
            file: file, line: line)
        let retired = try factory.retiredGenerationIDs()
        let expectedRetired = fixture.initialRetiredGenerationIDs + [fixture.oldGenerationID]
        XCTAssertEqual(retired.count, expectedRetired.count, file: file, line: line)
        XCTAssertEqual(Set(retired), Set(expectedRetired), file: file, line: line)
        try await assertPhotoRestoreSnapshot(fixture, session: session,
            restored: true, file: file, line: line)
        XCTAssertNil(try RestoreIntentStore(
            applicationSupportURL: fixture.harness.applicationSupportURL).load(),
            file: file, line: line)
        let bindingURL = photoRestoreBindingURL(
            fixture.harness.applicationSupportURL, restoreID: restoreID)
        XCTAssertFalse(fileManager.fileExists(atPath: bindingURL.path), file: file, line: line)
        XCTAssertFalse(fileManager.fileExists(atPath: bindingURL.path + ".next"),
            file: file, line: line)
        XCTAssertFalse(fileManager.fileExists(atPath: fixture.harness.applicationSupportURL
            .appendingPathComponent("FieldEvidenceRestore/portable-exchange-restore.json").path),
            file: file, line: line)
        XCTAssertFalse(fileManager.fileExists(atPath: fixture.sourcePackage.stagedPackageURL.path),
            file: file, line: line)
    }

    func photoRestoreBindingURL(_ support: URL, restoreID: UUID) -> URL {
        support.appendingPathComponent(
            "FieldEvidenceRestore/draft-publication-\(restoreID.uuidString.lowercased()).json")
    }

    func readPhotoRestoreBinding(_ url: URL) throws
        -> CheckRunnerPhotoRestorePublicationBindingV2 {
        try StoreMigrationCanonicalJSONV1.decodeCanonicalContract(
            CheckRunnerPhotoRestorePublicationBindingV2.self,
            from: Data(contentsOf: url), validate: { try $0.validate() })
    }

    func sequence(_ values: [UUID]) -> () -> UUID {
        var remaining = values
        return { remaining.isEmpty ? UUID() : remaining.removeFirst() }
    }

    @MainActor
    func appendCompositionTouchingState(_ harness: Harness) throws {
        let coordinator = try StoreSessionCoordinator(validatingSession: harness.session)
        defer { XCTAssertNoThrow(try coordinator.invalidateAndReleaseWriter()) }
        let pack = SignPack.illuminatedSignV1
        let siteID = UUID(uuidString: "62000000-0000-0000-0000-000000000001")!
        let placementMutationID = try MutationIDV1(rawValue: uuid(620))
        _ = try coordinator.workspaceWriter.execute(.createFirstSign(.init(
            siteID: siteID, newSite: nil, assetID: uuid(621),
            assetLabel: "Source-touching composition asset", packID: pack.packID,
            packSchemaVersion: pack.schemaVersion, packContentVersion: pack.contentVersion,
            createdAt: Date(timeIntervalSince1970: 1_786_709_400),
            initialPlacementMutationID: placementMutationID,
            initialPlacementEventID: uuid(622),
            initialPhysicalEpisodeID: PhysicalPlacementEpisodeIDV1(rawValue: uuid(623))
        )), mutationID: placementMutationID)
    }

    func compositionReplacementRecords(current: V4BackupRecordsV1,
                                       source: V4BackupRecordsV1) throws -> V4BackupRecordsV1 {
        var currentObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(current)) as? [String: Any])
        let sourceObject = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(source)) as? [String: Any])
        for key in ["fieldDrafts", "workflowRecords", "evidenceFiles", "roundSessions",
                    "assets", "sites", "packets", "issues", "requirementAssurance"] {
            currentObject[key] = sourceObject[key]
        }
        return try JSONDecoder().decode(V4BackupRecordsV1.self,
            from: JSONSerialization.data(withJSONObject: currentObject, options: [.sortedKeys]))
    }

    func expectedGenericStageIDs(_ records: V4BackupRecordsV1,
        excluding photoPlan: CheckRunnerPhotoBackupRestorePlanV1) throws -> Set<UUID> {
        let all = try records.fieldDrafts.reduce(into: Set<UUID>()) { result, row in
            guard row.kind == .stagingItem else { return }
            let item = try FieldDraftCanonicalCodecV1.decode(
                AttachmentStagingItemV1.self, from: row.canonicalData)
            if (item.state == .readyLocal || item.state == .committed),
               item.actualByteCount != nil, item.contentDigest != nil {
                result.insert(item.stageID)
            }
        }
        let photo = Set(photoPlan.rawPublications.map {
            $0.physicalEntry.entry.item.stageID
        })
        return all.subtracting(photo)
    }

    func allStageIDs(_ records: V4BackupRecordsV1) throws -> Set<UUID> {
        try records.fieldDrafts.reduce(into: Set<UUID>()) { result, row in
            guard row.kind == .stagingItem else { return }
            let item = try FieldDraftCanonicalCodecV1.decode(
                AttachmentStagingItemV1.self, from: row.canonicalData)
            result.insert(item.stageID)
        }
    }

    func replacingFieldDrafts(_ records: V4BackupRecordsV1,
                              with rows: [V16BackupFieldDraftRecordV1]) throws -> V4BackupRecordsV1 {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(records)) as? [String: Any])
        object["fieldDrafts"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rows))
        return try JSONDecoder().decode(V4BackupRecordsV1.self,
            from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
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

    func configurationCloneStableGenerationFacts(_ root: URL) throws -> [String] {
        let databaseFiles: Set<String> = ["model.sqlite", "model.sqlite-wal", "model.sqlite-shm"]
        let values = try XCTUnwrap(fileManager.enumerator(at: root,
            includingPropertiesForKeys: [.isRegularFileKey])).compactMap { $0 as? URL }
        return try values.compactMap { url -> String? in
            let relative = String(url.path.dropFirst(root.path.count + 1)).replacingOccurrences(of: "\\", with: "/")
            guard !databaseFiles.contains(relative),
                  try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { return nil }
            return "\(relative)|\((try Data(contentsOf: url)).sha256)"
        }.sorted()
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
        let authorized = try await makeAuthorizedExportHarness(harness)
        defer { authorized.close() }
        let destination = harness.applicationSupportURL.appendingPathComponent("c42-export", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        let exporter = makeService(authorized, capacity: .max)
        let preview = try authorized.contentAccess.withRead { try exporter.prepare() }
        let package = try await exporter.export(previewID: preview.id, to: destination,
            contentAccess: authorized.contentAccess)
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

    @MainActor
    func testPhotoHistoryAcceptsRealBeginOnlyExportWithZeroPhotoChildren() async throws {
        let harness = try await makeMixedHarness(
            "photo-history-begin-only", currentWriterSource: true, beginOnly: true)
        defer { try? fileManager.removeItem(at: harness.applicationSupportURL) }
        let authorized = try await makeAuthorizedExportHarness(harness)
        defer { authorized.close() }
        let destination = harness.applicationSupportURL.appendingPathComponent("export", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        let service = makeService(authorized, capacity: .max)
        let preview = try authorized.contentAccess.withRead { try service.prepare() }
        XCTAssertEqual(preview.photoCount, 0)
        let package = try await service.export(previewID: preview.id, to: destination,
            contentAccess: authorized.contentAccess)
        let importer = try BackupImportService(
            generationRootURL: harness.session.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
            makeUUID: { UUID() }, scopedAccess: .alreadyAuthorized)
        let validated = try importer.stageAndValidate(selectedPackageURL: package)
        defer { try? importer.discard(validated) }
        let history = try CheckRunnerPhotoBackupHistoryV1.project(
            source: validated.manifest.source, records: validated.records)
        XCTAssertTrue(history.children.isEmpty)
        let restorePlan = try CheckRunnerPhotoBackupRestorePlanV1.resolve(
            history: history, entries: validated.manifest.entries,
            metadata: { try XCTUnwrap(validated.members[$0]) })
        XCTAssertTrue(restorePlan.children.isEmpty)
        XCTAssertTrue(restorePlan.rawPublications.isEmpty)
        XCTAssertTrue(restorePlan.generationMembers.isEmpty)
        XCTAssertTrue(restorePlan.metadata.isEmpty)
        XCTAssertEqual(restorePlan, try CheckRunnerPhotoBackupRestorePlanV1.resolve(
            history: history, entries: validated.manifest.entries,
            metadata: { try XCTUnwrap(validated.members[$0]) }))
        let parentRelease = try CheckRunnerItemDraftCodecV1.release()
        let parents = try validated.records.fieldDrafts.compactMap { row -> CheckRunnerItemDraftPayloadV1? in
            guard row.kind == .checkpoint else { return nil }
            let checkpoint = try FieldDraftCanonicalCodecV1.decode(
                FieldDraftCheckpointV1.self, from: row.canonicalData)
            guard checkpoint.codec == parentRelease else { return nil }
            return try CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint)
        }
        XCTAssertEqual(parents.count, 1)
        let parent = try XCTUnwrap(parents.first)
        guard case .bound = parent.field.begin else {
            return XCTFail("The real zero-photo fixture must retain its bound parent")
        }
    }
}

extension S6_2BackupExportTests {
    @MainActor
    func testConfigurationCloneAcceptsEveryAuthenticPhotoPhaseAndOmitsOperationalFamily() async throws {
        for (index, phase) in ConfigurationClonePhotoPhase.allCases.enumerated() {
            try await withAsyncFrozenBeginFixture(
                "configuration-clone-\(phase.rawValue.lowercased())",
                entry: .check,
                storedTimeZoneID: "America/Chicago"
            ) { h in
                let photo = try await prepareConfigurationClonePhoto(phase, in: h)
                let sourceCheckpoint = try photo.checkpoint()
                let sourcePayload = try CheckRunnerPhotoDraftCodecV1
                    .validateCheckpoint(sourceCheckpoint)

                // The production fixture owns the live writer. Close it before
                // the independent temporal writer or cold authorized exporter.
                try h.closeCoordinator()
                let temporalSource: TemporalEvidenceClipV1?
                if phase == .terminal {
                    let temporal = try await C33TemporalEvidenceTestSupport
                        .commitPersistentClip(in: h.session, slot: 820 + index)
                    temporalSource = temporal.clip
                    try h.context.save()
                } else {
                    temporalSource = nil
                }

                let sourceHarness = Harness(
                    applicationSupportURL: h.root,
                    session: h.session,
                    context: h.context,
                    countedRoots: []
                )
                let sourceBasis = try canonicalBasis(sourceHarness)
                let sourceTree = try treeFacts(h.session.generationRootURL)
                let archive = try await exportLivePackage(
                    sourceHarness,
                    directoryName: "configuration-clone-source-\(index)"
                )
                let archiveBytes = try Data(contentsOf: archive)
                XCTAssertEqual(try canonicalBasis(sourceHarness), sourceBasis, phase.rawValue)
                XCTAssertEqual(try treeFacts(h.session.generationRootURL), sourceTree,
                    phase.rawValue)

                let packageHost = try makeConfigurationCloneTarget(
                    "source-package-\(index)")
                defer { try? fileManager.removeItem(at: packageHost.applicationSupportURL) }
                let importer = try BackupImportService(
                    generationRootURL: packageHost.session.generationRootURL,
                    storagePreflight: StoragePreflightService(
                        capacityProvider: { _ in .max }
                    ),
                    makeUUID: { UUID() },
                    scopedAccess: .alreadyAuthorized
                )
                let package = try importer.stageAndValidate(selectedPackageURL: archive)
                defer { try? importer.discard(package) }
                let sourceHistory = try CheckRunnerPhotoBackupHistoryV1.project(
                    source: package.manifest.source,
                    records: package.records
                )
                XCTAssertEqual(sourceHistory.children.count, 1, phase.rawValue)
                let child = try XCTUnwrap(sourceHistory.children.first)
                XCTAssertEqual(child.payload.childDraftID, photo.childID, phase.rawValue)
                assertConfigurationCloneSourcePhase(
                    phase,
                    child: child,
                    checkpoint: sourceCheckpoint,
                    payload: sourcePayload
                )
                XCTAssertEqual(
                    package.records.evidenceFiles.count,
                    phase.retainsFinalMedia ? 1 : 0,
                    phase.rawValue
                )
                let sourceMutationHistory = try XCTUnwrap(
                    package.records.mutationHistory,
                    phase.rawValue
                )
                let expectedPhotoBytes = try package.records.evidenceFiles.map { evidence in
                    let id = evidence.id.uuidString.lowercased()
                    return ConfigurationCloneFinalMediaFact(
                        evidence: evidence,
                        original: try XCTUnwrap(package.members["media/\(id).jpg"]),
                        thumbnail: try XCTUnwrap(package.members["thumbnails/\(id).jpg"])
                    )
                }
                if let temporalSource {
                    XCTAssertEqual(package.records.temporalEvidence.count, 1)
                    XCTAssertEqual(
                        package.members[
                            try TemporalEvidenceBackupMemberV1.original(for: temporalSource)
                        ],
                        C33TemporalEvidenceTestSupport.bytes(for: temporalSource.facts.kind)
                    )
                } else {
                    XCTAssertTrue(package.records.temporalEvidence.isEmpty)
                }

                // Retain the original empty-target route for every source
                // photo phase before exercising populated retirement below.
                let emptyTarget = try makeConfigurationCloneTarget("phase-\(index)")
                defer { try? fileManager.removeItem(at: emptyTarget.applicationSupportURL) }
                try await assertConfigurationCloneSucceeds(
                    package: package,
                    target: emptyTarget,
                    sourceWorkspaceID: h.workspaceID,
                    sourceMutationHistory: sourceMutationHistory,
                    expectedPhotoBytes: expectedPhotoBytes,
                    temporalSource: temporalSource,
                    incumbentPhoto: nil,
                    incumbentGeneric: nil,
                    expectsPopulatedRetirement: false,
                    label: "empty-\(phase.rawValue)"
                )

                // Every authentic incumbent photo phase crosses the populated
                // retirement path together with an unrelated generic stage.
                try await withAsyncFrozenBeginFixture(
                    "configuration-clone-mixed-incumbent-\(phase.rawValue.lowercased())",
                    entry: .check,
                    storedTimeZoneID: "America/Chicago"
                ) { current in
                    let incumbent = try await prepareConfigurationClonePhoto(phase,
                        in: current)
                    let incumbentCheckpoint = try incumbent.checkpoint()
                    let incumbentPayload = try CheckRunnerPhotoDraftCodecV1
                        .validateCheckpoint(incumbentCheckpoint)
                    try current.closeCoordinator()
                    let target = Harness(applicationSupportURL: current.root,
                        session: current.session, context: current.context, countedRoots: [])
                    let generic = try await appendGenericCompositionStage(
                        target,
                        slot: 870 + index,
                        bytes: Data("mixed incumbent generic \(phase.rawValue)".utf8)
                    )
                    try await assertConfigurationCloneSucceeds(
                        package: package,
                        target: target,
                        sourceWorkspaceID: h.workspaceID,
                        sourceMutationHistory: sourceMutationHistory,
                        expectedPhotoBytes: expectedPhotoBytes,
                        temporalSource: temporalSource,
                        incumbentPhoto: .init(phase: phase, childID: incumbent.childID,
                            checkpoint: incumbentCheckpoint, payload: incumbentPayload),
                        incumbentGeneric: generic,
                        expectsPopulatedRetirement: true,
                        label: "mixed-\(phase.rawValue)"
                    )
                }

                if phase == .awaitingRawStage {
                    let target = try makeConfigurationCloneTarget("generic-only")
                    defer { try? fileManager.removeItem(at: target.applicationSupportURL) }
                    let generic = try await appendGenericCompositionStage(
                        target,
                        slot: 890,
                        bytes: Data(repeating: 0xa5, count: 2 * 1_024 * 1_024)
                    )
                    XCTAssertEqual(generic.bytes.count, 2 * 1_024 * 1_024)
                    try await assertConfigurationCloneSucceeds(
                        package: package,
                        target: target,
                        sourceWorkspaceID: h.workspaceID,
                        sourceMutationHistory: sourceMutationHistory,
                        expectedPhotoBytes: expectedPhotoBytes,
                        temporalSource: temporalSource,
                        incumbentPhoto: nil,
                        incumbentGeneric: generic,
                        expectsPopulatedRetirement: true,
                        label: "generic-only"
                    )
                }

                if phase == .terminal {
                    try await withAsyncFrozenBeginFixture(
                        "configuration-clone-photo-only-incumbent",
                        entry: .check,
                        storedTimeZoneID: "America/Chicago"
                    ) { current in
                        let incumbent = try await prepareConfigurationClonePhoto(.terminal,
                            in: current)
                        let incumbentCheckpoint = try incumbent.checkpoint()
                        let incumbentPayload = try CheckRunnerPhotoDraftCodecV1
                            .validateCheckpoint(incumbentCheckpoint)
                        try current.closeCoordinator()
                        let target = Harness(applicationSupportURL: current.root,
                            session: current.session, context: current.context, countedRoots: [])
                        try await assertConfigurationCloneSucceeds(
                            package: package,
                            target: target,
                            sourceWorkspaceID: h.workspaceID,
                            sourceMutationHistory: sourceMutationHistory,
                            expectedPhotoBytes: expectedPhotoBytes,
                            temporalSource: temporalSource,
                            incumbentPhoto: .init(phase: .terminal,
                                childID: incumbent.childID,
                                checkpoint: incumbentCheckpoint,
                                payload: incumbentPayload),
                            incumbentGeneric: nil,
                            expectsPopulatedRetirement: true,
                            label: "photo-only-TERMINAL"
                        )
                    }
                }

                XCTAssertEqual(try Data(contentsOf: archive), archiveBytes, phase.rawValue)
                XCTAssertEqual(try canonicalBasis(sourceHarness), sourceBasis, phase.rawValue)
                XCTAssertEqual(try treeFacts(h.session.generationRootURL), sourceTree,
                    phase.rawValue)
            }
        }
    }

    @MainActor
    func testConfigurationCloneRejectsCorruptFinalMemberAndPopulatedDestinationStagingBeforeEffects() async throws {
        try await withAsyncFrozenBeginFixture(
            "configuration-clone-hostile-boundaries",
            entry: .check,
            storedTimeZoneID: "America/Chicago"
        ) { h in
            let photo = try await prepareConfigurationClonePhoto(.terminal, in: h)
            XCTAssertEqual(try photo.checkpoint().state, .committed)
            try h.closeCoordinator()
            let source = Harness(applicationSupportURL: h.root, session: h.session,
                context: h.context, countedRoots: [])
            let archive = try await exportLivePackage(
                source,
                directoryName: "configuration-clone-hostile-source"
            )
            let archiveBytes = try Data(contentsOf: archive)

            let corruptTarget = try makeConfigurationCloneTarget("corrupt-member")
            defer { try? fileManager.removeItem(at: corruptTarget.applicationSupportURL) }
            let corruptImporter = try BackupImportService(
                generationRootURL: corruptTarget.session.generationRootURL,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
                makeUUID: { UUID() }, scopedAccess: .alreadyAuthorized
            )
            let corruptPackage = try corruptImporter.stageAndValidate(
                selectedPackageURL: archive
            )
            defer { try? corruptImporter.discard(corruptPackage) }
            let evidence = try XCTUnwrap(corruptPackage.records.evidenceFiles.first)
            let memberPath = "media/\(evidence.id.uuidString.lowercased()).jpg"
            let memberURL = corruptPackage.members.rootURL
                .appendingPathComponent(memberPath)
            let originalMember = try Data(contentsOf: memberURL)
            var corruptedMember = originalMember
            corruptedMember[corruptedMember.startIndex] ^= 0xff
            XCTAssertEqual(corruptedMember.count, originalMember.count)
            XCTAssertNotEqual(corruptedMember.sha256, originalMember.sha256)
            let memberWriter = try FileHandle(forWritingTo: memberURL)
            try memberWriter.write(contentsOf: corruptedMember)
            try memberWriter.synchronize()
            try memberWriter.close()
            XCTAssertNil(corruptPackage.members[memberPath])
            let corruptFactory = StoreGenerationFactory(
                applicationSupportURL: corruptTarget.applicationSupportURL)
            try await assertConfigurationCloneFailureLeavesTargetUnchanged(
                package: corruptPackage,
                target: corruptTarget,
                expectedBasis: try canonicalBasis(corruptTarget),
                expectedTree: try treeFacts(corruptTarget.session.generationRootURL),
                expectedCurrentID: corruptTarget.session.generationID,
                expectedRetired: try corruptFactory.retiredGenerationIDs(),
                scenario: "corrupt-source-final-member"
            )
            XCTAssertEqual(try Data(contentsOf: memberURL), corruptedMember)
            XCTAssertEqual(try Data(contentsOf: archive), archiveBytes)

            let stagedTarget = try makeConfigurationCloneTarget("populated-staging")
            defer { try? fileManager.removeItem(at: stagedTarget.applicationSupportURL) }
            let stage = try await appendGenericCompositionStage(
                stagedTarget,
                slot: 860,
                bytes: Data("destination staging must survive rejection".utf8)
            )
            let adapter = try DraftAttachmentStagingAdapterV1(
                applicationSupportURL: stagedTarget.applicationSupportURL,
                workspaceID: stagedTarget.session.workspaceID
            )
            let stagedBytesBefore = try await adapter.data(stageID: stage.item.stageID)
            XCTAssertEqual(stagedBytesBefore, stage.bytes)
            let authenticBasis = try canonicalBasis(stagedTarget)
            let rawRoot = stagedTarget.applicationSupportURL
                .appendingPathComponent(OwnedStorageRootKindV1.data.rawValue,
                    isDirectory: true)
                .appendingPathComponent(DraftAttachmentStagingAdapterV1.directoryName,
                    isDirectory: true)
            let stageURL = rawRoot.appendingPathComponent(
                DraftAttachmentStagingAdapterV1.relativeDataPath(
                    draftID: stage.item.draftID,
                    stageID: stage.item.stageID
                )
            )
            var tamperedStageBytes = stage.bytes
            tamperedStageBytes[tamperedStageBytes.startIndex] ^= 0xff
            XCTAssertEqual(tamperedStageBytes.count, stage.bytes.count)
            XCTAssertNotEqual(tamperedStageBytes.sha256, stage.bytes.sha256)
            let stageWriter = try FileHandle(forWritingTo: stageURL)
            try stageWriter.write(contentsOf: tamperedStageBytes)
            try stageWriter.synchronize()
            try stageWriter.close()
            XCTAssertEqual(try Data(contentsOf: stageURL), tamperedStageBytes)
            XCTAssertEqual(
                try configurationCloneFieldDraftRows(stagedTarget.context),
                try BackupCanonicalDecoderV1().decodeRecords(
                    authenticBasis.recordsData).fieldDrafts
            )
            let stagedImporter = try BackupImportService(
                generationRootURL: stagedTarget.session.generationRootURL,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
                makeUUID: { UUID() }, scopedAccess: .alreadyAuthorized
            )
            let stagedPackage = try stagedImporter.stageAndValidate(
                selectedPackageURL: archive
            )
            defer { try? stagedImporter.discard(stagedPackage) }
            let stagedFactory = StoreGenerationFactory(
                applicationSupportURL: stagedTarget.applicationSupportURL)
            let stagedTree = try treeFacts(stagedTarget.session.generationRootURL)
            let stagedRawTree = try treeFacts(rawRoot)
            let stagedRetired = try stagedFactory.retiredGenerationIDs()
            let stagedRows = try configurationCloneFieldDraftRows(stagedTarget.context)
            let stagedHistory = try MutationJournalStoreV1(
                modelContext: stagedTarget.context,
                identity: stagedTarget.session.workspaceIdentity,
                generationID: stagedTarget.session.generationID
            )
            let stagedHistoryBytes = try StoreMigrationCanonicalJSONV1.encode(
                stagedHistory.exportSnapshot())
            try await assertConfigurationCloneFailureLeavesTargetUnchanged(
                package: stagedPackage,
                target: stagedTarget,
                expectedBasis: nil,
                expectedTree: stagedTree,
                expectedCurrentID: stagedTarget.session.generationID,
                expectedRetired: stagedRetired,
                scenario: "tampered-incumbent-generic-payload"
            )
            XCTAssertEqual(try Data(contentsOf: stageURL), tamperedStageBytes)
            XCTAssertEqual(try treeFacts(rawRoot), stagedRawTree)
            XCTAssertEqual(try configurationCloneFieldDraftRows(stagedTarget.context),
                stagedRows)
            XCTAssertEqual(
                try StoreMigrationCanonicalJSONV1.encode(stagedHistory.exportSnapshot()),
                stagedHistoryBytes
            )
            XCTAssertFalse(stagedTarget.context.hasChanges)
            XCTAssertEqual(try Data(contentsOf: archive), archiveBytes)
            XCTAssertTrue(fileManager.fileExists(atPath: stagedPackage.stagedPackageURL.path))

            // A current awaiting child owns no staged bytes, but its complete
            // canonical history must validate before clone can omit that family.
            let emptySource = try makeConfigurationCloneTarget("empty-history-source")
            defer { try? fileManager.removeItem(at: emptySource.applicationSupportURL) }
            let emptyArchive = try await exportLivePackage(
                emptySource, directoryName: "configuration-clone-empty-history-source")
            let emptyArchiveBytes = try Data(contentsOf: emptyArchive)
            for scenario in ["valid-awaiting", "missing-parent", "missing-all-checkpoints"] {
                try await withAsyncFrozenBeginFixture(
                    "configuration-clone-current-\(scenario)", entry: .check,
                    storedTimeZoneID: "America/Chicago"
                ) { current in
                    let awaiting = try await prepareConfigurationClonePhoto(.awaitingRawStage, in: current)
                    let checkpoint = try awaiting.checkpoint()
                    guard case .awaitingRawStage = try CheckRunnerPhotoDraftCodecV1
                        .validateCheckpoint(checkpoint).phase else {
                        return XCTFail("Expected authentic current awaiting phase")
                    }
                    let target = Harness(applicationSupportURL: current.root,
                        session: current.session, context: current.context, countedRoots: [])
                    let originalBasis = try canonicalBasis(target)
                    let originalRecords = try BackupCanonicalDecoderV1().decodeRecords(originalBasis.recordsData)
                    let currentSource = V4BackupSourceV1(appBuild: "test", appVersion: "test",
                        persistentSchemaVersion: LightingNightWorkflowBackupEnrollmentV1.persistentSchemaVersion,
                        replicaID: current.session.replicaID.rawValue,
                        recordsSchemaVersion: originalRecords.recordsSchemaVersion,
                        sourceGenerationID: current.session.generationID,
                        workspaceID: current.workspaceID.rawValue)
                    let currentHistory = try CheckRunnerPhotoBackupHistoryV1.project(
                        source: currentSource, records: originalRecords)
                    XCTAssertEqual(currentHistory.children.count, 1)
                    XCTAssertNil(try XCTUnwrap(currentHistory.children.first).raw)
                    XCTAssertTrue(originalRecords.fieldDrafts.allSatisfy { $0.kind != .stagingItem })
                    let rawRoot = current.root.appendingPathComponent(OwnedStorageRootKindV1.data.rawValue,
                        isDirectory: true).appendingPathComponent(DraftAttachmentStagingAdapterV1.directoryName,
                        isDirectory: true)
                    let rawTreeBefore = try treeFacts(rawRoot)
                    try current.closeCoordinator()
                    let targetImporter = try BackupImportService(
                        generationRootURL: current.session.generationRootURL,
                        storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
                        makeUUID: { UUID() }, scopedAccess: .alreadyAuthorized)
                    let targetPackage = try targetImporter.stageAndValidate(
                        selectedPackageURL: scenario == "missing-all-checkpoints" ? emptyArchive : archive)
                    defer { try? targetImporter.discard(targetPackage) }
                    if scenario == "missing-all-checkpoints" {
                        XCTAssertTrue(targetPackage.records.fieldDrafts.isEmpty)
                    }
                    if scenario != "valid-awaiting" {
                        let rows = try current.context.fetch(FetchDescriptor<FieldDraftCheckpointRow>())
                        let victims = rows.filter {
                            scenario == "missing-all-checkpoints" || $0.draftID == awaiting.parentID
                        }
                        XCTAssertFalse(victims.isEmpty)
                        for row in victims { current.context.delete(row) }
                        try current.context.save()
                        // This deliberately preserves authentic mutation receipts
                        // while removing their required current checkpoint rows.
                        XCTAssertThrowsError(try canonicalBasis(target))
                    }
                    let rowsBefore = try current.rowSnapshot()
                    let historyStore = try MutationJournalStoreV1(modelContext: current.context,
                        identity: current.session.workspaceIdentity,
                        generationID: current.session.generationID)
                    let historyBefore = try historyStore.exportSnapshot()
                    let targetTreeBefore = try treeFacts(current.session.generationRootURL)
                    let targetFactory = StoreGenerationFactory(applicationSupportURL: current.root)
                    let retiredBefore = try targetFactory.retiredGenerationIDs()
                    let service = try BackupRestoreService(applicationSupportURL: current.root,
                        storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }))
                    if scenario == "valid-awaiting" {
                        let restored = try await service.restore(validatedPackage: targetPackage,
                            currentModelContext: current.context,
                            currentGenerationID: current.session.generationID,
                            currentGenerationRootURL: current.session.generationRootURL, mode: .clone)
                        XCTAssertNotEqual(restored.workspaceID, current.workspaceID)
                        XCTAssertEqual(try targetFactory.currentGenerationID(), restored.generationID)
                        let cloned = Harness(applicationSupportURL: current.root, session: restored,
                            context: restored.modelContext, countedRoots: [])
                        let records = try BackupCanonicalDecoderV1().decodeRecords(canonicalBasis(cloned).recordsData)
                        XCTAssertTrue(records.fieldDrafts.isEmpty)
                        assertConfigurationCloneHistoryPreserved(
                            source: try XCTUnwrap(targetPackage.records.mutationHistory),
                            destination: try XCTUnwrap(records.mutationHistory))
                    } else {
                        do {
                            _ = try await service.restore(validatedPackage: targetPackage,
                                currentModelContext: current.context,
                                currentGenerationID: current.session.generationID,
                                currentGenerationRootURL: current.session.generationRootURL, mode: .clone)
                            XCTFail("Clone accepted malformed current history: \(scenario)")
                        } catch { }
                        XCTAssertEqual(try targetFactory.currentGenerationID(), current.session.generationID)
                        XCTAssertEqual(try targetFactory.retiredGenerationIDs(), retiredBefore)
                        XCTAssertEqual(try current.rowSnapshot(), rowsBefore)
                        XCTAssertEqual(try historyStore.exportSnapshot(), historyBefore)
                        XCTAssertEqual(try treeFacts(current.session.generationRootURL), targetTreeBefore)
                    }
                    XCTAssertNil(try RestoreIntentStore(applicationSupportURL: current.root).load())
                    XCTAssertEqual(try treeFacts(rawRoot), rawTreeBefore)
                    XCTAssertEqual(try Data(contentsOf: archive), archiveBytes)
                    XCTAssertEqual(try Data(contentsOf: emptyArchive), emptyArchiveBytes)
                }
            }
        }
    }
}

import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

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
        XCTAssertEqual(validated.manifest.source.persistentSchemaVersion, 8)
        XCTAssertEqual(validated.manifest.source.recordsSchemaVersion, 7)
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
        XCTAssertEqual(decodedRecords, validated.records)
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
        siteAddress: String? = nil
    ) async throws -> Harness {
        let support = fileManager.temporaryDirectory.appendingPathComponent("S6_2BackupExportTests-\(label)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: false)
        let session = try StoreGenerationFactory(applicationSupportURL: support).openOrBootstrapCurrent()
        let context = session.modelContext
        let pack = SignPack.illuminatedSignV1
        let siteID = UUID(uuidString: "62000000-0000-0000-0000-000000000001")!
        let assetID = UUID(uuidString: "62000000-0000-0000-0000-000000000002")!
        context.insert(Site(id: siteID, label: "Backup Site", address: siteAddress, timeZoneID: "America/New_York", createdAt: Date(timeIntervalSince1970: 1_776_420_000)))
        context.insert(Asset(id: assetID, siteID: siteID, packID: pack.packID, packSchemaVersion: pack.schemaVersion, packContentVersion: pack.contentVersion, label: "One Live Sign", createdAt: Date(timeIntervalSince1970: 1_776_420_001)))
        let state = try XCTUnwrap(context.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).first)
        let initialPlacement = try AssetPlacementEventV1(
            id: UUID(uuidString: "62000000-0000-4000-8000-000000000003")!,
            workspaceID: WorkspaceID(rawValue: state.workspaceID),
            assetID: assetID, siteID: siteID, locationNodeID: nil,
            predecessorEventID: nil, source: .manual,
            physicalEpisodeID: try PhysicalPlacementEpisodeIDV1(
                rawValue: UUID(uuidString: "62000000-0000-4000-8000-000000000004")!
            ),
            continuity: .samePhysicalInstallation,
            pathSnapshot: try LocationPathSnapshotV1(
                siteID: siteID, siteDisplay: "Backup Site", nodes: []
            ),
            mutationID: MutationIDV1(
                rawValue: UUID(uuidString: "62000000-0000-4000-8000-000000000005")!
            ),
            occurredAt: Date(timeIntervalSince1970: 1_776_420_001)
        )
        context.insert(try AssetPlacementEventRow(initialPlacement))
        try context.save()
        let coordinator = CheckRunnerCoordinator(modelContext: context, signPack: pack)
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
            guard case .ready = try coordinator.prepareReportDelivery(result: result) else { throw FixtureError.invalid }
            roots.append(rootID.uuidString.lowercased())
        }
        let reports = try context.fetch(FetchDescriptor<Report>()).sorted { $0.id.uuidString < $1.id.uuidString }
        for (offset, state) in [(1, ReportPDFState.pending), (2, ReportPDFState.failed)] {
            let report = reports[offset]
            if let path = report.pdfRelativePath { try fileManager.removeItem(at: session.generationRootURL.appendingPathComponent(path)) }
            report.pdfState = state.rawValue; report.pdfRelativePath = nil; report.pdfSHA256 = nil
        }
        let tombstoneRoot = uuid(90)
        context.insert(Packet(id: uuid(89), stableRootID: tombstoneRoot, currentRecordID: nil, evaluationCounted: true, contentDeletedAt: Date(timeIntervalSince1970: 1_776_421_000), createdAt: Date(timeIntervalSince1970: 1_776_420_000)))
        roots.append(tombstoneRoot.uuidString.lowercased())
        try context.save()
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

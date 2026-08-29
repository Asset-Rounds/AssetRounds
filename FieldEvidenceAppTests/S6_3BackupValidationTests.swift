import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

private final class C45BackupValidationCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityValidatesCanonicalMutationAndSnapshotDigests() {
        XCTAssertEqual(AssetLabelMutationV1.schemaVersion, 1)
        XCTAssertEqual(AcceptedLabelGenerationSnapshotV1.schemaVersion, 1)
        XCTAssertEqual(AssetLabelPersistenceEnrollmentV1.recordsSchemaVersion, 33)
    }
}

private final class C30EvidenceContextAnchorS6_3BackupValidation: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

final class S6_3BackupValidationTests: XCTestCase {
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
    func testV23P03C40Records10GraphRequiresExactPredecessorRevision() throws {
        let root = try C40BackupLifecycleTestValues.source()
        let successor = try C40BackupLifecycleTestValues.source(
            releaseID: C40BackupLifecycleTestValues.id(90_004),
            supersedes: root.releaseID,
            revision: 2
        )
        let records = try C40BackupLifecycleTestValues.records([root, successor])
        let decoded = try BackupCanonicalDecoderV1().decodeRecords(
            BackupCanonicalEncoderV1().encodeRecords(records).data
        )
        let values = try decoded.authorityCriterion.map {
            try AuthorityCriterionCanonicalCodecV1.decode(
                AuthoritySourceReleaseV1.self, from: $0.canonicalData
            )
        }
        let byID = Dictionary(uniqueKeysWithValues: values.map { ($0.releaseID, $0) })
        let restoredSuccessor = try XCTUnwrap(byID[successor.releaseID])
        let restoredRoot = try XCTUnwrap(byID[restoredSuccessor.supersedesReleaseID!])
        XCTAssertEqual(restoredRoot.revision + 1, restoredSuccessor.revision)

        let dangling = try C40BackupLifecycleTestValues.source(
            releaseID: C40BackupLifecycleTestValues.id(90_005),
            supersedes: C40BackupLifecycleTestValues.id(90_099),
            revision: 2
        )
        let danglingValues = [dangling]
        let danglingByID = Dictionary(uniqueKeysWithValues: danglingValues.map { ($0.releaseID, $0) })
        XCTAssertNil(danglingByID[dangling.supersedesReleaseID!])
    }

    private let fileManager = FileManager.default

    @MainActor
    func testGoldenMixedPackageStagesValidatesAndRecomputesSummary() async throws {
        let draftHarness = try await makeHarness(
            "active-work-draft",
            stopAfterWorkDraft: true
        )
        defer { try? fileManager.removeItem(at: draftHarness.supportURL) }
        let draftPackage = try exportPackage(
            draftHarness,
            name: "active-work-draft-source"
        )
        let draftImporter = try makeImporter(
            draftHarness,
            capacity: .max,
            operationID: uuid(798),
            scopedAccess: .alreadyAuthorized
        )
        let validatedDraft = try draftImporter.stageAndValidate(
            selectedPackageURL: draftPackage
        )
        let workDraft = try XCTUnwrap(validatedDraft.records.workflowRecords.first {
            $0.state == WorkflowState.draft.rawValue
        })
        XCTAssertEqual(workDraft.stage, WorkflowStage.work.rawValue)
        XCTAssertNil(workDraft.draftStepKey)
        try draftImporter.discard(validatedDraft)

        let harness = try await makeHarness("golden")
        defer { try? fileManager.removeItem(at: harness.supportURL) }
        let fixture = try loadFixture()
        let package = try exportPackage(harness, name: "golden-source")
        let sourceFacts = try payloadFacts(package)
        let sourceBefore = try treeFacts(package)
        let liveBefore = try treeFacts(harness.session.generationRootURL)
        var starts: [URL] = []
        var stops: [URL] = []
        let importer = try makeImporter(
            harness,
            capacity: .max,
            scopedAccess: .init(
                start: { starts.append($0); return true },
                stop: { stops.append($0) }
            )
        )

        let validated = try importer.stageAndValidate(selectedPackageURL: package)
        XCTAssertEqual(starts, [package.standardizedFileURL])
        XCTAssertEqual(stops, [package.standardizedFileURL])
        XCTAssertEqual(validated.summary.incomingSignCount, fixture.expected.incomingSignCount)
        XCTAssertEqual(validated.summary.incomingReportCount, fixture.expected.incomingReportCount)
        XCTAssertEqual(validated.summary.incomingPhotoCount, fixture.expected.incomingPhotoCount)
        XCTAssertEqual(validated.summary.consumedRootCount, fixture.expected.consumedRootCount)
        XCTAssertEqual(validated.summary.liveSlotCount, fixture.expected.liveSlotCount)
        XCTAssertEqual(validated.summary.tombstonedSlotCount, fixture.expected.tombstonedSlotCount)
        XCTAssertEqual(validated.summary.exportedAt, fixture.exportedAt)
        XCTAssertEqual(validated.summary.packs, [fixture.pack])
        XCTAssertEqual(validated.records.issues.count, fixture.expected.incomingIssueCount)
        XCTAssertEqual(validated.records.workflowRecords.count, fixture.expected.incomingWorkflowRecordCount)

        let recomputed = sourceFacts.reduce(0) { $0 + $1.byteCount }
        XCTAssertEqual(validated.summary.declaredPayloadByteCount, recomputed)
        XCTAssertEqual(validated.manifest.declaredPayloadByteCount, recomputed)
        XCTAssertEqual(validated.manifest.entries.map(\.path), sourceFacts.map(\.path))
        XCTAssertEqual(validated.manifest.entries.map(\.byteCount), sourceFacts.map(\.byteCount))
        XCTAssertEqual(validated.manifest.entries.map(\.sha256), sourceFacts.map(\.sha256))
        XCTAssertEqual(validated.manifest.entries.map(\.mimeType), sourceFacts.map(\.mimeType))
        XCTAssertEqual(
            Set(validated.members.keys),
            Set(["manifest.json"] + validated.manifest.entries.map(\.path))
        )
        XCTAssertEqual(
            try XCTUnwrap(validated.members["manifest.json"]),
            try BackupCanonicalEncoderV1().encodeManifest(validated.manifest).data
        )
        XCTAssertEqual(
            try XCTUnwrap(validated.members["records.json"]),
            try BackupCanonicalEncoderV1().encodeRecords(validated.records).data
        )
        for entry in validated.manifest.entries {
            XCTAssertEqual(
                try XCTUnwrap(validated.members[entry.path]),
                try Data(contentsOf: package.appendingPathComponent(entry.path)),
                entry.path
            )
        }
        XCTAssertEqual(
            validated.manifest.consumedEvaluationRootIDs,
            validated.records.packets.filter { $0.evaluationCounted }.map(\.stableRootID)
                .sorted { $0.uuidString < $1.uuidString }
        )
        let paths = Set(validated.manifest.entries.map(\.path))
        XCTAssertEqual(paths.filter { $0.hasPrefix("snapshots/") }.count, fixture.expected.snapshotCount)
        XCTAssertEqual(paths.filter { $0.hasPrefix("pdfs/") }.count, fixture.expected.readyPDFCount)
        for report in validated.records.reports {
            XCTAssertTrue(paths.contains(report.snapshotRelativePath))
            XCTAssertEqual(report.pdfRelativePath.map(paths.contains) ?? false, report.pdfState == "ready")
        }
        try assertMixedGraph(validated.records, expected: fixture.expected)
        for evidence in validated.records.evidenceFiles {
            let id = evidence.id.uuidString.lowercased()
            XCTAssertEqual(validated.members["media/\(id).jpg"]?.sha256, evidence.sha256)
            XCTAssertEqual(validated.members["thumbnails/\(id).jpg"]?.sha256, evidence.thumbnailSHA256)
        }
        XCTAssertEqual(try treeFacts(harness.session.generationRootURL), liveBefore)
        XCTAssertTrue(fileManager.fileExists(atPath: validated.stagedPackageURL.path))
        try importer.discard(validated)
        XCTAssertFalse(fileManager.fileExists(atPath: validated.stagedPackageURL.path))
        XCTAssertEqual(try treeFacts(package), sourceBefore)
        XCTAssertEqual(try treeFacts(harness.session.generationRootURL), liveBefore)
    }

    @MainActor
    func testInvalidFamiliesAndCapacityFailClosedAndCleanStage() async throws {
        let harness = try await makeHarness("invalid")
        defer { try? fileManager.removeItem(at: harness.supportURL) }
        let canonical = try exportPackage(harness, name: "canonical-source")
        let liveBefore = try treeFacts(harness.session.generationRootURL)
        let modelsBefore = try modelFacts(harness.context)
        let cases: [(String, (URL) throws -> Void)] = [
            ("path/member", { try Data([0]).write(to: $0.appendingPathComponent("unexpected.bin")) }),
            ("missing-member", { root in try self.fileManager.removeItem(at: try self.firstMember(in: root, prefix: "media/")) }),
            ("duplicate/case-fold", { root in
                try self.fileManager.copyItem(
                    at: root.appendingPathComponent("records.json"),
                    to: root.appendingPathComponent("\u{ff52}ecords.json")
                )
            }),
            ("symlink", { root in
                let member = try self.firstMember(in: root, prefix: "media/")
                try self.fileManager.removeItem(at: member)
                try self.fileManager.createSymbolicLink(at: member, withDestinationURL: root.appendingPathComponent("records.json"))
            }),
            ("ancestor-substitution/special", { root in
                let directory = root.appendingPathComponent("media", isDirectory: true)
                let retained = root.deletingLastPathComponent().appendingPathComponent("retained-media-\(UUID().uuidString)", isDirectory: true)
                try self.fileManager.copyItem(at: directory, to: retained)
                try self.fileManager.removeItem(at: directory)
                try self.fileManager.createSymbolicLink(at: directory, withDestinationURL: retained)
            }),
            ("hard-link", { root in
                let member = try self.firstMember(in: root, prefix: "thumbnails/")
                let source = root.appendingPathComponent("records.json")
                try self.fileManager.removeItem(at: member)
                try self.fileManager.linkItem(at: source, to: member)
            }),
            ("hash/bytes/media", { root in try self.flipFirstByte(at: try self.firstMember(in: root, prefix: "media/")) }),
            ("MIME", { root in
                let url = root.appendingPathComponent("manifest.json")
                var text = try String(contentsOf: url, encoding: .utf8)
                guard text.contains("\"mimeType\":\"image/jpeg\"") else { throw FixtureError.invalid }
                text = text.replacingOccurrences(of: "\"mimeType\":\"image/jpeg\"", with: "\"mimeType\":\"application/pdf\"")
                try XCTUnwrap(text.data(using: .utf8)).write(to: url)
            }),
            ("canonical-json", { root in
                let recordsURL = root.appendingPathComponent("records.json")
                var bytes = try Data(contentsOf: recordsURL); bytes.append(0x20)
                try bytes.write(to: recordsURL); try self.rebuildManifest(at: root)
            }),
            ("schema", { root in
                try self.replaceRecordsText(at: root, from: "\"recordsSchemaVersion\":1", to: "\"recordsSchemaVersion\":2")
            }),
            ("site-time-zone", { root in
                try self.setInvalidSiteTimeZone(at: root)
            }),
            ("scalar-time", { root in
                try self.moveAssetUpdateBeforeCreation(at: root)
            }),
            ("scalar-text", { root in
                try self.padAssetLabel(at: root)
            }),
            ("pack", { root in
                try self.replaceRecordsText(
                    at: root,
                    from: "field.evidence.illuminated_sign.v1",
                    to: "field.evidence.unknown_sign.v1"
                )
            }),
            ("template", { root in
                try self.replaceRecordsText(at: root, from: "\"pdfTemplateVersion\":1", to: "\"pdfTemplateVersion\":99")
            }),
            ("ids/relationships", { root in
                try self.replaceRecordsText(
                    at: root,
                    from: "\"siteID\":\"63000000-0000-0000-0000-000000000001\"",
                    to: "\"siteID\":\"63000000-0000-0000-0000-000000000777\""
                )
            }),
            ("ID-collision", { root in try self.collideEvidenceIDs(at: root) }),
            ("evidence-time", { root in
                try self.moveEvidenceBeforeRecord(at: root)
            }),
            ("mutation-ID-collision", { root in
                try self.collideFinalizationMutationIDs(at: root)
            }),
            ("draft-fork", { root in try self.addDuplicateCheckDrafts(at: root) }),
            ("draft-shape", { root in try self.addInvalidReviewDraft(at: root) }),
            ("draft-preflight", { root in
                try self.addInvalidDraftPreflight(at: root)
            }),
            ("issue-ambiguity", { root in
                try self.makeTwoOpenIssueLineages(at: root)
            }),
            ("duplicate-issue-opener", { root in
                try self.duplicateDifferentIssueOpener(at: root)
            }),
            ("report-source-coverage", { root in
                try self.omitPriorCorrectionReport(at: root)
            }),
            ("correction-copy", { root in
                try self.mutateCorrectionStartedAt(at: root)
            }),
            ("chain-time", { root in
                try self.moveWorkBeforeParent(at: root)
            }),
            ("work-date", { root in
                try self.setInvalidWorkLocalDate(at: root)
            }),
            ("cycle/fork", { root in try self.makeParentCycle(at: root) }),
            ("counted-root", { root in try self.replaceConsumedRoot(at: root) }),
            ("tombstone-time", { root in
                try self.moveTombstoneDeletionBeforeCreation(at: root)
            }),
            ("packet-time", { root in
                try self.changeLivePacketCreation(at: root)
            }),
            ("snapshot", { root in
                try self.flipFirstByte(at: try self.firstMember(in: root, prefix: "snapshots/"))
            }),
            ("cnv-snapshot", { root in
                try self.injectCouldNotVerifySnapshot(at: root)
            }),
            ("history-cnv", { root in
                try self.injectHistoryCouldNotVerifySnapshot(at: root)
            }),
            ("report-delivery", { root in
                try self.flipFirstByte(at: try self.firstMember(in: root, prefix: "pdfs/"))
            }),
            ("fake-pdf", { root in
                try self.replaceReadyPDFWithFake(at: root)
            }),
        ]

        for (index, item) in cases.enumerated() {
            let source = harness.supportURL.appendingPathComponent("invalid-\(index).fieldrecordbackup", isDirectory: true)
            try fileManager.copyItem(at: canonical, to: source)
            try item.1(source)
            var starts = 0, stops = 0
            let importer = try makeImporter(
                harness,
                capacity: .max,
                operationID: uuid(800 + index),
                scopedAccess: .init(start: { _ in starts += 1; return true }, stop: { _ in stops += 1 })
            )
            XCTAssertThrowsError(try importer.stageAndValidate(selectedPackageURL: source), item.0)
            XCTAssertEqual(starts, 1, item.0)
            XCTAssertEqual(stops, 1, item.0)
            XCTAssertEqual(try stagedPackages(harness).count, 0, item.0)
            XCTAssertEqual(try treeFacts(harness.session.generationRootURL), liveBefore, item.0)
            XCTAssertEqual(try modelFacts(harness.context), modelsBefore, item.0)
        }

        var starts = 0, stops = 0
        let capacityImporter = try makeImporter(
            harness,
            capacity: 0,
            operationID: uuid(899),
            scopedAccess: .init(start: { _ in starts += 1; return true }, stop: { _ in stops += 1 })
        )
        XCTAssertThrowsError(try capacityImporter.stageAndValidate(selectedPackageURL: canonical)) { error in
            guard let typed = error as? StoragePreflightError,
                  case .insufficientCapacity = typed else {
                return XCTFail("Expected exact insufficient-capacity failure, got \(error)")
            }
        }
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(try stagedPackages(harness).count, 0)
        XCTAssertEqual(try treeFacts(harness.session.generationRootURL), liveBefore)
        XCTAssertEqual(try modelFacts(harness.context), modelsBefore)
    }
}

private final class C27S63TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(LocatorResolutionOutcomeV1.allCases.count, 8)
        XCTAssertEqual(AssetLocatorLimitsV1.maximumCandidates, 32)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.scanMutatesCanonicalState)
    }
}

extension S6_3BackupValidationTests {
    func testC24AccessibleDocumentTypedAnchor() throws {
        XCTAssertEqual(AccessibleDocumentSemanticTreeV1.schemaVersion, 1)
        XCTAssertEqual(AccessibleDocumentRoleV1.allCases.count, 13)
        XCTAssertEqual(AccessibleDocumentAssessmentStateV1.allCases.count, 4)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
    }
}

extension S6_3BackupValidationTests {
    func testC22RecoverabilityVerificationAnchor() throws {
        XCTAssertEqual(RecoverabilityVerificationReceiptV1.schemaVersion, 1)
        try V21RecoverabilityImportBoundaryV1.validate(persistentSchemaVersion: 21, recordsSchemaVersion: 20)
        XCTAssertFalse(RecoverabilityVerificationLifecycleV1.externalCopyAvailabilityClaimed)
        XCTAssertEqual(RecoverabilityVerificationLifecycleV1.stagingPersistence, "DERIVED_ONLY_DROP_AND_REBUILD")
    }
}

extension S6_3BackupValidationTests {
    func testV23P03C18SemanticReleaseChangeRoundTripsCanonically() throws {
        let change = try PackageSemanticChangeV1(
            kind: .semanticReleaseChanged,
            stableSubjectID: "package.semantic.releases"
        )
        let bytes = try PackageEvolutionCanonicalCodecV1.encode(change)
        XCTAssertEqual(
            try PackageEvolutionCanonicalCodecV1.decode(
                PackageSemanticChangeV1.self,
                from: bytes
            ),
            change
        )
        XCTAssertTrue(PackageEvolutionLifecycleV1.migrationRequired)
    }
}

extension S6_3BackupValidationTests {
    func testV23P03C17RestoreDropsAndRebuildsDerivedProjection() throws {
        XCTAssertNoThrow(try IntegrationProjectionBackupRestoreExclusionV1.validate())
        XCTAssertEqual(IntegrationProjectionSchemaV1.downgradeDisposition, "DROP_AND_REBUILD")
    }
}

extension S6_3BackupValidationTests {
    func testV23P03C36CanonicalDecoderRejectsNonCanonicalCheckpointBytes() throws {
        XCTAssertThrowsError(try FieldDraftCanonicalCodecV1.decode(FieldDraftCheckpointV1.self,from:Data("{}".utf8)))
        XCTAssertEqual(Set(V16BackupFieldDraftRecordV1.Kind.allCases.map(\.rawValue)).count,6)
        XCTAssertEqual(
            [
                DraftCommitSagaStateV1.prepared,
                .contentPromotedUnbound,
                .targetCommitted,
                .draftRetirePending,
                .draftRetired,
            ].map(\.rawValue),
            [
                "PREPARED",
                "CONTENT_PROMOTED_UNBOUND",
                "TARGET_COMMITTED",
                "DRAFT_RETIRE_PENDING",
                "DRAFT_RETIRED",
            ]
        )
    }
}

extension S6_3BackupValidationTests {
    func testV23P03C15BackupValidationUsesV15SchemaAndTypedRows() throws {
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 150_163)
        let rows: [Data] = [
            try WorkPacketCanonicalCodecV1.encode(fixture.manifest),
            try WorkPacketCanonicalCodecV1.encode(fixture.claim),
            try WorkPacketCanonicalCodecV1.encode(fixture.lease),
            try WorkPacketCanonicalCodecV1.encode(fixture.completedRelease),
            try WorkPacketCanonicalCodecV1.encode(fixture.handoff)
        ]
        XCTAssertEqual(rows.count, 5)
        XCTAssertTrue(rows.allSatisfy { !$0.isEmpty && $0.count <= WorkPacketLimitsV1.maximumCanonicalBytes })
        XCTAssertEqual(PersistentSchemaV15.versionIdentifier, Schema.Version(15, 0, 0))
        XCTAssertEqual(PersistentSchemaV15.models.count, 58)
    }
}

extension S6_3BackupValidationTests {
    func testV23P03C13BackupValidationRejectsNonCanonicalAssuranceBytes() throws {
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture(seed: 51_630)
        var bytes = try EvidenceAssuranceCanonicalCodecV1.encode(fixture.customerManifest)
        bytes.append(0x0A)

        XCTAssertThrowsError(
            try EvidenceAssuranceCanonicalCodecV1.decode(AssuranceManifestV1.self, from: bytes)
        ) { error in
            XCTAssertEqual(error as? EvidenceAssuranceFailureV1, .nonCanonicalData)
        }
        XCTAssertEqual(fixture.customerManifest.manifestSHA256.count, 64)
        XCTAssertEqual(fixture.customerManifest.revision, 1)
    }
}

private extension S6_3BackupValidationTests {
    struct Harness {
        let supportURL: URL
        let session: StoreGenerationSession
        let context: ModelContext
    }
    struct Fixture: Decodable {
        struct Expected: Decodable {
            let clericalCorrectionCount: Int
            let consumedRootCount: Int
            let failedReportCount: Int
            let incomingIssueCount: Int
            let incomingPhotoCount: Int
            let incomingReportCount: Int
            let incomingSignCount: Int
            let incomingWorkflowRecordCount: Int
            let liveSlotCount: Int
            let pendingReportCount: Int
            let readyPDFCount: Int
            let recheckCount: Int
            let snapshotCount: Int
            let tombstonedSlotCount: Int
        }
        let exportedAt: Date
        let expected: Expected
        let fixtureSchemaVersion: Int
        let pack: V4BackupPackV1
    }
    struct PayloadFact {
        let path: String
        let byteCount: Int
        let mimeType: String
        let sha256: String
    }

    @MainActor
    func makeHarness(
        _ name: String,
        stopAfterWorkDraft: Bool = false,
        siteAddress: String? = nil
    ) async throws -> Harness {
        let support = fileManager.temporaryDirectory.appendingPathComponent("S6_3BackupValidationTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: false)
        let session = try StoreGenerationFactory(applicationSupportURL: support).openOrBootstrapCurrent()
        let context = session.modelContext
        let pack = SignPack.illuminatedSignV1
        let siteID = uuid(1), assetID = uuid(2)
        context.insert(Site(id: siteID, label: "Import Site", address: siteAddress, timeZoneID: "America/New_York", createdAt: Date(timeIntervalSince1970: 1_776_420_000)))
        context.insert(Asset(id: assetID, siteID: siteID, packID: pack.packID, packSchemaVersion: pack.schemaVersion, packContentVersion: pack.contentVersion, label: "One Live Sign", createdAt: Date(timeIntervalSince1970: 1_776_420_001)))
        try context.save()
        let coordinator = CheckRunnerCoordinator(modelContext: context, signPack: pack)
        coordinator.configureCapture(generationRootURL: session.generationRootURL)
        let openingObserved = Date(timeIntervalSince1970: 1_780_000_000)
        _ = try coordinator.beginCheck(assetID: assetID, timeZoneID: "America/New_York", isTimeZoneConfirmed: true, afterDarkAccepted: true, safePositionAccepted: true, observedAt: openingObserved)
        try await acceptPair(coordinator, assetID: assetID, observedAt: openingObserved, seeds: (31, 71))
        let issueID = uuid(15)
        let opening = try await coordinator.finalize(
            assetID: assetID,
            selection: .visibleIssue(labelKey: "dark_section"),
            completedAt: openingObserved.addingTimeInterval(30),
            snapshotCreatedAt: openingObserved.addingTimeInterval(31),
            sourceApp: .init(build: "42", version: "4.0"),
            identifiers: .init(mutationID: uuid(11), packetID: uuid(12), stableRootID: uuid(13), reportID: uuid(14), issueID: issueID)
        )
        guard case .ready = try coordinator.prepareReportDelivery(result: opening) else { throw FixtureError.invalid }

        let workObserved = openingObserved.addingTimeInterval(60)
        _ = try coordinator.beginOrResumeDraft(.init(
            assetID: assetID,
            requestedStage: .work,
            issueID: issueID,
            observedAtUTC: workObserved,
            confirmedTimeZoneID: nil,
            afterDarkAccepted: false,
            safePositionAccepted: false
        ))
        let workCoordinator = try WorkCoordinator(
            modelContext: context,
            signPack: pack,
            generationRootURL: session.generationRootURL,
            checkRunnerCoordinator: coordinator,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
        )
        let workDraft = try workCoordinator.beginWork(issueID: issueID)
        if stopAfterWorkDraft {
            return Harness(supportURL: support, session: session, context: context)
        }
        let workCompleted = workDraft.startedAt.addingTimeInterval(30)
        _ = try await workCoordinator.saveWork(
            draftID: workDraft.recordID,
            submission: .init(
                performedLocalDate: "2026-08-14",
                description: "Replaced failed power supply",
                note: "Fixture work authority",
                photos: [.init(purposeKey: "work_context", sourceData: try makePNG(seed: 91), createdAt: workDraft.startedAt.addingTimeInterval(10))],
                completedAt: workCompleted
            ),
            identifiers: .init(mutationID: uuid(16), evidenceID: uuid(17))
        )

        let recheckObserved = workCompleted.addingTimeInterval(60)
        _ = try coordinator.beginOrResumeDraft(.init(
            assetID: assetID,
            requestedStage: .recheck,
            issueID: issueID,
            observedAtUTC: recheckObserved,
            confirmedTimeZoneID: "America/New_York",
            afterDarkAccepted: true,
            safePositionAccepted: true
        ))
        try await acceptPair(coordinator, assetID: assetID, observedAt: recheckObserved, seeds: (41, 81))
        let recheck = try await coordinator.finalize(
            assetID: assetID,
            selection: .resolved(note: "Illumination remained steady."),
            completedAt: recheckObserved.addingTimeInterval(30),
            snapshotCreatedAt: recheckObserved.addingTimeInterval(31),
            sourceApp: .init(build: "42", version: "4.0"),
            identifiers: .init(mutationID: uuid(21), packetID: uuid(22), stableRootID: uuid(23), reportID: uuid(24), issueID: issueID)
        )
        guard case .ready = try coordinator.prepareReportDelivery(result: recheck) else { throw FixtureError.invalid }

        let delivery = try ReportDeliveryCoordinator(
            modelContext: context,
            generationRootURL: session.generationRootURL
        )
        let correctionSource = try delivery.correctionSource(reportID: recheck.reportID)
        guard case .ready = try await delivery.submitCorrection(
            from: correctionSource,
            note: "Clerical note corrected.",
            snapshotCreatedAt: recheckObserved.addingTimeInterval(40),
            sourceApp: .init(build: "42", version: "4.0"),
            identifiers: .init(mutationID: uuid(26), recordID: uuid(27), reportID: uuid(28))
        ) else { throw FixtureError.invalid }

        let openingReport = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Report>()).first { $0.id == opening.reportID }
        )
        let openingPDF = try XCTUnwrap(openingReport.pdfRelativePath)
        try fileManager.removeItem(
            at: session.generationRootURL.appendingPathComponent(openingPDF)
        )
        openingReport.pdfState = ReportPDFState.failed.rawValue
        openingReport.pdfRelativePath = nil
        openingReport.pdfSHA256 = nil
        try context.save()

        let laterObserved = recheckObserved.addingTimeInterval(120)
        let laterCoordinator = CheckRunnerCoordinator(
            modelContext: context,
            signPack: pack
        )
        laterCoordinator.configureCapture(
            generationRootURL: session.generationRootURL
        )
        _ = try laterCoordinator.beginCheck(assetID: assetID, timeZoneID: "America/New_York", isTimeZoneConfirmed: true, afterDarkAccepted: true, safePositionAccepted: true, observedAt: laterObserved)
        try await acceptPair(laterCoordinator, assetID: assetID, observedAt: laterObserved, seeds: (51, 101))
        _ = try await laterCoordinator.finalize(
            assetID: assetID,
            selection: .noVisibleIssue,
            completedAt: laterObserved.addingTimeInterval(30),
            snapshotCreatedAt: laterObserved.addingTimeInterval(31),
            sourceApp: .init(build: "42", version: "4.0"),
            identifiers: .init(mutationID: uuid(31), packetID: uuid(32), stableRootID: uuid(33), reportID: uuid(34), issueID: nil)
        )
        context.insert(Packet(id: uuid(89), stableRootID: uuid(90), currentRecordID: nil, evaluationCounted: true, contentDeletedAt: Date(timeIntervalSince1970: 1_776_421_000), createdAt: Date(timeIntervalSince1970: 1_776_420_000)))
        try context.save()
        return Harness(supportURL: support, session: session, context: context)
    }

    @MainActor
    func acceptPair(
        _ coordinator: CheckRunnerCoordinator,
        assetID: UUID,
        observedAt: Date,
        seeds: (UInt8, UInt8)
    ) async throws {
        let wide = try await coordinator.importCandidate(assetID: assetID, sourceData: try makePNG(seed: seeds.0), createdAt: observedAt.addingTimeInterval(1))
        _ = try await coordinator.accept(candidate: wide, assetID: assetID)
        let close = try await coordinator.importCandidate(assetID: assetID, sourceData: try makePNG(seed: seeds.1), createdAt: observedAt.addingTimeInterval(2))
        _ = try await coordinator.accept(candidate: close, assetID: assetID)
    }

    @MainActor
    func exportPackage(_ harness: Harness, name: String) throws -> URL {
        let destination = harness.supportURL.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        let service = BackupExportService(
            modelContext: harness.context,
            generationRootURL: harness.session.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
            now: { Date(timeIntervalSince1970: 1_786_708_800) },
            makeUUID: { self.uuid(99) },
            appVersion: { "4.0" },
            appBuild: { "42" }
        )
        let preview = try service.prepareCompatibilityFixtureLegacyDirectoryPackage()
        return try service.exportCompatibilityFixtureLegacyDirectoryPackage(
            previewID: preview.id,
            to: destination
        )
    }

    @MainActor
    func makeImporter(
        _ harness: Harness,
        capacity: Int64,
        operationID: UUID? = nil,
        scopedAccess: BackupSecurityScopedAccessV1
    ) throws -> BackupImportService {
        try BackupImportService(
            generationRootURL: harness.session.generationRootURL,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in capacity }),
            makeUUID: { operationID ?? self.uuid(799) },
            scopedAccess: scopedAccess
        )
    }

    func loadFixture() throws -> Fixture {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "S6_3V4BackupPackageV1", withExtension: "json", subdirectory: "Fixtures") ?? bundle.url(forResource: "S6_3V4BackupPackageV1", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let value = Self.fixtureDateFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid fixture date")
            }
            return value
        }
        let value = try decoder.decode(Fixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(value.fixtureSchemaVersion, 1)
        return value
    }

    func payloadFacts(_ root: URL) throws -> [PayloadFact] {
        let urls = try XCTUnwrap(fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])).compactMap { $0 as? URL }
        return try urls.filter { try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true && $0.lastPathComponent != "manifest.json" }.map { url in
            let data = try Data(contentsOf: url)
            let path = String(url.path.dropFirst(root.path.count + 1)).replacingOccurrences(of: "\\", with: "/")
            let mime = url.pathExtension == "jpg" ? "image/jpeg" : (url.pathExtension == "pdf" ? "application/pdf" : "application/json")
            return PayloadFact(path: path, byteCount: data.count, mimeType: mime, sha256: data.sha256)
        }.sorted { $0.path < $1.path }
    }

    func assertMixedGraph(
        _ records: V4BackupRecordsV1,
        expected: Fixture.Expected,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let issue = try XCTUnwrap(
            records.issues.count == 1 ? records.issues.first : nil,
            file: file,
            line: line
        )
        let opening = try XCTUnwrap(
            records.workflowRecords.first { $0.id == issue.openedByRecordID },
            file: file,
            line: line
        )
        let work = try XCTUnwrap(
            records.workflowRecords.first { $0.stage == WorkflowStage.work.rawValue },
            file: file,
            line: line
        )
        let rechecks = records.workflowRecords.filter {
            $0.stage == WorkflowStage.recheck.rawValue
                && $0.revisionKind == WorkflowRevisionKind.original.rawValue
        }
        let recheck = try XCTUnwrap(
            rechecks.count == 1 ? rechecks.first : nil,
            file: file,
            line: line
        )
        let corrections = records.workflowRecords.filter {
            $0.revisionKind == WorkflowRevisionKind.clericalCorrection.rawValue
        }
        let correction = try XCTUnwrap(
            corrections.count == 1 ? corrections.first : nil,
            file: file,
            line: line
        )

        XCTAssertEqual(rechecks.count, expected.recheckCount, file: file, line: line)
        XCTAssertEqual(corrections.count, expected.clericalCorrectionCount, file: file, line: line)
        XCTAssertEqual(opening.stage, WorkflowStage.check.rawValue, file: file, line: line)
        XCTAssertEqual(opening.outcomeKey, "visible_issue", file: file, line: line)
        XCTAssertEqual(opening.issueID, issue.id, file: file, line: line)
        XCTAssertEqual(work.parentRecordID, opening.id, file: file, line: line)
        XCTAssertEqual(work.issueID, issue.id, file: file, line: line)
        XCTAssertEqual(work.outcomeKey, "work_recorded", file: file, line: line)
        XCTAssertNil(work.packetID, file: file, line: line)
        XCTAssertEqual(recheck.parentRecordID, work.id, file: file, line: line)
        XCTAssertEqual(recheck.issueID, issue.id, file: file, line: line)
        XCTAssertEqual(recheck.outcomeKey, "resolved", file: file, line: line)
        XCTAssertEqual(correction.revisesRecordID, recheck.id, file: file, line: line)
        XCTAssertEqual(correction.evidenceSourceRecordID, recheck.id, file: file, line: line)
        XCTAssertEqual(correction.recordRevisionRootID, recheck.recordRevisionRootID, file: file, line: line)
        XCTAssertEqual(correction.packetID, recheck.packetID, file: file, line: line)
        XCTAssertEqual(issue.status, IssueStatus.resolved.rawValue, file: file, line: line)
        XCTAssertEqual(issue.resolvedByRecordID, recheck.id, file: file, line: line)

        let minimalLive = try XCTUnwrap(
            records.workflowRecords.first {
                $0.stage == WorkflowStage.check.rawValue
                    && $0.outcomeKey == "no_visible_issue"
            },
            file: file,
            line: line
        )
        let minimalPacketID = try XCTUnwrap(
            minimalLive.packetID,
            file: file,
            line: line
        )
        let minimalPacket = try XCTUnwrap(
            records.packets.first { $0.id == minimalPacketID },
            file: file,
            line: line
        )
        XCTAssertEqual(minimalPacket.currentRecordID, minimalLive.id, file: file, line: line)
        XCTAssertTrue(minimalPacket.evaluationCounted, file: file, line: line)

        let openingReport = try XCTUnwrap(
            records.reports.first { $0.sourceRecordID == opening.id },
            file: file,
            line: line
        )
        let recheckReport = try XCTUnwrap(
            records.reports.first { $0.sourceRecordID == recheck.id },
            file: file,
            line: line
        )
        let correctionReport = try XCTUnwrap(
            records.reports.first { $0.sourceRecordID == correction.id },
            file: file,
            line: line
        )
        let pendingReport = try XCTUnwrap(
            records.reports.first { $0.sourceRecordID == minimalLive.id },
            file: file,
            line: line
        )
        XCTAssertEqual(openingReport.pdfState, ReportPDFState.failed.rawValue, file: file, line: line)
        XCTAssertNil(openingReport.pdfRelativePath, file: file, line: line)
        XCTAssertNil(openingReport.pdfSHA256, file: file, line: line)
        XCTAssertEqual(recheckReport.pdfState, ReportPDFState.ready.rawValue, file: file, line: line)
        XCTAssertEqual(correctionReport.pdfState, ReportPDFState.ready.rawValue, file: file, line: line)
        XCTAssertEqual(correctionReport.replacesReportID, recheckReport.id, file: file, line: line)
        XCTAssertEqual(correctionReport.packetID, recheckReport.packetID, file: file, line: line)
        XCTAssertEqual(pendingReport.pdfState, ReportPDFState.pending.rawValue, file: file, line: line)
        XCTAssertNil(pendingReport.pdfRelativePath, file: file, line: line)
        XCTAssertNil(pendingReport.pdfSHA256, file: file, line: line)
        XCTAssertEqual(
            records.reports.filter { $0.pdfState == ReportPDFState.pending.rawValue }.count,
            expected.pendingReportCount,
            file: file,
            line: line
        )
        XCTAssertEqual(
            records.reports.filter { $0.pdfState == ReportPDFState.failed.rawValue }.count,
            expected.failedReportCount,
            file: file,
            line: line
        )
        XCTAssertEqual(
            records.reports.filter { $0.pdfState == ReportPDFState.ready.rawValue }.count,
            expected.readyPDFCount,
            file: file,
            line: line
        )
        XCTAssertEqual(
            records.evidenceFiles.filter { $0.purposeKey == "wide_context" }.count,
            3,
            file: file,
            line: line
        )
        XCTAssertEqual(
            records.evidenceFiles.filter { $0.purposeKey == "close_detail" }.count,
            3,
            file: file,
            line: line
        )
        XCTAssertEqual(
            records.evidenceFiles.filter { $0.purposeKey == "work_context" }.count,
            1,
            file: file,
            line: line
        )
        XCTAssertEqual(
            records.packets.filter { $0.currentRecordID == nil && $0.contentDeletedAt != nil }.count,
            expected.tombstonedSlotCount,
            file: file,
            line: line
        )
        let tombstone = try XCTUnwrap(
            records.packets.first { $0.currentRecordID == nil },
            file: file,
            line: line
        )
        XCTAssertTrue(tombstone.evaluationCounted, file: file, line: line)
        XCTAssertNotNil(tombstone.contentDeletedAt, file: file, line: line)
    }

    func treeFacts(_ root: URL) throws -> [String] {
        let urls = try XCTUnwrap(fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])).compactMap { $0 as? URL }
        return try urls.filter { try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true }.map {
            "\(String($0.path.dropFirst(root.path.count + 1)))|\((try Data(contentsOf: $0)).sha256)"
        }.sorted()
    }

    @MainActor
    func modelFacts(_ context: ModelContext) throws -> [String] {
        let packets = try context.fetch(FetchDescriptor<Packet>()).map {
            "packet|\($0.id)|\($0.currentRecordID?.uuidString ?? "nil")|\($0.evaluationCounted)|\($0.contentDeletedAt?.timeIntervalSince1970 ?? -1)"
        }
        let reports = try context.fetch(FetchDescriptor<Report>()).map {
            "report|\($0.id)|\($0.sourceRecordID)|\($0.pdfState)|\($0.pdfSHA256 ?? "nil")"
        }
        let evidence = try context.fetch(FetchDescriptor<EvidenceFile>()).map {
            "evidence|\($0.id)|\($0.recordID)|\($0.relativePath)|\($0.sha256)"
        }
        return (packets + reports + evidence).sorted()
    }

    @MainActor
    func stagedPackages(_ harness: Harness) throws -> [URL] {
        let directory = try StoreGenerationFactory.backupImportStagingDirectory(containing: harness.session.generationRootURL)
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "fieldrecordbackup" }
    }

    func firstMember(in root: URL, prefix: String) throws -> URL {
        let facts = try payloadFacts(root)
        return root.appendingPathComponent(try XCTUnwrap(facts.first { $0.path.hasPrefix(prefix) }?.path))
    }

    func flipFirstByte(at url: URL) throws {
        var data = try Data(contentsOf: url)
        guard !data.isEmpty else { throw FixtureError.invalid }
        data[0] ^= 0xff
        try data.write(to: url)
    }

    func replaceReadyPDFWithFake(at root: URL) throws {
        let recordsURL = root.appendingPathComponent("records.json")
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: recordsURL))
                as? [String: Any]
        )
        var reports = try XCTUnwrap(object["reports"] as? [[String: Any]])
        let index = try XCTUnwrap(reports.firstIndex {
            $0["pdfState"] as? String == ReportPDFState.ready.rawValue
        })
        let path = try XCTUnwrap(reports[index]["pdfRelativePath"] as? String)
        let fake = Data("%PDF-not-a-document".utf8)
        try fake.write(to: root.appendingPathComponent(path))
        reports[index]["pdfSHA256"] = fake.sha256
        object["reports"] = reports
        let loose = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let value = Self.fixtureDateFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid fixture date"
                )
            }
            return value
        }
        let records = try decoder.decode(V4BackupRecordsV1.self, from: loose)
        try BackupCanonicalEncoderV1().encodeRecords(records).data.write(
            to: recordsURL
        )
        try rebuildManifest(at: root)
    }

    func injectCouldNotVerifySnapshot(at root: URL) throws {
        let recordsURL = root.appendingPathComponent("records.json")
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: recordsURL))
                as? [String: Any]
        )
        var reports = try XCTUnwrap(object["reports"] as? [[String: Any]])
        guard let reportIndex = reports.indices.first else {
            throw FixtureError.invalid
        }
        let path = try XCTUnwrap(
            reports[reportIndex]["snapshotRelativePath"] as? String
        )
        let snapshotURL = root.appendingPathComponent(path)
        var snapshot = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: snapshotURL))
                as? [String: Any]
        )
        let reasons = SignPack.illuminatedSignV1.couldNotVerifyReasons
        let reason = try XCTUnwrap(reasons.entries.first)
        snapshot["couldNotVerify"] = [
            "display": reason.display,
            "key": reason.key,
            "registryVersion": reasons.version,
        ]
        let looseSnapshot = try JSONSerialization.data(withJSONObject: snapshot)
        let snapshotDecoder = JSONDecoder()
        snapshotDecoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let value = Self.fixtureDateFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid fixture date"
                )
            }
            return value
        }
        let value = try snapshotDecoder.decode(
            ReportSnapshotV1.self,
            from: looseSnapshot
        )
        let encoded = try ReportSnapshotEncoderV1().encode(value)
        try encoded.data.write(to: snapshotURL)
        reports[reportIndex]["snapshotSHA256"] = encoded.sha256
        object["reports"] = reports

        let looseRecords = try JSONSerialization.data(withJSONObject: object)
        let recordsDecoder = JSONDecoder()
        recordsDecoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let value = Self.fixtureDateFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid fixture date"
                )
            }
            return value
        }
        let records = try recordsDecoder.decode(
            V4BackupRecordsV1.self,
            from: looseRecords
        )
        try BackupCanonicalEncoderV1().encodeRecords(records).data.write(
            to: recordsURL
        )
        try rebuildManifest(at: root)
    }

    func injectHistoryCouldNotVerifySnapshot(at root: URL) throws {
        let recordsURL = root.appendingPathComponent("records.json")
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: recordsURL))
                as? [String: Any]
        )
        var reports = try XCTUnwrap(object["reports"] as? [[String: Any]])
        var target: (index: Int, url: URL, snapshot: [String: Any])?
        for index in reports.indices {
            let path = try XCTUnwrap(
                reports[index]["snapshotRelativePath"] as? String
            )
            let url = root.appendingPathComponent(path)
            let snapshot = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: Data(contentsOf: url))
                    as? [String: Any]
            )
            if let history = snapshot["history"] as? [[String: Any]],
               !history.isEmpty {
                target = (index, url, snapshot)
                break
            }
        }
        let selected = try XCTUnwrap(target)
        var snapshot = selected.snapshot
        var history = try XCTUnwrap(
            snapshot["history"] as? [[String: Any]]
        )
        let reasons = SignPack.illuminatedSignV1.couldNotVerifyReasons
        let reason = try XCTUnwrap(reasons.entries.first)
        history[0]["couldNotVerify"] = [
            "display": reason.display,
            "key": reason.key,
            "registryVersion": reasons.version,
        ]
        snapshot["history"] = history
        let looseSnapshot = try JSONSerialization.data(withJSONObject: snapshot)
        let snapshotDecoder = JSONDecoder()
        snapshotDecoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let value = Self.fixtureDateFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid fixture date"
                )
            }
            return value
        }
        let value = try snapshotDecoder.decode(
            ReportSnapshotV1.self,
            from: looseSnapshot
        )
        let encoded = try ReportSnapshotEncoderV1().encode(value)
        try encoded.data.write(to: selected.url)
        reports[selected.index]["snapshotSHA256"] = encoded.sha256
        object["reports"] = reports

        let looseRecords = try JSONSerialization.data(withJSONObject: object)
        let recordsDecoder = JSONDecoder()
        recordsDecoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let value = Self.fixtureDateFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid fixture date"
                )
            }
            return value
        }
        let records = try recordsDecoder.decode(
            V4BackupRecordsV1.self,
            from: looseRecords
        )
        try BackupCanonicalEncoderV1().encodeRecords(records).data.write(
            to: recordsURL
        )
        try rebuildManifest(at: root)
    }

    func moveEvidenceBeforeRecord(at root: URL) throws {
        let recordsURL = root.appendingPathComponent("records.json")
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: recordsURL))
                as? [String: Any]
        )
        var evidenceFiles = try XCTUnwrap(
            object["evidenceFiles"] as? [[String: Any]]
        )
        guard let evidenceIndex = evidenceFiles.indices.first else {
            throw FixtureError.invalid
        }
        let evidenceID = try XCTUnwrap(
            evidenceFiles[evidenceIndex]["id"] as? String
        )
        let early = "2020-01-01T00:00:00.000Z"
        evidenceFiles[evidenceIndex]["createdAt"] = early

        var reports = try XCTUnwrap(object["reports"] as? [[String: Any]])
        var updatedSnapshots = 0
        for reportIndex in reports.indices {
            let path = try XCTUnwrap(
                reports[reportIndex]["snapshotRelativePath"] as? String
            )
            let snapshotURL = root.appendingPathComponent(path)
            var snapshotObject = try XCTUnwrap(
                try JSONSerialization.jsonObject(
                    with: Data(contentsOf: snapshotURL)
                ) as? [String: Any]
            )
            var evidence = try XCTUnwrap(
                snapshotObject["evidence"] as? [[String: Any]]
            )
            var changed = false
            for index in evidence.indices where
                evidence[index]["evidenceID"] as? String == evidenceID {
                evidence[index]["createdAt"] = early
                changed = true
            }
            guard changed else { continue }
            snapshotObject["evidence"] = evidence
            let looseSnapshot = try JSONSerialization.data(
                withJSONObject: snapshotObject
            )
            let snapshotDecoder = JSONDecoder()
            snapshotDecoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let string = try container.decode(String.self)
                guard let value = Self.fixtureDateFormatter.date(from: string) else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Invalid fixture date"
                    )
                }
                return value
            }
            let snapshot = try snapshotDecoder.decode(
                ReportSnapshotV1.self,
                from: looseSnapshot
            )
            let encoded = try ReportSnapshotEncoderV1().encode(snapshot)
            try encoded.data.write(to: snapshotURL)
            reports[reportIndex]["snapshotSHA256"] = encoded.sha256
            updatedSnapshots += 1
        }
        guard updatedSnapshots > 0 else { throw FixtureError.invalid }

        object["evidenceFiles"] = evidenceFiles
        object["reports"] = reports
        let looseRecords = try JSONSerialization.data(withJSONObject: object)
        let recordsDecoder = JSONDecoder()
        recordsDecoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let value = Self.fixtureDateFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid fixture date"
                )
            }
            return value
        }
        let records = try recordsDecoder.decode(
            V4BackupRecordsV1.self,
            from: looseRecords
        )
        try BackupCanonicalEncoderV1().encodeRecords(records).data.write(
            to: recordsURL
        )
        try rebuildManifest(at: root)
    }

    func replaceRecordsText(at root: URL, from: String, to: String) throws {
        let url = root.appendingPathComponent("records.json")
        var text = try String(contentsOf: url, encoding: .utf8)
        guard text.contains(from) else { throw FixtureError.invalid }
        text = text.replacingOccurrences(of: from, with: to)
        try XCTUnwrap(text.data(using: .utf8)).write(to: url)
        try rebuildManifest(at: root)
    }

    func setInvalidSiteTimeZone(at root: URL) throws {
        let url = root.appendingPathComponent("records.json")
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url))
                as? [String: Any]
        )
        var sites = try XCTUnwrap(object["sites"] as? [[String: Any]])
        guard sites.count == 1 else { throw FixtureError.invalid }
        sites[0]["timeZoneID"] = "Mars/Olympus"
        object["sites"] = sites
        let loose = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let value = Self.fixtureDateFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid fixture date"
                )
            }
            return value
        }
        let records = try decoder.decode(V4BackupRecordsV1.self, from: loose)
        try BackupCanonicalEncoderV1().encodeRecords(records).data.write(to: url)
        try rebuildManifest(at: root)
    }

    func moveAssetUpdateBeforeCreation(at root: URL) throws {
        let url = root.appendingPathComponent("records.json")
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url))
                as? [String: Any]
        )
        var assets = try XCTUnwrap(object["assets"] as? [[String: Any]])
        guard assets.count == 1 else { throw FixtureError.invalid }
        assets[0]["updatedAt"] = "2020-01-01T00:00:00.000Z"
        object["assets"] = assets
        let loose = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let value = Self.fixtureDateFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid fixture date"
                )
            }
            return value
        }
        let records = try decoder.decode(V4BackupRecordsV1.self, from: loose)
        try BackupCanonicalEncoderV1().encodeRecords(records).data.write(to: url)
        try rebuildManifest(at: root)
    }

    func padAssetLabel(at root: URL) throws {
        let recordsURL = root.appendingPathComponent("records.json")
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: recordsURL))
                as? [String: Any]
        )
        var assets = try XCTUnwrap(object["assets"] as? [[String: Any]])
        guard assets.count == 1 else { throw FixtureError.invalid }
        let padded = " Padded sign "
        assets[0]["label"] = padded

        var reports = try XCTUnwrap(object["reports"] as? [[String: Any]])
        for index in reports.indices {
            let path = try XCTUnwrap(
                reports[index]["snapshotRelativePath"] as? String
            )
            let snapshotURL = root.appendingPathComponent(path)
            var snapshot = try XCTUnwrap(
                try JSONSerialization.jsonObject(
                    with: Data(contentsOf: snapshotURL)
                ) as? [String: Any]
            )
            var asset = try XCTUnwrap(snapshot["asset"] as? [String: Any])
            asset["label"] = padded
            snapshot["asset"] = asset
            let looseSnapshot = try JSONSerialization.data(withJSONObject: snapshot)
            let snapshotDecoder = JSONDecoder()
            snapshotDecoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let string = try container.decode(String.self)
                guard let value = Self.fixtureDateFormatter.date(from: string) else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Invalid fixture date"
                    )
                }
                return value
            }
            let value = try snapshotDecoder.decode(
                ReportSnapshotV1.self,
                from: looseSnapshot
            )
            let encoded = try ReportSnapshotEncoderV1().encode(value)
            try encoded.data.write(to: snapshotURL)
            reports[index]["snapshotSHA256"] = encoded.sha256
        }

        object["assets"] = assets
        object["reports"] = reports
        let looseRecords = try JSONSerialization.data(withJSONObject: object)
        let recordsDecoder = JSONDecoder()
        recordsDecoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let value = Self.fixtureDateFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid fixture date"
                )
            }
            return value
        }
        let records = try recordsDecoder.decode(
            V4BackupRecordsV1.self,
            from: looseRecords
        )
        try BackupCanonicalEncoderV1().encodeRecords(records).data.write(
            to: recordsURL
        )
        try rebuildManifest(at: root)
    }

    func moveTombstoneDeletionBeforeCreation(at root: URL) throws {
        let url = root.appendingPathComponent("records.json")
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url))
                as? [String: Any]
        )
        var packets = try XCTUnwrap(
            object["packets"] as? [[String: Any]]
        )
        let index = try XCTUnwrap(packets.firstIndex {
            $0["currentRecordID"] is NSNull
        })
        packets[index]["contentDeletedAt"] = "2020-01-01T00:00:00.000Z"
        object["packets"] = packets
        let loose = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let value = Self.fixtureDateFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid fixture date"
                )
            }
            return value
        }
        let records = try decoder.decode(V4BackupRecordsV1.self, from: loose)
        try BackupCanonicalEncoderV1().encodeRecords(records).data.write(to: url)
        try rebuildManifest(at: root)
    }

    func changeLivePacketCreation(at root: URL) throws {
        let url = root.appendingPathComponent("records.json")
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url))
                as? [String: Any]
        )
        var packets = try XCTUnwrap(
            object["packets"] as? [[String: Any]]
        )
        let index = try XCTUnwrap(packets.firstIndex {
            !($0["currentRecordID"] is NSNull)
        })
        packets[index]["createdAt"] = "2020-01-01T00:00:00.000Z"
        object["packets"] = packets
        let loose = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let value = Self.fixtureDateFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid fixture date"
                )
            }
            return value
        }
        let records = try decoder.decode(V4BackupRecordsV1.self, from: loose)
        try BackupCanonicalEncoderV1().encodeRecords(records).data.write(to: url)
        try rebuildManifest(at: root)
    }

    func rebuildManifest(
        at root: URL,
        excludingPaths: Set<String> = []
    ) throws {
        let url = root.appendingPathComponent("manifest.json")
        let old = try BackupCanonicalDecoderV1().decodeManifest(Data(contentsOf: url))
        let entries = try old.entries.filter {
            !excludingPaths.contains($0.path)
        }.map { entry -> V4BackupEntryV1 in
            let data = try Data(contentsOf: root.appendingPathComponent(entry.path))
            return .init(byteCount: data.count, mimeType: entry.mimeType, path: entry.path, sha256: data.sha256)
        }
        let manifest = V4BackupManifestV1(
            backupSchemaVersion: old.backupSchemaVersion,
            consumedEvaluationRootIDs: old.consumedEvaluationRootIDs,
            declaredPayloadByteCount: entries.reduce(0) { $0 + $1.byteCount },
            entries: entries,
            exportedAt: old.exportedAt,
            packs: old.packs,
            source: old.source
        )
        try BackupCanonicalEncoderV1().encodeManifest(manifest).data.write(to: url)
    }

    func replaceConsumedRoot(at root: URL) throws {
        let url = root.appendingPathComponent("manifest.json")
        let old = try BackupCanonicalDecoderV1().decodeManifest(Data(contentsOf: url))
        var roots = old.consumedEvaluationRootIDs
        roots[0] = uuid(778)
        roots.sort { $0.uuidString < $1.uuidString }
        let manifest = V4BackupManifestV1(
            backupSchemaVersion: old.backupSchemaVersion,
            consumedEvaluationRootIDs: roots,
            declaredPayloadByteCount: old.declaredPayloadByteCount,
            entries: old.entries,
            exportedAt: old.exportedAt,
            packs: old.packs,
            source: old.source
        )
        try BackupCanonicalEncoderV1().encodeManifest(manifest).data.write(to: url)
    }

    func collideEvidenceIDs(at root: URL) throws {
        let url = root.appendingPathComponent("records.json")
        let records = try BackupCanonicalDecoderV1().decodeRecords(Data(contentsOf: url))
        guard records.evidenceFiles.count >= 2 else { throw FixtureError.invalid }
        var text = try String(contentsOf: url, encoding: .utf8)
        text = text.replacingOccurrences(
            of: records.evidenceFiles[0].id.uuidString.lowercased(),
            with: records.evidenceFiles[1].id.uuidString.lowercased()
        )
        try XCTUnwrap(text.data(using: .utf8)).write(to: url)
        try rebuildManifest(at: root)
    }

    func collideFinalizationMutationIDs(at root: URL) throws {
        let url = root.appendingPathComponent("records.json")
        let records = try BackupCanonicalDecoderV1().decodeRecords(
            Data(contentsOf: url)
        )
        let values = records.workflowRecords.compactMap(\.finalizationMutationID)
        guard values.count >= 2 else { throw FixtureError.invalid }
        var text = try String(contentsOf: url, encoding: .utf8)
        text = text.replacingOccurrences(
            of: values[0].uuidString.lowercased(),
            with: values[1].uuidString.lowercased()
        )
        try XCTUnwrap(text.data(using: .utf8)).write(to: url)
        try rebuildManifest(at: root)
    }

    func addDuplicateCheckDrafts(at root: URL) throws {
        try addCheckDrafts(
            at: root,
            suffixes: [901, 902],
            step: WorkflowDraftStep.wide.rawValue
        )
    }

    func addInvalidReviewDraft(at root: URL) throws {
        try addCheckDrafts(
            at: root,
            suffixes: [903],
            step: WorkflowDraftStep.review.rawValue
        )
    }

    func addInvalidDraftPreflight(at root: URL) throws {
        try addCheckDrafts(
            at: root,
            suffixes: [904],
            step: WorkflowDraftStep.wide.rawValue
        ) { draft in
            draft["afterDarkAcknowledgementCopy"] = "Forged acknowledgement"
        }
    }

    func addCheckDrafts(
        at root: URL,
        suffixes: [Int],
        step: String,
        mutate: ((inout [String: Any]) -> Void)? = nil
    ) throws {
        let url = root.appendingPathComponent("records.json")
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url))
                as? [String: Any]
        )
        var records = try XCTUnwrap(
            object["workflowRecords"] as? [[String: Any]]
        )
        let template = try XCTUnwrap(records.first {
            $0["stage"] as? String == WorkflowStage.check.rawValue
                && $0["state"] as? String == WorkflowState.completed.rawValue
        })
        for suffix in suffixes {
            let id = uuid(suffix).uuidString.lowercased()
            var draft = template
            draft["completedAt"] = NSNull()
            draft["draftStepKey"] = step
            draft["evidenceSourceRecordID"] = NSNull()
            draft["finalizationMutationID"] = NSNull()
            draft["id"] = id
            draft["issueID"] = NSNull()
            draft["outcomeKey"] = NSNull()
            draft["packetID"] = NSNull()
            draft["parentRecordID"] = NSNull()
            draft["recordRevisionRootID"] = id
            draft["revisesRecordID"] = NSNull()
            draft["revisionKind"] = WorkflowRevisionKind.original.rawValue
            draft["state"] = WorkflowState.draft.rawValue
            mutate?(&draft)
            records.append(draft)
        }
        object["workflowRecords"] = records.sorted {
            ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "")
        }
        let loose = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let value = Self.fixtureDateFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid fixture date"
                )
            }
            return value
        }
        let value = try decoder.decode(V4BackupRecordsV1.self, from: loose)
        try BackupCanonicalEncoderV1().encodeRecords(value).data.write(to: url)
        try rebuildManifest(at: root)
    }

    func makeTwoOpenIssueLineages(at root: URL) throws {
        let recordsURL = root.appendingPathComponent("records.json")
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: recordsURL))
                as? [String: Any]
        )
        var workflow = try XCTUnwrap(
            object["workflowRecords"] as? [[String: Any]]
        )
        let recheckIndex = try XCTUnwrap(workflow.firstIndex {
            $0["stage"] as? String == WorkflowStage.recheck.rawValue
                && $0["revisionKind"] as? String
                    == WorkflowRevisionKind.original.rawValue
                && $0["outcomeKey"] as? String == "resolved"
        })
        let recheckID = try XCTUnwrap(workflow[recheckIndex]["id"] as? String)
        let originalIssueID = try XCTUnwrap(
            workflow[recheckIndex]["issueID"] as? String
        )
        let recheckCompletedAt = try XCTUnwrap(
            workflow[recheckIndex]["completedAt"] as? String
        )
        workflow[recheckIndex]["outcomeKey"] = "issue_still_visible"
        for index in workflow.indices where
            workflow[index]["revisionKind"] as? String
                == WorkflowRevisionKind.clericalCorrection.rawValue
                && workflow[index]["revisesRecordID"] as? String == recheckID {
            workflow[index]["outcomeKey"] = "issue_still_visible"
        }

        let separateIndex = try XCTUnwrap(workflow.firstIndex {
            $0["stage"] as? String == WorkflowStage.check.rawValue
                && $0["revisionKind"] as? String
                    == WorkflowRevisionKind.original.rawValue
                && $0["outcomeKey"] as? String == "no_visible_issue"
        })
        let separateID = try XCTUnwrap(
            workflow[separateIndex]["id"] as? String
        )
        let separateCompletedAt = try XCTUnwrap(
            workflow[separateIndex]["completedAt"] as? String
        )
        let assetID = try XCTUnwrap(
            workflow[separateIndex]["assetID"] as? String
        )
        let newIssueID = uuid(906).uuidString.lowercased()
        workflow[separateIndex]["outcomeKey"] = "visible_issue"
        workflow[separateIndex]["issueID"] = newIssueID

        var issues = try XCTUnwrap(object["issues"] as? [[String: Any]])
        let originalIssueIndex = try XCTUnwrap(issues.firstIndex {
            $0["id"] as? String == originalIssueID
        })
        let labelKey = try XCTUnwrap(
            issues[originalIssueIndex]["labelKey"] as? String
        )
        let labelDisplay = try XCTUnwrap(
            issues[originalIssueIndex]["labelDisplaySnapshot"] as? String
        )
        issues[originalIssueIndex]["status"] = IssueStatus.open.rawValue
        issues[originalIssueIndex]["resolvedByRecordID"] = NSNull()
        issues[originalIssueIndex]["updatedAt"] = recheckCompletedAt
        issues.append([
            "assetID": assetID,
            "createdAt": separateCompletedAt,
            "id": newIssueID,
            "labelDisplaySnapshot": labelDisplay,
            "labelKey": labelKey,
            "openedByRecordID": separateID,
            "resolvedByRecordID": NSNull(),
            "schemaVersion": 1,
            "status": IssueStatus.open.rawValue,
            "updatedAt": separateCompletedAt,
        ])
        issues.sort {
            ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "")
        }

        let pack = SignPack.illuminatedSignV1
        let stillVisibleDisplay = try XCTUnwrap(
            pack.outcomeDisplays.first { $0.key == "issue_still_visible" }?.display
        )
        let visibleDisplay = try XCTUnwrap(
            pack.outcomeDisplays.first { $0.key == "visible_issue" }?.display
        )
        var reports = try XCTUnwrap(object["reports"] as? [[String: Any]])
        var updatedSnapshots = 0
        let correctionIDs = Set(workflow.compactMap { record in
            record["revisesRecordID"] as? String == recheckID
                ? record["id"] as? String
                : nil
        })
        for reportIndex in reports.indices {
            let sourceID = try XCTUnwrap(
                reports[reportIndex]["sourceRecordID"] as? String
            )
            let primary = sourceID == recheckID || correctionIDs.contains(sourceID)
            let secondary = sourceID == separateID
            guard primary || secondary else { continue }
            let path = try XCTUnwrap(
                reports[reportIndex]["snapshotRelativePath"] as? String
            )
            let snapshotURL = root.appendingPathComponent(path)
            var snapshot = try XCTUnwrap(
                try JSONSerialization.jsonObject(
                    with: Data(contentsOf: snapshotURL)
                ) as? [String: Any]
            )
            var display = try XCTUnwrap(snapshot["display"] as? [String: Any])
            if primary {
                snapshot["outcome"] = "issue_still_visible"
                display["outcome"] = stillVisibleDisplay
                var snapshots = try XCTUnwrap(
                    snapshot["issues"] as? [[String: Any]]
                )
                let index = try XCTUnwrap(snapshots.firstIndex {
                    $0["issueID"] as? String == originalIssueID
                })
                snapshots[index]["status"] = IssueStatus.open.rawValue
                snapshots[index]["resolvedByRecordID"] = NSNull()
                snapshots[index]["updatedAt"] = recheckCompletedAt
                snapshot["issues"] = snapshots
            } else {
                snapshot["outcome"] = "visible_issue"
                display["outcome"] = visibleDisplay
                snapshot["issues"] = [[
                    "createdAt": separateCompletedAt,
                    "display": labelDisplay,
                    "issueID": newIssueID,
                    "key": labelKey,
                    "openedByRecordID": separateID,
                    "resolvedByRecordID": NSNull(),
                    "status": IssueStatus.open.rawValue,
                    "updatedAt": separateCompletedAt,
                ]]
            }
            snapshot["display"] = display
            let looseSnapshot = try JSONSerialization.data(withJSONObject: snapshot)
            let snapshotDecoder = JSONDecoder()
            snapshotDecoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let string = try container.decode(String.self)
                guard let value = Self.fixtureDateFormatter.date(from: string) else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Invalid fixture date"
                    )
                }
                return value
            }
            let value = try snapshotDecoder.decode(
                ReportSnapshotV1.self,
                from: looseSnapshot
            )
            let encoded = try ReportSnapshotEncoderV1().encode(value)
            try encoded.data.write(to: snapshotURL)
            reports[reportIndex]["snapshotSHA256"] = encoded.sha256
            updatedSnapshots += 1
        }
        guard updatedSnapshots >= 3 else { throw FixtureError.invalid }

        object["workflowRecords"] = workflow
        object["issues"] = issues
        object["reports"] = reports
        let looseRecords = try JSONSerialization.data(withJSONObject: object)
        let recordsDecoder = JSONDecoder()
        recordsDecoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let value = Self.fixtureDateFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid fixture date"
                )
            }
            return value
        }
        let records = try recordsDecoder.decode(
            V4BackupRecordsV1.self,
            from: looseRecords
        )
        try BackupCanonicalEncoderV1().encodeRecords(records).data.write(
            to: recordsURL
        )
        try rebuildManifest(at: root)
    }

    func duplicateDifferentIssueOpener(at root: URL) throws {
        let recordsURL = root.appendingPathComponent("records.json")
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: recordsURL))
                as? [String: Any]
        )
        var workflow = try XCTUnwrap(
            object["workflowRecords"] as? [[String: Any]]
        )
        let recheckIndex = try XCTUnwrap(workflow.firstIndex {
            $0["stage"] as? String == WorkflowStage.recheck.rawValue
                && $0["revisionKind"] as? String
                    == WorkflowRevisionKind.original.rawValue
                && $0["outcomeKey"] as? String == "resolved"
        })
        let recheckID = try XCTUnwrap(workflow[recheckIndex]["id"] as? String)
        let assetID = try XCTUnwrap(
            workflow[recheckIndex]["assetID"] as? String
        )
        let completedAt = try XCTUnwrap(
            workflow[recheckIndex]["completedAt"] as? String
        )
        workflow[recheckIndex]["outcomeKey"] =
            "original_resolved_different_issue"
        var correctionIDs = Set<String>()
        for index in workflow.indices where
            workflow[index]["revisionKind"] as? String
                == WorkflowRevisionKind.clericalCorrection.rawValue
                && workflow[index]["revisesRecordID"] as? String == recheckID {
            workflow[index]["outcomeKey"] =
                "original_resolved_different_issue"
            correctionIDs.insert(
                try XCTUnwrap(workflow[index]["id"] as? String)
            )
        }

        var issues = try XCTUnwrap(object["issues"] as? [[String: Any]])
        let labelKey = try XCTUnwrap(issues.first?["labelKey"] as? String)
        let labelDisplay = try XCTUnwrap(
            issues.first?["labelDisplaySnapshot"] as? String
        )
        let newIDs = [uuid(907), uuid(908)].map {
            $0.uuidString.lowercased()
        }
        for id in newIDs {
            issues.append([
                "assetID": assetID,
                "createdAt": completedAt,
                "id": id,
                "labelDisplaySnapshot": labelDisplay,
                "labelKey": labelKey,
                "openedByRecordID": recheckID,
                "resolvedByRecordID": NSNull(),
                "schemaVersion": 1,
                "status": IssueStatus.open.rawValue,
                "updatedAt": completedAt,
            ])
        }
        issues.sort {
            ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "")
        }

        let outcomeDisplay = try XCTUnwrap(
            SignPack.illuminatedSignV1.outcomeDisplays.first {
                $0.key == "original_resolved_different_issue"
            }?.display
        )
        var reports = try XCTUnwrap(object["reports"] as? [[String: Any]])
        var updatedSnapshots = 0
        for reportIndex in reports.indices {
            let sourceID = try XCTUnwrap(
                reports[reportIndex]["sourceRecordID"] as? String
            )
            guard sourceID == recheckID || correctionIDs.contains(sourceID) else {
                continue
            }
            let path = try XCTUnwrap(
                reports[reportIndex]["snapshotRelativePath"] as? String
            )
            let snapshotURL = root.appendingPathComponent(path)
            var snapshot = try XCTUnwrap(
                try JSONSerialization.jsonObject(
                    with: Data(contentsOf: snapshotURL)
                ) as? [String: Any]
            )
            snapshot["outcome"] = "original_resolved_different_issue"
            var display = try XCTUnwrap(snapshot["display"] as? [String: Any])
            display["outcome"] = outcomeDisplay
            snapshot["display"] = display
            var issueSnapshots = try XCTUnwrap(
                snapshot["issues"] as? [[String: Any]]
            )
            for id in newIDs {
                issueSnapshots.append([
                    "createdAt": completedAt,
                    "display": labelDisplay,
                    "issueID": id,
                    "key": labelKey,
                    "openedByRecordID": recheckID,
                    "resolvedByRecordID": NSNull(),
                    "status": IssueStatus.open.rawValue,
                    "updatedAt": completedAt,
                ])
            }
            issueSnapshots.sort {
                ($0["issueID"] as? String ?? "")
                    < ($1["issueID"] as? String ?? "")
            }
            snapshot["issues"] = issueSnapshots
            let looseSnapshot = try JSONSerialization.data(withJSONObject: snapshot)
            let snapshotDecoder = JSONDecoder()
            snapshotDecoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let string = try container.decode(String.self)
                guard let value = Self.fixtureDateFormatter.date(from: string) else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Invalid fixture date"
                    )
                }
                return value
            }
            let value = try snapshotDecoder.decode(
                ReportSnapshotV1.self,
                from: looseSnapshot
            )
            let encoded = try ReportSnapshotEncoderV1().encode(value)
            try encoded.data.write(to: snapshotURL)
            reports[reportIndex]["snapshotSHA256"] = encoded.sha256
            updatedSnapshots += 1
        }
        guard updatedSnapshots >= 2 else { throw FixtureError.invalid }

        object["workflowRecords"] = workflow
        object["issues"] = issues
        object["reports"] = reports
        let looseRecords = try JSONSerialization.data(withJSONObject: object)
        let recordsDecoder = JSONDecoder()
        recordsDecoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let value = Self.fixtureDateFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid fixture date"
                )
            }
            return value
        }
        let records = try recordsDecoder.decode(
            V4BackupRecordsV1.self,
            from: looseRecords
        )
        try BackupCanonicalEncoderV1().encodeRecords(records).data.write(
            to: recordsURL
        )
        try rebuildManifest(at: root)
    }

    func omitPriorCorrectionReport(at root: URL) throws {
        let recordsURL = root.appendingPathComponent("records.json")
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: recordsURL))
                as? [String: Any]
        )
        let workflow = try XCTUnwrap(
            object["workflowRecords"] as? [[String: Any]]
        )
        let correctionIDs = Set(workflow.compactMap { record in
            record["revisionKind"] as? String
                == WorkflowRevisionKind.clericalCorrection.rawValue
                ? record["id"] as? String
                : nil
        })
        var reports = try XCTUnwrap(object["reports"] as? [[String: Any]])
        let tipIndex = try XCTUnwrap(reports.firstIndex { report in
            guard let sourceID = report["sourceRecordID"] as? String else {
                return false
            }
            return correctionIDs.contains(sourceID)
                && !(report["replacesReportID"] is NSNull)
        })
        let priorID = try XCTUnwrap(reports[tipIndex]["replacesReportID"] as? String)
        let prior = try XCTUnwrap(reports.first { $0["id"] as? String == priorID })
        reports[tipIndex]["replacesReportID"] = NSNull()
        reports.removeAll { $0["id"] as? String == priorID }
        object["reports"] = reports
        let loose = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let value = Self.fixtureDateFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid fixture date"
                )
            }
            return value
        }
        let value = try decoder.decode(V4BackupRecordsV1.self, from: loose)
        try BackupCanonicalEncoderV1().encodeRecords(value).data.write(to: recordsURL)

        let snapshotPath = try XCTUnwrap(prior["snapshotRelativePath"] as? String)
        let pdfPath = try XCTUnwrap(prior["pdfRelativePath"] as? String)
        try fileManager.removeItem(at: root.appendingPathComponent(snapshotPath))
        try fileManager.removeItem(at: root.appendingPathComponent(pdfPath))
        try rebuildManifest(
            at: root,
            excludingPaths: [snapshotPath, pdfPath]
        )
    }

    func mutateCorrectionStartedAt(at root: URL) throws {
        let url = root.appendingPathComponent("records.json")
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url))
                as? [String: Any]
        )
        var records = try XCTUnwrap(
            object["workflowRecords"] as? [[String: Any]]
        )
        let index = try XCTUnwrap(records.firstIndex {
            $0["revisionKind"] as? String
                == WorkflowRevisionKind.clericalCorrection.rawValue
        })
        records[index]["startedAt"] = "2025-01-01T00:00:00.000Z"
        object["workflowRecords"] = records
        let loose = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let value = Self.fixtureDateFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid fixture date"
                )
            }
            return value
        }
        let value = try decoder.decode(V4BackupRecordsV1.self, from: loose)
        try BackupCanonicalEncoderV1().encodeRecords(value).data.write(to: url)
        try rebuildManifest(at: root)
    }

    func moveWorkBeforeParent(at root: URL) throws {
        let early = "2025-01-01T00:00:00.000Z"
        try mutateWorkAndHistory(
            at: root,
            recordMutation: { record in
                record["startedAt"] = early
                record["completedAt"] = early
            },
            historyMutation: { history in
                history["completedAt"] = early
            }
        )
    }

    func setInvalidWorkLocalDate(at root: URL) throws {
        let invalidDate = "2026-99-99"
        try mutateWorkAndHistory(
            at: root,
            recordMutation: { record in
                record["workPerformedLocalDate"] = invalidDate
            },
            historyMutation: { history in
                history["workPerformedLocalDate"] = invalidDate
            }
        )
    }

    func mutateWorkAndHistory(
        at root: URL,
        recordMutation: (inout [String: Any]) -> Void,
        historyMutation: (inout [String: Any]) -> Void
    ) throws {
        let recordsURL = root.appendingPathComponent("records.json")
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: recordsURL))
                as? [String: Any]
        )
        var workflow = try XCTUnwrap(
            object["workflowRecords"] as? [[String: Any]]
        )
        let workIndex = try XCTUnwrap(workflow.firstIndex {
            $0["stage"] as? String == WorkflowStage.work.rawValue
                && $0["state"] as? String == WorkflowState.completed.rawValue
                && $0["revisionKind"] as? String
                    == WorkflowRevisionKind.original.rawValue
        })
        let workID = try XCTUnwrap(workflow[workIndex]["id"] as? String)
        var work = workflow[workIndex]
        recordMutation(&work)
        workflow[workIndex] = work

        var reports = try XCTUnwrap(object["reports"] as? [[String: Any]])
        var updatedSnapshots = 0
        for reportIndex in reports.indices {
            let path = try XCTUnwrap(
                reports[reportIndex]["snapshotRelativePath"] as? String
            )
            let snapshotURL = root.appendingPathComponent(path)
            var snapshotObject = try XCTUnwrap(
                try JSONSerialization.jsonObject(
                    with: Data(contentsOf: snapshotURL)
                ) as? [String: Any]
            )
            var history = try XCTUnwrap(
                snapshotObject["history"] as? [[String: Any]]
            )
            var changed = false
            for historyIndex in history.indices where
                history[historyIndex]["recordID"] as? String == workID {
                var entry = history[historyIndex]
                historyMutation(&entry)
                history[historyIndex] = entry
                changed = true
            }
            guard changed else { continue }
            snapshotObject["history"] = history
            let looseSnapshot = try JSONSerialization.data(
                withJSONObject: snapshotObject
            )
            let snapshotDecoder = JSONDecoder()
            snapshotDecoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let string = try container.decode(String.self)
                guard let value = Self.fixtureDateFormatter.date(from: string) else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "Invalid fixture date"
                    )
                }
                return value
            }
            let snapshot = try snapshotDecoder.decode(
                ReportSnapshotV1.self,
                from: looseSnapshot
            )
            let encoded = try ReportSnapshotEncoderV1().encode(snapshot)
            try encoded.data.write(to: snapshotURL)
            reports[reportIndex]["snapshotSHA256"] = encoded.sha256
            updatedSnapshots += 1
        }
        guard updatedSnapshots > 0 else { throw FixtureError.invalid }

        object["workflowRecords"] = workflow
        object["reports"] = reports
        let looseRecords = try JSONSerialization.data(withJSONObject: object)
        let recordsDecoder = JSONDecoder()
        recordsDecoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let value = Self.fixtureDateFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid fixture date"
                )
            }
            return value
        }
        let records = try recordsDecoder.decode(
            V4BackupRecordsV1.self,
            from: looseRecords
        )
        try BackupCanonicalEncoderV1().encodeRecords(records).data.write(
            to: recordsURL
        )
        try rebuildManifest(at: root)
    }

    func makeParentCycle(at root: URL) throws {
        let url = root.appendingPathComponent("records.json")
        let records = try BackupCanonicalDecoderV1().decodeRecords(Data(contentsOf: url))
        let record = try XCTUnwrap(
            records.workflowRecords.first { $0.parentRecordID == nil }
        )
        var text = try String(contentsOf: url, encoding: .utf8)
        let source = "\"parentRecordID\":null"
        guard let range = text.range(of: source) else { throw FixtureError.invalid }
        text.replaceSubrange(
            range,
            with: "\"parentRecordID\":\"\(record.id.uuidString.lowercased())\""
        )
        try XCTUnwrap(text.data(using: .utf8)).write(to: url)
        try rebuildManifest(at: root)
    }

    func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "63000000-0000-0000-0000-%012d", suffix))!
    }

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

    static let fixtureDateFormatter: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter()
        value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        value.timeZone = TimeZone(secondsFromGMT: 0)
        return value
    }()
}

private enum FixtureError: Error { case invalid }
private extension Data {
    var sha256: String { SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined() }
}

extension S6_3BackupValidationTests {
    func testV23P03C41BackupValidationRejectsNonCanonicalRelationshipBytes() throws {
        let fixture = try C41FunctionalRelationshipTestSupportV1.makeFixture(seed: 41_630)
        var bytes = try FunctionalRelationshipCanonicalCodecV1.encode(fixture.added)
        bytes.append(0x0A)

        XCTAssertThrowsError(
            try FunctionalRelationshipCanonicalCodecV1.decode(
                AssetFunctionalRelationshipEventV1.self, from: bytes
            )
        ) { error in
            XCTAssertEqual(error as? FunctionalRelationshipFailureV1, .nonCanonicalData)
        }
        XCTAssertEqual(fixture.added.eventSHA256.count, 64)
        XCTAssertEqual(fixture.added.mutationID.rawValue, C41FunctionalRelationshipTestSupportV1.mutation(41_641).rawValue)
    }
}

extension S6_3BackupValidationTests {
    func testV23P03C14BackupValidatorRequiresRecordsSchema13AndFiveKinds() throws {
        try V14InspectionReviewImportBoundaryV1.validate(persistent: 14, records: 13)
        XCTAssertEqual(V14BackupInspectionReviewRecordV1.Kind.allCases.count, 5)
        XCTAssertThrowsError(
            try V14InspectionReviewImportBoundaryV1.validate(persistent: 14, records: 12)
        )
    }

    func testV23P03C19BackupRowsRejectCanonicalCorruption() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        let row = try MeasurementSeriesRow(fixture.series)
        XCTAssertEqual(try row.value(), fixture.series)
        row.seriesSHA256 = C19MeasurementIntegrityTestSupport.digest("z")
        XCTAssertThrowsError(try row.value())
    }

    func testC20PrivacyTransformBackupValidationRejectsDuplicateIdentity() throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        let duplicate = fixture.backupRecords + [fixture.backupRecords[0]]
        let keys = duplicate.map { "\($0.kind.rawValue)|\($0.id.uuidString)" }
        XCTAssertNotEqual(Set(keys).count, keys.count)
        XCTAssertThrowsError(try V19PrivacyTransformImportBoundaryV1.validate(persistent: 19, records: 17))
    }
}

extension S6_3BackupValidationTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}
extension S6_3BackupValidationTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(PersistentSchemaV24.models.count, 87)
        XCTAssertEqual(V24BackupSurveyDefinitionRecordV1.Kind.allCases.count, 2)
        XCTAssertEqual(V24SurveyDefinitionImportBoundaryV1.recordsSchemaVersion, 23)
    }
}
extension S6_3BackupValidationTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

extension S6_3BackupValidationTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
private final class C31LightingAnchorS63BackupValidationTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

extension S6_3BackupValidationTests {
    @MainActor
    func testV23P03C42BackupValidationRoundTripsTypedReceiptsForBothArchetypes() async throws {
        let receipts = [try CompositeAreaSafetyArchetypeV1.run(), try ControllerZoneDistributionArchetypeV1.run()]
        for (offset, receipt) in receipts.enumerated() {
            let c42Bytes = try CrossMarketCanonicalV1.data(receipt)
            let payload = c42Bytes.base64EncodedString()
            let harness = try await makeHarness(
                "c42-validation-\(offset)",
                siteAddress: payload
            )
            defer { try? fileManager.removeItem(at: harness.supportURL) }
            let package = try exportPackage(harness, name: "c42-source-\(offset)")
            let importer = try makeImporter(
                harness,
                capacity: .max,
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
            XCTAssertEqual(
                try BackupCanonicalEncoderV1().encodeRecords(validated.records).data,
                try XCTUnwrap(validated.members["records.json"])
            )
        }
    }
}

private final class C33TemporalEvidenceAnchorS63BackupValidation: XCTestCase {
    func testC33S63BackupValidationCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "backup.validation.temporal-evidence",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "backup.validation.temporal-evidence",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

private final class C32AssistanceAnchorS63BackupValidation: XCTestCase {
    func testC32S63BackupValidationCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .packet,
            fieldID: "backup.version-gate",
            value: .singleOption("RECORDS_31")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .packet,
            fieldID: "backup.version-gate",
            valueKind: .singleOption
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}

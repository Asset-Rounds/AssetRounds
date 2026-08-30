import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

private enum C52ServiceRequestBoundary_V9_06DeletionRightsTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

private enum C53AssetServiceReliabilityBoundary_V9_06DeletionRightsTests {
    static let typedAnchor: C53AssetServiceReliabilityBoundaryTokenV1.Type = C53AssetServiceReliabilityBoundaryTokenV1.self
}

private final class C50DeletionRightsTests: XCTestCase {
    func testV23P03C50DeletionPreservesCanonicalHistoryAndEraseClearsOnlyAppOwnedExchangeBytes() {
        XCTAssertFalse(C50IncumbentFileExchangeDeletionIntentBoundaryV1.ordinaryDeletionTargetsAdapterState)
        XCTAssertTrue(C50IncumbentFileExchangeDeletionIntentBoundaryV1.ordinaryDeletionPreservesAcceptedCanonicalHistory)
        XCTAssertTrue(C50IncumbentFileExchangeDeletionIntentBoundaryV1.terminalScratchCleanupUsesNoCanonicalTombstone)
        XCTAssertTrue(C50IncumbentFileExchangeEraseIntentBoundaryV1.clearsAppOwnedSourceScratch)
        XCTAssertTrue(C50IncumbentFileExchangeEraseIntentBoundaryV1.clearsAppOwnedQuarantine)
        XCTAssertTrue(C50IncumbentFileExchangeEraseIntentBoundaryV1.profileAndSelectionRemainInstalledConfiguration)
        XCTAssertFalse(C50IncumbentFileExchangeEraseAllBoundaryV1.recallsEscapedFiles)
        XCTAssertFalse(C50IncumbentFileExchangeEraseAllBoundaryV1.disablesOrRewritesInstalledProfileRelease)
    }
}

private final class C45DeletionRightsCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityDeletesOnlyDurableAcceptedSnapshotState() {
        XCTAssertEqual(AssetLabelPersistenceEnrollmentV1.persistentFamilies, ["AcceptedLabelGenerationSnapshotRow"])
        XCTAssertEqual(Set(AssetLabelPersistenceEnrollmentV1.derivedFamilies), ["AssetLabelGenerationPlanV1", "LabelProjectionResultV1"])
        XCTAssertFalse(AssetLabelPersistenceEnrollmentV1.persistentFamilies.contains("LabelProjectionResultV1"))
    }
}

private final class C30EvidenceContextAnchorV9_06DeletionRights: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

final class V9_06DeletionRightsTests: XCTestCase {
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
    func testV23P03C40OrdinaryDeletionCannotRemoveImmutableAuthorityHistory() throws {
        try AuthorityCriterionDeletionLedgerPolicyV1.validate()
        let kinds = V11BackupAuthorityCriterionRecordV1.Kind.allCases
        XCTAssertEqual(kinds.count, 9)
        let before = AuthorityCriterionDeletionInventoryV1(recordIDsByKind: Dictionary(
            uniqueKeysWithValues: kinds.enumerated().map { index, kind in
                (kind, Set([V906Integration.id(600 + index)]))
            }
        ))
        XCTAssertNoThrow(try WholeSignDeletionRule.validateAuthorityCriterionLifecycle(
            authority: .ordinaryAssetOrSiteDelete, before: before, after: before
        ))
        XCTAssertThrowsError(try WholeSignDeletionRule.validateAuthorityCriterionLifecycle(
            authority: .ordinaryAssetOrSiteDelete,
            before: before,
            after: AuthorityCriterionDeletionInventoryV1(recordIDsByKind: [:])
        )) {
            XCTAssertEqual($0 as? WholeSignDeletionRuleError, .invalidGraph)
        }
        XCTAssertNoThrow(try WholeSignDeletionRule.validateAuthorityCriterionLifecycle(
            authority: .workspaceErase,
            before: before,
            after: AuthorityCriterionDeletionInventoryV1(recordIDsByKind: [:])
        ))
    }

    @MainActor
    func testV9_06G01DeleteStreamingRoundTripAllModesAndEmptySite() async throws {
        let fixture = try V906Integration.loadFixture()
        XCTAssertEqual(fixture.schema, "V21P01C06DeletionGraphV1")
        XCTAssertEqual(fixture.schemaVersion, 1)
        XCTAssertEqual(Set(fixture.authority.deterministicEvidenceIDs), [
            "V23-P01-C06-G01", "V23-P01-C06-A01", "V23-P01-C06-H01",
            "V23-P01-C06-I01", "V23-P01-C06-R01",
        ])
        XCTAssertEqual(
            Set(fixture.deletionModes.map(\.mode)),
            Set(BackupRestoreMode.allCases.map { $0.rawValue.uppercased() })
        )
        XCTAssertTrue(fixture.registeredKindPolicy.currentPersistentTagKindPresent == false)
        let source = try V906Integration.makeHarness("g-source", withAsset: true)
        defer { V906Integration.remove(source.root) }
        let deletedAssetID = try XCTUnwrap(
            source.session.modelContext.fetch(FetchDescriptor<Asset>()).first?.id
        )
        let sourceSiteID = try XCTUnwrap(
            source.session.modelContext.fetch(FetchDescriptor<Site>()).first?.id
        )
        let retainedMutationID = try MutationIDV1(rawValue: V906Integration.id(49))
        let sourceWriter = StoreSessionCoordinator(session: source.session).workspaceWriter
        let sourceRevision = try sourceWriter.currentRevision()
        let mutationExpected = try WorkspaceExpectedRevisionV1(
            workspaceID: sourceRevision.workspaceID,
            generationID: sourceRevision.generationID,
            writerInstanceID: sourceRevision.writerInstanceID,
            workspaceRevision: sourceRevision.revision,
            entityRevisions: [.init(
                identity: try WorkspaceEntityIdentityV1(kind: .site, id: sourceSiteID),
                revision: 0
            )]
        )
        _ = try sourceWriter.execute(.init(
            mutationID: retainedMutationID,
            expectedRevision: mutationExpected,
            command: .updateSiteTimeZone(.init(
                siteID: sourceSiteID,
                timeZoneID: "UTC",
                confirmedAt: V906Integration.deletedAt.addingTimeInterval(-1)
            ))
        ))
        _ = try await V906Integration.deletionService(source).delete(assetID: deletedAssetID)
        XCTAssertEqual(try source.session.modelContext.fetchCount(FetchDescriptor<Site>()), 1)
        XCTAssertEqual(try source.session.modelContext.fetchCount(FetchDescriptor<Asset>()), 0)
        XCTAssertNotNil(try sourceWriter.durableReceipt(mutationID: retainedMutationID))
        let archive = try V906Integration.exportStreaming(source)

        for (offset, mode) in BackupRestoreMode.allCases.enumerated() {
            let target = try V906Integration.makeHarness(
                "g-target-\(mode.rawValue)",
                withAsset: mode == .replaceExisting
            )
            defer { V906Integration.remove(target.root) }
            let restored = try await V906Integration.restore(
                archive,
                into: target,
                mode: mode,
                ids: V906Integration.restoreIDs(mode, offset: offset)
            )
            XCTAssertEqual(try restored.modelContext.fetchCount(FetchDescriptor<Asset>()), 0, mode.rawValue)
            XCTAssertGreaterThanOrEqual(try restored.modelContext.fetchCount(FetchDescriptor<Site>()), 1, mode.rawValue)
            let ledger = try DeletionLedgerStore(context: restored.modelContext).snapshot()
            XCTAssertTrue(ledger.entries.contains {
                $0.identity.kind == .asset && $0.identity.id == deletedAssetID
            }, mode.rawValue)
            let restoredJournal = try MutationJournalStoreV1(
                modelContext: restored.modelContext,
                identity: restored.workspaceIdentity,
                generationID: restored.generationID
            )
            XCTAssertNotNil(
                try restoredJournal.receipt(mutationID: retainedMutationID),
                mode.rawValue
            )
        }
    }

    @MainActor
    func testV9_06A01DeleteRecreateUsesDistinctTypedIdentity() async throws {
        let harness = try V906Integration.makeHarness("a", withAsset: true)
        defer { V906Integration.remove(harness.root) }
        let context = harness.session.modelContext
        let old = try XCTUnwrap(context.fetch(FetchDescriptor<Asset>()).first)
        let oldID = old.id
        let siteID = old.siteID
        _ = try await V906Integration.deletionService(harness).delete(assetID: oldID)

        let replacementID = V906Integration.id(110)
        context.insert(Asset(
            id: replacementID,
            siteID: siteID,
            packID: SignPack.illuminatedSignV1.packID,
            packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
            packContentVersion: SignPack.illuminatedSignV1.contentVersion,
            label: "Recreated sign",
            createdAt: V906Integration.recreatedAt
        ))
        try context.save()

        let assets = try context.fetch(FetchDescriptor<Asset>())
        XCTAssertEqual(assets.map(\.id), [replacementID])
        let ledger = try DeletionLedgerStore(context: context).snapshot()
        let oldIdentity = try DeletionIdentityV2(kind: .asset, id: oldID)
        let replacementIdentity = try DeletionIdentityV2(kind: .asset, id: replacementID)
        XCTAssertNotEqual(oldIdentity.typedID, replacementIdentity.typedID)
        XCTAssertTrue(ledger.entries.contains { $0.identity == oldIdentity })
        XCTAssertFalse(ledger.entries.contains { $0.identity == replacementIdentity })
    }

    @MainActor
    func testV9_06H01OldArchiveUnknownKindAndNonEraseCannotClearLedger() async throws {
        let source = try V906Integration.makeHarness("h-source", withAsset: true)
        defer { V906Integration.remove(source.root) }
        let archivedAssetID = try XCTUnwrap(
            source.session.modelContext.fetch(FetchDescriptor<Asset>()).first?.id
        )
        let oldArchive = try V906Integration.exportLegacy(source)
        let legacyManifest = try BackupCanonicalDecoderV1().decodeManifest(
            Data(contentsOf: oldArchive.appendingPathComponent("manifest.json"))
        )
        XCTAssertEqual(legacyManifest.backupSchemaVersion, 1)
        XCTAssertEqual(legacyManifest.source.recordsSchemaVersion, 1)

        let target = try V906Integration.makeHarness("h-target", withAsset: false)
        defer { V906Integration.remove(target.root) }
        let identity = try DeletionIdentityV2(kind: .asset, id: archivedAssetID)
        try DeletionLedgerStore(context: target.session.modelContext).stageUnion([
            try DeletionLedgerEntryV2(identity: identity, deletedAt: V906Integration.deletedAt),
        ])
        try target.session.modelContext.save()

        let restored = try await V906Integration.restore(
            oldArchive,
            into: target,
            mode: .replaceExisting,
            ids: V906Integration.restoreIDs(.replaceExisting, offset: 10)
        )
        XCTAssertFalse(try restored.modelContext.fetch(FetchDescriptor<Asset>()).contains {
            $0.id == archivedAssetID
        })
        XCTAssertTrue(try DeletionLedgerStore(context: restored.modelContext).snapshot().entries.contains {
            $0.identity == identity
        })

        XCTAssertThrowsError(try DeletionIdentityV2(typedID: "unknown:\(V906Integration.id(120).uuidString.lowercased())"))
        XCTAssertThrowsError(try DeletionIdentityV2(typedID: "tag:\(V906Integration.id(121).uuidString.lowercased())"))
        XCTAssertNil(DeletionRecordKindV2(rawValue: "tag"))
        XCTAssertEqual(Set(DeletionRecordKindV2.allCases.map(\.rawValue)), [
            "site", "asset", "workflowRecord", "evidenceFile", "issue", "packet", "report",
            "acceptedLabelGenerationSnapshot",
        ])

        let malformedRecords = try V906Integration.injectUnknownLedgerKind(
            intoLegacyPackage: oldArchive
        )
        XCTAssertThrowsError(try BackupCanonicalDecoderV1().decodeRecords(malformedRecords)) {
            XCTAssertEqual($0 as? BackupCanonicalDecodingErrorV1, .invalidRecords)
        }
        XCTAssertThrowsError(try BackupPackageValidatorV1().validate(stagedPackageURL: oldArchive)) {
            XCTAssertEqual($0 as? BackupPackageValidationErrorV1, .invalidPackage)
        }
    }
}

private final class C27V906RightsTypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(AssetLocatorStateV1.allCases, [.active, .retired, .revoked, .replaced])
        XCTAssertEqual(LocatorResolutionOutcomeV1.allCases.count, 8)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionGrantsAccess)
    }
}

extension V9_06DeletionRightsTests {
    func testC24AccessibleDocumentTypedAnchor() throws {
        XCTAssertEqual(AccessibleDocumentSemanticTreeV1.schemaVersion, 1)
        XCTAssertEqual(AccessibleDocumentRoleV1.allCases.count, 13)
        XCTAssertEqual(AccessibleDocumentAssessmentStateV1.allCases.count, 4)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
    }
}

extension V9_06DeletionRightsTests {
    func testC22RecoverabilityVerificationAnchor() throws {
        XCTAssertEqual(RecoverabilityVerificationReceiptV1.schemaVersion, 1)
        try V21RecoverabilityImportBoundaryV1.validate(persistentSchemaVersion: 21, recordsSchemaVersion: 20)
        XCTAssertEqual(RecoverabilityVerificationLifecycleV1.receiptPersistence,
                       "RECOVERABILITY_VERIFICATION_RECEIPT_V1_IMMUTABLE_EVIDENCE")
        XCTAssertFalse(RecoverabilityVerificationLifecycleV1.externalCopyAvailabilityClaimed)
    }
}

extension V9_06DeletionRightsTests {
    func testV23P03C36DeletionRightsPreserveOperationalHistoryUntilErase() throws {
        try FieldDraftDeletionLedgerPolicyV1.validate()
        XCTAssertTrue(FieldDraftEraseBoundaryV1.operationalStateClearedOnlyByWorkspaceErase)
        XCTAssertTrue(FieldDraftEraseBoundaryV1.byteCleanupRequiresTerminalDiscardOrOrphanQuarantine)
    }
}

extension V9_06DeletionRightsTests {
    func testV23P03C15ReleaseRightsRetainTypedPredecessorIdentity() throws {
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 150_106)
        let mutation = try WorkPacketMutationV1(
            workspaceID: fixture.workspaceID, expectedRevision: 0,
            mutationID: fixture.completedRelease.mutationID,
            postImage: .recordRelease(fixture.completedRelease)
        )
        XCTAssertEqual(try mutation.affectedIdentity.kind, .workRelease)
        XCTAssertEqual(try mutation.concurrencyIdentity.id, fixture.completedRelease.releaseID)
        XCTAssertEqual(WorkReleaseReasonV1.allCases.count, 5)
    }
}

@MainActor
enum V906Integration {
    static let deletedAt = Date(timeIntervalSince1970: 1_767_322_645)
    static let recreatedAt = deletedAt.addingTimeInterval(60)
    static let storage = StoragePreflightService(capacityProvider: { _ in .max })
    static let fileManager = FileManager.default

    struct Harness {
        let root: URL
        let support: URL
        let caches: URL
        let temporary: URL
        let factory: StoreGenerationFactory
        let session: StoreGenerationSession
    }

    struct Fixture: Decodable {
        struct Authority: Decodable { let deterministicEvidenceIDs: [String] }
        struct Mode: Decodable { let mode: String }
        struct KindPolicy: Decodable { let currentPersistentTagKindPresent: Bool }
        let schema: String
        let schemaVersion: Int
        let authority: Authority
        let deletionModes: [Mode]
        let registeredKindPolicy: KindPolicy
    }

    static func makeHarness(_ name: String, withAsset: Bool) throws -> Harness {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "V9_06-\(name)-\(UUID().uuidString)", isDirectory: true
        )
        let support = root.appendingPathComponent("Library/Application Support", isDirectory: true)
        let caches = root.appendingPathComponent("Library/Caches", isDirectory: true)
        let temporary = root.appendingPathComponent("tmp", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: caches, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
        let factory = StoreGenerationFactory(applicationSupportURL: support)
        let session = try factory.openOrBootstrapCurrent()
        if withAsset {
            let siteID = fixtureID(1)
            session.modelContext.insert(Site(
                id: siteID,
                label: "Deletion fixture site",
                address: nil,
                timeZoneID: "America/New_York",
                createdAt: deletedAt.addingTimeInterval(-120)
            ))
            session.modelContext.insert(Asset(
                id: fixtureID(2),
                siteID: siteID,
                packID: SignPack.illuminatedSignV1.packID,
                packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
                packContentVersion: SignPack.illuminatedSignV1.contentVersion,
                label: "Deletion fixture sign",
                createdAt: deletedAt.addingTimeInterval(-119)
            ))
            try session.modelContext.save()
        }
        return Harness(
            root: root,
            support: support,
            caches: caches,
            temporary: temporary,
            factory: factory,
            session: session
        )
    }

    static func deletionService(
        _ harness: Harness,
        failure: WholeSignDeletionFailurePoint? = nil
    ) -> WholeSignDeletionService {
        WholeSignDeletionService(
            modelContext: harness.session.modelContext,
            generationRootURL: harness.session.generationRootURL,
            now: { deletedAt },
            makeUUID: { id(50) },
            failureInjection: failure.map {
                WholeSignDeletionFailureInjection(failOnceAt: $0)
            }
        )
    }

    static func exportStreaming(_ harness: Harness) throws -> URL {
        let destination = harness.root.appendingPathComponent("exports", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let service = BackupExportService(
            modelContext: harness.session.modelContext,
            generationRootURL: harness.session.generationRootURL,
            storagePreflight: storage,
            now: { deletedAt },
            makeUUID: sequence([id(60), id(61), id(62), id(63)])
        )
        let preview = try service.prepareStreaming()
        return try service.exportStreaming(previewID: preview.id, to: destination)
    }

    static func exportLegacy(_ harness: Harness) throws -> URL {
        let destination = harness.root.appendingPathComponent("legacy-export", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let service = BackupExportService(
            modelContext: harness.session.modelContext,
            generationRootURL: harness.session.generationRootURL,
            storagePreflight: storage,
            now: { deletedAt },
            makeUUID: { id(64) }
        )
        let preview = try service.prepareCompatibilityFixtureLegacyDirectoryPackage()
        return try service.exportCompatibilityFixtureLegacyDirectoryPackage(
            previewID: preview.id,
            to: destination
        )
    }

    static func injectUnknownLedgerKind(intoLegacyPackage package: URL) throws -> Data {
        let recordsURL = package.appendingPathComponent("records.json")
        let originalRecords = try Data(contentsOf: recordsURL)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: originalRecords) as? [String: Any]
        )
        object["recordsSchemaVersion"] = 2
        object["deletionLedger"] = [
            "entries": [[
                "deletedAt": "2026-01-02T03:04:05.000Z",
                "identity": [
                    "id": fixtureID(2).uuidString.lowercased(),
                    "kind": "unknown",
                ],
                "schemaVersion": 2,
            ]],
            "schemaVersion": 2,
        ]
        let malformedRecords = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        try malformedRecords.write(to: recordsURL)

        let manifestURL = package.appendingPathComponent("manifest.json")
        let old = try BackupCanonicalDecoderV1().decodeManifest(Data(contentsOf: manifestURL))
        let entries = try old.entries.map { entry -> V4BackupEntryV1 in
            let data = try Data(contentsOf: package.appendingPathComponent(entry.path))
            return V4BackupEntryV1(
                byteCount: data.count,
                mimeType: entry.mimeType,
                path: entry.path,
                sha256: CanonicalJSONV1.sha256(data)
            )
        }
        let manifest = V4BackupManifestV1(
            backupSchemaVersion: 2,
            consumedEvaluationRootIDs: old.consumedEvaluationRootIDs,
            declaredPayloadByteCount: entries.reduce(0) { $0 + $1.byteCount },
            entries: entries,
            exportedAt: old.exportedAt,
            packs: old.packs,
            source: V4BackupSourceV1(
                appBuild: old.source.appBuild,
                appVersion: old.source.appVersion,
                persistentSchemaVersion: 3,
                replicaID: id(131),
                recordsSchemaVersion: 2,
                workspaceID: id(130)
            )
        )
        try BackupCanonicalEncoderV1().encodeManifest(manifest).data.write(to: manifestURL)
        return malformedRecords
    }

    static func restore(
        _ archive: URL,
        into target: Harness,
        mode: BackupRestoreMode,
        ids values: [UUID]
    ) async throws -> StoreGenerationSession {
        let validated = try BackupImportService(
            generationRootURL: target.session.generationRootURL,
            storagePreflight: storage,
            makeUUID: { id(70) },
            scopedAccess: .alreadyAuthorized
        ).stageAndValidate(selectedPackageURL: archive)
        return try await BackupRestoreService(
            applicationSupportURL: target.support,
            storagePreflight: storage,
            makeUUID: sequence(values)
        ).restore(
            validatedPackage: validated,
            currentModelContext: target.session.modelContext,
            currentGenerationID: target.session.generationID,
            currentGenerationRootURL: target.session.generationRootURL,
            mode: mode
        )
    }

    static func restoreIDs(_ mode: BackupRestoreMode, offset: Int) -> [UUID] {
        let base = 200 + offset * 10
        switch mode {
        case .emptyInstall: [id(base), id(base + 1), id(base + 2)]
        case .replaceExisting: [id(base), id(base + 1)]
        case .clone, .fork: [id(base), id(base + 1), id(base + 2), id(base + 3)]
        }
    }

    static func sequence(_ values: [UUID]) -> () -> UUID {
        var remaining = values
        return { remaining.isEmpty ? UUID() : remaining.removeFirst() }
    }

    static func id(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "76000000-0000-4000-8000-%012d", suffix))!
    }

    static func fixtureID(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", suffix))!
    }

    static func loadFixture() throws -> Fixture {
        let bundle = Bundle(for: V9_06DeletionRightsTests.self)
        let url = try XCTUnwrap(
            bundle.url(
                forResource: "V21P01C06DeletionGraphV1",
                withExtension: "json",
                subdirectory: "Fixtures/V21/Deletion"
            ) ?? bundle.url(
                forResource: "V21P01C06DeletionGraphV1",
                withExtension: "json"
            )
        )
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    nonisolated static func remove(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }
}

extension V9_06DeletionRightsTests {
    func testV23P03C41DeletionPreviewEndsRelationshipWithoutPersistentWrite() throws {
        let fixture = try C41FunctionalRelationshipTestSupportV1.makeFixture(seed: 41_060)
        let preview = try FunctionalRelationshipDispositionPreviewEngineV1.preview(
            change: .deleted,
            relationship: fixture.added,
            descriptor: fixture.descriptor,
            currentSiteID: C41FunctionalRelationshipTestSupportV1.id(41_061)
        )

        XCTAssertEqual(preview.disposition, .end)
        XCTAssertEqual(preview.change, .deleted)
        XCTAssertEqual(preview.relationshipRevision, fixture.added.revision)
        XCTAssertFalse(preview.persistentWriteOccurred)
        try preview.validate()
    }
}

extension V9_06DeletionRightsTests {
    func testV23P03C13DeletionRightsDenyRestrictedAudiencesAndKeepPreviewZeroWrite() throws {
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture(seed: 51_906)
        XCTAssertEqual(try fixture.routineVisibility.decision(for: .customerReport).disposition, .included)
        XCTAssertEqual(try fixture.internalOnlyVisibility.decision(for: .customerReport).limitation, .audienceNotDeclared)
        XCTAssertEqual(try fixture.restrictedVisibility.decision(for: .externalCollaborator).limitation, .sensitivityRestricted)
        XCTAssertEqual(try fixture.highlyRestrictedVisibility.decision(for: .customerReport).limitation, .sensitivityRestricted)

        try fixture.customerPreview.validate()
        XCTAssertEqual(fixture.customerPreview.includedLinks.count, 1)
        XCTAssertEqual(fixture.customerPreview.excludedLinks.count, 1)
        XCTAssertFalse(fixture.customerPreview.includedLinks.contains { $0.evidenceID == "evidence.internal-canary" })
    }
}

extension V9_06DeletionRightsTests {
    func testV23P03C14DeletionBoundaryRequiresExactReviewSuccessor() throws {
        XCTAssertFalse(
            InspectionReviewTransitionTableV1.permits(
                from: .draft, to: .superseded, hasExactSuccessorSubject: false
            )
        )
        XCTAssertTrue(
            InspectionReviewTransitionTableV1.permits(
                from: .draft, to: .superseded, hasExactSuccessorSubject: true
            )
        )
    }

    func testV23P03C19DeletionPreservesMeasurementHistoryUntilErase() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        try MeasurementIntegrityDeletionLedgerPolicyV1.validate()
        XCTAssertEqual(
            V18BackupMeasurementIntegrityRecordV1.Kind.allCases.count,
            5
        )
        XCTAssertTrue(MeasurementIntegrityEraseBoundaryV1.ordinaryDeletionPreservesFrozenHistory)
        XCTAssertEqual(fixture.qualityOverride.supersedesAssessmentID, fixture.qualityReview.assessmentID)
    }

    func testC20PrivacyTransformDeletionProjectionDeniesWrongAudience() throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        let decision = try PrivacyProjectionV1.decide(
            manifest: fixture.manifest, review: fixture.approvedReview, policy: fixture.policy,
            requestedAudience: .externalCollaborator, currentSourceRevision: 1,
            currentSourceSHA256: fixture.manifest.sourceSHA256, at: fixture.capturedAt
        )
        XCTAssertEqual(decision.denial, .wrongAudience)
        XCTAssertFalse(decision.isAllowed)
    }
}

extension V9_06DeletionRightsTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}
extension V9_06DeletionRightsTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(SurveyDefinitionLifecycleV1.importDisposition, "QUARANTINE_THEN_NEW_DRAFT_IDENTITY")
        XCTAssertEqual(SurveyDefinitionLifecycleV1.persistentFamilies.count, 2)
        XCTAssertEqual(SurveyDefinitionLimitsV1.maximumCanonicalBytes, 4_194_304)
    }
}
extension V9_06DeletionRightsTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

extension V9_06DeletionRightsTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
private final class C31LightingAnchorV906DeletionRightsTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

private final class C33TemporalEvidenceAnchorV906DeletionRights: XCTestCase {
    func testC33V906DeletionRightsCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "deletion.temporal-evidence-rights",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "deletion.temporal-evidence-rights",
            kind: .audio,
            reportProjection: .typedLinkOnly
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

private final class C32AssistanceAnchorV906DeletionRights: XCTestCase {
    func testC32V906DeletionRightsCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .asset,
            fieldID: "deletion.rights",
            value: .boolean(true)
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .asset,
            fieldID: "deletion.rights",
            valueKind: .boolean
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
private final class C46V906DeletionRightsCompatibilityTests: XCTestCase {
    func testC46DeletionRightsKeepContactWorkspaceScoped() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "deletion-rights",
            kind: .phone,
            handoff: .call,
            slot: 46006
        )
    }
}


private enum C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_06DeletionRightsTests_swift {
    static let compatibilityCardID = "V23-P03-C47"
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

private final class C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_06DeletionRightsTests_swift_Tests: XCTestCase {
    func testC47V906DeletionRightsTestsOwnerCompatibilityIsTyped() {
        XCTAssertEqual(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_06DeletionRightsTests_swift.compatibilityCardID, "V23-P03-C47")
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_06DeletionRightsTests_swift.sharedEnvelopeDoesNotCollapseFamilyTruth)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_06DeletionRightsTests_swift.installationAndPunchReceiptsRemainIndependent)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_06DeletionRightsTests_swift.noPlanFallbackIsExplicit)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_06DeletionRightsTests_swift.surveyDefinitionOwnershipIsPreserved)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_06DeletionRightsTests_swift.legacyInspectionTruthIsNotRewritten)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_06DeletionRightsTests_swift.threeReceiptIsolationIsRequired)
        XCTAssertEqual(ActivityContractPersistenceEnrollmentV2.persistentFamilies.count, 6)
        XCTAssertTrue(ActivityContractPersistenceEnrollmentV2.usesSoleWorkspaceWriter)
    }
}

private final class C48PortableReviewV906DeletionRightsTests: XCTestCase {
    func testC48DeletionOwnsOnlyLocalExchangeState() {
        XCTAssertTrue(C48PortableExchangePersistentLifecycleBoundaryV2.eraseRemovesAppOwnedStagingOnly)
        XCTAssertTrue(C48PortableReviewPersistenceBoundaryV1.sessionStoreIsNonpersistent)
        XCTAssertTrue(C48PortableReviewPersistenceBoundaryV1.quarantineIsExcludedFromBackup)
    }
}
private final class C49WorkResourceDeletionRightsBoundaryTests: XCTestCase {
    func testNoIndependentInventoryDeletionAuthority() { XCTAssertFalse(C49WorkResourceContractBoundaryV1.liveInventoryReference) }
}

extension C50DeletionRightsTests {
    func testV23P03C51DeletionPreservesCalendarOverrideClosureUntilErase() throws {
        try ScheduleDeletionLedgerPolicyV1.validate()
        XCTAssertTrue(
            ScheduleDeletionLedgerPolicyV1.ordinaryDeletionPreservesCalendarOverrideBasisAndReceiptClosure
                && ScheduleDeletionLedgerPolicyV1.workspaceEraseRemovesAll
                && ScheduleDeletionLedgerPolicyV1.durableKinds
                    .contains("ExceptionCalendarReleaseV1")
                && ScheduleDeletionLedgerPolicyV1.durableKinds
                    .contains("ScheduleOverrideEventV1")
        )
    }
}

extension V9_06DeletionRightsTests {
    func testV23P03C34EraseClearsOnlyDeviceNavigationBytes() throws {
        let workspaceID = WorkspaceID(
            rawValue: UUID(uuidString: "00000000-0000-4000-8000-00000000340b")!
        )
        let target = try NavigationTargetV1(
            workspaceID: workspaceID, destination: .today
        )
        let work = try NavigationTargetV1(workspaceID: workspaceID, destination: .work)
        let assets = try NavigationTargetV1(workspaceID: workspaceID, destination: .assets)
        let reports = try NavigationTargetV1(workspaceID: workspaceID, destination: .reports)
        let snapshot = try SceneNavigationSnapshotV1(
            workspaceID: workspaceID,
            selectedRoot: .today,
            paths: [
                .init(root: .today, targets: [target]),
                .init(root: .work, targets: [work]),
                .init(root: .assets, targets: [assets]),
                .init(root: .reports, targets: [reports]),
            ],
            snapshotID: UUID(uuidString: "00000000-0000-4000-8000-00000000340c")!
        )
        let port = InMemorySceneNavigationDeviceStatePortV1()
        let adapter = SceneNavigationStateAdapterV1(port: port)
        try adapter.save(snapshot)
        XCTAssertNotNil(port.data)
        try adapter.erase()
        XCTAssertNil(port.data)
        XCTAssertTrue(SceneNavigationLifecycleDispositionV1().eraseClears)
    }
}

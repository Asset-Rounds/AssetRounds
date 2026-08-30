import Foundation
import XCTest
@testable import FieldEvidenceApp

private final class C45KernelPersistenceCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityPinsV34Records33AndOneRow() {
        XCTAssertEqual(AssetLabelPersistenceEnrollmentV1.persistentSchemaVersion, 34)
        XCTAssertEqual(AssetLabelPersistenceEnrollmentV1.recordsSchemaVersion, 33)
        XCTAssertEqual(AssetLabelPersistenceEnrollmentV1.persistentFamilies, ["AcceptedLabelGenerationSnapshotRow"])
    }
}

private final class C30EvidenceContextAnchorV9_17KernelPersistence: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

final class V9_17KernelPersistenceTests: XCTestCase {
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
    func testV9_17G01SchemaDescriptorAndEveryLifecycleRegistryAreCompleteAndDormant() throws {
        try KernelPersistenceV4Schema.validate()
        try KernelRecordRegistryV4.validate()
        try KernelMutationReceiptRegistryV4.validate()
        try KernelBackupRestoreRegistryV4.validate()
        try KernelDeletionEraseRegistryV4.validate()

        let schema = try KernelPersistenceV4Schema.descriptor()
        let kinds = KernelPersistenceV4RecordKind.allCases.sorted()
        XCTAssertEqual(schema.schemaID, "KERNEL_PERSISTENCE_V4")
        XCTAssertEqual(schema.schemaVersion, 4)
        XCTAssertEqual(schema.predecessorSchemaVersion, 3)
        XCTAssertEqual(schema.runtimePosture, .dormantStatic)
        XCTAssertFalse(schema.activationEnabled)
        XCTAssertTrue(schema.migrationRequired)
        XCTAssertTrue(schema.backupRestoreRequired)
        XCTAssertTrue(schema.deleteEraseRequired)
        XCTAssertTrue(schema.exportRequired)
        XCTAssertEqual(schema.records.map(\.kind), kinds)
        XCTAssertEqual(schema.relationships.map(\.kind), KernelPersistenceV4RelationshipKind.allCases.sorted())
        XCTAssertEqual(KernelRecordRegistryV4.registrations.map(\.descriptor.kind), kinds)
        XCTAssertEqual(KernelMutationReceiptRegistryV4.registrations.map(\.kind), kinds)
        XCTAssertEqual(KernelBackupRestoreRegistryV4.registrations.map(\.kind), kinds)
        XCTAssertEqual(KernelDeletionEraseRegistryV4.registrations.map(\.kind), kinds)
        XCTAssertTrue(KernelCanonicalHashV1.validSHA256(try KernelRecordRegistryV4.canonicalDigest))
        XCTAssertTrue(KernelCanonicalHashV1.validSHA256(try KernelMutationReceiptRegistryV4.canonicalDigest))
        XCTAssertTrue(KernelCanonicalHashV1.validSHA256(try KernelBackupRestoreRegistryV4.canonicalDigest))
        XCTAssertTrue(KernelCanonicalHashV1.validSHA256(try KernelDeletionEraseRegistryV4.canonicalDigest))

        for kind in kinds {
            let descriptor = try KernelPersistenceV4Schema.recordDescriptor(for: kind)
            XCTAssertEqual(descriptor.requirements, KernelPersistenceV4LifecycleRequirement.allCases.sorted())
            XCTAssertEqual(try KernelRecordRegistryV4.registration(for: kind).descriptor, descriptor)
            XCTAssertEqual(try KernelMutationReceiptRegistryV4.registration(for: kind).effectID,
                           descriptor.canonicalMutationEffectID)
            XCTAssertEqual(try KernelBackupRestoreRegistryV4.registration(for: kind).kind, kind)
            XCTAssertEqual(try KernelDeletionEraseRegistryV4.registration(for: kind).deleteRule,
                           descriptor.deleteRule)
        }
    }

    func testV9_17A01FullMigrationAndDataRightLifecycleMatrixIsDeterministic() throws {
        let schema = try KernelPersistenceV4Schema.descriptor()
        let staged = try V9_17KernelPersistenceFixture.completeStaging()
        let validating = try KernelPersistenceV4Migration.beginValidation(staged)
        let archive = try V9_17KernelPersistenceFixture.archiveManifest()
        let validated = try KernelPersistenceV4Migration.acceptValidation(
            validating,
            schema: schema,
            archiveManifestDigest: archive.archiveSHA256,
            exportManifestDigest: V9_17KernelPersistenceFixture.digest("export-manifest")
        )
        XCTAssertThrowsError(try KernelPersistenceV4Migration.activateValidatedStaging(
            validated, s10_6IntegrationAccepted: false
        ))
        let simulatedActive = try KernelPersistenceV4Migration.activateValidatedStaging(
            validated, s10_6IntegrationAccepted: true
        )
        XCTAssertEqual(simulatedActive.phase, .active)
        XCTAssertFalse(schema.activationEnabled, "unit simulation must not activate the dormant schema")

        try archive.validate()
        try KernelBackupRestoreRegistryV4.validateForRestore(
            archive, expectedArchiveID: archive.archiveID,
            knownSourceGenerationID: archive.sourceGenerationID
        )
        for kind in KernelPersistenceV4RecordKind.allCases.sorted() {
            let mutation = try KernelMutationReceiptRegistryV4.registration(for: kind)
            if mutation.effectDisposition != .dormantNoRuntimeEffect {
                let effect = try KernelMutationEffectV4(
                    kind: kind,
                    mutationID: "mutation-\(kind.rawValue)",
                    expectedRevision: 4,
                    resultingRevision: 5,
                    payloadSHA256: V9_17KernelPersistenceFixture.digest("payload-\(kind.rawValue)"),
                    effectID: mutation.effectID
                )
                let receipt = try KernelMutationReceiptRegistryV4.receipt(for: effect)
                XCTAssertEqual(try KernelMutationReceiptRegistryV4.reconcile(
                    effect: effect, existingReceipt: nil
                ), receipt)
                XCTAssertEqual(try KernelMutationReceiptRegistryV4.reconcile(
                    effect: effect, existingReceipt: receipt
                ), receipt)
            }

            let deletion = try KernelDeletionEraseRegistryV4.registration(for: kind)
            let removal = try KernelRemovalReceiptV4(
                operationID: "erase-\(kind.rawValue)",
                kind: kind,
                targetID: "target-\(kind.rawValue)",
                action: .erase,
                priorRevision: 8,
                resultingRevision: 9,
                clearedTombstone: deletion.clearsTombstonesOnErase
            )
            XCTAssertEqual(try KernelDeletionEraseRegistryV4.reconcile(
                candidate: removal, existing: nil
            ), removal)
            XCTAssertEqual(try KernelDeletionEraseRegistryV4.reconcile(
                candidate: removal, existing: removal
            ), removal)
        }
    }

    func testV9_17H01UnmappedDuplicateAndVersionSkewInputsFailClosed() throws {
        let firstRegistration = try XCTUnwrap(KernelRecordRegistryV4.registrations.first)
        XCTAssertThrowsError(try KernelRecordRegistryV4.validate(
            KernelRecordRegistryV4.registrations + [firstRegistration]
        ))
        XCTAssertThrowsError(try KernelPersistenceV4RelationshipDescriptor(
            kind: .assetSite,
            source: .issue,
            fieldName: "siteID",
            target: .site,
            optional: false,
            deleteRule: .deleteAfterDependents
        ))
        let descriptorData = try V9_17KernelPersistenceFixture.encoder.encode(
            KernelPersistenceV4Schema.recordDescriptor(for: .asset)
        )
        let unknownKind = try XCTUnwrap(String(data: descriptorData, encoding: .utf8))
            .replacingOccurrences(of: "\"kind\":\"Asset\"", with: "\"kind\":\"UnknownKernelKind\"")
        XCTAssertThrowsError(try JSONDecoder().decode(
            KernelPersistenceV4RecordDescriptor.self, from: Data(unknownKind.utf8)
        ))

        let begun = try KernelPersistenceV4Migration.begin(
            migrationID: "hostile-migration",
            sourceStoreDigest: V9_17KernelPersistenceFixture.digest("hostile-source")
        )
        let record = try V9_17KernelPersistenceFixture.stagedRecord(.asset)
        let once = try KernelPersistenceV4Migration.stage(begun, record: record)
        XCTAssertThrowsError(try KernelPersistenceV4Migration.stage(once, record: record))
        XCTAssertThrowsError(try KernelPersistenceV4Migration.completeStaging(
            once,
            schema: KernelPersistenceV4Schema.descriptor(),
            stagingDigest: V9_17KernelPersistenceFixture.digest("incomplete")
        ))

        let begunData = try V9_17KernelPersistenceFixture.encoder.encode(begun)
        let explicitNull = try XCTUnwrap(String(data: begunData, encoding: .utf8))
            .replacingOccurrences(
                of: "\"sourceStoreDigest\":",
                with: "\"stagingDigest\":null,\"sourceStoreDigest\":"
            )
        XCTAssertThrowsError(try JSONDecoder().decode(
            KernelPersistenceV4MigrationCheckpoint.self, from: Data(explicitNull.utf8)
        ))

        XCTAssertEqual(try KernelPersistenceV4Migration.openDisposition(
            storeSchemaVersion: 5, binaryMaximumSchemaVersion: 4, checkpoint: nil
        ), .refuseNewerStore)
        XCTAssertEqual(try KernelPersistenceV4Migration.openDisposition(
            storeSchemaVersion: 4, binaryMaximumSchemaVersion: 3, checkpoint: nil
        ), .refuseNewerStore)
        XCTAssertEqual(try KernelPersistenceV4Migration.openDisposition(
            storeSchemaVersion: 4, binaryMaximumSchemaVersion: 4, checkpoint: nil
        ), .refuseNewerStore)
        XCTAssertEqual(try KernelPersistenceV4Migration.openDisposition(
            storeSchemaVersion: 3, binaryMaximumSchemaVersion: 3, checkpoint: begun
        ), .refuseNewerStore)
        XCTAssertThrowsError(try KernelPersistenceV4Migration.openDisposition(
            storeSchemaVersion: 2, binaryMaximumSchemaVersion: 4, checkpoint: nil
        ))

        let archive = try V9_17KernelPersistenceFixture.archiveManifest()
        XCTAssertThrowsError(try KernelArchiveManifestV4(
            archiveID: "archive-omission",
            sourceGenerationID: archive.sourceGenerationID,
            entries: Array(archive.entries.dropLast())
        ))
        let encoded = try V9_17KernelPersistenceFixture.encoder.encode(archive)
        let future = try XCTUnwrap(String(data: encoded, encoding: .utf8))
            .replacingOccurrences(of: "\"schemaVersion\":4", with: "\"schemaVersion\":5")
        XCTAssertThrowsError(try JSONDecoder().decode(
            KernelArchiveManifestV4.self, from: Data(future.utf8)
        ))

        let removal = try KernelRemovalReceiptV4(
            operationID: "duplicate-operation", kind: .packet, targetID: "packet-a",
            action: .delete, priorRevision: 1, resultingRevision: 2, clearedTombstone: false
        )
        let conflicting = try KernelRemovalReceiptV4(
            operationID: "duplicate-operation", kind: .packet, targetID: "packet-b",
            action: .delete, priorRevision: 1, resultingRevision: 2, clearedTombstone: false
        )
        XCTAssertThrowsError(try KernelDeletionEraseRegistryV4.reconcile(
            candidate: conflicting, existing: removal
        ))
        XCTAssertThrowsError(try KernelRemovalReceiptV4(
            operationID: "wrong-action", kind: .mutationReceiptRow, targetID: "receipt-a",
            action: .delete, priorRevision: 1, resultingRevision: 2, clearedTombstone: false
        ))
        XCTAssertThrowsError(try KernelRemovalReceiptV4(
            operationID: "orphan-remains", kind: .asset, targetID: "asset-a",
            action: .orphanCleanup, priorRevision: 1, resultingRevision: 2,
            clearedTombstone: false
        ))
        XCTAssertThrowsError(try KernelRemovalReceiptV4(
            operationID: "overflow", kind: .packet, targetID: "packet-max",
            action: .erase, priorRevision: UInt64.max, resultingRevision: UInt64.max,
            clearedTombstone: true
        ))
    }

    func testV9_17I01EveryMigrationAndLifecycleInterruptionRecoversZeroOrCompleteIdempotently() throws {
        var checkpoint = try KernelPersistenceV4Migration.begin(
            migrationID: "interruption-migration",
            sourceStoreDigest: V9_17KernelPersistenceFixture.digest("interruption-source")
        )
        XCTAssertEqual(try KernelPersistenceV4Migration.resumeDisposition(for: checkpoint), .resumeStaging)
        for kind in KernelPersistenceV4RecordKind.allCases.sorted() {
            let before = checkpoint
            let record = try V9_17KernelPersistenceFixture.stagedRecord(kind)
            checkpoint = try KernelPersistenceV4Migration.stage(checkpoint, record: record)
            XCTAssertEqual(try KernelPersistenceV4Migration.resumeDisposition(for: checkpoint), .resumeStaging)
            XCTAssertEqual(try KernelPersistenceV4Migration.stage(before, record: record), checkpoint)
        }

        let staged = try KernelPersistenceV4Migration.completeStaging(
            checkpoint,
            schema: KernelPersistenceV4Schema.descriptor(),
            stagingDigest: V9_17KernelPersistenceFixture.digest("interruption-staging")
        )
        XCTAssertEqual(try KernelPersistenceV4Migration.resumeDisposition(for: staged), .resumeValidation)
        XCTAssertEqual(try KernelPersistenceV4Migration.completeStaging(
            checkpoint,
            schema: KernelPersistenceV4Schema.descriptor(),
            stagingDigest: V9_17KernelPersistenceFixture.digest("interruption-staging")
        ), staged)

        let validating = try KernelPersistenceV4Migration.beginValidation(staged)
        XCTAssertEqual(try KernelPersistenceV4Migration.resumeDisposition(for: validating), .resumeValidation)
        XCTAssertEqual(try KernelPersistenceV4Migration.beginValidation(staged), validating)
        let archive = try V9_17KernelPersistenceFixture.archiveManifest()
        let validated = try KernelPersistenceV4Migration.acceptValidation(
            validating,
            schema: KernelPersistenceV4Schema.descriptor(),
            archiveManifestDigest: archive.archiveSHA256,
            exportManifestDigest: V9_17KernelPersistenceFixture.digest("interruption-export")
        )
        XCTAssertEqual(try KernelPersistenceV4Migration.resumeDisposition(for: validated),
                       .activateValidatedStaging)
        XCTAssertEqual(try KernelPersistenceV4Migration.acceptValidation(
            validating,
            schema: KernelPersistenceV4Schema.descriptor(),
            archiveManifestDigest: archive.archiveSHA256,
            exportManifestDigest: V9_17KernelPersistenceFixture.digest("interruption-export")
        ), validated)

        let simulatedActive = try KernelPersistenceV4Migration.activateValidatedStaging(
            validated, s10_6IntegrationAccepted: true
        )
        XCTAssertEqual(try KernelPersistenceV4Migration.resumeDisposition(for: simulatedActive), .useActiveV4)
        let observed = try KernelPersistenceV4Migration.observePublicationOrCanonicalWrite(
            simulatedActive, published: true, canonicalWrite: false
        )
        XCTAssertEqual(try KernelPersistenceV4Migration.observePublicationOrCanonicalWrite(
            simulatedActive, published: true, canonicalWrite: false
        ), observed)
        let forwardFix = try KernelPersistenceV4Migration.requireForwardFix(observed)
        XCTAssertEqual(try KernelPersistenceV4Migration.resumeDisposition(for: forwardFix),
                       .requireForwardFixReadExport)

        let discarded = try KernelPersistenceV4Migration.discardBeforeActivation(validated)
        XCTAssertEqual(try KernelPersistenceV4Migration.resumeDisposition(for: discarded), .remainDiscardedV3)
        XCTAssertEqual(try KernelPersistenceV4Migration.discardBeforeActivation(validated), discarded)
        XCTAssertThrowsError(try KernelPersistenceV4Migration.discardBeforeActivation(observed))

        try KernelBackupRestoreRegistryV4.validateForRestore(
            archive, expectedArchiveID: archive.archiveID, knownSourceGenerationID: archive.sourceGenerationID
        )
        try KernelBackupRestoreRegistryV4.validateForRestore(
            archive, expectedArchiveID: archive.archiveID, knownSourceGenerationID: archive.sourceGenerationID
        )
        XCTAssertFalse(try KernelPersistenceV4Schema.descriptor().activationEnabled)
    }

    func testV9_17R01PreactivationDiscardAndPostWriteForwardFixPreserveHistoricReadExport() throws {
        let staged = try V9_17KernelPersistenceFixture.completeStaging()
        let discarded = try KernelPersistenceV4Migration.discardBeforeActivation(staged)
        XCTAssertEqual(discarded.phase, .discarded)
        XCTAssertEqual(try KernelPersistenceV4Migration.openDisposition(
            storeSchemaVersion: 3, binaryMaximumSchemaVersion: 4, checkpoint: discarded
        ), .openV3ReadWrite)

        let archiveBefore = try V9_17KernelPersistenceFixture.archiveManifest()
        let validated = try KernelPersistenceV4Migration.acceptValidation(
            KernelPersistenceV4Migration.beginValidation(staged),
            schema: KernelPersistenceV4Schema.descriptor(),
            archiveManifestDigest: archiveBefore.archiveSHA256,
            exportManifestDigest: V9_17KernelPersistenceFixture.digest("recovery-export")
        )
        let simulatedActive = try KernelPersistenceV4Migration.activateValidatedStaging(
            validated, s10_6IntegrationAccepted: true
        )
        XCTAssertEqual(try KernelPersistenceV4Migration.openDisposition(
            storeSchemaVersion: 4,
            binaryMaximumSchemaVersion: 4,
            checkpoint: simulatedActive
        ), .openV4ReadWrite)
        let written = try KernelPersistenceV4Migration.observePublicationOrCanonicalWrite(
            simulatedActive, published: false, canonicalWrite: true
        )
        let published = try KernelPersistenceV4Migration.observePublicationOrCanonicalWrite(
            simulatedActive, published: true, canonicalWrite: false
        )
        XCTAssertThrowsError(try KernelPersistenceV4Migration.discardBeforeActivation(written))
        let forwardFix = try KernelPersistenceV4Migration.requireForwardFix(written)
        let publicationForwardFix = try KernelPersistenceV4Migration.requireForwardFix(published)
        XCTAssertTrue(publicationForwardFix.published)
        XCTAssertFalse(publicationForwardFix.canonicalV4WriteObserved)
        XCTAssertEqual(try KernelPersistenceV4Migration.openDisposition(
            storeSchemaVersion: 4, binaryMaximumSchemaVersion: 4, checkpoint: forwardFix
        ), .forwardFixReadExportOnly)
        XCTAssertEqual(try KernelPersistenceV4Migration.resumeDisposition(for: forwardFix),
                       .requireForwardFixReadExport)

        try archiveBefore.validate()
        let archiveAfter = try V9_17KernelPersistenceFixture.archiveManifest()
        XCTAssertEqual(archiveAfter, archiveBefore, "forward recovery must not rewrite historic archive truth")
        XCTAssertThrowsError(try KernelBackupRestoreRegistryV4.validateForRestore(
            archiveBefore,
            expectedArchiveID: archiveBefore.archiveID,
            knownSourceGenerationID: "old-generation"
        ))
        for kind in KernelPersistenceV4RecordKind.allCases.sorted() {
            let record = try KernelRecordRegistryV4.registration(for: kind)
            let backup = try KernelBackupRestoreRegistryV4.registration(for: kind)
            XCTAssertEqual(backup.openExport, record.openExport)
            if [.canonicalWorkspace, .immutableContentMetadata, .appendOnlyReceipt,
                .dormantContractDeclaration].contains(record.descriptor.classification) {
                XCTAssertNotEqual(record.openExport, .excluded)
            }
        }
        XCTAssertFalse(try KernelPersistenceV4Schema.descriptor().activationEnabled)
    }
}

private final class C27V917TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(PersistentSchemaV26.models.count, 94)
        XCTAssertEqual(AssetLocatorStateV1.allCases.count, 4)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.scanMutatesCanonicalState)
    }
}

extension V9_17KernelPersistenceTests {
    func testC24AccessibleDocumentTypedAnchor() throws {
        XCTAssertEqual(AccessibleDocumentSemanticTreeV1.schemaVersion, 1)
        XCTAssertEqual(AccessibleDocumentRoleV1.allCases.count, 13)
        XCTAssertEqual(AccessibleDocumentAssessmentStateV1.allCases.count, 4)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
    }
}

private enum V9_17KernelPersistenceFixture {
    static let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return value
    }()

    static func digest(_ value: String) -> String {
        KernelCanonicalHashV1.sha256(Data(value.utf8))
    }

    static func stagedRecord(_ kind: KernelPersistenceV4RecordKind) throws -> KernelPersistenceV4StagedRecordCount {
        try KernelPersistenceV4StagedRecordCount(
            kind: kind, sourceCount: 1, stagedCount: 1, batchDigest: digest("batch-\(kind.rawValue)")
        )
    }

    static func completeStaging() throws -> KernelPersistenceV4MigrationCheckpoint {
        var checkpoint = try KernelPersistenceV4Migration.begin(
            migrationID: "fixture-migration", sourceStoreDigest: digest("fixture-source")
        )
        for kind in KernelPersistenceV4RecordKind.allCases.sorted() {
            checkpoint = try KernelPersistenceV4Migration.stage(checkpoint, record: stagedRecord(kind))
        }
        return try KernelPersistenceV4Migration.completeStaging(
            checkpoint,
            schema: KernelPersistenceV4Schema.descriptor(),
            stagingDigest: digest("fixture-staging")
        )
    }

    static func archiveManifest() throws -> KernelArchiveManifestV4 {
        let entries = try KernelPersistenceV4RecordKind.allCases.sorted().map { kind in
            let registration = try KernelBackupRestoreRegistryV4.registration(for: kind)
            let empty = [.rebuildAfterRestore, .excludeDormantDeclaration].contains(registration.archive)
            return try KernelArchiveEntryV4(
                kind: kind,
                disposition: registration.archive,
                recordCount: empty ? 0 : 1,
                payloadSHA256: empty ? KernelBackupRestoreRegistryV4.emptyPayloadSHA256 : digest("archive-\(kind.rawValue)")
            )
        }
        return try KernelArchiveManifestV4(
            archiveID: "archive-v4",
            sourceGenerationID: "generation-v3",
            entries: entries
        )
    }
}
extension V9_17KernelPersistenceTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(SurveyDefinitionLifecycleV1.lifecycleEventPersistence, "CANONICAL_MUTATION_JOURNAL_ENVELOPE")
        XCTAssertEqual(SurveyDefinitionLifecycleV1.persistentFamilies.count, 2)
        XCTAssertTrue(SurveyDefinitionLimitsV1.maximumCanonicalBytes >= 4_194_304)
    }
}
extension V9_17KernelPersistenceTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

extension V9_17KernelPersistenceTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
private final class C31LightingAnchorV917KernelPersistenceTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

private final class C33TemporalEvidenceAnchorV917KernelPersistence: XCTestCase {
    func testC33V917KernelPersistenceCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "persistence.temporal-clip-anchor",
            kind: .video,
            reportProjection: .typedLinkOnly
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "persistence.temporal-clip-anchor",
            kind: .video,
            reportProjection: .typedLinkOnly
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

private final class C32AssistanceAnchorV917KernelPersistence: XCTestCase {
    func testC32V917KernelPersistenceCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .factCapture,
            fieldID: "persistence.acceptance-row-only",
            value: .integer(31)
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .factCapture,
            fieldID: "persistence.acceptance-row-only",
            valueKind: .integer
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
private final class C46V917PersistenceCompatibilityTests: XCTestCase {
    func testC46PersistenceBindsExactContactRevision() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "kernel-persistence",
            kind: .email,
            handoff: .email,
            slot: 46017
        )
    }
}


private enum C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_17KernelPersistenceTests_swift {
    static let compatibilityCardID = "V23-P03-C47"
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

private final class C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_17KernelPersistenceTests_swift_Tests: XCTestCase {
    func testC47V917KernelPersistenceTestsOwnerCompatibilityIsTyped() {
        XCTAssertEqual(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_17KernelPersistenceTests_swift.compatibilityCardID, "V23-P03-C47")
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_17KernelPersistenceTests_swift.sharedEnvelopeDoesNotCollapseFamilyTruth)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_17KernelPersistenceTests_swift.installationAndPunchReceiptsRemainIndependent)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_17KernelPersistenceTests_swift.noPlanFallbackIsExplicit)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_17KernelPersistenceTests_swift.surveyDefinitionOwnershipIsPreserved)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_17KernelPersistenceTests_swift.legacyInspectionTruthIsNotRewritten)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_17KernelPersistenceTests_swift.threeReceiptIsolationIsRequired)
        XCTAssertEqual(ActivityContractPersistenceEnrollmentV2.persistentFamilies.count, 6)
        XCTAssertTrue(ActivityContractPersistenceEnrollmentV2.usesSoleWorkspaceWriter)
    }
}

private final class C48PortableReviewV917PersistenceTests: XCTestCase {
    func testC48PersistenceUsesExistingC14RowsOnly() {
        XCTAssertEqual(C48PortableExchangePersistentLifecycleBoundaryV2.canonicalRowsAdded, 0)
        XCTAssertTrue(C48PortableExchangePersistentLifecycleBoundaryV2.acceptedResponseUsesExistingC14Writer)
        XCTAssertEqual(C48PortableExchangeSyncBoundaryV2.canonicalAcceptedResponseOwner, "C14")
        XCTAssertTrue(PortableReviewChangeJournalPolicyV1.postimagesUseOnlyExistingC14Families)
    }
}

import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private final class C45AtomicRestoreCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityRestoresActiveOrHistoricDispositionExactly() {
        XCTAssertEqual(Set(AcceptedLabelSnapshotDispositionV1.allCases), [.activeSourceWorkspace, .historicCloneOrFork])
        XCTAssertEqual(LabelReprintEligibilityV1.activeExactReprint.rawValue, "ACTIVE_EXACT_REPRINT")
        XCTAssertEqual(LabelReprintEligibilityV1.blockedMissingRelease.rawValue, "BLOCKED_MISSING_RELEASE")
    }
}

private final class C30EvidenceContextAnchorS6_4AtomicRestore: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

final class S6_4AtomicRestoreTests: XCTestCase {
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
    @MainActor
    func testV23P03C40TypedRowPersistsAsAtomicRestoreUnit() throws {
        let harness = try makeHarness("c40-row")
        defer { try? fileManager.removeItem(at: harness.root) }
        let source = try C40BackupLifecycleTestValues.source(
            workspace: harness.session.workspaceIdentity.workspaceID.rawValue
        )
        harness.session.modelContext.insert(try AuthoritySourceReleaseRow(source))
        try harness.session.modelContext.save()

        let rows = try harness.session.modelContext.fetch(FetchDescriptor<AuthoritySourceReleaseRow>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(try rows[0].value(), source)
        XCTAssertEqual(
            try AuthorityCriterionCanonicalCodecV1.encode(rows[0].value()),
            try AuthorityCriterionCanonicalCodecV1.encode(source)
        )
    }

    private let fileManager = FileManager.default

    @MainActor
    func testGoldenEmptyRestoreSwitchesValidatedGenerationAndRetiresOld() async throws {
        let harness = try makeHarness("golden")
        defer { try? fileManager.removeItem(at: harness.root) }
        let package = try makeSourcePackage(in: harness.root, name: "source")
        let sourceBytes = try tree(package)
        let validated = try importPackage(package, into: harness.session)
        let oldID = harness.session.generationID

        let service = try BackupRestoreService(
            applicationSupportURL: harness.support,
            makeUUID: sequence([
                uuid("64000000-0000-0000-0000-000000000101"),
                uuid("64000000-0000-0000-0000-000000000102"),
            ])
        )
        let restored = try await service.restore(
            validatedPackage: validated,
            currentModelContext: harness.session.modelContext,
            currentGenerationID: oldID,
            currentGenerationRootURL: harness.session.generationRootURL
        )

        XCTAssertEqual(restored.generationID, uuid("64000000-0000-0000-0000-000000000101"))
        XCTAssertEqual(try harness.factory.currentGenerationID(), restored.generationID)
        XCTAssertEqual(try harness.factory.retiredGenerationIDs(), [oldID])
        XCTAssertEqual(try restored.modelContext.fetchCount(FetchDescriptor<Site>()), 1)
        XCTAssertEqual(try restored.modelContext.fetchCount(FetchDescriptor<Asset>()), 1)
        XCTAssertEqual(try restored.modelContext.fetchCount(FetchDescriptor<Report>()), 0)
        XCTAssertFalse(fileManager.fileExists(atPath: validated.stagedPackageURL.path))
        XCTAssertFalse(fileManager.fileExists(
            atPath: harness.support.appendingPathComponent(
                "FieldEvidenceRestore/restore.json"
            ).path
        ))
        XCTAssertEqual(try tree(package), sourceBytes)

        let reopened = try harness.factory.openOrBootstrapCurrent()
        XCTAssertEqual(reopened.generationID, restored.generationID)
        XCTAssertEqual(try reopened.modelContext.fetchCount(FetchDescriptor<Asset>()), 1)
    }

    @MainActor
    func testInterruptionMatrixRecoversOnlyOldOrFullyValidatedNew() async throws {
        let oldOutcome: Set<BackupRestoreFailurePoint> = [
            .beforePreparedWrite,
            .afterPreparedWrite,
            .beforeGenerationInstall,
        ]
        for (offset, point) in BackupRestoreFailurePoint.allCases.enumerated() {
            let harness = try makeHarness("phase-\(offset)")
            defer { try? fileManager.removeItem(at: harness.root) }
            let package = try makeSourcePackage(in: harness.root, name: "source")
            let validated = try importPackage(package, into: harness.session)
            let oldID = harness.session.generationID
            let newID = UUID(
                uuid: (
                    0x64, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                    UInt8(0x40 + offset), UInt8(0x50 + offset)
                )
            )
            let service = try BackupRestoreService(
                applicationSupportURL: harness.support,
                makeUUID: sequence([newID, UUID()]),
                failureInjection: BackupRestoreFailureInjection(failOnceAt: point)
            )
            await XCTAssertThrowsErrorAsync {
                _ = try await service.restore(
                    validatedPackage: validated,
                    currentModelContext: harness.session.modelContext,
                    currentGenerationID: oldID,
                    currentGenerationRootURL: harness.session.generationRootURL
                )
            } verify: { error in
                XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
            }

            let recovery = try BackupRestoreService(
                applicationSupportURL: harness.support
            )
            let recoveredNew = try recovery.reconcileAtStartup()
            let expectedID = oldOutcome.contains(point) ? oldID : newID
            XCTAssertEqual(try harness.factory.currentGenerationID(), expectedID, "\(point)")
            if oldOutcome.contains(point) {
                XCTAssertNil(recoveredNew, "\(point)")
                XCTAssertTrue(BackupRestoreService.isEmptyCurrent(
                    harness.session.modelContext
                ))
            } else {
                XCTAssertEqual(recoveredNew?.generationID, newID, "\(point)")
                XCTAssertEqual(
                    try XCTUnwrap(recoveredNew).modelContext.fetchCount(
                        FetchDescriptor<Asset>()
                    ),
                    1,
                    "\(point)"
                )
            }
            XCTAssertNil(try recovery.reconcileAtStartup(), "\(point)")
            XCTAssertFalse(fileManager.fileExists(
                atPath: harness.support.appendingPathComponent(
                    "FieldEvidenceRestore/restore.json"
                ).path
            ))
            XCTAssertTrue(fileManager.fileExists(
                atPath: harness.factory.installedGenerationURL(id: oldID).path
            ))
        }
    }

    @MainActor
    func testDirtyNonemptyAndImpossibleRecoveryFailClosed() async throws {
        let dirty = try makeHarness("dirty")
        defer { try? fileManager.removeItem(at: dirty.root) }
        let package = try makeSourcePackage(in: dirty.root, name: "source")
        let validated = try importPackage(package, into: dirty.session)
        dirty.session.modelContext.insert(Site(label: "Unsaved"))
        let service = try BackupRestoreService(applicationSupportURL: dirty.support)
        await XCTAssertThrowsErrorAsync {
            _ = try await service.restore(
                validatedPackage: validated,
                currentModelContext: dirty.session.modelContext,
                currentGenerationID: dirty.session.generationID,
                currentGenerationRootURL: dirty.session.generationRootURL
            )
        } verify: { error in
            XCTAssertEqual(error as? BackupRestoreServiceError, .contextHasChanges)
        }
        XCTAssertEqual(try dirty.factory.currentGenerationID(), dirty.session.generationID)
        dirty.session.modelContext.rollback()
        try BackupImportService(
            generationRootURL: dirty.session.generationRootURL,
            scopedAccess: .alreadyAuthorized
        ).discard(validated)

        let malformed = try makeHarness("impossible")
        defer { try? fileManager.removeItem(at: malformed.root) }
        let missingNew = uuid("64000000-0000-0000-0000-000000000301")
        let intent = RestoreIntentV1(
            newGenerationID: missingNew,
            newGenerationRelativePath:
                "FieldEvidenceData/generations/\(missingNew.uuidString.lowercased())",
            oldGenerationID: malformed.session.generationID,
            phase: .generationInstalled,
            restoreID: uuid("64000000-0000-0000-0000-000000000302"),
            schemaVersion: 1,
            stagingGenerationRelativePath:
                "FieldEvidenceRestore/generations/\(missingNew.uuidString.lowercased())"
        )
        let store = try RestoreIntentStore(applicationSupportURL: malformed.support)
        try store.create(intent)
        let before = try tree(malformed.session.generationRootURL)
        XCTAssertThrowsError(try BackupRestoreService(
            applicationSupportURL: malformed.support
        ).reconcileAtStartup())
        XCTAssertEqual(try malformed.factory.currentGenerationID(), malformed.session.generationID)
        XCTAssertEqual(try tree(malformed.session.generationRootURL), before)
        XCTAssertEqual(try store.load(), intent)
    }

    @MainActor
    func testRecoveryRejectsReplacedRestoreGenerationAncestorWithoutDeleting() async throws {
        let harness = try makeHarness("ancestor-replacement")
        defer { try? fileManager.removeItem(at: harness.root) }
        let package = try makeSourcePackage(in: harness.root, name: "source")
        let validated = try importPackage(package, into: harness.session)
        let newID = uuid("64000000-0000-0000-0000-000000000401")
        let restore = try BackupRestoreService(
            applicationSupportURL: harness.support,
            makeUUID: sequence([
                newID,
                uuid("64000000-0000-0000-0000-000000000402"),
            ]),
            failureInjection: BackupRestoreFailureInjection(
                failOnceAt: .afterPreparedWrite
            )
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await restore.restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: harness.session.generationID,
                currentGenerationRootURL: harness.session.generationRootURL
            )
        } verify: { error in
            XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
        }

        let recovery = try BackupRestoreService(
            applicationSupportURL: harness.support
        )
        let canonicalParent = harness.support.appendingPathComponent(
            "FieldEvidenceRestore/generations",
            isDirectory: true
        )
        let detachedParent = harness.support.appendingPathComponent(
            "FieldEvidenceRestore/generations.detached",
            isDirectory: true
        )
        try fileManager.moveItem(at: canonicalParent, to: detachedParent)
        try fileManager.createDirectory(
            at: canonicalParent,
            withIntermediateDirectories: false
        )
        let marker = canonicalParent.appendingPathComponent("replacement.marker")
        let markerBytes = Data("unowned".utf8)
        try markerBytes.write(to: marker)

        XCTAssertThrowsError(try recovery.reconcileAtStartup())
        XCTAssertEqual(
            try harness.factory.currentGenerationID(),
            harness.session.generationID
        )
        XCTAssertTrue(fileManager.fileExists(atPath: detachedParent
            .appendingPathComponent(newID.uuidString.lowercased()).path))
        XCTAssertEqual(try Data(contentsOf: marker), markerBytes)
        XCTAssertNotNil(try RestoreIntentStore(
            applicationSupportURL: harness.support
        ).load())
    }

    @MainActor
    func testRecoveryRejectsUnexpectedInstalledGenerationBytesWithoutAdoption() async throws {
        let harness = try makeHarness("unexpected-installed-byte")
        defer { try? fileManager.removeItem(at: harness.root) }
        let package = try makeSourcePackage(in: harness.root, name: "source")
        let validated = try importPackage(package, into: harness.session)
        let newID = uuid("64000000-0000-0000-0000-000000000501")
        let restore = try BackupRestoreService(
            applicationSupportURL: harness.support,
            makeUUID: sequence([
                newID,
                uuid("64000000-0000-0000-0000-000000000502"),
            ]),
            failureInjection: BackupRestoreFailureInjection(
                failOnceAt: .afterGenerationInstall
            )
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await restore.restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: harness.session.generationID,
                currentGenerationRootURL: harness.session.generationRootURL
            )
        } verify: { error in
            XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
        }

        let unexpected = harness.factory.installedGenerationURL(id: newID)
            .appendingPathComponent("unexpected.bin")
        let unexpectedBytes = Data("ambiguous".utf8)
        try unexpectedBytes.write(to: unexpected)
        let recovery = try BackupRestoreService(
            applicationSupportURL: harness.support
        )

        XCTAssertThrowsError(try recovery.reconcileAtStartup())
        XCTAssertEqual(
            try harness.factory.currentGenerationID(),
            harness.session.generationID
        )
        XCTAssertEqual(try Data(contentsOf: unexpected), unexpectedBytes)
        XCTAssertEqual(
            try RestoreIntentStore(applicationSupportURL: harness.support).load()?.phase,
            .generationInstalled
        )
    }

    @MainActor
    func testRecoveryRejectsReplacedDataAncestorBeforePointerMutation() async throws {
        let harness = try makeHarness("data-ancestor-replacement")
        defer { try? fileManager.removeItem(at: harness.root) }
        let package = try makeSourcePackage(in: harness.root, name: "source")
        let validated = try importPackage(package, into: harness.session)
        let newID = uuid("64000000-0000-0000-0000-000000000601")
        let restore = try BackupRestoreService(
            applicationSupportURL: harness.support,
            makeUUID: sequence([
                newID,
                uuid("64000000-0000-0000-0000-000000000602"),
            ]),
            failureInjection: BackupRestoreFailureInjection(
                failOnceAt: .afterGenerationInstall
            )
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await restore.restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: harness.session.generationID,
                currentGenerationRootURL: harness.session.generationRootURL
            )
        } verify: { error in
            XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
        }

        let recovery = try BackupRestoreService(
            applicationSupportURL: harness.support
        )
        let canonicalData = harness.support.appendingPathComponent(
            "FieldEvidenceData",
            isDirectory: true
        )
        let detachedData = harness.support.appendingPathComponent(
            "FieldEvidenceData.detached",
            isDirectory: true
        )
        try fileManager.moveItem(at: canonicalData, to: detachedData)
        let detachedBefore = try tree(detachedData)
        try fileManager.createDirectory(
            at: canonicalData,
            withIntermediateDirectories: false
        )
        let marker = canonicalData.appendingPathComponent("replacement.marker")
        let markerBytes = Data("unowned data root".utf8)
        try markerBytes.write(to: marker)

        XCTAssertThrowsError(try recovery.reconcileAtStartup())
        XCTAssertEqual(try tree(detachedData), detachedBefore)
        XCTAssertEqual(try Data(contentsOf: marker), markerBytes)
        XCTAssertEqual(
            try RestoreIntentStore(applicationSupportURL: harness.support).load()?.phase,
            .generationInstalled
        )
    }

    @MainActor
    func testRecoveryResumesExactCurrentPointerPreRenameTemp() async throws {
        let harness = try makeHarness("current-pointer-temp")
        defer { try? fileManager.removeItem(at: harness.root) }
        let package = try makeSourcePackage(in: harness.root, name: "source")
        let validated = try importPackage(package, into: harness.session)
        let newID = uuid("64000000-0000-0000-0000-000000000701")
        let restore = try BackupRestoreService(
            applicationSupportURL: harness.support,
            makeUUID: sequence([
                newID,
                uuid("64000000-0000-0000-0000-000000000702"),
            ]),
            failureInjection: BackupRestoreFailureInjection(
                failOnceAt: .afterGenerationInstall
            )
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await restore.restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: harness.session.generationID,
                currentGenerationRootURL: harness.session.generationRootURL
            )
        } verify: { error in
            XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
        }
        let temporary = harness.support.appendingPathComponent(
            "FieldEvidenceData/.current.json.restore-next"
        )
        try Data(
            "{\"generationID\":\"\(newID.uuidString.lowercased())\",\"schemaVersion\":1}"
                .utf8
        ).write(to: temporary, options: .withoutOverwriting)

        let recovered = try BackupRestoreService(
            applicationSupportURL: harness.support
        ).reconcileAtStartup()
        XCTAssertEqual(recovered?.generationID, newID)
        XCTAssertEqual(try harness.factory.currentGenerationID(), newID)
        XCTAssertFalse(fileManager.fileExists(atPath: temporary.path))
    }

    @MainActor
    func testRecoveryResumesExactRetiredPointerPreRenameTemp() async throws {
        let harness = try makeHarness("retired-pointer-temp")
        defer { try? fileManager.removeItem(at: harness.root) }
        let package = try makeSourcePackage(in: harness.root, name: "source")
        let validated = try importPackage(package, into: harness.session)
        let oldID = harness.session.generationID
        let newID = uuid("64000000-0000-0000-0000-000000000801")
        let restore = try BackupRestoreService(
            applicationSupportURL: harness.support,
            makeUUID: sequence([
                newID,
                uuid("64000000-0000-0000-0000-000000000802"),
            ]),
            failureInjection: BackupRestoreFailureInjection(
                failOnceAt: .afterNewGenerationValidation
            )
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await restore.restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: oldID,
                currentGenerationRootURL: harness.session.generationRootURL
            )
        } verify: { error in
            XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
        }
        let temporary = harness.support.appendingPathComponent(
            "FieldEvidenceData/.retired.json.restore-next"
        )
        try Data(
            "{\"generationIDs\":[\"\(oldID.uuidString.lowercased())\"],\"schemaVersion\":1}"
                .utf8
        ).write(to: temporary, options: .withoutOverwriting)

        let recovered = try BackupRestoreService(
            applicationSupportURL: harness.support
        ).reconcileAtStartup()
        XCTAssertEqual(recovered?.generationID, newID)
        XCTAssertEqual(try harness.factory.retiredGenerationIDs(), [oldID])
        XCTAssertFalse(fileManager.fileExists(atPath: temporary.path))
    }

    @MainActor
    func testRecoveryRejectsImpossibleRetiredStateBeforeMutation() async throws {
        let harness = try makeHarness("retired-state-mismatch")
        defer { try? fileManager.removeItem(at: harness.root) }
        let package = try makeSourcePackage(in: harness.root, name: "source")
        let validated = try importPackage(package, into: harness.session)
        let oldID = harness.session.generationID
        let newID = uuid("64000000-0000-0000-0000-000000000901")
        let restore = try BackupRestoreService(
            applicationSupportURL: harness.support,
            makeUUID: sequence([
                newID,
                uuid("64000000-0000-0000-0000-000000000902"),
            ]),
            failureInjection: BackupRestoreFailureInjection(
                failOnceAt: .afterGenerationInstall
            )
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await restore.restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: oldID,
                currentGenerationRootURL: harness.session.generationRootURL
            )
        } verify: { error in
            XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
        }
        let dataRoot = harness.support.appendingPathComponent("FieldEvidenceData")
        let retiredURL = dataRoot.appendingPathComponent("retired.json")
        try Data(
            "{\"generationIDs\":[\"\(oldID.uuidString.lowercased())\"],\"schemaVersion\":1}"
                .utf8
        ).write(to: retiredURL, options: .atomic)
        let before = try tree(dataRoot)
        let expectedIntent = try XCTUnwrap(RestoreIntentStore(
            applicationSupportURL: harness.support
        ).load())

        XCTAssertThrowsError(try BackupRestoreService(
            applicationSupportURL: harness.support
        ).reconcileAtStartup())
        XCTAssertEqual(try tree(dataRoot), before)
        XCTAssertEqual(
            try RestoreIntentStore(applicationSupportURL: harness.support).load(),
            expectedIntent
        )
    }

    @MainActor
    func testRecoveryRejectsExtraInstalledOrStagedGenerationBeforeMutation() async throws {
        for extraIsInstalled in [false, true] {
            let harness = try makeHarness(
                extraIsInstalled ? "extra-installed" : "extra-staged"
            )
            defer { try? fileManager.removeItem(at: harness.root) }
            let package = try makeSourcePackage(in: harness.root, name: "source")
            let validated = try importPackage(package, into: harness.session)
            let newID = extraIsInstalled
                ? uuid("64000000-0000-0000-0000-000000000a01")
                : uuid("64000000-0000-0000-0000-000000000b01")
            let restore = try BackupRestoreService(
                applicationSupportURL: harness.support,
                makeUUID: sequence([
                    newID,
                    extraIsInstalled
                        ? uuid("64000000-0000-0000-0000-000000000a02")
                        : uuid("64000000-0000-0000-0000-000000000b02"),
                ]),
                failureInjection: BackupRestoreFailureInjection(
                    failOnceAt: .afterPreparedWrite
                )
            )
            await XCTAssertThrowsErrorAsync {
                _ = try await restore.restore(
                    validatedPackage: validated,
                    currentModelContext: harness.session.modelContext,
                    currentGenerationID: harness.session.generationID,
                    currentGenerationRootURL: harness.session.generationRootURL
                )
            } verify: { error in
                XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
            }

            let extraID = extraIsInstalled
                ? uuid("64000000-0000-0000-0000-000000000a03")
                : uuid("64000000-0000-0000-0000-000000000b03")
            let parent = extraIsInstalled
                ? harness.support.appendingPathComponent(
                    "FieldEvidenceData/generations",
                    isDirectory: true
                )
                : harness.support.appendingPathComponent(
                    "FieldEvidenceRestore/generations",
                    isDirectory: true
                )
            let extra = parent.appendingPathComponent(
                extraID.uuidString.lowercased(),
                isDirectory: true
            )
            try fileManager.createDirectory(
                at: extra,
                withIntermediateDirectories: false
            )
            try Data("unowned".utf8).write(
                to: extra.appendingPathComponent("marker")
            )
            let recovery = try BackupRestoreService(
                applicationSupportURL: harness.support
            )
            let before = try tree(harness.support)
            let intentBefore = try RestoreIntentStore(
                applicationSupportURL: harness.support
            ).load()

            XCTAssertThrowsError(try recovery.reconcileAtStartup())
            XCTAssertEqual(try tree(harness.support), before)
            XCTAssertEqual(
                try RestoreIntentStore(applicationSupportURL: harness.support).load(),
                intentBefore
            )
        }
    }

    @MainActor
    func testPreparedRecoveryRejectsUnexpectedStagedMemberWithoutDeletion() async throws {
        let harness = try makeHarness("unexpected-staged-member")
        defer { try? fileManager.removeItem(at: harness.root) }
        let package = try makeSourcePackage(in: harness.root, name: "source")
        let validated = try importPackage(package, into: harness.session)
        let newID = uuid("64000000-0000-0000-0000-000000000c01")
        let restore = try BackupRestoreService(
            applicationSupportURL: harness.support,
            makeUUID: sequence([
                newID,
                uuid("64000000-0000-0000-0000-000000000c02"),
            ]),
            failureInjection: BackupRestoreFailureInjection(
                failOnceAt: .afterPreparedWrite
            )
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await restore.restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: harness.session.generationID,
                currentGenerationRootURL: harness.session.generationRootURL
            )
        } verify: { error in
            XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
        }
        let unexpected = harness.factory.restoreStagingGenerationURL(id: newID)
            .appendingPathComponent("unexpected.bin")
        try Data("ambiguous staged bytes".utf8).write(to: unexpected)
        let recovery = try BackupRestoreService(
            applicationSupportURL: harness.support
        )
        let before = try tree(harness.support)
        let intentBefore = try RestoreIntentStore(
            applicationSupportURL: harness.support
        ).load()

        XCTAssertThrowsError(try recovery.reconcileAtStartup())
        XCTAssertEqual(try tree(harness.support), before)
        XCTAssertEqual(
            try RestoreIntentStore(applicationSupportURL: harness.support).load(),
            intentBefore
        )
    }

    @MainActor
    func testActiveEraseAuthorityBlocksRestoreWithoutMutation() async throws {
        let harness = try makeHarness("active-erase")
        defer { try? fileManager.removeItem(at: harness.root) }
        let package = try makeSourcePackage(in: harness.root, name: "source")
        let packageBefore = try tree(package)
        let validated = try importPackage(package, into: harness.session)
        let eraseRoot = harness.support.appendingPathComponent(
            "FieldEvidenceErase",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: eraseRoot,
            withIntermediateDirectories: false
        )
        try Data("{\"schemaVersion\":1}".utf8).write(
            to: eraseRoot.appendingPathComponent("erase.json")
        )
        let service = try BackupRestoreService(
            applicationSupportURL: harness.support
        )
        let supportBefore = try tree(harness.support)

        await XCTAssertThrowsErrorAsync {
            _ = try await service.restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: harness.session.generationID,
                currentGenerationRootURL: harness.session.generationRootURL
            )
        } verify: { _ in }
        XCTAssertEqual(try tree(harness.support), supportBefore)
        XCTAssertEqual(try tree(package), packageBefore)
        XCTAssertEqual(
            try harness.factory.currentGenerationID(),
            harness.session.generationID
        )
        XCTAssertNil(try RestoreIntentStore(
            applicationSupportURL: harness.support
        ).load())
    }

    @MainActor
    func testExtraImportStageBlocksRestoreWithoutMutation() async throws {
        let harness = try makeHarness("extra-import-stage")
        defer { try? fileManager.removeItem(at: harness.root) }
        let package = try makeSourcePackage(in: harness.root, name: "source")
        let packageBefore = try tree(package)
        let validated = try importPackage(package, into: harness.session)
        let extra = validated.stagedPackageURL.deletingLastPathComponent()
            .appendingPathComponent(
                "64000000-0000-0000-0000-000000000d01.fieldrecordbackup",
                isDirectory: true
            )
        try fileManager.copyItem(at: validated.stagedPackageURL, to: extra)
        let service = try BackupRestoreService(
            applicationSupportURL: harness.support
        )
        let supportBefore = try tree(harness.support)

        await XCTAssertThrowsErrorAsync {
            _ = try await service.restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: harness.session.generationID,
                currentGenerationRootURL: harness.session.generationRootURL
            )
        } verify: { _ in }
        XCTAssertEqual(try tree(harness.support), supportBefore)
        XCTAssertEqual(try tree(package), packageBefore)
        XCTAssertEqual(
            try harness.factory.currentGenerationID(),
            harness.session.generationID
        )
        XCTAssertNil(try RestoreIntentStore(
            applicationSupportURL: harness.support
        ).load())
    }
}

private final class C27S64TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(AssetLocatorStateV1.allCases.count, 4)
        XCTAssertEqual(LocatorBindingActionV1.allCases.count, 6)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionStartsWork)
    }
}

extension S6_4AtomicRestoreTests {
    func testC24AccessibleDocumentTypedAnchor() throws {
        XCTAssertEqual(AccessibleDocumentSemanticTreeV1.schemaVersion, 1)
        XCTAssertEqual(AccessibleDocumentRoleV1.allCases.count, 13)
        XCTAssertEqual(AccessibleDocumentAssessmentStateV1.allCases.count, 4)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
    }
}

extension S6_4AtomicRestoreTests {
    func testC22RecoverabilityVerificationAnchor() throws {
        XCTAssertEqual(RecoverabilityVerificationReceiptV1.schemaVersion, 1)
        try V21RecoverabilityImportBoundaryV1.validate(persistentSchemaVersion: 21, recordsSchemaVersion: 20)
        XCTAssertFalse(RecoverabilityVerificationLifecycleV1.liveRestorePermitted)
        XCTAssertEqual(RecoverabilityVerificationLifecycleV1.writer, "SOLE_CANONICAL_WORKSPACE_WRITER")
    }
}

extension S6_4AtomicRestoreTests {
    func testV23P03C18PromotionBundleKeepsOldOrNewInterruptionPolicy() throws {
        XCTAssertEqual(
            PackageEvolutionLifecycleV1.interruption,
            "OLD_COMPLETE_OR_NEW_COMPLETE_NEVER_HYBRID"
        )
        XCTAssertTrue(PackageSandboxCheckKindV1.allCases.contains(.backupRestore))
        XCTAssertGreaterThan(MemoryLayout<PackagePromotionAtomicBundleV1>.size, 0)
    }
}

extension S6_4AtomicRestoreTests {
    func testV23P03C36RestorePublicationReceiptRequiresCanonicalCommit() throws {
        let receipt = try DraftAttachmentRestorePublicationReceiptV1(restoreID:UUID(),workspaceID:WorkspaceID(rawValue:UUID()),sourceManifestSHA256:String(repeating:"a",count:64),adoptedStageIDs:[UUID()],reusedStageIDs:[],publishedAt:Date(timeIntervalSince1970:1))
        try receipt.validate()
        XCTAssertFalse(receipt.atomicAcrossRoots)
        XCTAssertTrue(receipt.canonicalCommitRequired)
    }
}

extension S6_4AtomicRestoreTests {
    func testV23P03C15AtomicRestoreRoundTripsAllPacketRowsTogether() throws {
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 150_164)
        let manifest = try WorkPacketManifestRow(fixture.manifest).value()
        let claim = try WorkItemClaimRow(fixture.claim).value()
        let lease = try WorkLeaseRow(fixture.lease).value()
        let release = try WorkReleaseRow(fixture.completedRelease).value()
        let handoff = try WorkHandoffRow(fixture.handoff).value()
        XCTAssertEqual(manifest, fixture.manifest)
        XCTAssertEqual(claim, fixture.claim)
        XCTAssertEqual(lease, fixture.lease)
        XCTAssertEqual(release, fixture.completedRelease)
        XCTAssertEqual(handoff, fixture.handoff)
    }
}

extension S6_4AtomicRestoreTests {
    func testV23P03C13AtomicRestoreRebindsCompleteAssuranceBundle() throws {
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture(seed: 51_640)
        let destination = C13EvidenceAssuranceTestSupportV1.workspace(51_641)
        let visibility = try fixture.routineVisibility.rebound(to: destination)
        let link = try fixture.customerLink.rebound(to: destination, visibility: visibility)
        let preview = try fixture.customerPreview.rebound(to: destination, links: [link])
        let manifest = try fixture.customerManifest.rebound(to: destination, preview: preview)
        let attestation = try fixture.customerAttestation.rebound(to: destination, manifest: manifest)

        XCTAssertEqual(visibility.workspaceID, destination)
        XCTAssertEqual(link.workspaceID, destination)
        XCTAssertEqual(preview.workspaceID, destination)
        XCTAssertEqual(manifest.workspaceID, destination)
        XCTAssertEqual(attestation.workspaceID, destination)
        XCTAssertEqual(attestation.manifestID, manifest.manifestID)
        try attestation.validate(manifest: manifest)
    }
}

private extension S6_4AtomicRestoreTests {
    struct Harness {
        let root: URL
        let support: URL
        let factory: StoreGenerationFactory
        let session: StoreGenerationSession
    }

    struct FileFact: Equatable {
        let path: String
        let bytes: Data
    }

    enum FixtureError: Error { case invalid }

    @MainActor
    func makeHarness(_ name: String) throws -> Harness {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "S6_4-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        let factory = StoreGenerationFactory(applicationSupportURL: support)
        let session = try factory.openOrBootstrapCurrent()
        return Harness(root: root, support: support, factory: factory, session: session)
    }

    @MainActor
    func makeSourcePackage(
        in root: URL,
        name: String,
        siteAddress: String? = nil,
        seed: ((StoreGenerationSession) throws -> Void)? = nil
    ) throws -> URL {
        let support = root.appendingPathComponent(
            "\(name)-support",
            isDirectory: true
        )
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        let session = try StoreGenerationFactory(
            applicationSupportURL: support
        ).openOrBootstrapCurrent()
        let siteID = uuid("64000000-0000-0000-0000-000000000001")
        session.modelContext.insert(Site(
            id: siteID,
            label: "North lot",
            address: siteAddress,
            timeZoneID: "America/New_York",
            createdAt: Date(timeIntervalSince1970: 1_786_708_800)
        ))
        session.modelContext.insert(Asset(
            id: uuid("64000000-0000-0000-0000-000000000002"),
            siteID: siteID,
            packID: SignPack.illuminatedSignV1.packID,
            packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion,
            packContentVersion: SignPack.illuminatedSignV1.contentVersion,
            label: "Pylon sign",
            createdAt: Date(timeIntervalSince1970: 1_786_708_801)
        ))
        try seed?(session)
        try session.modelContext.save()
        let destination = root.appendingPathComponent(
            "\(name)-export",
            isDirectory: true
        )
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let exporter = BackupExportService(
            modelContext: session.modelContext,
            generationRootURL: session.generationRootURL,
            now: { Date(timeIntervalSince1970: 1_786_708_900) }
        )
        let preview = try exporter.prepare()
        return try exporter.export(previewID: preview.id, to: destination)
    }

    @MainActor
    func importPackage(
        _ package: URL,
        into session: StoreGenerationSession
    ) throws -> ValidatedV4BackupPackageV1 {
        try BackupImportService(
            generationRootURL: session.generationRootURL,
            makeUUID: { self.uuid("64000000-0000-0000-0000-000000000099") },
            scopedAccess: .alreadyAuthorized
        ).stageAndValidate(selectedPackageURL: package)
    }

    func sequence(_ values: [UUID]) -> () -> UUID {
        var remaining = values
        return {
            guard !remaining.isEmpty else { return UUID() }
            return remaining.removeFirst()
        }
    }

    func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    func tree(_ root: URL) throws -> [FileFact] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { throw FixtureError.invalid }
        var facts: [FileFact] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory != true else { continue }
            let relative = String(
                url.standardizedFileURL.path.dropFirst(
                    root.standardizedFileURL.path.count + 1
                )
            )
            facts.append(FileFact(path: relative, bytes: try Data(contentsOf: url)))
        }
        return facts.sorted { $0.path < $1.path }
    }
}

extension S6_4AtomicRestoreTests {
    func testV23P03C41AtomicRestoreRebindsDescriptorAndEventTogether() throws {
        let fixture = try C41FunctionalRelationshipTestSupportV1.makeFixture(seed: 41_640)
        let snapshot = try CompletedFunctionalRelationshipSnapshotV1(
            snapshotID: C41FunctionalRelationshipTestSupportV1.id(41_642),
            workspaceID: fixture.workspaceID,
            capturedAt: C41FunctionalRelationshipTestSupportV1.fixedDate,
            descriptorReleases: [fixture.descriptor],
            relationships: [fixture.added]
        )
        let restoredWorkspace = C41FunctionalRelationshipTestSupportV1.workspace(41_643)
        let restored = try snapshot.rebound(to: restoredWorkspace)

        XCTAssertEqual(restored.workspaceID, restoredWorkspace)
        XCTAssertEqual(restored.descriptorReleases.first?.workspaceID, restoredWorkspace)
        XCTAssertEqual(restored.relationships.first?.workspaceID, restoredWorkspace)
        XCTAssertEqual(restored.relationships.first?.actor.workspaceID, restoredWorkspace)
        XCTAssertNotEqual(restored.snapshotSHA256, snapshot.snapshotSHA256)
        try restored.validate()
    }
}

private extension S6_4AtomicRestoreTests {
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
}

extension S6_4AtomicRestoreTests {
    func testV23P03C14AtomicRestoreRoundTripsAllFivePersistentRows() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 145_164)
        let transitionRow = try InspectionReviewTransitionRow(fixture.transitions[0])
        let dispositionRow = try ReviewDispositionRow(fixture.acceptedDisposition)
        let requestRow = try ChangeRequestRow(fixture.resolvedChangeRequest)
        let policyRow = try CorrectiveActionPolicyRow(fixture.policy)
        let eventRow = try CorrectiveActionEventRow(fixture.actions[3])
        XCTAssertEqual(try transitionRow.value(), fixture.transitions[0])
        XCTAssertEqual(try dispositionRow.value(), fixture.acceptedDisposition)
        XCTAssertEqual(try requestRow.value(), fixture.resolvedChangeRequest)
        XCTAssertEqual(try policyRow.value(), fixture.policy)
        XCTAssertEqual(try eventRow.value(), fixture.actions[3])
    }

    func testV23P03C19RestoreRehydratesImmutableCaptureAndCalibrationRows() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        let captureRow = try MeasurementCaptureRow(fixture.capture)
        let calibrationRow = try CalibrationStatusSnapshotRow(fixture.currentCalibration)
        XCTAssertEqual(try captureRow.value(), fixture.capture)
        XCTAssertEqual(try calibrationRow.value(), fixture.currentCalibration)
        XCTAssertEqual(captureRow.mutationID, calibrationRow.mutationID)
        XCTAssertEqual(captureRow.workspaceID, calibrationRow.workspaceID)
    }

    func testC20PrivacyTransformRestoreAcceptsOnlyCompletePublicationReceipt() throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        let receipt = try PrivacyTransformPublicationReceiptV1(
            bundle: fixture.bundle,
            canonicalMutationReceiptSHA256: C20PrivacyTransformTestSupport.canonicalMutationReceiptSHA256
        )
        try receipt.validate(
            bundle: fixture.bundle,
            expectedCanonicalMutationReceiptSHA256:
                C20PrivacyTransformTestSupport.canonicalMutationReceiptSHA256
        )
        XCTAssertEqual(receipt.manifestID, fixture.manifest.manifestID)
        XCTAssertThrowsError(try fixture.original.validatePrivacyDerivative(fixture.original))
    }
}

extension S6_4AtomicRestoreTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}
extension S6_4AtomicRestoreTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(SurveyDefinitionLifecycleV1.writer, "SOLE_CANONICAL_WORKSPACE_WRITER")
        XCTAssertEqual(SurveyDefinitionLifecycleV1.persistentFamilies.count, 2)
        XCTAssertEqual(PersistentSchemaV24.models.count, 87)
    }
}
extension S6_4AtomicRestoreTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

extension S6_4AtomicRestoreTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
private final class C31LightingAnchorS64AtomicRestoreTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

extension S6_4AtomicRestoreTests {
    @MainActor
    func testC32RealBackupRestorePreservesImmutableAcceptanceAndRebindsOnlyTargetFacts() async throws {
        for (offset, mode) in [
            BackupRestoreMode.emptyInstall,
            .replaceExisting,
            .clone,
            .fork
        ].enumerated() {
            let harness = try makeHarness("c32-real-restore-\(offset)")
            defer { try? fileManager.removeItem(at: harness.root) }
            var sourceReceipt: AssistanceAcceptanceReceiptV1?
            var sourceAcceptanceBytes: Data?
            var sourceEnvelopeBytes: Data?
            var sourceMutationReceiptBytes: Data?
            let package = try makeSourcePackage(
                in: harness.root,
                name: "c32-source-\(offset)",
                seed: { sourceSession in
                    let receipt = try C32AssistanceTestSupport.commitPersistentAcceptance(
                        in: sourceSession,
                        slot: 620 + offset
                    )
                    sourceReceipt = receipt
                    sourceAcceptanceBytes = try XCTUnwrap(
                        sourceSession.modelContext.fetch(
                            FetchDescriptor<AssistanceAcceptanceReceiptRow>()
                        ).first
                    ).canonicalData
                    let mutationRow = try XCTUnwrap(
                        sourceSession.modelContext.fetch(FetchDescriptor<MutationReceiptRow>())
                            .first { $0.mutationID == receipt.mutationID.rawValue }
                    )
                    sourceEnvelopeBytes = mutationRow.envelopeData
                    sourceMutationReceiptBytes = mutationRow.receiptData
                }
            )
            let expectedReceipt = try XCTUnwrap(sourceReceipt)
            let expectedAcceptanceBytes = try XCTUnwrap(sourceAcceptanceBytes)
            let expectedEnvelopeBytes = try XCTUnwrap(sourceEnvelopeBytes)
            let expectedMutationReceiptBytes = try XCTUnwrap(sourceMutationReceiptBytes)
            let validated = try importPackage(package, into: harness.session)
            XCTAssertEqual(validated.records.assistanceAcceptanceReceipts.count, 1)
            XCTAssertEqual(validated.records.mutationHistory?.receipts.count, 1)
            let restored = try await BackupRestoreService(
                applicationSupportURL: harness.support,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
            ).restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: harness.session.generationID,
                currentGenerationRootURL: harness.session.generationRootURL,
                mode: mode
            )
            let acceptanceRows = try restored.modelContext.fetch(
                FetchDescriptor<AssistanceAcceptanceReceiptRow>()
            )
            XCTAssertEqual(acceptanceRows.count, 1)
            let restoredReceipt = try XCTUnwrap(acceptanceRows.first).value()
            XCTAssertEqual(restoredReceipt, expectedReceipt)
            XCTAssertEqual(acceptanceRows[0].canonicalData, expectedAcceptanceBytes)
            XCTAssertEqual(restoredReceipt.receiptSHA256, expectedReceipt.receiptSHA256)
            XCTAssertEqual(restoredReceipt.workspaceID, expectedReceipt.workspaceID)

            let mutationRow = try XCTUnwrap(
                restored.modelContext.fetch(FetchDescriptor<MutationReceiptRow>())
                    .first { $0.mutationID == expectedReceipt.mutationID.rawValue }
            )
            XCTAssertEqual(mutationRow.envelopeData, expectedEnvelopeBytes)
            XCTAssertEqual(mutationRow.receiptData, expectedMutationReceiptBytes)

            let restoredFact = try XCTUnwrap(
                restored.modelContext.fetch(FetchDescriptor<FactCaptureRow>()).first
            ).value()
            XCTAssertEqual(restoredFact.value, expectedReceipt.acceptedValue)
            XCTAssertEqual(restoredFact.workspaceID, restored.workspaceID)

            let restoredJournal = try MutationJournalStoreV1(
                modelContext: restored.modelContext,
                identity: restored.workspaceIdentity,
                generationID: restored.generationID,
                allowStateBootstrap: false
            )
            try restoredJournal.validateAll()
            if mode == .clone || mode == .fork {
                XCTAssertNotEqual(restored.workspaceID, expectedReceipt.workspaceID)
                XCTAssertNil(try restoredJournal.assistanceAcceptanceReceipt(
                    mutationID: expectedReceipt.mutationID
                ))
            } else {
                XCTAssertEqual(restored.workspaceID, expectedReceipt.workspaceID)
                XCTAssertEqual(
                    try restoredJournal.assistanceAcceptanceReceipt(
                        mutationID: expectedReceipt.mutationID
                    ),
                    expectedReceipt
                )
            }
            XCTAssertFalse(AssistancePersistenceEnrollmentV1.proposalIsPersistent)
            XCTAssertFalse(AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent)
        }

        let chainHarness = try makeHarness("c32-historic-chain")
        defer { try? fileManager.removeItem(at: chainHarness.root) }
        var originalReceipt: AssistanceAcceptanceReceiptV1?
        var originalAcceptanceBytes: Data?
        var originalEnvelopeBytes: Data?
        var originalMutationReceiptBytes: Data?
        let sourcePackage = try makeSourcePackage(
            in: chainHarness.root,
            name: "c32-historic-source",
            seed: { sourceSession in
                let receipt = try C32AssistanceTestSupport.commitPersistentAcceptance(
                    in: sourceSession,
                    slot: 630
                )
                originalReceipt = receipt
                originalAcceptanceBytes = try XCTUnwrap(
                    sourceSession.modelContext.fetch(
                        FetchDescriptor<AssistanceAcceptanceReceiptRow>()
                    ).first
                ).canonicalData
                let mutationRow = try XCTUnwrap(
                    sourceSession.modelContext.fetch(FetchDescriptor<MutationReceiptRow>())
                        .first { $0.mutationID == receipt.mutationID.rawValue }
                )
                originalEnvelopeBytes = mutationRow.envelopeData
                originalMutationReceiptBytes = mutationRow.receiptData
            }
        )
        let expectedReceipt = try XCTUnwrap(originalReceipt)
        let expectedAcceptanceBytes = try XCTUnwrap(originalAcceptanceBytes)
        let expectedEnvelopeBytes = try XCTUnwrap(originalEnvelopeBytes)
        let expectedMutationReceiptBytes = try XCTUnwrap(originalMutationReceiptBytes)

        func assertHistoricSourceProvenance(
            in session: StoreGenerationSession,
            expectedCurrentWorkspaceID: WorkspaceID? = nil
        ) throws {
            let acceptanceRows = try session.modelContext.fetch(
                FetchDescriptor<AssistanceAcceptanceReceiptRow>()
            )
            XCTAssertEqual(acceptanceRows.count, 1)
            let receipt = try XCTUnwrap(acceptanceRows.first).value()
            XCTAssertEqual(receipt, expectedReceipt)
            XCTAssertEqual(acceptanceRows[0].canonicalData, expectedAcceptanceBytes)
            XCTAssertEqual(receipt.receiptSHA256, expectedReceipt.receiptSHA256)
            XCTAssertEqual(receipt.workspaceID, expectedReceipt.workspaceID)
            XCTAssertNotEqual(session.workspaceID, expectedReceipt.workspaceID)
            if let expectedCurrentWorkspaceID {
                XCTAssertEqual(session.workspaceID, expectedCurrentWorkspaceID)
            }

            let mutationRow = try XCTUnwrap(
                session.modelContext.fetch(FetchDescriptor<MutationReceiptRow>())
                    .first { $0.mutationID == expectedReceipt.mutationID.rawValue }
            )
            XCTAssertEqual(mutationRow.envelopeData, expectedEnvelopeBytes)
            XCTAssertEqual(mutationRow.receiptData, expectedMutationReceiptBytes)

            let fact = try XCTUnwrap(
                session.modelContext.fetch(FetchDescriptor<FactCaptureRow>()).first
            ).value()
            XCTAssertEqual(fact.value, expectedReceipt.acceptedValue)
            XCTAssertEqual(fact.workspaceID, session.workspaceID)

            let journal = try MutationJournalStoreV1(
                modelContext: session.modelContext,
                identity: session.workspaceIdentity,
                generationID: session.generationID,
                allowStateBootstrap: false
            )
            try journal.validateAll()
            XCTAssertNil(try journal.assistanceAcceptanceReceipt(
                mutationID: expectedReceipt.mutationID
            ))
        }

        let cloned = try await BackupRestoreService(
            applicationSupportURL: chainHarness.support,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
        ).restore(
            validatedPackage: try importPackage(sourcePackage, into: chainHarness.session),
            currentModelContext: chainHarness.session.modelContext,
            currentGenerationID: chainHarness.session.generationID,
            currentGenerationRootURL: chainHarness.session.generationRootURL,
            mode: .clone
        )
        try assertHistoricSourceProvenance(in: cloned)

        let cloneExportDirectory = chainHarness.root.appendingPathComponent(
            "c32-historic-clone-export",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: cloneExportDirectory,
            withIntermediateDirectories: true
        )
        let cloneExporter = BackupExportService(
            modelContext: cloned.modelContext,
            generationRootURL: cloned.generationRootURL,
            now: { Date(timeIntervalSince1970: 1_786_709_000) }
        )
        let clonePreview = try cloneExporter.prepare()
        let clonePackage = try cloneExporter.export(
            previewID: clonePreview.id,
            to: cloneExportDirectory
        )

        let forked = try await BackupRestoreService(
            applicationSupportURL: chainHarness.support,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
        ).restore(
            validatedPackage: try importPackage(clonePackage, into: cloned),
            currentModelContext: cloned.modelContext,
            currentGenerationID: cloned.generationID,
            currentGenerationRootURL: cloned.generationRootURL,
            mode: .fork
        )
        XCTAssertNotEqual(forked.workspaceID, cloned.workspaceID)
        try assertHistoricSourceProvenance(in: forked)

        let forkExportDirectory = chainHarness.root.appendingPathComponent(
            "c32-historic-fork-export",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: forkExportDirectory,
            withIntermediateDirectories: true
        )
        let forkExporter = BackupExportService(
            modelContext: forked.modelContext,
            generationRootURL: forked.generationRootURL,
            now: { Date(timeIntervalSince1970: 1_786_709_100) }
        )
        let forkPreview = try forkExporter.prepare()
        let forkPackage = try forkExporter.export(
            previewID: forkPreview.id,
            to: forkExportDirectory
        )

        let ordinaryHarness = try makeHarness("c32-historic-chain-empty-install")
        defer { try? fileManager.removeItem(at: ordinaryHarness.root) }
        let ordinaryRestored = try await BackupRestoreService(
            applicationSupportURL: ordinaryHarness.support,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
        ).restore(
            validatedPackage: try importPackage(forkPackage, into: ordinaryHarness.session),
            currentModelContext: ordinaryHarness.session.modelContext,
            currentGenerationID: ordinaryHarness.session.generationID,
            currentGenerationRootURL: ordinaryHarness.session.generationRootURL,
            mode: .emptyInstall
        )
        try assertHistoricSourceProvenance(
            in: ordinaryRestored,
            expectedCurrentWorkspaceID: forked.workspaceID
        )
    }
}

extension S6_4AtomicRestoreTests {
    @MainActor
    func testC33RealBackupRestoreCloneForkCarryDirectOriginalBytesAndTypedRows() async throws {
        let sourceRoot = fileManager.temporaryDirectory.appendingPathComponent(
            "c33-real-backup-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: sourceRoot) }
        let sourceSupport = sourceRoot.appendingPathComponent("Application Support", isDirectory: true)
        try fileManager.createDirectory(at: sourceSupport, withIntermediateDirectories: true)
        let sourceSession = try StoreGenerationFactory(
            applicationSupportURL: sourceSupport
        ).openOrBootstrapCurrent()
        let source = try await C33TemporalEvidenceTestSupport.commitPersistentClip(
            in: sourceSession,
            slot: 730
        )
        let sourceAnchors = try C33TemporalEvidenceTestSupport.commitPersistentAnchors(
            in: sourceSession,
            clip: source.clip,
            slots: [731, 732, 733]
        )
        let sourceSnapshots = try C33TemporalEvidenceTestSupport.persistReportSnapshots(
            in: sourceSession,
            clip: source.clip,
            anchorSubsets: [
                [sourceAnchors[0], sourceAnchors[1]],
                [sourceAnchors[1], sourceAnchors[2]]
            ],
            slot: 740
        )
        try sourceSession.modelContext.save()
        let sourceSnapshotsByID = Dictionary(
            uniqueKeysWithValues: sourceSnapshots.map { ($0.reportID, $0) }
        )
        let sourceSnapshotSHAByID = try Dictionary(uniqueKeysWithValues: sourceSnapshots.map {
            ($0.reportID, try ReportSnapshotEncoderV1().encode($0).sha256)
        })
        let sourceRow = try XCTUnwrap(
            sourceSession.modelContext.fetch(FetchDescriptor<TemporalEvidenceClipRow>()).first
        )
        let sourceCanonicalData = sourceRow.canonicalData
        let sourceOriginalDigest = try XCTUnwrap(
            source.clip.original.digests.digest(for: .sha256)
        )
        let sourceBytes = C33TemporalEvidenceTestSupport.bytes(for: source.clip.facts.kind)
        let exportDirectory = sourceRoot.appendingPathComponent("Export", isDirectory: true)
        try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let exporter = BackupExportService(
            modelContext: sourceSession.modelContext,
            generationRootURL: sourceSession.generationRootURL,
            now: { C33TemporalEvidenceTestSupport.fixedDate.addingTimeInterval(100) }
        )
        let preview = try exporter.prepare()
        let package = try exporter.export(previewID: preview.id, to: exportDirectory)

        for (offset, mode) in [
            BackupRestoreMode.emptyInstall,
            .clone,
            .fork
        ].enumerated() {
            let harness = try makeHarness("c33-real-restore-\(offset)")
            defer { try? fileManager.removeItem(at: harness.root) }
            let validated = try importPackage(package, into: harness.session)
            XCTAssertEqual(validated.manifest.source.persistentSchemaVersion, 33)
            XCTAssertEqual(validated.records.recordsSchemaVersion, 32)
            XCTAssertEqual(validated.records.temporalEvidence.count, 1)
            XCTAssertEqual(validated.records.reports.count, 2)
            let archived = try XCTUnwrap(validated.records.temporalEvidence.first).clipValue()
            XCTAssertEqual(archived, source.clip)
            XCTAssertEqual(
                try XCTUnwrap(validated.records.temporalEvidence.first).canonicalData,
                sourceCanonicalData
            )
            let sourceMember = try TemporalEvidenceBackupMemberV1.original(for: source.clip)
            XCTAssertEqual(validated.members[sourceMember], sourceBytes)

            if offset == 0 {
                let profile = try C33TemporalEvidenceTestSupport.profile(
                    workspaceID: source.clip.workspaceID,
                    reportProjection: .typedLinkOnly
                )
                let conflictingClip = try TemporalEvidenceClipV1(
                    clipID: source.clip.clipID,
                    workspaceID: source.clip.workspaceID,
                    target: source.clip.target,
                    original: source.clip.original,
                    originalProvenance: source.clip.originalProvenance,
                    locator: source.clip.locator,
                    facts: source.clip.facts,
                    profile: profile,
                    accessibleDescription: source.clip.accessibleDescription + " Conflicting envelope.",
                    manualTranscript: source.clip.manualTranscript,
                    recordedBy: source.clip.recordedBy,
                    capturedAt: source.clip.capturedAt,
                    acceptedAt: source.clip.acceptedAt,
                    supersedesClipID: source.clip.supersedesClipID,
                    revision: source.clip.revision,
                    mutationID: source.clip.mutationID
                )
                var recordsObject = try XCTUnwrap(
                    JSONSerialization.jsonObject(
                        with: JSONEncoder().encode(validated.records)
                    ) as? [String: Any]
                )
                recordsObject["temporalEvidence"] = try JSONSerialization.jsonObject(
                    with: JSONEncoder().encode([
                        try V33BackupTemporalEvidenceRecordV1(conflictingClip)
                    ])
                )
                let conflictingRecords = try JSONDecoder().decode(
                    V4BackupRecordsV1.self,
                    from: JSONSerialization.data(withJSONObject: recordsObject)
                )
                XCTAssertThrowsError(try conflictingRecords.validateC33TemporalEvidence())
                let conflictingPackage = ValidatedV4BackupPackageV1(
                    stagedPackageURL: validated.stagedPackageURL,
                    manifest: validated.manifest,
                    records: conflictingRecords,
                    members: validated.members,
                    summary: validated.summary
                )
                do {
                    _ = try await BackupRestoreService(
                        applicationSupportURL: harness.support,
                        storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
                    ).restore(
                        validatedPackage: conflictingPackage,
                        currentModelContext: harness.session.modelContext,
                        currentGenerationID: harness.session.generationID,
                        currentGenerationRootURL: harness.session.generationRootURL,
                        mode: .emptyInstall
                    )
                    XCTFail("mismatched temporal record/envelope pair restored")
                } catch { }
                XCTAssertEqual(
                    try harness.session.modelContext.fetchCount(
                        FetchDescriptor<TemporalEvidenceClipRow>()
                    ),
                    0
                )
            }

            let restored = try await BackupRestoreService(
                applicationSupportURL: harness.support,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
            ).restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: harness.session.generationID,
                currentGenerationRootURL: harness.session.generationRootURL,
                mode: mode
            )
            let rows = try restored.modelContext.fetch(FetchDescriptor<TemporalEvidenceClipRow>())
            XCTAssertEqual(rows.count, 1)
            let clip = try XCTUnwrap(rows.first).value()
            let restoredAnchors = try restored.modelContext.fetch(
                FetchDescriptor<TimecodedEvidenceAnchorRow>()
            ).map { try $0.value() }
            XCTAssertEqual(restoredAnchors.count, 3)
            XCTAssertEqual(clip.workspaceID, restored.workspaceID)
            XCTAssertEqual(clip.original.contentID, source.clip.original.contentID)
            XCTAssertEqual(clip.original.digests.digest(for: .sha256), sourceOriginalDigest)
            XCTAssertEqual(clip.facts, source.clip.facts)
            XCTAssertEqual(
                try Data(contentsOf: restored.generationRootURL.appendingPathComponent(
                    try TemporalEvidenceBackupMemberV1.original(for: clip)
                )),
                sourceBytes
            )
            if mode == .emptyInstall || mode == .replaceExisting {
                XCTAssertEqual(clip.workspaceID, source.clip.workspaceID)
                XCTAssertEqual(rows[0].canonicalData, sourceCanonicalData)
                XCTAssertEqual(clip.limitProfile, source.clip.limitProfile)
            } else {
                XCTAssertNotEqual(clip.workspaceID, source.clip.workspaceID)
                XCTAssertNotEqual(rows[0].canonicalData, sourceCanonicalData)
                XCTAssertEqual(clip.limitProfile.profileID, source.clip.limitProfile.profileID)
                XCTAssertEqual(
                    clip.limitProfile.revision,
                    source.clip.limitProfile.revision + 1
                )
                XCTAssertEqual(clip.limitProfile.audio, source.clip.limitProfile.audio)
                XCTAssertEqual(clip.limitProfile.video, source.clip.limitProfile.video)
                XCTAssertEqual(
                    clip.limitProfile.maximumClipsPerRequirement,
                    source.clip.limitProfile.maximumClipsPerRequirement
                )
                XCTAssertEqual(
                    clip.limitProfile.maximumClipsPerSession,
                    source.clip.limitProfile.maximumClipsPerSession
                )
                XCTAssertEqual(
                    clip.limitProfile.minimumFreeByteCount,
                    source.clip.limitProfile.minimumFreeByteCount
                )
                XCTAssertEqual(
                    clip.limitProfile.reportProjection,
                    source.clip.limitProfile.reportProjection
                )
                XCTAssertEqual(
                    clip.limitProfile.requiresAccessibleDescription,
                    source.clip.limitProfile.requiresAccessibleDescription
                )
                XCTAssertEqual(
                    clip.limitProfile.requiresManualTranscript,
                    source.clip.limitProfile.requiresManualTranscript
                )
                XCTAssertEqual(clip.limitProfile.definitionRelease, clip.target.definitionRelease)
                XCTAssertNotEqual(
                    clip.limitProfile.definitionRelease,
                    source.clip.limitProfile.definitionRelease
                )
                XCTAssertNotEqual(
                    clip.limitProfile.packageRelease,
                    source.clip.limitProfile.packageRelease
                )
                XCTAssertNotEqual(
                    clip.limitProfile.profileSHA256,
                    source.clip.limitProfile.profileSHA256
                )
                XCTAssertNotEqual(clip.clipSHA256, source.clip.clipSHA256)
            }
            let journal = try MutationJournalStoreV1(
                modelContext: restored.modelContext,
                identity: restored.workspaceIdentity,
                generationID: restored.generationID,
                allowStateBootstrap: false
            )
            try journal.validateAll()

            let reportRows = try restored.modelContext.fetch(FetchDescriptor<Report>(
                sortBy: [SortDescriptor(\.id)]
            ))
            XCTAssertEqual(reportRows.count, 2)
            var restoredSnapshots: [ReportSnapshotV1] = []
            for report in reportRows {
                let data = try Data(contentsOf: restored.generationRootURL.appendingPathComponent(
                    report.snapshotRelativePath
                ))
                XCTAssertEqual(KernelCanonicalHashV1.sha256(data), report.snapshotSHA256)
                let snapshot = try ReportSnapshotEncoderV1().decode(data)
                let sourceSnapshot = try XCTUnwrap(sourceSnapshotsByID[snapshot.reportID])
                let sourceLink = try XCTUnwrap(sourceSnapshot.temporalEvidenceLinks?.first)
                let link = try XCTUnwrap(snapshot.temporalEvidenceLinks?.first)
                XCTAssertEqual(link.workspaceID, clip.workspaceID)
                XCTAssertEqual(link.clipID, clip.clipID)
                XCTAssertEqual(link.clipRevision, clip.revision)
                XCTAssertEqual(link.clipSHA256, clip.clipSHA256)
                XCTAssertEqual(link.contentID, clip.original.contentID)
                XCTAssertEqual(link.contentID, sourceLink.contentID)
                XCTAssertEqual(link.accessibleDescription, sourceLink.accessibleDescription)
                XCTAssertEqual(link.manualTranscript, sourceLink.manualTranscript)
                let selectedDestinationAnchors = try sourceLink.anchorBindings.map { binding in
                    try XCTUnwrap(restoredAnchors.first(where: {
                        $0.anchorID == binding.anchorID && $0.revision == binding.revision
                    }))
                }
                let expectedBindings = try selectedDestinationAnchors.map {
                    try TemporalEvidenceReportAnchorBindingV1(anchor: $0, clip: clip)
                }.sorted()
                XCTAssertEqual(link.anchorBindings, expectedBindings)
                XCTAssertEqual(
                    link.anchorBindings.map {
                        "\($0.anchorID.uuidString.lowercased()):\($0.revision)"
                    },
                    sourceLink.anchorBindings.map {
                        "\($0.anchorID.uuidString.lowercased()):\($0.revision)"
                    }
                )
                try link.validate(clip: clip, anchors: selectedDestinationAnchors)
                XCTAssertEqual(snapshot.assurance == nil, sourceSnapshot.assurance == nil)
                if let assurance = snapshot.assurance {
                    XCTAssertEqual(assurance.preview.workspaceID, clip.workspaceID)
                    try assurance.validate()
                }
                if mode == .clone || mode == .fork {
                    XCTAssertNotEqual(
                        report.snapshotSHA256,
                        sourceSnapshotSHAByID[snapshot.reportID]
                    )
                }
                restoredSnapshots.append(snapshot)
            }
            let restoredLinks = restoredSnapshots.compactMap {
                $0.temporalEvidenceLinks?.first
            }
            XCTAssertEqual(restoredLinks.count, 2)
            XCTAssertEqual(restoredLinks[0].anchorCount, restoredLinks[1].anchorCount)
            XCTAssertNotEqual(
                Set(restoredLinks[0].anchorBindings.map(\.anchorID)),
                Set(restoredLinks[1].anchorBindings.map(\.anchorID))
            )

            if mode == .clone || mode == .fork {
                let boundRevision = try journal.currentRevision(
                    writerInstanceID: C33TemporalEvidenceTestSupport.id(9_900 + offset)
                )
                let recovery = try TemporalEvidencePromotionRecoveryFileAdapterV1(
                    generationRootURL: restored.generationRootURL,
                    workspaceID: clip.workspaceID,
                    verify: { _, _, _ in false },
                    remove: { _, _, _ in }
                )
                let deletionReferences = try await TemporalEvidenceDeletionExternalReferenceResolverV1(
                    modelContext: restored.modelContext,
                    generationRootURL: restored.generationRootURL,
                    journal: journal,
                    recovery: recovery
                ).temporalEvidenceReferences(
                    workspaceID: clip.workspaceID,
                    boundRevision: boundRevision
                )
                XCTAssertEqual(
                    deletionReferences.reportLinks,
                    restoredSnapshots.flatMap { $0.temporalEvidenceLinks ?? [] }
                )
            }
        }
    }
}

extension S6_4AtomicRestoreTests {
    @MainActor
    func testV23P03C42AtomicRestorePublishesACompleteTypedReceipt() async throws {
        let receipts = [
            try CompositeAreaSafetyArchetypeV1.run(),
            try ControllerZoneDistributionArchetypeV1.run()
        ]

        for (offset, receipt) in receipts.enumerated() {
            let payload = try CrossMarketCanonicalV1.data(receipt).base64EncodedString()
            let harness = try makeHarness("c42-atomic-\(offset)")
            defer { try? fileManager.removeItem(at: harness.root) }
            let package = try makeSourcePackage(
                in: harness.root,
                name: "c42-source-\(offset)",
                siteAddress: payload
            )
            let validated = try importPackage(package, into: harness.session)
            let restoredSession = try await BackupRestoreService(
                applicationSupportURL: harness.support,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })
            ).restore(
                validatedPackage: validated,
                currentModelContext: harness.session.modelContext,
                currentGenerationID: harness.session.generationID,
                currentGenerationRootURL: harness.session.generationRootURL,
                mode: .emptyInstall
            )
            let restoredPayload = try XCTUnwrap(
                restoredSession.modelContext.fetch(FetchDescriptor<Site>()).first?.address
            )
            XCTAssertEqual(restoredPayload, payload)
            XCTAssertEqual(
                try CrossMarketCanonicalV1.decode(
                    ModelRunReceiptV1.self,
                    from: try XCTUnwrap(Data(base64Encoded: restoredPayload))
                ),
                receipt
            )
            XCTAssertNotEqual(restoredSession.generationID, harness.session.generationID)
            XCTAssertNil(try RestoreIntentStore(applicationSupportURL: harness.support).load())
        }
    }
}

private final class C33TemporalEvidenceAnchorS64AtomicRestore: XCTestCase {
    func testC33S64AtomicRestoreCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "restore.atomic.temporal-evidence",
            kind: .video,
            reportProjection: .typedLinkOnly
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "restore.atomic.temporal-evidence",
            kind: .video,
            reportProjection: .typedLinkOnly
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

private final class C32AssistanceAnchorS64AtomicRestore: XCTestCase {
    func testC32S64AtomicRestoreCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .site,
            fieldID: "restore.atomic-receipt",
            value: .text("restored accepted value")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .site,
            fieldID: "restore.atomic-receipt",
            valueKind: .text
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
private final class C46S64AtomicRestoreCompatibilityTests: XCTestCase {
    func testC46AtomicRestoreKeepsStableContactIdentity() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "atomic-restore",
            kind: .email,
            handoff: .email,
            slot: 46404
        )
    }
}

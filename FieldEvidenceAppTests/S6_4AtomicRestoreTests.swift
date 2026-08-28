import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class S6_4AtomicRestoreTests: XCTestCase {
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
    func makeSourcePackage(in root: URL, name: String) throws -> URL {
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
            address: nil,
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
}

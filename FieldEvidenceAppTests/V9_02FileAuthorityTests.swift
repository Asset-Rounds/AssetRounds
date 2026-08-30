import Darwin
import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class V9_02FileAuthorityTests: XCTestCase {
    private let fileManager = FileManager.default

    func testOwnedFileKindMatrixIsClosedAndHasExplicitDispositions() throws {
        let directoryKinds: Set<OwnedFileKindV1> = [
            .durableDirectory,
            .stagingDirectory,
            .restoreStaging,
            .generationLeaseDirectory,
            .portableExchangeDirectory,
            .cache,
            .scratch,
        ]
        let excludedKinds: Set<OwnedFileKindV1> = [
            .stagingDirectory,
            .restoreStaging,
            .stagingFile,
            .fieldDraftStagingFile,
            .temporaryFile,
            .generationPointerTemporary,
            .generationLeaseControl,
            .generationLeaseControlTemporary,
            .generationLeaseOwnerLock,
            .journal,
            .journalTemporary,
            .portableExchangeSessionFile,
            .portableExchangeJournalFile,
            .portableExchangeQuarantineFile,
            .diagnostics,
            .commerceEntitlementCache,
            .portableExchangeDirectory,
            .cache,
            .scratch,
            .searchIndex,
        ]

        XCTAssertEqual(OwnedFileKindV1.allCases.count, 30)
        XCTAssertEqual(
            Set(OwnedFileKindV1.allCases),
            directoryKinds.union(excludedKinds).union(Set([
                .database,
                .databaseWAL,
                .databaseSHM,
                .generationPointer,
                .mediaOriginal,
                .mediaThumbnail,
                .reportSnapshot,
                .reportPDF,
            ]))
        )

        for kind in OwnedFileKindV1.allCases {
            let disposition = ProtectedFilePolicyV1.disposition(for: kind)
            XCTAssertEqual(
                disposition.expectsDirectory,
                directoryKinds.contains(kind),
                kind.rawValue
            )
            XCTAssertEqual(
                disposition.isExcludedFromBackup,
                excludedKinds.contains(kind),
                kind.rawValue
            )
            XCTAssertEqual(
                ProtectedFilePolicyV1.isExcludedFromBackup(for: kind),
                excludedKinds.contains(kind),
                kind.rawValue
            )
            XCTAssertTrue(ProtectedFilePolicyV1.countsTowardOwnedStorage(kind), kind.rawValue)
            XCTAssertFalse(
                ProtectedFilePolicyV1.permitsAutomaticStoragePressureDeletion(kind),
                kind.rawValue
            )
        }

        try PortableExchangeProtectedFilePolicyV2.validate()
    }

    func testTemporaryFileSystemAppliesAndReadsBackEveryOwnedKind() throws {
        let root = try makeTemporaryRoot("matrix")
        defer { try? fileManager.removeItem(at: root) }

        for kind in OwnedFileKindV1.allCases {
            let disposition = ProtectedFilePolicyV1.disposition(for: kind)
            let item = root.appendingPathComponent(
                kind.rawValue,
                isDirectory: disposition.expectsDirectory
            )
            if disposition.expectsDirectory {
                try fileManager.createDirectory(
                    at: item,
                    withIntermediateDirectories: false
                )
            } else {
                XCTAssertTrue(
                    fileManager.createFile(
                        atPath: item.path,
                        contents: Data(kind.rawValue.utf8)
                    ),
                    kind.rawValue
                )
            }

            try ProtectedFilePolicyV1.applyAndVerify(kind, at: item)
            try ProtectedFilePolicyV1.verify(kind, at: item)
            try assertResourceValues(kind, at: item)
        }
    }

    func testWrongResourceValuesAreRepairedAndVerified() throws {
        let root = try makeTemporaryRoot("repair")
        defer { try? fileManager.removeItem(at: root) }
        let file = root.appendingPathComponent("model.sqlite")
        XCTAssertTrue(fileManager.createFile(atPath: file.path, contents: Data("old".utf8)))

        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.none],
            ofItemAtPath: file.path
        )
        var wrongValues = URLResourceValues()
        wrongValues.isExcludedFromBackup = true
        try file.setResourceValues(wrongValues)

        XCTAssertThrowsError(
            try ProtectedFilePolicyV1.verify(.database, at: file)
        ) { error in
            XCTAssertEqual(
                error as? ProtectedFilePolicyError,
                .resourceValueMismatch
            )
        }

        try ProtectedFilePolicyV1.applyAndVerify(.database, at: file)
        try assertResourceValues(.database, at: file)
    }

    func testRelativePathTraversalAndLinkEscapesFailClosed() throws {
        let root = try makeTemporaryRoot("confinement")
        defer { try? fileManager.removeItem(at: root) }
        let outside = root.deletingLastPathComponent()
            .appendingPathComponent("V9_02-outside-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: outside) }
        let outsideFile = outside.appendingPathComponent("payload")
        XCTAssertTrue(fileManager.createFile(atPath: outsideFile.path, contents: Data("outside".utf8)))

        for relativePath in [
            "../\(outside.lastPathComponent)/payload",
            "nested/../payload",
            "/absolute/payload",
            "\\absolute\\payload",
            "nested//payload",
            ".",
        ] {
            XCTAssertThrowsError(
                try ProtectedFilePolicyV1.applyAndVerify(
                    .stagingFile,
                    relativePath: relativePath,
                    within: root
                ),
                relativePath
            ) { error in
                XCTAssertEqual(
                    error as? ProtectedFilePolicyError,
                    .invalidRelativePath,
                    relativePath
                )
            }
        }

        let symlinkDirectory = root.appendingPathComponent("linked-directory", isDirectory: true)
        do {
            try fileManager.createSymbolicLink(
                at: symlinkDirectory,
                withDestinationURL: outside
            )
        } catch {
            throw XCTSkip("Symlink fixture unavailable: \(error)")
        }
        XCTAssertThrowsError(
            try ProtectedFilePolicyV1.applyAndVerify(
                .stagingFile,
                relativePath: "linked-directory/payload",
                within: root
            )
        ) { error in
            XCTAssertEqual(error as? ProtectedFilePolicyError, .symbolicLink)
        }

        let symlinkFile = root.appendingPathComponent("linked-file")
        do {
            try fileManager.createSymbolicLink(
                at: symlinkFile,
                withDestinationURL: outsideFile
            )
        } catch {
            throw XCTSkip("Symlink leaf fixture unavailable: \(error)")
        }
        XCTAssertThrowsError(
            try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: symlinkFile)
        ) { error in
            XCTAssertEqual(error as? ProtectedFilePolicyError, .symbolicLink)
        }
    }

    func testHardLinkedOwnedFileIsRejectedBeforeAttributeMutation() throws {
        let root = try makeTemporaryRoot("hard-link")
        defer { try? fileManager.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let linked = root.appendingPathComponent("linked")
        XCTAssertTrue(fileManager.createFile(atPath: source.path, contents: Data("source".utf8)))
        do {
            try fileManager.linkItem(at: source, to: linked)
        } catch {
            throw XCTSkip("Hard-link fixture unavailable: \(error)")
        }

        XCTAssertThrowsError(
            try ProtectedFilePolicyV1.verify(.stagingFile, at: linked)
        ) { error in
            XCTAssertEqual(error as? ProtectedFilePolicyError, .hardLink)
        }
        XCTAssertEqual(try Data(contentsOf: source), Data("source".utf8))
    }

    func testMissingInvalidTypeAndAuthorityOrderingFailClosed() throws {
        let root = try makeTemporaryRoot("typed-failures")
        defer { try? fileManager.removeItem(at: root) }

        let missing = root.appendingPathComponent("missing")
        XCTAssertThrowsError(
            try ProtectedFilePolicyV1.verify(.stagingFile, at: missing)
        ) { error in
            XCTAssertEqual(error as? ProtectedFilePolicyError, .missing)
        }

        let directory = root.appendingPathComponent("directory", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        XCTAssertThrowsError(
            try ProtectedFilePolicyV1.verify(.stagingFile, at: directory)
        ) { error in
            XCTAssertEqual(error as? ProtectedFilePolicyError, .invalidType)
        }

        let regularFile = root.appendingPathComponent("regular")
        XCTAssertTrue(fileManager.createFile(atPath: regularFile.path, contents: Data()))
        XCTAssertThrowsError(
            try ProtectedFilePolicyV1.verify(.durableDirectory, at: regularFile)
        ) { error in
            XCTAssertEqual(error as? ProtectedFilePolicyError, .invalidType)
        }

        let stableFile = root.appendingPathComponent("stable")
        XCTAssertTrue(fileManager.createFile(atPath: stableFile.path, contents: Data("stable".utf8)))
        var stableAuthorityCalls = 0
        try ProtectedFilePolicyV1.applyAndVerify(
            .stagingFile,
            at: stableFile,
            authorityCheck: { stableAuthorityCalls += 1 }
        )
        XCTAssertEqual(stableAuthorityCalls, 3)

        let replacedFile = root.appendingPathComponent("replaced")
        XCTAssertTrue(fileManager.createFile(atPath: replacedFile.path, contents: Data("first".utf8)))
        var replacementAuthorityCalls = 0
        XCTAssertThrowsError(
            try ProtectedFilePolicyV1.applyAndVerify(
                .stagingFile,
                at: replacedFile,
                authorityCheck: {
                    replacementAuthorityCalls += 1
                    if replacementAuthorityCalls == 2 {
                        try fileManager.removeItem(at: replacedFile)
                        guard fileManager.createFile(
                            atPath: replacedFile.path,
                            contents: Data("second".utf8)
                        ) else {
                            throw ProtectedFilePolicyError.invalidURL
                        }
                    }
                }
            )
        ) { error in
            XCTAssertEqual(error as? ProtectedFilePolicyError, .identityChanged)
        }
        XCTAssertEqual(replacementAuthorityCalls, 2)
    }

    func testJournalMediaReportAndDiagnosticsKindsUseTargetedPolicy() throws {
        let root = try makeTemporaryRoot("targeted-kinds")
        defer { try? fileManager.removeItem(at: root) }
        let cases: [(OwnedFileKindV1, String)] = [
            (.journal, "journal"),
            (.journalTemporary, "journal.tmp"),
            (.mediaOriginal, "original.bin"),
            (.mediaThumbnail, "thumbnail.bin"),
            (.reportSnapshot, "report.json"),
            (.reportPDF, "report.pdf"),
            (.diagnostics, "diagnostics.json"),
            (.commerceEntitlementCache, "entitlements.json"),
        ]

        for (kind, name) in cases {
            let url = root.appendingPathComponent(name)
            XCTAssertTrue(fileManager.createFile(atPath: url.path, contents: Data(name.utf8)))
            try ProtectedFilePolicyV1.applyAndVerify(kind, at: url)
            try ProtectedFilePolicyV1.verify(kind, at: url)
            try assertResourceValues(kind, at: url)
        }
    }

    func testOptionalSQLiteSidecarVerificationRejectsDanglingLinks() throws {
        let root = try makeTemporaryRoot("sidecar-link")
        defer { try? fileManager.removeItem(at: root) }
        let sidecar = root.appendingPathComponent("model.sqlite-wal")
        let absentTarget = root.appendingPathComponent("absent-target")
        do {
            try fileManager.createSymbolicLink(
                at: sidecar,
                withDestinationURL: absentTarget
            )
        } catch {
            throw XCTSkip("Symlink fixture unavailable: \(error)")
        }

        XCTAssertThrowsError(
            try ProtectedFilePolicyV1.verifyIfPresent(.databaseWAL, at: sidecar)
        ) { error in
            XCTAssertEqual(error as? ProtectedFilePolicyError, .symbolicLink)
        }
    }

    func testProtectedDataFailureSeamIsTypedWithoutPhysicalDeviceClaim() {
        XCTAssertTrue(
            ProtectedFilePolicyV1.isProtectedDataUnavailable(
                ProtectedFilePolicyError.protectedDataUnavailable
            )
        )
        XCTAssertTrue(
            ProtectedFilePolicyV1.isProtectedDataUnavailable(
                NSError(domain: NSPOSIXErrorDomain, code: EACCES)
            )
        )
        XCTAssertFalse(
            ProtectedFilePolicyV1.isProtectedDataUnavailable(
                NSError(domain: NSPOSIXErrorDomain, code: ENOENT)
            )
        )
    }

    @MainActor
    func testStoreGenerationBootstrapSaveAndProtectedResourceReadback() throws {
        let root = try makeTemporaryRoot("store-bootstrap")
        defer { try? fileManager.removeItem(at: root) }
        let factory = StoreGenerationFactory(applicationSupportURL: root)
        let session = try factory.openOrBootstrapCurrent()
        let siteID = UUID(uuidString: "A0000000-0000-0000-0000-000000000901")!
        session.modelContext.insert(
            Site(
                id: siteID,
                label: "Protected Site",
                timeZoneID: "UTC",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
        try session.modelContext.save()
        try session.reproofAfterSave()

        let dataRoot = root.appendingPathComponent("FieldEvidenceData", isDirectory: true)
        let currentPointer = dataRoot.appendingPathComponent("current.json")
        let retiredPointer = dataRoot.appendingPathComponent("retired.json")
        let model = session.generationRootURL.appendingPathComponent("model.sqlite")

        try ProtectedFilePolicyV1.verify(.generationPointer, at: currentPointer)
        try ProtectedFilePolicyV1.verify(.generationPointer, at: retiredPointer)
        try ProtectedFilePolicyV1.verify(.database, at: model)
        for (suffix, kind) in [
            ("-wal", OwnedFileKindV1.databaseWAL),
            ("-shm", OwnedFileKindV1.databaseSHM),
        ] as [(String, OwnedFileKindV1)] {
            let sidecar = session.generationRootURL.appendingPathComponent("model.sqlite\(suffix)")
            try ProtectedFilePolicyV1.verifyIfPresent(kind, at: sidecar)
        }

        XCTAssertEqual(try factory.currentGenerationID(), session.generationID)
        let reopened = try factory.openOrBootstrapCurrent()
        let sites = try reopened.modelContext.fetch(FetchDescriptor<Site>())
        XCTAssertEqual(sites.filter { $0.id == siteID }.count, 1)
        try ProtectedFilePolicyV1.verify(
            .database,
            at: reopened.generationRootURL.appendingPathComponent("model.sqlite")
        )
        try ProtectedFilePolicyV1.verifyIfPresent(
            .databaseWAL,
            at: reopened.generationRootURL.appendingPathComponent("model.sqlite-wal")
        )
        try ProtectedFilePolicyV1.verifyIfPresent(
            .databaseSHM,
            at: reopened.generationRootURL.appendingPathComponent("model.sqlite-shm")
        )
    }

    @MainActor
    func testAutomaticPostSaveReproofRecordsAndSurfacesFailureSynchronously() throws {
        let root = try makeTemporaryRoot("post-save-reproof")
        defer { try? fileManager.removeItem(at: root) }
        let session = try StoreGenerationFactory(
            applicationSupportURL: root
        ).openOrBootstrapCurrent()
        let unexpected = session.generationRootURL.appendingPathComponent("unexpected")
        XCTAssertTrue(
            fileManager.createFile(
                atPath: unexpected.path,
                contents: Data("unexpected".utf8)
            )
        )

        session.modelContext.insert(
            Site(
                id: UUID(uuidString: "A0000000-0000-0000-0000-000000000902")!,
                label: "Post-save Reproof",
                timeZoneID: "UTC",
                createdAt: Date(timeIntervalSince1970: 1_700_000_001)
            )
        )
        try session.modelContext.save()

        XCTAssertFalse(session.modelContext.autosaveEnabled)
        XCTAssertThrowsError(try session.reproofAfterSave()) { error in
            XCTAssertEqual(
                error as? StoreGenerationFailure,
                .dataPointerInvalid
            )
        }
    }
}

private extension V9_02FileAuthorityTests {
    func makeTemporaryRoot(_ label: String) throws -> URL {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "V9_02-\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return root
    }

    func assertResourceValues(
        _ kind: OwnedFileKindV1,
        at url: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let values = try url.resourceValues(forKeys: [
            .fileProtectionKey,
            .isExcludedFromBackupKey,
        ])
        XCTAssertEqual(values.fileProtection, .complete, kind.rawValue, file: file, line: line)
        XCTAssertEqual(
            values.isExcludedFromBackup,
            ProtectedFilePolicyV1.isExcludedFromBackup(for: kind),
            kind.rawValue,
            file: file,
            line: line
        )
    }
}
private final class C49WorkResourceFileAuthorityBoundaryTests: XCTestCase {
    func testWorkResourceCoreDoesNotClaimLiveStockFileAuthority() {
        XCTAssertFalse(C49WorkResourceContractBoundaryV1.liveInventoryReference)
        XCTAssertTrue(C49WorkResourceLifecycleBoundaryV1.liveInventoryLookupIsForbidden)
        XCTAssertTrue(C49WorkResourceLifecycleBoundaryV1.untrackedMaterialRemainsValid)
    }
}


private final class C50IncumbentFileExchangeFileAuthorityBoundaryTests: XCTestCase {
    func testCopiedSourceMappingScratchAndQuarantineAreProtectedAndBackupExcluded() {
        XCTAssertTrue(C50IncumbentFileExchangeProtectedFileBoundaryV1.validate())
        XCTAssertFalse(C50IncumbentFileExchangeProtectedFileBoundaryV1.persistsSecurityScopedBookmarks)
        XCTAssertFalse(C50IncumbentFileExchangeProtectedFileBoundaryV1.externalSourceAndExportFilesAreAppOwned)
        XCTAssertTrue(C50IncumbentFileExchangeKernelBackupEnrollmentV1.validate())
        XCTAssertTrue(C50IncumbentFileExchangeBackupRestoreServiceBoundaryV1.validate(mode: .replaceExisting))
        XCTAssertTrue(C50IncumbentFileExchangeBackupRestoreServiceBoundaryV1.validate(mode: .clone))
        XCTAssertTrue(C50IncumbentFileExchangeBackupRestoreServiceBoundaryV1.validate(mode: .fork))
        XCTAssertTrue(C50IncumbentFileExchangeDeletionLedgerBoundaryV1.validate())
    }

    func testInfoPlistDeclaresDisabledPortWithoutProviderTypeOrBookmarkClaim() throws {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "FieldEvidenceIncumbentFileAdapterStatus") as? String,
            "DISABLED_NO_SELECTED_PROFILE"
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "FieldEvidenceIncumbentFileAdapterDeclaresProviderType") as? Bool,
            false
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "FieldEvidenceIncumbentFileAdapterPersistsSecurityBookmarks") as? Bool,
            false
        )
        let declarations = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]]
        )
        let identifiers = Set(declarations.compactMap { $0["UTTypeIdentifier"] as? String })
        XCTAssertEqual(identifiers.count, 3)
        XCTAssertFalse(identifiers.contains { $0.localizedCaseInsensitiveContains("incumbent") })
    }

    func testBackupRestoreAndDeletionBoundariesPreserveOnlyExistingCanonicalOwners() {
        XCTAssertTrue(C50IncumbentFileExchangeBackupBoundaryV1.validate())
        XCTAssertEqual(C50IncumbentFileExchangeBackupBoundaryV1.profileContractSchemaVersion, 1)
        XCTAssertEqual(C50IncumbentFileExchangeBackupBoundaryV1.selectionContractSchemaVersion, 1)
        XCTAssertTrue(C50IncumbentFileExchangeBackupImportBoundaryV1.validate())
        XCTAssertTrue(C50IncumbentFileExchangeReplacementRestoreRuleV1.validate())
        XCTAssertFalse(C50IncumbentFileExchangeBackupEncoderBoundaryV1.encodesSourceScratchOrQuarantine)
        XCTAssertFalse(C50IncumbentFileExchangeBackupDecoderBoundaryV1.acceptsSourceScratchOrQuarantine)
        XCTAssertEqual(C50IncumbentFileExchangePackageValidationBoundaryV1.allowedAdapterMemberCount, 0)
        XCTAssertFalse(C50IncumbentFileExchangeBackupExportBoundaryV1.exportsSecurityBookmarksOrExternalPaths)
        XCTAssertFalse(C50IncumbentFileExchangeBackupImportServiceBoundaryV1.backupParserIsIncumbentFileParser)
        XCTAssertTrue(C50IncumbentFileExchangeWholeSignDeletionRuleV1.canonicalImportedRowsFollowTheirSubjectOwners)
        XCTAssertTrue(C50IncumbentFileExchangeWholeSignDeletionServiceBoundaryV1.createsNoAdapterDeletionReceipt)
        XCTAssertTrue(C50IncumbentFileExchangeEraseIntentBoundaryV1.clearsAppOwnedQuarantine)
        XCTAssertTrue(C50IncumbentFileExchangeEraseIntentStoreBoundaryV1.appOwnedScratchParticipatesInEraseInventory)
        XCTAssertTrue(C50IncumbentFileExchangeEraseAllBoundaryV1.removesAppOwnedScratch)
        XCTAssertEqual(C50IncumbentFileExchangeKernelDeletionEnrollmentV1.canonicalRowRegistrationCount, 0)
        XCTAssertFalse(C50IncumbentFileExchangeDeletionLedgerStoreBoundaryV1.persistsSourceOrQuarantineDigests)
        XCTAssertTrue(C50IncumbentFileExchangeOrphanCleanupBoundaryV1.externalSourceAndExportFilesAreNeverCleanupTargets)
    }
}

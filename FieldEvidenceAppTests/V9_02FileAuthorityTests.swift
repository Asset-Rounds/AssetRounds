import Darwin
import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

private enum C52ServiceRequestBoundary_V9_02FileAuthorityTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

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
            .generationLeaseDirectory,
            .generationLeaseControl,
            .generationLeaseControlTemporary,
            .generationLeaseOwnerLock,
            .journal,
            .journalTemporary,
            .sceneNavigation,
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

        XCTAssertEqual(OwnedFileKindV1.allCases.count, 31)
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

    #if DEBUG && os(iOS) && targetEnvironment(simulator)
    func testSimulatorDiagnosticClassifierRejectsEveryNonexactFact() throws {
        for kind in OwnedFileKindV1.allCases {
            let disposition = ProtectedFilePolicyV1.disposition(for: kind)
            func facts(
                capability: Bool? = false,
                url: String = "completeUntilFirstUserAuthentication",
                manager: String = "completeUntilFirstUserAuthentication",
                backup: Bool? = nil,
                directory: Bool? = nil
            ) -> ProtectedFilePolicyV1.DirectoryProtectionReadback {
                .init(urlProtection: url, fileManagerProtection: manager,
                    backupExcluded: backup ?? disposition.isExcludedFromBackup,
                    isDirectory: directory ?? disposition.expectsDirectory,
                    volumeSupportsProtection: capability)
            }
            func allowed(_ before: Bool?, _ after: ProtectedFilePolicyV1.DirectoryProtectionReadback,
                         request: Bool = true, identity: Bool = true) -> Bool {
                ProtectedFilePolicyV1.simulatorDiagnosticAllows(capabilityBefore: before,
                    after: after, disposition: disposition,
                    successfulCompleteRequest: request, identityUnchanged: identity)
            }
            XCTAssertTrue(allowed(false, facts()), kind.rawValue)
            for capability in [nil, true] as [Bool?] {
                XCTAssertFalse(allowed(capability, facts()), kind.rawValue)
                XCTAssertFalse(allowed(false, facts(capability: capability)), kind.rawValue)
            }
            for protection in ["complete", "completeUnlessOpen", "none", "unknown", "other", "readError"] {
                XCTAssertFalse(allowed(false, facts(url: protection)), protection)
                // FileManager remains a retained diagnostic observation. The
                // approved predicate uses the separately reconstructed URL.
                XCTAssertTrue(allowed(false, facts(manager: protection)), protection)
            }
            // Even the admitted fallback is denied on a supported volume.
            for protection in ["completeUntilFirstUserAuthentication", "completeUnlessOpen", "none", "unknown"] {
                XCTAssertFalse(allowed(true, facts(capability: true, url: protection, manager: protection)))
            }
            XCTAssertFalse(allowed(false, facts(backup: !disposition.isExcludedFromBackup)))
            XCTAssertFalse(allowed(false, facts(directory: !disposition.expectsDirectory)))
            XCTAssertFalse(allowed(false, facts(), request: false))
            XCTAssertFalse(allowed(false, facts(), identity: false))
            for missing in [
                ProtectedFilePolicyV1.DirectoryProtectionReadback(
                    urlProtection: "completeUntilFirstUserAuthentication",
                    fileManagerProtection: "completeUntilFirstUserAuthentication",
                    backupExcluded: nil, isDirectory: disposition.expectsDirectory,
                    volumeSupportsProtection: false),
                ProtectedFilePolicyV1.DirectoryProtectionReadback(
                    urlProtection: "completeUntilFirstUserAuthentication",
                    fileManagerProtection: "completeUntilFirstUserAuthentication",
                    backupExcluded: disposition.isExcludedFromBackup, isDirectory: nil,
                    volumeSupportsProtection: false),
            ] { XCTAssertFalse(allowed(false, missing)) }
        }

        // Exercise the actual shared writer with concurrent records larger
        // than the original diagnostic records. Test text stays in this
        // disposable file and never becomes a protection-disposition event.
        let root = try makeTemporaryRoot("diagnostic-output")
        defer { try? fileManager.removeItem(at: root) }
        let output = root.appendingPathComponent("concurrent-records.txt")
        XCTAssertTrue(fileManager.createFile(atPath: output.path, contents: nil))
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let writer = ProtectedFileDiagnosticWriterV1(fileHandle: handle)
        let records = (0..<64).map { index in
            "record-\(index):" + String(repeating: "0123456789abcdef", count: 2_048) + "\n"
        }
        DispatchQueue.concurrentPerform(iterations: records.count) { index in
            writer.write(records[index])
        }
        try handle.synchronize()
        let actual = try String(contentsOf: output, encoding: .utf8)
        let lines = actual.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.count, records.count + 1)
        XCTAssertTrue(lines.last?.isEmpty == true)
        XCTAssertEqual(Set(lines.dropLast().map(String.init)),
                       Set(records.map { String($0.dropLast()) }))
    }

    func testSimulatorUnsupportedFileAndDirectoryRemainExplicitAcrossVerification() throws {
        let root = try makeTemporaryRoot("simulator-unsupported")
        defer { try? fileManager.removeItem(at: root) }
        for kind in [OwnedFileKindV1.database, .generationLeaseDirectory] {
            let disposition = ProtectedFilePolicyV1.disposition(for: kind)
            let item = root.appendingPathComponent(kind.rawValue, isDirectory: disposition.expectsDirectory)
            if disposition.expectsDirectory {
                try fileManager.createDirectory(at: item, withIntermediateDirectories: false)
            } else {
                XCTAssertTrue(fileManager.createFile(atPath: item.path, contents: Data("unchanged".utf8)))
            }
            let before = try fileIdentity(at: item)
            let applied = try ProtectedFilePolicyV1.applyAndVerify(kind, at: item)
            XCTAssertEqual(applied, .simulatorFileProtectionUnsupported)
            try assertVerificationResourceValues(kind, at: item, result: applied)
            let verified = try ProtectedFilePolicyV1.verify(kind, at: URL(fileURLWithPath: item.path))
            XCTAssertEqual(verified, .simulatorFileProtectionUnsupported)
            try assertVerificationResourceValues(kind, at: item, result: verified)
            try ProtectedFilePolicyV1.verifyIfPresent(kind, at: item)
            try ProtectedFilePolicyV1.verifyIfPresent(kind, relativePath: kind.rawValue, within: root)
            XCTAssertEqual(try fileIdentity(at: item), before)
            if disposition.expectsDirectory {
                XCTAssertEqual(try directoryContents(at: item), [])
            } else {
                XCTAssertEqual(try Data(contentsOf: item), Data("unchanged".utf8))
            }
        }
        try ProtectedFilePolicyV1.verifyIfPresent(.databaseWAL, at: root.appendingPathComponent("absent"))
        XCTAssertFalse(fileManager.fileExists(atPath: root.appendingPathComponent("absent").path))
    }
    #endif

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

            let applied = try ProtectedFilePolicyV1.applyAndVerify(kind, at: item)
            XCTAssertEqual(try ProtectedFilePolicyV1.verify(kind, at: item), applied)
            try assertVerificationResourceValues(kind, at: item, result: applied)
        }
    }

    func testWrongResourceValuesAreRepairedAndVerified() throws {
        let root = try makeTemporaryRoot("repair")
        defer { try? fileManager.removeItem(at: root) }
        var file = root.appendingPathComponent("model.sqlite")
        XCTAssertTrue(fileManager.createFile(atPath: file.path, contents: Data("old".utf8)))
        var tracePhase = "wrongProtectionSet"
        var traceCompleted = false
        defer {
            if !traceCompleted {
                traceResourceReadback(
                    test: "wrongResourceValuesAreRepairedAndVerified",
                    phase: tracePhase,
                    at: file
                )
                runFailureOnlyProtectionProbe(in: root)
                runFailureOnlyDirectoryProtectionProbe(in: root)
            }
        }

        tracePhase = "wrongProtectionSet"
        try setFileProtection(.completeUntilFirstUserAuthentication, at: file)
        var wrongValues = URLResourceValues()
        wrongValues.isExcludedFromBackup = true
        tracePhase = "wrongBackupSet"
        try file.setResourceValues(wrongValues)
        tracePhase = "wrongAttributeAssert"
        try assertResourceValues(
            .database,
            at: file,
            protection: .completeUntilFirstUserAuthentication,
            isExcludedFromBackup: true
        )

        tracePhase = "wrongAttributeVerify"
        XCTAssertThrowsError(
            try ProtectedFilePolicyV1.verify(.database, at: file)
        ) { error in
            XCTAssertEqual(
                error as? ProtectedFilePolicyError,
                .resourceValueMismatch
            )
        }

        tracePhase = "repairedApply"
        let repairedFile = try ProtectedFilePolicyV1.applyAndVerify(.database, at: file)
        tracePhase = "repairedAttributeAssert"
        try assertVerificationResourceValues(.database, at: file, result: repairedFile)

        let directory = root.appendingPathComponent(
            "generation-lease-directory",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        let directoryIdentity = try fileIdentity(at: directory)
        let expectedDirectoryContents = try directoryContents(at: directory)
        XCTAssertTrue(expectedDirectoryContents.isEmpty)
        tracePhase = "directoryApply"
        let repairedDirectory = try ProtectedFilePolicyV1.applyAndVerify(
            .generationLeaseDirectory,
            at: directory
        )
        tracePhase = "directoryVerify"
        XCTAssertEqual(try ProtectedFilePolicyV1.verify(.generationLeaseDirectory, at: directory),
            repairedDirectory)
        tracePhase = "directoryIdentityAndContents"
        XCTAssertEqual(try fileIdentity(at: directory), directoryIdentity)
        XCTAssertEqual(try directoryContents(at: directory), expectedDirectoryContents)
        tracePhase = "directoryAttributeAssert"
        try assertVerificationResourceValues(
            .generationLeaseDirectory,
            at: directory,
            result: repairedDirectory
        )
        traceCompleted = true
    }

    func testCachedValidResourceValuesCannotHideLaterPhysicalAttributeChanges() throws {
        let root = try makeTemporaryRoot("cached-resource-values")
        defer { try? fileManager.removeItem(at: root) }
        let file = root.appendingPathComponent("model.sqlite")
        XCTAssertTrue(fileManager.createFile(atPath: file.path, contents: Data("protected".utf8)))
        var tracePhase = "initialApply"
        var traceCompleted = false
        defer {
            if !traceCompleted {
                traceResourceReadback(
                    test: "cachedValidResourceValuesCannotHideLaterPhysicalAttributeChanges",
                    phase: tracePhase,
                    at: file
                )
                runFailureOnlyProtectionProbe(in: root)
                runFailureOnlyDirectoryProtectionProbe(in: root)
            }
        }
        tracePhase = "initialApply"
        let initialResult = try ProtectedFilePolicyV1.applyAndVerify(.database, at: file)
        try assertVerificationResourceValues(.database, at: file, result: initialResult)
        tracePhase = "initialReadback"
        _ = try file.resourceValues(forKeys: [.fileProtectionKey, .isExcludedFromBackupKey])
        tracePhase = "wrongProtectionSet"
        try setFileProtection(.none, at: file)
        tracePhase = "wrongProtectionAssert"
        var independentlyChanged = URL(fileURLWithPath: file.path)
        independentlyChanged.removeAllCachedResourceValues()
        let changedProtection = try independentlyChanged.resourceValues(forKeys: [.fileProtectionKey]).fileProtection
        tracePhase = "wrongProtectionVerify"
        #if DEBUG && os(iOS) && targetEnvironment(simulator)
        if initialResult == .simulatorFileProtectionUnsupported
            && changedProtection == .completeUntilFirstUserAuthentication {
            // This volume did not apply the hostile protection request. Record the
            // unsupported fact; the independently changed backup below must still fail.
            let result = try ProtectedFilePolicyV1.verify(.database, at: file)
            XCTAssertEqual(result, .simulatorFileProtectionUnsupported)
            try assertVerificationResourceValues(.database, at: file, result: result)
        } else {
            XCTAssertEqual(changedProtection, URLFileProtection.none)
            XCTAssertThrowsError(try ProtectedFilePolicyV1.verify(.database, at: file)) { error in
                XCTAssertEqual(error as? ProtectedFilePolicyError, .resourceValueMismatch)
            }
        }
        #else
        XCTAssertEqual(changedProtection, URLFileProtection.none)
        XCTAssertThrowsError(try ProtectedFilePolicyV1.verify(.database, at: file)) { error in
            XCTAssertEqual(error as? ProtectedFilePolicyError, .resourceValueMismatch)
        }
        #endif
        tracePhase = "repairedApplyAfterProtection"
        let repairedProtection = try ProtectedFilePolicyV1.applyAndVerify(.database, at: file)
        tracePhase = "repairedAssertAfterProtection"
        try assertVerificationResourceValues(.database, at: file, result: repairedProtection)
        tracePhase = "secondReadback"
        _ = try file.resourceValues(forKeys: [.fileProtectionKey, .isExcludedFromBackupKey])
        var anotherURL = URL(fileURLWithPath: file.path)
        var wrongValues = URLResourceValues()
        wrongValues.isExcludedFromBackup = true
        tracePhase = "wrongBackupSet"
        try anotherURL.setResourceValues(wrongValues)
        tracePhase = "wrongBackupAssert"
        try assertResourceValues(
            .database,
            at: file,
            protection: repairedProtection == .verifiedComplete ? .complete : .completeUntilFirstUserAuthentication,
            isExcludedFromBackup: true
        )
        tracePhase = "wrongBackupVerify"
        XCTAssertThrowsError(try ProtectedFilePolicyV1.verify(.database, at: file)) { error in
            XCTAssertEqual(error as? ProtectedFilePolicyError, .resourceValueMismatch)
        }
        tracePhase = "repairedApplyAfterBackup"
        let repairedBackup = try ProtectedFilePolicyV1.applyAndVerify(.database, at: file)
        tracePhase = "repairedAssertAfterBackup"
        try assertVerificationResourceValues(.database, at: file, result: repairedBackup)
        tracePhase = "contentIntegrityRead"
        XCTAssertEqual(try Data(contentsOf: file), Data("protected".utf8))
        traceCompleted = true
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
            let applied = try ProtectedFilePolicyV1.applyAndVerify(kind, at: url)
            XCTAssertEqual(try ProtectedFilePolicyV1.verify(kind, at: url), applied)
            try assertVerificationResourceValues(kind, at: url, result: applied)
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
                NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
            )
        )
        XCTAssertFalse(
            ProtectedFilePolicyV1.isProtectedDataUnavailable(
                NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))
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
    enum FailureOnlyProtectionProbeWriter: String {
        case url
        case fileManager
    }

    struct FailureOnlyProtectionProbeReadback {
        let protection: String
        let protectionKnown: Bool
        let backupKnown: Bool
        let backupExcluded: Bool
    }

    enum FailureOnlyDirectoryCreationRoute: String {
        case urlProtection = "urlProtection"
        case fileManagerProtection = "fileManagerProtection"
        case creationAttributes = "creationAttributes"
    }

    struct FailureOnlyDirectoryURLReadback {
        let protection: String
        let backup: String
        let volumeProtection: String
        let shape: String
    }

    struct FailureOnlyDirectoryFileManagerReadback {
        let protection: String
        let shape: String
    }

    struct FileAuthorityIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
    }

    func runFailureOnlyProtectionProbe(in root: URL) {
        let cases: [(String, String, FailureOnlyProtectionProbeWriter)] = [
            ("model-url", "probe-model.sqlite", .url),
            ("model-fileManager", "probe-model.sqlite", .fileManager),
            ("control-url", "probe-control.bin", .url),
            ("control-fileManager", "probe-control.bin", .fileManager),
        ]
        for (name, basename, writer) in cases {
            let directory = root.appendingPathComponent(
                "file-authority-probe-\(name)",
                isDirectory: true
            )
            let file = directory.appendingPathComponent(basename)
            var setup = "ok"
            do {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: false
                )
                guard fileManager.createFile(atPath: file.path, contents: Data()) else {
                    setup = "typedError"
                    emitFailureOnlyProtectionProbe(
                        name: name,
                        writer: writer,
                        stage: "default",
                        setup: setup,
                        write: "notAttempted",
                        at: file
                    )
                    continue
                }
            } catch {
                setup = "typedError"
                emitFailureOnlyProtectionProbe(
                    name: name,
                    writer: writer,
                    stage: "default",
                    setup: setup,
                    write: "notAttempted",
                    at: file
                )
                continue
            }

            emitFailureOnlyProtectionProbe(
                name: name,
                writer: writer,
                stage: "default",
                setup: setup,
                write: "notAttempted",
                at: file
            )
            let wrongWrite = writeFailureOnlyProtection(
                .completeUntilFirstUserAuthentication,
                with: writer,
                at: file
            )
            emitFailureOnlyProtectionProbe(
                name: name,
                writer: writer,
                stage: "wrongProtection",
                setup: setup,
                write: wrongWrite,
                at: file
            )
            let completeWrite = writeFailureOnlyProtection(
                .complete,
                with: writer,
                at: file
            )
            emitFailureOnlyProtectionProbe(
                name: name,
                writer: writer,
                stage: "completeRepair",
                setup: setup,
                write: completeWrite,
                at: file
            )
        }
    }

    func runFailureOnlyDirectoryProtectionProbe(in root: URL) {
        let cases: [(String, FailureOnlyDirectoryCreationRoute)] = [
            ("excluded-url", .urlProtection),
            ("excluded-fileManager", .fileManagerProtection),
            ("excluded-creationAttributes", .creationAttributes),
        ]
        for (name, route) in cases {
            let directory = root.appendingPathComponent(
                "file-authority-directory-probe-\(name)",
                isDirectory: true
            )
            let setup: String
            do {
                switch route {
                case .urlProtection, .fileManagerProtection:
                    try fileManager.createDirectory(
                        at: directory,
                        withIntermediateDirectories: false
                    )
                case .creationAttributes:
                    try fileManager.createDirectory(
                        atPath: directory.path,
                        withIntermediateDirectories: false,
                        attributes: [.protectionKey: FileProtectionType.complete]
                    )
                }
                setup = "ok"
            } catch {
                emitFailureOnlyDirectoryProtectionProbe(
                    name: name,
                    route: route,
                    stage: "setup",
                    setup: "typedError",
                    protectionWrite: "notAttempted",
                    backupWrite: "notAttempted",
                    at: directory
                )
                continue
            }

            emitFailureOnlyDirectoryProtectionProbe(
                name: name,
                route: route,
                stage: route == .creationAttributes ? "afterCreation" : "default",
                setup: setup,
                protectionWrite: route == .creationAttributes ? "creationAttribute" : "notAttempted",
                backupWrite: "notAttempted",
                at: directory
            )

            var protectionWrite = route == .creationAttributes ? "creationAttribute" : "notAttempted"
            switch route {
            case .urlProtection:
                protectionWrite = writeFailureOnlyProtection(
                    .complete,
                    with: .url,
                    at: directory
                )
            case .fileManagerProtection:
                protectionWrite = writeFailureOnlyProtection(
                    .complete,
                    with: .fileManager,
                    at: directory
                )
            case .creationAttributes:
                break
            }
            if route != .creationAttributes {
                emitFailureOnlyDirectoryProtectionProbe(
                    name: name,
                    route: route,
                    stage: "afterProtection",
                    setup: setup,
                    protectionWrite: protectionWrite,
                    backupWrite: "notAttempted",
                    at: directory
                )
            }

            let backupWrite = writeFailureOnlyDirectoryBackup(at: directory)
            emitFailureOnlyDirectoryProtectionProbe(
                name: name,
                route: route,
                stage: "afterBackup",
                setup: setup,
                protectionWrite: protectionWrite,
                backupWrite: backupWrite,
                at: directory
            )
        }
    }

    func writeFailureOnlyDirectoryBackup(at url: URL) -> String {
        do {
            var mutationURL = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try mutationURL.setResourceValues(values)
            return "ok"
        } catch {
            return "typedError"
        }
    }

    func emitFailureOnlyDirectoryProtectionProbe(
        name: String,
        route: FailureOnlyDirectoryCreationRoute,
        stage: String,
        setup: String,
        protectionWrite: String,
        backupWrite: String,
        at url: URL
    ) {
        let current = failureOnlyDirectoryURLReadback(at: url, independentlyConstructed: false)
        let independent = failureOnlyDirectoryURLReadback(at: url, independentlyConstructed: true)
        let fileManager = failureOnlyDirectoryFileManagerReadback(at: url)
        print(
            "V9_02_DIRECTORY_PROTECTION_PROBE case=\(name) route=\(route.rawValue) "
                + "stage=\(stage) setup=\(setup) protectionWrite=\(protectionWrite) "
                + "backupWrite=\(backupWrite) currentProtection=\(current.protection) "
                + "currentBackup=\(current.backup) currentVolumeProtection=\(current.volumeProtection) "
                + "currentShape=\(current.shape) independentProtection=\(independent.protection) "
                + "independentBackup=\(independent.backup) "
                + "independentVolumeProtection=\(independent.volumeProtection) "
                + "independentShape=\(independent.shape) "
                + "fileManagerProtection=\(fileManager.protection) "
                + "fileManagerShape=\(fileManager.shape)"
        )
    }

    func failureOnlyDirectoryURLReadback(
        at url: URL,
        independentlyConstructed: Bool
    ) -> FailureOnlyDirectoryURLReadback {
        var reader = independentlyConstructed ? URL(fileURLWithPath: url.path) : url
        reader.removeAllCachedResourceValues()
        do {
            let values = try reader.resourceValues(forKeys: [
                .fileProtectionKey,
                .isExcludedFromBackupKey,
                .volumeSupportsFileProtectionKey,
                .isDirectoryKey,
            ])
            return FailureOnlyDirectoryURLReadback(
                protection: failureOnlyProtectionCategory(values.fileProtection),
                backup: failureOnlyBooleanCategory(values.isExcludedFromBackup),
                volumeProtection: failureOnlyBooleanCategory(values.allValues[.volumeSupportsFileProtectionKey] as? Bool),
                shape: failureOnlyDirectoryShapeCategory(values.isDirectory)
            )
        } catch {
            return FailureOnlyDirectoryURLReadback(
                protection: "readError",
                backup: "readError",
                volumeProtection: "readError",
                shape: "readError"
            )
        }
    }

    func failureOnlyDirectoryFileManagerReadback(
        at url: URL
    ) -> FailureOnlyDirectoryFileManagerReadback {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let protection = attributes[.protectionKey] as? FileProtectionType
            let type = attributes[.type] as? FileAttributeType
            return FailureOnlyDirectoryFileManagerReadback(
                protection: failureOnlyProtectionCategory(protection),
                shape: type == nil ? "unknown" : (type == .typeDirectory ? "directory" : "other")
            )
        } catch {
            return FailureOnlyDirectoryFileManagerReadback(
                protection: "readError",
                shape: "readError"
            )
        }
    }

    func failureOnlyBooleanCategory(_ value: Bool?) -> String {
        guard let value else { return "unknown" }
        return value ? "true" : "false"
    }

    func failureOnlyDirectoryShapeCategory(_ isDirectory: Bool?) -> String {
        guard let isDirectory else { return "unknown" }
        return isDirectory ? "directory" : "other"
    }

    func writeFailureOnlyProtection(
        _ protection: URLFileProtection,
        with writer: FailureOnlyProtectionProbeWriter,
        at url: URL
    ) -> String {
        do {
            switch writer {
            case .url:
                try (url as NSURL).setResourceValue(
                    protection,
                    forKey: .fileProtectionKey
                )
            case .fileManager:
                let fileManagerProtection: FileProtectionType
                switch protection {
                case .complete:
                    fileManagerProtection = .complete
                case .completeUntilFirstUserAuthentication:
                    fileManagerProtection = .completeUntilFirstUserAuthentication
                case .none:
                    fileManagerProtection = .none
                default:
                    return "typedError"
                }
                try fileManager.setAttributes(
                    [.protectionKey: fileManagerProtection],
                    ofItemAtPath: url.path
                )
            }
            return "ok"
        } catch {
            return "typedError"
        }
    }

    func emitFailureOnlyProtectionProbe(
        name: String,
        writer: FailureOnlyProtectionProbeWriter,
        stage: String,
        setup: String,
        write: String,
        at url: URL
    ) {
        let urlReadback = failureOnlyURLReadback(at: url)
        let fileManagerReadback = failureOnlyFileManagerReadback(at: url)
        print(
            "V9_02_FILE_AUTHORITY_PROBE case=\(name) writer=\(writer.rawValue) "
                + "stage=\(stage) setup=\(setup) write=\(write) "
                + "urlProtection=\(urlReadback.protection) "
                + "urlProtectionKnown=\(urlReadback.protectionKnown) "
                + "fileManagerProtection=\(fileManagerReadback.protection) "
                + "fileManagerProtectionKnown=\(fileManagerReadback.protectionKnown) "
                + "backupKnown=\(urlReadback.backupKnown) "
                + "backupExcluded=\(urlReadback.backupExcluded) "
                + "backupMatchesDatabase=\(urlReadback.backupKnown && !urlReadback.backupExcluded)"
        )
    }

    func failureOnlyURLReadback(at url: URL) -> FailureOnlyProtectionProbeReadback {
        var freshURL = URL(fileURLWithPath: url.path)
        freshURL.removeAllCachedResourceValues()
        do {
            let values = try freshURL.resourceValues(forKeys: [
                .fileProtectionKey,
                .isExcludedFromBackupKey,
            ])
            return FailureOnlyProtectionProbeReadback(
                protection: failureOnlyProtectionCategory(values.fileProtection),
                protectionKnown: values.fileProtection != nil,
                backupKnown: values.isExcludedFromBackup != nil,
                backupExcluded: values.isExcludedFromBackup == true
            )
        } catch {
            return FailureOnlyProtectionProbeReadback(
                protection: "readError",
                protectionKnown: false,
                backupKnown: false,
                backupExcluded: false
            )
        }
    }

    func failureOnlyFileManagerReadback(
        at url: URL
    ) -> FailureOnlyProtectionProbeReadback {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let protection = attributes[.protectionKey] as? FileProtectionType
            return FailureOnlyProtectionProbeReadback(
                protection: failureOnlyProtectionCategory(protection),
                protectionKnown: protection != nil,
                backupKnown: false,
                backupExcluded: false
            )
        } catch {
            return FailureOnlyProtectionProbeReadback(
                protection: "readError",
                protectionKnown: false,
                backupKnown: false,
                backupExcluded: false
            )
        }
    }

    func failureOnlyProtectionCategory(
        _ protection: URLFileProtection?
    ) -> String {
        guard let protection else { return "unknown" }
        switch protection {
        case .complete:
            return "complete"
        case .completeUntilFirstUserAuthentication:
            return "completeUntilFirstUserAuthentication"
        case .none:
            return "none"
        default:
            return "other"
        }
    }

    func failureOnlyProtectionCategory(
        _ protection: FileProtectionType?
    ) -> String {
        guard let protection else { return "unknown" }
        switch protection {
        case .complete:
            return "complete"
        case .completeUntilFirstUserAuthentication:
            return "completeUntilFirstUserAuthentication"
        case .none:
            return "none"
        default:
            return "other"
        }
    }

    func traceResourceReadback(test: String, phase: String, at url: URL) {
        var freshURL = URL(fileURLWithPath: url.path)
        freshURL.removeAllCachedResourceValues()
        do {
            let values = try freshURL.resourceValues(forKeys: [
                .fileProtectionKey,
                .isExcludedFromBackupKey,
            ])
            print(
                "V9_02_FILE_AUTHORITY_TRACE test=\(test) phase=\(phase) "
                    + "protectionComplete=\(values.fileProtection == .complete) "
                    + "protectionKnown=\(values.fileProtection != nil) "
                    + "backupExcluded=\(values.isExcludedFromBackup == true) "
                    + "backupKnown=\(values.isExcludedFromBackup != nil)"
            )
        } catch {
            print("V9_02_FILE_AUTHORITY_TRACE test=\(test) phase=\(phase) readbackUnavailable")
        }
    }

    func setFileProtection(
        _ protection: URLFileProtection,
        at url: URL
    ) throws {
        let mutationURL = NSURL(fileURLWithPath: url.path)
        try mutationURL.setResourceValue(protection, forKey: .fileProtectionKey)
    }

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

    func fileIdentity(at url: URL) throws -> FileAuthorityIdentity {
        var information = stat()
        guard Darwin.lstat(url.path, &information) == 0 else {
            throw ProtectedFilePolicyError.invalidURL
        }
        return FileAuthorityIdentity(
            device: UInt64(information.st_dev),
            inode: UInt64(information.st_ino)
        )
    }

    func directoryContents(at url: URL) throws -> [String] {
        try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ).map(\.lastPathComponent).sorted()
    }

    func assertVerificationResourceValues(
        _ kind: OwnedFileKindV1,
        at url: URL,
        result: ProtectedFileVerificationDispositionV1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        if result == .verifiedComplete {
            try assertResourceValues(kind, at: url, file: file, line: line)
            return
        }
        #if DEBUG && os(iOS) && targetEnvironment(simulator)
        XCTAssertEqual(result, .simulatorFileProtectionUnsupported, file: file, line: line)
        var fresh = URL(fileURLWithPath: url.path)
        fresh.removeAllCachedResourceValues()
        let values = try fresh.resourceValues(forKeys: [
            .fileProtectionKey, .isExcludedFromBackupKey, .isDirectoryKey,
            .volumeSupportsFileProtectionKey,
        ])
        XCTAssertEqual(values.allValues[.volumeSupportsFileProtectionKey] as? Bool, false, file: file, line: line)
        XCTAssertEqual(values.fileProtection, .completeUntilFirstUserAuthentication, file: file, line: line)
        XCTAssertEqual(values.isExcludedFromBackup,
            ProtectedFilePolicyV1.disposition(for: kind).isExcludedFromBackup, file: file, line: line)
        XCTAssertEqual(values.isDirectory,
            ProtectedFilePolicyV1.disposition(for: kind).expectsDirectory, file: file, line: line)
        #else
        XCTFail("Unsupported Simulator disposition outside the diagnostic target", file: file, line: line)
        #endif
    }

    func assertResourceValues(
        _ kind: OwnedFileKindV1,
        at url: URL,
        protection expectedProtection: URLFileProtection = .complete,
        isExcludedFromBackup expectedBackupDisposition: Bool? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var freshURL = URL(fileURLWithPath: url.path)
        freshURL.removeAllCachedResourceValues()
        let values = try freshURL.resourceValues(forKeys: [
            .fileProtectionKey,
            .isExcludedFromBackupKey,
        ])
        XCTAssertEqual(
            values.fileProtection,
            expectedProtection,
            kind.rawValue,
            file: file,
            line: line
        )
        XCTAssertEqual(
            values.isExcludedFromBackup,
            expectedBackupDisposition
                ?? ProtectedFilePolicyV1.isExcludedFromBackup(for: kind),
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

import Darwin
import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class V23ErasePreexistingRetiredAuthorityTests: XCTestCase {
    @MainActor
    func testReceiptFreeAndMultipleRetiredStoresUseCompleteAcceptedSemanticsWithoutBootstrap() throws {
        let fixture = try makeFixture()
        let first = try fixture.currentFacts()
        XCTAssertTrue(first.history.receipts.isEmpty)
        try fixture.retireCurrent()
        let second = try fixture.currentFacts()
        XCTAssertTrue(second.history.receipts.isEmpty)
        try fixture.retireCurrent()
        let before = try fixture.controls()
        let cold = StoreGenerationFactory(applicationSupportURL: fixture.support)
        let authority = try cold.makeRestoreGenerationAuthority()
        let service = fixture.service()
        for facts in [first, second] {
            try cold.validatePreexistingRetiredGenerationForErase(id: facts.id,
                expectedCurrentID: before.currentID, expectedRetiredIDs: before.retiredIDs,
                authority: authority, service: service)
            XCTAssertEqual(try fixture.facts(id: facts.id), facts)
        }
        XCTAssertEqual(try fixture.controls(), before)
        XCTAssertEqual(try cold.makeGenerationLeaseRegistry().activeEpochs(), [])
    }

    @MainActor
    func testPopulatedRetiredSummaryPreservesOriginalsWhileOrdinaryExportRemainsCurrentOnly() throws {
        let fixture = try makeFixture()
        try fixture.seedSign()
        let before = try fixture.currentFacts()
        XCTAssertFalse(before.history.receipts.isEmpty)
        try fixture.retireCurrent()
        let controls = try fixture.controls()
        let cold = StoreGenerationFactory(applicationSupportURL: fixture.support)
        let authority = try cold.makeRestoreGenerationAuthority()
        try cold.validatePreexistingRetiredGenerationForErase(id: before.id,
            expectedCurrentID: controls.currentID, expectedRetiredIDs: controls.retiredIDs,
            authority: authority, service: fixture.service())
        try autoreleasepool {
            let retired = try fixture.open(id: before.id)
            XCTAssertThrowsError(try BackupRestoreService.currentSummary(
                modelContext: retired.modelContext, generationRootURL: retired.generationRootURL)) {
                XCTAssertEqual($0 as? BackupExportServiceError, .invalidGeneration)
            }
        }
        XCTAssertEqual(try fixture.facts(id: before.id), before)
        XCTAssertEqual(try fixture.controls(), controls)
    }

    @MainActor
    func testForeignOnlyCloneHistoryNeedsNoInventedLocalReceiptToAdmitRetiredSummary() async throws {
        let source = try makeFixture()
        try source.seedSign()
        let originals = try source.currentFacts()
        let archive = try autoreleasepool { () throws -> URL in
            let session = try source.open()
            let exporter = BackupExportService(modelContext: session.modelContext,
                generationRootURL: session.generationRootURL)
            let preview = try exporter.prepare()
            let destination = source.root.appendingPathComponent("exports", isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            return try exporter.export(previewID: preview.id, to: destination)
        }
        let destination = try makeFixture()
        let cloneID: UUID = try await { @MainActor () async throws -> UUID in
            let current = try destination.open()
            let package = try BackupImportService(generationRootURL: current.generationRootURL,
                scopedAccess: .alreadyAuthorized).stageAndValidate(selectedPackageURL: archive)
            let restorer = try BackupRestoreService(applicationSupportURL: destination.support,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }))
            destination.owners.unobservedOpen = true
            let cloned = try await restorer.restore(validatedPackage: package,
                currentModelContext: current.modelContext, currentGenerationID: current.generationID,
                currentGenerationRootURL: current.generationRootURL, mode: .clone)
            destination.owners.observe(cloned)
            return cloned.generationID
        }()
        let clone = try destination.facts(id: cloneID)
        XCTAssertFalse(clone.history.receipts.isEmpty)
        XCTAssertEqual(clone.history.receipts, originals.history.receipts)
        XCTAssertTrue(try clone.history.receipts.allSatisfy {
            try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData).generationID != cloneID
        })
        try destination.retireCurrent()
        let controls = try destination.controls()
        let cold = StoreGenerationFactory(applicationSupportURL: destination.support)
        let authority = try cold.makeRestoreGenerationAuthority()
        try cold.validatePreexistingRetiredGenerationForErase(id: cloneID,
            expectedCurrentID: controls.currentID, expectedRetiredIDs: controls.retiredIDs,
            authority: authority, service: destination.service())
        XCTAssertEqual(try destination.facts(id: cloneID), clone)
        XCTAssertEqual(try destination.controls(), controls)
        XCTAssertEqual(try source.currentFacts(), originals)
        let recoveryIntent = try await destination.interruptErase(at: .afterPointerSwitch)
        try destination.requireDrained()
        let recoveryFactory = StoreGenerationFactory(applicationSupportURL: destination.support)
        try recoveryFactory.validateRecoveryRetiredGenerationForErase(id: cloneID, intent: recoveryIntent,
            authority: recoveryFactory.makeRestoreGenerationAuthority(), service: destination.service())
        XCTAssertEqual(try destination.facts(id: cloneID), clone)
        XCTAssertEqual(try source.currentFacts(), originals)
        try await destination.finishRecovery(intent: recoveryIntent)
    }

    @MainActor
    func testReplacedNonemptyDestinationRetiredReadSettlesBeforePreIntentRollback() async throws {
#if DEBUG
        let source = try makeFixture()
        try source.seedSign()
        let sourceFacts = try source.currentFacts()
        let archive = try autoreleasepool { () throws -> URL in
            let session = try source.open()
            let exporter = BackupExportService(modelContext: session.modelContext,
                generationRootURL: session.generationRootURL)
            let preview = try exporter.prepare()
            let directory = source.root.appendingPathComponent("exports", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return try exporter.export(previewID: preview.id, to: directory)
        }
        let destination = try makeFixture()
        try destination.seedSign()
        let oldDestination = try destination.currentFacts()
        XCTAssertFalse(oldDestination.history.receipts.isEmpty)
        XCTAssertTrue(try destination.controls().retiredIDs.isEmpty)
        let restoredID: UUID = try await { @MainActor () async throws -> UUID in
            let current = try destination.open()
            let package = try BackupImportService(generationRootURL: current.generationRootURL,
                scopedAccess: .alreadyAuthorized).stageAndValidate(selectedPackageURL: archive)
            let restorer = try BackupRestoreService(applicationSupportURL: destination.support,
                storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }))
            destination.owners.unobservedOpen = true
            let restored = try await restorer.restore(validatedPackage: package,
                currentModelContext: current.modelContext, currentGenerationID: current.generationID,
                currentGenerationRootURL: current.generationRootURL, mode: .replaceExisting)
            destination.owners.observe(restored)
            return restored.generationID
        }()
        XCTAssertNotEqual(restoredID, oldDestination.id)
        let controls = try destination.controls()
        XCTAssertEqual(controls.currentID, restoredID)
        XCTAssertEqual(controls.retiredIDs, [oldDestination.id])
        let currentFacts = try destination.currentFacts()
        XCTAssertEqual(try destination.facts(id: oldDestination.id), oldDestination)
        let retiredRows = try destination.rawRows(id: oldDestination.id)
        XCTAssertFalse(retiredRows.isEmpty)
        let retiredRoot = destination.factory.installedGenerationURL(id: oldDestination.id)
        let retiredBytes = try destination.closedGenerationSnapshot(at: retiredRoot)
        let foreignRegistry = try source.factory.makeGenerationLeaseRegistry()
        let abort = try await destination.rollbackPriorRetiredPreparation(foreignRegistry: foreignRegistry)
        try destination.requireDrained()
        XCTAssertEqual(abort.originalGenerationID, restoredID)
        XCTAssertNotEqual(abort.subject.newGenerationID, restoredID)
        XCTAssertEqual(abort.reservation.subject, abort.subject)
        XCTAssertEqual(try destination.controls(), controls)
        XCTAssertTrue(try EraseIntentStore.completedCleanupRootIsAbsent(
            applicationSupportURL: destination.support))
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            destination.factory.installedGenerationURL(id: abort.subject.newGenerationID).path))
        XCTAssertEqual(try destination.closedGenerationSnapshot(at: retiredRoot), retiredBytes)
        XCTAssertEqual(try destination.rawRows(id: oldDestination.id), retiredRows)
        XCTAssertEqual(try destination.facts(id: oldDestination.id), oldDestination)
        XCTAssertEqual(try destination.currentFacts(), currentFacts)
        XCTAssertEqual(try source.currentFacts(), sourceFacts)
#endif
    }

    @MainActor
    func testRetiredAdmissionRejectsCorruptOriginalStateAndUnknownMemberWithoutEffects() throws {
        for hostile in ["receipt", "state-generation", "unknown-member"] {
            let fixture = try makeFixture()
            try fixture.seedSign()
            let original = try fixture.currentFacts()
            try fixture.retireCurrent()
            let root = fixture.factory.installedGenerationURL(id: original.id)
            if hostile == "unknown-member" {
                // Read genuine semantic/raw baselines while the store is admissible,
                // then drain every observed owner before freezing all SQLite bytes.
                // Reopening after insertion would reject in fixture setup, before
                // exercising the cold Erase admission under test.
                XCTAssertEqual(try fixture.facts(id: original.id), original)
                let rawBaseline = try fixture.rawRows(id: original.id)
                XCTAssertFalse(rawBaseline.isEmpty)
                let closedBefore = try fixture.closedGenerationSnapshot(at: root)
                XCTAssertNotNil(closedBefore["model.sqlite"])
                let unknownURL = root.appendingPathComponent("unowned.bin")
                let unknownBytes = Data("unregistered synthetic bytes".utf8)
                try unknownBytes.write(to: unknownURL)
                let closedHostile = try fixture.closedGenerationSnapshot(at: root)
                // Inserting the hostile child may change its parent directory's
                // link count. Preserve the root identity/type and every prior
                // member, then use the complete post-insertion snapshot below
                // as the no-effect baseline (including the root link count).
                let rootBefore = try XCTUnwrap(closedBefore[""])
                let rootHostile = try XCTUnwrap(closedHostile[""])
                XCTAssertEqual(rootHostile.device, rootBefore.device)
                XCTAssertEqual(rootHostile.inode, rootBefore.inode)
                XCTAssertEqual(rootHostile.mode, rootBefore.mode)
                XCTAssertEqual(rootHostile.bytes, rootBefore.bytes)
                XCTAssertEqual(closedHostile.filter { !$0.key.isEmpty && $0.key != "unowned.bin" },
                    closedBefore.filter { !$0.key.isEmpty })
                XCTAssertEqual(closedHostile["unowned.bin"]?.bytes, unknownBytes)
                let controls = try fixture.controls()
                let cold = StoreGenerationFactory(applicationSupportURL: fixture.support)
                let authority = try cold.makeRestoreGenerationAuthority()
                XCTAssertThrowsError(try cold.validatePreexistingRetiredGenerationForErase(id: original.id,
                    expectedCurrentID: controls.currentID, expectedRetiredIDs: controls.retiredIDs,
                    authority: authority, service: fixture.service()), hostile) {
                    XCTAssertEqual($0 as? StoreMigrationFailure, .invalidPath)
                }
                // Complete member/presence/inode/type/byte equality includes the
                // database, WAL and SHM without excluding mutable SQLite sidecars.
                // Thus every raw row captured above remains unchanged without a
                // permissive reopen or a cached managed-object afterimage.
                XCTAssertEqual(try fixture.closedGenerationSnapshot(at: root), closedHostile, hostile)
                XCTAssertEqual(try fixture.controls(), controls, hostile)
                XCTAssertEqual(try Data(contentsOf: unknownURL), unknownBytes)
                continue
            } else {
                try autoreleasepool {
                    let session = try fixture.open(id: original.id)
                    if hostile == "receipt" {
                        let row = try XCTUnwrap(session.modelContext.fetch(FetchDescriptor<MutationReceiptRow>()).first)
                        row.envelopeData = Data("{}".utf8)
                    } else {
                        let state = try XCTUnwrap(session.modelContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).first)
                        state.generationID = UUID()
                    }
                    try session.modelContext.save()
                }
            }
            let controls = try fixture.controls()
            let raw = try fixture.rawRows(id: original.id)
            let names = try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted()
            let cold = StoreGenerationFactory(applicationSupportURL: fixture.support)
            let authority = try cold.makeRestoreGenerationAuthority()
            XCTAssertThrowsError(try cold.validatePreexistingRetiredGenerationForErase(id: original.id,
                expectedCurrentID: controls.currentID, expectedRetiredIDs: controls.retiredIDs,
                authority: authority, service: fixture.service()), hostile)
            XCTAssertEqual(try fixture.rawRows(id: original.id), raw, hostile)
            XCTAssertEqual(try fixture.controls(), controls, hostile)
            XCTAssertEqual(try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted(), names, hostile)
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("model.sqlite").path))
        }
    }

    @MainActor
    func testRetiredSummaryReprovesExactPointerAfterFullInventoryAndPreservesDenial() throws {
#if DEBUG
        let fixture = try makeFixture()
        try fixture.seedSign()
        let original = try fixture.currentFacts()
        try fixture.retireCurrent()
        let controls = try fixture.controls()
        let cold = StoreGenerationFactory(applicationSupportURL: fixture.support)
        let authority = try cold.makeRestoreGenerationAuthority()
        let pointer = try cold.currentGenerationPointerV3(expectedGenerationID: controls.currentID, authority: authority)
        let altered = try CurrentGenerationPointerV3(generationID: controls.currentID,
            generationManifestSHA256: pointer.generationManifestSHA256,
            workspaceID: WorkspaceID(rawValue: XCTUnwrap(UUID(uuidString: pointer.workspaceID))),
            replicaID: ReplicaID(rawValue: XCTUnwrap(UUID(uuidString: pointer.replicaID))),
            knownReplicaIDs: try pointer.knownReplicaIdentitySet().union([ReplicaID(rawValue: UUID())]),
            storeSchemaVersion: pointer.storeSchemaVersion).canonicalData()
        let service = fixture.service()
        var didInject = false
        var injectionError: Error?
        service.erasePhaseDiagnosticForTesting = { phase in
            guard phase == "frozen.inventory-predicate", !didInject else { return }
            didInject = true
            do { try altered.write(to: fixture.currentURL) }
            catch { injectionError = error }
        }
        XCTAssertThrowsError(try cold.validatePreexistingRetiredGenerationForErase(id: original.id,
            expectedCurrentID: controls.currentID, expectedRetiredIDs: controls.retiredIDs,
            authority: authority, service: service)) {
            XCTAssertEqual($0 as? EraseAllServiceError, .invalidAuthority)
        }
        XCTAssertTrue(didInject)
        XCTAssertNil(injectionError)
        XCTAssertEqual(try Data(contentsOf: fixture.currentURL), altered)
        XCTAssertEqual(try fixture.facts(id: original.id), original)
        XCTAssertEqual(try authority.retiredGenerationIDs(), controls.retiredIDs)
        XCTAssertEqual(try cold.makeGenerationLeaseRegistry().activeEpochs(), [])
        // Restore only the synthetic pointer changed by this witness, then a
        // fresh fixed read must succeed; no accepted capability was cached.
        try controls.pointer.write(to: fixture.currentURL)
        service.erasePhaseDiagnosticForTesting = nil
        try cold.validatePreexistingRetiredGenerationForErase(id: original.id,
            expectedCurrentID: controls.currentID, expectedRetiredIDs: controls.retiredIDs,
            authority: authority, service: service)
        XCTAssertEqual(try fixture.controls(), controls)
#endif
    }

    @MainActor
    func testRecoveryRetiredSourcesPreserveHistoryAcrossPreparedPointerLagAndPartialCleanup() async throws {
        for boundary in [EraseAllFailurePoint.afterPreparedWrite, .afterPointerSwitch, .afterPointerPhaseWrite, .afterSessionPhaseWrite] {
            let fixture = try makeFixture()
            try fixture.seedSign()
            let populated = try fixture.currentFacts()
            try fixture.retireCurrent()
            let receiptFree = try fixture.currentFacts()
            XCTAssertTrue(receiptFree.history.receipts.isEmpty)
            try fixture.retireCurrent()
            let intent = try await fixture.interruptErase(at: boundary)
            try fixture.requireDrained()
            let cold = StoreGenerationFactory(applicationSupportURL: fixture.support)
            let authority = try cold.makeRestoreGenerationAuthority()
            if boundary == .afterSessionPhaseWrite {
                XCTAssertEqual(intent.phase, .sessionActivated)
                // Use the real lease-aware removal kernel to model a completed
                // first cleanup step; the remaining source cannot depend on it.
                try cold.removeInstalledGeneration(id: intent.oldGenerationID,
                    keeping: intent.newGenerationID, authority: authority)
                XCTAssertFalse(FileManager.default.fileExists(
                    atPath: cold.installedGenerationURL(id: intent.oldGenerationID).path))
            }
            for source in [populated, receiptFree] {
                try cold.validateRecoveryRetiredGenerationForErase(id: source.id,
                    intent: intent, authority: authority, service: fixture.service())
                XCTAssertEqual(try fixture.facts(id: source.id), source)
            }
            if boundary == .afterPreparedWrite {
                XCTAssertEqual(try cold.currentGenerationID(), intent.oldGenerationID)
                // The real publication API reproduces the durable pointer/retired
                // lag before normalizePointerAndRetired publishes the second half.
                let empty = try DeletionLedgerProofV2(entryCount: 0,
                    canonicalSHA256: StoreMigrationCanonicalJSONV1.sha256(try DeletionLedgerV2.empty.canonicalData()))
                try cold.publishEmptyEraseGeneration(expectedOldPointer: try XCTUnwrap(intent.oldPointer),
                    targetPointer: try XCTUnwrap(intent.targetPointer), expectedEmptyLedger: empty,
                    authority: authority)
                XCTAssertEqual(try authority.retiredGenerationIDs(),
                    intent.generationIDsToDelete.filter { $0 != intent.oldGenerationID })
                for source in [populated, receiptFree] {
                    try cold.validateRecoveryRetiredGenerationForErase(id: source.id,
                        intent: intent, authority: authority, service: fixture.service())
                    XCTAssertEqual(try fixture.facts(id: source.id), source)
                }
            }
            try fixture.requireDrained()
            try await fixture.finishRecovery(intent: intent)
        }
    }

    @MainActor
    func testRecoveryRetiredScopeRejectsWrongMembershipAndLateControlDriftWithoutEffects() async throws {
        let fixture = try makeFixture()
        try fixture.seedSign()
        let source = try fixture.currentFacts()
        try fixture.retireCurrent()
        let intent = try await fixture.interruptErase(at: .afterPointerSwitch)
        try fixture.requireDrained()
        let cold = StoreGenerationFactory(applicationSupportURL: fixture.support)
        let authority = try cold.makeRestoreGenerationAuthority()
        let controls = try fixture.controls()
        let intentURL = fixture.support.appendingPathComponent("FieldEvidenceErase/erase.json")
        let intentBytes = try Data(contentsOf: intentURL)
        for wrongID in [intent.oldGenerationID, intent.newGenerationID, UUID()] {
            XCTAssertThrowsError(try cold.validateRecoveryRetiredGenerationForErase(id: wrongID,
                intent: intent, authority: authority, service: fixture.service())) {
                XCTAssertEqual($0 as? EraseAllServiceError, .invalidAuthority)
            }
        }
        XCTAssertThrowsError(try cold.validateRecoveryRetiredGenerationForErase(id: source.id,
            intent: intent.advancing(to: .pointerSwitched), authority: authority, service: fixture.service())) {
            XCTAssertEqual($0 as? EraseAllServiceError, .invalidAuthority)
        }
        for name in [".erase.json.next", ".preparation.json.next"] {
            let eraseRoot = intentURL.deletingLastPathComponent()
            let pending = eraseRoot.appendingPathComponent(name)
            let data = name == ".erase.json.next" ? intentBytes
                : try Data(contentsOf: eraseRoot.appendingPathComponent("preparation.json"))
            try fixture.requireDrained()
            let sourceRoot = cold.installedGenerationURL(id: source.id)
            let before = try fixture.closedGenerationSnapshot(at: sourceRoot)
            try data.write(to: pending)
            XCTAssertThrowsError(try cold.validateRecoveryRetiredGenerationForErase(id: source.id,
                intent: intent, authority: authority, service: fixture.service())) {
                XCTAssertEqual($0 as? EraseAllServiceError, .invalidAuthority)
            }
            XCTAssertEqual(try Data(contentsOf: pending), data)
            XCTAssertEqual(try fixture.closedGenerationSnapshot(at: sourceRoot), before)
            XCTAssertEqual(try fixture.controls(), controls)
            XCTAssertEqual(try Data(contentsOf: intentURL), intentBytes)
            try FileManager.default.removeItem(at: pending)
        }
        // Initial admission is not reusable after a durable Erase intent exists.
        XCTAssertThrowsError(try cold.validatePreexistingRetiredGenerationForErase(id: source.id,
            expectedCurrentID: controls.currentID, expectedRetiredIDs: controls.retiredIDs,
            authority: authority, service: fixture.service()))
        try autoreleasepool {
            let retired = try fixture.open(id: source.id)
            XCTAssertThrowsError(try BackupRestoreService.currentSummary(modelContext: retired.modelContext,
                generationRootURL: retired.generationRootURL)) {
                XCTAssertEqual($0 as? BackupExportServiceError, .invalidGeneration)
            }
        }
        XCTAssertEqual(try fixture.facts(id: source.id), source)
#if DEBUG
        for drift in ["pointer", "intent"] {
            let service = fixture.service()
            var injected = false
            var injectionError: Error?
            var hostileBytes: Data?
            service.erasePhaseDiagnosticForTesting = { phase in
                guard phase == "frozen.inventory-predicate", !injected else { return }
                injected = true
                do {
                    if drift == "pointer" {
                        let original = try cold.currentGenerationPointerV3(expectedGenerationID: intent.newGenerationID,
                            authority: authority)
                        let changed = try CurrentGenerationPointerV3(generationID: intent.newGenerationID,
                            generationManifestSHA256: original.generationManifestSHA256,
                            workspaceID: WorkspaceID(rawValue: try XCTUnwrap(intent.targetPointer).workspaceID),
                            replicaID: ReplicaID(rawValue: try XCTUnwrap(intent.targetPointer).replicaID),
                            knownReplicaIDs: try original.knownReplicaIdentitySet().union([ReplicaID(rawValue: UUID())]),
                            storeSchemaVersion: original.storeSchemaVersion)
                        let data = try changed.canonicalData()
                        hostileBytes = data
                        try data.write(to: fixture.currentURL)
                    } else {
                        let data = try EraseIntentCodecV1.encode(intent.advancing(to: .pointerSwitched))
                        hostileBytes = data
                        try data.write(to: intentURL)
                    }
                } catch { injectionError = error }
            }
            XCTAssertThrowsError(try cold.validateRecoveryRetiredGenerationForErase(id: source.id,
                intent: intent, authority: authority, service: service)) {
                XCTAssertEqual($0 as? EraseAllServiceError, .invalidAuthority)
            }
            service.erasePhaseDiagnosticForTesting = nil
            XCTAssertTrue(injected)
            XCTAssertNil(injectionError)
            let changedURL = drift == "pointer" ? fixture.currentURL : intentURL
            XCTAssertEqual(try Data(contentsOf: changedURL), try XCTUnwrap(hostileBytes))
            // Restore only this test's hostile controls, after denial. Production
            // must neither accept drift nor repair it as a side effect of the read.
            try controls.pointer.write(to: fixture.currentURL)
            try intentBytes.write(to: intentURL)
            XCTAssertEqual(try fixture.facts(id: source.id), source)
            XCTAssertEqual(try fixture.controls(), controls)
            XCTAssertEqual(try Data(contentsOf: intentURL), intentBytes)
        }
#endif
        try cold.validateRecoveryRetiredGenerationForErase(id: source.id,
            intent: intent, authority: authority, service: fixture.service())
        XCTAssertEqual(try fixture.facts(id: source.id), source)
        try fixture.requireDrained()
        try await fixture.finishRecovery(intent: intent)
    }

    @MainActor
    func testRecoveryRetiredCorruptHistoryAndUnknownBytesRetainAllSources() async throws {
        for hostile in ["receipt", "state-generation", "unknown-member"] {
            let fixture = try makeFixture()
            try fixture.seedSign()
            let source = try fixture.currentFacts()
            try fixture.retireCurrent()
            let intent = try await fixture.interruptErase(at: .afterPointerSwitch)
            let root = fixture.factory.installedGenerationURL(id: source.id)
            let controls = try fixture.controls()
            let intentURL = fixture.support.appendingPathComponent("FieldEvidenceErase/erase.json")
            let intentBytes = try Data(contentsOf: intentURL)
            if hostile != "unknown-member" {
                try autoreleasepool {
                    let session = try fixture.open(id: source.id)
                    if hostile == "receipt" {
                        let row = try XCTUnwrap(session.modelContext.fetch(FetchDescriptor<MutationReceiptRow>()).first)
                        row.envelopeData = Data("{}".utf8)
                    } else {
                        let state = try XCTUnwrap(session.modelContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).first)
                        state.generationID = UUID()
                    }
                    try session.modelContext.save()
                }
                let raw = try fixture.rawRows(id: source.id)
                let cold = StoreGenerationFactory(applicationSupportURL: fixture.support)
                XCTAssertThrowsError(try cold.validateRecoveryRetiredGenerationForErase(id: source.id,
                    intent: intent, authority: cold.makeRestoreGenerationAuthority(), service: fixture.service())) {
                    if hostile == "receipt" { XCTAssertTrue($0 is DecodingError) }
                    else { XCTAssertEqual($0 as? GenerationLeaseRegistryFailureV1, .corruptRegistry) }
                }
                XCTAssertEqual(try fixture.rawRows(id: source.id), raw)
            } else {
                XCTAssertEqual(try fixture.facts(id: source.id), source)
                try fixture.requireDrained()
                try Data("unregistered synthetic recovery bytes".utf8)
                    .write(to: root.appendingPathComponent("unowned.bin"))
                let before = try fixture.closedGenerationSnapshot(at: root)
                let cold = StoreGenerationFactory(applicationSupportURL: fixture.support)
                XCTAssertThrowsError(try cold.validateRecoveryRetiredGenerationForErase(id: source.id,
                    intent: intent, authority: cold.makeRestoreGenerationAuthority(), service: fixture.service())) {
                    XCTAssertEqual($0 as? StoreMigrationFailure, .invalidPath)
                }
                XCTAssertEqual(try fixture.closedGenerationSnapshot(at: root), before)
            }
            XCTAssertEqual(try fixture.controls(), controls)
            XCTAssertEqual(try Data(contentsOf: intentURL), intentBytes)
            for id in intent.generationIDsToDelete + [intent.newGenerationID] {
                XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.factory.installedGenerationURL(id: id).path))
            }
            try fixture.requireDrained()
        }
    }

    @MainActor
    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("preexisting-retired-\(UUID())", isDirectory: true)
        let owners = Owners()
        let defaultsName = "preexisting-retired.\(UUID())"
        addTeardownBlock { @MainActor in
            guard owners.pendingOperations.isEmpty, !owners.unobservedOpen,
                  owners.allObservedOwnerControlsAreSettled else {
                XCTFail("Preexisting retired fixture retained a store; preserving root \(root.path)")
                return
            }
            // A checked but host-retained original owns inert descriptor pins.
            // Never unlink its physical root during this test host's lifetime.
            if Fixture.retainsOriginalRoot(root) { return }
            UserDefaults(suiteName: defaultsName)?.removePersistentDomain(forName: defaultsName)
            if FileManager.default.fileExists(atPath: root.path) {
                try FileManager.default.removeItem(at: root)
            }
        }
        let fixture = try Fixture(root: root, owners: owners, defaultsName: defaultsName)
        try autoreleasepool {
            let session = try fixture.open()
            let owner = try StoreSessionCoordinator(validatingSession: session)
            try owner.invalidateAndReleaseWriter()
        }
        return fixture
    }
}

private actor V23RetiredEraseAuthentication: LocalAuthenticationClient {
    func availability() -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 {
        .authenticated
    }
    func cancel(attemptID: UUID) {}
}

/// A failed checked handoff must keep the actual original graph and root alive.
/// The host pin remains after checked control release because the exact
/// original operation still owns inert descriptor pins until test-host exit.
@MainActor
private final class RetainedInterruptedEraseOwner {
    let root: URL
    var gate: AppAccessGateV1?
    var router: StartupRouter?
    var coordinator: StoreSessionCoordinator?
    var operation: EraseRouterOperationV1?
    var service: EraseAllService?
    var activatedSession: StoreGenerationSession?
    private(set) var checkedControlsReleased = false

    init(root: URL) { self.root = root }

    func markCheckedControlsReleased() {
        // Keep the original operation, inert pins and physical root reachable
        // for the lifetime of this test host. This is not a weak-nil claim.
        checkedControlsReleased = true
    }
}

@MainActor
private final class Owners {
    @MainActor
    final class WeakStore {
        weak var session: StoreGenerationSession?
        weak var context: ModelContext?
        weak var container: ModelContainer?
        init(_ value: StoreGenerationSession) {
            session = value; context = value.modelContext; container = value.modelContext.container
        }
        init(context value: ModelContext) {
            session = nil; context = value; container = value.container
        }
        var isDrained: Bool { session == nil && context == nil && container == nil }
    }
    final class WeakRouter {
        weak var value: StartupRouter?
        init(_ value: StartupRouter) { self.value = value }
        var checkedTerminalControls = false
        var isSettled: Bool { value == nil || checkedTerminalControls }
    }
    @MainActor
    final class WeakCoordinator {
        weak var value: StoreSessionCoordinator?
        weak var writer: WorkspaceWriterV1?
        init(_ value: StoreSessionCoordinator) {
            self.value = value; writer = value.workspaceWriter
        }
        var isDrained: Bool { value == nil && writer == nil }
    }
    var values: [WeakStore] = []
    var routers: [WeakRouter] = []
    var coordinators: [WeakCoordinator] = []
    var unobservedOpen = false
    var allObservedOwnerControlsAreSettled: Bool {
        values.allSatisfy(\.isDrained) && routers.allSatisfy(\.isSettled)
            && coordinators.allSatisfy(\.isDrained)
    }
    func markOriginalRouterChecked(_ router: StartupRouter) throws {
        let matching = routers.filter { $0.value === router }
        guard matching.count == 1 else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        matching[0].checkedTerminalControls = true
    }
    // A later observed session cannot discharge an earlier incomplete acquisition.
    private(set) var pendingOperations: Set<UUID> = []
#if DEBUG
    var pendingOperationAfterPriorRetiredRollback: UUID?
#endif
    func beginOperation() -> UUID {
        let token = UUID()
        pendingOperations.insert(token)
        return token
    }
    func completeOperationAfterDrain(_ token: UUID) throws {
        _ = try XCTUnwrap(pendingOperations.contains(token) ? true : nil,
            "Synthetic Erase operation has no pending acquisition guard")
        _ = try XCTUnwrap(!unobservedOpen && allObservedOwnerControlsAreSettled ? true : nil,
            "Synthetic Erase operation still has unsettled controls or live aliases")
        pendingOperations.remove(token)
    }
    func observe(_ value: StoreGenerationSession) {
        values.append(WeakStore(value)); unobservedOpen = false
    }
    func observeContext(_ value: ModelContext) {
        values.append(WeakStore(context: value)); unobservedOpen = false
    }
    func observeRouter(_ value: StartupRouter) { routers.append(WeakRouter(value)) }
    func observeCoordinator(_ value: StoreSessionCoordinator) {
        coordinators.append(WeakCoordinator(value))
        observeContext(value.modelContext)
    }
}

@MainActor
private final class Fixture {
    struct Facts: Equatable {
        let id: UUID
        let identity: WorkspaceReplicaIdentityV1
        let history: MutationHistorySnapshotV1
        let signs: [UUID]
    }
    struct Controls: Equatable {
        let currentID: UUID
        let retiredIDs: [UUID]
        let pointer: Data
        let retired: Data
    }
    let root: URL
    let support: URL
    let caches: URL
    let temporary: URL
    let owners: Owners
    let defaultsName: String
    let factory: StoreGenerationFactory
    @MainActor private static var retainedInterruptedOwners: [RetainedInterruptedEraseOwner] = []
    @MainActor static func retainsOriginalRoot(_ root: URL) -> Bool {
        retainedInterruptedOwners.contains { $0.root.standardizedFileURL == root.standardizedFileURL }
    }
    var currentURL: URL { support.appendingPathComponent("FieldEvidenceData/current.json") }

    init(root: URL, owners: Owners, defaultsName: String) throws {
        self.root = root; self.owners = owners; self.defaultsName = defaultsName
        support = root.appendingPathComponent("Library/Application Support", isDirectory: true)
        caches = root.appendingPathComponent("Library/Caches", isDirectory: true)
        temporary = root.appendingPathComponent("tmp", isDirectory: true)
        factory = StoreGenerationFactory(applicationSupportURL: support)
        for directory in [support, caches, temporary] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
    func open(id: UUID? = nil) throws -> StoreGenerationSession {
        owners.unobservedOpen = true
        let session = try id.map { try factory.openInstalledGeneration(id: $0) } ?? factory.openOrBootstrapCurrent()
        owners.observe(session)
        return session
    }
    func service(failure: EraseAllFailurePoint? = nil,
        admitErase: (@MainActor (EraseAllOperationSubjectV1) async throws -> AppAccessGateV1.EraseAdoptionToken)? = nil
    ) -> EraseAllService {
        EraseAllService(applicationSupportURL: support, cachesDirectoryURL: caches,
            temporaryDirectoryURL: temporary, userDefaults: UserDefaults(suiteName: defaultsName)!,
            bundleIdentifier: "com.palatis3.fieldrecord", defaultsDomainName: defaultsName,
            failureInjection: failure.map { EraseAllFailureInjection(failOnceAt: $0) },
            admitErase: admitErase)
    }
    func unlockedGate() async throws -> AppAccessGateV1 {
        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
            authentication: V23RetiredEraseAuthentication(), clock: SystemApplicationClock(),
            identifiers: SystemApplicationIDSource())
        let unlocked = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(unlocked, .authenticated)
        guard unlocked == .authenticated else { throw AppAccessContractFailureV1.accessDenied }
        return gate
    }
    func startupRouter() -> StartupRouter {
        StartupRouter(applicationSupportURL: support,
            entitlementRuntime: StoreKitEntitlementRuntimeV1(initialEvents: { [] },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } }))
    }
    func requireDrained() throws {
#if DEBUG
        if let pending = owners.pendingOperationAfterPriorRetiredRollback {
            try owners.completeOperationAfterDrain(pending)
            owners.pendingOperationAfterPriorRetiredRollback = nil
        }
#endif
        _ = try XCTUnwrap(owners.pendingOperations.isEmpty && !owners.unobservedOpen
            && owners.allObservedOwnerControlsAreSettled ? true : nil,
            "Synthetic Erase boundary has unsettled controls or live aliases")
    }
    func interruptErase(at point: EraseAllFailurePoint) async throws -> EraseIntentV1 {
        let diagnostics = DiagnosticsStore(applicationSupportURL: support)
        await diagnostics.prepare()
        let pending = owners.beginOperation()
        let retained = RetainedInterruptedEraseOwner(root: root)
        // Install the host pin before constructing any original Router control.
        // On any throw it remains reachable, and teardown preserves the root.
        Self.retainedInterruptedOwners.append(retained)
        @MainActor
        func execute() async throws -> EraseIntentV1 {
            let gate = try await unlockedGate()
            retained.gate = gate
            let router = startupRouter()
            retained.router = router
            owners.observeRouter(router)
            try await router.startIfNeeded(accessGate: gate)
            guard case let .ready(coordinator, _, _) = router.route else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            retained.coordinator = coordinator
            owners.observeCoordinator(coordinator)
            let ticket = try await router.beginEraseOperation(coordinator: coordinator, accessGate: gate)
            let operation = try router.eraseRetirementOperation(for: ticket)
            retained.operation = operation
            var reservation: AppAccessGateV1.EraseAdoptionToken?
            let originalService = service(failure: point,
                admitErase: { subject in
                    if let authorization = try await router.eraseAdmissionAuthorization(ticket,
                        subject: subject) {
                        let actual = try await gate.reserveEraseAdoption(subject: subject,
                            authorization: authorization)
                        try router.recordEraseReservation(ticket, reservation: actual)
                        reservation = actual
                        return actual
                    }
                    guard let reservation, reservation.subject == subject else {
                        throw AppAccessContractFailureV1.staleAttempt
                    }
                    return reservation
                })
            retained.service = originalService
            let configured = try router.configureEraseService(originalService, operation: operation)
            // configureEraseService copies the Service. Pin the *actual* frame
            // owner, including its retained IntentStore, before first effect.
            retained.service = configured
            let lifecycleDependencies = try coordinator.packageLifecycleDependencies()
            var activationFailure: Error?
            var injected = false
            do {
                _ = try await configured.erase(confirmation: "ERASE",
                    coordinator: coordinator, diagnosticsStore: diagnostics,
                    operation: operation, activate: { [self] value in
                    retained.activatedSession = value
                    do {
                        try router.activateErasePreparationSession(value,
                            coordinator: coordinator, operation: operation)
                        owners.observe(value)
                        owners.observeCoordinator(coordinator)
                    } catch { activationFailure = error }
                }, lifecycleDependencies: lifecycleDependencies)
            } catch {
                guard error as? EraseAllServiceError == .injectedFailure else { throw error }
                injected = true
            }
            if let activationFailure { throw activationFailure }
            _ = try XCTUnwrap(injected ? true : nil, "Expected genuine Erase fault boundary \(point)")
            let authenticIntent = try configured.interruptedRetiredAuthorityIntentForTesting(
                point, operation: operation)
            // The Coordinator still owns the activated target; do not add a
            // second strong session alias across EX acquisition. A failure
            // remains pinned through the exact Coordinator and operation.
            retained.activatedSession = nil
            // This proof requires the original fault, live exact intent and
            // original Router ticket. It poisons continuations and transfers
            // the exact inventory, Registry G, temporal EX and physical root.
            try await router.beginInterruptedEarlyEraseColdRestartForTesting(
                operation, originalService: configured, expectedFault: point)
            // The old Router has released its aggregate. Only the test's
            // strong aliases are dropped; weak observations must then drain.
            retained.coordinator = nil
            retained.activatedSession = nil
            return authenticIntent
        }
        let authenticIntent = try await execute()
        let aliasDrain = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.owners.values.allSatisfy(\.isDrained)
                && self.owners.coordinators.allSatisfy(\.isDrained)
        }, object: NSObject())
        let drainResult = await XCTWaiter.fulfillment(of: [aliasDrain], timeout: 30)
        XCTAssertEqual(drainResult, .completed)
        _ = try XCTUnwrap(owners.values.allSatisfy(\.isDrained)
            && owners.coordinators.allSatisfy(\.isDrained) ? true : nil,
            "Original Erase session/coordinator aliases remain live")
        // The checked phase-specific close includes original readers,
        // preparation readers and, after session activation, the installed
        // target writer. A thrown close retains the host pin and pending token.
        let router = try XCTUnwrap(retained.router)
        let operation = try XCTUnwrap(retained.operation)
        let gate = try XCTUnwrap(retained.gate)
        try router.finishInterruptedEarlyEraseColdRestartForTesting(operation)
        var cleanupRefused = false
        do { _ = try await operation.advanceCleanup() }
        catch AppAccessContractFailureV1.staleAttempt { cleanupRefused = true }
        _ = try XCTUnwrap(cleanupRefused ? true : nil,
            "Original Erase cleanup effect re-entered after checked shutdown")
        var completionRefused = false
        do { _ = try operation.completedRetirement() }
        catch { completionRefused = true }
        _ = try XCTUnwrap(completionRefused ? true : nil,
            "Original Erase operation re-entered after checked shutdown")
        var startupRefused = false
        do { try await router.startIfNeeded(accessGate: gate) }
        catch AppAccessContractFailureV1.staleAttempt { startupRefused = true }
        _ = try XCTUnwrap(startupRefused ? true : nil,
            "Original Router re-entered after checked shutdown")
        retained.markCheckedControlsReleased()
        try owners.markOriginalRouterChecked(router)
        try owners.completeOperationAfterDrain(pending)
        try requireDrained()
        return authenticIntent
    }
#if DEBUG
    /// Real original Router and gate ownership; no synthetic source-only receipt.
    func rollbackPriorRetiredPreparation(foreignRegistry: GenerationLeaseRegistryV1) async throws
        -> AbortedEraseAdmissionReceiptV1 {
        let pending = owners.beginOperation()
        let retained = RetainedInterruptedEraseOwner(root: root)
        Self.retainedInterruptedOwners.append(retained) // before original controls/effects
        let gate = try await unlockedGate()
        retained.gate = gate
        let router = startupRouter()
        retained.router = router
        owners.observeRouter(router)
        try router.bindStartupAccessGate(gate)
        try await router.startIfNeeded(accessGate: gate)
        var checkedNegativeAuthorities = false
        var aborts: [AbortedEraseAdmissionReceiptV1] = []
        var activationEntries = 0
        @MainActor
        func execute() async throws -> (StartupRouter.OriginalOperationTicket, AbortedEraseAdmissionReceiptV1) {
            guard case let .ready(coordinator, diagnostics, _) = router.route else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            retained.coordinator = coordinator
            owners.observeCoordinator(coordinator)
            let ticket = try await router.beginEraseOperation(coordinator: coordinator, accessGate: gate)
            let operation = try router.eraseRetirementOperation(for: ticket)
            retained.operation = operation
            var reservation: AppAccessGateV1.EraseAdoptionToken?
            let original = EraseAllService(applicationSupportURL: support,
                cachesDirectoryURL: caches, temporaryDirectoryURL: temporary,
                userDefaults: UserDefaults(suiteName: defaultsName)!,
                bundleIdentifier: "com.palatis3.fieldrecord", defaultsDomainName: defaultsName,
                failureInjection: EraseAllFailureInjection(failOnceAt: .afterEmptyGenerationDirectoryCreate),
                admitErase: { [weak router, weak gate] subject in
                    guard let router, let gate else { throw AppAccessContractFailureV1.staleAttempt }
                    if let authorization = try await router.eraseAdmissionAuthorization(ticket, subject: subject) {
                        let value = try await gate.reserveEraseAdoption(subject: subject, authorization: authorization)
                        try router.recordEraseReservation(ticket, reservation: value)
                        reservation = value
                        return value
                    }
                    guard let reservation, reservation.subject == subject else {
                        throw AppAccessContractFailureV1.staleAttempt
                    }
                    return reservation
                }, didAbortEraseAdmission: { aborts.append($0) })
            retained.service = original
            let configured = try router.configureEraseService(original, operation: operation)
            retained.service = configured
            configured.erasePhaseDiagnosticForTesting = { phase in
                guard phase == "frozen.inventory-predicate", !checkedNegativeAuthorities,
                      let cohort = operation.inventory.lastPreexistingRetiredReadCohortForTesting else { return }
                do {
                    XCTAssertNoThrow(try operation.requirePreexistingRetiredReadCohort(cohort,
                        inventory: operation.inventory, registry: cohort.registryForTesting))
                    guard let allocation = cohort.readerAllocationForTesting else {
                        XCTFail("Live retired semantic read has no actual retained allocation")
                        return
                    }
                    XCTAssertThrowsError(try cohort.requireDrained(registry: cohort.registryForTesting,
                        readerAllocation: allocation)) {
                        XCTAssertEqual($0 as? GenerationLeaseRegistryFailureV1, .uncertainOwner)
                    }
                    XCTAssertThrowsError(try operation.requirePreexistingRetiredReadCohort(cohort,
                        inventory: EraseReaderRetirementInventoryV1(), registry: cohort.registryForTesting)) {
                        XCTAssertEqual($0 as? AppAccessContractFailureV1, .staleAttempt)
                    }
                    XCTAssertThrowsError(try operation.requirePreexistingRetiredReadCohort(cohort,
                        inventory: operation.inventory, registry: foreignRegistry)) {
                        XCTAssertEqual($0 as? AppAccessContractFailureV1, .staleAttempt)
                    }
                    checkedNegativeAuthorities = true
                } catch {
                    XCTFail("Unexpected error while checking retired read cohort authorities")
                }
            }
            defer { configured.erasePhaseDiagnosticForTesting = nil }
            do {
                _ = try await configured.erase(confirmation: "ERASE", coordinator: coordinator,
                    diagnosticsStore: diagnostics, operation: operation,
                    activate: { _ in activationEntries += 1 },
                    lifecycleDependencies: coordinator.packageLifecycleDependencies())
                XCTFail("Expected genuine pre-intent preparation injection")
                throw AppAccessContractFailureV1.staleAttempt
            } catch EraseAllServiceError.injectedFailure { }
            XCTAssertTrue(checkedNegativeAuthorities)
            XCTAssertEqual(activationEntries, 0)
            XCTAssertEqual(aborts.count, 1)
            let receipt = try XCTUnwrap(aborts.first)
            XCTAssertEqual(receipt.reservation, reservation)
            XCTAssertTrue(try EraseIntentStore.completedCleanupRootIsAbsent(applicationSupportURL: support))
            try router.cancelAbortedErase(ticket, receipt: receipt)
            XCTAssertThrowsError(try router.cancelAbortedErase(ticket, receipt: receipt)) {
                XCTAssertEqual($0 as? AppAccessContractFailureV1, .staleAttempt)
            }
            try await gate.abandonEraseAdmission(receipt, setting: .value(.init(isEnabled: true)))
            return (ticket, receipt)
        }
        let (_, receipt) = try await execute()
        retained.coordinator = nil
        let unlockedAgain = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(unlockedAgain, .authenticated)
        guard unlockedAgain == .authenticated else { throw AppAccessContractFailureV1.accessDenied }
        // This actual startup settles pending source writers and aborted readers
        // before reopening. Dropping aliases alone is never called settlement.
        try await router.retryChecks(accessGate: gate)
        guard case let .ready(coordinator, _, _) = router.route else {
            throw AppAccessContractFailureV1.staleAttempt
        }
        owners.observeCoordinator(coordinator)
        try coordinator.invalidateAndReleaseWriter()
        retained.router = nil
        retained.markCheckedControlsReleased()
        // The local router/coordinator aliases end at this helper's return;
        // the host pin still retains the original operation, service and root.
        owners.pendingOperationAfterPriorRetiredRollback = pending
        return receipt
    }
#endif

    func finishRecovery(intent: EraseIntentV1) async throws {
        try requireDrained()
        let diagnostics = DiagnosticsStore(applicationSupportURL: support)
        await diagnostics.prepare()
        @MainActor
        func reconcile() async throws {
            let gate = try await unlockedGate()
            let router = startupRouter()
            owners.observeRouter(router)
            try await router.retryColdEraseForTesting(service: service(), accessGate: gate)
            guard case let .ready(recovered, _, _) = router.route else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            owners.observeCoordinator(recovered)
            defer { XCTAssertNoThrow(try recovered.invalidateAndReleaseWriter()) }
            XCTAssertEqual(recovered.generationID, intent.newGenerationID)
            XCTAssertTrue(BackupRestoreService.isEmptyCurrent(recovered.modelContext))
            XCTAssertEqual(try recovered.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 0)
        }
        let firstOperation = owners.beginOperation()
        try await reconcile()
        try owners.completeOperationAfterDrain(firstOperation)
        try requireDrained()
        for id in intent.generationIDsToDelete {
            XCTAssertFalse(FileManager.default.fileExists(atPath: factory.installedGenerationURL(id: id).path))
        }
        let completedControls = try controls()
        let eraseRoot = support.appendingPathComponent("FieldEvidenceErase", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: eraseRoot.path))
        @MainActor
        func reconcileAgain() async throws {
            let gate = try await unlockedGate()
            let router = startupRouter()
            owners.observeRouter(router)
            try await router.retryColdEraseForTesting(service: service(), accessGate: gate)
            guard case let .ready(second, _, _) = router.route else {
                throw AppAccessContractFailureV1.staleAttempt
            }
            owners.observeCoordinator(second)
            defer { XCTAssertNoThrow(try second.invalidateAndReleaseWriter()) }
            XCTAssertEqual(second.generationID, intent.newGenerationID)
            XCTAssertTrue(BackupRestoreService.isEmptyCurrent(second.modelContext))
            XCTAssertEqual(try second.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 0)
        }
        let secondOperation = owners.beginOperation()
        try await reconcileAgain()
        try owners.completeOperationAfterDrain(secondOperation)
        try requireDrained()
        XCTAssertEqual(try controls(), completedControls,
            "A second cold startup must not repeat Erase or mutate its pointer and retired controls")
        XCTAssertFalse(FileManager.default.fileExists(atPath: eraseRoot.path))
    }
    func currentFacts() throws -> Facts { try facts(id: factory.currentGenerationID()) }
    func facts(id: UUID) throws -> Facts {
        try autoreleasepool {
            let session = try open(id: id)
            let state = try XCTUnwrap(session.modelContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>()).first)
            let identity = try WorkspaceReplicaIdentityV1(workspaceID: WorkspaceID(rawValue: state.workspaceID),
                replicaID: ReplicaID(rawValue: state.activeReplicaID))
            let history = try MutationJournalStoreV1(modelContext: session.modelContext,
                identity: identity, generationID: id, allowStateBootstrap: false).exportSnapshot()
            return Facts(id: id, identity: identity, history: history,
                signs: try session.modelContext.fetch(FetchDescriptor<Asset>()).map(\.id).sorted { $0.uuidString < $1.uuidString })
        }
    }
    func rawRows(id: UUID) throws -> [Data] {
        try autoreleasepool {
            let session = try open(id: id)
            let encoder = JSONEncoder()
            var result: [Data] = []
            for row in try session.modelContext.fetch(FetchDescriptor<MutationReceiptRow>())
                .sorted(by: { $0.receiptIdentity < $1.receiptIdentity }) {
                result.append(try encoder.encode([row.mutationID.uuidString, row.workspaceMutationKey,
                    row.receiptIdentity, row.workspaceID.uuidString, row.replicaID.uuidString,
                    String(row.localSequence), row.commandKind, row.envelopeSHA256, row.receiptSHA256,
                    row.reversalBasisSHA256 ?? "nil"]))
                result.append(try encoder.encode([row.envelopeData, row.receiptData,
                    row.reversalBasisData, row.semanticReversalData]))
            }
            for row in try session.modelContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
                .sorted(by: { $0.workspaceID.uuidString < $1.workspaceID.uuidString }) {
                result.append(try encoder.encode([row.workspaceID.uuidString, row.generationID.uuidString,
                    row.activeReplicaID.uuidString, String(row.workspaceRevision), String(row.lastLocalSequence),
                    row.mutableSemanticSHA256 ?? "nil"]))
            }
            for row in try session.modelContext.fetch(FetchDescriptor<MutationQuarantineRow>())
                .sorted(by: { $0.workspaceMutationKey < $1.workspaceMutationKey }) {
                result.append(try encoder.encode([row.workspaceID.uuidString, row.mutationID.uuidString,
                    row.workspaceMutationKey, row.identityDomain, row.acceptedIdentitySHA256,
                    row.conflictingIdentitySHA256, String(row.detectedAt.timeIntervalSinceReferenceDate)]))
            }
            for row in try session.modelContext.fetch(FetchDescriptor<EntityMutationRevisionRow>())
                .sorted(by: { $0.stableIdentity < $1.stableIdentity }) {
                result.append(try encoder.encode([row.stableIdentity, row.kind, row.entityID.uuidString,
                    String(row.revision), row.externalProjectionSHA256 ?? "nil"]))
            }
            return result
        }
    }
    struct ClosedMember: Equatable {
        let device: UInt64
        let inode: UInt64
        let mode: UInt32
        let links: UInt64
        let bytes: Data?
    }
    func closedGenerationSnapshot(at root: URL) throws -> [String: ClosedMember] {
        _ = try XCTUnwrap(owners.pendingOperations.isEmpty && !owners.unobservedOpen
            && owners.allObservedOwnerControlsAreSettled ? true : nil,
            "Closed generation snapshot requires transient aliases drained and controls settled")
        let names = [""] + (try FileManager.default.subpathsOfDirectory(atPath: root.path)).sorted()
        var result: [String: ClosedMember] = [:]
        for name in names {
            let url = name.isEmpty ? root : root.appendingPathComponent(name)
            var before = stat()
            _ = try XCTUnwrap(Darwin.lstat(url.path, &before) == 0 ? true : nil)
            let kind = before.st_mode & S_IFMT
            _ = try XCTUnwrap(kind == S_IFDIR || kind == S_IFREG ? true : nil,
                "Synthetic closed generation contains an unexpected node type")
            let bytes = kind == S_IFREG ? try Data(contentsOf: url) : nil
            var after = stat()
            _ = try XCTUnwrap(Darwin.lstat(url.path, &after) == 0 ? true : nil)
            _ = try XCTUnwrap(before.st_dev == after.st_dev && before.st_ino == after.st_ino
                && before.st_mode == after.st_mode && before.st_nlink == after.st_nlink
                && before.st_size == after.st_size ? true : nil,
                "Synthetic closed generation changed while taking a snapshot")
            result[name] = ClosedMember(device: UInt64(before.st_dev), inode: UInt64(before.st_ino),
                mode: UInt32(before.st_mode), links: UInt64(before.st_nlink), bytes: bytes)
        }
        XCTAssertEqual(try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted(),
            Array(names.dropFirst()), "Closed generation membership changed while taking a snapshot")
        return result
    }
    func controls() throws -> Controls {
        Controls(currentID: try factory.currentGenerationID(), retiredIDs: try factory.retiredGenerationIDs(),
            pointer: try Data(contentsOf: currentURL),
            retired: try Data(contentsOf: support.appendingPathComponent("FieldEvidenceData/retired.json")))
    }
    func retireCurrent() throws {
        let observed = try autoreleasepool { () throws -> (CurrentGenerationPointerV3, WorkspaceReplicaIdentityV1) in
            let session = try open()
            return (try factory.currentGenerationPointerV3(expectedGenerationID: session.generationID), session.workspaceIdentity)
        }
        let old = observed.0
        let oldID = try XCTUnwrap(UUID(uuidString: old.generationID))
        let oldPointer = RestorePointerIdentityV1(generationID: oldID,
            generationManifestSHA256: old.generationManifestSHA256,
            knownReplicaIDs: Set(try old.knownReplicaIdentitySet().map(\.rawValue)),
            workspaceID: observed.1.workspaceID.rawValue, replicaID: observed.1.replicaID.rawValue)
        let authority = try factory.makeRestoreGenerationAuthority()
        let nextID = UUID()
        let created = try factory.createEmptyEraseGeneration(id: nextID,
            expectedOldPointer: oldPointer, identity: observed.1, authority: authority)
        try factory.publishEmptyEraseGeneration(expectedOldPointer: oldPointer,
            targetPointer: created.pointer, expectedEmptyLedger: created.ledgerProof, authority: authority)
        try factory.retireGeneration(oldID: oldID, currentID: nextID, authority: authority)
    }
    func seedSign() throws {
        try autoreleasepool {
            let session = try open()
            let owner = try StoreSessionCoordinator(validatingSession: session)
            defer { XCTAssertNoThrow(try owner.invalidateAndReleaseWriter()) }
            let pack = SignPack.illuminatedSignV1
            let siteID = UUID(), assetID = UUID()
            let mutation = try MutationIDV1(rawValue: UUID())
            _ = try owner.workspaceWriter.execute(.createFirstSign(.init(siteID: siteID,
                newSite: .init(id: siteID, label: "Synthetic retained site", address: nil, timeZoneID: "America/New_York"),
                assetID: assetID, assetLabel: "Synthetic retained sign", packID: pack.packID,
                packSchemaVersion: pack.schemaVersion, packContentVersion: pack.contentVersion,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                initialPlacementMutationID: mutation, initialPlacementEventID: UUID(),
                initialPhysicalEpisodeID: PhysicalPlacementEpisodeIDV1(rawValue: UUID()))), mutationID: mutation)
        }
    }
}

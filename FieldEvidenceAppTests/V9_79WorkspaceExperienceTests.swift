import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V9_79WorkspaceExperienceTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_777_593_600)
    private let digest = String(repeating: "a", count: 64)

    func testPreAuthenticationFactoryDoesNotRequireWorkspaceReconciliation() async throws {
        let manager = FileManager.default
        let support = manager.temporaryDirectory.appendingPathComponent(
            "c16-blind-factory-\(UUID().uuidString.lowercased())", isDirectory: true
        )
        try manager.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: support) }
        // Deliberately unavailable workspace storage must not prevent metadata-
        // only scratch hygiene from reaching the authentication gate.
        let dataRoot = support.appendingPathComponent(OwnedStorageRootKindV1.data.rawValue)
        let inaccessibleWorkspace = Data("not-a-workspace-directory".utf8)
        try inaccessibleWorkspace.write(to: dataRoot)
        XCTAssertThrowsError(try OwnedStorageLedgerV1(
            applicationSupportURL: support, capacityProvider: { _ in 1_000_000 }
        ))
        let store = try ProductionCompositionRoot.makePreAuthenticationIngressStore(
            applicationSupportURL: support
        )
        let operationID = UUID()
        let receipt = try await store.performBlindStartupHygiene(now: date, operationID: operationID)
        XCTAssertEqual(receipt.operationID, operationID)
        XCTAssertEqual(receipt.inspectedCount, 0)
        XCTAssertFalse(receipt.contentRead)
        XCTAssertEqual(try Data(contentsOf: dataRoot), inaccessibleWorkspace)
    }

    func testBlindHygieneDoesNotLoadPendingIntentContent() async throws {
        let operationID = UUID()
        let expected = try ProtectedIngressStartupHygieneReceiptV1(
            operationID: operationID, inspectedCount: 3,
            removedKnownOwnedCount: 1, retainedValidCount: 1,
            deferredAmbiguousCount: 1, contentRead: false
        )
        let effect = C16PendingLoadTrap(receipt: expected)
        let store = InjectedProtectedIngressStoreV1(effects: effect)
        let actual = try await store.performBlindStartupHygiene(now: date, operationID: operationID)
        XCTAssertEqual(actual, expected)
        XCTAssertTrue(actual.requiresAuthenticatedRecovery)
        do {
            _ = try await store.pendingIntents()
            XCTFail("the trap must reject pending content reads when explicitly invoked")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
    }

    func testScratchRecoveryRejectsReplacedOperationsDirectory() async throws {
        let manager = FileManager.default
        let support = manager.temporaryDirectory.appendingPathComponent(
            "c16-replaced-operations-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try manager.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: support) }
        let now = date
        let store = try ScratchDataLeaseStoreV1(
            applicationSupportURL: support,
            clock: { now },
            capacityProvider: { _ in 1_000_000 }
        )
        let operations = support.appendingPathComponent(
            OwnedStorageRootKindV1.operations.rawValue, isDirectory: true
        )
        let retained = support.appendingPathComponent("retained-operations", isDirectory: true)
        let originalBytes = Data("original-owned-root".utf8)
        try originalBytes.write(to: operations.appendingPathComponent("sentinel"))
        try manager.moveItem(at: operations, to: retained)
        let replacementScratch = operations.appendingPathComponent("ScratchDataV1", isDirectory: true)
        try manager.createDirectory(at: replacementScratch, withIntermediateDirectories: true)
        let replacementBytes = Data("replacement-root".utf8)
        try replacementBytes.write(to: operations.appendingPathComponent("sentinel"))

        do {
            _ = try await store.recoverScratchLeases()
            XCTFail("a retained descriptor must not authorize a replaced operations root")
        } catch {
            XCTAssertEqual(error as? ScratchDataLeaseStoreFailureV1, .invalidRoot)
        }
        XCTAssertEqual(try Data(contentsOf: retained.appendingPathComponent("sentinel")), originalBytes)
        XCTAssertEqual(try Data(contentsOf: operations.appendingPathComponent("sentinel")), replacementBytes)
        XCTAssertTrue(manager.fileExists(atPath: replacementScratch.path))
    }

    func testBlindHygieneCountsMixedPurposesWithoutReadingLeaseBytes() throws {
        let manager = FileManager.default
        let support = manager.temporaryDirectory.appendingPathComponent("c16-mixed-\(UUID())", isDirectory: true)
        try manager.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: support) }
        let now = date
        let store = try ScratchDataLeaseStoreV1(applicationSupportURL: support, clock: { now })
        let scratch = support.appendingPathComponent("FieldEvidenceOperations/ScratchDataV1", isDirectory: true)
        let old = now.addingTimeInterval(-172_800)
        func fixture(_ purpose: String, modified: Date, protected: Bool = true) throws -> URL {
            let directory = scratch.appendingPathComponent("\(purpose)-\(UUID().uuidString.lowercased())", isDirectory: true)
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            // Invalid lease JSON makes any content-decoding shortcut fail.
            let lease = directory.appendingPathComponent("lease.json")
            try Data("not-json-or-a-valid-lease".utf8).write(to: lease)
            if protected {
                try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: directory)
                try ProtectedFilePolicyV1.applyAndVerify(.temporaryFile, at: lease)
            } else {
                try manager.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: directory.path)
                XCTAssertThrowsError(try ProtectedFilePolicyV1.verify(.stagingDirectory, at: directory))
            }
            try manager.setAttributes([.modificationDate: modified], ofItemAtPath: lease.path)
            try manager.setAttributes([.modificationDate: modified], ofItemAtPath: directory.path)
            return directory
        }
        let expired = try fixture("capture", modified: old)
        let fresh = try fixture("import", modified: now.addingTimeInterval(-60))
        let ambiguous = try fixture("capture", modified: old, protected: false)
        let unknown = try fixture("unknown", modified: old)
        let receipt = try store.reconcileProtectedIngressHygiene(now: now, operationID: UUID())
        XCTAssertEqual(receipt.inspectedCount, 4)
        XCTAssertEqual(receipt.removedKnownOwnedCount, 1)
        XCTAssertEqual(receipt.retainedValidCount, 1)
        XCTAssertEqual(receipt.deferredAmbiguousCount, 2)
        XCTAssertFalse(receipt.contentRead)
        XCTAssertFalse(manager.fileExists(atPath: expired.path))
        for preserved in [fresh, ambiguous, unknown] {
            XCTAssertEqual(try Data(contentsOf: preserved.appendingPathComponent("lease.json")),
                           Data("not-json-or-a-valid-lease".utf8))
        }
        // A second operation must observe the retained descriptor from offset zero.
        let second = try store.reconcileProtectedIngressHygiene(now: now, operationID: UUID())
        XCTAssertEqual(second.inspectedCount, 3)
        XCTAssertEqual(second.removedKnownOwnedCount, 0)
        XCTAssertEqual(second.retainedValidCount, 1)
        XCTAssertEqual(second.deferredAmbiguousCount, 2)
    }

    func testBlindHygieneRejectsPreparedTargetSubstitutionAndPreservesLaterEntry() throws {
        let manager = FileManager.default
        let support = manager.temporaryDirectory.appendingPathComponent("c16-target-\(UUID())", isDirectory: true)
        try manager.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: support) }
        let now = date
        let interrupted = try ScratchDataLeaseStoreV1(applicationSupportURL: support, clock: { now },
            ingressHygieneFailureInjection: .afterPrepare)
        let scratch = support.appendingPathComponent("FieldEvidenceOperations/ScratchDataV1", isDirectory: true)
        let target = scratch.appendingPathComponent("capture-\(UUID().uuidString.lowercased())", isDirectory: true)
        try manager.createDirectory(at: target, withIntermediateDirectories: true)
        try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: target)
        let old = now.addingTimeInterval(-172_800)
        try manager.setAttributes([.modificationDate: old], ofItemAtPath: target.path)
        let operationID = UUID()
        XCTAssertThrowsError(try interrupted.reconcileProtectedIngressHygiene(now: now, operationID: operationID)) {
            XCTAssertEqual($0 as? OwnedStorageLedgerFailureV1, .attemptCollision)
        }
        let retained = support.appendingPathComponent("retained-target", isDirectory: true)
        try manager.moveItem(at: target, to: retained)
        try manager.createDirectory(at: target, withIntermediateDirectories: true)
        try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: target)
        try manager.setAttributes([.modificationDate: old], ofItemAtPath: target.path)
        let later = scratch.appendingPathComponent("import-\(UUID().uuidString.lowercased())", isDirectory: true)
        try manager.createDirectory(at: later, withIntermediateDirectories: true)
        let sentinel = Data("later ingress must survive the original operation".utf8)
        try sentinel.write(to: later.appendingPathComponent("sentinel"))
        let reopened = try ScratchDataLeaseStoreV1(applicationSupportURL: support, clock: { now })
        XCTAssertThrowsError(try reopened.reconcileProtectedIngressHygiene(now: now, operationID: operationID))
        XCTAssertTrue(manager.fileExists(atPath: retained.path))
        XCTAssertTrue(manager.fileExists(atPath: target.path))
        XCTAssertEqual(try Data(contentsOf: later.appendingPathComponent("sentinel")), sentinel)
    }

    func testBlindHygieneRejectsReplacedControlDirectory() throws {
        let manager = FileManager.default
        let support = manager.temporaryDirectory.appendingPathComponent("c16-control-\(UUID())", isDirectory: true)
        try manager.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: support) }
        let now = date
        let store = try ScratchDataLeaseStoreV1(applicationSupportURL: support, clock: { now })
        let operationID = UUID()
        let receipt = try store.reconcileProtectedIngressHygiene(now: now, operationID: operationID)
        let control = support.appendingPathComponent("FieldEvidenceOperations/ProtectedIngressReceiptsV1", isDirectory: true)
        let retained = support.appendingPathComponent("retained-control", isDirectory: true)
        try manager.moveItem(at: control, to: retained)
        try manager.createDirectory(at: control, withIntermediateDirectories: true)
        let sentinel = Data("replacement control".utf8)
        try sentinel.write(to: control.appendingPathComponent("sentinel"))
        XCTAssertThrowsError(try store.readProtectedIngressHygieneReceipt(operationID: operationID))
        XCTAssertEqual(try Data(contentsOf: control.appendingPathComponent("sentinel")), sentinel)
        let original = retained.appendingPathComponent("hygiene-\(operationID.uuidString.lowercased()).json")
        XCTAssertEqual(try JSONDecoder().decode(ProtectedIngressStartupHygieneReceiptV1.self,
            from: Data(contentsOf: original)), receipt)
    }

    func testV23P04C16G01TypedSettingsAndTaskFirstShell() async throws {
        let workspaceID = WorkspaceID(rawValue: UUID())
        let gate = C16AccessGate(state: .disabled)
        let coordinator = WorkspaceExperienceCoordinatorV1(access: gate)
        let selection = try ActiveWorkspaceSelectionV1(
            workspaceID: workspaceID, selectedAt: date, deviceLocalRevision: 1
        )
        let availability = try coordinator.availability(
            featureKey: "workspace.today", policyEnabled: true, accessState: .disabled,
            protectedDataAvailable: true, workspaceKind: .real
        )
        let settings = try SettingsProjectionV1(
            workspaceID: workspaceID, deviceLocalAppLockEnabled: false,
            activeWorkspaceSelection: selection, availability: [availability]
        )

        XCTAssertEqual(WorkspaceExperienceRootV1.canonicalShellOrder, [.today, .work, .assets, .reports])
        XCTAssertEqual(WorkspaceExperienceSearchScopeV1.canonicalOrder, [.all, .assets, .locations, .work, .reports])
        XCTAssertEqual(WorkspaceExperienceRootV1.allCases.count, 4)
        XCTAssertEqual(WorkspaceExperienceSearchScopeV1.allCases.count, 5)
        XCTAssertEqual(settings.availability.first?.reason, .available)
        XCTAssertEqual(settings.availability.first?.nextAction, WorkspaceExperienceAvailabilityNextActionV1.none)
        XCTAssertEqual(ActiveWorkspaceSelectionV1.lifecycleDisposition, .deviceLocalNotBackedUp)
        XCTAssertEqual(NoticeAcknowledgementV1.lifecycleDisposition, .deviceLocalNotBackedUp)

        let template = try decodeResource("StarterWorkspaceTemplateV1", as: StarterWorkspaceTemplateReleaseV1.self)
        try template.validate()
        XCTAssertEqual(template.practiceWatermark, PracticeWorkspaceReportProjectionV1.mandatoryWatermark)
        XCTAssertTrue(template.syntheticOnly && template.offlineCapable && !template.requiresPermission)
        XCTAssertFalse(WorkspaceExperienceDataPolicyV1.practiceMetricsCollected)
    }

    func testV23P04C16A01PracticeWorkspaceIsolationAndReset() async throws {
        let fixture = try C16Fixture()
        let command = try fixture.command()
        let receipt = try fixture.writer.commitWorkspaceExperience(command)
        XCTAssertEqual(receipt.mutationReceipt.mutationID, command.mutationID)
        XCTAssertEqual(try fixture.lifecycle.classification(), .practice)
        XCTAssertEqual(try fixture.lifecycle.provenance(), command.provenance)

        let share = try PracticeShareConfirmationV1(
            provenance: command.provenance, confirmationKey: "practice.share.confirm"
        )
        XCTAssertEqual(share.watermark, "PRACTICE — NOT FOR FIELD USE")
        XCTAssertTrue(share.explicitConfirmationRequired)

        try fixture.lifecycle.eraseWorkspaceRows()
        try fixture.context.save()
        try PracticeWorkspaceProvenanceEraseAllPolicyV1.validatePublishedEmptyGeneration(
            fixture.context
        )
        XCTAssertEqual(try fixture.lifecycle.classification(), .real, "absence of provenance is REAL")
        XCTAssertNil(try fixture.lifecycle.provenance(), "reset never auto-reinstalls Practice")
        XCTAssertTrue(WorkspaceExperienceLifecycleAdapterV1.practiceResetUsesWholeWorkspaceDeletion)
        XCTAssertFalse(WorkspaceExperienceLifecycleAdapterV1.practiceResetAutomaticallyReinstalls)

        let eraseSupport = FileManager.default.temporaryDirectory.appendingPathComponent(
            "c16-erase-\(UUID().uuidString.lowercased())", isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: eraseSupport) }
        let factory = StoreGenerationFactory(applicationSupportURL: eraseSupport)
        let eraseCoordinator = StoreSessionCoordinator(
            session: try factory.openOrBootstrapCurrent()
        )
        let diagnostics = DiagnosticsStore(applicationSupportURL: eraseSupport)
        await diagnostics.prepare()
        let defaultsSuiteName = "c16.erase.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let eraseService = EraseAllService(
            applicationSupportURL: eraseSupport,
            cachesDirectoryURL: eraseSupport.appendingPathComponent("Caches", isDirectory: true),
            temporaryDirectoryURL: eraseSupport.appendingPathComponent("Temporary", isDirectory: true),
            userDefaults: defaults,
            bundleIdentifier: defaultsSuiteName,
            defaultsDomainName: defaultsSuiteName,
            privateSystemDiscoveryIndex: nil
        )
        let erased = try await eraseService.erase(
            confirmation: EraseAllService.requiredConfirmation,
            coordinator: eraseCoordinator,
            diagnosticsStore: diagnostics
        ) { session in
            eraseCoordinator.activate(session: session)
        }
        XCTAssertFalse(erased.cleanupDeferred)
        XCTAssertEqual(erased.session.generationID, eraseCoordinator.generationID)
        XCTAssertEqual(erased.session.workspaceID, eraseCoordinator.workspaceID)
        XCTAssertTrue(try BackupRestoreService.isEmptyCurrent(erased.session.modelContext))
        XCTAssertEqual(try WorkspaceExperienceLifecycleAdapterV1(
            modelContext: erased.session.modelContext, workspaceID: erased.session.workspaceID
        ).classification(), .real)
        XCTAssertEqual(try WorkspaceExperienceLifecycleAdapterV1(
            modelContext: eraseCoordinator.modelContext, workspaceID: eraseCoordinator.workspaceID
        ).classification(), .real)

        let destination = WorkspaceID(rawValue: UUID())
        let clone = try ConfigurationClonePlanV1(
            planID: UUID(), sourceWorkspaceID: fixture.workspaceID,
            destinationWorkspaceID: destination, sourceWorkspaceRevision: 1,
            destinationIdentityIsNew: true, destinationKind: .real,
            copiesConfigurationOnly: true, copiesCustomerContent: false,
            copiesPracticeProvenance: false, copiedDefinitionSHA256s: [digest],
            mutationID: try MutationIDV1(rawValue: UUID())
        )
        XCTAssertNotEqual(clone.sourceWorkspaceID, clone.destinationWorkspaceID)
        XCTAssertFalse(clone.copiesCustomerContent || clone.copiesPracticeProvenance)
        XCTAssertEqual(try WorkspaceExperienceLifecycleAdapterV1(
            modelContext: fixture.context, workspaceID: destination
        ).classification(), .real)
    }

    func testV23P04C16H01AccessGatePrecedesEveryContentRead() async throws {
        let allowed = C16AccessGate(state: .disabled)
        let coordinator = WorkspaceExperienceCoordinatorV1(access: allowed)
        let result: String = try await coordinator.withAuthorizedPrivateProjection {
            allowed.recordContentRead()
            return "private"
        }
        XCTAssertEqual(result, "private")
        XCTAssertEqual(allowed.events, ["gate", "content"])

        let locked = C16AccessGate(state: .locked(reason: .lockNow))
        let lockedCoordinator = WorkspaceExperienceCoordinatorV1(access: locked)
        do {
            let _: String = try await lockedCoordinator.withAuthorizedPrivateProjection {
                locked.recordContentRead()
                return "must-not-run"
            }
            XCTFail("locked access must fail before private lookup")
        } catch {
            XCTAssertEqual(locked.events, ["gate"])
        }

        let presentation = try lockedCoordinator.availability(
            featureKey: "workspace.resume", policyEnabled: true,
            accessState: .locked(reason: .lockNow), protectedDataAvailable: true,
            workspaceKind: .real
        )
        XCTAssertEqual(presentation.reason, .appLocked)
        XCTAssertEqual(presentation.nextAction, .unlockApp)
        XCTAssertFalse(presentation.isAvailable)

        let support = FileManager.default.temporaryDirectory.appendingPathComponent(
            "c16-gates-\(UUID().uuidString.lowercased())", isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: support) }
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        let startupSteps = C16ReadCounter()
        let startup = StartupRouter(applicationSupportURL: support) { _ in startupSteps.increment() }
        let startupGate = C16AccessGate(state: .locked(reason: .lockNow))
        do { try await startup.startIfNeeded(accessGate: startupGate); XCTFail("startup read bypassed gate") }
        catch { XCTAssertEqual(startupSteps.value, 0) }

        let routeGate = C16AccessGate(state: .locked(reason: .lockNow))
        let route = RouteCoordinatorV1(registry: try RouteRegistryV1())
        let target = try NavigationTargetV1(workspaceID: WorkspaceID(rawValue: UUID()), destination: .today)
        do {
            _ = try await route.resolve(
                target,
                context: RouteResolutionContextV1(currentWorkspaceID: target.workspaceID, currentRevision: 0),
                accessGate: routeGate
            )
            XCTFail("route read bypassed gate")
        } catch { XCTAssertEqual(routeGate.surfaces, [.routeResolution]) }

        let searchSource = C16SearchProjectionProbe()
        let search = SearchCoordinatorV1(index: searchSource)
        let sourceRevision = try SearchSourceRevisionV1(
            workspaceID: target.workspaceID.rawValue, generationID: UUID(), commitRevision: 0
        )
        let searchPlan = try search.makePlan(query: "sign", sourceRevision: 0)
        let registry = try SwiftDataSearchCanonicalProjectionSourceV1.makeRegistry()
        let searchGate = C16AccessGate(state: .locked(reason: .lockNow))
        do { _ = try await search.search(searchPlan, source: sourceRevision, registry: registry, accessGate: searchGate); XCTFail("search read bypassed gate") }
        catch {
            let readCount = await searchSource.readCount
            XCTAssertEqual(readCount, 0)
        }

        let localIndex = try LocalSearchIndexStoreV1(applicationSupportURL: support)
        let rebuildSource = C16CanonicalSearchProbe(revision: sourceRevision)
        let rebuilder = try SearchIndexRebuildCoordinatorV1(
            store: localIndex, source: rebuildSource, registry: registry,
            privateSystemDiscoveryIndex: nil, privateSystemDiscoverySource: nil
        )
        let rebuildGate = C16AccessGate(state: .locked(reason: .lockNow))
        do { _ = try await rebuilder.rebuildIfNeeded(accessGate: rebuildGate); XCTFail("rebuild bypassed gate") }
        catch {
            let readCount = await rebuildSource.readCount
            XCTAssertEqual(readCount, 0)
        }

        let generationRoot = support.appendingPathComponent("FieldEvidenceData/generations/\(UUID().uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(at: generationRoot, withIntermediateDirectories: true)
        let importer = try BackupImportService(generationRootURL: generationRoot)
        let backupGate = C16AccessGate(state: .locked(reason: .lockNow))
        do { _ = try await importer.stageAndValidate(selectedPackageURL: support.appendingPathComponent("missing.fieldrecordbackup"), accessGate: backupGate); XCTFail("backup import bypassed gate") }
        catch { XCTAssertEqual(backupGate.surfaces, [.backupImport]) }

        let diagnosticReads = C16ReadCounter()
        let diagnostics = DiagnosticExportService(
            counters: { diagnosticReads.increment(); return .zero }, metricKit: { nil },
            app: { .init(build: "1", version: "1") }, device: { .init(model: "test", osVersion: "test") },
            clock: { self.date }
        )
        let diagnosticsGate = C16AccessGate(state: .locked(reason: .lockNow))
        do { _ = try await diagnostics.prepare(accessGate: diagnosticsGate); XCTFail("diagnostic read bypassed gate") }
        catch { XCTAssertEqual(diagnosticReads.value, 0) }

        let bulkFixture = try C16Fixture()
        defer { withExtendedLifetime(bulkFixture) {} }
        let bulk = try ImportBulkLifecycleAdapterV1(
            registrations: [try C16ImportRegistration.make()], modelContext: bulkFixture.context
        )
        let bulkGate = C16AccessGate(state: .locked(reason: .lockNow))
        do { _ = try await bulk.durableSession(sessionID: UUID(), accessGate: bulkGate); XCTFail("bulk read bypassed gate") }
        catch { XCTAssertEqual(bulkGate.surfaces, [.bulkImport]) }

        let reportFixture = try C16Fixture()
        let reportRoot = support.appendingPathComponent("FieldEvidenceData/generations/\(UUID().uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(at: reportRoot, withIntermediateDirectories: true)
        let renderer = try ReportRenderService(modelContext: reportFixture.context, generationRootURL: reportRoot)
        let reportGate = C16AccessGate(state: .locked(reason: .lockNow))
        do { _ = try await renderer.renderPendingReport(id: UUID(), accessGate: reportGate); XCTFail("report read bypassed gate") }
        catch { XCTAssertEqual(reportGate.events, ["gate"]) }
    }

    func testV23P04C16I01InterruptedInstallResumeIsIdempotent() async throws {
        let fixture = try C16Fixture(failOnceAt: .afterSaveBeforeReturn)
        let command = try fixture.command()
        XCTAssertThrowsError(try fixture.writer.commitWorkspaceExperience(command))
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<PracticeWorkspaceProvenanceRowV1>()), 1)

        try MutationReceiptRecoveryServiceV1(store: fixture.journal).recoverBeforeWriterActivation()
        let recovered = try fixture.lifecycle.replay(command)
        let replayed = try fixture.lifecycle.replay(command)
        XCTAssertEqual(recovered, replayed)
        XCTAssertEqual(recovered.mutationReceipt.mutationID, command.mutationID)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<PracticeWorkspaceProvenanceRowV1>()), 1)
        XCTAssertEqual(try fixture.lifecycle.provenance(), command.provenance)
        try recovered.validate(command: command)
        XCTAssertEqual(recovered.mutationReceipt.resultingRevision.workspaceRevision, 1)

        let pairs = try fixture.journal.workspaceExperienceRecoveryPairs()
            .filter { $0.command.mutationID == command.mutationID }
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs.first?.command, command)
        XCTAssertEqual(pairs.first?.receipt, recovered)

        let boundaries: [C16IngressHygieneFailureInjectionV1] = [
            .afterPrepare, .afterEffect, .afterReceipt,
        ]
        for (index, boundary) in boundaries.enumerated() {
            let support = FileManager.default.temporaryDirectory.appendingPathComponent(
                "c16-ingress-\(index)-\(UUID().uuidString.lowercased())", isDirectory: true
            )
            defer { try? FileManager.default.removeItem(at: support) }
            let operations = support.appendingPathComponent(
                OwnedStorageRootKindV1.operations.rawValue, isDirectory: true
            )
            let scratch = operations.appendingPathComponent("ScratchDataV1", isDirectory: true)
            let lease = scratch.appendingPathComponent(
                "capture-\(UUID().uuidString.lowercased())", isDirectory: true
            )
            try FileManager.default.createDirectory(at: lease, withIntermediateDirectories: true)
            try ProtectedFilePolicyV1.applyAndVerify(.stagingDirectory, at: lease)
            let old = date.addingTimeInterval(-172_800)
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: lease.path)
            let operationID = UUID()
            let interrupted = try OwnedStorageLedgerV1(
                applicationSupportURL: support, capacityProvider: { _ in 1_000_000 },
                ingressHygieneFailureInjection: boundary
            )
            let interruptedEffect = OwnedStorageLedgerProtectedIngressEffectV1(ledger: interrupted)
            do {
                _ = try await interruptedEffect.performBlindStartupHygieneEffect(
                    now: date, operationID: operationID
                )
                XCTFail("durable hygiene boundary \(index) must interrupt")
            } catch {
                XCTAssertEqual(error as? OwnedStorageLedgerFailureV1, .attemptCollision)
            }
            XCTAssertEqual(
                FileManager.default.fileExists(atPath: lease.path),
                boundary == .afterPrepare,
                "only the prepare interruption precedes the metadata-only removal effect"
            )

            let reopened = try OwnedStorageLedgerV1(
                applicationSupportURL: support, capacityProvider: { _ in 1_000_000 }
            )
            let reopenedEffect = OwnedStorageLedgerProtectedIngressEffectV1(ledger: reopened)
            let recoveredHygiene = try await reopenedEffect.performBlindStartupHygieneEffect(
                now: date, operationID: operationID
            )
            let readback = try await reopenedEffect.readBlindStartupHygieneReceiptEffect(
                operationID: operationID
            )
            let retry = try reopened.reconcileProtectedIngressHygiene(
                now: date, operationID: operationID
            )
            XCTAssertEqual(recoveredHygiene, readback)
            XCTAssertEqual(readback, retry)
            XCTAssertEqual(recoveredHygiene.removedKnownOwnedCount, 1)
            XCTAssertEqual(recoveredHygiene.inspectedCount, 1)
            XCTAssertFalse(recoveredHygiene.contentRead, "hygiene may inspect metadata only")
            XCTAssertFalse(FileManager.default.fileExists(atPath: lease.path))

            let prepareURL = operations
                .appendingPathComponent("ProtectedIngressReceiptsV1", isDirectory: true)
                .appendingPathComponent(
                    "hygiene-\(operationID.uuidString.lowercased()).prepare.json",
                    isDirectory: false
                )
            let prepareObject = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(contentsOf: prepareURL)) as? [String: Any]
            )
            XCTAssertEqual(prepareObject["finalized"] as? Bool, true)
        }
    }

    func testV23P04C16H02HygieneReceiptPersistenceRejectsHostileBytes() throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(
            "c16-hygiene-receipt-\(UUID().uuidString.lowercased())", isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: support) }
        let ledger = try OwnedStorageLedgerV1(
            applicationSupportURL: support, capacityProvider: { _ in 1_000_000 }
        )
        let operationID = UUID()
        let receipt = try ProtectedIngressStartupHygieneReceiptV1(
            operationID: operationID,
            inspectedCount: 3,
            removedKnownOwnedCount: 1,
            retainedValidCount: 1,
            deferredAmbiguousCount: 1,
            contentRead: false
        )
        try ledger.writeProtectedIngressHygieneReceipt(receipt)

        let receiptDirectory = support
            .appendingPathComponent(OwnedStorageRootKindV1.operations.rawValue, isDirectory: true)
            .appendingPathComponent("ProtectedIngressReceiptsV1", isDirectory: true)
        func receiptURL(_ id: UUID) -> URL {
            receiptDirectory.appendingPathComponent(
                "hygiene-\(id.uuidString.lowercased()).json", isDirectory: false
            )
        }
        let canonicalBytes = try CompatibilityCanonicalV1.encode(receipt)
        XCTAssertEqual(try Data(contentsOf: receiptURL(operationID)), canonicalBytes)

        let reopened = try OwnedStorageLedgerV1(
            applicationSupportURL: support, capacityProvider: { _ in 1_000_000 }
        )
        XCTAssertEqual(
            try reopened.readProtectedIngressHygieneReceipt(operationID: operationID),
            receipt
        )
        XCTAssertNoThrow(try ProtectedIngressStartupHygieneReceiptV1(
            operationID: UUID(),
            inspectedCount: ProtectedIngressStartupHygieneReceiptV1.maximumInspectedCount,
            removedKnownOwnedCount: ProtectedIngressStartupHygieneReceiptV1.maximumInspectedCount,
            retainedValidCount: 0,
            deferredAmbiguousCount: 0,
            contentRead: false
        ))
        XCTAssertThrowsError(try ProtectedIngressStartupHygieneReceiptV1(
            operationID: UUID(), inspectedCount: 2, removedKnownOwnedCount: 1,
            retainedValidCount: 0, deferredAmbiguousCount: 0, contentRead: false
        ))
        XCTAssertThrowsError(try ProtectedIngressStartupHygieneReceiptV1(
            operationID: UUID(), inspectedCount: 0, removedKnownOwnedCount: 0,
            retainedValidCount: 0, deferredAmbiguousCount: 0, contentRead: true
        ))
        XCTAssertThrowsError(try ProtectedIngressStartupHygieneReceiptV1(
            operationID: SettingsValidationV1.zeroUUID, inspectedCount: 0,
            removedKnownOwnedCount: 0, retainedValidCount: 0,
            deferredAmbiguousCount: 0, contentRead: false
        ))

        var unknownObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: canonicalBytes) as? [String: Any]
        )
        let unknownID = UUID()
        unknownObject["operationID"] = unknownID.uuidString
        unknownObject["unexpected"] = true
        try JSONSerialization.data(withJSONObject: unknownObject, options: [.sortedKeys])
            .write(to: receiptURL(unknownID), options: .atomic)
        XCTAssertThrowsError(
            try reopened.readProtectedIngressHygieneReceipt(operationID: unknownID)
        )

        let invalidCountID = UUID()
        var invalidCountObject = unknownObject
        invalidCountObject.removeValue(forKey: "unexpected")
        invalidCountObject["operationID"] = invalidCountID.uuidString
        invalidCountObject["inspectedCount"] = 2
        try JSONSerialization.data(withJSONObject: invalidCountObject, options: [.sortedKeys])
            .write(to: receiptURL(invalidCountID), options: .atomic)
        XCTAssertThrowsError(
            try reopened.readProtectedIngressHygieneReceipt(operationID: invalidCountID)
        )

        let contentReadID = UUID()
        var contentReadObject = invalidCountObject
        contentReadObject["operationID"] = contentReadID.uuidString
        contentReadObject["inspectedCount"] = 3
        contentReadObject["contentRead"] = true
        try JSONSerialization.data(withJSONObject: contentReadObject, options: [.sortedKeys])
            .write(to: receiptURL(contentReadID), options: .atomic)
        XCTAssertThrowsError(
            try reopened.readProtectedIngressHygieneReceipt(operationID: contentReadID)
        )

        let mismatchedID = UUID()
        try canonicalBytes.write(to: receiptURL(mismatchedID), options: .atomic)
        XCTAssertThrowsError(
            try reopened.readProtectedIngressHygieneReceipt(operationID: mismatchedID)
        )

        let oversizedID = UUID()
        let oversized = canonicalBytes + Data(repeating: 0x20, count: 4_097)
        try oversized.write(to: receiptURL(oversizedID), options: .atomic)
        XCTAssertThrowsError(
            try reopened.readProtectedIngressHygieneReceipt(operationID: oversizedID)
        )
    }

    func testV23P04C16R01BackupRestoreCloneAndReportRebuildPracticeState() throws {
        let fixture = try C16Fixture()
        let command = try fixture.command()
        _ = try fixture.writer.commitWorkspaceExperience(command)
        let snapshot = try PracticeWorkspaceBackupSnapshotV1(provenance: command.provenance)
        let bytes = try WorkspaceExperienceCanonicalCodecV1.data(snapshot)
        let decoded = try WorkspaceExperienceCanonicalCodecV1.decode(
            PracticeWorkspaceBackupSnapshotV1.self, from: bytes,
            validate: { try $0.validate() }
        )

        try fixture.lifecycle.eraseWorkspaceRows()
        try fixture.context.save()
        fixture.context.insert(try PracticeWorkspaceProvenanceRowV1(decoded.provenance))
        try fixture.context.save()
        XCTAssertEqual(try fixture.lifecycle.provenance(), command.provenance)
        XCTAssertTrue(WorkspaceExperienceLifecycleAdapterV1.replaceRestorePreservesExactProvenance)

        let support = FileManager.default.temporaryDirectory.appendingPathComponent(
            "c16-backup-\(UUID().uuidString.lowercased())", isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: support) }
        let generationRoot = support.appendingPathComponent(
            "FieldEvidenceData/generations/\(fixture.generationID.uuidString.lowercased())",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: generationRoot, withIntermediateDirectories: true)
        let exporter = BackupExportService(
            modelContext: fixture.context, generationRootURL: generationRoot,
            storagePreflight: StoragePreflightService(capacityProvider: { _ in .max }),
            now: { self.date }, appVersion: { "c16" }, appBuild: { "c16" }
        )
        let preview = try exporter.prepare()
        XCTAssertEqual(preview.signCount, 0)
        XCTAssertTrue(C50IncumbentFileExchangeBackupRestoreServiceBoundaryV1.validate(mode: .replaceExisting))
        XCTAssertTrue(C50IncumbentFileExchangeBackupRestoreServiceBoundaryV1.validate(mode: .clone))
        XCTAssertTrue(C50IncumbentFileExchangeBackupRestoreServiceBoundaryV1.validate(mode: .fork))
        try WorkspaceExperienceLifecycleAdapterV1(
            modelContext: fixture.context, workspaceID: WorkspaceID(rawValue: UUID())
        ).validateCloneOrForkDestinationIsReal()

        let practiceReport = try PracticeWorkspaceReportProjectionV1(
            workspaceID: fixture.workspaceID, provenance: command.provenance
        )
        let realReport = try PracticeWorkspaceReportProjectionV1(
            workspaceID: WorkspaceID(rawValue: UUID()), provenance: nil
        )
        XCTAssertEqual(practiceReport.kind, .practice)
        XCTAssertEqual(practiceReport.watermark, "PRACTICE — NOT FOR FIELD USE")
        XCTAssertEqual(realReport.kind, .real)
        XCTAssertNil(realReport.watermark)

        let product = try decodeResource("ProductChangeCatalogV1", as: ProductChangeCatalogReleaseV1.self)
        let guidance = try decodeResource("ContextualGuidanceCatalogV1", as: ContextualGuidanceCatalogV1.self)
        try product.validate(); try guidance.validate()
        XCTAssertEqual(product.catalogSHA256, "f674c4192e77688522e83f7a58207a54806185e64c941feb5e381e3d8f54d071")
        XCTAssertEqual(guidance.catalogSHA256, "43bc01b7147c9e733b8a1d0ea93efa6576ed117fb612bda566b82cd6d4986e3b")

        let corpus = try loadJSON(
            "V21P04C16WorkspaceExperienceCorpusV1",
            subdirectory: "Fixtures/V21/WorkspaceExperience"
        )
        XCTAssertEqual((corpus["hostile"] as? [String])?.count, 12)
        XCTAssertEqual((corpus["recovery"] as? [String])?.count, 4)
        XCTAssertEqual(Set(corpus["forbidden"] as? [String] ?? []).count, 7)
    }

    private func loadJSON(_ name: String, subdirectory: String? = nil) throws -> [String: Any] {
        let url = try resourceURL(name, subdirectory: subdirectory)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func decodeResource<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: Data(contentsOf: try resourceURL(name)))
    }

    private func resourceURL(_ name: String, subdirectory: String? = nil) throws -> URL {
        let bundle = Bundle(for: Self.self)
        return try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "json", subdirectory: subdirectory)
                ?? bundle.url(forResource: name, withExtension: "json")
                ?? Bundle.main.url(forResource: name, withExtension: "json", subdirectory: subdirectory)
                ?? Bundle.main.url(forResource: name, withExtension: "json")
        )
    }
}

private struct C16Clock: ApplicationClock {
    func now() -> Date { Date(timeIntervalSince1970: 1_777_593_601) }
}

private struct C16IDs: ApplicationIDSource {
    func makeID() -> UUID { UUID() }
}

private struct C16Files: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(mutationID: MutationIDV1, component: String) throws -> String {
        "mutation-staging/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

private final class C16AccessGate: AppAccessGatePortV1, @unchecked Sendable {
    private let mutex = NSLock()
    private var state: AppAccessStateV1
    private var recordedEvents: [String] = []
    private var recordedSurfaces: [AppAccessContentReadSurfaceV1] = []

    init(state: AppAccessStateV1) { self.state = state }
    var events: [String] { mutex.withLock { recordedEvents } }
    var surfaces: [AppAccessContentReadSurfaceV1] { mutex.withLock { recordedSurfaces } }
    func currentState() async -> AppAccessStateV1 { mutex.withLock { state } }
    func lock(reason: AppLockReasonV1) async { mutex.withLock { state = .locked(reason: reason) } }
    func authenticate(trigger: LocalAuthenticationTriggerV1) async -> LocalAuthenticationOutcomeV1 { .authenticated }
    func requireContentAccess() async throws {
        let permits = mutex.withLock { recordedEvents.append("gate"); return state.permitsContentAccess }
        guard permits else { throw WorkspaceExperienceFailureV1.permissionRequired }
    }
    func requireContentAccess(for surface: AppAccessContentReadSurfaceV1) async throws -> AppAccessContentPermitV1 {
        let snapshot = mutex.withLock {
            recordedEvents.append("gate")
            recordedSurfaces.append(surface)
            return state
        }
        return try AppAccessContentPermitV1(surface: surface, state: snapshot)
    }
    func recordContentRead() { mutex.withLock { recordedEvents.append("content") } }
}

private final class C16ReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    var value: Int { lock.withLock { storage } }
    func increment() { lock.withLock { storage += 1 } }
}

private actor C16SearchProjectionProbe: SearchIndexSnapshotProvidingV1 {
    private(set) var readCount = 0
    func projection(
        for source: SearchSourceRevisionV1,
        registry: SearchableFieldRegistryV1
    ) async throws -> SearchIndexProjectionV1 {
        readCount += 1
        throw SearchContractFailureV1.invalidRevision
    }
}

private actor C16CanonicalSearchProbe: SearchCanonicalProjectionSourceV1 {
    let revision: SearchSourceRevisionV1
    private(set) var readCount = 0
    init(revision: SearchSourceRevisionV1) { self.revision = revision }
    func currentSearchSourceRevision() async throws -> SearchSourceRevisionV1 {
        readCount += 1
        return revision
    }
    func searchProjectionPage(
        at source: SearchSourceRevisionV1,
        canonicalOffset: Int,
        limit: Int
    ) async throws -> SearchCanonicalProjectionPageV1 {
        readCount += 1
        return try .init(
            requestedCanonicalOffset: canonicalOffset,
            nextCanonicalOffset: canonicalOffset,
            isComplete: true,
            records: []
        )
    }
}

private enum C16ImportRegistration {
    static func make() throws -> ImportAdapterRegistrationV1 {
        try ImportAdapterRegistrationV1(
            adapterID: "c16_gate_probe", adapterVersion: 1,
            schemaReleaseID: "c16_gate_probe_schema", schemaRelease: 1,
            entityKinds: ImportEntityKindV1.allCases.sorted(),
            requiredSourceKeys: ["asset_key"], dependencyAdapterIDs: [],
            commandKinds: ImportCommandKindV1.allCases.sorted(),
            lifecycleDispositions: [
                .activeBulkSessionRecoverableOperationalState,
                .bulkCommitReceiptImmutableCanonicalAudit,
                .importedEntityUsesOrdinaryLifecycle,
            ],
            privacyClass: .localOperational, supportsDeterministicExport: true,
            fixtureSHA256s: [String(repeating: "a", count: 64)]
        )
    }
}

@MainActor
private final class C16Fixture {
    let container: ModelContainer
    let workspaceID = WorkspaceID(rawValue: UUID())
    let generationID = UUID()
    let context: ModelContext
    let journal: MutationJournalStoreV1
    let writer: WorkspaceWriterV1
    let lifecycle: WorkspaceExperienceLifecycleAdapterV1

    init(failOnceAt boundary: MutationJournalFaultBoundaryV1? = nil) throws {
        let schema = Schema(PersistentSchemaV51.models, version: PersistentSchemaV51.versionIdentifier)
        let configuration = ModelConfiguration(
            "C16WorkspaceExperience", schema: schema, isStoredInMemoryOnly: true,
            allowsSave: true, cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, migrationPlan: nil, configurations: [configuration])
        self.container = container
        context = container.mainContext; context.autosaveEnabled = false
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: workspaceID, replicaID: ReplicaID(rawValue: UUID())
        )
        journal = try MutationJournalStoreV1(
            modelContext: context, identity: identity, generationID: generationID,
            failureInjection: boundary.map { MutationJournalFailureInjectionV1(failOnceAt: $0) }
        )
        writer = try WorkspaceWriterV1(
            identity: identity, generationID: generationID,
            initialRevision: journal.currentRevision(writerInstanceID: UUID()),
            clock: C16Clock(), idSource: C16IDs(), fileAuthority: C16Files(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context), journalStore: journal
        )
        lifecycle = WorkspaceExperienceLifecycleAdapterV1(
            modelContext: context, workspaceID: workspaceID, workspaceWriter: writer
        )
    }

    func command() throws -> WorkspaceExperienceMutationCommandV1 {
        let mutationID = try MutationIDV1(rawValue: UUID())
        let template = try StarterWorkspaceTemplateReleaseV1(
            templateID: UUID(uuidString: "4B7E6B53-8022-4DF8-A275-C35128E22908")!,
            release: 1, titleKey: "workspace.starter.practice.title",
            packageReleaseIDs: ["shipping.illuminated-sign.v1"],
            practiceWatermark: "PRACTICE — NOT FOR FIELD USE"
        )
        let plan = try StarterWorkspaceInstallPlanV1(
            planID: UUID(), workspaceID: workspaceID, template: template,
            mutationID: mutationID, requestedAt: Date(timeIntervalSince1970: 1_777_593_600),
            explicitUserRequest: true, destinationWasEmpty: true
        )
        let current = try writer.currentRevision()
        let receipt = try StarterWorkspaceInstallReceiptV1(
            receiptID: UUID(), plan: plan,
            resultingWorkspaceRevision: current.revision + 1,
            installedAt: Date(timeIntervalSince1970: 1_777_593_601), disposition: .committed
        )
        let provenance = try PracticeWorkspaceProvenanceV1(
            provenanceID: UUID(), plan: plan, receipt: receipt, revision: 1
        )
        let identity = try WorkspaceEntityIdentityV1(
            kind: .practiceWorkspaceProvenance, id: provenance.provenanceID
        )
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: workspaceID, generationID: current.generationID,
            writerInstanceID: current.writerInstanceID, workspaceRevision: current.revision,
            entityRevisions: [try WorkspaceEntityRevisionV1(identity: identity, revision: 0)]
        )
        return WorkspaceExperienceMutationCommandV1(
            workspaceID: workspaceID, expectedRevision: try MutationPortableExpectedRevisionV1(expected),
            mutationID: mutationID, plan: plan, installReceipt: receipt, provenance: provenance
        )
    }
}

private struct C16PendingLoadTrap: ProtectedIngressDurableEffectPortV1 {
    let receipt: ProtectedIngressStartupHygieneReceiptV1

    func performBlindStartupHygieneEffect(now: Date, operationID: UUID) throws -> ProtectedIngressStartupHygieneReceiptV1 {
        guard operationID == receipt.operationID else { throw AppAccessContractFailureV1.effectMismatch }
        return receipt
    }
    func readBlindStartupHygieneReceiptEffect(operationID: UUID) throws -> ProtectedIngressStartupHygieneReceiptV1 {
        guard operationID == receipt.operationID else { throw AppAccessContractFailureV1.effectMismatch }
        return receipt
    }
    func loadPendingIntentsEffect() throws -> [PendingLockedExternalIntentV1] {
        throw AppAccessContractFailureV1.accessDenied
    }
    func stageContentBlindEffect(_ request: ProtectedIngressStageRequestV1, source: URL) throws -> PendingLockedExternalIntentV1 {
        throw AppAccessContractFailureV1.accessDenied
    }
    func replacePendingIntentEffect(expected: PendingLockedExternalIntentV1, replacement: PendingLockedExternalIntentV1) throws {
        throw AppAccessContractFailureV1.accessDenied
    }
    func removePendingIntentEffect(expected: PendingLockedExternalIntentV1, disposition: LockedIngressDispositionV1) throws {
        throw AppAccessContractFailureV1.accessDenied
    }
    func erasePendingIntentsEffect(operationID: UUID) throws {
        throw AppAccessContractFailureV1.accessDenied
    }
}

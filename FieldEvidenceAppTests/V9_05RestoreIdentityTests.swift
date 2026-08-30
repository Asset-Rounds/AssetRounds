import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

private enum C52ServiceRequestBoundary_V9_05RestoreIdentityTests {
    static let typedAnchor: C52ServiceRequestBoundaryTokenV1.Type = C52ServiceRequestBoundaryTokenV1.self
}

private enum C53AssetServiceReliabilityBoundary_V9_05RestoreIdentityTests {
    static let typedAnchor: C53AssetServiceReliabilityBoundaryTokenV1.Type = C53AssetServiceReliabilityBoundaryTokenV1.self
}

private final class C50RestoreIdentityTests: XCTestCase {
    func testV23P03C50ReplaceCloneAndForkNeverActivateOrReinterpretAdapterState() {
        for mode in BackupRestoreMode.allCases {
            XCTAssertTrue(C50IncumbentFileExchangeRestoreIdentityBoundaryV1.validate(mode))
            XCTAssertTrue(C50IncumbentFileExchangeBackupRestoreServiceBoundaryV1.validate(mode: mode))
        }
        XCTAssertFalse(C50IncumbentFileExchangeRestoreIdentityBoundaryV1.cloneForkCopiesSessionState)
        XCTAssertFalse(C50IncumbentFileExchangeRestoreIdentityBoundaryV1.cloneForkCopiesSecurityBookmarks)
        XCTAssertFalse(C50IncumbentFileExchangeRestoreIdentityBoundaryV1.cloneForkReinterpretsReleasedFiles)
        XCTAssertFalse(C50IncumbentFileExchangeBackupRestoreServiceBoundaryV1.cloneForkActivatesSourceProfile)
    }
}

private final class C45RestoreIdentityCompatibilityTests: XCTestCase {
    func testV23P03C45CompatibilityMakesCloneForkSnapshotsHistoricOnly() {
        XCTAssertEqual(AcceptedLabelSnapshotDispositionV1.activeSourceWorkspace.rawValue, "ACTIVE_SOURCE_WORKSPACE")
        XCTAssertEqual(AcceptedLabelSnapshotDispositionV1.historicCloneOrFork.rawValue, "HISTORIC_CLONE_OR_FORK")
        XCTAssertEqual(LabelReprintEligibilityV1.historicExportOnly.rawValue, "HISTORIC_EXPORT_ONLY")
    }
}

private final class C30EvidenceContextAnchorV9_05RestoreIdentity: XCTestCase {
    func testTypedEvidenceContextContractAnchor() throws {
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.persistentSchemaVersion, 30)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.recordsSchemaVersion, 29)
        XCTAssertEqual(EvidenceContextPersistenceEnrollmentV1.durableModelCount, 2)
        XCTAssertEqual(EvidenceLightingConditionV1.allCases.count, 6)
        XCTAssertTrue(WorkspaceWriterAdapterV1.activeSupportedCommandKinds.contains(.applyEvidenceContext))
        try EvidenceContextLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

final class V9_05RestoreIdentityTests: XCTestCase {
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
    func testV23P03C40CloneForkRebindPreservesIdentityAndRecomputesDigest() throws {
        let source = try C40BackupLifecycleTestValues.source(workspace: id(40_000))
        for destinationID in [id(40_001), id(40_002)] {
            let rebound = try source.rebound(to: WorkspaceID(rawValue: destinationID))
            XCTAssertEqual(rebound.releaseID, source.releaseID)
            XCTAssertEqual(rebound.sourceID, source.sourceID)
            XCTAssertEqual(rebound.revision, source.revision)
            XCTAssertEqual(rebound.workspaceID.rawValue, destinationID)
            XCTAssertNotEqual(rebound.releaseSHA256, source.releaseSHA256)
            XCTAssertEqual(
                try AuthorityCriterionCanonicalCodecV1.decode(
                    AuthoritySourceReleaseV1.self,
                    from: AuthorityCriterionCanonicalCodecV1.encode(rebound)
                ),
                rebound
            )
        }
    }

    func testV23P03C39RestoreRebindUsesTypedSemanticReleaseIdentity() throws {
        let source = AssetSemanticCompatibilityPolicyV1.exactReleaseOnly
        let bytes = try AssetSemanticCanonicalCodecV1.encode(source)
        let restored = try AssetSemanticCanonicalCodecV1.decode(
            AssetSemanticCompatibilityPolicyV1.self,
            from: bytes
        )
        XCTAssertEqual(restored, source)
        XCTAssertEqual(AssetProductIdentifierKindV1.serial.rawValue, "SERIAL")
    }

    private let fileManager = FileManager.default

    @MainActor
    func testV9_05G01GoldenEmptyReplaceCloneForkMatrix() async throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.authority, "V23-P01-C05")
        XCTAssertEqual(corpus.cases.count, 13)
        XCTAssertEqual(Set(corpus.cases.map(\.family)), ["G01", "A01", "H01", "I01", "R01"])
        XCTAssertEqual(Set(corpus.cases.filter { $0.family == "G01" }.compactMap(\.mode)), Set(BackupRestoreMode.allCases.map(\.rawValue)))

        for (offset, mode) in BackupRestoreMode.allCases.enumerated() {
            let scenario = try makeScenario("golden-\(mode.rawValue)", targetIsNonempty: mode == .replaceExisting)
            defer { try? fileManager.removeItem(at: scenario.root) }
            let oldWorkspace = scenario.target.session.workspaceID
            let oldReplica = scenario.target.session.replicaID
            let freshWorkspace = id(300 + offset * 10)
            let freshReplica = id(301 + offset * 10)
            let restored = try await restore(
                scenario,
                mode: mode,
                uuidValues: restoreUUIDs(mode: mode, newGeneration: id(200 + offset * 10), restoreID: id(201 + offset * 10), workspace: freshWorkspace, replica: freshReplica)
            )
            let pointer = try scenario.target.factory.currentGenerationPointerV3(expectedGenerationID: restored.generationID)
            XCTAssertEqual(pointer.workspaceID, canonical(restored.workspaceID.rawValue), mode.rawValue)
            XCTAssertEqual(pointer.replicaID, canonical(restored.replicaID.rawValue), mode.rawValue)
            XCTAssertNotEqual(restored.replicaID.rawValue, scenario.sourceReplicaID, mode.rawValue)
            switch mode {
            case .emptyInstall:
                XCTAssertEqual(restored.workspaceID.rawValue, scenario.sourceWorkspaceID)
                XCTAssertEqual(restored.replicaID.rawValue, freshReplica)
            case .replaceExisting:
                XCTAssertEqual(restored.workspaceID, oldWorkspace)
                XCTAssertEqual(restored.replicaID, oldReplica)
            case .clone, .fork:
                XCTAssertEqual(restored.workspaceID.rawValue, freshWorkspace)
                XCTAssertEqual(restored.replicaID.rawValue, freshReplica)
            }
            XCTAssertEqual(try recordIDs(in: restored), scenario.sourceRecordIDs, mode.rawValue)
            let restoredJournal = try MutationJournalStoreV1(
                modelContext: restored.modelContext,
                identity: restored.workspaceIdentity,
                generationID: restored.generationID
            )
            let historicReceipt = try XCTUnwrap(
                restoredJournal.receipt(mutationID: scenario.sourceMutationID),
                mode.rawValue
            )
            XCTAssertEqual(
                historicReceipt.identity.replicaID.rawValue,
                scenario.sourceReplicaID,
                mode.rawValue
            )
            XCTAssertEqual(
                try restoredJournal.exportSnapshot().quarantines,
                [scenario.sourceQuarantine],
                mode.rawValue
            )
            XCTAssertNil(try RestoreIntentStore(applicationSupportURL: scenario.target.support).load())
        }
    }

    @MainActor
    func testV9_05A01AlternateBoundedCollisionsAndCrossWorkspace() async throws {
        let clone = try makeScenario("collision-retry", targetIsNonempty: false)
        defer { try? fileManager.removeItem(at: clone.root) }
        let old = clone.target.session
        let validWorkspace = id(410)
        let validReplica = id(411)
        let restored = try await restore(
            clone,
            mode: .clone,
            uuidValues: [id(400), id(401), clone.sourceWorkspaceID, old.workspaceID.rawValue, validWorkspace, clone.sourceReplicaID, old.replicaID.rawValue, validReplica]
        )
        XCTAssertEqual(restored.workspaceID.rawValue, validWorkspace)
        XCTAssertEqual(restored.replicaID.rawValue, validReplica)
        XCTAssertEqual(try recordIDs(in: restored), clone.sourceRecordIDs)

        let replace = try makeScenario("cross-workspace-replace", targetIsNonempty: true)
        defer { try? fileManager.removeItem(at: replace.root) }
        let destinationWorkspace = replace.target.session.workspaceID
        let destinationReplica = replace.target.session.replicaID
        XCTAssertNotEqual(destinationWorkspace.rawValue, replace.sourceWorkspaceID)
        let replaced = try await restore(replace, mode: .replaceExisting, uuidValues: [id(420), id(421)])
        XCTAssertEqual(replaced.workspaceID, destinationWorkspace)
        XCTAssertEqual(replaced.replicaID, destinationReplica)
        XCTAssertEqual(try recordIDs(in: replaced), replace.sourceRecordIDs)
    }

    @MainActor
    func testV9_05H01HostileIdentityCollisionAndSourceReplicaReuse() async throws {
        let scenario = try makeScenario("source-replica-reuse", targetIsNonempty: false)
        defer { try? fileManager.removeItem(at: scenario.root) }
        let oldID = scenario.target.session.generationID
        let pointerBefore = try pointerBytes(in: scenario.target.support)
        let validated = try importArchive(scenario.archiveURL, into: scenario.target.session)
        let service = try BackupRestoreService(
            applicationSupportURL: scenario.target.support,
            storagePreflight: unlimitedStorage,
            makeUUID: sequence([id(500), id(501)] + Array(repeating: scenario.sourceReplicaID, count: 16))
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await service.restore(validatedPackage: validated, currentModelContext: scenario.target.session.modelContext, currentGenerationID: oldID, currentGenerationRootURL: scenario.target.session.generationRootURL, mode: .emptyInstall)
        } verify: { error in
            XCTAssertEqual(error as? BackupRestoreServiceError, .invalidRestoreAuthority)
        }
        XCTAssertEqual(try scenario.target.factory.currentGenerationID(), oldID)
        XCTAssertEqual(try pointerBytes(in: scenario.target.support), pointerBefore)
        XCTAssertNil(try RestoreIntentStore(applicationSupportURL: scenario.target.support).load())
        XCTAssertFalse(fileManager.fileExists(atPath: scenario.target.factory.installedGenerationURL(id: id(500)).path))
        XCTAssertNotEqual(scenario.target.session.replicaID.rawValue, scenario.sourceReplicaID)
    }

    @MainActor
    func testV9_05I01CrashPartialActivationCancellationAndLowStorage() async throws {
        let oldOutcome: Set<BackupRestoreFailurePoint> = [
            .beforePreparedWrite,
            .afterPreparedWrite,
            .beforeGenerationInstall,
            .afterGenerationInstall,
            .beforePointerSwitch,
        ]
        for (offset, point) in BackupRestoreFailurePoint.allCases.enumerated() {
            let scenario = try makeScenario("interrupt-\(offset)", targetIsNonempty: false)
            defer { try? fileManager.removeItem(at: scenario.root) }
            let oldID = scenario.target.session.generationID
            let newID = id(600 + offset * 10)
            let validated = try importArchive(scenario.archiveURL, into: scenario.target.session)
            let service = try BackupRestoreService(
                applicationSupportURL: scenario.target.support,
                storagePreflight: unlimitedStorage,
                makeUUID: sequence([newID, id(601 + offset * 10), id(602 + offset * 10)]),
                failureInjection: BackupRestoreFailureInjection(failOnceAt: point)
            )
            await XCTAssertThrowsErrorAsync {
                _ = try await service.restore(validatedPackage: validated, currentModelContext: scenario.target.session.modelContext, currentGenerationID: oldID, currentGenerationRootURL: scenario.target.session.generationRootURL, mode: .emptyInstall)
            } verify: { error in
                XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure, "\(point)")
            }
            let portableSidecarURL = scenario.target.support.appendingPathComponent(
                "FieldEvidenceRestore/portable-exchange-restore.json",
                isDirectory: false
            )
            if point == .beforePointerSwitch {
                XCTAssertTrue(fileManager.fileExists(atPath: portableSidecarURL.path))
                XCTAssertEqual(try scenario.target.factory.currentGenerationID(), oldID)
            } else if point == .afterPointerSwitch {
                XCTAssertTrue(fileManager.fileExists(atPath: portableSidecarURL.path))
                XCTAssertEqual(try scenario.target.factory.currentGenerationID(), newID)
            }
            let recovery = try BackupRestoreService(applicationSupportURL: scenario.target.support, storagePreflight: unlimitedStorage)
            let recovered = try recovery.reconcileAtStartup()
            let expectedID = oldOutcome.contains(point) ? oldID : newID
            XCTAssertEqual(try scenario.target.factory.currentGenerationID(), expectedID, "\(point)")
            if oldOutcome.contains(point) {
                XCTAssertNil(recovered, "\(point)")
                XCTAssertFalse(fileManager.fileExists(atPath: scenario.target.factory.installedGenerationURL(id: newID).path))
            } else {
                let session = try XCTUnwrap(recovered, "\(point)")
                XCTAssertEqual(session.generationID, newID, "\(point)")
                XCTAssertEqual(try recordIDs(in: session), scenario.sourceRecordIDs, "\(point)")
                XCTAssertNotEqual(session.replicaID.rawValue, scenario.sourceReplicaID, "\(point)")
            }
            XCTAssertNil(try recovery.reconcileAtStartup(), "\(point)")
            XCTAssertFalse(fileManager.fileExists(atPath: portableSidecarURL.path), "\(point)")
            let manifest = try StoreMigrationJournalStoreV1(
                applicationSupportURL: scenario.target.support
            ).loadManifestIfPresent(targetGenerationID: newID)
            if oldOutcome.contains(point) {
                XCTAssertNil(manifest, "\(point)")
            } else {
                let retained = try XCTUnwrap(manifest, "\(point)")
                let active = try scenario.target.factory
                    .currentGenerationPointerV3(expectedGenerationID: newID)
                XCTAssertEqual(retained.digest, active.generationManifestSHA256, "\(point)")
                XCTAssertEqual(retained.manifest.generationID, newID, "\(point)")
            }
            try assertNoRestoreResidue(
                in: scenario.target.support,
                point: "\(point)"
            )
        }

        let manifestFirst = try makeScenario(
            "manifest-first-rollback",
            targetIsNonempty: false
        )
        defer { try? fileManager.removeItem(at: manifestFirst.root) }
        let manifestOldID = manifestFirst.target.session.generationID
        let manifestNewID = id(750)
        let manifestValidated = try importArchive(
            manifestFirst.archiveURL,
            into: manifestFirst.target.session
        )
        let interrupted = try BackupRestoreService(
            applicationSupportURL: manifestFirst.target.support,
            storagePreflight: unlimitedStorage,
            makeUUID: sequence([manifestNewID, id(751), id(752)]),
            failureInjection: BackupRestoreFailureInjection(
                failOnceAt: .afterGenerationInstall
            )
        )
        await XCTAssertThrowsErrorAsync {
            _ = try await interrupted.restore(
                validatedPackage: manifestValidated,
                currentModelContext: manifestFirst.target.session.modelContext,
                currentGenerationID: manifestOldID,
                currentGenerationRootURL:
                    manifestFirst.target.session.generationRootURL,
                mode: .emptyInstall
            )
        } verify: { error in
            XCTAssertEqual(error as? BackupRestoreServiceError, .injectedFailure)
        }
        let intentStore = try RestoreIntentStore(
            applicationSupportURL: manifestFirst.target.support
        )
        let retainedIntent = try XCTUnwrap(try intentStore.load())
        XCTAssertEqual(retainedIntent.phase, .generationInstalled)
        let retainedIdentity = try XCTUnwrap(retainedIntent.identity)
        let authority = try manifestFirst.target.factory
            .makeRestoreGenerationAuthority()
        let beforeRemoval = try manifestFirst.target.factory.generationPresence(
            id: manifestNewID,
            authority: authority
        )
        XCTAssertTrue(beforeRemoval.installed)
        XCTAssertFalse(beforeRemoval.staging)
        XCTAssertEqual(
            try manifestFirst.target.factory.currentGenerationID(
                authority: authority
            ),
            manifestOldID
        )
        try manifestFirst.target.factory
            .removePreparedRestoreGenerationManifestBeforeDiscard(
                expectedOldID: manifestOldID,
                generationID: manifestNewID,
                expectedDigest:
                    retainedIdentity.targetPointer.generationManifestSHA256,
                authority: authority
            )
        XCTAssertNil(
            try StoreMigrationJournalStoreV1(
                applicationSupportURL: manifestFirst.target.support
            ).loadManifestIfPresent(targetGenerationID: manifestNewID)
        )
        XCTAssertTrue(
            try manifestFirst.target.factory.generationPresence(
                id: manifestNewID,
                authority: authority
            ).installed
        )

        let manifestRecovery = try BackupRestoreService(
            applicationSupportURL: manifestFirst.target.support,
            storagePreflight: unlimitedStorage
        )
        XCTAssertNil(try manifestRecovery.reconcileAtStartup())
        XCTAssertEqual(
            try manifestFirst.target.factory.currentGenerationID(),
            manifestOldID
        )
        XCTAssertFalse(
            fileManager.fileExists(
                atPath: manifestFirst.target.factory
                    .installedGenerationURL(id: manifestNewID).path
            )
        )
        XCTAssertNil(try intentStore.load())
        try assertNoRestoreResidue(
            in: manifestFirst.target.support,
            point: "manifest-first-rollback"
        )

        let absent = try await makeManifestAbsentCrash(
            "manifest-absent-target-absent",
            newID: id(760)
        )
        defer { try? fileManager.removeItem(at: absent.scenario.root) }
        try absent.scenario.target.factory.removeInstalledGeneration(
            id: absent.newID,
            keeping: absent.oldID,
            authority: absent.authority
        )
        XCTAssertFalse(
            fileManager.fileExists(
                atPath: absent.scenario.target.factory
                    .installedGenerationURL(id: absent.newID).path
            )
        )
        XCTAssertNotNil(try absent.intentStore.load())
        let absentRecovery = try BackupRestoreService(
            applicationSupportURL: absent.scenario.target.support,
            storagePreflight: unlimitedStorage
        )
        XCTAssertNil(try absentRecovery.reconcileAtStartup())
        XCTAssertEqual(
            try absent.scenario.target.factory.currentGenerationID(),
            absent.oldID
        )
        XCTAssertNil(try absent.intentStore.load())
        try assertNoRestoreResidue(
            in: absent.scenario.target.support,
            point: "manifest-absent-target-absent"
        )

        let partial = try await makeManifestAbsentCrash(
            "manifest-absent-target-partial",
            newID: id(770)
        )
        defer { try? fileManager.removeItem(at: partial.scenario.root) }
        let partialRoot = partial.scenario.target.factory
            .installedGenerationURL(id: partial.newID)
        let removedModel = partialRoot.appendingPathComponent("model.sqlite")
        try fileManager.removeItem(at: removedModel)
        XCTAssertTrue(fileManager.fileExists(atPath: partialRoot.path))
        XCTAssertFalse(fileManager.fileExists(atPath: removedModel.path))
        XCTAssertNotNil(try partial.intentStore.load())
        let partialRecovery = try BackupRestoreService(
            applicationSupportURL: partial.scenario.target.support,
            storagePreflight: unlimitedStorage
        )
        XCTAssertNil(try partialRecovery.reconcileAtStartup())
        XCTAssertEqual(
            try partial.scenario.target.factory.currentGenerationID(),
            partial.oldID
        )
        XCTAssertFalse(fileManager.fileExists(atPath: partialRoot.path))
        XCTAssertNil(try partial.intentStore.load())
        try assertNoRestoreResidue(
            in: partial.scenario.target.support,
            point: "manifest-absent-target-partial"
        )

        let cancelled = try makeScenario("cancelled", targetIsNonempty: false)
        defer { try? fileManager.removeItem(at: cancelled.root) }
        let cancelledValidated = try importArchive(cancelled.archiveURL, into: cancelled.target.session)
        let cancelledID = cancelled.target.session.generationID
        let task = Task {
            try await BackupRestoreService(applicationSupportURL: cancelled.target.support, storagePreflight: unlimitedStorage).restore(
                validatedPackage: cancelledValidated,
                currentModelContext: cancelled.target.session.modelContext,
                currentGenerationID: cancelledID,
                currentGenerationRootURL: cancelled.target.session.generationRootURL,
                mode: .emptyInstall
            )
        }
        task.cancel()
        await XCTAssertThrowsErrorAsync { _ = try await task.value } verify: { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(try cancelled.target.factory.currentGenerationID(), cancelledID)
        try BackupImportService(generationRootURL: cancelled.target.session.generationRootURL, storagePreflight: unlimitedStorage, scopedAccess: .alreadyAuthorized).discard(cancelledValidated)

        let low = try makeScenario("low-storage", targetIsNonempty: false)
        defer { try? fileManager.removeItem(at: low.root) }
        let lowValidated = try importArchive(low.archiveURL, into: low.target.session)
        let lowID = low.target.session.generationID
        let lowService = try BackupRestoreService(applicationSupportURL: low.target.support, storagePreflight: StoragePreflightService(capacityProvider: { _ in 0 }))
        await XCTAssertThrowsErrorAsync {
            _ = try await lowService.restore(validatedPackage: lowValidated, currentModelContext: low.target.session.modelContext, currentGenerationID: lowID, currentGenerationRootURL: low.target.session.generationRootURL, mode: .emptyInstall)
        } verify: { error in
            guard let storage = error as? StoragePreflightError,
                  case .insufficientCapacity = storage else {
                return XCTFail("Unexpected low-storage error \(error)")
            }
        }
        XCTAssertEqual(try low.target.factory.currentGenerationID(), lowID)
        XCTAssertNil(try RestoreIntentStore(applicationSupportURL: low.target.support).load())
        try BackupImportService(generationRootURL: low.target.session.generationRootURL, storagePreflight: unlimitedStorage, scopedAccess: .alreadyAuthorized).discard(lowValidated)
    }

    @MainActor
    func testV9_05R01RecoveryRelaunchAndExportReconciliation() async throws {
        let scenario = try makeScenario("relaunch-export", targetIsNonempty: false)
        defer { try? fileManager.removeItem(at: scenario.root) }
        let restored = try await restore(scenario, mode: .fork, uuidValues: [id(800), id(801), id(802), id(803)])
        let secondLaunch = try scenario.target.factory.openOrBootstrapCurrent()
        XCTAssertEqual(secondLaunch.generationID, restored.generationID)
        XCTAssertEqual(secondLaunch.workspaceIdentity, restored.workspaceIdentity)
        let recovery = try BackupRestoreService(applicationSupportURL: scenario.target.support, storagePreflight: unlimitedStorage)
        XCTAssertNil(try recovery.reconcileAtStartup())

        let exportDirectory = scenario.root.appendingPathComponent("reconciled-export", isDirectory: true)
        try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: false)
        let exporter = BackupExportService(
            modelContext: secondLaunch.modelContext,
            generationRootURL: secondLaunch.generationRootURL,
            storagePreflight: unlimitedStorage,
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            makeUUID: sequence([id(810), id(811), id(812), id(813)])
        )
        let preview = try exporter.prepareStreaming()
        let archive = try exporter.exportStreaming(previewID: preview.id, to: exportDirectory)
        let verification = try makeHarness(at: scenario.root, name: "verification", nonempty: false)
        let validated = try importArchive(archive, into: verification.session)
        let pointer = try scenario.target.factory.currentGenerationPointerV3(expectedGenerationID: secondLaunch.generationID)
        XCTAssertEqual(validated.manifest.backupSchemaVersion, 4)
        XCTAssertEqual(validated.manifest.source.persistentSchemaVersion, 8)
        XCTAssertEqual(validated.manifest.source.recordsSchemaVersion, 7)
        XCTAssertEqual(
            validated.records.requirementAssurance.count,
            validated.records.workflowRecords.count
        )
        XCTAssertTrue(validated.records.requirementAssurance.allSatisfy {
            (try? $0.snapshot().workspaceID) == secondLaunch.workspaceIdentity.workspaceID.rawValue
        })
        XCTAssertTrue(validated.records.savedSmartViews.isEmpty)
        XCTAssertNotNil(validated.records.mutationHistory)
        XCTAssertEqual(validated.manifest.source.workspaceID?.uuidString.lowercased(), pointer.workspaceID)
        XCTAssertEqual(validated.manifest.source.replicaID?.uuidString.lowercased(), pointer.replicaID)
        XCTAssertNotEqual(validated.manifest.source.replicaID, scenario.sourceReplicaID)
        XCTAssertEqual(Set(validated.records.sites.map(\.id) + validated.records.assets.map(\.id)), scenario.sourceRecordIDs)
        try BackupImportService(generationRootURL: verification.session.generationRootURL, storagePreflight: unlimitedStorage, scopedAccess: .alreadyAuthorized).discard(validated)
        try assertNoRestoreResidue(in: scenario.target.support, point: "relaunch")

        let legacySource = try makeHarness(
            at: scenario.root,
            name: "legacy-records1-source",
            nonempty: true
        )
        let legacyDestination = scenario.root.appendingPathComponent(
            "legacy-records1-export",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: legacyDestination,
            withIntermediateDirectories: false
        )
        let legacyExporter = BackupExportService(
            modelContext: legacySource.session.modelContext,
            generationRootURL: legacySource.session.generationRootURL,
            storagePreflight: unlimitedStorage,
            now: { Date(timeIntervalSince1970: 1_800_000_100) },
            makeUUID: sequence([id(820), id(821), id(822), id(823)])
        )
        let legacyPreview = try legacyExporter.prepareCompatibilityFixtureLegacyDirectoryPackage()
        let legacyArchive = try legacyExporter.exportCompatibilityFixtureLegacyDirectoryPackage(
            previewID: legacyPreview.id,
            to: legacyDestination
        )
        let legacyTarget = try makeHarness(
            at: scenario.root,
            name: "legacy-records1-target",
            nonempty: false
        )
        let legacyValidated = try importArchive(legacyArchive, into: legacyTarget.session)
        XCTAssertEqual(legacyValidated.manifest.backupSchemaVersion, 1)
        XCTAssertEqual(legacyValidated.manifest.source.recordsSchemaVersion, 1)
        XCTAssertNil(legacyValidated.records.mutationHistory)
        let legacyRestore = try BackupRestoreService(
            applicationSupportURL: legacyTarget.support,
            storagePreflight: unlimitedStorage,
            makeUUID: sequence((830..<850).map { id($0) })
        )
        var legacyRestored: StoreGenerationSession? = try await legacyRestore.restore(
            validatedPackage: legacyValidated,
            currentModelContext: legacyTarget.session.modelContext,
            currentGenerationID: legacyTarget.session.generationID,
            currentGenerationRootURL: legacyTarget.session.generationRootURL,
            mode: .emptyInstall
        )
        var legacyCoordinator: StoreSessionCoordinator? = StoreSessionCoordinator(
            session: legacyTarget.session
        )
        try XCTUnwrap(legacyCoordinator).activate(session: try XCTUnwrap(legacyRestored))
        XCTAssertEqual(
            try XCTUnwrap(legacyRestored).modelContext.fetchCount(
                FetchDescriptor<WorkspaceMutationStateRow>()
            ),
            1
        )
        XCTAssertEqual(
            try legacyTarget.factory.currentGenerationPointerV3(
                expectedGenerationID: try XCTUnwrap(legacyRestored).generationID
            ).storeSchemaVersion,
            4
        )
        XCTAssertNoThrow(try XCTUnwrap(legacyCoordinator).workspaceWriter.currentRevision())
        let legacyGenerationID = try XCTUnwrap(legacyRestored).generationID
        let legacyIdentity = try XCTUnwrap(legacyRestored).workspaceIdentity
        legacyCoordinator = nil
        legacyRestored = nil
        let legacyReopened = try legacyTarget.factory.openOrBootstrapCurrent()
        XCTAssertEqual(legacyReopened.generationID, legacyGenerationID)
        XCTAssertEqual(legacyReopened.workspaceIdentity, legacyIdentity)
        XCTAssertEqual(
            try legacyReopened.modelContext.fetchCount(
                FetchDescriptor<WorkspaceMutationStateRow>()
            ),
            1
        )
        let legacyJournal = try MutationJournalStoreV1(
            modelContext: legacyReopened.modelContext,
            identity: legacyReopened.workspaceIdentity,
            generationID: legacyReopened.generationID,
            allowStateBootstrap: false
        )
        XCTAssertNoThrow(
            try MutationReceiptRecoveryServiceV1(store: legacyJournal)
                .recoverBeforeWriterActivation()
        )
    }

    func testV23P03C38RestoreRebindPreservesWorkspaceAndNeverClaimsIdentity() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = root.appendingPathComponent(
            "FieldEvidenceAppTests/Fixtures/V21/Accountability/V21P03C38PartyAccountabilityCorpusV1.json"
        )
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any]
        )
        let claims = try XCTUnwrap(fixture["claims"] as? [String: Any])
        XCTAssertTrue(claims.values.allSatisfy { ($0 as? Bool) == false })

        let restoreSource = try String(
            contentsOf: root.appendingPathComponent(
                "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(restoreSource.contains("rebindingPartyAccountability"))
        XCTAssertTrue(restoreSource.contains("records.partyAccountability"))
        XCTAssertTrue(restoreSource.contains("workspaceID"))
        XCTAssertTrue(restoreSource.contains("PartyAccountabilitySnapshotCodecV1.decode"))
        XCTAssertFalse(restoreSource.contains("identityVerified = true"))
        XCTAssertFalse(restoreSource.contains("legalSignature = true"))
    }
}

private final class C27V905TypedLocatorAnchorTests: XCTestCase {
    func testAssetLocatorContractAnchor() throws {
        XCTAssertEqual(ExternalKeyNormalizationV1.allCases.count, 2)
        XCTAssertEqual(LocatorBindingActionV1.allCases.count, 6)
        XCTAssertFalse(AssetLocatorLifecycleAdapterV1.resolutionStartsWork)
    }
}

extension V9_05RestoreIdentityTests {
    func testC24AccessibleDocumentTypedAnchor() throws {
        XCTAssertEqual(AccessibleDocumentSemanticTreeV1.schemaVersion, 1)
        XCTAssertEqual(AccessibleDocumentRoleV1.allCases.count, 13)
        XCTAssertEqual(AccessibleDocumentAssessmentStateV1.allCases.count, 4)
        XCTAssertFalse(AccessibleDocumentLifecycleV1.pdfUAClaimed)
    }
}

extension V9_05RestoreIdentityTests {
    func testC22RecoverabilityVerificationAnchor() throws {
        XCTAssertEqual(RecoverabilityVerificationReceiptV1.schemaVersion, 1)
        try V21RecoverabilityImportBoundaryV1.validate(persistentSchemaVersion: 21, recordsSchemaVersion: 20)
        XCTAssertFalse(RecoverabilityVerificationLifecycleV1.liveRestorePermitted)
        XCTAssertEqual(RecoverabilityVerificationLifecycleV1.backupEligibility, "SUBSEQUENT_BACKUPS_ONLY")
    }
}

extension V9_05RestoreIdentityTests {
    func testV23P03C36CloneDraftIdentityMappingIsDeterministicAndNamespaced() throws {
        let source=UUID(),workspace=UUID()
        let pointer=RestorePointerIdentityV1(generationID:UUID(),generationManifestSHA256:String(repeating:"a",count:64),workspaceID:workspace,replicaID:UUID())
        let identity=RestoreIdentityV1(mode:.clone,source:.init(workspaceID:UUID(),replicaID:UUID()),oldPointer:pointer,targetPointer:pointer,recordIdentityDisposition:.preserve)
        XCTAssertEqual(identity.destinationFieldDraftID(for:source,namespace:"stage"),identity.destinationFieldDraftID(for:source,namespace:"stage"))
        XCTAssertNotEqual(identity.destinationFieldDraftID(for:source,namespace:"stage"),identity.destinationFieldDraftID(for:source,namespace:"draft"))
    }
}

extension V9_05RestoreIdentityTests {
    func testV23P03C15RestoreRebindPreservesPacketIdentity() throws {
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 150_105)
        let restored = try WorkPacketManifestRow(fixture.manifest).value()
        let rebound = try restored.rebound(to: fixture.otherWorkspaceID)
        XCTAssertEqual(rebound.manifestID, fixture.manifest.manifestID)
        XCTAssertEqual(rebound.packetID, fixture.manifest.packetID)
        XCTAssertEqual(rebound.workspaceID, fixture.otherWorkspaceID)
        XCTAssertNotEqual(rebound.manifestSHA256, fixture.manifest.manifestSHA256)
    }
}

enum C40BackupLifecycleTestValues {
    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }

    static func source(
        workspace: UUID = id(90_000),
        releaseID: UUID = id(90_001),
        supersedes: UUID? = nil,
        revision: UInt64 = 1
    ) throws -> AuthoritySourceReleaseV1 {
        try AuthoritySourceReleaseV1(
            releaseID: releaseID,
            workspaceID: WorkspaceID(rawValue: workspace),
            sourceID: id(90_002),
            sourceType: .adoptedRule,
            designation: "Recorded authority source",
            editionOrRevision: "2026",
            retrievedAt: Date(timeIntervalSince1970: 1_788_000_000),
            licenseStorageDisposition: .metadataAndLocatorOnly,
            supersedesReleaseID: supersedes,
            recordedAt: Date(timeIntervalSince1970: 1_788_000_001),
            revision: revision,
            mutationID: MutationIDV1(rawValue: id(90_003))
        )
    }

    static func record(_ value: AuthoritySourceReleaseV1) throws -> V11BackupAuthorityCriterionRecordV1 {
        .init(
            kind: .authoritySourceRelease,
            id: value.releaseID,
            workspaceID: value.workspaceID.rawValue,
            canonicalData: try AuthorityCriterionCanonicalCodecV1.encode(value)
        )
    }

    static func records(_ values: [AuthoritySourceReleaseV1]) throws -> V4BackupRecordsV1 {
        V4BackupRecordsV1(
            authorityCriterion: try values.map(record).sorted { $0.id.uuidString < $1.id.uuidString },
            assets: [], evidenceFiles: [], issues: [], packets: [], recordsSchemaVersion: 10,
            reports: [], sites: [], workflowRecords: []
        )
    }
}

private extension V9_05RestoreIdentityTests {
    struct Harness { let support: URL; let factory: StoreGenerationFactory; let session: StoreGenerationSession }
    struct Scenario {
        let root: URL
        let target: Harness
        let archiveURL: URL
        let sourceWorkspaceID: UUID
        let sourceReplicaID: UUID
        let sourceRecordIDs: Set<UUID>
        let sourceMutationID: MutationIDV1
        let sourceQuarantine: MutationHistoryQuarantineRecordV1
    }
    struct ManifestAbsentCrash {
        let scenario: Scenario
        let oldID: UUID
        let newID: UUID
        let intentStore: RestoreIntentStore
        let authority: StoreRestoreGenerationAuthority
    }
    struct Corpus: Decodable {
        struct Case: Decodable { let id: String; let family: String; let mode: String? }
        let schemaVersion: Int
        let authority: String
        let cases: [Case]
    }

    var unlimitedStorage: StoragePreflightService { StoragePreflightService(capacityProvider: { _ in .max }) }

    @MainActor
    func makeScenario(
        _ name: String,
        targetIsNonempty: Bool,
        sourceSiteAddress: String? = nil
    ) throws -> Scenario {
        let root = fileManager.temporaryDirectory.appendingPathComponent("V9_05-\(name)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        let source = try makeHarness(
            at: root,
            name: "source",
            nonempty: true,
            siteAddress: sourceSiteAddress
        )
        let sourceRecordIDs = try recordIDs(in: source.session)
        let sourceSiteID = try XCTUnwrap(
            try source.session.modelContext.fetch(FetchDescriptor<Site>()).first?.id
        )
        let sourceMutationID = try MutationIDV1(rawValue: id(89))
        let writer = StoreSessionCoordinator(session: source.session).workspaceWriter
        let before = try writer.currentRevision()
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: before.workspaceID,
            generationID: before.generationID,
            writerInstanceID: before.writerInstanceID,
            workspaceRevision: before.revision,
            entityRevisions: [.init(
                identity: try WorkspaceEntityIdentityV1(kind: .site, id: sourceSiteID),
                revision: 0
            )]
        )
        let sourceRequest = WorkspaceMutationRequestV1(
            mutationID: sourceMutationID,
            expectedRevision: expected,
            command: .updateSiteTimeZone(.init(
                siteID: sourceSiteID,
                timeZoneID: "UTC",
                confirmedAt: Date(timeIntervalSince1970: 1_799_999_010)
            ))
        )
        _ = try writer.execute(sourceRequest)
        let conflictingRequest = WorkspaceMutationRequestV1(
            mutationID: sourceMutationID,
            expectedRevision: expected,
            command: .updateSiteTimeZone(.init(
                siteID: sourceSiteID,
                timeZoneID: "Europe/Paris",
                confirmedAt: Date(timeIntervalSince1970: 1_799_999_011)
            ))
        )
        XCTAssertThrowsError(try writer.execute(conflictingRequest)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        let sourceJournal = try MutationJournalStoreV1(
            modelContext: source.session.modelContext,
            identity: source.session.workspaceIdentity,
            generationID: source.session.generationID,
            allowStateBootstrap: false
        )
        let sourceQuarantine = try XCTUnwrap(
            try sourceJournal.exportSnapshot().quarantines.first
        )
        XCTAssertEqual(sourceQuarantine.identityDomain, .mutationEnvelope)
        let destination = root.appendingPathComponent("source-export", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        let exporter = BackupExportService(
            modelContext: source.session.modelContext,
            generationRootURL: source.session.generationRootURL,
            storagePreflight: unlimitedStorage,
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            makeUUID: sequence([id(90), id(91), id(92), id(93)])
        )
        let preview = try exporter.prepareStreaming()
        let archive = try exporter.exportStreaming(previewID: preview.id, to: destination)
        let target = try makeHarness(at: root, name: "target", nonempty: targetIsNonempty)
        return Scenario(root: root, target: target, archiveURL: archive, sourceWorkspaceID: source.session.workspaceID.rawValue, sourceReplicaID: source.session.replicaID.rawValue, sourceRecordIDs: sourceRecordIDs, sourceMutationID: sourceMutationID, sourceQuarantine: sourceQuarantine)
    }

    @MainActor
    func makeHarness(
        at root: URL,
        name: String,
        nonempty: Bool,
        siteAddress: String? = nil
    ) throws -> Harness {
        let support = root.appendingPathComponent("\(name)-support", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        let factory = StoreGenerationFactory(applicationSupportURL: support)
        let session = try factory.openOrBootstrapCurrent()
        if nonempty {
            let siteID = UUID()
            session.modelContext.insert(Site(id: siteID, label: "\(name) lot", address: siteAddress, timeZoneID: "America/New_York", createdAt: Date(timeIntervalSince1970: 1_799_999_000)))
            session.modelContext.insert(Asset(id: UUID(), siteID: siteID, packID: SignPack.illuminatedSignV1.packID, packSchemaVersion: SignPack.illuminatedSignV1.schemaVersion, packContentVersion: SignPack.illuminatedSignV1.contentVersion, label: "\(name) sign", createdAt: Date(timeIntervalSince1970: 1_799_999_001)))
            try session.modelContext.save()
        }
        return Harness(support: support, factory: factory, session: session)
    }

    @MainActor
    func importArchive(_ archive: URL, into session: StoreGenerationSession) throws -> ValidatedV4BackupPackageV1 {
        try BackupImportService(generationRootURL: session.generationRootURL, storagePreflight: unlimitedStorage, makeUUID: { self.id(99) }, scopedAccess: .alreadyAuthorized).stageAndValidate(selectedPackageURL: archive)
    }

    @MainActor
    func restore(_ scenario: Scenario, mode: BackupRestoreMode, uuidValues: [UUID]) async throws -> StoreGenerationSession {
        let validated = try importArchive(scenario.archiveURL, into: scenario.target.session)
        return try await BackupRestoreService(applicationSupportURL: scenario.target.support, storagePreflight: unlimitedStorage, makeUUID: sequence(uuidValues)).restore(
            validatedPackage: validated,
            currentModelContext: scenario.target.session.modelContext,
            currentGenerationID: scenario.target.session.generationID,
            currentGenerationRootURL: scenario.target.session.generationRootURL,
            mode: mode
        )
    }

    @MainActor
    func makeManifestAbsentCrash(
        _ name: String,
        newID: UUID
    ) async throws -> ManifestAbsentCrash {
        let scenario = try makeScenario(name, targetIsNonempty: false)
        let oldID = scenario.target.session.generationID
        let validated = try importArchive(
            scenario.archiveURL,
            into: scenario.target.session
        )
        let service = try BackupRestoreService(
            applicationSupportURL: scenario.target.support,
            storagePreflight: unlimitedStorage,
            makeUUID: sequence([newID, id(790), id(791)]),
            failureInjection: BackupRestoreFailureInjection(
                failOnceAt: .afterGenerationInstall
            )
        )
        do {
            _ = try await service.restore(
                validatedPackage: validated,
                currentModelContext: scenario.target.session.modelContext,
                currentGenerationID: oldID,
                currentGenerationRootURL:
                    scenario.target.session.generationRootURL,
                mode: .emptyInstall
            )
            XCTFail("Expected afterGenerationInstall interruption")
        } catch {
            XCTAssertEqual(
                error as? BackupRestoreServiceError,
                .injectedFailure
            )
        }
        let intentStore = try RestoreIntentStore(
            applicationSupportURL: scenario.target.support
        )
        let intent = try XCTUnwrap(try intentStore.load())
        XCTAssertEqual(intent.phase, .generationInstalled)
        let identity = try XCTUnwrap(intent.identity)
        let authority = try scenario.target.factory
            .makeRestoreGenerationAuthority()
        XCTAssertEqual(
            try scenario.target.factory.currentGenerationID(
                authority: authority
            ),
            oldID
        )
        let presence = try scenario.target.factory.generationPresence(
            id: newID,
            authority: authority
        )
        XCTAssertTrue(presence.installed)
        XCTAssertFalse(presence.staging)
        try scenario.target.factory
            .removePreparedRestoreGenerationManifestBeforeDiscard(
                expectedOldID: oldID,
                generationID: newID,
                expectedDigest:
                    identity.targetPointer.generationManifestSHA256,
                authority: authority
            )
        XCTAssertNil(
            try StoreMigrationJournalStoreV1(
                applicationSupportURL: scenario.target.support
            ).loadManifestIfPresent(targetGenerationID: newID)
        )
        return ManifestAbsentCrash(
            scenario: scenario,
            oldID: oldID,
            newID: newID,
            intentStore: intentStore,
            authority: authority
        )
    }

    func restoreUUIDs(mode: BackupRestoreMode, newGeneration: UUID, restoreID: UUID, workspace: UUID, replica: UUID) -> [UUID] {
        switch mode {
        case .emptyInstall: [newGeneration, restoreID, replica]
        case .replaceExisting: [newGeneration, restoreID]
        case .clone, .fork: [newGeneration, restoreID, workspace, replica]
        }
    }

    @MainActor
    func recordIDs(in session: StoreGenerationSession) throws -> Set<UUID> {
        let sites = try session.modelContext.fetch(FetchDescriptor<Site>()).map(\.id)
        let assets = try session.modelContext.fetch(FetchDescriptor<Asset>()).map(\.id)
        return Set(sites + assets)
    }

    func pointerBytes(in support: URL) throws -> Data { try Data(contentsOf: support.appendingPathComponent("FieldEvidenceData/current.json")) }

    func assertNoRestoreResidue(in support: URL, point: String, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertNil(try RestoreIntentStore(applicationSupportURL: support).load(), point, file: file, line: line)
        let restore = support.appendingPathComponent("FieldEvidenceRestore", isDirectory: true)
        XCTAssertFalse(
            fileManager.fileExists(
                atPath: restore.appendingPathComponent("restore.json").path
            ),
            point,
            file: file,
            line: line
        )
        if fileManager.fileExists(atPath: restore.path) {
            let allowed = Set(["generations", "staging"])
            let children = Set(try fileManager.contentsOfDirectory(atPath: restore.path))
            XCTAssertTrue(children.isSubset(of: allowed), point, file: file, line: line)
            for name in children {
                XCTAssertEqual(
                    try fileManager.contentsOfDirectory(
                        atPath: restore.appendingPathComponent(name).path
                    ),
                    [],
                    point,
                    file: file,
                    line: line
                )
            }
        }
    }

    func sequence(_ values: [UUID]) -> () -> UUID {
        var remaining = values
        return { remaining.isEmpty ? UUID() : remaining.removeFirst() }
    }

    func loadCorpus() throws -> Corpus {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "V21P01C05IdentityTransformationsV1", withExtension: "json", subdirectory: "Fixtures/V21/Restore") ?? bundle.url(forResource: "V21P01C05IdentityTransformationsV1", withExtension: "json"))
        return try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
    }

    func id(_ suffix: Int) -> UUID { UUID(uuidString: String(format: "66000000-0000-0000-0000-%012d", suffix))! }
    func canonical(_ value: UUID) -> String { value.uuidString.lowercased() }

    @MainActor
    func XCTAssertThrowsErrorAsync(_ expression: () async throws -> Void, verify: (Error) -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await expression(); XCTFail("Expected error", file: file, line: line) } catch { verify(error) }
    }
}

extension V9_05RestoreIdentityTests {
    func testV23P03C41RestoreRebindsWorkspaceAndPreservesPredecessorIdentity() throws {
        let fixture = try C41FunctionalRelationshipTestSupportV1.makeFixture(seed: 41_050)
        let restoredWorkspace = C41FunctionalRelationshipTestSupportV1.workspace(41_051)
        let restored = try fixture.ended.rebound(to: restoredWorkspace)

        XCTAssertEqual(restored.workspaceID, restoredWorkspace)
        XCTAssertEqual(restored.actor.workspaceID, restoredWorkspace)
        XCTAssertEqual(restored.predecessorEventID, fixture.added.eventID)
        XCTAssertEqual(restored.expectedRelationshipRevision, fixture.added.revision)
        XCTAssertEqual(restored.revision, fixture.ended.revision)
        XCTAssertNotEqual(restored.eventSHA256, fixture.ended.eventSHA256)
        try restored.validate()
    }
}

extension V9_05RestoreIdentityTests {
    func testV23P03C13RestoreRebindPreservesVisibilityManifestAndAttestationBytes() throws {
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture(seed: 51_905)
        let destination = C13EvidenceAssuranceTestSupportV1.workspace(51_906)
        let visibility = try fixture.routineVisibility.rebound(to: destination)
        let internalVisibility = try fixture.internalOnlyVisibility.rebound(to: destination)
        let customerLink = try fixture.customerLink.rebound(to: destination, visibility: visibility)
        let internalLink = try fixture.internalOnlyCustomerLink.rebound(to: destination, visibility: internalVisibility)
        let preview = try fixture.customerPreview.rebound(to: destination, links: [customerLink, internalLink])
        let manifest = try fixture.customerManifest.rebound(to: destination, preview: preview)
        let attestation = try fixture.customerAttestation.rebound(to: destination, manifest: manifest)

        XCTAssertEqual(visibility.workspaceID, destination)
        XCTAssertEqual(preview.workspaceID, destination)
        XCTAssertEqual(manifest.sourcePreviewID, preview.previewID)
        XCTAssertEqual(attestation.manifestSHA256, manifest.manifestSHA256)
        XCTAssertNotEqual(manifest.manifestSHA256, fixture.customerManifest.manifestSHA256)
        try attestation.validate(manifest: manifest)
    }
}

extension V9_05RestoreIdentityTests {
    func testV23P03C14RestoreRebindPreservesSubjectRevisionAndDigest() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 145_005)
        let rebound = try fixture.subject.rebound(to: fixture.otherWorkspaceID)
        XCTAssertEqual(rebound.workspaceID, fixture.otherWorkspaceID)
        XCTAssertEqual(rebound.subjectRevision, fixture.subject.subjectRevision)
        XCTAssertEqual(rebound.subjectSHA256, fixture.subject.subjectSHA256)
        XCTAssertEqual(rebound.kind, fixture.subject.kind)
    }

    func testV23P03C19CaptureRestorePreservesFrozenIdentity() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        let rebound = try fixture.capture.rebound(
            to: WorkspaceID(rawValue: C19MeasurementIntegrityTestSupport.id(201))
        )
        XCTAssertEqual(rebound.captureID, fixture.capture.captureID)
        XCTAssertEqual(rebound.captureSHA256, fixture.capture.captureSHA256)
        XCTAssertEqual(rebound.mutationID, fixture.capture.mutationID)
        try rebound.validate()
    }

    func testC20PrivacyTransformRestoreKeepsImmutableOriginalAndDerivativeDistinct() throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        try fixture.original.validatePrivacyDerivative(fixture.derivative)
        XCTAssertEqual(fixture.original.byteRole, .immutableOriginal)
        XCTAssertEqual(fixture.derivative.byteRole, .derivative)
        XCTAssertNotEqual(fixture.original.contentID, fixture.derivative.contentID)
    }
}

extension V9_05RestoreIdentityTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}
extension V9_05RestoreIdentityTests {
    func testC25SurveyDefinitionTypedAnchor() throws {
        XCTAssertEqual(SurveyDefinitionLifecycleV1.persistentFamilies, ["SurveyDefinitionIdentityV1", "SurveyDefinitionReleaseV1"])
        XCTAssertTrue(SurveyDefinitionLimitsV1.token("c25.definition.release"))
        XCTAssertTrue(SurveyDefinitionLimitsV1.digest(String(repeating: "b", count: 64)))
    }
}
extension V9_05RestoreIdentityTests {
    func testC26SurveySessionTypedAnchor() throws {
        XCTAssertEqual(ActivityKindSemanticsV1(kind: .survey).completion, .typedFactCollection)
        XCTAssertFalse(ActivityKindSemanticsV1(kind: .survey).mayClaimInspectionResult)
        XCTAssertEqual(SurveySessionStateV1.allCases.count, 8)
        XCTAssertEqual(SurveySessionTransitionV1.allCases.count, 10)
        XCTAssertNoThrow(try V25GuidedSurveyImportBoundaryV1.validate(persistent: 25, records: 24))
    }
}

extension V9_05RestoreIdentityTests {
    func testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent() {
        XCTAssertEqual(OccurrenceStateV1.allCases, [.upcoming, .ready, .due, .overdue, .deferred,
                                                    .missed, .skipped, .cancelled, .started, .completed])
        XCTAssertEqual(ScheduleReleaseActionV1.allCases.count, 6)
        XCTAssertFalse(WorkflowScheduleBoundaryV1.dueProjectionMayStartWorkflow)
    }
}
private final class C31LightingAnchorV905RestoreIdentityTests: XCTestCase {
    func testC31TypedLightingPackageContractAnchor() throws {
        XCTAssertEqual(LightingPersistenceEnrollmentV1.persistentSchemaVersion, 31)
        XCTAssertEqual(LightingClaimTierV1.allCases.count, 5)
        XCTAssertTrue(LightingIssueKindV1.allCases.contains(.cameraBandingOnly))
        try LightingLimitsV1.digest(String(repeating: "a", count: 64))
    }
}

extension V9_05RestoreIdentityTests {
    @MainActor
    func testV23P03C42RestoreIdentityRetainsCloneForkAndStaleRevisionContracts() async throws {
        let receipt = try CompositeAreaSafetyArchetypeV1.run()
        let payload = try CrossMarketCanonicalV1.data(receipt).base64EncodedString()
        let scenario = try makeScenario(
            "c42-restore-identity",
            targetIsNonempty: false,
            sourceSiteAddress: payload
        )
        defer { try? fileManager.removeItem(at: scenario.root) }
        let cloneFork = try XCTUnwrap(receipt.operations.first { $0.kind == .cloneFork })
        let staleRevision = try XCTUnwrap(receipt.operations.first { $0.kind == .rejectStaleRevision })
        let restored = try await restore(
            scenario,
            mode: .clone,
            uuidValues: [id(500), id(501), id(502), id(503)]
        )
        let restoredPayload = try XCTUnwrap(
            restored.modelContext.fetch(FetchDescriptor<Site>()).first?.address
        )
        XCTAssertEqual(restoredPayload, payload)
        XCTAssertEqual(
            try CrossMarketCanonicalV1.decode(
                ModelRunReceiptV1.self,
                from: try XCTUnwrap(Data(base64Encoded: restoredPayload))
            ),
            receipt
        )
        XCTAssertEqual(cloneFork.expectedDisposition, .accepted)
        XCTAssertEqual(staleRevision.expectedDisposition, .rejectedPrecondition)
        XCTAssertNotEqual(restored.workspaceID.rawValue, scenario.sourceWorkspaceID)
        XCTAssertNotEqual(restored.replicaID.rawValue, scenario.sourceReplicaID)
        XCTAssertNil(try RestoreIntentStore(applicationSupportURL: scenario.target.support).load())
    }
}

private final class C33TemporalEvidenceAnchorV905RestoreIdentity: XCTestCase {
    func testC33V905RestoreIdentityCompatibilityBindsTypedTemporalEvidenceToItsOwner() throws {
        let value = try C33TemporalEvidenceTestSupport.ownerClip(
            factID: "restore.temporal-evidence-identity",
            kind: .video,
            reportProjection: .typedLinkOnly
        )
        try C33TemporalEvidenceTestSupport.assertOwnerBoundary(
            value,
            factID: "restore.temporal-evidence-identity",
            kind: .video,
            reportProjection: .typedLinkOnly
        )
        let anchor = try C33TemporalEvidenceTestSupport.anchor(clip: value.clip)
        XCTAssertEqual(anchor.clipSHA256, value.clip.clipSHA256)
        XCTAssertEqual(anchor.sourceContentID, value.clip.original.contentID)
    }
}

private final class C32AssistanceAnchorV905RestoreIdentity: XCTestCase {
    func testC32V905RestoreIdentityCompatibilityKeepsProposalAtExplicitReviewBoundary() throws {
        let proposal = try C32AssistanceTestSupport.ownerProposal(
            entityKind: .site,
            fieldID: "restore.identity",
            value: .text("restore-stable accepted value")
        )
        try C32AssistanceTestSupport.assertOwnerBoundary(
            proposal,
            entityKind: .site,
            fieldID: "restore.identity",
            valueKind: .text
        )
        let canonical = try AssistanceCanonicalCodecV1.encode(proposal)
        XCTAssertEqual(
            try AssistanceCanonicalCodecV1.decode(AssistanceProposalV1.self, from: canonical),
            proposal
        )
    }
}
private final class C46V905RestoreIdentityCompatibilityTests: XCTestCase {
    func testC46RestoreIdentityKeepsStableDirectionsReference() throws {
        try C46OperationalContactTestSupport.assertOwnerBoundary(
            owner: "restore-identity",
            kind: .phone,
            handoff: .directions,
            slot: 46005
        )
    }
}


private enum C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_05RestoreIdentityTests_swift {
    static let compatibilityCardID = "V23-P03-C47"
    static let sharedEnvelopeDoesNotCollapseFamilyTruth = true
    static let installationAndPunchReceiptsRemainIndependent = true
    static let noPlanFallbackIsExplicit = true
    static let surveyDefinitionOwnershipIsPreserved = true
    static let legacyInspectionTruthIsNotRewritten = true
    static let threeReceiptIsolationIsRequired = true
}

private final class C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_05RestoreIdentityTests_swift_Tests: XCTestCase {
    func testC47V905RestoreIdentityTestsOwnerCompatibilityIsTyped() {
        XCTAssertEqual(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_05RestoreIdentityTests_swift.compatibilityCardID, "V23-P03-C47")
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_05RestoreIdentityTests_swift.sharedEnvelopeDoesNotCollapseFamilyTruth)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_05RestoreIdentityTests_swift.installationAndPunchReceiptsRemainIndependent)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_05RestoreIdentityTests_swift.noPlanFallbackIsExplicit)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_05RestoreIdentityTests_swift.surveyDefinitionOwnershipIsPreserved)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_05RestoreIdentityTests_swift.legacyInspectionTruthIsNotRewritten)
        XCTAssertTrue(C47ActivityContractCompatibility_FieldEvidenceAppTests_V9_05RestoreIdentityTests_swift.threeReceiptIsolationIsRequired)
        XCTAssertEqual(ActivityContractPersistenceEnrollmentV2.persistentFamilies.count, 6)
        XCTAssertTrue(ActivityContractPersistenceEnrollmentV2.usesSoleWorkspaceWriter)
    }
}

private final class C48PortableReviewV905RestoreIdentityBoundaryTests: XCTestCase {
    func testC48ReplacePreservesWhileCloneForkInvalidatesActiveCapability() {
        XCTAssertTrue(BackupRestoreFailurePoint.allCases.contains(.afterPointerSwitch))
        XCTAssertTrue(C48PortableExchangeMigrationBoundaryV2.cloneOrForkInvalidatesCapabilities)
        XCTAssertTrue(C48PortableReviewReleasedDataCompatibilityBoundaryV1.cloneAndForkMustNotReuseActiveCapability)
        XCTAssertTrue(C48PortableReviewPersistenceBoundaryV1.sessionStoreIsNonpersistent)
    }
}
private final class C49WorkResourceRestoreIdentityBoundaryTests: XCTestCase {
    func testRestoreIdentityKeepsSubjectKindsClosed() {
        XCTAssertEqual(Set(WorkResourceSubjectKindV1.allCases), [.workPacket, .correctiveWork])
    }
}

extension C50RestoreIdentityTests {
    func testV23P03C51RestoreRebindsCalendarClosureWithoutActivation() throws {
        try ScheduleRestoreIdentityPolicyV1.validate()
        XCTAssertTrue(
            ScheduleRestoreIdentityPolicyV1.calendarOverrideAndBasisClosureReboundAtomically
                && !ScheduleRestoreIdentityPolicyV1.cloneForkSourceScheduleAutomaticallyActive
                && !ScheduleRestoreIdentityPolicyV1.notificationStateRestoredAsTruth
                && C51ScheduleBackupClosureV1.embeddedCanonicalComponents
                    .contains("AdvancedRecurrenceRuleV1")
                && C51ScheduleBackupClosureV1.embeddedCanonicalComponents
                    .contains("ExceptionCalendarReleaseV1")
        )
    }
}

extension V9_05RestoreIdentityTests {
    func testV23P03C34RestorationPreservesStableOccurrenceWithoutAutoResume() throws {
        let workspaceID = WorkspaceID(
            rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000003408")!
        )
        let occurrenceID = OccurrenceIDV1(rawValue: String(repeating: "a", count: 64))
        let scheduleDefinitionID = UUID(uuidString: "00000000-0000-4000-8000-000000003409")!
        let scheduleReleaseID = UUID(uuidString: "00000000-0000-4000-8000-00000000340c")!
        let scheduleRevision: UInt64 = 1
        let occurrenceRevision: UInt64 = 1
        let target = try NavigationTargetV1(
            workspaceID: workspaceID,
            destination: .scheduleOccurrence,
            stableScheduleDefinitionID: scheduleDefinitionID,
            stableScheduleReleaseID: scheduleReleaseID,
            stableOccurrenceID: occurrenceID,
            requestedMode: .resume,
            expectedScheduleRevision: scheduleRevision,
            expectedOccurrenceRevision: occurrenceRevision
        )
        let receipt = try RouteCoordinatorV1(registry: try RouteRegistryV1()).restore(
            .init(
                context: .init(
                    currentWorkspaceID: workspaceID,
                    currentRevision: 0,
                    currentScheduleRevisions: [scheduleDefinitionID: scheduleRevision],
                    currentScheduleReleaseIDs: [scheduleDefinitionID: scheduleReleaseID],
                    currentOccurrenceRevisions: [occurrenceID: occurrenceRevision]
                ),
                startupMaintenanceTarget: nil,
                incompleteMutationRecoveryTarget: nil,
                explicitIngressTarget: target,
                sceneSnapshot: nil,
                discardedSnapshotReason: nil,
                evidenceKind: .recovery,
                receiptID: UUID(uuidString: "00000000-0000-4000-8000-00000000340a")!
            )
        )
        try receipt.validate()
        XCTAssertEqual(receipt.source, .explicitIngress)
        XCTAssertEqual(receipt.result.target.stableOccurrenceID, occurrenceID)
        XCTAssertFalse(receipt.startsAutomaticWork)
    }
}

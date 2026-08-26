import Darwin
import Foundation
import SwiftData

enum BackupRestoreServiceError: Error, Equatable {
    case contextHasChanges
    case currentGenerationInvalid
    case currentGenerationEmpty
    case currentGenerationNotEmpty
    case invalidPackage
    case invalidRestoreAuthority
    case materializationFailed
    case recoveryRequired
    case injectedFailure
}

struct BackupRestoreCurrentSummaryV1: Equatable, Sendable {
    let signCount: Int
    let reportCount: Int
    let photoCount: Int
    let declaredPayloadByteCount: Int
    let consumedRootCount: Int
}

enum BackupRestoreFailurePoint: CaseIterable, Equatable, Sendable {
    case beforePreparedWrite
    case afterPreparedWrite
    case beforeGenerationInstall
    case afterGenerationInstall
    case beforePointerSwitch
    case afterPointerSwitch
    case beforeNewGenerationValidation
    case afterNewGenerationValidation
    case beforeCleanup
}

@MainActor
final class BackupRestoreFailureInjection {
    private var pending: BackupRestoreFailurePoint?

    init(failOnceAt point: BackupRestoreFailurePoint) {
        pending = point
    }

    func consume(_ point: BackupRestoreFailurePoint) -> Bool {
        guard pending == point else { return false }
        pending = nil
        return true
    }
}

@MainActor
final class BackupRestoreService {
    private struct PinnedIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
        let linkCount: UInt64
        let type: UInt32

        init(_ info: stat) {
            device = UInt64(info.st_dev)
            inode = UInt64(info.st_ino)
            linkCount = UInt64(info.st_nlink)
            type = UInt32(info.st_mode & S_IFMT)
        }
    }

    private struct PinnedDirectory {
        let descriptor: Int32
        let identity: PinnedIdentity
        let parent: Int32?
        let name: String?
    }

    private static let modelStoreName = "model.sqlite"
    private let applicationSupportURL: URL
    private let generationFactory: StoreGenerationFactory
    private var generationAuthority: StoreRestoreGenerationAuthority!
    private let intentStore: RestoreIntentStore
    private let storagePreflight: StoragePreflightService
    private let fileManager: FileManager
    private let now: () -> Date
    private let makeUUID: () -> UUID
    private let failureInjection: BackupRestoreFailureInjection?

    init(
        applicationSupportURL: URL,
        fileManager: FileManager = .default,
        storagePreflight: StoragePreflightService = StoragePreflightService(),
        now: @escaping () -> Date = Date.init,
        makeUUID: @escaping () -> UUID = UUID.init,
        failureInjection: BackupRestoreFailureInjection? = nil
    ) throws {
        let root = applicationSupportURL.standardizedFileURL
        let factory = StoreGenerationFactory(
            applicationSupportURL: root,
            fileManager: fileManager
        )
        let store = try RestoreIntentStore(
            applicationSupportURL: root,
            fileManager: fileManager
        )
        let dataRoot = root.appendingPathComponent(
            "FieldEvidenceData",
            isDirectory: true
        )
        let authority: StoreRestoreGenerationAuthority?
        if fileManager.fileExists(atPath: dataRoot.path) {
            authority = try factory.makeRestoreGenerationAuthority()
        } else {
            authority = nil
        }
        self.applicationSupportURL = root
        self.generationFactory = factory
        self.generationAuthority = authority
        self.intentStore = store
        self.storagePreflight = storagePreflight
        self.fileManager = fileManager
        self.now = now
        self.makeUUID = makeUUID
        self.failureInjection = failureInjection
    }

    static func applicationSupportURL(
        containing generationRootURL: URL
    ) throws -> URL {
        let root = generationRootURL.standardizedFileURL
        let generations = root.deletingLastPathComponent()
        let data = generations.deletingLastPathComponent()
        let support = data.deletingLastPathComponent()
        guard generations.lastPathComponent == "generations",
              data.lastPathComponent == "FieldEvidenceData",
              let id = UUID(uuidString: root.lastPathComponent),
              id.uuidString.lowercased() == root.lastPathComponent else {
            throw BackupRestoreServiceError.currentGenerationInvalid
        }
        return support
    }

    static func isEmptyCurrent(_ modelContext: ModelContext) -> Bool {
        guard !modelContext.hasChanges else { return false }
        do {
            return try modelContext.fetchCount(FetchDescriptor<Site>()) == 0
                && modelContext.fetchCount(FetchDescriptor<Asset>()) == 0
                && modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()) == 0
                && modelContext.fetchCount(FetchDescriptor<EvidenceFile>()) == 0
                && modelContext.fetchCount(FetchDescriptor<Issue>()) == 0
                && modelContext.fetchCount(FetchDescriptor<Packet>()) == 0
                && modelContext.fetchCount(FetchDescriptor<Report>()) == 0
                && modelContext.fetchCount(FetchDescriptor<DeletionLedgerRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<MutationQuarantineRow>()) == 0
                && modelContext.fetchCount(
                    FetchDescriptor<EntityMutationRevisionRow>()
                ) == 0
        } catch {
            return false
        }
    }

    static func currentSummary(
        modelContext: ModelContext,
        generationRootURL: URL
    ) throws -> BackupRestoreCurrentSummaryV1 {
        guard !modelContext.hasChanges else {
            throw BackupRestoreServiceError.contextHasChanges
        }
        let preview = try BackupExportService(
            modelContext: modelContext,
            generationRootURL: generationRootURL
        ).prepare()
        let packets = try modelContext.fetch(FetchDescriptor<Packet>())
        let roots = packets.filter(\.evaluationCounted).map(\.stableRootID)
        guard Set(roots).count == roots.count,
              !modelContext.hasChanges else {
            throw BackupRestoreServiceError.currentGenerationInvalid
        }
        return BackupRestoreCurrentSummaryV1(
            signCount: preview.signCount,
            reportCount: preview.reportCount,
            photoCount: preview.photoCount,
            declaredPayloadByteCount: preview.declaredPayloadByteCount,
            consumedRootCount: roots.count
        )
    }

    /// The only restore mutation path. Its explicit mode keeps Welcome and
    /// maintenance empty-only while Settings owns confirmed replacement.
    func restore(
        validatedPackage: ValidatedV4BackupPackageV1,
        currentModelContext: ModelContext,
        currentGenerationID: UUID,
        currentGenerationRootURL: URL,
        mode: BackupRestoreMode = .emptyInstall
    ) async throws -> StoreGenerationSession {
        try Task.checkCancellation()
        guard !currentModelContext.hasChanges else {
            throw BackupRestoreServiceError.contextHasChanges
        }
        try ensureGenerationAuthority()
        try generationAuthority.requireNoEraseAuthority()
        let initialRetiredIDs = try generationAuthority.retiredGenerationIDs()
        guard try generationFactory.currentGenerationID(
                  authority: generationAuthority
              ) == currentGenerationID,
              !initialRetiredIDs.contains(currentGenerationID),
              generationFactory.installedGenerationURL(id: currentGenerationID)
                == currentGenerationRootURL.standardizedFileURL,
              try ReportPDFAnchoredFile.rootIdentity(at: currentGenerationRootURL)
                == ReportPDFAnchoredFile.rootIdentity(
                    at: generationFactory.installedGenerationURL(
                        id: currentGenerationID
                    )
                ),
               try intentStore.load() == nil else {
            throw BackupRestoreServiceError.currentGenerationInvalid
        }
        let frozenCurrentIdentity: WorkspaceReplicaIdentityV1
        let incomingIdentity: WorkspaceReplicaIdentityV1?
        do {
            frozenCurrentIdentity = try generationFactory
                .currentWorkspaceIdentity(
                    expectedGenerationID: currentGenerationID,
                    authority: generationAuthority
                )
            incomingIdentity = try sourceWorkspaceIdentity(
                validatedPackage.manifest.source
            )
        } catch {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        let initialIsEmpty = Self.isEmptyCurrent(currentModelContext)
        let frozenCurrentRecords: V4BackupRecordsV1?
        switch mode {
        case .emptyInstall:
            guard initialIsEmpty else {
                throw BackupRestoreServiceError.currentGenerationNotEmpty
            }
            frozenCurrentRecords = try records(in: currentModelContext)
        case .replaceExisting:
            guard !initialIsEmpty else {
                throw BackupRestoreServiceError.currentGenerationEmpty
            }
            _ = try Self.currentSummary(
                modelContext: currentModelContext,
                generationRootURL: currentGenerationRootURL
            )
            frozenCurrentRecords = try records(in: currentModelContext)
        case .clone, .fork:
            frozenCurrentRecords = try records(in: currentModelContext)
        }
        do {
            _ = try BackupPackageValidatorV1().validate(
                stagedPackageURL: validatedPackage.stagedPackageURL
            )
        } catch {
            throw BackupRestoreServiceError.invalidPackage
        }
        guard try BackupPackageValidatorV1().validate(
            stagedPackageURL: validatedPackage.stagedPackageURL
        ) == validatedPackage else {
            throw BackupRestoreServiceError.invalidPackage
        }
        try storagePreflight.checkBackupImport(
            declaredPayloadByteCount: Int64(
                validatedPackage.manifest.declaredPayloadByteCount
            ),
            onVolumeContaining: applicationSupportURL
        )
        try generationAuthority.requireNoEraseAuthority()
        try requireExclusiveLiveStaging(
            validatedPackage,
            currentGenerationID: currentGenerationID,
            retiredIDs: initialRetiredIDs
        )
        guard !currentModelContext.hasChanges,
              try generationFactory.currentGenerationID(
                  authority: generationAuthority
              ) == currentGenerationID else {
            throw BackupRestoreServiceError.contextHasChanges
        }

        guard let frozenCurrentRecords,
              try records(in: currentModelContext) == frozenCurrentRecords else {
            throw BackupRestoreServiceError.contextHasChanges
        }
        switch mode {
        case .emptyInstall:
            guard Self.isEmptyCurrent(currentModelContext) else {
                throw BackupRestoreServiceError.currentGenerationNotEmpty
            }
        case .replaceExisting:
            guard !Self.isEmptyCurrent(currentModelContext) else {
                throw BackupRestoreServiceError.currentGenerationEmpty
            }
            _ = try Self.currentSummary(
                modelContext: currentModelContext,
                generationRootURL: currentGenerationRootURL
            )
        case .clone, .fork:
            guard uniqueModelIDs(in: validatedPackage.records) else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
        }
        var expectedRecords: V4BackupRecordsV1
        do {
            expectedRecords = try ReplacementRestoreRule.makeDeletionWinningPlan(
                DeletionWinningRestoreInputV2(
                    currentRecords: frozenCurrentRecords,
                    currentIdentity: frozenCurrentIdentity,
                    incomingRecords: validatedPackage.records,
                    incomingIdentity: incomingIdentity,
                    mode: mode,
                    replacementAt: now()
                )
            ).recordsAfter
        } catch {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        if validatedPackage.manifest.source.recordsSchemaVersion <= 2,
           expectedRecords.mutationHistory == nil {
            expectedRecords = replacingMutationHistoryForCurrentWriter(
                in: expectedRecords,
                with: MutationHistorySnapshotV1(
                    workspaceRevision: 0,
                    lastLocalSequence: 0,
                    receipts: [],
                    quarantines: [],
                    entityRevisions: []
                )
            )
        }
        guard uniqueModelIDs(in: expectedRecords) else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }

        let newGenerationID = makeUUID()
        let restoreID = makeUUID()
        guard newGenerationID != currentGenerationID,
              restoreID != currentGenerationID,
              restoreID != newGenerationID,
              !initialRetiredIDs.contains(newGenerationID) else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }

        do {
            try Task.checkCancellation()
            let preliminaryIdentityDecision = try makeIdentityDecision(
                package: validatedPackage,
                mode: mode,
                currentGenerationID: currentGenerationID,
                newGenerationID: newGenerationID,
                targetManifestDigest: String(repeating: "0", count: 64)
            )
            expectedRecords = try recordsForMaterialization(
                expectedRecords,
                identityDecision: preliminaryIdentityDecision
            )
            try materialize(
                validatedPackage,
                records: expectedRecords,
                generationID: newGenerationID,
                identityDecision: preliminaryIdentityDecision,
                legacyDestinationIdentity: frozenCurrentIdentity
            )
            try Task.checkCancellation()
            try validateStagingGeneration(
                id: newGenerationID,
                expected: expectedRecords,
                identity: try preliminaryIdentityDecision.map {
                    try workspaceIdentity($0)
                } ?? frozenCurrentIdentity
            )
            try Task.checkCancellation()
            let targetManifestDigest = try generationFactory
                .prepareRestoreStagingGenerationManifest(
                    expectedOldID: currentGenerationID,
                    newID: newGenerationID,
                    authority: generationAuthority
                )
            guard try generationFactory.currentWorkspaceIdentity(
                    expectedGenerationID: currentGenerationID,
                    authority: generationAuthority
                  ) == frozenCurrentIdentity else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            let identityDecision = try makeIdentityDecision(
                package: validatedPackage,
                mode: mode,
                currentGenerationID: currentGenerationID,
                newGenerationID: newGenerationID,
                targetManifestDigest: targetManifestDigest,
                frozenWorkspaceID: preliminaryIdentityDecision.flatMap {
                    $0.mode == .clone || $0.mode == .fork
                        ? $0.targetPointer.workspaceID
                        : nil
                },
                frozenReplicaID: preliminaryIdentityDecision.flatMap {
                    let requiresReplica = $0.mode != .replaceExisting
                        || $0.oldPointer.replicaID == $0.source.replicaID
                    return requiresReplica ? $0.targetPointer.replicaID : nil
                }
            )
            switch (preliminaryIdentityDecision, identityDecision) {
            case (nil, nil):
                break
            case (let preliminary?, let final?):
                guard try workspaceIdentity(preliminary)
                        == workspaceIdentity(final) else {
                    throw BackupRestoreServiceError.invalidRestoreAuthority
                }
            default:
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            try validateStagingGeneration(
                id: newGenerationID,
                expected: expectedRecords,
                identity: try identityDecision.map {
                    try workspaceIdentity($0)
                } ?? frozenCurrentIdentity
            )
            let intent: RestoreIntentV1
            if let identityDecision {
                intent = RestoreIntentV1(
                    identity: identityDecision,
                    restoreID: restoreID
                )
            } else {
                guard mode == .emptyInstall || mode == .replaceExisting else {
                    throw BackupRestoreServiceError.invalidPackage
                }
                intent = RestoreIntentV1(
                    newGenerationID: newGenerationID,
                    newGenerationRelativePath:
                        "FieldEvidenceData/generations/\(canonical(newGenerationID))",
                    oldGenerationID: currentGenerationID,
                    phase: .prepared,
                    restoreID: restoreID,
                    schemaVersion: 1,
                    stagingGenerationRelativePath:
                        "FieldEvidenceRestore/generations/\(canonical(newGenerationID))"
                )
            }
            guard RestoreIntentCodecV1.valid(intent) else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            try Task.checkCancellation()
            try discardImportedPackage(validatedPackage, currentGenerationRootURL)
            let expectedInstalledNames = Set(
                (initialRetiredIDs + [currentGenerationID]).map(canonical)
            )
            guard Set(try generationAuthority.installedGenerationNames())
                    == expectedInstalledNames,
                  Set(try generationAuthority.restoreGenerationNames())
                    == [canonical(newGenerationID)],
                  try generationAuthority.importStagingNames().isEmpty else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }

            try inject(.beforePreparedWrite)
            try Task.checkCancellation()
            try intentStore.create(intent)
            try inject(.afterPreparedWrite)

            try inject(.beforeGenerationInstall)
            try Task.checkCancellation()
            try protectGenerationTree(
                id: newGenerationID,
                root: generationFactory.restoreStagingGenerationURL(id: newGenerationID),
                staging: true
            )
            try generationFactory.installRestoreStagingGeneration(
                id: newGenerationID,
                authority: generationAuthority
            )
            try protectGenerationTree(
                id: newGenerationID,
                root: generationFactory.installedGenerationURL(id: newGenerationID),
                staging: false
            )
            let installed = intent.advancing(to: .generationInstalled)
            try intentStore.replace(expected: intent, with: installed)
            try validateInstalledGeneration(
                id: newGenerationID,
                expected: expectedRecords,
                identity: try identityDecision.map {
                    try workspaceIdentity($0)
                } ?? frozenCurrentIdentity
            )
            try Task.checkCancellation()
            try inject(.afterGenerationInstall)

            try inject(.beforePointerSwitch)
            try Task.checkCancellation()
            try protectDataPointer(named: "current.json")
            guard try generationFactory.currentWorkspaceIdentity(
                    expectedGenerationID: currentGenerationID,
                    authority: generationAuthority
                  ) == frozenCurrentIdentity else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            if let identityDecision {
                let expectedCurrentPointer = try currentPointer(
                    identityDecision.oldPointer
                )
                try generationFactory.switchCurrentGeneration(
                    expected: currentGenerationID,
                    to: newGenerationID,
                    expectedCurrentPointer: expectedCurrentPointer,
                    identity: try workspaceIdentity(identityDecision),
                    sourceReplicaID: identityDecision.source.replicaID.map {
                        ReplicaID(rawValue: $0)
                    },
                    knownReplicaIDs: knownReplicaIDs(identityDecision),
                    preparedGenerationManifestSHA256: targetManifestDigest,
                    authority: generationAuthority
                )
            } else {
                try generationFactory.switchCurrentGeneration(
                    expected: currentGenerationID,
                    to: newGenerationID,
                    authority: generationAuthority
                )
            }
            try requireCurrentPointerBinding(
                installed,
                currentID: newGenerationID
            )
            let switched = installed.advancing(to: .pointerSwitched)
            try intentStore.replace(expected: installed, with: switched)
            try inject(.afterPointerSwitch)

            try inject(.beforeNewGenerationValidation)
            try Task.checkCancellation()
            let session: StoreGenerationSession
            if let identityDecision {
                session = try generationFactory.openInstalledGeneration(
                    id: newGenerationID,
                    identity: try workspaceIdentity(identityDecision),
                    authority: generationAuthority
                )
            } else {
                session = try generationFactory.openInstalledGeneration(
                    id: newGenerationID,
                    authority: generationAuthority
                )
            }
            try validateLiveSession(
                session,
                expected: expectedRecords
            )
            try Task.checkCancellation()
            let validated = switched.advancing(to: .newGenerationValidated)
            try intentStore.replace(expected: switched, with: validated)
            try inject(.afterNewGenerationValidation)

            try inject(.beforeCleanup)
            try Task.checkCancellation()
            try protectDataPointer(named: "retired.json")
            try generationFactory.retireGeneration(
                oldID: currentGenerationID,
                currentID: newGenerationID,
                authority: generationAuthority
            )
            try intentStore.remove(expected: validated)
            try cleanupEmptyRestoreDirectories()
            return session
        } catch let failure as ProtectedFilePolicyError
            where failure == .protectedDataUnavailable {
            throw failure
        } catch let error as BackupRestoreServiceError
            where error == .injectedFailure {
            throw error
        } catch {
            do {
                if let recovered = try reconcileAtStartup() {
                    return recovered
                }
            } catch let failure as ProtectedFilePolicyError
                where failure == .protectedDataUnavailable {
                throw failure
            } catch {
                // Preserve the original restore failure when reconciliation
                // cannot establish a safe recovery state.
            }
            throw error
        }
    }

    /// Runs before ordinary pointer maintenance. A returned session is the
    /// fully validated new current generation; nil means old remains current or
    /// no intent existed.
    func reconcileAtStartup() throws -> StoreGenerationSession? {
        guard let intent = try intentStore.load() else {
            let dataRoot = applicationSupportURL.appendingPathComponent(
                "FieldEvidenceData",
                isDirectory: true
            )
            guard fileManager.fileExists(atPath: dataRoot.path) else {
                return nil
            }
            try ensureGenerationAuthority()
            try cleanupAbandonedRestoreStaging()
            return nil
        }
        try ensureGenerationAuthority()
        guard RestoreIntentCodecV1.valid(intent) else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        let currentID = try generationFactory.currentGenerationID(
            authority: generationAuthority
        )
        try requireCurrentPointerBinding(intent, currentID: currentID)
        let retiredIDs = try generationAuthority.retiredGenerationIDs()
        let retainedLegacyIdentity: WorkspaceReplicaIdentityV1?
        if intent.identity == nil {
            retainedLegacyIdentity = try? generationFactory
                .currentWorkspaceIdentity(
                    expectedGenerationID: currentID,
                    authority: generationAuthority
                )
        } else {
            retainedLegacyIdentity = nil
        }
        let presence = try generationFactory.generationPresence(
            id: intent.newGenerationID,
            authority: generationAuthority
        )
        var expectedInstalledNames = Set(retiredIDs.map(canonical))
        expectedInstalledNames.insert(canonical(intent.oldGenerationID))
        if presence.installed {
            expectedInstalledNames.insert(canonical(intent.newGenerationID))
        }
        let expectedStagingNames: Set<String> = presence.staging
            ? [canonical(intent.newGenerationID)]
            : []
        guard Set(try generationAuthority.installedGenerationNames())
                == expectedInstalledNames,
              Set(try generationAuthority.restoreGenerationNames())
                == expectedStagingNames,
              try generationAuthority.importStagingNames().isEmpty else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        guard let oldSession = try validInstalledGeneration(
            id: intent.oldGenerationID,
            identity: try intent.identity.map {
                try workspaceIdentity($0.oldPointer)
            } ?? retainedLegacyIdentity,
            requireExportReconciliation:
                currentID == intent.oldGenerationID
        ), let oldRecords = try? records(in: oldSession.modelContext) else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        switch intent.phase {
        case .prepared, .generationInstalled, .pointerSwitched:
            guard !retiredIDs.contains(intent.oldGenerationID),
                  !retiredIDs.contains(intent.newGenerationID) else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
        case .newGenerationValidated:
            guard !retiredIDs.contains(intent.newGenerationID) else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
        }
        if intent.schemaVersion == 2,
           intent.phase == .generationInstalled,
           currentID == intent.oldGenerationID {
            guard !presence.staging,
                  let identity = intent.identity else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            try removePreparedRestoreManifestBeforeDiscard(
                expectedOldID: intent.oldGenerationID,
                generationID: intent.newGenerationID,
                expectedDigest:
                    identity.targetPointer.generationManifestSHA256
            )
            try generationFactory.removeInstalledGeneration(
                id: intent.newGenerationID,
                keeping: intent.oldGenerationID,
                authority: generationAuthority
            )
            let discardedPresence = try generationFactory.generationPresence(
                id: intent.newGenerationID,
                authority: generationAuthority
            )
            guard !discardedPresence.staging,
                  !discardedPresence.installed else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            try intentStore.remove(expected: intent)
            try cleanupEmptyRestoreDirectories()
            return nil
        }
        if presence.installed {
            try requireNoUnexpectedInstalledBytes(id: intent.newGenerationID)
            if intent.schemaVersion == 2,
               currentID == intent.newGenerationID,
               let identity = intent.identity {
                try generationFactory.requireInstalledRestoreGenerationSnapshot(
                    expectedOldID: intent.oldGenerationID,
                    generationID: intent.newGenerationID,
                    expectedManifestDigest:
                        identity.targetPointer.generationManifestSHA256,
                    authority: generationAuthority
                )
            }
        }
        if presence.staging {
            try requireNoUnexpectedStagingBytes(id: intent.newGenerationID)
        }
        let installedNewSession: StoreGenerationSession?
        if presence.installed {
            installedNewSession = try validInstalledGeneration(
                id: intent.newGenerationID,
                identity: try intent.identity.map {
                    try workspaceIdentity($0.targetPointer)
                } ?? retainedLegacyIdentity,
                requireExportReconciliation:
                    currentID == intent.newGenerationID
            )
        } else {
            installedNewSession = nil
        }
        if let installedNewSession {
            let newRecords = try records(in: installedNewSession.modelContext)
            guard validRecoveredRecords(
                intent: intent,
                old: oldRecords,
                target: newRecords
            ) else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
        }
        if presence.staging,
           let stagedRecords = try validStagingGenerationRecords(
               id: intent.newGenerationID,
               identity: try intent.identity.map {
                   try workspaceIdentity($0.targetPointer)
               }
           ),
           !validRecoveredRecords(
               intent: intent,
               old: oldRecords,
               target: stagedRecords
           ) {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }

        switch intent.phase {
        case .prepared:
            if intent.schemaVersion == 2,
               currentID == intent.newGenerationID,
               let newSession = installedNewSession {
                let switched = intent.advancing(to: .pointerSwitched)
                try intentStore.replace(expected: intent, with: switched)
                return try finishValidatedNew(switched, session: newSession)
            }
            guard currentID == intent.oldGenerationID else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            if presence.installed {
                guard installedNewSession != nil,
                      !presence.staging else {
                    throw BackupRestoreServiceError.invalidRestoreAuthority
                }
                try removePreparedRestoreManifestBeforeDiscard(
                    expectedOldID: intent.oldGenerationID,
                    generationID: intent.newGenerationID,
                    expectedDigest:
                        intent.identity?.targetPointer
                            .generationManifestSHA256
                )
                try generationFactory.removeInstalledGeneration(
                    id: intent.newGenerationID,
                    keeping: intent.oldGenerationID,
                    authority: generationAuthority
                )
            } else if presence.staging {
                try discardPrepublicationStagingGeneration(
                    id: intent.newGenerationID,
                    expectedDigest:
                        intent.identity?.targetPointer
                            .generationManifestSHA256
                )
            }
            try intentStore.remove(expected: intent)
            try cleanupEmptyRestoreDirectories()
            return nil

        case .generationInstalled:
            guard !presence.staging, presence.installed else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            let newSession = installedNewSession
            guard let newSession else {
                if intent.schemaVersion == 2 {
                    throw BackupRestoreServiceError.recoveryRequired
                }
                if currentID == intent.newGenerationID {
                    try protectDataPointer(named: "current.json")
                    try generationFactory.switchCurrentGeneration(
                        expected: intent.newGenerationID,
                        to: intent.oldGenerationID,
                        authority: generationAuthority
                    )
                } else if currentID != intent.oldGenerationID {
                    throw BackupRestoreServiceError.invalidRestoreAuthority
                }
                try generationFactory.removeInstalledGeneration(
                    id: intent.newGenerationID,
                    keeping: intent.oldGenerationID,
                    authority: generationAuthority
                )
                try intentStore.remove(expected: intent)
                try cleanupEmptyRestoreDirectories()
                return nil
            }
            if currentID == intent.oldGenerationID {
                try protectDataPointer(named: "current.json")
                try publishTarget(for: intent)
            } else if currentID != intent.newGenerationID {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            let switched = intent.advancing(to: .pointerSwitched)
            try intentStore.replace(expected: intent, with: switched)
            return try finishValidatedNew(
                switched,
                session: newSession
            )

        case .pointerSwitched:
            guard !presence.staging, presence.installed else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            let newSession = installedNewSession
            guard let newSession else {
                if intent.schemaVersion == 2 {
                    throw BackupRestoreServiceError.recoveryRequired
                }
                guard currentID == intent.newGenerationID else {
                    throw BackupRestoreServiceError.invalidRestoreAuthority
                }
                try protectDataPointer(named: "current.json")
                try generationFactory.switchCurrentGeneration(
                    expected: intent.newGenerationID,
                    to: intent.oldGenerationID,
                    authority: generationAuthority
                )
                try generationFactory.removeInstalledGeneration(
                    id: intent.newGenerationID,
                    keeping: intent.oldGenerationID,
                    authority: generationAuthority
                )
                try intentStore.remove(expected: intent)
                try cleanupEmptyRestoreDirectories()
                return nil
            }
            guard currentID == intent.newGenerationID else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            return try finishValidatedNew(intent, session: newSession)

        case .newGenerationValidated:
            let newSession = installedNewSession
            guard !presence.staging,
                  presence.installed,
                  currentID == intent.newGenerationID,
                  let newSession else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            try protectDataPointer(named: "retired.json")
            try generationFactory.retireGeneration(
                oldID: intent.oldGenerationID,
                currentID: intent.newGenerationID,
                authority: generationAuthority
            )
            try intentStore.remove(expected: intent)
            try cleanupEmptyRestoreDirectories()
            return newSession
        }
    }

    /// Migration-only bridge to the one canonical backup-record projection.
    /// Keeping the record construction in this file prevents schema migration
    /// from creating a second field-by-field export authority.
    func migrationCanonicalRecords(
        in context: ModelContext
    ) throws -> V4BackupRecordsV1 {
        try records(in: context, includingDeletionLedger: false)
    }
}

private extension BackupRestoreService {
    func requireCurrentPointerBinding(
        _ intent: RestoreIntentV1,
        currentID: UUID
    ) throws {
        guard let identity = intent.identity else { return }
        let expected: RestorePointerIdentityV1
        if currentID == intent.oldGenerationID {
            expected = identity.oldPointer
        } else if currentID == intent.newGenerationID {
            expected = identity.targetPointer
        } else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        let pointer = try generationFactory.currentGenerationPointerV3(
            expectedGenerationID: currentID,
            authority: generationAuthority
        )
        guard pointer.generationID == canonical(expected.generationID),
              pointer.generationManifestSHA256
                == expected.generationManifestSHA256,
              pointer.knownReplicaIDs
                == expected.knownReplicaIDs.map(canonical),
              pointer.workspaceID == canonical(expected.workspaceID),
              pointer.replicaID == canonical(expected.replicaID) else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
    }

    func publishTarget(for intent: RestoreIntentV1) throws {
        if let identity = intent.identity {
            let expectedCurrentPointer = try currentPointer(
                identity.oldPointer
            )
            try generationFactory.switchCurrentGeneration(
                expected: intent.oldGenerationID,
                to: intent.newGenerationID,
                expectedCurrentPointer: expectedCurrentPointer,
                identity: try workspaceIdentity(identity),
                sourceReplicaID: identity.source.replicaID.map {
                    ReplicaID(rawValue: $0)
                },
                knownReplicaIDs: knownReplicaIDs(identity),
                preparedGenerationManifestSHA256:
                    identity.targetPointer.generationManifestSHA256,
                authority: generationAuthority
            )
        } else {
            try generationFactory.switchCurrentGeneration(
                expected: intent.oldGenerationID,
                to: intent.newGenerationID,
                authority: generationAuthority
            )
        }
    }

    func validRecoveredRecords(
        intent: RestoreIntentV1,
        old: V4BackupRecordsV1,
        target: V4BackupRecordsV1
    ) -> Bool {
        guard let identity = intent.identity else {
            return validMonotonicUnion(from: old, to: target)
        }
        guard let plan = try? ReplacementRestoreRule.makeDeletionWinningPlan(
            DeletionWinningRestoreInputV2(
                currentRecords: old,
                currentIdentity: try? workspaceIdentity(identity.oldPointer),
                incomingRecords: target,
                incomingIdentity: try? sourceWorkspaceIdentity(identity.source),
                mode: identity.mode,
                replacementAt: now()
            )
        ) else { return false }
        guard let normalized = try? recordsForMaterialization(
            plan.recordsAfter,
            identityDecision: identity
        ) else { return false }
        return normalized == target
    }

    func makeIdentityDecision(
        package: ValidatedV4BackupPackageV1,
        mode: BackupRestoreMode,
        currentGenerationID: UUID,
        newGenerationID: UUID,
        targetManifestDigest: String,
        frozenWorkspaceID: UUID? = nil,
        frozenReplicaID: UUID? = nil
    ) throws -> RestoreIdentityV1? {
        let source = package.manifest.source
        switch (source.workspaceID, source.replicaID) {
        case (nil, nil):
            guard package.manifest.backupSchemaVersion == 1 else {
                throw BackupRestoreServiceError.invalidPackage
            }
            return nil
        case (let workspaceID?, let replicaID?):
            guard package.manifest.backupSchemaVersion == 2
                    || package.manifest.backupSchemaVersion == 3,
                  workspaceID != replicaID else {
                throw BackupRestoreServiceError.invalidPackage
            }
            let current: CurrentGenerationPointerV3 = try generationFactory
                .currentGenerationPointerV3(
                expectedGenerationID: currentGenerationID,
                authority: generationAuthority
            )
            guard let oldGenerationID = UUID(uuidString: current.generationID),
                  oldGenerationID == currentGenerationID,
                  let oldWorkspaceID = UUID(uuidString: current.workspaceID),
                  let oldReplicaID = UUID(uuidString: current.replicaID) else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            let decodedKnownReplicaIDs = current.knownReplicaIDs.compactMap {
                UUID(uuidString: $0)
            }
            guard decodedKnownReplicaIDs.count
                    == current.knownReplicaIDs.count else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            let oldPointer = RestorePointerIdentityV1(
                generationID: oldGenerationID,
                generationManifestSHA256: current.generationManifestSHA256,
                knownReplicaIDs: Set(decodedKnownReplicaIDs),
                workspaceID: oldWorkspaceID,
                replicaID: oldReplicaID
            )
            let known = Set(decodedKnownReplicaIDs)
            var unavailableWorkspaces = known
            unavailableWorkspaces.formUnion([
                workspaceID,
                oldWorkspaceID,
                replicaID,
                oldReplicaID,
                currentGenerationID,
                newGenerationID,
            ])
            let allocatedWorkspaceID: UUID?
            switch mode {
            case .clone, .fork:
                if let frozenWorkspaceID {
                    allocatedWorkspaceID = frozenWorkspaceID
                } else {
                    allocatedWorkspaceID = try destinationWorkspaceID(
                        excluding: unavailableWorkspaces
                    )
                }
            case .emptyInstall, .replaceExisting: allocatedWorkspaceID = nil
            }
            let targetWorkspaceID: UUID
            switch mode {
            case .emptyInstall: targetWorkspaceID = workspaceID
            case .replaceExisting: targetWorkspaceID = oldWorkspaceID
            case .clone, .fork:
                guard let allocatedWorkspaceID else {
                    throw BackupRestoreServiceError.invalidRestoreAuthority
                }
                targetWorkspaceID = allocatedWorkspaceID
            }
            let requiresReplica = mode != .replaceExisting
                || oldReplicaID == replicaID
            var unavailableReplicas = known
            if mode == .replaceExisting {
                unavailableReplicas.remove(oldReplicaID)
            }
            unavailableReplicas.formUnion([
                currentGenerationID,
                newGenerationID,
                workspaceID,
                oldWorkspaceID,
                targetWorkspaceID,
            ])
            let allocatedReplicaID: UUID?
            if requiresReplica {
                if let frozenReplicaID {
                    allocatedReplicaID = frozenReplicaID
                } else {
                    do {
                        allocatedReplicaID = try ReplicaID
                            .destinationOwnedForRestore(
                                excluding: ReplicaID(rawValue: replicaID),
                                disallowed: Set(unavailableReplicas.map {
                                    ReplicaID(rawValue: $0)
                                }),
                                generate: makeUUID
                            ).rawValue
                    } catch {
                        throw BackupRestoreServiceError.invalidRestoreAuthority
                    }
                }
            } else {
                allocatedReplicaID = nil
            }
            do {
                return try RestoreIdentityDecisionV1.decide(.init(
                    mode: mode,
                    source: RestoreSourceIdentityV1(
                        workspaceID: workspaceID,
                        replicaID: replicaID
                    ),
                    oldPointer: oldPointer,
                    targetGenerationID: newGenerationID,
                    targetGenerationManifestSHA256: targetManifestDigest,
                    allocatedWorkspaceID: allocatedWorkspaceID,
                    allocatedReplicaID: allocatedReplicaID,
                    unavailableWorkspaceIDs: unavailableWorkspaces,
                    unavailableReplicaIDs: unavailableReplicas
                ))
            } catch {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
        default:
            throw BackupRestoreServiceError.invalidPackage
        }
    }

    func workspaceIdentity(
        _ decision: RestoreIdentityV1
    ) throws -> WorkspaceReplicaIdentityV1 {
        try workspaceIdentity(decision.targetPointer)
    }

    func destinationWorkspaceID(excluding unavailable: Set<UUID>) throws -> UUID {
        for _ in 0..<16 {
            let candidate = makeUUID()
            if !unavailable.contains(candidate) { return candidate }
        }
        throw BackupRestoreServiceError.invalidRestoreAuthority
    }

    func currentPointer(
        _ pointer: RestorePointerIdentityV1
    ) throws -> CurrentGenerationPointerV3 {
        try CurrentGenerationPointerV3(
            generationID: pointer.generationID,
            generationManifestSHA256: pointer.generationManifestSHA256,
            workspaceID: WorkspaceID(rawValue: pointer.workspaceID),
            replicaID: ReplicaID(rawValue: pointer.replicaID),
            knownReplicaIDs: Set(pointer.knownReplicaIDs.map {
                ReplicaID(rawValue: $0)
            })
        )
    }

    func workspaceIdentity(
        _ pointer: RestorePointerIdentityV1
    ) throws -> WorkspaceReplicaIdentityV1 {
        try WorkspaceReplicaIdentityV1(
            workspaceID: WorkspaceID(rawValue: pointer.workspaceID),
            replicaID: ReplicaID(rawValue: pointer.replicaID)
        )
    }

    func sourceWorkspaceIdentity(
        _ source: V4BackupSourceV1
    ) throws -> WorkspaceReplicaIdentityV1? {
        switch (source.workspaceID, source.replicaID) {
        case (nil, nil):
            return nil
        case (let workspaceID?, let replicaID?):
            return try WorkspaceReplicaIdentityV1(
                workspaceID: WorkspaceID(rawValue: workspaceID),
                replicaID: ReplicaID(rawValue: replicaID)
            )
        default:
            throw BackupRestoreServiceError.invalidPackage
        }
    }

    func sourceWorkspaceIdentity(
        _ source: RestoreSourceIdentityV1
    ) throws -> WorkspaceReplicaIdentityV1? {
        switch (source.workspaceID, source.replicaID) {
        case (nil, nil):
            return nil
        case (let workspaceID?, let replicaID?):
            return try WorkspaceReplicaIdentityV1(
                workspaceID: WorkspaceID(rawValue: workspaceID),
                replicaID: ReplicaID(rawValue: replicaID)
            )
        default:
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
    }

    func knownReplicaIDs(_ decision: RestoreIdentityV1) -> Set<ReplicaID> {
        Set(decision.targetPointer.knownReplicaIDs.map {
            ReplicaID(rawValue: $0)
        })
    }

    func protectDataPointer(named name: String) throws {
        let pointerURL = applicationSupportURL
            .appendingPathComponent("FieldEvidenceData", isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)
        try ProtectedFilePolicyV1.applyAndVerify(
            .generationPointer,
            at: pointerURL,
            authorityCheck: { try generationAuthority.verify() }
        )
    }

    func ensureGenerationAuthority() throws {
        if generationAuthority == nil {
            generationAuthority = try generationFactory.makeRestoreGenerationAuthority()
        } else {
            try generationAuthority.verify()
        }
    }

    func requireExclusiveLiveStaging(
        _ value: ValidatedV4BackupPackageV1,
        currentGenerationID: UUID,
        retiredIDs: [UUID]
    ) throws {
        let expectedParent = applicationSupportURL
            .appendingPathComponent("FieldEvidenceRestore", isDirectory: true)
            .appendingPathComponent("staging", isDirectory: true)
            .standardizedFileURL
        let stage = value.stagedPackageURL.standardizedFileURL
        let name = stage.lastPathComponent
        let base = stage.deletingLastPathComponent()
        let stem = stage.deletingPathExtension().lastPathComponent
        guard base == expectedParent,
              stage.pathExtension == "fieldrecordbackup",
              let identifier = UUID(uuidString: stem),
              canonical(identifier) == stem,
              Set(try generationAuthority.importStagingNames()) == [name],
              try generationAuthority.restoreGenerationNames().isEmpty,
              Set(try generationAuthority.installedGenerationNames())
                == Set((retiredIDs + [currentGenerationID]).map(canonical)) else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
    }

    func finishValidatedNew(
        _ intent: RestoreIntentV1,
        session: StoreGenerationSession
    ) throws -> StoreGenerationSession {
        try requireCurrentPointerBinding(
            intent,
            currentID: intent.newGenerationID
        )
        try validateLiveSession(session, expected: nil)
        let validated = intent.advancing(to: .newGenerationValidated)
        try intentStore.replace(expected: intent, with: validated)
        try protectDataPointer(named: "retired.json")
        try generationFactory.retireGeneration(
            oldID: intent.oldGenerationID,
            currentID: intent.newGenerationID,
            authority: generationAuthority
        )
        try intentStore.remove(expected: validated)
        try cleanupEmptyRestoreDirectories()
        return session
    }

    func replacingPackets(
        in records: V4BackupRecordsV1,
        with packets: [V4BackupPacketDTO]
    ) -> V4BackupRecordsV1 {
        V4BackupRecordsV1(
            assets: records.assets,
            deletionLedger: records.deletionLedger,
            evidenceFiles: records.evidenceFiles,
            issues: records.issues,
            mutationHistory: records.mutationHistory,
            packets: packets,
            recordsSchemaVersion: records.recordsSchemaVersion,
            reports: records.reports,
            sites: records.sites,
            workflowRecords: records.workflowRecords
        )
    }

    func uniqueModelIDs(in records: V4BackupRecordsV1) -> Bool {
        let ids = records.sites.map(\.id)
            + records.assets.map(\.id)
            + records.workflowRecords.map(\.id)
            + records.evidenceFiles.map(\.id)
            + records.issues.map(\.id)
            + records.packets.map(\.id)
            + records.reports.map(\.id)
        return Set(ids).count == ids.count
    }

    func replacingMutationHistoryForCurrentWriter(
        in records: V4BackupRecordsV1,
        with history: MutationHistorySnapshotV1
    ) -> V4BackupRecordsV1 {
        V4BackupRecordsV1(
            assets: records.assets,
            deletionLedger: records.deletionLedger ?? .empty,
            evidenceFiles: records.evidenceFiles,
            issues: records.issues,
            mutationHistory: history,
            packets: records.packets,
            recordsSchemaVersion: 3,
            reports: records.reports,
            sites: records.sites,
            workflowRecords: records.workflowRecords
        )
    }

    func recordsForMaterialization(
        _ records: V4BackupRecordsV1,
        identityDecision: RestoreIdentityV1?
    ) throws -> V4BackupRecordsV1 {
        guard let history = records.mutationHistory else {
            throw BackupRestoreServiceError.invalidPackage
        }
        let resetsLocalSequence: Bool
        if let identityDecision {
            let target = try workspaceIdentity(identityDecision)
            let old = try workspaceIdentity(identityDecision.oldPointer)
            resetsLocalSequence = identityDecision.mode != .replaceExisting
                || target != old
        } else {
            resetsLocalSequence = false
        }
        guard resetsLocalSequence, history.lastLocalSequence != 0 else {
            return records
        }
        return replacingMutationHistoryForCurrentWriter(
            in: records,
            with: MutationHistorySnapshotV1(
                workspaceRevision: history.workspaceRevision,
                lastLocalSequence: 0,
                receipts: history.receipts,
                quarantines: history.quarantines,
                entityRevisions: history.entityRevisions
            )
        )
    }

    func materialize(
        _ value: ValidatedV4BackupPackageV1,
        records: V4BackupRecordsV1,
        generationID: UUID,
        identityDecision: RestoreIdentityV1?,
        legacyDestinationIdentity: WorkspaceReplicaIdentityV1
    ) throws {
        do {
            try generationFactory.createRestoreStagingGeneration(
                id: generationID,
                authority: generationAuthority
            ) { context in
                try insert(
                    records,
                    into: context,
                    generationID: generationID,
                    identityDecision: identityDecision,
                    legacyDestinationIdentity: legacyDestinationIdentity
                )
            }
            try writeMembers(
                value,
                records: records,
                to: generationFactory.restoreStagingGenerationURL(
                    id: generationID
                ),
                generationID: generationID
            )
            try protectGenerationTree(
                id: generationID,
                root: generationFactory.restoreStagingGenerationURL(id: generationID),
                staging: true
            )
        } catch {
            let originalError = error
            let cleanupError: Error?
            do {
                try generationFactory.removeRestoreStagingGeneration(
                    id: generationID,
                    authority: generationAuthority
                )
                cleanupError = nil
            } catch {
                cleanupError = error
            }
            if let failure = cleanupError as? ProtectedFilePolicyError,
               failure == .protectedDataUnavailable {
                throw failure
            }
            if let failure = originalError as? ProtectedFilePolicyError,
               failure == .protectedDataUnavailable {
                throw failure
            }
            throw BackupRestoreServiceError.materializationFailed
        }
    }

    func insert(
        _ records: V4BackupRecordsV1,
        into context: ModelContext,
        generationID: UUID,
        identityDecision: RestoreIdentityV1?,
        legacyDestinationIdentity: WorkspaceReplicaIdentityV1
    ) throws {
        guard (records.recordsSchemaVersion == 3)
                == (records.mutationHistory != nil) else {
            throw BackupRestoreServiceError.invalidPackage
        }
        switch (
            records.recordsSchemaVersion,
            records.deletionLedger,
            records.mutationHistory
        ) {
        case (1, nil, nil):
            break
        case (2, let ledger?, nil), (3, let ledger?, _):
            do {
                try ledger.validate()
                try DeletionLedgerStore(context: context).stageUnion(ledger.entries)
            } catch {
                throw BackupRestoreServiceError.invalidPackage
            }
        default:
            throw BackupRestoreServiceError.invalidPackage
        }
        for value in records.sites {
            context.insert(Site(
                id: value.id,
                label: value.label,
                address: value.address,
                timeZoneID: value.timeZoneID,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        for value in records.assets {
            context.insert(Asset(
                id: value.id,
                siteID: value.siteID,
                packID: value.packID,
                packSchemaVersion: value.packSchemaVersion,
                packContentVersion: value.packContentVersion,
                label: value.label,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        for value in records.workflowRecords {
            guard let revision = WorkflowRevisionKind(rawValue: value.revisionKind),
                  let stage = WorkflowStage(rawValue: value.stage),
                  let state = WorkflowState(rawValue: value.state),
                  value.draftStepKey == nil
                    || WorkflowDraftStep(rawValue: value.draftStepKey!) != nil else {
                throw BackupRestoreServiceError.invalidPackage
            }
            context.insert(WorkflowRecord(
                id: value.id,
                assetID: value.assetID,
                packetID: value.packetID,
                issueID: value.issueID,
                parentRecordID: value.parentRecordID,
                recordRevisionRootID: value.recordRevisionRootID,
                revisesRecordID: value.revisesRecordID,
                evidenceSourceRecordID: value.evidenceSourceRecordID,
                revisionKind: revision,
                stage: stage,
                state: state,
                draftStepKey: value.draftStepKey.flatMap(WorkflowDraftStep.init),
                startedAt: value.startedAt,
                completedAt: value.completedAt,
                observedAtUTC: value.observedAtUTC,
                timeZoneID: value.timeZoneID,
                utcOffsetMinutes: value.utcOffsetMinutes,
                localDate: value.localDate,
                localTime: value.localTime,
                afterDarkAcknowledgementKey: value.afterDarkAcknowledgementKey,
                afterDarkAcknowledgementCopy: value.afterDarkAcknowledgementCopy,
                afterDarkAcknowledgementVersion: value.afterDarkAcknowledgementVersion,
                afterDarkAcknowledgementAccepted:
                    value.afterDarkAcknowledgementAccepted,
                safePositionAcknowledgementKey:
                    value.safePositionAcknowledgementKey,
                safePositionAcknowledgementCopy:
                    value.safePositionAcknowledgementCopy,
                safePositionAcknowledgementVersion:
                    value.safePositionAcknowledgementVersion,
                safePositionAcknowledgementAccepted:
                    value.safePositionAcknowledgementAccepted,
                packID: value.packID,
                packSchemaVersion: value.packSchemaVersion,
                packContentVersion: value.packContentVersion,
                pdfTemplateID: value.pdfTemplateID,
                pdfTemplateVersion: value.pdfTemplateVersion,
                outcomeKey: value.outcomeKey,
                couldNotVerifyKey: value.couldNotVerifyKey,
                couldNotVerifyDisplaySnapshot:
                    value.couldNotVerifyDisplaySnapshot,
                couldNotVerifyRegistryVersion:
                    value.couldNotVerifyRegistryVersion,
                workPerformedLocalDate: value.workPerformedLocalDate,
                workDescription: value.workDescription,
                note: value.note,
                finalizationMutationID: value.finalizationMutationID
            ))
        }
        for value in records.evidenceFiles {
            context.insert(EvidenceFile(
                id: value.id,
                recordID: value.recordID,
                purposeKey: value.purposeKey,
                relativePath: value.relativePath,
                mimeType: value.mimeType,
                byteCount: value.byteCount,
                sha256: value.sha256,
                createdAt: value.createdAt,
                thumbnailRelativePath: value.thumbnailRelativePath,
                thumbnailByteCount: value.thumbnailByteCount,
                thumbnailSHA256: value.thumbnailSHA256
            ))
        }
        for value in records.issues {
            guard let status = IssueStatus(rawValue: value.status) else {
                throw BackupRestoreServiceError.invalidPackage
            }
            context.insert(Issue(
                id: value.id,
                assetID: value.assetID,
                openedByRecordID: value.openedByRecordID,
                labelKey: value.labelKey,
                labelDisplaySnapshot: value.labelDisplaySnapshot,
                status: status,
                resolvedByRecordID: value.resolvedByRecordID,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        for value in records.packets {
            context.insert(Packet(
                id: value.id,
                stableRootID: value.stableRootID,
                currentRecordID: value.currentRecordID,
                evaluationCounted: value.evaluationCounted,
                contentDeletedAt: value.contentDeletedAt,
                createdAt: value.createdAt
            ))
        }
        for value in records.reports {
            guard let state = ReportPDFState(rawValue: value.pdfState) else {
                throw BackupRestoreServiceError.invalidPackage
            }
            context.insert(Report(
                id: value.id,
                packetID: value.packetID,
                sourceRecordID: value.sourceRecordID,
                snapshotSchemaVersion: value.snapshotSchemaVersion,
                snapshotRelativePath: value.snapshotRelativePath,
                snapshotSHA256: value.snapshotSHA256,
                pdfState: state,
                pdfRelativePath: value.pdfRelativePath,
                pdfSHA256: value.pdfSHA256,
                createdAt: value.createdAt,
                replacesReportID: value.replacesReportID
            ))
        }
        if let mutationHistory = records.mutationHistory {
            guard records.recordsSchemaVersion == 3 else {
                throw BackupRestoreServiceError.invalidPackage
            }
            do {
                let identity = try identityDecision.map {
                    try workspaceIdentity($0)
                } ?? legacyDestinationIdentity
                let journal = try MutationJournalStoreV1(
                    modelContext: context,
                    identity: identity,
                    generationID: generationID
                )
                let disposition: MutationHistoryRestoreIdentityV1
                if identityDecision == nil
                    || (identityDecision?.mode == .replaceExisting
                        && identityDecision?.targetPointer.workspaceID
                            == identityDecision?.oldPointer.workspaceID
                        && identityDecision?.targetPointer.replicaID
                            == identityDecision?.oldPointer.replicaID) {
                    disposition = .preserve
                } else {
                    disposition = .destination(
                        identity,
                        generationID: generationID
                    )
                }
                try journal.replaceHistory(
                    with: mutationHistory,
                    identityDisposition: disposition
                )
            } catch {
                throw BackupRestoreServiceError.invalidPackage
            }
        }
    }

    func writeMembers(
        _ value: ValidatedV4BackupPackageV1,
        records: V4BackupRecordsV1,
        to root: URL,
        generationID: UUID
    ) throws {
        for evidence in records.evidenceFiles {
            let id = canonical(evidence.id)
            try protectStagingDirectory(
                root: root,
                relativePath: "evidence/\(id)",
                generationID: generationID
            )
            try writeExact(
                value.members["media/\(id).jpg"],
                to: root.appendingPathComponent(evidence.relativePath),
                expectedHash: evidence.sha256,
                generationID: generationID
            )
            try writeExact(
                value.members["thumbnails/\(id).jpg"],
                to: root.appendingPathComponent(evidence.thumbnailRelativePath),
                expectedHash: evidence.thumbnailSHA256,
                generationID: generationID
            )
        }
        if !records.reports.isEmpty {
            try protectStagingDirectory(
                root: root,
                relativePath: "snapshots",
                generationID: generationID
            )
        }
        if records.reports.contains(where: { $0.pdfState == "ready" }) {
            try protectStagingDirectory(
                root: root,
                relativePath: "pdfs",
                generationID: generationID
            )
        }
        for report in records.reports {
            try writeExact(
                value.members[report.snapshotRelativePath],
                to: root.appendingPathComponent(report.snapshotRelativePath),
                expectedHash: report.snapshotSHA256,
                generationID: generationID
            )
            if let path = report.pdfRelativePath,
               let hash = report.pdfSHA256 {
                try writeExact(
                    value.members[path],
                    to: root.appendingPathComponent(path),
                    expectedHash: hash,
                    generationID: generationID
                )
            }
        }
    }

    func writeExact(
        _ data: Data?,
        to url: URL,
        expectedHash: String,
        generationID: UUID
    ) throws {
        guard let data,
              CanonicalJSONV1.sha256(data) == expectedHash else {
            throw BackupRestoreServiceError.invalidPackage
        }
        let root = generationFactory.restoreStagingGenerationURL(id: generationID)
        let relative = try relativePath(of: url, within: root)
        let components = try validatedPathComponents(relative)
        guard let finalName = components.last else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        let parentRelative = components.dropLast().joined(separator: "/")
        let temporaryName = ".\(finalName).restore-next"
        let temporaryRelative = parentRelative.isEmpty
            ? temporaryName
            : "\(parentRelative)/\(temporaryName)"
        let authorityCheck = {
            try self.generationAuthority.requireStagingGeneration(id: generationID)
        }

        try withPinnedDirectory(
            root: root,
            relativePath: parentRelative,
            createMissing: false,
            authorityCheck: authorityCheck
        ) { parentDescriptor, verifyDirectories in
            guard try itemExists(parent: parentDescriptor, name: finalName) == false,
                  try itemExists(parent: parentDescriptor, name: temporaryName) == false else {
                throw BackupRestoreServiceError.materializationFailed
            }
            let descriptor = Darwin.openat(
                parentDescriptor,
                temporaryName,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
                mode_t(0o600)
            )
            guard descriptor >= 0 else {
                throw BackupRestoreServiceError.materializationFailed
            }
            defer { _ = Darwin.close(descriptor) }
            var temporaryIdentity: PinnedIdentity?
            do {
                try data.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress else { return }
                    var offset = 0
                    while offset < raw.count {
                        let count = Darwin.write(
                            descriptor,
                            base.advanced(by: offset),
                            raw.count - offset
                        )
                        if count > 0 {
                            offset += count
                        } else if errno != EINTR {
                            throw BackupRestoreServiceError.materializationFailed
                        }
                    }
                }
                guard Darwin.fsync(descriptor) == 0 else {
                    throw BackupRestoreServiceError.materializationFailed
                }
                var information = stat()
                guard Darwin.fstat(descriptor, &information) == 0,
                      (information.st_mode & S_IFMT) == S_IFREG,
                      information.st_nlink == 1 else {
                    throw BackupRestoreServiceError.invalidRestoreAuthority
                }
                let identity = PinnedIdentity(information)
                temporaryIdentity = identity
                try verifyDirectories()
                guard try itemIdentity(
                    parent: parentDescriptor,
                    name: temporaryName
                ) == identity else {
                    throw BackupRestoreServiceError.invalidRestoreAuthority
                }
                try ProtectedFilePolicyV1.applyAndVerify(
                    .stagingFile,
                    relativePath: temporaryRelative,
                    within: root,
                    authorityCheck: {
                        try verifyDirectories()
                        guard try itemIdentity(
                            parent: parentDescriptor,
                            name: temporaryName
                        ) == identity else {
                            throw BackupRestoreServiceError.invalidRestoreAuthority
                        }
                    }
                )
                guard try itemIdentity(
                    parent: parentDescriptor,
                    name: temporaryName
                ) == identity,
                      try itemExists(parent: parentDescriptor, name: finalName) == false else {
                    throw BackupRestoreServiceError.invalidRestoreAuthority
                }
                guard Darwin.renameatx_np(
                    parentDescriptor,
                    temporaryName,
                    parentDescriptor,
                    finalName,
                    UInt32(RENAME_EXCL)
                ) == 0,
                      Darwin.fsync(parentDescriptor) == 0 else {
                    throw BackupRestoreServiceError.materializationFailed
                }
                try ProtectedFilePolicyV1.applyAndVerify(
                    .stagingFile,
                    relativePath: relative,
                    within: root,
                    authorityCheck: {
                        try verifyDirectories()
                        guard try itemIdentity(
                            parent: parentDescriptor,
                            name: finalName
                        ) == identity else {
                            throw BackupRestoreServiceError.invalidRestoreAuthority
                        }
                    }
                )
                guard try itemIdentity(
                    parent: parentDescriptor,
                    name: finalName
                ) == identity,
                      try readRegularFile(
                          parent: parentDescriptor,
                          name: finalName,
                          expected: identity
                      ) == data else {
                    throw BackupRestoreServiceError.materializationFailed
                }
            } catch {
                if let temporaryIdentity,
                   let currentIdentity = try? itemIdentity(
                       parent: parentDescriptor,
                       name: temporaryName
                   ),
                   currentIdentity == temporaryIdentity {
                    _ = Darwin.unlinkat(parentDescriptor, temporaryName, 0)
                    _ = Darwin.fsync(parentDescriptor)
                }
                throw error
            }
        }
    }

    func protectStagingDirectory(
        root: URL,
        relativePath: String,
        generationID: UUID
    ) throws {
        let authorityCheck = {
            try self.generationAuthority.requireStagingGeneration(id: generationID)
        }
        try withPinnedDirectory(
            root: root,
            relativePath: relativePath,
            createMissing: true,
            authorityCheck: authorityCheck
        ) { _, verifyDirectories in
            try ProtectedFilePolicyV1.applyAndVerify(
                .stagingDirectory,
                relativePath: relativePath,
                within: root,
                authorityCheck: verifyDirectories
            )
        }
    }

    func protectGenerationTree(
        id: UUID,
        root: URL,
        staging: Bool
    ) throws {
        let root = root.standardizedFileURL
        let authorityCheck = {
            if staging {
                try self.generationAuthority.requireStagingGeneration(id: id)
            } else {
                try self.generationAuthority.requireInstalledGeneration(id: id)
            }
        }
        try withPinnedDirectory(
            root: root,
            relativePath: "",
            createMissing: false,
            authorityCheck: authorityCheck
        ) { _, verifyDirectories in
            try ProtectedFilePolicyV1.applyAndVerify(
                staging ? .restoreStaging : .durableDirectory,
                at: root,
                authorityCheck: verifyDirectories
            )
        }
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        for case let url as URL in enumerator {
            let relativePath = try relativePath(of: url, within: root)
            var information = stat()
            guard Darwin.lstat(url.path, &information) == 0 else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            let kind: OwnedFileKindV1
            switch information.st_mode & S_IFMT {
            case S_IFDIR:
                kind = staging || relativePath == ".staging"
                    || relativePath.hasPrefix(".staging/")
                    ? .stagingDirectory
                    : .durableDirectory
            case S_IFREG:
                if staging {
                    kind = .stagingFile
                } else {
                    kind = try installedFileKind(relativePath)
                }
            default:
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            try withPinnedExistingItem(
                root: root,
                relativePath: relativePath,
                expectedDirectory: (information.st_mode & S_IFMT) == S_IFDIR,
                authorityCheck: authorityCheck
            ) { _, _, verifyItem in
                try ProtectedFilePolicyV1.applyAndVerify(
                    kind,
                    relativePath: relativePath,
                    within: root,
                    authorityCheck: verifyItem
                )
            }
        }
        if let enumerationError {
            throw enumerationError
        }
        try authorityCheck()
    }

    private func validatedPathComponents(
        _ relativePath: String
    ) throws -> [String] {
        guard !relativePath.hasPrefix("/"),
              !relativePath.hasPrefix("\\"),
              !relativePath.contains("\\") else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        if relativePath.isEmpty { return [] }
        let components = relativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({
                  !$0.isEmpty && $0 != "." && $0 != ".."
              }) else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        return components
    }

    private func withPinnedDirectory<T>(
        root: URL,
        relativePath: String,
        createMissing: Bool,
        authorityCheck: () throws -> Void,
        body: (Int32, () throws -> Void) throws -> T
    ) throws -> T {
        let components = try validatedPathComponents(relativePath)
        try authorityCheck()
        let rootDescriptor = Darwin.open(
            root.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard rootDescriptor >= 0 else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        var descriptors = [rootDescriptor]
        defer {
            for descriptor in descriptors.reversed() {
                _ = Darwin.close(descriptor)
            }
        }

        var rootInformation = stat()
        guard Darwin.fstat(rootDescriptor, &rootInformation) == 0,
              (rootInformation.st_mode & S_IFMT) == S_IFDIR else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        var pins = [PinnedDirectory(
            descriptor: rootDescriptor,
            identity: PinnedIdentity(rootInformation),
            parent: nil,
            name: nil
        )]
        var current = rootDescriptor
        for component in components {
            var descriptor = Darwin.openat(
                current,
                component,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            if descriptor < 0, errno == ENOENT, createMissing {
                guard Darwin.mkdirat(
                    current,
                    component,
                    mode_t(0o700)
                ) == 0 || errno == EEXIST,
                      Darwin.fsync(current) == 0 else {
                    throw BackupRestoreServiceError.invalidRestoreAuthority
                }
                descriptor = Darwin.openat(
                    current,
                    component,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW
                )
            }
            guard descriptor >= 0 else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            descriptors.append(descriptor)
            var information = stat()
            guard Darwin.fstat(descriptor, &information) == 0,
                  (information.st_mode & S_IFMT) == S_IFDIR else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            pins.append(PinnedDirectory(
                descriptor: descriptor,
                identity: PinnedIdentity(information),
                parent: current,
                name: component
            ))
            current = descriptor
        }

        let pinned = pins
        func verifyDirectories() throws {
            try authorityCheck()
            for pin in pinned {
                var information = stat()
                guard Darwin.fstat(pin.descriptor, &information) == 0,
                      PinnedIdentity(information) == pin.identity else {
                    throw BackupRestoreServiceError.invalidRestoreAuthority
                }
                if let parent = pin.parent, let name = pin.name {
                    var pathInformation = stat()
                    guard Darwin.fstatat(
                        parent,
                        name,
                        &pathInformation,
                        AT_SYMLINK_NOFOLLOW
                    ) == 0,
                          PinnedIdentity(pathInformation) == pin.identity else {
                        throw BackupRestoreServiceError.invalidRestoreAuthority
                    }
                }
            }
        }
        try verifyDirectories()
        let result = try body(current, verifyDirectories)
        try verifyDirectories()
        return result
    }

    private func withPinnedExistingItem<T>(
        root: URL,
        relativePath: String,
        expectedDirectory: Bool,
        authorityCheck: () throws -> Void,
        body: (Int32, Int32, () throws -> Void) throws -> T
    ) throws -> T {
        let components = try validatedPathComponents(relativePath)
        guard let name = components.last else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        let parentRelative = components.dropLast().joined(separator: "/")
        return try withPinnedDirectory(
            root: root,
            relativePath: parentRelative,
            createMissing: false,
            authorityCheck: authorityCheck
        ) { parentDescriptor, verifyDirectories in
            let flags: Int32 = expectedDirectory
                ? (O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                : (O_RDONLY | O_NOFOLLOW)
            let descriptor = Darwin.openat(parentDescriptor, name, flags)
            guard descriptor >= 0 else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            defer { _ = Darwin.close(descriptor) }
            var information = stat()
            guard Darwin.fstat(descriptor, &information) == 0 else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            let identity = PinnedIdentity(information)
            let expectedType = expectedDirectory
                ? UInt32(S_IFDIR)
                : UInt32(S_IFREG)
            guard identity.type == expectedType,
                  expectedDirectory || identity.linkCount == 1 else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            func verifyItem() throws {
                try verifyDirectories()
                guard try itemIdentity(
                    parent: parentDescriptor,
                    name: name
                ) == identity else {
                    throw BackupRestoreServiceError.invalidRestoreAuthority
                }
                var descriptorInformation = stat()
                guard Darwin.fstat(descriptor, &descriptorInformation) == 0,
                      PinnedIdentity(descriptorInformation) == identity else {
                    throw BackupRestoreServiceError.invalidRestoreAuthority
                }
            }
            try verifyItem()
            let result = try body(parentDescriptor, descriptor, verifyItem)
            try verifyItem()
            return result
        }
    }

    private func itemExists(
        parent: Int32,
        name: String
    ) throws -> Bool {
        var information = stat()
        if Darwin.fstatat(
            parent,
            name,
            &information,
            AT_SYMLINK_NOFOLLOW
        ) == 0 {
            return true
        }
        if errno == ENOENT { return false }
        throw BackupRestoreServiceError.invalidRestoreAuthority
    }

    private func itemIdentity(
        parent: Int32,
        name: String
    ) throws -> PinnedIdentity {
        var information = stat()
        guard Darwin.fstatat(
            parent,
            name,
            &information,
            AT_SYMLINK_NOFOLLOW
        ) == 0 else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        guard (information.st_mode & S_IFMT) != S_IFLNK else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        return PinnedIdentity(information)
    }

    private func readRegularFile(
        parent: Int32,
        name: String,
        expected: PinnedIdentity
    ) throws -> Data {
        let descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        defer { _ = Darwin.close(descriptor) }
        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0,
              PinnedIdentity(before) == expected,
              expected.type == UInt32(S_IFREG),
              expected.linkCount == 1 else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count > 0 {
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                break
            } else if errno != EINTR {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
        }
        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              PinnedIdentity(after) == expected,
              data.count == Int(after.st_size),
              try itemIdentity(parent: parent, name: name) == expected else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        return data
    }

    func installedFileKind(_ relativePath: String) throws -> OwnedFileKindV1 {
        switch relativePath {
        case Self.modelStoreName:
            return .database
        case "\(Self.modelStoreName)-wal":
            return .databaseWAL
        case "\(Self.modelStoreName)-shm":
            return .databaseSHM
        case ".staging":
            throw BackupRestoreServiceError.invalidRestoreAuthority
        default:
            let components = relativePath.split(separator: "/").map(String.init)
            guard components.count == 3 || components.count == 2 else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            if components.first == "evidence",
               components.count == 3,
               let id = UUID(uuidString: components[1]),
               canonical(id) == components[1],
               components.last == "original.jpg" {
                return .mediaOriginal
            }
            if components.first == "evidence",
               components.count == 3,
               let id = UUID(uuidString: components[1]),
               canonical(id) == components[1],
               components.last == "thumbnail.jpg" {
                return .mediaThumbnail
            }
            if components.first == "snapshots",
               components.count == 2,
               let id = UUID(uuidString: components[1].replacingOccurrences(of: ".json", with: "")),
               "\(canonical(id)).json" == components[1],
               components.last?.hasSuffix(".json") == true {
                return .reportSnapshot
            }
            if components.first == "pdfs",
               components.count == 2,
               let id = UUID(uuidString: components[1].replacingOccurrences(of: ".pdf", with: "")),
               "\(canonical(id)).pdf" == components[1],
               components.last?.hasSuffix(".pdf") == true {
                return .reportPDF
            }
            if components.first == ".staging" {
                return .stagingFile
            }
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
    }

    func relativePath(of url: URL, within root: URL) throws -> String {
        let rootPath = root.standardizedFileURL.path
        let valuePath = url.standardizedFileURL.path
        guard valuePath.hasPrefix(rootPath + "/") else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        let value = String(valuePath.dropFirst(rootPath.count + 1))
        guard !value.isEmpty,
              !value.contains("\\"),
              !value.split(separator: "/", omittingEmptySubsequences: false)
                .contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        return value
    }

    func validateStagingGeneration(
        id: UUID,
        expected: V4BackupRecordsV1,
        identity: WorkspaceReplicaIdentityV1? = nil
    ) throws {
        let session: StoreGenerationSession
        if let identity {
            session = try generationFactory.openRestoreStagingGeneration(
                id: id,
                identity: identity,
                authority: generationAuthority
            )
        } else {
            session = try generationFactory.openRestoreStagingGeneration(
                id: id,
                authority: generationAuthority
            )
        }
        try protectGenerationTree(
            id: id,
            root: session.generationRootURL,
            staging: true
        )
        try validateRows(session.modelContext, expected: expected)
        try validateFrozenFiles(
            root: session.generationRootURL,
            records: expected,
            authorityCheck: {
                try generationAuthority.requireStagingGeneration(id: id)
            }
        )
        try validateGenerationTree(
            generationAuthority.stagingTree(id: id),
            records: expected
        )
    }

    func validateInstalledGeneration(
        id: UUID,
        expected: V4BackupRecordsV1,
        identity: WorkspaceReplicaIdentityV1? = nil
    ) throws {
        let session: StoreGenerationSession
        if let identity {
            session = try generationFactory.openInstalledGeneration(
                id: id,
                identity: identity,
                authority: generationAuthority
            )
        } else {
            session = try generationFactory.openInstalledGeneration(
                id: id,
                authority: generationAuthority
            )
        }
        try protectGenerationTree(
            id: id,
            root: session.generationRootURL,
            staging: false
        )
        try validateUnpublishedTargetSession(
            session,
            expected: expected,
            staging: false
        )
    }

    func validateUnpublishedTargetSession(
        _ session: StoreGenerationSession,
        expected: V4BackupRecordsV1,
        staging: Bool
    ) throws {
        guard !session.modelContext.hasChanges else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        try validateRows(session.modelContext, expected: expected)
        try validateFrozenFiles(
            root: session.generationRootURL,
            records: expected,
            authorityCheck: {
                if staging {
                    try generationAuthority.requireStagingGeneration(
                        id: session.generationID
                    )
                } else {
                    try generationAuthority.requireInstalledGeneration(
                        id: session.generationID
                    )
                }
            }
        )
        let tree: StoreRestoreGenerationAuthority.Tree
        if staging {
            tree = try generationAuthority.stagingTree(id: session.generationID)
        } else {
            tree = try generationAuthority.installedTree(id: session.generationID)
        }
        try validateGenerationTree(tree, records: expected)
    }

    func validateLiveSession(
        _ session: StoreGenerationSession,
        expected: V4BackupRecordsV1?
    ) throws {
        guard !session.modelContext.hasChanges else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        if let expected {
            try validateRows(session.modelContext, expected: expected)
        }
        do {
            _ = try BackupExportService(
                modelContext: session.modelContext,
                generationRootURL: session.generationRootURL,
                now: { Date(timeIntervalSince1970: 0) }
            ).prepareStreaming()
        } catch let failure as ProtectedFilePolicyError
            where failure == .protectedDataUnavailable {
            throw failure
        } catch {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        let frozenRecords: V4BackupRecordsV1
        if let expected {
            frozenRecords = expected
        } else {
            frozenRecords = try records(in: session.modelContext)
        }
        try validateGenerationTree(
            generationAuthority.installedTree(id: session.generationID),
            records: frozenRecords
        )
    }

    func validateGenerationTree(
        _ tree: StoreRestoreGenerationAuthority.Tree,
        records: V4BackupRecordsV1
    ) throws {
        let expected = expectedGenerationTree(records: records)
        let allowedDirectories = expected.directories.union(
            allowedEmptyStagingDirectories
        )
        guard expected.directories.isSubset(of: tree.directories),
              tree.directories.isSubset(of: allowedDirectories),
              expected.files.isSubset(of: tree.files),
              tree.files.isSubset(of: expected.files.union(expected.optionalFiles)) else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
    }

    func requireNoUnexpectedInstalledBytes(id: UUID) throws {
        let session = try generationFactory.openInstalledGeneration(
            id: id,
            authority: generationAuthority
        )
        try protectGenerationTree(
            id: id,
            root: session.generationRootURL,
            staging: false
        )
        let frozenRecords = try records(in: session.modelContext)
        let tree = try generationAuthority.installedTree(id: id)
        let expected = expectedGenerationTree(records: frozenRecords)
        guard tree.directories.isSubset(
                  of: expected.directories.union(allowedEmptyStagingDirectories)
              ),
              tree.files.isSubset(of: expected.files.union(expected.optionalFiles)) else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
    }

    func requireNoUnexpectedStagingBytes(id: UUID) throws {
        let session = try generationFactory.openRestoreStagingGeneration(
            id: id,
            authority: generationAuthority
        )
        try protectGenerationTree(
            id: id,
            root: session.generationRootURL,
            staging: true
        )
        let frozenRecords = try records(in: session.modelContext)
        let tree = try generationAuthority.stagingTree(id: id)
        let expected = expectedGenerationTree(records: frozenRecords)
        guard tree.directories.isSubset(
                  of: expected.directories.union(allowedEmptyStagingDirectories)
              ),
              tree.files.isSubset(of: expected.files.union(expected.optionalFiles)) else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
    }

    func expectedGenerationTree(
        records: V4BackupRecordsV1
    ) -> (
        directories: Set<String>,
        files: Set<String>,
        optionalFiles: Set<String>
    ) {
        var expectedFiles: Set<String> = ["model.sqlite"]
        var expectedDirectories = Set<String>()
        if !records.evidenceFiles.isEmpty {
            expectedDirectories.insert("evidence")
        }
        for evidence in records.evidenceFiles {
            expectedDirectories.insert("evidence/\(canonical(evidence.id))")
            expectedFiles.insert(evidence.relativePath)
            expectedFiles.insert(evidence.thumbnailRelativePath)
        }
        if !records.reports.isEmpty {
            expectedDirectories.insert("snapshots")
        }
        if records.reports.contains(where: {
            $0.pdfState == ReportPDFState.ready.rawValue
        }) {
            expectedDirectories.insert("pdfs")
        }
        for report in records.reports {
            expectedFiles.insert(report.snapshotRelativePath)
            if let path = report.pdfRelativePath {
                expectedFiles.insert(path)
            }
        }
        let optionalSQLiteSidecars: Set<String> = [
            "model.sqlite-shm",
            "model.sqlite-wal",
        ]
        return (
            expectedDirectories,
            expectedFiles,
            optionalSQLiteSidecars
        )
    }

    var allowedEmptyStagingDirectories: Set<String> {
        [
            ".staging",
            ".staging/evidence",
            ".staging/pdfs",
            ".staging/snapshots",
        ]
    }

    func validInstalledGeneration(
        id: UUID,
        identity: WorkspaceReplicaIdentityV1? = nil,
        requireExportReconciliation: Bool = true
    ) throws -> StoreGenerationSession? {
        let session: StoreGenerationSession
        do {
            if let identity {
                session = try generationFactory.openInstalledGeneration(
                    id: id,
                    identity: identity,
                    authority: generationAuthority
                )
            } else {
                session = try generationFactory.openInstalledGeneration(
                    id: id,
                    authority: generationAuthority
                )
            }
        } catch let failure as ProtectedFilePolicyError
            where failure == .protectedDataUnavailable {
            throw failure
        } catch {
            return nil
        }
        do {
            try protectGenerationTree(
                id: id,
                root: session.generationRootURL,
                staging: false
            )
        } catch let failure as ProtectedFilePolicyError
            where failure == .protectedDataUnavailable {
            throw failure
        } catch {
            return nil
        }
        do {
            let frozenRecords = try records(in: session.modelContext)
            if requireExportReconciliation {
                try validateLiveSession(session, expected: frozenRecords)
            } else {
                try validateUnpublishedTargetSession(
                    session,
                    expected: frozenRecords,
                    staging: false
                )
            }
        } catch let failure as ProtectedFilePolicyError
            where failure == .protectedDataUnavailable {
            throw failure
        } catch {
            return nil
        }
        return session
    }

    func validStagingGenerationRecords(
        id: UUID,
        identity: WorkspaceReplicaIdentityV1? = nil
    ) throws -> V4BackupRecordsV1? {
        do {
            let session: StoreGenerationSession
            if let identity {
                session = try generationFactory.openRestoreStagingGeneration(
                    id: id,
                    identity: identity,
                    authority: generationAuthority
                )
            } else {
                session = try generationFactory.openRestoreStagingGeneration(
                    id: id,
                    authority: generationAuthority
                )
            }
            try protectGenerationTree(
                id: id,
                root: session.generationRootURL,
                staging: true
            )
            guard !session.modelContext.hasChanges else { return nil }
            let frozenRecords = try records(in: session.modelContext)
            try validateFrozenFiles(
                root: session.generationRootURL,
                records: frozenRecords,
                authorityCheck: {
                    try generationAuthority.requireStagingGeneration(id: id)
                }
            )
            try validateGenerationTree(
                generationAuthority.stagingTree(id: id),
                records: frozenRecords
            )
            return frozenRecords
        } catch let failure as ProtectedFilePolicyError
            where failure == .protectedDataUnavailable {
            throw failure
        } catch {
            return nil
        }
    }

    func validMonotonicUnion(
        from current: V4BackupRecordsV1,
        to replacement: V4BackupRecordsV1
    ) -> Bool {
        guard let plan = try? ReplacementRestoreRule.makeDeletionWinningPlan(
            DeletionWinningRestoreInputV2(
                currentRecords: current,
                incomingRecords: replacement,
                mode: .replaceExisting,
                replacementAt: now()
            )
        ) else {
            return false
        }
        return plan.recordsAfter == replacement
    }

    func validateRows(
        _ context: ModelContext,
        expected: V4BackupRecordsV1
    ) throws {
        guard try records(in: context) == expected else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
    }

    func validateFrozenFiles(
        root: URL,
        records: V4BackupRecordsV1,
        authorityCheck: () throws -> Void = {}
    ) throws {
        try authorityCheck()
        for evidence in records.evidenceFiles {
            let original = try readValidatedRegularFile(
                root: root,
                relativePath: evidence.relativePath,
                authorityCheck: authorityCheck
            )
            let thumbnail = try readValidatedRegularFile(
                root: root,
                relativePath: evidence.thumbnailRelativePath,
                authorityCheck: authorityCheck
            )
            guard original.count == evidence.byteCount,
                  thumbnail.count == evidence.thumbnailByteCount,
                  CanonicalJSONV1.sha256(original) == evidence.sha256,
                  CanonicalJSONV1.sha256(thumbnail) == evidence.thumbnailSHA256 else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
        }
        for report in records.reports {
            let snapshot = try readValidatedRegularFile(
                root: root,
                relativePath: report.snapshotRelativePath,
                authorityCheck: authorityCheck
            )
            guard CanonicalJSONV1.sha256(snapshot) == report.snapshotSHA256 else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            if let path = report.pdfRelativePath,
               let hash = report.pdfSHA256 {
                let pdf = try readValidatedRegularFile(
                    root: root,
                    relativePath: path,
                    authorityCheck: authorityCheck
                )
                guard CanonicalJSONV1.sha256(pdf) == hash else {
                    throw BackupRestoreServiceError.invalidRestoreAuthority
                }
            }
        }
        try authorityCheck()
    }

    private func readValidatedRegularFile(
        root: URL,
        relativePath: String,
        authorityCheck: () throws -> Void
    ) throws -> Data {
        let components = try validatedPathComponents(relativePath)
        guard let name = components.last else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        return try withPinnedExistingItem(
            root: root,
            relativePath: relativePath,
            expectedDirectory: false,
            authorityCheck: authorityCheck
        ) { parentDescriptor, descriptor, verifyItem in
            var information = stat()
            guard Darwin.fstat(descriptor, &information) == 0,
                  (information.st_mode & S_IFMT) == S_IFREG,
                  information.st_nlink == 1 else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            let identity = PinnedIdentity(information)
            try verifyItem()
            let data = try readRegularFile(
                parent: parentDescriptor,
                name: name,
                expected: identity
            )
            try verifyItem()
            return data
        }
    }

    func records(in context: ModelContext) throws -> V4BackupRecordsV1 {
        try records(in: context, includingDeletionLedger: true)
    }

    func records(
        in context: ModelContext,
        includingDeletionLedger: Bool
    ) throws -> V4BackupRecordsV1 {
        let sites = try context.fetch(FetchDescriptor<Site>())
        let assets = try context.fetch(FetchDescriptor<Asset>())
        let workflow = try context.fetch(FetchDescriptor<WorkflowRecord>())
        let evidence = try context.fetch(FetchDescriptor<EvidenceFile>())
        let issues = try context.fetch(FetchDescriptor<Issue>())
        let packets = try context.fetch(FetchDescriptor<Packet>())
        let reports = try context.fetch(FetchDescriptor<Report>())
        let deletionLedger: DeletionLedgerV2?
        let mutationHistory: MutationHistorySnapshotV1?
        if includingDeletionLedger {
            deletionLedger = try DeletionLedgerStore(context: context).snapshot()
            mutationHistory = try mutationHistory(in: context)
        } else {
            deletionLedger = nil
            mutationHistory = nil
        }
        return V4BackupRecordsV1(
            assets: assets.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion, siteID: $0.siteID,
                    packID: $0.packID, packSchemaVersion: $0.packSchemaVersion,
                    packContentVersion: $0.packContentVersion, label: $0.label,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt
                )
            }.sorted { canonical($0.id) < canonical($1.id) },
            deletionLedger: deletionLedger,
            evidenceFiles: evidence.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion,
                    recordID: $0.recordID, purposeKey: $0.purposeKey,
                    relativePath: $0.relativePath, mimeType: $0.mimeType,
                    byteCount: $0.byteCount, sha256: $0.sha256,
                    createdAt: $0.createdAt,
                    thumbnailRelativePath: $0.thumbnailRelativePath,
                    thumbnailByteCount: $0.thumbnailByteCount,
                    thumbnailSHA256: $0.thumbnailSHA256
                )
            }.sorted { canonical($0.id) < canonical($1.id) },
            issues: issues.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion,
                    assetID: $0.assetID, openedByRecordID: $0.openedByRecordID,
                    labelKey: $0.labelKey,
                    labelDisplaySnapshot: $0.labelDisplaySnapshot,
                    status: $0.status,
                    resolvedByRecordID: $0.resolvedByRecordID,
                    createdAt: $0.createdAt, updatedAt: $0.updatedAt
                )
            }.sorted { canonical($0.id) < canonical($1.id) },
            mutationHistory: mutationHistory,
            packets: packets.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion,
                    stableRootID: $0.stableRootID,
                    currentRecordID: $0.currentRecordID,
                    evaluationCounted: $0.evaluationCounted,
                    contentDeletedAt: $0.contentDeletedAt,
                    createdAt: $0.createdAt
                )
            }.sorted { canonical($0.id) < canonical($1.id) },
            recordsSchemaVersion: mutationHistory == nil
                ? (includingDeletionLedger ? 2 : 1)
                : 3,
            reports: reports.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion,
                    packetID: $0.packetID, sourceRecordID: $0.sourceRecordID,
                    snapshotSchemaVersion: $0.snapshotSchemaVersion,
                    snapshotRelativePath: $0.snapshotRelativePath,
                    snapshotSHA256: $0.snapshotSHA256, pdfState: $0.pdfState,
                    pdfRelativePath: $0.pdfRelativePath,
                    pdfSHA256: $0.pdfSHA256, createdAt: $0.createdAt,
                    replacesReportID: $0.replacesReportID
                )
            }.sorted { canonical($0.id) < canonical($1.id) },
            sites: sites.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion,
                    label: $0.label, address: $0.address,
                    timeZoneID: $0.timeZoneID, createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }.sorted { canonical($0.id) < canonical($1.id) },
            workflowRecords: workflow.map(workflowDTO)
                .sorted { canonical($0.id) < canonical($1.id) }
        )
    }

    func mutationHistory(
        in context: ModelContext
    ) throws -> MutationHistorySnapshotV1? {
        var descriptor = FetchDescriptor<WorkspaceMutationStateRow>()
        descriptor.fetchLimit = 2
        let states = try context.fetch(descriptor)
        guard states.count <= 1 else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        guard let state = states.first else {
            let receiptCount = try context.fetchCount(
                FetchDescriptor<MutationReceiptRow>()
            )
            let quarantineCount = try context.fetchCount(
                FetchDescriptor<MutationQuarantineRow>()
            )
            let revisionCount = try context.fetchCount(
                FetchDescriptor<EntityMutationRevisionRow>()
            )
            guard receiptCount == 0,
                  quarantineCount == 0,
                  revisionCount == 0 else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            return nil
        }
        do {
            let identity = try WorkspaceReplicaIdentityV1(
                workspaceID: WorkspaceID(rawValue: state.workspaceID),
                replicaID: ReplicaID(rawValue: state.activeReplicaID)
            )
            return try MutationJournalStoreV1(
                modelContext: context,
                identity: identity,
                generationID: state.generationID
            ).exportSnapshot()
        } catch {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
    }

    func workflowDTO(_ value: WorkflowRecord) -> V4BackupWorkflowRecordDTO {
        .init(
            id: value.id, schemaVersion: value.schemaVersion,
            assetID: value.assetID, packetID: value.packetID,
            issueID: value.issueID, parentRecordID: value.parentRecordID,
            recordRevisionRootID: value.recordRevisionRootID,
            revisesRecordID: value.revisesRecordID,
            evidenceSourceRecordID: value.evidenceSourceRecordID,
            revisionKind: value.revisionKind, stage: value.stage,
            state: value.state, draftStepKey: value.draftStepKey,
            startedAt: value.startedAt, completedAt: value.completedAt,
            observedAtUTC: value.observedAtUTC, timeZoneID: value.timeZoneID,
            utcOffsetMinutes: value.utcOffsetMinutes, localDate: value.localDate,
            localTime: value.localTime,
            afterDarkAcknowledgementKey: value.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: value.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: value.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted:
                value.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: value.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy:
                value.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion:
                value.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted:
                value.safePositionAcknowledgementAccepted,
            packID: value.packID, packSchemaVersion: value.packSchemaVersion,
            packContentVersion: value.packContentVersion,
            pdfTemplateID: value.pdfTemplateID,
            pdfTemplateVersion: value.pdfTemplateVersion,
            outcomeKey: value.outcomeKey,
            couldNotVerifyKey: value.couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: value.couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: value.couldNotVerifyRegistryVersion,
            workPerformedLocalDate: value.workPerformedLocalDate,
            workDescription: value.workDescription, note: value.note,
            finalizationMutationID: value.finalizationMutationID
        )
    }

    func discardImportedPackage(
        _ value: ValidatedV4BackupPackageV1,
        _ currentGenerationRootURL: URL
    ) throws {
        do {
            try BackupImportService(
                generationRootURL: currentGenerationRootURL,
                scopedAccess: .alreadyAuthorized
            ).discard(value)
        } catch let failure as ProtectedFilePolicyError
            where failure == .protectedDataUnavailable {
            throw failure
        } catch {
            throw BackupRestoreServiceError.materializationFailed
        }
    }

    func cleanupAbandonedRestoreStaging() throws {
        let currentID = try generationFactory.currentGenerationID(
            authority: generationAuthority
        )
        for name in try generationAuthority.restoreGenerationNames() {
            guard let id = UUID(uuidString: name), canonical(id) == name else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            let digest = try generationFactory
                .prepareRestoreStagingGenerationManifest(
                    expectedOldID: currentID,
                    newID: id,
                    authority: generationAuthority
                )
            try discardPrepublicationStagingGeneration(
                id: id,
                expectedDigest: digest
            )
        }
        for name in try generationAuthority.importStagingNames() {
            let url = URL(fileURLWithPath: name)
            let canonicalName = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == "fieldrecordbackup",
                  let id = UUID(uuidString: canonicalName),
                  canonical(id) == canonicalName else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            try generationAuthority.removeImportStagingPackage(name: name)
        }
        try cleanupEmptyRestoreDirectories()
    }

    func discardPrepublicationStagingGeneration(
        id: UUID,
        expectedDigest: String?
    ) throws {
        if let expectedDigest {
            let currentID = try generationFactory.currentGenerationID(
                authority: generationAuthority
            )
            let observed = try generationFactory
                .prepareRestoreStagingGenerationManifest(
                    expectedOldID: currentID,
                    newID: id,
                    authority: generationAuthority
                )
            guard observed == expectedDigest else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            try removePreparedRestoreManifestBeforeDiscard(
                expectedOldID: currentID,
                generationID: id,
                expectedDigest: expectedDigest
            )
        }
        try generationFactory.removeRestoreStagingGeneration(
            id: id,
            authority: generationAuthority
        )
    }

    func removePreparedRestoreManifestBeforeDiscard(
        expectedOldID: UUID,
        generationID: UUID,
        expectedDigest: String?
    ) throws {
        guard let expectedDigest else { return }
        try generationFactory
            .removePreparedRestoreGenerationManifestBeforeDiscard(
                expectedOldID: expectedOldID,
                generationID: generationID,
                expectedDigest: expectedDigest,
                authority: generationAuthority
            )
    }

    func cleanupEmptyRestoreDirectories() throws {
        // These empty parents remain pinned for the service lifetime. Removing
        // and recreating them would weaken the authority that makes recovery
        // cleanup descriptor-relative.
        try generationAuthority.verify()
    }

    func inject(_ point: BackupRestoreFailurePoint) throws {
        if failureInjection?.consume(point) == true {
            throw BackupRestoreServiceError.injectedFailure
        }
    }

    func canonical(_ value: UUID) -> String {
        value.uuidString.lowercased()
    }
}

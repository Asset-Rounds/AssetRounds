import Darwin
import Foundation
import SwiftData

enum IntegrationProjectionBackupRestoreExclusionV1 {
    static func validate() throws {
        let coverage = IntegrationEventJournalCoverageV1()
        try coverage.validate()
        guard !coverage.backupIncluded, !coverage.restoreIncluded,
              IntegrationProjectionSchemaV1.downgradeDisposition == "DROP_AND_REBUILD"
        else { throw BackupRestoreServiceError.invalidRestoreAuthority }
    }
}

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
    private struct DraftRestorePublicationBindingV1: Codable, Equatable {
        let schemaVersion: Int
        let receipt: DraftAttachmentRestorePublicationReceiptV1

        init(receipt: DraftAttachmentRestorePublicationReceiptV1) throws {
            try receipt.validate()
            schemaVersion = 1
            self.receipt = receipt
        }

        func validate() throws {
            guard schemaVersion == 1 else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            try receipt.validate()
        }
    }

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
    private let lifecycleRoute: BackupPackageLifecycleRouteV1
    private let generationFactory: StoreGenerationFactory
    private var generationAuthority: StoreRestoreGenerationAuthority!
    private let intentStore: RestoreIntentStore
    private let storagePreflight: StoragePreflightService
    private let fileManager: FileManager
    private let now: () -> Date
    private let makeUUID: () -> UUID
    private let failureInjection: BackupRestoreFailureInjection?
    private let searchIndexLifecycle: any SearchIndexLifecyclePortV1

    init(
        applicationSupportURL: URL,
        lifecycleRoute: BackupPackageLifecycleRouteV1,
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
        self.lifecycleRoute = lifecycleRoute
        self.generationFactory = factory
        self.generationAuthority = authority
        self.intentStore = store
        self.storagePreflight = storagePreflight
        self.fileManager = fileManager
        self.now = now
        self.makeUUID = makeUUID
        self.failureInjection = failureInjection
        self.searchIndexLifecycle = try LocalSearchIndexStoreV1(
            applicationSupportURL: root,
            fileManager: fileManager
        )
    }

    convenience init(
        applicationSupportURL: URL,
        lifecycleDependencies: WorkspacePackageLifecycleDependenciesV1,
        fileManager: FileManager = .default,
        storagePreflight: StoragePreflightService = StoragePreflightService(),
        now: @escaping () -> Date = Date.init,
        makeUUID: @escaping () -> UUID = UUID.init,
        failureInjection: BackupRestoreFailureInjection? = nil
    ) throws {
        try self.init(
            applicationSupportURL: applicationSupportURL,
            lifecycleRoute: .live(lifecycleDependencies),
            fileManager: fileManager,
            storagePreflight: storagePreflight,
            now: now,
            makeUUID: makeUUID,
            failureInjection: failureInjection
        )
    }

    convenience init(
        applicationSupportURL: URL,
        fileManager: FileManager = .default,
        storagePreflight: StoragePreflightService = StoragePreflightService(),
        now: @escaping () -> Date = Date.init,
        makeUUID: @escaping () -> UUID = UUID.init,
        failureInjection: BackupRestoreFailureInjection? = nil,
        compatibilityPosture: BackupPackageCompatibilityPostureV1 = .frozenLegacyCallersOnly
    ) throws {
        try self.init(
            applicationSupportURL: applicationSupportURL,
            lifecycleRoute: .expiringCompatibility(compatibilityPosture),
            fileManager: fileManager,
            storagePreflight: storagePreflight,
            now: now,
            makeUUID: makeUUID,
            failureInjection: failureInjection
        )
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
            var observationAndTime = FetchDescriptor<ObservationAndTimeRow>()
            observationAndTime.fetchLimit = 1
            let hasNoObservationAndTime = try modelContext.fetch(
                observationAndTime
            ).isEmpty
            return try modelContext.fetchCount(FetchDescriptor<Site>()) == 0
                && modelContext.fetchCount(FetchDescriptor<Asset>()) == 0
                && modelContext.fetchCount(FetchDescriptor<InspectionReviewTransitionRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<ReviewDispositionRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<ChangeRequestRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<CorrectiveActionPolicyRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<CorrectiveActionEventRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<AttachmentStagingItemRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<DraftCommitSagaRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<DraftContentReservationRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<DraftCommitReceiptRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<DraftDiscardReceiptRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<WorkPacketManifestRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<WorkItemClaimRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<WorkLeaseRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<WorkReleaseRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<WorkHandoffRow>()) == 0
                && modelContext.fetchCount(
                    FetchDescriptor<AssetKindBindingEventRow>()
                ) == 0
                && modelContext.fetchCount(
                    FetchDescriptor<AssetWorkflowCapabilityBindingEventRow>()
                ) == 0
                && modelContext.fetchCount(
                    FetchDescriptor<AssetProductIdentityRow>()
                ) == 0
                && modelContext.fetchCount(
                    FetchDescriptor<AssetLifecycleEventRow>()
                ) == 0
                && modelContext.fetchCount(
                    FetchDescriptor<AssetSuccessorLinkRow>()
                ) == 0
                && modelContext.fetchCount(
                    FetchDescriptor<WorkSubjectScopeSnapshotRow>()
                ) == 0
                && modelContext.fetchCount(FetchDescriptor<AuthoritySourceReleaseRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<RequirementBasisBindingRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<ApplicabilityContextSnapshotRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<AssessmentScopeSnapshotRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<SeverityScaleReleaseRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<FindingClassificationBindingRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<MeasurementProtocolReleaseRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<DerivedFactEvaluatorDescriptorRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<DerivedFactProvenanceRow>()) == 0
                && modelContext.fetchCount(
                    FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>()
                ) == 0
                && modelContext.fetchCount(
                    FetchDescriptor<AssetFunctionalRelationshipEventRow>()
                ) == 0
                && modelContext.fetchCount(FetchDescriptor<EvidenceVisibilityRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<ClaimEvidenceLinkRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<AssuranceManifestRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<AttestationRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()) == 0
                && modelContext.fetchCount(FetchDescriptor<EvidenceFile>()) == 0
                && modelContext.fetchCount(FetchDescriptor<Issue>()) == 0
                && modelContext.fetchCount(FetchDescriptor<Packet>()) == 0
                && modelContext.fetchCount(FetchDescriptor<Report>()) == 0
                && modelContext.fetchCount(FetchDescriptor<RequirementAssuranceRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<DeletionLedgerRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<SavedSmartViewRowV1>()) == 0
                && modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()) == 0
                && modelContext.fetchCount(FetchDescriptor<MutationQuarantineRow>()) == 0
                && modelContext.fetchCount(
                    FetchDescriptor<EntityMutationRevisionRow>()
                ) == 0
                && hasNoObservationAndTime
        } catch {
            return false
        }
    }

    static func currentSummary(
        modelContext: ModelContext,
        generationRootURL: URL,
        lifecycleDependencies: WorkspacePackageLifecycleDependenciesV1
    ) throws -> BackupRestoreCurrentSummaryV1 {
        guard !modelContext.hasChanges else {
            throw BackupRestoreServiceError.contextHasChanges
        }
        let preview = try BackupExportService(
            modelContext: modelContext,
            generationRootURL: generationRootURL,
            lifecycleDependencies: lifecycleDependencies
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

    static func currentSummary(
        modelContext: ModelContext,
        generationRootURL: URL,
        compatibilityPosture: BackupPackageCompatibilityPostureV1 = .frozenLegacyCallersOnly
    ) throws -> BackupRestoreCurrentSummaryV1 {
        guard !modelContext.hasChanges else {
            throw BackupRestoreServiceError.contextHasChanges
        }
        let preview = try BackupExportService(
            modelContext: modelContext,
            generationRootURL: generationRootURL,
            compatibilityPosture: compatibilityPosture
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
        try validateLifecycleScope(
            currentModelContext,
            generationID: currentGenerationID,
            generationRootURL: currentGenerationRootURL
        )
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
            _ = try currentSummary(
                modelContext: currentModelContext,
                generationRootURL: currentGenerationRootURL
            )
            frozenCurrentRecords = try records(in: currentModelContext)
        case .clone, .fork:
            frozenCurrentRecords = try records(in: currentModelContext)
        }
        do {
            _ = try BackupPackageValidatorV1(
                route: packageValidationRoute()
            ).validate(
                stagedPackageURL: validatedPackage.stagedPackageURL
            )
        } catch {
            throw BackupRestoreServiceError.invalidPackage
        }
        guard try BackupPackageValidatorV1(
            route: packageValidationRoute()
        ).validate(
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
            _ = try currentSummary(
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
                members: validatedPackage.members,
                identityDecision: preliminaryIdentityDecision,
                legacyWorkspaceID: frozenCurrentIdentity.workspaceID.rawValue
            )
            guard uniqueModelIDs(in: expectedRecords) else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
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
            try inject(.beforePreparedWrite)
            try Task.checkCancellation()
            try intentStore.create(intent)
            try inject(.afterPreparedWrite)
            let draftPublicationReceipt = try publishRestoredDraftStaging(
                package: validatedPackage,
                records: expectedRecords,
                identityDecision: identityDecision,
                restoreID: restoreID
            )
            if let draftPublicationReceipt {
                try persistDraftPublicationBinding(draftPublicationReceipt)
            }
            try validateDraftPublicationBinding(intent: intent, records: expectedRecords)
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

            try inject(.beforeGenerationInstall)
            try Task.checkCancellation()
            try validateDraftPublicationBinding(intent: intent, records: expectedRecords)
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
            try removeDraftPublicationBinding(validated)
            try cleanupEmptyRestoreDirectories()
            try await searchIndexLifecycle.dropProjection(
                workspaceID: session.workspaceID.rawValue
            )
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
                    try await searchIndexLifecycle.dropProjection(
                        workspaceID: recovered.workspaceID.rawValue
                    )
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
        let liveImportNames = try generationAuthority.importStagingNames()
        if intent.phase == .prepared, !liveImportNames.isEmpty {
            guard liveImportNames.count == 1, presence.staging,
                  let stagedRecords = try validStagingGenerationRecords(
                    id: intent.newGenerationID,
                    identity: try intent.identity.map {
                        try workspaceIdentity($0.targetPointer)
                    }
                  ) else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            let packageURL = applicationSupportURL
                .appendingPathComponent("FieldEvidenceRestore", isDirectory: true)
                .appendingPathComponent("staging", isDirectory: true)
                .appendingPathComponent(liveImportNames[0], isDirectory: true)
            let package = try BackupPackageValidatorV1(
                route: packageValidationRoute()
            ).validate(stagedPackageURL: packageURL)
            let bindingURL = draftPublicationBindingURL(
                restoreID: intent.restoreID
            )
            if !fileManager.fileExists(atPath: bindingURL.path),
               let receipt = try publishRestoredDraftStaging(
                    package: package,
                    records: stagedRecords,
                    identityDecision: intent.identity,
                    restoreID: intent.restoreID
               ) {
                try persistDraftPublicationBinding(receipt)
            }
            try validateDraftPublicationBinding(
                intent: intent,
                records: stagedRecords
            )
            try discardImportedPackage(
                package,
                generationFactory.installedGenerationURL(
                    id: intent.oldGenerationID
                )
            )
        }
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
            try removeDraftPublicationBinding(intent)
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
            try validateDraftPublicationBinding(
                intent: intent,
                records: newRecords
            )
        }
        if presence.staging,
           let stagedRecords = try validStagingGenerationRecords(
               id: intent.newGenerationID,
               identity: try intent.identity.map {
                   try workspaceIdentity($0.targetPointer)
               }
           ) {
            guard validRecoveredRecords(
               intent: intent,
               old: oldRecords,
               target: stagedRecords
            ) else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            try validateDraftPublicationBinding(
                intent: intent,
                records: stagedRecords
            )
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
            try removeDraftPublicationBinding(intent)
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
                try removeDraftPublicationBinding(intent)
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
                try removeDraftPublicationBinding(intent)
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
            try removeDraftPublicationBinding(intent)
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
        try records(
            in: context,
            includingDeletionLedger: false,
            includesObservationAndTime: false
        )
    }

}

private extension BackupRestoreService {
    func packageValidationRoute() -> BackupPackageValidationRouteV1 {
        switch lifecycleRoute {
        case let .live(dependencies):
            return .live(dependencies.profileRegistry)
        case let .expiringCompatibility(posture):
            return .expiringCompatibility(.illuminatedSignV1, posture)
        }
    }

    func currentSummary(
        modelContext: ModelContext,
        generationRootURL: URL
    ) throws -> BackupRestoreCurrentSummaryV1 {
        switch lifecycleRoute {
        case let .live(dependencies):
            return try Self.currentSummary(
                modelContext: modelContext,
                generationRootURL: generationRootURL,
                lifecycleDependencies: dependencies
            )
        case let .expiringCompatibility(posture):
            return try Self.currentSummary(
                modelContext: modelContext,
                generationRootURL: generationRootURL,
                compatibilityPosture: posture
            )
        }
    }

    func validateLifecycleScope(
        _ context: ModelContext,
        generationID: UUID,
        generationRootURL: URL
    ) throws {
        do {
            try IntegrationProjectionBackupRestoreExclusionV1.validate()
            try KernelBackupRestoreRegistryV4.validate()
            let schema = try KernelPersistenceV4Schema.descriptor()
            guard schema.runtimePosture == .dormantStatic,
                  !schema.activationEnabled else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            guard case let .live(lifecycleDependencies) = lifecycleRoute else {
                guard case let .expiringCompatibility(posture) = lifecycleRoute,
                      posture == .frozenLegacyCallersOnly else {
                    throw BackupRestoreServiceError.invalidRestoreAuthority
                }
                return
            }
            guard lifecycleDependencies.generationID == generationID,
                  lifecycleDependencies.generationRootURL.standardizedFileURL
                    == generationRootURL.standardizedFileURL else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            let assetRows = try context.fetch(FetchDescriptor<Asset>())
            let pairs: [(WorkspaceEntityKindV1, UUID)] =
                try context.fetch(FetchDescriptor<Site>()).map { (.site, $0.id) }
                + assetRows.map { (.asset, $0.id) }
                + context.fetch(FetchDescriptor<WorkflowRecord>()).map { (.workflowRecord, $0.id) }
                + context.fetch(FetchDescriptor<EvidenceFile>()).map { (.evidenceFile, $0.id) }
                + context.fetch(FetchDescriptor<Issue>()).map { (.issue, $0.id) }
                + context.fetch(FetchDescriptor<Packet>()).map { (.packet, $0.id) }
                + context.fetch(FetchDescriptor<Report>()).map { (.report, $0.id) }
                + context.fetch(FetchDescriptor<SavedSmartViewRowV1>()).map {
                    (.savedSmartView, $0.id)
                }
            let identities = try pairs.map { try WorkspaceEntityIdentityV1(kind: $0.0, id: $0.1) }
            let revision = try lifecycleDependencies.writer.currentRevision()
            guard revision.workspaceID == lifecycleDependencies.workspaceID,
                  revision.generationID == generationID else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            for start in stride(from: 0, to: max(identities.count, 1), by: 256) {
                let slice = identities.isEmpty ? [] : Array(
                    identities[start..<min(start + 256, identities.count)]
                )
                let request = try WorkspacePackageLifecycleQueryRequestV1(
                    workspaceID: lifecycleDependencies.workspaceID,
                    generationID: generationID,
                    operation: .restore,
                    identities: slice
                )
                let result = try lifecycleDependencies.writer.query(request)
                guard result.existingIdentities == request.identities,
                      result.revision.revision == revision.revision else {
                    throw BackupRestoreServiceError.invalidRestoreAuthority
                }
                let expectedBindings = assetRows.filter { asset in
                    slice.contains(where: { $0.kind == .asset && $0.id == asset.id })
                }.map {
                    WorkspacePackageBindingV1(
                        assetID: $0.id,
                        packageID: $0.packID,
                        packageSchemaVersion: $0.packSchemaVersion,
                        packageContentVersion: $0.packContentVersion
                    )
                }.sorted { $0.assetID.uuidString < $1.assetID.uuidString }
                guard result.packageBindings == expectedBindings else {
                    throw BackupRestoreServiceError.invalidRestoreAuthority
                }
            }
            guard try lifecycleDependencies.writer.currentRevision() == revision else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
        } catch let failure as BackupRestoreServiceError {
            throw failure
        } catch {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
    }

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
            identityDecision: identity,
            legacyWorkspaceID: identity.oldPointer.workspaceID
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
                    || package.manifest.backupSchemaVersion == 3
                    || package.manifest.backupSchemaVersion == 4,
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
        try removeDraftPublicationBinding(validated)
        try cleanupEmptyRestoreDirectories()
        return session
    }

    func replacingPackets(
        in records: V4BackupRecordsV1,
        with packets: [V4BackupPacketDTO]
    ) -> V4BackupRecordsV1 {
        V4BackupRecordsV1(
            measurementIntegrity: records.measurementIntegrity,
            packageEvolution: records.packageEvolution,
            fieldDrafts: records.fieldDrafts, workPackets:records.workPackets, inspectionReview: records.inspectionReview,
            evidenceAssurance: records.evidenceAssurance,
            functionalRelationships: records.functionalRelationships,
            authorityCriterion: records.authorityCriterion, assetSemantics: records.assetSemantics,
            assetCompositionEdges: records.assetCompositionEdges,
            assetCompositionEvents: records.assetCompositionEvents,
            assetPlacementEvents: records.assetPlacementEvents,
            assets: records.assets,
            deletionLedger: records.deletionLedger,
            evidenceFiles: records.evidenceFiles,
            issues: records.issues,
            locationHierarchyEvents: records.locationHierarchyEvents,
            locationMigrationReceipts: records.locationMigrationReceipts,
            locationNodes: records.locationNodes,
            mutationHistory: records.mutationHistory,
            packets: packets,
            partyAccountability: records.partyAccountability,
            recordsSchemaVersion: records.recordsSchemaVersion,
            reports: records.reports,
            requirementAssurance: records.requirementAssurance,
            savedSmartViews: records.savedSmartViews,
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
            + records.assetCompositionEdges.map(\.id)
            + records.assetCompositionEvents.map(\.id)
            + records.assetPlacementEvents.map(\.id)
            + records.locationHierarchyEvents.map(\.id)
            + records.locationMigrationReceipts.map(\.id)
            + records.locationNodes.map(\.id)
            + records.savedSmartViews.map(\.id)
        return Set(ids).count == ids.count
    }

    func replacingMutationHistoryForCurrentWriter(
        in records: V4BackupRecordsV1,
        with history: MutationHistorySnapshotV1
    ) -> V4BackupRecordsV1 {
        V4BackupRecordsV1(
            measurementIntegrity: records.measurementIntegrity,
            packageEvolution: records.packageEvolution,
            fieldDrafts: records.fieldDrafts, workPackets:records.workPackets, inspectionReview: records.inspectionReview,
            evidenceAssurance: records.evidenceAssurance,
            functionalRelationships: records.functionalRelationships,
            authorityCriterion: records.authorityCriterion, assetSemantics: records.assetSemantics,
            assetCompositionEdges: records.assetCompositionEdges,
            assetCompositionEvents: records.assetCompositionEvents,
            assetPlacementEvents: records.assetPlacementEvents,
            assets: records.assets,
            deletionLedger: records.deletionLedger ?? .empty,
            evidenceFiles: records.evidenceFiles,
            issues: records.issues,
            locationHierarchyEvents: records.locationHierarchyEvents,
            locationMigrationReceipts: records.locationMigrationReceipts,
            locationNodes: records.locationNodes,
            mutationHistory: history,
            packets: records.packets,
            partyAccountability: records.partyAccountability,
            recordsSchemaVersion: max(3, records.recordsSchemaVersion),
            reports: records.reports,
            requirementAssurance: records.requirementAssurance,
            savedSmartViews: records.savedSmartViews,
            sites: records.sites,
            workflowRecords: records.workflowRecords
        )
    }

    func recordsForMaterialization(
        _ records: V4BackupRecordsV1,
        members: ValidatedV4BackupMembersV1,
        identityDecision: RestoreIdentityV1?,
        legacyWorkspaceID: UUID
    ) throws -> V4BackupRecordsV1 {
        var normalized = try recordsWithObservationAndTime(records)
        normalized = try recordsWithRequirementAssurance(
            normalized,
            workspaceID: identityDecision.map { $0.targetPointer.workspaceID }
                ?? legacyWorkspaceID
        )
        if normalized.recordsSchemaVersion >= 5,
           let identityDecision {
            let sourcePreviews = try sourceAssurancePreviews(
                records: normalized, members: members
            )
            normalized = try rebindingLocationMigrationReceipt(
                in: normalized,
                identity: identityDecision,
                workspaceID: WorkspaceID(
                    rawValue: identityDecision.targetPointer.workspaceID
                ),
                generationID: identityDecision.targetPointer.generationID,
                sourceAssurancePreviews: sourcePreviews,
                members: members
            )
        }
        guard let history = normalized.mutationHistory else {
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
            return normalized
        }
        return replacingMutationHistoryForCurrentWriter(
            in: normalized,
            with: MutationHistorySnapshotV1(
                workspaceRevision: history.workspaceRevision,
                lastLocalSequence: 0,
                receipts: history.receipts,
                quarantines: history.quarantines,
                entityRevisions: history.entityRevisions
            )
        )
    }

    func recordsWithRequirementAssurance(
        _ records: V4BackupRecordsV1,
        workspaceID: UUID
    ) throws -> V4BackupRecordsV1 {
        if records.recordsSchemaVersion >= 7 { return records }
        guard records.recordsSchemaVersion <= 6,
              Set(records.requirementAssurance.map(\.workflowRecordID)).count
                == records.requirementAssurance.count,
              Set(records.requirementAssurance.map(\.workflowRecordID))
                .isSubset(of: Set(records.workflowRecords.map(\.id))) else {
            throw BackupRestoreServiceError.invalidPackage
        }
        let existing = Dictionary(uniqueKeysWithValues:
            records.requirementAssurance.map { ($0.workflowRecordID, $0) }
        )
        let assurance = try records.workflowRecords.map { record in
            if let value = existing[record.id] { return value }
            let row = try RequirementAssuranceRow.blockingUnknownBackfill(
                workflowRecordID: record.id,
                workspaceID: workspaceID,
                evaluatedRevision: 1,
                requirementID: "legacy.requirement.assurance",
                requirementVersion: 1,
                requirementTypeID: "legacy.requirement.assurance",
                policySHA256: KernelCanonicalHashV1.sha256(
                    Data("V8|LEGACY_REQUIREMENT_ASSURANCE_UNKNOWN|1".utf8)
                ),
                mutationID: record.finalizationMutationID ?? record.id,
                timestamp: record.startedAt
            )
            return try V8BackupRequirementAssuranceRecordV1(row)
        }.sorted { canonical($0.workflowRecordID) < canonical($1.workflowRecordID) }
        return V4BackupRecordsV1(
            measurementIntegrity: records.measurementIntegrity,
            packageEvolution: records.packageEvolution,
            fieldDrafts: records.fieldDrafts, workPackets:records.workPackets, inspectionReview: records.inspectionReview,
            evidenceAssurance: records.evidenceAssurance,
            functionalRelationships: records.functionalRelationships,
            authorityCriterion: records.authorityCriterion, assetSemantics: records.assetSemantics,
            assetCompositionEdges: records.assetCompositionEdges,
            assetCompositionEvents: records.assetCompositionEvents,
            assetPlacementEvents: records.assetPlacementEvents,
            assets: records.assets, deletionLedger: records.deletionLedger,
            evidenceFiles: records.evidenceFiles, issues: records.issues,
            locationHierarchyEvents: records.locationHierarchyEvents,
            locationMigrationReceipts: records.locationMigrationReceipts,
            locationNodes: records.locationNodes, mutationHistory: records.mutationHistory,
            packets: records.packets, partyAccountability: records.partyAccountability,
            recordsSchemaVersion: records.recordsSchemaVersion,
            reports: records.reports, requirementAssurance: assurance,
            savedSmartViews: records.savedSmartViews, sites: records.sites,
            workflowRecords: records.workflowRecords
        )
    }

    func rebindingLocationMigrationReceipt(
        in records: V4BackupRecordsV1,
        identity: RestoreIdentityV1,
        workspaceID: WorkspaceID,
        generationID: UUID,
        sourceAssurancePreviews: [UUID: AssuranceProjectionPreviewV1],
        members: ValidatedV4BackupMembersV1
    ) throws -> V4BackupRecordsV1 {
        guard records.locationMigrationReceipts.count <= 1 else {
            throw BackupRestoreServiceError.invalidPackage
        }
        let nodes = try records.locationNodes.map { record -> V5BackupLocationRecordV1 in
            let value = try LocationPersistenceCodecV1.decode(
                LocationNodeV1.self, from: record.canonicalData
            )
            guard value.workspaceID != workspaceID else { return record }
            let rebound = try LocationNodeV1(
                id: value.id, workspaceID: workspaceID, siteID: value.siteID,
                parentNodeID: value.parentNodeID, kind: value.kind,
                label: value.label, shortCode: value.shortCode,
                siblingOrder: value.siblingOrder, state: value.state,
                revision: value.revision,
                provenance: try LocationMutationProvenanceV1(
                    mutationID: value.provenance.mutationID,
                    occurredAt: value.provenance.occurredAt
                )
            )
            return .init(id: rebound.id, canonicalData: try LocationPersistenceCodecV1.encode(rebound))
        }
        let placements = try records.assetPlacementEvents.map { record -> V5BackupLocationRecordV1 in
            let value = try LocationPersistenceCodecV1.decode(
                AssetPlacementEventV1.self, from: record.canonicalData
            )
            guard value.workspaceID != workspaceID else { return record }
            let rebound = try AssetPlacementEventV1(
                id: value.id, workspaceID: workspaceID, assetID: value.assetID,
                siteID: value.siteID, locationNodeID: value.locationNodeID,
                predecessorEventID: value.predecessorEventID, source: value.source,
                physicalEpisodeID: value.physicalEpisodeID,
                continuity: value.continuity, pathSnapshot: value.pathSnapshot,
                mutationID: value.mutationID, occurredAt: value.occurredAt
            )
            return .init(id: rebound.id, canonicalData: try LocationPersistenceCodecV1.encode(rebound))
        }
        let reboundEdges = try records.assetCompositionEdges.map { record -> (V5BackupLocationRecordV1, AssetCompositionEdgeV1) in
            let value = try LocationPersistenceCodecV1.decode(
                AssetCompositionEdgeV1.self, from: record.canonicalData
            )
            let rebound = value.workspaceID == workspaceID ? value : try AssetCompositionEdgeV1(
                id: value.id, workspaceID: workspaceID,
                parentAssetID: value.parentAssetID, childAssetID: value.childAssetID,
                relationship: value.relationship, isActive: value.isActive,
                revision: value.revision
            )
            return (
                .init(id: rebound.id, canonicalData: try LocationPersistenceCodecV1.encode(rebound)),
                rebound
            )
        }
        let edgesByID = Dictionary(uniqueKeysWithValues: reboundEdges.map { ($0.1.id, $0.1) })
        let compositionEvents = try records.assetCompositionEvents.map { record -> V5BackupLocationRecordV1 in
            let value = try LocationPersistenceCodecV1.decode(
                AssetCompositionEventV1.self, from: record.canonicalData
            )
            guard edgesByID[value.edge.id] != nil else {
                throw BackupRestoreServiceError.invalidPackage
            }
            let eventEdge = value.edge.workspaceID == workspaceID ? value.edge : try AssetCompositionEdgeV1(
                id: value.edge.id, workspaceID: workspaceID,
                parentAssetID: value.edge.parentAssetID,
                childAssetID: value.edge.childAssetID,
                relationship: value.edge.relationship,
                isActive: value.edge.isActive,
                revision: value.edge.revision
            )
            let rebound = try AssetCompositionEventV1(
                id: value.id, workspaceID: workspaceID, edge: eventEdge,
                predecessorEventID: value.predecessorEventID, action: value.action,
                mutationID: value.mutationID, occurredAt: value.occurredAt
            )
            return .init(id: rebound.id, canonicalData: try LocationPersistenceCodecV1.encode(rebound))
        }
        func reboundNode(_ value: LocationNodeV1) throws -> LocationNodeV1 {
            guard value.workspaceID != workspaceID else { return value }
            return try LocationNodeV1(
                id: value.id, workspaceID: workspaceID, siteID: value.siteID,
                parentNodeID: value.parentNodeID, kind: value.kind,
                label: value.label, shortCode: value.shortCode,
                siblingOrder: value.siblingOrder, state: value.state,
                revision: value.revision, provenance: value.provenance
            )
        }
        let hierarchyEvents = try records.locationHierarchyEvents.map { record -> V5BackupLocationRecordV1 in
            guard let receiptData = record.secondaryCanonicalData else {
                throw BackupRestoreServiceError.invalidPackage
            }
            let sourcePlan = try LocationPersistenceCodecV1.decode(
                LocationHierarchyChangePlanV1.self, from: record.canonicalData
            )
            let sourceReceipt = try LocationPersistenceCodecV1.decode(
                LocationHierarchyChangeReceiptV1.self, from: receiptData
            )
            guard sourcePlan.operationID == record.id else {
                throw BackupRestoreServiceError.invalidPackage
            }
            guard sourcePlan.workspaceID != workspaceID else { return record }
            let expectedRevision = try WorkspaceExpectedRevisionV1(
                workspaceID: workspaceID,
                generationID: generationID,
                writerInstanceID: sourcePlan.expectedRevision.writerInstanceID,
                workspaceRevision: sourcePlan.expectedRevision.workspaceRevision,
                entityRevisions: sourcePlan.expectedRevision.entityRevisions
            )
            let destinationPlan = try LocationHierarchyChangePlanV1(
                operationID: sourcePlan.operationID,
                workspaceID: workspaceID,
                expectedRevision: expectedRevision,
                beforeNodes: try sourcePlan.beforeNodes.map(reboundNode),
                afterNodes: try sourcePlan.afterNodes.map(reboundNode),
                affectedAssetIDs: sourcePlan.affectedAssetIDs,
                assetPathChanges: sourcePlan.assetPathChanges,
                immutablePlacementReferencedNodeIDs: sourcePlan.immutablePlacementReferencedNodeIDs,
                consumerImpact: sourcePlan.consumerImpact,
                assetBindingsChange: sourcePlan.assetBindingsChange,
                operationContinuityDisposition: sourcePlan.operationContinuityDisposition,
                continuityByAssetID: sourcePlan.continuityByAssetID
            )
            let destinationReceipt = try LocationHierarchyChangeReceiptV1.importedCloneFork(
                destinationPlan: destinationPlan,
                sourcePlan: sourcePlan,
                sourceReceipt: sourceReceipt
            )
            return .init(
                id: destinationPlan.operationID,
                canonicalData: try LocationPersistenceCodecV1.encode(destinationPlan),
                secondaryCanonicalData: try LocationPersistenceCodecV1.encode(destinationReceipt)
            )
        }
        let savedSmartViews = try records.savedSmartViews.map { record -> V7BackupSavedSmartViewRecordV1 in
            let value = try record.descriptor()
            guard value.workspaceID != workspaceID.rawValue else { return record }
            return try V7BackupSavedSmartViewRecordV1(SavedSmartViewDescriptorV1(
                id: value.id,
                workspaceID: workspaceID.rawValue,
                stableID: value.stableID,
                origin: value.origin,
                builtInKind: value.builtInKind,
                name: value.name,
                query: value.query,
                scope: value.scope,
                filters: value.filters,
                sort: value.sort,
                revision: value.revision,
                mutationID: value.mutationID,
                createdAt: value.createdAt,
                updatedAt: value.updatedAt
            ))
        }
        let requirementAssurance = try records.requirementAssurance.map { record in
            let source = try record.snapshot()
            guard source.workspaceID != workspaceID.rawValue else { return record }
            let rebound = try RequirementAssuranceSnapshotV1(
                workflowRecordID: source.workflowRecordID,
                workspaceID: workspaceID.rawValue,
                evaluatedRevision: source.evaluatedRevision,
                policySetSHA256: source.policySetSHA256,
                evaluations: source.evaluations,
                findings: source.findings,
                decision: source.decision
            )
            return try V8BackupRequirementAssuranceRecordV1(
                workflowRecordID: rebound.workflowRecordID,
                canonicalData: RequirementAssuranceCanonicalV1.data(rebound),
                snapshotSHA256: rebound.snapshotSHA256,
                mutationID: record.mutationID,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            )
        }
        let partyAccountability = try rebindingPartyAccountability(
            records.partyAccountability,
            workspaceID: workspaceID
        )
        let assetSemantics = try rebindingAssetSemantics(
            records.assetSemantics,
            workspaceID: workspaceID
        )
        let authorityCriterion = try rebindingAuthorityCriterion(
            records.authorityCriterion, workspaceID: workspaceID
        )
        let functionalRelationships = try rebindingFunctionalRelationships(
            records.functionalRelationships, workspaceID: workspaceID
        )
        let evidenceAssurance = try rebindingEvidenceAssurance(
            records.evidenceAssurance, workspaceID: workspaceID,
            sourcePreviews: sourceAssurancePreviews
        )
        let reports = try rebindingReportDTOs(
            records.reports, members: members, workspaceID: workspaceID
        )
        let inspectionReview = try rebindingInspectionReview(
            records.inspectionReview, workspaceID: workspaceID,
            sourceEvidenceAssurance: records.evidenceAssurance,
            evidenceAssurance: evidenceAssurance,
            sourceAuthorityCriterion: records.authorityCriterion,
            authorityCriterion: authorityCriterion,
            sourceFunctionalRelationships: records.functionalRelationships,
            functionalRelationships: functionalRelationships,
            sourceReports: records.reports, reboundReports: reports,
            members: members
        )
        let workPackets = try rebindingWorkPackets(records.workPackets, workspaceID:workspaceID)
        let fieldDrafts = try rebindingFieldDrafts(records.fieldDrafts, identity: identity)
        let packageEvolution = try rebindingPackageEvolution(
            records.packageEvolution, workspaceID: workspaceID,
            sourcePartyAccountability: records.partyAccountability,
            partyAccountability: partyAccountability
        )
        let measurementIntegrity = try rebindingMeasurementIntegrity(
            records.measurementIntegrity, workspaceID: workspaceID,
            authorityCriterion: authorityCriterion
        )
        guard let archived = records.locationMigrationReceipts.first else {
            return V4BackupRecordsV1(
                measurementIntegrity: measurementIntegrity,
                packageEvolution: packageEvolution,
                fieldDrafts: fieldDrafts, workPackets:workPackets,
                inspectionReview: inspectionReview,
                evidenceAssurance: evidenceAssurance,
                functionalRelationships: functionalRelationships,
                authorityCriterion: authorityCriterion, assetSemantics: assetSemantics,
                assetCompositionEdges: reboundEdges.map(\.0),
                assetCompositionEvents: compositionEvents,
                assetPlacementEvents: placements,
                assets: records.assets, deletionLedger: records.deletionLedger,
                evidenceFiles: records.evidenceFiles, issues: records.issues,
                locationHierarchyEvents: hierarchyEvents,
                locationMigrationReceipts: [], locationNodes: nodes,
                mutationHistory: records.mutationHistory, packets: records.packets,
                partyAccountability: partyAccountability,
                recordsSchemaVersion: records.recordsSchemaVersion,
                reports: reports, sites: records.sites,
                requirementAssurance: requirementAssurance,
                savedSmartViews: savedSmartViews,
                workflowRecords: records.workflowRecords
            )
        }
        let receipt = try LocationPersistenceCodecV1.decode(
            LocationMigrationReceiptV1.self, from: archived.canonicalData
        )
        if receipt.workspaceID == workspaceID,
           receipt.candidateGenerationID == generationID,
           nodes == records.locationNodes,
           placements == records.assetPlacementEvents,
           reboundEdges.map(\.0) == records.assetCompositionEdges,
           compositionEvents == records.assetCompositionEvents,
           savedSmartViews == records.savedSmartViews,
           partyAccountability == records.partyAccountability,
           assetSemantics == records.assetSemantics,
           authorityCriterion == records.authorityCriterion,
           functionalRelationships == records.functionalRelationships,
           evidenceAssurance == records.evidenceAssurance,
           inspectionReview == records.inspectionReview,
           workPackets == records.workPackets,
           reports == records.reports {
            return records
        }
        let rebound = try LocationMigrationReceiptV1(
            workspaceID: workspaceID,
            sourceGenerationID: receipt.candidateGenerationID,
            candidateGenerationID: generationID,
            sourceSiteCount: receipt.sourceSiteCount,
            sourceAssetCount: receipt.sourceAssetCount,
            bindings: receipt.bindings
        )
        return V4BackupRecordsV1(
            measurementIntegrity: measurementIntegrity,
            packageEvolution: packageEvolution,
            fieldDrafts: fieldDrafts, workPackets:workPackets,
            inspectionReview: inspectionReview,
            evidenceAssurance: evidenceAssurance,
            functionalRelationships: functionalRelationships,
            authorityCriterion: authorityCriterion, assetSemantics: assetSemantics,
            assetCompositionEdges: reboundEdges.map(\.0),
            assetCompositionEvents: compositionEvents,
            assetPlacementEvents: placements,
            assets: records.assets,
            deletionLedger: records.deletionLedger,
            evidenceFiles: records.evidenceFiles,
            issues: records.issues,
            locationHierarchyEvents: hierarchyEvents,
            locationMigrationReceipts: [.init(
                id: rebound.candidateGenerationID,
                canonicalData: try LocationPersistenceCodecV1.encode(rebound)
            )],
            locationNodes: nodes,
            mutationHistory: records.mutationHistory,
            packets: records.packets,
            partyAccountability: partyAccountability,
            recordsSchemaVersion: records.recordsSchemaVersion,
            reports: reports,
            requirementAssurance: requirementAssurance,
            savedSmartViews: savedSmartViews,
            sites: records.sites,
            workflowRecords: records.workflowRecords
        )
    }

    func rebindingPartyAccountability(
        _ records: [V9BackupPartyAccountabilityRecordV1],
        workspaceID: WorkspaceID
    ) throws -> [V9BackupPartyAccountabilityRecordV1] {
        do {
            var parties: [UUID: ServicePartyReferenceV1] = [:]
            var roles: [UUID: SitePartyRoleEventV1] = [:]
            var actors: [UUID: ActorSnapshotV1] = [:]
            var qualifications: [UUID: QualificationSnapshotV1] = [:]
            var signoffs: [UUID: SignoffSnapshotV1] = [:]

            for record in records {
                switch record.kind {
                case .serviceParty:
                    let value = try PartyAccountabilitySnapshotCodecV1.decode(
                        ServicePartyReferenceV1.self, from: record.canonicalData
                    )
                    guard value.partyID == record.id,
                          value.workspaceID.rawValue == record.workspaceID,
                          value.revision == record.revision,
                          parties.updateValue(value, forKey: value.partyID) == nil else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                case .sitePartyRoleEvent:
                    let value = try PartyAccountabilitySnapshotCodecV1.decode(
                        SitePartyRoleEventV1.self, from: record.canonicalData
                    )
                    guard value.eventID == record.id,
                          value.workspaceID.rawValue == record.workspaceID,
                          value.revision == record.revision,
                          roles.updateValue(value, forKey: value.eventID) == nil else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                case .actorSnapshot:
                    let value = try PartyAccountabilitySnapshotCodecV1.decode(
                        ActorSnapshotV1.self, from: record.canonicalData
                    )
                    guard value.snapshotID == record.id,
                          value.workspaceID.rawValue == record.workspaceID,
                          record.revision == nil,
                          actors.updateValue(value, forKey: value.snapshotID) == nil else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                case .qualificationSnapshot:
                    let value = try PartyAccountabilitySnapshotCodecV1.decode(
                        QualificationSnapshotV1.self, from: record.canonicalData
                    )
                    guard value.snapshotID == record.id,
                          value.workspaceID.rawValue == record.workspaceID,
                          record.revision == nil,
                          qualifications.updateValue(value, forKey: value.snapshotID) == nil else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                case .signoffSnapshot:
                    let value = try PartyAccountabilitySnapshotCodecV1.decode(
                        SignoffSnapshotV1.self, from: record.canonicalData
                    )
                    guard value.snapshotID == record.id,
                          value.workspaceID.rawValue == record.workspaceID,
                          value.subjectRevision == record.revision,
                          signoffs.updateValue(value, forKey: value.snapshotID) == nil else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                }
            }

            let reboundParties = try parties.mapValues { value in
                try ServicePartyReferenceV1(
                    partyID: value.partyID, workspaceID: workspaceID,
                    kind: value.kind, displayName: value.displayName,
                    profileDescriptor: value.profileDescriptor,
                    provenance: value.provenance, privacyClass: value.privacyClass,
                    state: value.state, effectiveAt: value.effectiveAt,
                    retiredAt: value.retiredAt, revision: value.revision,
                    mutationID: value.mutationID
                )
            }
            let reboundRoles = try roles.mapValues { value in
                guard reboundParties[value.partyID] != nil else {
                    throw BackupRestoreServiceError.invalidPackage
                }
                return try SitePartyRoleEventV1(
                    eventID: value.eventID, workspaceID: workspaceID,
                    siteID: value.siteID, partyID: value.partyID, role: value.role,
                    effectiveFrom: value.effectiveFrom, effectiveUntil: value.effectiveUntil,
                    source: value.source, supersedesEventID: value.supersedesEventID,
                    revision: value.revision, mutationID: value.mutationID,
                    recordedAt: value.recordedAt
                )
            }
            let reboundActors = try actors.mapValues { value in
                if let partyID = value.actor.partyID,
                   reboundParties[partyID] == nil {
                    throw BackupRestoreServiceError.invalidPackage
                }
                let actor = try LocalActorReferenceV1(
                    actorReferenceID: value.actor.actorReferenceID,
                    workspaceID: workspaceID, partyID: value.actor.partyID,
                    displayName: value.actor.displayName
                )
                return try ActorSnapshotV1(
                    snapshotID: value.snapshotID, workspaceID: workspaceID,
                    actor: actor, responsibility: value.responsibility,
                    displayNameAtTime: value.displayNameAtTime,
                    capturedAt: value.capturedAt
                )
            }
            let reboundQualifications = try qualifications.mapValues { value in
                try QualificationSnapshotV1(
                    snapshotID: value.snapshotID, workspaceID: workspaceID,
                    declaredScope: value.declaredScope,
                    issuerDisplay: value.issuerDisplay,
                    credentialLocator: value.credentialLocator,
                    effectiveAt: value.effectiveAt, expiresAt: value.expiresAt,
                    provenance: value.provenance, capturedAt: value.capturedAt
                )
            }
            let reboundSignoffs = try signoffs.mapValues { value in
                let roleAssertion: SignoffRoleAssertionV1?
                if let sourceAssertion = value.roleAssertion {
                    guard actors[sourceAssertion.actor.snapshotID] == sourceAssertion.actor,
                          let actor = reboundActors[sourceAssertion.actor.snapshotID] else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                    roleAssertion = try SignoffRoleAssertionV1(
                        claimedRole: sourceAssertion.claimedRole,
                        claimedRelationship: sourceAssertion.claimedRelationship,
                        actor: actor,
                        disclosureRelease: sourceAssertion.disclosureRelease
                    )
                } else {
                    roleAssertion = nil
                }
                let qualification: QualificationSnapshotV1?
                if let sourceQualification = value.qualification {
                    guard qualifications[sourceQualification.snapshotID] == sourceQualification,
                          let rebound = reboundQualifications[sourceQualification.snapshotID] else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                    qualification = rebound
                } else {
                    qualification = nil
                }
                return try SignoffSnapshotV1(
                    snapshotID: value.snapshotID, workspaceID: workspaceID,
                    purpose: value.purpose, subjectID: value.subjectID,
                    subjectRevision: value.subjectRevision,
                    disposition: value.disposition, method: value.method,
                    roleAssertion: roleAssertion, qualification: qualification,
                    externalEvidenceID: value.externalEvidenceID,
                    occurredAt: value.occurredAt, recordedAt: value.recordedAt,
                    supersedesSnapshotID: value.supersedesSnapshotID,
                    mutationID: value.mutationID
                )
            }

            return try records.map { record in
                let data: Data
                switch record.kind {
                case .serviceParty:
                    guard let value = reboundParties[record.id] else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                    data = try PartyAccountabilitySnapshotCodecV1.encode(value)
                case .sitePartyRoleEvent:
                    guard let value = reboundRoles[record.id] else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                    data = try PartyAccountabilitySnapshotCodecV1.encode(value)
                case .actorSnapshot:
                    guard let value = reboundActors[record.id] else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                    data = try PartyAccountabilitySnapshotCodecV1.encode(value)
                case .qualificationSnapshot:
                    guard let value = reboundQualifications[record.id] else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                    data = try PartyAccountabilitySnapshotCodecV1.encode(value)
                case .signoffSnapshot:
                    guard let value = reboundSignoffs[record.id] else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                    data = try PartyAccountabilitySnapshotCodecV1.encode(value)
                }
                return .init(
                    kind: record.kind, id: record.id,
                    workspaceID: workspaceID.rawValue,
                    revision: record.revision, canonicalData: data
                )
            }
        } catch let error as BackupRestoreServiceError {
            throw error
        } catch {
            throw BackupRestoreServiceError.invalidPackage
        }
    }

    func rebindingAssetSemantics(
        _ records: [V10BackupAssetSemanticRecordV1],
        workspaceID: WorkspaceID
    ) throws -> [V10BackupAssetSemanticRecordV1] {
        do {
            return try records.map { record in
                let data: Data
                switch record.kind {
                case .kindBindingEvent:
                    let source = try AssetSemanticCanonicalCodecV1.decode(
                        AssetKindBindingEventV1.self, from: record.canonicalData
                    )
                    guard source.eventID == record.id,
                          source.workspaceID.rawValue == record.workspaceID,
                          source.revision == record.revision else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                    data = try AssetSemanticCanonicalCodecV1.encode(
                        source.workspaceID == workspaceID ? source : source.rebound(to: workspaceID)
                    )
                case .workflowCapabilityBindingEvent:
                    let source = try AssetSemanticCanonicalCodecV1.decode(
                        AssetWorkflowCapabilityBindingEventV1.self,
                        from: record.canonicalData
                    )
                    guard source.eventID == record.id,
                          source.workspaceID.rawValue == record.workspaceID,
                          source.revision == record.revision else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                    data = try AssetSemanticCanonicalCodecV1.encode(
                        source.workspaceID == workspaceID ? source : source.rebound(to: workspaceID)
                    )
                case .productIdentity:
                    let source = try AssetSemanticCanonicalCodecV1.decode(
                        AssetProductIdentityV1.self, from: record.canonicalData
                    )
                    guard source.identityID == record.id,
                          source.workspaceID.rawValue == record.workspaceID,
                          source.revision == record.revision else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                    data = try AssetSemanticCanonicalCodecV1.encode(
                        source.workspaceID == workspaceID ? source : source.rebound(to: workspaceID)
                    )
                case .lifecycleEvent:
                    let source = try AssetSemanticCanonicalCodecV1.decode(
                        AssetLifecycleEventV1.self, from: record.canonicalData
                    )
                    guard source.record.eventID == record.id,
                          source.record.workspaceID.rawValue == record.workspaceID,
                          source.record.revision == record.revision else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                    data = try AssetSemanticCanonicalCodecV1.encode(
                        source.record.workspaceID == workspaceID
                            ? source : source.rebound(to: workspaceID)
                    )
                case .successorLink:
                    let source = try AssetSemanticCanonicalCodecV1.decode(
                        AssetSuccessorLinkV1.self, from: record.canonicalData
                    )
                    guard source.linkID == record.id,
                          source.workspaceID.rawValue == record.workspaceID,
                          source.revision == record.revision else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                    data = try AssetSemanticCanonicalCodecV1.encode(
                        source.workspaceID == workspaceID ? source : source.rebound(to: workspaceID)
                    )
                case .workSubjectScopeSnapshot:
                    let source = try AssetSemanticCanonicalCodecV1.decode(
                        WorkSubjectScopeSnapshotV1.self, from: record.canonicalData
                    )
                    guard source.snapshotID == record.id,
                          source.workspaceID.rawValue == record.workspaceID,
                          source.workspaceRevision == record.revision else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                    data = try AssetSemanticCanonicalCodecV1.encode(
                        source.workspaceID == workspaceID ? source : source.rebound(to: workspaceID)
                    )
                }
                return .init(
                    kind: record.kind, id: record.id,
                    workspaceID: workspaceID.rawValue,
                    revision: record.revision, canonicalData: data
                )
            }
        } catch let error as BackupRestoreServiceError {
            throw error
        } catch {
            throw BackupRestoreServiceError.invalidPackage
        }
    }

    func rebindingAuthorityCriterion(
        _ records: [V11BackupAuthorityCriterionRecordV1],
        workspaceID: WorkspaceID
    ) throws -> [V11BackupAuthorityCriterionRecordV1] {
        try records.map { record in
            let data: Data
            switch record.kind {
            case .authoritySourceRelease:
                let source = try AuthorityCriterionCanonicalCodecV1.decode(AuthoritySourceReleaseV1.self, from: record.canonicalData); data = try AuthorityCriterionCanonicalCodecV1.encode(source.workspaceID == workspaceID ? source : source.rebound(to: workspaceID))
            case .requirementBasisBinding:
                let source = try AuthorityCriterionCanonicalCodecV1.decode(RequirementBasisBindingV1.self, from: record.canonicalData); data = try AuthorityCriterionCanonicalCodecV1.encode(source.workspaceID == workspaceID ? source : source.rebound(to: workspaceID))
            case .applicabilityContextSnapshot:
                let source = try AuthorityCriterionCanonicalCodecV1.decode(ApplicabilityContextSnapshotV1.self, from: record.canonicalData); data = try AuthorityCriterionCanonicalCodecV1.encode(source.workspaceID == workspaceID ? source : source.rebound(to: workspaceID))
            case .assessmentScopeSnapshot:
                let source = try AuthorityCriterionCanonicalCodecV1.decode(AssessmentScopeSnapshotV1.self, from: record.canonicalData); data = try AuthorityCriterionCanonicalCodecV1.encode(source.workspaceID == workspaceID ? source : source.rebound(to: workspaceID))
            case .severityScaleRelease:
                let source = try AuthorityCriterionCanonicalCodecV1.decode(SeverityScaleReleaseV1.self, from: record.canonicalData); data = try AuthorityCriterionCanonicalCodecV1.encode(source.workspaceID == workspaceID ? source : source.rebound(to: workspaceID))
            case .findingClassificationBinding:
                let source = try AuthorityCriterionCanonicalCodecV1.decode(FindingClassificationBindingV1.self, from: record.canonicalData); data = try AuthorityCriterionCanonicalCodecV1.encode(source.workspaceID == workspaceID ? source : source.rebound(to: workspaceID))
            case .measurementProtocolRelease:
                let source = try AuthorityCriterionCanonicalCodecV1.decode(MeasurementProtocolReleaseV1.self, from: record.canonicalData); data = try AuthorityCriterionCanonicalCodecV1.encode(source.workspaceID == workspaceID ? source : source.rebound(to: workspaceID))
            case .derivedFactEvaluatorDescriptor:
                let source = try AuthorityCriterionCanonicalCodecV1.decode(DerivedFactEvaluatorDescriptorV1.self, from: record.canonicalData); data = try AuthorityCriterionCanonicalCodecV1.encode(source.workspaceID == workspaceID ? source : source.rebound(to: workspaceID))
            case .derivedFactProvenance:
                let source = try AuthorityCriterionCanonicalCodecV1.decode(DerivedFactProvenanceV1.self, from: record.canonicalData); data = try AuthorityCriterionCanonicalCodecV1.encode(source.workspaceID == workspaceID ? source : source.rebound(to: workspaceID))
            }
            return .init(kind: record.kind, id: record.id, workspaceID: workspaceID.rawValue, canonicalData: data)
        }
    }

    func rebindingFunctionalRelationships(
        _ records: [V12BackupFunctionalRelationshipRecordV1],
        workspaceID: WorkspaceID
    ) throws -> [V12BackupFunctionalRelationshipRecordV1] {
        do {
            return try records.map { record in
                let data: Data
                switch record.kind {
                case .descriptor:
                    let source = try FunctionalRelationshipCanonicalCodecV1.decode(
                        FunctionalRelationshipTypeDescriptorV1.self, from: record.canonicalData
                    )
                    data = try FunctionalRelationshipCanonicalCodecV1.encode(
                        source.workspaceID == workspaceID ? source : source.rebound(to: workspaceID)
                    )
                case .event:
                    let source = try FunctionalRelationshipCanonicalCodecV1.decode(
                        AssetFunctionalRelationshipEventV1.self, from: record.canonicalData
                    )
                    data = try FunctionalRelationshipCanonicalCodecV1.encode(
                        source.workspaceID == workspaceID ? source : source.rebound(to: workspaceID)
                    )
                }
                return .init(kind: record.kind, id: record.id,
                             workspaceID: workspaceID.rawValue,
                             revision: record.revision, canonicalData: data)
            }
        } catch { throw BackupRestoreServiceError.invalidPackage }
    }

    func sourceAssurancePreviews(
        records: V4BackupRecordsV1,
        members: ValidatedV4BackupMembersV1
    ) throws -> [UUID: AssuranceProjectionPreviewV1] {
        guard !records.evidenceAssurance.isEmpty else { return [:] }
        var result: [UUID: AssuranceProjectionPreviewV1] = [:]
        for report in records.reports {
            guard let data = members[report.snapshotRelativePath] else {
                throw BackupRestoreServiceError.invalidPackage
            }
            let snapshot = try ReportSnapshotEncoderV1().decode(data)
            guard let preview = snapshot.assurance?.preview else { continue }
            if let existing = result[preview.previewID], existing != preview {
                throw BackupRestoreServiceError.invalidPackage
            }
            result[preview.previewID] = preview
        }
        return result
    }

    func reboundReportSnapshotData(
        _ data: Data, workspaceID: WorkspaceID
    ) throws -> Data {
        var snapshot = try ReportSnapshotEncoderV1().decode(data)
        guard let source = snapshot.assurance else { return data }
        let visibilities = try source.visibilities.map { visibility in
            visibility.workspaceID == workspaceID ? visibility : try visibility.rebound(to: workspaceID)
        }
        let visibilityByID = Dictionary(uniqueKeysWithValues: visibilities.map { ($0.visibilityID, $0) })
        let sourceLinks = source.preview.includedLinks + source.preview.excludedLinks
        let links = try sourceLinks.map { link -> ClaimEvidenceLinkV1 in
            guard let visibility = visibilityByID[link.visibilityID] else {
                throw BackupRestoreServiceError.invalidPackage
            }
            return link.workspaceID == workspaceID ? link : try link.rebound(to: workspaceID, visibility: visibility)
        }
        let preview = try source.preview.rebound(to: workspaceID, links: links)
        let manifest = try source.manifest.map {
            $0.workspaceID == workspaceID ? $0 : try $0.rebound(to: workspaceID, preview: preview)
        }
        let attestations = try source.attestations.map { value -> AttestationV1 in
            guard let manifest else { throw BackupRestoreServiceError.invalidPackage }
            return value.workspaceID == workspaceID ? value : try value.rebound(to: workspaceID, manifest: manifest)
        }
        snapshot.assurance = try ReportEvidenceAssuranceProjectionV1(
            preview: preview, manifest: manifest,
            visibilities: visibilities, attestations: attestations
        )
        return try ReportSnapshotEncoderV1().encode(snapshot).data
    }

    func rebindingReportDTOs(
        _ reports: [V4BackupReportDTO], members: ValidatedV4BackupMembersV1,
        workspaceID: WorkspaceID
    ) throws -> [V4BackupReportDTO] {
        try reports.map { report in
            guard let source = members[report.snapshotRelativePath] else {
                throw BackupRestoreServiceError.invalidPackage
            }
            let data = try reboundReportSnapshotData(source, workspaceID: workspaceID)
            return .init(
                id: report.id, schemaVersion: report.schemaVersion, packetID: report.packetID,
                sourceRecordID: report.sourceRecordID,
                snapshotSchemaVersion: report.snapshotSchemaVersion,
                snapshotRelativePath: report.snapshotRelativePath,
                snapshotSHA256: CanonicalJSONV1.sha256(data), pdfState: report.pdfState,
                pdfRelativePath: report.pdfRelativePath, pdfSHA256: report.pdfSHA256,
                createdAt: report.createdAt, replacesReportID: report.replacesReportID
            )
        }
    }

    func rebindingWorkPackets(_ records:[V15BackupWorkPacketRecordV1],workspaceID:WorkspaceID)throws->[V15BackupWorkPacketRecordV1]{
        let sourceManifests=try Dictionary(uniqueKeysWithValues:records.compactMap{r->(UUID,WorkPacketManifestV1)? in guard r.kind == .manifest else{return nil};let v=try WorkPacketCanonicalCodecV1.decode(WorkPacketManifestV1.self,from:r.canonicalData);return(v.manifestID,v)})
        let manifests=try sourceManifests.mapValues{$0.workspaceID==workspaceID ? $0:try $0.rebound(to:workspaceID)}
        func item(_ source:WorkPacketItemReferenceV1)throws->WorkPacketItemReferenceV1{guard let manifest=manifests.values.first(where:{$0.packetID==source.packetID&&$0.packetVersion==source.packetVersion}),let value=manifest.items.first(where:{$0.itemID==source.itemID&&$0.kind==source.itemKind&&$0.expectedRevision==source.expectedRevision&&$0.itemSHA256==source.itemSHA256})else{throw BackupRestoreServiceError.invalidPackage};return try .init(manifest:manifest,item:value)}
        return try records.map{record in
            let data:Data
            switch record.kind{
            case .manifest:guard let v=manifests[record.id]else{throw BackupRestoreServiceError.invalidPackage};data=try WorkPacketCanonicalCodecV1.encode(v)
            case .claim:let s=try WorkPacketCanonicalCodecV1.decode(WorkItemClaimV1.self,from:record.canonicalData);let b=try s.rebound(to:workspaceID);guard let m=manifests[s.manifest.manifestID]else{throw BackupRestoreServiceError.invalidPackage};let v=try WorkItemClaimV1(claimID:b.claimID,workspaceID:workspaceID,manifest:WorkPacketManifestReferenceV1(m),item:item(s.item),holder:b.holder,claimSequence:b.claimSequence,claimedAt:b.claimedAt,supersedesClaimID:b.supersedesClaimID,revision:b.revision,mutationID:b.mutationID);data=try WorkPacketCanonicalCodecV1.encode(v)
            case .lease:let s=try WorkPacketCanonicalCodecV1.decode(WorkLeaseV1.self,from:record.canonicalData);let b=try s.rebound(to:workspaceID);let v=try WorkLeaseV1(leaseID:b.leaseID,workspaceID:workspaceID,claimID:b.claimID,item:item(s.item),holder:b.holder,leaseSequence:b.leaseSequence,startsAt:b.startsAt,expiresAt:b.expiresAt,supersedesLeaseID:b.supersedesLeaseID,revision:b.revision,mutationID:b.mutationID);data=try WorkPacketCanonicalCodecV1.encode(v)
            case .release:let s=try WorkPacketCanonicalCodecV1.decode(WorkReleaseV1.self,from:record.canonicalData);let b=try s.rebound(to:workspaceID);let v=try WorkReleaseV1(releaseID:b.releaseID,workspaceID:workspaceID,claimID:b.claimID,leaseID:b.leaseID,item:item(s.item),holder:b.holder,reason:b.reason,resultLinks:b.resultLinks,releasedAt:b.releasedAt,revision:b.revision,mutationID:b.mutationID);data=try WorkPacketCanonicalCodecV1.encode(v)
            case .handoff:let s=try WorkPacketCanonicalCodecV1.decode(WorkHandoffV1.self,from:record.canonicalData);let b=try s.rebound(to:workspaceID);let v=try WorkHandoffV1(handoffID:b.handoffID,workspaceID:workspaceID,releaseID:b.releaseID,item:item(s.item),fromHolder:b.fromHolder,toHolder:b.toHolder,resultLinks:b.resultLinks,reason:b.reason,handedOffAt:b.handedOffAt,revision:b.revision,mutationID:b.mutationID);data=try WorkPacketCanonicalCodecV1.encode(v)
            }
            return .init(kind:record.kind,id:record.id,workspaceID:workspaceID.rawValue,revision:record.revision,canonicalData:data)
        }
    }

    func rebindingFieldDrafts(
        _ records: [V16BackupFieldDraftRecordV1],
        identity: RestoreIdentityV1
    ) throws -> [V16BackupFieldDraftRecordV1] {
        guard !records.isEmpty else { return [] }
        if identity.mode == .emptyInstall || identity.mode == .replaceExisting,
           records.allSatisfy({ $0.workspaceID == identity.targetPointer.workspaceID }) {
            return records
        }
        let target = identity.destinationFieldDraftWorkspaceID()
        func mapped(_ id: UUID, _ namespace: String) throws -> UUID {
            guard let value = identity.destinationFieldDraftID(for: id, namespace: namespace) else {
                throw BackupRestoreServiceError.invalidPackage
            }
            return value
        }
        let decodedCheckpoints = try records.filter { $0.kind == .checkpoint }.map { try FieldDraftCanonicalCodecV1.decode(FieldDraftCheckpointV1.self, from: $0.canonicalData) }
        let decodedStages = try records.filter { $0.kind == .stagingItem }.map { try FieldDraftCanonicalCodecV1.decode(AttachmentStagingItemV1.self, from: $0.canonicalData) }
        let decodedSagas = try records.filter { $0.kind == .commitSaga }.map { try FieldDraftCanonicalCodecV1.decode(DraftCommitSagaV1.self, from: $0.canonicalData) }
        let decodedReservations = try records.filter { $0.kind == .contentReservation }.map { try FieldDraftCanonicalCodecV1.decode(DraftContentReservationV1.self, from: $0.canonicalData) }
        let decodedCommitReceipts = try records.filter { $0.kind == .commitReceipt }.map { try FieldDraftCanonicalCodecV1.decode(DraftCommitReceiptV1.self, from: $0.canonicalData) }
        let decodedDiscardReceipts = try records.filter { $0.kind == .discardReceipt }.map { try FieldDraftCanonicalCodecV1.decode(DraftDiscardReceiptV1.self, from: $0.canonicalData) }
        func pairs(_ ids: [UUID], _ namespace: String) throws -> [UUID: UUID] {
            guard Set(ids).count == ids.count else { throw BackupRestoreServiceError.invalidPackage }
            return try Dictionary(uniqueKeysWithValues: ids.map { ($0, try mapped($0, namespace)) })
        }
        let receiptIDs = decodedCommitReceipts.map(\.receiptID) + decodedDiscardReceipts.map(\.receiptID)
        let map = try DraftRestoreIdentityMapV1(
            targetWorkspaceID: target,
            draftIDs: try pairs(decodedCheckpoints.map(\.draftID), "draft"),
            stageIDs: try pairs(decodedStages.map(\.stageID), "stage"),
            sagaIDs: try pairs(decodedSagas.map(\.sagaID), "saga"),
            reservationIDs: try pairs(decodedReservations.map(\.reservationID), "reservation"),
            receiptIDs: try pairs(receiptIDs, "receipt")
        )
        func mutation(_ id: MutationIDV1, _ namespace: String) throws -> MutationIDV1 {
            try MutationIDV1(rawValue: mapped(id.rawValue, "mutation.\(namespace)"))
        }
        var planByDigest: [String: DraftCommitPlanV1] = [:]
        for saga in decodedSagas {
            let source = saga.plan
            let rebound = try source.rebound(
                using: map, planID: mapped(source.planID, "plan"),
                stageDigests: source.stageDigests,
                expectedTargetRevision: source.expectedTargetRevision,
                mutationID: mutation(source.mutationID, "plan"), outputKeys: source.outputKeys
            )
            planByDigest[source.planSHA256] = rebound
        }
        var output: [V16BackupFieldDraftRecordV1] = []
        for source in decodedCheckpoints {
            let scope = try DraftScopeKeyV1(
                scopeKind: source.scope.scopeKind,
                stableComponentIDs: source.scope.stableComponentIDs.map { component in
                    guard let id = UUID(uuidString: component) else { return component }
                    return (try? mapped(id, "scope").uuidString.lowercased()) ?? component
                }
            )
            let value = try source.rebound(using: map, scope: scope, mutationID: mutation(source.mutationID, "checkpoint"))
            output.append(.init(kind:.checkpoint,id:value.draftID,workspaceID:target.rawValue,revision:value.draftRevision,canonicalData:try FieldDraftCanonicalCodecV1.encode(value)))
        }
        for source in decodedStages {
            let contentReference = try source.contentReference.map { reference in
                try ContentReferenceV1(workspaceID: target.rawValue.uuidString.lowercased(), contentID: reference.contentID, byteLength: reference.byteLength, mediaType: reference.mediaType, digests: reference.digests, byteRole: reference.byteRole, createdAt: reference.createdAt)
            }
            let value = try source.rebound(using: map, scratchLeaseID: mapped(source.scratchLeaseID, "scratchLease"), contentReference: contentReference, processingJobID: try source.processingJobID.map { try mapped($0, "processingJob") }, mutationID: mutation(source.mutationID, "stage"))
            output.append(.init(kind:.stagingItem,id:value.stageID,workspaceID:target.rawValue,revision:value.revision,canonicalData:try FieldDraftCanonicalCodecV1.encode(value)))
        }
        var reboundSagaSHA: [String: String] = [:]
        for source in decodedSagas.sorted(by: { $0.revision < $1.revision }) {
            guard let plan = planByDigest[source.plan.planSHA256] else { throw BackupRestoreServiceError.invalidPackage }
            let value = try source.rebound(using: map, plan: plan, mutationID: mutation(source.mutationID, "saga"))
            reboundSagaSHA[source.sagaSHA256] = value.sagaSHA256
            output.append(.init(kind:.commitSaga,id:value.sagaID,workspaceID:target.rawValue,revision:value.revision,canonicalData:try FieldDraftCanonicalCodecV1.encode(value)))
        }
        for source in decodedReservations {
            guard let plan = planByDigest[source.commitPlanSHA256] else { throw BackupRestoreServiceError.invalidPackage }
            let locator = try ContentLocatorV1(locatorID: source.locator.locatorID, workspaceID: target.rawValue.uuidString.lowercased(), contentID: source.locator.contentID, locatorRevision: source.locator.locatorRevision, contentDigest: source.contentDigest, expectedByteLength: source.locator.expectedByteLength)
            let value = try source.rebound(using: map, commitPlanSHA256: plan.planSHA256, contentDigest: source.contentDigest, locator: locator, mutationID: mutation(source.mutationID, "reservation"))
            output.append(.init(kind:.contentReservation,id:value.reservationID,workspaceID:target.rawValue,revision:value.revision,canonicalData:try FieldDraftCanonicalCodecV1.encode(value)))
        }
        for source in decodedCommitReceipts {
            guard let plan = planByDigest[source.commitPlanSHA256] else { throw BackupRestoreServiceError.invalidPackage }
            var consumed: [String: String] = [:]
            for (key, contentID) in source.consumedStageToContentID {
                guard let sourceStageID = UUID(uuidString: key) else { throw BackupRestoreServiceError.invalidPackage }
                consumed[try map.stageID(sourceStageID).uuidString] = contentID
            }
            let chain = try source.sagaEventSHA256Chain.map { digest -> String in
                guard let rebound = reboundSagaSHA[digest] else { throw BackupRestoreServiceError.invalidPackage }
                return rebound
            }
            let value = try source.rebound(using: map, commitPlanSHA256: plan.planSHA256, sagaEventSHA256Chain: chain, targetMutationID: mutation(source.targetMutationID, "target"), targetReceiptSHA256: source.targetReceiptSHA256, consumedStageToContentID: consumed, mutationID: mutation(source.mutationID, "commitReceipt"))
            output.append(.init(kind:.commitReceipt,id:value.receiptID,workspaceID:target.rawValue,revision:value.revision,canonicalData:try FieldDraftCanonicalCodecV1.encode(value)))
        }
        for source in decodedDiscardReceipts {
            let value = try source.rebound(using: map, planSHA256: source.planSHA256, mutationID: mutation(source.mutationID, "discardReceipt"))
            output.append(.init(kind:.discardReceipt,id:value.receiptID,workspaceID:target.rawValue,revision:value.revision,canonicalData:try FieldDraftCanonicalCodecV1.encode(value)))
        }
        return output.sorted { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" < "\($1.kind.rawValue)\u{0}\($1.id.uuidString)" }
    }

    func rebindingPackageEvolution(
        _ records: [V17BackupPackageEvolutionRecordV1], workspaceID: WorkspaceID,
        sourcePartyAccountability: [V9BackupPartyAccountabilityRecordV1],
        partyAccountability: [V9BackupPartyAccountabilityRecordV1]
    ) throws -> [V17BackupPackageEvolutionRecordV1] {
        guard !records.isEmpty else { return [] }
        let sourceActors = try Dictionary(uniqueKeysWithValues: sourcePartyAccountability.compactMap { row -> (String, UUID)? in
            guard row.kind == .actorSnapshot else { return nil }
            let value = try PartyAccountabilitySnapshotCodecV1.decode(ActorSnapshotV1.self, from: row.canonicalData)
            return (value.snapshotSHA256, value.snapshotID)
        })
        let actors = try Dictionary(uniqueKeysWithValues: partyAccountability.compactMap { row -> (UUID, ActorSnapshotV1)? in
            guard row.kind == .actorSnapshot else { return nil }
            let value = try PartyAccountabilitySnapshotCodecV1.decode(ActorSnapshotV1.self, from: row.canonicalData)
            return (value.snapshotID, value)
        })
        let sourceReleases = try records.filter { $0.kind == .promotedRelease }.map { try PackageEvolutionCanonicalCodecV1.decode(PromotedPackageReleaseV1.self, from: $0.canonicalData) }
        let releases = try Dictionary(uniqueKeysWithValues: sourceReleases.map { source in
            let value = source.workspaceID == workspaceID ? source : try source.rebound(to: workspaceID)
            return (value.releaseRecordID, value)
        })
        let sourceRuns = try records.filter { $0.kind == .sandboxRun }.map { try PackageEvolutionCanonicalCodecV1.decode(PackageSandboxRunV1.self, from: $0.canonicalData) }
        let runs = try Dictionary(uniqueKeysWithValues: sourceRuns.map { source in
            let value = source.workspaceID == workspaceID ? source : try source.rebound(to: workspaceID)
            return (value.runID, value)
        })
        let sourcePointers = try records.filter { $0.kind == .activePointer }.map { try PackageEvolutionCanonicalCodecV1.decode(ActivePackageRegistryPointerV1.self, from: $0.canonicalData) }
        var pointers: [UUID: ActivePackageRegistryPointerV1] = [:]
        for source in sourcePointers.sorted(by: { $0.revision < $1.revision }) {
            guard let release = releases[source.activeReleaseRecordID] else { throw BackupRestoreServiceError.invalidPackage }
            let value = source.workspaceID == workspaceID ? source : try source.rebound(to: workspaceID, activeReleaseRecord: release)
            if let predecessorID = value.supersedesPointerID {
                guard let predecessor = pointers[predecessorID] else { throw BackupRestoreServiceError.invalidPackage }
                try value.validateSuccessor(of: predecessor, expectedRevision: predecessor.revision)
            }
            pointers[value.pointerID] = value
        }
        let sourceReceipts = try records.filter { $0.kind == .promotionReceipt }.map { try PackageEvolutionCanonicalCodecV1.decode(PackagePromotionReceiptV1.self, from: $0.canonicalData) }
        var receipts: [UUID: PackagePromotionReceiptV1] = [:]
        for source in sourceReceipts {
            guard let release = releases[source.promotedReleaseRecordID], let run = runs[source.sandboxRunID],
                  let pointer = pointers.values.first(where: { $0.promotionReceiptID == source.receiptID }),
                  let actorID = sourceActors[source.actorSnapshotSHA256], let actor = actors[actorID] else {
                throw BackupRestoreServiceError.invalidPackage
            }
            let predecessor = pointer.supersedesPointerID.flatMap { pointers[$0] }
            let value = source.workspaceID == workspaceID ? source : try source.rebound(
                to: workspaceID, promotedRelease: release, sandboxRun: run,
                predecessorPointer: predecessor, resultingPointer: pointer, actor: actor
            )
            receipts[value.receiptID] = value
        }
        let closure = try PackageEvolutionLifecycleClosureV1(
            promotedReleases: Array(releases.values), sandboxRuns: Array(runs.values),
            promotionReceipts: Array(receipts.values), activePointers: Array(pointers.values)
        )
        try closure.validate()
        var output: [V17BackupPackageEvolutionRecordV1] = []
        output += try releases.values.map { .init(kind:.promotedRelease,id:$0.releaseRecordID,workspaceID:workspaceID.rawValue,revision:$0.revision,canonicalData:try PackageEvolutionCanonicalCodecV1.encode($0)) }
        output += try runs.values.map { .init(kind:.sandboxRun,id:$0.runID,workspaceID:workspaceID.rawValue,revision:$0.revision,canonicalData:try PackageEvolutionCanonicalCodecV1.encode($0)) }
        output += try receipts.values.map { .init(kind:.promotionReceipt,id:$0.receiptID,workspaceID:workspaceID.rawValue,revision:$0.revision,canonicalData:try PackageEvolutionCanonicalCodecV1.encode($0)) }
        output += try pointers.values.map { .init(kind:.activePointer,id:$0.pointerID,workspaceID:workspaceID.rawValue,revision:$0.revision,canonicalData:try PackageEvolutionCanonicalCodecV1.encode($0)) }
        return output.sorted { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" < "\($1.kind.rawValue)\u{0}\($1.id.uuidString)" }
    }

    func rebindingMeasurementIntegrity(
        _ records:[V18BackupMeasurementIntegrityRecordV1], workspaceID:WorkspaceID,
        authorityCriterion:[V11BackupAuthorityCriterionRecordV1]
    ) throws -> [V18BackupMeasurementIntegrityRecordV1] {
        let sourceInstruments=try records.filter{$0.kind == .instrumentReference}.map{try MeasurementIntegrityCanonicalCodecV1.decode(InstrumentReferenceV1.self,from:$0.canonicalData)}
        let instruments=try Dictionary(uniqueKeysWithValues:sourceInstruments.map{let v=try $0.rebound(to:workspaceID);return(v.referenceID,v)})
        let sourceCalibrations=try records.filter{$0.kind == .calibrationSnapshot}.map{try MeasurementIntegrityCanonicalCodecV1.decode(CalibrationStatusSnapshotV1.self,from:$0.canonicalData)}
        var calibrations:[UUID:CalibrationStatusSnapshotV1]=[:]
        for source in sourceCalibrations { guard let instrument=instruments[source.instrument.referenceID] else{throw BackupRestoreServiceError.invalidPackage};let base=try source.rebound(to:workspaceID);let value=try CalibrationStatusSnapshotV1(snapshotID:base.snapshotID,workspaceID:workspaceID,instrument:InstrumentRevisionReferenceV1(instrument),status:base.status,basis:base.basis,effectiveAt:base.effectiveAt,expiresAt:base.expiresAt,sourceReference:base.sourceReference,capturedAt:base.capturedAt,supersedesSnapshotID:base.supersedesSnapshotID,revision:base.revision,mutationID:base.mutationID);calibrations[value.snapshotID]=value }
        let sourceCaptures=try records.filter{$0.kind == .measurementCapture}.map{try MeasurementIntegrityCanonicalCodecV1.decode(MeasurementCaptureV1.self,from:$0.canonicalData)}
        var captures:[UUID:MeasurementCaptureV1]=[:]
        for source in sourceCaptures { let base=try source.rebound(to:workspaceID);let instrument=try source.instrument.map{ref in guard let value=instruments[ref.referenceID]else{throw BackupRestoreServiceError.invalidPackage};return try InstrumentRevisionReferenceV1(value)};let calibration=try source.calibration.map{ref in guard let value=calibrations[ref.snapshotID]else{throw BackupRestoreServiceError.invalidPackage};return try CalibrationSnapshotReferenceV1(value)};let value=try MeasurementCaptureV1(captureID:base.captureID,workspaceID:workspaceID,packageReleaseID:base.packageReleaseID,workflowSHA256:base.workflowSHA256,response:base.response,measurement:base.measurement,sourceMode:base.sourceMode,instrument:instrument,calibration:calibration,observationBasis:base.observationBasis,operatorSnapshot:base.operatorSnapshot,evidence:base.evidence,capturedAt:base.capturedAt,supersedesCaptureID:base.supersedesCaptureID,revision:base.revision,mutationID:base.mutationID);captures[value.captureID]=value }
        let reboundProtocols=try authorityCriterion.filter{$0.kind == .measurementProtocolRelease}.map{try AuthorityCriterionCanonicalCodecV1.decode(MeasurementProtocolReleaseV1.self,from:$0.canonicalData)}
        let protocols=Dictionary(uniqueKeysWithValues:reboundProtocols.map{($0.releaseID,$0)})
        let sourceSeries=try records.filter{$0.kind == .measurementSeries}.map{try MeasurementIntegrityCanonicalCodecV1.decode(MeasurementSeriesV1.self,from:$0.canonicalData)}
        var series:[UUID:MeasurementSeriesV1]=[:]
        for source in sourceSeries { guard let protocolRelease=protocols[source.protocolReference.releaseID]else{throw BackupRestoreServiceError.invalidPackage};let base=try source.rebound(to:workspaceID);let samples=try source.samples.map{ref in guard let capture=captures[ref.captureID]else{throw BackupRestoreServiceError.invalidPackage};return try MeasurementCaptureReferenceV1(captureID:capture.captureID,revision:capture.revision,captureSHA256:capture.captureSHA256,sampleOrdinal:ref.sampleOrdinal)};let value=try MeasurementSeriesV1(snapshotID:base.snapshotID,seriesID:base.seriesID,workspaceID:workspaceID,protocolReference:MeasurementProtocolReferenceV1(protocolRelease),samples:samples,expectedSampleCount:base.expectedSampleCount,aggregationPolicy:base.aggregationPolicy,state:base.state,derivedFact:base.derivedFact,recordedAt:base.recordedAt,supersedesSnapshotID:base.supersedesSnapshotID,revision:base.revision,mutationID:base.mutationID);series[value.snapshotID]=value }
        let sourceAssessments=try records.filter{$0.kind == .qualityAssessment}.map{try MeasurementIntegrityCanonicalCodecV1.decode(MeasurementQualityAssessmentV1.self,from:$0.canonicalData)}
        var assessments:[UUID:MeasurementQualityAssessmentV1]=[:]
        for source in sourceAssessments {
            let base = try source.rebound(to: workspaceID)
            let subject: (UInt64, String)
            switch source.subjectKind {
            case .capture:
                guard let value = captures[source.subjectID] else {
                    throw BackupRestoreServiceError.invalidPackage
                }
                subject = (value.revision, value.captureSHA256)
            case .series:
                let matchingSourceSubjects = sourceSeries.filter {
                    ($0.snapshotID == source.subjectID || $0.seriesID == source.subjectID)
                        && $0.revision == source.subjectRevision
                        && $0.seriesSHA256 == source.subjectSHA256
                }
                guard matchingSourceSubjects.count == 1,
                      let value = series[matchingSourceSubjects[0].snapshotID],
                      value.state == .finalized else {
                    throw BackupRestoreServiceError.invalidPackage
                }
                subject = (value.revision, value.seriesSHA256)
            }
            let value = try MeasurementQualityAssessmentV1(
                assessmentID: base.assessmentID,
                workspaceID: workspaceID,
                subjectKind: base.subjectKind,
                subjectID: base.subjectID,
                subjectRevision: subject.0,
                subjectSHA256: subject.1,
                result: base.result,
                reasonCodes: base.reasonCodes,
                policyVersion: base.policyVersion,
                policySHA256: base.policySHA256,
                evidence: base.evidence,
                reviewer: base.reviewer,
                overrideRationale: base.overrideRationale,
                assessedAt: base.assessedAt,
                supersedesAssessmentID: base.supersedesAssessmentID,
                revision: base.revision,
                mutationID: base.mutationID
            )
            assessments[value.assessmentID] = value
        }
        var output:[V18BackupMeasurementIntegrityRecordV1]=[]
        output += try instruments.values.map{.init(kind:.instrumentReference,id:$0.referenceID,workspaceID:workspaceID.rawValue,revision:$0.revision,canonicalData:try MeasurementIntegrityCanonicalCodecV1.encode($0))};output += try calibrations.values.map{.init(kind:.calibrationSnapshot,id:$0.snapshotID,workspaceID:workspaceID.rawValue,revision:$0.revision,canonicalData:try MeasurementIntegrityCanonicalCodecV1.encode($0))};output += try captures.values.map{.init(kind:.measurementCapture,id:$0.captureID,workspaceID:workspaceID.rawValue,revision:$0.revision,canonicalData:try MeasurementIntegrityCanonicalCodecV1.encode($0))};output += try series.values.map{.init(kind:.measurementSeries,id:$0.snapshotID,workspaceID:workspaceID.rawValue,revision:$0.revision,canonicalData:try MeasurementIntegrityCanonicalCodecV1.encode($0))};output += try assessments.values.map{.init(kind:.qualityAssessment,id:$0.assessmentID,workspaceID:workspaceID.rawValue,revision:$0.revision,canonicalData:try MeasurementIntegrityCanonicalCodecV1.encode($0))}
        return output.sorted{"\($0.kind.rawValue)\u{0}\($0.id.uuidString)"<"\($1.kind.rawValue)\u{0}\($1.id.uuidString)"}
    }

    func rebindingInspectionReview(
        _ records: [V14BackupInspectionReviewRecordV1], workspaceID: WorkspaceID,
        sourceEvidenceAssurance: [V13BackupEvidenceAssuranceRecordV1],
        evidenceAssurance: [V13BackupEvidenceAssuranceRecordV1],
        sourceAuthorityCriterion: [V11BackupAuthorityCriterionRecordV1],
        authorityCriterion: [V11BackupAuthorityCriterionRecordV1],
        sourceFunctionalRelationships: [V12BackupFunctionalRelationshipRecordV1],
        functionalRelationships: [V12BackupFunctionalRelationshipRecordV1],
        sourceReports: [V4BackupReportDTO], reboundReports: [V4BackupReportDTO],
        members: ValidatedV4BackupMembersV1
    ) throws -> [V14BackupInspectionReviewRecordV1] {
        let reboundPolicies = try Dictionary(uniqueKeysWithValues: records.compactMap { record -> (UUID, CorrectiveActionPolicyV1)? in
            guard record.kind == .correctiveActionPolicy else { return nil }
            let source = try InspectionReviewCanonicalCodecV1.decode(CorrectiveActionPolicyV1.self, from: record.canonicalData)
            let rebound = try source.rebound(to: workspaceID)
            return (rebound.releaseID, rebound)
        })
        let reboundManifests = try Dictionary(uniqueKeysWithValues: evidenceAssurance.compactMap { record -> (UUID, AssuranceManifestV1)? in
            guard record.kind == .manifest else { return nil }
            let value = try EvidenceAssuranceCanonicalCodecV1.decode(AssuranceManifestV1.self, from: record.canonicalData)
            return (value.manifestID, value)
        })
        let reboundLinks = try Dictionary(uniqueKeysWithValues: evidenceAssurance.compactMap { record -> (UUID, ClaimEvidenceLinkV1)? in
            guard record.kind == .evidenceLink else { return nil }
            let value = try EvidenceAssuranceCanonicalCodecV1.decode(ClaimEvidenceLinkV1.self, from: record.canonicalData)
            return (value.linkID, value)
        })
        var digestRebindings: [String: String] = [:]
        func normalizedReferenceID(_ id: String) -> String { UUID(uuidString:id)?.uuidString ?? id }
        func key(_ family: String, _ id: String, _ revision: UInt64, _ digest: String) -> String {
            "\(family)\u{0}\(normalizedReferenceID(id))\u{0}\(revision)\u{0}\(digest)"
        }
        func bind(_ family: String, _ id: String, _ revision: UInt64, _ old: String, _ new: String) {
            digestRebindings[key(family, id, revision, old)] = new
        }
        let reboundReportByID = Dictionary(uniqueKeysWithValues: reboundReports.map { ($0.id, $0) })
        for source in sourceReports {
            guard let rebound = reboundReportByID[source.id],
                  let bytes = members[source.snapshotRelativePath] else {
                throw BackupRestoreServiceError.invalidPackage
            }
            let snapshot = try ReportSnapshotEncoderV1().decode(bytes)
            for id in [source.id.uuidString, snapshot.reportID.uuidString,
                       snapshot.sourceRecordID.uuidString, snapshot.stableRootID.uuidString] {
                bind("reportSnapshot", id, UInt64(source.snapshotSchemaVersion), source.snapshotSHA256, rebound.snapshotSHA256)
                bind("completedActivitySnapshot", id, UInt64(source.snapshotSchemaVersion), source.snapshotSHA256, rebound.snapshotSHA256)
            }
            if let old = snapshot.functionalRelationships {
                let reboundData = try reboundReportSnapshotData(bytes, workspaceID: workspaceID)
                if let new = try ReportSnapshotEncoderV1().decode(reboundData).functionalRelationships {
                    bind("functionalRelationshipSnapshot", old.snapshotID.uuidString,
                         UInt64(old.schemaVersion), old.snapshotSHA256, new.snapshotSHA256)
                }
            }
        }
        let sourceLinks = try Dictionary(uniqueKeysWithValues: sourceEvidenceAssurance.compactMap { record -> (UUID, ClaimEvidenceLinkV1)? in
            guard record.kind == .evidenceLink else { return nil }
            let value = try EvidenceAssuranceCanonicalCodecV1.decode(ClaimEvidenceLinkV1.self, from: record.canonicalData)
            return (value.linkID, value)
        })
        for (id, rebound) in reboundLinks {
            guard let source = sourceLinks[id] else { throw BackupRestoreServiceError.invalidPackage }
            bind("claimEvidenceLink", id.uuidString, source.revision, source.linkSHA256, rebound.linkSHA256)
            bind("evidence", id.uuidString, source.revision, source.linkSHA256, rebound.linkSHA256)
        }
        let reboundClassifications = try Dictionary(uniqueKeysWithValues: authorityCriterion.compactMap { record -> (UUID, FindingClassificationBindingV1)? in
            guard record.kind == .findingClassificationBinding else { return nil }
            let value = try AuthorityCriterionCanonicalCodecV1.decode(FindingClassificationBindingV1.self, from: record.canonicalData)
            return (value.bindingID, value)
        })
        for record in sourceAuthorityCriterion where record.kind == .findingClassificationBinding {
            let source = try AuthorityCriterionCanonicalCodecV1.decode(FindingClassificationBindingV1.self, from: record.canonicalData)
            guard let rebound = reboundClassifications[source.bindingID] else { throw BackupRestoreServiceError.invalidPackage }
            bind("finding", source.findingID.uuidString, source.revision, source.bindingSHA256, rebound.bindingSHA256)
            bind("criterion", source.criterionID, source.revision, source.bindingSHA256, rebound.bindingSHA256)
        }
        let reboundRelationshipEvents = try Dictionary(uniqueKeysWithValues: functionalRelationships.compactMap { record -> (UUID, AssetFunctionalRelationshipEventV1)? in
            guard record.kind == .event else { return nil }
            let value = try FunctionalRelationshipCanonicalCodecV1.decode(AssetFunctionalRelationshipEventV1.self, from: record.canonicalData)
            return (value.eventID, value)
        })
        for record in sourceFunctionalRelationships where record.kind == .event {
            let source = try FunctionalRelationshipCanonicalCodecV1.decode(AssetFunctionalRelationshipEventV1.self, from: record.canonicalData)
            guard let rebound = reboundRelationshipEvents[source.eventID] else { throw BackupRestoreServiceError.invalidPackage }
            for id in [source.relationshipID.uuidString, source.eventID.uuidString] {
                bind("functionalRelationship", id, source.revision, source.eventSHA256, rebound.eventSHA256)
            }
        }
        func reboundDigest(_ family: String, _ id: String, _ revision: UInt64, _ digest: String) -> String {
            digestRebindings[key(family, id, revision, digest)] ?? digest
        }
        func reboundItem(_ value: ChangeRequestItemReferenceV1) throws -> ChangeRequestItemReferenceV1 {
            let family: String
            switch value.kind { case .review: family="review";case .finding:family="finding";case .criterion:family="criterion";case .evidence:family="evidence";case .functionalRelationship:family="functionalRelationship" }
            return try .init(kind:value.kind,itemID:value.itemID,itemRevision:value.itemRevision,
                             itemSHA256:reboundDigest(family,value.itemID,value.itemRevision,value.itemSHA256))
        }
        func reboundSubject(_ value: InspectionReviewSubjectReferenceV1) throws -> InspectionReviewSubjectReferenceV1 {
            let family: String
            switch value.kind { case .completedActivitySnapshot:family="completedActivitySnapshot";case .reportSnapshot:family="reportSnapshot";case .finding:family="finding" }
            return try .init(workspaceID:workspaceID,kind:value.kind,subjectID:value.subjectID,
                             subjectRevision:value.subjectRevision,
                             subjectSHA256:reboundDigest(family,value.subjectID,value.subjectRevision,value.subjectSHA256),
                             packageRelease:value.packageRelease)
        }
        let reboundTransitions = try Dictionary(uniqueKeysWithValues: records.compactMap { record -> (UUID, InspectionReviewTransitionV1)? in
            guard record.kind == .reviewTransition else { return nil }
            let source = try InspectionReviewCanonicalCodecV1.decode(InspectionReviewTransitionV1.self, from: record.canonicalData)
            let base = try source.rebound(to: workspaceID)
            let rebound = try InspectionReviewTransitionV1(
                transitionID:base.transitionID,reviewID:base.reviewID,workspaceID:workspaceID,
                subject:reboundSubject(source.subject),fromState:base.fromState,toState:base.toState,
                actor:base.actor,reason:base.reason,dispositionID:base.dispositionID,
                changeRequestIDs:base.changeRequestIDs,successorReviewID:base.successorReviewID,
                successorSubject:try source.successorSubject.map(reboundSubject),occurredAt:base.occurredAt,
                recordedAt:base.recordedAt,predecessorTransitionID:base.predecessorTransitionID,
                revision:base.revision,mutationID:base.mutationID)
            bind("review", source.reviewID.uuidString, source.revision, source.transitionSHA256, rebound.transitionSHA256)
            return (source.transitionID, rebound)
        })
        func reboundEvidence(_ values: [ReviewEvidenceReferenceV1]) throws -> [ReviewEvidenceReferenceV1] {
            try values.map { value in
                let family: String
                switch value.kind {case .claimEvidenceLink:family="claimEvidenceLink";case .verifiedRecheck:family="verifiedRecheck";case .completedActivitySnapshot:family="completedActivitySnapshot";case .requirementEvaluation:family="requirementEvaluation";case .functionalRelationshipSnapshot:family="functionalRelationshipSnapshot";case .externalEvidenceReference:family="externalEvidenceReference"}
                return try ReviewEvidenceReferenceV1(
                    kind: value.kind, referenceID: value.referenceID,
                    revision: value.revision,
                    sha256: reboundDigest(family,value.referenceID,value.revision,value.sha256)
                )
            }
        }
        return try records.map { record in
            let data: Data
            let identity: (UUID, UInt64)
            switch record.kind {
            case .reviewTransition:
                let source = try InspectionReviewCanonicalCodecV1.decode(InspectionReviewTransitionV1.self, from: record.canonicalData)
                guard let rebound = reboundTransitions[source.transitionID] else { throw BackupRestoreServiceError.invalidPackage }
                data = try InspectionReviewCanonicalCodecV1.encode(rebound); identity = (rebound.transitionID, rebound.revision)
            case .reviewDisposition:
                let source = try InspectionReviewCanonicalCodecV1.decode(ReviewDispositionV1.self, from: record.canonicalData)
                let base = try source.rebound(to: workspaceID)
                let manifest = try base.assuranceManifestID.map { id -> AssuranceManifestV1 in
                    guard let value = reboundManifests[id] else { throw BackupRestoreServiceError.invalidPackage }
                    return value
                }
                let rebound = try ReviewDispositionV1(
                    dispositionID: base.dispositionID, reviewID: base.reviewID,
                    workspaceID: workspaceID, subject: reboundSubject(source.subject),
                    reviewRevision: base.reviewRevision, kind: base.kind,
                    reviewer: base.reviewer, reason: base.reason,
                    changeRequestIDs: base.changeRequestIDs,
                    assuranceManifestID: manifest?.manifestID,
                    assuranceManifestRevision: manifest?.revision,
                    assuranceManifestSHA256: manifest?.manifestSHA256,
                    recordedAt: base.recordedAt,
                    supersedesDispositionID: base.supersedesDispositionID,
                    revision: base.revision, mutationID: base.mutationID
                )
                data = try InspectionReviewCanonicalCodecV1.encode(rebound); identity = (rebound.dispositionID, rebound.revision)
            case .changeRequest:
                let source = try InspectionReviewCanonicalCodecV1.decode(ChangeRequestV1.self, from: record.canonicalData)
                let base = try source.rebound(to: workspaceID)
                let resolution = try base.resolution.map { value in
                    try ChangeRequestResolutionV1(
                        kind: value.kind, resolver: value.resolver,
                        evidence: reboundEvidence(value.evidence), reason: value.reason,
                        resolvedAt: value.resolvedAt
                    )
                }
                let rebound = try ChangeRequestV1(
                    requestRevisionID: base.requestRevisionID, requestID: base.requestID,
                    reviewID: base.reviewID, workspaceID: workspaceID,
                    reviewRevision: base.reviewRevision, item: reboundItem(source.item), reason: base.reason,
                    requirements: base.requirements, requester: base.requester, state: base.state,
                    resolution: resolution, recordedAt: base.recordedAt,
                    supersedesRequestRevisionID: base.supersedesRequestRevisionID,
                    revision: base.revision, mutationID: base.mutationID
                )
                data = try InspectionReviewCanonicalCodecV1.encode(rebound); identity = (rebound.requestRevisionID, rebound.revision)
            case .correctiveActionPolicy:
                let source = try InspectionReviewCanonicalCodecV1.decode(CorrectiveActionPolicyV1.self, from: record.canonicalData)
                let rebound = try source.rebound(to: workspaceID)
                data = try InspectionReviewCanonicalCodecV1.encode(rebound); identity = (rebound.releaseID, rebound.revision)
            case .correctiveActionEvent:
                let source = try InspectionReviewCanonicalCodecV1.decode(CorrectiveActionEventV1.self, from: record.canonicalData)
                let base = try source.rebound(to: workspaceID)
                guard let policy = reboundPolicies[base.policy.releaseID] else {
                    throw BackupRestoreServiceError.invalidPackage
                }
                let rebound = try CorrectiveActionEventV1(
                    eventID: base.eventID, actionID: base.actionID, workspaceID: workspaceID,
                    source: reboundItem(source.source), policy: CorrectiveActionPolicyReferenceV1(policy),
                    priority: base.priority, state: base.state, assignee: base.assignee,
                    recorder: base.recorder, due: base.due,
                    closureEvidence: reboundEvidence(base.closureEvidence),
                    verifier: base.verifier, reopenTrigger: base.reopenTrigger, reason: base.reason,
                    occurredAt: base.occurredAt, recordedAt: base.recordedAt,
                    predecessorEventID: base.predecessorEventID, revision: base.revision,
                    mutationID: base.mutationID
                )
                data = try InspectionReviewCanonicalCodecV1.encode(rebound); identity = (rebound.eventID, rebound.revision)
            }
            guard identity == (record.id, record.revision) else {
                throw BackupRestoreServiceError.invalidPackage
            }
            return .init(kind: record.kind, id: identity.0, workspaceID: workspaceID.rawValue,
                         revision: identity.1, canonicalData: data)
        }
    }

    func rebindingEvidenceAssurance(
        _ records: [V13BackupEvidenceAssuranceRecordV1], workspaceID: WorkspaceID,
        sourcePreviews: [UUID: AssuranceProjectionPreviewV1]
    ) throws -> [V13BackupEvidenceAssuranceRecordV1] {
        do {
            var visibilities: [UUID: EvidenceVisibilityV1] = [:]
            for record in records where record.kind == .visibility {
                let source = try EvidenceAssuranceCanonicalCodecV1.decode(EvidenceVisibilityV1.self, from: record.canonicalData)
                visibilities[source.visibilityID] = source.workspaceID == workspaceID ? source : try source.rebound(to: workspaceID)
            }
            var links: [UUID: ClaimEvidenceLinkV1] = [:]
            for record in records where record.kind == .evidenceLink {
                let source = try EvidenceAssuranceCanonicalCodecV1.decode(ClaimEvidenceLinkV1.self, from: record.canonicalData)
                guard let visibility = visibilities[source.visibilityID] else { throw BackupRestoreServiceError.invalidPackage }
                links[source.linkID] = source.workspaceID == workspaceID ? source : try source.rebound(to: workspaceID, visibility: visibility)
            }
            var manifests: [UUID: AssuranceManifestV1] = [:]
            for record in records where record.kind == .manifest {
                let source = try EvidenceAssuranceCanonicalCodecV1.decode(AssuranceManifestV1.self, from: record.canonicalData)
                if source.workspaceID == workspaceID { manifests[source.manifestID] = source; continue }
                let sourceLinks = source.includedLinks + source.excludedLinks
                let reboundLinks = try sourceLinks.map { link -> ClaimEvidenceLinkV1 in
                    guard let value = links[link.linkID] else { throw BackupRestoreServiceError.invalidPackage }
                    return value
                }
                guard let frozenPreview = sourcePreviews[source.sourcePreviewID] else {
                    throw BackupRestoreServiceError.invalidPackage
                }
                try source.validateFresh(preview: frozenPreview)
                let preview = try frozenPreview.rebound(to: workspaceID, links: reboundLinks)
                manifests[source.manifestID] = try source.rebound(to: workspaceID, preview: preview)
            }
            var attestations: [UUID: AttestationV1] = [:]
            for record in records where record.kind == .attestation {
                let source = try EvidenceAssuranceCanonicalCodecV1.decode(AttestationV1.self, from: record.canonicalData)
                guard let manifest = manifests[source.manifestID] else { throw BackupRestoreServiceError.invalidPackage }
                attestations[source.attestationID] = source.workspaceID == workspaceID ? source : try source.rebound(to: workspaceID, manifest: manifest)
            }
            return try records.map { record in
                let valueData: Data
                switch record.kind {
                case .visibility: valueData = try EvidenceAssuranceCanonicalCodecV1.encode(visibilities[record.id]!)
                case .evidenceLink: valueData = try EvidenceAssuranceCanonicalCodecV1.encode(links[record.id]!)
                case .manifest: valueData = try EvidenceAssuranceCanonicalCodecV1.encode(manifests[record.id]!)
                case .attestation: valueData = try EvidenceAssuranceCanonicalCodecV1.encode(attestations[record.id]!)
                }
                return .init(kind: record.kind, id: record.id, workspaceID: workspaceID.rawValue,
                             revision: record.revision, canonicalData: valueData)
            }
        } catch { throw BackupRestoreServiceError.invalidPackage }
    }

    func recordsWithObservationAndTime(
        _ records: V4BackupRecordsV1
    ) throws -> V4BackupRecordsV1 {
        guard records.recordsSchemaVersion < 4 else { return records }
        let workflowRecords = try records.workflowRecords.map { value in
            let data = try observationAndTimeData(
                for: value,
                recordsSchemaVersion: records.recordsSchemaVersion
            )
            return value.replacingObservationAndTime(
                basisData: data.basis,
                temporalData: data.temporal
            )
        }
        return V4BackupRecordsV1(
            evidenceAssurance: [], functionalRelationships: [], authorityCriterion: [], assetSemantics: [],
            assetCompositionEdges: records.assetCompositionEdges,
            assetCompositionEvents: records.assetCompositionEvents,
            assetPlacementEvents: records.assetPlacementEvents,
            assets: records.assets,
            deletionLedger: records.deletionLedger,
            evidenceFiles: records.evidenceFiles,
            issues: records.issues,
            locationHierarchyEvents: records.locationHierarchyEvents,
            locationMigrationReceipts: records.locationMigrationReceipts,
            locationNodes: records.locationNodes,
            mutationHistory: records.mutationHistory,
            packets: records.packets,
            partyAccountability: [],
            recordsSchemaVersion: 4,
            reports: records.reports,
            requirementAssurance: records.requirementAssurance,
            savedSmartViews: records.savedSmartViews,
            sites: records.sites,
            workflowRecords: workflowRecords
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
                authority: generationAuthority,
                recordsSchemaVersion: records.recordsSchemaVersion,
                sourceGenerationID: value.manifest.source.sourceGenerationID,
                archiveProvenanceSHA256: try BackupCanonicalEncoderV1()
                    .encodeManifest(value.manifest).sha256
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

    func publishRestoredDraftStaging(
        package: ValidatedV4BackupPackageV1,
        records: V4BackupRecordsV1,
        identityDecision: RestoreIdentityV1?,
        restoreID: UUID
    ) throws -> DraftAttachmentRestorePublicationReceiptV1? {
        let sourceItems = try package.records.fieldDrafts.compactMap { record -> AttachmentStagingItemV1? in
            guard record.kind == .stagingItem else { return nil }
            return try FieldDraftCanonicalCodecV1.decode(AttachmentStagingItemV1.self,from:record.canonicalData)
        }
        let targetItems = try records.fieldDrafts.compactMap { record -> AttachmentStagingItemV1? in
            guard record.kind == .stagingItem else { return nil }
            return try FieldDraftCanonicalCodecV1.decode(AttachmentStagingItemV1.self,from:record.canonicalData)
        }
        let restorableSources = sourceItems.filter {
            ($0.state == .readyLocal || $0.state == .committed)
                && $0.actualByteCount != nil && $0.contentDigest != nil
        }
        guard !restorableSources.isEmpty else {
            guard targetItems.filter({ $0.state == .readyLocal || $0.state == .committed }).isEmpty else {
                throw BackupRestoreServiceError.invalidPackage
            }
            return nil
        }
        let targets = Dictionary(uniqueKeysWithValues: targetItems.map { ($0.stageID,$0) })
        var entries: [DraftAttachmentStagingEntryV1] = []
        for source in restorableSources {
            let targetID: UUID
            if let identityDecision {
                guard let mapped = identityDecision.destinationFieldDraftID(for:source.stageID,namespace:"stage") else {
                    throw BackupRestoreServiceError.invalidPackage
                }
                targetID = mapped
            } else { targetID = source.stageID }
            guard let target = targets[targetID],
                  target.actualByteCount == source.actualByteCount,
                  target.contentDigest == source.contentDigest else {
                throw BackupRestoreServiceError.invalidPackage
            }
            entries.append(try DraftAttachmentStagingEntryV1(
                item:target,
                relativeDataPath:"\(source.draftID.uuidString.lowercased())/\(source.stageID.uuidString.lowercased()).bin",
                mediaType:draftAttachmentMediaType(source.attachmentKind),
                updatedAt:package.manifest.exportedAt
            ))
        }
        let manifest = try DraftAttachmentStagingManifestV1(entries:entries)
        let workspaceID = entries[0].item.workspaceID
        guard entries.allSatisfy({$0.item.workspaceID == workspaceID}) else {
            throw BackupRestoreServiceError.invalidPackage
        }
        let adapter = try DraftAttachmentStagingAdapterV1(
            applicationSupportURL:applicationSupportURL,
            workspaceID:workspaceID,
            fileManager:fileManager,
            clock:now
        )
        let receipt = try adapter.adoptRestoredStaging(
            from:package.stagedPackageURL.appendingPathComponent("draft-staging",isDirectory:true),
            entries:entries,
            workspaceID:workspaceID,
            sourceManifestSHA256:manifest.manifestSHA256,
            restoreID:restoreID
        )
        try receipt.validate()
        guard Set(receipt.adoptedStageIDs + receipt.reusedStageIDs) == Set(entries.map{$0.item.stageID}),
              receipt.atomicAcrossRoots == false, receipt.canonicalCommitRequired else {
            throw BackupRestoreServiceError.recoveryRequired
        }
        return receipt
    }

    func draftPublicationBindingURL(restoreID: UUID) -> URL {
        applicationSupportURL
            .appendingPathComponent("FieldEvidenceRestore", isDirectory: true)
            .appendingPathComponent(
                "draft-publication-\(canonical(restoreID)).json",
                isDirectory: false
            )
    }

    func expectedDraftPublicationStageIDs(
        in records: V4BackupRecordsV1
    ) throws -> Set<UUID> {
        Set(try records.fieldDrafts.compactMap { record in
            guard record.kind == .stagingItem else { return nil }
            let item = try FieldDraftCanonicalCodecV1.decode(
                AttachmentStagingItemV1.self,
                from: record.canonicalData
            )
            guard (item.state == .readyLocal || item.state == .committed),
                  item.actualByteCount != nil,
                  item.contentDigest != nil else { return nil }
            return item.stageID
        })
    }

    func persistDraftPublicationBinding(
        _ receipt: DraftAttachmentRestorePublicationReceiptV1
    ) throws {
        let binding = try DraftRestorePublicationBindingV1(receipt: receipt)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(binding)
        let url = draftPublicationBindingURL(restoreID: receipt.restoreID)
        if fileManager.fileExists(atPath: url.path) {
            guard try Data(contentsOf: url) == data else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
        } else {
            try data.write(to: url, options: [.atomic])
        }
        try ProtectedFilePolicyV1.applyAndVerify(.stagingFile, at: url)
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        defer { _ = Darwin.close(descriptor) }
        let directory = Darwin.open(
            url.deletingLastPathComponent().path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard directory >= 0 else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        defer { _ = Darwin.close(directory) }
        guard Darwin.fsync(descriptor) == 0,
              Darwin.fsync(directory) == 0,
              try Data(contentsOf: url) == data else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
    }

    func validateDraftPublicationBinding(
        intent: RestoreIntentV1,
        records: V4BackupRecordsV1
    ) throws {
        let expected = try expectedDraftPublicationStageIDs(in: records)
        let url = draftPublicationBindingURL(restoreID: intent.restoreID)
        guard !expected.isEmpty else {
            guard !fileManager.fileExists(atPath: url.path) else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            return
        }
        try ProtectedFilePolicyV1.verify(.stagingFile, at: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let data = try Data(contentsOf: url)
        let binding = try decoder.decode(
            DraftRestorePublicationBindingV1.self,
            from: data
        )
        try binding.validate()
        let receipt = binding.receipt
        let actual = Set(receipt.adoptedStageIDs + receipt.reusedStageIDs)
        guard let targetWorkspaceID = intent.identity?.targetPointer.workspaceID
                ?? records.fieldDrafts.first?.workspaceID else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        guard receipt.restoreID == intent.restoreID,
              receipt.workspaceID.rawValue == targetWorkspaceID,
              actual == expected,
              receipt.adoptedStageIDs.count + receipt.reusedStageIDs.count
                == expected.count else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
    }

    func removeDraftPublicationBinding(_ intent: RestoreIntentV1) throws {
        let url = draftPublicationBindingURL(restoreID: intent.restoreID)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try ProtectedFilePolicyV1.verify(.stagingFile, at: url)
        try fileManager.removeItem(at: url)
        let directory = Darwin.open(
            url.deletingLastPathComponent().path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard directory >= 0 else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        defer { _ = Darwin.close(directory) }
        guard Darwin.fsync(directory) == 0 else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
    }

    func draftAttachmentMediaType(_ kind:DraftAttachmentKindV1)->String{
        switch kind{case .photo:return "image/jpeg";case .audio:return "audio/mpeg";case .video:return "video/mp4";case .file:return "application/octet-stream"}
    }

    func observationAndTimeData(
        for value: V4BackupWorkflowRecordDTO,
        recordsSchemaVersion: Int
    ) throws -> (basis: Data?, temporal: Data?) {
        do {
            if recordsSchemaVersion == 4 || recordsSchemaVersion == 5
                || recordsSchemaVersion == 6 || recordsSchemaVersion == 7
                || recordsSchemaVersion == 8 {
                guard let basisData = value.observationBasisV1Data,
                      let temporalData = value.temporalContextV1Data else {
                    throw BackupRestoreServiceError.invalidPackage
                }
                let basis = try ObservationAndTimeCodecV1
                    .decodeObservationBasis(basisData)
                let temporal = try ObservationAndTimeCodecV1
                    .decodeTemporalContext(temporalData)
                guard try ObservationAndTimeCodecV1.encode(basis) == basisData,
                      try ObservationAndTimeCodecV1.encode(temporal) == temporalData else {
                    throw BackupRestoreServiceError.invalidPackage
                }
                return (basisData, temporalData)
            }
            guard (1...3).contains(recordsSchemaVersion),
                  value.observationBasisV1Data == nil,
                  value.temporalContextV1Data == nil else {
                throw BackupRestoreServiceError.invalidPackage
            }
            var basis = try ObservationAndTimeLegacyMigrationV1.observationBasis(
                couldNotVerifyKey: value.couldNotVerifyKey,
                displaySnapshot: value.couldNotVerifyDisplaySnapshot,
                registryVersion: value.couldNotVerifyRegistryVersion
            )
            var temporal = try ObservationAndTimeLegacyMigrationV1.temporalContext(
                observedAtUTC: value.observedAtUTC,
                recordedAtUTC: value.completedAt ?? value.startedAt,
                timeZoneID: value.timeZoneID,
                utcOffsetMinutes: value.utcOffsetMinutes,
                localDate: value.localDate,
                localTime: value.localTime
            )
            if basis == nil {
                basis = try ObservationBasisV1(
                    kind: .unknown,
                    method: ObservationMethodV1(key: ObservationMethodV1.unknownKey),
                    source: ObservationSourceReferenceV1(kind: .unknown)
                )
            }
            if temporal == nil {
                temporal = try TemporalContextV1(
                    occurredAtUTC: nil,
                    recordedAtUTC: value.completedAt ?? value.startedAt,
                    localDate: nil,
                    localTime: nil,
                    utcOffsetSeconds: nil,
                    ianaTimeZoneIdentifier: nil,
                    localTimeDisposition: .unknown
                )
            }
            guard let basis, let temporal else {
                throw BackupRestoreServiceError.invalidPackage
            }
            return (
                try ObservationAndTimeCodecV1.encode(basis),
                try ObservationAndTimeCodecV1.encode(temporal)
            )
        } catch let failure as BackupRestoreServiceError {
            throw failure
        } catch {
            throw BackupRestoreServiceError.invalidPackage
        }
    }

    func insert(
        _ records: V4BackupRecordsV1,
        into context: ModelContext,
        generationID: UUID,
        identityDecision: RestoreIdentityV1?,
        legacyDestinationIdentity: WorkspaceReplicaIdentityV1
    ) throws {
        guard (records.recordsSchemaVersion == 3
                || records.recordsSchemaVersion == 4
                || records.recordsSchemaVersion == 5
                || records.recordsSchemaVersion == 6
                || records.recordsSchemaVersion == 7
                || records.recordsSchemaVersion == 8
                || records.recordsSchemaVersion == 9
                || records.recordsSchemaVersion == 10
                || records.recordsSchemaVersion == 11
                || records.recordsSchemaVersion == 12
                || records.recordsSchemaVersion == 13
                || records.recordsSchemaVersion == 14
                || records.recordsSchemaVersion == 15
                || records.recordsSchemaVersion == 16
                || records.recordsSchemaVersion == 17)
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
        case (2, let ledger?, nil), (3, let ledger?, _), (4, let ledger?, _),
             (5, let ledger?, _), (6, let ledger?, _),
             (7, let ledger?, _), (8, let ledger?, _),
             (9, let ledger?, _), (10, let ledger?, _), (11, let ledger?, _),
             (12, let ledger?, _):
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
        if records.recordsSchemaVersion >= 5 {
            do {
                for record in records.locationNodes {
                    let value = try LocationPersistenceCodecV1.decode(
                        LocationNodeV1.self, from: record.canonicalData
                    )
                    guard value.id == record.id,
                          record.secondaryCanonicalData == nil else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                    context.insert(try LocationNodeRow(value))
                }
                for record in records.assetPlacementEvents {
                    let value = try LocationPersistenceCodecV1.decode(
                        AssetPlacementEventV1.self, from: record.canonicalData
                    )
                    guard value.id == record.id,
                          record.secondaryCanonicalData == nil else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                    context.insert(try AssetPlacementEventRow(value))
                }
                for record in records.assetCompositionEdges {
                    let value = try LocationPersistenceCodecV1.decode(
                        AssetCompositionEdgeV1.self, from: record.canonicalData
                    )
                    guard value.id == record.id,
                          record.secondaryCanonicalData == nil else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                    context.insert(try AssetCompositionEdgeRow(value))
                }
                for record in records.assetCompositionEvents {
                    let value = try LocationPersistenceCodecV1.decode(
                        AssetCompositionEventV1.self, from: record.canonicalData
                    )
                    guard value.id == record.id,
                          record.secondaryCanonicalData == nil else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                    context.insert(try AssetCompositionEventRow(value))
                }
                for record in records.locationHierarchyEvents {
                    guard let receiptData = record.secondaryCanonicalData else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                    let plan = try LocationPersistenceCodecV1.decode(
                        LocationHierarchyChangePlanV1.self, from: record.canonicalData
                    )
                    let receipt = try LocationPersistenceCodecV1.decode(
                        LocationHierarchyChangeReceiptV1.self, from: receiptData
                    )
                    guard plan.operationID == record.id else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                    context.insert(try LocationHierarchyEventRow(
                        plan: plan, receipt: receipt
                    ))
                }
                for record in records.locationMigrationReceipts {
                    let value = try LocationPersistenceCodecV1.decode(
                        LocationMigrationReceiptV1.self, from: record.canonicalData
                    )
                    guard value.candidateGenerationID == record.id,
                          record.secondaryCanonicalData == nil else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                    context.insert(try LocationMigrationReceiptRow(value))
                }
            } catch {
                throw BackupRestoreServiceError.invalidPackage
            }
        }
        for value in records.workflowRecords {
            let observationAndTime = try observationAndTimeData(
                for: value,
                recordsSchemaVersion: records.recordsSchemaVersion
            )
            guard let revision = WorkflowRevisionKind(rawValue: value.revisionKind),
                  let stage = WorkflowStage(rawValue: value.stage),
                  let state = WorkflowState(rawValue: value.state),
                  value.draftStepKey == nil
                    || WorkflowDraftStep(rawValue: value.draftStepKey!) != nil else {
                throw BackupRestoreServiceError.invalidPackage
            }
            guard let basisData = observationAndTime.basis,
                  let temporalData = observationAndTime.temporal else {
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
            context.insert(try ObservationAndTimeRow(
                recordID: value.id,
                observationBasisV1Data: basisData,
                temporalContextV1Data: temporalData
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
        if records.recordsSchemaVersion == 6 || records.recordsSchemaVersion == 7
            || records.recordsSchemaVersion == 8 || records.recordsSchemaVersion == 9
            || records.recordsSchemaVersion == 10
            || records.recordsSchemaVersion == 11
            || records.recordsSchemaVersion == 12
            || records.recordsSchemaVersion == 13 || records.recordsSchemaVersion == 14
            || records.recordsSchemaVersion == 15
            || records.recordsSchemaVersion == 16
            || records.recordsSchemaVersion == 17 {
            do {
                for record in records.savedSmartViews {
                    let descriptor = try record.descriptor()
                    guard descriptor.id == record.id else {
                        throw BackupRestoreServiceError.invalidPackage
                    }
                    context.insert(try SavedSmartViewRowV1(descriptor))
                }
            } catch {
                throw BackupRestoreServiceError.invalidPackage
            }
        }
        if records.recordsSchemaVersion >= 7 {
            do {
                for record in records.requirementAssurance {
                    let snapshot = try record.snapshot()
                    context.insert(try RequirementAssuranceRow(
                        snapshot: snapshot,
                        mutationID: record.mutationID,
                        createdAt: record.createdAt,
                        updatedAt: record.updatedAt
                    ))
                }
            } catch { throw BackupRestoreServiceError.invalidPackage }
        }
        if records.recordsSchemaVersion >= 8 {
            do {
                var roleValues: [UUID: SitePartyRoleEventV1] = [:]
                var signoffValues: [UUID: SignoffSnapshotV1] = [:]
                for record in records.partyAccountability {
                    switch record.kind {
                    case .serviceParty:
                        let value = try PartyAccountabilitySnapshotCodecV1.decode(
                            ServicePartyReferenceV1.self, from: record.canonicalData
                        )
                        context.insert(try ServicePartyRow(value))
                    case .sitePartyRoleEvent:
                        let value = try PartyAccountabilitySnapshotCodecV1.decode(
                            SitePartyRoleEventV1.self, from: record.canonicalData
                        )
                        roleValues[value.eventID] = value
                    case .actorSnapshot:
                        let value = try PartyAccountabilitySnapshotCodecV1.decode(
                            ActorSnapshotV1.self, from: record.canonicalData
                        )
                        context.insert(try ActorSnapshotRow(value))
                    case .qualificationSnapshot:
                        let value = try PartyAccountabilitySnapshotCodecV1.decode(
                            QualificationSnapshotV1.self, from: record.canonicalData
                        )
                        context.insert(try QualificationSnapshotRow(value))
                    case .signoffSnapshot:
                        let value = try PartyAccountabilitySnapshotCodecV1.decode(
                            SignoffSnapshotV1.self, from: record.canonicalData
                        )
                        signoffValues[value.snapshotID] = value
                    }
                }
                for value in roleValues.values.sorted(by: { $0.recordedAt < $1.recordedAt }) {
                    context.insert(try SitePartyRoleEventRow(
                        value, predecessor: value.supersedesEventID.flatMap { roleValues[$0] }
                    ))
                }
                for value in signoffValues.values.sorted(by: { $0.recordedAt < $1.recordedAt }) {
                    context.insert(try SignoffSnapshotRow(
                        value, predecessor: value.supersedesSnapshotID.flatMap { signoffValues[$0] }
                    ))
                }
            } catch { throw BackupRestoreServiceError.invalidPackage }
        }
        if records.recordsSchemaVersion >= 9 {
            do {
                for record in records.assetSemantics {
                    switch record.kind {
                    case .kindBindingEvent:
                        context.insert(try AssetKindBindingEventRow(
                            AssetSemanticCanonicalCodecV1.decode(
                                AssetKindBindingEventV1.self, from: record.canonicalData
                            )
                        ))
                    case .workflowCapabilityBindingEvent:
                        context.insert(try AssetWorkflowCapabilityBindingEventRow(
                            AssetSemanticCanonicalCodecV1.decode(
                                AssetWorkflowCapabilityBindingEventV1.self,
                                from: record.canonicalData
                            )
                        ))
                    case .productIdentity:
                        context.insert(try AssetProductIdentityRow(
                            AssetSemanticCanonicalCodecV1.decode(
                                AssetProductIdentityV1.self, from: record.canonicalData
                            )
                        ))
                    case .lifecycleEvent:
                        context.insert(try AssetLifecycleEventRow(
                            AssetSemanticCanonicalCodecV1.decode(
                                AssetLifecycleEventV1.self, from: record.canonicalData
                            )
                        ))
                    case .successorLink:
                        context.insert(try AssetSuccessorLinkRow(
                            AssetSemanticCanonicalCodecV1.decode(
                                AssetSuccessorLinkV1.self, from: record.canonicalData
                            )
                        ))
                    case .workSubjectScopeSnapshot:
                        context.insert(try WorkSubjectScopeSnapshotRow(
                            AssetSemanticCanonicalCodecV1.decode(
                                WorkSubjectScopeSnapshotV1.self, from: record.canonicalData
                            )
                        ))
                    }
                }
            } catch { throw BackupRestoreServiceError.invalidPackage }
        }
        if records.recordsSchemaVersion >= 10 {
            do {
                for record in records.authorityCriterion {
                    switch record.kind {
                    case .authoritySourceRelease: context.insert(try AuthoritySourceReleaseRow(AuthorityCriterionCanonicalCodecV1.decode(AuthoritySourceReleaseV1.self, from: record.canonicalData)))
                    case .requirementBasisBinding: context.insert(try RequirementBasisBindingRow(AuthorityCriterionCanonicalCodecV1.decode(RequirementBasisBindingV1.self, from: record.canonicalData)))
                    case .applicabilityContextSnapshot: context.insert(try ApplicabilityContextSnapshotRow(AuthorityCriterionCanonicalCodecV1.decode(ApplicabilityContextSnapshotV1.self, from: record.canonicalData)))
                    case .assessmentScopeSnapshot: context.insert(try AssessmentScopeSnapshotRow(AuthorityCriterionCanonicalCodecV1.decode(AssessmentScopeSnapshotV1.self, from: record.canonicalData)))
                    case .severityScaleRelease: context.insert(try SeverityScaleReleaseRow(AuthorityCriterionCanonicalCodecV1.decode(SeverityScaleReleaseV1.self, from: record.canonicalData)))
                    case .findingClassificationBinding: context.insert(try FindingClassificationBindingRow(AuthorityCriterionCanonicalCodecV1.decode(FindingClassificationBindingV1.self, from: record.canonicalData)))
                    case .measurementProtocolRelease: context.insert(try MeasurementProtocolReleaseRow(AuthorityCriterionCanonicalCodecV1.decode(MeasurementProtocolReleaseV1.self, from: record.canonicalData)))
                    case .derivedFactEvaluatorDescriptor: context.insert(try DerivedFactEvaluatorDescriptorRow(AuthorityCriterionCanonicalCodecV1.decode(DerivedFactEvaluatorDescriptorV1.self, from: record.canonicalData)))
                    case .derivedFactProvenance: context.insert(try DerivedFactProvenanceRow(AuthorityCriterionCanonicalCodecV1.decode(DerivedFactProvenanceV1.self, from: record.canonicalData)))
                    }
                }
            } catch { throw BackupRestoreServiceError.invalidPackage }
        }
        if records.recordsSchemaVersion >= 11 {
            do {
                for record in records.functionalRelationships {
                    switch record.kind {
                    case .descriptor:
                        context.insert(try FunctionalRelationshipTypeDescriptorRow(
                            FunctionalRelationshipCanonicalCodecV1.decode(
                                FunctionalRelationshipTypeDescriptorV1.self,
                                from: record.canonicalData
                            )
                        ))
                    case .event:
                        context.insert(try AssetFunctionalRelationshipEventRow(
                            FunctionalRelationshipCanonicalCodecV1.decode(
                                AssetFunctionalRelationshipEventV1.self,
                                from: record.canonicalData
                            )
                        ))
                    }
                }
            } catch { throw BackupRestoreServiceError.invalidPackage }
        }
        if records.recordsSchemaVersion >= 12 {
            do {
                for record in records.evidenceAssurance {
                    switch record.kind {
                    case .visibility: context.insert(try EvidenceVisibilityRow(EvidenceAssuranceCanonicalCodecV1.decode(EvidenceVisibilityV1.self, from: record.canonicalData)))
                    case .evidenceLink: context.insert(try ClaimEvidenceLinkRow(EvidenceAssuranceCanonicalCodecV1.decode(ClaimEvidenceLinkV1.self, from: record.canonicalData)))
                    case .manifest: context.insert(try AssuranceManifestRow(EvidenceAssuranceCanonicalCodecV1.decode(AssuranceManifestV1.self, from: record.canonicalData)))
                    case .attestation: context.insert(try AttestationRow(EvidenceAssuranceCanonicalCodecV1.decode(AttestationV1.self, from: record.canonicalData)))
                    }
                }
            } catch { throw BackupRestoreServiceError.invalidPackage }
        }
        if records.recordsSchemaVersion >= 13 {
            do {
                for record in records.inspectionReview {
                    switch record.kind {
                    case .reviewTransition: context.insert(try InspectionReviewTransitionRow(InspectionReviewCanonicalCodecV1.decode(InspectionReviewTransitionV1.self, from: record.canonicalData)))
                    case .reviewDisposition: context.insert(try ReviewDispositionRow(InspectionReviewCanonicalCodecV1.decode(ReviewDispositionV1.self, from: record.canonicalData)))
                    case .changeRequest: context.insert(try ChangeRequestRow(InspectionReviewCanonicalCodecV1.decode(ChangeRequestV1.self, from: record.canonicalData)))
                    case .correctiveActionPolicy: context.insert(try CorrectiveActionPolicyRow(InspectionReviewCanonicalCodecV1.decode(CorrectiveActionPolicyV1.self, from: record.canonicalData)))
                    case .correctiveActionEvent: context.insert(try CorrectiveActionEventRow(InspectionReviewCanonicalCodecV1.decode(CorrectiveActionEventV1.self, from: record.canonicalData)))
                    }
                }
            } catch { throw BackupRestoreServiceError.invalidPackage }
        }
        if records.recordsSchemaVersion >= 14 {
            do {for record in records.workPackets {switch record.kind {
                case .manifest:context.insert(try WorkPacketManifestRow(WorkPacketCanonicalCodecV1.decode(WorkPacketManifestV1.self,from:record.canonicalData)))
                case .claim:context.insert(try WorkItemClaimRow(WorkPacketCanonicalCodecV1.decode(WorkItemClaimV1.self,from:record.canonicalData)))
                case .lease:context.insert(try WorkLeaseRow(WorkPacketCanonicalCodecV1.decode(WorkLeaseV1.self,from:record.canonicalData)))
                case .release:context.insert(try WorkReleaseRow(WorkPacketCanonicalCodecV1.decode(WorkReleaseV1.self,from:record.canonicalData)))
                case .handoff:context.insert(try WorkHandoffRow(WorkPacketCanonicalCodecV1.decode(WorkHandoffV1.self,from:record.canonicalData)))
            }}}catch{throw BackupRestoreServiceError.invalidPackage}
        }
        if records.recordsSchemaVersion >= 15 {
            do {
                for record in records.fieldDrafts {
                    switch record.kind {
                    case .checkpoint: context.insert(try FieldDraftCheckpointRow(FieldDraftCanonicalCodecV1.decode(FieldDraftCheckpointV1.self, from: record.canonicalData)))
                    case .stagingItem: context.insert(try AttachmentStagingItemRow(FieldDraftCanonicalCodecV1.decode(AttachmentStagingItemV1.self, from: record.canonicalData)))
                    case .commitSaga: context.insert(try DraftCommitSagaRow(FieldDraftCanonicalCodecV1.decode(DraftCommitSagaV1.self, from: record.canonicalData)))
                    case .contentReservation: context.insert(try DraftContentReservationRow(FieldDraftCanonicalCodecV1.decode(DraftContentReservationV1.self, from: record.canonicalData)))
                    case .commitReceipt: context.insert(try DraftCommitReceiptRow(FieldDraftCanonicalCodecV1.decode(DraftCommitReceiptV1.self, from: record.canonicalData)))
                    case .discardReceipt: context.insert(try DraftDiscardReceiptRow(FieldDraftCanonicalCodecV1.decode(DraftDiscardReceiptV1.self, from: record.canonicalData)))
                    }
                }
            } catch { throw BackupRestoreServiceError.invalidPackage }
        }
        if records.recordsSchemaVersion >= 16 {
            do {
                for record in records.packageEvolution {
                    switch record.kind {
                    case .promotedRelease: context.insert(try PromotedPackageReleaseRow(PackageEvolutionCanonicalCodecV1.decode(PromotedPackageReleaseV1.self, from: record.canonicalData)))
                    case .sandboxRun: context.insert(try PackageSandboxRunRow(PackageEvolutionCanonicalCodecV1.decode(PackageSandboxRunV1.self, from: record.canonicalData)))
                    case .promotionReceipt: context.insert(try PackagePromotionReceiptRow(PackageEvolutionCanonicalCodecV1.decode(PackagePromotionReceiptV1.self, from: record.canonicalData)))
                    case .activePointer: context.insert(try ActivePackageRegistryPointerRow(PackageEvolutionCanonicalCodecV1.decode(ActivePackageRegistryPointerV1.self, from: record.canonicalData)))
                    }
                }
            } catch { throw BackupRestoreServiceError.invalidPackage }
        }
        if records.recordsSchemaVersion >= 17 {
            do {
                for record in records.measurementIntegrity {
                    switch record.kind {
                    case .instrumentReference: context.insert(try InstrumentReferenceRow(MeasurementIntegrityCanonicalCodecV1.decode(InstrumentReferenceV1.self,from:record.canonicalData)))
                    case .calibrationSnapshot: context.insert(try CalibrationStatusSnapshotRow(MeasurementIntegrityCanonicalCodecV1.decode(CalibrationStatusSnapshotV1.self,from:record.canonicalData)))
                    case .measurementCapture: context.insert(try MeasurementCaptureRow(MeasurementIntegrityCanonicalCodecV1.decode(MeasurementCaptureV1.self,from:record.canonicalData)))
                    case .measurementSeries: context.insert(try MeasurementSeriesRow(MeasurementIntegrityCanonicalCodecV1.decode(MeasurementSeriesV1.self,from:record.canonicalData)))
                    case .qualityAssessment: context.insert(try MeasurementQualityAssessmentRow(MeasurementIntegrityCanonicalCodecV1.decode(MeasurementQualityAssessmentV1.self,from:record.canonicalData)))
                    }
                }
            } catch { throw BackupRestoreServiceError.invalidPackage }
        }
        if let mutationHistory = records.mutationHistory {
            guard records.recordsSchemaVersion == 3
                    || records.recordsSchemaVersion == 4
                    || records.recordsSchemaVersion == 5
                    || records.recordsSchemaVersion == 6
                    || records.recordsSchemaVersion == 7
                    || records.recordsSchemaVersion == 8
                    || records.recordsSchemaVersion == 9
                    || records.recordsSchemaVersion == 10
                    || records.recordsSchemaVersion == 11
                    || records.recordsSchemaVersion == 12
                    || records.recordsSchemaVersion == 13
                    || records.recordsSchemaVersion == 14
                    || records.recordsSchemaVersion == 15
                    || records.recordsSchemaVersion == 16
                    || records.recordsSchemaVersion == 17 else {
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
            var snapshotData = value.members[report.snapshotRelativePath]
            if let source = snapshotData,
               CanonicalJSONV1.sha256(source) != report.snapshotSHA256,
               let rawWorkspaceID = records.evidenceAssurance.first?.workspaceID {
                snapshotData = try reboundReportSnapshotData(
                    source,
                    workspaceID: WorkspaceID(rawValue: rawWorkspaceID)
                )
            }
            try writeExact(
                snapshotData,
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
            switch lifecycleRoute {
            case let .live(lifecycleDependencies):
                let coordinator = try StoreSessionCoordinator(
                    validatingSession: session,
                    clock: lifecycleDependencies.clock,
                    idSource: lifecycleDependencies.idSource,
                    fileAuthority: lifecycleDependencies.fileAuthority
                )
                let dependencies = try coordinator.packageLifecycleDependencies(
                    profileRegistry: lifecycleDependencies.profileRegistry
                )
                _ = try BackupExportService(
                    modelContext: session.modelContext,
                    generationRootURL: session.generationRootURL,
                    lifecycleDependencies: dependencies,
                    now: { Date(timeIntervalSince1970: 0) }
                ).prepareStreaming()
            case let .expiringCompatibility(posture):
                _ = try BackupExportService(
                    modelContext: session.modelContext,
                    generationRootURL: session.generationRootURL,
                    now: { Date(timeIntervalSince1970: 0) },
                    compatibilityPosture: posture
                ).prepareStreaming()
            }
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
        let actual = try records(in: context)
        if actual == expected { return }
        guard expected.recordsSchemaVersion < 9,
              (actual.recordsSchemaVersion == 9 || actual.recordsSchemaVersion == 10
                || actual.recordsSchemaVersion == 11
                || actual.recordsSchemaVersion == 12
                || actual.recordsSchemaVersion == 13
                || actual.recordsSchemaVersion == 14
                || actual.recordsSchemaVersion == 15
                || actual.recordsSchemaVersion == 16
                || actual.recordsSchemaVersion == 17) else {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
        if expected.recordsSchemaVersion == 5 || expected.recordsSchemaVersion == 6 {
            guard recordsByReplacingV7Fields(
                actual, schemaVersion: expected.recordsSchemaVersion
            ) == expected else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
        } else if try !validLegacyLocationMigration(actual, expected: expected) {
            throw BackupRestoreServiceError.invalidRestoreAuthority
        }
    }

    func recordsByReplacingV7Fields(
        _ records: V4BackupRecordsV1,
        schemaVersion: Int
    ) -> V4BackupRecordsV1 {
        V4BackupRecordsV1(
            measurementIntegrity: schemaVersion >= 17 ? records.measurementIntegrity : [],
            packageEvolution: schemaVersion >= 16 ? records.packageEvolution : [],
            fieldDrafts: schemaVersion >= 15 ? records.fieldDrafts : [],
            workPackets:schemaVersion>=14 ? records.workPackets:[],
            inspectionReview: schemaVersion >= 13 ? records.inspectionReview : [],
            evidenceAssurance: schemaVersion >= 12 ? records.evidenceAssurance : [],
            functionalRelationships: schemaVersion >= 11 ? records.functionalRelationships : [],
            authorityCriterion: schemaVersion >= 10 ? records.authorityCriterion : [],
            assetSemantics: schemaVersion >= 9 ? records.assetSemantics : [],
            assetCompositionEdges: records.assetCompositionEdges,
            assetCompositionEvents: records.assetCompositionEvents,
            assetPlacementEvents: records.assetPlacementEvents,
            assets: records.assets,
            deletionLedger: records.deletionLedger,
            evidenceFiles: records.evidenceFiles,
            issues: records.issues,
            locationHierarchyEvents: records.locationHierarchyEvents,
            locationMigrationReceipts: records.locationMigrationReceipts,
            locationNodes: records.locationNodes,
            mutationHistory: records.mutationHistory,
            packets: records.packets,
            partyAccountability: schemaVersion >= 8 ? records.partyAccountability : [],
            recordsSchemaVersion: schemaVersion,
            reports: records.reports,
            requirementAssurance: [],
            savedSmartViews: schemaVersion >= 6 ? records.savedSmartViews : [],
            sites: records.sites,
            workflowRecords: records.workflowRecords
        )
    }

    func validLegacyLocationMigration(
        _ actual: V4BackupRecordsV1,
        expected: V4BackupRecordsV1
    ) throws -> Bool {
        let predecessor = V4BackupRecordsV1(
            measurementIntegrity: expected.recordsSchemaVersion >= 17 ? expected.measurementIntegrity : [],
            packageEvolution: expected.recordsSchemaVersion >= 16 ? expected.packageEvolution : [],
            fieldDrafts: expected.recordsSchemaVersion >= 15 ? expected.fieldDrafts : [],
            workPackets:expected.recordsSchemaVersion>=14 ? expected.workPackets:[],
            inspectionReview: expected.recordsSchemaVersion >= 13 ? expected.inspectionReview : [],
            evidenceAssurance: expected.recordsSchemaVersion >= 12 ? expected.evidenceAssurance : [],
            functionalRelationships: expected.recordsSchemaVersion >= 11 ? expected.functionalRelationships : [],
            authorityCriterion: expected.recordsSchemaVersion >= 10 ? expected.authorityCriterion : [],
            assetSemantics: expected.recordsSchemaVersion >= 9 ? expected.assetSemantics : [],
            assets: actual.assets,
            deletionLedger: actual.deletionLedger,
            evidenceFiles: actual.evidenceFiles,
            issues: actual.issues,
            mutationHistory: actual.mutationHistory,
            packets: actual.packets,
            recordsSchemaVersion: expected.recordsSchemaVersion,
            reports: actual.reports,
            sites: actual.sites,
            workflowRecords: actual.workflowRecords
        )
        guard predecessor == expected,
              actual.locationNodes.isEmpty,
              actual.locationHierarchyEvents.isEmpty,
              actual.assetCompositionEdges.isEmpty,
              actual.assetCompositionEvents.isEmpty,
              actual.assetPlacementEvents.count == actual.assets.count,
              actual.locationMigrationReceipts.count == 1 else { return false }
        let assetIDs = Set(actual.assets.map(\.id))
        let events = try actual.assetPlacementEvents.map {
            try LocationPersistenceCodecV1.decode(
                AssetPlacementEventV1.self, from: $0.canonicalData
            )
        }
        let receipt = try LocationPersistenceCodecV1.decode(
            LocationMigrationReceiptV1.self,
            from: actual.locationMigrationReceipts[0].canonicalData
        )
        return Set(events.map(\.assetID)) == assetIDs
            && events.allSatisfy {
                $0.source == .migratedBaseline && $0.locationNodeID == nil
                    && $0.predecessorEventID == nil
            }
            && Set(receipt.bindings.map(\.assetID)) == assetIDs
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
        try records(
            in: context,
            includingDeletionLedger: true,
            includesObservationAndTime: true
        )
    }

    func records(
        in context: ModelContext,
        includingDeletionLedger: Bool,
        includesObservationAndTime: Bool
    ) throws -> V4BackupRecordsV1 {
        let sites = try context.fetch(FetchDescriptor<Site>())
        let assets = try context.fetch(FetchDescriptor<Asset>())
        let workflow = try context.fetch(FetchDescriptor<WorkflowRecord>())
        let evidence = try context.fetch(FetchDescriptor<EvidenceFile>())
        let issues = try context.fetch(FetchDescriptor<Issue>())
        let packets = try context.fetch(FetchDescriptor<Packet>())
        let reports = try context.fetch(FetchDescriptor<Report>())
        let requirementAssurance = try context.fetch(
            FetchDescriptor<RequirementAssuranceRow>()
        )
        let assetCompositionEdges = try context.fetch(FetchDescriptor<AssetCompositionEdgeRow>())
        let assetCompositionEvents = try context.fetch(FetchDescriptor<AssetCompositionEventRow>())
        let assetPlacementEvents = try context.fetch(FetchDescriptor<AssetPlacementEventRow>())
        let locationHierarchyEvents = try context.fetch(FetchDescriptor<LocationHierarchyEventRow>())
        let locationMigrationReceipts = try context.fetch(FetchDescriptor<LocationMigrationReceiptRow>())
        let locationNodes = try context.fetch(FetchDescriptor<LocationNodeRow>())
        let savedSmartViews = try context.fetch(FetchDescriptor<SavedSmartViewRowV1>())
        let serviceParties = try context.fetch(FetchDescriptor<ServicePartyRow>())
        let sitePartyRoles = try context.fetch(FetchDescriptor<SitePartyRoleEventRow>())
        let actorSnapshots = try context.fetch(FetchDescriptor<ActorSnapshotRow>())
        let qualificationSnapshots = try context.fetch(FetchDescriptor<QualificationSnapshotRow>())
        let signoffSnapshots = try context.fetch(FetchDescriptor<SignoffSnapshotRow>())
        let assetKindBindingEvents = try context.fetch(FetchDescriptor<AssetKindBindingEventRow>())
        let assetWorkflowCapabilityBindingEvents = try context.fetch(FetchDescriptor<AssetWorkflowCapabilityBindingEventRow>())
        let assetProductIdentities = try context.fetch(FetchDescriptor<AssetProductIdentityRow>())
        let assetLifecycleEvents = try context.fetch(FetchDescriptor<AssetLifecycleEventRow>())
        let assetSuccessorLinks = try context.fetch(FetchDescriptor<AssetSuccessorLinkRow>())
        let workSubjectScopeSnapshots = try context.fetch(FetchDescriptor<WorkSubjectScopeSnapshotRow>())
        let authoritySourceReleases = try context.fetch(FetchDescriptor<AuthoritySourceReleaseRow>())
        let requirementBasisBindings = try context.fetch(FetchDescriptor<RequirementBasisBindingRow>())
        let applicabilityContexts = try context.fetch(FetchDescriptor<ApplicabilityContextSnapshotRow>())
        let assessmentScopes = try context.fetch(FetchDescriptor<AssessmentScopeSnapshotRow>())
        let severityScales = try context.fetch(FetchDescriptor<SeverityScaleReleaseRow>())
        let classifications = try context.fetch(FetchDescriptor<FindingClassificationBindingRow>())
        let measurementProtocols = try context.fetch(FetchDescriptor<MeasurementProtocolReleaseRow>())
        let evaluators = try context.fetch(FetchDescriptor<DerivedFactEvaluatorDescriptorRow>())
        let derivedFacts = try context.fetch(FetchDescriptor<DerivedFactProvenanceRow>())
        let inspectionReviewTransitions = try context.fetch(FetchDescriptor<InspectionReviewTransitionRow>())
        let reviewDispositions = try context.fetch(FetchDescriptor<ReviewDispositionRow>())
        let changeRequests = try context.fetch(FetchDescriptor<ChangeRequestRow>())
        let correctiveActionPolicies = try context.fetch(FetchDescriptor<CorrectiveActionPolicyRow>())
        let correctiveActionEvents = try context.fetch(FetchDescriptor<CorrectiveActionEventRow>())
        let fieldDraftCheckpoints = try context.fetch(FetchDescriptor<FieldDraftCheckpointRow>())
        let attachmentStagingItems = try context.fetch(FetchDescriptor<AttachmentStagingItemRow>())
        let draftCommitSagas = try context.fetch(FetchDescriptor<DraftCommitSagaRow>())
        let draftContentReservations = try context.fetch(FetchDescriptor<DraftContentReservationRow>())
        let draftCommitReceipts = try context.fetch(FetchDescriptor<DraftCommitReceiptRow>())
        let draftDiscardReceipts = try context.fetch(FetchDescriptor<DraftDiscardReceiptRow>())
        let promotedPackageReleases = try context.fetch(FetchDescriptor<PromotedPackageReleaseRow>())
        let packageSandboxRuns = try context.fetch(FetchDescriptor<PackageSandboxRunRow>())
        let packagePromotionReceipts = try context.fetch(FetchDescriptor<PackagePromotionReceiptRow>())
        let activePackageRegistryPointers = try context.fetch(FetchDescriptor<ActivePackageRegistryPointerRow>())
        let instrumentReferences=try context.fetch(FetchDescriptor<InstrumentReferenceRow>()),calibrationStatusSnapshots=try context.fetch(FetchDescriptor<CalibrationStatusSnapshotRow>()),measurementCaptures=try context.fetch(FetchDescriptor<MeasurementCaptureRow>()),measurementSeries=try context.fetch(FetchDescriptor<MeasurementSeriesRow>()),measurementQualityAssessments=try context.fetch(FetchDescriptor<MeasurementQualityAssessmentRow>())
        let workPacketManifests=try context.fetch(FetchDescriptor<WorkPacketManifestRow>()),workItemClaims=try context.fetch(FetchDescriptor<WorkItemClaimRow>()),workLeases=try context.fetch(FetchDescriptor<WorkLeaseRow>()),workReleases=try context.fetch(FetchDescriptor<WorkReleaseRow>()),workHandoffs=try context.fetch(FetchDescriptor<WorkHandoffRow>())
        let evidenceVisibilities = try context.fetch(FetchDescriptor<EvidenceVisibilityRow>())
        let claimEvidenceLinks = try context.fetch(FetchDescriptor<ClaimEvidenceLinkRow>())
        let assuranceManifests = try context.fetch(FetchDescriptor<AssuranceManifestRow>())
        let attestations = try context.fetch(FetchDescriptor<AttestationRow>())
        let functionalRelationshipDescriptors = try context.fetch(
            FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>()
        )
        let functionalRelationshipEvents = try context.fetch(
            FetchDescriptor<AssetFunctionalRelationshipEventRow>()
        )
        let observationAndTime: [UUID: ObservationAndTimeRow]
        if includesObservationAndTime {
            observationAndTime = try ObservationAndTimeRowStoreV1.validatedIndex(
                in: context
            )
        } else {
            observationAndTime = [:]
        }
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
            measurementIntegrity: try (
                instrumentReferences.map{let v=try $0.value();return V18BackupMeasurementIntegrityRecordV1(kind:.instrumentReference,id:v.referenceID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:$0.canonicalData)}
                + calibrationStatusSnapshots.map{let v=try $0.value();return V18BackupMeasurementIntegrityRecordV1(kind:.calibrationSnapshot,id:v.snapshotID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:$0.canonicalData)}
                + measurementCaptures.map{let v=try $0.value();return V18BackupMeasurementIntegrityRecordV1(kind:.measurementCapture,id:v.captureID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:$0.canonicalData)}
                + measurementSeries.map{let v=try $0.value();return V18BackupMeasurementIntegrityRecordV1(kind:.measurementSeries,id:v.snapshotID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:$0.canonicalData)}
                + measurementQualityAssessments.map{let v=try $0.value();return V18BackupMeasurementIntegrityRecordV1(kind:.qualityAssessment,id:v.assessmentID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:$0.canonicalData)}
            ).sorted{"\($0.kind.rawValue)\u{0}\($0.id.uuidString)"<"\($1.kind.rawValue)\u{0}\($1.id.uuidString)"},
            packageEvolution: try (
                promotedPackageReleases.map { let v=try $0.value(); return .init(kind:.promotedRelease,id:v.releaseRecordID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:$0.canonicalData) }
                + packageSandboxRuns.map { let v=try $0.value(); return .init(kind:.sandboxRun,id:v.runID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:$0.canonicalData) }
                + packagePromotionReceipts.map { let v=try $0.value(); return .init(kind:.promotionReceipt,id:v.receiptID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:$0.canonicalData) }
                + activePackageRegistryPointers.map { let v=try $0.value(); return .init(kind:.activePointer,id:v.pointerID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:$0.canonicalData) }
            ).sorted { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" < "\($1.kind.rawValue)\u{0}\($1.id.uuidString)" },
            fieldDrafts: try (
                fieldDraftCheckpoints.map { let v=try $0.value(); return .init(kind:.checkpoint,id:v.draftID,workspaceID:v.workspaceID.rawValue,revision:v.draftRevision,canonicalData:try FieldDraftCanonicalCodecV1.encode(v)) }
                + attachmentStagingItems.map { let v=try $0.value(); return .init(kind:.stagingItem,id:v.stageID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:try FieldDraftCanonicalCodecV1.encode(v)) }
                + draftCommitSagas.map { let v=try $0.value(); return .init(kind:.commitSaga,id:v.sagaID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:try FieldDraftCanonicalCodecV1.encode(v)) }
                + draftContentReservations.map { let v=try $0.value(); return .init(kind:.contentReservation,id:v.reservationID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:try FieldDraftCanonicalCodecV1.encode(v)) }
                + draftCommitReceipts.map { let v=try $0.value(); return .init(kind:.commitReceipt,id:v.receiptID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:try FieldDraftCanonicalCodecV1.encode(v)) }
                + draftDiscardReceipts.map { let v=try $0.value(); return .init(kind:.discardReceipt,id:v.receiptID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:try FieldDraftCanonicalCodecV1.encode(v)) }
            ).sorted { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" < "\($1.kind.rawValue)\u{0}\($1.id.uuidString)" },
            workPackets:try(workPacketManifests.map{let v=try $0.value();return .init(kind:.manifest,id:v.manifestID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:$0.canonicalData)}+workItemClaims.map{let v=try $0.value();return .init(kind:.claim,id:v.claimID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:$0.canonicalData)}+workLeases.map{let v=try $0.value();return .init(kind:.lease,id:v.leaseID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:$0.canonicalData)}+workReleases.map{let v=try $0.value();return .init(kind:.release,id:v.releaseID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:$0.canonicalData)}+workHandoffs.map{let v=try $0.value();return .init(kind:.handoff,id:v.handoffID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:$0.canonicalData)}).sorted{"\($0.kind.rawValue)\u{0}\($0.id.uuidString)"<"\($1.kind.rawValue)\u{0}\($1.id.uuidString)"},
            inspectionReview: try (
                inspectionReviewTransitions.map { let v=try $0.value(); return .init(kind:.reviewTransition,id:v.transitionID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:$0.canonicalData) }
                + reviewDispositions.map { let v=try $0.value(); return .init(kind:.reviewDisposition,id:v.dispositionID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:$0.canonicalData) }
                + changeRequests.map { let v=try $0.value(); return .init(kind:.changeRequest,id:v.requestRevisionID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:$0.canonicalData) }
                + correctiveActionPolicies.map { let v=try $0.value(); return .init(kind:.correctiveActionPolicy,id:v.releaseID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:$0.canonicalData) }
                + correctiveActionEvents.map { let v=try $0.value(); return .init(kind:.correctiveActionEvent,id:v.eventID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:$0.canonicalData) }
            ).sorted { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" < "\($1.kind.rawValue)\u{0}\($1.id.uuidString)" },
            evidenceAssurance: try (
                evidenceVisibilities.map { let v=try $0.value(); return .init(kind:.visibility,id:v.visibilityID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:$0.canonicalData) }
                + claimEvidenceLinks.map { let v=try $0.value(); return .init(kind:.evidenceLink,id:v.linkID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:$0.canonicalData) }
                + assuranceManifests.map { let v=try $0.value(); return .init(kind:.manifest,id:v.manifestID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:$0.canonicalData) }
                + attestations.map { let v=try $0.value(); return .init(kind:.attestation,id:v.attestationID,workspaceID:v.workspaceID.rawValue,revision:v.revision,canonicalData:$0.canonicalData) }
            ).sorted { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" < "\($1.kind.rawValue)\u{0}\($1.id.uuidString)" },
            functionalRelationships: try (
                functionalRelationshipDescriptors.map {
                    let value = try $0.value()
                    return .init(kind: .descriptor, id: value.descriptorReleaseID,
                                 workspaceID: value.workspaceID.rawValue,
                                 revision: value.revision, canonicalData: $0.canonicalData)
                } + functionalRelationshipEvents.map {
                    let value = try $0.value()
                    return .init(kind: .event, id: value.eventID,
                                 workspaceID: value.workspaceID.rawValue,
                                 revision: value.revision, canonicalData: $0.canonicalData)
                }
            ).sorted {
                "\($0.kind.rawValue)\u{0}\($0.id.uuidString)"
                    < "\($1.kind.rawValue)\u{0}\($1.id.uuidString)"
            },
            authorityCriterion: try (
                authoritySourceReleases.map { let v=try $0.value(); return .init(kind: .authoritySourceRelease,id:v.releaseID,workspaceID:v.workspaceID.rawValue,canonicalData:$0.canonicalData) }
                + requirementBasisBindings.map { let v=try $0.value(); return .init(kind:.requirementBasisBinding,id:v.bindingID,workspaceID:v.workspaceID.rawValue,canonicalData:$0.canonicalData) }
                + applicabilityContexts.map { let v=try $0.value(); return .init(kind:.applicabilityContextSnapshot,id:v.snapshotID,workspaceID:v.workspaceID.rawValue,canonicalData:$0.canonicalData) }
                + assessmentScopes.map { let v=try $0.value(); return .init(kind:.assessmentScopeSnapshot,id:v.snapshotID,workspaceID:v.workspaceID.rawValue,canonicalData:$0.canonicalData) }
                + severityScales.map { let v=try $0.value(); return .init(kind:.severityScaleRelease,id:v.releaseID,workspaceID:v.workspaceID.rawValue,canonicalData:$0.canonicalData) }
                + classifications.map { let v=try $0.value(); return .init(kind:.findingClassificationBinding,id:v.bindingID,workspaceID:v.workspaceID.rawValue,canonicalData:$0.canonicalData) }
                + measurementProtocols.map { let v=try $0.value(); return .init(kind:.measurementProtocolRelease,id:v.releaseID,workspaceID:v.workspaceID.rawValue,canonicalData:$0.canonicalData) }
                + evaluators.map { let v=try $0.value(); return .init(kind:.derivedFactEvaluatorDescriptor,id:v.descriptorID,workspaceID:v.workspaceID.rawValue,canonicalData:$0.canonicalData) }
                + derivedFacts.map { let v=try $0.value(); return .init(kind:.derivedFactProvenance,id:v.provenanceID,workspaceID:v.workspaceID.rawValue,canonicalData:$0.canonicalData) }
            ).sorted { "\($0.kind.rawValue)\u{0}\($0.id.uuidString)" < "\($1.kind.rawValue)\u{0}\($1.id.uuidString)" },
            assetSemantics: try (
                assetKindBindingEvents.map {
                    let value = try $0.value()
                    return .init(kind: .kindBindingEvent, id: value.eventID,
                                 workspaceID: value.workspaceID.rawValue,
                                 revision: value.revision, canonicalData: $0.canonicalData)
                } + assetWorkflowCapabilityBindingEvents.map {
                    let value = try $0.value()
                    return .init(kind: .workflowCapabilityBindingEvent, id: value.eventID,
                                 workspaceID: value.workspaceID.rawValue,
                                 revision: value.revision, canonicalData: $0.canonicalData)
                } + assetProductIdentities.map {
                    let value = try $0.value()
                    return .init(kind: .productIdentity, id: value.identityID,
                                 workspaceID: value.workspaceID.rawValue,
                                 revision: value.revision, canonicalData: $0.canonicalData)
                } + assetLifecycleEvents.map {
                    let value = try $0.value()
                    return .init(kind: .lifecycleEvent, id: value.record.eventID,
                                 workspaceID: value.record.workspaceID.rawValue,
                                 revision: value.record.revision, canonicalData: $0.canonicalData)
                } + assetSuccessorLinks.map {
                    let value = try $0.value()
                    return .init(kind: .successorLink, id: value.linkID,
                                 workspaceID: value.workspaceID.rawValue,
                                 revision: value.revision, canonicalData: $0.canonicalData)
                } + workSubjectScopeSnapshots.map {
                    let value = try $0.value()
                    return .init(kind: .workSubjectScopeSnapshot, id: value.snapshotID,
                                 workspaceID: value.workspaceID.rawValue,
                                 revision: value.workspaceRevision, canonicalData: $0.canonicalData)
                }
            ).sorted {
                "\($0.kind.rawValue)\u{0}\($0.id.uuidString)"
                    < "\($1.kind.rawValue)\u{0}\($1.id.uuidString)"
            },
            assetCompositionEdges: assetCompositionEdges.map {
                .init(id: $0.id, canonicalData: $0.canonicalData)
            }.sorted { canonical($0.id) < canonical($1.id) },
            assetCompositionEvents: assetCompositionEvents.map {
                .init(id: $0.id, canonicalData: $0.canonicalData)
            }.sorted { canonical($0.id) < canonical($1.id) },
            assetPlacementEvents: assetPlacementEvents.map {
                .init(id: $0.id, canonicalData: $0.canonicalData)
            }.sorted { canonical($0.id) < canonical($1.id) },
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
            locationHierarchyEvents: locationHierarchyEvents.map {
                .init(
                    id: $0.operationID,
                    canonicalData: $0.planData,
                    secondaryCanonicalData: $0.receiptData
                )
            }.sorted { canonical($0.id) < canonical($1.id) },
            locationMigrationReceipts: locationMigrationReceipts.map {
                .init(id: $0.candidateGenerationID, canonicalData: $0.canonicalData)
            }.sorted { canonical($0.id) < canonical($1.id) },
            locationNodes: locationNodes.map {
                .init(id: $0.id, canonicalData: $0.canonicalData)
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
            partyAccountability: try (
                serviceParties.map {
                    let value = try $0.value()
                    return .init(kind: .serviceParty, id: value.partyID,
                                 workspaceID: value.workspaceID.rawValue,
                                 revision: value.revision, canonicalData: $0.canonicalData)
                } + sitePartyRoles.map {
                    let value = try $0.value()
                    return .init(kind: .sitePartyRoleEvent, id: value.eventID,
                                 workspaceID: value.workspaceID.rawValue,
                                 revision: value.revision, canonicalData: $0.canonicalData)
                } + actorSnapshots.map {
                    let value = try $0.value()
                    return .init(kind: .actorSnapshot, id: value.snapshotID,
                                 workspaceID: value.workspaceID.rawValue,
                                 revision: nil, canonicalData: $0.canonicalData)
                } + qualificationSnapshots.map {
                    let value = try $0.value()
                    return .init(kind: .qualificationSnapshot, id: value.snapshotID,
                                 workspaceID: value.workspaceID.rawValue,
                                 revision: nil, canonicalData: $0.canonicalData)
                } + signoffSnapshots.map {
                    let value = try $0.value()
                    return .init(kind: .signoffSnapshot, id: value.snapshotID,
                                 workspaceID: value.workspaceID.rawValue,
                                 revision: value.subjectRevision, canonicalData: $0.canonicalData)
                }
            ).sorted {
                "\($0.kind.rawValue)\u{0}\($0.id.uuidString)"
                    < "\($1.kind.rawValue)\u{0}\($1.id.uuidString)"
            },
            recordsSchemaVersion: !(promotedPackageReleases.isEmpty && packageSandboxRuns.isEmpty
                && packagePromotionReceipts.isEmpty && activePackageRegistryPointers.isEmpty) ? 16
                : !(fieldDraftCheckpoints.isEmpty && attachmentStagingItems.isEmpty
                    && draftCommitSagas.isEmpty && draftContentReservations.isEmpty
                    && draftCommitReceipts.isEmpty && draftDiscardReceipts.isEmpty) ? 15
                : workPacketManifests.isEmpty && workItemClaims.isEmpty && workLeases.isEmpty && workReleases.isEmpty && workHandoffs.isEmpty
                ? (inspectionReviewTransitions.isEmpty && reviewDispositions.isEmpty
                    && changeRequests.isEmpty && correctiveActionPolicies.isEmpty
                    && correctiveActionEvents.isEmpty
                ? (evidenceVisibilities.isEmpty && claimEvidenceLinks.isEmpty
                    && assuranceManifests.isEmpty && attestations.isEmpty
                ? (functionalRelationshipDescriptors.isEmpty
                    && functionalRelationshipEvents.isEmpty
                ? (authoritySourceReleases.isEmpty
                    && requirementBasisBindings.isEmpty
                    && applicabilityContexts.isEmpty
                    && assessmentScopes.isEmpty
                    && severityScales.isEmpty
                    && classifications.isEmpty
                    && measurementProtocols.isEmpty
                    && evaluators.isEmpty
                    && derivedFacts.isEmpty
                    ? (mutationHistory == nil ? (includingDeletionLedger ? 2 : 1) : 9)
                    : 10)
                    : 11)
                : 12)
                : 13)
                : 14,
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
            requirementAssurance: try (mutationHistory == nil ? []
                : requirementAssurance.map(V8BackupRequirementAssuranceRecordV1.init))
                .sorted { canonical($0.workflowRecordID) < canonical($1.workflowRecordID) },
            savedSmartViews: try savedSmartViews.map {
                try V7BackupSavedSmartViewRecordV1($0.descriptor())
            }.sorted { canonical($0.id) < canonical($1.id) },
            sites: sites.map {
                .init(
                    id: $0.id, schemaVersion: $0.schemaVersion,
                    label: $0.label, address: $0.address,
                    timeZoneID: $0.timeZoneID, createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }.sorted { canonical($0.id) < canonical($1.id) },
            workflowRecords: try workflow.map { record in
                guard includesObservationAndTime else {
                    return workflowDTO(record)
                }
                guard let companion = observationAndTime[record.id] else {
                    throw BackupRestoreServiceError.invalidRestoreAuthority
                }
                return workflowDTO(record, observationAndTime: companion)
            }.sorted { canonical($0.id) < canonical($1.id) }
        )
    }

    func workflowDTO(
        _ value: WorkflowRecord,
        observationAndTime: ObservationAndTimeRow
    ) -> V4BackupWorkflowRecordDTO {
        workflowDTO(value).replacingObservationAndTime(
            basisData: observationAndTime.observationBasisV1Data,
            temporalData: observationAndTime.temporalContextV1Data
        )
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
        let restoreRoot = applicationSupportURL.appendingPathComponent(
            "FieldEvidenceRestore",
            isDirectory: true
        )
        for url in try fileManager.contentsOfDirectory(
            at: restoreRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            let name = url.lastPathComponent
            guard name.hasPrefix("draft-publication-"),
                  name.hasSuffix(".json") else { continue }
            let start = name.index(
                name.startIndex,
                offsetBy: "draft-publication-".count
            )
            let end = name.index(name.endIndex, offsetBy: -".json".count)
            let rawID = String(name[start..<end])
            guard let id = UUID(uuidString: rawID), canonical(id) == rawID else {
                throw BackupRestoreServiceError.invalidRestoreAuthority
            }
            try ProtectedFilePolicyV1.verify(.stagingFile, at: url)
            try fileManager.removeItem(at: url)
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

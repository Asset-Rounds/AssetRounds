import CryptoKit
import Darwin
import Foundation

enum C50IncumbentFileExchangeOrphanCleanupBoundaryV1 {
    static let excludesSceneRouteState = C34SceneNavigationCompatibilityBoundaryV1.validate()
    static let terminalSourceScratchIsRemovable = true
    static let terminalQuarantineIsRemovable = true
    static let liveLeaseBlocksCleanup = true
    static let externalSourceAndExportFilesAreNeverCleanupTargets = true
    static let canonicalImportedRowsAreNeverOrphanFiles = true
}

enum SurveySessionOrphanCleanupEnrollmentV1{static let surveyRowsOwnNoExternalFiles=true;static let cleanupMustNotInventPromotionOrPublication=true}

enum C30EvidenceContextOrphanCleanupPolicyV1 {
    static let contextRowsOwnNoExternalFiles = true
    static let canonicalRowsAreProtected = true
    static let derivedProjectionMayRebuild = true
    static let unknownContextBytesAreRemovable = false

    static func protectedIDs(contexts: [EvidenceContextV1],
                             links: [PairedObservationLinkV1]) throws -> Set<UUID> {
        try contexts.forEach { try $0.validateIntrinsic() }
        try links.forEach { try $0.validateIntrinsic() }
        guard contextRowsOwnNoExternalFiles, canonicalRowsAreProtected,
              derivedProjectionMayRebuild, !unknownContextBytesAreRemovable else {
            throw EvidenceContextFailureV1.invalidValue
        }
        return Set(contexts.map(\.contextID) + links.map(\.linkID))
    }
}

enum C49WorkResourceOrphanCleanupBoundaryV1 {
    static let ownsNoWorkResourceFiles = true
    static let localPartSnapshotIsEmbeddedData = true
    static let directCostIsEmbeddedData = true
}

enum C31LightingOrphanCleanupBoundaryV1 {
    static let canonicalRowsMustExistBeforeOwnedBytesRemoval = true
    static let unknownLightingRootsAreRejected = true
    static let derivedIndexesMayBeRebuilt = true

    static func validate(
        records: [V31BackupLightingRecordV1],
        workspaceID: WorkspaceID
    ) throws {
        try LightingBackupRecordSetV1.decode(records)
        let roots = try LightingBackupRecordSetV1.decode(records)
        let workspaces = roots.systems.map(\.workspaceID)
            + roots.observations.map(\.workspaceID)
            + roots.issues.map(\.workspaceID)
            + roots.plans.map(\.workspaceID)
            + roots.claims.map(\.workspaceID)
        guard workspaces.allSatisfy({ $0 == workspaceID }),
              canonicalRowsMustExistBeforeOwnedBytesRemoval,
              unknownLightingRootsAreRejected,
              derivedIndexesMayBeRebuilt else {
            throw LightingContractFailureV1.wrongWorkspace
        }
    }
}

struct OrphanFileCleanupSummary: Equatable, Sendable {
    let inspectedFileCount: Int
    let removedFileCount: Int
    let removedByteCount: Int64
    let removedDirectoryCount: Int
}

enum OrphanFileCleanupServiceError: Error, Equatable, Sendable {
    case invalidGeneration
    case invalidReference
    case inventoryLimitExceeded
    case byteLimitExceeded
    case invalidOwnedLayout
    case identityChanged
    case cleanupFailed
    case nonterminalDraftContent
}

enum FieldReferenceOrphanCleanupPolicyV1{static func removableReleaseIDs(releases:[FieldReferenceReleaseV1],bindings:[FieldReferenceBindingV1])->Set<UUID>{Set(releases.map(\.releaseID)).subtracting(Set(bindings.map(\.releaseID)))};static func protectedContentIDs(releases:[FieldReferenceReleaseV1],bindings:[FieldReferenceBindingV1])->Set<String>{let retained=Set(bindings.map(\.releaseID));return Set(releases.filter{retained.contains($0.releaseID)}.flatMap{$0.manifest.entries.map(\.contentID)})}}
enum AccessibleDocumentOrphanCleanupPolicyV1{static func protectedOutputDigests(_ receipts:[AccessibleDocumentAssessmentReceiptV1])->Set<String>{Set(receipts.map(\.outputSHA256))};static func mayRemove(outputSHA256:String,receipts:[AccessibleDocumentAssessmentReceiptV1],hasAuthorizedExpiryTombstoneAndRedactionProof:Bool)->Bool{hasAuthorizedExpiryTombstoneAndRedactionProof && !protectedOutputDigests(receipts).contains(outputSHA256)}}

/// Orphan cleanup removes only owned derivative bytes after its incumbent
/// retention closure proves them unreferenced. It never infers removal of an
/// append-only C05 association or sequence row from a missing file.
enum EvidenceMetadataOrphanCleanupPolicyV1 {
    static let ownedDerivativeRoot = "content"
    static let removesOnlyUnreferencedOwnedDerivativeBytes = true
    static let preservesAssociationAndSequencePredecessors = true
    static let missingDerivativeBytesNeverDeleteMetadataRows = true
    static let workspaceEraseOwnsFinalRowAndContentClear = true

    static func validate() throws {
        try EvidenceMetadataKernelDeletionEraseEnrollmentV1.validate()
        guard ownedDerivativeRoot == "content",
              removesOnlyUnreferencedOwnedDerivativeBytes,
              preservesAssociationAndSequencePredecessors,
              missingDerivativeBytesNeverDeleteMetadataRows,
              workspaceEraseOwnsFinalRowAndContentClear else {
            throw OrphanFileCleanupServiceError.invalidOwnedLayout
        }
    }
}
/// Asset-locator rows are canonical lookup/receipt state, not file-owned
/// payloads. Orphan maintenance may never infer a row deletion from a missing
/// file; callers must provide the complete immutable locator/receipt closure.
enum AssetLocatorOrphanCleanupPolicyV1 {
    static let locatorRowsOwnNoFilesystemPayload = true
    static let bindingReceiptsRequireReferencedLocators = true
    static let privateKeyMaterialIsNeverExportedOrCleaned = true
    static let maximumValues = 200_000

    static func validate(
        locators: [AssetLocatorV1],
        receipts: [LocatorBindingReceiptV1]
    ) throws {
        guard locatorRowsOwnNoFilesystemPayload,
              bindingReceiptsRequireReferencedLocators,
              privateKeyMaterialIsNeverExportedOrCleaned,
              locators.count <= maximumValues,
              receipts.count <= maximumValues,
              Set(locators.map(\.locatorID)).count == locators.count,
              Set(receipts.map(\.receiptID)).count == receipts.count else {
            throw OrphanFileCleanupServiceError.invalidOwnedLayout
        }
        do {
            try AssetLocatorLifecycleClosureV1(
                locators: locators,
                receipts: receipts
            ).validate()
        } catch {
            throw OrphanFileCleanupServiceError.invalidOwnedLayout
        }
    }
}
enum SurveyTemplateOrphanCleanupPolicyV1 {
    /// Import archives are staging-only. Cleanup may remove only a quarantined
    /// archive that was never admitted as either canonical survey family.
    static func mayRemove(
        filename: String,
        isInsideQuarantineRoot: Bool,
        admittedReleaseSHA256: String?
    ) -> Bool {
        isInsideQuarantineRoot
            && filename.lowercased().hasSuffix(".arsurveytemplate")
            && admittedReleaseSHA256 == nil
    }
}

/// Schedule releases and occurrence history own no filesystem payload. Their
/// due/reminder projections are disposable and must be rebuilt from the
/// durable closure; a missing file can therefore never justify deleting a
/// schedule row or history event.
enum ScheduleOrphanCleanupPolicyV1 {
    static let rowsOwnNoFilesystemPayload = true
    static let projectionsAreDerived = true
    static let missingFileCannotDeleteCanonicalRows = true
    static let missingFileCannotPruneEmbeddedCalendarOverrideOrBasisClosure = true
    static let notificationStateIsTruth = false

    static func validate() throws {
        guard rowsOwnNoFilesystemPayload,
              projectionsAreDerived,
              missingFileCannotDeleteCanonicalRows,
              missingFileCannotPruneEmbeddedCalendarOverrideOrBasisClosure,
              !notificationStateIsTruth else {
            throw OrphanFileCleanupServiceError.invalidOwnedLayout
        }
    }
}

/// Plan rows do not own files. Orphan cleanup may remove only unreferenced
/// content bytes and derived previews; a missing plan-related file can never
/// authorize deletion of an immutable document, revision, placement, frame,
/// or rebase receipt row.
enum PlanOrphanCleanupPolicyV1 {
    static let rowsOwnNoFilesystemPayload = true
    static let previewsAndRegistriesAreDerived = true
    static let missingFileCannotDeleteCanonicalRows = true
    static let immutableHistoryPreserved = true

    static func validate() throws {
        guard rowsOwnNoFilesystemPayload,
              previewsAndRegistriesAreDerived,
              missingFileCannotDeleteCanonicalRows,
              immutableHistoryPreserved,
              PlanPersistenceEnrollmentV1.durableModelCount == 4,
              V28BackupPlanRecordV1.Kind.allCases.count == 5 else {
            throw OrphanFileCleanupServiceError.invalidOwnedLayout
        }
        try PlanDeletionLedgerPolicyV1.validate()
    }
}

/// Pose events and anchor observations are SwiftData rows, not file-owned
/// payloads. Orphan maintenance can remove only derived projection files; a
/// missing file must never authorize removal of either immutable history row.
enum PlacementPoseOrphanCleanupPolicyV1 {
    static let rowsOwnNoFilesystemPayload = true
    static let derivedProjectionsAreRebuilt = true
    static let missingFileCannotDeleteCanonicalRows = true
    static let durableFamilyCount = 2

    static func validate() throws {
        guard rowsOwnNoFilesystemPayload,
              derivedProjectionsAreRebuilt,
              missingFileCannotDeleteCanonicalRows,
              durableFamilyCount == PlacementPosePersistenceEnrollmentV1.durableModelCount else {
            throw OrphanFileCleanupServiceError.invalidOwnedLayout
        }
        try PlacementPoseDeletionLedgerPolicyV1.validate()
    }
}

struct FieldDraftOrphanCleanupProofV1: Equatable, Sendable {
    let removableStageIDs: [UUID]
    let removableReservationIDs: [UUID]
}

/// Closed, revision-bound retention proof assembled by the canonical deletion
/// service.  File cleanup receives this single proof instead of independently
/// optional caller arrays, so omitting one owner class cannot authorize byte
/// removal.
struct TemporalEvidenceLiveReferenceClosureV1: Equatable, Sendable {
    let boundRevision: WorkspaceRevisionV1
    let liveClipContentIDs: Set<String>
    let liveJournalContentIDs: Set<String>
    let liveReportContentIDs: Set<String>
    let reservedContentIDs: Set<String>
    let recoveryContentIDs: Set<String>

    func validate(workspaceID: WorkspaceID) throws {
        let all = liveClipContentIDs
            .union(liveJournalContentIDs)
            .union(liveReportContentIDs)
            .union(reservedContentIDs)
            .union(recoveryContentIDs)
        guard boundRevision.workspaceID == workspaceID,
              all.allSatisfy(ContentContractValidationV1.validID) else {
            throw OrphanFileCleanupServiceError.invalidReference
        }
    }
}

final class OrphanFileCleanupReplacementInjection {
    private let lock = NSLock()
    private var operation: ((URL) throws -> Void)?

    init(runOnce operation: @escaping (URL) throws -> Void) {
        self.operation = operation
    }

    fileprivate func runIfPresent(at url: URL) throws {
        lock.lock()
        let current = operation
        operation = nil
        lock.unlock()
        try current?(url)
    }
}

/// Removes only unreferenced files from the three durable, row-owned content
/// roots. This type deliberately has no database or deletion-ledger handle:
/// callers provide a complete referenced-path projection and tombstones remain
/// outside this file-only authority boundary.
final class OrphanFileCleanupService {
    static let maximumEntriesPerRoot = 100_000
    static let maximumInspectedBytes: Int64 = 16 * 1_024 * 1_024 * 1_024

    private let generationRootURL: URL
    private let generationID: UUID
    private let rootIdentity: Identity
    private let fileManager: FileManager
    private let replacementInjection: OrphanFileCleanupReplacementInjection?
    #if DEBUG
    private var temporalRemovalBoundary: (@MainActor (TemporalUncommittedOriginalRemovalBoundaryV1, URL) throws -> Void)?
    #endif

    init(
        generationRootURL: URL,
        fileManager: FileManager = .default,
        replacementInjection: OrphanFileCleanupReplacementInjection? = nil
    ) throws {
        let root = generationRootURL.standardizedFileURL
        let generations = root.deletingLastPathComponent()
        let data = generations.deletingLastPathComponent()
        guard root.isFileURL,
              generations.lastPathComponent == "generations",
              data.lastPathComponent == "FieldEvidenceData",
              let generationID = UUID(uuidString: root.lastPathComponent),
              generationID.uuidString.lowercased() == root.lastPathComponent else {
            throw OrphanFileCleanupServiceError.invalidGeneration
        }
        let descriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw OrphanFileCleanupServiceError.invalidGeneration
        }
        defer { Darwin.close(descriptor) }
        self.generationRootURL = root
        self.generationID = generationID
        self.fileManager = fileManager
        self.replacementInjection = replacementInjection
        rootIdentity = try Self.identity(descriptor, directory: true)
    }

    /// Fixed retained-owner view; no transient root descriptor is opened.
    fileprivate init(temporalRootURL root: URL, heldRoot: Int32) throws {
        guard root.isFileURL, root == root.standardizedFileURL,
              root.deletingLastPathComponent().lastPathComponent == "generations",
              root.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "FieldEvidenceData",
              let generation = UUID(uuidString: root.lastPathComponent),
              generation.uuidString.lowercased() == root.lastPathComponent else {
            throw OrphanFileCleanupServiceError.invalidGeneration
        }
        generationRootURL = root; generationID = generation
        rootIdentity = try Self.identity(heldRoot, directory: true)
        fileManager = .default; replacementInjection = nil
    }

    func reconcile(
        referencedRelativePaths: [String]
    ) throws -> OrphanFileCleanupSummary {
        guard Set(referencedRelativePaths).count == referencedRelativePaths.count,
              referencedRelativePaths.allSatisfy(
                DeletionIntentEncoderV1.validRelativePath
              ),
              validEvidencePairs(referencedRelativePaths) else {
            throw OrphanFileCleanupServiceError.invalidReference
        }
        try validateKernelOrphanMappings()
        let summary = try reconcile(references: Set(referencedRelativePaths))
        try purgeDerivedSearchProjection()
        return summary
    }

    /// Produces the closed set that a private draft-content adapter may remove.
    /// This file-only service never guesses paths from a scratch lease or locator.
    func fieldDraftCleanupProof(
        stagingItems: [AttachmentStagingItemV1],
        reservations: [DraftContentReservationV1],
        discardReceipts: [DraftDiscardReceiptV1],
        liveStageIDs: Set<UUID>,
        liveReservationIDs: Set<UUID>
    ) throws -> FieldDraftOrphanCleanupProofV1 {
        try stagingItems.forEach { try $0.validate() }
        try reservations.forEach { try $0.validate() }
        try discardReceipts.forEach { try $0.validate() }
        let disposedStages = Set(discardReceipts.flatMap(\.disposedStageIDs))
        let quarantinedReservations = Set(discardReceipts.flatMap(\.quarantinedReservationIDs))
        let removableStages = stagingItems.filter {
            !liveStageIDs.contains($0.stageID)
                && (disposedStages.contains($0.stageID) || $0.state == .orphanQuarantined)
        }.map(\.stageID).sorted { $0.uuidString < $1.uuidString }
        let removableReservations = reservations.filter {
            quarantinedReservations.contains($0.reservationID)
                && $0.mayDelete(hasLiveReference: liveReservationIDs.contains($0.reservationID))
        }.map(\.reservationID).sorted { $0.uuidString < $1.uuidString }
        guard Set(removableStages).isSubset(of: disposedStages.union(Set(stagingItems.filter { $0.state == .orphanQuarantined }.map(\.stageID)))),
              Set(removableReservations).isSubset(of: quarantinedReservations) else {
            throw OrphanFileCleanupServiceError.nonterminalDraftContent
        }
        return .init(removableStageIDs: removableStages, removableReservationIDs: removableReservations)
    }

    /// Removes one exact canonical content object only after every durable and
    /// recovery owner has been projected. Active clips, report links, draft
    /// reservations, and recovery holds are all retention authorities.
    func removeCanonicalContentIfUnreferenced(
        reference: ContentReferenceV1,
        locator: ContentLocatorV1,
        authoritySnapshot: TemporalEvidenceLiveReferenceClosureV1
    ) throws -> OrphanFileCleanupSummary {
        try locator.validate(against: reference)
        guard let rawWorkspaceID = UUID(uuidString: reference.workspaceID) else {
            throw OrphanFileCleanupServiceError.invalidReference
        }
        let workspaceID = WorkspaceID(rawValue: rawWorkspaceID)
        try authoritySnapshot.validate(workspaceID: workspaceID)
        let retained = authoritySnapshot.liveClipContentIDs
            .union(authoritySnapshot.liveJournalContentIDs)
            .union(authoritySnapshot.liveReportContentIDs)
            .union(authoritySnapshot.reservedContentIDs)
            .union(authoritySnapshot.recoveryContentIDs)
        if retained.contains(reference.contentID) {
            return .init(inspectedFileCount: 1, removedFileCount: 0,
                         removedByteCount: 0, removedDirectoryCount: 0)
        }
        guard ContentContractValidationV1.validID(reference.contentID),
              UUID(uuidString: reference.workspaceID)?.uuidString.lowercased()
                == reference.workspaceID else {
            throw OrphanFileCleanupServiceError.invalidReference
        }
        let relativePath = "content/\(reference.workspaceID)/\(reference.contentID)/original.bin"
        let root = try openPinnedRoot(); defer { Darwin.close(root) }
        guard let content = try openRootIfPresent(parent: root, name: "content") else {
            return .init(inspectedFileCount: 0, removedFileCount: 0,
                         removedByteCount: 0, removedDirectoryCount: 0)
        }
        defer { Darwin.close(content.descriptor) }
        guard let workspace = try openRootIfPresent(
            parent: content.descriptor, name: reference.workspaceID
        ) else {
            return .init(inspectedFileCount: 0, removedFileCount: 0,
                         removedByteCount: 0, removedDirectoryCount: 0)
        }
        defer { Darwin.close(workspace.descriptor) }
        guard let object = try openRootIfPresent(
            parent: workspace.descriptor, name: reference.contentID
        ) else {
            return .init(inspectedFileCount: 0, removedFileCount: 0,
                         removedByteCount: 0, removedDirectoryCount: 0)
        }
        defer { Darwin.close(object.descriptor) }
        guard try boundedNames(in: object.descriptor) == ["original.bin"] else {
            throw OrphanFileCleanupServiceError.invalidOwnedLayout
        }
        let leaf = try inspectLeaf(parent: object.descriptor, name: "original.bin")
        guard leaf.byteCount == reference.byteLength else {
            throw OrphanFileCleanupServiceError.identityChanged
        }
        try verifySHA256(parent: object.descriptor, leaf: leaf, reference: reference)
        try removeLeaf(parent: object.descriptor, expectedParent: object.identity,
                       leaf: leaf, relativePath: relativePath)
        guard try boundedNames(in: object.descriptor).isEmpty,
              Darwin.unlinkat(workspace.descriptor, reference.contentID, AT_REMOVEDIR) == 0,
              Self.entryIsAbsent(parent: workspace.descriptor, name: reference.contentID),
              try Self.identity(workspace.descriptor, directory: true) == workspace.identity,
              Darwin.fsync(workspace.descriptor) == 0 else {
            throw OrphanFileCleanupServiceError.identityChanged
        }
        return .init(inspectedFileCount: 1, removedFileCount: 1,
                     removedByteCount: reference.byteLength, removedDirectoryCount: 1)
    }

    /// The local search projection is derived and has no canonical row-owned
    /// path. Orphan maintenance may therefore drop it wholesale for rebuild.
    func purgeDerivedSearchProjection() throws {
        do {
            try KernelDeletionEraseRegistryV4.validateSearchLifecycle()
            let applicationSupportURL = generationRootURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            try LocalSearchIndexStoreV1.synchronouslyEraseAll(
                applicationSupportURL: applicationSupportURL,
                fileManager: fileManager
            )
        } catch {
            throw OrphanFileCleanupServiceError.cleanupFailed
        }
    }

    /// Package-aware callers must prove the file projection belongs to the
    /// same workspace/generation before any pinned-FD cleanup is allowed. The
    /// overload is main-actor isolated because the shared query dependency is
    /// deliberately main-actor bound; the historical file-only entry point
    /// above remains available for synthetic XCTest stores.
    @MainActor
    func reconcile(
        referencedRelativePaths: [String],
        packageLifecycleDependencies dependencies: WorkspacePackageLifecycleDependenciesV1
    ) throws -> OrphanFileCleanupSummary {
        guard Set(referencedRelativePaths).count == referencedRelativePaths.count,
              referencedRelativePaths.allSatisfy(
                  DeletionIntentEncoderV1.validRelativePath
              ),
              validEvidencePairs(referencedRelativePaths) else {
            throw OrphanFileCleanupServiceError.invalidReference
        }
        try validateKernelOrphanMappings()
        let identities = try evidenceIdentities(in: referencedRelativePaths)
        try validatePackageLifecycleScope(
            dependencies,
            identities: identities
        )
        let summary = try reconcile(references: Set(referencedRelativePaths))
        try purgeDerivedSearchProjection()
        return summary
    }

    private func reconcile(
        references: Set<String>
    ) throws -> OrphanFileCleanupSummary {
        let sortedReferences = references.sorted()
        guard sortedReferences.allSatisfy(
                DeletionIntentEncoderV1.validRelativePath
              ),
              validEvidencePairs(sortedReferences) else {
            throw OrphanFileCleanupServiceError.invalidReference
        }

        let root = try openPinnedRoot()
        defer { Darwin.close(root) }
        var inventory = Inventory()
        try inventoryEvidence(
            root: root,
            references: references,
            inventory: &inventory
        )
        try inventoryFlatRoot(
            root: root,
            rootName: "snapshots",
            pathExtension: "json",
            references: references,
            inventory: &inventory
        )
        try inventoryFlatRoot(
            root: root,
            rootName: "pdfs",
            pathExtension: "pdf",
            references: references,
            inventory: &inventory
        )

        // Retain the injected FileManager as part of the initializer's
        // authority surface, but perform mutation only through pinned FDs.
        _ = fileManager
        var removedFiles = 0
        var removedBytes: Int64 = 0
        var removedDirectories = 0
        for candidate in inventory.candidates {
            try remove(candidate)
            removedFiles += candidate.leaves.count
            removedBytes += candidate.leaves.reduce(0) { $0 + $1.byteCount }
            if candidate.directoryIdentity != nil { removedDirectories += 1 }
        }
        return OrphanFileCleanupSummary(
            inspectedFileCount: inventory.inspectedFileCount,
            removedFileCount: removedFiles,
            removedByteCount: removedBytes,
            removedDirectoryCount: removedDirectories
        )
    }
}

private extension OrphanFileCleanupService {
    func validateKernelOrphanMappings() throws {
        do {
            try EvidenceMetadataOrphanCleanupPolicyV1.validate()
            try ScheduleOrphanCleanupPolicyV1.validate()
            try PlanOrphanCleanupPolicyV1.validate()
            try PlacementPoseOrphanCleanupPolicyV1.validate()
            let ownedContent = try KernelDeletionEraseRegistryV4.registration(
                for: .contentReference
            )
            let evidence = try KernelDeletionEraseRegistryV4.registration(
                for: .evidenceFile
            )
            let report = try KernelDeletionEraseRegistryV4.registration(
                for: .report
            )
            let completedSnapshot = try KernelDeletionEraseRegistryV4.registration(
                for: .completedActivitySnapshot
            )
            guard ownedContent.orphanCleanup == .removeOwnedBytesWhenUnreferenced,
                  evidence.orphanCleanup == .removeOwnedBytesWhenUnreferenced,
                  report.orphanCleanup == .preserveCanonicalRecord,
                  completedSnapshot.orphanCleanup == .preserveCanonicalRecord,
                  !ownedContent.clearsTombstonesOnDelete,
                  !evidence.clearsTombstonesOnDelete,
                  !report.clearsTombstonesOnDelete,
                  !completedSnapshot.clearsTombstonesOnDelete else {
                throw OrphanFileCleanupServiceError.invalidOwnedLayout
            }
        } catch let error as OrphanFileCleanupServiceError {
            throw error
        } catch {
            throw OrphanFileCleanupServiceError.invalidOwnedLayout
        }
    }

    @MainActor
    func evidenceIdentities(
        in paths: [String]
    ) throws -> [WorkspaceEntityIdentityV1] {
        let values = paths.compactMap { path -> UUID? in
            let components = path.split(separator: "/").map(String.init)
            guard components.count == 3,
                  components[0] == "evidence",
                  components[2] == "original.jpg"
                      || components[2] == "thumbnail.jpg",
                  let id = UUID(uuidString: components[1]),
                  id.uuidString.lowercased() == components[1] else {
                return nil
            }
            return id
        }
        guard Set(values).count * 2 == paths.filter({ $0.hasPrefix("evidence/") }).count
                || paths.filter({ $0.hasPrefix("evidence/") }).isEmpty else {
            throw OrphanFileCleanupServiceError.invalidReference
        }
        return try Set(values).sorted { $0.uuidString < $1.uuidString }.map {
            try WorkspaceEntityIdentityV1(kind: .evidenceFile, id: $0)
        }
    }

    @MainActor
    func validatePackageLifecycleScope(
        _ dependencies: WorkspacePackageLifecycleDependenciesV1,
        identities: [WorkspaceEntityIdentityV1]
    ) throws {
        guard dependencies.generationID == generationID,
              dependencies.generationRootURL.standardizedFileURL == generationRootURL,
              dependencies.generationRootURL.isFileURL else {
            throw OrphanFileCleanupServiceError.invalidGeneration
        }
        do {
            let request = try WorkspacePackageLifecycleQueryRequestV1(
                workspaceID: dependencies.workspaceID,
                generationID: dependencies.generationID,
                operation: .delete,
                identities: identities
            )
            let result = try dependencies.queryClient.query(request)
            guard result.workspaceID == dependencies.workspaceID,
                  result.generationID == generationID,
                  result.operation == .delete,
                  Set(result.existingIdentities) == Set(request.identities),
                  try dependencies.queryClient.currentRevision() == result.revision else {
                throw OrphanFileCleanupServiceError.identityChanged
            }
        } catch let error as OrphanFileCleanupServiceError {
            throw error
        } catch {
            throw OrphanFileCleanupServiceError.identityChanged
        }
    }

    struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    struct Leaf {
        let name: String
        let identity: Identity
        let byteCount: Int64
    }

    struct Candidate {
        let rootName: String
        let rootIdentity: Identity
        let directoryName: String?
        let directoryIdentity: Identity?
        let leaves: [Leaf]
    }

    struct Inventory {
        var candidates = [Candidate]()
        var inspectedFileCount = 0
        var inspectedBytes: Int64 = 0

        mutating func inspect(byteCount: Int64) throws {
            guard byteCount >= 0,
                  inspectedFileCount < OrphanFileCleanupService.maximumEntriesPerRoot * 3,
                  inspectedBytes <= OrphanFileCleanupService.maximumInspectedBytes - byteCount else {
                if byteCount < 0 {
                    throw OrphanFileCleanupServiceError.invalidOwnedLayout
                }
                if inspectedFileCount >= OrphanFileCleanupService.maximumEntriesPerRoot * 3 {
                    throw OrphanFileCleanupServiceError.inventoryLimitExceeded
                }
                throw OrphanFileCleanupServiceError.byteLimitExceeded
            }
            inspectedFileCount += 1
            inspectedBytes += byteCount
        }
    }

    func validEvidencePairs(_ paths: [String]) -> Bool {
        var names = [String: Set<String>]()
        for path in paths where path.hasPrefix("evidence/") {
            let components = path.split(separator: "/").map(String.init)
            guard components.count == 3 else { return false }
            names[components[1], default: []].insert(components[2])
        }
        return names.values.allSatisfy {
            $0 == Set(["original.jpg", "thumbnail.jpg"])
        }
    }

    func inventoryEvidence(
        root: Int32,
        references: Set<String>,
        inventory: inout Inventory
    ) throws {
        guard let evidence = try openRootIfPresent(parent: root, name: "evidence") else {
            return
        }
        defer { Darwin.close(evidence.descriptor) }
        let bundleNames = try boundedNames(in: evidence.descriptor)
        for bundleName in bundleNames {
            guard canonicalUUID(bundleName) else {
                throw OrphanFileCleanupServiceError.invalidOwnedLayout
            }
            let bundle = Darwin.openat(
                evidence.descriptor,
                bundleName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard bundle >= 0 else {
                throw OrphanFileCleanupServiceError.invalidOwnedLayout
            }
            do {
                let bundleIdentity = try Self.identity(bundle, directory: true)
                let names = try boundedNames(in: bundle)
                guard Set(names).isSubset(of: Set(["original.jpg", "thumbnail.jpg"])) else {
                    throw OrphanFileCleanupServiceError.invalidOwnedLayout
                }
                var leaves = [Leaf]()
                for name in names {
                    let leaf = try inspectLeaf(parent: bundle, name: name)
                    try inventory.inspect(byteCount: leaf.byteCount)
                    leaves.append(leaf)
                }
                let prefix = "evidence/\(bundleName)/"
                let referenced = references.contains(prefix + "original.jpg")
                    || references.contains(prefix + "thumbnail.jpg")
                if !referenced {
                    inventory.candidates.append(Candidate(
                        rootName: "evidence",
                        rootIdentity: evidence.identity,
                        directoryName: bundleName,
                        directoryIdentity: bundleIdentity,
                        leaves: leaves.sorted { $0.name < $1.name }
                    ))
                }
                Darwin.close(bundle)
            } catch {
                Darwin.close(bundle)
                throw error
            }
        }
    }

    func inventoryFlatRoot(
        root: Int32,
        rootName: String,
        pathExtension: String,
        references: Set<String>,
        inventory: inout Inventory
    ) throws {
        guard let ownedRoot = try openRootIfPresent(parent: root, name: rootName) else {
            return
        }
        defer { Darwin.close(ownedRoot.descriptor) }
        for name in try boundedNames(in: ownedRoot.descriptor) {
            guard canonicalUUIDFilename(name, pathExtension: pathExtension) else {
                throw OrphanFileCleanupServiceError.invalidOwnedLayout
            }
            let leaf = try inspectLeaf(parent: ownedRoot.descriptor, name: name)
            try inventory.inspect(byteCount: leaf.byteCount)
            if !references.contains("\(rootName)/\(name)") {
                inventory.candidates.append(Candidate(
                    rootName: rootName,
                    rootIdentity: ownedRoot.identity,
                    directoryName: nil,
                    directoryIdentity: nil,
                    leaves: [leaf]
                ))
            }
        }
    }

    func remove(_ candidate: Candidate) throws {
        let root = try openPinnedRoot()
        defer { Darwin.close(root) }
        guard let ownedRoot = try openRootIfPresent(
            parent: root,
            name: candidate.rootName
        ) else {
            throw OrphanFileCleanupServiceError.identityChanged
        }
        guard ownedRoot.identity == candidate.rootIdentity else {
            Darwin.close(ownedRoot.descriptor)
            throw OrphanFileCleanupServiceError.identityChanged
        }
        defer { Darwin.close(ownedRoot.descriptor) }

        if let directoryName = candidate.directoryName,
           let expectedDirectory = candidate.directoryIdentity {
            let directory = Darwin.openat(
                ownedRoot.descriptor,
                directoryName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
            guard directory >= 0,
                  try Self.identity(directory, directory: true) == expectedDirectory else {
                if directory >= 0 { Darwin.close(directory) }
                throw OrphanFileCleanupServiceError.identityChanged
            }
            defer { Darwin.close(directory) }
            for leaf in candidate.leaves {
                try removeLeaf(
                    parent: directory,
                    expectedParent: expectedDirectory,
                    leaf: leaf,
                    relativePath: "\(candidate.rootName)/\(directoryName)/\(leaf.name)"
                )
            }
            let relativeDirectory = "\(candidate.rootName)/\(directoryName)"
            try replacementInjection?.runIfPresent(
                at: generationRootURL.appendingPathComponent(
                    relativeDirectory,
                    isDirectory: true
                )
            )
            var namedDirectory = stat()
            guard try boundedNames(in: directory).isEmpty,
                  Darwin.fstatat(
                    ownedRoot.descriptor,
                    directoryName,
                    &namedDirectory,
                    AT_SYMLINK_NOFOLLOW
                  ) == 0,
                  (namedDirectory.st_mode & S_IFMT) == S_IFDIR,
                  Identity(
                    device: namedDirectory.st_dev,
                    inode: namedDirectory.st_ino
                  ) == expectedDirectory,
                  Darwin.unlinkat(ownedRoot.descriptor, directoryName, AT_REMOVEDIR) == 0,
                  Self.entryIsAbsent(parent: ownedRoot.descriptor, name: directoryName),
                  try Self.identity(ownedRoot.descriptor, directory: true)
                    == candidate.rootIdentity,
                  Darwin.fsync(ownedRoot.descriptor) == 0 else {
                throw OrphanFileCleanupServiceError.identityChanged
            }
        } else {
            guard candidate.leaves.count == 1, let leaf = candidate.leaves.first else {
                throw OrphanFileCleanupServiceError.invalidOwnedLayout
            }
            try removeLeaf(
                parent: ownedRoot.descriptor,
                expectedParent: candidate.rootIdentity,
                leaf: leaf,
                relativePath: "\(candidate.rootName)/\(leaf.name)"
            )
        }
    }

    func removeLeaf(
        parent: Int32,
        expectedParent: Identity,
        leaf: Leaf,
        relativePath: String
    ) throws {
        let descriptor = Darwin.openat(parent, leaf.name, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw OrphanFileCleanupServiceError.identityChanged
        }
        defer { Darwin.close(descriptor) }
        var info = stat()
        try replacementInjection?.runIfPresent(
            at: generationRootURL.appendingPathComponent(relativePath)
        )
        var named = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              try Self.identity(parent, directory: true) == expectedParent,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1,
              Identity(device: info.st_dev, inode: info.st_ino) == leaf.identity,
              Int64(info.st_size) == leaf.byteCount,
              Darwin.fstatat(parent, leaf.name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              (named.st_mode & S_IFMT) == S_IFREG,
              named.st_nlink == 1,
              Identity(device: named.st_dev, inode: named.st_ino) == leaf.identity,
              Int64(named.st_size) == leaf.byteCount,
              Darwin.unlinkat(parent, leaf.name, 0) == 0,
              Self.entryIsAbsent(parent: parent, name: leaf.name),
              try Self.identity(parent, directory: true) == expectedParent,
              Darwin.fsync(parent) == 0 else {
            throw OrphanFileCleanupServiceError.identityChanged
        }
    }

    func verifySHA256(
        parent: Int32,
        leaf: Leaf,
        reference: ContentReferenceV1
    ) throws {
        guard let expected = reference.digests.digest(for: .sha256) else {
            throw OrphanFileCleanupServiceError.invalidReference
        }
        let descriptor = Darwin.openat(parent, leaf.name, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw OrphanFileCleanupServiceError.identityChanged
        }
        defer { Darwin.close(descriptor) }
        var initial = stat()
        guard Darwin.fstat(descriptor, &initial) == 0,
              (initial.st_mode & S_IFMT) == S_IFREG,
              initial.st_nlink == 1,
              Identity(device: initial.st_dev, inode: initial.st_ino) == leaf.identity,
              Int64(initial.st_size) == leaf.byteCount else {
            throw OrphanFileCleanupServiceError.identityChanged
        }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else {
                throw OrphanFileCleanupServiceError.identityChanged
            }
            if count == 0 { break }
            hasher.update(data: Data(buffer[0..<count]))
        }
        var after = stat()
        let observed = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard observed == expected.hexadecimalValue,
              Darwin.fstat(descriptor, &after) == 0,
              after.st_dev == initial.st_dev, after.st_ino == initial.st_ino,
              after.st_size == initial.st_size, after.st_nlink == 1 else {
            throw OrphanFileCleanupServiceError.identityChanged
        }
    }

    func inspectLeaf(parent: Int32, name: String) throws -> Leaf {
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw OrphanFileCleanupServiceError.invalidOwnedLayout
        }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1,
              info.st_size >= 0 else {
            throw OrphanFileCleanupServiceError.invalidOwnedLayout
        }
        return Leaf(
            name: name,
            identity: Identity(device: info.st_dev, inode: info.st_ino),
            byteCount: Int64(info.st_size)
        )
    }

    func openPinnedRoot() throws -> Int32 {
        let descriptor = Darwin.open(
            generationRootURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0,
              try Self.identity(descriptor, directory: true) == rootIdentity,
              generationRootURL.lastPathComponent == generationID.uuidString.lowercased() else {
            if descriptor >= 0 { Darwin.close(descriptor) }
            throw OrphanFileCleanupServiceError.invalidGeneration
        }
        return descriptor
    }

    func openRootIfPresent(
        parent: Int32,
        name: String
    ) throws -> (descriptor: Int32, identity: Identity)? {
        let descriptor = Darwin.openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        if descriptor < 0, errno == ENOENT { return nil }
        guard descriptor >= 0 else {
            throw OrphanFileCleanupServiceError.invalidOwnedLayout
        }
        do {
            return (descriptor, try Self.identity(descriptor, directory: true))
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    func boundedNames(in descriptor: Int32) throws -> [String] {
        let duplicate = Darwin.dup(descriptor)
        guard duplicate >= 0, let directory = Darwin.fdopendir(duplicate) else {
            if duplicate >= 0 { Darwin.close(duplicate) }
            throw OrphanFileCleanupServiceError.invalidOwnedLayout
        }
        defer { Darwin.closedir(directory) }
        var result = [String]()
        errno = 0
        while let entry = Darwin.readdir(directory) {
            guard let name = OwnedStorageDirectoryEntryNameV1.decode(entry) else {
                throw OrphanFileCleanupServiceError.invalidOwnedLayout
            }
            if name != "." && name != ".." {
                guard result.count < Self.maximumEntriesPerRoot else {
                    throw OrphanFileCleanupServiceError.inventoryLimitExceeded
                }
                result.append(name)
            }
            errno = 0
        }
        guard errno == 0 else {
            throw OrphanFileCleanupServiceError.invalidOwnedLayout
        }
        return result.sorted()
    }

    func canonicalUUIDFilename(_ filename: String, pathExtension: String) -> Bool {
        let suffix = ".\(pathExtension)"
        guard filename.hasSuffix(suffix) else { return false }
        return canonicalUUID(String(filename.dropLast(suffix.count)))
    }

    func canonicalUUID(_ value: String) -> Bool {
        guard let identifier = UUID(uuidString: value) else { return false }
        return identifier.uuidString.lowercased() == value
    }

    static func identity(_ descriptor: Int32, directory: Bool) throws -> Identity {
        var info = stat()
        let expected = directory ? S_IFDIR : S_IFREG
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == expected else {
            throw OrphanFileCleanupServiceError.invalidOwnedLayout
        }
        return Identity(device: info.st_dev, inode: info.st_ino)
    }

    static func entryIsAbsent(parent: Int32, name: String) -> Bool {
        var info = stat()
        guard Darwin.fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) != 0 else {
            return false
        }
        return errno == ENOENT
    }
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Deletion_OrphanFileCleanupService {
    enum ProposalDispositionV1: Sendable {
        case nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
    }

    enum AcceptanceDispositionV1: Sendable {
        case durableThroughExistingCanonicalWriter
    }

    static func disposition(
        for proposal: AssistanceProposalV1
    ) throws -> ProposalDispositionV1 {
        try proposal.validate()
        guard !AssistancePersistenceEnrollmentV1.proposalIsPersistent,
              !AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent else {
            throw AssistanceContractFailureV1.nonCanonicalData
        }
        switch proposal.verificationState {
        case .unverified:
            return .nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
        }
    }

    static func disposition(
        for receipt: AssistanceAcceptanceReceiptV1
    ) throws -> AcceptanceDispositionV1 {
        try receipt.validate()
        guard AssistancePersistenceEnrollmentV1.durableModelCount == 1 else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
        return .durableThroughExistingCanonicalWriter
    }

    static let capabilityScratchIsDiscardedOnTerminalReview = true
    static let manualFallbackRemainsAvailable = true
    static let interruptionNeverPromotesAProposal = true
    static let createsParallelStoreOrWriter = false
}


// MARK: - C33 temporal evidence orphan cleanup

enum TemporalEvidenceOrphanCleanupPolicyV1 {
    static let missingOriginalCannotDeleteClipRow = true
    static let regenerableDerivativeMayBeRemoved = true
    static let unacceptedScratchIsAlwaysDisposable = true
    static let acceptedOriginalUsesCanonicalReferenceReachability = true

    static func mayRemoveDerivative(
        _ derivative: TemporalEvidenceDerivativeV1,
        clip: TemporalEvidenceClipV1,
        hasLiveReference: Bool
    ) throws -> Bool {
        try derivative.validate(clip: clip)
        return regenerableDerivativeMayBeRemoved && !hasLiveReference
    }

    static func validate() throws {
        guard missingOriginalCannotDeleteClipRow,
              regenerableDerivativeMayBeRemoved,
              unacceptedScratchIsAlwaysDisposable,
              acceptedOriginalUsesCanonicalReferenceReachability else {
            throw KernelPersistenceV4Failure.incompleteCoverage
        }
    }
}

struct AssetLabelDerivedScratchCleanupV1 {
    private static let maximumAttemptCount = 10_000
    private let rootURL: URL
    private let fileManager: FileManager

    init(generationRootURL: URL, fileManager: FileManager = .default) throws {
        let generationRoot = generationRootURL.standardizedFileURL
        guard generationRoot.isFileURL,
              UUID(uuidString: generationRoot.lastPathComponent) != nil,
              generationRoot.deletingLastPathComponent().lastPathComponent == "generations",
              generationRoot.deletingLastPathComponent()
                .deletingLastPathComponent().lastPathComponent == "FieldEvidenceData" else {
            throw OrphanFileCleanupServiceError.invalidGeneration
        }
        rootURL = generationRoot
            .appendingPathComponent("jobs", isDirectory: true)
            .appendingPathComponent("asset-label-render", isDirectory: true)
        self.fileManager = fileManager
    }

    /// Deletes only validated C45 attempt directories whose canonical plan
    /// references the deleted asset. Unknown, corrupt, symlinked, or
    /// over-limit scratch fails closed so canonical deletion can be retried.
    func removeAttempts(referencing assetID: UUID) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) else { return }
        guard isDirectory.boolValue else { throw OrphanFileCleanupServiceError.invalidGeneration }
        let children = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        guard children.count <= Self.maximumAttemptCount else {
            throw OrphanFileCleanupServiceError.invalidGeneration
        }
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true,
                  UUID(uuidString: child.lastPathComponent) != nil else {
                throw OrphanFileCleanupServiceError.invalidGeneration
            }
            try ProtectedFilePolicyV1.verify(.scratch, at: child)
            let planURL = child.appendingPathComponent("plan.json")
            let attributes = try fileManager.attributesOfItem(atPath: planURL.path)
            guard let byteCount = attributes[.size] as? NSNumber,
                  byteCount.int64Value > 0,
                  byteCount.int64Value <= Int64(AssetLabelCanonicalCodecV1.maximumCanonicalByteCount) else {
                throw OrphanFileCleanupServiceError.invalidGeneration
            }
            let data = try Data(contentsOf: planURL, options: [.mappedIfSafe])
            let plan = try AssetLabelCanonicalCodecV1.decode(
                AssetLabelGenerationPlanV1.self, from: data
            )
            guard try AssetLabelCanonicalCodecV1.encode(plan) == data else {
                throw OrphanFileCleanupServiceError.invalidGeneration
            }
            if plan.items.contains(where: { $0.assetID == assetID }) {
                try fileManager.removeItem(at: child)
            }
        }
    }

    func removeAllAttempts() throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) else { return }
        guard isDirectory.boolValue else { throw OrphanFileCleanupServiceError.invalidGeneration }
        let children = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        guard children.count <= Self.maximumAttemptCount else {
            throw OrphanFileCleanupServiceError.invalidGeneration
        }
        for child in children {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true,
                  UUID(uuidString: child.lastPathComponent) != nil else {
                throw OrphanFileCleanupServiceError.invalidGeneration
            }
            try ProtectedFilePolicyV1.verify(.scratch, at: child)
        }
        try fileManager.removeItem(at: rootURL)
    }
}

enum C45AcceptedLabelOrphanCleanupBoundaryV1 { static let cleansOnlyLeasedDerivedArtifacts=true;static let neverDeletesCanonicalLocatorTruth=true }

enum C46OperationalContactBoundary_46{static let assetOrSiteCascadeDeletesPartyContacts=false;static let workspaceEraseOwnsRows=true}
enum C47ActivityContractOrphanCleanupBoundaryV2 { static let canonicalRowsAreNeverOrphanFiles=true;static let releasedCompletedSnapshotUsesExistingReportCleanup=true;static let derivedSearchAndScratchMayBeRebuilt=true }

enum C48PortableExchangeOrphanCleanupBoundaryV2 {
    static let sessionStoreOwnsImmutablePayloadCleanup = true
    static let genericOrphanCleanupMayDeleteSessionBytes = false
    static let eraseRemovesWholeProtectedRoot = true
    static func validate() throws {
        guard sessionStoreOwnsImmutablePayloadCleanup,
              !genericOrphanCleanupMayDeleteSessionBytes,
              eraseRemovesWholeProtectedRoot else {
            throw OrphanFileCleanupServiceError.invalidOwnedLayout
        }
    }
}
// C52_BOUNDARY_ANCHOR: sanitized-media-cleanup-only

// MARK: - Prepared, original-only temporal reservation cleanup

/// Immutable physical observation only. Canonical/operational no-owner proof
/// belongs to the normalizer and must be freshly supplied at publication.
struct PreparedTemporalUncommittedOriginalV1: Equatable, Sendable {
    let reservation: TemporalEvidencePromotionReservationV1
    let generationRootURL: URL
    let observedByteCount: Int64
    fileprivate let directories: [TemporalOrphanDirectoryObservationV1]
    fileprivate let state: TemporalOrphanOriginalStateV1

    fileprivate init(reservation: TemporalEvidencePromotionReservationV1, generationRootURL: URL,
                     directories: [TemporalOrphanDirectoryObservationV1], state: TemporalOrphanOriginalStateV1) {
        self.reservation = reservation
        self.generationRootURL = generationRootURL
        self.directories = directories
        self.state = state
        if case .original(let facts, _, _) = state { observedByteCount = facts.byteCount }
        else { observedByteCount = 0 }
    }
}

fileprivate struct TemporalOrphanFileFactsV1: Equatable, Sendable {
    let device: dev_t
    let inode: ino_t
    let mode: mode_t
    let links: nlink_t
    let byteCount: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64

    init(_ info: stat) {
        device = info.st_dev; inode = info.st_ino; mode = info.st_mode; links = info.st_nlink
        byteCount = Int64(info.st_size)
        modifiedSeconds = Int64(info.st_mtimespec.tv_sec)
        modifiedNanoseconds = Int64(info.st_mtimespec.tv_nsec)
        changedSeconds = Int64(info.st_ctimespec.tv_sec)
        changedNanoseconds = Int64(info.st_ctimespec.tv_nsec)
    }
    func sameDirectoryIdentity(as other: Self) -> Bool {
        mode & S_IFMT == S_IFDIR && other.mode & S_IFMT == S_IFDIR
            && device == other.device && inode == other.inode
    }
}

fileprivate struct TemporalOrphanDirectoryObservationV1: Equatable, Sendable {
    let facts: TemporalOrphanFileFactsV1
    let policy: TemporalPolicyObservationV1
}

fileprivate enum TemporalOrphanOriginalStateV1: Equatable, Sendable {
    // The next component after the exact observed directory prefix is absent.
    case absent
    case emptyObject
    case original(TemporalOrphanFileFactsV1, TemporalPolicyObservationV1, String)
}

#if DEBUG
enum TemporalUncommittedOriginalRemovalBoundaryV1: Sendable {
    case afterOriginalUnlink
    case beforeObjectRemoval
}
#endif

extension OrphanFileCleanupService {
    #if DEBUG
    convenience init(generationRootURL: URL,
                     temporalRemovalBoundary: @escaping @MainActor (TemporalUncommittedOriginalRemovalBoundaryV1, URL) throws -> Void) throws {
        try self.init(generationRootURL: generationRootURL)
        self.temporalRemovalBoundary = temporalRemovalBoundary
    }
    #endif

    /// Call off-main, before acquiring G. Never creates, repairs or removes a
    /// path; request allowance is not substituted for observed file length.
    func prepareTemporalUncommittedOriginal(
        _ reservation: TemporalEvidencePromotionReservationV1
    ) throws -> PreparedTemporalUncommittedOriginalV1 {
        let components = try temporalOriginalComponents(reservation)
        return try withTemporalOriginalDirectories(components: components) { descriptors in
            let directories = try temporalDirectoryObservations(descriptors, components: components)
            let state: TemporalOrphanOriginalStateV1
            if descriptors.count < 4 {
                guard Self.entryIsAbsent(parent: descriptors.last!, name: components[descriptors.count - 1]) else {
                    throw OrphanFileCleanupServiceError.identityChanged
                }
                state = .absent
            } else {
                let object = descriptors[3]
                let hasOriginal = try temporalOriginalOnlyCensus(object)
                if !hasOriginal {
                    state = .emptyObject
                } else {
                    let descriptor = Darwin.openat(object, "original.bin", O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
                    guard descriptor >= 0 else { throw OrphanFileCleanupServiceError.identityChanged }
                    defer { Darwin.close(descriptor) }
                    let facts = try temporalRegularFacts(descriptor)
                    guard facts.byteCount > 0, facts.byteCount <= Self.maximumInspectedBytes,
                          UInt64(facts.byteCount) <= reservation.binding.request.requestedByteCount else {
                        throw OrphanFileCleanupServiceError.byteLimitExceeded
                    }
                    try temporalRequireNamedFile(object: object, descriptor: descriptor, facts: facts)
                    let policy = try ProtectedFilePolicyV1.observeTemporalPolicy(.mediaOriginal, at: temporalOriginalURL(components))
                    try temporalRequireNamedFile(object: object, descriptor: descriptor, facts: facts)
                    var hasher = SHA256()
                    var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
                    var remaining = facts.byteCount
                    while remaining > 0 {
                        let limit = Int(min(Int64(buffer.count), remaining))
                        let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, limit) }
                        if count < 0, errno == EINTR { continue }
                        guard count > 0 else { throw OrphanFileCleanupServiceError.identityChanged }
                        hasher.update(data: Data(buffer[0..<count]))
                        remaining -= Int64(count)
                    }
                    let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
                    guard digest == reservation.contentSHA256 else {
                        throw OrphanFileCleanupServiceError.identityChanged
                    }
                    try temporalRequireNamedFile(object: object, descriptor: descriptor, facts: facts)
                    guard try temporalOriginalOnlyCensus(object) else { throw OrphanFileCleanupServiceError.identityChanged }
                    state = .original(facts, policy, digest)
                }
            }
            try temporalReproveDirectories(descriptors, components: components, expected: directories)
            if descriptors.count == 4 {
                guard try temporalDirectoryFacts(descriptors[3]) == directories[3].facts else {
                    throw OrphanFileCleanupServiceError.identityChanged
                }
            } else if !Self.entryIsAbsent(parent: descriptors.last!, name: components[descriptors.count - 1]) {
                throw OrphanFileCleanupServiceError.identityChanged
            }
            return PreparedTemporalUncommittedOriginalV1(reservation: reservation, generationRootURL: generationRootURL,
                                                        directories: directories, state: state)
        }
    }

    /// Fixed synchronous publication: physical preparation is never authority.
    /// The genuine normalizer revalidates its same-G no-owner closure at entry
    /// and immediately before every unlink/rmdir. No hashing occurs here.
    @MainActor
    func publishTemporalUncommittedOriginalRemoval(
        _ prepared: PreparedTemporalUncommittedOriginalV1,
        publication: TemporalNormalizationPublicationProofV1
    ) throws -> OrphanFileCleanupSummary {
        try publication.requireUncommittedOriginalRemoval(reservation: prepared.reservation,
            generationRootURL: prepared.generationRootURL)
        return try publication.publishRetainedOriginal(prepared, service: self)
    }

    fileprivate func retainedTemporalOriginalComponents(_ reservation: TemporalEvidencePromotionReservationV1) throws -> [String] {
        try temporalOriginalComponents(reservation)
    }

    /// Only the actual retained read object calls this file-private mechanism.
    /// Every original predicate remains; no transient publication FD is opened.
    @MainActor
    fileprivate func publishHeldTemporalOriginal(_ prepared: PreparedTemporalUncommittedOriginalV1,
        publication: TemporalNormalizationPublicationProofV1, descriptors: [Int32],
        retainedOriginal: Int32?) throws -> OrphanFileCleanupSummary {
        try publication.requireUncommittedOriginalRemoval(reservation: prepared.reservation,
            generationRootURL: prepared.generationRootURL)
        guard prepared.generationRootURL == generationRootURL else { throw OrphanFileCleanupServiceError.invalidGeneration }
        let components = try temporalOriginalComponents(prepared.reservation)
        try temporalReproveDirectories(descriptors, components: components, expected: prepared.directories)
        if case .absent = prepared.state {
            guard descriptors.count < 4,
                  Self.entryIsAbsent(parent: descriptors.last!, name: components[descriptors.count - 1]) else {
                throw OrphanFileCleanupServiceError.identityChanged
            }
            try publication.requireUncommittedOriginalRemoval(reservation: prepared.reservation,
                                                              generationRootURL: prepared.generationRootURL)
            try temporalReproveDirectories(descriptors, components: components, expected: prepared.directories)
            guard Self.entryIsAbsent(parent: descriptors.last!, name: components[descriptors.count - 1]) else {
                throw OrphanFileCleanupServiceError.identityChanged
            }
            return .init(inspectedFileCount: 0, removedFileCount: 0, removedByteCount: 0, removedDirectoryCount: 0)
        }
        guard descriptors.count == 4,
              try temporalDirectoryFacts(descriptors[3]) == prepared.directories[3].facts else {
            throw OrphanFileCleanupServiceError.identityChanged
        }
        let object = descriptors[3], workspace = descriptors[2]
        let objectURL = temporalOriginalURL(components).deletingLastPathComponent()
        var removedFiles = 0
        var removedBytes: Int64 = 0
        let emptyObject: TemporalOrphanFileFactsV1
        if case .original(let facts, let policy, let digest) = prepared.state {
            guard digest == prepared.reservation.contentSHA256,
                  try publication.originalOnlyCensus() else { throw OrphanFileCleanupServiceError.identityChanged }
            guard let descriptor = retainedOriginal else { throw OrphanFileCleanupServiceError.identityChanged }
            try temporalRequireNamedFile(object: object, descriptor: descriptor, facts: facts)
            guard try ProtectedFilePolicyV1.observeTemporalPolicy(.mediaOriginal, at: temporalOriginalURL(components)) == policy else {
                throw OrphanFileCleanupServiceError.identityChanged
            }
            try temporalReproveDirectories(descriptors, components: components, expected: prepared.directories)
            guard try temporalDirectoryFacts(object) == prepared.directories[3].facts,
                  try publication.originalOnlyCensus() else { throw OrphanFileCleanupServiceError.identityChanged }
            try temporalRequireNamedFile(object: object, descriptor: descriptor, facts: facts)
            try publication.requireUncommittedOriginalRemoval(reservation: prepared.reservation,
                                                              generationRootURL: prepared.generationRootURL)
            try temporalReproveDirectories(descriptors, components: components, expected: prepared.directories)
            try temporalRequireNamedFile(object: object, descriptor: descriptor, facts: facts)
            guard try temporalDirectoryFacts(object) == prepared.directories[3].facts,
                  try publication.originalOnlyCensus(),
                  Darwin.unlinkat(object, "original.bin", 0) == 0 else {
                throw OrphanFileCleanupServiceError.identityChanged
            }
            // An observed-present disappearance is never reinterpreted as
            // initial absence; only this successful unlink reaches here.
            guard Self.entryIsAbsent(parent: object, name: "original.bin"),
                  try !publication.originalOnlyCensus(), Darwin.fsync(object) == 0 else {
                throw OrphanFileCleanupServiceError.cleanupFailed
            }
            removedFiles = 1; removedBytes = facts.byteCount
            emptyObject = try temporalDirectoryFacts(object)
            #if DEBUG
            try temporalRemovalBoundary?(.afterOriginalUnlink, temporalOriginalURL(components))
            #endif
        } else {
            guard try !publication.originalOnlyCensus() else {
                throw OrphanFileCleanupServiceError.identityChanged
            }
            emptyObject = prepared.directories[3].facts
        }
        #if DEBUG
        try temporalRemovalBoundary?(.beforeObjectRemoval, objectURL)
        #endif
        try temporalReproveDirectories(descriptors, components: components, expected: prepared.directories)
        guard try temporalDirectoryFacts(object) == emptyObject,
              try !publication.originalOnlyCensus() else { throw OrphanFileCleanupServiceError.identityChanged }
        try publication.requireUncommittedOriginalRemoval(reservation: prepared.reservation,
                                                          generationRootURL: prepared.generationRootURL)
        try temporalReproveDirectories(descriptors, components: components, expected: prepared.directories)
        guard try temporalDirectoryFacts(object) == emptyObject,
              try !publication.originalOnlyCensus(),
              Darwin.unlinkat(workspace, components[2], AT_REMOVEDIR) == 0 else {
            throw OrphanFileCleanupServiceError.identityChanged
        }
        guard Self.entryIsAbsent(parent: workspace, name: components[2]), Darwin.fsync(workspace) == 0 else {
            throw OrphanFileCleanupServiceError.cleanupFailed
        }
        // The object is intentionally gone; reprove every retained named
        // ancestor instead of trying to remint a new absent observation.
        try temporalReproveDirectories(Array(descriptors.prefix(3)), components: components,
                                        expected: Array(prepared.directories.prefix(3)))
        return .init(inspectedFileCount: removedFiles, removedFileCount: removedFiles,
                     removedByteCount: removedBytes, removedDirectoryCount: 1)
    }

}

private extension OrphanFileCleanupService {
    func temporalOriginalComponents(_ reservation: TemporalEvidencePromotionReservationV1) throws -> [String] {
        let workspace = reservation.workspaceID.rawValue.uuidString.lowercased()
        guard canonicalUUID(workspace), ContentContractValidationV1.validID(reservation.contentID),
              reservation.contentID != ".", reservation.contentID != "..",
              MutationEnvelopeV1.isSHA256(reservation.contentSHA256),
              reservation.mutationID == reservation.binding.mutationID,
              reservation.contentID == reservation.binding.contentID,
              reservation.contentSHA256 == reservation.binding.contentSHA256,
              reservation.binding.request.leaseID == reservation.binding.lease.leaseID,
              reservation.binding.request.purpose == reservation.binding.lease.purpose,
              reservation.binding.request.operationID == reservation.mutationID.rawValue,
              !ProtectedFilePolicyV1.isExcludedFromBackup(for: .mediaOriginal) else {
            throw OrphanFileCleanupServiceError.invalidReference
        }
        _ = try CapabilityScratchLeaseRequestV1(leaseID: reservation.binding.request.leaseID,
            operationID: reservation.binding.request.operationID, purpose: reservation.binding.request.purpose,
            requestedByteCount: reservation.binding.request.requestedByteCount,
            createdAt: reservation.binding.request.createdAt, expiresAt: reservation.binding.request.expiresAt)
        return ["content", workspace, reservation.contentID]
    }

    func temporalOriginalURL(_ components: [String]) -> URL {
        components.reduce(generationRootURL) { $0.appendingPathComponent($1, isDirectory: true) }
            .appendingPathComponent("original.bin")
    }

    func withTemporalOriginalDirectories<Value>(components: [String],
        body: ([Int32]) throws -> Value) throws -> Value {
        var descriptors = [try openPinnedRoot()]
        defer { descriptors.reversed().forEach { Darwin.close($0) } }
        for name in components {
            guard let next = try openRootIfPresent(parent: descriptors.last!, name: name) else { break }
            descriptors.append(next.descriptor)
        }
        return try body(descriptors)
    }

    func temporalDirectoryFacts(_ descriptor: Int32) throws -> TemporalOrphanFileFactsV1 {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
            throw OrphanFileCleanupServiceError.identityChanged
        }
        return .init(info)
    }

    func temporalRegularFacts(_ descriptor: Int32) throws -> TemporalOrphanFileFactsV1 {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_nlink == 1, info.st_size >= 0 else { throw OrphanFileCleanupServiceError.invalidOwnedLayout }
        return .init(info)
    }

    func temporalDirectoryObservations(_ descriptors: [Int32], components: [String]) throws -> [TemporalOrphanDirectoryObservationV1] {
        var result: [TemporalOrphanDirectoryObservationV1] = []
        var url = generationRootURL
        for index in descriptors.indices {
            if index > 0 { url.appendPathComponent(components[index - 1], isDirectory: true) }
            let before = try temporalDirectoryFacts(descriptors[index])
            let policy = try ProtectedFilePolicyV1.observeTemporalPolicy(.durableDirectory, at: url)
            guard try temporalDirectoryFacts(descriptors[index]) == before else {
                throw OrphanFileCleanupServiceError.identityChanged
            }
            result.append(.init(facts: before, policy: policy))
        }
        try temporalReproveDirectories(descriptors, components: components, expected: result)
        return result
    }

    func temporalReproveDirectories(_ descriptors: [Int32], components: [String],
        expected: [TemporalOrphanDirectoryObservationV1]) throws {
        guard !descriptors.isEmpty, descriptors.count == expected.count, descriptors.count <= 4 else {
            throw OrphanFileCleanupServiceError.identityChanged
        }
        var url = generationRootURL
        for index in descriptors.indices {
            let held = try temporalDirectoryFacts(descriptors[index])
            var named = stat()
            let status: Int32
            if index == 0 { status = Darwin.lstat(generationRootURL.path, &named) }
            else {
                url.appendPathComponent(components[index - 1], isDirectory: true)
                status = Darwin.fstatat(descriptors[index - 1], components[index - 1], &named, AT_SYMLINK_NOFOLLOW)
            }
            guard status == 0, held.sameDirectoryIdentity(as: expected[index].facts),
                  held.sameDirectoryIdentity(as: .init(named)), held.device == expected[0].facts.device,
                  try ProtectedFilePolicyV1.observeTemporalPolicy(.durableDirectory, at: url) == expected[index].policy,
                  try temporalDirectoryFacts(descriptors[index]).sameDirectoryIdentity(as: held) else {
                throw OrphanFileCleanupServiceError.identityChanged
            }
            var afterNamed = stat()
            let afterStatus = index == 0 ? Darwin.lstat(generationRootURL.path, &afterNamed)
                : Darwin.fstatat(descriptors[index - 1], components[index - 1], &afterNamed, AT_SYMLINK_NOFOLLOW)
            guard afterStatus == 0, held.sameDirectoryIdentity(as: .init(afterNamed)) else {
                throw OrphanFileCleanupServiceError.identityChanged
            }
        }
        // Resource checks above use URLs. Finish with the complete pinned
        // descriptor/name chain again before allowing the caller's effect.
        for index in descriptors.indices.reversed() {
            let held = try temporalDirectoryFacts(descriptors[index])
            var named = stat()
            let status = index == 0 ? Darwin.lstat(generationRootURL.path, &named)
                : Darwin.fstatat(descriptors[index - 1], components[index - 1], &named, AT_SYMLINK_NOFOLLOW)
            guard status == 0, held.sameDirectoryIdentity(as: expected[index].facts),
                  held.sameDirectoryIdentity(as: .init(named)) else {
                throw OrphanFileCleanupServiceError.identityChanged
            }
        }
    }

    func temporalRequireNamedFile(object: Int32, descriptor: Int32, facts: TemporalOrphanFileFactsV1) throws {
        var named = stat()
        guard try temporalRegularFacts(descriptor) == facts,
              Darwin.fstatat(object, "original.bin", &named, AT_SYMLINK_NOFOLLOW) == 0,
              TemporalOrphanFileFactsV1(named) == facts else { throw OrphanFileCleanupServiceError.identityChanged }
    }

    /// Closed original-only census, bounded by its first unexpected member.
    /// Opening dot gives an independent directory offset for every reproof.
    func temporalOriginalOnlyCensus(_ descriptor: Int32) throws -> Bool {
        let duplicate = Darwin.openat(descriptor, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard duplicate >= 0 else { throw OrphanFileCleanupServiceError.invalidOwnedLayout }
        guard let directory = Darwin.fdopendir(duplicate) else {
            Darwin.close(duplicate); throw OrphanFileCleanupServiceError.invalidOwnedLayout
        }
        defer { Darwin.closedir(directory) }
        var found = false
        while true {
            errno = 0
            guard let entry = Darwin.readdir(directory) else {
                guard errno == 0 else { throw OrphanFileCleanupServiceError.invalidOwnedLayout }
                return found
            }
            var tuple = entry.pointee.d_name
            let capacity = MemoryLayout.size(ofValue: tuple)
            let name = withUnsafePointer(to: &tuple) {
                $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            guard name == "original.bin", !found else { throw OrphanFileCleanupServiceError.invalidOwnedLayout }
            found = true
        }
    }
}

/// Fixed original-abandonment read resources. The genuine source set retains
/// this object before its first open. It is observation, never effect authority.
final class TemporalNormalizationAbandonmentReadV1: @unchecked Sendable {
    let sourceSetIdentity: ObjectIdentifier
    let generationRootURL: URL
    private let lock = NSLock()
    private var owned: [Int32] = []
    private var closed = Set<Int32>()
    private var closeUncertain = false
    private var closing = false
    private struct Directory {
        let fd: Int32, parent: Int32?, name: String, url: URL
        let facts: TemporalOrphanFileFactsV1
        let kind: OwnedFileKindV1
        let policy: TemporalPolicyObservationV1
    }
    private struct File {
        let fd: Int32, parent: Int32, name: String, url: URL
        let facts: TemporalOrphanFileFactsV1
        let kind: OwnedFileKindV1
        let policy: TemporalPolicyObservationV1
        let retainsBytes: Bool
        var offset: Int64 = 0
        var bytes = Data()
        var hash = SHA256()
        var digest: String?
    }
    private var directories: [Directory] = []
    private var files: [File] = []
    private var journalDirectory: Int32?
    private var journalNames: [String] = []
    private var journalResult: TemporalOperationalJournalObservationV1?
    private var originalDirectoryStart: Int?
    private var reservation: TemporalEvidencePromotionReservationV1?
    private var originalAbsent = false
    private var originalPrepared: PreparedTemporalUncommittedOriginalV1?
    private var readIndex = 0
    private var readPassComplete = false

    @MainActor
    init(sourceSet: TemporalNormalizationRetainedSourceSetV1, generationRootURL: URL) {
        sourceSetIdentity = ObjectIdentifier(sourceSet)
        self.generationRootURL = generationRootURL
    }
    private func requireOpen() throws {
        guard !closing, !closeUncertain else { throw OrphanFileCleanupServiceError.identityChanged }
    }
    private func retain(_ fd: Int32) throws -> Int32 {
        guard fd >= 0 else { throw OrphanFileCleanupServiceError.identityChanged }
        owned.append(fd) // before any stat, policy or allocation may throw
        return fd
    }
    private func openDirectory(parent: Int32?, name: String, url: URL,
                               kind: OwnedFileKindV1) throws -> Int32 {
        let fd = try retain(parent.map { Darwin.openat($0, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
            ?? Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC))
        var held = stat(), named = stat()
        guard Darwin.fstat(fd, &held) == 0, held.st_mode & S_IFMT == S_IFDIR,
              (parent.map { Darwin.fstatat($0, name, &named, AT_SYMLINK_NOFOLLOW) }
                ?? Darwin.lstat(url.path, &named)) == 0,
              named.st_mode & S_IFMT == S_IFDIR, held.st_dev == named.st_dev,
              held.st_ino == named.st_ino else { throw OrphanFileCleanupServiceError.identityChanged }
        let policy = try ProtectedFilePolicyV1.observeTemporalPolicy(kind, at: url)
        let value = Directory(fd: fd, parent: parent, name: name, url: url,
            facts: .init(held), kind: kind, policy: policy)
        directories.append(value)
        try revalidate(value)
        return fd
    }
    private func openFile(parent: Int32, name: String, url: URL, kind: OwnedFileKindV1,
                          maximum: Int64, retainsBytes: Bool) throws {
        let fd = try retain(Darwin.openat(parent, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC))
        var held = stat()
        guard Darwin.fstat(fd, &held) == 0, held.st_mode & S_IFMT == S_IFREG,
              held.st_nlink == 1, held.st_size >= 0, held.st_size <= maximum else {
            throw OrphanFileCleanupServiceError.byteLimitExceeded
        }
        let policy = try ProtectedFilePolicyV1.observeTemporalPolicy(kind, at: url)
        let file = File(fd: fd, parent: parent, name: name, url: url,
            facts: .init(held), kind: kind, policy: policy, retainsBytes: retainsBytes)
        files.append(file)
        try revalidate(file)
    }
    private func revalidate(_ value: Directory) throws {
        var held = stat(), named = stat()
        guard Darwin.fstat(value.fd, &held) == 0,
              (value.parent.map { Darwin.fstatat($0, value.name, &named, AT_SYMLINK_NOFOLLOW) }
                ?? Darwin.lstat(value.url.path, &named)) == 0,
              value.facts.sameDirectoryIdentity(as: .init(held)),
              value.facts.sameDirectoryIdentity(as: .init(named)) else {
            throw OrphanFileCleanupServiceError.identityChanged
        }
        let policy = try ProtectedFilePolicyV1.observeTemporalPolicy(value.kind, at: value.url)
        guard policy == value.policy, policy.device == UInt64(held.st_dev),
              policy.inode == UInt64(held.st_ino) else { throw OrphanFileCleanupServiceError.identityChanged }
    }
    private func revalidate(_ value: File) throws {
        var held = stat(), named = stat()
        guard Darwin.fstat(value.fd, &held) == 0,
              Darwin.fstatat(value.parent, value.name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              TemporalOrphanFileFactsV1(held) == value.facts,
              TemporalOrphanFileFactsV1(named) == value.facts else { throw OrphanFileCleanupServiceError.identityChanged }
        let policy = try ProtectedFilePolicyV1.observeTemporalPolicy(value.kind, at: value.url)
        guard policy == value.policy, policy.device == UInt64(held.st_dev),
              policy.inode == UInt64(held.st_ino) else { throw OrphanFileCleanupServiceError.identityChanged }
    }
    /// A fresh directory description is always closed exactly once, with its
    /// close result checked even on a scan failure. Ambiguity poisons this owner.
    private func names(_ fd: Int32, limit: Int) throws -> [String] {
        let fresh = Darwin.openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fresh >= 0 else { throw OrphanFileCleanupServiceError.identityChanged }
        guard let stream = Darwin.fdopendir(fresh) else {
            if Darwin.close(fresh) != 0 { closeUncertain = true }
            throw OrphanFileCleanupServiceError.identityChanged
        }
        let result: Result<[String], any Error> = Result {
            var result: [String] = []
            while true {
                errno = 0
                guard let entry = Darwin.readdir(stream) else {
                    guard errno == 0 else { throw OrphanFileCleanupServiceError.identityChanged }
                    break
                }
                guard let name = OwnedStorageDirectoryEntryNameV1.decode(entry) else {
                    throw OrphanFileCleanupServiceError.invalidOwnedLayout
                }
                if name == "." || name == ".." { continue }
                guard result.count < limit else { throw OrphanFileCleanupServiceError.byteLimitExceeded }
                result.append(name)
            }
            guard Set(result).count == result.count else { throw OrphanFileCleanupServiceError.invalidOwnedLayout }
            return result.sorted()
        }
        guard Darwin.closedir(stream) == 0 else {
            closeUncertain = true
            throw OrphanFileCleanupServiceError.identityChanged
        }
        return try result.get()
    }
    @MainActor
    func prepareJournalDescriptors() throws {
        try lock.withLock {
            try requireOpen()
            guard owned.isEmpty, journalDirectory == nil else { throw OrphanFileCleanupServiceError.identityChanged }
            let root = try openDirectory(parent: nil, name: "", url: generationRootURL, kind: .durableDirectory)
            let operationalURL = generationRootURL.appendingPathComponent("operational", isDirectory: true)
            let operational = try openDirectory(parent: root, name: "operational", url: operationalURL, kind: .stagingDirectory)
            let url = operationalURL.appendingPathComponent("temporal-evidence-promotion-v1", isDirectory: true)
            let directory = try openDirectory(parent: operational, name: "temporal-evidence-promotion-v1", url: url, kind: .stagingDirectory)
            journalDirectory = directory
            journalNames = try names(directory, limit: 257)
            // This fixed action never performs M1 recovery. Any registered slot
            // blocks before reads/classification/effects, including partial slots.
            guard journalNames.count <= 256, !journalNames.contains(where: { $0.hasPrefix(".tp2-") }) else {
                throw OrphanFileCleanupServiceError.invalidOwnedLayout
            }
            var total: Int64 = 0
            for name in journalNames {
                try openFile(parent: directory, name: name, url: url.appendingPathComponent(name),
                    kind: .journal, maximum: 1_048_576, retainsBytes: true)
                total += files.last!.facts.byteCount
                guard total <= 15 * 1_048_576 else { throw OrphanFileCleanupServiceError.byteLimitExceeded }
            }
            guard try names(directory, limit: 257) == journalNames else { throw OrphanFileCleanupServiceError.identityChanged }
        }
    }
    /// Called only by the original-reference access object's fixed chunk method.
    /// The caller cannot select a path, FD, offset, expected bytes or hash.
    func readNextChunkUnderOriginalReference() throws -> Bool {
        try lock.withLock {
            try requireOpen()
            guard journalDirectory != nil else { throw OrphanFileCleanupServiceError.identityChanged }
            if readIndex == files.count { readPassComplete = true; return false }
            let index = readIndex
            var file = files[index]
            try revalidate(file)
            let remaining = file.facts.byteCount - file.offset
            guard remaining >= 0 else { throw OrphanFileCleanupServiceError.identityChanged }
            if remaining > 0 {
                var bytes = Data(count: Int(min(65_536, remaining)))
                let count = bytes.withUnsafeMutableBytes { Darwin.pread(file.fd, $0.baseAddress!, $0.count, off_t(file.offset)) }
                if count < 0 && errno == EINTR { return true }
                guard count > 0 else { throw OrphanFileCleanupServiceError.identityChanged }
                bytes.count = count; file.offset += Int64(count); file.hash.update(data: bytes)
                if file.retainsBytes { file.bytes.append(bytes) }
            }
            try revalidate(file)
            if file.offset == file.facts.byteCount {
                file.digest = file.hash.finalize().map { String(format: "%02x", $0) }.joined()
                readIndex += 1
            }
            files[index] = file
            if readIndex == files.count { readPassComplete = true; return false }
            return true
        }
    }
    @MainActor
    func completedJournal() throws -> TemporalOperationalJournalObservationV1 {
        try lock.withLock {
            try requireOpen()
            guard reservation == nil, readPassComplete, let directory = journalDirectory,
                  try names(directory, limit: 257) == journalNames else { throw OrphanFileCleanupServiceError.identityChanged }
            for value in directories { try revalidate(value) }
            var bytes: [String: Data] = [:], policies: [String: TemporalPolicyObservationV1] = [:]
            for file in files {
                try revalidate(file)
                guard file.retainsBytes, file.offset == file.facts.byteCount,
                      file.bytes.count == Int(file.facts.byteCount), file.digest != nil else {
                    throw OrphanFileCleanupServiceError.identityChanged
                }
                bytes[file.name] = file.bytes; policies[file.url.path] = file.policy
            }
            for value in directories { policies[value.url.path] = value.policy }
            let result = try TemporalOperationalJournalObservationV1.decodeRetainedSettled(
                generationRootURL: generationRootURL, manifests: bytes, policyObservations: policies)
            journalResult = result
            return result
        }
    }
    @MainActor
    func prepareOriginalDescriptors(_ value: TemporalEvidencePromotionReservationV1) throws {
        try lock.withLock {
            try requireOpen()
            guard journalResult != nil, reservation == nil, readPassComplete, let root = directories.first else {
                throw OrphanFileCleanupServiceError.identityChanged
            }
            let service = try OrphanFileCleanupService(temporalRootURL: generationRootURL, heldRoot: root.fd)
            let components = try service.retainedTemporalOriginalComponents(value)
            reservation = value; originalDirectoryStart = directories.count
            var parent = root.fd, url = generationRootURL
            for name in components {
                url.appendPathComponent(name, isDirectory: true)
                var named = stat()
                if Darwin.fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) != 0 {
                    guard errno == ENOENT else { throw OrphanFileCleanupServiceError.identityChanged }
                    originalAbsent = true; break
                }
                parent = try openDirectory(parent: parent, name: name, url: url, kind: .durableDirectory)
            }
            if !originalAbsent {
                let children = try names(parent, limit: 2)
                guard children.isEmpty || children == ["original.bin"] else { throw OrphanFileCleanupServiceError.invalidOwnedLayout }
                if !children.isEmpty {
                    let maximum = min(UInt64(OrphanFileCleanupService.maximumInspectedBytes), value.binding.request.requestedByteCount)
                    try openFile(parent: parent, name: "original.bin", url: url.appendingPathComponent("original.bin"),
                        kind: .mediaOriginal, maximum: Int64(maximum), retainsBytes: false)
                    guard files.last!.facts.byteCount > 0 else { throw OrphanFileCleanupServiceError.invalidOwnedLayout }
                }
            }
            readPassComplete = readIndex == files.count
        }
    }
    @MainActor
    func completedOriginal() throws -> PreparedTemporalUncommittedOriginalV1 {
        try lock.withLock {
            try requireOpen()
            guard readPassComplete, let value = reservation, let start = originalDirectoryStart,
                  let root = directories.first else { throw OrphanFileCleanupServiceError.identityChanged }
            let originalDirectories = [root] + Array(directories[start...])
            for directory in originalDirectories { try revalidate(directory) }
            let state: TemporalOrphanOriginalStateV1
            if originalAbsent { state = .absent }
            else if let file = files.first(where: { !$0.retainsBytes }) {
                try revalidate(file)
                guard let digest = file.digest, digest == value.contentSHA256 else { throw OrphanFileCleanupServiceError.identityChanged }
                state = .original(file.facts, file.policy, digest)
            } else { state = .emptyObject }
            let prepared = PreparedTemporalUncommittedOriginalV1(reservation: value, generationRootURL: generationRootURL,
                directories: originalDirectories.map { .init(facts: $0.facts, policy: $0.policy) }, state: state)
            originalPrepared = prepared
            return prepared
        }
    }
    @MainActor
    func originalOnlyCensus() throws -> Bool {
        try lock.withLock {
            try requireOpen()
            guard let start = originalDirectoryStart, !originalAbsent,
                  directories.count == start + 3 else { throw OrphanFileCleanupServiceError.identityChanged }
            let children = try names(directories.last!.fd, limit: 2)
            guard children.isEmpty || children == ["original.bin"] else { throw OrphanFileCleanupServiceError.invalidOwnedLayout }
            return !children.isEmpty
        }
    }
    @MainActor
    func publishRetainedOriginal(_ expected: PreparedTemporalUncommittedOriginalV1,
        service: OrphanFileCleanupService, publication: TemporalNormalizationPublicationProofV1) throws -> OrphanFileCleanupSummary {
        let retained = try lock.withLock { () throws -> ([Int32], Int32?) in
            try requireOpen()
            guard let prepared = originalPrepared, prepared == expected, let root = directories.first,
                  let start = originalDirectoryStart, readPassComplete else { throw OrphanFileCleanupServiceError.identityChanged }
            return ([root.fd] + directories[start...].map(\.fd), files.first(where: { !$0.retainsBytes })?.fd)
        }
        return try service.publishHeldTemporalOriginal(expected, publication: publication,
            descriptors: retained.0, retainedOriginal: retained.1)
    }
    @MainActor
    func fixedRemovalService() throws -> OrphanFileCleanupService {
        try lock.withLock {
            try requireOpen()
            guard originalPrepared != nil, let root = directories.first else {
                throw OrphanFileCleanupServiceError.identityChanged
            }
            try revalidate(root)
            return try OrphanFileCleanupService(temporalRootURL: generationRootURL, heldRoot: root.fd)
        }
    }
    @MainActor
    func requireJournalUnchanged() throws {
        try lock.withLock {
            try requireOpen()
            guard let directory = journalDirectory, journalResult != nil, readPassComplete,
                  try names(directory, limit: 257) == journalNames else { throw OrphanFileCleanupServiceError.identityChanged }
            for value in directories.prefix(3) { try revalidate(value) }
            for file in files where file.retainsBytes { try revalidate(file) }
            // Pending observation is never admitted as complete. This first
            // fixed action requires genuine current strict observations.
            guard directories.allSatisfy({ $0.policy.state == .strictComplete }),
                  files.allSatisfy({ $0.policy.state == .strictComplete }) else {
                throw OrphanFileCleanupServiceError.identityChanged
            }
        }
    }
    @MainActor
    func closeAfterWorkerJoined() throws {
        try lock.withLock {
            closing = true
            guard !closeUncertain else { throw OrphanFileCleanupServiceError.identityChanged }
            for fd in owned.reversed() where !closed.contains(fd) {
                closed.insert(fd)
                guard Darwin.close(fd) == 0 else {
                    closeUncertain = true; throw OrphanFileCleanupServiceError.identityChanged
                }
            }
        }
    }
}

import CryptoKit
import Foundation

struct MutationIDV1: Codable, Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID) throws {
        guard rawValue != Self.zero else { throw WorkspaceMutationContractFailureV1.invalidID }
        self.rawValue = rawValue
    }

    private static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(UUID.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum WorkspaceEntityKindV1: String, CaseIterable, Codable, Sendable {
    case site
    case asset
    case locationNode
    case assetPlacementEvent
    case assetCompositionEdge
    case assetCompositionEvent
    case savedSmartView
    case workflowRecord
    case evidenceFile
    case issue
    case packet
    case report
    case deletionLedgerEntry
}

struct WorkspaceEntityIdentityV1: Codable, Hashable, Sendable {
    let kind: WorkspaceEntityKindV1
    let id: UUID

    init(kind: WorkspaceEntityKindV1, id: UUID) throws {
        guard id != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) else {
            throw WorkspaceMutationContractFailureV1.invalidID
        }
        self.kind = kind
        self.id = id
    }

    private enum CodingKeys: String, CodingKey {
        case kind, id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: container.decode(WorkspaceEntityKindV1.self, forKey: .kind),
            id: container.decode(UUID.self, forKey: .id)
        )
    }

    func encode(to encoder: Encoder) throws {
        _ = try Self(kind: kind, id: id)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(id, forKey: .id)
    }

    var stableKey: String { "\(kind.rawValue):\(id.uuidString.lowercased())" }
}

struct WorkspaceEntityRevisionV1: Codable, Equatable, Sendable {
    let identity: WorkspaceEntityIdentityV1
    let revision: UInt64
}

struct WorkspaceRevisionV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let generationID: UUID
    let writerInstanceID: UUID
    let revision: UInt64
    let entityRevisions: [WorkspaceEntityRevisionV1]

    init(
        workspaceID: WorkspaceID,
        generationID: UUID,
        writerInstanceID: UUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
        revision: UInt64,
        entityRevisions: [WorkspaceEntityRevisionV1]
    ) throws {
        guard generationID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) else {
            throw WorkspaceMutationContractFailureV1.invalidID
        }
        let ordered = entityRevisions.sorted { $0.identity.stableKey < $1.identity.stableKey }
        guard Set(ordered.map(\.identity)).count == ordered.count else {
            throw WorkspaceMutationContractFailureV1.duplicateEntityRevision
        }
        self.workspaceID = workspaceID
        self.generationID = generationID
        self.writerInstanceID = writerInstanceID
        self.revision = revision
        self.entityRevisions = ordered
    }
}

struct WorkspaceExpectedRevisionV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let generationID: UUID
    let writerInstanceID: UUID
    let workspaceRevision: UInt64
    let entityRevisions: [WorkspaceEntityRevisionV1]

    init(snapshot: WorkspaceRevisionV1) {
        workspaceID = snapshot.workspaceID
        generationID = snapshot.generationID
        writerInstanceID = snapshot.writerInstanceID
        workspaceRevision = snapshot.revision
        entityRevisions = snapshot.entityRevisions
    }

    init(
        workspaceID: WorkspaceID,
        generationID: UUID,
        writerInstanceID: UUID,
        workspaceRevision: UInt64,
        entityRevisions: [WorkspaceEntityRevisionV1]
    ) throws {
        let validated = try WorkspaceRevisionV1(
            workspaceID: workspaceID,
            generationID: generationID,
            writerInstanceID: writerInstanceID,
            revision: workspaceRevision,
            entityRevisions: entityRevisions
        )
        self.init(snapshot: validated)
    }
}

struct FirstSignMutationV1: Codable, Equatable, Sendable {
    struct NewSiteV1: Codable, Equatable, Sendable {
        let id: UUID
        let label: String
        let address: String?
        let timeZoneID: String?
    }

    let siteID: UUID
    let newSite: NewSiteV1?
    let assetID: UUID
    let assetLabel: String
    let packID: String
    let packSchemaVersion: Int
    let packContentVersion: Int
    let createdAt: Date
    /// Nil only for decoding/replaying the frozen pre-V6 command shape. Every
    /// live V6 caller supplies all three placement fields atomically.
    let initialPlacementMutationID: MutationIDV1?
    let initialPlacementEventID: UUID?
    let initialPhysicalEpisodeID: PhysicalPlacementEpisodeIDV1?

    init(
        siteID: UUID,
        newSite: NewSiteV1?,
        assetID: UUID,
        assetLabel: String,
        packID: String,
        packSchemaVersion: Int,
        packContentVersion: Int,
        createdAt: Date,
        initialPlacementMutationID: MutationIDV1? = nil,
        initialPlacementEventID: UUID? = nil,
        initialPhysicalEpisodeID: PhysicalPlacementEpisodeIDV1? = nil
    ) {
        self.siteID = siteID
        self.newSite = newSite
        self.assetID = assetID
        self.assetLabel = assetLabel
        self.packID = packID
        self.packSchemaVersion = packSchemaVersion
        self.packContentVersion = packContentVersion
        self.createdAt = createdAt
        self.initialPlacementMutationID = initialPlacementMutationID
        self.initialPlacementEventID = initialPlacementEventID
        self.initialPhysicalEpisodeID = initialPhysicalEpisodeID
    }
}

struct CheckDraftMutationV1: Codable, Equatable, Sendable {
    let recordID: UUID
    let assetID: UUID
    let issueID: UUID?
    let parentRecordID: UUID?
    let stage: String
    let draftStepKey: String?
    let startedAt: Date
    let observedAtUTC: Date?
    let timeZoneID: String?
    let utcOffsetMinutes: Int?
    let localDate: String?
    let localTime: String?
    let afterDarkAcknowledgementKey: String?
    let afterDarkAcknowledgementCopy: String?
    let afterDarkAcknowledgementVersion: String?
    let afterDarkAcknowledgementAccepted: Bool?
    let safePositionAcknowledgementKey: String?
    let safePositionAcknowledgementCopy: String?
    let safePositionAcknowledgementVersion: String?
    let safePositionAcknowledgementAccepted: Bool?
    let packID: String
    let packSchemaVersion: Int
    let packContentVersion: Int
    let pdfTemplateID: String
    let pdfTemplateVersion: Int
    /// Optional only for decoding/replaying pre-ObservationAndTimeSchemaV1
    /// commands. New callers submit both values atomically.
    let observationBasis: ObservationBasisV1?
    let temporalContext: TemporalContextV1?

    init(
        recordID: UUID,
        assetID: UUID,
        issueID: UUID?,
        parentRecordID: UUID?,
        stage: String,
        draftStepKey: String?,
        startedAt: Date,
        observedAtUTC: Date?,
        timeZoneID: String?,
        utcOffsetMinutes: Int?,
        localDate: String?,
        localTime: String?,
        afterDarkAcknowledgementKey: String?,
        afterDarkAcknowledgementCopy: String?,
        afterDarkAcknowledgementVersion: String?,
        afterDarkAcknowledgementAccepted: Bool?,
        safePositionAcknowledgementKey: String?,
        safePositionAcknowledgementCopy: String?,
        safePositionAcknowledgementVersion: String?,
        safePositionAcknowledgementAccepted: Bool?,
        packID: String,
        packSchemaVersion: Int,
        packContentVersion: Int,
        pdfTemplateID: String,
        pdfTemplateVersion: Int,
        observationBasis: ObservationBasisV1? = nil,
        temporalContext: TemporalContextV1? = nil
    ) {
        self.recordID = recordID
        self.assetID = assetID
        self.issueID = issueID
        self.parentRecordID = parentRecordID
        self.stage = stage
        self.draftStepKey = draftStepKey
        self.startedAt = startedAt
        self.observedAtUTC = observedAtUTC
        self.timeZoneID = timeZoneID
        self.utcOffsetMinutes = utcOffsetMinutes
        self.localDate = localDate
        self.localTime = localTime
        self.afterDarkAcknowledgementKey = afterDarkAcknowledgementKey
        self.afterDarkAcknowledgementCopy = afterDarkAcknowledgementCopy
        self.afterDarkAcknowledgementVersion = afterDarkAcknowledgementVersion
        self.afterDarkAcknowledgementAccepted = afterDarkAcknowledgementAccepted
        self.safePositionAcknowledgementKey = safePositionAcknowledgementKey
        self.safePositionAcknowledgementCopy = safePositionAcknowledgementCopy
        self.safePositionAcknowledgementVersion = safePositionAcknowledgementVersion
        self.safePositionAcknowledgementAccepted = safePositionAcknowledgementAccepted
        self.packID = packID
        self.packSchemaVersion = packSchemaVersion
        self.packContentVersion = packContentVersion
        self.pdfTemplateID = pdfTemplateID
        self.pdfTemplateVersion = pdfTemplateVersion
        self.observationBasis = observationBasis
        self.temporalContext = temporalContext
    }
}

struct CheckEvidenceMutationV1: Codable, Equatable, Sendable {
    let evidenceID: UUID
    let draftID: UUID
    let purposeKey: String
    let relativePath: String
    let mimeType: String
    let byteCount: Int
    let sha256: String
    let thumbnailRelativePath: String
    let thumbnailByteCount: Int
    let thumbnailSHA256: String
    let nextDraftStepKey: String
    let createdAt: Date
}

struct SiteTimeZoneMutationV1: Codable, Equatable, Sendable {
    let siteID: UUID
    let timeZoneID: String
    let confirmedAt: Date
}

struct ArchiveEntitiesMutationV1: Codable, Equatable, Sendable {
    let identities: [WorkspaceEntityIdentityV1]
    let reason: String
}

struct DeleteAssetMutationV1: Codable, Equatable, Sendable {
    let deletionID: UUID
    let assetID: UUID
    let planDigest: String
}

struct DeleteSiteMutationV1: Codable, Equatable, Sendable {
    let deletionID: UUID
    let siteID: UUID
    let planDigest: String
}

struct EraseWorkspaceMutationV1: Codable, Equatable, Sendable {
    let eraseID: UUID
    let targetGenerationID: UUID
    let oldPointerDigest: String
    let emptyLedgerDigest: String
}

struct FinalizeCheckMutationV1: Codable, Equatable, Sendable {
    let finalizationMutationID: UUID
    let assetID: UUID
    let recordID: UUID
    let packetID: UUID
    let reportID: UUID
    let issueID: UUID?
    let semanticDigest: String
    let contentDigests: [String]
}

struct FinalizeCorrectionMutationV1: Codable, Equatable, Sendable {
    let finalizationMutationID: UUID
    let assetID: UUID
    let correctionRecordID: UUID
    let revisesRecordID: UUID
    let packetID: UUID
    let reportID: UUID
    let replacesReportID: UUID
    let semanticDigest: String
}

struct RecordWorkMutationV1: Codable, Equatable, Sendable {
    let workMutationID: UUID
    let assetID: UUID
    let issueID: UUID
    let recordID: UUID
    let evidenceIDs: [UUID]
    let semanticDigest: String
}

struct RestoreWorkspaceMutationV1: Codable, Equatable, Sendable {
    let restoreID: UUID
    let mode: String
    let sourceArchiveDigest: String
    let targetGenerationID: UUID
}

struct LocationHierarchyMutationV1: Codable, Equatable, Sendable {
    let plan: LocationHierarchyChangePlanV1
    let placementChanges: [AssetPlacementChangePlanV1]

    init(plan: LocationHierarchyChangePlanV1, placementChanges: [AssetPlacementChangePlanV1]) throws {
        try plan.validate()
        let ordered = placementChanges.sorted { $0.basis.assetID.uuidString < $1.basis.assetID.uuidString }
        guard ordered == placementChanges,
              Set(ordered.map(\.basis.assetID)).count == ordered.count,
              ordered.map(\.basis.assetID) == plan.bindingChangedAssetIDs,
              ordered.allSatisfy({
                  $0.operationID == plan.operationID
                    && $0.mutationID.rawValue == plan.operationID
                    && $0.basis.workspaceID == plan.workspaceID
                    && plan.continuityByAssetID[$0.basis.assetID] == $0.basis.reviewedContinuity
              }) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        self.plan = plan
        self.placementChanges = ordered
    }
}

enum SavedSmartViewMutationDispositionV1: String, Codable, Equatable, Sendable {
    case upsert = "UPSERT"
    case delete = "DELETE"
}

/// The sole canonical smart-view mutation payload. Query text may occur only
/// inside the workspace-owned descriptor; device preferences store only a
/// stable selected-view ID.
struct SavedSmartViewMutationV1: Codable, Equatable, Sendable {
    let disposition: SavedSmartViewMutationDispositionV1
    let workspaceID: UUID
    let id: UUID
    let stableID: String
    let expectedDescriptorRevision: UInt64
    let mutationID: UUID
    let descriptor: SavedSmartViewDescriptorV1?

    init(upserting descriptor: SavedSmartViewDescriptorV1) throws {
        try descriptor.validate()
        disposition = .upsert
        workspaceID = descriptor.workspaceID
        id = descriptor.id
        stableID = descriptor.stableID
        expectedDescriptorRevision = descriptor.revision - 1
        mutationID = descriptor.mutationID
        self.descriptor = descriptor
        try validate()
    }

    init(
        deletingID id: UUID,
        workspaceID: UUID,
        stableID: String,
        expectedDescriptorRevision: UInt64,
        mutationID: UUID
    ) throws {
        disposition = .delete
        self.workspaceID = workspaceID
        self.id = id
        self.stableID = stableID
        self.expectedDescriptorRevision = expectedDescriptorRevision
        self.mutationID = mutationID
        descriptor = nil
        try validate()
    }

    func validate() throws {
        guard workspaceID != SearchContractValidationV1.zeroUUID,
              id != SearchContractValidationV1.zeroUUID,
              mutationID != SearchContractValidationV1.zeroUUID,
              SearchContractValidationV1.validID(stableID) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        switch disposition {
        case .upsert:
            guard let descriptor,
                  descriptor.origin == .userSaved,
                  descriptor.workspaceID == workspaceID,
                  descriptor.id == id,
                  descriptor.stableID == stableID,
                  descriptor.mutationID == mutationID,
                  expectedDescriptorRevision < UInt64.max,
                  descriptor.revision == expectedDescriptorRevision + 1 else {
                throw WorkspaceMutationContractFailureV1.invalidPlan
            }
            try descriptor.validate()
        case .delete:
            guard descriptor == nil,
                  expectedDescriptorRevision > 0,
                  !stableID.hasPrefix("builtin.search.") else {
                throw WorkspaceMutationContractFailureV1.invalidPlan
            }
        }
    }
}

enum WorkspaceCommandV1: Codable, Equatable, Sendable {
    case createFirstSign(FirstSignMutationV1)
    case createCheckDraft(CheckDraftMutationV1)
    case acceptCheckEvidence(CheckEvidenceMutationV1)
    case updateSiteTimeZone(SiteTimeZoneMutationV1)
    case deleteAsset(DeleteAssetMutationV1)
    case deleteSite(DeleteSiteMutationV1)
    case eraseWorkspace(EraseWorkspaceMutationV1)
    case finalizeCheck(FinalizeCheckMutationV1)
    case finalizeCorrection(FinalizeCorrectionMutationV1)
    case recordWork(RecordWorkMutationV1)
    case restoreWorkspace(RestoreWorkspaceMutationV1)
    case archiveEntities(ArchiveEntitiesMutationV1)
    case applyLocationHierarchyChange(LocationHierarchyMutationV1)
    case applyAssetPlacementChange(AssetPlacementChangePlanV1)
    case applyAssetCompositionChange(AssetCompositionChangePlanV1)
    case applySavedSmartView(SavedSmartViewMutationV1)

    var kind: WorkspaceCommandKindV1 {
        switch self {
        case .createFirstSign: .createFirstSign
        case .createCheckDraft: .createCheckDraft
        case .acceptCheckEvidence: .acceptCheckEvidence
        case .updateSiteTimeZone: .updateSiteTimeZone
        case .deleteAsset: .deleteAsset
        case .deleteSite: .deleteSite
        case .eraseWorkspace: .eraseWorkspace
        case .finalizeCheck: .finalizeCheck
        case .finalizeCorrection: .finalizeCorrection
        case .recordWork: .recordWork
        case .restoreWorkspace: .restoreWorkspace
        case .archiveEntities: .archiveEntities
        case .applyLocationHierarchyChange: .applyLocationHierarchyChange
        case .applyAssetPlacementChange: .applyAssetPlacementChange
        case .applyAssetCompositionChange: .applyAssetCompositionChange
        case .applySavedSmartView: .applySavedSmartView
        }
    }
}

enum WorkspaceCommandKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case createFirstSign = "create_first_sign"
    case createCheckDraft = "begin_check_draft"
    case acceptCheckEvidence = "capture_evidence"
    case updateSiteTimeZone = "confirm_site_timezone"
    case deleteAsset = "delete_asset"
    case deleteSite = "delete_site"
    case eraseWorkspace = "erase_workspace"
    case finalizeCheck = "finalize_check"
    case finalizeCorrection = "finalize_correction"
    case recordWork = "record_work"
    case restoreWorkspace = "restore_workspace"
    case archiveEntities = "archive_entities_preview_compensation"
    case applyLocationHierarchyChange = "apply_location_hierarchy_change"
    case applyAssetPlacementChange = "apply_asset_placement_change"
    case applyAssetCompositionChange = "apply_asset_composition_change"
    case applySavedSmartView = "apply_saved_smart_view"
}

extension WorkspaceCommandV1 {
    func canonicalLocationAffectedIdentities() throws -> [WorkspaceEntityIdentityV1]? {
        let values: [WorkspaceEntityIdentityV1]
        switch self {
        case let .applyLocationHierarchyChange(value):
            let nodeIDs = Set(value.plan.beforeNodes.map(\.id)).union(value.plan.afterNodes.map(\.id))
            var result = try nodeIDs.map { try WorkspaceEntityIdentityV1(kind: .locationNode, id: $0) }
            for placement in value.placementChanges {
                result.append(try .init(kind: .asset, id: placement.basis.assetID))
                result.append(try .init(kind: .assetPlacementEvent, id: placement.newEventID))
            }
            values = result
        case let .applyAssetPlacementChange(plan):
            values = try [.init(kind: .asset, id: plan.basis.assetID), .init(kind: .assetPlacementEvent, id: plan.newEventID)]
        case let .applyAssetCompositionChange(plan):
            values = try [.init(kind: .assetCompositionEdge, id: plan.event.edge.id), .init(kind: .assetCompositionEvent, id: plan.event.id)]
        default:
            return nil
        }
        let ordered = values.sorted { $0.stableKey < $1.stableKey }
        guard ordered.count <= MutationReceiptV1.maximumPostImageCount,
              Set(ordered).count == ordered.count else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        return ordered
    }
}

struct WorkspaceMutationRequestV1: Codable, Equatable, Sendable {
    let mutationID: MutationIDV1
    let expectedRevision: WorkspaceExpectedRevisionV1
    let command: WorkspaceCommandV1
}

struct OwnedStorageAttemptIDV1: Hashable, Sendable {
    let workspaceID: WorkspaceID
    let generationID: UUID
    let mutationID: MutationIDV1

    init(
        workspaceID: WorkspaceID,
        generationID: UUID,
        mutationID: MutationIDV1
    ) throws {
        guard workspaceID.rawValue != Self.zero,
              generationID != Self.zero else {
            throw WorkspaceMutationContractFailureV1.invalidID
        }
        self.workspaceID = workspaceID
        self.generationID = generationID
        self.mutationID = mutationID
    }

    private static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

struct OwnedStorageVolumeIdentityV1: Equatable, Hashable, Sendable {
    let device: UInt64
}

struct OwnedStorageReservationV1: Equatable, Sendable {
    let attemptID: OwnedStorageAttemptIDV1
    let requiredBytes: Int64
    let volumeIdentity: OwnedStorageVolumeIdentityV1
}

protocol WorkspaceStorageAdmissionPortV1: AnyObject {
    func reserve(
        attemptID: OwnedStorageAttemptIDV1,
        requiredBytes: Int64
    ) throws -> OwnedStorageReservationV1
    func release(reservation: OwnedStorageReservationV1)
}

enum WorkspaceStorageEstimateV1 {
    /// Bounded allowance for the journal, SQLite pages and sidecars written by
    /// one canonical transaction. Existing feature-specific preflight
    /// estimates remain unchanged and additive.
    static let canonicalMutationAllowanceBytes: Int64 = 1_048_576

    static func requiredBytes(for command: WorkspaceCommandV1) throws -> Int64 {
        var required = canonicalMutationAllowanceBytes
        if case let .acceptCheckEvidence(value) = command {
            guard value.byteCount >= 0, value.thumbnailByteCount >= 0 else {
                throw WorkspaceMutationContractFailureV1.invalidPlan
            }
            let (content, contentOverflow) = Int64(value.byteCount)
                .addingReportingOverflow(Int64(value.thumbnailByteCount))
            let (total, totalOverflow) = required.addingReportingOverflow(content)
            guard !contentOverflow, !totalOverflow, total >= 0 else {
                throw WorkspaceMutationContractFailureV1.invalidPlan
            }
            required = total
        }
        return required
    }
}

struct WorkspaceMutationEffectV1: Codable, Equatable, Sendable {
    let affectedEntities: [WorkspaceEntityIdentityV1]
    let temporaryRelativePath: String

    init(affectedEntities: [WorkspaceEntityIdentityV1], temporaryRelativePath: String) throws {
        let ordered = affectedEntities.sorted { $0.stableKey < $1.stableKey }
        guard Set(ordered).count == ordered.count,
              !temporaryRelativePath.isEmpty,
              !temporaryRelativePath.hasPrefix("/"),
              !temporaryRelativePath.contains("..") else {
            throw WorkspaceMutationContractFailureV1.invalidEffect
        }
        self.affectedEntities = ordered
        self.temporaryRelativePath = temporaryRelativePath
    }
}

/// Process-local evidence only. C02 owns durable mutation receipts.
struct WorkspaceMutationOutcomeV1: Equatable, Sendable {
    let mutationID: MutationIDV1
    let commandDigest: String
    let occurredAt: Date
    let before: WorkspaceRevisionV1
    let after: WorkspaceRevisionV1
    let effect: WorkspaceMutationEffectV1
}

enum WorkspaceMutationFailureV1: Error, Equatable {
    case writerInvalidated
    case wrongWriterInstance
    case wrongWorkspace
    case wrongGeneration
    case staleWorkspaceRevision
    case staleEntityRevision(WorkspaceEntityIdentityV1)
    case mutationIDQuarantined
    case idempotencyCapacityReached
    case revisionOverflow
    case unsupportedCommand
    case invalidCommand
    case invalidEnvelope
    case invalidReceipt
    case invalidReversal
    case receiptHistoryCorrupt
    case sequenceCollision
    case storageAdmissionFailed
    case persistenceFailed
}

enum WorkspaceMutationContractFailureV1: Error, Equatable {
    case invalidID
    case duplicateEntityRevision
    case invalidEffect
    case invalidPlan
}

@MainActor
protocol WorkspaceQueryClientV1: AnyObject {
    func currentRevision() throws -> WorkspaceRevisionV1
    func query(
        _ request: WorkspacePackageLifecycleQueryRequestV1
    ) throws -> WorkspacePackageLifecycleQueryResultV1
}

enum WorkspacePackageLifecycleOperationV1: String, Codable, CaseIterable, Sendable {
    case acknowledge = "ACKNOWLEDGE"
    case archive = "ARCHIVE"
    case backup = "BACKUP"
    case capture = "CAPTURE"
    case complete = "COMPLETE"
    case delete = "DELETE"
    case erase = "ERASE"
    case exportOpen = "EXPORT_OPEN"
    case finalize = "FINALIZE"
    case query = "QUERY"
    case recover = "RECOVER"
    case reportPDF = "REPORT_PDF"
    case restore = "RESTORE"
}

struct PackageReleaseIdentityV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let packageID: String
    let schemaVersion: Int
    let contentVersion: Int

    init(packageID: String, schemaVersion: Int, contentVersion: Int) throws {
        guard !packageID.isEmpty,
              packageID == packageID.trimmingCharacters(in: .whitespacesAndNewlines),
              schemaVersion > 0, contentVersion > 0 else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        self.packageID = packageID
        self.schemaVersion = schemaVersion
        self.contentVersion = contentVersion
    }

    init(package: SignPack) throws {
        try self.init(
            packageID: package.packID,
            schemaVersion: package.schemaVersion,
            contentVersion: package.contentVersion
        )
    }

    func matches(_ package: SignPack) -> Bool {
        packageID == package.packID
            && schemaVersion == package.schemaVersion
            && contentVersion == package.contentVersion
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.packageID != rhs.packageID { return lhs.packageID < rhs.packageID }
        if lhs.schemaVersion != rhs.schemaVersion { return lhs.schemaVersion < rhs.schemaVersion }
        return lhs.contentVersion < rhs.contentVersion
    }
}

enum WorkspacePackageOutcomeRoleV1: String, Codable, CaseIterable, Hashable, Sendable {
    case noFinding = "NO_FINDING"
    case findingObserved = "FINDING_OBSERVED"
    case couldNotVerify = "COULD_NOT_VERIFY"
    case resolved = "RESOLVED"
    case findingStillPresent = "FINDING_STILL_PRESENT"
    case originalResolvedDifferentFinding = "ORIGINAL_RESOLVED_DIFFERENT_FINDING"
    case workRecorded = "WORK_RECORDED"
}

struct WorkspacePackageOutcomeProfileV1: Equatable, Sendable {
    let key: String
    let display: String
    let role: WorkspacePackageOutcomeRoleV1

    init(key: String, display: String, role: WorkspacePackageOutcomeRoleV1) throws {
        guard !key.isEmpty, key == key.trimmingCharacters(in: .whitespacesAndNewlines),
              !display.isEmpty, display == display.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        self.key = key
        self.display = display
        self.role = role
    }
}

enum WorkspacePackageEvidenceRoleV1: String, Codable, CaseIterable, Hashable, Sendable {
    case captureRequired = "CAPTURE_REQUIRED"
    case captureSupplementary = "CAPTURE_SUPPLEMENTARY"
    case workSupplementary = "WORK_SUPPLEMENTARY"
}

struct WorkspacePackageEvidenceProfileV1: Equatable, Sendable {
    let key: String
    let role: WorkspacePackageEvidenceRoleV1

    init(key: String, role: WorkspacePackageEvidenceRoleV1) throws {
        guard !key.isEmpty, key == key.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        self.key = key
        self.role = role
    }
}

struct WorkspacePackageStageProfileV1: Equatable, Sendable {
    let stageKey: String
    let stageDisplay: String
    let outcomes: [WorkspacePackageOutcomeProfileV1]

    var outcomeKeys: [String] { outcomes.map(\.key) }

    init(
        stageKey: String,
        stageDisplay: String,
        outcomes: [WorkspacePackageOutcomeProfileV1]
    ) throws {
        guard !stageKey.isEmpty, !outcomes.isEmpty,
              Set(outcomes.map(\.key)).count == outcomes.count,
              Set(outcomes.map(\.role)).count == outcomes.count,
              outcomes.allSatisfy({ !$0.key.isEmpty }),
              stageKey == stageKey.trimmingCharacters(in: .whitespacesAndNewlines),
              !stageDisplay.isEmpty,
              stageDisplay == stageDisplay.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        self.stageKey = stageKey
        self.stageDisplay = stageDisplay
        self.outcomes = outcomes
    }
}

struct WorkspacePackageLifecycleProfileV1: Equatable, Sendable {
    let package: SignPack
    let release: PackageReleaseIdentityV1
    let stages: [WorkspacePackageStageProfileV1]
    let evidencePurposes: [WorkspacePackageEvidenceProfileV1]
    let requiredAcknowledgementKeys: [String]
    let pdfTemplate: PDFTemplateReferenceV1

    init(
        package: SignPack,
        release: PackageReleaseIdentityV1,
        stages: [WorkspacePackageStageProfileV1],
        evidencePurposes: [WorkspacePackageEvidenceProfileV1],
        requiredAcknowledgementKeys: [String],
        pdfTemplate: PDFTemplateReferenceV1
    ) throws {
        let packageStages = package.stageDisplays
        let packageOutcomes = package.outcomeDisplays
        let packagePurposeKeys = package.evidencePurposes.map(\.key)
        let profileOutcomes = stages.flatMap(\.outcomes)
        let packageStageProfiles = stages.filter { profile in
            packageStages.contains {
                $0.key == profile.stageKey && $0.display == profile.stageDisplay
            }
        }
        let supplementalStages = stages.filter { !packageStageProfiles.contains($0) }
        let packageOutcomeProfiles = packageStageProfiles.flatMap(\.outcomes)
        let profilePurposeKeys = evidencePurposes.map(\.key)
        let supportsWork = evidencePurposes.contains { $0.role == .workSupplementary }
        let declaredOutcomeKeys = Set(packageOutcomes.map(\.key))
        let packageOutcomesAreCovered = declaredOutcomeKeys.isSubset(
            of: Set(packageOutcomeProfiles.map(\.key))
        )
        let packageOutcomeMappingsAreExact = packageOutcomeProfiles.allSatisfy { profile in
            packageOutcomes.contains { $0.key == profile.key && $0.display == profile.display }
        }
        let repeatedOutcomeMappingsAreConsistent = Dictionary(
            grouping: packageOutcomeProfiles,
            by: \.key
        ).values.allSatisfy { values in
            Set(values.map(\.role)).count == 1 && Set(values.map(\.display)).count == 1
        }
        guard release.matches(package),
              packageStageProfiles.map({ "\($0.stageKey)\u{0}\($0.stageDisplay)" })
                == packageStages.map({ "\($0.key)\u{0}\($0.display)" }),
              Set(stages.map(\.stageKey)).count == stages.count,
              packageOutcomesAreCovered,
              packageOutcomeMappingsAreExact,
              repeatedOutcomeMappingsAreConsistent,
              supplementalStages.count == (supportsWork ? 1 : 0),
              supplementalStages.first.map({ $0.outcomes.count == 1 && $0.outcomes[0].role == .workRecorded }) ?? !supportsWork,
              supplementalStages.allSatisfy({ supplemental in
                  !packageStages.contains(where: {
                      $0.key == supplemental.stageKey || $0.display == supplemental.stageDisplay
                  }) && supplemental.outcomes.allSatisfy({ outcome in
                      !packageOutcomes.contains(where: {
                          $0.key == outcome.key || $0.display == outcome.display
                      })
                  })
              }),
              evidencePurposes.contains(where: { $0.role == .captureRequired }),
              profilePurposeKeys == packagePurposeKeys,
              Set(profilePurposeKeys).count == profilePurposeKeys.count,
              Set(requiredAcknowledgementKeys).count == requiredAcknowledgementKeys.count,
              requiredAcknowledgementKeys == package.acknowledgements.map(\.key),
              !pdfTemplate.id.isEmpty, pdfTemplate.version > 0 else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        self.package = package
        self.release = release
        self.stages = stages
        self.evidencePurposes = evidencePurposes
        self.requiredAcknowledgementKeys = requiredAcknowledgementKeys
        self.pdfTemplate = pdfTemplate
    }

    func stage(_ key: String) throws -> WorkspacePackageStageProfileV1 {
        guard let value = stages.first(where: { $0.stageKey == key }) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        return value
    }

    func evidencePurposes(
        for role: WorkspacePackageEvidenceRoleV1
    ) -> [WorkspacePackageEvidenceProfileV1] {
        evidencePurposes.filter { $0.role == role }
    }

    func evidencePurposeKeys(for role: WorkspacePackageEvidenceRoleV1) -> [String] {
        evidencePurposes(for: role).map(\.key)
    }
}

struct WorkspacePackageLifecycleProfileRegistryV1: Sendable {
    private let profiles: [WorkspacePackageLifecycleProfileV1]

    init(profiles: [WorkspacePackageLifecycleProfileV1]) throws {
        let ordered = profiles.sorted { $0.release < $1.release }
        guard !ordered.isEmpty,
              Set(ordered.map(\.release)).count == ordered.count else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        self.profiles = ordered
    }

    func resolve(
        _ release: PackageReleaseIdentityV1
    ) throws -> WorkspacePackageLifecycleProfileV1 {
        guard let value = profiles.first(where: { $0.release == release }) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        return value
    }
}

enum WorkspacePackageLifecycleCompatibilityV1 {
    static let expiration = "AFTER_ACCEPTED_S10_6_RECONCILIATION"

    static func legacyV3Profile(
        package: SignPack
    ) throws -> WorkspacePackageLifecycleProfileV1 {
        let baseOutcomeRoles: [String: WorkspacePackageOutcomeRoleV1] = [
            "no_visible_issue": .noFinding,
            "visible_issue": .findingObserved,
            "could_not_verify": .couldNotVerify,
        ]
        let recheckOutcomeRoles: [String: WorkspacePackageOutcomeRoleV1] = [
            "resolved": .resolved,
            "issue_still_visible": .findingStillPresent,
            "original_resolved_different_issue": .originalResolvedDifferentFinding,
        ]
        let purposeRoles: [String: WorkspacePackageEvidenceRoleV1] = [
            "wide_context": .captureRequired,
            "close_detail": .captureRequired,
            "work_context": .workSupplementary,
        ]
        let stageKeys = package.stageDisplays.map(\.key)
        let outcomeKeys = package.outcomeDisplays.map(\.key)
        let purposeKeys = package.evidencePurposes.map(\.key)
        let acknowledgementKeys = package.acknowledgements.map(\.key)
        let baseOutcomeKeys = Set(baseOutcomeRoles.keys)
        let completeOutcomeKeys = baseOutcomeKeys.union(recheckOutcomeRoles.keys)
        let hasRecheckOutcomes = Set(outcomeKeys) == completeOutcomeKeys
        let hasWorkPurpose = purposeKeys.contains("work_context")
        guard legacyPackageStructureIsValid(package),
              Set(stageKeys) == Set(["check"]) || Set(stageKeys) == Set(["check", "recheck"]),
              Set(stageKeys).count == stageKeys.count,
              Set(outcomeKeys) == baseOutcomeKeys || hasRecheckOutcomes,
              !hasRecheckOutcomes || stageKeys.contains("recheck"),
              Set(purposeKeys) == Set(["wide_context", "close_detail"])
                || Set(purposeKeys) == Set(["wide_context", "close_detail", "work_context"]),
              Set(acknowledgementKeys) == Set(["safe_authorized_position"])
                || Set(acknowledgementKeys) == Set(["after_dark", "safe_authorized_position"]) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        let outcomesByKey = Dictionary(
            uniqueKeysWithValues: package.outcomeDisplays.map { ($0.key, $0) }
        )
        func outcome(
            _ key: String,
            role: WorkspacePackageOutcomeRoleV1
        ) throws -> WorkspacePackageOutcomeProfileV1 {
            guard let entry = outcomesByKey[key] else {
                throw WorkspaceMutationContractFailureV1.invalidPlan
            }
            return try WorkspacePackageOutcomeProfileV1(
                key: entry.key,
                display: entry.display,
                role: role
            )
        }
        var stages: [WorkspacePackageStageProfileV1] = []
        for entry in package.stageDisplays {
            let mappings: [(String, WorkspacePackageOutcomeRoleV1)]
            switch entry.key {
            case "check":
                mappings = [
                    ("no_visible_issue", .noFinding),
                    ("visible_issue", .findingObserved),
                    ("could_not_verify", .couldNotVerify),
                ]
            case "recheck" where hasRecheckOutcomes:
                mappings = [
                    ("could_not_verify", .couldNotVerify),
                    ("resolved", .resolved),
                    ("issue_still_visible", .findingStillPresent),
                    ("original_resolved_different_issue", .originalResolvedDifferentFinding),
                ]
            case "recheck":
                mappings = [
                    ("no_visible_issue", .noFinding),
                    ("visible_issue", .findingObserved),
                    ("could_not_verify", .couldNotVerify),
                ]
            default:
                throw WorkspaceMutationContractFailureV1.invalidPlan
            }
            stages.append(try WorkspacePackageStageProfileV1(
                stageKey: entry.key,
                stageDisplay: entry.display,
                outcomes: try mappings.map { try outcome($0.0, role: $0.1) }
            ))
        }
        if hasWorkPurpose {
            stages.append(try WorkspacePackageStageProfileV1(
                stageKey: "work",
                stageDisplay: "Work",
                outcomes: [
                    try WorkspacePackageOutcomeProfileV1(
                        key: "work_recorded",
                        display: "Work recorded",
                        role: .workRecorded
                    ),
                ]
            ))
        }
        return try WorkspacePackageLifecycleProfileV1(
            package: package,
            release: PackageReleaseIdentityV1(package: package),
            stages: stages,
            evidencePurposes: try package.evidencePurposes.map { purpose in
                guard let role = purposeRoles[purpose.key] else {
                    throw WorkspaceMutationContractFailureV1.invalidPlan
                }
                return try WorkspacePackageEvidenceProfileV1(key: purpose.key, role: role)
            },
            requiredAcknowledgementKeys: acknowledgementKeys,
            pdfTemplate: PDFTemplateReferenceV1(
                id: "field.evidence.pdf.worklight.v1",
                version: 1
            )
        )
    }

    static func legacyV3Registry(
        package: SignPack
    ) throws -> WorkspacePackageLifecycleProfileRegistryV1 {
        try WorkspacePackageLifecycleProfileRegistryV1(
            profiles: [legacyV3Profile(package: package)]
        )
    }

    static func shippingProfile() throws -> WorkspacePackageLifecycleProfileV1 {
        try legacyV3Profile(package: .illuminatedSignV1)
    }

    static func shippingRegistry() throws -> WorkspacePackageLifecycleProfileRegistryV1 {
        try WorkspacePackageLifecycleProfileRegistryV1(profiles: [shippingProfile()])
    }

    private static func legacyPackageStructureIsValid(_ package: SignPack) -> Bool {
        func valid(_ value: String) -> Bool {
            !value.isEmpty
                && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
                && value.unicodeScalars.allSatisfy {
                    !CharacterSet.controlCharacters.contains($0) || $0.value == 10
                }
        }
        func unique(_ values: [String]) -> Bool {
            Set(values).count == values.count
        }
        let registries = [
            package.stageDisplays,
            package.outcomeDisplays,
            package.issueLabels,
            package.couldNotVerifyReasons.entries,
        ]
        return package.schemaVersion > 0
            && package.contentVersion > 0
            && valid(package.packID)
            && valid(package.nouns.asset.singular)
            && valid(package.nouns.asset.plural)
            && valid(package.nouns.check.singular)
            && valid(package.nouns.check.plural)
            && valid(package.nouns.issue.singular)
            && valid(package.nouns.issue.plural)
            && valid(package.couldNotVerifyReasons.version)
            && valid(package.disclaimer)
            && registries.allSatisfy { entries in
                !entries.isEmpty
                    && unique(entries.map(\.key))
                    && entries.allSatisfy { valid($0.key) && valid($0.display) }
            }
            && !package.evidencePurposes.isEmpty
            && unique(package.evidencePurposes.map(\.key))
            && package.evidencePurposes.allSatisfy {
                valid($0.key) && valid($0.display) && valid($0.instruction)
            }
            && !package.acknowledgements.isEmpty
            && unique(package.acknowledgements.map(\.key))
            && package.acknowledgements.allSatisfy {
                valid($0.key) && valid($0.copy) && valid($0.version)
            }
    }
}

struct WorkspacePackageLifecycleQueryRequestV1: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let generationID: UUID
    let operation: WorkspacePackageLifecycleOperationV1
    let identities: [WorkspaceEntityIdentityV1]

    init(
        workspaceID: WorkspaceID,
        generationID: UUID,
        operation: WorkspacePackageLifecycleOperationV1,
        identities: [WorkspaceEntityIdentityV1]
    ) throws {
        let ordered = identities.sorted { $0.stableKey < $1.stableKey }
        guard generationID != Self.zero,
              identities.count <= 256,
              Set(ordered).count == ordered.count else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        self.workspaceID = workspaceID
        self.generationID = generationID
        self.operation = operation
        self.identities = ordered
    }

    private static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

struct WorkspacePackageBindingV1: Equatable, Sendable {
    let assetID: UUID
    let packageID: String
    let packageSchemaVersion: Int
    let packageContentVersion: Int
}

struct WorkspacePackageLifecycleQueryResultV1: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let generationID: UUID
    let operation: WorkspacePackageLifecycleOperationV1
    let revision: WorkspaceRevisionV1
    let existingIdentities: [WorkspaceEntityIdentityV1]
    let packageBindings: [WorkspacePackageBindingV1]

    init(
        request: WorkspacePackageLifecycleQueryRequestV1,
        revision: WorkspaceRevisionV1,
        existingIdentities: [WorkspaceEntityIdentityV1],
        packageBindings: [WorkspacePackageBindingV1]
    ) throws {
        let identities = existingIdentities.sorted { $0.stableKey < $1.stableKey }
        let bindings = packageBindings.sorted { $0.assetID.uuidString < $1.assetID.uuidString }
        let existingAssetIDs = Set(identities.compactMap {
            $0.kind == .asset ? $0.id : nil
        })
        guard revision.workspaceID == request.workspaceID,
              revision.generationID == request.generationID,
              Set(identities).count == identities.count,
              Set(identities).isSubset(of: Set(request.identities)),
              Set(bindings.map(\.assetID)).count == bindings.count,
              bindings.allSatisfy({
                  existingAssetIDs.contains($0.assetID)
                    && !$0.packageID.isEmpty
                    && $0.packageID == $0.packageID.trimmingCharacters(in: .whitespacesAndNewlines)
                    && $0.packageSchemaVersion > 0
                    && $0.packageContentVersion > 0
              }) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        workspaceID = request.workspaceID
        generationID = request.generationID
        operation = request.operation
        self.revision = revision
        self.existingIdentities = identities
        self.packageBindings = bindings
    }
}

@MainActor
struct WorkspacePackageLifecycleDependenciesV1 {
    let workspaceID: WorkspaceID
    let generationID: UUID
    let generationRootURL: URL
    let writer: WorkspaceWriterV1
    let queryClient: any WorkspaceQueryClientV1
    let clock: any ApplicationClock
    let idSource: any ApplicationIDSource
    let fileAuthority: any ApplicationFileAuthorityV1
    let profileRegistry: WorkspacePackageLifecycleProfileRegistryV1

    init(
        workspaceID: WorkspaceID,
        generationID: UUID,
        generationRootURL: URL,
        writer: WorkspaceWriterV1,
        clock: any ApplicationClock,
        idSource: any ApplicationIDSource,
        fileAuthority: any ApplicationFileAuthorityV1,
        profileRegistry: WorkspacePackageLifecycleProfileRegistryV1
    ) throws {
        let revision = try writer.currentRevision()
        guard revision.workspaceID == workspaceID,
              revision.generationID == generationID,
              generationRootURL.isFileURL else {
            throw WorkspaceMutationFailureV1.wrongWorkspace
        }
        self.workspaceID = workspaceID
        self.generationID = generationID
        self.generationRootURL = generationRootURL.standardizedFileURL
        self.writer = writer
        queryClient = writer
        self.clock = clock
        self.idSource = idSource
        self.fileAuthority = fileAuthority
        self.profileRegistry = profileRegistry
    }
}

enum MutationReversalDispositionV1: String, Codable, Sendable {
    case reversible = "REVERSIBLE"
    case compensatable = "COMPENSATABLE"
    case irreversible = "IRREVERSIBLE"
}

struct MutationReversalPolicyV1: Codable, Equatable, Sendable {
    let commandKind: WorkspaceCommandKindV1
    let disposition: MutationReversalDispositionV1
    let stableReason: String
}

enum MutationReversalPolicyRegistryV1 {
    static let version = 1

    static let policies: [MutationReversalPolicyV1] = [
        .init(commandKind: .createFirstSign, disposition: .compensatable, stableReason: "dependency_checked_delete_only"),
        .init(commandKind: .createCheckDraft, disposition: .reversible, stableReason: "archive_unfinalized_draft"),
        .init(commandKind: .acceptCheckEvidence, disposition: .irreversible, stableReason: "immutable_evidence_original"),
        .init(commandKind: .updateSiteTimeZone, disposition: .reversible, stableReason: "restore_prior_timezone_if_unchanged"),
        .init(commandKind: .deleteAsset, disposition: .irreversible, stableReason: "deletion_ledger_and_purged_content"),
        .init(commandKind: .deleteSite, disposition: .irreversible, stableReason: "explicit_site_deletion"),
        .init(commandKind: .eraseWorkspace, disposition: .irreversible, stableReason: "erase_cannot_be_reversed"),
        .init(commandKind: .finalizeCheck, disposition: .irreversible, stableReason: "finalized_artifact_amendment_only"),
        .init(commandKind: .finalizeCorrection, disposition: .irreversible, stableReason: "correction_supersession_only"),
        .init(commandKind: .recordWork, disposition: .irreversible, stableReason: "completed_work_supersession_only"),
        .init(commandKind: .restoreWorkspace, disposition: .irreversible, stableReason: "generation_restore_cannot_be_reversed"),
        .init(commandKind: .archiveEntities, disposition: .compensatable, stableReason: "append_semantic_successor_only"),
        .init(commandKind: .applyLocationHierarchyChange, disposition: .compensatable, stableReason: "append_hierarchy_successor_only"),
        .init(commandKind: .applyAssetPlacementChange, disposition: .compensatable, stableReason: "append_placement_successor_only"),
        .init(commandKind: .applyAssetCompositionChange, disposition: .compensatable, stableReason: "append_composition_successor_only"),
        .init(commandKind: .applySavedSmartView, disposition: .compensatable, stableReason: "replace_or_delete_saved_smart_view"),
    ]

    static func policy(for kind: WorkspaceCommandKindV1) throws -> MutationReversalPolicyV1 {
        guard policies.count == WorkspaceCommandKindV1.allCases.count,
              Set(policies.map(\.commandKind)).count == policies.count,
              let policy = policies.first(where: { $0.commandKind == kind }) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        return policy
    }
}

struct SemanticReversalValueV1: Codable, Equatable, Sendable {
    let key: String
    let value: String
}

struct SemanticReversalDependencyV1: Codable, Equatable, Sendable {
    let predecessor: WorkspaceEntityIdentityV1
    let successor: WorkspaceEntityIdentityV1
}

struct SemanticReversalPlanV1: Equatable, Sendable {
    static let maximumItems = 256
    static let maximumTextLength = 4_096

    let schemaVersion: Int
    let mutationID: MutationIDV1
    let commandKind: WorkspaceCommandKindV1
    let disposition: MutationReversalDispositionV1
    let expectedRevision: WorkspaceExpectedRevisionV1
    let prospectiveTargets: [WorkspaceEntityIdentityV1]
    let requiredSemanticValues: [SemanticReversalValueV1]
    let contentReferences: [String]
    let dependencyGraph: [SemanticReversalDependencyV1]
    let conflicts: [String]
    let compensatingCommands: [WorkspaceCommandV1]
    let planDigest: String

    init(
        mutationID: MutationIDV1,
        commandKind: WorkspaceCommandKindV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        prospectiveTargets: [WorkspaceEntityIdentityV1],
        requiredSemanticValues: [SemanticReversalValueV1],
        contentReferences: [String],
        dependencyGraph: [SemanticReversalDependencyV1],
        conflicts: [String],
        compensatingCommands: [WorkspaceCommandV1]
    ) throws {
        let policy = try MutationReversalPolicyRegistryV1.policy(for: commandKind)
        let counts = [prospectiveTargets.count, requiredSemanticValues.count, contentReferences.count,
                      dependencyGraph.count, conflicts.count, compensatingCommands.count]
        guard counts.allSatisfy({ $0 <= Self.maximumItems }),
              requiredSemanticValues.allSatisfy({ !$0.key.isEmpty && $0.key.count <= Self.maximumTextLength && $0.value.count <= Self.maximumTextLength }),
              (contentReferences + conflicts).allSatisfy({ !$0.isEmpty && $0.count <= Self.maximumTextLength }),
              policy.disposition != .irreversible || compensatingCommands.isEmpty else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        let targets = prospectiveTargets.sorted { $0.stableKey < $1.stableKey }
        let values = requiredSemanticValues.sorted { ($0.key, $0.value) < ($1.key, $1.value) }
        let references = contentReferences.sorted()
        let dependencies = dependencyGraph.sorted {
            ($0.predecessor.stableKey, $0.successor.stableKey) < ($1.predecessor.stableKey, $1.successor.stableKey)
        }
        let sortedConflicts = conflicts.sorted()
        let basis = DigestBasis(
            schemaVersion: 1,
            mutationID: mutationID,
            commandKind: commandKind,
            disposition: policy.disposition,
            expectedRevision: expectedRevision,
            prospectiveTargets: targets,
            requiredSemanticValues: values,
            contentReferences: references,
            dependencyGraph: dependencies,
            conflicts: sortedConflicts,
            compensatingCommands: compensatingCommands
        )
        schemaVersion = 1
        self.mutationID = mutationID
        self.commandKind = commandKind
        disposition = policy.disposition
        self.expectedRevision = expectedRevision
        self.prospectiveTargets = targets
        self.requiredSemanticValues = values
        self.contentReferences = references
        self.dependencyGraph = dependencies
        self.conflicts = sortedConflicts
        self.compensatingCommands = compensatingCommands
        planDigest = try WorkspaceMutationCanonicalV1.sha256(basis)
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let mutationID: MutationIDV1
        let commandKind: WorkspaceCommandKindV1
        let disposition: MutationReversalDispositionV1
        let expectedRevision: WorkspaceExpectedRevisionV1
        let prospectiveTargets: [WorkspaceEntityIdentityV1]
        let requiredSemanticValues: [SemanticReversalValueV1]
        let contentReferences: [String]
        let dependencyGraph: [SemanticReversalDependencyV1]
        let conflicts: [String]
        let compensatingCommands: [WorkspaceCommandV1]
    }
}

struct MutationBoundaryClosureReceiptV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let writerType: String
    let writersPerWorkspaceGeneration: Int
    let unreservedProductionFeatureOwnedInsertSaveDeleteCount: Int
    let deferredReservedDirectWritePaths: [String]
    let fullyClosed: Bool
    let reconciliationRequired: Bool
    let temporaryAdapterType: String
    let durableMutationSchemaPresent: Bool

    static let kernel = MutationBoundaryClosureReceiptV1(
        schemaVersion: 1,
        writerType: "WorkspaceWriterV1",
        writersPerWorkspaceGeneration: 1,
        unreservedProductionFeatureOwnedInsertSaveDeleteCount: 0,
        deferredReservedDirectWritePaths: [
            "FieldEvidenceApp/Features/Issues/WorkCoordinator.swift",
            "FieldEvidenceApp/Features/Shell/AppShellView.swift",
        ],
        fullyClosed: false,
        reconciliationRequired: true,
        temporaryAdapterType: "WorkspaceWriterAdapterV1",
        durableMutationSchemaPresent: true
    )
}

enum WorkspaceMutationCanonicalV1 {
    static func data<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func sha256<T: Encodable>(_ value: T) throws -> String {
        SHA256.hash(data: try data(value)).map { String(format: "%02x", $0) }.joined()
    }
}

extension WorkspaceID: Codable {
    private enum CodingKeys: String, CodingKey { case rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(rawValue: try container.decode(UUID.self, forKey: .rawValue))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawValue, forKey: .rawValue)
    }
}

extension ReplicaID: Codable {
    private enum CodingKeys: String, CodingKey { case rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(rawValue: container.decode(UUID.self, forKey: .rawValue))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawValue, forKey: .rawValue)
    }
}

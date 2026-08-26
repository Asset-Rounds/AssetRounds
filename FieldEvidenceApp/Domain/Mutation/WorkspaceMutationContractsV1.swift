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

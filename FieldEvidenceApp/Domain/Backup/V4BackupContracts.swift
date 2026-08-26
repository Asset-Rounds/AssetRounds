import Foundation

struct V4BackupSiteDTO: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let schemaVersion: Int
    let label: String
    let address: String?
    let timeZoneID: String?
    let createdAt: Date
    let updatedAt: Date
}

struct V4BackupAssetDTO: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let schemaVersion: Int
    let siteID: UUID
    let packID: String
    let packSchemaVersion: Int
    let packContentVersion: Int
    let label: String
    let createdAt: Date
    let updatedAt: Date
}

struct V4BackupWorkflowRecordDTO: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let schemaVersion: Int
    let assetID: UUID
    let packetID: UUID?
    let issueID: UUID?
    let parentRecordID: UUID?
    let recordRevisionRootID: UUID
    let revisesRecordID: UUID?
    let evidenceSourceRecordID: UUID?
    let revisionKind: String
    let stage: String
    let state: String
    let draftStepKey: String?
    let startedAt: Date
    let completedAt: Date?
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
    let outcomeKey: String?
    let couldNotVerifyKey: String?
    let couldNotVerifyDisplaySnapshot: String?
    let couldNotVerifyRegistryVersion: String?
    let workPerformedLocalDate: String?
    let workDescription: String?
    let note: String?
    let finalizationMutationID: UUID?
}

struct V4BackupEvidenceFileDTO: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let schemaVersion: Int
    let recordID: UUID
    let purposeKey: String
    let relativePath: String
    let mimeType: String
    let byteCount: Int
    let sha256: String
    let createdAt: Date
    let thumbnailRelativePath: String
    let thumbnailByteCount: Int
    let thumbnailSHA256: String
}

struct V4BackupIssueDTO: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let schemaVersion: Int
    let assetID: UUID
    let openedByRecordID: UUID
    let labelKey: String
    let labelDisplaySnapshot: String
    let status: String
    let resolvedByRecordID: UUID?
    let createdAt: Date
    let updatedAt: Date
}

struct V4BackupPacketDTO: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let schemaVersion: Int
    let stableRootID: UUID
    let currentRecordID: UUID?
    let evaluationCounted: Bool
    let contentDeletedAt: Date?
    let createdAt: Date
}

struct V4BackupReportDTO: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let schemaVersion: Int
    let packetID: UUID
    let sourceRecordID: UUID
    let snapshotSchemaVersion: Int
    let snapshotRelativePath: String
    let snapshotSHA256: String
    let pdfState: String
    let pdfRelativePath: String?
    let pdfSHA256: String?
    let createdAt: Date
    let replacesReportID: UUID?
}

struct V4BackupRecordsV1: Codable, Equatable, Sendable {
    let assets: [V4BackupAssetDTO]
    let deletionLedger: DeletionLedgerV2?
    let evidenceFiles: [V4BackupEvidenceFileDTO]
    let issues: [V4BackupIssueDTO]
    let mutationHistory: MutationHistorySnapshotV1?
    let packets: [V4BackupPacketDTO]
    let recordsSchemaVersion: Int
    let reports: [V4BackupReportDTO]
    let sites: [V4BackupSiteDTO]
    let workflowRecords: [V4BackupWorkflowRecordDTO]

    init(
        assets: [V4BackupAssetDTO],
        deletionLedger: DeletionLedgerV2? = nil,
        evidenceFiles: [V4BackupEvidenceFileDTO],
        issues: [V4BackupIssueDTO],
        mutationHistory: MutationHistorySnapshotV1? = nil,
        packets: [V4BackupPacketDTO],
        recordsSchemaVersion: Int,
        reports: [V4BackupReportDTO],
        sites: [V4BackupSiteDTO],
        workflowRecords: [V4BackupWorkflowRecordDTO]
    ) {
        self.assets = assets
        self.deletionLedger = deletionLedger
        self.evidenceFiles = evidenceFiles
        self.issues = issues
        self.mutationHistory = mutationHistory
        self.packets = packets
        self.recordsSchemaVersion = recordsSchemaVersion
        self.reports = reports
        self.sites = sites
        self.workflowRecords = workflowRecords
    }
}

struct V4BackupEntryV1: Codable, Equatable, Sendable {
    let byteCount: Int
    let mimeType: String
    let path: String
    let sha256: String
}

struct V4BackupPackV1: Codable, Equatable, Sendable {
    let contentVersion: Int
    let packID: String
    let schemaVersion: Int
}

struct V4BackupSourceV1: Codable, Equatable, Sendable {
    let appBuild: String
    let appVersion: String
    let persistentSchemaVersion: Int
    let replicaID: UUID?
    let recordsSchemaVersion: Int
    let workspaceID: UUID?

    init(
        appBuild: String,
        appVersion: String,
        persistentSchemaVersion: Int,
        replicaID: UUID? = nil,
        recordsSchemaVersion: Int,
        workspaceID: UUID? = nil
    ) {
        self.appBuild = appBuild
        self.appVersion = appVersion
        self.persistentSchemaVersion = persistentSchemaVersion
        self.replicaID = replicaID
        self.recordsSchemaVersion = recordsSchemaVersion
        self.workspaceID = workspaceID
    }
}

struct V4BackupManifestV1: Codable, Equatable, Sendable {
    let backupSchemaVersion: Int
    let consumedEvaluationRootIDs: [UUID]
    let declaredPayloadByteCount: Int
    let entries: [V4BackupEntryV1]
    let exportedAt: Date
    let packs: [V4BackupPackV1]
    let source: V4BackupSourceV1
}

struct BackupExportPreviewV1: Equatable, Sendable {
    let id: UUID
    let signCount: Int
    let reportCount: Int
    let photoCount: Int
    let declaredPayloadByteCount: Int
}

struct V4BackupPackageMemberV1: Equatable, Sendable {
    let path: String
    let mimeType: String
    let data: Data
}

struct PreparedV4BackupV1: Equatable, Sendable {
    let preview: BackupExportPreviewV1
    let records: V4BackupRecordsV1
    let manifest: V4BackupManifestV1
    let members: [V4BackupPackageMemberV1]
}

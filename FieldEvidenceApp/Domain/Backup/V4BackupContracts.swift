import Foundation

struct V5BackupLocationRecordV1: Codable, Equatable, Sendable {
    let id: UUID
    let canonicalData: Data
    let secondaryCanonicalData: Data?

    init(
        id: UUID,
        canonicalData: Data,
        secondaryCanonicalData: Data? = nil
    ) {
        self.id = id
        self.canonicalData = canonicalData
        self.secondaryCanonicalData = secondaryCanonicalData
    }
}

struct V7BackupSavedSmartViewRecordV1: Codable, Equatable, Sendable {
    let id: UUID
    let canonicalData: Data

    init(_ descriptor: SavedSmartViewDescriptorV1) throws {
        try descriptor.validate()
        id = descriptor.id
        canonicalData = try SearchPersistenceCodecV1.encode(descriptor)
    }

    func descriptor() throws -> SavedSmartViewDescriptorV1 {
        let value = try SearchPersistenceCodecV1.decodeCanonical(
            SavedSmartViewDescriptorV1.self,
            from: canonicalData
        )
        guard value.id == id else { throw SearchContractFailureV1.invalidSmartView }
        return value
    }
}

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
    /// Exact canonical ObservationAndTimeCodecV1 bytes. Legacy records omit it.
    var observationBasisV1Data: Data? = nil
    /// Exact canonical ObservationAndTimeCodecV1 bytes. Legacy records omit it.
    var temporalContextV1Data: Data? = nil

    func replacingObservationAndTime(
        basisData: Data?,
        temporalData: Data?
    ) -> Self {
        Self(
            id: id, schemaVersion: schemaVersion, assetID: assetID,
            packetID: packetID, issueID: issueID,
            parentRecordID: parentRecordID,
            recordRevisionRootID: recordRevisionRootID,
            revisesRecordID: revisesRecordID,
            evidenceSourceRecordID: evidenceSourceRecordID,
            revisionKind: revisionKind, stage: stage, state: state,
            draftStepKey: draftStepKey, startedAt: startedAt,
            completedAt: completedAt, observedAtUTC: observedAtUTC,
            timeZoneID: timeZoneID, utcOffsetMinutes: utcOffsetMinutes,
            localDate: localDate, localTime: localTime,
            afterDarkAcknowledgementKey: afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: safePositionAcknowledgementAccepted,
            packID: packID, packSchemaVersion: packSchemaVersion,
            packContentVersion: packContentVersion,
            pdfTemplateID: pdfTemplateID, pdfTemplateVersion: pdfTemplateVersion,
            outcomeKey: outcomeKey, couldNotVerifyKey: couldNotVerifyKey,
            couldNotVerifyDisplaySnapshot: couldNotVerifyDisplaySnapshot,
            couldNotVerifyRegistryVersion: couldNotVerifyRegistryVersion,
            workPerformedLocalDate: workPerformedLocalDate,
            workDescription: workDescription, note: note,
            finalizationMutationID: finalizationMutationID,
            observationBasisV1Data: basisData,
            temporalContextV1Data: temporalData
        )
    }
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
    let assetCompositionEdges: [V5BackupLocationRecordV1]
    let assetCompositionEvents: [V5BackupLocationRecordV1]
    let assetPlacementEvents: [V5BackupLocationRecordV1]
    let assets: [V4BackupAssetDTO]
    let deletionLedger: DeletionLedgerV2?
    let evidenceFiles: [V4BackupEvidenceFileDTO]
    let issues: [V4BackupIssueDTO]
    let locationHierarchyEvents: [V5BackupLocationRecordV1]
    let locationMigrationReceipts: [V5BackupLocationRecordV1]
    let locationNodes: [V5BackupLocationRecordV1]
    let mutationHistory: MutationHistorySnapshotV1?
    let packets: [V4BackupPacketDTO]
    let recordsSchemaVersion: Int
    let reports: [V4BackupReportDTO]
    let savedSmartViews: [V7BackupSavedSmartViewRecordV1]
    let sites: [V4BackupSiteDTO]
    let workflowRecords: [V4BackupWorkflowRecordDTO]

    init(
        assetCompositionEdges: [V5BackupLocationRecordV1] = [],
        assetCompositionEvents: [V5BackupLocationRecordV1] = [],
        assetPlacementEvents: [V5BackupLocationRecordV1] = [],
        assets: [V4BackupAssetDTO],
        deletionLedger: DeletionLedgerV2? = nil,
        evidenceFiles: [V4BackupEvidenceFileDTO],
        issues: [V4BackupIssueDTO],
        locationHierarchyEvents: [V5BackupLocationRecordV1] = [],
        locationMigrationReceipts: [V5BackupLocationRecordV1] = [],
        locationNodes: [V5BackupLocationRecordV1] = [],
        mutationHistory: MutationHistorySnapshotV1? = nil,
        packets: [V4BackupPacketDTO],
        recordsSchemaVersion: Int,
        reports: [V4BackupReportDTO],
        savedSmartViews: [V7BackupSavedSmartViewRecordV1] = [],
        sites: [V4BackupSiteDTO],
        workflowRecords: [V4BackupWorkflowRecordDTO]
    ) {
        self.assetCompositionEdges = assetCompositionEdges
        self.assetCompositionEvents = assetCompositionEvents
        self.assetPlacementEvents = assetPlacementEvents
        self.assets = assets
        self.deletionLedger = deletionLedger
        self.evidenceFiles = evidenceFiles
        self.issues = issues
        self.locationHierarchyEvents = locationHierarchyEvents
        self.locationMigrationReceipts = locationMigrationReceipts
        self.locationNodes = locationNodes
        self.mutationHistory = mutationHistory
        self.packets = packets
        self.recordsSchemaVersion = recordsSchemaVersion
        self.reports = reports
        self.savedSmartViews = savedSmartViews
        self.sites = sites
        self.workflowRecords = workflowRecords
    }

    private enum CodingKeys: String, CodingKey {
        case assetCompositionEdges, assetCompositionEvents, assetPlacementEvents, assets
        case deletionLedger, evidenceFiles, issues, locationHierarchyEvents
        case locationMigrationReceipts, locationNodes, mutationHistory, packets
        case recordsSchemaVersion, reports, savedSmartViews, sites, workflowRecords
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .recordsSchemaVersion)
        self.init(
            assetCompositionEdges: try values.decodeIfPresent([V5BackupLocationRecordV1].self, forKey: .assetCompositionEdges) ?? [],
            assetCompositionEvents: try values.decodeIfPresent([V5BackupLocationRecordV1].self, forKey: .assetCompositionEvents) ?? [],
            assetPlacementEvents: try values.decodeIfPresent([V5BackupLocationRecordV1].self, forKey: .assetPlacementEvents) ?? [],
            assets: try values.decode([V4BackupAssetDTO].self, forKey: .assets),
            deletionLedger: try values.decodeIfPresent(DeletionLedgerV2.self, forKey: .deletionLedger),
            evidenceFiles: try values.decode([V4BackupEvidenceFileDTO].self, forKey: .evidenceFiles),
            issues: try values.decode([V4BackupIssueDTO].self, forKey: .issues),
            locationHierarchyEvents: try values.decodeIfPresent([V5BackupLocationRecordV1].self, forKey: .locationHierarchyEvents) ?? [],
            locationMigrationReceipts: try values.decodeIfPresent([V5BackupLocationRecordV1].self, forKey: .locationMigrationReceipts) ?? [],
            locationNodes: try values.decodeIfPresent([V5BackupLocationRecordV1].self, forKey: .locationNodes) ?? [],
            mutationHistory: try values.decodeIfPresent(MutationHistorySnapshotV1.self, forKey: .mutationHistory),
            packets: try values.decode([V4BackupPacketDTO].self, forKey: .packets),
            recordsSchemaVersion: version,
            reports: try values.decode([V4BackupReportDTO].self, forKey: .reports),
            savedSmartViews: try values.decodeIfPresent(
                [V7BackupSavedSmartViewRecordV1].self,
                forKey: .savedSmartViews
            ) ?? [],
            sites: try values.decode([V4BackupSiteDTO].self, forKey: .sites),
            workflowRecords: try values.decode([V4BackupWorkflowRecordDTO].self, forKey: .workflowRecords)
        )
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
    let sourceGenerationID: UUID?
    let workspaceID: UUID?

    init(
        appBuild: String,
        appVersion: String,
        persistentSchemaVersion: Int,
        replicaID: UUID? = nil,
        recordsSchemaVersion: Int,
        sourceGenerationID: UUID? = nil,
        workspaceID: UUID? = nil
    ) {
        self.appBuild = appBuild
        self.appVersion = appVersion
        self.persistentSchemaVersion = persistentSchemaVersion
        self.replicaID = replicaID
        self.recordsSchemaVersion = recordsSchemaVersion
        self.sourceGenerationID = sourceGenerationID
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

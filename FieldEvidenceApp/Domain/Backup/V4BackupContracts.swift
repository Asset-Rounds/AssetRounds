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

struct V8BackupRequirementAssuranceRecordV1: Codable, Equatable, Sendable {
    let workflowRecordID: UUID
    let canonicalData: Data
    let snapshotSHA256: String
    let mutationID: UUID
    let createdAt: Date
    let updatedAt: Date

    init(_ row: RequirementAssuranceRow) throws {
        let snapshot = try row.snapshot()
        workflowRecordID = snapshot.workflowRecordID
        canonicalData = try RequirementAssuranceCanonicalV1.data(snapshot)
        snapshotSHA256 = snapshot.snapshotSHA256
        mutationID = row.mutationID
        createdAt = row.createdAt
        updatedAt = row.updatedAt
        try validate()
    }

    init(
        workflowRecordID: UUID,
        canonicalData: Data,
        snapshotSHA256: String,
        mutationID: UUID,
        createdAt: Date,
        updatedAt: Date
    ) throws {
        self.workflowRecordID = workflowRecordID
        self.canonicalData = canonicalData
        self.snapshotSHA256 = snapshotSHA256
        self.mutationID = mutationID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        try validate()
    }

    func snapshot() throws -> RequirementAssuranceSnapshotV1 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(RequirementAssuranceSnapshotV1.self, from: canonicalData)
        try value.validate()
        guard try RequirementAssuranceCanonicalV1.data(value) == canonicalData,
              value.workflowRecordID == workflowRecordID,
              value.snapshotSHA256 == snapshotSHA256 else {
            throw RequirementAssuranceFailureV1.digestMismatch
        }
        return value
    }

    func validate() throws {
        let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        guard workflowRecordID != zero, mutationID != zero, createdAt <= updatedAt,
              !canonicalData.isEmpty,
              canonicalData.count <= SnapshotProjectionLimitsV1.maximumProjectionBytes,
              KernelCanonicalHashV1.validSHA256(snapshotSHA256) else {
            throw RequirementAssuranceFailureV1.invalidValue
        }
        _ = try snapshot()
    }
}

/// Canonical V9 party/accountability rows. Keeping the canonical domain bytes
/// in the package preserves historical display/provenance without allowing a
/// restore to reinterpret a local assertion as verified identity or signoff.
struct V9BackupPartyAccountabilityRecordV1: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case serviceParty = "SERVICE_PARTY"
        case sitePartyRoleEvent = "SITE_PARTY_ROLE_EVENT"
        case actorSnapshot = "ACTOR_SNAPSHOT"
        case qualificationSnapshot = "QUALIFICATION_SNAPSHOT"
        case signoffSnapshot = "SIGNOFF_SNAPSHOT"
    }

    let kind: Kind
    let id: UUID
    let workspaceID: UUID
    let revision: UInt64?
    let canonicalData: Data
}

struct V10BackupAssetSemanticRecordV1: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case kindBindingEvent = "ASSET_KIND_BINDING_EVENT"
        case workflowCapabilityBindingEvent = "ASSET_WORKFLOW_CAPABILITY_BINDING_EVENT"
        case productIdentity = "ASSET_PRODUCT_IDENTITY"
        case lifecycleEvent = "ASSET_LIFECYCLE_EVENT"
        case successorLink = "ASSET_SUCCESSOR_LINK"
        case workSubjectScopeSnapshot = "WORK_SUBJECT_SCOPE_SNAPSHOT"
    }

    let kind: Kind
    let id: UUID
    let workspaceID: UUID
    let revision: UInt64
    let canonicalData: Data
}

struct V11BackupAuthorityCriterionRecordV1: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case authoritySourceRelease = "AUTHORITY_SOURCE_RELEASE"
        case requirementBasisBinding = "REQUIREMENT_BASIS_BINDING"
        case applicabilityContextSnapshot = "APPLICABILITY_CONTEXT_SNAPSHOT"
        case assessmentScopeSnapshot = "ASSESSMENT_SCOPE_SNAPSHOT"
        case severityScaleRelease = "SEVERITY_SCALE_RELEASE"
        case findingClassificationBinding = "FINDING_CLASSIFICATION_BINDING"
        case measurementProtocolRelease = "MEASUREMENT_PROTOCOL_RELEASE"
        case derivedFactEvaluatorDescriptor = "DERIVED_FACT_EVALUATOR_DESCRIPTOR"
        case derivedFactProvenance = "DERIVED_FACT_PROVENANCE"
    }
    let kind: Kind
    let id: UUID
    let workspaceID: UUID
    let canonicalData: Data
}

struct V12BackupFunctionalRelationshipRecordV1: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case descriptor = "FUNCTIONAL_RELATIONSHIP_DESCRIPTOR"
        case event = "ASSET_FUNCTIONAL_RELATIONSHIP_EVENT"
    }
    let kind: Kind
    let id: UUID
    let workspaceID: UUID
    let revision: UInt64
    let canonicalData: Data
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

struct V13BackupEvidenceAssuranceRecordV1: Codable, Equatable, Sendable {
    enum Kind: String, CaseIterable, Codable, Sendable {
        case visibility, evidenceLink, manifest, attestation
    }
    let kind: Kind
    let id: UUID
    let workspaceID: UUID
    let revision: UInt64
    let canonicalData: Data
}

struct V14BackupInspectionReviewRecordV1: Codable, Equatable, Sendable {
    enum Kind: String, CaseIterable, Codable, Sendable {
        case reviewTransition, reviewDisposition, changeRequest, correctiveActionPolicy, correctiveActionEvent
    }
    let kind: Kind
    let id: UUID
    let workspaceID: UUID
    let revision: UInt64
    let canonicalData: Data
}

struct V15BackupWorkPacketRecordV1: Codable, Equatable, Sendable {
    enum Kind: String, CaseIterable, Codable, Sendable {
        case manifest, claim, lease, release, handoff
    }
    let kind: Kind
    let id: UUID
    let workspaceID: UUID
    let revision: UInt64
    let canonicalData: Data
}

struct V16BackupFieldDraftRecordV1: Codable, Equatable, Sendable {
    enum Kind: String, CaseIterable, Codable, Sendable {
        case checkpoint, stagingItem, commitSaga, contentReservation, commitReceipt, discardReceipt
    }
    let kind: Kind
    let id: UUID
    let workspaceID: UUID
    let revision: UInt64
    let canonicalData: Data
}

struct V17BackupPackageEvolutionRecordV1: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case promotedRelease, sandboxRun, promotionReceipt, activePointer
    }
    let kind: Kind
    let id: UUID
    let workspaceID: UUID
    let revision: UInt64
    let canonicalData: Data
}

struct V18BackupMeasurementIntegrityRecordV1: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case instrumentReference, calibrationSnapshot, measurementCapture, measurementSeries, qualityAssessment
    }
    let kind: Kind
    let id: UUID
    let workspaceID: UUID
    let revision: UInt64
    let canonicalData: Data
}

struct V19BackupPrivacyTransformRecordV1: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case policy, region, manifest, reviewReceipt
    }
    let kind: Kind
    let id: UUID
    let workspaceID: UUID
    let revision: UInt64
    let canonicalData: Data
}

struct V20BackupClientCapabilityRecordV1: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable { case profile, policy, disposition, admissionDecision }
    let kind: Kind; let id: UUID; let workspaceID: UUID; let revision: UInt64; let canonicalData: Data
}

struct V4BackupRecordsV1: Codable, Equatable, Sendable {
    let clientCapabilities: [V20BackupClientCapabilityRecordV1]
    let privacyTransforms: [V19BackupPrivacyTransformRecordV1]
    let measurementIntegrity: [V18BackupMeasurementIntegrityRecordV1]
    let packageEvolution: [V17BackupPackageEvolutionRecordV1]
    let fieldDrafts: [V16BackupFieldDraftRecordV1]
    let workPackets: [V15BackupWorkPacketRecordV1]
    let inspectionReview: [V14BackupInspectionReviewRecordV1]
    let evidenceAssurance: [V13BackupEvidenceAssuranceRecordV1]
    let functionalRelationships: [V12BackupFunctionalRelationshipRecordV1]
    let authorityCriterion: [V11BackupAuthorityCriterionRecordV1]
    let assetSemantics: [V10BackupAssetSemanticRecordV1]
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
    let partyAccountability: [V9BackupPartyAccountabilityRecordV1]
    let recordsSchemaVersion: Int
    let reports: [V4BackupReportDTO]
    let requirementAssurance: [V8BackupRequirementAssuranceRecordV1]
    let savedSmartViews: [V7BackupSavedSmartViewRecordV1]
    let sites: [V4BackupSiteDTO]
    let workflowRecords: [V4BackupWorkflowRecordDTO]

    init(
        clientCapabilities: [V20BackupClientCapabilityRecordV1] = [],
        privacyTransforms: [V19BackupPrivacyTransformRecordV1] = [],
        measurementIntegrity: [V18BackupMeasurementIntegrityRecordV1] = [],
        packageEvolution: [V17BackupPackageEvolutionRecordV1] = [],
        fieldDrafts: [V16BackupFieldDraftRecordV1] = [],
        workPackets: [V15BackupWorkPacketRecordV1] = [],
        inspectionReview: [V14BackupInspectionReviewRecordV1] = [],
        evidenceAssurance: [V13BackupEvidenceAssuranceRecordV1] = [],
        functionalRelationships: [V12BackupFunctionalRelationshipRecordV1] = [],
        authorityCriterion: [V11BackupAuthorityCriterionRecordV1] = [],
        assetSemantics: [V10BackupAssetSemanticRecordV1] = [],
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
        partyAccountability: [V9BackupPartyAccountabilityRecordV1] = [],
        recordsSchemaVersion: Int,
        reports: [V4BackupReportDTO],
        requirementAssurance: [V8BackupRequirementAssuranceRecordV1] = [],
        savedSmartViews: [V7BackupSavedSmartViewRecordV1] = [],
        sites: [V4BackupSiteDTO],
        workflowRecords: [V4BackupWorkflowRecordDTO]
    ) {
        self.clientCapabilities = clientCapabilities
        self.privacyTransforms = privacyTransforms
        self.measurementIntegrity = measurementIntegrity
        self.packageEvolution = packageEvolution
        self.fieldDrafts = fieldDrafts
        self.workPackets = workPackets
        self.inspectionReview = inspectionReview
        self.evidenceAssurance = evidenceAssurance
        self.functionalRelationships = functionalRelationships
        self.authorityCriterion = authorityCriterion
        self.assetSemantics = assetSemantics
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
        self.partyAccountability = partyAccountability
        self.recordsSchemaVersion = recordsSchemaVersion
        self.reports = reports
        self.requirementAssurance = requirementAssurance
        self.savedSmartViews = savedSmartViews
        self.sites = sites
        self.workflowRecords = workflowRecords
    }

    private enum CodingKeys: String, CodingKey {
        case clientCapabilities, privacyTransforms, measurementIntegrity, packageEvolution, fieldDrafts, workPackets, inspectionReview, evidenceAssurance, functionalRelationships, authorityCriterion, assetSemantics, assetCompositionEdges, assetCompositionEvents, assetPlacementEvents, assets
        case deletionLedger, evidenceFiles, issues, locationHierarchyEvents
        case locationMigrationReceipts, locationNodes, mutationHistory, packets, partyAccountability
        case recordsSchemaVersion, reports, requirementAssurance, savedSmartViews, sites
        case workflowRecords
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .recordsSchemaVersion)
        self.init(
            clientCapabilities: try values.decodeIfPresent([V20BackupClientCapabilityRecordV1].self, forKey: .clientCapabilities) ?? [],
            privacyTransforms: try values.decodeIfPresent(
                [V19BackupPrivacyTransformRecordV1].self, forKey: .privacyTransforms
            ) ?? [],
            measurementIntegrity: try values.decodeIfPresent(
                [V18BackupMeasurementIntegrityRecordV1].self, forKey: .measurementIntegrity
            ) ?? [],
            packageEvolution: try values.decodeIfPresent(
                [V17BackupPackageEvolutionRecordV1].self, forKey: .packageEvolution
            ) ?? [],
            fieldDrafts: try values.decodeIfPresent(
                [V16BackupFieldDraftRecordV1].self, forKey: .fieldDrafts
            ) ?? [],
            workPackets: try values.decodeIfPresent(
                [V15BackupWorkPacketRecordV1].self, forKey: .workPackets
            ) ?? [],
            inspectionReview: try values.decodeIfPresent(
                [V14BackupInspectionReviewRecordV1].self, forKey: .inspectionReview
            ) ?? [],
            evidenceAssurance: try values.decodeIfPresent(
                [V13BackupEvidenceAssuranceRecordV1].self, forKey: .evidenceAssurance
            ) ?? [],
            functionalRelationships: try values.decodeIfPresent(
                [V12BackupFunctionalRelationshipRecordV1].self, forKey: .functionalRelationships
            ) ?? [],
            authorityCriterion: try values.decodeIfPresent(
                [V11BackupAuthorityCriterionRecordV1].self, forKey: .authorityCriterion
            ) ?? [],
            assetSemantics: try values.decodeIfPresent(
                [V10BackupAssetSemanticRecordV1].self, forKey: .assetSemantics
            ) ?? [],
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
            partyAccountability: try values.decodeIfPresent(
                [V9BackupPartyAccountabilityRecordV1].self,
                forKey: .partyAccountability
            ) ?? [],
            recordsSchemaVersion: version,
            reports: try values.decode([V4BackupReportDTO].self, forKey: .reports),
            requirementAssurance: try values.decodeIfPresent(
                [V8BackupRequirementAssuranceRecordV1].self,
                forKey: .requirementAssurance
            ) ?? [],
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

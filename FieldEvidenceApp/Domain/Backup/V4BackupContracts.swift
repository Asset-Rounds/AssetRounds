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
       enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
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

enum V4BackupEvidenceMemberKeyV1{
    static func original(_ evidenceID:UUID)->String{"media/\(evidenceID.uuidString.lowercased()).jpg"}
    static func thumbnail(_ evidenceID:UUID)->String{"thumbnails/\(evidenceID.uuidString.lowercased()).jpg"}
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

struct V21BackupRecoverabilityReceiptRecordV1: Codable, Equatable, Sendable {
    let id: UUID; let workspaceID: UUID; let revision: UInt64; let canonicalData: Data
}
struct V22BackupFieldReferenceRecordV1:Codable,Equatable,Sendable{enum Kind:String,Codable,CaseIterable,Sendable{case release,binding};let kind:Kind;let id:UUID;let workspaceID:UUID;let revision:UInt64;let canonicalData:Data}
struct V23BackupAccessibleDocumentAssessmentRecordV1:Codable,Equatable,Sendable{let id:UUID;let workspaceID:UUID;let revision:UInt64;let canonicalData:Data}
struct V24BackupSurveyDefinitionRecordV1:Codable,Equatable,Sendable{enum Kind:String,Codable,CaseIterable,Sendable{case identity,release};let kind:Kind;let id:UUID;let workspaceID:UUID;let revision:UInt64;let canonicalData:Data}
struct V25BackupGuidedSurveyRecordV1:Codable,Equatable,Sendable{
    enum Kind:String,Codable,CaseIterable,Hashable,Sendable{case session,factCapture,provisionalSubject,subjectPromotionReceipt,publicationSnapshot}
    let kind:Kind;let id:UUID;let workspaceID:UUID;let revision:UInt64;let canonicalData:Data
}

/// C27 locator records are the transport projection of the two durable
/// workspace families. Resolution results and rebinding previews are derived
/// values and deliberately never enter a backup package.
struct V26BackupAssetLocatorRecordV1: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        case locator = "ASSET_LOCATOR"
        case bindingReceipt = "LOCATOR_BINDING_RECEIPT"
    }

    let kind: Kind
    let id: UUID
    let workspaceID: UUID
    let revision: UInt64
    let canonicalData: Data
}

/// C28 transports the two durable schedule families.  Due/reminder queues
/// and generation plans are derived projections and are intentionally absent
/// from the package record model.
struct V27BackupScheduleRecordV1: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        case scheduleRelease = "SCHEDULE_DEFINITION_RELEASE"
        case occurrenceHistory = "OCCURRENCE_HISTORY_EVENT"
    }

    let kind: Kind
    let id: UUID
    let workspaceID: UUID
    let revision: UInt64
    let canonicalData: Data
}

/// C29 transports the immutable plan families as canonical value records.
/// Spatial frames are embedded in revisions for persistence but are carried
/// as their own record kind so an archive can prove frame/revision closure.
struct V28BackupPlanRecordV1: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        case document = "PLAN_DOCUMENT"
        case revision = "PLAN_REVISION"
        case spatialFrame = "SPATIAL_REFERENCE_FRAME"
        case placement = "PLAN_PLACEMENT"
        case rebaseReceipt = "REBASE_RECEIPT"
    }

    let kind: Kind
    let id: UUID
    let workspaceID: UUID
    let revision: UInt64
    let canonicalData: Data
}

/// Decode and validate plan records once at the backup boundary.  Consumers
/// use this value-only result rather than decoding a second, competing plan
/// representation.  Rebase previews/component registries are intentionally
/// absent: they are derived and are rebuilt from the immutable rows.
struct PlanBackupRecordSetV1: Sendable {
    let documents: [PlanDocumentV1]
    let revisions: [PlanRevisionV1]
    let spatialFrames: [SpatialReferenceFrameV1]
    let placements: [PlanPlacementV1]
    let receipts: [RebaseReceiptV1]

    static func decode(_ records: [V28BackupPlanRecordV1]) throws -> Self {
        let ordered = records.sorted {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
                < "\($1.kind.rawValue)\u{0}\($1.id.uuidString.lowercased())"
        }
        guard ordered == records,
              Set(records.map { "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())" }).count == records.count,
              records.count <= PlanLimitsV1.maximumPlacements * 5 else {
            throw PlanContractFailureV1.invalidValue
        }
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        var documents: [PlanDocumentV1] = []
        var revisions: [PlanRevisionV1] = []
        var frames: [SpatialReferenceFrameV1] = []
        var placements: [PlanPlacementV1] = []
        var receipts: [RebaseReceiptV1] = []
        for record in records {
            guard record.id != zero, record.workspaceID != zero,
                  record.revision > 0, !record.canonicalData.isEmpty else {
                throw PlanContractFailureV1.invalidValue
            }
            switch record.kind {
            case .document:
                let value = try PlanCanonicalCodecV1.decode(PlanDocumentV1.self, from: record.canonicalData)
                try value.validateIntrinsic()
                guard value.planDocumentID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      value.revision == record.revision else { throw PlanContractFailureV1.invalidValue }
                documents.append(value)
            case .revision:
                let value = try PlanCanonicalCodecV1.decode(PlanRevisionV1.self, from: record.canonicalData)
                try value.validateIntrinsic()
                guard value.planRevisionID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      value.revision == record.revision else { throw PlanContractFailureV1.invalidValue }
                revisions.append(value)
            case .spatialFrame:
                let value = try PlanCanonicalCodecV1.decode(SpatialReferenceFrameV1.self, from: record.canonicalData)
                try value.validate()
                guard value.frameID == record.id else { throw PlanContractFailureV1.invalidValue }
                frames.append(value)
            case .placement:
                let value = try PlanCanonicalCodecV1.decode(PlanPlacementV1.self, from: record.canonicalData)
                try value.validateIntrinsic()
                guard value.placementID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      value.revision == record.revision else { throw PlanContractFailureV1.invalidValue }
                placements.append(value)
            case .rebaseReceipt:
                let value = try PlanCanonicalCodecV1.decode(RebaseReceiptV1.self, from: record.canonicalData)
                try value.validateIntrinsic()
                guard value.receiptID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      value.revision == record.revision else { throw PlanContractFailureV1.invalidValue }
                receipts.append(value)
            }
        }
        let workspaceIDs = Set(documents.map { $0.workspaceID.rawValue }
            + revisions.map { $0.workspaceID.rawValue }
            + placements.map { $0.workspaceID.rawValue }
            + receipts.map { $0.workspaceID.rawValue }
            + records.filter { $0.kind == .spatialFrame }.map(\.workspaceID))
        guard workspaceIDs.count <= 1 else { throw PlanContractFailureV1.wrongWorkspace }
        let revisionsByReference = Dictionary(uniqueKeysWithValues: revisions.map { value in
            (value.planRevisionID, value)
        })
        for revision in revisions {
            // A document's stable ID is intentionally reused across its
            // immutable revision history.  Resolve the full document
            // reference (ID + revision + digest), rather than collapsing the
            // history into a dictionary keyed only by the stable ID.
            guard documents.contains(where: {
                $0.planDocumentID == revision.planDocument.planDocumentID &&
                $0.revision == revision.planDocument.revision &&
                $0.documentSHA256 == revision.planDocument.documentSHA256
            }) else {
                throw PlanContractFailureV1.invalidValue
            }
        }
        let frameIDs = Set(frames.map(\.frameID))
        guard frameIDs == Set(revisions.flatMap { $0.spatialFrames.map(\.frameID) }) else {
            throw PlanContractFailureV1.invalidValue
        }
        for placement in placements {
            guard let revision = revisionsByReference[placement.planRevision.planRevisionID],
                  revision.reference == placement.planRevision,
                  revision.spatialFrames.contains(where: { $0.frameID == placement.spatialFrameID }) else {
                throw PlanContractFailureV1.invalidValue
            }
        }
        try PlanLifecycleClosureV1(
            documentHistory: documents,
            revisionHistory: revisions,
            placementHistory: placements,
            receipts: receipts
        ).validate()
        return Self(documents: documents, revisions: revisions, spatialFrames: frames,
                    placements: placements, receipts: receipts)
    }
}

/// C37 transports only the two durable pose families. Axis registries,
/// current tips, completed snapshots, editor state, and rebase components are
/// derived and are rebuilt from these immutable rows after import. The
/// record-set decoder is the single backup boundary for pose history: it
/// rejects duplicate identities, broken predecessor chains, cross-workspace
/// material, and an observation chain that changes its exact episode or plan
/// frame mid-history.
struct V29BackupPlacementPoseRecordV1: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        case poseEvent = "ASSET_POSE_EVENT"
        case spatialAnchorObservation = "SPATIAL_ANCHOR_OBSERVATION"
    }

    let kind: Kind
    let id: UUID
    let workspaceID: UUID
    let revision: UInt64
    let canonicalData: Data
}

struct PlacementPoseBackupRecordSetV1: Sendable {
    let poseEvents: [AssetPoseEventV1]
    let spatialAnchors: [SpatialAnchorObservationV1]

    static func decode(_ records: [V29BackupPlacementPoseRecordV1]) throws -> Self {
        let ordered = records.sorted {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
                < "\($1.kind.rawValue)\u{0}\($1.id.uuidString.lowercased())"
        }
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0,
                               0, 0, 0, 0, 0, 0, 0, 0))
        guard ordered == records,
              records.count <= PlacementPoseLimitsV1.maximumEventsPerClosure * 2,
              Set(records.map { "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())" }).count == records.count else {
            throw PlacementPoseFailureV1.unorderedValue
        }

        var events: [AssetPoseEventV1] = []
        var observations: [SpatialAnchorObservationV1] = []
        var workspaceIDs = Set<UUID>()
        for record in records {
            guard record.id != zero, record.workspaceID != zero,
                  record.revision > 0,
                  record.revision <= UInt64(Int.max),
                  !record.canonicalData.isEmpty else {
                throw PlacementPoseFailureV1.invalidValue
            }
            switch record.kind {
            case .poseEvent:
                let value = try PlacementPoseCanonicalCodecV1.decode(
                    AssetPoseEventV1.self, from: record.canonicalData
                )
                try value.validateIntrinsic()
                guard value.eventID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      value.revision == record.revision else {
                    throw PlacementPoseFailureV1.referenceMismatch
                }
                events.append(value)
                workspaceIDs.insert(value.workspaceID.rawValue)
            case .spatialAnchorObservation:
                let value = try PlacementPoseCanonicalCodecV1.decode(
                    SpatialAnchorObservationV1.self, from: record.canonicalData
                )
                try value.validateIntrinsic()
                guard value.observationID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      value.revision == record.revision else {
                    throw PlacementPoseFailureV1.referenceMismatch
                }
                observations.append(value)
                workspaceIDs.insert(value.workspaceID.rawValue)
            }
        }
        guard workspaceIDs.count <= 1 else {
            throw PlacementPoseFailureV1.wrongWorkspace
        }

        let eventGroups = Dictionary(grouping: events) {
            "\($0.workspaceID.rawValue.uuidString.lowercased())\u{0}\($0.assetID.uuidString.lowercased())"
        }
        for values in eventGroups.values {
            guard let first = values.first else { continue }
            _ = try AssetPoseHistoryV1.currentTip(
                workspaceID: first.workspaceID,
                assetID: first.assetID,
                events: values
            )
            let byID = Dictionary(uniqueKeysWithValues: values.map { ($0.eventID, $0) })
            for value in values {
                guard value.placementEventID != zero,
                      value.placementEpisodeID.rawValue != zero else {
                    throw PlacementPoseFailureV1.referenceMismatch
                }
                if let predecessor = value.predecessor {
                    guard let prior = byID[predecessor.eventID],
                          prior.eventSHA256 == predecessor.eventSHA256 else {
                        throw PlacementPoseFailureV1.predecessorMismatch
                    }
                    // `validateSuccessor` checks identity/axis/revision and
                    // permits a new physical episode or plan-frame binding
                    // only when the canonical source explicitly represents
                    // that disposition/rebase. A missing predecessor is
                    // always corruption, regardless of source label.
                    try value.validateSuccessor(of: prior)
                }
            }
        }

        let observationGroups = Dictionary(grouping: observations) {
            "\($0.workspaceID.rawValue.uuidString.lowercased())\u{0}\($0.assetID.uuidString.lowercased())"
        }
        for values in observationGroups.values {
            let orderedValues = values.sorted {
                ($0.revision, $0.observationID.uuidString.lowercased())
                    < ($1.revision, $1.observationID.uuidString.lowercased())
            }
            guard let first = orderedValues.first,
                  first.revision == 1,
                  first.predecessorObservationID == nil,
                  first.predecessorSHA256 == nil else {
                throw PlacementPoseFailureV1.predecessorMismatch
            }
            let byID = Dictionary(uniqueKeysWithValues: orderedValues.map { ($0.observationID, $0) })
            var childCount: [UUID: Int] = [:]
            for value in orderedValues {
                if let predecessorID = value.predecessorObservationID {
                    guard let prior = byID[predecessorID],
                          prior.placementEpisodeID == value.placementEpisodeID,
                          prior.planFrame == value.planFrame else {
                        throw PlacementPoseFailureV1.referenceMismatch
                    }
                    try value.validateSuccessor(of: prior)
                    childCount[predecessorID, default: 0] += 1
                    guard childCount[predecessorID] == 1 else {
                        throw PlacementPoseFailureV1.predecessorMismatch
                    }
                }
            }
            let tips = orderedValues.filter {
                childCount[$0.observationID, default: 0] == 0
            }
            guard tips.count == 1 else {
                throw PlacementPoseFailureV1.predecessorMismatch
            }
        }
        return Self(poseEvents: events, spatialAnchors: observations)
    }
}

struct V4BackupRecordsV1: Codable, Equatable, Sendable {
    let guidedSurveys:[V25BackupGuidedSurveyRecordV1]
    let assetLocators: [V26BackupAssetLocatorRecordV1]
    let schedules: [V27BackupScheduleRecordV1]
    let plans: [V28BackupPlanRecordV1]
    let placementPoses: [V29BackupPlacementPoseRecordV1]
    let surveyDefinitions:[V24BackupSurveyDefinitionRecordV1]
    let accessibleDocumentAssessments:[V23BackupAccessibleDocumentAssessmentRecordV1]
    let fieldReferences:[V22BackupFieldReferenceRecordV1]
    let recoverabilityReceipts: [V21BackupRecoverabilityReceiptRecordV1]
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
        guidedSurveys:[V25BackupGuidedSurveyRecordV1]=[],
        assetLocators: [V26BackupAssetLocatorRecordV1] = [],
        schedules: [V27BackupScheduleRecordV1] = [],
        plans: [V28BackupPlanRecordV1] = [],
        placementPoses: [V29BackupPlacementPoseRecordV1] = [],
        accessibleDocumentAssessments:[V23BackupAccessibleDocumentAssessmentRecordV1]=[],
        surveyDefinitions:[V24BackupSurveyDefinitionRecordV1]=[],
        fieldReferences:[V22BackupFieldReferenceRecordV1]=[],
        recoverabilityReceipts: [V21BackupRecoverabilityReceiptRecordV1] = [],
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
        self.guidedSurveys=guidedSurveys
        self.assetLocators = assetLocators
        self.schedules = schedules
        self.plans = plans
        self.placementPoses = placementPoses
        self.surveyDefinitions=surveyDefinitions
        self.accessibleDocumentAssessments=accessibleDocumentAssessments
        self.fieldReferences=fieldReferences
        self.recoverabilityReceipts = recoverabilityReceipts
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
         case guidedSurveys,assetLocators,schedules,plans,placementPoses,surveyDefinitions,accessibleDocumentAssessments,fieldReferences,recoverabilityReceipts, clientCapabilities, privacyTransforms, measurementIntegrity, packageEvolution, fieldDrafts, workPackets, inspectionReview, evidenceAssurance, functionalRelationships, authorityCriterion, assetSemantics, assetCompositionEdges, assetCompositionEvents, assetPlacementEvents, assets
        case deletionLedger, evidenceFiles, issues, locationHierarchyEvents
        case locationMigrationReceipts, locationNodes, mutationHistory, packets, partyAccountability
        case recordsSchemaVersion, reports, requirementAssurance, savedSmartViews, sites
        case workflowRecords
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .recordsSchemaVersion)
        self.init(
            guidedSurveys:try values.decodeIfPresent([V25BackupGuidedSurveyRecordV1].self,forKey:.guidedSurveys) ?? [],
            assetLocators: try values.decodeIfPresent([V26BackupAssetLocatorRecordV1].self, forKey: .assetLocators) ?? [],
            schedules: try values.decodeIfPresent([V27BackupScheduleRecordV1].self, forKey: .schedules) ?? [],
            plans: try values.decodeIfPresent([V28BackupPlanRecordV1].self, forKey: .plans) ?? [],
            placementPoses: try values.decodeIfPresent([V29BackupPlacementPoseRecordV1].self, forKey: .placementPoses) ?? [],
            accessibleDocumentAssessments:try values.decodeIfPresent([V23BackupAccessibleDocumentAssessmentRecordV1].self,forKey:.accessibleDocumentAssessments) ?? [],
            surveyDefinitions:try values.decodeIfPresent([V24BackupSurveyDefinitionRecordV1].self,forKey:.surveyDefinitions) ?? [],
            fieldReferences:try values.decodeIfPresent([V22BackupFieldReferenceRecordV1].self,forKey:.fieldReferences) ?? [],
            recoverabilityReceipts: try values.decodeIfPresent([V21BackupRecoverabilityReceiptRecordV1].self, forKey: .recoverabilityReceipts) ?? [],
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

extension V4BackupRecordsV1{
    func replacingAssetLocators(_ values: [V26BackupAssetLocatorRecordV1]) -> Self {
        Self(guidedSurveys: guidedSurveys, assetLocators: values,
             schedules: schedules, plans: plans,
             placementPoses: placementPoses,
             accessibleDocumentAssessments: accessibleDocumentAssessments,
             surveyDefinitions: surveyDefinitions, fieldReferences: fieldReferences,
             recoverabilityReceipts: recoverabilityReceipts,
             clientCapabilities: clientCapabilities, privacyTransforms: privacyTransforms,
             measurementIntegrity: measurementIntegrity, packageEvolution: packageEvolution,
             fieldDrafts: fieldDrafts, workPackets: workPackets,
             inspectionReview: inspectionReview, evidenceAssurance: evidenceAssurance,
             functionalRelationships: functionalRelationships,
             authorityCriterion: authorityCriterion, assetSemantics: assetSemantics,
             assetCompositionEdges: assetCompositionEdges,
             assetCompositionEvents: assetCompositionEvents,
             assetPlacementEvents: assetPlacementEvents, assets: assets,
             deletionLedger: deletionLedger, evidenceFiles: evidenceFiles,
             issues: issues, locationHierarchyEvents: locationHierarchyEvents,
             locationMigrationReceipts: locationMigrationReceipts,
             locationNodes: locationNodes, mutationHistory: mutationHistory,
             packets: packets, partyAccountability: partyAccountability,
             recordsSchemaVersion: recordsSchemaVersion, reports: reports,
             requirementAssurance: requirementAssurance,
             savedSmartViews: savedSmartViews, sites: sites,
             workflowRecords: workflowRecords)
    }

    func replacingSchedules(_ values: [V27BackupScheduleRecordV1]) -> Self {
        Self(guidedSurveys: guidedSurveys, assetLocators: assetLocators,
             schedules: values, plans: plans, placementPoses: placementPoses, accessibleDocumentAssessments: accessibleDocumentAssessments,
             surveyDefinitions: surveyDefinitions, fieldReferences: fieldReferences,
             recoverabilityReceipts: recoverabilityReceipts,
             clientCapabilities: clientCapabilities, privacyTransforms: privacyTransforms,
             measurementIntegrity: measurementIntegrity, packageEvolution: packageEvolution,
             fieldDrafts: fieldDrafts, workPackets: workPackets,
             inspectionReview: inspectionReview, evidenceAssurance: evidenceAssurance,
             functionalRelationships: functionalRelationships,
             authorityCriterion: authorityCriterion, assetSemantics: assetSemantics,
             assetCompositionEdges: assetCompositionEdges,
             assetCompositionEvents: assetCompositionEvents,
             assetPlacementEvents: assetPlacementEvents, assets: assets,
             deletionLedger: deletionLedger, evidenceFiles: evidenceFiles,
             issues: issues, locationHierarchyEvents: locationHierarchyEvents,
             locationMigrationReceipts: locationMigrationReceipts,
             locationNodes: locationNodes, mutationHistory: mutationHistory,
             packets: packets, partyAccountability: partyAccountability,
             recordsSchemaVersion: recordsSchemaVersion, reports: reports,
             requirementAssurance: requirementAssurance,
             savedSmartViews: savedSmartViews, sites: sites,
             workflowRecords: workflowRecords)
    }

    func replacingPlans(_ values: [V28BackupPlanRecordV1]) -> Self {
        Self(guidedSurveys: guidedSurveys, assetLocators: assetLocators,
             schedules: schedules, plans: values, placementPoses: placementPoses,
             accessibleDocumentAssessments: accessibleDocumentAssessments,
             surveyDefinitions: surveyDefinitions, fieldReferences: fieldReferences,
             recoverabilityReceipts: recoverabilityReceipts,
             clientCapabilities: clientCapabilities, privacyTransforms: privacyTransforms,
             measurementIntegrity: measurementIntegrity, packageEvolution: packageEvolution,
             fieldDrafts: fieldDrafts, workPackets: workPackets,
             inspectionReview: inspectionReview, evidenceAssurance: evidenceAssurance,
             functionalRelationships: functionalRelationships,
             authorityCriterion: authorityCriterion, assetSemantics: assetSemantics,
             assetCompositionEdges: assetCompositionEdges,
             assetCompositionEvents: assetCompositionEvents,
             assetPlacementEvents: assetPlacementEvents, assets: assets,
             deletionLedger: deletionLedger, evidenceFiles: evidenceFiles,
             issues: issues, locationHierarchyEvents: locationHierarchyEvents,
             locationMigrationReceipts: locationMigrationReceipts,
             locationNodes: locationNodes, mutationHistory: mutationHistory,
             packets: packets, partyAccountability: partyAccountability,
             recordsSchemaVersion: recordsSchemaVersion, reports: reports,
             requirementAssurance: requirementAssurance,
             savedSmartViews: savedSmartViews, sites: sites,
             workflowRecords: workflowRecords)
    }

    func replacingPlacementPoses(_ values: [V29BackupPlacementPoseRecordV1]) -> Self {
        Self(guidedSurveys: guidedSurveys, assetLocators: assetLocators,
             schedules: schedules, plans: plans, placementPoses: values,
             accessibleDocumentAssessments: accessibleDocumentAssessments,
             surveyDefinitions: surveyDefinitions, fieldReferences: fieldReferences,
             recoverabilityReceipts: recoverabilityReceipts,
             clientCapabilities: clientCapabilities, privacyTransforms: privacyTransforms,
             measurementIntegrity: measurementIntegrity, packageEvolution: packageEvolution,
             fieldDrafts: fieldDrafts, workPackets: workPackets,
             inspectionReview: inspectionReview, evidenceAssurance: evidenceAssurance,
             functionalRelationships: functionalRelationships,
             authorityCriterion: authorityCriterion, assetSemantics: assetSemantics,
             assetCompositionEdges: assetCompositionEdges,
             assetCompositionEvents: assetCompositionEvents,
             assetPlacementEvents: assetPlacementEvents, assets: assets,
             deletionLedger: deletionLedger, evidenceFiles: evidenceFiles,
             issues: issues, locationHierarchyEvents: locationHierarchyEvents,
             locationMigrationReceipts: locationMigrationReceipts,
             locationNodes: locationNodes, mutationHistory: mutationHistory,
             packets: packets, partyAccountability: partyAccountability,
             recordsSchemaVersion: recordsSchemaVersion, reports: reports,
             requirementAssurance: requirementAssurance,
             savedSmartViews: savedSmartViews, sites: sites,
             workflowRecords: workflowRecords)
    }

    func replacingAccessibleDocumentAssessments(_ values:[V23BackupAccessibleDocumentAssessmentRecordV1])->Self{Self(guidedSurveys:guidedSurveys,assetLocators:assetLocators,schedules:schedules,plans:plans,placementPoses:placementPoses,accessibleDocumentAssessments:values,surveyDefinitions:surveyDefinitions,fieldReferences:fieldReferences,recoverabilityReceipts:recoverabilityReceipts,clientCapabilities:clientCapabilities,privacyTransforms:privacyTransforms,measurementIntegrity:measurementIntegrity,packageEvolution:packageEvolution,fieldDrafts:fieldDrafts,workPackets:workPackets,inspectionReview:inspectionReview,evidenceAssurance:evidenceAssurance,functionalRelationships:functionalRelationships,authorityCriterion:authorityCriterion,assetSemantics:assetSemantics,assetCompositionEdges:assetCompositionEdges,assetCompositionEvents:assetCompositionEvents,assetPlacementEvents:assetPlacementEvents,assets:assets,deletionLedger:deletionLedger,evidenceFiles:evidenceFiles,issues:issues,locationHierarchyEvents:locationHierarchyEvents,locationMigrationReceipts:locationMigrationReceipts,locationNodes:locationNodes,mutationHistory:mutationHistory,packets:packets,partyAccountability:partyAccountability,recordsSchemaVersion:recordsSchemaVersion,reports:reports,requirementAssurance:requirementAssurance,savedSmartViews:savedSmartViews,sites:sites,workflowRecords:workflowRecords)}
    func replacingSurveyDefinitions(_ values:[V24BackupSurveyDefinitionRecordV1])->Self{Self(guidedSurveys:guidedSurveys,assetLocators:assetLocators,schedules:schedules,plans:plans,placementPoses:placementPoses,accessibleDocumentAssessments:accessibleDocumentAssessments,surveyDefinitions:values,fieldReferences:fieldReferences,recoverabilityReceipts:recoverabilityReceipts,clientCapabilities:clientCapabilities,privacyTransforms:privacyTransforms,measurementIntegrity:measurementIntegrity,packageEvolution:packageEvolution,fieldDrafts:fieldDrafts,workPackets:workPackets,inspectionReview:inspectionReview,evidenceAssurance:evidenceAssurance,functionalRelationships:functionalRelationships,authorityCriterion:authorityCriterion,assetSemantics:assetSemantics,assetCompositionEdges:assetCompositionEdges,assetCompositionEvents:assetCompositionEvents,assetPlacementEvents:assetPlacementEvents,assets:assets,deletionLedger:deletionLedger,evidenceFiles:evidenceFiles,issues:issues,locationHierarchyEvents:locationHierarchyEvents,locationMigrationReceipts:locationMigrationReceipts,locationNodes:locationNodes,mutationHistory:mutationHistory,packets:packets,partyAccountability:partyAccountability,recordsSchemaVersion:recordsSchemaVersion,reports:reports,requirementAssurance:requirementAssurance,savedSmartViews:savedSmartViews,sites:sites,workflowRecords:workflowRecords)}
    func replacingGuidedSurveys(_ values:[V25BackupGuidedSurveyRecordV1])->Self{Self(guidedSurveys:values,assetLocators:assetLocators,schedules:schedules,plans:plans,placementPoses:placementPoses,accessibleDocumentAssessments:accessibleDocumentAssessments,surveyDefinitions:surveyDefinitions,fieldReferences:fieldReferences,recoverabilityReceipts:recoverabilityReceipts,clientCapabilities:clientCapabilities,privacyTransforms:privacyTransforms,measurementIntegrity:measurementIntegrity,packageEvolution:packageEvolution,fieldDrafts:fieldDrafts,workPackets:workPackets,inspectionReview:inspectionReview,evidenceAssurance:evidenceAssurance,functionalRelationships:functionalRelationships,authorityCriterion:authorityCriterion,assetSemantics:assetSemantics,assetCompositionEdges:assetCompositionEdges,assetCompositionEvents:assetCompositionEvents,assetPlacementEvents:assetPlacementEvents,assets:assets,deletionLedger:deletionLedger,evidenceFiles:evidenceFiles,issues:issues,locationHierarchyEvents:locationHierarchyEvents,locationMigrationReceipts:locationMigrationReceipts,locationNodes:locationNodes,mutationHistory:mutationHistory,packets:packets,partyAccountability:partyAccountability,recordsSchemaVersion:recordsSchemaVersion,reports:reports,requirementAssurance:requirementAssurance,savedSmartViews:savedSmartViews,sites:sites,workflowRecords:workflowRecords)}
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

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

struct V32BackupAssistanceAcceptanceRecordV1: Codable, Equatable, Sendable {
    let receiptID: UUID
    let workspaceID: UUID
    let proposalID: UUID
    let mutationID: UUID
    let canonicalData: Data

    init(_ receipt: AssistanceAcceptanceReceiptV1) throws {
        try receipt.validate()
        receiptID = receipt.receiptID
        workspaceID = receipt.workspaceID.rawValue
        proposalID = receipt.proposalID
        mutationID = receipt.mutationID.rawValue
        canonicalData = try AssistanceCanonicalCodecV1.encode(receipt)
    }

    func value() throws -> AssistanceAcceptanceReceiptV1 {
        let receipt = try AssistanceCanonicalCodecV1.decode(
            AssistanceAcceptanceReceiptV1.self,
            from: canonicalData
        )
        guard receipt.receiptID == receiptID,
              receipt.workspaceID.rawValue == workspaceID,
              receipt.proposalID == proposalID,
              receipt.mutationID.rawValue == mutationID else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
        try receipt.validate()
        return receipt
    }
}

enum V33BackupTemporalEvidenceKindV1: String, Codable, Sendable {
    case clip = "TEMPORAL_EVIDENCE_CLIP"
    case anchor = "TIMECODED_EVIDENCE_ANCHOR"
}

struct V33BackupTemporalEvidenceRecordV1: Codable, Equatable, Sendable {
    let kind: V33BackupTemporalEvidenceKindV1
    let id: UUID
    let workspaceID: UUID
    let revision: UInt64
    let mutationID: UUID
    let canonicalData: Data

    init(_ value: TemporalEvidenceClipV1) throws {
        try value.validateIntrinsic()
        kind = .clip; id = value.clipID; workspaceID = value.workspaceID.rawValue
        revision = value.revision; mutationID = value.mutationID.rawValue
        canonicalData = try TemporalEvidenceCanonicalCodecV1.encode(value)
    }

    init(_ value: TimecodedEvidenceAnchorV1) throws {
        try value.validateIntrinsic()
        kind = .anchor; id = value.anchorID; workspaceID = value.workspaceID.rawValue
        revision = value.revision; mutationID = value.mutationID.rawValue
        canonicalData = try TemporalEvidenceCanonicalCodecV1.encode(value)
    }

    func clipValue() throws -> TemporalEvidenceClipV1 {
        guard kind == .clip else { throw TemporalEvidenceContractFailureV1.invalidValue }
        let value = try TemporalEvidenceCanonicalCodecV1.decode(TemporalEvidenceClipV1.self, from: canonicalData)
        guard value.clipID == id, value.workspaceID.rawValue == workspaceID,
              value.revision == revision, value.mutationID.rawValue == mutationID else {
            throw TemporalEvidenceContractFailureV1.digestMismatch
        }
        try value.validateIntrinsic(); return value
    }

    func anchorValue() throws -> TimecodedEvidenceAnchorV1 {
        guard kind == .anchor else { throw TemporalEvidenceContractFailureV1.invalidValue }
        let value = try TemporalEvidenceCanonicalCodecV1.decode(TimecodedEvidenceAnchorV1.self, from: canonicalData)
        guard value.anchorID == id, value.workspaceID.rawValue == workspaceID,
              value.revision == revision, value.mutationID.rawValue == mutationID else {
            throw TemporalEvidenceContractFailureV1.digestMismatch
        }
        try value.validateIntrinsic(); return value
    }
}

enum TemporalEvidenceBackupMemberV1 {
    static func original(for clip: TemporalEvidenceClipV1) throws -> String {
        try clip.validateIntrinsic()
        return "content/\(clip.workspaceID.rawValue.uuidString.lowercased())/\(clip.original.contentID)/original.bin"
    }
}

struct V34BackupAcceptedLabelSnapshotRecordV1: Codable, Equatable, Sendable {
    let snapshotID: UUID
    let workspaceID: UUID
    let mutationID: UUID
    let snapshotSHA256: String
    let canonicalData: Data

    init(_ value: AcceptedLabelGenerationSnapshotV1) throws {
        try value.validate()
        snapshotID = value.snapshotID
        workspaceID = value.workspaceID.rawValue
        mutationID = value.mutationID.rawValue
        snapshotSHA256 = value.snapshotSHA256
        canonicalData = try AssetLabelCanonicalCodecV1.encode(value)
    }

    func value() throws -> AcceptedLabelGenerationSnapshotV1 {
        let value = try AssetLabelCanonicalCodecV1.decode(
            AcceptedLabelGenerationSnapshotV1.self, from: canonicalData
        )
        try value.validate()
        guard value.snapshotID == snapshotID,
              value.workspaceID.rawValue == workspaceID,
              value.mutationID.rawValue == mutationID,
              value.snapshotSHA256 == snapshotSHA256,
              try AssetLabelCanonicalCodecV1.encode(value) == canonicalData else {
            throw AssetLabelContractFailureV1.invalidDigest
        }
        return value
    }
}

struct V4BackupRecordsV1: Codable, Equatable, Sendable {
    let guidedSurveys:[V25BackupGuidedSurveyRecordV1]
    let assetLocators: [V26BackupAssetLocatorRecordV1]
    let schedules: [V27BackupScheduleRecordV1]
    let plans: [V28BackupPlanRecordV1]
    let placementPoses: [V29BackupPlacementPoseRecordV1]
    /// C30 canonical durable rows. These are part of the records envelope,
    /// not a sidecar, so every encoder/decoder round trip carries them.
    let evidenceContexts: [V30BackupEvidenceContextRecordV1]
    let pairedObservationLinks: [V30BackupEvidenceContextRecordV1]
    /// C31 canonical lighting roots.  The five durable roots are transported
    /// as one stably ordered array so topology, observations, issues, plans,
    /// and claim states cannot be split across a backup sidecar.
    let lighting: [V31BackupLightingRecordV1]
    /// C32 durable acceptance provenance. Proposals and leased scratch remain
    /// process-local and therefore have no records-envelope representation.
    let assistanceAcceptanceReceipts: [V32BackupAssistanceAcceptanceRecordV1]
    /// C33 carries two durable metadata families. Immutable original bytes are
    /// direct archive members named by `TemporalEvidenceBackupMemberV1`.
    let temporalEvidence: [V33BackupTemporalEvidenceRecordV1]
    /// C45 immutable accepted label truth. Projection bytes, plans-in-flight,
    /// renderer checkpoints, and handoff staging are deliberately excluded.
    let acceptedLabelGenerationSnapshots: [V34BackupAcceptedLabelSnapshotRecordV1]
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
        workflowRecords: [V4BackupWorkflowRecordDTO],
        evidenceContexts: [V30BackupEvidenceContextRecordV1] = [],
        pairedObservationLinks: [V30BackupEvidenceContextRecordV1] = [],
        lighting: [V31BackupLightingRecordV1] = [],
        assistanceAcceptanceReceipts: [V32BackupAssistanceAcceptanceRecordV1] = [],
        temporalEvidence: [V33BackupTemporalEvidenceRecordV1] = [],
        acceptedLabelGenerationSnapshots: [V34BackupAcceptedLabelSnapshotRecordV1] = []
    ) {
        self.guidedSurveys=guidedSurveys
        self.assetLocators = assetLocators
        self.schedules = schedules
        self.plans = plans
        self.placementPoses = placementPoses
        self.evidenceContexts = evidenceContexts
        self.pairedObservationLinks = pairedObservationLinks
        self.lighting = lighting
        self.assistanceAcceptanceReceipts = assistanceAcceptanceReceipts
        self.temporalEvidence = temporalEvidence
        self.acceptedLabelGenerationSnapshots = acceptedLabelGenerationSnapshots
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
         case workflowRecords, evidenceContexts, pairedObservationLinks, lighting
         case assistanceAcceptanceReceipts, temporalEvidence, acceptedLabelGenerationSnapshots
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
            workflowRecords: try values.decode([V4BackupWorkflowRecordDTO].self, forKey: .workflowRecords),
            evidenceContexts: try values.decodeIfPresent(
                [V30BackupEvidenceContextRecordV1].self, forKey: .evidenceContexts
            ) ?? [],
            pairedObservationLinks: try values.decodeIfPresent(
                [V30BackupEvidenceContextRecordV1].self, forKey: .pairedObservationLinks
            ) ?? [],
            lighting: try values.decodeIfPresent(
                [V31BackupLightingRecordV1].self, forKey: .lighting
            ) ?? [],
            assistanceAcceptanceReceipts: try values.decodeIfPresent(
                [V32BackupAssistanceAcceptanceRecordV1].self,
                forKey: .assistanceAcceptanceReceipts
            ) ?? [],
            temporalEvidence: try values.decodeIfPresent(
                [V33BackupTemporalEvidenceRecordV1].self,
                forKey: .temporalEvidence
            ) ?? [],
            acceptedLabelGenerationSnapshots: try values.decodeIfPresent(
                [V34BackupAcceptedLabelSnapshotRecordV1].self,
                forKey: .acceptedLabelGenerationSnapshots
            ) ?? []
        )
    }
}

extension V4BackupRecordsV1 {
    func validateC45AcceptedLabelSnapshots() throws -> [AcceptedLabelGenerationSnapshotV1] {
        if recordsSchemaVersion < AssetLabelPersistenceEnrollmentV1.recordsSchemaVersion {
            guard acceptedLabelGenerationSnapshots.isEmpty else {
                throw AssetLabelContractFailureV1.invalidValue
            }
            return []
        }
        guard recordsSchemaVersion == AssetLabelPersistenceEnrollmentV1.recordsSchemaVersion,
              Set(acceptedLabelGenerationSnapshots.map { "\($0.workspaceID.uuidString.lowercased()):\($0.snapshotID.uuidString.lowercased())" }).count
                == acceptedLabelGenerationSnapshots.count else {
            throw AssetLabelContractFailureV1.duplicateIdentity
        }
        let values = try acceptedLabelGenerationSnapshots.map { try $0.value() }
        try Self.validateC45ActivePublicationOwnership(values)
        let mutations = try mutationHistory?.receipts.compactMap { record -> AssetLabelMutationV1? in
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
            guard case let .applyAssetLabel(mutation) = envelope.command else { return nil }
            let receipt = try MutationReceiptV1.decodeCanonical(from: record.receiptData)
            _ = try AssetLabelAcceptanceReceiptV1(mutation: mutation, canonicalMutationReceipt: receipt)
            return mutation
        } ?? []
        let mutationSnapshotIDs = Set(mutations.map { $0.snapshot.snapshotID })
        let liveSnapshotIDs = Set(values.map(\.snapshotID))
        let deletedSnapshotIDs = Set((deletionLedger?.entries ?? []).compactMap {
            $0.identity.kind == .acceptedLabelGenerationSnapshot ? $0.identity.id : nil
        })
        guard mutationSnapshotIDs.count == mutations.count,
              liveSnapshotIDs.isDisjoint(with: deletedSnapshotIDs),
              mutationSnapshotIDs == liveSnapshotIDs.union(deletedSnapshotIDs),
              values.allSatisfy({ value in
                  mutations.contains(where: { mutation in
                      let source = mutation.snapshot
                      if value.disposition == .activeSourceWorkspace {
                          return source == value
                              && (try? AssetLabelCanonicalCodecV1.encode(source))
                                  == acceptedLabelGenerationSnapshots.first(where: {
                                      $0.mutationID == value.mutationID.rawValue
                                  })?.canonicalData
                      }
                      // Clone/fork history intentionally has a new outer
                      // workspace, expected token, actor, mutation and digest.
                      // Its immutable source artifact truth must still join
                      // one-to-one to the exact original accepted mutation.
                      return source.disposition == .activeSourceWorkspace
                          && source.snapshotID == value.snapshotID
                          && source.workspaceID == value.plan.workspaceID
                          && source.plan == value.plan
                          && source.manifest == value.manifest
                          && source.outputReceipt == value.outputReceipt
                          && source.activationDecision == value.activationDecision
                          && source.recordedAt == value.recordedAt
                          && source.revision == value.revision
                  })
              }) else {
            throw AssetLabelContractFailureV1.invalidReceipt
        }
        return values
    }

    private static func validateC45ActivePublicationOwnership(
        _ values: [AcceptedLabelGenerationSnapshotV1]
    ) throws {
        var bindingByJobID: [LocalJobIDV1: Data] = [:]
        var bindingByContentID: [String: Data] = [:]
        var bindingByLocatorID: [String: Data] = [:]
        for snapshot in values
            where snapshot.disposition == .activeSourceWorkspace {
            let binding = snapshot.outputReceipt.publicationBinding
            try binding.validate(manifest: snapshot.manifest)
            let canonicalBinding = try AssetLabelCanonicalCodecV1.encode(binding)
            if let existing = bindingByJobID[binding.jobID],
               existing != canonicalBinding {
                throw AssetLabelContractFailureV1.duplicateIdentity
            }
            bindingByJobID[binding.jobID] = canonicalBinding
            for artifact in binding.publishedArtifacts {
                let contentID = artifact.reference.contentID
                if let existing = bindingByContentID[contentID],
                   existing != canonicalBinding {
                    throw AssetLabelContractFailureV1.duplicateIdentity
                }
                bindingByContentID[contentID] = canonicalBinding
                let locatorID = artifact.locator.locatorID
                if let existing = bindingByLocatorID[locatorID],
                   existing != canonicalBinding {
                    throw AssetLabelContractFailureV1.duplicateIdentity
                }
                bindingByLocatorID[locatorID] = canonicalBinding
            }
        }
    }
}

extension V4BackupRecordsV1{
    func validateC33TemporalEvidence() throws -> (
        clips: [TemporalEvidenceClipV1], anchors: [TimecodedEvidenceAnchorV1]
    ) {
        if recordsSchemaVersion < TemporalEvidencePersistenceEnrollmentV1.recordsSchemaVersion {
            guard temporalEvidence.isEmpty else { throw TemporalEvidenceContractFailureV1.invalidValue }
            return ([], [])
        }
        guard (TemporalEvidencePersistenceEnrollmentV1.recordsSchemaVersion...
            AssetLabelPersistenceEnrollmentV1.recordsSchemaVersion).contains(recordsSchemaVersion),
              Set(temporalEvidence.map(\.id)).count == temporalEvidence.count else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
        let clips = try temporalEvidence.filter { $0.kind == .clip }.map { try $0.clipValue() }
        let anchors = try temporalEvidence.filter { $0.kind == .anchor }.map { try $0.anchorValue() }
        let clipsByID = Dictionary(uniqueKeysWithValues: clips.map { ($0.clipID, $0) })
        let anchorsByID = Dictionary(uniqueKeysWithValues: anchors.map { ($0.anchorID, $0) })
        for anchor in anchors {
            guard let clip = clipsByID[anchor.clipID] else { throw TemporalEvidenceContractFailureV1.staleSource }
            try anchor.validate(clip: clip)
            if let predecessorID = anchor.supersedesAnchorID {
                guard let predecessor = anchorsByID[predecessorID],
                      predecessor.clipID == anchor.clipID,
                      predecessor.revision < UInt64.max,
                      anchor.revision == predecessor.revision + 1,
                      anchor.predecessorAnchorSHA256 == predecessor.anchorSHA256 else {
                    throw TemporalEvidenceContractFailureV1.staleSource
                }
            }
        }
        guard let mutationHistory else {
            guard temporalEvidence.isEmpty else { throw TemporalEvidenceContractFailureV1.invalidValue }
            return (clips, anchors)
        }
        let archivedByMutation = Dictionary(grouping: temporalEvidence, by: \.mutationID)
        guard archivedByMutation.values.allSatisfy({ $0.count == 1 }) else {
            throw TemporalEvidenceContractFailureV1.digestMismatch
        }
        var removedByMutation: [UUID: V33BackupTemporalEvidenceRecordV1] = [:]
        for row in mutationHistory.receipts {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: row.envelopeData)
            guard case let .applyTemporalEvidence(mutation) = envelope.command,
                  case let .removeClip(_, clips, anchors, _, _) = mutation.payload else { continue }
            for value in clips {
                let record = try V33BackupTemporalEvidenceRecordV1(value)
                guard removedByMutation.updateValue(record, forKey: record.mutationID) == nil else {
                    throw TemporalEvidenceContractFailureV1.digestMismatch
                }
            }
            for value in anchors {
                let record = try V33BackupTemporalEvidenceRecordV1(value)
                guard removedByMutation.updateValue(record, forKey: record.mutationID) == nil else {
                    throw TemporalEvidenceContractFailureV1.digestMismatch
                }
            }
        }
        var journalMutationIDs = Set<UUID>()
        var durableJournalMutationIDs = Set<UUID>()
        var consumedRemovedMutationIDs = Set<UUID>()
        for row in mutationHistory.receipts {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: row.envelopeData)
            guard case let .applyTemporalEvidence(mutation) = envelope.command else { continue }
            try mutation.validate()
            let receipt = try MutationReceiptV1.decodeCanonical(from: row.receiptData)
            _ = try TemporalEvidenceMutationReceiptV1(mutation: mutation, mutationReceipt: receipt)
            guard receipt.postImages == (try mutation.mutationPostImages),
                  journalMutationIDs.insert(mutation.mutationID.rawValue).inserted else {
                throw TemporalEvidenceContractFailureV1.digestMismatch
            }
            switch mutation.payload {
            case let .acceptClip(value, _, _),
                 let .registerDerivative(value, _, _, _),
                 let .applyRetention(value, _, _, _):
                if let removed = removedByMutation[mutation.mutationID.rawValue] {
                    guard archivedByMutation[mutation.mutationID.rawValue] == nil,
                          consumedRemovedMutationIDs.insert(mutation.mutationID.rawValue).inserted,
                          removed.kind == .clip,
                          removed.canonicalData == (try TemporalEvidenceCanonicalCodecV1.encode(value)),
                          try removed.clipValue() == value else {
                        throw TemporalEvidenceContractFailureV1.digestMismatch
                    }
                    continue
                }
                guard durableJournalMutationIDs.insert(mutation.mutationID.rawValue).inserted,
                      let archived = archivedByMutation[mutation.mutationID.rawValue]?.first,
                      archived.kind == .clip else {
                    throw TemporalEvidenceContractFailureV1.digestMismatch
                }
                let archivedValue = try archived.clipValue()
                if archivedValue != value {
                    let rebound = try value.rebound(
                        to: archivedValue.workspaceID,
                        target: archivedValue.target,
                        profile: archivedValue.limitProfile,
                        recordedBy: archivedValue.recordedBy
                    )
                    guard rebound == archivedValue else {
                        throw TemporalEvidenceContractFailureV1.digestMismatch
                    }
                } else if archived.canonicalData != (try TemporalEvidenceCanonicalCodecV1.encode(value)) {
                    throw TemporalEvidenceContractFailureV1.digestMismatch
                }
            case let .appendAnchor(value, _, _):
                if let removed = removedByMutation[mutation.mutationID.rawValue] {
                    guard archivedByMutation[mutation.mutationID.rawValue] == nil,
                          consumedRemovedMutationIDs.insert(mutation.mutationID.rawValue).inserted,
                          removed.kind == .anchor,
                          removed.canonicalData == (try TemporalEvidenceCanonicalCodecV1.encode(value)),
                          try removed.anchorValue() == value else {
                        throw TemporalEvidenceContractFailureV1.digestMismatch
                    }
                    continue
                }
                guard durableJournalMutationIDs.insert(mutation.mutationID.rawValue).inserted,
                      let archived = archivedByMutation[mutation.mutationID.rawValue]?.first,
                      archived.kind == .anchor else {
                    throw TemporalEvidenceContractFailureV1.digestMismatch
                }
                let archivedValue = try archived.anchorValue()
                if archivedValue != value {
                    guard let archivedClip = clipsByID[archivedValue.clipID] else {
                        throw TemporalEvidenceContractFailureV1.staleSource
                    }
                    let archivedPredecessor = value.supersedesAnchorID.flatMap { anchorsByID[$0] }
                    let rebound = try TimecodedEvidenceAnchorV1(
                        anchorID: value.anchorID,
                        clip: archivedClip,
                        offsetMilliseconds: value.offsetMilliseconds,
                        label: value.label,
                        note: value.note,
                        author: archivedValue.author,
                        recordedAt: value.recordedAt,
                        supersedesAnchorID: archivedPredecessor?.anchorID,
                        predecessorAnchorSHA256: archivedPredecessor?.anchorSHA256,
                        revision: value.revision,
                        mutationID: value.mutationID
                    )
                    guard rebound == archivedValue else {
                        throw TemporalEvidenceContractFailureV1.digestMismatch
                    }
                } else if archived.canonicalData != (try TemporalEvidenceCanonicalCodecV1.encode(value)) {
                    throw TemporalEvidenceContractFailureV1.digestMismatch
                }
            case .removeClip:
                guard archivedByMutation[mutation.mutationID.rawValue] == nil else {
                    throw TemporalEvidenceContractFailureV1.digestMismatch
                }
            }
        }
        guard Set(archivedByMutation.keys) == durableJournalMutationIDs,
              Set(removedByMutation.keys) == consumedRemovedMutationIDs else {
            throw TemporalEvidenceContractFailureV1.digestMismatch
        }
        return (clips, anchors)
    }

    /// C32 persists only accepted receipts. The receipt's canonical mutation
    /// identity remains the authority; transient proposals never enter this
    /// closure and cannot be reconstructed by restore.
    func validateC32AssistanceAcceptanceReceipts() throws {
        if recordsSchemaVersion < 31 {
            guard assistanceAcceptanceReceipts.isEmpty else {
                throw AssistanceContractFailureV1.invalidReceipt
            }
            return
        }
        guard (31...33).contains(recordsSchemaVersion),
              Set(assistanceAcceptanceReceipts.map(\.receiptID)).count == assistanceAcceptanceReceipts.count,
              Set(assistanceAcceptanceReceipts.map(\.mutationID)).count == assistanceAcceptanceReceipts.count,
              Set(assistanceAcceptanceReceipts.map(\.proposalID)).count == assistanceAcceptanceReceipts.count else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
        let receiptByMutationKey = try Dictionary(uniqueKeysWithValues:
            assistanceAcceptanceReceipts.map { record -> (String, V32BackupAssistanceAcceptanceRecordV1) in
                let value = try record.value()
                guard record.canonicalData == (try AssistanceCanonicalCodecV1.encode(value)) else {
                    throw AssistanceContractFailureV1.invalidReceipt
                }
                return (
                    MutationWorkspaceKeyV1.value(
                        workspaceID: value.workspaceID,
                        mutationID: value.mutationID
                    ),
                    record
                )
            }
        )
        guard let mutationHistory else {
            guard receiptByMutationKey.isEmpty else {
                throw AssistanceContractFailureV1.invalidReceipt
            }
            return
        }
        var assistanceJournalKeys = Set<String>()
        for journalRecord in mutationHistory.receipts {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: journalRecord.envelopeData)
            guard case let .applyAssistanceAcceptance(request) = envelope.command else { continue }
            let canonicalReceipt = try MutationReceiptV1.decodeCanonical(from: journalRecord.receiptData)
            let acceptance = try AssistanceAcceptanceReceiptV1(
                request: request,
                canonicalMutationReceipt: canonicalReceipt
            )
            let key = MutationWorkspaceKeyV1.value(
                workspaceID: request.workspaceID,
                mutationID: request.mutationID
            )
            guard assistanceJournalKeys.insert(key).inserted,
                  let archived = receiptByMutationKey[key],
                  archived.canonicalData == (try AssistanceCanonicalCodecV1.encode(acceptance)),
                  (try archived.value()) == acceptance else {
                throw AssistanceContractFailureV1.invalidReceipt
            }
        }
        guard assistanceJournalKeys == Set(receiptByMutationKey.keys) else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
    }

    /// C31 canonical lighting closure.  Every durable root is decoded from
    /// its canonical bytes, checked against its envelope identity, and then
    /// joined through exact workspace/revision/digest references.  Derived
    /// reports, search, and display projections are intentionally absent.
    func validateC31LightingClosure() throws {
        if recordsSchemaVersion < 30 {
            guard lighting.isEmpty else { throw LightingContractFailureV1.invalidValue }
            return
        }
        guard recordsSchemaVersion == 30 || recordsSchemaVersion == 31
                || recordsSchemaVersion == 32 || recordsSchemaVersion == 33 else {
            throw LightingContractFailureV1.invalidValue
        }
        let decodedLighting = try LightingBackupRecordSetV1.decode(lighting)
        try C31LightingClaimEvidenceClosureV1.validate(
            lighting: decodedLighting,
            measurementIntegrity: measurementIntegrity,
            authorityCriterion: authorityCriterion
        )
    }

    /// Validates C30 rows after decoding and before any replacement/restore
    /// operation. A link is only valid when both endpoints are represented by
    /// a decoded context with the exact workspace/evidence/digest/revision and
    /// asset binding recorded by the canonical reference.
    func validateC30EvidenceContextClosure() throws {
        if recordsSchemaVersion < 29 {
            guard evidenceContexts.isEmpty, pairedObservationLinks.isEmpty else {
                throw EvidenceContextFailureV1.incompatibleVersion
            }
            return
        }
        guard recordsSchemaVersion == 29 || recordsSchemaVersion == 30
                || recordsSchemaVersion == 31 || recordsSchemaVersion == 32
                || recordsSchemaVersion == 33 else {
            throw EvidenceContextFailureV1.incompatibleVersion
        }
        guard evidenceContexts.allSatisfy({ $0.kind == .evidenceContext }),
              pairedObservationLinks.allSatisfy({ $0.kind == .pairedObservationLink }) else {
            throw EvidenceContextFailureV1.referenceMismatch
        }
        let rows = try EvidenceContextBackupRecordSetV1.decode(
            evidenceContexts + pairedObservationLinks
        )
        let contexts = rows.contexts
        for link in rows.pairedObservationLinks {
            for endpoint in [link.first, link.second] {
                guard contexts.contains(where: {
                    $0.workspaceID == endpoint.workspaceID &&
                    $0.evidenceID == endpoint.evidenceID &&
                    $0.evidenceSHA256 == endpoint.evidenceSHA256 &&
                    $0.evidenceRevision == endpoint.evidenceRevision &&
                    $0.assetID == endpoint.assetID &&
                    $0.assetRevision == endpoint.assetRevision
                }) else {
                    throw EvidenceContextFailureV1.referenceMismatch
                }
            }
        }
    }

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
             workflowRecords: workflowRecords,
             evidenceContexts: evidenceContexts,
             pairedObservationLinks: pairedObservationLinks,
             lighting: lighting,
             assistanceAcceptanceReceipts: assistanceAcceptanceReceipts,temporalEvidence:temporalEvidence,acceptedLabelGenerationSnapshots:acceptedLabelGenerationSnapshots)
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
              workflowRecords: workflowRecords,
              evidenceContexts: evidenceContexts,
              pairedObservationLinks: pairedObservationLinks,
              lighting: lighting,
              assistanceAcceptanceReceipts: assistanceAcceptanceReceipts,temporalEvidence:temporalEvidence,acceptedLabelGenerationSnapshots:acceptedLabelGenerationSnapshots)
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
              workflowRecords: workflowRecords,
              evidenceContexts: evidenceContexts,
              pairedObservationLinks: pairedObservationLinks,
              lighting: lighting,
              assistanceAcceptanceReceipts: assistanceAcceptanceReceipts,temporalEvidence:temporalEvidence,acceptedLabelGenerationSnapshots:acceptedLabelGenerationSnapshots)
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
              workflowRecords: workflowRecords,
              evidenceContexts: evidenceContexts,
              pairedObservationLinks: pairedObservationLinks,
              lighting: lighting,
              assistanceAcceptanceReceipts: assistanceAcceptanceReceipts,temporalEvidence:temporalEvidence,acceptedLabelGenerationSnapshots:acceptedLabelGenerationSnapshots)
    }

     func replacingAccessibleDocumentAssessments(_ values:[V23BackupAccessibleDocumentAssessmentRecordV1])->Self{Self(guidedSurveys:guidedSurveys,assetLocators:assetLocators,schedules:schedules,plans:plans,placementPoses:placementPoses,accessibleDocumentAssessments:values,surveyDefinitions:surveyDefinitions,fieldReferences:fieldReferences,recoverabilityReceipts:recoverabilityReceipts,clientCapabilities:clientCapabilities,privacyTransforms:privacyTransforms,measurementIntegrity:measurementIntegrity,packageEvolution:packageEvolution,fieldDrafts:fieldDrafts,workPackets:workPackets,inspectionReview:inspectionReview,evidenceAssurance:evidenceAssurance,functionalRelationships:functionalRelationships,authorityCriterion:authorityCriterion,assetSemantics:assetSemantics,assetCompositionEdges:assetCompositionEdges,assetCompositionEvents:assetCompositionEvents,assetPlacementEvents:assetPlacementEvents,assets:assets,deletionLedger:deletionLedger,evidenceFiles:evidenceFiles,issues:issues,locationHierarchyEvents:locationHierarchyEvents,locationMigrationReceipts:locationMigrationReceipts,locationNodes:locationNodes,mutationHistory:mutationHistory,packets:packets,partyAccountability:partyAccountability,recordsSchemaVersion:recordsSchemaVersion,reports:reports,requirementAssurance:requirementAssurance,savedSmartViews:savedSmartViews,sites:sites,workflowRecords:workflowRecords,evidenceContexts:evidenceContexts,pairedObservationLinks:pairedObservationLinks,lighting:lighting,assistanceAcceptanceReceipts:assistanceAcceptanceReceipts,temporalEvidence:temporalEvidence,acceptedLabelGenerationSnapshots:acceptedLabelGenerationSnapshots)}
     func replacingSurveyDefinitions(_ values:[V24BackupSurveyDefinitionRecordV1])->Self{Self(guidedSurveys:guidedSurveys,assetLocators:assetLocators,schedules:schedules,plans:plans,placementPoses:placementPoses,accessibleDocumentAssessments:accessibleDocumentAssessments,surveyDefinitions:values,fieldReferences:fieldReferences,recoverabilityReceipts:recoverabilityReceipts,clientCapabilities:clientCapabilities,privacyTransforms:privacyTransforms,measurementIntegrity:measurementIntegrity,packageEvolution:packageEvolution,fieldDrafts:fieldDrafts,workPackets:workPackets,inspectionReview:inspectionReview,evidenceAssurance:evidenceAssurance,functionalRelationships:functionalRelationships,authorityCriterion:authorityCriterion,assetSemantics:assetSemantics,assetCompositionEdges:assetCompositionEdges,assetCompositionEvents:assetCompositionEvents,assetPlacementEvents:assetPlacementEvents,assets:assets,deletionLedger:deletionLedger,evidenceFiles:evidenceFiles,issues:issues,locationHierarchyEvents:locationHierarchyEvents,locationMigrationReceipts:locationMigrationReceipts,locationNodes:locationNodes,mutationHistory:mutationHistory,packets:packets,partyAccountability:partyAccountability,recordsSchemaVersion:recordsSchemaVersion,reports:reports,requirementAssurance:requirementAssurance,savedSmartViews:savedSmartViews,sites:sites,workflowRecords:workflowRecords,evidenceContexts:evidenceContexts,pairedObservationLinks:pairedObservationLinks,lighting:lighting,assistanceAcceptanceReceipts:assistanceAcceptanceReceipts,temporalEvidence:temporalEvidence,acceptedLabelGenerationSnapshots:acceptedLabelGenerationSnapshots)}
     func replacingGuidedSurveys(_ values:[V25BackupGuidedSurveyRecordV1])->Self{Self(guidedSurveys:values,assetLocators:assetLocators,schedules:schedules,plans:plans,placementPoses:placementPoses,accessibleDocumentAssessments:accessibleDocumentAssessments,surveyDefinitions:surveyDefinitions,fieldReferences:fieldReferences,recoverabilityReceipts:recoverabilityReceipts,clientCapabilities:clientCapabilities,privacyTransforms:privacyTransforms,measurementIntegrity:measurementIntegrity,packageEvolution:packageEvolution,fieldDrafts:fieldDrafts,workPackets:workPackets,inspectionReview:inspectionReview,evidenceAssurance:evidenceAssurance,functionalRelationships:functionalRelationships,authorityCriterion:authorityCriterion,assetSemantics:assetSemantics,assetCompositionEdges:assetCompositionEdges,assetCompositionEvents:assetCompositionEvents,assetPlacementEvents:assetPlacementEvents,assets:assets,deletionLedger:deletionLedger,evidenceFiles:evidenceFiles,issues:issues,locationHierarchyEvents:locationHierarchyEvents,locationMigrationReceipts:locationMigrationReceipts,locationNodes:locationNodes,mutationHistory:mutationHistory,packets:packets,partyAccountability:partyAccountability,recordsSchemaVersion:recordsSchemaVersion,reports:reports,requirementAssurance:requirementAssurance,savedSmartViews:savedSmartViews,sites:sites,workflowRecords:workflowRecords,evidenceContexts:evidenceContexts,pairedObservationLinks:pairedObservationLinks,lighting:lighting,assistanceAcceptanceReceipts:assistanceAcceptanceReceipts,temporalEvidence:temporalEvidence,acceptedLabelGenerationSnapshots:acceptedLabelGenerationSnapshots)}
     func replacingTemporalEvidence(_ values:[V33BackupTemporalEvidenceRecordV1])->Self{Self(guidedSurveys:guidedSurveys,assetLocators:assetLocators,schedules:schedules,plans:plans,placementPoses:placementPoses,accessibleDocumentAssessments:accessibleDocumentAssessments,surveyDefinitions:surveyDefinitions,fieldReferences:fieldReferences,recoverabilityReceipts:recoverabilityReceipts,clientCapabilities:clientCapabilities,privacyTransforms:privacyTransforms,measurementIntegrity:measurementIntegrity,packageEvolution:packageEvolution,fieldDrafts:fieldDrafts,workPackets:workPackets,inspectionReview:inspectionReview,evidenceAssurance:evidenceAssurance,functionalRelationships:functionalRelationships,authorityCriterion:authorityCriterion,assetSemantics:assetSemantics,assetCompositionEdges:assetCompositionEdges,assetCompositionEvents:assetCompositionEvents,assetPlacementEvents:assetPlacementEvents,assets:assets,deletionLedger:deletionLedger,evidenceFiles:evidenceFiles,issues:issues,locationHierarchyEvents:locationHierarchyEvents,locationMigrationReceipts:locationMigrationReceipts,locationNodes:locationNodes,mutationHistory:mutationHistory,packets:packets,partyAccountability:partyAccountability,recordsSchemaVersion:recordsSchemaVersion,reports:reports,requirementAssurance:requirementAssurance,savedSmartViews:savedSmartViews,sites:sites,workflowRecords:workflowRecords,evidenceContexts:evidenceContexts,pairedObservationLinks:pairedObservationLinks,lighting:lighting,assistanceAcceptanceReceipts:assistanceAcceptanceReceipts,temporalEvidence:values,acceptedLabelGenerationSnapshots:acceptedLabelGenerationSnapshots)}
     func replacingAcceptedLabelGenerationSnapshots(_ values:[V34BackupAcceptedLabelSnapshotRecordV1])->Self{Self(guidedSurveys:guidedSurveys,assetLocators:assetLocators,schedules:schedules,plans:plans,placementPoses:placementPoses,accessibleDocumentAssessments:accessibleDocumentAssessments,surveyDefinitions:surveyDefinitions,fieldReferences:fieldReferences,recoverabilityReceipts:recoverabilityReceipts,clientCapabilities:clientCapabilities,privacyTransforms:privacyTransforms,measurementIntegrity:measurementIntegrity,packageEvolution:packageEvolution,fieldDrafts:fieldDrafts,workPackets:workPackets,inspectionReview:inspectionReview,evidenceAssurance:evidenceAssurance,functionalRelationships:functionalRelationships,authorityCriterion:authorityCriterion,assetSemantics:assetSemantics,assetCompositionEdges:assetCompositionEdges,assetCompositionEvents:assetCompositionEvents,assetPlacementEvents:assetPlacementEvents,assets:assets,deletionLedger:deletionLedger,evidenceFiles:evidenceFiles,issues:issues,locationHierarchyEvents:locationHierarchyEvents,locationMigrationReceipts:locationMigrationReceipts,locationNodes:locationNodes,mutationHistory:mutationHistory,packets:packets,partyAccountability:partyAccountability,recordsSchemaVersion:recordsSchemaVersion,reports:reports,requirementAssurance:requirementAssurance,savedSmartViews:savedSmartViews,sites:sites,workflowRecords:workflowRecords,evidenceContexts:evidenceContexts,pairedObservationLinks:pairedObservationLinks,lighting:lighting,assistanceAcceptanceReceipts:assistanceAcceptanceReceipts,temporalEvidence:temporalEvidence,acceptedLabelGenerationSnapshots:values)}
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

/// C30 backup boundary for user-observed operating context and paired
/// comparison provenance. The rows are archived as canonical bytes; solar
/// output and control expectations remain the values recorded by the user or
/// the deterministic offline calculator and are never inferred during restore.
struct V30BackupEvidenceContextRecordV1: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        case evidenceContext = "EVIDENCE_CONTEXT"
        case pairedObservationLink = "PAIRED_OBSERVATION_LINK"
    }

    let kind: Kind
    let id: UUID
    let workspaceID: UUID
    let revision: UInt64
    let canonicalData: Data
}

struct EvidenceContextBackupRecordSetV1: Sendable {
    let contexts: [EvidenceContextV1]
    let pairedObservationLinks: [PairedObservationLinkV1]

    static func decode(_ records: [V30BackupEvidenceContextRecordV1]) throws -> Self {
        let key: (V30BackupEvidenceContextRecordV1) -> String = {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
        }
        guard records == records.sorted(by: { key($0) < key($1) }),
              Set(records.map(key)).count == records.count else {
            throw EvidenceContextFailureV1.unorderedValue
        }

        var contexts: [EvidenceContextV1] = []
        var links: [PairedObservationLinkV1] = []
        var workspaceIDs = Set<UUID>()
        for record in records {
            guard record.id.uuidString != "00000000-0000-0000-0000-000000000000",
                  record.workspaceID.uuidString != "00000000-0000-0000-0000-000000000000",
                  record.revision > 0, !record.canonicalData.isEmpty else {
                throw EvidenceContextFailureV1.invalidValue
            }
            switch record.kind {
            case .evidenceContext:
                let value = try EvidenceContextCanonicalCodecV1.decode(
                    EvidenceContextV1.self, from: record.canonicalData
                )
                guard value.contextID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      value.revision == record.revision else {
                    throw EvidenceContextFailureV1.referenceMismatch
                }
                try value.validateIntrinsic()
                contexts.append(value)
                workspaceIDs.insert(value.workspaceID.rawValue)
            case .pairedObservationLink:
                let value = try EvidenceContextCanonicalCodecV1.decode(
                    PairedObservationLinkV1.self, from: record.canonicalData
                )
                guard value.linkID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      value.revision == record.revision else {
                    throw EvidenceContextFailureV1.referenceMismatch
                }
                try value.validateIntrinsic()
                links.append(value)
                workspaceIDs.insert(value.workspaceID.rawValue)
            }
        }
        guard workspaceIDs.count <= 1 else {
            throw EvidenceContextFailureV1.wrongWorkspace
        }

        let contextGroups = Dictionary(grouping: contexts) {
            "\($0.workspaceID.rawValue.uuidString.lowercased())\u{0}\($0.evidenceID)"
        }
        for values in contextGroups.values {
            let ordered = values.sorted { ($0.revision, $0.contextID.uuidString) < ($1.revision, $1.contextID.uuidString) }
            guard Set(ordered.map(\.revision)).count == ordered.count,
                  ordered.first?.revision == 1,
                  ordered.first?.predecessorContextSHA256 == nil else {
                throw EvidenceContextFailureV1.predecessorMismatch
            }
            let byDigest = Dictionary(uniqueKeysWithValues: ordered.map { ($0.contextSHA256, $0) })
            for value in ordered.dropFirst() {
                guard let predecessorDigest = value.predecessorContextSHA256,
                      let predecessor = byDigest[predecessorDigest] else {
                    throw EvidenceContextFailureV1.predecessorMismatch
                }
                try value.validateSuccessor(of: predecessor)
            }
        }

        let linkGroups = Dictionary(grouping: links) {
            "\($0.workspaceID.rawValue.uuidString.lowercased())\u{0}\($0.first.evidenceID)\u{0}\($0.second.evidenceID)\u{0}\($0.first.evidenceSHA256)\u{0}\($0.second.evidenceSHA256)"
        }
        for values in linkGroups.values {
            let ordered = values.sorted { ($0.revision, $0.linkID.uuidString) < ($1.revision, $1.linkID.uuidString) }
            guard Set(ordered.map(\.revision)).count == ordered.count,
                  ordered.first?.revision == 1,
                  ordered.first?.predecessorLinkSHA256 == nil else {
                throw EvidenceContextFailureV1.predecessorMismatch
            }
            let byDigest = Dictionary(uniqueKeysWithValues: ordered.map { ($0.linkSHA256, $0) })
            for value in ordered.dropFirst() {
                guard let predecessorDigest = value.predecessorLinkSHA256,
                      let predecessor = byDigest[predecessorDigest] else {
                    throw EvidenceContextFailureV1.predecessorMismatch
                }
                try value.validateSuccessor(of: predecessor)
            }
        }
        return Self(contexts: contexts, pairedObservationLinks: links)
    }
}

/// C31 backup transport for the five durable lighting roots.  A root carries
/// canonical bytes rather than a second DTO shape; this keeps backup identity,
/// revision, and digest validation on the same codec as the writer path.
struct V31BackupLightingRecordV1: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        case lightingSystem = "LIGHTING_SYSTEM"
        case lightingObservation = "LIGHTING_OBSERVATION"
        case lightingIssue = "LIGHTING_ISSUE"
        case measurementPlan = "MEASUREMENT_PLAN"
        case lightingClaim = "LIGHTING_CLAIM"
    }

    let kind: Kind
    let id: UUID
    let workspaceID: UUID
    let revision: UInt64
    let canonicalData: Data
}

struct LightingBackupRecordSetV1: Sendable {
    let systems: [LightingSystemV1]
    let observations: [LightingObservationV1]
    let issues: [LightingIssueV1]
    let plans: [MeasurementPlanV1]
    let claims: [LightingClaimStateV1]

    static func decode(_ records: [V31BackupLightingRecordV1]) throws -> Self {
        let key: (V31BackupLightingRecordV1) -> String = {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
        }
        guard records == records.sorted(by: { key($0) < key($1) }),
              Set(records.map(key)).count == records.count else {
            throw LightingContractFailureV1.invalidValue
        }

        var systems: [LightingSystemV1] = []
        var observations: [LightingObservationV1] = []
        var issues: [LightingIssueV1] = []
        var plans: [MeasurementPlanV1] = []
        var claims: [LightingClaimStateV1] = []
        let zero = LightingLimitsV1.zero
        var workspaceIDs = Set<UUID>()

        for record in records {
            guard record.id != zero, record.workspaceID != zero,
                  record.revision > 0, !record.canonicalData.isEmpty else {
                throw LightingContractFailureV1.invalidValue
            }
            workspaceIDs.insert(record.workspaceID)
            switch record.kind {
            case .lightingSystem:
                let value = try LightingCanonicalCodecV1.decode(
                    LightingSystemV1.self, from: record.canonicalData
                )
                guard value.recordID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      value.revision == record.revision else {
                    throw LightingContractFailureV1.staleReference
                }
                systems.append(value)
            case .lightingObservation:
                let value = try LightingCanonicalCodecV1.decode(
                    LightingObservationV1.self, from: record.canonicalData
                )
                guard value.recordID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      value.revision == record.revision else {
                    throw LightingContractFailureV1.staleReference
                }
                observations.append(value)
            case .lightingIssue:
                let value = try LightingCanonicalCodecV1.decode(
                    LightingIssueV1.self, from: record.canonicalData
                )
                guard value.recordID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      value.revision == record.revision else {
                    throw LightingContractFailureV1.staleReference
                }
                issues.append(value)
            case .measurementPlan:
                let value = try LightingCanonicalCodecV1.decode(
                    MeasurementPlanV1.self, from: record.canonicalData
                )
                guard value.recordID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      value.revision == record.revision else {
                    throw LightingContractFailureV1.staleReference
                }
                plans.append(value)
            case .lightingClaim:
                let value = try LightingCanonicalCodecV1.decode(
                    LightingClaimStateV1.self, from: record.canonicalData
                )
                guard value.recordID == record.id,
                      value.workspaceID.rawValue == record.workspaceID,
                      value.revision == record.revision else {
                    throw LightingContractFailureV1.staleReference
                }
                claims.append(value)
            }
        }
        guard workspaceIDs.count <= 1 else {
            throw LightingContractFailureV1.wrongWorkspace
        }

        // Do not use Dictionary(uniqueKeysWithValues:) here.  A hostile
        // archive can contain two different row identities which collapse to
        // one reference key; the initializer would trap instead of failing
        // closed through the backup boundary.
        var systemByReference: [String: LightingSystemV1] = [:]
        for value in systems {
            let reference = "\(value.systemID.uuidString.lowercased())|\(value.revision)|\(value.systemSHA256)"
            guard systemByReference.updateValue(value, forKey: reference) == nil else {
                throw LightingContractFailureV1.invalidValue
            }
        }
        var observationByReference: [String: LightingObservationV1] = [:]
        for value in observations {
            let reference = "\(value.observationID.uuidString.lowercased())|\(value.revision)|\(value.observationSHA256)"
            guard observationByReference.updateValue(value, forKey: reference) == nil else {
                throw LightingContractFailureV1.invalidValue
            }
        }
        var planByReference: [String: MeasurementPlanV1] = [:]
        for value in plans {
            let reference = "\(value.planID.uuidString.lowercased())|\(value.revision)|\(value.planSHA256)"
            guard planByReference.updateValue(value, forKey: reference) == nil else {
                throw LightingContractFailureV1.invalidValue
            }
        }

        for observation in observations {
            guard let system = systemByReference[
                "\(observation.systemID.uuidString.lowercased())|\(observation.systemRevision)|\(observation.systemSHA256)"
            ] else { throw LightingContractFailureV1.staleReference }
            try observation.validate(system: system)
        }
        for plan in plans {
            guard let system = systemByReference[
                "\(plan.systemID.uuidString.lowercased())|\(plan.systemRevision)|\(plan.systemSHA256)"
            ] else { throw LightingContractFailureV1.staleReference }
            try plan.validate(system: system)
        }
        for issue in issues {
            let reference = issue.observation
            let key = "\(reference.observationID.uuidString.lowercased())|\(reference.revision)|\(reference.observationSHA256)"
            guard let observation = observationByReference[key],
                  reference.workspaceID == issue.workspaceID,
                  observation.workspaceID == issue.workspaceID,
                  observation.assetID == issue.subjectAssetID,
                  observation.issueKinds.contains(issue.kind) else {
                throw LightingContractFailureV1.staleReference
            }
        }
        for claim in claims {
            if let reference = claim.observation {
                let key = "\(reference.observationID.uuidString.lowercased())|\(reference.revision)|\(reference.observationSHA256)"
                guard let observation = observationByReference[key],
                      observation.workspaceID == claim.workspaceID,
                      observation.assetID == claim.subjectAssetID else {
                    throw LightingContractFailureV1.staleReference
                }
            }
            if let measurement = claim.measurement {
                let key = "\(measurement.planID.uuidString.lowercased())|\(measurement.planRevision)|\(measurement.planSHA256)"
                guard let plan = planByReference[key], plan.workspaceID == claim.workspaceID else {
                    throw LightingContractFailureV1.staleReference
                }
            }
        }

        func validateChain<T>(
            _ values: [T],
            id: (T) -> UUID,
            revision: (T) -> UInt64,
            predecessorID: (T) -> UUID?,
            predecessorDigest: (T) -> String?,
            successor: (T, T) throws -> Void
        ) throws {
            for group in Dictionary(grouping: values, by: id).values {
                let ordered = group.sorted {
                    (revision($0), id($0).uuidString) < (revision($1), id($1).uuidString)
                }
                guard let first = ordered.first,
                      revision(first) == 1,
                      predecessorID(first) == nil,
                      predecessorDigest(first) == nil,
                      Set(ordered.map(revision)).count == ordered.count else {
                    throw LightingContractFailureV1.invalidSuccessor
                }
                if ordered.count > 1 {
                    for index in 1..<ordered.count {
                        try successor(ordered[index - 1], ordered[index])
                    }
                }
            }
        }

        try validateChain(
            systems, id: { $0.systemID }, revision: { $0.revision },
            predecessorID: { $0.supersedesRecordID }, predecessorDigest: { $0.predecessorSHA256 }
        ) { try $1.validateSuccessor(of: $0) }
        try validateChain(
            observations, id: { $0.observationID }, revision: { $0.revision },
            predecessorID: { $0.supersedesRecordID }, predecessorDigest: { $0.predecessorSHA256 }
        ) {
            guard let system = systemByReference[
                "\($1.systemID.uuidString.lowercased())|\($1.systemRevision)|\($1.systemSHA256)"
            ] else { throw LightingContractFailureV1.staleReference }
            try $1.validateSuccessor(of: $0, system: system)
        }
        try validateChain(
            issues, id: { $0.issueID }, revision: { $0.revision },
            predecessorID: { $0.supersedesRecordID }, predecessorDigest: { $0.predecessorSHA256 }
        ) { try $1.validateSuccessor(of: $0) }
        try validateChain(
            plans, id: { $0.planID }, revision: { $0.revision },
            predecessorID: { $0.supersedesRecordID }, predecessorDigest: { $0.predecessorSHA256 }
        ) {
            guard let system = systemByReference[
                "\($1.systemID.uuidString.lowercased())|\($1.systemRevision)|\($1.systemSHA256)"
            ] else { throw LightingContractFailureV1.staleReference }
            try $1.validateSuccessor(of: $0, system: system)
        }
        try validateChain(
            claims, id: { $0.claimID }, revision: { $0.revision },
            predecessorID: { $0.supersedesRecordID }, predecessorDigest: { $0.predecessorSHA256 }
        ) { try $1.validateSuccessor(of: $0) }
        return Self(systems: systems, observations: observations, issues: issues,
                    plans: plans, claims: claims)
    }
}

/// Shared C31 admission closure used by package validation and restore.  A
/// lighting claim is not independently restorable: measured, derived, and
/// screened claims must resolve the exact archived plan/capture/protocol/
/// instrument/calibration/quality graph, plus the applicable C40 authority
/// rows.  Keeping this join here prevents package and restore from drifting
/// into separate, weaker checks.
enum C31LightingClaimEvidenceClosureV1 {
    static func validate(
        lighting: LightingBackupRecordSetV1,
        measurementIntegrity: [V18BackupMeasurementIntegrityRecordV1],
        authorityCriterion: [V11BackupAuthorityCriterionRecordV1]
    ) throws {
        var instruments: [UUID: InstrumentReferenceV1] = [:]
        var calibrations: [UUID: CalibrationStatusSnapshotV1] = [:]
        var captures: [UUID: MeasurementCaptureV1] = [:]
        var series: [UUID: MeasurementSeriesV1] = [:]
        var quality: [UUID: MeasurementQualityAssessmentV1] = [:]

        for row in measurementIntegrity {
            guard !row.canonicalData.isEmpty else {
                throw LightingContractFailureV1.invalidValue
            }
            switch row.kind {
            case .instrumentReference:
                let value = try MeasurementIntegrityCanonicalCodecV1.decode(
                    InstrumentReferenceV1.self, from: row.canonicalData
                )
                guard value.referenceID == row.id,
                      value.workspaceID.rawValue == row.workspaceID,
                      value.revision == row.revision,
                      instruments.updateValue(value, forKey: value.referenceID) == nil else {
                    throw LightingContractFailureV1.staleReference
                }
            case .calibrationSnapshot:
                let value = try MeasurementIntegrityCanonicalCodecV1.decode(
                    CalibrationStatusSnapshotV1.self, from: row.canonicalData
                )
                guard value.snapshotID == row.id,
                      value.workspaceID.rawValue == row.workspaceID,
                      value.revision == row.revision,
                      calibrations.updateValue(value, forKey: value.snapshotID) == nil else {
                    throw LightingContractFailureV1.staleReference
                }
            case .measurementCapture:
                let value = try MeasurementIntegrityCanonicalCodecV1.decode(
                    MeasurementCaptureV1.self, from: row.canonicalData
                )
                guard value.captureID == row.id,
                      value.workspaceID.rawValue == row.workspaceID,
                      value.revision == row.revision,
                      captures.updateValue(value, forKey: value.captureID) == nil else {
                    throw LightingContractFailureV1.staleReference
                }
            case .measurementSeries:
                let value = try MeasurementIntegrityCanonicalCodecV1.decode(
                    MeasurementSeriesV1.self, from: row.canonicalData
                )
                guard value.snapshotID == row.id,
                      value.workspaceID.rawValue == row.workspaceID,
                      value.revision == row.revision,
                      series.updateValue(value, forKey: value.snapshotID) == nil else {
                    throw LightingContractFailureV1.staleReference
                }
            case .qualityAssessment:
                let value = try MeasurementIntegrityCanonicalCodecV1.decode(
                    MeasurementQualityAssessmentV1.self, from: row.canonicalData
                )
                guard value.assessmentID == row.id,
                      value.workspaceID.rawValue == row.workspaceID,
                      value.revision == row.revision,
                      quality.updateValue(value, forKey: value.assessmentID) == nil else {
                    throw LightingContractFailureV1.staleReference
                }
            }
        }

        var authorities: [UUID: AuthoritySourceReleaseV1] = [:]
        var bases: [UUID: RequirementBasisBindingV1] = [:]
        var applicability: [UUID: ApplicabilityContextSnapshotV1] = [:]
        var scopes: [UUID: AssessmentScopeSnapshotV1] = [:]
        var classifications: [UUID: FindingClassificationBindingV1] = [:]
        var protocols: [UUID: MeasurementProtocolReleaseV1] = [:]
        var evaluators: [UUID: DerivedFactEvaluatorDescriptorV1] = [:]
        var provenances: [UUID: DerivedFactProvenanceV1] = [:]

        for row in authorityCriterion {
            guard !row.canonicalData.isEmpty else {
                throw LightingContractFailureV1.invalidValue
            }
            switch row.kind {
            case .authoritySourceRelease:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(
                    AuthoritySourceReleaseV1.self, from: row.canonicalData
                )
                guard value.releaseID == row.id,
                      value.workspaceID.rawValue == row.workspaceID,
                      authorities.updateValue(value, forKey: value.releaseID) == nil else {
                    throw LightingContractFailureV1.staleReference
                }
            case .requirementBasisBinding:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(
                    RequirementBasisBindingV1.self, from: row.canonicalData
                )
                guard value.bindingID == row.id,
                      value.workspaceID.rawValue == row.workspaceID,
                      bases.updateValue(value, forKey: value.bindingID) == nil else {
                    throw LightingContractFailureV1.staleReference
                }
            case .applicabilityContextSnapshot:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(
                    ApplicabilityContextSnapshotV1.self, from: row.canonicalData
                )
                guard value.snapshotID == row.id,
                      value.workspaceID.rawValue == row.workspaceID,
                      applicability.updateValue(value, forKey: value.snapshotID) == nil else {
                    throw LightingContractFailureV1.staleReference
                }
            case .assessmentScopeSnapshot:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(
                    AssessmentScopeSnapshotV1.self, from: row.canonicalData
                )
                guard value.snapshotID == row.id,
                      value.workspaceID.rawValue == row.workspaceID,
                      scopes.updateValue(value, forKey: value.snapshotID) == nil else {
                    throw LightingContractFailureV1.staleReference
                }
            case .severityScaleRelease:
                // Severity rows are validated by the package authority
                // boundary. They are not a claim join key.
                _ = try AuthorityCriterionCanonicalCodecV1.decode(
                    SeverityScaleReleaseV1.self, from: row.canonicalData
                )
            case .findingClassificationBinding:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(
                    FindingClassificationBindingV1.self, from: row.canonicalData
                )
                guard value.bindingID == row.id,
                      value.workspaceID.rawValue == row.workspaceID,
                      classifications.updateValue(value, forKey: value.bindingID) == nil else {
                    throw LightingContractFailureV1.staleReference
                }
            case .measurementProtocolRelease:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(
                    MeasurementProtocolReleaseV1.self, from: row.canonicalData
                )
                guard value.releaseID == row.id,
                      value.workspaceID.rawValue == row.workspaceID,
                      protocols.updateValue(value, forKey: value.releaseID) == nil else {
                    throw LightingContractFailureV1.staleReference
                }
            case .derivedFactEvaluatorDescriptor:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(
                    DerivedFactEvaluatorDescriptorV1.self, from: row.canonicalData
                )
                guard value.descriptorID == row.id,
                      value.workspaceID.rawValue == row.workspaceID,
                      evaluators.updateValue(value, forKey: value.descriptorID) == nil else {
                    throw LightingContractFailureV1.staleReference
                }
            case .derivedFactProvenance:
                let value = try AuthorityCriterionCanonicalCodecV1.decode(
                    DerivedFactProvenanceV1.self, from: row.canonicalData
                )
                guard value.provenanceID == row.id,
                      value.workspaceID.rawValue == row.workspaceID,
                      provenances.updateValue(value, forKey: value.provenanceID) == nil else {
                    throw LightingContractFailureV1.staleReference
                }
            }
        }

        for claim in lighting.claims {
            try claim.validateIntrinsic()
            guard let observationReference = claim.observation,
                  let observation = lighting.observations.first(where: {
                      $0.observationID == observationReference.observationID
                          && $0.revision == observationReference.revision
                          && $0.observationSHA256 == observationReference.observationSHA256
                  }) else {
                if claim.tier == .observed || claim.tier == .measured
                    || claim.tier == .derived || claim.tier == .screened {
                    throw LightingContractFailureV1.staleReference
                }
                continue
            }
            let expectedObservation = try LightingObservationReferenceV1(observation)
            guard expectedObservation == observationReference,
                  observation.workspaceID == claim.workspaceID,
                  observation.assetID == claim.subjectAssetID else {
                throw LightingContractFailureV1.staleReference
            }

            switch claim.tier {
            case .observed:
                try LightingClaimAdmissionV1.validateObserved(
                    claim, observation: observation
                )
            case .externallyAttested:
                // External attestations are not C19 measurement claims. The
                // claim's intrinsic validator still enforces its typed shape.
                continue
            case .measured, .derived, .screened:
                guard let measurement = claim.measurement,
                      let plan = lighting.plans.first(where: {
                          $0.planID == measurement.planID
                              && $0.revision == measurement.planRevision
                              && $0.planSHA256 == measurement.planSHA256
                      }),
                      plan.workspaceID == claim.workspaceID,
                      measurement.workspaceID == claim.workspaceID,
                      measurement.planID == plan.planID,
                      measurement.planRevision == plan.revision,
                      measurement.planSHA256 == plan.planSHA256 else {
                    throw LightingContractFailureV1.staleReference
                }

                let protocolReference = try MeasurementProtocolReferenceV1(
                    releaseID: plan.protocolReference.releaseID,
                    revision: plan.protocolReference.revision,
                    releaseSHA256: plan.protocolReference.releaseSHA256
                )
                guard let protocolRelease = protocols[protocolReference.releaseID],
                      protocolRelease.workspaceID == claim.workspaceID,
                      (try MeasurementProtocolReferenceV1(protocolRelease)) == protocolReference,
                      let evaluator = evaluators[protocolRelease.evaluatorDescriptorID],
                      evaluator.workspaceID == claim.workspaceID else {
                    throw LightingContractFailureV1.staleReference
                }

                var boundCaptures: [MeasurementCaptureV1] = []
                var boundQuality: [MeasurementQualityAssessmentV1] = []
                for binding in measurement.captures {
                    guard let capture = captures[binding.captureID],
                          capture.workspaceID == claim.workspaceID,
                          capture.revision == binding.captureRevision,
                          capture.captureSHA256 == binding.captureSHA256 else {
                        throw LightingContractFailureV1.staleReference
                    }
                    let matchingQuality = quality.values.filter {
                        $0.subjectKind == .capture && $0.subjectID == capture.captureID
                    }
                    guard matchingQuality.count == 1 else {
                        throw LightingContractFailureV1.staleReference
                    }
                    boundCaptures.append(capture)
                    boundQuality.append(matchingQuality[0])
                }
                guard let firstCapture = boundCaptures.first,
                      let instrumentReference = firstCapture.instrument,
                      let calibrationReference = firstCapture.calibration,
                      let instrument = instruments[instrumentReference.referenceID],
                      let calibration = calibrations[calibrationReference.snapshotID],
                      (try InstrumentRevisionReferenceV1(instrument)) == instrumentReference,
                      (try CalibrationSnapshotReferenceV1(calibration)) == calibrationReference,
                      boundCaptures.allSatisfy({
                          $0.instrument == instrumentReference
                              && $0.calibration == calibrationReference
                      }) else {
                    throw LightingContractFailureV1.staleReference
                }

                try LightingClaimAdmissionV1.validateMeasured(
                    claim,
                    observation: observation,
                    plan: plan,
                    captures: boundCaptures,
                    bindings: measurement.captures,
                    protocolRelease: protocolRelease,
                    instrument: instrument,
                    calibration: calibration,
                    quality: boundQuality
                )

                if let seriesID = measurement.seriesID {
                    guard let seriesRevision = measurement.seriesRevision,
                          let seriesSHA256 = measurement.seriesSHA256 else {
                        throw LightingContractFailureV1.staleReference
                    }
                    let matchingSeries = series.values.filter {
                        $0.seriesID == seriesID
                            && $0.revision == seriesRevision
                            && $0.seriesSHA256 == seriesSHA256
                    }
                    guard matchingSeries.count == 1 else {
                        throw LightingContractFailureV1.staleReference
                    }
                    let archivedSeries = matchingSeries[0]
                    try archivedSeries.validateClosure(
                        captures: boundCaptures,
                        protocolRelease: protocolRelease
                    )
                    if let seriesProvenance = archivedSeries.derivedFact {
                        guard provenances[seriesProvenance.provenanceID] == seriesProvenance else {
                            throw LightingContractFailureV1.staleReference
                        }
                    }
                } else {
                    guard measurement.seriesRevision == nil,
                          measurement.seriesSHA256 == nil else {
                        throw LightingContractFailureV1.staleReference
                    }
                }

                switch claim.tier {
                case .measured:
                    break
                case .derived:
                    guard let provenance = claim.derivedFact,
                          provenances[provenance.provenanceID] == provenance,
                          provenance.workspaceID == claim.workspaceID,
                          provenance.protocolReleaseID == protocolRelease.releaseID,
                          provenance.evaluatorDescriptorID == evaluator.descriptorID else {
                        throw LightingContractFailureV1.staleReference
                    }
                    try LightingClaimAdmissionV1.validateDerived(
                        claim,
                        observation: observation,
                        plan: plan,
                        captures: boundCaptures,
                        bindings: measurement.captures,
                        protocolRelease: protocolRelease,
                        evaluator: evaluator,
                        instrument: instrument,
                        calibration: calibration,
                        quality: boundQuality
                    )
                case .screened:
                    guard let criterion = claim.criterion,
                          let authority = authorities[criterion.authorityReleaseID],
                          let basis = bases[criterion.basisBindingID],
                          let applicabilitySnapshot = applicability[criterion.applicabilitySnapshotID],
                          let scope = scopes[criterion.assessmentScopeID] else {
                        throw LightingContractFailureV1.staleReference
                    }
                    let matchingClassifications = classifications.values.filter {
                        $0.workspaceID == claim.workspaceID
                            && $0.criterionID == criterion.criterionID
                            && $0.applicabilityContextID == criterion.applicabilitySnapshotID
                            && $0.assessmentScopeID == criterion.assessmentScopeID
                    }
                    guard matchingClassifications.count == 1 else {
                        throw LightingContractFailureV1.staleReference
                    }
                    try LightingClaimAdmissionV1.validateScreened(
                        claim,
                        observation: observation,
                        plan: plan,
                        captures: boundCaptures,
                        bindings: measurement.captures,
                        protocolRelease: protocolRelease,
                        instrument: instrument,
                        calibration: calibration,
                        quality: boundQuality,
                        classification: matchingClassifications[0],
                        criterion: criterion,
                        authority: authority,
                        basis: basis,
                        applicability: applicabilitySnapshot,
                        scope: scope
                    )
                case .observed, .externallyAttested:
                    break
                }
            }
        }
    }
}

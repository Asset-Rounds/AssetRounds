import Foundation

enum C50IncumbentFileExchangeBackupBoundaryV1 {
    static let excludesSceneRouteState = C34SceneNavigationCompatibilityBoundaryV1.validate()
    static let recordsSchemaVersion = C49BackupEnrollmentV1.recordsSchemaVersion
    static let profileContractSchemaVersion = IncumbentFileProfileReleaseV1.schemaVersion
    static let selectionContractSchemaVersion = IncumbentSelectionReceiptV1.schemaVersion
    static let canonicalFamilyCount = 0
    static let profileAndSelectionAreNonpersistent = true
    static let sourceScratchAndQuarantineAreExcluded = true
    static let securityBookmarksAreExcluded = true
    static let canonicalImportedRowsRemainOwnedByTargetFamilies = true

    static func validate() -> Bool {
        excludesSceneRouteState
            && recordsSchemaVersion == C49BackupEnrollmentV1.recordsSchemaVersion
            && profileContractSchemaVersion == 1
            && selectionContractSchemaVersion == 1
            && canonicalFamilyCount == 0
            && profileAndSelectionAreNonpersistent
            && sourceScratchAndQuarantineAreExcluded
            && securityBookmarksAreExcluded
            && canonicalImportedRowsRemainOwnedByTargetFamilies
    }
}

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

/// Explicit transport for C48's protected, non-SwiftData session staging.
/// Quarantine never enters this member; the snapshot contract enforces that.
enum PortableExchangeBackupMemberV2 {
    static let path = "review-exchange/snapshot.json"
    static let mimeType = "application/json"
    static let maximumByteCount = C48PortableReviewPersistenceLimitsV1.maximumEnvelopeBytes
        + Int(2 * C48PortableReviewPersistenceLimitsV1.maximumStagedBytes)
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

/// C28 transports the original two durable schedule families. C51 extends
/// this same record family with immutable exception-calendar releases while
/// preserving the canonical representation of both original record kinds. Due/reminder queues
/// and generation plans are derived projections and are intentionally absent
/// from the package record model.
struct V27BackupScheduleRecordV1: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        case scheduleRelease = "SCHEDULE_DEFINITION_RELEASE"
        case occurrenceHistory = "OCCURRENCE_HISTORY_EVENT"
        case exceptionCalendarRelease = "EXCEPTION_CALENDAR_RELEASE"
        case scheduleOverrideEvent = "SCHEDULE_OVERRIDE_EVENT"
    }

    let kind: Kind
    let id: UUID
    let workspaceID: UUID
    let revision: UInt64
    let canonicalData: Data
}

/// C51 extends the existing V27 schedule record family rather than creating a
/// parallel archive family. Existing release/history bytes remain unchanged;
/// calendar releases and effective-dated override events use additional kinds,
/// while resolved V2 bases and change receipts remain the canonical closure
/// carried by occurrence/override records and mutation history.
enum C51ScheduleBackupClosureV1 {
    static let persistentSchemaVersion = 27
    static let recordsSchemaVersion = 26
    static let persistedRecordKindCount = 4
    static let preservedV27RecordBytes = true
    static let embeddedCanonicalComponents = [
        "AdvancedRecurrenceRuleV1",
        "ExceptionCalendarReleaseV1",
        "ScheduleOverrideEventV1",
        "OccurrenceScheduleBasisV2",
        "ScheduleChangeReceiptV1",
        "AllDaysCompatibilityCalendarV1",
    ]
    static let canonicalComponentOrder = [
        "SCHEDULE_RELEASE",
        "CALENDAR_RELEASE",
        "OVERRIDE_EFFECTIVE_INTERVAL",
        "OCCURRENCE_NOMINAL_DATE",
        "OCCURRENCE_ID",
        "CHANGE_RECEIPT",
    ]
    static let allDaysMigrationPreservesOccurrenceIdentityAndDate = true
    static let sourceScheduleAutomaticallyActiveAfterCloneOrFork = false
    static let derivedDueReminderAndPreviewStateIsArchived = false

    static func validatesEnvelope(_ records: [V27BackupScheduleRecordV1]) -> Bool {
        let keys = records.map {
            "\($0.kind.rawValue)\u{0}\($0.id.uuidString.lowercased())"
        }
        return persistedRecordKindCount == V27BackupScheduleRecordV1.Kind.allCases.count
            && embeddedCanonicalComponents.count == 6
            && Set(embeddedCanonicalComponents).count == embeddedCanonicalComponents.count
            && canonicalComponentOrder.count == 6
            && Set(keys).count == keys.count
            && keys == keys.sorted()
            && records.allSatisfy { $0.revision > 0 && !$0.canonicalData.isEmpty }
            && preservedV27RecordBytes
            && allDaysMigrationPreservesOccurrenceIdentityAndDate
            && !sourceScheduleAutomaticallyActiveAfterCloneOrFork
            && !derivedDueReminderAndPreviewStateIsArchived
    }

    static func validatesAdvancedCalendarReferences(
        definitions: [ScheduleDefinitionReleaseV1],
        calendars: [ExceptionCalendarReleaseV1]
    ) -> Bool {
        do {
            try definitions.forEach { try $0.validate() }
            try calendars.forEach { try $0.validate() }
        } catch {
            return false
        }
        let calendarsByReleaseID = Dictionary(
            grouping: calendars, by: \.releaseID
        )
        return definitions.allSatisfy { definition in
            switch definition.recurrence {
            case .fixedCalendar, .completionRelative:
                return true
            case .advanced(let configuration):
                guard let matches = calendarsByReleaseID[configuration.calendarRelease.releaseID],
                      matches.count == 1,
                      let calendar = matches.first else { return false }
                return calendar.workspaceID == definition.workspaceID
                    && calendar.reference == configuration.calendarRelease
            }
        }
    }
}
enum C52ServiceRequestBoundary_V4BackupContracts {
    static let sourceKind: ServiceRequestSourceKindV1 = .portableSubmission
    static let requesterAssertionType: ServiceRequestRequesterAssertionV1.Type = ServiceRequestRequesterAssertionV1.self
    static let contactAssertionType: ServiceRequestContactAssertionV1.Type = ServiceRequestContactAssertionV1.self
    static let requesterIdentityIsUnverified: Bool = !PortableServiceRequestFormatBoundaryV1.requesterIdentityIsVerified
    static let contactAssertionWording: String = "SELF_ASSERTED_UNVERIFIED"
    static let urgencyIsUnverified: Bool = !PortableServiceRequestFormatBoundaryV1.urgencyIsVerified
    static let cleartextIsReadableAndForwardable: Bool = PortableServiceRequestFormatBoundaryV1.submissionIsCleartext && PortableServiceRequestFormatBoundaryV1.invitationIsReadableAndForwardable
    static let providerContactPurposeSeparationRequired: Bool = true
    static let canonicalSourceBytesAreAuthoritative: Bool = true
    static let duplicateCandidatesAreDerived: Bool = !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityMayBecomeWorkspaceTruth: Bool = ServiceRequestNoncanonicalBoundaryV1.rawCapabilityIsWorkspaceTruth
    static let automaticWorkOrDuplicateActionPermitted: Bool = ServiceRequestNoncanonicalBoundaryV1.automaticWorkCreationPermitted || ServiceRequestNoncanonicalBoundaryV1.automaticDuplicateMergePermitted
    static let excludedSurfaces: [String] = ["REPORT", "SEARCH", "DIAGNOSTIC", "LIFECYCLE", "COMPATIBILITY", "BACKUP", "DELETE"]
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

enum V35BackupOperationalContactKindV1: String, Codable, CaseIterable, Equatable, Sendable {
    case serviceContactPoint = "SERVICE_CONTACT_POINT"
    case systemHandoffIntent = "SYSTEM_HANDOFF_INTENT"
}

struct V35BackupOperationalContactRecordV1: Codable, Equatable, Sendable {
    let kind: V35BackupOperationalContactKindV1
    let id: UUID
    let workspaceID: UUID
    let mutationID: UUID
    let revision: UInt64
    let semanticSHA256: String
    let canonicalData: Data

    init(_ value: ServiceContactPointV1) throws {
        try value.validate()
        kind = .serviceContactPoint; id = value.contactPointID
        workspaceID = value.workspaceID.rawValue; mutationID = value.mutationID.rawValue
        revision = value.revision; semanticSHA256 = value.contactPointSHA256
        canonicalData = try OperationalContactCanonicalCodecV1.data(value)
    }

    init(_ value: SystemHandoffIntentV1) throws {
        try value.validate()
        kind = .systemHandoffIntent; id = value.intentID
        workspaceID = value.workspaceID.rawValue; mutationID = value.mutationID.rawValue
        revision = value.revision; semanticSHA256 = value.intentSHA256
        canonicalData = try OperationalContactCanonicalCodecV1.data(value)
    }

    func contactValue() throws -> ServiceContactPointV1 {
        guard kind == .serviceContactPoint else { throw OperationalContactFailureV1.invalidValue }
        let value = try OperationalContactCanonicalCodecV1.decode(ServiceContactPointV1.self, from: canonicalData)
        try value.validate()
        guard id == value.contactPointID, workspaceID == value.workspaceID.rawValue,
              mutationID == value.mutationID.rawValue, revision == value.revision,
              semanticSHA256 == value.contactPointSHA256 else { throw OperationalContactFailureV1.digestMismatch }
        return value
    }

    func intentValue() throws -> SystemHandoffIntentV1 {
        guard kind == .systemHandoffIntent else { throw OperationalContactFailureV1.invalidValue }
        let value = try OperationalContactCanonicalCodecV1.decode(SystemHandoffIntentV1.self, from: canonicalData)
        try value.validate()
        guard id == value.intentID, workspaceID == value.workspaceID.rawValue,
              mutationID == value.mutationID.rawValue, revision == value.revision,
              semanticSHA256 == value.intentSHA256 else { throw OperationalContactFailureV1.digestMismatch }
        return value
    }
}

enum V36BackupActivityContractKindV2: String, Codable, CaseIterable, Equatable, Sendable {
    case sessionEnvelope = "ACTIVITY_SESSION_ENVELOPE_V2"
    case stateTransition = "ACTIVITY_STATE_TRANSITION_V2"
    case installationTaskResult = "INSTALLATION_TASK_RESULT_V1"
    case installationAsBuiltSnapshot = "INSTALLATION_AS_BUILT_SNAPSHOT_V1"
    case punchReviewBasisSnapshot = "PUNCH_REVIEW_BASIS_SNAPSHOT_V1"
}

/// Direct canonical transport for the five newly row-backed C47 families.
/// CompletedActivitySnapshotV2 remains in its released report-snapshot file
/// lifecycle and is joined through ActivityContractMutationV2's compatibility
/// reference; the three conformance receipts and NoPlanFallbackV1 never enter
/// this records envelope.
struct V36BackupActivityContractRecordV2: Codable, Equatable, Sendable {
    let kind: V36BackupActivityContractKindV2
    let id: UUID
    let workspaceID: UUID
    let activityID: UUID
    let mutationID: UUID
    let revision: UInt64
    let semanticSHA256: String
    let canonicalData: Data

    init(_ value: ActivitySessionEnvelopeV2) throws {
        try value.validateForRead(); kind = .sessionEnvelope; id = value.activityID
        workspaceID = value.workspaceID.rawValue; activityID = value.activityID
        mutationID = value.mutationID.rawValue; revision = value.revision
        semanticSHA256 = value.envelopeSHA256; canonicalData = try value.canonicalData()
    }
    init(_ value: ActivityStateTransitionV2) throws {
        try value.validate(); kind = .stateTransition; id = value.transitionID
        workspaceID = value.workspaceID.rawValue; activityID = value.activityID
        mutationID = value.mutationID.rawValue; revision = value.revision
        semanticSHA256 = value.transitionSHA256; canonicalData = try Self.encode(value)
    }
    init(_ value: InstallationTaskResultV1) throws {
        try value.validate(); kind = .installationTaskResult; id = value.resultID
        workspaceID = value.workspaceID.rawValue; activityID = value.activityID
        mutationID = value.mutationID.rawValue; revision = value.revision
        semanticSHA256 = value.resultSHA256; canonicalData = try Self.encode(value)
    }
    init(_ value: InstallationAsBuiltSnapshotV1) throws {
        try value.validate(); kind = .installationAsBuiltSnapshot; id = value.snapshotID
        workspaceID = value.workspaceID.rawValue; activityID = value.activityID
        mutationID = value.mutationID.rawValue; revision = value.revision
        semanticSHA256 = value.snapshotSHA256; canonicalData = try Self.encode(value)
    }
    init(_ value: PunchReviewBasisSnapshotV1) throws {
        try value.validate(); kind = .punchReviewBasisSnapshot; id = value.basisID
        workspaceID = value.workspaceID.rawValue; activityID = value.activityID
        mutationID = value.mutationID.rawValue; revision = value.revision
        semanticSHA256 = value.basisSHA256; canonicalData = try Self.encode(value)
    }

    func envelopeValue() throws -> ActivitySessionEnvelopeV2 {
        let value: ActivitySessionEnvelopeV2 = try decoded(.sessionEnvelope)
        try value.validateForRead(); try require(value.activityID, value.workspaceID, value.activityID,
                                                 value.mutationID, value.revision, value.envelopeSHA256)
        return value
    }
    func transitionValue() throws -> ActivityStateTransitionV2 {
        let value: ActivityStateTransitionV2 = try decoded(.stateTransition)
        try value.validate(); try require(value.transitionID, value.workspaceID, value.activityID,
                                          value.mutationID, value.revision, value.transitionSHA256)
        return value
    }
    func installationTaskResultValue() throws -> InstallationTaskResultV1 {
        let value: InstallationTaskResultV1 = try decoded(.installationTaskResult)
        try value.validate(); try require(value.resultID, value.workspaceID, value.activityID,
                                          value.mutationID, value.revision, value.resultSHA256)
        return value
    }
    func installationAsBuiltSnapshotValue() throws -> InstallationAsBuiltSnapshotV1 {
        let value: InstallationAsBuiltSnapshotV1 = try decoded(.installationAsBuiltSnapshot)
        try value.validate(); try require(value.snapshotID, value.workspaceID, value.activityID,
                                          value.mutationID, value.revision, value.snapshotSHA256)
        return value
    }
    func punchReviewBasisSnapshotValue() throws -> PunchReviewBasisSnapshotV1 {
        let value: PunchReviewBasisSnapshotV1 = try decoded(.punchReviewBasisSnapshot)
        try value.validate(); try require(value.basisID, value.workspaceID, value.activityID,
                                          value.mutationID, value.revision, value.basisSHA256)
        return value
    }

    private func decoded<T: Codable>(_ requiredKind: V36BackupActivityContractKindV2) throws -> T {
        guard kind == requiredKind else { throw ActivityContractFailureV2.invalidValue }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(T.self, from: canonicalData)
        guard try Self.encode(value) == canonicalData else { throw ActivityContractFailureV2.invalidValue }
        return value
    }
    private func require(_ decodedID: UUID, _ decodedWorkspaceID: WorkspaceID,
                         _ decodedActivityID: UUID, _ decodedMutationID: MutationIDV1,
                         _ decodedRevision: UInt64, _ decodedSHA256: String) throws {
        guard id == decodedID, workspaceID == decodedWorkspaceID.rawValue,
              activityID == decodedActivityID, mutationID == decodedMutationID.rawValue,
              revision == decodedRevision, semanticSHA256 == decodedSHA256 else {
            throw ActivityContractFailureV2.invalidValue
        }
    }
    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        try WorkspaceMutationCanonicalV1.data(value)
    }
}

enum C49BackupEnrollmentV1 {
    static let recordsSchemaVersion = 36
    static let workResourcesAreCanonicalRows = true
    static let totalsSearchAndDraftsAreExcluded = true
    static let directCostsRoundTripWithCanonicalRows = true
    static let customerSafeReportCostRequiresExplicitProjection = true
}

/// Canonical C49 row transport. The envelope carries the exact accepted
/// postimage bytes and enough duplicated identity to reject substitution.
struct V37BackupWorkResourceRecordV1: Codable, Equatable, Sendable {
    let entryID: UUID
    let workspaceID: UUID
    let mutationID: UUID
    let revision: UInt64
    let entrySHA256: String
    let canonicalData: Data

    init(_ value: WorkResourceEntryV1) throws {
        try value.validate()
        entryID = value.entryID
        workspaceID = value.workspaceID.rawValue
        mutationID = value.mutationID.rawValue
        revision = value.revision
        entrySHA256 = value.entrySHA256
        canonicalData = try WorkspaceMutationCanonicalV1.data(value)
    }

    func value() throws -> WorkResourceEntryV1 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let decoded = try decoder.decode(WorkResourceEntryV1.self, from: canonicalData)
        try decoded.validate()
        guard try WorkspaceMutationCanonicalV1.data(decoded) == canonicalData,
              entryID == decoded.entryID,
              workspaceID == decoded.workspaceID.rawValue,
              mutationID == decoded.mutationID.rawValue,
              revision == decoded.revision,
              entrySHA256 == decoded.entrySHA256 else {
            throw WorkResourceContractFailureV1.invalidDigest
        }
        return decoded
    }
}

/// C52 canonical service-request rows are carried in the records envelope.
/// The duplicated identity columns are checked against `canonicalData` on
/// decode so a backup cannot substitute a row while retaining its digest.
enum ServiceRequestBackupContractFailureV1: Error, Equatable, Sendable {
    case invalidSchemaVersion
    case invalidIdentity
    case invalidDigest
    case invalidHistory
    case invalidWorkspaceBinding
    case prohibitedProjection
}

struct V38BackupServiceRequestRecordV1: Codable, Equatable, Sendable {
    let recordID: UUID
    let workspaceID: UUID
    let revision: UInt64
    let mutationID: UUID
    let recordSHA256: String
    let acceptedSourceSHA256: String?
    let canonicalData: Data

    init(_ value: ServiceRequestRecordV1) throws {
        try value.validate()
        recordID = value.recordID
        workspaceID = value.workspaceID.rawValue
        revision = value.revision
        mutationID = value.mutationID.rawValue
        recordSHA256 = value.recordSHA256
        acceptedSourceSHA256 = value.acceptedSourceBytes?.sha256
        canonicalData = try ServiceRequestCanonicalCodecV1.data(value)
    }

    func value() throws -> ServiceRequestRecordV1 {
        let value = try ServiceRequestCanonicalCodecV1.decode(
            ServiceRequestRecordV1.self,
            from: canonicalData
        )
        try value.validate()
        guard recordID == value.recordID,
              workspaceID == value.workspaceID.rawValue,
              revision == value.revision,
              mutationID == value.mutationID.rawValue,
              recordSHA256 == value.recordSHA256,
              acceptedSourceSHA256 == value.acceptedSourceBytes?.sha256 else {
            throw ServiceRequestBackupContractFailureV1.invalidIdentity
        }
        return value
    }
}

struct V38BackupServiceRequestDispositionEventV1: Codable, Equatable, Sendable {
    let eventID: UUID
    let workspaceID: UUID
    let requestRecordID: UUID
    let requestRevision: UInt64
    let revision: UInt64
    let mutationID: UUID
    let eventSHA256: String
    let predecessorEventID: UUID?
    let predecessorEventSHA256: String?
    let canonicalData: Data

    init(_ value: ServiceRequestDispositionEventV1) throws {
        try value.validate()
        eventID = value.eventID
        workspaceID = value.workspaceID.rawValue
        requestRecordID = value.request.recordID
        requestRevision = value.request.revision
        revision = value.revision
        mutationID = value.mutationID.rawValue
        eventSHA256 = value.eventSHA256
        predecessorEventID = value.predecessorEventID
        predecessorEventSHA256 = value.predecessorEventSHA256
        canonicalData = try ServiceRequestCanonicalCodecV1.data(value)
    }

    func value() throws -> ServiceRequestDispositionEventV1 {
        let value = try ServiceRequestCanonicalCodecV1.decode(
            ServiceRequestDispositionEventV1.self,
            from: canonicalData
        )
        try value.validate()
        guard eventID == value.eventID,
              workspaceID == value.workspaceID.rawValue,
              requestRecordID == value.request.recordID,
              requestRevision == value.request.revision,
              revision == value.revision,
              mutationID == value.mutationID.rawValue,
              eventSHA256 == value.eventSHA256,
              predecessorEventID == value.predecessorEventID,
              predecessorEventSHA256 == value.predecessorEventSHA256 else {
            throw ServiceRequestBackupContractFailureV1.invalidIdentity
        }
        return value
    }
}

struct V38BackupServiceRequestWorkLinkEventV1: Codable, Equatable, Sendable {
    let eventID: UUID
    let workspaceID: UUID
    let requestRecordID: UUID
    let requestRevision: UInt64
    let canonicalWorkID: UUID
    let canonicalWorkRevision: UInt64
    let canonicalWorkSHA256: String
    let kind: ServiceRequestWorkLinkKindV1
    let revision: UInt64
    let mutationID: UUID
    let eventSHA256: String
    let reversesEventID: UUID?
    let predecessorEventID: UUID?
    let predecessorEventSHA256: String?
    let canonicalData: Data

    init(_ value: ServiceRequestWorkLinkEventV1) throws {
        try value.validate()
        eventID = value.eventID
        workspaceID = value.workspaceID.rawValue
        requestRecordID = value.request.recordID
        requestRevision = value.request.revision
        canonicalWorkID = value.canonicalWorkID
        canonicalWorkRevision = value.canonicalWorkRevision
        canonicalWorkSHA256 = value.canonicalWorkSHA256
        kind = value.kind
        revision = value.revision
        mutationID = value.mutationID.rawValue
        eventSHA256 = value.eventSHA256
        reversesEventID = value.reversesEventID
        predecessorEventID = value.predecessorEventID
        predecessorEventSHA256 = value.predecessorEventSHA256
        canonicalData = try ServiceRequestCanonicalCodecV1.data(value)
    }

    func value() throws -> ServiceRequestWorkLinkEventV1 {
        let value = try ServiceRequestCanonicalCodecV1.decode(
            ServiceRequestWorkLinkEventV1.self,
            from: canonicalData
        )
        try value.validate()
        guard eventID == value.eventID,
              workspaceID == value.workspaceID.rawValue,
              requestRecordID == value.request.recordID,
              requestRevision == value.request.revision,
              canonicalWorkID == value.canonicalWorkID,
              canonicalWorkRevision == value.canonicalWorkRevision,
              canonicalWorkSHA256 == value.canonicalWorkSHA256,
              kind == value.kind,
              revision == value.revision,
              mutationID == value.mutationID.rawValue,
              eventSHA256 == value.eventSHA256,
              reversesEventID == value.reversesEventID,
              predecessorEventID == value.predecessorEventID,
              predecessorEventSHA256 == value.predecessorEventSHA256 else {
            throw ServiceRequestBackupContractFailureV1.invalidIdentity
        }
        return value
    }
}

// MARK: - C53 append-only asset-service reliability backup rows

/// The records envelope keeps the seven C53 durable families separate at its
/// API boundary, while each row uses one closed transport shape.  `canonicalData`
/// is always the exact post-image emitted by the service-reliability codec; the
/// duplicated identity columns are checked again on decode to prevent row
/// substitution.  The aliases below intentionally do not introduce parallel
/// domain contracts.
enum C53ServiceReliabilityBackupContractFailureV1: Error, Equatable, Sendable {
    case invalidSchemaVersion
    case invalidIdentity
    case invalidDigest
    case invalidHistory
    case invalidWorkspaceBinding
}

struct V39BackupServiceReliabilityRecordV1: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        case incident = "ASSET_SERVICE_INCIDENT"
        case impactSegment = "SERVICE_IMPACT_SEGMENT"
        case causeAssertion = "SERVICE_CAUSE_ASSERTION"
        case remedyAssertion = "SERVICE_REMEDY_ASSERTION"
        case repairInterval = "SERVICE_REPAIR_INTERVAL"
        case restorationAssertion = "SERVICE_RESTORATION_ASSERTION"
        case qualifiedExposure = "QUALIFIED_SERVICE_EXPOSURE"
    }

    let kind: Kind
    let eventID: UUID
    /// The stable append-only chain identity (`incidentID`, `segmentID`,
    /// assertion/repair ID, or exposure ID), not a mutable projection key.
    let lineageID: UUID
    let incidentID: UUID?
    let workspaceID: UUID
    let revision: UInt64
    let mutationID: UUID
    let eventSHA256: String
    let canonicalData: Data

    init(
        kind: Kind,
        eventID: UUID,
        lineageID: UUID,
        incidentID: UUID?,
        workspaceID: UUID,
        revision: UInt64,
        mutationID: UUID,
        eventSHA256: String,
        canonicalData: Data
    ) throws {
        self.kind = kind
        self.eventID = eventID
        self.lineageID = lineageID
        self.incidentID = incidentID
        self.workspaceID = workspaceID
        self.revision = revision
        self.mutationID = mutationID
        self.eventSHA256 = eventSHA256
        self.canonicalData = canonicalData
        try validateEnvelope()
    }

    init(_ value: AssetServiceIncidentV1) throws {
        try value.validate()
        try self.init(kind: .incident, eventID: value.eventID,
                      lineageID: value.incidentID, incidentID: value.incidentID,
                      workspaceID: value.workspaceID.rawValue, revision: value.revision,
                      mutationID: value.mutationID.rawValue, eventSHA256: value.eventSHA256,
                      canonicalData: try ServiceReliabilityCanonicalCodecV1.encode(value))
    }

    init(_ value: ServiceImpactSegmentV1) throws {
        try value.validate()
        try self.init(kind: .impactSegment, eventID: value.eventID,
                      lineageID: value.segmentID, incidentID: value.incidentID,
                      workspaceID: value.workspaceID.rawValue, revision: value.revision,
                      mutationID: value.mutationID.rawValue, eventSHA256: value.eventSHA256,
                      canonicalData: try ServiceReliabilityCanonicalCodecV1.encode(value))
    }

    init(_ value: ServiceCauseAssertionV1) throws {
        try value.validate()
        try self.init(kind: .causeAssertion, eventID: value.eventID,
                      lineageID: value.assertionID, incidentID: value.incidentID,
                      workspaceID: value.workspaceID.rawValue, revision: value.revision,
                      mutationID: value.mutationID.rawValue, eventSHA256: value.eventSHA256,
                      canonicalData: try ServiceReliabilityCanonicalCodecV1.encode(value))
    }

    init(_ value: ServiceRemedyAssertionV1) throws {
        try value.validate()
        try self.init(kind: .remedyAssertion, eventID: value.eventID,
                      lineageID: value.assertionID, incidentID: value.incidentID,
                      workspaceID: value.workspaceID.rawValue, revision: value.revision,
                      mutationID: value.mutationID.rawValue, eventSHA256: value.eventSHA256,
                      canonicalData: try ServiceReliabilityCanonicalCodecV1.encode(value))
    }

    init(_ value: ServiceRepairIntervalV1) throws {
        try value.validate()
        try self.init(kind: .repairInterval, eventID: value.eventID,
                      lineageID: value.repairID, incidentID: value.incidentID,
                      workspaceID: value.workspaceID.rawValue, revision: value.revision,
                      mutationID: value.mutationID.rawValue, eventSHA256: value.eventSHA256,
                      canonicalData: try ServiceReliabilityCanonicalCodecV1.encode(value))
    }

    init(_ value: ServiceRestorationAssertionV1) throws {
        try value.validate()
        try self.init(kind: .restorationAssertion, eventID: value.eventID,
                      lineageID: value.assertionID, incidentID: value.incidentID,
                      workspaceID: value.workspaceID.rawValue, revision: value.revision,
                      mutationID: value.mutationID.rawValue, eventSHA256: value.eventSHA256,
                      canonicalData: try ServiceReliabilityCanonicalCodecV1.encode(value))
    }

    init(_ value: QualifiedServiceExposureV1) throws {
        try value.validate()
        try self.init(kind: .qualifiedExposure, eventID: value.eventID,
                      lineageID: value.exposureID, incidentID: nil,
                      workspaceID: value.workspaceID.rawValue, revision: value.revision,
                      mutationID: value.mutationID.rawValue, eventSHA256: value.eventSHA256,
                      canonicalData: try ServiceReliabilityCanonicalCodecV1.encode(value))
    }

    func value() throws -> ServiceReliabilityMutationPayloadV1 {
        let payload: ServiceReliabilityMutationPayloadV1
        switch kind {
        case .incident:
            payload = .incident(try ServiceReliabilityCanonicalCodecV1.decode(
                AssetServiceIncidentV1.self, from: canonicalData
            ))
        case .impactSegment:
            payload = .impact(try ServiceReliabilityCanonicalCodecV1.decode(
                ServiceImpactSegmentV1.self, from: canonicalData
            ))
        case .causeAssertion:
            payload = .cause(try ServiceReliabilityCanonicalCodecV1.decode(
                ServiceCauseAssertionV1.self, from: canonicalData
            ))
        case .remedyAssertion:
            payload = .remedy(try ServiceReliabilityCanonicalCodecV1.decode(
                ServiceRemedyAssertionV1.self, from: canonicalData
            ))
        case .repairInterval:
            payload = .repair(try ServiceReliabilityCanonicalCodecV1.decode(
                ServiceRepairIntervalV1.self, from: canonicalData
            ))
        case .restorationAssertion:
            payload = .restoration(try ServiceReliabilityCanonicalCodecV1.decode(
                ServiceRestorationAssertionV1.self, from: canonicalData
            ))
        case .qualifiedExposure:
            payload = .exposure(try ServiceReliabilityCanonicalCodecV1.decode(
                QualifiedServiceExposureV1.self, from: canonicalData
            ))
        }
        guard payload.eventID == eventID,
              payload.workspaceID.rawValue == workspaceID,
              payload.revision == revision,
              payload.mutationID.rawValue == mutationID,
              payload.eventSHA256 == eventSHA256 else {
            throw C53ServiceReliabilityBackupContractFailureV1.invalidIdentity
        }
        switch payload {
        case .incident(let value):
            guard kind == .incident, lineageID == value.incidentID,
                  incidentID == value.incidentID else { throw C53ServiceReliabilityBackupContractFailureV1.invalidIdentity }
        case .impact(let value):
            guard kind == .impactSegment, lineageID == value.segmentID,
                  incidentID == value.incidentID else { throw C53ServiceReliabilityBackupContractFailureV1.invalidIdentity }
        case .cause(let value):
            guard kind == .causeAssertion, lineageID == value.assertionID,
                  incidentID == value.incidentID else { throw C53ServiceReliabilityBackupContractFailureV1.invalidIdentity }
        case .remedy(let value):
            guard kind == .remedyAssertion, lineageID == value.assertionID,
                  incidentID == value.incidentID else { throw C53ServiceReliabilityBackupContractFailureV1.invalidIdentity }
        case .repair(let value):
            guard kind == .repairInterval, lineageID == value.repairID,
                  incidentID == value.incidentID else { throw C53ServiceReliabilityBackupContractFailureV1.invalidIdentity }
        case .restoration(let value):
            guard kind == .restorationAssertion, lineageID == value.assertionID,
                  incidentID == value.incidentID else { throw C53ServiceReliabilityBackupContractFailureV1.invalidIdentity }
        case .exposure(let value):
            guard kind == .qualifiedExposure, lineageID == value.exposureID,
                  incidentID == nil else { throw C53ServiceReliabilityBackupContractFailureV1.invalidIdentity }
        }
        return payload
    }

    private func validateEnvelope() throws {
        try ServiceReliabilityLimitsV1.id(eventID)
        try ServiceReliabilityLimitsV1.id(lineageID)
        try incidentID.map(ServiceReliabilityLimitsV1.id)
        try ServiceReliabilityLimitsV1.id(workspaceID)
        try ServiceReliabilityLimitsV1.id(mutationID)
        try ServiceReliabilityLimitsV1.digest(eventSHA256)
        guard revision > 0, !canonicalData.isEmpty else {
            throw C53ServiceReliabilityBackupContractFailureV1.invalidIdentity
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, eventID, lineageID, incidentID, workspaceID, revision,
             mutationID, eventSHA256, canonicalData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard Set(container.allKeys) == Set(CodingKeys.allCases) else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container,
                debugDescription: "C53 service-reliability row contains an unknown key"
            )
        }
        try self.init(
            kind: try container.decode(Kind.self, forKey: .kind),
            eventID: try container.decode(UUID.self, forKey: .eventID),
            lineageID: try container.decode(UUID.self, forKey: .lineageID),
            incidentID: try container.decodeIfPresent(UUID.self, forKey: .incidentID),
            workspaceID: try container.decode(UUID.self, forKey: .workspaceID),
            revision: try container.decode(UInt64.self, forKey: .revision),
            mutationID: try container.decode(UUID.self, forKey: .mutationID),
            eventSHA256: try container.decode(String.self, forKey: .eventSHA256),
            canonicalData: try container.decode(Data.self, forKey: .canonicalData)
        )
    }
}

typealias V39BackupAssetServiceIncidentRecordV1 = V39BackupServiceReliabilityRecordV1
typealias V39BackupServiceImpactSegmentRecordV1 = V39BackupServiceReliabilityRecordV1
typealias V39BackupServiceCauseAssertionRecordV1 = V39BackupServiceReliabilityRecordV1
typealias V39BackupServiceRemedyAssertionRecordV1 = V39BackupServiceReliabilityRecordV1
typealias V39BackupServiceRepairIntervalRecordV1 = V39BackupServiceReliabilityRecordV1
typealias V39BackupServiceRestorationAssertionRecordV1 = V39BackupServiceReliabilityRecordV1
typealias V39BackupQualifiedServiceExposureRecordV1 = V39BackupServiceReliabilityRecordV1

/// The journal remains the receipt source of truth. This typed transport row
/// is a closed projection of the existing C53 mutation receipt, never a second
/// writer or store.
struct V39BackupServiceReliabilityReceiptRecordV1: Codable, Equatable, Sendable {
    let mutationID: UUID
    let bundleSHA256: String
    let canonicalData: Data

    init(_ value: ServiceReliabilityMutationReceiptV1) throws {
        mutationID = value.mutationReceipt.mutationID.rawValue
        bundleSHA256 = value.bundleSHA256
        canonicalData = try WorkspaceMutationCanonicalV1.data(value)
        try validateEnvelope()
    }

    func value() throws -> ServiceReliabilityMutationReceiptV1 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(ServiceReliabilityMutationReceiptV1.self, from: canonicalData)
        guard try WorkspaceMutationCanonicalV1.data(value) == canonicalData,
              value.mutationReceipt.mutationID.rawValue == mutationID,
              value.bundleSHA256 == bundleSHA256 else {
            throw C53ServiceReliabilityBackupContractFailureV1.invalidDigest
        }
        try value.mutationReceipt.validate()
        return value
    }

    private func validateEnvelope() throws {
        try ServiceReliabilityLimitsV1.id(mutationID)
        try ServiceReliabilityLimitsV1.digest(bundleSHA256)
        guard !canonicalData.isEmpty else {
            throw C53ServiceReliabilityBackupContractFailureV1.invalidDigest
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case mutationID, bundleSHA256, canonicalData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard Set(container.allKeys) == Set(CodingKeys.allCases) else {
            throw DecodingError.dataCorruptedError(
                forKey: .mutationID, in: container,
                debugDescription: "C53 service-reliability receipt contains an unknown key"
            )
        }
        mutationID = try container.decode(UUID.self, forKey: .mutationID)
        bundleSHA256 = try container.decode(String.self, forKey: .bundleSHA256)
        canonicalData = try container.decode(Data.self, forKey: .canonicalData)
        try validateEnvelope()
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
    /// C46 canonical contact and reviewed-intent rows. Platform outcomes and
    /// imported source-file bytes are never members of the archive.
    let operationalContacts: [V35BackupOperationalContactRecordV1]
    let activityContracts: [V36BackupActivityContractRecordV2]
    /// C49 canonical append-only manual-resource and direct-cost history.
    /// Search/totals/drafts are deliberately absent and rebuilt after import.
    let workResources: [V37BackupWorkResourceRecordV1]
    /// C52 canonical service-request record revisions and append-only
    /// disposition/work-link history. Derived projections and raw capability
    /// material intentionally have no records-envelope fields.
    let serviceRequests: [V38BackupServiceRequestRecordV1]
    let serviceRequestDispositionEvents: [V38BackupServiceRequestDispositionEventV1]
    let serviceRequestWorkLinkEvents: [V38BackupServiceRequestWorkLinkEventV1]
    /// C53 actor-recorded operational-impact source rows. The metric input
    /// projection is intentionally absent and is rebuilt from these histories.
    let serviceReliabilityIncidents: [V39BackupAssetServiceIncidentRecordV1]
    let serviceImpactSegments: [V39BackupServiceImpactSegmentRecordV1]
    let serviceCauseAssertions: [V39BackupServiceCauseAssertionRecordV1]
    let serviceRemedyAssertions: [V39BackupServiceRemedyAssertionRecordV1]
    let serviceRepairIntervals: [V39BackupServiceRepairIntervalRecordV1]
    let serviceRestorationAssertions: [V39BackupServiceRestorationAssertionRecordV1]
    let qualifiedServiceExposures: [V39BackupQualifiedServiceExposureRecordV1]
    let serviceReliabilityReceipts: [V39BackupServiceReliabilityReceiptRecordV1]
    /// C57 canonical My Day plan history and explicit carryover receipts.
    /// Readiness, due, and source-state projections are deliberately absent.
    let myDayPlans: [MyDayPlanV1]
    let myDayCarryoverReceipts: [MyDayCarryoverReceiptV1]
    /// Exact immutable revisions retained by a workspace fork. This is derived
    /// from the complete predecessor-closed plan history, never caller-selected.
    let nonactivePlanReferences: [MyDayPlanReferenceV1]
    /// C05 accepted-dependency correction: append-only evidence association
    /// events and predecessor-closed reviewed sequence revisions. Derivative
    /// bytes remain archive members owned by the incumbent content lifecycle.
    let evidenceAssociationEvents: [EvidenceAssociationV1]
    let evidenceSequenceRevisions: [EvidenceSequenceV1]
    /// V44 carries complete append-only histories so profile revision closure
    /// survives backup, clone, restore, and exact export.
    let shopReportProfiles: [ShopReportProfileV1]
    /// V45 carries the canonical round-session frontier history. Item state is
    /// embedded in each immutable revision; no mutable item table is archived.
    let roundSessions: [RoundSessionV1]
    /// C55 is transported as the one canonical snapshot owned by PartsStock.
    /// Its seven durable families must never be split into a parallel archive.
    let partsStockSnapshot: PartsStockBackupSnapshotV1?
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
        acceptedLabelGenerationSnapshots: [V34BackupAcceptedLabelSnapshotRecordV1] = [],
        operationalContacts: [V35BackupOperationalContactRecordV1] = [],
        activityContracts: [V36BackupActivityContractRecordV2] = [],
        workResources: [V37BackupWorkResourceRecordV1] = [],
        serviceRequests: [V38BackupServiceRequestRecordV1] = [],
        serviceRequestDispositionEvents: [V38BackupServiceRequestDispositionEventV1] = [],
        serviceRequestWorkLinkEvents: [V38BackupServiceRequestWorkLinkEventV1] = [],
        serviceReliabilityIncidents: [V39BackupAssetServiceIncidentRecordV1] = [],
        serviceImpactSegments: [V39BackupServiceImpactSegmentRecordV1] = [],
        serviceCauseAssertions: [V39BackupServiceCauseAssertionRecordV1] = [],
        serviceRemedyAssertions: [V39BackupServiceRemedyAssertionRecordV1] = [],
        serviceRepairIntervals: [V39BackupServiceRepairIntervalRecordV1] = [],
        serviceRestorationAssertions: [V39BackupServiceRestorationAssertionRecordV1] = [],
        qualifiedServiceExposures: [V39BackupQualifiedServiceExposureRecordV1] = [],
        serviceReliabilityReceipts: [V39BackupServiceReliabilityReceiptRecordV1] = [],
        partsStockSnapshot: PartsStockBackupSnapshotV1? = nil,
        myDayPlans: [MyDayPlanV1] = [],
        myDayCarryoverReceipts: [MyDayCarryoverReceiptV1] = [],
        nonactivePlanReferences: [MyDayPlanReferenceV1] = [],
        evidenceAssociationEvents: [EvidenceAssociationV1] = [],
        evidenceSequenceRevisions: [EvidenceSequenceV1] = [],
        shopReportProfiles: [ShopReportProfileV1] = [],
        roundSessions: [RoundSessionV1] = []
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
        self.operationalContacts = operationalContacts
        self.activityContracts = activityContracts
        self.workResources = workResources
        self.serviceRequests = serviceRequests
        self.serviceRequestDispositionEvents = serviceRequestDispositionEvents
        self.serviceRequestWorkLinkEvents = serviceRequestWorkLinkEvents
        self.serviceReliabilityIncidents = serviceReliabilityIncidents
        self.serviceImpactSegments = serviceImpactSegments
        self.serviceCauseAssertions = serviceCauseAssertions
        self.serviceRemedyAssertions = serviceRemedyAssertions
        self.serviceRepairIntervals = serviceRepairIntervals
        self.serviceRestorationAssertions = serviceRestorationAssertions
        self.qualifiedServiceExposures = qualifiedServiceExposures
        self.serviceReliabilityReceipts = serviceReliabilityReceipts
        self.partsStockSnapshot = partsStockSnapshot
        self.myDayPlans = myDayPlans
        self.myDayCarryoverReceipts = myDayCarryoverReceipts
        self.nonactivePlanReferences = nonactivePlanReferences
        self.evidenceAssociationEvents = evidenceAssociationEvents
        self.evidenceSequenceRevisions = evidenceSequenceRevisions
        self.shopReportProfiles = shopReportProfiles
        self.roundSessions = roundSessions
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
         case assistanceAcceptanceReceipts, temporalEvidence, acceptedLabelGenerationSnapshots, operationalContacts, activityContracts, workResources
          case serviceRequests, serviceRequestDispositionEvents, serviceRequestWorkLinkEvents
          case serviceReliabilityIncidents, serviceImpactSegments, serviceCauseAssertions
          case serviceRemedyAssertions, serviceRepairIntervals, serviceRestorationAssertions
          case qualifiedServiceExposures, serviceReliabilityReceipts
          case partsStockSnapshot, myDayPlans, myDayCarryoverReceipts, nonactivePlanReferences
          case evidenceAssociationEvents, evidenceSequenceRevisions, shopReportProfiles, roundSessions
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
            ) ?? [],
            operationalContacts: try values.decodeIfPresent(
                [V35BackupOperationalContactRecordV1].self,
                forKey: .operationalContacts
            ) ?? [],
            activityContracts: try values.decodeIfPresent(
                [V36BackupActivityContractRecordV2].self,
                forKey: .activityContracts
            ) ?? [],
            workResources: try values.decodeIfPresent(
                [V37BackupWorkResourceRecordV1].self,
                forKey: .workResources
            ) ?? [],
            serviceRequests: try values.decodeIfPresent(
                [V38BackupServiceRequestRecordV1].self,
                forKey: .serviceRequests
            ) ?? [],
            serviceRequestDispositionEvents: try values.decodeIfPresent(
                [V38BackupServiceRequestDispositionEventV1].self,
                forKey: .serviceRequestDispositionEvents
            ) ?? [],
            serviceRequestWorkLinkEvents: try values.decodeIfPresent(
                [V38BackupServiceRequestWorkLinkEventV1].self,
                forKey: .serviceRequestWorkLinkEvents
            ) ?? [],
            serviceReliabilityIncidents: try values.decodeIfPresent(
                [V39BackupAssetServiceIncidentRecordV1].self,
                forKey: .serviceReliabilityIncidents
            ) ?? [],
            serviceImpactSegments: try values.decodeIfPresent(
                [V39BackupServiceImpactSegmentRecordV1].self,
                forKey: .serviceImpactSegments
            ) ?? [],
            serviceCauseAssertions: try values.decodeIfPresent(
                [V39BackupServiceCauseAssertionRecordV1].self,
                forKey: .serviceCauseAssertions
            ) ?? [],
            serviceRemedyAssertions: try values.decodeIfPresent(
                [V39BackupServiceRemedyAssertionRecordV1].self,
                forKey: .serviceRemedyAssertions
            ) ?? [],
            serviceRepairIntervals: try values.decodeIfPresent(
                [V39BackupServiceRepairIntervalRecordV1].self,
                forKey: .serviceRepairIntervals
            ) ?? [],
            serviceRestorationAssertions: try values.decodeIfPresent(
                [V39BackupServiceRestorationAssertionRecordV1].self,
                forKey: .serviceRestorationAssertions
            ) ?? [],
            qualifiedServiceExposures: try values.decodeIfPresent(
                [V39BackupQualifiedServiceExposureRecordV1].self,
                forKey: .qualifiedServiceExposures
            ) ?? [],
            serviceReliabilityReceipts: try values.decodeIfPresent(
                [V39BackupServiceReliabilityReceiptRecordV1].self,
                forKey: .serviceReliabilityReceipts
            ) ?? [],
            partsStockSnapshot: try values.decodeIfPresent(
                PartsStockBackupSnapshotV1.self,
                forKey: .partsStockSnapshot
            ),
            myDayPlans: try values.decodeIfPresent([MyDayPlanV1].self, forKey: .myDayPlans) ?? [],
            myDayCarryoverReceipts: try values.decodeIfPresent(
                [MyDayCarryoverReceiptV1].self, forKey: .myDayCarryoverReceipts
            ) ?? [],
            nonactivePlanReferences: try values.decodeIfPresent(
                [MyDayPlanReferenceV1].self, forKey: .nonactivePlanReferences
            ) ?? [],
            evidenceAssociationEvents: try values.decodeIfPresent(
                [EvidenceAssociationV1].self, forKey: .evidenceAssociationEvents
            ) ?? [],
            evidenceSequenceRevisions: try values.decodeIfPresent(
                [EvidenceSequenceV1].self, forKey: .evidenceSequenceRevisions
            ) ?? [],
            shopReportProfiles: try values.decodeIfPresent(
                [ShopReportProfileV1].self, forKey: .shopReportProfiles
            ) ?? [],
            roundSessions: try values.decodeIfPresent(
                [RoundSessionV1].self, forKey: .roundSessions
            ) ?? []
        )
    }
}

enum C05EvidenceMetadataBackupEnrollmentV1 {
    static let persistentSchemaVersion = 43
    static let recordsSchemaVersion = 42
    static let durableFamilyCount = 2
    static let canonicalRowKinds = ["EvidenceAssociationEventRowV1", "EvidenceSequenceRevisionRowV1"]

    static func validate(_ records: V4BackupRecordsV1) throws {
        if records.recordsSchemaVersion < recordsSchemaVersion {
            guard records.evidenceAssociationEvents.isEmpty,
                  records.evidenceSequenceRevisions.isEmpty else {
                throw EvidenceMetadataFailureV1.invalidValue
            }
            return
        }
        guard (recordsSchemaVersion...C05RoundSessionBackupEnrollmentV1.recordsSchemaVersion)
                .contains(records.recordsSchemaVersion),
              durableFamilyCount == canonicalRowKinds.count else {
            throw EvidenceMetadataFailureV1.invalidValue
        }
        let associationKeys = records.evidenceAssociationEvents.map {
            "\($0.workspaceID)|\($0.associationEventID)"
        }
        guard associationKeys == associationKeys.sorted(),
              Set(associationKeys).count == associationKeys.count else {
            throw EvidenceMetadataFailureV1.duplicateIdentity
        }
        let ledgerOrderedAssociations = records.evidenceAssociationEvents.sorted {
            ($0.workspaceID, $0.evidenceID, $0.resultingEvidenceRevision, $0.associationEventID)
                < ($1.workspaceID, $1.evidenceID, $1.resultingEvidenceRevision, $1.associationEventID)
        }
        try EvidenceAssociationLedgerV1.validate(ledgerOrderedAssociations)
        let sequenceKeys = records.evidenceSequenceRevisions.map {
            EvidenceSequenceRevisionRowV1.rowID(sequenceID: $0.sequenceID, revision: $0.revision)
        }
        guard sequenceKeys == sequenceKeys.sorted(),
              Set(sequenceKeys).count == sequenceKeys.count else {
            throw EvidenceMetadataFailureV1.duplicateIdentity
        }
        try EvidenceMetadataGraphV1.validate(
            sequences: records.evidenceSequenceRevisions,
            associationEvents: ledgerOrderedAssociations
        )
    }
}

enum C04ShopReportProfileBackupEnrollmentV1 {
    static let persistentSchemaVersion = 44
    static let recordsSchemaVersion = 43
    static let durableFamilyCount = 1
    static let canonicalRowKinds = ["ShopReportProfileRowV1"]

    static func validate(_ records: V4BackupRecordsV1) throws {
        if records.recordsSchemaVersion < recordsSchemaVersion {
            guard records.shopReportProfiles.isEmpty else {
                throw ShopReportProfileFailureV1.invalidValue
            }
            return
        }
        guard (recordsSchemaVersion...C05RoundSessionBackupEnrollmentV1.recordsSchemaVersion)
                .contains(records.recordsSchemaVersion),
              durableFamilyCount == canonicalRowKinds.count else {
            throw ShopReportProfileFailureV1.invalidValue
        }
        let rowKeys = records.shopReportProfiles.map {
            "\($0.workspaceID.rawValue.uuidString.lowercased())|\($0.profileID.uuidString.lowercased())|\(String(format: \"%020llu\", $0.revision))"
        }
        guard rowKeys == rowKeys.sorted() else {
            throw ShopReportProfileFailureV1.invalidValue
        }
        let mutationKeys = records.shopReportProfiles.map {
            MutationWorkspaceKeyV1.value(workspaceID: $0.workspaceID, mutationID: $0.mutationID)
        }
        guard Set(mutationKeys).count == mutationKeys.count else {
            throw ShopReportProfileFailureV1.invalidValue
        }
        for history in Dictionary(grouping: records.shopReportProfiles, by: {
            "\($0.workspaceID.rawValue.uuidString)|\($0.profileID.uuidString)"
        }).values {
            let values = history.sorted {
                ($0.revision, $0.mutationID.rawValue.uuidString)
                    < ($1.revision, $1.mutationID.rawValue.uuidString)
            }
            guard Set(values.map(\.revision)).count == values.count,
                  values.first?.revision == 1,
                  values.first?.predecessor == nil else {
                throw ShopReportProfileFailureV1.staleRevision
            }
            try values.forEach { try $0.validateIntrinsic() }
            for index in values.indices.dropFirst() {
                let predecessor = values[index - 1]
                let current = values[index]
                guard current.revision == predecessor.revision + 1,
                      current.predecessor == (try predecessor.reference),
                      current.recordedAt >= predecessor.recordedAt else {
                    throw ShopReportProfileFailureV1.staleRevision
                }
            }
        }
    }
}

enum C05RoundSessionBackupEnrollmentV1 {
    static let persistentSchemaVersion = 45
    static let recordsSchemaVersion = 44
    static let durableFamilyCount = 1
    static let canonicalRowKinds = ["RoundSessionRevisionRowV1"]

    static func validate(_ records: V4BackupRecordsV1) throws {
        if records.recordsSchemaVersion < recordsSchemaVersion {
            guard records.roundSessions.isEmpty else {
                throw RoundSessionFailureV1.staleRevision
            }
            return
        }
        guard records.recordsSchemaVersion == recordsSchemaVersion,
              durableFamilyCount == canonicalRowKinds.count else {
            throw RoundSessionFailureV1.staleRevision
        }
        let rowKeys = records.roundSessions.map {
            "\($0.workspaceID.rawValue.uuidString.lowercased())|\($0.sessionID.uuidString.lowercased())|\(String(format: \"%020llu\", $0.revision))"
        }
        guard rowKeys == rowKeys.sorted() else {
            throw RoundSessionFailureV1.staleRevision
        }
        let mutationKeys = records.roundSessions.map {
            MutationWorkspaceKeyV1.value(workspaceID: $0.workspaceID, mutationID: $0.mutationID)
        }
        guard Set(mutationKeys).count == mutationKeys.count else {
            throw RoundSessionFailureV1.staleRevision
        }
        for history in Dictionary(grouping: records.roundSessions, by: {
            "\($0.workspaceID.rawValue.uuidString)|\($0.sessionID.uuidString)"
        }).values {
            let values = history.sorted {
                ($0.revision, $0.mutationID.rawValue.uuidString)
                    < ($1.revision, $1.mutationID.rawValue.uuidString)
            }
            guard let first = values.first else {
                throw RoundSessionFailureV1.staleRevision
            }
            _ = try RoundSessionHistoryValidatorV1.validate(
                values,
                workspaceID: first.workspaceID,
                sessionID: first.sessionID
            )
        }
    }
}

enum C57MyDayBackupEnrollmentV1 {
    static let persistentSchemaVersion = 42
    static let recordsSchemaVersion = 41
    static let durableFamilyCount = 2
    static let canonicalRowKinds = ["MyDayPlanRowV1", "MyDayCarryoverReceiptRowV1"]
    static let replaceRestorePreservesExactHistory = true
    static let configurationCloneOmitsAllMyDayTruth = true
    static let workspaceForkRetainsNonactiveHistoryOnly = true
    static let readinessSourceStateAndDueAreExcluded = true

    static func orderedReferences(_ values: [MyDayPlanReferenceV1]) -> [MyDayPlanReferenceV1] {
        values.sorted {
            ($0.key.stableKey, $0.planID.uuidString, $0.revision, $0.planSHA256)
                < ($1.key.stableKey, $1.planID.uuidString, $1.revision, $1.planSHA256)
        }
    }

    static func exactNonactiveReferences(
        for plans: [MyDayPlanV1]
    ) throws -> [MyDayPlanReferenceV1] {
        let grouped = Dictionary(grouping: plans, by: { $0.key.stableKey })
        var result: [MyDayPlanReferenceV1] = []
        for values in grouped.values {
            let lineages = Set(values.map(\.planID))
            guard lineages.count == 1 else { throw MyDayFailureV1.divergentMutation }
            let ordered = values.sorted { $0.revision < $1.revision }
            guard ordered.first?.revision == 1 else { throw MyDayFailureV1.staleRevision }
            for (index, plan) in ordered.enumerated() {
                try plan.validate(predecessor: index == 0 ? nil : ordered[index - 1])
            }
            result.append(contentsOf: try ordered.dropLast().map(MyDayPlanReferenceV1.init))
        }
        return orderedReferences(result)
    }

    static func validate(_ records: V4BackupRecordsV1) throws {
        if records.recordsSchemaVersion < recordsSchemaVersion {
            guard records.myDayPlans.isEmpty, records.myDayCarryoverReceipts.isEmpty,
                  records.nonactivePlanReferences.isEmpty else {
                throw MyDayFailureV1.invalidValue
            }
            return
        }
        guard records.recordsSchemaVersion == recordsSchemaVersion else {
            throw MyDayFailureV1.invalidValue
        }
        try records.myDayPlans.forEach { try $0.validate() }
        try records.myDayCarryoverReceipts.forEach { try $0.validate() }
        try records.nonactivePlanReferences.forEach { try $0.validate() }
        let planIdentities = records.myDayPlans.map { "\($0.planID.uuidString)|\($0.revision)" }
        let planReferences = try Set(records.myDayPlans.map(MyDayPlanReferenceV1.init))
        let exactNonactive = try exactNonactiveReferences(for: records.myDayPlans)
        guard Set(planIdentities).count == planIdentities.count,
              Set(records.myDayCarryoverReceipts.map(\.receiptSHA256)).count
                == records.myDayCarryoverReceipts.count,
              records.nonactivePlanReferences == exactNonactive,
              Set(records.nonactivePlanReferences).count == records.nonactivePlanReferences.count,
              records.myDayCarryoverReceipts.allSatisfy {
                  planReferences.contains($0.sourcePlan) && planReferences.contains($0.targetPlan)
              } else {
            throw MyDayFailureV1.divergentMutation
        }
    }
}

/// C52 backup enrollment for the V39 store. Canonical request rows and both
/// append-only history families share one records envelope; all projections,
/// capability material, and import plans are reconstructed or operation-scoped.
enum C52ServiceRequestBackupEnrollmentV1 {
    static let persistentSchemaVersion = ServiceRequestPersistenceEnrollmentV1.targetPersistentSchemaVersion
    static let recordsSchemaVersion = 38
    static let durableFamilyCount = 3
    static let canonicalRowKinds = [
        "ServiceRequestRecordV1",
        "ServiceRequestDispositionEventV1",
        "ServiceRequestWorkLinkEventV1"
    ]
    static let immutableAcceptedSourceBytesAreRetained = true
    static let rawCapabilityBytesAreExcluded = true
    static let derivedProjectionsAreExcluded = true
    static let automaticWorkAndDuplicateActionsAreExcluded = true

    static func validate(
        records: V4BackupRecordsV1,
        workspaceID expectedWorkspaceID: UUID? = nil
    ) throws {
        try ServiceRequestPersistenceEnrollmentV1.validate()
        guard persistentSchemaVersion == 39,
              recordsSchemaVersion == 38,
              durableFamilyCount == canonicalRowKinds.count,
              canonicalRowKinds.count == 3,
              immutableAcceptedSourceBytesAreRetained,
              rawCapabilityBytesAreExcluded,
              derivedProjectionsAreExcluded,
              automaticWorkAndDuplicateActionsAreExcluded,
              !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent,
              !ServiceRequestNoncanonicalBoundaryV1.stateProjectionIsPersistent,
              !ServiceRequestNoncanonicalBoundaryV1.importPlanIsPersistent,
              !ServiceRequestNoncanonicalBoundaryV1.rawCapabilityIsWorkspaceTruth,
              !ServiceRequestNoncanonicalBoundaryV1.automaticWorkCreationPermitted,
              !ServiceRequestNoncanonicalBoundaryV1.automaticDuplicateMergePermitted else {
            throw ServiceRequestBackupContractFailureV1.invalidSchemaVersion
        }

        let containsServiceRequestRows = !records.serviceRequests.isEmpty
            || !records.serviceRequestDispositionEvents.isEmpty
            || !records.serviceRequestWorkLinkEvents.isEmpty
        // V38 is the first envelope carrying C52 rows. Older archives remain
        // decodable with their established empty-array defaults.
        guard !containsServiceRequestRows
                || (recordsSchemaVersion...C05RoundSessionBackupEnrollmentV1.recordsSchemaVersion)
                    .contains(records.recordsSchemaVersion) else {
            throw ServiceRequestBackupContractFailureV1.invalidSchemaVersion
        }
        guard records.recordsSchemaVersion < recordsSchemaVersion
                || records.mutationHistory != nil else {
            throw ServiceRequestBackupContractFailureV1.invalidSchemaVersion
        }

        let requestValues = try records.serviceRequests.map { try $0.value() }
        let dispositionValues = try records.serviceRequestDispositionEvents.map { try $0.value() }
        let workLinkValues = try records.serviceRequestWorkLinkEvents.map { try $0.value() }

        let requestKeys = requestValues.map(requestIdentity)
        guard Set(requestKeys).count == requestKeys.count,
              records.serviceRequests.map(recordIdentity) == records.serviceRequests.map(recordIdentity).sorted() else {
            throw ServiceRequestBackupContractFailureV1.invalidIdentity
        }
        let dispositionKeys = dispositionValues.map(eventIdentity)
        guard Set(dispositionKeys).count == dispositionKeys.count,
              records.serviceRequestDispositionEvents.map(dispositionIdentity)
                  == records.serviceRequestDispositionEvents.map(dispositionIdentity).sorted() else {
            throw ServiceRequestBackupContractFailureV1.invalidIdentity
        }
        let workLinkKeys = records.serviceRequestWorkLinkEvents.map(workLinkIdentity)
        guard Set(workLinkKeys).count == workLinkKeys.count,
              records.serviceRequestWorkLinkEvents.map(workLinkIdentity)
                  == records.serviceRequestWorkLinkEvents.map(workLinkIdentity).sorted() else {
            throw ServiceRequestBackupContractFailureV1.invalidIdentity
        }

        var workspaces = Set<UUID>()
        for value in requestValues {
            try value.validate()
            try value.acceptedSourceBytes?.validate()
            workspaces.insert(value.workspaceID.rawValue)
        }
        guard dispositionValues.allSatisfy({ value in
            workspaces.insert(value.workspaceID.rawValue)
            return true
        }), workLinkValues.allSatisfy({ value in
            workspaces.insert(value.workspaceID.rawValue)
            return true
        }), workspaces.count <= 1,
              expectedWorkspaceID.map({ workspaces.isEmpty || workspaces == Set([$0]) }) ?? true else {
            throw ServiceRequestBackupContractFailureV1.invalidWorkspaceBinding
        }

        var recordsByIdentity: [String: ServiceRequestRecordV1] = [:]
        for value in requestValues {
            recordsByIdentity[requestIdentity(value)] = value
        }
        try validateRecordHistory(requestValues)
        try validateDispositionHistory(dispositionValues, recordsByIdentity: recordsByIdentity)
        try validateWorkLinkHistory(workLinkValues, recordsByIdentity: recordsByIdentity)
    }

    static func canonicalRows(
        from records: V4BackupRecordsV1,
        workspaceID expectedWorkspaceID: UUID? = nil
    ) throws -> (
        records: [ServiceRequestRecordV1],
        dispositions: [ServiceRequestDispositionEventV1],
        workLinks: [ServiceRequestWorkLinkEventV1]
    ) {
        try validate(records: records, workspaceID: expectedWorkspaceID)
        return (
            try records.serviceRequests.map { try $0.value() },
            try records.serviceRequestDispositionEvents.map { try $0.value() },
            try records.serviceRequestWorkLinkEvents.map { try $0.value() }
        )
    }

    private static func requestIdentity(_ value: ServiceRequestRecordV1) -> String {
        "\(value.workspaceID.rawValue.uuidString.lowercased())|\(value.recordID.uuidString.lowercased())|\(value.revision)"
    }

    private static func recordIdentity(_ value: V38BackupServiceRequestRecordV1) -> String {
        "\(value.workspaceID.uuidString.lowercased())|\(value.recordID.uuidString.lowercased())|\(value.revision)"
    }

    private static func eventIdentity(_ value: ServiceRequestDispositionEventV1) -> String {
        "\(value.workspaceID.rawValue.uuidString.lowercased())|\(value.eventID.uuidString.lowercased())"
    }

    private static func dispositionIdentity(_ value: V38BackupServiceRequestDispositionEventV1) -> String {
        "\(value.workspaceID.uuidString.lowercased())|\(value.eventID.uuidString.lowercased())"
    }

    private static func workLinkIdentity(_ value: V38BackupServiceRequestWorkLinkEventV1) -> String {
        "\(value.workspaceID.uuidString.lowercased())|\(value.eventID.uuidString.lowercased())"
    }

    private static func chainIdentity(
        workspaceID: WorkspaceID,
        recordID: UUID,
        revision: UInt64
    ) -> String {
        "\(workspaceID.rawValue.uuidString.lowercased())|\(recordID.uuidString.lowercased())|\(revision)"
    }

    private static func validateRecordHistory(
        _ values: [ServiceRequestRecordV1]
    ) throws {
        let chains = Dictionary(grouping: values) {
            "\($0.workspaceID.rawValue.uuidString.lowercased())|\($0.recordID.uuidString.lowercased())"
        }
        for chain in chains.values {
            let ordered = chain.sorted { $0.revision < $1.revision }
            guard ordered.first?.revision == 1,
                  ordered.first?.supersedes == nil else {
                throw ServiceRequestBackupContractFailureV1.invalidHistory
            }
            for index in ordered.indices.dropFirst() {
                do { try ordered[index].validateSuccessor(of: ordered[index - 1]) }
                catch { throw ServiceRequestBackupContractFailureV1.invalidHistory }
            }
        }
    }

    private static func validateDispositionHistory(
        _ values: [ServiceRequestDispositionEventV1],
        recordsByIdentity: [String: ServiceRequestRecordV1]
    ) throws {
        for value in values {
            let key = chainIdentity(
                workspaceID: value.workspaceID,
                recordID: value.request.recordID,
                revision: value.request.revision
            )
            guard let request = recordsByIdentity[key],
                  request.recordSHA256 == value.request.recordSHA256 else {
                throw ServiceRequestBackupContractFailureV1.invalidHistory
            }
            if let duplicate = value.duplicateRecord {
                let duplicateKey = chainIdentity(
                    workspaceID: value.workspaceID,
                    recordID: duplicate.recordID,
                    revision: duplicate.revision
                )
                guard recordsByIdentity[duplicateKey]?.recordSHA256 == duplicate.recordSHA256 else {
                    throw ServiceRequestBackupContractFailureV1.invalidHistory
                }
            }
        }
        try validateDispositionChains(values)
    }

    private static func validateWorkLinkHistory(
        _ values: [ServiceRequestWorkLinkEventV1],
        recordsByIdentity: [String: ServiceRequestRecordV1]
    ) throws {
        for value in values {
            let key = chainIdentity(
                workspaceID: value.workspaceID,
                recordID: value.request.recordID,
                revision: value.request.revision
            )
            guard let request = recordsByIdentity[key],
                  request.recordSHA256 == value.request.recordSHA256 else {
                throw ServiceRequestBackupContractFailureV1.invalidHistory
            }
        }
        try validateWorkLinkChains(values)
    }

    private static func validateDispositionChains(
        _ values: [ServiceRequestDispositionEventV1]
    ) throws {
        let chains = Dictionary(grouping: values) {
            "\($0.workspaceID.rawValue.uuidString.lowercased())|\($0.request.recordID.uuidString.lowercased())|\($0.request.revision)"
        }
        for chain in chains.values {
            let ordered = chain.sorted { $0.revision < $1.revision }
            guard ordered.first?.revision == 1,
                  ordered.first?.predecessorEventID == nil,
                  ordered.first?.predecessorEventSHA256 == nil else {
                throw ServiceRequestBackupContractFailureV1.invalidHistory
            }
            for index in ordered.indices.dropFirst() {
                do { try ordered[index].validateSuccessor(of: ordered[index - 1]) }
                catch { throw ServiceRequestBackupContractFailureV1.invalidHistory }
            }
        }
    }

    private static func validateWorkLinkChains(
        _ values: [ServiceRequestWorkLinkEventV1]
    ) throws {
        let chains = Dictionary(grouping: values) {
            "\($0.workspaceID.rawValue.uuidString.lowercased())|\($0.request.recordID.uuidString.lowercased())|\($0.request.revision)"
        }
        for chain in chains.values {
            let ordered = chain.sorted { $0.revision < $1.revision }
            guard ordered.first?.revision == 1,
                  ordered.first?.predecessorEventID == nil,
                  ordered.first?.predecessorEventSHA256 == nil else {
                throw ServiceRequestBackupContractFailureV1.invalidHistory
            }
            for index in ordered.indices.dropFirst() {
                do { try ordered[index].validateSuccessor(of: ordered[index - 1]) }
                catch { throw ServiceRequestBackupContractFailureV1.invalidHistory }
            }
        }
    }
}

/// C53 backup enrollment is a projection of the existing mutation journal and
/// the seven SwiftData source families.  It deliberately has no projection or
/// capability storage of its own: restore writes the canonical rows through
/// the normal workspace writer and rebuilds metric projections afterwards.
struct C53ServiceReliabilityBackupRowsV1: Sendable {
    let incidents: [AssetServiceIncidentV1]
    let impactSegments: [ServiceImpactSegmentV1]
    let causeAssertions: [ServiceCauseAssertionV1]
    let remedyAssertions: [ServiceRemedyAssertionV1]
    let repairIntervals: [ServiceRepairIntervalV1]
    let restorationAssertions: [ServiceRestorationAssertionV1]
    let qualifiedExposures: [QualifiedServiceExposureV1]
    let receipts: [ServiceReliabilityMutationReceiptV1]
}

enum C53ServiceReliabilityBackupEnrollmentV1 {
    static let persistentSchemaVersion = AssetServiceReliabilityPersistenceEnrollmentV1.targetPersistentSchemaVersion
    static let recordsSchemaVersion = AssetServiceReliabilityPersistenceEnrollmentV1.recordsSchemaVersion
    static let durableFamilyCount = AssetServiceReliabilityPersistenceEnrollmentV1.durableFamilies.count
    static let canonicalRowKinds = [
        "ASSET_SERVICE_INCIDENT", "SERVICE_IMPACT_SEGMENT", "SERVICE_CAUSE_ASSERTION",
        "SERVICE_REMEDY_ASSERTION", "SERVICE_REPAIR_INTERVAL",
        "SERVICE_RESTORATION_ASSERTION", "QUALIFIED_SERVICE_EXPOSURE"
    ]
    static let appendOnlySourceHistory = true
    static let reliabilityIdentityEpochIsEmbedded = true
    static let derivedProjectionIsPersistent = AssetServiceReliabilityPersistenceEnrollmentV1.derivedProjectionIsPersistent
    static let rawCapabilityBytesAreExcluded = true

    static func validate(
        records: V4BackupRecordsV1,
        workspaceID expectedWorkspaceID: UUID? = nil
    ) throws {
        try AssetServiceReliabilityPersistenceEnrollmentV1.validate()
        guard persistentSchemaVersion == 40,
              recordsSchemaVersion == 39,
              durableFamilyCount == 7,
              canonicalRowKinds.count == durableFamilyCount,
              appendOnlySourceHistory,
              reliabilityIdentityEpochIsEmbedded,
              !derivedProjectionIsPersistent,
              rawCapabilityBytesAreExcluded else {
            throw C53ServiceReliabilityBackupContractFailureV1.invalidSchemaVersion
        }

        let hasRows = !records.serviceReliabilityIncidents.isEmpty
            || !records.serviceImpactSegments.isEmpty
            || !records.serviceCauseAssertions.isEmpty
            || !records.serviceRemedyAssertions.isEmpty
            || !records.serviceRepairIntervals.isEmpty
            || !records.serviceRestorationAssertions.isEmpty
            || !records.qualifiedServiceExposures.isEmpty
            || !records.serviceReliabilityReceipts.isEmpty
        if records.recordsSchemaVersion < recordsSchemaVersion {
            guard !hasRows else {
                throw C53ServiceReliabilityBackupContractFailureV1.invalidSchemaVersion
            }
            return
        }
        guard (recordsSchemaVersion...C05RoundSessionBackupEnrollmentV1.recordsSchemaVersion)
            .contains(records.recordsSchemaVersion) else {
            throw C53ServiceReliabilityBackupContractFailureV1.invalidSchemaVersion
        }

        let rows = try decodedRows(from: records)
        let allPayloads: [ServiceReliabilityMutationPayloadV1] =
            rows.incidents.map { .incident($0) }
            + rows.impactSegments.map { .impact($0) }
            + rows.causeAssertions.map { .cause($0) }
            + rows.remedyAssertions.map { .remedy($0) }
            + rows.repairIntervals.map { .repair($0) }
            + rows.restorationAssertions.map { .restoration($0) }
            + rows.qualifiedExposures.map { .exposure($0) }
        let workspaces = Set(allPayloads.map { $0.workspaceID.rawValue })
        guard workspaces.count <= 1,
              expectedWorkspaceID.map({ workspaces.isEmpty || workspaces == Set([$0]) }) ?? true else {
            throw C53ServiceReliabilityBackupContractFailureV1.invalidWorkspaceBinding
        }
        let assetIDs = Set(records.assets.map(\.id))
        guard allPayloads.allSatisfy({ payload in
            let subject: ServiceReliabilitySubjectV1
            switch payload {
            case .incident(let value): subject = value.subject
            case .impact(let value): subject = value.subject
            case .cause(let value): subject = value.subject
            case .remedy(let value): subject = value.subject
            case .repair(let value): subject = value.subject
            case .restoration(let value): subject = value.subject
            case .exposure(let value): subject = value.subject
            }
            return assetIDs.contains(subject.asset.subjectID)
        }) else {
            throw C53ServiceReliabilityBackupContractFailureV1.invalidWorkspaceBinding
        }

        try validateChain(rows.incidents, lineage: \.incidentID,
                          workspace: \.workspaceID, revision: \.revision,
                          predecessor: \.predecessor,
                          validate: { try $0.validate() },
                          successor: { try $0.validateSuccessor(of: $1) })
        try validateChain(rows.impactSegments, lineage: \.segmentID,
                          workspace: \.workspaceID, revision: \.revision,
                          predecessor: \.predecessor,
                          validate: { try $0.validate() },
                          successor: { try $0.validateSuccessor(of: $1) })
        try validateChain(rows.causeAssertions, lineage: \.assertionID,
                          workspace: \.workspaceID, revision: \.revision,
                          predecessor: \.predecessor,
                          validate: { try $0.validate() },
                          successor: { try $0.validateSuccessor(of: $1) })
        try validateChain(rows.remedyAssertions, lineage: \.assertionID,
                          workspace: \.workspaceID, revision: \.revision,
                          predecessor: \.predecessor,
                          validate: { try $0.validate() },
                          successor: { try $0.validateSuccessor(of: $1) })
        try validateChain(rows.repairIntervals, lineage: \.repairID,
                          workspace: \.workspaceID, revision: \.revision,
                          predecessor: \.predecessor,
                          validate: { try $0.validate() },
                          successor: { try $0.validateSuccessor(of: $1) })
        try validateChain(rows.restorationAssertions, lineage: \.assertionID,
                          workspace: \.workspaceID, revision: \.revision,
                          predecessor: \.predecessor,
                          validate: { try $0.validate() },
                          successor: { try $0.validateSuccessor(of: $1) })
        try validateChain(rows.qualifiedExposures, lineage: \.exposureID,
                          workspace: \.workspaceID, revision: \.revision,
                          predecessor: \.predecessor,
                          validate: { try $0.validate() },
                          successor: { try $0.validateSuccessor(of: $1) })

        let incidentIDs = Set(rows.incidents.map(\.incidentID))
        guard rows.impactSegments.allSatisfy({ incidentIDs.contains($0.incidentID) }),
              rows.causeAssertions.allSatisfy({ incidentIDs.contains($0.incidentID) }),
              rows.remedyAssertions.allSatisfy({ incidentIDs.contains($0.incidentID) }),
              rows.repairIntervals.allSatisfy({ incidentIDs.contains($0.incidentID) }),
              rows.restorationAssertions.allSatisfy({ incidentIDs.contains($0.incidentID) }) else {
            throw C53ServiceReliabilityBackupContractFailureV1.invalidHistory
        }

        var eventIDs = Set<UUID>()
        for payload in allPayloads {
            guard eventIDs.insert(payload.eventID).inserted else {
                throw C53ServiceReliabilityBackupContractFailureV1.invalidIdentity
            }
        }
        guard let history = records.mutationHistory else {
            guard allPayloads.isEmpty && rows.receipts.isEmpty else {
                throw C53ServiceReliabilityBackupContractFailureV1.invalidHistory
            }
            return
        }
        let historyClosure = try serviceReliabilityClosure(from: history)
        let rowPayloadsByEventID = Dictionary(uniqueKeysWithValues: allPayloads.map { ($0.eventID, $0) })
        let historyPayloadsByEventID = Dictionary(uniqueKeysWithValues: historyClosure.payloads.map { ($0.eventID, $0) })
        guard rowPayloadsByEventID == historyPayloadsByEventID else {
            throw C53ServiceReliabilityBackupContractFailureV1.invalidHistory
        }
        let orderedHistoryReceipts = historyClosure.receipts.sorted {
            $0.mutationReceipt.mutationID.rawValue.uuidString
                < $1.mutationReceipt.mutationID.rawValue.uuidString
        }
        guard rows.receipts == orderedHistoryReceipts else {
            throw C53ServiceReliabilityBackupContractFailureV1.invalidHistory
        }
        let receiptIDs = rows.receipts.map { $0.mutationReceipt.mutationID.rawValue }
        guard Set(receiptIDs).count == receiptIDs.count,
              receiptIDs == receiptIDs.sorted(by: { $0.uuidString < $1.uuidString }) else {
            throw C53ServiceReliabilityBackupContractFailureV1.invalidIdentity
        }
    }

    static func canonicalRows(
        from records: V4BackupRecordsV1,
        workspaceID expectedWorkspaceID: UUID? = nil
    ) throws -> C53ServiceReliabilityBackupRowsV1 {
        try validate(records: records, workspaceID: expectedWorkspaceID)
        return try decodedRows(from: records)
    }

    static func receiptRecords(
        from history: MutationHistorySnapshotV1?
    ) throws -> [V39BackupServiceReliabilityReceiptRecordV1] {
        guard let history else { return [] }
        return try serviceReliabilityReceipts(from: history)
            .map(V39BackupServiceReliabilityReceiptRecordV1.init)
            .sorted { $0.mutationID.uuidString < $1.mutationID.uuidString }
    }

    private static func decodedRows(
        from records: V4BackupRecordsV1
    ) throws -> C53ServiceReliabilityBackupRowsV1 {
        for rows in [
            records.serviceReliabilityIncidents,
            records.serviceImpactSegments,
            records.serviceCauseAssertions,
            records.serviceRemedyAssertions,
            records.serviceRepairIntervals,
            records.serviceRestorationAssertions,
            records.qualifiedServiceExposures
        ] {
            let keys = rows.map(rowKey)
            guard keys == keys.sorted(), Set(keys).count == keys.count else {
                throw C53ServiceReliabilityBackupContractFailureV1.invalidIdentity
            }
        }
        let incidentPayloads = try records.serviceReliabilityIncidents.map { try $0.value() }
        let impactPayloads = try records.serviceImpactSegments.map { try $0.value() }
        let causePayloads = try records.serviceCauseAssertions.map { try $0.value() }
        let remedyPayloads = try records.serviceRemedyAssertions.map { try $0.value() }
        let repairPayloads = try records.serviceRepairIntervals.map { try $0.value() }
        let restorationPayloads = try records.serviceRestorationAssertions.map { try $0.value() }
        let exposurePayloads = try records.qualifiedServiceExposures.map { try $0.value() }
        let incidents = try incidentPayloads.map { payload -> AssetServiceIncidentV1 in
            guard case .incident(let value) = payload else { throw C53ServiceReliabilityBackupContractFailureV1.invalidIdentity }
            return value
        }
        let impactSegments = try impactPayloads.map { payload -> ServiceImpactSegmentV1 in
            guard case .impact(let value) = payload else { throw C53ServiceReliabilityBackupContractFailureV1.invalidIdentity }
            return value
        }
        let causeAssertions = try causePayloads.map { payload -> ServiceCauseAssertionV1 in
            guard case .cause(let value) = payload else { throw C53ServiceReliabilityBackupContractFailureV1.invalidIdentity }
            return value
        }
        let remedyAssertions = try remedyPayloads.map { payload -> ServiceRemedyAssertionV1 in
            guard case .remedy(let value) = payload else { throw C53ServiceReliabilityBackupContractFailureV1.invalidIdentity }
            return value
        }
        let repairIntervals = try repairPayloads.map { payload -> ServiceRepairIntervalV1 in
            guard case .repair(let value) = payload else { throw C53ServiceReliabilityBackupContractFailureV1.invalidIdentity }
            return value
        }
        let restorationAssertions = try restorationPayloads.map { payload -> ServiceRestorationAssertionV1 in
            guard case .restoration(let value) = payload else { throw C53ServiceReliabilityBackupContractFailureV1.invalidIdentity }
            return value
        }
        let qualifiedExposures = try exposurePayloads.map { payload -> QualifiedServiceExposureV1 in
            guard case .exposure(let value) = payload else { throw C53ServiceReliabilityBackupContractFailureV1.invalidIdentity }
            return value
        }
        let receipts = try records.serviceReliabilityReceipts.map { try $0.value() }
        return C53ServiceReliabilityBackupRowsV1(
            incidents: incidents, impactSegments: impactSegments,
            causeAssertions: causeAssertions, remedyAssertions: remedyAssertions,
            repairIntervals: repairIntervals, restorationAssertions: restorationAssertions,
            qualifiedExposures: qualifiedExposures, receipts: receipts
        )
    }

    private static func rowKey(_ value: V39BackupServiceReliabilityRecordV1) -> String {
        "\(value.kind.rawValue)|\(value.workspaceID.uuidString.lowercased())|\(value.lineageID.uuidString.lowercased())|\(value.revision)|\(value.eventID.uuidString.lowercased())"
    }

    private static func validateChain<T>(
        _ values: [T],
        lineage: (T) -> UUID,
        workspace: (T) -> WorkspaceID,
        revision: (T) -> UInt64,
        predecessor: (T) -> ServiceReliabilityEventReferenceV1?,
        validate: (T) throws -> Void,
        successor: (T, T) throws -> Void
    ) throws {
        let groups = Dictionary(grouping: values) {
            "\(workspace($0).rawValue.uuidString.lowercased())|\(lineage($0).uuidString.lowercased())"
        }
        for group in groups.values {
            let ordered = group.sorted { revision($0) < revision($1) }
            let revisions = ordered.map(revision)
            guard let first = ordered.first,
                  revision(first) == 1,
                  predecessor(first) == nil,
                  Set(revisions).count == revisions.count else {
                throw C53ServiceReliabilityBackupContractFailureV1.invalidHistory
            }
            try ordered.forEach(validate)
            for index in ordered.indices.dropFirst() {
                do { try successor(ordered[index], ordered[index - 1]) }
                catch { throw C53ServiceReliabilityBackupContractFailureV1.invalidHistory }
            }
        }
    }

    private static func serviceReliabilityClosure(
        from history: MutationHistorySnapshotV1
    ) throws -> (payloads:[ServiceReliabilityMutationPayloadV1],receipts:[ServiceReliabilityMutationReceiptV1]) {
        var payloads:[ServiceReliabilityMutationPayloadV1]=[]
        var receipts:[ServiceReliabilityMutationReceiptV1]=[]
        var mutationIDs=Set<UUID>(),eventIDs=Set<UUID>()
        for record in history.receipts {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
            guard case let .applyServiceReliability(bundle) = envelope.command else { continue }
            let receipt = try MutationReceiptV1.decodeCanonical(from: record.receiptData)
            let typedReceipt=try ServiceReliabilityMutationReceiptV1(bundle:bundle,mutationReceipt:receipt)
            guard mutationIDs.insert(bundle.mutationID.rawValue).inserted,
                  bundle.payloads.allSatisfy({eventIDs.insert($0.eventID).inserted}),
                  typedReceipt.postImages == (try bundle.mutationPostImages) else {
                throw C53ServiceReliabilityBackupContractFailureV1.invalidHistory
            }
            payloads += bundle.payloads
            receipts.append(typedReceipt)
        }
        return (payloads,receipts)
    }

    private static func serviceReliabilityReceipts(
        from history: MutationHistorySnapshotV1
    ) throws -> [ServiceReliabilityMutationReceiptV1] {
        try serviceReliabilityClosure(from:history).receipts
    }
}

/// C55 owns exactly one snapshot that contains all seven durable PartsStock
/// families.  It is intentionally a record-envelope field, rather than a
/// sidecar, so archive validation and replacement restore see the same truth.
enum C55PartsStockBackupEnrollmentV1 {
    static let persistentSchemaVersion = C55PartsStockKernelBackupRestoreEnrollmentV1.persistentSchemaVersion
    static let recordsSchemaVersion = 40
    static let durableFamilyCount = C55PartsStockKernelBackupRestoreEnrollmentV1.durableFamilies.count

    static func validate(_ records: V4BackupRecordsV1, workspaceID: WorkspaceID? = nil) throws {
        guard persistentSchemaVersion == 41, recordsSchemaVersion == 40,
              durableFamilyCount == 7 else { throw PartsStockFailureV1.incompatibleVersion }
        guard records.recordsSchemaVersion >= recordsSchemaVersion else {
            guard records.partsStockSnapshot == nil else { throw PartsStockFailureV1.incompatibleVersion }
            return
        }
        guard records.recordsSchemaVersion >= recordsSchemaVersion,
              let snapshot = records.partsStockSnapshot else { throw PartsStockFailureV1.incompatibleVersion }
        try snapshot.validate()
        guard workspaceID.map({ snapshot.workspaceID == $0 }) ?? true else {
            throw PartsStockFailureV1.crossWorkspace
        }
        guard unique(snapshot.parts.map(\.partID)),
              unique(snapshot.locations.map(\.locationID)),
              unique(snapshot.movements.map(\.movementID)),
              unique(snapshot.uses.map(\.receiptID)),
              unique(snapshot.reversals.map(\.receiptID)),
              unique(snapshot.returns.map(\.receiptID)),
              unique(snapshot.abandonments.map(\.dispositionID)),
              snapshot.parts.map(\.partID.uuidString) == snapshot.parts.map(\.partID.uuidString).sorted(),
              snapshot.locations.map(\.locationID.uuidString) == snapshot.locations.map(\.locationID.uuidString).sorted(),
              snapshot.movements.map { ($0.recordedAt, $0.movementID.uuidString) }
                == snapshot.movements.map { ($0.recordedAt, $0.movementID.uuidString) }.sorted(by: { $0 < $1 }),
              snapshot.uses.map(\.receiptID.uuidString) == snapshot.uses.map(\.receiptID.uuidString).sorted(),
              snapshot.reversals.map(\.receiptID.uuidString) == snapshot.reversals.map(\.receiptID.uuidString).sorted(),
              snapshot.returns.map(\.receiptID.uuidString) == snapshot.returns.map(\.receiptID.uuidString).sorted(),
              snapshot.abandonments.map(\.dispositionID.uuidString) == snapshot.abandonments.map(\.dispositionID.uuidString).sorted() else {
            throw PartsStockFailureV1.duplicateMutation
        }
        let partIDs = Set(snapshot.parts.map(\.partID))
        let locationIDs = Set(snapshot.locations.map(\.locationID))
        let movementByID = Dictionary(uniqueKeysWithValues: snapshot.movements.map { ($0.movementID, $0) })
        let useByID = Dictionary(uniqueKeysWithValues: snapshot.uses.map { ($0.receiptID, $0) })
        guard snapshot.movements.allSatisfy({ partIDs.contains($0.part.partID) && locationIDs.contains($0.locationID) }),
              snapshot.uses.allSatisfy({ movementByID[$0.movement.movementID] == $0.movement }),
              snapshot.reversals.allSatisfy({ useByID[$0.sourceUse.receiptID] == $0.sourceUse && movementByID[$0.reversalMovement.movementID] == $0.reversalMovement }),
              snapshot.returns.allSatisfy({ useByID[$0.sourceUse.receiptID] == $0.sourceUse && movementByID[$0.returnMovement.movementID] == $0.returnMovement }),
              snapshot.abandonments.allSatisfy({ partIDs.contains($0.partID) && locationIDs.contains($0.locationID) && ($0.lastMovementID.map { movementByID[$0] != nil } ?? true) }) else {
            throw PartsStockFailureV1.invalidTransition
        }
        guard let history = records.mutationHistory else { throw PartsStockFailureV1.invalidTransition }
        try validateJournal(snapshot, history: history)
    }

    private static func validateJournal(
        _ snapshot: PartsStockBackupSnapshotV1,
        history: MutationHistorySnapshotV1
    ) throws {
        func isStockKind(_ kind: WorkspaceEntityKindV1) -> Bool {
            switch kind {
            case .localPartDefinition, .stockStorageLocation, .stockBalanceStream,
                 .stockMovementEvent, .stockUseReceipt, .stockUseReversalReceipt,
                 .stockReturnReceipt, .stockAbandonment:
                return true
            default:
                return false
            }
        }

        func stockRevisionMap(
            _ value: MutationPortableExpectedRevisionV1
        ) -> [WorkspaceEntityIdentityV1: UInt64] {
            Dictionary(uniqueKeysWithValues: value.entityRevisions.compactMap {
                isStockKind($0.identity.kind) ? ($0.identity, $0.revision) : nil
            })
        }

        func physicalIdentity(
            for image: MutationPostImageV1
        ) throws -> WorkspaceEntityIdentityV1 {
            if case let .partsStock(id, kind, _, _, _) = image {
                return try WorkspaceEntityIdentityV1(kind: kind, id: id)
            }
            return try image.identity
        }

        let partByID = Dictionary(uniqueKeysWithValues: snapshot.parts.map { ($0.partID, $0) })
        let locationByID = Dictionary(uniqueKeysWithValues: snapshot.locations.map {
            ($0.locationID, $0)
        })
        var parts: [UUID: LocalPartDefinitionV1] = [:]
        var locations: [UUID: StockStorageLocationV1] = [:]
        var movements: [UUID: StockMovementEventV1] = [:]
        var uses: [UUID: StockUseOnWorkReceiptV1] = [:]
        var reversals: [UUID: StockUseReversalReceiptV1] = [:]
        var returns: [UUID: StockReturnAgainstUseReceiptV1] = [:]
        var abandonments: [UUID: AbandonUnverifiedStockDispositionV1] = [:]
        var terminalStockRevisions: [WorkspaceEntityIdentityV1: MutationHistoryEntityRevisionV1] = [:]
        for value in history.entityRevisions where isStockKind(value.identity.kind) {
            guard terminalStockRevisions.updateValue(value, forKey: value.identity) == nil else {
                throw PartsStockFailureV1.duplicateMutation
            }
        }
        var stockState: [WorkspaceEntityIdentityV1: UInt64] = [:]
        var externalPartBaselines: [UUID: LocalPartDefinitionV1] = [:]
        var externalLocationBaselines: [UUID: StockStorageLocationV1] = [:]
        for value in history.entityRevisions where value.externalProjectionSHA256 != nil {
            guard isStockKind(value.identity.kind) else { continue }
            guard let digest = value.externalProjectionSHA256,
                  MutationEnvelopeV1.isSHA256(digest) else {
                throw PartsStockFailureV1.invalidTransition
            }
            switch value.identity.kind {
            case .localPartDefinition:
                guard let part = partByID[value.identity.id],
                      part.revision == value.revision,
                      part.partSHA256 == digest,
                      externalPartBaselines.updateValue(part, forKey: part.partID) == nil else {
                    throw PartsStockFailureV1.invalidTransition
                }
            case .stockStorageLocation:
                guard let location = locationByID[value.identity.id],
                      location.revision == value.revision,
                      try PartsStockCanonicalCodecV1.sha256(location) == digest,
                      externalLocationBaselines.updateValue(
                        location,
                        forKey: location.locationID
                      ) == nil else {
                    throw PartsStockFailureV1.invalidTransition
                }
            case .stockBalanceStream, .stockMovementEvent, .stockUseReceipt,
                 .stockUseReversalReceipt, .stockReturnReceipt, .stockAbandonment:
                throw PartsStockFailureV1.invalidTransition
            default:
                throw PartsStockFailureV1.invalidTransition
            }
        }
        let projected = !externalPartBaselines.isEmpty || !externalLocationBaselines.isEmpty
        for partID in externalPartBaselines.keys {
            stockState[try WorkspaceEntityIdentityV1(
                kind: .localPartDefinition,
                id: partID
            )] = 1
        }
        for locationID in externalLocationBaselines.keys {
            stockState[try WorkspaceEntityIdentityV1(
                kind: .stockStorageLocation,
                id: locationID
            )] = 1
        }

        func latestPart(_ value: LocalPartDefinitionV1) throws {
            if let existing = parts[value.partID] {
                let (next, overflow) = existing.revision.addingReportingOverflow(1)
                guard !overflow, existing != value, value.revision == next else {
                    throw PartsStockFailureV1.invalidTransition
                }
            } else if value.revision != 1 {
                guard projected,
                      let baseline = externalPartBaselines[value.partID],
                      value.revision <= baseline.revision else {
                    throw PartsStockFailureV1.invalidTransition
                }
            }
            parts[value.partID] = value
        }
        func latestLocation(_ value: StockStorageLocationV1) throws {
            if let existing = locations[value.locationID] {
                let (next, overflow) = existing.revision.addingReportingOverflow(1)
                guard !overflow, existing != value, value.revision == next else {
                    throw PartsStockFailureV1.invalidTransition
                }
            } else if value.revision != 1 {
                guard projected,
                      let baseline = externalLocationBaselines[value.locationID],
                      value.revision <= baseline.revision else {
                    throw PartsStockFailureV1.invalidTransition
                }
            }
            locations[value.locationID] = value
        }
        func append<T: Equatable>(_ value: T, id: UUID, to values: inout [UUID: T]) throws {
            guard values.updateValue(value, forKey: id) == nil else {
                throw PartsStockFailureV1.duplicateMutation
            }
        }

        struct DecodedReceipt {
            let envelope: MutationEnvelopeV1
            let receipt: MutationReceiptV1
        }
        guard history.quarantines.allSatisfy({
            $0.workspaceID == snapshot.workspaceID
        }) else {
            throw PartsStockFailureV1.crossWorkspace
        }
        let decoded = try history.receipts.map { record in
            DecodedReceipt(
                envelope: try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData),
                receipt: try MutationReceiptV1.decodeCanonical(from: record.receiptData)
            )
        }.sorted {
            if $0.receipt.expectedRevision.workspaceRevision
                != $1.receipt.expectedRevision.workspaceRevision {
                return $0.receipt.expectedRevision.workspaceRevision
                    < $1.receipt.expectedRevision.workspaceRevision
            }
            return $0.receipt.identity.stableKey < $1.receipt.identity.stableKey
        }
        var priorResultingWorkspaceRevision: UInt64?
        var importedPrefixCutoff: UInt64 = 0
        var sawNonImportedReceipt = false
        var workspaceResults = Set<UInt64>()
        var explainedPartRevision: [UUID: UInt64] = [:]
        var explainedLocationRevision: [UUID: UInt64] = [:]

        for value in decoded {
            let envelope = value.envelope
            let receipt = value.receipt
            let receiptExpected = Dictionary(uniqueKeysWithValues: receipt.expectedRevision.entityRevisions.map {
                ($0.identity, $0.revision)
            })
            let receiptResult = Dictionary(uniqueKeysWithValues: receipt.resultingRevision.entityRevisions.map {
                ($0.identity, $0.revision)
            })
            guard receipt.envelopeSHA256 == (try envelope.canonicalSHA256()),
                  receipt.expectedRevision == envelope.expectedRevision,
                  envelope.workspaceID == snapshot.workspaceID,
                  receipt.identity.workspaceID == snapshot.workspaceID,
                  receipt.expectedRevision.workspaceID == snapshot.workspaceID,
                  receipt.resultingRevision.workspaceID == snapshot.workspaceID,
                  receipt.identity.workspaceID == envelope.workspaceID,
                  receipt.resultingRevision.workspaceID == envelope.workspaceID,
                  receipt.resultingRevision.generationID == envelope.generationID else {
                throw PartsStockFailureV1.invalidTransition
            }
            let expectedWorkspaceRevision = receipt.expectedRevision.workspaceRevision
            let (nextWorkspaceRevision, workspaceRevisionOverflow) =
                expectedWorkspaceRevision.addingReportingOverflow(1)
            guard !workspaceRevisionOverflow,
                  receipt.resultingRevision.workspaceRevision
                    == nextWorkspaceRevision,
                  workspaceResults.insert(nextWorkspaceRevision).inserted else {
                throw PartsStockFailureV1.invalidTransition
            }
            if envelope.sourceKind == .importedHistory {
                guard !sawNonImportedReceipt,
                      priorResultingWorkspaceRevision.map({
                          expectedWorkspaceRevision >= $0
                      }) ?? true else {
                    throw PartsStockFailureV1.staleRevision
                }
                importedPrefixCutoff = nextWorkspaceRevision
            } else {
                let expectedPredecessor = priorResultingWorkspaceRevision
                    ?? importedPrefixCutoff
                guard expectedWorkspaceRevision == expectedPredecessor else {
                    throw PartsStockFailureV1.staleRevision
                }
                sawNonImportedReceipt = true
            }
            guard receipt.resultingRevision.workspaceRevision <= history.workspaceRevision else {
                throw PartsStockFailureV1.invalidTransition
            }
            priorResultingWorkspaceRevision = receipt.resultingRevision.workspaceRevision
            guard case let .applyPartsStock(mutation) = envelope.command else {
                let receiptImages = try receipt.postImages.map {
                    (try physicalIdentity(for: $0), try $0.concurrencyIdentity)
                }
                let expectedStock = stockRevisionMap(receipt.expectedRevision)
                let resultingStock = stockRevisionMap(receipt.resultingRevision)
                guard receiptImages.allSatisfy({
                          !isStockKind($0.0.kind) && !isStockKind($0.1.kind)
                      }),
                      expectedStock.isEmpty,
                      projected && envelope.sourceKind == .importedHistory
                        ? (resultingStock.isEmpty || resultingStock == stockState)
                        : resultingStock == stockState else {
                    throw PartsStockFailureV1.invalidTransition
                }
                continue
            }
            try mutation.validate()
            let images = try mutation.mutationPostImages
            let concurrency = try mutation.concurrencyIdentities
            let expectedByMutation = try Dictionary(uniqueKeysWithValues: concurrency.map {
                ($0, try mutation.expectedRevision(for: $0))
            })
            guard envelope.commandKind == .applyPartsStock,
                  envelope.mutationID == mutation.mutationID,
                  envelope.workspaceID == snapshot.workspaceID,
                  mutation.workspaceID == snapshot.workspaceID,
                  receipt.mutationID == mutation.mutationID,
                  receipt.identity.workspaceID == snapshot.workspaceID,
                  receipt.commandBodySHA256 == (try WorkspaceMutationCanonicalV1.sha256(
                    WorkspaceCommandV1.applyPartsStock(mutation)
                  )),
                  receipt.postImages == images,
                  receiptExpected.count == concurrency.count,
                  Set(receiptExpected.keys) == Set(concurrency),
                  receiptExpected == expectedByMutation,
                  try images.allSatisfy {
                      receiptResult[try physicalIdentity(for: $0)] == $0.revision
                        && receiptResult[try $0.concurrencyIdentity] == $0.revision
                  } else {
                throw PartsStockFailureV1.invalidTransition
            }
            let expectedStock = stockRevisionMap(receipt.expectedRevision)
            for image in images {
                let identity = try physicalIdentity(for: image)
                switch identity.kind {
                case .localPartDefinition:
                    guard let baseline = externalPartBaselines[identity.id] else { break }
                    let expected = expectedStock[identity]
                    let prior = explainedPartRevision[identity.id]
                    let (successor, overflow) = (expected ?? 0).addingReportingOverflow(1)
                    guard let expected,
                          !overflow,
                          expected == (prior ?? 1),
                          image.revision == successor,
                          image.revision <= baseline.revision else {
                        throw PartsStockFailureV1.staleRevision
                    }
                    explainedPartRevision[identity.id] = image.revision
                case .stockStorageLocation:
                    guard let baseline = externalLocationBaselines[identity.id] else { break }
                    let expected = expectedStock[identity]
                    let prior = explainedLocationRevision[identity.id]
                    let (successor, overflow) = (expected ?? 0).addingReportingOverflow(1)
                    guard let expected,
                          !overflow,
                          expected == (prior ?? 1),
                          image.revision == successor,
                          image.revision <= baseline.revision else {
                        throw PartsStockFailureV1.staleRevision
                    }
                    explainedLocationRevision[identity.id] = image.revision
                default:
                    break
                }
            }
            for (identity, expected) in expectedStock
                where stockState[identity] == nil && expected > 0 {
                let (successor, overflow) = expected.addingReportingOverflow(1)
                guard !overflow,
                      let image = try images.first(where: {
                          try physicalIdentity(for: $0) == identity
                      }),
                      image.revision == successor else {
                    throw PartsStockFailureV1.staleRevision
                }
                switch identity.kind {
                case .localPartDefinition:
                    guard projected,
                          let baseline = externalPartBaselines[identity.id],
                          successor <= baseline.revision else {
                        throw PartsStockFailureV1.staleRevision
                    }
                case .stockStorageLocation:
                    guard projected,
                          let baseline = externalLocationBaselines[identity.id],
                          successor <= baseline.revision else {
                        throw PartsStockFailureV1.staleRevision
                    }
                default:
                    throw PartsStockFailureV1.staleRevision
                }
                stockState[identity] = expected
            }
            switch mutation {
            case let .retirePart(value):
                let identity = try WorkspaceEntityIdentityV1(
                    kind: .localPartDefinition,
                    id: value.predecessorPart.partID
                )
                if parts[value.predecessorPart.partID] == nil {
                    guard projected,
                          expectedStock[identity] == value.predecessorPart.revision,
                          let baseline = externalPartBaselines[value.predecessorPart.partID],
                          value.archivedPartSuccessor.revision <= baseline.revision else {
                        throw PartsStockFailureV1.invalidTransition
                    }
                    parts[value.predecessorPart.partID] = value.predecessorPart
                }
            case let .abandon(value):
                let identity = try WorkspaceEntityIdentityV1(
                    kind: .localPartDefinition,
                    id: value.predecessorPart.partID
                )
                if parts[value.predecessorPart.partID] == nil {
                    guard projected,
                          expectedStock[identity] == value.predecessorPart.revision,
                          let baseline = externalPartBaselines[value.predecessorPart.partID],
                          value.archivedPartSuccessor.revision <= baseline.revision else {
                        throw PartsStockFailureV1.invalidTransition
                    }
                    parts[value.predecessorPart.partID] = value.predecessorPart
                }
            default:
                break
            }
            guard expectedStock.allSatisfy({
                stockState[$0.key, default: 0] == $0.value
            }) else {
                throw PartsStockFailureV1.staleRevision
            }
            var nextStockState = stockState
            for image in images {
                let identity = try physicalIdentity(for: image)
                let concurrencyIdentity = try image.concurrencyIdentity
                if isStockKind(identity.kind) {
                    nextStockState[identity] = image.revision
                }
                if isStockKind(concurrencyIdentity.kind) {
                    nextStockState[concurrencyIdentity] = image.revision
                }
            }
            let resultingStock = stockRevisionMap(receipt.resultingRevision)
            if projected {
                for (identity, revision) in resultingStock
                    where nextStockState[identity] == nil {
                    switch identity.kind {
                    case .localPartDefinition:
                        guard let baseline = externalPartBaselines[identity.id],
                              revision <= baseline.revision else {
                            throw PartsStockFailureV1.invalidTransition
                        }
                    case .stockStorageLocation:
                        guard let baseline = externalLocationBaselines[identity.id],
                              revision <= baseline.revision else {
                            throw PartsStockFailureV1.invalidTransition
                        }
                    default:
                        throw PartsStockFailureV1.invalidTransition
                    }
                    nextStockState[identity] = revision
                }
            }
            guard resultingStock == nextStockState else {
                throw PartsStockFailureV1.invalidTransition
            }
            stockState = nextStockState
            switch mutation {
            case let .upsertPart(value):
                try latestPart(value)
            case let .retirePart(value):
                guard parts[value.predecessorPart.partID] == value.predecessorPart else {
                    throw PartsStockFailureV1.invalidTransition
                }
                try latestPart(value.archivedPartSuccessor)
            case let .abandon(value):
                guard parts[value.predecessorPart.partID] == value.predecessorPart else {
                    throw PartsStockFailureV1.invalidTransition
                }
                try latestPart(value.archivedPartSuccessor)
                for disposition in value.dispositions {
                    try append(disposition, id: disposition.dispositionID, to: &abandonments)
                }
            case let .upsertLocation(value, _):
                try latestLocation(value)
            case let .appendMovement(value):
                try append(value, id: value.movementID, to: &movements)
            case let .transfer(value):
                try append(value.outbound, id: value.outbound.movementID, to: &movements)
                try append(value.inbound, id: value.inbound.movementID, to: &movements)
            case let .use(value):
                guard value.mutationID == mutation.mutationID,
                      value.movement.mutationID == mutation.mutationID,
                      value.workResourceSuccessor.mutationID == mutation.mutationID else {
                    throw PartsStockFailureV1.invalidTransition
                }
                try append(value.movement, id: value.movement.movementID, to: &movements)
                try append(value, id: value.receiptID, to: &uses)
            case let .reverseUse(value):
                guard value.mutationID == mutation.mutationID,
                      value.reversalMovement.mutationID == mutation.mutationID,
                      value.workResourceSuccessor.mutationID == mutation.mutationID else {
                    throw PartsStockFailureV1.invalidTransition
                }
                try append(value.reversalMovement, id: value.reversalMovement.movementID, to: &movements)
                try append(value, id: value.receiptID, to: &reversals)
            case let .returnAgainstUse(value):
                guard value.mutationID == mutation.mutationID,
                      value.returnMovement.mutationID == mutation.mutationID,
                      value.workResourceSuccessor.mutationID == mutation.mutationID else {
                    throw PartsStockFailureV1.invalidTransition
                }
                try append(value.returnMovement, id: value.returnMovement.movementID, to: &movements)
                try append(value, id: value.receiptID, to: &returns)
            }
        }

        let derivedTerminalWorkspaceRevision = priorResultingWorkspaceRevision
            ?? importedPrefixCutoff
        guard derivedTerminalWorkspaceRevision == history.workspaceRevision else {
            throw PartsStockFailureV1.invalidTransition
        }
        for (partID, baseline) in externalPartBaselines {
            guard baseline.revision == 1
                    ? explainedPartRevision[partID] == nil
                    : explainedPartRevision[partID] == baseline.revision else {
                throw PartsStockFailureV1.invalidTransition
            }
        }
        for (locationID, baseline) in externalLocationBaselines {
            guard baseline.revision == 1
                    ? explainedLocationRevision[locationID] == nil
                    : explainedLocationRevision[locationID] == baseline.revision else {
                throw PartsStockFailureV1.invalidTransition
            }
        }
        for (partID, part) in externalPartBaselines where parts[partID] == nil {
            let identity = try WorkspaceEntityIdentityV1(
                kind: .localPartDefinition,
                id: partID
            )
            guard stockState[identity].map({ $0 == part.revision }) ?? true else {
                throw PartsStockFailureV1.invalidTransition
            }
            parts[partID] = part
            stockState[identity] = part.revision
        }
        for (locationID, location) in externalLocationBaselines
            where locations[locationID] == nil {
            let identity = try WorkspaceEntityIdentityV1(
                kind: .stockStorageLocation,
                id: locationID
            )
            guard stockState[identity].map({ $0 == location.revision }) ?? true else {
                throw PartsStockFailureV1.invalidTransition
            }
            locations[locationID] = location
            stockState[identity] = location.revision
        }
        let terminalStockMap = Dictionary(
            uniqueKeysWithValues: terminalStockRevisions.map { ($0.key, $0.value.revision) }
        )
        guard terminalStockMap == stockState else {
            throw PartsStockFailureV1.invalidTransition
        }

        guard parts.values.sorted(by: { $0.partID.uuidString < $1.partID.uuidString }) == snapshot.parts,
              locations.values.sorted(by: { $0.locationID.uuidString < $1.locationID.uuidString }) == snapshot.locations,
              movements.values.sorted(by: { ($0.recordedAt, $0.movementID.uuidString) < ($1.recordedAt, $1.movementID.uuidString) }) == snapshot.movements,
              uses.values.sorted(by: { $0.receiptID.uuidString < $1.receiptID.uuidString }) == snapshot.uses,
              reversals.values.sorted(by: { $0.receiptID.uuidString < $1.receiptID.uuidString }) == snapshot.reversals,
              returns.values.sorted(by: { $0.receiptID.uuidString < $1.receiptID.uuidString }) == snapshot.returns,
              abandonments.values.sorted(by: { $0.dispositionID.uuidString < $1.dispositionID.uuidString }) == snapshot.abandonments else {
            throw PartsStockFailureV1.invalidTransition
        }
    }

    private static func unique(_ values: [UUID]) -> Bool { Set(values).count == values.count }
}

enum C47ActivityContractMutationOrderingV2 {
    static func orderedIndices(
        for mutations: [ActivityContractMutationV2]
    ) throws -> [Int] {
        var indexByEnvelopeSHA256: [String: Int] = [:]
        for (index, mutation) in mutations.enumerated() {
            guard indexByEnvelopeSHA256.updateValue(
                index,
                forKey: mutation.successorEnvelope.envelopeSHA256
            ) == nil else {
                throw ActivityContractFailureV2.duplicateIdentity
            }
        }

        var indegree = Array(repeating: 0, count: mutations.count)
        var dependents = Array(repeating: [Int](), count: mutations.count)
        for (index, mutation) in mutations.enumerated() {
            let dependencySHA256s = Set([
                mutation.predecessorEnvelope?.envelopeSHA256,
                mutation.successorEnvelope.amendment?.predecessorSHA256
            ].compactMap { $0 })
            for dependencySHA256 in dependencySHA256s {
                guard let dependencyIndex = indexByEnvelopeSHA256[dependencySHA256] else {
                    throw ActivityContractFailureV2.missingReference
                }
                indegree[index] += 1
                dependents[dependencyIndex].append(index)
            }
        }

        func comesBefore(_ lhs: Int, _ rhs: Int) -> Bool {
            let lhsMutation = mutations[lhs]
            let rhsMutation = mutations[rhs]
            let lhsWorkspace = lhsMutation.workspaceID.rawValue.uuidString.lowercased()
            let rhsWorkspace = rhsMutation.workspaceID.rawValue.uuidString.lowercased()
            if lhsWorkspace != rhsWorkspace { return lhsWorkspace < rhsWorkspace }
            let lhsActivity = lhsMutation.successorEnvelope.activityID.uuidString.lowercased()
            let rhsActivity = rhsMutation.successorEnvelope.activityID.uuidString.lowercased()
            if lhsActivity != rhsActivity { return lhsActivity < rhsActivity }
            if lhsMutation.successorEnvelope.revision
                != rhsMutation.successorEnvelope.revision {
                return lhsMutation.successorEnvelope.revision
                    < rhsMutation.successorEnvelope.revision
            }
            let lhsID = lhsMutation.mutationID.rawValue.uuidString.lowercased()
            let rhsID = rhsMutation.mutationID.rawValue.uuidString.lowercased()
            if lhsID != rhsID { return lhsID < rhsID }
            return lhs < rhs
        }

        for index in dependents.indices {
            dependents[index].sort(by: comesBefore)
        }
        var ready = mutations.indices.filter { indegree[$0] == 0 }.sorted(by: comesBefore)
        var ordered: [Int] = []
        var readyIndex = 0
        while readyIndex < ready.count {
            let index = ready[readyIndex]
            readyIndex += 1
            ordered.append(index)
            for dependent in dependents[index] {
                indegree[dependent] -= 1
                if indegree[dependent] == 0 {
                    ready.append(dependent)
                }
            }
        }
        guard ordered.count == mutations.count else {
            throw ActivityContractFailureV2.staleRevision
        }
        return ordered
    }
}

extension V4BackupRecordsV1 {
    func validateC47ActivityContracts() throws -> (
        envelopes: [ActivitySessionEnvelopeV2], transitions: [ActivityStateTransitionV2],
        taskResults: [InstallationTaskResultV1], asBuilt: [InstallationAsBuiltSnapshotV1],
        punchBasis: [PunchReviewBasisSnapshotV1]
    ) {
        if recordsSchemaVersion < C47ActivityContractPersistenceBoundaryV2.recordsSchemaVersion {
            guard activityContracts.isEmpty else { throw ActivityContractFailureV2.incompatibleVersion }
            return ([], [], [], [], [])
        }
        guard (C47ActivityContractPersistenceBoundaryV2.recordsSchemaVersion...
            C05RoundSessionBackupEnrollmentV1.recordsSchemaVersion).contains(recordsSchemaVersion),
              Set(activityContracts.map { "\($0.kind.rawValue):\($0.workspaceID):\($0.id)" }).count
                == activityContracts.count else {
            throw ActivityContractFailureV2.invalidValue
        }
        let envelopes = try activityContracts.filter { $0.kind == .sessionEnvelope }.map { try $0.envelopeValue() }
        let transitions = try activityContracts.filter { $0.kind == .stateTransition }.map { try $0.transitionValue() }
        let taskResults = try activityContracts.filter { $0.kind == .installationTaskResult }.map { try $0.installationTaskResultValue() }
        let asBuilt = try activityContracts.filter { $0.kind == .installationAsBuiltSnapshot }.map { try $0.installationAsBuiltSnapshotValue() }
        let punchBasis = try activityContracts.filter { $0.kind == .punchReviewBasisSnapshot }.map { try $0.punchReviewBasisSnapshotValue() }
        guard envelopes.allSatisfy({
                  C47ActivityContractPersistenceBoundaryV2.acceptsCanonicalRow(kind: $0.kind)
              }),
              Set(envelopes.map { "\($0.workspaceID.rawValue):\($0.activityID)" }).count == envelopes.count,
              let mutationHistory else {
            guard activityContracts.isEmpty else { throw ActivityContractFailureV2.missingReference }
            return (envelopes, transitions, taskResults, asBuilt, punchBasis)
        }
        let activityMutations = try mutationHistory.receipts.compactMap {
            record -> ActivityContractMutationV2? in
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
            guard case let .applyActivityContract(mutation) = envelope.command else { return nil }
            let receipt = try MutationReceiptV1.decodeCanonical(from: record.receiptData)
            _ = try ActivityContractMutationReceiptV2(
                mutation: mutation,
                mutationReceipt: receipt
            )
            return mutation
        }
        let orderedMutationIndices = try C47ActivityContractMutationOrderingV2
            .orderedIndices(for: activityMutations)
        var mutations: [ActivityContractMutationV2] = []
        var envelopeHeads: [String: ActivitySessionEnvelopeV2] = [:]
        var envelopeBySHA256: [String: ActivitySessionEnvelopeV2] = [:]
        var taskHistory: [String: [InstallationTaskResultV1]] = [:]
        var installationBasis: [String: InstallationBasisSnapshotV1] = [:]
        func activityKey(_ workspaceID: WorkspaceID, _ activityID: UUID) -> String {
            "\(workspaceID.rawValue.uuidString.lowercased()):\(activityID.uuidString.lowercased())"
        }
        for mutationIndex in orderedMutationIndices {
            let mutation = activityMutations[mutationIndex]
            guard C47ActivityContractPersistenceBoundaryV2.acceptsCanonicalRow(
                kind: mutation.successorEnvelope.kind
            ) else { throw ActivityContractFailureV2.incompatibleVersion }
            let key = activityKey(
                mutation.workspaceID,
                mutation.successorEnvelope.activityID
            )
            if let predecessor = mutation.predecessorEnvelope {
                guard envelopeHeads[key] == predecessor else {
                    throw ActivityContractFailureV2.staleRevision
                }
            } else {
                guard envelopeHeads[key] == nil else {
                    throw ActivityContractFailureV2.duplicateIdentity
                }
            }
            if let amendment = mutation.successorEnvelope.amendment {
                guard let amended = envelopeBySHA256[amendment.predecessorSHA256],
                      amended.workspaceID == mutation.workspaceID,
                      amended.activityID == amendment.predecessorActivityID,
                      amended.revision == amendment.predecessorRevision else {
                    throw ActivityContractFailureV2.missingReference
                }
            }
            let priorResults = taskHistory[key] ?? []
            let priorHeads = try InstallationTaskResultLineageV1.validateAndCurrentHeads(priorResults)
            let headContext = try InstallationTaskCurrentHeadContextV1(
                workspaceID: mutation.workspaceID,
                activityID: mutation.successorEnvelope.activityID,
                currentHeads: Array(priorHeads.values)
            )
            try headContext.validate(successors: mutation.installationTaskResults)
            let resultingResults = priorResults + mutation.installationTaskResults
            let resultingHeads = try InstallationTaskResultLineageV1
                .validateAndCurrentHeads(resultingResults)
            if let basis = mutation.installationBasisSnapshot {
                if let authority = installationBasis[key] {
                    try basis.validateSuccessor(of: authority)
                } else {
                    try basis.validate()
                    guard basis.revision == 1,
                          basis.predecessorBasisID == nil,
                          basis.predecessorBasisSHA256 == nil else {
                        throw ActivityContractFailureV2.staleRevision
                    }
                }
                installationBasis[key] = basis
            }
            if let snapshot = mutation.installationAsBuiltSnapshot {
                guard let basis = installationBasis[key] else {
                    throw ActivityContractFailureV2.missingReference
                }
                try snapshot.validateBasis(basis)
                guard Set(snapshot.taskResultSHA256s)
                        == Set(resultingHeads.values.map(\.resultSHA256)) else {
                    throw ActivityContractFailureV2.staleRevision
                }
            }
            envelopeHeads[key] = mutation.successorEnvelope
            envelopeBySHA256[mutation.successorEnvelope.envelopeSHA256]
                = mutation.successorEnvelope
            taskHistory[key] = resultingResults
            mutations.append(mutation)
        }
        let mutationKeys = mutations.map {
            "\($0.workspaceID.rawValue.uuidString.lowercased()):\($0.mutationID.rawValue.uuidString.lowercased())"
        }
        guard Set(mutationKeys).count == mutations.count else { throw ActivityContractFailureV2.invalidValue }
        try deletionLedger?.validate()
        // Whole-sign asset deletion records the subject asset itself. Explicit
        // site deletion is the union of those exact per-asset plans plus the
        // site entry, so a site tombstone alone never authorizes guessing an
        // omitted activity subject. Workspace Erase removes the mutation
        // journal as well and therefore cannot reach this retained-history
        // closure with orphan activity receipts.
        let deletedSubjectAssetIDs = Set((deletionLedger?.entries ?? []).compactMap { entry in
            entry.identity.kind == .asset ? entry.identity.id : nil
        })
        let immutableActivityKeys = Set(
            transitions.map { activityKey($0.workspaceID, $0.activityID) }
                + taskResults.map { activityKey($0.workspaceID, $0.activityID) }
                + asBuilt.map { activityKey($0.workspaceID, $0.activityID) }
                + punchBasis.map { activityKey($0.workspaceID, $0.activityID) }
                + envelopes.compactMap { envelope in
                    guard envelope.installationCloseout != nil
                        || envelope.punchReviewCloseout != nil
                        || envelope.completedSnapshotReference != nil else {
                        return nil
                    }
                    return activityKey(envelope.workspaceID, envelope.activityID)
                }
        )
        let retainedActivityKeys = Set(envelopeHeads.compactMap { key, envelope in
            switch envelope.state {
            case .finalized, .superseded, .cancelled, .unableToComplete:
                return key
            default:
                return deletedSubjectAssetIDs.contains(envelope.subjectID)
                    && !immutableActivityKeys.contains(key) ? nil : key
            }
        })
        var expectedRecords: [V36BackupActivityContractRecordV2] = try envelopeHeads.compactMap {
            key, envelope in
            retainedActivityKeys.contains(key) ? try .init(envelope) : nil
        }
        for mutation in mutations where retainedActivityKeys.contains(activityKey(
            mutation.workspaceID,
            mutation.successorEnvelope.activityID
        )) {
            if let value = mutation.transition { expectedRecords.append(try .init(value)) }
            expectedRecords += try mutation.installationTaskResults.map { try .init($0) }
            if let value = mutation.installationAsBuiltSnapshot {
                expectedRecords.append(try .init(value))
            }
            if let value = mutation.punchReviewBasisSnapshot {
                expectedRecords.append(try .init(value))
            }
        }
        func ordered(_ values: [V36BackupActivityContractRecordV2])
            -> [V36BackupActivityContractRecordV2] {
            values.sorted {
                ($0.kind.rawValue, $0.workspaceID.uuidString, $0.id.uuidString)
                    < ($1.kind.rawValue, $1.workspaceID.uuidString, $1.id.uuidString)
            }
        }
        guard ordered(activityContracts) == ordered(expectedRecords) else {
            throw ActivityContractFailureV2.missingReference
        }
        return (envelopes, transitions, taskResults, asBuilt, punchBasis)
    }

    func validateC49WorkResources() throws -> [WorkResourceEntryV1] {
        if recordsSchemaVersion < C49BackupEnrollmentV1.recordsSchemaVersion {
            guard workResources.isEmpty else {
                throw WorkResourceContractFailureV1.invalidValue
            }
            return []
        }
        guard (C49BackupEnrollmentV1.recordsSchemaVersion...
            C05RoundSessionBackupEnrollmentV1.recordsSchemaVersion).contains(recordsSchemaVersion) else {
            throw WorkResourceContractFailureV1.invalidValue
        }
        guard Set(workResources.map(\.entryID)).count == workResources.count,
              workResources == workResources.sorted(by: {
                  ($0.workspaceID.uuidString, $0.entryID.uuidString)
                    < ($1.workspaceID.uuidString, $1.entryID.uuidString)
              }) else {
            throw WorkResourceContractFailureV1.invalidValue
        }
        let entries = try workResources.map { try $0.value() }

        var actorByID: [UUID: ActorSnapshotV1] = [:]
        for record in partyAccountability where record.kind == .actorSnapshot {
            let actor = try PartyAccountabilitySnapshotCodecV1.decode(
                ActorSnapshotV1.self,
                from: record.canonicalData
            )
            guard record.id == actor.snapshotID,
                  record.workspaceID == actor.workspaceID.rawValue,
                  actorByID.updateValue(actor, forKey: actor.snapshotID) == nil else {
                throw WorkResourceContractFailureV1.invalidValue
            }
        }
        var workPacketBySubjectKey: [String: WorkPacketManifestV1] = [:]
        for record in workPackets where record.kind == .manifest {
            let manifest = try WorkPacketCanonicalCodecV1.decode(
                WorkPacketManifestV1.self,
                from: record.canonicalData
            )
            let key = "\(manifest.manifestID.uuidString.lowercased()):\(manifest.revision)"
            guard record.id == manifest.manifestID,
                  record.workspaceID == manifest.workspaceID.rawValue,
                  record.revision == manifest.revision,
                  workPacketBySubjectKey.updateValue(manifest, forKey: key) == nil else {
                throw WorkResourceContractFailureV1.invalidValue
            }
        }
        var correctiveEventBySubjectKey: [String: CorrectiveActionEventV1] = [:]
        for record in inspectionReview where record.kind == .correctiveActionEvent {
            let event = try InspectionReviewCanonicalCodecV1.decode(
                CorrectiveActionEventV1.self,
                from: record.canonicalData
            )
            let key = "\(event.eventID.uuidString.lowercased()):\(event.revision)"
            guard record.id == event.eventID,
                  record.workspaceID == event.workspaceID.rawValue,
                  record.revision == event.revision,
                  correctiveEventBySubjectKey.updateValue(event, forKey: key) == nil else {
                throw WorkResourceContractFailureV1.invalidValue
            }
        }

        let entryByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.entryID, $0) })
        guard Set(entries.map(\.mutationID)).count == entries.count else {
            throw WorkResourceContractFailureV1.invalidTransition
        }
        var entrySuccessors = Set<UUID>()
        for entry in entries {
            try entry.validate()
            guard entry.subject.workspaceID == entry.workspaceID,
                  entry.actor.responsibility == .recordedBy
                    || entry.actor.responsibility == .performedBy,
                  actorByID[entry.actor.snapshotID] == entry.actor else {
                throw WorkResourceContractFailureV1.crossWorkspace
            }
            let subjectKey = "\(entry.subject.subjectID):\(entry.subject.subjectRevision)"
            switch entry.subject.kind {
            case .workPacket:
                guard let subject = workPacketBySubjectKey[subjectKey],
                      subject.workspaceID == entry.workspaceID,
                      subject.manifestSHA256 == entry.subject.subjectSHA256 else {
                    throw WorkResourceContractFailureV1.invalidTransition
                }
            case .correctiveWork:
                guard let subject = correctiveEventBySubjectKey[subjectKey],
                      subject.workspaceID == entry.workspaceID,
                      subject.eventSHA256 == entry.subject.subjectSHA256 else {
                    throw WorkResourceContractFailureV1.invalidTransition
                }
            }
            if let predecessorID = entry.supersedesEntryID {
                guard entrySuccessors.insert(predecessorID).inserted,
                      let predecessor = entryByID[predecessorID] else {
                    throw WorkResourceContractFailureV1.invalidTransition
                }
                try entry.validateSuccessor(of: predecessor)
                guard entry.entryID != predecessor.entryID,
                      entry.mutationID != predecessor.mutationID,
                      entry.recordedAt >= predecessor.recordedAt,
                      entry.disposition == .superseded
                        || entry.disposition == .voidedWithReason
                        || entry.disposition == .reversed else {
                    throw WorkResourceContractFailureV1.invalidTransition
                }
            } else if entry.revision != 1 || entry.expectedRevision != 0
                        || entry.disposition != .active {
                throw WorkResourceContractFailureV1.invalidTransition
            }
        }
        func partsStockWorkEntries(_ mutation: PartsStockMutationV1) throws -> [WorkResourceEntryV1] {
            try mutation.validate()
            switch mutation {
            case let .use(value):
                return [value.workResourceSuccessor]
            case let .reverseUse(value):
                return [value.sourceUse.workResourceSuccessor, value.workResourceSuccessor]
            case let .returnAgainstUse(value):
                return [
                    value.sourceUse.workResourceSuccessor,
                    value.workResourcePredecessor,
                    value.workResourceSuccessor,
                ]
            default:
                return []
            }
        }
        func canonicalByEntryID(_ values: [WorkResourceEntryV1]) throws -> [UUID: Data] {
            var result: [UUID: Data] = [:]
            for value in values {
                let data = try WorkspaceMutationCanonicalV1.data(value)
                if let existing = result[value.entryID], existing != data {
                    throw WorkResourceContractFailureV1.invalidTransition
                }
                result[value.entryID] = data
            }
            return result
        }
        let receiptEntries = try mutationHistory?.receipts.flatMap { record -> [WorkResourceEntryV1] in
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
            let receipt = try MutationReceiptV1.decodeCanonical(from: record.receiptData)
            switch envelope.command {
            case let .applyWorkResource(mutation):
                _ = try WorkResourceMutationReceiptV1(
                    mutation: mutation,
                    mutationReceipt: receipt
                )
                return [mutation.postImage]
            case let .applyPartsStock(mutation):
                guard receipt.mutationID == mutation.mutationID,
                      receipt.identity.workspaceID == mutation.workspaceID else {
                    throw WorkResourceContractFailureV1.invalidTransition
                }
                return try partsStockWorkEntries(mutation)
            default:
                return []
            }
        }
        if let receiptEntries {
            let canonicalReceiptEntries = try canonicalByEntryID(receiptEntries)
            let canonicalBackupEntries = try canonicalByEntryID(entries)
            guard canonicalReceiptEntries == canonicalBackupEntries else {
                throw WorkResourceContractFailureV1.invalidTransition
            }
        }
        if recordsSchemaVersion >= C55PartsStockBackupEnrollmentV1.recordsSchemaVersion {
            guard let snapshot = partsStockSnapshot,
                  let receiptEntries else {
                throw WorkResourceContractFailureV1.invalidTransition
            }
            try snapshot.validate()
            let snapshotEntries = snapshot.uses.map(\.workResourceSuccessor)
                + snapshot.reversals.flatMap { [$0.sourceUse.workResourceSuccessor, $0.workResourceSuccessor] }
                + snapshot.returns.flatMap {
                    [$0.sourceUse.workResourceSuccessor, $0.workResourcePredecessor, $0.workResourceSuccessor]
                }
            let partsStockReceiptEntries = try mutationHistory?.receipts.flatMap { record -> [WorkResourceEntryV1] in
                let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
                guard case let .applyPartsStock(mutation) = envelope.command else { return [] }
                let receipt = try MutationReceiptV1.decodeCanonical(from: record.receiptData)
                guard receipt.mutationID == mutation.mutationID,
                      receipt.identity.workspaceID == mutation.workspaceID else {
                    throw WorkResourceContractFailureV1.invalidTransition
                }
                return try partsStockWorkEntries(mutation)
            } ?? []
            let canonicalSnapshotEntries = try canonicalByEntryID(snapshotEntries)
            let canonicalReceiptEntries = try canonicalByEntryID(partsStockReceiptEntries)
            guard canonicalSnapshotEntries == canonicalReceiptEntries else {
                throw WorkResourceContractFailureV1.invalidTransition
            }
        }
        return entries
    }

    func validateC46OperationalContacts() throws -> (
        contacts: [ServiceContactPointV1], intents: [SystemHandoffIntentV1]
    ) {
        if recordsSchemaVersion < OperationalContactPersistenceEnrollmentV1.recordsSchemaVersion {
            guard operationalContacts.isEmpty else { throw OperationalContactFailureV1.incompatibleVersion }
            return ([], [])
        }
        guard (OperationalContactPersistenceEnrollmentV1.recordsSchemaVersion...
            C05RoundSessionBackupEnrollmentV1.recordsSchemaVersion).contains(recordsSchemaVersion),
              Set(operationalContacts.map { "\($0.kind.rawValue):\($0.workspaceID):\($0.id)" }).count == operationalContacts.count else {
            throw OperationalContactFailureV1.invalidValue
        }
        let contacts = try operationalContacts.filter { $0.kind == .serviceContactPoint }.map { try $0.contactValue() }
        let intents = try operationalContacts.filter { $0.kind == .systemHandoffIntent }.map { try $0.intentValue() }
        let receiptMutations = try mutationHistory?.receipts.compactMap { record -> OperationalContactMutationV1? in
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
            guard case let .applyOperationalContact(mutation) = envelope.command else { return nil }
            let receipt = try MutationReceiptV1.decodeCanonical(from: record.receiptData)
            _ = try OperationalContactMutationReceiptV1(mutation: mutation, mutationReceipt: receipt)
            return mutation
        } ?? []
        let activeContacts = contacts.filter { $0.workspaceID.rawValue == $0.party.workspaceID.rawValue }
        let activeIntents = intents.filter { $0.disposition == .activeSourceWorkspace }
        let parties = try Dictionary(uniqueKeysWithValues: partyAccountability.compactMap {
            record -> (UUID, ServicePartyReferenceV1)? in
            guard record.kind == .serviceParty else { return nil }
            let value = try PartyAccountabilitySnapshotCodecV1.decode(
                ServicePartyReferenceV1.self, from: record.canonicalData
            )
            return (value.partyID, value)
        })
        let effectiveByScope = Dictionary(grouping: contacts.filter {
            $0.lifecycle == .effective
        }) {
            "\($0.workspaceID.rawValue.uuidString):\($0.party.partyID.uuidString):\($0.kind.rawValue)"
        }
        guard contacts.allSatisfy({ parties[$0.party.partyID] == $0.party }),
              effectiveByScope.values.allSatisfy({ $0.filter(\.preferred).count <= 1 }),
              activeContacts.allSatisfy({ contact in
                receiptMutations.contains(where: { mutation in
                    mutation.mutationID == contact.mutationID
                        && mutation.successors.contains(contact)
                })
              }),
              activeIntents.allSatisfy({ intent in
                receiptMutations.contains(where: { mutation in
                    mutation.mutationID == intent.mutationID
                        && mutation.handoffIntents.contains(intent)
                })
              }) else {
            throw OperationalContactFailureV1.digestMismatch
        }
        let contactsByID = Dictionary(uniqueKeysWithValues: contacts.map {
            ($0.contactPointID, $0)
        })
        for intent in activeIntents where intent.target.kind == .serviceContactPoint {
            guard let target = contactsByID[intent.target.targetID],
                  target.workspaceID == intent.workspaceID,
                  target.lifecycle == .effective,
                  target.revision == intent.target.expectedRevision,
                  target.contactPointSHA256 == intent.target.expectedSHA256 else {
                throw OperationalContactFailureV1.digestMismatch
            }
        }
        return (contacts, intents)
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
        guard (AssetLabelPersistenceEnrollmentV1.recordsSchemaVersion...
            C05RoundSessionBackupEnrollmentV1.recordsSchemaVersion).contains(recordsSchemaVersion),
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
            C05RoundSessionBackupEnrollmentV1.recordsSchemaVersion).contains(recordsSchemaVersion),
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
        guard (31...C05RoundSessionBackupEnrollmentV1.recordsSchemaVersion).contains(recordsSchemaVersion),
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
                || recordsSchemaVersion == 32 || recordsSchemaVersion == 33 || recordsSchemaVersion == 34
                || recordsSchemaVersion == C47ActivityContractPersistenceBoundaryV2.recordsSchemaVersion
                || recordsSchemaVersion == C49BackupEnrollmentV1.recordsSchemaVersion
                || recordsSchemaVersion == C55PartsStockBackupEnrollmentV1.recordsSchemaVersion || recordsSchemaVersion == C57MyDayBackupEnrollmentV1.recordsSchemaVersion || recordsSchemaVersion == C04ShopReportProfileBackupEnrollmentV1.recordsSchemaVersion || recordsSchemaVersion == C05RoundSessionBackupEnrollmentV1.recordsSchemaVersion else {
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
                || recordsSchemaVersion == 33 || recordsSchemaVersion == 34
                || recordsSchemaVersion == C47ActivityContractPersistenceBoundaryV2.recordsSchemaVersion
                || recordsSchemaVersion == C49WorkResourcePersistenceBoundaryV1.recordsSchemaVersion
                || recordsSchemaVersion == C55PartsStockBackupEnrollmentV1.recordsSchemaVersion || recordsSchemaVersion == C57MyDayBackupEnrollmentV1.recordsSchemaVersion || recordsSchemaVersion == C04ShopReportProfileBackupEnrollmentV1.recordsSchemaVersion || recordsSchemaVersion == C05RoundSessionBackupEnrollmentV1.recordsSchemaVersion else {
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
             assistanceAcceptanceReceipts: assistanceAcceptanceReceipts,temporalEvidence:temporalEvidence,acceptedLabelGenerationSnapshots:acceptedLabelGenerationSnapshots,operationalContacts:operationalContacts,activityContracts:activityContracts,workResources:workResources,serviceRequests:serviceRequests,serviceRequestDispositionEvents:serviceRequestDispositionEvents,serviceRequestWorkLinkEvents:serviceRequestWorkLinkEvents,partsStockSnapshot:partsStockSnapshot,myDayPlans:myDayPlans,myDayCarryoverReceipts:myDayCarryoverReceipts,nonactivePlanReferences:nonactivePlanReferences,evidenceAssociationEvents:evidenceAssociationEvents,evidenceSequenceRevisions:evidenceSequenceRevisions,shopReportProfiles:shopReportProfiles,roundSessions:roundSessions))
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
             assistanceAcceptanceReceipts: assistanceAcceptanceReceipts,temporalEvidence:temporalEvidence,acceptedLabelGenerationSnapshots:acceptedLabelGenerationSnapshots,operationalContacts:operationalContacts,activityContracts:activityContracts,workResources:workResources,serviceRequests:serviceRequests,serviceRequestDispositionEvents:serviceRequestDispositionEvents,serviceRequestWorkLinkEvents:serviceRequestWorkLinkEvents,partsStockSnapshot:partsStockSnapshot,myDayPlans:myDayPlans,myDayCarryoverReceipts:myDayCarryoverReceipts,nonactivePlanReferences:nonactivePlanReferences,evidenceAssociationEvents:evidenceAssociationEvents,evidenceSequenceRevisions:evidenceSequenceRevisions,shopReportProfiles:shopReportProfiles,roundSessions:roundSessions))
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
             assistanceAcceptanceReceipts: assistanceAcceptanceReceipts,temporalEvidence:temporalEvidence,acceptedLabelGenerationSnapshots:acceptedLabelGenerationSnapshots,operationalContacts:operationalContacts,activityContracts:activityContracts,workResources:workResources,serviceRequests:serviceRequests,serviceRequestDispositionEvents:serviceRequestDispositionEvents,serviceRequestWorkLinkEvents:serviceRequestWorkLinkEvents,partsStockSnapshot:partsStockSnapshot,myDayPlans:myDayPlans,myDayCarryoverReceipts:myDayCarryoverReceipts,nonactivePlanReferences:nonactivePlanReferences,evidenceAssociationEvents:evidenceAssociationEvents,evidenceSequenceRevisions:evidenceSequenceRevisions,shopReportProfiles:shopReportProfiles,roundSessions:roundSessions))
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
             assistanceAcceptanceReceipts: assistanceAcceptanceReceipts,temporalEvidence:temporalEvidence,acceptedLabelGenerationSnapshots:acceptedLabelGenerationSnapshots,operationalContacts:operationalContacts,activityContracts:activityContracts,workResources:workResources,serviceRequests:serviceRequests,serviceRequestDispositionEvents:serviceRequestDispositionEvents,serviceRequestWorkLinkEvents:serviceRequestWorkLinkEvents,partsStockSnapshot:partsStockSnapshot,myDayPlans:myDayPlans,myDayCarryoverReceipts:myDayCarryoverReceipts,nonactivePlanReferences:nonactivePlanReferences,evidenceAssociationEvents:evidenceAssociationEvents,evidenceSequenceRevisions:evidenceSequenceRevisions,shopReportProfiles:shopReportProfiles,roundSessions:roundSessions))
    }

     func replacingAccessibleDocumentAssessments(_ values:[V23BackupAccessibleDocumentAssessmentRecordV1])->Self{Self(guidedSurveys:guidedSurveys,assetLocators:assetLocators,schedules:schedules,plans:plans,placementPoses:placementPoses,accessibleDocumentAssessments:values,surveyDefinitions:surveyDefinitions,fieldReferences:fieldReferences,recoverabilityReceipts:recoverabilityReceipts,clientCapabilities:clientCapabilities,privacyTransforms:privacyTransforms,measurementIntegrity:measurementIntegrity,packageEvolution:packageEvolution,fieldDrafts:fieldDrafts,workPackets:workPackets,inspectionReview:inspectionReview,evidenceAssurance:evidenceAssurance,functionalRelationships:functionalRelationships,authorityCriterion:authorityCriterion,assetSemantics:assetSemantics,assetCompositionEdges:assetCompositionEdges,assetCompositionEvents:assetCompositionEvents,assetPlacementEvents:assetPlacementEvents,assets:assets,deletionLedger:deletionLedger,evidenceFiles:evidenceFiles,issues:issues,locationHierarchyEvents:locationHierarchyEvents,locationMigrationReceipts:locationMigrationReceipts,locationNodes:locationNodes,mutationHistory:mutationHistory,packets:packets,partyAccountability:partyAccountability,recordsSchemaVersion:recordsSchemaVersion,reports:reports,requirementAssurance:requirementAssurance,savedSmartViews:savedSmartViews,sites:sites,workflowRecords:workflowRecords,evidenceContexts:evidenceContexts,pairedObservationLinks:pairedObservationLinks,lighting:lighting,assistanceAcceptanceReceipts:assistanceAcceptanceReceipts,temporalEvidence:temporalEvidence,acceptedLabelGenerationSnapshots:acceptedLabelGenerationSnapshots,operationalContacts:operationalContacts,activityContracts:activityContracts,workResources:workResources,serviceRequests:serviceRequests,serviceRequestDispositionEvents:serviceRequestDispositionEvents,serviceRequestWorkLinkEvents:serviceRequestWorkLinkEvents,partsStockSnapshot:partsStockSnapshot,myDayPlans:myDayPlans,myDayCarryoverReceipts:myDayCarryoverReceipts,nonactivePlanReferences:nonactivePlanReferences,evidenceAssociationEvents:evidenceAssociationEvents,evidenceSequenceRevisions:evidenceSequenceRevisions,shopReportProfiles:shopReportProfiles,roundSessions:roundSessions))}
func replacingSurveyDefinitions(_ values:[V24BackupSurveyDefinitionRecordV1])->Self{Self(guidedSurveys:guidedSurveys,assetLocators:assetLocators,schedules:schedules,plans:plans,placementPoses:placementPoses,accessibleDocumentAssessments:accessibleDocumentAssessments,surveyDefinitions:values,fieldReferences:fieldReferences,recoverabilityReceipts:recoverabilityReceipts,clientCapabilities:clientCapabilities,privacyTransforms:privacyTransforms,measurementIntegrity:measurementIntegrity,packageEvolution:packageEvolution,fieldDrafts:fieldDrafts,workPackets:workPackets,inspectionReview:inspectionReview,evidenceAssurance:evidenceAssurance,functionalRelationships:functionalRelationships,authorityCriterion:authorityCriterion,assetSemantics:assetSemantics,assetCompositionEdges:assetCompositionEdges,assetCompositionEvents:assetCompositionEvents,assetPlacementEvents:assetPlacementEvents,assets:assets,deletionLedger:deletionLedger,evidenceFiles:evidenceFiles,issues:issues,locationHierarchyEvents:locationHierarchyEvents,locationMigrationReceipts:locationMigrationReceipts,locationNodes:locationNodes,mutationHistory:mutationHistory,packets:packets,partyAccountability:partyAccountability,recordsSchemaVersion:recordsSchemaVersion,reports:reports,requirementAssurance:requirementAssurance,savedSmartViews:savedSmartViews,sites:sites,workflowRecords:workflowRecords,evidenceContexts:evidenceContexts,pairedObservationLinks:pairedObservationLinks,lighting:lighting,assistanceAcceptanceReceipts:assistanceAcceptanceReceipts,temporalEvidence:temporalEvidence,acceptedLabelGenerationSnapshots:acceptedLabelGenerationSnapshots,operationalContacts:operationalContacts,activityContracts:activityContracts,workResources:workResources,serviceRequests:serviceRequests,serviceRequestDispositionEvents:serviceRequestDispositionEvents,serviceRequestWorkLinkEvents:serviceRequestWorkLinkEvents,partsStockSnapshot:partsStockSnapshot,myDayPlans:myDayPlans,myDayCarryoverReceipts:myDayCarryoverReceipts,nonactivePlanReferences:nonactivePlanReferences,evidenceAssociationEvents:evidenceAssociationEvents,evidenceSequenceRevisions:evidenceSequenceRevisions,shopReportProfiles:shopReportProfiles,roundSessions:roundSessions))}
     func replacingGuidedSurveys(_ values:[V25BackupGuidedSurveyRecordV1])->Self{Self(guidedSurveys:values,assetLocators:assetLocators,schedules:schedules,plans:plans,placementPoses:placementPoses,accessibleDocumentAssessments:accessibleDocumentAssessments,surveyDefinitions:surveyDefinitions,fieldReferences:fieldReferences,recoverabilityReceipts:recoverabilityReceipts,clientCapabilities:clientCapabilities,privacyTransforms:privacyTransforms,measurementIntegrity:measurementIntegrity,packageEvolution:packageEvolution,fieldDrafts:fieldDrafts,workPackets:workPackets,inspectionReview:inspectionReview,evidenceAssurance:evidenceAssurance,functionalRelationships:functionalRelationships,authorityCriterion:authorityCriterion,assetSemantics:assetSemantics,assetCompositionEdges:assetCompositionEdges,assetCompositionEvents:assetCompositionEvents,assetPlacementEvents:assetPlacementEvents,assets:assets,deletionLedger:deletionLedger,evidenceFiles:evidenceFiles,issues:issues,locationHierarchyEvents:locationHierarchyEvents,locationMigrationReceipts:locationMigrationReceipts,locationNodes:locationNodes,mutationHistory:mutationHistory,packets:packets,partyAccountability:partyAccountability,recordsSchemaVersion:recordsSchemaVersion,reports:reports,requirementAssurance:requirementAssurance,savedSmartViews:savedSmartViews,sites:sites,workflowRecords:workflowRecords,evidenceContexts:evidenceContexts,pairedObservationLinks:pairedObservationLinks,lighting:lighting,assistanceAcceptanceReceipts:assistanceAcceptanceReceipts,temporalEvidence:temporalEvidence,acceptedLabelGenerationSnapshots:acceptedLabelGenerationSnapshots,operationalContacts:operationalContacts,activityContracts:activityContracts,workResources:workResources,serviceRequests:serviceRequests,serviceRequestDispositionEvents:serviceRequestDispositionEvents,serviceRequestWorkLinkEvents:serviceRequestWorkLinkEvents,partsStockSnapshot:partsStockSnapshot,myDayPlans:myDayPlans,myDayCarryoverReceipts:myDayCarryoverReceipts,nonactivePlanReferences:nonactivePlanReferences,evidenceAssociationEvents:evidenceAssociationEvents,evidenceSequenceRevisions:evidenceSequenceRevisions,shopReportProfiles:shopReportProfiles,roundSessions:roundSessions))}
     func replacingTemporalEvidence(_ values:[V33BackupTemporalEvidenceRecordV1])->Self{Self(guidedSurveys:guidedSurveys,assetLocators:assetLocators,schedules:schedules,plans:plans,placementPoses:placementPoses,accessibleDocumentAssessments:accessibleDocumentAssessments,surveyDefinitions:surveyDefinitions,fieldReferences:fieldReferences,recoverabilityReceipts:recoverabilityReceipts,clientCapabilities:clientCapabilities,privacyTransforms:privacyTransforms,measurementIntegrity:measurementIntegrity,packageEvolution:packageEvolution,fieldDrafts:fieldDrafts,workPackets:workPackets,inspectionReview:inspectionReview,evidenceAssurance:evidenceAssurance,functionalRelationships:functionalRelationships,authorityCriterion:authorityCriterion,assetSemantics:assetSemantics,assetCompositionEdges:assetCompositionEdges,assetCompositionEvents:assetCompositionEvents,assetPlacementEvents:assetPlacementEvents,assets:assets,deletionLedger:deletionLedger,evidenceFiles:evidenceFiles,issues:issues,locationHierarchyEvents:locationHierarchyEvents,locationMigrationReceipts:locationMigrationReceipts,locationNodes:locationNodes,mutationHistory:mutationHistory,packets:packets,partyAccountability:partyAccountability,recordsSchemaVersion:recordsSchemaVersion,reports:reports,requirementAssurance:requirementAssurance,savedSmartViews:savedSmartViews,sites:sites,workflowRecords:workflowRecords,evidenceContexts:evidenceContexts,pairedObservationLinks:pairedObservationLinks,lighting:lighting,assistanceAcceptanceReceipts:assistanceAcceptanceReceipts,temporalEvidence:values,acceptedLabelGenerationSnapshots:acceptedLabelGenerationSnapshots,operationalContacts:operationalContacts,activityContracts:activityContracts,workResources:workResources,serviceRequests:serviceRequests,serviceRequestDispositionEvents:serviceRequestDispositionEvents,serviceRequestWorkLinkEvents:serviceRequestWorkLinkEvents,partsStockSnapshot:partsStockSnapshot,myDayPlans:myDayPlans,myDayCarryoverReceipts:myDayCarryoverReceipts,nonactivePlanReferences:nonactivePlanReferences,evidenceAssociationEvents:evidenceAssociationEvents,evidenceSequenceRevisions:evidenceSequenceRevisions,shopReportProfiles:shopReportProfiles,roundSessions:roundSessions))}
     func replacingAcceptedLabelGenerationSnapshots(_ values:[V34BackupAcceptedLabelSnapshotRecordV1])->Self{Self(guidedSurveys:guidedSurveys,assetLocators:assetLocators,schedules:schedules,plans:plans,placementPoses:placementPoses,accessibleDocumentAssessments:accessibleDocumentAssessments,surveyDefinitions:surveyDefinitions,fieldReferences:fieldReferences,recoverabilityReceipts:recoverabilityReceipts,clientCapabilities:clientCapabilities,privacyTransforms:privacyTransforms,measurementIntegrity:measurementIntegrity,packageEvolution:packageEvolution,fieldDrafts:fieldDrafts,workPackets:workPackets,inspectionReview:inspectionReview,evidenceAssurance:evidenceAssurance,functionalRelationships:functionalRelationships,authorityCriterion:authorityCriterion,assetSemantics:assetSemantics,assetCompositionEdges:assetCompositionEdges,assetCompositionEvents:assetCompositionEvents,assetPlacementEvents:assetPlacementEvents,assets:assets,deletionLedger:deletionLedger,evidenceFiles:evidenceFiles,issues:issues,locationHierarchyEvents:locationHierarchyEvents,locationMigrationReceipts:locationMigrationReceipts,locationNodes:locationNodes,mutationHistory:mutationHistory,packets:packets,partyAccountability:partyAccountability,recordsSchemaVersion:recordsSchemaVersion,reports:reports,requirementAssurance:requirementAssurance,savedSmartViews:savedSmartViews,sites:sites,workflowRecords:workflowRecords,evidenceContexts:evidenceContexts,pairedObservationLinks:pairedObservationLinks,lighting:lighting,assistanceAcceptanceReceipts:assistanceAcceptanceReceipts,temporalEvidence:temporalEvidence,acceptedLabelGenerationSnapshots:values,operationalContacts:operationalContacts,activityContracts:activityContracts,workResources:workResources,serviceRequests:serviceRequests,serviceRequestDispositionEvents:serviceRequestDispositionEvents,serviceRequestWorkLinkEvents:serviceRequestWorkLinkEvents,partsStockSnapshot:partsStockSnapshot,myDayPlans:myDayPlans,myDayCarryoverReceipts:myDayCarryoverReceipts,nonactivePlanReferences:nonactivePlanReferences,evidenceAssociationEvents:evidenceAssociationEvents,evidenceSequenceRevisions:evidenceSequenceRevisions,shopReportProfiles:shopReportProfiles,roundSessions:roundSessions))}
     func replacingOperationalContacts(_ values:[V35BackupOperationalContactRecordV1])->Self{Self(guidedSurveys:guidedSurveys,assetLocators:assetLocators,schedules:schedules,plans:plans,placementPoses:placementPoses,accessibleDocumentAssessments:accessibleDocumentAssessments,surveyDefinitions:surveyDefinitions,fieldReferences:fieldReferences,recoverabilityReceipts:recoverabilityReceipts,clientCapabilities:clientCapabilities,privacyTransforms:privacyTransforms,measurementIntegrity:measurementIntegrity,packageEvolution:packageEvolution,fieldDrafts:fieldDrafts,workPackets:workPackets,inspectionReview:inspectionReview,evidenceAssurance:evidenceAssurance,functionalRelationships:functionalRelationships,authorityCriterion:authorityCriterion,assetSemantics:assetSemantics,assetCompositionEdges:assetCompositionEdges,assetCompositionEvents:assetCompositionEvents,assetPlacementEvents:assetPlacementEvents,assets:assets,deletionLedger:deletionLedger,evidenceFiles:evidenceFiles,issues:issues,locationHierarchyEvents:locationHierarchyEvents,locationMigrationReceipts:locationMigrationReceipts,locationNodes:locationNodes,mutationHistory:mutationHistory,packets:packets,partyAccountability:partyAccountability,recordsSchemaVersion:recordsSchemaVersion,reports:reports,requirementAssurance:requirementAssurance,savedSmartViews:savedSmartViews,sites:sites,workflowRecords:workflowRecords,evidenceContexts:evidenceContexts,pairedObservationLinks:pairedObservationLinks,lighting:lighting,assistanceAcceptanceReceipts:assistanceAcceptanceReceipts,temporalEvidence:temporalEvidence,acceptedLabelGenerationSnapshots:acceptedLabelGenerationSnapshots,operationalContacts:values,activityContracts:activityContracts,workResources:workResources,serviceRequests:serviceRequests,serviceRequestDispositionEvents:serviceRequestDispositionEvents,serviceRequestWorkLinkEvents:serviceRequestWorkLinkEvents,partsStockSnapshot:partsStockSnapshot,myDayPlans:myDayPlans,myDayCarryoverReceipts:myDayCarryoverReceipts,nonactivePlanReferences:nonactivePlanReferences,evidenceAssociationEvents:evidenceAssociationEvents,evidenceSequenceRevisions:evidenceSequenceRevisions,shopReportProfiles:shopReportProfiles,roundSessions:roundSessions))}
     func replacingMyDay(_ snapshot:MyDayBackupSnapshotV1)->Self{Self(guidedSurveys:guidedSurveys,assetLocators:assetLocators,schedules:schedules,plans:plans,placementPoses:placementPoses,accessibleDocumentAssessments:accessibleDocumentAssessments,surveyDefinitions:surveyDefinitions,fieldReferences:fieldReferences,recoverabilityReceipts:recoverabilityReceipts,clientCapabilities:clientCapabilities,privacyTransforms:privacyTransforms,measurementIntegrity:measurementIntegrity,packageEvolution:packageEvolution,fieldDrafts:fieldDrafts,workPackets:workPackets,inspectionReview:inspectionReview,evidenceAssurance:evidenceAssurance,functionalRelationships:functionalRelationships,authorityCriterion:authorityCriterion,assetSemantics:assetSemantics,assetCompositionEdges:assetCompositionEdges,assetCompositionEvents:assetCompositionEvents,assetPlacementEvents:assetPlacementEvents,assets:assets,deletionLedger:deletionLedger,evidenceFiles:evidenceFiles,issues:issues,locationHierarchyEvents:locationHierarchyEvents,locationMigrationReceipts:locationMigrationReceipts,locationNodes:locationNodes,mutationHistory:mutationHistory,packets:packets,partyAccountability:partyAccountability,recordsSchemaVersion:recordsSchemaVersion,reports:reports,requirementAssurance:requirementAssurance,savedSmartViews:savedSmartViews,sites:sites,workflowRecords:workflowRecords,evidenceContexts:evidenceContexts,pairedObservationLinks:pairedObservationLinks,lighting:lighting,assistanceAcceptanceReceipts:assistanceAcceptanceReceipts,temporalEvidence:temporalEvidence,acceptedLabelGenerationSnapshots:acceptedLabelGenerationSnapshots,operationalContacts:operationalContacts,activityContracts:activityContracts,workResources:workResources,serviceRequests:serviceRequests,serviceRequestDispositionEvents:serviceRequestDispositionEvents,serviceRequestWorkLinkEvents:serviceRequestWorkLinkEvents,partsStockSnapshot:partsStockSnapshot,myDayPlans:snapshot.plans,myDayCarryoverReceipts:snapshot.carryoverReceipts,nonactivePlanReferences:snapshot.nonactivePlanReferences,evidenceAssociationEvents:evidenceAssociationEvents,evidenceSequenceRevisions:evidenceSequenceRevisions,shopReportProfiles:shopReportProfiles,roundSessions:roundSessions))}
     func replacingEvidenceMetadata(_ associations:[EvidenceAssociationV1],_ sequences:[EvidenceSequenceV1])->Self{Self(guidedSurveys:guidedSurveys,assetLocators:assetLocators,schedules:schedules,plans:plans,placementPoses:placementPoses,accessibleDocumentAssessments:accessibleDocumentAssessments,surveyDefinitions:surveyDefinitions,fieldReferences:fieldReferences,recoverabilityReceipts:recoverabilityReceipts,clientCapabilities:clientCapabilities,privacyTransforms:privacyTransforms,measurementIntegrity:measurementIntegrity,packageEvolution:packageEvolution,fieldDrafts:fieldDrafts,workPackets:workPackets,inspectionReview:inspectionReview,evidenceAssurance:evidenceAssurance,functionalRelationships:functionalRelationships,authorityCriterion:authorityCriterion,assetSemantics:assetSemantics,assetCompositionEdges:assetCompositionEdges,assetCompositionEvents:assetCompositionEvents,assetPlacementEvents:assetPlacementEvents,assets:assets,deletionLedger:deletionLedger,evidenceFiles:evidenceFiles,issues:issues,locationHierarchyEvents:locationHierarchyEvents,locationMigrationReceipts:locationMigrationReceipts,locationNodes:locationNodes,mutationHistory:mutationHistory,packets:packets,partyAccountability:partyAccountability,recordsSchemaVersion:recordsSchemaVersion,reports:reports,requirementAssurance:requirementAssurance,savedSmartViews:savedSmartViews,sites:sites,workflowRecords:workflowRecords,evidenceContexts:evidenceContexts,pairedObservationLinks:pairedObservationLinks,lighting:lighting,assistanceAcceptanceReceipts:assistanceAcceptanceReceipts,temporalEvidence:temporalEvidence,acceptedLabelGenerationSnapshots:acceptedLabelGenerationSnapshots,operationalContacts:operationalContacts,activityContracts:activityContracts,workResources:workResources,serviceRequests:serviceRequests,serviceRequestDispositionEvents:serviceRequestDispositionEvents,serviceRequestWorkLinkEvents:serviceRequestWorkLinkEvents,partsStockSnapshot:partsStockSnapshot,myDayPlans:myDayPlans,myDayCarryoverReceipts:myDayCarryoverReceipts,nonactivePlanReferences:nonactivePlanReferences,evidenceAssociationEvents:associations,evidenceSequenceRevisions:sequences,shopReportProfiles:shopReportProfiles,roundSessions:roundSessions)}
     func replacingActivityContracts(_ values:[V36BackupActivityContractRecordV2])->Self{Self(guidedSurveys:guidedSurveys,assetLocators:assetLocators,schedules:schedules,plans:plans,placementPoses:placementPoses,accessibleDocumentAssessments:accessibleDocumentAssessments,surveyDefinitions:surveyDefinitions,fieldReferences:fieldReferences,recoverabilityReceipts:recoverabilityReceipts,clientCapabilities:clientCapabilities,privacyTransforms:privacyTransforms,measurementIntegrity:measurementIntegrity,packageEvolution:packageEvolution,fieldDrafts:fieldDrafts,workPackets:workPackets,inspectionReview:inspectionReview,evidenceAssurance:evidenceAssurance,functionalRelationships:functionalRelationships,authorityCriterion:authorityCriterion,assetSemantics:assetSemantics,assetCompositionEdges:assetCompositionEdges,assetCompositionEvents:assetCompositionEvents,assetPlacementEvents:assetPlacementEvents,assets:assets,deletionLedger:deletionLedger,evidenceFiles:evidenceFiles,issues:issues,locationHierarchyEvents:locationHierarchyEvents,locationMigrationReceipts:locationMigrationReceipts,locationNodes:locationNodes,mutationHistory:mutationHistory,packets:packets,partyAccountability:partyAccountability,recordsSchemaVersion:recordsSchemaVersion,reports:reports,requirementAssurance:requirementAssurance,savedSmartViews:savedSmartViews,sites:sites,workflowRecords:workflowRecords,evidenceContexts:evidenceContexts,pairedObservationLinks:pairedObservationLinks,lighting:lighting,assistanceAcceptanceReceipts:assistanceAcceptanceReceipts,temporalEvidence:temporalEvidence,acceptedLabelGenerationSnapshots:acceptedLabelGenerationSnapshots,operationalContacts:operationalContacts,activityContracts:values,workResources:workResources,serviceRequests:serviceRequests,serviceRequestDispositionEvents:serviceRequestDispositionEvents,serviceRequestWorkLinkEvents:serviceRequestWorkLinkEvents,partsStockSnapshot:partsStockSnapshot,myDayPlans:myDayPlans,myDayCarryoverReceipts:myDayCarryoverReceipts,nonactivePlanReferences:nonactivePlanReferences,evidenceAssociationEvents:evidenceAssociationEvents,evidenceSequenceRevisions:evidenceSequenceRevisions,shopReportProfiles:shopReportProfiles,roundSessions:roundSessions))}
     func replacingWorkResources(_ value:[V37BackupWorkResourceRecordV1])->Self{Self(guidedSurveys:guidedSurveys,assetLocators:assetLocators,schedules:schedules,plans:plans,placementPoses:placementPoses,accessibleDocumentAssessments:accessibleDocumentAssessments,surveyDefinitions:surveyDefinitions,fieldReferences:fieldReferences,recoverabilityReceipts:recoverabilityReceipts,clientCapabilities:clientCapabilities,privacyTransforms:privacyTransforms,measurementIntegrity:measurementIntegrity,packageEvolution:packageEvolution,fieldDrafts:fieldDrafts,workPackets:workPackets,inspectionReview:inspectionReview,evidenceAssurance:evidenceAssurance,functionalRelationships:functionalRelationships,authorityCriterion:authorityCriterion,assetSemantics:assetSemantics,assetCompositionEdges:assetCompositionEdges,assetCompositionEvents:assetCompositionEvents,assetPlacementEvents:assetPlacementEvents,assets:assets,deletionLedger:deletionLedger,evidenceFiles:evidenceFiles,issues:issues,locationHierarchyEvents:locationHierarchyEvents,locationMigrationReceipts:locationMigrationReceipts,locationNodes:locationNodes,mutationHistory:mutationHistory,packets:packets,partyAccountability:partyAccountability,recordsSchemaVersion:recordsSchemaVersion,reports:reports,requirementAssurance:requirementAssurance,savedSmartViews:savedSmartViews,sites:sites,workflowRecords:workflowRecords,evidenceContexts:evidenceContexts,pairedObservationLinks:pairedObservationLinks,lighting:lighting,assistanceAcceptanceReceipts:assistanceAcceptanceReceipts,temporalEvidence:temporalEvidence,acceptedLabelGenerationSnapshots:acceptedLabelGenerationSnapshots,operationalContacts:operationalContacts,activityContracts:activityContracts,workResources:value,serviceRequests:serviceRequests,serviceRequestDispositionEvents:serviceRequestDispositionEvents,serviceRequestWorkLinkEvents:serviceRequestWorkLinkEvents,partsStockSnapshot:partsStockSnapshot,myDayPlans:myDayPlans,myDayCarryoverReceipts:myDayCarryoverReceipts,nonactivePlanReferences:nonactivePlanReferences,evidenceAssociationEvents:evidenceAssociationEvents,evidenceSequenceRevisions:evidenceSequenceRevisions,shopReportProfiles:shopReportProfiles,roundSessions:roundSessions))}

    func replacingServiceReliability(_ rows:C53ServiceReliabilityBackupRowsV1)throws->Self{
        Self(guidedSurveys:guidedSurveys,assetLocators:assetLocators,schedules:schedules,plans:plans,
             placementPoses:placementPoses,accessibleDocumentAssessments:accessibleDocumentAssessments,
             surveyDefinitions:surveyDefinitions,fieldReferences:fieldReferences,
             recoverabilityReceipts:recoverabilityReceipts,clientCapabilities:clientCapabilities,
             privacyTransforms:privacyTransforms,measurementIntegrity:measurementIntegrity,
             packageEvolution:packageEvolution,fieldDrafts:fieldDrafts,workPackets:workPackets,
             inspectionReview:inspectionReview,evidenceAssurance:evidenceAssurance,
             functionalRelationships:functionalRelationships,authorityCriterion:authorityCriterion,
             assetSemantics:assetSemantics,assetCompositionEdges:assetCompositionEdges,
             assetCompositionEvents:assetCompositionEvents,assetPlacementEvents:assetPlacementEvents,
             assets:assets,deletionLedger:deletionLedger,evidenceFiles:evidenceFiles,issues:issues,
             locationHierarchyEvents:locationHierarchyEvents,locationMigrationReceipts:locationMigrationReceipts,
             locationNodes:locationNodes,mutationHistory:mutationHistory,packets:packets,
             partyAccountability:partyAccountability,
             recordsSchemaVersion:max(recordsSchemaVersion,C53ServiceReliabilityBackupEnrollmentV1.recordsSchemaVersion),
             reports:reports,requirementAssurance:requirementAssurance,savedSmartViews:savedSmartViews,
             sites:sites,workflowRecords:workflowRecords,evidenceContexts:evidenceContexts,
             pairedObservationLinks:pairedObservationLinks,lighting:lighting,
             assistanceAcceptanceReceipts:assistanceAcceptanceReceipts,temporalEvidence:temporalEvidence,
             acceptedLabelGenerationSnapshots:acceptedLabelGenerationSnapshots,
             operationalContacts:operationalContacts,activityContracts:activityContracts,
             workResources:workResources,serviceRequests:serviceRequests,
             serviceRequestDispositionEvents:serviceRequestDispositionEvents,
             serviceRequestWorkLinkEvents:serviceRequestWorkLinkEvents,
             serviceReliabilityIncidents:try rows.incidents.map(V39BackupServiceReliabilityRecordV1.init),
             serviceImpactSegments:try rows.impactSegments.map(V39BackupServiceReliabilityRecordV1.init),
             serviceCauseAssertions:try rows.causeAssertions.map(V39BackupServiceReliabilityRecordV1.init),
             serviceRemedyAssertions:try rows.remedyAssertions.map(V39BackupServiceReliabilityRecordV1.init),
             serviceRepairIntervals:try rows.repairIntervals.map(V39BackupServiceReliabilityRecordV1.init),
             serviceRestorationAssertions:try rows.restorationAssertions.map(V39BackupServiceReliabilityRecordV1.init),
             qualifiedServiceExposures:try rows.qualifiedExposures.map(V39BackupServiceReliabilityRecordV1.init),
             serviceReliabilityReceipts:try rows.receipts.map(V39BackupServiceReliabilityReceiptRecordV1.init),
             partsStockSnapshot:partsStockSnapshot,myDayPlans:myDayPlans,myDayCarryoverReceipts:myDayCarryoverReceipts,nonactivePlanReferences:nonactivePlanReferences,evidenceAssociationEvents:evidenceAssociationEvents,evidenceSequenceRevisions:evidenceSequenceRevisions,shopReportProfiles:shopReportProfiles,roundSessions:roundSessions))
    }

    func replacingShopReportProfiles(_ values: [ShopReportProfileV1]) -> Self {
        Self(guidedSurveys:guidedSurveys,assetLocators:assetLocators,schedules:schedules,plans:plans,placementPoses:placementPoses,accessibleDocumentAssessments:accessibleDocumentAssessments,surveyDefinitions:surveyDefinitions,fieldReferences:fieldReferences,recoverabilityReceipts:recoverabilityReceipts,clientCapabilities:clientCapabilities,privacyTransforms:privacyTransforms,measurementIntegrity:measurementIntegrity,packageEvolution:packageEvolution,fieldDrafts:fieldDrafts,workPackets:workPackets,inspectionReview:inspectionReview,evidenceAssurance:evidenceAssurance,functionalRelationships:functionalRelationships,authorityCriterion:authorityCriterion,assetSemantics:assetSemantics,assetCompositionEdges:assetCompositionEdges,assetCompositionEvents:assetCompositionEvents,assetPlacementEvents:assetPlacementEvents,assets:assets,deletionLedger:deletionLedger,evidenceFiles:evidenceFiles,issues:issues,locationHierarchyEvents:locationHierarchyEvents,locationMigrationReceipts:locationMigrationReceipts,locationNodes:locationNodes,mutationHistory:mutationHistory,packets:packets,partyAccountability:partyAccountability,recordsSchemaVersion:recordsSchemaVersion,reports:reports,requirementAssurance:requirementAssurance,savedSmartViews:savedSmartViews,sites:sites,workflowRecords:workflowRecords,evidenceContexts:evidenceContexts,pairedObservationLinks:pairedObservationLinks,lighting:lighting,assistanceAcceptanceReceipts:assistanceAcceptanceReceipts,temporalEvidence:temporalEvidence,acceptedLabelGenerationSnapshots:acceptedLabelGenerationSnapshots,operationalContacts:operationalContacts,activityContracts:activityContracts,workResources:workResources,serviceRequests:serviceRequests,serviceRequestDispositionEvents:serviceRequestDispositionEvents,serviceRequestWorkLinkEvents:serviceRequestWorkLinkEvents,partsStockSnapshot:partsStockSnapshot,myDayPlans:myDayPlans,myDayCarryoverReceipts:myDayCarryoverReceipts,nonactivePlanReferences:nonactivePlanReferences,evidenceAssociationEvents:evidenceAssociationEvents,evidenceSequenceRevisions:evidenceSequenceRevisions,shopReportProfiles:values,roundSessions:roundSessions)
    }

    func replacingRoundSessions(_ values: [RoundSessionV1]) -> Self {
        Self(guidedSurveys:guidedSurveys,assetLocators:assetLocators,schedules:schedules,plans:plans,placementPoses:placementPoses,accessibleDocumentAssessments:accessibleDocumentAssessments,surveyDefinitions:surveyDefinitions,fieldReferences:fieldReferences,recoverabilityReceipts:recoverabilityReceipts,clientCapabilities:clientCapabilities,privacyTransforms:privacyTransforms,measurementIntegrity:measurementIntegrity,packageEvolution:packageEvolution,fieldDrafts:fieldDrafts,workPackets:workPackets,inspectionReview:inspectionReview,evidenceAssurance:evidenceAssurance,functionalRelationships:functionalRelationships,authorityCriterion:authorityCriterion,assetSemantics:assetSemantics,assetCompositionEdges:assetCompositionEdges,assetCompositionEvents:assetCompositionEvents,assetPlacementEvents:assetPlacementEvents,assets:assets,deletionLedger:deletionLedger,evidenceFiles:evidenceFiles,issues:issues,locationHierarchyEvents:locationHierarchyEvents,locationMigrationReceipts:locationMigrationReceipts,locationNodes:locationNodes,mutationHistory:mutationHistory,packets:packets,partyAccountability:partyAccountability,recordsSchemaVersion:recordsSchemaVersion,reports:reports,requirementAssurance:requirementAssurance,savedSmartViews:savedSmartViews,sites:sites,workflowRecords:workflowRecords,evidenceContexts:evidenceContexts,pairedObservationLinks:pairedObservationLinks,lighting:lighting,assistanceAcceptanceReceipts:assistanceAcceptanceReceipts,temporalEvidence:temporalEvidence,acceptedLabelGenerationSnapshots:acceptedLabelGenerationSnapshots,operationalContacts:operationalContacts,activityContracts:activityContracts,workResources:workResources,serviceRequests:serviceRequests,serviceRequestDispositionEvents:serviceRequestDispositionEvents,serviceRequestWorkLinkEvents:serviceRequestWorkLinkEvents,partsStockSnapshot:partsStockSnapshot,myDayPlans:myDayPlans,myDayCarryoverReceipts:myDayCarryoverReceipts,nonactivePlanReferences:nonactivePlanReferences,evidenceAssociationEvents:evidenceAssociationEvents,evidenceSequenceRevisions:evidenceSequenceRevisions,shopReportProfiles:shopReportProfiles,roundSessions:values)
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

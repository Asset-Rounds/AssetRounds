import Foundation

enum WorkflowScheduleBoundaryV1 { static let dueProjectionMayStartWorkflow = false }

enum WorkflowAssetLocatorBoundaryV1 {
    static let resolutionStartsWorkflow = false
    static let captureStoresFrozenInterpretation = true

    static func freeze(
        resolution: LocatorResolutionV1,
        locator: AssetLocatorV1,
        receipt: LocatorBindingReceiptV1
    ) throws -> FrozenAssetLocatorInterpretationV1 {
        try resolution.validate()
        try locator.validate()
        try receipt.validateIntrinsic()
        guard resolution.outcome == .matched,
              resolution.matchedLocator == locator.reference,
              resolution.matchedAssetID == locator.assetID,
              receipt.after == locator.reference else {
            throw AssetLocatorFailureV1.invalidValue
        }
        return try FrozenAssetLocatorInterpretationV1(
            locator: locator.reference, receipt: receipt, assetID: locator.assetID
        )
    }
}

enum WorkflowRevisionKind: String, CaseIterable, Codable, Sendable {
    case original
    case clericalCorrection = "clerical_correction"
}

enum SurveySessionWorkflowBoundaryV1 {
    static func validate(_ closure:SurveySessionLifecycleClosureV1)throws{try closure.validate()}
    static let claimsInspectionPassFail=false
    static let usesSoleWorkspaceWriter=true
}

struct WorkflowSurveyDefinitionBindingV1: Codable, Equatable, Sendable {
    let activityKind: ActivityKindV1
    let release: SurveyDefinitionReleaseReferenceV1
    init(_ value: SurveyDefinitionReleaseV1) throws { try value.validate(); activityKind = value.activityKind; release = try .init(value) }
    func validate() throws { try release.validate() }
}

enum WorkflowAccessibleDocumentBoundaryV1{
    static let assessmentChangesWorkflowOutcome=false
    static let externalProofChangesInspectionTruth=false
}

enum WorkflowStage: String, CaseIterable, Codable, Sendable {
    case check
    case work
    case recheck
}

enum WorkflowState: String, CaseIterable, Codable, Sendable {
    case draft
    case completed
}

enum WorkflowDraftStep: String, CaseIterable, Codable, Sendable {
    case wide
    case close
    case outcome
    case review
}

enum IssueStatus: String, CaseIterable, Codable, Sendable {
    case open
    case recheckDue = "recheck_due"
    case resolved
}

enum ReportPDFState: String, CaseIterable, Codable, Sendable {
    case pending
    case ready
    case failed
}

// MARK: - C23 version-bound field-reference work-session projections

/// C23 reference bindings are canonical rows owned by the field-reference
/// pack writer.  Workflow consumers carry this small metadata-only projection
/// instead of copying reference bytes, locators, or license material.
enum WorkSessionFieldReferenceFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case wrongWorkspace
    case wrongSubject
    case staleBinding
    case missingReadiness
    case divergentBinding
    case finalizedWorkImmutable
}

struct WorkSessionFieldReferenceProjectionV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let bindingID: UUID
    let workspaceID: WorkspaceID
    let subjectKind: FieldReferenceSubjectKindV1
    let subjectID: UUID
    let subjectRevision: UInt64
    let subjectState: FieldReferenceSubjectStateV1
    let releaseID: UUID
    let releaseRevision: UInt64
    let releaseSHA256: String
    let manifestSHA256: String
    let availability: FieldReferenceAvailabilityV1
    let missingContentIDs: [String]
    let readinessSHA256: String
    let projectionSHA256: String

    init(
        binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1
    ) throws {
        try Self.validateInputs(binding: binding, release: release, readiness: readiness)
        schemaVersion = Self.schemaVersion
        bindingID = binding.bindingID
        workspaceID = binding.workspaceID
        subjectKind = binding.subjectKind
        subjectID = binding.subjectID
        subjectRevision = binding.subjectRevision
        subjectState = binding.subjectState
        releaseID = release.releaseID
        releaseRevision = release.revision
        releaseSHA256 = release.releaseSHA256
        manifestSHA256 = release.manifestSHA256
        availability = readiness.availability
        missingContentIDs = readiness.missingContentIDs.sorted()
        readinessSHA256 = readiness.readinessSHA256
        projectionSHA256 = try Self.digest(
            bindingID: bindingID,
            workspaceID: workspaceID,
            subjectKind: subjectKind,
            subjectID: subjectID,
            subjectRevision: subjectRevision,
            subjectState: subjectState,
            releaseID: releaseID,
            releaseRevision: releaseRevision,
            releaseSHA256: releaseSHA256,
            manifestSHA256: manifestSHA256,
            availability: availability,
            missingContentIDs: missingContentIDs,
            readinessSHA256: readinessSHA256
        )
        try validate()
    }

    var isReadyOffline: Bool {
        availability == .readyOffline && missingContentIDs.isEmpty
    }

    func validate(
        expectedWorkspaceID: WorkspaceID? = nil,
        expectedSubjectKind: FieldReferenceSubjectKindV1? = nil,
        expectedSubjectID: UUID? = nil,
        expectedSubjectRevision: UInt64? = nil,
        expectedSubjectState: FieldReferenceSubjectStateV1? = nil
    ) throws {
        guard schemaVersion == Self.schemaVersion,
              workspaceID.rawValue != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              bindingID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              subjectID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              subjectRevision > 0,
              releaseID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              releaseRevision > 0,
              missingContentIDs == missingContentIDs.sorted(),
              Set(missingContentIDs).count == missingContentIDs.count,
              projectionSHA256 == (try Self.digest(
                  bindingID: bindingID,
                  workspaceID: workspaceID,
                  subjectKind: subjectKind,
                  subjectID: subjectID,
                  subjectRevision: subjectRevision,
                  subjectState: subjectState,
                  releaseID: releaseID,
                  releaseRevision: releaseRevision,
                  releaseSHA256: releaseSHA256,
                  manifestSHA256: manifestSHA256,
                  availability: availability,
                  missingContentIDs: missingContentIDs,
                  readinessSHA256: readinessSHA256
              )) else {
            throw WorkSessionFieldReferenceFailureV1.invalidValue
        }
        guard expectedWorkspaceID.map({ $0 == workspaceID }) ?? true,
              expectedSubjectKind.map({ $0 == subjectKind }) ?? true,
              expectedSubjectID.map({ $0 == subjectID }) ?? true,
              expectedSubjectRevision.map({ $0 == subjectRevision }) ?? true,
              expectedSubjectState.map({ $0 == subjectState }) ?? true else {
            throw WorkSessionFieldReferenceFailureV1.wrongSubject
        }
        try FieldReferenceValidationV1.digest(releaseSHA256)
        try FieldReferenceValidationV1.digest(manifestSHA256)
        try FieldReferenceValidationV1.digest(readinessSHA256)
        if availability == .readyOffline {
            guard missingContentIDs.isEmpty else {
                throw WorkSessionFieldReferenceFailureV1.missingReadiness
            }
        }
        if availability == .missingBytes {
            guard !missingContentIDs.isEmpty else {
                throw WorkSessionFieldReferenceFailureV1.missingReadiness
            }
        }
    }

    static func validateInputs(
        binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1
    ) throws {
        try binding.validate(release: release)
        guard readiness.releaseID == release.releaseID,
              readiness.bindingID == binding.bindingID else {
            throw WorkSessionFieldReferenceFailureV1.staleBinding
        }
        try FieldReferenceValidationV1.digest(readiness.readinessSHA256)
        let manifestContentIDs = Set(release.manifest.entries.map(\.contentID))
        guard readiness.missingContentIDs == readiness.missingContentIDs.sorted(),
              Set(readiness.missingContentIDs).count == readiness.missingContentIDs.count,
              readiness.missingContentIDs.allSatisfy({ manifestContentIDs.contains($0) }) else {
            throw WorkSessionFieldReferenceFailureV1.invalidValue
        }
    }

    private static func digest(
        bindingID: UUID,
        workspaceID: WorkspaceID,
        subjectKind: FieldReferenceSubjectKindV1,
        subjectID: UUID,
        subjectRevision: UInt64,
        subjectState: FieldReferenceSubjectStateV1,
        releaseID: UUID,
        releaseRevision: UInt64,
        releaseSHA256: String,
        manifestSHA256: String,
        availability: FieldReferenceAvailabilityV1,
        missingContentIDs: [String],
        readinessSHA256: String
    ) throws -> String {
        try WorkspaceMutationCanonicalV1.sha256(Basis(
            schemaVersion: Self.schemaVersion,
            bindingID: bindingID,
            workspaceID: workspaceID,
            subjectKind: subjectKind,
            subjectID: subjectID,
            subjectRevision: subjectRevision,
            subjectState: subjectState,
            releaseID: releaseID,
            releaseRevision: releaseRevision,
            releaseSHA256: releaseSHA256,
            manifestSHA256: manifestSHA256,
            availability: availability,
            missingContentIDs: missingContentIDs,
            readinessSHA256: readinessSHA256
        ))
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let bindingID: UUID
        let workspaceID: WorkspaceID
        let subjectKind: FieldReferenceSubjectKindV1
        let subjectID: UUID
        let subjectRevision: UInt64
        let subjectState: FieldReferenceSubjectStateV1
        let releaseID: UUID
        let releaseRevision: UInt64
        let releaseSHA256: String
        let manifestSHA256: String
        let availability: FieldReferenceAvailabilityV1
        let missingContentIDs: [String]
        let readinessSHA256: String
    }
}

enum WorkSessionFieldReferenceBindingV1 {
    static func validateSuccessor(
        _ successor: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        after predecessor: FieldReferenceBindingV1
    ) throws {
        guard predecessor.subjectState != .finalized else {
            throw WorkSessionFieldReferenceFailureV1.finalizedWorkImmutable
        }
        try successor.validateSuccessor(of: predecessor, release: release)
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_Workflow_WorkflowContracts {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_Workflow_WorkflowContracts_swift {
    /// Typed C37 boundary: inherited owners may retain an immutable pose
    /// reference, but cannot infer pose, compliance, or current-state truth.
    static func validate(reference: AssetPoseEventReferenceV1,
                         in workspaceID: WorkspaceID) throws {
        try reference.validate()
        guard reference.workspaceID == workspaceID else {
            throw PlacementPoseFailureV1.wrongWorkspace
        }
    }
}

enum C30EvidenceContextWorkflowBoundaryV1 {
    static let contextIsEvidenceNotCompliance = true
    static let temporalAndControlValuesAreExplicit = true
    static let automaticInferenceAllowed = false

    static func validate(context: EvidenceContextV1,
                         pairedLink: PairedObservationLinkV1? = nil) throws {
        try context.validateIntrinsic()
        if let pairedLink {
            try pairedLink.validateIntrinsic()
            guard pairedLink.workspaceID == context.workspaceID else {
                throw EvidenceContextFailureV1.wrongWorkspace
            }
        }
        guard contextIsEvidenceNotCompliance,
              temporalAndControlValuesAreExplicit,
              !automaticInferenceAllowed else {
            throw EvidenceContextFailureV1.invalidValue
        }
    }
}

enum C31LightingWorkflowBoundaryV1 {
    static let topologyAndObservationAreRecordedFacts = true
    static let measurementRequiresRecordedProtocolAndCalibration = true
    static let safetyStopBlocksUnsafeIntent = true
    static let previewNeverAppliesOrSavesTruth = true
    static let timestampPhotoAndSolarInferenceRejected = true

    static func validate(
        records: [V31BackupLightingRecordV1],
        workspaceID: WorkspaceID
    ) throws {
        let roots = try LightingBackupRecordSetV1.decode(records)
        let workspaces = roots.systems.map(\.workspaceID)
            + roots.observations.map(\.workspaceID)
            + roots.issues.map(\.workspaceID)
            + roots.plans.map(\.workspaceID)
            + roots.claims.map(\.workspaceID)
        guard workspaces.allSatisfy({ $0 == workspaceID }),
              topologyAndObservationAreRecordedFacts,
              measurementRequiresRecordedProtocolAndCalibration,
              safetyStopBlocksUnsafeIntent,
              previewNeverAppliesOrSavesTruth,
              timestampPhotoAndSolarInferenceRejected else {
            throw LightingContractFailureV1.wrongWorkspace
        }
    }
}
// MARK: - C32 assistance workflow boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Workflow_WorkflowContracts_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let workflowRevisionIsExpectedAcceptanceBoundary = true

    static func validateProposal(_ proposal: AssistanceProposalV1, in context: AssistanceProposalEvaluationContextV1) throws {
        try proposal.validate()
        try context.validate()
        guard proposal.verificationState.rawValue == AssistanceProposalVerificationStateV1.unverified.rawValue,
              context.policy.manualFallback == .typeManually else {
            throw AssistanceContractFailureV1.incompatibleCapability
        }
        if let reason = try proposal.expiryReason(in: context) {
            throw AssistanceContractFailureV1.expired(reason)
        }
    }

    static func validateAcceptanceReceipt(_ receipt: AssistanceAcceptanceReceiptV1) throws {
        try receipt.validate()
    }
}

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Domain_Workflow_WorkflowContracts_swift {
    static let durableFamilyCount = TemporalEvidencePersistenceEnrollmentV1.durableModelCount
    static func validate(clip: TemporalEvidenceClipV1,
                         anchor: TimecodedEvidenceAnchorV1) throws {
        try clip.validateIntrinsic()
        try anchor.validate(clip: clip)
        guard durableFamilyCount == 2 else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
    }
}

/// C45 label preview and generation remain outside survey answer mutation.
enum C45AssetLabelBoundary_WorkflowContractsV1 {
    static func validate(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws { try snapshot.validate() }
    static let writesSurveyFactsDuringPreview = false
}

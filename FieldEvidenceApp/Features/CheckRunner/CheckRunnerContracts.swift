import Foundation

struct CheckRunnerPreparation: Equatable, Sendable {
    let confirmedTimeZoneID: String?
    let existingDraftID: UUID?
}

struct BeginDraftSubmission: Equatable, Sendable {
    let assetID: UUID
    let requestedStage: WorkflowStage
    let issueID: UUID?
    let observedAtUTC: Date?
    let confirmedTimeZoneID: String?
    let afterDarkAccepted: Bool
    let safePositionAccepted: Bool
}

enum CheckRunnerCoordinatorError: Error, Equatable {
    case assetNotFound
    case siteNotFound
    case invalidTimeZoneID
    case timeZoneConfirmationRequired
    case acknowledgementsRequired
    case multipleActiveDrafts
    case issueRequired
    case issueNotAllowed
    case issueNotFound
    case issueAssetMismatch
    case issueStateMismatch
    case parentRecordMissing
    case invalidLineage
    case captureNotConfigured
    case captureDraftRequired
    case captureUnavailable
    case invalidCaptureState
    case mediaImportFailed
    case storageUnavailable
    case cleanupFailed
    case outcomeRequired
    case issueLabelRequired
    case issueLabelInvalid
    case reviewUnavailable
    case finalizationNotConfigured
    case finalizationFailed
    case packageLifecycleMismatch
    case legacyFinalizationReceiptDebt
    case saveFailed
    case workPacketUnavailable
    case workPacketStaleRevision
    case workPacketCollisionReviewRequired
    case accessDenied(DraftAccessDecisionV1)
}

struct PackFinalizationBindingV1: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let generationID: UUID
    let packageRelease: PackageReleaseIdentityV1
    let mutationID: MutationIDV1
    let durableReceiptIdentity: MutationReceiptIdentityV1?
    let preservesReservedLegacyRawWriteDebt: Bool

    init(
        workspaceID: WorkspaceID,
        generationID: UUID,
        packageRelease: PackageReleaseIdentityV1,
        mutationID: MutationIDV1,
        durableReceiptIdentity: MutationReceiptIdentityV1?,
        preservesReservedLegacyRawWriteDebt: Bool
    ) throws {
        guard generationID != Self.zero,
              durableReceiptIdentity?.workspaceID == workspaceID || durableReceiptIdentity == nil,
              (durableReceiptIdentity != nil) != preservesReservedLegacyRawWriteDebt else {
            throw CheckRunnerCoordinatorError.packageLifecycleMismatch
        }
        self.workspaceID = workspaceID
        self.generationID = generationID
        self.packageRelease = packageRelease
        self.mutationID = mutationID
        self.durableReceiptIdentity = durableReceiptIdentity
        self.preservesReservedLegacyRawWriteDebt = preservesReservedLegacyRawWriteDebt
    }

    private static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

/// The check runner may start new work only from a published, immutable
/// survey-definition release.  This is a narrow binding over the canonical
/// C25 release contract; it deliberately does not create a second definition
/// or lifecycle model in the runner feature.
struct CheckRunnerSurveyDefinitionStartBindingV1: Equatable, Sendable {
    let release: SurveyDefinitionReleaseV1
    let lifecycleState: SurveyDefinitionLifecycleStateV1

    init(
        release: SurveyDefinitionReleaseV1,
        lifecycleState: SurveyDefinitionLifecycleStateV1
    ) throws {
        try release.validate()
        guard lifecycleState == .published else {
            throw CheckRunnerCoordinatorError.packageLifecycleMismatch
        }
        self.release = release
        self.lifecycleState = lifecycleState
    }

    func validate() throws {
        try release.validate()
        guard lifecycleState == .published else {
            throw CheckRunnerCoordinatorError.packageLifecycleMismatch
        }
    }
}

enum CheckOutcomeSelection: Equatable, Sendable {
    case noVisibleIssue
    case visibleIssue(labelKey: String)
    case couldNotVerify(reasonKey: String, note: String?)
    case resolved(note: String?)
    case issueStillVisible(note: String?)
    case originalResolvedDifferentIssue(labelKey: String, note: String?)
}

struct ReviewEvidence: Equatable, Sendable {
    let id: UUID
    let purposeKey: String
    let purposeDisplay: String
    let thumbnailRelativePath: String
}

struct FinalizationReview: Equatable, Sendable {
    let draftID: UUID
    let outcomeKey: String
    let outcomeDisplay: String
    let issueLabelDisplay: String?
    let wideEvidence: ReviewEvidence?
    let closeEvidence: ReviewEvidence?
    let couldNotVerifyReasonDisplay: String?
    let note: String?
    let missingPurposeDisplays: [String]
    let localDate: String
    let localTime: String
    let timeZoneID: String
    let afterDarkAcknowledgementCopy: String
    let safePositionAcknowledgementCopy: String
}

struct FinalizationIdentifiers: Equatable, Sendable {
    let mutationID: UUID
    let packetID: UUID
    let stableRootID: UUID
    let reportID: UUID
    let issueID: UUID?
    let newIssueID: UUID?

    init(
        mutationID: UUID,
        packetID: UUID,
        stableRootID: UUID,
        reportID: UUID,
        issueID: UUID?,
        newIssueID: UUID? = nil
    ) {
        self.mutationID = mutationID
        self.packetID = packetID
        self.stableRootID = stableRootID
        self.reportID = reportID
        self.issueID = issueID
        self.newIssueID = newIssueID
    }
}

struct FinalizationResult: Equatable, Sendable {
    let recordID: UUID
    let packetID: UUID
    let stableRootID: UUID
    let reportID: UUID
    let issueID: UUID?
    let newIssueID: UUID?
    let snapshotRelativePath: String
    let snapshotSHA256: String

    init(
        recordID: UUID,
        packetID: UUID,
        stableRootID: UUID,
        reportID: UUID,
        issueID: UUID?,
        newIssueID: UUID? = nil,
        snapshotRelativePath: String,
        snapshotSHA256: String
    ) {
        self.recordID = recordID
        self.packetID = packetID
        self.stableRootID = stableRootID
        self.reportID = reportID
        self.issueID = issueID
        self.newIssueID = newIssueID
        self.snapshotRelativePath = snapshotRelativePath
        self.snapshotSHA256 = snapshotSHA256
    }
}

struct CapturePreparation: Equatable, Sendable {
    let draftID: UUID
    let step: WorkflowDraftStep
    let purpose: SignPack.EvidencePurpose?
}

struct CaptureCandidate: Equatable, Sendable {
    let id: UUID
    let recordID: UUID
    let purposeKey: String
    let createdAt: Date
    let previewJPEG: Data
    let stagedBundle: StagedEvidenceBundle
}

// MARK: - C36 draft capture bridge

enum CheckRunnerDraftBridgeFailureV1: Error, Equatable, Sendable {
    case invalidDraft
    case wrongWorkspace
    case stageNotReady
    case accessRequired
    case legacyEvidenceIDRequiredAfterCommit
}

/// The check runner's C36 boundary is a draft-owned candidate.  It deliberately
/// carries no EvidenceID and no canonical evidence bytes; the C36 coordinator
/// obtains a content reservation and commits it before any legacy finalization
/// route is considered.
struct CheckRunnerDraftCaptureCandidateV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let draftID: UUID
    let stageID: UUID
    let attachmentKind: DraftAttachmentKindV1
    let itemRevision: UInt64
    let stageSHA256: String
    let durability: DraftAttachmentPresentationStateV1
    let legacyBridgeDisposition: CheckRunnerLegacyBridgeDispositionV1

    init(
        item: AttachmentStagingItemV1,
        durableReceiptReadBack: Bool
    ) throws {
        try item.validate()
        guard item.state == .readyLocal || item.state == .committed else {
            throw CheckRunnerDraftBridgeFailureV1.stageNotReady
        }
        workspaceID = item.workspaceID
        draftID = item.draftID
        stageID = item.stageID
        attachmentKind = item.attachmentKind
        itemRevision = item.revision
        stageSHA256 = item.stageSHA256
        durability = DraftAttachmentPresentationMapperV1.state(
            for: item,
            durableReceiptReadBack: durableReceiptReadBack
        )
        legacyBridgeDisposition = .draftOwnedUntilCanonicalCommit
    }
}

enum CheckRunnerLegacyBridgeDispositionV1: String, Codable, Equatable, Hashable, Sendable {
    case draftOwnedUntilCanonicalCommit = "DRAFT_OWNED_UNTIL_CANONICAL_COMMIT"
    case legacyEvidenceRouteAfterCommit = "LEGACY_EVIDENCE_ROUTE_AFTER_COMMIT"
}

struct CheckRunnerDraftDurabilitySnapshotV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let draftID: UUID
    let state: DraftDurabilityPresentationStateV1
    let stagedItemCount: Int
    let readyItemCount: Int
    let retryableItemCount: Int
    let protectedDataBlocked: Bool
    let lowStorageBlocked: Bool

    init(
        checkpoint: FieldDraftCheckpointV1,
        items: [AttachmentStagingItemV1],
        receiptReadBack: Bool = true
    ) throws {
        try checkpoint.validate()
        guard items.count <= FieldDraftLimitsV1.maximumStageItems,
              items.allSatisfy({ $0.workspaceID == checkpoint.workspaceID
                  && $0.draftID == checkpoint.draftID }) else {
            throw CheckRunnerDraftBridgeFailureV1.wrongWorkspace
        }
        workspaceID = checkpoint.workspaceID
        draftID = checkpoint.draftID
        state = DraftDurabilityPresentationMapperV1.state(
            checkpoint: checkpoint,
            hasDirtyChanges: checkpoint.state == .active && !receiptReadBack,
            writeInFlight: false,
            writeBlocked: items.contains {
                $0.protectionState != .available
                    || $0.state == .failedFinal
            },
            receiptReadBack: receiptReadBack
        )
        stagedItemCount = items.count
        readyItemCount = items.filter {
            $0.state == .readyLocal || $0.state == .committed
        }.count
        retryableItemCount = items.filter { $0.state == .failedRetryable }.count
        protectedDataBlocked = items.contains { $0.protectionState == .protectedDataUnavailable }
        lowStorageBlocked = items.contains { $0.protectionState == .lowStorage }
    }
}

enum CheckRunnerDraftBridgeV1 {
    static let preservesExistingEntitlementGate = true
    static let assignsEvidenceIDBeforeCommit = false
    static let importsLegacyBundleBeforeCommit = false

    static func captureCandidate(
        item: AttachmentStagingItemV1,
        durableReceiptReadBack: Bool,
        accessState: DraftAccessNormalizedStateV1
    ) throws -> CheckRunnerDraftCaptureCandidateV1 {
        guard accessState == .entitled
                || accessState == .formerPaidInactive
                || accessState == .neverPaid
                || accessState == .loading(.validCachedEntitlement) else {
            throw CheckRunnerDraftBridgeFailureV1.accessRequired
        }
        return try CheckRunnerDraftCaptureCandidateV1(
            item: item,
            durableReceiptReadBack: durableReceiptReadBack
        )
    }
}

enum CheckRunnerCoordinatorFailurePoint: Equatable, Sendable {
    case evidenceModelSave
}

enum CheckRunnerCompatibilityPostureV1: String, Sendable {
    case frozenS10CallersOnly = "FROZEN_S10_CALLERS_ONLY_EXPIRES_AFTER_ACCEPTED_S10_6_RECONCILIATION"
}

enum RequirementAssuranceGateFailureV1: String, Equatable, Sendable {
    case notConfigured = "NOT_CONFIGURED"
    case noAcceptedRevision = "NO_ACCEPTED_REVISION"
    case staleRevision = "STALE_REVISION"
    case unknownRequirementType = "UNKNOWN_REQUIREMENT_TYPE"
    case missingEvaluator = "MISSING_EVALUATOR"
    case cancelled = "CANCELLED"
    case protectedDataUnavailable = "PROTECTED_DATA_UNAVAILABLE"
    case persistenceUnavailable = "PERSISTENCE_UNAVAILABLE"
    case invalidCanonicalState = "INVALID_CANONICAL_STATE"
}

/// A non-UI, fail-closed result for future site-exit callers. A prior accepted
/// snapshot is evidence only; it never turns a failed candidate evaluation into
/// permission to complete.
struct RequirementAssuranceGatePreflightV1: Equatable, Sendable {
    let candidateSnapshot: RequirementAssuranceSnapshotV1?
    let priorAcceptedSnapshot: RequirementAssuranceSnapshotV1?
    let failure: RequirementAssuranceGateFailureV1?

    var decision: CompletionDecisionV1? { candidateSnapshot?.decision }
    var explanations: [RequirementExplanationItemV1] {
        candidateSnapshot.map { RequirementExplanationProjectionV1.project($0.evaluations) } ?? []
    }
    var permitsCompletion: Bool {
        failure == nil
            && candidateSnapshot?.decision.disposition == .permitted
            && candidateSnapshot?.findings.isEmpty == true
    }

    static func evaluated(
        _ snapshot: RequirementAssuranceSnapshotV1,
        priorAcceptedSnapshot: RequirementAssuranceSnapshotV1?
    ) -> Self {
        Self(
            candidateSnapshot: snapshot,
            priorAcceptedSnapshot: priorAcceptedSnapshot,
            failure: nil
        )
    }

    static func failed(
        _ failure: RequirementAssuranceGateFailureV1,
        priorAcceptedSnapshot: RequirementAssuranceSnapshotV1?
    ) -> Self {
        Self(
            candidateSnapshot: nil,
            priorAcceptedSnapshot: priorAcceptedSnapshot,
            failure: failure
        )
    }
}

enum RequirementAssuranceProvisionalReachabilityV1: String, Equatable, Sendable {
    case universalFinalizationGate = "NOT_PROVEN_S10_RESERVED"
    case completedSnapshotCreation = "NOT_PROVEN_S10_RESERVED"
    case siteExitAccessibility = "NOT_RUN_NO_CREDIT_S10_RESERVED"
}

/// Read-only handoff from CheckRunner completion into the C14 review stream.
/// It is not saved state and cannot claim review acceptance.
struct CheckRunnerInspectionReviewCandidateV1: Equatable, Sendable {
    let subject: InspectionReviewSubjectReferenceV1
    let initialState: InspectionReviewStateV1

    init(subject: InspectionReviewSubjectReferenceV1) throws {
        try subject.validate()
        self.subject = subject
        initialState = .draft
    }
}

/// Read-only packet context supplied to a check runner. It carries the exact
/// manifest/item identity and expected revision required for a later writer
/// command, but it does not claim the item, acquire a lease, or expose actor
/// or result/evidence detail.
struct CheckRunnerWorkPacketContextV1: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let packetID: UUID
    let packetVersion: UInt64
    let manifestID: UUID
    let manifestSHA256: String
    let itemID: String
    let itemKind: WorkPacketItemKindV1
    let expectedRevision: UInt64
    let itemSHA256: String
    let currentState: CompletedWorkPacketItemStateV1
    let sourceRevision: UInt64

    init(
        snapshot: CompletedWorkPacketSnapshotV1,
        itemID: String
    ) throws {
        try snapshot.validate()
        guard let item = snapshot.manifest.items.first(where: { $0.itemID == itemID }),
              let itemSnapshot = snapshot.items.first(where: { $0.itemID == itemID }) else {
            throw CheckRunnerCoordinatorError.workPacketUnavailable
        }
        workspaceID = snapshot.workspaceID
        packetID = snapshot.manifest.packetID
        packetVersion = snapshot.manifest.packetVersion
        manifestID = snapshot.manifest.manifestID
        manifestSHA256 = snapshot.manifest.manifestSHA256
        self.itemID = item.itemID
        itemKind = item.kind
        expectedRevision = item.expectedRevision
        itemSHA256 = item.itemSHA256
        currentState = itemSnapshot.state
        sourceRevision = snapshot.sourceRevision
        try validate()
    }

    func validate() throws {
        guard workspaceID.rawValue != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              packetID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              packetVersion > 0,
              manifestID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              KernelCanonicalHashV1.validSHA256(manifestSHA256),
              SnapshotProjectionValidationV1.validText(itemID),
              expectedRevision > 0,
              KernelCanonicalHashV1.validSHA256(itemSHA256),
              sourceRevision > 0 else {
            throw CheckRunnerCoordinatorError.workPacketUnavailable
        }
    }
}

/// Explicit review handoff for a packet collision. All canonical products
/// remain preserved; the runner only receives a safe count/kind summary and
/// must not treat this value as an approval or automatic merge.
struct CheckRunnerWorkPacketCollisionReviewV1: Equatable, Sendable {
    let packetID: UUID
    let itemID: String
    let conflictKinds: [WorkPacketConflictKindV1]
    let preservedResultCount: Int
    let reviewRequired: Bool

    init(
        packetID: UUID,
        item: CompletedWorkPacketItemSnapshotV1
    ) throws {
        guard packetID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) else {
            throw CheckRunnerCoordinatorError.workPacketUnavailable
        }
        try item.validate()
        self.packetID = packetID
        itemID = item.itemID
        conflictKinds = item.conflictKinds
        preservedResultCount = item.preservedResultCount
        reviewRequired = !item.conflictKinds.isEmpty
    }

    func validate() throws {
        guard packetID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              SnapshotProjectionValidationV1.validText(itemID),
              conflictKinds == conflictKinds.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(conflictKinds).count == conflictKinds.count,
              preservedResultCount >= 0,
              reviewRequired == !conflictKinds.isEmpty else {
            throw CheckRunnerCoordinatorError.workPacketUnavailable
        }
    }
}

// MARK: - C19 measurement capture boundary

/// Read-only check input for a C19 capture. It validates the existing field,
/// package, observation, actor, and calibration references without creating
/// a second evaluator or writing durable state.
struct CheckRunnerMeasurementCaptureContextV1: Equatable, Sendable {
    let capture: MeasurementCaptureV1
    let fieldDefinition: ResponseFieldDefinitionV1
    let protocolRelease: MeasurementProtocolReleaseV1
    let instrument: InstrumentReferenceV1?
    let calibration: CalibrationStatusSnapshotV1?

    init(
        capture: MeasurementCaptureV1,
        fieldDefinition: ResponseFieldDefinitionV1,
        protocolRelease: MeasurementProtocolReleaseV1,
        instrument: InstrumentReferenceV1? = nil,
        calibration: CalibrationStatusSnapshotV1? = nil
    ) throws {
        self.capture = capture
        self.fieldDefinition = fieldDefinition
        self.protocolRelease = protocolRelease
        self.instrument = instrument
        self.calibration = calibration
        try validate()
    }

    func validate() throws {
        try capture.response.value.c19ValidateMeasurementEquality(capture.measurement)
        try fieldDefinition.validateMeasurementCapture(capture)
        try protocolRelease.c19ValidateCapture(capture)
        try capture.validateClosure(instrument: instrument, calibration: calibration)
        try capture.observationBasis.c19ValidateMeasurementCapture(sourceMode: capture.sourceMode)
        try capture.operatorSnapshot.c19ValidateMeasurementOperator(in: capture.workspaceID)
        if capture.sourceMode == .localObservation, let instrument {
            guard instrument.supportedUnitIDs.contains(capture.measurement.enteredUnitID) else {
                throw MeasurementIntegrityFailureV1.unsupportedSource
            }
        }
        guard protocolRelease.workspaceID == capture.workspaceID else {
            throw MeasurementIntegrityFailureV1.wrongWorkspace
        }
    }
}

// MARK: - C20 reviewed-derivative check boundary

/// Read-only privacy projection input for a check runner. The context keeps
/// source revision/digest and the requested audience explicit so callers
/// cannot accidentally reuse a stale or differently scoped derivative. A
/// successful projection is evidence for the check only; it never completes
/// a workflow or makes a privacy/compliance decision on its own.
struct CheckRunnerPrivacyTransformContextV1: Equatable, Sendable {
    let manifest: PrivacyTransformManifestV1
    let review: PrivacyReviewReceiptV1?
    let policy: PrivacyTransformPolicyV1
    let requestedAudience: EvidenceAudienceV1
    let currentSourceRevision: UInt64
    let currentSourceSHA256: String
    let evaluatedAt: Date

    init(
        manifest: PrivacyTransformManifestV1,
        review: PrivacyReviewReceiptV1?,
        policy: PrivacyTransformPolicyV1,
        requestedAudience: EvidenceAudienceV1,
        currentSourceRevision: UInt64,
        currentSourceSHA256: String,
        at evaluatedAt: Date
    ) throws {
        self.manifest = manifest
        self.review = review
        self.policy = policy
        self.requestedAudience = requestedAudience
        self.currentSourceRevision = currentSourceRevision
        self.currentSourceSHA256 = currentSourceSHA256
        self.evaluatedAt = evaluatedAt
        try validate()
    }

    func projectionDecision() throws -> PrivacyProjectionDecisionV1 {
        try C20PrivacyProjectionBridgeV1.decision(
            manifest: manifest,
            review: review,
            policy: policy,
            requestedAudience: requestedAudience,
            currentSourceRevision: currentSourceRevision,
            currentSourceSHA256: currentSourceSHA256,
            at: evaluatedAt
        )
    }

    func validate() throws {
        _ = try projectionDecision()
    }

    /// Returns a derivative only when the canonical projection gate allows
    /// it. Denials are preserved as typed C20 failures and never downgraded
    /// to an empty or original-content reference.
    func reviewedDerivative() throws -> ContentReferenceV1 {
        try C20PrivacyProjectionBridgeV1.requireAllowed(
            manifest: manifest,
            review: review,
            policy: policy,
            requestedAudience: requestedAudience,
            currentSourceRevision: currentSourceRevision,
            currentSourceSHA256: currentSourceSHA256,
            at: evaluatedAt
        )
    }
}

// MARK: - C23 version-bound field-reference check context

/// A check receives a packet context and an explicit metadata-only reference
/// projection. Missing bytes remain visible as a typed availability state and
/// are never treated as an empty successful reference.
struct CheckRunnerFieldReferenceContextV1: Equatable, Sendable {
    let packet: CheckRunnerWorkPacketContextV1
    let fieldReferences: WorkPacketFieldReferenceProjectionV1

    init(
        snapshot: CompletedWorkPacketSnapshotV1,
        itemID: String,
        fieldReferenceBindings: [FieldReferenceBindingV1],
        fieldReferenceReleases: [FieldReferenceReleaseV1],
        fieldReferenceReadiness: [FieldReferenceOfflineReadinessV1]
    ) throws {
        let packet = try CheckRunnerWorkPacketContextV1(
            snapshot: snapshot, itemID: itemID
        )
        let projection = try WorkPacketReferenceProjectionBuilderV1.rebuild(
            workspaceID: snapshot.workspaceID,
            manifest: snapshot.manifest,
            claims: snapshot.claims,
            leases: snapshot.leases,
            releases: snapshot.releases,
            handoffs: snapshot.handoffs,
            fieldReferenceBindings: fieldReferenceBindings,
            fieldReferenceReleases: fieldReferenceReleases,
            fieldReferenceReadiness: fieldReferenceReadiness,
            subjectState: .finalized,
            at: snapshot.createdAt
        )
        self.packet = packet
        fieldReferences = projection
        try validate()
    }

    func validate() throws {
        try packet.validate()
        try fieldReferences.validate()
        guard fieldReferences.packetID == packet.packetID,
              fieldReferences.packetVersion == packet.packetVersion,
              fieldReferences.manifestSHA256 == packet.manifestSHA256,
              packet.currentState != .conflicted else {
            throw CheckRunnerCoordinatorError.workPacketUnavailable
        }
        guard fieldReferences.references.allSatisfy({
            $0.subjectState == .finalized
        }) else {
            throw CheckRunnerCoordinatorError.workPacketUnavailable
        }
    }

    /// A check may consume bytes only after every supplied reference is
    /// explicitly ready offline. Empty input is allowed for packets with no
    /// field-reference requirement; a missing-content state is not success.
    func requireReadyOffline() throws {
        try validate()
        guard fieldReferences.references.allSatisfy(\.isReadyOffline) else {
            throw CheckRunnerCoordinatorError.workPacketUnavailable
        }
    }
}

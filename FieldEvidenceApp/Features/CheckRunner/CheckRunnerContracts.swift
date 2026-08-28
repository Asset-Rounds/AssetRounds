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

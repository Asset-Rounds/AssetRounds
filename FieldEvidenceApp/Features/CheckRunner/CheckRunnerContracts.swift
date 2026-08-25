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
    case saveFailed
    case accessDenied(DraftAccessDecisionV1)
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

import Foundation

/// SIG-1 completed-work subject vocabulary. Every value here is in-memory
/// only. The durable binding remains the unchanged `SignoffSnapshotV1`
/// `(subjectID, subjectRevision)` pair stored under the C43 purpose
/// `WORK_DETAIL_COMPLETED_RESPONSE_V1`, which permanently means an approval
/// response. No schema, store or persisted route is introduced.
enum CompletedWorkSubjectFamilyV1: String, CaseIterable, Hashable, Sendable {
    /// A finalized legacy `Report` whose frozen `ReportSnapshotV1` bytes pass
    /// `SnapshotValidatorV1.validateCompletedInspection`.
    case legacyReportSnapshot = "LEGACY_REPORT_SNAPSHOT"
    /// Reserved for typed `CompletedActivitySnapshotV2` and C06 file subjects.
    /// Batch 1 has no producer or resolver for this family; it always
    /// resolves as unavailable and can never be recorded against.
    case typedCompletedActivityReserved = "TYPED_COMPLETED_ACTIVITY_RESERVED"
}

enum CompletedWorkSubjectFailureV1: Error, Equatable, Sendable {
    case invalidKey
    case unsupportedPurpose
    case storeUnavailable
}

/// The identity of one immutable completed-work version. `subjectID` is the
/// `Report.id`; `subjectRevision` is that report's fixed position in its
/// correction chain (1 for the original, plus one per `replacesReportID` link
/// back to it). It is never the chain length.
struct CompletedWorkSubjectKeyV1: Hashable, Sendable {
    let workspaceID: WorkspaceID
    let family: CompletedWorkSubjectFamilyV1
    let subjectID: UUID
    let subjectRevision: UInt64

    init(
        workspaceID: WorkspaceID,
        family: CompletedWorkSubjectFamilyV1 = .legacyReportSnapshot,
        subjectID: UUID,
        subjectRevision: UInt64
    ) throws {
        guard workspaceID.rawValue != PartyAccountabilityValidationV1.zero,
              subjectID != PartyAccountabilityValidationV1.zero,
              subjectRevision > 0 else {
            throw CompletedWorkSubjectFailureV1.invalidKey
        }
        self.workspaceID = workspaceID
        self.family = family
        self.subjectID = subjectID
        self.subjectRevision = subjectRevision
    }

    /// The subject kind is implied by the C43 purpose, which the writer
    /// already enforces for this purpose. Any other purpose is not a
    /// completed-work approval response and cannot produce a key.
    init(signoff: SignoffSnapshotV1) throws {
        guard signoff.purpose
                == SignoffEnrollmentManifestV1.workDetailCompletedResponseV1.purpose else {
            throw CompletedWorkSubjectFailureV1.unsupportedPurpose
        }
        try self.init(
            workspaceID: signoff.workspaceID,
            family: .legacyReportSnapshot,
            subjectID: signoff.subjectID,
            subjectRevision: signoff.subjectRevision
        )
    }
}

enum CompletedWorkSubjectUnavailableReasonV1: String, CaseIterable, Hashable, Sendable {
    case missing = "MISSING"
    case deleted = "DELETED"
    case tampered = "TAMPERED"
    case notCompleted = "NOT_COMPLETED"
    case unsupportedFamily = "UNSUPPORTED_FAMILY"
    case wrongWorkspace = "WRONG_WORKSPACE"
    case revisionMismatch = "REVISION_MISMATCH"
    case storeUnavailable = "STORE_UNAVAILABLE"

    var displayText: String {
        switch self {
        case .missing:
            return "This completed work could not be found."
        case .deleted:
            return "This completed work was deleted."
        case .tampered:
            return "This completed work could not be checked as unchanged."
        case .notCompleted:
            return "This work is not completed."
        case .unsupportedFamily:
            return "Responses are not available for this kind of completed work yet."
        case .wrongWorkspace:
            return "This completed work belongs to a different workspace."
        case .revisionMismatch:
            return "This version of the completed work is not available."
        case .storeUnavailable:
            return "Completed work could not be opened."
        }
    }
}

enum CompletedWorkSubjectEligibilityV1: Hashable, Sendable {
    case eligible
    case superseded
    case unavailable(CompletedWorkSubjectUnavailableReasonV1)

    var canRecord: Bool {
        if case .eligible = self { return true }
        return false
    }

    /// The on-screen reason for an ineligible subject. `nil` when eligible.
    var reasonText: String? {
        switch self {
        case .eligible:
            return nil
        case .superseded:
            return "A newer version of this completed work exists. Responses can be recorded only on the current version."
        case let .unavailable(reason):
            return reason.displayText
        }
    }
}

/// Human display taken only from the frozen report snapshot. It never joins
/// current Party, Site or Asset rows and never contains an identifier.
struct CompletedWorkSubjectDisplayV1: Hashable, Sendable {
    let siteLabel: String
    let assetLabel: String
    let stage: String
    let outcome: String
    let localDate: String
    let localTime: String
    let version: UInt64

    var versionText: String { "Version \(version)" }
    var whenText: String { "\(localDate) at \(localTime)" }
}

/// In-memory proof that a key currently names one validated, immutable
/// completed-work version. It is checked before any write and again
/// immediately before the signoff commit.
struct CompletedWorkSubjectProofV1: Hashable, Sendable {
    let workspaceID: WorkspaceID
    let generationID: UUID
    let reportID: UUID
    let packetID: UUID
    let sourceRecordID: UUID
    let chainPosition: UInt64
    let snapshotFamily: CompletedWorkSubjectFamilyV1
    let snapshotSchemaVersion: Int
    let snapshotSHA256: String
    let isTip: Bool
    let display: CompletedWorkSubjectDisplayV1

    var key: CompletedWorkSubjectKeyV1 {
        get throws {
            try CompletedWorkSubjectKeyV1(
                workspaceID: workspaceID,
                family: snapshotFamily,
                subjectID: reportID,
                subjectRevision: chainPosition
            )
        }
    }

    var eligibility: CompletedWorkSubjectEligibilityV1 {
        isTip ? .eligible : .superseded
    }
}

enum CompletedWorkSubjectResolutionV1: Hashable, Sendable {
    case resolved(CompletedWorkSubjectProofV1)
    case unavailable(CompletedWorkSubjectUnavailableReasonV1)

    var proof: CompletedWorkSubjectProofV1? {
        if case let .resolved(value) = self { return value }
        return nil
    }
}

/// One Work-root row. A row never substitutes another subject for its key.
struct CompletedWorkSubjectListingV1: Hashable, Identifiable, Sendable {
    let key: CompletedWorkSubjectKeyV1
    let display: CompletedWorkSubjectDisplayV1?
    let eligibility: CompletedWorkSubjectEligibilityV1
    let responseCount: Int

    var id: CompletedWorkSubjectKeyV1 { key }
}

/// The completed-work detail. `proof` is nil when the subject is unavailable.
struct CompletedWorkSubjectDetailV1: Hashable, Sendable {
    let key: CompletedWorkSubjectKeyV1
    let proof: CompletedWorkSubjectProofV1?
    let eligibility: CompletedWorkSubjectEligibilityV1
    let responseCount: Int
}

/// Closed result of one Record or Try again action. Only `.saved` carries a
/// receipt; `.uncertain` means a canonical write may be durable and the same
/// prepared operation must be retried rather than replaced. `.notRecorded`
/// means the writer rejected the response with no durable receipt; the same
/// prepared operation can be tried again.
enum CompletedWorkResponseOutcomeV1: Equatable, Sendable {
    case saved(SignoffEnrollmentReceiptV1)
    case stale
    case unavailable
    case accessDenied
    case uncertain
    case notRecorded
}

extension SignoffHistoryRouteV1 {
    /// The Reports-root read target for one response. Like other report
    /// targets, its safe fallback is the Reports root rather than Today.
    var reportsTarget: NavigationTargetV1 {
        get throws {
            try NavigationTargetV1(
                workspaceID: workspaceID,
                destination: .signoffHistory,
                stableEntityID: signoffID,
                requestedMode: .read,
                fallback: try NavigationFallbackV1(root: .reports, destination: .reports)
            )
        }
    }
}

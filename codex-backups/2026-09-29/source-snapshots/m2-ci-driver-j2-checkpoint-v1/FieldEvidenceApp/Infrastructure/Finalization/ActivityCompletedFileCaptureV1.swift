import Foundation

enum ActivityCompletionCaptureFailureV1: Error, Equatable, Sendable {
    case sourceUnavailable
    case staleSource
    case invalidHistory
    case selectedProfileUnavailable
}

/// Code-backed workflow definitions validated against the exact recorded
/// package, retaining original and destination identities across a Fork.
enum ActivityCompletionWorkflowSourceV1: Equatable, Sendable {
    case installation(source: InstallationWorkflowDefinitionReleaseV1,
                      target: InstallationWorkflowDefinitionReleaseV1)
    case punchReview(source: PunchReviewWorkflowDefinitionReleaseV1,
                     target: PunchReviewWorkflowDefinitionReleaseV1)
}

/// An ephemeral read result from the actual writer's adapter. Its process-local
/// lease must never become part of the completed file or a restart identity.
struct ActivityCompletionSourceFrameV1: Equatable, Sendable {
    let expectedRevision: WorkspaceExpectedRevisionV1
    let predecessor: ActivitySessionEnvelopeV2
    let transitions: [ActivityStateTransitionV2]
    let installationBasisHistory: [InstallationBasisSnapshotV1]
    let taskHistory: [InstallationTaskResultV1]
    let asBuiltHistory: [InstallationAsBuiltSnapshotV1]
    let punchBasisHistory: [PunchReviewBasisSnapshotV1]
    let shopProfileHistory: [ShopReportProfileV1]
    let packageRelease: InspectionPackageReleaseV1
    let workflowSource: ActivityCompletionWorkflowSourceV1

    var shopProfile: ShopReportProfileV1 {
        get throws {
            guard let value = shopProfileHistory.last else {
                throw ActivityCompletionCaptureFailureV1.selectedProfileUnavailable
            }
            return value
        }
    }
}

/// Read-only preparation within the existing writer/generation boundary. A
/// source frame is not a completed file or permission to publish one: package,
/// selected supplemental facts, retained media and the immutable report release
/// must also be captured and revalidated before the combined writer operation.
@MainActor
enum ActivityCompletedFileCaptureV1 {
    static func readSource(
        writer: WorkspaceWriterV1,
        workspaceID: WorkspaceID,
        activityID: UUID,
        profile: ShopReportProfileReferenceV1
    ) throws -> ActivityCompletionSourceFrameV1 {
        try writer.readActivityCompletionSource(
            workspaceID: workspaceID, activityID: activityID, profile: profile
        )
    }

    static func makeActivityCapture(
        from frame: ActivityCompletionSourceFrameV1,
        completionTransition: ActivityStateTransitionV2,
        capturedAt: Date,
        generatedAt: Date
    ) throws -> ActivityCompletionCaptureV1 {
        let (revision, overflow) = frame.predecessor.revision.addingReportingOverflow(1)
        guard !overflow else { throw WorkspaceMutationFailureV1.revisionOverflow }
        let value = ActivityCompletionCaptureV1(
            version: ActivityCompletionCaptureV1.currentVersion,
            source: try MutationPortableExpectedRevisionV1(frame.expectedRevision),
            predecessor: frame.predecessor,
            transitionHistory: frame.transitions,
            completionTransition: completionTransition,
            resultingActivityRevision: revision,
            capturedAt: capturedAt,
            generatedAt: generatedAt
        )
        try value.validateIntrinsic()
        return value
    }

    /// Invoke after any asynchronous immutable-byte work. Never refresh the
    /// preview's revision or silently adopt a newer profile on a stale attempt.
    static func validateSourceStillCurrent(
        _ frame: ActivityCompletionSourceFrameV1,
        writer: WorkspaceWriterV1
    ) throws {
        let current = try writer.currentRevision()
        guard WorkspaceExpectedRevisionV1(snapshot: current) == frame.expectedRevision else {
            throw ActivityCompletionCaptureFailureV1.staleSource
        }
        let profile = try frame.shopProfile.reference
        let refreshed = try readSource(
            writer: writer,
            workspaceID: frame.predecessor.workspaceID,
            activityID: frame.predecessor.activityID,
            profile: profile
        )
        guard refreshed == frame else { throw ActivityCompletionCaptureFailureV1.staleSource }
    }
}

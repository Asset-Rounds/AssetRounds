import Foundation

enum ScheduleWorkStartRuleV1 {
    static func validate(_ event: OccurrenceHistoryEventV1, predecessor: OccurrenceHistoryEventV1) throws {
        try event.validate(predecessor: predecessor)
        guard event.action == .start, event.workInstance != nil else { throw ScheduleFailureV1.duplicateWorkLink }
    }
}

struct WorkRuleSubmission: Equatable, Sendable {
    let performedLocalDate: String
    let description: String
    let note: String?
    let completedAt: Date
    let mutationID: UUID
    let evidencePurposeKeys: [String]
}

struct WorkRulePlan: Equatable, Sendable {
    let recordAfter: WorkflowRecordPayloadV1
    let issueAfter: IssuePayloadV1
}

enum WorkRuleError: Error, Equatable {
    case invalidDraft
    case invalidIssue
    case invalidParent
    case invalidDate
    case invalidDescription
    case invalidNote
    case invalidEvidence
    case invalidCompletion
}

enum WorkRule {
    private static let pdfTemplateID = "field.evidence.pdf.worklight.v1"
    private static let validRecheckOutcomes: Set<String> = [
        "resolved",
        "issue_still_visible",
        "original_resolved_different_issue",
        "could_not_verify",
    ]

    static func makePlan(
        draft: WorkflowRecordPayloadV1,
        issue: IssuePayloadV1,
        parent: WorkflowRecordPayloadV1,
        submission: WorkRuleSubmission
    ) throws -> WorkRulePlan {
        guard validDraft(draft, issue: issue, parent: parent) else {
            throw WorkRuleError.invalidDraft
        }
        guard validOpenIssue(issue, draft: draft) else {
            throw WorkRuleError.invalidIssue
        }
        guard validSubstantiveParent(parent, issue: issue, draft: draft) else {
            throw WorkRuleError.invalidParent
        }
        guard validLocalDate(submission.performedLocalDate) else {
            throw WorkRuleError.invalidDate
        }

        let normalizedDescription = submission.description
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDescription.isEmpty,
              normalizedDescription.count <= 160,
              normalizedDescription == submission.description else {
            throw WorkRuleError.invalidDescription
        }

        let normalizedNote: String?
        if let note = submission.note {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  trimmed.count <= 1_000,
                  trimmed == note else {
                throw WorkRuleError.invalidNote
            }
            normalizedNote = trimmed
        } else {
            normalizedNote = nil
        }

        guard submission.evidencePurposeKeys.count <= 1,
              submission.evidencePurposeKeys.allSatisfy({ $0 == "work_context" }) else {
            throw WorkRuleError.invalidEvidence
        }
        guard submission.completedAt >= draft.startedAt,
              submission.completedAt >= issue.updatedAt else {
            throw WorkRuleError.invalidCompletion
        }

        let recordAfter = WorkflowRecordPayloadV1(
            id: draft.id,
            schemaVersion: 1,
            assetID: draft.assetID,
            packetID: nil,
            issueID: issue.id,
            parentRecordID: parent.id,
            recordRevisionRootID: draft.id,
            revisesRecordID: nil,
            evidenceSourceRecordID: nil,
            revisionKind: WorkflowRevisionKind.original.rawValue,
            stage: WorkflowStage.work.rawValue,
            state: WorkflowState.completed.rawValue,
            draftStepKey: nil,
            startedAt: draft.startedAt,
            completedAt: submission.completedAt,
            observedAtUTC: nil,
            timeZoneID: nil,
            utcOffsetMinutes: nil,
            localDate: nil,
            localTime: nil,
            afterDarkAcknowledgementKey: nil,
            afterDarkAcknowledgementCopy: nil,
            afterDarkAcknowledgementVersion: nil,
            afterDarkAcknowledgementAccepted: nil,
            safePositionAcknowledgementKey: nil,
            safePositionAcknowledgementCopy: nil,
            safePositionAcknowledgementVersion: nil,
            safePositionAcknowledgementAccepted: nil,
            packID: draft.packID,
            packSchemaVersion: draft.packSchemaVersion,
            packContentVersion: draft.packContentVersion,
            pdfTemplateID: pdfTemplateID,
            pdfTemplateVersion: 1,
            outcomeKey: "work_recorded",
            couldNotVerifyKey: nil,
            couldNotVerifyDisplaySnapshot: nil,
            couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: submission.performedLocalDate,
            workDescription: normalizedDescription,
            note: normalizedNote,
            finalizationMutationID: submission.mutationID
        )
        let issueAfter = IssuePayloadV1(
            id: issue.id,
            schemaVersion: 1,
            assetID: issue.assetID,
            openedByRecordID: issue.openedByRecordID,
            labelKey: issue.labelKey,
            labelDisplaySnapshot: issue.labelDisplaySnapshot,
            status: IssueStatus.recheckDue.rawValue,
            resolvedByRecordID: nil,
            createdAt: issue.createdAt,
            updatedAt: submission.completedAt
        )
        return WorkRulePlan(recordAfter: recordAfter, issueAfter: issueAfter)
    }

    private static func validDraft(
        _ draft: WorkflowRecordPayloadV1,
        issue: IssuePayloadV1,
        parent: WorkflowRecordPayloadV1
    ) -> Bool {
        draft.schemaVersion == 1
            && draft.assetID == issue.assetID
            && draft.packetID == nil
            && draft.issueID == issue.id
            && draft.parentRecordID == parent.id
            && draft.recordRevisionRootID == draft.id
            && draft.revisesRecordID == nil
            && draft.evidenceSourceRecordID == nil
            && draft.revisionKind == WorkflowRevisionKind.original.rawValue
            && draft.stage == WorkflowStage.work.rawValue
            && draft.state == WorkflowState.draft.rawValue
            && draft.draftStepKey == nil
            && draft.completedAt == nil
            && draft.observedAtUTC == nil
            && draft.timeZoneID == nil
            && draft.utcOffsetMinutes == nil
            && draft.localDate == nil
            && draft.localTime == nil
            && draft.afterDarkAcknowledgementKey == nil
            && draft.afterDarkAcknowledgementCopy == nil
            && draft.afterDarkAcknowledgementVersion == nil
            && draft.afterDarkAcknowledgementAccepted == nil
            && draft.safePositionAcknowledgementKey == nil
            && draft.safePositionAcknowledgementCopy == nil
            && draft.safePositionAcknowledgementVersion == nil
            && draft.safePositionAcknowledgementAccepted == nil
            && !draft.packID.isEmpty
            && draft.packSchemaVersion == 1
            && draft.packContentVersion > 0
            && draft.packID == parent.packID
            && draft.packSchemaVersion == parent.packSchemaVersion
            && draft.packContentVersion == parent.packContentVersion
            && draft.pdfTemplateID == pdfTemplateID
            && draft.pdfTemplateVersion == 1
            && draft.outcomeKey == nil
            && draft.couldNotVerifyKey == nil
            && draft.couldNotVerifyDisplaySnapshot == nil
            && draft.couldNotVerifyRegistryVersion == nil
            && draft.workPerformedLocalDate == nil
            && draft.workDescription == nil
            && draft.note == nil
            && draft.finalizationMutationID == nil
            && draft.startedAt >= issue.updatedAt
            && parent.completedAt.map({ draft.startedAt >= $0 }) == true
    }

    private static func validOpenIssue(
        _ issue: IssuePayloadV1,
        draft: WorkflowRecordPayloadV1
    ) -> Bool {
        issue.schemaVersion == 1
            && issue.assetID == draft.assetID
            && !issue.labelKey.isEmpty
            && !issue.labelDisplaySnapshot.isEmpty
            && issue.status == IssueStatus.open.rawValue
            && issue.resolvedByRecordID == nil
            && issue.updatedAt >= issue.createdAt
    }

    private static func validSubstantiveParent(
        _ parent: WorkflowRecordPayloadV1,
        issue: IssuePayloadV1,
        draft: WorkflowRecordPayloadV1
    ) -> Bool {
        guard parent.schemaVersion == 1,
              parent.id == draft.parentRecordID,
              parent.assetID == draft.assetID,
              parent.issueID == issue.id,
              parent.recordRevisionRootID == parent.id,
              parent.revisesRecordID == nil,
              parent.evidenceSourceRecordID == nil,
              parent.revisionKind == WorkflowRevisionKind.original.rawValue,
              parent.state == WorkflowState.completed.rawValue,
              parent.draftStepKey == nil,
              parent.completedAt != nil,
              parent.finalizationMutationID != nil else {
            return false
        }
        switch parent.stage {
        case WorkflowStage.check.rawValue:
            return parent.parentRecordID == nil
                && parent.outcomeKey == "visible_issue"
        case WorkflowStage.work.rawValue:
            return parent.outcomeKey == "work_recorded"
                && parent.workPerformedLocalDate != nil
                && parent.workDescription != nil
        case WorkflowStage.recheck.rawValue:
            return validRecheckOutcomes.contains(parent.outcomeKey ?? "")
        default:
            return false
        }
    }

    private static func validLocalDate(_ value: String) -> Bool {
        guard value.range(
            of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#,
            options: .regularExpression
        ) != nil else {
            return false
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }
}

// MARK: - C23 round-session binding gate

extension WorkRule {
    /// Work completion may consume a reference only when it names the exact
    /// round-session revision. This is a validation seam, not another source
    /// of release state; the durable binding is appended by the canonical
    /// field-reference writer.
    static func validateFieldReferenceBinding(
        draft: WorkflowRecordPayloadV1,
        binding: FieldReferenceBindingV1,
        release: FieldReferenceReleaseV1,
        readiness: FieldReferenceOfflineReadinessV1,
        subjectRevision: UInt64
    ) throws -> WorkSessionFieldReferenceProjectionV1 {
        guard draft.state == WorkflowState.draft.rawValue,
              binding.subjectKind == .roundSession,
              binding.subjectID == draft.id,
              binding.subjectRevision == subjectRevision,
              binding.subjectState == .active else {
            throw WorkRuleError.invalidDraft
        }
        let projection = try WorkSessionFieldReferenceProjectionV1(
            binding: binding, release: release, readiness: readiness
        )
        try projection.validate(
            expectedWorkspaceID: release.workspaceID,
            expectedSubjectKind: .roundSession,
            expectedSubjectID: draft.id,
            expectedSubjectRevision: subjectRevision,
            expectedSubjectState: .active
        )
        return projection
    }

    /// Source-compatible C23 overload. Existing work-rule callers continue
    /// to use the original plan path; this overload proves the immutable
    /// reference tuple before delegating to that same plan builder.
    static func makePlan(
        draft: WorkflowRecordPayloadV1,
        issue: IssuePayloadV1,
        parent: WorkflowRecordPayloadV1,
        submission: WorkRuleSubmission,
        fieldReferenceBinding: FieldReferenceBindingV1,
        fieldReferenceRelease: FieldReferenceReleaseV1,
        fieldReferenceReadiness: FieldReferenceOfflineReadinessV1,
        fieldReferenceSubjectRevision: UInt64
    ) throws -> WorkRulePlan {
        _ = try validateFieldReferenceBinding(
            draft: draft,
            binding: fieldReferenceBinding,
            release: fieldReferenceRelease,
            readiness: fieldReferenceReadiness,
            subjectRevision: fieldReferenceSubjectRevision
        )
        return try makePlan(
            draft: draft, issue: issue, parent: parent, submission: submission
        )
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_Workflow_WorkRule {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_Workflow_WorkRule_swift {
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

enum C30EvidenceContextWorkRuleV1 {
    static let pairedComparisonsRequireExplicitBasis = true
    static let mismatchReasonsAreOrdered = true
    static let pairMayClaimCompliance = false

    static func validate(_ value: PairedObservationLinkV1) throws {
        try value.validateIntrinsic()
        guard pairedComparisonsRequireExplicitBasis, mismatchReasonsAreOrdered,
              !pairMayClaimCompliance else { throw EvidenceContextFailureV1.invalidValue }
    }
}

enum C31LightingWorkRuleBoundaryV1 {
    static let observedFactsRequireExplicitBasis = true
    static let safetyStopsRemainBlocking = true
    static let claimsRequireRecordedReferences = true

    static func validate(
        records: [V31BackupLightingRecordV1],
        workspaceID: WorkspaceID
    ) throws {
        try C31LightingWorkflowBoundaryV1.validate(
            records: records,
            workspaceID: workspaceID
        )
        guard observedFactsRequireExplicitBasis,
              safetyStopsRemainBlocking,
              claimsRequireRecordedReferences else {
            throw LightingContractFailureV1.invalidValue
        }
    }
}

import Foundation

struct DifferentIssueOutcomeRuleInput: Equatable, Sendable {
    let draft: WorkflowRecordPayloadV1
    let parent: WorkflowRecordPayloadV1
    let originalIssue: IssuePayloadV1
    let outcomeKey: String
    let newIssueID: UUID
    let newIssueLabelKey: String
    let newIssueLabelDisplaySnapshot: String
    let note: String?
    let completedAt: Date
    let mutationID: UUID
    let packetID: UUID
}

struct DifferentIssueOutcomeRulePlan: Equatable, Sendable {
    let recordAfter: WorkflowRecordPayloadV1
    let originalIssueBefore: IssuePayloadV1
    let originalIssueAfter: IssuePayloadV1
    let newIssue: IssuePayloadV1
}

enum DifferentIssueOutcomeRuleError: Error, Equatable {
    case invalidDraft
    case invalidParent
    case invalidOriginalIssue
    case invalidOutcome
    case invalidNewIssue
    case invalidNote
    case invalidCompletion
}

enum DifferentIssueOutcomeRule {
    private static let packID = "field.evidence.illuminated_sign.v1"
    private static let packSchemaVersion = 1
    private static let packContentVersion = 1
    private static let pdfTemplateID = "field.evidence.pdf.worklight.v1"
    private static let acknowledgementVersion = "preflight.ack.en-US.v1"
    private static let afterDarkCopy =
        "It is dark enough to observe the sign's visible illumination."
    private static let safePositionCopy =
        "I am in a safe, authorized position to take these photos."
    private static let issueLabels: [String: String] = [
        "dark_section": "Section appears dark",
        "dim_or_uneven": "Illumination appears dim or uneven",
        "flicker_or_intermittent": "Flicker or intermittent light",
        "color_mismatch": "Visible color mismatch",
        "physical_damage": "Visible physical damage",
        "other_visible_condition": "Other visible condition",
    ]
    private static let couldNotVerifyDisplays: [String: String] = [
        "conditions_changed": "Conditions changed",
        "access_lost": "I lost safe access",
        "unsafe_to_continue": "It became unsafe to continue",
        "required_view_obstructed": "Required view is blocked",
        "capture_unavailable": "Camera or photo capture is unavailable",
        "other": "Another reason",
    ]

    static func makePlan(
        _ input: DifferentIssueOutcomeRuleInput
    ) throws -> DifferentIssueOutcomeRulePlan {
        guard validDraft(input.draft) else {
            throw DifferentIssueOutcomeRuleError.invalidDraft
        }
        guard validParent(input.parent, draft: input.draft) else {
            throw DifferentIssueOutcomeRuleError.invalidParent
        }
        guard validOriginalIssue(
            input.originalIssue,
            draft: input.draft,
            parent: input.parent
        ) else {
            throw DifferentIssueOutcomeRuleError.invalidOriginalIssue
        }
        guard input.outcomeKey == "original_resolved_different_issue" else {
            throw DifferentIssueOutcomeRuleError.invalidOutcome
        }
        guard issueLabels[input.newIssueLabelKey]
                == input.newIssueLabelDisplaySnapshot,
              Set([
                input.draft.assetID,
                input.draft.id,
                input.parent.id,
                input.originalIssue.openedByRecordID,
                input.originalIssue.id,
                input.newIssueID,
                input.mutationID,
                input.packetID,
              ]).count == 8 else {
            throw DifferentIssueOutcomeRuleError.invalidNewIssue
        }

        let normalizedNote: String?
        if let note = input.note {
            guard validText(note, maximum: 1_000) else {
                throw DifferentIssueOutcomeRuleError.invalidNote
            }
            normalizedNote = note
        } else {
            normalizedNote = nil
        }

        guard input.completedAt >= input.draft.startedAt,
              input.completedAt >= input.originalIssue.updatedAt,
              input.parent.completedAt.map({ input.completedAt >= $0 }) == true else {
            throw DifferentIssueOutcomeRuleError.invalidCompletion
        }

        let recordAfter = WorkflowRecordPayloadV1(
            id: input.draft.id,
            schemaVersion: 1,
            assetID: input.draft.assetID,
            packetID: input.packetID,
            issueID: input.originalIssue.id,
            parentRecordID: input.parent.id,
            recordRevisionRootID: input.draft.id,
            revisesRecordID: nil,
            evidenceSourceRecordID: nil,
            revisionKind: WorkflowRevisionKind.original.rawValue,
            stage: WorkflowStage.recheck.rawValue,
            state: WorkflowState.completed.rawValue,
            draftStepKey: nil,
            startedAt: input.draft.startedAt,
            completedAt: input.completedAt,
            observedAtUTC: input.draft.observedAtUTC,
            timeZoneID: input.draft.timeZoneID,
            utcOffsetMinutes: input.draft.utcOffsetMinutes,
            localDate: input.draft.localDate,
            localTime: input.draft.localTime,
            afterDarkAcknowledgementKey: input.draft.afterDarkAcknowledgementKey,
            afterDarkAcknowledgementCopy: input.draft.afterDarkAcknowledgementCopy,
            afterDarkAcknowledgementVersion: input.draft.afterDarkAcknowledgementVersion,
            afterDarkAcknowledgementAccepted: input.draft.afterDarkAcknowledgementAccepted,
            safePositionAcknowledgementKey: input.draft.safePositionAcknowledgementKey,
            safePositionAcknowledgementCopy: input.draft.safePositionAcknowledgementCopy,
            safePositionAcknowledgementVersion: input.draft.safePositionAcknowledgementVersion,
            safePositionAcknowledgementAccepted: input.draft.safePositionAcknowledgementAccepted,
            packID: input.draft.packID,
            packSchemaVersion: input.draft.packSchemaVersion,
            packContentVersion: input.draft.packContentVersion,
            pdfTemplateID: pdfTemplateID,
            pdfTemplateVersion: 1,
            outcomeKey: input.outcomeKey,
            couldNotVerifyKey: nil,
            couldNotVerifyDisplaySnapshot: nil,
            couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: nil,
            workDescription: nil,
            note: normalizedNote,
            finalizationMutationID: input.mutationID
        )
        let originalIssueAfter = IssuePayloadV1(
            id: input.originalIssue.id,
            schemaVersion: 1,
            assetID: input.originalIssue.assetID,
            openedByRecordID: input.originalIssue.openedByRecordID,
            labelKey: input.originalIssue.labelKey,
            labelDisplaySnapshot: input.originalIssue.labelDisplaySnapshot,
            status: IssueStatus.resolved.rawValue,
            resolvedByRecordID: input.draft.id,
            createdAt: input.originalIssue.createdAt,
            updatedAt: input.completedAt
        )
        let newIssue = IssuePayloadV1(
            id: input.newIssueID,
            schemaVersion: 1,
            assetID: input.draft.assetID,
            openedByRecordID: input.draft.id,
            labelKey: input.newIssueLabelKey,
            labelDisplaySnapshot: input.newIssueLabelDisplaySnapshot,
            status: IssueStatus.open.rawValue,
            resolvedByRecordID: nil,
            createdAt: input.completedAt,
            updatedAt: input.completedAt
        )
        return DifferentIssueOutcomeRulePlan(
            recordAfter: recordAfter,
            originalIssueBefore: input.originalIssue,
            originalIssueAfter: originalIssueAfter,
            newIssue: newIssue
        )
    }

    private static func validDraft(_ draft: WorkflowRecordPayloadV1) -> Bool {
        draft.schemaVersion == 1
            && draft.packetID == nil
            && draft.issueID != nil
            && draft.parentRecordID != nil
            && draft.recordRevisionRootID == draft.id
            && draft.revisesRecordID == nil
            && draft.evidenceSourceRecordID == nil
            && draft.revisionKind == WorkflowRevisionKind.original.rawValue
            && draft.stage == WorkflowStage.recheck.rawValue
            && draft.state == WorkflowState.draft.rawValue
            && draft.draftStepKey == WorkflowDraftStep.outcome.rawValue
            && draft.completedAt == nil
            && draft.observedAtUTC == draft.startedAt
            && validTimeContext(draft)
            && validAcknowledgements(draft)
            && draft.packID == packID
            && draft.packSchemaVersion == packSchemaVersion
            && draft.packContentVersion == packContentVersion
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
    }

    private static func validParent(
        _ parent: WorkflowRecordPayloadV1,
        draft: WorkflowRecordPayloadV1
    ) -> Bool {
        guard parent.schemaVersion == 1,
              parent.id == draft.parentRecordID,
              parent.assetID == draft.assetID,
              parent.issueID == draft.issueID,
              parent.recordRevisionRootID == parent.id,
              parent.revisesRecordID == nil,
              parent.evidenceSourceRecordID == nil,
              parent.revisionKind == WorkflowRevisionKind.original.rawValue,
              parent.state == WorkflowState.completed.rawValue,
              parent.draftStepKey == nil,
              parent.completedAt.map({ $0 >= parent.startedAt }) == true,
              parent.finalizationMutationID != nil,
              parent.packID == draft.packID,
              parent.packSchemaVersion == draft.packSchemaVersion,
              parent.packContentVersion == draft.packContentVersion,
              parent.pdfTemplateID == pdfTemplateID,
              parent.pdfTemplateVersion == 1,
              parent.completedAt.map({ draft.startedAt >= $0 }) == true else {
            return false
        }
        if parent.stage == WorkflowStage.work.rawValue {
            return parent.packetID == nil
                && parent.outcomeKey == "work_recorded"
                && parent.observedAtUTC == nil
                && parent.timeZoneID == nil
                && parent.utcOffsetMinutes == nil
                && parent.localDate == nil
                && parent.localTime == nil
                && noAcknowledgements(parent)
                && parent.couldNotVerifyKey == nil
                && parent.couldNotVerifyDisplaySnapshot == nil
                && parent.couldNotVerifyRegistryVersion == nil
                && parent.workPerformedLocalDate.map(validLocalDate) == true
                && parent.workDescription.map({ validText($0, maximum: 160) }) == true
                && (parent.note.map({ validText($0, maximum: 1_000) }) ?? true)
        }
        if parent.stage == WorkflowStage.recheck.rawValue {
            return parent.packetID != nil
                && parent.outcomeKey == "could_not_verify"
                && validTimeContext(parent)
                && validAcknowledgements(parent)
                && parent.couldNotVerifyRegistryVersion == "cnv.reason.en-US.v1"
                && parent.couldNotVerifyKey.flatMap({ couldNotVerifyDisplays[$0] })
                    == parent.couldNotVerifyDisplaySnapshot
                && parent.workPerformedLocalDate == nil
                && parent.workDescription == nil
                && (parent.note.map({ validText($0, maximum: 1_000) }) ?? true)
        }
        return false
    }

    private static func validOriginalIssue(
        _ issue: IssuePayloadV1,
        draft: WorkflowRecordPayloadV1,
        parent: WorkflowRecordPayloadV1
    ) -> Bool {
        issue.schemaVersion == 1
            && draft.issueID == issue.id
            && issue.assetID == draft.assetID
            && issueLabels[issue.labelKey] == issue.labelDisplaySnapshot
            && issue.status == IssueStatus.recheckDue.rawValue
            && issue.resolvedByRecordID == nil
            && issue.updatedAt >= issue.createdAt
            && issue.updatedAt == parent.completedAt
    }

    private static func validTimeContext(_ record: WorkflowRecordPayloadV1) -> Bool {
        record.observedAtUTC == record.startedAt
            && record.timeZoneID.map(validKey) == true
            && record.utcOffsetMinutes.map({ ((-14 * 60)...(14 * 60)).contains($0) }) == true
            && record.localDate.map(validLocalDate) == true
            && record.localTime.map(validLocalTime) == true
    }

    private static func validAcknowledgements(_ record: WorkflowRecordPayloadV1) -> Bool {
        record.afterDarkAcknowledgementKey == "after_dark"
            && record.afterDarkAcknowledgementCopy == afterDarkCopy
            && record.afterDarkAcknowledgementVersion == acknowledgementVersion
            && record.afterDarkAcknowledgementAccepted == true
            && record.safePositionAcknowledgementKey == "safe_authorized_position"
            && record.safePositionAcknowledgementCopy == safePositionCopy
            && record.safePositionAcknowledgementVersion == acknowledgementVersion
            && record.safePositionAcknowledgementAccepted == true
    }

    private static func noAcknowledgements(_ record: WorkflowRecordPayloadV1) -> Bool {
        record.afterDarkAcknowledgementKey == nil
            && record.afterDarkAcknowledgementCopy == nil
            && record.afterDarkAcknowledgementVersion == nil
            && record.afterDarkAcknowledgementAccepted == nil
            && record.safePositionAcknowledgementKey == nil
            && record.safePositionAcknowledgementCopy == nil
            && record.safePositionAcknowledgementVersion == nil
            && record.safePositionAcknowledgementAccepted == nil
    }

    private static func validText(_ value: String, maximum: Int) -> Bool {
        !value.isEmpty
            && value.count <= maximum
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func validKey(_ value: String) -> Bool {
        !value.isEmpty
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static func validLocalTime(_ value: String) -> Bool {
        value.range(
            of: #"^(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$"#,
            options: .regularExpression
        ) != nil
    }
}

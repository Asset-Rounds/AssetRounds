import Foundation

struct RecheckOutcomeRuleInput: Equatable, Sendable {
    let draft: WorkflowRecordPayloadV1
    let parent: WorkflowRecordPayloadV1
    let issue: IssuePayloadV1
    let outcomeKey: String
    let note: String?
    let completedAt: Date
    let mutationID: UUID
    let packetID: UUID
    let couldNotVerify: RecheckCouldNotVerifySelection?

    init(
        draft: WorkflowRecordPayloadV1,
        parent: WorkflowRecordPayloadV1,
        issue: IssuePayloadV1,
        outcomeKey: String,
        note: String?,
        completedAt: Date,
        mutationID: UUID,
        packetID: UUID,
        couldNotVerify: RecheckCouldNotVerifySelection? = nil
    ) {
        self.draft = draft
        self.parent = parent
        self.issue = issue
        self.outcomeKey = outcomeKey
        self.note = note
        self.completedAt = completedAt
        self.mutationID = mutationID
        self.packetID = packetID
        self.couldNotVerify = couldNotVerify
    }
}

struct RecheckCouldNotVerifySelection: Equatable, Sendable {
    let key: String
    let display: String
    let registryVersion: String
}

struct RecheckOutcomeRulePlan: Equatable, Sendable {
    let recordAfter: WorkflowRecordPayloadV1
    let issueBefore: IssuePayloadV1
    let issueAfter: IssuePayloadV1
}

enum RecheckOutcomeRuleError: Error, Equatable {
    case invalidDraft
    case invalidParent
    case invalidIssue
    case invalidOutcome
    case invalidNote
    case invalidCompletion
}

enum RecheckOutcomeRule {
    private static let pdfTemplateID = "field.evidence.pdf.worklight.v1"
    private static let couldNotVerifyDisplays: [String: String] = [
        "conditions_changed": "Conditions changed",
        "access_lost": "I lost safe access",
        "unsafe_to_continue": "It became unsafe to continue",
        "required_view_obstructed": "Required view is blocked",
        "capture_unavailable": "Camera or photo capture is unavailable",
        "other": "Another reason",
    ]

    static func makePlan(
        _ input: RecheckOutcomeRuleInput
    ) throws -> RecheckOutcomeRulePlan {
        guard validDraft(input.draft, outcomeKey: input.outcomeKey) else {
            throw RecheckOutcomeRuleError.invalidDraft
        }
        guard validParent(input.parent, draft: input.draft) else {
            throw RecheckOutcomeRuleError.invalidParent
        }
        guard validIssue(input.issue, draft: input.draft, parent: input.parent) else {
            throw RecheckOutcomeRuleError.invalidIssue
        }
        let isCouldNotVerify = input.outcomeKey == "could_not_verify"
        guard input.outcomeKey == "resolved"
                || input.outcomeKey == "issue_still_visible"
                || isCouldNotVerify else {
            throw RecheckOutcomeRuleError.invalidOutcome
        }
        if isCouldNotVerify {
            guard let selection = input.couldNotVerify,
                  selection.registryVersion == "cnv.reason.en-US.v1",
                  couldNotVerifyDisplays[selection.key] == selection.display else {
                throw RecheckOutcomeRuleError.invalidOutcome
            }
        } else if input.couldNotVerify != nil {
            throw RecheckOutcomeRuleError.invalidOutcome
        }

        let normalizedNote: String?
        if let note = input.note {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  trimmed.count <= 1_000,
                  trimmed == note else {
                throw RecheckOutcomeRuleError.invalidNote
            }
            normalizedNote = trimmed
        } else {
            normalizedNote = nil
        }

        guard input.completedAt >= input.draft.startedAt,
              input.completedAt >= input.issue.updatedAt,
              input.parent.completedAt.map({ input.completedAt >= $0 }) == true else {
            throw RecheckOutcomeRuleError.invalidCompletion
        }

        let recordAfter = WorkflowRecordPayloadV1(
            id: input.draft.id,
            schemaVersion: 1,
            assetID: input.draft.assetID,
            packetID: input.packetID,
            issueID: input.issue.id,
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
            couldNotVerifyKey: input.couldNotVerify?.key,
            couldNotVerifyDisplaySnapshot: input.couldNotVerify?.display,
            couldNotVerifyRegistryVersion: input.couldNotVerify?.registryVersion,
            workPerformedLocalDate: nil,
            workDescription: nil,
            note: normalizedNote,
            finalizationMutationID: input.mutationID
        )
        let issueAfter: IssuePayloadV1
        if isCouldNotVerify {
            issueAfter = input.issue
        } else {
            let resolves = input.outcomeKey == "resolved"
            issueAfter = IssuePayloadV1(
                id: input.issue.id,
                schemaVersion: 1,
                assetID: input.issue.assetID,
                openedByRecordID: input.issue.openedByRecordID,
                labelKey: input.issue.labelKey,
                labelDisplaySnapshot: input.issue.labelDisplaySnapshot,
                status: resolves ? IssueStatus.resolved.rawValue : IssueStatus.open.rawValue,
                resolvedByRecordID: resolves ? input.draft.id : nil,
                createdAt: input.issue.createdAt,
                updatedAt: input.completedAt
            )
        }
        return RecheckOutcomeRulePlan(
            recordAfter: recordAfter,
            issueBefore: input.issue,
            issueAfter: issueAfter
        )
    }

    private static func validDraft(
        _ draft: WorkflowRecordPayloadV1,
        outcomeKey: String
    ) -> Bool {
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
            && (outcomeKey == "could_not_verify"
                ? [
                    WorkflowDraftStep.wide.rawValue,
                    WorkflowDraftStep.close.rawValue,
                    WorkflowDraftStep.outcome.rawValue,
                  ].contains(draft.draftStepKey ?? "")
                : draft.draftStepKey == WorkflowDraftStep.outcome.rawValue)
            && draft.completedAt == nil
            && draft.observedAtUTC == draft.startedAt
            && validTimeContext(draft)
            && validAcknowledgements(draft)
            && !draft.packID.isEmpty
            && draft.packSchemaVersion == 1
            && draft.packContentVersion > 0
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
                && parent.couldNotVerifyDisplaySnapshot != nil
                && parent.couldNotVerifyKey.flatMap({ couldNotVerifyDisplays[$0] })
                    == parent.couldNotVerifyDisplaySnapshot
                && parent.workPerformedLocalDate == nil
                && parent.workDescription == nil
                && (parent.note.map({ validText($0, maximum: 1_000) }) ?? true)
        }
        return false
    }

    private static func validIssue(
        _ issue: IssuePayloadV1,
        draft: WorkflowRecordPayloadV1,
        parent: WorkflowRecordPayloadV1
    ) -> Bool {
        issue.schemaVersion == 1
            && draft.issueID == issue.id
            && issue.assetID == draft.assetID
            && !issue.labelKey.isEmpty
            && issue.labelKey == issue.labelKey.trimmingCharacters(in: .whitespacesAndNewlines)
            && !issue.labelDisplaySnapshot.isEmpty
            && issue.labelDisplaySnapshot
                == issue.labelDisplaySnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
            && issue.status == IssueStatus.recheckDue.rawValue
            && issue.resolvedByRecordID == nil
            && issue.updatedAt >= issue.createdAt
            && (parent.stage == WorkflowStage.work.rawValue
                ? issue.updatedAt == parent.completedAt
                : (parent.stage == WorkflowStage.recheck.rawValue
                    && parent.outcomeKey == "could_not_verify"
                    && parent.completedAt.map({ issue.updatedAt <= $0 }) == true))
    }

    private static func validTimeContext(_ record: WorkflowRecordPayloadV1) -> Bool {
        record.observedAtUTC != nil
            && record.timeZoneID.map(validKey) == true
            && record.utcOffsetMinutes.map({ ((-14 * 60)...(14 * 60)).contains($0) }) == true
            && record.localDate.map(validLocalDate) == true
            && record.localTime.map(validLocalTime) == true
    }

    private static func validAcknowledgements(_ record: WorkflowRecordPayloadV1) -> Bool {
        record.afterDarkAcknowledgementKey == "after_dark"
            && record.afterDarkAcknowledgementCopy.map({ !$0.isEmpty }) == true
            && record.afterDarkAcknowledgementVersion.map(validKey) == true
            && record.afterDarkAcknowledgementAccepted == true
            && record.safePositionAcknowledgementKey == "safe_authorized_position"
            && record.safePositionAcknowledgementCopy.map({ !$0.isEmpty }) == true
            && record.safePositionAcknowledgementVersion.map(validKey) == true
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

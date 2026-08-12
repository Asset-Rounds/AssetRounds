import Foundation
import SwiftData

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
    case saveFailed
}

@MainActor
final class CheckRunnerCoordinator {
    private static let pdfTemplateID = "field.evidence.pdf.worklight.v1"
    private static let pdfTemplateVersion = 1
    private static let recheckOutcomes: Set<String> = [
        "resolved",
        "issue_still_visible",
        "original_resolved_different_issue",
        "could_not_verify",
    ]

    private let modelContext: ModelContext
    private let signPack: SignPack

    init(modelContext: ModelContext, signPack: SignPack) {
        self.modelContext = modelContext
        self.signPack = signPack
    }

    func prepare(assetID: UUID) throws -> CheckRunnerPreparation {
        let draft = try existingDraft(assetID: assetID)
        let asset = try requiredAsset(id: assetID)
        let site = try requiredSite(id: asset.siteID)
        return CheckRunnerPreparation(
            confirmedTimeZoneID: site.timeZoneID,
            existingDraftID: draft?.id
        )
    }

    func existingDraft(assetID: UUID) throws -> WorkflowRecord? {
        let descriptor = FetchDescriptor<WorkflowRecord>(
            predicate: #Predicate { $0.assetID == assetID }
        )
        let drafts = try modelContext.fetch(descriptor).filter {
            $0.state == WorkflowState.draft.rawValue
        }
        guard drafts.count <= 1 else {
            throw CheckRunnerCoordinatorError.multipleActiveDrafts
        }
        return drafts.first
    }

    func beginCheck(
        assetID: UUID,
        timeZoneID: String?,
        isTimeZoneConfirmed: Bool,
        afterDarkAccepted: Bool,
        safePositionAccepted: Bool,
        observedAt: Date
    ) throws -> WorkflowRecord {
        try beginOrResumeDraft(
            BeginDraftSubmission(
                assetID: assetID,
                requestedStage: .check,
                issueID: nil,
                observedAtUTC: observedAt,
                confirmedTimeZoneID: isTimeZoneConfirmed ? timeZoneID : nil,
                afterDarkAccepted: afterDarkAccepted,
                safePositionAccepted: safePositionAccepted
            )
        )
    }

    func beginOrResumeDraft(
        assetID: UUID,
        requestedStage: WorkflowStage,
        issueID: UUID?
    ) throws -> WorkflowRecord {
        if let draft = try existingDraft(assetID: assetID) {
            return draft
        }

        let asset = try requiredAsset(id: assetID)
        let parentRecordID = try validatedParentRecordID(
            assetID: assetID,
            requestedStage: requestedStage,
            issueID: issueID
        )

        guard requestedStage == .work else {
            throw CheckRunnerCoordinatorError.acknowledgementsRequired
        }

        return try createDraft(
            asset: asset,
            requestedStage: requestedStage,
            issueID: issueID,
            parentRecordID: parentRecordID,
            timeContext: nil,
            acknowledgementSnapshots: nil,
            startedAt: Date()
        )
    }

    func beginOrResumeDraft(
        _ submission: BeginDraftSubmission
    ) throws -> WorkflowRecord {
        if let draft = try existingDraft(assetID: submission.assetID) {
            return draft
        }

        let asset = try requiredAsset(id: submission.assetID)
        let parentRecordID = try validatedParentRecordID(
            assetID: submission.assetID,
            requestedStage: submission.requestedStage,
            issueID: submission.issueID
        )

        switch submission.requestedStage {
        case .work:
            return try createDraft(
                asset: asset,
                requestedStage: .work,
                issueID: submission.issueID,
                parentRecordID: parentRecordID,
                timeContext: nil,
                acknowledgementSnapshots: nil,
                startedAt: submission.observedAtUTC ?? Date()
            )

        case .check, .recheck:
            guard submission.afterDarkAccepted,
                  submission.safePositionAccepted else {
                throw CheckRunnerCoordinatorError.acknowledgementsRequired
            }
            guard let observedAtUTC = submission.observedAtUTC else {
                throw CheckRunnerCoordinatorError.invalidLineage
            }

            let acknowledgementSnapshots = try acknowledgementSnapshots(for: asset)
            let timeZoneResolution = try resolvedTimeZone(
                asset: asset,
                proposedTimeZoneID: submission.confirmedTimeZoneID
            )
            let timeContext: FrozenTimeContext
            do {
                timeContext = try TimeContextRule.freeze(
                    observedAtUTC: observedAtUTC,
                    confirmedTimeZoneID: timeZoneResolution.timeZoneID
                )
            } catch TimeContextRuleError.invalidTimeZoneID {
                throw CheckRunnerCoordinatorError.invalidTimeZoneID
            }
            try persistConfirmedTimeZoneIfNeeded(
                timeZoneResolution,
                confirmedAt: observedAtUTC
            )

            return try createDraft(
                asset: asset,
                requestedStage: submission.requestedStage,
                issueID: submission.issueID,
                parentRecordID: parentRecordID,
                timeContext: timeContext,
                acknowledgementSnapshots: acknowledgementSnapshots,
                startedAt: observedAtUTC
            )
        }
    }

    private func requiredAsset(id: UUID) throws -> Asset {
        let descriptor = FetchDescriptor<Asset>(
            predicate: #Predicate { $0.id == id }
        )
        let assets = try modelContext.fetch(descriptor)
        guard assets.count == 1, let asset = assets.first else {
            throw CheckRunnerCoordinatorError.assetNotFound
        }
        return asset
    }

    private func requiredSite(id: UUID) throws -> Site {
        let descriptor = FetchDescriptor<Site>(
            predicate: #Predicate { $0.id == id }
        )
        let sites = try modelContext.fetch(descriptor)
        guard sites.count == 1, let site = sites.first else {
            throw CheckRunnerCoordinatorError.siteNotFound
        }
        return site
    }

    private func resolvedTimeZone(
        asset: Asset,
        proposedTimeZoneID: String?
    ) throws -> TimeZoneResolution {
        let site = try requiredSite(id: asset.siteID)

        if let storedTimeZoneID = site.timeZoneID {
            guard TimeZone.knownTimeZoneIdentifiers.contains(storedTimeZoneID),
                  TimeZone(identifier: storedTimeZoneID) != nil else {
                throw CheckRunnerCoordinatorError.invalidTimeZoneID
            }
            return TimeZoneResolution(
                site: site,
                timeZoneID: storedTimeZoneID,
                requiresSave: false
            )
        }

        guard let proposedTimeZoneID else {
            throw CheckRunnerCoordinatorError.timeZoneConfirmationRequired
        }
        let normalizedTimeZoneID = proposedTimeZoneID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard TimeZone.knownTimeZoneIdentifiers.contains(normalizedTimeZoneID),
              TimeZone(identifier: normalizedTimeZoneID) != nil else {
            throw CheckRunnerCoordinatorError.invalidTimeZoneID
        }

        return TimeZoneResolution(
            site: site,
            timeZoneID: normalizedTimeZoneID,
            requiresSave: true
        )
    }

    private func persistConfirmedTimeZoneIfNeeded(
        _ resolution: TimeZoneResolution,
        confirmedAt: Date
    ) throws {
        guard resolution.requiresSave else { return }

        resolution.site.timeZoneID = resolution.timeZoneID
        resolution.site.updatedAt = confirmedAt
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw CheckRunnerCoordinatorError.saveFailed
        }

        let siteID = resolution.site.id
        let descriptor = FetchDescriptor<Site>(
            predicate: #Predicate { $0.id == siteID }
        )
        guard let persistedSite = try? modelContext.fetch(descriptor),
              persistedSite.count == 1,
              persistedSite.first?.timeZoneID == resolution.timeZoneID else {
            throw CheckRunnerCoordinatorError.saveFailed
        }
    }

    private func validatedParentRecordID(
        assetID: UUID,
        requestedStage: WorkflowStage,
        issueID: UUID?
    ) throws -> UUID? {
        switch requestedStage {
        case .check:
            guard issueID == nil else {
                throw CheckRunnerCoordinatorError.issueNotAllowed
            }
            return nil

        case .work, .recheck:
            guard let issueID else {
                throw CheckRunnerCoordinatorError.issueRequired
            }
            let issue = try requiredIssue(id: issueID)
            guard issue.assetID == assetID else {
                throw CheckRunnerCoordinatorError.issueAssetMismatch
            }

            let requiredStatus: IssueStatus = requestedStage == .work
                ? .open
                : .recheckDue
            guard issue.status == requiredStatus.rawValue else {
                throw CheckRunnerCoordinatorError.issueStateMismatch
            }
            return try latestCompletedSubstantiveRecordID(
                assetID: assetID,
                issue: issue
            )
        }
    }

    private func requiredIssue(id: UUID) throws -> Issue {
        let descriptor = FetchDescriptor<Issue>(
            predicate: #Predicate { $0.id == id }
        )
        let issues = try modelContext.fetch(descriptor)
        guard issues.count == 1, let issue = issues.first else {
            throw CheckRunnerCoordinatorError.issueNotFound
        }
        return issue
    }

    private func latestCompletedSubstantiveRecordID(
        assetID: UUID,
        issue: Issue
    ) throws -> UUID {
        let descriptor = FetchDescriptor<WorkflowRecord>(
            predicate: #Predicate { $0.assetID == assetID }
        )
        let records = try modelContext.fetch(descriptor).filter {
            $0.state == WorkflowState.completed.rawValue
                && $0.revisionKind == WorkflowRevisionKind.original.rawValue
        }

        guard !records.isEmpty else {
            throw CheckRunnerCoordinatorError.parentRecordMissing
        }
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        guard recordsByID.count == records.count,
              let openingRecord = recordsByID[issue.openedByRecordID],
              openingRecord.completedAt != nil,
              openingRecord.finalizationMutationID != nil else {
            throw CheckRunnerCoordinatorError.invalidLineage
        }

        let opensOrdinaryIssue = openingRecord.parentRecordID == nil
            && openingRecord.stage == WorkflowStage.check.rawValue
            && openingRecord.outcomeKey == "visible_issue"
            && openingRecord.issueID == issue.id
        let opensDifferentIssue: Bool
        if let originalIssueID = openingRecord.issueID,
           originalIssueID != issue.id,
           openingRecord.stage == WorkflowStage.recheck.rawValue,
           openingRecord.outcomeKey == "original_resolved_different_issue" {
            let originalIssue = try requiredIssue(id: originalIssueID)
            guard originalIssue.assetID == assetID,
                  originalIssue.status == IssueStatus.resolved.rawValue,
                  originalIssue.resolvedByRecordID == openingRecord.id else {
                throw CheckRunnerCoordinatorError.invalidLineage
            }
            opensDifferentIssue = try ordinaryIssueChainTerminal(
                assetID: assetID,
                issue: originalIssue,
                records: records,
                recordsByID: recordsByID
            ).id == openingRecord.id
        } else {
            opensDifferentIssue = false
        }
        guard opensOrdinaryIssue || opensDifferentIssue else {
            throw CheckRunnerCoordinatorError.invalidLineage
        }

        if opensOrdinaryIssue {
            return try ordinaryIssueChainTerminal(
                assetID: assetID,
                issue: issue,
                records: records,
                recordsByID: recordsByID
            ).id
        }

        let issueRecords = records.filter { $0.issueID == issue.id }
        var visitedIssueRecords: Set<UUID> = []
        var current = openingRecord
        while true {
            let children = issueRecords.filter { $0.parentRecordID == current.id }
            guard children.count <= 1 else {
                throw CheckRunnerCoordinatorError.invalidLineage
            }
            guard let child = children.first else {
                break
            }
            guard visitedIssueRecords.insert(child.id).inserted,
                  child.issueID == issue.id,
                  child.assetID == assetID,
                  child.completedAt != nil,
                  child.finalizationMutationID != nil,
                  (child.stage == WorkflowStage.work.rawValue
                    && child.outcomeKey == "work_recorded")
                    || (child.stage == WorkflowStage.recheck.rawValue
                    && Self.recheckOutcomes.contains(child.outcomeKey ?? "")) else {
                throw CheckRunnerCoordinatorError.invalidLineage
            }
            current = child
        }

        guard visitedIssueRecords.count == issueRecords.count else {
            throw CheckRunnerCoordinatorError.invalidLineage
        }
        return current.id
    }

    private func ordinaryIssueChainTerminal(
        assetID: UUID,
        issue: Issue,
        records: [WorkflowRecord],
        recordsByID: [UUID: WorkflowRecord]
    ) throws -> WorkflowRecord {
        guard let openingRecord = recordsByID[issue.openedByRecordID],
              openingRecord.assetID == assetID,
              openingRecord.issueID == issue.id,
              openingRecord.parentRecordID == nil,
              openingRecord.stage == WorkflowStage.check.rawValue,
              openingRecord.outcomeKey == "visible_issue",
              openingRecord.completedAt != nil,
              openingRecord.finalizationMutationID != nil else {
            throw CheckRunnerCoordinatorError.invalidLineage
        }

        let issueRecords = records.filter { $0.issueID == issue.id }
        var visited: Set<UUID> = [openingRecord.id]
        var current = openingRecord
        while true {
            let children = issueRecords.filter { $0.parentRecordID == current.id }
            guard children.count <= 1 else {
                throw CheckRunnerCoordinatorError.invalidLineage
            }
            guard let child = children.first else { break }
            guard visited.insert(child.id).inserted,
                  child.assetID == assetID,
                  child.completedAt != nil,
                  child.finalizationMutationID != nil,
                  (child.stage == WorkflowStage.work.rawValue
                    && child.outcomeKey == "work_recorded")
                    || (child.stage == WorkflowStage.recheck.rawValue
                    && Self.recheckOutcomes.contains(child.outcomeKey ?? "")) else {
                throw CheckRunnerCoordinatorError.invalidLineage
            }
            current = child
        }

        guard visited.count == issueRecords.count else {
            throw CheckRunnerCoordinatorError.invalidLineage
        }
        return current
    }

    private func acknowledgementSnapshots(for asset: Asset) throws -> (
        afterDark: SignPack.Acknowledgement,
        safePosition: SignPack.Acknowledgement
    ) {
        guard signPack.packID == asset.packID,
              signPack.schemaVersion == asset.packSchemaVersion,
              signPack.contentVersion == asset.packContentVersion,
              signPack.acknowledgements.count == 2,
              signPack.acknowledgements[0].key == "after_dark",
              signPack.acknowledgements[1].key == "safe_authorized_position" else {
            throw CheckRunnerCoordinatorError.invalidLineage
        }
        return (
            afterDark: signPack.acknowledgements[0],
            safePosition: signPack.acknowledgements[1]
        )
    }

    private func createDraft(
        asset: Asset,
        requestedStage: WorkflowStage,
        issueID: UUID?,
        parentRecordID: UUID?,
        timeContext: FrozenTimeContext?,
        acknowledgementSnapshots: (
            afterDark: SignPack.Acknowledgement,
            safePosition: SignPack.Acknowledgement
        )?,
        startedAt: Date
    ) throws -> WorkflowRecord {
        guard signPack.packID == asset.packID,
              signPack.schemaVersion == asset.packSchemaVersion,
              signPack.contentVersion == asset.packContentVersion else {
            throw CheckRunnerCoordinatorError.invalidLineage
        }

        let id = UUID()
        let draft = WorkflowRecord(
            id: id,
            assetID: asset.id,
            packetID: nil,
            issueID: issueID,
            parentRecordID: parentRecordID,
            recordRevisionRootID: id,
            revisesRecordID: nil,
            evidenceSourceRecordID: nil,
            revisionKind: .original,
            stage: requestedStage,
            state: .draft,
            draftStepKey: requestedStage == .work ? nil : .wide,
            startedAt: startedAt,
            completedAt: nil,
            observedAtUTC: timeContext?.observedAtUTC,
            timeZoneID: timeContext?.timeZoneID,
            utcOffsetMinutes: timeContext?.utcOffsetMinutes,
            localDate: timeContext?.localDate,
            localTime: timeContext?.localTime,
            afterDarkAcknowledgementKey: acknowledgementSnapshots?.afterDark.key,
            afterDarkAcknowledgementCopy: acknowledgementSnapshots?.afterDark.copy,
            afterDarkAcknowledgementVersion: acknowledgementSnapshots?.afterDark.version,
            afterDarkAcknowledgementAccepted: acknowledgementSnapshots == nil ? nil : true,
            safePositionAcknowledgementKey: acknowledgementSnapshots?.safePosition.key,
            safePositionAcknowledgementCopy: acknowledgementSnapshots?.safePosition.copy,
            safePositionAcknowledgementVersion: acknowledgementSnapshots?.safePosition.version,
            safePositionAcknowledgementAccepted: acknowledgementSnapshots == nil ? nil : true,
            packID: asset.packID,
            packSchemaVersion: asset.packSchemaVersion,
            packContentVersion: asset.packContentVersion,
            pdfTemplateID: Self.pdfTemplateID,
            pdfTemplateVersion: Self.pdfTemplateVersion,
            outcomeKey: nil,
            couldNotVerifyKey: nil,
            couldNotVerifyDisplaySnapshot: nil,
            couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: nil,
            workDescription: nil,
            note: nil,
            finalizationMutationID: nil
        )

        modelContext.insert(draft)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw CheckRunnerCoordinatorError.saveFailed
        }
        return draft
    }
}

private struct TimeZoneResolution {
    let site: Site
    let timeZoneID: String
    let requiresSave: Bool
}

import Foundation
import SwiftUI
import UIKit

struct OutcomeReviewView: View {
    static let outcomeScreenAccessibilityIdentifier = "s3.outcome.screen"
    static let noVisibleIssueAccessibilityIdentifier = "s3.outcome.no-visible-issue"
    static let visibleIssueAccessibilityIdentifier = "s3.outcome.visible-issue"
    static let couldNotVerifyAccessibilityIdentifier = "s3.outcome.could-not-verify"
    static let couldNotVerifyNoteAccessibilityIdentifier = "s3.outcome.cnv.note"
    static let continueAccessibilityIdentifier = "s3.outcome.continue"
    static let reviewScreenAccessibilityIdentifier = "s3.review.screen"
    static let reviewOutcomeAccessibilityIdentifier = "s3.review.outcome"
    static let reviewCouldNotVerifyAccessibilityIdentifier = "s3.review.could-not-verify"
    static let wideEvidenceAccessibilityIdentifier = "s3.review.evidence.wide"
    static let closeEvidenceAccessibilityIdentifier = "s3.review.evidence.close"
    static let saveAccessibilityIdentifier = "s3.review.save-report"
    static let backAccessibilityIdentifier = "s3.review.back"
    static let resolvedAccessibilityIdentifier = "s5.2.outcome.resolved"
    static let issueStillVisibleAccessibilityIdentifier =
        "s5.2.outcome.issue-still-visible"
    static let recheckNoteAccessibilityIdentifier = "s5.2.outcome.note"

    let assetID: UUID
    let coordinator: CheckRunnerCoordinator
    let startsWithCouldNotVerify: Bool

    @State private var selection: CheckOutcomeSelection?
    @State private var isChoosingVisibleIssue = false
    @State private var isChoosingCouldNotVerify: Bool
    @State private var selectedCouldNotVerifyReasonKey: String?
    @State private var couldNotVerifyNote = ""
    @State private var recheckNote = ""
    @State private var review: FinalizationReview?
    @State private var result: FinalizationResult?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        assetID: UUID,
        coordinator: CheckRunnerCoordinator,
        startsWithCouldNotVerify: Bool = false
    ) {
        self.assetID = assetID
        self.coordinator = coordinator
        self.startsWithCouldNotVerify = startsWithCouldNotVerify
        _isChoosingCouldNotVerify = State(initialValue: startsWithCouldNotVerify)
    }

    var body: some View {
        Group {
            if let result {
                ValueReceiptView(result: result, coordinator: coordinator)
            } else if let review {
                reviewScreen(review)
            } else {
                outcomeScreen
            }
        }
    }

    private var outcomeScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            WorklightCard {
                WorklightStatusBadge(kind: .information, text: "Outcome")
                Text("What did you observe?")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .accessibilityAddTraits(.isHeader)

                if isRecheck {
                    choiceButton(
                        title: outcomeDisplay("resolved"),
                        isSelected: isResolvedSelected,
                        identifier: Self.resolvedAccessibilityIdentifier
                    ) {
                        selection = .resolved(note: normalizedRecheckNote)
                        isChoosingVisibleIssue = false
                        isChoosingCouldNotVerify = false
                        errorMessage = nil
                    }

                    choiceButton(
                        title: outcomeDisplay("issue_still_visible"),
                        isSelected: isIssueStillVisibleSelected,
                        identifier: Self.issueStillVisibleAccessibilityIdentifier
                    ) {
                        selection = .issueStillVisible(note: normalizedRecheckNote)
                        isChoosingVisibleIssue = false
                        isChoosingCouldNotVerify = false
                        errorMessage = nil
                    }
                } else if !startsWithCouldNotVerify {
                    choiceButton(
                        title: outcomeDisplay("no_visible_issue"),
                        isSelected: selection == .noVisibleIssue,
                        identifier: Self.noVisibleIssueAccessibilityIdentifier
                    ) {
                        selection = .noVisibleIssue
                        isChoosingVisibleIssue = false
                        isChoosingCouldNotVerify = false
                        errorMessage = nil
                    }

                    choiceButton(
                        title: outcomeDisplay("visible_issue"),
                        isSelected: isChoosingVisibleIssue,
                        identifier: Self.visibleIssueAccessibilityIdentifier
                    ) {
                        selection = nil
                        isChoosingVisibleIssue = true
                        isChoosingCouldNotVerify = false
                        errorMessage = nil
                    }
                }

                if !isRecheck {
                    choiceButton(
                        title: outcomeDisplay("could_not_verify"),
                        isSelected: isChoosingCouldNotVerify,
                        identifier: Self.couldNotVerifyAccessibilityIdentifier
                    ) {
                        selection = nil
                        isChoosingVisibleIssue = false
                        isChoosingCouldNotVerify = true
                        errorMessage = nil
                    }
                }
            }

            if isRecheck {
                WorklightCard {
                    TextField("Optional note", text: $recheckNote, axis: .vertical)
                        .lineLimit(3...6)
                        .frame(
                            minHeight: DesignTokens.Control.minimumHitSize,
                            alignment: .topLeading
                        )
                        .accessibilityIdentifier(Self.recheckNoteAccessibilityIdentifier)
                        .onChange(of: recheckNote) { _, _ in
                            updateRecheckSelection()
                        }
                    Text("\(recheckNote.count) of 1000 characters")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                }
            }

            if isChoosingVisibleIssue {
                WorklightCard {
                    Text("Choose one visible issue")
                        .font(.headline)
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                    ForEach(coordinator.signPackIssueLabels) { label in
                        choiceButton(
                            title: label.display,
                            isSelected: selectedIssueKey == label.key,
                            identifier: "s3.outcome.issue.\(label.key)"
                        ) {
                            selection = .visibleIssue(labelKey: label.key)
                            isChoosingVisibleIssue = true
                            errorMessage = nil
                        }
                    }
                }
            }

            if isChoosingCouldNotVerify {
                WorklightCard {
                    Text("Why could this check not be completed?")
                        .font(.headline)
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                    ForEach(coordinator.couldNotVerifyReasons) { reason in
                        choiceButton(
                            title: reason.display,
                            isSelected: selectedCouldNotVerifyReasonKey == reason.key,
                            identifier: "s3.outcome.cnv.reason.\(reason.key)"
                        ) {
                            selectedCouldNotVerifyReasonKey = reason.key
                            selection = .couldNotVerify(
                                reasonKey: reason.key,
                                note: normalizedCouldNotVerifyNote
                            )
                            errorMessage = nil
                        }
                    }

                    TextField(
                        "Optional note",
                        text: $couldNotVerifyNote,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                    .accessibilityIdentifier(
                        Self.couldNotVerifyNoteAccessibilityIdentifier
                    )
                    .onChange(of: couldNotVerifyNote) { _, _ in
                        updateCouldNotVerifySelection()
                    }

                    Text("\(couldNotVerifyNote.count) of 1000 characters")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                }
            }

            errorCard

            Button("Continue") {
                prepareReview()
            }
            .buttonStyle(WorklightPrimaryButtonStyle())
            .disabled(!canContinue)
            .accessibilityIdentifier(Self.continueAccessibilityIdentifier)
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle("Outcome")
        .accessibilityIdentifier(Self.outcomeScreenAccessibilityIdentifier)
    }

    private func reviewScreen(_ review: FinalizationReview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            WorklightCard {
                WorklightStatusBadge(kind: .information, text: "Review")
                Text(isRecheck ? "Review this recheck" : "Review this check")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .accessibilityAddTraits(.isHeader)

                reviewRow(label: "Outcome", value: review.outcomeDisplay)
                    .accessibilityIdentifier(Self.reviewOutcomeAccessibilityIdentifier)
                if let issue = review.issueLabelDisplay {
                    reviewRow(label: "Visible issue", value: issue)
                }
                if let reason = review.couldNotVerifyReasonDisplay {
                    reviewRow(label: "Could not verify", value: reason)
                        .accessibilityIdentifier(
                            Self.reviewCouldNotVerifyAccessibilityIdentifier
                        )
                }
                if let note = review.note {
                    reviewRow(label: "Note", value: note)
                }
                reviewRow(
                    label: "Observed",
                    value: "\(review.localDate) · \(review.localTime) · \(review.timeZoneID)"
                )
            }

            reviewEvidence(
                review.wideEvidence,
                purposeDisplay: "Wide view",
                isMissing: review.missingPurposeDisplays.contains("Wide view"),
                identifier: Self.wideEvidenceAccessibilityIdentifier
            )
            reviewEvidence(
                review.closeEvidence,
                purposeDisplay: "Close view",
                isMissing: review.missingPurposeDisplays.contains("Close view"),
                identifier: Self.closeEvidenceAccessibilityIdentifier
            )

            WorklightCard {
                Text("Confirmed")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                Label(review.afterDarkAcknowledgementCopy, systemImage: "checkmark.circle.fill")
                Label(review.safePositionAcknowledgementCopy, systemImage: "checkmark.circle.fill")
            }

            errorCard

            Button(isSaving ? "Saving…" : "Save and finish") {
                finalize()
            }
            .buttonStyle(WorklightPrimaryButtonStyle())
            .disabled(isSaving)
            .accessibilityIdentifier(Self.saveAccessibilityIdentifier)

            Button("Back") {
                self.review = nil
                errorMessage = nil
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .disabled(isSaving)
            .accessibilityIdentifier(Self.backAccessibilityIdentifier)
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle("Review")
        .accessibilityIdentifier(Self.reviewScreenAccessibilityIdentifier)
    }

    private func choiceButton(
        title: String,
        isSelected: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(WorklightSecondaryButtonStyle())
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier(identifier)
    }

    private func reviewRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(label)
                .font(.caption)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
            Text(value)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private func reviewEvidence(
        _ evidence: ReviewEvidence?,
        purposeDisplay: String,
        isMissing: Bool,
        identifier: String
    ) -> some View {
        WorklightCard {
            if let evidence,
               let data = try? coordinator.reviewThumbnailData(for: evidence),
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard))
                    .accessibilityHidden(true)
            }
            Label(
                evidence?.purposeDisplay ?? purposeDisplay,
                systemImage: evidence == nil ? "photo.badge.exclamationmark" : "photo.fill"
            )
                .font(.headline)
                .foregroundStyle(DesignTokens.Colors.primaryText)
            Text(
                isMissing || evidence == nil
                    ? "Not captured — Could not verify"
                    : "Photo saved for this check"
            )
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var errorCard: some View {
        if let errorMessage {
            WorklightCard {
                WorklightStatusBadge(kind: .blocked, text: "Check not saved")
                Text(errorMessage)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
            }
        }
    }

    private var selectedIssueKey: String? {
        if case let .visibleIssue(labelKey) = selection { return labelKey }
        return nil
    }

    private var canContinue: Bool {
        switch selection {
        case .noVisibleIssue:
            true
        case let .visibleIssue(labelKey):
            coordinator.signPackIssueLabels.contains { $0.key == labelKey }
        case let .couldNotVerify(reasonKey, note):
            coordinator.couldNotVerifyReasons.contains { $0.key == reasonKey }
                && normalizedNote(note) != .invalid
        case let .resolved(note), let .issueStillVisible(note):
            normalizedNote(note) != .invalid
        case nil:
            false
        }
    }

    private enum NormalizedNote: Equatable {
        case none
        case value(String)
        case invalid
    }

    private var normalizedCouldNotVerifyNote: String? {
        switch normalizedNote(couldNotVerifyNote) {
        case .none: nil
        case let .value(value): value
        case .invalid: couldNotVerifyNote
        }
    }

    private var normalizedRecheckNote: String? {
        switch normalizedNote(recheckNote) {
        case .none: nil
        case let .value(value): value
        case .invalid: recheckNote
        }
    }

    private var isRecheck: Bool {
        coordinator.activeDraftStage(assetID: assetID) == .recheck
    }

    private var isResolvedSelected: Bool {
        if case .resolved = selection { return true }
        return false
    }

    private var isIssueStillVisibleSelected: Bool {
        if case .issueStillVisible = selection { return true }
        return false
    }

    private func updateRecheckSelection() {
        switch selection {
        case .resolved:
            selection = .resolved(note: normalizedRecheckNote)
        case .issueStillVisible:
            selection = .issueStillVisible(note: normalizedRecheckNote)
        default:
            break
        }
    }

    private func normalizedNote(_ value: String?) -> NormalizedNote {
        guard let value else { return .none }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }
        guard trimmed.count <= 1000 else { return .invalid }
        return .value(trimmed)
    }

    private func updateCouldNotVerifySelection() {
        guard let key = selectedCouldNotVerifyReasonKey else { return }
        selection = .couldNotVerify(
            reasonKey: key,
            note: normalizedCouldNotVerifyNote
        )
    }

    private func outcomeDisplay(_ key: String) -> String {
        coordinator.signPackOutcomeDisplay(key: key) ?? key
    }

    private func prepareReview() {
        guard let selection else { return }
        do {
            review = try coordinator.prepareReview(assetID: assetID, selection: selection)
            errorMessage = nil
        } catch {
            errorMessage = "The check could not be prepared for review. Try again."
        }
    }

    private func finalize() {
        guard let selection, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        let info = Bundle.main.infoDictionary ?? [:]
        let sourceApp = SourceAppSnapshotV1(
            build: info["CFBundleVersion"] as? String ?? "0",
            version: info["CFBundleShortVersionString"] as? String ?? "0"
        )
        Task { @MainActor in
            do {
                let now = Date()
                result = try await coordinator.finalize(
                    assetID: assetID,
                    selection: selection,
                    completedAt: now,
                    snapshotCreatedAt: now,
                    sourceApp: sourceApp
                )
            } catch {
                errorMessage = "The report could not be saved. Your check is still available to retry."
            }
            isSaving = false
        }
    }
}

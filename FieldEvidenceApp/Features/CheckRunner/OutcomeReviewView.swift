import Foundation
import SwiftUI
import UIKit

struct OutcomeReviewView: View {
    static let outcomeScreenAccessibilityIdentifier = "s3.outcome.screen"
    static let noVisibleIssueAccessibilityIdentifier = "s3.outcome.no-visible-issue"
    static let visibleIssueAccessibilityIdentifier = "s3.outcome.visible-issue"
    static let continueAccessibilityIdentifier = "s3.outcome.continue"
    static let reviewScreenAccessibilityIdentifier = "s3.review.screen"
    static let reviewOutcomeAccessibilityIdentifier = "s3.review.outcome"
    static let wideEvidenceAccessibilityIdentifier = "s3.review.evidence.wide"
    static let closeEvidenceAccessibilityIdentifier = "s3.review.evidence.close"
    static let saveAccessibilityIdentifier = "s3.review.save-report"

    let assetID: UUID
    let coordinator: CheckRunnerCoordinator

    @State private var selection: CheckOutcomeSelection?
    @State private var isChoosingVisibleIssue = false
    @State private var review: FinalizationReview?
    @State private var result: FinalizationResult?
    @State private var isSaving = false
    @State private var errorMessage: String?

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

                choiceButton(
                    title: outcomeDisplay("no_visible_issue"),
                    isSelected: selection == .noVisibleIssue,
                    identifier: Self.noVisibleIssueAccessibilityIdentifier
                ) {
                    selection = .noVisibleIssue
                    isChoosingVisibleIssue = false
                    errorMessage = nil
                }

                choiceButton(
                    title: outcomeDisplay("visible_issue"),
                    isSelected: isChoosingVisibleIssue,
                    identifier: Self.visibleIssueAccessibilityIdentifier
                ) {
                    selection = nil
                    isChoosingVisibleIssue = true
                    errorMessage = nil
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
                Text("Review this check")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .accessibilityAddTraits(.isHeader)

                reviewRow(label: "Outcome", value: review.outcomeDisplay)
                    .accessibilityIdentifier(Self.reviewOutcomeAccessibilityIdentifier)
                if let issue = review.issueLabelDisplay {
                    reviewRow(label: "Visible issue", value: issue)
                }
                reviewRow(
                    label: "Observed",
                    value: "\(review.localDate) · \(review.localTime) · \(review.timeZoneID)"
                )
            }

            evidenceRow(review.wideEvidence, identifier: Self.wideEvidenceAccessibilityIdentifier)
            evidenceRow(review.closeEvidence, identifier: Self.closeEvidenceAccessibilityIdentifier)

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
    }

    private func evidenceRow(_ evidence: ReviewEvidence, identifier: String) -> some View {
        WorklightCard {
            if let data = try? coordinator.reviewThumbnailData(for: evidence),
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard))
                    .accessibilityHidden(true)
            }
            Label(evidence.purposeDisplay, systemImage: "photo.fill")
                .font(.headline)
                .foregroundStyle(DesignTokens.Colors.primaryText)
            Text("Photo saved for this check")
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
        case nil:
            false
        }
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

import Foundation
import SwiftUI
import UIKit

/// Explicit durable actions for a live Round item. The live parent owns the
/// saved outcome, review and finalization; no standalone coordinator write occurs.
@MainActor
struct CheckRunnerDurableOutcomeActionsV1 {
    let presentation: CheckRunnerItemOutcomePresentationV1
    /// Photos are incomplete, so only Could not verify can be reviewed.
    let couldNotVerifyOnly: Bool
    let values: @MainActor () -> CheckRunnerEditableOutcomeV1
    let update: @MainActor (CheckRunnerEditableOutcomeV1) throws -> Void
    let review: @MainActor () async throws -> FinalizationReview
    let thumbnail: @MainActor (ReviewEvidence) -> Data?
    let returnToPhotos: (@MainActor () throws -> Void)?
    let finish: @MainActor () async throws -> Void
}

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
    static let originalResolvedDifferentIssueAccessibilityIdentifier =
        "s5.3.outcome.original-resolved-different-issue"
    static let returnToPhotosAccessibilityIdentifier = "v23.outcome.return-to-photos"

    let assetID: UUID
    private enum Backend {
        case standalone(CheckRunnerCoordinator)
        case durable(CheckRunnerDurableOutcomeActionsV1)
    }
    private let backend: Backend
    let startsWithCouldNotVerify: Bool
    @State private var standaloneEditable: CheckRunnerEditableOutcomeV1
    private var editable: CheckRunnerEditableOutcomeV1 {
        get {
            if case let .durable(actions) = backend { return actions.values() }
            return standaloneEditable
        }
        nonmutating set {
            if case let .durable(actions) = backend {
                do { try actions.update(newValue) }
                catch { errorMessage = "Your changes could not be saved. Try again." }
            } else {
                standaloneEditable = newValue
            }
        }
    }
    private var editableBinding: Binding<CheckRunnerEditableOutcomeV1> {
        Binding(get: { editable }, set: { editable = $0 })
    }

    private var selection: CheckOutcomeSelection? { editable.selection?.liveSelection }
    private var isChoosingVisibleIssue: Bool { editable.choice == .visibleIssue }
    private var isChoosingDifferentIssue: Bool { editable.choice == .differentIssue }
    private var isChoosingCouldNotVerify: Bool { editable.choice == .couldNotVerify }
    private var selectedCouldNotVerifyReasonKey: String? { editable.selectedCouldNotVerifyReasonKey }
    private var couldNotVerifyNote: String { editable.couldNotVerifyNote }
    private var recheckNote: String { editable.recheckNote }
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
        self.backend = .standalone(coordinator)
        self.startsWithCouldNotVerify = startsWithCouldNotVerify
        _standaloneEditable = State(initialValue: .initial(startsWithCouldNotVerify: startsWithCouldNotVerify))
    }

    /// The live parent owns the outcome; this backend never calls the standalone coordinator.
    init(assetID: UUID, durable: CheckRunnerDurableOutcomeActionsV1) {
        self.assetID = assetID
        self.backend = .durable(durable)
        self.startsWithCouldNotVerify = durable.couldNotVerifyOnly
        _standaloneEditable = State(initialValue: .init())
    }

    var body: some View {
        Group {
            if let result, case let .standalone(coordinator) = backend {
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
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space16) {
            AssetRoundsEvidenceCard {
                Label("Outcome", systemImage: "info.circle.fill")
                    .font(DesignTokens.Typography.secondaryBody.weight(.semibold))
                    .foregroundStyle(DesignTokens.SemanticColors.brandHeading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Information: Outcome")
                Text("What did you observe?")
                    .font(DesignTokens.Typography.screenTitle)
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                    .accessibilityAddTraits(.isHeader)

                if isRecheck && !startsWithCouldNotVerify {
                    choiceButton(
                        title: outcomeDisplay("resolved"),
                        isSelected: isResolvedSelected,
                        identifier: Self.resolvedAccessibilityIdentifier
                    ) {
                        editable.selectResolved()
                        errorMessage = nil
                    }

                    choiceButton(
                        title: outcomeDisplay("issue_still_visible"),
                        isSelected: isIssueStillVisibleSelected,
                        identifier: Self.issueStillVisibleAccessibilityIdentifier
                    ) {
                        editable.selectIssueStillVisible()
                        errorMessage = nil
                    }

                    choiceButton(
                        title: outcomeDisplay("original_resolved_different_issue"),
                        isSelected: isOriginalResolvedDifferentIssueSelected,
                        identifier: Self.originalResolvedDifferentIssueAccessibilityIdentifier
                    ) {
                        editable.chooseDifferentIssue()
                        errorMessage = nil
                    }
                } else if !isRecheck && !startsWithCouldNotVerify {
                    choiceButton(
                        title: outcomeDisplay("no_visible_issue"),
                        isSelected: selection == .noVisibleIssue,
                        identifier: Self.noVisibleIssueAccessibilityIdentifier
                    ) {
                        editable.selectNoVisibleIssue()
                        errorMessage = nil
                    }

                    choiceButton(
                        title: outcomeDisplay("visible_issue"),
                        isSelected: isChoosingVisibleIssue,
                        identifier: Self.visibleIssueAccessibilityIdentifier
                    ) {
                        editable.chooseVisibleIssue()
                        errorMessage = nil
                    }
                }

                choiceButton(
                    title: outcomeDisplay("could_not_verify"),
                    isSelected: isChoosingCouldNotVerify,
                    identifier: Self.couldNotVerifyAccessibilityIdentifier
                ) {
                    editable.chooseCouldNotVerify()
                    errorMessage = nil
                }
            }

            if isRecheck && !isChoosingCouldNotVerify {
                AssetRoundsEvidenceCard {
                    TextField("Optional note", text: editableBinding.recheckNote, axis: .vertical)
                        .lineLimit(3...6)
                        .frame(
                            minHeight: DesignTokens.Target.minimumInteractiveHeight,
                            alignment: .topLeading
                        )
                        .accessibilityIdentifier(Self.recheckNoteAccessibilityIdentifier)
                        .onChange(of: recheckNote) { _, _ in
                            updateRecheckSelection()
                        }
                    Text("\(recheckNote.count) of 1000 characters")
                        .font(DesignTokens.Typography.supportingCaption)
                        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                }
            }

            if isChoosingVisibleIssue || isChoosingDifferentIssue {
                AssetRoundsEvidenceCard {
                    Text("Choose one visible issue")
                        .font(DesignTokens.Typography.sectionHeading)
                        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                    ForEach(issueLabels) { label in
                        choiceButton(
                            title: label.display,
                            isSelected: selectedIssueKey == label.key,
                            identifier: "s3.outcome.issue.\(label.key)"
                        ) {
                            editable.selectIssue(labelKey: label.key)
                            errorMessage = nil
                        }
                    }
                }
            }

            if isChoosingCouldNotVerify {
                AssetRoundsEvidenceCard {
                    Text("Why could this check not be completed?")
                        .font(DesignTokens.Typography.sectionHeading)
                        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                    ForEach(couldNotVerifyReasons) { reason in
                        choiceButton(
                            title: reason.display,
                            isSelected: selectedCouldNotVerifyReasonKey == reason.key,
                            identifier: "s3.outcome.cnv.reason.\(reason.key)"
                        ) {
                            editable.selectCouldNotVerifyReason(key: reason.key)
                            errorMessage = nil
                        }
                    }

                    TextField(
                        "Optional note",
                        text: editableBinding.couldNotVerifyNote,
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
                        .font(DesignTokens.Typography.supportingCaption)
                        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                }
            }

            errorCard

            AssetRoundsPrimaryAction("Continue") {
                prepareReview()
            }
            .disabled(!canContinue || isSaving)
            .accessibilityIdentifier(Self.continueAccessibilityIdentifier)

            if case let .durable(actions) = backend, let returnToPhotos = actions.returnToPhotos {
                AssetRoundsSecondaryAction("Take photos instead") {
                    do { try returnToPhotos(); errorMessage = nil }
                    catch { errorMessage = "Your changes could not be saved. Try again." }
                }
                .disabled(isSaving)
                .accessibilityIdentifier(Self.returnToPhotosAccessibilityIdentifier)
            }
            }
            .padding(DesignTokens.Spacing.space16)
        }
        .clipped()
        .modifier(OutcomeTopScrollEdgeVisibility())
        .navigationTitle("Outcome")
        .accessibilityIdentifier(Self.outcomeScreenAccessibilityIdentifier)
    }

    private func reviewScreen(_ review: FinalizationReview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space16) {
            AssetRoundsEvidenceCard {
                Label("Review", systemImage: "info.circle.fill")
                    .font(DesignTokens.Typography.secondaryBody.weight(.semibold))
                    .foregroundStyle(DesignTokens.SemanticColors.brandHeading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Information: Review")
                Text(isRecheck ? "Review this recheck" : "Review this check")
                    .font(DesignTokens.Typography.screenTitle)
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
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

            AssetRoundsEvidenceCard {
                Text("Confirmed")
                    .font(DesignTokens.Typography.sectionHeading)
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                Label(review.afterDarkAcknowledgementCopy, systemImage: "checkmark.circle.fill")
                Label(review.safePositionAcknowledgementCopy, systemImage: "checkmark.circle.fill")
            }

            errorCard

            AssetRoundsPrimaryAction(action: {
                finalize()
            }) {
                Text(isSaving ? "Saving…" : "Save and finish")
            }
            .disabled(isSaving)
            .accessibilityIdentifier(Self.saveAccessibilityIdentifier)

            AssetRoundsSecondaryAction("Back") {
                self.review = nil
                errorMessage = nil
            }
            .disabled(isSaving)
            .accessibilityIdentifier(Self.backAccessibilityIdentifier)
            }
            .padding(DesignTokens.Spacing.space16)
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
        AssetRoundsSecondaryAction(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier(identifier)
    }

    private func reviewRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space8) {
            Text(label)
                .font(DesignTokens.Typography.supportingCaption)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
            Text(value)
                .font(DesignTokens.Typography.primaryBody)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private func reviewEvidence(
        _ evidence: ReviewEvidence?,
        purposeDisplay: String,
        isMissing: Bool,
        identifier: String
    ) -> some View {
        AssetRoundsPhotoCapture {
            if let evidence,
               let data = thumbnailData(for: evidence),
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
                .font(DesignTokens.Typography.sectionHeading)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
            Text(
                isMissing || evidence == nil
                    ? "Not captured — Could not verify"
                    : "Photo saved for this check"
            )
                .font(DesignTokens.Typography.primaryBody)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
        }
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var errorCard: some View {
        if let errorMessage {
            AssetRoundsEvidenceCard {
                AssetRoundsStateLabel(
                    kind: .error,
                    text: Text("Check not saved")
                )
                .accessibilityLabel("Blocked: Check not saved")
                .accessibilityValue(Text(verbatim: String()))
                Text(errorMessage)
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
            }
        }
    }

    private var selectedIssueKey: String? {
        if case let .visibleIssue(labelKey) = selection { return labelKey }
        if case let .originalResolvedDifferentIssue(labelKey, _) = selection {
            return labelKey
        }
        return nil
    }

    private var canContinue: Bool {
        switch selection {
        case .noVisibleIssue:
            true
        case let .visibleIssue(labelKey):
            issueLabels.contains { $0.key == labelKey }
        case let .couldNotVerify(reasonKey, note):
            couldNotVerifyReasons.contains { $0.key == reasonKey }
                && normalizedNote(note) != .invalid
        case let .resolved(note), let .issueStillVisible(note):
            normalizedNote(note) != .invalid
        case let .originalResolvedDifferentIssue(labelKey, note):
            issueLabels.contains { $0.key == labelKey }
                && normalizedNote(note) != .invalid
        case nil:
            false
        }
    }

    private typealias NormalizedNote = CheckRunnerEditableNoteProjectionV1

    private var isRecheck: Bool {
        switch backend {
        case let .standalone(coordinator): coordinator.activeDraftStage(assetID: assetID) == .recheck
        case let .durable(actions): actions.presentation.isRecheck
        }
    }

    private var issueLabels: [SignPack.RegistryEntry] {
        switch backend {
        case let .standalone(coordinator): coordinator.signPackIssueLabels
        case let .durable(actions): actions.presentation.issueLabels
        }
    }

    private var couldNotVerifyReasons: [SignPack.RegistryEntry] {
        switch backend {
        case let .standalone(coordinator): coordinator.couldNotVerifyReasons
        case let .durable(actions): actions.presentation.couldNotVerifyReasons
        }
    }

    private func thumbnailData(for evidence: ReviewEvidence) -> Data? {
        switch backend {
        case let .standalone(coordinator): try? coordinator.reviewThumbnailData(for: evidence)
        case let .durable(actions): actions.thumbnail(evidence)
        }
    }

    private var isResolvedSelected: Bool {
        if case .resolved = selection { return true }
        return false
    }

    private var isIssueStillVisibleSelected: Bool {
        if case .issueStillVisible = selection { return true }
        return false
    }

    private var isOriginalResolvedDifferentIssueSelected: Bool {
        if case .originalResolvedDifferentIssue = selection { return true }
        return false
    }

    private func updateRecheckSelection() {
        editable.updateRecheckSelection()
    }

    private func normalizedNote(_ value: String?) -> NormalizedNote {
        CheckRunnerOutcomeResolverV1.projectEditableNote(value)
    }

    private func updateCouldNotVerifySelection() {
        editable.updateCouldNotVerifySelection()
    }

    private func outcomeDisplay(_ key: String) -> String {
        switch backend {
        case let .standalone(coordinator): coordinator.signPackOutcomeDisplay(key: key) ?? key
        case let .durable(actions): actions.presentation.outcomeDisplay(key)
        }
    }

    private func prepareReview() {
        guard let selection else { return }
        switch backend {
        case let .standalone(coordinator):
            do {
                review = try coordinator.prepareReview(assetID: assetID, selection: selection)
                errorMessage = nil
            } catch {
                errorMessage = "The check could not be prepared for review. Try again."
            }
        case let .durable(actions):
            // Review reads only the saved outcome, after its forced flush.
            guard !isSaving else { return }
            isSaving = true
            Task { @MainActor in
                defer { isSaving = false }
                do {
                    review = try await actions.review()
                    errorMessage = nil
                } catch {
                    errorMessage = "The check could not be prepared for review. Try again."
                }
            }
        }
    }

    private func finalize() {
        guard let selection, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        guard case let .standalone(coordinator) = backend else {
            guard case let .durable(actions) = backend else { return }
            Task { @MainActor in
                defer { isSaving = false }
                do { try await actions.finish() }
                catch { errorMessage = "The report could not be saved. Your check is still available to retry." }
            }
            return
        }
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

private struct OutcomeTopScrollEdgeVisibility: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .top)
        } else {
            content
        }
    }
}

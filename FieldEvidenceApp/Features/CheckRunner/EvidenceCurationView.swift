import Foundation
import SwiftUI

/// Presentation-only C02 surface. It reads version-pinned previews and plans;
/// all selection, derivative, privacy, and canonical association effects stay
/// with their existing coordinators and writers.
struct EvidenceCurationView: View {
    static let screenAccessibilityIdentifier = EvidenceCurationAccessibilityIDV1.screen.rawValue
    static let detailPreviewAccessibilityIdentifier = EvidenceCurationAccessibilityIDV1.detailPreview.rawValue
    static let originalAccessibilityIdentifier = EvidenceCurationAccessibilityIDV1.original.rawValue
    static let referenceAccessibilityIdentifier = EvidenceCurationAccessibilityIDV1.reference.rawValue
    static let comparisonAccessibilityIdentifier = EvidenceCurationAccessibilityIDV1.comparison.rawValue
    static let overlayAdvisoryAccessibilityIdentifier = EvidenceCurationAccessibilityIDV1.overlayAdvisory.rawValue
    static let markupControlsAccessibilityIdentifier = EvidenceCurationAccessibilityIDV1.markupControls.rawValue
    static let removeMarkupAccessibilityIdentifier = EvidenceCurationAccessibilityIDV1.removeMarkup.rawValue
    static let retakeAccessibilityIdentifier = EvidenceCurationAccessibilityIDV1.retake.rawValue
    static let removeFromWorkAccessibilityIdentifier = EvidenceCurationAccessibilityIDV1.removeFromWork.rawValue
    static let moveEarlierAccessibilityIdentifier = EvidenceCurationAccessibilityIDV1.moveEarlier.rawValue
    static let moveLaterAccessibilityIdentifier = EvidenceCurationAccessibilityIDV1.moveLater.rawValue
    static let sequenceAccessibilityIdentifier = EvidenceCurationAccessibilityIDV1.sequence.rawValue
    static let contactSheetAccessibilityIdentifier = EvidenceCurationAccessibilityIDV1.contactSheet.rawValue
    static let reducedMotionAccessibilityIdentifier = EvidenceCurationAccessibilityIDV1.reducedMotion.rawValue
    static let reviewOrderAccessibilityIdentifier = EvidenceCurationAccessibilityIDV1.reviewOrder.rawValue
    static let roleAccessibilityIdentifier = EvidenceCurationAccessibilityIDV1.role.rawValue
    static let captionAccessibilityIdentifier = EvidenceCurationAccessibilityIDV1.caption.rawValue
    static let accessibilityDescriptionAccessibilityIdentifier = EvidenceCurationAccessibilityIDV1.accessibilityDescription.rawValue
    static let visualDerivativeReadinessAccessibilityIdentifier = EvidenceCurationAccessibilityIDV1.visualDerivativeReadiness.rawValue

    let previews: [EvidenceVersionPinnedPreviewV1]
    /// The accepted C05 sequence is the sole authority for display order,
    /// role, reviewed caption, and optional accessibility description.
    let evidenceSequence: EvidenceSequenceV1
    let comparison: EvidenceComparisonProjectionV1?
    let markupPlan: EvidenceReviewedMarkupPlanV1?
    let sequencePlan: EvidenceSequencePlanV1?
    /// A completed publication receipt can establish derivative readiness, but
    /// its media type still determines whether that readiness is visual.
    let derivativePublication: EvidenceDerivativePublicationReceiptV1?
    let onAddArrowMarkup: (() -> Void)?
    let onAddCircleMarkup: (() -> Void)?
    let onAddTextMarkup: (() -> Void)?
    let onRemoveMarkup: (() -> Void)?
    let onRetake: ((EvidenceSequenceItemV1) -> Void)?
    let onRemoveFromWork: ((EvidenceSequenceItemV1) -> Void)?
    let onMoveEarlier: ((EvidenceSequenceItemV1) -> Void)?
    let onMoveLater: ((EvidenceSequenceItemV1) -> Void)?

    @Environment(\.accessibilityDifferentiateWithoutColor)
    private var differentiatesWithoutColor
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize

    init(
        previews: [EvidenceVersionPinnedPreviewV1],
        evidenceSequence: EvidenceSequenceV1,
        comparison: EvidenceComparisonProjectionV1? = nil,
        markupPlan: EvidenceReviewedMarkupPlanV1? = nil,
        sequencePlan: EvidenceSequencePlanV1? = nil,
        derivativePublication: EvidenceDerivativePublicationReceiptV1? = nil,
        onAddArrowMarkup: (() -> Void)? = nil,
        onAddCircleMarkup: (() -> Void)? = nil,
        onAddTextMarkup: (() -> Void)? = nil,
        onRemoveMarkup: (() -> Void)? = nil,
        onRetake: ((EvidenceSequenceItemV1) -> Void)? = nil,
        onRemoveFromWork: ((EvidenceSequenceItemV1) -> Void)? = nil,
        onMoveEarlier: ((EvidenceSequenceItemV1) -> Void)? = nil,
        onMoveLater: ((EvidenceSequenceItemV1) -> Void)? = nil
    ) {
        self.previews = previews
        self.evidenceSequence = evidenceSequence
        self.comparison = comparison
        self.markupPlan = markupPlan
        self.sequencePlan = sequencePlan
        self.derivativePublication = derivativePublication
        self.onAddArrowMarkup = onAddArrowMarkup
        self.onAddCircleMarkup = onAddCircleMarkup
        self.onAddTextMarkup = onAddTextMarkup
        self.onRemoveMarkup = onRemoveMarkup
        self.onRetake = onRetake
        self.onRemoveFromWork = onRemoveFromWork
        self.onMoveEarlier = onMoveEarlier
        self.onMoveLater = onMoveLater
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: contentSpacing) {
                detailPreview
                comparisonSection
                markupSection
                sequenceSection
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle(localized(.heading))
        .navigationBarTitleDisplayMode(.inline)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
    }

    private var contentSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize
            ? DesignTokens.Spacing.large
            : DesignTokens.Spacing.medium
    }

    private var detailPreview: some View {
        WorklightCard {
            sectionHeading(.detailPreviewHeading, identifier: Self.detailPreviewAccessibilityIdentifier)
            Text(localized(.immutableOriginal))
                .font(.subheadline)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(previews, id: \.evidenceID) { preview in
                previewCard(preview)
            }
        }
    }

    @ViewBuilder
    private var comparisonSection: some View {
        if let comparison {
            WorklightCard {
                sectionHeading(.comparisonHeading, identifier: Self.comparisonAccessibilityIdentifier)
                if comparison.mode == .advisoryOverlay {
                    Text(comparisonAdvisoryLabel(for: comparison.advisoryKey))
                        .font(.body)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(Self.overlayAdvisoryAccessibilityIdentifier)
                        .accessibilityLabel(Text("\(localized(.overlayAdvisory)) \(comparisonAdvisoryLabel(for: comparison.advisoryKey))"))
                }

                if comparison.orderedPreviews.count == EvidenceCurationLimitsV1.maximumComparisonCount {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: DesignTokens.Spacing.medium) {
                            comparisonPreview(comparison.orderedPreviews[0], label: .originalHeading, identifier: Self.originalAccessibilityIdentifier)
                            comparisonPreview(comparison.orderedPreviews[1], label: .referenceHeading, identifier: Self.referenceAccessibilityIdentifier)
                        }
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                            comparisonPreview(comparison.orderedPreviews[0], label: .originalHeading, identifier: Self.originalAccessibilityIdentifier)
                            comparisonPreview(comparison.orderedPreviews[1], label: .referenceHeading, identifier: Self.referenceAccessibilityIdentifier)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(
                        Text("\(localized(.comparisonHeading)). \(localized(.originalHeading)). \(localized(.referenceHeading)).")
                    )
                } else {
                    Text(localized(.missingReference))
                        .font(.body)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var markupSection: some View {
        WorklightCard {
            sectionHeading(.markupHeading, identifier: Self.markupControlsAccessibilityIdentifier)
            Text(localized(.accessibilityDescriptionHeading))
                .font(.headline)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityIdentifier(Self.accessibilityDescriptionAccessibilityIdentifier)
            Text(markupText)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            derivativeReadiness

            markupButton(.addArrowMarkup, action: approvedMarkupPlan == nil ? nil : onAddArrowMarkup)
            markupButton(.addCircleMarkup, action: approvedMarkupPlan == nil ? nil : onAddCircleMarkup)
            markupButton(.addTextMarkup, action: approvedMarkupPlan == nil ? nil : onAddTextMarkup)
            Button {
                onRemoveMarkup?()
            } label: {
                Text(localized(.removeMarkup))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .disabled(approvedMarkupPlan?.reviewedMarkup.orderedAnnotations.isEmpty != false || onRemoveMarkup == nil)
            .accessibilityIdentifier(Self.removeMarkupAccessibilityIdentifier)
            .accessibilityHint(localized(.immutableOriginal))
        }
    }

    @ViewBuilder
    private var sequenceSection: some View {
        if let sequencePlan = validatedSequencePlan {
            WorklightCard {
                sectionHeading(.sequenceHeading, identifier: Self.sequenceAccessibilityIdentifier)
                Text("\(localized(.reviewOrderHeading)): \(sequencePlan.orderedSources.count)")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .accessibilityIdentifier(Self.reviewOrderAccessibilityIdentifier)

                switch sequencePlan.kind {
                case .flicker:
                    flickerFrames(sequencePlan)
                case .contactSheet:
                    contactSheet(sequencePlan)
                }
            }
        }
    }

    private func previewCard(
        _ preview: EvidenceVersionPinnedPreviewV1
    ) -> some View {
        let metadata = sequenceItem(for: preview)
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                WorklightStatusBadge(
                    kind: preview.availability == .available ? .information : .blocked,
                    text: preview.availability == .available ? localized(.originalHeading) : localized(.missingReference)
                )
                previewText(preview)
                reviewMetadata(metadata, evidenceID: preview.evidenceID)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(previewAccessibilityLabel(preview)))

            if let metadata {
                curationActions(metadata)
            }
        }
        .accessibilityElement(children: .contain)
        .overlay {
            if differentiatesWithoutColor {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                    .stroke(DesignTokens.Colors.essentialControlStroke, lineWidth: 1)
            }
        }
    }

    private func curationActions(_ item: EvidenceSequenceItemV1) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Button {
                onRetake?(item)
            } label: {
                Text(localized(.retake))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .disabled(onRetake == nil)
            .accessibilityIdentifier(uniqueIdentifier(Self.retakeAccessibilityIdentifier, evidenceID: item.evidenceID))
            .accessibilityHint(localized(.retakeReviewRequired))

            Button {
                onRemoveFromWork?(item)
            } label: {
                Text(localized(.removeFromWork))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .disabled(onRemoveFromWork == nil)
            .accessibilityIdentifier(uniqueIdentifier(Self.removeFromWorkAccessibilityIdentifier, evidenceID: item.evidenceID))
            .accessibilityHint(localized(.removeHistoryDisclosure))

            Text(localized(.removeHistoryDisclosure))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DesignTokens.Spacing.small) {
                Button {
                    onMoveEarlier?(item)
                } label: {
                    Text(localized(.moveEarlier))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(item.ordinal == 0 || onMoveEarlier == nil)
                .accessibilityIdentifier(uniqueIdentifier(Self.moveEarlierAccessibilityIdentifier, evidenceID: item.evidenceID))

                Button {
                    onMoveLater?(item)
                } label: {
                    Text(localized(.moveLater))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(item.ordinal + 1 >= evidenceSequence.orderedItems.count || onMoveLater == nil)
                .accessibilityIdentifier(uniqueIdentifier(Self.moveLaterAccessibilityIdentifier, evidenceID: item.evidenceID))
            }
        }
    }

    private func comparisonPreview(
        _ preview: EvidenceVersionPinnedPreviewV1,
        label: EvidenceCurationLocalizationKeyV1,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(localized(label))
                .font(.headline)
                .foregroundStyle(DesignTokens.Colors.primaryText)
            previewText(preview)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(identifier)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(localized(label)). \(previewAccessibilityLabel(preview))"))
    }

    @ViewBuilder
    private func previewText(_ preview: EvidenceVersionPinnedPreviewV1) -> some View {
        if preview.availability == .missing {
            Text(preview.missingFallbackText ?? localized(.missingReference))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else if let detailCard = preview.availableBundle?.card {
            ForEach(detailCard.fields, id: \.fieldID) { field in
                Text("\(field.label): \(field.value)")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(detailCard.limitationsText)
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(localized(.immutableOriginal))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

    }

    @ViewBuilder
    private func reviewMetadata(
        _ item: EvidenceSequenceItemV1?,
        evidenceID: String
    ) -> some View {
        if let item {
            Text("\(localized(.reviewOrderHeading)): \(item.ordinal + 1)")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .accessibilityIdentifier(uniqueIdentifier(Self.reviewOrderAccessibilityIdentifier, evidenceID: evidenceID))
            Text("\(localized(.roleHeading)): \(roleLabel(item.role))")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .accessibilityIdentifier(uniqueIdentifier(Self.roleAccessibilityIdentifier, evidenceID: evidenceID))
            Text("\(localized(.captionHeading)): \(item.caption.text)")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(uniqueIdentifier(Self.captionAccessibilityIdentifier, evidenceID: evidenceID))
            if let description = item.accessibilityDescription?.text {
                Text("\(localized(.accessibilityDescriptionHeading)): \(description)")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(uniqueIdentifier(Self.accessibilityDescriptionAccessibilityIdentifier, evidenceID: evidenceID))
            }
        } else {
            Text(localized(.metadataUnavailable))
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func flickerFrames(_ plan: EvidenceSequencePlanV1) -> some View {
        if reduceMotion {
            Text(localized(.reducedMotion))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(Self.reducedMotionAccessibilityIdentifier)
        }
        ForEach(plan.metadataSequence.orderedItems, id: \.contentID) { item in
            Text("\(item.ordinal + 1) / \(plan.orderedSources.count)")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .accessibilityLabel(sequenceAccessibilityLabel(item, total: plan.orderedSources.count))
        }
    }

    private func contactSheet(_ plan: EvidenceSequencePlanV1) -> some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: DesignTokens.Spacing.small),
            count: plan.contactSheetColumns ?? 1
        )
        return LazyVGrid(columns: columns, spacing: DesignTokens.Spacing.small) {
            ForEach(plan.metadataSequence.orderedItems, id: \.contentID) { item in
                Text("\(item.ordinal + 1)")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.Control.minimumHitSize)
                    .background(DesignTokens.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard))
                    .accessibilityLabel(sequenceAccessibilityLabel(item, total: plan.orderedSources.count))
            }
        }
        .accessibilityIdentifier(Self.contactSheetAccessibilityIdentifier)
    }

    private func markupButton(
        _ key: EvidenceCurationLocalizationKeyV1,
        action: (() -> Void)?
    ) -> some View {
        Button {
            action?()
        } label: {
            Text(localized(key))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(WorklightSecondaryButtonStyle())
        .disabled(action == nil)
    }

    private func sectionHeading(
        _ key: EvidenceCurationLocalizationKeyV1,
        identifier: String
    ) -> some View {
        Text(localized(key))
            .font(.title3.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(identifier)
    }

    private func previewAccessibilityLabel(_ preview: EvidenceVersionPinnedPreviewV1) -> String {
        let metadata = sequenceItem(for: preview)
        let order = metadata.map { "\(localized(.reviewOrderHeading)) \($0.ordinal + 1). " } ?? ""
        let reviewedMetadata = metadata.map { item in
            let description = item.accessibilityDescription.map {
                " \(localized(.accessibilityDescriptionHeading)): \($0.text)."
            } ?? ""
            return "\(localized(.roleHeading)): \(roleLabel(item.role)). \(localized(.captionHeading)): \(item.caption.text).\(description)"
        } ?? localized(.metadataUnavailable)
        switch preview.availability {
        case .available:
            return "\(order)\(localized(.immutableOriginal)). \(reviewedMetadata)"
        case .missing:
            return "\(order)\(preview.missingFallbackText ?? localized(.missingReference)). \(reviewedMetadata)"
        }
    }

    @ViewBuilder
    private var derivativeReadiness: some View {
        let status = derivativeReadinessStatus
        Text(localized(status.localizationKey))
            .font(.footnote)
            .foregroundStyle(status == .visualReady ? DesignTokens.Colors.primaryText : DesignTokens.Colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(Self.visualDerivativeReadinessAccessibilityIdentifier)
    }

    private var derivativeReadinessStatus: DerivativeReadiness {
        guard let derivativePublication,
              derivativePublication.operation.state == .completed,
              derivativePublication.result.derivative.byteRole == .derivative else {
            return .unavailable
        }
        let mediaType = derivativePublication.result.derivative.mediaType
        return mediaType.hasPrefix("image/") || mediaType.hasPrefix("video/")
            ? .visualReady
            : .manifestReady
    }

    private func sequenceItem(for preview: EvidenceVersionPinnedPreviewV1) -> EvidenceSequenceItemV1? {
        guard let metadataSequence,
              metadataSequence.workspaceID.rawValue.uuidString.lowercased() == preview.reference.workspaceID else {
            return nil
        }
        return metadataSequence.orderedItems.first {
            $0.evidenceID == preview.evidenceID
                && $0.contentID == preview.reference.contentID
                && $0.associationBinding.resultingEvidenceRevision == preview.associationRevision
        }
    }

    private var validatedSequencePlan: EvidenceSequencePlanV1? {
        guard let sequencePlan else { return nil }
        do {
            try sequencePlan.validate()
            return sequencePlan
        } catch {
            return nil
        }
    }

    private var metadataSequence: EvidenceSequenceV1? {
        do {
            try evidenceSequence.validate()
        } catch {
            return nil
        }
        if let sequencePlan = validatedSequencePlan {
            guard evidenceSequence == sequencePlan.metadataSequence else {
                return nil
            }
            return sequencePlan.metadataSequence
        }
        return evidenceSequence
    }

    private func roleLabel(_ role: EvidenceRoleV1) -> String {
        switch role {
        case .context: return localized(.roleContext)
        case .detail: return localized(.roleDetail)
        case .before: return localized(.roleBefore)
        case .after: return localized(.roleAfter)
        case .other: return localized(.roleOther)
        }
    }

    private func uniqueIdentifier(_ base: String, evidenceID: String) -> String {
        "\(base).\(evidenceID)"
    }

    private func sequenceAccessibilityLabel(_ item: EvidenceSequenceItemV1, total: Int) -> String {
        let description = item.accessibilityDescription.map {
            " \(localized(.accessibilityDescriptionHeading)): \($0.text)."
        } ?? ""
        return "\(localized(.reviewOrderHeading)) \(item.ordinal + 1) / \(total). \(localized(.roleHeading)): \(roleLabel(item.role)). \(localized(.captionHeading)): \(item.caption.text).\(description)"
    }

    private var markupText: String {
        guard let markupPlan = approvedMarkupPlan,
              !markupPlan.reviewedMarkup.orderedAnnotations.isEmpty else {
            return localized(.noMarkup)
        }
        return markupPlan.reviewedMarkup.orderedAnnotations.joined(separator: "\n")
    }

    private var approvedMarkupPlan: EvidenceReviewedMarkupPlanV1? {
        guard let markupPlan,
              markupPlan.privacyReview.decision == .approved else {
            return nil
        }
        do {
            try markupPlan.validate()
            return markupPlan
        } catch {
            return nil
        }
    }

    private func comparisonAdvisoryLabel(
        for key: EvidenceComparisonAdvisoryKeyV1
    ) -> String {
        switch key {
        case .comparisonIsNotProof:
            return localized(.overlayAdvisory)
        }
    }

    private func localized(_ key: EvidenceCurationLocalizationKeyV1) -> String {
        BundledLocalizationCatalogV1.evidenceCurationLocalized(key)
    }

    private enum DerivativeReadiness {
        case visualReady
        case manifestReady
        case unavailable

        var localizationKey: EvidenceCurationLocalizationKeyV1 {
            switch self {
            case .visualReady: return .visualDerivativeReady
            case .manifestReady: return .derivativeManifestReady
            case .unavailable: return .visualDerivativeUnavailable
            }
        }
    }
}

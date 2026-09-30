import Foundation
import SwiftUI

/// Standalone C03 projection. It renders only validated C03/C37 facts and
/// exposes no writer, route, camera, or persistence authority.
struct IlluminatedSignPlaybookView: View {
    static let screenAccessibilityIdentifier = IlluminatedSignPlaybookAccessibilityIDV1.screen.rawValue
    static let playbooksAccessibilityIdentifier = IlluminatedSignPlaybookAccessibilityIDV1.playbooks.rawValue
    static let preflightAccessibilityIdentifier = IlluminatedSignPlaybookAccessibilityIDV1.preflight.rawValue
    static let afterDarkAccessibilityIdentifier = IlluminatedSignPlaybookAccessibilityIDV1.afterDark.rawValue
    static let safeAuthorizedPositionAccessibilityIdentifier = IlluminatedSignPlaybookAccessibilityIDV1.safeAuthorizedPosition.rawValue
    static let captureAccessibilityIdentifier = IlluminatedSignPlaybookAccessibilityIDV1.capture.rawValue
    static let wideCaptureAccessibilityIdentifier = IlluminatedSignPlaybookAccessibilityIDV1.wideCapture.rawValue
    static let closeCaptureAccessibilityIdentifier = IlluminatedSignPlaybookAccessibilityIDV1.closeCapture.rawValue
    static let workCaptureAccessibilityIdentifier = IlluminatedSignPlaybookAccessibilityIDV1.workCapture.rawValue
    static let poseAccessibilityIdentifier = IlluminatedSignPlaybookAccessibilityIDV1.pose.rawValue
    static let factsAccessibilityIdentifier = IlluminatedSignPlaybookAccessibilityIDV1.facts.rawValue
    static let disclaimerAccessibilityIdentifier = IlluminatedSignPlaybookAccessibilityIDV1.disclaimer.rawValue
    static let retakeDisclosureAccessibilityIdentifier = IlluminatedSignPlaybookAccessibilityIDV1.retakeDisclosure.rawValue
    static let offlineReadyAccessibilityIdentifier = IlluminatedSignPlaybookAccessibilityIDV1.offlineReady.rawValue
    static let blockedAccessibilityIdentifier = IlluminatedSignPlaybookAccessibilityIDV1.blocked.rawValue
    static let recoveryAccessibilityIdentifier = IlluminatedSignPlaybookAccessibilityIDV1.recovery.rawValue

    let coordinator: IlluminatedSignPlaybookCoordinatorV1
    let projection: IlluminatedSignPlaybookCheckpointProjectionV1
    /// C37 editor state is display-only. The view never turns it into a pose
    /// event or a checkpoint update.
    let poseEditorState: PlacementPoseEditorStateV1?
    let recovery: IlluminatedSignPlaybookRecoveryV1?

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize

    init(
        coordinator: IlluminatedSignPlaybookCoordinatorV1,
        projection: IlluminatedSignPlaybookCheckpointProjectionV1,
        poseEditorState: PlacementPoseEditorStateV1? = nil,
        recovery: IlluminatedSignPlaybookRecoveryV1? = nil
    ) {
        self.coordinator = coordinator
        self.projection = projection
        self.poseEditorState = poseEditorState
        self.recovery = recovery
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: contentSpacing) {
                statusCard
                playbookList
                preflight
                captureStatus
                poseStatus
                structuredFacts
                disclosures
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

    private var trustedProjection: IlluminatedSignPlaybookCheckpointProjectionV1? {
        do {
            try coordinator.registry.validate()
            try projection.validate()
            try projection.payload.validate(registry: coordinator.registry)
            guard try coordinator.completeness(of: projection.payload) == projection.completeness,
                  recovery == nil || validatedRecovery != nil else {
                return nil
            }
            return projection
        } catch {
            return nil
        }
    }

    private var validatedRecovery: IlluminatedSignPlaybookRecoveryV1? {
        guard let recovery else { return nil }
        do {
            try recovery.validate()
            guard recovery.projection == projection else { return nil }
            return recovery
        } catch {
            return nil
        }
    }

    private var selectedManifest: IlluminatedSignPlaybookManifestV1? {
        guard let trustedProjection else { return nil }
        return try? coordinator.registry.manifest(for: trustedProjection.payload.playbookID)
    }

    private var statusCard: some View {
        WorklightCard {
            switch trustedProjection?.completeness.state {
            case .some(.complete):
                WorklightStatusBadge(kind: .complete, text: localized(.offlineReady))
                Text(localized(.offlineReady))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .accessibilityIdentifier(Self.offlineReadyAccessibilityIdentifier)
            case .some(.couldNotVerify):
                WorklightStatusBadge(kind: .information, text: localized(.outcomeCouldNotVerify))
                Text(localized(.outcomeCouldNotVerify))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .accessibilityIdentifier(Self.offlineReadyAccessibilityIdentifier)
            case .some(.incomplete), .none:
                WorklightStatusBadge(kind: .blocked, text: localized(.blocked))
                Text(trustedProjection == nil ? localized(.recoveryRequired) : localized(.blocked))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Self.blockedAccessibilityIdentifier)
            }
            if validatedRecovery != nil {
                Text(localized(.recovered))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Self.recoveryAccessibilityIdentifier)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var playbookList: some View {
        WorklightCard {
            sectionHeading(.playbooksHeading, identifier: Self.playbooksAccessibilityIdentifier)
            ForEach(coordinator.registry.manifests, id: \.playbookID) { manifest in
                let isSelected = trustedProjection?.payload.playbookID == manifest.playbookID
                Text(playbookLabel(manifest.playbookID))
                    .font(isSelected ? .body.weight(.semibold) : .body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(
                        "\(playbookLabel(manifest.playbookID)). \(isSelected ? localized(.selectedPlaybook) : localized(.captureRequired))."
                    )
                    .accessibilityIdentifier(uniqueIdentifier(Self.playbooksAccessibilityIdentifier, suffix: manifest.playbookID.rawValue))
            }
        }
    }

    private var preflight: some View {
        WorklightCard {
            sectionHeading(.preflightHeading, identifier: Self.preflightAccessibilityIdentifier)
            Text(localized(.afterDark))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(Self.afterDarkAccessibilityIdentifier)
            Text(localized(.safeAuthorizedPosition))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(Self.safeAuthorizedPositionAccessibilityIdentifier)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var captureStatus: some View {
        if let manifest = selectedManifest, let trustedProjection {
            WorklightCard {
                sectionHeading(.captureHeading, identifier: Self.captureAccessibilityIdentifier)
                ForEach(manifest.captureRequirements, id: \.slotID) { requirement in
                    captureRow(requirement, payload: trustedProjection.payload)
                }
            }
        }
    }

    private func captureRow(
        _ requirement: IlluminatedSignCaptureRequirementV1,
        payload: IlluminatedSignPlaybookDraftPayloadV1
    ) -> some View {
        let present = payload.captures.contains { $0.slotID == requirement.slotID }
        return HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.small) {
            Text(captureLabel(requirement.slotID))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
            Spacer(minLength: DesignTokens.Spacing.small)
            Text(present ? localized(.captureComplete) : localized(.captureMissing))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(present ? DesignTokens.Colors.primaryText : DesignTokens.Colors.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(captureLabel(requirement.slotID)). \(requirement.required ? localized(.captureRequired) : localized(.workCapture)). \(present ? localized(.captureComplete) : localized(.captureMissing))."
        )
        .accessibilityIdentifier(captureIdentifier(requirement.slotID))
    }

    private var poseStatus: some View {
        WorklightCard {
            sectionHeading(.poseHeading, identifier: Self.poseAccessibilityIdentifier)
            if trustedProjection?.payload.poseTrace != nil {
                Text(localized(.poseReviewed))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if poseEditorState != nil {
                Text(localized(.poseReviewRequired))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(localized(.poseUnavailable))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var structuredFacts: some View {
        if let payload = trustedProjection?.payload {
            WorklightCard {
                sectionHeading(.factsHeading, identifier: Self.factsAccessibilityIdentifier)
                factRow(.stageLabel, stageLabel(payload.stage))
                factRow(.checkedTime, "\(payload.checkedTime.context.localDate) \(payload.checkedTime.context.localTime) (\(payload.checkedTime.context.timeZoneID))")
                if let outcome = payload.outcome {
                    factRow(.outcomeLabel, outcomeLabel(outcome))
                }
                if let selected = payload.selectedVisibleCondition {
                    factRow(.selectedCondition, selected.frozenDisplay)
                }
                if let couldNotVerify = payload.couldNotVerify {
                    factRow(.couldNotVerifyReason, couldNotVerify.frozenDisplay)
                }
                Text(localized(.visibleConditionsOnly))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(localized(.reportTrace))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private var disclosures: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            WorklightCard {
                Text(localized(.retakeDisclosure))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Self.retakeDisclosureAccessibilityIdentifier)
            }
            WorklightCard {
                Text(localized(.disclaimer))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(Self.disclaimerAccessibilityIdentifier)
            }
        }
    }

    private func factRow(
        _ key: IlluminatedSignPlaybookLocalizationKeyV1,
        _ value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(localized(key))
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
            Text(value)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func sectionHeading(
        _ key: IlluminatedSignPlaybookLocalizationKeyV1,
        identifier: String
    ) -> some View {
        Text(localized(key))
            .font(.title3.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(identifier)
    }

    private func playbookLabel(_ id: IlluminatedSignPlaybookIDV1) -> String {
        switch id {
        case .generalVisibleCondition: return localized(.generalVisibleCondition)
        case .darkSection: return localized(.darkSection)
        case .dimOrUneven: return localized(.dimOrUneven)
        case .flickerOrIntermittent: return localized(.flickerOrIntermittent)
        case .colorMismatch: return localized(.colorMismatch)
        case .physicalDamage: return localized(.physicalDamage)
        case .otherVisibleCondition: return localized(.otherVisibleCondition)
        }
    }

    private func captureLabel(_ slot: IlluminatedSignCaptureSlotIDV1) -> String {
        switch slot {
        case .wideContext: return localized(.wideCapture)
        case .closeDetail: return localized(.closeCapture)
        case .workContext: return localized(.workCapture)
        }
    }

    private func captureIdentifier(_ slot: IlluminatedSignCaptureSlotIDV1) -> String {
        switch slot {
        case .wideContext: return Self.wideCaptureAccessibilityIdentifier
        case .closeDetail: return Self.closeCaptureAccessibilityIdentifier
        case .workContext: return Self.workCaptureAccessibilityIdentifier
        }
    }

    private func stageLabel(_ value: IlluminatedSignPlaybookStageV1) -> String {
        switch value {
        case .check: return localized(.stageCheck)
        case .recheck: return localized(.stageRecheck)
        }
    }

    private func outcomeLabel(_ value: IlluminatedSignPlaybookOutcomeV1) -> String {
        switch value {
        case .noVisibleIssue: return localized(.outcomeNoVisibleIssue)
        case .visibleIssue: return localized(.outcomeVisibleIssue)
        case .couldNotVerify: return localized(.outcomeCouldNotVerify)
        }
    }

    private func uniqueIdentifier(_ base: String, suffix: String) -> String {
        "\(base).\(suffix)"
    }

    private func localized(_ key: IlluminatedSignPlaybookLocalizationKeyV1) -> String {
        BundledLocalizationCatalogV1.illuminatedSignPlaybookLocalized(key)
    }
}

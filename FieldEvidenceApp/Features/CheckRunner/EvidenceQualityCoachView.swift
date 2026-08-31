import SwiftUI

/// Presentation-only C10 quality coach. The embedding coordinator owns all
/// assessment, retake, waiver, and persistence effects. This view only renders
/// typed state and delegates an explicitly chosen action through injected closures.
struct EvidenceQualityCoachView: View {
    struct UserContent: Equatable, Sendable {
        /// Display-ready content supplied separately from system copy.
        let text: String
    }

    struct RuleWarning: Identifiable, Equatable, Sendable {
        let id: String
        let title: UserContent
        let explanation: UserContent
        let recordedInput: UserContent
        let threshold: UserContent
        let remedy: UserContent
        let ruleVersion: String
    }

    struct Limitation: Equatable, Sendable {
        let text: UserContent
        let required: Bool

        /// Limits a display-only limitation to a bounded local presentation.
        /// The coordinator remains responsible for any canonical validation.
        init?(text: UserContent, required: Bool) {
            guard !text.text.isEmpty, text.text.utf8.count <= 500 else { return nil }
            self.text = text
            self.required = required
        }
    }

    enum ClosedReason: String, CaseIterable, Identifiable, Sendable {
        case evidenceUnavailable
        case conditionsChanged
        case retakeNotPossible

        var id: String { rawValue }

        var localizationKey: EvidenceQualityCoachLocalizationKeyV1 {
            switch self {
            case .evidenceUnavailable: return .reasonEvidenceUnavailable
            case .conditionsChanged: return .reasonConditionsChanged
            case .retakeNotPossible: return .reasonRetakeNotPossible
            }
        }

        var requiresLimitation: Bool {
            self == .retakeNotPossible
        }
    }

    enum UnavailableState: Sendable {
        case unavailable
        case corrupt
        case stale
        case cancelled
        case protectedData
        case offline
        case storage

        var localizationKey: EvidenceQualityCoachLocalizationKeyV1 {
            switch self {
            case .unavailable: return .unavailable
            case .corrupt: return .unavailableCorrupt
            case .stale: return .unavailableStale
            case .cancelled: return .unavailableCancelled
            case .protectedData: return .unavailableProtected
            case .offline: return .unavailableOffline
            case .storage: return .unavailableStorage
            }
        }
    }

    enum ViewState: Sendable {
        case review(warnings: [RuleWarning], limitation: Limitation?)
        case unavailable(UnavailableState)
    }

    private enum FocusTarget: Hashable { case reason, actionError }

    static let screenAccessibilityIdentifier = EvidenceQualityCoachAccessibilityIDV1.screen.rawValue

    let state: ViewState
    let onRetake: (() -> Void)?
    let onAcceptWithReason: ((ClosedReason) -> Void)?
    let onCancel: (() -> Void)?

    @State private var selectedReason: ClosedReason?
    @State private var showsReasonError = false
    @FocusState private var focusTarget: FocusTarget?
    @AccessibilityFocusState private var accessibilityFocus: FocusTarget?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    init(
        state: ViewState,
        onRetake: (() -> Void)? = nil,
        onAcceptWithReason: ((ClosedReason) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.state = state
        self.onRetake = onRetake
        self.onAcceptWithReason = onAcceptWithReason
        self.onCancel = onCancel
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                heading
                switch state {
                case let .review(warnings, limitation): review(warnings: warnings, limitation: limitation)
                case let .unavailable(unavailable): unavailable(unavailable)
                }
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(localized(.heading))
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(EvidenceQualityCoachAccessibilityIDV1.heading.rawValue)
            Text(localized(.introduction))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            if reduceMotion {
                Text(localized(.reducedMotion))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
        }
    }

    private func review(warnings: [RuleWarning], limitation: Limitation?) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            ForEach(warnings) { warning in warningCard(warning) }
            actions(limitation: limitation)
        }
    }

    private func warningCard(_ warning: RuleWarning) -> some View {
        WorklightCard {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                Text(warning.title.text)
                    .font(.headline)
                    .accessibilityIdentifier(EvidenceQualityCoachAccessibilityIDV1.ruleWarning.rawValue + "." + warning.id)
                Text(warning.explanation.text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                fact(.input, warning.recordedInput.text, id: .ruleInput, warningID: warning.id)
                fact(.threshold, warning.threshold.text, id: .ruleThreshold, warningID: warning.id)
                fact(.remedy, warning.remedy.text, id: .ruleRemedy, warningID: warning.id)
                fact(.ruleVersion, warning.ruleVersion, id: .ruleVersion, warningID: warning.id)
            }
            .accessibilityElement(children: .contain)
        }
        .overlay {
            if differentiateWithoutColor {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                    .stroke(DesignTokens.Colors.essentialControlStroke, lineWidth: 1)
            }
        }
    }

    private func fact(
        _ key: EvidenceQualityCoachLocalizationKeyV1,
        _ value: String,
        id: EvidenceQualityCoachAccessibilityIDV1,
        warningID: String
    ) -> some View {
        Text("\(localized(key)): \(value)")
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(id.rawValue + "." + warningID)
    }

    private func actions(limitation: Limitation?) -> some View {
        WorklightCard {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                Button(action: { onRetake?() }) {
                    Text(localized(.retake)).frame(maxWidth: .infinity)
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .disabled(onRetake == nil)
                .accessibilityIdentifier(EvidenceQualityCoachAccessibilityIDV1.retake.rawValue)
                .accessibilityHint(localized(.retakeHint))

                Picker(localized(.reasonHeading), selection: $selectedReason) {
                    Text(localized(.reasonHeading)).tag(ClosedReason?.none)
                    ForEach(ClosedReason.allCases) { reason in
                        Text(localized(reason.localizationKey)).tag(Optional(reason))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier(EvidenceQualityCoachAccessibilityIDV1.reasonPicker.rawValue)
                .focused($focusTarget, equals: .reason)

                if let limitation, selectedReason?.requiresLimitation == true {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        Text(localized(.limitationHeading)).font(.headline)
                        Text(limitation.text.text).font(.body).fixedSize(horizontal: false, vertical: true)
                        if limitation.required { Text(localized(.limitationRequired)).font(.footnote) }
                    }
                    .accessibilityIdentifier(EvidenceQualityCoachAccessibilityIDV1.limitation.rawValue)
                }

                if showsReasonError {
                    Text(localized(.reasonRequired))
                        .font(.body.weight(.semibold))
                        .accessibilityIdentifier(EvidenceQualityCoachAccessibilityIDV1.actionError.rawValue)
                        .accessibilityFocused($accessibilityFocus, equals: .actionError)
                }

                Button(action: acceptWithReason) {
                    Text(localized(.acceptWithReason)).frame(maxWidth: .infinity)
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(onAcceptWithReason == nil || limitationMissingForSelectedReason(limitation))
                .accessibilityIdentifier(EvidenceQualityCoachAccessibilityIDV1.acceptWithReason.rawValue)
                .accessibilityHint(localized(.acceptWithReasonHint))

                Button(action: { onCancel?() }) {
                    Text(localized(.cancel)).frame(maxWidth: .infinity)
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(onCancel == nil)
                .accessibilityIdentifier(EvidenceQualityCoachAccessibilityIDV1.cancel.rawValue)
                .accessibilityHint(localized(.cancelHint))
                Text(localized(.originalPreserved))
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
        }
    }

    private func unavailable(_ unavailable: UnavailableState) -> some View {
        WorklightCard {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                Text(localized(.unavailableHeading)).font(.headline).accessibilityAddTraits(.isHeader)
                Text(localized(unavailable.localizationKey)).font(.body).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier(EvidenceQualityCoachAccessibilityIDV1.unavailable.rawValue)
        }
    }

    private func acceptWithReason() {
        guard let selectedReason else {
            showsReasonError = true
            focusTarget = .actionError
            accessibilityFocus = .actionError
            return
        }
        showsReasonError = false
        onAcceptWithReason?(selectedReason)
    }

    private func limitationMissingForSelectedReason(_ limitation: Limitation?) -> Bool {
        selectedReason?.requiresLimitation == true && limitation == nil
    }

    private func localized(_ key: EvidenceQualityCoachLocalizationKeyV1) -> String {
        BundledLocalizationCatalogV1.evidenceQualityCoachLocalized(key)
    }
}

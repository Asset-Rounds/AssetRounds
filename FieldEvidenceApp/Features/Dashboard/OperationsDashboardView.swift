import SwiftUI

/// A contained, non-adopted presentation of the C09 operations-metrics
/// projection. The owning coordinator supplies only display-safe values and
/// actions; this view never creates a metric, writer, or persistence route.
struct OperationsDashboardView: View {
    static let screenAccessibilityIdentifier = C09OperationsDashboardAccessibilityIDV1.screen.rawValue
    static let metricAccessibilityIdentifier = C09OperationsDashboardAccessibilityIDV1.metric.rawValue
    static let timelineAccessibilityIdentifier = C09OperationsDashboardAccessibilityIDV1.timeline.rawValue
    static let exposureAccessibilityIdentifier = C09OperationsDashboardAccessibilityIDV1.exposureReview.rawValue
    static let correctionAccessibilityIdentifier = C09OperationsDashboardAccessibilityIDV1.exposureCorrection.rawValue

    let model: OperationsDashboardPresentationModelV1
    let onReviewExposure: (() -> Void)?
    let onCorrectExposure: (() -> Void)?
    let onReviewMetricDetail: ((OperationsDashboardMetricPresentationV1) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var focusedMetricIndex: Int?

    init(
        model: OperationsDashboardPresentationModelV1,
        onReviewExposure: (() -> Void)? = nil,
        onCorrectExposure: (() -> Void)? = nil,
        onReviewMetricDetail: ((OperationsDashboardMetricPresentationV1) -> Void)? = nil
    ) {
        self.model = model
        self.onReviewExposure = onReviewExposure
        self.onCorrectExposure = onCorrectExposure
        self.onReviewMetricDetail = onReviewMetricDetail
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                Text(localized(.introduction))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                metricSection
                timelineSection
                exposureSection
            }
            .padding(.horizontal, DesignTokens.Spacing.medium)
            .padding(.vertical, DesignTokens.Spacing.medium)
        }
        .navigationTitle(localized(.heading))
        .navigationBarTitleDisplayMode(.inline)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
        .onAppear {
            focusedMetricIndex = model.metrics.firstIndex { $0.qualifiedValue == nil }
        }
    }

    private var spacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? DesignTokens.Spacing.large : DesignTokens.Spacing.medium
    }

    private var metricSection: some View {
        WorklightCard {
            Text(localized(.metricsHeading))
                .font(.headline)
                .foregroundStyle(DesignTokens.Colors.primaryText)

            ForEach(Array(model.metrics.enumerated()), id: \.element.id) { index, metric in
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    Text(localized(metric.kind.localizationKey))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                    LabeledContent(localized(.definitionVersion)) {
                        Text(metric.definitionVersion.formatted())
                    }
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)

                    if let qualifiedValue = metric.qualifiedValue {
                        Text(qualifiedValue.displayText)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(DesignTokens.Colors.primaryText)
                            .accessibilityLabel(Text("\(localized(metric.kind.localizationKey)): \(qualifiedValue.displayText)"))
                    } else {
                        Text(localized(.metricUnavailable))
                            .font(.body)
                            .foregroundStyle(DesignTokens.Colors.attentionText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(localized(metric.unavailableReason?.localizationKey ?? .unavailableNoReason))
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.Colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(Text("\(localized(metric.kind.localizationKey)): \(localized(.metricUnavailable)). \(localized(metric.unavailableReason?.localizationKey ?? .unavailableNoReason))"))
                    }

                    if let onReviewMetricDetail {
                        Button {
                            onReviewMetricDetail(metric)
                        } label: {
                            Text(localized(.reviewMetricDetails))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .accessibilityHint(Text(localized(.reviewMetricDetailsHint)))
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(Self.metricAccessibilityIdentifier + "." + String(index))
                .accessibilityFocused($focusedMetricIndex, equals: index)
            }
        }
    }

    private var timelineSection: some View {
        WorklightCard {
            Text(localized(.timelineHeading))
                .font(.headline)
                .foregroundStyle(DesignTokens.Colors.primaryText)

            if model.timeline.isEmpty {
                Text(localized(.timelineEmpty))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(model.timeline) { entry in
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        Text(localized(entry.event.localizationKey))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(DesignTokens.Colors.primaryText)
                        Text(localized(entry.provenance.localizationKey))
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.Colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if let assetDisplayName = entry.assetDisplayName {
                            LabeledContent(localized(.assetName)) {
                                Text(assetDisplayName)
                                    .multilineTextAlignment(.trailing)
                            }
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.Colors.secondaryText)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .accessibilityIdentifier(Self.timelineAccessibilityIdentifier)
    }

    private var exposureSection: some View {
        WorklightCard {
            Text(localized(.exposureHeading))
                .font(.headline)
                .foregroundStyle(DesignTokens.Colors.primaryText)
            Text(localized(model.exposure.state.localizationKey))
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let reason = model.exposure.unavailableReason {
                Text(localized(reason.localizationKey))
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.Colors.attentionText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let onReviewExposure {
                Button {
                    onReviewExposure()
                } label: {
                    Text(localized(.reviewExposure))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityHint(Text(localized(.reviewExposureHint)))
            }

            if model.exposure.correctionAvailable, let onCorrectExposure {
                Button {
                    onCorrectExposure()
                } label: {
                    Text(localized(.correctExposure))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .accessibilityHint(Text(localized(.correctExposureHint)))
                .accessibilityIdentifier(Self.correctionAccessibilityIdentifier)
            }
        }
        .accessibilityIdentifier(Self.exposureAccessibilityIdentifier)
    }

    private func localized(_ key: C09OperationsDashboardLocalizationKeyV1) -> String {
        BundledLocalizationCatalogV1.operationsDashboardLocalized(key)
    }
}

/// Display-only values are deliberately supplied by the C09 coordinator. All
/// system text is a closed typed state; only `assetDisplayName` may contain
/// user-authored content, and it is isolated under its own label.
struct OperationsDashboardPresentationModelV1: Equatable, Sendable {
    let metrics: [OperationsDashboardMetricPresentationV1]
    let timeline: [OperationsDashboardTimelinePresentationV1]
    let exposure: OperationsDashboardExposurePresentationV1
}

struct OperationsDashboardMetricPresentationV1: Identifiable, Equatable, Sendable {
    let id: Int
    let kind: OperationsDashboardMetricKindV1
    let definitionVersion: Int
    let qualifiedValue: OperationsDashboardMetricValueV1?
    let unavailableReason: OperationsDashboardUnavailableReasonV1?
}

struct OperationsDashboardTimelinePresentationV1: Identifiable, Equatable, Sendable {
    let id: Int
    let event: OperationsDashboardTimelineEventV1
    let provenance: OperationsDashboardProvenanceV1
    let assetDisplayName: String?
}

struct OperationsDashboardExposurePresentationV1: Equatable, Sendable {
    let state: OperationsDashboardExposureStateV1
    let unavailableReason: OperationsDashboardUnavailableReasonV1?
    let correctionAvailable: Bool
}

enum OperationsDashboardMetricKindV1: Equatable, Sendable {
    case meanTimeBetweenFailures
    case fullInterruptionAvailability

    var localizationKey: C09OperationsDashboardLocalizationKeyV1 {
        switch self {
        case .meanTimeBetweenFailures: .metricMTBF
        case .fullInterruptionAvailability: .metricFullInterruptionAvailability
        }
    }
}

struct OperationsDashboardMetricValueV1: Equatable, Sendable {
    let numerator: UInt64
    let denominator: UInt64

    var displayText: String { "\(numerator.formatted()) / \(denominator.formatted())" }
}

enum OperationsDashboardUnavailableReasonV1: Equatable, Sendable {
    case cancelled
    case missingCoverage
    case missingQualifiedExposure
    case noQualifyingFailureStart
    case protectedDataUnavailable
    case unavailableData

    var localizationKey: C09OperationsDashboardLocalizationKeyV1 {
        switch self {
        case .cancelled: .unavailableCancelled
        case .missingCoverage: .unavailableMissingCoverage
        case .missingQualifiedExposure: .unavailableMissingQualifiedExposure
        case .noQualifyingFailureStart: .unavailableNoQualifyingFailureStart
        case .protectedDataUnavailable: .unavailableProtectedData
        case .unavailableData: .unavailableData
        }
    }
}

enum OperationsDashboardTimelineEventV1: Equatable, Sendable {
    case incident
    case impactSegment
    case qualifiedExposure
    case inspection
    case finding
    case correctiveWork
    case recheck
    case report
    case evidenceAssociation
    case explicitAssetChange
    case placementChange

    /// Deliberately exhaustive over the canonical history kind. Adding a new
    /// domain kind requires a corresponding local presentation decision.
    static func presentation(
        for historyKind: AssetServiceHistoryEventKindV1
    ) -> OperationsDashboardTimelineEventV1 {
        switch historyKind {
        case .incident: .incident
        case .impactSegment: .impactSegment
        case .qualifiedExposure: .qualifiedExposure
        case .inspection: .inspection
        case .finding: .finding
        case .correctiveWork: .correctiveWork
        case .recheck: .recheck
        case .report: .report
        case .evidenceAssociation: .evidenceAssociation
        case .explicitAssetChange: .explicitAssetChange
        case .placementChange: .placementChange
        }
    }

    var localizationKey: C09OperationsDashboardLocalizationKeyV1 {
        switch self {
        case .incident: .timelineIncident
        case .impactSegment: .timelineImpactSegment
        case .qualifiedExposure: .timelineQualifiedExposure
        case .inspection: .timelineInspection
        case .finding: .timelineFinding
        case .correctiveWork: .timelineCorrectiveWork
        case .recheck: .timelineRecheck
        case .report: .timelineReport
        case .evidenceAssociation: .timelineEvidenceAssociation
        case .explicitAssetChange: .timelineExplicitAssetChange
        case .placementChange: .timelinePlacementChange
        }
    }
}

enum OperationsDashboardProvenanceV1: Equatable, Sendable {
    case corrected
    case recorded
    case superseded

    var localizationKey: C09OperationsDashboardLocalizationKeyV1 {
        switch self {
        case .corrected: .provenanceCorrected
        case .recorded: .provenanceRecorded
        case .superseded: .provenanceSuperseded
        }
    }
}

enum OperationsDashboardExposureStateV1: Equatable, Sendable {
    case qualified
    case unavailable

    var localizationKey: C09OperationsDashboardLocalizationKeyV1 {
        switch self {
        case .qualified: .exposureQualified
        case .unavailable: .exposureUnavailable
        }
    }
}

import SwiftUI

struct PackSampleView: View {
    static let scrollAccessibilityIdentifier = "s1.sample.scroll"
    static let disclaimerAccessibilityIdentifier = "s1.sample.disclaimer"

    let pack: SignPack

    var body: some View {
        AssetRoundsScreenFoundation {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.space16) {
                    identityCard
                    nounsCard
                    evidenceCard
                    acknowledgementsCard
                    registryCard(title: "Visible issue labels", entries: pack.issueLabels)
                    couldNotVerifyCard
                    registryCard(title: "Stages", entries: pack.stageDisplays)
                    registryCard(title: "Outcomes", entries: pack.outcomeDisplays)
                    disclaimerCard
                }
            }
            .modifier(SampleBottomScrollEdgeEffect())
        }
        .accessibilityIdentifier(Self.scrollAccessibilityIdentifier)
    }

    private var identityCard: some View {
        AssetRoundsEvidenceCard {
            AssetRoundsReportBrandHeader(
                title: Text("Illuminated sign pack"),
                symbolRendering: .original
            )
            SampleValue(label: "Pack ID", value: pack.packID)
            SampleValue(label: "Schema version", value: String(pack.schemaVersion))
            SampleValue(label: "Content version", value: String(pack.contentVersion))
        }
    }

    private var nounsCard: some View {
        AssetRoundsEvidenceCard {
            sectionTitle("Nouns")
            SampleValue(
                label: "Asset",
                value: "\(pack.nouns.asset.singular) / \(pack.nouns.asset.plural)"
            )
            SampleValue(
                label: "Check",
                value: "\(pack.nouns.check.singular) / \(pack.nouns.check.plural)"
            )
            SampleValue(
                label: "Issue",
                value: "\(pack.nouns.issue.singular) / \(pack.nouns.issue.plural)"
            )
        }
    }

    private var evidenceCard: some View {
        AssetRoundsEvidenceCard {
            sectionTitle("Evidence purposes")
            ForEach(pack.evidencePurposes) { purpose in
                SampleRegistryRow(
                    key: purpose.key,
                    display: purpose.display,
                    detail: purpose.instruction
                )
            }
        }
    }

    private var acknowledgementsCard: some View {
        AssetRoundsEvidenceCard {
            sectionTitle("Preflight acknowledgements")
            ForEach(pack.acknowledgements) { acknowledgement in
                SampleRegistryRow(
                    key: acknowledgement.key,
                    display: acknowledgement.copy,
                    detail: acknowledgement.version
                )
            }
        }
    }

    private var couldNotVerifyCard: some View {
        AssetRoundsEvidenceCard {
            sectionTitle("Could not verify")
            SampleValue(label: "Registry version", value: pack.couldNotVerifyReasons.version)
            ForEach(pack.couldNotVerifyReasons.entries) { entry in
                SampleRegistryRow(key: entry.key, display: entry.display)
            }
        }
    }

    private var disclaimerCard: some View {
        AssetRoundsEvidenceCard {
            sectionTitle("Report disclaimer")
            Text(pack.disclaimer)
                .font(DesignTokens.Typography.primaryBody)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(Self.disclaimerAccessibilityIdentifier)
        }
    }

    private func registryCard(title: String, entries: [SignPack.RegistryEntry]) -> some View {
        AssetRoundsEvidenceCard {
            sectionTitle(title)
            ForEach(entries) { entry in
                SampleRegistryRow(key: entry.key, display: entry.display)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(DesignTokens.Typography.sectionHeading)
            .foregroundStyle(DesignTokens.SemanticColors.brandHeading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct SampleBottomScrollEdgeEffect: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.hard, for: .bottom)
        } else {
            content
        }
    }
}

private struct SampleValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space8) {
            Text(label)
                .font(DesignTokens.Typography.supportingCaption.weight(.semibold))
                .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(value)
                .font(DesignTokens.Typography.primaryBody)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DesignTokens.Spacing.space8)
        .accessibilityElement(children: .combine)
    }
}

private struct SampleRegistryRow: View {
    let key: String
    let display: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space8) {
            Text(display)
                .font(DesignTokens.Typography.primaryBody.weight(.medium))
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(key)
                .font(DesignTokens.Typography.numericOrTimestamp)
                .foregroundStyle(DesignTokens.SemanticColors.primaryAction)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if let detail {
                Text(detail)
                    .font(DesignTokens.Typography.secondaryBody)
                    .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.space8)
        .accessibilityElement(children: .combine)
    }
}

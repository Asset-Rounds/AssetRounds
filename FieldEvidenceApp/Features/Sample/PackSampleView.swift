import SwiftUI

struct PackSampleView: View {
    static let scrollAccessibilityIdentifier = "s1.sample.scroll"
    static let disclaimerAccessibilityIdentifier = "s1.sample.disclaimer"

    let pack: SignPack

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
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
            .padding(DesignTokens.Spacing.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.scrollAccessibilityIdentifier)
    }

    private var identityCard: some View {
        WorklightCard {
            sectionTitle("Illuminated sign pack")
            SampleValue(label: "Pack ID", value: pack.packID)
            SampleValue(label: "Schema version", value: String(pack.schemaVersion))
            SampleValue(label: "Content version", value: String(pack.contentVersion))
        }
    }

    private var nounsCard: some View {
        WorklightCard {
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
        WorklightCard {
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
        WorklightCard {
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
        WorklightCard {
            sectionTitle("Could not verify")
            SampleValue(label: "Registry version", value: pack.couldNotVerifyReasons.version)
            ForEach(pack.couldNotVerifyReasons.entries) { entry in
                SampleRegistryRow(key: entry.key, display: entry.display)
            }
        }
    }

    private var disclaimerCard: some View {
        WorklightCard {
            sectionTitle("Report disclaimer")
            Text(pack.disclaimer)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(Self.disclaimerAccessibilityIdentifier)
        }
    }

    private func registryCard(title: String, entries: [SignPack.RegistryEntry]) -> some View {
        WorklightCard {
            sectionTitle(title)
            ForEach(entries) { entry in
                SampleRegistryRow(key: entry.key, display: entry.display)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct SampleValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(value)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DesignTokens.Spacing.small)
        .accessibilityElement(children: .combine)
    }
}

private struct SampleRegistryRow: View {
    let key: String
    let display: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(display)
                .font(.body.weight(.medium))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(key)
                .font(.caption.monospaced())
                .foregroundStyle(DesignTokens.Colors.interactionAccent)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.small)
        .accessibilityElement(children: .combine)
    }
}

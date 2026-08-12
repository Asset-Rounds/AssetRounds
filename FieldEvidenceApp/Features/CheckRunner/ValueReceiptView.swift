import SwiftUI

struct ValueReceiptView: View {
    static let screenAccessibilityIdentifier = "s3.receipt.screen"
    static let savedAccessibilityIdentifier = "s3.receipt.saved"
    static let viewReportAccessibilityIdentifier = "s3.receipt.view-report"
    static let shareAccessibilityIdentifier = "s3.receipt.share"
    static let doneAccessibilityIdentifier = "s3.receipt.done"

    let result: FinalizationResult
    let coordinator: CheckRunnerCoordinator

    @Environment(\.dismiss) private var dismiss
    @State private var didPresent = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            WorklightCard {
                WorklightStatusBadge(kind: .complete, text: "Check complete")
                Text("Report saved on this device.")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(Self.savedAccessibilityIdentifier)

                Text("Your photos and check details are stored locally. Report viewing and sharing are not available yet.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("View Report") {}
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(true)
                .accessibilityHint("Unavailable until S4.3")
                .accessibilityIdentifier(Self.viewReportAccessibilityIdentifier)

            Button("Share") {}
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(true)
                .accessibilityHint("Unavailable until S4.3")
                .accessibilityIdentifier(Self.shareAccessibilityIdentifier)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(WorklightPrimaryButtonStyle())
            .accessibilityIdentifier(Self.doneAccessibilityIdentifier)
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle("Saved")
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .task {
            guard !didPresent else { return }
            didPresent = true
            await coordinator.valueReceiptDidPresent()
        }
    }
}

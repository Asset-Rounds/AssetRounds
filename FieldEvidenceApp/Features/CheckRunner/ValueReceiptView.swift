import SwiftUI

struct ValueReceiptView: View {
    static let screenAccessibilityIdentifier = "s3.receipt.screen"
    static let savedAccessibilityIdentifier = "s3.receipt.saved"
    static let viewReportAccessibilityIdentifier = "s3.receipt.view-report"
    static let shareAccessibilityIdentifier = "s3.receipt.share"
    static let doneAccessibilityIdentifier = "s3.receipt.done"
    static let deliveryErrorAccessibilityIdentifier = "s4.3.receipt.delivery-error"

    let result: FinalizationResult
    let coordinator: CheckRunnerCoordinator

    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var isSavedMessageFocused: Bool
    @State private var didPresent = false
    @State private var didPrepareDelivery = false
    @State private var delivery: ReportDeliveryValue?
    @State private var deliveryCoordinator: ReportDeliveryCoordinator?
    @State private var deliveryUnavailable = false
    @State private var showsReport = false
    @State private var showsShareSheet = false

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
                        .accessibilityFocused($isSavedMessageFocused)

                    statusText
                }

                if delivery != nil {
                    Button("View report") {
                        showsReport = true
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityHint("Opens the report PDF stored on this device")
                    .accessibilityIdentifier(Self.viewReportAccessibilityIdentifier)

                    Button("Share PDF") {
                        showsShareSheet = true
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityHint("Opens the system share sheet for this report PDF")
                    .accessibilityIdentifier(Self.shareAccessibilityIdentifier)
                } else if !deliveryUnavailable {
                    ProgressView("Preparing report PDF")
                        .frame(maxWidth: .infinity, minHeight: DesignTokens.Control.minimumHitSize)
                        .accessibilityIdentifier("s4.3.receipt.preparing")
                }

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .accessibilityHint("Returns to this sign")
                .accessibilityIdentifier(Self.doneAccessibilityIdentifier)
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle("Saved")
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .navigationDestination(isPresented: $showsReport) {
            if let delivery, let deliveryCoordinator {
                ReportDetailView(
                    delivery: delivery,
                    coordinator: deliveryCoordinator
                )
            }
        }
        .sheet(isPresented: $showsShareSheet) {
            if let delivery, let deliveryCoordinator {
                ReportShareSheet(
                    delivery: delivery,
                    coordinator: deliveryCoordinator
                )
            }
        }
        .task {
            guard !didPresent else { return }
            didPresent = true
            await coordinator.valueReceiptDidPresent()
            isSavedMessageFocused = true
        }
        .task {
            guard !didPrepareDelivery else { return }
            didPrepareDelivery = true
            do {
                let preparedCoordinator = try coordinator.makeReportDeliveryCoordinator()
                deliveryCoordinator = preparedCoordinator
                switch try coordinator.prepareReportDelivery(result: result) {
                case let .ready(value):
                    delivery = value
                case .failed:
                    deliveryUnavailable = true
                }
            } catch {
                deliveryUnavailable = true
            }
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if delivery != nil {
            receiptStatus("Your report PDF is ready to view, share, or save to Files.")
        } else if deliveryUnavailable {
            receiptStatus("Your report is saved on this device, but its PDF is not ready.")
                .accessibilityIdentifier(Self.deliveryErrorAccessibilityIdentifier)
        } else {
            receiptStatus("Your photos and check details are stored locally.")
        }
    }

    private func receiptStatus(_ copy: String) -> some View {
        Text(copy)
            .font(.body)
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

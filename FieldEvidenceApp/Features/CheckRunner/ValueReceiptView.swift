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
                    WorklightStatusBadge(kind: .complete, text: BundledLocalizationCatalogV1.v30Text(.receiptCheckCompleteBadge))

                    Text(BundledLocalizationCatalogV1.v30Text(.receiptReportSavedHeading))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(Self.savedAccessibilityIdentifier)
                        .accessibilityFocused($isSavedMessageFocused)

                    statusText
                }

                if delivery != nil {
                    Button(BundledLocalizationCatalogV1.v30Text(.receiptViewReportAction)) {
                        showsReport = true
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.receiptViewReportAccessibilityHint))
                    .accessibilityIdentifier(Self.viewReportAccessibilityIdentifier)

                    Button(BundledLocalizationCatalogV1.v30Text(.receiptSharePDFAction)) {
                        showsShareSheet = true
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.receiptSharePDFAccessibilityHint))
                    .accessibilityIdentifier(Self.shareAccessibilityIdentifier)
                } else if !deliveryUnavailable {
                    ProgressView(BundledLocalizationCatalogV1.v30Text(.receiptPreparingReportPDF))
                        .frame(maxWidth: .infinity, minHeight: DesignTokens.Control.minimumHitSize)
                        .accessibilityIdentifier("s4.3.receipt.preparing")
                }

                Button(BundledLocalizationCatalogV1.v30Text(.receiptDoneAction)) {
                    dismiss()
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.receiptDoneAccessibilityHint))
                .accessibilityIdentifier(Self.doneAccessibilityIdentifier)
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.receiptSavedNavigationTitle))
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
            receiptStatus(BundledLocalizationCatalogV1.v30Text(.receiptPDFReadyStatus))
        } else if deliveryUnavailable {
            receiptStatus(BundledLocalizationCatalogV1.v30Text(.receiptPDFNotReadyStatus))
                .accessibilityIdentifier(Self.deliveryErrorAccessibilityIdentifier)
        } else {
            receiptStatus(BundledLocalizationCatalogV1.v30Text(.receiptPhotosStoredLocallyStatus))
        }
    }

    private func receiptStatus(_ copy: String) -> some View {
        Text(copy)
            .font(.body)
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

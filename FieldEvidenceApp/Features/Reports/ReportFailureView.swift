import Foundation
import SwiftUI

/// The bounded S4.2 delivery-failure surface. It intentionally describes only
/// the unavailable local PDF and offers the single explicit recovery action;
/// report detail, preview, sharing, and Files stay unavailable until S4.3.
struct ReportFailureView: View {
    static let screenAccessibilityIdentifier = "s4.pdf-failure.screen"
    static let headlineAccessibilityIdentifier = "s4.pdf-failure.headline"
    static let retryAccessibilityIdentifier = "s4.pdf-failure.retry"

    @ObservedObject var recovery: ReportRecoveryService
    let onUnsafeRecovery: @MainActor () -> Void

    @State private var activeRetryReportID: UUID?
    @State private var isRetrying = false
    @AccessibilityFocusState private var isFailureHeadlineFocused: Bool

    init(
        recovery: ReportRecoveryService,
        onUnsafeRecovery: @escaping @MainActor () -> Void
    ) {
        self.recovery = recovery
        self.onUnsafeRecovery = onUnsafeRecovery
    }

    var body: some View {
        if let reportID = displayedReportID {
            ZStack {
                DesignTokens.Colors.canvas
                    .opacity(0.96)
                    .ignoresSafeArea()

                ScrollView {
                    WorklightCard {
                        WorklightStatusBadge(
                            kind: .blocked,
                            text: BundledLocalizationCatalogV1.v30Text(.reportFailureReportFailure)
                        )

                        Text(BundledLocalizationCatalogV1.v30Text(.reportFailureReportFailure2))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(DesignTokens.Colors.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityFocused($isFailureHeadlineFocused)
                            .accessibilityIdentifier(
                                Self.headlineAccessibilityIdentifier
                            )

                        Text(BundledLocalizationCatalogV1.v30Text(.reportFailureCheckRetry))
                            .font(.body)
                            .foregroundStyle(DesignTokens.Colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(isRetryInProgress ? BundledLocalizationCatalogV1.v30Text(.reportFailureReportRetry) : BundledLocalizationCatalogV1.v30Text(.reportFailureReportRetry2)) {
                            retryReport(id: reportID)
                        }
                        .buttonStyle(WorklightPrimaryButtonStyle())
                        .disabled(isRetryInProgress)
                        .accessibilityLabel(
                            isRetryInProgress
                                ? BundledLocalizationCatalogV1.v30Text(.reportFailureReportRetry3)
                                : BundledLocalizationCatalogV1.v30Text(.reportFailureReportRetry2)
                        )
                        .accessibilityHint(
                            isRetryInProgress
                                ? BundledLocalizationCatalogV1.v30Text(.reportFailureReportRetry4)
                                : BundledLocalizationCatalogV1.v30Text(.reportFailureReportLabel)
                        )
                        .accessibilityIdentifier(Self.retryAccessibilityIdentifier)
                    }
                    .padding(DesignTokens.Spacing.medium)
                }
            }
            .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
            .onAppear {
                focusFailureHeadline()
            }
            .onChange(of: failedReportID) { _, newValue in
                if newValue != nil, !isRetrying {
                    focusFailureHeadline()
                }
            }
        }
    }

    /// A report moves to pending before its render attempt. Pinning the report
    /// ID prevents the query's temporary absence from dismissing the surface
    /// or enabling a second tap while that one bounded attempt is in flight.
    private var displayedReportID: UUID? {
        activeRetryReportID ?? failedReportID
    }

    private var failedReportID: UUID? {
        recovery.failedReportIDs.first
    }

    private var isRetryInProgress: Bool {
        isRetrying || recovery.isRetrying
    }

    private func retryReport(id reportID: UUID) {
        guard !isRetryInProgress else { return }

        activeRetryReportID = reportID
        isRetrying = true
        Task { @MainActor in
            let becameReady: Bool
            do {
                switch try await recovery.retryFailedReport(id: reportID) {
                case .ready:
                    becameReady = true
                case .failed:
                    becameReady = false
                }
            } catch {
                onUnsafeRecovery()
                becameReady = false
            }
            isRetrying = false
            activeRetryReportID = nil
            if !becameReady {
                focusFailureHeadline()
            }
        }
    }

    private func focusFailureHeadline() {
        DispatchQueue.main.async {
            isFailureHeadlineFocused = true
        }
    }
}

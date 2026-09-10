import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FeedbackView: View {
    static let settingsEntryAccessibilityIdentifier = "s8.4.feedback.settings-entry"
    static let screenAccessibilityIdentifier = "s8.4.feedback.screen"
    static let headingAccessibilityIdentifier = "s8.4.feedback.heading"
    static let privacyAccessibilityIdentifier = "s8.4.feedback.privacy"
    static let reviewAccessibilityIdentifier = "s8.4.feedback.review"
    static let consentAccessibilityIdentifier = "s8.4.feedback.consent"
    static let attachAccessibilityIdentifier = "s8.4.feedback.attach"
    static let doNotAttachAccessibilityIdentifier = "s8.4.feedback.do-not-attach"
    static let copyAddressAccessibilityIdentifier = "s8.4.feedback.copy-address"
    static let saveDiagnosticsAccessibilityIdentifier = "s8.4.feedback.save-diagnostics"
    static let retryAccessibilityIdentifier = "s8.4.feedback.retry"
    static let statusAccessibilityIdentifier = "s8.4.feedback.status"

    private struct MailPresentation: Identifiable {
        let id = UUID()
        let draft: FeedbackMailDraftV1
    }

    private let configuration: FeedbackConfigurationV1
    private let mailComposer: MailComposerAdapter
    private let diagnosticService: DiagnosticExportService

    @State private var prepared: PreparedDiagnosticExportV1?
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var mailPresentation: MailPresentation?
    @State private var showsExporter = false
    @State private var didPrepare = false

    @MainActor
    init(
        diagnosticsStore: DiagnosticsStore,
        metricKitAdapter: MetricKitDiagnosticsAdapter,
        configuration: FeedbackConfigurationV1,
        mailComposer: MailComposerAdapter
    ) {
        self.configuration = configuration
        self.mailComposer = mailComposer
        diagnosticService = DiagnosticExportService(
            diagnosticsStore: diagnosticsStore,
            metricKitAdapter: metricKitAdapter
        )
    }

    var body: some View {
        ScrollView {
            WorklightCard {
                Text(BundledLocalizationCatalogV1.v30Text(.feedbackFeedbackLabel))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(Self.headingAccessibilityIdentifier)

                Text(
                    BundledLocalizationCatalogV1.v30Text(.feedbackFeedbackLabel2)
                )
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(Self.privacyAccessibilityIdentifier)

                if let prepared {
                    diagnosticReview(prepared)
                    routeControls(prepared)
                } else if let errorMessage {
                    WorklightStatusBadge(
                        kind: .blocked,
                        text: errorMessage
                    )
                    Button(BundledLocalizationCatalogV1.v30Text(.feedbackFeedbackRetry)) {
                        Task { await prepare(force: true) }
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityIdentifier(Self.retryAccessibilityIdentifier)
                } else {
                    ProgressView(BundledLocalizationCatalogV1.v30Text(.feedbackFeedbackProgress))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if prepared != nil, let errorMessage {
                    WorklightStatusBadge(kind: .blocked, text: errorMessage)
                }

                if let statusMessage {
                    WorklightStatusBadge(kind: .complete, text: statusMessage)
                        .accessibilityIdentifier(Self.statusAccessibilityIdentifier)
                }
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.feedbackFeedbackNavigation))
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .sheet(item: $mailPresentation) { presentation in
            MailComposerSheet(
                adapter: mailComposer,
                draft: presentation.draft
            ) { result in
                mailPresentation = nil
                switch result {
                case .cancelled:
                    statusMessage = BundledLocalizationCatalogV1.v30Text(.feedbackFeedbackLabel3)
                case .failed:
                    statusMessage = nil
                    errorMessage = BundledLocalizationCatalogV1.v30Text(.feedbackFeedbackFailure)
                case .saved:
                    statusMessage = BundledLocalizationCatalogV1.v30Text(.feedbackFeedbackLabel4)
                case .sent:
                    statusMessage = BundledLocalizationCatalogV1.v30Text(.feedbackFeedbackLabel5)
                }
            }
        }
        .fileExporter(
            isPresented: $showsExporter,
            document: prepared.map {
                DiagnosticJSONDocument(data: $0.canonicalData)
            },
            contentType: .json,
            defaultFilename: "FieldEvidence-Diagnostics"
        ) { result in
            switch result {
            case .success:
                errorMessage = nil
                statusMessage = BundledLocalizationCatalogV1.v30Text(.feedbackDiagnosticLabel)
            case let .failure(error):
                if (error as? CocoaError)?.code == .userCancelled {
                    return
                }
                statusMessage = nil
                errorMessage = BundledLocalizationCatalogV1.v30Text(.feedbackDiagnosticFailure)
            }
        }
        .task {
            await prepare(force: false)
        }
    }

    @ViewBuilder
    private func diagnosticReview(
        _ prepared: PreparedDiagnosticExportV1
    ) -> some View {
        let value = prepared.value
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(BundledLocalizationCatalogV1.v30Text(.feedbackDiagnosticLabel2))
                .font(.headline)
            Text(BundledLocalizationCatalogV1.v30Text(.feedbackDiagnosticLabel3))
            Text(BundledLocalizationCatalogV1.v30FeedbackDiagnosticSize(bytes: prepared.canonicalData.count))
            Text(BundledLocalizationCatalogV1.v30DiagnosticsAppVersionBuild(version: value.app.version, build: value.app.build))
            Text(BundledLocalizationCatalogV1.v30DiagnosticsDeviceModelOS(model: value.device.model, osVersion: value.device.osVersion))
            Text(BundledLocalizationCatalogV1.v30DiagnosticsGeneratedAt(date: value.generatedAt.formatted(date: .abbreviated, time: .shortened)))

            let counters = value.counters
            Text(BundledLocalizationCatalogV1.v30DiagnosticsFirstSignsCount(count: counters.firstSignCreated))
            Text(BundledLocalizationCatalogV1.v30DiagnosticsOnboardingCompletionsCount(count: counters.onboardingCompleted))
            Text(BundledLocalizationCatalogV1.v30DiagnosticsReportsSavedCount(count: counters.reportSaved))
            Text(BundledLocalizationCatalogV1.v30DiagnosticsRechecksCompletedCount(count: counters.recheckCompleted))
            Text(BundledLocalizationCatalogV1.v30DiagnosticsReportShareSheetsCount(count: counters.reportShareSheetPresented))
            Text(BundledLocalizationCatalogV1.v30DiagnosticsPaywallsShownCount(count: counters.paywallPresented))
            Text(
                BundledLocalizationCatalogV1.v30DiagnosticsPurchaseResults(verified: counters.purchaseResult.verified, cancelled: counters.purchaseResult.cancelled, pending: counters.purchaseResult.pending, unverified: counters.purchaseResult.unverified, failed: counters.purchaseResult.failed)
            )

            if let metricKit = value.metricKit {
                Text(BundledLocalizationCatalogV1.v30DiagnosticsCrashesCount(count: metricKit.crashCount))
                Text(BundledLocalizationCatalogV1.v30DiagnosticsHangsCount(count: metricKit.hangCount))
                if let bytes = metricKit.peakMemoryBytes {
                    Text(BundledLocalizationCatalogV1.v30DiagnosticsPeakMemoryBytes(bytes: bytes))
                }
                if let launch = metricKit.launchTimeMilliseconds {
                    Text(
                        BundledLocalizationCatalogV1.v30DiagnosticsLaunchBuckets(under500: launch.under500, from500Through999: launch.from500Through999, from1000Through1999: launch.from1000Through1999, from2000Up: launch.from2000Up)
                    )
                }
            } else {
                Text(BundledLocalizationCatalogV1.v30Text(.feedbackFeedbackLabel6))
            }

            Text(
                BundledLocalizationCatalogV1.v30Text(.feedbackPhotoLabel)
            )
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
        .font(.body)
        .foregroundStyle(DesignTokens.Colors.primaryText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(Self.reviewAccessibilityIdentifier)
    }

    @ViewBuilder
    private func routeControls(
        _ prepared: PreparedDiagnosticExportV1
    ) -> some View {
        switch configuration.route(
            mailComposerAvailable: mailComposer.isAvailable
        ) {
        case .blocked:
            WorklightStatusBadge(
                kind: .blocked,
                text: BundledLocalizationCatalogV1.v30Text(.feedbackFeedbackFailure2)
            )
            Button(BundledLocalizationCatalogV1.v30Text(.feedbackFeedbackRetry)) {
                Task { await prepare(force: true) }
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .accessibilityIdentifier(Self.retryAccessibilityIdentifier)

        case .composer:
            Text(
                BundledLocalizationCatalogV1.v30Text(.feedbackFeedbackLabel7)
            )
            .font(.body)
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(Self.consentAccessibilityIdentifier)

            Button(BundledLocalizationCatalogV1.v30Text(.feedbackFeedbackAction)) {
                presentMail(prepared, choice: .attach)
            }
            .buttonStyle(WorklightPrimaryButtonStyle())
            .accessibilityHint(
                BundledLocalizationCatalogV1.v30Text(.feedbackDiagnosticLabel4)
            )
            .accessibilityIdentifier(Self.attachAccessibilityIdentifier)

            Button(BundledLocalizationCatalogV1.v30Text(.feedbackFeedbackAction2)) {
                presentMail(prepared, choice: .doNotAttach)
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .accessibilityHint(
                BundledLocalizationCatalogV1.v30Text(.feedbackDiagnosticLabel5)
            )
            .accessibilityIdentifier(Self.doNotAttachAccessibilityIdentifier)

        case .unavailableFallback:
            WorklightStatusBadge(
                kind: .attention,
                text: BundledLocalizationCatalogV1.v30Text(.feedbackFeedbackFailure3)
            )

            Button(BundledLocalizationCatalogV1.v30Text(.feedbackFeedbackAction3)) {
                guard let address = configuration.validatedSupportAddress else {
                    errorMessage = BundledLocalizationCatalogV1.v30Text(.feedbackFeedbackFailure4)
                    return
                }
                UIPasteboard.general.string = address
                statusMessage = BundledLocalizationCatalogV1.v30Text(.feedbackFeedbackLabel8)
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .accessibilityIdentifier(Self.copyAddressAccessibilityIdentifier)

            Button(BundledLocalizationCatalogV1.v30Text(.feedbackDiagnosticAction)) {
                statusMessage = nil
                showsExporter = true
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .accessibilityHint(
                BundledLocalizationCatalogV1.v30Text(.feedbackDiagnosticLabel6)
            )
            .accessibilityIdentifier(Self.saveDiagnosticsAccessibilityIdentifier)
        }
    }

    private func presentMail(
        _ prepared: PreparedDiagnosticExportV1,
        choice: FeedbackAttachmentChoiceV1
    ) {
        guard mailComposer.isAvailable else {
            statusMessage = nil
            errorMessage = BundledLocalizationCatalogV1.v30Text(.feedbackFeedbackFailure5)
            return
        }
        do {
            let draft = try FeedbackMailDraftBuilderV1.make(
                configuration: configuration,
                diagnostic: prepared,
                attachmentChoice: choice
            )
            statusMessage = nil
            errorMessage = nil
            mailPresentation = MailPresentation(draft: draft)
        } catch {
            statusMessage = nil
            errorMessage = BundledLocalizationCatalogV1.v30Text(.feedbackFeedbackFailure6)
        }
    }

    private func prepare(force: Bool) async {
        if !force, didPrepare { return }
        didPrepare = true
        prepared = nil
        statusMessage = nil
        guard configuration.validatedSupportAddress != nil else {
            errorMessage = BundledLocalizationCatalogV1.v30Text(.feedbackFeedbackFailure2)
            return
        }
        errorMessage = nil
        do {
            prepared = try await diagnosticService.prepare()
        } catch {
            errorMessage = BundledLocalizationCatalogV1.v30Text(.feedbackDiagnosticFailure2)
        }
    }
}

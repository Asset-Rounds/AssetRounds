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
                Text("Send feedback")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(Self.headingAccessibilityIdentifier)

                Text(
                    "Your message stays editable. Only app version, build, device model, and iOS version are prefilled; customer and inspection content is never prefilled."
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
                    Button("Retry") {
                        Task { await prepare(force: true) }
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityIdentifier(Self.retryAccessibilityIdentifier)
                } else {
                    ProgressView("Preparing privacy-safe feedback context")
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
        .navigationTitle("Feedback")
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
                    statusMessage = "Feedback composer cancelled. No delivery was claimed."
                case .failed:
                    statusMessage = nil
                    errorMessage = "The feedback composer closed with an error. No delivery was claimed."
                case .saved:
                    statusMessage = "Feedback draft closed. Delivery remains under your control."
                case .sent:
                    statusMessage = "The system composer finished. The app does not claim delivery."
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
                statusMessage = "Diagnostic file saved."
            case let .failure(error):
                if (error as? CocoaError)?.code == .userCancelled {
                    return
                }
                statusMessage = nil
                errorMessage = "The diagnostic file could not be saved to Files."
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
            Text("Review diagnostics before choosing")
                .font(.headline)
            Text("File: field-record-diagnostics.json")
            Text("Size: \(prepared.canonicalData.count) bytes")
            Text("App \(value.app.version) (\(value.app.build))")
            Text("Device \(value.device.model) · iOS \(value.device.osVersion)")
            Text("Generated \(value.generatedAt.formatted(date: .abbreviated, time: .shortened))")

            let counters = value.counters
            Text("First signs: \(counters.firstSignCreated)")
            Text("Onboarding completions: \(counters.onboardingCompleted)")
            Text("Reports saved: \(counters.reportSaved)")
            Text("Rechecks completed: \(counters.recheckCompleted)")
            Text("Report share sheets: \(counters.reportShareSheetPresented)")
            Text("Paywalls shown: \(counters.paywallPresented)")
            Text(
                "Purchase results — verified \(counters.purchaseResult.verified), cancelled \(counters.purchaseResult.cancelled), pending \(counters.purchaseResult.pending), unverified \(counters.purchaseResult.unverified), failed \(counters.purchaseResult.failed)"
            )

            if let metricKit = value.metricKit {
                Text("Crashes: \(metricKit.crashCount)")
                Text("Hangs: \(metricKit.hangCount)")
                if let bytes = metricKit.peakMemoryBytes {
                    Text("Peak memory bytes: \(bytes)")
                }
                if let launch = metricKit.launchTimeMilliseconds {
                    Text(
                        "Launches — under 500 ms \(launch.under500), 500–999 ms \(launch.from500Through999), 1000–1999 ms \(launch.from1000Through1999), 2000 ms or more \(launch.from2000Up)"
                    )
                }
            } else {
                Text("No recent bounded system summary is available.")
            }

            Text(
                "This reviewed JSON never includes customer or sign details, addresses, notes, photos, reports, backups, paths, hashes, StoreKit details, credentials, or logs."
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
                text: "Feedback is unavailable because a support address has not been configured. No app data changed."
            )
            Button("Retry") {
                Task { await prepare(force: true) }
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .accessibilityIdentifier(Self.retryAccessibilityIdentifier)

        case .composer:
            Text(
                "Choose Attach to include exactly this reviewed JSON, or Don't Attach to open the same editable composer without it."
            )
            .font(.body)
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(Self.consentAccessibilityIdentifier)

            Button("Attach") {
                presentMail(prepared, choice: .attach)
            }
            .buttonStyle(WorklightPrimaryButtonStyle())
            .accessibilityHint(
                "Opens the editable system composer with one reviewed diagnostic JSON attachment"
            )
            .accessibilityIdentifier(Self.attachAccessibilityIdentifier)

            Button("Don't Attach") {
                presentMail(prepared, choice: .doNotAttach)
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .accessibilityHint(
                "Opens the same editable system composer with no diagnostic attachment"
            )
            .accessibilityIdentifier(Self.doNotAttachAccessibilityIdentifier)

        case .unavailableFallback:
            WorklightStatusBadge(
                kind: .attention,
                text: "Mail is unavailable on this device. Nothing was sent."
            )

            Button("Copy support address") {
                guard let address = configuration.validatedSupportAddress else {
                    errorMessage = "The support address is unavailable. Nothing was copied."
                    return
                }
                UIPasteboard.general.string = address
                statusMessage = "Support address copied."
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .accessibilityIdentifier(Self.copyAddressAccessibilityIdentifier)

            Button("Save diagnostics to Files") {
                statusMessage = nil
                showsExporter = true
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .accessibilityHint(
                "Opens the system Files destination picker for the reviewed diagnostic JSON"
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
            errorMessage = "Mail became unavailable. Nothing was sent."
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
            errorMessage = "Feedback could not be prepared. No message or attachment was sent."
        }
    }

    private func prepare(force: Bool) async {
        if !force, didPrepare { return }
        didPrepare = true
        prepared = nil
        statusMessage = nil
        guard configuration.validatedSupportAddress != nil else {
            errorMessage = "Feedback is unavailable because a support address has not been configured. No app data changed."
            return
        }
        errorMessage = nil
        do {
            prepared = try await diagnosticService.prepare()
        } catch {
            errorMessage = "Privacy-safe diagnostics are unavailable right now. No app data changed."
        }
    }
}

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct DiagnosticExportView: View {
    static let settingsEntryAccessibilityIdentifier = "s8.3.diagnostics.settings-entry"
    static let screenAccessibilityIdentifier = "s8.3.diagnostics.screen"
    static let headingAccessibilityIdentifier = "s8.3.diagnostics.heading"
    static let authorityAccessibilityIdentifier = "s8.3.diagnostics.authority"
    static let privacyAccessibilityIdentifier = "s8.3.diagnostics.privacy"
    static let countersAccessibilityIdentifier = "s8.3.diagnostics.counters"
    static let metricKitAccessibilityIdentifier = "s8.3.diagnostics.metrickit"
    static let exportAccessibilityIdentifier = "s8.3.diagnostics.export"
    static let statusAccessibilityIdentifier = "s8.3.diagnostics.status"

    private let service: DiagnosticExportService

    @State private var prepared: PreparedDiagnosticExportV1?
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var showsExporter = false
    @State private var didPrepare = false

    @MainActor
    init(
        diagnosticsStore: DiagnosticsStore,
        metricKitAdapter: MetricKitDiagnosticsAdapter
    ) {
        service = DiagnosticExportService(
            diagnosticsStore: diagnosticsStore,
            metricKitAdapter: metricKitAdapter
        )
    }

    var body: some View {
        ScrollView {
            WorklightCard {
                Text("Diagnostics preview")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(Self.headingAccessibilityIdentifier)

                Text(
                    "These counters are best-effort lower-bound signals. They may be incomplete and are not payment, access, or cohort authority."
                )
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(Self.authorityAccessibilityIdentifier)

                Text(
                    "The export includes only app and device versions, local counters, and bounded system metrics when available. It never includes customer or sign details, addresses, notes, photos, reports, backups, paths, hashes, StoreKit details, credentials, or logs."
                )
                .font(.subheadline)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(Self.privacyAccessibilityIdentifier)

                if let prepared {
                    preview(prepared.value)

                    Button("Save diagnostics to Files") {
                        statusMessage = nil
                        showsExporter = true
                    }
                    .buttonStyle(WorklightPrimaryButtonStyle())
                    .accessibilityHint(
                        "Opens the system Files destination picker for this reviewed diagnostic JSON"
                    )
                    .accessibilityIdentifier(Self.exportAccessibilityIdentifier)
                } else if let errorMessage {
                    WorklightStatusBadge(kind: .blocked, text: errorMessage)
                } else {
                    ProgressView("Preparing privacy-safe diagnostics")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let statusMessage {
                    WorklightStatusBadge(kind: .complete, text: statusMessage)
                        .accessibilityIdentifier(Self.statusAccessibilityIdentifier)
                }
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .fileExporter(
            isPresented: $showsExporter,
            document: prepared.map { DiagnosticJSONDocument(data: $0.canonicalData) },
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
            guard !didPrepare else { return }
            didPrepare = true
            do {
                prepared = try await service.prepare()
            } catch {
                errorMessage = "Diagnostics are unavailable right now. No app data changed."
            }
        }
    }

    @ViewBuilder
    private func preview(_ value: DiagnosticExportV1) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("App \(value.app.version) (\(value.app.build))")
            Text("Device \(value.device.model) · iOS \(value.device.osVersion)")
            Text("Generated \(value.generatedAt.formatted(date: .abbreviated, time: .shortened))")
        }
        .font(.subheadline)
        .foregroundStyle(DesignTokens.Colors.secondaryText)
        .fixedSize(horizontal: false, vertical: true)

        let counters = value.counters
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("Local counters")
                .font(.headline)
            Text("First signs: \(counters.firstSignCreated)")
            Text("Onboarding completions: \(counters.onboardingCompleted)")
            Text("Reports saved: \(counters.reportSaved)")
            Text("Rechecks completed: \(counters.recheckCompleted)")
            Text("Report share sheets: \(counters.reportShareSheetPresented)")
            Text("Paywalls shown: \(counters.paywallPresented)")
            Text(
                "Purchase results — verified \(counters.purchaseResult.verified), cancelled \(counters.purchaseResult.cancelled), pending \(counters.purchaseResult.pending), unverified \(counters.purchaseResult.unverified), failed \(counters.purchaseResult.failed)"
            )
        }
        .font(.body)
        .foregroundStyle(DesignTokens.Colors.primaryText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(Self.countersAccessibilityIdentifier)

        if let metricKit = value.metricKit {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                Text("Bounded system summary")
                    .font(.headline)
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
            }
            .font(.body)
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(Self.metricKitAccessibilityIdentifier)
        } else {
            Text("No recent bounded system summary is available.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(Self.metricKitAccessibilityIdentifier)
        }
    }
}

struct DiagnosticJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

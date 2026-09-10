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
                Text(BundledLocalizationCatalogV1.v30Text(.diagnosticsDiagnosticLabel))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(Self.headingAccessibilityIdentifier)

                Text(
                    BundledLocalizationCatalogV1.v30Text(.diagnosticsDiagnosticLabel2)
                )
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(Self.authorityAccessibilityIdentifier)

                Text(
                    BundledLocalizationCatalogV1.v30Text(.diagnosticsPhotoLabel)
                )
                .font(.subheadline)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(Self.privacyAccessibilityIdentifier)

                if let prepared {
                    preview(prepared.value)

                    Button(BundledLocalizationCatalogV1.v30Text(.diagnosticsDiagnosticAction)) {
                        statusMessage = nil
                        showsExporter = true
                    }
                    .buttonStyle(WorklightPrimaryButtonStyle())
                    .accessibilityHint(
                        BundledLocalizationCatalogV1.v30Text(.diagnosticsDiagnosticLabel3)
                    )
                    .accessibilityIdentifier(Self.exportAccessibilityIdentifier)
                } else if let errorMessage {
                    WorklightStatusBadge(kind: .blocked, text: errorMessage)
                } else {
                    ProgressView(BundledLocalizationCatalogV1.v30Text(.diagnosticsDiagnosticProgress))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let statusMessage {
                    WorklightStatusBadge(kind: .complete, text: statusMessage)
                        .accessibilityIdentifier(Self.statusAccessibilityIdentifier)
                }
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.diagnosticsDiagnosticNavigation))
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
                statusMessage = BundledLocalizationCatalogV1.v30Text(.diagnosticsDiagnosticLabel4)
            case let .failure(error):
                if (error as? CocoaError)?.code == .userCancelled {
                    return
                }
                statusMessage = nil
                errorMessage = BundledLocalizationCatalogV1.v30Text(.diagnosticsDiagnosticFailure)
            }
        }
        .task {
            guard !didPrepare else { return }
            didPrepare = true
            do {
                prepared = try await service.prepare()
            } catch {
                errorMessage = BundledLocalizationCatalogV1.v30Text(.diagnosticsDiagnosticFailure2)
            }
        }
    }

    @ViewBuilder
    private func preview(_ value: DiagnosticExportV1) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(BundledLocalizationCatalogV1.v30DiagnosticsAppVersionBuild(version: value.app.version, build: value.app.build))
            Text(BundledLocalizationCatalogV1.v30DiagnosticsDeviceModelOS(model: value.device.model, osVersion: value.device.osVersion))
            Text(BundledLocalizationCatalogV1.v30DiagnosticsGeneratedAt(date: value.generatedAt.formatted(date: .abbreviated, time: .shortened)))
        }
        .font(.subheadline)
        .foregroundStyle(DesignTokens.Colors.secondaryText)
        .fixedSize(horizontal: false, vertical: true)

        let counters = value.counters
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(BundledLocalizationCatalogV1.v30Text(.diagnosticsDiagnosticLabel5))
                .font(.headline)
            Text(BundledLocalizationCatalogV1.v30DiagnosticsFirstSignsCount(count: counters.firstSignCreated))
            Text(BundledLocalizationCatalogV1.v30DiagnosticsOnboardingCompletionsCount(count: counters.onboardingCompleted))
            Text(BundledLocalizationCatalogV1.v30DiagnosticsReportsSavedCount(count: counters.reportSaved))
            Text(BundledLocalizationCatalogV1.v30DiagnosticsRechecksCompletedCount(count: counters.recheckCompleted))
            Text(BundledLocalizationCatalogV1.v30DiagnosticsReportShareSheetsCount(count: counters.reportShareSheetPresented))
            Text(BundledLocalizationCatalogV1.v30DiagnosticsPaywallsShownCount(count: counters.paywallPresented))
            Text(
                BundledLocalizationCatalogV1.v30DiagnosticsPurchaseResults(verified: counters.purchaseResult.verified, cancelled: counters.purchaseResult.cancelled, pending: counters.purchaseResult.pending, unverified: counters.purchaseResult.unverified, failed: counters.purchaseResult.failed)
            )
        }
        .font(.body)
        .foregroundStyle(DesignTokens.Colors.primaryText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(Self.countersAccessibilityIdentifier)

        if let metricKit = value.metricKit {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                Text(BundledLocalizationCatalogV1.v30Text(.diagnosticsDiagnosticLabel6))
                    .font(.headline)
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
            }
            .font(.body)
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(Self.metricKitAccessibilityIdentifier)
        } else {
            Text(BundledLocalizationCatalogV1.v30Text(.diagnosticsDiagnosticLabel7))
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

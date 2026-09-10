import Foundation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ReportDetailView: View {
    static let screenAccessibilityIdentifier = "s4.3.report-detail.screen"
    static let previewAccessibilityIdentifier = "s4.3.report-detail.preview"
    static let shareAccessibilityIdentifier = "s4.3.report-detail.share"
    static let saveToFilesAccessibilityIdentifier = "s4.3.report-detail.save-to-files"
    static let deliveryErrorAccessibilityIdentifier = "s4.3.report-detail.delivery-error"
    static let closeAccessibilityIdentifier = "s4.3.report-detail.close"
    static let correctAccessibilityIdentifier = "s4.5.report-detail.correct"
    static let revisionStateAccessibilityIdentifier =
        "s4.5.report-detail.revision-state"

    private struct DetailState {
        let chain: ReportDeliveryChainValue
        let selectedReportID: UUID
        let correctionSource: ReportCorrectionSourceValue?
        let unavailableCurrentReportID: UUID?
        let isAuthorityResolved: Bool

        var selectedDelivery: ReportDeliveryValue {
            ([chain.current] + chain.ancestors).first {
                $0.reportID == selectedReportID
            } ?? chain.current
        }

        var isCurrentReadyRevision: Bool {
            isAuthorityResolved
                && unavailableCurrentReportID == nil
                && selectedReportID == chain.current.reportID
        }
    }

    let coordinator: ReportDeliveryCoordinator

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var state: DetailState
    @State private var showsShareSheet = false
    @State private var showsFilesExporter = false
    @State private var exportErrorMessage: String?
    @State private var activeCorrectionSource: ReportCorrectionSourceValue?
    @State private var didLoadCorrectionAuthority = false

    init(delivery: ReportDeliveryValue, coordinator: ReportDeliveryCoordinator) {
        self.coordinator = coordinator
        _state = State(initialValue: DetailState(
            chain: ReportDeliveryChainValue(current: delivery, ancestors: []),
            selectedReportID: delivery.reportID,
            correctionSource: nil,
            unavailableCurrentReportID: nil,
            isAuthorityResolved: false
        ))
    }

    private var delivery: ReportDeliveryValue { state.selectedDelivery }

    private var previewMinimumHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 240 : 520
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                    WorklightCard {
                        WorklightStatusBadge(kind: .complete, text: BundledLocalizationCatalogV1.v30Text(.reportDetailReportStatus))

                        if state.isAuthorityResolved {
                            WorklightStatusBadge(
                                kind: state.isCurrentReadyRevision ? .complete : .information,
                                text: state.isCurrentReadyRevision
                                    ? BundledLocalizationCatalogV1.v30Text(.reportDetailReportLabel)
                                    : BundledLocalizationCatalogV1.v30Text(.reportDetailReportLabel2)
                            )
                            .accessibilityIdentifier(
                                Self.revisionStateAccessibilityIdentifier
                            )
                        }

                        Text(delivery.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(DesignTokens.Colors.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)

                        Text(delivery.subtitle)
                            .font(.body)
                            .foregroundStyle(DesignTokens.Colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(Array(delivery.detailLines.enumerated()), id: \.offset) { _, line in
                            detailRow(line)
                        }
                    }

                    if state.unavailableCurrentReportID != nil {
                        WorklightStatusBadge(
                            kind: .attention,
                            text: BundledLocalizationCatalogV1.v30Text(.reportDetailReportRetry)
                        )
                        .accessibilityIdentifier(ReportCorrectionView.failureAccessibilityIdentifier)
                    }

                    ReportPDFPreview(data: delivery.pdfData)
                        .frame(height: previewMinimumHeight)
                        .background(DesignTokens.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard))
                        .overlay {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                                .stroke(DesignTokens.Colors.essentialControlStroke, lineWidth: 1)
                        }
                        .accessibilityLabel(BundledLocalizationCatalogV1.v30Text(.reportDetailReportAccessibility))
                        .accessibilityIdentifier(Self.previewAccessibilityIdentifier)

                    if let exportErrorMessage {
                        Label(exportErrorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.body)
                            .foregroundStyle(DesignTokens.Colors.blockedText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(Self.deliveryErrorAccessibilityIdentifier)
                    }
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .id(state.selectedReportID)
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.reportDetailReportNavigation))
        .navigationBarTitleDisplayMode(.inline)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .navigationDestination(isPresented: correctionIsPresented) {
            if let source = activeCorrectionSource {
                ReportCorrectionView(
                    source: source,
                    coordinator: coordinator,
                    didProduceReady: applyReadyCorrection,
                    didSelectReport: selectReport,
                    didPersistDeliveryFailure: applyDeliveryFailure
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: DesignTokens.Spacing.small) {
                revisionActions

                HStack(spacing: DesignTokens.Spacing.small) {
                    Button(BundledLocalizationCatalogV1.v30Text(.reportDetailReportAction)) {
                        showsShareSheet = true
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .frame(maxWidth: .infinity)
                    .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.reportDetailReportAccessibility2))
                    .accessibilityIdentifier(Self.shareAccessibilityIdentifier)

                    Button(BundledLocalizationCatalogV1.v30Text(.reportDetailReportAction2)) {
                        showsFilesExporter = true
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .frame(maxWidth: .infinity)
                    .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.reportDetailReportAccessibility3))
                    .accessibilityIdentifier(Self.saveToFilesAccessibilityIdentifier)
                }

                Button(BundledLocalizationCatalogV1.v30Text(.reportDetailReportAction3)) {
                    dismiss()
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.reportDetailReportAccessibility4))
                .accessibilityIdentifier(Self.closeAccessibilityIdentifier)
            }
            .padding(.horizontal, DesignTokens.Spacing.medium)
            .padding(.vertical, DesignTokens.Spacing.small)
            .background(DesignTokens.Colors.canvas)
        }
        .sheet(isPresented: $showsShareSheet) {
            ReportShareSheet(delivery: delivery, coordinator: coordinator)
        }
        .fileExporter(
            isPresented: $showsFilesExporter,
            document: ReportPDFDocument(data: delivery.pdfData),
            contentType: .pdf,
            defaultFilename: delivery.filename
        ) { result in
            switch result {
            case .success:
                exportErrorMessage = nil
            case let .failure(error):
                if (error as? CocoaError)?.code == .userCancelled {
                    return
                } else {
                    exportErrorMessage = BundledLocalizationCatalogV1.v30Text(.reportDetailReportFailure)
                }
            }
        }
        .task {
            guard !didLoadCorrectionAuthority else { return }
            didLoadCorrectionAuthority = true
            loadCorrectionAuthority()
        }
    }

    private var correctionIsPresented: Binding<Bool> {
        Binding(
            get: { activeCorrectionSource != nil },
            set: { isPresented in
                if !isPresented { activeCorrectionSource = nil }
            }
        )
    }

    @ViewBuilder
    private var revisionActions: some View {
        if hasRevisionActions {
            VStack(spacing: DesignTokens.Spacing.small) {
                if let source = state.correctionSource,
                   state.isCurrentReadyRevision {
                    Button(BundledLocalizationCatalogV1.v30Text(.reportDetailReportAction4)) {
                        activeCorrectionSource = source
                    }
                    .buttonStyle(WorklightPrimaryButtonStyle())
                    .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.reportDetailReportAccessibility5))
                    .accessibilityIdentifier(Self.correctAccessibilityIdentifier)
                }

                if let prior = immediatelyPriorDelivery {
                    Button(BundledLocalizationCatalogV1.v30Text(.reportDetailReportAction5)) {
                        selectReport(id: prior.reportID)
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.reportDetailReportAccessibility6))
                    .accessibilityIdentifier(
                        ReportCorrectionView.priorReportAccessibilityIdentifier
                    )
                }

                if !state.isCurrentReadyRevision,
                   state.unavailableCurrentReportID == nil {
                    Button(BundledLocalizationCatalogV1.v30Text(.reportDetailReportAction6)) {
                        selectReport(id: state.chain.current.reportID)
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.reportDetailReportAccessibility7))
                    .accessibilityIdentifier(
                        ReportCorrectionView.currentReportAccessibilityIdentifier
                    )
                }
            }
        }
    }

    private var hasRevisionActions: Bool {
        state.isAuthorityResolved && (
            state.correctionSource != nil && state.isCurrentReadyRevision
                || immediatelyPriorDelivery != nil
                || !state.isCurrentReadyRevision
                    && state.unavailableCurrentReportID == nil
        )
    }

    private var immediatelyPriorDelivery: ReportDeliveryValue? {
        let deliveries = [state.chain.current] + state.chain.ancestors
        guard let selectedIndex = deliveries.firstIndex(where: {
            $0.reportID == state.selectedReportID
        }) else { return nil }
        let nextIndex = deliveries.index(after: selectedIndex)
        return deliveries.indices.contains(nextIndex) ? deliveries[nextIndex] : nil
    }

    private func loadCorrectionAuthority() {
        do {
            let selectedReportID = state.selectedReportID
            let chain = try coordinator.readyDeliveryChain(
                containingReportID: selectedReportID
            )
            guard ([chain.current] + chain.ancestors).contains(where: {
                $0.reportID == selectedReportID
            }) else {
                return
            }
            let source = try? coordinator.correctionSource(
                reportID: chain.current.reportID
            )
            state = DetailState(
                chain: chain,
                selectedReportID: selectedReportID,
                correctionSource: source,
                unavailableCurrentReportID: nil,
                isAuthorityResolved: true
            )
        } catch {
            state = DetailState(
                chain: state.chain,
                selectedReportID: state.selectedReportID,
                correctionSource: nil,
                unavailableCurrentReportID: nil,
                isAuthorityResolved: false
            )
        }
    }

    private func applyReadyCorrection(_ chain: ReportDeliveryChainValue) {
        let freshSource = try? coordinator.correctionSource(
            reportID: chain.current.reportID
        )
        state = DetailState(
            chain: chain,
            selectedReportID: chain.current.reportID,
            correctionSource: freshSource,
            unavailableCurrentReportID: nil,
            isAuthorityResolved: true
        )
    }

    private func applyDeliveryFailure(
        _ failedReportID: UUID,
        prior: ReportDeliveryValue
    ) {
        state = DetailState(
            chain: state.chain,
            selectedReportID: prior.reportID,
            correctionSource: nil,
            unavailableCurrentReportID: failedReportID,
            isAuthorityResolved: true
        )
    }

    private func selectReport(id: UUID) {
        state = DetailState(
            chain: state.chain,
            selectedReportID: id,
            correctionSource: state.correctionSource,
            unavailableCurrentReportID: state.unavailableCurrentReportID,
            isAuthorityResolved: state.isAuthorityResolved
        )
    }

    private func detailRow(_ value: String) -> some View {
        Text(value)
            .font(.body)
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ReportPDFPreview: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .systemBackground
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.dataRepresentation() != data {
            view.document = PDFDocument(data: data)
            view.autoScales = true
        }
    }
}

struct ReportShareSheet: UIViewControllerRepresentable {
    let delivery: ReportDeliveryValue
    let coordinator: ReportDeliveryCoordinator

    func makeUIViewController(context: Context) -> ObservedActivityViewController {
        makeController()
    }

    func makeController() -> ObservedActivityViewController {
        let payload = ReportSharePayload(delivery: delivery)
        let controller = ObservedActivityViewController(
            activityItemsConfiguration: UIActivityItemsConfiguration(
                itemProviders: [payload.itemProvider]
            )
        )
        controller.presentationGate = ReportSharePresentationGate {
            Task { await coordinator.shareSheetDidPresent() }
        }
        return controller
    }

    func updateUIViewController(
        _ uiViewController: ObservedActivityViewController,
        context: Context
    ) {}

    @MainActor
    final class ObservedActivityViewController: UIActivityViewController {
        var presentationGate: ReportSharePresentationGate?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            presentationGate?.consume()
        }
    }
}

struct ReportSharePayload {
    let itemProvider: NSItemProvider

    init(delivery: ReportDeliveryValue) {
        let provider = NSItemProvider()
        provider.suggestedName = delivery.filename
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.pdf.identifier,
            visibility: .all
        ) { completion in
            completion(delivery.pdfData, nil)
            return nil
        }
        itemProvider = provider
    }
}

@MainActor
final class ReportSharePresentationGate {
    private var isConsumed = false
    private let onFirstPresentation: () -> Void

    init(onFirstPresentation: @escaping () -> Void) {
        self.onFirstPresentation = onFirstPresentation
    }

    @discardableResult
    func consume() -> Bool {
        guard !isConsumed else { return false }
        isConsumed = true
        onFirstPresentation()
        return true
    }
}

struct ReportPDFDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

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
        exportedFileWrapper()
    }

    func exportedFileWrapper() -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

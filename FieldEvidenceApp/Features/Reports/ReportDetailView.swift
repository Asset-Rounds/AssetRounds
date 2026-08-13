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

    let delivery: ReportDeliveryValue
    let coordinator: ReportDeliveryCoordinator

    @Environment(\.dismiss) private var dismiss
    @State private var showsShareSheet = false
    @State private var showsFilesExporter = false
    @State private var exportErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                WorklightCard {
                    WorklightStatusBadge(kind: .complete, text: "Report ready")

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

                ReportPDFPreview(data: delivery.pdfData)
                    .frame(minHeight: 520)
                    .background(DesignTokens.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard))
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                            .stroke(DesignTokens.Colors.essentialControlStroke, lineWidth: 1)
                    }
                    .accessibilityLabel("Report PDF preview")
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
        .navigationTitle("Report")
        .navigationBarTitleDisplayMode(.inline)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: DesignTokens.Spacing.small) {
                HStack(spacing: DesignTokens.Spacing.small) {
                    Button("Share PDF") {
                        showsShareSheet = true
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .frame(maxWidth: .infinity)
                    .accessibilityHint("Opens the system share sheet for this report PDF")
                    .accessibilityIdentifier(Self.shareAccessibilityIdentifier)

                    Button("Save to Files") {
                        showsFilesExporter = true
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .frame(maxWidth: .infinity)
                    .accessibilityHint("Choose a Files destination for an identical copy of this report PDF")
                    .accessibilityIdentifier(Self.saveToFilesAccessibilityIdentifier)
                }

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .accessibilityHint("Returns to the saved report receipt")
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
                    exportErrorMessage = "The report could not be saved to Files."
                }
            }
        }
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

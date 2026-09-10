import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct BackupExportView: View {
    static let screenAccessibilityIdentifier = "s6.2.backup.screen"
    static let settingsEntryAccessibilityIdentifier = "s6.2.backup.settings-entry"
    static let signCountAccessibilityIdentifier = "s6.2.backup.sign-count"
    static let reportCountAccessibilityIdentifier = "s6.2.backup.report-count"
    static let photoCountAccessibilityIdentifier = "s6.2.backup.photo-count"
    static let warningAccessibilityIdentifier = "s6.2.backup.warning"
    static let actionAccessibilityIdentifier = "s6.2.backup.action"
    static let exportedAccessibilityIdentifier = "s6.2.backup.exported"

    static let warning = BundledLocalizationCatalogV1.v30Text(.backupExportPhotoLabel)

    private let service: BackupExportService
    private let usesConfirmedDestinationForUITest: Bool

    @State private var preview: BackupExportPreviewV1?
    @State private var isWorking = false
    @State private var showsDestinationPicker = false
    @State private var exportedPackageName: String?
    @AccessibilityFocusState private var warningFocused: Bool
    @AccessibilityFocusState private var exportedFocused: Bool

    init(modelContext: ModelContext, generationRootURL: URL) {
        service = BackupExportService(
            modelContext: modelContext,
            generationRootURL: generationRootURL
        )
        usesConfirmedDestinationForUITest = ProcessInfo.processInfo.arguments.contains(
            "--s6-2-ui-test-confirmed-destination"
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                WorklightCard {
                    if let preview {
                        Text(BundledLocalizationCatalogV1.v30BackupExportSignCount(count: preview.signCount))
                            .font(.headline)
                            .foregroundStyle(DesignTokens.Colors.primaryText)
                            .accessibilityIdentifier(Self.signCountAccessibilityIdentifier)
                        Text(BundledLocalizationCatalogV1.v30BackupExportReportCount(count: preview.reportCount))
                            .font(.headline)
                            .foregroundStyle(DesignTokens.Colors.primaryText)
                            .accessibilityIdentifier(Self.reportCountAccessibilityIdentifier)
                        Text(BundledLocalizationCatalogV1.v30BackupExportPhotoCount(count: preview.photoCount))
                            .font(.headline)
                            .foregroundStyle(DesignTokens.Colors.primaryText)
                            .accessibilityIdentifier(Self.photoCountAccessibilityIdentifier)
                    } else if isWorking {
                        ProgressView()
                    }

                    Text(Self.warning)
                        .font(.body)
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(Self.warningAccessibilityIdentifier)
                        .accessibilityFocused($warningFocused)
                }

                Button(BundledLocalizationCatalogV1.v30Text(.backupExportBackupAction)) {
                    beginExport()
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .disabled(isWorking || preview == nil || exportedPackageName != nil)
                .accessibilityIdentifier(Self.actionAccessibilityIdentifier)

                if let exportedPackageName {
                    Text(exportedPackageName)
                        .font(.body.monospaced())
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(Self.exportedAccessibilityIdentifier)
                        .accessibilityFocused($exportedFocused)
                }
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.backupExportBackupAction))
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .sheet(isPresented: $showsDestinationPicker) {
            BackupDestinationPicker(
                selected: export(to:),
                cancelled: { showsDestinationPicker = false }
            )
        }
        .task {
            guard preview == nil, !isWorking else { return }
            loadPreview()
        }
    }

    private func loadPreview() {
        isWorking = true
        defer { isWorking = false }
        preview = try? service.prepare()
        if preview != nil {
            Task { @MainActor in
                await Task.yield()
                warningFocused = true
            }
        }
    }

    private func beginExport() {
        guard let preview, !isWorking, exportedPackageName == nil else { return }
        if usesConfirmedDestinationForUITest {
            guard let documents = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first else { return }
            export(previewID: preview.id, to: documents)
        } else {
            showsDestinationPicker = true
        }
    }

    private func export(to destination: URL) {
        guard let preview else { return }
        export(previewID: preview.id, to: destination)
    }

    private func export(previewID: UUID, to destination: URL) {
        showsDestinationPicker = false
        isWorking = true
        let accessed = destination.startAccessingSecurityScopedResource()
        defer {
            if accessed { destination.stopAccessingSecurityScopedResource() }
            isWorking = false
        }
        if let url = try? service.export(previewID: previewID, to: destination) {
            exportedPackageName = url.lastPathComponent
            Task { @MainActor in
                await Task.yield()
                exportedFocused = true
            }
        }
    }


}

private struct BackupDestinationPicker: UIViewControllerRepresentable {
    let selected: (URL) -> Void
    let cancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(selected: selected, cancelled: cancelled)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.folder],
            asCopy: false
        )
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let selected: (URL) -> Void
        let cancelled: () -> Void

        init(selected: @escaping (URL) -> Void, cancelled: @escaping () -> Void) {
            self.selected = selected
            self.cancelled = cancelled
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard urls.count == 1, let url = urls.first else {
                cancelled()
                return
            }
            selected(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            cancelled()
        }
    }
}

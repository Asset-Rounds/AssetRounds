import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupRestoreProgressView: View {
    static let screenAccessibilityIdentifier = "s6.4.restore.screen"
    static let chooseAccessibilityIdentifier = "s6.4.restore.choose"
    static let confirmAccessibilityIdentifier = "s6.4.restore.confirm"
    static let cancelAccessibilityIdentifier = "s6.4.restore.cancel"
    static let progressAccessibilityIdentifier = "s6.4.restore.progress"
    static let errorAccessibilityIdentifier = "s6.4.restore.error"
    static let signCountAccessibilityIdentifier = "s6.4.restore.sign-count"
    static let reportCountAccessibilityIdentifier = "s6.4.restore.report-count"
    static let photoCountAccessibilityIdentifier = "s6.4.restore.photo-count"

    let applicationSupportURL: URL
    let currentModelContext: ModelContext
    let currentGenerationID: UUID
    let currentGenerationRootURL: URL
    let selectedPackageForUITest: URL?
    let onRestored: @MainActor (StoreGenerationSession) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var validatedPackage: ValidatedV4BackupPackageV1?
    @State private var showsImporter = false
    @State private var isChecking = false
    @State private var isRestoring = false
    @State private var errorMessage: String?
    @State private var didStartUITestSelection = false
    @State private var didComplete = false
    @AccessibilityFocusState private var headingFocused: Bool

    init(
        applicationSupportURL: URL,
        currentModelContext: ModelContext,
        currentGenerationID: UUID,
        currentGenerationRootURL: URL,
        selectedPackageForUITest: URL? = nil,
        onRestored: @escaping @MainActor (StoreGenerationSession) async -> Void
    ) {
        self.applicationSupportURL = applicationSupportURL
        self.currentModelContext = currentModelContext
        self.currentGenerationID = currentGenerationID
        self.currentGenerationRootURL = currentGenerationRootURL
        self.selectedPackageForUITest = selectedPackageForUITest
        self.onRestored = onRestored
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                    WorklightCard {
                        Text("Restore data backup")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(DesignTokens.Colors.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityFocused($headingFocused)

                        if let summary = validatedPackage?.summary {
                            summaryContent(summary)
                        } else {
                            Text("Choose a Field Evidence backup to restore.")
                                .font(.body)
                                .foregroundStyle(DesignTokens.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let errorMessage {
                            WorklightStatusBadge(
                                kind: .blocked,
                                text: errorMessage
                            )
                            .accessibilityIdentifier(Self.errorAccessibilityIdentifier)
                        }

                        if isChecking || isRestoring {
                            ProgressView(
                                isRestoring ? "Restoring backup" : "Checking backup"
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier(Self.progressAccessibilityIdentifier)
                        }
                    }

                    if validatedPackage == nil {
                        Button("Choose backup") {
                            guard !isBusy else { return }
                            showsImporter = true
                        }
                        .buttonStyle(WorklightPrimaryButtonStyle())
                        .disabled(isBusy)
                        .accessibilityIdentifier(Self.chooseAccessibilityIdentifier)
                    } else {
                        Button("Restore data backup") {
                            confirmRestore()
                        }
                        .buttonStyle(WorklightPrimaryButtonStyle())
                        .disabled(isBusy)
                        .accessibilityIdentifier(Self.confirmAccessibilityIdentifier)
                    }

                    Button("Cancel") {
                        cancel()
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .disabled(isBusy)
                    .accessibilityIdentifier(Self.cancelAccessibilityIdentifier)
                }
                .padding(DesignTokens.Spacing.medium)
            }
            .navigationTitle("Restore")
            .navigationBarTitleDisplayMode(.inline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [Self.backupType],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first, urls.count == 1 else {
                    errorMessage = "Backup unavailable"
                    return
                }
                validateSelection(url)
            case .failure:
                errorMessage = "Backup unavailable"
            }
        }
        .task {
            await Task.yield()
            headingFocused = true
            guard !didStartUITestSelection,
                  let selectedPackageForUITest else { return }
            didStartUITestSelection = true
            validateSelection(selectedPackageForUITest, alreadyAuthorized: true)
        }
        .onDisappear {
            guard !didComplete, !isRestoring else { return }
            discardValidatedPackage()
        }
    }

    @ViewBuilder
    private func summaryContent(_ summary: BackupValidationSummaryV1) -> some View {
        Text("\(summary.incomingSignCount) \(summary.incomingSignCount == 1 ? "sign" : "signs")")
            .summaryLine()
            .accessibilityIdentifier(Self.signCountAccessibilityIdentifier)
        Text("\(summary.incomingReportCount) \(summary.incomingReportCount == 1 ? "report" : "reports")")
            .summaryLine()
            .accessibilityIdentifier(Self.reportCountAccessibilityIdentifier)
        Text("\(summary.incomingPhotoCount) \(summary.incomingPhotoCount == 1 ? "photo" : "photos")")
            .summaryLine()
            .accessibilityIdentifier(Self.photoCountAccessibilityIdentifier)
        Text("\(summary.consumedRootCount) counted roots")
            .summaryLine()
        Text("\(summary.liveSlotCount) live, \(summary.tombstonedSlotCount) deleted")
            .summaryLine()
    }

    private var isBusy: Bool { isChecking || isRestoring }

    private func validateSelection(
        _ url: URL,
        alreadyAuthorized: Bool = false
    ) {
        guard !isBusy else { return }
        discardValidatedPackage()
        isChecking = true
        errorMessage = nil
        defer { isChecking = false }
        do {
            let importer = try BackupImportService(
                generationRootURL: currentGenerationRootURL,
                scopedAccess: alreadyAuthorized ? .alreadyAuthorized : .live
            )
            validatedPackage = try importer.stageAndValidate(
                selectedPackageURL: url
            )
        } catch {
            validatedPackage = nil
            errorMessage = "Backup unavailable"
        }
    }

    private func confirmRestore() {
        guard let package = validatedPackage, !isBusy else { return }
        isRestoring = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let service = try BackupRestoreService(
                    applicationSupportURL: applicationSupportURL
                )
                let session = try await service.restore(
                    validatedPackage: package,
                    currentModelContext: currentModelContext,
                    currentGenerationID: currentGenerationID,
                    currentGenerationRootURL: currentGenerationRootURL
                )
                validatedPackage = nil
                didComplete = true
                await onRestored(session)
                dismiss()
            } catch {
                isRestoring = false
                errorMessage = "Backup could not be restored"
            }
        }
    }

    private func cancel() {
        guard !isBusy else { return }
        discardValidatedPackage()
        dismiss()
    }

    private func discardValidatedPackage() {
        guard let package = validatedPackage else { return }
        do {
            try BackupImportService(
                generationRootURL: currentGenerationRootURL,
                scopedAccess: .alreadyAuthorized
            ).discard(package)
        } catch {
            errorMessage = "Backup cleanup unavailable"
            return
        }
        validatedPackage = nil
    }

    private static let backupType = UTType(
        "com.palatis3.fieldrecordbackup"
    ) ?? .package
}

private extension View {
    func summaryLine() -> some View {
        self
            .font(.headline)
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

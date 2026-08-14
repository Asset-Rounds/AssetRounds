import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupRestoreProgressView: View {
    static let screenAccessibilityIdentifier = "s6.4.restore.screen"
    static let settingsEntryAccessibilityIdentifier = "s6.5.restore.settings-entry"
    static let chooseAccessibilityIdentifier = "s6.4.restore.choose"
    static let confirmAccessibilityIdentifier = "s6.4.restore.confirm"
    static let cancelAccessibilityIdentifier = "s6.4.restore.cancel"
    static let progressAccessibilityIdentifier = "s6.4.restore.progress"
    static let errorAccessibilityIdentifier = "s6.4.restore.error"
    static let signCountAccessibilityIdentifier = "s6.4.restore.sign-count"
    static let reportCountAccessibilityIdentifier = "s6.4.restore.report-count"
    static let photoCountAccessibilityIdentifier = "s6.4.restore.photo-count"
    static let currentSummaryAccessibilityIdentifier = "s6.5.restore.current-summary"
    static let incomingSummaryAccessibilityIdentifier = "s6.5.restore.incoming-summary"
    static let currentSignCountAccessibilityIdentifier = "s6.5.restore.current-sign-count"
    static let currentReportCountAccessibilityIdentifier = "s6.5.restore.current-report-count"
    static let currentPhotoCountAccessibilityIdentifier = "s6.5.restore.current-photo-count"
    static let currentRootCountAccessibilityIdentifier = "s6.5.restore.current-root-count"
    static let currentSizeAccessibilityIdentifier = "s6.5.restore.current-size"
    static let incomingDateAccessibilityIdentifier = "s6.5.restore.incoming-date"
    static let incomingSizeAccessibilityIdentifier = "s6.5.restore.incoming-size"
    static let backupCurrentAccessibilityIdentifier = "s6.5.restore.backup-current"
    static let replaceAccessibilityIdentifier = "s6.5.restore.replace"

    let applicationSupportURL: URL
    let currentModelContext: ModelContext
    let currentGenerationID: UUID
    let currentGenerationRootURL: URL
    let mode: BackupRestoreMode
    let selectedPackageForUITest: URL?
    let onRestored: @MainActor (StoreGenerationSession) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var validatedPackage: ValidatedV4BackupPackageV1?
    @State private var currentSummary: BackupRestoreCurrentSummaryV1?
    @State private var showsImporter = false
    @State private var showsCurrentBackup = false
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
        mode: BackupRestoreMode = .emptyInstall,
        selectedPackageForUITest: URL? = nil,
        onRestored: @escaping @MainActor (StoreGenerationSession) async -> Void
    ) {
        self.applicationSupportURL = applicationSupportURL
        self.currentModelContext = currentModelContext
        self.currentGenerationID = currentGenerationID
        self.currentGenerationRootURL = currentGenerationRootURL
        self.mode = mode
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
                            if mode == .replaceExisting,
                               let currentSummary {
                                currentSummaryContent(currentSummary)
                                incomingSummaryContent(summary)
                            } else {
                                summaryContent(summary)
                            }
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
                    } else if mode == .replaceExisting {
                        Button("Back up current data") {
                            guard !isBusy else { return }
                            showsCurrentBackup = true
                        }
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .disabled(isBusy)
                        .accessibilityIdentifier(Self.backupCurrentAccessibilityIdentifier)

                        Button("Replace current data") {
                            confirmRestore()
                        }
                        .buttonStyle(WorklightPrimaryButtonStyle())
                        .disabled(isBusy)
                        .accessibilityIdentifier(Self.replaceAccessibilityIdentifier)
                    } else {
                        Button("Restore data backup") { confirmRestore() }
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
        .interactiveDismissDisabled(validatedPackage != nil || isBusy)
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
        .navigationDestination(isPresented: $showsCurrentBackup) {
            BackupExportView(
                modelContext: currentModelContext,
                generationRootURL: currentGenerationRootURL
            )
        }
        .task {
            await Task.yield()
            headingFocused = true
            if mode == .replaceExisting, currentSummary == nil {
                do {
                    currentSummary = try BackupRestoreService.currentSummary(
                        modelContext: currentModelContext,
                        generationRootURL: currentGenerationRootURL
                    )
                } catch {
                    errorMessage = "Current data unavailable"
                    return
                }
            }
            guard !didStartUITestSelection,
                  let selectedPackageForUITest else { return }
            didStartUITestSelection = true
            validateSelection(selectedPackageForUITest, alreadyAuthorized: true)
        }
        .onDisappear {
            guard !didComplete, !isRestoring, !showsCurrentBackup else { return }
            _ = discardValidatedPackage()
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
        Text("\(summary.consumedRootCount) counted \(summary.consumedRootCount == 1 ? "root" : "roots")")
            .summaryLine()
        Text("\(summary.liveSlotCount) live, \(summary.tombstonedSlotCount) deleted")
            .summaryLine()
    }

    @ViewBuilder
    private func currentSummaryContent(
        _ summary: BackupRestoreCurrentSummaryV1
    ) -> some View {
        Text("Current data")
            .font(.headline)
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(Self.currentSummaryAccessibilityIdentifier)
        Text("\(summary.signCount) \(summary.signCount == 1 ? "sign" : "signs")")
            .summaryLine()
            .accessibilityIdentifier(Self.currentSignCountAccessibilityIdentifier)
        Text("\(summary.reportCount) \(summary.reportCount == 1 ? "report" : "reports")")
            .summaryLine()
            .accessibilityIdentifier(Self.currentReportCountAccessibilityIdentifier)
        Text("\(summary.photoCount) \(summary.photoCount == 1 ? "photo" : "photos")")
            .summaryLine()
            .accessibilityIdentifier(Self.currentPhotoCountAccessibilityIdentifier)
        Text("\(summary.consumedRootCount) counted \(summary.consumedRootCount == 1 ? "root" : "roots")")
            .summaryLine()
            .accessibilityIdentifier(Self.currentRootCountAccessibilityIdentifier)
        Text("Estimated backup size \(formattedBytes(summary.declaredPayloadByteCount))")
            .summaryLine()
            .accessibilityIdentifier(Self.currentSizeAccessibilityIdentifier)
    }

    @ViewBuilder
    private func incomingSummaryContent(
        _ summary: BackupValidationSummaryV1
    ) -> some View {
        Text("Incoming backup")
            .font(.headline)
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(Self.incomingSummaryAccessibilityIdentifier)
        summaryContent(summary)
        Text("Backup date \(summary.exportedAt.formatted(date: .abbreviated, time: .shortened))")
            .summaryLine()
            .accessibilityIdentifier(Self.incomingDateAccessibilityIdentifier)
        Text("Backup size \(formattedBytes(summary.declaredPayloadByteCount))")
            .summaryLine()
            .accessibilityIdentifier(Self.incomingSizeAccessibilityIdentifier)
    }

    private var isBusy: Bool { isChecking || isRestoring }

    private func validateSelection(
        _ url: URL,
        alreadyAuthorized: Bool = false
    ) {
        guard !isBusy else { return }
        guard discardValidatedPackage() else { return }
        isChecking = true
        errorMessage = nil
        defer { isChecking = false }
        var stagedPackage: ValidatedV4BackupPackageV1?
        var importer: BackupImportService?
        do {
            let service = try BackupImportService(
                generationRootURL: currentGenerationRootURL,
                scopedAccess: alreadyAuthorized ? .alreadyAuthorized : .live
            )
            importer = service
            let package = try service.stageAndValidate(
                selectedPackageURL: url
            )
            stagedPackage = package
            if mode == .replaceExisting {
                currentSummary = try BackupRestoreService.currentSummary(
                    modelContext: currentModelContext,
                    generationRootURL: currentGenerationRootURL
                )
            }
            validatedPackage = package
        } catch {
            if let stagedPackage, let importer {
                do {
                    try importer.discard(stagedPackage)
                } catch {
                    errorMessage = "Backup cleanup unavailable"
                    return
                }
            }
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
                    currentGenerationRootURL: currentGenerationRootURL,
                    mode: mode
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
        guard discardValidatedPackage() else { return }
        dismiss()
    }

    @discardableResult
    private func discardValidatedPackage() -> Bool {
        guard let package = validatedPackage else { return true }
        do {
            try BackupImportService(
                generationRootURL: currentGenerationRootURL,
                scopedAccess: .alreadyAuthorized
            ).discard(package)
        } catch {
            errorMessage = "Backup cleanup unavailable"
            return false
        }
        validatedPackage = nil
        return true
    }

    private static let backupType = UTType(
        "com.palatis3.fieldrecordbackup"
    ) ?? .package

    private func formattedBytes(_ value: Int) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(value),
            countStyle: .file
        )
    }
}

private extension View {
    func summaryLine() -> some View {
        self
            .font(.headline)
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

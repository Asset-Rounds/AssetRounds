import Foundation
import SwiftData
import SwiftUI

private struct EraseAllAction {
    let call: @MainActor () -> Void
}

private struct EraseAllActionKey: EnvironmentKey {
    static let defaultValue = EraseAllAction(call: {})
}

private extension EnvironmentValues {
    var eraseAllAction: EraseAllAction {
        get { self[EraseAllActionKey.self] }
        set { self[EraseAllActionKey.self] = newValue }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Local, resettable evidence for the synthetic C06 renderer. It has no
/// persistence, telemetry, or connection to production diagnostics.
struct TestOnlyPseudoLocalizationDiagnosticSnapshotV1: Equatable, Sendable {
    let resolvedCount: Int
    let unresolvedKeyCount: Int
    let unexpectedFallbackCount: Int
}


enum TestOnlyPseudoLocalizationDiagnosticsV1 {
    private static let lock = NSLock()
    private static var resolvedIdentifiers = Set<String>()
    private static var unresolvedIdentifiers = Set<String>()
    private static var fallbackIdentifiers = Set<String>()

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        resolvedIdentifiers.removeAll()
        unresolvedIdentifiers.removeAll()
        fallbackIdentifiers.removeAll()
    }

    static func snapshot() -> TestOnlyPseudoLocalizationDiagnosticSnapshotV1 {
        lock.lock()
        defer { lock.unlock() }
        return TestOnlyPseudoLocalizationDiagnosticSnapshotV1(
            resolvedCount: resolvedIdentifiers.count,
            unresolvedKeyCount: unresolvedIdentifiers.count,
            unexpectedFallbackCount: fallbackIdentifiers.count
        )
    }

    fileprivate static func recordResolved(_ identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        unresolvedIdentifiers.remove(identifier)
        fallbackIdentifiers.remove(identifier)
        resolvedIdentifiers.insert(identifier)
    }

    fileprivate static func recordUnresolved(_ identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        resolvedIdentifiers.remove(identifier)
        fallbackIdentifiers.remove(identifier)
        unresolvedIdentifiers.insert(identifier)
    }

    fileprivate static func recordFallback(_ identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        resolvedIdentifiers.remove(identifier)
        unresolvedIdentifiers.remove(identifier)
        fallbackIdentifiers.insert(identifier)
    }
}

/// Resolver used solely by the synthetic scene. Unknown identifiers never
/// become displayed text, which makes an unresolved key visible without
/// leaking a raw localization key into a screenshot.
enum TestOnlyPseudoLocalizationResolverV1 {
    private static let supportedIdentifiers: Set<String> = [
        "pseudo.title",
        "pseudo.summary",
        "pseudo.status",
        "pseudo.identifier",
        "pseudo.primaryAction",
        "pseudo.navigation",
        "pseudo.input",
        "pseudo.recovery",
        "pseudo.error",
        "pseudo.fallbackProbe",
    ]
    private static let englishOnlyProbeValues = [
        "pseudo.fallbackProbe": "Fallback probe",
    ]
    private static let pseudoEligibleIdentifiers = supportedIdentifiers.subtracting(
        englishOnlyProbeValues.keys
    )

    static func render(
        semanticID: String,
        english: String,
        configuration: V30PseudoLocalizationLaunchConfigurationV1
    ) -> String {
        let diagnosticIdentifier = supportedIdentifiers.contains(semanticID)
            ? semanticID
            : "unrecognizedSemanticID"
        let sourceEnglish = englishOnlyProbeValues[semanticID] ?? english
        guard supportedIdentifiers.contains(semanticID), !sourceEnglish.isEmpty else {
            TestOnlyPseudoLocalizationDiagnosticsV1.recordUnresolved(diagnosticIdentifier)
            return "[unresolved test string]"
        }
        guard pseudoEligibleIdentifiers.contains(semanticID) else {
            TestOnlyPseudoLocalizationDiagnosticsV1.recordFallback(diagnosticIdentifier)
            return sourceEnglish
        }
        TestOnlyPseudoLocalizationDiagnosticsV1.recordResolved(diagnosticIdentifier)
        return transform(sourceEnglish, profile: configuration.profile)
    }

    private static func transform(
        _ english: String,
        profile: V30PseudoLocalizationLaunchConfigurationV1.Profile
    ) -> String {
        let protectedPattern = "%%|%[0-9]+\\$@|%[0-9]+\\$lld|%lld|%@|\\{[^}]+\\}"
        guard let expression = try? NSRegularExpression(pattern: protectedPattern) else {
            return transformPlainText(english, profile: profile)
        }
        let range = NSRange(english.startIndex..., in: english)
        let matches = expression.matches(in: english, range: range)
        var result = ""
        var cursor = english.startIndex
        for match in matches {
            guard let tokenRange = Range(match.range, in: english) else { continue }
            result += transformPlainText(String(english[cursor..<tokenRange.lowerBound]), profile: profile)
            result += String(english[tokenRange])
            cursor = tokenRange.upperBound
        }
        result += transformPlainText(String(english[cursor...]), profile: profile)
        return result
    }

    private static func transformPlainText(
        _ text: String,
        profile: V30PseudoLocalizationLaunchConfigurationV1.Profile
    ) -> String {
        switch profile {
        case .enXA:
            let accents: [Character: Character] = [
                "a": "á", "e": "ë", "i": "ï", "o": "ô", "u": "ü",
                "A": "Á", "E": "Ë", "I": "Ï", "O": "Ô", "U": "Ü",
            ]
            let accented = text.map { accents[$0] ?? $0 }.reduce(into: "") { $0.append($1) }
            return text.isEmpty ? text : "⟦\(accented) ··⟧"
        case .enXL:
            return text.isEmpty ? text : "⟦\(text) · \(text)⟧"
        case .arXB:
            return text.isEmpty ? text : "\u{202B}⟦\(text)⟧\u{202C}"
        }
    }
}

private struct PseudoLocalizationScreenshotHarnessContentV1 {
    let title: String
    let summary: String
    let status: String
    let identifierLabel: String
    let identifierValue = "FE-0427-2026"
    let primaryAction: String
    let navigation: String
    let input: String
    let recovery: String
    let error: String

    init(configuration: V30PseudoLocalizationLaunchConfigurationV1) {
        title = TestOnlyPseudoLocalizationResolverV1.render(
            semanticID: "pseudo.title",
            english: BundledLocalizationCatalogV1.v30Text(
                .shellSignsTab,
                languageLocale: Locale(identifier: "en")
            ),
            configuration: configuration
        )
        summary = TestOnlyPseudoLocalizationResolverV1.render(
            semanticID: "pseudo.summary",
            english: "Review the evidence before completing this round.",
            configuration: configuration
        )
        status = TestOnlyPseudoLocalizationResolverV1.render(
            semanticID: "pseudo.status",
            english: "Requires attention",
            configuration: configuration
        )
        identifierLabel = TestOnlyPseudoLocalizationResolverV1.render(
            semanticID: "pseudo.identifier",
            english: "Serial:",
            configuration: configuration
        )
        primaryAction = TestOnlyPseudoLocalizationResolverV1.render(
            semanticID: "pseudo.primaryAction",
            english: "Continue review",
            configuration: configuration
        )
        navigation = TestOnlyPseudoLocalizationResolverV1.render(
            semanticID: "pseudo.navigation",
            english: "Review navigation",
            configuration: configuration
        )
        input = TestOnlyPseudoLocalizationResolverV1.render(
            semanticID: "pseudo.input",
            english: "Add an inspection note",
            configuration: configuration
        )
        recovery = TestOnlyPseudoLocalizationResolverV1.render(
            semanticID: "pseudo.recovery",
            english: "Recovery remains available",
            configuration: configuration
        )
        error = TestOnlyPseudoLocalizationResolverV1.render(
            semanticID: "pseudo.error",
            english: "Synthetic validation message",
            configuration: configuration
        )
    }
}

private struct PseudoLocalizationObservedEnvironmentV1: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var observedDynamicType: String {
        switch dynamicTypeSize {
        case .large: return "large"
        case .accessibility5: return "accessibility5"
        default: return String(describing: dynamicTypeSize)
        }
    }

    var body: some View {
        Text("layoutDirection \(layoutDirection == .rightToLeft ? "rightToLeft" : "leftToRight") • dynamicType \(observedDynamicType) • colorScheme \(colorScheme == .dark ? "dark" : "light") • contrast \(colorSchemeContrast == .increased ? "increased" : "normal")")
            .font(.footnote)
            .accessibilityIdentifier("v30.pseudo.observed-environment")
    }
}
struct PseudoLocalizationScreenshotHarnessView: View {
    let configuration: V30PseudoLocalizationLaunchConfigurationV1
    private let content: PseudoLocalizationScreenshotHarnessContentV1
    @State private var completed = false
    @State private var note = ""
    @State private var showsError = false
    @State private var finalActionCompleted = false
    @FocusState private var noteIsFocused: Bool
    @State private var diagnosticSnapshot = TestOnlyPseudoLocalizationDiagnosticSnapshotV1(resolvedCount: 0, unresolvedKeyCount: 0, unexpectedFallbackCount: 0)

    init(configuration: V30PseudoLocalizationLaunchConfigurationV1) {
        self.configuration = configuration
        content = PseudoLocalizationScreenshotHarnessContentV1(configuration: configuration)
    }

    var body: some View {
        let diagnostics = diagnosticSnapshot
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                    Text(content.title)
                        .font(.largeTitle.weight(.bold))
                        .modifier(GlobalizationAdaptiveLayoutPolicyV1())
                        .accessibilityIdentifier("v30.pseudo.title")
                        .accessibilityAddTraits(.isHeader)

                    Text(content.summary)
                        .font(.body)
                        .modifier(GlobalizationAdaptiveLayoutPolicyV1())
                        .accessibilityIdentifier("v30.pseudo.summary")

                    WorklightCard {
                        Text(content.status)
                            .font(.headline)
                            .modifier(GlobalizationAdaptiveLayoutPolicyV1())
                            .accessibilityIdentifier("v30.pseudo.status")
                        VStack(alignment: .leading) {
                            Text(content.identifierLabel)
                            Text(GlobalizationRTLSemanticsV1.opaqueFallback(nil, identifier: content.identifierValue))
                                .font(.body.monospaced())
                                .accessibilityIdentifier("v30.pseudo.identifier")
                        }
                        .modifier(GlobalizationAdaptiveLayoutPolicyV1())
                        Button(content.primaryAction) { completed = true }
                            .buttonStyle(WorklightPrimaryButtonStyle())
                            .accessibilityIdentifier("v30.pseudo.primary-action")
                        if completed {
                            Text("Synthetic review complete")
                                .font(.footnote)
                                .accessibilityIdentifier("v30.pseudo.completion")
                        }
                    }

                    WorklightCard {
                        NavigationLink {
                            Text(content.summary).modifier(GlobalizationAdaptiveLayoutPolicyV1())
                                .accessibilityIdentifier("v30.pseudo.navigation-destination")
                        } label: {
                            Text(content.navigation)
                                .modifier(GlobalizationAdaptiveLayoutPolicyV1())
                                .frame(minWidth: DesignTokens.Control.minimumHitSize,
                                       minHeight: DesignTokens.Control.minimumHitSize)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("v30.pseudo.navigation")
                        TextField(content.input, text: $note, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .frame(minHeight: DesignTokens.Control.minimumHitSize)
                            .focused($noteIsFocused)
                            .accessibilityIdentifier("v30.pseudo.input")
                        Button(content.error) {
                            noteIsFocused = false
                            showsError = true
                        }
                            .buttonStyle(WorklightSecondaryButtonStyle())
                            .accessibilityIdentifier("v30.pseudo.error-trigger")
                        if showsError {
                            Text(content.error)
                                .font(.footnote)
                                .modifier(GlobalizationAdaptiveLayoutPolicyV1())
                                .accessibilityIdentifier("v30.pseudo.error")
                            Button(content.recovery) { showsError = false }
                                .buttonStyle(WorklightSecondaryButtonStyle())
                                .accessibilityIdentifier("v30.pseudo.recovery")
                        }
                        Button("Record unresolved diagnostic") {
                            _ = TestOnlyPseudoLocalizationResolverV1.render(semanticID: "private.unresolved", english: "ignored", configuration: configuration)
                            diagnosticSnapshot = TestOnlyPseudoLocalizationDiagnosticsV1.snapshot()
                        }
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .accessibilityIdentifier("v30.pseudo.unresolved-trigger")
                        Button("Record fallback diagnostic") {
                            _ = TestOnlyPseudoLocalizationResolverV1.render(semanticID: "pseudo.fallbackProbe", english: "Fallback probe", configuration: configuration)
                            diagnosticSnapshot = TestOnlyPseudoLocalizationDiagnosticsV1.snapshot()
                        }
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .accessibilityIdentifier("v30.pseudo.fallback-trigger")
                        Button("Reset diagnostics") {
                            TestOnlyPseudoLocalizationDiagnosticsV1.reset()
                            diagnosticSnapshot = TestOnlyPseudoLocalizationDiagnosticsV1.snapshot()
                        }
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .accessibilityIdentifier("v30.pseudo.diagnostics-reset")
                    }

                    PseudoLocalizationObservedEnvironmentV1()
                    Text(verbatim: "NFD: cafe\u{301} • ZWJ: 👩‍🔧 • CJK: 漢字 • Hangul: 한글 • Arabic: العربية")
                        .font(.footnote)
                        .accessibilityIdentifier("v30.pseudo.authored-source")
                    Text(BundledLocalizationCatalogV1.v30Text(
                        .shellSignsTab,
                        languageLocale: Locale(identifier: "en")
                    ))
                    .font(.footnote)
                    .accessibilityIdentifier("v30.pseudo.catalog-source")

                    Button(content.primaryAction) { finalActionCompleted = true }
                        .buttonStyle(WorklightPrimaryButtonStyle())
                        .accessibilityIdentifier("v30.pseudo.final-action")
                    if finalActionCompleted {
                        Text("Synthetic final action completed")
                            .modifier(GlobalizationAdaptiveLayoutPolicyV1())
                            .accessibilityIdentifier("v30.pseudo.final-completion")
                    }
                    Text(
                        "Profile \(configuration.profile.rawValue) • Dynamic Type \(configuration.dynamicType.rawValue) • \(configuration.appearance.rawValue) • contrast \(configuration.contrast.rawValue) • states navigation/input/recovery/error • resolved \(diagnostics.resolvedCount) • unresolved \(diagnostics.unresolvedKeyCount) • unexpected fallback \(diagnostics.unexpectedFallbackCount)"
                    )
                    .font(.footnote)
                    .modifier(GlobalizationAdaptiveLayoutPolicyV1())
                    .accessibilityIdentifier("v30.pseudo.diagnostics")
                }
                .padding(DesignTokens.Spacing.medium)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { noteIsFocused = false }
                        .accessibilityIdentifier("v30.pseudo.keyboard-dismiss")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .environment(\.layoutDirection, configuration.profile.isRightToLeft ? .rightToLeft : .leftToRight)
        .environment(
            \.dynamicTypeSize,
            configuration.dynamicType == .large ? .large : .accessibility5
        )
        .environment(
            \.colorSchemeContrast,
            configuration.contrast == .increased ? .increased : .standard
        )
        .preferredColorScheme(configuration.appearance == .dark ? .dark : .light)
        .accessibilityIdentifier("v30.pseudo.screen")
        .onAppear { diagnosticSnapshot = TestOnlyPseudoLocalizationDiagnosticsV1.snapshot() }
    }
}
#endif

struct AppShellView: View {
    static let screenAccessibilityIdentifier = "s1.shell.screen"
    static let signsTabAccessibilityIdentifier = "s1.tab.signs"
    static let reportsTabAccessibilityIdentifier = "s1.tab.reports"
    static let settingsButtonAccessibilityIdentifier = "s1.settings.button"
    static let settingsScreenAccessibilityIdentifier = "s1.settings.screen"
    static let reportsPlaceholderAccessibilityIdentifier = "s1.reports.placeholder"
    static let unavailableAccessibilityIdentifier = "s1.pack.unavailable"

    @Environment(\.colorScheme) private var colorScheme

    private enum Tab: Hashable {
        case signs
        case reports
    }

    let packLoadResult: SignPackLoadResult
    let exposesColorSchemeForUITest: Bool
    let modelContext: ModelContext
    let diagnosticsStore: DiagnosticsStore
    let metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter
    let feedbackConfiguration: FeedbackConfigurationV1
    let mailComposerAdapter: MailComposerAdapter
    let generationRootURL: URL
    let usesImportedCaptureFixturesForUITest: Bool
    let injectsLowStorageFailureOnceForUITest: Bool
    let cameraAdapter: CameraAdapter
    let restoreDataBackup: @MainActor () -> Void
    let replaceDataBackup: @MainActor () -> Void
    let eraseAll: @MainActor () -> Void

    @StateObject private var purchaseCoordinator: StoreKitPurchaseCoordinator
    @StateObject private var lifecycleCoordinator: StoreKitLifecycleCoordinator

    @State private var selectedTab: Tab = .signs

    init(
        packLoadResult: SignPackLoadResult,
        exposesColorSchemeForUITest: Bool = false,
        modelContext: ModelContext,
        diagnosticsStore: DiagnosticsStore,
        metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter,
        feedbackConfiguration: FeedbackConfigurationV1,
        mailComposerAdapter: MailComposerAdapter,
        generationRootURL: URL,
        usesImportedCaptureFixturesForUITest: Bool = false,
        injectsLowStorageFailureOnceForUITest: Bool = false,
        cameraAdapter: CameraAdapter = .live,
        entitlementProcessor: StoreKitTransactionProcessor? = nil,
        paywallCatalogLinks: PaywallCatalogLinksV1? = nil,
        restoreDataBackup: @escaping @MainActor () -> Void = {},
        replaceDataBackup: @escaping @MainActor () -> Void = {},
        eraseAll: @escaping @MainActor () -> Void = {}
    ) {
        self.packLoadResult = packLoadResult
        self.exposesColorSchemeForUITest = exposesColorSchemeForUITest
        self.modelContext = modelContext
        self.diagnosticsStore = diagnosticsStore
        self.metricKitDiagnosticsAdapter = metricKitDiagnosticsAdapter
        self.feedbackConfiguration = feedbackConfiguration
        self.mailComposerAdapter = mailComposerAdapter
        self.generationRootURL = generationRootURL
        self.usesImportedCaptureFixturesForUITest = usesImportedCaptureFixturesForUITest
        self.injectsLowStorageFailureOnceForUITest =
            injectsLowStorageFailureOnceForUITest
        self.cameraAdapter = cameraAdapter
        _purchaseCoordinator = StateObject(
            wrappedValue: StoreKitPurchaseCoordinator(
                processor: entitlementProcessor,
                diagnosticsStore: diagnosticsStore,
                catalogLinks: paywallCatalogLinks
            )
        )
        _lifecycleCoordinator = StateObject(
            wrappedValue: StoreKitLifecycleCoordinator(
                processor: entitlementProcessor
            )
        )
        self.restoreDataBackup = restoreDataBackup
        self.replaceDataBackup = replaceDataBackup
        self.eraseAll = eraseAll
    }

    var body: some View {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--s6-3-ui-test-validation-summary")
            || arguments.contains("--s6-4-ui-test-export-source") {
            S6_3BackupValidationUITestHost(
                modelContext: modelContext,
                generationRootURL: generationRootURL,
                keepsPackageForRestoreUITest: arguments.contains(
                    "--s6-4-ui-test-export-source"
                )
            )
        } else {
            switch packLoadResult {
            case let .available(pack):
                availableShell(pack: pack)
            case .unavailable:
                PackUnavailableView()
                    .accessibilityIdentifier(Self.unavailableAccessibilityIdentifier)
            }
        }
    }

    private func availableShell(pack: SignPack) -> some View {
        TabView(selection: $selectedTab) {
            SignsRootView(
                modelContext: modelContext,
                diagnosticsStore: diagnosticsStore,
                metricKitDiagnosticsAdapter: metricKitDiagnosticsAdapter,
                feedbackConfiguration: feedbackConfiguration,
                mailComposerAdapter: mailComposerAdapter,
                pack: pack,
                generationRootURL: generationRootURL,
                usesImportedCaptureFixturesForUITest: usesImportedCaptureFixturesForUITest,
                injectsLowStorageFailureOnceForUITest:
                    injectsLowStorageFailureOnceForUITest,
                cameraAdapter: cameraAdapter,
                purchaseCoordinator: purchaseCoordinator,
                lifecycleCoordinator: lifecycleCoordinator,
                restoreDataBackup: restoreDataBackup,
                replaceDataBackup: replaceDataBackup
            )
            .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
            .accessibilityValue(
                exposesColorSchemeForUITest
                    ? (colorScheme == .dark ? BundledLocalizationCatalogV1.v30Text(.shellDarkAppearance) : BundledLocalizationCatalogV1.v30Text(.shellLightAppearance))
                    : ""
            )
            .tag(Tab.signs)
            .tabItem {
                Label(BundledLocalizationCatalogV1.v30Text(.shellSignsTab), systemImage: "signpost.right.fill")
                    .accessibilityIdentifier(Self.signsTabAccessibilityIdentifier)
            }

            NavigationStack {
                ReportsRootView(
                    modelContext: modelContext,
                    generationRootURL: generationRootURL,
                    diagnosticsStore: diagnosticsStore,
                    signPack: pack
                )
                    .toolbar {
                        settingsToolbar
                    }
            }
            .tag(Tab.reports)
            .tabItem {
                Label(BundledLocalizationCatalogV1.v30Text(.shellReportsTab), systemImage: "doc.text.fill")
                    .accessibilityIdentifier(Self.reportsTabAccessibilityIdentifier)
            }
        }
        .tint(DesignTokens.Colors.interactionAccent)
        .background(DesignTokens.Colors.canvas)
        .environment(\.eraseAllAction, EraseAllAction(call: eraseAll))
    }

    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                SettingsPlaceholderView(
                    modelContext: modelContext,
                    generationRootURL: generationRootURL,
                    diagnosticsStore: diagnosticsStore,
                    metricKitDiagnosticsAdapter: metricKitDiagnosticsAdapter,
                    feedbackConfiguration: feedbackConfiguration,
                    mailComposerAdapter: mailComposerAdapter,
                    purchaseCoordinator: purchaseCoordinator,
                    lifecycleCoordinator: lifecycleCoordinator,
                    restoreDataBackup: replaceDataBackup
                )
            } label: {
                Image(systemName: "gearshape")
            }
            .frame(
                minWidth: DesignTokens.Control.minimumHitSize,
                minHeight: DesignTokens.Control.minimumHitSize
            )
            .contentShape(Rectangle())
            .accessibilityLabel(BundledLocalizationCatalogV1.v30Text(.shellSettingsAccessibilityLabel))
            .accessibilityIdentifier(Self.settingsButtonAccessibilityIdentifier)
        }
    }
}

private struct S6_3BackupValidationUITestHost: View {
    let modelContext: ModelContext
    let generationRootURL: URL
    let keepsPackageForRestoreUITest: Bool

    @State private var summary: BackupValidationSummaryV1?
    @State private var didStart = false

    var body: some View {
        Group {
            if let summary {
                BackupValidationSummaryView(summary: summary)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .task {
            guard !didStart else { return }
            didStart = true
            loadValidatedSummary()
        }
    }

    @MainActor
    private func loadValidatedSummary() {
        do {
            let fileManager = FileManager.default
            let destination: URL
            if keepsPackageForRestoreUITest {
                destination = try BackupRestoreService.applicationSupportURL(
                    containing: generationRootURL
                ).appendingPathComponent(
                    "S6_4UITestSource",
                    isDirectory: true
                )
            } else {
                destination = fileManager.temporaryDirectory.appendingPathComponent(
                    "S6_3BackupValidationUITest",
                    isDirectory: true
                )
            }
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.createDirectory(
                at: destination,
                withIntermediateDirectories: false
            )
            try materializeMixedFixture(fileManager: fileManager)
            let exporter = BackupExportService(
                modelContext: modelContext,
                generationRootURL: generationRootURL,
                now: { Date(timeIntervalSince1970: 1_786_708_800) }
            )
            let preview = try exporter.prepare()
            let packageURL = try exporter.export(
                previewID: preview.id,
                to: destination
            )
            let importer = try BackupImportService(
                generationRootURL: generationRootURL,
                scopedAccess: .alreadyAuthorized
            )
            let validatedPackage = try importer.stageAndValidate(
                selectedPackageURL: packageURL
            )
            try importer.discard(validatedPackage)
            summary = validatedPackage.summary
        } catch {
            summary = nil
        }
    }

    @MainActor
    private func materializeMixedFixture(fileManager: FileManager) throws {
        let issues = try modelContext.fetch(FetchDescriptor<Issue>())
        let records = try modelContext.fetch(FetchDescriptor<WorkflowRecord>())
        let reports = try modelContext.fetch(FetchDescriptor<Report>())
        guard issues.count == 1,
              let issue = issues.first,
              issue.status == IssueStatus.resolved.rawValue,
              let resolvedBy = issue.resolvedByRecordID,
              let opening = records.first(where: { $0.id == issue.openedByRecordID }),
              let recheck = records.first(where: {
                  $0.id == resolvedBy
                      && $0.stage == WorkflowStage.recheck.rawValue
                      && $0.revisionKind == WorkflowRevisionKind.original.rawValue
              }),
              let correction = records.first(where: {
                  $0.revisesRecordID == recheck.id
                      && $0.revisionKind == WorkflowRevisionKind.clericalCorrection.rawValue
              }),
              correction.evidenceSourceRecordID == recheck.id,
              let separate = records.first(where: {
                  $0.stage == WorkflowStage.check.rawValue
                      && $0.outcomeKey == "no_visible_issue"
                      && $0.issueID == nil
              }),
              let openingReport = reports.first(where: { $0.sourceRecordID == opening.id }),
              let recheckReport = reports.first(where: { $0.sourceRecordID == recheck.id }),
              let correctionReport = reports.first(where: { $0.sourceRecordID == correction.id }),
              let separateReport = reports.first(where: { $0.sourceRecordID == separate.id }),
              reports.count == 4,
              recheckReport.pdfState == ReportPDFState.ready.rawValue,
              correctionReport.pdfState == ReportPDFState.ready.rawValue,
              correctionReport.replacesReportID == recheckReport.id else {
            throw BackupImportServiceError.invalidSource
        }

        try removeReadyPDF(openingReport, fileManager: fileManager)
        openingReport.pdfState = ReportPDFState.failed.rawValue
        openingReport.pdfRelativePath = nil
        openingReport.pdfSHA256 = nil
        try removeReadyPDF(separateReport, fileManager: fileManager)
        separateReport.pdfState = ReportPDFState.pending.rawValue
        separateReport.pdfRelativePath = nil
        separateReport.pdfSHA256 = nil

        modelContext.insert(Packet(
            id: UUID(uuidString: "63000000-0000-0000-0000-000000000089")!,
            stableRootID: UUID(uuidString: "63000000-0000-0000-0000-000000000090")!,
            currentRecordID: nil,
            evaluationCounted: true,
            contentDeletedAt: Date(timeIntervalSince1970: 1_735_689_590),
            createdAt: Date(timeIntervalSince1970: 1_735_689_500)
        ))
        try modelContext.save()
    }

    private func removeReadyPDF(
        _ report: Report,
        fileManager: FileManager
    ) throws {
        let expectedPath = "pdfs/\(report.id.uuidString.lowercased()).pdf"
        guard report.pdfState == ReportPDFState.ready.rawValue,
              report.pdfRelativePath == expectedPath,
              report.pdfSHA256 != nil else {
            throw BackupImportServiceError.invalidSource
        }
        let rootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL)
        let url = generationRootURL.appendingPathComponent(expectedPath)
        _ = try ReportPDFAnchoredFile.readRegularFile(
            at: url,
            within: generationRootURL,
            rootIdentity: rootIdentity
        )
        try fileManager.removeItem(at: url)
    }
}

struct SettingsPlaceholderView: View {
    private struct PaywallPresentation: Identifiable {
        let id = UUID()
    }

    private struct LifecyclePresentation: Identifiable {
        let id = UUID()
    }

    @Environment(\.eraseAllAction) private var eraseAllAction
    @Environment(\.scenePhase) private var globalizationScenePhase
    @State private var effectiveLanguage = SystemLanguageResolverV1().resolve()
    @State private var globalizationSettingsUnavailable = false
    @AccessibilityFocusState private var globalizationSettingsErrorFocused: Bool
    @State private var globalizationFallbackDiagnostic: EffectiveLanguageFallbackDiagnosticV1?

    @ObservedObject var purchaseCoordinator: StoreKitPurchaseCoordinator
    @ObservedObject var lifecycleCoordinator: StoreKitLifecycleCoordinator

    let modelContext: ModelContext
    let generationRootURL: URL
    let diagnosticsStore: DiagnosticsStore
    let metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter
    let feedbackConfiguration: FeedbackConfigurationV1
    let mailComposerAdapter: MailComposerAdapter
    let restoreDataBackup: @MainActor () -> Void

    @State private var paywallPresentation: PaywallPresentation?
    @State private var lifecyclePresentation: LifecyclePresentation?

    init(
        modelContext: ModelContext,
        generationRootURL: URL,
        diagnosticsStore: DiagnosticsStore,
        metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter,
        feedbackConfiguration: FeedbackConfigurationV1,
        mailComposerAdapter: MailComposerAdapter,
        purchaseCoordinator: StoreKitPurchaseCoordinator,
        lifecycleCoordinator: StoreKitLifecycleCoordinator,
        restoreDataBackup: @escaping @MainActor () -> Void = {}
    ) {
        self.modelContext = modelContext
        self.generationRootURL = generationRootURL
        self.diagnosticsStore = diagnosticsStore
        self.metricKitDiagnosticsAdapter = metricKitDiagnosticsAdapter
        self.feedbackConfiguration = feedbackConfiguration
        self.mailComposerAdapter = mailComposerAdapter
        self.purchaseCoordinator = purchaseCoordinator
        self.lifecycleCoordinator = lifecycleCoordinator
        self.restoreDataBackup = restoreDataBackup
    }

    var body: some View {
        ScrollView {
            WorklightCard {
                Text(BundledLocalizationCatalogV1.v30Text(.shellSettingsHeading))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    Text(BundledLocalizationCatalogV1.v30Text(.shellLanguageAndRegionHeading))
                        .font(.headline)
                        .modifier(GlobalizationAdaptiveLayoutPolicyV1())
                        .accessibilityAddTraits(.isHeader)
                    Text(GlobalizationRTLSemanticsV1.opaqueFallback(
                        Locale.autoupdatingCurrent.localizedString(
                            forLanguageCode: effectiveLanguage.effectiveLanguage.rawValue
                        ),
                        identifier: effectiveLanguage.effectiveLanguage.rawValue
                    ))
                    Text(GlobalizationRTLSemanticsV1.opaqueFallback(
                        Locale.autoupdatingCurrent.localizedString(
                            forIdentifier: Locale.autoupdatingCurrent.identifier
                        ),
                        identifier: Locale.autoupdatingCurrent.identifier
                    ))
                    Text(BundledLocalizationCatalogV1.v30Text(.shellLanguageAndRegionJurisdictionNotice))
                        .font(.footnote)
                    DisclosureGroup(BundledLocalizationCatalogV1.v30Text(.shellLanguageSupportDetails)) {
                        if let diagnostic = globalizationFallbackDiagnostic {
                            if diagnostic.usedEnglishFallback {
                                Text(BundledLocalizationCatalogV1.v30Text(.shellEnglishFallbackExplanation))
                            } else {
                                Text(BundledLocalizationCatalogV1.v30Text(.shellBaseLanguageFallbackExplanation))
                            }
                        } else {
                            Text(BundledLocalizationCatalogV1.v30Text(.shellSystemLanguageExplanation))
                        }
                        Text(BundledLocalizationCatalogV1.v30Text(.shellLanguageSupportPrivacyNotice))
                            .font(.footnote)
                    }
                    .accessibilityIdentifier("v30.language-region.support-summary")
                    Button(BundledLocalizationCatalogV1.v30Text(.shellOpenSystemSettings)) {
                        Task {
                            globalizationSettingsUnavailable =
                                !(await GlobalizationSettingsCoordinatorV1().openAppSettings())
                        }
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityIdentifier("v30.language-region.open-settings")
                    if globalizationSettingsUnavailable {
                        Text(BundledLocalizationCatalogV1.v30Text(.shellSystemSettingsUnavailable))
                            .font(.footnote)
                            .modifier(GlobalizationAdaptiveLayoutPolicyV1())
                            .accessibilityFocused($globalizationSettingsErrorFocused)
                            .onAppear { globalizationSettingsErrorFocused = true }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("v30.language-region.section")
                .onAppear {
                    effectiveLanguage = GlobalizationSettingsCoordinatorV1().refreshEffectiveLanguage()
                    globalizationFallbackDiagnostic = try? PreferencesAdapterV1().readGlobalizationFallback()
                }
                .onChange(of: globalizationScenePhase) { _, phase in
                    if phase == .active {
                        effectiveLanguage = GlobalizationSettingsCoordinatorV1().refreshEffectiveLanguage()
                        globalizationFallbackDiagnostic = try? PreferencesAdapterV1().readGlobalizationFallback()
                    }
                }

                NavigationLink(BundledLocalizationCatalogV1.v30Text(.shellBackUpCurrentData)) {
                    BackupExportView(
                        modelContext: modelContext,
                        generationRootURL: generationRootURL
                    )
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .accessibilityIdentifier(
                    BackupExportView.settingsEntryAccessibilityIdentifier
                )

                Button(BundledLocalizationCatalogV1.v30Text(.shellRestoreDataBackup), action: restoreDataBackup)
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityIdentifier(
                        BackupRestoreProgressView.settingsEntryAccessibilityIdentifier
                    )

                Button(BundledLocalizationCatalogV1.v30Text(.shellViewSubscription)) {
                    paywallPresentation = PaywallPresentation()
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityHint(
                    BundledLocalizationCatalogV1.v30Text(.shellViewSubscriptionHint)
                )
                .accessibilityIdentifier(
                    PaywallView.settingsEntryAccessibilityIdentifier
                )

                Button(BundledLocalizationCatalogV1.v30Text(.shellRestorePurchases)) {
                    lifecyclePresentation = LifecyclePresentation()
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityHint(
                    BundledLocalizationCatalogV1.v30Text(.shellRestorePurchasesHint)
                )
                .accessibilityIdentifier(
                    SubscriptionStatusView.settingsRestoreAccessibilityIdentifier
                )

                NavigationLink(BundledLocalizationCatalogV1.v30Text(.shellViewDiagnostics)) {
                    DiagnosticExportView(
                        diagnosticsStore: diagnosticsStore,
                        metricKitAdapter: metricKitDiagnosticsAdapter
                    )
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityHint(
                    BundledLocalizationCatalogV1.v30Text(.shellViewDiagnosticsHint)
                )
                .accessibilityIdentifier(
                    DiagnosticExportView.settingsEntryAccessibilityIdentifier
                )

                NavigationLink(BundledLocalizationCatalogV1.v30Text(.shellSendFeedback)) {
                    FeedbackView(
                        diagnosticsStore: diagnosticsStore,
                        metricKitAdapter: metricKitDiagnosticsAdapter,
                        configuration: feedbackConfiguration,
                        mailComposer: mailComposerAdapter
                    )
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityHint(
                    BundledLocalizationCatalogV1.v30Text(.shellSendFeedbackHint)
                )
                .accessibilityIdentifier(
                    FeedbackView.settingsEntryAccessibilityIdentifier
                )

                Text(BundledLocalizationCatalogV1.v30Text(.shellSubscriptionDataNotice))
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Button(BundledLocalizationCatalogV1.v30Text(.shellEraseAll), action: eraseAllAction.call)
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .accessibilityIdentifier(
                        EraseAllView.settingsEntryAccessibilityIdentifier
                    )
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.shellSettingsNavigationTitle))
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(AppShellView.settingsScreenAccessibilityIdentifier)
        .sheet(item: $paywallPresentation) { presentation in
            PaywallView(
                coordinator: purchaseCoordinator,
                presentationToken: presentation.id,
                close: { paywallPresentation = nil }
            )
        }
        .sheet(item: $lifecyclePresentation) { _ in
            NavigationStack {
                SubscriptionStatusView(
                    coordinator: lifecycleCoordinator,
                    startsRestoreOnAppear: true,
                    close: { lifecyclePresentation = nil }
                )
            }
        }
    }
}

private struct PackUnavailableView: View {
    var body: some View {
        ScrollView {
            WorklightCard {
                Text(BundledLocalizationCatalogV1.v30Text(.shellContentUnavailableHeading))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.blockedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(BundledLocalizationCatalogV1.v30Text(.shellBundledContentUnavailable))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(BundledLocalizationCatalogV1.v30Text(.shellNoPartialContentNotice))
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
    }
}

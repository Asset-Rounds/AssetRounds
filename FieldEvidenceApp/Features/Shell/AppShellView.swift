import Foundation
import SwiftData
import SwiftUI

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
    let generationRootURL: URL
    let usesImportedCaptureFixturesForUITest: Bool

    @State private var selectedTab: Tab = .signs

    init(
        packLoadResult: SignPackLoadResult,
        exposesColorSchemeForUITest: Bool = false,
        modelContext: ModelContext,
        diagnosticsStore: DiagnosticsStore,
        generationRootURL: URL,
        usesImportedCaptureFixturesForUITest: Bool = false
    ) {
        self.packLoadResult = packLoadResult
        self.exposesColorSchemeForUITest = exposesColorSchemeForUITest
        self.modelContext = modelContext
        self.diagnosticsStore = diagnosticsStore
        self.generationRootURL = generationRootURL
        self.usesImportedCaptureFixturesForUITest = usesImportedCaptureFixturesForUITest
    }

    var body: some View {
        switch packLoadResult {
        case let .available(pack):
            availableShell(pack: pack)
        case .unavailable:
            PackUnavailableView()
                .accessibilityIdentifier(Self.unavailableAccessibilityIdentifier)
        }
    }

    private func availableShell(pack: SignPack) -> some View {
        TabView(selection: $selectedTab) {
            SignsRootView(
                modelContext: modelContext,
                diagnosticsStore: diagnosticsStore,
                pack: pack,
                generationRootURL: generationRootURL,
                usesImportedCaptureFixturesForUITest: usesImportedCaptureFixturesForUITest
            )
            .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
            .accessibilityValue(
                exposesColorSchemeForUITest
                    ? (colorScheme == .dark ? "Dark" : "Light")
                    : ""
            )
            .tag(Tab.signs)
            .tabItem {
                Label("Signs", systemImage: "signpost.right.fill")
                    .accessibilityIdentifier(Self.signsTabAccessibilityIdentifier)
            }

            NavigationStack {
                ReportsPlaceholderView()
                    .navigationTitle("Reports")
                    .toolbar {
                        settingsToolbar
                    }
            }
            .tag(Tab.reports)
            .tabItem {
                Label("Reports", systemImage: "doc.text.fill")
                    .accessibilityIdentifier(Self.reportsTabAccessibilityIdentifier)
            }
        }
        .tint(DesignTokens.Colors.interactionAccent)
        .background(DesignTokens.Colors.canvas)
    }

    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                SettingsPlaceholderView()
            } label: {
                Image(systemName: "gearshape")
            }
            .frame(
                minWidth: DesignTokens.Control.minimumHitSize,
                minHeight: DesignTokens.Control.minimumHitSize
            )
            .contentShape(Rectangle())
            .accessibilityLabel("Settings")
            .accessibilityIdentifier(Self.settingsButtonAccessibilityIdentifier)
        }
    }
}

private struct ReportsPlaceholderView: View {
    var body: some View {
        ScrollView {
            WorklightCard {
                WorklightStatusBadge(kind: .information, text: "Reports")

                Text("Saved reports will appear here.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier(AppShellView.reportsPlaceholderAccessibilityIdentifier)
            .padding(DesignTokens.Spacing.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
    }
}

struct SettingsPlaceholderView: View {
    var body: some View {
        ScrollView {
            WorklightCard {
                Text("Settings")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text("Settings are not available in this sample.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(AppShellView.settingsScreenAccessibilityIdentifier)
    }
}

private struct PackUnavailableView: View {
    var body: some View {
        ScrollView {
            WorklightCard {
                Text("Content unavailable")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.blockedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("The bundled sign content could not be loaded.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("No partial or guessed content is shown.")
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

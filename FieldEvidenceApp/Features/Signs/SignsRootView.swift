import Foundation
import SwiftData
import SwiftUI

struct SignsRootView: View {
    static let welcomeScreenAccessibilityIdentifier = "s2.welcome.screen"
    static let welcomeTitleAccessibilityIdentifier = "s2.welcome.title"
    static let addFirstSignAccessibilityIdentifier = "s2.welcome.add-first-sign"
    static let viewSampleAccessibilityIdentifier = "s2.welcome.view-sample"
    static let restoreDataAccessibilityIdentifier = "s2.welcome.restore-data-backup"
    static let restorePurchasesAccessibilityIdentifier = "s2.welcome.restore-purchases"
    static let sampleScreenAccessibilityIdentifier = "s2.sample.screen"
    static let sampleBackAccessibilityIdentifier = "s2.sample.back"

    private enum Route: Hashable {
        case sample
        case newSign
        case check
    }

    let pack: SignPack
    let generationRootURL: URL
    let usesImportedCaptureFixturesForUITest: Bool

    @StateObject private var coordinator: FirstSignCoordinator
    private let checkRunnerCoordinator: CheckRunnerCoordinator
    @State private var snapshot: FirstSignSnapshot?
    @State private var path = NavigationPath()
    @State private var didLoad = false
    @State private var loadErrorMessage: String?
    @State private var checkNotice: String?

    init(
        modelContext: ModelContext,
        diagnosticsStore: DiagnosticsStore,
        pack: SignPack,
        generationRootURL: URL,
        usesImportedCaptureFixturesForUITest: Bool = false
    ) {
        self.pack = pack
        self.generationRootURL = generationRootURL
        self.usesImportedCaptureFixturesForUITest = usesImportedCaptureFixturesForUITest
        _coordinator = StateObject(
            wrappedValue: FirstSignCoordinator(
                modelContext: modelContext,
                diagnosticsStore: diagnosticsStore,
                signPack: pack
            )
        )
        checkRunnerCoordinator = CheckRunnerCoordinator(
            modelContext: modelContext,
            signPack: pack
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let snapshot {
                    SignDetailView(
                        snapshot: snapshot,
                        checkNotice: checkNotice
                    ) {
                        checkNotice = nil
                        path.append(Route.check)
                    }
                } else if let loadErrorMessage {
                    loadFailure(message: loadErrorMessage)
                } else {
                    welcome
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .sample:
                    sample
                case .newSign:
                    NewSignView(coordinator: coordinator) { savedSnapshot in
                        snapshot = savedSnapshot
                        path = NavigationPath()
                    }
                case .check:
                    if let snapshot {
                        PreflightView(
                            snapshot: snapshot,
                            pack: pack,
                            coordinator: checkRunnerCoordinator,
                            generationRootURL: generationRootURL,
                            usesImportedCaptureFixturesForUITest:
                                usesImportedCaptureFixturesForUITest
                        ) {
                            checkNotice = "No check was started."
                            path.removeLast()
                        }
                    }
                }
            }
            .toolbar {
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
                    .accessibilityIdentifier(AppShellView.settingsButtonAccessibilityIdentifier)
                }
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true

            do {
                let loadedSnapshot = try coordinator.load()
                snapshot = loadedSnapshot

                if let loadedSnapshot,
                   try checkRunnerCoordinator.existingDraft(assetID: loadedSnapshot.assetID) != nil {
                    path.append(Route.check)
                }
            } catch {
                loadErrorMessage = "Saved sign data could not be opened."
            }
        }
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                WorklightCard {
                    WorklightStatusBadge(kind: .information, text: "Field Evidence")

                    Text("Turn tonight's sign check into a clear report.")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(Self.welcomeTitleAccessibilityIdentifier)
                        .accessibilityAddTraits(.isHeader)

                    Text("Add the first sign you inspect, or look through the bundled sample before you begin.")
                        .font(.body)
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Add first sign") {
                    path.append(Route.newSign)
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .accessibilityIdentifier(Self.addFirstSignAccessibilityIdentifier)

                Button("View sample") {
                    path.append(Route.sample)
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityIdentifier(Self.viewSampleAccessibilityIdentifier)

                WorklightCard {
                    Button("Restore data backup") {}
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .disabled(true)
                        .accessibilityHint("Unavailable in this version")
                        .accessibilityIdentifier(Self.restoreDataAccessibilityIdentifier)

                    Button("Restore Purchases") {}
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .disabled(true)
                        .accessibilityHint("Unavailable in this version")
                        .accessibilityIdentifier(Self.restorePurchasesAccessibilityIdentifier)
                }
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle("Signs")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.welcomeScreenAccessibilityIdentifier)
    }

    private var sample: some View {
        PackSampleView(pack: pack)
            .navigationTitle("Sample")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        path.removeLast()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .frame(
                        minWidth: DesignTokens.Control.minimumHitSize,
                        minHeight: DesignTokens.Control.minimumHitSize
                    )
                    .accessibilityIdentifier(Self.sampleBackAccessibilityIdentifier)
                }
            }
            .accessibilityIdentifier(Self.sampleScreenAccessibilityIdentifier)
    }

    private func loadFailure(message: String) -> some View {
        ScrollView {
            WorklightCard {
                WorklightStatusBadge(kind: .blocked, text: "Saved data unavailable")

                Text(message)
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
    }
}

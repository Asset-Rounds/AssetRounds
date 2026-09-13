import SwiftUI

/// A current-source landing surface. Destination actions are supplied only
/// after their exact canonical target and incumbent view can be composed.
@MainActor
struct ProductionWorkRootViewV1: View {
    static let screenAccessibilityIdentifier = "v23.shell.work.screen"
    @ObservedObject var source: ProductionMyDaySourceStateV1

    var body: some View {
        List {
            if let snapshot = source.snapshot {
                if snapshot.sources.isEmpty {
                    AssetRoundsEmptyState(title: Text("No current work"),
                        message: Text("Work packets, rounds, scheduled work and saved drafts will appear here."))
                } else {
                    ForEach(snapshot.sources, id: \.reference) { item in
                        AssetRoundsEvidenceCard {
                            ProductionWorkSourceRowV1(source: item,
                                readiness: snapshot.readinessAssessments.first {
                                    $0.reference == item.reference
                                })
                        }
                    }
                }
            } else if source.couldNotLoad {
                AssetRoundsEmptyState(title: Text("Work unavailable"),
                    message: Text("Your current work could not be opened. Try again."))
            } else {
                ProgressView("Opening work")
            }
            Section {
                Button(source.couldNotLoad ? "Try again" : "Refresh work") {
                    Task { await source.refresh() }
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(source.isLoading)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DesignTokens.SemanticColors.workBackground)
        .navigationTitle("Work")
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .task { await source.refresh() }
    }
}

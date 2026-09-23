import SwiftUI

/// A current-source landing surface. Destination actions are supplied only
/// after their exact canonical target and incumbent view can be composed.
@MainActor
struct ProductionWorkRootViewV1: View {
    static let screenAccessibilityIdentifier = "v23.shell.work.screen"
    @ObservedObject var source: ProductionMyDaySourceStateV1
    var openRound: ((MyDayEligibleReferenceV1) -> Void)? = nil
    var reviewAccess: AppAccessPresentationV1.RoundAccess? = nil
    var openSavedReview: ((MyDayEligibleReferenceV1) -> Void)? = nil

    var body: some View {
        List {
            if let snapshot = source.snapshot {
                if snapshot.sources.isEmpty {
                    AssetRoundsEmptyState(title: Text("No current work"),
                        message: Text("Work packets, rounds, scheduled work and saved drafts will appear here."))
                } else {
                    ForEach(snapshot.sources, id: \.reference) { item in
                        let readiness = snapshot.readinessAssessments.first {
                            $0.reference == item.reference
                        }
                        if case let .roundSession(_, sessionID, _, _) = item.reference, let openRound {
                            Button { openRound(item.reference) } label: {
                                sourceRow(item, readiness: readiness)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("v23.work.round." + sessionID.uuidString.lowercased())
                        } else if case .resumableDraft = item.reference,
                                  let reviewAccess, let openSavedReview {
                            ProductionSavedReviewRowV1(source: item, readiness: readiness,
                                access: reviewAccess, open: openSavedReview)
                        } else {
                            sourceRow(item, readiness: readiness)
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
        #if DEBUG
        .background {
            if source.snapshot != nil {
                NativeScreenObservationAnchorV1(identifier: Self.screenAccessibilityIdentifier)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
        }
        #endif
        .navigationTitle("Work")
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .task { await source.refresh() }
    }

    private func sourceRow(_ item: MyDayLiveSourceV1,
                           readiness: MyDaySourceReadinessAssessmentV1?) -> some View {
        AssetRoundsEvidenceCard {
            ProductionWorkSourceRowV1(source: item, readiness: readiness)
        }
    }
}

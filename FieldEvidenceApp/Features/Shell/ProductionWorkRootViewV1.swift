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
    /// SIG-1 Completed work section. Opening a row is a local Work-stack push
    /// owned by this presentation, never a saved navigation route.
    var completedWork: CompletedWorkPresentationV1? = nil

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
            if let completedWork {
                CompletedWorkSectionV1(presentation: completedWork)
            }
            Section {
                Button(source.couldNotLoad ? "Try again" : "Refresh work") {
                    Task { await source.refresh() }
                    completedWork?.refresh()
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
        // The Completed work listing loads once per Work-root appearance and
        // is served from the service's revision-keyed cache when unchanged.
        .task { completedWork?.refresh() }
    }

    private func sourceRow(_ item: MyDayLiveSourceV1,
                           readiness: MyDaySourceReadinessAssessmentV1?) -> some View {
        AssetRoundsEvidenceCard {
            ProductionWorkSourceRowV1(source: item, readiness: readiness)
        }
    }
}

/// SIG-1 "Completed work" section: current-tip completed work, newest first,
/// capped by the resolver, each with its bound response count.
@MainActor
struct CompletedWorkSectionV1: View {
    @ObservedObject var presentation: CompletedWorkPresentationV1

    var body: some View {
        Section {
            rows
        } header: {
            header
        }
    }

    private var header: some View {
        Text("Completed work")
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(SignoffEnrollmentView.workRootAccessibilityIdentifier)
            #if DEBUG
            .background {
                NativeScreenObservationAnchorV1(
                    identifier: SignoffEnrollmentView.workRootAccessibilityIdentifier
                )
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
            #endif
    }

    @ViewBuilder
    private var rows: some View {
        switch presentation.list {
        case .loading:
            ProgressView("Opening completed work")
        case .unavailable:
            Text("Completed work could not be opened. Try again.")
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
        case let .loaded(items):
            if items.isEmpty {
                Text("Completed reports will appear here.")
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
            } else {
                ForEach(items) { item in
                    row(item)
                }
            }
        }
    }

    private func row(_ item: CompletedWorkSubjectListingV1) -> some View {
        Button {
            presentation.open(item)
        } label: {
            CompletedWorkRowV1(item: item)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            "v23.work.completed." + item.key.subjectID.uuidString.lowercased()
        )
    }
}

@MainActor
private struct CompletedWorkRowV1: View {
    let item: CompletedWorkSubjectListingV1

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            if let display = item.display {
                Text(display.assetLabel)
                    .font(.headline)
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                Text(display.siteLabel)
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                Text(verbatim: "\(display.stage) · \(display.outcome)")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                Text(verbatim: "\(display.whenText) · \(display.versionText)")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
            } else {
                Text("Completed work unavailable")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
            }
            Text(CompletedWorkDetailViewV1.responseCountText(item.responseCount))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

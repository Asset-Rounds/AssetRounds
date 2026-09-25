import SwiftUI

typealias CompletedWorkHistoryLoaderV1 = @MainActor (UUID) throws -> CompletedWorkResponseHistoryV1

enum SignoffResponseHistoryLoadStateV1: Equatable {
    case loading
    case loaded(CompletedWorkResponseHistoryV1)
    case unavailable
}

/// Read-only Reports destination for C43 approval responses. It shows stored
/// response facts only and never offers a Record action, so a deep link can
/// never create an effect here.
@MainActor
struct SignoffResponseHistoryViewV1: View {
    static let entryAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.history.entry"
    static let unsupportedAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.history.unsupported"
    static let unavailableSubjectAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.history.subject-unavailable"
    static let notVerifiedText = "Not verified by AssetRounds"

    private let signoffID: UUID
    private let load: CompletedWorkHistoryLoaderV1
    @State private var state: SignoffResponseHistoryLoadStateV1 = .loading

    init(signoffID: UUID, load: @escaping CompletedWorkHistoryLoaderV1) {
        self.signoffID = signoffID
        self.load = load
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space16) {
                content
            }
            .padding(DesignTokens.Spacing.space16)
            #if DEBUG
            .background {
                NativeScreenObservationAnchorV1(
                    identifier: SignoffEnrollmentView.historyAccessibilityIdentifier
                )
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
            #endif
        }
        .navigationTitle("Responses")
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.SemanticColors.workBackground)
        .accessibilityIdentifier(SignoffEnrollmentView.historyAccessibilityIdentifier)
        .task(id: signoffID) {
            reload()
        }
    }

    private func reload() {
        do {
            state = .loaded(try load(signoffID))
        } catch {
            state = .unavailable
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView("Opening responses")
                .frame(maxWidth: .infinity, minHeight: DesignTokens.Target.minimumInteractiveHeight)
        case .unavailable:
            AssetRoundsEvidenceCard {
                Text("Responses unavailable")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text("This response history could not be opened.")
                    .font(.body)
                    .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case let .loaded(history):
            subjectHeader(history)
            group(title: "Current version", entries: history.current)
            group(title: "Earlier versions", entries: history.earlier)
        }
    }

    @ViewBuilder
    private func subjectHeader(_ history: CompletedWorkResponseHistoryV1) -> some View {
        if let subject = history.subject {
            AssetRoundsEvidenceCard {
                Text(subject.assetLabel)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                fact(label: "Site", value: subject.siteLabel)
                fact(label: "Stage", value: subject.stage)
                fact(label: "Outcome", value: subject.outcome)
                fact(label: "Completed", value: subject.whenText)
                fact(label: "Version", value: subject.versionText)
            }
            .accessibilityElement(children: .contain)
        } else if let reason = history.unavailableReason {
            AssetRoundsEvidenceCard {
                Text("Completed work unavailable")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(reason.displayText)
                    .font(.body)
                    .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(Self.unavailableSubjectAccessibilityIdentifier)
        }
    }

    @ViewBuilder
    private func group(
        title: String,
        entries: [CompletedWorkResponseHistoryEntryV1]
    ) -> some View {
        if !entries.isEmpty {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                .accessibilityAddTraits(.isHeader)
            ForEach(entries) { entry in
                entryCard(entry)
            }
        }
    }

    @ViewBuilder
    private func entryCard(_ entry: CompletedWorkResponseHistoryEntryV1) -> some View {
        if let facts = entry.facts {
            responseCard(facts, version: entry.version)
                .accessibilityIdentifier(Self.entryAccessibilityIdentifier)
        } else {
            AssetRoundsEvidenceCard {
                Text("Unsupported response record")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("This record cannot be shown as a completed-work response.")
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(Self.unsupportedAccessibilityIdentifier)
        }
    }

    private func responseCard(
        _ facts: CompletedWorkResponseFactsV1,
        version: UInt64?
    ) -> some View {
        AssetRoundsEvidenceCard {
            Text("Response recorded")
                .font(.body.weight(.semibold))
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
            fact(label: "Typed name", value: facts.typedName)
            fact(label: "Claimed role", value: facts.claimedRole)
            if let relationship = facts.relationshipText {
                fact(label: "Claimed relationship", value: relationship)
            }
            fact(label: "Method", value: facts.methodText)
            fact(label: "Occurred", value: Self.dateText(facts.occurredAt))
            fact(label: "Recorded", value: Self.dateText(facts.recordedAt))
            if let version {
                fact(label: "Bound to", value: "Version \(version)")
            }
            disclosure(facts.disclosureText)
        }
        .accessibilityElement(children: .contain)
    }

    private func disclosure(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space8) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(Self.notVerifiedText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
        }
    }

    private func fact(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
            Text(value)
                .font(.body)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private static func dateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

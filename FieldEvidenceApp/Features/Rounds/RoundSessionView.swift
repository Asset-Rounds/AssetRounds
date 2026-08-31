import SwiftUI

/// Isolated presentation contracts for the C07 RoundSession surface. All
/// mutations remain with the canonical caller; callbacks run only after that
/// caller has accepted a durable effect or has reported a failure.
struct RoundSessionViewActionsV1 {
    let openItem: (UUID) -> Void
    let requestReorder: (UUID, Int) -> Void
    let jumpToNextIncomplete: () -> Void
    let jumpToNextFlagged: () -> Void
    let requestBatchHandoff: () -> Void
    let requestRecovery: () -> Void
    /// Must durably persist and read back the exact anchor before returning it.
    let preserveFieldPosition: (FieldPositionAnchorV1) async throws -> FieldPositionAnchorV1
    let flushBeforeLeaving: () async throws -> Void
    let leaveAfterFlush: () -> Void
}

/// Presentation input from the owning field-flow authority. `notRequired`
/// deliberately means a nil anchor is ordinary and must not block Back.
enum RoundSessionFieldPositionRequirementV1: Equatable, Sendable {
    case notRequired
    case requiredForCurrentFieldFlow
}

struct RoundSessionView: View {
    static let screenAccessibilityIdentifier = RoundSessionAccessibilityIDV1.screen.rawValue

    let session: RoundSessionV1
    let readiness: OfflineReadinessManifestV1?
    let fieldSectionIndex: FieldSectionIndexProjectionV1?
    let fieldPositionAnchor: FieldPositionAnchorV1?
    let fieldPositionRequirement: RoundSessionFieldPositionRequirementV1
    let batchHandoffStatus: RoundSessionBatchHandoffStatusV1
    let actions: RoundSessionViewActionsV1

    @State private var navigationFailure: String?
    @State private var flushing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                progress
                readinessStatus
                itemList
                navigationControls
                handoffAndRecovery
                backControl
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(text(.heading))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text(.heading)).font(.title2.weight(.semibold))
            Text(text(.manualPathDisclosure))
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text(.progressHeading)).font(.headline)
            HStack {
                count(text(.completedCount), session.counts.completed)
                count(text(.incompleteCount), session.counts.undispositioned)
                count(text(.flaggedCount), session.counts.inaccessible + session.counts.deferred)
            }
            Text(session.state == .completed ? text(.closeoutComplete) : text(.closeoutIncomplete))
                .font(.body.weight(.medium))
                .accessibilityIdentifier(RoundSessionAccessibilityIDV1.closeout.rawValue)
        }
        .accessibilityIdentifier(RoundSessionAccessibilityIDV1.progress.rawValue)
    }

    @ViewBuilder
    private var readinessStatus: some View {
        if let readiness {
            Label(readinessLabel(readiness), systemImage: readinessSymbol(readiness))
                .foregroundStyle(.primary)
                .accessibilityIdentifier(RoundSessionAccessibilityIDV1.readiness.rawValue)
            if !readiness.mayStartFieldWork {
                Text(text(.readinessBlockedDisclosure))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } else {
            Label(text(.readinessUnavailable), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.primary)
                .accessibilityIdentifier(RoundSessionAccessibilityIDV1.readiness.rawValue)
        }
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text(.itemsHeading)).font(.headline)
            ForEach(session.items, id: \.itemID) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Button { actions.openItem(item.itemID) } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: itemSymbol(item)).accessibilityHidden(true)
                            VStack(alignment: .leading) {
                                Text(item.selection.labelAtSelection).font(.body.weight(.medium))
                                Text(itemDetail(item)).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(item.order + 1)").font(.caption.monospacedDigit())
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(RoundSessionAccessibilityIDV1.item.rawValue + "." + item.itemID.uuidString.lowercased())

                    let field = projectedField(for: item)
                    let permitsOutOfOrder = field?.packagePermitsOutOfOrderNavigation == true
                    HStack {
                        Button(text(.moveEarlier)) { actions.requestReorder(item.itemID, -1) }
                            .disabled(item.order == 0 || !permitsOutOfOrder)
                        Button(text(.moveLater)) { actions.requestReorder(item.itemID, 1) }
                            .disabled(item.order + 1 == session.items.count || !permitsOutOfOrder)
                        Spacer()
                        Text(permitsOutOfOrder ? text(.outOfOrderPermitted) : text(field == nil ? .projectionUnavailable : .orderedOnly))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .accessibilityIdentifier(RoundSessionAccessibilityIDV1.items.rawValue)
    }

    private var navigationControls: some View {
        HStack {
            Button(text(.jumpIncomplete), action: actions.jumpToNextIncomplete)
                .buttonStyle(.bordered)
                .accessibilityIdentifier(RoundSessionAccessibilityIDV1.jumpIncomplete.rawValue)
            Button(text(.jumpFlagged), action: actions.jumpToNextFlagged)
                .buttonStyle(.bordered)
                .accessibilityIdentifier(RoundSessionAccessibilityIDV1.jumpFlagged.rawValue)
        }
    }

    private var handoffAndRecovery: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(batchHandoffStatus.localizedDescription).font(.body.weight(.medium))
            Button(text(.batchHandoff), action: actions.requestBatchHandoff)
                .buttonStyle(.bordered)
                .accessibilityIdentifier(RoundSessionAccessibilityIDV1.handoff.rawValue)
            Button(text(.recovery), action: actions.requestRecovery)
                .buttonStyle(.bordered)
                .accessibilityIdentifier(RoundSessionAccessibilityIDV1.recovery.rawValue)
            if fieldPositionAnchor != nil {
                Text(text(.positionPreserved))
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier(RoundSessionAccessibilityIDV1.position.rawValue)
            }
        }
    }

    private var backControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let navigationFailure {
                Label(navigationFailure, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier(RoundSessionAccessibilityIDV1.saveFailure.rawValue)
            }
            Button(flushing ? text(.saving) : text(.back)) { flushAndLeave() }
                .buttonStyle(.borderedProminent)
                .disabled(flushing)
                .accessibilityIdentifier(RoundSessionAccessibilityIDV1.back.rawValue)
        }
    }

    private func flushAndLeave() {
        guard !flushing else { return }
        flushing = true; navigationFailure = nil
        Task { @MainActor in
            do {
                try await actions.flushBeforeLeaving()
                if let fieldPositionAnchor {
                    let readBack = try await actions.preserveFieldPosition(fieldPositionAnchor)
                    guard readBack == fieldPositionAnchor else { throw RoundSessionViewFailureV1.anchorReadbackMismatch }
                } else if fieldPositionRequirement == .requiredForCurrentFieldFlow {
                    throw RoundSessionViewFailureV1.anchorUnavailable
                }
                actions.leaveAfterFlush()
            }
            catch { navigationFailure = text(.saveFailure); flushing = false }
        }
    }

    private func count(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading) { Text("\(value)").font(.title3.monospacedDigit()); Text(label).font(.caption) }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func projectedField(for item: RoundItemV1) -> FieldSectionIndexFieldV1? {
        guard let fieldSectionIndex,
              (try? fieldSectionIndex.validate(session: session)) != nil,
              let reference = try? session.reference,
              fieldSectionIndex.session == reference else { return nil }
        return fieldSectionIndex.sections.flatMap(\.fields).first(where: {
            $0.itemID == item.itemID
                && $0.assetID == item.selection.assetID
                && $0.siteID == item.selection.siteID
                && $0.order == item.order
                && $0.requirementSHA256 == item.requirement.requirementSHA256
                && $0.disposition == item.disposition
        })
    }

    private func itemSymbol(_ item: RoundItemV1) -> String {
        switch item.disposition { case .completed: return "checkmark.circle.fill"; case .inaccessible, .deferred: return "exclamationmark.triangle.fill"; case .skipped: return "minus.circle"; case .pending, .visited: return "circle" }
    }

    private func itemDetail(_ item: RoundItemV1) -> String {
        guard let reason = item.reason else { return item.disposition == .completed ? text(.completed) : text(.incomplete) }
        return reasonText(reason)
    }

    private func readinessLabel(_ manifest: OfflineReadinessManifestV1) -> String {
        switch manifest.status { case .ready: return text(.readinessReady); case .warning: return text(.readinessWarning); case .blocked: return text(.readinessBlocked); case .stale: return text(.readinessStale) }
    }
    private func readinessSymbol(_ manifest: OfflineReadinessManifestV1) -> String {
        switch manifest.status { case .ready: return "checkmark.seal.fill"; case .warning: return "exclamationmark.triangle.fill"; case .blocked: return "xmark.octagon.fill"; case .stale: return "arrow.triangle.2.circlepath" }
    }
    private func reasonText(_ reason: RoundItemReasonV1) -> String { RoundSessionLocalizationPolicyV1.reason(reason) }
    private func text(_ key: RoundSessionLocalizationKeyV1) -> String { BundledLocalizationCatalogV1.roundSessionLocalized(key) }
}

private enum RoundSessionViewFailureV1: Error { case anchorUnavailable, anchorReadbackMismatch }

enum RoundSessionBatchHandoffStatusV1: String, Sendable {
    case unavailable, pending, ready, completed

    var localizedDescription: String {
        let key: RoundSessionLocalizationKeyV1
        switch self {
        case .unavailable: key = .handoffUnavailable
        case .pending: key = .handoffPending
        case .ready: key = .handoffReady
        case .completed: key = .handoffCompleted
        }
        return BundledLocalizationCatalogV1.roundSessionLocalized(key)
    }
}

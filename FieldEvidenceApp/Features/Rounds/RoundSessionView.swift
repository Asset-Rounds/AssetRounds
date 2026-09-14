import SwiftUI

/// Isolated presentation contracts for the C07 RoundSession surface. All
/// mutations remain with the canonical caller; callbacks run only after that
/// caller has accepted a durable effect or has reported a failure.
struct RoundSessionViewActionsV1 {
    let openItem: ((UUID) -> Void)?
    let requestReorder: ((UUID, Int) -> Void)?
    let jumpToNextIncomplete: (() -> Void)?
    let jumpToNextFlagged: (() -> Void)?
    let requestBatchHandoff: (() -> Void)?
    let requestRecovery: (() -> Void)?
    /// Must durably persist and read back the exact anchor before returning it.
    let preserveFieldPosition: (FieldPositionAnchorV1) async throws -> FieldPositionAnchorV1
    let flushBeforeLeaving: () async throws -> Void
    let leaveAfterFlush: () -> Void
    var requestSessionTransition: ((RoundSessionTransitionV1) -> Void)? = nil
    var requestItemTransition: ((UUID, RoundSessionTransitionV1, RoundItemReasonV1?) -> Void)? = nil
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
                sessionControls
                progress
                readinessStatus
                itemList
                navigationControls
                handoffAndRecovery
                backControl
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            #if DEBUG
            .background {
                NativeScreenObservationAnchorV1(identifier: Self.screenAccessibilityIdentifier)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
            #endif
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

    @ViewBuilder
    private var sessionControls: some View {
        switch session.state {
        case .draft:
            Button("Start") { actions.requestSessionTransition?(.start) }
                .buttonStyle(.borderedProminent)
                .disabled(actions.requestSessionTransition == nil)
                .accessibilityIdentifier("production.round.transition.start")
        case .active:
            Button("Pause") { actions.requestSessionTransition?(.pause) }
                .buttonStyle(.bordered)
                .disabled(actions.requestSessionTransition == nil)
                .accessibilityIdentifier("production.round.transition.pause")
        case .paused:
            Button("Resume") { actions.requestSessionTransition?(.resume) }
                .buttonStyle(.borderedProminent)
                .disabled(actions.requestSessionTransition == nil)
                .accessibilityIdentifier("production.round.transition.resume")
        default:
            EmptyView()
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
                    Button { actions.openItem?(item.itemID) } label: {
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
                    .disabled(actions.openItem == nil)
                    .accessibilityIdentifier(RoundSessionAccessibilityIDV1.item.rawValue + "." + item.itemID.uuidString.lowercased())

                    itemProgressControls(item)

                    let field = projectedField(for: item)
                    let permitsOutOfOrder = field?.packagePermitsOutOfOrderNavigation == true
                    // Draft selection order is distinct from package permission
                    // to navigate active field work out of order.
                    let permitsSelectionOrder = session.state == .draft || permitsOutOfOrder
                    HStack {
                        Button(text(.moveEarlier)) { actions.requestReorder?(item.itemID, -1) }
                            .disabled(actions.requestReorder == nil || item.order == 0 || !permitsSelectionOrder)
                        Button(text(.moveLater)) { actions.requestReorder?(item.itemID, 1) }
                            .disabled(actions.requestReorder == nil || item.order + 1 == session.items.count || !permitsSelectionOrder)
                        Spacer()
                        if session.state != .draft {
                            Text(permitsOutOfOrder ? text(.outOfOrderPermitted) : text(field == nil ? .projectionUnavailable : .orderedOnly))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .accessibilityIdentifier(RoundSessionAccessibilityIDV1.items.rawValue)
    }

    @ViewBuilder
    private func itemProgressControls(_ item: RoundItemV1) -> some View {
        if session.state == .active, let request = actions.requestItemTransition {
            VStack(alignment: .leading, spacing: 8) {
                if item.disposition == .pending {
                    Button("Mark visited") { request(item.itemID, .visitItem, nil) }
                        .accessibilityIdentifier("production.round.item.visit." + item.itemID.uuidString.lowercased())
                }
                if [.pending, .visited].contains(item.disposition) {
                    Menu("Mark inaccessible") {
                        ForEach(RoundItemReasonV1.allCases.filter { $0.isAllowed(for: .inaccessible) }, id: \.self) { reason in
                            Button(reasonText(reason)) { request(item.itemID, .markInaccessible, reason) }
                        }
                    }
                    .accessibilityIdentifier("production.round.item.inaccessible." + item.itemID.uuidString.lowercased())
                    Menu("Skip") {
                        ForEach(RoundItemReasonV1.allCases.filter { $0.isAllowed(for: .skipped) }, id: \.self) { reason in
                            Button(reasonText(reason)) { request(item.itemID, .skipItem, reason) }
                        }
                    }
                    .accessibilityIdentifier("production.round.item.skip." + item.itemID.uuidString.lowercased())
                    Menu("Defer") {
                        ForEach(RoundItemReasonV1.allCases.filter { $0.isAllowed(for: .deferred) }, id: \.self) { reason in
                            Button(reasonText(reason)) { request(item.itemID, .deferItem, reason) }
                        }
                    }
                    .accessibilityIdentifier("production.round.item.defer." + item.itemID.uuidString.lowercased())
                }
                if [.inaccessible, .deferred].contains(item.disposition) {
                    Button("Retry item") { request(item.itemID, .retryItem, nil) }
                        .accessibilityIdentifier("production.round.item.retry." + item.itemID.uuidString.lowercased())
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var navigationControls: some View {
        HStack {
            Button(text(.jumpIncomplete)) { actions.jumpToNextIncomplete?() }
                .disabled(actions.jumpToNextIncomplete == nil)
                .buttonStyle(.bordered)
                .accessibilityIdentifier(RoundSessionAccessibilityIDV1.jumpIncomplete.rawValue)
            Button(text(.jumpFlagged)) { actions.jumpToNextFlagged?() }
                .disabled(actions.jumpToNextFlagged == nil)
                .buttonStyle(.bordered)
                .accessibilityIdentifier(RoundSessionAccessibilityIDV1.jumpFlagged.rawValue)
        }
    }

    private var handoffAndRecovery: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(batchHandoffStatus.localizedDescription).font(.body.weight(.medium))
            Button(text(.batchHandoff)) { actions.requestBatchHandoff?() }
                .disabled(actions.requestBatchHandoff == nil)
                .buttonStyle(.bordered)
                .accessibilityIdentifier(RoundSessionAccessibilityIDV1.handoff.rawValue)
            Button(text(.recovery)) { actions.requestRecovery?() }
                .disabled(actions.requestRecovery == nil)
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

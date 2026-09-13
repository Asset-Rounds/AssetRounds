import Combine
import Foundation
import SwiftUI

/// Presentation values from one original app publication. This owner has no
/// persistence objects and cannot authorize a later publication's callbacks.
@MainActor
final class ProductionMyDaySourceStateV1: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    private(set) var snapshot: MyDaySourceSnapshotV1?
    private(set) var isLoading = false
    private(set) var couldNotLoad = false

    private let workspaceID: WorkspaceID
    private let access: AppAccessPresentationV1.MyDayAccess
    private let clock: any ApplicationClock
    private var readID: UUID?
    private weak var activePlanningEditor: ProductionMyDayPlanningEditorStateV1?

    #if DEBUG
    /// Runs after the real access read; cannot replace source data or authority.
    var afterSnapshotReadyForTesting: (@MainActor () async throws -> Void)?
    #endif

    init(workspaceID: WorkspaceID, access: AppAccessPresentationV1.MyDayAccess,
         clock: any ApplicationClock = SystemApplicationClock()) {
        self.workspaceID = workspaceID
        self.access = access
        self.clock = clock
    }

    func refresh() async {
        objectWillChange.send()
        let operationID = UUID()
        readID = operationID
        snapshot = nil
        couldNotLoad = false
        isLoading = true
        do {
            let milliseconds = (clock.now().timeIntervalSince1970 * 1_000)
                .rounded(.toNearestOrAwayFromZero)
            let instant = Date(timeIntervalSince1970: milliseconds / 1_000)
            let value = try await access.snapshot(evaluatedAt: instant)
            #if DEBUG
            try await afterSnapshotReadyForTesting?()
            #endif
            guard readID == operationID else { return }
            try Task.checkCancellation()
            // Notify outside the nonrecursive content-read hold. Subscribers
            // may revoke/discard this publication; recheck after they return.
            objectWillChange.send()
            try Task.checkCancellation()
            guard readID == operationID else { return }
            guard value.workspaceID == workspaceID else {
                throw MyDayFailureV1.wrongWorkspace
            }
            try access.withCurrentPresentation {
                snapshot = value
                isLoading = false
            }
        } catch {
            guard readID == operationID else { return }
            objectWillChange.send()
            guard readID == operationID else { return }
            snapshot = nil
            isLoading = false
            couldNotLoad = true
        }
    }

    func makePlanningEditor() throws -> ProductionMyDayPlanningEditorStateV1 {
        try access.withCurrentPresentation {
            let editor = ProductionMyDayPlanningEditorStateV1(workspaceID: workspaceID,
                access: access, clock: clock)
            activePlanningEditor = editor
            return editor
        }
    }

    func discard() {
        objectWillChange.send()
        readID = nil
        activePlanningEditor?.discardPresentation()
        activePlanningEditor = nil
        snapshot = nil
        isLoading = false
        couldNotLoad = false
    }
}

@MainActor
struct ProductionMyDayRootViewV1: View {
    static let screenAccessibilityIdentifier = "v23.shell.today.screen"
    @ObservedObject var source: ProductionMyDaySourceStateV1
    @State private var planningEditor: ProductionMyDayPlanningEditorStateV1?
    @State private var planningCouldNotOpen = false

    var body: some View {
        Group {
            if let snapshot = source.snapshot {
                MyDayWorkflowView(sourceSnapshot: snapshot, onRefresh: refresh)
            } else if source.couldNotLoad {
                AssetRoundsScreenFoundation {
                    VStack(spacing: DesignTokens.Spacing.space16) {
                        AssetRoundsEmptyState(title: Text("My Day unavailable"),
                            message: Text("Your current work could not be opened. Try again."))
                        AssetRoundsSecondaryAction(action: refresh) { Text("Try again") }
                    }
                    .padding(DesignTokens.Spacing.space16)
                }
            } else {
                AssetRoundsScreenFoundation {
                    ProgressView("Opening My Day")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("Today")
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .task { await source.refresh() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Plan") {
                    do { planningEditor = try source.makePlanningEditor() }
                    catch { planningCouldNotOpen = true }
                }
                .accessibilityIdentifier("v23.my-day.open-planning")
            }
        }
        .sheet(item: $planningEditor, onDismiss: refresh) { editor in
            ProductionMyDayPlanningEditorV1(state: editor)
        }
        .alert("Planning unavailable", isPresented: $planningCouldNotOpen) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your current work could not be opened. Try again.")
        }
    }

    private func refresh() { Task { await source.refresh() } }
}

@MainActor
struct ProductionWorkSourceRowV1: View {
    let source: MyDayLiveSourceV1
    let readiness: MyDaySourceReadinessAssessmentV1?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space8) {
            Text(Self.title(for: source.reference))
                .font(DesignTokens.Typography.sectionHeading)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
            Text("\(Self.shortIdentity(for: source.reference)) · Version \(source.reference.sourceRevision)")
                .font(.footnote)
                .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
            Text(Self.stateLabel(source.state))
                .font(DesignTokens.Typography.primaryBody)
            if let dueAt = source.dueAt {
                LabeledContent("Due") {
                    Text(dueAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                }
            }
            Text(readinessLabel)
                .font(.footnote)
                .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var readinessLabel: String {
        guard let readiness else { return "Readiness not checked" }
        switch readiness.assessment {
        case .notAssessed: return "Readiness not checked"
        case .unavailable: return "Readiness unavailable"
        case .roundManifest(let manifest):
            switch manifest.status {
            case .ready: return "Ready for offline work"
            case .blocked: return "Offline readiness blocked"
            case .warning: return "Offline readiness needs attention"
            case .stale: return "Offline readiness needs a fresh check"
            }
        }
    }

    static func title(for reference: MyDayEligibleReferenceV1) -> String {
        switch reference {
        case .workPacket: return "Work packet"
        case .roundSession: return "Round session"
        case .scheduleOccurrence: return "Scheduled work"
        case .resumableDraft: return "Saved draft"
        }
    }

    static func shortIdentity(for reference: MyDayEligibleReferenceV1) -> String {
        let value: String
        switch reference {
        case .workPacket(let packet): value = packet.packetID.uuidString
        case .roundSession(_, let id, _, _), .resumableDraft(_, let id, _, _, _):
            value = id.uuidString
        case .scheduleOccurrence(let anchor, _): value = anchor.occurrenceID.rawValue
        }
        return String(value.prefix(8)).uppercased()
    }

    private static func stateLabel(_ state: MyDaySourceStateV1) -> String {
        switch state {
        case .ruleRetired: return "Retired by a schedule change"
        case .recoveryRequired: return "Recovery required"
        case .discardPending: return "Discard pending"
        default: return state.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

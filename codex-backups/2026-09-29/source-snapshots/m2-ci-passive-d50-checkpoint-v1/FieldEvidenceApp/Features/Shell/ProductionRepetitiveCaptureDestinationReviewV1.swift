import Foundation
import SwiftUI

struct ProductionSavedReviewProvenanceV1: Equatable {
    let sourceWorkspaceID: WorkspaceID
    let sourceDraftID: UUID
    let sourceRoundID: UUID
    let recordedAt: Date
    let recordedBy: String
    let assetLabels: [String]
    let restoreMode: RepetitiveCaptureReviewModeV1
}

/// The row reference is a hint. Every presentation and command re-enters the
/// original content publication and the caller's still-current Work scene.
@MainActor
final class ProductionRepetitiveCaptureReviewPresentationV1: ObservableObject {
    @Published private(set) var checkpoint: FieldDraftCheckpointV1?
    @Published private(set) var provenance: ProductionSavedReviewProvenanceV1?
    @Published private(set) var isDiscarded = false
    @Published private(set) var couldNotLoad = false
    @Published private(set) var couldNotDiscard = false
    @Published private(set) var wantsConfirmation = false
    @Published private(set) var isWorking = false
    private let reference: MyDayEligibleReferenceV1
    private let access: AppAccessPresentationV1.RoundAccess
    private let validateIntent: @MainActor () throws -> Void
    private var isActive = true
    private var resolution: PreparedRepetitiveCaptureDestinationResolutionV1?
    private var discard: PreparedRepetitiveCaptureDestinationDiscardV1?

    init(reference: MyDayEligibleReferenceV1, access: AppAccessPresentationV1.RoundAccess,
         validateIntent: @escaping @MainActor () throws -> Void) {
        self.reference = reference
        self.access = access
        self.validateIntent = validateIntent
    }

    var permitsDiscard: Bool {
        guard !isWorking, !isDiscarded, !couldNotLoad, provenance != nil, let checkpoint else { return false }
        return checkpoint.state == .recoveryRequired || checkpoint.state == .discardPending
    }

    func load() {
        guard !isWorking else { return }
        do {
            try requireIntent()
            guard let lineage = try access.readRepetitiveCaptureDestinationReview(reference: reference) else {
                throw FieldDraftFailureV1.invalidValue
            }
            try publish(lineage)
            couldNotLoad = false
        } catch {
            checkpoint = nil
            provenance = nil
            isDiscarded = false
            couldNotLoad = true
        }
    }

    func requestDiscard() {
        guard permitsDiscard else { return }
        do {
            try requireIntent()
            guard let checkpoint else { throw FieldDraftFailureV1.invalidValue }
            let current = try access.readRepetitiveCaptureDestinationReview(reviewDraftID: checkpoint.draftID)
            guard current.selectedReview.checkpoint == checkpoint else { throw ScanToWorkFailureV1.stale }
            wantsConfirmation = true
            couldNotDiscard = false
        } catch { couldNotDiscard = true; provenance = nil; wantsConfirmation = false }
    }

    func cancelConfirmation() { wantsConfirmation = false }

    /// No IDs or canonical writes are allocated until this explicit action.
    /// Frozen attempts survive a failed acknowledgement; retries use their
    /// authentic original receipts before considering any new effect.
    func confirmDiscard(confirmed: Bool) {
        guard confirmed, permitsDiscard, let displayed = checkpoint else { return }
        wantsConfirmation = false
        isWorking = true
        defer { isWorking = false }
        do {
            try requireIntent()
            let current = try access.readRepetitiveCaptureDestinationReview(reviewDraftID: displayed.draftID)
            guard current.selectedReview.checkpoint == displayed else { throw ScanToWorkFailureV1.stale }
            if displayed.state == .recoveryRequired || resolution != nil {
                if resolution == nil {
                    resolution = try access.prepareRepetitiveCaptureDestinationResolution(
                        reviewDraftID: displayed.draftID, plan: .discard, round: nil)
                }
                guard let resolution else { throw FieldDraftFailureV1.invalidValue }
                _ = try access.persistRepetitiveCaptureDestinationResolution(resolution,
                    validateIntent: { try self.requireIntent() })
            }
            try requireIntent()
            let pending = try access.readRepetitiveCaptureDestinationReview(reviewDraftID: displayed.draftID)
            if pending.selectedReview.checkpoint.state == .discarded {
                try publish(pending)
                couldNotDiscard = false
                return
            }
            guard pending.selectedReview.checkpoint.state == .discardPending else {
                throw FieldDraftFailureV1.invalidTransition
            }
            if discard == nil {
                discard = try access.prepareRepetitiveCaptureDestinationDiscard(reviewDraftID: displayed.draftID)
            }
            guard let discard else { throw FieldDraftFailureV1.invalidValue }
            _ = try access.persistRepetitiveCaptureDestinationDiscard(discard, confirmed: true,
                validateIntent: { try self.requireIntent() })
            try publish(access.readRepetitiveCaptureDestinationReview(reviewDraftID: displayed.draftID))
            couldNotDiscard = false
        } catch {
            couldNotDiscard = true
            provenance = nil
            wantsConfirmation = false
            // Do not replace a prepared attempt or present an unverified result.
        }
    }

    /// A read-only recovery after an uncertain acknowledgement. A pending
    /// discard still requires a fresh explicit confirmation before completion.
    func checkSavedResult() {
        guard !isWorking, let checkpoint else { return }
        do {
            try requireIntent()
            let current = try access.readRepetitiveCaptureDestinationReview(reviewDraftID: checkpoint.draftID)
            if resolution == nil && discard == nil && current.selectedReview.checkpoint != checkpoint {
                throw ScanToWorkFailureV1.stale
            }
            try publish(current)
            couldNotDiscard = false
        } catch { couldNotDiscard = true; provenance = nil; wantsConfirmation = false }
    }

    func invalidate() {
        isActive = false
        wantsConfirmation = false
        checkpoint = nil
        provenance = nil
        isDiscarded = false
    }

    private func requireIntent() throws {
        try Task.checkCancellation()
        guard isActive else { throw AppAccessContractFailureV1.accessDenied }
        try validateIntent()
    }

    private func publish(_ lineage: RepetitiveCaptureReviewLineageV1) throws {
        try requireIntent()
        let current = lineage.selectedReview.checkpoint
        guard case let .resumableDraft(workspaceID, draftID, _, _, _) = reference,
              current.workspaceID == workspaceID, current.draftID == draftID,
              [.recoveryRequired, .discardPending, .discarded].contains(current.state) else {
            throw ScanToWorkFailureV1.stale
        }
        let terminal: Bool
        if current.state == .discarded {
            guard let original = try access.readRepetitiveCaptureDestinationDiscard(reviewDraftID: draftID),
                  original.evidence.bundle.discardedCheckpoint == current else {
                throw ScanToWorkFailureV1.authorityMismatch
            }
            terminal = true
        } else { terminal = false }
        try requireIntent()
        let source = lineage.selectedReview.payload.source.value
        let originalRound = lineage.retainedSource.graph.packageCurrentRound
        let original = ProductionSavedReviewProvenanceV1(sourceWorkspaceID: source.sourceWorkspaceID,
            sourceDraftID: source.sourceDraftID, sourceRoundID: source.roundSessionID,
            recordedAt: originalRound.recordedAt, recordedBy: originalRound.recordedBy.displayNameAtTime,
            assetLabels: originalRound.items.map { $0.selection.labelAtSelection },
            restoreMode: lineage.selectedReview.payload.provenance.mode)
        checkpoint = current
        provenance = original
        isDiscarded = terminal
    }
}

struct ProductionRepetitiveCaptureReviewSheetV1: Identifiable {
    let id = UUID()
    let reference: MyDayEligibleReferenceV1
    let sceneSnapshot: SceneNavigationSnapshotV1
}

/// The same entry state is used by the Work view and native contract tests.
@MainActor
final class ProductionSavedReviewSheetStateV1: ObservableObject {
    @Published private(set) var route: ProductionRepetitiveCaptureReviewSheetV1?
    @Published private(set) var errorMessage: String?

    func open(_ reference: MyDayEligibleReferenceV1, scene: AppShellSceneStateV1,
              sceneAccess: AppAccessPresentationV1.SceneNavigationAccess,
              access: AppAccessPresentationV1.RoundAccess) {
        route = nil
        errorMessage = nil
        do {
            guard let snapshot = scene.snapshot, snapshot.selectedRoot == .work,
                  snapshot.path(for: .work)?.targets.isEmpty == true,
                  case let .restored(saved) = try sceneAccess.load(), saved == snapshot,
                  let review = try access.readRepetitiveCaptureDestinationReview(reference: reference),
                  [.recoveryRequired, .discardPending, .discarded]
                    .contains(review.selectedReview.checkpoint.state) else {
                throw SceneNavigationFailureV1.invalidSnapshot
            }
            route = .init(reference: reference, sceneSnapshot: snapshot)
        } catch {
            errorMessage = "This saved draft could not be opened. Refresh Work and try again."
        }
    }

    func validateIntent(_ expected: ProductionRepetitiveCaptureReviewSheetV1,
                        scene: AppShellSceneStateV1,
                        sceneAccess: AppAccessPresentationV1.SceneNavigationAccess) throws {
        guard route?.id == expected.id, scene.snapshot == expected.sceneSnapshot,
              scene.snapshot?.selectedRoot == .work,
              case let .restored(saved) = try sceneAccess.load(), saved == expected.sceneSnapshot else {
            throw SceneNavigationFailureV1.invalidSnapshot
        }
    }

    func dismiss() { route = nil }
    func dismissError() { errorMessage = nil }
}

@MainActor
struct ProductionSavedReviewRowV1: View {
    let source: MyDayLiveSourceV1
    let readiness: MyDaySourceReadinessAssessmentV1?
    let access: AppAccessPresentationV1.RoundAccess
    let open: (MyDayEligibleReferenceV1) -> Void
    @State private var supported = false

    var body: some View {
        Group {
            if supported {
                Button { open(source.reference) } label: { row }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("v23.work.saved-review." + source.reference.stableKey)
            } else { row }
        }
        .task(id: source.reference) {
            supported = false
            do {
                let review = try access.readRepetitiveCaptureDestinationReview(reference: source.reference)
                if let review {
                    supported = [.recoveryRequired, .discardPending, .discarded]
                        .contains(review.selectedReview.checkpoint.state)
                }
            } catch { supported = false }
        }
    }

    private var row: some View {
        AssetRoundsEvidenceCard { ProductionWorkSourceRowV1(source: source, readiness: readiness) }
    }
}

@MainActor
struct ProductionRepetitiveCaptureReviewDestinationV1: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var presentation: ProductionRepetitiveCaptureReviewPresentationV1

    init(reference: MyDayEligibleReferenceV1, access: AppAccessPresentationV1.RoundAccess,
         validateIntent: @escaping @MainActor () throws -> Void) {
        _presentation = StateObject(wrappedValue: ProductionRepetitiveCaptureReviewPresentationV1(
            reference: reference, access: access, validateIntent: validateIntent))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if presentation.couldNotLoad {
                        Text("This saved draft could not be opened. Close this view and refresh Work.")
                    } else if presentation.isDiscarded {
                        Label("Draft discarded", systemImage: "checkmark.circle")
                            .accessibilityIdentifier("v23.saved-review.discarded")
                        Text("The saved draft is closed. Original records are retained.")
                    } else if let checkpoint = presentation.checkpoint {
                        Text("Restored draft")
                            .font(.headline)
                        Text(checkpoint.state == .discardPending
                            ? "A discard was started. Confirm to finish closing this saved draft."
                            : "Review this saved draft before continuing.")
                        Text("Discard closes this saved draft. Work already recorded stays unchanged.")
                    } else { ProgressView("Opening saved draft") }
                }
                if let original = presentation.provenance {
                    Section("Original work") {
                        Text(original.recordedAt, format: .dateTime.year().month().day().hour().minute())
                        Text("Recorded by " + original.recordedBy)
                        ForEach(Array(original.assetLabels.enumerated()), id: \.offset) { _, label in
                            Text(label)
                        }
                        Text(original.restoreMode == .fork
                            ? "Restored as a separate workspace" : "Restored into this workspace")
                        Text("Original draft: " + original.sourceDraftID.uuidString.lowercased())
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                    .accessibilityIdentifier("v23.saved-review.provenance")
                }
                if presentation.permitsDiscard {
                    Section {
                        Button("Discard draft", role: .destructive) { presentation.requestDiscard() }
                            .accessibilityIdentifier("v23.saved-review.request-discard")
                    }
                }
                if presentation.couldNotDiscard {
                    Section {
                        Text("The result could not be confirmed. Check the saved result before trying again.")
                        Button("Check saved result") { presentation.checkSavedResult() }
                            .accessibilityIdentifier("v23.saved-review.check-result")
                    }
                }
            }
            .navigationTitle("Saved draft")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .confirmationDialog("Discard this saved draft?", isPresented: Binding(
                get: { presentation.wantsConfirmation },
                set: { if !$0 { presentation.cancelConfirmation() } }), titleVisibility: .visible) {
                Button("Discard draft", role: .destructive) { presentation.confirmDiscard(confirmed: true) }
                Button("Keep draft", role: .cancel) { presentation.cancelConfirmation() }
            } message: {
                Text("The saved draft will close. Original records and work already recorded will be kept.")
            }
            .accessibilityIdentifier("v23.saved-review.screen")
        }
        .task { presentation.load() }
        .onDisappear { presentation.invalidate() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { presentation.invalidate(); dismiss() }
        }
    }
}

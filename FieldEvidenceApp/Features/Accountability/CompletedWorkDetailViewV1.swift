import SwiftUI

typealias CompletedWorkListOperationV1 = @MainActor () throws -> [CompletedWorkSubjectListingV1]
typealias CompletedWorkDetailOperationV1 = @MainActor (CompletedWorkSubjectKeyV1) throws -> CompletedWorkSubjectDetailV1
typealias CompletedWorkPrepareOperationV1 = @MainActor (SignoffEnrollmentSubmissionV1, CompletedWorkSubjectProofV1) throws -> PreparedCompletedWorkResponseV1
typealias CompletedWorkRecordOperationV1 = @MainActor (PreparedCompletedWorkResponseV1) throws -> CompletedWorkResponseOutcomeV1
typealias CompletedWorkOpenHistoryOperationV1 = @MainActor (SignoffHistoryRouteV1) -> Void

/// The editor push for one validated completed-work version. It is local
/// Work-stack state, never a saved navigation route. When
/// `resumesRetainedAttempt` is true the editor reopens on an earlier attempt
/// for this same subject and offers only Try again.
struct CompletedWorkEditorRouteV1: Hashable, Identifiable {
    let id: UUID
    let proof: CompletedWorkSubjectProofV1
    let resumesRetainedAttempt: Bool

    var metadata: SignoffEnrollmentRouteMetadataV1 {
        SignoffEnrollmentRouteMetadataV1(
            workspaceID: proof.workspaceID,
            subjectID: proof.reportID,
            subjectRevision: proof.chainPosition,
            subject: proof.display
        )
    }
}

/// Typed fields kept for one subject only. In memory only.
struct CompletedWorkResponseDraftV1: Equatable {
    let typedName: String
    let claimedRole: String
    let claimedRelationship: SitePartyRoleV1?
}

enum CompletedWorkListStateV1: Equatable {
    case loading
    case loaded([CompletedWorkSubjectListingV1])
    case unavailable
}

enum CompletedWorkDetailStateV1: Equatable {
    case loading
    case loaded(CompletedWorkSubjectDetailV1)
    case unavailable
}

/// Work-root presentation state for SIG-1: the Completed work section, the
/// local detail push, the editor push and the real record result. Every
/// operation is supplied by the shell, which wraps each service call in the
/// current content-access read and owns the scene transition.
///
/// An operation whose canonical write was attempted but not confirmed is
/// retained per subject key, never across subjects. Reopening that subject's
/// editor shows the retained entries in Try-again mode; Record never
/// substitutes new entries for a retained attempt.
@MainActor
final class CompletedWorkPresentationV1: ObservableObject {
    struct Operations {
        let list: CompletedWorkListOperationV1
        let detail: CompletedWorkDetailOperationV1
        let prepare: CompletedWorkPrepareOperationV1
        let record: CompletedWorkRecordOperationV1
        let openHistory: CompletedWorkOpenHistoryOperationV1
    }

    @Published private(set) var list: CompletedWorkListStateV1 = .loading
    @Published var detailRoute: CompletedWorkSubjectKeyV1?
    @Published private(set) var detail: CompletedWorkDetailStateV1 = .loading
    @Published var editorRoute: CompletedWorkEditorRouteV1?
    /// The prefill for the currently presented editor's subject only.
    @Published private(set) var draft: CompletedWorkResponseDraftV1?
    @Published private(set) var lastResult: SignoffEnrollmentRecordResultV1?

    private let operations: Operations
    private var retainedBySubject: [CompletedWorkSubjectKeyV1: PreparedCompletedWorkResponseV1] = [:]
    private var draftsBySubject: [CompletedWorkSubjectKeyV1: CompletedWorkResponseDraftV1] = [:]

    #if DEBUG
    /// Observes the hosted instance; it cannot supply state or operations.
    static var didCreateForTesting: (@MainActor (CompletedWorkPresentationV1) -> Void)?
    #endif

    init(operations: Operations) {
        self.operations = operations
        #if DEBUG
        Self.didCreateForTesting?(self)
        #endif
    }

    /// The attempted operation retained for this subject's Try again, if any.
    func retainedOperation(for key: CompletedWorkSubjectKeyV1) -> PreparedCompletedWorkResponseV1? {
        retainedBySubject[key]
    }

    func refresh() {
        do {
            list = .loaded(try operations.list())
        } catch {
            list = .unavailable
        }
    }

    func open(_ listing: CompletedWorkSubjectListingV1) {
        editorRoute = nil
        draft = nil
        lastResult = nil
        detail = .loading
        detailRoute = listing.key
        loadDetail()
    }

    func loadDetail() {
        guard let key = detailRoute else {
            detail = .unavailable
            return
        }
        do {
            detail = .loaded(try operations.detail(key))
        } catch {
            detail = .unavailable
        }
    }

    func closeDetail() {
        editorRoute = nil
        detailRoute = nil
        draft = nil
    }

    /// More -> Record approval response. Ineligible subjects never open the
    /// editor; the detail shows the reason instead. A retained attempt for
    /// this subject reopens in Try-again mode with its own entries.
    func requestRecord() {
        guard case let .loaded(value) = detail,
              value.eligibility.canRecord,
              let proof = value.proof,
              let key = try? proof.key else { return }
        let retained = retainedBySubject[key]
        if let retained {
            draft = CompletedWorkResponseDraftV1(
                typedName: retained.typedName,
                claimedRole: retained.claimedRole,
                claimedRelationship: retained.claimedRelationship
            )
            lastResult = .uncertain
        } else {
            draft = draftsBySubject[key]
            lastResult = nil
        }
        editorRoute = CompletedWorkEditorRouteV1(
            id: UUID(),
            proof: proof,
            resumesRetainedAttempt: retained != nil
        )
    }

    /// Cancel leaves a retained attempt in place, discards this subject's
    /// unsent entries otherwise, and reloads the detail so eligibility and
    /// Record availability are current.
    func cancelEditor() {
        if let route = editorRoute, let key = try? route.proof.key,
           retainedBySubject[key] == nil {
            draftsBySubject[key] = nil
        }
        editorRoute = nil
        draft = nil
        lastResult = nil
        loadDetail()
    }

    /// The editor's Record action.
    func submit(_ submission: SignoffEnrollmentSubmissionV1) -> SignoffEnrollmentRecordResultV1 {
        guard let route = editorRoute, let key = try? route.proof.key else {
            return finish(.unavailable)
        }
        // No silent substitution: an attempted response for this subject is
        // resolved only through Try again with its retained entries.
        if retainedBySubject[key] != nil {
            return finish(.uncertain)
        }
        let entries = CompletedWorkResponseDraftV1(
            typedName: submission.typedName,
            claimedRole: submission.claimedRole,
            claimedRelationship: submission.claimedRelationship
        )
        draft = entries
        draftsBySubject[key] = entries
        let value: PreparedCompletedWorkResponseV1
        do {
            value = try operations.prepare(submission, route.proof)
        } catch let failure as CompletedWorkResponseFailureV1 {
            switch failure {
            case .stale:
                loadDetail()
                return finish(.stale)
            case .unavailable, .invalidSubmission, .notFound:
                return finish(.unavailable)
            }
        } catch {
            return finish(.accessDenied)
        }
        return perform(value, key: key, route: route)
    }

    /// The editor's Try again action for this subject's retained attempt.
    func retry() -> SignoffEnrollmentRecordResultV1 {
        guard let route = editorRoute, let key = try? route.proof.key,
              let existing = retainedBySubject[key] else {
            return finish(.unavailable)
        }
        return perform(existing, key: key, route: route)
    }

    private func perform(
        _ operation: PreparedCompletedWorkResponseV1,
        key: CompletedWorkSubjectKeyV1,
        route: CompletedWorkEditorRouteV1
    ) -> SignoffEnrollmentRecordResultV1 {
        let outcome: CompletedWorkResponseOutcomeV1
        do {
            outcome = try operations.record(operation)
        } catch {
            outcome = .accessDenied
        }
        switch outcome {
        case let .saved(receipt):
            let history = route.metadata.historyRoute(for: receipt)
            retainedBySubject[key] = nil
            draftsBySubject[key] = nil
            draft = nil
            editorRoute = nil
            detailRoute = nil
            _ = finish(.saved)
            operations.openHistory(history)
            refresh()
            return .saved
        case .stale:
            // No signoff is durable for a stale result; the operation ends.
            retainedBySubject[key] = nil
            loadDetail()
            return finish(.stale)
        case .unavailable:
            // No signoff is durable for an unavailable result.
            retainedBySubject[key] = nil
            return finish(.unavailable)
        case .accessDenied:
            // The service did not run; an attempted operation stays retained.
            if operation.attemptState == .canonicalWriteAttempted {
                retainedBySubject[key] = operation
            }
            return finish(.accessDenied)
        case .uncertain:
            retainedBySubject[key] = operation
            return finish(.uncertain)
        case .notRecorded:
            // Nothing durable for this response; Try again reuses the same
            // entries through the same prepared operation.
            retainedBySubject[key] = operation
            return finish(.notRecorded)
        }
    }

    private func finish(_ result: SignoffEnrollmentRecordResultV1) -> SignoffEnrollmentRecordResultV1 {
        lastResult = result
        return result
    }
}

/// Attaches the local completed-work detail push to the Work stack.
@MainActor
struct CompletedWorkNavigationModifierV1: ViewModifier {
    @ObservedObject var presentation: CompletedWorkPresentationV1

    func body(content: Content) -> some View {
        content.navigationDestination(item: $presentation.detailRoute) { key in
            CompletedWorkDetailViewV1(presentation: presentation, key: key)
        }
    }
}

extension View {
    @MainActor
    func completedWorkNavigation(_ presentation: CompletedWorkPresentationV1) -> some View {
        modifier(CompletedWorkNavigationModifierV1(presentation: presentation))
    }
}

/// Immutable completed-work detail. More -> Record approval response opens
/// the existing C43 editor only for the current version; otherwise the item
/// is disabled and the reason is shown on screen.
@MainActor
struct CompletedWorkDetailViewV1: View {
    static let reasonAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.immutable-work-detail.reason"

    @ObservedObject var presentation: CompletedWorkPresentationV1
    let key: CompletedWorkSubjectKeyV1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space16) {
                content
            }
            .padding(DesignTokens.Spacing.space16)
            #if DEBUG
            .background {
                NativeScreenObservationAnchorV1(
                    identifier: SignoffEnrollmentView.immutableDetailAccessibilityIdentifier
                )
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
            #endif
        }
        .navigationTitle("Completed work")
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.SemanticColors.workBackground)
        .accessibilityIdentifier(SignoffEnrollmentView.immutableDetailAccessibilityIdentifier)
        .navigationDestination(item: $presentation.editorRoute) { route in
            editor(route)
        }
    }

    private var loadedDetail: CompletedWorkSubjectDetailV1? {
        if case let .loaded(value) = presentation.detail, value.key == key {
            return value
        }
        return nil
    }

    private var canRecord: Bool {
        loadedDetail?.eligibility.canRecord == true && loadedDetail?.proof != nil
    }

    @ViewBuilder
    private var content: some View {
        if let value = loadedDetail {
            if let proof = value.proof {
                subjectCard(proof.display, responseCount: value.responseCount)
            } else {
                unavailableCard
            }
            if let reason = value.eligibility.reasonText {
                reasonText(reason)
            }
            moreMenu
        } else if presentation.detail == .loading {
            ProgressView("Opening completed work")
                .frame(maxWidth: .infinity, minHeight: DesignTokens.Target.minimumInteractiveHeight)
        } else {
            unavailableCard
        }
    }

    private func subjectCard(
        _ display: CompletedWorkSubjectDisplayV1,
        responseCount: Int
    ) -> some View {
        AssetRoundsEvidenceCard {
            Text(display.assetLabel)
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            factRow(label: "Site", value: display.siteLabel)
            factRow(label: "Stage", value: display.stage)
            factRow(label: "Outcome", value: display.outcome)
            factRow(label: "Completed", value: display.whenText)
            factRow(label: "Version", value: display.versionText)
            factRow(label: "Responses", value: Self.responseCountText(responseCount))
        }
        .accessibilityElement(children: .contain)
    }

    private var unavailableCard: some View {
        AssetRoundsEvidenceCard {
            Text("Completed work unavailable")
                .font(.title3.weight(.semibold))
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func reasonText(_ reason: String) -> some View {
        Text(reason)
            .font(.body.weight(.semibold))
            .foregroundStyle(DesignTokens.SemanticColors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(Self.reasonAccessibilityIdentifier)
    }

    private func factRow(label: String, value: String) -> some View {
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

    /// More -> Record approval response. The menu stays on screen so an
    /// ineligible subject shows a disabled action next to its reason.
    private var moreMenu: some View {
        Menu {
            Button {
                presentation.requestRecord()
            } label: {
                Text(verbatim: SignoffEnrollmentManifestV1.actionTitle)
            }
            .disabled(!canRecord)
            .accessibilityIdentifier(SignoffEnrollmentView.recordResponseAccessibilityIdentifier)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
                .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
        }
        .accessibilityHint("Shows actions for this completed work.")
        .accessibilityIdentifier(SignoffEnrollmentView.moreAccessibilityIdentifier)
    }

    private func editor(_ route: CompletedWorkEditorRouteV1) -> some View {
        let draft = presentation.draft
        let model = presentation
        var retainedMark = false
        if route.resumesRetainedAttempt, let key = try? route.proof.key,
           let retained = model.retainedOperation(for: key) {
            retainedMark = retained.drawnMark != nil
        }
        return SignoffEnrollmentView(
            route: route.metadata,
            revisionState: .current,
            initialTypedName: draft?.typedName ?? "",
            initialClaimedRole: draft?.claimedRole ?? "",
            initialClaimedRelationship: draft?.claimedRelationship,
            resumesRetainedAttempt: route.resumesRetainedAttempt,
            retainedAttemptHasDrawnMark: retainedMark,
            onRecordResponse: { submission in model.submit(submission) },
            onRetry: { model.retry() },
            onCancel: { model.cancelEditor() }
        )
    }

    static func responseCountText(_ count: Int) -> String {
        switch count {
        case 0: return "No responses recorded"
        case 1: return "1 response recorded"
        default: return "\(count) responses recorded"
        }
    }
}

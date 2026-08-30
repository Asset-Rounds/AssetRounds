import Foundation
import SwiftData

@MainActor final class InspectionReviewLifecycleAdapterV1 {
    private let modelContext: ModelContext
    init(modelContext: ModelContext) { self.modelContext = modelContext }

    func reviewProjection(workspaceID: WorkspaceID, reviewID: UUID) throws -> InspectionReviewProjectionV1 {
        let transitions = try modelContext.fetch(FetchDescriptor<InspectionReviewTransitionRow>()).map { try $0.value() }
        let dispositions = try modelContext.fetch(FetchDescriptor<ReviewDispositionRow>()).map { try $0.value() }
        let requests = try modelContext.fetch(FetchDescriptor<ChangeRequestRow>()).map { try $0.value() }
        return try InspectionReviewProjectionBuilderV1.rebuild(workspaceID: workspaceID, reviewID: reviewID, transitions: transitions, dispositions: dispositions, changeRequests: requests)
    }

    func correctiveActionProjection(workspaceID: WorkspaceID, actionID: UUID, now: Date) throws -> CorrectiveActionProjectionV1 {
        let events = try modelContext.fetch(FetchDescriptor<CorrectiveActionEventRow>()).map { try $0.value() }
        let policies = try modelContext.fetch(FetchDescriptor<CorrectiveActionPolicyRow>()).map { try $0.value() }
        return try CorrectiveActionProjectionBuilderV1.rebuild(workspaceID: workspaceID, actionID: actionID, events: events, policies: policies, now: now)
    }

    /// Read-only exact C14 basis used by C48 preview and the immediate
    /// pre-write recheck. No portable session fact is persisted here.
    func portableReviewBasis(
        mapping: ReviewRequestC14SubjectItemMappingV1,
        reviewID: UUID
    ) throws -> InspectionReviewProjectionV1 {
        try mapping.validate()
        let projection = try reviewProjection(workspaceID: mapping.workspaceID, reviewID: reviewID)
        let transitions = try modelContext.fetch(FetchDescriptor<InspectionReviewTransitionRow>()).map { try $0.value() }
        guard let head = transitions.first(where: { $0.transitionID == projection.headTransitionID }),
              head.workspaceID == mapping.workspaceID,
              head.reviewID == reviewID,
              head.subject == mapping.subject else { throw InspectionReviewFailureV1.staleRevision }
        return projection
    }
}

// MARK: - C49 work-resource review boundary

/// C49 review stays on the existing C14 read/lifecycle path. A review is a
/// derived projection and cannot append work-resource rows or resolve live
/// inventory/price data.
enum C49WorkResourceInspectionReviewLifecycleBoundaryV1 {
    static let readsCanonicalWorkResourceHistory = true
    static let reviewUsesExistingC14Lifecycle = true
    static let directCostDefaultVisibility = "INTERNAL_ONLY"
    static let customerSafeCostRequiresExplicitPreview = true
    static let reviewMayWriteWorkResourceRows = false
    static let liveInventoryLookup = false
    static let privateContentBytesEntered = false
    static let reportAndReviewAreDerived = true
}

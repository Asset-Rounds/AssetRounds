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
}

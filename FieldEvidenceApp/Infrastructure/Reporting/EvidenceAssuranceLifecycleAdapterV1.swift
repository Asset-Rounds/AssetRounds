import Foundation
import SwiftData
@MainActor final class EvidenceAssuranceLifecycleAdapterV1{
    private let modelContext:ModelContext;init(modelContext:ModelContext){self.modelContext=modelContext}
    func currentLinks(workspaceID:WorkspaceID,audience:EvidenceAudienceV1)throws->[ClaimEvidenceLinkV1]{let raw=workspaceID.rawValue;let values=try modelContext.fetch(FetchDescriptor<ClaimEvidenceLinkRow>(predicate:#Predicate{$0.workspaceID==raw})).map{try $0.value()};let superseded=Set(values.compactMap(\.supersedesLinkID));return values.filter{!superseded.contains($0.linkID)&&$0.decision.audience==audience}.sorted{$0.linkID.uuidString<$1.linkID.uuidString}}
    func preview(previewID:UUID,workspaceID:WorkspaceID,audience:EvidenceAudienceV1,snapshotSHA256:String,projectionVersion:String,createdAt:Date)throws->AssuranceProjectionPreviewV1{try .init(previewID:previewID,workspaceID:workspaceID,audience:audience,snapshotSHA256:snapshotSHA256,projectionVersion:projectionVersion,links:currentLinks(workspaceID:workspaceID,audience:audience),createdAt:createdAt)}
}

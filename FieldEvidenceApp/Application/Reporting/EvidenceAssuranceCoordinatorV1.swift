import Foundation
@MainActor final class EvidenceAssuranceCoordinatorV1{
    private let writer:WorkspaceWriterV1;private let lifecycle:EvidenceAssuranceLifecycleAdapterV1
    init(writer:WorkspaceWriterV1,lifecycle:EvidenceAssuranceLifecycleAdapterV1){self.writer=writer;self.lifecycle=lifecycle}
    func apply(_ mutation:EvidenceAssuranceMutationV1)throws->EvidenceAssuranceMutationReceiptV1{try mutation.validate();_ = try writer.execute(.applyEvidenceAssurance(mutation),mutationID:mutation.mutationID);guard let receipt=try writer.durableReceipt(mutationID:mutation.mutationID)else{throw WorkspaceMutationFailureV1.invalidReceipt};return try .init(mutation:mutation,mutationReceipt:receipt)}
    func preview(previewID:UUID,workspaceID:WorkspaceID,audience:EvidenceAudienceV1,snapshotSHA256:String,projectionVersion:String,createdAt:Date)throws->AssuranceProjectionPreviewV1{try lifecycle.preview(previewID:previewID,workspaceID:workspaceID,audience:audience,snapshotSHA256:snapshotSHA256,projectionVersion:projectionVersion,createdAt:createdAt)}
    func manifest(id:UUID,workspaceID:WorkspaceID,revision:UInt64,sha256:String)throws->AssuranceManifestV1{try lifecycle.manifest(id:id,workspaceID:workspaceID,revision:revision,sha256:sha256)}
}

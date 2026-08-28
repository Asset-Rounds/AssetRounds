import Foundation

struct ClientCapabilityWriteReceiptV1:Codable,Equatable,Sendable{let mutationID:MutationIDV1;let postImageSHA256:String;let canonicalMutationReceiptSHA256:String;init(mutationID:MutationIDV1,postImageSHA256:String,canonicalMutationReceiptSHA256:String)throws{try ClientCapabilityValidationV1.digest(postImageSHA256);try ClientCapabilityValidationV1.digest(canonicalMutationReceiptSHA256);self.mutationID=mutationID;self.postImageSHA256=postImageSHA256;self.canonicalMutationReceiptSHA256=canonicalMutationReceiptSHA256}}

@MainActor
protocol ClientCapabilityWritingV1:AnyObject{
    func acceptedWriteReceipt(for mutation:ClientCapabilityMutationV1)throws->ClientCapabilityWriteReceiptV1?
    func applyClientCapability(_ mutation:ClientCapabilityMutationV1)throws->ClientCapabilityWriteReceiptV1
}

@MainActor
final class ClientCapabilityCoordinatorV1{
    private let writer:any ClientCapabilityWritingV1
    init(writer:any ClientCapabilityWritingV1){self.writer=writer}

    func recordProfile(_ value:ClientCapabilityProfileV1)throws->ClientCapabilityWriteReceiptV1{try commit(.profile(value),expectedSHA256:value.profileSHA256)}
    func recordPolicy(_ value:PackageLifecyclePolicyV1,release:InspectionPackageReleaseV1)throws->ClientCapabilityWriteReceiptV1{try commit(.policy(value:value,release:release),expectedSHA256:value.policySHA256)}
    func recordDisposition(_ value:PackageLifecycleDispositionV1,release:InspectionPackageReleaseV1)throws->ClientCapabilityWriteReceiptV1{try commit(.disposition(value:value,release:release),expectedSHA256:value.dispositionSHA256)}

    func previewAdmission(decisionID:UUID,workspaceID:WorkspaceID,profile:ClientCapabilityProfileV1,policy:PackageLifecyclePolicyV1,disposition:PackageLifecycleDispositionV1,release:InspectionPackageReleaseV1,operation:PackageLifecycleOperationV1,decidedAt:Date,mutationID:MutationIDV1)throws->ClientCapabilityAdmissionDecisionV1{
        let result=ClientCapabilityAdmissionEvaluatorV1.evaluate(profile:profile,policy:policy,disposition:disposition,release:release,operation:operation)
        return try .init(decisionID:decisionID,workspaceID:workspaceID,profile:profile,policy:policy,disposition:disposition,release:release,operation:operation,admission:result.0,reasons:result.1,decidedAt:decidedAt,mutationID:mutationID)
    }

    func recordAdmission(_ value:ClientCapabilityAdmissionDecisionV1,profile:ClientCapabilityProfileV1,policy:PackageLifecyclePolicyV1,disposition:PackageLifecycleDispositionV1,release:InspectionPackageReleaseV1)throws->ClientCapabilityWriteReceiptV1{
        let expected=ClientCapabilityAdmissionEvaluatorV1.evaluate(profile:profile,policy:policy,disposition:disposition,release:release,operation:value.operation)
        guard value.admission==expected.0,value.reasons==expected.1.sorted(by:{$0.rawValue<$1.rawValue})else{throw ClientCapabilityFailureV1.admissionDenied}
        return try commit(.admission(value:value,profile:profile,policy:policy,disposition:disposition,release:release),expectedSHA256:value.decisionSHA256)
    }

    private func commit(_ mutation:ClientCapabilityMutationV1,expectedSHA256:String)throws->ClientCapabilityWriteReceiptV1{
        try mutation.validate()
        if let receipt=try writer.acceptedWriteReceipt(for:mutation){guard receipt.postImageSHA256==expectedSHA256 else{throw ClientCapabilityFailureV1.digestMismatch};return receipt}
        let receipt=try writer.applyClientCapability(mutation)
        guard receipt.mutationID==mutation.mutationID,receipt.postImageSHA256==expectedSHA256 else{throw ClientCapabilityFailureV1.digestMismatch}
        return receipt
    }
}

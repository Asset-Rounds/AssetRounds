import CryptoKit
import Foundation

struct Ed25519LocalLocatorSignatureVerifierV1: LocalLocatorSignatureVerifyingV1 {
    func verify(payload:Data,signature:Data,key:LocatorSigningKeyReferenceV1)throws->Bool{try key.validate();guard signature.count==AssetLocatorLimitsV1.ed25519SignatureBytes else{return false};do{return try Curve25519.Signing.PublicKey(rawRepresentation:key.publicKeyData).isValidSignature(signature,for:payload)}catch{return false}}
}

struct AssetLocatorInputDecoderV1:Sendable{
    func localSigned(_ bytes:Data,source:LocatorInputSourceV1)throws->LocatorResolutionInputV1{let digest=KernelCanonicalHashV1.sha256(bytes);guard !bytes.isEmpty,bytes.count<=AssetLocatorLimitsV1.maximumInputBytes else{return try .init(source:source,inputSHA256:digest,decoded:.damagedOrIncomplete)};do{let payload=try AssetLocatorCanonicalCodecV1.decode(SignedLocalAssetLocatorPayloadV1.self,from:bytes);try payload.validateStructure();return try .init(source:source,inputSHA256:digest,decoded:.localSigned(payload))}catch{return try .init(source:source,inputSHA256:digest,decoded:.damagedOrIncomplete)}}
    func externalKey(_ bytes:Data,namespaceID:String,normalization:ExternalKeyNormalizationV1,source:LocatorInputSourceV1)throws->LocatorResolutionInputV1{let digest=KernelCanonicalHashV1.sha256(bytes);guard !bytes.isEmpty,bytes.count<=AssetLocatorLimitsV1.maximumInputBytes,let value=String(data:bytes,encoding:.utf8)else{return try .init(source:source,inputSHA256:digest,decoded:.damagedOrIncomplete)};do{return try .init(source:source,inputSHA256:digest,decoded:.externalKey(try ExternalKeyV1(namespaceID:namespaceID,normalization:normalization,suppliedValue:value)))}catch{return try .init(source:source,inputSHA256:digest,decoded:.damagedOrIncomplete)}}
}

struct AssetLocatorLifecycleAdapterV1{
    let resolver:OfflineAssetLocatorResolverV1
    let writer:(any AssetLocatorMutationCommittingV1)?
    init(resolver:OfflineAssetLocatorResolverV1,writer:(any AssetLocatorMutationCommittingV1)?=nil){self.resolver=resolver;self.writer=writer}
    func resolve(_ input:LocatorResolutionInputV1,workspaceID:WorkspaceID,evaluatedAt:Date)async throws->LocatorResolutionV1{try await resolver.resolve(input,workspaceID:workspaceID,evaluatedAt:evaluatedAt)}
    func publish(_ mutation:AssetLocatorMutationV1)throws->AssetLocatorMutationReceiptV1{guard let writer else{throw WorkspaceMutationFailureV1.writerInvalidated};try mutation.validate();let receipt=try writer.commitAssetLocator(mutation);return try .init(mutation:mutation,mutationReceipt:receipt)}
    func validateClosure(locators:[AssetLocatorV1],receipts:[LocatorBindingReceiptV1])throws{_ = try AssetLocatorLifecycleClosureV1(locators:locators,receipts:receipts)}
    static let scanMutatesCanonicalState=false
    static let resolutionStartsWork=false
    static let resolutionGrantsAccess=false
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Infrastructure_AssetSemantics_AssetLocatorLifecycleAdapterV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Infrastructure_AssetSemantics_AssetLocatorLifecycleAdapterV1_swift {
    /// Typed C37 boundary: inherited owners may retain an immutable pose
    /// reference, but cannot infer pose, compliance, or current-state truth.
    static func validate(reference: AssetPoseEventReferenceV1,
                         in workspaceID: WorkspaceID) throws {
        try reference.validate()
        guard reference.workspaceID == workspaceID else {
            throw PlacementPoseFailureV1.wrongWorkspace
        }
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Infrastructure_AssetSemantics_AssetLocatorLifecycleAdapterV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/AssetSemantics/AssetLocatorLifecycleAdapterV1.swift", role: .asset)
}

import Foundation

enum LocatorDecodedInputV1: Equatable, Sendable {
    case localSigned(SignedLocalAssetLocatorPayloadV1)
    case externalKey(ExternalKeyV1)
    case damagedOrIncomplete
}

struct LocatorResolutionInputV1: Equatable, Sendable {
    let source: LocatorInputSourceV1
    let inputSHA256: String
    let decoded: LocatorDecodedInputV1

    init(source: LocatorInputSourceV1, rawBytes: Data, decoded: LocatorDecodedInputV1) throws {
        guard !rawBytes.isEmpty, rawBytes.count <= AssetLocatorLimitsV1.maximumInputBytes else {
            throw AssetLocatorFailureV1.limitExceeded
        }
        self.source=source;inputSHA256=KernelCanonicalHashV1.sha256(rawBytes);self.decoded=decoded
    }
    init(source:LocatorInputSourceV1,inputSHA256:String,decoded:LocatorDecodedInputV1)throws{guard KernelCanonicalHashV1.validSHA256(inputSHA256)else{throw AssetLocatorFailureV1.invalidValue};self.source=source;self.inputSHA256=inputSHA256;self.decoded=decoded}
}

protocol AssetLocatorQueryingV1: Sendable {
    func locator(id: UUID, workspaceID: WorkspaceID) async throws -> AssetLocatorV1?
    func locators(lookupKey: String, workspaceID: WorkspaceID) async throws -> [AssetLocatorV1]
    func locatorExistsOutsideWorkspace(
        lookupKey: String,
        workspaceID: WorkspaceID
    ) async throws -> Bool
}

extension AssetLocatorQueryingV1 {
    func locatorExistsOutsideWorkspace(
        lookupKey: String,
        workspaceID: WorkspaceID
    ) async throws -> Bool { false }
}

protocol LocalLocatorSignatureVerifyingV1: Sendable {
    func verify(payload: Data, signature: Data, key: LocatorSigningKeyReferenceV1) throws -> Bool
}

struct OfflineAssetLocatorResolverV1: Sendable {
    let query: any AssetLocatorQueryingV1
    let signatureVerifier: any LocalLocatorSignatureVerifyingV1

    func resolve(_ input: LocatorResolutionInputV1, workspaceID: WorkspaceID, evaluatedAt: Date) async throws -> LocatorResolutionV1 {
        switch input.decoded {
        case .damagedOrIncomplete:
            return try result(input,.damagedOrIncomplete,workspaceID,evaluatedAt,nil,[])
        case .localSigned(let payload):
            do { try payload.validateStructure() } catch { return try result(input,.damagedOrIncomplete,workspaceID,evaluatedAt,nil,[]) }
            guard payload.workspaceID == workspaceID else { return try result(input,.foreignWorkspace,workspaceID,evaluatedAt,nil,[]) }
            guard try signatureVerifier.verify(payload:payload.unsignedCanonicalData(),signature:payload.signatureData,key:payload.signingKey) else{return try result(input,.damagedOrIncomplete,workspaceID,evaluatedAt,nil,[])}
            guard let locator=try await query.locator(id:payload.locatorID,workspaceID:workspaceID) else{return try result(input,.noMatch,workspaceID,evaluatedAt,nil,[])}
            guard case .localSigned(let stored)=locator.representation,stored==payload else{return try result(input,.damagedOrIncomplete,workspaceID,evaluatedAt,nil,[])}
            return try result(input,outcome(locator.state),workspaceID,evaluatedAt,locator,[])
        case .externalKey(let key):
            do { try key.validate() } catch { return try result(input,.damagedOrIncomplete,workspaceID,evaluatedAt,nil,[]) }
            let candidates=try await query.locators(lookupKey:key.lookupKey,workspaceID:workspaceID).sorted{$0.locatorID.uuidString<$1.locatorID.uuidString}
            guard candidates.count<=AssetLocatorLimitsV1.maximumCandidates else{return try result(input,.ambiguous,workspaceID,evaluatedAt,nil,Array(candidates.prefix(AssetLocatorLimitsV1.maximumCandidates)))}
            guard !candidates.isEmpty else {
                let foreign = try await query.locatorExistsOutsideWorkspace(
                    lookupKey: key.lookupKey, workspaceID: workspaceID
                )
                return try result(
                    input, foreign ? .foreignWorkspace : .noMatch,
                    workspaceID, evaluatedAt, nil, []
                )
            }
            guard candidates.count==1 else{return try result(input,.ambiguous,workspaceID,evaluatedAt,nil,candidates)}
            return try result(input,outcome(candidates[0].state),workspaceID,evaluatedAt,candidates[0],[])
        }
    }

    private func outcome(_ state:AssetLocatorStateV1)->LocatorResolutionOutcomeV1{switch state{case .active:return .matched;case .retired:return .retired;case .revoked:return .revoked;case .replaced:return .replaced}}
    private func result(_ input:LocatorResolutionInputV1,_ outcome:LocatorResolutionOutcomeV1,_ workspaceID:WorkspaceID,_ at:Date,_ locator:AssetLocatorV1?,_ candidates:[AssetLocatorV1])throws->LocatorResolutionV1{try .init(workspaceID:workspaceID,source:input.source,inputSHA256:input.inputSHA256,outcome:outcome,matchedLocator:try locator?.reference,matchedAssetID:locator?.assetID,replacementLocatorID:locator?.replacedByLocatorID,candidateLocators:try candidates.map{$0.reference},evaluatedAt:at)}
}

struct AssetLocatorCoordinatorV1: Sendable {
    let resolver: OfflineAssetLocatorResolverV1
    func resolveCamera(_ input:LocatorResolutionInputV1,workspaceID:WorkspaceID,evaluatedAt:Date)async throws->LocatorResolutionV1{guard input.source == .camera else{throw AssetLocatorFailureV1.invalidValue};return try await resolver.resolve(input,workspaceID:workspaceID,evaluatedAt:evaluatedAt)}
    func resolveManual(_ input:LocatorResolutionInputV1,workspaceID:WorkspaceID,evaluatedAt:Date)async throws->LocatorResolutionV1{guard input.source == .manual else{throw AssetLocatorFailureV1.invalidValue};return try await resolver.resolve(input,workspaceID:workspaceID,evaluatedAt:evaluatedAt)}
    func resolveImported(_ input:LocatorResolutionInputV1,workspaceID:WorkspaceID,evaluatedAt:Date)async throws->LocatorResolutionV1{guard input.source == .imported else{throw AssetLocatorFailureV1.invalidValue};return try await resolver.resolve(input,workspaceID:workspaceID,evaluatedAt:evaluatedAt)}
    func preview(action:LocatorBindingActionV1,before:AssetLocatorV1?,after:AssetLocatorV1,replacement:AssetLocatorV1?,generatedAt:Date)throws->LocatorBindingPreviewV1{let value=try LocatorBindingPreviewV1(workspaceID:after.workspaceID,action:action,before:try before?.reference,after:after.reference,replacement:try replacement?.reference,generatedAt:generatedAt);try value.validate(before:before,after:after,replacement:replacement);return value}
}

protocol AssetLocatorMutationCommittingV1: AnyObject {
    func commitAssetLocator(_ mutation: AssetLocatorMutationV1) throws -> MutationReceiptV1
}

extension WorkspaceWriterV1: AssetLocatorMutationCommittingV1 {}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Application_AssetSemantics_AssetLocatorCoordinatorV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Application_AssetSemantics_AssetLocatorCoordinatorV1_swift {
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
enum C30ConsumerBoundaryV1_Application_AssetSemantics_AssetLocatorCoordinatorV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Application/AssetSemantics/AssetLocatorCoordinatorV1.swift", role: .asset)
}

enum C31LightingConsumerBoundary_Application_AssetSemantics_AssetLocatorCoordinatorV1 {
    static let registrationID = "C31_LIGHTING_CONSUMER/asset-locator-coordinator"
    static let compatibility = C31LightingCompatibilityPolicyV1()
    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}

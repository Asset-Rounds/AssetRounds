import Foundation
enum EvidenceContextAssetLocatorBoundaryV1{static let locatorLookupNeverSubstitutesForExactAssetRevision=true;static let contextRowsOwnNoLocatorProjection=true}
enum PlacementPoseAssetLocatorPersistenceBoundaryV1{static let locatorIdentityNeverReplacesAssetIdentity=true;static let poseEventsBindAssetIDDirectly=true}
import SwiftData

enum PlanAssetLocatorPersistenceBindingV1 { static let planPlacementRequiresExactBindingReceipt = true; static let locatorResolutionIsDerived = true }

enum AssetLocatorPersistenceFailureV1: Error { case corruptRow }

private func assetLocatorDecoded<T:Codable & Equatable>(_ type:T.Type,data:Data,expected:T?=nil)throws->T{let value=try AssetLocatorCanonicalCodecV1.decode(type,from:data);if let expected,value != expected{throw AssetLocatorPersistenceFailureV1.corruptRow};return value}

@Model final class AssetLocatorRow{
    @Attribute(.unique) var locatorID:UUID
    var workspaceID:UUID
    var assetID:UUID
    var lookupKey:String
    var stateRawValue:String
    var replacedByLocatorID:UUID?
    var revision:UInt64
    var mutationID:UUID
    var locatorSHA256:String
    var canonicalData:Data

    init(_ value:AssetLocatorV1)throws{try value.validate();locatorID=value.locatorID;workspaceID=value.workspaceID.rawValue;assetID=value.assetID;lookupKey=value.lookupKey;stateRawValue=value.state.rawValue;replacedByLocatorID=value.replacedByLocatorID;revision=value.revision;mutationID=value.mutationID.rawValue;locatorSHA256=value.locatorSHA256;canonicalData=try AssetLocatorCanonicalCodecV1.encode(value);_ = try assetLocatorDecoded(AssetLocatorV1.self,data:canonicalData,expected:value)}
    func value()throws->AssetLocatorV1{let value=try assetLocatorDecoded(AssetLocatorV1.self,data:canonicalData);try value.validate();guard value.locatorID==locatorID,value.workspaceID.rawValue==workspaceID,value.assetID==assetID,value.lookupKey==lookupKey,value.state.rawValue==stateRawValue,value.replacedByLocatorID==replacedByLocatorID,value.revision==revision,value.mutationID.rawValue==mutationID,value.locatorSHA256==locatorSHA256 else{throw AssetLocatorPersistenceFailureV1.corruptRow};return value}
    func value(reboundTo workspaceID:WorkspaceID,representation:AssetLocatorRepresentationV1,predecessorLocatorSHA256:String?)throws->AssetLocatorV1{try value().rebound(to:workspaceID,representation:representation,predecessorLocatorSHA256:predecessorLocatorSHA256)}
    func replace(with value:AssetLocatorV1,expectedRevision:UInt64)throws{let prior=try self.value();guard prior.revision==expectedRevision else{throw AssetLocatorPersistenceFailureV1.corruptRow};try value.validateSuccessor(of:prior);let data=try AssetLocatorCanonicalCodecV1.encode(value);_ = try assetLocatorDecoded(AssetLocatorV1.self,data:data,expected:value);workspaceID=value.workspaceID.rawValue;assetID=value.assetID;lookupKey=value.lookupKey;stateRawValue=value.state.rawValue;replacedByLocatorID=value.replacedByLocatorID;revision=value.revision;mutationID=value.mutationID.rawValue;locatorSHA256=value.locatorSHA256;canonicalData=data}
}

@Model final class LocatorBindingReceiptRow{
    @Attribute(.unique) var receiptID:UUID
    var workspaceID:UUID
    var actionRawValue:String
    var afterLocatorID:UUID
    var replacementLocatorID:UUID?
    var previewGeneratedAt:Date
    var predecessorReceiptID:UUID?
    var revision:UInt64
    var mutationID:UUID
    var receiptSHA256:String
    var canonicalData:Data

    init(_ value:LocatorBindingReceiptV1)throws{try value.validateIntrinsic();receiptID=value.receiptID;workspaceID=value.workspaceID.rawValue;actionRawValue=value.action.rawValue;afterLocatorID=value.after.locatorID;replacementLocatorID=value.replacement?.locatorID;previewGeneratedAt=value.previewGeneratedAt;predecessorReceiptID=value.predecessorReceiptID;revision=value.revision;mutationID=value.mutationID.rawValue;receiptSHA256=value.receiptSHA256;canonicalData=try AssetLocatorCanonicalCodecV1.encode(value);_ = try assetLocatorDecoded(LocatorBindingReceiptV1.self,data:canonicalData,expected:value)}
    func value()throws->LocatorBindingReceiptV1{let value=try assetLocatorDecoded(LocatorBindingReceiptV1.self,data:canonicalData);try value.validateIntrinsic();guard value.receiptID==receiptID,value.workspaceID.rawValue==workspaceID,value.action.rawValue==actionRawValue,value.after.locatorID==afterLocatorID,value.replacement?.locatorID==replacementLocatorID,value.previewGeneratedAt==previewGeneratedAt,value.predecessorReceiptID==predecessorReceiptID,value.revision==revision,value.mutationID.rawValue==mutationID,value.receiptSHA256==receiptSHA256 else{throw AssetLocatorPersistenceFailureV1.corruptRow};return value}
    func value(predecessor:LocatorBindingReceiptV1?)throws->LocatorBindingReceiptV1{let value=try self.value();try value.validate(preview:value.reconstructedPreview,predecessor:predecessor);return value}
    func value(reboundTo workspaceID:WorkspaceID,preview:LocatorBindingPreviewV1,recordedBy:ActorSnapshotV1,predecessor:LocatorBindingReceiptV1?)throws->LocatorBindingReceiptV1{try value().rebound(to:workspaceID,preview:preview,recordedBy:recordedBy,predecessor:predecessor)}
}

/// Read-only SwiftData query authority used by the derived offline resolver.
/// It returns every current head so duplicate lookup keys remain ambiguous.
@MainActor final class AssetLocatorRowQueryV1:AssetLocatorQueryingV1{
    private let modelContext:ModelContext
    init(modelContext:ModelContext){self.modelContext=modelContext}
    func locator(id:UUID,workspaceID:WorkspaceID)async throws->AssetLocatorV1?{let workspace=workspaceID.rawValue,rows=try modelContext.fetch(FetchDescriptor<AssetLocatorRow>(predicate:#Predicate{$0.locatorID==id&&$0.workspaceID==workspace}));guard rows.count<=1 else{throw AssetLocatorPersistenceFailureV1.corruptRow};return try rows.first?.value()}
    func bindingReceipt(id:UUID,workspaceID:WorkspaceID)async throws->LocatorBindingReceiptV1?{let workspace=workspaceID.rawValue,rows=try modelContext.fetch(FetchDescriptor<LocatorBindingReceiptRow>(predicate:#Predicate{$0.receiptID==id&&$0.workspaceID==workspace}));guard rows.count<=1 else{throw AssetLocatorPersistenceFailureV1.corruptRow};return try rows.first?.value()}
    func locators(lookupKey:String,workspaceID:WorkspaceID)async throws->[AssetLocatorV1]{let workspace=workspaceID.rawValue,rows=try modelContext.fetch(FetchDescriptor<AssetLocatorRow>(predicate:#Predicate{$0.lookupKey==lookupKey&&$0.workspaceID==workspace}));return try rows.map{$0.value()}.sorted{$0.locatorID.uuidString<$1.locatorID.uuidString}}
    func locatorExistsOutsideWorkspace(lookupKey:String,workspaceID:WorkspaceID)async throws->Bool{let workspace=workspaceID.rawValue,rows=try modelContext.fetch(FetchDescriptor<AssetLocatorRow>(predicate:#Predicate{$0.lookupKey==lookupKey&&$0.workspaceID != workspace}));return !rows.isEmpty}
}

enum LightingAssetLocatorReuseV1 { static let locatorHistoryRemainsReferencedAuthority = true; static let topologyDoesNotPersistLocatorCopies = true }

enum C31LightingAssetLocatorPersistenceBoundaryV1 {
    static let locatorDigestAndIdentityMayBeProjected = true
    static let rawLookupTokensRemainOutsideReports = true
    static let crossWorkspaceLocatorReadsFailClosed = true
}
// MARK: - C32 assistance asset locator persistence boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Models_AssetLocatorPersistenceModelsV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let proposalNotPersistedInLocatorRows = true

    static func validateProposal(_ proposal: AssistanceProposalV1, in context: AssistanceProposalEvaluationContextV1) throws {
        try proposal.validate()
        try context.validate()
        guard proposal.verificationState.rawValue == AssistanceProposalVerificationStateV1.unverified.rawValue,
              context.policy.manualFallback == .typeManually else {
            throw AssistanceContractFailureV1.incompatibleCapability
        }
        if let reason = try proposal.expiryReason(in: context) {
            throw AssistanceContractFailureV1.expired(reason)
        }
    }

    static func validateAcceptanceReceipt(_ receipt: AssistanceAcceptanceReceiptV1) throws {
        try receipt.validate()
    }
}

enum C33TemporalEvidenceBoundary_Domain_Models_AssetLocatorPersistenceModelsV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row138 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}

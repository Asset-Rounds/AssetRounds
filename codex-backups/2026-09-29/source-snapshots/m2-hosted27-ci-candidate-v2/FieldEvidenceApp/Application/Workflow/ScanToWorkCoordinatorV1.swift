import Foundation

@MainActor
final class ScanToWorkCoordinatorV1 {
    private let workspaceID: WorkspaceID
    private let resolver: any ScanToWorkExactResolvingV1
    private let roundCoordinator: RoundSessionCoordinatorV1

    init(workspaceID: WorkspaceID, resolver: any ScanToWorkExactResolvingV1,
         roundCoordinator: RoundSessionCoordinatorV1) {
        self.workspaceID = workspaceID; self.resolver = resolver; self.roundCoordinator = roundCoordinator
    }

    func preview(source: ScanToWorkEntrySourceV1, rawBytes: Data,
                 selectedAssetIDs: Set<UUID> = [], existingRound: RoundSessionReferenceV1? = nil) async throws -> ScanToWorkFlowV1 {
        if let existingRound { try existingRound.validate(); guard existingRound.workspaceID == workspaceID else { throw ScanToWorkFailureV1.authorityMismatch } }
        let value = try await resolver.preview(workspaceID: workspaceID, source: source, rawBytes: rawBytes,
                                               selectedAssetIDs: selectedAssetIDs, existingRound: existingRound)
        guard value.workspaceID == workspaceID, value.source == source else { throw ScanToWorkFailureV1.authorityMismatch }
        return try ScanToWorkFlowV1(preview: value)
    }

    /// The preview is deliberately zero-write. Only this explicit method may
    /// delegate a previously constructed canonical RoundSession mutation.
    func start(_ request: ScanToWorkStartRequestV1) async throws -> InstallationScanEntryReceiptV1 {
        try request.flow.validateIntrinsic(); try request.roundMutation.validate()
        guard request.explicitUserConfirmation, request.flow.preview.workspaceID == workspaceID,
              request.flow.preview.outcome == .ready, let asset = request.flow.preview.asset,
              asset.assetRevision > 0, asset.readiness.status == .ready || asset.readiness.status == .warning,
              request.roundMutation.session.items.filter({ $0.selection.assetID == asset.assetID && $0.selection.siteID == asset.siteID && $0.selection.labelAtSelection == asset.label }).count == 1 else { throw ScanToWorkFailureV1.notReady }
        try await resolver.validateStart(binding: asset, policy: request.policy)
        return try roundCoordinator.persistScanToWorkStart(request)
    }

    func repetitiveProjection(_ plan: RepetitiveCapturePlanV1) throws -> RepetitiveCaptureProjectionV1 {
        guard plan.workspaceID == workspaceID else { throw ScanToWorkFailureV1.authorityMismatch }
        return try .init(plan: plan)
    }

    func checkpoint(_ request: RepetitiveCaptureCheckpointRequestV1) throws -> RepetitiveCaptureCheckpointReceiptV1 {
        guard request.plan.workspaceID == workspaceID else { throw ScanToWorkFailureV1.authorityMismatch }
        return try roundCoordinator.persistRepetitiveCaptureCheckpoint(request)
    }
}

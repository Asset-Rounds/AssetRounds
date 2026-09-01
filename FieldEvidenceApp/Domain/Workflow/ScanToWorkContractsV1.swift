import Foundation

enum ScanToWorkFailureV1: Error, Equatable {
    case invalidValue
    case digestMismatch
    case authorityMismatch
    case stale
    case notReady
    case duplicate
    case assetChangedAfterPreview
}

enum ScanToWorkLimitsV1 {
    static let maximumCandidates = 32
    static let maximumSelection = 200
    static let maximumLabelBytes = 256
}

enum ScanToWorkResolutionOutcomeV1: String, Codable, CaseIterable, Hashable, Sendable {
    case ready = "READY"
    case duplicateInSelection = "DUPLICATE_IN_SELECTION"
    case alreadyInRound = "ALREADY_IN_ROUND"
    case ambiguous = "AMBIGUOUS"
    case foreign = "FOREIGN"
    case retiredOrReplaced = "RETIRED_OR_REPLACED"
    case notFound = "NOT_FOUND"
    case notOfflineReady = "NOT_OFFLINE_READY"
    case stale = "STALE"
}

enum ScanToWorkEntrySourceV1: String, Codable, CaseIterable, Hashable, Sendable {
    case scan = "SCAN"
    case manual = "MANUAL"
    case search = "SEARCH"

    var locatorSource: LocatorInputSourceV1 {
        switch self { case .scan: return .camera; case .manual: return .manual; case .search: return .search }
    }
}

enum ScanToWorkPrimaryActionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case startExplicitly = "START_EXPLICITLY"
    case removeDuplicate = "REMOVE_DUPLICATE"
    case openExistingRound = "OPEN_EXISTING_ROUND"
    case chooseCandidate = "CHOOSE_CANDIDATE"
    case switchWorkspace = "SWITCH_WORKSPACE"
    case useReplacement = "USE_REPLACEMENT"
    case manualLookup = "MANUAL_LOOKUP"
    case prepareOffline = "PREPARE_OFFLINE"
    case refresh = "REFRESH"
}

struct ScanToWorkOfflineReadinessProofV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let session: RoundSessionReferenceV1
    let assetID: UUID
    let manifestSHA256: String
    let sourceSnapshotSHA256: String
    let status: OfflineReadinessStatusV1
    let checkedAt: Date
    let proofSHA256: String

    init(manifest: OfflineReadinessManifestV1, assetID: UUID) throws {
        try manifest.validate()
        guard assetID != Self.zero,
              manifest.selectedAssets.contains(where: { $0.assetID == assetID }) else { throw ScanToWorkFailureV1.notReady }
        workspaceID = manifest.session.workspaceID; session = manifest.session; self.assetID = assetID
        manifestSHA256 = manifest.manifestSHA256; sourceSnapshotSHA256 = manifest.sourceSnapshotSHA256
        status = manifest.status; checkedAt = manifest.checkedAt
        guard manifest.mayStartFieldWork else { throw ScanToWorkFailureV1.notReady }
        proofSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(workspaceID: workspaceID, session: session, assetID: assetID, manifestSHA256: manifestSHA256, sourceSnapshotSHA256: sourceSnapshotSHA256, status: status, checkedAt: checkedAt))
    }

    func validate(manifest: OfflineReadinessManifestV1) throws {
        guard self == (try Self(manifest: manifest, assetID: assetID)) else { throw ScanToWorkFailureV1.authorityMismatch }
    }

    func validateIntrinsic() throws {
        try session.validate()
        guard session.workspaceID == workspaceID, assetID != Self.zero,
              KernelCanonicalHashV1.validSHA256(manifestSHA256), KernelCanonicalHashV1.validSHA256(sourceSnapshotSHA256),
              (status == .ready || status == .warning),
              proofSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(workspaceID: workspaceID, session: session, assetID: assetID, manifestSHA256: manifestSHA256, sourceSnapshotSHA256: sourceSnapshotSHA256, status: status, checkedAt: checkedAt))) else { throw ScanToWorkFailureV1.digestMismatch }
    }

    private struct Basis: Codable { let workspaceID: WorkspaceID; let session: RoundSessionReferenceV1; let assetID: UUID; let manifestSHA256: String; let sourceSnapshotSHA256: String; let status: OfflineReadinessStatusV1; let checkedAt: Date }
    private static let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
}

struct ScanToWorkAssetBindingV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let assetID: UUID
    let siteID: UUID
    let label: String
    let assetRevision: UInt64
    let assetSHA256: String
    let locator: AssetLocatorReferenceV1
    let readiness: ScanToWorkOfflineReadinessProofV1
    let qualifiedPose: AssetPoseEventReferenceV1?
    let bindingSHA256: String

    init(workspaceID: WorkspaceID, assetID: UUID, siteID: UUID, label: String,
         assetRevision: UInt64, assetSHA256: String, locator: AssetLocatorReferenceV1,
         readiness: ScanToWorkOfflineReadinessProofV1, qualifiedPose: AssetPoseEventReferenceV1?) throws {
        self.workspaceID = workspaceID; self.assetID = assetID; self.siteID = siteID; self.label = label
        self.assetRevision = assetRevision; self.assetSHA256 = assetSHA256; self.locator = locator
        self.readiness = readiness; self.qualifiedPose = qualifiedPose
        bindingSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(workspaceID: workspaceID, assetID: assetID, siteID: siteID, label: label, assetRevision: assetRevision, assetSHA256: assetSHA256, locator: locator, readiness: readiness, qualifiedPose: qualifiedPose))
        try validateIntrinsic()
    }

    func validateIntrinsic() throws {
        try locator.validate(); try readiness.validateIntrinsic(); try qualifiedPose?.validate()
        guard assetID != Self.zero, siteID != Self.zero, assetRevision > 0,
              !label.isEmpty, label == label.trimmingCharacters(in: .whitespacesAndNewlines), label.utf8.count <= ScanToWorkLimitsV1.maximumLabelBytes,
              KernelCanonicalHashV1.validSHA256(assetSHA256), readiness.workspaceID == workspaceID,
              readiness.assetID == assetID, qualifiedPose.map { $0.workspaceID == workspaceID && $0.assetID == assetID } ?? true,
              bindingSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(workspaceID: workspaceID, assetID: assetID, siteID: siteID, label: label, assetRevision: assetRevision, assetSHA256: assetSHA256, locator: locator, readiness: readiness, qualifiedPose: qualifiedPose))) else { throw ScanToWorkFailureV1.digestMismatch }
    }
    private struct Basis: Codable { let workspaceID: WorkspaceID; let assetID: UUID; let siteID: UUID; let label: String; let assetRevision: UInt64; let assetSHA256: String; let locator: AssetLocatorReferenceV1; let readiness: ScanToWorkOfflineReadinessProofV1; let qualifiedPose: AssetPoseEventReferenceV1? }
    private static let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
}

struct ManualLookupFallbackV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let inputSHA256: String
    let reason: ScanToWorkResolutionOutcomeV1
    let explicitEntryRequired: Bool
    let automaticNetworkLookup: Bool
    let fallbackSHA256: String

    init(workspaceID: WorkspaceID, inputSHA256: String, reason: ScanToWorkResolutionOutcomeV1) throws {
        guard reason != .ready, KernelCanonicalHashV1.validSHA256(inputSHA256) else { throw ScanToWorkFailureV1.invalidValue }
        self.workspaceID = workspaceID; self.inputSHA256 = inputSHA256; self.reason = reason
        explicitEntryRequired = true; automaticNetworkLookup = false
        fallbackSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(workspaceID: workspaceID, inputSHA256: inputSHA256, reason: reason, explicitEntryRequired: true, automaticNetworkLookup: false))
    }
    func validateIntrinsic() throws { guard self == (try Self(workspaceID: workspaceID, inputSHA256: inputSHA256, reason: reason)) else { throw ScanToWorkFailureV1.digestMismatch } }
    private struct Basis: Codable { let workspaceID: WorkspaceID; let inputSHA256: String; let reason: ScanToWorkResolutionOutcomeV1; let explicitEntryRequired: Bool; let automaticNetworkLookup: Bool }
}

struct AssetPreviewStateV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let source: ScanToWorkEntrySourceV1
    let inputSHA256: String
    let resolutionSHA256: String
    let outcome: ScanToWorkResolutionOutcomeV1
    let asset: ScanToWorkAssetBindingV1?
    let candidateLocators: [AssetLocatorReferenceV1]
    let manualFallback: ManualLookupFallbackV1?
    let primaryAction: ScanToWorkPrimaryActionV1
    let evaluatedAt: Date
    let previewSHA256: String

    init(workspaceID: WorkspaceID, source: ScanToWorkEntrySourceV1, inputSHA256: String,
         resolutionSHA256: String, outcome: ScanToWorkResolutionOutcomeV1,
         asset: ScanToWorkAssetBindingV1?, candidateLocators: [AssetLocatorReferenceV1], evaluatedAt: Date) throws {
        self.workspaceID = workspaceID; self.source = source; self.inputSHA256 = inputSHA256
        self.resolutionSHA256 = resolutionSHA256; self.outcome = outcome; self.asset = asset
        self.candidateLocators = candidateLocators
        primaryAction = Self.action(for: outcome)
        manualFallback = outcome == .ready ? nil : try ManualLookupFallbackV1(workspaceID: workspaceID, inputSHA256: inputSHA256, reason: outcome)
        self.evaluatedAt = evaluatedAt
        previewSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(workspaceID: workspaceID, source: source, inputSHA256: inputSHA256, resolutionSHA256: resolutionSHA256, outcome: outcome, asset: asset, candidateLocators: candidateLocators, manualFallback: manualFallback, primaryAction: primaryAction, evaluatedAt: evaluatedAt))
        try validateIntrinsic()
    }

    func validateIntrinsic() throws {
        try asset?.validateIntrinsic(); try manualFallback?.validateIntrinsic(); try candidateLocators.forEach { try $0.validate() }
        guard KernelCanonicalHashV1.validSHA256(inputSHA256), KernelCanonicalHashV1.validSHA256(resolutionSHA256),
              candidateLocators.count <= ScanToWorkLimitsV1.maximumCandidates,
              candidateLocators == candidateLocators.sorted(by: { $0.locatorID.uuidString < $1.locatorID.uuidString }),
              Set(candidateLocators.map(\.locatorID)).count == candidateLocators.count,
              evaluatedAt.timeIntervalSinceReferenceDate.isFinite,
              (outcome == .ready) == (asset != nil), (outcome == .ready) == (manualFallback == nil),
              asset.map { $0.workspaceID == workspaceID } ?? true, primaryAction == Self.action(for: outcome),
              previewSHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(workspaceID: workspaceID, source: source, inputSHA256: inputSHA256, resolutionSHA256: resolutionSHA256, outcome: outcome, asset: asset, candidateLocators: candidateLocators, manualFallback: manualFallback, primaryAction: primaryAction, evaluatedAt: evaluatedAt))) else { throw ScanToWorkFailureV1.digestMismatch }
    }
    private static func action(for value: ScanToWorkResolutionOutcomeV1) -> ScanToWorkPrimaryActionV1 {
        switch value { case .ready: return .startExplicitly; case .duplicateInSelection: return .removeDuplicate; case .alreadyInRound: return .openExistingRound; case .ambiguous: return .chooseCandidate; case .foreign: return .switchWorkspace; case .retiredOrReplaced: return .useReplacement; case .notFound: return .manualLookup; case .notOfflineReady: return .prepareOffline; case .stale: return .refresh }
    }
    private struct Basis: Codable { let workspaceID: WorkspaceID; let source: ScanToWorkEntrySourceV1; let inputSHA256: String; let resolutionSHA256: String; let outcome: ScanToWorkResolutionOutcomeV1; let asset: ScanToWorkAssetBindingV1?; let candidateLocators: [AssetLocatorReferenceV1]; let manualFallback: ManualLookupFallbackV1?; let primaryAction: ScanToWorkPrimaryActionV1; let evaluatedAt: Date }
}

struct ScanToWorkFlowV1: Codable, Equatable, Sendable {
    let preview: AssetPreviewStateV1
    let automaticMutation: Bool
    let explicitStartRequired: Bool
    let flowSHA256: String
    init(preview: AssetPreviewStateV1) throws {
        try preview.validateIntrinsic(); self.preview = preview; automaticMutation = false; explicitStartRequired = true
        flowSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(preview: preview, automaticMutation: false, explicitStartRequired: true))
    }
    func validateIntrinsic() throws { guard self == (try Self(preview: preview)) else { throw ScanToWorkFailureV1.digestMismatch } }
    private struct Basis: Codable { let preview: AssetPreviewStateV1; let automaticMutation: Bool; let explicitStartRequired: Bool }
}

struct BatchScanSelectionV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let previews: [AssetPreviewStateV1]
    let selectionSHA256: String
    init(workspaceID: WorkspaceID, previews: [AssetPreviewStateV1]) throws {
        try previews.forEach { try $0.validateIntrinsic() }
        guard !previews.isEmpty, previews.count <= ScanToWorkLimitsV1.maximumSelection,
              previews.allSatisfy({ $0.workspaceID == workspaceID }),
              previews == previews.sorted(by: { $0.inputSHA256 < $1.inputSHA256 }),
              Set(previews.map(\.inputSHA256)).count == previews.count,
              Set(previews.compactMap { $0.asset?.assetID }).count == previews.compactMap({ $0.asset?.assetID }).count else { throw ScanToWorkFailureV1.duplicate }
        self.workspaceID = workspaceID; self.previews = previews
        selectionSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(workspaceID: workspaceID, previews: previews))
        try validateIntrinsic()
    }
    func validateIntrinsic() throws { guard self == (try Self(workspaceID: workspaceID, previews: previews)) else { throw ScanToWorkFailureV1.digestMismatch } }
    private struct Basis: Codable { let workspaceID: WorkspaceID; let previews: [AssetPreviewStateV1] }
}

struct RepetitiveCapturePlanV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let planID: UUID
    let draftID: UUID
    let draftRevision: UInt64
    let draftSHA256: String
    let round: RoundSessionReferenceV1?
    let selection: BatchScanSelectionV1
    let planSHA256: String
    init(workspaceID: WorkspaceID, planID: UUID, draftID: UUID, draftRevision: UInt64, draftSHA256: String, round: RoundSessionReferenceV1?, selection: BatchScanSelectionV1) throws {
        guard planID != Self.zero, draftID != Self.zero, draftRevision > 0, KernelCanonicalHashV1.validSHA256(draftSHA256), selection.workspaceID == workspaceID, round.map({ $0.workspaceID == workspaceID }) ?? true else { throw ScanToWorkFailureV1.invalidValue }
        try selection.validateIntrinsic(); try round?.validate()
        self.workspaceID = workspaceID; self.planID = planID; self.draftID = draftID; self.draftRevision = draftRevision; self.draftSHA256 = draftSHA256; self.round = round; self.selection = selection
        planSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(workspaceID: workspaceID, planID: planID, draftID: draftID, draftRevision: draftRevision, draftSHA256: draftSHA256, round: round, selection: selection))
    }
    func validateIntrinsic() throws { guard self == (try Self(workspaceID: workspaceID, planID: planID, draftID: draftID, draftRevision: draftRevision, draftSHA256: draftSHA256, round: round, selection: selection)) else { throw ScanToWorkFailureV1.digestMismatch } }
    private struct Basis: Codable { let workspaceID: WorkspaceID; let planID: UUID; let draftID: UUID; let draftRevision: UInt64; let draftSHA256: String; let round: RoundSessionReferenceV1?; let selection: BatchScanSelectionV1 }
    private static let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
}

struct RepetitiveCaptureProjectionV1: Codable, Equatable, Sendable {
    let planSHA256: String
    let readyAssetIDs: [UUID]
    let blockedCount: Int
    let nextAssetID: UUID?
    init(plan: RepetitiveCapturePlanV1) throws {
        try plan.validateIntrinsic(); planSHA256 = plan.planSHA256
        readyAssetIDs = plan.selection.previews.compactMap { $0.outcome == .ready ? $0.asset?.assetID : nil }.sorted(by: { $0.uuidString < $1.uuidString })
        guard Set(readyAssetIDs).count == readyAssetIDs.count else { throw ScanToWorkFailureV1.duplicate }
        blockedCount = plan.selection.previews.count - readyAssetIDs.count; nextAssetID = readyAssetIDs.first
    }
    func validate(plan: RepetitiveCapturePlanV1) throws { guard self == (try Self(plan: plan)) else { throw ScanToWorkFailureV1.digestMismatch } }
}

struct InstallationScanEntryReceiptV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let previewSHA256: String
    let assetID: UUID
    let assetBinding: ScanToWorkAssetBindingV1
    let policy: ScanToWorkStartPolicyV1
    let roundMutationReceipt: RoundSessionMutationReceiptV1
    let receiptSHA256: String
    init(request: ScanToWorkStartRequestV1, roundMutationReceipt: RoundSessionMutationReceiptV1) throws {
        try request.flow.validateIntrinsic(); try request.policy.validateIntrinsic(); try roundMutationReceipt.validate()
        guard roundMutationReceipt.mutation == request.roundMutation,
              request.flow.preview.outcome == .ready, let asset = request.flow.preview.asset,
              roundMutationReceipt.sessionFrontier.workspaceID == asset.workspaceID,
              roundMutationReceipt.mutation.session.items.filter({ $0.selection.assetID == asset.assetID && $0.selection.siteID == asset.siteID && $0.selection.labelAtSelection == asset.label }).count == 1 else { throw ScanToWorkFailureV1.authorityMismatch }
        workspaceID = asset.workspaceID; previewSHA256 = request.flow.preview.previewSHA256; assetID = asset.assetID
        assetBinding = asset; policy = request.policy
        self.roundMutationReceipt = roundMutationReceipt
        receiptSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(workspaceID: workspaceID, previewSHA256: previewSHA256, assetID: assetID, assetBinding: asset, policy: policy, roundMutationReceipt: roundMutationReceipt))
    }
    func validate(request: ScanToWorkStartRequestV1) throws { guard self == (try Self(request: request, roundMutationReceipt: roundMutationReceipt)) else { throw ScanToWorkFailureV1.digestMismatch } }
    private struct Basis: Codable { let workspaceID: WorkspaceID; let previewSHA256: String; let assetID: UUID; let assetBinding: ScanToWorkAssetBindingV1; let policy: ScanToWorkStartPolicyV1; let roundMutationReceipt: RoundSessionMutationReceiptV1 }
}

struct ScanToWorkStartRequestV1: Codable, Equatable, Sendable {
    let flow: ScanToWorkFlowV1
    let policy: ScanToWorkStartPolicyV1
    let roundMutation: RoundSessionMutationV1
    let explicitUserConfirmation: Bool
    init(flow: ScanToWorkFlowV1, policy: ScanToWorkStartPolicyV1, roundMutation: RoundSessionMutationV1, explicitUserConfirmation: Bool) throws {
        try flow.validateIntrinsic(); try policy.validateIntrinsic(); try roundMutation.validate()
        guard explicitUserConfirmation, flow.preview.outcome == .ready,
              flow.preview.workspaceID == roundMutation.workspaceID,
              policy.workspaceID == flow.preview.workspaceID, policy.startAllowed,
              flow.preview.asset.map { asset in
                  roundMutation.session.items.filter { $0.selection.assetID == asset.assetID && $0.selection.siteID == asset.siteID && $0.selection.labelAtSelection == asset.label }.count == 1
              } == true else { throw ScanToWorkFailureV1.notReady }
        self.flow = flow; self.policy = policy; self.roundMutation = roundMutation; self.explicitUserConfirmation = true
    }
}

struct ScanToWorkStartPolicyV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID; let policyID: String; let revision: UInt64
    let policySHA256: String; let startAllowed: Bool; let evaluatedAt: Date; let evaluationSHA256: String
    init(workspaceID: WorkspaceID, policyID: String, revision: UInt64, policySHA256: String, startAllowed: Bool, evaluatedAt: Date) throws {
        guard !policyID.isEmpty, policyID.utf8.count <= 128, revision > 0,
              KernelCanonicalHashV1.validSHA256(policySHA256), evaluatedAt.timeIntervalSinceReferenceDate.isFinite else { throw ScanToWorkFailureV1.invalidValue }
        self.workspaceID = workspaceID; self.policyID = policyID; self.revision = revision; self.policySHA256 = policySHA256
        self.startAllowed = startAllowed; self.evaluatedAt = evaluatedAt
        evaluationSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(workspaceID: workspaceID, policyID: policyID, revision: revision, policySHA256: policySHA256, startAllowed: startAllowed, evaluatedAt: evaluatedAt))
    }
    func validateIntrinsic() throws { guard self == (try Self(workspaceID: workspaceID, policyID: policyID, revision: revision, policySHA256: policySHA256, startAllowed: startAllowed, evaluatedAt: evaluatedAt)) else { throw ScanToWorkFailureV1.digestMismatch } }
    private struct Basis: Codable { let workspaceID: WorkspaceID; let policyID: String; let revision: UInt64; let policySHA256: String; let startAllowed: Bool; let evaluatedAt: Date }
}

struct NextAssetProjectionV1: Codable, Equatable, Sendable {
    let planSHA256: String; let currentAssetID: UUID?; let nextAssetID: UUID?; let remainingCount: Int
    init(plan: RepetitiveCapturePlanV1, currentAssetID: UUID?) throws {
        let projection = try RepetitiveCaptureProjectionV1(plan: plan)
        if let currentAssetID { guard projection.readyAssetIDs.contains(currentAssetID) else { throw ScanToWorkFailureV1.authorityMismatch } }
        let candidates = currentAssetID.flatMap { id in projection.readyAssetIDs.firstIndex(of: id).map { Array(projection.readyAssetIDs.dropFirst($0 + 1)) } } ?? projection.readyAssetIDs
        planSHA256 = plan.planSHA256; self.currentAssetID = currentAssetID; nextAssetID = candidates.first; remainingCount = candidates.count
    }
    func validate(plan: RepetitiveCapturePlanV1) throws { guard self == (try Self(plan: plan, currentAssetID: currentAssetID)) else { throw ScanToWorkFailureV1.digestMismatch } }
}

enum RepetitiveCaptureDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case complete = "COMPLETE"
    case `defer` = "DEFER"
    case keepOpenAndNext = "KEEP_OPEN_AND_NEXT"
}

struct RepetitiveCapturePersistenceOperationV1: Codable, Equatable, Sendable {
    let planSHA256: String; let workspaceID: WorkspaceID; let assetID: UUID
    let disposition: RepetitiveCaptureDispositionV1
    let nextAsset: NextAssetProjectionV1
    let resumeAnchor: DraftResumeAnchorV1
    let roundMutation: RoundSessionMutationV1
    init(plan: RepetitiveCapturePlanV1, assetID: UUID, disposition: RepetitiveCaptureDispositionV1,
         resumeAnchor: DraftResumeAnchorV1, roundMutation: RoundSessionMutationV1) throws {
        try plan.validateIntrinsic(); try resumeAnchor.validate(); try roundMutation.validate()
        let next = try NextAssetProjectionV1(plan: plan, currentAssetID: assetID)
        guard assetID != Self.zero, plan.selection.previews.contains(where: { $0.asset?.assetID == assetID }),
              roundMutation.workspaceID == plan.workspaceID,
              try RepetitiveCaptureRoundSemanticV1.matches(plan: plan, assetID: assetID, disposition: disposition, next: next, resumeAnchor: resumeAnchor, mutation: roundMutation) else { throw ScanToWorkFailureV1.authorityMismatch }
        planSHA256 = plan.planSHA256; workspaceID = plan.workspaceID; self.assetID = assetID
        self.disposition = disposition; nextAsset = next; self.resumeAnchor = resumeAnchor; self.roundMutation = roundMutation
    }
    func validate(plan: RepetitiveCapturePlanV1) throws {
        guard self == (try Self(plan: plan, assetID: assetID, disposition: disposition, resumeAnchor: resumeAnchor, roundMutation: roundMutation)) else { throw ScanToWorkFailureV1.digestMismatch }
    }
    private static let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
}

struct RepetitiveCaptureConfigurationCopyV1: Codable, Equatable, Sendable {
    let sourcePlanSHA256: String; let destinationWorkspaceID: WorkspaceID
    let destinationPlanID: UUID; let copiedConfigurationSHA256: String
    let copiedFactsOrEvidence: Bool; let copySHA256: String
    init(source: RepetitiveCapturePlanV1, destinationWorkspaceID: WorkspaceID,
         destinationPlanID: UUID, copiedConfigurationSHA256: String) throws {
        try source.validateIntrinsic()
        guard destinationPlanID != Self.zero, destinationPlanID != source.planID,
              KernelCanonicalHashV1.validSHA256(copiedConfigurationSHA256) else { throw ScanToWorkFailureV1.invalidValue }
        sourcePlanSHA256 = source.planSHA256; self.destinationWorkspaceID = destinationWorkspaceID
        self.destinationPlanID = destinationPlanID; self.copiedConfigurationSHA256 = copiedConfigurationSHA256
        copiedFactsOrEvidence = false
        copySHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(sourcePlanSHA256: source.planSHA256, destinationWorkspaceID: destinationWorkspaceID, destinationPlanID: destinationPlanID, copiedConfigurationSHA256: copiedConfigurationSHA256, copiedFactsOrEvidence: false))
    }
    func validateIntrinsic() throws {
        guard KernelCanonicalHashV1.validSHA256(sourcePlanSHA256), destinationPlanID != Self.zero,
              KernelCanonicalHashV1.validSHA256(copiedConfigurationSHA256), !copiedFactsOrEvidence,
              copySHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(sourcePlanSHA256: sourcePlanSHA256, destinationWorkspaceID: destinationWorkspaceID, destinationPlanID: destinationPlanID, copiedConfigurationSHA256: copiedConfigurationSHA256, copiedFactsOrEvidence: false))) else { throw ScanToWorkFailureV1.digestMismatch }
    }
    private struct Basis: Codable { let sourcePlanSHA256: String; let destinationWorkspaceID: WorkspaceID; let destinationPlanID: UUID; let copiedConfigurationSHA256: String; let copiedFactsOrEvidence: Bool }
    private static let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
}

enum RepetitiveCaptureRequirementFocusV1: String, Codable, CaseIterable, Hashable, Sendable {
    case facts = "FACTS"; case evidence = "EVIDENCE"; case review = "REVIEW"
}

struct RepetitiveCaptureCheckpointRequestV1: Codable, Equatable, Sendable {
    let plan: RepetitiveCapturePlanV1; let assetID: UUID; let disposition: RepetitiveCaptureDispositionV1
    let nextAsset: NextAssetProjectionV1; let requirementFocus: RepetitiveCaptureRequirementFocusV1
    let resumeAnchor: DraftResumeAnchorV1; let roundMutation: RoundSessionMutationV1
    init(plan: RepetitiveCapturePlanV1, assetID: UUID, disposition: RepetitiveCaptureDispositionV1,
         requirementFocus: RepetitiveCaptureRequirementFocusV1, resumeAnchor: DraftResumeAnchorV1,
         roundMutation: RoundSessionMutationV1) throws {
        try plan.validateIntrinsic(); try resumeAnchor.validate(); try roundMutation.validate()
        let next = try NextAssetProjectionV1(plan: plan, currentAssetID: assetID)
        guard roundMutation.workspaceID == plan.workspaceID,
              try RepetitiveCaptureRoundSemanticV1.matches(plan: plan, assetID: assetID, disposition: disposition, next: next, resumeAnchor: resumeAnchor, mutation: roundMutation) else { throw ScanToWorkFailureV1.authorityMismatch }
        self.plan = plan; self.assetID = assetID; self.disposition = disposition; self.nextAsset = next
        self.requirementFocus = requirementFocus; self.resumeAnchor = resumeAnchor; self.roundMutation = roundMutation
    }
}

private enum RepetitiveCaptureRoundSemanticV1 {
    static func matches(plan: RepetitiveCapturePlanV1, assetID: UUID,
                        disposition: RepetitiveCaptureDispositionV1, next: NextAssetProjectionV1,
                        resumeAnchor: DraftResumeAnchorV1, mutation: RoundSessionMutationV1) throws -> Bool {
        guard let predecessor = plan.round, mutation.expectedRevision == predecessor.revision,
              mutation.session.predecessor == predecessor,
              let item = mutation.session.items.first(where: { $0.selection.assetID == assetID }),
              mutation.session.transitionItemID == item.itemID,
              next.planSHA256 == plan.planSHA256,
              resumeAnchor.selectedStableID == next.nextAssetID?.uuidString.lowercased() else { return false }
        switch disposition {
        case .complete: return mutation.session.transition == .completeItem && item.disposition == .completed
        case .defer: return mutation.session.transition == .deferItem && item.disposition == .deferred
        case .keepOpenAndNext: return mutation.session.transition == .visitItem && item.disposition == .visited
        }
    }
}

struct RepetitiveCaptureCheckpointReceiptV1: Codable, Equatable, Sendable {
    let planSHA256: String; let assetID: UUID; let disposition: RepetitiveCaptureDispositionV1
    let nextAsset: NextAssetProjectionV1; let requirementFocus: RepetitiveCaptureRequirementFocusV1
    let resumeAnchor: DraftResumeAnchorV1; let roundReceipt: RoundSessionMutationReceiptV1; let receiptSHA256: String
    init(request: RepetitiveCaptureCheckpointRequestV1, roundReceipt: RoundSessionMutationReceiptV1) throws {
        try roundReceipt.validate()
        guard roundReceipt.mutation == request.roundMutation else { throw ScanToWorkFailureV1.authorityMismatch }
        planSHA256 = request.plan.planSHA256; assetID = request.assetID; disposition = request.disposition
        nextAsset = request.nextAsset; requirementFocus = request.requirementFocus; resumeAnchor = request.resumeAnchor; self.roundReceipt = roundReceipt
        receiptSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(planSHA256: planSHA256, assetID: assetID, disposition: disposition, nextAsset: nextAsset, requirementFocus: requirementFocus, resumeAnchor: resumeAnchor, roundReceipt: roundReceipt))
    }
    func validate(request: RepetitiveCaptureCheckpointRequestV1) throws { guard self == (try Self(request: request, roundReceipt: roundReceipt)) else { throw ScanToWorkFailureV1.digestMismatch } }
    private struct Basis: Codable { let planSHA256: String; let assetID: UUID; let disposition: RepetitiveCaptureDispositionV1; let nextAsset: NextAssetProjectionV1; let requirementFocus: RepetitiveCaptureRequirementFocusV1; let resumeAnchor: DraftResumeAnchorV1; let roundReceipt: RoundSessionMutationReceiptV1 }
}

/// Capture setup is intentionally unable to encode observations or outcome
/// truth. It carries only nonsemantic device configuration identifiers.
struct RepetitiveCaptureSetupV1: Codable, Equatable, Sendable {
    let captureModeID: String; let lensPreferenceID: String?; let framingGuideID: String?
    let setupSHA256: String
    init(captureModeID: String, lensPreferenceID: String? = nil, framingGuideID: String? = nil) throws {
        let values = [captureModeID, lensPreferenceID, framingGuideID].compactMap { $0 }
        guard !captureModeID.isEmpty, values.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) }) else { throw ScanToWorkFailureV1.invalidValue }
        self.captureModeID = captureModeID; self.lensPreferenceID = lensPreferenceID; self.framingGuideID = framingGuideID
        setupSHA256 = try WorkspaceMutationCanonicalV1.sha256(Basis(captureModeID: captureModeID, lensPreferenceID: lensPreferenceID, framingGuideID: framingGuideID))
    }
    func validateIntrinsic() throws { guard self == (try Self(captureModeID: captureModeID, lensPreferenceID: lensPreferenceID, framingGuideID: framingGuideID)) else { throw ScanToWorkFailureV1.digestMismatch } }
    private struct Basis: Codable { let captureModeID: String; let lensPreferenceID: String?; let framingGuideID: String? }
}

protocol ScanToWorkExactResolvingV1: Sendable {
    func preview(workspaceID: WorkspaceID, source: ScanToWorkEntrySourceV1, rawBytes: Data, selectedAssetIDs: Set<UUID>, existingRound: RoundSessionReferenceV1?) async throws -> AssetPreviewStateV1
    func validateStart(binding: ScanToWorkAssetBindingV1, policy: ScanToWorkStartPolicyV1) async throws
}

extension ScanToWorkExactResolvingV1 {
    /// Existing preview-only test doubles remain source-compatible but fail
    /// closed if they are used as start authority.
    func validateStart(binding: ScanToWorkAssetBindingV1, policy: ScanToWorkStartPolicyV1) async throws {
        throw ScanToWorkFailureV1.assetChangedAfterPreview
    }
}

struct ScanToWorkAuthoritySnapshotV1: Sendable {
    let binding: ScanToWorkAssetBindingV1?
    let disposition: ScanToWorkResolutionOutcomeV1
    let alreadyInRound: Bool
    init(binding: ScanToWorkAssetBindingV1?, disposition: ScanToWorkResolutionOutcomeV1, alreadyInRound: Bool) throws {
        guard [.ready, .notOfflineReady, .stale].contains(disposition),
              (disposition == .ready) == (binding != nil) else { throw ScanToWorkFailureV1.invalidValue }
        try binding?.validateIntrinsic(); self.binding = binding; self.disposition = disposition; self.alreadyInRound = alreadyInRound
    }
}

protocol ScanToWorkAuthorityResolvingV1: Sendable {
    func exactSnapshot(for resolution: LocatorResolutionV1, existingRound: RoundSessionReferenceV1?) async throws -> ScanToWorkAuthoritySnapshotV1
    func validateCurrent(binding: ScanToWorkAssetBindingV1, policy: ScanToWorkStartPolicyV1) async throws
}

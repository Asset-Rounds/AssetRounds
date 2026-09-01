import Foundation

struct ScanToWorkLifecycleAdapterV1: ScanToWorkExactResolvingV1 {
    typealias InputDecoder = @Sendable (ScanToWorkEntrySourceV1, Data) throws -> LocatorResolutionInputV1

    let locatorCoordinator: AssetLocatorCoordinatorV1
    let authority: any ScanToWorkAuthorityResolvingV1
    let decode: InputDecoder
    let now: @Sendable () -> Date

    init(locatorCoordinator: AssetLocatorCoordinatorV1,
         authority: any ScanToWorkAuthorityResolvingV1,
         decode: @escaping InputDecoder,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.locatorCoordinator = locatorCoordinator; self.authority = authority; self.decode = decode; self.now = now
    }

    func preview(workspaceID: WorkspaceID, source: ScanToWorkEntrySourceV1, rawBytes: Data,
                 selectedAssetIDs: Set<UUID>, existingRound: RoundSessionReferenceV1?) async throws -> AssetPreviewStateV1 {
        let input = try decode(source, rawBytes)
        guard input.source == source.locatorSource else { throw ScanToWorkFailureV1.authorityMismatch }
        let evaluatedAt = now()
        guard evaluatedAt.timeIntervalSinceReferenceDate.isFinite else { throw ScanToWorkFailureV1.invalidValue }
        let resolution: LocatorResolutionV1
        switch source {
        case .scan: resolution = try await locatorCoordinator.resolveCamera(input, workspaceID: workspaceID, evaluatedAt: evaluatedAt)
        case .manual: resolution = try await locatorCoordinator.resolveManual(input, workspaceID: workspaceID, evaluatedAt: evaluatedAt)
        case .search: resolution = try await locatorCoordinator.resolveSearch(input, workspaceID: workspaceID, evaluatedAt: evaluatedAt)
        }
        let mapped = map(resolution.outcome)
        var binding: ScanToWorkAssetBindingV1?
        var outcome = mapped
        if mapped == .ready {
            let snapshot = try await authority.exactSnapshot(for: resolution, existingRound: existingRound)
            binding = snapshot.binding; outcome = snapshot.alreadyInRound ? .alreadyInRound : snapshot.disposition
            if let assetID = binding?.assetID, selectedAssetIDs.contains(assetID) { binding = nil; outcome = .duplicateInSelection }
            if outcome != .ready { binding = nil }
        }
        return try AssetPreviewStateV1(workspaceID: workspaceID, source: source,
                                       inputSHA256: resolution.inputSHA256, resolutionSHA256: resolution.resolutionSHA256,
                                       outcome: outcome, asset: binding,
                                       candidateLocators: resolution.candidateLocators.sorted(by: { $0.locatorID.uuidString < $1.locatorID.uuidString }),
                                       evaluatedAt: resolution.evaluatedAt)
    }

    func validateStart(binding: ScanToWorkAssetBindingV1, policy: ScanToWorkStartPolicyV1) async throws {
        try binding.validateIntrinsic(); try policy.validateIntrinsic()
        guard binding.workspaceID == policy.workspaceID, policy.startAllowed else { throw ScanToWorkFailureV1.notReady }
        try await authority.validateCurrent(binding: binding, policy: policy)
    }

    private func map(_ value: LocatorResolutionOutcomeV1) -> ScanToWorkResolutionOutcomeV1 {
        switch value {
        case .matched: return .ready
        case .noMatch, .damagedOrIncomplete: return .notFound
        case .foreignWorkspace: return .foreign
        case .ambiguous: return .ambiguous
        case .retired, .revoked, .replaced: return .retiredOrReplaced
        }
    }

    static let persistenceMode = "DERIVED_JOURNAL_BACKED_V1"
    static let durableModelCount = 0
    static let schemaVersion = 53
    static let activeModelCount = 168
    static let usesLatestFallback = false
    static let scanMutatesCanonicalState = false
}

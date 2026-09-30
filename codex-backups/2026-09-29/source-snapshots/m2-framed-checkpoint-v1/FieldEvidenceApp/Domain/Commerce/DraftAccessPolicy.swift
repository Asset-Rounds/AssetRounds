import Foundation

enum DraftAccessEntryV1: String, Equatable, Sendable {
    case createSign = "create_sign"
    case check
    case work
    case recheck
}

enum DraftAccessLoadingAuthorityV1: Equatable, Sendable {
    /// A still-valid signed active or grace cache remains authoritative.
    case validCachedEntitlement
    /// Purchase history is known, but no signed cache currently grants access.
    case priorPaidWithoutValidCache
    /// No cache exists and no verified paid transaction has ever been seen.
    case neverPaidWithoutCache
}

enum DraftAccessNormalizedStateV1: Equatable, Sendable {
    case loading(DraftAccessLoadingAuthorityV1)
    case entitled
    case neverPaid
    case formerPaidInactive
}

/// A value the owning repository coordinator may construct only after proving
/// the draft exists, belongs to the requested Asset/Issue/stage, predates the
/// gate check, and is a continuation rather than a clone.
struct RepositoryValidatedDraftV1: Equatable, Sendable {
    let draftID: UUID
    let assetID: UUID
    let issueID: UUID?
    let entry: DraftAccessEntryV1
    let createdAt: Date
    let gateCheckedAt: Date

    init?(
        draftID: UUID,
        assetID: UUID,
        issueID: UUID?,
        entry: DraftAccessEntryV1,
        createdAt: Date,
        gateCheckedAt: Date
    ) {
        guard entry != .createSign,
              createdAt.timeIntervalSinceReferenceDate.isFinite,
              gateCheckedAt.timeIntervalSinceReferenceDate.isFinite,
              createdAt < gateCheckedAt else {
            return nil
        }
        switch entry {
        case .check:
            guard issueID == nil else { return nil }
        case .work, .recheck:
            guard issueID != nil else { return nil }
        case .createSign:
            return nil
        }
        self.draftID = draftID
        self.assetID = assetID
        self.issueID = issueID
        self.entry = entry
        self.createdAt = createdAt
        self.gateCheckedAt = gateCheckedAt
    }
}

struct DraftAccessPolicyInputV1: Equatable, Sendable {
    let accessState: DraftAccessNormalizedStateV1
    let liveAssetCount: Int
    let countedStableRootIDs: Set<UUID>
    let requestedEntry: DraftAccessEntryV1
    let existingDraft: RepositoryValidatedDraftV1?

    init(
        accessState: DraftAccessNormalizedStateV1,
        liveAssetCount: Int,
        countedStableRootIDs: Set<UUID>,
        requestedEntry: DraftAccessEntryV1,
        existingDraft: RepositoryValidatedDraftV1? = nil
    ) {
        self.accessState = accessState
        self.liveAssetCount = liveAssetCount
        self.countedStableRootIDs = countedStableRootIDs
        self.requestedEntry = requestedEntry
        self.existingDraft = existingDraft
    }
}

enum DraftAccessDecisionV1: Equatable, Sendable {
    case continueExisting
    case allow
    case blockPaid
    case blockEvaluation
    case waitForStore
    case blockInvalidRequest
}

enum DraftAccessPolicy {
    static let maximumNeverPaidCountedRoots = 3

    static func evaluate(
        _ input: DraftAccessPolicyInputV1
    ) -> DraftAccessDecisionV1 {
        if let existingDraft = input.existingDraft {
            guard existingDraft.entry == input.requestedEntry else {
                return .blockInvalidRequest
            }
            return .continueExisting
        }

        guard input.liveAssetCount >= 0 else {
            return .blockInvalidRequest
        }

        switch input.accessState {
        case .entitled:
            return .allow
        case .formerPaidInactive:
            return .blockPaid
        case .neverPaid:
            return evaluateNeverPaid(input)
        case let .loading(authority):
            switch authority {
            case .validCachedEntitlement:
                return .allow
            case .priorPaidWithoutValidCache:
                return .waitForStore
            case .neverPaidWithoutCache:
                return evaluateNeverPaid(input)
            }
        }
    }

    private static func evaluateNeverPaid(
        _ input: DraftAccessPolicyInputV1
    ) -> DraftAccessDecisionV1 {
        guard input.countedStableRootIDs.count
                < maximumNeverPaidCountedRoots else {
            return .blockEvaluation
        }
        switch input.requestedEntry {
        case .createSign:
            return input.liveAssetCount == 0 ? .allow : .blockEvaluation
        case .check, .work, .recheck:
            return input.liveAssetCount == 1 ? .allow : .blockEvaluation
        }
    }
}

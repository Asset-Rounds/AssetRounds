struct OriginalEraseC16BornSourceObservationV1: Equatable {
    let role: String
    let path: String
    let bytes: Data
    let fullFact: String
    let sha256: String
}

@MainActor final class OriginalEraseC16BoundaryObservationV1 {
    enum Purpose: String { case inspection, bornSource }
    let boundaryID: UUID
    let planSHA256: String
    let stepSHA256: String
    let ordinal: Int
    let purpose: Purpose
    let projection: OriginalEraseC16ExpectedTreeV1
    let bornSource: OriginalEraseC16BornSourceObservationV1?
    fileprivate init(planSHA256: String, stepSHA256: String, ordinal: Int,
        projection: OriginalEraseC16ExpectedTreeV1,
        bornSource: OriginalEraseC16BornSourceObservationV1?) {
        boundaryID = UUID(); self.planSHA256 = planSHA256
        self.stepSHA256 = stepSHA256; self.ordinal = ordinal
        purpose = bornSource == nil ? .inspection : .bornSource
        self.projection = projection; self.bornSource = bornSource
    }
}

struct OriginalEraseC16CurrentPairV1: Equatable {
    let finalURL: URL
    let partialURL: URL
    let bytes: Data
    let expectedDevice: UInt64
    let finalFullFact: String
    let partialFullFact: String
}

struct OriginalEraseC16CurrentZeroV1: Equatable {
    let finalURL: URL
    let temporaryURL: URL
    let expectedDevice: UInt64
    let temporaryFullFact: String
}

struct OriginalEraseC16CurrentPrefixV1: Equatable {
    let finalURL: URL
    let temporaryURL: URL
    let expectedBytes: Data
    let observedBytes: Data
    let expectedDevice: UInt64
    let temporaryFullFact: String
}

enum OriginalEraseC16CurrentPathRoleV1: Equatable {
    case ordinary
    case pair(OriginalEraseC16CurrentPairV1)
    case unacceptedEmptyPublication(OriginalEraseC16CurrentZeroV1)
    case publicationPrefix(OriginalEraseC16CurrentPrefixV1)
}

/// Observation-only capability. Only the Ledger's actual fixed publication
/// role may issue it; there is no raw link-count exemption or success flag.
@MainActor final class OriginalEraseC16CurrentObservationScopeV1 {
    let operationID: UUID
    let planSHA256: String
    let ordinal: Int
    private let roles: [String: OriginalEraseC16CurrentPathRoleV1]
    private let requireBinding: @MainActor () throws -> Void
    private let poison: @MainActor () -> Void
    private var retainedAttempts: [OriginalEraseC16CurrentTemporalObservationAttemptV1] = []
    fileprivate init(operationID: UUID, planSHA256: String, ordinal: Int,
        roles: [String: OriginalEraseC16CurrentPathRoleV1],
        requireBinding: @escaping @MainActor () throws -> Void,
        poison: @escaping @MainActor () -> Void) {
        self.operationID = operationID; self.planSHA256 = planSHA256
        self.ordinal = ordinal; self.roles = roles
        self.requireBinding = requireBinding; self.poison = poison
    }
    func requireCurrentBinding() throws { try requireBinding() }
    func requirePair(finalURL: URL, partialURL: URL) throws -> OriginalEraseC16CurrentPairV1 {
        try requireCurrentBinding()
        for role in roles.values {
            if case let .pair(pair) = role,
               pair.finalURL.standardizedFileURL == finalURL.standardizedFileURL,
               pair.partialURL.standardizedFileURL == partialURL.standardizedFileURL {
                try requireCurrentBinding(); return pair
            }
        }
        throw ScratchDataLeaseStoreFailureV1.leaseCollision
    }
    /// Factory visits both exceptional paths in the complete closed tree.
    /// All unassigned paths retain the ordinary strict predicates.
    func roleFor(path: String, fullFact: String, sha256: String) throws -> OriginalEraseC16CurrentPathRoleV1 {
        try requireCurrentBinding()
        guard let role = roles[path] else { return .ordinary }
        switch role {
        case .ordinary: return .ordinary
        case let .pair(pair):
            guard fullFact == pair.finalFullFact || fullFact == pair.partialFullFact,
                  try CompatibilityCanonicalV1.sha256(pair.bytes) == sha256 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        case let .unacceptedEmptyPublication(zero):
            guard fullFact == zero.temporaryFullFact,
                  try CompatibilityCanonicalV1.sha256(Data()) == sha256 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        case let .publicationPrefix(prefix):
            guard fullFact == prefix.temporaryFullFact,
                  prefix.expectedBytes.starts(with: prefix.observedBytes),
                  try CompatibilityCanonicalV1.sha256(prefix.observedBytes) == sha256 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        }
        try requireCurrentBinding(); return role
    }
    func retainObservationAttempt(_ attempt: OriginalEraseC16CurrentTemporalObservationAttemptV1) {
        retainedAttempts.append(attempt)
    }
    func poisonOnUncertainObservation() { poison() }
}

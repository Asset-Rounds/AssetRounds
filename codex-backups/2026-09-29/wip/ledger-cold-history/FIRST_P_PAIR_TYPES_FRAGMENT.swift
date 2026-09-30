struct OriginalEraseC16FirstPPairV1: Equatable {
    let finalURL: URL
    let partialURL: URL
    let finalOriginalFact: String
    let partialOriginalFact: String
    let expectedSHA256: String
    let expectedByteCount: Int64
    let expectedDevice: UInt64
    let finalFullFact: String
    let partialFullFact: String
    let assignedSettlementOrdinal: Int
    let planSHA256: String
    let currentOrdinal: Int
}

@MainActor final class OriginalEraseC16FirstPObservationScopeV1 {
    let operationID: UUID
    let planSHA256: String
    let currentOrdinal: Int
    private let pairs: [OriginalEraseC16FirstPPairV1]
    private let requireBinding: @MainActor () throws -> Void
    private let poison: @MainActor () -> Void
    private var retainedAttempts: [OriginalEraseC16CurrentTemporalObservationAttemptV1] = []
    fileprivate init(operationID: UUID, planSHA256: String, currentOrdinal: Int,
        pairs: [OriginalEraseC16FirstPPairV1],
        requireBinding: @escaping @MainActor () throws -> Void,
        poison: @escaping @MainActor () -> Void) {
        self.operationID = operationID; self.planSHA256 = planSHA256
        self.currentOrdinal = currentOrdinal; self.pairs = pairs
        self.requireBinding = requireBinding; self.poison = poison
    }
    func requireCurrentBinding() throws { try requireBinding() }
    func requirePair(finalURL: URL, partialURL: URL) throws -> OriginalEraseC16FirstPPairV1 {
        try requireCurrentBinding()
        guard let pair = pairs.first(where: { $0.finalURL == finalURL && $0.partialURL == partialURL }) else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try requireCurrentBinding(); return pair
    }
    func roleFor(path: String, fullFact: String, sha256: String) throws -> OriginalEraseC16FirstPPairV1? {
        try requireCurrentBinding()
        guard let pair = pairs.first(where: {
            let suffix = "/Operations/" + path
            return $0.finalURL.path.hasSuffix(suffix) || $0.partialURL.path.hasSuffix(suffix)
        }) else { return nil }
        guard fullFact == pair.finalFullFact || fullFact == pair.partialFullFact,
              sha256 == pair.expectedSHA256 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        try requireCurrentBinding(); return pair
    }
    func retainObservationAttempt(_ attempt: OriginalEraseC16CurrentTemporalObservationAttemptV1) {
        retainedAttempts.append(attempt)
    }
    func poisonOnUncertainObservation() { poison() }
}

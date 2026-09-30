    private struct OriginalEraseC16ScopedPairPolicyV1 {
        let pair: OriginalEraseC16CurrentPairV1
        let observations: [TemporalPolicyObservationV1]
    }
    private var originalEraseC16ScopedPairPolicies: [String: OriginalEraseC16ScopedPairPolicyV1] = [:]
    @MainActor private var originalEraseC16ObservationScope: OriginalEraseC16CurrentObservationScopeV1?
    @MainActor private static var retainedFailedC16ObservationScopes: [OriginalEraseC16CurrentObservationScopeV1] = []

    @MainActor
    func originalEraseC16CurrentObservationScope(
        plan: OriginalEraseC16PlanV1, currentOrdinal: Int,
        controlMarkerState: OriginalEraseC16ControlMarkerStateV1?,
        ingressMarkerState: OriginalEraseC16IngressMarkerStateV1?
    ) throws -> OriginalEraseC16CurrentObservationScopeV1 {
        try requireScratchDescriptorAccess()
        guard let permit = originalEraseColdPermit, let operationID = originalEraseOperationID,
              originalEraseC16ReferencePlan == plan,
              currentOrdinal >= 0, currentOrdinal < plan.steps.count else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try permit.requireObservationBinding()
        try originalEraseBorrowedLocalLineageCheck()
        originalEraseC16ScopedPairPolicies.removeAll()
        var candidates = try originalEraseC16CanonicalRoles(plan: plan, through: currentOrdinal)
        if currentOrdinal > 0 {
            let earlier = try originalEraseC16CanonicalRoles(plan: plan, through: currentOrdinal - 1)
            candidates = candidates.filter { earlier[$0.key]?.bytes != $0.value.bytes }
        }
        if let marker = try originalEraseC16MaterializedControlRole(plan: plan, ordinal: currentOrdinal) {
            candidates[Self.controlEraseName] = marker
        }
        var roles: [String: OriginalEraseC16CurrentPathRoleV1] = [:]
        var pairs: [OriginalEraseC16CurrentPairV1] = []
        if try hasExistingIngressControl() {
            let parent = try ingressControlDescriptor(), directory = try protectedIngressReceiptDirectory()
            var parentFact = stat()
            guard Darwin.fstat(parent, &parentFact) == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            let expectedGroup = parentFact.st_mode & S_ISGID == 0 ? Darwin.getegid() : parentFact.st_gid
            var exceptionalRoleCount = 0
            for (name, candidate) in candidates.sorted(by: { $0.key < $1.key }) {
                let temporary = try Self.originalErasePublicationTemporaryName(operationID: operationID, finalName: name, leaseName: nil)
                guard let temp = try readOriginalErasePublicationLeaf(named: temporary, parent: parent,
                    maximumBytes: candidate.bytes.count) else { continue }
                exceptionalRoleCount += 1
                let final = try readOriginalErasePublicationLeaf(named: name, parent: parent, maximumBytes: candidate.bytes.count)
                let finalURL = directory.appendingPathComponent(name), tempURL = directory.appendingPathComponent(temporary)
                guard temp.0.st_uid == Darwin.geteuid(), temp.0.st_gid == expectedGroup,
                      temp.0.st_mode & 0o7777 == 0o600,
                      UInt64(temp.0.st_dev) == authority.rootDevice else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                if let final {
                    guard name != Self.controlEraseName, final.1 == candidate.bytes, temp.1 == candidate.bytes,
                          final.0.st_nlink == 2, temp.0.st_nlink == 2,
                          Self.originalEraseSourceFullFact(final.0) == Self.originalEraseSourceFullFact(temp.0) else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                    let pair = OriginalEraseC16CurrentPairV1(finalURL: finalURL, partialURL: tempURL,
                        bytes: candidate.bytes, expectedDevice: authority.rootDevice,
                        finalFullFact: Self.originalEraseSourceFullFact(final.0), partialFullFact: Self.originalEraseSourceFullFact(temp.0))
                    roles["ProtectedIngressReceiptsV1/" + name] = .pair(pair)
                    roles["ProtectedIngressReceiptsV1/" + temporary] = .pair(pair); pairs.append(pair)
                } else {
                    guard temp.0.st_nlink == 1, candidate.bytes.starts(with: temp.1) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    if temp.1.isEmpty {
                        roles["ProtectedIngressReceiptsV1/" + temporary] = .unacceptedEmptyPublication(.init(
                            finalURL: finalURL, temporaryURL: tempURL, expectedDevice: authority.rootDevice,
                            temporaryFullFact: Self.originalEraseSourceFullFact(temp.0)))
                    } else {
                        roles["ProtectedIngressReceiptsV1/" + temporary] = .publicationPrefix(.init(
                            finalURL: finalURL, temporaryURL: tempURL, expectedBytes: candidate.bytes, observedBytes: temp.1,
                            expectedDevice: authority.rootDevice, temporaryFullFact: Self.originalEraseSourceFullFact(temp.0)))
                    }
                }
            }
            guard exceptionalRoleCount <= 1 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        }
        let scope = OriginalEraseC16CurrentObservationScopeV1(operationID: operationID,
            planSHA256: try CompatibilityCanonicalV1.sha256(CompatibilityCanonicalV1.encode(plan)), ordinal: currentOrdinal,
            roles: roles, requireBinding: { [self] in
                try requireScratchDescriptorAccess()
                try permit.requireObservationBinding()
                try originalEraseBorrowedLocalLineageCheck()
            }, poison: { [self] in
                originalEraseBorrowedLifetime = .uncertain
                permit.poisonOnUncertainEffect()
                if let scope = originalEraseC16ObservationScope {
                    Self.retainedFailedC16ObservationScopes.append(scope)
                }
            })
        originalEraseC16ObservationScope = scope
        for pair in pairs {
            let observed = try ProtectedFilePolicyV1.observeEraseC16CurrentTemporalPairWithCheckedClose(
                finalURL: pair.finalURL, partialURL: pair.partialURL, scope: scope,
                retainUncertainDescriptor: { _ = ScratchUncertainCloseQuarantineV1.shared.begin($0) })
            originalEraseC16ScopedPairPolicies[pair.finalURL.path] = .init(pair: pair, observations: observed)
            originalEraseC16ScopedPairPolicies[pair.partialURL.path] = .init(pair: pair, observations: observed)
        }
        try scope.requireCurrentBinding()
        return scope
    }

    /// A policy observation is local data for one synchronous engine boundary,
    /// never cached authorization. The actor controller reobserves the pair
    /// before/after every advance; primitives recheck exact full facts/bytes
    /// under the held local lineage before consuming that observed data.
    private func originalEraseC16VerifyScopedPairPolicy(at url: URL) throws -> Bool {
        try requireScratchDescriptorAccess()
        guard let observed = originalEraseC16ScopedPairPolicies[url.path] else { return false }
        try originalEraseBorrowedExclusiveCheck?()
        let pair = observed.pair
        guard !observed.observations.isEmpty,
              let parent = ingressControlAuthority?.rootDescriptor,
              let first = try readOriginalErasePublicationLeaf(named: pair.finalURL.lastPathComponent,
                parent: parent, maximumBytes: pair.bytes.count),
              let second = try readOriginalErasePublicationLeaf(named: pair.partialURL.lastPathComponent,
                parent: parent, maximumBytes: pair.bytes.count),
              Self.originalEraseSourceFullFact(first.0) == pair.finalFullFact,
              Self.originalEraseSourceFullFact(second.0) == pair.partialFullFact,
              first.0.st_nlink == 2, second.0.st_nlink == 2,
              first.1 == pair.bytes, second.1 == pair.bytes else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try originalEraseBorrowedExclusiveCheck?(); return true
    }

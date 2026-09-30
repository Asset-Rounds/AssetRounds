    private struct OriginalEraseC16FirstPPairPolicyV1 {
        let pair: OriginalEraseC16FirstPPairV1
        let observations: [TemporalPolicyObservationV1]
    }
    private var originalEraseC16FirstPPairPolicies: [String: OriginalEraseC16FirstPPairPolicyV1] = [:]
    @MainActor private var originalEraseC16FirstPPairScope: OriginalEraseC16FirstPObservationScopeV1?
    @MainActor private static var retainedFailedC16FirstPScopes: [OriginalEraseC16FirstPObservationScopeV1] = []

    @MainActor private func originalEraseC16IssueFirstPPairs(
        plan: OriginalEraseC16PlanV1, currentOrdinal: Int,
        planSHA256: String, recordBinding: String
    ) throws -> [String: OriginalEraseC16CurrentPathRoleV1] {
        try requireScratchDescriptorAccess()
        guard let permit = originalEraseColdPermit, let operationID = originalEraseOperationID else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        originalEraseC16FirstPPairPolicies.removeAll()
        var pairs: [OriginalEraseC16FirstPPairV1] = []
        for (assigned, step) in plan.steps.enumerated() where assigned >= currentOrdinal {
            guard case let .settleFirstPPartial(location, name, device, inode, byteCount) = step else { continue }
            let prefix: String, parentURL: URL, parent: Int32, needsClose: Bool
            switch location {
            case .control:
                prefix = "ProtectedIngressReceiptsV1/"; parentURL = try protectedIngressReceiptDirectory()
                parent = try ingressControlDescriptor(); needsClose = false
            case let .lease(lease):
                prefix = "ScratchDataV1/" + lease + "/"; parentURL = rootURL.appendingPathComponent(lease)
                parent = try openLeaseDirectory(lease); needsClose = true
            }
            let inspect = { (parent: Int32) throws -> OriginalEraseC16FirstPPairV1? in
                var partial = stat()
                if Darwin.fstatat(parent, name, &partial, AT_SYMLINK_NOFOLLOW) != 0 {
                    guard errno == ENOENT else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }; return nil
                }
                guard partial.st_mode & S_IFMT == S_IFREG,
                      UInt64(partial.st_dev) == device, UInt64(partial.st_ino) == inode,
                      Int64(partial.st_size) == byteCount else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                guard partial.st_nlink == 2 else { return nil }
                guard let original = self.originalEraseC16FirstPFacts[prefix + name],
                      Self.originalEraseC16NineFieldFact(partial) == original else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                let aliasPaths = self.originalEraseC16FirstPFacts.filter {
                    $0.key.hasPrefix(prefix) && !$0.key.dropFirst(prefix.count).contains("/")
                        && $0.key != prefix + name && $0.value == original
                }.map(\.key)
                guard aliasPaths.count == 1, let finalPath = aliasPaths.first,
                      !finalPath.dropFirst(prefix.count).hasPrefix(".partial-") else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                let finalName = String(finalPath.dropFirst(prefix.count))
                var final = stat(), parentFact = stat()
                guard Darwin.fstatat(parent, finalName, &final, AT_SYMLINK_NOFOLLOW) == 0,
                      Darwin.fstat(parent, &parentFact) == 0,
                      Self.originalEraseC16NineFieldFact(final) == original,
                      Self.originalEraseSourceFullFact(final) == Self.originalEraseSourceFullFact(partial) else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                let group = parentFact.st_mode & S_ISGID == 0 ? Darwin.getegid() : parentFact.st_gid
                guard partial.st_uid == Darwin.geteuid(), partial.st_gid == group,
                      partial.st_mode & 0o7777 == 0o600,
                      byteCount >= 0, byteCount <= 1_024 * 1_024 * 1_024 else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                return .init(finalURL: parentURL.appendingPathComponent(finalName),
                    partialURL: parentURL.appendingPathComponent(name), finalOriginalFact: original,
                    partialOriginalFact: original, expectedSHA256: "", expectedByteCount: byteCount,
                    expectedDevice: device, finalFullFact: Self.originalEraseSourceFullFact(final),
                    partialFullFact: Self.originalEraseSourceFullFact(partial), assignedSettlementOrdinal: assigned,
                    planSHA256: planSHA256, currentOrdinal: currentOrdinal)
            }
            let pair = needsClose ? try withObservedScratchDescriptor(parent, inspect) : try inspect(parent)
            if let pair {
                let finalPath = prefix + pair.finalURL.lastPathComponent
                let partialPath = prefix + name
                let finalSHA = try permit.originalPPhysicalSHA256(path: finalPath)
                let partialSHA = try permit.originalPPhysicalSHA256(path: partialPath)
                guard finalSHA == partialSHA, CompatibilityCanonicalV1.validSHA256(finalSHA) else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                pairs.append(.init(finalURL: pair.finalURL, partialURL: pair.partialURL,
                    finalOriginalFact: pair.finalOriginalFact, partialOriginalFact: pair.partialOriginalFact,
                    expectedSHA256: finalSHA, expectedByteCount: pair.expectedByteCount, expectedDevice: pair.expectedDevice,
                    finalFullFact: pair.finalFullFact, partialFullFact: pair.partialFullFact,
                    assignedSettlementOrdinal: assigned, planSHA256: planSHA256, currentOrdinal: currentOrdinal))
            }
        }
        let scope = OriginalEraseC16FirstPObservationScopeV1(operationID: operationID,
            planSHA256: planSHA256, currentOrdinal: currentOrdinal, pairs: pairs,
            requireBinding: { [self] in
                try requireScratchDescriptorAccess()
                guard try permit.requireC16ObservationBinding(planSHA256: planSHA256, ordinal: currentOrdinal) == recordBinding else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                try originalEraseBorrowedLocalLineageCheck()
            }, poison: { [self] in
                originalEraseBorrowedLifetime = .uncertain; permit.poisonOnUncertainEffect()
                if let scope = originalEraseC16FirstPPairScope { Self.retainedFailedC16FirstPScopes.append(scope) }
            })
        originalEraseC16FirstPPairScope = scope
        var roles: [String: OriginalEraseC16CurrentPathRoleV1] = [:]
        for pair in pairs {
            let observations = try ProtectedFilePolicyV1.observeEraseC16FirstPTemporalPairWithCheckedClose(
                finalURL: pair.finalURL, partialURL: pair.partialURL, scope: scope,
                retainUncertainDescriptor: { _ = ScratchUncertainCloseQuarantineV1.shared.begin($0) })
            let value = OriginalEraseC16FirstPPairPolicyV1(pair: pair, observations: observations)
            for url in [pair.finalURL, pair.partialURL] {
                originalEraseC16FirstPPairPolicies[url.path] = value
                guard let range = url.path.range(of: "/Operations/", options: .backwards) else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                roles[String(url.path[range.upperBound...])] = .firstPPair(pair)
            }
        }
        try scope.requireCurrentBinding(); return roles
    }

    private func originalEraseC16VerifyFirstPPairPolicy(at url: URL) throws -> Bool {
        try requireScratchDescriptorAccess()
        guard let value = originalEraseC16FirstPPairPolicies[url.path] else { return false }
        guard !value.observations.isEmpty else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        try originalEraseBorrowedExclusiveCheck?()
        var final = stat(), partial = stat()
        guard Darwin.lstat(value.pair.finalURL.path, &final) == 0,
              Darwin.lstat(value.pair.partialURL.path, &partial) == 0,
              Self.originalEraseSourceFullFact(final) == value.pair.finalFullFact,
              Self.originalEraseSourceFullFact(partial) == value.pair.partialFullFact,
              final.st_nlink == 2, partial.st_nlink == 2 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        try originalEraseBorrowedExclusiveCheck?(); return true
    }

from pathlib import Path
import hashlib,json
q=Path('.codex-temp/cold-ledger-continuation-successor-v1');p=q/'candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift';b=p.read_bytes();before='2c065a08e4c0214a6eb0fe39e28c564303c6783f0ddf8857fe688366eb9e640d';assert hashlib.sha256(b).hexdigest()==before;s=b.decode()
def once(a,b):
 global s
 assert s.count(a)==1,(s.count(a),a[:100]);s=s.replace(a,b)
once('''            if originalEraseBorrowedExclusiveCheck != nil,
               (try originalEraseC16VerifyScopedPairPolicy(at: url)''','''            if originalEraseBorrowedExclusiveCheck != nil,
               (try originalEraseVerifyGenericPolicy(at: url)
                || originalEraseC16VerifyScopedPairPolicy(at: url)''')
anchor='''    private var originalEraseBorrowedAdmitting = false
'''
helper='''    private struct OriginalEraseGenericPairPolicyV1 {
        let pair: OriginalEraseSealedOwnedGenericAliasPairV1
        let observations: [TemporalPolicyObservationV1]
    }
    // Policy data is scoped to one synchronous boundary. The real provider
    // and immutable row are freshly rechecked; these values grant no effect.
    private var originalEraseGenericPairPolicies: [String: OriginalEraseGenericPairPolicyV1] = [:]
    private var originalEraseGenericOriginalFacts: [String: String] = [:]
    // Populated only after a held/named directory identity proof. The exact
    // close attempt is removed before its numeric descriptor can be reused.
    private var originalEraseObservedDirectoryPaths: [Int32: URL] = [:]

    private func originalEraseGenericOriginalAllowsPair(path: String) throws -> Bool {
        try requireScratchDescriptorAccess()
        guard let rowFact = originalEraseGenericOriginalFacts[path],
              originalEraseC16FirstPFacts[path] == rowFact else { return false }
        return try OriginalEraseC16PhysicalFactV1(rowFact).linkCount == 2
    }

    private func originalEraseVerifyGenericPolicy(
        at url: URL, information supplied: stat? = nil
    ) throws -> Bool {
        try requireScratchDescriptorAccess()
        guard originalEraseBorrowedLifetime == .active else { return false }
        guard Thread.isMainThread, let provider = originalEraseGenericScopeProvider,
              let operationID = originalEraseOperationID else {
            originalEraseBorrowedLifetime = .uncertain
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        return try MainActor.assumeIsolated {
            guard let scope = try provider() else { return false }
            do {
                try scope.requireCurrentBinding()
                guard scope.operationID == operationID else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                let operations = rootURL.deletingLastPathComponent().standardizedFileURL
                let pathPrefix = operations.path + "/"
                guard url == url.standardizedFileURL, url.path.hasPrefix(pathPrefix) else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                let path = String(url.path.dropFirst(pathPrefix.count))
                let parts = path.split(separator: "/", omittingEmptySubsequences: false)
                guard parts.count == 3, parts[0] == "ScratchDataV1" else { return false }
                var information = supplied ?? stat()
                if supplied == nil {
                    try scope.requireCurrentBinding()
                    guard Darwin.lstat(url.path, &information) == 0 else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                    try scope.requireCurrentBinding()
                }
                guard information.st_mode & S_IFMT == S_IFREG else { return false }
                @MainActor func firstPFact(_ source: String) throws -> String? {
                    if let permit = originalEraseColdPermit { return try permit.originalPPhysicalFact(path: source) }
                    guard let permit = originalEraseC16BootstrapPermit else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    return try permit.originalPPhysicalFact(path: source)
                }
                @MainActor func firstPSHA(_ source: String) throws -> String {
                    if let permit = originalEraseColdPermit { return try permit.originalPPhysicalSHA256(path: source) }
                    guard let permit = originalEraseC16BootstrapPermit else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    return try permit.originalPPhysicalSHA256(path: source)
                }
                var sourcePath: String?
                if try firstPFact(path) != nil { sourcePath = path }
                if sourcePath == nil, String(parts[1]).hasPrefix(Self.deletionPrefix) {
                    let originalParent = String(parts[1].dropFirst(Self.deletionPrefix.count))
                    let candidate = "ScratchDataV1/" + originalParent + "/" + String(parts[2])
                    if try firstPFact(candidate) != nil { sourcePath = candidate }
                }
                let sha = try sourcePath.map { try firstPSHA($0) } ?? ""
                let fact = Self.originalEraseSourceFullFact(information)
                let role = try scope.roleFor(path: path, fullFact: fact, sha256: sha)
                switch role {
                case .ordinary: return false
                case .observedOwnedGenericAliases(let pair):
                    guard information.st_nlink == 2,
                          pair.members.contains(where: { $0.url == url && $0.fullFact == fact }),
                          pair.sha256 == sha else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    let value: OriginalEraseGenericPairPolicyV1
                    if let prior = originalEraseGenericPairPolicies[url.path], prior.pair == pair,
                       !prior.observations.isEmpty { value = prior }
                    else {
                        let observed = try ProtectedFilePolicyV1.observeEraseObservedOwnedGenericAliasTemporalPairWithCheckedClose(
                            aliasURLs: pair.members.map(\\.url), scope: scope,
                            retainUncertainDescriptor: { _ = ScratchUncertainCloseQuarantineV1.shared.begin($0) })
                        guard observed.count == 2 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                        value = .init(pair: pair, observations: observed)
                    }
                    for member in pair.members { originalEraseGenericPairPolicies[member.url.path] = value }
                    for member in pair.original.members { originalEraseGenericOriginalFacts[member.operationsRelativePath] = member.observedFact }
                case .ownedGenericSingleSurvivor(let survivor):
                    guard information.st_nlink == 1,
                          survivor.member.url == url, survivor.member.fullFact == fact,
                          survivor.sha256 == sha else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    // A retained original pair never widens the single-link
                    // private policy. Actual consumed-member progress supplies
                    // lineage; ordinary strict policy still checks this leaf.
                    try ProtectedFilePolicyV1.verifyEraseColdPrivateWithCheckedClose(.temporaryFile, at: url,
                        retainUncertainDescriptor: { _ = ScratchUncertainCloseQuarantineV1.shared.begin($0) })
                    for member in survivor.original.members { originalEraseGenericOriginalFacts[member.operationsRelativePath] = member.observedFact }
                }
                try scope.requireCurrentBinding()
                guard let after = try provider(), after.operationID == operationID,
                      after.originBinding == scope.originBinding,
                      after.accountingSHA256 == scope.accountingSHA256,
                      try after.roleFor(path: path, fullFact: fact, sha256: sha) == role else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                try after.requireCurrentBinding()
                return true
            } catch {
                originalEraseBorrowedLifetime = .uncertain
                scope.poisonOnUncertainObservation()
                originalEraseColdPermit?.poisonOnUncertainEffect()
                originalEraseC16BootstrapPermit?.poisonOnUncertainEffect()
                throw error
            }
        }
    }

'''
once(anchor,helper+anchor)
once('''        originalEraseC16ScopedPairPolicies.removeAll()
        var candidates''','''        originalEraseC16ScopedPairPolicies.removeAll()
        originalEraseGenericPairPolicies.removeAll()
        var candidates''')
# Positive generic DATA classification precedes canonical pair issuance. It
# does not issue a generic C16 ordinal or select an alias by suffix.
old='''                guard partial.st_nlink == 2 else { return nil }
'''
new='''                guard partial.st_nlink == 2 else { return nil }
                if try self.originalEraseVerifyGenericPolicy(at: parentURL.appendingPathComponent(name),
                    information: partial) { return nil }
'''
assert s.count(old)==2;s=s.replace(old,new)
once('''                let paired = try originalEraseC16ReferencePlan.map {
''','''                let genericPair = try originalEraseGenericOriginalAllowsPair(path: path + "/" + file.name)
                let paired = try originalEraseC16ReferencePlan.map {
''')
once('''                guard fact.matches(file, allowPair: paired) else''','''                guard fact.matches(file, allowPair: paired || genericPair) else''')
# Expected first-P link transition is qualified by authenticated row data
# already positively reobserved under this actual current scope/cut.
once('''                        allowOneLinkSettlement: try originalEraseC16FirstPAllowsOneLinkSettlement(
                            path: firstPPath + "/" + file.name, plan: plan))))''','''                        allowOneLinkSettlement: try originalEraseC16FirstPAllowsOneLinkSettlement(
                            path: firstPPath + "/" + file.name, plan: plan)
                            || originalEraseGenericOriginalAllowsPair(path: firstPPath + "/" + file.name))))''')
# Track paths only after the existing held/named directory identity proof.
once('''        return descriptor
    }

    private func verifyLeaseDirectory(''','''        if originalEraseBorrowedLifetime == .active {
            originalEraseObservedDirectoryPaths[descriptor] = rootURL.appendingPathComponent(name).standardizedFileURL
        }
        return descriptor
    }

    private func verifyLeaseDirectory(''')
once('''        linked.st_ino == pinned.st_ino else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
    }

    private func directoryNames(''','''        linked.st_ino == pinned.st_ino else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        if originalEraseBorrowedLifetime == .active {
            guard originalEraseObservedCloseAttempts[descriptor] != nil else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            originalEraseObservedDirectoryPaths[descriptor] = rootURL.appendingPathComponent(name).standardizedFileURL
        }
    }

    private func directoryNames(''')
once('''            originalEraseObservedCloseAttempts.removeValue(forKey: descriptor)
            guard Darwin.close(descriptor)''','''            originalEraseObservedCloseAttempts.removeValue(forKey: descriptor)
            originalEraseObservedDirectoryPaths.removeValue(forKey: descriptor)
            guard Darwin.close(descriptor)''')
once('''        if information.st_nlink == 2, originalEraseBorrowedExclusiveCheck != nil {
            for (path, value) in originalEraseC16InitialPairPolicies''','''        if originalEraseBorrowedLifetime == .active,
           let directory = originalEraseObservedDirectoryPaths[directoryDescriptor],
           originalEraseObservedCloseAttempts[directoryDescriptor] != nil,
           try originalEraseVerifyGenericPolicy(at: directory.appendingPathComponent(name), information: information) {
            return information
        }
        if information.st_nlink == 2, originalEraseBorrowedExclusiveCheck != nil {
            for (path, value) in originalEraseC16InitialPairPolicies''')
# Exact already-authenticated generic DATA is excluded from semantic C16
# settlement. Router must perform same complete classification before its
# initial role-list equality; this code alone cannot fabricate that issuer.
once('''        var steps = firstPPartials
        var owned''','''        var steps = firstPPartials.filter { step in
            guard case let .settleFirstPPartial(.lease(lease), name, _, _, _) = step else { return true }
            return originalEraseGenericOriginalFacts["ScratchDataV1/" + lease + "/" + name] == nil
        }
        var owned''')
# Lexical state clearing always follows the permanent lifetime latch.
old='''                store.originalEraseGenericScopeProvider = nil
''';new=old+'''                store.originalEraseGenericPairPolicies.removeAll()
                store.originalEraseGenericOriginalFacts.removeAll()
                store.originalEraseObservedDirectoryPaths.removeAll()
''';assert s.count(old)==2;s=s.replace(old,new)
p.write_text(s)
r={'model':'gpt-6.1-sol','reasoningEffort':'xhigh','beforeSHA256':before,'afterSHA256':hashlib.sha256(p.read_bytes()).hexdigest(),'sealedGenericContractSHA256':'afcccf2438ae96d12f14662c8914fc3f68bf6e2a2d9f5d05141148ee4ea624d4','PFPWorkingSourceSHA256':'fb3020533cfe03022e9d590984f7ae19a386debc95f4ecb1777fc538b5b2daeb','status':'INTERMEDIATE NONINSTALLABLE; parse/typecheck/review/runtime due','remaining':['Actual Router fresh provider and lossless Store generic accounting provenance','Complete initial C16 role classification before authentic list equality, including unpaired generic partials','Fresh provider before/after every raw IO and owned one-effect receipt ordering','Mixed/legacy generic parent rename provenance outside authentic C16 mapping','Current image/order/tail codec bounds under root/reviewer direction']};(q/'GENERIC_POLICY_BRIDGE_V16.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))

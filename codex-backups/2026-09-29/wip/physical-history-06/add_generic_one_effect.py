from pathlib import Path
p=Path('.codex-temp/cold-physical-continuation-successor-v5/candidate/FieldEvidenceApp/Infrastructure/Persistence/EraseSchema2ColdAuxiliaryFirstObservationV1.swift')
s=p.read_text()
a=s.index('final class EraseSchema2ColdPhysicalCleanupOwnerV1');c=s[a:]
c=c.replace('''            }
        }
        var values: [Progress.Projection]''','''            }
            try c16Scope?.requireCurrentBinding(); try initialScope?.requireCurrentBinding()
            try genericScope?.requireCurrentBinding()
        }
        var values: [Progress.Projection]''',1)
c=c.replace('''func poison() { self.uncertain = true; permit.poisonOnUncertainEffect() }
        var parentFacts''','''func poison() { self.uncertain = true; permit.poisonOnUncertainEffect()
            c16Scope?.poisonOnUncertainObservation(); initialScope?.poisonOnUncertainObservation()
            genericScope?.poisonOnUncertainObservation() }
        var parentFacts''',1)
helper='''    private func genericCurrentPath(_ original: String,
        mapping: OriginalEraseSealedGenericPathMappingV1) throws -> String {
        switch mapping {
        case .unchanged: return original
        case .c16ParentRename(let before, let after, let ordinal, let binding):
            guard before != after, plan.steps.indices.contains(ordinal),
                  StoreMigrationCanonicalJSONV1.isLowercaseSHA256(binding),
                  original.hasPrefix(before + "/") else { throw EraseAllServiceError.invalidAuthority }
            // The privately issued scope already proves the actual rename and
            // source/record tuple. This pure path mapping supplies no effect.
            return after + String(original.dropFirst(before.count))
        }
    }

    /// A current scanner node can carry only the genuine scope's exact
    /// declared survivor. Immutable source facts are never rewritten. Drift
    /// from an already captured progress fact is allowed solely for the ONE
    /// active PREPARING loss; completed postimages remain exact.
    private func genericSurvivor(_ node: Node, path: String, image: Image,
        progress: Progress, sourcePath: String? = nil,
        allowingActiveProgressDrift: Bool = false) throws -> Bool {
        guard case .ownedGenericSingleSurvivor(let single)? = node.sealedGenericRole else { return false }
        let prefix = "support/FieldEvidenceOperations/"
        guard node.names == nil, path == prefix + single.member.operationsRelativePath,
              node.fullFact == single.member.fullFact, node.sha256 == single.sha256,
              single.original.kind == "observedOwnedGenericAliases",
              single.original.members.count == 2,
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(single.originBinding),
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(single.accountingSHA256),
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(single.consumed.recordBindingSHA256) else {
            throw EraseAllServiceError.invalidAuthority
        }
        let originals = originalNodes()
        var source: OriginalEraseAuxiliaryPairAccountingDataV1.Member?
        for member in single.original.members {
            guard let original = originals[prefix + member.operationsRelativePath],
                  original.kind == "file", original.fact == member.observedFact,
                  original.sha256 == single.sha256,
                  try Self.nine(member.fullFact) == member.observedFact else {
                throw EraseAllServiceError.invalidAuthority
            }
            if try genericCurrentPath(member.operationsRelativePath, mapping: single.pathMapping)
                == single.member.operationsRelativePath { source = member }
        }
        guard let source, sourcePath == nil || sourcePath == source.operationsRelativePath,
              source.operationsRelativePath != single.consumed.operationsRelativePath,
              single.original.members.contains(where: { $0.operationsRelativePath == single.consumed.operationsRelativePath }) else {
            throw EraseAllServiceError.invalidAuthority
        }
        let before = try Self.fields(source.fullFact), after = try Self.fields(node.fullFact)
        guard before[5] == "2", after[5] == "1",
              [0,1,2,3,4,6,7,8].allSatisfy({ before[$0] == after[$0] }),
              try Self.nine(node.fullFact) == single.member.observedFact,
              image.nodes[prefix + (try genericCurrentPath(single.consumed.operationsRelativePath,
                mapping: single.pathMapping))] == nil else { throw EraseAllServiceError.invalidAuthority }
        switch single.consumed.target {
        case .mixedTarget(let index):
            let consumedPath = prefix + (try genericCurrentPath(single.consumed.operationsRelativePath,
                mapping: single.pathMapping))
            guard targets.indices.contains(index), targets[index].kind != .c16,
                  targets[index].path == consumedPath else { throw EraseAllServiceError.invalidAuthority }
            switch single.consumed.disposition {
            case .completedPostimage:
                guard index < progress.completedPrefixCount, !allowingActiveProgressDrift else {
                    throw EraseAllServiceError.invalidAuthority
                }
            case .activePreparingAbsence:
                guard index == progress.activeTargetIndex, index == progress.completedPrefixCount,
                      progress.stage == .preparing || progress.stage == .preparingCaptured else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
        case .c16Step(let ordinal):
            guard !allowingActiveProgressDrift, plan.steps.indices.contains(ordinal),
                  let current = progress.activeC16Ordinal, ordinal <= current else {
                throw EraseAllServiceError.invalidAuthority
            }
            // Exact effect/record/path membership was positively proved by
            // the real generic scope, never inferred from this range check.
        }
        return true
    }

'''
c=c.replace('''    private func requireFinite(_ image: Image,''',helper+'''    private func requireFinite(_ image: Image,''',1)
c=c.replace('''                guard try Self.nine(actual.fullFact) == node.fact else { throw EraseAllServiceError.invalidAuthority }
''','''                guard try Self.nine(actual.fullFact) == node.fact
                    || genericSurvivor(actual, path: path, image: image, progress: progress) else {
                    throw EraseAllServiceError.invalidAuthority
                }
''',1)
# Within the exact C16 expected first-P source comparison, a genuine generic
# evolution is separate from the canonical declared first-P settlement.
c=c.replace('''                    if nine != first.fact {
                        let a''','''                    if nine != first.fact,
                       !(try genericSurvivor(actual, path: prefix + file.path,
                            image: image, progress: progress, sourcePath: sourcePath)) {
                        let a''',1)
c=c.replace('''                      let prior = expected[path], actual.fullFact == prior.fullFact else''','''                      let prior = expected[path], actual.fullFact == prior.fullFact
                        || (try genericSurvivor(actual, path: path, image: image,
                            progress: progress, allowingActiveProgressDrift: true)) else''',1)
# Generic C16 siblings comparison of immutable original source.
pos=c.index('            for (path, node) in generic where')
end=c.index('            if let scratch',pos)
d=c[pos:end].replace('''guard try Self.nine(actual.fullFact) == node.fact else''','''guard try Self.nine(actual.fullFact) == node.fact
                        || genericSurvivor(actual, path: path, image: image, progress: progress) else''')
c=c[:pos]+d+c[end:]
c=c.replace('''guard let old = expected[path], actual.fullFact == old.fullFact, actual.sha256 == old.sha256 else''','''guard let old = expected[path], actual.sha256 == old.sha256,
                      actual.fullFact == old.fullFact
                        || (try genericSurvivor(actual, path: path, image: image,
                            progress: progress, allowingActiveProgressDrift: true)) else''',1)
c=c.replace('''                guard value == old else { throw EraseAllServiceError.invalidAuthority }
''','''                guard value == old || (image.nodes[value.path].map { node in
                    try genericSurvivor(node, path: value.path, image: image,
                        progress: progress, allowingActiveProgressDrift: true)
                } == true) else { throw EraseAllServiceError.invalidAuthority }
''',1)
# Genuine scope provider across the actual assigned unlink. It issues a new
# lexical source/control proof; physical code never constructs a scope.
c=c.replace('''        permit: EraseSchema2ColdPhysicalPermitV1) throws -> EraseSchema2ColdPhysicalEffectReceiptV1 {''','''        permit: EraseSchema2ColdPhysicalPermitV1,
        genericScopeProvider: @MainActor () throws -> OriginalEraseSealedGenericObservationScopeV1? = { nil }
    ) throws -> EraseSchema2ColdPhysicalEffectReceiptV1 {''',1)
c=c.replace('''        func bound() throws { try self.requireBinding(permit, progress: progress); try c16Scope?.requireCurrentBinding() }
        func poison()''','''        var genericScope = try genericScopeProvider()
        try genericScope?.requireCurrentBinding()
        func bound() throws { try self.requireBinding(permit, progress: progress)
            try c16Scope?.requireCurrentBinding(); try genericScope?.requireCurrentBinding() }
        func poison()''',1)
start=c.index('    func performOneTarget(');end=c.index('    fileprivate func requireReceipt',start)
d=c[start:end]
d=d.replace('''c16Scope: c16Scope, permit: permit, progress: progress)''','''c16Scope: c16Scope, permit: permit, progress: progress, genericScope: genericScope)''')
d=d.replace('''                    guard !directory || node.names == [] else { throw EraseAllServiceError.invalidAuthority }
                    try io.schema2ColdWithOpen''','''                    guard !directory || node.names == [] else { throw EraseAllServiceError.invalidAuthority }
                    let exactPair: OriginalEraseSealedOwnedGenericAliasPairV1?
                    if case .observedOwnedGenericAliases(let pair)? = node.sealedGenericRole {
                        guard !directory, let genericScope,
                              pair.operationID == genericScope.operationID,
                              pair.originBinding == genericScope.originBinding,
                              pair.accountingSHA256 == genericScope.accountingSHA256,
                              pair.members.contains(where: { "support/FieldEvidenceOperations/" + $0.operationsRelativePath == target.path }),
                              case .intact(let currentPair) = try genericScope.requireOwnedGenericEvolution(
                                accountingRowIndex: pair.original.index), currentPair == pair else {
                            throw EraseAllServiceError.invalidAuthority
                        }
                        exactPair = pair
                    } else { exactPair = nil }
                    try io.schema2ColdWithOpen''')
d=d.replace('''directory ? held.st_mode & S_IFMT == S_IFDIR : held.st_mode & S_IFMT == S_IFREG && held.st_nlink == 1,''','''directory ? held.st_mode & S_IFMT == S_IFDIR : held.st_mode & S_IFMT == S_IFREG
                                && (held.st_nlink == 1 || (held.st_nlink == 2 && exactPair != nil)),''')
d=d.replace('''                        effect = .unlinked
                        try bound()''','''                        effect = .unlinked
                        // The real central provider revokes the preimage
                        // scope and proves this ONE owned PREPARING loss.
                        genericScope = try genericScopeProvider()
                        if exactPair != nil { guard genericScope != nil else { throw EraseAllServiceError.invalidAuthority } }
                        try bound()''',1)
d=d.replace('''            for (path, node) in before.nodes where path != target.path && path != parentPath {
                guard after.nodes[path] == node else { throw EraseAllServiceError.invalidAuthority }
            }''','''            for (path, node) in before.nodes where path != target.path && path != parentPath {
                if after.nodes[path] == node { continue }
                guard effect == .unlinked, before.nodes[target.path] != nil,
                      case .observedOwnedGenericAliases(let beforePair)? = node.sealedGenericRole,
                      case .observedOwnedGenericAliases(let targetPair)? = before.nodes[target.path]?.sealedGenericRole,
                      beforePair == targetPair,
                      let survivor = after.nodes[path],
                      case .ownedGenericSingleSurvivor(let single)? = survivor.sealedGenericRole,
                      single.original == beforePair.original,
                      case .mixedTarget(let lostIndex) = single.consumed.target, lostIndex == index,
                      try genericSurvivor(survivor, path: path, image: after, progress: progress,
                        allowingActiveProgressDrift: true) else { throw EraseAllServiceError.invalidAuthority }
            }''')
c=c[:start]+d+c[end:]
s=s[:a]+c;p.write_text(s)

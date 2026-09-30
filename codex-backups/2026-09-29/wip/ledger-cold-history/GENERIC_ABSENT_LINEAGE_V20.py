from pathlib import Path
import hashlib,json
q=Path('.codex-temp/cold-ledger-continuation-successor-v1');p=q/'candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift';b=p.read_bytes();before='2f5966b47e6c32d29f743d19986f1682f6ea68cf5478b47741576362dcd3dc87';assert hashlib.sha256(b).hexdigest()==before;s=b.decode()
a='''    private func originalEraseGenericOriginalAllowsPair(path: String) throws -> Bool {
        try requireScratchDescriptorAccess()
        guard let rowFact = originalEraseGenericOriginalFacts[path],
              originalEraseC16FirstPFacts[path] == rowFact else { return false }
        return try OriginalEraseC16PhysicalFactV1(rowFact).linkCount == 2
    }
'''
b='''    private func originalEraseGenericOriginalAllowsPair(path: String) throws -> Bool {
        try requireScratchDescriptorAccess()
        guard originalEraseBorrowedLifetime == .active else { return false }
        guard Thread.isMainThread, let provider = originalEraseGenericScopeProvider,
              let operationID = originalEraseOperationID else {
            originalEraseBorrowedLifetime = .uncertain
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        return try MainActor.assumeIsolated {
            let scope: OriginalEraseSealedGenericObservationScopeV1
            do {
                guard let issued = try provider() else { return false }
                scope = issued
            } catch {
                originalEraseBorrowedLifetime = .uncertain
                originalEraseColdPermit?.poisonOnUncertainEffect()
                originalEraseC16BootstrapPermit?.poisonOnUncertainEffect()
                throw error
            }
            do {
                guard scope.operationID == operationID else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                try scope.requireCurrentBinding()
                guard let evolution = try scope.requireOwnedGenericEvolutionForOriginalPath(path: path) else { return false }
                let row: OriginalEraseAuxiliaryPairAccountingDataV1.Row
                switch evolution {
                case .intact(let pair): row = pair.original
                case .oneMemberConsumed(let survivor): row = survivor.original
                case .bothMembersConsumed(let original, _, _, _, _, _, _): row = original
                }
                guard let member = row.members.first(where: { $0.operationsRelativePath == path }),
                      originalEraseC16FirstPFacts[path] == member.observedFact,
                      try OriginalEraseC16PhysicalFactV1(member.observedFact).linkCount == 2,
                      let after = try provider(), after.operationID == operationID,
                      after.originBinding == scope.originBinding,
                      after.accountingSHA256 == scope.accountingSHA256,
                      try after.requireOwnedGenericEvolutionForOriginalPath(path: path) == evolution else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                try after.requireCurrentBinding()
                // Original DATA remains available after the last alias has
                // been consumed. Nil was authenticated complete-table absence,
                // never inferred from a missing current name or cached policy.
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
''';assert s.count(a)==1;s=s.replace(a,b);p.write_text(s)
f=Path('/Users/rentamac/.codex/worktrees/cold-erase-continuation/AssetRounds/.codex-temp/cold-schema2-continuation-successor-v1/issuer-core-successor-v9/SEALED_GENERIC_OBSERVATION_V2.swift.fragment')
r={'model':'gpt-6.1-sol','reasoningEffort':'xhigh','beforeSHA256':before,'afterSHA256':hashlib.sha256(p.read_bytes()).hexdigest(),'scopeV2SHA256':hashlib.sha256(f.read_bytes()).hexdigest(),'change':'Actual original-path accounting/evolution lookup for intact/single/both-consumed cold replay; immutable P source9 equality and fresh current token on both sides; no survivor/cached authorization','status':'INTERMEDIATE NONINSTALLABLE; actual issuer/source/accounting and compile/review/runtime due'};(q/'GENERIC_ABSENT_LINEAGE_V20.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))

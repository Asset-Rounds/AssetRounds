from pathlib import Path
import hashlib,json
packet=Path('.codex-temp/cold-ledger-continuation-successor-v1')
p=packet/'candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift'
b=p.read_bytes(); expected='9e103f62be4aeb15d72c7e822c2c89eb17853c5aa2c9f837fdb2abcac1977723'
assert hashlib.sha256(b).hexdigest()==expected
s=b.decode()
def replace(old,new):
    global s
    assert s.count(old)==1,(s.count(old),old[:100])
    s=s.replace(old,new)
replace('''    private var originalEraseOperationID: UUID?
    private enum OriginalEraseBorrowedLifetimeV1''','''    private var originalEraseOperationID: UUID?
    // A Router-issued observation is renewed from the actual retained source
    // and Store cut. It is never preserved as authority across a capture CAS,
    // ordinal advance or parent rename. Nil retains ordinary strict predicates.
    private var originalEraseGenericScopeProvider:
        (@MainActor () throws -> OriginalEraseSealedGenericObservationScopeV1?)?
    private enum OriginalEraseBorrowedLifetimeV1''')
replace('''            guard originalEraseBorrowedExclusiveCheck != nil else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
        case .closed, .uncertain: throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
    }

    private var originalEraseBorrowedAdmitting''','''            guard originalEraseBorrowedExclusiveCheck != nil else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            try originalEraseRequireFreshGenericBinding()
        case .closed, .uncertain: throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
    }

    // The legacy ordinary store remains nonisolated. Borrowed calls originate
    // only in the MainActor body/engine. Check the permanent memory latch before
    // entering the actor bridge, and never inspect a descriptor as a guard.
    private func originalEraseRequireFreshGenericBinding() throws {
        guard originalEraseBorrowedLifetime == .active,
              Thread.isMainThread,
              let provider = originalEraseGenericScopeProvider,
              let operationID = originalEraseOperationID else {
            originalEraseBorrowedLifetime = .uncertain
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        do {
            try MainActor.assumeIsolated {
                if let scope = try provider() {
                    guard scope.operationID == operationID else {
                        scope.poisonOnUncertainObservation()
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                    try scope.requireCurrentBinding()
                }
            }
        } catch {
            originalEraseBorrowedLifetime = .uncertain
            MainActor.assumeIsolated {
                originalEraseColdPermit?.poisonOnUncertainEffect()
                originalEraseC16BootstrapPermit?.poisonOnUncertainEffect()
            }
            throw error
        }
    }

    private var originalEraseBorrowedAdmitting''')
replace('''        permit: EraseSchema2ColdScratchBootstrapPermitV1,
        firstPPartials: [OriginalEraseC16StepV1],
        verifyPostimageBeforeClose:''','''        permit: EraseSchema2ColdScratchBootstrapPermitV1,
        firstPPartials: [OriginalEraseC16StepV1],
        genericObservationScope: @escaping @MainActor () throws
            -> OriginalEraseSealedGenericObservationScopeV1?,
        verifyPostimageBeforeClose:''')
replace('''            store.originalEraseOperationID = operationID
            store.originalEraseC16BootstrapPermit = permit''','''            store.originalEraseOperationID = operationID
            store.originalEraseGenericScopeProvider = genericObservationScope
            store.originalEraseC16BootstrapPermit = permit''')
replace('''                store.originalEraseC16BootstrapPermit = nil; store.originalEraseOperationID = nil
''','''                store.originalEraseC16BootstrapPermit = nil; store.originalEraseOperationID = nil
                store.originalEraseGenericScopeProvider = nil
''')
replace('''        permit: EraseSchema2ColdScratchLifecyclePermitV1,
        frozenGenericLeaseAdmission:''','''        permit: EraseSchema2ColdScratchLifecyclePermitV1,
        genericObservationScope: @escaping @MainActor () throws
            -> OriginalEraseSealedGenericObservationScopeV1?,
        frozenGenericLeaseAdmission:''')
replace('''            store.originalEraseOperationID = operationID
            store.originalEraseColdPermit = permit''','''            store.originalEraseOperationID = operationID
            store.originalEraseGenericScopeProvider = genericObservationScope
            store.originalEraseColdPermit = permit''')
replace('''                store.originalEraseOperationID = nil
                store.originalEraseColdPermit = nil''','''                store.originalEraseOperationID = nil
                store.originalEraseGenericScopeProvider = nil
                store.originalEraseColdPermit = nil''')
p.write_text(s)
record={'model':'gpt-6.1-sol','reasoningEffort':'xhigh','beforeSHA256':expected,'afterSHA256':hashlib.sha256(p.read_bytes()).hexdigest(),'contractSHA256':'afcccf2438ae96d12f14662c8914fc3f68bf6e2a2d9f5d05141148ee4ea624d4','scope':'Ledger-only ignored candidate','status':'INTERMEDIATE NONINSTALLABLE; required provider API and permanent memory-first actor bridge only','remaining':['actual Router provider/Store authenticated accounting readback','generic positive pair/single policy bridge and role exclusion','raw IO before/after proof census beyond entry memory fence','actual generic rename provenance beyond C16 mapping','independent review/typecheck/runtime/gates']}
(packet/'GENERIC_FRESH_PROVIDER_V14.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record,indent=2))

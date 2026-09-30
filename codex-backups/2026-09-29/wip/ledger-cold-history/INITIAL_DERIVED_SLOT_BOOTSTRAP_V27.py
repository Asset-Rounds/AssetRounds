from pathlib import Path
import hashlib,json
q=Path('.codex-temp/cold-ledger-continuation-successor-v1');p=q/'candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift'
s=p.read_text();before=hashlib.sha256(p.read_bytes()).hexdigest()
assert before=='fed6159d0a7b210aafe4182c441c5a97b0e228a71b2f77bdd425f8bd29cc3dcb',before
def replace(a,b):
 global s
 assert s.count(a)==1,(s.count(a),a[:100])
 s=s.replace(a,b)
replace('''    private var originalEraseC16InitialSourceProof = false
''','''    private var originalEraseC16InitialSourceProof = false
    // Read-only output of this exact Store's genuine first-P planner. It is
    // distinct from the authenticated effect referencePlan and cannot enter
    // an engine ordinal or manufacture a Progress record.
    private var originalEraseC16InitialDerivedPlan: OriginalEraseC16PlanV1?
''')
replace('''                store.originalEraseC16InitialPartials.removeAll(); store.originalEraseC16InitialSourceProof = false
''','''                store.originalEraseC16InitialPartials.removeAll(); store.originalEraseC16InitialSourceProof = false
                store.originalEraseC16InitialDerivedPlan = nil
''')
start=s.index('    func originalEraseC16PlanFromFirstP(')
end=s.index('    @MainActor private func settleOriginalEraseFirstPPartial(',start)
part=s[start:end]
assert part.count('''            try plan.validate()
            return plan''')==2
part=part.replace('''            try plan.validate()
            return plan''','''            try plan.validate()
            try requireOriginalEraseBorrowedOwner()
            originalEraseC16InitialDerivedPlan = plan
            return plan''')
assert part.count('''        try plan.validate()
''')>=1
# The final complete original-P planner validates then renews real ownership.
needle='''        try plan.validate()
        return plan'''
assert part.count(needle)==1
part=part.replace(needle,'''        try plan.validate()
        try requireOriginalEraseBorrowedOwner()
        try originalEraseBorrowedExclusiveCheck?()
        originalEraseC16InitialDerivedPlan = plan
        return plan''')
s=s[:start]+part+s[end:]
replace('''        guard originalEraseC16ReferencePlan == plan else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        let maximum = try plan.maximumRetainedBornProducerSlotCount()''','''        let initialDerived = originalEraseC16InitialSourceProof
            && originalEraseC16ReferencePlan == nil
            && originalEraseC16InitialDerivedPlan == plan
            && originalEraseC16BootstrapPermit != nil
        guard originalEraseC16ReferencePlan == plan || initialDerived else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        // requireOriginalEraseBorrowedOwner invokes the real complete
        // no-progress Initial binding for initialDerived, including a freshly
        // issued Sources/Plan/noProgress control cut. No proposed ordinal.
        let maximum = try plan.maximumRetainedBornProducerSlotCount()''')
replace('''            guard let permit = originalEraseColdPermit else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            do {
                try permit.requireObservationBinding()
                guard let value = try permit.canonicalProducerRequest(slot: slot) else { return nil }''','''            if let bootstrap = originalEraseC16BootstrapPermit {
                guard originalEraseColdPermit == nil, originalEraseC16InitialSourceProof,
                      originalEraseC16ReferencePlan == nil, originalEraseC16CurrentOrdinal == nil else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                // The required actual Initial callback proves the COMPLETE
                // current no-progress/no-effects control image, including
                // pending producer absence. This is a read-only origin proof,
                // not a default nil getter or permission to publish.
                _ = try bootstrap.requireInitialC16ObservationBinding(firstPPartials: originalEraseC16InitialPartials)
                _ = try bootstrap.requireInitialC16ObservationBinding(firstPPartials: originalEraseC16InitialPartials)
                return nil
            }
            guard let permit = originalEraseColdPermit else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            do {
                try permit.requireObservationBinding()
                guard let value = try permit.canonicalProducerRequest(slot: slot) else { return nil }''')
replace('''        let value = try CompatibilityCanonicalV1.decode(type, from: source.bytes)
        guard try CompatibilityCanonicalV1.encode(value) == source.bytes else {''','''        if originalEraseC16InitialSourceProof {
            guard originalEraseBorrowedLifetime == .active, Thread.isMainThread else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            try MainActor.assumeIsolated {
                guard let bootstrap = originalEraseC16BootstrapPermit,
                      originalEraseColdPermit == nil, originalEraseC16ReferencePlan == nil else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                _ = try bootstrap.requireInitialC16ObservationBinding(firstPPartials: originalEraseC16InitialPartials)
                try bootstrap.requireOriginalPSource(path: "ProtectedIngressReceiptsV1/" + name,
                    bytes: source.bytes, fullFact: source.fullFact)
                _ = try bootstrap.requireInitialC16ObservationBinding(firstPPartials: originalEraseC16InitialPartials)
            }
        }
        let value = try CompatibilityCanonicalV1.decode(type, from: source.bytes)
        guard try CompatibilityCanonicalV1.encode(value) == source.bytes else {''')
p.write_text(s)
r={'model':'gpt-6.1-sol','reasoningEffort':'xhigh','beforeSHA256':before,
 'afterSHA256':hashlib.sha256(p.read_bytes()).hexdigest(),
 'authority':'central accepted distinct read-only first-P-derived plan DATA; actual complete noProgress proof remains required',
 'change':['Private exact initialDerivedPlan retained only after genuine PlanFromFirstP output proof','Slot enumeration accepts exact initialDerived output under real Bootstrap owner; effect referencePlan remains nil','Original marker source is freshly admitted per bootstrap decode','Pending absence in Bootstrap only under actual COMPLETE noProgress/noEffects Initial callback'],
 'limitations':['Actual central complete noProgress/pending-absence issuer and Store bootstrap controls not implemented','No fake proposed plan/ordinal/Progress/effect authority','Compile/runtime and complete generic-directory/current capacity remain due']}
(q/'INITIAL_DERIVED_SLOT_BOOTSTRAP_V27.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))

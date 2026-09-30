from pathlib import Path
import hashlib,json
q=Path('.codex-temp/cold-ledger-continuation-successor-v1');p=q/'candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift'
s=p.read_text();before=hashlib.sha256(p.read_bytes()).hexdigest()
assert before=='8c5c436e7293d8550eafa05bdc8acea50abfc1748ab68b39f8acbf4ec7860041',before
def replace(a,b):
 global s
 assert s.count(a)==1,(s.count(a),a[:100]);s=s.replace(a,b)
replace('struct OriginalEraseC16BornSourceObservationV1: Equatable {','''/// Position and prior pure computation only. Neither a cursor nor its private
/// warm stamp retains an Initial permit, record token, descriptor or authority.
struct OriginalEraseC16BornSlotCursorV4 {
    let planSHA256: String
    let nextProducerOrdinal: Int
    let nextWithinProducerOrdinal: UInt64
    let nextSlotOrdinal: UInt64
    let prefixCommitmentSHA256: String
    fileprivate let warmComputation: OriginalEraseC16BornSlotComputationV4?
    init(planSHA256: String, nextProducerOrdinal: Int,
        nextWithinProducerOrdinal: UInt64, nextSlotOrdinal: UInt64,
        prefixCommitmentSHA256: String) {
        self.planSHA256 = planSHA256; self.nextProducerOrdinal = nextProducerOrdinal
        self.nextWithinProducerOrdinal = nextWithinProducerOrdinal
        self.nextSlotOrdinal = nextSlotOrdinal
        self.prefixCommitmentSHA256 = prefixCommitmentSHA256
        warmComputation = nil
    }
    fileprivate init(computation: OriginalEraseC16BornSlotComputationV4) {
        planSHA256 = computation.planSHA256
        nextProducerOrdinal = computation.nextProducerOrdinal
        nextWithinProducerOrdinal = computation.nextWithinProducerOrdinal
        nextSlotOrdinal = computation.nextSlotOrdinal
        prefixCommitmentSHA256 = computation.prefixCommitmentSHA256
        warmComputation = computation
    }
}

fileprivate struct OriginalEraseC16BornSlotComputationV4 {
    let planSHA256: String
    let nextProducerOrdinal: Int
    let nextWithinProducerOrdinal: UInt64
    let nextSlotOrdinal: UInt64
    let prefixCommitmentSHA256: String
    func exactlyMatches(_ cursor: OriginalEraseC16BornSlotCursorV4) -> Bool {
        planSHA256 == cursor.planSHA256 && nextProducerOrdinal == cursor.nextProducerOrdinal
            && nextWithinProducerOrdinal == cursor.nextWithinProducerOrdinal
            && nextSlotOrdinal == cursor.nextSlotOrdinal
            && prefixCommitmentSHA256 == cursor.prefixCommitmentSHA256
    }
}

struct OriginalEraseC16BornSlotPageV4 {
    let slots: [OriginalEraseC16BornProducerSlotV1]
    let nextCursor: OriginalEraseC16BornSlotCursorV4?
    /// Cumulative exact prefix count, including this page; never page length.
    let emittedSlotCount: UInt64
}

struct OriginalEraseC16BornSourceObservationV1: Equatable {''')
replace('''    private var originalEraseC16InitialDerivedPlan: OriginalEraseC16PlanV1?
''','''    private var originalEraseC16InitialDerivedPlan: OriginalEraseC16PlanV1?
    private var originalEraseC16InitialDerivedPlanSHA256: String?
''')
replace('''                store.originalEraseC16InitialDerivedPlan = nil
''','''                store.originalEraseC16InitialDerivedPlan = nil
                store.originalEraseC16InitialDerivedPlanSHA256 = nil
''')
assert s.count('originalEraseC16InitialDerivedPlan = plan')==3
s=s.replace('originalEraseC16InitialDerivedPlan = plan','originalEraseC16InitialDerivedPlan = plan\n            originalEraseC16InitialDerivedPlanSHA256 = try CompatibilityCanonicalV1.sha256(CompatibilityCanonicalV1.encode(plan))',2)
pos=s.index('        originalEraseC16InitialDerivedPlan = plan',s.index('    func originalEraseC16PlanFromFirstP('))
# The last branch has eight-space indentation. Normalize its hash line.
last=s.rfind('        originalEraseC16InitialDerivedPlan = plan')
lineEnd=s.index('\n',last)
s=s[:lineEnd]+'''\n        originalEraseC16InitialDerivedPlanSHA256 = try CompatibilityCanonicalV1.sha256(CompatibilityCanonicalV1.encode(plan))'''+s[lineEnd:]

replace('''            var slots: [OriginalEraseC16BornProducerSlotV1] = []
            if step == .eraseFinalControl {
                slots = [.init(producerOrdinal: ordinal, role: "scratchControlErase",
                    path: "ProtectedIngressReceiptsV1/" + Self.controlEraseName)]
            } else {
                let roles = try originalEraseC16CanonicalRolesForStep(plan: plan, ordinal: ordinal)
                for name in try originalEraseC16PublicationRoleSequence(plan: plan, ordinal: ordinal) {
                    guard let role = roles[name] else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    slots.append(.init(producerOrdinal: ordinal, role: role.role,
                        path: "ProtectedIngressReceiptsV1/" + name))
                }
            }
            guard Set(slots).count == slots.count else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            for slot in slots.sorted(by: { $0.role == $1.role ? $0.path < $1.path : $0.role < $1.role }) {''','''            let slots = try originalEraseC16BornSlotsForProducer(plan: plan, ordinal: ordinal)
            for slot in slots {''')
replace('''        for (ordinal, step) in plan.steps.enumerated() {
            try requireOriginalEraseBorrowedOwner()
            let slots = try originalEraseC16BornSlotsForProducer''','''        for ordinal in plan.steps.indices {
            try requireOriginalEraseBorrowedOwner()
            let slots = try originalEraseC16BornSlotsForProducer''')
replace('''    /// Convenience for bounded inspection callers. Durable publication uses
''','''    @MainActor private func originalEraseC16BornSlotsForProducer(
        plan: OriginalEraseC16PlanV1, ordinal: Int
    ) throws -> [OriginalEraseC16BornProducerSlotV1] {
        try requireScratchDescriptorAccess()
        try requireOriginalEraseBorrowedOwner()
        guard ordinal >= 0, ordinal < plan.steps.count else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        var slots: [OriginalEraseC16BornProducerSlotV1] = []
        if plan.steps[ordinal] == .eraseFinalControl {
            slots = [.init(producerOrdinal: ordinal, role: "scratchControlErase",
                path: "ProtectedIngressReceiptsV1/" + Self.controlEraseName)]
        } else {
            let roles = try originalEraseC16CanonicalRolesForStep(plan: plan, ordinal: ordinal)
            for name in try originalEraseC16PublicationRoleSequence(plan: plan, ordinal: ordinal) {
                guard let role = roles[name] else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                slots.append(.init(producerOrdinal: ordinal, role: role.role,
                    path: "ProtectedIngressReceiptsV1/" + name))
            }
        }
        guard Set(slots).count == slots.count else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        try requireOriginalEraseBorrowedOwner()
        return slots.sorted { $0.role == $1.role ? $0.path < $1.path : $0.role < $1.role }
    }

    /// Read-only transfer page. Store publishes only after returning from this
    /// call and exiting/revoking its actual Initial image. A new page requires
    /// a freshly issued real Initial source/checkpoint/noProgress owner.
    @MainActor
    func readOriginalEraseC16InitialBornProducerSlotPage(
        plan: OriginalEraseC16PlanV1,
        cursor: OriginalEraseC16BornSlotCursorV4?,
        maximumCount: Int
    ) throws -> OriginalEraseC16BornSlotPageV4 {
        try requireScratchDescriptorAccess()
        try requireOriginalEraseBorrowedOwner()
        guard maximumCount > 0, maximumCount <= 128,
              originalEraseC16InitialSourceProof, originalEraseC16ReferencePlan == nil,
              originalEraseC16InitialDerivedPlan == plan,
              let planSHA = originalEraseC16InitialDerivedPlanSHA256,
              originalEraseC16BootstrapPermit != nil, originalEraseColdPermit == nil,
              originalEraseC16CurrentOrdinal == nil else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let maximumSlots = UInt64(try plan.maximumRetainedBornProducerSlotCount())
        var producer = 0, within: UInt64 = 0, count: UInt64 = 0
        var prefix = try CompatibilityCanonicalV1.sha256(
            Data(("OriginalEraseC16BornSlotPrefixV4|" + planSHA).utf8))
        func nextPrefix(_ old: String, _ slot: OriginalEraseC16BornProducerSlotV1) throws -> String {
            let framed = old + "|" + String(slot.producerOrdinal) + "|"
                + String(slot.role.utf8.count) + ":" + slot.role + "|"
                + String(slot.path.utf8.count) + ":" + slot.path
            return try CompatibilityCanonicalV1.sha256(Data(framed.utf8))
        }
        if let cursor {
            guard cursor.planSHA256 == planSHA,
                  cursor.nextProducerOrdinal >= 0, cursor.nextProducerOrdinal <= plan.steps.count,
                  cursor.nextSlotOrdinal <= maximumSlots,
                  CompatibilityCanonicalV1.validSHA256(cursor.prefixCommitmentSHA256) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            if let computed = cursor.warmComputation, computed.exactlyMatches(cursor) {
                // Pure prior computation only. Actual Initial/source proof
                // above and below is never skipped by this retained data.
                producer = cursor.nextProducerOrdinal
                within = cursor.nextWithinProducerOrdinal
                count = cursor.nextSlotOrdinal
                prefix = cursor.prefixCommitmentSHA256
            } else {
                // A decoded cold cursor has no private stamp. Recompute its
                // exact source-backed prefix once, without an all-slot array.
                while producer < cursor.nextProducerOrdinal {
                    let slots = try originalEraseC16BornSlotsForProducer(plan: plan, ordinal: producer)
                    for slot in slots {
                        guard count < cursor.nextSlotOrdinal, count < maximumSlots else {
                            throw ScratchDataLeaseStoreFailureV1.leaseCollision
                        }
                        prefix = try nextPrefix(prefix, slot); count += 1
                    }
                    producer += 1
                }
                if producer < plan.steps.count {
                    let slots = try originalEraseC16BornSlotsForProducer(plan: plan, ordinal: producer)
                    guard cursor.nextWithinProducerOrdinal < UInt64(slots.count) else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                    for index in 0..<Int(cursor.nextWithinProducerOrdinal) {
                        guard count < cursor.nextSlotOrdinal, count < maximumSlots else {
                            throw ScratchDataLeaseStoreFailureV1.leaseCollision
                        }
                        prefix = try nextPrefix(prefix, slots[index]); count += 1
                    }
                    within = cursor.nextWithinProducerOrdinal
                } else {
                    guard cursor.nextWithinProducerOrdinal == 0 else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                }
                guard count == cursor.nextSlotOrdinal, prefix == cursor.prefixCommitmentSHA256 else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
            }
        }
        var output: [OriginalEraseC16BornProducerSlotV1] = []
        output.reserveCapacity(maximumCount)
        while producer < plan.steps.count {
            let slots = try originalEraseC16BornSlotsForProducer(plan: plan, ordinal: producer)
            guard within <= UInt64(slots.count) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            while within < UInt64(slots.count), output.count < maximumCount {
                let slot = slots[Int(within)]
                guard count < maximumSlots else { throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded }
                prefix = try nextPrefix(prefix, slot)
                output.append(slot); count += 1; within += 1
            }
            if within == UInt64(slots.count) { producer += 1; within = 0 }
            if output.count == maximumCount { break }
        }
        // Normalize empty following producers without emitting/skipping slots;
        // this yields nil only after the exact complete source-backed sequence.
        while producer < plan.steps.count, within == 0 {
            let slots = try originalEraseC16BornSlotsForProducer(plan: plan, ordinal: producer)
            if !slots.isEmpty { break }
            producer += 1
        }
        try requireOriginalEraseBorrowedOwner()
        let next = producer == plan.steps.count ? nil
            : OriginalEraseC16BornSlotCursorV4(computation: .init(planSHA256: planSHA,
                nextProducerOrdinal: producer, nextWithinProducerOrdinal: within,
                nextSlotOrdinal: count, prefixCommitmentSHA256: prefix))
        return .init(slots: output, nextCursor: next, emittedSlotCount: count)
    }

    /// Convenience for bounded inspection callers. Durable publication uses
''')
p.write_text(s)
r={'model':'gpt-6.1-sol','reasoningEffort':'xhigh','beforeSHA256':before,
 'afterSHA256':hashlib.sha256(p.read_bytes()).hexdigest(),
 'change':['Read-only Initial output pages1...128','Exact producerOrdinal/role/path sequence shared with existing stream','Private warm stamp caches pure prefix computation only; decoded cold cursor replays exact prefix','Fresh actual Initial/source proof at every call/source boundary; no page writes or permission retained','Cumulative emitted count and explicit SHA-chain framing'],
 'limitations':['Actual source-renew entry/required published-plan binding still needs central contract','Store contiguous checkpoint/table proof before publication and no-effects ordering due','Existing per-producer source arrays retain original model bounds (genuine H131), not an invented128 producer cap','Semantic compile/runtime, whole current capacity and generic directory lineage due']}
(q/'INITIAL_SLOT_PAGE_V30.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))

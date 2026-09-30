from pathlib import Path
p=Path('.codex-temp/cold-ledger-continuation-successor-v1');c=p/'candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift';s=c.read_text();a=s.index('    /// Source-backed finite producer slots, retaining same-path role versions.');b=s.index('    private func originalEraseC16MayConsumePending',a)
f='''    /// Source-backed producer slots in stable ordinal/role/path order. Only
    /// the bounded outputs of one original marker are materialized at once.
    /// Store's paged control format consumes this iterator, never a full list.
    @MainActor @discardableResult
    func enumerateOriginalEraseC16BornProducerSlots(
        plan: OriginalEraseC16PlanV1,
        visit: @MainActor (OriginalEraseC16BornProducerSlotV1) throws -> Void
    ) throws -> Int {
        try requireScratchDescriptorAccess()
        try requireOriginalEraseBorrowedOwner()
        guard originalEraseC16ReferencePlan == plan else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        let maximum = try plan.maximumRetainedBornProducerSlotCount()
        var count = 0
        for (ordinal, step) in plan.steps.enumerated() {
            try requireOriginalEraseBorrowedOwner()
            var slots: [OriginalEraseC16BornProducerSlotV1] = []
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
            for slot in slots.sorted(by: { $0.role == $1.role ? $0.path < $1.path : $0.role < $1.role }) {
                let next = count.addingReportingOverflow(1)
                guard !next.overflow, next.partialValue <= maximum else { throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded }
                try requireOriginalEraseBorrowedOwner()
                try visit(slot)
                try requireOriginalEraseBorrowedOwner()
                count = next.partialValue
            }
        }
        try requireOriginalEraseBorrowedOwner()
        return count
    }

    /// Convenience for bounded inspection callers. Durable publication uses
    /// the streaming variant to avoid allocating the complete logical table.
    @MainActor func originalEraseC16BornProducerSlots(
        plan: OriginalEraseC16PlanV1
    ) throws -> [OriginalEraseC16BornProducerSlotV1] {
        var slots: [OriginalEraseC16BornProducerSlotV1] = []
        try enumerateOriginalEraseC16BornProducerSlots(plan: plan) { slots.append($0) }
        return slots
    }

'''
s=s[:a]+f+s[b:];c.write_text(s);p.joinpath('BORN_PRODUCER_SLOTS_STREAM_V6.swift.fragment').write_text(f)

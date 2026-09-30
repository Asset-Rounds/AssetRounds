from pathlib import Path
p=Path('.codex-temp/cold-ledger-continuation-successor-v1/candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift')
s=p.read_text()
a=s.index('    /// Exact canonical outputs of the sole semantic engine through this')
b=s.index('    private func originalEraseC16MayConsumePending',a)
r=s[a:b]
start=r.index('        for index in 0...ordinal {')
end=r.index('        return roles\n',start)
loop=r[start:end]
body=loop.removeprefix('        for index in 0...ordinal {\n').removesuffix('        }\n')
new='''    private func originalEraseC16CanonicalRolesForStep(
        plan: OriginalEraseC16PlanV1, ordinal index: Int
    ) throws -> [String: OriginalEraseC16CanonicalRoleV1] {
        try requireScratchDescriptorAccess()
        guard index >= 0, index < plan.steps.count else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
'''+r[r.index('        var roles:'):start]+body+'''        return roles
    }

    /// Exact canonical outputs of completed and active fixed producer slots.
    private func originalEraseC16CanonicalRoles(
        plan: OriginalEraseC16PlanV1, through ordinal: Int
    ) throws -> [String: OriginalEraseC16CanonicalRoleV1] {
        try requireScratchDescriptorAccess()
        guard ordinal >= 0, ordinal < plan.steps.count else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        var roles: [String: OriginalEraseC16CanonicalRoleV1] = [:]
        for index in 0...ordinal {
            for (name, role) in try originalEraseC16CanonicalRolesForStep(plan: plan, ordinal: index) {
                guard roles[name] == nil || roles[name]?.bytes == role.bytes else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                roles[name] = role
            }
        }
        return roles
    }

    /// Source-backed finite producer slots, retaining same-path role versions.
    /// A count is not permission: Store and the boundary receipt must bind the
    /// exact slot plus genuine canonical payload and its actual physical cut.
    @MainActor func originalEraseC16BornProducerSlots(
        plan: OriginalEraseC16PlanV1
    ) throws -> [OriginalEraseC16BornProducerSlotV1] {
        try requireScratchDescriptorAccess()
        try requireOriginalEraseBorrowedOwner()
        guard originalEraseC16ReferencePlan == plan else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        var result: [OriginalEraseC16BornProducerSlotV1] = []
        for (ordinal, step) in plan.steps.enumerated() {
            if step == .eraseFinalControl {
                result.append(.init(producerOrdinal: ordinal, role: "scratchControlErase",
                    path: "ProtectedIngressReceiptsV1/" + Self.controlEraseName))
                continue
            }
            let roles = try originalEraseC16CanonicalRolesForStep(plan: plan, ordinal: ordinal)
            for name in try originalEraseC16PublicationRoleSequence(plan: plan, ordinal: ordinal) {
                guard let role = roles[name] else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                result.append(.init(producerOrdinal: ordinal, role: role.role,
                    path: "ProtectedIngressReceiptsV1/" + name))
            }
        }
        guard result.count <= (try plan.maximumRetainedBornProducerSlotCount()),
              Set(result).count == result.count else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        try requireOriginalEraseBorrowedOwner()
        return result
    }

'''
s=s[:a]+new+s[b:]
a=s.index('struct OriginalEraseC16BornSourceObservationV1: Equatable {')
s=s[:a]+'''struct OriginalEraseC16BornProducerSlotV1: Hashable {
    let producerOrdinal: Int
    let role: String
    let path: String
}

'''+s[a:]
a=s.index('    func validate() throws {',s.index('struct OriginalEraseC16PlanV1:'))
s=s[:a]+'''    /// Conservative bound from the actual existing producer vocabulary.
    /// E's unchanged128-target cap includes prepared-only nil directories,
    /// which are intentionally absent from its old physical target binding.
    func maximumRetainedBornProducerSlotCount() throws -> Int {
        try validate()
        var total = 0, hygiene = false
        func charge(_ count: Int) throws {
            let next = total.addingReportingOverflow(count)
            guard count >= 0, !next.overflow else { throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded }
            total = next.partialValue
        }
        for step in steps {
            switch step {
            case .resumeHygiene: hygiene = true; try charge(3)
            case .resumeIngressErase: try charge(1 + ProtectedIngressCoordinatorV1.maximumPendingIntentCount)
            case .recoverIngressPointer: try charge(1)
            case .eraseIngress:
                try charge(2); try charge(freshPublishedTargets.count); try charge(freshUnpublishedTargets.count)
            case .eraseFinalControl: try charge(1)
            case .settleFirstPPartial, .resumeControlTail: break
            }
        }
        if hygiene {
            try charge(markerBindings.filter { $0.name.hasPrefix("ingress-") && $0.name.hasSuffix(".published.json") }.count)
        }
        return total
    }

'''+s[a:]
s=s.replace('currentOrdinal < plan.steps.count, capturedBirths.count <= 100_000 else {','currentOrdinal < plan.steps.count,\n              capturedBirths.count <= (try plan.maximumRetainedBornProducerSlotCount()) else {',1)
p.write_text(s)

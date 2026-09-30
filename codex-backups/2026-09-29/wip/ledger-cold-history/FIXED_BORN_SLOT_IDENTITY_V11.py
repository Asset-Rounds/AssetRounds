from pathlib import Path
import hashlib, json
packet = Path(__file__).parent
path = packet / 'candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift'
source = path.read_text()
before = hashlib.sha256(path.read_bytes()).hexdigest()
old = '''    private struct OriginalEraseC16CanonicalRoleV1 {
        let role: String
        let bytes: Data
    }'''
new = '''    private struct OriginalEraseC16CanonicalRoleV1 {
        let role: String
        let bytes: Data
        let producerOrdinal: Int?
        init(role: String, bytes: Data, producerOrdinal: Int? = nil) {
            self.role = role; self.bytes = bytes
            self.producerOrdinal = producerOrdinal
        }
    }'''
assert source.count(old) == 1
source = source.replace(old, new, 1)
old = '            roles[name] = .init(role: role, bytes: bytes)'
assert source.count(old) == 1
source = source.replace(old, '            roles[name] = .init(role: role, bytes: bytes, producerOrdinal: index)', 1)
old = '''                guard roles[name] == nil || roles[name]?.bytes == role.bytes else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                roles[name] = role'''
new = '''                if let earlier = roles[name] {
                    guard earlier.bytes == role.bytes, earlier.role == role.role else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                    // The sole publisher compares and returns when the same
                    // final already exists. A later identical intent is not
                    // another physical birth or a latest-version selector.
                } else { roles[name] = role }'''
assert source.count(old) == 1
source = source.replace(old, new, 1)
start = source.index('    @MainActor private func originalEraseC16MaterializedControlRole(')
end = source.index('    /// Ordered publication roles', start)
chunk = source[start:end]
chunk = chunk.replace('return .init(role: "scratchControlErase", bytes: born.bytes)', 'return .init(role: "scratchControlErase", bytes: born.bytes,\n                producerOrdinal: plan.steps.firstIndex(of: .eraseFinalControl))')
chunk = chunk.replace('return .init(role: "scratchControlErase", bytes: bytes)', 'return .init(role: "scratchControlErase", bytes: bytes,\n            producerOrdinal: plan.steps.firstIndex(of: .eraseFinalControl))')
source = source[:start] + chunk + source[end:]
anchor = '    @MainActor\n    func originalEraseC16ExpectedTree('
helper = '''    private func originalEraseC16FixedBornProducerSlot(
        plan: OriginalEraseC16PlanV1, currentOrdinal: Int,
        name: String, role: OriginalEraseC16CanonicalRoleV1
    ) throws -> OriginalEraseC16BornProducerSlotV1 {
        try requireScratchDescriptorAccess()
        guard let producer = role.producerOrdinal, producer >= 0,
              producer <= currentOrdinal, producer < plan.steps.count,
              try originalEraseC16PublicationRoleSequence(plan: plan,
                ordinal: producer).contains(name) else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        return .init(producerOrdinal: producer, role: role.role,
            path: "ProtectedIngressReceiptsV1/" + name)
    }

'''
assert source.count(anchor) == 1
source = source.replace(anchor, helper + anchor, 1)
path.write_text(source)
(packet / 'FIXED_BORN_SLOT_IDENTITY_V11.json').write_text(json.dumps({'before':before,'after':hashlib.sha256(path.read_bytes()).hexdigest(),'status':'working source-derived slot identity; retained Store matching awaits fresh-stage contract'},indent=2)+'\n')

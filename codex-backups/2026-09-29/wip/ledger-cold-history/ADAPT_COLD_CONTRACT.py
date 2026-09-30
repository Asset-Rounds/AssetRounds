from pathlib import Path
p=Path('.codex-temp/cold-ledger-continuation-successor-v1/candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift')
s=p.read_text()
s=s.replace('withOriginalEraseBorrowedExistingRoot','withSchema2ColdBorrowedExistingRoot').replace('permit: OriginalEraseAuxiliaryScratchLifecyclePermitV1','permit: EraseSchema2ColdScratchLifecyclePermitV1')
anchor='    private var originalEraseC16Planning = false\n'
addition='''    // Immutable data inputs are retained separately from the persisted plan.
    // They never cache authority: the real permit reauthenticates the transfer
    // and current physical cut at every MainActor engine boundary.
    private struct OriginalEraseC16SourceInputV1 {
        let bytes: Data
        let fullFact: String
    }
    private var originalEraseC16SourceInputs: [String: OriginalEraseC16SourceInputV1] = [:]
    private var originalEraseC16FirstPFacts: [String: String] = [:]
    private var originalEraseC16FirstPAbsentPaths = Set<String>()
    @MainActor private var originalEraseColdPermit: EraseSchema2ColdScratchLifecyclePermitV1?

'''
assert anchor in s;s=s.replace(anchor,addition+anchor,1)
anchor='            store.originalEraseOperationID = operationID\n'
s=s.replace(anchor,anchor+'            store.originalEraseColdPermit = permit\n',1)
anchor='                store.originalEraseOperationID = nil\n'
s=s.replace(anchor,anchor+'''                store.originalEraseColdPermit = nil
                store.originalEraseC16SourceInputs.removeAll()
                store.originalEraseC16FirstPFacts.removeAll()
                store.originalEraseC16FirstPAbsentPaths.removeAll()
''',1)
anchor='                store.originalEraseBorrowedAdmitting = true\n'
s=s.replace(anchor,'''                try store.primeOriginalEraseC16ImmutableInputs(plan: referencePlan)
'''+anchor,1)
anchor='        try originalEraseC16CutCheck()\n'
s=s.replace(anchor,'''        try requireOriginalEraseC16TransferredInputs()
'''+anchor+'''        try requireOriginalEraseC16TransferredInputs()
''',1)
# Preserve the pure persisted plan, but make source selection explicit.
start=s.index('    private func originalEraseC16ReferenceValue<Value: Codable>(')
end=s.index('    /// Finalization changes only one canonical flag.',start)
s=s[:start]+'''    private func originalEraseC16ReferenceValue<Value: Codable>(
        _ type: Value.Type, name: String
    ) throws -> Value {
        guard let source = originalEraseC16SourceInputs[name],
              source.bytes.count <= Self.originalEraseC16SourceMaximum(name: name) else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let value = try CompatibilityCanonicalV1.decode(type, from: source.bytes)
        guard try CompatibilityCanonicalV1.encode(value) == source.bytes else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        if let plan = originalEraseC16ReferencePlan {
            guard let binding = plan.markerBindings.first(where: { $0.name == name }),
                  try CompatibilityCanonicalV1.sha256(source.bytes) == binding.sha256 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        } else if !originalEraseC16InitialSourceProof {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        return value
    }

'''+s[end:]
# Exact first-P source remains available after the finalized prepare is rewritten
# or the ordered tail removes it. Current physical state remains an observation.
start=s.index('    private func originalEraseC16ReferenceHygiene(')
end=s.index('    private func originalEraseC16IngressRecipe(',start)
s=s[:start]+'''    private func originalEraseC16ReferenceHygiene(
        name: String
    ) throws -> (initial: C16IngressHygienePrepareV1,
                 current: C16IngressHygienePrepareV1) {
        let initial = try originalEraseC16ReferenceValue(C16IngressHygienePrepareV1.self, name: name)
        try initial.validate()
        let file = try protectedIngressReceiptDirectory().appendingPathComponent(name)
        guard try ingressControlFileExists(file) else { return (initial, initial) }
        let current = try readProtectedIngressPrepare(at: file)
        guard current == initial || (!initial.finalized && current == initial.finalizing()) else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        return (initial, current)
    }

'''+s[end:]
p.write_text(s)

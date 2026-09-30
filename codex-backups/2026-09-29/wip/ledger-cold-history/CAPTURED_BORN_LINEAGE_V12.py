from pathlib import Path
import hashlib, json
packet = Path(__file__).parent
path = packet / 'candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift'
source = path.read_text(); before = hashlib.sha256(path.read_bytes()).hexdigest()
anchor = '    @MainActor\n    func originalEraseC16ExpectedTree('
helper = '''    @MainActor private func originalEraseC16CurrentRecordSnapshot(
        plan: OriginalEraseC16PlanV1, ordinal: Int
    ) throws -> (recordBindingSHA256: String, logicalProgressSHA256: String,
        progress: OriginalEraseC16ReferenceProgressV1) {
        try requireScratchDescriptorAccess()
        guard let permit = originalEraseColdPermit, !plan.steps.isEmpty else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let current = try permit.requireC16CurrentRecordBinding(
            planSHA256: CompatibilityCanonicalV1.sha256(CompatibilityCanonicalV1.encode(plan)),
            ordinal: ordinal)
        try current.progress.validate(plan: plan)
        let actualOrdinal = current.progress.activeC16Ordinal
            ?? min(current.progress.completedC16PrefixCount, plan.steps.count - 1)
        guard actualOrdinal == ordinal else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        return current
    }

    @MainActor private func originalEraseC16RequirePostPBornLineage(
        plan: OriginalEraseC16PlanV1, ordinal: Int, name: String,
        role: OriginalEraseC16CanonicalRoleV1, bytes: Data,
        fullFact: String, sha256: String,
        current: (recordBindingSHA256: String, logicalProgressSHA256: String,
            progress: OriginalEraseC16ReferenceProgressV1)
    ) throws {
        try requireScratchDescriptorAccess()
        guard let permit = originalEraseColdPermit, role.bytes == bytes,
              try CompatibilityCanonicalV1.sha256(bytes) == sha256 else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let slot = try originalEraseC16FixedBornProducerSlot(plan: plan,
            currentOrdinal: ordinal, name: name, role: role)
        if let retained = try permit.canonicalCapturedBornSource(slot: slot) {
            guard retained.bytes == bytes, retained.fullFact == fullFact,
                  try CompatibilityCanonicalV1.sha256(retained.bytes) == sha256 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        } else {
            // A genuine crash may leave this exact deterministic birth before
            // its capture CAS. The fresh actual Store record permits only the
            // active producer's finite preparing cut. The typed boundary must
            // capture/read back it before another engine advance or loss.
            guard slot.producerOrdinal == ordinal,
                  current.progress.activeC16Ordinal == ordinal,
                  current.progress.recordStage == .preparing
                    || current.progress.recordStage == .preparingCaptured else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        }
        let after = try originalEraseC16CurrentRecordSnapshot(plan: plan, ordinal: ordinal)
        guard after.recordBindingSHA256 == current.recordBindingSHA256,
              after.logicalProgressSHA256 == current.logicalProgressSHA256,
              after.progress == current.progress else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
    }

'''
assert source.count(anchor) == 1
source = source.replace(anchor, helper + anchor, 1)
start = source.index(anchor)
end = source.index('    private func originalEraseC16FinalControlRoleNames(', start)
chunk = source[start:end]
needle = '''        let observed = try requireOriginalEraseC16ObservedProjection(plan: plan, currentOrdinal: currentOrdinal,'''
replacement = '''        let currentRecord = try originalEraseC16CurrentRecordSnapshot(plan: plan, ordinal: currentOrdinal)
        let observed = try requireOriginalEraseC16ObservedProjection(plan: plan, currentOrdinal: currentOrdinal,'''
assert chunk.count(needle) == 1; chunk = chunk.replace(needle, replacement, 1)
chunk = chunk.replace('''                    for (finalName, role) in roles {
                        if try''', '''                    for (finalName, role) in roles where role.role != "finalizedHygienePrepare" {
                        if try''', 1)
needle = '''                    guard let role = selected,
                          let leaf = try'''
replacement = '''                    guard let role = selected, role.producerOrdinal == currentOrdinal,
                          currentRecord.progress.activeC16Ordinal == currentOrdinal,
                          currentRecord.progress.recordStage == .preparing
                            || currentRecord.progress.recordStage == .preparingCaptured,
                          let leaf = try'''
assert chunk.count(needle) == 1; chunk = chunk.replace(needle, replacement, 1)
needle = '''                    let fact = Self.originalEraseSourceFullFact(leaf.0)
                    if let captured'''
replacement = '''                    let fact = Self.originalEraseSourceFullFact(leaf.0)
                    try originalEraseC16RequirePostPBornLineage(plan: plan, ordinal: currentOrdinal,
                        name: name, role: role, bytes: leaf.1, fullFact: fact, sha256: sha,
                        current: currentRecord)
                    if let captured'''
assert chunk.count(needle) == 1; chunk = chunk.replace(needle, replacement, 1)
needle = '''        try requireOriginalEraseBorrowedOwner()
        return .init(currentOrdinal: currentOrdinal'''
replacement = '''        let finalRecord = try originalEraseC16CurrentRecordSnapshot(plan: plan, ordinal: currentOrdinal)
        guard finalRecord.recordBindingSHA256 == currentRecord.recordBindingSHA256,
              finalRecord.logicalProgressSHA256 == currentRecord.logicalProgressSHA256,
              finalRecord.progress == currentRecord.progress else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try requireOriginalEraseBorrowedOwner()
        return .init(currentOrdinal: currentOrdinal'''
assert chunk.count(needle) == 1; chunk = chunk.replace(needle, replacement, 1)
source = source[:start] + chunk + source[end:]
# The finalized prepare is born by the checked rename of the distinct staged
# role, never by a second publishDurably temporary channel at that final path.
start = source.index('    func originalEraseC16CurrentObservationScope(')
end = source.index('    /// A policy observation is local data', start)
chunk = source[start:end]
needle = '''            for (name, candidate) in candidates.sorted(by: { $0.key < $1.key }) {
                let temporary'''
replacement = '''            for (name, candidate) in candidates.sorted(by: { $0.key < $1.key }) {
                guard candidate.role != "finalizedHygienePrepare" else { continue }
                let temporary'''
assert chunk.count(needle) == 1; chunk = chunk.replace(needle, replacement, 1)
source = source[:start] + chunk + source[end:]
start = source.index('    private func originalEraseC16RequireControlPublicationPrefix(')
end = source.index('    private func originalEraseC16FixedBornProducerSlot(', start)
chunk = source[start:end]
needle = '''            let temp = try readOriginalErasePublicationLeaf(named: temporary, parent: parent, maximumBytes: role.bytes.count)
            if completed {'''
replacement = '''            let temp = try readOriginalErasePublicationLeaf(named: temporary, parent: parent, maximumBytes: role.bytes.count)
            if role.role == "finalizedHygienePrepare", temp != nil {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            if completed {'''
assert chunk.count(needle) == 1; chunk = chunk.replace(needle, replacement, 1)
source = source[:start] + chunk + source[end:]
path.write_text(source)
(packet/'CAPTURED_BORN_LINEAGE_V12.json').write_text(json.dumps({'before':before,'after':hashlib.sha256(path.read_bytes()).hexdigest(),'capturedGetterContract':'7da5496de5321bf772b7cac989df424d24fd584edbb343278899f0d254e95c37','freshRecordContract':'e2f4dc2b3267ba1b84733c309cb6cd0552aa1e8ce9a46b836844ba7b11a6a3c1','status':'working; syntax, actual callbacks, compilation/review/runtime due'},indent=2)+'\n')

from pathlib import Path
import hashlib, json

packet = Path(__file__).parent
path = packet / 'candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift'
source = path.read_text()
before = hashlib.sha256(path.read_bytes()).hexdigest()
anchor = '    private func originalEraseC16TargetCut(\n'
assert source.count(anchor) == 1
helper = '''    /// A prior fixed partial settlement changes only that exact first-P
    /// member. Original marker bytes stay immutable; later H/E deletion uses
    /// this derived member list instead of selecting current survivors.
    private func originalEraseC16RemainingTargetFiles(
        _ target: OriginalEraseC16TargetFactV1,
        includeCurrentPartial: Bool = false
    ) throws -> [OriginalEraseC16FileFactV1] {
        try requireScratchDescriptorAccess()
        guard originalEraseBorrowedExclusiveCheck != nil else { return target.files }
        guard let plan = originalEraseC16ReferencePlan else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let ordinal = originalEraseC16CurrentOrdinal
            ?? originalEraseC16AdmissionProgress?.completedC16PrefixCount ?? 0
        guard ordinal >= 0, ordinal <= plan.steps.count else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        var removed = Set<String>()
        for (index, step) in plan.steps.enumerated() {
            guard index < ordinal || (includeCurrentPartial && index == ordinal),
                  case let .settleFirstPPartial(.lease(lease), name, device, inode, byteCount) = step,
                  lease == target.directoryName,
                  let file = target.files.first(where: { $0.name == name }) else { continue }
            guard file.device == device, file.inode == inode,
                  file.byteCount == byteCount,
                  let firstP = originalEraseC16FirstPFacts["ScratchDataV1/" + lease + "/" + name] else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            let fact = try OriginalEraseC16PhysicalFactV1(firstP)
            guard fact.device == device, fact.inode == inode,
                  fact.byteCount == byteCount,
                  fact.modifiedSeconds == file.modifiedSeconds,
                  fact.modifiedNanoseconds == file.modifiedNanoseconds else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            guard removed.insert(name).inserted else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        }
        return target.files.filter { !removed.contains($0.name) }
    }

'''
# Use the already exact nine-field parser's actual names below.
source = source.replace(anchor, helper + anchor, 1)
old = '''            let physicalNames = try directoryNames(descriptor)
            let extras = physicalNames.filter { !target.files.map(\\.name).contains($0) }'''
new = '''            let physicalNames = try directoryNames(descriptor)
            var expectedFiles = try originalEraseC16RemainingTargetFiles(target)
            if let plan = originalEraseC16ReferencePlan,
               let ordinal = originalEraseC16CurrentOrdinal ?? originalEraseC16AdmissionProgress?.activeC16Ordinal,
               ordinal < plan.steps.count,
               case let .settleFirstPPartial(.lease(lease), child, _, _, _) = plan.steps[ordinal],
               lease == target.directoryName, !physicalNames.contains(child) {
                expectedFiles = try originalEraseC16RemainingTargetFiles(target, includeCurrentPartial: true)
            }
            let extras = physicalNames.filter { !expectedFiles.map(\\.name).contains($0) }'''
assert source.count(old) == 1
source = source.replace(old, new, 1)
start = source.index(anchor)
end = source.index('    /// A claimed-only directory', start)
chunk = source[start:end]
chunk = chunk.replace('let removed = target.files.count - names.count', 'let removed = expectedFiles.count - names.count')
chunk = chunk.replace('names == Array(target.files.map(\\.name)', 'names == Array(expectedFiles.map(\\.name)')
chunk = chunk.replace('guard value == target.files[removed + index]', 'guard value == expectedFiles[removed + index]')
source = source[:start] + chunk + source[end:]
start = source.index('    private func validatePreparedIngressTargetForRecovery(')
end = source.index('    private func removePreparedIngressTarget(', start)
chunk = source[start:end]
chunk = chunk.replace('        let actual = try ingressHygieneFileIdentities(name: name, descriptor: descriptor)', '''        let expectedFiles = try originalEraseC16RemainingTargetFiles(.init(target))
            .map(C16IngressHygieneFileIdentityV1.init)
        let priorFixedPartialSettlement = expectedFiles != target.files
        let actual = try ingressHygieneFileIdentities(name: name, descriptor: descriptor)''')
chunk = chunk.replace('guard modified == target.modifiedAt, actual == target.files', 'guard (priorFixedPartialSettlement || modified == target.modifiedAt), actual == expectedFiles')
chunk = chunk.replace('? actual == Array(target.files.suffix(actual.count))', '? actual == Array(expectedFiles.suffix(actual.count))')
source = source[:start] + chunk + source[end:]
start = source.index('    private func c16OwnedTargetSteps(')
end = source.index('    private func readProtectedIngressPrepare(', start)
chunk = source[start:end]
chunk = chunk.replace('            let actual = try self.ingressHygieneFileIdentities(name: name, descriptor: descriptor)', '''            let fixedTarget = OriginalEraseC16TargetFactV1(directoryName: originalName,
                device: device, inode: inode, files: files)
            let expectedFiles = try self.originalEraseC16RemainingTargetFiles(fixedTarget)
                .map(C16IngressHygieneFileIdentityV1.init)
            let priorFixedPartialSettlement = expectedFiles != files
            let actual = try self.ingressHygieneFileIdentities(name: name, descriptor: descriptor)''')
chunk = chunk.replace('guard (modifiedAt == nil || modified == modifiedAt), actual == files', 'guard (priorFixedPartialSettlement || modifiedAt == nil || modified == modifiedAt), actual == expectedFiles')
chunk = chunk.replace('descriptor: descriptor) == files', 'descriptor: descriptor) == expectedFiles')
chunk = chunk.replace('? actual == Array(files.suffix(actual.count))', '? actual == Array(expectedFiles.suffix(actual.count))')
chunk = chunk.replace('descriptor: descriptor, expectedFiles: files)', 'descriptor: descriptor, expectedFiles: expectedFiles)')
source = source[:start] + chunk + source[end:]
old = '            let children = Array(target.source.files.dropFirst(removed))'
new = '''            let remainingSource = try originalEraseC16RemainingTargetFiles(target.source,
                includeCurrentPartial: observed.currentCut == .terminal)
            let settledNames = Set(target.source.files.map(\\.name))
                .subtracting(remainingSource.map(\\.name))
            for child in settledNames { consumed.insert(firstPPath + "/" + child) }
            let children = Array(remainingSource.dropFirst(removed))'''
assert source.count(old) == 1
source = source.replace(old, new, 1)
source = source.replace('for file in target.source.files.prefix(removed) { consumed.insert(firstPPath + "/" + file.name) }', 'for file in remainingSource.prefix(removed) { consumed.insert(firstPPath + "/" + file.name) }', 1)
path.write_text(source)
(packet / 'FIXED_PARTIAL_TARGET_PROJECTION_V9.json').write_text(json.dumps({'before': before, 'after': hashlib.sha256(path.read_bytes()).hexdigest(), 'status':'working, syntax/compile/review due'}, indent=2)+'\n')

from pathlib import Path
import hashlib,json
packet=Path(__file__).parent
path=packet/'candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift'
source=path.read_text();before=hashlib.sha256(path.read_bytes()).hexdigest()
start=source.index('    /// A prior fixed partial settlement changes only that exact first-P')
end=source.index('    private func originalEraseC16TargetCut(',start)
source=source[:start]+source[end:]
start=source.index('    private func originalEraseC16TargetCut(')
end=source.index('    /// A claimed-only directory',start)
chunk=source[start:end]
a=chunk.index('            var expectedFiles = try originalEraseC16RemainingTargetFiles(target)')
b=chunk.index('            let extras = physicalNames.filter',a)
chunk=chunk[:a]+chunk[b:]
chunk=chunk.replace('let extras = physicalNames.filter { !expectedFiles.map(\\.name).contains($0) }','let extras = physicalNames.filter { !target.files.map(\\.name).contains($0) }')
chunk=chunk.replace('let removed = expectedFiles.count - names.count','let removed = target.files.count - names.count')
chunk=chunk.replace('names == Array(expectedFiles.map(\\.name)','names == Array(target.files.map(\\.name)')
chunk=chunk.replace('guard value == expectedFiles[removed + index]','guard value == target.files[removed + index]')
source=source[:start]+chunk+source[end:]
start=source.index('    private func validatePreparedIngressTargetForRecovery(')
end=source.index('    private func removePreparedIngressTarget(',start)
chunk=source[start:end]
chunk=chunk.replace('''        let expectedFiles = try originalEraseC16RemainingTargetFiles(.init(target))
            .map(C16IngressHygieneFileIdentityV1.init)
        let priorFixedPartialSettlement = expectedFiles != target.files
''','')
chunk=chunk.replace('guard (priorFixedPartialSettlement || modified == target.modifiedAt), actual == expectedFiles','guard modified == target.modifiedAt, actual == target.files')
chunk=chunk.replace('? actual == Array(expectedFiles.suffix(actual.count))','? actual == Array(target.files.suffix(actual.count))')
source=source[:start]+chunk+source[end:]
start=source.index('    private func c16OwnedTargetSteps(')
end=source.index('    private func readProtectedIngressPrepare(',start)
chunk=source[start:end]
chunk=chunk.replace('''            let fixedTarget = OriginalEraseC16TargetFactV1(directoryName: originalName,
                device: device, inode: inode, files: files)
            let expectedFiles = try self.originalEraseC16RemainingTargetFiles(fixedTarget)
                .map(C16IngressHygieneFileIdentityV1.init)
            let priorFixedPartialSettlement = expectedFiles != files
''','')
chunk=chunk.replace('guard (priorFixedPartialSettlement || modifiedAt == nil || modified == modifiedAt), actual == expectedFiles','guard (modifiedAt == nil || modified == modifiedAt), actual == files')
chunk=chunk.replace('descriptor: descriptor) == expectedFiles','descriptor: descriptor) == files')
chunk=chunk.replace('? actual == Array(expectedFiles.suffix(actual.count))','? actual == Array(files.suffix(actual.count))')
chunk=chunk.replace('descriptor: descriptor, expectedFiles: expectedFiles)','descriptor: descriptor, expectedFiles: files)')
source=source[:start]+chunk+source[end:]
old='''            let remainingSource = try originalEraseC16RemainingTargetFiles(target.source,
                includeCurrentPartial: observed.currentCut == .terminal)
            let settledNames = Set(target.source.files.map(\\.name))
                .subtracting(remainingSource.map(\\.name))
            for child in settledNames { consumed.insert(firstPPath + "/" + child) }
            let children = Array(remainingSource.dropFirst(removed))'''
assert source.count(old)==1
source=source.replace(old,'            let children = Array(target.source.files.dropFirst(removed))',1)
source=source.replace('for file in remainingSource.prefix(removed) { consumed.insert(firstPPath + "/" + file.name) }','for file in target.source.files.prefix(removed) { consumed.insert(firstPPath + "/" + file.name) }',1)
assert 'originalEraseC16RemainingTargetFiles' not in source
assert 'priorFixedPartialSettlement' not in source
path.write_text(source)
(packet/'REMOVE_UNREACHABLE_PARTIAL_TARGET_RELAXATION_V13.json').write_text(json.dumps({'before':before,'after':hashlib.sha256(path.read_bytes()).hexdigest(),'reason':'Actual original-P planner already excludes canonical C16 target-owned partial facts from independent settlement steps. Preserve original mtime/member predicates; do not retain unsupported relaxation. V9 proposal/parse artifacts preserved.'},indent=2)+'\n')

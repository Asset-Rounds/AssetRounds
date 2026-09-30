from pathlib import Path
p=Path('.codex-temp/cold-ledger-continuation-successor-v1/candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift');s=p.read_text()
a='    fileprivate init(_ value: C16IngressHygieneFileIdentityV1) {'
s=s.replace(a,'''    fileprivate init(name: String, device: UInt64, inode: UInt64,
        byteCount: Int64, modifiedSeconds: Int64, modifiedNanoseconds: Int64) {
        self.name = name; self.device = device; self.inode = inode
        self.byteCount = byteCount; self.modifiedSeconds = modifiedSeconds
        self.modifiedNanoseconds = modifiedNanoseconds
    }

'''+a,1)
a='    init(name: String, information: stat) {'
s=s.replace(a,'''    init(_ value: OriginalEraseC16FileFactV1) {
        name = value.name; device = value.device; inode = value.inode
        byteCount = value.byteCount; modifiedSeconds = value.modifiedSeconds
        modifiedNanoseconds = value.modifiedNanoseconds
    }

'''+a,1)
a='    static func < (lhs: Self, rhs: Self) -> Bool { lhs.directoryName < rhs.directoryName }'
s=s.replace(a,'''    init(directoryName: String, modifiedAt: Date, device: UInt64, inode: UInt64,
        files: [C16IngressHygieneFileIdentityV1]) throws {
        guard OwnedStorageLedgerV1.isConfidentScratchLeaseDirectoryName(directoryName),
              modifiedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        self.directoryName = directoryName; self.modifiedAt = modifiedAt
        self.device = device; self.inode = inode; self.files = files
    }

'''+a,1)
a='    private struct OriginalEraseC16IngressRecipeV1 {'
s=s.replace(a,Path('.codex-temp/cold-ledger-continuation-successor-v1/CLAIM_ONLY_FRAGMENT.swift').read_text()+'\n'+a,1)
a='''                } else {
                    let descriptor = try validateIngressClaim(claim)
                    try closeObservedScratchDescriptor(descriptor)
                }
                unresolvedPreparations.append(preparation)'''
b='''                } else if originalEraseBorrowedExclusiveCheck != nil {
                    _ = try originalEraseC16ClaimOnlySource(preparation: preparation, claim: claim)
                } else {
                    let descriptor = try validateIngressClaim(claim)
                    try closeObservedScratchDescriptor(descriptor)
                }
                unresolvedPreparations.append(preparation)'''
assert a in s;s=s.replace(a,b,1)
start=s.index('            let descriptor = try validateIngressClaim(claim)',s.index('        var freshUnpublishedTargets:'))
end=s.index('            freshUnpublishedTargets.append(',start)
s=s[:start]+'''            let fixedTarget = try originalEraseC16ClaimOnlySource(preparation: preparation, claim: claim)
            guard let directory = fixedTarget.directory else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            let target = OriginalEraseC16TargetFactV1(directory)
'''+s[end:]
start=s.index('    private func makeUnpublishedIngressEraseTarget(')
# Put borrowed path before the ordinary tombstone refusal, after exact claim read.
a='''        let name = preparation.lease.relativeDirectory
        guard try directoryInformationIfPresent(named: Self.deletionTombstoneName(for: name)) == nil else {'''
pos=s.index(a,start)
s=s[:pos]+'''        if originalEraseBorrowedExclusiveCheck != nil,
           let claim = try readIngressControl(C16IngressDirectoryClaimV1.self,
               at: ingressControlURL(id, ".claim.json")) {
            return try originalEraseC16ClaimOnlySource(preparation: preparation, claim: claim)
        }
'''+s[pos:]
start=s.index('            var sawLive = false\n            var sawIntermediate = false\n',s.index('    private func originalEraseC16PhysicalCutPrimitive'))
end=s.index('            let receipt = try protectedIngressReceiptFile(',start)
s=s[:start]+'''            let groupCut = try originalEraseC16HygieneGroupCut(prepare)
'''+s[end:]
s=s.replace('''                guard !sawLive,
                      try readProtectedIngressReceipt''','''                guard groupCut != .preimage,
                      try readProtectedIngressReceipt''',1)
s=s.replace('            return sawIntermediate ? .intermediate : .preimage\n','            return groupCut\n',1)
start=s.index('            var sawLive = false\n            for item in prepare.targets {',s.index('    private func originalEraseC16IngressRecipe'))
end=s.index('            let ordinal: Int?\n',start)
s=s[:start]+'''            _ = try originalEraseC16HygieneGroupCut(source.current)
'''+s[end:]
s=s.replace('receipt == prepare.receipt(), !sawLive','receipt == (try prepare.receipt()), !sawLive')
p.write_text(s)

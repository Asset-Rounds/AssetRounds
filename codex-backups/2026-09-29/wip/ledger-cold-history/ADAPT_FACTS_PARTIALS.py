from pathlib import Path
p=Path('.codex-temp/cold-ledger-continuation-successor-v1/candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift');s=p.read_text()
start=s.index('    private struct OriginalEraseC16PhysicalFactV1 {')
end=s.index('    @MainActor private func primeOriginalEraseC16ImmutableInputs',start)
s=s[:start]+'''    private struct OriginalEraseC16PhysicalFactV1 {
        let device: UInt64
        let inode: UInt64
        let mode: UInt64
        let uid: UInt64?
        let gid: UInt64?
        let linkCount: UInt64
        let byteCount: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        init(_ text: String) throws {
            let fields = text.split(separator: "|", omittingEmptySubsequences: false)
            // Node.fact is the unchanged persisted nine-field roster format.
            // A transferred source's real held full fact has eleven fields.
            // Missing uid/gid are never synthesized into an original-P fact.
            guard fields.count == 9 || fields.count == 11 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            let offset = fields.count == 11 ? 2 : 0
            guard let device = UInt64(fields[0]), let inode = UInt64(fields[1]),
                  let mode = UInt64(fields[2]), let links = UInt64(fields[3 + offset]),
                  let bytes = Int64(fields[4 + offset]), let seconds = Int64(fields[5 + offset]),
                  let nanos = Int64(fields[6 + offset]), Int64(fields[7 + offset]) != nil,
                  Int64(fields[8 + offset]) != nil, inode != 0, nanos >= 0,
                  nanos < 1_000_000_000 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            self.device = device; self.inode = inode; self.mode = mode
            uid = fields.count == 11 ? UInt64(fields[3]) : nil
            gid = fields.count == 11 ? UInt64(fields[4]) : nil
            guard fields.count == 9 || (uid != nil && gid != nil) else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            linkCount = links; byteCount = bytes
            modifiedSeconds = seconds; modifiedNanoseconds = nanos
        }
        func matches(_ file: OriginalEraseC16FileFactV1) -> Bool {
            device == file.device && inode == file.inode && byteCount == file.byteCount
                && modifiedSeconds == file.modifiedSeconds
                && modifiedNanoseconds == file.modifiedNanoseconds
                && mode & UInt64(S_IFMT) == UInt64(S_IFREG) && linkCount == 1
                && (uid == nil || uid == UInt64(Darwin.geteuid()))
                && (gid == nil || gid == UInt64(Darwin.getegid()))
        }
        var modifiedAt: Date {
            Date(timeIntervalSince1970: TimeInterval(modifiedSeconds)
                + TimeInterval(modifiedNanoseconds) / 1_000_000_000)
        }
    }

    private static func originalEraseC16NineFieldFact(_ value: stat) -> String {
        "\\(value.st_dev)|\\(value.st_ino)|\\(value.st_mode)|\\(value.st_nlink)|\\(value.st_size)|\\(value.st_mtimespec.tv_sec)|\\(value.st_mtimespec.tv_nsec)|\\(value.st_ctimespec.tv_sec)|\\(value.st_ctimespec.tv_nsec)"
    }

'''+s[end:]
s=s.replace('''        for name in names {
            try permit.requireHeld()
            let path = "ProtectedIngressReceiptsV1/" + name''','''        for name in names {
            guard !name.hasPrefix(".partial-") else { continue }
            try permit.requireHeld()
            let path = "ProtectedIngressReceiptsV1/" + name''',1)
s=s.replace('''                      Self.originalEraseSourceFullFact(leaf.0) == originalFact''','''                      Self.originalEraseC16NineFieldFact(leaf.0) == originalFact''',1)
s=s.replace('''                input = .init(bytes: leaf.1, fullFact: originalFact)''','''                input = .init(bytes: leaf.1, fullFact: Self.originalEraseSourceFullFact(leaf.0))''',1)
start=s.index('        for name in names {\n            var named = stat()',s.index('    func originalEraseC16PlanFromFirstP('))
s=s[:start]+s[start:].replace('''                  named.st_size <= 32 * 1_024 * 1_024,
                  named.st_nlink == 1 || named.st_nlink == 2 else {''','''                  named.st_size <= (name.hasPrefix(".partial-") ? 1_024 * 1_024 * 1_024
                    : Int64(Self.originalEraseC16SourceMaximum(name: name))),
                  named.st_nlink == 1 || named.st_nlink == 2 else {''',1)
pos=s.index('            let data: Data\n',start)
s=s[:pos]+'''            if name.hasPrefix(".partial-") {
                guard let permit = originalEraseColdPermit else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                try permit.requireHeld()
                let sha = try permit.originalPPhysicalSHA256(path: "ProtectedIngressReceiptsV1/" + name)
                guard CompatibilityCanonicalV1.validSHA256(sha) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                let binding = OriginalEraseC16MarkerBindingV1(name: name, sha256: sha,
                    targets: [], targetIntentIDs: [], unpublishedTargetCount: 0, controlFiles: [])
                let charge = retainedEncodedBytes.addingReportingOverflow(try CompatibilityCanonicalV1.encode(binding).count)
                guard !charge.overflow, charge.partialValue <= OriginalEraseC16PlanV1.maximumEncodedBytes else {
                    throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
                }
                retainedEncodedBytes = charge.partialValue; bindings.append(binding)
                try permit.requireHeld()
                continue
            }
'''+s[pos:]
p.write_text(s)

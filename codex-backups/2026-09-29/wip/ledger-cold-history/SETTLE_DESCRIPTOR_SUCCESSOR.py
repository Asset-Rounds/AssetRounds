from pathlib import Path
p=Path('.codex-temp/cold-ledger-continuation-successor-v1/candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift')
s=p.read_text()
a=s.index('    private func closeObservedScratchDescriptor(_ descriptor: Int32) throws {')
b=s.index('    private func withObservedScratchDescriptor<Value>',a)
s=s[:a]+'''    private func closeObservedScratchDescriptor(_ descriptor: Int32) throws {
        try requireScratchDescriptorAccess()
        if exclusiveNoRepairRead {
            // The retained object is the close attempt. An old integer can
            // never acquire a second close attempt after terminal admission.
            guard let attempt = originalEraseObservedCloseAttempts[descriptor] else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            do { try originalEraseBorrowedExclusiveCheck?() }
            catch { originalEraseBorrowedLifetime = .uncertain; throw error }
            originalEraseObservedCloseAttempts.removeValue(forKey: descriptor)
            guard Darwin.close(descriptor) == 0 else {
                originalEraseBorrowedLifetime = .uncertain
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
            do { try originalEraseBorrowedExclusiveCheck?() }
            catch { originalEraseBorrowedLifetime = .uncertain; throw error }
        } else {
            _ = Darwin.close(descriptor)
        }
    }

''' +s[b:]
a=s.index('    private func directoryNames(_ descriptor: Int32) throws -> [String] {')
b=s.index('    private func regularFileInformation(',a)
s=s[:a]+'''    private func directoryNames(_ descriptor: Int32) throws -> [String] {
        try requireScratchDescriptorAccess()
        try originalEraseBorrowedExclusiveCheck?()
        let duplicate = Darwin.dup(descriptor)
        guard duplicate >= 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        retainOriginalEraseObservedDescriptor(duplicate)
        guard let directory = Darwin.fdopendir(duplicate) else {
            try closeObservedScratchDescriptor(duplicate)
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        var closeAttempted = false
        func closeDirectory() throws {
            guard !closeAttempted else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
            try requireScratchDescriptorAccess()
            if exclusiveNoRepairRead {
                guard let attempt = originalEraseObservedCloseAttempts[duplicate] else {
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                do { try originalEraseBorrowedExclusiveCheck?() }
                catch { originalEraseBorrowedLifetime = .uncertain; throw error }
                // fdopendir owns this exact duplicate. Never ask dirfd for a
                // numeric alias after a closedir admission, including failure.
                closeAttempted = true
                originalEraseObservedCloseAttempts.removeValue(forKey: duplicate)
                guard Darwin.closedir(directory) == 0 else {
                    originalEraseBorrowedLifetime = .uncertain
                    throw ScratchDataLeaseStoreFailureV1.invalidRoot
                }
                ScratchUncertainCloseQuarantineV1.shared.complete(attempt)
                do { try originalEraseBorrowedExclusiveCheck?() }
                catch { originalEraseBorrowedLifetime = .uncertain; throw error }
            } else { closeAttempted = true; _ = Darwin.closedir(directory) }
        }
        defer { if !closeAttempted { try? closeDirectory() } }
        // dup shares the directory offset with the retained descriptor.
        Darwin.rewinddir(directory)
        var names: [String] = []
        errno = 0
        while let entry = Darwin.readdir(directory) {
            guard let name = OwnedStorageDirectoryEntryNameV1.decode(entry) else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            if name == "." || name == ".." { continue }
            guard OperationalDiagnosticsBoundsV1.validRelativeName(name) else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            if exclusiveNoRepairRead, names.count >= 100_000 {
                throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
            }
            names.append(name)
        }
        guard errno == 0 else { throw ScratchDataLeaseStoreFailureV1.invalidRoot }
        try closeDirectory()
        return names.sorted()
    }

''' +s[b:]
# A pair is admitted by the exact private PFP scope above, not by this reader.
a=s.index('    private func readRegularFile(');b=s.index('    private func readOriginalErasePublicationLeaf(',a)
r=s[a:b]
r=r.replace('after.st_nlink == 1,','after.st_nlink == expected.st_nlink,').replace('linked.st_nlink == 1,','linked.st_nlink == expected.st_nlink,')
da=r.index('        defer {');db=r.index('        var pinned = stat()',da)
r=r[:da]+'''        defer { if !closeAttempted { try? closeObservedScratchDescriptor(descriptor) } }
'''+r[db:]
ca=r.index('        if exclusiveNoRepairRead {\n            closeAttempted = true',da);cb=r.index('        return result',ca)
r=r[:ca]+'''        if exclusiveNoRepairRead {
            closeAttempted = true
            try closeObservedScratchDescriptor(descriptor)
        }
'''+r[cb:]
s=s[:a]+r+s[b:]
a=s.index('    private func readOriginalErasePublicationLeaf(');b=s.index('    private enum OriginalErasePublicationCutV1',a)
r=s[a:b]
da=r.index('        defer {');db=r.index('        var heldBefore = stat()',da)
r=r[:da]+'''        defer { if !closeAttempted { try? closeObservedScratchDescriptor(descriptor) } }
'''+r[db:]
ca=r.index('        closeAttempted = true\n',da);cb=r.index('        return (heldBefore, bytes)',ca)
r=r[:ca]+'''        closeAttempted = true
        try closeObservedScratchDescriptor(descriptor)
'''+r[cb:]
s=s[:a]+r+s[b:]
# Initial roles come from complete immutable P paths, not current survivors.
s=s.replace('''            let namesResult = Result { try directoryNames(parent) }
''','''            let namesResult = Result { try permit.originalPPhysicalPaths(prefix: prefix).map {
                String($0.dropFirst(prefix.count))
            }.filter { !$0.contains("/") } }
''',1)
# Once openLeaseDirectory installs ownership, any getter failure must settle
# through the checked owner (or retain it if proof no longer holds).
s=s.replace('''            guard let originalPartial = try permit.originalPPhysicalFact(path: prefix + name) else {
                if needsClose { try closeObservedScratchDescriptor(parent) }
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
''','''            let originalPartial: String
            do {
                guard let value = try permit.originalPPhysicalFact(path: prefix + name) else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                originalPartial = value
            } catch { if needsClose { try closeObservedScratchDescriptor(parent) }; throw error }
''',1)
# Open-validation failure consumes the existing attempt only once.
s=s.replace('''                let attempt = originalEraseObservedCloseAttempts.removeValue(forKey: descriptor)
                    ?? ScratchUncertainCloseQuarantineV1.shared.begin(descriptor)
                if Darwin.close(descriptor) == 0 { ScratchUncertainCloseQuarantineV1.shared.complete(attempt) }
                else { originalEraseBorrowedLifetime = .uncertain }
''','''                try closeObservedScratchDescriptor(descriptor)
''',1)
p.write_text(s)

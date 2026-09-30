from pathlib import Path
p=Path('.codex-temp/cold-ledger-continuation-successor-v1/candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift');s=p.read_text()
a=s.index('    @MainActor private func originalEraseNoRepairSemanticAdmission()');b=s.index('    /// A preexisting `scratch-erase.json`',a);r=s[a:b]
r=r.replace('''            let closeAttempt = ScratchUncertainCloseQuarantineV1.shared.begin(
                descriptor)
''','',1)
r=r.replace('''                try ProtectedFilePolicyV1
                    .verifyEraseColdPrivateWithCheckedClose(.temporaryFile,
                        at: metadataURL, retainUncertainDescriptor: {
                            _ = ScratchUncertainCloseQuarantineV1.shared.begin($0)
                        })
''','''                try verifySourceReadPolicy(.temporaryFile, at: metadataURL)
''',1)
r=r.replace('''            } catch {
                if Darwin.close(descriptor) == 0 {
                    ScratchUncertainCloseQuarantineV1.shared.complete(
                        closeAttempt)
                }
                throw error
            }
            guard Darwin.close(descriptor) == 0 else {
                throw ScratchDataLeaseStoreFailureV1.invalidRoot
            }
            ScratchUncertainCloseQuarantineV1.shared.complete(closeAttempt)
''','''            } catch {
                try closeObservedScratchDescriptor(descriptor)
                throw error
            }
            try closeObservedScratchDescriptor(descriptor)
''',1)
s=s[:a]+r+s[b:]
a=s.index('    private func protectedIngressReceiptDirectory()');b=s.index('    private func ingressControlDescriptor()',a);r=s[a:b]
r=r.replace('''            if originalEraseBorrowedExclusiveCheck != nil {
                try ProtectedFilePolicyV1.verifyEraseColdPrivateWithCheckedClose(''','''            if originalEraseBorrowedExclusiveCheck != nil {
                // Retain the root owner before policy IO can fail. Its checked
                // settlement/quarantine stays with the actual outer operation.
                ingressControlAuthority = pinned
                try ProtectedFilePolicyV1.verifyEraseColdPrivateWithCheckedClose(''',1)
r=r.replace('_ = ScratchUncertainCloseQuarantineV1.shared.begin($0)','originalEraseBorrowedLifetime = .uncertain\n                        _ = ScratchUncertainCloseQuarantineV1.shared.begin($0)')
s=s[:a]+r+s[b:]
a=s.index('    private func c16ControlEraseSteps(');b=s.index('    private func ',a+len('    private func c16ControlEraseSteps('));r=s[a:b]
r=r.replace('try ProtectedFilePolicyV1.verify(.temporaryFile, at:', 'try verifySourceReadPolicy(.temporaryFile, at:')
s=s[:a]+r+s[b:]
# The old private checked close also cannot be re-entered with verify=false.
a=s.index('    func closeCheckedForExclusiveOriginalEraseRead(');b=s.index('    @MainActor func closeCheckedForSchema2BorrowedScope(',a);r=s[a:b]
r=r.replace('''        if verifyBeforeClose { try verify(rootName: rootName) }
''','''        guard !rootCloseAttempted, !operationsCloseAttempted,
              rootDescriptor >= 0, operationsDescriptor >= 0 else {
            throw ScratchDataLeaseStoreFailureV1.invalidRoot
        }
        if verifyBeforeClose { try verify(rootName: rootName) }
''',1)
r=r.replace('''        rootCloseAttempted = true
''','''        rootCloseAttempted = true; rootDescriptor = -1
''',1).replace('''        operationsCloseAttempted = true
''','''        operationsCloseAttempted = true; operationsDescriptor = -1
''',1)
s=s[:a]+r+s[b:];p.write_text(s)

from pathlib import Path
p=Path('.codex-temp/cold-ledger-continuation-successor-v1/candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift');s=p.read_text()
a='    private var originalEraseC16SourceInputs: [String: OriginalEraseC16SourceInputV1] = [:]\n'
s=s.replace(a,a+'    private var originalEraseC16BornSourceInputs: [String: OriginalEraseC16SourceInputV1] = [:]\n',1)
a='                store.originalEraseC16SourceInputs.removeAll()\n';s=s.replace(a,a+'                store.originalEraseC16BornSourceInputs.removeAll()\n',1)
# Nonrecursive owner reproof belongs to local observations. The typed outer
# boundary and wrapper still demand complete whole-namespace proofs.
s=s.replace('store.originalEraseBorrowedOwnerCheck = { try permit.requireHeld() }','store.originalEraseBorrowedOwnerCheck = { try permit.requireObservationBinding() }',1)
a='        try permit.requireHeld()\n    }\n\n    @MainActor private func requireOriginalEraseC16TransferredInputs()'
b='''        if let plan, let progress = originalEraseC16AdmissionProgress {
            for (step, role, name) in [
                (OriginalEraseC16StepV1.eraseIngress, "freshIngressErasePrepare", "erase-" + originalEraseOperationID!.uuidString.lowercased() + ".prepare.json"),
                (OriginalEraseC16StepV1.eraseFinalControl, "scratchControlErase", Self.controlEraseName)
            ] {
                guard let ordinal = plan.steps.firstIndex(of: step) else { continue }
                if ordinal < progress.completedC16PrefixCount || (progress.activeC16Ordinal == ordinal && progress.recordStage == .preparingCaptured) {
                    try permit.requireObservationBinding()
                    let source = try permit.canonicalBornTransferredSource(path: "ProtectedIngressReceiptsV1/" + name, role: role)
                    guard source.bytes.count <= Self.originalEraseC16SourceMaximum(name: name) else {
                        throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
                    }
                    try permit.requireTransferredSource(path: "ProtectedIngressReceiptsV1/" + name,
                        bytes: source.bytes, fullFact: source.fullFact)
                    originalEraseC16BornSourceInputs[role + "|" + name] = .init(bytes: source.bytes, fullFact: source.fullFact)
                    try permit.requireObservationBinding()
                }
            }
        }
        try permit.requireHeld()
    }

    @MainActor private func requireOriginalEraseC16TransferredInputs()'''
assert a in s;s=s.replace(a,b,1)
a='''        }
    }

    private func originalEraseC16FirstPFact(path: String)'''
b='''        }
        for (key, source) in originalEraseC16BornSourceInputs.sorted(by: { $0.key < $1.key }) {
            guard let separator = key.firstIndex(of: "|") else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            let name = String(key[key.index(after: separator)...])
            try permit.requireTransferredSource(path: "ProtectedIngressReceiptsV1/" + name,
                bytes: source.bytes, fullFact: source.fullFact)
            try permit.requireHeld()
        }
    }

    private func originalEraseC16FirstPFact(path: String)'''
assert a in s;s=s.replace(a,b,1)
# Materialize a live fixed claim's date only after the current whole ordinal
# proof, before its control publication; captured E supplies it on later replay.
a='''        let target = try C16IngressHygieneTargetV1(directoryName: directoryName,
            modifiedAt: directory.modifiedAt, device: claim.device, inode: claim.inode,
            files: fixedFiles.map(C16IngressHygieneFileIdentityV1.init))'''
b='''        let modifiedAt: Date
        if !originalEraseC16InitialSourceProof,
           let actual = try directoryInformationIfPresent(named: directoryName) {
            guard UInt64(actual.st_dev) == claim.device, UInt64(actual.st_ino) == claim.inode else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            modifiedAt = Date(timeIntervalSince1970: TimeInterval(actual.st_mtimespec.tv_sec)
                + TimeInterval(actual.st_mtimespec.tv_nsec) / 1_000_000_000)
        } else { modifiedAt = directory.modifiedAt }
        let target = try C16IngressHygieneTargetV1(directoryName: directoryName,
            modifiedAt: modifiedAt, device: claim.device, inode: claim.inode,
            files: fixedFiles.map(C16IngressHygieneFileIdentityV1.init))'''
assert a in s;s=s.replace(a,b,1)
a='    /// Authenticated semantic cut observations.'
# Already global declaration; implementation fragment goes before existing
# fixed expected role names so all APIs remain within the sole store class.
a='    private func originalEraseC16FinalControlRoleNames('
pos=s.index(a)
s=s[:pos]+Path('.codex-temp/cold-ledger-continuation-successor-v1/FINITE_ROLES_FRAGMENT.swift').read_text()+'\n'+s[pos:]
p.write_text(s)

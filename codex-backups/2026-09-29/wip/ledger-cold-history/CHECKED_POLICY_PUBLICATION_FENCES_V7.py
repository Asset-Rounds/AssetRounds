from pathlib import Path
p=Path('.codex-temp/cold-ledger-continuation-successor-v1/candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift');s=p.read_text()
a=s.index('final class ScratchDataLeaseStoreV1:');b=s.index('    // Populated only by real returned in-process acquisitions',a)
r=s[a:b]
r=r.replace('_ = ScratchUncertainCloseQuarantineV1.shared.begin($0)','originalEraseBorrowedLifetime = .uncertain\n                    _ = ScratchUncertainCloseQuarantineV1.shared.begin($0)')
s=s[:a]+r+s[b:]
a=s.index('        private func closeOwnedDescriptor() throws {',s.index('private final class PublicationSessionV1'))
b=s.index('        /// One explicit close or ordinary legacy temp cleanup.',a)
s=s[:a]+'''        private func closeOwnedDescriptor() throws {
            try store.requireScratchDescriptorAccess()
            guard let owned = descriptor, !closeAttempted else { return }
            // Retire the owner's numeric alias before entering close, whether
            // the syscall succeeds or becomes uncertain. No second attempt.
            closeAttempted = true; descriptor = nil
            if borrowed { try store.closeObservedScratchDescriptor(owned) }
            else { _ = Darwin.close(owned) }
        }

'''+s[b:]
s=s.replace('''                descriptor = opened
                closeAttempted = false
                var held = stat(), named = stat()
                guard Darwin.fstat(opened, &held) == 0,
''','''                descriptor = opened
                store.retainOriginalEraseObservedDescriptor(opened)
                closeAttempted = false
                var held = stat(), named = stat(), heldParent = stat()
                guard Darwin.fstat(parent, &heldParent) == 0,
                      Darwin.fstat(opened, &held) == 0,
''',1)
s=s.replace('''                      held.st_uid == geteuid(), held.st_gid == getegid(),
                      UInt64(held.st_dev) == store.authority.rootDevice,
''','''                      held.st_uid == geteuid(),
                      held.st_gid == (heldParent.st_mode & S_ISGID == 0 ? getegid() : heldParent.st_gid),
                      UInt64(held.st_dev) == store.authority.rootDevice,
''',1)
s=s.replace('''                var held = stat(), named = stat()
                guard Darwin.fstat(descriptor, &held) == 0,
                      Darwin.fstatat(parent, temporaryName, &named, AT_SYMLINK_NOFOLLOW) == 0,
''','''                var held = stat(), named = stat(), heldParent = stat()
                guard Darwin.fstat(parent, &heldParent) == 0,
                      Darwin.fstat(descriptor, &held) == 0,
                      Darwin.fstatat(parent, temporaryName, &named, AT_SYMLINK_NOFOLLOW) == 0,
''',1)
s=s.replace('''                      held.st_gid == getegid(), named.st_gid == getegid(),
''','''                      held.st_gid == (heldParent.st_mode & S_ISGID == 0 ? getegid() : heldParent.st_gid),
                      named.st_gid == held.st_gid,
''',1)
a=s.index('    private func createPublicationTemporary(');b=s.index('    private func writePublicationChunk(',a)
r=s[a:b];r=r.replace('        return descriptor\n','        retainOriginalEraseObservedDescriptor(descriptor)\n        return descriptor\n',1);s=s[:a]+r+s[b:]
# Global terminal/control phases may inspect an already completed C16 prefix;
# active C16 remains only the actual PREPARING/PREPARING_CAPTURED record.
a=s.index('    func validate(plan: OriginalEraseC16PlanV1) throws {',s.index('struct OriginalEraseC16ReferenceProgressV1:'));b=s.index('\nenum OriginalEraseC16CutV1:',a)
r=s[a:b]
r=r.replace('''                || recordStage == .preparingCaptured || recordStage == .completed else {''','''                || recordStage == .preparingCaptured || recordStage == .completed
                || recordStage == .completedEmpty || recordStage == .phaseCASPreparing
                || recordStage == .phaseCASComplete else {''',1)
end='''        }
    }
}
''';assert r.endswith(end);r=r[:-len(end)]+'''        }
        if recordStage == .completedEmpty {
            guard plan.steps.isEmpty, completedC16PrefixCount == 0, activeC16Ordinal == nil else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        }
        if recordStage == .phaseCASPreparing || recordStage == .phaseCASComplete {
            guard completedC16PrefixCount == plan.steps.count, activeC16Ordinal == nil else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        }
    }
}
''';s=s[:a]+r+s[b:]
p.write_text(s)

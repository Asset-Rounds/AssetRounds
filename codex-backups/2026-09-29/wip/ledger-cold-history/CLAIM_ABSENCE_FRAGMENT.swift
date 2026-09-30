    /// A claimed-only directory may have been consumed by an exact earlier
    /// H. Its unchanged preparation/claim remains an E dependency; absence
    /// is a proved initial E input, not an invented E deletion receipt.
    private func originalEraseC16ClaimHasCompletedHygieneOwner(
        _ target: C16IngressUnpublishedEraseTargetV1
    ) throws -> Bool {
        try requireScratchDescriptorAccess()
        guard let directory = target.directory else { return false }
        for name in try originalEraseC16ReferenceNames()
            where name.hasPrefix("hygiene-") && name.hasSuffix(".prepare.json") {
            let reference = try originalEraseC16ReferenceHygiene(name: name)
            guard reference.initial.targets.contains(where: {
                $0.directoryName == directory.directoryName && $0.device == directory.device
                    && $0.inode == directory.inode
                    && $0.files.filter({ !$0.name.hasPrefix(".partial-") }) == directory.files
            }) else { continue }
            if let plan = originalEraseC16ReferencePlan,
               let ordinal = plan.steps.firstIndex(of: .resumeHygiene(operationID: reference.initial.request.operationID)) {
                guard ordinal < (originalEraseC16CurrentOrdinal
                    ?? originalEraseC16AdmissionProgress?.completedC16PrefixCount ?? 0) else { continue }
            }
            guard try originalEraseC16HygieneGroupCut(reference.current) == .terminal,
                  try originalEraseC16TargetCut(.init(directory)) == .absent else { continue }
            return true
        }
        return false
    }

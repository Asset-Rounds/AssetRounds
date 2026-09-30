    private func originalEraseC16ClaimOnlySource(
        preparation: C16IngressPreparedStageV1,
        claim: C16IngressDirectoryClaimV1
    ) throws -> C16IngressUnpublishedEraseTargetV1 {
        guard originalEraseBorrowedExclusiveCheck != nil,
              claim.preparation == preparation, claim.device == authority.rootDevice else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let directoryName = preparation.lease.relativeDirectory
        var selected: C16IngressHygieneTargetV1?
        for name in try originalEraseC16ReferenceNames()
            where name.hasPrefix("hygiene-") && name.hasSuffix(".prepare.json") {
            let prepare = try originalEraseC16ReferenceValue(C16IngressHygienePrepareV1.self, name: name)
            for target in prepare.targets where target.directoryName == directoryName {
                guard target.device == claim.device, target.inode == claim.inode,
                      selected == nil || selected == target else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                _ = try originalEraseC16HygieneGroupCut(prepare)
                selected = target
            }
        }
        // A fixed older E may be the lossless owner of an unfinished claim
        // even after its H source has completed. Never select a Q directory.
        for name in try originalEraseC16ReferenceNames()
            where name.hasPrefix("erase-") && name.hasSuffix(".prepare.json") {
            let erase = try originalEraseC16ReferenceValue(C16IngressEraseV1.self, name: name)
            for target in erase.unpublishedTargets where target.preparation == preparation {
                guard target.claim == claim else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                if let directory = target.directory {
                    if let selected {
                        guard selected.directoryName == directory.directoryName,
                              selected.device == directory.device, selected.inode == directory.inode,
                              selected.modifiedAt == directory.modifiedAt,
                              selected.files.filter({ !$0.name.hasPrefix(".partial-") }) == directory.files else {
                            throw ScratchDataLeaseStoreFailureV1.leaseCollision
                        }
                    } else { selected = directory }
                }
            }
        }
        if let selected {
            // H retains every early partial file and performs its fixed
            // deletion first. The aborted/E record remains the unchanged
            // unpublished schema containing only lease.json/opaque-data.
            _ = try originalEraseC16TargetCut(.init(selected))
            let directory = try C16IngressHygieneTargetV1(directoryName: directoryName,
                modifiedAt: selected.modifiedAt, device: selected.device, inode: selected.inode,
                files: selected.files.filter { !$0.name.hasPrefix(".partial-") })
            let result = C16IngressUnpublishedEraseTargetV1(preparation: preparation, directory: directory)
            try result.validate(); return result
        }
        let originalPath = "ScratchDataV1/" + directoryName
        guard let directory = try originalEraseC16FirstPFact(path: originalPath),
              try originalEraseC16FirstPFact(path: "ScratchDataV1/" + Self.deletionTombstoneName(for: directoryName)) == nil,
              directory.device == claim.device, directory.inode == claim.inode else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let fixedFiles: [OriginalEraseC16FileFactV1]
        if let plan = originalEraseC16ReferencePlan {
            guard let target = plan.freshUnpublishedTargets.first(where: { $0.intentID == preparation.intent.intentID }),
                  let fact = target.directory, fact.directoryName == directoryName,
                  fact.device == claim.device, fact.inode == claim.inode else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            fixedFiles = fact.files
        } else {
            guard originalEraseC16InitialSourceProof else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            fixedFiles = try [Self.metadataName, "opaque-data"].compactMap { name in
                guard let fact = try originalEraseC16FirstPFact(path: originalPath + "/" + name) else { return nil }
                return OriginalEraseC16FileFactV1(name: name, device: fact.device, inode: fact.inode,
                    byteCount: fact.byteCount, modifiedSeconds: fact.modifiedSeconds,
                    modifiedNanoseconds: fact.modifiedNanoseconds)
            }.sorted { $0.name < $1.name }
        }
        let target = try C16IngressHygieneTargetV1(directoryName: directoryName,
            modifiedAt: directory.modifiedAt, device: claim.device, inode: claim.inode,
            files: fixedFiles.map(C16IngressHygieneFileIdentityV1.init))
        let result = C16IngressUnpublishedEraseTargetV1(preparation: preparation, directory: target)
        try result.validate()
        _ = try originalEraseC16TargetCut(.init(target))
        return result
    }

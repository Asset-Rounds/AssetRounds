    private static func originalEraseC16SourceMaximum(name: String) -> Int {
        if name == controlEraseName || name.hasPrefix(".partial-") { return 32 * 1_024 * 1_024 }
        if name.hasPrefix("hygiene-"), name.hasSuffix(".json"),
           !name.hasSuffix(".prepare.json"), !name.hasSuffix(".prepare.json.finalizing") { return 4_096 }
        return 262_144
    }

    private struct OriginalEraseC16PhysicalFactV1 {
        let device: UInt64
        let inode: UInt64
        let mode: UInt64
        let uid: UInt64
        let gid: UInt64
        let linkCount: UInt64
        let byteCount: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        init(_ text: String) throws {
            let fields = text.split(separator: "|", omittingEmptySubsequences: false)
            guard fields.count == 11,
                  let device = UInt64(fields[0]), let inode = UInt64(fields[1]),
                  let mode = UInt64(fields[2]), let uid = UInt64(fields[3]),
                  let gid = UInt64(fields[4]), let links = UInt64(fields[5]),
                  let bytes = Int64(fields[6]), let seconds = Int64(fields[7]),
                  let nanos = Int64(fields[8]), Int64(fields[9]) != nil,
                  Int64(fields[10]) != nil, inode != 0, nanos >= 0,
                  nanos < 1_000_000_000 else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            self.device = device; self.inode = inode; self.mode = mode
            self.uid = uid; self.gid = gid; linkCount = links; byteCount = bytes
            modifiedSeconds = seconds; modifiedNanoseconds = nanos
        }
        func matches(_ file: OriginalEraseC16FileFactV1) -> Bool {
            device == file.device && inode == file.inode && byteCount == file.byteCount
                && modifiedSeconds == file.modifiedSeconds
                && modifiedNanoseconds == file.modifiedNanoseconds
                && mode & UInt64(S_IFMT) == UInt64(S_IFREG)
                && linkCount == 1 && uid == UInt64(Darwin.geteuid())
                && gid == UInt64(Darwin.getegid())
        }
        var modifiedAt: Date {
            Date(timeIntervalSince1970: TimeInterval(modifiedSeconds)
                + TimeInterval(modifiedNanoseconds) / 1_000_000_000)
        }
    }

    @MainActor private func primeOriginalEraseC16ImmutableInputs(
        plan: OriginalEraseC16PlanV1?
    ) throws {
        guard let permit = originalEraseColdPermit else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try permit.requireHeld()
        var inputs: [String: OriginalEraseC16SourceInputV1] = [:]
        let names: [String]
        if let plan { names = plan.markerBindings.map(\.name) }
        else if try hasExistingIngressControl() { names = try directoryNames(ingressControlDescriptor()) }
        else { names = [] }
        guard names.count <= 100_000, names == names.sorted(), Set(names).count == names.count else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        var bytesTotal = 0
        for name in names {
            try permit.requireHeld()
            let path = "ProtectedIngressReceiptsV1/" + name
            let input: OriginalEraseC16SourceInputV1
            if let plan {
                let transfer = try permit.canonicalTransferredSource(path: path)
                guard let binding = plan.markerBindings.first(where: { $0.name == name }),
                      try CompatibilityCanonicalV1.sha256(transfer.bytes) == binding.sha256 else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                try permit.requireTransferredSource(path: path, bytes: transfer.bytes, fullFact: transfer.fullFact)
                input = .init(bytes: transfer.bytes, fullFact: transfer.fullFact)
            } else {
                guard let originalFact = try permit.originalPPhysicalFact(path: path),
                      let leaf = try readOriginalErasePublicationLeaf(named: name,
                        parent: ingressControlDescriptor(), maximumBytes: Self.originalEraseC16SourceMaximum(name: name)),
                      Self.originalEraseSourceFullFact(leaf.0) == originalFact else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                input = .init(bytes: leaf.1, fullFact: originalFact)
            }
            guard input.bytes.count <= Self.originalEraseC16SourceMaximum(name: name) else {
                throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
            }
            let charge = bytesTotal.addingReportingOverflow(input.bytes.count)
            guard !charge.overflow, charge.partialValue <= 1_024 * 1_024 * 1_024 else {
                throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
            }
            bytesTotal = charge.partialValue; inputs[name] = input
            try permit.requireHeld()
        }
        originalEraseC16SourceInputs = inputs
        var targets: [OriginalEraseC16TargetFactV1] = plan?.markerBindings.flatMap(\.targets) ?? []
        targets += plan?.freshPublishedTargets.compactMap(\.directory) ?? []
        targets += plan?.freshUnpublishedTargets.compactMap(\.directory) ?? []
        var preparationNames = Set<String>()
        for name in names {
            guard !name.hasPrefix(".partial-") else { continue }
            if name.hasPrefix("hygiene-"), name.hasSuffix(".prepare.json") {
                let value = try originalEraseC16ReferenceValue(C16IngressHygienePrepareV1.self, name: name)
                try value.validate(); targets += value.targets.map(OriginalEraseC16TargetFactV1.init)
            } else if name.hasPrefix("erase-"), name.hasSuffix(".prepare.json") {
                let value = try originalEraseC16ReferenceValue(C16IngressEraseV1.self, name: name)
                try value.validate()
                targets += value.targets.map(OriginalEraseC16TargetFactV1.init)
                targets += value.unpublishedTargets.compactMap { $0.directory.map(OriginalEraseC16TargetFactV1.init) }
            } else if name.hasPrefix("ingress-"), name.hasSuffix(".published.json") {
                let value = try originalEraseC16ReferenceValue(C16IngressPublicationV1.self, name: name)
                try value.validate(); targets.append(.init(value))
            } else if name.hasPrefix("ingress-"), name.hasSuffix(".prepare.json") {
                let value = try originalEraseC16ReferenceValue(C16IngressPreparedStageV1.self, name: name)
                try value.validate(); preparationNames.insert(value.lease.relativeDirectory)
            }
        }
        var paths = Set(names.map { "ProtectedIngressReceiptsV1/" + $0 })
        for target in targets {
            for name in [target.directoryName, Self.deletionTombstoneName(for: target.directoryName)] {
                let path = "ScratchDataV1/" + name
                paths.insert(path)
                for child in target.files { paths.insert(path + "/" + child.name) }
            }
        }
        for name in preparationNames {
            for location in [name, Self.deletionTombstoneName(for: name)] {
                let path = "ScratchDataV1/" + location
                paths.insert(path)
                for child in [Self.metadataName, "opaque-data"] { paths.insert(path + "/" + child) }
                // Only the positive immutable-P scope may discover initial
                // claimed-only children. Replay uses the fixed plan/H/E source.
                if plan == nil, try directoryInformationIfPresent(named: location) != nil {
                    let descriptor = try openLeaseDirectory(location)
                    let children = try withObservedScratchDescriptor(descriptor) { try directoryNames($0) }
                    for child in children { paths.insert(path + "/" + child) }
                }
            }
        }
        guard paths.count <= 100_000 else { throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded }
        for path in paths.sorted() {
            try permit.requireHeld()
            if let fact = try permit.originalPPhysicalFact(path: path) {
                _ = try OriginalEraseC16PhysicalFactV1(fact)
                originalEraseC16FirstPFacts[path] = fact
            } else { originalEraseC16FirstPAbsentPaths.insert(path) }
            try permit.requireHeld()
        }
        try permit.requireHeld()
    }

    @MainActor private func requireOriginalEraseC16TransferredInputs() throws {
        guard !originalEraseC16InitialSourceProof, let permit = originalEraseColdPermit else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        // Reproof is intentionally fresh. Cached bytes are only immutable
        // semantic inputs, never an authorization or readback receipt.
        for (name, source) in originalEraseC16SourceInputs.sorted(by: { $0.key < $1.key }) {
            try permit.requireHeld()
            try permit.requireTransferredSource(path: "ProtectedIngressReceiptsV1/" + name,
                bytes: source.bytes, fullFact: source.fullFact)
            try permit.requireHeld()
        }
    }

    private func originalEraseC16FirstPFact(path: String) throws -> OriginalEraseC16PhysicalFactV1? {
        if let fact = originalEraseC16FirstPFacts[path] { return try .init(fact) }
        guard originalEraseC16FirstPAbsentPaths.contains(path) else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        return nil
    }

    private func originalEraseC16InitialTargetCut(
        _ target: OriginalEraseC16TargetFactV1
    ) throws -> OriginalEraseC16TargetCutV1 {
        let originalPath = "ScratchDataV1/" + target.directoryName
        let tombstonePath = "ScratchDataV1/" + Self.deletionTombstoneName(for: target.directoryName)
        let original = try originalEraseC16FirstPFact(path: originalPath)
        let tombstone = try originalEraseC16FirstPFact(path: tombstonePath)
        guard original == nil || tombstone == nil else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        guard let directory = original ?? tombstone else { return .absent }
        guard directory.device == target.device, directory.inode == target.inode,
              directory.mode & UInt64(S_IFMT) == UInt64(S_IFDIR) else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let path = tombstone == nil ? originalPath : tombstonePath
        var missing = 0, sawPresent = false
        for file in target.files {
            if let fact = try originalEraseC16FirstPFact(path: path + "/" + file.name) {
                guard fact.matches(file) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                sawPresent = true
            } else {
                guard !sawPresent else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                missing += 1
            }
        }
        guard tombstone != nil || missing == 0 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        return tombstone == nil ? .original : .tombstone(removedChildren: missing)
    }

    private func originalEraseC16InitialHygieneOwner(
        target: OriginalEraseC16TargetFactV1, excluding operationID: UUID
    ) throws -> Bool {
        for name in try originalEraseC16ReferenceNames()
            where name.hasPrefix("hygiene-") && name.hasSuffix(".prepare.json") {
            let prepare = try originalEraseC16ReferenceValue(C16IngressHygienePrepareV1.self, name: name)
            guard prepare.request.operationID != operationID,
                  prepare.targets.contains(where: { OriginalEraseC16TargetFactV1($0) == target }) else { continue }
            var sawLive = false, valid = true
            for value in prepare.targets {
                switch try originalEraseC16InitialTargetCut(.init(value)) {
                case .absent: if sawLive { valid = false }
                case .tombstone: if sawLive { valid = false }; sawLive = true
                case .original: sawLive = true
                }
            }
            let receiptName = "hygiene-" + prepare.request.operationID.uuidString.lowercased() + ".json"
            if originalEraseC16SourceInputs[receiptName] != nil {
                let receipt = try originalEraseC16ReferenceValue(ProtectedIngressStartupHygieneReceiptV1.self, name: receiptName)
                guard receipt == prepare.receipt(), !sawLive else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            }
            if valid { return true }
        }
        return false
    }

    /// Deletion order is evaluated over the immutable initial projection.
    /// Another exact H may already have consumed a later target in first P;
    /// that absence is a fixed input, not a claimed earlier effect by this H.
    private func originalEraseC16HygieneGroupCut(
        _ prepare: C16IngressHygienePrepareV1
    ) throws -> OriginalEraseC16CutV1 {
        var initialSawLive = false, changed = false, sawUntouched = false, sawActive = false
        var allAbsent = true
        for value in prepare.targets {
            let target = OriginalEraseC16TargetFactV1(value)
            let initial = try originalEraseC16InitialTargetCut(target)
            let current = try originalEraseC16TargetCut(target)
            if initial != .original,
               try originalEraseC16InitialHygieneOwner(target: target, excluding: prepare.request.operationID) {
                // Exact other-H original sources prove this independent cut.
            } else {
                switch initial {
                case .absent: guard !initialSawLive else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                case .tombstone: guard !initialSawLive else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }; initialSawLive = true
                case .original: initialSawLive = true
                }
            }
            if current != .absent { allAbsent = false }
            if initial == .absent {
                guard current == .absent else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                continue
            }
            if current == initial { sawUntouched = true; continue }
            guard !sawUntouched, !sawActive else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            changed = true
            switch current {
            case .absent: break
            case let .tombstone(removedChildren):
                if case let .tombstone(initialRemoved) = initial {
                    guard removedChildren >= initialRemoved else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                }
                sawActive = true
            case .original: throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        }
        let receipt = try protectedIngressReceiptFile(operationID: prepare.request.operationID)
        if try ingressControlFileExists(receipt) {
            guard allAbsent, try readProtectedIngressReceipt(at: receipt,
                operationID: prepare.request.operationID) == prepare.receipt() else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            return prepare.finalized ? .terminal : .intermediate
        }
        guard !prepare.finalized else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        return changed ? .intermediate : .preimage
    }

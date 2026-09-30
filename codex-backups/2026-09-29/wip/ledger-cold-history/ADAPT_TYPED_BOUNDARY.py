from pathlib import Path
p=Path('.codex-temp/cold-ledger-continuation-successor-v1/candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift');s=p.read_text()
s=s.replace('(@MainActor () throws -> Void)?\n    // Immutable sidecar input','(@MainActor (OriginalEraseC16BoundaryObservationV1) throws -> OriginalEraseC16BoundaryReceiptV1)?\n    // Immutable sidecar input',1)
s=s.replace('requireCut: @escaping @MainActor () throws -> Void','requireCut: @escaping @MainActor (OriginalEraseC16BoundaryObservationV1) throws -> OriginalEraseC16BoundaryReceiptV1')
a='    private var originalEraseC16CurrentOrdinal: Int?\n'
s=s.replace(a,a+'''    private var originalEraseC16CurrentControlMarkerState: OriginalEraseC16ControlMarkerStateV1?
    private var originalEraseC16CurrentIngressMarkerState: OriginalEraseC16IngressMarkerStateV1?
''',1)
a='''        originalEraseC16CurrentOrdinal = ordinal
        defer { originalEraseC16CurrentOrdinal = nil }'''
b='''        originalEraseC16CurrentOrdinal = ordinal
        originalEraseC16CurrentControlMarkerState = controlMarkerState
        originalEraseC16CurrentIngressMarkerState = ingressMarkerState
        defer {
            originalEraseC16CurrentOrdinal = nil
            originalEraseC16CurrentControlMarkerState = nil
            originalEraseC16CurrentIngressMarkerState = nil
        }''';assert a in s;s=s.replace(a,b,1)
start=s.index('    @MainActor private func requireOriginalEraseC16Cut() throws {')
end=s.index('    /// The callback must prove the held EX/G',start)
s=s[:start]+'''    @MainActor private func requireOriginalEraseC16Cut(
        explicitlyCapturing explicit: OriginalEraseC16BornSourceObservationV1? = nil
    ) throws {
        try requireScratchDescriptorAccess()
        guard originalEraseBorrowedExclusiveCheck != nil else { return }
        guard let permit = originalEraseColdPermit, let check = originalEraseC16CutCheck,
              let plan = originalEraseC16ReferencePlan, let ordinal = originalEraseC16CurrentOrdinal else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try permit.requireObservationBinding()
        try requireOriginalEraseC16TransferredInputs()
        var explicitBirth = explicit
        // Every genuine active canonical birth is transferred before the next
        // semantic advance. Fresh-owner pre-capture cuts use the same typed
        // request; a retained exact tuple is an authenticated no-effect retry.
        while true {
            _ = try originalEraseC16CurrentObservationScope(plan: plan, currentOrdinal: ordinal,
                controlMarkerState: originalEraseC16CurrentControlMarkerState,
                ingressMarkerState: originalEraseC16CurrentIngressMarkerState)
            let projection = try originalEraseC16ExpectedTree(plan: plan, currentOrdinal: ordinal,
                controlMarkerState: originalEraseC16CurrentControlMarkerState,
                ingressMarkerState: originalEraseC16CurrentIngressMarkerState, capturedBirths: [])
            var candidates = try originalEraseC16CanonicalRoles(plan: plan, through: ordinal)
            if ordinal > 0 {
                let earlier = try originalEraseC16CanonicalRoles(plan: plan, through: ordinal - 1)
                candidates = candidates.filter { earlier[$0.key]?.bytes != $0.value.bytes }
            }
            if let marker = try originalEraseC16MaterializedControlRole(plan: plan, ordinal: ordinal) {
                candidates[Self.controlEraseName] = marker
            }
            var birth = explicitBirth
            if birth == nil, try hasExistingIngressControl() {
                for (name, role) in candidates.sorted(by: { $0.key < $1.key }) {
                    guard let leaf = try readOriginalErasePublicationLeaf(named: name,
                        parent: ingressControlDescriptor(), maximumBytes: role.bytes.count),
                        leaf.0.st_nlink == 1, leaf.1 == role.bytes else { continue }
                    let fact = Self.originalEraseSourceFullFact(leaf.0)
                    if let original = originalEraseC16SourceInputs[name], original.bytes == leaf.1,
                       original.fullFact == fact { continue }
                    if let captured = originalEraseC16BornSourceInputs[role.role + "|" + name],
                       captured.bytes == leaf.1, captured.fullFact == fact { continue }
                    birth = .init(role: role.role, path: "ProtectedIngressReceiptsV1/" + name,
                        bytes: leaf.1, fullFact: fact, sha256: try CompatibilityCanonicalV1.sha256(leaf.1))
                    break
                }
            }
            if let birth {
                let name = String(birth.path.dropFirst("ProtectedIngressReceiptsV1/".count))
                guard birth.path == "ProtectedIngressReceiptsV1/" + name,
                      let role = candidates[name], role.role == birth.role, role.bytes == birth.bytes,
                      try CompatibilityCanonicalV1.sha256(birth.bytes) == birth.sha256 else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
            }
            let observation = OriginalEraseC16BoundaryObservationV1(
                planSHA256: try CompatibilityCanonicalV1.sha256(CompatibilityCanonicalV1.encode(plan)),
                stepSHA256: try CompatibilityCanonicalV1.sha256(CompatibilityCanonicalV1.encode(plan.steps[ordinal])),
                ordinal: ordinal, projection: projection, bornSource: birth)
            let receipt = try check(observation)
            try receipt.requireBound(to: observation)
            try permit.requireHeld()
            try originalEraseBorrowedExclusiveCheck?()
            if let birth {
                try permit.requireTransferredSource(path: birth.path, bytes: birth.bytes, fullFact: birth.fullFact)
                let name = String(birth.path.dropFirst("ProtectedIngressReceiptsV1/".count))
                originalEraseC16BornSourceInputs[birth.role + "|" + name] = .init(bytes: birth.bytes, fullFact: birth.fullFact)
                if birth.role == "freshIngressErasePrepare" { originalEraseC16CurrentIngressMarkerState = .capturedPublished }
                if birth.role == "scratchControlErase" { originalEraseC16CurrentControlMarkerState = .capturedPublished }
                explicitBirth = nil
                continue
            }
            try requireOriginalEraseC16TransferredInputs()
            return
        }
    }

'''+s[end:]
a='''                    try permit.requireHeld()
                    try permit.captureBornSource(path: capture.path, bytes: capture.bytes, fullFact: capture.fullFact)
                    try permit.requireHeld()
                    try permit.requireTransferredSource(path: capture.path, bytes: capture.bytes, fullFact: capture.fullFact)
                    try requireOriginalEraseC16Cut()
                    try session.authorizeCaptureAdvance()'''
b='''                    try permit.requireObservationBinding()
                    guard let plan = originalEraseC16ReferencePlan, let ordinal = originalEraseC16CurrentOrdinal else {
                        throw ScratchDataLeaseStoreFailureV1.leaseCollision
                    }
                    var roles = try originalEraseC16CanonicalRoles(plan: plan, through: ordinal)
                    if let marker = try originalEraseC16MaterializedControlRole(plan: plan, ordinal: ordinal) { roles[Self.controlEraseName] = marker }
                    let name = String(capture.path.dropFirst("ProtectedIngressReceiptsV1/".count))
                    guard let role = roles[name], role.bytes == capture.bytes else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    try requireOriginalEraseC16Cut(explicitlyCapturing: .init(role: role.role,
                        path: capture.path, bytes: capture.bytes, fullFact: capture.fullFact,
                        sha256: try CompatibilityCanonicalV1.sha256(capture.bytes)))
                    try session.authorizeCaptureAdvance()''';assert a in s;s=s.replace(a,b,1)
# Raw canonical reads are role-scoped only under the borrowed controller.
a='''        let data = try readRegularFile(named: file.lastPathComponent,
            directoryDescriptor: ingressControlDescriptor(), maximumBytes: maximumBytes)'''
b='''        let data: Data
        if originalEraseBorrowedExclusiveCheck != nil {
            guard let leaf = try readOriginalErasePublicationLeaf(named: file.lastPathComponent,
                parent: ingressControlDescriptor(), maximumBytes: maximumBytes) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            data = leaf.1
        } else {
            data = try readRegularFile(named: file.lastPathComponent,
                directoryDescriptor: ingressControlDescriptor(), maximumBytes: maximumBytes)
        }''';assert a in s;s=s.replace(a,b,1)
a='''        let data = try readRegularFile(named: name, directoryDescriptor: inventory.descriptor,
            maximumBytes: 262_144)
        try ProtectedFilePolicyV1.verify(.temporaryFile, at: file)'''
b='''        let data = try readIngressControlFile(file, maximumBytes: 262_144)
        try verifySourceReadPolicy(.temporaryFile, at: file)''';assert a in s;s=s.replace(a,b,1)
# Strict one-link defaults are unchanged; only an actually observed exact
# current pair can reach this additional branch.
a='''        guard (information.st_mode & S_IFMT) == S_IFREG,
              information.st_nlink == 1,
              information.st_size >= 0,'''
b='''        if information.st_nlink == 2, originalEraseBorrowedExclusiveCheck != nil,
           ingressControlAuthority?.rootDescriptor == directoryDescriptor,
           try originalEraseC16VerifyScopedPairPolicy(at: rootURL.deletingLastPathComponent()
               .appendingPathComponent("ProtectedIngressReceiptsV1").appendingPathComponent(name)) {
            return information
        }
        guard (information.st_mode & S_IFMT) == S_IFREG,
              information.st_nlink == 1,
              information.st_size >= 0,''';assert a in s;s=s.replace(a,b,1)
# Priming only immutable data must be possible before a scoped physical
# observation can be issued; no destructive advance is admitted here.
start=s.index('    @MainActor private func primeOriginalEraseC16ImmutableInputs(');end=s.index('    @MainActor private func requireOriginalEraseC16TransferredInputs()',start)
region=s[start:end].replace('permit.requireHeld()','permit.requireObservationBinding()');s=s[:start]+region+s[end:]
start=s.index('    static func withSchema2ColdBorrowedExistingRoot<');end=s.index('    /// Classify the real control graph',start)
region=s[start:end]
region=region.replace('        try permit.requireHeld()\n','        try permit.requireObservationBinding()\n',1)
a='''                try store.primeOriginalEraseC16ImmutableInputs(plan: referencePlan)
                store.originalEraseBorrowedAdmitting = true'''
b='''                try store.primeOriginalEraseC16ImmutableInputs(plan: referencePlan)
                if let plan = referencePlan, let progress = referenceProgress, !plan.steps.isEmpty {
                    let current = min(progress.completedC16PrefixCount, plan.steps.count - 1)
                    let captured = progress.activeC16Ordinal == current && progress.recordStage == .preparingCaptured
                    _ = try store.originalEraseC16CurrentObservationScope(plan: plan, currentOrdinal: current,
                        controlMarkerState: plan.steps[current] == .eraseFinalControl ? (captured ? .capturedPublished : .notYetCaptured) : nil,
                        ingressMarkerState: plan.steps[current] == .eraseIngress ? (captured ? .capturedPublished : .notYetCaptured) : nil)
                }
                try permit.requireHeld()
                store.originalEraseBorrowedAdmitting = true''';assert a in region;region=region.replace(a,b,1)
s=s[:start]+region+s[end:]
p.write_text(s)

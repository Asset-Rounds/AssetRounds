    private struct OriginalEraseC16CanonicalRoleV1 {
        let role: String
        let bytes: Data
    }

    private func originalEraseC16FixedFreshEraseMarker(
        plan: OriginalEraseC16PlanV1
    ) throws -> C16IngressEraseV1 {
        try requireScratchDescriptorAccess()
        guard let operationID = originalEraseOperationID else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        let name = "erase-" + operationID.uuidString.lowercased() + ".prepare.json"
        if let born = originalEraseC16BornSourceInputs["freshIngressErasePrepare|" + name] {
            let marker = try CompatibilityCanonicalV1.decode(C16IngressEraseV1.self, from: born.bytes)
            try marker.validate()
            guard marker.operationID == operationID, marker.rootDevice == authority.rootDevice,
                  marker.rootInode == authority.rootInode,
                  marker.targets.map({ OriginalEraseC16PlannedTargetV1(intentID: $0.intent.intentID, directory: .init($0)) }) == plan.freshPublishedTargets,
                  marker.unpublishedTargets.map({ OriginalEraseC16PlannedTargetV1(intentID: $0.preparation.intent.intentID,
                    directory: $0.directory.map(OriginalEraseC16TargetFactV1.init)) }) == plan.freshUnpublishedTargets,
                  try CompatibilityCanonicalV1.encode(marker) == born.bytes else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            return marker
        }
        let published = try plan.freshPublishedTargets.map { target -> C16IngressPublicationV1 in
            let value = try originalEraseC16FixedIngressRecipeData(intentID: target.intentID).expected
            guard target.directory == OriginalEraseC16TargetFactV1(value) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            return value
        }
        let unpublished = try plan.freshUnpublishedTargets.map { target -> C16IngressUnpublishedEraseTargetV1 in
            let preparation = try originalEraseC16ReferenceValue(C16IngressPreparedStageV1.self,
                name: ingressControlName(target.intentID, ".prepare.json"))
            if target.directory == nil {
                guard originalEraseC16SourceInputs[try ingressControlName(target.intentID, ".claim.json")] == nil else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                return .init(preparation: preparation, directory: nil)
            }
            let claim = try originalEraseC16ReferenceValue(C16IngressDirectoryClaimV1.self,
                name: ingressControlName(target.intentID, ".claim.json"))
            let value = try originalEraseC16ClaimOnlySource(preparation: preparation, claim: claim)
            guard value.directory.map(OriginalEraseC16TargetFactV1.init) == target.directory else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            return value
        }
        let value = C16IngressEraseV1(operationID: operationID, rootDevice: authority.rootDevice,
            rootInode: authority.rootInode, targets: published, unpublishedTargets: unpublished)
        try value.validate(); return value
    }

    /// Exact canonical outputs of the sole semantic engine through this
    /// ordinal. This selects fixed roles, never currently surviving IDs.
    private func originalEraseC16CanonicalRoles(
        plan: OriginalEraseC16PlanV1, through ordinal: Int
    ) throws -> [String: OriginalEraseC16CanonicalRoleV1] {
        try requireScratchDescriptorAccess()
        guard ordinal >= 0, ordinal < plan.steps.count else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        var roles: [String: OriginalEraseC16CanonicalRoleV1] = [:]
        func add<Value: Encodable>(_ value: Value, name: String, role: String) throws {
            let bytes = try CompatibilityCanonicalV1.encode(value)
            guard bytes.count <= Self.originalEraseC16SourceMaximum(name: name) else {
                throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded
            }
            if let existing = roles[name], existing.bytes != bytes {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            roles[name] = .init(role: role, bytes: bytes)
        }
        func addErase(_ marker: C16IngressEraseV1) throws {
            try add(marker, name: "erase-" + marker.operationID.uuidString.lowercased() + ".complete.json", role: "ingressEraseComplete")
            for target in marker.targets {
                try add(C16IngressRemovalV1(expected: target, disposition: .erased),
                    name: ingressControlName(target.intent.intentID, ".terminal.json"), role: "ingressTerminal")
            }
            for target in marker.unpublishedTargets {
                try add(C16IngressAbortedStageV1(operationID: marker.operationID, expected: target),
                    name: ingressControlName(target.preparation.intent.intentID, ".aborted.json"), role: "ingressAborted")
            }
        }
        for index in 0...ordinal {
            switch plan.steps[index] {
            case .settleFirstPPartial, .resumeControlTail, .eraseFinalControl: break
            case let .resumeHygiene(operationID):
                let name = "hygiene-" + operationID.uuidString.lowercased() + ".prepare.json"
                let prepare = try originalEraseC16ReferenceValue(C16IngressHygienePrepareV1.self, name: name)
                try add(prepare.receipt(), name: "hygiene-" + operationID.uuidString.lowercased() + ".json", role: "hygieneReceipt")
                try add(prepare.finalizing(), name: name + ".finalizing", role: "hygieneFinalizing")
                try add(prepare.finalizing(), name: name, role: "finalizedHygienePrepare")
                for binding in plan.markerBindings where binding.name.hasPrefix("ingress-") && binding.name.hasSuffix(".published.json") {
                    let published = try originalEraseC16ReferenceValue(C16IngressPublicationV1.self, name: binding.name)
                    let recipe = try originalEraseC16FixedIngressRecipeData(intentID: published.intent.intentID)
                    if recipe.terminalBeforeHygieneOrdinal == index, let removal = recipe.removal {
                        try add(removal, name: ingressControlName(published.intent.intentID, ".terminal.json"), role: "ingressTerminal")
                    }
                }
            case let .resumeIngressErase(operationID):
                let marker = try originalEraseC16ReferenceValue(C16IngressEraseV1.self,
                    name: "erase-" + operationID.uuidString.lowercased() + ".prepare.json")
                try addErase(marker)
            case let .recoverIngressPointer(intentID):
                let recipe = try originalEraseC16FixedIngressRecipeData(intentID: intentID)
                if let removal = recipe.removal {
                    try add(removal, name: ingressControlName(intentID, ".terminal.json"), role: "ingressTerminal")
                } else {
                    try add(recipe.expected, name: ingressControlName(intentID, ".pending.json"), role: "ingressPending")
                }
            case .eraseIngress:
                let marker = try originalEraseC16FixedFreshEraseMarker(plan: plan)
                try add(marker, name: "erase-" + marker.operationID.uuidString.lowercased() + ".prepare.json", role: "freshIngressErasePrepare")
                try addErase(marker)
            }
        }
        return roles
    }

    private func originalEraseC16MayConsumePending(id: UUID, plan: OriginalEraseC16PlanV1, through ordinal: Int) throws -> Bool {
        try requireScratchDescriptorAccess()
        for index in 0...ordinal {
            switch plan.steps[index] {
            case let .recoverIngressPointer(intentID) where intentID == id:
                if try originalEraseC16FixedIngressRecipeData(intentID: id).removal != nil { return true }
            case let .resumeIngressErase(operationID):
                let marker = try originalEraseC16ReferenceValue(C16IngressEraseV1.self,
                    name: "erase-" + operationID.uuidString.lowercased() + ".prepare.json")
                if marker.targets.contains(where: { $0.intent.intentID == id }) { return true }
            case .eraseIngress: if plan.freshPublishedTargets.contains(where: { $0.intentID == id }) { return true }
            default: break
            }
        }
        return false
    }

    @MainActor private func originalEraseC16MaterializedControlRole(
        plan: OriginalEraseC16PlanV1, ordinal: Int
    ) throws -> OriginalEraseC16CanonicalRoleV1? {
        try requireScratchDescriptorAccess()
        let step = plan.steps[ordinal]
        guard step == .eraseFinalControl || step == .resumeControlTail else { return nil }
        if let source = originalEraseC16SourceInputs[Self.controlEraseName] {
            return .init(role: "scratchControlErase", bytes: source.bytes)
        }
        if let born = originalEraseC16BornSourceInputs["scratchControlErase|" + Self.controlEraseName] {
            return .init(role: "scratchControlErase", bytes: born.bytes)
        }
        guard try hasExistingIngressControl(), let control = ingressControlAuthority else { return nil }
        let names = try originalEraseC16FinalControlRoleNames(plan: plan)
        let files = try names.map { name -> C16IngressHygieneFileIdentityV1 in
            let info = try regularFileInformation(named: name, directoryDescriptor: control.rootDescriptor)
            try verifySourceReadPolicy(.temporaryFile, at: protectedIngressReceiptDirectory().appendingPathComponent(name))
            return .init(name: name, information: info)
        }
        let marker = C16ScratchControlEraseV1(schemaVersion: 1, rootDevice: authority.rootDevice,
            rootInode: authority.rootInode, controlDevice: control.rootDevice, controlInode: control.rootInode, files: files)
        let bytes = try CompatibilityCanonicalV1.encode(marker)
        guard bytes.count <= 32 * 1_024 * 1_024 else { throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded }
        return .init(role: "scratchControlErase", bytes: bytes)
    }

    @MainActor
    func originalEraseC16ExpectedTree(
        plan: OriginalEraseC16PlanV1, currentOrdinal: Int,
        controlMarkerState: OriginalEraseC16ControlMarkerStateV1?,
        ingressMarkerState: OriginalEraseC16IngressMarkerStateV1?,
        capturedBirths: [OriginalEraseC16CapturedBirthV1]
    ) throws -> OriginalEraseC16ExpectedTreeV1 {
        try requireScratchDescriptorAccess()
        try requireOriginalEraseBorrowedOwner()
        guard originalEraseC16ReferencePlan == plan, currentOrdinal >= 0,
              currentOrdinal < plan.steps.count, capturedBirths.count <= 100_000 else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let observed = try requireOriginalEraseC16ObservedProjection(plan: plan, currentOrdinal: currentOrdinal,
            controlMarkerState: controlMarkerState, ingressMarkerState: ingressMarkerState)
        var roles = try originalEraseC16CanonicalRoles(plan: plan, through: currentOrdinal)
        if let marker = try originalEraseC16MaterializedControlRole(plan: plan, ordinal: currentOrdinal) {
            roles[Self.controlEraseName] = marker
        }
        var files: [OriginalEraseC16ExpectedFileV1] = [], directories: [OriginalEraseC16ExpectedDirectoryV1] = []
        var consumed = Set<String>(), seen = Set<String>()
        let controlPrefix = "ProtectedIngressReceiptsV1/"
        let tailStep = plan.steps[currentOrdinal] == .eraseFinalControl || plan.steps[currentOrdinal] == .resumeControlTail
        let tailMarker: C16ScratchControlEraseV1?
        if tailStep, let marker = roles[Self.controlEraseName] {
            tailMarker = try CompatibilityCanonicalV1.decode(C16ScratchControlEraseV1.self, from: marker.bytes)
        } else { tailMarker = nil }
        let tailRemoved: Set<String>
        if let tailMarker {
            let surviving = observed.observedControlNames.filter { $0 != Self.controlEraseName }
            let order = tailMarker.files.map(\.name)
            guard surviving == Array(order.suffix(surviving.count)) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            tailRemoved = Set(order.prefix(order.count - surviving.count))
        } else { tailRemoved = [] }
        if observed.controlRootPresent {
            let parent = try ingressControlDescriptor()
            var exceptionalCount = 0
            for name in observed.observedControlNames {
                let path = controlPrefix + name; seen.insert(name)
                if let binding = plan.markerBindings.first(where: { $0.name == name }), name.hasPrefix(".partial-") {
                    let stepIndex = plan.steps.firstIndex { step in
                        if case let .settleFirstPPartial(.control, expected, _, _, _) = step { return expected == name }; return false
                    }
                    guard let stepIndex, stepIndex >= currentOrdinal else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    files.append(.init(path: path, source: .firstP(sourcePath: path, allowOneLinkSettlement: true)))
                    guard CompatibilityCanonicalV1.validSHA256(binding.sha256) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    continue
                }
                if name.hasPrefix(".partial-") {
                    var selected: OriginalEraseC16CanonicalRoleV1?
                    for (finalName, role) in roles {
                        if try Self.originalErasePublicationTemporaryName(operationID: originalEraseOperationID!, finalName: finalName, leaseName: nil) == name {
                            guard selected == nil else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }; selected = role
                        }
                    }
                    guard let role = selected,
                          let leaf = try readOriginalErasePublicationLeaf(named: name, parent: parent, maximumBytes: role.bytes.count),
                          role.bytes.starts(with: leaf.1) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    exceptionalCount += 1
                    files.append(.init(path: path, source: .postPDeterministic(role: "publicationPrefix:" + role.role,
                        fullFact: Self.originalEraseSourceFullFact(leaf.0), sha256: try CompatibilityCanonicalV1.sha256(leaf.1))))
                    continue
                }
                guard let leaf = try readOriginalErasePublicationLeaf(named: name, parent: parent,
                    maximumBytes: Self.originalEraseC16SourceMaximum(name: name)) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                let sha = try CompatibilityCanonicalV1.sha256(leaf.1)
                if let binding = plan.markerBindings.first(where: { $0.name == name }), sha == binding.sha256 {
                    files.append(.init(path: path, source: .firstP(sourcePath: path, allowOneLinkSettlement: leaf.0.st_nlink == 2)))
                } else {
                    guard let role = roles[name], role.bytes == leaf.1 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    let fact = Self.originalEraseSourceFullFact(leaf.0)
                    if let captured = capturedBirths.first(where: { $0.name == name }) {
                        guard captured.fullFact == fact, captured.sha256 == sha else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    }
                    files.append(.init(path: path, source: .postPDeterministic(role: role.role, fullFact: fact, sha256: sha)))
                }
            }
            guard exceptionalCount <= 1 else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            directories.append(.init(path: "ProtectedIngressReceiptsV1", firstPSourcePath: "ProtectedIngressReceiptsV1",
                expectedMembers: observed.observedControlNames, expectedLinkCount: 2))
        }
        for binding in plan.markerBindings where !seen.contains(binding.name) {
            let name = binding.name, path = controlPrefix + name
            if tailRemoved.contains(name) || (tailStep && observed.observedControlNames.isEmpty && tailMarker != nil) {
                consumed.insert(path); continue
            }
            if name.hasPrefix(".partial-") {
                guard plan.steps.prefix(currentOrdinal + 1).contains(where: {
                    if case let .settleFirstPPartial(.control, expected, _, _, _) = $0 { return expected == name }; return false
                }) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                consumed.insert(path); continue
            }
            if name.hasPrefix("ingress-"), name.hasSuffix(".pending.json") {
                let id = try ingressControlIdentifier(name, prefix: "ingress-", suffixes: [".pending.json"])
                guard try originalEraseC16MayConsumePending(id: id, plan: plan, through: currentOrdinal),
                      let terminal = try readIngressControl(C16IngressRemovalV1.self, at: ingressControlURL(id, ".terminal.json")),
                      originalEraseC16TargetCut(.init(terminal.expected)) == .absent else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                consumed.insert(path); continue
            }
            if name.hasSuffix(".prepare.json.finalizing") {
                let base = String(name.dropLast(".finalizing".count))
                let initial = try originalEraseC16ReferenceValue(C16IngressHygienePrepareV1.self, name: base)
                let current = try readProtectedIngressPrepare(at: protectedIngressReceiptDirectory().appendingPathComponent(base))
                guard current == initial.finalizing() else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                consumed.insert(path); continue
            }
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        for target in observed.targets {
            let sourceName = target.source.directoryName
            let originalPath = "ScratchDataV1/" + sourceName
            let tombstonePath = "ScratchDataV1/" + Self.deletionTombstoneName(for: sourceName)
            let initial = try originalEraseC16InitialTargetCut(target.source)
            let firstPPath: String
            switch initial { case .tombstone: firstPPath = tombstonePath; default: firstPPath = originalPath }
            let path: String, removed: Int
            switch target.location {
            case .absent:
                for source in originalEraseC16FirstPFacts.keys where source == firstPPath || source.hasPrefix(firstPPath + "/") { consumed.insert(source) }
                continue
            case .original: path = originalPath; removed = 0
            case let .tombstone(count): path = tombstonePath; removed = count
            }
            let children = Array(target.source.files.dropFirst(removed))
            for file in children {
                files.append(.init(path: path + "/" + file.name,
                    source: .firstP(sourcePath: firstPPath + "/" + file.name, allowOneLinkSettlement: false)))
            }
            for file in target.source.files.prefix(removed) { consumed.insert(firstPPath + "/" + file.name) }
            directories.append(.init(path: path, firstPSourcePath: firstPPath,
                expectedMembers: children.map(\.name), expectedLinkCount: 2))
        }
        guard files.count + directories.count <= 100_000,
              Set(files.map(\.path)).count == files.count,
              Set(directories.map(\.path)).count == directories.count else { throw ScratchDataLeaseStoreFailureV1.sizeLimitExceeded }
        try requireOriginalEraseBorrowedOwner()
        return .init(currentOrdinal: currentOrdinal, currentCut: observed.currentCut,
            files: files.sorted { $0.path < $1.path }, directories: directories.sorted { $0.path < $1.path },
            consumedFirstPPaths: consumed.sorted())
    }

    /// Ordered publication roles of one fixed semantic ordinal. A current
    /// publication can be absent, a single deterministic prefix/pair, or a
    /// completed prefix of this list. Names are never selected from survivors.
    private func originalEraseC16PublicationRoleSequence(
        plan: OriginalEraseC16PlanV1, ordinal: Int
    ) throws -> [String] {
        try requireScratchDescriptorAccess()
        var names: [String] = []
        func erase(_ marker: C16IngressEraseV1, fresh: Bool) throws {
            let prefix = "erase-" + marker.operationID.uuidString.lowercased()
            if fresh { names.append(prefix + ".prepare.json") }
            for target in marker.unpublishedTargets {
                names.append(try ingressControlName(target.preparation.intent.intentID, ".aborted.json"))
            }
            for target in marker.targets { names.append(try ingressControlName(target.intent.intentID, ".terminal.json")) }
            names.append(prefix + ".complete.json")
        }
        switch plan.steps[ordinal] {
        case let .resumeHygiene(operationID):
            for binding in plan.markerBindings where binding.name.hasPrefix("ingress-") && binding.name.hasSuffix(".published.json") {
                let published = try originalEraseC16ReferenceValue(C16IngressPublicationV1.self, name: binding.name)
                let recipe = try originalEraseC16FixedIngressRecipeData(intentID: published.intent.intentID)
                if recipe.terminalBeforeHygieneOrdinal == ordinal {
                    names.append(try ingressControlName(published.intent.intentID, ".terminal.json"))
                }
            }
            let prefix = "hygiene-" + operationID.uuidString.lowercased()
            names += [prefix + ".json", prefix + ".prepare.json.finalizing", prefix + ".prepare.json"]
        case let .resumeIngressErase(operationID):
            try erase(originalEraseC16ReferenceValue(C16IngressEraseV1.self,
                name: "erase-" + operationID.uuidString.lowercased() + ".prepare.json"), fresh: false)
        case let .recoverIngressPointer(intentID):
            let recipe = try originalEraseC16FixedIngressRecipeData(intentID: intentID)
            names.append(try ingressControlName(intentID, recipe.removal == nil ? ".pending.json" : ".terminal.json"))
        case .eraseIngress: try erase(originalEraseC16FixedFreshEraseMarker(plan: plan), fresh: true)
        case .eraseFinalControl: names = [Self.controlEraseName]
        case .settleFirstPPartial, .resumeControlTail: break
        }
        guard Set(names).count == names.count else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        return names
    }

    private func originalEraseC16RequireControlPublicationPrefix(
        plan: OriginalEraseC16PlanV1, ordinal: Int,
        roles: [String: OriginalEraseC16CanonicalRoleV1],
        controlNames: [String]
    ) throws {
        try requireScratchDescriptorAccess()
        guard try hasExistingIngressControl() else { return }
        let parent = try ingressControlDescriptor()
        let step = plan.steps[ordinal]
        if step == .resumeControlTail || step == .eraseFinalControl { return }
        // All completed prior outputs remain until the final control tail.
        if ordinal > 0 {
            let previous = try originalEraseC16CanonicalRoles(plan: plan, through: ordinal - 1)
            for (name, role) in previous where role.role != "hygieneFinalizing" {
                let consumedPending: Bool
                if name.hasSuffix(".pending.json") {
                    let id = try ingressControlIdentifier(name, prefix: "ingress-", suffixes: [".pending.json"])
                    consumedPending = try originalEraseC16MayConsumePending(id: id, plan: plan, through: ordinal)
                        && !controlNames.contains(name)
                } else { consumedPending = false }
                if consumedPending { continue }
                guard let leaf = try readOriginalErasePublicationLeaf(named: name, parent: parent,
                    maximumBytes: role.bytes.count), leaf.1 == role.bytes, leaf.0.st_nlink == 1 else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
            }
        }
        let sequence = try originalEraseC16PublicationRoleSequence(plan: plan, ordinal: ordinal)
        var sawIncomplete = false, sawActive = false
        for name in sequence {
            guard let role = roles[name] else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            let leaf = try readOriginalErasePublicationLeaf(named: name, parent: parent, maximumBytes: role.bytes.count)
            let completed: Bool
            if role.role == "hygieneFinalizing" {
                let finalizedName = String(name.dropLast(".finalizing".count))
                let renamed = try readOriginalErasePublicationLeaf(named: finalizedName, parent: parent,
                    maximumBytes: role.bytes.count)
                completed = leaf?.1 == role.bytes || renamed?.1 == role.bytes
            } else { completed = leaf?.1 == role.bytes }
            let temporary = try Self.originalErasePublicationTemporaryName(operationID: originalEraseOperationID!,
                finalName: name, leaseName: nil)
            let temp = try readOriginalErasePublicationLeaf(named: temporary, parent: parent, maximumBytes: role.bytes.count)
            if completed {
                // A role that already existed exactly in original P is an
                // immutable initial input, not a claimed effect of this step.
                let initial = originalEraseC16SourceInputs[name]?.bytes == role.bytes
                guard initial || (!sawIncomplete && !sawActive) else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                if temp != nil { sawActive = true }
            } else {
                if temp != nil {
                    guard !sawIncomplete, !sawActive else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
                    sawActive = true
                }
                sawIncomplete = true
            }
        }
    }

    private func originalEraseC16FixedIngressRecipeData(
        intentID: UUID
    ) throws -> OriginalEraseC16IngressRecipeV1 {
        try requireScratchDescriptorAccess()
        let names = try originalEraseC16ReferenceNames()
        let published = try originalEraseC16ReferenceValue(C16IngressPublicationV1.self,
            name: ingressControlName(intentID, ".published.json"))
        let pendingName = try ingressControlName(intentID, ".pending.json")
        let terminalName = try ingressControlName(intentID, ".terminal.json")
        let initialTerminal = names.contains(terminalName)
        let terminal = initialTerminal ? try originalEraseC16ReferenceValue(C16IngressRemovalV1.self, name: terminalName) : nil
        let expected: C16IngressPublicationV1
        if let terminal { expected = terminal.expected }
        else if names.contains(pendingName) {
            expected = try originalEraseC16ReferenceValue(C16IngressPublicationV1.self, name: pendingName)
        } else { expected = published }
        try expected.validate()
        guard try published.replacingIntent(expected.intent) == expected else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        var eraseExpected: C16IngressPublicationV1?
        for name in names where name.hasPrefix("erase-") && name.hasSuffix(".prepare.json") {
            let id = try ingressControlIdentifier(name, prefix: "erase-", suffixes: [".prepare.json"])
            let incomplete = originalEraseC16ReferencePlan.map { $0.steps.contains(.resumeIngressErase(operationID: id)) }
                ?? !names.contains("erase-" + id.uuidString.lowercased() + ".complete.json")
            guard incomplete else { continue }
            let erase = try originalEraseC16ReferenceValue(C16IngressEraseV1.self, name: name)
            try erase.validate()
            if let value = erase.targets.first(where: { $0.intent.intentID == intentID }) {
                guard value == expected, eraseExpected == nil || eraseExpected == value else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                eraseExpected = value
            }
        }
        struct Association {
            let target: C16IngressHygieneTargetV1
            let operationID: UUID
            let initiallyCompleted: Bool
            let expired: Bool
            let ordinal: Int?
        }
        var associations: [Association] = [], initialOrdinal = 0
        for name in names where name.hasPrefix("hygiene-") && name.hasSuffix(".prepare.json") {
            let prepare = try originalEraseC16ReferenceValue(C16IngressHygienePrepareV1.self, name: name)
            try prepare.validate()
            guard prepare.rootDevice == authority.rootDevice, prepare.rootInode == authority.rootInode else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            let ordinal: Int?
            let receiptName = "hygiene-" + prepare.request.operationID.uuidString.lowercased() + ".json"
            let completed = names.contains(receiptName)
            if completed {
                let receipt = try originalEraseC16ReferenceValue(ProtectedIngressStartupHygieneReceiptV1.self, name: receiptName)
                guard receipt == (try prepare.receipt()) else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            }
            if prepare.finalized || completed { ordinal = nil }
            else if let plan = originalEraseC16ReferencePlan {
                guard let index = plan.steps.firstIndex(of: .resumeHygiene(operationID: prepare.request.operationID)) else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                ordinal = index
            } else { ordinal = initialOrdinal; initialOrdinal += 1 }
            guard let target = prepare.targets.first(where: { OriginalEraseC16TargetFactV1($0) == OriginalEraseC16TargetFactV1(expected) }) else { continue }
            associations.append(.init(target: target, operationID: prepare.request.operationID,
                initiallyCompleted: completed, expired: prepare.request.requestedAt >= expected.intent.expiresAt, ordinal: ordinal))
        }
        let removal: C16IngressRemovalV1?
        let expirationReceipt: UUID?
        let terminalOrdinal: Int?
        if let eraseExpected {
            removal = .init(expected: eraseExpected, disposition: .erased)
            expirationReceipt = nil; terminalOrdinal = associations.compactMap(\.ordinal).min()
        } else if let terminal {
            removal = terminal; expirationReceipt = nil; terminalOrdinal = nil
        } else if let completed = associations.first(where: { $0.initiallyCompleted && $0.expired }) {
            removal = .init(expected: expected, disposition: .expiredDeleted)
            expirationReceipt = completed.operationID; terminalOrdinal = nil
        } else if associations.contains(where: { $0.initiallyCompleted }) {
            removal = .init(expected: expected, disposition: .erased)
            expirationReceipt = nil; terminalOrdinal = nil
        } else if let first = associations.filter({ $0.ordinal != nil }).min(by: { $0.ordinal! < $1.ordinal! }) {
            removal = .init(expected: expected, disposition: first.expired ? .expiredDeleted : .erased)
            expirationReceipt = first.expired ? first.operationID : nil
            terminalOrdinal = first.expired ? nil : first.ordinal
        } else { removal = nil; expirationReceipt = nil; terminalOrdinal = nil }
        if let removal { try removal.validate() }
        if let terminal, let removal { guard terminal == removal else { throw ScratchDataLeaseStoreFailureV1.leaseCollision } }
        return .init(expected: expected, removal: removal, hygiene: associations.map(\.target),
            expirationReceiptOperationID: expirationReceipt,
            terminalBeforeHygieneOrdinal: initialTerminal ? nil : terminalOrdinal, initialTerminal: initialTerminal)
    }

    private func originalEraseC16IngressRecipe(
        for observed: C16IngressPublicationV1
    ) throws -> OriginalEraseC16IngressRecipeV1 {
        try requireScratchDescriptorAccess()
        let source = try originalEraseC16FixedIngressRecipeData(intentID: observed.intent.intentID)
        guard observed == source.expected else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        let pending = try readIngressControl(C16IngressPublicationV1.self, at: ingressControlURL(observed.intent.intentID, ".pending.json"))
        let terminal = try readIngressControl(C16IngressRemovalV1.self, at: ingressControlURL(observed.intent.intentID, ".terminal.json"))
        guard pending == nil || pending == source.expected else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
        for name in try originalEraseC16ReferenceNames() where name.hasPrefix("hygiene-") && name.hasSuffix(".prepare.json") {
            let value = try originalEraseC16ReferenceHygiene(name: name)
            _ = try originalEraseC16HygieneGroupCut(value.current)
        }
        var removal = source.removal
        if removal == nil, terminal != nil,
           originalEraseC16ReferencePlan?.freshPublishedTargets.contains(where: {
               $0.intentID == observed.intent.intentID && $0.directory == OriginalEraseC16TargetFactV1(observed)
           }) == true { removal = .init(expected: source.expected, disposition: .erased) }
        if let terminal {
            try terminal.validate()
            guard terminal == removal else { throw ScratchDataLeaseStoreFailureV1.leaseCollision }
            if let id = source.expirationReceiptOperationID, !source.initialTerminal {
                let prepare = try originalEraseC16ReferenceValue(C16IngressHygienePrepareV1.self,
                    name: "hygiene-" + id.uuidString.lowercased() + ".prepare.json")
                guard try readProtectedIngressReceipt(at: protectedIngressReceiptFile(operationID: id),
                    operationID: id) == prepare.receipt(),
                    originalEraseC16TargetCut(.init(observed)) == .absent else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
            }
        }
        if source.removal?.disposition == .erased, source.hygiene.isEmpty,
           !source.initialTerminal, terminal == nil {
            guard pending == source.expected, try originalEraseC16TargetCut(.init(observed)) == .original else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
        }
        return .init(expected: source.expected, removal: removal, hygiene: source.hygiene,
            expirationReceiptOperationID: source.expirationReceiptOperationID,
            terminalBeforeHygieneOrdinal: source.terminalBeforeHygieneOrdinal, initialTerminal: source.initialTerminal)
    }

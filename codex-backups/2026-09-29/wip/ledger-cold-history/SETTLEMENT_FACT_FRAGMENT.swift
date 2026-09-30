    private func originalEraseC16FirstPAllowsOneLinkSettlement(
        path: String, plan: OriginalEraseC16PlanV1
    ) throws -> Bool {
        try requireScratchDescriptorAccess()
        guard let raw = originalEraseC16FirstPFacts[path],
              try OriginalEraseC16PhysicalFactV1(raw).linkCount == 2 else { return false }
        for step in plan.steps {
            guard case let .settleFirstPPartial(location, name, _, _, _) = step else { continue }
            let partialPath: String
            switch location {
            case .control: partialPath = "ProtectedIngressReceiptsV1/" + name
            case let .lease(lease): partialPath = "ScratchDataV1/" + lease + "/" + name
            }
            guard partialPath != path,
                  URL(fileURLWithPath: partialPath).deletingLastPathComponent()
                    == URL(fileURLWithPath: path).deletingLastPathComponent() else { continue }
            if originalEraseC16FirstPFacts[partialPath] == raw { return true }
        }
        return false
    }

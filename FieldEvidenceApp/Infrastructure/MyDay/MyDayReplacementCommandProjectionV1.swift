import Foundation

/// Exact typed command correspondence for the complete C57 value projection.
/// Global restore remains responsible for original receipt admission and the
/// destination workspace, generation, replica and journal revision frontiers.
enum MyDayReplacementCommandProjectionV1 {
    struct CommandPair: Equatable, Sendable {
        let source: MyDayCommandV1
        let target: MyDayCommandV1
        fileprivate init(source: MyDayCommandV1, target: MyDayCommandV1) {
            self.source = source; self.target = target
        }
    }

    struct Result: Equatable, Sendable {
        let values: MyDayReplacementValueProjectionV1.Result
        let commands: [CommandPair]

        fileprivate init(values: MyDayReplacementValueProjectionV1.Result, commands: [CommandPair]) {
            self.values = values; self.commands = commands
        }

        func targetCommand(for original: MyDayCommandV1) throws -> MyDayCommandV1 {
            try original.validate()
            let matches = commands.filter { $0.source.mutationID == original.mutationID }
            guard matches.count == 1, let pair = matches.first, pair.source == original else {
                throw MyDayReplacementValueProjectionFailureV1.invalidSource
            }
            return pair.target
        }

        func targetMutation(for original: MyDayMutationV1,
                            expectedRevision: WorkspaceExpectedRevisionV1) throws -> MyDayMutationV1 {
            try original.validate()
            return try .init(command: targetCommand(for: original.command), expectedRevision: expectedRevision)
        }
    }

    static func project(_ source: MyDayReplacementValueProjectionV1.Source,
                        bindings: MyDayReplacementValueProjectionV1.Bindings) throws -> Result {
        let values = try MyDayReplacementValueProjectionV1.project(source, bindings: bindings)
        let sourcePlans = try planMap(values.plans.map(\.source))
        let targetPlans = try planMap(values.plans.map(\.target))
        let sourceCarryovers = Dictionary(grouping: values.carryovers, by: { $0.source.targetPlan })
        guard sourceCarryovers.values.allSatisfy({ $0.count == 1 }) else {
            throw MyDayReplacementValueProjectionFailureV1.invalidSource
        }
        var pairs: [CommandPair] = []
        var usedCarryovers = Set<MyDayPlanReferenceV1>()
        for plan in values.plans {
            let reference = try MyDayPlanReferenceV1(plan.source)
            let sourceCommand: MyDayCommandV1
            let targetCommand: MyDayCommandV1
            if let carryover = sourceCarryovers[reference]?.first {
                guard let originalSource = sourcePlans[carryover.source.sourcePlan],
                      let targetSource = targetPlans[carryover.target.sourcePlan],
                      carryover.target.targetPlan == (try MyDayPlanReferenceV1(plan.target)),
                      usedCarryovers.insert(reference).inserted else {
                    throw MyDayReplacementValueProjectionFailureV1.incompleteProjection
                }
                sourceCommand = .carryover(plan: carryover.sourceCommandPlan, source: originalSource,
                                           target: plan.source, receipt: carryover.source)
                targetCommand = .carryover(plan: carryover.targetCommandPlan, source: targetSource,
                                           target: plan.target, receipt: carryover.target)
            } else {
                sourceCommand = .save(successor: plan.source,
                                      predecessor: try predecessor(of: plan.source, in: sourcePlans))
                targetCommand = .save(successor: plan.target,
                                      predecessor: try predecessor(of: plan.target, in: targetPlans))
            }
            try sourceCommand.validate(); try targetCommand.validate()
            guard sourceCommand.mutationID == plan.source.mutationID,
                  targetCommand.mutationID == plan.target.mutationID else {
                throw MyDayReplacementValueProjectionFailureV1.incompleteProjection
            }
            pairs.append(.init(source: sourceCommand, target: targetCommand))
        }
        guard pairs.count == source.snapshot.plans.count,
              usedCarryovers.count == source.snapshot.carryoverReceipts.count,
              Set(pairs.map { $0.source.mutationID }).count == pairs.count,
              Set(pairs.map { $0.target.mutationID }).count == pairs.count else {
            throw MyDayReplacementValueProjectionFailureV1.incompleteProjection
        }
        return .init(values: values, commands: pairs)
    }

    private static func planMap(_ plans: [MyDayPlanV1]) throws -> [MyDayPlanReferenceV1: MyDayPlanV1] {
        var result: [MyDayPlanReferenceV1: MyDayPlanV1] = [:]
        for plan in plans {
            guard result.updateValue(plan, forKey: try MyDayPlanReferenceV1(plan)) == nil else {
                throw MyDayReplacementValueProjectionFailureV1.invalidSource
            }
        }
        return result
    }

    private static func predecessor(of plan: MyDayPlanV1,
                                    in plans: [MyDayPlanReferenceV1: MyDayPlanV1]) throws -> MyDayPlanV1? {
        if plan.revision == 1 {
            guard plan.predecessorPlanSHA256 == nil else {
                throw MyDayReplacementValueProjectionFailureV1.invalidSource
            }
            return nil
        }
        let matches = plans.values.filter {
            $0.planID == plan.planID && $0.key == plan.key && $0.revision == plan.revision - 1
                && $0.planSHA256 == plan.predecessorPlanSHA256
        }
        guard matches.count == 1, let predecessor = matches.first else {
            throw MyDayReplacementValueProjectionFailureV1.incompleteProjection
        }
        return predecessor
    }
}

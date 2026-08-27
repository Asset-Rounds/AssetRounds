import Foundation

struct WorkflowGraphValidationReceiptV1: Equatable, Sendable {
    let workflowID: String
    let nodeCount: Int
    let edgeCount: Int
    let branchCount: Int
    let repeatGroupCount: Int
    let maximumObservedDepth: Int
    let orderedNodeIDs: [String]
    let valid: Bool
}

enum WorkflowGraphValidatorV1 {
    static func validate(_ definition: WorkflowDefinitionV1) throws
        -> WorkflowGraphValidationReceiptV1 {
        guard definition.schemaVersion == WorkflowDefinitionV1.schemaVersion,
              !definition.nodes.isEmpty,
              definition.nodes.count <= WorkflowGrammarLimitsV1.maximumNodeCount,
              definition.declaredFieldIDs.count <= WorkflowGrammarLimitsV1.maximumFieldCount else {
            throw InspectionKernelFailureV1.limitExceeded
        }
        let nodeIDs = definition.nodes.map(\.nodeID)
        guard Set(nodeIDs).count == nodeIDs.count else {
            throw InspectionKernelFailureV1.duplicateIdentity
        }
        let nodes = Dictionary(uniqueKeysWithValues: definition.nodes.map { ($0.nodeID, $0) })
        guard nodes[definition.entryNodeID] != nil else {
            throw InspectionKernelFailureV1.missingTarget
        }
        try definition.nodes.forEach { try $0.validateShape() }
        let edges = definition.nodes.reduce(0) { $0 + $1.outgoingNodeIDs.count }
        guard edges <= WorkflowGrammarLimitsV1.maximumEdgeCount else {
            throw InspectionKernelFailureV1.limitExceeded
        }
        for node in definition.nodes {
            guard node.outgoingNodeIDs.allSatisfy({ nodes[$0] != nil }) else {
                throw InspectionKernelFailureV1.missingTarget
            }
            if let exit = node.repeatBodyExitNodeID, nodes[exit] == nil {
                throw InspectionKernelFailureV1.missingTarget
            }
        }
        let reachableIDs = try reachableAndAcyclic(
            entry: definition.entryNodeID,
            nodes: nodes
        )
        guard reachableIDs.count == nodes.count else {
            throw InspectionKernelFailureV1.unreachableNode
        }
        let maximumDepth = longestPathDepth(
            entry: definition.entryNodeID,
            nodes: nodes
        )
        guard maximumDepth <= WorkflowGrammarLimitsV1.maximumGraphDepth else {
            throw InspectionKernelFailureV1.limitExceeded
        }
        let factNodes = definition.nodes.filter { $0.kind == .fact }
        let factFields = factNodes.compactMap(\.fieldID)
        guard Set(factFields).count == factFields.count else {
            throw InspectionKernelFailureV1.duplicateIdentity
        }
        guard Set(factFields).isSubset(of: Set(definition.declaredFieldIDs)) else {
            throw InspectionKernelFailureV1.missingFieldID
        }
        let dominators = computeDominators(
            entry: definition.entryNodeID,
            nodes: nodes
        )
        for repeatNode in definition.nodes where repeatNode.kind == .repeatGroup {
            guard let entry = repeatNode.repeatBodyEntryNodeID,
                  let exit = repeatNode.repeatBodyExitNodeID,
                  repeatNode.outgoingNodeIDs.count == 2 else {
                throw InspectionKernelFailureV1.invalidCardinality
            }
            let successor = repeatNode.outgoingNodeIDs[1]
            guard dominators[entry]?.contains(repeatNode.nodeID) == true,
                  dominators[exit]?.contains(repeatNode.nodeID) == true,
                  nodes[exit]?.outgoingNodeIDs == [successor] else {
                throw InspectionKernelFailureV1.invalidCardinality
            }
            try validateRepeatContainment(
                repeatNodeID: repeatNode.nodeID,
                entry: entry,
                exit: exit,
                successor: successor,
                nodes: nodes
            )
        }
        let factNodeByField = Dictionary(uniqueKeysWithValues: factNodes.compactMap {
            guard let fieldID = $0.fieldID else { return nil }
            return (fieldID, $0.nodeID)
        })
        for node in definition.nodes where node.kind == .branch {
            guard let predicate = node.predicate else {
                throw InspectionKernelFailureV1.invalidCardinality
            }
            for fieldID in predicate.referencedFieldIDs() {
                guard definition.declaredFieldIDs.contains(fieldID),
                      let factNodeID = factNodeByField[fieldID] else {
                    throw InspectionKernelFailureV1.missingFieldID
                }
                guard dominators[node.nodeID]?.contains(factNodeID) == true,
                      factNodeID != node.nodeID else {
                    throw InspectionKernelFailureV1.forwardPredicateReference
                }
            }
        }
        let branchCount = definition.nodes.filter { $0.kind == .branch }.count
        let repeats = definition.nodes.filter { $0.kind == .repeatGroup }
        guard branchCount <= WorkflowGrammarLimitsV1.maximumBranchCount else {
            throw InspectionKernelFailureV1.limitExceeded
        }
        var maximumMultiplier = 1
        for repeatNode in repeats {
            guard let count = repeatNode.maximumRepeatInstances,
                  count <= WorkflowGrammarLimitsV1.maximumTotalExecutions / maximumMultiplier else {
                throw InspectionKernelFailureV1.limitExceeded
            }
            maximumMultiplier *= count
        }
        guard definition.nodes.count
                <= WorkflowGrammarLimitsV1.maximumTotalExecutions / maximumMultiplier else {
            throw InspectionKernelFailureV1.limitExceeded
        }
        return WorkflowGraphValidationReceiptV1(
            workflowID: definition.workflowID,
            nodeCount: definition.nodes.count,
            edgeCount: edges,
            branchCount: branchCount,
            repeatGroupCount: repeats.count,
            maximumObservedDepth: maximumDepth,
            orderedNodeIDs: nodeIDs.sorted(),
            valid: true
        )
    }

    private static func reachableAndAcyclic(
        entry: String,
        nodes: [String: WorkflowNodeV1]
    ) throws -> Set<String> {
        var visiting = Set<String>()
        var visited = Set<String>()
        func visit(_ id: String) throws {
            if visiting.contains(id) { throw InspectionKernelFailureV1.cycleDetected }
            if visited.contains(id) { return }
            guard let node = nodes[id] else { throw InspectionKernelFailureV1.missingTarget }
            visiting.insert(id)
            for target in node.outgoingNodeIDs { try visit(target) }
            visiting.remove(id)
            visited.insert(id)
        }
        try visit(entry)
        return visited
    }

    // Cycle validation runs first. Repeated relaxation therefore converges to the
    // exact longest entry-to-node path even when several branches converge.
    private static func longestPathDepth(
        entry: String,
        nodes: [String: WorkflowNodeV1]
    ) -> Int {
        var depths = [entry: 1]
        for _ in 0..<nodes.count {
            var changed = false
            for nodeID in nodes.keys.sorted() {
                guard let node = nodes[nodeID], let depth = depths[nodeID] else { continue }
                for target in node.outgoingNodeIDs {
                    let candidate = depth + 1
                    if candidate > (depths[target] ?? 0) {
                        depths[target] = candidate
                        changed = true
                    }
                }
            }
            if !changed { break }
        }
        return depths.values.max() ?? 0
    }

    private static func computeDominators(
        entry: String,
        nodes: [String: WorkflowNodeV1]
    ) -> [String: Set<String>] {
        let all = Set(nodes.keys)
        var predecessors: [String: Set<String>] = [:]
        for id in nodes.keys { predecessors[id] = [] }
        for node in nodes.values {
            for target in node.outgoingNodeIDs { predecessors[target, default: []].insert(node.nodeID) }
        }
        var result = Dictionary(uniqueKeysWithValues: nodes.keys.map {
            ($0, $0 == entry ? Set([$0]) : all)
        })
        var changed = true
        while changed {
            changed = false
            for id in nodes.keys.sorted() where id != entry {
                let incoming = predecessors[id] ?? []
                var next = incoming.first.map { result[$0] ?? all } ?? []
                for predecessor in incoming.dropFirst() {
                    next.formIntersection(result[predecessor] ?? all)
                }
                next.insert(id)
                if next != result[id] { result[id] = next; changed = true }
            }
        }
        return result
    }

    // A repeat body is a closed single-entry region. Its declared exit is the
    // only body node allowed to reach the successor, and no outside node may
    // enter the region. Applying this independently to every repeat also makes
    // nested repeat boundaries fail closed when they overlap or cross.
    private static func validateRepeatContainment(
        repeatNodeID: String,
        entry: String,
        exit: String,
        successor: String,
        nodes: [String: WorkflowNodeV1]
    ) throws {
        var body = Set<String>()
        var pending = [entry]
        while let current = pending.popLast() {
            if body.contains(current) { continue }
            guard let node = nodes[current] else {
                throw InspectionKernelFailureV1.missingTarget
            }
            body.insert(current)
            if current == exit { continue }
            guard !node.outgoingNodeIDs.isEmpty else {
                throw InspectionKernelFailureV1.invalidCardinality
            }
            for target in node.outgoingNodeIDs {
                guard target != successor, target != repeatNodeID else {
                    throw InspectionKernelFailureV1.invalidCardinality
                }
                pending.append(target)
            }
        }
        guard body.contains(exit) else {
            throw InspectionKernelFailureV1.invalidCardinality
        }

        var canReachExit: Set<String> = [exit]
        var changed = true
        while changed {
            changed = false
            for id in body.sorted() where !canReachExit.contains(id) {
                guard let node = nodes[id] else { continue }
                if node.outgoingNodeIDs.contains(where: canReachExit.contains) {
                    canReachExit.insert(id)
                    changed = true
                }
            }
        }
        guard canReachExit == body else {
            throw InspectionKernelFailureV1.invalidCardinality
        }

        for node in nodes.values where node.nodeID != repeatNodeID && !body.contains(node.nodeID) {
            guard node.outgoingNodeIDs.allSatisfy({ !body.contains($0) }) else {
                throw InspectionKernelFailureV1.invalidCardinality
            }
        }
    }
}

from pathlib import Path
p=Path('.codex-temp/cold-physical-continuation-successor-v3/candidate/FieldEvidenceApp/Infrastructure/Persistence/EraseSchema2ColdAuxiliaryFirstObservationV1.swift')
s=p.read_text()
s=s.replace('planSHA256 == (try CompatibilityCanonicalV1.sha256(CompatibilityCanonicalV1.encode(c16Plan))),\n              fixedTargets.count <= 100_000 else', 'planSHA256 == (try CompatibilityCanonicalV1.sha256(CompatibilityCanonicalV1.encode(c16Plan))) else')
s=s.replace('guard result.count <= 100_000, Set(result.map(\\.path)).count == result.count else {', 'guard Set(result.map(\\.path)).count == result.count else {')
needle='''    /// Construct once from the immutable original record and canonical plan.
'''
add='''    /// These are the immutable roster's nine domains, in its wire order.
    /// The three named parents are projection roles, never additional trees.
    static let recordedRootKeys = [
        "support/FieldEvidenceRestore", "support/FieldEvidenceCommerce",
        "support/FieldEvidenceDiagnostics", "support/LocalSearchIndexV1",
        "support/PortableReviewExchangeV2", "support/local-jobs-v1",
        "support/FieldEvidenceOperations", "caches/FieldEvidenceApp",
        "temporary/FieldEvidenceApp"
    ]
    struct RecordedRootCensusV1: Codable, Equatable {
        let key: String
        let originalNodeCount: Int
        let originalRegularBytes: Int64
        let genericTargetCount: Int
    }
    private static func relativePath(_ path: String, root: String) throws -> String {
        guard path == root || path.hasPrefix(root + "/") else {
            throw EraseAllServiceError.invalidAuthority
        }
        let relative = path == root ? "" : String(path.dropFirst(root.count + 1))
        if !relative.isEmpty {
            let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\0") }) else {
                throw EraseAllServiceError.invalidAuthority
            }
        }
        return relative
    }
    private static func requireOriginalRootCensus(_ originalP: EraseSchema2ColdAuxiliaryPhysicalRosterV1) throws -> [(Int, Int64)] {
        guard originalP.canonicalBytes == (try StoreMigrationCanonicalJSONV1.encode(originalP.record)),
              originalP.canonicalSHA256 == StoreMigrationCanonicalJSONV1.sha256(originalP.canonicalBytes),
              originalP.record.trees.map(\\.key) == recordedRootKeys else {
            throw EraseAllServiceError.invalidAuthority
        }
        return try originalP.record.trees.map { tree in
            if tree.state == "absent" {
                guard tree.rootFact == nil, tree.digest == nil, tree.nodes == nil, tree.deletionOrder == nil else {
                    throw EraseAllServiceError.invalidAuthority
                }
                return (0, 0)
            }
            guard tree.state == "present", let nodes = tree.nodes, !nodes.isEmpty,
                  nodes.count < 100_000, nodes.first?.path == "", nodes.first?.kind == "directory",
                  let rootFact = tree.rootFact, let digest = tree.digest,
                  StoreMigrationCanonicalJSONV1.isLowercaseSHA256(digest),
                  nodes.map(\\.path) == nodes.map(\\.path).sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }),
                  Set(nodes.map(\\.path)).count == nodes.count,
                  let order = tree.deletionOrder, Set(order) == Set(nodes.map(\\.path)), order.count == nodes.count,
                  try nine(rootFact) == nodes[0].fact else { throw EraseAllServiceError.invalidAuthority }
            let byPath = Dictionary(uniqueKeysWithValues: nodes.map { ($0.path, $0) })
            var bytes: Int64 = 0
            for node in nodes {
                let qualified = node.path.isEmpty ? tree.key : tree.key + "/" + node.path
                let relative = try relativePath(qualified, root: tree.key)
                let parts = relative.isEmpty ? [] : relative.split(separator: "/").map(String.init)
                let f = try fields(node.fact, count: 9)
                guard let mode = UInt32(f[2]), parts.count <= (node.kind == "directory" ? 64 : 65),
                      relative.isEmpty || byPath[parts.dropLast().joined(separator: "/")]?.kind == "directory" else {
                    throw EraseAllServiceError.invalidAuthority
                }
                if node.kind == "directory" {
                    guard mode & UInt32(S_IFMT) == UInt32(S_IFDIR), node.sha256 == nil,
                          let members = node.members, members == members.sorted(),
                          Set(members).count == members.count else { throw EraseAllServiceError.invalidAuthority }
                    let children = nodes.filter { other in
                        guard other.path != relative, !other.path.isEmpty else { return false }
                        return other.path.split(separator: "/").dropLast().joined(separator: "/") == relative
                    }.map { String($0.path.split(separator: "/").last!) }.sorted()
                    guard members == children else { throw EraseAllServiceError.invalidAuthority }
                } else {
                    guard node.kind == "file", mode & UInt32(S_IFMT) == UInt32(S_IFREG),
                          node.members == nil, let sha = node.sha256,
                          StoreMigrationCanonicalJSONV1.isLowercaseSHA256(sha),
                          let size = Int64(f[4]), size <= 1_073_741_824, bytes <= 1_073_741_824 - size else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    bytes += size
                }
            }
            let expectedOrder = nodes.map(\\.path).sorted { lhs, rhs in
                let left = lhs.isEmpty ? 0 : lhs.split(separator: "/").count
                let right = rhs.isEmpty ? 0 : rhs.split(separator: "/").count
                return left == right ? lhs.utf8.lexicographicallyPrecedes(rhs.utf8) : left > right
            }
            guard order == expectedOrder else { throw EraseAllServiceError.invalidAuthority }
            return (nodes.count, bytes)
        }
    }
    /// Pure source data for losslessly segmented controls. The logical mixed
    /// stream is C16's independently bounded steps plus these exact counts;
    /// no global node limit narrows the nine admitted original trees.
    static func fixedRootCensus(originalP: EraseSchema2ColdAuxiliaryPhysicalRosterV1,
        c16Plan: OriginalEraseC16PlanV1, targetGenerationID: UUID) throws -> [RecordedRootCensusV1] {
        let original = try requireOriginalRootCensus(originalP)
        let generic = try fixedNonC16Targets(originalP: originalP, c16Plan: c16Plan, targetGenerationID: targetGenerationID)
        return recordedRootKeys.enumerated().map { index, key in
            RecordedRootCensusV1(key: key, originalNodeCount: original[index].0,
                originalRegularBytes: original[index].1,
                genericTargetCount: generic.filter { $0.path == key || $0.path.hasPrefix(key + "/") }.count)
        }
    }
    /// This is a grammar/bounds check of actual data, never an EX, source,
    /// policy, OS, birth or current-progress receipt. Those remain mandatory
    /// in the enclosing retained scope and physical permit at every IO.
    static func requireRecordedProjectionCensus(originalP: EraseSchema2ColdAuxiliaryPhysicalRosterV1,
        projection: [Progress.Projection]) throws {
        _ = try requireOriginalRootCensus(originalP)
        guard projection.map(\\.path) == projection.map(\\.path).sorted(),
              Set(projection.map(\\.path)).count == projection.count else { throw EraseAllServiceError.invalidAuthority }
        let parents = ["support", "caches", "temporary"]
        let byPath = Dictionary(uniqueKeysWithValues: projection.map { ($0.path, $0) })
        for (index, parent) in parents.enumerated() {
            guard let node = byPath[parent], node.sha256 == nil else { throw EraseAllServiceError.invalidAuthority }
            let f = try fields(node.fullFact)
            let expected: (Int64, UInt64, UInt32, UInt32, UInt32)
            switch index {
            case 0: expected = (originalP.record.supportDevice, originalP.record.supportInode, originalP.record.supportMode, originalP.record.supportUser, originalP.record.supportGroup)
            case 1: expected = (originalP.record.cachesDevice, originalP.record.cachesInode, originalP.record.cachesMode, originalP.record.cachesUser, originalP.record.cachesGroup)
            default: expected = (originalP.record.temporaryDevice, originalP.record.temporaryInode, originalP.record.temporaryMode, originalP.record.temporaryUser, originalP.record.temporaryGroup)
            }
            guard Int64(f[0]) == expected.0, UInt64(f[1]) == expected.1, UInt32(f[2]) == expected.2,
                  UInt32(f[3]) == expected.3, UInt32(f[4]) == expected.4,
                  expected.2 & UInt32(S_IFMT) == UInt32(S_IFDIR) else { throw EraseAllServiceError.invalidAuthority }
        }
        guard projection.allSatisfy({ item in parents.contains(item.path)
            || recordedRootKeys.contains(where: { item.path == $0 || item.path.hasPrefix($0 + "/") }) }) else {
            throw EraseAllServiceError.invalidAuthority
        }
        for root in recordedRootKeys {
            let nodes = projection.filter { $0.path == root || $0.path.hasPrefix(root + "/") }
            guard nodes.count <= 100_000 else { throw EraseAllServiceError.invalidAuthority }
            if nodes.isEmpty { continue }
            guard let rootNode = byPath[root], rootNode.sha256 == nil,
                  let parent = byPath[String(root.split(separator: "/").first!) ] else { throw EraseAllServiceError.invalidAuthority }
            let parentFields = try fields(parent.fullFact)
            var bytes: Int64 = 0
            for node in nodes {
                let relative = try relativePath(node.path, root: root)
                let parts = relative.isEmpty ? [] : relative.split(separator: "/").map(String.init)
                let f = try fields(node.fullFact)
                guard let mode = UInt32(f[2]), f[0] == parentFields[0], f[3] == parentFields[3], f[4] == parentFields[4] else {
                    throw EraseAllServiceError.invalidAuthority
                }
                let directory = mode & UInt32(S_IFMT) == UInt32(S_IFDIR)
                guard parts.count <= (directory ? 64 : 65), mode & 0o7777 == (directory ? 0o700 : 0o600) else {
                    throw EraseAllServiceError.invalidAuthority
                }
                if !relative.isEmpty {
                    let parentPath = parts.count == 1 ? root : root + "/" + parts.dropLast().joined(separator: "/")
                    guard let enclosing = byPath[parentPath],
                          (try UInt32(fields(enclosing.fullFact)[2]))! & UInt32(S_IFMT) == UInt32(S_IFDIR) else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                }
                if directory {
                    guard node.sha256 == nil else { throw EraseAllServiceError.invalidAuthority }
                } else {
                    guard mode & UInt32(S_IFMT) == UInt32(S_IFREG), let sha = node.sha256,
                          StoreMigrationCanonicalJSONV1.isLowercaseSHA256(sha),
                          let size = Int64(f[6]), size <= 1_073_741_824, bytes <= 1_073_741_824 - size else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    bytes += size
                }
            }
        }
    }

'''
assert needle in s
s=s.replace(needle,add+needle)
s=s.replace('''        let operationsKey = "support/FieldEvidenceOperations"
        guard let operations''','''        _ = try requireOriginalRootCensus(originalP)
        let operationsKey = "support/FieldEvidenceOperations"
        guard let operations''',1)
s=s.replace('''        try permit.requireExternalBranches(projection)
        return Image''','''        try Self.requireRecordedProjectionCensus(originalP: originalP, projection: projection)
        try permit.requireExternalBranches(projection)
        return Image''',1)
p.write_text(s)

from pathlib import Path
base=Path('.codex-temp/cold-physical-continuation-successor-v4/candidate/FieldEvidenceApp/Infrastructure/Persistence')
p=base/'StoreGenerationFactory.swift';s=p.read_text()
needle='''/// Descriptor owner for the completed-abort source-byte witness.'''
add='''/// Immutable ORIGINAL-P accounting data, privately bound only after a real
/// complete FirstCapture consumer and exact original record match. This never
/// supplies a current pair policy/effect scope or an invented cold origin.
@MainActor
final class EraseSchema2ColdOriginalPairAccountingRosterV1 {
    let originalPAuxiliaryRosterSHA256: String
    let operationID: UUID
    let captureOriginBinding: String
    let pairs: [EraseAbortCheckedSnapshotIOV1.Schema2ColdAuthenticatedPairObservationV1]
    fileprivate init(rosterSHA256: String, operationID: UUID, captureOriginBinding: String,
        pairs: [EraseAbortCheckedSnapshotIOV1.Schema2ColdAuthenticatedPairObservationV1]) {
        originalPAuxiliaryRosterSHA256 = rosterSHA256; self.operationID = operationID
        self.captureOriginBinding = captureOriginBinding; self.pairs = pairs
    }
    /// Pure immutable lineage comparison. The enclosing actual Router/Store
    /// source permit still proves the current record and source authority.
    func requireOriginalPBinding(originalPAuxiliaryRosterSHA256: String) throws {
        guard self.originalPAuxiliaryRosterSHA256 == originalPAuxiliaryRosterSHA256,
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(originalPAuxiliaryRosterSHA256),
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(captureOriginBinding) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }
}

'''
assert needle in s;s=s.replace(needle,add+needle,1)
needle='''    @MainActor
    func schema2ColdCurrentC16Tree('''
add='''    /// Original capture only: a genuine fresh private scope reproofs the
    /// same source image before/after binding the complete observed tree to P.
    /// Cold replay needs its separately reviewed lossless source-role format;
    /// no decoder or caller alias-map shortcut is provided by this method.
    @MainActor
    static func makeOriginalPairAccountingRoster(
        originalP: EraseSchema2ColdAuxiliaryPhysicalRosterV1,
        capturedOperationsTree: Schema2ColdCurrentTreeV1,
        scope: OriginalEraseC16FirstCaptureObservationScopeV1
    ) throws -> EraseSchema2ColdOriginalPairAccountingRosterV1 {
        try scope.requireCurrentBinding()
        guard originalP.canonicalBytes == (try StoreMigrationCanonicalJSONV1.encode(originalP.record)),
              originalP.canonicalSHA256 == StoreMigrationCanonicalJSONV1.sha256(originalP.canonicalBytes),
              let tree = originalP.record.trees.first(where: { $0.key == "support/FieldEvidenceOperations" }),
              tree.state == "present", let nodes = tree.nodes,
              capturedOperationsTree.rootFact == tree.rootFact, capturedOperationsTree.digest == tree.digest,
              capturedOperationsTree.nodes.count == nodes.count, capturedOperationsTree.work != nil else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        let byPath = Dictionary(uniqueKeysWithValues: nodes.map { ($0.path, $0) })
        func nine(_ full: String) throws -> String {
            let f = full.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 11 else { throw StoreGenerationFailure.dataPointerInvalid }
            return [f[0],f[1],f[2],f[5],f[6],f[7],f[8],f[9],f[10]].joined(separator: "|")
        }
        for actual in capturedOperationsTree.nodes {
            guard let original = byPath[actual.path], original.fact == (try nine(actual.fullFact)),
                  original.members == actual.names, original.sha256 == actual.sha256,
                  original.kind == (actual.names == nil ? "file" : "directory"), actual.policy != nil else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        }
        var members = Set<String>()
        for pair in capturedOperationsTree.typedPairs {
            guard pair.operationID == scope.operationID, pair.originBinding == scope.captureToken,
                  pair.originKind == "firstCaptureCanonical" || pair.originKind == "firstCaptureObservedGeneric",
                  pair.treeRelativeMemberPaths == pair.operationsRelativeMemberPaths,
                  pair.observedFacts.count == 2, pair.fullFacts.count == 2,
                  pair.operationsRelativeMemberPaths.count == 2 else { throw StoreGenerationFailure.dataPointerInvalid }
            for index in 0..<2 {
                let path = pair.operationsRelativeMemberPaths[index]
                guard members.insert(path).inserted, let original = byPath[path], original.kind == "file",
                      original.fact == pair.observedFacts[index], original.sha256 == pair.sha256 else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
            }
            if let metadata = pair.genericMetadata {
                switch metadata {
                case .validatedLease(let directory, let canonicalBytes, let hash):
                    guard StoreMigrationCanonicalJSONV1.sha256(canonicalBytes) == hash,
                          byPath[directory + "/lease.json"]?.sha256 == hash,
                          pair.operationsRelativeMemberPaths.allSatisfy({ $0.split(separator: "/").dropLast().joined(separator: "/") == directory }) else {
                        throw StoreGenerationFailure.dataPointerInvalid
                    }
                case .ownedOrphan(let directory):
                    guard byPath[directory + "/lease.json"] == nil,
                          pair.operationsRelativeMemberPaths.allSatisfy({ $0.split(separator: "/").dropLast().joined(separator: "/") == directory }) else {
                        throw StoreGenerationFailure.dataPointerInvalid
                    }
                }
            }
        }
        for node in nodes where node.kind == "file" {
            let f = node.fact.split(separator: "|", omittingEmptySubsequences: false)
            guard f.count == 9, let links = UInt64(f[3]),
                  links == 1 || (links == 2 && members.contains(node.path)) else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        }
        try scope.requireCurrentBinding()
        return .init(rosterSHA256: originalP.canonicalSHA256, operationID: scope.operationID,
            captureOriginBinding: scope.captureToken, pairs: capturedOperationsTree.typedPairs)
    }

'''
assert needle in s;s=s.replace(needle,add+needle,1);p.write_text(s)
p=base/'EraseSchema2ColdAuxiliaryFirstObservationV1.swift';s=p.read_text()
s=s.replace('''    private let plan: OriginalEraseC16PlanV1
''','''    private let plan: OriginalEraseC16PlanV1
    private let originalPairAccounting: EraseSchema2ColdOriginalPairAccountingRosterV1?
''',1)
s=s.replace('''        targetGenerationID: UUID, planSHA256: String) throws {''','''        targetGenerationID: UUID, planSHA256: String,
        originalPairAccounting: EraseSchema2ColdOriginalPairAccountingRosterV1? = nil) throws {''',1)
s=s.replace('''Self.fixedNonC16Targets(originalP: originalP, c16Plan: c16Plan, targetGenerationID: targetGenerationID)''','''Self.fixedNonC16Targets(originalP: originalP, c16Plan: c16Plan, targetGenerationID: targetGenerationID, originalPairAccounting: originalPairAccounting)''',1)
s=s.replace('''        self.originalP = originalP; self.initial = initial; self.plan = c16Plan
''','''        self.originalP = originalP; self.initial = initial; self.plan = c16Plan
        self.originalPairAccounting = originalPairAccounting
''',1)
s=s.replace('''    private static func requireOriginalRootCensus(_ originalP: EraseSchema2ColdAuxiliaryPhysicalRosterV1) throws -> [(Int, Int64)] {''','''    private static func requireOriginalRootCensus(_ originalP: EraseSchema2ColdAuxiliaryPhysicalRosterV1,
        originalPairAccounting: EraseSchema2ColdOriginalPairAccountingRosterV1? = nil) throws -> [(Int, Int64)] {''',1)
needle='''        return try originalP.record.trees.map { tree in'''
add='''        try originalPairAccounting?.requireOriginalPBinding(originalPAuxiliaryRosterSHA256: originalP.canonicalSHA256)
        var typedPairByPath: [String: EraseAbortCheckedSnapshotIOV1.Schema2ColdAuthenticatedPairObservationV1] = [:]
        for pair in originalPairAccounting?.pairs ?? [] {
            guard pair.operationsRelativeMemberPaths.count == 2, pair.observedFacts.count == 2,
                  pair.observedFacts[0] == pair.observedFacts[1], pair.byteCount >= 0,
                  pair.byteCount <= 1_073_741_824,
                  StoreMigrationCanonicalJSONV1.isLowercaseSHA256(pair.sha256) else { throw EraseAllServiceError.invalidAuthority }
            for path in pair.operationsRelativeMemberPaths {
                guard typedPairByPath.updateValue(pair, forKey: "support/FieldEvidenceOperations/" + path) == nil else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
        }
'''
assert needle in s;s=s.replace(needle,add+needle,1)
s=s.replace('''            var bytes: Int64 = 0
            for node in nodes {''','''            var bytes: Int64 = 0
            var chargedTypedPairs = Set<String>()
            for node in nodes {''',1)
needle='''                          let size = Int64(f[4]), size <= 1_073_741_824, bytes <= 1_073_741_824 - size else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    bytes += size
'''
replace='''                          let size = Int64(f[4]), size <= 1_073_741_824, let links = UInt64(f[3]) else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    if let pair = typedPairByPath[qualified] {
                        guard links == 2, pair.observedFacts.contains(node.fact), pair.sha256 == sha,
                              pair.byteCount == size, Int64(pair.device) == Int64(f[0]), pair.inode == UInt64(f[1]),
                              pair.operationsRelativeMemberPaths.allSatisfy({ member in
                                  byPath[member]?.fact == node.fact && byPath[member]?.sha256 == sha
                              }) else { throw EraseAllServiceError.invalidAuthority }
                        let key = String(pair.device) + "|" + String(pair.inode)
                        if chargedTypedPairs.insert(key).inserted {
                            guard bytes <= 1_073_741_824 - size else { throw EraseAllServiceError.invalidAuthority }
                            bytes += size
                        }
                    } else {
                        guard links == 1, bytes <= 1_073_741_824 - size else { throw EraseAllServiceError.invalidAuthority }
                        bytes += size
                    }
'''
assert needle in s;s=s.replace(needle,replace,1)
s=s.replace('''        c16Plan: OriginalEraseC16PlanV1, targetGenerationID: UUID) throws -> [RecordedRootCensusV1] {
        let original = try requireOriginalRootCensus(originalP)
        let generic = try fixedNonC16Targets(originalP: originalP, c16Plan: c16Plan, targetGenerationID: targetGenerationID)''','''        c16Plan: OriginalEraseC16PlanV1, targetGenerationID: UUID,
        originalPairAccounting: EraseSchema2ColdOriginalPairAccountingRosterV1? = nil) throws -> [RecordedRootCensusV1] {
        let original = try requireOriginalRootCensus(originalP, originalPairAccounting: originalPairAccounting)
        let generic = try fixedNonC16Targets(originalP: originalP, c16Plan: c16Plan, targetGenerationID: targetGenerationID, originalPairAccounting: originalPairAccounting)''',1)
s=s.replace('''        projection: [Progress.Projection]) throws {
        _ = try requireOriginalRootCensus(originalP)
        try requireCurrentProjectionBounds(originalP: originalP, projection: projection)
''','''        projection: [Progress.Projection], originalPairAccounting: EraseSchema2ColdOriginalPairAccountingRosterV1? = nil,
        currentTypedPairs: [EraseAbortCheckedSnapshotIOV1.Schema2ColdAuthenticatedPairObservationV1] = []) throws {
        _ = try requireOriginalRootCensus(originalP, originalPairAccounting: originalPairAccounting)
        try requireCurrentProjectionBounds(originalP: originalP, projection: projection, currentTypedPairs: currentTypedPairs)
''',1)
s=s.replace('''    private static func requireCurrentProjectionBounds(originalP: EraseSchema2ColdAuxiliaryPhysicalRosterV1,
        projection: [Progress.Projection]) throws {''','''    private static func requireCurrentProjectionBounds(originalP: EraseSchema2ColdAuxiliaryPhysicalRosterV1,
        projection: [Progress.Projection],
        currentTypedPairs: [EraseAbortCheckedSnapshotIOV1.Schema2ColdAuthenticatedPairObservationV1]) throws {''',1)
needle='''        for root in recordedRootKeys {
            let nodes = projection.filter'''
add='''        var typedPairByPath: [String: EraseAbortCheckedSnapshotIOV1.Schema2ColdAuthenticatedPairObservationV1] = [:]
        for pair in currentTypedPairs {
            guard pair.operationsRelativeMemberPaths.count == 2, pair.fullFacts.count == 2,
                  pair.fullFacts[0] == pair.fullFacts[1], pair.byteCount >= 0, pair.byteCount <= 1_073_741_824 else {
                throw EraseAllServiceError.invalidAuthority
            }
            for (index, path) in pair.operationsRelativeMemberPaths.enumerated() {
                let qualified = "support/FieldEvidenceOperations/" + path
                guard typedPairByPath.updateValue(pair, forKey: qualified) == nil,
                      byPath[qualified]?.fullFact == pair.fullFacts[index], byPath[qualified]?.sha256 == pair.sha256 else {
                    throw EraseAllServiceError.invalidAuthority
                }
            }
        }
'''
assert needle in s;s=s.replace(needle,add+needle,1)
# second bytes declaration is current projection, not original above
start=s.index('''    private static func requireCurrentProjectionBounds(''');end=s.index('''    /// Construct once''',start);block=s[start:end]
block=block.replace('''            var bytes: Int64 = 0
            for node in nodes {''','''            var bytes: Int64 = 0
            var chargedTypedPairs = Set<String>()
            for node in nodes {''',1)
needle='''                          let size = Int64(f[6]), size <= 1_073_741_824, bytes <= 1_073_741_824 - size else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    bytes += size
'''
replace='''                          let size = Int64(f[6]), size <= 1_073_741_824, let links = UInt64(f[5]) else {
                        throw EraseAllServiceError.invalidAuthority
                    }
                    if let pair = typedPairByPath[node.path] {
                        guard links == 2, pair.byteCount == size, pair.sha256 == sha,
                              pair.device == UInt64(f[0]), pair.inode == UInt64(f[1]) else { throw EraseAllServiceError.invalidAuthority }
                        let key = String(pair.device) + "|" + String(pair.inode)
                        if chargedTypedPairs.insert(key).inserted {
                            guard bytes <= 1_073_741_824 - size else { throw EraseAllServiceError.invalidAuthority }
                            bytes += size
                        }
                    } else {
                        guard links == 1, bytes <= 1_073_741_824 - size else { throw EraseAllServiceError.invalidAuthority }
                        bytes += size
                    }
'''
assert needle in block;block=block.replace(needle,replace,1);s=s[:start]+block+s[end:]
s=s.replace('''        c16Plan: OriginalEraseC16PlanV1, targetGenerationID: UUID) throws -> [Progress.Target] {
        try c16Plan.validate()''','''        c16Plan: OriginalEraseC16PlanV1, targetGenerationID: UUID,
        originalPairAccounting: EraseSchema2ColdOriginalPairAccountingRosterV1? = nil) throws -> [Progress.Target] {
        try c16Plan.validate()''',1)
s=s.replace('''        _ = try requireOriginalRootCensus(originalP)
        let operationsKey''','''        _ = try requireOriginalRootCensus(originalP, originalPairAccounting: originalPairAccounting)
        let operationsKey''',1)
# Complete scan merges private actual pair observations, never an external alias map.
s=s.replace('''        var values: [Progress.Projection] = [], nodes: [String: Node] = [:]
''','''        var values: [Progress.Projection] = [], nodes: [String: Node] = [:]
        var currentTypedPairs: [EraseAbortCheckedSnapshotIOV1.Schema2ColdAuthenticatedPairObservationV1] = []
''',1)
needle='''            for node in observed.nodes {'''
replace='''            if isOperations { currentTypedPairs.append(contentsOf: observed.typedPairs) }
            for node in observed.nodes {'''
assert needle in s;s=s.replace(needle,replace,1)
s=s.replace('''try Self.requireCurrentProjectionBounds(originalP: originalP, projection: projection)''','''try Self.requireCurrentProjectionBounds(originalP: originalP, projection: projection, currentTypedPairs: currentTypedPairs)''',1)
p.write_text(s)

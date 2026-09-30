from pathlib import Path
base=Path('.codex-temp/cold-physical-continuation-successor-v4/candidate/FieldEvidenceApp/Infrastructure/Persistence')
p=base/'StoreGenerationFactory.swift';s=p.read_text()
needle='''    /// Whole current tree data for the cold fixed C16 projection. Ordinary
'''
add='''    /// Actual complete scoped observations, privately formed only after both
    /// namespace members and real policy consumers passed. Data, never a lease,
    /// historical-final claim, birth, source permission or effect capability.
    struct Schema2ColdAuthenticatedPairObservationV1: Equatable {
        let treeRelativeMemberPaths: [String]
        let operationsRelativeMemberPaths: [String]
        let fullFacts: [String]
        let observedFacts: [String]
        let sha256: String
        let byteCount: Int64
        let device: UInt64
        let inode: UInt64
        let operationID: UUID
        let originKind: String
        let originBinding: String
        let policyObservations: [TemporalPolicyObservationV1]
        let genericMetadata: OriginalEraseOwnedScratchMetadataV1?
        fileprivate init(treeRelativeMemberPaths: [String], operationsRelativeMemberPaths: [String],
            fullFacts: [String], observedFacts: [String], sha256: String, byteCount: Int64,
            device: UInt64, inode: UInt64, operationID: UUID, originKind: String,
            originBinding: String, policyObservations: [TemporalPolicyObservationV1],
            genericMetadata: OriginalEraseOwnedScratchMetadataV1?) {
            self.treeRelativeMemberPaths = treeRelativeMemberPaths
            self.operationsRelativeMemberPaths = operationsRelativeMemberPaths
            self.fullFacts = fullFacts; self.observedFacts = observedFacts; self.sha256 = sha256
            self.byteCount = byteCount; self.device = device; self.inode = inode
            self.operationID = operationID; self.originKind = originKind; self.originBinding = originBinding
            self.policyObservations = policyObservations; self.genericMetadata = genericMetadata
        }
    }
    struct Schema2ColdReadWorkV1: Equatable {
        let physicalRegularBytes: UInt64
        let pathRegularBytes: UInt64
        let scannerPayloadReadBytes: UInt64
        let scannerPayloadReadCalls: UInt64
        let policyPairPayloadReadBytes: UInt64
        let policyPairPayloadPasses: UInt64
        let policyPairInvocations: UInt64
        let payloadWorkReservationBytes: UInt64
        let payloadWorkLimitBytes: UInt64
        // Scope issuer/control/metadata IO is deliberately a separate domain.
        fileprivate init(physicalRegularBytes: UInt64, pathRegularBytes: UInt64,
            scannerPayloadReadBytes: UInt64, scannerPayloadReadCalls: UInt64,
            policyPairPayloadReadBytes: UInt64, policyPairPayloadPasses: UInt64,
            policyPairInvocations: UInt64, payloadWorkReservationBytes: UInt64,
            payloadWorkLimitBytes: UInt64) {
            self.physicalRegularBytes = physicalRegularBytes; self.pathRegularBytes = pathRegularBytes
            self.scannerPayloadReadBytes = scannerPayloadReadBytes; self.scannerPayloadReadCalls = scannerPayloadReadCalls
            self.policyPairPayloadReadBytes = policyPairPayloadReadBytes; self.policyPairPayloadPasses = policyPairPayloadPasses
            self.policyPairInvocations = policyPairInvocations; self.payloadWorkReservationBytes = payloadWorkReservationBytes
            self.payloadWorkLimitBytes = payloadWorkLimitBytes
        }
    }

'''
assert needle in s;s=s.replace(needle,add+needle,1)
s=s.replace('''        let rootFact: String
        let digest: String
        let nodes: [Node]
    }

    @MainActor
    func schema2ColdCurrentC16Tree''','''        let rootFact: String
        let digest: String
        let nodes: [Node]
        let typedPairs: [Schema2ColdAuthenticatedPairObservationV1]
        let work: Schema2ColdReadWorkV1?
        fileprivate init(rootFact: String, digest: String, nodes: [Node],
            typedPairs: [Schema2ColdAuthenticatedPairObservationV1] = [], work: Schema2ColdReadWorkV1? = nil) {
            self.rootFact = rootFact; self.digest = digest; self.nodes = nodes
            self.typedPairs = typedPairs; self.work = work
        }
    }

    @MainActor
    func schema2ColdCurrentC16Tree''',1)
s=s.replace('''            })
    }

    /// Complete data image''','''            }, typedPairs: value.typedPairs, work: value.work)
    }

    /// Complete data image''',1)
start=s.index('''    func schema2ColdCurrentOwnedTree(''');end=s.index('''    func postRetiredTree(''',start);block=s[start:end]
block=block.replace('''        var count = 0, totalBytes: Int64 = 0
''','''        var count = 0, totalBytes: Int64 = 0
        let physicalLimit: UInt64 = 1_073_741_824
        let multipliedLimit = physicalLimit.multipliedReportingOverflow(by: 18)
        guard !multipliedLimit.overflow else { throw StoreGenerationFailure.dataPointerInvalid }
        let workLimit = multipliedLimit.partialValue
        var pathBytes: UInt64 = 0, ownReadBytes: UInt64 = 0, ownReadCalls: UInt64 = 0
        var pairReadBytes: UInt64 = 0, pairPasses: UInt64 = 0, pairCalls: UInt64 = 0, workReserved: UInt64 = 0
        struct PairCandidate: Equatable {
            let paths: [String], operationsPaths: [String], facts: [String], nineFacts: [String]
            let sha: String, bytes: Int64, device: UInt64, inode: UInt64, operationID: UUID
            let originKind: String, originBinding: String
            let policies: [TemporalPolicyObservationV1]
            let genericMetadata: OriginalEraseOwnedScratchMetadataV1?
        }
        var pairs: [String: PairCandidate] = [:]
        var pairMemberPaths = Set<String>()
        func add(_ counter: inout UInt64, _ value: UInt64, limit: UInt64) throws {
            let result = counter.addingReportingOverflow(value)
            guard !result.overflow, result.partialValue <= limit else { throw StoreGenerationFailure.dataPointerInvalid }
            counter = result.partialValue
        }
        func reservePairWork(_ bytes: Int64, _ kind: EraseC16TemporalPairReadWorkKindV1) throws -> (UInt64, UInt64) {
            let work = try EraseC16TemporalPairReadWorkV1.maximumPayloadReadBytes(expectedByteCount: bytes, kind: kind)
            let passes = EraseC16TemporalPairReadWorkV1.payloadBytePassesPerInvocation(kind: kind)
            try add(&workReserved, work, limit: workLimit)
            try add(&pairCalls, 1, limit: 100_000)
            return (work, passes)
        }
        func completedPairWork(_ reserved: (UInt64, UInt64)) throws {
            try add(&pairReadBytes, reserved.0, limit: workLimit)
            try add(&pairPasses, reserved.1, limit: 800_000)
        }
''',1)
# Scoped read is finite exact pread chunks, never an unbounded EINTR/short-read loop.
a=block.index('''        func scopedDigest(''');b=block.index('''        func named(''',a)
block=block[:a]+'''        func scopedDigest(_ fd: Int32, _ before: stat) throws -> String {
            guard let size = UInt64(exactly: before.st_size), size <= physicalLimit else { throw StoreGenerationFailure.dataPointerInvalid }
            try add(&workReserved, size, limit: workLimit)
            var digest = SHA256(), offset: UInt64 = 0
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while offset < size {
                try bound()
                let wanted = Int(min(UInt64(buffer.count), size - offset))
                let count = buffer.withUnsafeMutableBytes { Darwin.pread(fd, $0.baseAddress, wanted, off_t(offset)) }
                try add(&ownReadCalls, 1, limit: 132_768)
                try bound()
                guard count == wanted else { throw StoreGenerationFailure.dataPointerInvalid }
                try add(&ownReadBytes, UInt64(count), limit: workLimit)
                offset += UInt64(count)
                buffer.withUnsafeBytes { raw in
                    digest.update(bufferPointer: UnsafeRawBufferPointer(start: raw.baseAddress, count: count))
                }
            }
            try bound()
            var extra: UInt8 = 0
            let end = Darwin.pread(fd, &extra, 1, off_t(size))
            try add(&ownReadCalls, 1, limit: 132_768)
            try bound()
            guard end == 0 else { throw StoreGenerationFailure.dataPointerInvalid }
            return digest.finalize().map { String(format: "%02x", $0) }.joined()
        }
        func observedNine(_ full: String) throws -> String {
            let f = full.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 11 else { throw StoreGenerationFailure.dataPointerInvalid }
            return [f[0],f[1],f[2],f[5],f[6],f[7],f[8],f[9],f[10]].joined(separator: "|")
        }
        func recordPair(urls: [URL], facts: [String], policies: [TemporalPolicyObservationV1],
            sha: String, bytes: Int64, before: stat, operationID: UUID, kind: String, binding: String,
            metadata: OriginalEraseOwnedScratchMetadataV1? = nil) throws {
            guard urls.count == 2, facts.count == 2, urls[0] != urls[1], facts[0] == facts[1],
                  facts.contains(fullFact(before)), before.st_nlink == 2, Int64(before.st_size) == bytes,
                  policies.count == 2, policies[0] == policies[1], policies.allSatisfy({
                      $0.device == UInt64(before.st_dev) && $0.inode == UInt64(before.st_ino) && $0.linkCount == 2
                        && !$0.isDirectory && $0.backupExcluded == true
                        && ($0.state == .strictComplete || $0.state == .pendingSimulatorRequest)
                  }) else { throw StoreGenerationFailure.dataPointerInvalid }
            let prefix = rootURL.standardizedFileURL.path + "/"
            var members: [(String, String)] = []
            for (index, url) in urls.enumerated() {
                guard url.isFileURL, url.standardizedFileURL == url, url.path.hasPrefix(prefix) else {
                    throw StoreGenerationFailure.dataPointerInvalid
                }
                let relative = String(url.path.dropFirst(prefix.count))
                let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
                guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.utf8.contains(0) }),
                      parts.count <= 65 else { throw StoreGenerationFailure.dataPointerInvalid }
                members.append((relative, facts[index]))
            }
            members.sort { $0.0.utf8.lexicographicallyPrecedes($1.0.utf8) }
            let paths = members.map { $0.0 }
            guard let rolePrefix = operationsRelativePrefix else { throw StoreGenerationFailure.dataPointerInvalid }
            let operationsPaths = paths.map { rolePrefix.isEmpty ? $0 : rolePrefix + "/" + $0 }
            let orderedFacts = members.map { $0.1 }
            let candidate = PairCandidate(paths: paths, operationsPaths: operationsPaths, facts: orderedFacts,
                nineFacts: try orderedFacts.map(observedNine), sha: sha, bytes: bytes,
                device: UInt64(before.st_dev), inode: UInt64(before.st_ino), operationID: operationID,
                originKind: kind, originBinding: binding, policies: policies, genericMetadata: metadata)
            let key = String(before.st_dev) + "|" + String(before.st_ino)
            if let prior = pairs[key] { guard prior == candidate else { throw StoreGenerationFailure.dataPointerInvalid } }
            else {
                guard paths.allSatisfy({ !pairMemberPaths.contains($0) }), bytes >= 0,
                      totalBytes <= Int64(physicalLimit) - bytes else { throw StoreGenerationFailure.dataPointerInvalid }
                // Positive scoped PFP proof already checked both names; the
                // complete return below additionally requires both walker nodes.
                totalBytes += bytes; pairs[key] = candidate; pairMemberPaths.formUnion(paths)
            }
        }
'''+block[b:]
block=block.replace('''                    guard before.st_size >= 0, before.st_size <= 1_073_741_824,
                          totalBytes <= 1_073_741_824 - Int64(before.st_size) else {''','''                    guard before.st_size >= 0, before.st_size <= 1_073_741_824 else {''',1)
block=block.replace('''                    totalBytes += Int64(before.st_size) // Each recorded alias consumes its own tree allowance.
''','''                    try add(&pathBytes, UInt64(before.st_size), limit: 2 * physicalLimit)
''',1)
# Record every successful exact typed pair; work counts the actual existing API.
repls=[
('''                            let values = try ProtectedFilePolicyV1.observeEraseC16FirstCaptureTemporalPairWithCheckedClose(''', '''                            let reserved = try reservePairWork(pair.expectedByteCount, .firstCaptureOpaquePair)
                            let values = try ProtectedFilePolicyV1.observeEraseC16FirstCaptureTemporalPairWithCheckedClose('''),
('''                        let values = try ProtectedFilePolicyV1.observeEraseC16CurrentTemporalPairWithCheckedClose(''', '''                        let reserved = try reservePairWork(Int64(pair.bytes.count), .currentCanonicalPair)
                        let values = try ProtectedFilePolicyV1.observeEraseC16CurrentTemporalPairWithCheckedClose('''),
('''                        let values = try ProtectedFilePolicyV1.observeEraseC16FirstPTemporalPairWithCheckedClose(''', '''                        let reserved = try reservePairWork(pair.expectedByteCount, .firstPImmutablePair)
                        let values = try ProtectedFilePolicyV1.observeEraseC16FirstPTemporalPairWithCheckedClose('''),
('''                        let values = try ProtectedFilePolicyV1.observeEraseC16InitialTemporalPairWithCheckedClose(''', '''                        let reserved = try reservePairWork(pair.expectedByteCount, .initialOpaquePair)
                        let values = try ProtectedFilePolicyV1.observeEraseC16InitialTemporalPairWithCheckedClose(''')]
for old,new in repls:assert old in block;block=block.replace(old,new,1)
# Locate each origin's observedPolicy assignment, insert accounting after all existing guards.
origins=[('observeEraseC16FirstCaptureTemporalPairWithCheckedClose', '''                            try completedPairWork(reserved)
                            try recordPair(urls: [pair.finalURL, pair.partialURL], facts: [pair.finalFullFact, pair.partialFullFact],
                                policies: values, sha: sha, bytes: pair.expectedByteCount, before: before,
                                operationID: firstCaptureScope.operationID, kind: "firstCaptureCanonical", binding: firstCaptureScope.captureToken)
'''),
('observeEraseC16CurrentTemporalPairWithCheckedClose', '''                        try completedPairWork(reserved)
                        try recordPair(urls: [pair.finalURL, pair.partialURL], facts: [pair.finalFullFact, pair.partialFullFact],
                            policies: values, sha: sha, bytes: Int64(pair.bytes.count), before: before,
                            operationID: scope.operationID, kind: "currentCanonical", binding: scope.planSHA256 + "|" + String(scope.ordinal))
'''),
('observeEraseC16FirstPTemporalPairWithCheckedClose', '''                        try completedPairWork(reserved)
                        try recordPair(urls: [pair.finalURL, pair.partialURL], facts: [pair.finalFullFact, pair.partialFullFact],
                            policies: values, sha: sha, bytes: pair.expectedByteCount, before: before,
                            operationID: scope.operationID, kind: "immutableFirstP", binding: firstP.planSHA256 + "|" + String(firstP.currentOrdinal))
'''),
('observeEraseC16InitialTemporalPairWithCheckedClose', '''                        try completedPairWork(reserved)
                        try recordPair(urls: [pair.finalURL, pair.partialURL], facts: [pair.finalFullFact, pair.partialFullFact],
                            policies: values, sha: sha, bytes: pair.expectedByteCount, before: before,
                            operationID: initialScope.operationID, kind: "immutableInitial", binding: initialScope.originToken)
''')]
for marker,code in origins:
 a=block.index(marker);b=block.index('observedPolicy = values[0]',a);block=block[:b]+code+block[b:]
# New generic DATA role uses truthful ordered aliases, no guessed final URL.
needle='''                            observedPolicy = values[0]
                        }
                    } else { switch role {'''
# Accounting insert indentation may include varying spaces but target exact assignment still retains28spaces.
if needle not in block:
 needle='''observedPolicy = values[0]
                        }
                    } else { switch role {'''
new='''observedPolicy = values[0]
                        case .observedOwnedGenericAliases(let pair):
                            guard let firstCaptureScope, scope == nil, initialScope == nil, before.st_nlink == 2,
                                  pair.members.count == 2, pair.members.contains(where: { $0.url == url }),
                                  pair.originBinding == firstCaptureScope.captureToken,
                                  pair.operationID == firstCaptureScope.operationID,
                                  pair.sha256 == sha, pair.byteCount == Int64(before.st_size),
                                  pair.device == UInt64(before.st_dev), pair.inode == UInt64(before.st_ino) else {
                                throw StoreGenerationFailure.dataPointerInvalid
                            }
                            let reserved = try reservePairWork(pair.byteCount, .observedOwnedGenericAliases)
                            let values = try ProtectedFilePolicyV1.observeEraseObservedOwnedGenericAliasTemporalPairWithCheckedClose(
                                aliasURLs: pair.members.map(\\.url), scope: firstCaptureScope, retainUncertainDescriptor: retain)
                            try completedPairWork(reserved)
                            try recordPair(urls: pair.members.map(\\.url), facts: pair.members.map(\\.fullFact),
                                policies: values, sha: sha, bytes: pair.byteCount, before: before,
                                operationID: pair.operationID, kind: "firstCaptureObservedGeneric", binding: pair.originBinding,
                                metadata: pair.metadata)
                            observedPolicy = values[0]
                        }
                    } else { switch role {'''
assert needle in block;block=block.replace(needle,new,1)
needle='''                    try bound()
                    nodes.append(.init(path: path, fullFact: fullFact(before), names: nil,'''
replace='''                    if !pairMemberPaths.contains(path) {
                        guard before.st_nlink == 1, totalBytes <= Int64(physicalLimit) - Int64(before.st_size) else {
                            throw StoreGenerationFailure.dataPointerInvalid
                        }
                        totalBytes += Int64(before.st_size)
                    }
                    try bound()
                    nodes.append(.init(path: path, fullFact: fullFact(before), names: nil,'''
assert needle in block;block=block.replace(needle,replace,1)
needle='''            return .init(rootFact: rootFact,
                digest: SHA256.hash(data: Data(tokens.joined(separator: "\\n").utf8)).map { String(format: "%02x", $0) }.joined(),
                nodes: nodes.sorted { $0.path < $1.path })'''
replace='''            let byPath = Dictionary(uniqueKeysWithValues: nodes.map { ($0.path, $0) })
            var provedPairs: [Schema2ColdAuthenticatedPairObservationV1] = []
            for pair in pairs.values.sorted(by: { $0.operationsPaths[0].utf8.lexicographicallyPrecedes($1.operationsPaths[0].utf8) }) {
                for index in 0..<2 {
                    guard let node = byPath[pair.paths[index]], node.names == nil,
                          node.fullFact == pair.facts[index], node.sha256 == pair.sha,
                          node.policy == pair.policies[index] else { throw StoreGenerationFailure.dataPointerInvalid }
                }
                provedPairs.append(.init(treeRelativeMemberPaths: pair.paths,
                    operationsRelativeMemberPaths: pair.operationsPaths, fullFacts: pair.facts, observedFacts: pair.nineFacts,
                    sha256: pair.sha, byteCount: pair.bytes, device: pair.device, inode: pair.inode,
                    operationID: pair.operationID, originKind: pair.originKind, originBinding: pair.originBinding,
                    policyObservations: pair.policies, genericMetadata: pair.genericMetadata))
            }
            let actual = ownReadBytes.addingReportingOverflow(pairReadBytes)
            guard !actual.overflow, actual.partialValue == workReserved, actual.partialValue <= workLimit else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            try bound()
            let work = Schema2ColdReadWorkV1(physicalRegularBytes: UInt64(totalBytes), pathRegularBytes: pathBytes,
                scannerPayloadReadBytes: ownReadBytes, scannerPayloadReadCalls: ownReadCalls,
                policyPairPayloadReadBytes: pairReadBytes, policyPairPayloadPasses: pairPasses,
                policyPairInvocations: pairCalls, payloadWorkReservationBytes: workReserved, payloadWorkLimitBytes: workLimit)
            return .init(rootFact: rootFact,
                digest: SHA256.hash(data: Data(tokens.joined(separator: "\\n").utf8)).map { String(format: "%02x", $0) }.joined(),
                nodes: nodes.sorted { $0.path < $1.path }, typedPairs: provedPairs, work: work)'''
assert needle in block;block=block.replace(needle,replace,1)
s=s[:start]+block+s[end:]
# Cold-only cursor bound; default ordinary names() untouched.
start=s.index('''    func schema2ColdNames(''');end=s.index('''    /// Actual complete scoped observations''',start);block=s[start:end]
block=block.replace('''            var values: [String] = []
            while true {''','''            var values: [String] = []
            var entryReads = 0
            while true {
                guard entryReads < 100_003 else { throw StoreGenerationFailure.dataPointerInvalid }
                entryReads += 1''',1)
block=block.replace('''if name != "." && name != ".." { values.append(name) }''','''if name != "." && name != ".." {
                    guard values.count < 100_000 else { throw StoreGenerationFailure.dataPointerInvalid }
                    values.append(name)
                }''',1)
s=s[:start]+block+s[end:];p.write_text(s)

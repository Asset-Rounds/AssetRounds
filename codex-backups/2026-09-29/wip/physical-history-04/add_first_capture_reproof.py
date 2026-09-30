from pathlib import Path
base=Path('.codex-temp/cold-physical-continuation-successor-v3/candidate/FieldEvidenceApp/Infrastructure/Persistence')
p=base/'EraseSchema2ColdAuxiliaryFirstObservationV1.swift';s=p.read_text()
s=s.replace('''    private var firstCaptureC16Scope: OriginalEraseC16FirstCaptureObservationScopeV1?
''','''    private var firstCaptureC16Scope: OriginalEraseC16FirstCaptureObservationScopeV1?
    private var firstCaptureOperationID: UUID?
    private var firstCaptureSupportURL: URL?
''',1)
old='''        guard !attempted, initialC16Scope == nil else { throw EraseAllServiceError.invalidAuthority }
        try scope.requireCurrentBinding()
        firstCaptureC16Scope = scope; initialSupportURL = applicationSupportURL.standardizedFileURL
        defer { firstCaptureC16Scope = nil; initialSupportURL = nil }
        let value = try captureFirst(support: support, caches: caches, temporary: temporary,
            applicationSupportURL: applicationSupportURL)
        try scope.requireCurrentBinding(); return value
    }

    /// Returns the first complete data image.'''
new='''        guard !attempted else { throw EraseAllServiceError.invalidAuthority }
        return try withFirstCaptureScope(scope: scope, applicationSupportURL: applicationSupportURL) {
            try captureFirst(support: support, caches: caches, temporary: temporary,
                applicationSupportURL: applicationSupportURL)
        }
    }

    /// Re-enter only a genuine fresh first-owner/G callback. The synchronous
    /// body may reprove the retained first image; this helper never captures,
    /// refreshes or changes it and never holds a G scope across an await.
    func withFirstCaptureScope<Value>(scope: OriginalEraseC16FirstCaptureObservationScopeV1,
        applicationSupportURL: URL, _ body: @MainActor () throws -> Value) throws -> Value {
        guard firstCaptureC16Scope == nil, initialC16Scope == nil, applicationSupportURL.isFileURL,
              firstCaptureOperationID == nil || firstCaptureOperationID == scope.operationID,
              firstCaptureSupportURL == nil || firstCaptureSupportURL == applicationSupportURL.standardizedFileURL else {
            throw EraseAllServiceError.invalidAuthority
        }
        try scope.requireCurrentBinding()
        if firstCaptureOperationID == nil {
            firstCaptureOperationID = scope.operationID
            firstCaptureSupportURL = applicationSupportURL.standardizedFileURL
        }
        firstCaptureC16Scope = scope; initialSupportURL = applicationSupportURL.standardizedFileURL
        defer { firstCaptureC16Scope = nil; initialSupportURL = nil }
        let value = try body()
        try scope.requireCurrentBinding(); try io.requireSettled()
        return value
    }

    /// Returns the first complete data image.'''
assert old in s;s=s.replace(old,new,1)
s=s.replace('''        guard !attempted else { throw EraseAllServiceError.invalidAuthority }
        try scope.requireCurrentBinding()
        initialC16Scope''','''        guard !attempted, firstCaptureC16Scope == nil else { throw EraseAllServiceError.invalidAuthority }
        try scope.requireCurrentBinding()
        initialC16Scope''',1)
# All operations child directories use the exact complete scope, with an explicit role origin.
s=s.replace('''try tree(parent: directory, name: name) else''','''try tree(parent: directory, name: name, operationsChild: true) else''',1)
s=s.replace('''    private func tree(parent: Int32, name: String) throws -> Tree {''','''    private func tree(parent: Int32, name: String, operationsChild: Bool = false) throws -> Tree {''',1)
s=s.replace('''           name == "FieldEvidenceOperations" || name == "ScratchDataV1" || name == "ProtectedIngressReceiptsV1" {''','''           name == "FieldEvidenceOperations" || operationsChild {''',1)
# Scoped observation of regular top-level Operations children avoids a strict
# fallback refusing a positively declared same-inode role. No whole bytes.
needle='''            let names = try io.names(in: directory)
            var children: [String: OperationsChild] = [:]'''
replace='''            let names = try io.names(in: directory)
            let scopedTree: EraseAbortCheckedSnapshotIOV1.Schema2ColdCurrentTreeV1?
            if (initialC16Scope != nil || firstCaptureC16Scope != nil), let supportURL = initialSupportURL {
                let initialScope = initialC16Scope, captureScope = firstCaptureC16Scope
                scopedTree = try io.schema2ColdCurrentOwnedTree(parent: parent, name: "FieldEvidenceOperations",
                    rootURL: supportURL.appendingPathComponent("FieldEvidenceOperations", isDirectory: true),
                    expectedUser: held.st_uid, expectedGroup: held.st_gid,
                    initialScope: initialScope, firstCaptureScope: captureScope, operationsRelativePrefix: "",
                    requireBinding: { try initialScope?.requireCurrentBinding(); try captureScope?.requireCurrentBinding() },
                    poison: { initialScope?.poisonOnUncertainObservation(); captureScope?.poisonOnUncertainObservation() })
                guard scopedTree?.rootFact == rootFact else { throw EraseAllServiceError.invalidAuthority }
            } else { scopedTree = nil }
            var children: [String: OperationsChild] = [:]'''
assert needle in s;s=s.replace(needle,replace,1)
needle='''                } else if initial.st_mode & S_IFMT == S_IFREG {
                    guard initial.st_nlink == 1'''
replace='''                } else if initial.st_mode & S_IFMT == S_IFREG {
                    if let scopedTree {
                        guard let node = scopedTree.nodes.first(where: { $0.path == name }),
                              node.fullFact == Self.fullFact(initial), node.names == nil,
                              node.policy != nil, let sha = node.sha256 else { throw EraseAllServiceError.invalidAuthority }
                        children[name] = .regular(fact: node.fullFact, digest: sha)
                        continue
                    }
                    guard initial.st_nlink == 1'''
assert needle in s;s=s.replace(needle,replace,1)
p.write_text(s)
p=base/'StoreGenerationFactory.swift';s=p.read_text();start=s.index('''    func schema2ColdCurrentOwnedTree(''');end=s.index('''    func postRetiredTree(''',start)
block=s[start:end].replace('before.st_mode & 0o777 ==','before.st_mode & 0o7777 ==');s=s[:start]+block+s[end:];p.write_text(s)

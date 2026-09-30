from pathlib import Path
base=Path('.codex-temp/cold-physical-continuation-successor-v3/candidate/FieldEvidenceApp/Infrastructure/Persistence')
p=base/'StoreGenerationFactory.swift';s=p.read_text()
s=s.replace('''            let publicationRole: OriginalEraseC16CurrentPathRoleV1
        }
''','''            let publicationRole: OriginalEraseC16CurrentPathRoleV1
            let firstCaptureRole: OriginalEraseC16FirstCapturePathRoleV1?
            init(path: String, fullFact: String, names: [String]?, sha256: String?,
                policy: TemporalPolicyObservationV1?, publicationRole: OriginalEraseC16CurrentPathRoleV1,
                firstCaptureRole: OriginalEraseC16FirstCapturePathRoleV1? = nil) {
                self.path = path; self.fullFact = fullFact; self.names = names; self.sha256 = sha256
                self.policy = policy; self.publicationRole = publicationRole; self.firstCaptureRole = firstCaptureRole
            }
        }
''',1)
s=s.replace('policy: node.policy, publicationRole: node.publicationRole)','policy: node.policy, publicationRole: node.publicationRole, firstCaptureRole: node.firstCaptureRole)',1)
s=s.replace('''        initialScope: OriginalEraseC16InitialObservationScopeV1? = nil,
        operationsRelativePrefix''','''        initialScope: OriginalEraseC16InitialObservationScopeV1? = nil,
        firstCaptureScope: OriginalEraseC16FirstCaptureObservationScopeV1? = nil,
        operationsRelativePrefix''',1)
s=s.replace('''              scope == nil || initialScope == nil,
              ((scope == nil && initialScope == nil) == (operationsRelativePrefix == nil))''','''              [scope != nil, initialScope != nil, firstCaptureScope != nil].filter({ $0 }).count <= 1,
              ((scope == nil && initialScope == nil && firstCaptureScope == nil) == (operationsRelativePrefix == nil))''',1)
s=s.replace('''func bound() throws { try requireSettled(); try requireBinding(); try scope?.requireCurrentBinding(); try initialScope?.requireCurrentBinding() }
        func retain(_ fd: Int32) { retainUncertainDescriptor(fd); scope?.poisonOnUncertainObservation(); initialScope?.poisonOnUncertainObservation(); poison() }''','''func bound() throws { try requireSettled(); try requireBinding(); try scope?.requireCurrentBinding(); try initialScope?.requireCurrentBinding(); try firstCaptureScope?.requireCurrentBinding() }
        func retain(_ fd: Int32) { retainUncertainDescriptor(fd); scope?.poisonOnUncertainObservation(); initialScope?.poisonOnUncertainObservation(); firstCaptureScope?.poisonOnUncertainObservation(); poison() }''',1)
needle='''                    let observedPolicy: TemporalPolicyObservationV1?
                    switch role {'''
replace='''                    let captureRole: OriginalEraseC16FirstCapturePathRoleV1?
                    if let rolePath, let firstCaptureScope {
                        captureRole = try firstCaptureScope.roleFor(path: rolePath, fullFact: fullFact(before), sha256: sha)
                    } else { captureRole = nil }
                    let observedPolicy: TemporalPolicyObservationV1?
                    if let captureRole {
                        switch captureRole {
                        case .ordinary:
                            guard before.st_nlink == 1 else { throw StoreGenerationFailure.dataPointerInvalid }
                            observedPolicy = try policy(url, before)
                        case .firstCapturePair(let pair):
                            guard let firstCaptureScope, scope == nil, initialScope == nil, before.st_nlink == 2,
                                  url == pair.finalURL || url == pair.partialURL,
                                  pair.captureToken == firstCaptureScope.captureToken,
                                  pair.expectedSHA256 == sha, pair.expectedByteCount == Int64(before.st_size) else {
                                throw StoreGenerationFailure.dataPointerInvalid
                            }
                            let values = try ProtectedFilePolicyV1.observeEraseC16FirstCaptureTemporalPairWithCheckedClose(
                                finalURL: pair.finalURL, partialURL: pair.partialURL, scope: firstCaptureScope,
                                retainUncertainDescriptor: retain)
                            guard values.count == 2, values.allSatisfy({
                                $0.device == UInt64(before.st_dev) && $0.inode == UInt64(before.st_ino) && $0.linkCount == 2
                            }) else { throw StoreGenerationFailure.dataPointerInvalid }
                            observedPolicy = values[0]
                        }
                    } else { switch role {'''
assert needle in s;s=s.replace(needle,replace,1)
s=s.replace('''                        observedPolicy = nil
                    }
                    try bound()
                    nodes.append(.init(path: path, fullFact: fullFact(before), names: nil,
                        sha256: sha, policy: observedPolicy, publicationRole: role))''','''                        observedPolicy = nil
                    } }
                    try bound()
                    nodes.append(.init(path: path, fullFact: fullFact(before), names: nil,
                        sha256: sha, policy: observedPolicy, publicationRole: role, firstCaptureRole: captureRole))''',1)
s=s.replace('''if (try? requireSettled()) == nil { scope?.poisonOnUncertainObservation(); initialScope?.poisonOnUncertainObservation(); poison() }''','''if (try? requireSettled()) == nil { scope?.poisonOnUncertainObservation(); initialScope?.poisonOnUncertainObservation(); firstCaptureScope?.poisonOnUncertainObservation(); poison() }''',1)
p.write_text(s)
p=base/'EraseSchema2ColdAuxiliaryFirstObservationV1.swift';s=p.read_text()
s=s.replace('''    private var initialC16Scope: OriginalEraseC16InitialObservationScopeV1?
''','''    private var initialC16Scope: OriginalEraseC16InitialObservationScopeV1?
    private var firstCaptureC16Scope: OriginalEraseC16FirstCaptureObservationScopeV1?
''',1)
needle='''    /// Returns the first complete data image. It does not reobserve, refresh,
'''
replace='''    /// Distinct data origin before the auxiliary P exists. Migration's
    /// genuine first-capture owner supplies the complete producer-role scope
    /// under its real EX/G/phase; no immutable-P or proposed plan is asserted.
    func captureFirstWithFirstCaptureScope(support: Int32, caches: Int32, temporary: Int32,
        applicationSupportURL: URL, scope: OriginalEraseC16FirstCaptureObservationScopeV1) throws -> Snapshot {
        guard !attempted, initialC16Scope == nil else { throw EraseAllServiceError.invalidAuthority }
        try scope.requireCurrentBinding()
        firstCaptureC16Scope = scope; initialSupportURL = applicationSupportURL.standardizedFileURL
        defer { firstCaptureC16Scope = nil; initialSupportURL = nil }
        let value = try captureFirst(support: support, caches: caches, temporary: temporary,
            applicationSupportURL: applicationSupportURL)
        try scope.requireCurrentBinding(); return value
    }

'''+needle
assert needle in s;s=s.replace(needle,replace,1)
s=s.replace('''        if !notificationControl, let scope = initialC16Scope {
''','''        if !notificationControl, initialC16Scope != nil || firstCaptureC16Scope != nil {
            let initialScope = initialC16Scope, captureScope = firstCaptureC16Scope
            func bound() throws { try initialScope?.requireCurrentBinding(); try captureScope?.requireCurrentBinding() }
            func poison() { initialScope?.poisonOnUncertainObservation(); captureScope?.poisonOnUncertainObservation() }
''',1)
# only protected-control method block; use segmented replacement
start=s.index('''        if !notificationControl, initialC16Scope != nil || firstCaptureC16Scope != nil {''')
end=s.index('''        var nodes: [EraseAbortCheckedSnapshotIOV1.CheckedTreeNode]''',start)
block=s[start:end].replace('initialScope: scope, operationsRelativePrefix: name,\n                requireBinding: { try scope.requireCurrentBinding() },\n                poison: { scope.poisonOnUncertainObservation() })','initialScope: initialScope, firstCaptureScope: captureScope, operationsRelativePrefix: name,\n                requireBinding: bound, poison: poison)')
s=s[:start]+block+s[end:]
needle='''        if let scope = initialC16Scope, let supportURL = initialSupportURL,
           name == "FieldEvidenceOperations" || name == "ScratchDataV1" || name == "ProtectedIngressReceiptsV1" {'''
replace='''        if let supportURL = initialSupportURL,
           (initialC16Scope != nil || firstCaptureC16Scope != nil),
           name == "FieldEvidenceOperations" || name == "ScratchDataV1" || name == "ProtectedIngressReceiptsV1" {
            let initialScope = initialC16Scope, captureScope = firstCaptureC16Scope
            func bound() throws { try initialScope?.requireCurrentBinding(); try captureScope?.requireCurrentBinding() }
            func poison() { initialScope?.poisonOnUncertainObservation(); captureScope?.poisonOnUncertainObservation() }'''
assert needle in s;s=s.replace(needle,replace,1)
s=s.replace('''                initialScope: scope, operationsRelativePrefix: rolePrefix,
                requireBinding: { try scope.requireCurrentBinding() }, poison: { scope.poisonOnUncertainObservation() })''','''                initialScope: initialScope, firstCaptureScope: captureScope, operationsRelativePrefix: rolePrefix,
                requireBinding: bound, poison: poison)''',1)
p.write_text(s)

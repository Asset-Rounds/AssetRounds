from pathlib import Path
p=Path('.codex-temp/cold-physical-continuation-successor-v5/candidate/FieldEvidenceApp/Infrastructure/Persistence/EraseSchema2ColdAuxiliaryFirstObservationV1.swift')
s=p.read_text()
s=s.replace('''    private var firstCaptureC16Scope: OriginalEraseC16FirstCaptureObservationScopeV1?
''','''    private var firstCaptureC16Scope: OriginalEraseC16FirstCaptureObservationScopeV1?
    private var sealedGenericScope: OriginalEraseSealedGenericObservationScopeV1?
''',1)
s=s.replace('''        applicationSupportURL: URL, scope: OriginalEraseC16InitialObservationScopeV1) throws -> Snapshot {
        guard !attempted, firstCaptureC16Scope == nil''','''        applicationSupportURL: URL, scope: OriginalEraseC16InitialObservationScopeV1,
        genericScope: OriginalEraseSealedGenericObservationScopeV1? = nil) throws -> Snapshot {
        guard !attempted, firstCaptureC16Scope == nil, sealedGenericScope == nil''',1)
s=s.replace('''        initialC16Scope = scope; initialSupportURL = applicationSupportURL.standardizedFileURL
        defer { initialC16Scope = nil; initialSupportURL = nil }''','''        try genericScope?.requireCurrentBinding()
        initialC16Scope = scope; sealedGenericScope = genericScope
        initialSupportURL = applicationSupportURL.standardizedFileURL
        defer { initialC16Scope = nil; sealedGenericScope = nil; initialSupportURL = nil }''',1)
s=s.replace('''        try scope.requireCurrentBinding(); return value
    }

    /// Distinct data origin''','''        try scope.requireCurrentBinding(); try genericScope?.requireCurrentBinding(); return value
    }

    /// A separate real sealed source/current-record scope can reprove the
    /// same retained image in one synchronous owner/G callback. No new first
    /// snapshot or future source/publication authority is minted here.
    func withSealedGenericScope<Value>(scope: OriginalEraseSealedGenericObservationScopeV1,
        applicationSupportURL: URL, _ body: @MainActor () throws -> Value) throws -> Value {
        guard firstCaptureC16Scope == nil, initialC16Scope == nil, sealedGenericScope == nil,
              applicationSupportURL.isFileURL else { throw EraseAllServiceError.invalidAuthority }
        try scope.requireCurrentBinding()
        sealedGenericScope = scope; initialSupportURL = applicationSupportURL.standardizedFileURL
        defer { sealedGenericScope = nil; initialSupportURL = nil }
        let result = try body()
        try scope.requireCurrentBinding(); try io.requireSettled(); return result
    }

    func captureFirstWithSealedGenericScope(support: Int32, caches: Int32, temporary: Int32,
        applicationSupportURL: URL, scope: OriginalEraseSealedGenericObservationScopeV1) throws -> Snapshot {
        guard !attempted else { throw EraseAllServiceError.invalidAuthority }
        return try withSealedGenericScope(scope: scope, applicationSupportURL: applicationSupportURL) {
            try captureFirst(support: support, caches: caches, temporary: temporary,
                applicationSupportURL: applicationSupportURL)
        }
    }

    /// Distinct data origin''',1)
s=s.replace('''guard firstCaptureC16Scope == nil, initialC16Scope == nil, applicationSupportURL.isFileURL,''','''guard firstCaptureC16Scope == nil, initialC16Scope == nil, sealedGenericScope == nil, applicationSupportURL.isFileURL,''',1)
# Existing lexical scoped Observation paths only; ordinary paths stay exact.
a=s.index('    private var initialC16Scope');b=s.index('/// Complete auxiliary one-effect',a) if '/// Complete auxiliary one-effect' in s[a:] else s.index('@MainActor\nfinal class EraseSchema2ColdPhysicalCleanupOwnerV1',a)
c=s[a:b]
c=c.replace('(initialC16Scope != nil || firstCaptureC16Scope != nil)','(initialC16Scope != nil || firstCaptureC16Scope != nil || sealedGenericScope != nil)')
c=c.replace('initialC16Scope != nil || firstCaptureC16Scope != nil {','initialC16Scope != nil || firstCaptureC16Scope != nil || sealedGenericScope != nil {')
c=c.replace('let initialScope = initialC16Scope, captureScope = firstCaptureC16Scope','let initialScope = initialC16Scope, captureScope = firstCaptureC16Scope, genericScope = sealedGenericScope')
c=c.replace('initialScope: initialScope, firstCaptureScope: captureScope, operationsRelativePrefix:','initialScope: initialScope, firstCaptureScope: captureScope, genericScope: genericScope, operationsRelativePrefix:')
c=c.replace('try captureScope?.requireCurrentBinding()','try captureScope?.requireCurrentBinding(); try genericScope?.requireCurrentBinding()')
c=c.replace('captureScope?.poisonOnUncertainObservation()','captureScope?.poisonOnUncertainObservation(); genericScope?.poisonOnUncertainObservation()')
s=s[:a]+c+s[b:]
# Actual whole owner scan and public observation APIs receive genuine lexical scope.
a=s.index('final class EraseSchema2ColdPhysicalCleanupOwnerV1');c=s[a:]
c=c.replace('''progress: Progress?, initialScope: OriginalEraseC16InitialObservationScopeV1? = nil) throws -> Image''','''progress: Progress?, initialScope: OriginalEraseC16InitialObservationScopeV1? = nil,
        genericScope: OriginalEraseSealedGenericObservationScopeV1? = nil) throws -> Image''',1)
c=c.replace('''            try c16Scope?.requireCurrentBinding()
''','''            try c16Scope?.requireCurrentBinding(); try genericScope?.requireCurrentBinding()
''')
c=c.replace('''c16Scope?.poisonOnUncertainObservation() }''','''c16Scope?.poisonOnUncertainObservation(); genericScope?.poisonOnUncertainObservation() }''')
c=c.replace('''                initialScope: isOperations ? initialScope : nil,
                operationsRelativePrefix: isOperations && (c16Scope != nil || initialScope != nil) ? "" : nil,''','''                initialScope: isOperations ? initialScope : nil,
                genericScope: isOperations ? genericScope : nil,
                operationsRelativePrefix: isOperations && (c16Scope != nil || initialScope != nil || genericScope != nil) ? "" : nil,''')
c=c.replace('''        initialScope: OriginalEraseC16InitialObservationScopeV1?,
        permit: EraseSchema2ColdPhysicalPermitV1)''','''        initialScope: OriginalEraseC16InitialObservationScopeV1?,
        genericScope: OriginalEraseSealedGenericObservationScopeV1? = nil,
        permit: EraseSchema2ColdPhysicalPermitV1)''',1)
c=c.replace('''progress: nil, initialScope: initialScope)''','''progress: nil, initialScope: initialScope, genericScope: genericScope)''')
c=c.replace('''        permit: EraseSchema2ColdPhysicalPermitV1, progress: Progress) throws -> [Progress.Projection]''','''        permit: EraseSchema2ColdPhysicalPermitV1, progress: Progress,
        genericScope: OriginalEraseSealedGenericObservationScopeV1? = nil) throws -> [Progress.Projection]''',1)
c=c.replace('''        progress: Progress) throws -> [Progress.Projection] {
        let one = try scan''','''        progress: Progress,
        genericScope: OriginalEraseSealedGenericObservationScopeV1? = nil) throws -> [Progress.Projection] {
        let one = try scan''',1)
# Public observation scans use same lexical scope; executor provider introduced separately.
start=c.index('    func observeComplete(');end=c.index('    private func withTargetParent',start)
d=c[start:end].replace('permit: permit, progress: progress)','permit: permit, progress: progress, genericScope: genericScope)')
c=c[:start]+d+c[end:]
s=s[:a]+c;p.write_text(s)

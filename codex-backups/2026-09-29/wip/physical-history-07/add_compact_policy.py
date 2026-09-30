from pathlib import Path
p=Path('.codex-temp/cold-physical-continuation-successor-v6');f=p/'candidate/FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift';s=f.read_text()
old='''        genericScope: OriginalEraseSealedGenericObservationScopeV1? = nil,
        operationsRelativePrefix: String? = nil,
        requireBinding: @MainActor () throws -> Void,'''
new='''        genericScope: OriginalEraseSealedGenericObservationScopeV1? = nil,
        compactTargetReadPermit: EraseSchema2CompactTargetReadPermitV4? = nil,
        operationsRelativePrefix: String? = nil,
        requireBinding: @MainActor () throws -> Void,'''
assert s.count(old)==1;s=s.replace(old,new,1)
old='''        try requireSettled(); try requireBinding()
        guard rootURL.isFileURL, rootURL.lastPathComponent == name,'''
new='''        compactTargetReadPermit?.retainObservationAttempt(io: self)
        try requireSettled(); try requireBinding()
        try compactTargetReadPermit?.requireCurrentBinding()
        let compactTargetID = try compactTargetReadPermit?.requireExpectedTargetGenerationID()
        guard compactTargetReadPermit == nil || (scope == nil && initialScope == nil
            && firstCaptureScope == nil && genericScope == nil && operationsRelativePrefix == nil),
              compactTargetID == nil || name == "FieldEvidenceData"
                || name == compactTargetID?.uuidString.lowercased(),
              rootURL.isFileURL, rootURL.lastPathComponent == name,'''
assert s.count(old)==1;s=s.replace(old,new,1)
old='''func bound() throws { try requireSettled(); try requireBinding(); try scope?.requireCurrentBinding(); try initialScope?.requireCurrentBinding(); try firstCaptureScope?.requireCurrentBinding(); try genericScope?.requireCurrentBinding() }
        func retain(_ fd: Int32) { retainUncertainDescriptor(fd); scope?.poisonOnUncertainObservation(); initialScope?.poisonOnUncertainObservation(); firstCaptureScope?.poisonOnUncertainObservation(); genericScope?.poisonOnUncertainObservation(); poison() }'''
new='''func bound() throws { try requireSettled(); try requireBinding(); try scope?.requireCurrentBinding(); try initialScope?.requireCurrentBinding(); try firstCaptureScope?.requireCurrentBinding(); try genericScope?.requireCurrentBinding(); try compactTargetReadPermit?.requireCurrentBinding() }
        func retain(_ fd: Int32) { retainUncertainDescriptor(fd); scope?.poisonOnUncertainObservation(); initialScope?.poisonOnUncertainObservation(); firstCaptureScope?.poisonOnUncertainObservation(); genericScope?.poisonOnUncertainObservation(); compactTargetReadPermit?.poisonOnUncertainObservation(); poison() }'''
assert s.count(old)==1;s=s.replace(old,new,1)
old='''        func policy(_ url: URL, _ f: stat) throws -> TemporalPolicyObservationV1 {
            try bound()
            let directory = f.st_mode & S_IFMT == S_IFDIR
            let value = try ProtectedFilePolicyV1.observeTemporalPolicyWithCheckedClose(
                directory ? .stagingDirectory : .temporaryFile, at: url,
                retainUncertainDescriptor: retain)
            try bound()
            guard value.device == UInt64(f.st_dev), value.inode == UInt64(f.st_ino),
                  value.mode == UInt16(f.st_mode), value.linkCount == UInt64(f.st_nlink),
                  value.isDirectory == directory, value.backupExcluded == true,'''
new='''        func compactKind(_ path: String, directory: Bool, target: UUID) throws -> OwnedFileKindV1 {
            if path.isEmpty { guard directory else { throw StoreGenerationFailure.dataPointerInvalid }; return .durableDirectory }
            let targetName = target.uuidString.lowercased()
            if name == targetName {
                return try GenerationOwnedPathV1.classify(path,
                    nodeType: directory ? .directory : .regularFile).kind
            }
            guard name == "FieldEvidenceData" else { throw StoreGenerationFailure.dataPointerInvalid }
            let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            if parts == ["generations"] || parts == ["generations", targetName] {
                guard directory else { throw StoreGenerationFailure.dataPointerInvalid }; return .durableDirectory
            }
            if parts.count > 2, parts[0] == "generations", parts[1] == targetName {
                return try GenerationOwnedPathV1.classify(parts.dropFirst(2).joined(separator: "/"),
                    nodeType: directory ? .directory : .regularFile).kind
            }
            guard !directory, parts.count == 1 else { throw StoreGenerationFailure.dataPointerInvalid }
            switch path {
            case "current.json", "retired.json": return .generationPointer
            case "erase-current-manifest.json": return .journal
            default: throw StoreGenerationFailure.dataPointerInvalid
            }
        }
        func policy(_ url: URL, _ f: stat, path: String) throws -> TemporalPolicyObservationV1 {
            try bound()
            let directory = f.st_mode & S_IFMT == S_IFDIR
            let kind: OwnedFileKindV1
            if let compactTargetID { kind = try compactKind(path, directory: directory, target: compactTargetID) }
            else { kind = directory ? .stagingDirectory : .temporaryFile }
            let value = try ProtectedFilePolicyV1.observeTemporalPolicyWithCheckedClose(
                kind, at: url, retainUncertainDescriptor: retain)
            try bound()
            guard value.device == UInt64(f.st_dev), value.inode == UInt64(f.st_ino),
                  value.mode == UInt16(f.st_mode), value.linkCount == UInt64(f.st_nlink),
                  value.isDirectory == directory,
                  value.backupExcluded == ProtectedFilePolicyV1.isExcludedFromBackup(for: kind),'''
assert s.count(old)==1;s=s.replace(old,new,1)
start=s.index('    func schema2ColdCurrentOwnedTree(');end=s.index('    func postRetiredTree(',start)
part=s[start:end];assert part.count('try policy(url, before)')==4
part=part.replace('try policy(url, before)','try policy(url, before, path: path)')
part=part.replace('genericScope?.poisonOnUncertainObservation(); poison() }\n            throw error','genericScope?.poisonOnUncertainObservation(); compactTargetReadPermit?.poisonOnUncertainObservation(); poison() }\n            throw error',1)
s=s[:start]+part+s[end:];f.write_text(s)
(p/'WORKING_HANDOFF.md').write_text('Unique V6 successor over immutable V5d84d. Bounded compact read-only physical inspector in progress, exact permit86825/subject600f source contracts. No SQL/Journal loan issuer exists yet; no semantic graph or ready claim. Only owned ignored candidates; no tracked/Git/build/native effects.\n')

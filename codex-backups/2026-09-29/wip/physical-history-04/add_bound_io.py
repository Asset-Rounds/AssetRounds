from pathlib import Path
base=Path('.codex-temp/cold-physical-continuation-successor-v3/candidate/FieldEvidenceApp/Infrastructure/Persistence')
p=base/'StoreGenerationFactory.swift';s=p.read_text()
needle='''    /// Whole current tree data for the cold fixed C16 projection. Ordinary
'''
add='''    /// The cold witness uses fresh retained-owner binding around every
    /// descriptor and directory-entry boundary. Ordinary helpers are unchanged.
    @MainActor
    func schema2ColdWithOpen<Value>(parent: Int32, name: String, flags: Int32,
        requireBinding: @MainActor () throws -> Void, poison: @MainActor () -> Void,
        _ body: @MainActor (Int32) throws -> Value) throws -> Value {
        try requireSettled(); try requireBinding()
        guard flags & O_ACCMODE == O_RDONLY else { throw StoreGenerationFailure.dataPointerInvalid }
        let descriptor = Darwin.openat(parent, name, flags | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        var closeAttempted = false
        do {
            try requireBinding()
            let value = try body(descriptor)
            try requireBinding()
            closeAttempted = true
            guard Darwin.close(descriptor) == 0 else {
                uncertainDescriptors.append(descriptor); poison()
                throw StoreGenerationFailure.dataPointerInvalid
            }
            try requireBinding(); try requireSettled()
            return value
        } catch {
            // Cleanup of a definitely owned FD remains checked even when the
            // admission token has already revoked. Never retry ambiguous close.
            if !closeAttempted {
                closeAttempted = true
                if Darwin.close(descriptor) != 0 { uncertainDescriptors.append(descriptor); poison() }
            }
            throw error
        }
    }
    @MainActor
    func schema2ColdNames(in parent: Int32, requireBinding: @MainActor () throws -> Void,
        poison: @MainActor () -> Void) throws -> [String] {
        try requireSettled(); try requireBinding()
        let descriptor = Darwin.openat(parent, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw StoreGenerationFailure.dataPointerInvalid }
        var directory: UnsafeMutablePointer<DIR>?
        var closeAttempted = false
        do {
            try requireBinding()
            guard let opened = Darwin.fdopendir(descriptor) else { throw StoreGenerationFailure.dataPointerInvalid }
            directory = opened
            try requireBinding()
            var values: [String] = []
            while true {
                try requireBinding()
                errno = 0
                let entry = Darwin.readdir(opened)
                let entryError = errno
                try requireBinding()
                guard let entry else {
                    guard entryError == 0 else { throw StoreGenerationFailure.dataPointerInvalid }
                    break
                }
                guard let name = OwnedStorageDirectoryEntryNameV1.decode(entry),
                      !name.utf8.contains(0), !name.contains("/") else { throw StoreGenerationFailure.dataPointerInvalid }
                if name != "." && name != ".." { values.append(name) }
            }
            try requireBinding()
            closeAttempted = true
            guard Darwin.closedir(opened) == 0 else {
                uncertainDirectories.append(opened); poison()
                throw StoreGenerationFailure.dataPointerInvalid
            }
            try requireBinding(); try requireSettled()
            return values.sorted()
        } catch {
            if !closeAttempted {
                closeAttempted = true
                if let directory {
                    if Darwin.closedir(directory) != 0 { uncertainDirectories.append(directory); poison() }
                } else if Darwin.close(descriptor) != 0 {
                    uncertainDescriptors.append(descriptor); poison()
                }
            }
            throw error
        }
    }

'''
assert needle in s;s=s.replace(needle,add+needle,1)
start=s.index('''    func schema2ColdCurrentOwnedTree(''');end=s.index('''    func postRetiredTree(''',start)
block=s[start:end]
needle='''        func named(_ parent: Int32'''
digest='''        func scopedDigest(_ fd: Int32, _ before: stat) throws -> String {
            var digest = SHA256(), bytes: off_t = 0
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                try bound()
                let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
                let readError = errno
                try bound()
                if count > 0 {
                    guard off_t(count) <= before.st_size - bytes else { throw StoreGenerationFailure.dataPointerInvalid }
                    bytes += off_t(count)
                    buffer.withUnsafeBytes { raw in
                        digest.update(bufferPointer: UnsafeRawBufferPointer(start: raw.baseAddress, count: count))
                    }
                } else if count == 0 { break }
                else if readError != EINTR { throw StoreGenerationFailure.dataPointerInvalid }
            }
            guard bytes == before.st_size else { throw StoreGenerationFailure.dataPointerInvalid }
            return digest.finalize().map { String(format: "%02x", $0) }.joined()
        }
'''
assert needle in block;block=block.replace(needle,digest+needle,1)
block=block.replace('''            guard Darwin.fstat(fd, &held) == 0,
                  Darwin.fstatat(parent, name, &path, AT_SYMLINK_NOFOLLOW) == 0,
                  fullFact(held)''','''            guard Darwin.fstat(fd, &held) == 0 else { throw StoreGenerationFailure.dataPointerInvalid }
            try bound()
            guard Darwin.fstatat(parent, name, &path, AT_SYMLINK_NOFOLLOW) == 0,
                  fullFact(held)''',1)
block=block.replace('''            try withOpen(parent: parent, name: leaf,
                flags: O_RDONLY | O_NONBLOCK | (directory ? O_DIRECTORY : 0)) { fd in''','''            try schema2ColdWithOpen(parent: parent, name: leaf,
                flags: O_RDONLY | O_NONBLOCK | (directory ? O_DIRECTORY : 0),
                requireBinding: bound, poison: poison) { fd in''',1)
block=block.replace('try names(in: fd)','try schema2ColdNames(in: fd, requireBinding: bound, poison: poison)')
block=block.replace('let sha = try digestFile(fd, before: before)','let sha = try scopedDigest(fd, before)')
s=s[:start]+block+s[end:];p.write_text(s)

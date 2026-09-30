from pathlib import Path
base=Path('.codex-temp/cold-physical-continuation-successor-v3/candidate/FieldEvidenceApp/Infrastructure/Persistence')
p=base/'StoreGenerationFactory.swift';s=p.read_text().replace('''        guard flags & O_ACCMODE == O_RDONLY else''','''        guard flags & ~(O_DIRECTORY | O_NONBLOCK) == O_RDONLY,
              !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.utf8.contains(0) else''',1)
p.write_text(s)
p=base/'EraseSchema2ColdAuxiliaryFirstObservationV1.swift';s=p.read_text()
start=s.index('''    private func scan(''');end=s.index('''    private func originalNodes()''',start);block=s[start:end]
block=block.replace('''        var parentFacts: [String: String] = [:]''','''        func poison() { self.uncertain = true; permit.poisonOnUncertainEffect() }
        var parentFacts: [String: String] = [:]''',1)
block=block.replace('''            var held = stat()
            guard Darwin.fstat''','''            try bound()
            var held = stat()
            guard Darwin.fstat''')
block=block.replace('try io.names(in: support)','try io.schema2ColdNames(in: support, requireBinding: bound, poison: poison)')
block=block.replace('''            var named = stat()
            if Darwin.fstatat(parent.1, parts[1], &named, AT_SYMLINK_NOFOLLOW) != 0 {
                guard errno == ENOENT''','''            try bound()
            var named = stat()
            let status = Darwin.fstatat(parent.1, parts[1], &named, AT_SYMLINK_NOFOLLOW)
            let namedError = errno
            try bound()
            if status != 0 {
                guard namedError == ENOENT''',1)
s=s[:start]+block+s[end:]
start=s.index('''    private func withTargetParent<Value>''');end=s.index('''    /// One fixed mixed ordinal''',start);block=s[start:end]
block=block.replace('''        requireBinding: () throws -> Void, _ body: (Int32,String) throws -> Value)''','''        requireBinding: @MainActor () throws -> Void, poison: @MainActor () -> Void,
        _ body: @MainActor (Int32,String) throws -> Value)''',1)
block=block.replace('''return try io.withOpen(parent: fd, name: parts[index], flags: O_RDONLY | O_DIRECTORY | O_NONBLOCK)''','''return try io.schema2ColdWithOpen(parent: fd, name: parts[index], flags: O_RDONLY | O_DIRECTORY | O_NONBLOCK,
                requireBinding: requireBinding, poison: poison)''',1)
block=block.replace('''                guard Darwin.fstat(child, &held) == 0,
                      Darwin.fstatat''','''                try requireBinding()
                guard Darwin.fstat(child, &held) == 0 else { throw EraseAllServiceError.invalidAuthority }
                try requireBinding()
                guard Darwin.fstatat''',1)
block=block.replace('try io.names(in: child)','try io.schema2ColdNames(in: child, requireBinding: requireBinding, poison: poison)')
s=s[:start]+block+s[end:]
start=s.index('''    func performOneTarget(''');end=s.index('''    fileprivate func requireReceipt(''',start);block=s[start:end]
block=block.replace('''        let target = targets[index]''','''        func bound() throws { try self.requireBinding(permit, progress: progress); try c16Scope?.requireCurrentBinding() }
        func poison() { self.uncertain = true; permit.poisonOnUncertainEffect(); c16Scope?.poisonOnUncertainObservation() }
        let target = targets[index]''',1)
block=block.replace('''                requireBinding: { try self.requireBinding(permit, progress: progress) })''','''                requireBinding: bound, poison: poison)''',1)
block=block.replace('''                    try io.withOpen(parent: parent, name: name,
                        flags: O_RDONLY | O_NONBLOCK | (directory ? O_DIRECTORY : 0))''','''                    try io.schema2ColdWithOpen(parent: parent, name: name,
                        flags: O_RDONLY | O_NONBLOCK | (directory ? O_DIRECTORY : 0), requireBinding: bound, poison: poison)''',1)
block=block.replace('''                        guard Darwin.fstat(fd, &held) == 0,
                              Darwin.fstatat''','''                        try bound()
                        guard Darwin.fstat(fd, &held) == 0 else { throw EraseAllServiceError.invalidAuthority }
                        try bound()
                        guard Darwin.fstatat''',1)
block=block.replace('try io.names(in: fd)','try io.schema2ColdNames(in: fd, requireBinding: bound, poison: poison)')
block=block.replace('''                        effect = .unlinked
                        guard Darwin.fsync(parent) == 0,
                              Darwin.fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) != 0,
                              errno == ENOENT else''','''                        effect = .unlinked
                        try bound()
                        guard Darwin.fsync(parent) == 0 else { throw EraseAllServiceError.cleanupFailed }
                        try bound()
                        guard Darwin.fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) != 0,
                              errno == ENOENT else''',1)
block=block.replace('''                    guard Darwin.fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) != 0,
                          errno == ENOENT, Darwin.fsync(parent) == 0 else { throw EraseAllServiceError.cleanupFailed }
''','''                    try bound()
                    guard Darwin.fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) != 0,
                          errno == ENOENT else { throw EraseAllServiceError.cleanupFailed }
                    try bound()
                    guard Darwin.fsync(parent) == 0 else { throw EraseAllServiceError.cleanupFailed }
                    try bound()
''',1)
s=s[:start]+block+s[end:];p.write_text(s)

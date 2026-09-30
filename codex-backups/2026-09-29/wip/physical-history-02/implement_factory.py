from pathlib import Path
p=Path('.codex-temp/cold-physical-continuation-successor-v1/candidate/FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift')
s=p.read_text(); start=s.index('    @MainActor\n    func schema2ColdCurrentC16Tree('); end=s.index('\n    func postRetiredTree(',start)
s=s[:start]+'''    @MainActor
    func schema2ColdCurrentC16Tree(parent: Int32, name: String,
        operationsURL: URL,
        scope: OriginalEraseC16CurrentObservationScopeV1
    ) throws -> Schema2ColdCurrentTreeV1 {
        guard name == "ScratchDataV1" || name == "ProtectedIngressReceiptsV1" else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        var parentFact = stat()
        guard Darwin.fstat(parent, &parentFact) == 0 else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return try schema2ColdCurrentOwnedTree(parent: parent, name: name,
            rootURL: operationsURL.appendingPathComponent(name, isDirectory: true),
            expectedUser: parentFact.st_uid, expectedGroup: parentFact.st_gid,
            scope: scope, operationsRelativePrefix: name,
            requireBinding: { try scope.requireCurrentBinding() },
            poison: { scope.poisonOnUncertainObservation() })
    }

    /// Complete data image of one fixed, private auxiliary tree. This adds no
    /// ordinary-walker exemption: the default remains a one-link regular file.
    /// The sole exceptional path is a Ledger-issued exact C16 role. A caller
    /// retains this checked IO owner before the first call and brackets every
    /// observation with its actual EX/G and current canonical Store record.
    @MainActor
    func schema2ColdCurrentOwnedTree(parent: Int32, name: String,
        rootURL: URL, expectedUser: uid_t, expectedGroup: gid_t,
        scope: OriginalEraseC16CurrentObservationScopeV1? = nil,
        operationsRelativePrefix: String? = nil,
        requireBinding: @MainActor () throws -> Void,
        poison: @MainActor () -> Void
    ) throws -> Schema2ColdCurrentTreeV1 {
        try requireSettled(); try requireBinding()
        guard rootURL.isFileURL, rootURL.lastPathComponent == name,
              !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.utf8.contains(0),
              expectedUser == Darwin.geteuid(),
              (scope == nil) == (operationsRelativePrefix == nil) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        var parentFact = stat()
        guard Darwin.fstat(parent, &parentFact) == 0,
              parentFact.st_mode & S_IFMT == S_IFDIR,
              parentFact.st_uid == expectedUser, parentFact.st_gid == expectedGroup else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        var nodes: [Schema2ColdCurrentTreeV1.Node] = [], tokens: [String] = []
        var count = 0, totalBytes: Int64 = 0
        var rootFact: String?
        func fullFact(_ f: stat) -> String {
            [String(f.st_dev), String(f.st_ino), String(f.st_mode),
             String(f.st_uid), String(f.st_gid), String(f.st_nlink), String(f.st_size),
             String(f.st_mtimespec.tv_sec), String(f.st_mtimespec.tv_nsec),
             String(f.st_ctimespec.tv_sec), String(f.st_ctimespec.tv_nsec)].joined(separator: "|")
        }
        func nine(_ f: stat) -> String {
            [String(f.st_dev), String(f.st_ino), String(f.st_mode),
             String(f.st_nlink), String(f.st_size), String(f.st_mtimespec.tv_sec),
             String(f.st_mtimespec.tv_nsec), String(f.st_ctimespec.tv_sec),
             String(f.st_ctimespec.tv_nsec)].joined(separator: "|")
        }
        func encoded(_ x: String) -> String { x.utf8.map { String(format: "%02x", $0) }.joined() }
        func bound() throws { try requireSettled(); try requireBinding(); try scope?.requireCurrentBinding() }
        func retain(_ fd: Int32) { retainUncertainDescriptor(fd); scope?.poisonOnUncertainObservation(); poison() }
        func named(_ parent: Int32, _ name: String, _ fd: Int32, _ before: stat) throws {
            try bound()
            var held = stat(), path = stat()
            guard Darwin.fstat(fd, &held) == 0,
                  Darwin.fstatat(parent, name, &path, AT_SYMLINK_NOFOLLOW) == 0,
                  fullFact(held) == fullFact(before), fullFact(path) == fullFact(before) else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        }
        func policy(_ url: URL, _ f: stat) throws -> TemporalPolicyObservationV1 {
            try bound()
            let directory = f.st_mode & S_IFMT == S_IFDIR
            let value = try ProtectedFilePolicyV1.observeTemporalPolicyWithCheckedClose(
                directory ? .stagingDirectory : .temporaryFile, at: url,
                retainUncertainDescriptor: retain)
            try bound()
            guard value.device == UInt64(f.st_dev), value.inode == UInt64(f.st_ino),
                  value.mode == UInt16(f.st_mode), value.linkCount == UInt64(f.st_nlink),
                  value.isDirectory == directory, value.backupExcluded == true,
                  value.state == .strictComplete || value.state == .pendingSimulatorRequest else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            return value
        }
        func walk(_ parent: Int32, _ leaf: String, _ path: String, _ depth: Int) throws {
            try bound()
            guard depth <= 64, count < 100_000 else { throw StoreGenerationFailure.dataPointerInvalid }
            count += 1
            var before = stat()
            guard Darwin.fstatat(parent, leaf, &before, AT_SYMLINK_NOFOLLOW) == 0,
                  before.st_dev == parentFact.st_dev, before.st_uid == expectedUser,
                  before.st_gid == expectedGroup else { throw StoreGenerationFailure.dataPointerInvalid }
            let directory = before.st_mode & S_IFMT == S_IFDIR
            guard directory || before.st_mode & S_IFMT == S_IFREG,
                  before.st_mode & 0o777 == (directory ? 0o700 : 0o600),
                  directory ? before.st_nlink > 0 : before.st_nlink == 1 || before.st_nlink == 2 else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            let url = path.isEmpty ? rootURL : rootURL.appendingPathComponent(path, isDirectory: directory)
            try withOpen(parent: parent, name: leaf,
                flags: O_RDONLY | O_NONBLOCK | (directory ? O_DIRECTORY : 0)) { fd in
                try named(parent, leaf, fd, before)
                if directory {
                    let namesBefore = try names(in: fd)
                    let observedPolicy = try policy(url, before)
                    if path.isEmpty { rootFact = fullFact(before) }
                    nodes.append(.init(path: path, fullFact: fullFact(before), names: namesBefore,
                        sha256: nil, policy: observedPolicy, publicationRole: .ordinary))
                    tokens.append("D|\\(encoded(path))|\\(nine(before))|\\(namesBefore.map(encoded).joined(separator: ","))")
                    for child in namesBefore {
                        guard !child.isEmpty, child != ".", child != "..", !child.contains("/"),
                              !child.utf8.contains(0) else { throw StoreGenerationFailure.dataPointerInvalid }
                        try walk(fd, child, path.isEmpty ? child : path + "/" + child, depth + 1)
                    }
                    guard try names(in: fd) == namesBefore else { throw StoreGenerationFailure.dataPointerInvalid }
                } else {
                    guard before.st_size >= 0, before.st_size <= 1_073_741_824,
                          totalBytes <= 1_073_741_824 - Int64(before.st_size) else {
                        throw StoreGenerationFailure.dataPointerInvalid
                    }
                    totalBytes += Int64(before.st_size) // Each recorded alias consumes its own tree allowance.
                    let sha = try digestFile(fd, before: before)
                    try named(parent, leaf, fd, before)
                    let rolePath = operationsRelativePrefix.map { path.isEmpty ? $0 : $0 + "/" + path }
                    let role = try rolePath.flatMap { try scope?.roleFor(path: $0, fullFact: fullFact(before), sha256: sha) } ?? .ordinary
                    let observedPolicy: TemporalPolicyObservationV1?
                    switch role {
                    case .ordinary:
                        guard before.st_nlink == 1 else { throw StoreGenerationFailure.dataPointerInvalid }
                        observedPolicy = try policy(url, before)
                    case .pair(let pair):
                        guard let scope, before.st_nlink == 2,
                              url == pair.finalURL || url == pair.partialURL else { throw StoreGenerationFailure.dataPointerInvalid }
                        let values = try ProtectedFilePolicyV1.observeEraseC16CurrentTemporalPairWithCheckedClose(
                            finalURL: pair.finalURL, partialURL: pair.partialURL, scope: scope,
                            retainUncertainDescriptor: retain)
                        guard values.count == 2, values.allSatisfy({
                            $0.device == UInt64(before.st_dev) && $0.inode == UInt64(before.st_ino) && $0.linkCount == 2
                        }) else { throw StoreGenerationFailure.dataPointerInvalid }
                        observedPolicy = values[0]
                    case .firstPPair(let pair):
                        guard let scope, before.st_nlink == 2,
                              url == pair.finalURL || url == pair.partialURL else { throw StoreGenerationFailure.dataPointerInvalid }
                        let firstP = try scope.requireFirstPObservationScope()
                        let values = try ProtectedFilePolicyV1.observeEraseC16FirstPTemporalPairWithCheckedClose(
                            finalURL: pair.finalURL, partialURL: pair.partialURL, scope: firstP,
                            retainUncertainDescriptor: retain)
                        guard values.count == 2, values.allSatisfy({
                            $0.device == UInt64(before.st_dev) && $0.inode == UInt64(before.st_ino) && $0.linkCount == 2
                        }), pair.expectedSHA256 == sha,
                              pair.expectedByteCount == Int64(before.st_size) else { throw StoreGenerationFailure.dataPointerInvalid }
                        observedPolicy = values[0]
                    case .unacceptedEmptyPublication(let zero):
                        guard before.st_nlink == 1, before.st_size == 0, url == zero.temporaryURL,
                              zero.finalURL.deletingLastPathComponent() == url.deletingLastPathComponent() else {
                            throw StoreGenerationFailure.dataPointerInvalid
                        }
                        var final = stat()
                        guard Darwin.fstatat(parent, zero.finalURL.lastPathComponent, &final,
                            AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else { throw StoreGenerationFailure.dataPointerInvalid }
                        observedPolicy = nil
                    case .publicationPrefix(let prefix):
                        guard before.st_nlink == 1, url == prefix.temporaryURL,
                              Int64(before.st_size) == Int64(prefix.observedBytes.count),
                              !prefix.observedBytes.isEmpty, prefix.observedBytes.count < prefix.expectedBytes.count,
                              prefix.expectedBytes.starts(with: prefix.observedBytes),
                              prefix.finalURL.deletingLastPathComponent() == url.deletingLastPathComponent() else {
                            throw StoreGenerationFailure.dataPointerInvalid
                        }
                        var final = stat()
                        guard Darwin.fstatat(parent, prefix.finalURL.lastPathComponent, &final,
                            AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else { throw StoreGenerationFailure.dataPointerInvalid }
                        observedPolicy = nil
                    }
                    try bound()
                    nodes.append(.init(path: path, fullFact: fullFact(before), names: nil,
                        sha256: sha, policy: observedPolicy, publicationRole: role))
                    tokens.append("F|\\(encoded(path))|\\(nine(before))|\\(sha)")
                }
                try named(parent, leaf, fd, before)
            }
            try bound()
        }
        do {
            try walk(parent, name, "", 0); try bound()
            guard let rootFact else { throw StoreGenerationFailure.dataPointerInvalid }
            return .init(rootFact: rootFact,
                digest: SHA256.hash(data: Data(tokens.joined(separator: "\\n").utf8)).map { String(format: "%02x", $0) }.joined(),
                nodes: nodes.sorted { $0.path < $1.path })
        } catch {
            if (try? requireSettled()) == nil { scope?.poisonOnUncertainObservation(); poison() }
            throw error
        }
    }
''' +s[end:]; p.write_text(s)

import Darwin
import Foundation

enum EntitlementStoreFailurePoint: Equatable, Sendable {
    case beforeWrite
    case afterTemporaryWrite
}

enum EntitlementStoreError: Error, Equatable, Sendable {
    case invalidAuthority
    case invalidCache
    case collidingAuthority
    case staleCache
    case writeFailed
}

/// The sole durable commerce authority. The file deliberately contains only
/// normalized entitlement facts; StoreKit receipts, JWS values, transaction
/// identifiers, and customer/storefront identity never enter this store.
@MainActor
final class EntitlementStore {
    typealias FailureInjection = @Sendable (
        EntitlementStoreFailurePoint
    ) throws -> Void

    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private struct ReadValue {
        let data: Data
        let identity: Identity
    }

    private static let directoryName = "FieldEvidenceCommerce"
    private static let cacheName = "entitlement.json"
    private static let temporaryName = ".entitlement.json.next"

    private let applicationSupportURL: URL
    private let applicationSupportDescriptor: Int32
    private let applicationSupportIdentity: Identity
    private let commerceDescriptor: Int32
    private let commerceIdentity: Identity
    private let failureInjection: FailureInjection

    init(
        applicationSupportURL: URL,
        fileManager: FileManager = .default,
        failureInjection: @escaping FailureInjection = { _ in }
    ) throws {
        let root = applicationSupportURL.standardizedFileURL
        guard root.isFileURL else {
            throw EntitlementStoreError.invalidAuthority
        }
        _ = fileManager

        let applicationSupportDescriptor = Darwin.open(
            root.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard applicationSupportDescriptor >= 0 else {
            throw EntitlementStoreError.invalidAuthority
        }
        var ownsApplicationSupport = true
        defer {
            if ownsApplicationSupport {
                _ = Darwin.close(applicationSupportDescriptor)
            }
        }
        let applicationSupportIdentity = try Self.directoryIdentity(
            applicationSupportDescriptor
        )

        var commerceDescriptor = Darwin.openat(
            applicationSupportDescriptor,
            Self.directoryName,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        if commerceDescriptor < 0, errno == ENOENT {
            guard Darwin.mkdirat(
                applicationSupportDescriptor,
                Self.directoryName,
                mode_t(0o700)
            ) == 0,
                  Darwin.fsync(applicationSupportDescriptor) == 0 else {
                throw EntitlementStoreError.invalidAuthority
            }
            commerceDescriptor = Darwin.openat(
                applicationSupportDescriptor,
                Self.directoryName,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW
            )
        }
        guard commerceDescriptor >= 0 else {
            throw EntitlementStoreError.invalidAuthority
        }
        var ownsCommerce = true
        defer {
            if ownsCommerce { _ = Darwin.close(commerceDescriptor) }
        }
        let commerceIdentity = try Self.directoryIdentity(commerceDescriptor)
        do {
            try ProtectedFilePolicyV1.applyAndVerify(
                .stagingDirectory,
                relativePath: Self.directoryName,
                within: root
            ) {
                guard try Self.directoryIdentity(applicationSupportDescriptor)
                        == applicationSupportIdentity,
                      try Self.directoryIdentity(commerceDescriptor)
                        == commerceIdentity else {
                    throw EntitlementStoreError.invalidAuthority
                }
            }
        } catch {
            throw EntitlementStoreError.invalidAuthority
        }

        self.applicationSupportURL = root
        self.applicationSupportDescriptor = applicationSupportDescriptor
        self.applicationSupportIdentity = applicationSupportIdentity
        self.commerceDescriptor = commerceDescriptor
        self.commerceIdentity = commerceIdentity
        self.failureInjection = failureInjection
        ownsApplicationSupport = false
        ownsCommerce = false
    }

    deinit {
        _ = Darwin.close(commerceDescriptor)
        _ = Darwin.close(applicationSupportDescriptor)
    }

    func load() throws -> EntitlementCacheV1? {
        try verifyAuthority()
        let names = try directoryNames()
        guard names.allSatisfy({ $0 == Self.cacheName }) else {
            throw EntitlementStoreError.collidingAuthority
        }
        try verifyExistingPolicy(
            .commerceEntitlementCache,
            name: Self.cacheName
        )
        guard let value = try readIfPresent(Self.cacheName) else {
            return nil
        }
        let cache = try EntitlementCacheCodecV1.decode(value.data)
        try verifyAuthority()
        return cache
    }

    @discardableResult
    func persist(_ cache: EntitlementCacheV1) throws -> EntitlementCacheV1 {
        let replacement = try EntitlementCacheCodecV1.encode(cache)
        try verifyAuthority()
        let names = try directoryNames()
        guard names.allSatisfy({ $0 == Self.cacheName }) else {
            throw EntitlementStoreError.collidingAuthority
        }
        try verifyExistingPolicy(
            .commerceEntitlementCache,
            name: Self.cacheName
        )

        let priorValue = try readIfPresent(Self.cacheName)
        let prior = try priorValue.map { value in
            try EntitlementCacheCodecV1.decode(value.data)
        }
        if let prior {
            guard !prior.hasEverVerifiedPaid || cache.hasEverVerifiedPaid else {
                throw EntitlementStoreError.staleCache
            }
            if cache.verifiedAt < prior.verifiedAt {
                throw EntitlementStoreError.staleCache
            }
            if cache.verifiedAt == prior.verifiedAt {
                guard cache == prior else {
                    throw EntitlementStoreError.staleCache
                }
                return prior
            }
        }

        var temporaryValue: ReadValue?
        var published = false
        var swapped = false
        do {
            try failureInjection(.beforeWrite)
            temporaryValue = try createTemporary(replacement)
            try failureInjection(.afterTemporaryWrite)

            if let priorValue {
                guard let current = try readIfPresent(Self.cacheName),
                      current.identity == priorValue.identity,
                      current.data == priorValue.data else {
                    throw EntitlementStoreError.collidingAuthority
                }
                guard Darwin.renameatx_np(
                    commerceDescriptor,
                    Self.temporaryName,
                    commerceDescriptor,
                    Self.cacheName,
                    UInt32(RENAME_SWAP)
                ) == 0 else {
                    throw EntitlementStoreError.writeFailed
                }
                published = true
                swapped = true
            } else {
                guard case nil = try readIfPresent(Self.cacheName),
                      Darwin.renameatx_np(
                        commerceDescriptor,
                        Self.temporaryName,
                        commerceDescriptor,
                        Self.cacheName,
                        UInt32(RENAME_EXCL)
                      ) == 0 else {
                    throw EntitlementStoreError.collidingAuthority
                }
                published = true
            }
            guard Darwin.fsync(commerceDescriptor) == 0 else {
                throw EntitlementStoreError.writeFailed
            }
            guard let temporaryValue else {
                throw EntitlementStoreError.writeFailed
            }
            try applyPublishedPolicy(
                .commerceEntitlementCache,
                name: Self.cacheName,
                expectedIdentity: temporaryValue.identity
            )
            guard let reopened = try readIfPresent(Self.cacheName),
                  reopened.identity == temporaryValue.identity,
                  reopened.data == replacement else {
                throw EntitlementStoreError.writeFailed
            }
            if let priorValue {
                try applyPublishedPolicy(
                    .temporaryFile,
                    name: Self.temporaryName,
                    expectedIdentity: priorValue.identity
                )
                guard let displaced = try readIfPresent(Self.temporaryName),
                      displaced.identity == priorValue.identity,
                      displaced.data == priorValue.data else {
                    throw EntitlementStoreError.writeFailed
                }
                guard try directoryNames()
                        == [Self.cacheName, Self.temporaryName].sorted() else {
                    throw EntitlementStoreError.writeFailed
                }
            }
            let durable = try EntitlementCacheCodecV1.decode(reopened.data)
            guard durable == cache else {
                throw EntitlementStoreError.writeFailed
            }
            if let priorValue {
                try removeExact(Self.temporaryName, expected: priorValue)
                swapped = false
            }
            guard try directoryNames() == [Self.cacheName] else {
                throw EntitlementStoreError.writeFailed
            }
            try verifyAuthority()
            return durable
        } catch {
            if let temporaryValue {
                if let priorValue, swapped {
                    do {
                        if let current = try readIfPresent(Self.cacheName),
                           let displaced = try readIfPresent(Self.temporaryName),
                           current.identity == temporaryValue.identity,
                           current.data == replacement,
                           displaced.identity == priorValue.identity,
                           displaced.data == priorValue.data {
                            _ = Darwin.renameatx_np(
                                commerceDescriptor,
                                Self.temporaryName,
                                commerceDescriptor,
                                Self.cacheName,
                                UInt32(RENAME_SWAP)
                            )
                            _ = Darwin.fsync(commerceDescriptor)
                        }
                    } catch {
                        // Preserve the exact failure and leave uncertain state for recovery.
                    }
                } else if priorValue == nil, published {
                    do {
                        if let current = try readIfPresent(Self.cacheName),
                           current.identity == temporaryValue.identity,
                           current.data == replacement {
                            try removeExact(Self.cacheName, expected: current)
                        }
                    } catch {
                        // Preserve the exact failure and leave uncertain state for recovery.
                    }
                }
            }
            if let temporaryValue {
                try? removeIfExact(
                    Self.temporaryName,
                    expected: temporaryValue.identity
                )
            }
            if let storeError = error as? EntitlementStoreError {
                throw storeError
            }
            throw EntitlementStoreError.writeFailed
        }
    }
}

private extension EntitlementStore {
    func policyRelativePath(_ name: String) -> String {
        "\(Self.directoryName)/\(name)"
    }

    func verifyExistingPolicy(
        _ kind: OwnedFileKindV1,
        name: String
    ) throws {
        do {
            try verifyAuthority()
            let descriptor = Darwin.openat(
                commerceDescriptor,
                name,
                O_RDONLY | O_NOFOLLOW
            )
            if descriptor < 0, errno == ENOENT { return }
            guard descriptor >= 0 else {
                throw EntitlementStoreError.invalidAuthority
            }
            defer { _ = Darwin.close(descriptor) }
            let expected = try Self.fileIdentity(descriptor)
            try ProtectedFilePolicyV1.applyAndVerify(
                kind,
                relativePath: policyRelativePath(name),
                within: applicationSupportURL
            ) {
                try verifyAuthority()
                try verifyLeaf(
                    name,
                    descriptor: descriptor,
                    expected: expected
                )
            }
        } catch {
            throw EntitlementStoreError.invalidAuthority
        }
    }

    func applyPublishedPolicy(
        _ kind: OwnedFileKindV1,
        name: String,
        descriptor: Int32? = nil,
        expectedIdentity: Identity? = nil
    ) throws {
        let retainedDescriptor: Int32
        let ownsDescriptor: Bool
        if let descriptor {
            retainedDescriptor = descriptor
            ownsDescriptor = false
        } else {
            retainedDescriptor = Darwin.openat(
                commerceDescriptor,
                name,
                O_RDONLY | O_NOFOLLOW
            )
            guard retainedDescriptor >= 0 else {
                throw EntitlementStoreError.writeFailed
            }
            ownsDescriptor = true
        }
        defer {
            if ownsDescriptor { _ = Darwin.close(retainedDescriptor) }
        }
        do {
            let expected: Identity
            if let expectedIdentity {
                expected = expectedIdentity
            } else {
                expected = try Self.fileIdentity(retainedDescriptor)
            }
            try ProtectedFilePolicyV1.applyAndVerify(
                kind,
                relativePath: policyRelativePath(name),
                within: applicationSupportURL
            ) {
                try verifyAuthority()
                try verifyLeaf(
                    name,
                    descriptor: retainedDescriptor,
                    expected: expected
                )
            }
        } catch {
            throw EntitlementStoreError.writeFailed
        }
    }

    func verifyAuthority() throws {
        guard try Self.directoryIdentity(applicationSupportDescriptor)
                == applicationSupportIdentity,
              try Self.directoryIdentity(commerceDescriptor)
                == commerceIdentity else {
            throw EntitlementStoreError.invalidAuthority
        }

        let reopenedApplicationSupport = Darwin.open(
            applicationSupportURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard reopenedApplicationSupport >= 0 else {
            throw EntitlementStoreError.invalidAuthority
        }
        defer { _ = Darwin.close(reopenedApplicationSupport) }
        guard try Self.directoryIdentity(reopenedApplicationSupport)
                == applicationSupportIdentity else {
            throw EntitlementStoreError.invalidAuthority
        }

        let reopenedCommerce = Darwin.openat(
            reopenedApplicationSupport,
            Self.directoryName,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard reopenedCommerce >= 0 else {
            throw EntitlementStoreError.invalidAuthority
        }
        defer { _ = Darwin.close(reopenedCommerce) }
        guard try Self.directoryIdentity(reopenedCommerce) == commerceIdentity
        else {
            throw EntitlementStoreError.invalidAuthority
        }
    }

    func createTemporary(_ data: Data) throws -> ReadValue {
        guard case nil = try readIfPresent(Self.temporaryName) else {
            throw EntitlementStoreError.collidingAuthority
        }
        let descriptor = Darwin.openat(
            commerceDescriptor,
            Self.temporaryName,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard descriptor >= 0 else {
            throw EntitlementStoreError.writeFailed
        }
        defer { _ = Darwin.close(descriptor) }
        let expectedIdentity = try Self.fileIdentity(descriptor)
        do {
            try applyPublishedPolicy(
                .temporaryFile,
                name: Self.temporaryName,
                descriptor: descriptor,
                expectedIdentity: expectedIdentity
            )
            try data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var offset = 0
                while offset < raw.count {
                    let count = Darwin.write(
                        descriptor,
                        base.advanced(by: offset),
                        raw.count - offset
                    )
                    if count > 0 {
                        offset += count
                    } else if errno != EINTR {
                        throw EntitlementStoreError.writeFailed
                    }
                }
            }
            guard Darwin.fsync(descriptor) == 0,
                  let reopened = try readIfPresent(Self.temporaryName),
                  reopened.identity == expectedIdentity,
                  reopened.data == data else {
                throw EntitlementStoreError.writeFailed
            }
            return reopened
        } catch {
            try? removeIfExact(
                Self.temporaryName,
                expected: expectedIdentity
            )
            throw error
        }
    }

    func removeIfExact(_ name: String, expected: Identity) throws {
        guard let current = try readIfPresent(name),
              current.identity == expected,
              Darwin.unlinkat(commerceDescriptor, name, 0) == 0,
              Darwin.fsync(commerceDescriptor) == 0,
              case nil = try readIfPresent(name) else {
            throw EntitlementStoreError.collidingAuthority
        }
    }

    func removeExact(_ name: String, expected: ReadValue) throws {
        guard let current = try readIfPresent(name),
              current.identity == expected.identity,
              current.data == expected.data,
              Darwin.unlinkat(commerceDescriptor, name, 0) == 0,
              Darwin.fsync(commerceDescriptor) == 0,
              case nil = try readIfPresent(name) else {
            throw EntitlementStoreError.collidingAuthority
        }
    }

    func verifyLeaf(
        _ name: String,
        descriptor: Int32,
        expected: Identity
    ) throws {
        guard try Self.fileIdentity(descriptor) == expected else {
            throw EntitlementStoreError.invalidAuthority
        }
        var info = stat()
        guard Darwin.fstatat(
            commerceDescriptor,
            name,
            &info,
            AT_SYMLINK_NOFOLLOW
        ) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1,
              Identity(device: info.st_dev, inode: info.st_ino) == expected else {
            throw EntitlementStoreError.invalidAuthority
        }
    }

    private func readIfPresent(_ name: String) throws -> ReadValue? {
        let descriptor = Darwin.openat(
            commerceDescriptor,
            name,
            O_RDONLY | O_NOFOLLOW
        )
        if descriptor < 0, errno == ENOENT { return nil }
        guard descriptor >= 0 else {
            throw EntitlementStoreError.invalidAuthority
        }
        defer { _ = Darwin.close(descriptor) }

        var before = stat()
        guard Darwin.fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1,
              before.st_size >= 0,
              before.st_size <= 64 * 1024 else {
            throw EntitlementStoreError.invalidAuthority
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count > 0 {
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                break
            } else if errno != EINTR {
                throw EntitlementStoreError.invalidAuthority
            }
        }

        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              data.count == Int(after.st_size) else {
            throw EntitlementStoreError.invalidAuthority
        }
        return ReadValue(
            data: data,
            identity: Identity(device: after.st_dev, inode: after.st_ino)
        )
    }

    func directoryNames() throws -> [String] {
        let independent = Darwin.openat(
            commerceDescriptor,
            ".",
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard independent >= 0,
              let directory = Darwin.fdopendir(independent) else {
            if independent >= 0 { _ = Darwin.close(independent) }
            throw EntitlementStoreError.invalidAuthority
        }
        defer { _ = Darwin.closedir(directory) }

        var names = [String]()
        errno = 0
        while let entry = Darwin.readdir(directory) {
            var tuple = entry.pointee.d_name
            let capacity = MemoryLayout.size(ofValue: tuple)
            let name = withUnsafePointer(to: &tuple) { pointer in
                pointer.withMemoryRebound(
                    to: CChar.self,
                    capacity: capacity
                ) { String(cString: $0) }
            }
            if name != ".", name != ".." { names.append(name) }
        }
        guard errno == 0 else {
            throw EntitlementStoreError.invalidAuthority
        }
        return names.sorted()
    }

    private static func directoryIdentity(
        _ descriptor: Int32
    ) throws -> Identity {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR else {
            throw EntitlementStoreError.invalidAuthority
        }
        return Identity(device: info.st_dev, inode: info.st_ino)
    }

    private static func fileIdentity(_ descriptor: Int32) throws -> Identity {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_nlink == 1 else {
            throw EntitlementStoreError.invalidAuthority
        }
        return Identity(device: info.st_dev, inode: info.st_ino)
    }
}

enum EntitlementCacheCodecV1 {
    private static let keys: Set<String> = [
        "expirationAt",
        "graceExpirationAt",
        "hasEverVerifiedPaid",
        "productID",
        "revocationAt",
        "schemaVersion",
        "state",
        "verifiedAt",
    ]

    static func encode(_ cache: EntitlementCacheV1) throws -> Data {
        do {
            _ = try EntitlementReducerV1.offlineState(
                cache: cache,
                now: cache.verifiedAt
            )
            return try CanonicalJSONV1.encode(.object([
                "expirationAt": CanonicalJSONV1.optionalDate(
                    cache.expirationAt
                ),
                "graceExpirationAt": CanonicalJSONV1.optionalDate(
                    cache.graceExpirationAt
                ),
                "hasEverVerifiedPaid": .bool(cache.hasEverVerifiedPaid),
                "productID": .string(cache.productID),
                "revocationAt": CanonicalJSONV1.optionalDate(
                    cache.revocationAt
                ),
                "schemaVersion": .integer(cache.schemaVersion),
                "state": .string(cache.state.rawValue),
                "verifiedAt": CanonicalJSONV1.date(cache.verifiedAt),
            ]))
        } catch {
            throw EntitlementStoreError.invalidCache
        }
    }

    static func decode(_ data: Data) throws -> EntitlementCacheV1 {
        do {
            guard let object = try JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
                  Set(object.keys) == keys,
                  let schemaVersion = object["schemaVersion"] as? Int,
                  let productID = object["productID"] as? String,
                  let rawState = object["state"] as? String,
                  let state = CachedEntitlementStateV1(rawValue: rawState),
                  let verifiedAt = date(object["verifiedAt"]),
                  let hasEverVerifiedPaid = object["hasEverVerifiedPaid"]
                    as? Bool else {
                throw EntitlementStoreError.invalidCache
            }
            let cache = EntitlementCacheV1(
                schemaVersion: schemaVersion,
                productID: productID,
                state: state,
                expirationAt: try optionalDate(object["expirationAt"]),
                graceExpirationAt: try optionalDate(
                    object["graceExpirationAt"]
                ),
                revocationAt: try optionalDate(object["revocationAt"]),
                verifiedAt: verifiedAt,
                hasEverVerifiedPaid: hasEverVerifiedPaid
            )
            guard try encode(cache) == data else {
                throw EntitlementStoreError.invalidCache
            }
            return cache
        } catch let error as EntitlementStoreError {
            throw error
        } catch {
            throw EntitlementStoreError.invalidCache
        }
    }

    private static func optionalDate(_ value: Any?) throws -> Date? {
        if value is NSNull { return nil }
        guard let result = date(value) else {
            throw EntitlementStoreError.invalidCache
        }
        return result
    }

    private static func date(_ value: Any?) -> Date? {
        guard let string = value as? String,
              let date = timestampFormatter.date(from: string),
              timestampFormatter.string(from: date) == string else {
            return nil
        }
        return date
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

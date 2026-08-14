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

        do {
            try failureInjection(.beforeWrite)
            try createTemporary(replacement)
            try failureInjection(.afterTemporaryWrite)

            if let priorValue {
                guard let current = try readIfPresent(Self.cacheName),
                      current.identity == priorValue.identity,
                      current.data == priorValue.data else {
                    throw EntitlementStoreError.collidingAuthority
                }
                guard Darwin.renameat(
                    commerceDescriptor,
                    Self.temporaryName,
                    commerceDescriptor,
                    Self.cacheName
                ) == 0 else {
                    throw EntitlementStoreError.writeFailed
                }
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
            }
            guard Darwin.fsync(commerceDescriptor) == 0,
                  let reopened = try readIfPresent(Self.cacheName),
                  reopened.data == replacement,
                  try directoryNames() == [Self.cacheName] else {
                throw EntitlementStoreError.writeFailed
            }
            let durable = try EntitlementCacheCodecV1.decode(reopened.data)
            guard durable == cache else {
                throw EntitlementStoreError.writeFailed
            }
            try verifyAuthority()
            return durable
        } catch {
            try? removeTemporary(matching: replacement)
            if let storeError = error as? EntitlementStoreError {
                throw storeError
            }
            throw EntitlementStoreError.writeFailed
        }
    }
}

private extension EntitlementStore {
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

    func createTemporary(_ data: Data) throws {
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
        do {
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
                  reopened.data == data else {
                throw EntitlementStoreError.writeFailed
            }
        } catch {
            _ = Darwin.unlinkat(commerceDescriptor, Self.temporaryName, 0)
            _ = Darwin.fsync(commerceDescriptor)
            throw error
        }
    }

    func removeTemporary(matching data: Data) throws {
        guard let current = try readIfPresent(Self.temporaryName) else {
            return
        }
        guard current.data == data,
              let verified = try readIfPresent(Self.temporaryName),
              verified.identity == current.identity,
              verified.data == current.data,
              Darwin.unlinkat(
                commerceDescriptor,
                Self.temporaryName,
                0
              ) == 0,
              Darwin.fsync(commerceDescriptor) == 0 else {
            throw EntitlementStoreError.collidingAuthority
        }
    }

    func readIfPresent(_ name: String) throws -> ReadValue? {
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

    static func directoryIdentity(_ descriptor: Int32) throws -> Identity {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR else {
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

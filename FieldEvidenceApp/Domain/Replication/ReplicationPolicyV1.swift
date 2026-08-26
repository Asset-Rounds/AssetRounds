import Foundation

enum ReplicationAuthorityV1: String, Codable, CaseIterable, Sendable {
    case workspaceWriter = "WORKSPACE_WRITER"
    case immutableContentWriter = "IMMUTABLE_CONTENT_WRITER"
    case localDevice = "LOCAL_DEVICE"
    case derivedFromCanonicalInputs = "DERIVED_FROM_CANONICAL_INPUTS"
}

enum ReplicationPersistenceV1: String, Codable, CaseIterable, Sendable {
    case swiftDataRecord = "SWIFT_DATA_RECORD"
    case ownedFile = "OWNED_FILE"
    case nonpersistent = "NONPERSISTENT"
}

enum ReplicationTransportV1: String, Codable, CaseIterable, Sendable {
    case futureAcceptedMutationEligible = "FUTURE_ACCEPTED_MUTATION_ELIGIBLE"
    case futureBoundedBlobEligible = "FUTURE_BOUNDED_BLOB_ELIGIBLE"
    case excluded = "EXCLUDED"
}

enum ReplicationBootstrapV1: String, Codable, CaseIterable, Sendable {
    case canonicalSnapshot = "CANONICAL_SNAPSHOT"
    case immutableHistory = "IMMUTABLE_HISTORY"
    case rebuildFromDependencies = "REBUILD_FROM_DEPENDENCIES"
    case destinationLocal = "DESTINATION_LOCAL"
    case excluded = "EXCLUDED"
}

enum ReplicationPrivacyV1: String, Codable, CaseIterable, Sendable {
    case workspaceData = "WORKSPACE_DATA"
    case workspaceContentBlob = "WORKSPACE_CONTENT_BLOB"
    case privateDeviceData = "PRIVATE_DEVICE_DATA"
    case secretNeverPortable = "SECRET_NEVER_PORTABLE"
    case noncustomerDiagnostic = "NONCUSTOMER_DIAGNOSTIC"
}

enum ReplicationRetentionV1: String, Codable, CaseIterable, Sendable {
    case untilCanonicalDeleteOrErase = "UNTIL_CANONICAL_DELETE_OR_ERASE"
    case immutableHistoryUntilErase = "IMMUTABLE_HISTORY_UNTIL_ERASE"
    case rebuildable = "REBUILDABLE"
    case operationScoped = "OPERATION_SCOPED"
    case localDeviceRetained = "LOCAL_DEVICE_RETAINED"
}

enum ReplicationBackupDispositionV1: String, Codable, CaseIterable, Sendable {
    case includeCanonical = "INCLUDE_CANONICAL"
    case includeImmutableHistory = "INCLUDE_IMMUTABLE_HISTORY"
    case rebuildAfterRestore = "REBUILD_AFTER_RESTORE"
    case exclude = "EXCLUDE"
}

enum ReplicationExportDispositionV1: String, Codable, CaseIterable, Sendable {
    case portableCanonical = "PORTABLE_CANONICAL"
    case portableImmutableHistory = "PORTABLE_IMMUTABLE_HISTORY"
    case exclude = "EXCLUDE"
}

enum ReplicationDeleteDispositionV1: String, Codable, CaseIterable, Sendable {
    case canonicalDelete = "CANONICAL_DELETE"
    case appendTombstone = "APPEND_TOMBSTONE"
    case rebuild = "REBUILD"
    case operationCleanup = "OPERATION_CLEANUP"
    case localAuthority = "LOCAL_AUTHORITY"
}

enum ReplicationEraseDispositionV1: String, Codable, CaseIterable, Sendable {
    case clearWithWorkspace = "CLEAR_WITH_WORKSPACE"
    case recreateEmpty = "RECREATE_EMPTY"
    case rebuildAfterErase = "REBUILD_AFTER_ERASE"
    case localAuthority = "LOCAL_AUTHORITY"
}

struct ReplicationCodecV1: Codable, Equatable, Sendable {
    let codecID: String
    let readableVersions: [Int]
    let currentWriteVersion: Int

    init(codecID: String, readableVersions: [Int], currentWriteVersion: Int) throws {
        self.codecID = codecID
        self.readableVersions = readableVersions
        self.currentWriteVersion = currentWriteVersion
        try validate()
    }

    func validate() throws {
        guard ReplicationContractValidationV1.validToken(codecID) else {
            throw ReplicationPolicyFailureV1.invalidCodec
        }
        let normalized = Array(Set(readableVersions)).sorted()
        guard normalized == readableVersions,
              normalized.allSatisfy({ $0 > 0 }),
              normalized.contains(currentWriteVersion) else {
            throw ReplicationPolicyFailureV1.invalidCodec
        }
    }
}

enum ReplicationSizeLimitV1: Codable, Equatable, Sendable {
    case boundedBytes(Int64)
    case notApplicable

    func validate() throws {
        if case .boundedBytes(let bytes) = self, bytes <= 0 {
            throw ReplicationPolicyFailureV1.invalidSizeLimit
        }
    }
}

struct ReplicationPolicyV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumDependencyCount = 64

    let schemaVersion: Int
    let policyID: String
    let policyVersion: Int
    let authority: ReplicationAuthorityV1
    let persistence: ReplicationPersistenceV1
    let transport: ReplicationTransportV1
    let bootstrap: ReplicationBootstrapV1
    let privacy: ReplicationPrivacyV1
    let retention: ReplicationRetentionV1
    let codec: ReplicationCodecV1
    let sizeLimit: ReplicationSizeLimitV1
    let dependencies: [SyncSubjectIdentityV1]
    let backup: ReplicationBackupDispositionV1
    let export: ReplicationExportDispositionV1
    let deletion: ReplicationDeleteDispositionV1
    let erase: ReplicationEraseDispositionV1

    init(
        policyID: String,
        policyVersion: Int = 1,
        authority: ReplicationAuthorityV1,
        persistence: ReplicationPersistenceV1,
        transport: ReplicationTransportV1,
        bootstrap: ReplicationBootstrapV1,
        privacy: ReplicationPrivacyV1,
        retention: ReplicationRetentionV1,
        codec: ReplicationCodecV1,
        sizeLimit: ReplicationSizeLimitV1,
        dependencies: [SyncSubjectIdentityV1],
        backup: ReplicationBackupDispositionV1,
        export: ReplicationExportDispositionV1,
        deletion: ReplicationDeleteDispositionV1,
        erase: ReplicationEraseDispositionV1
    ) throws {
        self.schemaVersion = Self.schemaVersion
        self.policyID = policyID
        self.policyVersion = policyVersion
        self.authority = authority
        self.persistence = persistence
        self.transport = transport
        self.bootstrap = bootstrap
        self.privacy = privacy
        self.retention = retention
        self.codec = codec
        self.sizeLimit = sizeLimit
        self.dependencies = dependencies
        self.backup = backup
        self.export = export
        self.deletion = deletion
        self.erase = erase
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              ReplicationContractValidationV1.validToken(policyID),
              policyVersion > 0,
              dependencies.count <= Self.maximumDependencyCount else {
            throw ReplicationPolicyFailureV1.invalidPolicy
        }
        try codec.validate()
        try sizeLimit.validate()
        let keys = dependencies.map(\.canonicalKey)
        guard keys == keys.sorted(), Set(keys).count == keys.count else {
            throw ReplicationPolicyFailureV1.invalidDependencies
        }
        if classificationMustRemainLocal,
           transport != .excluded {
            throw ReplicationPolicyFailureV1.privateTransportEnabled
        }
        if privacy == .secretNeverPortable,
           (authority != .localDevice
                || (bootstrap != .destinationLocal && bootstrap != .excluded)
                || backup != .exclude
                || export != .exclude
                || deletion != .localAuthority
                || erase != .localAuthority) {
            throw ReplicationPolicyFailureV1.secretPortabilityEnabled
        }
    }

    func canonicalData() throws -> Data {
        try validate()
        return try WorkspaceMutationCanonicalV1.data(self)
    }

    func canonicalSHA256() throws -> String {
        try validate()
        return try WorkspaceMutationCanonicalV1.sha256(self)
    }

    static func decodeCanonical(from data: Data) throws -> Self {
        let decoder = JSONDecoder()
        let value = try decoder.decode(Self.self, from: data)
        try value.validate()
        guard try value.canonicalData() == data else {
            throw ReplicationPolicyFailureV1.invalidPolicy
        }
        return value
    }

    private var classificationMustRemainLocal: Bool {
        privacy == .privateDeviceData
            || privacy == .secretNeverPortable
            || privacy == .noncustomerDiagnostic
    }
}

enum ReplicationPolicyFailureV1: Error, Equatable {
    case invalidPolicy
    case invalidCodec
    case invalidSizeLimit
    case invalidDependencies
    case privateTransportEnabled
    case secretPortabilityEnabled
}

enum ReplicationContractValidationV1 {
    static func validToken(_ value: String) -> Bool {
        guard (1...128).contains(value.utf8.count) else { return false }
        return value.utf8.allSatisfy { byte in
            (48...57).contains(byte)
                || (65...90).contains(byte)
                || (97...122).contains(byte)
                || byte == 45 || byte == 46 || byte == 95
        }
    }

    static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}

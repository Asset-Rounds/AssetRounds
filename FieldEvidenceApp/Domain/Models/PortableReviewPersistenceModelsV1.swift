import Foundation

/// C48's exchange/session state is an operation-scoped, protected staging
/// surface.  It is intentionally not a SwiftData schema release: accepted
/// response truth is reconciled by the existing C14 writer and only the
/// immutable bytes it owns may be retained by this store.
enum C48PortableReviewPersistenceBoundaryV1 {
    static let protocolVersion = 1
    static let sessionStoreSourceVersion = 1
    static let sessionStoreVersion = 2
    static let currentPersistentSchemaVersion = 36
    static let sessionStoreIsNonpersistent = true
    static let canonicalAcceptedResponseOwner = "C14"
    static let rawCapabilityIsNeverAWorkspaceRow = true
    static let quarantineIsExcludedFromBackup = true
    static let reviewAndServiceNamespacesAreIndependent = true
    static let immutableAcceptedBytesAreNeverRewritten = true
    static let cloneOrForkInvalidatesActiveCapabilities = true
    static let eraseCannotRecallEscapedFiles = true
}

/// The two purposes have separate indexes, quotas, cleanup, and parser
/// dispatch.  A service-request record is never a portable-review record.
enum PortableExchangeSessionNamespaceV2: String, Codable, CaseIterable, Hashable, Sendable {
    case review = "REVIEW"
    case serviceRequest = "SERVICE_REQUEST"
}

enum PortableExchangeSessionStateV2: String, Codable, CaseIterable, Hashable, Sendable {
    case openUnexported = "OPEN_UNEXPORTED"
    case exportedAwaitingResponse = "EXPORTED_AWAITING_RESPONSE"
    case responsePendingDecision = "RESPONSE_PENDING_DECISION"
    case acknowledgedAwaitingDecision = "ACKNOWLEDGED_AWAITING_DECISION"
    case approvalResponseRecorded = "APPROVAL_RESPONSE_RECORDED"
    case changesResponseRecorded = "CHANGES_RESPONSE_RECORDED"
    case superseded = "SUPERSEDED"
    case closedWithoutResponse = "CLOSED_WITHOUT_RESPONSE"
    case historyOnlyTerminal = "HISTORY_ONLY_TERMINAL"
    case historyOnlySuperseded = "HISTORY_ONLY_SUPERSEDED"
    case historyOnlyClonedOrForked = "HISTORY_ONLY_CLONED_OR_FORKED"
    case quarantined = "QUARANTINED"
    case erasePending = "ERASE_PENDING"
    case erased = "ERASED"

    var isImmutableHistory: Bool {
        switch self {
        case .approvalResponseRecorded,
             .changesResponseRecorded,
             .superseded,
             .closedWithoutResponse,
             .historyOnlyTerminal,
             .historyOnlySuperseded,
             .historyOnlyClonedOrForked,
             .erased:
            return true
        case .openUnexported,
             .exportedAwaitingResponse,
             .responsePendingDecision,
             .acknowledgedAwaitingDecision,
             .quarantined,
             .erasePending:
            return false
        }
    }

    var permitsCapabilityUse: Bool {
        self == .exportedAwaitingResponse || self == .responsePendingDecision
    }

    var isDiscardableScratch: Bool {
        self == .openUnexported || self == .quarantined
    }
}

enum PortableExchangeCapabilityStateV2: String, Codable, CaseIterable, Hashable, Sendable {
    case issuedNotExported = "ISSUED_NOT_EXPORTED"
    case exportedAccepting = "EXPORTED_ACCEPTING"
    case responsePendingDecision = "RESPONSE_PENDING_DECISION"
    case historyOnlyTerminal = "HISTORY_ONLY_TERMINAL"
    case historyOnlySuperseded = "HISTORY_ONLY_SUPERSEDED"
    case historyOnlyClonedOrForked = "HISTORY_ONLY_CLONED_OR_FORKED"
    case unavailableCorruptOrMissing = "UNAVAILABLE_CORRUPT_OR_MISSING"
    case erasePending = "ERASE_PENDING"
    case erased = "ERASED"

    var isActive: Bool {
        switch self {
        case .issuedNotExported, .exportedAccepting, .responsePendingDecision:
            return true
        case .historyOnlyTerminal,
             .historyOnlySuperseded,
             .historyOnlyClonedOrForked,
             .unavailableCorruptOrMissing,
             .erasePending,
             .erased:
            return false
        }
    }
}

enum PortableExchangeImmutableByteRoleV2: String, Codable, CaseIterable, Hashable, Sendable {
    case requestPackage = "REQUEST_PACKAGE"
    case requestManifest = "REQUEST_MANIFEST"
    case acceptedResponse = "ACCEPTED_RESPONSE"
    case reconciliationReceipt = "RECONCILIATION_RECEIPT"
}

struct PortableExchangeImmutableByteReferenceV2: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 2

    let schemaVersion: Int
    let role: PortableExchangeImmutableByteRoleV2
    let sha256: String
    let byteCount: UInt64
    let relativePath: String
    let released: Bool

    init(
        role: PortableExchangeImmutableByteRoleV2,
        sha256: String,
        byteCount: UInt64,
        relativePath: String,
        released: Bool
    ) throws {
        self.schemaVersion = Self.schemaVersion
        self.role = role
        self.sha256 = sha256
        self.byteCount = byteCount
        self.relativePath = relativePath
        self.released = released
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(sha256),
              byteCount > 0,
              byteCount <= C48PortableReviewPersistenceLimitsV1.maximumImmutableBytes,
              C48PortableReviewPersistenceValidationV1.validRelativePath(relativePath),
              !relativePath.contains("capability"),
              !relativePath.contains("quarantine") else {
            throw PortableExchangePersistenceFailureV2.invalidRecord
        }
    }
}

/// Protected capability material is deliberately a separate type.  It is
/// accepted only by the internal store/backup paths and never participates in
/// portable JSON, reports, search, diagnostics, or SwiftData.
struct PortableExchangeProtectedCapabilityArtifactV2: Codable, Equatable, Sendable {
    static let schemaVersion = 2

    let schemaVersion: Int
    let relativePath: String
    let byteCount: UInt64
    let sha256: String
    let state: PortableExchangeCapabilityStateV2

    init(
        relativePath: String,
        byteCount: UInt64,
        sha256: String,
        state: PortableExchangeCapabilityStateV2
    ) throws {
        self.schemaVersion = Self.schemaVersion
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.sha256 = sha256
        self.state = state
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              C48PortableReviewPersistenceValidationV1.validRelativePath(relativePath),
              relativePath.contains("capability"),
              byteCount == 32,
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(sha256),
              state.isActive else {
            throw PortableExchangePersistenceFailureV2.invalidCapabilityArtifact
        }
    }
}

struct PortableExchangeSessionRecordV2: Codable, Equatable, Sendable {
    static let schemaVersion = 2

    let schemaVersion: Int
    let sessionID: UUID
    let namespace: PortableExchangeSessionNamespaceV2
    let publicRequestID: String
    let revision: Int
    /// Internal-only keys used to scope deletion and invalidation.  These
    /// fields never enter portable request/response bytes or reports.
    var workspaceID: UUID?
    var canonicalReviewIdentity: String?
    var canonicalSubjectIdentity: String?
    /// The released protocol digest is retained only for proof
    /// reconciliation; it is not an identity or a portable payload.
    let protocolReleaseDigest: Data?
    /// Two-plane C14 reconciliation marker.  A pending marker is retained
    /// until the canonical receipt is observed; it prevents a relaunch from
    /// applying the same response twice or claiming an uncommitted effect.
    var pendingMutationID: MutationIDV1?
    var pendingEffectSHA256: String?
    var pendingImportReceiptSHA256: String?
    let createdAt: Date
    var updatedAt: Date
    var state: PortableExchangeSessionStateV2
    var capabilityState: PortableExchangeCapabilityStateV2
    var attemptCount: Int
    var immutableBytes: [PortableExchangeImmutableByteReferenceV2]
    var protectedCapability: PortableExchangeProtectedCapabilityArtifactV2?
    var responseIDs: [String]
    var requestManifestSHA256: String?
    var requestPackageSHA256: String?
    var acceptedResponseSHA256: String?
    var cloneOrForkGenerationID: UUID?
    var escapedCopyAcknowledged: Bool

    init(
        sessionID: UUID,
        namespace: PortableExchangeSessionNamespaceV2,
        publicRequestID: String,
        revision: Int,
        workspaceID: UUID? = nil,
        canonicalReviewIdentity: String? = nil,
        canonicalSubjectIdentity: String? = nil,
        protocolReleaseDigest: Data? = nil,
        pendingMutationID: MutationIDV1? = nil,
        pendingEffectSHA256: String? = nil,
        pendingImportReceiptSHA256: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        state: PortableExchangeSessionStateV2,
        capabilityState: PortableExchangeCapabilityStateV2,
        attemptCount: Int = 0,
        immutableBytes: [PortableExchangeImmutableByteReferenceV2] = [],
        protectedCapability: PortableExchangeProtectedCapabilityArtifactV2? = nil,
        responseIDs: [String] = [],
        requestManifestSHA256: String? = nil,
        requestPackageSHA256: String? = nil,
        acceptedResponseSHA256: String? = nil,
        cloneOrForkGenerationID: UUID? = nil,
        escapedCopyAcknowledged: Bool = false
    ) throws {
        self.schemaVersion = Self.schemaVersion
        self.sessionID = sessionID
        self.namespace = namespace
        self.publicRequestID = publicRequestID
        self.revision = revision
        self.workspaceID = workspaceID
        self.canonicalReviewIdentity = canonicalReviewIdentity
        self.canonicalSubjectIdentity = canonicalSubjectIdentity
        self.protocolReleaseDigest = protocolReleaseDigest
        self.pendingMutationID = pendingMutationID
        self.pendingEffectSHA256 = pendingEffectSHA256
        self.pendingImportReceiptSHA256 = pendingImportReceiptSHA256
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.state = state
        self.capabilityState = capabilityState
        self.attemptCount = attemptCount
        self.immutableBytes = immutableBytes
        self.protectedCapability = protectedCapability
        self.responseIDs = responseIDs
        self.requestManifestSHA256 = requestManifestSHA256
        self.requestPackageSHA256 = requestPackageSHA256
        self.acceptedResponseSHA256 = acceptedResponseSHA256
        self.cloneOrForkGenerationID = cloneOrForkGenerationID
        self.escapedCopyAcknowledged = escapedCopyAcknowledged
        try validate()
    }

    mutating func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              revision > 0,
              attemptCount >= 0,
              attemptCount <= C48PortableReviewPersistenceLimitsV1.maximumAttempts,
              createdAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt >= createdAt,
              C48PortableReviewPersistenceValidationV1.validPublicID(publicRequestID),
              Set(responseIDs).count == responseIDs.count,
              responseIDs.allSatisfy(C48PortableReviewPersistenceValidationV1.validPublicID),
              immutableBytes.filter({ $0.role != .acceptedResponse }).map(\.role).count
                == Set(immutableBytes.filter({ $0.role != .acceptedResponse }).map(\.role)).count,
              immutableBytes.allSatisfy({ (try? $0.validate()) != nil }) else {
            throw PortableExchangePersistenceFailureV2.invalidRecord
        }
        if let canonicalReviewIdentity {
            guard C48PortableReviewPersistenceValidationV1.validInternalIdentity(canonicalReviewIdentity) else {
                throw PortableExchangePersistenceFailureV2.invalidRecord
            }
        }
        if let canonicalSubjectIdentity {
            guard C48PortableReviewPersistenceValidationV1.validInternalIdentity(canonicalSubjectIdentity) else {
                throw PortableExchangePersistenceFailureV2.invalidRecord
            }
        }
        if let protocolReleaseDigest {
            guard protocolReleaseDigest.count == 32 else {
                throw PortableExchangePersistenceFailureV2.invalidRecord
            }
        }
        if let pendingEffectSHA256 {
            guard StoreMigrationCanonicalJSONV1.isLowercaseSHA256(pendingEffectSHA256) else {
                throw PortableExchangePersistenceFailureV2.invalidRecord
            }
        }
        if let pendingImportReceiptSHA256 {
            guard StoreMigrationCanonicalJSONV1.isLowercaseSHA256(pendingImportReceiptSHA256) else {
                throw PortableExchangePersistenceFailureV2.invalidRecord
            }
        }
        if pendingMutationID == nil {
            guard pendingEffectSHA256 == nil, pendingImportReceiptSHA256 == nil else {
                throw PortableExchangePersistenceFailureV2.invalidTransition
            }
        } else {
            guard pendingEffectSHA256 != nil,
                  pendingImportReceiptSHA256 != nil,
                  state == .responsePendingDecision else {
                throw PortableExchangePersistenceFailureV2.invalidTransition
            }
        }
        if let protectedCapability {
            try protectedCapability.validate()
            guard capabilityState.isActive else {
                throw PortableExchangePersistenceFailureV2.invalidCapabilityArtifact
            }
        }
        if capabilityState == .exportedAccepting || capabilityState == .responsePendingDecision {
            guard protectedCapability != nil else {
                throw PortableExchangePersistenceFailureV2.invalidCapabilityArtifact
            }
        }
        if let requestManifestSHA256 {
            guard StoreMigrationCanonicalJSONV1.isLowercaseSHA256(requestManifestSHA256) else {
                throw PortableExchangePersistenceFailureV2.invalidRecord
            }
        }
        if let requestPackageSHA256 {
            guard StoreMigrationCanonicalJSONV1.isLowercaseSHA256(requestPackageSHA256) else {
                throw PortableExchangePersistenceFailureV2.invalidRecord
            }
        }
        if let acceptedResponseSHA256 {
            guard StoreMigrationCanonicalJSONV1.isLowercaseSHA256(acceptedResponseSHA256) else {
                throw PortableExchangePersistenceFailureV2.invalidRecord
            }
        }
        let immutable = state.isImmutableHistory
        if immutable {
            guard capabilityState != .issuedNotExported,
                  capabilityState != .exportedAccepting,
                  capabilityState != .responsePendingDecision else {
                throw PortableExchangePersistenceFailureV2.invalidTransition
            }
        }
        if capabilityState == .historyOnlyClonedOrForked {
            guard cloneOrForkGenerationID != nil else {
                throw PortableExchangePersistenceFailureV2.invalidTransition
            }
        }
        if state == .erased {
            guard capabilityState == .erased, protectedCapability == nil else {
                throw PortableExchangePersistenceFailureV2.invalidTransition
            }
        }
    }

    func validated() throws -> Self {
        var copy = self
        try copy.validate()
        return copy
    }

    func isTerminalImmutable() -> Bool {
        state.isImmutableHistory || capabilityState.isActive == false
    }
}

struct PortableExchangeQuarantineRecordV2: Codable, Equatable, Sendable {
    static let schemaVersion = 2

    let schemaVersion: Int
    let quarantineID: UUID
    let namespace: PortableExchangeSessionNamespaceV2
    let relativePath: String
    let sha256: String
    let byteCount: UInt64
    let reason: String
    let createdAt: Date
    var disposition: PortableExchangeQuarantineDispositionV2

    init(
        quarantineID: UUID,
        namespace: PortableExchangeSessionNamespaceV2,
        relativePath: String,
        sha256: String,
        byteCount: UInt64,
        reason: String,
        createdAt: Date,
        disposition: PortableExchangeQuarantineDispositionV2 = .keptQuarantined
    ) throws {
        self.schemaVersion = Self.schemaVersion
        self.quarantineID = quarantineID
        self.namespace = namespace
        self.relativePath = relativePath
        self.sha256 = sha256
        self.byteCount = byteCount
        self.reason = reason
        self.createdAt = createdAt
        self.disposition = disposition
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              C48PortableReviewPersistenceValidationV1.validRelativePath(relativePath),
              relativePath.contains("quarantine"),
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(sha256),
              byteCount <= C48PortableReviewPersistenceLimitsV1.maximumQuarantineBytes,
              !reason.isEmpty,
              reason.utf8.count <= 512,
              createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw PortableExchangePersistenceFailureV2.invalidQuarantine
        }
    }
}

enum PortableExchangeQuarantineDispositionV2: String, Codable, CaseIterable, Hashable, Sendable {
    case pending = "PENDING"
    case keptQuarantined = "KEPT_QUARANTINED"
    case discarded = "DISCARDED"
    case promotedToHistory = "PROMOTED_TO_HISTORY"
}

struct PortableExchangeNamespaceQuotaV2: Codable, Equatable, Sendable {
    static let schemaVersion = 2

    let schemaVersion: Int
    let maximumSessions: Int
    let maximumStagedBytes: UInt64
    let maximumQuarantineBytes: UInt64
    let maximumAttemptsPerSession: Int

    init(
        maximumSessions: Int,
        maximumStagedBytes: UInt64,
        maximumQuarantineBytes: UInt64,
        maximumAttemptsPerSession: Int
    ) throws {
        self.schemaVersion = Self.schemaVersion
        self.maximumSessions = maximumSessions
        self.maximumStagedBytes = maximumStagedBytes
        self.maximumQuarantineBytes = maximumQuarantineBytes
        self.maximumAttemptsPerSession = maximumAttemptsPerSession
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              maximumSessions > 0,
              maximumSessions <= C48PortableReviewPersistenceLimitsV1.maximumSessions,
              maximumStagedBytes > 0,
              maximumStagedBytes <= C48PortableReviewPersistenceLimitsV1.maximumStagedBytes,
              maximumQuarantineBytes > 0,
              maximumQuarantineBytes <= C48PortableReviewPersistenceLimitsV1.maximumQuarantineBytes,
              maximumAttemptsPerSession > 0,
              maximumAttemptsPerSession <= C48PortableReviewPersistenceLimitsV1.maximumAttempts else {
            throw PortableExchangePersistenceFailureV2.invalidQuota
        }
    }
}

enum C48PortableReviewNamespaceQuotaCatalogV2 {
    static let review = try! PortableExchangeNamespaceQuotaV2(
        maximumSessions: 128,
        maximumStagedBytes: 128 * 1_024 * 1_024,
        maximumQuarantineBytes: 64 * 1_024 * 1_024,
        maximumAttemptsPerSession: 32
    )
    static let serviceRequest = try! PortableExchangeNamespaceQuotaV2(
        maximumSessions: 128,
        maximumStagedBytes: 128 * 1_024 * 1_024,
        maximumQuarantineBytes: 64 * 1_024 * 1_024,
        maximumAttemptsPerSession: 32
    )

    static func quota(for namespace: PortableExchangeSessionNamespaceV2) -> PortableExchangeNamespaceQuotaV2 {
        switch namespace {
        case .review: return review
        case .serviceRequest: return serviceRequest
        }
    }
}

struct PortableExchangeSessionEnvelopeV2: Codable, Equatable, Sendable {
    static let schemaVersion = 2

    let schemaVersion: Int
    let generationID: UUID
    let updatedAt: Date
    var sessions: [PortableExchangeSessionRecordV2]
    var quarantine: [PortableExchangeQuarantineRecordV2]

    init(
        generationID: UUID = UUID(),
        updatedAt: Date,
        sessions: [PortableExchangeSessionRecordV2] = [],
        quarantine: [PortableExchangeQuarantineRecordV2] = []
    ) throws {
        self.schemaVersion = Self.schemaVersion
        self.generationID = generationID
        self.updatedAt = updatedAt
        self.sessions = sessions
        self.quarantine = quarantine
        try validate()
    }

    mutating func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              updatedAt.timeIntervalSinceReferenceDate.isFinite,
              Set(sessions.map(\.sessionID)).count == sessions.count,
              Set(sessions.map { "\($0.namespace.rawValue):\($0.publicRequestID)" }).count == sessions.count,
              Set(quarantine.map(\.quarantineID)).count == quarantine.count else {
            throw PortableExchangePersistenceFailureV2.invalidEnvelope
        }
        for index in sessions.indices {
            sessions[index] = try sessions[index].validated()
        }
        try quarantine.forEach { try $0.validate() }
        for namespace in PortableExchangeSessionNamespaceV2.allCases {
            let values = sessions.filter { $0.namespace == namespace }
            let quota = C48PortableReviewNamespaceQuotaCatalogV2.quota(for: namespace)
            guard values.count <= quota.maximumSessions,
                  values.reduce(UInt64(0), { $0 + $1.immutableBytes.reduce(0) { $0 + $1.byteCount } }) <= quota.maximumStagedBytes,
                  quarantine.filter({ $0.namespace == namespace }).reduce(UInt64(0), { $0 + $1.byteCount }) <= quota.maximumQuarantineBytes else {
                throw PortableExchangePersistenceFailureV2.quotaExceeded
            }
        }
    }

    func validated() throws -> Self {
        var copy = self
        try copy.validate()
        return copy
    }

    func canonicalSorted() throws -> Self {
        var copy = self
        copy.sessions.sort {
            ($0.namespace.rawValue, $0.publicRequestID, $0.revision) <
                ($1.namespace.rawValue, $1.publicRequestID, $1.revision)
        }
        copy.quarantine.sort { $0.quarantineID.uuidString < $1.quarantineID.uuidString }
        try copy.validate()
        return copy
    }
}

/// V1 is intentionally a permissive wire container.  The migration code
/// validates every promoted V2 record before publishing, so unknown V1 bytes
/// cannot silently become canonical state or lose their exact paths.
struct PortableExchangeSessionEnvelopeV1: Codable, Equatable, Sendable {
    let storeVersion: Int
    let generationID: UUID
    let updatedAt: Date
    let sessions: [PortableExchangeSessionRecordV2]
    let quarantine: [PortableExchangeQuarantineRecordV2]

    init(
        generationID: UUID,
        updatedAt: Date,
        sessions: [PortableExchangeSessionRecordV2],
        quarantine: [PortableExchangeQuarantineRecordV2]
    ) {
        storeVersion = 1
        self.generationID = generationID
        self.updatedAt = updatedAt
        self.sessions = sessions
        self.quarantine = quarantine
    }
}

struct PortableExchangeSessionMigrationReceiptV2: Codable, Equatable, Sendable {
    static let schemaVersion = 2

    let schemaVersion: Int
    let sourceVersion: Int
    let targetVersion: Int
    let sourceSHA256: String
    let resultSHA256: String
    let preservedSessionCount: Int
    let preservedImmutableByteCount: UInt64
    let idempotent: Bool
    let requiresForwardRepair: Bool

    init(
        sourceVersion: Int = 1,
        targetVersion: Int = 2,
        sourceSHA256: String,
        resultSHA256: String,
        preservedSessionCount: Int,
        preservedImmutableByteCount: UInt64,
        requiresForwardRepair: Bool = false
    ) throws {
        self.schemaVersion = Self.schemaVersion
        self.sourceVersion = sourceVersion
        self.targetVersion = targetVersion
        self.sourceSHA256 = sourceSHA256
        self.resultSHA256 = resultSHA256
        self.preservedSessionCount = preservedSessionCount
        self.preservedImmutableByteCount = preservedImmutableByteCount
        idempotent = true
        self.requiresForwardRepair = requiresForwardRepair
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              sourceVersion == 1,
              targetVersion == 2,
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(sourceSHA256),
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(resultSHA256),
              preservedSessionCount >= 0,
              preservedImmutableByteCount <= C48PortableReviewPersistenceLimitsV1.maximumStagedBytes,
              idempotent,
              !requiresForwardRepair else {
            throw PortableExchangePersistenceFailureV2.invalidMigrationReceipt
        }
    }
}

enum PortableExchangeJournalPhaseV2: String, Codable, CaseIterable, Hashable, Sendable {
    case prepared = "PREPARED"
    case committed = "COMMITTED"
    case rolledBack = "ROLLED_BACK"
}

enum PortableExchangeJournalOperationV2: String, Codable, CaseIterable, Hashable, Sendable {
    case stage = "STAGE"
    case accept = "ACCEPT"
    case restore = "REPLACE_RESTORE"
    case cloneOrFork = "CLONE_OR_FORK"
    case erase = "ERASE"
    case purge = "PURGE"
    case migrate = "MIGRATE"
}

struct PortableExchangeJournalEntryV2: Codable, Equatable, Sendable {
    static let schemaVersion = 2

    let schemaVersion: Int
    let operationID: UUID
    let operation: PortableExchangeJournalOperationV2
    let namespace: PortableExchangeSessionNamespaceV2?
    let sessionID: UUID?
    let beforeSHA256: String
    let afterSHA256: String
    var phase: PortableExchangeJournalPhaseV2
    let createdAt: Date

    init(
        operationID: UUID,
        operation: PortableExchangeJournalOperationV2,
        namespace: PortableExchangeSessionNamespaceV2?,
        sessionID: UUID?,
        beforeSHA256: String,
        afterSHA256: String,
        phase: PortableExchangeJournalPhaseV2,
        createdAt: Date
    ) throws {
        self.schemaVersion = Self.schemaVersion
        self.operationID = operationID
        self.operation = operation
        self.namespace = namespace
        self.sessionID = sessionID
        self.beforeSHA256 = beforeSHA256
        self.afterSHA256 = afterSHA256
        self.phase = phase
        self.createdAt = createdAt
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(beforeSHA256),
              StoreMigrationCanonicalJSONV1.isLowercaseSHA256(afterSHA256),
              createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw PortableExchangePersistenceFailureV2.invalidJournal
        }
        if operation == .migrate {
            guard namespace == nil, sessionID == nil else {
                throw PortableExchangePersistenceFailureV2.invalidJournal
            }
        }
    }
}

struct PortableExchangeBackupSnapshotV2: Codable, Equatable, Sendable {
    static let schemaVersion = 2

    let schemaVersion: Int
    let snapshotID: UUID
    let createdAt: Date
    let sessions: [PortableExchangeSessionRecordV2]
    let immutablePayloads: [PortableExchangeImmutablePayloadV2]
    let protectedCapabilityArtifacts: [PortableExchangeProtectedCapabilityBackupV2]

    init(
        snapshotID: UUID = UUID(),
        createdAt: Date,
        sessions: [PortableExchangeSessionRecordV2],
        immutablePayloads: [PortableExchangeImmutablePayloadV2] = [],
        protectedCapabilityArtifacts: [PortableExchangeProtectedCapabilityBackupV2] = []
    ) throws {
        self.schemaVersion = Self.schemaVersion
        self.snapshotID = snapshotID
        self.createdAt = createdAt
        self.sessions = sessions
        self.immutablePayloads = immutablePayloads
        self.protectedCapabilityArtifacts = protectedCapabilityArtifacts
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              createdAt.timeIntervalSinceReferenceDate.isFinite,
              Set(sessions.map(\.sessionID)).count == sessions.count,
              sessions.allSatisfy({ (try? $0.validated()) != nil }),
              immutablePayloads.allSatisfy({ (try? $0.validate()) != nil }),
              protectedCapabilityArtifacts.allSatisfy({ (try? $0.validate()) != nil }) else {
            throw PortableExchangePersistenceFailureV2.invalidBackupSnapshot
        }
        guard sessions.allSatisfy({ $0.state != .quarantined && $0.state != .erased }) else {
            throw PortableExchangePersistenceFailureV2.invalidBackupSnapshot
        }
    }
}

struct PortableExchangeImmutablePayloadV2: Codable, Equatable, Sendable {
    static let schemaVersion = 2

    let schemaVersion: Int
    let role: PortableExchangeImmutableByteRoleV2
    let sha256: String
    let bytes: Data

    init(role: PortableExchangeImmutableByteRoleV2, bytes: Data) throws {
        self.schemaVersion = Self.schemaVersion
        self.role = role
        self.sha256 = StoreMigrationCanonicalJSONV1.sha256(bytes)
        self.bytes = bytes
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              !bytes.isEmpty,
              bytes.count <= C48PortableReviewPersistenceLimitsV1.maximumImmutableBytes,
              StoreMigrationCanonicalJSONV1.sha256(bytes) == sha256 else {
            throw PortableExchangePersistenceFailureV2.invalidPayload
        }
    }
}

struct PortableExchangeProtectedCapabilityBackupV2: Codable, Equatable, Sendable {
    static let schemaVersion = 2

    let schemaVersion: Int
    let sessionID: UUID
    let bytes: Data
    let sha256: String
    let state: PortableExchangeCapabilityStateV2

    init(sessionID: UUID, bytes: Data, state: PortableExchangeCapabilityStateV2) throws {
        self.schemaVersion = Self.schemaVersion
        self.sessionID = sessionID
        self.bytes = bytes
        self.sha256 = StoreMigrationCanonicalJSONV1.sha256(bytes)
        self.state = state
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              bytes.count == 32,
              StoreMigrationCanonicalJSONV1.sha256(bytes) == sha256,
              state.isActive else {
            throw PortableExchangePersistenceFailureV2.invalidCapabilityArtifact
        }
    }
}

struct PortableExchangeRestoreReceiptV2: Codable, Equatable, Sendable {
    static let schemaVersion = 2

    let schemaVersion: Int
    let operationID: UUID
    let snapshotID: UUID
    let restoredSessionCount: Int
    let preservedImmutableByteCount: UInt64
    let activeCapabilitiesPreserved: Int
    let quarantineExcluded: Bool
    let idempotent: Bool
    let completedAt: Date

    init(
        operationID: UUID,
        snapshotID: UUID,
        restoredSessionCount: Int,
        preservedImmutableByteCount: UInt64,
        activeCapabilitiesPreserved: Int,
        completedAt: Date
    ) throws {
        self.schemaVersion = Self.schemaVersion
        self.operationID = operationID
        self.snapshotID = snapshotID
        self.restoredSessionCount = restoredSessionCount
        self.preservedImmutableByteCount = preservedImmutableByteCount
        self.activeCapabilitiesPreserved = activeCapabilitiesPreserved
        quarantineExcluded = true
        idempotent = true
        self.completedAt = completedAt
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              restoredSessionCount >= 0,
              preservedImmutableByteCount <= C48PortableReviewPersistenceLimitsV1.maximumStagedBytes,
              activeCapabilitiesPreserved >= 0,
              quarantineExcluded,
              idempotent,
              completedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw PortableExchangePersistenceFailureV2.invalidRestoreReceipt
        }
    }
}

struct PortableExchangeCloneForkReceiptV2: Codable, Equatable, Sendable {
    static let schemaVersion = 2

    let schemaVersion: Int
    let operationID: UUID
    let sourceGenerationID: UUID
    let resultGenerationID: UUID
    let invalidatedSessionCount: Int
    let preservedHistoryCount: Int
    let activeCapabilitiesInvalidated: Bool
    let completedAt: Date

    init(
        operationID: UUID,
        sourceGenerationID: UUID,
        resultGenerationID: UUID,
        invalidatedSessionCount: Int,
        preservedHistoryCount: Int,
        completedAt: Date
    ) throws {
        self.schemaVersion = Self.schemaVersion
        self.operationID = operationID
        self.sourceGenerationID = sourceGenerationID
        self.resultGenerationID = resultGenerationID
        self.invalidatedSessionCount = invalidatedSessionCount
        self.preservedHistoryCount = preservedHistoryCount
        activeCapabilitiesInvalidated = true
        self.completedAt = completedAt
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              invalidatedSessionCount >= 0,
              preservedHistoryCount >= invalidatedSessionCount,
              activeCapabilitiesInvalidated,
              completedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw PortableExchangePersistenceFailureV2.invalidCloneForkReceipt
        }
    }
}

struct PortableExchangeEraseReceiptV2: Codable, Equatable, Sendable {
    static let schemaVersion = 2

    let schemaVersion: Int
    let operationID: UUID
    let erasedSessionCount: Int
    let erasedQuarantineCount: Int
    let erasedCapabilityCount: Int
    let escapedCopiesAcknowledged: Int
    let appOwnedBytesRemoved: UInt64
    let completedAt: Date

    init(
        operationID: UUID,
        erasedSessionCount: Int,
        erasedQuarantineCount: Int,
        erasedCapabilityCount: Int,
        escapedCopiesAcknowledged: Int,
        appOwnedBytesRemoved: UInt64,
        completedAt: Date
    ) throws {
        self.schemaVersion = Self.schemaVersion
        self.operationID = operationID
        self.erasedSessionCount = erasedSessionCount
        self.erasedQuarantineCount = erasedQuarantineCount
        self.erasedCapabilityCount = erasedCapabilityCount
        self.escapedCopiesAcknowledged = escapedCopiesAcknowledged
        self.appOwnedBytesRemoved = appOwnedBytesRemoved
        self.completedAt = completedAt
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              erasedSessionCount >= 0,
              erasedQuarantineCount >= 0,
              erasedCapabilityCount >= 0,
              escapedCopiesAcknowledged >= 0,
              completedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw PortableExchangePersistenceFailureV2.invalidEraseReceipt
        }
    }
}

enum PortableExchangePersistenceFailureV2: Error, Equatable, Sendable {
    case invalidRoot
    case invalidRecord
    case invalidEnvelope
    case invalidQuarantine
    case invalidQuota
    case quotaExceeded
    case invalidCapabilityArtifact
    case invalidPayload
    case invalidJournal
    case invalidMigrationReceipt
    case invalidBackupSnapshot
    case invalidRestoreReceipt
    case invalidCloneForkReceipt
    case invalidEraseReceipt
    case unsupportedSchemaVersion
    case corruptStore
    case protectedDataUnavailable
    case storageUnavailable
    case writeFailed
    case cleanupFailed
    case sessionNotFound
    case duplicateSession
    case invalidTransition
    case staleGeneration
    case escapedFileCannotBeRecalled
}

enum C48PortableReviewPersistenceLimitsV1 {
    static let maximumSessions = 256
    static let maximumStagedBytes: UInt64 = 256 * 1_024 * 1_024
    static let maximumQuarantineBytes: UInt64 = 128 * 1_024 * 1_024
    static let maximumImmutableBytes: UInt64 = 128 * 1_024 * 1_024
    static let maximumAttempts = 64
    static let maximumEnvelopeBytes = 4 * 1_024 * 1_024
}

enum C48PortableReviewPersistenceValidationV1 {
    static func validRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.utf8.count <= 512,
              !value.hasPrefix("/"),
              !value.hasPrefix("\\"),
              !value.contains("\\") else { return false }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        return !parts.isEmpty && parts.allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".." &&
                !$0.contains(":") && !$0.contains("\0")
        }
    }

    static func validPublicID(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else { return false }
        return value.unicodeScalars.allSatisfy {
            ($0.value >= 0x30 && $0.value <= 0x39) ||
            ($0.value >= 0x41 && $0.value <= 0x5a) ||
            ($0.value >= 0x61 && $0.value <= 0x7a) ||
            $0.value == 0x2d || $0.value == 0x5f
        }
    }

    static func validInternalIdentity(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 &&
            !value.unicodeScalars.contains(where: { $0.value == 0 })
    }
}

/// C49 keeps accepted work-resource facts in the durable append-only schema;
/// this C48 exchange/session file remains protected, operation-scoped staging
/// and is never promoted to a second SwiftData truth source.
enum C49WorkResourcePortableReviewBoundaryV1 {
    static let acceptedWorkResourceFactsUseDurableRow = true
    static let exchangeSessionsRemainNonPersistent = true
    static let exchangeBytesAreNotWorkResourceTruth = true
    static let persistentSchemaVersion = C49WorkResourcePersistenceBoundaryV1.persistentSchemaVersion
    static let recordsSchemaVersion = C49WorkResourcePersistenceBoundaryV1.recordsSchemaVersion
    static let durableRows = C49WorkResourcePersistenceBoundaryV1.newlyEnrolledRows

    static func validate() throws {
        guard acceptedWorkResourceFactsUseDurableRow,
              exchangeSessionsRemainNonPersistent,
              exchangeBytesAreNotWorkResourceTruth,
              durableRows == ["ManualWorkResourceRecordRow"] else {
            throw PortableExchangePersistenceFailureV2.invalidEnvelope
        }
        try C49WorkResourcePersistenceBoundaryV1.validate()
    }
}

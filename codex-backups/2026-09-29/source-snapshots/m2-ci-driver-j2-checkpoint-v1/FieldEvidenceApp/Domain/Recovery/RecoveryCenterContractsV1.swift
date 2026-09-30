import CryptoKit
import Foundation

enum RecoveryCenterContractFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case unsupportedVersion
    case invalidDigest
    case duplicateSource
    case duplicateFailure
    case inconsistentProjection
    case privacyViolation
}

enum RecoveryCenterStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case healthy = "HEALTHY"
    case checking = "CHECKING"
    case actionable = "ACTIONABLE"
    case inProgress = "IN_PROGRESS"
    case interrupted = "INTERRUPTED"
    case fileRequired = "FILE_REQUIRED"
    case validationFailed = "VALIDATION_FAILED"
    case partialSafe = "PARTIAL_SAFE"
    case complete = "COMPLETE"
    case restartRequired = "RESTART_REQUIRED"
    case externalActionRequired = "EXTERNAL_ACTION_REQUIRED"
}

enum RecoveryAuthoritySourceV1: String, CaseIterable, Codable, Hashable, Sendable {
    case backup = "BACKUP"
    case restore = "RESTORE"
    case generation = "GENERATION"
    case finalization = "FINALIZATION"
    case reporting = "REPORTING"
    case storage = "STORAGE"
    case protectedData = "PROTECTED_DATA"
    case jobs = "JOBS"
    case packageReadiness = "PACKAGE_READINESS"
    case commerce = "COMMERCE"
    case diagnostics = "DIAGNOSTICS"
}

enum RecoverySourceFreshnessV1: String, CaseIterable, Codable, Hashable, Sendable {
    case current = "CURRENT"
    case historic = "HISTORIC"
    case unavailable = "UNAVAILABLE"
}

/// Privacy-safe, rebuildable input from one incumbent authority. It contains
/// no workspace, customer, entity, file, content, location, or secret data.
struct RecoveryAuthoritySnapshotV1: Encodable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let source: RecoveryAuthoritySourceV1
    let state: RecoveryCenterStateV1
    let frontierRevision: UInt64?
    let frontierSHA256: String?
    let freshness: RecoverySourceFreshnessV1
    let observedUptimeNanoseconds: UInt64

    init(
        source: RecoveryAuthoritySourceV1,
        state: RecoveryCenterStateV1,
        frontierRevision: UInt64? = nil,
        frontierSHA256: String? = nil,
        freshness: RecoverySourceFreshnessV1,
        observedUptimeNanoseconds: UInt64
    ) throws {
        schemaVersion = Self.schemaVersion
        self.source = source
        self.state = state
        self.frontierRevision = frontierRevision
        self.frontierSHA256 = frontierSHA256
        self.freshness = freshness
        self.observedUptimeNanoseconds = observedUptimeNanoseconds
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw RecoveryCenterContractFailureV1.unsupportedVersion
        }
        guard (frontierRevision == nil) == (frontierSHA256 == nil),
              frontierRevision.map { $0 > 0 } ?? true,
              frontierSHA256.map(RecoveryCenterValidationV1.isSHA256) ?? true,
              observedUptimeNanoseconds > 0 else {
            throw RecoveryCenterContractFailureV1.invalidValue
        }
    }
}

/// A failure's presentation is derived from the single incumbent operational
/// registry. Callers cannot substitute a second owner or action mapping.
struct RecoveryFailurePresentationV1: Equatable, Sendable {
    let code: OperationalFailureCodeV1
    let owner: OperationalOwnerV1
    let primaryAction: OperationalActionV1
    let fallbackAction: OperationalActionV1?
    let helpTopic: OperationalHelpTopicV1?

    init(failure: OperationalFailureV1) throws {
        try failure.validate()
        code = failure.descriptor.code
        owner = failure.descriptor.owner
        primaryAction = failure.descriptor.primaryAction
        fallbackAction = failure.descriptor.fallbackAction
        helpTopic = failure.descriptor.helpTopic
        try validate()
    }

    func validate() throws {
        let descriptor = try OperationalFailureRegistryV1.descriptor(for: code)
        guard owner == descriptor.owner,
              primaryAction == descriptor.primaryAction,
              fallbackAction == descriptor.fallbackAction,
              helpTopic == descriptor.helpTopic else {
            throw RecoveryCenterContractFailureV1.inconsistentProjection
        }
    }
}

struct ReliabilityStateProjectionV1: Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumSourceCount = RecoveryAuthoritySourceV1.allCases.count
    static let maximumFailureCount = OperationalFailureCodeV1.allCases.count

    let schemaVersion: Int
    let state: RecoveryCenterStateV1
    let sources: [RecoveryAuthoritySnapshotV1]
    let failures: [RecoveryFailurePresentationV1]
    let observedUptimeNanoseconds: UInt64
    let sourceSetSHA256: String

    static let statePrecedence: [RecoveryCenterStateV1] = [
        .validationFailed, .fileRequired, .partialSafe, .restartRequired,
        .externalActionRequired, .interrupted, .actionable, .inProgress,
        .checking, .complete, .healthy,
    ]

    init(
        sources: [RecoveryAuthoritySnapshotV1],
        operationalFailures: [OperationalFailureV1],
        observedUptimeNanoseconds: UInt64
    ) throws {
        let orderedSources = sources.sorted { $0.source.rawValue < $1.source.rawValue }
        let orderedFailures = try operationalFailures
            .map(RecoveryFailurePresentationV1.init(failure:))
            .sorted { $0.code.rawValue < $1.code.rawValue }
        schemaVersion = Self.schemaVersion
        state = Self.deriveState(sources: orderedSources, failures: orderedFailures)
        self.sources = orderedSources
        failures = orderedFailures
        self.observedUptimeNanoseconds = observedUptimeNanoseconds
        sourceSetSHA256 = try RecoveryCenterCanonicalV1.sha256(orderedSources)
        try validate()
    }

    func validate() throws {
        try sources.forEach { try $0.validate() }
        try failures.forEach { try $0.validate() }
        guard schemaVersion == Self.schemaVersion,
              sources.count <= Self.maximumSourceCount,
              failures.count <= Self.maximumFailureCount,
              sources == sources.sorted(by: { $0.source.rawValue < $1.source.rawValue }),
              failures == failures.sorted(by: { $0.code.rawValue < $1.code.rawValue }),
              Set(sources.map(\.source)).count == sources.count,
              Set(failures.map(\.code)).count == failures.count,
              observedUptimeNanoseconds > 0,
              state == Self.deriveState(sources: sources, failures: failures),
              sourceSetSHA256 == (try RecoveryCenterCanonicalV1.sha256(sources)) else {
            throw RecoveryCenterContractFailureV1.inconsistentProjection
        }
    }

    static func deriveState(
        sources: [RecoveryAuthoritySnapshotV1],
        failures: [RecoveryFailurePresentationV1]
    ) -> RecoveryCenterStateV1 {
        guard sources.count == RecoveryAuthoritySourceV1.allCases.count,
              Set(sources.map(\.source)) == Set(RecoveryAuthoritySourceV1.allCases) else {
            return .validationFailed
        }
        var states = Set(sources.map(\.state))
        if !failures.isEmpty { states.insert(.actionable) }
        if sources.contains(where: { $0.freshness == .unavailable }) {
            states.insert(.validationFailed)
        } else if sources.contains(where: { $0.freshness == .historic }) {
            states.insert(.actionable)
        }
        if let selected = statePrecedence.dropLast().first(where: states.contains) {
            return selected
        }
        return .healthy
    }
}

struct RecoveryRouteV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID

    var target: NavigationTargetV1 {
        get throws {
            let recoveryFallback = try NavigationFallbackV1(
                root: .reports,
                destination: .recoveryCenter
            )
            let value = try NavigationTargetV1(
                workspaceID: workspaceID,
                destination: .recoveryCenter,
                requestedMode: .read,
                fallback: recoveryFallback
            )
            try value.validate()
            return value
        }
    }

    func validate(using registry: RouteRegistryV1) throws {
        let value = try target
        let descriptors = registry.descriptors.filter {
            $0.destination == .recoveryCenter
        }
        guard value.destination == .recoveryCenter,
              value.workspaceID == workspaceID,
              descriptors.count == 1,
              descriptors[0].root == .reports,
              descriptors[0].packageID == nil else {
            throw RecoveryCenterContractFailureV1.inconsistentProjection
        }
    }
}

enum EncryptedBackupAvailabilityStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case available = "AVAILABLE"
    case unavailable = "UNAVAILABLE"
}

/// Optional C54 capability truth. Its state is never included in ordinary
/// recovery state derivation and therefore cannot gate clear backup/restore.
struct EncryptedBackupAvailabilityV1: Equatable, Sendable {
    let state: EncryptedBackupAvailabilityStateV1
    let reason: FeatureAvailabilityReasonV1
    let receipt: TypedAvailabilityAndFallbackReceiptV1

    init(receipt: TypedAvailabilityAndFallbackReceiptV1) throws {
        try receipt.validate()
        guard receipt.capabilityID == .encryptedBackup,
              receipt.mandatoryCoreComplete,
              receipt.zeroUnsupportedPublicClaim else {
            throw RecoveryCenterContractFailureV1.inconsistentProjection
        }
        self.receipt = receipt
        reason = receipt.availabilityReason
        state = reason == .available ? .available : .unavailable
    }

    func validate() throws {
        try receipt.validate()
        guard receipt.capabilityID == .encryptedBackup,
              state == (reason == .available ? .available : .unavailable),
              reason == receipt.availabilityReason,
              receipt.mandatoryCoreComplete,
              receipt.zeroUnsupportedPublicClaim else {
            throw RecoveryCenterContractFailureV1.inconsistentProjection
        }
    }
}

struct SupportExportPreviewProjectionV1: Equatable, Sendable {
    let mode: SupportBundleModeV1
    let entries: [SupportBundleManifestEntryV1]
    let totalCanonicalByteCount: Int
    let containsCustomerContent: Bool
    let containsCustomerIdentifier: Bool
    let containsRawLogs: Bool
    let permitsAutomaticUpload: Bool

    init(manifest: SupportBundleManifestV1) throws {
        try manifest.validate()
        mode = manifest.mode
        entries = manifest.entries
        totalCanonicalByteCount = manifest.totalCanonicalByteCount
        containsCustomerContent = manifest.containsCustomerContent
        containsCustomerIdentifier = manifest.containsCustomerIdentifier
        containsRawLogs = manifest.containsRawLogs
        permitsAutomaticUpload = manifest.permitsAutomaticUpload
        try validate()
    }

    func validate() throws {
        try entries.forEach { try $0.validate() }
        let total = entries.reduce(0) { partial, entry in
            let (sum, overflow) = partial.addingReportingOverflow(entry.byteCount)
            return overflow ? Int.max : sum
        }
        guard !entries.isEmpty,
              entries.count <= SupportBundleManifestV1.maximumMemberCount,
              entries.map(\.kind).allSatisfy(SupportBundleManifestV1.allowedMembers(for: mode).contains),
              Set(entries.map(\.kind)).count == entries.count,
              total == totalCanonicalByteCount,
              totalCanonicalByteCount <= SupportBundleManifestV1.maximumCanonicalBytes,
              !containsCustomerContent,
              !containsCustomerIdentifier,
              !containsRawLogs,
              !permitsAutomaticUpload else {
            throw RecoveryCenterContractFailureV1.privacyViolation
        }
    }
}

enum PrivacyPolicyReleaseStatusV1: String, CaseIterable, Codable, Hashable, Sendable {
    case draftLocal = "DRAFT_LOCAL"
    case liveMatched = "LIVE_MATCHED"
    case blocked = "BLOCKED"
}

enum PrivacyPolicyBlockReasonV1: String, CaseIterable, Codable, Hashable, Sendable {
    case missingLiveRelease = "MISSING_LIVE_RELEASE"
    case releaseDigestMismatch = "RELEASE_DIGEST_MISMATCH"
    case invalidLiveURL = "INVALID_LIVE_URL"
    case closureUnavailable = "CLOSURE_UNAVAILABLE"
}

/// Read-only status supplied by the P00-C06 policy owner. It does not define,
/// copy, or fabricate policy text.
struct PrivacyPolicyStatusSnapshotV1: Equatable, Sendable {
    let status: PrivacyPolicyReleaseStatusV1
    let expectedReleaseSHA256: String
    let observedReleaseSHA256: String?
    let bundledSummaryLocalizationKey: String?
    let livePolicyURL: URL?
    let blockerReason: PrivacyPolicyBlockReasonV1?

    init(
        status: PrivacyPolicyReleaseStatusV1,
        expectedReleaseSHA256: String,
        observedReleaseSHA256: String?,
        bundledSummaryLocalizationKey: String?,
        livePolicyURL: URL?,
        blockerReason: PrivacyPolicyBlockReasonV1? = nil
    ) throws {
        self.status = status
        self.expectedReleaseSHA256 = expectedReleaseSHA256
        self.observedReleaseSHA256 = observedReleaseSHA256
        self.bundledSummaryLocalizationKey = bundledSummaryLocalizationKey
        self.livePolicyURL = livePolicyURL
        self.blockerReason = blockerReason
        try validate()
    }

    func validate() throws {
        guard RecoveryCenterValidationV1.isSHA256(expectedReleaseSHA256),
              observedReleaseSHA256.map(RecoveryCenterValidationV1.isSHA256) ?? true,
              bundledSummaryLocalizationKey.map({
                  RecoveryCenterValidationV1.validToken($0, maximumBytes: 160)
              }) ?? true else {
            throw RecoveryCenterContractFailureV1.invalidValue
        }
        switch status {
        case .liveMatched:
            guard observedReleaseSHA256 == expectedReleaseSHA256,
                  bundledSummaryLocalizationKey != nil,
                  livePolicyURL?.scheme?.lowercased() == "https",
                  livePolicyURL?.host?.isEmpty == false,
                  blockerReason == nil else {
                throw RecoveryCenterContractFailureV1.inconsistentProjection
            }
        case .draftLocal:
            guard observedReleaseSHA256 == nil,
                  livePolicyURL == nil,
                  bundledSummaryLocalizationKey != nil,
                  blockerReason == nil else {
                throw RecoveryCenterContractFailureV1.inconsistentProjection
            }
        case .blocked:
            guard let blockerReason else {
                throw RecoveryCenterContractFailureV1.inconsistentProjection
            }
            if blockerReason == .releaseDigestMismatch {
                guard let observedReleaseSHA256,
                      observedReleaseSHA256 != expectedReleaseSHA256 else {
                    throw RecoveryCenterContractFailureV1.inconsistentProjection
                }
            }
        }
    }
}

struct PrivacyDataProjectionV1: Equatable, Sendable {
    let policy: PrivacyPolicyStatusSnapshotV1
    let backupRouteVisible: Bool
    let deleteRouteVisible: Bool
    let eraseRouteVisible: Bool
    let permissionRevocationRouteVisible: Bool
    let isReady: Bool

    init(
        policy: PrivacyPolicyStatusSnapshotV1,
        backupRouteVisible: Bool,
        deleteRouteVisible: Bool,
        eraseRouteVisible: Bool,
        permissionRevocationRouteVisible: Bool
    ) throws {
        self.policy = policy
        self.backupRouteVisible = backupRouteVisible
        self.deleteRouteVisible = deleteRouteVisible
        self.eraseRouteVisible = eraseRouteVisible
        self.permissionRevocationRouteVisible = permissionRevocationRouteVisible
        isReady = policy.status == .liveMatched
        try validate()
    }

    func validate() throws {
        try policy.validate()
        guard isReady == (policy.status == .liveMatched),
              backupRouteVisible,
              deleteRouteVisible,
              eraseRouteVisible,
              permissionRevocationRouteVisible else {
            throw RecoveryCenterContractFailureV1.inconsistentProjection
        }
    }
}

struct RecoveryCenterProjectionV1: Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let state: RecoveryCenterStateV1
    let reliability: ReliabilityStateProjectionV1
    let encryptedBackup: EncryptedBackupAvailabilityV1
    let supportExportPreview: SupportExportPreviewProjectionV1?
    let privacyData: PrivacyDataProjectionV1
    let observedUptimeNanoseconds: UInt64

    init(
        reliability: ReliabilityStateProjectionV1,
        encryptedBackup: EncryptedBackupAvailabilityV1,
        supportExportPreview: SupportExportPreviewProjectionV1?,
        privacyData: PrivacyDataProjectionV1,
        observedUptimeNanoseconds: UInt64
    ) throws {
        schemaVersion = Self.schemaVersion
        state = reliability.state
        self.reliability = reliability
        self.encryptedBackup = encryptedBackup
        self.supportExportPreview = supportExportPreview
        self.privacyData = privacyData
        self.observedUptimeNanoseconds = observedUptimeNanoseconds
        try validate()
    }

    func validate() throws {
        try reliability.validate()
        try encryptedBackup.validate()
        try supportExportPreview?.validate()
        try privacyData.validate()
        guard schemaVersion == Self.schemaVersion,
              state == reliability.state,
              observedUptimeNanoseconds >= reliability.observedUptimeNanoseconds else {
            throw RecoveryCenterContractFailureV1.inconsistentProjection
        }
    }
}

/// Injected monotonic presentation time. It cannot issue wall-clock dates,
/// identifiers, revisions, or causal ordering.
protocol PresentationClockV1: Sendable {
    func monotonicNowNanoseconds() -> UInt64
}

struct FixedPresentationClockV1: PresentationClockV1, Equatable, Sendable {
    let nanoseconds: UInt64

    init(nanoseconds: UInt64) throws {
        guard nanoseconds > 0 else { throw RecoveryCenterContractFailureV1.invalidValue }
        self.nanoseconds = nanoseconds
    }

    func monotonicNowNanoseconds() -> UInt64 { nanoseconds }
}

enum SupportFeedbackCategoryV1: String, CaseIterable, Codable, Hashable, Sendable {
    case recovery = "RECOVERY"
    case backup = "BACKUP"
    case diagnostics = "DIAGNOSTICS"
    case privacyAndData = "PRIVACY_AND_DATA"
    case other = "OTHER"
}

enum SupportFeedbackContactChoiceV1: String, CaseIterable, Codable, Hashable, Sendable {
    case noContact = "NO_CONTACT"
    case includeEmail = "INCLUDE_EMAIL"
    case includePhone = "INCLUDE_PHONE"
}

struct SupportBundleAttachmentReferenceV1: Codable, Equatable, Sendable {
    let bundleID: UUID
    let canonicalSHA256: String
    let byteCount: Int
    let expiresAt: Date

    init(bundleID: UUID, canonicalSHA256: String, byteCount: Int, expiresAt: Date) throws {
        self.bundleID = bundleID
        self.canonicalSHA256 = canonicalSHA256
        self.byteCount = byteCount
        self.expiresAt = expiresAt
        try validate()
    }

    func validate() throws {
        guard bundleID != RecoveryCenterValidationV1.zeroUUID,
              RecoveryCenterValidationV1.isSHA256(canonicalSHA256),
              byteCount > 0,
              byteCount <= SupportBundleManifestV1.maximumCanonicalBytes,
              expiresAt.timeIntervalSinceReferenceDate.isFinite else {
            throw RecoveryCenterContractFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case bundleID, canonicalSHA256, byteCount, expiresAt
    }

    init(from decoder: Decoder) throws {
        try RecoveryCenterValidationV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            bundleID: values.decode(UUID.self, forKey: .bundleID),
            canonicalSHA256: values.decode(String.self, forKey: .canonicalSHA256),
            byteCount: values.decode(Int.self, forKey: .byteCount),
            expiresAt: values.decode(Date.self, forKey: .expiresAt)
        )
    }
}

struct SupportFeedbackDraftV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumMessageBytes = 4_096

    let schemaVersion: Int
    let draftID: UUID
    let category: SupportFeedbackCategoryV1
    let message: String
    let contactChoice: SupportFeedbackContactChoiceV1
    let supportBundle: SupportBundleAttachmentReferenceV1?
    let createdAt: Date
    let updatedAt: Date
    let revision: UInt64
    let draftSHA256: String

    init(
        draftID: UUID,
        category: SupportFeedbackCategoryV1,
        message: String,
        contactChoice: SupportFeedbackContactChoiceV1,
        supportBundle: SupportBundleAttachmentReferenceV1? = nil,
        createdAt: Date,
        updatedAt: Date,
        revision: UInt64
    ) throws {
        schemaVersion = Self.schemaVersion
        self.draftID = draftID
        self.category = category
        self.message = message
        self.contactChoice = contactChoice
        self.supportBundle = supportBundle
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        draftSHA256 = try RecoveryCenterCanonicalV1.sha256(DigestBasis(
            schemaVersion: Self.schemaVersion,
            draftID: draftID,
            category: category,
            message: message,
            contactChoice: contactChoice,
            supportBundle: supportBundle,
            createdAt: createdAt,
            updatedAt: updatedAt,
            revision: revision
        ))
        try validate()
    }

    func validate() throws {
        try supportBundle?.validate()
        let basis = DigestBasis(
            schemaVersion: schemaVersion,
            draftID: draftID,
            category: category,
            message: message,
            contactChoice: contactChoice,
            supportBundle: supportBundle,
            createdAt: createdAt,
            updatedAt: updatedAt,
            revision: revision
        )
        guard schemaVersion == Self.schemaVersion,
              draftID != RecoveryCenterValidationV1.zeroUUID,
              RecoveryCenterValidationV1.validDraftText(message, maximumBytes: Self.maximumMessageBytes),
              createdAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt >= createdAt,
              revision > 0,
              draftSHA256 == (try RecoveryCenterCanonicalV1.sha256(basis)) else {
            throw RecoveryCenterContractFailureV1.invalidDigest
        }
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let draftID: UUID
        let category: SupportFeedbackCategoryV1
        let message: String
        let contactChoice: SupportFeedbackContactChoiceV1
        let supportBundle: SupportBundleAttachmentReferenceV1?
        let createdAt: Date
        let updatedAt: Date
        let revision: UInt64
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, draftID, category, message, contactChoice
        case supportBundle, createdAt, updatedAt, revision, draftSHA256
    }

    init(from decoder: Decoder) throws {
        try RecoveryCenterValidationV1.rejectUnknownKeys(
            decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.schemaVersion else {
            throw RecoveryCenterContractFailureV1.unsupportedVersion
        }
        let rebuilt = try Self(
            draftID: values.decode(UUID.self, forKey: .draftID),
            category: values.decode(SupportFeedbackCategoryV1.self, forKey: .category),
            message: values.decode(String.self, forKey: .message),
            contactChoice: values.decode(
                SupportFeedbackContactChoiceV1.self,
                forKey: .contactChoice
            ),
            supportBundle: values.decodeIfPresent(
                SupportBundleAttachmentReferenceV1.self,
                forKey: .supportBundle
            ),
            createdAt: values.decode(Date.self, forKey: .createdAt),
            updatedAt: values.decode(Date.self, forKey: .updatedAt),
            revision: values.decode(UInt64.self, forKey: .revision)
        )
        guard try values.decode(String.self, forKey: .draftSHA256)
                == rebuilt.draftSHA256 else {
            throw RecoveryCenterContractFailureV1.invalidDigest
        }
        self = rebuilt
    }
}

enum FeedbackHandoffDestinationV1: String, CaseIterable, Codable, Hashable, Sendable {
    case mail = "MAIL"
    case localOnly = "LOCAL_ONLY"
}

struct FeedbackHandoffPreviewV1: Equatable, Sendable {
    let draftID: UUID
    let draftRevision: UInt64
    let draftSHA256: String
    let category: SupportFeedbackCategoryV1
    let exactMessage: String
    let messageByteCount: Int
    let contactChoice: SupportFeedbackContactChoiceV1
    let supportBundle: SupportBundleAttachmentReferenceV1?
    let totalByteCount: Int
    let destination: FeedbackHandoffDestinationV1

    init(draft: SupportFeedbackDraftV1, destination: FeedbackHandoffDestinationV1) throws {
        try draft.validate()
        guard !draft.message.isEmpty else {
            throw RecoveryCenterContractFailureV1.invalidValue
        }
        let messageByteCount = draft.message.utf8.count
        let attachmentBytes = draft.supportBundle?.byteCount ?? 0
        let (total, overflow) = messageByteCount.addingReportingOverflow(attachmentBytes)
        guard !overflow else { throw RecoveryCenterContractFailureV1.invalidValue }
        draftID = draft.draftID
        draftRevision = draft.revision
        draftSHA256 = draft.draftSHA256
        category = draft.category
        exactMessage = draft.message
        self.messageByteCount = messageByteCount
        contactChoice = draft.contactChoice
        supportBundle = draft.supportBundle
        totalByteCount = total
        self.destination = destination
        try validate(against: draft)
    }

    func validate(against draft: SupportFeedbackDraftV1) throws {
        try draft.validate()
        try supportBundle?.validate()
        let (expectedTotal, overflow) = messageByteCount.addingReportingOverflow(
            supportBundle?.byteCount ?? 0
        )
        guard !overflow,
              draftID == draft.draftID,
              draftRevision == draft.revision,
              draftSHA256 == draft.draftSHA256,
              category == draft.category,
              exactMessage == draft.message,
              messageByteCount == exactMessage.utf8.count,
              contactChoice == draft.contactChoice,
              supportBundle == draft.supportBundle,
              totalByteCount == expectedTotal else {
            throw RecoveryCenterContractFailureV1.inconsistentProjection
        }
    }
}

enum FeedbackHandoffResultV1: String, CaseIterable, Codable, Hashable, Sendable {
    case handedToMail = "HANDED_TO_MAIL"
    case savedInMail = "SAVED_IN_MAIL"
    case cancelled = "CANCELLED"
    case failed = "FAILED"
    case localOnly = "LOCAL_ONLY"

    var preservesDraft: Bool {
        true
    }

    static let claimsDeliveredOrReceived = false
}

enum RecoveryCenterLifecycleV1 {
    static let projectionPersistence = "NONPERSISTENT_DROP_AND_REBUILD"
    static let presentationClockPersistence = "NONPERSISTENT_MONOTONIC_ONLY"
    static let feedbackDraftPersistence = "DEVICE_OPERATIONAL_SUPPORT_STORE_ONLY"
    static let feedbackDraftIncludedInWorkspaceBackup = false
    static let ordinaryRecoveryRequiresEncryptedBackup = false
    static let ownsSecondRecoveryWriter = false
    static let ownsSecondRouter = false
}

private enum RecoveryCenterCanonicalV1 {
    static func sha256<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(value)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private enum RecoveryCenterValidationV1 {
    static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64
            && value.utf8.allSatisfy {
                (48...57).contains($0) || (97...102).contains($0)
            }
    }

    static func validText(_ value: String, maximumBytes: Int) -> Bool {
        !value.isEmpty
            && value.utf8.count <= maximumBytes
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            && !value.unicodeScalars.contains(where: { $0.properties.isBidiControl })
    }

    static func validToken(_ value: String, maximumBytes: Int) -> Bool {
        validText(value, maximumBytes: maximumBytes)
            && value.trimmingCharacters(in: .whitespacesAndNewlines) == value
    }

    static func validDraftText(_ value: String, maximumBytes: Int) -> Bool {
        value.utf8.count <= maximumBytes
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            && !value.unicodeScalars.contains(where: { $0.properties.isBidiControl })
    }

    static func rejectUnknownKeys(
        _ decoder: Decoder,
        allowed: Set<String>
    ) throws {
        let values = try decoder.container(keyedBy: RecoveryCenterAnyCodingKeyV1.self)
        guard values.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw RecoveryCenterContractFailureV1.invalidValue
        }
    }
}

private struct RecoveryCenterAnyCodingKeyV1: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

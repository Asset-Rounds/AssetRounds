import Foundation

enum PersistentKindLifecycleFailureV1: Error, Equatable, Sendable {
    case invalidSchemaVersion
    case invalidToken
    case invalidDescriptor
    case invalidLifecyclePolicy
    case invalidDataHandlingPolicy
    case incompleteCoverage
    case duplicateKind
    case conflictingOwner
    case unknownKind
    case unresolvedAuthority
    case noncanonicalValue
}
enum ActivityContractPersistentKindPolicyV2 {
    static let durableKindIDs=Set(ActivityContractPersistenceEnrollmentV2.persistentFamilies.map{"PERSISTENT_FAMILY:\($0)"})
    static let nonpersistentKindIDs=Set(ActivityContractPersistenceEnrollmentV2.nonpersistentFamilies.map{"NONPERSISTENT_RECEIPT:\($0)"})
    static let completedSnapshotReusesReleasedFileLifecycle=true
}

enum PersistentKindStorageDispositionV1: String, Codable, CaseIterable, Sendable {
    case swiftDataModel = "SWIFT_DATA_MODEL"
    case ownedFile = "OWNED_FILE"
    case recoveryJournal = "RECOVERY_JOURNAL"
    case derivedProjection = "DERIVED_PROJECTION"
    case portableWireProjection = "PORTABLE_WIRE_PROJECTION"
    case nonpersistentDeclaration = "NONPERSISTENT_DECLARATION"
}

enum PersistentKindRevisionDispositionV1: String, Codable, CaseIterable, Sendable {
    case exactRevision = "EXACT_REVISION"
    case appendOnlyImmutable = "APPEND_ONLY_IMMUTABLE"
    case immutableContent = "IMMUTABLE_CONTENT"
    case derivedFromCanonicalInputs = "DERIVED_FROM_CANONICAL_INPUTS"
    case destinationLocal = "DESTINATION_LOCAL"
    case operationScoped = "OPERATION_SCOPED"
}

enum PersistentKindMutationDispositionV1: String, Codable, CaseIterable, Sendable {
    case workspaceWriter = "WORKSPACE_WRITER"
    case immutableContentWriter = "IMMUTABLE_CONTENT_WRITER"
    case localDeviceOwner = "LOCAL_DEVICE_OWNER"
    case derivedOnly = "DERIVED_ONLY"
    case none = "NONE"
}

enum PersistentKindDigestDispositionV1: String, Codable, CaseIterable, Sendable {
    case canonicalDigestRequired = "CANONICAL_DIGEST_REQUIRED"
    case immutableContentDigestRequired = "IMMUTABLE_CONTENT_DIGEST_REQUIRED"
    case rebuildFromDependencies = "REBUILD_FROM_DEPENDENCIES"
    case notApplicable = "NOT_APPLICABLE"
}

enum PersistentKindClassificationV1: String, Codable, CaseIterable, Sendable {
    case canonical = "CANONICAL"
    case immutable = "IMMUTABLE"
    case derived = "DERIVED"
    case content = "CONTENT"
    case declaration = "DECLARATION"
    case wire = "WIRE"
    case nonpersistent = "NONPERSISTENT"
}

enum PersistentKindTemporalDispositionV1: String, Codable, CaseIterable, Sendable {
    case enrolledBeforeFirstWrite = "ENROLLED_BEFORE_FIRST_WRITE"
    case preexistingBoundForwardFix = "PREEXISTING_BOUND_FORWARD_FIX"
    case nonpersistentNoCanonicalWrite = "NONPERSISTENT_NO_CANONICAL_WRITE"
}

struct PersistentKindTemporalEvidenceV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let notApplicable = "NOT_APPLICABLE"

    let schemaVersion: Int
    let evidenceID: String
    let evidenceVersion: Int
    let disposition: PersistentKindTemporalDispositionV1
    let representationSourceCard: String
    let representationSourceOrdinal: Int
    let firstWriteVersion: String
    let lifecycleEnrollmentVersion: String
    let forwardFixVersion: String
    let firstWriteOrdinal: Int
    let lifecycleEnrollmentOrdinal: Int
    let forwardFixOrdinal: Int

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        evidenceID: String,
        evidenceVersion: Int,
        disposition: PersistentKindTemporalDispositionV1,
        representationSourceCard: String? = nil,
        representationSourceOrdinal: Int? = nil,
        firstWriteVersion: String,
        lifecycleEnrollmentVersion: String,
        forwardFixVersion: String,
        firstWriteOrdinal: Int,
        lifecycleEnrollmentOrdinal: Int,
        forwardFixOrdinal: Int
    ) throws {
        self.schemaVersion = schemaVersion
        self.evidenceID = evidenceID
        self.evidenceVersion = evidenceVersion
        self.disposition = disposition
        let compatibleSource: (String, Int)
        switch disposition {
        case .enrolledBeforeFirstWrite:
            compatibleSource = (lifecycleEnrollmentVersion, lifecycleEnrollmentOrdinal)
        case .preexistingBoundForwardFix:
            compatibleSource = (firstWriteVersion, firstWriteOrdinal)
        case .nonpersistentNoCanonicalWrite:
            compatibleSource = ("PRE_V23_BASELINE", 0)
        }
        self.representationSourceCard = representationSourceCard ?? compatibleSource.0
        self.representationSourceOrdinal = representationSourceOrdinal ?? compatibleSource.1
        self.firstWriteVersion = firstWriteVersion
        self.lifecycleEnrollmentVersion = lifecycleEnrollmentVersion
        self.forwardFixVersion = forwardFixVersion
        self.firstWriteOrdinal = firstWriteOrdinal
        self.lifecycleEnrollmentOrdinal = lifecycleEnrollmentOrdinal
        self.forwardFixOrdinal = forwardFixOrdinal
        try validate()
    }

    func validate() throws {
        let isBaselineSource = representationSourceCard == "PRE_V23_BASELINE"
        guard schemaVersion == Self.currentSchemaVersion,
              evidenceVersion > 0,
              CompatibilityCanonicalV1.validToken(evidenceID, maximumUTF8ByteCount: 200),
              CompatibilityCanonicalV1.validToken(representationSourceCard),
              representationSourceOrdinal >= 0,
              (isBaselineSource
                ? representationSourceOrdinal == 0
                : representationSourceOrdinal > 0),
              CompatibilityCanonicalV1.validToken(firstWriteVersion),
              CompatibilityCanonicalV1.validToken(lifecycleEnrollmentVersion),
              CompatibilityCanonicalV1.validToken(forwardFixVersion) else {
            throw PersistentKindLifecycleFailureV1.invalidDescriptor
        }
        switch disposition {
        case .enrolledBeforeFirstWrite:
            guard representationSourceCard == lifecycleEnrollmentVersion,
                  representationSourceOrdinal == lifecycleEnrollmentOrdinal,
                  firstWriteVersion != Self.notApplicable,
                  lifecycleEnrollmentVersion != Self.notApplicable,
                  forwardFixVersion == Self.notApplicable,
                  lifecycleEnrollmentOrdinal > 0,
                  firstWriteOrdinal >= lifecycleEnrollmentOrdinal,
                  forwardFixOrdinal == 0 else {
                throw PersistentKindLifecycleFailureV1.invalidDescriptor
            }
        case .preexistingBoundForwardFix:
            let isBaseline = firstWriteVersion == "PRE_V23_BASELINE"
            guard firstWriteVersion != Self.notApplicable,
                  representationSourceCard == firstWriteVersion,
                  representationSourceOrdinal == firstWriteOrdinal,
                  lifecycleEnrollmentVersion != Self.notApplicable,
                  forwardFixVersion != Self.notApplicable,
                  (isBaseline ? firstWriteOrdinal == 0 : firstWriteOrdinal > 0),
                  representationSourceOrdinal < lifecycleEnrollmentOrdinal,
                  lifecycleEnrollmentOrdinal > firstWriteOrdinal,
                  forwardFixOrdinal >= lifecycleEnrollmentOrdinal else {
                throw PersistentKindLifecycleFailureV1.invalidDescriptor
            }
        case .nonpersistentNoCanonicalWrite:
            guard representationSourceOrdinal < lifecycleEnrollmentOrdinal,
                  firstWriteVersion == Self.notApplicable,
                  forwardFixVersion == Self.notApplicable,
                  firstWriteOrdinal == 0,
                  lifecycleEnrollmentOrdinal > 0,
                  forwardFixOrdinal == 0 else {
                throw PersistentKindLifecycleFailureV1.invalidDescriptor
            }
        }
    }
}

struct PersistentKindDescriptorV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let subject: SyncSubjectIdentityV1
    let policyRevision: Int
    let storage: PersistentKindStorageDispositionV1
    let revision: PersistentKindRevisionDispositionV1
    let mutation: PersistentKindMutationDispositionV1
    let digest: PersistentKindDigestDispositionV1
    let kindClassification: PersistentKindClassificationV1
    let replicationClassification: SyncClassificationV1
    let temporalEvidence: PersistentKindTemporalEvidenceV1
    let declarationOwner: String
    let currentImplementationOwner: String

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        subject: SyncSubjectIdentityV1,
        policyRevision: Int = 1,
        storage: PersistentKindStorageDispositionV1,
        revision: PersistentKindRevisionDispositionV1,
        mutation: PersistentKindMutationDispositionV1,
        digest: PersistentKindDigestDispositionV1,
        kindClassification: PersistentKindClassificationV1,
        replicationClassification: SyncClassificationV1,
        temporalEvidence: PersistentKindTemporalEvidenceV1,
        declarationOwner: String,
        currentImplementationOwner: String
    ) throws {
        self.schemaVersion = schemaVersion
        self.subject = subject
        self.policyRevision = policyRevision
        self.storage = storage
        self.revision = revision
        self.mutation = mutation
        self.digest = digest
        self.kindClassification = kindClassification
        self.replicationClassification = replicationClassification
        self.temporalEvidence = temporalEvidence
        self.declarationOwner = declarationOwner
        self.currentImplementationOwner = currentImplementationOwner
        try validate()
    }

    var stableKindID: String { subject.canonicalKey }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion,
              policyRevision > 0,
              PersistentKindLifecycleValidationV1.validOwner(declarationOwner),
              PersistentKindLifecycleValidationV1.validOwner(currentImplementationOwner),
              declarationOwner != currentImplementationOwner else {
            throw PersistentKindLifecycleFailureV1.invalidDescriptor
        }
        try temporalEvidence.validate()
        let hasDurableRepresentationWrite =
            PersistentKindLifecycleRegistryV1.hasIndependentRepresentationWrite(subject)
        switch replicationClassification {
        case .derivedRebuildable:
            guard mutation == .derivedOnly,
                  digest == .rebuildFromDependencies else {
                throw PersistentKindLifecycleFailureV1.invalidDescriptor
            }
        case .contentBlob:
            guard mutation == .immutableContentWriter,
                  digest == .immutableContentDigestRequired else {
                throw PersistentKindLifecycleFailureV1.invalidDescriptor
            }
        case .replicated:
            guard mutation == .workspaceWriter,
                  digest == .canonicalDigestRequired else {
                throw PersistentKindLifecycleFailureV1.invalidDescriptor
            }
        case .localOnly, .privateDeviceOnly:
            guard mutation == .localDeviceOwner || mutation == .none else {
                throw PersistentKindLifecycleFailureV1.invalidDescriptor
            }
        }
        switch kindClassification {
        case .canonical, .immutable:
            guard replicationClassification != .contentBlob,
                  temporalEvidence.disposition != .nonpersistentNoCanonicalWrite else {
                throw PersistentKindLifecycleFailureV1.invalidDescriptor
            }
        case .content:
            guard replicationClassification == .contentBlob,
                  temporalEvidence.disposition != .nonpersistentNoCanonicalWrite else {
                throw PersistentKindLifecycleFailureV1.invalidDescriptor
            }
        case .declaration:
            guard replicationClassification == .localOnly
                    || replicationClassification == .privateDeviceOnly,
                  temporalEvidence.disposition != .nonpersistentNoCanonicalWrite else {
                throw PersistentKindLifecycleFailureV1.invalidDescriptor
            }
        case .wire:
            guard !hasDurableRepresentationWrite,
                  replicationClassification != .localOnly,
                  replicationClassification != .privateDeviceOnly,
                  temporalEvidence.disposition == .nonpersistentNoCanonicalWrite else {
                throw PersistentKindLifecycleFailureV1.invalidDescriptor
            }
        case .derived:
            guard replicationClassification == .derivedRebuildable,
                  temporalEvidence.disposition == (hasDurableRepresentationWrite
                    ? .preexistingBoundForwardFix : .nonpersistentNoCanonicalWrite) else {
                throw PersistentKindLifecycleFailureV1.invalidDescriptor
            }
        case .nonpersistent:
            guard replicationClassification == .localOnly
                    || replicationClassification == .privateDeviceOnly,
                  temporalEvidence.disposition == (hasDurableRepresentationWrite
                    ? .preexistingBoundForwardFix : .nonpersistentNoCanonicalWrite) else {
                throw PersistentKindLifecycleFailureV1.invalidDescriptor
            }
        }
    }
}

enum PersistentLifecycleActionDispositionV1: String, Codable, CaseIterable, Sendable {
    case supported = "SUPPORTED"
    case denied = "DENIED"
    case rebuildable = "REBUILDABLE"
    case immutable = "IMMUTABLE"
    case contentManaged = "CONTENT_MANAGED"
    case notApplicable = "NOT_APPLICABLE"
    case ownerRequired = "OWNER_REQUIRED"
}

enum PersistentLifecycleActionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case schemaAndVersion = "SCHEMA_AND_VERSION"
    case writerCommand = "WRITER_COMMAND"
    case canonicalQuery = "CANONICAL_QUERY"
    case migration = "MIGRATION"
    case filesystemBackup = "FILESYSTEM_BACKUP"
    case semanticBackup = "SEMANTIC_BACKUP"
    case replaceRestore = "REPLACE_RESTORE"
    case clone = "CLONE"
    case fork = "FORK"
    case importAction = "IMPORT"
    case export = "EXPORT"
    case report = "REPORT"
    case journal = "JOURNAL"
    case replay = "REPLAY"
    case search = "SEARCH"
    case rebuild = "REBUILD"
    case delete = "DELETE"
    case erase = "ERASE"
    case retention = "RETENTION"
    case localization = "LOCALIZATION"
    case accessibility = "ACCESSIBILITY"
    case privacy = "PRIVACY"
    case compatibility = "COMPATIBILITY"
    case downgrade = "DOWNGRADE"
    case forwardFix = "FORWARD_FIX"
    case interruptionRecovery = "INTERRUPTION_RECOVERY"
    case idempotentReceipt = "IDEMPOTENT_RECEIPT"
    case futureReplication = "FUTURE_REPLICATION"
}

enum PersistentLifecycleEvidenceDispositionV1: String, Codable, Sendable {
    case implementationRequired = "IMPLEMENTATION_REQUIRED"
    case absenceProved = "ABSENCE_PROVED"
    case immutableDeclaration = "IMMUTABLE_DECLARATION"
    case notApplicable = "NOT_APPLICABLE"
}

struct PersistentLifecycleActionPolicyV1: Codable, Equatable, Sendable {
    let action: PersistentLifecycleActionV1
    let disposition: PersistentLifecycleActionDispositionV1
    let authority: String
    let reason: String
    let dependencyKindIDs: [String]
    let evidence: PersistentLifecycleEvidenceDispositionV1

    init(
        action: PersistentLifecycleActionV1,
        disposition: PersistentLifecycleActionDispositionV1,
        authority: String,
        reason: String,
        dependencyKindIDs: [String],
        evidence: PersistentLifecycleEvidenceDispositionV1
    ) throws {
        self.action = action
        self.disposition = disposition
        self.authority = authority
        self.reason = reason
        self.dependencyKindIDs = dependencyKindIDs
        self.evidence = evidence
        try validate()
    }

    func validate() throws {
        guard PersistentKindLifecycleValidationV1.validOwner(authority),
              CompatibilityCanonicalV1.validToken(reason, maximumUTF8ByteCount: 200),
              dependencyKindIDs == dependencyKindIDs.sorted(),
              Set(dependencyKindIDs).count == dependencyKindIDs.count,
              dependencyKindIDs.allSatisfy(PersistentKindLifecycleValidationV1.validKindID),
              disposition != .ownerRequired,
              !(evidence == .notApplicable && disposition != .notApplicable),
              !(evidence == .absenceProved
                && disposition != .denied && disposition != .notApplicable) else {
            throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy
        }
    }
}

struct PersistentLifecyclePolicyV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let kindID: String
    let policyRevision: Int
    let actionPolicies: [PersistentLifecycleActionPolicyV1]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        kindID: String,
        policyRevision: Int,
        actionPolicies: [PersistentLifecycleActionPolicyV1]
    ) throws {
        self.schemaVersion = schemaVersion
        self.kindID = kindID
        self.policyRevision = policyRevision
        self.actionPolicies = actionPolicies
        try validate()
    }

    var actions: [PersistentLifecycleActionV1] { actionPolicies.map(\.action) }

    func disposition(
        for action: PersistentLifecycleActionV1
    ) throws -> PersistentLifecycleActionDispositionV1 {
        let matches = actionPolicies.filter { $0.action == action }
        guard matches.count == 1, let value = matches.first else {
            throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy
        }
        return value.disposition
    }

    var migration: PersistentLifecycleActionDispositionV1 { get throws { try disposition(for: .migration) } }
    var backup: PersistentLifecycleActionDispositionV1 { get throws { try disposition(for: .semanticBackup) } }
    var replaceRestore: PersistentLifecycleActionDispositionV1 { get throws { try disposition(for: .replaceRestore) } }
    var clone: PersistentLifecycleActionDispositionV1 { get throws { try disposition(for: .clone) } }
    var fork: PersistentLifecycleActionDispositionV1 { get throws { try disposition(for: .fork) } }
    var importAction: PersistentLifecycleActionDispositionV1 { get throws { try disposition(for: .importAction) } }
    var export: PersistentLifecycleActionDispositionV1 { get throws { try disposition(for: .export) } }
    var report: PersistentLifecycleActionDispositionV1 { get throws { try disposition(for: .report) } }
    var search: PersistentLifecycleActionDispositionV1 { get throws { try disposition(for: .search) } }
    var rebuild: PersistentLifecycleActionDispositionV1 { get throws { try disposition(for: .rebuild) } }
    var replay: PersistentLifecycleActionDispositionV1 { get throws { try disposition(for: .replay) } }
    var delete: PersistentLifecycleActionDispositionV1 { get throws { try disposition(for: .delete) } }
    var erase: PersistentLifecycleActionDispositionV1 { get throws { try disposition(for: .erase) } }
    var localization: PersistentLifecycleActionDispositionV1 { get throws { try disposition(for: .localization) } }
    var accessibility: PersistentLifecycleActionDispositionV1 { get throws { try disposition(for: .accessibility) } }
    var compatibility: PersistentLifecycleActionDispositionV1 { get throws { try disposition(for: .compatibility) } }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion,
              policyRevision > 0,
              PersistentKindLifecycleValidationV1.validKindID(kindID),
              actionPolicies.map(\.action.rawValue) == PersistentLifecycleActionV1.allCases
                .map(\.rawValue).sorted(),
              Set(actionPolicies.map(\.action)).count == actionPolicies.count else {
            throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy
        }
        try actionPolicies.forEach { try $0.validate() }
    }
}

enum PersistentDataPrivacyDispositionV1: String, Codable, CaseIterable, Sendable {
    case workspaceCanonical = "WORKSPACE_CANONICAL"
    case workspaceContent = "WORKSPACE_CONTENT"
    case privateDeviceOperational = "PRIVATE_DEVICE_OPERATIONAL"
    case noncustomerDiagnostic = "NONCUSTOMER_DIAGNOSTIC"
}

enum PersistentDataRetentionDispositionV1: String, Codable, CaseIterable, Sendable {
    case untilCanonicalDeleteOrErase = "UNTIL_CANONICAL_DELETE_OR_ERASE"
    case immutableHistoryUntilErase = "IMMUTABLE_HISTORY_UNTIL_ERASE"
    case rebuildable = "REBUILDABLE"
    case operationScoped = "OPERATION_SCOPED"
    case localDeviceRetained = "LOCAL_DEVICE_RETAINED"
}

enum PersistentDestructiveAuthorityV1: String, Codable, CaseIterable, Sendable {
    case canonicalWorkspaceDeletion = "CANONICAL_WORKSPACE_DELETION"
    case immutableContentManager = "IMMUTABLE_CONTENT_MANAGER"
    case derivedRebuildOwner = "DERIVED_REBUILD_OWNER"
    case localDeviceOwner = "LOCAL_DEVICE_OWNER"
    case operationCleanupOwner = "OPERATION_CLEANUP_OWNER"
    case notApplicable = "NOT_APPLICABLE"
    case ownerRequired = "OWNER_REQUIRED"
}

enum PersistentSecretHandlingDispositionV1: String, Codable, Sendable {
    case forbidden = "FORBIDDEN"
    case nonportableSecretAuthority = "NONPORTABLE_SECRET_AUTHORITY"
}

enum PersistentTelemetryDispositionV1: String, Codable, Sendable {
    case forbidden = "FORBIDDEN"
    case boundedNoncustomerOperationalOnly = "BOUNDED_NONCUSTOMER_OPERATIONAL_ONLY"
}

enum PersistentFileProtectionDispositionV1: String, Codable, Sendable {
    case complete = "COMPLETE"
    case notApplicable = "NOT_APPLICABLE"
}

enum PersistentPresentationDispositionV1: String, Codable, Sendable {
    case frozenDataNoPresentation = "FROZEN_DATA_NO_PRESENTATION"
    case localizedProjectionRequired = "LOCALIZED_PROJECTION_REQUIRED"
    case accessibleProjectionRequired = "ACCESSIBLE_PROJECTION_REQUIRED"
    case localizedFrozenHistoricProjection = "LOCALIZED_FROZEN_HISTORIC_PROJECTION"
    case accessibleFrozenHistoricProjection = "ACCESSIBLE_FROZEN_HISTORIC_PROJECTION"
}

enum PersistentCustomerWorkDataScopeV1: String, Codable, Sendable {
    case workspaceData = "WORKSPACE_DATA"
    case workspaceContent = "WORKSPACE_CONTENT"
    case deviceOperationalNoCustomerData = "DEVICE_OPERATIONAL_NO_CUSTOMER_DATA"
}

struct DataHandlingPolicyV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let kindID: String
    let policyRevision: Int
    let privacy: PersistentDataPrivacyDispositionV1
    let retention: PersistentDataRetentionDispositionV1
    let privacyAuthority: String
    let retentionAuthority: String
    let destructiveAuthority: PersistentDestructiveAuthorityV1
    let destructiveAuthorityOwner: String
    let secretHandling: PersistentSecretHandlingDispositionV1
    let telemetry: PersistentTelemetryDispositionV1
    let fileProtection: PersistentFileProtectionDispositionV1
    let localization: PersistentPresentationDispositionV1
    let accessibility: PersistentPresentationDispositionV1
    let customerWorkDataScope: PersistentCustomerWorkDataScopeV1

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        kindID: String,
        policyRevision: Int,
        privacy: PersistentDataPrivacyDispositionV1,
        retention: PersistentDataRetentionDispositionV1,
        privacyAuthority: String,
        retentionAuthority: String,
        destructiveAuthority: PersistentDestructiveAuthorityV1,
        destructiveAuthorityOwner: String,
        secretHandling: PersistentSecretHandlingDispositionV1,
        telemetry: PersistentTelemetryDispositionV1,
        fileProtection: PersistentFileProtectionDispositionV1,
        localization: PersistentPresentationDispositionV1,
        accessibility: PersistentPresentationDispositionV1,
        customerWorkDataScope: PersistentCustomerWorkDataScopeV1
    ) throws {
        self.schemaVersion = schemaVersion
        self.kindID = kindID
        self.policyRevision = policyRevision
        self.privacy = privacy
        self.retention = retention
        self.privacyAuthority = privacyAuthority
        self.retentionAuthority = retentionAuthority
        self.destructiveAuthority = destructiveAuthority
        self.destructiveAuthorityOwner = destructiveAuthorityOwner
        self.secretHandling = secretHandling
        self.telemetry = telemetry
        self.fileProtection = fileProtection
        self.localization = localization
        self.accessibility = accessibility
        self.customerWorkDataScope = customerWorkDataScope
        try validate()
    }

    var customerDataAllowedInDiagnostics: Bool { false }
    var secretsAllowedInDiagnostics: Bool { false }
    var automaticStoragePressureDeletionAllowed: Bool { false }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion,
              policyRevision > 0,
              PersistentKindLifecycleValidationV1.validKindID(kindID),
              PersistentKindLifecycleValidationV1.validOwner(privacyAuthority),
              PersistentKindLifecycleValidationV1.validOwner(retentionAuthority),
              PersistentKindLifecycleValidationV1.validOwner(destructiveAuthorityOwner),
              destructiveAuthority != .ownerRequired,
              !(privacy == .noncustomerDiagnostic
                && customerWorkDataScope != .deviceOperationalNoCustomerData),
              !(telemetry == .boundedNoncustomerOperationalOnly
                && customerWorkDataScope != .deviceOperationalNoCustomerData) else {
            throw PersistentKindLifecycleFailureV1.invalidDataHandlingPolicy
        }
    }
}

struct LifecycleUniverseSourceEvidenceV1: Codable, Equatable, Sendable {
    let sourceID: String
    let canonicalDigest: String

    init(sourceID: String, canonicalDigest: String) throws {
        guard CompatibilityCanonicalV1.validToken(sourceID),
              CompatibilityCanonicalV1.validSHA256(canonicalDigest) else {
            throw PersistentKindLifecycleFailureV1.invalidToken
        }
        self.sourceID = sourceID
        self.canonicalDigest = canonicalDigest
    }
}

struct LifecycleCoverageManifestV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let shippingBoundaryAdoption =
        "DEFERRED_UNTIL_ACCEPTED_S10_6_RECONCILIATION"

    let schemaVersion: Int
    let candidateHead: String
    let sourceEvidence: [LifecycleUniverseSourceEvidenceV1]
    let universeKindIDs: [String]
    let descriptorKindIDs: [String]
    let lifecyclePolicyKindIDs: [String]
    let dataHandlingPolicyKindIDs: [String]
    let missingKindIDs: [String]
    let duplicateKindIDs: [String]
    let conflictingKindIDs: [String]
    let unknownKindIDs: [String]
    let ownershipGapKindIDs: [String]
    let temporalConflictKindIDs: [String]
    let backupRestoreGapKindIDs: [String]
    let eraseGapKindIDs: [String]
    let exportReportGapKindIDs: [String]
    let searchAbsenceGapKindIDs: [String]
    let rebuildDependencyGapKindIDs: [String]
    let replayGapKindIDs: [String]
    let unresolvedAuthorityKindIDs: [String]
    let sourceDriftIDs: [String]
    let provisionalKernelOnly: Bool
    let shippingBoundaryAdoption: String

    var isComplete: Bool {
        missingKindIDs.isEmpty && duplicateKindIDs.isEmpty
            && conflictingKindIDs.isEmpty && unknownKindIDs.isEmpty
            && ownershipGapKindIDs.isEmpty && temporalConflictKindIDs.isEmpty
            && backupRestoreGapKindIDs.isEmpty && eraseGapKindIDs.isEmpty
            && exportReportGapKindIDs.isEmpty && searchAbsenceGapKindIDs.isEmpty
            && rebuildDependencyGapKindIDs.isEmpty && replayGapKindIDs.isEmpty
            && unresolvedAuthorityKindIDs.isEmpty && sourceDriftIDs.isEmpty
            && universeKindIDs == descriptorKindIDs
            && universeKindIDs == lifecyclePolicyKindIDs
            && universeKindIDs == dataHandlingPolicyKindIDs
    }

    func validate() throws {
        let collections = [universeKindIDs, descriptorKindIDs,
                           lifecyclePolicyKindIDs, dataHandlingPolicyKindIDs,
                           missingKindIDs, duplicateKindIDs,
                           conflictingKindIDs, unknownKindIDs,
                           ownershipGapKindIDs, temporalConflictKindIDs,
                           backupRestoreGapKindIDs, eraseGapKindIDs,
                           exportReportGapKindIDs, searchAbsenceGapKindIDs,
                           rebuildDependencyGapKindIDs, replayGapKindIDs,
                           unresolvedAuthorityKindIDs]
        guard schemaVersion == Self.currentSchemaVersion,
              CompatibilityCanonicalV1.validGitObjectID(candidateHead),
              !sourceEvidence.isEmpty,
              sourceEvidence.map(\.sourceID) == sourceEvidence.map(\.sourceID).sorted(),
              Set(sourceEvidence.map(\.sourceID)).count == sourceEvidence.count,
              sourceEvidence.allSatisfy({ CompatibilityCanonicalV1.validSHA256($0.canonicalDigest) }),
              sourceDriftIDs == sourceDriftIDs.sorted(),
              Set(sourceDriftIDs).count == sourceDriftIDs.count,
              sourceDriftIDs.allSatisfy({ CompatibilityCanonicalV1.validToken($0) }),
              !universeKindIDs.isEmpty,
              collections.allSatisfy({ values in
                  values == values.sorted()
                      && Set(values).count == values.count
                      && values.allSatisfy(PersistentKindLifecycleValidationV1.validKindID)
              }),
              provisionalKernelOnly,
              shippingBoundaryAdoption == Self.shippingBoundaryAdoption,
              isComplete else {
            throw PersistentKindLifecycleFailureV1.incompleteCoverage
        }
    }

    func canonicalData() throws -> Data {
        try validate()
        return try CompatibilityCanonicalV1.encode(self)
    }

    static func decodeCanonical(_ data: Data) throws -> Self {
        let value: Self = try CompatibilityCanonicalV1.decode(Self.self, from: data)
        try value.validate()
        return value
    }
}

enum PersistentLifecycleActivationStateV1: String, Codable, Sendable {
    case preActivation = "PRE_ACTIVATION"
    case activated = "ACTIVATED"
}

enum PersistentLifecyclePolicyRecoveryDispositionV1: String, Codable, Sendable {
    case discardUnpublishedStaging = "DISCARD_UNPUBLISHED_STAGING"
    case appendForwardFixSuccessor = "APPEND_FORWARD_FIX_SUCCESSOR"
}

struct PersistentLifecyclePolicySuccessorReceiptV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let kindID: String
    let activationState: PersistentLifecycleActivationStateV1
    let priorPolicyRevision: Int
    let resultingPolicyRevision: Int
    let priorCanonicalDigest: String
    let resultingCanonicalDigest: String
    let disposition: PersistentLifecyclePolicyRecoveryDispositionV1

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        kindID: String,
        activationState: PersistentLifecycleActivationStateV1,
        priorPolicyRevision: Int,
        resultingPolicyRevision: Int,
        priorCanonicalDigest: String,
        resultingCanonicalDigest: String,
        disposition: PersistentLifecyclePolicyRecoveryDispositionV1
    ) throws {
        self.schemaVersion = schemaVersion
        self.kindID = kindID
        self.activationState = activationState
        self.priorPolicyRevision = priorPolicyRevision
        self.resultingPolicyRevision = resultingPolicyRevision
        self.priorCanonicalDigest = priorCanonicalDigest
        self.resultingCanonicalDigest = resultingCanonicalDigest
        self.disposition = disposition
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion,
              PersistentKindLifecycleValidationV1.validKindID(kindID),
              priorPolicyRevision > 0,
              CompatibilityCanonicalV1.validSHA256(priorCanonicalDigest),
              CompatibilityCanonicalV1.validSHA256(resultingCanonicalDigest) else {
            throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy
        }
        switch activationState {
        case .preActivation:
            guard disposition == .discardUnpublishedStaging,
                  resultingPolicyRevision == priorPolicyRevision,
                  resultingCanonicalDigest == priorCanonicalDigest else {
                throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy
            }
        case .activated:
            let (successor, overflow) = priorPolicyRevision.addingReportingOverflow(1)
            guard !overflow,
                  disposition == .appendForwardFixSuccessor,
                  resultingPolicyRevision == successor,
                  resultingCanonicalDigest != priorCanonicalDigest else {
                throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy
            }
        }
    }
}

enum PersistentLifecycleInterruptionPointV1: String, Codable, Sendable {
    case beforePolicyStaging = "BEFORE_POLICY_STAGING"
    case afterPolicyStagingBeforeActivation = "AFTER_POLICY_STAGING_BEFORE_ACTIVATION"
    case afterActivationBeforeReceipt = "AFTER_ACTIVATION_BEFORE_RECEIPT"
    case afterReceiptBeforeCleanup = "AFTER_RECEIPT_BEFORE_CLEANUP"
}

enum PersistentLifecycleRecoveredEffectV1: String, Codable, Sendable {
    case noEffect = "NO_EFFECT"
    case discardedUnpublishedStaging = "DISCARDED_UNPUBLISHED_STAGING"
    case adoptedCompleteEffect = "ADOPTED_COMPLETE_EFFECT"
    case adoptedExistingReceipt = "ADOPTED_EXISTING_RECEIPT"
}

struct PersistentLifecycleRecoveryReceiptV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let operationID: UUID
    let kindID: String
    let persistenceClass: PersistentKindStorageDispositionV1
    let interruptionPoint: PersistentLifecycleInterruptionPointV1
    let recoveredEffect: PersistentLifecycleRecoveredEffectV1
    let policyRevision: Int

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        operationID: UUID,
        kindID: String,
        persistenceClass: PersistentKindStorageDispositionV1,
        interruptionPoint: PersistentLifecycleInterruptionPointV1,
        recoveredEffect: PersistentLifecycleRecoveredEffectV1,
        policyRevision: Int
    ) throws {
        self.schemaVersion = schemaVersion
        self.operationID = operationID
        self.kindID = kindID
        self.persistenceClass = persistenceClass
        self.interruptionPoint = interruptionPoint
        self.recoveredEffect = recoveredEffect
        self.policyRevision = policyRevision
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion,
              PersistentKindLifecycleValidationV1.validKindID(kindID),
              policyRevision > 0 else {
            throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy
        }
        switch interruptionPoint {
        case .beforePolicyStaging:
            guard recoveredEffect == .noEffect else {
                throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy
            }
        case .afterPolicyStagingBeforeActivation:
            guard recoveredEffect == .discardedUnpublishedStaging else {
                throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy
            }
        case .afterActivationBeforeReceipt:
            guard recoveredEffect == .adoptedCompleteEffect else {
                throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy
            }
        case .afterReceiptBeforeCleanup:
            guard recoveredEffect == .adoptedExistingReceipt else {
                throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy
            }
        }
    }
}

enum PersistentLifecycleReceiptPublicationV1 {
    /// Pure publish-or-adopt boundary used by the concrete durable adapter.
    /// An effect-before-receipt retry adopts byte-identical truth; a
    /// contradictory receipt for the same operation fails closed.
    static func publishOrAdopt(
        proposed: PersistentLifecycleRecoveryReceiptV1,
        existing: PersistentLifecycleRecoveryReceiptV1?
    ) throws -> PersistentLifecycleRecoveryReceiptV1 {
        try proposed.validate()
        guard let existing else { return proposed }
        try existing.validate()
        guard existing.operationID == proposed.operationID,
              existing == proposed else {
            throw PersistentKindLifecycleFailureV1.noncanonicalValue
        }
        return existing
    }
}

enum PersistentEraseObservedDispositionV1: String, Codable, Sendable {
    case removed = "REMOVED"
    case rebuiltEmpty = "REBUILT_EMPTY"
    case clearedByDeclaredOwner = "CLEARED_BY_DECLARED_OWNER"
    case preservedImmutable = "PRESERVED_IMMUTABLE"
    case preservedDenied = "PRESERVED_DENIED"
    case notApplicable = "NOT_APPLICABLE"
}

struct PersistentEraseObservationV1: Codable, Equatable, Sendable {
    let kindID: String
    let disposition: PersistentEraseObservedDispositionV1

    init(kindID: String, disposition: PersistentEraseObservedDispositionV1) throws {
        guard PersistentKindLifecycleValidationV1.validKindID(kindID) else {
            throw PersistentKindLifecycleFailureV1.invalidToken
        }
        self.kindID = kindID
        self.disposition = disposition
    }
}

struct LifecycleEraseAuditReceiptV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let auditedKindIDs: [String]
    let missingKindIDs: [String]
    let duplicateKindIDs: [String]
    let unexpectedKindIDs: [String]
    let mismatchedKindIDs: [String]

    var isComplete: Bool {
        missingKindIDs.isEmpty && duplicateKindIDs.isEmpty
            && unexpectedKindIDs.isEmpty && mismatchedKindIDs.isEmpty
    }

    func validate() throws {
        let values = [auditedKindIDs, missingKindIDs, duplicateKindIDs,
                      unexpectedKindIDs, mismatchedKindIDs]
        guard schemaVersion == Self.currentSchemaVersion,
              !auditedKindIDs.isEmpty,
              values.allSatisfy({ value in
                  value == value.sorted() && Set(value).count == value.count
                      && value.allSatisfy(PersistentKindLifecycleValidationV1.validKindID)
              }),
              isComplete else {
            throw PersistentKindLifecycleFailureV1.incompleteCoverage
        }
    }
}

enum PersistentKindLifecycleRegistryV1 {
    static let schemaVersion = 1
    static let schemaID = "PERSISTENT_LIFECYCLE_POLICY_V1"
    static let declarationOwner = "V23-P02-C09.PersistentKindLifecycleRegistryV1"
    static let requiredUniverseSourceIDs = [
        "ACCEPTED_FIXTURE_DECLARATION",
        "ARCHIVE_EXPORT_REPORT_PACKAGE_EXCHANGE_REGISTRY",
        "JOURNAL_CHECKPOINT_PROJECTION_REGISTRY",
        "OWNED_FILE_POLICY",
        "PERSISTENT_SCHEMA",
        "SYNC_CLASSIFICATION_CATALOG",
        "TEMPORAL_PROVENANCE_REGISTRY",
    ]

    /// Closed representation-write authority. Some durable bytes are exposed
    /// through projection or diagnostic subjects, so persistence shape alone
    /// is not evidence that a representation has (or lacks) an independent
    /// write boundary.
    static func hasIndependentRepresentationWrite(
        _ subject: SyncSubjectIdentityV1
    ) -> Bool {
        switch subject.category {
        case .persistentModel, .ownedFileClass, .journal:
            return true
        case .projection:
            return [
                "ReportSnapshotV1",
                "entityMutationRevision",
                "workspaceMutationState",
            ].contains(subject.stableName)
        case .diagnostic:
            return [
                "DeviceOperationalSupportStoreV2",
                "ScratchDataLeaseStoreV1",
                "diagnosticCounters",
            ].contains(subject.stableName)
        case .index, .secret:
            return false
        }
    }

    static func expectedEraseDisposition(
        classification: PersistentKindClassificationV1,
        dataHandling: DataHandlingPolicyV1
    ) throws -> PersistentEraseObservedDispositionV1 {
        try dataHandling.validate()
        switch classification {
        case .canonical: return .removed
        case .immutable, .declaration: return .preservedImmutable
        case .derived: return .rebuiltEmpty
        case .wire: return .notApplicable
        case .content:
            guard dataHandling.destructiveAuthority == .immutableContentManager else {
                throw PersistentKindLifecycleFailureV1.unresolvedAuthority
            }
            return .clearedByDeclaredOwner
        case .nonpersistent: return .notApplicable
        }
    }

    static func temporalProvenanceCanonicalMembers(
        for descriptors: [PersistentKindDescriptorV1]
    ) -> [String] {
        descriptors.map {
            let value = $0.temporalEvidence
            return [$0.stableKindID, value.evidenceID,
                    String(value.evidenceVersion), value.disposition.rawValue,
                    value.representationSourceCard,
                    String(value.representationSourceOrdinal),
                    value.firstWriteVersion, String(value.firstWriteOrdinal),
                    value.lifecycleEnrollmentVersion,
                    String(value.lifecycleEnrollmentOrdinal),
                    value.forwardFixVersion, String(value.forwardFixOrdinal)]
                .joined(separator: "|")
        }.sorted()
    }

    static func compileCoverage(
        candidateHead: String,
        sourceEvidence: [LifecycleUniverseSourceEvidenceV1],
        universe: [SyncSubjectIdentityV1],
        descriptors: [PersistentKindDescriptorV1],
        lifecyclePolicies: [PersistentLifecyclePolicyV1],
        dataHandlingPolicies: [DataHandlingPolicyV1]
    ) throws -> LifecycleCoverageManifestV1 {
        try descriptors.forEach { try $0.validate() }
        try lifecyclePolicies.forEach { try $0.validate() }
        try dataHandlingPolicies.forEach { try $0.validate() }

        let universeIDs = universe.map(\.canonicalKey)
        let descriptorIDs = descriptors.map(\.stableKindID)
        let lifecycleIDs = lifecyclePolicies.map(\.kindID)
        let handlingIDs = dataHandlingPolicies.map(\.kindID)
        let universeSet = Set(universeIDs)
        let declaredSet = Set(descriptorIDs)
        let lifecycleSet = Set(lifecycleIDs)
        let handlingSet = Set(handlingIDs)
        let allDeclared = declaredSet.union(lifecycleSet).union(handlingSet)
        let missing = universeSet.subtracting(declaredSet)
            .union(universeSet.subtracting(lifecycleSet))
            .union(universeSet.subtracting(handlingSet))
        let duplicates = duplicateValues(descriptorIDs)
            .union(duplicateValues(lifecycleIDs))
            .union(duplicateValues(handlingIDs))
        var conflicting = Set<String>()
        var temporalConflicts = Set<String>()
        var backupRestoreGaps = Set<String>()
        var eraseGaps = Set<String>()
        var exportReportGaps = Set<String>()
        var searchAbsenceGaps = Set<String>()
        var rebuildDependencyGaps = Set<String>()
        var replayGaps = Set<String>()
        var unresolved = Set<String>()
        for descriptor in descriptors {
            guard let lifecycle = lifecyclePolicies.first(where: {
                $0.kindID == descriptor.stableKindID
            }), let handling = dataHandlingPolicies.first(where: {
                $0.kindID == descriptor.stableKindID
            }) else { continue }
            if lifecycle.policyRevision != descriptor.policyRevision
                || handling.policyRevision != descriptor.policyRevision {
                conflicting.insert(descriptor.stableKindID)
            }
            switch descriptor.temporalEvidence.disposition {
            case .enrolledBeforeFirstWrite:
                if descriptor.temporalEvidence.lifecycleEnrollmentOrdinal
                    > descriptor.temporalEvidence.firstWriteOrdinal {
                    temporalConflicts.insert(descriptor.stableKindID)
                }
            case .preexistingBoundForwardFix:
                if descriptor.temporalEvidence.firstWriteOrdinal
                    >= descriptor.temporalEvidence.lifecycleEnrollmentOrdinal
                    || descriptor.temporalEvidence.forwardFixOrdinal
                        < descriptor.temporalEvidence.lifecycleEnrollmentOrdinal
                    || descriptor.temporalEvidence.forwardFixVersion != "V23_P02_C09" {
                    temporalConflicts.insert(descriptor.stableKindID)
                }
            case .nonpersistentNoCanonicalWrite:
                if hasIndependentRepresentationWrite(descriptor.subject) {
                    temporalConflicts.insert(descriptor.stableKindID)
                }
            }
            if descriptor.temporalEvidence.evidenceID
                != "temporal." + descriptor.stableKindID
                || descriptor.temporalEvidence.evidenceVersion != 1
                || descriptor.temporalEvidence.lifecycleEnrollmentVersion != "V23_P02_C09"
                || descriptor.temporalEvidence.lifecycleEnrollmentOrdinal != 29
                || (descriptor.temporalEvidence.disposition == .preexistingBoundForwardFix
                    && descriptor.temporalEvidence.forwardFixOrdinal != 29) {
                temporalConflicts.insert(descriptor.stableKindID)
            }
            let backup = try lifecycle.disposition(for: .semanticBackup)
            let restore = try lifecycle.disposition(for: .replaceRestore)
            if (backup == .supported && restore != .supported)
                || (backup == .immutable && restore != .immutable)
                || (backup == .rebuildable && restore != .rebuildable)
                || (backup == .denied && restore != .denied) {
                backupRestoreGaps.insert(descriptor.stableKindID)
            }
            let erase = try lifecycle.disposition(for: .erase)
            let expectedErase: PersistentLifecycleActionDispositionV1
            switch descriptor.kindClassification {
            case .canonical: expectedErase = .supported
            case .immutable, .declaration: expectedErase = .immutable
            case .derived: expectedErase = .rebuildable
            case .wire: expectedErase = .notApplicable
            case .content: expectedErase = .contentManaged
            case .nonpersistent: expectedErase = .notApplicable
            }
            if erase != expectedErase {
                eraseGaps.insert(descriptor.stableKindID)
            }
            if try lifecycle.disposition(for: .export) == .denied,
               try lifecycle.disposition(for: .report) != .denied {
                exportReportGaps.insert(descriptor.stableKindID)
            }
            let searchRow = try actionPolicy(.search, in: lifecycle)
            if searchRow.disposition == .denied && searchRow.evidence != .absenceProved {
                searchAbsenceGaps.insert(descriptor.stableKindID)
            }
            let rebuildRow = try actionPolicy(.rebuild, in: lifecycle)
            if rebuildRow.disposition == .rebuildable
                && rebuildRow.dependencyKindIDs.isEmpty {
                rebuildDependencyGaps.insert(descriptor.stableKindID)
            }
            let replayRow = try actionPolicy(.replay, in: lifecycle)
            if replayRow.disposition != .notApplicable
                && replayRow.evidence == .notApplicable {
                replayGaps.insert(descriptor.stableKindID)
            }
            if lifecycle.actionPolicies.contains(where: { $0.disposition == .ownerRequired })
                || handling.destructiveAuthority == .ownerRequired {
                unresolved.insert(descriptor.stableKindID)
            }
        }
        let observedSourceIDs = Set(sourceEvidence.map(\.sourceID))
        let requiredSourceIDs = Set(requiredUniverseSourceIDs)
        var sourceDrift = requiredSourceIDs.symmetricDifference(observedSourceIDs)
        let temporalSources = sourceEvidence.filter {
            $0.sourceID == "TEMPORAL_PROVENANCE_REGISTRY"
        }
        if temporalSources.count == 1, let temporalSource = temporalSources.first {
            let members = temporalProvenanceCanonicalMembers(for: descriptors)
            let canonical = try CompatibilityCanonicalV1.encode(members)
            if CompatibilityCanonicalV1.sha256(canonical) != temporalSource.canonicalDigest {
                sourceDrift.insert("TEMPORAL_PROVENANCE_REGISTRY")
                temporalConflicts.formUnion(descriptorIDs)
            }
        } else {
            sourceDrift.insert("TEMPORAL_PROVENANCE_REGISTRY")
            temporalConflicts.formUnion(descriptorIDs)
        }
        let manifest = LifecycleCoverageManifestV1(
            schemaVersion: LifecycleCoverageManifestV1.currentSchemaVersion,
            candidateHead: candidateHead,
            sourceEvidence: sourceEvidence.sorted { $0.sourceID < $1.sourceID },
            universeKindIDs: universeSet.sorted(),
            descriptorKindIDs: declaredSet.sorted(),
            lifecyclePolicyKindIDs: lifecycleSet.sorted(),
            dataHandlingPolicyKindIDs: handlingSet.sorted(),
            missingKindIDs: missing.sorted(),
            duplicateKindIDs: duplicates.sorted(),
            conflictingKindIDs: conflicting.sorted(),
            unknownKindIDs: allDeclared.subtracting(universeSet).sorted(),
            ownershipGapKindIDs: conflicting.sorted(),
            temporalConflictKindIDs: temporalConflicts.sorted(),
            backupRestoreGapKindIDs: backupRestoreGaps.sorted(),
            eraseGapKindIDs: eraseGaps.sorted(),
            exportReportGapKindIDs: exportReportGaps.sorted(),
            searchAbsenceGapKindIDs: searchAbsenceGaps.sorted(),
            rebuildDependencyGapKindIDs: rebuildDependencyGaps.sorted(),
            replayGapKindIDs: replayGaps.sorted(),
            unresolvedAuthorityKindIDs: unresolved.sorted(),
            sourceDriftIDs: sourceDrift.sorted(),
            provisionalKernelOnly: true,
            shippingBoundaryAdoption: LifecycleCoverageManifestV1.shippingBoundaryAdoption
        )
        try manifest.validate()
        return manifest
    }

    private static func duplicateValues(_ values: [String]) -> Set<String> {
        var seen = Set<String>()
        return Set(values.filter { !seen.insert($0).inserted })
    }


    private static func actionPolicy(
        _ action: PersistentLifecycleActionV1,
        in policy: PersistentLifecyclePolicyV1
    ) throws -> PersistentLifecycleActionPolicyV1 {
        let matches = policy.actionPolicies.filter { $0.action == action }
        guard matches.count == 1, let value = matches.first else {
            throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy
        }
        return value
    }
}

enum PersistentKindLifecycleValidationV1 {
    static func validKindID(_ value: String) -> Bool {
        let pieces = value.split(separator: ":", omittingEmptySubsequences: false)
        return pieces.count == 2
            && pieces.allSatisfy { CompatibilityCanonicalV1.validToken(
                String($0), maximumUTF8ByteCount: 160
            ) }
    }

    static func validOwner(_ value: String) -> Bool {
        CompatibilityCanonicalV1.validToken(value, maximumUTF8ByteCount: 200)
    }
}

enum SurveyDefinitionPersistentKindPolicyV1 {
    static let durableKindIDs=Set(["PERSISTENT_MODEL:SurveyDefinitionIdentityRow","PERSISTENT_MODEL:SurveyDefinitionReleaseRow","JOURNAL:SurveyDefinitionLifecycleEventV1"])
    static let derivedKindIDs=Set(["PROJECTION:SurveyDefinitionSemanticDiffV1","PROJECTION:SurveyDefinitionAdoptionPreviewV1","PROJECTION:SurveyTemplateQuarantineAssessmentV1"])
    static func validate(_ descriptors:[PersistentKindDescriptorV1])throws{let byID=Dictionary(uniqueKeysWithValues:descriptors.map{($0.stableKindID,$0)});guard durableKindIDs.allSatisfy({byID[$0].map{PersistentKindLifecycleRegistryV1.hasIndependentRepresentationWrite($0.subject)} == true}),derivedKindIDs.allSatisfy({byID[$0]?.kindClassification == .nonpersistent})else{throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy}}
    static func validateDeclaration()throws{guard durableKindIDs.count==3,derivedKindIDs.count==3,(durableKindIDs.union(derivedKindIDs)).allSatisfy(PersistentKindLifecycleValidationV1.validKindID)else{throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy}}
}

enum SurveySessionPersistentKindPolicyV1 {
    static let durableKindIDs=Set(["PERSISTENT_MODEL:SurveySessionRow","PERSISTENT_MODEL:FactCaptureRow","PERSISTENT_MODEL:ProvisionalSubjectRow","PERSISTENT_MODEL:SubjectPromotionReceiptRow","PERSISTENT_MODEL:SurveyPublicationSnapshotRow"])
    static let derivedKindIDs=Set(["PROJECTION:SurveySessionLifecycleClosureV1","PROJECTION:StoreSemanticEnvelopeV25"])
    static func validateDeclaration()throws{guard durableKindIDs.count==5,derivedKindIDs.count==2,durableKindIDs.isDisjoint(with:derivedKindIDs),(durableKindIDs.union(derivedKindIDs)).allSatisfy(PersistentKindLifecycleValidationV1.validKindID)else{throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy}}
}
enum AssetLocatorPersistentKindPolicyV1{static let durableKindIDs=Set(["PERSISTENT_MODEL:AssetLocatorRow","PERSISTENT_MODEL:LocatorBindingReceiptRow"]);static let derivedKindIDs=Set(["PROJECTION:LocatorResolutionV1","PROJECTION:LocatorBindingPreviewV1","PROJECTION:AssetLocatorLifecycleClosureV1","PROJECTION:StoreSemanticEnvelopeV26"]);static func validateDeclaration()throws{guard durableKindIDs.count==2,derivedKindIDs.count==4,durableKindIDs.isDisjoint(with:derivedKindIDs),(durableKindIDs.union(derivedKindIDs)).allSatisfy(PersistentKindLifecycleValidationV1.validKindID)else{throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy}}}
enum SchedulePersistentKindPolicyV1{static let durableKindIDs=Set(["PERSISTENT_MODEL:ScheduleDefinitionReleaseRow","PERSISTENT_MODEL:OccurrenceHistoryEventRow","PERSISTENT_MODEL:ExceptionCalendarReleaseRow","PERSISTENT_MODEL:ScheduleOverrideEventRow"]);static let derivedKindIDs=Set(["PROJECTION:ScheduleDefinitionReleaseV1","PROJECTION:OccurrenceHistoryEventV1","PROJECTION:ExceptionCalendarReleaseV1","PROJECTION:ScheduleOverrideEventV1","PROJECTION:OccurrenceGenerationPlanV1","PROJECTION:DueQueueProjectionV1","PROJECTION:ReminderProjectionV1","PROJECTION:StoreSemanticEnvelopeV27","PROJECTION:StoreSemanticEnvelopeV38"]);static func validateDeclaration()throws{guard durableKindIDs.count==4,derivedKindIDs.count==9,durableKindIDs.isDisjoint(with:derivedKindIDs),(durableKindIDs.union(derivedKindIDs)).allSatisfy(PersistentKindLifecycleValidationV1.validKindID)else{throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy}}}
enum PlanPersistentKindPolicyV1{static let durableKindIDs=Set(["PERSISTENT_MODEL:PlanDocumentRow","PERSISTENT_MODEL:PlanRevisionRow","PERSISTENT_MODEL:PlanPlacementRow","PERSISTENT_MODEL:RebaseReceiptRow"]);static let derivedKindIDs=Set(["PROJECTION:PlanDocumentV1","PROJECTION:PlanRevisionV1","PROJECTION:SpatialReferenceFrameV1","PROJECTION:PlanPlacementV1","PROJECTION:RebasePreviewV1","PROJECTION:RebaseReceiptV1","PROJECTION:StoreSemanticEnvelopeV28"]);static func validateDeclaration()throws{guard durableKindIDs.count==4,derivedKindIDs.count==7,durableKindIDs.isDisjoint(with:derivedKindIDs),(durableKindIDs.union(derivedKindIDs)).allSatisfy(PersistentKindLifecycleValidationV1.validKindID)else{throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy}}}
enum PlacementPosePersistentKindPolicyV1{static let durableKindIDs=Set(["PERSISTENT_MODEL:AssetPoseEventRow","PERSISTENT_MODEL:SpatialAnchorObservationRow"]);static let derivedKindIDs=Set(["PROJECTION:PoseAxisDescriptorRegistryV1","PROJECTION:AssetPoseCurrentTipV1","PROJECTION:CompletedPlacementPoseSnapshotV1","PROJECTION:StoreSemanticEnvelopeV29"]);static func validateDeclaration()throws{guard durableKindIDs.count==2,derivedKindIDs.count==4,durableKindIDs.isDisjoint(with:derivedKindIDs),(durableKindIDs.union(derivedKindIDs)).allSatisfy(PersistentKindLifecycleValidationV1.validKindID)else{throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy}}}
enum EvidenceContextPersistentKindPolicyV1{static let durableKindIDs=Set(["PERSISTENT_MODEL:EvidenceContextRow","PERSISTENT_MODEL:PairedObservationLinkRow"]);static let derivedKindIDs=Set(["PROJECTION:EvidenceContextV1","PROJECTION:PairedObservationLinkV1","PROJECTION:StoreSemanticEnvelopeV30"]);static func validateDeclaration()throws{guard durableKindIDs.count==2,derivedKindIDs.count==3,durableKindIDs.isDisjoint(with:derivedKindIDs),(durableKindIDs.union(derivedKindIDs)).allSatisfy(PersistentKindLifecycleValidationV1.validKindID)else{throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy}}}
enum LightingPersistentKindPolicyV1{static let durableKindIDs=Set(["PERSISTENT_MODEL:LightingSystemRow","PERSISTENT_MODEL:LightingObservationRow","PERSISTENT_MODEL:LightingIssueRow","PERSISTENT_MODEL:MeasurementPlanRow","PERSISTENT_MODEL:LightingClaimStateRow"]);static let derivedKindIDs=Set(["PROJECTION:LightingTopologyV1","PROJECTION:LightingDuePreviewV1","PROJECTION:StoreSemanticEnvelopeV31"]);static func validateDeclaration()throws{guard durableKindIDs.count==5,durableKindIDs.isDisjoint(with:derivedKindIDs)else{throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy}}}
enum AssistancePersistentKindPolicyV1{static let durableKindIDs=Set(["PERSISTENT_MODEL:AssistanceAcceptanceReceiptRow"]);static let nonpersistentKindIDs=Set(["PROJECTION:AssistanceProposalV1","PROJECTION:AssistanceCapabilityScratchV1"]);static let derivedKindIDs=Set(["PROJECTION:StoreSemanticEnvelopeV32"]);static let rejectedOrCancelledCorpusKindIDs:Set<String>=[];static func validateDeclaration()throws{guard durableKindIDs.count==1,nonpersistentKindIDs==Set(["PROJECTION:AssistanceProposalV1","PROJECTION:AssistanceCapabilityScratchV1"]),rejectedOrCancelledCorpusKindIDs.isEmpty,durableKindIDs.isDisjoint(with:nonpersistentKindIDs),durableKindIDs.isDisjoint(with:derivedKindIDs)else{throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy}}}

/// C56's structured voice proposal is a typed, operation-scoped view under
/// the existing C32 assistance proposal authority. It deliberately does not
/// add a sync subject, durable family, journal kind, or canonical write.
enum C56VoiceStructuringNonpersistentLifecyclePolicyV1 {
    static let reusedAssistanceKindID = "PROJECTION:AssistanceProposalV1"
    static let durableFamilyCount = 0
    static let declaresIndependentSyncSubject = false
    static let canonicalWritePermitted = false

    static func validateDeclaration() throws {
        guard AssistancePersistentKindPolicyV1.nonpersistentKindIDs
                .contains(reusedAssistanceKindID),
              !AssistancePersistentKindPolicyV1.durableKindIDs
                .contains(reusedAssistanceKindID),
              durableFamilyCount == 0,
              !declaresIndependentSyncSubject,
              !canonicalWritePermitted else {
            throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy
        }
    }
}
enum TemporalEvidencePersistentKindPolicyV1 {
    static let durableKindIDs = Set([
        "PERSISTENT_MODEL:TemporalEvidenceClipRow",
        "PERSISTENT_MODEL:TimecodedEvidenceAnchorRow",
    ])
    static let journalSupportingKindIDs = Set([
        "JOURNAL:TemporalEvidenceDerivativeV1",
        "JOURNAL:TemporalEvidenceRetentionEventV1",
    ])
    static let contentKindIDs = Set(["OWNED_FILE_CLASS:mediaOriginal"])
    static let nonpersistentKindIDs = Set(["PROJECTION:TemporalEvidenceCaptureScratchV1"])
    static let derivedKindIDs = Set(["PROJECTION:StoreSemanticEnvelopeV33"])

    static func validateDeclaration() throws {
        let persistent = durableKindIDs.union(journalSupportingKindIDs).union(contentKindIDs)
        guard durableKindIDs.count == TemporalEvidencePersistenceEnrollmentV1.durableModelCount,
              TemporalEvidencePersistenceEnrollmentV1.persistentFamilies == [
                "TemporalEvidenceClipRow", "TimecodedEvidenceAnchorRow",
              ],
              journalSupportingKindIDs.count == 2,
              contentKindIDs.count == 1,
              nonpersistentKindIDs == Set(["PROJECTION:TemporalEvidenceCaptureScratchV1"]),
              persistent.isDisjoint(with: nonpersistentKindIDs),
              persistent.isDisjoint(with: derivedKindIDs),
              persistent.union(nonpersistentKindIDs).union(derivedKindIDs)
                .allSatisfy(PersistentKindLifecycleValidationV1.validKindID) else {
            throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy
        }
    }
}

enum AssetLabelPersistentKindPolicyV1 {
    static let durableKindIDs = Set(["PERSISTENT_MODEL:AcceptedLabelGenerationSnapshotRow"])
    static let existingLocatorTruthKindIDs = Set([
        "PERSISTENT_MODEL:AssetLocatorRow", "PERSISTENT_MODEL:LocatorBindingReceiptRow",
    ])
    static let nonpersistentKindIDs = Set([
        "PROJECTION:AssetLabelGenerationPlanV1", "PROJECTION:AssetLabelGenerationResultV1",
        "PROJECTION:AssetLabelBatchCheckpointV1", "PROJECTION:AssetLabelOutputArtifactV1",
    ])
    static let derivedKindIDs = Set(["PROJECTION:StoreSemanticEnvelopeV34"])

    static func validateDeclaration() throws {
        guard durableKindIDs.count == AssetLabelPersistenceEnrollmentV1.durableModelCount,
              AssetLabelPersistenceEnrollmentV1.persistentFamilies
                == ["AcceptedLabelGenerationSnapshotRow"],
              existingLocatorTruthKindIDs.count == 2,
              nonpersistentKindIDs.count == 4,
              durableKindIDs.isDisjoint(with: nonpersistentKindIDs),
              durableKindIDs.isDisjoint(with: derivedKindIDs),
              durableKindIDs.union(existingLocatorTruthKindIDs)
                .union(nonpersistentKindIDs).union(derivedKindIDs)
                .allSatisfy(PersistentKindLifecycleValidationV1.validKindID) else {
            throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy
        }
    }
}

enum C45AcceptedLabelPersistentKindEnrollmentV1 { static let kind:WorkspaceEntityKindV1 = .acceptedLabelGenerationSnapshot;static let durableFamilyCount=AssetLabelPersistenceEnrollmentV1.durableModelCount }

enum OperationalContactPersistentKindPolicyV1{
    static let durableKindIDs=Set(["PERSISTENT_MODEL:ServiceContactPointRow","PERSISTENT_MODEL:SystemHandoffIntentRow"])
    static let nonpersistentKindIDs=Set(["PROJECTION:SystemHandoffResultV1","PROJECTION:PartyContactsImportPreviewV1"])
    static func validateDeclaration()throws{guard durableKindIDs.count==OperationalContactPersistenceEnrollmentV1.durableModelCount,durableKindIDs.isDisjoint(with:nonpersistentKindIDs),(durableKindIDs.union(nonpersistentKindIDs)).allSatisfy(PersistentKindLifecycleValidationV1.validKindID)else{throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy}}
}

enum C05EvidenceCurationPersistentKindPolicyV1 {
    static let durableKindIDs = Set([
        "PERSISTENT_MODEL:EvidenceAssociationEventRowV1",
        "PERSISTENT_MODEL:EvidenceSequenceRevisionRowV1",
    ])
    static let derivedKindIDs = Set(["PROJECTION:StoreSemanticEnvelopeV43"])

    static func validateDeclaration() throws {
        guard durableKindIDs.count == 2,
              derivedKindIDs.count == 1,
              durableKindIDs.isDisjoint(with: derivedKindIDs),
              durableKindIDs.union(derivedKindIDs)
                .allSatisfy(PersistentKindLifecycleValidationV1.validKindID) else {
            throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy
        }
    }
}

enum C04ShopReportProfilePersistentKindPolicyV1 {
    static let durableKindIDs = Set(["PERSISTENT_MODEL:ShopReportProfileRowV1"])
    static let derivedKindIDs = Set(["PROJECTION:StoreSemanticEnvelopeV44"])

    static func validateDeclaration() throws {
        guard durableKindIDs.count == 1,
              derivedKindIDs.count == 1,
              durableKindIDs.isDisjoint(with: derivedKindIDs),
              (durableKindIDs.union(derivedKindIDs)).allSatisfy(PersistentKindLifecycleValidationV1.validKindID) else {
            throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy
        }
    }
}

enum C05RoundSessionPersistentKindPolicyV1 {
    static let durableKindIDs = Set(["PERSISTENT_MODEL:RoundSessionRevisionRowV1"])
    static let derivedKindIDs = Set(["PROJECTION:StoreSemanticEnvelopeV45"])

    static func validateDeclaration() throws {
        guard durableKindIDs.count == 1,
              derivedKindIDs.count == 1,
              durableKindIDs.isDisjoint(with: derivedKindIDs),
              (durableKindIDs.union(derivedKindIDs))
                .allSatisfy(PersistentKindLifecycleValidationV1.validKindID) else {
            throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy
        }
    }
}

enum C08ImportBulkPersistentKindPolicyV1 {
    static let durableKindIDs = Set([
        "PERSISTENT_MODEL:ImportMappingProfileRowV1",
        "PERSISTENT_MODEL:BulkSessionRowV1",
        "PERSISTENT_MODEL:BulkCommitReceiptRowV1"
    ])
    static let derivedKindIDs = Set(["PROJECTION:StoreSemanticEnvelopeV46"])
    static let excludedKindIDs = Set([
        "SCRATCH:ImportSourceV1", "PREVIEW:ImportBulkPreviewV1",
        "SCRATCH:ImportBulkCorrectionStagingV1"
    ])

    static func validateDeclaration() throws {
        guard durableKindIDs.count == 3, derivedKindIDs.count == 1,
              durableKindIDs.isDisjoint(with: derivedKindIDs),
              durableKindIDs.isDisjoint(with: excludedKindIDs),
              (durableKindIDs.union(derivedKindIDs)).allSatisfy(PersistentKindLifecycleValidationV1.validKindID) else {
            throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy
        }
    }

    static let savedMappingMayDeleteWithWorkspace = true
    static let sessionMayDeleteWithWorkspace = true
    static let immutableReceiptNeverRollsBackCommittedBatch = true
}

/// C10 keeps every assessment, rule-set, waiver, and durable mutation receipt
/// as an independent canonical fact. Later evidence or policy cannot rewrite
/// the historic fact it invalidates.
enum C10EvidenceQualityPersistentKindPolicyV1 {
    static let durableKindIDs = Set([
        "PERSISTENT_MODEL:EvidenceQualityAssessmentRowV1",
        "PERSISTENT_MODEL:EvidenceQualityMutationReceiptRowV1",
        "PERSISTENT_MODEL:EvidenceQualityRuleSetRowV1",
        "PERSISTENT_MODEL:EvidenceQualityWaiverRowV1",
    ])
    static let derivedKindIDs = Set(["PROJECTION:StoreSemanticEnvelopeV47"])

    static func validateDeclaration() throws {
        guard durableKindIDs.count == 4, derivedKindIDs.count == 1,
              durableKindIDs.isDisjoint(with: derivedKindIDs),
              durableKindIDs.union(derivedKindIDs)
                .allSatisfy(PersistentKindLifecycleValidationV1.validKindID) else {
            throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy
        }
    }

    static let historicWarningsAndWaiversAreImmutable = true
    static let changedEvidenceOrRulesInvalidateWithoutRewrite = true
    static let downgradeDisposition = "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_ACTIVATION"
}

/// C11 keeps offline inbox capture and frozen snippet revisions as canonical
/// history. Promotion is explicit and links immutable original evidence; an
/// unpromoted row never becomes an inspection, finding, or report outcome.
enum C11FastSurveyInboxPersistentKindPolicyV1 {
    static let durableKindIDs = Set([
        "PERSISTENT_MODEL:CaptureInboxItemRowV1",
        "PERSISTENT_MODEL:CapturePromotionRowV1",
        "PERSISTENT_MODEL:FastSurveyInboxMutationReceiptRowV1",
        "PERSISTENT_MODEL:SnippetInsertionHistoryRowV1",
        "PERSISTENT_MODEL:SnippetRowV1",
    ])
    static let derivedKindIDs = Set(["PROJECTION:StoreSemanticEnvelopeV48"])

    static func validateDeclaration() throws {
        guard durableKindIDs.count == 5, derivedKindIDs.count == 1,
              durableKindIDs.isDisjoint(with: derivedKindIDs),
              durableKindIDs.union(derivedKindIDs)
                .allSatisfy(PersistentKindLifecycleValidationV1.validKindID) else {
            throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy
        }
    }

    static let unpromotedItemsExcludedFromInspectionAndReports = true
    static let promotionPreservesOriginalEvidenceAndExactLinks = true
    static let frozenSnippetInsertionsAreHistoric = true
    static let downgradeDisposition = "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_ACTIVATION"
}

/// C13 stores only immutable alias/consolidation history and its typed
/// receipt. Plans and previews are derived, explicitly mutation-free input.
enum C13EntityIdentityResolutionPersistentKindPolicyV1 {
    static let durableKindIDs = Set([
        "PERSISTENT_MODEL:EntityAliasLinkRowV1",
        "PERSISTENT_MODEL:EntityConsolidationReceiptRowV1",
        "PERSISTENT_MODEL:EntityIdentityResolutionMutationReceiptRowV1",
    ])
    static let derivedKindIDs = Set(["PROJECTION:StoreSemanticEnvelopeV50"])

    static func validateDeclaration() throws {
        guard durableKindIDs.count == 3, derivedKindIDs.count == 1,
              durableKindIDs.isDisjoint(with: derivedKindIDs),
              durableKindIDs.union(derivedKindIDs)
                .allSatisfy(PersistentKindLifecycleValidationV1.validKindID) else {
            throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy
        }
    }

    static let plansAndPreviewsAreNonpersistent = true
    static let aliasesAndConsolidationReceiptsAreAppendOnly = true
    static let reversalIsSuccessorReceiptOnly = true
    static let downgradeDisposition = "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_ACTIVATION"
}

/// C16 persists only the canonical Practice-workspace provenance marker. The
/// install/reset/clone plans, catalogs, and experience projections are inputs
/// or rebuildable views; the generic mutation receipt remains their sole
/// durable receipt authority.
enum C16WorkspaceExperiencePersistentKindPolicyV1 {
    static let durableKindIDs = Set([
        "PERSISTENT_MODEL:PracticeWorkspaceProvenanceRowV1",
    ])
    static let derivedKindIDs = Set(["PROJECTION:StoreSemanticEnvelopeV51"])

    static func validateDeclaration() throws {
        guard durableKindIDs.count == 1, derivedKindIDs.count == 1,
              durableKindIDs.isDisjoint(with: derivedKindIDs),
              durableKindIDs.union(derivedKindIDs)
                .allSatisfy(PersistentKindLifecycleValidationV1.validKindID) else {
            throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy
        }
    }

    static let absenceMeansRealWorkspace = true
    static let installUsesGenericMutationReceiptOnly = true
    static let plansCatalogsAndProjectionsAreNonpersistent = true
    static let activeSelectionAndNoticeAcknowledgementAreDeviceLocal = true
    static let cloneAndForkOmitPracticeProvenance = true
    static let practiceResetDeletesWholeWorkspaceBeforeExplicitInstall = true
    static let downgradeDisposition = "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_ACTIVATION"
}

/// C17 has one append-only aggregate. Generic MutationReceiptRow remains the
/// only receipt owner; offline readiness and safety/report/search projections
/// are derived and cannot become independent durable records.
enum C17LightingDayInventoryPersistentKindPolicyV1 {
    static let durableKindIDs = Set([
        "PERSISTENT_MODEL:LightingDayInventoryWorkflowRowV1",
    ])
    static let derivedKindIDs = Set(["PROJECTION:StoreSemanticEnvelopeV52"])

    static func validateDeclaration() throws {
        guard durableKindIDs.count == 1, derivedKindIDs.count == 1,
              durableKindIDs.isDisjoint(with: derivedKindIDs),
              durableKindIDs.union(derivedKindIDs)
                .allSatisfy(PersistentKindLifecycleValidationV1.validKindID) else {
            throw PersistentKindLifecycleFailureV1.invalidLifecyclePolicy
        }
    }

    static let genericMutationReceiptIsSoleReceiptOwner = true
    static let workflowHistoryIsAppendOnly = true
    static let offlineReadinessIsDerivedOnly = true
    static let hardSafetyStopAuthorizesObservation = false
    static let downgradeDisposition = "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_ACTIVATION"
}

enum C34SceneNavigationPersistentKindBoundaryV1 {
    static let persistentKindCount = 0
    static let lifecycleEnrollmentCount = 0
    static func validate() -> Bool { persistentKindCount == 0 && lifecycleEnrollmentCount == 0 && C34SceneNavigationCanonicalExclusionV1.validate() }
}
enum C52ServiceRequestBoundary_PersistentKindLifecycleRegistryV1 {
    static let sourceKind: ServiceRequestSourceKindV1 = .portableSubmission
    static let requesterAssertionType: ServiceRequestRequesterAssertionV1.Type = ServiceRequestRequesterAssertionV1.self
    static let contactAssertionType: ServiceRequestContactAssertionV1.Type = ServiceRequestContactAssertionV1.self
    static let requesterIdentityIsUnverified: Bool = !PortableServiceRequestFormatBoundaryV1.requesterIdentityIsVerified
    static let contactAssertionWording: String = "SELF_ASSERTED_UNVERIFIED"
    static let urgencyIsUnverified: Bool = !PortableServiceRequestFormatBoundaryV1.urgencyIsVerified
    static let cleartextIsReadableAndForwardable: Bool = PortableServiceRequestFormatBoundaryV1.submissionIsCleartext && PortableServiceRequestFormatBoundaryV1.invitationIsReadableAndForwardable
    static let providerContactPurposeSeparationRequired: Bool = true
    static let canonicalSourceBytesAreAuthoritative: Bool = true
    static let duplicateCandidatesAreDerived: Bool = !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityMayBecomeWorkspaceTruth: Bool = ServiceRequestNoncanonicalBoundaryV1.rawCapabilityIsWorkspaceTruth
    static let automaticWorkOrDuplicateActionPermitted: Bool = ServiceRequestNoncanonicalBoundaryV1.automaticWorkCreationPermitted || ServiceRequestNoncanonicalBoundaryV1.automaticDuplicateMergePermitted
    static let excludedSurfaces: [String] = ["REPORT", "SEARCH", "DIAGNOSTIC", "LIFECYCLE", "COMPATIBILITY", "BACKUP", "DELETE"]
}

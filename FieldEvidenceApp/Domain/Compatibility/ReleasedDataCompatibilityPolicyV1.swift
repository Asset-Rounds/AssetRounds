import Foundation

enum CompatibilityContractErrorV1: Error, Equatable, Sendable {
    case invalidSchemaVersion
    case invalidCanonicalValue
    case invalidSupportTable
    case duplicateArtifactFamily
    case unknownArtifactFamily
    case unsupportedVersion
    case noncurrentWriterVersion
    case missingCorpusEnrollment
    case invalidCorpus
    case releasedCaseRemoved
    case quarantinedCaseIDReuse
    case quarantinedRunIDReuse
    case invalidRunReceipt
    case invalidSeedSeal
}

enum CompatibilityArtifactFamilyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case liveStore = "live_store"
    case currentGenerationPointer = "current_generation_pointer"
    case storeGenerationManifest = "store_generation_manifest"
    case storeMigrationJournal = "store_migration_journal"
    case backupPackage = "backup_package"
    case streamingArchive = "streaming_archive"
    case reportOpenJSON = "report_open_json"
    case reportPDF = "report_pdf"
    case finalizationIntent = "finalization_intent"
    case signPack = "sign_pack"
    case durableMedia = "durable_media"
    case deletionLedger = "deletion_ledger"
    case deletionIntent = "deletion_intent"
    case eraseIntent = "erase_intent"
    case restoreIntent = "restore_intent"
}

enum CompatibilityUnsupportedVersionDispositionV1: String, Codable, Sendable {
    case failClosedUnsupportedVersion = "fail_closed_unsupported_version"
}

enum CompatibilityWriterDispositionV1: String, Codable, Sendable {
    case currentVersionOnly = "current_version_only"
}

enum CompatibilityCapabilityDispositionV1: String, Codable, Sendable {
    case available
    case unavailableAtThisHead = "unavailable_at_this_head"
    case deferredToV23P03C09 = "deferred_to_v23_p03_c09"
    case notApplicable = "not_applicable"
}

enum CompatibilityPersistenceDispositionV1: String, Codable, Sendable {
    case publiclyPersisted = "publicly_persisted"
    case internalRecovery = "internal_recovery"
}

struct SupportedUpgradeTransitionV1: Codable, Equatable, Sendable {
    let fromVersion: String
    let toVersion: String

    init(fromVersion: String, toVersion: String) {
        self.fromVersion = fromVersion
        self.toVersion = toVersion
    }
}

struct SupportedUpgradePathV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let family: CompatibilityArtifactFamilyV1
    let persistence: CompatibilityPersistenceDispositionV1
    let readableVersions: [String]
    let currentWriterVersion: String
    let forwardUpgradeTransitions: [SupportedUpgradeTransitionV1]
    let unknownVersionDisposition: CompatibilityUnsupportedVersionDispositionV1
    let writerDisposition: CompatibilityWriterDispositionV1
    let searchDisposition: CompatibilityCapabilityDispositionV1
    let rebuildDisposition: CompatibilityCapabilityDispositionV1

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        family: CompatibilityArtifactFamilyV1,
        persistence: CompatibilityPersistenceDispositionV1,
        readableVersions: [String],
        currentWriterVersion: String,
        forwardUpgradeTransitions: [SupportedUpgradeTransitionV1] = [],
        unknownVersionDisposition: CompatibilityUnsupportedVersionDispositionV1 = .failClosedUnsupportedVersion,
        writerDisposition: CompatibilityWriterDispositionV1 = .currentVersionOnly,
        searchDisposition: CompatibilityCapabilityDispositionV1,
        rebuildDisposition: CompatibilityCapabilityDispositionV1
    ) {
        self.schemaVersion = schemaVersion
        self.family = family
        self.persistence = persistence
        self.readableVersions = readableVersions
        self.currentWriterVersion = currentWriterVersion
        self.forwardUpgradeTransitions = forwardUpgradeTransitions
        self.unknownVersionDisposition = unknownVersionDisposition
        self.writerDisposition = writerDisposition
        self.searchDisposition = searchDisposition
        self.rebuildDisposition = rebuildDisposition
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion,
              Self.validVersions(readableVersions),
              readableVersions.contains(currentWriterVersion),
              unknownVersionDisposition == .failClosedUnsupportedVersion,
              writerDisposition == .currentVersionOnly else {
            throw CompatibilityContractErrorV1.invalidSupportTable
        }
        let transitionKeys = forwardUpgradeTransitions.map {
            "\($0.fromVersion)->\($0.toVersion)"
        }
        guard Set(transitionKeys).count == transitionKeys.count,
              forwardUpgradeTransitions.allSatisfy({ transition in
                  Self.validVersion(transition.fromVersion)
                      && Self.validVersion(transition.toVersion)
                      && readableVersions.contains(transition.fromVersion)
                      && readableVersions.contains(transition.toVersion)
                      && transition.fromVersion != transition.toVersion
              }) else {
            throw CompatibilityContractErrorV1.invalidSupportTable
        }
        if family == .liveStore {
            guard readableVersions.allSatisfy({ version in
                version == currentWriterVersion || Self.hasForwardPath(
                    from: version,
                    to: currentWriterVersion,
                    transitions: forwardUpgradeTransitions
                )
            }) else {
                throw CompatibilityContractErrorV1.invalidSupportTable
            }
        }
    }

    func validateReadableVersion(_ version: String) throws {
        try validate()
        guard readableVersions.contains(version) else {
            throw CompatibilityContractErrorV1.unsupportedVersion
        }
    }

    func validateWriterVersion(_ version: String) throws {
        try validateReadableVersion(version)
        guard version == currentWriterVersion else {
            throw CompatibilityContractErrorV1.noncurrentWriterVersion
        }
    }

    func supportsForwardUpgrade(fromVersion: String, toVersion: String) throws -> Bool {
        try validateReadableVersion(fromVersion)
        try validateReadableVersion(toVersion)
        return fromVersion == toVersion || Self.hasForwardPath(
            from: fromVersion,
            to: toVersion,
            transitions: forwardUpgradeTransitions
        )
    }

    static func decodeCanonical(_ data: Data) throws -> SupportedUpgradePathV1 {
        let value: SupportedUpgradePathV1 = try CompatibilityCanonicalV1.decode(
            SupportedUpgradePathV1.self,
            from: data
        )
        try value.validate()
        return value
    }

    private static func validVersions(_ values: [String]) -> Bool {
        !values.isEmpty
            && Set(values).count == values.count
            && values == values.sorted()
            && values.allSatisfy(validVersion)
    }

    private static func validVersion(_ value: String) -> Bool {
        CompatibilityCanonicalV1.validToken(value, maximumUTF8ByteCount: 160)
    }

    private static func hasForwardPath(
        from source: String,
        to target: String,
        transitions: [SupportedUpgradeTransitionV1]
    ) -> Bool {
        var visited: Set<String> = [source]
        var pending = [source]
        while let version = pending.first {
            pending.removeFirst()
            for transition in transitions where transition.fromVersion == version {
                if transition.toVersion == target { return true }
                if visited.insert(transition.toVersion).inserted {
                    pending.append(transition.toVersion)
                }
            }
        }
        return false
    }
}

struct DataCompatibilityManifestV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let candidateHead: String
    let supportedUpgradePaths: [SupportedUpgradePathV1]
    let internalScratchIndefiniteSupport: Bool
    let unknownVersionsFailClosed: Bool
    let writersEmitCurrentVersionsOnly: Bool

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        candidateHead: String,
        supportedUpgradePaths: [SupportedUpgradePathV1],
        internalScratchIndefiniteSupport: Bool = false,
        unknownVersionsFailClosed: Bool = true,
        writersEmitCurrentVersionsOnly: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.candidateHead = candidateHead
        self.supportedUpgradePaths = supportedUpgradePaths
        self.internalScratchIndefiniteSupport = internalScratchIndefiniteSupport
        self.unknownVersionsFailClosed = unknownVersionsFailClosed
        self.writersEmitCurrentVersionsOnly = writersEmitCurrentVersionsOnly
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion,
              CompatibilityCanonicalV1.validGitObjectID(candidateHead),
              !internalScratchIndefiniteSupport,
              unknownVersionsFailClosed,
              writersEmitCurrentVersionsOnly,
              supportedUpgradePaths.map(\.family) == CompatibilityArtifactFamilyV1.allCases,
              Set(supportedUpgradePaths.map(\.family)).count == supportedUpgradePaths.count else {
            throw CompatibilityContractErrorV1.invalidSupportTable
        }
        try supportedUpgradePaths.forEach { try $0.validate() }
    }

    func path(for family: CompatibilityArtifactFamilyV1) throws -> SupportedUpgradePathV1 {
        try validate()
        guard let path = supportedUpgradePaths.first(where: { $0.family == family }) else {
            throw CompatibilityContractErrorV1.unknownArtifactFamily
        }
        return path
    }

    func validateReadableVersion(_ version: String, for family: CompatibilityArtifactFamilyV1) throws {
        try path(for: family).validateReadableVersion(version)
    }

    func validateWriterVersion(_ version: String, for family: CompatibilityArtifactFamilyV1) throws {
        try path(for: family).validateWriterVersion(version)
    }

    func canonicalData() throws -> Data {
        try validate()
        return try CompatibilityCanonicalV1.encode(self)
    }

    func canonicalSHA256() throws -> String {
        CompatibilityCanonicalV1.sha256(try canonicalData())
    }

    static func decodeCanonical(_ data: Data) throws -> DataCompatibilityManifestV1 {
        let value: DataCompatibilityManifestV1 = try CompatibilityCanonicalV1.decode(
            DataCompatibilityManifestV1.self,
            from: data
        )
        try value.validate()
        return value
    }
}

struct ReleasedDataCompatibilityPolicyV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let candidateHead = "e576a3ca91d597fff41d0f23209bab009ff8de6b"
    static let firstPublicSealOwner = "V23-P05-C01"

    let schemaVersion: Int
    let dataManifest: DataCompatibilityManifestV1
    let skippedReleaseStoreMigrationRequired: Bool
    let immutableReleasedFixturesRequired: Bool
    let syntheticFixturesOnly: Bool
    let noCustomerData: Bool
    let noSecrets: Bool
    let appendBeforeFirstWriteRequired: Bool
    let firstPublicSealOwner: String

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        dataManifest: DataCompatibilityManifestV1,
        skippedReleaseStoreMigrationRequired: Bool = true,
        immutableReleasedFixturesRequired: Bool = true,
        syntheticFixturesOnly: Bool = true,
        noCustomerData: Bool = true,
        noSecrets: Bool = true,
        appendBeforeFirstWriteRequired: Bool = true,
        firstPublicSealOwner: String = Self.firstPublicSealOwner
    ) {
        self.schemaVersion = schemaVersion
        self.dataManifest = dataManifest
        self.skippedReleaseStoreMigrationRequired = skippedReleaseStoreMigrationRequired
        self.immutableReleasedFixturesRequired = immutableReleasedFixturesRequired
        self.syntheticFixturesOnly = syntheticFixturesOnly
        self.noCustomerData = noCustomerData
        self.noSecrets = noSecrets
        self.appendBeforeFirstWriteRequired = appendBeforeFirstWriteRequired
        self.firstPublicSealOwner = firstPublicSealOwner
    }

    static let current = ReleasedDataCompatibilityPolicyV1(
        dataManifest: DataCompatibilityManifestV1(
            candidateHead: candidateHead,
            supportedUpgradePaths: currentSupportTable
        )
    )

    /// Exact-head successor used by Card 29 and later compilers. `current`
    /// remains the immutable released C07 policy so its corpus and observable
    /// API are not rewritten in place.
    static func exactHead(candidateHead: String) -> ReleasedDataCompatibilityPolicyV1 {
        ReleasedDataCompatibilityPolicyV1(
            dataManifest: DataCompatibilityManifestV1(
                candidateHead: candidateHead,
                supportedUpgradePaths: exactHeadSupportTable
            )
        )
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion,
              skippedReleaseStoreMigrationRequired,
              immutableReleasedFixturesRequired,
              syntheticFixturesOnly,
              noCustomerData,
              noSecrets,
              appendBeforeFirstWriteRequired,
              firstPublicSealOwner == Self.firstPublicSealOwner else {
            throw CompatibilityContractErrorV1.invalidSupportTable
        }
        try dataManifest.validate()
    }

    func validateWriterEnrollment(
        family: CompatibilityArtifactFamilyV1,
        version: String,
        corpus: CompatibilityCorpusManifestV1
    ) throws {
        try validate()
        try dataManifest.validateWriterVersion(version, for: family)
        try corpus.validate(against: dataManifest)
        guard corpus.cases.contains(where: {
            $0.family == family
                && $0.artifactVersion == version
                && $0.kind == .positive
        }) else {
            throw CompatibilityContractErrorV1.missingCorpusEnrollment
        }
    }

    func canonicalData() throws -> Data {
        try validate()
        return try CompatibilityCanonicalV1.encode(self)
    }

    func canonicalSHA256() throws -> String {
        CompatibilityCanonicalV1.sha256(try canonicalData())
    }

    static func decodeCanonical(_ data: Data) throws -> ReleasedDataCompatibilityPolicyV1 {
        let value: ReleasedDataCompatibilityPolicyV1 = try CompatibilityCanonicalV1.decode(
            ReleasedDataCompatibilityPolicyV1.self,
            from: data
        )
        try value.validate()
        return value
    }

    private static let currentSupportTable: [SupportedUpgradePathV1] = [
        path(.liveStore, .publiclyPersisted, ["1.0.0", "2.0.0", "3.0.0"], "3.0.0", transitions: [
            .init(fromVersion: "1.0.0", toVersion: "2.0.0"),
            .init(fromVersion: "2.0.0", toVersion: "3.0.0"),
        ], search: .unavailableAtThisHead, rebuild: .available),
        path(.currentGenerationPointer, .publiclyPersisted, ["1", "2", "3"], "3", search: .notApplicable, rebuild: .notApplicable),
        path(.storeGenerationManifest, .publiclyPersisted, ["1"], "1", search: .notApplicable, rebuild: .notApplicable),
        path(.storeMigrationJournal, .internalRecovery, ["1"], "1", search: .notApplicable, rebuild: .notApplicable),
        path(.backupPackage, .publiclyPersisted, [
            "archive1-backup2-persistent1-records1",
            "archive1-backup2-persistent3-records2",
            "directory-v4-backup1-persistent1-records1",
        ], "archive1-backup2-persistent3-records2", search: .notApplicable, rebuild: .notApplicable),
        path(.streamingArchive, .publiclyPersisted, ["header1-index1"], "header1-index1", search: .notApplicable, rebuild: .notApplicable),
        path(.reportOpenJSON, .publiclyPersisted, ["snapshot1"], "snapshot1", search: .deferredToV23P03C09, rebuild: .notApplicable),
        path(.reportPDF, .publiclyPersisted, ["template1"], "template1", search: .deferredToV23P03C09, rebuild: .notApplicable),
        path(.finalizationIntent, .internalRecovery, ["1"], "1", search: .notApplicable, rebuild: .notApplicable),
        path(.signPack, .publiclyPersisted, ["schema1-content1"], "schema1-content1", search: .notApplicable, rebuild: .notApplicable),
        path(.durableMedia, .publiclyPersisted, ["canonical-jpeg-v1"], "canonical-jpeg-v1", search: .notApplicable, rebuild: .notApplicable),
        path(.deletionLedger, .publiclyPersisted, ["2"], "2", search: .unavailableAtThisHead, rebuild: .available),
        path(.deletionIntent, .internalRecovery, ["1", "2"], "2", search: .notApplicable, rebuild: .notApplicable),
        path(.eraseIntent, .internalRecovery, ["1", "2"], "2", search: .notApplicable, rebuild: .notApplicable),
        path(.restoreIntent, .internalRecovery, ["1", "2"], "2", search: .notApplicable, rebuild: .notApplicable),
    ]

    private static let exactHeadSupportTable: [SupportedUpgradePathV1] =
        currentSupportTable.map { value in
            switch value.family {
            case .liveStore:
                return path(.liveStore, .publiclyPersisted, [
                    "1.0.0", "2.0.0", "3.0.0", "4.0.0", "5.0.0", "6.0.0", "7.0.0", "8.0.0", "9.0.0", "10.0.0", "11.0.0", "12.0.0", "13.0.0", "14.0.0", "15.0.0",
                ], "15.0.0", transitions: [
                    .init(fromVersion: "1.0.0", toVersion: "2.0.0"),
                    .init(fromVersion: "2.0.0", toVersion: "3.0.0"),
                    .init(fromVersion: "3.0.0", toVersion: "4.0.0"),
                    .init(fromVersion: "4.0.0", toVersion: "5.0.0"),
                    .init(fromVersion: "5.0.0", toVersion: "6.0.0"),
                    .init(fromVersion: "6.0.0", toVersion: "7.0.0"),
                    .init(fromVersion: "7.0.0", toVersion: "8.0.0"),
                    .init(fromVersion: "8.0.0", toVersion: "9.0.0"),
                    .init(fromVersion: "9.0.0", toVersion: "10.0.0"),
                    .init(fromVersion: "10.0.0", toVersion: "11.0.0"),
                    .init(fromVersion: "11.0.0", toVersion: "12.0.0"),
                    .init(fromVersion: "12.0.0", toVersion: "13.0.0"),
                    .init(fromVersion: "13.0.0", toVersion: "14.0.0"),
                    .init(fromVersion: "14.0.0", toVersion: "15.0.0"),
                ], search: .available, rebuild: .available)
            case .backupPackage:
                return path(.backupPackage, .publiclyPersisted, [
                    "archive1-backup2-persistent1-records1",
                    "archive1-backup2-persistent3-records2",
                    "archive1-backup4-persistent5-records4",
                    "archive1-backup4-persistent6-records5",
                    "archive1-backup4-persistent7-records6",
                    "archive1-backup4-persistent9-records8",
                    "archive1-backup4-persistent10-records9",
                    "archive1-backup4-persistent11-records10",
                    "archive1-backup4-persistent12-records11",
                    "archive1-backup4-persistent13-records12",
                    "archive1-backup4-persistent14-records13",
                    "archive1-backup4-persistent15-records14",
                    "directory-v4-backup1-persistent1-records1",
                ], "archive1-backup4-persistent15-records14",
                search: .available, rebuild: .available)
            case .reportOpenJSON:
                return path(.reportOpenJSON, .publiclyPersisted,
                    ["snapshot1", "snapshot2", "snapshot3", "snapshot4"], "snapshot4",
                    search: .deferredToV23P03C09, rebuild: .notApplicable)
            default:
                return value
            }
        }

    private static func path(
        _ family: CompatibilityArtifactFamilyV1,
        _ persistence: CompatibilityPersistenceDispositionV1,
        _ readableVersions: [String],
        _ currentWriterVersion: String,
        transitions: [SupportedUpgradeTransitionV1] = [],
        search: CompatibilityCapabilityDispositionV1,
        rebuild: CompatibilityCapabilityDispositionV1
    ) -> SupportedUpgradePathV1 {
        SupportedUpgradePathV1(
            family: family,
            persistence: persistence,
            readableVersions: readableVersions.sorted(),
            currentWriterVersion: currentWriterVersion,
            forwardUpgradeTransitions: transitions,
            searchDisposition: search,
            rebuildDisposition: rebuild
        )
    }
}

/// C15's V15 coordination contract is an additive compatibility successor.
/// Released C07 values remain available through `current`; this policy only
/// describes the provisional V15 writer and its pre-activation downgrade
/// boundary.
enum WorkPacketCompatibilityPolicyV1 {
    static let persistentSchemaVersion = 15
    static let recordsSchemaVersion = 14
    static let persistentContractSchema = "PERSISTENT_SCHEMA_V15_WORK_PACKET_COORDINATION"
    static let currentPersistentWriterVersion = "15.0.0"
    static let currentBackupWriterVersion = "archive1-backup4-persistent15-records14"
    static let readablePersistentWriterVersions = [
        "1.0.0", "2.0.0", "3.0.0", "4.0.0", "5.0.0", "6.0.0", "7.0.0",
        "8.0.0", "9.0.0", "10.0.0", "11.0.0", "12.0.0", "13.0.0",
        "14.0.0", "15.0.0",
    ]
    static let readableBackupWriterVersions = [
        "archive1-backup2-persistent1-records1",
        "archive1-backup2-persistent3-records2",
        "archive1-backup4-persistent5-records4",
        "archive1-backup4-persistent6-records5",
        "archive1-backup4-persistent7-records6",
        "archive1-backup4-persistent9-records8",
        "archive1-backup4-persistent10-records9",
        "archive1-backup4-persistent11-records10",
        "archive1-backup4-persistent12-records11",
        "archive1-backup4-persistent13-records12",
        "archive1-backup4-persistent14-records13",
        "archive1-backup4-persistent15-records14",
        "directory-v4-backup1-persistent1-records1",
    ]
    static let downgradeDisposition =
        "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V15_WRITE"
    static let migrationRequired = true
    static let backupRequired = true
    static let restoreRequired = true
    static let importRequired = true
    static let exportRequired = true
    static let deleteRequired = true
    static let eraseRequired = true
    static let replayRequired = true
    static let searchRequired = true
    static let reportRequired = true
    static let requiresAcceptedS10_6Reconciliation = true
    static let nativeCompileRan = false
    static let hostedDispatchEnabled = false
    static let adoptionEnabled = false
    static let acceptanceEnabled = false
    static let acceptanceCredit = false
    static let releaseCredit = false

    static func validate() throws {
        guard persistentSchemaVersion == 15,
              recordsSchemaVersion == 14,
              persistentContractSchema
                  == "PERSISTENT_SCHEMA_V15_WORK_PACKET_COORDINATION",
              currentPersistentWriterVersion
                  == readablePersistentWriterVersions.last,
              currentBackupWriterVersion
                  == readableBackupWriterVersions[
                      readableBackupWriterVersions.count - 2
                  ],
              readablePersistentWriterVersions
                  == readablePersistentWriterVersions.sorted(),
              Set(readablePersistentWriterVersions).count
                  == readablePersistentWriterVersions.count,
              Set(readableBackupWriterVersions).count
                  == readableBackupWriterVersions.count,
              downgradeDisposition
                  == "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V15_WRITE",
              migrationRequired,
              backupRequired,
              restoreRequired,
              importRequired,
              exportRequired,
              deleteRequired,
              eraseRequired,
              replayRequired,
              searchRequired,
              reportRequired,
              requiresAcceptedS10_6Reconciliation,
              !nativeCompileRan,
              !hostedDispatchEnabled,
              !adoptionEnabled,
              !acceptanceEnabled,
              !acceptanceCredit,
              !releaseCredit else {
            throw CompatibilityContractErrorV1.invalidSupportTable
        }
    }

    static func acceptsPersistentWriterVersion(_ version: String) -> Bool {
        (try? validate()) != nil
            && readablePersistentWriterVersions.contains(version)
    }

    static func acceptsBackupWriterVersion(_ version: String) -> Bool {
        (try? validate()) != nil
            && readableBackupWriterVersions.contains(version)
    }
}

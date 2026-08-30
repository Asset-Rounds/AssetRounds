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
                    "1.0.0", "2.0.0", "3.0.0", "4.0.0", "5.0.0", "6.0.0", "7.0.0", "8.0.0", "9.0.0", "10.0.0", "11.0.0", "12.0.0", "13.0.0", "14.0.0", "15.0.0", "16.0.0",
                ], "16.0.0", transitions: [
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
                    .init(fromVersion: "15.0.0", toVersion: "16.0.0"),
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
                    "archive1-backup4-persistent16-records15",
                    "directory-v4-backup1-persistent1-records1",
                ], "archive1-backup4-persistent16-records15",
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

enum FieldDraftCompatibilityPolicyV1 {
    static let persistentSchemaVersion=16,recordsSchemaVersion=15
    static let persistentContractSchema="PERSISTENT_SCHEMA_V16_FIELD_DRAFT_RESILIENCE"
    static let currentPersistentWriterVersion="16.0.0"
    static let currentBackupWriterVersion="archive1-backup4-persistent16-records15"
    static let readablePersistentWriterVersions=["1.0.0","2.0.0","3.0.0","4.0.0","5.0.0","6.0.0","7.0.0","8.0.0","9.0.0","10.0.0","11.0.0","12.0.0","13.0.0","14.0.0","15.0.0","16.0.0"]
    static let readableBackupWriterVersions=["archive1-backup2-persistent1-records1","archive1-backup2-persistent3-records2","archive1-backup4-persistent5-records4","archive1-backup4-persistent6-records5","archive1-backup4-persistent7-records6","archive1-backup4-persistent9-records8","archive1-backup4-persistent10-records9","archive1-backup4-persistent11-records10","archive1-backup4-persistent12-records11","archive1-backup4-persistent13-records12","archive1-backup4-persistent14-records13","archive1-backup4-persistent15-records14","archive1-backup4-persistent16-records15","directory-v4-backup1-persistent1-records1"]
    static let downgradeDisposition="PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V16_WRITE"
    static func validate()throws{guard persistentSchemaVersion==16,recordsSchemaVersion==15,persistentContractSchema==PersistentSchemaReleaseV1.v16.compatibilityID,currentPersistentWriterVersion==readablePersistentWriterVersions.last,currentBackupWriterVersion==readableBackupWriterVersions[readableBackupWriterVersions.count-2],Set(readablePersistentWriterVersions).count==readablePersistentWriterVersions.count,Set(readableBackupWriterVersions).count==readableBackupWriterVersions.count,downgradeDisposition=="PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V16_WRITE"else{throw CompatibilityContractErrorV1.invalidSupportTable}}
    static func acceptsPersistentWriterVersion(_ version:String)->Bool{(try? validate()) != nil&&readablePersistentWriterVersions.contains(version)}
    static func acceptsBackupWriterVersion(_ version:String)->Bool{(try? validate()) != nil&&readableBackupWriterVersions.contains(version)}
}

/// C18's package-evolution rows are a new V17/records-16 durable family. The
/// compatibility surface is intentionally separate from the released-data
/// artifact-family table: old reports remain readable, while unknown package
/// evolution writers and post-activation downgrades fail closed.
struct PackageEvolutionCompatibilityV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let persistentSchemaVersion = 17
    static let recordsSchemaVersion = 16
    static let persistentContractSchema = PersistentSchemaReleaseV1.v17.compatibilityID
    static let currentWriterVersion = "PACKAGE_EVOLUTION_WRITER_V1"

    let schemaVersion: Int
    let persistentSchemaVersion: Int
    let recordsSchemaVersion: Int
    let persistentContractSchema: String
    let readableWriterVersions: [String]
    let currentWriterVersion: String
    let unknownVersionsFailClosed: Bool
    let preActivationDowngradeAllowed: Bool
    let postActivationRequiresForwardFix: Bool
    let derivedSearchDropsAndRebuilds: Bool
    let historicalReportsPinFrozenReleaseIdentity: Bool

    init(
        readableWriterVersions: [String] = ["PACKAGE_EVOLUTION_WRITER_V1"],
        preActivationDowngradeAllowed: Bool = true,
        postActivationRequiresForwardFix: Bool = true
    ) {
        schemaVersion = Self.schemaVersion
        persistentSchemaVersion = Self.persistentSchemaVersion
        recordsSchemaVersion = Self.recordsSchemaVersion
        persistentContractSchema = Self.persistentContractSchema
        self.readableWriterVersions = readableWriterVersions.sorted()
        currentWriterVersion = Self.currentWriterVersion
        unknownVersionsFailClosed = true
        self.preActivationDowngradeAllowed = preActivationDowngradeAllowed
        self.postActivationRequiresForwardFix = postActivationRequiresForwardFix
        derivedSearchDropsAndRebuilds = true
        historicalReportsPinFrozenReleaseIdentity = true
    }

    static let current = Self()

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              persistentSchemaVersion == Self.persistentSchemaVersion,
              recordsSchemaVersion == Self.recordsSchemaVersion,
              persistentContractSchema == Self.persistentContractSchema,
              readableWriterVersions == readableWriterVersions.sorted(),
              !readableWriterVersions.isEmpty,
              readableWriterVersions.contains(currentWriterVersion),
              currentWriterVersion == Self.currentWriterVersion,
              unknownVersionsFailClosed,
              preActivationDowngradeAllowed,
              postActivationRequiresForwardFix,
              derivedSearchDropsAndRebuilds,
              historicalReportsPinFrozenReleaseIdentity else {
            throw CompatibilityContractErrorV1.invalidSupportTable
        }
    }

    func validateWriterVersion(_ version: String) throws {
        try validate()
        guard readableWriterVersions.contains(version) else {
            throw CompatibilityContractErrorV1.unsupportedVersion
        }
        guard version == currentWriterVersion else {
            throw CompatibilityContractErrorV1.noncurrentWriterVersion
        }
    }

    func validateStorage(schemaVersion: Int, recordsSchemaVersion: Int) throws {
        try validate()
        guard schemaVersion == persistentSchemaVersion,
              recordsSchemaVersion == Self.recordsSchemaVersion else {
            throw CompatibilityContractErrorV1.unsupportedVersion
        }
    }
}

extension ReleasedDataCompatibilityPolicyV1 {
    static let packageEvolutionCompatibility = PackageEvolutionCompatibilityV1.current
}

/// C19's V18/records-17 compatibility contract is additive to the released
/// artifact-family table. Historical reports remain readable as frozen data;
/// derived search metadata is always dropped and rebuilt from canonical
/// measurement snapshots.
struct MeasurementIntegrityCompatibilityPolicyV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let persistentSchemaVersion = 18
    static let recordsSchemaVersion = 17
    static let persistentContractSchema = PersistentSchemaReleaseV1.v18.compatibilityID
    static let currentPersistentWriterVersion = "18.0.0"
    static let currentBackupWriterVersion = "archive1-backup4-persistent18-records17"
    static let readablePersistentWriterVersions = [
        "1.0.0", "2.0.0", "3.0.0", "4.0.0", "5.0.0", "6.0.0", "7.0.0",
        "8.0.0", "9.0.0", "10.0.0", "11.0.0", "12.0.0", "13.0.0",
        "14.0.0", "15.0.0", "16.0.0", "17.0.0", "18.0.0",
    ]
    static let readableBackupWriterVersions = [
        "archive1-backup4-persistent17-records16",
        "archive1-backup4-persistent18-records17",
    ]
    static let downgradeDisposition =
        "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_ACTIVATION"

    let schemaVersion: Int
    let persistentSchemaVersion: Int
    let recordsSchemaVersion: Int
    let persistentContractSchema: String
    let currentPersistentWriterVersion: String
    let currentBackupWriterVersion: String
    let readablePersistentWriterVersions: [String]
    let readableBackupWriterVersions: [String]
    let downgradeDisposition: String
    let historicalReportsPinFrozenCaptureAndCalibration: Bool
    let derivedSearchDropsAndRebuilds: Bool
    let unknownVersionsFailClosed: Bool

    init() {
        schemaVersion = Self.schemaVersion
        persistentSchemaVersion = Self.persistentSchemaVersion
        recordsSchemaVersion = Self.recordsSchemaVersion
        persistentContractSchema = Self.persistentContractSchema
        currentPersistentWriterVersion = Self.currentPersistentWriterVersion
        currentBackupWriterVersion = Self.currentBackupWriterVersion
        readablePersistentWriterVersions = Self.readablePersistentWriterVersions
        readableBackupWriterVersions = Self.readableBackupWriterVersions
        downgradeDisposition = Self.downgradeDisposition
        historicalReportsPinFrozenCaptureAndCalibration = true
        derivedSearchDropsAndRebuilds = true
        unknownVersionsFailClosed = true
    }

    static let current = Self()

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              persistentSchemaVersion == Self.persistentSchemaVersion,
              recordsSchemaVersion == Self.recordsSchemaVersion,
              persistentContractSchema == Self.persistentContractSchema,
              currentPersistentWriterVersion == Self.currentPersistentWriterVersion,
              currentBackupWriterVersion == Self.currentBackupWriterVersion,
              readablePersistentWriterVersions == Self.readablePersistentWriterVersions,
              readableBackupWriterVersions == Self.readableBackupWriterVersions,
              readablePersistentWriterVersions.contains(currentPersistentWriterVersion),
              readableBackupWriterVersions.contains(currentBackupWriterVersion),
              downgradeDisposition == Self.downgradeDisposition,
              historicalReportsPinFrozenCaptureAndCalibration,
              derivedSearchDropsAndRebuilds,
              unknownVersionsFailClosed else {
            throw CompatibilityContractErrorV1.invalidSupportTable
        }
    }

    static func acceptsPersistentWriterVersion(_ version: String) -> Bool {
        (try? current.validate()) != nil
            && current.readablePersistentWriterVersions.contains(version)
    }

    static func acceptsBackupWriterVersion(_ version: String) -> Bool {
        (try? current.validate()) != nil
            && current.readableBackupWriterVersions.contains(version)
    }
}

extension ReleasedDataCompatibilityPolicyV1 {
    static let measurementIntegrityCompatibility = MeasurementIntegrityCompatibilityPolicyV1.current
}

/// C20 adds the V19 privacy-transform rows while keeping report readers and
/// pre-V23 history compatible. Privacy-transform search remains disposable and
/// is rebuilt from approved projections after restore/replay/downgrade.
struct PrivacyTransformCompatibilityPolicyV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let persistentSchemaVersion = 19
    static let recordsSchemaVersion = 18
    static let persistentContractSchema = PersistentSchemaReleaseV1.v19.compatibilityID
    static let currentPersistentWriterVersion = "19.0.0"
    static let currentBackupWriterVersion = "archive1-backup4-persistent19-records18"
    static let readablePersistentWriterVersions = [
        "1.0.0", "2.0.0", "3.0.0", "4.0.0", "5.0.0", "6.0.0", "7.0.0",
        "8.0.0", "9.0.0", "10.0.0", "11.0.0", "12.0.0", "13.0.0",
        "14.0.0", "15.0.0", "16.0.0", "17.0.0", "18.0.0", "19.0.0",
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
        "archive1-backup4-persistent16-records15",
        "archive1-backup4-persistent17-records16",
        "archive1-backup4-persistent18-records17",
        "archive1-backup4-persistent19-records18",
        "directory-v4-backup1-persistent1-records1",
    ]
    static let downgradeDisposition =
        "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_ACTIVATION"

    let schemaVersion: Int
    let persistentSchemaVersion: Int
    let recordsSchemaVersion: Int
    let persistentContractSchema: String
    let currentPersistentWriterVersion: String
    let currentBackupWriterVersion: String
    let readablePersistentWriterVersions: [String]
    let readableBackupWriterVersions: [String]
    let downgradeDisposition: String
    let historicalReportsRemainFrozen: Bool
    let derivedSearchDropsAndRebuilds: Bool
    let unknownVersionsFailClosed: Bool

    init() {
        schemaVersion = Self.schemaVersion
        persistentSchemaVersion = Self.persistentSchemaVersion
        recordsSchemaVersion = Self.recordsSchemaVersion
        persistentContractSchema = Self.persistentContractSchema
        currentPersistentWriterVersion = Self.currentPersistentWriterVersion
        currentBackupWriterVersion = Self.currentBackupWriterVersion
        readablePersistentWriterVersions = Self.readablePersistentWriterVersions
        readableBackupWriterVersions = Self.readableBackupWriterVersions
        downgradeDisposition = Self.downgradeDisposition
        historicalReportsRemainFrozen = true
        derivedSearchDropsAndRebuilds = true
        unknownVersionsFailClosed = true
    }

    static let current = Self()

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              persistentSchemaVersion == Self.persistentSchemaVersion,
              recordsSchemaVersion == Self.recordsSchemaVersion,
              persistentContractSchema == Self.persistentContractSchema,
              currentPersistentWriterVersion == Self.currentPersistentWriterVersion,
              currentBackupWriterVersion == Self.currentBackupWriterVersion,
              readablePersistentWriterVersions == Self.readablePersistentWriterVersions,
              readableBackupWriterVersions == Self.readableBackupWriterVersions,
              readablePersistentWriterVersions.contains(currentPersistentWriterVersion),
              readableBackupWriterVersions.contains(currentBackupWriterVersion),
              downgradeDisposition == Self.downgradeDisposition,
              historicalReportsRemainFrozen,
              derivedSearchDropsAndRebuilds,
              unknownVersionsFailClosed else {
            throw CompatibilityContractErrorV1.invalidSupportTable
        }
    }

    static func acceptsPersistentWriterVersion(_ version: String) -> Bool {
        (try? current.validate()) != nil
            && current.readablePersistentWriterVersions.contains(version)
    }

    static func acceptsBackupWriterVersion(_ version: String) -> Bool {
        (try? current.validate()) != nil
            && current.readableBackupWriterVersions.contains(version)
    }
}

extension ReleasedDataCompatibilityPolicyV1 {
    static let privacyTransformCompatibility = PrivacyTransformCompatibilityPolicyV1.current
}

/// C21 enrolls the V20 client-capability/package-lifecycle writer while
/// retaining readers for all released predecessors. Capability and lifecycle
/// search rows remain derived and are dropped/rebuilt; finalized reports keep
/// their frozen display and remain exportable after withdrawal.
struct ClientCapabilityCompatibilityPolicyV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let persistentSchemaVersion = 20
    static let recordsSchemaVersion = 19
    static let persistentContractSchema = PersistentSchemaReleaseV1.v20.compatibilityID
    static let currentPersistentWriterVersion = "20.0.0"
    static let currentBackupWriterVersion = "archive1-backup4-persistent20-records19"
    static let readablePersistentWriterVersions = [
        "1.0.0", "2.0.0", "3.0.0", "4.0.0", "5.0.0", "6.0.0", "7.0.0",
        "8.0.0", "9.0.0", "10.0.0", "11.0.0", "12.0.0", "13.0.0",
        "14.0.0", "15.0.0", "16.0.0", "17.0.0", "18.0.0", "19.0.0",
        "20.0.0",
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
        "archive1-backup4-persistent16-records15",
        "archive1-backup4-persistent17-records16",
        "archive1-backup4-persistent18-records17",
        "archive1-backup4-persistent19-records18",
        "archive1-backup4-persistent20-records19",
        "directory-v4-backup1-persistent1-records1",
    ]
    static let downgradeDisposition =
        "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V20_WRITE"

    let schemaVersion: Int
    let persistentSchemaVersion: Int
    let recordsSchemaVersion: Int
    let persistentContractSchema: String
    let currentPersistentWriterVersion: String
    let currentBackupWriterVersion: String
    let readablePersistentWriterVersions: [String]
    let readableBackupWriterVersions: [String]
    let downgradeDisposition: String
    let historicalReportsRemainFrozen: Bool
    let historicFinalizedArtifactsExportAfterWithdrawal: Bool
    let withdrawalBlocksNewWork: Bool
    let derivedSearchDropsAndRebuilds: Bool
    let unknownVersionsFailClosed: Bool

    init() {
        schemaVersion = Self.schemaVersion
        persistentSchemaVersion = Self.persistentSchemaVersion
        recordsSchemaVersion = Self.recordsSchemaVersion
        persistentContractSchema = Self.persistentContractSchema
        currentPersistentWriterVersion = Self.currentPersistentWriterVersion
        currentBackupWriterVersion = Self.currentBackupWriterVersion
        readablePersistentWriterVersions = Self.readablePersistentWriterVersions
        readableBackupWriterVersions = Self.readableBackupWriterVersions
        downgradeDisposition = Self.downgradeDisposition
        historicalReportsRemainFrozen = true
        historicFinalizedArtifactsExportAfterWithdrawal = true
        withdrawalBlocksNewWork = true
        derivedSearchDropsAndRebuilds = true
        unknownVersionsFailClosed = true
    }

    static let current = Self()

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              persistentSchemaVersion == Self.persistentSchemaVersion,
              recordsSchemaVersion == Self.recordsSchemaVersion,
              persistentContractSchema == Self.persistentContractSchema,
              currentPersistentWriterVersion == Self.currentPersistentWriterVersion,
              currentBackupWriterVersion == Self.currentBackupWriterVersion,
              readablePersistentWriterVersions == Self.readablePersistentWriterVersions,
              readableBackupWriterVersions == Self.readableBackupWriterVersions,
              readablePersistentWriterVersions.contains(currentPersistentWriterVersion),
              readableBackupWriterVersions.contains(currentBackupWriterVersion),
              downgradeDisposition == Self.downgradeDisposition,
              historicalReportsRemainFrozen,
              historicFinalizedArtifactsExportAfterWithdrawal,
              withdrawalBlocksNewWork,
              derivedSearchDropsAndRebuilds,
              unknownVersionsFailClosed else {
            throw CompatibilityContractErrorV1.invalidSupportTable
        }
    }

    static func acceptsPersistentWriterVersion(_ version: String) -> Bool {
        (try? current.validate()) != nil
            && current.readablePersistentWriterVersions.contains(version)
    }

    static func acceptsBackupWriterVersion(_ version: String) -> Bool {
        (try? current.validate()) != nil
            && current.readableBackupWriterVersions.contains(version)
    }
}

extension ReleasedDataCompatibilityPolicyV1 {
    static let clientCapabilityCompatibility = ClientCapabilityCompatibilityPolicyV1.current
}

struct FieldReferencePackCompatibilityPolicyV1:Codable,Equatable,Sendable{
    static let persistentSchemaVersion=22,recordsSchemaVersion=21
    static let persistentContractSchema=PersistentSchemaReleaseV1.v22.compatibilityID
    static let currentPersistentWriterVersion="22.0.0"
    static let currentBackupWriterVersion="archive1-backup4-persistent22-records21"
    static let readablePersistentWriterVersions=(1...22).map{"\($0).0.0"}
    static let readableBackupWriterVersions=ClientCapabilityCompatibilityPolicyV1.readableBackupWriterVersions+["archive1-backup4-persistent21-records20",currentBackupWriterVersion]
    static let downgradeDisposition="PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V22_WRITE"
    let persistentSchemaVersion:Int;let recordsSchemaVersion:Int;let persistentContractSchema:String;let currentPersistentWriterVersion:String;let currentBackupWriterVersion:String;let readablePersistentWriterVersions:[String];let readableBackupWriterVersions:[String];let downgradeDisposition:String;let stagingIsNonpersistent:Bool
    init(){persistentSchemaVersion=Self.persistentSchemaVersion;recordsSchemaVersion=Self.recordsSchemaVersion;persistentContractSchema=Self.persistentContractSchema;currentPersistentWriterVersion=Self.currentPersistentWriterVersion;currentBackupWriterVersion=Self.currentBackupWriterVersion;readablePersistentWriterVersions=Self.readablePersistentWriterVersions;readableBackupWriterVersions=Self.readableBackupWriterVersions;downgradeDisposition=Self.downgradeDisposition;stagingIsNonpersistent=true}
    static let current=Self()
    func validate()throws{guard persistentSchemaVersion==22,recordsSchemaVersion==21,persistentContractSchema==PersistentSchemaReleaseV1.v22.compatibilityID,currentPersistentWriterVersion==readablePersistentWriterVersions.last,currentBackupWriterVersion==readableBackupWriterVersions.last,Set(readablePersistentWriterVersions).count==readablePersistentWriterVersions.count,Set(readableBackupWriterVersions).count==readableBackupWriterVersions.count,downgradeDisposition==Self.downgradeDisposition,stagingIsNonpersistent else{throw CompatibilityContractErrorV1.invalidSupportTable}}
}

extension ReleasedDataCompatibilityPolicyV1{static let fieldReferencePackCompatibility=FieldReferencePackCompatibilityPolicyV1.current}

struct AccessibleDocumentCompatibilityPolicyV1:Codable,Equatable,Sendable{
    static let persistentSchemaVersion=23,recordsSchemaVersion=22
    static let currentPersistentWriterVersion="23.0.0",currentBackupWriterVersion="archive1-backup4-persistent23-records22"
    static let downgradeDisposition="PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V23_WRITE_NO_ACCEPTED_RECEIPT_REWRITE"
    let semanticTreePersistence="DERIVED_ONLY";let acceptedReceiptPreserved=true;let unknownVersionsFailClosed=true
    static let current=Self()
    func validate()throws{guard semanticTreePersistence==AccessibleDocumentLifecycleV1.semanticTreePersistence,acceptedReceiptPreserved,unknownVersionsFailClosed else{throw CompatibilityContractErrorV1.invalidSupportTable}}
}
extension ReleasedDataCompatibilityPolicyV1{static let accessibleDocumentCompatibility=AccessibleDocumentCompatibilityPolicyV1.current}

struct SurveyDefinitionCompatibilityPolicyV1:Codable,Equatable,Sendable{
    static let persistentSchemaVersion=24,recordsSchemaVersion=23
    static let currentPersistentWriterVersion="24.0.0",currentBackupWriterVersion="archive1-backup4-persistent24-records23"
    static let readablePersistentWriterVersions=(1...24).map{"\($0).0.0"}
    static let readableBackupWriterVersions=FieldReferencePackCompatibilityPolicyV1.readableBackupWriterVersions+["archive1-backup4-persistent23-records22",currentBackupWriterVersion]
    static let current=Self()
    func validate()throws{guard Self.readablePersistentWriterVersions.last==Self.currentPersistentWriterVersion,Self.readableBackupWriterVersions.last==Self.currentBackupWriterVersion,Set(Self.readableBackupWriterVersions).count==Self.readableBackupWriterVersions.count else{throw CompatibilityContractErrorV1.invalidSupportTable}}
}
extension ReleasedDataCompatibilityPolicyV1{static let surveyDefinitionCompatibility=SurveyDefinitionCompatibilityPolicyV1.current}

struct SurveySessionCompatibilityPolicyV1:Codable,Equatable,Sendable{
    static let persistentSchemaVersion=25,recordsSchemaVersion=24
    static let currentPersistentWriterVersion="25.0.0",currentBackupWriterVersion="archive1-backup4-persistent25-records24"
    static let readablePersistentWriterVersions=(1...25).map{"\($0).0.0"}
    static let readableBackupWriterVersions=SurveyDefinitionCompatibilityPolicyV1.readableBackupWriterVersions+[currentBackupWriterVersion]
    static let downgradeDisposition="PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V25_WRITE"
    let stagingIsNonpersistent=true;let publicationSnapshotsRemainFrozen=true;let unknownVersionsFailClosed=true
    static let current=Self()
    func validate()throws{guard Set(Self.readablePersistentWriterVersions).count==25,Self.readablePersistentWriterVersions.last==Self.currentPersistentWriterVersion,Set(Self.readableBackupWriterVersions).count==Self.readableBackupWriterVersions.count,Self.readableBackupWriterVersions.last==Self.currentBackupWriterVersion,stagingIsNonpersistent,publicationSnapshotsRemainFrozen,unknownVersionsFailClosed else{throw CompatibilityContractErrorV1.invalidSupportTable}}
}
extension ReleasedDataCompatibilityPolicyV1{static let surveySessionCompatibility=SurveySessionCompatibilityPolicyV1.current}

struct AssetLocatorCompatibilityPolicyV1:Codable,Equatable,Sendable{
    static let persistentSchemaVersion=26,recordsSchemaVersion=25
    static let currentPersistentWriterVersion="26.0.0",currentBackupWriterVersion="archive1-backup4-persistent26-records25"
    static let readablePersistentWriterVersions=(1...26).map{"\($0).0.0"}
    static let readableBackupWriterVersions=SurveySessionCompatibilityPolicyV1.readableBackupWriterVersions+[currentBackupWriterVersion]
    static let downgradeDisposition="PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V26_WRITE"
    let resolutionAndPreviewPersistence="DERIVED_ONLY";let historicalLocatorEvidencePreserved=true;let unknownVersionsFailClosed=true
    static let current=Self()
    func validate()throws{guard Set(Self.readablePersistentWriterVersions).count==26,Self.readablePersistentWriterVersions.last==Self.currentPersistentWriterVersion,Set(Self.readableBackupWriterVersions).count==Self.readableBackupWriterVersions.count,Self.readableBackupWriterVersions.last==Self.currentBackupWriterVersion,resolutionAndPreviewPersistence=="DERIVED_ONLY",historicalLocatorEvidencePreserved,unknownVersionsFailClosed else{throw CompatibilityContractErrorV1.invalidSupportTable}}
}
extension ReleasedDataCompatibilityPolicyV1{static let assetLocatorCompatibility=AssetLocatorCompatibilityPolicyV1.current}

struct ScheduleCompatibilityPolicyV1:Codable,Equatable,Sendable{
    static let persistentSchemaVersion=27,recordsSchemaVersion=26
    static let currentPersistentWriterVersion="27.0.0",currentBackupWriterVersion="archive1-backup4-persistent27-records26"
    static let readablePersistentWriterVersions=(1...27).map{"\($0).0.0"}
    static let readableBackupWriterVersions=AssetLocatorCompatibilityPolicyV1.readableBackupWriterVersions+[currentBackupWriterVersion]
    static let downgradeDisposition="PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V27_WRITE"
    let exceptionPersistence="EMBEDDED_HISTORY_PAYLOAD_ONLY";let dueAndReminderPersistence="DERIVED_ONLY";let unknownVersionsFailClosed=true
    static let current=Self()
    func validate()throws{guard Set(Self.readablePersistentWriterVersions).count==27,Self.readablePersistentWriterVersions.last==Self.currentPersistentWriterVersion,Set(Self.readableBackupWriterVersions).count==Self.readableBackupWriterVersions.count,Self.readableBackupWriterVersions.last==Self.currentBackupWriterVersion,exceptionPersistence=="EMBEDDED_HISTORY_PAYLOAD_ONLY",dueAndReminderPersistence=="DERIVED_ONLY",unknownVersionsFailClosed else{throw CompatibilityContractErrorV1.invalidSupportTable}}
}
extension ReleasedDataCompatibilityPolicyV1{static let scheduleCompatibility=ScheduleCompatibilityPolicyV1.current}
struct PlanCompatibilityPolicyV1:Codable,Equatable,Sendable{static let persistentSchemaVersion=28,recordsSchemaVersion=27;static let currentPersistentWriterVersion="28.0.0",currentBackupWriterVersion="archive1-backup4-persistent28-records27";static let readablePersistentWriterVersions=(1...28).map{"\($0).0.0"};static let readableBackupWriterVersions=ScheduleCompatibilityPolicyV1.readableBackupWriterVersions+[currentBackupWriterVersion];static let downgradeDisposition="PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V28_WRITE";let durableFamilies=["PlanDocumentRow","PlanRevisionRow","PlanPlacementRow","RebaseReceiptRow"];let spatialFrames="EMBEDDED_IN_PLAN_REVISION";let rebasePreview="DERIVED_ONLY";let unknownVersionsFailClosed=true;static let current=Self();func validate()throws{guard durableFamilies.count==4,Set(durableFamilies).count==4,spatialFrames=="EMBEDDED_IN_PLAN_REVISION",rebasePreview=="DERIVED_ONLY",Self.readablePersistentWriterVersions.last==Self.currentPersistentWriterVersion,Self.readableBackupWriterVersions.last==Self.currentBackupWriterVersion,unknownVersionsFailClosed else{throw CompatibilityContractErrorV1.invalidSupportTable}}}
extension ReleasedDataCompatibilityPolicyV1{static let planCompatibility=PlanCompatibilityPolicyV1.current}
struct PlacementPoseCompatibilityPolicyV1:Codable,Equatable,Sendable{static let persistentSchemaVersion=29,recordsSchemaVersion=28;static let currentPersistentWriterVersion="29.0.0",currentBackupWriterVersion="archive1-backup4-persistent29-records28";static let readablePersistentWriterVersions=(1...29).map{"\($0).0.0"};static let readableBackupWriterVersions=PlanCompatibilityPolicyV1.readableBackupWriterVersions+[currentBackupWriterVersion];static let downgradeDisposition="PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V29_WRITE";let durableFamilies=["AssetPoseEventRow","SpatialAnchorObservationRow"];let derivedKinds=["PoseAxisDescriptorRegistryV1","AssetPoseCurrentTipV1","CompletedPlacementPoseSnapshotV1"];let unknownVersionsFailClosed=true;static let current=Self();func validate()throws{guard durableFamilies.count==2,Set(durableFamilies).count==2,derivedKinds.count==3,Self.readablePersistentWriterVersions.last==Self.currentPersistentWriterVersion,Self.readableBackupWriterVersions.last==Self.currentBackupWriterVersion,unknownVersionsFailClosed else{throw CompatibilityContractErrorV1.invalidSupportTable}}}

extension ReleasedDataCompatibilityPolicyV1{static let placementPoseCompatibility=PlacementPoseCompatibilityPolicyV1.current}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Domain_Compatibility_ReleasedDataCompatibilityPolicyV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Domain/Compatibility/ReleasedDataCompatibilityPolicyV1.swift", role: .compatibility)
}

struct C31LightingCompatibilityPolicyV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let currentLightingProjection = "C31_LIGHTING_REPORT_PROJECTION_V1"
    let historicProjectionReadable: Bool
    let unknownProjectionFailsClosed: Bool
    let displayInterpretationImmutable: Bool
    let migrationDisposition: String

    init() {
        schemaVersion = Self.schemaVersion
        historicProjectionReadable = true
        unknownProjectionFailsClosed = true
        displayInterpretationImmutable = true
        migrationDisposition = "READ_HISTORIC_OR_AMEND_WITH_REPLACEMENT"
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              currentLightingProjection == "C31_LIGHTING_REPORT_PROJECTION_V1",
              historicProjectionReadable, unknownProjectionFailsClosed,
              displayInterpretationImmutable,
              migrationDisposition == "READ_HISTORIC_OR_AMEND_WITH_REPLACEMENT" else {
            throw CompatibilityContractErrorV1.invalidSupportTable
        }
    }
}

extension ReleasedDataCompatibilityPolicyV1 {
    static let lightingCompatibility = C31LightingCompatibilityPolicyV1()
}
// MARK: - C32 assistance released-data compatibility boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_Compatibility_ReleasedDataCompatibilityPolicyV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let releasedDataCarriesReceiptNotProposal = true

    static func validateProposal(_ proposal: AssistanceProposalV1, in context: AssistanceProposalEvaluationContextV1) throws {
        try proposal.validate()
        try context.validate()
        guard proposal.verificationState.rawValue == AssistanceProposalVerificationStateV1.unverified.rawValue,
              context.policy.manualFallback == .typeManually else {
            throw AssistanceContractFailureV1.incompatibleCapability
        }
        if let reason = try proposal.expiryReason(in: context) {
            throw AssistanceContractFailureV1.expired(reason)
        }
    }

    static func validateAcceptanceReceipt(_ receipt: AssistanceAcceptanceReceiptV1) throws {
        try receipt.validate()
    }
}

struct TemporalEvidenceCompatibilityPolicyV1: Codable, Equatable, Sendable {
    static let persistentSchemaVersion = 33
    static let recordsSchemaVersion = 32
    static let currentPersistentWriterVersion = "33.0.0"
    static let currentBackupWriterVersion = "archive1-backup4-persistent33-records32"
    static let downgradeDisposition = "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V33_WRITE"
    static let readablePersistentWriterVersions = (1...33).map { "\($0).0.0" }
    static let readableBackupWriterVersions = SurveySessionCompatibilityPolicyV1.readableBackupWriterVersions
        + (26...32).map { "archive1-backup4-persistent\($0 + 1)-records\($0)" }

    let durableFamilies = TemporalEvidencePersistenceEnrollmentV1.persistentFamilies
    let originalContentBytesAreCanonical = true
    let secondByteStoreAllowed = TemporalEvidencePersistenceEnrollmentV1.secondByteStoreAllowed
    let historicOriginalDigestsRemainImmutable = true
    let unknownVersionsFailClosed = true

    func validate() throws {
        guard Self.persistentSchemaVersion == TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion,
              Self.recordsSchemaVersion == TemporalEvidencePersistenceEnrollmentV1.recordsSchemaVersion,
              durableFamilies == ["TemporalEvidenceClipRow", "TimecodedEvidenceAnchorRow"],
              originalContentBytesAreCanonical, !secondByteStoreAllowed,
              historicOriginalDigestsRemainImmutable, unknownVersionsFailClosed,
              Self.readablePersistentWriterVersions.last == Self.currentPersistentWriterVersion,
              Self.readableBackupWriterVersions.last == Self.currentBackupWriterVersion else {
            throw CompatibilityContractErrorV1.invalidSupportTable
        }
    }
}

extension ReleasedDataCompatibilityPolicyV1 {
    static let temporalEvidenceCompatibility = TemporalEvidenceCompatibilityPolicyV1()
}

struct AssetLabelCompatibilityPolicyV1: Codable, Equatable, Sendable {
    static let persistentSchemaVersion = 34
    static let recordsSchemaVersion = 33
    static let currentPersistentWriterVersion = "34.0.0"
    static let currentBackupWriterVersion = "archive1-backup4-persistent34-records33"
    static let downgradeDisposition = "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V34_WRITE"
    static let readablePersistentWriterVersions = (1...34).map { "\($0).0.0" }
    static let readableBackupWriterVersions = SurveySessionCompatibilityPolicyV1.readableBackupWriterVersions
        + (26...33).map { "archive1-backup4-persistent\($0 + 1)-records\($0)" }

    let durableFamilies = AssetLabelPersistenceEnrollmentV1.persistentFamilies
    let existingLocatorBindingTruthRemainsCanonical = true
    let derivedRendererStateIsReadableData = false
    let historicSourcePlanRemainsImmutable = true
    let unknownVersionsFailClosed = true

    func validate() throws {
        guard Self.persistentSchemaVersion == AssetLabelPersistenceEnrollmentV1.persistentSchemaVersion,
              Self.recordsSchemaVersion == AssetLabelPersistenceEnrollmentV1.recordsSchemaVersion,
              durableFamilies == ["AcceptedLabelGenerationSnapshotRow"],
              existingLocatorBindingTruthRemainsCanonical,
              !derivedRendererStateIsReadableData,
              historicSourcePlanRemainsImmutable, unknownVersionsFailClosed,
              Self.readablePersistentWriterVersions.last == Self.currentPersistentWriterVersion,
              Self.readableBackupWriterVersions.last == Self.currentBackupWriterVersion else {
            throw CompatibilityContractErrorV1.invalidSupportTable
        }
    }
}

extension ReleasedDataCompatibilityPolicyV1 {
    static let assetLabelCompatibility = AssetLabelCompatibilityPolicyV1()
}

enum C45AcceptedLabelReleasedDataCompatibilityV1 { static let persistentSchemaVersion=34;static let recordsSchemaVersion=33;static let downgradeRequiresExplicitForwardFix=true }

struct OperationalContactCompatibilityPolicyV1:Codable,Equatable,Sendable{
    static let persistentSchemaVersion=35;static let recordsSchemaVersion=34
    static let currentPersistentWriterVersion="35.0.0";static let currentBackupWriterVersion="archive1-backup4-persistent35-records34"
    static let downgradeDisposition="FORWARD_FIX_PRESERVE_ACCEPTED_OPERATIONAL_CONTACT_REVISIONS_AND_FROZEN_HANDOFF_HISTORY"
    let durableFamilies=OperationalContactPersistenceEnrollmentV1.persistentFamilies
    let partyContactsSchemaID=PartyContactCSVRowV1.schemaID
    let platformOutcomeIsReleasedData=false
    let historicIntentIsExecutable=false
    func validate()throws{guard Self.persistentSchemaVersion==OperationalContactPersistenceEnrollmentV1.persistentSchemaVersion,Self.recordsSchemaVersion==OperationalContactPersistenceEnrollmentV1.recordsSchemaVersion,durableFamilies==["ServiceContactPointRow","SystemHandoffIntentRow"],partyContactsSchemaID=="PARTY_CONTACTS_V1",!platformOutcomeIsReleasedData,!historicIntentIsExecutable else{throw CompatibilityContractErrorV1.invalidSupportTable}}
}
extension ReleasedDataCompatibilityPolicyV1{static let operationalContactCompatibility=OperationalContactCompatibilityPolicyV1()}

enum C48PortableReviewReleasedDataCompatibilityBoundaryV1 {
    static let exchangeProtocolIsSeparateFromWorkspaceSchema = true
    static let activeCapabilityIsNotAWorkspaceRevision = true
    static let responseBytesArePreservedOnlyByTheExchangeOwner = true
    static let derivedHistoryNeverRequiresHistoricSnapshotRewrite = true
    static let cloneAndForkMustNotReuseActiveCapability = true
    static let unknownProtocolVersionsFailClosed = true
}

import Foundation
import SwiftData

enum CurrentFilesystemBackupDispositionV1: String, Equatable, Sendable {
    case included = "INCLUDED"
    case excluded = "EXCLUDED"
    case notApplicable = "NOT_APPLICABLE"
}

enum CurrentRebuildDispositionV1: String, Equatable, Sendable {
    case rebuildFromCanonicalDependencies = "REBUILD_FROM_CANONICAL_DEPENDENCIES"
    case unavailableAtThisHead = "UNAVAILABLE_AT_THIS_HEAD"
    case notApplicable = "NOT_APPLICABLE"
}

enum CurrentReplayDispositionV1: String, Equatable, Sendable {
    case immutableMutationHistory = "IMMUTABLE_MUTATION_HISTORY"
    case recoveryStateMachine = "RECOVERY_STATE_MACHINE"
    case notApplicable = "NOT_APPLICABLE"
}

struct CurrentSyncLifecycleRouteV1: Equatable, Sendable {
    let subject: SyncSubjectIdentityV1
    let filesystemBackup: CurrentFilesystemBackupDispositionV1
    let semanticBackup: ReplicationBackupDispositionV1
    let portableExport: ReplicationExportDispositionV1
    let deletion: ReplicationDeleteDispositionV1
    let erase: ReplicationEraseDispositionV1
    let rebuild: CurrentRebuildDispositionV1
    let replay: CurrentReplayDispositionV1
}

enum CurrentSyncClassificationCatalogFailureV1: Error, Equatable {
    case invalidInventory
    case invalidBaseline
    case invalidLifecycleRoute
    case unexpectedSearchImplementation
    case unexpectedSecretOrKeychain
}

/// Repository-derived current-kind catalog for the C03 domain registry.
///
/// `SyncClassificationRegistryV1` remains the closed domain baseline. This
/// adapter proves that baseline is an exact subset of every kind shipped by
/// the current repository and adds infrastructure-only lifecycle routes that
/// do not belong in the transport-neutral domain contract.
struct CurrentSyncClassificationCatalogV1: Sendable {
    static let persistentModelNames = [
        "Asset", "DeletionLedgerRow", "EntityMutationRevisionRow", "EvidenceFile",
        "Issue", "MutationQuarantineRow", "MutationReceiptRow", "ObservationAndTimeRow", "Packet",
        "PersistentSchemaReleaseMarker", "Report", "Site", "WorkflowRecord",
        "WorkspaceMutationStateRow",
    ]

    static let ownedFileClassNames = [
        "cache", "commerceEntitlementCache", "database", "databaseSHM", "databaseWAL",
        "diagnostics", "durableDirectory", "generationPointer", "generationPointerTemporary",
        "journal", "journalTemporary", "mediaOriginal", "mediaThumbnail", "reportPDF",
        "reportSnapshot", "restoreStaging", "scratch", "stagingDirectory", "stagingFile",
        "temporaryFile",
    ]

    static let portableContentProjectionNames = [
        "DeletionLedgerV2",
        "MutationHistorySnapshotV1",
        "ObservationBasisV1",
        "ReportSnapshotV1",
        "StreamingArchiveIndexV1",
        "TemporalContextV1",
        "V4BackupAssetDTO",
        "V4BackupEvidenceFileDTO",
        "V4BackupIssueDTO",
        "V4BackupManifestV1",
        "V4BackupPacketDTO",
        "V4BackupRecordsV1",
        "V4BackupReportDTO",
        "V4BackupSiteDTO",
        "V4BackupWorkflowRecordDTO",
    ]

    static let derivedIndexNames = [
        "ReportHistoryIndexValue",
        "reportHistoryChronology",
    ]

    static let derivedProjectionNames = [
        "EntityMutationRevisionSemanticV1",
        "MutationQuarantineSemanticV1",
        "MutationReceiptSemanticV1",
        "ObservationAndTimeMigrationReceiptV1",
        "ObservationAndTimeSemanticV1",
        "StoreSemanticEnvelopeV3",
        "StoreSemanticEnvelopeV4",
        "StoreSemanticEnvelopeV5",
        "WorkspaceMutationStateSemanticV1",
        "entityMutationRevision",
        "workspaceMutationState",
    ]

    static let journalRecoveryNames = [
        "CurrentGenerationPointerV2",
        "CurrentGenerationPointerV3",
        "DeletionIntentV1",
        "EraseIntentV1",
        "ErasePreparationV2",
        "FinalizationIntentV1",
        "MutationEnvelopeV1",
        "MutationHistoryQuarantineRecordV1",
        "MutationReceiptV1",
        "PreparedMigrationEnvelopeV1",
        "RestoreIntentV1",
        "ReversalBasisV1",
        "SemanticReversalReceiptV1",
        "StoreGenerationManifestV1",
        "StoreMigrationJournalV1",
        "deletionIntent",
        "eraseIntent",
        "finalizationIntent",
        "mutationReceipt",
        "restoreIntent",
        "storeMigration",
    ]

    static let diagnosticNames = [
        "DiagnosticExportV1",
        "DiagnosticsLogEvent",
        "DiagnosticsV1",
        "LaunchTimeMillisecondsV1",
        "MetricKitSummaryV1",
        "PurchaseResultHistogram",
        "diagnosticCounters",
    ]

    /// No Search implementation ships at this head. Report history is an
    /// in-memory derived index and is registered above, not a search store.
    static let declaredSearchImplementationPresent = false

    /// The accepted portable-secret inventory is explicitly empty and the
    /// application has no Keychain-backed secret at this head.
    static let secretNames: [String] = []
    static let declaredKeychainUsage = false

    let registrations: [SyncClassificationRegistrationV1]
    let lifecycleRoutes: [CurrentSyncLifecycleRouteV1]
    let persistentModelSubjects: [SyncSubjectIdentityV1]
    let ownedFileClassSubjects: [SyncSubjectIdentityV1]
    let portableContentProjectionSubjects: [SyncSubjectIdentityV1]
    let derivedIndexProjectionSubjects: [SyncSubjectIdentityV1]
    let journalRecoverySubjects: [SyncSubjectIdentityV1]
    let diagnosticSubjects: [SyncSubjectIdentityV1]
    let secretSubjects: [SyncSubjectIdentityV1]
    let searchImplementationPresent: Bool
    let keychainUsageDeclared: Bool

    static var current: CurrentSyncClassificationCatalogV1 {
        get throws {
            let baseline = try SyncClassificationRegistryV1.registrations
            let additions = try makeAdditionalRegistrations()
            let registrations = (baseline + additions).sorted {
                $0.subject.canonicalKey < $1.subject.canonicalKey
            }
            let routes = try registrations.map(makeLifecycleRoute).sorted {
                $0.subject.canonicalKey < $1.subject.canonicalKey
            }
            let persistentSubjects = try subjects(
                category: .persistentModel,
                names: persistentModelNames
            )
            let ownedFileSubjects = try subjects(
                category: .ownedFileClass,
                names: ownedFileClassNames
            )
            let portableSubjects = try subjects(
                category: .projection,
                names: portableContentProjectionNames
            )
            let derivedSubjects = try subjects(
                category: .index,
                names: derivedIndexNames
            ) + (try subjects(
                category: .projection,
                names: derivedProjectionNames
            ))
            let journalSubjects = try subjects(
                category: .journal,
                names: journalRecoveryNames
            )
            let diagnostics = try subjects(
                category: .diagnostic,
                names: diagnosticNames
            )
            let secrets = try subjects(category: .secret, names: secretNames)
            return try CurrentSyncClassificationCatalogV1(
                registrations: registrations,
                lifecycleRoutes: routes,
                persistentModelSubjects: persistentSubjects,
                ownedFileClassSubjects: ownedFileSubjects,
                portableContentProjectionSubjects: portableSubjects,
                derivedIndexProjectionSubjects: derivedSubjects,
                journalRecoverySubjects: journalSubjects,
                diagnosticSubjects: diagnostics,
                secretSubjects: secrets,
                searchImplementationPresent: Self.declaredSearchImplementationPresent,
                keychainUsageDeclared: Self.declaredKeychainUsage
            )
        }
    }

    init(
        registrations: [SyncClassificationRegistrationV1],
        lifecycleRoutes: [CurrentSyncLifecycleRouteV1],
        persistentModelSubjects: [SyncSubjectIdentityV1],
        ownedFileClassSubjects: [SyncSubjectIdentityV1],
        portableContentProjectionSubjects: [SyncSubjectIdentityV1],
        derivedIndexProjectionSubjects: [SyncSubjectIdentityV1],
        journalRecoverySubjects: [SyncSubjectIdentityV1],
        diagnosticSubjects: [SyncSubjectIdentityV1],
        secretSubjects: [SyncSubjectIdentityV1],
        searchImplementationPresent: Bool,
        keychainUsageDeclared: Bool
    ) throws {
        self.registrations = registrations
        self.lifecycleRoutes = lifecycleRoutes
        self.persistentModelSubjects = persistentModelSubjects
        self.ownedFileClassSubjects = ownedFileClassSubjects
        self.portableContentProjectionSubjects = portableContentProjectionSubjects
        self.derivedIndexProjectionSubjects = derivedIndexProjectionSubjects
        self.journalRecoverySubjects = journalRecoverySubjects
        self.diagnosticSubjects = diagnosticSubjects
        self.secretSubjects = secretSubjects
        self.searchImplementationPresent = searchImplementationPresent
        self.keychainUsageDeclared = keychainUsageDeclared
        try validate()
    }

    func registration(
        for subject: SyncSubjectIdentityV1
    ) throws -> SyncClassificationRegistrationV1 {
        let matches = registrations.filter { $0.subject == subject }
        guard matches.count == 1, let value = matches.first else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
        return value
    }

    func lifecycleRoute(
        for subject: SyncSubjectIdentityV1
    ) throws -> CurrentSyncLifecycleRouteV1 {
        let matches = lifecycleRoutes.filter { $0.subject == subject }
        guard matches.count == 1, let value = matches.first else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidLifecycleRoute
        }
        return value
    }

    func validate() throws {
        try SyncClassificationRegistryV1.validate()
        guard !registrations.isEmpty,
              registrations.count <= SyncClassificationRegistryV1.maximumRegistrationCount else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
        let registrationKeys = registrations.map(\.subject.canonicalKey)
        guard registrationKeys == registrationKeys.sorted(),
              Set(registrationKeys).count == registrationKeys.count else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
        try registrations.forEach { try $0.validate() }

        let bySubject = Dictionary(
            uniqueKeysWithValues: registrations.map { ($0.subject, $0) }
        )
        for baseline in try SyncClassificationRegistryV1.registrations {
            guard bySubject[baseline.subject] == baseline else {
                throw CurrentSyncClassificationCatalogFailureV1.invalidBaseline
            }
        }

        try validatePersistentModels()
        try validateOwnedFileClasses()
        try requireExactCategory(
            persistentModelSubjects,
            category: .persistentModel,
            expectedNames: Self.persistentModelNames
        )
        try requireExactCategory(
            ownedFileClassSubjects,
            category: .ownedFileClass,
            expectedNames: Self.ownedFileClassNames
        )
        try requireExactCategory(
            portableContentProjectionSubjects,
            category: .projection,
            expectedNames: Self.portableContentProjectionNames
        )
        let expectedDerived = try Self.subjects(
            category: .index,
            names: Self.derivedIndexNames
        ) + (try Self.subjects(
            category: .projection,
            names: Self.derivedProjectionNames
        ))
        guard Set(derivedIndexProjectionSubjects) == Set(expectedDerived),
              derivedIndexProjectionSubjects.count == expectedDerived.count else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
        try requireExactCategory(
            journalRecoverySubjects,
            category: .journal,
            expectedNames: Self.journalRecoveryNames
        )
        try requireExactCategory(
            diagnosticSubjects,
            category: .diagnostic,
            expectedNames: Self.diagnosticNames
        )
        guard secretSubjects.isEmpty,
              SyncClassificationRegistryV1.declaredSecretSubjects.isEmpty,
              !keychainUsageDeclared else {
            throw CurrentSyncClassificationCatalogFailureV1.unexpectedSecretOrKeychain
        }
        guard !searchImplementationPresent else {
            throw CurrentSyncClassificationCatalogFailureV1.unexpectedSearchImplementation
        }

        let declaredSubjects = Set(
            persistentModelSubjects
            + ownedFileClassSubjects
            + portableContentProjectionSubjects
            + derivedIndexProjectionSubjects
            + journalRecoverySubjects
            + diagnosticSubjects
            + secretSubjects
        )
        guard declaredSubjects == Set(registrations.map(\.subject)),
              lifecycleRoutes.map(\.subject.canonicalKey) == registrationKeys else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
        try lifecycleRoutes.forEach { route in
            let policy = try registration(for: route.subject).replicationPolicy
            guard route.semanticBackup == policy.backup,
                  route.portableExport == policy.export,
                  route.deletion == policy.deletion,
                  route.erase == policy.erase else {
                throw CurrentSyncClassificationCatalogFailureV1.invalidLifecycleRoute
            }
            if route.subject.category == .ownedFileClass {
                guard let kind = OwnedFileKindV1(rawValue: route.subject.stableName),
                      route.filesystemBackup == (
                        ProtectedFilePolicyV1.isExcludedFromBackup(for: kind)
                            ? .excluded : .included
                      ) else {
                    throw CurrentSyncClassificationCatalogFailureV1.invalidLifecycleRoute
                }
            } else if route.filesystemBackup != .notApplicable {
                throw CurrentSyncClassificationCatalogFailureV1.invalidLifecycleRoute
            }
        }

        // These two assertions prevent filesystem-backup eligibility from
        // being confused with portable semantic backup/export eligibility.
        let database = try Self.subject(category: .ownedFileClass, name: "database")
        let databaseRoute = try lifecycleRoute(for: database)
        guard databaseRoute.filesystemBackup == .included,
              databaseRoute.semanticBackup == .exclude,
              databaseRoute.portableExport == .exclude else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidLifecycleRoute
        }
        let records = try Self.subject(category: .projection, name: "V4BackupRecordsV1")
        let recordsRoute = try lifecycleRoute(for: records)
        guard recordsRoute.filesystemBackup == .notApplicable,
              recordsRoute.semanticBackup == .includeCanonical,
              recordsRoute.portableExport == .portableCanonical else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidLifecycleRoute
        }
    }
}

private extension CurrentSyncClassificationCatalogV1 {
    enum AdditionalProfile {
        case portableProjection
        case immutableContent
        case replicatedContent
        case derivedProjection
        case replicatedMutationHistory
        case recoveryJournal
        case privateDiagnostic
        case reviewedDiagnosticExport
    }

    struct AdditionalSpec {
        let category: SyncSubjectCategoryV1
        let name: String
        let profile: AdditionalProfile
        let dependencies: [SyncSubjectIdentityV1]
    }

    static func makeAdditionalRegistrations() throws -> [SyncClassificationRegistrationV1] {
        let baselineKeys = Set(
            try SyncClassificationRegistryV1.registrations.map(\.subject.canonicalKey)
        )
        var specs: [AdditionalSpec] = []

        specs.append(AdditionalSpec(
            category: .persistentModel,
            name: "ObservationAndTimeRow",
            profile: .replicatedContent,
            dependencies: [
                try subject(category: .persistentModel, name: "WorkflowRecord")
            ]
        ))

        for name in portableContentProjectionNames {
            let profile: AdditionalProfile = name == "ReportSnapshotV1"
                ? .immutableContent : .portableProjection
            specs.append(AdditionalSpec(
                category: .projection,
                name: name,
                profile: profile,
                dependencies: try projectionDependencies(for: name)
            ))
        }
        for name in derivedIndexNames {
            specs.append(AdditionalSpec(
                category: .index,
                name: name,
                profile: .derivedProjection,
                dependencies: try contentModelSubjects()
            ))
        }
        for name in derivedProjectionNames {
            specs.append(AdditionalSpec(
                category: .projection,
                name: name,
                profile: .derivedProjection,
                dependencies: try semanticDependencies(for: name)
            ))
        }
        let replicatedHistory = Set([
            "MutationEnvelopeV1", "MutationHistoryQuarantineRecordV1",
            "MutationReceiptV1", "ReversalBasisV1", "SemanticReversalReceiptV1",
        ])
        for name in journalRecoveryNames {
            specs.append(AdditionalSpec(
                category: .journal,
                name: name,
                profile: replicatedHistory.contains(name)
                    ? .replicatedMutationHistory : .recoveryJournal,
                dependencies: []
            ))
        }
        for name in diagnosticNames {
            let profile: AdditionalProfile
            if name == "DiagnosticExportV1" {
                profile = .reviewedDiagnosticExport
            } else {
                profile = .privateDiagnostic
            }
            specs.append(AdditionalSpec(
                category: .diagnostic,
                name: name,
                profile: profile,
                dependencies: []
            ))
        }

        return try specs.compactMap { spec in
            let subject = try subject(category: spec.category, name: spec.name)
            guard !baselineKeys.contains(subject.canonicalKey) else { return nil }
            return try registration(
                subject: subject,
                profile: spec.profile,
                dependencies: spec.dependencies
            )
        }.sorted { $0.subject.canonicalKey < $1.subject.canonicalKey }
    }

    static func registration(
        subject: SyncSubjectIdentityV1,
        profile: AdditionalProfile,
        dependencies: [SyncSubjectIdentityV1]
    ) throws -> SyncClassificationRegistrationV1 {
        let classification: SyncClassificationV1
        let authority: ReplicationAuthorityV1
        let persistence: ReplicationPersistenceV1
        let transport: ReplicationTransportV1
        let bootstrap: ReplicationBootstrapV1
        let privacy: ReplicationPrivacyV1
        let retention: ReplicationRetentionV1
        let backup: ReplicationBackupDispositionV1
        let export: ReplicationExportDispositionV1
        let deletion: ReplicationDeleteDispositionV1
        let erase: ReplicationEraseDispositionV1
        let rule: ConflictRuleV1
        let maximumBytes: Int64

        switch profile {
        case .portableProjection:
            classification = .derivedRebuildable
            authority = .derivedFromCanonicalInputs
            persistence = .nonpersistent
            transport = .excluded
            bootstrap = .rebuildFromDependencies
            privacy = .workspaceData
            retention = .rebuildable
            backup = .includeCanonical
            export = .portableCanonical
            deletion = .rebuild
            erase = .rebuildAfterErase
            rule = .derivedRebuild
            maximumBytes = 1_073_741_824
        case .immutableContent:
            classification = .contentBlob
            authority = .immutableContentWriter
            persistence = .ownedFile
            transport = .futureBoundedBlobEligible
            bootstrap = .immutableHistory
            privacy = .workspaceContentBlob
            retention = .immutableHistoryUntilErase
            backup = .includeImmutableHistory
            export = .portableImmutableHistory
            deletion = .canonicalDelete
            erase = .clearWithWorkspace
            rule = .immutableVersion
            maximumBytes = 134_217_728
        case .replicatedContent:
            classification = .replicated
            authority = .workspaceWriter
            persistence = .swiftDataRecord
            transport = .futureAcceptedMutationEligible
            bootstrap = .canonicalSnapshot
            privacy = .workspaceData
            retention = .untilCanonicalDeleteOrErase
            backup = .includeCanonical
            export = .portableCanonical
            deletion = .canonicalDelete
            erase = .clearWithWorkspace
            rule = .exactRevisionManual
            maximumBytes = 16_777_216
        case .derivedProjection:
            classification = .derivedRebuildable
            authority = .derivedFromCanonicalInputs
            persistence = .nonpersistent
            transport = .excluded
            bootstrap = .rebuildFromDependencies
            privacy = .workspaceData
            retention = .rebuildable
            backup = .rebuildAfterRestore
            export = .exclude
            deletion = .rebuild
            erase = .rebuildAfterErase
            rule = .derivedRebuild
            maximumBytes = 16_777_216
        case .replicatedMutationHistory:
            classification = .replicated
            authority = .workspaceWriter
            persistence = .swiftDataRecord
            transport = .futureAcceptedMutationEligible
            bootstrap = .immutableHistory
            privacy = .workspaceData
            retention = .immutableHistoryUntilErase
            backup = .includeImmutableHistory
            export = .portableImmutableHistory
            deletion = .localAuthority
            erase = .clearWithWorkspace
            rule = .stableIDAppendUnion
            maximumBytes = 16_777_216
        case .recoveryJournal:
            classification = .localOnly
            authority = .localDevice
            persistence = .ownedFile
            transport = .excluded
            bootstrap = .destinationLocal
            privacy = .workspaceData
            retention = .operationScoped
            backup = .exclude
            export = .exclude
            deletion = .operationCleanup
            erase = .clearWithWorkspace
            rule = .localOnly
            maximumBytes = 16_777_216
        case .privateDiagnostic:
            classification = .privateDeviceOnly
            authority = .localDevice
            persistence = subject.stableName == "DiagnosticsV1" ? .ownedFile : .nonpersistent
            transport = .excluded
            bootstrap = .destinationLocal
            privacy = .noncustomerDiagnostic
            retention = .localDeviceRetained
            backup = .exclude
            export = .exclude
            deletion = .localAuthority
            erase = .localAuthority
            rule = .localOnly
            maximumBytes = 4_194_304
        case .reviewedDiagnosticExport:
            classification = .localOnly
            authority = .localDevice
            persistence = .nonpersistent
            transport = .excluded
            bootstrap = .excluded
            privacy = .noncustomerDiagnostic
            retention = .operationScoped
            backup = .exclude
            export = .portableCanonical
            deletion = .operationCleanup
            erase = .localAuthority
            rule = .localOnly
            maximumBytes = 4_194_304
        }

        let sortedDependencies = dependencies.sorted { $0.canonicalKey < $1.canonicalKey }
        let policy = try ReplicationPolicyV1(
            policyID: "current." + subject.canonicalKey.replacingOccurrences(of: ":", with: "."),
            authority: authority,
            persistence: persistence,
            transport: transport,
            bootstrap: bootstrap,
            privacy: privacy,
            retention: retention,
            codec: try ReplicationCodecV1(
                codecID: "current." + subject.stableName,
                readableVersions: [1],
                currentWriteVersion: 1
            ),
            sizeLimit: .boundedBytes(maximumBytes),
            dependencies: sortedDependencies,
            backup: backup,
            export: export,
            deletion: deletion,
            erase: erase
        )
        return try SyncClassificationRegistrationV1(
            subject: subject,
            classification: classification,
            replicationPolicy: policy,
            conflictPolicy: try ConflictPolicyV1(
                policyID: "current." + subject.canonicalKey.replacingOccurrences(of: ":", with: "."),
                rule: rule
            )
        )
    }

    static func makeLifecycleRoute(
        _ registration: SyncClassificationRegistrationV1
    ) throws -> CurrentSyncLifecycleRouteV1 {
        let filesystemBackup: CurrentFilesystemBackupDispositionV1
        if registration.subject.category == .ownedFileClass {
            guard let kind = OwnedFileKindV1(rawValue: registration.subject.stableName) else {
                throw CurrentSyncClassificationCatalogFailureV1.invalidLifecycleRoute
            }
            filesystemBackup = ProtectedFilePolicyV1.isExcludedFromBackup(for: kind)
                ? .excluded : .included
        } else {
            filesystemBackup = .notApplicable
        }

        let rebuild: CurrentRebuildDispositionV1
        switch registration.classification {
        case .derivedRebuildable:
            rebuild = .rebuildFromCanonicalDependencies
        default:
            rebuild = .notApplicable
        }

        let replay: CurrentReplayDispositionV1
        if registration.subject.category == .journal {
            switch registration.classification {
            case .replicated:
                replay = .immutableMutationHistory
            default:
                replay = .recoveryStateMachine
            }
        } else if registration.subject.category == .persistentModel,
                  registration.subject.stableName == "MutationReceiptRow" {
            replay = .immutableMutationHistory
        } else {
            replay = .notApplicable
        }

        return CurrentSyncLifecycleRouteV1(
            subject: registration.subject,
            filesystemBackup: filesystemBackup,
            semanticBackup: registration.replicationPolicy.backup,
            portableExport: registration.replicationPolicy.export,
            deletion: registration.replicationPolicy.deletion,
            erase: registration.replicationPolicy.erase,
            rebuild: rebuild,
            replay: replay
        )
    }

    static func projectionDependencies(
        for name: String
    ) throws -> [SyncSubjectIdentityV1] {
        switch name {
        case "DeletionLedgerV2":
            return [try subject(category: .persistentModel, name: "DeletionLedgerRow")]
        case "MutationHistorySnapshotV1":
            return try subjects(category: .persistentModel, names: [
                "EntityMutationRevisionRow", "MutationQuarantineRow",
                "MutationReceiptRow", "WorkspaceMutationStateRow",
            ])
        case "ObservationBasisV1", "TemporalContextV1":
            return [try subject(category: .persistentModel, name: "ObservationAndTimeRow")]
        case "ReportSnapshotV1":
            return try contentModelSubjects()
        case "StreamingArchiveIndexV1":
            return [try subject(category: .projection, name: "V4BackupManifestV1")]
        case "V4BackupAssetDTO":
            return [try subject(category: .persistentModel, name: "Asset")]
        case "V4BackupEvidenceFileDTO":
            return [try subject(category: .persistentModel, name: "EvidenceFile")]
        case "V4BackupIssueDTO":
            return [try subject(category: .persistentModel, name: "Issue")]
        case "V4BackupPacketDTO":
            return [try subject(category: .persistentModel, name: "Packet")]
        case "V4BackupReportDTO":
            return [try subject(category: .persistentModel, name: "Report")]
        case "V4BackupSiteDTO":
            return [try subject(category: .persistentModel, name: "Site")]
        case "V4BackupWorkflowRecordDTO":
            return try subjects(category: .persistentModel, names: [
                "ObservationAndTimeRow", "WorkflowRecord",
            ])
        case "V4BackupRecordsV1", "V4BackupManifestV1":
            return try contentModelSubjects()
        default:
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
    }

    static func semanticDependencies(
        for name: String
    ) throws -> [SyncSubjectIdentityV1] {
        switch name {
        case "EntityMutationRevisionSemanticV1", "entityMutationRevision":
            return [try subject(category: .persistentModel, name: "EntityMutationRevisionRow")]
        case "MutationQuarantineSemanticV1":
            return [try subject(category: .persistentModel, name: "MutationQuarantineRow")]
        case "MutationReceiptSemanticV1":
            return [try subject(category: .persistentModel, name: "MutationReceiptRow")]
        case "WorkspaceMutationStateSemanticV1", "workspaceMutationState":
            return [try subject(category: .persistentModel, name: "WorkspaceMutationStateRow")]
        case "ObservationAndTimeMigrationReceiptV1", "ObservationAndTimeSemanticV1":
            return [
                try subject(category: .persistentModel, name: "WorkflowRecord"),
                try subject(category: .persistentModel, name: "ObservationAndTimeRow"),
            ]
        case "StoreSemanticEnvelopeV3", "StoreSemanticEnvelopeV4", "StoreSemanticEnvelopeV5":
            return try subjects(category: .persistentModel, names: persistentModelNames)
        default:
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
    }

    static func contentModelSubjects() throws -> [SyncSubjectIdentityV1] {
        try subjects(category: .persistentModel, names: [
            "Asset", "EvidenceFile", "Issue", "ObservationAndTimeRow", "Packet",
            "Report", "Site", "WorkflowRecord",
        ])
    }

    static func validatePersistentModels() throws {
        let expected: [any PersistentModel.Type] = [
            Site.self,
            Asset.self,
            WorkflowRecord.self,
            EvidenceFile.self,
            Issue.self,
            Packet.self,
            Report.self,
            PersistentSchemaReleaseMarker.self,
            DeletionLedgerRow.self,
            MutationReceiptRow.self,
            MutationQuarantineRow.self,
            WorkspaceMutationStateRow.self,
            EntityMutationRevisionRow.self,
            ObservationAndTimeRow.self,
        ]
        let runtimeNames = PersistentSchemaV5.models.map { modelType in
            String(describing: modelType)
                .split(separator: ".")
                .last
                .map(String.init) ?? ""
        }.sorted()
        guard PersistentSchemaV5.models.count == expected.count,
              Set(PersistentSchemaV5.models.map { ObjectIdentifier($0) })
                == Set(expected.map { ObjectIdentifier($0) }),
              runtimeNames.count == Set(runtimeNames).count,
              runtimeNames.allSatisfy(ReplicationContractValidationV1.validToken),
              runtimeNames == persistentModelNames,
              Set(persistentModelNames)
                == Set(SyncClassificationRegistryV1.persistentModelNames + ["ObservationAndTimeRow"]) else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
    }

    static func validateOwnedFileClasses() throws {
        let observed = OwnedFileKindV1.allCases.map(\.rawValue).sorted()
        guard observed == ownedFileClassNames,
              ownedFileClassNames == SyncClassificationRegistryV1.ownedFileClassNames else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
    }

    func requireExactCategory(
        _ subjects: [SyncSubjectIdentityV1],
        category: SyncSubjectCategoryV1,
        expectedNames: [String]
    ) throws {
        guard subjects.allSatisfy({ $0.category == category }),
              subjects.map(\.stableName).sorted() == expectedNames.sorted(),
              Set(subjects).count == subjects.count else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
    }

    static func subjects(
        category: SyncSubjectCategoryV1,
        names: [String]
    ) throws -> [SyncSubjectIdentityV1] {
        try names.map { try subject(category: category, name: $0) }
            .sorted { $0.canonicalKey < $1.canonicalKey }
    }

    static func subject(
        category: SyncSubjectCategoryV1,
        name: String
    ) throws -> SyncSubjectIdentityV1 {
        try SyncSubjectIdentityV1(category: category, stableName: name)
    }
}

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

enum CurrentRepresentationAuthorityV1: String, Equatable, Sendable {
    case canonicalRow = "CANONICAL_ROW"
    case derivedPersistedRow = "DERIVED_PERSISTED_ROW"
    case localRecoveryRow = "LOCAL_RECOVERY_ROW"
    case portableProjection = "PORTABLE_PROJECTION"
    case persistedDeviceStore = "PERSISTED_DEVICE_STORE"
    case nonpersistentView = "NONPERSISTENT_VIEW"
}

struct CurrentRepresentationRuleV1: Equatable, Sendable {
    let source: SyncSubjectIdentityV1
    let representation: SyncSubjectIdentityV1
    let sourceAuthority: CurrentRepresentationAuthorityV1
    let representationAuthority: CurrentRepresentationAuthorityV1
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

    /// Frozen V5 public baseline remains available to sealed Kernel V4 and
    /// prior tooling. Runtime V6 consumers use this additive inventory.
    static let v6PersistentModelNames = [
        "AssetCompositionEdgeRow", "AssetCompositionEventRow",
        "AssetPlacementEventRow", "LocationHierarchyEventRow",
        "LocationMigrationReceiptRow", "LocationNodeRow",
    ]
    static let v7PersistentModelNames = ["SavedSmartView"]
    static let v8PersistentModelNames = ["RequirementAssuranceRow"]
    static let v9PersistentModelNames = [
        "ActorSnapshotRow", "QualificationSnapshotRow", "ServicePartyRow",
        "SignoffSnapshotRow", "SitePartyRoleEventRow",
    ]
    static let activePersistentModelNames =
        (persistentModelNames + v6PersistentModelNames + v7PersistentModelNames
            + v8PersistentModelNames + v9PersistentModelNames).sorted()

    static let ownedFileClassNames = [
        "cache", "commerceEntitlementCache", "database", "databaseSHM", "databaseWAL",
        "diagnostics", "durableDirectory", "generationLeaseControl",
        "generationLeaseControlTemporary", "generationLeaseDirectory",
        "generationLeaseOwnerLock", "generationPointer", "generationPointerTemporary",
        "journal", "journalTemporary", "mediaOriginal", "mediaThumbnail", "reportPDF",
        "reportSnapshot", "restoreStaging", "scratch", "stagingDirectory", "stagingFile",
        "temporaryFile", "searchIndex",
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
        "V5BackupLocationRecordV1",
        "SavedSmartViewDescriptorV1",
        "RequirementAssuranceSnapshotV1",
        "RequirementEvaluationV1",
        "CompletionDecisionV1",
        "IntegrityFindingV1",
        "ServicePartyReferenceV1",
        "SitePartyRoleEventV1",
        "ActorSnapshotV1",
        "QualificationSnapshotV1",
        "SignoffSnapshotV1",
    ]

    static let derivedIndexNames = [
        "ReportHistoryIndexValue",
        "SearchIndexProjectionV1",
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
        "StoreSemanticEnvelopeV6",
        "StoreSemanticEnvelopeV7",
        "StoreSemanticEnvelopeV8",
        "StoreSemanticEnvelopeV9",
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
        "DeviceOperationalSupportSnapshotV2",
        "DeviceOperationalSupportStoreV1",
        "DeviceOperationalSupportStoreV2",
        "LaunchTimeMillisecondsV1",
        "MetricKitSummaryV1",
        "OperationalFailureV1",
        "PurchaseResultHistogram",
        "ScratchDataLeaseStoreV1",
        "SystemHealthDiagnosticsV1",
        "diagnosticCounters",
    ]

    static let declaredSearchImplementationPresent = true

    /// The accepted portable-secret inventory is explicitly empty and the
    /// application has no Keychain-backed secret at this head.
    static let secretNames: [String] = []
    static let declaredKeychainUsage = false

    /// Canonical mutation rows and their portable snapshot are distinct
    /// representations. Export never promotes the projection into row truth.
    static var mutationHistoryRepresentationRules: [CurrentRepresentationRuleV1] {
        get throws {
            let projection = try subject(
                category: .projection,
                name: "MutationHistorySnapshotV1"
            )
            return try [
                ("EntityMutationRevisionRow", CurrentRepresentationAuthorityV1.derivedPersistedRow),
                ("MutationQuarantineRow", CurrentRepresentationAuthorityV1.localRecoveryRow),
                ("MutationReceiptRow", CurrentRepresentationAuthorityV1.canonicalRow),
                ("WorkspaceMutationStateRow", CurrentRepresentationAuthorityV1.derivedPersistedRow),
            ].map { name, authority in
                CurrentRepresentationRuleV1(
                    source: try subject(category: .persistentModel, name: name),
                    representation: projection,
                    sourceAuthority: authority,
                    representationAuthority: .portableProjection
                )
            }
        }
    }

    /// The V1 name is a legacy schema/interface declaration. V2 is the sole
    /// persisted operational-support store kind; bounded snapshots, failures,
    /// exports, counters, and summaries are nonpersistent views.
    static var diagnosticRepresentationRules: [CurrentRepresentationRuleV1] {
        get throws {
            let store = try subject(
                category: .diagnostic,
                name: "DeviceOperationalSupportStoreV2"
            )
            return try diagnosticNames
                .filter { $0 != "DeviceOperationalSupportStoreV2"
                          && $0 != "ScratchDataLeaseStoreV1" }
                .map {
                    CurrentRepresentationRuleV1(
                        source: store,
                        representation: try subject(category: .diagnostic, name: $0),
                        sourceAuthority: .persistedDeviceStore,
                        representationAuthority: .nonpersistentView
                    )
                }
        }
    }

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
                names: activePersistentModelNames
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
            expectedNames: Self.activePersistentModelNames
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
        guard searchImplementationPresent else {
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

        let mutationRules = try Self.mutationHistoryRepresentationRules
        guard mutationRules.count == 4,
              Set(mutationRules.map(\.source)).count == mutationRules.count,
              mutationRules.allSatisfy({ rule in
                  rule.sourceAuthority == .canonicalRow
                      || rule.sourceAuthority == .derivedPersistedRow
                      || rule.sourceAuthority == .localRecoveryRow
              }),
              mutationRules.allSatisfy({
                  $0.representationAuthority == .portableProjection
              }) else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
        let diagnosticRules = try Self.diagnosticRepresentationRules
        let diagnosticViewNames = Set(diagnosticRules.map { $0.representation.stableName })
        guard diagnosticViewNames == Set(Self.diagnosticNames).subtracting([
            "DeviceOperationalSupportStoreV2", "ScratchDataLeaseStoreV1",
        ]) else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
        let supportStore = try Self.subject(
            category: .diagnostic,
            name: "DeviceOperationalSupportStoreV2"
        )
        let scratchStore = try Self.subject(
            category: .diagnostic,
            name: "ScratchDataLeaseStoreV1"
        )
        guard try registration(for: supportStore).replicationPolicy.persistence == .ownedFile,
              try registration(for: scratchStore).replicationPolicy.persistence == .ownedFile,
              try diagnosticRules.allSatisfy({ rule in
                  try registration(for: rule.representation)
                      .replicationPolicy.persistence == .nonpersistent
              }) else {
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
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

        // Card 28 support state is device-operational, never workspace truth.
        // Its concrete store/projections and scratch-lease adapter must remain
        // local-device authorities and ineligible for Cloud transport, backup,
        // or portable export. The generic owned scratch/diagnostics file kinds
        // are independently required to stay excluded from transport and
        // filesystem backup.
        for name in Self.diagnosticNames {
            let subject = try Self.subject(category: .diagnostic, name: name)
            let registration = try registration(for: subject)
            let route = try lifecycleRoute(for: subject)
            guard registration.classification == .privateDeviceOnly,
                  registration.replicationPolicy.authority == .localDevice,
                  registration.replicationPolicy.transport == .excluded,
                  registration.replicationPolicy.bootstrap == .destinationLocal,
                  route.filesystemBackup == .notApplicable,
                  route.semanticBackup == .exclude,
                  route.portableExport == .exclude else {
                throw CurrentSyncClassificationCatalogFailureV1.invalidLifecycleRoute
            }
        }
        for name in ["diagnostics", "scratch"] {
            let subject = try Self.subject(category: .ownedFileClass, name: name)
            let registration = try registration(for: subject)
            let route = try lifecycleRoute(for: subject)
            guard registration.replicationPolicy.transport == .excluded,
                  route.filesystemBackup == .excluded,
                  route.semanticBackup == .exclude,
                  route.portableExport == .exclude else {
                throw CurrentSyncClassificationCatalogFailureV1.invalidLifecycleRoute
            }
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
        for name in v6PersistentModelNames {
            let mutable = ["LocationNodeRow", "AssetCompositionEdgeRow"].contains(name)
            specs.append(AdditionalSpec(
                category: .persistentModel,
                name: name,
                profile: mutable ? .replicatedContent : .replicatedMutationHistory,
                dependencies: try locationPersistentDependencies(for: name)
            ))
        }
        for name in v7PersistentModelNames {
            specs.append(AdditionalSpec(
                category: .persistentModel,
                name: name,
                profile: .replicatedContent,
                dependencies: []
            ))
        }
        for name in v8PersistentModelNames {
            specs.append(AdditionalSpec(
                category: .persistentModel,
                name: name,
                profile: .replicatedContent,
                dependencies: [try subject(category: .persistentModel, name: "WorkflowRecord")]
            ))
        }
        for name in v9PersistentModelNames {
            let mutable = name == "ServicePartyRow"
            specs.append(AdditionalSpec(
                category: .persistentModel,
                name: name,
                profile: mutable ? .replicatedContent : .replicatedMutationHistory,
                dependencies: try partyPersistentDependencies(for: name)
            ))
        }

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
            // DiagnosticExportV1 is the bounded in-app preparation, not the
            // user-directed external Files/share effect. It remains device
            // local and is never a sync or portable-semantic-export subject.
            specs.append(AdditionalSpec(
                category: .diagnostic,
                name: name,
                profile: .privateDiagnostic,
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
            persistence = [
                "DeviceOperationalSupportStoreV2",
                "ScratchDataLeaseStoreV1",
            ].contains(subject.stableName) ? .ownedFile : .nonpersistent
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
        case "V5BackupLocationRecordV1":
            return try subjects(category: .persistentModel, names: v6PersistentModelNames)
        case "SavedSmartViewDescriptorV1":
            return [try subject(category: .persistentModel, name: "SavedSmartView")]
        case "RequirementAssuranceSnapshotV1", "RequirementEvaluationV1",
             "CompletionDecisionV1", "IntegrityFindingV1":
            return [try subject(category: .persistentModel, name: "RequirementAssuranceRow")]
        case "ServicePartyReferenceV1":
            return [try subject(category: .persistentModel, name: "ServicePartyRow")]
        case "SitePartyRoleEventV1":
            return [try subject(category: .persistentModel, name: "SitePartyRoleEventRow")]
        case "ActorSnapshotV1":
            return [try subject(category: .persistentModel, name: "ActorSnapshotRow")]
        case "QualificationSnapshotV1":
            return [try subject(category: .persistentModel, name: "QualificationSnapshotRow")]
        case "SignoffSnapshotV1":
            return [try subject(category: .persistentModel, name: "SignoffSnapshotRow")]
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
        case "StoreSemanticEnvelopeV6":
            return try subjects(
                category: .persistentModel,
                names: persistentModelNames + v6PersistentModelNames
            )
        case "StoreSemanticEnvelopeV7":
            return try subjects(
                category: .persistentModel,
                names: persistentModelNames + v6PersistentModelNames + v7PersistentModelNames
            )
        case "StoreSemanticEnvelopeV8":
            return try subjects(category: .persistentModel, names:
                persistentModelNames + v6PersistentModelNames + v7PersistentModelNames + v8PersistentModelNames)
        case "StoreSemanticEnvelopeV9":
            return try subjects(category: .persistentModel, names: activePersistentModelNames)
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

    static func locationPersistentDependencies(
        for name: String
    ) throws -> [SyncSubjectIdentityV1] {
        switch name {
        case "LocationNodeRow":
            return [try subject(category: .persistentModel, name: "Site")]
        case "LocationHierarchyEventRow":
            return try subjects(category: .persistentModel, names: ["LocationNodeRow", "Site"])
        case "AssetPlacementEventRow":
            return try subjects(category: .persistentModel, names: ["Asset", "LocationNodeRow", "Site"])
        case "AssetCompositionEdgeRow", "AssetCompositionEventRow":
            return [try subject(category: .persistentModel, name: "Asset")]
        case "LocationMigrationReceiptRow":
            return try subjects(category: .persistentModel, names: ["Asset", "AssetPlacementEventRow", "Site"])
        default:
            throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
    }

    static func partyPersistentDependencies(for name: String) throws -> [SyncSubjectIdentityV1] {
        switch name {
        case "ServicePartyRow": return []
        case "SitePartyRoleEventRow":
            return try subjects(category: .persistentModel, names: ["ServicePartyRow", "Site"])
        case "ActorSnapshotRow":
            return [try subject(category: .persistentModel, name: "ServicePartyRow")]
        case "QualificationSnapshotRow": return []
        case "SignoffSnapshotRow":
            return try subjects(category: .persistentModel, names: ["ActorSnapshotRow", "QualificationSnapshotRow", "ServicePartyRow"])
        default: throw CurrentSyncClassificationCatalogFailureV1.invalidInventory
        }
    }

    static func validatePersistentModels() throws {
        let frozenV5: [any PersistentModel.Type] = [
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
        let expected = frozenV5 + [
            LocationNodeRow.self,
            LocationHierarchyEventRow.self,
            AssetPlacementEventRow.self,
            AssetCompositionEdgeRow.self,
            AssetCompositionEventRow.self,
            LocationMigrationReceiptRow.self,
            SavedSmartViewRowV1.self,
            RequirementAssuranceRow.self,
            ServicePartyRow.self,
            SitePartyRoleEventRow.self,
            ActorSnapshotRow.self,
            QualificationSnapshotRow.self,
            SignoffSnapshotRow.self,
        ]
        let runtimeNames = PersistentSchemaV9.models.map { modelType in
            String(describing: modelType)
                .split(separator: ".")
                .last
                .map(String.init) ?? ""
        }.sorted()
        let frozenNames = PersistentSchemaV5.models.map { modelType in
            String(describing: modelType).split(separator: ".").last.map(String.init) ?? ""
        }.sorted()
        guard PersistentSchemaV5.models.count == frozenV5.count,
              Set(PersistentSchemaV5.models.map { ObjectIdentifier($0) })
                == Set(frozenV5.map { ObjectIdentifier($0) }),
              frozenNames == persistentModelNames,
              PersistentSchemaV9.models.count == expected.count,
              Set(PersistentSchemaV9.models.map { ObjectIdentifier($0) })
                == Set(expected.map { ObjectIdentifier($0) }),
              runtimeNames.count == Set(runtimeNames).count,
              runtimeNames.allSatisfy(ReplicationContractValidationV1.validToken),
              runtimeNames == activePersistentModelNames,
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

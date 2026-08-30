import Foundation
import XCTest

@testable import FieldEvidenceApp

private enum C53AssetServiceReliabilityBoundary_V10_03ReplicationConflictRegistryTests {
    static let typedAnchor: C53AssetServiceReliabilityBoundaryTokenV1.Type = C53AssetServiceReliabilityBoundaryTokenV1.self
}

extension V10_03ReplicationConflictRegistryTests {
    func testV23P03C57MyDayIsDeviceLocalDurableAndNotAReplicationLedger() throws {
        XCTAssertEqual(PersistentSchemaV42.models.count, 142)
        XCTAssertEqual(PersistentSchemaV42.models.count, PersistentSchemaV41.models.count + 2)
        XCTAssertTrue(PersistentSchemaV42.models.contains {
            ObjectIdentifier($0) == ObjectIdentifier(MyDayPlanRowV1.self)
        })
        XCTAssertTrue(PersistentSchemaV42.models.contains {
            ObjectIdentifier($0) == ObjectIdentifier(MyDayCarryoverReceiptRowV1.self)
        })
        XCTAssertFalse(CurrentSyncClassificationCatalogV1.persistentModelNames.contains(
            "MyDayPlanRowV1"
        ))
        XCTAssertFalse(CurrentSyncClassificationCatalogV1.persistentModelNames.contains(
            "MyDayCarryoverReceiptRowV1"
        ))
        XCTAssertTrue(C57MyDayLifecycleBoundaryV1.canonicalWriterIsIncumbentWorkspaceWriter)
    }
}

final class V10_03ReplicationConflictRegistryTests: XCTestCase {
    func testV23P03C40SupersessionCarriesDistinctReplicationAndConcurrencyIdentities() throws {
        let workspaceID = WorkspaceID(rawValue: Self.id(70))
        let mutationID = try MutationIDV1(rawValue: Self.id(71))
        let predecessorID = Self.id(72)
        let value = try AuthoritySourceReleaseV1(
            releaseID: Self.id(73), workspaceID: workspaceID, sourceID: Self.id(74),
            sourceType: .ownerPolicy, designation: "Replicated policy", editionOrRevision: "2",
            retrievedAt: Date(timeIntervalSince1970: 1_735_689_600),
            licenseStorageDisposition: .notStored, supersedesReleaseID: predecessorID,
            recordedAt: Date(timeIntervalSince1970: 1_735_689_600), revision: 2,
            mutationID: mutationID
        )
        let mutation = try AuthorityCriterionMutationV1(
            workspaceID: workspaceID, expectedRevision: 1, mutationID: mutationID,
            postImage: .supersedeAuthoritySource(value)
        )
        let postImage = try mutation.postImage.mutationPostImage
        XCTAssertEqual(try postImage.identity, try mutation.affectedIdentity)
        XCTAssertEqual(try postImage.concurrencyIdentity, try mutation.concurrencyIdentity)
        XCTAssertNotEqual(try postImage.identity, try postImage.concurrencyIdentity)

        let catalog = try CurrentSyncClassificationCatalogV1.current
        let registration = try catalog.registration(for: .init(
            category: .persistentModel, stableName: "AuthoritySourceReleaseRow"
        ))
        XCTAssertEqual(registration.classification, .replicated)
        XCTAssertEqual(registration.replicationPolicy.authority, .workspaceWriter)
        XCTAssertEqual(registration.replicationPolicy.bootstrap, .immutableHistory)
        XCTAssertEqual(registration.conflictPolicy.rule, .stableIDAppendUnion)
    }

    func testV23P03C39SuccessorConflictIsRejectedBeforeReplication() throws {
        let workspaceID = WorkspaceID()
        let mutationID = try MutationIDV1(rawValue: UUID())
        let predecessor = UUID(uuidString: "00000000-0000-0000-0000-000000002201")!
        let first = AssetSuccessorLinkV1(
            linkID: UUID(uuidString: "00000000-0000-0000-0000-000000002202")!,
            workspaceID: workspaceID,
            predecessorAssetID: predecessor,
            successorAssetID: UUID(uuidString: "00000000-0000-0000-0000-000000002203")!,
            predecessorLinkID: nil,
            revision: 1,
            mutationID: mutationID,
            recordedAt: Date(timeIntervalSince1970: 1_735_689_600),
            linkSHA256: String(repeating: "a", count: 64)
        )
        let conflicting = AssetSuccessorLinkV1(
            linkID: UUID(uuidString: "00000000-0000-0000-0000-000000002204")!,
            workspaceID: workspaceID,
            predecessorAssetID: predecessor,
            successorAssetID: UUID(uuidString: "00000000-0000-0000-0000-000000002205")!,
            predecessorLinkID: first.linkID,
            revision: 2,
            mutationID: mutationID,
            recordedAt: Date(timeIntervalSince1970: 1_735_689_600),
            linkSHA256: String(repeating: "a", count: 64)
        )
        XCTAssertThrowsError(try AssetSuccessorLinkV1.validateAcyclic([first, conflicting])) { error in
            XCTAssertEqual(error as? AssetSemanticContractFailureV1, .duplicateValue)
        }
    }

    func testV10_03G01CatalogCompletenessAndLifecycleRouting() throws {
        let fixture = try Self.loadFixture()
        XCTAssertEqual(fixture.schemaVersion, 1)
        XCTAssertEqual(fixture.cardID, "V23-P02-C03")
        XCTAssertEqual(Set(fixture.caseIDs), [
            "V23-P02-C03-G01", "V23-P02-C03-A01", "V23-P02-C03-H01",
            "V23-P02-C03-I01", "V23-P02-C03-R01",
        ])

        let catalog = try CurrentSyncClassificationCatalogV1.current
        try catalog.validate()
        let registrations = catalog.registrations
        // The current catalog is the complete post-C38 inventory. The older
        // fixture remains a compatibility baseline, while these counts bind
        // the active registry to its closed category declarations.
        XCTAssertEqual(registrations.count, 130)
        XCTAssertEqual(catalog.persistentModelSubjects.count, 27)
        XCTAssertEqual(catalog.ownedFileClassSubjects.count, 25)
        XCTAssertEqual(catalog.portableContentProjectionSubjects.count, 26)
        XCTAssertEqual(catalog.derivedIndexProjectionSubjects.count, 18)
        XCTAssertEqual(catalog.journalRecoverySubjects.count, 21)
        XCTAssertEqual(catalog.diagnosticSubjects.count, 13)
        XCTAssertTrue(catalog.secretSubjects.isEmpty)
        XCTAssertTrue(catalog.searchImplementationPresent)
        XCTAssertFalse(catalog.keychainUsageDeclared)
        let expectedCategoryCounts = [
            SyncSubjectCategoryV1.diagnostic.rawValue: 13,
            SyncSubjectCategoryV1.index.rawValue: 3,
            SyncSubjectCategoryV1.journal.rawValue: 21,
            SyncSubjectCategoryV1.ownedFileClass.rawValue: 25,
            SyncSubjectCategoryV1.persistentModel.rawValue: 27,
            SyncSubjectCategoryV1.projection.rawValue: 26,
            SyncSubjectCategoryV1.secret.rawValue: 0,
        ]
        XCTAssertEqual(
            Self.counts(registrations.map { $0.subject.category.rawValue }),
            expectedCategoryCounts
        )
        XCTAssertEqual(
            Self.counts(registrations.map { $0.classification.rawValue }).values.reduce(0, +),
            registrations.count
        )
        XCTAssertEqual(
            registrations.map(\.subject.canonicalKey),
            registrations.map(\.subject.canonicalKey).sorted()
        )

        for registration in registrations {
            try registration.validate()
            XCTAssertEqual(
                try catalog.registration(for: registration.subject),
                registration
            )
            let route = try catalog.lifecycleRoute(for: registration.subject)
            XCTAssertEqual(route.semanticBackup, registration.replicationPolicy.backup)
            XCTAssertEqual(route.portableExport, registration.replicationPolicy.export)
            XCTAssertEqual(route.deletion, registration.replicationPolicy.deletion)
            XCTAssertEqual(route.erase, registration.replicationPolicy.erase)
            switch registration.classification {
            case .replicated:
                XCTAssertEqual(
                    registration.replicationPolicy.transport,
                    .futureAcceptedMutationEligible
                )
            case .contentBlob:
                XCTAssertEqual(
                    registration.replicationPolicy.transport,
                    .futureBoundedBlobEligible
                )
            case .derivedRebuildable:
                XCTAssertEqual(registration.replicationPolicy.bootstrap, .rebuildFromDependencies)
                XCTAssertEqual(route.rebuild, .rebuildFromCanonicalDependencies)
            case .localOnly, .privateDeviceOnly:
                XCTAssertEqual(registration.replicationPolicy.transport, .excluded)
            }
        }
        XCTAssertEqual(catalog.lifecycleRoutes.count, registrations.count)
        let database = try SyncSubjectIdentityV1(
            category: .ownedFileClass,
            stableName: "database"
        )
        let databaseRoute = try catalog.lifecycleRoute(for: database)
        XCTAssertEqual(databaseRoute.filesystemBackup, .included)
        XCTAssertEqual(databaseRoute.semanticBackup, .exclude)
        XCTAssertEqual(databaseRoute.portableExport, .exclude)
        let records = try SyncSubjectIdentityV1(
            category: .projection,
            stableName: "V4BackupRecordsV1"
        )
        let recordsRoute = try catalog.lifecycleRoute(for: records)
        XCTAssertEqual(recordsRoute.filesystemBackup, .notApplicable)
        XCTAssertEqual(recordsRoute.semanticBackup, .includeCanonical)
        XCTAssertEqual(recordsRoute.portableExport, .portableCanonical)

        let observationRow = try SyncSubjectIdentityV1(
            category: .persistentModel,
            stableName: "ObservationAndTimeRow"
        )
        let workflowRecord = try SyncSubjectIdentityV1(
            category: .persistentModel,
            stableName: "WorkflowRecord"
        )
        let observationRegistration = try catalog.registration(for: observationRow)
        XCTAssertEqual(observationRegistration.classification, .replicated)
        XCTAssertEqual(observationRegistration.replicationPolicy.authority, .workspaceWriter)
        XCTAssertEqual(observationRegistration.replicationPolicy.persistence, .swiftDataRecord)
        XCTAssertEqual(
            observationRegistration.replicationPolicy.transport,
            .futureAcceptedMutationEligible
        )
        XCTAssertEqual(observationRegistration.replicationPolicy.bootstrap, .canonicalSnapshot)
        XCTAssertEqual(
            observationRegistration.replicationPolicy.retention,
            .untilCanonicalDeleteOrErase
        )
        XCTAssertEqual(observationRegistration.replicationPolicy.backup, .includeCanonical)
        XCTAssertEqual(observationRegistration.replicationPolicy.export, .portableCanonical)
        XCTAssertEqual(observationRegistration.replicationPolicy.deletion, .canonicalDelete)
        XCTAssertEqual(observationRegistration.conflictPolicy.rule, .exactRevisionManual)
        XCTAssertEqual(observationRegistration.replicationPolicy.dependencies, [workflowRecord])

        for projectionName in ["ObservationBasisV1", "TemporalContextV1"] {
            let projection = try SyncSubjectIdentityV1(
                category: .projection,
                stableName: projectionName
            )
            XCTAssertEqual(
                try catalog.registration(for: projection).replicationPolicy.dependencies,
                [observationRow]
            )
        }
        let backupWorkflow = try SyncSubjectIdentityV1(
            category: .projection,
            stableName: "V4BackupWorkflowRecordDTO"
        )
        XCTAssertEqual(
            try catalog.registration(for: backupWorkflow).replicationPolicy.dependencies,
            [observationRow, workflowRecord].sorted { $0.canonicalKey < $1.canonicalKey }
        )
    }

    func testV23P03C38CatalogFixtureParityKeepsRowsReplicatedAndProjectionsBounded() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = root.appendingPathComponent(
            "FieldEvidenceAppTests/Fixtures/V21/Accountability/V21P03C38PartyAccountabilityCorpusV1.json"
        )
        let fixtureObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any]
        )
        XCTAssertEqual(fixtureObject["cardID"] as? String, "V23-P03-C38")
        XCTAssertEqual(fixtureObject["schema"] as? String, "V21P03C38PartyAccountabilityCorpusV1")
        XCTAssertEqual(fixtureObject["synthetic"] as? Bool, true)
        XCTAssertEqual(fixtureObject["containsCustomerData"] as? Bool, false)
        XCTAssertEqual(fixtureObject["containsSecrets"] as? Bool, false)

        let catalog = try CurrentSyncClassificationCatalogV1.current
        let rowNames = [
            "ServicePartyRow", "SitePartyRoleEventRow", "ActorSnapshotRow",
            "QualificationSnapshotRow", "SignoffSnapshotRow",
        ]
        for name in rowNames {
            let subject = try SyncSubjectIdentityV1(category: .persistentModel, stableName: name)
            let registration = try catalog.registration(for: subject)
            XCTAssertEqual(registration.classification, .replicated, name)
            XCTAssertEqual(registration.replicationPolicy.authority, .workspaceWriter, name)
            XCTAssertEqual(registration.replicationPolicy.persistence, .swiftDataRecord, name)
            XCTAssertEqual(registration.replicationPolicy.backup, .includeCanonical, name)
            XCTAssertEqual(registration.replicationPolicy.export, .portableCanonical, name)
        }
        for name in [
            "ServicePartyReferenceV1", "SitePartyRoleEventV1", "ActorSnapshotV1",
            "QualificationSnapshotV1", "SignoffSnapshotV1",
        ] {
            let subject = try SyncSubjectIdentityV1(category: .projection, stableName: name)
            let registration = try catalog.registration(for: subject)
            XCTAssertEqual(registration.classification, .derivedRebuildable, name)
            XCTAssertEqual(registration.replicationPolicy.bootstrap, .rebuildFromDependencies, name)
            XCTAssertEqual(registration.replicationPolicy.transport, .excluded, name)
            XCTAssertEqual(registration.replicationPolicy.export, .portableCanonical, name)
        }
        let envelope = try catalog.registration(for: SyncSubjectIdentityV1(
            category: .projection,
            stableName: "StoreSemanticEnvelopeV9"
        ))
        XCTAssertEqual(envelope.classification, .derivedRebuildable)
        XCTAssertEqual(envelope.replicationPolicy.bootstrap, .rebuildFromDependencies)
        XCTAssertEqual(envelope.replicationPolicy.export, .exclude)
    }

    func testV10_03A01SixRuleMatrixAndPermutationIdentity() throws {
        let fixture = try Self.loadFixture()
        XCTAssertEqual(fixture.rules.count, ConflictRuleV1.allCases.count)
        let subject = Self.subject()
        let competitors = try (0..<3).map(Self.competitor)

        for ruleCase in fixture.rules {
            let rule = try XCTUnwrap(ConflictRuleV1(rawValue: ruleCase.rule))
            let disposition = try XCTUnwrap(
                ConflictDispositionV1(rawValue: ruleCase.disposition)
            )
            let policy = try ConflictPolicyV1(
                policyID: "conflict.synthetic.\(rule.rawValue.lowercased())",
                rule: rule
            )
            let basis = try ConflictResolutionBasisV1(
                subject: subject,
                policy: policy,
                competitors: Array(competitors.prefix(2)),
                causalFrontier: try ConflictCausalFrontierV1(
                    baseRevision: 7,
                    baseSemanticSHA256: Self.digest(14),
                    observedInputs: [competitors[0]]
                ),
                disposition: disposition
            )
            try basis.validate()
            XCTAssertEqual(basis.disposition, disposition)
        }

        let identityPolicy = try ConflictPolicyV1(
            policyID: "conflict.synthetic.permutation",
            rule: .exactRevisionManual
        )
        let twoWay = try fixture.permutations.twoWay.map { permutation in
            try ConflictIdentityV1.derive(
                subject: subject,
                policy: identityPolicy,
                competitors: permutation.map { competitors[$0] }
            )
        }
        XCTAssertEqual(Set(twoWay.map(\.digestSHA256)).count, 1)
        let threeWay = try fixture.permutations.threeWay.map { permutation in
            try ConflictIdentityV1.derive(
                subject: subject,
                policy: identityPolicy,
                competitors: permutation.map { competitors[$0] }
            )
        }
        XCTAssertEqual(Set(threeWay.map(\.digestSHA256)).count, 1)
        XCTAssertNotEqual(twoWay[0], threeWay[0])
    }

    func testV10_03H01UnknownLimitsPrivacyDependencyLeakAndCollisionRejection() throws {
        let fixture = try Self.loadFixture()
        XCTAssertEqual(fixture.hostileCases.count, 17)
        XCTAssertTrue(fixture.privacy.syntheticOnly)
        XCTAssertFalse(fixture.privacy.containsCustomerData)
        XCTAssertFalse(fixture.privacy.containsSecrets)

        let policy = try ConflictPolicyV1(policyID: "conflict.synthetic.hostile", rule: .deleteWins)
        let policyData = try WorkspaceMutationCanonicalV1.data(policy)
        let futurePolicy = try XCTUnwrap(String(data: policyData, encoding: .utf8))
            .replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2")
            .data(using: .utf8)!
        let decodedFuture = try JSONDecoder().decode(ConflictPolicyV1.self, from: futurePolicy)
        XCTAssertThrowsError(try decodedFuture.validate()) {
            XCTAssertEqual($0 as? ConflictPolicyFailureV1, .invalidPolicy)
        }
        let unknownRule = try XCTUnwrap(String(data: policyData, encoding: .utf8))
            .replacingOccurrences(of: ConflictRuleV1.deleteWins.rawValue, with: "UNKNOWN_RULE")
            .data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(ConflictPolicyV1.self, from: unknownRule))

        let currentCatalog = try CurrentSyncClassificationCatalogV1.current
        let registeredModelNames = currentCatalog.registrations
            .filter { $0.subject.category == .persistentModel }
            .map(\.subject.stableName)
        XCTAssertEqual(registeredModelNames.count, 22)
        XCTAssertEqual(Set(registeredModelNames).count, registeredModelNames.count)
        XCTAssertEqual(
            registeredModelNames.sorted(),
            CurrentSyncClassificationCatalogV1.activePersistentModelNames.sorted()
        )
        XCTAssertEqual(CurrentSyncClassificationCatalogV1.persistentModelNames.count, 14)
        XCTAssertTrue(
            Set(CurrentSyncClassificationCatalogV1.persistentModelNames)
                .isSubset(of: Set(registeredModelNames))
        )
        XCTAssertEqual(
            Set(CurrentSyncClassificationCatalogV1.v6PersistentModelNames),
            Set([
                "AssetCompositionEdgeRow", "AssetCompositionEventRow",
                "AssetPlacementEventRow", "LocationHierarchyEventRow",
                "LocationMigrationReceiptRow", "LocationNodeRow",
            ])
        )
        for name in CurrentSyncClassificationCatalogV1.v6PersistentModelNames {
            let registration = try currentCatalog.registration(for: .init(
                category: .persistentModel,
                stableName: name
            ))
            XCTAssertEqual(registration.replicationPolicy.persistence, .swiftDataRecord)
            XCTAssertEqual(registration.replicationPolicy.authority, .workspaceWriter)
        }
        XCTAssertEqual(CurrentSyncClassificationCatalogV1.v7PersistentModelNames, ["SavedSmartView"])
        for name in CurrentSyncClassificationCatalogV1.v7PersistentModelNames {
            let registration = try currentCatalog.registration(for: .init(
                category: .persistentModel,
                stableName: name
            ))
            XCTAssertEqual(registration.replicationPolicy.persistence, .swiftDataRecord)
            XCTAssertEqual(registration.replicationPolicy.authority, .workspaceWriter)
        }
        XCTAssertEqual(
            CurrentSyncClassificationCatalogV1.v8PersistentModelNames,
            ["RequirementAssuranceRow"]
        )
        for name in CurrentSyncClassificationCatalogV1.v8PersistentModelNames {
            XCTAssertTrue(registeredModelNames.contains(name))
        }
        let registeredFileNames = currentCatalog.registrations
            .filter { $0.subject.category == .ownedFileClass }
            .map(\.subject.stableName)
        XCTAssertEqual(registeredFileNames.count, 21)
        XCTAssertTrue(registeredFileNames.contains("searchIndex"))
        XCTAssertEqual(Set(registeredFileNames).count, registeredFileNames.count)
        XCTAssertEqual(
            registeredFileNames.sorted(),
            CurrentSyncClassificationCatalogV1.ownedFileClassNames.sorted()
        )
        for category in [SyncSubjectCategoryV1.persistentModel, .ownedFileClass] {
            let unknown = try SyncSubjectIdentityV1(
                category: category,
                stableName: "SyntheticUnknownDeclaredKind"
            )
            XCTAssertThrowsError(try currentCatalog.registration(for: unknown)) {
                XCTAssertEqual(
                    $0 as? CurrentSyncClassificationCatalogFailureV1,
                    .invalidInventory
                )
            }
        }
        XCTAssertEqual(
            Set(ReplicationAuthorityV1.allCases.map(\.rawValue)),
            [
                "WORKSPACE_WRITER", "IMMUTABLE_CONTENT_WRITER", "LOCAL_DEVICE",
                "DERIVED_FROM_CANONICAL_INPUTS",
            ]
        )
        XCTAssertFalse(
            ReplicationAuthorityV1.allCases.map(\.rawValue).contains("EXTERNAL_PROVIDER")
        )
        XCTAssertEqual(
            Set(ReplicationRetentionV1.allCases.map(\.rawValue)),
            [
                "UNTIL_CANONICAL_DELETE_OR_ERASE", "IMMUTABLE_HISTORY_UNTIL_ERASE",
                "REBUILDABLE", "OPERATION_SCOPED", "LOCAL_DEVICE_RETAINED",
            ]
        )
        XCTAssertFalse(
            ReplicationRetentionV1.allCases.map(\.rawValue).contains("PROVIDER_CONTROLLED_CACHE")
        )
        let privateDeviceRows = currentCatalog.registrations.filter {
            $0.classification == .privateDeviceOnly
        }
        XCTAssertFalse(privateDeviceRows.isEmpty)
        XCTAssertTrue(privateDeviceRows.allSatisfy {
            $0.replicationPolicy.authority == .localDevice
                && $0.replicationPolicy.retention == .localDeviceRetained
        })
        let replicated = try XCTUnwrap(
            currentCatalog.registrations.first {
                $0.classification == .replicated
            }
        )
        let registrationData = try WorkspaceMutationCanonicalV1.data(replicated)
        let unknownClass = try XCTUnwrap(String(data: registrationData, encoding: .utf8))
            .replacingOccurrences(of: SyncClassificationV1.replicated.rawValue, with: "UNKNOWN_CLASS")
            .data(using: .utf8)!
        XCTAssertThrowsError(
            try JSONDecoder().decode(SyncClassificationRegistrationV1.self, from: unknownClass)
        )

        XCTAssertThrowsError(try ConflictIdentityV1.derive(
            subject: Self.subject(),
            policy: policy,
            competitors: try (0...64).map(Self.competitor)
        )) {
            XCTAssertEqual($0 as? ConflictPolicyFailureV1, .tooManyCompetitors)
        }
        let duplicateID = try MutationIDV1(rawValue: Self.id(90))
        XCTAssertThrowsError(try ConflictIdentityV1.derive(
            subject: Self.subject(),
            policy: policy,
            competitors: [
                try .init(mutationID: duplicateID, canonicalInputSHA256: Self.digest(1)),
                try .init(mutationID: duplicateID, canonicalInputSHA256: Self.digest(2)),
            ]
        )) {
            XCTAssertEqual($0 as? ConflictPolicyFailureV1, .duplicateMutationID)
        }

        XCTAssertThrowsError(try ReplicationPolicyV1(
            policyID: "policy.synthetic.private-leak",
            authority: .localDevice,
            persistence: .ownedFile,
            transport: .futureAcceptedMutationEligible,
            bootstrap: .destinationLocal,
            privacy: .privateDeviceData,
            retention: .localDeviceRetained,
            codec: try .init(codecID: "codec.synthetic.private", readableVersions: [1], currentWriteVersion: 1),
            sizeLimit: .boundedBytes(1),
            dependencies: [],
            backup: .exclude,
            export: .exclude,
            deletion: .localAuthority,
            erase: .localAuthority
        )) {
            XCTAssertEqual($0 as? ReplicationPolicyFailureV1, .privateTransportEnabled)
        }
        XCTAssertThrowsError(try ReplicationPolicyV1(
            policyID: "policy.synthetic.secret-backup-leak",
            authority: .localDevice,
            persistence: .nonpersistent,
            transport: .excluded,
            bootstrap: .excluded,
            privacy: .secretNeverPortable,
            retention: .operationScoped,
            codec: try .init(codecID: "codec.synthetic.secret", readableVersions: [1], currentWriteVersion: 1),
            sizeLimit: .boundedBytes(1),
            dependencies: [],
            backup: .includeCanonical,
            export: .exclude,
            deletion: .localAuthority,
            erase: .localAuthority
        )) {
            XCTAssertEqual($0 as? ReplicationPolicyFailureV1, .secretPortabilityEnabled)
        }
        let localSecret = try ReplicationPolicyV1(
            policyID: "policy.synthetic.secret-local",
            authority: .localDevice,
            persistence: .nonpersistent,
            transport: .excluded,
            bootstrap: .excluded,
            privacy: .secretNeverPortable,
            retention: .operationScoped,
            codec: try .init(codecID: "codec.synthetic.secret", readableVersions: [1], currentWriteVersion: 1),
            sizeLimit: .boundedBytes(1),
            dependencies: [],
            backup: .exclude,
            export: .exclude,
            deletion: .localAuthority,
            erase: .localAuthority
        )
        let secretExportLeak = try XCTUnwrap(
            String(data: localSecret.canonicalData(), encoding: .utf8)
        )
            .replacingOccurrences(of: "\"export\":\"EXCLUDE\"", with: "\"export\":\"PORTABLE_CANONICAL\"")
            .data(using: .utf8)!
        XCTAssertThrowsError(try ReplicationPolicyV1.decodeCanonical(from: secretExportLeak)) {
            XCTAssertEqual($0 as? ReplicationPolicyFailureV1, .secretPortabilityEnabled)
        }
        let reviewedDiagnostic = try currentCatalog.registration(for: .init(
            category: .diagnostic,
            stableName: "DiagnosticExportV1"
        ))
        XCTAssertEqual(reviewedDiagnostic.classification, .privateDeviceOnly)
        XCTAssertEqual(reviewedDiagnostic.replicationPolicy.privacy, .noncustomerDiagnostic)
        XCTAssertEqual(reviewedDiagnostic.replicationPolicy.transport, .excluded)
        XCTAssertEqual(reviewedDiagnostic.replicationPolicy.backup, .exclude)
        XCTAssertEqual(reviewedDiagnostic.replicationPolicy.export, .exclude)
        let dependencyA = try SyncSubjectIdentityV1(category: .projection, stableName: "zeta")
        let dependencyB = try SyncSubjectIdentityV1(category: .projection, stableName: "alpha")
        XCTAssertThrowsError(try ReplicationPolicyV1(
            policyID: "policy.synthetic.dependencies",
            authority: .derivedFromCanonicalInputs,
            persistence: .nonpersistent,
            transport: .excluded,
            bootstrap: .rebuildFromDependencies,
            privacy: .workspaceData,
            retention: .rebuildable,
            codec: try .init(codecID: "codec.synthetic.dependencies", readableVersions: [1], currentWriteVersion: 1),
            sizeLimit: .notApplicable,
            dependencies: [dependencyA, dependencyB],
            backup: .rebuildAfterRestore,
            export: .exclude,
            deletion: .rebuild,
            erase: .rebuildAfterErase
        )) {
            XCTAssertEqual($0 as? ReplicationPolicyFailureV1, .invalidDependencies)
        }
        XCTAssertLessThan(
            currentCatalog.registrations.count,
            SyncClassificationRegistryV1.maximumRegistrationCount
        )
        XCTAssertEqual(ConflictCompetitorV1.maximumCount, 64)
    }

    func testV10_03I01NamedInputsDeferredAndInterruptionBoundaries() throws {
        let fixture = try Self.loadFixture()
        XCTAssertEqual(fixture.interruptionBoundaries.count, 4)
        XCTAssertTrue(fixture.lifecycle.resolutionRequiresAllNamedInputs)
        XCTAssertTrue(fixture.lifecycle.declarationOnlyNoDurableState)
        let competitors = try (0..<3).map(Self.competitor)
        let basis = try Self.basis(competitors: competitors)

        XCTAssertEqual(
            try basis.readiness(availableInputs: []),
            .deferred(missingInputs: competitors)
        )
        XCTAssertEqual(
            try basis.readiness(availableInputs: [competitors[0]]),
            .deferred(missingInputs: [competitors[1], competitors[2]])
        )
        XCTAssertEqual(try basis.readiness(availableInputs: competitors), .ready)
        let late = try Self.competitor(3)
        let expectedSuccessor = try basis.successor(adding: late)
        XCTAssertEqual(
            try basis.readiness(availableInputs: competitors + [late]),
            .successorRequired(
                identity: expectedSuccessor,
                unexpectedInputs: [late]
            )
        )

        let bytes = try basis.canonicalData()
        XCTAssertThrowsError(
            try JSONDecoder().decode(ConflictResolutionBasisV1.self, from: Data(bytes.dropLast()))
        )
        let relaunched = try ConflictResolutionBasisV1.decodeCanonical(from: bytes)
        try relaunched.validate()
        XCTAssertEqual(try relaunched.canonicalData(), bytes)
        XCTAssertEqual(
            try relaunched.readiness(availableInputs: [competitors[0], competitors[2]]),
            .deferred(missingInputs: [competitors[1]])
        )
    }

    func testV10_03R01FrozenBasisRelaunchIdempotencyAndLateCompetitor() throws {
        let fixture = try Self.loadFixture()
        XCTAssertTrue(fixture.lifecycle.basisIsFrozen)
        XCTAssertTrue(fixture.lifecycle.lateCompetitorCreatesSuccessor)
        XCTAssertTrue(fixture.lifecycle.lateInputRequiresSuccessor)
        let originalCompetitors = try (0..<2).map(Self.competitor)
        let basis = try Self.basis(competitors: originalCompetitors)
        let frozenBytes = try basis.canonicalData()
        let relaunched = try ConflictResolutionBasisV1.decodeCanonical(from: frozenBytes)
        try relaunched.validate()
        XCTAssertEqual(relaunched, basis)
        XCTAssertEqual(try relaunched.canonicalData(), frozenBytes)
        XCTAssertEqual(
            try basis.successor(adding: originalCompetitors[0]),
            basis.conflictIdentity
        )

        let late = try Self.competitor(2)
        let successor = try basis.successor(adding: late)
        XCTAssertNotEqual(successor, basis.conflictIdentity)
        XCTAssertEqual(successor, try relaunched.successor(adding: late))
        XCTAssertEqual(
            try relaunched.readiness(
                availableInputs: [late] + Array(originalCompetitors.reversed())
            ),
            .successorRequired(identity: successor, unexpectedInputs: [late])
        )
        let direct = try ConflictIdentityV1.derive(
            subject: basis.subject,
            policy: basis.policy,
            competitors: [late] + Array(originalCompetitors.reversed())
        )
        XCTAssertEqual(successor, direct)
        XCTAssertEqual(try basis.canonicalData(), frozenBytes)
    }

    private static func subject() -> ConflictSubjectIdentityV1 {
        .workspace(WorkspaceID(rawValue: id(1)))
    }

    private static func competitor(_ index: Int) throws -> ConflictCompetitorV1 {
        try .init(
            mutationID: MutationIDV1(rawValue: id(UInt8(index + 10))),
            canonicalInputSHA256: digest(index + 1)
        )
    }

    private static func basis(
        competitors: [ConflictCompetitorV1]
    ) throws -> ConflictResolutionBasisV1 {
        try ConflictResolutionBasisV1(
            subject: subject(),
            policy: ConflictPolicyV1(
                policyID: "conflict.synthetic.frozen",
                rule: .exactRevisionManual
            ),
            competitors: competitors,
            causalFrontier: ConflictCausalFrontierV1(
                baseRevision: 11,
                baseSemanticSHA256: digest(11),
                observedInputs: [competitors[0]]
            ),
            disposition: .manualResolutionRequired
        )
    }

    private static func digest(_ value: Int) -> String {
        String(format: "%064x", value)
    }

    private static func id(_ byte: UInt8) -> UUID {
        UUID(uuid: (byte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, byte))
    }

    private static func counts(_ values: [String]) -> [String: Int] {
        values.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    private static func loadFixture() throws -> ReplicationConflictPolicyCorpusFixtureV1 {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(
            forResource: "V21P02C03ReplicationConflictPolicyCorpusV1",
            withExtension: "json",
            subdirectory: "Fixtures/V21/ReplicationPolicy"
        ) ?? bundle.url(
            forResource: "V21P02C03ReplicationConflictPolicyCorpusV1",
            withExtension: "json"
        ))
        return try JSONDecoder().decode(
            ReplicationConflictPolicyCorpusFixtureV1.self,
            from: Data(contentsOf: url)
        )
    }
}

extension V10_03ReplicationConflictRegistryTests {
    func testV23P03C15ReplicationClassifiesIdempotentAndDivergentPackets() throws {
        let fixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 150_203)
        XCTAssertEqual(
            try WorkPacketReplayValidatorV1.disposition(
                existing: fixture.claim, incoming: fixture.claim, identityMatches: true
            ), .idempotentReplay
        )
        XCTAssertEqual(
            try WorkPacketReplayValidatorV1.disposition(
                existing: fixture.manifest, incoming: fixture.alternateManifest, identityMatches: true
            ), .quarantineDivergentBytes
        )
        XCTAssertEqual(WorkPacketConflictKindV1.divergentSameIdentity.rawValue, "DIVERGENT_SAME_IDENTITY")
    }
}

extension V10_03ReplicationConflictRegistryTests {
    func testV23P03C54EncryptedEnvelopeSecretsScratchAndSessionsNeverBecomeSyncTruth() {
        XCTAssertTrue(C54EncryptedPortableEnvelopeSyncClassificationBoundaryV1.validate())
        XCTAssertEqual(C54EncryptedPortableEnvelopeSyncClassificationBoundaryV1.envelopeSession, "NONPERSISTENT")
        XCTAssertEqual(C54EncryptedPortableEnvelopeSyncClassificationBoundaryV1.passphrase, "MEMORY_ONLY")
        XCTAssertEqual(C54EncryptedPortableEnvelopeSyncClassificationBoundaryV1.derivedKey, "MEMORY_ONLY")
        XCTAssertEqual(C54EncryptedPortableEnvelopeSyncClassificationBoundaryV1.syncDisposition, "NOT_APPLICABLE")
        XCTAssertEqual(C54EncryptedPortableEnvelopeSyncClassificationBoundaryV1.integrationEventCountAdded, 0)
        XCTAssertTrue(C54EncryptedPortableEnvelopeSyncClassificationBoundaryV1.canonicalInnerPayloadKeepsExistingOwner)
    }
}

extension V10_03ReplicationConflictRegistryTests {
    func testV23P03C34PackageSurfaceCannotAddShellParserOrWriter() throws {
        let route = PackageSurfaceRouteV1(
            routeID: "package.surface.c34",
            root: .assets,
            destination: .packageSurface,
            kind: .destination,
            startsAutomaticWork: false
        )
        let manifest = try PackageSurfaceManifestV1(
            packageID: "package.c34", routes: [route]
        )
        let registry = try RouteRegistryV1(manifests: [manifest])
        let receipt = RouteConformanceReceiptV1(
            registry: registry, evidenceKind: .alternate,
            observedShellCount: 1, observedParserCount: 1,
            observedMutationAuthorityCount: 0
        )
        try receipt.validate()
        XCTAssertEqual(receipt.mutationAuthorityCount, 0)
        XCTAssertEqual(receipt.shellCount, 1)
        XCTAssertEqual(receipt.parserCount, 1)
        XCTAssertThrowsError(
            try PackageSurfaceManifestV1(
                packageID: "package.c34.shell", routes: [route], addsNavigationShell: true
            )
        )
    }
}

extension V10_03ReplicationConflictRegistryTests {
    func testV23P03C36ConflictPlanRejectsDivergentSagaAndKeepsExplicitChoicesClosed() throws {
        let fixture = try C36FieldDraftTestSupportV1.makeFixture()
        XCTAssertEqual(DraftConflictResolutionPlanV1.allCases, [
            .reviewAndRebase, .commitAsCopy, .continueEditing, .discard
        ])
        XCTAssertEqual(fixture.recoverySaga.state, .recoveryRequired)
        XCTAssertEqual(fixture.conflictedSaga.state, .conflicted)

        let divergentPlan = try DraftCommitPlanV1(
            planID: C36FieldDraftTestSupportV1.id(138_000), workspaceID: fixture.workspaceID,
            draftID: fixture.draftID, draftRevision: fixture.plan.draftRevision,
            baseCanonicalRevision: fixture.plan.baseCanonicalRevision,
            payloadSHA256: fixture.plan.payloadSHA256, stageDigests: fixture.plan.stageDigests,
            targetCommandKind: fixture.plan.targetCommandKind,
            expectedTargetRevision: fixture.plan.expectedTargetRevision,
            mutationID: try C36FieldDraftTestSupportV1.mutation(138_001), outputKeys: ["divergent"]
        )
        let divergentSaga = try DraftCommitSagaV1(
            sagaID: C36FieldDraftTestSupportV1.id(138_002), workspaceID: fixture.workspaceID,
            draftID: fixture.draftID, plan: divergentPlan, state: .contentPromotedUnbound,
            predecessorSagaID: fixture.preparedSaga.sagaID, revision: 2,
            mutationID: try C36FieldDraftTestSupportV1.mutation(138_003),
            updatedAt: C36FieldDraftTestSupportV1.fixedDate.addingTimeInterval(30)
        )
        XCTAssertThrowsError(try divergentSaga.validateSuccessor(of: fixture.preparedSaga))
        XCTAssertNotEqual(divergentSaga.plan.planSHA256, fixture.plan.planSHA256)
    }
}

private struct ReplicationConflictPolicyCorpusFixtureV1: Decodable {
    struct InventoryExpectations: Decodable {
        let registrationCount: Int
        let persistentModelCount: Int
        let ownedFileClassCount: Int
        let portableContentProjectionCount: Int
        let derivedIndexProjectionCount: Int
        let journalRecoveryCount: Int
        let diagnosticCount: Int
        let categoryCounts: [String: Int]
        let classificationCounts: [String: Int]
    }

    struct RuleCase: Decodable {
        let rule: String
        let disposition: String
    }

    struct Permutations: Decodable {
        let twoWay: [[Int]]
        let threeWay: [[Int]]
    }

    struct Lifecycle: Decodable {
        let resolutionRequiresAllNamedInputs: Bool
        let basisIsFrozen: Bool
        let lateCompetitorCreatesSuccessor: Bool
        let lateInputRequiresSuccessor: Bool
        let declarationOnlyNoDurableState: Bool
    }

    struct Privacy: Decodable {
        let syntheticOnly: Bool
        let containsCustomerData: Bool
        let containsSecrets: Bool
    }

    let schema: String
    let schemaVersion: Int
    let cardID: String
    let caseIDs: [String]
    let inventoryExpectations: InventoryExpectations
    let rules: [RuleCase]
    let permutations: Permutations
    let hostileCases: [String]
    let interruptionBoundaries: [String]
    let lifecycle: Lifecycle
    let privacy: Privacy
}

extension V10_03ReplicationConflictRegistryTests {
    func testV23P03C41ReplicationSuccessorBindsPredecessorAndRevision() throws {
        let fixture = try C41FunctionalRelationshipTestSupportV1.makeFixture(seed: 41_030)

        try fixture.superseded.validateSuccessor(of: fixture.added)
        XCTAssertEqual(fixture.superseded.action, .superseded)
        XCTAssertEqual(fixture.superseded.predecessorEventID, fixture.added.eventID)
        XCTAssertEqual(
            fixture.superseded.expectedRelationshipRevision,
            fixture.added.revision
        )
        XCTAssertEqual(fixture.superseded.revision, fixture.added.revision + 1)
        XCTAssertNotEqual(fixture.superseded.mutationID, fixture.added.mutationID)
        XCTAssertEqual(fixture.superseded.workspaceID, fixture.added.workspaceID)
    }
}

extension V10_03ReplicationConflictRegistryTests {
    func testV23P03C13ReplicationSuccessorsRetainPredecessorAndConcurrencyIdentity() throws {
        let fixture = try C13EvidenceAssuranceTestSupportV1.makeFixture(seed: 51_030)
        let successorVisibility = try EvidenceVisibilityV1(
            visibilityID: C13EvidenceAssuranceTestSupportV1.id(51_031),
            workspaceID: fixture.workspaceID,
            sensitivity: .routine,
            allowedAudiences: [.internalReview, .customerReport],
            effectiveAt: C13EvidenceAssuranceTestSupportV1.fixedDate.addingTimeInterval(1),
            supersedesVisibilityID: fixture.routineVisibility.visibilityID,
            revision: 2,
            mutationID: try C13EvidenceAssuranceTestSupportV1.mutation(51_032)
        )
        try successorVisibility.validateSuccessor(of: fixture.routineVisibility)
        let identity = try WorkspaceEntityIdentityV1(kind: .evidenceVisibility, id: successorVisibility.visibilityID)
        let predecessor = try WorkspaceEntityIdentityV1(kind: .evidenceVisibility, id: fixture.routineVisibility.visibilityID)

        XCTAssertEqual(identity.kind, .evidenceVisibility)
        XCTAssertEqual(identity.id, successorVisibility.visibilityID)
        XCTAssertNotEqual(identity, predecessor)
        XCTAssertEqual(successorVisibility.revision, fixture.routineVisibility.revision + 1)
        XCTAssertEqual(successorVisibility.workspaceID, fixture.routineVisibility.workspaceID)
    }
}

extension V10_03ReplicationConflictRegistryTests {
    func testV23P03C14PolicyReplicaRequiresDirectPredecessor() throws {
        let fixture = try C14InspectionReviewTestSupportV1.makeFixture(seed: 145_103)
        try fixture.supersedingPolicy.validateSuccessor(of: fixture.policy)
        XCTAssertEqual(fixture.supersedingPolicy.supersedesReleaseID, fixture.policy.releaseID)
        XCTAssertEqual(fixture.supersedingPolicy.revision, fixture.policy.revision + 1)
        XCTAssertNotEqual(fixture.supersedingPolicy.policySHA256, fixture.policy.policySHA256)
    }
}

extension V10_03ReplicationConflictRegistryTests {
    func testV23P03C18RegistryPointerConflictAndRollbackPolicyRemainClosed() throws {
        XCTAssertEqual(
            PackageRollbackCompatibilityV1.preActivationDiscardable.rawValue,
            "PRE_ACTIVATION_DISCARDABLE"
        )
        XCTAssertEqual(
            PackageRollbackCompatibilityV1.activatedForwardFixRequired.rawValue,
            "ACTIVATED_FORWARD_FIX_REQUIRED"
        )
        XCTAssertEqual(
            PackageEvolutionLifecycleV1.downgradePolicy,
            "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V17_WRITE"
        )
        XCTAssertTrue(PackageEvolutionLifecycleV1.persistent)
        XCTAssertTrue(PackageEvolutionLifecycleV1.backupRestoreRequired)
        XCTAssertEqual(
            PackageEvolutionLifecycleV1.interruption,
            "OLD_COMPLETE_OR_NEW_COMPLETE_NEVER_HYBRID"
        )
    }

    func testV23P03C19ReplayIdentityIsMutationAndDigestBound() throws {
        let fixture = try C19MeasurementIntegrityTestSupport.makeFixture()
        let bytes = try MeasurementIntegrityCanonicalCodecV1.encode(fixture.bundle)
        let replayed = try MeasurementIntegrityCanonicalCodecV1.decode(
            MeasurementIntegrityAtomicBundleV1.self, from: bytes
        )
        XCTAssertEqual(replayed.mutationID, fixture.bundle.mutationID)
        XCTAssertEqual(replayed.bundleSHA256, fixture.bundle.bundleSHA256)
        XCTAssertEqual(replayed.captures.map(\.captureID), fixture.bundle.captures.map(\.captureID))
    }

    func testC20PrivacyTransformBackupKindsHaveDistinctTypedIdentity() throws {
        let fixture = try C20PrivacyTransformTestSupport.makeFixture()
        XCTAssertEqual(V19BackupPrivacyTransformRecordV1.Kind.allCases.count, 4)
        let keys = fixture.backupRecords.map { "\($0.kind.rawValue)|\($0.id.uuidString)" }
        XCTAssertEqual(Set(keys).count, keys.count)
    }
}

extension V10_03ReplicationConflictRegistryTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}

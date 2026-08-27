import Foundation
import XCTest

@testable import FieldEvidenceApp

final class V10_03ReplicationConflictRegistryTests: XCTestCase {
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
        // The inherited C03 fixture is the transport-policy baseline. Card27 adds one
        // canonical model, two portable projections, and three derived projections.
        XCTAssertEqual(registrations.count, fixture.inventoryExpectations.registrationCount + 6)
        XCTAssertEqual(
            catalog.persistentModelSubjects.count,
            fixture.inventoryExpectations.persistentModelCount + 1
        )
        XCTAssertEqual(
            catalog.ownedFileClassSubjects.count,
            fixture.inventoryExpectations.ownedFileClassCount
        )
        XCTAssertEqual(
            catalog.portableContentProjectionSubjects.count,
            fixture.inventoryExpectations.portableContentProjectionCount + 2
        )
        XCTAssertEqual(
            catalog.derivedIndexProjectionSubjects.count,
            fixture.inventoryExpectations.derivedIndexProjectionCount + 3
        )
        XCTAssertEqual(
            catalog.journalRecoverySubjects.count,
            fixture.inventoryExpectations.journalRecoveryCount
        )
        XCTAssertEqual(
            catalog.diagnosticSubjects.count,
            fixture.inventoryExpectations.diagnosticCount
        )
        XCTAssertTrue(catalog.secretSubjects.isEmpty)
        XCTAssertFalse(catalog.searchImplementationPresent)
        XCTAssertFalse(catalog.keychainUsageDeclared)
        var expectedCategoryCounts = fixture.inventoryExpectations.categoryCounts
        expectedCategoryCounts[SyncSubjectCategoryV1.persistentModel.rawValue, default: 0] += 1
        expectedCategoryCounts[SyncSubjectCategoryV1.projection.rawValue, default: 0] += 5
        XCTAssertEqual(
            Self.counts(registrations.map { $0.subject.category.rawValue }),
            expectedCategoryCounts
        )
        var expectedClassificationCounts = fixture.inventoryExpectations.classificationCounts
        expectedClassificationCounts[SyncClassificationV1.replicated.rawValue, default: 0] += 1
        expectedClassificationCounts[SyncClassificationV1.derivedRebuildable.rawValue, default: 0] += 5
        XCTAssertEqual(
            Self.counts(registrations.map { $0.classification.rawValue }),
            expectedClassificationCounts
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
        XCTAssertEqual(registeredModelNames.count, 21)
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

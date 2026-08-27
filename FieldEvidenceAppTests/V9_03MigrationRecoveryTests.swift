import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V9_03MigrationRecoveryTests: XCTestCase {
    private let fileManager = FileManager.default

    private struct LegacyFixture {
        let root: URL
        let sourceID: UUID
        let migrationID: UUID
        let targetID: UUID
        let v3TargetID: UUID
        let v4TargetID: UUID
        let v5TargetID: UUID
        let v6TargetID: UUID
        let siteID: UUID
        let assetID: UUID
        let recordID: UUID
        let processIDs: [UUID]
    }

    private struct LegacyCurrentPointer: Codable {
        let generationID: String
        let schemaVersion: Int
    }

    private struct RetiredPointer: Codable {
        let generationIDs: [String]
        let schemaVersion: Int
    }

    private struct FuturePointer: Codable {
        let schemaVersion: Int
    }

    private struct MalformedV2Pointer: Codable {
        let generationID: String
        let generationManifestSHA256: String
        let storeSchemaVersion: Int = 2
        let schemaVersion: Int = 2
    }

    private final class ProcessCursor {
        var index = 0
    }

    func testLegacyV1MigrationPreservesRowsAndCompletesTwoLaunchValidation() throws {
        let fixture = try makeLegacyFixture(suffix: "Clean")
        defer { try? fileManager.removeItem(at: fixture.root) }
        let processCursor = ProcessCursor()
        let factory = makeFactory(fixture: fixture, processCursor: processCursor)
        let sourceSemantic = try semanticData(
            at: installedModelURL(in: fixture.root, id: fixture.sourceID),
            root: fixture.root,
            release: .v1
        )

        XCTAssertEqual(try pointerSchema(in: fixture.root), 1)
        var firstLaunch: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
        let first = try XCTUnwrap(firstLaunch)
        XCTAssertEqual(first.generationID, fixture.targetID)
        try assertMigratedRows(in: first.modelContext, fixture: fixture)

        let store = try StoreMigrationJournalStoreV1(
            applicationSupportURL: fixture.root
        )
        let firstJournal = try XCTUnwrap(try store.loadJournal())
        XCTAssertEqual(firstJournal.phase, .firstLaunchValidated)
        XCTAssertEqual(firstJournal.firstValidationProcessID, fixture.processIDs[0])
        XCTAssertNil(firstJournal.secondValidationProcessID)
        XCTAssertEqual(try pointerSchema(in: fixture.root), 2)

        let sourceManifest = try store.loadManifest(
            targetGenerationID: fixture.sourceID,
            expectedDigest: firstJournal.sourceManifestDigest
        )
        XCTAssertEqual(sourceManifest.storeSchemaRelease, .v1)
        XCTAssertEqual(sourceManifest.generationID, fixture.sourceID)
        XCTAssertEqual(sourceManifest.migrationID, fixture.migrationID)
        XCTAssertNil(sourceManifest.semanticSHA256)
        XCTAssertEqual(
            firstJournal.sourceSemanticDigest,
            StoreMigrationCanonicalJSONV1.sha256(sourceSemantic)
        )
        XCTAssertEqual(
            try sourceManifest.canonicalSHA256(),
            firstJournal.sourceManifestDigest
        )

        let firstMarker = try XCTUnwrap(
            try first.modelContext.fetch(
                FetchDescriptor<PersistentSchemaReleaseMarker>()
            ).first
        )
        XCTAssertEqual(firstMarker.id, PersistentSchemaReleaseRegistryV1.v2MarkerID)
        XCTAssertEqual(firstMarker.schemaVersion, 2)
        XCTAssertEqual(
            firstMarker.releaseID,
            PersistentSchemaReleaseRegistryV1.v2CompatibilityID
        )
        XCTAssertEqual(
            firstMarker.predecessorReleaseID,
            PersistentSchemaReleaseRegistryV1.v1CompatibilityID
        )
        XCTAssertEqual(firstMarker.migrationID, fixture.migrationID)

        let pointer = try CurrentGenerationPointerV2.decodeCanonical(
            from: try Data(contentsOf: currentPointerURL(in: fixture.root))
        )
        let manifest = try store.loadManifest(
            targetGenerationID: fixture.targetID,
            expectedDigest: pointer.generationManifestSHA256
        )
        XCTAssertEqual(manifest.storeSchemaRelease, .v2)
        XCTAssertEqual(manifest.migrationID, fixture.migrationID)
        XCTAssertEqual(manifest.predecessorGenerationID, fixture.sourceID)
        XCTAssertTrue(manifest.files.contains { $0.relativePath == "model.sqlite" })
        XCTAssertEqual(
            try manifest.canonicalSHA256(),
            pointer.generationManifestSHA256
        )
        XCTAssertEqual(
            try XCTUnwrap(firstJournal.targetManifestDigest),
            pointer.generationManifestSHA256
        )
        XCTAssertEqual(
            try XCTUnwrap(firstJournal.targetSemanticDigest),
            try XCTUnwrap(manifest.semanticSHA256)
        )
        XCTAssertEqual(
            try pointer.canonicalSHA256(),
            try XCTUnwrap(firstJournal.desiredPointerDigest)
        )
        XCTAssertEqual(
            try XCTUnwrap(manifest.semanticSHA256),
            StoreMigrationCanonicalJSONV1.sha256(sourceSemantic)
        )
        let targetSemantic = try semanticData(
            at: first.generationRootURL.appendingPathComponent(
                "model.sqlite",
                isDirectory: false
            ),
            root: fixture.root,
            release: .v2
        )
        XCTAssertEqual(sourceSemantic, targetSemantic)

        firstLaunch = nil
        XCTAssertNotEqual(fixture.processIDs[0], fixture.processIDs[1])
        var secondLaunch: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
        let second = try XCTUnwrap(secondLaunch)
        XCTAssertEqual(second.generationID, fixture.v3TargetID)
        try assertMigratedRows(in: second.modelContext, fixture: fixture)
        XCTAssertEqual(
            try DeletionLedgerStore(context: second.modelContext).snapshot(),
            .empty
        )
        secondLaunch = nil

        let v3FirstLaunch = try XCTUnwrap(try store.loadJournal())
        XCTAssertEqual(v3FirstLaunch.sourceRelease, .v2)
        XCTAssertEqual(v3FirstLaunch.targetRelease, .v3)
        XCTAssertEqual(v3FirstLaunch.phase, .firstLaunchValidated)
        XCTAssertEqual(try pointerSchema(in: fixture.root), 3)

        var thirdLaunch: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
        let third = try XCTUnwrap(thirdLaunch)
        XCTAssertEqual(third.generationID, fixture.v4TargetID)
        try assertMigratedRows(in: third.modelContext, fixture: fixture)
        XCTAssertEqual(
            try DeletionLedgerStore(context: third.modelContext).snapshot(),
            .empty
        )
        XCTAssertEqual(try third.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 0)
        thirdLaunch = nil

        let v4FirstLaunch = try XCTUnwrap(try store.loadJournal())
        XCTAssertEqual(v4FirstLaunch.sourceRelease, .v3)
        XCTAssertEqual(v4FirstLaunch.targetRelease, .v4)
        XCTAssertEqual(v4FirstLaunch.phase, .firstLaunchValidated)
        XCTAssertEqual(try pointerSchema(in: fixture.root), 3)

        var fourthLaunch: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
        let fourth = try XCTUnwrap(fourthLaunch)
        XCTAssertEqual(fourth.generationID, fixture.v5TargetID)
        XCTAssertEqual(try fourth.modelContext.fetchCount(FetchDescriptor<MutationReceiptRow>()), 0)
        let migratedRecord = try XCTUnwrap(
            try fourth.modelContext.fetch(FetchDescriptor<WorkflowRecord>()).first
        )
        XCTAssertEqual(migratedRecord.id, fixture.recordID)
        let migratedCompanion = try ObservationAndTimeRowStoreV1.requireRow(
            recordID: migratedRecord.id,
            in: fourth.modelContext
        )
        XCTAssertEqual(try migratedCompanion.observationBasisV1().kind, .unverifiable)
        XCTAssertEqual(try migratedCompanion.observationBasisV1().method.key, ObservationMethodV1.unknownKey)
        XCTAssertEqual(try migratedCompanion.temporalContextV1().localTimeDisposition, .unknown)
        XCTAssertEqual(try migratedCompanion.temporalContextV1().utcOffsetSeconds, -18_000)
        fourthLaunch = nil

        let v5FirstLaunch = try XCTUnwrap(try store.loadJournal())
        XCTAssertEqual(v5FirstLaunch.sourceRelease, .v4)
        XCTAssertEqual(v5FirstLaunch.targetRelease, .v5)
        XCTAssertEqual(v5FirstLaunch.phase, .firstLaunchValidated)

        var fifthLaunch: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
        let fifth = try XCTUnwrap(fifthLaunch)
        XCTAssertEqual(fifth.generationID, fixture.v6TargetID)
        XCTAssertEqual(
            try fifth.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()),
            1
        )
        XCTAssertEqual(
            try fifth.modelContext.fetchCount(FetchDescriptor<ObservationAndTimeRow>()),
            1
        )
        XCTAssertEqual(
            try fifth.modelContext.fetchCount(FetchDescriptor<AssetPlacementEventRow>()),
            1
        )
        XCTAssertEqual(
            try fifth.modelContext.fetchCount(FetchDescriptor<LocationMigrationReceiptRow>()),
            1
        )
        fifthLaunch = nil

        let v6FirstLaunch = try XCTUnwrap(try store.loadJournal())
        XCTAssertEqual(v6FirstLaunch.sourceRelease, .v5)
        XCTAssertEqual(v6FirstLaunch.targetRelease, .v6)
        XCTAssertEqual(v6FirstLaunch.phase, .firstLaunchValidated)

        var sixthLaunch: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
        XCTAssertEqual(try XCTUnwrap(sixthLaunch).generationID, fixture.v6TargetID)
        sixthLaunch = nil
        XCTAssertNil(try store.loadJournal())
        XCTAssertEqual(try pointerSchema(in: fixture.root), 3)
    }

#if DEBUG
    func testEveryFaultBoundaryUsesPreWriteFallbackOrPostWriteForwardRecovery() throws {
        let boundaries = StoreMigrationFaultBoundaryV1.allCases
        XCTAssertEqual(boundaries.count, 18)

        let preWriteBoundaries: [StoreMigrationFaultBoundaryV1] = [
            .beforePreparedJournalWrite,
            .afterPreparedJournalWrite,
            .beforeSourceClone,
            .afterSourceClone,
            .beforeV2WriteAuthorization,
        ]
        let publishedBoundaries: [StoreMigrationFaultBoundaryV1] = [
            .afterPointerPublication,
            .beforeFirstLaunchValidation,
            .afterFirstLaunchValidation,
            .beforeSecondLaunchValidation,
            .afterSecondLaunchValidation,
            .beforeJournalRemoval,
            .afterJournalRemoval,
        ]
        let durableMarkerBoundaries: [StoreMigrationFaultBoundaryV1] = [
            .afterV2Validation,
            .beforeGenerationInstall,
            .afterGenerationInstall,
            .beforePointerPublication,
            .afterPointerPublication,
            .beforeFirstLaunchValidation,
            .afterFirstLaunchValidation,
            .beforeSecondLaunchValidation,
            .afterSecondLaunchValidation,
            .beforeJournalRemoval,
            .afterJournalRemoval,
        ]

        for (index, boundary) in boundaries.enumerated() {
            let fixture = try makeLegacyFixture(
                suffix: "Boundary-\(index)-\(boundary.rawValue)"
            )
            defer { try? fileManager.removeItem(at: fixture.root) }
            let processCursor = ProcessCursor()
            let injection = StoreMigrationFailureInjection(failOnceAt: boundary)
            let factory = makeFactory(
                fixture: fixture,
                processCursor: processCursor,
                injection: injection
            )

            var didReachInjectedBoundary = false
            for _ in 0..<4 {
                do {
                    var session: StoreGenerationSession? =
                        try factory.openOrBootstrapCurrent()
                    session = nil
                } catch let failure as StoreMigrationFailure {
                    guard case .injectedFault(let actualBoundary) = failure else {
                        XCTFail(
                            "\(boundary.rawValue) produced unexpected failure \(failure)"
                        )
                        break
                    }
                    XCTAssertEqual(actualBoundary, boundary)
                    didReachInjectedBoundary = true
                    break
                } catch {
                    XCTFail("\(boundary.rawValue) produced non-migration error \(error)")
                    break
                }
            }
            XCTAssertTrue(didReachInjectedBoundary, boundary.rawValue)

            let journal = try loadJournal(in: fixture.root)
            let pointerVersion = try pointerSchema(in: fixture.root)
            if preWriteBoundaries.contains(boundary) {
                XCTAssertEqual(pointerVersion, 1, boundary.rawValue)
                XCTAssertTrue(
                    journal == nil || journal?.targetWritePossible == false,
                    boundary.rawValue
                )
            } else if publishedBoundaries.contains(boundary) {
                XCTAssertEqual(pointerVersion, 2, boundary.rawValue)
                if let journal {
                    XCTAssertTrue(journal.targetWritePossible, boundary.rawValue)
                }
            } else {
                XCTAssertEqual(pointerVersion, 1, boundary.rawValue)
                XCTAssertTrue(journal?.targetWritePossible == true, boundary.rawValue)
            }

            if boundary == .afterSecondLaunchValidation {
                let secondLaunchJournal = try XCTUnwrap(journal)
                XCTAssertEqual(
                    secondLaunchJournal.phase,
                    .secondLaunchValidated,
                    boundary.rawValue
                )
                let firstProcess = try XCTUnwrap(
                    secondLaunchJournal.firstValidationProcessID
                )
                let secondProcess = try XCTUnwrap(
                    secondLaunchJournal.secondValidationProcessID
                )
                let publicationProcess = try XCTUnwrap(
                    secondLaunchJournal.publicationProcessID
                )
                XCTAssertNotEqual(firstProcess, secondProcess, boundary.rawValue)
                XCTAssertNotEqual(
                    secondProcess,
                    secondLaunchJournal.originatingProcessID,
                    boundary.rawValue
                )
                XCTAssertNotEqual(
                    secondProcess,
                    publicationProcess,
                    boundary.rawValue
                )
            }

            if durableMarkerBoundaries.contains(boundary) {
                let authority = try factory.makeRestoreGenerationAuthority()
                let presence = try authority.presence(id: fixture.targetID)
                XCTAssertTrue(
                    presence.staging || presence.installed,
                    boundary.rawValue
                )
                let root = presence.installed
                    ? factory.installedGenerationURL(id: fixture.targetID)
                    : factory.restoreStagingGenerationURL(id: fixture.targetID)
                try assertMarker(
                    at: root.appendingPathComponent("model.sqlite"),
                    migrationID: fixture.migrationID
                )
            }

            var reachedCleanState = false
            for _ in 0..<6 {
                var session: StoreGenerationSession? =
                    try factory.openOrBootstrapCurrent()
                let hasJournal = try loadJournal(in: fixture.root) != nil
                session = nil
                if !hasJournal {
                    reachedCleanState = true
                    break
                }
            }
            XCTAssertTrue(reachedCleanState, boundary.rawValue)

            var finalSession: StoreGenerationSession? =
                try factory.openOrBootstrapCurrent()
            let final = try XCTUnwrap(finalSession)
            XCTAssertEqual(final.generationID, fixture.v3TargetID, boundary.rawValue)
            try assertMigratedRows(in: final.modelContext, fixture: fixture)
            finalSession = nil
            try assertMarker(
                at: final.generationRootURL.appendingPathComponent("model.sqlite"),
                migrationID: fixture.migrationID,
                release: .v3
            )
            XCTAssertNil(try loadJournal(in: fixture.root), boundary.rawValue)
            XCTAssertEqual(try pointerSchema(in: fixture.root), 3, boundary.rawValue)
        }

        let markerRetry = try makeLegacyFixture(suffix: "V4MarkerRetry")
        defer { try? fileManager.removeItem(at: markerRetry.root) }
        let markerRetryCursor = ProcessCursor()
        let advanceFactory = makeFactory(
            fixture: markerRetry,
            processCursor: markerRetryCursor
        )
        var advanced: StoreGenerationSession? = try advanceFactory.openOrBootstrapCurrent()
        advanced = nil
        advanced = try advanceFactory.openOrBootstrapCurrent()
        XCTAssertEqual(try XCTUnwrap(advanced).generationID, markerRetry.v3TargetID)
        advanced = nil

        let retryFactory = makeFactory(
            fixture: markerRetry,
            processCursor: markerRetryCursor,
            injection: StoreMigrationFailureInjection(failOnceAt: .afterV2Validation)
        )
        XCTAssertThrowsError(try retryFactory.openOrBootstrapCurrent()) {
            XCTAssertEqual(
                $0 as? StoreMigrationFailure,
                .injectedFault(.afterV2Validation)
            )
        }
        let retryStaging = retryFactory.restoreStagingGenerationURL(
            id: markerRetry.v4TargetID
        )
        try assertMarker(
            at: retryStaging.appendingPathComponent("model.sqlite"),
            migrationID: markerRetry.migrationID,
            release: .v4
        )
        var recovered: StoreGenerationSession? = try retryFactory.openOrBootstrapCurrent()
        XCTAssertEqual(try XCTUnwrap(recovered).generationID, markerRetry.v4TargetID)
        XCTAssertEqual(
            try XCTUnwrap(recovered).modelContext.fetchCount(
                FetchDescriptor<MutationReceiptRow>()
            ),
            0
        )
        XCTAssertEqual(
            try XCTUnwrap(recovered).modelContext.fetchCount(
                FetchDescriptor<WorkspaceMutationStateRow>()
            ),
            1
        )
        recovered = nil
        let secondRecovery = try retryFactory.openOrBootstrapCurrent()
        XCTAssertEqual(secondRecovery.generationID, markerRetry.v4TargetID)
        XCTAssertEqual(
            try secondRecovery.modelContext.fetchCount(
                FetchDescriptor<WorkspaceMutationStateRow>()
            ),
            1
        )

        let exactMarkerSchema = Schema(
            PersistentSchemaV4.models,
            version: PersistentSchemaV4.versionIdentifier
        )
        let exactMarkerContainer = try ModelContainer(
            for: exactMarkerSchema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                "V9_03V4ExactMarkerRetry",
                schema: exactMarkerSchema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                cloudKitDatabase: .none
            )]
        )
        let exactMarkerContext = exactMarkerContainer.mainContext
        exactMarkerContext.autosaveEnabled = false
        exactMarkerContext.insert(PersistentSchemaReleaseMarker(
            id: PersistentSchemaReleaseRegistryV1.v2MarkerID,
            schemaVersion: 4,
            releaseID: PersistentSchemaReleaseRegistryV1.v4CompatibilityID,
            predecessorReleaseID: PersistentSchemaReleaseRegistryV1.v3CompatibilityID,
            migrationID: markerRetry.migrationID
        ))
        try exactMarkerContext.save()
        let exactIdentity = try WorkspaceReplicaIdentityV1(
            workspaceID: WorkspaceID(rawValue: fixedUUID("00000000-0000-0000-0000-000000000091")),
            replicaID: ReplicaID(rawValue: fixedUUID("00000000-0000-0000-0000-000000000092"))
        )
        _ = try MutationJournalStoreV1(
            modelContext: exactMarkerContext,
            identity: exactIdentity,
            generationID: fixedUUID("00000000-0000-0000-0000-000000000093")
        )
        var exactStates = try exactMarkerContext.fetch(
            FetchDescriptor<WorkspaceMutationStateRow>()
        )
        XCTAssertEqual(exactStates.count, 1)
        let incompleteState = try XCTUnwrap(exactStates.first)
        incompleteState.mutableSemanticSHA256 = nil
        try exactMarkerContext.save()
        _ = try MutationJournalStoreV1(
            modelContext: exactMarkerContext,
            identity: exactIdentity,
            generationID: fixedUUID("00000000-0000-0000-0000-000000000093")
        )
        exactStates = try exactMarkerContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
        XCTAssertEqual(exactStates.count, 1)
        XCTAssertNotNil(try XCTUnwrap(exactStates.first).mutableSemanticSHA256)
    }

    func testSourceCloneRecoveryReclonesButAuthorizedRecoveryIsForwardOnly() throws {
        let sourceCloneFixture = try makeLegacyFixture(suffix: "Reclone")
        defer { try? fileManager.removeItem(at: sourceCloneFixture.root) }
        let sourceCloneCursor = ProcessCursor()
        let sourceCloneFactory = makeFactory(
            fixture: sourceCloneFixture,
            processCursor: sourceCloneCursor,
            injection: StoreMigrationFailureInjection(
                failOnceAt: .afterSourceClone
            )
        )

        XCTAssertThrowsError(
            try sourceCloneFactory.openOrBootstrapCurrent()
        ) { error in
            XCTAssertEqual(
                error as? StoreMigrationFailure,
                .injectedFault(.afterSourceClone)
            )
        }
        let clonedModelURL = sourceCloneFactory
            .restoreStagingGenerationURL(id: sourceCloneFixture.targetID)
            .appendingPathComponent("model.sqlite", isDirectory: false)
        try Data(repeating: 0xA5, count: 32).write(
            to: clonedModelURL,
            options: .atomic
        )
        var firstRecovery: StoreGenerationSession? = try sourceCloneFactory
            .openOrBootstrapCurrent()
        firstRecovery = nil
        var secondRecovery: StoreGenerationSession? = try sourceCloneFactory
            .openOrBootstrapCurrent()
        XCTAssertEqual(secondRecovery?.generationID, sourceCloneFixture.v3TargetID)
        XCTAssertEqual(
            try DeletionLedgerStore(
                context: try XCTUnwrap(secondRecovery).modelContext
            ).snapshot(),
            .empty
        )
        secondRecovery = nil
        XCTAssertEqual(try pointerSchema(in: sourceCloneFixture.root), 3)
        let installedModelURL = sourceCloneFactory
            .installedGenerationURL(id: sourceCloneFixture.targetID)
            .appendingPathComponent("model.sqlite", isDirectory: false)
        XCTAssertTrue(fileManager.fileExists(atPath: installedModelURL.path))
        XCTAssertEqual(
            try loadJournal(in: sourceCloneFixture.root)?.targetRelease,
            .v3
        )
        var thirdRecovery: StoreGenerationSession? = try sourceCloneFactory
            .openOrBootstrapCurrent()
        thirdRecovery = nil
        XCTAssertNil(try loadJournal(in: sourceCloneFixture.root))

        let authorizedFixture = try makeLegacyFixture(suffix: "ForwardOnly")
        defer { try? fileManager.removeItem(at: authorizedFixture.root) }
        let authorizedCursor = ProcessCursor()
        let authorizedFactory = makeFactory(
            fixture: authorizedFixture,
            processCursor: authorizedCursor,
            injection: StoreMigrationFailureInjection(
                failOnceAt: .afterV2WriteAuthorization
            )
        )
        XCTAssertThrowsError(
            try authorizedFactory.openOrBootstrapCurrent()
        ) { error in
            XCTAssertEqual(
                error as? StoreMigrationFailure,
                .injectedFault(.afterV2WriteAuthorization)
            )
        }
        let authorizedAuthority = try authorizedFactory
            .makeRestoreGenerationAuthority()
        try authorizedAuthority.removeStagingGeneration(
            id: authorizedFixture.targetID
        )
        XCTAssertThrowsError(
            try authorizedFactory.openOrBootstrapCurrent()
        ) { error in
            XCTAssertEqual(
                error as? StoreMigrationFailure,
                .maintenanceRequired(.targetUnavailable)
            )
        }
        XCTAssertEqual(try pointerSchema(in: authorizedFixture.root), 1)
        let authorizedJournal = try XCTUnwrap(
            try loadJournal(in: authorizedFixture.root)
        )
        XCTAssertEqual(authorizedJournal.phase, .v2WriteAuthorized)
        XCTAssertTrue(authorizedJournal.targetWritePossible)
    }

    func testTargetSnapshotMutationAfterValidationFailsForwardClosed() throws {
        let fixture = try makeLegacyFixture(suffix: "TargetReproof")
        defer { try? fileManager.removeItem(at: fixture.root) }
        let processCursor = ProcessCursor()
        let factory = makeFactory(
            fixture: fixture,
            processCursor: processCursor,
            injection: StoreMigrationFailureInjection(
                failOnceAt: .afterV2Validation
            )
        )

        XCTAssertThrowsError(try factory.openOrBootstrapCurrent()) { error in
            XCTAssertEqual(
                error as? StoreMigrationFailure,
                .injectedFault(.afterV2Validation)
            )
        }
        let journal = try XCTUnwrap(try loadJournal(in: fixture.root))
        XCTAssertEqual(journal.phase, .v2Validated)
        let targetModelURL = factory
            .restoreStagingGenerationURL(id: fixture.targetID)
            .appendingPathComponent("model.sqlite", isDirectory: false)
        var mutated = try Data(contentsOf: targetModelURL)
        mutated.append(0)
        try mutated.write(to: targetModelURL, options: .atomic)

        XCTAssertThrowsError(try factory.openOrBootstrapCurrent()) { error in
            XCTAssertEqual(
                error as? StoreMigrationFailure,
                .maintenanceRequired(.targetMismatch)
            )
        }
        XCTAssertEqual(try pointerSchema(in: fixture.root), 1)
        let retained = try XCTUnwrap(try loadJournal(in: fixture.root))
        XCTAssertEqual(retained.phase, .v2Validated)
        XCTAssertTrue(retained.targetWritePossible)
    }

    func testPreparedSourceMutationFailsClosedAgainstSourceManifest() throws {
        let fixture = try makeLegacyFixture(suffix: "SourceReproof")
        defer { try? fileManager.removeItem(at: fixture.root) }
        let processCursor = ProcessCursor()
        let factory = makeFactory(
            fixture: fixture,
            processCursor: processCursor,
            injection: StoreMigrationFailureInjection(
                failOnceAt: .afterPreparedJournalWrite
            )
        )

        XCTAssertThrowsError(try factory.openOrBootstrapCurrent()) { error in
            XCTAssertEqual(
                error as? StoreMigrationFailure,
                .injectedFault(.afterPreparedJournalWrite)
            )
        }
        let sourceModelURL = installedModelURL(
            in: fixture.root,
            id: fixture.sourceID
        )
        try Data(repeating: 0x5A, count: 32).write(
            to: sourceModelURL,
            options: .atomic
        )

        XCTAssertThrowsError(try factory.openOrBootstrapCurrent()) { error in
            XCTAssertEqual(
                error as? StoreMigrationFailure,
                .maintenanceRequired(.sourceMismatch)
            )
        }
        XCTAssertEqual(try pointerSchema(in: fixture.root), 1)
        let retained = try XCTUnwrap(try loadJournal(in: fixture.root))
        XCTAssertEqual(retained.phase, .prepared)
        XCTAssertFalse(retained.targetWritePossible)
    }
#endif

    func testLegacyPointerIsAcceptedAndFutureOrMalformedBinaryIsRejected() throws {
        let legacy = try makeLegacyFixture(suffix: "LegacyPointer")
        defer { try? fileManager.removeItem(at: legacy.root) }
        let processCursor = ProcessCursor()
        let factory = makeFactory(fixture: legacy, processCursor: processCursor)
        XCTAssertEqual(try pointerSchema(in: legacy.root), 1)
        var session: StoreGenerationSession? = try factory.openOrBootstrapCurrent()
        XCTAssertEqual(session?.generationID, legacy.targetID)
        session = nil
        let validPointerData = try Data(
            contentsOf: currentPointerURL(in: legacy.root)
        )
        XCTAssertEqual(try pointerSchema(in: legacy.root), 2)
        let validPointer = try CurrentGenerationPointerV2.decodeCanonical(
            from: validPointerData
        )
        XCTAssertEqual(
            validPointer.generationID,
            legacy.targetID.uuidString.lowercased()
        )

        let cases: [(String, Data, StoreMigrationFailure)] = [
            (
                "future",
                try StoreMigrationCanonicalJSONV1.encode(
                    FuturePointer(schemaVersion: 4)
                ),
                .maintenanceRequired(.futureVersion)
            ),
            (
                "malformed-v2",
                try StoreMigrationCanonicalJSONV1.encode(
                    MalformedV2Pointer(
                        generationID: legacy.targetID.uuidString.lowercased(),
                        generationManifestSHA256: "not-a-digest"
                    )
                ),
                .invalidDigest
            ),
        ]

        for (name, data, expected) in cases {
            try data.write(
                to: currentPointerURL(in: legacy.root),
                options: .atomic
            )
            XCTAssertThrowsError(try factory.openOrBootstrapCurrent(), name) { error in
                XCTAssertEqual(error as? StoreMigrationFailure, expected, name)
            }
            let restoredPointer = try CurrentGenerationPointerV2.decodeCanonical(
                from: validPointerData
            )
            XCTAssertEqual(restoredPointer.schemaVersion, 2, name)
            try validPointerData.write(
                to: currentPointerURL(in: legacy.root),
                options: .atomic
            )
        }
    }

    @MainActor
    func testLegacyRestorePublishesFormat2AndReusesRollbackManifest() throws {
        let fixture = try makeLegacyFixture(suffix: "LegacyRestore")
        defer { try? fileManager.removeItem(at: fixture.root) }
        let factory = StoreGenerationFactory(applicationSupportURL: fixture.root)
        let authority = try factory.makeRestoreGenerationAuthority()
        let firstRestoreID = fixedUUID(
            "00000000-0000-0000-0000-000000000021"
        )
        let secondRestoreID = fixedUUID(
            "00000000-0000-0000-0000-000000000022"
        )
        try factory.createEmptyInstalledGeneration(
            id: firstRestoreID,
            authority: authority
        )
        try factory.switchCurrentGeneration(
            expected: fixture.sourceID,
            to: firstRestoreID,
            authority: authority
        )

        let store = try StoreMigrationJournalStoreV1(
            applicationSupportURL: fixture.root
        )
        let firstPointer = try CurrentGenerationPointerV2.decodeCanonical(
            from: Data(contentsOf: currentPointerURL(in: fixture.root))
        )
        XCTAssertEqual(firstPointer.schemaVersion, 2)
        XCTAssertEqual(firstPointer.storeSchemaVersion, 2)
        XCTAssertEqual(
            firstPointer.generationID,
            firstRestoreID.uuidString.lowercased()
        )
        let firstManifest = try store.loadManifest(
            targetGenerationID: firstRestoreID,
            expectedDigest: firstPointer.generationManifestSHA256
        )
        XCTAssertEqual(firstManifest.storeSchemaRelease, .v2)
        XCTAssertEqual(firstManifest.migrationID, firstRestoreID)

        try factory.createEmptyInstalledGeneration(
            id: secondRestoreID,
            authority: authority
        )
        try factory.switchCurrentGeneration(
            expected: firstRestoreID,
            to: secondRestoreID,
            authority: authority
        )
        let secondPointer = try CurrentGenerationPointerV2.decodeCanonical(
            from: Data(contentsOf: currentPointerURL(in: fixture.root))
        )
        XCTAssertEqual(
            secondPointer.generationID,
            secondRestoreID.uuidString.lowercased()
        )
        XCTAssertNotEqual(
            secondPointer.generationManifestSHA256,
            firstPointer.generationManifestSHA256
        )

        try factory.switchCurrentGeneration(
            expected: secondRestoreID,
            to: firstRestoreID,
            authority: authority
        )
        let restoredPointer = try CurrentGenerationPointerV2.decodeCanonical(
            from: Data(contentsOf: currentPointerURL(in: fixture.root))
        )
        XCTAssertEqual(
            restoredPointer.generationID,
            firstRestoreID.uuidString.lowercased()
        )
        XCTAssertEqual(
            restoredPointer.generationManifestSHA256,
            firstPointer.generationManifestSHA256
        )
        let reusedManifest = try store.loadManifest(
            targetGenerationID: firstRestoreID,
            expectedDigest: restoredPointer.generationManifestSHA256
        )
        XCTAssertEqual(reusedManifest, firstManifest)
        XCTAssertEqual(
            try factory.currentGenerationID(authority: authority),
            firstRestoreID
        )
    }

    private func makeLegacyFixture(suffix: String) throws -> LegacyFixture {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "V9_03MigrationRecoveryTests-\(suffix)",
            isDirectory: true
        )
        try? fileManager.removeItem(at: root)
        let dataRoot = root.appendingPathComponent("FieldEvidenceData", isDirectory: true)
        let generationsRoot = dataRoot.appendingPathComponent("generations", isDirectory: true)

        let sourceID = fixedUUID("00000000-0000-0000-0000-000000000010")
        let migrationID = fixedUUID("00000000-0000-0000-0000-000000000011")
        let targetID = fixedUUID("00000000-0000-0000-0000-000000000012")
        let v3TargetID = fixedUUID("00000000-0000-0000-0000-000000000015")
        let v4TargetID = fixedUUID("00000000-0000-0000-0000-000000000016")
        let v5TargetID = fixedUUID("00000000-0000-0000-0000-000000000017")
        let v6TargetID = fixedUUID("00000000-0000-0000-0000-00000000001a")
        let siteID = fixedUUID("00000000-0000-0000-0000-000000000013")
        let assetID = fixedUUID("00000000-0000-0000-0000-000000000014")
        let recordID = fixedUUID("00000000-0000-0000-0000-000000000018")
        let processIDs = (0..<10).map {
            fixedUUID(String(format: "00000000-0000-0000-0000-00000000002%1d", $0))
        }
        let sourceRoot = generationsRoot.appendingPathComponent(
            sourceID.uuidString.lowercased(),
            isDirectory: true
        )
        let modelURL = sourceRoot.appendingPathComponent("model.sqlite", isDirectory: false)

        try fileManager.createDirectory(
            at: sourceRoot,
            withIntermediateDirectories: true
        )
        let createdAt = Date(timeIntervalSince1970: 1_700_000_100)
        do {
            let schema = PersistentSchemaV1.makeSchema()
            let configuration = ModelConfiguration(
                "V9_03LegacyV1",
                schema: schema,
                url: modelURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: schema,
                migrationPlan: nil,
                configurations: [configuration]
            )
            let context = container.mainContext
            context.insert(
                Site(
                    id: siteID,
                    label: "Synthetic Legacy Site",
                    address: "1 Synthetic Way",
                    timeZoneID: "America/New_York",
                    createdAt: createdAt,
                    updatedAt: createdAt
                )
            )
            context.insert(
                Asset(
                    id: assetID,
                    siteID: siteID,
                    packID: "field.evidence.illuminated_sign.v1",
                    packSchemaVersion: 1,
                    packContentVersion: 1,
                    label: "Synthetic Legacy Asset",
                    createdAt: createdAt,
                    updatedAt: createdAt
                )
            )
            context.insert(WorkflowRecord(
                id: recordID,
                assetID: assetID,
                packetID: nil,
                issueID: nil,
                parentRecordID: nil,
                recordRevisionRootID: recordID,
                revisesRecordID: nil,
                evidenceSourceRecordID: nil,
                revisionKind: .original,
                stage: .recheck,
                state: .completed,
                draftStepKey: nil,
                startedAt: createdAt,
                completedAt: createdAt.addingTimeInterval(5),
                observedAtUTC: createdAt,
                timeZoneID: "America/New_York",
                utcOffsetMinutes: -300,
                localDate: "2023-11-14",
                localTime: "17:15:00",
                afterDarkAcknowledgementKey: nil,
                afterDarkAcknowledgementCopy: nil,
                afterDarkAcknowledgementVersion: nil,
                afterDarkAcknowledgementAccepted: nil,
                safePositionAcknowledgementKey: nil,
                safePositionAcknowledgementCopy: nil,
                safePositionAcknowledgementVersion: nil,
                safePositionAcknowledgementAccepted: nil,
                packID: "field.evidence.illuminated_sign.v1",
                packSchemaVersion: 1,
                packContentVersion: 1,
                pdfTemplateID: "field.evidence.pdf.worklight.v1",
                pdfTemplateVersion: 1,
                outcomeKey: "could_not_verify",
                couldNotVerifyKey: "required_view_obstructed",
                couldNotVerifyDisplaySnapshot: "Required view is blocked",
                couldNotVerifyRegistryVersion: "cnv.reason.en-US.v1",
                workPerformedLocalDate: nil,
                workDescription: nil,
                note: nil,
                finalizationMutationID: fixedUUID(
                    "00000000-0000-0000-0000-000000000019"
                )
            ))
            try context.save()
        }

        let current = LegacyCurrentPointer(
            generationID: sourceID.uuidString.lowercased(),
            schemaVersion: 1
        )
        let retired = RetiredPointer(generationIDs: [], schemaVersion: 1)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try StoreMigrationCanonicalJSONV1.encode(current).write(
            to: dataRoot.appendingPathComponent("current.json"),
            options: .atomic
        )
        try StoreMigrationCanonicalJSONV1.encode(retired).write(
            to: dataRoot.appendingPathComponent("retired.json"),
            options: .atomic
        )

        return LegacyFixture(
            root: root,
            sourceID: sourceID,
            migrationID: migrationID,
            targetID: targetID,
            v3TargetID: v3TargetID,
            v4TargetID: v4TargetID,
            v5TargetID: v5TargetID,
            v6TargetID: v6TargetID,
            siteID: siteID,
            assetID: assetID,
            recordID: recordID,
            processIDs: processIDs
        )
    }

    private func makeFactory(
        fixture: LegacyFixture,
        processCursor: ProcessCursor
    ) -> StoreGenerationFactory {
        return StoreGenerationFactory(
            applicationSupportURL: fixture.root,
            migrationIdentitySource: makeIdentitySource(
                fixture: fixture,
                processCursor: processCursor
            )
        )
    }

    private func makeIdentitySource(
        fixture: LegacyFixture,
        processCursor: ProcessCursor
    ) -> StoreMigrationIdentitySourceV1 {
        StoreMigrationIdentitySourceV1(
            makeMigrationID: { fixture.migrationID },
            makeGenerationID: {
                let pointerURL = fixture.root
                    .appendingPathComponent("FieldEvidenceData", isDirectory: true)
                    .appendingPathComponent("current.json", isDirectory: false)
                let schemaVersion: Int?
                if let data = try? Data(contentsOf: pointerURL),
                   let object = try? JSONSerialization.jsonObject(with: data),
                   let fields = object as? [String: Any] {
                    schemaVersion = fields["schemaVersion"] as? Int
                } else {
                    schemaVersion = nil
                }
                if schemaVersion == 1 { return fixture.targetID }
                if let data = try? Data(contentsOf: pointerURL),
                   let pointer = try? CurrentGenerationPointerV3.decodeCanonical(from: data),
                   pointer.storeSchemaVersion >= 3 {
                    if pointer.storeSchemaVersion == 3 { return fixture.v4TargetID }
                    if pointer.storeSchemaVersion == 4 { return fixture.v5TargetID }
                    if pointer.storeSchemaVersion == 5 { return fixture.v6TargetID }
                }
                return fixture.v3TargetID
            },
            makeProcessID: {
                defer { processCursor.index += 1 }
                return fixture.processIDs[
                    min(processCursor.index, fixture.processIDs.count - 1)
                ]
            }
        )
    }

#if DEBUG
    private func makeFactory(
        fixture: LegacyFixture,
        processCursor: ProcessCursor,
        injection: StoreMigrationFailureInjection
    ) -> StoreGenerationFactory {
        StoreGenerationFactory(
            applicationSupportURL: fixture.root,
            migrationIdentitySource: makeIdentitySource(
                fixture: fixture,
                processCursor: processCursor
            ),
            migrationFailureInjection: injection
        )
    }
#endif

    private func assertMigratedRows(
        in context: ModelContext,
        fixture: LegacyFixture
    ) throws {
        let sites = try context.fetch(FetchDescriptor<Site>())
        let assets = try context.fetch(FetchDescriptor<Asset>())
        let records = try context.fetch(FetchDescriptor<WorkflowRecord>())
        XCTAssertEqual(sites.count, 1)
        XCTAssertEqual(assets.count, 1)
        XCTAssertEqual(records.count, 1)
        let site = try XCTUnwrap(sites.first)
        let asset = try XCTUnwrap(assets.first)
        XCTAssertEqual(site.id, fixture.siteID)
        XCTAssertEqual(site.label, "Synthetic Legacy Site")
        XCTAssertEqual(asset.id, fixture.assetID)
        XCTAssertEqual(asset.siteID, fixture.siteID)
        XCTAssertEqual(asset.label, "Synthetic Legacy Asset")
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.id, fixture.recordID)
    }

    private func assertMarker(
        at modelURL: URL,
        migrationID: UUID,
        release: PersistentSchemaReleaseV1 = .v2
    ) throws {
        let schema: Schema
        switch release {
        case .v1:
            throw StoreMigrationFailure.invalidContract
        case .v2:
            schema = Schema(
                PersistentSchemaV2.models,
                version: PersistentSchemaV2.versionIdentifier
            )
        case .v3:
            schema = Schema(
                PersistentSchemaV3.models,
                version: PersistentSchemaV3.versionIdentifier
            )
        case .v4:
            schema = Schema(
                PersistentSchemaV4.models,
                version: PersistentSchemaV4.versionIdentifier
            )
        case .v5:
            schema = Schema(
                PersistentSchemaV5.models,
                version: PersistentSchemaV5.versionIdentifier
            )
        case .v6:
            schema = try PersistentSchemaReleaseRegistryV1.activeSchema()
        }
        let configuration = ModelConfiguration(
            "V9_03MarkerInspection",
            schema: schema,
            url: modelURL,
            allowsSave: false,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [configuration]
        )
        let markers = try container.mainContext.fetch(
            FetchDescriptor<PersistentSchemaReleaseMarker>()
        )
        let marker = try XCTUnwrap(markers.first)
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(marker.id, PersistentSchemaReleaseRegistryV1.v2MarkerID)
        let expectedSchemaVersion: Int
        let expectedReleaseID: String
        let expectedPredecessorID: String
        switch release {
        case .v1:
            throw StoreMigrationFailure.invalidContract
        case .v2:
            expectedSchemaVersion = 2
            expectedReleaseID = PersistentSchemaReleaseRegistryV1.v2CompatibilityID
            expectedPredecessorID = PersistentSchemaReleaseRegistryV1.v1CompatibilityID
        case .v3:
            expectedSchemaVersion = 3
            expectedReleaseID = PersistentSchemaReleaseRegistryV1.v3CompatibilityID
            expectedPredecessorID = PersistentSchemaReleaseRegistryV1.v2CompatibilityID
        case .v4:
            expectedSchemaVersion = 4
            expectedReleaseID = PersistentSchemaReleaseRegistryV1.v4CompatibilityID
            expectedPredecessorID = PersistentSchemaReleaseRegistryV1.v3CompatibilityID
        case .v5:
            expectedSchemaVersion = 5
            expectedReleaseID = PersistentSchemaReleaseRegistryV1.v5CompatibilityID
            expectedPredecessorID = PersistentSchemaReleaseRegistryV1.v4CompatibilityID
        case .v6:
            expectedSchemaVersion = 6
            expectedReleaseID = PersistentSchemaReleaseRegistryV1.v6CompatibilityID
            expectedPredecessorID = PersistentSchemaReleaseRegistryV1.v5CompatibilityID
        }
        XCTAssertEqual(marker.schemaVersion, expectedSchemaVersion)
        XCTAssertEqual(
            marker.releaseID,
            expectedReleaseID
        )
        XCTAssertEqual(
            marker.predecessorReleaseID,
            expectedPredecessorID
        )
        XCTAssertEqual(marker.migrationID, migrationID)
    }

    private func semanticData(
        at modelURL: URL,
        root: URL,
        release: PersistentSchemaReleaseV1
    ) throws -> Data {
        let schema: Schema
        switch release {
        case .v1:
            schema = PersistentSchemaV1.makeSchema()
        case .v2:
            schema = Schema(
                PersistentSchemaV2.models,
                version: PersistentSchemaV2.versionIdentifier
            )
        case .v3:
            schema = Schema(
                PersistentSchemaV3.models,
                version: PersistentSchemaV3.versionIdentifier
            )
        case .v4:
            schema = Schema(
                PersistentSchemaV4.models,
                version: PersistentSchemaV4.versionIdentifier
            )
        case .v5:
            schema = Schema(
                PersistentSchemaV5.models,
                version: PersistentSchemaV5.versionIdentifier
            )
        case .v6:
            schema = try PersistentSchemaReleaseRegistryV1.activeSchema()
        }
        let configuration = ModelConfiguration(
            "V9_03Semantic-\(release.rawValue)",
            schema: schema,
            url: modelURL,
            allowsSave: false,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [configuration]
        )
        let service = try BackupRestoreService(applicationSupportURL: root)
        return try BackupCanonicalEncoderV1()
            .encodeRecords(
                service.migrationCanonicalRecords(in: container.mainContext)
            )
            .data
    }

    private func loadJournal(in root: URL) throws -> StoreMigrationJournalV1? {
        let store = try StoreMigrationJournalStoreV1(applicationSupportURL: root)
        return try store.loadJournal()
    }

    private func pointerSchema(in root: URL) throws -> Int {
        let data = try Data(contentsOf: currentPointerURL(in: root))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return try XCTUnwrap(object["schemaVersion"] as? Int)
    }

    private func currentPointerURL(in root: URL) -> URL {
        root
            .appendingPathComponent("FieldEvidenceData", isDirectory: true)
            .appendingPathComponent("current.json", isDirectory: false)
    }

    private func installedModelURL(in root: URL, id: UUID) -> URL {
        root
            .appendingPathComponent("FieldEvidenceData", isDirectory: true)
            .appendingPathComponent("generations", isDirectory: true)
            .appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("model.sqlite", isDirectory: false)
    }

    private func fixedUUID(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}

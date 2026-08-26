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
        let siteID: UUID
        let assetID: UUID
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
        XCTAssertEqual(second.generationID, fixture.targetID)
        try assertMigratedRows(in: second.modelContext, fixture: fixture)
        secondLaunch = nil

        XCTAssertNil(try store.loadJournal())
        XCTAssertEqual(try pointerSchema(in: fixture.root), 2)
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
            XCTAssertEqual(final.generationID, fixture.targetID, boundary.rawValue)
            try assertMigratedRows(in: final.modelContext, fixture: fixture)
            finalSession = nil
            try assertMarker(
                at: final.generationRootURL.appendingPathComponent("model.sqlite"),
                migrationID: fixture.migrationID
            )
            XCTAssertNil(try loadJournal(in: fixture.root), boundary.rawValue)
            XCTAssertEqual(try pointerSchema(in: fixture.root), 2, boundary.rawValue)
        }
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
        secondRecovery = nil
        XCTAssertEqual(try pointerSchema(in: sourceCloneFixture.root), 2)
        let installedModelURL = sourceCloneFactory
            .installedGenerationURL(id: sourceCloneFixture.targetID)
            .appendingPathComponent("model.sqlite", isDirectory: false)
        XCTAssertTrue(fileManager.fileExists(atPath: installedModelURL.path))
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
                    FuturePointer(schemaVersion: 3)
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
        let siteID = fixedUUID("00000000-0000-0000-0000-000000000013")
        let assetID = fixedUUID("00000000-0000-0000-0000-000000000014")
        let processIDs = (0..<8).map {
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
            siteID: siteID,
            assetID: assetID,
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
            makeGenerationID: { fixture.targetID },
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
        XCTAssertEqual(sites.count, 1)
        XCTAssertEqual(assets.count, 1)
        let site = try XCTUnwrap(sites.first)
        let asset = try XCTUnwrap(assets.first)
        XCTAssertEqual(site.id, fixture.siteID)
        XCTAssertEqual(site.label, "Synthetic Legacy Site")
        XCTAssertEqual(asset.id, fixture.assetID)
        XCTAssertEqual(asset.siteID, fixture.siteID)
        XCTAssertEqual(asset.label, "Synthetic Legacy Asset")
    }

    private func assertMarker(at modelURL: URL, migrationID: UUID) throws {
        let schema = try PersistentSchemaReleaseRegistryV1.activeSchema()
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
        XCTAssertEqual(marker.schemaVersion, 2)
        XCTAssertEqual(
            marker.releaseID,
            PersistentSchemaReleaseRegistryV1.v2CompatibilityID
        )
        XCTAssertEqual(
            marker.predecessorReleaseID,
            PersistentSchemaReleaseRegistryV1.v1CompatibilityID
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

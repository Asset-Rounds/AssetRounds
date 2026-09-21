import CoreGraphics
import Darwin
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import FieldEvidenceApp

final class S6_5ReplacementUnionTests: XCTestCase {
    private let fileManager = FileManager.default
    private let replacementAt = Date(timeIntervalSince1970: 1_786_710_000)

    func testPureRuleCreatesOnlyCurrentOnlyTombstonesAndRejectsCollisions() throws {
        let currentA = packet(
            id: uuid(10), root: uuid(11), currentRecord: uuid(12), created: 100
        )
        let currentB = packet(
            id: uuid(20), root: uuid(21), currentRecord: uuid(22), created: 200
        )
        let incomingB = packet(
            id: uuid(20), root: uuid(21), currentRecord: uuid(23), created: 200
        )
        let incomingC = packet(
            id: uuid(30), root: uuid(31), currentRecord: uuid(32), created: 300
        )

        let plan = try ReplacementRestoreRule.makePlan(
            .init(
                currentPackets: [currentA, currentB],
                incomingPackets: [incomingB, incomingC],
                replacementAt: replacementAt
            )
        )
        XCTAssertEqual(plan.currentOnlyTombstones, [
            packet(
                id: uuid(10), root: uuid(11), currentRecord: nil,
                created: 100, deleted: replacementAt.timeIntervalSince1970
            ),
        ])
        XCTAssertEqual(
            plan.packetsAfter.first(where: { $0.id == incomingB.id }),
            incomingB
        )
        XCTAssertEqual(
            Set(plan.consumedEvaluationRootIDs),
            Set([uuid(11), uuid(21), uuid(31)])
        )

        let wrongRoot = packet(
            id: currentA.id,
            root: uuid(99),
            currentRecord: uuid(98),
            created: 100
        )
        XCTAssertThrowsError(try ReplacementRestoreRule.makePlan(
            .init(
                currentPackets: [currentA],
                incomingPackets: [wrongRoot],
                replacementAt: replacementAt
            )
        ))

        let wrongID = packet(
            id: uuid(97),
            root: currentA.stableRootID,
            currentRecord: uuid(96),
            created: 100
        )
        XCTAssertThrowsError(try ReplacementRestoreRule.makePlan(
            .init(
                currentPackets: [currentA],
                incomingPackets: [wrongID],
                replacementAt: replacementAt
            )
        ))
        XCTAssertThrowsError(try ReplacementRestoreRule.makePlan(
            .init(
                currentPackets: [currentB, currentA],
                incomingPackets: [incomingC],
                replacementAt: replacementAt
            )
        ))
    }

#if DEBUG
    @MainActor
    private func assertObservationSchemaContract(
        service: BackupRestoreService,
        value: V4BackupWorkflowRecordDTO
    ) throws {
        let basis = try XCTUnwrap(value.observationBasisV1Data)
        let temporal = try XCTUnwrap(value.temporalContextV1Data)
        let upperBound = LightingNightWorkflowBackupEnrollmentV1.recordsSchemaVersion
        for version in 4...upperBound {
            let restored = try service.c36ObservationAndTimeDataForTesting(
                for: value, recordsSchemaVersion: version)
            XCTAssertEqual(restored.basis, basis, "schema \(version)")
            XCTAssertEqual(restored.temporal, temporal, "schema \(version)")
        }

        let legacy = value.replacingObservationAndTime(basisData: nil, temporalData: nil)
        for version in 1...3 {
            XCTAssertThrowsError(try service.c36ObservationAndTimeDataForTesting(
                for: value, recordsSchemaVersion: version))
            let migrated = try service.c36ObservationAndTimeDataForTesting(
                for: legacy, recordsSchemaVersion: version)
            let migratedBasis = try XCTUnwrap(migrated.basis)
            let migratedTemporal = try XCTUnwrap(migrated.temporal)
            XCTAssertEqual(try ObservationAndTimeCodecV1.encode(
                ObservationAndTimeCodecV1.decodeObservationBasis(migratedBasis)), migratedBasis)
            XCTAssertEqual(try ObservationAndTimeCodecV1.encode(
                ObservationAndTimeCodecV1.decodeTemporalContext(migratedTemporal)), migratedTemporal)
        }
        for version in [0, upperBound + 1] {
            for record in [value, legacy] {
                XCTAssertThrowsError(try service.c36ObservationAndTimeDataForTesting(
                    for: record, recordsSchemaVersion: version))
            }
        }
        let invalidRecords: [V4BackupWorkflowRecordDTO] = [
            value.replacingObservationAndTime(basisData: nil, temporalData: temporal),
            value.replacingObservationAndTime(basisData: basis, temporalData: nil),
            value.replacingObservationAndTime(basisData: Data([0xff]), temporalData: temporal),
            value.replacingObservationAndTime(basisData: basis, temporalData: Data([0xff])),
            value.replacingObservationAndTime(basisData: basis + Data([0x20]), temporalData: temporal),
            value.replacingObservationAndTime(basisData: basis, temporalData: temporal + Data([0x20])),
        ]
        for version in [4, 9, upperBound] {
            for record in invalidRecords {
                XCTAssertThrowsError(try service.c36ObservationAndTimeDataForTesting(
                    for: record, recordsSchemaVersion: version))
            }
        }
    }
#endif

    @MainActor
    func testGoldenReplacementKeepsIncomingLiveAndUnionsCurrentRoot() async throws {
        var diagnosticPhase = "fixture.begin"
        var firstRecoveryOrigin: String?
        var rowHistoryDiagnostics: [String] = []
        diagnosticPhase = "fixture.root"
        let root = try makeRoot("golden")
        // Keep cleanup outside the caught scope so original-error evidence is
        // captured before this defer can encounter an unrelated cleanup error.
        defer { try? fileManager.removeItem(at: root) }
        do {
            let current = try await makeLiveHarness(
                root: root,
                name: "current",
                base: 1,
                label: "Current sign",
                observedAt: Date(timeIntervalSince1970: 1_786_708_000),
                diagnostic: { diagnosticPhase = "current." + $0 }
            )
            let incoming = try await makeLiveHarness(
                root: root,
                name: "incoming",
                base: 101,
                label: "Restored sign",
                observedAt: Date(timeIntervalSince1970: 1_786_709_000),
                diagnostic: { diagnosticPhase = "incoming." + $0 }
            )
            diagnosticPhase = "incoming.freeze-report"
            let incomingReport = try freezeReportPreservation(in: incoming)
            diagnosticPhase = "current.history"
            let currentHistory = try MutationJournalStoreV1(
                modelContext: current.session.modelContext, identity: current.session.workspaceIdentity,
                generationID: current.session.generationID, allowStateBootstrap: false
            ).exportSnapshot()
            let package = try exportPackage(incoming, root: root, name: "incoming",
                diagnostic: { diagnosticPhase = "package.export." + $0 })
            diagnosticPhase = "package.before"
            let sourceBefore = try fileTree(package)
            diagnosticPhase = "package.import"
            let validated = try importPackage(package, into: current.session, stageID: uuid(190))
            let oldID = current.session.generationID

            diagnosticPhase = "restore.service.init"
            let service = try BackupRestoreService(
                applicationSupportURL: current.support,
                now: { self.replacementAt },
                makeUUID: sequence([uuid(191), uuid(192)])
            )
#if DEBUG
            diagnosticPhase = "restore.owned-create-contract"
            try assertOwnedRegularCreationContract(service: service, root: root)
            diagnosticPhase = "restore.observation-schema-contract"
            let incomingRecords = try service.c55CurrentRecordsForTesting(
                in: incoming.session.modelContext)
            try assertCoreRestoreProjectionPlanning(
                service: service, records: incomingRecords,
                sourceWorkspaceID: incoming.session.workspaceIdentity.workspaceID,
                destinationWorkspaceID: current.session.workspaceIdentity.workspaceID
            )
            try assertObservationSchemaContract(service: service,
                value: XCTUnwrap(incomingRecords.workflowRecords.first))
            service.restorePhaseDiagnosticForTesting = { value in
                if value == "restore-error.recovery.begin", firstRecoveryOrigin == nil {
                    firstRecoveryOrigin = diagnosticPhase
                }
                if firstRecoveryOrigin == nil,
                   value.hasPrefix("rows.history.") || value.hasPrefix("rows.schema."),
                   rowHistoryDiagnostics.count < 32,
                   !rowHistoryDiagnostics.contains(value) {
                    rowHistoryDiagnostics.append(value)
                }
                diagnosticPhase = "restore." + value
            }
#endif
            diagnosticPhase = "restore.execute"
            let restored = try await service.restore(
                validatedPackage: validated,
                currentModelContext: current.session.modelContext,
                currentGenerationID: oldID,
                currentGenerationRootURL: current.session.generationRootURL,
                mode: .replaceExisting
            )

            diagnosticPhase = "postrestore.assertions"
            XCTAssertEqual(try current.factory.currentGenerationID(), restored.generationID)
            XCTAssertEqual(try current.factory.retiredGenerationIDs(), [oldID])
            XCTAssertEqual(
                try restored.modelContext.fetch(FetchDescriptor<Asset>()).map(\.label),
                ["Restored sign"]
            )
            XCTAssertEqual(try restored.modelContext.fetchCount(FetchDescriptor<Report>()), 1)
            let packets = try restored.modelContext.fetch(FetchDescriptor<Packet>())
            XCTAssertEqual(
                Set(packets.map(\.stableRootID)),
                Set([current.rootID, incoming.rootID])
            )
            let currentTombstone = try XCTUnwrap(
                packets.first(where: { $0.stableRootID == current.rootID })
            )
            XCTAssertEqual(currentTombstone.id, current.packetID)
            XCTAssertNil(currentTombstone.currentRecordID)
            XCTAssertEqual(currentTombstone.contentDeletedAt, replacementAt)
            XCTAssertEqual(currentTombstone.createdAt, current.packetCreatedAt)
            let restoredHistory = try MutationJournalStoreV1(
                modelContext: restored.modelContext, identity: restored.workspaceIdentity,
                generationID: restored.generationID, allowStateBootstrap: false
            ).exportSnapshot()
            let packetIdentity = try WorkspaceEntityIdentityV1(kind: .packet, id: current.packetID)
            let priorTerminal = try XCTUnwrap(currentHistory.entityRevisions.first { $0.identity == packetIdentity })
            let terminal = try XCTUnwrap(restoredHistory.entityRevisions.first { $0.identity == packetIdentity })
            XCTAssertEqual(terminal.revision, priorTerminal.revision)
            struct PacketBasis: Codable {
                let identity: WorkspaceEntityIdentityV1
                let revision: UInt64
                let value: V4BackupPacketDTO
            }
            // A retained packet tombstone hashes its DTO, never an absent row.
            let expectedPacket = V4BackupPacketDTO(
                id: current.packetID, schemaVersion: currentTombstone.schemaVersion,
                stableRootID: current.rootID, currentRecordID: nil, evaluationCounted: true,
                contentDeletedAt: replacementAt, createdAt: current.packetCreatedAt
            )
            XCTAssertEqual(terminal.externalProjectionSHA256,
                try WorkspaceMutationCanonicalV1.sha256(PacketBasis(identity: packetIdentity,
                    revision: priorTerminal.revision, value: expectedPacket)))
            for original in currentHistory.receipts {
                XCTAssertTrue(restoredHistory.receipts.contains(original))
            }
            let incomingLive = try XCTUnwrap(
                packets.first(where: { $0.stableRootID == incoming.rootID })
            )
            XCTAssertEqual(incomingLive.id, incoming.packetID)
            XCTAssertNotNil(incomingLive.currentRecordID)
            XCTAssertNil(incomingLive.contentDeletedAt)
            XCTAssertEqual(
                try BackupRestoreService.currentSummary(
                    modelContext: restored.modelContext,
                    generationRootURL: restored.generationRootURL
                ).consumedRootCount,
                2
            )
            XCTAssertFalse(fileManager.fileExists(atPath: validated.stagedPackageURL.path))
            XCTAssertFalse(fileManager.fileExists(
                atPath: current.support.appendingPathComponent(
                    "FieldEvidenceRestore/restore.json"
                ).path
            ))
            XCTAssertEqual(try fileTree(package), sourceBefore)
            XCTAssertTrue(fileManager.fileExists(
                atPath: current.factory.installedGenerationURL(id: oldID).path
            ))

            diagnosticPhase = "restore.reopen"
            let reopened = try current.factory.openOrBootstrapCurrent()
            XCTAssertEqual(reopened.generationID, restored.generationID)
            XCTAssertEqual(try MutationJournalStoreV1(
                modelContext: reopened.modelContext, identity: reopened.workspaceIdentity,
                generationID: reopened.generationID, allowStateBootstrap: false
            ).exportSnapshot(), restoredHistory)
            XCTAssertEqual(
                Set(try reopened.modelContext.fetch(FetchDescriptor<Packet>()).map(\.stableRootID)),
                Set([current.rootID, incoming.rootID])
            )
            diagnosticPhase = "restore.reopened-report-readback"
            try assertPreservedReportAfterReopen(incomingReport, in: reopened)
        } catch {
            let originalError = error
            let failureType = String(reflecting: type(of: originalError))
            let failureDomain = (originalError as NSError).domain
            let failureCode = (originalError as NSError).code
            let failureRecord = "ReplacementUnionGolden.caught phase=\(diagnosticPhase) type=\(failureType) domain=\(failureDomain) code=\(failureCode)"
            XCTContext.runActivity(named: "Retained original failure before cleanup") { activity in
                let attachment = XCTAttachment(string: failureRecord)
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
            XCTFail(failureRecord)
            print(failureRecord)
            if let firstRecoveryOrigin {
                print("ReplacementUnionGolden.firstRecoveryOrigin=\(firstRecoveryOrigin)")
            }
            for value in rowHistoryDiagnostics {
                print("ReplacementUnionGolden.historyDifference=\(value)")
            }
            if let policyError = error as? ProtectedFilePolicyError,
               case .resourceValueMismatch = policyError {
                print("ReplacementUnionGolden.failure.protectedFileResourceValueMismatch")
            }
            throw originalError
        }
    }

    @MainActor
    func testFinalizedReportBytesAndReceiptsSurviveRepeatedForkAndColdReadback() async throws {
        let root = try makeRoot("report-fork")
        defer { try? fileManager.removeItem(at: root) }
        let current = try await makeLiveHarness(
            root: root, name: "current", base: 20_001, label: "Current sign",
            observedAt: Date(timeIntervalSince1970: 1_786_708_000))
        let incoming = try await makeLiveHarness(
            root: root, name: "incoming", base: 21_001, label: "Finalized source sign",
            observedAt: Date(timeIntervalSince1970: 1_786_709_000))
        let frozen = try freezeReportPreservation(in: incoming)
        let package = try exportPackage(incoming, root: root, name: "original-report")
        let packageBefore = try fileTree(package)
        let validated = try importPackage(package, into: current.session, stageID: uuid(22_001))
        let first = try await BackupRestoreService(applicationSupportURL: current.support).restore(
            validatedPackage: validated,
            currentModelContext: current.session.modelContext,
            currentGenerationID: current.session.generationID,
            currentGenerationRootURL: current.session.generationRootURL,
            mode: .fork)
        XCTAssertNotEqual(first.workspaceID, current.session.workspaceID)
        XCTAssertNotEqual(first.workspaceID, incoming.session.workspaceID)
        XCTAssertNotEqual(first.workspaceIdentity.replicaID, current.session.workspaceIdentity.replicaID)
        XCTAssertNotEqual(first.workspaceIdentity.replicaID, incoming.session.workspaceIdentity.replicaID)
        XCTAssertNotEqual(first.generationID, current.session.generationID)
        XCTAssertEqual(try fileTree(package), packageBefore)
        XCTAssertFalse(fileManager.fileExists(atPath: validated.stagedPackageURL.path))

        // Open a fresh factory and use the production lifecycle-bound report
        // readers. A retained source model or PDF alone is not readback proof.
        let firstFactory = StoreGenerationFactory(applicationSupportURL: current.support)
        let firstReopened = try firstFactory.openOrBootstrapCurrent()
        XCTAssertEqual(firstReopened.generationID, first.generationID)
        XCTAssertEqual(firstReopened.workspaceIdentity, first.workspaceIdentity)
        try assertPreservedReportAfterReopen(frozen, in: firstReopened)
        let firstHarness = LiveHarness(
            support: current.support, factory: firstFactory, session: firstReopened,
            packetID: incoming.packetID, rootID: incoming.rootID,
            packetCreatedAt: incoming.packetCreatedAt)
        let secondPackage = try exportPackage(firstHarness, root: root, name: "forked-report")
        let secondPackageBefore = try fileTree(secondPackage)
        XCTAssertEqual(try fileTree(package), packageBefore)
        try fileManager.removeItem(at: package)
        XCTAssertFalse(fileManager.fileExists(atPath: package.path))

        let secondValidated = try importPackage(
            secondPackage, into: firstReopened, stageID: uuid(22_002))
        let second = try await BackupRestoreService(applicationSupportURL: current.support).restore(
            validatedPackage: secondValidated,
            currentModelContext: firstReopened.modelContext,
            currentGenerationID: firstReopened.generationID,
            currentGenerationRootURL: firstReopened.generationRootURL,
            mode: .fork)
        XCTAssertNotEqual(second.workspaceID, first.workspaceID)
        XCTAssertNotEqual(second.workspaceID, incoming.session.workspaceID)
        XCTAssertNotEqual(second.workspaceIdentity.replicaID, first.workspaceIdentity.replicaID)
        XCTAssertNotEqual(second.generationID, first.generationID)
        XCTAssertEqual(try fileTree(secondPackage), secondPackageBefore)
        XCTAssertFalse(fileManager.fileExists(atPath: secondValidated.stagedPackageURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: package.path))
        let secondFactory = StoreGenerationFactory(applicationSupportURL: current.support)
        let secondReopened = try secondFactory.openOrBootstrapCurrent()
        XCTAssertEqual(secondReopened.generationID, second.generationID)
        XCTAssertEqual(secondReopened.workspaceIdentity, second.workspaceIdentity)
        try assertPreservedReportAfterReopen(frozen, in: secondReopened)
        XCTAssertFalse(fileManager.fileExists(atPath: current.support
            .appendingPathComponent("FieldEvidenceRestore/restore.json").path))
    }

    @MainActor
    func testCancelRemovesOnlyOwnedStageAndDirtyCurrentFailsClosed() async throws {
        let root = try makeRoot("cancel")
        defer { try? fileManager.removeItem(at: root) }
        let current = try await makeLiveHarness(
            root: root, name: "current", base: 201, label: "Current sign",
            observedAt: Date(timeIntervalSince1970: 1_786_708_000)
        )
        let incoming = try await makeLiveHarness(
            root: root, name: "incoming", base: 301, label: "Incoming sign",
            observedAt: Date(timeIntervalSince1970: 1_786_709_000)
        )
        let package = try exportPackage(incoming, root: root, name: "incoming")
        let packageBefore = try fileTree(package)
        let currentBefore = try fileTree(current.session.generationRootURL)
        let pointerBefore = try Data(contentsOf: current.support.appendingPathComponent(
            "FieldEvidenceData/current.json"
        ))
        let validated = try importPackage(package, into: current.session, stageID: uuid(390))

        try BackupImportService(
            generationRootURL: current.session.generationRootURL,
            scopedAccess: .alreadyAuthorized
        ).discard(validated)

        XCTAssertFalse(fileManager.fileExists(atPath: validated.stagedPackageURL.path))
        XCTAssertEqual(try fileTree(package), packageBefore)
        XCTAssertEqual(try fileTree(current.session.generationRootURL), currentBefore)
        XCTAssertEqual(
            try Data(contentsOf: current.support.appendingPathComponent(
                "FieldEvidenceData/current.json"
            )),
            pointerBefore
        )
        XCTAssertEqual(try current.factory.currentGenerationID(), current.session.generationID)
        XCTAssertFalse(fileManager.fileExists(atPath: current.support.appendingPathComponent(
            "FieldEvidenceRestore/restore.json"
        ).path))

        let site = try XCTUnwrap(
            try current.session.modelContext.fetch(FetchDescriptor<Site>()).first
        )
        site.label = "Unsaved current edit"
        XCTAssertThrowsError(try BackupRestoreService.currentSummary(
            modelContext: current.session.modelContext,
            generationRootURL: current.session.generationRootURL
        )) { error in
            XCTAssertEqual(
                error as? BackupRestoreServiceError,
                .contextHasChanges
            )
        }
        current.session.modelContext.rollback()
    }

    @MainActor
    func testPacketCollisionFailsBeforeGenerationOrJournalMutation() async throws {
        let root = try makeRoot("collision")
        defer { try? fileManager.removeItem(at: root) }
        let current = try await makeLiveHarness(
            root: root, name: "current", base: 401, label: "Current sign",
            observedAt: Date(timeIntervalSince1970: 1_786_708_000),
            packetIDOverride: uuid(501)
        )
        let incoming = try await makeLiveHarness(
            root: root, name: "incoming", base: 501, label: "Incoming sign",
            observedAt: Date(timeIntervalSince1970: 1_786_709_000)
        )
        let package = try exportPackage(incoming, root: root, name: "incoming")
        let validated = try importPackage(package, into: current.session, stageID: uuid(590))
        let supportBefore = try fileTree(current.support)
        let service = try BackupRestoreService(
            applicationSupportURL: current.support,
            now: { self.replacementAt },
            makeUUID: sequence([uuid(591), uuid(592)])
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await service.restore(
                validatedPackage: validated,
                currentModelContext: current.session.modelContext,
                currentGenerationID: current.session.generationID,
                currentGenerationRootURL: current.session.generationRootURL,
                mode: .replaceExisting
            )
        } verify: { error in
            XCTAssertEqual(error as? BackupRestoreServiceError, .invalidRestoreAuthority)
        }
        XCTAssertEqual(try fileTree(current.support), supportBefore)
        XCTAssertEqual(try current.factory.currentGenerationID(), current.session.generationID)
        XCTAssertFalse(fileManager.fileExists(atPath: current.support.appendingPathComponent(
            "FieldEvidenceRestore/restore.json"
        ).path))
        try BackupImportService(
            generationRootURL: current.session.generationRootURL,
            scopedAccess: .alreadyAuthorized
        ).discard(validated)
    }

    @MainActor
    func testRecoveryPreservesReplacementUnionAcrossEveryJournalPhase() async throws {
        let cases: [(point: BackupRestoreFailurePoint, keepsOld: Bool)] = [
            (.afterPreparedWrite, true),
            (.afterGenerationInstall, true),
            (.afterPointerSwitch, false),
            (.afterNewGenerationValidation, false),
        ]

        for (index, value) in cases.enumerated() {
            let plannedAt = Date(timeIntervalSince1970: 1_786_710_000 + Double(index))
            let reopenedAt = plannedAt.addingTimeInterval(86_400 + Double(index))
            let root = try makeRoot("recovery-\(index)")
            defer { try? fileManager.removeItem(at: root) }
            let current = try await makeLiveHarness(
                root: root,
                name: "current",
                base: 601 + index * 20,
                label: "Current sign \(index)",
                observedAt: Date(timeIntervalSince1970: 1_786_708_000)
            )
            let incoming = try await makeLiveHarness(
                root: root,
                name: "incoming",
                base: 701 + index * 20,
                label: "Incoming sign \(index)",
                observedAt: Date(timeIntervalSince1970: 1_786_709_000)
            )
            let package = try exportPackage(incoming, root: root, name: "incoming")
            let validated = try importPackage(
                package,
                into: current.session,
                stageID: uuid(790 + index)
            )
            let oldID = current.session.generationID
            let service = try BackupRestoreService(
                applicationSupportURL: current.support,
                now: { plannedAt },
                makeUUID: sequence([uuid(800 + index * 2), uuid(801 + index * 2)]),
                failureInjection: BackupRestoreFailureInjection(
                    failOnceAt: value.point
                )
            )

            await XCTAssertThrowsErrorAsync {
                _ = try await service.restore(
                    validatedPackage: validated,
                    currentModelContext: current.session.modelContext,
                    currentGenerationID: oldID,
                    currentGenerationRootURL: current.session.generationRootURL,
                    mode: .replaceExisting
                )
            } verify: { error in
                XCTAssertEqual(
                    error as? BackupRestoreServiceError,
                    .injectedFailure
                )
            }

            let intentBeforeRecovery = try XCTUnwrap(
                RestoreIntentStore(applicationSupportURL: current.support).load()
            )
            XCTAssertEqual(intentBeforeRecovery.schemaVersion, 3)
            XCTAssertEqual(intentBeforeRecovery.replacementAt, plannedAt)
            let intentData = try Data(contentsOf: current.support.appendingPathComponent(
                "FieldEvidenceRestore/restore.json"
            ))
            let timestamp = try XCTUnwrap(
                intentBeforeRecovery.replacementTimestampMilliseconds
            )
            let intentText = try XCTUnwrap(String(data: intentData, encoding: .utf8))
            let hostileTimestampData = Data(intentText.replacingOccurrences(
                of: "\"replacementTimestampMilliseconds\":\(timestamp)",
                with: "\"replacementTimestampMilliseconds\":\(timestamp).5"
            ).utf8)
            XCTAssertThrowsError(try RestoreIntentCodecV1.decode(hostileTimestampData))
            if index == 0, let identity = intentBeforeRecovery.identity {
                let legacyV1 = RestoreIntentV1(
                    newGenerationID: intentBeforeRecovery.newGenerationID,
                    newGenerationRelativePath: intentBeforeRecovery.newGenerationRelativePath,
                    oldGenerationID: intentBeforeRecovery.oldGenerationID,
                    phase: intentBeforeRecovery.phase,
                    restoreID: intentBeforeRecovery.restoreID,
                    schemaVersion: 1,
                    stagingGenerationRelativePath: intentBeforeRecovery
                        .stagingGenerationRelativePath
                )
                let legacyV2 = RestoreIntentV1(
                    newGenerationID: intentBeforeRecovery.newGenerationID,
                    newGenerationRelativePath: intentBeforeRecovery.newGenerationRelativePath,
                    oldGenerationID: intentBeforeRecovery.oldGenerationID,
                    phase: intentBeforeRecovery.phase,
                    restoreID: intentBeforeRecovery.restoreID,
                    schemaVersion: 2,
                    stagingGenerationRelativePath: intentBeforeRecovery
                        .stagingGenerationRelativePath,
                    identity: identity
                )
                let legacyV1Data = try RestoreIntentCodecV1.encode(legacyV1)
                let legacyV2Data = try RestoreIntentCodecV1.encode(legacyV2)
                XCTAssertEqual(
                    try RestoreIntentCodecV1.decode(
                        legacyV1Data
                    ),
                    legacyV1
                )
                XCTAssertEqual(
                    try RestoreIntentCodecV1.decode(
                        legacyV2Data
                    ),
                    legacyV2
                )
                let legacyV1Object = try XCTUnwrap(
                    try JSONSerialization.jsonObject(with: legacyV1Data)
                        as? [String: Any]
                )
                let legacyV2Object = try XCTUnwrap(
                    try JSONSerialization.jsonObject(with: legacyV2Data)
                        as? [String: Any]
                )
                XCTAssertEqual(Set(legacyV1Object.keys), Set([
                    "newGenerationID", "newGenerationRelativePath",
                    "oldGenerationID", "phase", "restoreID", "schemaVersion",
                    "stagingGenerationRelativePath",
                ]))
                XCTAssertEqual(Set(legacyV2Object.keys), Set([
                    "identity", "newGenerationID", "newGenerationRelativePath",
                    "oldGenerationID", "phase", "restoreID", "schemaVersion",
                    "stagingGenerationRelativePath",
                ]))
                XCTAssertNil(legacyV1Object["cloneRetirementPlanSHA256"])
                XCTAssertNil(legacyV2Object["cloneRetirementPlanSHA256"])
            }
            if index == 2, let identity = intentBeforeRecovery.identity {
                let legacyV2 = RestoreIntentV1(
                    newGenerationID: intentBeforeRecovery.newGenerationID,
                    newGenerationRelativePath: intentBeforeRecovery.newGenerationRelativePath,
                    oldGenerationID: intentBeforeRecovery.oldGenerationID,
                    phase: intentBeforeRecovery.phase,
                    restoreID: intentBeforeRecovery.restoreID,
                    schemaVersion: 2,
                    stagingGenerationRelativePath: intentBeforeRecovery
                        .stagingGenerationRelativePath,
                    identity: identity
                )
                let intentURL = current.support.appendingPathComponent(
                    "FieldEvidenceRestore/restore.json"
                )
                let pendingURL = current.support.appendingPathComponent(
                    "FieldEvidenceRestore/.restore.json.next"
                )
                let phaseMismatch = Data(intentText.replacingOccurrences(
                    of: "\"phase\":\"pointer_switched\"",
                    with: "\"phase\":\"prepared\""
                ).utf8)
                try phaseMismatch.write(to: pendingURL, options: .atomic)
                try ProtectedFilePolicyV1.applyAndVerify(.journalTemporary, at: pendingURL)
                XCTAssertThrowsError(try RestoreIntentStore(
                    applicationSupportURL: current.support
                ).load())
                XCTAssertEqual(try Data(contentsOf: intentURL), intentData)
                XCTAssertEqual(try Data(contentsOf: pendingURL), phaseMismatch)
                try fileManager.removeItem(at: pendingURL)

                let timestampMismatch = Data(intentText
                    .replacingOccurrences(
                        of: "\"phase\":\"pointer_switched\"",
                        with: "\"phase\":\"new_generation_validated\""
                    )
                    .replacingOccurrences(
                        of: "\"replacementTimestampMilliseconds\":\(timestamp)",
                        with: "\"replacementTimestampMilliseconds\":\(timestamp + 1)"
                    ).utf8)
                try timestampMismatch.write(to: pendingURL, options: .atomic)
                try ProtectedFilePolicyV1.applyAndVerify(.journalTemporary, at: pendingURL)
                XCTAssertThrowsError(try RestoreIntentStore(
                    applicationSupportURL: current.support
                ).load())
                XCTAssertEqual(try Data(contentsOf: intentURL), intentData)
                XCTAssertEqual(try Data(contentsOf: pendingURL), timestampMismatch)
                try fileManager.removeItem(at: pendingURL)

                // Inject released canonical V2 bytes after the pointer switch;
                // a V3-to-V2 store replacement is itself an invalid operation.
                let legacyData = try RestoreIntentCodecV1.encode(legacyV2)
                try legacyData.write(to: intentURL, options: .atomic)
                try ProtectedFilePolicyV1.applyAndVerify(.journal, at: intentURL)
                XCTAssertThrowsError(try BackupRestoreService(
                    applicationSupportURL: current.support,
                    now: { reopenedAt }
                ).reconcileAtStartup())
                XCTAssertEqual(try Data(contentsOf: intentURL), legacyData)
                XCTAssertEqual(
                    try RestoreIntentStore(applicationSupportURL: current.support).load(),
                    legacyV2
                )
                try intentData.write(to: intentURL, options: .atomic)
                try ProtectedFilePolicyV1.applyAndVerify(.journal, at: intentURL)
            }

            let recovery = try BackupRestoreService(
                applicationSupportURL: current.support,
                now: { reopenedAt }
            )
            let recovered: StoreGenerationSession?
            do {
                recovered = try await recovery
                    .reconcileRestoreAndPrivateSystemDiscoveryAtStartup()
            } catch {
                XCTFail("Recovery failed at \(value.point): \(error)")
                continue
            }
            let active = try current.factory.openOrBootstrapCurrent()
            if value.keepsOld {
                XCTAssertNil(recovered)
                XCTAssertEqual(active.generationID, oldID)
                XCTAssertEqual(
                    try active.modelContext.fetch(FetchDescriptor<Asset>()).map(\.label),
                    ["Current sign \(index)"]
                )
                XCTAssertEqual(
                    Set(try active.modelContext.fetch(FetchDescriptor<Packet>())
                        .map(\.stableRootID)),
                    Set([current.rootID])
                )
            } else {
                XCTAssertEqual(recovered?.generationID, active.generationID)
                XCTAssertNotEqual(active.generationID, oldID)
                XCTAssertEqual(
                    try active.modelContext.fetch(FetchDescriptor<Asset>()).map(\.label),
                    ["Incoming sign \(index)"]
                )
                XCTAssertEqual(
                    Set(try active.modelContext.fetch(FetchDescriptor<Packet>())
                        .map(\.stableRootID)),
                    Set([current.rootID, incoming.rootID])
                )
                XCTAssertEqual(
                    try active.modelContext.fetch(FetchDescriptor<Packet>())
                        .first(where: { $0.stableRootID == current.rootID })?
                        .contentDeletedAt,
                    plannedAt
                )
            }
            XCTAssertFalse(fileManager.fileExists(
                atPath: current.support.appendingPathComponent(
                    "FieldEvidenceRestore/restore.json"
                ).path
            ))
            XCTAssertNil(try RestoreIntentStore(applicationSupportURL: current.support).load())
        }
    }

    func testRestoreIntentTimestampUsesOneCanonicalMillisecondDomain() throws {
        XCTAssertEqual(
            RestoreIntentV1.canonicalReplacementTimestampMilliseconds(
                Date(timeIntervalSince1970: 1.001)
            ),
            1_001
        )
        XCTAssertEqual(
            RestoreIntentV1.canonicalReplacementTimestampMilliseconds(
                Date(timeIntervalSince1970: 1.0014)
            ),
            1_001
        )
        XCTAssertNil(RestoreIntentV1.canonicalReplacementTimestampMilliseconds(
            Date(timeIntervalSince1970: .infinity)
        ))
        XCTAssertNil(RestoreIntentV1.date(Int.max))

        let intent = RestoreIntentV1(
            newGenerationID: uuid(901),
            newGenerationRelativePath:
                "FieldEvidenceData/generations/\(uuid(901).uuidString.lowercased())",
            oldGenerationID: uuid(902),
            phase: .prepared,
            restoreID: uuid(903),
            schemaVersion: 3,
            stagingGenerationRelativePath:
                "FieldEvidenceRestore/generations/\(uuid(901).uuidString.lowercased())",
            replacementTimestampMilliseconds: 1_001
        )
        let data = try RestoreIntentCodecV1.encode(intent)
        XCTAssertEqual(try RestoreIntentCodecV1.decode(data), intent)
        let schema3Object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(Set(schema3Object.keys), Set([
            "identity", "newGenerationID", "newGenerationRelativePath",
            "oldGenerationID", "phase", "replacementTimestampMilliseconds",
            "restoreID", "schemaVersion", "stagingGenerationRelativePath",
        ]))
        XCTAssertNil(schema3Object["cloneRetirementPlanSHA256"])
        let phaseCopy = intent.advancing(to: .generationInstalled)
        XCTAssertEqual(phaseCopy.replacementTimestampMilliseconds, 1_001)
        XCTAssertEqual(try RestoreIntentCodecV1.decode(
            RestoreIntentCodecV1.encode(phaseCopy)
        ), phaseCopy)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertThrowsError(try RestoreIntentCodecV1.decode(Data(text
            .replacingOccurrences(
                of: "\"replacementTimestampMilliseconds\":1001",
                with: "\"replacementTimestampMilliseconds\":true"
            ).utf8)))
        XCTAssertThrowsError(try RestoreIntentCodecV1.decode(Data(
            (String(text.dropLast()) + ",\"unexpected\":0}").utf8
        )))
        let outOfRange = RestoreIntentV1(
            newGenerationID: uuid(901),
            newGenerationRelativePath:
                "FieldEvidenceData/generations/\(uuid(901).uuidString.lowercased())",
            oldGenerationID: uuid(902),
            phase: .prepared,
            restoreID: uuid(903),
            schemaVersion: 3,
            stagingGenerationRelativePath:
                "FieldEvidenceRestore/generations/\(uuid(901).uuidString.lowercased())",
            replacementTimestampMilliseconds: Int.max
        )
        XCTAssertThrowsError(try RestoreIntentCodecV1.encode(outOfRange))

        let sourceWorkspaceID = uuid(904)
        let sourceReplicaID = uuid(905)
        let oldPointer = RestorePointerIdentityV1(
            generationID: uuid(902),
            generationManifestSHA256: String(repeating: "a", count: 64),
            workspaceID: uuid(906),
            replicaID: uuid(907)
        )
        let targetPointer = RestorePointerIdentityV1(
            generationID: uuid(901),
            generationManifestSHA256: String(repeating: "b", count: 64),
            knownReplicaIDs: Set([sourceReplicaID, oldPointer.replicaID]),
            workspaceID: uuid(908),
            replicaID: uuid(909)
        )
        let cloneIdentity = RestoreIdentityV1(
            mode: .clone,
            source: .init(
                workspaceID: sourceWorkspaceID,
                replicaID: sourceReplicaID
            ),
            oldPointer: oldPointer,
            targetPointer: targetPointer,
            recordIdentityDisposition: .preserve
        )
        let planDigest = String(repeating: "c", count: 64)
        let cloneIntent = RestoreIntentV1(
            identity: cloneIdentity,
            restoreID: uuid(903),
            replacementTimestampMilliseconds: 1_001,
            cloneRetirementPlanSHA256: planDigest
        )
        XCTAssertEqual(cloneIntent.schemaVersion, 4)
        let cloneData = try RestoreIntentCodecV1.encode(cloneIntent)
        XCTAssertEqual(try RestoreIntentCodecV1.decode(cloneData), cloneIntent)
        let cloneObject = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: cloneData) as? [String: Any]
        )
        XCTAssertEqual(cloneObject["cloneRetirementPlanSHA256"] as? String, planDigest)
        XCTAssertEqual(Set(cloneObject.keys), Set([
            "cloneRetirementPlanSHA256", "identity", "newGenerationID",
            "newGenerationRelativePath", "oldGenerationID", "phase",
            "replacementTimestampMilliseconds", "restoreID", "schemaVersion",
            "stagingGenerationRelativePath",
        ]))
        let clonePhaseCopy = cloneIntent.advancing(to: .generationInstalled)
        XCTAssertEqual(clonePhaseCopy.cloneRetirementPlanSHA256, planDigest)
        XCTAssertEqual(
            try RestoreIntentCodecV1.decode(
                RestoreIntentCodecV1.encode(clonePhaseCopy)
            ),
            clonePhaseCopy
        )

        let ordinaryClone = RestoreIntentV1(
            identity: cloneIdentity,
            restoreID: uuid(903),
            replacementTimestampMilliseconds: 1_001
        )
        XCTAssertEqual(ordinaryClone.schemaVersion, 3)
        XCTAssertNil(ordinaryClone.cloneRetirementPlanSHA256)
        let ordinaryCloneData = try RestoreIntentCodecV1.encode(ordinaryClone)
        let ordinaryCloneObject = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: ordinaryCloneData)
                as? [String: Any]
        )
        XCTAssertNil(ordinaryCloneObject["cloneRetirementPlanSHA256"])

        let forkIdentity = RestoreIdentityV1(
            mode: .fork,
            source: cloneIdentity.source,
            oldPointer: oldPointer,
            targetPointer: targetPointer,
            recordIdentityDisposition: .preserve
        )
        let schema4Null = RestoreIntentV1(
            newGenerationID: targetPointer.generationID,
            newGenerationRelativePath: cloneIntent.newGenerationRelativePath,
            oldGenerationID: oldPointer.generationID,
            phase: .prepared,
            restoreID: uuid(903),
            schemaVersion: 4,
            stagingGenerationRelativePath: cloneIntent.stagingGenerationRelativePath,
            identity: forkIdentity,
            replacementTimestampMilliseconds: 1_001
        )
        let schema4NullData = try RestoreIntentCodecV1.encode(schema4Null)
        let schema4NullObject = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: schema4NullData) as? [String: Any]
        )
        XCTAssertTrue(schema4NullObject["cloneRetirementPlanSHA256"] is NSNull)
        XCTAssertEqual(try RestoreIntentCodecV1.decode(schema4NullData), schema4Null)

        let invalidDigest = RestoreIntentV1(
            identity: cloneIdentity,
            restoreID: uuid(903),
            replacementTimestampMilliseconds: 1_001,
            cloneRetirementPlanSHA256: String(repeating: "C", count: 64)
        )
        XCTAssertThrowsError(try RestoreIntentCodecV1.encode(invalidDigest))
        let shortDigest = RestoreIntentV1(
            identity: cloneIdentity,
            restoreID: uuid(903),
            replacementTimestampMilliseconds: 1_001,
            cloneRetirementPlanSHA256: String(repeating: "c", count: 63)
        )
        XCTAssertThrowsError(try RestoreIntentCodecV1.encode(shortDigest))
        let invalidMode = RestoreIntentV1(
            identity: forkIdentity,
            restoreID: uuid(903),
            replacementTimestampMilliseconds: 1_001,
            cloneRetirementPlanSHA256: planDigest
        )
        XCTAssertThrowsError(try RestoreIntentCodecV1.encode(invalidMode))
        let invalidSchema = RestoreIntentV1(
            newGenerationID: cloneIntent.newGenerationID,
            newGenerationRelativePath: cloneIntent.newGenerationRelativePath,
            oldGenerationID: cloneIntent.oldGenerationID,
            phase: .prepared,
            restoreID: cloneIntent.restoreID,
            schemaVersion: 3,
            stagingGenerationRelativePath: cloneIntent.stagingGenerationRelativePath,
            identity: cloneIdentity,
            replacementTimestampMilliseconds: 1_001,
            cloneRetirementPlanSHA256: planDigest
        )
        XCTAssertThrowsError(try RestoreIntentCodecV1.encode(invalidSchema))
        let invalidNullClone = RestoreIntentV1(
            newGenerationID: cloneIntent.newGenerationID,
            newGenerationRelativePath: cloneIntent.newGenerationRelativePath,
            oldGenerationID: cloneIntent.oldGenerationID,
            phase: .prepared,
            restoreID: cloneIntent.restoreID,
            schemaVersion: 4,
            stagingGenerationRelativePath: cloneIntent.stagingGenerationRelativePath,
            identity: cloneIdentity,
            replacementTimestampMilliseconds: 1_001
        )
        XCTAssertThrowsError(try RestoreIntentCodecV1.encode(invalidNullClone))
        let cloneText = try XCTUnwrap(String(data: cloneData, encoding: .utf8))
        let missingDigestText = cloneText.replacingOccurrences(
            of: "\"cloneRetirementPlanSHA256\":\"\(planDigest)\",",
            with: ""
        )
        XCTAssertNotEqual(missingDigestText, cloneText)
        XCTAssertThrowsError(try RestoreIntentCodecV1.decode(Data(
            missingDigestText.utf8
        )))
        XCTAssertThrowsError(try RestoreIntentCodecV1.decode(Data(
            (String(cloneText.dropLast()) + ",\"unexpected\":0}").utf8
        )))

        let storeRoot = try makeRoot("clone-retirement-intent")
        defer { try? fileManager.removeItem(at: storeRoot) }
        let store = try RestoreIntentStore(applicationSupportURL: storeRoot)
        try store.create(cloneIntent)
        let differentDigestPhase = RestoreIntentV1(
            identity: cloneIdentity,
            phase: .generationInstalled,
            restoreID: uuid(903),
            replacementTimestampMilliseconds: 1_001,
            cloneRetirementPlanSHA256: String(repeating: "d", count: 64)
        )
        XCTAssertThrowsError(try store.replace(
            expected: cloneIntent,
            with: differentDigestPhase
        )) { error in
            XCTAssertEqual(error as? RestoreIntentStoreError, .intentMismatch)
        }
        XCTAssertEqual(try store.load(), cloneIntent)
        try store.replace(expected: cloneIntent, with: clonePhaseCopy)
        XCTAssertEqual(try store.load(), clonePhaseCopy)
        try store.remove(expected: clonePhaseCopy)
    }
}

extension S6_5ReplacementUnionTests {
    func testV23P03C18RegistryPointerBindsPromotionReceiptIdentity() throws {
        let workspaceID = WorkspaceID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-00000000c185")!)
        let receiptID = UUID(uuidString: "c1850000-0000-4000-8000-000000000001")!
        let pointer = try ActivePackageRegistryPointerV1(
            pointerID: UUID(uuidString: "c1850000-0000-4000-8000-000000000002")!,
            workspaceID: workspaceID,
            packageID: "com.field-evidence.c18.replacement",
            activeReleaseRecordID: UUID(uuidString: "c1850000-0000-4000-8000-000000000003")!,
            promotionReceiptID: receiptID,
            activePackageReleaseID: String(repeating: "a", count: 64),
            activeReleaseRecordSHA256: String(repeating: "b", count: 64),
            revision: 1,
            mutationID: try MutationIDV1(
                rawValue: UUID(uuidString: "c1850000-0000-4000-8000-000000000004")!
            )
        )
        XCTAssertNoThrow(try pointer.validate())
        XCTAssertEqual(pointer.promotionReceiptID, receiptID)
    }
}

extension S6_5ReplacementUnionTests {
    func testV23P03C05Records42ReplacementUnionsPredecessorClosedMetadata() throws {
        let sourceWorkspace = WorkspaceID(rawValue: uuid(501))
        let targetWorkspace = WorkspaceID(rawValue: uuid(502))
        let first = try c05Sequence(
            workspace: sourceWorkspace,
            sequenceID: uuid(503),
            mutationID: uuid(504),
            revision: 1
        )
        let second = try c05Sequence(
            workspace: sourceWorkspace,
            sequenceID: uuid(503),
            mutationID: uuid(505),
            revision: 2,
            predecessor: try first.reference
        )
        let current = c05Records(sequences: [first])
        let incoming = c05Records(sequences: [first, second])

        let union = try C05EvidenceMetadataReplacementRestoreBoundaryV1.canonicalRows(
            current: current,
            incoming: incoming,
            mode: .replaceExisting,
            sourceWorkspaceID: sourceWorkspace.rawValue,
            targetWorkspaceID: sourceWorkspace.rawValue
        )
        XCTAssertEqual(union.associations, [])
        XCTAssertEqual(union.sequences, [first, second])
        try C05EvidenceMetadataBackupEnrollmentV1.validate(
            c05Records(sequences: union.sequences)
        )

        for mode in [BackupRestoreMode.clone, .fork] {
            XCTAssertThrowsError(try C05EvidenceMetadataReplacementRestoreBoundaryV1.canonicalRows(
                current: c05Records(),
                incoming: incoming,
                mode: mode,
                sourceWorkspaceID: sourceWorkspace.rawValue,
                targetWorkspaceID: targetWorkspace.rawValue
            )) { error in
                XCTAssertEqual(error as? ReplacementRestoreRuleError, .invalidAuthority)
            }
            let empty = try C05EvidenceMetadataReplacementRestoreBoundaryV1.canonicalRows(
                current: c05Records(),
                incoming: c05Records(),
                mode: mode,
                sourceWorkspaceID: sourceWorkspace.rawValue,
                targetWorkspaceID: targetWorkspace.rawValue
            )
            XCTAssertEqual(empty.associations, [])
            XCTAssertEqual(empty.sequences, [])
        }
        XCTAssertEqual(
            C05EvidenceMetadataRestoreIdentityBoundaryV1.disposition(for: .clone),
            .rejectCloneForkWithoutRebind
        )
        XCTAssertFalse(C05EvidenceMetadataRestoreIdentityBoundaryV1.sourceRowsAutomaticallyActivateOnCloneOrFork)
        XCTAssertTrue(C05EvidenceMetadataRestoreIdentityBoundaryV1.cloneForkWithoutRebindFailsClosed)

        let sourcePointer = RestorePointerIdentityV1(
            generationID: uuid(508),
            generationManifestSHA256: String(repeating: "a", count: 64),
            workspaceID: sourceWorkspace.rawValue,
            replicaID: uuid(509)
        )
        let targetPointer = RestorePointerIdentityV1(
            generationID: uuid(510),
            generationManifestSHA256: String(repeating: "b", count: 64),
            workspaceID: targetWorkspace.rawValue,
            replicaID: uuid(511)
        )
        for mode in [BackupRestoreMode.clone, .fork] {
            let identity = RestoreIdentityV1(
                mode: mode,
                source: .init(workspaceID: sourceWorkspace.rawValue, replicaID: sourcePointer.replicaID),
                oldPointer: sourcePointer,
                targetPointer: targetPointer,
                recordIdentityDisposition: .preserve
            )
            XCTAssertThrowsError(try C05EvidenceMetadataRestoreIdentityBoundaryV1.validate(
                incoming,
                identity: identity
            )) { error in
                XCTAssertEqual(error as? RestoreIdentityDecisionErrorV1, .invalidMode)
            }
            XCTAssertNoThrow(try C05EvidenceMetadataRestoreIdentityBoundaryV1.validate(
                c05Records(),
                identity: identity
            ))
        }

        let orphan = c05Records(sequences: [second])
        XCTAssertThrowsError(try C05EvidenceMetadataReplacementRestoreBoundaryV1.canonicalRows(
            current: current,
            incoming: orphan,
            mode: .replaceExisting,
            sourceWorkspaceID: sourceWorkspace.rawValue,
            targetWorkspaceID: sourceWorkspace.rawValue
        )) { error in
            XCTAssertEqual(error as? ReplacementRestoreRuleError, .invalidAuthority)
        }

        let conflicting = try c05Sequence(
            workspace: sourceWorkspace,
            sequenceID: uuid(503),
            mutationID: uuid(506),
            revision: 1
        )
        XCTAssertThrowsError(try C05EvidenceMetadataReplacementRestoreBoundaryV1.canonicalRows(
            current: current,
            incoming: c05Records(sequences: [conflicting]),
            mode: .replaceExisting,
            sourceWorkspaceID: sourceWorkspace.rawValue,
            targetWorkspaceID: sourceWorkspace.rawValue
        )) { error in
            XCTAssertEqual(error as? ReplacementRestoreRuleError, .invalidAuthority)
        }
    }
}

extension S6_5ReplacementUnionTests {
    func testV23P03C36ReplacementRecordRetainsCanonicalOperationalIdentity() {
        let id=UUID(),workspaceID=UUID(),bytes=Data("canonical-draft".utf8)
        let record=V16BackupFieldDraftRecordV1(kind:.checkpoint,id:id,workspaceID:workspaceID,revision:7,canonicalData:bytes)
        XCTAssertEqual(record,V16BackupFieldDraftRecordV1(kind:.checkpoint,id:id,workspaceID:workspaceID,revision:7,canonicalData:bytes))
        XCTAssertNotEqual(record.kind,.discardReceipt)
    }
}

private extension S6_5ReplacementUnionTests {
    struct LiveHarness {
        let support: URL
        let factory: StoreGenerationFactory
        let session: StoreGenerationSession
        let packetID: UUID
        let rootID: UUID
        let packetCreatedAt: Date
    }

#if DEBUG
    @MainActor
    func assertOwnedRegularCreationContract(service: BackupRestoreService, root: URL) throws {
        let contractRoot = root.appendingPathComponent("owned-create-contract", isDirectory: true)
        try fileManager.createDirectory(at: contractRoot, withIntermediateDirectories: true)
        let normal = contractRoot.appendingPathComponent("normal", isDirectory: true)
        let normalParent = normal.appendingPathComponent("parent", isDirectory: true)
        try fileManager.createDirectory(at: normalParent, withIntermediateDirectories: true)
        try service.c36WithPinnedRegularCreationForTesting(
            root: normal, relativePath: "parent", authorityCheck: {}
        ) { parent, verify, create in
            var before = stat()
            XCTAssertEqual(Darwin.fstat(parent, &before), 0)
            for name in ["first", "second"] {
                let fd = try create(name)
                defer { _ = Darwin.close(fd) }
                var opened = stat()
                var named = stat()
                var after = stat()
                XCTAssertEqual(Darwin.fstat(fd, &opened), 0)
                XCTAssertEqual(Darwin.fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW), 0)
                XCTAssertEqual(opened.st_ino, named.st_ino)
                XCTAssertEqual(opened.st_dev, named.st_dev)
                XCTAssertEqual(opened.st_mode & S_IFMT, S_IFREG)
                XCTAssertEqual(opened.st_nlink, 1)
                XCTAssertEqual(Darwin.fstat(parent, &after), 0)
                XCTAssertEqual(UInt64(after.st_nlink), UInt64(before.st_nlink) + 1)
                try verify()
                before = after
            }
        }
        XCTAssertEqual(Set(try fileManager.contentsOfDirectory(atPath: normalParent.path)),
                       Set(["first", "second"]))

        for kind in ["regular", "symlink", "hardlink", "directory"] {
            let caseRoot = contractRoot.appendingPathComponent("existing-" + kind, isDirectory: true)
            let parent = caseRoot.appendingPathComponent("parent", isDirectory: true)
            let target = caseRoot.appendingPathComponent("target")
            let leaf = parent.appendingPathComponent("leaf")
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            let original = Data("preserved existing bytes".utf8)
            try original.write(to: target)
            switch kind {
            case "regular": try original.write(to: leaf)
            case "symlink": try fileManager.createSymbolicLink(at: leaf, withDestinationURL: target)
            case "hardlink": try fileManager.linkItem(at: target, to: leaf)
            default: try fileManager.createDirectory(at: leaf, withIntermediateDirectories: false)
            }
            try service.c36WithPinnedRegularCreationForTesting(
                root: caseRoot, relativePath: "parent", authorityCheck: {}
            ) { _, verify, create in
                XCTAssertThrowsError(try create("leaf"))
                try verify()
            }
            XCTAssertEqual(try Data(contentsOf: target), original)
            if kind != "directory" { XCTAssertEqual(try Data(contentsOf: leaf), original) }
            XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: parent.path), ["leaf"])
        }
        for name in ["", ".", "..", "../outside", "/absolute", "back\\slash", "nul\0suffix"] {
            try service.c36WithPinnedRegularCreationForTesting(
                root: normal, relativePath: "parent", authorityCheck: {}
            ) { _, verify, create in
                XCTAssertThrowsError(try create(name))
                try verify()
            }
        }
        XCTAssertEqual(Set(try fileManager.contentsOfDirectory(atPath: normalParent.path)),
                       Set(["first", "second"]))

        for mutation in ["authority-loss", "extra-entry", "replace-leaf", "hardlink-leaf",
                         "replace-parent", "replace-ancestor"] {
            let caseRoot = contractRoot.appendingPathComponent(mutation, isDirectory: true)
            let ancestor = caseRoot.appendingPathComponent("ancestor", isDirectory: true)
            let parent = ancestor.appendingPathComponent("parent", isDirectory: true)
            let leaf = parent.appendingPathComponent("leaf")
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            var injected = false
            let authorityCheck = {
                guard !injected, self.fileManager.fileExists(atPath: leaf.path) else { return }
                injected = true
                switch mutation {
                case "authority-loss": throw FixtureError.invalid
                case "extra-entry": try Data("unrelated".utf8).write(to: parent.appendingPathComponent("extra"))
                case "replace-leaf":
                    try self.fileManager.removeItem(at: leaf)
                    try Data("replacement must survive".utf8).write(to: leaf)
                case "hardlink-leaf":
                    try self.fileManager.linkItem(at: leaf,
                        to: contractRoot.appendingPathComponent("outside-leaf-alias"))
                case "replace-parent":
                    try self.fileManager.moveItem(at: parent, to: ancestor.appendingPathComponent("old-parent"))
                    try self.fileManager.createDirectory(at: parent, withIntermediateDirectories: false)
                default:
                    try self.fileManager.moveItem(at: ancestor, to: caseRoot.appendingPathComponent("old-ancestor"))
                    try self.fileManager.createDirectory(at: ancestor, withIntermediateDirectories: false)
                }
            }
            XCTAssertThrowsError(try service.c36WithPinnedRegularCreationForTesting(
                root: caseRoot, relativePath: "ancestor/parent", authorityCheck: authorityCheck
            ) { _, verify, create in
                XCTAssertThrowsError(try create("leaf"))
                // Catching a post-create failure cannot revive the pin scope.
                XCTAssertThrowsError(try verify())
                XCTAssertThrowsError(try create("must-not-create"))
            })
            XCTAssertTrue(injected)
            XCTAssertFalse(fileManager.fileExists(atPath: parent.appendingPathComponent("must-not-create").path))
            if mutation == "replace-leaf" {
                XCTAssertEqual(try Data(contentsOf: leaf), Data("replacement must survive".utf8))
            } else if ["authority-loss", "extra-entry", "hardlink-leaf"].contains(mutation) {
                XCTAssertEqual(try Data(contentsOf: leaf), Data())
            }
        }
    }
#endif

    @MainActor
    func assertCoreRestoreProjectionPlanning(
        service: BackupRestoreService,
        records: V4BackupRecordsV1,
        sourceWorkspaceID: WorkspaceID,
        destinationWorkspaceID: WorkspaceID
    ) throws {
        XCTAssertNotEqual(sourceWorkspaceID, destinationWorkspaceID)
        let original = try XCTUnwrap(records.mutationHistory)
        let sourcePlan = try MutationJournalStoreV1.planningCoreRestoreHistory(
            in: records, workspaceID: sourceWorkspaceID
        )
        XCTAssertEqual(sourcePlan.entityRevisions,
            original.entityRevisions.sorted { $0.identity.stableKey < $1.identity.stableKey })
        let destinationPlan = try MutationJournalStoreV1.planningCoreRestoreHistory(
            in: records, workspaceID: destinationWorkspaceID
        )
        for plan in [sourcePlan, destinationPlan] {
            XCTAssertEqual(plan.receipts, original.receipts)
            XCTAssertEqual(plan.quarantines, original.quarantines)
            XCTAssertEqual(plan.workspaceRevision, original.workspaceRevision)
            XCTAssertEqual(plan.lastLocalSequence, original.lastLocalSequence)
            XCTAssertEqual(plan.entityRevisions.map(\.identity),
                original.entityRevisions.map(\.identity).sorted { $0.stableKey < $1.stableKey })
            for terminal in plan.entityRevisions {
                XCTAssertEqual(terminal.revision,
                    try XCTUnwrap(original.entityRevisions.first { $0.identity == terminal.identity }).revision)
            }
        }
        let coreKinds: Set<WorkspaceEntityKindV1> = [
            .site, .asset, .locationNode, .assetPlacementEvent,
            .assetCompositionEdge, .assetCompositionEvent, .savedSmartView,
            .workflowRecord, .evidenceFile, .issue, .packet, .report, .deletionLedgerEntry,
        ]
        let originalByID = Dictionary(uniqueKeysWithValues: original.entityRevisions.map { ($0.identity, $0) })
        for terminal in destinationPlan.entityRevisions {
            if coreKinds.contains(terminal.identity.kind) {
                XCTAssertNotNil(terminal.externalProjectionSHA256)
            } else {
                XCTAssertEqual(terminal, originalByID[terminal.identity])
            }
        }
        // Expected bytes come from the frozen site DTO, not the planner's output
        // or a materialized destination journal.
        let site = try XCTUnwrap(records.sites.first)
        let siteIdentity = try WorkspaceEntityIdentityV1(kind: .site, id: site.id)
        let siteTerminal = try XCTUnwrap(destinationPlan.entityRevisions.first { $0.identity == siteIdentity })
        struct SiteBasis: Codable {
            let identity: WorkspaceEntityIdentityV1
            let revision: UInt64
            let value: V4BackupSiteDTO
        }
        XCTAssertEqual(siteTerminal.externalProjectionSHA256, try WorkspaceMutationCanonicalV1.sha256(
            SiteBasis(identity: siteIdentity, revision: siteTerminal.revision, value: site)))
        XCTAssertEqual(records.mutationHistory, original)

#if DEBUG
        // This is a history-copy regression, not C30 semantic admission. Opaque
        // payload sentinels must survive unchanged; the copier must not decode them.
        let context = V30BackupEvidenceContextRecordV1(kind: .evidenceContext,
            id: uuid(810), workspaceID: sourceWorkspaceID.rawValue, revision: 1,
            canonicalData: Data("context-copy-sentinel".utf8))
        let link = V30BackupEvidenceContextRecordV1(kind: .pairedObservationLink,
            id: uuid(811), workspaceID: sourceWorkspaceID.rawValue, revision: 2,
            canonicalData: Data("paired-link-copy-sentinel".utf8))
        var populatedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(records)) as? [String: Any])
        populatedObject["evidenceContexts"] = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode([context]))
        populatedObject["pairedObservationLinks"] = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode([link]))
        let populated = try JSONDecoder().decode(V4BackupRecordsV1.self,
            from: JSONSerialization.data(withJSONObject: populatedObject))
        XCTAssertEqual(populated.evidenceContexts, [context])
        XCTAssertEqual(populated.pairedObservationLinks, [link])
        let copied = service.c36ReplacingMutationHistoryForTesting(
            in: populated, with: destinationPlan)
        populatedObject["mutationHistory"] = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(destinationPlan))
        let expectedCopy = try JSONDecoder().decode(V4BackupRecordsV1.self,
            from: JSONSerialization.data(withJSONObject: populatedObject))
        XCTAssertEqual(copied, expectedCopy)
#endif

        // A duplicate planned row must reach and fail the changed entry point.
        // Decoding happens outside the failure assertion so it cannot mask it.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(records)) as? [String: Any])
        let sites = try XCTUnwrap(object["sites"] as? [[String: Any]])
        XCTAssertFalse(sites.isEmpty)
        object["sites"] = sites + [try XCTUnwrap(sites.first)]
        let duplicated = try JSONDecoder().decode(V4BackupRecordsV1.self,
            from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try MutationJournalStoreV1.planningCoreRestoreHistory(
            in: duplicated, workspaceID: destinationWorkspaceID))
    }

    struct FrozenReportPreservation {
        let reportID: UUID
        let packetID: UUID
        let sourceRecordID: UUID
        let snapshotSchemaVersion: Int
        let snapshotRelativePath: String
        let snapshotSHA256: String
        let snapshotData: Data
        let pdfRelativePath: String
        let pdfSHA256: String
        let pdfData: Data
        let originalReceipts: [MutationHistoryReceiptRecordV1]
    }

    @MainActor
    func freezeReportPreservation(in harness: LiveHarness) throws -> FrozenReportPreservation {
        let reports = try harness.session.modelContext.fetch(FetchDescriptor<Report>())
        XCTAssertEqual(reports.count, 1)
        let report = try XCTUnwrap(reports.first)
        XCTAssertEqual(report.packetID, harness.packetID)
        XCTAssertEqual(report.pdfState, ReportPDFState.ready.rawValue)
        let pdfPath = try XCTUnwrap(report.pdfRelativePath)
        let pdfHash = try XCTUnwrap(report.pdfSHA256)
        let snapshotData = try Data(contentsOf: harness.session.generationRootURL
            .appendingPathComponent(report.snapshotRelativePath))
        let pdfData = try Data(contentsOf: harness.session.generationRootURL.appendingPathComponent(pdfPath))
        XCTAssertEqual(CanonicalJSONV1.sha256(snapshotData), report.snapshotSHA256)
        XCTAssertEqual(CanonicalJSONV1.sha256(pdfData), pdfHash)
        let snapshot = try ReportSnapshotEncoderV1().decode(snapshotData)
        XCTAssertEqual(try ReportSnapshotEncoderV1().encode(snapshot).data, snapshotData)
        XCTAssertEqual(snapshot.reportID, report.id)
        XCTAssertEqual(snapshot.sourceRecordID, report.sourceRecordID)
        // This authentic CheckRunner fixture is the ordinary legacy control.
        // It does not prove temporal/assurance or typed snapshot preservation.
        XCTAssertEqual(snapshot.snapshotSchemaVersion, 1)
        XCTAssertNil(snapshot.temporalEvidenceLinks)
        let journal = try MutationJournalStoreV1(modelContext: harness.session.modelContext,
            identity: harness.session.workspaceIdentity, generationID: harness.session.generationID,
            allowStateBootstrap: false)
        try journal.validateAll()
        let receipts = try journal.exportSnapshot().receipts
        XCTAssertFalse(receipts.isEmpty)
        return FrozenReportPreservation(reportID: report.id, packetID: report.packetID,
            sourceRecordID: report.sourceRecordID, snapshotSchemaVersion: report.snapshotSchemaVersion,
            snapshotRelativePath: report.snapshotRelativePath, snapshotSHA256: report.snapshotSHA256,
            snapshotData: snapshotData, pdfRelativePath: pdfPath, pdfSHA256: pdfHash,
            pdfData: pdfData, originalReceipts: receipts)
    }

    @MainActor
    func assertPreservedReportAfterReopen(
        _ expected: FrozenReportPreservation, in session: StoreGenerationSession
    ) throws {
        let reports = try session.modelContext.fetch(FetchDescriptor<Report>())
        XCTAssertEqual(reports.count, 1)
        let report = try XCTUnwrap(reports.first)
        XCTAssertEqual(report.id, expected.reportID)
        XCTAssertEqual(report.packetID, expected.packetID)
        XCTAssertEqual(report.sourceRecordID, expected.sourceRecordID)
        XCTAssertEqual(report.snapshotSchemaVersion, expected.snapshotSchemaVersion)
        XCTAssertEqual(report.snapshotRelativePath, expected.snapshotRelativePath)
        XCTAssertEqual(report.snapshotSHA256, expected.snapshotSHA256)
        XCTAssertEqual(report.pdfRelativePath, expected.pdfRelativePath)
        XCTAssertEqual(report.pdfSHA256, expected.pdfSHA256)
        XCTAssertEqual(report.pdfState, ReportPDFState.ready.rawValue)
        XCTAssertEqual(try Data(contentsOf: session.generationRootURL
            .appendingPathComponent(expected.snapshotRelativePath)), expected.snapshotData)
        XCTAssertEqual(try Data(contentsOf: session.generationRootURL
            .appendingPathComponent(expected.pdfRelativePath)), expected.pdfData)
        let journal = try MutationJournalStoreV1(modelContext: session.modelContext,
            identity: session.workspaceIdentity, generationID: session.generationID,
            allowStateBootstrap: false)
        try journal.validateAll()
        let beforeRead = try journal.exportSnapshot()
        for receipt in expected.originalReceipts {
            XCTAssertTrue(beforeRead.receipts.contains(receipt),
                          "Preserve the exact original envelope, receipt and reversal bytes")
        }
        let owner = try StoreSessionCoordinator(validatingSession: session)
        var writerReleased = false
        defer { if !writerReleased { try? owner.invalidateAndReleaseWriter() } }
        do {
            let dependencies = try owner.packageLifecycleDependencies()
            let sourceSnapshot = try ReportSnapshotEncoderV1().decode(expected.snapshotData)
            let release = try PackageReleaseIdentityV1(package: SignPack.illuminatedSignV1)
            let profile = try dependencies.profileRegistry.resolve(release)
            let delivery = try ReportDeliveryCoordinator(modelContext: session.modelContext,
                lifecycleDependencies: dependencies, lifecycleProfile: profile)
            let ready = try delivery.validatedReadyReport(id: expected.reportID)
            XCTAssertEqual(ready.delivery.reportID, expected.reportID)
            XCTAssertEqual(ready.delivery.pdfSHA256, expected.pdfSHA256)
            XCTAssertEqual(ready.delivery.pdfData, expected.pdfData)
            XCTAssertEqual(try ReportSnapshotEncoderV1().encode(ready.snapshot).data, expected.snapshotData)
            let history = ReportHistoryCoordinator(modelContext: session.modelContext,
                deliveryCoordinator: delivery)
            let visits = try history.index().visits
            XCTAssertEqual(visits.count, 1)
            let visit = try XCTUnwrap(visits.first)
            XCTAssertEqual(visit.reportID, expected.reportID)
            XCTAssertEqual(visit.packetID, expected.packetID)
            XCTAssertEqual(visit.stableRootID, sourceSnapshot.stableRootID)
            XCTAssertEqual(visit.assetLabel, sourceSnapshot.asset.label)
            XCTAssertEqual(visit.siteLabel, sourceSnapshot.site.label)
            XCTAssertEqual(visit.evidence.map(\.evidenceID), sourceSnapshot.evidence.map(\.evidenceID))
        }
        XCTAssertFalse(session.modelContext.hasChanges)
        XCTAssertEqual(try journal.exportSnapshot(), beforeRead)
        try owner.invalidateAndReleaseWriter()
        writerReleased = true
    }

    struct FileFact: Equatable {
        let path: String
        let bytes: Data
    }

    enum FixtureError: Error { case invalid }

    @MainActor
    func makeLiveHarness(
        root: URL,
        name: String,
        base: Int,
        label: String,
        observedAt: Date,
        packetIDOverride: UUID? = nil,
        diagnostic: (@MainActor (String) -> Void)? = nil
    ) async throws -> LiveHarness {
        diagnostic?("support")
        let support = root.appendingPathComponent("\(name)-support", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        diagnostic?("bootstrap")
        let factory = StoreGenerationFactory(applicationSupportURL: support)
        let session = try factory.openOrBootstrapCurrent()
        let context = session.modelContext
        let pack = SignPack.illuminatedSignV1
        let siteID = uuid(base)
        let assetID = uuid(base + 1)
        diagnostic?("seed")
        let sessionCoordinator = try StoreSessionCoordinator(validatingSession: session)
        var writerReleased = false
        defer {
            if !writerReleased { try? sessionCoordinator.invalidateAndReleaseWriter() }
        }
        let placementMutationID = try MutationIDV1(rawValue: uuid(base + 70))
        _ = try sessionCoordinator.workspaceWriter.execute(.createFirstSign(.init(
            siteID: siteID,
            newSite: .init(id: siteID, label: "\(label) site", address: nil,
                           timeZoneID: "America/New_York"),
            assetID: assetID, assetLabel: label, packID: pack.packID,
            packSchemaVersion: pack.schemaVersion, packContentVersion: pack.contentVersion,
            createdAt: observedAt.addingTimeInterval(-9),
            initialPlacementMutationID: placementMutationID,
            initialPlacementEventID: uuid(base + 71),
            initialPhysicalEpisodeID: PhysicalPlacementEpisodeIDV1(rawValue: uuid(base + 72))
        )), mutationID: placementMutationID)
        let journal = try MutationJournalStoreV1(modelContext: context,
            identity: session.workspaceIdentity, generationID: session.generationID,
            allowStateBootstrap: false)
        var committedRevision = try journal.exportSnapshot().workspaceRevision
        XCTAssertFalse(context.hasChanges)
        XCTAssertGreaterThan(committedRevision, 0)
        func requireCommittedCapture() throws {
            XCTAssertFalse(context.hasChanges)
            let history = try journal.exportSnapshot()
            XCTAssertGreaterThan(history.workspaceRevision, committedRevision)
            committedRevision = history.workspaceRevision
        }

        diagnostic?("capture.configure")
        let profile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(package: pack)
        let dependencies = try sessionCoordinator.packageLifecycleDependencies(
            profileRegistry: WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile]))
        let coordinator = try CheckRunnerCoordinator(modelContext: context,
            packageLifecycleDependencies: dependencies, packageLifecycleProfile: profile)
        coordinator.configureCapture(generationRootURL: session.generationRootURL)
        diagnostic?("capture.begin")
        _ = try coordinator.beginCheck(
            assetID: assetID,
            timeZoneID: nil,
            isTimeZoneConfirmed: false,
            afterDarkAccepted: true,
            safePositionAccepted: true,
            observedAt: observedAt
        )
        try requireCommittedCapture()
        diagnostic?("wide.import")
        let wide = try await coordinator.importCandidate(
            assetID: assetID,
            sourceData: try makePNG(seed: UInt8(truncatingIfNeeded: base)),
            createdAt: observedAt.addingTimeInterval(1)
        )
        diagnostic?("wide.accept")
        _ = try await coordinator.accept(candidate: wide, assetID: assetID)
        try requireCommittedCapture()
        diagnostic?("close.import")
        let close = try await coordinator.importCandidate(
            assetID: assetID,
            sourceData: try makePNG(seed: UInt8(truncatingIfNeeded: base + 17)),
            createdAt: observedAt.addingTimeInterval(2)
        )
        diagnostic?("close.accept")
        _ = try await coordinator.accept(candidate: close, assetID: assetID)
        try requireCommittedCapture()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<EvidenceFile>()), 2)
        let packetID = packetIDOverride ?? uuid(base + 3)
        let rootID = uuid(base + 4)
        diagnostic?("finalize")
        let result = try await coordinator.finalize(
            assetID: assetID,
            selection: .noVisibleIssue,
            completedAt: observedAt.addingTimeInterval(5),
            snapshotCreatedAt: observedAt.addingTimeInterval(6),
            sourceApp: .init(build: "42", version: "4.0"),
            identifiers: .init(
                mutationID: uuid(base + 2),
                packetID: packetID,
                stableRootID: rootID,
                reportID: uuid(base + 5),
                issueID: nil
            )
        )
        try requireCommittedCapture()
        diagnostic?("delivery")
        guard case .ready = try coordinator.prepareReportDelivery(result: result) else {
            throw FixtureError.invalid
        }
        diagnostic?("packet.readback")
        let packet = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Packet>()).first
        )
        try sessionCoordinator.invalidateAndReleaseWriter()
        writerReleased = true
        return LiveHarness(
            support: support,
            factory: factory,
            session: session,
            packetID: packetID,
            rootID: rootID,
            packetCreatedAt: packet.createdAt
        )
    }

    @MainActor
    func exportPackage(
        _ harness: LiveHarness,
        root: URL,
        name: String,
        diagnostic: (@MainActor (String) -> Void)? = nil
    ) throws -> URL {
        diagnostic?("destination")
        let destination = root.appendingPathComponent("\(name)-export", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        diagnostic?("initialize")
        let exporter = BackupExportService(
            modelContext: harness.session.modelContext,
            generationRootURL: harness.session.generationRootURL,
            now: { Date(timeIntervalSince1970: 1_786_709_500) },
            appVersion: { "4.0" },
            appBuild: { "42" }
        )
        diagnostic?("prepare")
        let preview = try exporter.prepare()
        diagnostic?("write")
        return try exporter.export(previewID: preview.id, to: destination)
    }

    @MainActor
    func importPackage(
        _ package: URL,
        into session: StoreGenerationSession,
        stageID: UUID
    ) throws -> ValidatedV4BackupPackageV1 {
        try BackupImportService(
            generationRootURL: session.generationRootURL,
            makeUUID: { stageID },
            scopedAccess: .alreadyAuthorized
        ).stageAndValidate(selectedPackageURL: package)
    }

    func packet(
        id: UUID,
        root: UUID,
        currentRecord: UUID?,
        created: TimeInterval,
        deleted: TimeInterval? = nil
    ) -> V4BackupPacketDTO {
        V4BackupPacketDTO(
            id: id,
            schemaVersion: 1,
            stableRootID: root,
            currentRecordID: currentRecord,
            evaluationCounted: true,
            contentDeletedAt: deleted.map { Date(timeIntervalSince1970: $0) },
            createdAt: Date(timeIntervalSince1970: created)
        )
    }

    func makeRoot(_ name: String) throws -> URL {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "S6_5-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    func sequence(_ values: [UUID]) -> () -> UUID {
        var remaining = values
        return {
            guard !remaining.isEmpty else { return UUID() }
            return remaining.removeFirst()
        }
    }

    func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(
            format: "65000000-0000-0000-0000-%012d",
            suffix
        ))!
    }

    func fileTree(_ root: URL) throws -> [FileFact] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { throw FixtureError.invalid }
        var facts: [FileFact] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory != true else { continue }
            let relative = String(url.standardizedFileURL.path.dropFirst(
                root.standardizedFileURL.path.count + 1
            ))
            facts.append(FileFact(path: relative, bytes: try Data(contentsOf: url)))
        }
        return facts.sorted { $0.path < $1.path }
    }

    func makePNG(seed: UInt8) throws -> Data {
        let width = 48
        let height = 32
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = seed &+ UInt8(truncatingIfNeeded: index / 4)
            pixels[index + 1] = seed &+ 17
            pixels[index + 2] = seed &+ 43
            pixels[index + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: space,
                  bitmapInfo: CGBitmapInfo(
                      rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                  ),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else { throw FixtureError.invalid }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { throw FixtureError.invalid }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.invalid
        }
        return output as Data
    }

    @MainActor
    func XCTAssertThrowsErrorAsync(
        _ expression: () async throws -> Void,
        verify: (Error) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail("Expected error", file: file, line: line)
        } catch {
            verify(error)
        }
    }
}

extension S6_5ReplacementUnionTests {
    func testC21ClientCapabilityLifecycleAnchor() throws {
        XCTAssertEqual(ClientCapabilityProfileV1.schemaVersion, 1)
        XCTAssertEqual(ClientAdmissionV1.allCases.count, 5)
        XCTAssertEqual(PackageLifecycleOperationV1.allCases.count, 9)
        XCTAssertEqual(PersistentSchemaV20.models.count, 81)
        XCTAssertNoThrow(try V20ClientCapabilityImportBoundaryV1.validate(persistent: 20, records: 19))
    }
}

extension S6_5ReplacementUnionTests {
    func testV23P03C34PackageRouteUsesOneShellAndNoWriter() throws {
        let route = PackageSurfaceRouteV1(routeID: "c34.package", root: .assets, destination: .packageSurface, kind: .destination, startsAutomaticWork: false)
        let manifest = try PackageSurfaceManifestV1(packageID: "c34.package", routes: [route])
        let registry = try RouteRegistryV1(manifests: [manifest])
        let receipt = RouteConformanceReceiptV1(
            registry: registry,
            evidenceKind: .golden,
            observedShellCount: 1,
            observedParserCount: 1,
            observedMutationAuthorityCount: 0
        )
        try receipt.validate()
        XCTAssertEqual(receipt.roots, AppRootV1.frozenOrder)
        XCTAssertEqual(receipt.shellCount, 1)
        XCTAssertEqual(receipt.parserCount, 1)
        XCTAssertEqual(receipt.mutationAuthorityCount, 0)
    }
}

private extension S6_5ReplacementUnionTests {
    func c05Sequence(
        workspace: WorkspaceID,
        sequenceID: UUID,
        mutationID: UUID,
        revision: UInt64,
        predecessor: EvidenceSequenceReferenceV1? = nil
    ) throws -> EvidenceSequenceV1 {
        try EvidenceSequenceV1(
            sequenceID: sequenceID,
            workspaceID: workspace,
            target: try EvidenceAssociationTargetV1(
                workspaceID: workspace.rawValue.uuidString.lowercased(),
                kind: .finding,
                targetID: "finding.c05",
                targetRevision: 1
            ),
            policy: try EvidenceCurationPolicyV1(
                policyID: uuid(507),
                workspaceID: workspace
            ),
            orderedItems: [],
            predecessor: predecessor,
            revision: revision,
            mutationID: try MutationIDV1(rawValue: mutationID)
        )
    }

    func c05Records(sequences: [EvidenceSequenceV1] = []) -> V4BackupRecordsV1 {
        V4BackupRecordsV1(
            assets: [],
            evidenceFiles: [],
            issues: [],
            packets: [],
            recordsSchemaVersion: C05EvidenceMetadataBackupEnrollmentV1.recordsSchemaVersion,
            reports: [],
            sites: [],
            workflowRecords: [],
            evidenceSequenceRevisions: sequences
        )
    }
}

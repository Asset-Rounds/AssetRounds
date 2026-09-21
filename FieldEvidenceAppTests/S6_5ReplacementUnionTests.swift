import CoreGraphics
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
            diagnosticPhase = "restore.observation-schema-contract"
            let incomingRecords = try service.c55CurrentRecordsForTesting(
                in: incoming.session.modelContext)
            try assertObservationSchemaContract(service: service,
                value: XCTUnwrap(incomingRecords.workflowRecords.first))
            service.restorePhaseDiagnosticForTesting = { value in
                if value == "restore-error.recovery.begin", firstRecoveryOrigin == nil {
                    firstRecoveryOrigin = diagnosticPhase
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
            if let policyError = error as? ProtectedFilePolicyError,
               case .resourceValueMismatch = policyError {
                print("ReplacementUnionGolden.failure.protectedFileResourceValueMismatch")
            }
            throw originalError
        }
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

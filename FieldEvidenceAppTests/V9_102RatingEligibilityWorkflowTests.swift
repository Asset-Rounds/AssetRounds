import Foundation
import XCTest

@testable import FieldEvidenceApp

private enum C39 {
    static let now = Date(timeIntervalSince1970: 1_900_000_000)
    static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "C3900000-0000-4000-8000-%012x", n))!
    }
    static func digest(_ c: Character) -> String { String(repeating: String(c), count: 64) }
    static func mutation(_ n: Int) throws -> MutationIDV1 { try .init(rawValue: id(n)) }
    static func version(_ value: String = "2.3.0") throws -> RatingMarketingVersionV1 { try .init(value) }
    static func build(_ value: String = "230") throws -> RatingBuildVersionV1 { try .init(value) }

    static func completions(span: TimeInterval = 7 * 86_400,
                            end: Date = now) throws -> [RatingEligibleCompletionProjectionV1] {
        [
            .init(finalizationMutationID: try mutation(10), activitySeriesID: id(11),
                  completedAt: end.addingTimeInterval(-span), snapshotSHA256: digest("a")),
            .init(finalizationMutationID: try mutation(12), activitySeriesID: id(13),
                  completedAt: end.addingTimeInterval(-span / 2), snapshotSHA256: digest("b")),
            .init(finalizationMutationID: try mutation(14), activitySeriesID: id(15),
                  completedAt: end, snapshotSHA256: digest("c")),
        ]
    }

    static func stop(completions: [RatingEligibleCompletionProjectionV1],
                     at: Date = now, active: Set<RatingActiveContextV1> = [],
                     scene: Bool = true, later: Bool = true, event: Int = 20)
        -> RatingNaturalStopV1 {
        .init(eventID: id(event), successfullyRetrievedSnapshotSHA256: completions.last!.snapshotSHA256,
              occurredAt: at, isLaterVoluntaryReopen: later,
              activeContexts: active, activeSceneAvailable: scene)
    }

    static func attempt(slot: Int, version: String, reservedAt: Date) throws -> RatingRequestAttemptV1 {
        try .init(idempotencyKeySHA256: digest(Character(String(format: "%x", slot % 16))),
                  policySHA256: RatingEligibilityPolicyV1().policySHA256,
                  marketingVersion: try C39.version(version), buildVersion: build(), reservedAt: reservedAt,
                  nativeInvokedAt: reservedAt, disposition: .nativeRequestInvoked)
    }

    static func state(attempts: [RatingRequestAttemptV1], highWater: Date = now,
                      origin: RatingLedgerOriginV1 = .established) throws
        -> RatingRequestAttemptLedgerStateV1 {
        try .init(revision: 1, origin: origin, attempts: attempts, clockHighWatermarkUTC: highWater)
    }

    static func corpus() throws -> [String: Any] {
        let bundle = Bundle(for: V9_102RatingEligibilityWorkflowTests.self)
        let url = bundle.url(forResource: "V23P04C39RatingSupportWorkflowCorpusV1", withExtension: "json",
                             subdirectory: "Fixtures/V23/Feedback")
            ?? bundle.url(forResource: "V23P04C39RatingSupportWorkflowCorpusV1", withExtension: "json")
        guard let url, let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        else { throw RatingEligibilityFailureV1.invalidValue }
        return value
    }

    static func finalizedCandidate(slot: Int, v2: Bool = false,
                                   source: MutationSourceKindV1 = .localUser,
                                   evaluationCounted: Bool = true,
                                   completedAt: Date? = nil) throws
        -> RatingFinalizedActivityCandidateV1 {
        let workspace = WorkspaceID(rawValue: id(1_000 + slot))
        let assetID = id(1_100 + slot), recordID = id(1_200 + slot)
        let packetID = id(1_300 + slot), reportID = id(1_400 + slot)
        let rootID = id(1_500 + slot), snapshotID = "c39-snapshot-\(slot)"
        let workspaceToken = workspace.rawValue.uuidString.lowercased()
        let formats: [ReportProjectionFormatV1] = [.openJSON, .pdf, .structuredText]
        let section = try ReportSectionDefinitionV1(
            sectionID: "identity", version: 1, required: true, supportedFormats: formats,
            privacyClass: .mandatoryPublicTruth, requiresHeading: true,
            requiresTextAlternative: true, order: 0)
        let registry = try ReportSectionRegistryV1(
            registryID: "c39-registry", registryVersion: 1, sections: [section])
        let manifest = try ContractManifestV1(
            manifestID: "c39-manifest", manifestVersion: 1,
            codec: .init(codecVersion: 1),
            compatibility: .init(minimumReaderVersion: 1, maximumReaderVersion: 1,
                                 unknownObjectFields: .reject),
            objects: [try .init(typeID: "completed-snapshot", version: 1,
                                unknownFieldPolicy: .reject,
                                fields: [try .init(fieldID: "snapshot-id", jsonName: "snapshotID",
                                                   kind: .string, required: true,
                                                   maximumUTF8Bytes: 128)])],
            enums: [], reportSectionRegistry: registry)
        let layout = try ReportLayoutProfileV1(
            profileID: "c39-layout", profileRelease: 1, audience: .customerSafe,
            detail: .complete, sectionIDs: [section.sectionID], mediaLayout: .standardGrid,
            orientation: .portrait, localeIdentifier: "en_US", unitsProfileID: "units-si-v1",
            displayProfileID: "display-v1", registry: registry)
        let export = try ExportProfileV1(
            exportProfileID: "c39-export", exportProfileRelease: 1, formats: formats,
            packaging: .combined, privacyTransformID: "customer-safe-v1", maximumMediaItems: 1,
            maximumArchiveBytes: Int64(SnapshotProjectionLimitsV1.maximumProjectionBytes))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let binding = try FinalizedReportProfileBindingV1(
            workspaceID: workspaceToken, snapshotID: snapshotID, outputScopeID: "c39-output",
            reportProfileID: layout.profileID, reportProfileRelease: layout.profileRelease,
            reportProfileSHA256: KernelCanonicalHashV1.sha256(try encoder.encode(layout)),
            exportProfileID: export.exportProfileID, exportProfileRelease: export.exportProfileRelease,
            exportProfileSHA256: KernelCanonicalHashV1.sha256(try encoder.encode(export)),
            sectionRegistryID: registry.registryID, sectionRegistryVersion: registry.registryVersion,
            sectionRegistrySHA256: KernelCanonicalHashV1.sha256(try encoder.encode(registry)),
            contractManifestID: manifest.manifestID, contractManifestVersion: manifest.manifestVersion,
            contractManifestSHA256: KernelCanonicalHashV1.sha256(try encoder.encode(manifest)),
            sectionIDs: layout.sectionIDs, audience: .customerSafe, detail: .complete,
            privacyTransformID: export.privacyTransformID, localeIdentifier: layout.localeIdentifier,
            unitsProfileID: layout.unitsProfileID, displayProfileID: layout.displayProfileID,
            orientation: layout.orientation, mediaLayout: layout.mediaLayout,
            rendererVersion: ReportSemanticProjectorV1.rendererVersion,
            projectionVersion: "c39-rating-v1")
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let instant = completedAt ?? now.addingTimeInterval(TimeInterval(slot))
        let instantText = iso.string(from: instant)
        let activity = try CompletedActivitySnapshotPayloadV1(
            workspaceID: workspaceToken, snapshotID: snapshotID, snapshotRevision: 1,
            sourceActivityID: recordID.uuidString.lowercased(), sourceRevision: 1,
            reportID: reportID.uuidString.lowercased(), packageReleaseID: "c39-package-v1",
            generatedAt: instantText, completedAt: instantText, supersedesSnapshotID: nil,
            supersededSnapshotSHA256: nil, amendmentReason: nil, profileBinding: binding,
            serviceFacts: [], evidenceCards: [], limitations: ["System consideration is not a rating result."])
        let evidence: RatingCompletedActivitySnapshotEvidenceV1
        if v2 {
            let path = try LocationPathSnapshotV1(siteID: id(1_600 + slot), siteDisplay: "C39 site", nodes: [])
            let placement = try AssetPlacementEventV1(
                id: id(1_610 + slot), workspaceID: workspace, assetID: assetID,
                siteID: path.siteID, locationNodeID: nil, predecessorEventID: nil,
                source: .migratedBaseline, physicalEpisodeID: .init(rawValue: id(1_620 + slot)),
                continuity: .samePhysicalInstallation, pathSnapshot: path,
                mutationID: mutation(1_630 + slot), occurredAt: instant)
            let location = try CompletedLocationCompositionSnapshotV1.build(
                workspaceID: workspace, assetID: assetID, currentLocationPath: path,
                currentPlacementByAssetID: [assetID: placement], activeCompositionEdges: [],
                frozenAtRevision: 1)
            evidence = .v2(try CompletedActivitySnapshotV2.freezeOriginal(.init(
                activity: activity, assetID: assetID, locationComposition: location)))
        } else {
            evidence = .v1(try CompletedActivitySnapshotV1.freezeOriginal(activity))
        }
        let record = WorkflowRecordPayloadV1(
            id: recordID, schemaVersion: 1, assetID: assetID, packetID: packetID, issueID: nil,
            parentRecordID: nil, recordRevisionRootID: recordID, revisesRecordID: nil,
            evidenceSourceRecordID: nil, revisionKind: WorkflowRevisionKind.original.rawValue,
            stage: "check", state: WorkflowState.completed.rawValue, draftStepKey: nil,
            startedAt: instant.addingTimeInterval(-60), completedAt: instant, observedAtUTC: instant,
            timeZoneID: "UTC", utcOffsetMinutes: 0, localDate: "2030-03-17", localTime: "00:00:00",
            afterDarkAcknowledgementKey: nil, afterDarkAcknowledgementCopy: nil,
            afterDarkAcknowledgementVersion: nil, afterDarkAcknowledgementAccepted: false,
            safePositionAcknowledgementKey: nil, safePositionAcknowledgementCopy: nil,
            safePositionAcknowledgementVersion: nil, safePositionAcknowledgementAccepted: false,
            packID: "c39-pack", packSchemaVersion: 1, packContentVersion: 1,
            pdfTemplateID: "c39-pdf", pdfTemplateVersion: 1, outcomeKey: "completed",
            couldNotVerifyKey: nil, couldNotVerifyDisplaySnapshot: nil,
            couldNotVerifyRegistryVersion: nil, workPerformedLocalDate: nil,
            workDescription: nil, note: nil, finalizationMutationID: id(1_700 + slot))
        let packet = PacketPayloadV1(
            id: packetID, schemaVersion: 1, stableRootID: rootID, currentRecordID: recordID,
            evaluationCounted: evaluationCounted, contentDeletedAt: nil, createdAt: instant)
        let report = ReportPayloadV1(
            id: reportID, schemaVersion: 1, packetID: packetID, sourceRecordID: recordID,
            snapshotSchemaVersion: v2 ? 2 : 1, snapshotRelativePath: "snapshots/c39-\(slot).json",
            snapshotSHA256: evidence.snapshotSHA256, pdfState: ReportPDFState.pending.rawValue,
            pdfRelativePath: nil, pdfSHA256: nil, createdAt: instant, replacesReportID: nil)
        let mutationID = try MutationIDV1(rawValue: id(1_700 + slot))
        let command = FinalizeCheckMutationV1(
            finalizationMutationID: mutationID.rawValue, assetID: assetID, recordID: recordID,
            packetID: packetID, reportID: reportID, issueID: nil,
            semanticDigest: digest("9"), contentDigests: [])
        let identities = try [
            WorkspaceEntityRevisionV1(identity: .init(kind: .workflowRecord, id: recordID), revision: 0),
            WorkspaceEntityRevisionV1(identity: .init(kind: .packet, id: packetID), revision: 0),
            WorkspaceEntityRevisionV1(identity: .init(kind: .report, id: reportID), revision: 0),
        ]
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: workspace, generationID: id(1_800 + slot), writerInstanceID: id(1_810 + slot),
            workspaceRevision: 0, entityRevisions: identities)
        let replica = ReplicaID(rawValue: id(1_820 + slot))
        let envelope = try MutationEnvelopeV1(
            request: .init(mutationID: mutationID, expectedRevision: expected,
                           command: .finalizeCheck(command)),
            identity: try .init(workspaceID: workspace, replicaID: replica), sourceKind: source)
        let posts: [MutationPostImageV1] = [
            .workflowRecord(id: recordID, revision: 1, semanticSHA256: digest("1")),
            .packet(id: packetID, revision: 1, semanticSHA256: digest("2")),
            .report(id: reportID, revision: 1, semanticSHA256: digest("3")),
        ]
        let resulting = try WorkspaceExpectedRevisionV1(
            workspaceID: workspace, generationID: expected.generationID,
            writerInstanceID: expected.writerInstanceID, workspaceRevision: 1,
            entityRevisions: try identities.map { try .init(identity: $0.identity, revision: 1) })
        let receipt = try MutationReceiptV1(
            identity: .init(workspaceID: workspace, replicaID: replica, localSequence: 1),
            envelope: envelope, resultingRevision: try .init(resulting), postImages: posts,
            committedAt: instant)
        return RatingFinalizedActivityCandidateV1(
            envelope: envelope, receipt: receipt, record: record, packet: packet, report: report,
            completedSnapshot: evidence, practiceProvenance: nil)
    }
}

private struct C39Clock: ApplicationClock { let value: Date; func now() -> Date { value } }

@MainActor private final class C39InvocationOrderProbe {
    private(set) var reservationPersisted = false
    func markReservationPersisted() { reservationPersisted = true }
}

private actor C39Store: RatingEligibilityStoreV1 {
    private var result: RatingLedgerLoadResultV1
    private var receipts: [UUID: RatingLedgerPersistenceReceiptV1] = [:]
    private(set) var writeCount = 0
    var failAfterNextCommit = false
    private let orderProbe: C39InvocationOrderProbe?

    init(_ result: RatingLedgerLoadResultV1 = .absentFreshInstall,
         orderProbe: C39InvocationOrderProbe? = nil) {
        self.result = result
        self.orderProbe = orderProbe
    }
    func load() async throws -> RatingLedgerLoadResultV1 { result }
    func compareAndSwap(operationID: UUID, expectedRevision: UInt64?,
                        successor: RatingRequestAttemptLedgerStateV1) async throws
        -> RatingLedgerPersistenceReceiptV1 {
        if let receipt = receipts[operationID] {
            guard receipt.stateSHA256 == successor.stateSHA256 else {
                throw RatingEligibilityFailureV1.divergentReplay
            }
            return .init(operationID: receipt.operationID, expectedRevision: receipt.expectedRevision,
                         resultingRevision: receipt.resultingRevision, stateSHA256: receipt.stateSHA256,
                         disposition: .idempotentReplay)
        }
        let receipt = RatingLedgerPersistenceReceiptV1(
            operationID: operationID, expectedRevision: expectedRevision,
            resultingRevision: successor.revision, stateSHA256: successor.stateSHA256,
            disposition: .committed)
        result = .current(successor); receipts[operationID] = receipt; writeCount += 1
        if let orderProbe { await orderProbe.markReservationPersisted() }
        if failAfterNextCommit { failAfterNextCommit = false; throw RatingEligibilityFailureV1.storageUnavailable }
        return receipt
    }
    func enablePostCommitFailure() { failAfterNextCommit = true }
    func snapshot() -> (RatingLedgerLoadResultV1, Int) { (result, writeCount) }
}

@MainActor private final class C39Adapter: RatingRequestAdapterV1 {
    var availability: RatingNativeRequestAvailabilityV1 = .available
    var loseAvailabilityDuringPreparation = false
    private let orderProbe: C39InvocationOrderProbe?
    private(set) var preparationCount = 0
    private(set) var callCount = 0

    init(orderProbe: C39InvocationOrderProbe? = nil) { self.orderProbe = orderProbe }

    func prepareRequest() -> RatingNativeRequestPreparationV1? {
        preparationCount += 1
        if loseAvailabilityDuringPreparation {
            availability = .sceneUnavailable
            return nil
        }
        guard availability == .available else { return nil }
        return .init { [weak self] in
            guard let self else { return .systemConsiderationRequested }
            self.callCount += 1
            XCTAssertEqual(self.orderProbe?.reservationPersisted, true)
            return .systemConsiderationRequested
        }
    }
}

final class V9_102RatingEligibilityWorkflowTests: XCTestCase {
    @MainActor
    func testV23P04C39G01FinalizedValueReopenRequestsSystemConsiderationExactlyOnce() async throws {
        let corpus = try C39.corpus()
        XCTAssertEqual((corpus["scenarioIDs"] as? [String])?.count, 5)
        let claims = try XCTUnwrap(corpus["claims"] as? [String: Bool])
        XCTAssertTrue(claims.values.allSatisfy { !$0 })
        let orderProbe = C39InvocationOrderProbe()
        let store = C39Store(orderProbe: orderProbe)
        let adapter = C39Adapter(orderProbe: orderProbe)
        let coordinator = try RatingEligibilityCoordinatorV1(
            store: store, nativeRequest: adapter, clock: C39Clock(value: C39.now))
        let realCandidates = [
            try C39.finalizedCandidate(
                slot: 1, completedAt: C39.now.addingTimeInterval(-7 * 86_400)),
            try C39.finalizedCandidate(
                slot: 2, v2: true, completedAt: C39.now.addingTimeInterval(-3.5 * 86_400)),
            try C39.finalizedCandidate(slot: 3, completedAt: C39.now),
        ]
        let completions = try realCandidates.map { candidate in
            guard case let .eligibleRuntimeProjection(projection) =
                    coordinator.recordEligibleCompletion(candidate) else {
                throw RatingEligibilityFailureV1.invalidCandidate
            }
            return projection
        }
        XCTAssertEqual(Set(completions.map(\.activitySeriesID)).count, 3)
        XCTAssertEqual(completions.map(\.completedAt).max()!.timeIntervalSince(
            completions.map(\.completedAt).min()!), 7 * 86_400)
        let projection = await coordinator.project(
            completions: completions, marketingVersion: C39.version(), buildVersion: C39.build(),
            naturalStop: C39.stop(completions: completions))
        XCTAssertTrue(projection.eligible)
        XCTAssertTrue(projection.supportVisible && projection.recoveryVisible)
        guard case let .nativeRequestInvoked(attempt) = try await coordinator.requestIfEligible(
            completions: completions, marketingVersion: C39.version(), buildVersion: C39.build(),
            naturalStop: C39.stop(completions: completions),
            reservationOperationID: C39.id(21), invocationStatusOperationID: C39.id(22))
        else { return XCTFail("Expected one native consideration request") }
        XCTAssertEqual(attempt.disposition, .nativeRequestInvoked)
        XCTAssertEqual(adapter.preparationCount, 1)
        XCTAssertEqual(adapter.callCount, 1)
        let persisted = await store.snapshot()
        XCTAssertEqual(persisted.1, 2)
        guard case let .current(state) = persisted.0 else { return XCTFail("Expected local ledger") }
        let ledgerText = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        for forbidden in ["workspaceID", "activitySeriesID", "receipt", "snapshot", "reportID",
                          "reviewText", "star", "promptDisplayed", "contact"] {
            XCTAssertFalse(ledgerText.localizedCaseInsensitiveContains(forbidden))
        }
        XCTAssertFalse(RatingEligibilityPrivacyBoundaryV1.persistedWorkspaceIDs)
        XCTAssertFalse(RatingEligibilityPrivacyBoundaryV1.persistedActivitySeriesIDs)
        XCTAssertFalse(RatingEligibilityPrivacyBoundaryV1.persistedReceiptSnapshotOrReportIDs)
        XCTAssertFalse(RatingEligibilityPrivacyBoundaryV1.telemetryOrMarketingWrites)
        XCTAssertEqual(try RateAppLinkV1.available(appStoreID: "1234567890"),
                       .available(URL(string: "https://apps.apple.com/app/id1234567890?action=write-review")!))
    }

    @MainActor
    func testV23P04C39A01SevenOneTwentyAndRollingYearBoundariesAreExact() async throws {
        for (span, eligible) in [(7 * 86_400.0 - 1, false), (7 * 86_400.0, true)] {
            let values = try C39.completions(span: span)
            let coordinator = try RatingEligibilityCoordinatorV1(
                store: C39Store(), nativeRequest: C39Adapter(), clock: C39Clock(value: C39.now))
            let projection = await coordinator.project(
                completions: values, marketingVersion: C39.version(), buildVersion: C39.build(),
                naturalStop: C39.stop(completions: values))
            XCTAssertEqual(projection.eligible, eligible)
        }
        for (age, eligible) in [(120 * 86_400.0 - 1, false), (120 * 86_400.0, true)] {
            let old = try C39.attempt(slot: 1, version: "2.2.0", reservedAt: C39.now.addingTimeInterval(-age))
            let coordinator = try RatingEligibilityCoordinatorV1(
                store: C39Store(.current(try C39.state(attempts: [old]))),
                nativeRequest: C39Adapter(), clock: C39Clock(value: C39.now))
            let values = try C39.completions()
            let projection = await coordinator.project(
                completions: values, marketingVersion: C39.version(), buildVersion: C39.build(),
                naturalStop: C39.stop(completions: values))
            XCTAssertEqual(projection.eligible, eligible)
        }
        for (age, eligible) in [(365 * 86_400.0 - 1, false), (365 * 86_400.0, true)] {
            let first = try C39.attempt(slot: 2, version: "2.1.0", reservedAt: C39.now.addingTimeInterval(-age))
            let second = try C39.attempt(slot: 3, version: "2.2.0", reservedAt: C39.now.addingTimeInterval(-200 * 86_400))
            let coordinator = try RatingEligibilityCoordinatorV1(
                store: C39Store(.current(try C39.state(attempts: [first, second]))),
                nativeRequest: C39Adapter(), clock: C39Clock(value: C39.now))
            let values = try C39.completions()
            let projection = await coordinator.project(
                completions: values, marketingVersion: C39.version(), buildVersion: C39.build(),
                naturalStop: C39.stop(completions: values))
            XCTAssertEqual(projection.eligible, eligible)
        }
        let sceneAdapter = C39Adapter(); sceneAdapter.availability = .sceneUnavailable
        let sceneStore = C39Store(); let values = try C39.completions()
        let scene = try RatingEligibilityCoordinatorV1(
            store: sceneStore, nativeRequest: sceneAdapter, clock: C39Clock(value: C39.now))
        guard case let .ineligible(value) = try await scene.requestIfEligible(
            completions: values, marketingVersion: C39.version(), buildVersion: C39.build(),
            naturalStop: C39.stop(completions: values, scene: false),
            reservationOperationID: C39.id(23), invocationStatusOperationID: C39.id(24))
        else { return XCTFail("Expected unavailable scene") }
        XCTAssertTrue(value.reasons.contains(.sceneUnavailable)); XCTAssertEqual(sceneAdapter.callCount, 0)
        let sceneSnapshot = await sceneStore.snapshot()
        XCTAssertEqual(sceneSnapshot.1, 0)

        let changingAdapter = C39Adapter()
        changingAdapter.loseAvailabilityDuringPreparation = true
        let changingStore = C39Store()
        let changing = try RatingEligibilityCoordinatorV1(
            store: changingStore, nativeRequest: changingAdapter, clock: C39Clock(value: C39.now))
        guard case let .ineligible(changed) = try await changing.requestIfEligible(
            completions: values, marketingVersion: C39.version(), buildVersion: C39.build(),
            naturalStop: C39.stop(completions: values, event: 25),
            reservationOperationID: C39.id(26), invocationStatusOperationID: C39.id(27))
        else { return XCTFail("Expected preparation loss to fail closed") }
        XCTAssertEqual(changed.reasons, [.sceneUnavailable])
        XCTAssertEqual(changingAdapter.preparationCount, 1)
        XCTAssertEqual(changingAdapter.callCount, 0)
        let changingSnapshot = await changingStore.snapshot()
        XCTAssertEqual(changingSnapshot.1, 0)
    }

    @MainActor
    func testV23P04C39H01ExclusionsContextsAndHostileLedgersFailClosedWithoutEffects() async throws {
        let fixture = try C39.corpus()
        XCTAssertEqual((fixture["excludedCompletionCases"] as? [String])?.count, 15)
        XCTAssertEqual(Set((fixture["activeContextSuppressions"] as? [String]) ?? []),
                       Set(RatingActiveContextV1.allCases.map(\.rawValue)))
        let duplicateSeries = try C39.completions().map {
            RatingEligibleCompletionProjectionV1(finalizationMutationID: $0.finalizationMutationID,
                activitySeriesID: C39.id(99), completedAt: $0.completedAt, snapshotSHA256: $0.snapshotSHA256)
        }
        for context in RatingActiveContextV1.allCases {
            let store = C39Store(); let adapter = C39Adapter()
            let coordinator = try RatingEligibilityCoordinatorV1(
                store: store, nativeRequest: adapter, clock: C39Clock(value: C39.now))
            let projection = await coordinator.project(
                completions: try C39.completions(), marketingVersion: C39.version(), buildVersion: C39.build(),
                naturalStop: C39.stop(completions: try C39.completions(), active: [context]))
            XCTAssertTrue(projection.reasons.contains(.activeContext)); XCTAssertEqual(adapter.callCount, 0)
            let storeSnapshot = await store.snapshot()
            XCTAssertEqual(storeSnapshot.1, 0)
        }
        let duplicateCoordinator = try RatingEligibilityCoordinatorV1(
            store: C39Store(), nativeRequest: C39Adapter(), clock: C39Clock(value: C39.now))
        let duplicateProjection = await duplicateCoordinator.project(
            completions: duplicateSeries, marketingVersion: C39.version(), buildVersion: C39.build(),
            naturalStop: C39.stop(completions: duplicateSeries))
        XCTAssertTrue(duplicateProjection.reasons.contains(.insufficientDistinctSeries))
        XCTAssertEqual(duplicateCoordinator.recordEligibleCompletion(
            try C39.finalizedCandidate(slot: 31, source: .importedHistory)), .excluded)
        XCTAssertEqual(duplicateCoordinator.recordEligibleCompletion(
            try C39.finalizedCandidate(slot: 32, evaluationCounted: false)), .excluded)
        for (loaded, reason) in [(RatingLedgerLoadResultV1.corrupt, RatingEligibilityReasonV1.ledgerCorrupt),
                                 (.futureVersion, .ledgerFutureVersion), (.migrationFailed, .ledgerMigrationFailed)] {
            let adapter = C39Adapter(); let values = try C39.completions()
            let coordinator = try RatingEligibilityCoordinatorV1(
                store: C39Store(loaded), nativeRequest: adapter, clock: C39Clock(value: C39.now))
            let projection = await coordinator.project(
                completions: values, marketingVersion: C39.version(), buildVersion: C39.build(),
                naturalStop: C39.stop(completions: values))
            XCTAssertTrue(projection.reasons.contains(reason))
            XCTAssertEqual(adapter.callCount, 0)
        }
        let rollbackAdapter = C39Adapter()
        let rollbackStore = C39Store(.current(try C39.state(
            attempts: [], highWater: C39.now.addingTimeInterval(1))))
        let rollbackCoordinator = try RatingEligibilityCoordinatorV1(
            store: rollbackStore, nativeRequest: rollbackAdapter, clock: C39Clock(value: C39.now))
        let rollbackProjection = await rollbackCoordinator.project(
            completions: try C39.completions(), marketingVersion: C39.version(), buildVersion: C39.build(),
            naturalStop: C39.stop(completions: try C39.completions()))
        XCTAssertTrue(rollbackProjection.reasons.contains(.clockRollbackDetected))
        XCTAssertEqual(rollbackAdapter.callCount, 0)
        let rollbackSnapshot = await rollbackStore.snapshot()
        XCTAssertEqual(rollbackSnapshot.1, 0)
        XCTAssertThrowsError(try RatingMarketingVersionV1("2.beta"))
        XCTAssertThrowsError(try RateAppLinkV1.available(appStoreID: "unverified"))
        let disabledReceipt = try TypedAvailabilityAndFallbackReceiptV1(
            candidateHead: String(repeating: "d", count: 40),
            candidateTree: String(repeating: "e", count: 40),
            providerID: "APP_STORE_RATING_LINK", providerSliceDigest: C39.digest("f"),
            consumerID: "C39_SETTINGS_RATE_LINK", capabilityID: .filesAndShare,
            availabilityReason: .unsupportedOSOrDevice, mandatoryCoreComplete: true,
            visibleFallback: .saveLocally, persistenceDisposition: .noCanonicalEffectUntilAcceptance,
            dataDisposition: .priorHistoryPreserved, reentryTrigger: .capabilityStateChanged,
            localizedVisibleStateKey: "rating.link.disabled",
            localizedVisibleCopyKey: "rating.link.unavailable",
            localizedNextActionKey: "support.contact",
            fallbackTestArtifactIDs: ["V23-P04-C39-H01-SUPPORT"],
            evidenceArtifactIDs: ["V23-P04-C39-H01-RATE-LINK"], zeroUnsupportedPublicClaim: true
        )
        XCTAssertEqual(RateAppLinkV1.disabledUnverifiedAppStoreID(disabledReceipt),
                       .disabledUnverifiedAppStoreID(disabledReceipt))
    }

    @MainActor
    func testV23P04C39I01ReservedBeforeCallKillRelaunchAndDuplicateInvokeAtMostOnce() async throws {
        let values = try C39.completions(); let store = C39Store(); let adapter = C39Adapter()
        await store.enablePostCommitFailure()
        let coordinator = try RatingEligibilityCoordinatorV1(
            store: store, nativeRequest: adapter, clock: C39Clock(value: C39.now))
        await XCTAssertThrowsErrorAsyncC39 {
            _ = try await coordinator.requestIfEligible(
                completions: values, marketingVersion: C39.version(), buildVersion: C39.build(),
                naturalStop: C39.stop(completions: values, event: 80),
                reservationOperationID: C39.id(81), invocationStatusOperationID: C39.id(82))
        }
        XCTAssertEqual(adapter.callCount, 0)
        var storeSnapshot = await store.snapshot()
        XCTAssertEqual(storeSnapshot.1, 1)
        let relaunched = try RatingEligibilityCoordinatorV1(
            store: store, nativeRequest: adapter, clock: C39Clock(value: C39.now))
        let replay = try await relaunched.requestIfEligible(
            completions: values, marketingVersion: C39.version(), buildVersion: C39.build(),
            naturalStop: C39.stop(completions: values, event: 80),
            reservationOperationID: C39.id(81), invocationStatusOperationID: C39.id(82))
        guard case .duplicateConservativeAttempt = replay else {
            return XCTFail("Expected conservative duplicate adoption")
        }
        XCTAssertEqual(adapter.preparationCount, 1)
        XCTAssertEqual(adapter.callCount, 0)
        storeSnapshot = await store.snapshot()
        XCTAssertEqual(storeSnapshot.1, 1)
    }

    @MainActor
    func testV23P04C39R01ResetEraseCooldownAndFreshInstallReearnDeterministically() async throws {
        let values = try C39.completions(); let old = try C39.attempt(
            slot: 9, version: "2.2.0", reservedAt: C39.now.addingTimeInterval(-200 * 86_400))
        let store = C39Store(.current(try C39.state(attempts: [old])))
        let adapter = C39Adapter()
        let coordinator = try RatingEligibilityCoordinatorV1(
            store: store, nativeRequest: adapter, clock: C39Clock(value: C39.now))
        XCTAssertEqual(coordinator.applySettingsReset(), .preserved)
        var storeSnapshot = await store.snapshot()
        XCTAssertEqual(storeSnapshot.1, 0)
        let erased = try await coordinator.applyCompletedErase(eraseOperationID: C39.id(90), erasedAt: C39.now)
        XCTAssertEqual(erased.suppressUntil, C39.now.addingTimeInterval(365 * 86_400))
        storeSnapshot = await store.snapshot()
        guard case let .current(erasedState) = storeSnapshot.0,
              case .erasedCooldown = erasedState.origin else { return XCTFail("Expected erased cooldown") }
        XCTAssertTrue(erasedState.attempts.isEmpty)
        for (offset, eligible) in [(365 * 86_400.0 - 1, false), (365 * 86_400.0, true)] {
            let at = C39.now.addingTimeInterval(offset)
            let c = try RatingEligibilityCoordinatorV1(
                store: store, nativeRequest: adapter, clock: C39Clock(value: at))
            let projection = await c.project(
                completions: values, marketingVersion: C39.version("3.0.0"), buildVersion: C39.build("300"),
                naturalStop: C39.stop(completions: values, at: at, event: Int(offset)))
            XCTAssertEqual(projection.eligible, eligible)
        }
        let fresh = try RatingEligibilityCoordinatorV1(
            store: C39Store(), nativeRequest: C39Adapter(), clock: C39Clock(value: C39.now))
        let insufficient = await fresh.project(
            completions: Array(values.prefix(2)), marketingVersion: C39.version(), buildVersion: C39.build(),
            naturalStop: C39.stop(completions: values))
        XCTAssertFalse(insufficient.eligible)
        let eligible = await fresh.project(
            completions: values, marketingVersion: C39.version(), buildVersion: C39.build(),
            naturalStop: C39.stop(completions: values))
        XCTAssertTrue(eligible.eligible)
        XCTAssertFalse(RatingEligibilityPrivacyBoundaryV1.eraseCooldownContainsCustomerData)
        XCTAssertFalse(RatingEligibilityPrivacyBoundaryV1.includedInWorkspaceBackupExportSearchOrDiagnostics)
    }
}

private func XCTAssertThrowsErrorAsyncC39(_ operation: () async throws -> Void) async {
    do { try await operation(); XCTFail("Expected error") } catch {}
}

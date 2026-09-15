import Combine
import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

final class V23ProductionMyDayPresentationTests: XCTestCase {
    @MainActor
    func testProductionStartupPublishesLiveMyDaySourcesWithoutCanonicalWrites() async throws {
        let fixture = try await makeFixture("live-source")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        guard case .ready(let coordinator, _, _) = fixture.router.route else {
            return XCTFail("Production startup did not publish its actual store coordinator")
        }
        let evaluatedAt = Date(timeIntervalSince1970: 1_800_200_000)
        let checkpoint = try makeCheckpoint(workspaceID: coordinator.workspaceID,
                                            updatedAt: evaluatedAt)
        coordinator.modelContext.insert(try FieldDraftCheckpointRow(checkpoint))
        try coordinator.modelContext.save()
        let beforeRevision = try coordinator.workspaceWriter.currentRevision()
        let beforeCount = try coordinator.modelContext.fetchCount(
            FetchDescriptor<FieldDraftCheckpointRow>())
        XCTAssertEqual(try coordinator.modelContext.fetchCount(
            FetchDescriptor<MyDayPlanRowV1>()), 0)
        XCTAssertEqual(try coordinator.modelContext.fetchCount(
            FetchDescriptor<MyDayCarryoverReceiptRowV1>()), 0)

        let snapshot = try await access.snapshot(evaluatedAt: evaluatedAt)

        XCTAssertEqual(snapshot.workspaceID, coordinator.workspaceID)
        XCTAssertEqual(snapshot.evaluatedAt, evaluatedAt)
        XCTAssertEqual(snapshot.sources.count, 1)
        XCTAssertEqual(snapshot.eligibleReferences.count, 1)
        guard case let .resumableDraft(workspaceID, draftID, revision,
                                       checkpointSHA256, anchor) = snapshot.sources[0].reference else {
            return XCTFail("Expected the actual persisted draft source")
        }
        XCTAssertEqual(workspaceID, coordinator.workspaceID)
        XCTAssertEqual(draftID, checkpoint.draftID)
        XCTAssertEqual(revision, checkpoint.draftRevision)
        XCTAssertEqual(checkpointSHA256, checkpoint.checkpointSHA256)
        XCTAssertEqual(anchor, checkpoint.resumeAnchor)
        XCTAssertEqual(snapshot.sources[0].state, .draft)
        XCTAssertEqual(snapshot.readinessAssessments.count, 1)
        XCTAssertEqual(snapshot.readinessAssessments[0].reference,
                       snapshot.sources[0].reference)
        XCTAssertEqual(snapshot.readinessAssessments[0].assessment, .notAssessed)
        XCTAssertEqual(snapshot.readinessAssessments[0].assessment.readiness,
                       .unavailable)
        XCTAssertEqual(try coordinator.workspaceWriter.currentRevision(), beforeRevision)
        XCTAssertEqual(try coordinator.modelContext.fetchCount(
            FetchDescriptor<FieldDraftCheckpointRow>()), beforeCount)
        XCTAssertEqual(try coordinator.modelContext.fetchCount(
            FetchDescriptor<MyDayPlanRowV1>()), 0)
        XCTAssertEqual(try coordinator.modelContext.fetchCount(
            FetchDescriptor<MyDayCarryoverReceiptRowV1>()), 0)
        XCTAssertFalse(coordinator.modelContext.hasChanges)
    }

    @MainActor
    func testCoverImmediatelyDeniesOldMyDayAccessAndForegroundPublishesFreshAccess() async throws {
        let fixture = try await makeFixture("cover")
        defer { fixture.cleanUp() }
        let original = try XCTUnwrap(fixture.presentation.myDayAccess)
        let evaluatedAt = Date(timeIntervalSince1970: 1_800_200_100)
        _ = try await original.snapshot(evaluatedAt: evaluatedAt)

        fixture.presentation.receive(.sceneInactive)
        XCTAssertNil(fixture.presentation.myDayAccess)
        do {
            _ = try await original.snapshot(evaluatedAt: evaluatedAt)
            XCTFail("The synchronously covered publication must deny its retained My Day access")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }

        let republished = expectation(description: "Foreground publishes fresh My Day access")
        let observation = fixture.presentation.$permitsContentPresentation
            .filter { $0 }.prefix(1).sink { _ in republished.fulfill() }
        fixture.presentation.receive(.sceneActive)
        await fulfillment(of: [republished], timeout: 30)
        observation.cancel()
        let fresh = try XCTUnwrap(fixture.presentation.myDayAccess)
        _ = try await fresh.snapshot(evaluatedAt: evaluatedAt)
        do {
            _ = try await original.snapshot(evaluatedAt: evaluatedAt)
            XCTFail("Foreground republication must not revive the old My Day access")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
    }

    @MainActor
    func testCoverDuringSnapshotPreventsTheMaterializedSourceFromPublishing() async throws {
        let fixture = try await makeFixture("in-flight-cover")
        defer { fixture.cleanUp() }
        let original = try XCTUnwrap(fixture.presentation.myDayAccess)
        let evaluatedAt = Date(timeIntervalSince1970: 1_800_200_200)
        #if DEBUG
        original.setAfterSourceMaterializationForTesting {
            fixture.presentation.receive(.sceneInactive)
        }
        do {
            _ = try await original.snapshot(evaluatedAt: evaluatedAt)
            XCTFail("A snapshot materialized under the privacy cover must not escape")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
        original.setAfterSourceMaterializationForTesting(nil)
        XCTAssertFalse(fixture.presentation.permitsContentPresentation)
        XCTAssertNil(fixture.presentation.myDayAccess)
        do {
            _ = try await original.snapshot(evaluatedAt: evaluatedAt)
            XCTFail("The covered publication must remain denied")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
        #else
        throw XCTSkip("Publication fault injection is DEBUG-only")
        #endif
    }

    @MainActor
    func testActualCoordinatorSessionReplacementMakesPublishedProviderInaccessible() async throws {
        let fixture = try await makeFixture("session-replacement")
        defer { fixture.cleanUp() }
        let access = try XCTUnwrap(fixture.presentation.myDayAccess)
        guard case .ready(let coordinator, _, _) = fixture.router.route else {
            return XCTFail("Production startup did not publish its actual store coordinator")
        }
        let replacement = try StoreGenerationFactory(
            applicationSupportURL: fixture.support).openOrBootstrapCurrent()
        try coordinator.activateValidating(session: replacement)

        do {
            _ = try await access.snapshot(
                evaluatedAt: Date(timeIntervalSince1970: 1_800_200_300))
            XCTFail("A provider bound to the replaced coordinator session must fail closed")
        } catch {
            XCTAssertEqual(error as? MyDaySourceReadFailureV1, .sessionChanged)
        }
    }

    @MainActor
    private func makeFixture(_ name: String) async throws
        -> V23ProductionMyDayPresentationHarness {
        try await V23ProductionMyDayPresentationHarness.start(
            testCase: self,
            name: name
        )
    }

    private func makeCheckpoint(workspaceID: WorkspaceID,
                                updatedAt: Date) throws -> FieldDraftCheckpointV1 {
        try FieldDraftCheckpointV1(
            draftID: UUID(),
            workspaceID: workspaceID,
            scope: .init(scopeKind: "V23_PRODUCTION_MY_DAY",
                         stableComponentIDs: ["live-draft"]),
            purpose: .assetFieldEdit,
            codec: .init(codecID: "V23_PRODUCTION_MY_DAY",
                         codecVersion: 1,
                         releaseSHA256: String(repeating: "a", count: 64)),
            baseCanonicalRevision: 0,
            draftRevision: 1,
            payloadData: Data("production-my-day-live-source".utf8),
            stageIDs: [],
            resumeAnchor: .init(sectionID: "my-day"),
            state: .active,
            updatedAt: updatedAt,
            mutationID: try MutationIDV1(rawValue: UUID())
        )
    }
}

/// Shared genuine production startup for the My Day and four-root host tests.
/// It contains only test ownership and the real objects published by startup.
@MainActor
struct V23ProductionMyDayPresentationHarness {
    let suiteName: String
    let defaults: UserDefaults
    let root: URL
    let support: URL
    let router: StartupRouter
    let session: ProductionAppAccessSessionV1
    let presentation: AppAccessPresentationV1
    let coordinator: StoreSessionCoordinator
    let diagnostics: DiagnosticsStore

    static func start(testCase: XCTestCase, name: String) async throws -> Self {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let suiteName = "V23.ProductionMyDay.\(name).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-ProductionMyDay-\(name)-\(UUID().uuidString)")
        let support = root.appendingPathComponent("Library/Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Library/Caches", isDirectory: true),
            withIntermediateDirectories: true)
        let router = StartupRouter(applicationSupportURL: support)
        let session: ProductionAppAccessSessionV1
        do {
            session = try await ProductionCompositionRoot.makeAppAccessSession(
                applicationSupportURL: support,
                startupRouter: router,
                defaults: defaults,
                authenticationClient: V23ProductionMyDayAuthentication(),
                notificationSystem: V23ProductionMyDayNotificationSystem()
            )
        } catch {
            let value = error as NSError
            let elapsed = (DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
            print("V23 production-startup failure phase=make-session elapsedMs=\(elapsed) type=\(String(reflecting: type(of: error))) domain=\(value.domain) code=\(value.code)")
            throw error
        }
        let presentation = AppAccessPresentationV1(
            startupRouter: router,
            sessionFactory: { session }
        )
        XCTAssertNil(presentation.myDayAccess)
        let published = testCase.expectation(
            description: "Production startup publishes My Day access"
        )
        let observation = presentation.$permitsContentPresentation
            .filter { $0 }.prefix(1).sink { _ in published.fulfill() }
        await presentation.bootstrapIfNeeded()
        logUnpublishedStartup(presentation, router: router, phase: "after-bootstrap", startedAt: startedAt)
        await testCase.fulfillment(of: [published], timeout: 30)
        observation.cancel()
        logUnpublishedStartup(presentation, router: router, phase: "after-publication-wait", startedAt: startedAt)
        XCTAssertTrue(presentation.permitsContentPresentation)
        guard case .ready(let coordinator, let diagnostics, _) = router.route else {
            throw AppAccessContractFailureV1.configurationUnknown
        }
        return .init(suiteName: suiteName, defaults: defaults, root: root, support: support,
                     router: router, session: session, presentation: presentation,
                     coordinator: coordinator, diagnostics: diagnostics)
    }

    private static func logUnpublishedStartup(
        _ presentation: AppAccessPresentationV1, router: StartupRouter,
        phase: String, startedAt: UInt64
    ) {
        guard !presentation.permitsContentPresentation else { return }
        let failure: String
        switch presentation.failure {
        case .none: failure = "none"
        case .some(.bootstrap): failure = "bootstrap"
        case .some(.authentication(_)): failure = "authentication"
        case .some(.configuration): failure = "configuration"
        case .some(.startup): failure = "startup"
        case .some(.lifecycle(_)): failure = "lifecycle"
        }
        let elapsed = (DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
#if DEBUG
        let runtimeFacts: String
        if let observation = router.runtimeObservation {
            let end = observation.endedAtUptimeNanoseconds
            let phaseElapsed = ((end ?? DispatchTime.now().uptimeNanoseconds)
                - observation.startedAtUptimeNanoseconds) / 1_000_000
            runtimeFacts = " startupPhase=\(observation.phase.rawValue)"
                + " startupPhaseStartedAt=\(observation.startedAtUptimeNanoseconds)"
                + " startupPhaseEndedAt=\(String(describing: end))"
                + " startupPhaseElapsedMs=\(phaseElapsed)"
        } else {
            runtimeFacts = " startupPhase=none"
        }
#else
        let runtimeFacts = ""
#endif
        print("V23 production-startup unpublished phase=\(phase) elapsedMs=\(elapsed) route=\(router.recoveryBootstrapState) failure=\(failure) busy=\(presentation.isBusy) enabled=\(String(describing: presentation.settingIsEnabled)) myDayAccess=\(presentation.myDayAccess != nil)\(runtimeFacts)")
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
        // This harness still owns the live SwiftData coordinator and container.
        // Unlinking its store here can mask the test result with SQLite and
        // lease failures. The disposable hosted Simulator owns this temp root.
    }
}

private actor V23ProductionMyDayAuthentication: LocalAuthenticationClient {
    func availability() -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }

    func authenticate(_ attempt: LocalAuthenticationAttemptV1)
        -> LocalAuthenticationOutcomeV1 {
        .authenticated
    }

    func cancel(attemptID: UUID) {}
}

@MainActor
private final class V23ProductionMyDayNotificationSystem: NotificationSystemPortV1 {
    private var requests: [NotificationSystemRequestV1] = []

    func authorization() async throws -> LocalReminderAuthorizationV1 { .authorized }

    func observations() async throws -> [NotificationSystemObservationV1] {
        requests.map {
            .init(requestID: $0.notification.requestID, request: $0, delivered: false)
        }
    }

    func add(_ request: NotificationSystemRequestV1) async throws {
        requests.append(request)
    }

    func remove(_ requestIDs: [String]) async throws {
        requests.removeAll { requestIDs.contains($0.notification.requestID) }
    }
}

import Foundation
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V9_78PrivateSystemDiscoveryTests: XCTestCase {
    func testV23P04C14G01OptedInAvailableUnlockedDiscoveryInvokesReusableReadAndRouteOnlyIntents() async throws {
        let corpus = try loadCorpus()
        let manifest = try PrivateSystemDiscoveryManifestV1()
        try manifest.validate()

        XCTAssertEqual(manifest.schemaVersion, corpus.schemaVersion)
        XCTAssertEqual(manifest.indexName, corpus.semantics.namedIndex)
        XCTAssertEqual(manifest.actions.map { $0.action.rawValue }, corpus.actions.sorted())
        XCTAssertEqual(Set(manifest.actions.map(\.action)), Set(PrivateSystemDiscoveryActionV1.allCases))
        XCTAssertTrue(manifest.actions.allSatisfy { !$0.performsMutation && !$0.permitsBackgroundExecution && !$0.permitsNetworkAccess })
        XCTAssertFalse(manifest.activationEnabled)
        XCTAssertFalse(manifest.adoptionEnabled)
        try PrivateSystemDiscoveryAppIntentManifestV1.validate()
        XCTAssertEqual(
            PrivateSystemDiscoveryAppIntentManifestV1.actions,
            [.openAssets, .openReports, .openToday]
        )
        XCTAssertTrue(PrivateSystemDiscoveryAppIntentManifestV1.searchRequiresInAppGatedParameterResolution)
        XCTAssertTrue(PrivateSystemDiscoveryAppIntentManifestV1.allIntentsAreForegroundReadOrNavigation)
        XCTAssertFalse(PrivateSystemDiscoveryAppIntentManifestV1.nonWhitelistedIntentsDiscoverable)

        let coordinator = try C14TestSupport.coordinator(
            workspaceID: C14TestSupport.workspace,
            accessPermitted: true,
            optedIn: true,
            featureReason: .available,
            protectedDataAvailable: true
        )
        for (offset, action) in PrivateSystemDiscoveryActionV1.allCases.enumerated() {
            let request = try C14TestSupport.request(
                workspaceID: C14TestSupport.workspace,
                action: action,
                slot: 100 + offset
            )
            let inApp = try await coordinator.execute(request)
            let intent = try await coordinator.preview(request)
            XCTAssertEqual(inApp, intent, "in-app and intent paths must share the same coordinator result")
            switch inApp {
            case let .navigation(route):
                XCTAssertEqual(route.disposition, .resolved)
                XCTAssertEqual(route.canonicalMutationCount, 0)
                XCTAssertFalse(route.startsAutomaticWork)
                XCTAssertEqual(route.target.workspaceID, C14TestSupport.workspace)
            case let .read(projection):
                XCTAssertEqual(projection.workspaceID, C14TestSupport.workspace)
                XCTAssertEqual(projection.resultIDs, projection.resultIDs.sorted { $0.uuidString < $1.uuidString })
                XCTAssertEqual(projection.resultIDs.count, 2)
                XCTAssertEqual(projection.querySHA256, C14TestSupport.digest("a"))
            case .unavailable, .unlockRequired:
                XCTFail("available, opted-in, unlocked action unexpectedly failed closed")
            }
        }

        XCTAssertEqual(corpus.expectedDispositions.first?.caseName, "OPTED_IN_AVAILABLE_UNLOCKED")
        XCTAssertTrue(corpus.semantics.appAccessBeforeResolution)
        XCTAssertFalse(corpus.semantics.publicRoute)
        XCTAssertFalse(corpus.semantics.networkAccess)
    }

    func testV23P04C14A01UnavailableOrOptedOutDiscoveryPublishesNoPrivateSystemProjection() async throws {
        let corpus = try loadCorpus()
        let disabled = PrivateSystemDiscoveryOptInV1.disabled
        XCTAssertFalse(disabled.isEnabled)
        XCTAssertEqual(disabled.canonicalSettingToken, PrivateSystemDiscoveryOptInV1.offToken)

        let enabled = try PrivateSystemDiscoveryOptInV1.enabled(
            workspaceID: C14TestSupport.workspace,
            workspaceKind: .real
        )
        XCTAssertTrue(enabled.isEnabled)
        XCTAssertEqual(
            try PrivateSystemDiscoveryOptInV1(
                canonicalSettingToken: enabled.canonicalSettingToken,
                workspaceKind: .real
            ),
            enabled
        )
        XCTAssertThrowsError(
            try PrivateSystemDiscoveryOptInV1.enabled(
                workspaceID: C14TestSupport.practiceWorkspace,
                workspaceKind: .practice
            )
        ) { error in
            XCTAssertEqual(error as? PrivateSystemDiscoveryFailureV1, .practiceWorkspaceForbidden)
        }

        let optedOut = try C14TestSupport.coordinator(
            workspaceID: C14TestSupport.workspace,
            accessPermitted: true,
            optedIn: false,
            featureReason: .available,
            protectedDataAvailable: true,
            projection: C14FailingProjection()
        )
        let optedOutRequest = try C14TestSupport.request(
            workspaceID: C14TestSupport.workspace,
            action: .searchWorkspace,
            slot: 201
        )
        let optedOutResult = try await optedOut.execute(optedOutRequest)
        XCTAssertEqual(optedOutResult, .unavailable)

        let unavailable = try C14TestSupport.coordinator(
            workspaceID: C14TestSupport.workspace,
            accessPermitted: true,
            optedIn: true,
            featureReason: .packageNotEnabled,
            protectedDataAvailable: true,
            projection: C14FailingProjection()
        )
        let unavailableRequest = try C14TestSupport.request(
            workspaceID: C14TestSupport.workspace,
            action: .openAssets,
            slot: 202
        )
        let unavailableResult = try await unavailable.execute(unavailableRequest)
        XCTAssertEqual(unavailableResult, .unavailable)

        let descriptors = try C14TestSupport.projectionDescriptors()
        let activeState = try PrivateSystemDiscoveryWorkspaceStateV1(
            workspaceID: C14TestSupport.workspace,
            workspaceRevision: 7,
            projections: descriptors,
            deletionFrontier: 3,
            rebuiltAt: C14TestSupport.now
        )
        let activeMap = try PrivateSystemDiscoveryStateMapV1(workspaces: [activeState])
        let emptyMap = try PrivateSystemDiscoveryStateMapV1(workspaces: [])
        let activeSHA = try WorkspaceMutationCanonicalV1.sha256(activeMap)
        let emptySHA = try WorkspaceMutationCanonicalV1.sha256(emptyMap)

        let rebuild = try PrivateSystemDiscoveryJournalEntryV1(
            operationID: C14TestSupport.id(210), workspaceID: C14TestSupport.workspace,
            operation: .rebuild, expectedPriorStateSHA256: emptySHA,
            resultingStateSHA256: activeSHA, state: .committed, recordedAt: C14TestSupport.now
        )
        let removal = try PrivateSystemDiscoveryJournalEntryV1(
            operationID: C14TestSupport.id(211), workspaceID: C14TestSupport.workspace,
            operation: .removal, expectedPriorStateSHA256: activeSHA,
            resultingStateSHA256: emptySHA, state: .committed, recordedAt: C14TestSupport.now.addingTimeInterval(1)
        )
        try rebuild.validate()
        try removal.validate()
        XCTAssertEqual(rebuild.resultingStateSHA256, activeSHA)
        XCTAssertEqual(removal.resultingStateSHA256, emptySHA)
        XCTAssertTrue(emptyMap.workspaces.isEmpty, "disable/tombstone/Erase must leave no discoverable projection")
        XCTAssertEqual(corpus.expectedDispositions[1].all, "UNAVAILABLE_NO_PRIVATE_PROJECTION")
        XCTAssertTrue(corpus.recovery.preservesCanonicalRecords)
        XCTAssertTrue(corpus.recovery.preservesImmutableReceipts)
    }

    func testV23P04C14H01LockedIngressResolvesNothingAndReturnsOnlyGenericUnlockRequired() async throws {
        let corpus = try loadCorpus()
        let locked = try C14TestSupport.coordinator(
            workspaceID: C14TestSupport.workspace,
            accessPermitted: false,
            optedIn: true,
            featureReason: .available,
            protectedDataAvailable: true,
            projection: C14FailingProjection()
        )
        let lockedRequest = try C14TestSupport.request(
            workspaceID: C14TestSupport.workspace,
            action: .searchWorkspace,
            slot: 301
        )
        let lockedResult = try await locked.execute(lockedRequest)
        XCTAssertEqual(lockedResult, .unlockRequired)

        let concurrentResults = try await withThrowingTaskGroup(of: PrivateSystemDiscoveryResultV1.self) { group in
            for slot in 0..<4 {
                let request = try C14TestSupport.request(
                    workspaceID: C14TestSupport.workspace,
                    action: .openToday,
                    slot: 310 + slot
                )
                group.addTask { try await locked.execute(request) }
            }
            var results: [PrivateSystemDiscoveryResultV1] = []
            for try await result in group { results.append(result) }
            return results
        }
        XCTAssertEqual(concurrentResults.count, 4)
        XCTAssertTrue(concurrentResults.allSatisfy { $0 == .unlockRequired })

        let registry = try RouteRegistryV1()
        XCTAssertTrue(registry.descriptors.allSatisfy { $0.packageID == nil && $0.routeID.hasPrefix("builtin.") })
        XCTAssertNotEqual(PrivateSystemDiscoveryLifecycleV1.namedIndex, "default")
        XCTAssertFalse(PrivateSystemDiscoveryLifecycleV1.createsSecondIndex)
        XCTAssertFalse(PrivateSystemDiscoveryLifecycleV1.createsSecondSettingsSchema)

        let staleTarget = try NavigationTargetV1(
            workspaceID: C14TestSupport.workspace,
            destination: .assets,
            requestedMode: .read,
            expectedRevision: 8
        )
        let staleRoute = try registry.resolve(
            staleTarget,
            context: RouteResolutionContextV1(
                currentWorkspaceID: C14TestSupport.workspace,
                currentRevision: 7
            )
        )
        XCTAssertEqual(staleRoute.disposition, .safeFallback)
        XCTAssertEqual(staleRoute.reason, .staleRevision)

        let foreignRequest = try C14TestSupport.request(
            workspaceID: C14TestSupport.otherWorkspace,
            action: .openAssets,
            slot: 302
        )
        let localCoordinator = try C14TestSupport.coordinator(
            workspaceID: C14TestSupport.workspace,
            accessPermitted: true,
            optedIn: true,
            featureReason: .available,
            protectedDataAvailable: true
        )
        do {
            _ = try await localCoordinator.execute(foreignRequest)
            XCTFail("cross-workspace discovery must not resolve a local route")
        } catch {
            XCTAssertEqual(error as? PrivateSystemDiscoveryFailureV1, .wrongWorkspace)
        }

        XCTAssertThrowsError(
            try PrivateSystemDiscoveryProjectionDescriptorV1(
                domain: .workspaceSearch, projectionVersion: 0,
                allowlistSHA256: C14TestSupport.digest("d"),
                policySHA256: C14TestSupport.digest("e"),
                indexDefinitionSHA256: C14TestSupport.digest("f")
            )
        )
        XCTAssertThrowsError(
            try PrivateSystemDiscoveryRequestV1(
                requestID: C14TestSupport.id(303), workspaceID: C14TestSupport.workspace,
                action: .searchWorkspace, requestedAt: C14TestSupport.now
            )
        )
        XCTAssertThrowsError(
            try PrivateSystemDiscoveryWorkspaceStateV1(
                workspaceID: C14TestSupport.workspace,
                workspaceRevision: 0,
                projections: [], deletionFrontier: 1,
                rebuiltAt: C14TestSupport.now
            )
        )

        for hostile in [
            "EXPECTED_REVISION_BYPASS", "SENSITIVE_FIELD_ALLOWLIST_BYPASS", "PRACTICE_WORKSPACE",
            "CROSS_WORKSPACE_COLLISION", "STALE_PROJECTION", "PUBLIC_ROUTE", "DEFAULT_INDEX",
            "DIRECT_API_SCANNER", "CONCURRENT_SCANNER", "UNSAFE_ORIGINAL_SHARE"
        ] {
            XCTAssertTrue(corpus.hostileCases.contains(hostile), "fixture must bind hostile case \(hostile)")
        }
        XCTAssertEqual(corpus.expectedDispositions[2].all, "UNLOCK_REQUIRED_NO_EXISTENCE_DISCLOSURE")
    }

    func testV23P04C14I01InterruptedRebuildOrRemovalJournalReplaysWithoutDuplicateSystemProjection() async throws {
        let corpus = try loadCorpus()
        let descriptors = try C14TestSupport.projectionDescriptors()
        let manifest = try PrivateSystemDiscoveryManifestV1()
        let availability = try C14TestSupport.availability(for: C14TestSupport.workspace)
        let emptyMap = try PrivateSystemDiscoveryStateMapV1(workspaces: [])
        let active = try PrivateSystemDiscoveryWorkspaceStateV1(
            workspaceID: C14TestSupport.workspace,
            workspaceRevision: 7,
            projections: descriptors,
            deletionFrontier: 3,
            rebuiltAt: C14TestSupport.now
        )
        let activeMap = try PrivateSystemDiscoveryStateMapV1(workspaces: [active])
        let priorSHA = try C14TestSupport.stateDigest(emptyMap)
        let resultingSHA = try C14TestSupport.stateDigest(activeMap)
        XCTAssertEqual(corpus.journal.acceptedStateRule, "ZERO_PARTIAL_OR_ONE_COMPLETE_RECEIPT")
        XCTAssertEqual(corpus.journal.idempotency, "OPERATION_ID_AND_RESULTING_STATE_SHA256")
        XCTAssertEqual(corpus.journal.durableReplay, "REOPEN_ACTOR_LOADS_PREPARED_OR_EFFECT_APPLIED_THEN_COMMITS_ONCE")
        XCTAssertTrue(corpus.journal.noDuplicateIndexing)
        XCTAssertTrue(corpus.journal.noDuplicateDeletion)
        for boundary in ["BEFORE_EFFECT", "AFTER_EFFECT_BEFORE_COMMIT", "AFTER_COMMIT_BEFORE_RETURN"] {
            XCTAssertTrue(corpus.journal.boundaries.contains(boundary))
        }

        let scenarios: [(name: String, failEffect: Bool, failSave: Int?, persistedState: PrivateSystemDiscoveryJournalStateV1?, expectedReplacementCalls: Int, expectedDeletionCalls: Int)] = [
            ("BEFORE_EFFECT", true, nil, .prepared, 2, 2),
            ("AFTER_EFFECT_BEFORE_COMMIT", false, 2, .prepared, 2, 2),
            ("AFTER_COMMIT_BEFORE_RETURN", false, 3, .effectApplied, 1, 1),
            ("NO_FAULT_COMMITTED", false, nil, nil, 1, 1)
        ]

        for (offset, scenario) in scenarios.enumerated() {
            let indexClient = C14ProtectedIndexClient()
            let stateStore = C14DurableStateStore()
            indexClient.failNextReplacement = scenario.failEffect
            if let failSave = scenario.failSave { stateStore.failOnSaveNumbers = [failSave] }
            let operationID = try C14TestSupport.operationID(
                slot: 410 + offset,
                operation: .rebuild,
                workspaceID: C14TestSupport.workspace,
                inputSHA256: priorSHA
            )
            let firstActor = try PrivateSystemDiscoveryIndexStoreV1(
                indexClient: indexClient,
                clientStateStore: stateStore,
                globalJournalStore: stateStore
            )
            var threw = false
            do {
                try await firstActor.rebuild(
                    operationID: operationID,
                    workspaceID: C14TestSupport.workspace,
                    workspaceRevision: 7,
                    deletionFrontier: 3,
                    descriptors: descriptors,
                    manifest: manifest,
                    optIn: try .enabled(workspaceID: C14TestSupport.workspace, workspaceKind: .real),
                    availability: availability,
                    now: C14TestSupport.now
                )
            } catch {
                threw = true
            }
            XCTAssertEqual(threw, scenario.persistedState != nil, "fault boundary \(scenario.name)")

            if let expectedPersistedState = scenario.persistedState {
                let persisted = try XCTUnwrap(try stateStore.load())
                XCTAssertEqual(persisted.pendingOperation?.operationID, operationID)
                XCTAssertEqual(persisted.journal.last?.state, expectedPersistedState)

                let reopenedActor = try PrivateSystemDiscoveryIndexStoreV1(
                    indexClient: indexClient,
                    clientStateStore: stateStore,
                    globalJournalStore: stateStore
                )
                let recovered = try await reopenedActor.state()
                XCTAssertEqual(recovered, activeMap)
                let journal = try await reopenedActor.journalEntries()
                let operationEntries = journal.filter { $0.operationID == operationID.rawValue }
                XCTAssertEqual(operationEntries.map(\.state), [.prepared, .effectApplied, .committed])
                XCTAssertEqual(operationEntries.last?.resultingStateSHA256, resultingSHA)
                XCTAssertEqual(try C14TestSupport.stateDigest(recovered), resultingSHA)
                XCTAssertEqual(indexClient.items().count, PrivateSystemDiscoveryActionV1.allCases.count)
                XCTAssertEqual(Set(indexClient.items().map(\.uniqueIdentifier)).count, indexClient.items().count)
                XCTAssertEqual(indexClient.replacementCallCount, scenario.expectedReplacementCalls)
                XCTAssertEqual(indexClient.deletionCallCount, 0)
            } else {
                let sameRequestActor = try PrivateSystemDiscoveryIndexStoreV1(
                    indexClient: indexClient,
                    clientStateStore: stateStore,
                    globalJournalStore: stateStore
                )
                try await sameRequestActor.rebuild(
                    operationID: operationID,
                    workspaceID: C14TestSupport.workspace,
                    workspaceRevision: 7,
                    deletionFrontier: 3,
                    descriptors: descriptors,
                    manifest: manifest,
                    optIn: try .enabled(workspaceID: C14TestSupport.workspace, workspaceKind: .real),
                    availability: availability,
                    now: C14TestSupport.now
                )
                let recovered = try await sameRequestActor.state()
                XCTAssertEqual(recovered, activeMap)
                let journal = try await sameRequestActor.journalEntries()
                XCTAssertEqual(journal.filter { $0.operationID == operationID.rawValue }.map(\.state), [.prepared, .effectApplied, .committed])
                XCTAssertEqual(indexClient.replacementCallCount, scenario.expectedReplacementCalls)
                let changedInputOperation = try PrivateSystemDiscoveryOperationIDV1(
                    rawValue: operationID.rawValue,
                    operation: .rebuild,
                    workspaceID: C14TestSupport.workspace,
                    inputSHA256: C14TestSupport.digest("x")
                )
                do {
                    try await sameRequestActor.rebuild(
                        operationID: changedInputOperation,
                        workspaceID: C14TestSupport.workspace,
                        workspaceRevision: 7,
                        deletionFrontier: 3,
                        descriptors: descriptors,
                        manifest: manifest,
                        optIn: try .enabled(workspaceID: C14TestSupport.workspace, workspaceKind: .real),
                        availability: availability,
                        now: C14TestSupport.now
                    )
                    XCTFail("same raw operation ID with a changed input digest must fail closed")
                } catch {
                    XCTAssertEqual(error as? PrivateSystemDiscoveryFailureV1, .invalidValue)
                }
            }
        }

        for (offset, scenario) in scenarios.enumerated() {
            let indexClient = C14ProtectedIndexClient()
            let stateStore = C14DurableStateStore()
            let seedActor = try PrivateSystemDiscoveryIndexStoreV1(
                indexClient: indexClient,
                clientStateStore: stateStore,
                globalJournalStore: stateStore
            )
            let seedOperation = try C14TestSupport.operationID(
                slot: 450 + offset,
                operation: .rebuild,
                workspaceID: C14TestSupport.workspace,
                inputSHA256: priorSHA
            )
            try await seedActor.rebuild(
                operationID: seedOperation,
                workspaceID: C14TestSupport.workspace,
                workspaceRevision: 7,
                deletionFrontier: 3,
                descriptors: descriptors,
                manifest: manifest,
                optIn: try .enabled(workspaceID: C14TestSupport.workspace, workspaceKind: .real),
                availability: availability,
                now: C14TestSupport.now
            )
            let seededState = try await seedActor.state()
            XCTAssertEqual(seededState, activeMap)
            XCTAssertEqual(indexClient.items().count, PrivateSystemDiscoveryActionV1.allCases.count)

            let removeOperation = try C14TestSupport.operationID(
                slot: 460 + offset,
                operation: .removal,
                workspaceID: C14TestSupport.workspace,
                inputSHA256: try C14TestSupport.stateDigest(seededState)
            )
            indexClient.failNextDeletion = scenario.failEffect
            if let failSave = scenario.failSave { stateStore.failOnSaveNumbers = [3 + failSave] }
            let removalActor = try PrivateSystemDiscoveryIndexStoreV1(
                indexClient: indexClient,
                clientStateStore: stateStore,
                globalJournalStore: stateStore
            )
            var threw = false
            do {
                try await removalActor.remove(
                    operationID: removeOperation,
                    workspaceID: C14TestSupport.workspace,
                    now: C14TestSupport.now.addingTimeInterval(1)
                )
            } catch {
                threw = true
            }
            XCTAssertEqual(threw, scenario.persistedState != nil, "removal fault boundary \(scenario.name)")
            if let persistedState = scenario.persistedState {
                let persisted = try XCTUnwrap(try stateStore.load())
                XCTAssertEqual(persisted.pendingOperation?.operationID, removeOperation)
                XCTAssertEqual(persisted.journal.last?.state, persistedState)
            } else {
                XCTAssertNil(try stateStore.load()?.pendingOperation)
            }

            let reopenedRemovalActor = try PrivateSystemDiscoveryIndexStoreV1(
                indexClient: indexClient,
                clientStateStore: stateStore,
                globalJournalStore: stateStore
            )
            let removalState = try await reopenedRemovalActor.state()
            XCTAssertTrue(removalState.workspaces.isEmpty)
            let removalJournal = try await reopenedRemovalActor.journalEntries()
            let removalEntries = removalJournal.filter { $0.operationID == removeOperation.rawValue }
            XCTAssertEqual(removalEntries.map(\.state), [.prepared, .effectApplied, .committed])
            XCTAssertEqual(removalEntries.last?.resultingStateSHA256, priorSHA)
            XCTAssertEqual(try C14TestSupport.stateDigest(removalState), priorSHA)
            XCTAssertTrue(indexClient.items().isEmpty, "removal replay leaves no derived projection")
            XCTAssertEqual(indexClient.replacementCallCount, 1)
            XCTAssertEqual(indexClient.deletionCallCount, scenario.expectedDeletionCalls)
            XCTAssertNil(try stateStore.load()?.pendingOperation)

            try await reopenedRemovalActor.remove(
                operationID: removeOperation,
                workspaceID: C14TestSupport.workspace,
                now: C14TestSupport.now.addingTimeInterval(1)
            )
            XCTAssertEqual(indexClient.deletionCallCount, scenario.expectedDeletionCalls, "same removal ID is idempotent")
        }

        let globalSaveFailures: [(name: String, saveNumber: Int)] = [
            ("PREPARED", 1),
            ("EFFECT_APPLIED", 2),
            ("COMMITTED", 3)
        ]
        for (offset, scenario) in globalSaveFailures.enumerated() {
            let indexClient = C14ProtectedIndexClient()
            let stateStore = C14DurableStateStore()
            let seedActor = try PrivateSystemDiscoveryIndexStoreV1(
                indexClient: indexClient,
                clientStateStore: stateStore,
                globalJournalStore: stateStore
            )
            let seedOperation = try C14TestSupport.operationID(
                slot: 490 + offset,
                operation: .rebuild,
                workspaceID: C14TestSupport.workspace,
                inputSHA256: priorSHA
            )
            try await seedActor.rebuild(
                operationID: seedOperation,
                workspaceID: C14TestSupport.workspace,
                workspaceRevision: 7,
                deletionFrontier: 3,
                descriptors: descriptors,
                manifest: manifest,
                optIn: try .enabled(workspaceID: C14TestSupport.workspace, workspaceKind: .real),
                availability: availability,
                now: C14TestSupport.now
            )
            let seededGlobalState = try await seedActor.state()
            XCTAssertEqual(seededGlobalState, activeMap)
            XCTAssertEqual(indexClient.items().count, PrivateSystemDiscoveryActionV1.allCases.count)

            let eraseOperation = try C14TestSupport.operationID(
                slot: 500 + offset,
                operation: .removal,
                workspaceID: C14TestSupport.workspace,
                inputSHA256: C14TestSupport.digest("g")
            )
            stateStore.failOnGlobalSaveNumbers = [scenario.saveNumber]
            let failingActor = try PrivateSystemDiscoveryIndexStoreV1(
                indexClient: indexClient,
                clientStateStore: stateStore,
                globalJournalStore: stateStore
            )
            var caughtFailure: Error?
            do {
                try await failingActor.eraseAll(operationID: eraseOperation, now: C14TestSupport.now)
            } catch {
                caughtFailure = error
            }
            XCTAssertEqual(
                caughtFailure as? C14InjectedFailure,
                .globalSave(scenario.saveNumber),
                "global journal save fault " + scenario.name + " must be surfaced"
            )
            XCTAssertEqual(stateStore.globalSaveCount, scenario.saveNumber)

            let durableGlobal = try XCTUnwrap(try stateStore.loadGlobal())
            XCTAssertEqual(
                durableGlobal.entries.map(\.state),
                scenario.saveNumber == 1 ? [] : [.prepared] + (scenario.saveNumber == 3 ? [.effectApplied] : []),
                "durable global journal must stop before the failed transition " + scenario.name
            )
            switch scenario.saveNumber {
            case 1:
                let failedPreparedState = try await failingActor.state()
                XCTAssertEqual(failedPreparedState, activeMap)
                XCTAssertEqual(indexClient.deleteAllCallCount, 0)
                XCTAssertEqual(indexClient.items().count, PrivateSystemDiscoveryActionV1.allCases.count)
                XCTAssertEqual(try stateStore.load()?.stateMap, activeMap)
            case 2:
                XCTAssertEqual(indexClient.deleteAllCallCount, 1)
                XCTAssertTrue(indexClient.items().isEmpty)
                XCTAssertEqual(try stateStore.load()?.stateMap, emptyMap)
            case 3:
                XCTAssertEqual(indexClient.deleteAllCallCount, 1)
                XCTAssertTrue(indexClient.items().isEmpty)
                XCTAssertEqual(try stateStore.load()?.stateMap, emptyMap, "client state is cleared before the durable commit retry")
            default:
                XCTFail("unexpected global save fault number")
            }

            stateStore.failOnGlobalSaveNumbers = []
            let deleteAllBeforeSameActorRetry = indexClient.deleteAllCallCount
            try await failingActor.eraseAll(operationID: eraseOperation, now: C14TestSupport.now)
            let sameActorState = try await failingActor.state()
            XCTAssertEqual(sameActorState, emptyMap)
            XCTAssertTrue(indexClient.items().isEmpty)
            XCTAssertEqual(
                indexClient.deleteAllCallCount,
                scenario.saveNumber == 1 ? deleteAllBeforeSameActorRetry + 1
                    : scenario.saveNumber == 2 ? deleteAllBeforeSameActorRetry + 1
                    : deleteAllBeforeSameActorRetry,
                "same-process retry must recover from the last durable global phase " + scenario.name
            )
            XCTAssertEqual(
                try stateStore.loadGlobal()?.entries.map(\.state),
                [.prepared, .effectApplied, .committed]
            )

            let reopenedActor = try PrivateSystemDiscoveryIndexStoreV1(
                indexClient: indexClient,
                clientStateStore: stateStore,
                globalJournalStore: stateStore
            )
            switch scenario.saveNumber {
            case 1:
                try await reopenedActor.eraseAll(operationID: eraseOperation, now: C14TestSupport.now)
            case 2, 3:
                let reopenedRecoveredState = try await reopenedActor.state()
                XCTAssertEqual(reopenedRecoveredState, emptyMap)
            default:
                XCTFail("unexpected global save fault number")
            }
            let reopenedFinalState = try await reopenedActor.state()
            XCTAssertEqual(reopenedFinalState, emptyMap)
            XCTAssertTrue(indexClient.items().isEmpty)
            XCTAssertEqual(
                indexClient.deleteAllCallCount,
                scenario.saveNumber == 2 ? 2 : 1,
                "recovery replays only the effect that was not durably acknowledged"
            )
            XCTAssertEqual(
                try stateStore.loadGlobal()?.entries.map(\.state),
                [.prepared, .effectApplied, .committed]
            )

            let deleteAllBeforeCommittedReplay = indexClient.deleteAllCallCount
            try await PrivateSystemDiscoveryEraseAllServiceBoundaryV1.dropAfterRestoreOrReplay(
                operationID: eraseOperation,
                index: reopenedActor
            )
            XCTAssertEqual(
                indexClient.deleteAllCallCount,
                deleteAllBeforeCommittedReplay,
                "a committed global parent receipt short-circuits same-ID restore replay"
            )
        }
    }

    func testV23P04C14R01DeleteEraseExportAndReportDropAndRebuildDerivedDiscoveryProjection() async throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(PrivateSystemDiscoveryIndexStoreV1.indexName, PrivateSystemDiscoveryLifecycleV1.namedIndex)
        XCTAssertFalse(PrivateSystemDiscoverySearchRebuildBoundaryV1.usesDefaultIndex)
        XCTAssertTrue(PrivateSystemDiscoverySearchRebuildBoundaryV1.sourceIsSelectedRealWorkspaceOnly)
        XCTAssertTrue(PrivateSystemDiscoverySearchRebuildBoundaryV1.projectionIsDerivedOnly)
        XCTAssertTrue(corpus.recovery.eraseOnePreservesOtherWorkspace)
        XCTAssertTrue(corpus.recovery.globalEraseClearsAllKnownDomains)
        XCTAssertEqual(corpus.recovery.stateBlobLifecycle, "PRESENT_AFTER_COMMIT_CLEARED_BY_GLOBAL_ERASE_OR_DROP")
        XCTAssertEqual(corpus.recovery.reportDisposition, "AGGREGATE_ONLY_DERIVED_REMOVAL_JOURNALED")

        let indexClient = C14ProtectedIndexClient()
        let stateStore = C14DurableStateStore()
        let index = try PrivateSystemDiscoveryIndexStoreV1(
            indexClient: indexClient,
            clientStateStore: stateStore,
            globalJournalStore: stateStore
        )
        let descriptors = try C14TestSupport.projectionDescriptors()
        let manifest = try PrivateSystemDiscoveryManifestV1()
        let workspace = C14TestSupport.workspace
        let otherWorkspace = C14TestSupport.otherWorkspace
        let emptyMap = try PrivateSystemDiscoveryStateMapV1(workspaces: [])

        let defaultOffClient = C14ProtectedIndexClient()
        let defaultOffStore = C14DurableStateStore()
        let defaultOffIndex = try PrivateSystemDiscoveryIndexStoreV1(
            indexClient: defaultOffClient,
            clientStateStore: defaultOffStore,
            globalJournalStore: defaultOffStore
        )
        let defaultOffOperation = try C14TestSupport.operationID(
            slot: 509, operation: .rebuild, workspaceID: workspace,
            inputSHA256: try C14TestSupport.stateDigest(emptyMap)
        )
        try await PrivateSystemDiscoverySearchRebuildBoundaryV1.rebuild(
            operationID: defaultOffOperation,
            index: defaultOffIndex,
            workspaceID: workspace,
            workspaceRevision: 7,
            deletionFrontier: 3,
            descriptors: descriptors,
            manifest: manifest,
            optIn: .disabled,
            availability: try C14TestSupport.availability(
                for: workspace, optedIn: false, featureReason: .workspacePolicyDisabled
            ),
            now: C14TestSupport.now
        )
        let defaultOffState = try await defaultOffIndex.state()
        XCTAssertTrue(defaultOffState.workspaces.isEmpty)
        XCTAssertTrue(defaultOffClient.items().isEmpty, "default-off rebuild must publish no private projection")
        let defaultOffJournal = try await defaultOffIndex.journalEntries()
        XCTAssertEqual(defaultOffJournal.last?.state, .committed)
        try await PrivateSystemDiscoverySearchRebuildBoundaryV1.rebuild(
            operationID: defaultOffOperation,
            index: defaultOffIndex,
            workspaceID: workspace,
            workspaceRevision: 7,
            deletionFrontier: 3,
            descriptors: descriptors,
            manifest: manifest,
            optIn: .disabled,
            availability: try C14TestSupport.availability(
                for: workspace, optedIn: false, featureReason: .workspacePolicyDisabled
            ),
            now: C14TestSupport.now
        )
        let retriedDefaultOffJournal = try await defaultOffIndex.journalEntries()
        XCTAssertEqual(retriedDefaultOffJournal.count, defaultOffJournal.count)

        let workspaceState = try PrivateSystemDiscoveryWorkspaceStateV1(
            workspaceID: workspace,
            workspaceRevision: 7,
            projections: descriptors,
            deletionFrontier: 3,
            rebuiltAt: C14TestSupport.now
        )
        let otherState = try PrivateSystemDiscoveryWorkspaceStateV1(
            workspaceID: otherWorkspace,
            workspaceRevision: 9,
            projections: descriptors,
            deletionFrontier: 4,
            rebuiltAt: C14TestSupport.now.addingTimeInterval(1)
        )
        let searchRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("C14-private-system-search-\(C14TestSupport.id(590).uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: searchRoot) }
        let searchStore = try LocalSearchIndexStoreV1(applicationSupportURL: searchRoot)
        let searchRegistry = try SearchIndexRebuildCoordinatorV1.makeRegistry()
        let firstSourceRevision = try SearchSourceRevisionV1(
            workspaceID: workspace.rawValue,
            generationID: C14TestSupport.id(591),
            commitRevision: 7
        )
        let firstRebuilder = try SearchIndexRebuildCoordinatorV1(
            store: searchStore,
            source: C14SearchSource(revision: firstSourceRevision),
            registry: searchRegistry,
            makeOperationID: { C14TestSupport.id(510) },
            privateSystemDiscoveryIndex: index,
            privateSystemDiscoverySource: C14ProductionRebuildProvider(
                deletionFrontier: 3,
                requestedAt: C14TestSupport.now
            )
        )
        let firstRebuild = try await firstRebuilder.rebuildIfNeeded()
        XCTAssertEqual(firstRebuild.disposition, .absentBuild)
        XCTAssertEqual(firstRebuild.indexedRecordCount, 0)
        let firstSearchRevision = try await searchStore.revision()
        XCTAssertEqual(firstSearchRevision?.workspaceID, workspace.rawValue)
        XCTAssertEqual(firstSearchRevision?.generationID, firstSourceRevision.generationID)
        XCTAssertEqual(firstSearchRevision?.indexedCommitRevision, 7)
        let firstState = try await PrivateSystemDiscoverySearchLifecycleV1(index: index).reportState()
        XCTAssertEqual(firstState.workspaces, [workspaceState])
        XCTAssertEqual(indexClient.items().count, PrivateSystemDiscoveryActionV1.allCases.count)
        XCTAssertNotNil(try stateStore.load(), "a committed derived state blob is durable across actor recreation")
        let firstJournal = try await index.journalEntries()
        XCTAssertEqual(firstJournal.last?.operationID, C14TestSupport.id(510))
        XCTAssertEqual(firstJournal.last?.operation, .rebuild)
        let firstReport = try await PrivateSystemDiscoveryReportProjectionRegistryV1.projection(from: index)
        XCTAssertEqual(firstReport.indexedRealWorkspaceCount, 1)
        XCTAssertEqual(firstReport.persistenceDisposition, "DERIVED_ONLY")
        XCTAssertEqual(firstReport.deletionDisposition, "REMOVAL_JOURNALED")

        let secondSourceRevision = try SearchSourceRevisionV1(
            workspaceID: otherWorkspace.rawValue,
            generationID: C14TestSupport.id(592),
            commitRevision: 9
        )
        let secondRebuilder = try SearchIndexRebuildCoordinatorV1(
            store: searchStore,
            source: C14SearchSource(revision: secondSourceRevision),
            registry: searchRegistry,
            makeOperationID: { C14TestSupport.id(511) },
            privateSystemDiscoveryIndex: index,
            privateSystemDiscoverySource: C14ProductionRebuildProvider(
                deletionFrontier: 4,
                requestedAt: C14TestSupport.now.addingTimeInterval(1)
            )
        )
        let secondRebuild = try await secondRebuilder.rebuildIfNeeded()
        XCTAssertEqual(secondRebuild.disposition, .wrongGenerationDropAndRebuild)
        XCTAssertEqual(secondRebuild.indexedRecordCount, 0)
        let secondSearchRevision = try await searchStore.revision()
        XCTAssertEqual(secondSearchRevision?.workspaceID, otherWorkspace.rawValue)
        XCTAssertEqual(secondSearchRevision?.generationID, secondSourceRevision.generationID)
        XCTAssertEqual(secondSearchRevision?.indexedCommitRevision, 9)
        let bothState = try await PrivateSystemDiscoverySearchLifecycleV1(index: index).reportState()
        XCTAssertEqual(bothState.workspaces, [workspaceState, otherState].sorted { $0.workspaceID.rawValue.uuidString < $1.workspaceID.rawValue.uuidString })
        XCTAssertEqual(indexClient.items().count, PrivateSystemDiscoveryActionV1.allCases.count * 2)
        XCTAssertEqual(try stateStore.load()?.knownWorkspaceIDs.count, 2)
        let secondJournal = try await index.journalEntries()
        XCTAssertEqual(secondJournal.last?.operationID, C14TestSupport.id(511))
        XCTAssertEqual(secondJournal.last?.operation, .rebuild)

        let eraseRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("C14-private-system-erase-\(C14TestSupport.id(593).uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: eraseRoot) }
        let eraseLibrary = eraseRoot.appendingPathComponent("Library", isDirectory: true)
        let eraseSupport = eraseLibrary.appendingPathComponent("Application Support", isDirectory: true)
        let eraseCaches = eraseLibrary.appendingPathComponent("Caches", isDirectory: true)
        let eraseTemporary = eraseRoot.appendingPathComponent("tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: eraseSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: eraseCaches, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: eraseTemporary, withIntermediateDirectories: true)
        let eraseFactory = StoreGenerationFactory(applicationSupportURL: eraseSupport)
        let eraseSession = try eraseFactory.openOrBootstrapCurrent()
        let eraseCoordinator = StoreSessionCoordinator(session: eraseSession)
        let eraseWorkspace = eraseCoordinator.workspaceID
        let diagnostics = DiagnosticsStore(applicationSupportURL: eraseSupport)
        await diagnostics.prepare()
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "C14-\(C14TestSupport.id(594).uuidString)")
        )
        let eraseBundleID = "com.palatis3.fieldrecord"
        defaults.setPersistentDomain(["c14-test": true], forName: eraseBundleID)
        defer { defaults.removePersistentDomain(forName: eraseBundleID) }

        let removeOperation = try C14TestSupport.operationID(
            slot: 512, operation: .removal, workspaceID: workspace,
            inputSHA256: try C14TestSupport.stateDigest(bothState)
        )
        let deletionLedgerStore = DeletionLedgerStore(
            context: eraseCoordinator.modelContext,
            privateSystemDiscoveryIndex: index
        )
        let removalRequest = try PrivateSystemDiscoveryRemovalRequestV1(
            operationRawID: removeOperation.rawValue,
            workspaceID: workspace,
            priorStateSHA256: removeOperation.inputSHA256,
            requestedAt: C14TestSupport.now.addingTimeInterval(2)
        )
        try await deletionLedgerStore.removePrivateSystemDiscovery(request: removalRequest)
        let deletionAfterFirstRequest = indexClient.deletionCallCount
        try await deletionLedgerStore.removePrivateSystemDiscovery(request: removalRequest)
        XCTAssertEqual(indexClient.deletionCallCount, deletionAfterFirstRequest, "same removal request is an explicit production-ledger replay")
        let afterOne = try await PrivateSystemDiscoverySearchLifecycleV1(index: index).reportState()
        XCTAssertEqual(afterOne.workspaces, [otherState])
        XCTAssertEqual(indexClient.items().count, PrivateSystemDiscoveryActionV1.allCases.count)
        XCTAssertTrue(indexClient.items().allSatisfy { $0.domainIdentifier.contains(otherWorkspace.rawValue.uuidString.lowercased()) })
        let afterOneJournal = try await index.journalEntries()
        XCTAssertEqual(afterOneJournal.last?.operation, .removal)
        XCTAssertEqual(afterOneJournal.last?.state, .committed)
        XCTAssertEqual(afterOneJournal.last?.operationID, removeOperation.rawValue)
        let afterOneReport = try await PrivateSystemDiscoveryReportProjectionRegistryV1.projection(from: index)
        XCTAssertEqual(afterOneReport.indexedRealWorkspaceCount, 1)
        XCTAssertEqual(afterOneReport.deletionDisposition, "REMOVAL_JOURNALED")

        var generatedEraseIDs: [UUID] = []
        let eraseIndexSpy = C14IndexLifecycleSpy(index: index)
        let eraseService = EraseAllService(
            applicationSupportURL: eraseSupport,
            cachesDirectoryURL: eraseCaches,
            temporaryDirectoryURL: eraseTemporary,
            userDefaults: defaults,
            bundleIdentifier: eraseBundleID,
            makeUUID: {
                let value = C14TestSupport.id(513 + generatedEraseIDs.count)
                generatedEraseIDs.append(value)
                return value
            },
            privateSystemDiscoveryIndex: eraseIndexSpy
        )
        let erased = try await eraseService.erase(
            confirmation: EraseAllService.requiredConfirmation,
            coordinator: eraseCoordinator,
            diagnosticsStore: diagnostics
        ) { session in
            eraseCoordinator.activate(session: session)
        }
        XCTAssertFalse(erased.cleanupDeferred)
        XCTAssertEqual(generatedEraseIDs, [C14TestSupport.id(513), C14TestSupport.id(514)])
        let eraseParentOperation = try XCTUnwrap(eraseIndexSpy.lastEraseOperationID)
        XCTAssertEqual(eraseParentOperation.rawValue, C14TestSupport.id(514))
        XCTAssertEqual(eraseParentOperation.operation, .removal)
        XCTAssertEqual(eraseParentOperation.workspaceID, eraseWorkspace)
        let erasedState = try await index.state()
        XCTAssertTrue(erasedState.workspaces.isEmpty)
        XCTAssertTrue(indexClient.items().isEmpty, "global Erase removes all known disposable domains")
        XCTAssertEqual(indexClient.deleteAllCallCount, 1, "incumbent EraseAllService invokes the protected global effect exactly once")
        XCTAssertEqual(try stateStore.load()?.stateMap, emptyMap, "global Erase persists an empty derived state envelope")

        let deleteAllBeforeRestoreReplay = indexClient.deleteAllCallCount
        try await PrivateSystemDiscoveryEraseAllServiceBoundaryV1.dropAfterRestoreOrReplay(
            operationID: eraseParentOperation,
            index: index
        )
        XCTAssertEqual(
            indexClient.deleteAllCallCount,
            deleteAllBeforeRestoreReplay,
            "restore/replay with the exact committed parent binding must not repeat the protected global effect"
        )
        let changedParentBinding = try PrivateSystemDiscoveryOperationIDV1(
            rawValue: eraseParentOperation.rawValue,
            operation: .removal,
            workspaceID: eraseParentOperation.workspaceID,
            inputSHA256: C14TestSupport.digest("z")
        )
        do {
            try await PrivateSystemDiscoveryEraseAllServiceBoundaryV1.dropAfterRestoreOrReplay(
                operationID: changedParentBinding,
                index: index
            )
            XCTFail("same raw parent ID with changed binding must fail closed")
        } catch {
            XCTAssertEqual(error as? PrivateSystemDiscoveryFailureV1, .invalidValue)
        }
        XCTAssertEqual(
            indexClient.deleteAllCallCount,
            deleteAllBeforeRestoreReplay,
            "a stale parent binding must not re-run the protected global effect"
        )

        let reopenedAfterGlobalCommit = try PrivateSystemDiscoveryIndexStoreV1(
            indexClient: indexClient,
            clientStateStore: stateStore,
            globalJournalStore: stateStore
        )
        let reopenedState = try await reopenedAfterGlobalCommit.state()
        XCTAssertTrue(reopenedState.workspaces.isEmpty)
        XCTAssertTrue(indexClient.items().isEmpty)
        let deleteAllBeforeReopenedReplay = indexClient.deleteAllCallCount
        try await PrivateSystemDiscoveryEraseAllServiceBoundaryV1.dropAfterRestoreOrReplay(
            operationID: eraseParentOperation,
            index: reopenedAfterGlobalCommit
        )
        XCTAssertEqual(
            indexClient.deleteAllCallCount,
            deleteAllBeforeReopenedReplay,
            "reopened global journal must short-circuit the committed parent replay"
        )
        let droppedState = try await reopenedAfterGlobalCommit.state()
        XCTAssertTrue(droppedState.workspaces.isEmpty)
        XCTAssertTrue(indexClient.items().isEmpty)
        let emptyReport = try await PrivateSystemDiscoveryReportProjectionRegistryV1.projection(from: index)
        XCTAssertEqual(emptyReport.indexedRealWorkspaceCount, 0)
        XCTAssertEqual(emptyReport.persistenceDisposition, "DERIVED_ONLY")
        XCTAssertTrue(PrivateSystemDiscoveryLifecycleV1.dropAndRebuildOnRestore)
        XCTAssertTrue(PrivateSystemDiscoveryLifecycleV1.removalIsJournaled)
        XCTAssertFalse(PrivateSystemDiscoveryLifecycleV1.canonicalPersistence)
        try PrivateSystemDiscoverySearchPersistenceBoundaryV1.validate()

        let share = try C14TestSupport.shareFixture()
        let safeShare = try PrivateSystemDiscoveryShareDescriptorV1(
            workspaceID: share.workspace,
            audience: .customerReport,
            content: share.derivative,
            privacyManifest: share.manifest,
            policy: share.policy,
            review: share.review,
            now: C14TestSupport.now.addingTimeInterval(4)
        )
        XCTAssertEqual(safeShare.workspaceID, share.workspace)
        XCTAssertEqual(safeShare.content, share.derivative)
        XCTAssertEqual(safeShare.audience, .customerReport)
        XCTAssertThrowsError(
            try PrivateSystemDiscoveryShareDescriptorV1(
                workspaceID: share.workspace,
                audience: .customerReport,
                content: share.original,
                privacyManifest: share.manifest,
                policy: share.policy,
                review: share.review,
                now: C14TestSupport.now.addingTimeInterval(4)
            )
        ) { error in
            XCTAssertEqual(error as? PrivateSystemDiscoveryFailureV1, .unsafeShare)
        }
        XCTAssertTrue(corpus.safeShare.originalBytesNeverShared)
        XCTAssertTrue(corpus.safeShare.requiresPrivacyManifest)
        XCTAssertTrue(corpus.safeShare.requiresApprovedReview)
    }

    private func loadCorpus() throws -> C14Corpus {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V23/SystemDiscovery/V23P04C14PrivateSystemDiscoveryCorpusV1.json")
        let corpus = try JSONDecoder().decode(C14Corpus.self, from: Data(contentsOf: url))
        XCTAssertEqual(corpus.schema, "V23P04C14PrivateSystemDiscoveryCorpusV1")
        XCTAssertEqual(corpus.cardID, "V23-P04-C14")
        XCTAssertEqual(corpus.ordinal, 102)
        XCTAssertEqual(corpus.selectors.count, 5)
        XCTAssertEqual(corpus.selectors.map(\.selector), [
            "testV23P04C14G01OptedInAvailableUnlockedDiscoveryInvokesReusableReadAndRouteOnlyIntents",
            "testV23P04C14A01UnavailableOrOptedOutDiscoveryPublishesNoPrivateSystemProjection",
            "testV23P04C14H01LockedIngressResolvesNothingAndReturnsOnlyGenericUnlockRequired",
            "testV23P04C14I01InterruptedRebuildOrRemovalJournalReplaysWithoutDuplicateSystemProjection",
            "testV23P04C14R01DeleteEraseExportAndReportDropAndRebuildDerivedDiscoveryProjection"
        ])
        XCTAssertEqual(corpus.statusFlags, .allFalse)
        XCTAssertTrue(corpus.uiAdoptionSkipped)
        return corpus
    }
}

private struct C14Corpus: Decodable {
    struct Selector: Decodable {
        let selector: String
    }

    struct Authority: Decodable {
        let contextDigest: String
        let pathFenceDigest: String
        let sequence: Int
        let finalHashesSealed: Bool
    }

    struct Semantics: Decodable {
        let namedIndex: String
        let persistentContractMode: String
        let persistentContractSchema: String
        let canonicalPersistence: Bool
        let defaultOff: Bool
        let selectedWorkspaceOnly: Bool
        let realWorkspaceOnly: Bool
        let practiceExcluded: Bool
        let appAccessBeforeResolution: Bool
        let removalDisposition: String
        let restoreDisposition: String
        let publicRoute: Bool
        let networkAccess: Bool
        let telemetry: Bool
    }

    struct SourceHandoff: Decodable {
        let cardID: String
        let previewFirst: Bool
        let usesExistingAvailabilityPolicy: Bool
        let usesExistingAccessGate: Bool
        let usesExistingRouteRegistry: Bool
        let secondIndex: Bool
        let secondSettingsSchema: Bool
        let canonicalWriter: Bool
    }

    struct ProjectionDescriptor: Decodable {
        let domain: String
        let projectionVersion: Int
        let allowlistSHA256: String
        let policySHA256: String
        let indexDefinitionSHA256: String
    }

    struct ExpectedDisposition: Decodable {
        let caseName: String
        let all: String?

        enum CodingKeys: String, CodingKey {
            case caseName = "case"
            case all
        }
    }

    struct Journal: Decodable {
        let acceptedStateRule: String
        let idempotency: String
        let boundaries: [String]
        let durableReplay: String
        let noDuplicateIndexing: Bool
        let noDuplicateDeletion: Bool
    }

    struct SafeShare: Decodable {
        let requiresPrivacyManifest: Bool
        let requiresApprovedReview: Bool
        let originalBytesNeverShared: Bool
    }

    struct Recovery: Decodable {
        let preservesCanonicalRecords: Bool
        let preservesImmutableReceipts: Bool
        let eraseOnePreservesOtherWorkspace: Bool
        let globalEraseClearsAllKnownDomains: Bool
        let stateBlobLifecycle: String
        let reportDisposition: String
    }

    struct StatusFlags: Decodable, Equatable {
        let activation: Bool
        let native: Bool
        let hosted: Bool
        let adoption: Bool
        let acceptance: Bool
        let release: Bool
        let nativeAcceptance: Bool
        let hostedAcceptance: Bool
        let physicalEvidence: Bool
        let phase10PollingDuringParallelExecution: Bool
        let uiAcceptanceCredit: Bool

        static let allFalse = StatusFlags(
            activation: false, native: false, hosted: false, adoption: false,
            acceptance: false, release: false, nativeAcceptance: false,
            hostedAcceptance: false, physicalEvidence: false,
            phase10PollingDuringParallelExecution: false, uiAcceptanceCredit: false
        )
    }

    let schema: String
    let schemaVersion: Int
    let cardID: String
    let ordinal: Int
    let selectors: [Selector]
    let actions: [String]
    let authority: Authority
    let semantics: Semantics
    let sourceHandoff: SourceHandoff
    let projectionDescriptors: [ProjectionDescriptor]
    let expectedDispositions: [ExpectedDisposition]
    let journal: Journal
    let safeShare: SafeShare
    let hostileCases: [String]
    let recovery: Recovery
    let statusFlags: StatusFlags
    let uiAdoptionSkipped: Bool
}

private enum C14TestSupport {
    static let now = Date(timeIntervalSince1970: 1_800_100_000)
    static let workspace = WorkspaceID(rawValue: id(1))
    static let otherWorkspace = WorkspaceID(rawValue: id(2))
    static let practiceWorkspace = WorkspaceID(rawValue: id(3))

    static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "c1400000-0000-4000-8000-%012x", slot))!
    }

    static func digest(_ character: Character) -> String {
        String(repeating: character, count: 64)
    }

    static func request(workspaceID: WorkspaceID, action: PrivateSystemDiscoveryActionV1, slot: Int) throws -> PrivateSystemDiscoveryRequestV1 {
        try PrivateSystemDiscoveryRequestV1(
            requestID: id(slot),
            workspaceID: workspaceID,
            action: action,
            privateParameterToken: action == .searchWorkspace ? "opaque-\(slot)" : nil,
            requestedAt: now
        )
    }

    static func coordinator(
        workspaceID: WorkspaceID,
        accessPermitted: Bool,
        optedIn: Bool,
        featureReason: FeatureAvailabilityReasonV1,
        protectedDataAvailable: Bool,
        projection: any PrivateSystemDiscoveryProjectionPortV1 = C14Projection(),
        routeContext: (any PrivateSystemDiscoveryRouteContextPortV1)? = nil
    ) throws -> PrivateSystemDiscoveryCoordinatorV1 {
        let context = routeContext ?? C14RouteContext(
            context: RouteResolutionContextV1(
                currentWorkspaceID: workspaceID,
                currentRevision: 7,
                protectedDataAvailable: protectedDataAvailable
            )
        )
        return PrivateSystemDiscoveryCoordinatorV1(
            accessGate: C14AccessGate(permitted: accessPermitted),
            availability: C14Availability(
                optedIn: optedIn,
                featureReason: featureReason,
                appAccessPermitsContent: accessPermitted,
                protectedDataAvailable: protectedDataAvailable
            ),
            projection: projection,
            routeContext: context,
            routeRegistry: try RouteRegistryV1()
        )
    }

    static func projectionDescriptors() throws -> [PrivateSystemDiscoveryProjectionDescriptorV1] {
        try PrivateSystemDiscoveryProjectionDomainV1.allCases.map {
            try PrivateSystemDiscoveryProjectionDescriptorV1(
                domain: $0,
                projectionVersion: 1,
                allowlistSHA256: digest("d"),
                policySHA256: digest("e"),
                indexDefinitionSHA256: digest("f")
            )
        }
    }

    static func availability(
        for workspaceID: WorkspaceID,
        optedIn: Bool = true,
        protectedDataAvailable: Bool = true,
        featureReason: FeatureAvailabilityReasonV1 = .available
    ) throws -> [AppIntentAvailabilityV1] {
        try PrivateSystemDiscoveryActionV1.allCases.map {
            try AppIntentAvailabilityV1(
                workspaceID: workspaceID,
                action: $0,
                optedIn: optedIn,
                featureReason: featureReason,
                appAccessPermitsContent: optedIn,
                protectedDataAvailable: protectedDataAvailable,
                evaluatedAt: now
            )
        }
    }

    static func stateDigest(_ state: PrivateSystemDiscoveryStateMapV1) throws -> String {
        CompatibilityCanonicalV1.sha256(try CompatibilityCanonicalV1.encode(state))
    }

    static func operationID(
        slot: Int,
        operation: PrivateSystemDiscoveryJournalOperationV1,
        workspaceID: WorkspaceID,
        inputSHA256: String
    ) throws -> PrivateSystemDiscoveryOperationIDV1 {
        try PrivateSystemDiscoveryOperationIDV1(
            rawValue: id(slot), operation: operation, workspaceID: workspaceID, inputSHA256: inputSHA256
        )
    }

    static func shareFixture() throws -> (
        workspace: WorkspaceID,
        original: ContentReferenceV1,
        derivative: ContentReferenceV1,
        policy: PrivacyTransformPolicyV1,
        manifest: PrivacyTransformManifestV1,
        review: PrivacyReviewReceiptV1
    ) {
        let mutationID = try MutationIDV1(rawValue: id(600))
        let originalBytes = Data("c14 immutable original bytes".utf8)
        let derivativeBytes = Data("c14 safe local derivative bytes".utf8)
        let originalObserved = try ContentIntegrityV1.observe(
            workspaceID: workspace.rawValue.uuidString.lowercased(),
            contentID: "c14-original", data: originalBytes, mediaType: "image/jpeg"
        )
        let derivativeObserved = try ContentIntegrityV1.observe(
            workspaceID: workspace.rawValue.uuidString.lowercased(),
            contentID: "c14-derivative", data: derivativeBytes, mediaType: "image/jpeg"
        )
        let original = try ContentReferenceV1(
            workspaceID: workspace.rawValue.uuidString.lowercased(), contentID: "c14-original",
            byteLength: Int64(originalBytes.count), mediaType: "image/jpeg",
            digests: originalObserved.digests, byteRole: .immutableOriginal,
            createdAt: "2026-08-31T00:00:00.000Z"
        )
        let derivative = try ContentReferenceV1(
            workspaceID: workspace.rawValue.uuidString.lowercased(), contentID: "c14-derivative",
            byteLength: Int64(derivativeBytes.count), mediaType: "image/jpeg",
            digests: derivativeObserved.digests, byteRole: .derivative,
            createdAt: "2026-08-31T00:00:00.000Z"
        )
        let sourceSHA256 = try XCTUnwrap(originalObserved.digests.digest(for: .sha256)?.hexadecimalValue)
        let derivativeSHA256 = try XCTUnwrap(derivativeObserved.digests.digest(for: .sha256)?.hexadecimalValue)
        let authorReference = try LocalActorReferenceV1(
            actorReferenceID: id(601), workspaceID: workspace, displayName: "C14 operator"
        )
        let author = try ActorSnapshotV1(
            snapshotID: id(602), workspaceID: workspace, actor: authorReference,
            responsibility: .performedBy, displayNameAtTime: "C14 operator", capturedAt: now
        )
        let reviewerReference = try LocalActorReferenceV1(
            actorReferenceID: id(603), workspaceID: workspace, displayName: "C14 reviewer"
        )
        let reviewer = try ActorSnapshotV1(
            snapshotID: id(604), workspaceID: workspace, actor: reviewerReference,
            responsibility: .reviewedBy, displayNameAtTime: "C14 reviewer",
            capturedAt: now.addingTimeInterval(1)
        )
        let policy = try PrivacyTransformPolicyV1(
            policyID: id(605), workspaceID: workspace, purpose: "c14 safe local share",
            audience: .customerReport,
            allowedTransformKinds: [.blur, .pixelate, .solidFill],
            allowedReasons: [.confidentialInformation, .identifyingMark, .person, .unrelatedPrivateDetail, .vehicleIdentifier],
            maximumAgeSeconds: 3_600, effectiveAt: now, mutationID: mutationID
        )
        let region = try PrivacyRegionV1(
            regionID: id(606), workspaceID: workspace, sourceContentID: original.contentID,
            sourceRevision: 1, sourceSHA256: sourceSHA256,
            coordinateSpace: .normalizedImage, orientation: .up,
            sourceBounds: try PrivacyIntegerRectV1(x: 100_000, y: 100_000, width: 300_000, height: 300_000),
            transformKind: .solidFill, reason: .confidentialInformation,
            author: author, order: 0, authoredAt: now, mutationID: mutationID
        )
        let manifest = try PrivacyTransformManifestV1(
            manifestID: id(607), workspaceID: workspace, original: original,
            sourceRevision: 1, sourceSHA256: sourceSHA256, derivative: derivative,
            derivativeSHA256: derivativeSHA256, policy: policy, orderedRegions: [region],
            rendererID: "c14-privacy-renderer", rendererVersion: "1",
            metadataSanitation: try PrivacyMetadataSanitationEvidenceV1(
                sanitizerID: "c14-metadata-sanitizer", sanitizerVersion: "1", result: .complete
            ), renderedAt: now, mutationID: mutationID
        )
        let review = try PrivacyReviewReceiptV1(
            receiptID: id(608), workspaceID: workspace, manifest: manifest, policy: policy,
            reviewer: reviewer, decision: .approved, rationale: "C14 safe local derivative reviewed",
            reviewedAt: now.addingTimeInterval(2), mutationID: mutationID
        )
        return (workspace, original, derivative, policy, manifest, review)
    }
}

private enum C14InjectedFailure: Error, Equatable {
    case protectedIndexEffect
    case stateSave(Int)
    case globalSave(Int)
}

private struct C14SearchSource: SearchCanonicalProjectionSourceV1 {
    let revision: SearchSourceRevisionV1

    func currentSearchSourceRevision() async throws -> SearchSourceRevisionV1 {
        revision
    }

    func searchProjectionPage(
        at source: SearchSourceRevisionV1,
        canonicalOffset: Int,
        limit: Int
    ) async throws -> SearchCanonicalProjectionPageV1 {
        guard source == revision, canonicalOffset == 0, limit == SearchIndexRebuildCoordinatorV1.pageSize else {
            throw SearchIndexRebuildFailureV1.invalidPage
        }
        return try SearchCanonicalProjectionPageV1(
            requestedCanonicalOffset: 0,
            nextCanonicalOffset: 0,
            isComplete: true,
            records: []
        )
    }
}

private struct C14ProductionRebuildProvider: PrivateSystemDiscoveryRebuildRequestProvidingV1 {
    let optedIn: Bool
    let deletionFrontier: UInt64
    let requestedAt: Date

    init(
        optedIn: Bool = true,
        deletionFrontier: UInt64,
        requestedAt: Date
    ) {
        self.optedIn = optedIn
        self.deletionFrontier = deletionFrontier
        self.requestedAt = requestedAt
    }

    func privateSystemDiscoveryRebuildRequest(
        source: SearchSourceRevisionV1,
        operationID: PrivateSystemDiscoveryOperationIDV1
    ) async throws -> PrivateSystemDiscoveryIndexRebuildPayloadV1? {
        let workspaceID = WorkspaceID(rawValue: source.workspaceID)
        let manifest = try PrivateSystemDiscoveryManifestV1()
        let optIn = optedIn
            ? try PrivateSystemDiscoveryOptInV1.enabled(workspaceID: workspaceID, workspaceKind: .real)
            : .disabled
        let availability = try C14TestSupport.availability(
            for: workspaceID,
            optedIn: optedIn,
            featureReason: optedIn ? .available : .workspacePolicyDisabled
        )
        let request = try PrivateSystemDiscoveryRebuildRequestV1(
            operationRawID: operationID.rawValue,
            workspaceID: workspaceID,
            workspaceRevision: source.commitRevision,
            deletionFrontier: deletionFrontier,
            sourceStateSHA256: operationID.inputSHA256,
            requestedAt: requestedAt
        )
        return PrivateSystemDiscoveryIndexRebuildPayloadV1(
            request: request,
            descriptors: try C14TestSupport.projectionDescriptors(),
            manifest: manifest,
            optIn: optIn,
            availability: availability,
            requestedAt: requestedAt
        )
    }
}

private final class C14DurableStateStore: PrivateSystemDiscoveryClientStateStoreV1,
    PrivateSystemDiscoveryGlobalJournalStoreV1, @unchecked Sendable {
    private let lock = NSLock()
    private var durableEnvelope: PrivateSystemDiscoveryDurableEnvelopeV1?
    private var saveCountStorage = 0
    private var globalSaveCountStorage = 0
    var failOnSaveNumbers: Set<Int> = []
    var failOnGlobalSaveNumbers: Set<Int> = []

    func load() throws -> PrivateSystemDiscoveryClientStateV1? {
        lock.withLock { durableEnvelope?.clientState }
    }

    func save(_ state: PrivateSystemDiscoveryClientStateV1) throws {
        try lock.withLock {
            saveCountStorage += 1
            if failOnSaveNumbers.contains(saveCountStorage) {
                throw C14InjectedFailure.stateSave(saveCountStorage)
            }
            try state.validate()
            let candidate = try PrivateSystemDiscoveryDurableEnvelopeV1(
                schemaVersion: 1,
                clientState: state,
                globalJournal: durableEnvelope?.globalJournal ?? .empty
            )
            try candidate.validate()
            durableEnvelope = candidate
        }
    }

    func clear() throws {
        try save(.empty)
    }

    func loadGlobal() throws -> PrivateSystemDiscoveryGlobalJournalV1? {
        lock.withLock { durableEnvelope?.globalJournal ?? .empty }
    }

    func saveGlobal(_ journal: PrivateSystemDiscoveryGlobalJournalV1) throws {
        try lock.withLock {
            globalSaveCountStorage += 1
            if failOnGlobalSaveNumbers.contains(globalSaveCountStorage) {
                throw C14InjectedFailure.globalSave(globalSaveCountStorage)
            }
            try journal.validate()
            let candidate = try PrivateSystemDiscoveryDurableEnvelopeV1(
                schemaVersion: 1,
                clientState: durableEnvelope?.clientState ?? .empty,
                globalJournal: journal
            )
            try candidate.validate()
            durableEnvelope = candidate
        }
    }

    var globalSaveCount: Int {
        lock.withLock { globalSaveCountStorage }
    }
}

private final class C14IndexLifecycleSpy: PrivateSystemDiscoveryIndexLifecyclePortV1, @unchecked Sendable {
    private let index: PrivateSystemDiscoveryIndexStoreV1
    private let lock = NSLock()
    private var lastEraseOperationIDStorage: PrivateSystemDiscoveryOperationIDV1?

    init(index: PrivateSystemDiscoveryIndexStoreV1) {
        self.index = index
    }

    func rebuild(
        operationID: PrivateSystemDiscoveryOperationIDV1,
        workspaceID: WorkspaceID,
        workspaceRevision: UInt64,
        deletionFrontier: UInt64,
        descriptors: [PrivateSystemDiscoveryProjectionDescriptorV1],
        manifest: PrivateSystemDiscoveryManifestV1,
        optIn: PrivateSystemDiscoveryOptInV1,
        availability: [AppIntentAvailabilityV1],
        now: Date
    ) async throws {
        try await index.rebuild(
            operationID: operationID,
            workspaceID: workspaceID,
            workspaceRevision: workspaceRevision,
            deletionFrontier: deletionFrontier,
            descriptors: descriptors,
            manifest: manifest,
            optIn: optIn,
            availability: availability,
            now: now
        )
    }

    func remove(
        operationID: PrivateSystemDiscoveryOperationIDV1,
        workspaceID: WorkspaceID,
        now: Date
    ) async throws {
        try await index.remove(operationID: operationID, workspaceID: workspaceID, now: now)
    }

    func eraseAll(operationID: PrivateSystemDiscoveryOperationIDV1, now: Date) async throws {
        lock.withLock { lastEraseOperationIDStorage = operationID }
        try await index.eraseAll(operationID: operationID, now: now)
    }

    func dropAndRebuild() async throws {
        try await index.dropAndRebuild()
    }

    func state() async throws -> PrivateSystemDiscoveryStateMapV1 {
        try await index.state()
    }

    func journalEntries() async throws -> [PrivateSystemDiscoveryJournalEntryV1] {
        try await index.journalEntries()
    }

    var lastEraseOperationID: PrivateSystemDiscoveryOperationIDV1? {
        lock.withLock { lastEraseOperationIDStorage }
    }
}

private final class C14ProtectedIndexClient: PrivateSystemDiscoveryProtectedIndexClientV1, @unchecked Sendable {
    private let lock = NSLock()
    private var indexedItems: [String: PrivateSystemDiscoveryIndexItemV1] = [:]
    private var replacementCallCountStorage = 0
    private var deletionCallCountStorage = 0
    private var deleteAllCallCountStorage = 0
    var failNextReplacement = false
    var failNextDeletion = false

    func replaceItems(
        deleting identifiers: [String],
        with items: [PrivateSystemDiscoveryIndexItemV1]
    ) async throws {
        try lock.withLock {
            replacementCallCountStorage += 1
            if failNextReplacement {
                failNextReplacement = false
                throw C14InjectedFailure.protectedIndexEffect
            }
            for identifier in identifiers { indexedItems.removeValue(forKey: identifier) }
            for item in items { indexedItems[item.uniqueIdentifier] = item }
        }
    }

    func deleteItems(withIdentifiers identifiers: [String]) async throws {
        try lock.withLock {
            deletionCallCountStorage += 1
            if failNextDeletion {
                failNextDeletion = false
                throw C14InjectedFailure.protectedIndexEffect
            }
            for identifier in identifiers { indexedItems.removeValue(forKey: identifier) }
        }
    }

    func deleteAllItems() async throws {
        lock.withLock {
            deleteAllCallCountStorage += 1
            indexedItems.removeAll()
        }
    }

    func items() -> [PrivateSystemDiscoveryIndexItemV1] {
        lock.lock()
        defer { lock.unlock() }
        return indexedItems.values.sorted { $0.uniqueIdentifier < $1.uniqueIdentifier }
    }

    var replacementCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return replacementCallCountStorage
    }

    var deletionCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return deletionCallCountStorage
    }

    var deleteAllCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return deleteAllCallCountStorage
    }
}

private struct C14AccessGate: AppAccessGatePortV1, Sendable {
    let permitted: Bool

    func currentState() async -> AppAccessStateV1 {
        permitted ? .disabled : .locked(reason: .protectedDataUnavailable)
    }

    func lock(reason: AppLockReasonV1) async {}

    func authenticate(trigger: LocalAuthenticationTriggerV1) async -> LocalAuthenticationOutcomeV1 {
        permitted ? .authenticated : .authenticationFailed
    }

    func requireContentAccess() async throws {
        guard permitted else { throw AppAccessContractFailureV1.accessDenied }
    }
}

private struct C14Availability: PrivateSystemDiscoveryAvailabilityPortV1, Sendable {
    let optedIn: Bool
    let featureReason: FeatureAvailabilityReasonV1
    let appAccessPermitsContent: Bool
    let protectedDataAvailable: Bool

    func availability(
        workspaceID: WorkspaceID,
        action: PrivateSystemDiscoveryActionV1,
        evaluatedAt: Date
    ) async throws -> AppIntentAvailabilityV1 {
        try AppIntentAvailabilityV1(
            workspaceID: workspaceID,
            action: action,
            optedIn: optedIn,
            featureReason: featureReason,
            appAccessPermitsContent: appAccessPermitsContent,
            protectedDataAvailable: protectedDataAvailable,
            evaluatedAt: evaluatedAt
        )
    }
}

private struct C14Projection: PrivateSystemDiscoveryProjectionPortV1, Sendable {
    func resolvePrivateRead(workspaceID: WorkspaceID, opaqueParameterToken: String) async throws -> PrivateSystemDiscoveryReadProjectionV1 {
        try PrivateSystemDiscoveryReadProjectionV1(
            workspaceID: workspaceID,
            resultIDs: [C14TestSupport.id(701), C14TestSupport.id(702)],
            querySHA256: C14TestSupport.digest("a")
        )
    }
}

private struct C14FailingProjection: PrivateSystemDiscoveryProjectionPortV1, Sendable {
    func resolvePrivateRead(workspaceID: WorkspaceID, opaqueParameterToken: String) async throws -> PrivateSystemDiscoveryReadProjectionV1 {
        throw PrivateSystemDiscoveryFailureV1.privateResolutionBeforeAccess
    }
}

private struct C14RouteContext: PrivateSystemDiscoveryRouteContextPortV1, Sendable {
    let context: RouteResolutionContextV1

    func routeContext(workspaceID: WorkspaceID) async throws -> RouteResolutionContextV1 {
        context
    }
}

import XCTest
@testable import FieldEvidenceApp

@MainActor
final class V23SearchReconciliationTests: XCTestCase {
    func testGuardedProjectionDropRejectsRevokedAndWrongConsumerTokensWithoutChangingBytes() async throws {
        let gate = AppAccessGateV1(
            setting: .value(.init(isEnabled: true)),
            authentication: V23Authentication(outcomes: [.authenticated, .authenticated]),
            clock: V23Clock(), identifiers: V23IDs())
        let firstAuthentication = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(firstAuthentication, .authenticated)
        let token = try await gate.beginContentRead(for: .searchRebuild)
        let root = V23Fixture.root("drop-original-token")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalSearchIndexStoreV1(applicationSupportURL: root)
        let source = try V23Fixture.source()
        let registry = try SwiftDataSearchCanonicalProjectionSourceV1.makeRegistry()
        try await store.replaceProjection(source: source, records: [], registry: registry)
        let path = root.appendingPathComponent(LocalSearchIndexStoreV1.directoryName)
            .appendingPathComponent(LocalSearchIndexStoreV1.fileName)
        let bytes = try Data(contentsOf: path)
        let revision = try await store.revision()
        let publication = await store.publicationToken()

        await gate.lock(reason: .lockNow)
        let secondAuthentication = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(secondAuthentication, .authenticated)
        let wrongConsumer = try await gate.beginContentRead(for: .search)
        for denied in [token, wrongConsumer] {
            do {
                try await store.dropProjection(contentReadToken: denied)
                XCTFail("A revoked or wrong-consumer token deleted the projection")
            } catch {
                XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
            }
            XCTAssertEqual(try Data(contentsOf: path), bytes)
            let retainedRevision = try await store.revision()
            let retainedPublication = await store.publicationToken()
            XCTAssertEqual(retainedRevision, revision)
            XCTAssertEqual(retainedPublication, publication)
        }
        let fresh = try await gate.beginContentRead(for: .searchRebuild)
        try await store.dropProjection(contentReadToken: fresh)
        let emptyRevision = try await store.revision()
        let changedPublication = await store.publicationToken()
        XCTAssertNil(emptyRevision)
        XCTAssertNotEqual(changedPublication, publication)
    }

    #if DEBUG
    func testActualRebuildRevocationBeforeProjectionDropPreservesOldBytesAndFreshRetryCompletes() async throws {
        let cases: [(String, UInt64, UInt64, Bool, SearchIndexReconciliationV1)] = [
            ("stale", 1, 2, false, .staleDropAndRebuild),
            ("ahead", 2, 1, false, .aheadDropAndRebuild),
            ("generation", 1, 1, true, .wrongGenerationDropAndRebuild)
        ]
        for (label, oldCommit, newCommit, changesGeneration, expected) in cases {
            let gate = AppAccessGateV1(
                setting: .value(.init(isEnabled: true)),
                authentication: V23Authentication(outcomes: [.authenticated, .authenticated]),
                clock: V23Clock(), identifiers: V23IDs())
            let authenticated = await gate.authenticate(trigger: .unlock)
            XCTAssertEqual(authenticated, .authenticated)
            let root = V23Fixture.root("drop-boundary-" + label)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = try LocalSearchIndexStoreV1(applicationSupportURL: root)
            let old = try SearchSourceRevisionV1(workspaceID: UUID(), generationID: UUID(),
                                                commitRevision: oldCommit)
            let target = try SearchSourceRevisionV1(workspaceID: old.workspaceID,
                generationID: changesGeneration ? UUID() : old.generationID,
                commitRevision: newCommit)
            let registry = try SwiftDataSearchCanonicalProjectionSourceV1.makeRegistry()
            try await store.replaceProjection(source: old, records: [], registry: registry)
            let path = root.appendingPathComponent(LocalSearchIndexStoreV1.directoryName)
                .appendingPathComponent(LocalSearchIndexStoreV1.fileName)
            let bytes = try Data(contentsOf: path)
            let revision = try await store.revision()
            let publication = await store.publicationToken()
            let staging = try await store.rebuildStaging(publicationToken: publication)
            XCTAssertEqual(SearchIndexReconciliationV1.disposition(source: target, index: revision), expected)
            let coordinator = try SearchIndexRebuildCoordinatorV1(store: store,
                source: V23ImmediateCanonicalSource(revision: target), registry: registry,
                privateSystemDiscoveryIndex: nil, privateSystemDiscoverySource: nil)
            let boundary = V23ProjectionDropRevocationProbe(gate: gate)
            await coordinator.setBeforeProjectionDropForTesting { await boundary.revokeAndReauthenticate() }
            do {
                _ = try await coordinator.rebuildIfNeeded(accessGate: gate)
                XCTFail("The original rebuild erased its projection after access revocation")
            } catch {
                XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
            }
            let calls = await boundary.calls
            let outcome = await boundary.outcome
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(outcome, .authenticated)
            XCTAssertEqual(try Data(contentsOf: path), bytes)
            let retainedRevision = try await store.revision()
            let retainedPublication = await store.publicationToken()
            let retainedStaging = try await store.rebuildStaging(publicationToken: publication)
            XCTAssertEqual(retainedRevision, revision)
            XCTAssertEqual(retainedPublication, publication)
            XCTAssertEqual(retainedStaging, staging)

            await coordinator.setBeforeProjectionDropForTesting(nil)
            let fresh = try await coordinator.rebuildIfNeeded(accessGate: gate)
            XCTAssertEqual(fresh.disposition, expected)
            XCTAssertEqual(fresh.source, target)
            XCTAssertEqual(fresh.indexedRecordCount, 0)
            let finalRevision = try await store.revision()
            XCTAssertEqual(SearchIndexReconciliationV1.disposition(source: target, index: finalRevision), .current)
        }
    }
    #endif

    func testConcreteTokenDeniesLocalProjectionCreationAfterLock() async throws {
        let authentication = V23Authentication(outcomes: [.authenticated, .authenticated])
        let gate = AppAccessGateV1(
            setting: .value(.init(isEnabled: true)), authentication: authentication,
            clock: V23Clock(), identifiers: V23IDs()
        )
        let outcome = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(outcome, .authenticated)
        let token = try await gate.beginContentRead(for: .searchRebuild)
        let source = try V23Fixture.source()
        let root = V23Fixture.root("local-denial")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalSearchIndexStoreV1(applicationSupportURL: root)
        await gate.lock(reason: .lockNow)
        let fence = await store.publicationToken()
        do {
            try await store.replaceProjection(
                source: source, records: [], registry: try SwiftDataSearchCanonicalProjectionSourceV1.makeRegistry(),
                publicationToken: fence, contentReadToken: token
            )
            XCTFail("a revoked token must not create a local projection")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
        let path = root.appendingPathComponent(LocalSearchIndexStoreV1.directoryName)
            .appendingPathComponent(LocalSearchIndexStoreV1.fileName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
        let revision = try await store.revision()
        XCTAssertNil(revision)
    }

    func testStalePublicationTokenCannotCreateAbsentProjectionFile() async throws {
        let root = V23Fixture.root("stale-publication")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalSearchIndexStoreV1(applicationSupportURL: root)
        let token = await store.publicationToken()
        try LocalSearchIndexStoreV1.synchronouslyEraseAll(applicationSupportURL: root)
        let source = try V23Fixture.source()
        do {
            try await store.replaceProjection(source: source, records: [], registry: try SwiftDataSearchCanonicalProjectionSourceV1.makeRegistry(), publicationToken: token)
            XCTFail("stale path token recreated an absent projection")
        } catch { XCTAssertEqual(error as? LocalSearchIndexStoreFailureV1, .staleMutation) }
        let path = root.appendingPathComponent(LocalSearchIndexStoreV1.directoryName).appendingPathComponent(LocalSearchIndexStoreV1.fileName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
    }

    func testGuardedDiscoveryRejectsUnsupportedClientWithoutEffect() async throws {
        let authentication = V23Authentication(outcomes: [.authenticated])
        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)), authentication: authentication, clock: V23Clock(), identifiers: V23IDs())
        let unlock = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(unlock, .authenticated)
        let token = try await gate.beginContentRead(for: .searchRebuild)
        let client = V23DiscoveryClient(); let state = V23DiscoveryStateStore()
        let index = try PrivateSystemDiscoveryIndexStoreV1(indexClient: client, clientStateStore: state, globalJournalStore: state)
        let input = try V23DiscoveryRequest.make()
        do {
            try await index.rebuild(operationID: input.operationID, workspaceID: input.workspace, workspaceRevision: 1, deletionFrontier: 0, descriptors: input.descriptors, manifest: input.manifest, optIn: input.optIn, availability: input.availability, now: input.now, contentReadToken: token)
            XCTFail("unguarded client received a guarded submission")
        } catch { XCTAssertEqual(error as? PrivateSystemDiscoveryFailureV1, .unavailable) }
        XCTAssertTrue(client.items().isEmpty)
        XCTAssertNil(try state.load())
    }

    func testLegacyPendingEncodingOmitsAuthorityMarkerAndRemainsReplayCompatible() async throws {
        let input = try V23DiscoveryRequest.make()
        let request = try PrivateSystemDiscoveryRebuildRequestV1(operationRawID: input.operationID.rawValue, workspaceID: input.workspace, workspaceRevision: 1, deletionFrontier: 0, sourceStateSHA256: input.operationID.inputSHA256, requestedAt: input.now)
        let payload = PrivateSystemDiscoveryIndexRebuildPayloadV1(request: request, descriptors: input.descriptors, manifest: input.manifest, optIn: input.optIn, availability: input.availability, requestedAt: input.now)
        let empty = try PrivateSystemDiscoveryStateMapV1(workspaces: [])
        let workspaceState = try PrivateSystemDiscoveryWorkspaceStateV1(workspaceID: input.workspace,
            workspaceRevision: 1, projections: input.descriptors, deletionFrontier: 0, rebuiltAt: input.now)
        let result = try PrivateSystemDiscoveryStateMapV1(workspaces: [workspaceState])
        let digest = CompatibilityCanonicalV1.sha256(try CompatibilityCanonicalV1.encode(result))
        let pending = PrivateSystemDiscoveryPendingOperationV1(operationID: input.operationID, operation: .rebuild, workspaceID: input.workspace, expectedPriorStateSHA256: input.operationID.inputSHA256, resultingStateSHA256: digest, rebuild: payload, preparedAt: input.now, requiresContentAuthority: nil)
        let journal = try PrivateSystemDiscoveryJournalEntryV1(operationID: input.operationID, expectedPriorStateSHA256: input.operationID.inputSHA256, resultingStateSHA256: nil, state: .prepared, recordedAt: input.now)
        let state = try PrivateSystemDiscoveryClientStateV1(stateMap: empty, knownWorkspaceIDs: [input.workspace], workspaceInventory: [.init(workspaceID: input.workspace, deletionFrontier: 0)], journal: [journal], pendingOperation: pending)
        let bytes = try CompatibilityCanonicalV1.encode(state)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("requiresContentAuthority"))
        let decoded = try CompatibilityCanonicalV1.decode(PrivateSystemDiscoveryClientStateV1.self, from: bytes)
        XCTAssertNil(decoded.pendingOperation?.requiresContentAuthority)
        XCTAssertEqual(try CompatibilityCanonicalV1.encode(decoded), bytes)
        let durable = V23DiscoveryStateStore()
        try durable.save(decoded)
        let client = V23DiscoveryClient()
        let reopened = try PrivateSystemDiscoveryIndexStoreV1(indexClient: client,
            clientStateStore: durable, globalJournalStore: durable)
        let replayed = try await reopened.state()
        XCTAssertEqual(replayed, result)
        XCTAssertEqual(client.items().count, PrivateSystemDiscoveryActionV1.allCases.count)
        XCTAssertNil(try durable.load()?.pendingOperation)
        XCTAssertEqual(try durable.load()?.journal.map(\.state), [.prepared, .effectApplied, .committed])
    }

    func testGuardedDiscoverySubmissionCannotStartAfterDeletionSuspensionRevokesToken() async throws {
        let authentication = V23Authentication(outcomes: [.authenticated, .authenticated])
        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)), authentication: authentication, clock: V23Clock(), identifiers: V23IDs())
        let unlock = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(unlock, .authenticated)
        let token = try await gate.beginContentRead(for: .searchRebuild)
        let client = V23SuspendingGuardedDiscoveryClient()
        let state = V23DiscoveryStateStore()
        let index = try PrivateSystemDiscoveryIndexStoreV1(indexClient: client, clientStateStore: state, globalJournalStore: state)
        let input = try V23DiscoveryRequest.make()
        let task = Task { try await index.rebuild(operationID: input.operationID, workspaceID: input.workspace, workspaceRevision: 1, deletionFrontier: 0, descriptors: input.descriptors, manifest: input.manifest, optIn: input.optIn, availability: input.availability, now: input.now, contentReadToken: token) }
        await client.waitUntilDeletionCompletes()
        await gate.lock(reason: .lockNow)
        await client.resumeDeletion()
        do { _ = try await task.value; XCTFail("revoked authority submitted Spotlight indexing") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        let submissionsAfterRevocation = await client.submissionCount()
        XCTAssertEqual(submissionsAfterRevocation, 0)
        let persisted = try XCTUnwrap(try state.load()?.pendingOperation)
        XCTAssertEqual(persisted.requiresContentAuthority, true)
        let reopened = try PrivateSystemDiscoveryIndexStoreV1(indexClient: client, clientStateStore: state, globalJournalStore: state)
        do { _ = try await reopened.state(); XCTFail("cold unguarded replay admitted marked pending work") }
        catch { XCTAssertEqual(error as? PrivateSystemDiscoveryFailureV1, .unavailable) }
        let secondUnlock = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(secondUnlock, .authenticated)
        let freshToken = try await gate.beginContentRead(for: .searchRebuild)
        let retainedState = try state.load()
        do {
            try await reopened.rebuild(operationID: input.operationID, workspaceID: input.workspace,
                workspaceRevision: 2, deletionFrontier: 0, descriptors: input.descriptors,
                manifest: input.manifest, optIn: input.optIn, availability: input.availability,
                now: input.now, contentReadToken: freshToken)
            XCTFail("changed source resumed a marked original request")
        } catch { XCTAssertEqual(error as? PrivateSystemDiscoveryFailureV1, .unavailable) }
        do {
            try await reopened.rebuild(operationID: input.operationID, workspaceID: input.workspace,
                workspaceRevision: 1, deletionFrontier: 0, descriptors: input.descriptors,
                manifest: input.manifest, optIn: .disabled, availability: input.availability,
                now: input.now, contentReadToken: freshToken)
            XCTFail("opt-out discarded marked pending ownership")
        } catch { XCTAssertEqual(error as? PrivateSystemDiscoveryFailureV1, .unavailable) }
        XCTAssertEqual(try state.load(), retainedState)
        let later = input.now.addingTimeInterval(60)
        let laterAvailability = try PrivateSystemDiscoveryActionV1.allCases.map {
            try AppIntentAvailabilityV1(workspaceID: input.workspace, action: $0, optedIn: true,
                featureReason: .available, appAccessPermitsContent: true,
                protectedDataAvailable: true, evaluatedAt: later)
        }
        try await reopened.rebuild(operationID: input.operationID, workspaceID: input.workspace, workspaceRevision: 1, deletionFrontier: 0, descriptors: input.descriptors, manifest: input.manifest, optIn: input.optIn, availability: laterAvailability, now: later, contentReadToken: freshToken)
        let submissionsAfterResume = await client.submissionCount()
        XCTAssertEqual(submissionsAfterResume, 1)
        let resumedState = try XCTUnwrap(try state.load())
        XCTAssertNil(resumedState.pendingOperation)
        XCTAssertEqual(resumedState.stateMap.workspaces.first?.rebuiltAt, input.now)
        XCTAssertEqual(resumedState.journal.map(\.recordedAt), [input.now, input.now, input.now])
    }

    func testConcreteRebuildGateReadsCurrentProjectionWithRebuildAuthority() async throws {
        let authentication = V23Authentication(outcomes: [.authenticated])
        let gate = AppAccessGateV1(
            setting: .value(.init(isEnabled: true)), authentication: authentication,
            clock: V23Clock(), identifiers: V23IDs()
        )
        let unlock = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(unlock, .authenticated)
        let source = try V23Fixture.source()
        let root = V23Fixture.root("current-rebuild-gate")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalSearchIndexStoreV1(applicationSupportURL: root)
        let registry = try SwiftDataSearchCanonicalProjectionSourceV1.makeRegistry()
        try await store.replaceProjection(source: source, records: [], registry: registry)
        let client = V23ControlledDiscoveryClient()
        let durable = V23DiscoveryStateStore()
        let index = try PrivateSystemDiscoveryIndexStoreV1(indexClient: client,
            clientStateStore: durable, globalJournalStore: durable)
        let policy = V23DiscoveryPolicy(selection: try .enabled(
            workspaceID: WorkspaceID(rawValue: source.workspaceID), workspaceKind: .real))
        let coordinator = try SearchIndexRebuildCoordinatorV1(
            store: store, source: V23PausedCanonicalSource(revision: source), registry: registry,
            privateSystemDiscoveryIndex: index,
            privateSystemDiscoverySource: V23DiscoveryFixture.productionSource(policy)
        )
        let result = try await coordinator.rebuildIfNeeded(accessGate: gate)
        XCTAssertEqual(result.disposition, .current)
        XCTAssertEqual(result.indexedRecordCount, 0)
        let items = await client.items()
        XCTAssertEqual(items.count, PrivateSystemDiscoveryActionV1.allCases.count)
        _ = try await coordinator.rebuildIfNeeded(accessGate: gate)
        let submissions = await client.submissionCount()
        XCTAssertEqual(submissions, 1)
    }
    func testGuardedCoordinatorAbsentBuildRetainsPendingAndFreshCurrentRetryCompletes() async throws {
        let source = try V23Fixture.source()
        let root = V23Fixture.root("absent-current-retry")
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
            authentication: V23Authentication(outcomes: [.authenticated, .authenticated]),
            clock: V23Clock(), identifiers: V23IDs())
        let unlock = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(unlock, .authenticated)
        let policy = V23DiscoveryPolicy(selection: try .enabled(
            workspaceID: WorkspaceID(rawValue: source.workspaceID), workspaceKind: .real))
        let client = V23ControlledDiscoveryClient(pause: .deletion)
        let durable = V23DiscoveryStateStore()
        let index = try PrivateSystemDiscoveryIndexStoreV1(indexClient: client,
            clientStateStore: durable, globalJournalStore: durable)
        let store = try LocalSearchIndexStoreV1(applicationSupportURL: root)
        let coordinator = try SearchIndexRebuildCoordinatorV1(store: store,
            source: V23ImmediateCanonicalSource(revision: source),
            registry: try SwiftDataSearchCanonicalProjectionSourceV1.makeRegistry(),
            privateSystemDiscoveryIndex: index,
            privateSystemDiscoverySource: V23DiscoveryFixture.productionSource(policy))
        let task = Task { try await coordinator.rebuildIfNeeded(accessGate: gate) }
        await client.waitUntilPaused()
        let pending = try XCTUnwrap(try durable.load()?.pendingOperation)
        XCTAssertEqual(pending.requiresContentAuthority, true)
        let localRevision = try await store.revision()
        XCTAssertEqual(localRevision?.indexedCommitRevision, source.commitRevision)
        await gate.lock(reason: .lockNow)
        await client.resume()
        do { _ = try await task.value; XCTFail("revoked absent rebuild published discovery") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        let beforeRetry = await client.submissionCount()
        XCTAssertEqual(beforeRetry, 0)
        let reopened = try PrivateSystemDiscoveryIndexStoreV1(indexClient: client,
            clientStateStore: durable, globalJournalStore: durable)
        do { _ = try await reopened.journalEntries(); XCTFail("unguarded journal read replayed marked work") }
        catch { XCTAssertEqual(error as? PrivateSystemDiscoveryFailureV1, .unavailable) }
        let secondUnlock = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(secondUnlock, .authenticated)
        let retry = try SearchIndexRebuildCoordinatorV1(
            store: LocalSearchIndexStoreV1(applicationSupportURL: root),
            source: V23ImmediateCanonicalSource(revision: source),
            registry: try SwiftDataSearchCanonicalProjectionSourceV1.makeRegistry(),
            privateSystemDiscoveryIndex: reopened,
            privateSystemDiscoverySource: V23DiscoveryFixture.productionSource(policy))
        let result = try await retry.rebuildIfNeeded(accessGate: gate)
        XCTAssertEqual(result.disposition, .current)
        let final = try XCTUnwrap(try durable.load())
        XCTAssertNil(final.pendingOperation)
        XCTAssertEqual(Set(final.journal.map(\.operationID)), [pending.operationID.rawValue])
        XCTAssertEqual(final.journal.map(\.state), [.prepared, .effectApplied, .committed])
        let submissions = await client.submissionCount()
        XCTAssertEqual(submissions, 1)
    }

    func testGuardedLateIndexCallbackRetainsOriginalPendingWithoutLocalAcceptance() async throws {
        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
            authentication: V23Authentication(outcomes: [.authenticated, .authenticated]),
            clock: V23Clock(), identifiers: V23IDs())
        let unlock = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(unlock, .authenticated)
        let token = try await gate.beginContentRead(for: .searchRebuild)
        let input = try V23DiscoveryRequest.make()
        let client = V23ControlledDiscoveryClient(pause: .callback)
        let durable = V23DiscoveryStateStore()
        let index = try PrivateSystemDiscoveryIndexStoreV1(indexClient: client,
            clientStateStore: durable, globalJournalStore: durable)
        let task = Task { try await input.rebuild(index, token: token) }
        await client.waitUntilPaused()
        let prepared = try XCTUnwrap(try durable.load())
        await gate.lock(reason: .lockNow)
        await client.resume()
        do { try await task.value; XCTFail("late callback gained local acceptance") }
        catch { XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied) }
        XCTAssertEqual(try durable.load(), prepared)
        let lateItems = await client.items()
        XCTAssertEqual(lateItems.count, PrivateSystemDiscoveryActionV1.allCases.count)
        // The submitted OS effect can arrive late. Neither recovery nor removal
        // is allowed to erase the pending owner or invent a completed drain.
        let reopened = try PrivateSystemDiscoveryIndexStoreV1(indexClient: client,
            clientStateStore: durable, globalJournalStore: durable)
        let removal = try PrivateSystemDiscoveryOperationIDV1(rawValue: UUID(), operation: .removal,
            workspaceID: input.workspace, inputSHA256: String(repeating: "b", count: 64))
        do { try await reopened.remove(operationID: removal, workspaceID: input.workspace, now: input.now); XCTFail("removal silently discarded marked work") }
        catch { XCTAssertEqual(error as? PrivateSystemDiscoveryFailureV1, .unavailable) }
        XCTAssertEqual(try durable.load(), prepared)
        do { try await reopened.dropAndRebuild(); XCTFail("drop discarded marked pending ownership") }
        catch { XCTAssertEqual(error as? PrivateSystemDiscoveryFailureV1, .unavailable) }
        XCTAssertEqual(try durable.load(), prepared)
        let retainedGlobal = try durable.loadGlobal()
        do { try await reopened.eraseAll(operationID: removal, now: input.now); XCTFail("erase stranded marked pending behind a new global operation") }
        catch { XCTAssertEqual(error as? PrivateSystemDiscoveryFailureV1, .unavailable) }
        XCTAssertEqual(try durable.load(), prepared)
        XCTAssertEqual(try durable.loadGlobal(), retainedGlobal)
        let retainedItems = await client.items()
        let deleteAllCalls = await client.deleteAllCount()
        let retainedSubmissions = await client.submissionCount()
        XCTAssertEqual(retainedItems, lateItems)
        XCTAssertEqual(deleteAllCalls, 0)
        XCTAssertEqual(retainedSubmissions, 1)
        let unlockAgain = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(unlockAgain, .authenticated)
        let fresh = try await gate.beginContentRead(for: .searchRebuild)
        try await input.rebuild(reopened, token: fresh)
        let final = try XCTUnwrap(try durable.load())
        XCTAssertNil(final.pendingOperation)
        XCTAssertEqual(Set(final.journal.map(\.operationID)), [input.operationID.rawValue])
        let submissions = await client.submissionCount()
        XCTAssertEqual(submissions, 2)
    }

    func testGuardedOptOutRemovesExistingActionsAndReenrollmentEffectAppliedResumesCold() async throws {
        let source = try V23Fixture.source()
        let workspace = WorkspaceID(rawValue: source.workspaceID)
        let root = V23Fixture.root("guarded-reenrollment")
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
            authentication: V23Authentication(outcomes: [.authenticated]),
            clock: V23Clock(), identifiers: V23IDs())
        let unlock = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(unlock, .authenticated)
        let enabled = try PrivateSystemDiscoveryOptInV1.enabled(workspaceID: workspace, workspaceKind: .real)
        let policy = V23DiscoveryPolicy(selection: enabled)
        let client = V23ControlledDiscoveryClient()
        let durable = V23DiscoveryStateStore()
        let index = try PrivateSystemDiscoveryIndexStoreV1(indexClient: client,
            clientStateStore: durable, globalJournalStore: durable)
        let store = try LocalSearchIndexStoreV1(applicationSupportURL: root)
        let registry = try SwiftDataSearchCanonicalProjectionSourceV1.makeRegistry()
        let coordinator = try SearchIndexRebuildCoordinatorV1(store: store,
            source: V23ImmediateCanonicalSource(revision: source), registry: registry,
            privateSystemDiscoveryIndex: index,
            privateSystemDiscoverySource: V23DiscoveryFixture.productionSource(policy))
        let initial = try await coordinator.rebuildIfNeeded(accessGate: gate)
        XCTAssertEqual(initial.disposition, .absentBuild)
        let initialID = try XCTUnwrap(try durable.load()?.journal.last?.operationID)
        let initialItems = await client.items()
        XCTAssertEqual(initialItems.count, PrivateSystemDiscoveryActionV1.allCases.count)
        await policy.setSelection(.disabled)
        _ = try await coordinator.rebuildIfNeeded(accessGate: gate)
        let removedItems = await client.items()
        XCTAssertTrue(removedItems.isEmpty)
        XCTAssertTrue(try XCTUnwrap(try durable.load()).stateMap.workspaces.isEmpty)
        let removedState = try durable.load()
        _ = try await coordinator.rebuildIfNeeded(accessGate: gate)
        XCTAssertEqual(try durable.load(), removedState)
        await policy.setSelection(enabled)
        durable.failNextCommit()
        do { _ = try await coordinator.rebuildIfNeeded(accessGate: gate); XCTFail("injected final commit failure was missed") }
        catch { XCTAssertEqual(error as? PrivateSystemDiscoveryFailureV1, .unavailable) }
        let effectApplied = try XCTUnwrap(try durable.load())
        let pending = try XCTUnwrap(effectApplied.pendingOperation)
        XCTAssertEqual(pending.requiresContentAuthority, true)
        XCTAssertNotEqual(pending.operationID.rawValue, initialID)
        XCTAssertEqual(effectApplied.journal.last?.state, .effectApplied)
        XCTAssertEqual(effectApplied.stateMap.workspaces.map(\.workspaceID), [workspace])
        let encoded = try CompatibilityCanonicalV1.encode(effectApplied)
        let coldDurable = V23DiscoveryStateStore()
        try coldDurable.save(CompatibilityCanonicalV1.decode(PrivateSystemDiscoveryClientStateV1.self, from: encoded))
        let reopened = try PrivateSystemDiscoveryIndexStoreV1(indexClient: client,
            clientStateStore: coldDurable, globalJournalStore: coldDurable)
        do { _ = try await reopened.state(); XCTFail("cold effectApplied committed without authority") }
        catch { XCTAssertEqual(error as? PrivateSystemDiscoveryFailureV1, .unavailable) }
        XCTAssertEqual(try coldDurable.load(), effectApplied)
        let retry = try SearchIndexRebuildCoordinatorV1(store: store,
            source: V23ImmediateCanonicalSource(revision: source), registry: registry,
            privateSystemDiscoveryIndex: reopened,
            privateSystemDiscoverySource: V23DiscoveryFixture.productionSource(policy))
        let result = try await retry.rebuildIfNeeded(accessGate: gate)
        XCTAssertEqual(result.disposition, .current)
        let committed = try XCTUnwrap(try coldDurable.load())
        XCTAssertNil(committed.pendingOperation)
        XCTAssertEqual(committed.journal.last?.operationID, pending.operationID.rawValue)
        XCTAssertEqual(committed.journal.last?.state, .committed)
        _ = try await retry.rebuildIfNeeded(accessGate: gate)
        let submissions = await client.submissionCount()
        XCTAssertEqual(submissions, 2, "effectApplied recovery and current reconciliation must not resubmit")
    }

    func testOldCommittedDiscoveryCannotOverwriteNewerEnrollmentAfterRemoval() async throws {
        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
            authentication: V23Authentication(outcomes: [.authenticated]),
            clock: V23Clock(), identifiers: V23IDs())
        let unlock = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(unlock, .authenticated)
        let token = try await gate.beginContentRead(for: .searchRebuild)
        let original = try V23DiscoveryRequest.make()
        let client = V23ControlledDiscoveryClient()
        let durable = V23DiscoveryStateStore()
        let index = try PrivateSystemDiscoveryIndexStoreV1(indexClient: client,
            clientStateStore: durable, globalJournalStore: durable)
        try await original.rebuild(index, token: token)
        let removal = try PrivateSystemDiscoveryOperationIDV1(rawValue: UUID(), operation: .removal,
            workspaceID: original.workspace, inputSHA256: String(repeating: "b", count: 64))
        try await index.remove(operationID: removal, workspaceID: original.workspace, now: original.now)
        let newer = try PrivateSystemDiscoveryOperationIDV1(rawValue: UUID(), operation: .rebuild,
            workspaceID: original.workspace, inputSHA256: String(repeating: "c", count: 64))
        try await index.rebuild(operationID: newer, workspaceID: original.workspace,
            workspaceRevision: 2, deletionFrontier: 0, descriptors: original.descriptors,
            manifest: original.manifest, optIn: original.optIn, availability: original.availability,
            now: original.now, contentReadToken: token)
        let retained = try durable.load()
        do { try await original.rebuild(index, token: token); XCTFail("old operation replaced the newer active enrollment") }
        catch { XCTAssertEqual(error as? PrivateSystemDiscoveryFailureV1, .unavailable) }
        do {
            try await index.rebuild(operationID: original.operationID, workspaceID: original.workspace,
                workspaceRevision: 1, deletionFrontier: 0, descriptors: original.descriptors,
                manifest: original.manifest, optIn: original.optIn, availability: original.availability,
                now: original.now)
            XCTFail("legacy replay replaced the newer active enrollment")
        } catch { XCTAssertEqual(error as? PrivateSystemDiscoveryFailureV1, .unavailable) }
        XCTAssertEqual(try durable.load(), retained)
        let submissions = await client.submissionCount()
        XCTAssertEqual(submissions, 2)
    }

    func testConcreteSearchGateRejectsLockUnlockABAAfterSuspendedProjection() async throws {
        let authentication = V23Authentication(outcomes: [.authenticated, .authenticated])
        let gate = AppAccessGateV1(
            setting: .value(.init(isEnabled: true)), authentication: authentication,
            clock: V23Clock(), identifiers: V23IDs()
        )
        let firstAuthentication = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(firstAuthentication, .authenticated)
        let probe = V23PausedProjectionProbe()
        let coordinator = SearchCoordinatorV1(index: probe)
        let source = try V23Fixture.source()
        let plan = try coordinator.makePlan(query: "asset", sourceRevision: source.commitRevision)
        let registry = try SwiftDataSearchCanonicalProjectionSourceV1.makeRegistry()
        let task = Task {
            try await coordinator.search(plan, source: source, registry: registry, accessGate: gate)
        }
        await probe.waitUntilProjectionStarts()
        await gate.lock(reason: .lockNow)
        let secondAuthentication = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(secondAuthentication, .authenticated)
        await probe.resume()
        do {
            _ = try await task.value
            XCTFail("the original read token must not survive lock/unlock ABA")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
    }

    func testConcreteRebuildGateRejectsLockUnlockABABeforePublication() async throws {
        let authentication = V23Authentication(outcomes: [.authenticated, .authenticated])
        let gate = AppAccessGateV1(
            setting: .value(.init(isEnabled: true)), authentication: authentication,
            clock: V23Clock(), identifiers: V23IDs()
        )
        let firstAuthentication = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(firstAuthentication, .authenticated)
        let source = try V23Fixture.source()
        let pausedSource = V23PausedCanonicalSource(revision: source)
        let root = V23Fixture.root("rebuild-gate")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalSearchIndexStoreV1(applicationSupportURL: root)
        let coordinator = try SearchIndexRebuildCoordinatorV1(
            store: store, source: pausedSource,
            registry: try SwiftDataSearchCanonicalProjectionSourceV1.makeRegistry(),
            privateSystemDiscoveryIndex: nil, privateSystemDiscoverySource: nil
        )
        let task = Task { try await coordinator.rebuildIfNeeded(accessGate: gate) }
        await pausedSource.waitUntilPageStarts()
        await gate.lock(reason: .lockNow)
        let secondAuthentication = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(secondAuthentication, .authenticated)
        await pausedSource.resume()
        do {
            _ = try await task.value
            XCTFail("a revoked token must not publish a rebuilt projection")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
        let finalRevision = try await store.revision()
        XCTAssertNil(finalRevision)
    }

    func testGuardedCanonicalRevisionReadRejectsRevokedOriginalTokenBeforeRead() async throws {
        let gate = AppAccessGateV1(
            setting: .value(.init(isEnabled: true)),
            authentication: V23Authentication(outcomes: [.authenticated, .authenticated]),
            clock: V23Clock(), identifiers: V23IDs()
        )
        let initialAuthentication = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(initialAuthentication, .authenticated)
        let source = V23PausedCanonicalSource(
            revision: try V23Fixture.source(), pauseBeforeRevisionRead: true
        )
        let root = V23Fixture.root("guarded-revision-read")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalSearchIndexStoreV1(applicationSupportURL: root)
        let coordinator = try SearchIndexRebuildCoordinatorV1(
            store: store, source: source,
            registry: try SwiftDataSearchCanonicalProjectionSourceV1.makeRegistry(),
            privateSystemDiscoveryIndex: nil, privateSystemDiscoverySource: nil
        )
        let task = Task { try await coordinator.rebuildIfNeeded(accessGate: gate) }
        await source.waitUntilRevisionReadStarts()
        await gate.lock(reason: .lockNow)
        let resumedAuthentication = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(resumedAuthentication, .authenticated)
        await source.resumeRevisionRead()
        do {
            _ = try await task.value
            XCTFail("a revoked original token reached the canonical revision read")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
        let revisionReadCount = await source.revisionReadCount()
        let pageReadCount = await source.pageReadCount()
        let finalRevision = try await store.revision()
        XCTAssertEqual(revisionReadCount, 0)
        XCTAssertEqual(pageReadCount, 0)
        XCTAssertNil(finalRevision)
        let revisionFence = await store.publicationToken()
        let revisionStaging = try await store.rebuildStaging(publicationToken: revisionFence)
        XCTAssertNil(revisionStaging)

        let control = V23PausedCanonicalSource(
            revision: try V23Fixture.source(), pauseBeforePageRead: false
        )
        let controlRoot = V23Fixture.root("guarded-revision-control")
        defer { try? FileManager.default.removeItem(at: controlRoot) }
        let controlStore = try LocalSearchIndexStoreV1(applicationSupportURL: controlRoot)
        let controlCoordinator = try SearchIndexRebuildCoordinatorV1(
            store: controlStore, source: control,
            registry: try SwiftDataSearchCanonicalProjectionSourceV1.makeRegistry(),
            privateSystemDiscoveryIndex: nil, privateSystemDiscoverySource: nil
        )
        let result = try await controlCoordinator.rebuildIfNeeded(accessGate: gate)
        XCTAssertEqual(result.indexedRecordCount, 0)
        let controlRevisionReadCount = await control.revisionReadCount()
        let controlPageReadCount = await control.pageReadCount()
        XCTAssertEqual(controlRevisionReadCount, 2)
        XCTAssertEqual(controlPageReadCount, 1)
    }

    func testGuardedCanonicalPageReadRejectsRevokedOriginalTokenBeforeRead() async throws {
        let gate = AppAccessGateV1(
            setting: .value(.init(isEnabled: true)),
            authentication: V23Authentication(outcomes: [.authenticated, .authenticated]),
            clock: V23Clock(), identifiers: V23IDs()
        )
        let initialAuthentication = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(initialAuthentication, .authenticated)
        let source = V23PausedCanonicalSource(
            revision: try V23Fixture.source(), pauseBeforePageRead: true
        )
        let root = V23Fixture.root("guarded-page-read")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalSearchIndexStoreV1(applicationSupportURL: root)
        let coordinator = try SearchIndexRebuildCoordinatorV1(
            store: store, source: source,
            registry: try SwiftDataSearchCanonicalProjectionSourceV1.makeRegistry(),
            privateSystemDiscoveryIndex: nil, privateSystemDiscoverySource: nil
        )
        let task = Task { try await coordinator.rebuildIfNeeded(accessGate: gate) }
        await source.waitUntilPageStarts()
        await gate.lock(reason: .lockNow)
        let resumedAuthentication = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(resumedAuthentication, .authenticated)
        await source.resumePageRead()
        do {
            _ = try await task.value
            XCTFail("a revoked original token reached the canonical page read")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
        let revisionReadCount = await source.revisionReadCount()
        let pageReadCount = await source.pageReadCount()
        let finalRevision = try await store.revision()
        XCTAssertEqual(revisionReadCount, 1)
        XCTAssertEqual(pageReadCount, 0)
        XCTAssertNil(finalRevision)
        let pageFence = await store.publicationToken()
        let staging = try await store.rebuildStaging(publicationToken: pageFence)
        XCTAssertEqual(staging?.records.count, 0)
        XCTAssertEqual(staging?.checkpoint.nextCanonicalOffset, 0)
        XCTAssertEqual(staging?.checkpoint.projectedRecordCount, 0)
    }

    func testDiscoveryOptOutDuringProtectedDataAwaitPublishesNoActions() async throws {
        let fixture = try await V23DiscoveryFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let policy = V23DiscoveryPolicy(selection: fixture.enabledSelection, pauseProtectedData: true)
        let coordinator = try fixture.currentCoordinator(
            policy: policy, index: fixture.index, source: fixture.source
        )
        let task = Task { try await coordinator.rebuildIfNeeded() }
        await policy.waitUntilProtectedDataRequested()
        await policy.setSelection(.disabled)
        await policy.resumeProtectedData()
        _ = try await task.value
        XCTAssertTrue(fixture.client.items().isEmpty)
        let discoveryState = try await fixture.index.state()
        XCTAssertTrue(discoveryState.workspaces.isEmpty)
    }

    func testDiscoveryTrueRemoveTrueWithSameSourceRestoresActions() async throws {
        let fixture = try await V23DiscoveryFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let policy = V23DiscoveryPolicy(selection: fixture.enabledSelection)
        let first = try fixture.currentCoordinator(policy: policy, index: fixture.index, source: fixture.source)
        _ = try await first.rebuildIfNeeded()
        XCTAssertEqual(fixture.client.items().count, PrivateSystemDiscoveryActionV1.allCases.count)

        await policy.setSelection(.disabled)
        let removed = try fixture.currentCoordinator(policy: policy, index: fixture.index, source: fixture.source)
        _ = try await removed.rebuildIfNeeded()
        XCTAssertTrue(fixture.client.items().isEmpty)

        await policy.setSelection(fixture.enabledSelection)
        let restored = try fixture.currentCoordinator(policy: policy, index: fixture.index, source: fixture.source)
        _ = try await restored.rebuildIfNeeded()
        XCTAssertEqual(fixture.client.items().count, PrivateSystemDiscoveryActionV1.allCases.count)
        let restoredState = try await fixture.index.state()
        XCTAssertEqual(restoredState.workspaces.map(\.workspaceID), [fixture.workspace])
    }

    func testDiscoveryStoreRebindsWhenRemovalFollowsCoordinatorLookup() async throws {
        let fixture = try await V23DiscoveryFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let policy = V23DiscoveryPolicy(selection: fixture.enabledSelection)
        let initial = try fixture.currentCoordinator(policy: policy, index: fixture.index, source: fixture.source)
        _ = try await initial.rebuildIfNeeded()
        let proxy = V23PausedDiscoveryIndex(index: fixture.index)
        await proxy.armJournalPause()
        let coordinator = try fixture.currentCoordinator(policy: policy, index: proxy, source: fixture.source)
        let task = Task { try await coordinator.rebuildIfNeeded() }
        await proxy.waitUntilJournalRead()
        let removal = try PrivateSystemDiscoveryOperationIDV1(
            rawValue: UUID(), operation: .removal, workspaceID: fixture.workspace,
            inputSHA256: String(repeating: "b", count: 64)
        )
        try await fixture.index.remove(operationID: removal, workspaceID: fixture.workspace,
                                       now: Date(timeIntervalSince1970: 1_800_000_001))
        XCTAssertTrue(fixture.client.items().isEmpty)
        await proxy.resumeJournalRead()
        _ = try await task.value
        XCTAssertEqual(fixture.client.items().count, PrivateSystemDiscoveryActionV1.allCases.count)
    }

    func testGatedSearchRejectsPermissiveGenericPortBeforeProjection() async throws {
        let probe = V23SearchProjectionProbe()
        let coordinator = SearchCoordinatorV1(index: probe)
        let source = try SearchSourceRevisionV1(
            workspaceID: UUID(), generationID: UUID(), commitRevision: 1
        )
        let plan = try coordinator.makePlan(query: "asset", sourceRevision: 1)
        let registry = try SwiftDataSearchCanonicalProjectionSourceV1.makeRegistry()

        do {
            _ = try await coordinator.search(
                plan, source: source, registry: registry,
                accessGate: V23PermissivePort()
            )
            XCTFail("a generic point-in-time permit must not authorize search")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .configurationUnknown)
        }
        let readCount = await probe.readCount()
        XCTAssertEqual(readCount, 0)
    }

    func testGuardedCoordinatorRejectsUnsupportedDiscoveryPortBeforeJournalReplay() async throws {
        let fixture = try await V23DiscoveryFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let gate = AppAccessGateV1(setting: .value(.init(isEnabled: true)),
            authentication: V23Authentication(outcomes: [.authenticated]),
            clock: V23Clock(), identifiers: V23IDs())
        let unlock = await gate.authenticate(trigger: .unlock)
        XCTAssertEqual(unlock, .authenticated)
        let proxy = V23PausedDiscoveryIndex(index: fixture.index)
        let coordinator = try fixture.currentCoordinator(
            policy: V23DiscoveryPolicy(selection: fixture.enabledSelection),
            index: proxy, source: fixture.source)
        do { _ = try await coordinator.rebuildIfNeeded(accessGate: gate); XCTFail("unsupported port entered guarded replay") }
        catch { XCTAssertEqual(error as? PrivateSystemDiscoveryFailureV1, .unavailable) }
        let reads = await proxy.journalReadCount()
        XCTAssertEqual(reads, 0)
        XCTAssertTrue(fixture.client.items().isEmpty)
    }

    func testGatedRebuildPreservesGenericPortDenialReasonBeforeSourceRead() async throws {
        let source = try V23Fixture.source()
        let root = V23Fixture.root("generic-denial")
        defer { try? FileManager.default.removeItem(at: root) }
        let coordinator = try SearchIndexRebuildCoordinatorV1(
            store: LocalSearchIndexStoreV1(applicationSupportURL: root),
            source: V23PausedCanonicalSource(revision: source),
            registry: try SwiftDataSearchCanonicalProjectionSourceV1.makeRegistry(),
            privateSystemDiscoveryIndex: nil, privateSystemDiscoverySource: nil
        )
        do {
            _ = try await coordinator.rebuildIfNeeded(accessGate: V23DeniedPort())
            XCTFail("the port's denial must remain the caller-visible reason")
        } catch {
            XCTAssertEqual(error as? AppAccessContractFailureV1, .accessDenied)
        }
    }
}

private struct V23PermissivePort: AppAccessGatePortV1 {
    func currentState() async -> AppAccessStateV1 { .disabled }
    func lock(reason: AppLockReasonV1) async {}
    func authenticate(trigger: LocalAuthenticationTriggerV1) async -> LocalAuthenticationOutcomeV1 {
        .authenticated
    }
    func requireContentAccess() async throws {}
}

private struct V23DeniedPort: AppAccessGatePortV1 {
    func currentState() async -> AppAccessStateV1 { .locked(reason: .lockNow) }
    func lock(reason: AppLockReasonV1) async {}
    func authenticate(trigger: LocalAuthenticationTriggerV1) async -> LocalAuthenticationOutcomeV1 { .authenticated }
    func requireContentAccess() async throws { throw AppAccessContractFailureV1.accessDenied }
}

private actor V23SearchProjectionProbe: SearchIndexSnapshotProvidingV1 {
    private var reads = 0

    func projection(
        for source: SearchSourceRevisionV1,
        registry: SearchableFieldRegistryV1
    ) async throws -> SearchIndexProjectionV1 {
        reads += 1
        let index = try SearchIndexRevisionV1(
            workspaceID: source.workspaceID,
            generationID: source.generationID,
            indexedCommitRevision: source.commitRevision
        )
        return try SearchIndexProjectionV1(
            source: source, index: index, records: [], registry: registry
        )
    }

    func readCount() -> Int { reads }
}

private actor V23PausedProjectionProbe: SearchIndexSnapshotProvidingV1 {
    private var started: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?
    private var didStart = false

    func projection(for source: SearchSourceRevisionV1, registry: SearchableFieldRegistryV1) async throws -> SearchIndexProjectionV1 {
        didStart = true; started?.resume(); started = nil
        await withCheckedContinuation { resumeContinuation = $0 }
        let index = try SearchIndexRevisionV1(workspaceID: source.workspaceID, generationID: source.generationID, indexedCommitRevision: source.commitRevision)
        return try SearchIndexProjectionV1(source: source, index: index, records: [], registry: registry)
    }
    func waitUntilProjectionStarts() async {
        if didStart { return }
        await withCheckedContinuation { started = $0 }
    }
    func resume() { resumeContinuation?.resume(); resumeContinuation = nil }
}

private actor V23PausedCanonicalSource: SearchContentReadGuardedProjectionSourceV1 {
    let revision: SearchSourceRevisionV1
    private var started: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?
    private var didStart = false
    private let pauseBeforeRevisionRead: Bool
    private let pauseBeforePageRead: Bool
    private var revisionStarted: CheckedContinuation<Void, Never>?
    private var revisionResumeContinuation: CheckedContinuation<Void, Never>?
    private var didStartRevisionRead = false
    private var observedRevisionReads = 0
    private var observedPageReads = 0

    init(
        revision: SearchSourceRevisionV1,
        pauseBeforeRevisionRead: Bool = false,
        pauseBeforePageRead: Bool = true
    ) {
        self.revision = revision
        self.pauseBeforeRevisionRead = pauseBeforeRevisionRead
        self.pauseBeforePageRead = pauseBeforePageRead
    }

    func currentSearchSourceRevision() async throws -> SearchSourceRevisionV1 {
        observedRevisionReads += 1
        return revision
    }

    func currentSearchSourceRevision(
        contentReadToken: AppAccessGateV1.ContentReadToken
    ) async throws -> SearchSourceRevisionV1 {
        if pauseBeforeRevisionRead {
            didStartRevisionRead = true
            revisionStarted?.resume()
            revisionStarted = nil
            await withCheckedContinuation { revisionResumeContinuation = $0 }
        }
        return try contentReadToken.withContentRead(for: .searchRebuild) {
            observedRevisionReads += 1
            return revision
        }
    }

    func searchProjectionPage(at source: SearchSourceRevisionV1, canonicalOffset: Int, limit: Int) async throws -> SearchCanonicalProjectionPageV1 {
        guard pauseBeforePageRead else {
            observedPageReads += 1
            return try .init(requestedCanonicalOffset: canonicalOffset, nextCanonicalOffset: canonicalOffset, isComplete: true, records: [])
        }
        didStart = true; started?.resume(); started = nil
        await withCheckedContinuation { resumeContinuation = $0 }
        observedPageReads += 1
        return try .init(requestedCanonicalOffset: canonicalOffset, nextCanonicalOffset: canonicalOffset, isComplete: true, records: [])
    }

    func searchProjectionPage(
        at source: SearchSourceRevisionV1,
        canonicalOffset: Int,
        limit: Int,
        contentReadToken: AppAccessGateV1.ContentReadToken
    ) async throws -> SearchCanonicalProjectionPageV1 {
        guard pauseBeforePageRead else {
            return try contentReadToken.withContentRead(for: .searchRebuild) {
                observedPageReads += 1
                return try .init(requestedCanonicalOffset: canonicalOffset, nextCanonicalOffset: canonicalOffset, isComplete: true, records: [])
            }
        }
        didStart = true; started?.resume(); started = nil
        await withCheckedContinuation { resumeContinuation = $0 }
        return try contentReadToken.withContentRead(for: .searchRebuild) {
            observedPageReads += 1
            return try .init(requestedCanonicalOffset: canonicalOffset, nextCanonicalOffset: canonicalOffset, isComplete: true, records: [])
        }
    }

    func waitUntilPageStarts() async { if didStart { return }; await withCheckedContinuation { started = $0 } }
    func resume() { resumePageRead() }
    func resumePageRead() { resumeContinuation?.resume(); resumeContinuation = nil }
    func waitUntilRevisionReadStarts() async {
        if didStartRevisionRead { return }
        await withCheckedContinuation { revisionStarted = $0 }
    }
    func resumeRevisionRead() { revisionResumeContinuation?.resume(); revisionResumeContinuation = nil }
    func revisionReadCount() -> Int { observedRevisionReads }
    func pageReadCount() -> Int { observedPageReads }
}

private struct V23ImmediateCanonicalSource: SearchContentReadGuardedProjectionSourceV1 {
    let revision: SearchSourceRevisionV1
    func currentSearchSourceRevision() async throws -> SearchSourceRevisionV1 { revision }
    func currentSearchSourceRevision(
        contentReadToken: AppAccessGateV1.ContentReadToken
    ) async throws -> SearchSourceRevisionV1 {
        try contentReadToken.withContentRead(for: .searchRebuild) { revision }
    }
    func searchProjectionPage(at source: SearchSourceRevisionV1, canonicalOffset: Int,
                              limit: Int) async throws -> SearchCanonicalProjectionPageV1 {
        try .init(requestedCanonicalOffset: canonicalOffset, nextCanonicalOffset: canonicalOffset,
                  isComplete: true, records: [])
    }
    func searchProjectionPage(
        at source: SearchSourceRevisionV1,
        canonicalOffset: Int,
        limit: Int,
        contentReadToken: AppAccessGateV1.ContentReadToken
    ) async throws -> SearchCanonicalProjectionPageV1 {
        try contentReadToken.withContentRead(for: .searchRebuild) {
            try .init(requestedCanonicalOffset: canonicalOffset,
                      nextCanonicalOffset: canonicalOffset, isComplete: true, records: [])
        }
    }
}

private actor V23Authentication: LocalAuthenticationClient {
    private var outcomes: [LocalAuthenticationOutcomeV1]
    init(outcomes: [LocalAuthenticationOutcomeV1]) { self.outcomes = outcomes }
    func availability() async -> LocalAuthenticationAvailabilityV1 { .systemValue(status: .available, biometry: .faceID) }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) async -> LocalAuthenticationOutcomeV1 { outcomes.removeFirst() }
    func cancel(attemptID: UUID) async {}
}

private struct V23Clock: ApplicationClock { func now() -> Date { Date(timeIntervalSince1970: 1_800_000_000) } }
private struct V23IDs: ApplicationIDSource { func makeID() -> UUID { UUID() } }

private enum V23Fixture {
    static func source() throws -> SearchSourceRevisionV1 { try .init(workspaceID: UUID(), generationID: UUID(), commitRevision: 1) }
    static func root(_ label: String) -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("V23SearchReconciliation-\(label)-\(UUID().uuidString)", isDirectory: true) }
}

private actor V23DiscoveryPolicy {
    private var selection: PrivateSystemDiscoveryOptInV1
    private let pauseProtectedData: Bool
    private var didRequestProtectedData = false
    private var requested: CheckedContinuation<Void, Never>?
    private var continuation: CheckedContinuation<Void, Never>?
    init(selection: PrivateSystemDiscoveryOptInV1, pauseProtectedData: Bool = false) { self.selection = selection; self.pauseProtectedData = pauseProtectedData }
    func optIn() throws -> PrivateSystemDiscoveryOptInV1 { selection }
    func protectedDataAvailable() async -> Bool {
        guard pauseProtectedData else { return true }
        didRequestProtectedData = true; requested?.resume(); requested = nil
        await withCheckedContinuation { continuation = $0 }
        return true
    }
    func setSelection(_ value: PrivateSystemDiscoveryOptInV1) { selection = value }
    func waitUntilProtectedDataRequested() async { if didRequestProtectedData { return }; await withCheckedContinuation { requested = $0 } }
    func resumeProtectedData() { continuation?.resume(); continuation = nil }
}

private final class V23DiscoveryClient: PrivateSystemDiscoveryProtectedIndexClientV1, @unchecked Sendable {
    private let lock = NSLock(); private var values: [String: PrivateSystemDiscoveryIndexItemV1] = [:]
    func replaceItems(deleting identifiers: [String], with items: [PrivateSystemDiscoveryIndexItemV1]) async throws { lock.withLock { identifiers.forEach { values.removeValue(forKey: $0) }; items.forEach { values[$0.uniqueIdentifier] = $0 } } }
    func deleteItems(withIdentifiers identifiers: [String]) async throws { lock.withLock { identifiers.forEach { values.removeValue(forKey: $0) } } }
    func deleteAllItems() async throws { lock.withLock { values.removeAll() } }
    func items() -> [PrivateSystemDiscoveryIndexItemV1] { lock.withLock { values.values.sorted { $0.uniqueIdentifier < $1.uniqueIdentifier } } }
}

private actor V23SuspendingGuardedDiscoveryClient: PrivateSystemDiscoveryContentGuardedIndexClientV1 {
    private var started: CheckedContinuation<Void, Never>?
    private var deletion: CheckedContinuation<Void, Never>?
    private var submissions = 0
    private var pausesNextDeletion = true
    private var didStart = false
    func replaceItems(deleting identifiers: [String], with items: [PrivateSystemDiscoveryIndexItemV1]) async throws { submissions += 1 }
    func replaceItems(deleting identifiers: [String], with items: [PrivateSystemDiscoveryIndexItemV1], contentReadToken: AppAccessGateV1.ContentReadToken) async throws {
        if pausesNextDeletion {
            pausesNextDeletion = false; didStart = true; started?.resume(); started = nil
            await withCheckedContinuation { deletion = $0 }
        }
        try contentReadToken.withContentRead(for: .searchRebuild) { submissions += 1 }
    }
    func deleteItems(withIdentifiers identifiers: [String]) async throws {}
    func deleteAllItems() async throws {}
    func waitUntilDeletionCompletes() async {
        if didStart { return }
        await withCheckedContinuation { started = $0 }
    }
    func resumeDeletion() { deletion?.resume(); deletion = nil }
    func submissionCount() -> Int { submissions }
}

/// Models the real client's deletion callback, synchronous guarded submission,
/// and a later OS indexing callback. The late effect deliberately ignores the
/// now-revoked token: only the store may decide whether to accept it locally.
private actor V23ControlledDiscoveryClient: PrivateSystemDiscoveryContentGuardedIndexClientV1 {
    enum Pause: Equatable, Sendable { case none, deletion, callback }
    private var pause: Pause
    private var didPause = false
    private var paused: CheckedContinuation<Void, Never>?
    private var continuation: CheckedContinuation<Void, Never>?
    private var submissions = 0
    private var values: [String: PrivateSystemDiscoveryIndexItemV1] = [:]
    private var deleteAllCalls = 0
    init(pause: Pause = .none) { self.pause = pause }
    func replaceItems(deleting identifiers: [String], with items: [PrivateSystemDiscoveryIndexItemV1]) async throws {
        XCTFail("guarded fixture was sent through unguarded replacement")
        throw PrivateSystemDiscoveryFailureV1.unavailable
    }
    func replaceItems(deleting identifiers: [String], with items: [PrivateSystemDiscoveryIndexItemV1],
                      contentReadToken: AppAccessGateV1.ContentReadToken) async throws {
        identifiers.forEach { values.removeValue(forKey: $0) }
        if pause == .deletion { await suspend() }
        try contentReadToken.withContentRead(for: .searchRebuild) { submissions += 1 }
        if pause == .callback { await suspend() }
        items.forEach { values[$0.uniqueIdentifier] = $0 }
    }
    private func suspend() async {
        pause = .none
        // Install the resume continuation before notifying the waiting test.
        await withCheckedContinuation { next in
            continuation = next; didPause = true; paused?.resume(); paused = nil
        }
    }
    func waitUntilPaused() async {
        if didPause { return }
        await withCheckedContinuation { paused = $0 }
    }
    func resume() { continuation?.resume(); continuation = nil }
    func deleteItems(withIdentifiers identifiers: [String]) async throws {
        identifiers.forEach { values.removeValue(forKey: $0) }
    }
    func deleteAllItems() async throws { deleteAllCalls += 1; values.removeAll() }
    func items() -> [PrivateSystemDiscoveryIndexItemV1] {
        values.values.sorted { $0.uniqueIdentifier < $1.uniqueIdentifier }
    }
    func submissionCount() -> Int { submissions }
    func deleteAllCount() -> Int { deleteAllCalls }
}

private struct V23DiscoveryRequest {
    let workspace: WorkspaceID; let operationID: PrivateSystemDiscoveryOperationIDV1
    let descriptors: [PrivateSystemDiscoveryProjectionDescriptorV1]; let manifest: PrivateSystemDiscoveryManifestV1
    let optIn: PrivateSystemDiscoveryOptInV1; let availability: [AppIntentAvailabilityV1]; let now: Date
    func rebuild(_ index: PrivateSystemDiscoveryIndexStoreV1,
                 token: AppAccessGateV1.ContentReadToken) async throws {
        try await index.rebuild(operationID: operationID, workspaceID: workspace,
            workspaceRevision: 1, deletionFrontier: 0, descriptors: descriptors,
            manifest: manifest, optIn: optIn, availability: availability, now: now,
            contentReadToken: token)
    }
    static func make() throws -> Self {
        let workspace = WorkspaceID(rawValue: UUID()); let now = Date(timeIntervalSince1970: 1_800_000_000)
        let manifest = try PrivateSystemDiscoveryManifestV1()
        let descriptors = try PrivateSystemDiscoveryProjectionDomainV1.allCases.map { try PrivateSystemDiscoveryProjectionDescriptorV1(domain: $0, projectionVersion: 1, allowlistSHA256: manifest.manifestSHA256, policySHA256: manifest.manifestSHA256, indexDefinitionSHA256: manifest.manifestSHA256) }.sorted { $0.stableKey < $1.stableKey }
        let optIn = try PrivateSystemDiscoveryOptInV1.enabled(workspaceID: workspace, workspaceKind: .real)
        let availability = try PrivateSystemDiscoveryActionV1.allCases.map { try AppIntentAvailabilityV1(workspaceID: workspace, action: $0, optedIn: true, featureReason: .available, appAccessPermitsContent: true, protectedDataAvailable: true, evaluatedAt: now) }
        let operationID = try PrivateSystemDiscoveryOperationIDV1(rawValue: UUID(), operation: .rebuild, workspaceID: workspace, inputSHA256: String(repeating: "a", count: 64))
        return .init(workspace: workspace, operationID: operationID, descriptors: descriptors, manifest: manifest, optIn: optIn, availability: availability, now: now)
    }
}

private final class V23DiscoveryStateStore: PrivateSystemDiscoveryClientStateStoreV1, PrivateSystemDiscoveryGlobalJournalStoreV1, @unchecked Sendable {
    private let lock = NSLock(); private var value: PrivateSystemDiscoveryClientStateV1?; private var global: PrivateSystemDiscoveryGlobalJournalV1?
    private var failCommit = false
    func failNextCommit() { lock.withLock { failCommit = true } }
    func load() throws -> PrivateSystemDiscoveryClientStateV1? { lock.withLock { value } }
    func save(_ state: PrivateSystemDiscoveryClientStateV1) throws {
        try lock.withLock {
            if failCommit, state.journal.last?.state == .committed {
                failCommit = false
                throw PrivateSystemDiscoveryFailureV1.unavailable
            }
            value = state
        }
    }
    func clear() throws { lock.withLock { value = .empty } }
    func loadGlobal() throws -> PrivateSystemDiscoveryGlobalJournalV1? { lock.withLock { global } }
    func saveGlobal(_ journal: PrivateSystemDiscoveryGlobalJournalV1) throws { lock.withLock { global = journal } }
}

private actor V23PausedDiscoveryIndex: PrivateSystemDiscoveryIndexLifecyclePortV1 {
    private let index: PrivateSystemDiscoveryIndexStoreV1
    private var armed = false; private var didRead = false
    private var journalReads = 0
    private var started: CheckedContinuation<Void, Never>?
    private var continuation: CheckedContinuation<Void, Never>?
    init(index: PrivateSystemDiscoveryIndexStoreV1) { self.index = index }
    func armJournalPause() { armed = true }
    func waitUntilJournalRead() async { if didRead { return }; await withCheckedContinuation { started = $0 } }
    func resumeJournalRead() { continuation?.resume(); continuation = nil }
    func journalReadCount() -> Int { journalReads }
    func rebuild(operationID: PrivateSystemDiscoveryOperationIDV1, workspaceID: WorkspaceID, workspaceRevision: UInt64, deletionFrontier: UInt64, descriptors: [PrivateSystemDiscoveryProjectionDescriptorV1], manifest: PrivateSystemDiscoveryManifestV1, optIn: PrivateSystemDiscoveryOptInV1, availability: [AppIntentAvailabilityV1], now: Date) async throws { try await index.rebuild(operationID: operationID, workspaceID: workspaceID, workspaceRevision: workspaceRevision, deletionFrontier: deletionFrontier, descriptors: descriptors, manifest: manifest, optIn: optIn, availability: availability, now: now) }
    func remove(operationID: PrivateSystemDiscoveryOperationIDV1, workspaceID: WorkspaceID, now: Date) async throws { try await index.remove(operationID: operationID, workspaceID: workspaceID, now: now) }
    func eraseAll(operationID: PrivateSystemDiscoveryOperationIDV1, now: Date) async throws { try await index.eraseAll(operationID: operationID, now: now) }
    func dropAndRebuild() async throws { try await index.dropAndRebuild() }
    func state() async throws -> PrivateSystemDiscoveryStateMapV1 { try await index.state() }
    func journalEntries() async throws -> [PrivateSystemDiscoveryJournalEntryV1] {
        journalReads += 1
        let entries = try await index.journalEntries()
        guard armed else { return entries }
        armed = false; didRead = true; started?.resume(); started = nil
        await withCheckedContinuation { continuation = $0 }
        return entries
    }
}

@MainActor
private struct V23DiscoveryFixture {
    let root: URL; let workspace: WorkspaceID; let source: SearchSourceRevisionV1; let store: LocalSearchIndexStoreV1
    let index: PrivateSystemDiscoveryIndexStoreV1; let client: V23DiscoveryClient; let enabledSelection: PrivateSystemDiscoveryOptInV1
    static func make() async throws -> Self {
        let workspace = WorkspaceID(rawValue: UUID()); let source = try SearchSourceRevisionV1(workspaceID: workspace.rawValue, generationID: UUID(), commitRevision: 1)
        let root = V23Fixture.root("discovery"); let store = try LocalSearchIndexStoreV1(applicationSupportURL: root)
        let registry = try SwiftDataSearchCanonicalProjectionSourceV1.makeRegistry()
        try await store.replaceProjection(source: source, records: [], registry: registry)
        let client = V23DiscoveryClient(); let state = V23DiscoveryStateStore()
        return try .init(root: root, workspace: workspace, source: source, store: store, index: PrivateSystemDiscoveryIndexStoreV1(indexClient: client, clientStateStore: state, globalJournalStore: state), client: client, enabledSelection: .enabled(workspaceID: workspace, workspaceKind: .real))
    }
    func currentCoordinator(policy: V23DiscoveryPolicy, index: any PrivateSystemDiscoveryIndexLifecyclePortV1, source: SearchSourceRevisionV1) throws -> SearchIndexRebuildCoordinatorV1 {
        try SearchIndexRebuildCoordinatorV1(store: store, source: V23PausedCanonicalSource(revision: source), registry: try SwiftDataSearchCanonicalProjectionSourceV1.makeRegistry(), privateSystemDiscoveryIndex: index, privateSystemDiscoverySource: Self.productionSource(policy))
    }
    static func productionSource(_ policy: V23DiscoveryPolicy) -> PrivateSystemDiscoveryProductionRebuildSourceV1 {
        PrivateSystemDiscoveryProductionRebuildSourceV1(optIn: { try await policy.optIn() }, protectedDataAvailable: { await policy.protectedDataAvailable() }, now: { Date(timeIntervalSince1970: 1_800_000_000) })
    }
}

#if DEBUG
private actor V23ProjectionDropRevocationProbe {
    let gate: AppAccessGateV1
    private(set) var calls = 0
    private(set) var outcome: LocalAuthenticationOutcomeV1?
    init(gate: AppAccessGateV1) { self.gate = gate }
    func revokeAndReauthenticate() async {
        calls += 1
        await gate.lock(reason: .lockNow)
        outcome = await gate.authenticate(trigger: .unlock)
    }
}
#endif

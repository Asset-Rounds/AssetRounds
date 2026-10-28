import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class S7_5DataRightsIntegrationTests: XCTestCase {
    private let fileManager = FileManager.default
    private let bundleID = "com.palatis3.fieldrecord"
    @MainActor private static var retainedFailedTemporalRestores: [(
        root: URL, session: StoreGenerationSession, error: any Error
    )] = []
    @MainActor private static var retainedFailedSeedGraphs: [(
        root: URL,
        session: StoreGenerationSession,
        coordinator: StoreSessionCoordinator?,
        runner: CheckRunnerCoordinator?
    )] = []

    @MainActor
    func testFormerPaidBlocksOnlyNewValueAndKeepsExactDraftAndDataServices()
        async throws {
        let root = try makeApplicationSupport("lapse")
        defer {
            if !FirstSignFixtureWriterReleaseV1.retains(root: root) {
                try? fileManager.removeItem(at: root)
            }
        }
        let session = try StoreGenerationFactory(applicationSupportURL: root)
            .openOrBootstrapCurrent()
        let diagnostics = DiagnosticsStore(applicationSupportURL: root)
        var access = DraftAccessNormalizedStateV1.entitled
        let firstSignProfile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(package: .illuminatedSignV1)
        let firstSignRegistry = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [firstSignProfile])
        let firstSignOwner = try FirstSignFixtureWriterReleaseV1.makeOwner(session: session,
            profileRegistry: firstSignRegistry, root: root)
        defer {
            do { try FirstSignFixtureWriterReleaseV1.close(firstSignOwner, session: session, root: root) }
            catch { XCTFail("First-sign fixture writer release failed: \(error)") }
        }
        let firstSignDependencies = try firstSignOwner.packageLifecycleDependencies(profileRegistry: firstSignRegistry)
        let signs = try FirstSignCoordinator(
            modelContext: session.modelContext,
            diagnosticsStore: diagnostics,
            packageLifecycleDependencies: firstSignDependencies,
            packageLifecycleProfile: firstSignProfile,
            accessState: { access }
        )
        let first = try await signs.create(FirstSignInput(
            siteLabel: "Lapse site",
            signLabel: "Existing draft sign",
            timeZoneID: "America/New_York",
            isTimeZoneConfirmed: true
        ))
        let second = try await signs.create(FirstSignInput(
            existingSiteID: first.siteID,
            siteLabel: "",
            signLabel: "New-value sign"
        ))
        let runner = try CheckRunnerCoordinator(
            modelContext: session.modelContext,
            packageLifecycleDependencies: firstSignDependencies,
            packageLifecycleProfile: firstSignProfile,
            diagnosticsStore: diagnostics,
            draftAccessState: { access }
        )
        let draft = try runner.beginOrResumeDraft(BeginDraftSubmission(
            assetID: first.assetID,
            requestedStage: .check,
            issueID: nil,
            observedAtUTC: Date().addingTimeInterval(-60),
            confirmedTimeZoneID: nil,
            afterDarkAccepted: true,
            safePositionAccepted: true
        ))

        access = .formerPaidInactive
        XCTAssertEqual(
            try signs.accessDecisionForCreateSign(),
            .blockPaid
        )
        XCTAssertEqual(
            try runner.accessDecision(
                assetID: second.assetID,
                requestedStage: .check,
                issueID: nil
            ),
            .blockPaid
        )
        XCTAssertEqual(
            try runner.accessDecision(
                assetID: first.assetID,
                requestedStage: .check,
                issueID: nil
            ),
            .continueExisting
        )
        XCTAssertEqual(
            try runner.beginOrResumeDraft(
                assetID: first.assetID,
                requestedStage: .check,
                issueID: nil
            ).id,
            draft.id
        )

        let reportDelivery = try ReportDeliveryCoordinator(
            modelContext: session.modelContext,
            generationRootURL: session.generationRootURL,
            diagnosticsStore: diagnostics
        )
        _ = reportDelivery
        let backup = BackupExportService(
            modelContext: session.modelContext,
            generationRootURL: session.generationRootURL,
            now: { Date(timeIntervalSince1970: 1_900_000_000) },
            appVersion: { "1.0" },
            appBuild: { "1" }
        )
        let preview = try backup.prepare()
        XCTAssertEqual(preview.signCount, 2)
        XCTAssertEqual(preview.reportCount, 0)
        XCTAssertEqual(preview.photoCount, 0)
        XCTAssertEqual(
            try session.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()),
            1
        )

        _ = try await WholeSignDeletionService(
            modelContext: session.modelContext,
            lifecycleDependencies: firstSignDependencies,
            storeSession: firstSignOwner
        ).delete(assetID: first.assetID)
        XCTAssertEqual(try signs.loadAll().map(\.assetID), [second.assetID])
        XCTAssertEqual(
            try session.modelContext.fetchCount(FetchDescriptor<WorkflowRecord>()),
            0
        )
    }

    @MainActor
    func testFractionalObservedInstantPreservesTypedAuthorityThroughLiveBackup() async throws {
        let root = try makeApplicationSupport("fractional-observation-backup")
        let targetRoot = try makeApplicationSupport("fractional-observation-restored")
        var completed = false
        defer {
            // Preserve both physical fixtures on any uncertain close/restore failure.
            if completed {
                for candidate in [root, targetRoot]
                    where !FirstSignFixtureWriterReleaseV1.retains(root: candidate) {
                    try? fileManager.removeItem(at: candidate)
                }
            }
        }
        let observed = Date(timeIntervalSinceReferenceDate: 811_123_456.000_000_1)
        struct Authority {
            let recordID: UUID
            let generationID: UUID
            let basisBytes: Data
            let temporalBytes: Data
            let basis: ObservationBasisV1
            let temporal: TemporalContextV1
        }

        // Only immutable values leave a phase; its readers/session/owner cannot
        // remain captured by the next factory open.
        @MainActor func seedAndClose() async throws -> Authority {
            let session = try StoreGenerationFactory(applicationSupportURL: root)
                .openOrBootstrapCurrent()
            let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
            let registry = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
            let owner = try FirstSignFixtureWriterReleaseV1.makeOwner(session: session,
                profileRegistry: registry, root: root)
            var closeAttempted = false
            defer {
                if !closeAttempted {
                    do { try FirstSignFixtureWriterReleaseV1.close(owner, session: session, root: root) }
                    catch { XCTFail("Fractional observation fixture writer release failed: \(error)") }
                }
            }
            let dependencies = try owner.packageLifecycleDependencies(profileRegistry: registry)
            let diagnostics = DiagnosticsStore(applicationSupportURL: root)
            let signs = try FirstSignCoordinator(modelContext: session.modelContext,
                diagnosticsStore: diagnostics, packageLifecycleDependencies: dependencies,
                packageLifecycleProfile: profile)
            let sign = try await signs.create(FirstSignInput(siteLabel: "Temporal site",
                signLabel: "Temporal sign", timeZoneID: "America/New_York",
                isTimeZoneConfirmed: true))
            let runner = try CheckRunnerCoordinator(modelContext: session.modelContext,
                packageLifecycleDependencies: dependencies, packageLifecycleProfile: profile,
                diagnosticsStore: diagnostics)
            // Existing fixed fractional premise; never round the submitted observation.
            let draft = try runner.beginOrResumeDraft(BeginDraftSubmission(
                assetID: sign.assetID, requestedStage: .check, issueID: nil,
                observedAtUTC: observed, confirmedTimeZoneID: nil,
                afterDarkAccepted: true, safePositionAccepted: true))
            XCTAssertFalse(session.modelContext.hasChanges)
            XCTAssertEqual(draft.observedAtUTC, observed)
            let companion = try ObservationAndTimeRowStoreV1.requireRow(
                recordID: draft.id, in: session.modelContext)
            let basisBytes = companion.observationBasisV1Data
            let temporalBytes = companion.temporalContextV1Data
            let basis = try companion.observationBasisV1()
            let temporal = try companion.temporalContextV1()
            XCTAssertEqual(try ObservationAndTimeCodecV1.encode(basis), basisBytes)
            XCTAssertEqual(try ObservationAndTimeCodecV1.encode(temporal), temporalBytes)
            // The retained standalone probe characterizes current Foundation drift.
            // Correct backup behavior must also hold if that conversion becomes lossless.
            XCTAssertNotNil(temporal.occurredAtUTC)
            XCTAssertEqual(CanonicalJSONV1.optionalDate(temporal.occurredAtUTC),
                CanonicalJSONV1.optionalDate(observed))

            let authority = Authority(recordID: draft.id, generationID: session.generationID,
                basisBytes: basisBytes, temporalBytes: temporalBytes, basis: basis, temporal: temporal)
            closeAttempted = true
            try FirstSignFixtureWriterReleaseV1.close(owner, session: session, root: root)
            return authority
        }

        @MainActor func reopenExportAndClose(root: URL, expected: Authority,
            generationID: UUID) throws -> URL {
            let session = try StoreGenerationFactory(applicationSupportURL: root).openOrBootstrapCurrent()
            XCTAssertEqual(session.generationID, generationID)
            let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
            let registry = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
            let owner = try FirstSignFixtureWriterReleaseV1.makeOwner(session: session,
                profileRegistry: registry, root: root)
            var closeAttempted = false
            defer {
                if !closeAttempted {
                    do { try FirstSignFixtureWriterReleaseV1.close(owner, session: session, root: root) }
                    catch { XCTFail("Fractional observation reopened writer release failed: \(error)") }
                }
            }
            let dependencies = try owner.packageLifecycleDependencies(profileRegistry: registry)
            let draft = try XCTUnwrap(session.modelContext.fetch(FetchDescriptor<WorkflowRecord>())
                .first { $0.id == expected.recordID })
            let companion = try ObservationAndTimeRowStoreV1.requireRow(
                recordID: draft.id, in: session.modelContext)
            let storedObserved = draft.observedAtUTC
            let basisBytes = expected.basisBytes
            let temporalBytes = expected.temporalBytes
            let temporal = expected.temporal
            XCTAssertEqual(companion.observationBasisV1Data, basisBytes)
            XCTAssertEqual(companion.temporalContextV1Data, temporalBytes)
            XCTAssertEqual(try companion.observationBasisV1(), expected.basis)
            XCTAssertEqual(try companion.temporalContextV1(), temporal)
            XCTAssertEqual(draft.localDate, temporal.localDate)
            XCTAssertEqual(draft.localTime, temporal.localTime)
            XCTAssertEqual(draft.timeZoneID, temporal.ianaTimeZoneIdentifier)
            XCTAssertEqual(draft.utcOffsetMinutes.map { $0 * 60 }, temporal.utcOffsetSeconds)
            XCTAssertEqual(CanonicalJSONV1.optionalDate(draft.observedAtUTC),
                CanonicalJSONV1.optionalDate(observed))
            let backup = BackupExportService(modelContext: session.modelContext,
                generationRootURL: session.generationRootURL,
                lifecycleDependencies: dependencies,
                now: { Date(timeIntervalSince1970: 1_900_000_000) },
                appVersion: { "1.0" }, appBuild: { "1" })
            // This must succeed for the genuine committed record; a thrown error is red.
            let preview = try backup.prepare()
            XCTAssertEqual(preview.signCount, 1)
            XCTAssertEqual(preview.reportCount, 0)
            XCTAssertEqual(preview.photoCount, 0)
            let destination = root.appendingPathComponent("export", isDirectory: true)
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
            // No photos: the ordinary synchronous archive path is the production API.
            let archive = try backup.export(previewID: preview.id, to: destination)
            let importer = try BackupImportService(generationRootURL: session.generationRootURL,
                scopedAccess: .alreadyAuthorized)
            let validated = try importer.stageAndValidate(selectedPackageURL: archive)

            XCTAssertEqual(validated.records.workflowRecords.count, 1)
            let exported = try XCTUnwrap(validated.records.workflowRecords.first)
            XCTAssertEqual(exported.id, draft.id)
            XCTAssertEqual(exported.observationBasisV1Data, basisBytes)
            XCTAssertEqual(exported.temporalContextV1Data, temporalBytes)
            let exportedTemporal = try ObservationAndTimeCodecV1.decodeTemporalContext(
                XCTUnwrap(exported.temporalContextV1Data))
            XCTAssertEqual(exportedTemporal, temporal)
            XCTAssertEqual(CanonicalJSONV1.optionalDate(exported.observedAtUTC),
                CanonicalJSONV1.optionalDate(observed))
            XCTAssertEqual(exported.localDate, draft.localDate)
            XCTAssertEqual(exported.localTime, draft.localTime)
            XCTAssertEqual(exported.timeZoneID, draft.timeZoneID)
            XCTAssertEqual(exported.utcOffsetMinutes, draft.utcOffsetMinutes)
            // Check actual archived metadata/raw members, not a synthetic DTO fixture.
            let recordsData = try BackupRawDataWireTestSupport.logicalRecordsData(afterChecking: validated)
            let decoded = try BackupCanonicalDecoderV1().decodeRecords(recordsData)
            XCTAssertEqual(decoded, validated.records)
            XCTAssertEqual(try BackupCanonicalEncoderV1().encodeRecords(decoded).data, recordsData)
            XCTAssertEqual(companion.observationBasisV1Data, basisBytes)
            XCTAssertEqual(companion.temporalContextV1Data, temporalBytes)
            XCTAssertEqual(CanonicalJSONV1.optionalDate(draft.observedAtUTC),
                CanonicalJSONV1.optionalDate(observed))
            XCTAssertFalse(session.modelContext.hasChanges)
            XCTAssertEqual(draft.observedAtUTC, storedObserved)
            try importer.discard(validated)
            closeAttempted = true
            try FirstSignFixtureWriterReleaseV1.close(owner, session: session, root: root)
            return archive
        }

        @MainActor func restoreAndClose(archive: URL) async throws -> UUID {
            let session = try StoreGenerationFactory(applicationSupportURL: targetRoot).openOrBootstrapCurrent()
            do {
                XCTAssertTrue(BackupRestoreService.isEmptyCurrent(session.modelContext))
                let importer = try BackupImportService(generationRootURL: session.generationRootURL,
                    scopedAccess: .alreadyAuthorized)
                let validated = try importer.stageAndValidate(selectedPackageURL: archive)
                let restored = try await BackupRestoreService(applicationSupportURL: targetRoot,
                    storagePreflight: StoragePreflightService(capacityProvider: { _ in .max })).restore(
                        validatedPackage: validated, currentModelContext: session.modelContext,
                        currentGenerationID: session.generationID,
                        currentGenerationRootURL: session.generationRootURL)
                let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
                let registry = try WorkspacePackageLifecycleProfileRegistryV1(profiles: [profile])
                let owner = try FirstSignFixtureWriterReleaseV1.makeOwner(session: restored,
                    profileRegistry: registry, root: targetRoot)
                // Restore consumed the staging package. Establish and release the
                // real restored writer before allowing a new factory open.
                try FirstSignFixtureWriterReleaseV1.close(owner, session: restored, root: targetRoot)
                XCTAssertFalse(fileManager.fileExists(atPath: validated.stagedPackageURL.path))
                return restored.generationID
            } catch {
                Self.retainedFailedTemporalRestores.append((targetRoot, session, error))
                throw error
            }
        }

        let expected = try await seedAndClose()
        let archive = try reopenExportAndClose(root: root, expected: expected,
            generationID: expected.generationID)
        let restoredGenerationID = try await restoreAndClose(archive: archive)
        // A second real archive/validation cycle after cold target reopen proves
        // typed companions remain exact through restore and repeated transport.
        _ = try reopenExportAndClose(root: targetRoot, expected: expected,
            generationID: restoredGenerationID)
        completed = true
    }

    @MainActor
    func testActiveEraseClearsLocalAuthorityThenOrdinaryRefreshRediscovers()
        async throws {
        let paths = try makeErasePaths("active")
        // No root-removal defer: the shared owner pins actual fixture resources
        // for host lifetime, including every admission/retirement failure.
        let probe = CommerceRuntimeProbe()
        let entitlementNow = Date(
            timeIntervalSince1970: floor(Date().timeIntervalSince1970)
        )
        let expiration = entitlementNow.addingTimeInterval(7_200)
        let fact = VerifiedEntitlementFactV1(
            productID: EntitlementReducerV1.productID,
            purchaseAt: entitlementNow.addingTimeInterval(-3_600),
            expirationAt: expiration,
            verifiedAt: entitlementNow,
            state: .active
        )
        let shippingRegistry = try WorkspacePackageLifecycleCompatibilityV1.shippingRegistry()
        let owner = V23EraseOperationHarnessV1(retainingRoot: paths.root,
            applicationSupportURL: paths.support,
            runtime: StoreKitEntitlementRuntimeV1(
                initialEvents: {
                    await probe.recordRefresh()
                    return [.verified(.init(fact: fact))]
                },
                transactionUpdates: { AsyncStream { $0.finish() } },
                statusUpdates: { AsyncStream { $0.finish() } }
            ), profileRegistry: shippingRegistry)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let siteID = UUID()
        weak var seededSession: StoreGenerationSession?
        weak var seededContext: ModelContext?
        weak var seededContainer: ModelContainer?
        weak var seededCoordinator: StoreSessionCoordinator?
        weak var seededRunner: CheckRunnerCoordinator?
        try await { @MainActor () async throws -> Void in
            let seeded = try StoreGenerationFactory(applicationSupportURL: paths.support)
                .openOrBootstrapCurrent()
            seededSession = seeded
            seededContext = seeded.modelContext
            seededContainer = seeded.modelContext.container
            var failedCoordinator: StoreSessionCoordinator?
            var failedRunner: CheckRunnerCoordinator?
            do {
                let seedWriter = try StoreSessionCoordinator(
                    validatingSession: seeded,
                    lifecycleProfileRegistry: shippingRegistry
                )
                failedCoordinator = seedWriter
                seededCoordinator = seedWriter
                let dependencies = try seedWriter.packageLifecycleDependencies()
                let profile = try WorkspacePackageLifecycleCompatibilityV1.shippingProfile()
                let mutationID = try dependencies.writer.makeMutationID()
                let assetID = UUID()
                let command = WorkspaceCommandV1.createFirstSign(FirstSignMutationV1(
                    siteID: siteID,
                    newSite: .init(
                        id: siteID,
                        label: "Erase site",
                        address: nil,
                        timeZoneID: "America/New_York"
                    ),
                    assetID: assetID,
                    assetLabel: "Erase sign",
                    packID: profile.package.packID,
                    packSchemaVersion: profile.package.schemaVersion,
                    packContentVersion: profile.package.contentVersion,
                    createdAt: createdAt,
                    initialPlacementMutationID: mutationID,
                    initialPlacementEventID: UUID(),
                    initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(rawValue: UUID())
                ))
                _ = try dependencies.writer.execute(command, mutationID: mutationID)
                let runner = try CheckRunnerCoordinator(
                    modelContext: seeded.modelContext,
                    packageLifecycleDependencies: dependencies,
                    packageLifecycleProfile: profile
                )
                failedRunner = runner
                seededRunner = runner
                runner.configureCapture(generationRootURL: seeded.generationRootURL)
                _ = try runner.beginCheck(
                    assetID: assetID,
                    timeZoneID: "America/New_York",
                    isTimeZoneConfirmed: true,
                    afterDarkAccepted: true,
                    safePositionAccepted: true,
                    observedAt: Date(timeIntervalSince1970: 1_768_800_000)
                )
                let result = try await runner.finalize(
                    assetID: assetID,
                    selection: .couldNotVerify(reasonKey: "conditions_changed", note: nil),
                    completedAt: Date(timeIntervalSince1970: 1_768_800_010),
                    snapshotCreatedAt: Date(timeIntervalSince1970: 1_768_800_011),
                    sourceApp: .init(build: "s7-erase", version: "1.0")
                )
                XCTAssertEqual(try rowCounts(seeded.modelContext), [1, 1, 1, 0, 0, 1, 1])
                XCTAssertEqual(
                    try seeded.modelContext.fetch(FetchDescriptor<Packet>()).map(\.id),
                    [result.packetID]
                )
                XCTAssertEqual(
                    try seeded.modelContext.fetch(FetchDescriptor<Report>()).map(\.id),
                    [result.reportID]
                )
                try seedWriter.invalidateAndReleaseWriter()
            } catch {
                // A failed checked writer close must retain the actual store
                // graph and physical root; it never licenses Router startup.
                Self.retainedFailedSeedGraphs.append((
                    root: paths.root,
                    session: seeded,
                    coordinator: failedCoordinator,
                    runner: failedRunner
                ))
                throw error
            }
        }()
        guard seededSession == nil, seededContext == nil, seededContainer == nil,
              seededCoordinator == nil, seededRunner == nil else {
            XCTFail("Seed aliases must drain before authentic Router startup")
            throw V23EraseOperationHarnessV1.Failure.drainPending
        }
        let cache = EntitlementCacheV1(
            productID: EntitlementReducerV1.productID,
            state: .active,
            expirationAt: entitlementNow.addingTimeInterval(3_600),
            graceExpirationAt: nil,
            revocationAt: nil,
            verifiedAt: entitlementNow,
            hasEverVerifiedPaid: true
        )
        _ = try EntitlementStore(applicationSupportURL: paths.support).persist(cache)
        let commerceURL = paths.support.appendingPathComponent("FieldEvidenceCommerce", isDirectory: true)
        XCTAssertTrue(fileManager.fileExists(atPath: commerceURL.path))
        let defaultsName = "S7_5-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: bundleID)
            defaults.removePersistentDomain(forName: defaultsName)
        }
        var eraseDiagnostics: DiagnosticsStore?
        var refreshesBeforeErase = 0
        var admittedReservation: AppAccessGateV1.EraseAdoptionToken?
        var completedReceipts: [CompletedEraseReceiptV1] = []
        weak var originalCoordinator: StoreSessionCoordinator?
        weak var originalContext: ModelContext?
        weak var originalContainer: ModelContainer?
        try await { @MainActor () async throws -> Void in
            let (coordinator, diagnostics) = try await owner.startOriginalOwner()
            eraseDiagnostics = diagnostics
            await owner.router.entitlementProcessor?.waitForInitialRefresh()
            refreshesBeforeErase = await probe.refreshCount
            XCTAssertEqual(refreshesBeforeErase, 1)
            await diagnostics.prepare()
            await diagnostics.increment(.reportSaved)
            // The original operation uses the Router's published writer.
            try await owner.admit(coordinator: coordinator)
            let service = try owner.configure(EraseAllService(
                applicationSupportURL: paths.support,
                cachesDirectoryURL: paths.caches,
                temporaryDirectoryURL: paths.temporary,
                userDefaults: defaults,
                bundleIdentifier: bundleID,
                admitErase: { subject in
                    let reservation = try await owner.admitSubject(subject)
                    admittedReservation = reservation
                    return reservation
                },
                didCompleteErase: { completedReceipts.append($0) }
            ))
            originalCoordinator = coordinator
            originalContext = coordinator.modelContext
            originalContainer = coordinator.modelContext.container
            try await owner.prepareCompatibility(service: service, confirmation: "ERASE",
                coordinator: coordinator, diagnostics: diagnostics)
        }()
        guard originalCoordinator == nil, originalContext == nil, originalContainer == nil else {
            XCTFail("Original aliases must drain before cleanup")
            throw V23EraseOperationHarnessV1.Failure.drainPending
        }
        XCTAssertTrue(completedReceipts.isEmpty)
        try await owner.completeCleanup() // Pending/false is a failure, as cleanupDeferred was.
        XCTAssertEqual(completedReceipts.count, 1)
        let deliveredReceipt = try XCTUnwrap(completedReceipts.first)
        let reservation = try XCTUnwrap(admittedReservation)
        XCTAssertEqual(deliveredReceipt.reservation, reservation)
        XCTAssertEqual(deliveredReceipt.subject, reservation.subject)
        XCTAssertFalse(fileManager.fileExists(atPath: commerceURL.path))
        let diagnosticsAfterErase = await (try XCTUnwrap(eraseDiagnostics)).snapshot()
        XCTAssertEqual(diagnosticsAfterErase, .zero)
        let refreshesBeforeOrdinaryStartup = await probe.refreshCount
        // Initial authentic startup already refreshed once; Erase itself must
        // perform no commerce refresh before its fresh post-adoption startup.
        XCTAssertEqual(refreshesBeforeOrdinaryStartup, refreshesBeforeErase)

        try await owner.adoptCompletedReceipt()
        // Inspect the completed empty generation under a genuine startup-read
        // token before ordinary startup may recreate local commerce state.
        let token = try await owner.accessGate.beginContentRead(for: .startupRecovery)
        weak var observedReader: StoreGenerationSession?
        weak var observedContext: ModelContext?
        weak var observedContainer: ModelContainer?
        let erasedCounts = try token.withContentRead(for: .startupRecovery) {
            try autoreleasepool {
                let reader = try StoreGenerationFactory(applicationSupportURL: paths.support)
                    .openOrBootstrapCurrent()
                observedReader = reader
                observedContext = reader.modelContext
                observedContainer = reader.modelContext.container
                return try rowCounts(reader.modelContext)
            }
        }
        XCTAssertEqual(erasedCounts, [0, 0, 0, 0, 0, 0, 0])
        guard observedReader == nil, observedContext == nil, observedContainer == nil else {
            XCTFail("Completed-generation observation must drain before ordinary activation.")
            throw V23EraseOperationHarnessV1.Failure.drainPending
        }
        XCTAssertFalse(fileManager.fileExists(atPath: commerceURL.path))
        try await owner.activateFreshOrdinarySession()
        let router = owner.router
        await router.entitlementProcessor?.waitForInitialRefresh()
        guard case let .ready(reopened, _, _) = router.route else {
            return XCTFail("Fresh post-Erase startup must reopen the erased generation.")
        }
        XCTAssertEqual(try rowCounts(reopened.modelContext), [0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(router.entitlementProcessor?.state, .entitled(.active, until: expiration))
        XCTAssertEqual(router.entitlementProcessor?.draftAccessState, .entitled)
        let refreshCount = await probe.refreshCount
        let syncCount = await probe.syncCount
        let finishCount = await probe.finishCount
        XCTAssertEqual(refreshCount, refreshesBeforeErase + 1)
        XCTAssertEqual(syncCount, 0)
        XCTAssertEqual(finishCount, 0)
        router.entitlementProcessor?.stop()
    }

}

private extension S7_5DataRightsIntegrationTests {
    struct ErasePaths {
        let root: URL
        let support: URL
        let caches: URL
        let temporary: URL
    }

    func makeApplicationSupport(_ name: String) throws -> URL {
        let url = fileManager.temporaryDirectory.appendingPathComponent(
            "S7_5-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    func makeErasePaths(_ name: String) throws -> ErasePaths {
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "S7_5-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        let library = root.appendingPathComponent("Library", isDirectory: true)
        let support = library.appendingPathComponent("Application Support", isDirectory: true)
        let caches = library.appendingPathComponent("Caches", isDirectory: true)
        let temporary = root.appendingPathComponent("tmp", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: caches, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
        return ErasePaths(root: root, support: support, caches: caches, temporary: temporary)
    }

    @MainActor
    func rowCounts(_ context: ModelContext) throws -> [Int] {
        [
            try context.fetchCount(FetchDescriptor<Site>()),
            try context.fetchCount(FetchDescriptor<Asset>()),
            try context.fetchCount(FetchDescriptor<WorkflowRecord>()),
            try context.fetchCount(FetchDescriptor<EvidenceFile>()),
            try context.fetchCount(FetchDescriptor<Issue>()),
            try context.fetchCount(FetchDescriptor<Packet>()),
            try context.fetchCount(FetchDescriptor<Report>()),
        ]
    }

}

private actor CommerceRuntimeProbe {
    private(set) var refreshCount = 0
    private(set) var syncCount = 0
    private(set) var finishCount = 0

    func recordRefresh() { refreshCount += 1 }
    func recordSync() { syncCount += 1 }
    func recordFinish() { finishCount += 1 }
}

extension S7_5DataRightsIntegrationTests {
    func testC36StagingBytesRemainOutsideBackupAndExport() {
        XCTAssertTrue(LocalContentStoreDraftBoundaryV1.requiresCanonicalCommit)
        XCTAssertFalse(LocalContentStoreDraftBoundaryV1.carriesEvidenceID)
        XCTAssertFalse(LocalContentStoreDraftBoundaryV1.storesStagingBytes)
        XCTAssertTrue(OwnedStorageLedgerV1.c36StagingExcludedFromBackup)
    }
}

extension S7_5DataRightsIntegrationTests {
    func testV23P03C34ProtectedDataDenialFallsBackWithoutWriter() throws {
        let workspace = WorkspaceID(rawValue: UUID(uuid: (0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x47, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x0d)))
        let target = try NavigationTargetV1(workspaceID: workspace, destination: .settings)
        let result = try RouteRegistryV1().resolve(target, context: .init(currentWorkspaceID: workspace, currentRevision: 0, protectedDataAvailable: false))
        XCTAssertEqual(result.disposition, .safeFallback)
        XCTAssertEqual(result.reason, .protectedDataUnavailable)
        XCTAssertEqual(result.target.destination, .today)
        XCTAssertEqual(result.canonicalMutationCount, 0)
        XCTAssertFalse(result.startsAutomaticWork)
    }
}

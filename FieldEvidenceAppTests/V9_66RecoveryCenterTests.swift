import Foundation
import XCTest

@testable import FieldEvidenceApp

private enum C01RecoveryCenterTestError: Error, Sendable {
    case fixtureMissing
    case unused
}

private struct C01RecoveryCenterCorpus: Decodable {
    let schema: String
    let schemaVersion: Int
    let cardID: String
    let corpusID: String
    let testOnly: Bool
    let synthetic: Bool
    let immutable: Bool
    let containsCustomerData: Bool
    let containsProductionSecrets: Bool
    let evidenceIDs: [String]
    let states: [String]
    let statePrecedence: [String]
    let authoritySources: [String]
    let operationalFailureCodes: [String]
    let support: Support
    let privacy: Privacy
    let encryptedBackup: EncryptedBackup
    let feedback: Feedback
    let interruptionBoundaries: [String]
    let recoveryCases: [String]
    let hostileCases: [String]
    let lifecycle: Lifecycle
    let forbiddenClaims: [String]

    struct Support: Decodable {
        let fullMembers: [String]
        let bootstrapMembers: [String]
        let maximumCanonicalBytes: Int
        let maximumMemberCount: Int
        let scratchPurpose: String
        let scratchMaximumBytes: UInt64
        let scratchMaximumLifetimeSeconds: TimeInterval
        let terminalResults: [String]
        let networkPermitted: Bool
        let automaticUpload: Bool
        let forbiddenFields: [String]
    }

    struct Privacy: Decodable {
        let statuses: [String]
        let blockedReasons: [String]
        let alwaysVisibleRoutes: [String]
        let readyStatus: String
        let customerDataInTelemetry: Bool
        let networkPermitted: Bool
    }

    struct EncryptedBackup: Decodable {
        let availabilityStates: [String]
        let innerKinds: [String]
        let protocolVersion: UInt16
        let uniformTypeIdentifier: String
        let fileExtension: String
        let innerBytesUnchanged: Bool
        let legacyClearReadersRemainAvailable: Bool
        let ordinaryRecoveryRequiresEncryptedBackup: Bool
        let journey: [String]
    }

    struct Feedback: Decodable {
        let categories: [String]
        let contactChoices: [String]
        let destinations: [String]
        let results: [String]
        let maximumMessageBytes: Int
        let maximumDraftCount: Int
        let storeSchemaVersion: Int
        let everyResultPreservesDraft: Bool
        let claimsDeliveredOrReceived: Bool
    }

    struct Lifecycle: Decodable {
        let projectionPersistence: String
        let presentationClockPersistence: String
        let feedbackDraftPersistence: String
        let feedbackDraftIncludedInWorkspaceBackup: Bool
        let canonicalWorkspaceWrites: Bool
        let secondRecoveryWriter: Bool
        let secondRouter: Bool
        let secretsPersisted: Bool
    }
}

private struct C01CoordinatorProbe: RecoverySupportExportPreparingV1,
    RecoveryFeedbackHandoffPerformingV1 {
    let supportResult: SupportExportResultV1
    let handoffResult: FeedbackHandoffResultV1

    func prepareSupportExport(
        mode: SupportBundleModeV1,
        cancellation: SupportExportCancellationV1
    ) async throws -> SupportExportResultV1 {
        supportResult
    }

    func handoff(_ preview: FeedbackHandoffPreviewV1) async throws -> FeedbackHandoffResultV1 {
        handoffResult
    }
}

private actor C01ScratchProbe: ScratchDataLeasePortV1 {
    private var resetCount = 0
    private var eraseCount = 0

    func acquireScratchLease(
        _ request: ScratchDataLeaseRequestV1
    ) async throws -> ScratchDataLeaseV1 {
        throw C01RecoveryCenterTestError.unused
    }

    func writeScratchData(
        _ data: Data,
        named: String,
        lease: ScratchDataLeaseV1
    ) async throws -> URL {
        throw C01RecoveryCenterTestError.unused
    }

    func releaseScratchLease(
        _ lease: ScratchDataLeaseV1,
        terminal: ScratchDataLeaseTerminalV1
    ) async throws {
        throw C01RecoveryCenterTestError.unused
    }

    func recoverScratchLeases() async throws -> ScratchDataLeaseRecoverySummaryV1 {
        throw C01RecoveryCenterTestError.unused
    }

    func resetScratchData() async throws {
        resetCount += 1
    }

    func eraseScratchData() async throws {
        eraseCount += 1
    }

    func counts() -> (reset: Int, erase: Int) {
        (resetCount, eraseCount)
    }
}

private enum C01RecoveryCenterTestSupport {
    static let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
    static let workspaceID = WorkspaceID(rawValue: uuid(1))
    static let candidateHead = String(repeating: "a", count: 40)
    static let candidateTree = String(repeating: "b", count: 40)

    static func uuid(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "c0100000-0000-4000-8000-%012x", slot))!
    }

    static func digest(_ character: Character = "c") -> String {
        String(repeating: String(character), count: 64)
    }

    static func fixture() throws -> C01RecoveryCenterCorpus {
        let bundle = Bundle(for: V9_66RecoveryCenterTests.self)
        let name = "V22P04C01RecoveryCenterCorpusV1"
        guard let url = bundle.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures/V22/RecoveryCenter"
        ) ?? bundle.url(forResource: name, withExtension: "json") else {
            throw C01RecoveryCenterTestError.fixtureMissing
        }
        return try JSONDecoder().decode(
            C01RecoveryCenterCorpus.self,
            from: Data(contentsOf: url)
        )
    }

    static func authoritySources(
        states: [RecoveryCenterStateV1]? = nil,
        freshness: [RecoverySourceFreshnessV1]? = nil,
        observedBase: UInt64 = 100
    ) throws -> [RecoveryAuthoritySnapshotV1] {
        let selectedStates = states ?? Array(repeating: .healthy, count: RecoveryAuthoritySourceV1.allCases.count)
        return try RecoveryAuthoritySourceV1.allCases.enumerated().map { index, source in
            let state = selectedStates[index]
            let selectedFreshness = freshness?[index]
                ?? (state == .checking ? .historic : .current)
            return try RecoveryAuthoritySnapshotV1(
                source: source,
                state: state,
                frontierRevision: UInt64(index + 1),
                frontierSHA256: digest(Character("0")),
                freshness: selectedFreshness,
                observedUptimeNanoseconds: observedBase + UInt64(index)
            )
        }
    }

    static func availability(
        reason: FeatureAvailabilityReasonV1,
        capability: CapabilityIDV1 = .encryptedBackup
    ) throws -> TypedAvailabilityAndFallbackReceiptV1 {
        let fallback: ManualFallbackActionV1
        if reason == .available {
            fallback = .noFallback
        } else {
            fallback = try CapabilityPermissionMatrixV1.current()
                .descriptor(for: capability)
                .manualFallback
        }
        return try TypedAvailabilityAndFallbackReceiptV1(
            candidateHead: candidateHead,
            candidateTree: candidateTree,
            providerID: "V23_P03_C54",
            providerSliceDigest: digest("d"),
            consumerID: "V23_P04_C01",
            capabilityID: capability,
            availabilityReason: reason,
            mandatoryCoreComplete: true,
            visibleFallback: fallback,
            persistenceDisposition: .deviceLocalOnly,
            dataDisposition: reason == .available
                ? .acceptedImmutableContent
                : .priorHistoryPreserved,
            reentryTrigger: reason == .available
                ? .capabilityStateChanged
                : .userInitiatedRetry,
            localizedVisibleStateKey: "recovery.encrypted-backup.state",
            localizedVisibleCopyKey: "recovery.encrypted-backup.copy",
            localizedNextActionKey: "recovery.encrypted-backup.next-action",
            fallbackTestArtifactIDs: ["V23-P03-C54-G01"],
            evidenceArtifactIDs: ["V23-P03-C54-G01"],
            zeroUnsupportedPublicClaim: true
        )
    }

    static func manifest(
        mode: SupportBundleModeV1 = .full
    ) throws -> SupportBundleManifestV1 {
        let diagnostic = SupportBundleManifestEntryV1(
            kind: .diagnosticSummary,
            relativeName: "diagnostic-summary.json",
            byteCount: 128,
            sha256: digest("e")
        )
        let entries: [SupportBundleManifestEntryV1]
        switch mode {
        case .bootstrapOnly:
            entries = [diagnostic]
        case .full:
            entries = [
                diagnostic,
                SupportBundleManifestEntryV1(
                    kind: .systemHealth,
                    relativeName: "system-health.json",
                    byteCount: 256,
                    sha256: digest("f")
                ),
            ]
        }
        return try SupportBundleManifestV1(
            bundleID: uuid(20),
            mode: mode,
            generatedAt: fixedDate,
            entries: entries,
            totalCanonicalByteCount: entries.reduce(0) { $0 + $1.byteCount }
        )
    }

    static func privacy(
        status: PrivacyPolicyReleaseStatusV1
    ) throws -> PrivacyPolicyStatusSnapshotV1 {
        let expected = digest("1")
        switch status {
        case .liveMatched:
            return try PrivacyPolicyStatusSnapshotV1(
                status: status,
                expectedReleaseSHA256: expected,
                observedReleaseSHA256: expected,
                bundledSummaryLocalizationKey: "privacy.summary.v1",
                livePolicyURL: URL(string: "https://example.invalid/privacy")
            )
        case .draftLocal:
            return try PrivacyPolicyStatusSnapshotV1(
                status: status,
                expectedReleaseSHA256: expected,
                observedReleaseSHA256: nil,
                bundledSummaryLocalizationKey: "privacy.summary.v1",
                livePolicyURL: nil
            )
        case .blocked:
            return try PrivacyPolicyStatusSnapshotV1(
                status: status,
                expectedReleaseSHA256: expected,
                observedReleaseSHA256: nil,
                bundledSummaryLocalizationKey: nil,
                livePolicyURL: nil,
                blockerReason: .missingLiveRelease
            )
        }
    }

    static func blockedPrivacy(
        reason: PrivacyPolicyBlockReasonV1
    ) throws -> PrivacyPolicyStatusSnapshotV1 {
        let expected = digest("1")
        let observed = reason == .releaseDigestMismatch ? digest("2") : nil
        return try PrivacyPolicyStatusSnapshotV1(
            status: .blocked,
            expectedReleaseSHA256: expected,
            observedReleaseSHA256: observed,
            bundledSummaryLocalizationKey: nil,
            livePolicyURL: nil,
            blockerReason: reason
        )
    }

    static func draft(
        idSlot: Int = 30,
        revision: UInt64 = 1,
        message: String = "Synthetic recovery feedback"
    ) throws -> SupportFeedbackDraftV1 {
        try SupportFeedbackDraftV1(
            draftID: uuid(idSlot),
            category: .recovery,
            message: message,
            contactChoice: .noContact,
            createdAt: fixedDate,
            updatedAt: fixedDate.addingTimeInterval(Double(revision - 1)),
            revision: revision
        )
    }

    static func draftWithAttachment() throws -> SupportFeedbackDraftV1 {
        let attachment = try SupportBundleAttachmentReferenceV1(
            bundleID: uuid(40),
            canonicalSHA256: digest("7"),
            byteCount: 256,
            expiresAt: fixedDate.addingTimeInterval(900)
        )
        return try SupportFeedbackDraftV1(
            draftID: uuid(41),
            category: .backup,
            message: "Synthetic backup recovery feedback",
            contactChoice: .includeEmail,
            supportBundle: attachment,
            createdAt: fixedDate,
            updatedAt: fixedDate,
            revision: 1
        )
    }

    static func builder(scratch: any ScratchDataLeasePortV1) -> SupportBundleBuilderV1 {
        SupportBundleBuilderV1(
            diagnostic: { () async throws -> PreparedDiagnosticExportV1 in
                throw C01RecoveryCenterTestError.unused
            },
            support: { () async throws -> DeviceOperationalSupportSnapshotV2 in
                throw C01RecoveryCenterTestError.unused
            },
            scratch: scratch,
            clock: { C01RecoveryCenterTestSupport.fixedDate },
            idSource: { C01RecoveryCenterTestSupport.uuid(90) }
        )
    }

    static func addJSONValue(
        _ value: Any,
        to data: Data,
        key: String
    ) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw C01RecoveryCenterTestError.fixtureMissing
        }
        object[key] = value
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

final class V9_66RecoveryCenterTests: XCTestCase {
    func testV23P04C01G01HealthyProjectionRoutesAndOptionalBackupAreCanonical() async throws {
        let corpus = try C01RecoveryCenterTestSupport.fixture()
        XCTAssertEqual(corpus.schema, "V22P04C01RecoveryCenterCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.cardID, "V23-P04-C01")
        XCTAssertTrue(corpus.testOnly)
        XCTAssertTrue(corpus.synthetic)
        XCTAssertTrue(corpus.immutable)
        XCTAssertFalse(corpus.containsCustomerData)
        XCTAssertFalse(corpus.containsProductionSecrets)
        XCTAssertEqual(
            corpus.evidenceIDs,
            [
                "V23-P04-C01-G01",
                "V23-P04-C01-A01",
                "V23-P04-C01-H01",
                "V23-P04-C01-I01",
                "V23-P04-C01-R01",
            ]
        )
        XCTAssertEqual(
            corpus.states,
            RecoveryCenterStateV1.allCases.map(\.rawValue)
        )
        XCTAssertEqual(
            corpus.statePrecedence,
            ReliabilityStateProjectionV1.statePrecedence.map(\.rawValue)
        )
        XCTAssertEqual(
            corpus.authoritySources.sorted(),
            RecoveryAuthoritySourceV1.allCases.map(\.rawValue).sorted()
        )
        XCTAssertEqual(
            corpus.operationalFailureCodes.sorted(),
            OperationalFailureCodeV1.allCases.map(\.rawValue).sorted()
        )

        let healthySources = try C01RecoveryCenterTestSupport.authoritySources()
        let clock = try FixedPresentationClockV1(nanoseconds: 10_000)
        let cancelledResult = try SupportExportResultV1(
            disposition: .cancelled,
            manifest: nil,
            lease: nil,
            fileURL: nil
        )
        let probe = C01CoordinatorProbe(
            supportResult: cancelledResult,
            handoffResult: .cancelled
        )
        let coordinator = RecoveryCenterCoordinatorV1(
            clock: clock,
            supportExport: probe,
            feedbackHandoff: probe
        )
        let projection = try coordinator.project(
            sources: healthySources,
            operationalFailures: [],
            encryptedBackupReceipt: try C01RecoveryCenterTestSupport.availability(
                reason: .available
            ),
            supportManifest: try C01RecoveryCenterTestSupport.manifest(),
            privacyPolicy: try C01RecoveryCenterTestSupport.privacy(status: .liveMatched)
        )
        XCTAssertEqual(projection.state, .healthy)
        XCTAssertEqual(projection.reliability.state, .healthy)
        XCTAssertEqual(projection.reliability.sources.count, RecoveryAuthoritySourceV1.allCases.count)
        XCTAssertEqual(projection.encryptedBackup.state, .available)
        XCTAssertTrue(projection.privacyData.isReady)
        XCTAssertEqual(projection.supportExportPreview?.entries.count, 2)
        XCTAssertFalse(projection.supportExportPreview?.containsCustomerContent ?? true)
        XCTAssertFalse(projection.supportExportPreview?.containsCustomerIdentifier ?? true)
        XCTAssertFalse(projection.supportExportPreview?.containsRawLogs ?? true)
        XCTAssertFalse(projection.supportExportPreview?.permitsAutomaticUpload ?? true)

        let route = RecoveryRouteV1(workspaceID: C01RecoveryCenterTestSupport.workspaceID)
        let routeRegistry = try RouteRegistryV1()
        try route.validate(using: routeRegistry)
        let target = try route.target
        XCTAssertEqual(target.destination, .recoveryCenter)
        XCTAssertEqual(target.root, .reports)
        XCTAssertEqual(target.requestedMode, .read)
        XCTAssertEqual(target.fallback.destination, .recoveryCenter)
        XCTAssertEqual(target.fallback.root, .reports)

        let routerRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("c01-startup-\(C01RecoveryCenterTestSupport.uuid(91).uuidString)")
        let router = await MainActor.run {
            StartupRouter(applicationSupportURL: routerRoot)
        }
        let bootstrap = await MainActor.run { router.recoveryBootstrapState }
        let restoreSession = await MainActor.run { router.maintenanceRestoreSession }
        let eraseSession = await MainActor.run { router.maintenanceEraseSession }
        XCTAssertEqual(bootstrap, .checking)
        XCTAssertNil(restoreSession)
        XCTAssertNil(eraseSession)

        try OperationalFailureRegistryV1.validate()
        let failures = try OperationalFailureCodeV1.allCases.map {
            try OperationalFailureV1(code: $0, occurredAt: C01RecoveryCenterTestSupport.fixedDate)
        }
        let presentations = try failures.map(RecoveryFailurePresentationV1.init(failure:))
        XCTAssertEqual(Set(presentations.map(\.code)), Set(OperationalFailureCodeV1.allCases))
        for presentation in presentations {
            let descriptor = try OperationalFailureRegistryV1.descriptor(for: presentation.code)
            XCTAssertEqual(presentation.owner, descriptor.owner)
            XCTAssertEqual(presentation.primaryAction, descriptor.primaryAction)
            XCTAssertEqual(presentation.fallbackAction, descriptor.fallbackAction)
            XCTAssertEqual(presentation.helpTopic, descriptor.helpTopic)
        }
        XCTAssertEqual(clock.nanoseconds, 10_000)
        XCTAssertFalse(RecoveryCenterCoordinatorBoundaryV1.performsCanonicalWrites)
        XCTAssertFalse(RecoveryCenterCoordinatorBoundaryV1.ownsRecoveryStore)
        XCTAssertFalse(RecoveryCenterCoordinatorBoundaryV1.ownsScratchStorage)
        XCTAssertFalse(RecoveryCenterCoordinatorBoundaryV1.ownsRouter)
    }

    func testV23P04C01A01ClosedStatesFreshnessPrivacyAndEntitlementFallbacksRemainVisible() async throws {
        let corpus = try C01RecoveryCenterTestSupport.fixture()
        XCTAssertEqual(corpus.states.count, 11)
        XCTAssertEqual(corpus.authoritySources.count, 11)
        XCTAssertEqual(corpus.support.fullMembers, ["DIAGNOSTIC_SUMMARY", "SYSTEM_HEALTH"])
        XCTAssertEqual(corpus.support.bootstrapMembers, ["DIAGNOSTIC_SUMMARY"])
        XCTAssertEqual(corpus.support.maximumCanonicalBytes, SupportBundleManifestV1.maximumCanonicalBytes)
        XCTAssertEqual(corpus.support.maximumMemberCount, SupportBundleManifestV1.maximumMemberCount)
        XCTAssertEqual(corpus.support.scratchPurpose, ScratchDataPurposeV1.supportExport.rawValue)
        XCTAssertEqual(corpus.support.scratchMaximumBytes, ScratchDataPurposeV1.supportExport.maximumByteCount)
        XCTAssertEqual(corpus.support.scratchMaximumLifetimeSeconds, ScratchDataPurposeV1.supportExport.maximumLifetimeSeconds)
        XCTAssertEqual(corpus.feedback.storeSchemaVersion, DeviceOperationalSupportStoreSchemaV3.version)

        let allStates = RecoveryCenterStateV1.allCases
        let mixedSources = try C01RecoveryCenterTestSupport.authoritySources(states: allStates)
        let mixedReliability = try ReliabilityStateProjectionV1(
            sources: mixedSources,
            operationalFailures: [],
            observedUptimeNanoseconds: 10_000
        )
        XCTAssertEqual(mixedReliability.state, .validationFailed)
        XCTAssertEqual(
            Set(mixedReliability.sources.map(\.state)),
            Set(RecoveryCenterStateV1.allCases)
        )

        let historicFreshness = Array(repeating: RecoverySourceFreshnessV1.current, count: 11)
            .enumerated()
            .map { $0.offset == 0 ? .historic : $0.element }
        let historic = try ReliabilityStateProjectionV1(
            sources: C01RecoveryCenterTestSupport.authoritySources(freshness: historicFreshness),
            operationalFailures: [],
            observedUptimeNanoseconds: 10_000
        )
        XCTAssertEqual(historic.state, .actionable)

        let unavailableFreshness = Array(repeating: RecoverySourceFreshnessV1.current, count: 11)
            .enumerated()
            .map { $0.offset == 0 ? .unavailable : $0.element }
        let unavailable = try ReliabilityStateProjectionV1(
            sources: C01RecoveryCenterTestSupport.authoritySources(freshness: unavailableFreshness),
            operationalFailures: [],
            observedUptimeNanoseconds: 10_000
        )
        XCTAssertEqual(unavailable.state, .validationFailed)

        let incomplete = try ReliabilityStateProjectionV1(
            sources: Array(try C01RecoveryCenterTestSupport.authoritySources().dropLast()),
            operationalFailures: [],
            observedUptimeNanoseconds: 10_000
        )
        XCTAssertEqual(incomplete.state, .validationFailed)
        let empty = try ReliabilityStateProjectionV1(
            sources: [],
            operationalFailures: [],
            observedUptimeNanoseconds: 10_000
        )
        XCTAssertEqual(empty.state, .validationFailed)

        let coordinatorProbe = C01CoordinatorProbe(
            supportResult: try SupportExportResultV1(
                disposition: .cancelled,
                manifest: nil,
                lease: nil,
                fileURL: nil
            ),
            handoffResult: .cancelled
        )
        let coordinator = RecoveryCenterCoordinatorV1(
            clock: try FixedPresentationClockV1(nanoseconds: 10_000),
            supportExport: coordinatorProbe,
            feedbackHandoff: coordinatorProbe
        )
        let incompleteProjection = try coordinator.project(
            sources: Array(try C01RecoveryCenterTestSupport.authoritySources().dropLast()),
            operationalFailures: [],
            encryptedBackupReceipt: try C01RecoveryCenterTestSupport.availability(
                reason: .packageNotEnabled
            ),
            supportManifest: nil,
            privacyPolicy: try C01RecoveryCenterTestSupport.privacy(status: .draftLocal)
        )
        XCTAssertEqual(incompleteProjection.state, .validationFailed)
        XCTAssertEqual(incompleteProjection.encryptedBackup.state, .unavailable)
        XCTAssertFalse(incompleteProjection.privacyData.isReady)
        XCTAssertTrue(incompleteProjection.privacyData.backupRouteVisible)
        XCTAssertTrue(incompleteProjection.privacyData.deleteRouteVisible)
        XCTAssertTrue(incompleteProjection.privacyData.eraseRouteVisible)
        XCTAssertTrue(incompleteProjection.privacyData.permissionRevocationRouteVisible)

        XCTAssertEqual(
            corpus.privacy.statuses,
            PrivacyPolicyReleaseStatusV1.allCases.map(\.rawValue)
        )
        for status in PrivacyPolicyReleaseStatusV1.allCases {
            let policy = try C01RecoveryCenterTestSupport.privacy(status: status)
            let data = try PrivacyDataProjectionV1(
                policy: policy,
                backupRouteVisible: true,
                deleteRouteVisible: true,
                eraseRouteVisible: true,
                permissionRevocationRouteVisible: true
            )
            XCTAssertEqual(data.isReady, status == .liveMatched)
        }
        for reason in PrivacyPolicyBlockReasonV1.allCases {
            XCTAssertNoThrow(try C01RecoveryCenterTestSupport.blockedPrivacy(reason: reason))
        }

        let descriptor = try CapabilityPermissionMatrixV1.current()
            .descriptor(for: .encryptedBackup)
        XCTAssertEqual(descriptor.manualFallback, .saveLocally)
        XCTAssertEqual(descriptor.scratchPurpose, .none)
        XCTAssertEqual(descriptor.requestTiming, .neverRequested)
        let notEntitled = FeatureAvailabilityPolicyV1().evaluate(
            FeatureAvailabilityInputsV1(
                packageEnabled: true,
                entitled: false,
                osAndDeviceSupported: true,
                permission: .notRequired,
                offlineContentAvailable: true,
                recoveryReady: true,
                workspacePolicyEnabled: true,
                packageRetired: false,
                temporarilyAvailable: true
            ),
            manualFallbackCapabilityID: .encryptedBackup
        )
        XCTAssertEqual(notEntitled.reason, .notEntitled)
        XCTAssertFalse(notEntitled.mayStartNewOperation)
        XCTAssertTrue(notEntitled.preservesEssentialOperations)
        XCTAssertFalse(RecoveryCenterLifecycleV1.ordinaryRecoveryRequiresEncryptedBackup)

        XCTAssertEqual(
            corpus.encryptedBackup.innerKinds,
            EncryptedPortableEnvelopeInnerKindV1.allCases.map(\.stableName)
        )
        XCTAssertEqual(corpus.encryptedBackup.protocolVersion, 1)
        XCTAssertEqual(
            EncryptedPortableEnvelopeProtocolReleaseV1.uniformTypeIdentifier,
            corpus.encryptedBackup.uniformTypeIdentifier
        )
        XCTAssertEqual(
            EncryptedPortableEnvelopeProtocolReleaseV1.fileExtension,
            corpus.encryptedBackup.fileExtension
        )
        XCTAssertFalse(EncryptedPortableEnvelopeInnerKindV1.acceptsServiceRequestKinds)
        XCTAssertTrue(ReviewExchangeProtectionV1.legacyClearReadersRemainAvailable)
        XCTAssertTrue(corpus.encryptedBackup.innerBytesUnchanged)
        XCTAssertTrue(corpus.encryptedBackup.legacyClearReadersRemainAvailable)
        XCTAssertFalse(corpus.encryptedBackup.ordinaryRecoveryRequiresEncryptedBackup)

        let bootstrapManifest = try C01RecoveryCenterTestSupport.manifest(mode: .bootstrapOnly)
        let bootstrapPreview = try SupportExportPreviewProjectionV1(manifest: bootstrapManifest)
        XCTAssertEqual(bootstrapPreview.entries.map(\.kind), [.diagnosticSummary])
        XCTAssertTrue(RecoveryCenterLifecycleV1.feedbackDraftIncludedInWorkspaceBackup == false)
    }

    func testV23P04C01H01HostileDuplicateFalseHealthyPrivacySupportAndDraftInputsFailClosed() throws {
        let corpus = try C01RecoveryCenterTestSupport.fixture()
        XCTAssertTrue(corpus.hostileCases.contains("FALSE_HEALTHY_PROJECTION"))
        XCTAssertTrue(corpus.hostileCases.contains("DUPLICATE_AUTHORITY_SOURCE"))
        XCTAssertTrue(corpus.hostileCases.contains("MISSING_AUTHORITY_SOURCE"))
        XCTAssertTrue(corpus.hostileCases.contains("FUTURE_AUTHORITY_UPTIME"))
        XCTAssertTrue(corpus.hostileCases.contains("CUSTOMER_DATA_IN_SUPPORT_BUNDLE"))
        XCTAssertTrue(corpus.hostileCases.contains("SUPPORT_ALLOWLIST_ESCALATION"))
        XCTAssertTrue(corpus.hostileCases.contains("PRIVACY_LIVE_URL_MISMATCH"))
        XCTAssertTrue(corpus.hostileCases.contains("ENCRYPTED_CAPABILITY_WRONG_KIND"))
        XCTAssertTrue(corpus.hostileCases.contains("FEEDBACK_DIGEST_TAMPER"))
        XCTAssertTrue(corpus.hostileCases.contains("FEEDBACK_UNKNOWN_KEY"))

        let healthy = try C01RecoveryCenterTestSupport.authoritySources()
        XCTAssertThrowsError(
            try ReliabilityStateProjectionV1(
                sources: healthy + [try XCTUnwrap(healthy.first)],
                operationalFailures: [],
                observedUptimeNanoseconds: 10_000
            )
        ) { error in
            XCTAssertEqual(error as? RecoveryCenterContractFailureV1, .inconsistentProjection)
        }
        let falseHealthy = try ReliabilityStateProjectionV1(
            sources: healthy,
            operationalFailures: [
                try OperationalFailureV1(
                    code: .backupRestoreFailed,
                    occurredAt: C01RecoveryCenterTestSupport.fixedDate
                ),
            ],
            observedUptimeNanoseconds: 10_000
        )
        XCTAssertEqual(falseHealthy.state, .actionable)
        XCTAssertFalse(falseHealthy.failures.isEmpty)

        let wrongCapability = try C01RecoveryCenterTestSupport.availability(
            reason: .packageNotEnabled,
            capability: .filesAndShare
        )
        XCTAssertThrowsError(try EncryptedBackupAvailabilityV1(receipt: wrongCapability)) {
            XCTAssertEqual($0 as? RecoveryCenterContractFailureV1, .inconsistentProjection)
        }
        XCTAssertThrowsError(
            try PrivacyPolicyStatusSnapshotV1(
                status: .liveMatched,
                expectedReleaseSHA256: C01RecoveryCenterTestSupport.digest("1"),
                observedReleaseSHA256: C01RecoveryCenterTestSupport.digest("2"),
                bundledSummaryLocalizationKey: "privacy.summary.v1",
                livePolicyURL: URL(string: "https://example.invalid/privacy")
            )
        ) { error in
            XCTAssertEqual(error as? RecoveryCenterContractFailureV1, .inconsistentProjection)
        }

        XCTAssertThrowsError(
            try SupportBundleManifestV1(
                bundleID: C01RecoveryCenterTestSupport.uuid(50),
                mode: .bootstrapOnly,
                generatedAt: C01RecoveryCenterTestSupport.fixedDate,
                entries: [
                    SupportBundleManifestEntryV1(
                        kind: .systemHealth,
                        relativeName: "system-health.json",
                        byteCount: 1,
                        sha256: C01RecoveryCenterTestSupport.digest("a")
                    ),
                ],
                totalCanonicalByteCount: 1
            )
        ) { error in
            XCTAssertEqual(error as? OperationalDiagnosticsValidationFailureV1, .privacyViolation)
        }
        XCTAssertThrowsError(
            try SupportBundleManifestV1(
                bundleID: C01RecoveryCenterTestSupport.uuid(51),
                mode: .full,
                generatedAt: C01RecoveryCenterTestSupport.fixedDate,
                entries: [
                    SupportBundleManifestEntryV1(
                        kind: .diagnosticSummary,
                        relativeName: "diagnostic-summary.json",
                        byteCount: SupportBundleManifestV1.maximumCanonicalBytes,
                        sha256: C01RecoveryCenterTestSupport.digest("a")
                    ),
                    SupportBundleManifestEntryV1(
                        kind: .systemHealth,
                        relativeName: "system-health.json",
                        byteCount: 1,
                        sha256: C01RecoveryCenterTestSupport.digest("b")
                    ),
                ],
                totalCanonicalByteCount: SupportBundleManifestV1.maximumCanonicalBytes + 1
            )
        )
        XCTAssertThrowsError(
            try SupportBundleManifestV1(
                bundleID: C01RecoveryCenterTestSupport.uuid(52),
                mode: .full,
                generatedAt: C01RecoveryCenterTestSupport.fixedDate,
                entries: [
                    SupportBundleManifestEntryV1(
                        kind: .diagnosticSummary,
                        relativeName: "diagnostic-summary.json",
                        byteCount: 1,
                        sha256: C01RecoveryCenterTestSupport.digest("a")
                    ),
                    SupportBundleManifestEntryV1(
                        kind: .diagnosticSummary,
                        relativeName: "diagnostic-summary-copy.json",
                        byteCount: 1,
                        sha256: C01RecoveryCenterTestSupport.digest("b")
                    ),
                ],
                totalCanonicalByteCount: 2
            )
        )

        let draft = try C01RecoveryCenterTestSupport.draft()
        let encoder = JSONEncoder()
        let encodedDraft = try encoder.encode(draft)
        let tamperedDigest = try C01RecoveryCenterTestSupport.addJSONValue(
            C01RecoveryCenterTestSupport.digest("9"),
            to: encodedDraft,
            key: "draftSHA256"
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(SupportFeedbackDraftV1.self, from: tamperedDigest)
        ) { error in
            XCTAssertEqual(error as? RecoveryCenterContractFailureV1, .invalidDigest)
        }
        let unknownKey = try C01RecoveryCenterTestSupport.addJSONValue(
            "not allowed",
            to: encodedDraft,
            key: "customerText"
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(SupportFeedbackDraftV1.self, from: unknownKey)
        )

        XCTAssertThrowsError(
            try SupportFeedbackDraftV1(
                draftID: C01RecoveryCenterTestSupport.uuid(53),
                category: .recovery,
                message: String(repeating: "x", count: SupportFeedbackDraftV1.maximumMessageBytes + 1),
                contactChoice: .noContact,
                createdAt: C01RecoveryCenterTestSupport.fixedDate,
                updatedAt: C01RecoveryCenterTestSupport.fixedDate,
                revision: 1
            )
        )
        XCTAssertThrowsError(
            try SupportFeedbackDraftStoreSnapshotV1(
                state: .empty,
                draft: draft,
                safeCopyAvailable: false
            )
        ) { error in
            XCTAssertEqual(error as? OperationalDiagnosticsValidationFailureV1, .invalidValue)
        }
        XCTAssertNoThrow(
            try SupportFeedbackDraftStoreSnapshotV1(
                state: .recoveryRequired,
                draft: nil,
                safeCopyAvailable: true
            )
        )

        XCTAssertFalse(RecoveryCenterLifecycleAdapterBoundaryV1.createsSecondStore)
        XCTAssertFalse(RecoveryCenterLifecycleAdapterBoundaryV1.createsSecondScratchLeaseStore)
        XCTAssertFalse(RecoveryCenterLifecycleAdapterBoundaryV1.writesWorkspaceTruth)
        XCTAssertFalse(RecoveryCenterLifecycleAdapterBoundaryV1.includesDraftInBackupOrExport)
        XCTAssertFalse(RecoveryCenterLifecycleAdapterBoundaryV1.usesNetworkOrAutomaticUpload)
        XCTAssertFalse(RecoveryCenterLifecycleAdapterBoundaryV1.persistsSecretFieldsOrPassphraseCredentials)
    }

    func testV23P04C01I01InterruptionCancellationAndReplayLeaveNoPartialCanonicalEffect() async throws {
        let corpus = try C01RecoveryCenterTestSupport.fixture()
        XCTAssertEqual(
            corpus.interruptionBoundaries,
            [
                "BEFORE_STAGING",
                "AFTER_STAGING",
                "BEFORE_CANONICAL_BOUNDARY",
                "AFTER_EFFECT_BEFORE_RECEIPT",
                "DURING_EVIDENCE_EXPORT",
                "RELAUNCH",
            ]
        )
        XCTAssertEqual(
            corpus.support.terminalResults,
            SupportExportDispositionV1.allCases.map(\.rawValue)
        )
        XCTAssertEqual(
            corpus.feedback.results,
            FeedbackHandoffResultV1.allCases.map(\.rawValue)
        )
        XCTAssertTrue(corpus.support.networkPermitted == false)
        XCTAssertTrue(corpus.support.automaticUpload == false)
        XCTAssertTrue(corpus.privacy.networkPermitted == false)
        XCTAssertTrue(corpus.lifecycle.canonicalWorkspaceWrites == false)

        let scratch = C01ScratchProbe()
        let builder = C01RecoveryCenterTestSupport.builder(scratch: scratch)
        let cancelled = try await builder.prepare(
            mode: .full,
            cancellation: SupportExportCancellationV1 { true }
        )
        XCTAssertEqual(cancelled.disposition, .cancelled)
        XCTAssertNil(cancelled.manifest)
        XCTAssertNil(cancelled.lease)
        XCTAssertNil(cancelled.fileURL)
        for disposition in [
            SupportExportDispositionV1.cancelled,
            .expired,
            .failed,
        ] {
            let result = try SupportExportResultV1(
                disposition: disposition,
                manifest: nil,
                lease: nil,
                fileURL: nil
            )
            XCTAssertNil(result.manifest)
            XCTAssertNil(result.lease)
            XCTAssertNil(result.fileURL)
        }

        let draft = try C01RecoveryCenterTestSupport.draft()
        let preview = try FeedbackHandoffPreviewV1(draft: draft, destination: .localOnly)
        let replayedPreview = try FeedbackHandoffPreviewV1(draft: draft, destination: .localOnly)
        XCTAssertEqual(preview, replayedPreview)
        XCTAssertEqual(preview.draftSHA256, draft.draftSHA256)
        XCTAssertEqual(preview.messageByteCount, draft.message.utf8.count)
        XCTAssertEqual(preview.totalByteCount, draft.message.utf8.count)

        let coordinatorProbe = C01CoordinatorProbe(
            supportResult: cancelled,
            handoffResult: .cancelled
        )
        let coordinator = RecoveryCenterCoordinatorV1(
            clock: try FixedPresentationClockV1(nanoseconds: 10_000),
            supportExport: coordinatorProbe,
            feedbackHandoff: coordinatorProbe
        )
        let supportOutcome = try await coordinator.prepareSupportPreview(
            mode: .full,
            cancellation: .never
        )
        XCTAssertEqual(supportOutcome.result.disposition, .cancelled)
        XCTAssertNil(supportOutcome.preview)
        let handoffOutcome = try await coordinator.handoffFeedback(
            draft: draft,
            destination: .localOnly
        )
        XCTAssertEqual(handoffOutcome, .cancelled)

        let sharedProbe = C01CoordinatorProbe(
            supportResult: try SupportExportResultV1(
                disposition: .shared,
                manifest: try C01RecoveryCenterTestSupport.manifest(),
                lease: nil,
                fileURL: nil
            ),
            handoffResult: .cancelled
        )
        let sharedCoordinator = RecoveryCenterCoordinatorV1(
            clock: try FixedPresentationClockV1(nanoseconds: 10_000),
            supportExport: sharedProbe,
            feedbackHandoff: sharedProbe
        )
        do {
            _ = try await sharedCoordinator.prepareSupportPreview(mode: .full)
            XCTFail("a terminal shared result cannot be reused as a prepared preview")
        } catch {
            XCTAssertEqual(error as? RecoveryCenterCoordinatorFailureV1, .invalidSupportResult)
        }

        let canceledDraftResults = FeedbackHandoffResultV1.allCases
        XCTAssertTrue(canceledDraftResults.allSatisfy(\.preservesDraft))
        XCTAssertFalse(FeedbackHandoffResultV1.claimsDeliveredOrReceived)
        XCTAssertEqual(
            FeedbackHandoffDestinationV1.allCases.map(\.rawValue),
            corpus.feedback.destinations
        )
        XCTAssertEqual(corpus.feedback.maximumMessageBytes, SupportFeedbackDraftV1.maximumMessageBytes)
        XCTAssertEqual(corpus.feedback.maximumDraftCount, DeviceOperationalSupportStoreSchemaV3.maximumFeedbackDrafts)
    }

    func testV23P04C01R01RecoveryFeedbackStoreResetEraseAndFJ11TruthRemainDurable() async throws {
        let corpus = try C01RecoveryCenterTestSupport.fixture()
        XCTAssertTrue(corpus.recoveryCases.contains("SAME_ID_AND_DIGEST_IS_IDEMPOTENT"))
        XCTAssertTrue(corpus.recoveryCases.contains("DIVERGENT_INPUTS_QUARANTINED"))
        XCTAssertTrue(corpus.recoveryCases.contains("ACCEPTED_GENERATION_PRESERVED"))
        XCTAssertTrue(corpus.recoveryCases.contains("IMMUTABLE_ARTIFACTS_PRESERVED"))
        XCTAssertTrue(corpus.recoveryCases.contains("RESET_AND_ERASE_CLEAR_DEVICE_OPERATIONAL_DATA"))
        XCTAssertTrue(corpus.recoveryCases.contains("SUPPORT_SCRATCH_EXPIRES_AND_IS_DELETED"))
        XCTAssertTrue(corpus.recoveryCases.contains("CORRUPT_DRAFT_SAFE_COPY_EXACT"))
        XCTAssertTrue(corpus.recoveryCases.contains("SAFE_COPY_REMOVED_BY_RESET_ERASE"))
        XCTAssertTrue(corpus.recoveryCases.contains("NO_PARTIAL_CANONICAL_SUCCESS"))
        XCTAssertEqual(corpus.feedback.maximumMessageBytes, SupportFeedbackDraftV1.maximumMessageBytes)
        XCTAssertEqual(corpus.feedback.maximumDraftCount, DeviceOperationalSupportStoreSchemaV3.maximumFeedbackDrafts)
        XCTAssertTrue(corpus.feedback.everyResultPreservesDraft)
        XCTAssertFalse(corpus.feedback.claimsDeliveredOrReceived)
        XCTAssertEqual(
            corpus.lifecycle.projectionPersistence,
            RecoveryCenterLifecycleV1.projectionPersistence
        )
        XCTAssertEqual(
            corpus.lifecycle.presentationClockPersistence,
            RecoveryCenterLifecycleV1.presentationClockPersistence
        )
        XCTAssertEqual(
            corpus.lifecycle.feedbackDraftPersistence,
            RecoveryCenterLifecycleV1.feedbackDraftPersistence
        )
        XCTAssertFalse(corpus.lifecycle.feedbackDraftIncludedInWorkspaceBackup)
        XCTAssertFalse(corpus.lifecycle.canonicalWorkspaceWrites)
        XCTAssertFalse(corpus.lifecycle.secondRecoveryWriter)
        XCTAssertFalse(corpus.lifecycle.secondRouter)
        XCTAssertFalse(corpus.lifecycle.secretsPersisted)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "c01-diagnostics-\(C01RecoveryCenterTestSupport.uuid(100).uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = DiagnosticsStore(
            applicationSupportURL: root,
            now: { C01RecoveryCenterTestSupport.fixedDate },
            capacityProvider: { _ in Int64.max }
        )
        let scratch = C01ScratchProbe()
        let adapter = RecoveryCenterLifecycleAdapterV1(
            store: store,
            supportBuilder: C01RecoveryCenterTestSupport.builder(scratch: scratch),
            scratch: scratch,
            feedbackHandoff: { _ in .cancelled }
        )

        let empty = try await adapter.feedbackDraftSnapshot()
        XCTAssertEqual(empty.state, .empty)
        XCTAssertNil(empty.draft)
        XCTAssertFalse(empty.safeCopyAvailable)
        let initialRecoveryCopy = try await adapter.feedbackRecoveryCopy()
        XCTAssertNil(initialRecoveryCopy)

        let draft = try C01RecoveryCenterTestSupport.draft()
        try await adapter.saveFeedbackDraft(draft, expectedRevision: nil)
        let saved = try await adapter.feedbackDraftSnapshot()
        XCTAssertEqual(saved.state, .available)
        XCTAssertEqual(saved.draft, draft)
        XCTAssertFalse(saved.safeCopyAvailable)

        let mailPreview = try FeedbackHandoffPreviewV1(
            draft: draft,
            destination: .mail
        )
        let handoffResult = try await adapter.handoff(mailPreview)
        XCTAssertEqual(handoffResult, .cancelled)

        let successor = try C01RecoveryCenterTestSupport.draft(revision: 2)
        let stalePreview = try FeedbackHandoffPreviewV1(
            draft: successor,
            destination: .mail
        )
        do {
            _ = try await adapter.handoff(stalePreview)
            XCTFail("a preview from a later draft revision must be rejected")
        } catch {
            XCTAssertEqual(error as? RecoveryCenterLifecycleAdapterFailureV1, .staleDraft)
        }

        do {
            try await adapter.discardFeedbackDraft(
                expectedDraftID: draft.draftID,
                expectedRevision: 2
            )
            XCTFail("a stale discard CAS must not remove the draft")
        } catch {
            XCTAssertNotNil(error)
        }
        try await adapter.discardFeedbackDraft(
            expectedDraftID: draft.draftID,
            expectedRevision: draft.revision
        )
        let discarded = try await adapter.feedbackDraftSnapshot()
        XCTAssertEqual(discarded.state, .empty)

        try await adapter.reset()
        try await adapter.erase()
        let scratchCounts = await scratch.counts()
        XCTAssertEqual(scratchCounts.reset, 1)
        XCTAssertEqual(scratchCounts.erase, 1)

        let corruptBytes = Data("{\"schemaVersion\":3,\"corrupt\":true}".utf8)
        let countersURL = root
            .appendingPathComponent("FieldEvidenceDiagnostics", isDirectory: true)
            .appendingPathComponent("counters.json", isDirectory: false)
        try corruptBytes.write(to: countersURL, options: .atomic)
        let corruptStore = DiagnosticsStore(
            applicationSupportURL: root,
            now: { C01RecoveryCenterTestSupport.fixedDate },
            capacityProvider: { _ in Int64.max }
        )
        let corruptAdapter = RecoveryCenterLifecycleAdapterV1(
            store: corruptStore,
            supportBuilder: C01RecoveryCenterTestSupport.builder(scratch: scratch),
            scratch: scratch,
            feedbackHandoff: { _ in .cancelled }
        )
        let recoverySnapshot = try await corruptAdapter.feedbackDraftSnapshot()
        XCTAssertEqual(recoverySnapshot.state, .recoveryRequired)
        XCTAssertTrue(recoverySnapshot.safeCopyAvailable)
        let recoveryCopy = try await corruptAdapter.feedbackRecoveryCopy()
        XCTAssertEqual(recoveryCopy, corruptBytes)
        try await corruptStore.resetOperationalSupport()
        let removedRecoveryCopy = try await corruptAdapter.feedbackRecoveryCopy()
        XCTAssertNil(removedRecoveryCopy)
        let recoveredEmpty = try await corruptAdapter.feedbackDraftSnapshot()
        XCTAssertEqual(recoveredEmpty.state, .empty)

        XCTAssertEqual(
            corpus.encryptedBackup.journey,
            [
                "CREATE",
                "SEPARATE_PASSPHRASE_HANDOFF",
                "WRONG_PASSPHRASE",
                "CORRECT_OPEN",
                "IMPORT",
                "CLEANUP",
            ]
        )
        XCTAssertTrue(EncryptedPortableEnvelopeClaimsV1.providesConfidentiality)
        XCTAssertTrue(EncryptedPortableEnvelopeClaimsV1.detectsModification)
        XCTAssertFalse(EncryptedPortableEnvelopeClaimsV1.establishesIdentity)
        XCTAssertFalse(EncryptedPortableEnvelopeClaimsV1.establishesAuthority)
        XCTAssertFalse(EncryptedPortableEnvelopeClaimsV1.establishesDelivery)
        XCTAssertFalse(EncryptedPortableEnvelopeClaimsV1.isDigitalSignature)
        XCTAssertFalse(EncryptedPortableEnvelopeClaimsV1.establishesExportExemption)

        let attachmentDraft = try C01RecoveryCenterTestSupport.draftWithAttachment()
        let attachmentPreview = try FeedbackHandoffPreviewV1(
            draft: attachmentDraft,
            destination: .mail
        )
        XCTAssertEqual(attachmentPreview.totalByteCount, attachmentPreview.messageByteCount + 256)
        XCTAssertEqual(attachmentPreview.supportBundle?.byteCount, 256)
        XCTAssertTrue(FeedbackHandoffResultV1.allCases.allSatisfy { $0.preservesDraft })
    }
}

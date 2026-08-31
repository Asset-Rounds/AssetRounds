import Foundation
import XCTest

@testable import FieldEvidenceApp

private struct C06OfflineReadinessCorpusV1: Decodable {
    struct Selector: Decodable { let id: String; let selector: String; let tier: String }
    struct Claims: Decodable {
        let allFlagsFalse: Bool
        let readinessIsDerived: Bool
        let sourceDriftIsStaleWithoutPartialSuccess: Bool
        let derivedViewRebuildPreservesRoundSessionAndCanonicalData: Bool
        let noPersistenceBackupDeleteOrExportClaim: Bool
        let optionalOnlyWarningMayStartFieldWork: Bool
        let mandatorySatisfactionRemainsExplicit: Bool
    }

    let schema: String
    let schemaVersion: Int
    let cardID: String
    let ordinal: Int
    let selectors: [Selector]
    let statuses: [String]
    let hostileVectors: [String]
    let interruptionVectors: [String]
    let recoveryVectors: [String]
    let forbidden: [String]
    let claims: Claims
    let statusFlags: [String: Bool]
}

private enum C06OfflineReadinessTestSupportV1 {
    static let digest = String(repeating: "a", count: 64)
    static let alternateDigest = String(repeating: "b", count: 64)
    static let checkedAt = Date(timeIntervalSince1970: 1_788_134_400)

    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }

    static func workspace(_ value: Int = 1) -> WorkspaceID { WorkspaceID(rawValue: id(971_000 + value)) }

    static func session(_ workspace: WorkspaceID, revision: UInt64 = 1) throws -> RoundSessionReferenceV1 {
        try RoundSessionReferenceV1(workspaceID: workspace, sessionID: id(972_001), revision: revision, sessionSHA256: digest)
    }

    static func package() throws -> RoundPackageReleaseReferenceV1 {
        try RoundPackageReleaseReferenceV1(packageReleaseID: digest, packageID: "c06-package", packageContentVersion: 1, packageSHA256: digest, workflowSHA256: alternateDigest)
    }

    static func asset() throws -> RoundAssetSelectionV1 {
        try RoundAssetSelectionV1(assetID: id(973_001), siteID: id(973_002), labelAtSelection: "C06 asset")
    }

    static func content(_ workspace: WorkspaceID, id: String = "c06-content") throws -> ContentReferenceV1 {
        try ContentReferenceV1(
            workspaceID: workspace.rawValue.uuidString.lowercased(), contentID: id, byteLength: 12,
            mediaType: "image/jpeg", digests: try ContentDigestSetV1([try ContentDigestV1(algorithm: .sha256, hexadecimalValue: digest)]),
            byteRole: .immutableOriginal, createdAt: "2026-08-31T00:00:00Z"
        )
    }

    static func fieldReferenceRequirement(_ workspace: WorkspaceID, releaseID: UUID = id(974_001)) throws -> OfflineReadinessFieldReferenceRequirementV1 {
        try OfflineReadinessFieldReferenceRequirementV1(
            workspaceID: workspace.rawValue.uuidString.lowercased(), releaseID: releaseID,
            releaseRevision: 1, releaseSHA256: digest, manifestSHA256: alternateDigest,
            bindingID: id(974_002), bindingRevision: 1, bindingSHA256: digest
        )
    }

    static func fieldReferenceObservation(_ expected: OfflineReadinessFieldReferenceRequirementV1) throws -> OfflineReadinessReferenceObservationV1 {
        try OfflineReadinessReferenceObservationV1(
            workspaceID: expected.workspaceID, releaseID: expected.releaseID, releaseRevision: expected.releaseRevision,
            releaseSHA256: expected.releaseSHA256, manifestSHA256: expected.manifestSHA256,
            bindingID: expected.bindingID, bindingRevision: expected.bindingRevision, bindingSHA256: expected.bindingSHA256,
            availability: .readyOffline, missingContentIDs: [], readinessSHA256: digest
        )
    }

    static func snapshot(
        workspace: WorkspaceID = C06OfflineReadinessTestSupportV1.workspace(), sessionRevision: UInt64 = 1,
        observedPackage: RoundPackageReleaseReferenceV1? = nil,
        contentRequirements: [OfflineReadinessContentRequirementV1] = [],
        contentObservations: [OfflineReadinessContentObservationV1]? = nil,
        expectedFieldReferences: [OfflineReadinessFieldReferenceRequirementV1] = [],
        protectedDataAvailable: Bool = true,
        storage: OfflineReadinessStorageObservationV1? = nil,
        clockState: OfflineReadinessClockStateV1 = .checked,
        checkedAt: Date = C06OfflineReadinessTestSupportV1.checkedAt,
        timeZoneIdentifier: String = "America/New_York",
        observedAssets: Set<UUID>? = nil,
        guidance: Set<String> = ["c06-guidance"]
    ) throws -> OfflineReadinessSnapshotV1 {
        let selectedAsset = try asset()
        let observations: [OfflineReadinessContentObservationV1]
        if let contentObservations {
            observations = contentObservations
        } else {
            observations = try contentRequirements.map {
                try OfflineReadinessContentObservationV1(
                    contentID: $0.reference.contentID, workspaceID: $0.reference.workspaceID, state: .missing
                )
            }
        }
        return try OfflineReadinessSnapshotV1(
            session: session(workspace, revision: sessionRevision), expectedPackage: try package(),
            observedPackage: observedPackage ?? (try package()), selectedAssets: [selectedAsset],
            observedAssetIDs: observedAssets ?? [selectedAsset.assetID], guidanceReferenceIDs: ["c06-guidance"],
            availableGuidanceReferenceIDs: guidance, contentRequirements: contentRequirements,
            contentObservations: observations, expectedFieldReferences: expectedFieldReferences, fieldReferenceReadiness: [],
            storage: storage ?? (try OfflineReadinessStorageObservationV1(capacityState: .checked, availableBytes: 10_000)),
            access: OfflineReadinessAccessObservationV1(protectedDataAvailable: protectedDataAvailable),
            checkedAt: checkedAt, timeZoneIdentifier: timeZoneIdentifier, clockState: clockState
        )
    }
}

final class V9_71OfflineReadinessManifestTests: XCTestCase {
    func testV23P04C06G01ReadyManifestDeterministicRepeatAndRevisionInvalidation() throws {
        let corpus = try loadCorpus(); assertCorpus(corpus, selector: "G01", tier: "GOLDEN")
        let snapshot = try C06OfflineReadinessTestSupportV1.snapshot()
        let first = try OfflineReadinessManifestBuilderV1.build(snapshot: snapshot)
        let repeated = try OfflineReadinessManifestBuilderV1.build(snapshot: snapshot)
        XCTAssertEqual(first.status, .ready)
        XCTAssertEqual(first, repeated)
        XCTAssertEqual(first.manifestSHA256, repeated.manifestSHA256)
        XCTAssertEqual(first.session.revision, 1)
        XCTAssertEqual(first.expectedPackage.packageSHA256, C06OfflineReadinessTestSupportV1.digest)
        XCTAssertEqual(first.requirements.map(\.state), [.satisfied, .satisfied, .satisfied, .satisfied, .satisfied, .satisfied])
        XCTAssertTrue(first.mayStartFieldWork)
        XCTAssertTrue(first.maySafelyCloseFieldWork)
        let samePrior = try OfflineReadinessManifestBuilderV1.build(snapshot: snapshot, previous: first)
        XCTAssertEqual(samePrior.status, .ready)
        XCTAssertFalse(samePrior.sourceBindingDrift)

        let laterCheckedAt = C06OfflineReadinessTestSupportV1.checkedAt.addingTimeInterval(60)
        let laterMaterialization = try OfflineReadinessManifestBuilderV1.build(
            snapshot: try C06OfflineReadinessTestSupportV1.snapshot(checkedAt: laterCheckedAt), previous: first
        )
        XCTAssertEqual(laterMaterialization.sourceSnapshotSHA256, first.sourceSnapshotSHA256)
        XCTAssertFalse(laterMaterialization.sourceBindingDrift)
        XCTAssertEqual(laterMaterialization.status, .ready)
        XCTAssertNotEqual(laterMaterialization.checkedAt, first.checkedAt)
        XCTAssertNotEqual(laterMaterialization.manifestSHA256, first.manifestSHA256)

        let timeZoneChanged = try OfflineReadinessManifestBuilderV1.build(
            snapshot: try C06OfflineReadinessTestSupportV1.snapshot(timeZoneIdentifier: "UTC"), previous: first
        )
        XCTAssertNotEqual(timeZoneChanged.sourceSnapshotSHA256, first.sourceSnapshotSHA256)
        XCTAssertTrue(timeZoneChanged.sourceBindingDrift)
        XCTAssertEqual(timeZoneChanged.status, .stale)
        XCTAssertEqual(timeZoneChanged.requirements.last?.reason, .sourceBindingDrift)

        let revised = try OfflineReadinessManifestBuilderV1.build(
            snapshot: try C06OfflineReadinessTestSupportV1.snapshot(sessionRevision: 2), previous: first
        )
        XCTAssertEqual(revised.status, .stale)
        XCTAssertEqual(revised.priorSourceSnapshotSHA256, first.sourceSnapshotSHA256)
        XCTAssertTrue(revised.sourceBindingDrift)
        XCTAssertEqual(revised.requirements.last?.reason, .sourceBindingDrift)
    }

    func testV23P04C06A01ColdLaunchRebootForceQuitReconstructsAndWarnsOnlyForOptionalContent() throws {
        let corpus = try loadCorpus(); assertCorpus(corpus, selector: "A01", tier: "ALTERNATE")
        XCTAssertTrue(OfflineReadinessManifestLifecycleV1.coldLaunchRequiresRebuild)
        XCTAssertTrue(OfflineReadinessManifestLifecycleV1.rebootRequiresRebuild)
        XCTAssertTrue(OfflineReadinessManifestLifecycleV1.terminationRequiresRebuild)
        let workspace = C06OfflineReadinessTestSupportV1.workspace(2)
        let reference = try C06OfflineReadinessTestSupportV1.content(workspace)
        let optional = try OfflineReadinessContentRequirementV1(reference: reference, mandatory: false)
        let cold = try OfflineReadinessManifestBuilderV1.build(snapshot: C06OfflineReadinessTestSupportV1.snapshot(workspace: workspace, contentRequirements: [optional]))
        let reboot = try OfflineReadinessManifestBuilderV1.build(snapshot: C06OfflineReadinessTestSupportV1.snapshot(workspace: workspace, contentRequirements: [optional]))
        XCTAssertEqual(cold, reboot)
        XCTAssertEqual(cold.status, .warning)
        XCTAssertEqual(cold.requirements.first(where: { $0.category == .content })?.manualFallback, .useApprovedManualProcedure)
    }

    func testV23P04C06H01MandatoryOptionalAndHostileReadinessMatrixFailsClosed() throws {
        let corpus = try loadCorpus(); assertCorpus(corpus, selector: "H01", tier: "HOSTILE")
        let workspace = C06OfflineReadinessTestSupportV1.workspace(3)
        let reference = try C06OfflineReadinessTestSupportV1.content(workspace)
        let mandatory = try OfflineReadinessContentRequirementV1(reference: reference, mandatory: true)
        let optional = try OfflineReadinessContentRequirementV1(reference: reference, mandatory: false)
        let wrongWorkspace = try OfflineReadinessContentObservationV1(contentID: reference.contentID, workspaceID: "other-workspace", state: .present, observedSHA256: C06OfflineReadinessTestSupportV1.digest, observedByteLength: 12)
        let blocked = try OfflineReadinessManifestBuilderV1.build(snapshot: C06OfflineReadinessTestSupportV1.snapshot(workspace: workspace, contentRequirements: [mandatory], contentObservations: [wrongWorkspace]))
        XCTAssertEqual(blocked.status, .blocked)
        XCTAssertEqual(blocked.requirements.first(where: { $0.category == .content })?.state, .wrongWorkspace)
        XCTAssertEqual(try OfflineReadinessManifestBuilderV1.build(snapshot: C06OfflineReadinessTestSupportV1.snapshot(observedAssets: [])).status, .blocked)
        XCTAssertEqual(try OfflineReadinessManifestBuilderV1.build(snapshot: C06OfflineReadinessTestSupportV1.snapshot(guidance: [])).status, .blocked)
        let corrupt = try OfflineReadinessContentObservationV1(contentID: reference.contentID, workspaceID: reference.workspaceID, state: .corrupt)
        let partial = try OfflineReadinessContentObservationV1(contentID: reference.contentID, workspaceID: reference.workspaceID, state: .partial)
        XCTAssertEqual(try OfflineReadinessManifestBuilderV1.build(snapshot: C06OfflineReadinessTestSupportV1.snapshot(workspace: workspace, contentRequirements: [mandatory], contentObservations: [corrupt])).status, .blocked)
        XCTAssertEqual(try OfflineReadinessManifestBuilderV1.build(snapshot: C06OfflineReadinessTestSupportV1.snapshot(workspace: workspace, contentRequirements: [mandatory], contentObservations: [partial])).status, .blocked)
        let warning = try OfflineReadinessManifestBuilderV1.build(snapshot: C06OfflineReadinessTestSupportV1.snapshot(workspace: workspace, contentRequirements: [optional]))
        XCTAssertEqual(warning.status, .warning)
        XCTAssertEqual(warning.requirements.first(where: { $0.category == .content })?.reason, .missingOptionalContent)
        XCTAssertTrue(warning.mandatoryRequirementsAreSatisfied)
        XCTAssertTrue(warning.mayStartFieldWork)
        XCTAssertFalse(warning.maySafelyCloseFieldWork)
        XCTAssertEqual(try OfflineReadinessManifestBuilderV1.build(snapshot: C06OfflineReadinessTestSupportV1.snapshot(protectedDataAvailable: false)).status, .blocked)
        XCTAssertEqual(try OfflineReadinessManifestBuilderV1.build(snapshot: C06OfflineReadinessTestSupportV1.snapshot(storage: try OfflineReadinessStorageObservationV1(capacityState: .unavailable, availableBytes: nil))).status, .blocked)
        XCTAssertEqual(try OfflineReadinessManifestBuilderV1.build(snapshot: C06OfflineReadinessTestSupportV1.snapshot(contentRequirements: [mandatory], storage: try OfflineReadinessStorageObservationV1(capacityState: .checked, availableBytes: Int64.max, reservedBytes: Int64.max))).status, .blocked)
        XCTAssertThrowsError(try C06OfflineReadinessTestSupportV1.snapshot(workspace: workspace, contentRequirements: [mandatory, mandatory]))
        XCTAssertThrowsError(try C06OfflineReadinessTestSupportV1.snapshot(workspace: workspace, contentObservations: [try OfflineReadinessContentObservationV1(contentID: "unknown-content", workspaceID: workspace.rawValue.uuidString.lowercased(), state: .missing)]))
        let expectedReference = try C06OfflineReadinessTestSupportV1.fieldReferenceRequirement(workspace)
        let exactReference = try C06OfflineReadinessTestSupportV1.fieldReferenceObservation(expectedReference)
        XCTAssertTrue(expectedReference.matches(exactReference))
        let unrelatedReference = try C06OfflineReadinessTestSupportV1.fieldReferenceRequirement(workspace, releaseID: C06OfflineReadinessTestSupportV1.id(974_003))
        XCTAssertFalse(unrelatedReference.matches(exactReference))
        let omittedReference = try OfflineReadinessManifestBuilderV1.build(snapshot: C06OfflineReadinessTestSupportV1.snapshot(workspace: workspace, expectedFieldReferences: [expectedReference]))
        XCTAssertEqual(omittedReference.status, .blocked)
        XCTAssertEqual(omittedReference.requirements.first(where: { $0.category == .fieldReference })?.state, .missing)
        XCTAssertEqual(try OfflineReadinessManifestBuilderV1.build(snapshot: C06OfflineReadinessTestSupportV1.snapshot(clockState: .uncheckable)).status, .blocked)
        XCTAssertTrue(Set(corpus.hostileVectors).isSuperset(of: Set(["missing-bytes", "corrupt-bytes", "partial-bytes", "overflow", "duplicate", "unknown-key", "noncanonical-decode"])))
    }

    func testV23P04C06I01CancellationTerminationBoundariesRejectPartialAndSourceDriftStales() throws {
        let corpus = try loadCorpus(); assertCorpus(corpus, selector: "I01", tier: "INTERRUPTION")
        let ready = try OfflineReadinessManifestBuilderV1.build(snapshot: C06OfflineReadinessTestSupportV1.snapshot())
        let bytes = try OfflineReadinessManifestCanonicalCodecV1.encode(ready)
        XCTAssertThrowsError(try OfflineReadinessManifestCanonicalCodecV1.decode(OfflineReadinessManifestV1.self, from: Data(bytes.dropLast())))
        XCTAssertThrowsError(try OfflineReadinessManifestCanonicalCodecV1.decode(OfflineReadinessManifestV1.self, from: bytes + Data(" ".utf8)))
        let unknown = Data(bytes.dropLast()) + Data(",\"unknown\":true}".utf8)
        XCTAssertThrowsError(try OfflineReadinessManifestCanonicalCodecV1.decode(OfflineReadinessManifestV1.self, from: unknown))
        var inconsistentRows = ready.requirements
        let clockIndex = try XCTUnwrap(inconsistentRows.firstIndex(where: { $0.requirementID == "clock" }))
        inconsistentRows[clockIndex] = try OfflineReadinessRequirementV1(requirementID: "clock", category: .clock, mandatory: true, state: .stale, reason: .clockOrTimeZoneChanged, remediation: .rebuildPreflight, manualFallback: .doNotStart)
        func assertForgedRowsReject(_ rows: [OfflineReadinessRequirementV1], status: OfflineReadinessStatusV1, sourceSnapshotSHA256: String = ready.sourceSnapshotSHA256) {
            XCTAssertThrowsError(try OfflineReadinessManifestV1(session: ready.session, expectedPackage: ready.expectedPackage, observedPackage: ready.observedPackage, selectedAssets: ready.selectedAssets, observedAssetIDs: ready.observedAssetIDs, guidanceReferenceIDs: ready.guidanceReferenceIDs, availableGuidanceReferenceIDs: ready.availableGuidanceReferenceIDs, contentRequirements: ready.contentRequirements, contentObservations: ready.contentObservations, expectedFieldReferences: ready.expectedFieldReferences, referenceObservations: ready.referenceObservations, requiredBytes: ready.requiredBytes, availableBytes: ready.availableBytes, storage: ready.storage, protectedDataAvailable: ready.protectedDataAvailable, checkedAt: ready.checkedAt, timeZoneIdentifier: ready.timeZoneIdentifier, clockState: ready.clockState, sourceSnapshotSHA256: sourceSnapshotSHA256, priorSourceSnapshotSHA256: ready.priorSourceSnapshotSHA256, requirements: rows, status: status))
        }
        assertForgedRowsReject(inconsistentRows, status: .ready)
        assertForgedRowsReject(ready.requirements, status: .ready, sourceSnapshotSHA256: C06OfflineReadinessTestSupportV1.alternateDigest)
        let semanticForges: [(OfflineReadinessRequirementCategoryV1, Bool, OfflineReadinessReasonV1, OfflineReadinessRemediationV1, OfflineReadinessManualFallbackV1)] = [
            (.binding, true, .clockOrTimeZoneChanged, .rebuildPreflight, .doNotStart),
            (.clock, false, .clockOrTimeZoneChanged, .rebuildPreflight, .doNotStart),
            (.clock, true, .sourceBindingDrift, .rebuildPreflight, .doNotStart),
            (.clock, true, .clockOrTimeZoneChanged, .restoreExactPackage, .doNotStart),
            (.clock, true, .clockOrTimeZoneChanged, .rebuildPreflight, .contactSupervisor),
        ]
        for forge in semanticForges {
            var rows = ready.requirements
            rows[clockIndex] = try OfflineReadinessRequirementV1(requirementID: "clock", category: forge.0, mandatory: forge.1, state: .stale, reason: forge.2, remediation: forge.3, manualFallback: forge.4)
            assertForgedRowsReject(rows, status: .stale)
        }
        let stale = try OfflineReadinessManifestBuilderV1.build(snapshot: C06OfflineReadinessTestSupportV1.snapshot(guidance: []), previous: ready)
        XCTAssertEqual(stale.status, .stale)
        XCTAssertFalse(stale.requirements.contains { $0.category == .binding && $0.state == .satisfied })
        XCTAssertEqual(corpus.interruptionVectors, ["snapshot", "readback", "build", "source-drift"])
    }

    func testV23P04C06R01DerivedViewDropAndRebuildPreservesSessionAndCanonicalData() throws {
        let corpus = try loadCorpus(); assertCorpus(corpus, selector: "R01", tier: "RECOVERY")
        XCTAssertEqual(OfflineReadinessManifestLifecycleV1.persistenceMode, "DERIVED_ONLY")
        XCTAssertFalse(OfflineReadinessManifestLifecycleV1.migrationRequired)
        XCTAssertFalse(OfflineReadinessManifestLifecycleV1.backupRestoreRequired)
        XCTAssertFalse(OfflineReadinessManifestLifecycleV1.exportReportRequired)
        XCTAssertEqual(OfflineReadinessManifestLifecycleV1.downgradeDisposition, "DROP_AND_REBUILD")
        let rebuilt = try OfflineReadinessManifestBuilderV1.build(snapshot: C06OfflineReadinessTestSupportV1.snapshot())
        let recovered = try OfflineReadinessManifestCanonicalCodecV1.decode(OfflineReadinessManifestV1.self, from: try OfflineReadinessManifestCanonicalCodecV1.encode(rebuilt))
        XCTAssertEqual(recovered.session, rebuilt.session)
        XCTAssertEqual(recovered.manifestSHA256, rebuilt.manifestSHA256)
        XCTAssertTrue(corpus.claims.derivedViewRebuildPreservesRoundSessionAndCanonicalData)
        XCTAssertTrue(corpus.claims.noPersistenceBackupDeleteOrExportClaim)
    }

    private func loadCorpus() throws -> C06OfflineReadinessCorpusV1 {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("FieldEvidenceAppTests/Fixtures/V22/OfflineReadiness/V22P04C06OfflineReadinessManifestCorpusV1.json")
        return try JSONDecoder().decode(C06OfflineReadinessCorpusV1.self, from: Data(contentsOf: url))
    }

    private func assertCorpus(_ corpus: C06OfflineReadinessCorpusV1, selector: String, tier: String) {
        XCTAssertEqual(corpus.schema, "V22P04C06OfflineReadinessManifestCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1); XCTAssertEqual(corpus.cardID, "V23-P04-C06"); XCTAssertEqual(corpus.ordinal, 94)
        XCTAssertEqual(corpus.selectors.map(\.id), ["G01", "A01", "H01", "I01", "R01"])
        XCTAssertEqual(corpus.selectors.first(where: { $0.id == selector })?.selector, "V23-P04-C06-\(selector)")
        XCTAssertEqual(corpus.selectors.first(where: { $0.id == selector })?.tier, tier)
        XCTAssertEqual(corpus.statuses, ["READY", "BLOCKED", "WARNING", "STALE"])
        XCTAssertTrue(corpus.claims.allFlagsFalse); XCTAssertTrue(corpus.claims.readinessIsDerived)
        XCTAssertTrue(corpus.claims.sourceDriftIsStaleWithoutPartialSuccess); XCTAssertTrue(corpus.statusFlags.values.allSatisfy { !$0 })
        XCTAssertTrue(corpus.claims.optionalOnlyWarningMayStartFieldWork); XCTAssertTrue(corpus.claims.mandatorySatisfactionRemainsExplicit)
    }
}

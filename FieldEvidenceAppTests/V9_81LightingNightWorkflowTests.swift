import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V9_81LightingNightWorkflowTests: XCTestCase {
    func testV23P04C18G01DayNightDeltaPreservesExpectedObservedAndExactFrontiers() throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(corpus.cardID, "V23-P04-C18")
        XCTAssertEqual(corpus.golden.workflowStates,
                       LightingNightWorkflowStateV1.allCases.map(\.rawValue).sorted())
        XCTAssertEqual(corpus.golden.expectedControlStates,
                       LightingExpectedControlStateV1.allCases.map(\.rawValue).sorted())
        XCTAssertEqual(corpus.golden.observedControlStates,
                       LightingObservedControlStateV1.allCases.map(\.rawValue).sorted())
        XCTAssertNotEqual(LightingExpectedControlStateV1.expectedOn.rawValue,
                          LightingObservedControlStateV1.appearedOn.rawValue)
        XCTAssertTrue(corpus.prohibitedClaims.contains("CAMERA_BANDING_IS_FLICKER"))

        let policy = try LightingRepairRecheckPolicyV1()
        XCTAssertEqual(policy.policyVersion, LightingRepairRecheckPolicyV1.currentVersion)
        XCTAssertNoThrow(try policy.validate())
        XCTAssertEqual(LightingRepairRecheckPolicyV1.requirement(for: .appearedUnlit),
                       .nightExpectedOnObservation)
        XCTAssertEqual(LightingRepairRecheckPolicyV1.requirement(for: .visiblePotentialElectricalIndicator),
                       .qualifiedElectricalOrStructuralVerification)
        XCTAssertEqual(LightingRepairRecheckPolicyV1.requirement(for: .glareConcern),
                       .relevantNightReobservation)
    }

    func testV23P04C18A01FreshNightSafetyAndIssueSpecificClosureFailClosed() throws {
        let policy = try LightingRepairRecheckPolicyV1()
        XCTAssertThrowsError(try policy.validate(requirement: .comparableQualifiedMeasurement,
                                                  for: .appearedUnlit))
        XCTAssertNoThrow(try policy.validate(requirement: .comparableQualifiedMeasurement,
                                              for: .appearedUnlit,
                                              hasScreenedVariance: true))
        XCTAssertThrowsError(try policy.validate(requirement: .nightExpectedOnObservation,
                                                  for: .supportDamage))
        XCTAssertNoThrow(try policy.validate(requirement: .qualifiedElectricalOrStructuralVerification,
                                              for: .supportDamage))
        let unsafe = Set([
            LightingDaySafetyStopReasonV1.siteAuthorityMissing,
            .routeUnavailable, .requiredPPEMissing, .emergencyReadinessMissing,
            .trafficControlMissing, .activeTrafficUnsafe, .observerPositionInaccessible,
            .observerPositionUnsafe, .observerPositionUnknown
        ])
        XCTAssertEqual(unsafe, Set(LightingDaySafetyStopReasonV1.allCases))
        XCTAssertTrue(try loadCorpus().hostileCases.contains("MISSING_FRESH_NIGHT_SAFETY"))
    }

    func testV23P04C18H01FortyFiveHostileMeasurementGroupingAndClaimCasesFailClosed() throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(corpus.hostileCases.count, 45)
        XCTAssertEqual(Set(corpus.hostileCases).count, 45)
        XCTAssertEqual(corpus.hostileCases, corpus.hostileCases.sorted())
        let required = [
            "APP_CAMERA_BANDING_ASSERTED_AS_FLICKER",
            "INCOMPLETE_MEASUREMENT_GRID",
            "INCONCLUSIVE_UNCERTAINTY_REPORTED_AS_PASS",
            "GROUP_CLOSURE_PROPAGATES_TO_CHILDREN",
            "DUPLICATE_REOPEN_OF_SAME_RECHECK",
            "REOPEN_REFERENCES_NONEXISTENT_RECHECK",
            "UNKNOWN_OR_NOT_OBSERVED_AS_PASS",
            "REVISION_OVERFLOW",
            "CROSS_WORKSPACE_ISSUE_BINDING"
        ]
        XCTAssertTrue(Set(required).isSubset(of: Set(corpus.hostileCases)))
        XCTAssertTrue(corpus.hostileCases.contains("PATROL_ROUND_ITEM_COMPLETION_MISMATCH"))
        let patrolWorkspace = WorkspaceID(rawValue: id(20))
        let round = try RoundSessionReferenceV1(
            workspaceID: patrolWorkspace, sessionID: id(21), revision: 3,
            sessionSHA256: digest("1")
        )
        let completion = try RoundItemCompletionReferenceV1(
            completionID: id(22), revision: 2, completionSHA256: digest("2")
        )
        let patrol = LightingPatrolReferenceV1(round: round, itemID: id(23), completion: completion)
        XCTAssertNoThrow(try patrol.validate(workspaceID: patrolWorkspace))
        XCTAssertThrowsError(try patrol.validate(workspaceID: WorkspaceID(rawValue: id(24))))
        XCTAssertThrowsError(try LightingNightWorkflowLimitsV1.next(UInt64.max))

        let incomplete = LightingQualifiedMeasurementReferenceV1(
            planID: id(1), planRevision: 1, planSHA256: digest("a"),
            seriesID: id(2), seriesRevision: 1, seriesSHA256: digest("b"),
            protocolReleaseID: id(3), protocolVersion: 1, protocolSHA256: digest("c"),
            instrumentID: id(4), instrumentRevision: 1, instrumentSHA256: digest("d"),
            calibrationSnapshotID: id(5), calibrationSHA256: digest("e"), criterionSHA256: digest("f"),
            usedUnroundedCanonicalValues: false, completeSingleVersionGrid: true,
            uncertaintyCrossesCriterion: false, disposition: .withinRecordedCriterion)
        XCTAssertThrowsError(try incomplete.validate())

        let uncertainty = LightingQualifiedMeasurementReferenceV1(
            planID: id(1), planRevision: 1, planSHA256: digest("a"),
            seriesID: id(2), seriesRevision: 1, seriesSHA256: digest("b"),
            protocolReleaseID: id(3), protocolVersion: 1, protocolSHA256: digest("c"),
            instrumentID: id(4), instrumentRevision: 1, instrumentSHA256: digest("d"),
            calibrationSnapshotID: id(5), calibrationSHA256: digest("e"), criterionSHA256: digest("f"),
            usedUnroundedCanonicalValues: true, completeSingleVersionGrid: true,
            uncertaintyCrossesCriterion: true,
            disposition: .inconclusiveUncertaintyCrossesCriterion)
        XCTAssertNoThrow(try uncertainty.validate())
    }

    func testV23P04C18I01CanonicalWriterInterruptionRecoveryIsIdempotent() throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(corpus.interruptionCases,
                       ["PREPARE_BEFORE_EFFECT", "EFFECT_BEFORE_RECEIPT", "RECEIPT_BEFORE_PROJECTION_REBUILD"])
        let policy = try LightingRepairRecheckPolicyV1()
        let encoded = try LightingCanonicalCodecV1.encode(policy)
        let reopened = try LightingCanonicalCodecV1.decode(LightingRepairRecheckPolicyV1.self, from: encoded)
        let retry = try LightingCanonicalCodecV1.encode(reopened)
        XCTAssertEqual(encoded, retry)
        XCTAssertEqual(policy, reopened)
        XCTAssertEqual(try LightingCanonicalCodecV1.sha256(policy),
                       try LightingCanonicalCodecV1.sha256(reopened))
        XCTAssertFalse(encoded.isEmpty)
    }

    func testV23P04C18R01BackupClonePatrolSearchAndReportRemainExactAndDerived() throws {
        let lifecycle = try loadCorpus().lifecycle
        XCTAssertEqual(lifecycle.backupRestore, "PRESERVE_EXACT_CANONICAL_ROW")
        XCTAssertEqual(lifecycle.cloneFork,
                       "REBIND_FACTS_CLEAR_ACTIVE_OCCURRENCE_PATROL_READINESS_CLAIMS")
        XCTAssertEqual(lifecycle.deleteErase, "REMOVE_EXACT_ROW")
        XCTAssertEqual(lifecycle.patrol, "EXACT_ROUND_SESSION_ITEM_COMPLETION_REFERENCE")
        XCTAssertEqual(lifecycle.report, "DERIVED_FROM_CANONICAL_ROW")
        XCTAssertEqual(lifecycle.search, "DERIVED_FROM_CANONICAL_ROW")
        XCTAssertEqual(lifecycle.readiness, "DERIVED_ONLY")
        XCTAssertTrue(try loadCorpus().hostileCases.contains("SOURCE_PATROL_SURVIVES_REBOUND"))
        XCTAssertTrue(try loadCorpus().hostileCases.contains("SOURCE_OCCURRENCE_SURVIVES_REBOUND"))
        XCTAssertTrue(try loadCorpus().hostileCases.contains("SOURCE_READINESS_SURVIVES_REBOUND"))
        XCTAssertTrue(try loadCorpus().hostileCases.contains("SOURCE_CLAIM_SURVIVES_REBOUND"))
        XCTAssertEqual(LightingNightWorkflowV1.schemaVersion, 1)
        XCTAssertEqual(LightingNightWorkflowPersistenceEnrollmentV1.persistentSchemaVersion, 53)
        XCTAssertEqual(LightingNightWorkflowPersistenceEnrollmentV1.durableModelCount, 1)
        XCTAssertEqual(LightingNightWorkflowPersistenceEnrollmentV1.totalModelCount, 168)
        XCTAssertTrue(LightingNightWorkflowPersistenceEnrollmentV1.usesGenericMutationReceiptOnly)
        XCTAssertFalse(LightingNightWorkflowPersistenceEnrollmentV1.derivedProjectionIsPersistent)
    }

    private func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "c1800000-0000-4000-8000-%012x", slot))!
    }

    private func digest(_ value: Character) -> String { String(repeating: String(value), count: 64) }

    private func loadCorpus() throws -> Corpus {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V23/Lighting/V23P04C18LightingNightWorkflowCorpusV1.json")
        return try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
    }

    private struct Corpus: Decodable {
        let cardID: String; let schema: String; let schemaVersion: Int
        let golden: Golden; let hostileCases: [String]; let interruptionCases: [String]
        let lifecycle: Lifecycle; let prohibitedClaims: [String]
    }
    private struct Golden: Decodable {
        let workflowStates: [String]; let expectedControlStates: [String]; let observedControlStates: [String]
    }
    private struct Lifecycle: Decodable {
        let backupRestore: String; let cloneFork: String; let deleteErase: String
        let patrol: String; let report: String; let search: String; let readiness: String
    }
}

import Foundation
import XCTest

@testable import FieldEvidenceApp

final class V9_83GuidedSurveyFlowTests: XCTestCase {
    private struct Corpus: Decodable {
        let cardID: String
        let caseCount: Int
        let cases: [Case]
        struct Case: Decodable { let category: String; let expected: String; let id: String; let scenario: String }
    }

    private func corpus() throws -> Corpus {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V23/Surveys/V23P04C20GuidedSurveyFlowCorpusV1.json")
        return try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
    }

    func testV23P04C20G01TwoReleasesAuthorRunReviewPublishAndOfflineReport() throws {
        let policy = try SurveyAuthoringPolicyV1()
        try policy.validate()
        XCTAssertEqual(GuidedSurveyFlowPersistenceV1.mode, "DERIVED_NONPERSISTENT")
        XCTAssertEqual(GuidedSurveyFlowPersistenceV1.persistentSchemaVersion, 53)
        XCTAssertEqual(GuidedSurveyFlowPersistenceV1.activeModelCount, 168)
        XCTAssertFalse(GuidedSurveyFlowPersistenceV1.addsDurableRows)
        XCTAssertFalse(policy.allowsGenericEAV)
        XCTAssertFalse(policy.allowsPassFail)
        XCTAssertEqual(SurveyDefinitionLifecycleV1.writer, "SOLE_CANONICAL_WORKSPACE_WRITER")
        XCTAssertEqual(SurveyDefinitionLifecycleV1.importDisposition,
                       "QUARANTINE_THEN_NEW_DRAFT_IDENTITY")
    }

    func testV23P04C20A01AllClosedFieldsConditionalRepeatUnknownAndPoseParity() throws {
        let policy = try SurveyAuthoringPolicyV1()
        XCTAssertEqual(policy.allowedFieldKinds.map(\.rawValue),
                       SurveyFieldKindV1.allCases.map(\.rawValue).sorted())
        XCTAssertEqual(policy.allowedFieldKinds.count, 18)
        let noPose = try GuidedSurveyPoseRequirementV1(release: nil)
        try noPose.validate()
        XCTAssertTrue(noPose.applicableAxes.isEmpty)
        XCTAssertFalse(noPose.manualEntryAvailable)
        XCTAssertFalse(noPose.notObservedAvailable)
        XCTAssertTrue(SurveyBooleanObservationV1.allCases.contains(.unknown))
        XCTAssertTrue(SurveyBooleanObservationV1.allCases.contains(.notObserved))
        XCTAssertEqual(SurveyDefinitionLimitsV1.maximumRepeatCount, 128)
    }

    func testV23P04C20H01HostileDefinitionsImportsConflictsAndPrivacyFailClosed() throws {
        let value = try corpus()
        XCTAssertEqual(value.cardID, "V23-P04-C20")
        XCTAssertEqual(value.caseCount, 45)
        XCTAssertEqual(value.cases.count, 45)
        XCTAssertEqual(value.cases.map(\.id), value.cases.map(\.id).sorted())
        XCTAssertEqual(Set(value.cases.map(\.id)).count, 45)
        XCTAssertTrue(value.cases.contains { $0.scenario == "conditional rule cycle" })
        XCTAssertTrue(value.cases.contains { $0.scenario == "archive traversal" })
        XCTAssertTrue(value.cases.contains { $0.scenario == "report exposes hidden prior fact" })
        XCTAssertTrue(value.cases.contains { $0.scenario == "private direction field" })
    }

    func testV23P04C20I01PauseKillResumeAndPublishRecoveryRemainIdempotent() throws {
        XCTAssertTrue(SurveySessionTransitionV1.allCases.contains(.pause))
        XCTAssertTrue(SurveySessionTransitionV1.allCases.contains(.resume))
        XCTAssertTrue(SurveySessionTransitionV1.allCases.contains(.complete))
        XCTAssertEqual(SurveySessionScheduleBoundaryV1.dueProjectionMayCreateSession, false)
        XCTAssertTrue(SurveyDefinitionLifecycleActionV1.allCases.contains(.duplicateAsDraft))
        XCTAssertTrue(SurveyDefinitionLifecycleActionV1.allCases.contains(.importAsDraft))
        let interruption = try corpus().cases.filter { $0.category == "PUBLICATION" && $0.expected == "RECOVER" }
        XCTAssertEqual(interruption.count, 2)
    }

    func testV23P04C20R01RestoreSearchReportAndPromotionPreserveFrozenPublication() throws {
        let policy = try SurveyAuthoringPolicyV1()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(policy)
        let restored = try JSONDecoder().decode(SurveyAuthoringPolicyV1.self, from: data)
        try restored.validate()
        XCTAssertEqual(restored, policy)
        XCTAssertEqual(SurveySessionEraseBoundaryV1.atomicFamilyCount, 5)
        XCTAssertTrue(SurveySessionEraseBoundaryV1.ordinaryDeletionPreservesPublicationAndCaptureHistory)
        XCTAssertTrue(SurveyDefinitionEraseBoundaryV1.workspaceEraseClearsIdentityAndReleaseRows)
        XCTAssertTrue(try corpus().cases.contains {
            $0.scenario == "restore retains exact immutable publication" && $0.expected == "EXACT"
        })
    }
}

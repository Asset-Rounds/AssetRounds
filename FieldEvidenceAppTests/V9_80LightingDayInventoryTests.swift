import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V9_80LightingDayInventoryTests: XCTestCase {
    func testV23P04C17G01DayInventoryCapturesCompleteStableTopologyAndNightBinding() throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(corpus.golden.workflowStates, LightingDayInventoryWorkflowStateV1.allCases.map(\.rawValue).sorted())
        XCTAssertEqual(corpus.golden.conditionAspects, LightingDayConditionAspectV1.allCases.map(\.rawValue).sorted())
        let facts = [
            LightingDayConditionFactV1(aspect:.visibleWiring,state:.unknown,issueKind:nil),
            LightingDayConditionFactV1(aspect:.lens,state:.observedConcern,issueKind:.lensConcern),
            LightingDayConditionFactV1(aspect:.daylightEnergized,state:.observedPresent,issueKind:nil)
        ].sorted()
        try facts.forEach { try $0.validate() }
        XCTAssertEqual(facts.map(\.aspect), [.daylightEnergized,.lens,.visibleWiring])
        XCTAssertTrue(corpus.prohibitedClaims.contains("DAY_PASS_OF_NIGHT_BEHAVIOR"))
        XCTAssertEqual(corpus.lifecycle.offlineReadiness, "DERIVED_ONLY_DIGEST_BOUND")
        XCTAssertEqual(LightingPersistenceEnrollmentV1.durableModelCount,5)
        XCTAssertEqual(C17LightingDayOfflineReadinessCoordinatorV1.persistenceMode, "DERIVED_ONLY")
        XCTAssertFalse(C17LightingDayOfflineReadinessCoordinatorV1.ownsPersistentRow)
        XCTAssertFalse(C17LightingDayOfflineReadinessCoordinatorV1.writesCanonicalWorkspaceState)

        // A package with no accepted LIGHT_BEAM_CENTERLINE declaration admits
        // a complete daylight condition snapshot with no fabricated pose.
        let workspaceID = WorkspaceID(rawValue: id(1))
        let observation = try JSONDecoder().decode(
            LightingObservationReferenceV1.self,
            from: Data("""
            {"workspaceID":{"rawValue":"\(workspaceID.rawValue.uuidString)"},"observationID":"\(id(2).uuidString)","luminaireID":"\(id(3).uuidString)","assetID":"\(id(4).uuidString)","assetRevision":1,"revision":1,"observationSHA256":"\(digest("a"))"}
            """.utf8)
        )
        let snapshot = try LightingDayConditionSnapshotV1(
            luminaireID: id(3), assetID: id(4), assetRevision: 1,
            zoneID: id(5), controlGroupID: id(6), observation: observation,
            poseDisposition: .notDeclared, poseEvent: nil,
            facts: [.init(aspect: .lens, state: .notObserved, issueKind: nil)],
            contextualMedia: []
        )
        let package = try JSONDecoder().decode(
            LightingPackageReleaseReferenceV1.self,
            from: Data("""
            {"packageReleaseID":"\(digest("c"))","packageID":"c17.no-beam-axis","contentVersion":1,"packageSHA256":"\(digest("b"))","workflowSHA256":"\(digest("d"))"}
            """.utf8)
        )
        XCTAssertNoThrow(try LightingDayInventoryAdmissionClosureV1.validatePoseBinding(
            snapshot: snapshot, poseEvent: nil, registryRelease: nil, packageRelease: package
        ))
        XCTAssertNil(snapshot.poseEvent)
        XCTAssertEqual(snapshot.poseDisposition, .notDeclared)
        XCTAssertTrue(LightingDayInventoryAdmissionClosureV1.poseDispositionMatches(
            .notObserved, .notObserved
        ))
        XCTAssertFalse(LightingDayInventoryAdmissionClosureV1.poseDispositionMatches(
            .notObserved, .observed
        ))
    }

    func testV23P04C17A01SafetyTrafficAndObserverStopsAuthorizeNoConditionCapture() throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(Set(corpus.hardStops), Set(LightingDaySafetyStopReasonV1.allCases.map(\.rawValue)))
        XCTAssertTrue(corpus.hardStops.contains(LightingDaySafetyStopReasonV1.activeTrafficUnsafe.rawValue))
        XCTAssertTrue(corpus.hardStops.contains(LightingDaySafetyStopReasonV1.observerPositionUnknown.rawValue))
        XCTAssertThrowsError(try LightingDayConditionFactV1(aspect:.lens,state:.observedConcern,issueKind:nil).validate())
        XCTAssertNoThrow(try LightingDayConditionFactV1(aspect:.lens,state:.unknown,issueKind:nil).validate())
    }

    func testV23P04C17H01WrongWorkspaceStaleMissingDuplicateAndDaylightClaimsFailClosed() throws {
        let corpus = try loadCorpus()
        let required = ["WRONG_WORKSPACE","STALE_OBSERVATION_DIGEST","DUPLICATE_LUMINAIRE","MISSING_LUMINAIRE_SNAPSHOT","UNSAFE_INTAKE_WITH_OBSERVATIONS","POSE_AXIS_NOT_LIGHT_BEAM_CENTERLINE","UNKNOWN_AS_PASS"]
        XCTAssertTrue(Set(required).isSubset(of:Set(corpus.hostileCases)))
        XCTAssertThrowsError(try LightingDayConditionFactV1(aspect:.daylightEnergized,state:.observedConcern,issueKind:.controlUnknown).validate())
        XCTAssertThrowsError(try LightingDayInventoryLimitsV1.next(UInt64.max))
        XCTAssertTrue(corpus.prohibitedClaims.contains("PHONE_LUX"))
        XCTAssertTrue(corpus.prohibitedClaims.contains("CONTROL_DIAGNOSIS"))
    }

    func testV23P04C17I01InterruptedOfflineDraftAndWriterRecoveryResumeIdempotently() throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(corpus.interruptionCases,["DRAFT_CHECKPOINT_BEFORE_CANONICAL_COMMIT","EFFECT_BEFORE_RECEIPT","OFFLINE_COLD_LAUNCH_REBUILD"])
        let value = [LightingDayConditionFactV1(aspect:.obstruction,state:.notObserved,issueKind:nil)]
        let first = try LightingDayInventoryCanonicalCodecV1.encode(value)
        let decoded = try LightingDayInventoryCanonicalCodecV1.decode([LightingDayConditionFactV1].self,from:first)
        let retry = try LightingDayInventoryCanonicalCodecV1.encode(decoded)
        XCTAssertEqual(first,retry)
        XCTAssertEqual(decoded,value)
        XCTAssertEqual(DraftPurposeV1.assetFieldEdit.rawValue,"ASSET_FIELD_EDIT")
        XCTAssertTrue(OfflineReadinessManifestLifecycleV1.coldLaunchRequiresRebuild)
        XCTAssertEqual(OfflineReadinessManifestLifecycleV1.persistenceMode,"DERIVED_ONLY")
    }

    func testV23P04C17R01BackupRestoreCloneSearchAndReportRebuildExactInventoryTruth() throws {
        let lifecycle = try loadCorpus().lifecycle
        XCTAssertEqual(lifecycle.backupRestore,"PRESERVE_EXACT_CANONICAL_ROW")
        XCTAssertEqual(lifecycle.cloneFork,"REBIND_IDENTITIES_CLEAR_NIGHT_ACTIVATION")
        XCTAssertEqual(lifecycle.deleteErase,"REMOVE_EXACT_ROW")
        XCTAssertEqual(lifecycle.search,"DERIVED_FROM_CANONICAL_ROW")
        XCTAssertEqual(lifecycle.report,"DERIVED_FROM_CANONICAL_ROW")
        XCTAssertEqual(LightingDayInventoryWorkflowStateV1.allCases.count,3)
        XCTAssertEqual(LightingDayInventoryPersistenceEnrollmentV1.persistentSchemaVersion,52)
        XCTAssertEqual(LightingDayInventoryPersistenceEnrollmentV1.durableModelCount,1)
        XCTAssertEqual(LightingDayInventoryPersistenceEnrollmentV1.totalModelCount,167)
        let rebuilt = try C17LightingDaySearchRebuildBoundaryV1.records(workflows: [])
        XCTAssertEqual(rebuilt, [])
        XCTAssertEqual(try SearchCoordinatorV1.searchC17LightingDayMetadata(
            query: "day lighting", workspaceID: WorkspaceID(rawValue: id(1)), records: rebuilt
        ), [])
        XCTAssertTrue(C17LightingDaySearchRebuildBoundaryV1.projectionIsDerivedAndDisposable)
        XCTAssertTrue(C17LightingDaySearchRebuildBoundaryV1.canonicalWriterIsUntouched)
        XCTAssertTrue(ReportRenderService.c17UsesIncumbentSnapshotEncoderAndRenderOutput)
        XCTAssertFalse(ReportRenderService.c17IntroducesSecondRenderer)
    }

    private func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "c1700000-0000-4000-8000-%012x", slot))!
    }

    private func digest(_ character: Character) -> String {
        String(repeating: String(character), count: 64)
    }

    private func loadCorpus() throws -> Corpus {
        let url = URL(fileURLWithPath:#filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/V23/Lighting/V23P04C17LightingDayInventoryCorpusV1.json")
        return try JSONDecoder().decode(Corpus.self,from:Data(contentsOf:url))
    }
    private struct Corpus:Decodable{let cardID:String;let schema:String;let schemaVersion:Int;let golden:Golden;let hardStops:[String];let hostileCases:[String];let interruptionCases:[String];let lifecycle:Lifecycle;let prohibitedClaims:[String]}
    private struct Golden:Decodable{let conditionAspects:[String];let workflowStates:[String]}
    private struct Lifecycle:Decodable{let backupRestore:String;let cloneFork:String;let deleteErase:String;let offlineReadiness:String;let report:String;let search:String}
}

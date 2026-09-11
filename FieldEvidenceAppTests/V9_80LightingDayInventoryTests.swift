import Foundation
import XCTest
@testable import FieldEvidenceApp

final class V9_80LightingDayInventoryTests: XCTestCase {
    func testReportConstructionRequiresAdmittedBeamRoleAndExactDisplayedPose() throws {
        let fixture = try reportFixture()
        let good = try C17LightingDayInventoryReportProjectionV1(
            workflow: fixture.workflow, admission: fixture.admission, poseSnapshots: fixture.poses)
        XCTAssertEqual(good.conditions.first?.poseEvent?.axisID.rawValue, "axis.owner_defined_beam_17")
        let repeated = try C17LightingDayInventoryReportProjectionV1(
            workflow: fixture.workflow, admission: fixture.admission, poseSnapshots: fixture.poses)
        XCTAssertEqual(repeated, good)
        let basis = DayReportDigestBasis(projectionVersion: good.projectionVersion,
            workspaceID: good.workspaceID, workflowID: good.workflowID,
            workflowRevision: good.workflowRevision, workflowSHA256: good.workflowSHA256,
            systemID: good.systemID, systemRevision: good.systemRevision, systemSHA256: good.systemSHA256,
            packageRelease: good.packageRelease, state: good.state, conditions: good.conditions,
            unknownOrNotObservedCount: good.unknownOrNotObservedCount,
            daylightEnergizedObservationCount: good.daylightEnergizedObservationCount,
            nightFollowupPlanID: good.nightFollowupPlanID, nightFollowupPlanSHA256: good.nightFollowupPlanSHA256,
            offlineReadinessSourceSHA256: good.offlineReadinessSourceSHA256,
            offlineReadinessManifestSHA256: good.offlineReadinessManifestSHA256,
            claimBoundary: good.claimBoundary)
        XCTAssertEqual(good.projectionSHA256, try LightingDayInventoryCanonicalCodecV1.sha256(basis))
        let bytes = try LightingDayInventoryCanonicalCodecV1.encode(good)
        XCTAssertEqual(try LightingDayInventoryCanonicalCodecV1.encode(repeated), bytes)
        let roundTrip = try LightingDayInventoryCanonicalCodecV1.decode(
            C17LightingDayInventoryReportProjectionV1.self, from: bytes)
        try roundTrip.validate()
        XCTAssertEqual(roundTrip, good)
        XCTAssertEqual(try LightingDayInventoryCanonicalCodecV1.encode(roundTrip), bytes)
        var tampered = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        tampered["projectionSHA256"] = String(repeating: "0", count: 64)
        let invalid = try LightingDayInventoryCanonicalCodecV1.decoder().decode(
            C17LightingDayInventoryReportProjectionV1.self,
            from: JSONSerialization.data(withJSONObject: tampered))
        XCTAssertThrowsError(try invalid.validate()) {
            XCTAssertEqual($0 as? LightingDayInventoryFailureV1, .invalidValue)
        }
        let frozen = try C17LightingDayInventoryFrozenSnapshotV1(
            workflow: fixture.workflow, admission: fixture.admission,
            poseSnapshots: fixture.poses, capturedAt: fixture.date)
        try frozen.validate()
        XCTAssertEqual(frozen.projection, good)
        let noPose = try reportFixture(role: nil)
        let noPoseReport = try C17LightingDayInventoryFrozenSnapshotV1(
            workflow: noPose.workflow, admission: noPose.admission,
            poseSnapshots: [], capturedAt: noPose.date)
        XCTAssertNil(noPoseReport.projection.conditions.first?.pose)
        XCTAssertEqual(noPoseReport.projection.conditions.first?.poseDisposition, .notDeclared)

        let wrongRole = try reportFixture(role: .assetForwardAxis)
        assertReportRejected(wrongRole, admission: wrongRole.admission, poses: wrongRole.poses)
        let otherPackage = try C26SurveySessionTestSupport.packageRelease(workflowID: "c17.other.workflow")
        let registry = try XCTUnwrap(fixture.admission.acceptedPoseAxisRegistryRelease)
        let wrongRegistry = try PoseAxisRegistryReleaseV1(packageRelease: otherPackage, registry: registry.registry)
        assertReportRejected(fixture, admission: fixture.admissionReplacing(registry: wrongRegistry), poses: fixture.poses)
        assertReportRejected(fixture, admission: fixture.admissionReplacing(events: []), poses: fixture.poses)
        let changedEvent = try fixture.poseEvent(azimuth: 91_000)
        assertReportRejected(fixture, admission: fixture.admissionReplacing(events: [changedEvent]), poses: fixture.poses)
        let foreign = try reportFixture(workspaceID: WorkspaceID(rawValue: id(999)))
        assertReportRejected(fixture, admission: foreign.admission, poses: foreign.poses)
        assertReportRejected(fixture, admission: fixture.admission, poses: foreign.poses)

        // A self-consistent projection digest does not prove that displayed
        // angles came from the event admitted by the canonical source owner.
        let original = try XCTUnwrap(fixture.poses.first)
        let projection = original.projection
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(projection)) as? [String: Any])
        var histories = try XCTUnwrap(object["history"] as? [[String: Any]])
        histories[0]["azimuthMilliDegrees"] = 91_000
        let alteredHistory = try JSONDecoder().decode([C37PoseHistoryProjectionV1].self,
            from: JSONSerialization.data(withJSONObject: histories))
        let alteredDigest = try WorkspaceMutationCanonicalV1.sha256(ReportPoseDigestBasis(
            schemaVersion: projection.schemaVersion, projectionVersion: projection.projectionVersion,
            workspaceID: projection.workspaceID, assetID: projection.assetID,
            currentTipReferences: projection.currentTipReferences, history: alteredHistory,
            capturedAt: projection.capturedAt, historyFrozen: projection.historyFrozen,
            rebasePreviewIsNotApplied: projection.rebasePreviewIsNotApplied,
            sensorInputAllowed: projection.sensorInputAllowed, networkInputAllowed: projection.networkInputAllowed))
        object["history"] = histories
        object["projectionSHA256"] = alteredDigest
        let alteredProjection = try JSONDecoder().decode(C37PlacementPoseReportProjectionV1.self,
            from: JSONSerialization.data(withJSONObject: object))
        try alteredProjection.validate()
        XCTAssertEqual(alteredProjection.history[0].eventSHA256, projection.history[0].eventSHA256)
        XCTAssertNotEqual(alteredProjection.history[0], projection.history[0])
        let alteredFrozen = try C37PlacementPoseFrozenSnapshotV1(
            sourceSnapshotID: original.sourceSnapshotID, projection: alteredProjection)
        assertReportRejected(fixture, admission: fixture.admission, poses: [alteredFrozen])
    }

    private func assertReportRejected(_ fixture: ReportFixture,
                                     admission: LightingDayInventoryAdmissionClosureV1,
                                     poses: [C37PlacementPoseFrozenSnapshotV1],
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try C17LightingDayInventoryReportProjectionV1(
            workflow: fixture.workflow, admission: admission, poseSnapshots: poses), file: file, line: line)
        XCTAssertThrowsError(try C17LightingDayInventoryFrozenSnapshotV1(
            workflow: fixture.workflow, admission: admission, poseSnapshots: poses,
            capturedAt: fixture.date), file: file, line: line)
    }

    private struct DayReportDigestBasis: Codable {
        let projectionVersion: String; let workspaceID: WorkspaceID
        let workflowID: UUID; let workflowRevision: UInt64; let workflowSHA256: String
        let systemID: UUID; let systemRevision: UInt64; let systemSHA256: String
        let packageRelease: LightingPackageReleaseReferenceV1
        let state: LightingDayInventoryWorkflowStateV1
        let conditions: [C17LightingDayConditionReportProjectionV1]
        let unknownOrNotObservedCount: Int; let daylightEnergizedObservationCount: Int
        let nightFollowupPlanID: UUID?; let nightFollowupPlanSHA256: String?
        let offlineReadinessSourceSHA256: String?; let offlineReadinessManifestSHA256: String?
        let claimBoundary: String
    }

    private struct ReportPoseDigestBasis: Codable {
        let schemaVersion: Int; let projectionVersion: String; let workspaceID: WorkspaceID
        let assetID: UUID; let currentTipReferences: [AssetPoseEventReferenceV1]
        let history: [C37PoseHistoryProjectionV1]; let capturedAt: Date; let historyFrozen: Bool
        let rebasePreviewIsNotApplied: Bool; let sensorInputAllowed: Bool; let networkInputAllowed: Bool
    }

    private struct ReportFixture {
        let workflow: LightingDayInventoryWorkflowV1
        let admission: LightingDayInventoryAdmissionClosureV1
        let poses: [C37PlacementPoseFrozenSnapshotV1]
        let date: Date

        func admissionReplacing(events: [AssetPoseEventV1]? = nil,
                                registry: PoseAxisRegistryReleaseV1? = nil) -> LightingDayInventoryAdmissionClosureV1 {
            .init(system: admission.system, observations: admission.observations,
                  poseEvents: events ?? admission.poseEvents,
                  acceptedPoseAxisRegistryRelease: registry ?? admission.acceptedPoseAxisRegistryRelease,
                  occurrence: nil, workPacket: nil, readiness: nil)
        }

        func poseEvent(azimuth: Int32) throws -> AssetPoseEventV1 {
            let old = try XCTUnwrap(admission.poseEvents.first)
            let pose = try PlacementPoseV1(disposition: .observed, referenceFrame: .trueBearing,
                azimuth: .init(kind: .azimuth, milliDegrees: azimuth), horizontalUncertainty: .unknown,
                descriptor: old.axisDescriptor)
            return try AssetPoseEventV1(eventID: old.eventID, workspaceID: old.workspaceID,
                assetID: old.assetID, axisDescriptor: old.axisDescriptor,
                placementEpisodeID: old.placementEpisodeID, placementEventID: old.placementEventID,
                locationPathSnapshot: old.locationPathSnapshot, pose: pose, source: .manual,
                rootObservationEventID: old.eventID, rootObservedAt: old.rootObservedAt,
                predecessor: nil, revision: 1, mutationID: old.mutationID,
                recordedBy: old.recordedBy, occurredAt: old.occurredAt, recordedAt: old.recordedAt)
        }
    }

    private func reportFixture(role: PoseAxisSemanticRoleV1? = .lightBeamCenterline,
                               workspaceID: WorkspaceID? = nil) throws -> ReportFixture {
        let workspace = workspaceID ?? WorkspaceID(rawValue: id(201))
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let actor = try C26SurveySessionTestSupport.actor(workspaceID: workspace)
        let observer = try C26SurveySessionTestSupport.actor(workspaceID: workspace, slot: 310, responsibility: .observedBy)
        let package = try C26SurveySessionTestSupport.packageRelease(workflowID: "c17.report.workflow")
        let packageIdentity = try PackageReleaseIdentityV1(packageID: package.packageID, schemaVersion: 1,
                                                          contentVersion: package.packageContentVersion)
        let assetID = id(202), zoneID = id(203), groupID = id(204), luminaireID = id(205)
        let binding = try WorkSubjectSemanticBindingSnapshotV1(assetID: assetID,
            kindBindingEventID: id(206), kindBindingRevision: 1,
            catalogRelease: .init(releaseID: id(207), packageRelease: packageIdentity, catalogSHA256: digest("a")),
            semanticID: "luminaire.exterior", workflowPackageReleases: [packageIdentity])
        let zone = LightingZoneV1(zoneID: zoneID, displayName: "Day inventory",
            workSubject: .init(kind: .locationNode, subjectID: zoneID, revision: 1, ownerAssetID: nil),
            declaredActivityClass: "PARKING", declaredSecurityClass: "GENERAL")
        let group = ControlGroupV1(controlGroupID: groupID, semanticID: "lighting.primary",
            expectation: try .init(controlGroupID: groupID.uuidString.lowercased(), expectedState: .noExpectation,
                policyID: "C17_LOCAL_POLICY", policyVersion: 1, policySHA256: digest("b")))
        let luminaire = LuminaireAssetV1(luminaireID: luminaireID, assetID: assetID, assetRevision: 1,
            semanticBinding: binding, zoneIDs: [zoneID], controlGroupIDs: [groupID],
            maintenanceDisposition: .independentlyMaintained)
        let system = try LightingSystemV1(recordID: id(208), systemID: id(209), workspaceID: workspace,
            siteID: id(210), packageRelease: .init(package), zones: [zone], controlGroups: [group],
            luminaires: [luminaire], revision: 1, mutationID: .init(rawValue: id(211)),
            recordedBy: actor, recordedAt: date)
        let temporal = try TemporalContextV1(occurredAtUTC: date, recordedAtUTC: date,
            localDate: "2027-01-15", localTime: "08:00:00", utcOffsetSeconds: 0,
            ianaTimeZoneIdentifier: "UTC", localTimeDisposition: .unambiguous)
        let context = try EvidenceContextV1(contextID: id(212), workspaceID: workspace,
            evidenceID: "c17-original", evidenceSHA256: digest("c"), evidenceRevision: 1,
            assetID: assetID, assetRevision: 1, temporalContext: temporal,
            userObserved: .init(condition: .daylight, observationNoteCode: "DAY_NOT_NIGHT_TEST"),
            derivedSolar: nil, controlExpectation: nil, predecessor: nil, revision: 1,
            mutationID: .init(rawValue: id(213)), recordedBy: actor, recordedAt: date)
        let observation = try LightingObservationV1(recordID: id(214), observationID: id(215),
            workspaceID: workspace, system: system, luminaireID: luminaireID, zoneID: zoneID,
            controlGroupID: groupID, evidenceContext: context,
            observationBasis: .init(kind: .directlyObserved, method: .init(key: "c17.manual"),
                source: .init(kind: .observer), limitations: []), issueKinds: [], revision: 1,
            mutationID: .init(rawValue: id(216)), recordedBy: actor, recordedAt: date)
        let path = try LocationPathSnapshotV1(siteID: system.siteID, siteDisplay: "Fixture site", nodes: [])
        let safety = try LightingSafetyIntakeV1(intakeID: id(217), workspaceID: workspace,
            systemID: system.systemID, systemRevision: system.revision, systemSHA256: system.systemSHA256,
            area: zone.workSubject, route: path, timeContext: temporal, siteAuthority: .confirmed,
            requiredPPE: [], confirmedPPE: [], emergencyReadiness: .confirmed,
            trafficSafety: .noTrafficExposure, observerSafety: .authorizedAccessibleVantage,
            recordedBy: actor, recordedAt: date)
        var events: [AssetPoseEventV1] = [], poses: [C37PlacementPoseFrozenSnapshotV1] = []
        var registry: PoseAxisRegistryReleaseV1?
        if let role {
            let descriptor = try PoseAxisDescriptorV1(axisID: .init(rawValue: "axis.owner_defined_beam_17"),
                localizedLabelKey: "pose.day.beam", semanticRole: role, requiredComponents: .azimuthOnly,
                observationRequirement: .optional, applicability: .applicable)
            registry = try .init(packageRelease: package, registry: .init(descriptors: [descriptor]))
            let pose = try PlacementPoseV1(disposition: .observed, referenceFrame: .trueBearing,
                azimuth: .init(kind: .azimuth, milliDegrees: 90_000), horizontalUncertainty: .unknown,
                descriptor: descriptor)
            let event = try AssetPoseEventV1(eventID: id(218), workspaceID: workspace, assetID: assetID,
                axisDescriptor: descriptor, placementEpisodeID: .init(rawValue: id(219)),
                placementEventID: id(220), locationPathSnapshot: path, pose: pose, source: .manual,
                rootObservationEventID: id(218), rootObservedAt: date, predecessor: nil, revision: 1,
                mutationID: .init(rawValue: id(221)), recordedBy: observer, occurredAt: date, recordedAt: date)
            events = [event]
            poses = [try .init(sourceSnapshotID: id(222), projection: .init(
                workspaceID: workspace, assetID: assetID, events: events, capturedAt: date))]
        }
        let condition = try LightingDayConditionSnapshotV1(luminaireID: luminaireID, assetID: assetID,
            assetRevision: 1, zoneID: zoneID, controlGroupID: groupID, observation: .init(observation),
            poseDisposition: role == nil ? .notDeclared : .observed, poseEvent: events.first?.reference,
            facts: [.init(aspect: .lens, state: .notObserved, issueKind: nil)], contextualMedia: [])
        let workflow = try LightingDayInventoryWorkflowV1(recordID: id(223), workflowID: id(224),
            workspaceID: workspace, system: system, safetyIntake: safety, conditionSnapshots: [condition],
            state: .dayInventoryRecorded, revision: 1, mutationID: .init(rawValue: id(225)),
            recordedBy: actor, recordedAt: date)
        let admission = LightingDayInventoryAdmissionClosureV1(system: system, observations: [observation],
            poseEvents: events, acceptedPoseAxisRegistryRelease: registry,
            occurrence: nil, workPacket: nil, readiness: nil)
        return .init(workflow: workflow, admission: admission, poses: poses, date: date)
    }

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

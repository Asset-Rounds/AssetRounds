import Foundation
import XCTest
@testable import FieldEvidenceApp

/// Shared C17 lighting day/night fixture. The night follow-up plan binds a
/// real offline-readiness manifest, occurrence and work packet so the
/// planned day can be committed through the canonical writer.
enum CanonicalLightingFixtureV1 {
    struct Fixture {
        let package: InspectionPackageReleaseV1
        let definition: SurveyDefinitionReleaseV1
        let schedule: ScheduleDefinitionReleaseV1
        let occurrence: OccurrenceHistoryEventV1
        let workPacket: WorkPacketManifestV1
        let plannedDayAdmission: LightingDayInventoryAdmissionClosureV1
        let system: LightingSystemV1
        let dayObservation: LightingObservationV1
        let nightObservation: LightingObservationV1
        let day: LightingDayInventoryWorkflowV1
        let plannedDay: LightingDayInventoryWorkflowV1
        let night: LightingNightWorkflowV1
        let dayAdmission: LightingDayInventoryAdmissionClosureV1
        let nightAdmission: LightingNightWorkflowAdmissionClosureV1
    }

    static func makeFixture(slot: Int) throws -> Fixture {
        let packetFixture = try C15WorkPacketManifestTestSupportV1.makeFixture(seed: 290_000 + slot)
        let workspace = packetFixture.workspaceID
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let actor = try C26SurveySessionTestSupport.actor(workspaceID: workspace)
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
        let condition = try LightingDayConditionSnapshotV1(luminaireID: luminaireID, assetID: assetID,
            assetRevision: 1, zoneID: zoneID, controlGroupID: groupID, observation: .init(observation),
            poseDisposition: .notDeclared, poseEvent: nil,
            facts: [.init(aspect: .lens, state: .notObserved, issueKind: nil)], contextualMedia: [])
        let day = try LightingDayInventoryWorkflowV1(recordID: id(223), workflowID: id(224),
            workspaceID: workspace, system: system, safetyIntake: safety, conditionSnapshots: [condition],
            state: .dayInventoryRecorded, revision: 1, mutationID: .init(rawValue: id(225)),
            recordedBy: actor, recordedAt: date)
        let dayAdmission = LightingDayInventoryAdmissionClosureV1(system: system, observations: [observation],
            poseEvents: [], occurrence: nil, workPacket: nil, readiness: nil)
        try dayAdmission.validate(day)

        let nightDate = Date(timeIntervalSince1970: 1_800_046_800)
        let definition = try C26SurveySessionTestSupport.release(workspaceID: workspace)
        let timeBasis = try FrozenScheduleTimeBasisV1(
            ianaTimeZoneIdentifier: "UTC", timeZoneRuleSetVersion: "test-frozen-v1",
            timeZoneRuleSetSHA256: digest("a"), ambiguousTimePolicy: .earlierOffset,
            nonexistentTimePolicy: .shiftForwardByGap, calendarBasisSHA256: digest("b")
        )
        let anchor = ScheduleLocalAnchorV1(
            year: nil, month: nil, day: nil, weekday: nil, weekdayOrdinal: nil,
            hour: 21, minute: 0, second: 0
        )
        let schedule = try ScheduleDefinitionReleaseV1(
            scheduleDefinitionID: id(8_101), releaseID: id(8_102), workspaceID: workspace,
            occurrenceIdentityNamespaceID: id(8_103), action: .create, lifecycleState: .active,
            recurrence: .fixedCalendar(.init(cadence: .daily, interval: 1, anchor: anchor)),
            timeBasis: timeBasis, startsAtUTC: nightDate, generationHorizonDays: 30,
            maximumGeneratedOccurrences: 8, readyLeadSeconds: 0, overdueGraceSeconds: 0,
            subject: WorkSubjectReferenceV1(kind: .asset, subjectID: id(8_104),
                                            revision: 1, ownerAssetID: nil),
            workDefinition: ScheduledWorkDefinitionReferenceV1(
                kind: .workPacket, definition: definition, packageRelease: package
            ),
            revision: 1, mutationID: MutationIDV1(rawValue: id(8_105)),
            authoredBy: actor, authoredAt: nightDate
        )
        let basis = ResolvedOccurrenceBasisV1(
            nominalLocalDate: "2027-01-15", nominalLocalTime: "21:00:00",
            resolvedAtUTC: nightDate, utcOffsetSeconds: 0, disposition: .unambiguous,
            timeBasisSHA256: try timeBasis.canonicalSHA256(), adjustmentProvenanceSHA256: nil
        )
        let occurrenceID = try OccurrenceIDV1(
            scheduleDefinitionID: schedule.scheduleDefinitionID,
            identityNamespaceID: schedule.occurrenceIdentityNamespaceID, nominalKey: basis.nominalKey
        )
        let event = try OccurrenceHistoryEventV1(
            eventID: id(8_106), workspaceID: workspace, occurrenceID: occurrenceID,
            scheduleRelease: ScheduleDefinitionReleaseReferenceV1(schedule),
            action: .generated, nominalBasis: basis, effectiveBasis: basis,
            predecessor: nil, revision: 1, mutationID: MutationIDV1(rawValue: id(8_107)),
            recordedBy: actor, recordedAt: nightDate
        )
        let readiness = try OfflineReadinessManifestBuilderV1.build(snapshot: readinessSnapshot(workspace: workspace,
            package: package, assetID: assetID, siteID: system.siteID, checkedAt: nightDate))
        let plan = try LightingNightFollowupPlanV1(planID: id(310), workspaceID: workspace,
            sourceSystemID: system.systemID, sourceSystemRevision: system.revision,
            sourceSystemSHA256: system.systemSHA256, sourceDayInventoryContentSHA256: day.dayInventoryContentSHA256,
            selectedLuminaireIDs: [luminaireID], occurrence: .init(event),
            workPacket: .init(packetFixture.manifest), offlineReadinessSourceSHA256: readiness.sourceSnapshotSHA256,
            offlineReadinessManifestSHA256: readiness.manifestSHA256, readinessCheckedAt: nightDate,
            createdBy: actor, createdAt: nightDate)
        let plannedDay = try LightingDayInventoryWorkflowV1(recordID: id(311), workflowID: id(312),
            workspaceID: workspace, system: system, safetyIntake: safety, conditionSnapshots: [condition],
            state: .nightFollowupPrepared, nightFollowupPlan: plan, revision: 1,
            mutationID: .init(rawValue: id(313)), recordedBy: actor, recordedAt: nightDate)
        let plannedDayAdmission = LightingDayInventoryAdmissionClosureV1(system: system,
            observations: [observation], poseEvents: [], occurrence: event,
            workPacket: packetFixture.manifest, readiness: readiness)
        try plannedDayAdmission.validate(plannedDay)
        let nightTime = try TemporalContextV1(occurredAtUTC: nightDate, recordedAtUTC: nightDate,
            localDate: "2027-01-15", localTime: "21:00:00", utcOffsetSeconds: 0,
            ianaTimeZoneIdentifier: "UTC", localTimeDisposition: .unambiguous)
        let nightContext = try EvidenceContextV1(contextID: id(314), workspaceID: workspace,
            evidenceID: "receipt-safety-night", evidenceSHA256: digest("8"), evidenceRevision: 1,
            assetID: assetID, assetRevision: 1, temporalContext: nightTime,
            userObserved: .init(condition: .night, observationNoteCode: "NIGHT_INVENTORY"),
            derivedSolar: nil, controlExpectation: nil, predecessor: nil, revision: 1,
            mutationID: .init(rawValue: id(315)), recordedBy: actor, recordedAt: nightDate)
        let nightObservation = try LightingObservationV1(recordID: id(316), observationID: id(317),
            workspaceID: workspace, system: system, luminaireID: luminaireID, zoneID: zoneID,
            controlGroupID: groupID, evidenceContext: nightContext,
            observationBasis: .init(kind: .directlyObserved, method: .init(key: "receipt.night.manual"),
                source: .init(kind: .observer), limitations: []), issueKinds: [], revision: 1,
            mutationID: .init(rawValue: id(318)), recordedBy: actor, recordedAt: nightDate)
        let nightSafety = try LightingSafetyIntakeV1(intakeID: id(319), workspaceID: workspace,
            systemID: system.systemID, systemRevision: system.revision, systemSHA256: system.systemSHA256,
            area: zone.workSubject, route: path, timeContext: nightTime, siteAuthority: .confirmed,
            requiredPPE: [], confirmedPPE: [], emergencyReadiness: .confirmed,
            trafficSafety: .noTrafficExposure, observerSafety: .authorizedAccessibleVantage,
            recordedBy: actor, recordedAt: nightDate)
        let comparableMedia = try ContentReferenceV1(
            workspaceID: workspace.rawValue.uuidString.lowercased(),
            contentID: nightContext.evidenceID, byteLength: 1, mediaType: "image/jpeg",
            digests: .init([.init(algorithm: .sha256,
                hexadecimalValue: nightContext.evidenceSHA256)]),
            byteRole: .immutableOriginal, createdAt: ISO8601DateFormatter().string(from: nightDate))
        let delta = try LightingNightDeltaV1(luminaireID: luminaireID, assetID: assetID, assetRevision: 1,
            zoneID: zoneID, controlGroupID: groupID, observation: .init(nightObservation),
            expectedControl: .noDeclaredExpectation, observedControl: .appearedOn,
            issueKinds: [], comparableMedia: [comparableMedia], temporaryLight: .notObserved,
            weatherContext: .notObserved, surfaceContext: .notObserved, measurement: nil,
            cameraBandingRecordedWithoutFlickerClaim: false)
        let night = try LightingNightWorkflowV1(recordID: id(320), workflowID: id(321),
            workspaceID: workspace, system: system, dayWorkflow: plannedDay,
            safety: .init(intake: nightSafety, nightPlan: plan), deltas: [delta], repairPolicy: .init(),
            state: .nightInventoryRecorded, revision: 1, mutationID: .init(rawValue: id(322)),
            recordedBy: actor, recordedAt: nightDate)
        let nightAdmission = LightingNightWorkflowAdmissionClosureV1(system: system,
            dayWorkflow: plannedDay, observations: [nightObservation], issues: [],
            admittedMeasurementSHA256s: [], patrolSessions: [])
        try nightAdmission.validate(night)
        return .init(package: package, definition: definition, schedule: schedule, occurrence: event,
            workPacket: packetFixture.manifest, plannedDayAdmission: plannedDayAdmission,
            system: system, dayObservation: observation, nightObservation: nightObservation,
            day: day, plannedDay: plannedDay, night: night, dayAdmission: dayAdmission,
            nightAdmission: nightAdmission)
    }

    private static func readinessSnapshot(workspace: WorkspaceID, package: InspectionPackageReleaseV1,
                                          assetID: UUID, siteID: UUID, checkedAt: Date) throws -> OfflineReadinessSnapshotV1 {
        let packageReference = try RoundPackageReleaseReferenceV1(packageReleaseID: package.packageReleaseID,
            packageID: package.packageID, packageContentVersion: package.packageContentVersion,
            packageSHA256: package.packageSHA256, workflowSHA256: package.workflowSHA256)
        let selected = try RoundAssetSelectionV1(assetID: assetID, siteID: siteID, labelAtSelection: "Lighting asset")
        return try OfflineReadinessSnapshotV1(
            session: RoundSessionReferenceV1(workspaceID: workspace, sessionID: id(330), revision: 1,
                sessionSHA256: digest("9")),
            expectedPackage: packageReference, observedPackage: packageReference, selectedAssets: [selected],
            observedAssetIDs: [assetID], guidanceReferenceIDs: [], availableGuidanceReferenceIDs: [],
            contentRequirements: [], contentObservations: [], expectedFieldReferences: [], fieldReferenceReadiness: [],
            storage: try OfflineReadinessStorageObservationV1(capacityState: .checked, availableBytes: 10_000),
            access: OfflineReadinessAccessObservationV1(protectedDataAvailable: true),
            checkedAt: checkedAt, timeZoneIdentifier: "UTC", clockState: .checked)
    }

    private static func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "d1800000-0000-4000-8000-%012x", slot))!
    }
    private static func digest(_ character: Character) -> String {
        String(repeating: String(character), count: 64)
    }
}

import Foundation

enum LightingDayInventoryFailureV1: Error, Equatable, Sendable {
    case incompatibleVersion, invalidValue, invalidDigest, wrongWorkspace, staleReference
    case duplicateIdentity, incompleteInventory, safetyStop, invalidSuccessor, limitExceeded
    case forbiddenClaim, nonCanonicalData
}

enum LightingDayInventoryLimitsV1 {
    static let maximumSnapshots = LightingLimitsV1.maximumLuminaires
    static let maximumFactsPerSnapshot = 16
    static let maximumContextualMedia = 32
    static let maximumSelectedNightLuminaires = LightingLimitsV1.maximumLuminaires
    static let maximumCanonicalBytes = 16 * 1_024 * 1_024
    static func id(_ value: UUID) throws { try LightingLimitsV1.id(value) }
    static func revision(_ value: UInt64) throws { try LightingLimitsV1.revision(value) }
    static func digest(_ value: String) throws { try LightingLimitsV1.digest(value) }
    static func instant(_ value: Date) throws { try LightingLimitsV1.instant(value) }
    static func next(_ value: UInt64) throws -> UInt64 { try LightingLimitsV1.next(value) }
}

enum LightingDayInventoryWorkflowStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case safetyStopped = "SAFETY_STOPPED"
    case dayInventoryRecorded = "DAY_INVENTORY_RECORDED"
    case nightFollowupPrepared = "NIGHT_FOLLOWUP_PREPARED"
}

enum LightingSiteAuthorityDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case confirmed = "CONFIRMED", missing = "MISSING"
}

enum LightingPPEKindV1: String, Codable, CaseIterable, Hashable, Comparable, Sendable {
    case highVisibility = "HIGH_VISIBILITY", eyeProtection = "EYE_PROTECTION"
    case protectiveFootwear = "PROTECTIVE_FOOTWEAR", weatherProtection = "WEATHER_PROTECTION"
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum LightingEmergencyReadinessV1: String, Codable, CaseIterable, Hashable, Sendable {
    case confirmed = "CONFIRMED", missing = "MISSING"
}

enum LightingTrafficSafetyDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case noTrafficExposure = "NO_TRAFFIC_EXPOSURE"
    case authorizedControlPlan = "AUTHORIZED_CONTROL_PLAN"
    case controlPlanMissing = "CONTROL_PLAN_MISSING"
    case unsafeActiveTraffic = "UNSAFE_ACTIVE_TRAFFIC"
}

enum LightingObserverSafetyDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case authorizedAccessibleVantage = "AUTHORIZED_ACCESSIBLE_VANTAGE"
    case inaccessible = "INACCESSIBLE", unsafe = "UNSAFE", unknown = "UNKNOWN"
}

enum LightingDaySafetyStopReasonV1: String, Codable, CaseIterable, Hashable, Comparable, Sendable {
    case siteAuthorityMissing = "SITE_AUTHORITY_MISSING"
    case routeUnavailable = "ROUTE_UNAVAILABLE"
    case requiredPPEMissing = "REQUIRED_PPE_MISSING"
    case emergencyReadinessMissing = "EMERGENCY_READINESS_MISSING"
    case trafficControlMissing = "TRAFFIC_CONTROL_MISSING"
    case activeTrafficUnsafe = "ACTIVE_TRAFFIC_UNSAFE"
    case observerPositionInaccessible = "OBSERVER_POSITION_INACCESSIBLE"
    case observerPositionUnsafe = "OBSERVER_POSITION_UNSAFE"
    case observerPositionUnknown = "OBSERVER_POSITION_UNKNOWN"
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct LightingSafetyIntakeV1: Codable, Equatable, Sendable {
    let intakeID: UUID
    let workspaceID: WorkspaceID
    let systemID: UUID
    let systemRevision: UInt64
    let systemSHA256: String
    let area: WorkSubjectReferenceV1
    let route: LocationPathSnapshotV1?
    let timeContext: TemporalContextV1
    let siteAuthority: LightingSiteAuthorityDispositionV1
    let requiredPPE: [LightingPPEKindV1]
    let confirmedPPE: [LightingPPEKindV1]
    let emergencyReadiness: LightingEmergencyReadinessV1
    let trafficSafety: LightingTrafficSafetyDispositionV1
    let observerSafety: LightingObserverSafetyDispositionV1
    let stopReasons: [LightingDaySafetyStopReasonV1]
    let recordedBy: ActorSnapshotV1
    let recordedAt: Date
    let intakeSHA256: String

    init(intakeID: UUID, workspaceID: WorkspaceID, systemID: UUID, systemRevision: UInt64,
         systemSHA256: String, area: WorkSubjectReferenceV1, route: LocationPathSnapshotV1?,
         timeContext: TemporalContextV1, siteAuthority: LightingSiteAuthorityDispositionV1,
         requiredPPE: [LightingPPEKindV1], confirmedPPE: [LightingPPEKindV1],
         emergencyReadiness: LightingEmergencyReadinessV1,
         trafficSafety: LightingTrafficSafetyDispositionV1,
         observerSafety: LightingObserverSafetyDispositionV1,
         recordedBy: ActorSnapshotV1, recordedAt: Date) throws {
        let required = requiredPPE.sorted(), confirmed = confirmedPPE.sorted()
        let reasons = Self.deriveStopReasons(route: route, siteAuthority: siteAuthority,
            requiredPPE: required, confirmedPPE: confirmed, emergencyReadiness: emergencyReadiness,
            trafficSafety: trafficSafety, observerSafety: observerSafety)
        self.intakeID=intakeID;self.workspaceID=workspaceID;self.systemID=systemID
        self.systemRevision=systemRevision;self.systemSHA256=systemSHA256;self.area=area;self.route=route
        self.timeContext=timeContext;self.siteAuthority=siteAuthority;self.requiredPPE=required
        self.confirmedPPE=confirmed;self.emergencyReadiness=emergencyReadiness
        self.trafficSafety=trafficSafety;self.observerSafety=observerSafety;stopReasons=reasons
        self.recordedBy=recordedBy;self.recordedAt=recordedAt
        intakeSHA256=try LightingDayInventoryCanonicalCodecV1.sha256(Basis(intakeID:intakeID,workspaceID:workspaceID,systemID:systemID,systemRevision:systemRevision,systemSHA256:systemSHA256,area:area,route:route,timeContext:timeContext,siteAuthority:siteAuthority,requiredPPE:required,confirmedPPE:confirmed,emergencyReadiness:emergencyReadiness,trafficSafety:trafficSafety,observerSafety:observerSafety,stopReasons:reasons,recordedBy:recordedBy,recordedAt:recordedAt))
        try validate()
    }
    var observationIsAuthorized: Bool { stopReasons.isEmpty }
    func validate() throws {
        try LightingDayInventoryLimitsV1.id(intakeID);try LightingDayInventoryLimitsV1.id(systemID)
        try LightingDayInventoryLimitsV1.revision(systemRevision);try LightingDayInventoryLimitsV1.digest(systemSHA256)
        try area.validate();try route?.validate();try timeContext.validate();try recordedBy.validate()
        try LightingDayInventoryLimitsV1.instant(recordedAt)
        let derived=Self.deriveStopReasons(route:route,siteAuthority:siteAuthority,requiredPPE:requiredPPE,confirmedPPE:confirmedPPE,emergencyReadiness:emergencyReadiness,trafficSafety:trafficSafety,observerSafety:observerSafety)
        guard requiredPPE==requiredPPE.sorted(),confirmedPPE==confirmedPPE.sorted(),Set(requiredPPE).count==requiredPPE.count,Set(confirmedPPE).count==confirmedPPE.count,Set(confirmedPPE).isSubset(of:Set(requiredPPE)),stopReasons==derived,recordedBy.workspaceID==workspaceID,recordedBy.responsibility == .recordedBy,intakeSHA256==(try LightingDayInventoryCanonicalCodecV1.sha256(basis)) else{throw LightingDayInventoryFailureV1.invalidValue}
    }
    func validate(system: LightingSystemV1) throws { try validate();try system.validateIntrinsic();guard workspaceID==system.workspaceID,systemID==system.systemID,systemRevision==system.revision,systemSHA256==system.systemSHA256,route?.siteID==system.siteID else{throw LightingDayInventoryFailureV1.staleReference} }
    private static func deriveStopReasons(route:LocationPathSnapshotV1?,siteAuthority:LightingSiteAuthorityDispositionV1,requiredPPE:[LightingPPEKindV1],confirmedPPE:[LightingPPEKindV1],emergencyReadiness:LightingEmergencyReadinessV1,trafficSafety:LightingTrafficSafetyDispositionV1,observerSafety:LightingObserverSafetyDispositionV1)->[LightingDaySafetyStopReasonV1]{var v:[LightingDaySafetyStopReasonV1]=[];if siteAuthority == .missing{v.append(.siteAuthorityMissing)};if route==nil{v.append(.routeUnavailable)};if !Set(requiredPPE).isSubset(of:Set(confirmedPPE)){v.append(.requiredPPEMissing)};if emergencyReadiness == .missing{v.append(.emergencyReadinessMissing)};if trafficSafety == .controlPlanMissing{v.append(.trafficControlMissing)};if trafficSafety == .unsafeActiveTraffic{v.append(.activeTrafficUnsafe)};switch observerSafety{case .authorizedAccessibleVantage:break;case .inaccessible:v.append(.observerPositionInaccessible);case .unsafe:v.append(.observerPositionUnsafe);case .unknown:v.append(.observerPositionUnknown)};return v.sorted()}
    private var basis:Basis{.init(intakeID:intakeID,workspaceID:workspaceID,systemID:systemID,systemRevision:systemRevision,systemSHA256:systemSHA256,area:area,route:route,timeContext:timeContext,siteAuthority:siteAuthority,requiredPPE:requiredPPE,confirmedPPE:confirmedPPE,emergencyReadiness:emergencyReadiness,trafficSafety:trafficSafety,observerSafety:observerSafety,stopReasons:stopReasons,recordedBy:recordedBy,recordedAt:recordedAt)}
    private struct Basis:Codable{let intakeID:UUID;let workspaceID:WorkspaceID;let systemID:UUID;let systemRevision:UInt64;let systemSHA256:String;let area:WorkSubjectReferenceV1;let route:LocationPathSnapshotV1?;let timeContext:TemporalContextV1;let siteAuthority:LightingSiteAuthorityDispositionV1;let requiredPPE:[LightingPPEKindV1];let confirmedPPE:[LightingPPEKindV1];let emergencyReadiness:LightingEmergencyReadinessV1;let trafficSafety:LightingTrafficSafetyDispositionV1;let observerSafety:LightingObserverSafetyDispositionV1;let stopReasons:[LightingDaySafetyStopReasonV1];let recordedBy:ActorSnapshotV1;let recordedAt:Date}
}

enum LightingDayConditionAspectV1:String,Codable,CaseIterable,Hashable,Comparable,Sendable{case lens="LENS",housing="HOUSING",shield="SHIELD",poleBase="POLE_BASE",arm="ARM",obstruction="OBSTRUCTION",visibleWiring="VISIBLE_WIRING",accessCover="ACCESS_COVER",daylightEnergized="DAYLIGHT_ENERGIZED",contextualMedia="CONTEXTUAL_MEDIA";static func <(l:Self,r:Self)->Bool{l.rawValue<r.rawValue}}
enum LightingDayConditionStateV1:String,Codable,CaseIterable,Hashable,Sendable{case observedNoVisibleConcern="OBSERVED_NO_VISIBLE_CONCERN",observedConcern="OBSERVED_CONCERN",observedPresent="OBSERVED_PRESENT",observedAbsent="OBSERVED_ABSENT",unknown="UNKNOWN",notObserved="NOT_OBSERVED",notApplicable="NOT_APPLICABLE"}
struct LightingDayConditionFactV1:Codable,Equatable,Hashable,Comparable,Sendable{let aspect:LightingDayConditionAspectV1;let state:LightingDayConditionStateV1;let issueKind:LightingIssueKindV1?;static func <(l:Self,r:Self)->Bool{l.aspect<r.aspect};func validate()throws{let concern=state == .observedConcern;guard concern==(issueKind != nil),aspect != .daylightEnergized || issueKind == nil else{throw LightingDayInventoryFailureV1.forbiddenClaim}}}

enum LightingDayPoseDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case notDeclared = "NOT_DECLARED"
    case observed = "OBSERVED"
    case notObserved = "NOT_OBSERVED"
}

struct LightingDayConditionSnapshotV1:Codable,Equatable,Sendable{
    let luminaireID:UUID;let assetID:UUID;let assetRevision:UInt64;let zoneID:UUID;let controlGroupID:UUID
    let observation:LightingObservationReferenceV1;let poseDisposition:LightingDayPoseDispositionV1
    let poseEvent:AssetPoseEventReferenceV1?
    let facts:[LightingDayConditionFactV1];let contextualMedia:[ContentReferenceV1];let snapshotSHA256:String
    init(luminaireID:UUID,assetID:UUID,assetRevision:UInt64,zoneID:UUID,controlGroupID:UUID,
         observation:LightingObservationReferenceV1,poseDisposition:LightingDayPoseDispositionV1,
         poseEvent:AssetPoseEventReferenceV1?,facts:[LightingDayConditionFactV1],
         contextualMedia:[ContentReferenceV1])throws{
        let facts=facts.sorted(),media=contextualMedia.sorted{$0.contentID<$1.contentID}
        self.luminaireID=luminaireID;self.assetID=assetID;self.assetRevision=assetRevision
        self.zoneID=zoneID;self.controlGroupID=controlGroupID;self.observation=observation
        self.poseDisposition=poseDisposition;self.poseEvent=poseEvent;self.facts=facts
        self.contextualMedia=media
        snapshotSHA256=try LightingDayInventoryCanonicalCodecV1.sha256(Basis(
            luminaireID:luminaireID,assetID:assetID,assetRevision:assetRevision,zoneID:zoneID,
            controlGroupID:controlGroupID,observation:observation,poseDisposition:poseDisposition,
            poseEvent:poseEvent,facts:facts,contextualMedia:media))
        try validate()
    }
    init(luminaireID:UUID,assetID:UUID,assetRevision:UInt64,zoneID:UUID,controlGroupID:UUID,
         observation:LightingObservationReferenceV1,poseEvent:AssetPoseEventReferenceV1,
         facts:[LightingDayConditionFactV1],contextualMedia:[ContentReferenceV1])throws{
        try self.init(luminaireID:luminaireID,assetID:assetID,assetRevision:assetRevision,
                      zoneID:zoneID,controlGroupID:controlGroupID,observation:observation,
                      poseDisposition:.observed,poseEvent:poseEvent,facts:facts,
                      contextualMedia:contextualMedia)
    }
    func validate()throws{
        try [luminaireID,assetID,zoneID,controlGroupID].forEach(LightingDayInventoryLimitsV1.id)
        try LightingDayInventoryLimitsV1.revision(assetRevision);try observation.validate()
        try poseEvent?.validate();try facts.forEach{try $0.validate()}
        let workspaceToken=observation.workspaceID.rawValue.uuidString.lowercased()
        guard observation.luminaireID==luminaireID,observation.assetID==assetID,
              observation.assetRevision==assetRevision,
              poseEvent.map{$0.workspaceID==observation.workspaceID&&$0.assetID==assetID} ?? true,
              (poseDisposition == .notDeclared)==(poseEvent == nil),
              !facts.isEmpty,facts.count<=LightingDayInventoryLimitsV1.maximumFactsPerSnapshot,
              facts==facts.sorted(),Set(facts.map(\.aspect)).count==facts.count,
              contextualMedia.count<=LightingDayInventoryLimitsV1.maximumContextualMedia,
              contextualMedia.allSatisfy({$0.workspaceID==workspaceToken && !$0.contentID.isEmpty && $0.byteLength>=0}),
              contextualMedia==contextualMedia.sorted(by:{$0.contentID<$1.contentID}),
              Set(contextualMedia.map(\.contentID)).count==contextualMedia.count,
              snapshotSHA256==(try LightingDayInventoryCanonicalCodecV1.sha256(basis))else{
            throw LightingDayInventoryFailureV1.invalidValue
        }
    }
    private var basis:Basis{.init(luminaireID:luminaireID,assetID:assetID,
        assetRevision:assetRevision,zoneID:zoneID,controlGroupID:controlGroupID,
        observation:observation,poseDisposition:poseDisposition,poseEvent:poseEvent,
        facts:facts,contextualMedia:contextualMedia)}
    private struct Basis:Codable{let luminaireID:UUID;let assetID:UUID;let assetRevision:UInt64
        let zoneID:UUID;let controlGroupID:UUID;let observation:LightingObservationReferenceV1
        let poseDisposition:LightingDayPoseDispositionV1;let poseEvent:AssetPoseEventReferenceV1?
        let facts:[LightingDayConditionFactV1];let contextualMedia:[ContentReferenceV1]}
}

struct LightingNightOccurrenceBindingV1:Codable,Equatable,Sendable{let occurrenceID:OccurrenceIDV1;let eventID:UUID;let eventRevision:UInt64;let eventSHA256:String;let scheduleRelease:ScheduleDefinitionReleaseReferenceV1;init(_ value:OccurrenceHistoryEventV1)throws{try value.validateIntrinsic();occurrenceID=value.occurrenceID;eventID=value.eventID;eventRevision=value.revision;eventSHA256=value.eventSHA256;scheduleRelease=value.scheduleRelease;try validate()}func validate()throws{try occurrenceID.validate();try LightingDayInventoryLimitsV1.id(eventID);try LightingDayInventoryLimitsV1.revision(eventRevision);try LightingDayInventoryLimitsV1.digest(eventSHA256);try scheduleRelease.validate()}}

struct LightingNightFollowupPlanV1:Codable,Equatable,Sendable{
    let planID:UUID;let workspaceID:WorkspaceID;let sourceSystemID:UUID;let sourceSystemRevision:UInt64;let sourceSystemSHA256:String;let sourceDayInventoryContentSHA256:String;let selectedLuminaireIDs:[UUID];let occurrence:LightingNightOccurrenceBindingV1;let workPacket:WorkPacketManifestReferenceV1;let offlineReadinessSourceSHA256:String;let offlineReadinessManifestSHA256:String;let readinessCheckedAt:Date;let createdBy:ActorSnapshotV1;let createdAt:Date;let planSHA256:String
    init(planID:UUID,workspaceID:WorkspaceID,sourceSystemID:UUID,sourceSystemRevision:UInt64,sourceSystemSHA256:String,sourceDayInventoryContentSHA256:String,selectedLuminaireIDs:[UUID],occurrence:LightingNightOccurrenceBindingV1,workPacket:WorkPacketManifestReferenceV1,offlineReadinessSourceSHA256:String,offlineReadinessManifestSHA256:String,readinessCheckedAt:Date,createdBy:ActorSnapshotV1,createdAt:Date)throws{let ids=selectedLuminaireIDs.sorted{$0.uuidString<$1.uuidString};self.planID=planID;self.workspaceID=workspaceID;self.sourceSystemID=sourceSystemID;self.sourceSystemRevision=sourceSystemRevision;self.sourceSystemSHA256=sourceSystemSHA256;self.sourceDayInventoryContentSHA256=sourceDayInventoryContentSHA256;self.selectedLuminaireIDs=ids;self.occurrence=occurrence;self.workPacket=workPacket;self.offlineReadinessSourceSHA256=offlineReadinessSourceSHA256;self.offlineReadinessManifestSHA256=offlineReadinessManifestSHA256;self.readinessCheckedAt=readinessCheckedAt;self.createdBy=createdBy;self.createdAt=createdAt;planSHA256=try LightingDayInventoryCanonicalCodecV1.sha256(Basis(planID:planID,workspaceID:workspaceID,sourceSystemID:sourceSystemID,sourceSystemRevision:sourceSystemRevision,sourceSystemSHA256:sourceSystemSHA256,sourceDayInventoryContentSHA256:sourceDayInventoryContentSHA256,selectedLuminaireIDs:ids,occurrence:occurrence,workPacket:workPacket,offlineReadinessSourceSHA256:offlineReadinessSourceSHA256,offlineReadinessManifestSHA256:offlineReadinessManifestSHA256,readinessCheckedAt:readinessCheckedAt,createdBy:createdBy,createdAt:createdAt));try validate()}
    func validate()throws{try [planID,sourceSystemID].forEach(LightingDayInventoryLimitsV1.id);try LightingDayInventoryLimitsV1.revision(sourceSystemRevision);try [sourceSystemSHA256,sourceDayInventoryContentSHA256,offlineReadinessSourceSHA256,offlineReadinessManifestSHA256].forEach(LightingDayInventoryLimitsV1.digest);try selectedLuminaireIDs.forEach(LightingDayInventoryLimitsV1.id);try occurrence.validate();try workPacket.validate();try createdBy.validate();try LightingDayInventoryLimitsV1.instant(readinessCheckedAt);try LightingDayInventoryLimitsV1.instant(createdAt);guard !selectedLuminaireIDs.isEmpty,selectedLuminaireIDs.count<=LightingDayInventoryLimitsV1.maximumSelectedNightLuminaires,selectedLuminaireIDs==selectedLuminaireIDs.sorted(by:{$0.uuidString<$1.uuidString}),Set(selectedLuminaireIDs).count==selectedLuminaireIDs.count,occurrence.scheduleRelease.workspaceID==workspaceID,workPacket.workspaceID==workspaceID,createdBy.workspaceID==workspaceID,createdBy.responsibility == .recordedBy,createdAt>=readinessCheckedAt,planSHA256==(try LightingDayInventoryCanonicalCodecV1.sha256(basis))else{throw LightingDayInventoryFailureV1.invalidValue}}
    private var basis:Basis{.init(planID:planID,workspaceID:workspaceID,sourceSystemID:sourceSystemID,sourceSystemRevision:sourceSystemRevision,sourceSystemSHA256:sourceSystemSHA256,sourceDayInventoryContentSHA256:sourceDayInventoryContentSHA256,selectedLuminaireIDs:selectedLuminaireIDs,occurrence:occurrence,workPacket:workPacket,offlineReadinessSourceSHA256:offlineReadinessSourceSHA256,offlineReadinessManifestSHA256:offlineReadinessManifestSHA256,readinessCheckedAt:readinessCheckedAt,createdBy:createdBy,createdAt:createdAt)};private struct Basis:Codable{let planID:UUID;let workspaceID:WorkspaceID;let sourceSystemID:UUID;let sourceSystemRevision:UInt64;let sourceSystemSHA256:String;let sourceDayInventoryContentSHA256:String;let selectedLuminaireIDs:[UUID];let occurrence:LightingNightOccurrenceBindingV1;let workPacket:WorkPacketManifestReferenceV1;let offlineReadinessSourceSHA256:String;let offlineReadinessManifestSHA256:String;let readinessCheckedAt:Date;let createdBy:ActorSnapshotV1;let createdAt:Date}
}

struct LightingDayInventoryWorkflowV1:Codable,Equatable,Sendable{
    static let schemaVersion=1;let schemaVersion:Int;let recordID:UUID;let workflowID:UUID;let workspaceID:WorkspaceID;let systemID:UUID;let systemRevision:UInt64;let systemSHA256:String;let packageRelease:LightingPackageReleaseReferenceV1;let safetyIntake:LightingSafetyIntakeV1;let conditionSnapshots:[LightingDayConditionSnapshotV1];let state:LightingDayInventoryWorkflowStateV1;let dayInventoryContentSHA256:String;let nightFollowupPlan:LightingNightFollowupPlanV1?;let supersedesRecordID:UUID?;let predecessorSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1;let recordedBy:ActorSnapshotV1;let recordedAt:Date;let workflowSHA256:String
    init(recordID:UUID,workflowID:UUID,workspaceID:WorkspaceID,system:LightingSystemV1,safetyIntake:LightingSafetyIntakeV1,conditionSnapshots:[LightingDayConditionSnapshotV1],state:LightingDayInventoryWorkflowStateV1,nightFollowupPlan:LightingNightFollowupPlanV1?=nil,predecessor:Self?=nil,revision:UInt64,mutationID:MutationIDV1,recordedBy:ActorSnapshotV1,recordedAt:Date)throws{try system.validateIntrinsic();let snapshots=conditionSnapshots.sorted(by:Self.snapshotLess);schemaVersion=Self.schemaVersion;self.recordID=recordID;self.workflowID=workflowID;self.workspaceID=workspaceID;systemID=system.systemID;systemRevision=system.revision;systemSHA256=system.systemSHA256;packageRelease=system.packageRelease;self.safetyIntake=safetyIntake;self.conditionSnapshots=snapshots;self.state=state;dayInventoryContentSHA256=try Self.contentDigest(workspaceID:workspaceID,systemID:system.systemID,systemRevision:system.revision,systemSHA256:system.systemSHA256,safetyIntake:safetyIntake,snapshots:snapshots);self.nightFollowupPlan=nightFollowupPlan;supersedesRecordID=predecessor?.recordID;predecessorSHA256=predecessor?.workflowSHA256;self.revision=revision;self.mutationID=mutationID;self.recordedBy=recordedBy;self.recordedAt=recordedAt;workflowSHA256=try LightingDayInventoryCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,recordID:recordID,workflowID:workflowID,workspaceID:workspaceID,systemID:system.systemID,systemRevision:system.revision,systemSHA256:system.systemSHA256,packageRelease:system.packageRelease,safetyIntake:safetyIntake,conditionSnapshots:snapshots,state:state,dayInventoryContentSHA256:dayInventoryContentSHA256,nightFollowupPlan:nightFollowupPlan,supersedesRecordID:predecessor?.recordID,predecessorSHA256:predecessor?.workflowSHA256,revision:revision,mutationID:mutationID,recordedBy:recordedBy,recordedAt:recordedAt));try validateIntrinsic();try validate(system:system);if let predecessor{try validateSuccessor(of:predecessor)}}
    func validateIntrinsic()throws{try [recordID,workflowID,systemID].forEach(LightingDayInventoryLimitsV1.id);try LightingDayInventoryLimitsV1.revision(systemRevision);try LightingDayInventoryLimitsV1.revision(revision);try [systemSHA256,dayInventoryContentSHA256].forEach(LightingDayInventoryLimitsV1.digest);try packageRelease.validate();try safetyIntake.validate();try conditionSnapshots.forEach{try $0.validate()};try nightFollowupPlan?.validate();try predecessorSHA256.map(LightingDayInventoryLimitsV1.digest);try recordedBy.validate();try LightingDayInventoryLimitsV1.instant(recordedAt);let stopped=state == .safetyStopped;let complete=state != .safetyStopped;guard schemaVersion==Self.schemaVersion,conditionSnapshots.count<=LightingDayInventoryLimitsV1.maximumSnapshots,conditionSnapshots==conditionSnapshots.sorted(by:Self.snapshotLess),Set(conditionSnapshots.map(\.luminaireID)).count==conditionSnapshots.count,Set(conditionSnapshots.map(\.assetID)).count==conditionSnapshots.count,safetyIntake.workspaceID==workspaceID,safetyIntake.systemID==systemID,safetyIntake.systemRevision==systemRevision,safetyIntake.systemSHA256==systemSHA256,recordedBy.workspaceID==workspaceID,recordedBy.responsibility == .recordedBy,(revision==1)==(supersedesRecordID==nil&&predecessorSHA256==nil),stopped == !safetyIntake.observationIsAuthorized,stopped ? conditionSnapshots.isEmpty && nightFollowupPlan==nil : !conditionSnapshots.isEmpty,complete ? safetyIntake.observationIsAuthorized:true,(state == .nightFollowupPrepared)==(nightFollowupPlan != nil),nightFollowupPlan.map({$0.workspaceID==workspaceID&&$0.sourceSystemID==systemID&&$0.sourceSystemRevision==systemRevision&&$0.sourceSystemSHA256==systemSHA256&&$0.sourceDayInventoryContentSHA256==dayInventoryContentSHA256&&Set($0.selectedLuminaireIDs).isSubset(of:Set(conditionSnapshots.map(\.luminaireID)))}) ?? true,dayInventoryContentSHA256==(try Self.contentDigest(workspaceID:workspaceID,systemID:systemID,systemRevision:systemRevision,systemSHA256:systemSHA256,safetyIntake:safetyIntake,snapshots:conditionSnapshots)),workflowSHA256==(try LightingDayInventoryCanonicalCodecV1.sha256(basis))else{throw LightingDayInventoryFailureV1.invalidValue}}
    func validate(system:LightingSystemV1)throws{try validateIntrinsic();try system.validateIntrinsic();try safetyIntake.validate(system:system);guard workspaceID==system.workspaceID,systemID==system.systemID,systemRevision==system.revision,systemSHA256==system.systemSHA256,packageRelease==system.packageRelease,state == .safetyStopped || Set(conditionSnapshots.map(\.luminaireID))==Set(system.luminaires.map(\.luminaireID)),conditionSnapshots.allSatisfy({snapshot in system.luminaires.contains(where:{$0.luminaireID==snapshot.luminaireID&&$0.assetID==snapshot.assetID&&$0.assetRevision==snapshot.assetRevision&&$0.zoneIDs.contains(snapshot.zoneID)&&$0.controlGroupIDs.contains(snapshot.controlGroupID)})})else{throw LightingDayInventoryFailureV1.incompleteInventory}}
    func validateSuccessor(of predecessor:Self)throws{try predecessor.validateIntrinsic();try validateIntrinsic();guard workflowID==predecessor.workflowID,workspaceID==predecessor.workspaceID,recordID != predecessor.recordID,supersedesRecordID==predecessor.recordID,predecessorSHA256==predecessor.workflowSHA256,revision==(try LightingDayInventoryLimitsV1.next(predecessor.revision)),mutationID != predecessor.mutationID,recordedAt>=predecessor.recordedAt,predecessor.state != .safetyStopped,state != .safetyStopped,!(predecessor.state == .nightFollowupPrepared),state == .nightFollowupPrepared,safetyIntake==predecessor.safetyIntake,conditionSnapshots==predecessor.conditionSnapshots,dayInventoryContentSHA256==predecessor.dayInventoryContentSHA256 else{throw LightingDayInventoryFailureV1.invalidSuccessor}}
    func rebound(recordID:UUID,workflowID:UUID,to destinationSystem:LightingSystemV1,safetyIntake destinationSafety:LightingSafetyIntakeV1,conditionSnapshots destinationSnapshots:[LightingDayConditionSnapshotV1],nightFollowupPlan destinationNightPlan:LightingNightFollowupPlanV1?,mutationID:MutationIDV1,recordedBy:ActorSnapshotV1,recordedAt:Date)throws->Self{
        try validateIntrinsic();try destinationSystem.validateIntrinsic();try destinationSafety.validate(system:destinationSystem)
        let destinationState:LightingDayInventoryWorkflowStateV1
        if state == .safetyStopped { guard destinationSnapshots.isEmpty,destinationNightPlan==nil else{throw LightingDayInventoryFailureV1.safetyStop};destinationState = .safetyStopped }
        else if destinationNightPlan != nil { destinationState = .nightFollowupPrepared }
        else { destinationState = .dayInventoryRecorded }
        let sourceFactInventory=try conditionSnapshots.map{try LightingDayInventoryCanonicalCodecV1.sha256($0.facts)}.sorted()
        let destinationFactInventory=try destinationSnapshots.map{try LightingDayInventoryCanonicalCodecV1.sha256($0.facts)}.sorted()
        guard destinationSystem.workspaceID != workspaceID,
              destinationSafety.workspaceID == destinationSystem.workspaceID,
              destinationSnapshots.count == conditionSnapshots.count,
              destinationFactInventory == sourceFactInventory,
              destinationNightPlan == nil else { throw LightingDayInventoryFailureV1.staleReference }
        let value=try Self(recordID:recordID,workflowID:workflowID,workspaceID:destinationSystem.workspaceID,system:destinationSystem,safetyIntake:destinationSafety,conditionSnapshots:destinationSnapshots,state:destinationState,nightFollowupPlan:nil,predecessor:nil,revision:1,mutationID:mutationID,recordedBy:recordedBy,recordedAt:recordedAt)
        try value.validate(system:destinationSystem);return value
    }
    private static func snapshotLess(_ l:LightingDayConditionSnapshotV1,_ r:LightingDayConditionSnapshotV1)->Bool{(l.zoneID.uuidString,l.controlGroupID.uuidString,l.luminaireID.uuidString,l.observation.observationID.uuidString)<(r.zoneID.uuidString,r.controlGroupID.uuidString,r.luminaireID.uuidString,r.observation.observationID.uuidString)}
    private static func contentDigest(workspaceID:WorkspaceID,systemID:UUID,systemRevision:UInt64,systemSHA256:String,safetyIntake:LightingSafetyIntakeV1,snapshots:[LightingDayConditionSnapshotV1])throws->String{try LightingDayInventoryCanonicalCodecV1.sha256(ContentBasis(workspaceID:workspaceID,systemID:systemID,systemRevision:systemRevision,systemSHA256:systemSHA256,safetyIntake:safetyIntake,conditionSnapshots:snapshots))}
    private struct ContentBasis:Codable{let workspaceID:WorkspaceID;let systemID:UUID;let systemRevision:UInt64;let systemSHA256:String;let safetyIntake:LightingSafetyIntakeV1;let conditionSnapshots:[LightingDayConditionSnapshotV1]}
    private var basis:Basis{.init(schemaVersion:schemaVersion,recordID:recordID,workflowID:workflowID,workspaceID:workspaceID,systemID:systemID,systemRevision:systemRevision,systemSHA256:systemSHA256,packageRelease:packageRelease,safetyIntake:safetyIntake,conditionSnapshots:conditionSnapshots,state:state,dayInventoryContentSHA256:dayInventoryContentSHA256,nightFollowupPlan:nightFollowupPlan,supersedesRecordID:supersedesRecordID,predecessorSHA256:predecessorSHA256,revision:revision,mutationID:mutationID,recordedBy:recordedBy,recordedAt:recordedAt)};private struct Basis:Codable{let schemaVersion:Int;let recordID:UUID;let workflowID:UUID;let workspaceID:WorkspaceID;let systemID:UUID;let systemRevision:UInt64;let systemSHA256:String;let packageRelease:LightingPackageReleaseReferenceV1;let safetyIntake:LightingSafetyIntakeV1;let conditionSnapshots:[LightingDayConditionSnapshotV1];let state:LightingDayInventoryWorkflowStateV1;let dayInventoryContentSHA256:String;let nightFollowupPlan:LightingNightFollowupPlanV1?;let supersedesRecordID:UUID?;let predecessorSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1;let recordedBy:ActorSnapshotV1;let recordedAt:Date}
}

struct LightingDayInventoryAdmissionClosureV1:Codable,Equatable,Sendable{
    let system:LightingSystemV1;let observations:[LightingObservationV1]
    let poseEvents:[AssetPoseEventV1]
    let acceptedPoseAxisRegistryRelease:PoseAxisRegistryReleaseV1?
    let occurrence:OccurrenceHistoryEventV1?;let workPacket:WorkPacketManifestV1?
    let readiness:OfflineReadinessManifestV1?
    init(system:LightingSystemV1,observations:[LightingObservationV1],poseEvents:[AssetPoseEventV1],
         acceptedPoseAxisRegistryRelease:PoseAxisRegistryReleaseV1?=nil,
         occurrence:OccurrenceHistoryEventV1?,workPacket:WorkPacketManifestV1?,
         readiness:OfflineReadinessManifestV1?){
        self.system=system
        self.observations=observations.sorted{$0.observationID.uuidString<$1.observationID.uuidString}
        self.poseEvents=poseEvents.sorted{$0.eventID.uuidString<$1.eventID.uuidString}
        self.acceptedPoseAxisRegistryRelease=acceptedPoseAxisRegistryRelease
        self.occurrence=occurrence;self.workPacket=workPacket;self.readiness=readiness
    }
    func validate(_ value:LightingDayInventoryWorkflowV1)throws{
        try value.validate(system:system)
        guard observations==observations.sorted(by:{$0.observationID.uuidString<$1.observationID.uuidString}),
              poseEvents==poseEvents.sorted(by:{$0.eventID.uuidString<$1.eventID.uuidString}),
              Set(observations.map(\.observationID)).count==observations.count,
              Set(poseEvents.map(\.eventID)).count==poseEvents.count else{
            throw LightingDayInventoryFailureV1.duplicateIdentity
        }
        let observationsByID=Dictionary(uniqueKeysWithValues:observations.map{($0.observationID,$0)})
        let posesByID=Dictionary(uniqueKeysWithValues:poseEvents.map{($0.eventID,$0)})
        let referencedPoseIDs=Set(value.conditionSnapshots.compactMap{$0.poseEvent?.eventID})
        guard referencedPoseIDs == Set(poseEvents.map(\.eventID)) else{
            throw LightingDayInventoryFailureV1.incompleteInventory
        }
        for snapshot in value.conditionSnapshots{
            guard let observation=observationsByID[snapshot.observation.observationID],
                  try LightingObservationReferenceV1(observation)==snapshot.observation else{
                throw LightingDayInventoryFailureV1.staleReference
            }
            let pose=snapshot.poseEvent.flatMap{posesByID[$0.eventID]}
            try Self.validatePoseBinding(snapshot:snapshot,poseEvent:pose,
                                         registryRelease:acceptedPoseAxisRegistryRelease,
                                         packageRelease:system.packageRelease)
        }
        if let plan=value.nightFollowupPlan{
            guard let occurrence,let workPacket,let readiness else{throw LightingDayInventoryFailureV1.staleReference}
            try occurrence.validateIntrinsic();try workPacket.validate();try readiness.validate()
            guard LightingNightOccurrenceBindingV1(occurrence)==plan.occurrence,
                  try WorkPacketManifestReferenceV1(workPacket)==plan.workPacket,
                  occurrence.workspaceID==value.workspaceID,workPacket.workspaceID==value.workspaceID,
                  readiness.session.workspaceID==value.workspaceID,
                  readiness.sourceSnapshotSHA256==plan.offlineReadinessSourceSHA256,
                  readiness.manifestSHA256==plan.offlineReadinessManifestSHA256,
                  readiness.status == .ready,readiness.mayStartFieldWork else{
                throw LightingDayInventoryFailureV1.staleReference
            }
        }
    }
    static func validatePoseBinding(snapshot:LightingDayConditionSnapshotV1,
                                    poseEvent:AssetPoseEventV1?,
                                    registryRelease:PoseAxisRegistryReleaseV1?,
                                    packageRelease:LightingPackageReleaseReferenceV1)throws{
        try snapshot.validate();try packageRelease.validate();try poseEvent?.validateIntrinsic()
        let descriptors=registryRelease?.registry.descriptors.filter{
            $0.semanticRole == .lightBeamCenterline && $0.applicability == .applicable
        } ?? []
        guard descriptors.count<=1 else{throw LightingDayInventoryFailureV1.duplicateIdentity}
        if let registryRelease{
            try registryRelease.registry.validate()
            guard registryRelease.packageReleaseID==packageRelease.packageReleaseID,
                  registryRelease.packageID==packageRelease.packageID,
                  registryRelease.packageContentVersion==packageRelease.contentVersion,
                  registryRelease.packageSHA256==packageRelease.packageSHA256,
                  registryRelease.workflowSHA256==packageRelease.workflowSHA256,
                  registryRelease.releaseSHA256==(try LightingDayInventoryCanonicalCodecV1.sha256(
                    PoseRegistryReleaseBasis(packageReleaseID:registryRelease.packageReleaseID,
                        packageID:registryRelease.packageID,
                        packageContentVersion:registryRelease.packageContentVersion,
                        packageSHA256:registryRelease.packageSHA256,
                        workflowSHA256:registryRelease.workflowSHA256,
                        registry:registryRelease.registry))) else{
                throw LightingDayInventoryFailureV1.staleReference
            }
        }
        guard let descriptor=descriptors.first else{
            guard snapshot.poseDisposition == .notDeclared,snapshot.poseEvent==nil,poseEvent==nil else{
                throw LightingDayInventoryFailureV1.staleReference
            }
            return
        }
        guard let reference=snapshot.poseEvent,let poseEvent,
              poseEvent.reference==reference,poseEvent.workspaceID==snapshot.observation.workspaceID,
              poseEvent.assetID==snapshot.assetID,poseEvent.axisDescriptor==descriptor,
              reference.axisID==descriptor.axisID,
              poseDispositionMatches(snapshot.poseDisposition,poseEvent.pose.disposition) else{
            throw LightingDayInventoryFailureV1.staleReference
        }
    }
    static func poseDispositionMatches(_ snapshot:LightingDayPoseDispositionV1,
                                       _ event:PoseObservationDispositionV1)->Bool{
        switch (snapshot,event){
        case (.observed,.observed),(.notObserved,.notObserved):return true
        case (.notDeclared,_),(.observed,.notObserved),(.notObserved,.observed):return false
        }
    }
    private struct PoseRegistryReleaseBasis:Codable{
        let packageReleaseID:String;let packageID:String;let packageContentVersion:Int
        let packageSHA256:String;let workflowSHA256:String;let registry:PoseAxisDescriptorRegistryV1
    }
}

struct LightingDayInventoryProjectionV1:Equatable,Sendable{let workflow:LightingDayInventoryWorkflowV1;let safetyStopReasons:[LightingDaySafetyStopReasonV1];let unknownOrNotObservedCount:Int;let reportEligible:Bool;let searchEligible:Bool;let requiresReadinessRebuild:Bool
    init(_ value:LightingDayInventoryWorkflowV1)throws{try value.validateIntrinsic();workflow=value;safetyStopReasons=value.safetyIntake.stopReasons;unknownOrNotObservedCount=value.conditionSnapshots.flatMap(\.facts).filter{[LightingDayConditionStateV1.unknown,.notObserved].contains($0.state)}.count;reportEligible=value.state != .safetyStopped;searchEligible=value.state != .safetyStopped;requiresReadinessRebuild=value.nightFollowupPlan != nil}
}

struct LightingDayInventoryReportProjectionV1:Codable,Equatable,Sendable{let workspaceID:WorkspaceID;let workflowID:UUID;let workflowRevision:UInt64;let workflowSHA256:String;let state:LightingDayInventoryWorkflowStateV1;let safetyStopReasons:[LightingDaySafetyStopReasonV1];let snapshots:[LightingDayConditionSnapshotV1];let unknownOrNotObservedCount:Int;let daylightIsDescriptiveOnly:Bool
    init(_ value:LightingDayInventoryWorkflowV1)throws{try value.validateIntrinsic();workspaceID=value.workspaceID;workflowID=value.workflowID;workflowRevision=value.revision;workflowSHA256=value.workflowSHA256;state=value.state;safetyStopReasons=value.safetyIntake.stopReasons;snapshots=value.conditionSnapshots;unknownOrNotObservedCount=value.conditionSnapshots.flatMap(\.facts).filter{[LightingDayConditionStateV1.unknown,.notObserved].contains($0.state)}.count;daylightIsDescriptiveOnly=true}
}

struct LightingDayInventorySearchProjectionV1:Codable,Equatable,Sendable{let workspaceID:WorkspaceID;let workflowID:UUID;let workflowRevision:UInt64;let workflowSHA256:String;let systemID:UUID;let assetIDs:[UUID];let issueKinds:[LightingIssueKindV1];let includesUnknownOrNotObserved:Bool
    init(_ value:LightingDayInventoryWorkflowV1)throws{try value.validateIntrinsic();let assets=value.conditionSnapshots.map(\.assetID).sorted{$0.uuidString<$1.uuidString};let issues=Array(Set(value.conditionSnapshots.flatMap(\.facts).compactMap(\.issueKind))).sorted();workspaceID=value.workspaceID;workflowID=value.workflowID;workflowRevision=value.revision;workflowSHA256=value.workflowSHA256;systemID=value.systemID;assetIDs=assets;issueKinds=issues;includesUnknownOrNotObserved=value.conditionSnapshots.flatMap(\.facts).contains{[LightingDayConditionStateV1.unknown,.notObserved].contains($0.state)}}
}

struct LightingNightReadinessProjectionV1:Codable,Equatable,Sendable{let workspaceID:WorkspaceID;let workflowID:UUID;let workflowRevision:UInt64;let workflowSHA256:String;let planID:UUID;let sourceSnapshotSHA256:String;let priorManifestSHA256:String;let mustRebuildDerivedReadiness:Bool
    init(_ value:LightingDayInventoryWorkflowV1)throws{try value.validateIntrinsic();guard let plan=value.nightFollowupPlan else{throw LightingDayInventoryFailureV1.invalidValue};workspaceID=value.workspaceID;workflowID=value.workflowID;workflowRevision=value.revision;workflowSHA256=value.workflowSHA256;planID=plan.planID;sourceSnapshotSHA256=plan.offlineReadinessSourceSHA256;priorManifestSHA256=plan.offlineReadinessManifestSHA256;mustRebuildDerivedReadiness=true}
}

enum LightingDayInventoryCanonicalCodecV1{static func encoder()->JSONEncoder{let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];e.dateEncodingStrategy=.millisecondsSince1970;return e}static func decoder()->JSONDecoder{let d=JSONDecoder();d.dateDecodingStrategy=.millisecondsSince1970;return d}static func encode<T:Encodable>(_ value:T)throws->Data{let d=try encoder().encode(value);guard !d.isEmpty,d.count<=LightingDayInventoryLimitsV1.maximumCanonicalBytes else{throw LightingDayInventoryFailureV1.limitExceeded};return d}static func decode<T:Codable>(_ type:T.Type,from data:Data)throws->T{guard !data.isEmpty,data.count<=LightingDayInventoryLimitsV1.maximumCanonicalBytes else{throw LightingDayInventoryFailureV1.limitExceeded};let v=try decoder().decode(type,from:data);guard try encode(v)==data else{throw LightingDayInventoryFailureV1.nonCanonicalData};return v}static func sha256<T:Encodable>(_ value:T)throws->String{try WorkspaceMutationCanonicalV1.sha256(value)}}

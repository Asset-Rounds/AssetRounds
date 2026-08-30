import Foundation

enum ServiceReliabilityFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case invalidInterval
    case invalidHistory
    case wrongWorkspace
    case staleReference
    case unresolvedOverlap
    case arithmeticOverflow
    case unavailable(ServiceReliabilityUnavailableReasonV1)
    case nonCanonicalEncoding
}

protocol ServiceReliabilityCanonicalValidatingV1 {
    func validate() throws
}

enum ServiceReliabilityLimitsV1 {
    static let maximumTextBytes = 2_048
    static let maximumEvidenceCount = 64
    static let maximumBundleEvents = 128
    static let maximumIntervals = 10_000

    static func id(_ value: UUID) throws {
        guard value != UUID.zero else { throw ServiceReliabilityFailureV1.invalidValue }
    }

    static func digest(_ value: String) throws {
        guard MutationEnvelopeV1.isSHA256(value) else { throw ServiceReliabilityFailureV1.invalidValue }
    }

    static func text(_ value: String) throws {
        guard !value.isEmpty,
              value == value.precomposedStringWithCanonicalMapping,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              value.utf8.count <= maximumTextBytes,
              value.unicodeScalars.allSatisfy({ !$0.properties.isControl }) else {
            throw ServiceReliabilityFailureV1.invalidValue
        }
    }

    static func next(_ value: UInt64) throws -> UInt64 {
        let result = value.addingReportingOverflow(1)
        guard !result.overflow else { throw ServiceReliabilityFailureV1.arithmeticOverflow }
        return result.partialValue
    }

    static func add(_ lhs: UInt64, _ rhs: UInt64) throws -> UInt64 {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else { throw ServiceReliabilityFailureV1.arithmeticOverflow }
        return result.partialValue
    }
}

enum ServiceReliabilityCanonicalCodecV1 {
    static func encode<T: Encodable & ServiceReliabilityCanonicalValidatingV1>(_ value: T) throws -> Data {
        try value.validate()
        return try WorkspaceMutationCanonicalV1.data(value)
    }

    static func decode<T: Codable & ServiceReliabilityCanonicalValidatingV1>(
        _ type: T.Type,
        from data: Data
    ) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(type, from: data)
        try value.validate()
        guard try WorkspaceMutationCanonicalV1.data(value) == data else {
            throw ServiceReliabilityFailureV1.nonCanonicalEncoding
        }
        return value
    }

    static func sha256<T: Encodable>(_ value: T) throws -> String {
        try WorkspaceMutationCanonicalV1.sha256(value)
    }
}

// Exact integer instants keep interval union/subtraction deterministic. UI and
// evidence retain their independent TemporalContextV1 display provenance.
struct ServiceReliabilityInstantV1: Codable, Equatable, Hashable, Comparable, Sendable,
    ServiceReliabilityCanonicalValidatingV1 {
    let millisecondsSince1970: Int64

    init(millisecondsSince1970: Int64) { self.millisecondsSince1970 = millisecondsSince1970 }

    init(_ date: Date) throws {
        let milliseconds = date.timeIntervalSince1970 * 1_000
        guard milliseconds.isFinite,milliseconds.rounded(.towardZero) == milliseconds,
              let exactMilliseconds=Int64(exactly:milliseconds) else {
            throw ServiceReliabilityFailureV1.invalidValue
        }
        millisecondsSince1970 = exactMilliseconds
    }

    func validate() throws {}
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.millisecondsSince1970 < rhs.millisecondsSince1970 }
}

struct ServiceReliabilityClosedIntervalV1: Codable, Equatable, Hashable, Comparable, Sendable,
    ServiceReliabilityCanonicalValidatingV1 {
    let lowerBound: ServiceReliabilityInstantV1
    let upperBound: ServiceReliabilityInstantV1

    init(lowerBound: ServiceReliabilityInstantV1, upperBound: ServiceReliabilityInstantV1) throws {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        try validate()
    }

    func validate() throws {
        guard lowerBound < upperBound else { throw ServiceReliabilityFailureV1.invalidInterval }
    }

    var durationMilliseconds: UInt64 {
        get throws {
            let value = upperBound.millisecondsSince1970.subtractingReportingOverflow(
                lowerBound.millisecondsSince1970
            )
            guard !value.overflow, value.partialValue > 0 else {
                throw ServiceReliabilityFailureV1.arithmeticOverflow
            }
            return UInt64(value.partialValue)
        }
    }

    func intersection(_ other: Self) throws -> Self? {
        let lower = max(lowerBound, other.lowerBound)
        let upper = min(upperBound, other.upperBound)
        return lower < upper ? try Self(lowerBound: lower, upperBound: upper) : nil
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.lowerBound, lhs.upperBound) < (rhs.lowerBound, rhs.upperBound)
    }
}

enum ServiceImpactKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case fullInterruption = "FULL_INTERRUPTION"
    case degraded = "DEGRADED"
    case intermittent = "INTERMITTENT"
    case unknown = "UNKNOWN"

    var displayPrecedence: Int {
        switch self {
        case .fullInterruption: return 3
        case .degraded: return 2
        case .intermittent: return 1
        case .unknown: return 0
        }
    }
}

enum ServiceImpactOriginV1: String, Codable, CaseIterable, Hashable, Sendable {
    case planned = "PLANNED"
    case unplanned = "UNPLANNED"
    case unknown = "UNKNOWN"
}

enum ServiceTimeCertaintyV1: String, Codable, CaseIterable, Hashable, Sendable {
    case exact = "EXACT"
    case estimated = "ESTIMATED"
    case unknown = "UNKNOWN"
}

enum ServiceCauseAssessmentV1: String, Codable, CaseIterable, Hashable, Sendable {
    case unknown = "UNKNOWN"
    case suspectedByRecordedActor = "SUSPECTED_BY_RECORDED_ACTOR"
    case confirmedByRecordedActor = "CONFIRMED_BY_RECORDED_ACTOR"
}

enum ServiceIncidentContinuationV1: String, Codable, CaseIterable, Hashable, Sendable {
    case newOccurrence = "NEW_OCCURRENCE"
    case continuation = "CONTINUATION"
}

enum ServiceReliabilityCoverageV1: String, Codable, CaseIterable, Hashable, Sendable {
    case complete = "COMPLETE"
    case incomplete = "INCOMPLETE"
    case unknown = "UNKNOWN"
}

enum ServiceReliabilityQualificationSourceV1: String, Codable, CaseIterable, Hashable, Sendable {
    case actorDeclared = "ACTOR_DECLARED"
    case acceptedRecord = "ACCEPTED_RECORD"
}

enum ServiceReliabilityUnavailableReasonV1: String, Codable, CaseIterable, Hashable, Sendable {
    case zeroQualifiedExposure = "UNAVAILABLE_ZERO_QUALIFIED_EXPOSURE"
    case zeroQualifiedOperatingExposure = "UNAVAILABLE_ZERO_QUALIFIED_OPERATING_EXPOSURE"
    case noQualifyingFailureStarts = "UNAVAILABLE_NO_QUALIFYING_FAILURE_STARTS"
    case incompleteCoverage = "UNAVAILABLE_INCOMPLETE_COVERAGE"
    case uncertainInterval = "UNAVAILABLE_UNCERTAIN_INTERVAL"
    case unknownImpact = "UNAVAILABLE_UNKNOWN_IMPACT"
    case unknownOrigin = "UNAVAILABLE_UNKNOWN_ORIGIN"
    case plannedOverlap = "UNAVAILABLE_INCONSISTENT_PLANNED_OVERLAP"
    case unresolvedOverlap = "UNAVAILABLE_UNRESOLVED_OVERLAP"
    case missingTransitionIdentity = "UNAVAILABLE_MISSING_TRANSITION_IDENTITY"
    case openDowntime = "UNAVAILABLE_OPEN_DOWNTIME"
    case replacementOrResetAmbiguity = "UNAVAILABLE_REPLACEMENT_OR_RESET_AMBIGUITY"
    case downtimeExceedsExposure = "UNAVAILABLE_DOWNTIME_EXCEEDS_EXPOSURE"
    case noCompletedExactRepairs = "UNAVAILABLE_NO_COMPLETED_EXACT_REPAIRS"
}

enum ServiceReliabilityQualificationV1: Codable, Equatable, Hashable, Sendable {
    case qualified
    case unavailable(ServiceReliabilityUnavailableReasonV1)
}

struct ServiceReliabilityEventReferenceV1: Codable, Equatable, Hashable, Sendable,
    ServiceReliabilityCanonicalValidatingV1 {
    let eventID: UUID
    let revision: UInt64
    let eventSHA256: String

    func validate() throws {
        try ServiceReliabilityLimitsV1.id(eventID)
        try ServiceReliabilityLimitsV1.digest(eventSHA256)
        guard revision > 0 else { throw ServiceReliabilityFailureV1.invalidValue }
    }
}

struct ServiceReliabilitySubjectV1: Codable, Equatable, Hashable, Sendable,
    ServiceReliabilityCanonicalValidatingV1 {
    let asset: WorkSubjectReferenceV1
    let frozenScope: WorkSubjectScopeSnapshotV1
    let function: FrozenFunctionalRelationshipReferenceV1?
    let reliabilityIdentityEpochID: UUID

    func validate() throws {
        try asset.validate()
        try frozenScope.validate()
        try function?.validate()
        try ServiceReliabilityLimitsV1.id(reliabilityIdentityEpochID)
        guard asset.kind == .asset,
              frozenScope.subjects.contains(asset),
              frozenScope.semanticBindings.contains(where: { $0.assetID == asset.subjectID }),
              function.map({ relationship in
                  frozenScope.subjects.contains(where:{
                      $0.kind == .functionalRelationship && $0.functionalRelationship == relationship
                  })
              }) ?? true else {
            throw ServiceReliabilityFailureV1.staleReference
        }
    }
}

struct AssetServiceIncidentV1: Codable, Equatable, Sendable, ServiceReliabilityCanonicalValidatingV1 {
    static let schemaVersion = 1
    let schemaVersion: Int
    let eventID: UUID
    let incidentID: UUID
    let workspaceID: WorkspaceID
    let subject: ServiceReliabilitySubjectV1
    let continuation: ServiceIncidentContinuationV1
    let continuedIncidentID: UUID?
    let observationBasis: ObservationBasisV1
    let time: TemporalContextV1
    let recordedBy: ActorSnapshotV1
    let predecessor: ServiceReliabilityEventReferenceV1?
    let revision: UInt64
    let mutationID: MutationIDV1
    let eventSHA256: String

    init(eventID:UUID,incidentID:UUID,workspaceID:WorkspaceID,subject:ServiceReliabilitySubjectV1,
         continuation:ServiceIncidentContinuationV1,continuedIncidentID:UUID?=nil,
         observationBasis:ObservationBasisV1,time:TemporalContextV1,recordedBy:ActorSnapshotV1,
         predecessor:ServiceReliabilityEventReferenceV1?=nil,revision:UInt64,mutationID:MutationIDV1)throws{
        schemaVersion=Self.schemaVersion;self.eventID=eventID;self.incidentID=incidentID;self.workspaceID=workspaceID
        self.subject=subject;self.continuation=continuation;self.continuedIncidentID=continuedIncidentID
        self.observationBasis=observationBasis;self.time=time;self.recordedBy=recordedBy;self.predecessor=predecessor
        self.revision=revision;self.mutationID=mutationID
        eventSHA256=try ServiceReliabilityCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,eventID:eventID,
            incidentID:incidentID,workspaceID:workspaceID,subject:subject,continuation:continuation,
            continuedIncidentID:continuedIncidentID,observationBasis:observationBasis,time:time,
            recordedBy:recordedBy,predecessor:predecessor,revision:revision,mutationID:mutationID))
        try validate()
    }

    func validate()throws{try ServiceReliabilityLimitsV1.id(eventID);try ServiceReliabilityLimitsV1.id(incidentID)
        try subject.validate();try observationBasis.validate();try time.validate();try recordedBy.validate();try predecessor?.validate()
        let continuationShape=(continuation == .continuation)==(continuedIncidentID != nil)
        guard schemaVersion==Self.schemaVersion,subject.frozenScope.workspaceID==workspaceID,
              recordedBy.workspaceID==workspaceID,recordedBy.responsibility == .recordedBy,continuationShape,revision>0,
              (revision==1)==(predecessor==nil),eventSHA256==(try ServiceReliabilityCanonicalCodecV1.sha256(basis))
        else{throw ServiceReliabilityFailureV1.invalidHistory}}

    func validateSuccessor(of prior:Self)throws{try prior.validate();try validate();guard workspaceID==prior.workspaceID,
        incidentID==prior.incidentID,subject==prior.subject,predecessor==prior.reference,
        revision==(try ServiceReliabilityLimitsV1.next(prior.revision)),time.recordedAtUTC>=prior.time.recordedAtUTC,
        mutationID != prior.mutationID else{throw ServiceReliabilityFailureV1.invalidHistory}}
    var reference:ServiceReliabilityEventReferenceV1{.init(eventID:eventID,revision:revision,eventSHA256:eventSHA256)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,eventID:eventID,incidentID:incidentID,workspaceID:workspaceID,
        subject:subject,continuation:continuation,continuedIncidentID:continuedIncidentID,observationBasis:observationBasis,
        time:time,recordedBy:recordedBy,predecessor:predecessor,revision:revision,mutationID:mutationID)}
    private struct Basis:Codable{let schemaVersion:Int;let eventID,incidentID:UUID;let workspaceID:WorkspaceID
        let subject:ServiceReliabilitySubjectV1;let continuation:ServiceIncidentContinuationV1;let continuedIncidentID:UUID?
        let observationBasis:ObservationBasisV1;let time:TemporalContextV1;let recordedBy:ActorSnapshotV1
        let predecessor:ServiceReliabilityEventReferenceV1?;let revision:UInt64;let mutationID:MutationIDV1}
}

struct ServiceImpactSegmentV1: Codable, Equatable, Sendable, ServiceReliabilityCanonicalValidatingV1 {
    static let schemaVersion=1
    let schemaVersion:Int;let eventID,segmentID,incidentID:UUID;let workspaceID:WorkspaceID
    let subject:ServiceReliabilitySubjectV1;let impact:ServiceImpactKindV1;let origin:ServiceImpactOriginV1
    let interval:ServiceReliabilityClosedIntervalV1?;let openedAt:ServiceReliabilityInstantV1
    let certainty:ServiceTimeCertaintyV1;let transitionIntoImpactEventID:UUID?
    let observationBasis:ObservationBasisV1;let recordedTime:TemporalContextV1;let recordedBy:ActorSnapshotV1
    let evidence:[ContentReferenceV1];let predecessor:ServiceReliabilityEventReferenceV1?
    let revision:UInt64;let mutationID:MutationIDV1;let eventSHA256:String
    init(eventID:UUID,segmentID:UUID,incidentID:UUID,workspaceID:WorkspaceID,subject:ServiceReliabilitySubjectV1,
         impact:ServiceImpactKindV1,origin:ServiceImpactOriginV1,interval:ServiceReliabilityClosedIntervalV1?,
         openedAt:ServiceReliabilityInstantV1,certainty:ServiceTimeCertaintyV1,transitionIntoImpactEventID:UUID?=nil,
         observationBasis:ObservationBasisV1,recordedTime:TemporalContextV1,recordedBy:ActorSnapshotV1,
         evidence:[ContentReferenceV1]=[],predecessor:ServiceReliabilityEventReferenceV1?=nil,
         revision:UInt64,mutationID:MutationIDV1)throws{schemaVersion=Self.schemaVersion;self.eventID=eventID;self.segmentID=segmentID
        self.incidentID=incidentID;self.workspaceID=workspaceID;self.subject=subject;self.impact=impact;self.origin=origin
        self.interval=interval;self.openedAt=openedAt;self.certainty=certainty;self.transitionIntoImpactEventID=transitionIntoImpactEventID
        self.observationBasis=observationBasis;self.recordedTime=recordedTime;self.recordedBy=recordedBy
        self.evidence=evidence.sorted{$0.contentID<$1.contentID};self.predecessor=predecessor;self.revision=revision;self.mutationID=mutationID
        eventSHA256=try ServiceReliabilityCanonicalCodecV1.sha256(basis);try validate()}
    func validate()throws{try [eventID,segmentID,incidentID].forEach(ServiceReliabilityLimitsV1.id);try subject.validate()
        try interval?.validate();try openedAt.validate();try observationBasis.validate();try recordedTime.validate();try recordedBy.validate()
        try predecessor?.validate();if let transitionIntoImpactEventID{try ServiceReliabilityLimitsV1.id(transitionIntoImpactEventID)}
        guard schemaVersion==Self.schemaVersion,subject.frozenScope.workspaceID==workspaceID,recordedBy.workspaceID==workspaceID,
              recordedBy.responsibility == .recordedBy,
              evidence.count<=ServiceReliabilityLimitsV1.maximumEvidenceCount,evidence==evidence.sorted(by:{$0.contentID<$1.contentID}),
              Set(evidence.map(\.contentID)).count==evidence.count,evidence.allSatisfy({$0.workspaceID==workspaceID.rawValue.uuidString.lowercased()}),
              interval.map{$0.lowerBound==openedAt} ?? true,(certainty != .exact || interval != nil),revision>0,
              (revision==1)==(predecessor==nil),eventSHA256==(try ServiceReliabilityCanonicalCodecV1.sha256(basis))
        else{throw ServiceReliabilityFailureV1.invalidHistory}}
    func validateSuccessor(of prior:Self)throws{try prior.validate();try validate()
        guard workspaceID==prior.workspaceID,segmentID==prior.segmentID,incidentID==prior.incidentID,subject==prior.subject,
              predecessor==prior.reference,revision==(try ServiceReliabilityLimitsV1.next(prior.revision)),
              recordedTime.recordedAtUTC>=prior.recordedTime.recordedAtUTC,mutationID != prior.mutationID
        else{throw ServiceReliabilityFailureV1.invalidHistory}}
    var reference:ServiceReliabilityEventReferenceV1{.init(eventID:eventID,revision:revision,eventSHA256:eventSHA256)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,eventID:eventID,segmentID:segmentID,incidentID:incidentID,
        workspaceID:workspaceID,subject:subject,impact:impact,origin:origin,interval:interval,openedAt:openedAt,
        certainty:certainty,transitionIntoImpactEventID:transitionIntoImpactEventID,observationBasis:observationBasis,
        recordedTime:recordedTime,recordedBy:recordedBy,evidence:evidence,predecessor:predecessor,revision:revision,mutationID:mutationID)}
    private struct Basis:Codable{let schemaVersion:Int;let eventID,segmentID,incidentID:UUID;let workspaceID:WorkspaceID
        let subject:ServiceReliabilitySubjectV1;let impact:ServiceImpactKindV1;let origin:ServiceImpactOriginV1
        let interval:ServiceReliabilityClosedIntervalV1?;let openedAt:ServiceReliabilityInstantV1;let certainty:ServiceTimeCertaintyV1
        let transitionIntoImpactEventID:UUID?;let observationBasis:ObservationBasisV1;let recordedTime:TemporalContextV1
        let recordedBy:ActorSnapshotV1;let evidence:[ContentReferenceV1];let predecessor:ServiceReliabilityEventReferenceV1?
        let revision:UInt64;let mutationID:MutationIDV1}
}

struct ServiceCauseAssertionV1:Codable,Equatable,Sendable,ServiceReliabilityCanonicalValidatingV1{
    static let schemaVersion=1;let schemaVersion:Int;let eventID,assertionID,incidentID:UUID;let workspaceID:WorkspaceID
    let subject:ServiceReliabilitySubjectV1;let assessment:ServiceCauseAssessmentV1;let failureModeSemanticID:String?
    let note:String?;let observationBasis:ObservationBasisV1;let recordedTime:TemporalContextV1;let recordedBy:ActorSnapshotV1
    let predecessor:ServiceReliabilityEventReferenceV1?;let revision:UInt64;let mutationID:MutationIDV1;let eventSHA256:String
    init(eventID:UUID,assertionID:UUID,incidentID:UUID,workspaceID:WorkspaceID,subject:ServiceReliabilitySubjectV1,
         assessment:ServiceCauseAssessmentV1,failureModeSemanticID:String?=nil,note:String?=nil,
         observationBasis:ObservationBasisV1,recordedTime:TemporalContextV1,recordedBy:ActorSnapshotV1,
         predecessor:ServiceReliabilityEventReferenceV1?=nil,revision:UInt64,mutationID:MutationIDV1)throws{
        schemaVersion=Self.schemaVersion;self.eventID=eventID;self.assertionID=assertionID;self.incidentID=incidentID
        self.workspaceID=workspaceID;self.subject=subject;self.assessment=assessment;self.failureModeSemanticID=failureModeSemanticID
        self.note=note;self.observationBasis=observationBasis;self.recordedTime=recordedTime;self.recordedBy=recordedBy
        self.predecessor=predecessor;self.revision=revision;self.mutationID=mutationID
        eventSHA256=try ServiceReliabilityCanonicalCodecV1.sha256(basis);try validate()}
    func validate()throws{try [eventID,assertionID,incidentID].forEach(ServiceReliabilityLimitsV1.id);try subject.validate()
        try observationBasis.validate();try recordedTime.validate();try recordedBy.validate();try predecessor?.validate()
        if let failureModeSemanticID{try ServiceReliabilityLimitsV1.text(failureModeSemanticID)};if let note{try ServiceReliabilityLimitsV1.text(note)}
        guard schemaVersion==Self.schemaVersion,subject.frozenScope.workspaceID==workspaceID,recordedBy.workspaceID==workspaceID,
              recordedBy.responsibility == .recordedBy,
              revision>0,(revision==1)==(predecessor==nil),eventSHA256==(try ServiceReliabilityCanonicalCodecV1.sha256(basis))
        else{throw ServiceReliabilityFailureV1.invalidHistory}}
    func validateSuccessor(of prior:Self)throws{try prior.validate();try validate()
        guard workspaceID==prior.workspaceID,assertionID==prior.assertionID,incidentID==prior.incidentID,subject==prior.subject,
              predecessor==prior.reference,revision==(try ServiceReliabilityLimitsV1.next(prior.revision)),
              recordedTime.recordedAtUTC>=prior.recordedTime.recordedAtUTC,mutationID != prior.mutationID
        else{throw ServiceReliabilityFailureV1.invalidHistory}}
    var reference:ServiceReliabilityEventReferenceV1{.init(eventID:eventID,revision:revision,eventSHA256:eventSHA256)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,eventID:eventID,assertionID:assertionID,incidentID:incidentID,
        workspaceID:workspaceID,subject:subject,assessment:assessment,failureModeSemanticID:failureModeSemanticID,note:note,
        observationBasis:observationBasis,recordedTime:recordedTime,recordedBy:recordedBy,predecessor:predecessor,
        revision:revision,mutationID:mutationID)}
    private struct Basis:Codable{let schemaVersion:Int;let eventID,assertionID,incidentID:UUID;let workspaceID:WorkspaceID
        let subject:ServiceReliabilitySubjectV1;let assessment:ServiceCauseAssessmentV1;let failureModeSemanticID:String?
        let note:String?;let observationBasis:ObservationBasisV1;let recordedTime:TemporalContextV1;let recordedBy:ActorSnapshotV1
        let predecessor:ServiceReliabilityEventReferenceV1?;let revision:UInt64;let mutationID:MutationIDV1}
}

struct ServiceRemedyAssertionV1:Codable,Equatable,Sendable,ServiceReliabilityCanonicalValidatingV1{
    static let schemaVersion=1;let schemaVersion:Int;let eventID,assertionID,incidentID:UUID;let workspaceID:WorkspaceID
    let subject:ServiceReliabilitySubjectV1;let work:ScheduledWorkInstanceReferenceV1;let note:String?
    let recordedTime:TemporalContextV1;let recordedBy:ActorSnapshotV1;let predecessor:ServiceReliabilityEventReferenceV1?
    let revision:UInt64;let mutationID:MutationIDV1;let eventSHA256:String
    init(eventID:UUID,assertionID:UUID,incidentID:UUID,workspaceID:WorkspaceID,subject:ServiceReliabilitySubjectV1,
         work:ScheduledWorkInstanceReferenceV1,note:String?=nil,recordedTime:TemporalContextV1,recordedBy:ActorSnapshotV1,
         predecessor:ServiceReliabilityEventReferenceV1?=nil,revision:UInt64,mutationID:MutationIDV1)throws{
        schemaVersion=Self.schemaVersion;self.eventID=eventID;self.assertionID=assertionID;self.incidentID=incidentID
        self.workspaceID=workspaceID;self.subject=subject;self.work=work;self.note=note;self.recordedTime=recordedTime
        self.recordedBy=recordedBy;self.predecessor=predecessor;self.revision=revision;self.mutationID=mutationID
        eventSHA256=try ServiceReliabilityCanonicalCodecV1.sha256(basis);try validate()}
    func validate()throws{try [eventID,assertionID,incidentID].forEach(ServiceReliabilityLimitsV1.id);try subject.validate();try work.validate()
        try recordedTime.validate();try recordedBy.validate();try predecessor?.validate();if let note{try ServiceReliabilityLimitsV1.text(note)}
        guard schemaVersion==Self.schemaVersion,subject.frozenScope.workspaceID==workspaceID,recordedBy.workspaceID==workspaceID,
              recordedBy.responsibility == .recordedBy,
              revision>0,(revision==1)==(predecessor==nil),eventSHA256==(try ServiceReliabilityCanonicalCodecV1.sha256(basis))
        else{throw ServiceReliabilityFailureV1.invalidHistory}}
    func validateSuccessor(of prior:Self)throws{try prior.validate();try validate()
        guard workspaceID==prior.workspaceID,assertionID==prior.assertionID,incidentID==prior.incidentID,subject==prior.subject,
              predecessor==prior.reference,revision==(try ServiceReliabilityLimitsV1.next(prior.revision)),
              recordedTime.recordedAtUTC>=prior.recordedTime.recordedAtUTC,mutationID != prior.mutationID
        else{throw ServiceReliabilityFailureV1.invalidHistory}}
    var reference:ServiceReliabilityEventReferenceV1{.init(eventID:eventID,revision:revision,eventSHA256:eventSHA256)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,eventID:eventID,assertionID:assertionID,incidentID:incidentID,
        workspaceID:workspaceID,subject:subject,work:work,note:note,recordedTime:recordedTime,recordedBy:recordedBy,
        predecessor:predecessor,revision:revision,mutationID:mutationID)}
    private struct Basis:Codable{let schemaVersion:Int;let eventID,assertionID,incidentID:UUID;let workspaceID:WorkspaceID
        let subject:ServiceReliabilitySubjectV1;let work:ScheduledWorkInstanceReferenceV1;let note:String?
        let recordedTime:TemporalContextV1;let recordedBy:ActorSnapshotV1;let predecessor:ServiceReliabilityEventReferenceV1?
        let revision:UInt64;let mutationID:MutationIDV1}
}

struct ServiceRepairIntervalV1:Codable,Equatable,Sendable,ServiceReliabilityCanonicalValidatingV1{
    static let schemaVersion=1;let schemaVersion:Int;let eventID,repairID,incidentID:UUID;let workspaceID:WorkspaceID
    let subject:ServiceReliabilitySubjectV1;let interval:ServiceReliabilityClosedIntervalV1?
    let certainty:ServiceTimeCertaintyV1;let completed:Bool;let work:ScheduledWorkInstanceReferenceV1?
    let observationBasis:ObservationBasisV1;let recordedTime:TemporalContextV1;let recordedBy:ActorSnapshotV1
    let predecessor:ServiceReliabilityEventReferenceV1?;let revision:UInt64;let mutationID:MutationIDV1;let eventSHA256:String
    init(eventID:UUID,repairID:UUID,incidentID:UUID,workspaceID:WorkspaceID,subject:ServiceReliabilitySubjectV1,
         interval:ServiceReliabilityClosedIntervalV1?,certainty:ServiceTimeCertaintyV1,completed:Bool,
         work:ScheduledWorkInstanceReferenceV1?=nil,observationBasis:ObservationBasisV1,
         recordedTime:TemporalContextV1,recordedBy:ActorSnapshotV1,predecessor:ServiceReliabilityEventReferenceV1?=nil,
         revision:UInt64,mutationID:MutationIDV1)throws{schemaVersion=Self.schemaVersion;self.eventID=eventID;self.repairID=repairID
        self.incidentID=incidentID;self.workspaceID=workspaceID;self.subject=subject;self.interval=interval;self.certainty=certainty
        self.completed=completed;self.work=work;self.observationBasis=observationBasis;self.recordedTime=recordedTime
        self.recordedBy=recordedBy;self.predecessor=predecessor;self.revision=revision;self.mutationID=mutationID
        eventSHA256=try ServiceReliabilityCanonicalCodecV1.sha256(basis);try validate()}
    func validate()throws{try [eventID,repairID,incidentID].forEach(ServiceReliabilityLimitsV1.id);try subject.validate();try interval?.validate()
        try work?.validate();try observationBasis.validate();try recordedTime.validate();try recordedBy.validate();try predecessor?.validate()
        guard schemaVersion==Self.schemaVersion,subject.frozenScope.workspaceID==workspaceID,recordedBy.workspaceID==workspaceID,
              recordedBy.responsibility == .recordedBy,
              (certainty != .exact || interval != nil),(!completed || interval != nil),revision>0,(revision==1)==(predecessor==nil),
              eventSHA256==(try ServiceReliabilityCanonicalCodecV1.sha256(basis))else{throw ServiceReliabilityFailureV1.invalidHistory}}
    func validateSuccessor(of prior:Self)throws{try prior.validate();try validate()
        guard workspaceID==prior.workspaceID,repairID==prior.repairID,incidentID==prior.incidentID,subject==prior.subject,
              predecessor==prior.reference,revision==(try ServiceReliabilityLimitsV1.next(prior.revision)),
              recordedTime.recordedAtUTC>=prior.recordedTime.recordedAtUTC,mutationID != prior.mutationID
        else{throw ServiceReliabilityFailureV1.invalidHistory}}
    var reference:ServiceReliabilityEventReferenceV1{.init(eventID:eventID,revision:revision,eventSHA256:eventSHA256)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,eventID:eventID,repairID:repairID,incidentID:incidentID,
        workspaceID:workspaceID,subject:subject,interval:interval,certainty:certainty,completed:completed,work:work,
        observationBasis:observationBasis,recordedTime:recordedTime,recordedBy:recordedBy,predecessor:predecessor,
        revision:revision,mutationID:mutationID)}
    private struct Basis:Codable{let schemaVersion:Int;let eventID,repairID,incidentID:UUID;let workspaceID:WorkspaceID
        let subject:ServiceReliabilitySubjectV1;let interval:ServiceReliabilityClosedIntervalV1?
        let certainty:ServiceTimeCertaintyV1;let completed:Bool;let work:ScheduledWorkInstanceReferenceV1?
        let observationBasis:ObservationBasisV1;let recordedTime:TemporalContextV1;let recordedBy:ActorSnapshotV1
        let predecessor:ServiceReliabilityEventReferenceV1?;let revision:UInt64;let mutationID:MutationIDV1}
}

struct ServiceRestorationAssertionV1:Codable,Equatable,Sendable,ServiceReliabilityCanonicalValidatingV1{
    static let schemaVersion=1;let schemaVersion:Int;let eventID,assertionID,incidentID:UUID;let workspaceID:WorkspaceID
    let subject:ServiceReliabilitySubjectV1;let restoredAt:ServiceReliabilityInstantV1?;let certainty:ServiceTimeCertaintyV1
    let observationBasis:ObservationBasisV1;let recordedTime:TemporalContextV1;let recordedBy:ActorSnapshotV1
    let predecessor:ServiceReliabilityEventReferenceV1?;let revision:UInt64;let mutationID:MutationIDV1;let eventSHA256:String
    init(eventID:UUID,assertionID:UUID,incidentID:UUID,workspaceID:WorkspaceID,subject:ServiceReliabilitySubjectV1,
         restoredAt:ServiceReliabilityInstantV1?,certainty:ServiceTimeCertaintyV1,observationBasis:ObservationBasisV1,
         recordedTime:TemporalContextV1,recordedBy:ActorSnapshotV1,predecessor:ServiceReliabilityEventReferenceV1?=nil,
         revision:UInt64,mutationID:MutationIDV1)throws{schemaVersion=Self.schemaVersion;self.eventID=eventID
        self.assertionID=assertionID;self.incidentID=incidentID;self.workspaceID=workspaceID;self.subject=subject
        self.restoredAt=restoredAt;self.certainty=certainty;self.observationBasis=observationBasis;self.recordedTime=recordedTime
        self.recordedBy=recordedBy;self.predecessor=predecessor;self.revision=revision;self.mutationID=mutationID
        eventSHA256=try ServiceReliabilityCanonicalCodecV1.sha256(basis);try validate()}
    func validate()throws{try [eventID,assertionID,incidentID].forEach(ServiceReliabilityLimitsV1.id);try subject.validate()
        try restoredAt?.validate();try observationBasis.validate();try recordedTime.validate();try recordedBy.validate();try predecessor?.validate()
        guard schemaVersion==Self.schemaVersion,subject.frozenScope.workspaceID==workspaceID,recordedBy.workspaceID==workspaceID,
              recordedBy.responsibility == .recordedBy,
              (certainty != .exact || restoredAt != nil),revision>0,(revision==1)==(predecessor==nil),
              eventSHA256==(try ServiceReliabilityCanonicalCodecV1.sha256(basis))else{throw ServiceReliabilityFailureV1.invalidHistory}}
    func validateSuccessor(of prior:Self)throws{try prior.validate();try validate()
        guard workspaceID==prior.workspaceID,assertionID==prior.assertionID,incidentID==prior.incidentID,subject==prior.subject,
              predecessor==prior.reference,revision==(try ServiceReliabilityLimitsV1.next(prior.revision)),
              recordedTime.recordedAtUTC>=prior.recordedTime.recordedAtUTC,mutationID != prior.mutationID
        else{throw ServiceReliabilityFailureV1.invalidHistory}}
    var reference:ServiceReliabilityEventReferenceV1{.init(eventID:eventID,revision:revision,eventSHA256:eventSHA256)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,eventID:eventID,assertionID:assertionID,incidentID:incidentID,
        workspaceID:workspaceID,subject:subject,restoredAt:restoredAt,certainty:certainty,observationBasis:observationBasis,
        recordedTime:recordedTime,recordedBy:recordedBy,predecessor:predecessor,revision:revision,mutationID:mutationID)}
    private struct Basis:Codable{let schemaVersion:Int;let eventID,assertionID,incidentID:UUID;let workspaceID:WorkspaceID
        let subject:ServiceReliabilitySubjectV1;let restoredAt:ServiceReliabilityInstantV1?;let certainty:ServiceTimeCertaintyV1
        let observationBasis:ObservationBasisV1;let recordedTime:TemporalContextV1;let recordedBy:ActorSnapshotV1
        let predecessor:ServiceReliabilityEventReferenceV1?;let revision:UInt64;let mutationID:MutationIDV1}
}

struct QualifiedServiceExposureV1:Codable,Equatable,Sendable,ServiceReliabilityCanonicalValidatingV1{
    static let schemaVersion=1;let schemaVersion:Int;let eventID,exposureID:UUID;let workspaceID:WorkspaceID
    let subject:ServiceReliabilitySubjectV1;let interval:ServiceReliabilityClosedIntervalV1
    let declaredCoverageWindow:ServiceReliabilityClosedIntervalV1;let coverage:ServiceReliabilityCoverageV1
    let plannedNonserviceExclusions:[ServiceReliabilityClosedIntervalV1];let source:ServiceReliabilityQualificationSourceV1
    let observationBasis:ObservationBasisV1;let timeBasis:TemporalContextV1;let sourceNote:String?
    let recordedBy:ActorSnapshotV1;let predecessor:ServiceReliabilityEventReferenceV1?
    let revision:UInt64;let mutationID:MutationIDV1;let eventSHA256:String
    init(eventID:UUID,exposureID:UUID,workspaceID:WorkspaceID,subject:ServiceReliabilitySubjectV1,
         interval:ServiceReliabilityClosedIntervalV1,declaredCoverageWindow:ServiceReliabilityClosedIntervalV1,
         coverage:ServiceReliabilityCoverageV1,plannedNonserviceExclusions:[ServiceReliabilityClosedIntervalV1]=[],
         source:ServiceReliabilityQualificationSourceV1,observationBasis:ObservationBasisV1,timeBasis:TemporalContextV1,
         sourceNote:String?=nil,recordedBy:ActorSnapshotV1,predecessor:ServiceReliabilityEventReferenceV1?=nil,
         revision:UInt64,mutationID:MutationIDV1)throws{schemaVersion=Self.schemaVersion;self.eventID=eventID;self.exposureID=exposureID
        self.workspaceID=workspaceID;self.subject=subject;self.interval=interval;self.declaredCoverageWindow=declaredCoverageWindow
        self.coverage=coverage;self.plannedNonserviceExclusions=plannedNonserviceExclusions.sorted();self.source=source
        self.observationBasis=observationBasis;self.timeBasis=timeBasis;self.sourceNote=sourceNote;self.recordedBy=recordedBy
        self.predecessor=predecessor;self.revision=revision;self.mutationID=mutationID
        eventSHA256=try ServiceReliabilityCanonicalCodecV1.sha256(basis);try validate()}
    func validate()throws{try [eventID,exposureID].forEach(ServiceReliabilityLimitsV1.id);try subject.validate();try interval.validate()
        try declaredCoverageWindow.validate();try plannedNonserviceExclusions.forEach{$0.validate()};try observationBasis.validate()
        try timeBasis.validate();try recordedBy.validate();try predecessor?.validate();if let sourceNote{try ServiceReliabilityLimitsV1.text(sourceNote)}
        let exclusionsInside=plannedNonserviceExclusions.allSatisfy{$0.lowerBound>=interval.lowerBound&&$0.upperBound<=interval.upperBound}
        guard schemaVersion==Self.schemaVersion,subject.frozenScope.workspaceID==workspaceID,recordedBy.workspaceID==workspaceID,
              recordedBy.responsibility == .recordedBy,
              interval.lowerBound>=declaredCoverageWindow.lowerBound,interval.upperBound<=declaredCoverageWindow.upperBound,
              exclusionsInside,plannedNonserviceExclusions.count<=ServiceReliabilityLimitsV1.maximumIntervals,
              plannedNonserviceExclusions==plannedNonserviceExclusions.sorted(),!Self.hasOverlap(plannedNonserviceExclusions),
              revision>0,(revision==1)==(predecessor==nil),eventSHA256==(try ServiceReliabilityCanonicalCodecV1.sha256(basis))
        else{throw ServiceReliabilityFailureV1.invalidHistory}}
    func validateSuccessor(of prior:Self)throws{try prior.validate();try validate()
        guard workspaceID==prior.workspaceID,exposureID==prior.exposureID,subject==prior.subject,
              predecessor==prior.reference,revision==(try ServiceReliabilityLimitsV1.next(prior.revision)),
              timeBasis.recordedAtUTC>=prior.timeBasis.recordedAtUTC,mutationID != prior.mutationID
        else{throw ServiceReliabilityFailureV1.invalidHistory}}
    private static func hasOverlap(_ values:[ServiceReliabilityClosedIntervalV1])->Bool{
        zip(values,values.dropFirst()).contains{$0.0.upperBound>$0.1.lowerBound}
    }
    var reference:ServiceReliabilityEventReferenceV1{.init(eventID:eventID,revision:revision,eventSHA256:eventSHA256)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,eventID:eventID,exposureID:exposureID,workspaceID:workspaceID,
        subject:subject,interval:interval,declaredCoverageWindow:declaredCoverageWindow,coverage:coverage,
        plannedNonserviceExclusions:plannedNonserviceExclusions,source:source,observationBasis:observationBasis,
        timeBasis:timeBasis,sourceNote:sourceNote,recordedBy:recordedBy,predecessor:predecessor,revision:revision,mutationID:mutationID)}
    private struct Basis:Codable{let schemaVersion:Int;let eventID,exposureID:UUID;let workspaceID:WorkspaceID
        let subject:ServiceReliabilitySubjectV1;let interval,declaredCoverageWindow:ServiceReliabilityClosedIntervalV1
        let coverage:ServiceReliabilityCoverageV1;let plannedNonserviceExclusions:[ServiceReliabilityClosedIntervalV1]
        let source:ServiceReliabilityQualificationSourceV1;let observationBasis:ObservationBasisV1;let timeBasis:TemporalContextV1
        let sourceNote:String?;let recordedBy:ActorSnapshotV1;let predecessor:ServiceReliabilityEventReferenceV1?
        let revision:UInt64;let mutationID:MutationIDV1}
}

struct NormalizedServiceIntervalV1:Codable,Equatable,Hashable,Comparable,Sendable,ServiceReliabilityCanonicalValidatingV1{
    let interval:ServiceReliabilityClosedIntervalV1;let sourceEventIDs:[UUID]
    init(interval:ServiceReliabilityClosedIntervalV1,sourceEventIDs:[UUID])throws{self.interval=interval
        self.sourceEventIDs=sourceEventIDs.sorted{$0.uuidString<$1.uuidString};try validate()}
    func validate()throws{try interval.validate();try sourceEventIDs.forEach(ServiceReliabilityLimitsV1.id)
        guard !sourceEventIDs.isEmpty,sourceEventIDs==sourceEventIDs.sorted(by:{$0.uuidString<$1.uuidString}),
              Set(sourceEventIDs).count==sourceEventIDs.count else{throw ServiceReliabilityFailureV1.invalidValue}}
    static func <(l:Self,r:Self)->Bool{l.interval<r.interval}
}

struct MaximalDowntimeComponentV1:Codable,Equatable,Hashable,Sendable,ServiceReliabilityCanonicalValidatingV1{
    let interval:ServiceReliabilityClosedIntervalV1;let incidentIDs:[UUID];let segmentEventIDs:[UUID]
    let qualifyingFailureStartEventID:UUID?;let componentSHA256:String
    init(interval:ServiceReliabilityClosedIntervalV1,incidentIDs:[UUID],segmentEventIDs:[UUID],qualifyingFailureStartEventID:UUID?)throws{
        self.interval=interval;self.incidentIDs=incidentIDs.sorted{$0.uuidString<$1.uuidString}
        self.segmentEventIDs=segmentEventIDs.sorted{$0.uuidString<$1.uuidString};self.qualifyingFailureStartEventID=qualifyingFailureStartEventID
        componentSHA256=try ServiceReliabilityCanonicalCodecV1.sha256(Basis(interval:interval,incidentIDs:self.incidentIDs,
            segmentEventIDs:self.segmentEventIDs,qualifyingFailureStartEventID:qualifyingFailureStartEventID));try validate()}
    func validate()throws{try interval.validate();try incidentIDs.forEach(ServiceReliabilityLimitsV1.id)
        try segmentEventIDs.forEach(ServiceReliabilityLimitsV1.id);if let qualifyingFailureStartEventID{try ServiceReliabilityLimitsV1.id(qualifyingFailureStartEventID)}
        try ServiceReliabilityLimitsV1.digest(componentSHA256);guard !incidentIDs.isEmpty,!segmentEventIDs.isEmpty,
              incidentIDs==incidentIDs.sorted(by:{$0.uuidString<$1.uuidString}),Set(incidentIDs).count==incidentIDs.count,
              segmentEventIDs==segmentEventIDs.sorted(by:{$0.uuidString<$1.uuidString}),Set(segmentEventIDs).count==segmentEventIDs.count,
              componentSHA256==(try ServiceReliabilityCanonicalCodecV1.sha256(basis))else{throw ServiceReliabilityFailureV1.invalidValue}}
    private var basis:Basis{.init(interval:interval,incidentIDs:incidentIDs,segmentEventIDs:segmentEventIDs,
        qualifyingFailureStartEventID:qualifyingFailureStartEventID)}
    private struct Basis:Codable{let interval:ServiceReliabilityClosedIntervalV1;let incidentIDs,segmentEventIDs:[UUID]
        let qualifyingFailureStartEventID:UUID?}
}

struct ServiceReliabilityExcludedSourceV1:Codable,Equatable,Hashable,Comparable,Sendable,
    ServiceReliabilityCanonicalValidatingV1{
    let sourceEventID:UUID;let reason:ServiceReliabilityUnavailableReasonV1
    func validate()throws{try ServiceReliabilityLimitsV1.id(sourceEventID)}
    static func <(l:Self,r:Self)->Bool{(l.sourceEventID.uuidString,l.reason.rawValue)<(r.sourceEventID.uuidString,r.reason.rawValue)}
}

struct ServiceReliabilityRationalV1:Codable,Equatable,Sendable,ServiceReliabilityCanonicalValidatingV1{
    let numerator:UInt64;let denominator:UInt64
    init(numerator:UInt64,denominator:UInt64)throws{guard denominator>0 else{throw ServiceReliabilityFailureV1.invalidValue}
        let divisor=Self.greatestCommonDivisor(numerator,denominator);self.numerator=numerator/divisor;self.denominator=denominator/divisor}
    func validate()throws{guard denominator>0,Self.greatestCommonDivisor(numerator,denominator)==1
        else{throw ServiceReliabilityFailureV1.invalidValue}}
    private static func greatestCommonDivisor(_ lhs:UInt64,_ rhs:UInt64)->UInt64{
        var a=lhs,b=rhs;while b != 0{let remainder=a%b;a=b;b=remainder};return a == 0 ? 1:a
    }
}

struct ReliabilityMetricInputProjectionV1:Codable,Equatable,Sendable,ServiceReliabilityCanonicalValidatingV1{
    static let schemaVersion=1;let schemaVersion:Int;let workspaceID:WorkspaceID;let subject:ServiceReliabilitySubjectV1
    let observationWindow:ServiceReliabilityClosedIntervalV1;let asOf:ServiceReliabilityInstantV1
    let exposure:[NormalizedServiceIntervalV1];let downtime:[NormalizedServiceIntervalV1]
    let operatingExposure:[NormalizedServiceIntervalV1];let maximalDowntimeComponents:[MaximalDowntimeComponentV1]
    let qualifiedRepairIntervals:[ServiceReliabilityClosedIntervalV1];let qualifiedRestorationIntervals:[ServiceReliabilityClosedIntervalV1]
    let exposureDurationMilliseconds,unplannedFullDowntimeMilliseconds,operatingExposureDurationMilliseconds:UInt64
    let exactRepairDurationMilliseconds,exactRestorationDurationMilliseconds:UInt64
    let qualifyingFailureStartEventIDs:[UUID];let completedRepairCount:Int
    let availabilityQualification,mtbfQualification,mttrQualification:ServiceReliabilityQualificationV1
    let includedSourceEventIDs:[UUID];let excludedSources:[ServiceReliabilityExcludedSourceV1]
    let intervalUnionPolicySHA256,sourceClosureSHA256,projectionSHA256:String
    var availabilityFraction:ServiceReliabilityRationalV1?{get throws{
        guard availabilityQualification == .qualified else{return nil}
        return try .init(numerator:operatingExposureDurationMilliseconds,denominator:exposureDurationMilliseconds)}}
    var mtbfOperatingMillisecondsPerFailure:ServiceReliabilityRationalV1?{get throws{
        guard mtbfQualification == .qualified else{return nil}
        return try .init(numerator:operatingExposureDurationMilliseconds,denominator:UInt64(qualifyingFailureStartEventIDs.count))}}
    var meanExactRepairMilliseconds:ServiceReliabilityRationalV1?{get throws{
        guard mttrQualification == .qualified,completedRepairCount>0 else{return nil}
        return try .init(numerator:exactRepairDurationMilliseconds,denominator:UInt64(completedRepairCount))}}
    var meanRecordedRestorationMilliseconds:ServiceReliabilityRationalV1?{get throws{
        guard !qualifiedRestorationIntervals.isEmpty else{return nil}
        return try .init(numerator:exactRestorationDurationMilliseconds,denominator:UInt64(qualifiedRestorationIntervals.count))}}
    init(workspaceID:WorkspaceID,subject:ServiceReliabilitySubjectV1,observationWindow:ServiceReliabilityClosedIntervalV1,
         asOf:ServiceReliabilityInstantV1,exposure:[NormalizedServiceIntervalV1],downtime:[NormalizedServiceIntervalV1],
         operatingExposure:[NormalizedServiceIntervalV1],maximalDowntimeComponents:[MaximalDowntimeComponentV1],
         qualifiedRepairIntervals:[ServiceReliabilityClosedIntervalV1],qualifiedRestorationIntervals:[ServiceReliabilityClosedIntervalV1],
         exposureDurationMilliseconds:UInt64,unplannedFullDowntimeMilliseconds:UInt64,operatingExposureDurationMilliseconds:UInt64,
         exactRepairDurationMilliseconds:UInt64,exactRestorationDurationMilliseconds:UInt64,
         qualifyingFailureStartEventIDs:[UUID],completedRepairCount:Int,
         availabilityQualification:ServiceReliabilityQualificationV1,mtbfQualification:ServiceReliabilityQualificationV1,
         mttrQualification:ServiceReliabilityQualificationV1,includedSourceEventIDs:[UUID],
         excludedSources:[ServiceReliabilityExcludedSourceV1],intervalUnionPolicySHA256:String,sourceClosureSHA256:String)throws{
        let canonicalRepairIntervals=try Self.canonicalIntervals(qualifiedRepairIntervals)
        let canonicalRestorationIntervals=try Self.canonicalIntervals(qualifiedRestorationIntervals)
        schemaVersion=Self.schemaVersion;self.workspaceID=workspaceID;self.subject=subject;self.observationWindow=observationWindow
        self.asOf=asOf;self.exposure=exposure;self.downtime=downtime;self.operatingExposure=operatingExposure
        self.maximalDowntimeComponents=maximalDowntimeComponents;self.qualifiedRepairIntervals=canonicalRepairIntervals
        self.qualifiedRestorationIntervals=canonicalRestorationIntervals;self.exposureDurationMilliseconds=exposureDurationMilliseconds
        self.unplannedFullDowntimeMilliseconds=unplannedFullDowntimeMilliseconds
        self.operatingExposureDurationMilliseconds=operatingExposureDurationMilliseconds
        self.exactRepairDurationMilliseconds=exactRepairDurationMilliseconds;self.exactRestorationDurationMilliseconds=exactRestorationDurationMilliseconds
        self.qualifyingFailureStartEventIDs=qualifyingFailureStartEventIDs.sorted{$0.uuidString<$1.uuidString}
        self.completedRepairCount=completedRepairCount;self.availabilityQualification=availabilityQualification
        self.mtbfQualification=mtbfQualification;self.mttrQualification=mttrQualification
        self.includedSourceEventIDs=includedSourceEventIDs.sorted{$0.uuidString<$1.uuidString};self.excludedSources=excludedSources.sorted()
        self.intervalUnionPolicySHA256=intervalUnionPolicySHA256;self.sourceClosureSHA256=sourceClosureSHA256
        projectionSHA256=try ServiceReliabilityCanonicalCodecV1.sha256(basis);try validate()}
    func validate()throws{try subject.validate();try observationWindow.validate();try asOf.validate()
        try exposure.forEach{$0.validate()};try downtime.forEach{$0.validate()};try operatingExposure.forEach{$0.validate()}
        try maximalDowntimeComponents.forEach{$0.validate()};try qualifiedRepairIntervals.forEach{$0.validate()}
        try qualifiedRestorationIntervals.forEach{$0.validate()};try qualifyingFailureStartEventIDs.forEach(ServiceReliabilityLimitsV1.id)
        try includedSourceEventIDs.forEach(ServiceReliabilityLimitsV1.id);try excludedSources.forEach{$0.validate()}
        try [intervalUnionPolicySHA256,sourceClosureSHA256,projectionSHA256].forEach(ServiceReliabilityLimitsV1.digest)
        let canonicalExposure=try ServiceReliabilityIntervalAlgebraV1.union(exposure)
        let canonicalDowntime=try ServiceReliabilityIntervalAlgebraV1.union(downtime)
        let canonicalRepairs=try Self.canonicalIntervals(qualifiedRepairIntervals)
        let canonicalRestorations=try Self.canonicalIntervals(qualifiedRestorationIntervals)
        let expectedOperating=try ServiceReliabilityIntervalAlgebraV1.subtract(canonicalExposure,canonicalDowntime)
        let downtimeIsInsideExposure=canonicalDowntime.allSatisfy{down in
            canonicalExposure.contains(where:{up in
                up.interval.lowerBound<=down.interval.lowerBound&&down.interval.upperBound<=up.interval.upperBound
            })
        }
        let componentParity=zip(maximalDowntimeComponents,canonicalDowntime).allSatisfy{
            $0.0.interval==$0.1.interval&&$0.0.segmentEventIDs==$0.1.sourceEventIDs
        }
        let expectedFailureStarts=maximalDowntimeComponents.compactMap(\.qualifyingFailureStartEventID)
            .sorted{$0.uuidString<$1.uuidString}
        let expectedAvailability:ServiceReliabilityQualificationV1=excludedSources.isEmpty
            ? (exposureDurationMilliseconds==0 ? .unavailable(.zeroQualifiedExposure):.qualified)
            : .unavailable(excludedSources[0].reason)
        let expectedMTBF:ServiceReliabilityQualificationV1
        if expectedAvailability != .qualified{expectedMTBF=expectedAvailability
        }else if operatingExposureDurationMilliseconds==0{expectedMTBF = .unavailable(.zeroQualifiedOperatingExposure)
        }else if maximalDowntimeComponents.contains(where:{$0.qualifyingFailureStartEventID==nil}){
            expectedMTBF = .unavailable(.missingTransitionIdentity)
        }else if qualifyingFailureStartEventIDs.isEmpty{expectedMTBF = .unavailable(.noQualifyingFailureStarts)
        }else{expectedMTBF = .qualified}
        let expectedMTTR:ServiceReliabilityQualificationV1=qualifiedRepairIntervals.isEmpty
            ? .unavailable(.noCompletedExactRepairs):.qualified
        guard schemaVersion==Self.schemaVersion,subject.frozenScope.workspaceID==workspaceID,completedRepairCount>=0,
              Self.nonoverlapping(exposure),Self.nonoverlapping(downtime),Self.nonoverlapping(operatingExposure),
              exposure==canonicalExposure,downtime==canonicalDowntime,operatingExposure==expectedOperating,
              qualifiedRepairIntervals.count<=ServiceReliabilityLimitsV1.maximumIntervals,
              qualifiedRestorationIntervals.count<=ServiceReliabilityLimitsV1.maximumIntervals,
              qualifiedRepairIntervals==canonicalRepairs,qualifiedRestorationIntervals==canonicalRestorations,
              downtimeIsInsideExposure,maximalDowntimeComponents.count==canonicalDowntime.count,componentParity,
              exposureDurationMilliseconds==(try Self.duration(exposure.map(\.interval))),
              unplannedFullDowntimeMilliseconds==(try Self.duration(downtime.map(\.interval))),
              operatingExposureDurationMilliseconds==(try Self.duration(operatingExposure.map(\.interval))),
              exactRepairDurationMilliseconds==(try Self.duration(qualifiedRepairIntervals)),
              exactRestorationDurationMilliseconds==(try Self.duration(qualifiedRestorationIntervals)),
              operatingExposureDurationMilliseconds<=exposureDurationMilliseconds,
              unplannedFullDowntimeMilliseconds<=exposureDurationMilliseconds,
              completedRepairCount==qualifiedRepairIntervals.count,
              availabilityQualification==expectedAvailability,mtbfQualification==expectedMTBF,mttrQualification==expectedMTTR,
              qualifyingFailureStartEventIDs==expectedFailureStarts,
              Set(qualifyingFailureStartEventIDs).count==qualifyingFailureStartEventIDs.count,
              includedSourceEventIDs==includedSourceEventIDs.sorted(by:{$0.uuidString<$1.uuidString}),
              Set(includedSourceEventIDs).count==includedSourceEventIDs.count,excludedSources==excludedSources.sorted(),
              Set(excludedSources).count==excludedSources.count,projectionSHA256==(try ServiceReliabilityCanonicalCodecV1.sha256(basis))
        else{throw ServiceReliabilityFailureV1.invalidValue}}
    private static func nonoverlapping(_ values:[NormalizedServiceIntervalV1])->Bool{
        let ordered=values.sorted();return !zip(ordered,ordered.dropFirst()).contains{$0.0.interval.upperBound>$0.1.interval.lowerBound}}
    private static func duration(_ values:[ServiceReliabilityClosedIntervalV1])throws->UInt64{
        var total:UInt64=0;for value in values{total=try ServiceReliabilityLimitsV1.add(total,value.durationMilliseconds)};return total}
    private static func canonicalIntervals(_ values:[ServiceReliabilityClosedIntervalV1])throws->[ServiceReliabilityClosedIntervalV1]{
        guard values.count<=ServiceReliabilityLimitsV1.maximumIntervals else{throw ServiceReliabilityFailureV1.invalidValue}
        let ordered=values.sorted();var result:[ServiceReliabilityClosedIntervalV1]=[]
        for value in ordered{try value.validate();guard let prior=result.last else{result.append(value);continue}
            if value.lowerBound<=prior.upperBound{result.removeLast();result.append(try .init(
                lowerBound:prior.lowerBound,upperBound:max(prior.upperBound,value.upperBound)))
            }else{result.append(value)}}
        return result
    }
    private var basis:Basis{.init(schemaVersion:schemaVersion,workspaceID:workspaceID,subject:subject,
        observationWindow:observationWindow,asOf:asOf,exposure:exposure,downtime:downtime,operatingExposure:operatingExposure,
        maximalDowntimeComponents:maximalDowntimeComponents,qualifiedRepairIntervals:qualifiedRepairIntervals,
        qualifiedRestorationIntervals:qualifiedRestorationIntervals,exposureDurationMilliseconds:exposureDurationMilliseconds,
        unplannedFullDowntimeMilliseconds:unplannedFullDowntimeMilliseconds,
        operatingExposureDurationMilliseconds:operatingExposureDurationMilliseconds,
        exactRepairDurationMilliseconds:exactRepairDurationMilliseconds,exactRestorationDurationMilliseconds:exactRestorationDurationMilliseconds,
        qualifyingFailureStartEventIDs:qualifyingFailureStartEventIDs,completedRepairCount:completedRepairCount,
        availabilityQualification:availabilityQualification,mtbfQualification:mtbfQualification,mttrQualification:mttrQualification,
        includedSourceEventIDs:includedSourceEventIDs,excludedSources:excludedSources,
        intervalUnionPolicySHA256:intervalUnionPolicySHA256,sourceClosureSHA256:sourceClosureSHA256)}
    private struct Basis:Codable{let schemaVersion:Int;let workspaceID:WorkspaceID;let subject:ServiceReliabilitySubjectV1
        let observationWindow:ServiceReliabilityClosedIntervalV1;let asOf:ServiceReliabilityInstantV1
        let exposure,downtime,operatingExposure:[NormalizedServiceIntervalV1]
        let maximalDowntimeComponents:[MaximalDowntimeComponentV1]
        let qualifiedRepairIntervals,qualifiedRestorationIntervals:[ServiceReliabilityClosedIntervalV1]
        let exposureDurationMilliseconds,unplannedFullDowntimeMilliseconds,operatingExposureDurationMilliseconds:UInt64
        let exactRepairDurationMilliseconds,exactRestorationDurationMilliseconds:UInt64
        let qualifyingFailureStartEventIDs:[UUID];let completedRepairCount:Int
        let availabilityQualification,mtbfQualification,mttrQualification:ServiceReliabilityQualificationV1
        let includedSourceEventIDs:[UUID];let excludedSources:[ServiceReliabilityExcludedSourceV1]
        let intervalUnionPolicySHA256,sourceClosureSHA256:String}
}

enum ServiceReliabilityIntervalAlgebraV1 {
    static let policyID="SERVICE_RELIABILITY_HALF_OPEN_UNION_SUBTRACT_V1"
    static var policySHA256:String{get throws{try ServiceReliabilityCanonicalCodecV1.sha256(policyID)}}

    static func union(_ values:[NormalizedServiceIntervalV1])throws->[NormalizedServiceIntervalV1]{
        guard values.count<=ServiceReliabilityLimitsV1.maximumIntervals else{throw ServiceReliabilityFailureV1.invalidValue}
        let ordered=values.sorted();var output:[NormalizedServiceIntervalV1]=[]
        for value in ordered{try value.validate();guard let last=output.last else{output.append(value);continue}
            if value.interval.lowerBound<=last.interval.upperBound{output.removeLast();let merged=try ServiceReliabilityClosedIntervalV1(
                lowerBound:last.interval.lowerBound,upperBound:max(last.interval.upperBound,value.interval.upperBound))
                output.append(try .init(interval:merged,sourceEventIDs:Array(Set(last.sourceEventIDs+value.sourceEventIDs))))
            }else{output.append(value)}}
        return output
    }

    static func subtract(_ minuends:[NormalizedServiceIntervalV1],_ subtrahends:[NormalizedServiceIntervalV1])throws->[NormalizedServiceIntervalV1]{
        let cuts=try union(subtrahends);var result:[NormalizedServiceIntervalV1]=[]
        for source in try union(minuends){var fragments=[source.interval]
            for cut in cuts{var next:[ServiceReliabilityClosedIntervalV1]=[];for fragment in fragments{
                guard let overlap=try fragment.intersection(cut.interval)else{next.append(fragment);continue}
                if fragment.lowerBound<overlap.lowerBound{next.append(try .init(lowerBound:fragment.lowerBound,upperBound:overlap.lowerBound))}
                if overlap.upperBound<fragment.upperBound{next.append(try .init(lowerBound:overlap.upperBound,upperBound:fragment.upperBound))}}
                fragments=next};result += try fragments.map{try .init(interval:$0,sourceEventIDs:source.sourceEventIDs)}}
        return result.sorted()
    }
}

enum ServiceReliabilityProjectionEngineV1 {
    static func project(workspaceID:WorkspaceID,subject:ServiceReliabilitySubjectV1,
        observationWindow:ServiceReliabilityClosedIntervalV1,asOf:ServiceReliabilityInstantV1,
        exposures:[QualifiedServiceExposureV1],segments:[ServiceImpactSegmentV1],
        repairs:[ServiceRepairIntervalV1],restorations:[ServiceRestorationAssertionV1])throws->ReliabilityMetricInputProjectionV1{
        try subject.validate();try observationWindow.validate()
        guard exposures.count<=ServiceReliabilityLimitsV1.maximumIntervals,
              segments.count<=ServiceReliabilityLimitsV1.maximumIntervals,
              repairs.count<=ServiceReliabilityLimitsV1.maximumIntervals,
              restorations.count<=ServiceReliabilityLimitsV1.maximumIntervals,
              exposures.allSatisfy({$0.workspaceID==workspaceID&&$0.subject==subject}),
              segments.allSatisfy({$0.workspaceID==workspaceID&&$0.subject==subject}),
              repairs.allSatisfy({$0.workspaceID==workspaceID&&$0.subject==subject}),
              restorations.allSatisfy({$0.workspaceID==workspaceID&&$0.subject==subject})else{throw ServiceReliabilityFailureV1.wrongWorkspace}
        try exposures.forEach{$0.validate()};try segments.forEach{$0.validate()};try repairs.forEach{$0.validate()};try restorations.forEach{$0.validate()}
        let activeExposures=try activeExposureEvents(exposures),activeSegments=try activeSegmentEvents(segments)
        let activeRepairs=try activeRepairEvents(repairs),activeRestorations=try activeRestorationEvents(restorations)
        let exposureOrdered=activeExposures.sorted{$0.interval<$1.interval}
        var excluded:[ServiceReliabilityExcludedSourceV1]=[]
        for pair in zip(exposureOrdered,exposureOrdered.dropFirst()) where pair.0.interval.upperBound>pair.1.interval.lowerBound{
            excluded.append(.init(sourceEventID:pair.0.eventID,reason:.unresolvedOverlap))
            excluded.append(.init(sourceEventID:pair.1.eventID,reason:.unresolvedOverlap))
        }
        for index in activeSegments.indices{for otherIndex in activeSegments.indices where otherIndex>index{
            let lhs=activeSegments[index],rhs=activeSegments[otherIndex]
            guard let lhsInterval=lhs.interval,let rhsInterval=rhs.interval,
                  lhsInterval.lowerBound<rhsInterval.upperBound,rhsInterval.lowerBound<lhsInterval.upperBound,
                  (lhs.impact != rhs.impact || lhs.origin != rhs.origin)else{continue}
            excluded.append(.init(sourceEventID:lhs.eventID,reason:.unresolvedOverlap))
            excluded.append(.init(sourceEventID:rhs.eventID,reason:.unresolvedOverlap))
        }}
        if let bad=exposureOrdered.first(where:{$0.coverage != .complete}){
            excluded.append(.init(sourceEventID:bad.eventID,reason:.incompleteCoverage))
        }
        var e:[NormalizedServiceIntervalV1]=[]
        for exposure in exposureOrdered{guard let clipped=try exposure.interval.intersection(observationWindow)else{continue}
            var pieces=[try NormalizedServiceIntervalV1(interval:clipped,sourceEventIDs:[exposure.eventID])]
            let exclusions=try exposure.plannedNonserviceExclusions.compactMap{try $0.intersection(observationWindow)}
                .map{try NormalizedServiceIntervalV1(interval:$0,sourceEventIDs:[exposure.eventID])}
            pieces=try ServiceReliabilityIntervalAlgebraV1.subtract(pieces,exclusions);e += pieces}
        e=try ServiceReliabilityIntervalAlgebraV1.union(e)
        var dInputs:[NormalizedServiceIntervalV1]=[];var included=Set(e.flatMap(\.sourceEventIDs))
        for segment in activeSegments{guard let interval=segment.interval else{
                excluded.append(.init(sourceEventID:segment.eventID,reason:.openDowntime));continue
            }
            guard let clipped=try interval.intersection(observationWindow),
                  e.contains(where:{$0.interval.lowerBound<clipped.upperBound&&clipped.lowerBound<$0.interval.upperBound})
            else{continue}
            switch (segment.impact,segment.origin,segment.certainty){
            case (.unknown,_,_):excluded.append(.init(sourceEventID:segment.eventID,reason:.unknownImpact))
            case (_,.unknown,_):excluded.append(.init(sourceEventID:segment.eventID,reason:.unknownOrigin))
            case (.fullInterruption,.planned,.exact):excluded.append(.init(sourceEventID:segment.eventID,reason:.plannedOverlap))
            case (.fullInterruption,.unplanned,.exact):
                for exposurePiece in e{if let intersection=try clipped.intersection(exposurePiece.interval){
                    dInputs.append(try .init(interval:intersection,sourceEventIDs:[segment.eventID]));included.insert(segment.eventID)}}
            case (_,_,.estimated),(_,_,.unknown):excluded.append(.init(sourceEventID:segment.eventID,reason:.uncertainInterval))
            default:included.insert(segment.eventID)
            }}
        let d=try ServiceReliabilityIntervalAlgebraV1.union(dInputs),o=try ServiceReliabilityIntervalAlgebraV1.subtract(e,d)
        var components:[MaximalDowntimeComponentV1]=[]
        for value in d{let contributing=activeSegments.filter{value.sourceEventIDs.contains($0.eventID)}
            let candidates=contributing.filter{$0.transitionIntoImpactEventID != nil&&$0.interval?.lowerBound==value.interval.lowerBound}
            let transition=candidates.count==1 ? candidates[0].transitionIntoImpactEventID:nil
            components.append(try .init(interval:value.interval,incidentIDs:Array(Set(contributing.map(\.incidentID))),
                segmentEventIDs:value.sourceEventIDs,qualifyingFailureStartEventID:transition))}
        let repairInputs=try activeRepairs.compactMap{repair -> NormalizedServiceIntervalV1? in
            guard repair.completed,repair.certainty == .exact,let interval=repair.interval,
                  let clipped=try interval.intersection(observationWindow)else{return nil}
            return try .init(interval:clipped,sourceEventIDs:[repair.eventID])
        }
        let repairIntervals=try ServiceReliabilityIntervalAlgebraV1.union(repairInputs).map(\.interval)
        let restorationByIncident=Dictionary(grouping:activeRestorations.filter{$0.certainty == .exact&&$0.restoredAt != nil},by:\.incidentID)
        var restorationInputs:[NormalizedServiceIntervalV1]=[]
        for segment in activeSegments where segment.impact == .fullInterruption{guard let start=segment.interval?.lowerBound,
            let restoration=restorationByIncident[segment.incidentID]?.sorted(by:{$0.revision<$1.revision}).last,
            let restored=restoration.restoredAt,start<restored,
            let clipped=try ServiceReliabilityClosedIntervalV1(lowerBound:start,upperBound:restored).intersection(observationWindow)
            else{continue}
            restorationInputs.append(try .init(interval:clipped,sourceEventIDs:[segment.eventID,restoration.eventID]))}
        let restorationIntervals=try ServiceReliabilityIntervalAlgebraV1.union(restorationInputs).map(\.interval)
        let eDuration=try e.reduce(UInt64(0)){try ServiceReliabilityLimitsV1.add($0,$1.interval.durationMilliseconds)}
        let dDuration=try d.reduce(UInt64(0)){try ServiceReliabilityLimitsV1.add($0,$1.interval.durationMilliseconds)}
        let oDuration=try o.reduce(UInt64(0)){try ServiceReliabilityLimitsV1.add($0,$1.interval.durationMilliseconds)}
        let starts=components.compactMap(\.qualifyingFailureStartEventID)
        excluded=Array(Set(excluded)).sorted()
        let availability:ServiceReliabilityQualificationV1=excluded.isEmpty
            ? (eDuration==0 ? .unavailable(.zeroQualifiedExposure):.qualified)
            : .unavailable(excluded[0].reason)
        let mtbf:ServiceReliabilityQualificationV1
        if availability != .qualified{mtbf=availability}else if oDuration==0{mtbf = .unavailable(.zeroQualifiedOperatingExposure)
        }else if components.contains(where:{$0.qualifyingFailureStartEventID==nil}){mtbf = .unavailable(.missingTransitionIdentity)
        }else if starts.isEmpty{mtbf = .unavailable(.noQualifyingFailureStarts)}else{mtbf = .qualified}
        let mttr:ServiceReliabilityQualificationV1=repairIntervals.isEmpty ? .unavailable(.noCompletedExactRepairs):.qualified
        let sourceClosure=try ServiceReliabilityCanonicalCodecV1.sha256(Source(
            exposures:exposures.sorted{($0.eventID.uuidString,$0.revision)<($1.eventID.uuidString,$1.revision)},
            segments:segments.sorted{($0.eventID.uuidString,$0.revision)<($1.eventID.uuidString,$1.revision)},
            repairs:repairs.sorted{($0.eventID.uuidString,$0.revision)<($1.eventID.uuidString,$1.revision)},
            restorations:restorations.sorted{($0.eventID.uuidString,$0.revision)<($1.eventID.uuidString,$1.revision)}))
        return try .init(workspaceID:workspaceID,subject:subject,observationWindow:observationWindow,asOf:asOf,
            exposure:e,downtime:d,operatingExposure:o,maximalDowntimeComponents:components,
            qualifiedRepairIntervals:repairIntervals,qualifiedRestorationIntervals:restorationIntervals.sorted(),
            exposureDurationMilliseconds:eDuration,unplannedFullDowntimeMilliseconds:dDuration,
            operatingExposureDurationMilliseconds:oDuration,
            exactRepairDurationMilliseconds:try repairIntervals.reduce(0){try ServiceReliabilityLimitsV1.add($0,$1.durationMilliseconds)},
            exactRestorationDurationMilliseconds:try restorationIntervals.reduce(0){try ServiceReliabilityLimitsV1.add($0,$1.durationMilliseconds)},
            qualifyingFailureStartEventIDs:starts,completedRepairCount:repairIntervals.count,
            availabilityQualification:availability,mtbfQualification:mtbf,mttrQualification:mttr,
            includedSourceEventIDs:Array(included),excludedSources:excluded,
            intervalUnionPolicySHA256:try ServiceReliabilityIntervalAlgebraV1.policySHA256,sourceClosureSHA256:sourceClosure)
    }
    private static func activeExposureEvents(_ values:[QualifiedServiceExposureV1])throws->[QualifiedServiceExposureV1]{
        try Dictionary(grouping:values,by:\.exposureID).values.map{chain in
            let ordered=chain.sorted{$0.revision<$1.revision};guard ordered.first?.revision==1 else{throw ServiceReliabilityFailureV1.invalidHistory}
            for pair in zip(ordered,ordered.dropFirst()){try pair.1.validateSuccessor(of:pair.0)}
            guard let latest=ordered.last else{throw ServiceReliabilityFailureV1.invalidHistory};return latest
        }.sorted{$0.exposureID.uuidString<$1.exposureID.uuidString}
    }
    private static func activeSegmentEvents(_ values:[ServiceImpactSegmentV1])throws->[ServiceImpactSegmentV1]{
        try Dictionary(grouping:values,by:\.segmentID).values.map{chain in
            let ordered=chain.sorted{$0.revision<$1.revision};guard ordered.first?.revision==1 else{throw ServiceReliabilityFailureV1.invalidHistory}
            for pair in zip(ordered,ordered.dropFirst()){try pair.1.validateSuccessor(of:pair.0)}
            guard let latest=ordered.last else{throw ServiceReliabilityFailureV1.invalidHistory};return latest
        }.sorted{$0.segmentID.uuidString<$1.segmentID.uuidString}
    }
    private static func activeRepairEvents(_ values:[ServiceRepairIntervalV1])throws->[ServiceRepairIntervalV1]{
        try Dictionary(grouping:values,by:\.repairID).values.map{chain in
            let ordered=chain.sorted{$0.revision<$1.revision};guard ordered.first?.revision==1 else{throw ServiceReliabilityFailureV1.invalidHistory}
            for pair in zip(ordered,ordered.dropFirst()){try pair.1.validateSuccessor(of:pair.0)}
            guard let latest=ordered.last else{throw ServiceReliabilityFailureV1.invalidHistory};return latest
        }.sorted{$0.repairID.uuidString<$1.repairID.uuidString}
    }
    private static func activeRestorationEvents(_ values:[ServiceRestorationAssertionV1])throws->[ServiceRestorationAssertionV1]{
        try Dictionary(grouping:values,by:\.assertionID).values.map{chain in
            let ordered=chain.sorted{$0.revision<$1.revision};guard ordered.first?.revision==1 else{throw ServiceReliabilityFailureV1.invalidHistory}
            for pair in zip(ordered,ordered.dropFirst()){try pair.1.validateSuccessor(of:pair.0)}
            guard let latest=ordered.last else{throw ServiceReliabilityFailureV1.invalidHistory};return latest
        }.sorted{$0.assertionID.uuidString<$1.assertionID.uuidString}
    }
    private struct Source:Codable{let exposures:[QualifiedServiceExposureV1];let segments:[ServiceImpactSegmentV1]
        let repairs:[ServiceRepairIntervalV1];let restorations:[ServiceRestorationAssertionV1]}
}

enum ServiceReliabilityMutationPayloadV1:Codable,Equatable,Sendable{
    case incident(AssetServiceIncidentV1);case impact(ServiceImpactSegmentV1);case cause(ServiceCauseAssertionV1)
    case remedy(ServiceRemedyAssertionV1);case repair(ServiceRepairIntervalV1)
    case restoration(ServiceRestorationAssertionV1);case exposure(QualifiedServiceExposureV1)
}

struct ServiceReliabilityAtomicBundleV1:Codable,Equatable,Sendable,ServiceReliabilityCanonicalValidatingV1{
    static let schemaVersion=1;let schemaVersion:Int;let workspaceID:WorkspaceID;let expectedRevision:WorkspaceExpectedRevisionV1
    let mutationID:MutationIDV1;let payloads:[ServiceReliabilityMutationPayloadV1];let bundleSHA256:String
    init(workspaceID:WorkspaceID,expectedRevision:WorkspaceExpectedRevisionV1,mutationID:MutationIDV1,
         payloads:[ServiceReliabilityMutationPayloadV1])throws{schemaVersion=Self.schemaVersion;self.workspaceID=workspaceID
        self.expectedRevision=expectedRevision;self.mutationID=mutationID;self.payloads=payloads
        bundleSHA256=try ServiceReliabilityCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,workspaceID:workspaceID,
            expectedRevision:expectedRevision,mutationID:mutationID,payloads:payloads));try validate()}
    func validate()throws{guard schemaVersion==Self.schemaVersion,expectedRevision.workspaceID==workspaceID,
        !payloads.isEmpty,payloads.count<=ServiceReliabilityLimitsV1.maximumBundleEvents else{throw ServiceReliabilityFailureV1.invalidValue}
        for payload in payloads{let scope:(WorkspaceID,MutationIDV1);switch payload{
            case .incident(let v):try v.validate();scope=(v.workspaceID,v.mutationID)
            case .impact(let v):try v.validate();scope=(v.workspaceID,v.mutationID)
            case .cause(let v):try v.validate();scope=(v.workspaceID,v.mutationID)
            case .remedy(let v):try v.validate();scope=(v.workspaceID,v.mutationID)
            case .repair(let v):try v.validate();scope=(v.workspaceID,v.mutationID)
            case .restoration(let v):try v.validate();scope=(v.workspaceID,v.mutationID)
            case .exposure(let v):try v.validate();scope=(v.workspaceID,v.mutationID)}
            guard scope.0==workspaceID,scope.1==mutationID else{throw ServiceReliabilityFailureV1.wrongWorkspace}}
        try ServiceReliabilityLimitsV1.digest(bundleSHA256);guard bundleSHA256==(try ServiceReliabilityCanonicalCodecV1.sha256(basis))
        else{throw ServiceReliabilityFailureV1.invalidValue}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,workspaceID:workspaceID,expectedRevision:expectedRevision,
        mutationID:mutationID,payloads:payloads)}
    private struct Basis:Codable{let schemaVersion:Int;let workspaceID:WorkspaceID;let expectedRevision:WorkspaceExpectedRevisionV1
        let mutationID:MutationIDV1;let payloads:[ServiceReliabilityMutationPayloadV1]}
}

struct ServiceReliabilityWriterReceiptV1:Codable,Equatable,Sendable,ServiceReliabilityCanonicalValidatingV1{
    let receiptID:UUID;let workspaceID:WorkspaceID;let mutationID:MutationIDV1;let bundleSHA256:String
    let canonicalMutationReceiptSHA256:String;let committedAt:Date;let receiptSHA256:String
    init(receiptID:UUID,bundle:ServiceReliabilityAtomicBundleV1,canonicalMutationReceiptSHA256:String,committedAt:Date)throws{
        self.receiptID=receiptID;workspaceID=bundle.workspaceID;mutationID=bundle.mutationID;bundleSHA256=bundle.bundleSHA256
        self.canonicalMutationReceiptSHA256=canonicalMutationReceiptSHA256;self.committedAt=committedAt
        receiptSHA256=try ServiceReliabilityCanonicalCodecV1.sha256(Basis(receiptID:receiptID,workspaceID:bundle.workspaceID,
            mutationID:bundle.mutationID,bundleSHA256:bundle.bundleSHA256,
            canonicalMutationReceiptSHA256:canonicalMutationReceiptSHA256,committedAt:committedAt));try validate()}
    func validate()throws{try ServiceReliabilityLimitsV1.id(receiptID);try [bundleSHA256,canonicalMutationReceiptSHA256,receiptSHA256]
        .forEach(ServiceReliabilityLimitsV1.digest);_ = try ServiceReliabilityInstantV1(committedAt)
        guard committedAt.timeIntervalSinceReferenceDate.isFinite,
        receiptSHA256==(try ServiceReliabilityCanonicalCodecV1.sha256(basis))else{throw ServiceReliabilityFailureV1.invalidValue}}
    private var basis:Basis{.init(receiptID:receiptID,workspaceID:workspaceID,mutationID:mutationID,bundleSHA256:bundleSHA256,
        canonicalMutationReceiptSHA256:canonicalMutationReceiptSHA256,committedAt:committedAt)}
    private struct Basis:Codable{let receiptID:UUID;let workspaceID:WorkspaceID;let mutationID:MutationIDV1
        let bundleSHA256,canonicalMutationReceiptSHA256:String;let committedAt:Date}
}

enum ServiceReliabilityClaimBoundaryV1 {
    static let sourceTruthIsActorRecordedOperationalImpact = true
    static let assignsNoDegradationWeight = true
    static let restorationImpliesSafety = false
    static let restorationImpliesCompliance = false
    static let restorationImpliesVerification = false
    static let restorationGrantsNoIndependentOperationalAuthority = true
    static let acceptsNoAutomaticExternalConditionFeed = true
    static let makesNoAutomatedFutureConditionClaim = true
    static let makesNoBusinessCommitmentClaim = true
    static let automaticallyConfirmsCause = false
}

enum ServiceReliabilityFJ09ContractV1 {
    static let requiresVisibleQualifiedExposureAuthoring = true
    static let requiresExplicitUnavailableDisposition = true
    static let canonicalDecodeRequiresExactByteParity = true
    static let atomicCommitUsesExistingWorkspaceMutationRoute = true
}

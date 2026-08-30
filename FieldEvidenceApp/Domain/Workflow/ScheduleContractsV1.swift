import Foundation

enum ScheduleFailureV1: Error, Equatable, Sendable {
    case invalidValue, invalidDigest, invalidSuccessor, wrongWorkspace
    case ambiguousLocalTime, nonexistentLocalTime, limitExceeded
    case divergentReplay, staleBasis, invalidTransition, duplicateWorkLink
    case manualResolutionRequired
}

enum ScheduleClockDispositionV1: String, Codable, Hashable, Sendable {
    case forwardOrEqual = "FORWARD_OR_EQUAL"
    case rollbackDetected = "ROLLBACK_DETECTED"
}

struct ScheduleProjectionEvaluationV1: Codable, Equatable, Sendable {
    let evaluatedAt: Date
    let priorEvaluationAt: Date?
    let disposition: ScheduleClockDispositionV1
    init(evaluatedAt: Date, priorEvaluationAt: Date?) throws {
        try ScheduleLimitsV1.instant(evaluatedAt)
        if let priorEvaluationAt { try ScheduleLimitsV1.instant(priorEvaluationAt) }
        self.evaluatedAt = evaluatedAt
        self.priorEvaluationAt = priorEvaluationAt
        disposition = priorEvaluationAt.map { evaluatedAt < $0 ? .rollbackDetected : .forwardOrEqual } ?? .forwardOrEqual
    }
    var permitsReminderReconciliation: Bool { disposition == .forwardOrEqual }
}

enum ScheduleLimitsV1 {
    static let maximumCanonicalBytes = 1_048_576
    static let maximumGeneratedOccurrences = 512
    static let maximumHorizonDays = 732
    static let maximumCalendarDaySeconds = 93_600
    static let maximumTokenBytes = 255
    static let maximumInterval = 36_600
    static let maximumExceptionsPerOccurrence = 64
    static let allDaysCalendarBasisID = "ALL_DAYS_V1"
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    static func id(_ value: UUID) throws {
        guard value != zero else { throw ScheduleFailureV1.invalidValue }
    }
    static func revision(_ value: UInt64) throws {
        guard value > 0 else { throw ScheduleFailureV1.invalidValue }
    }
    static func digest(_ value: String) throws {
        guard KernelCanonicalHashV1.validSHA256(value) else { throw ScheduleFailureV1.invalidDigest }
    }
    static func instant(_ value: Date) throws {
        guard value.timeIntervalSinceReferenceDate.isFinite else { throw ScheduleFailureV1.invalidValue }
    }
    static func token(_ value: String) throws {
        guard !value.isEmpty, value.utf8.count <= maximumTokenBytes,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw ScheduleFailureV1.invalidValue
        }
    }
}

private protocol ScheduleCanonicalIntrinsicValidatingV1 {
    func validateCanonicalValue() throws
}

enum ScheduleCalendarIdentifierV1: String, Codable, CaseIterable, Hashable, Sendable {
    case gregorianV1 = "GREGORIAN_V1"
}
enum AmbiguousLocalTimePolicyV1: String, Codable, CaseIterable, Hashable, Sendable {
    case earlierOffset = "EARLIER_OFFSET"
    case laterOffset = "LATER_OFFSET"
}
enum NonexistentLocalTimePolicyV1: String, Codable, CaseIterable, Hashable, Sendable {
    case shiftForwardByGap = "SHIFT_FORWARD_BY_GAP"
    case skipOccurrence = "SKIP_OCCURRENCE"
}

struct FrozenScheduleTimeBasisV1: Codable, Equatable, Hashable, Sendable {
    let calendar: ScheduleCalendarIdentifierV1
    let ianaTimeZoneIdentifier: String
    let timeZoneRuleSetVersion: String
    let timeZoneRuleSetSHA256: String
    let ambiguousTimePolicy: AmbiguousLocalTimePolicyV1
    let nonexistentTimePolicy: NonexistentLocalTimePolicyV1
    let calendarBasisID: String
    let calendarBasisRevision: UInt64
    let calendarBasisSHA256: String

    init(calendar: ScheduleCalendarIdentifierV1 = .gregorianV1,
         ianaTimeZoneIdentifier: String, timeZoneRuleSetVersion: String,
         timeZoneRuleSetSHA256: String,
         ambiguousTimePolicy: AmbiguousLocalTimePolicyV1,
         nonexistentTimePolicy: NonexistentLocalTimePolicyV1,
         calendarBasisID: String = ScheduleLimitsV1.allDaysCalendarBasisID,
         calendarBasisRevision: UInt64 = 1,
         calendarBasisSHA256: String) throws {
        self.calendar = calendar; self.ianaTimeZoneIdentifier = ianaTimeZoneIdentifier
        self.timeZoneRuleSetVersion = timeZoneRuleSetVersion
        self.timeZoneRuleSetSHA256 = timeZoneRuleSetSHA256
        self.ambiguousTimePolicy = ambiguousTimePolicy
        self.nonexistentTimePolicy = nonexistentTimePolicy
        self.calendarBasisID = calendarBasisID
        self.calendarBasisRevision = calendarBasisRevision
        self.calendarBasisSHA256 = calendarBasisSHA256
        try validate()
    }

    func validate() throws {
        try ScheduleLimitsV1.token(ianaTimeZoneIdentifier)
        try ScheduleLimitsV1.token(timeZoneRuleSetVersion)
        try ScheduleLimitsV1.digest(timeZoneRuleSetSHA256)
        try ScheduleLimitsV1.token(calendarBasisID)
        try ScheduleLimitsV1.revision(calendarBasisRevision)
        try ScheduleLimitsV1.digest(calendarBasisSHA256)
        guard calendar == .gregorianV1 else { throw ScheduleFailureV1.invalidValue }
    }
    func canonicalSHA256() throws -> String {
        try validate()
        return try ScheduleCanonicalCodecV1.sha256(self)
    }
}

struct ScheduleLocalAnchorV1: Codable, Equatable, Hashable, Comparable, Sendable {
    let year: Int?; let month: Int?; let day: Int?
    let weekday: Int?; let weekdayOrdinal: Int?
    let hour: Int; let minute: Int; let second: Int
    var stableKey: String { "\(year ?? 0)|\(month ?? 0)|\(day ?? 0)|\(weekday ?? 0)|\(weekdayOrdinal ?? 0)|\(hour)|\(minute)|\(second)" }
    func validate() throws {
        guard year.map({ 1...9_999 ~= $0 }) ?? true,
              month.map({ 1...12 ~= $0 }) ?? true,
              day.map({ 1...31 ~= $0 }) ?? true,
              weekday.map({ 1...7 ~= $0 }) ?? true,
              weekdayOrdinal.map({ (-5 ... -1).contains($0) || (1...5).contains($0) }) ?? true,
              (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else {
            throw ScheduleFailureV1.invalidValue
        }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableKey < rhs.stableKey }
}

enum FixedCalendarCadenceV1: String, Codable, CaseIterable, Hashable, Sendable {
    case daily = "DAILY", weekly = "WEEKLY", monthlyDay = "MONTHLY_DAY"
    case monthlyWeekday = "MONTHLY_WEEKDAY", yearly = "YEARLY"
}
struct FixedCalendarScheduleRuleV1: Codable, Equatable, Hashable, Sendable {
    let cadence: FixedCalendarCadenceV1; let interval: Int; let anchor: ScheduleLocalAnchorV1
    func validate() throws {
        try anchor.validate()
        guard (1...ScheduleLimitsV1.maximumInterval).contains(interval) else { throw ScheduleFailureV1.invalidValue }
        switch cadence {
        case .daily: guard anchor.weekday == nil, anchor.weekdayOrdinal == nil else { throw ScheduleFailureV1.invalidValue }
        case .weekly: guard anchor.weekday != nil, anchor.weekdayOrdinal == nil else { throw ScheduleFailureV1.invalidValue }
        case .monthlyDay: guard anchor.day != nil, anchor.weekday == nil, anchor.weekdayOrdinal == nil else { throw ScheduleFailureV1.invalidValue }
        case .monthlyWeekday: guard anchor.weekday != nil, anchor.weekdayOrdinal != nil else { throw ScheduleFailureV1.invalidValue }
        case .yearly: guard anchor.month != nil, anchor.day != nil else { throw ScheduleFailureV1.invalidValue }
        }
    }
}
enum CompletionRelativeUnitV1: String, Codable, CaseIterable, Hashable, Sendable {
    case elapsedHours = "ELAPSED_HOURS", calendarDays = "CALENDAR_DAYS", calendarWeeks = "CALENDAR_WEEKS"
}
struct CompletionRelativeScheduleRuleV1: Codable, Equatable, Hashable, Sendable {
    let interval: Int; let unit: CompletionRelativeUnitV1; let firstAnchor: ScheduleLocalAnchorV1
    func validate() throws { try firstAnchor.validate(); guard (1...ScheduleLimitsV1.maximumInterval).contains(interval) else { throw ScheduleFailureV1.invalidValue } }
}
enum ScheduleRecurrenceV1: Codable, Equatable, Hashable, Sendable {
    case fixedCalendar(FixedCalendarScheduleRuleV1)
    case completionRelative(CompletionRelativeScheduleRuleV1)
    case advanced(AdvancedScheduleConfigurationV1)
    func validate() throws { switch self { case .fixedCalendar(let value): try value.validate(); case .completionRelative(let value): try value.validate(); case .advanced(let value): try value.validate() } }
}

enum ScheduledWorkKindV1: String, Codable, CaseIterable, Hashable, Sendable {
    case workPacket = "WORK_PACKET", roundSession = "ROUND_SESSION"
}
struct ScheduledWorkDefinitionReferenceV1: Codable, Equatable, Hashable, Sendable {
    let kind: ScheduledWorkKindV1; let definitionWorkspaceID: WorkspaceID
    let definitionRelease: SurveyDefinitionReleaseReferenceV1
    let packageReleaseID: String; let packageID: String; let packageContentVersion: Int
    let packageSHA256: String; let workflowSHA256: String
    init(kind:ScheduledWorkKindV1,definition:SurveyDefinitionReleaseV1,packageRelease:InspectionPackageReleaseV1)throws{try definition.validate();try packageRelease.validate();guard definition.ownerPackageID==packageRelease.packageID,packageRelease.state == .published else{throw ScheduleFailureV1.invalidValue};self.kind=kind;definitionWorkspaceID=definition.workspaceID;definitionRelease=try .init(definition);packageReleaseID=packageRelease.packageReleaseID;packageID=packageRelease.packageID;packageContentVersion=packageRelease.packageContentVersion;packageSHA256=packageRelease.packageSHA256;workflowSHA256=packageRelease.workflowSHA256;try validate()}
    func validate() throws {
        try definitionRelease.validate(); try ScheduleLimitsV1.token(packageReleaseID); try ScheduleLimitsV1.token(packageID)
        try ScheduleLimitsV1.digest(packageSHA256); try ScheduleLimitsV1.digest(workflowSHA256)
        guard packageContentVersion > 0 else { throw ScheduleFailureV1.invalidValue }
    }
}

enum ScheduleReleaseActionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case create = "CREATE", edit = "EDIT", pause = "PAUSE", resume = "RESUME"
    case end = "END", retireAndReplace = "RETIRE_AND_REPLACE"
}
enum ScheduleLifecycleStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case active = "ACTIVE", paused = "PAUSED", ended = "ENDED", retired = "RETIRED"
}
struct ScheduleDefinitionReleaseReferenceV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID; let scheduleDefinitionID: UUID; let releaseID: UUID
    let occurrenceIdentityNamespaceID: UUID; let revision: UInt64
    let releaseSHA256: String; let timeBasisSHA256: String
    init(_ value: ScheduleDefinitionReleaseV1) throws { try value.validate();workspaceID=value.workspaceID;scheduleDefinitionID=value.scheduleDefinitionID;releaseID=value.releaseID;occurrenceIdentityNamespaceID=value.occurrenceIdentityNamespaceID;revision=value.revision;releaseSHA256=value.releaseSHA256;timeBasisSHA256=try value.timeBasis.canonicalSHA256() }
    func validate() throws { try ScheduleLimitsV1.id(scheduleDefinitionID);try ScheduleLimitsV1.id(releaseID);try ScheduleLimitsV1.id(occurrenceIdentityNamespaceID);try ScheduleLimitsV1.revision(revision);try ScheduleLimitsV1.digest(releaseSHA256);try ScheduleLimitsV1.digest(timeBasisSHA256) }
}

struct ScheduleDefinitionReleaseV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let scheduleDefinitionID: UUID; let releaseID: UUID; let workspaceID: WorkspaceID
    let occurrenceIdentityNamespaceID: UUID; let action: ScheduleReleaseActionV1; let lifecycleState: ScheduleLifecycleStateV1
    let recurrence: ScheduleRecurrenceV1; let timeBasis: FrozenScheduleTimeBasisV1
    let startsAtUTC: Date; let endsAtUTC: Date?; let generationHorizonDays: Int; let maximumGeneratedOccurrences: Int
    let readyLeadSeconds: Int64; let overdueGraceSeconds: Int64
    let subject: WorkSubjectReferenceV1; let workDefinition: ScheduledWorkDefinitionReferenceV1; let assignee: ActorSnapshotV1?
    let supersedesReleaseID: UUID?; let predecessorReleaseSHA256: String?; let revision: UInt64
    let mutationID: MutationIDV1; let authoredBy: ActorSnapshotV1; let authoredAt: Date; let releaseSHA256: String

    init(scheduleDefinitionID: UUID, releaseID: UUID, workspaceID: WorkspaceID,
         occurrenceIdentityNamespaceID: UUID, action: ScheduleReleaseActionV1,
         lifecycleState: ScheduleLifecycleStateV1, recurrence: ScheduleRecurrenceV1,
         timeBasis: FrozenScheduleTimeBasisV1, startsAtUTC: Date, endsAtUTC: Date? = nil,
         generationHorizonDays: Int, maximumGeneratedOccurrences: Int,
         readyLeadSeconds: Int64, overdueGraceSeconds: Int64,
         subject: WorkSubjectReferenceV1, workDefinition: ScheduledWorkDefinitionReferenceV1,
         assignee: ActorSnapshotV1? = nil, supersedesReleaseID: UUID? = nil,
         predecessorReleaseSHA256: String? = nil, revision: UInt64,
         mutationID: MutationIDV1, authoredBy: ActorSnapshotV1, authoredAt: Date) throws {
        schemaVersion=Self.schemaVersion;self.scheduleDefinitionID=scheduleDefinitionID;self.releaseID=releaseID;self.workspaceID=workspaceID
        self.occurrenceIdentityNamespaceID=occurrenceIdentityNamespaceID;self.action=action;self.lifecycleState=lifecycleState
        self.recurrence=recurrence;self.timeBasis=timeBasis;self.startsAtUTC=startsAtUTC;self.endsAtUTC=endsAtUTC
        self.generationHorizonDays=generationHorizonDays;self.maximumGeneratedOccurrences=maximumGeneratedOccurrences
        self.readyLeadSeconds=readyLeadSeconds;self.overdueGraceSeconds=overdueGraceSeconds;self.subject=subject
        self.workDefinition=workDefinition;self.assignee=assignee;self.supersedesReleaseID=supersedesReleaseID
        self.predecessorReleaseSHA256=predecessorReleaseSHA256;self.revision=revision;self.mutationID=mutationID
        self.authoredBy=authoredBy;self.authoredAt=authoredAt
        releaseSHA256 = try ScheduleCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,scheduleDefinitionID:scheduleDefinitionID,releaseID:releaseID,workspaceID:workspaceID,occurrenceIdentityNamespaceID:occurrenceIdentityNamespaceID,action:action,lifecycleState:lifecycleState,recurrence:recurrence,timeBasis:timeBasis,startsAtUTC:startsAtUTC,endsAtUTC:endsAtUTC,generationHorizonDays:generationHorizonDays,maximumGeneratedOccurrences:maximumGeneratedOccurrences,readyLeadSeconds:readyLeadSeconds,overdueGraceSeconds:overdueGraceSeconds,subject:subject,workDefinition:workDefinition,assignee:assignee,supersedesReleaseID:supersedesReleaseID,predecessorReleaseSHA256:predecessorReleaseSHA256,revision:revision,mutationID:mutationID,authoredBy:authoredBy,authoredAt:authoredAt))
        try validate()
    }
    func validate() throws {
        try ScheduleLimitsV1.id(scheduleDefinitionID);try ScheduleLimitsV1.id(releaseID);try ScheduleLimitsV1.id(occurrenceIdentityNamespaceID)
        try recurrence.validate();try timeBasis.validate();try ScheduleLimitsV1.instant(startsAtUTC);try endsAtUTC.map(ScheduleLimitsV1.instant)
        try subject.validate();try workDefinition.validate();try authoredBy.validate();try assignee?.validate();try ScheduleLimitsV1.instant(authoredAt)
        guard schemaVersion==Self.schemaVersion,(1...ScheduleLimitsV1.maximumHorizonDays).contains(generationHorizonDays),
              (1...ScheduleLimitsV1.maximumGeneratedOccurrences).contains(maximumGeneratedOccurrences),readyLeadSeconds>=0,overdueGraceSeconds>=0,readyLeadSeconds<=Int64(ScheduleLimitsV1.maximumHorizonDays*ScheduleLimitsV1.maximumCalendarDaySeconds),overdueGraceSeconds<=Int64(ScheduleLimitsV1.maximumHorizonDays*ScheduleLimitsV1.maximumCalendarDaySeconds),
              endsAtUTC.map({$0>=startsAtUTC}) ?? true,workDefinition.definitionWorkspaceID==workspaceID,authoredBy.workspaceID==workspaceID,assignee.map({$0.workspaceID==workspaceID&&$0.responsibility == .assignedTo}) ?? true,Self.validAdvancedCalendarBinding(recurrence,timeBasis,workspaceID),
              revision>0,(revision==1)==(supersedesReleaseID==nil&&predecessorReleaseSHA256==nil&&action == .create),
              supersedesReleaseID != releaseID,predecessorReleaseSHA256.map(KernelCanonicalHashV1.validSHA256) ?? true,
              Self.valid(action:action,state:lifecycleState),releaseSHA256==(try ScheduleCanonicalCodecV1.sha256(basis)) else { throw ScheduleFailureV1.invalidDigest }
    }
    func validateSuccessor(of old: Self) throws {
        try old.validate();try validate()
        guard old.revision<UInt64.max,revision==old.revision+1,scheduleDefinitionID==old.scheduleDefinitionID,
              workspaceID==old.workspaceID,supersedesReleaseID==old.releaseID,predecessorReleaseSHA256==old.releaseSHA256,
              releaseID != old.releaseID,mutationID != old.mutationID,Self.validTransition(old.lifecycleState,lifecycleState,action) else { throw ScheduleFailureV1.invalidSuccessor }
        let identityChanged = action == .retireAndReplace || Self.identityRecurrenceChanged(old.recurrence, recurrence) || Self.identityTimeBasisChanged(old.timeBasis,timeBasis,old.recurrence,recurrence) ||
            startsAtUTC != old.startsAtUTC || subject != old.subject ||
            workDefinition != old.workDefinition
        guard identityChanged == (occurrenceIdentityNamespaceID != old.occurrenceIdentityNamespaceID) else { throw ScheduleFailureV1.invalidSuccessor }
    }
    func rebound(to workspaceID:WorkspaceID,subject:WorkSubjectReferenceV1,workDefinition:ScheduledWorkDefinitionReferenceV1,authoredBy:ActorSnapshotV1,assignee:ActorSnapshotV1?)throws->Self{try .init(scheduleDefinitionID:scheduleDefinitionID,releaseID:releaseID,workspaceID:workspaceID,occurrenceIdentityNamespaceID:occurrenceIdentityNamespaceID,action:action,lifecycleState:lifecycleState,recurrence:recurrence,timeBasis:timeBasis,startsAtUTC:startsAtUTC,endsAtUTC:endsAtUTC,generationHorizonDays:generationHorizonDays,maximumGeneratedOccurrences:maximumGeneratedOccurrences,readyLeadSeconds:readyLeadSeconds,overdueGraceSeconds:overdueGraceSeconds,subject:subject,workDefinition:workDefinition,assignee:assignee,supersedesReleaseID:supersedesReleaseID,predecessorReleaseSHA256:predecessorReleaseSHA256,revision:revision,mutationID:mutationID,authoredBy:authoredBy,authoredAt:authoredAt)}
    private static func valid(action:ScheduleReleaseActionV1,state:ScheduleLifecycleStateV1)->Bool{switch action{case .create,.edit,.resume:return state == .active;case .pause:return state == .paused;case .end:return state == .ended;case .retireAndReplace:return state == .retired}}
    private static func identityRecurrenceChanged(_ old:ScheduleRecurrenceV1,_ new:ScheduleRecurrenceV1)->Bool{switch(old,new){case let(.advanced(lhs),.advanced(rhs)):return lhs.recurrence != rhs.recurrence;default:return old != new}}
    private static func identityTimeBasisChanged(_ old:FrozenScheduleTimeBasisV1,_ new:FrozenScheduleTimeBasisV1,_ oldRecurrence:ScheduleRecurrenceV1,_ newRecurrence:ScheduleRecurrenceV1)->Bool{if case .advanced=oldRecurrence,case .advanced=newRecurrence{return old.calendar != new.calendar||old.ianaTimeZoneIdentifier != new.ianaTimeZoneIdentifier||old.timeZoneRuleSetVersion != new.timeZoneRuleSetVersion||old.timeZoneRuleSetSHA256 != new.timeZoneRuleSetSHA256||old.ambiguousTimePolicy != new.ambiguousTimePolicy||old.nonexistentTimePolicy != new.nonexistentTimePolicy};return old != new}
    private static func validAdvancedCalendarBinding(_ recurrence:ScheduleRecurrenceV1,_ timeBasis:FrozenScheduleTimeBasisV1,_ workspaceID:WorkspaceID)->Bool{guard case .advanced(let configuration)=recurrence else{return true};let reference=configuration.calendarRelease;return reference.workspaceID==workspaceID&&timeBasis.calendarBasisID==reference.calendarID.uuidString.lowercased()&&timeBasis.calendarBasisRevision==reference.revision&&timeBasis.calendarBasisSHA256==reference.releaseSHA256}
    private static func validTransition(_ from:ScheduleLifecycleStateV1,_ to:ScheduleLifecycleStateV1,_ action:ScheduleReleaseActionV1)->Bool{switch(from,to,action){case(.active,.active,.edit),(.active,.paused,.pause),(.paused,.active,.resume),(.active,.ended,.end),(.paused,.ended,.end),(.active,.retired,.retireAndReplace),(.paused,.retired,.retireAndReplace),(.ended,.retired,.retireAndReplace):return true;default:return false}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,scheduleDefinitionID:scheduleDefinitionID,releaseID:releaseID,workspaceID:workspaceID,occurrenceIdentityNamespaceID:occurrenceIdentityNamespaceID,action:action,lifecycleState:lifecycleState,recurrence:recurrence,timeBasis:timeBasis,startsAtUTC:startsAtUTC,endsAtUTC:endsAtUTC,generationHorizonDays:generationHorizonDays,maximumGeneratedOccurrences:maximumGeneratedOccurrences,readyLeadSeconds:readyLeadSeconds,overdueGraceSeconds:overdueGraceSeconds,subject:subject,workDefinition:workDefinition,assignee:assignee,supersedesReleaseID:supersedesReleaseID,predecessorReleaseSHA256:predecessorReleaseSHA256,revision:revision,mutationID:mutationID,authoredBy:authoredBy,authoredAt:authoredAt)}
    private struct Basis:Codable{let schemaVersion:Int;let scheduleDefinitionID,releaseID:UUID;let workspaceID:WorkspaceID;let occurrenceIdentityNamespaceID:UUID;let action:ScheduleReleaseActionV1;let lifecycleState:ScheduleLifecycleStateV1;let recurrence:ScheduleRecurrenceV1;let timeBasis:FrozenScheduleTimeBasisV1;let startsAtUTC:Date;let endsAtUTC:Date?;let generationHorizonDays,maximumGeneratedOccurrences:Int;let readyLeadSeconds,overdueGraceSeconds:Int64;let subject:WorkSubjectReferenceV1;let workDefinition:ScheduledWorkDefinitionReferenceV1;let assignee:ActorSnapshotV1?;let supersedesReleaseID:UUID?;let predecessorReleaseSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1;let authoredBy:ActorSnapshotV1;let authoredAt:Date}
}

extension ScheduleDefinitionReleaseV1: ScheduleCanonicalIntrinsicValidatingV1 {
    fileprivate func validateCanonicalValue() throws { try validate() }
}

struct OccurrenceIDV1: RawRepresentable, Codable, Equatable, Hashable, Comparable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue=rawValue }
    init(scheduleDefinitionID:UUID,identityNamespaceID:UUID,nominalKey:String,predecessorOccurrenceID:OccurrenceIDV1?=nil,completionEventSHA256:String?=nil)throws{try ScheduleLimitsV1.id(scheduleDefinitionID);try ScheduleLimitsV1.id(identityNamespaceID);try ScheduleLimitsV1.token(nominalKey);if let completionEventSHA256{try ScheduleLimitsV1.digest(completionEventSHA256)};rawValue=try ScheduleCanonicalCodecV1.sha256(Basis(scheduleDefinitionID:scheduleDefinitionID,identityNamespaceID:identityNamespaceID,nominalKey:nominalKey,predecessorOccurrenceID:predecessorOccurrenceID,completionEventSHA256:completionEventSHA256));try validate()}
    func validate()throws{try ScheduleLimitsV1.digest(rawValue)}
    static func <(lhs:Self,rhs:Self)->Bool{lhs.rawValue<rhs.rawValue}
    private struct Basis:Codable{let scheduleDefinitionID:UUID;let identityNamespaceID:UUID;let nominalKey:String;let predecessorOccurrenceID:OccurrenceIDV1?;let completionEventSHA256:String?}
}

struct ResolvedOccurrenceBasisV1: Codable, Equatable, Hashable, Sendable {
    let nominalLocalDate: String; let nominalLocalTime: String; let resolvedAtUTC: Date?
    let utcOffsetSeconds: Int?; let disposition: LocalTimeDispositionV1
    let timeBasisSHA256: String; let adjustmentProvenanceSHA256: String?
    var nominalKey:String{"\(nominalLocalDate)T\(nominalLocalTime)"}
    func validate()throws{let maximum=TemporalContextV1.maximumAbsoluteUTCOffsetSeconds;guard ObservationAndTimeValidationV1.isISODate(nominalLocalDate),ObservationAndTimeValidationV1.isISOTime(nominalLocalTime),resolvedAtUTC.map({$0.timeIntervalSinceReferenceDate.isFinite}) ?? true,utcOffsetSeconds.map({$0 >= -maximum && $0 <= maximum}) ?? true,KernelCanonicalHashV1.validSHA256(timeBasisSHA256),adjustmentProvenanceSHA256.map(KernelCanonicalHashV1.validSHA256) ?? true,disposition != .unknown,(resolvedAtUTC != nil)==(utcOffsetSeconds != nil),(disposition != .nonexistentGap || resolvedAtUTC == nil || adjustmentProvenanceSHA256 != nil),(disposition == .nonexistentGap || resolvedAtUTC != nil) else{throw ScheduleFailureV1.invalidValue}}
}

enum ScheduleExceptionKindV1:String,Codable,CaseIterable,Hashable,Sendable{case deferred="DEFERRED",skipped="SKIPPED",cancelled="CANCELLED",missed="MISSED",basisAdjusted="BASIS_ADJUSTED",retiredForRuleChange="RETIRED_FOR_RULE_CHANGE"}
struct ScheduleExceptionV1:Codable,Equatable,Hashable,Sendable{let exceptionID:UUID;let kind:ScheduleExceptionKindV1;let priorEffectiveBasisSHA256:String;let replacementBasis:ResolvedOccurrenceBasisV1?;let replacementOccurrenceID:OccurrenceIDV1?;let reasonCode:String;let recordedBy:ActorSnapshotV1;let recordedAt:Date;let exceptionSHA256:String
    init(exceptionID:UUID,kind:ScheduleExceptionKindV1,priorEffectiveBasisSHA256:String,replacementBasis:ResolvedOccurrenceBasisV1?=nil,replacementOccurrenceID:OccurrenceIDV1?=nil,reasonCode:String,recordedBy:ActorSnapshotV1,recordedAt:Date)throws{self.exceptionID=exceptionID;self.kind=kind;self.priorEffectiveBasisSHA256=priorEffectiveBasisSHA256;self.replacementBasis=replacementBasis;self.replacementOccurrenceID=replacementOccurrenceID;self.reasonCode=reasonCode;self.recordedBy=recordedBy;self.recordedAt=recordedAt;exceptionSHA256=try ScheduleCanonicalCodecV1.sha256(Basis(exceptionID:exceptionID,kind:kind,priorEffectiveBasisSHA256:priorEffectiveBasisSHA256,replacementBasis:replacementBasis,replacementOccurrenceID:replacementOccurrenceID,reasonCode:reasonCode,recordedBy:recordedBy,recordedAt:recordedAt));try validate()}
    func validate()throws{try ScheduleLimitsV1.id(exceptionID);try ScheduleLimitsV1.digest(priorEffectiveBasisSHA256);try replacementBasis?.validate();try replacementOccurrenceID?.validate();try ScheduleLimitsV1.token(reasonCode);try recordedBy.validate();try ScheduleLimitsV1.instant(recordedAt);let replacementRequired=[ScheduleExceptionKindV1.deferred,.basisAdjusted].contains(kind);guard recordedBy.responsibility == .recordedBy,replacementRequired==(replacementBasis != nil),(kind == .retiredForRuleChange)==(replacementOccurrenceID != nil),exceptionSHA256==(try ScheduleCanonicalCodecV1.sha256(basis))else{throw ScheduleFailureV1.invalidDigest}}
    private var basis:Basis{.init(exceptionID:exceptionID,kind:kind,priorEffectiveBasisSHA256:priorEffectiveBasisSHA256,replacementBasis:replacementBasis,replacementOccurrenceID:replacementOccurrenceID,reasonCode:reasonCode,recordedBy:recordedBy,recordedAt:recordedAt)};private struct Basis:Codable{let exceptionID:UUID;let kind:ScheduleExceptionKindV1;let priorEffectiveBasisSHA256:String;let replacementBasis:ResolvedOccurrenceBasisV1?;let replacementOccurrenceID:OccurrenceIDV1?;let reasonCode:String;let recordedBy:ActorSnapshotV1;let recordedAt:Date}
}

enum OccurrenceStateV1:String,Codable,CaseIterable,Hashable,Sendable{case upcoming="UPCOMING",ready="READY",due="DUE",overdue="OVERDUE",deferred="DEFERRED",missed="MISSED",skipped="SKIPPED",cancelled="CANCELLED",started="STARTED",completed="COMPLETED"}
enum OccurrenceHistoryActionV1:String,Codable,CaseIterable,Hashable,Sendable{case generated="GENERATED",applyException="APPLY_EXCEPTION",start="START",complete="COMPLETE"}
enum ScheduledWorkInstanceReferenceV1:Codable,Equatable,Hashable,Sendable{case workPacket(WorkPacketManifestReferenceV1);case roundSession(sessionID:UUID,revision:UInt64,sessionSHA256:String);func validate()throws{switch self{case .workPacket(let value):try value.validate();case let .roundSession(id,revision,digest):try ScheduleLimitsV1.id(id);try ScheduleLimitsV1.revision(revision);try ScheduleLimitsV1.digest(digest)}}}

struct OccurrenceHistoryEventV1:Codable,Equatable,Sendable{
    static let schemaVersion=1;let schemaVersion:Int;let eventID:UUID;let workspaceID:WorkspaceID;let occurrenceID:OccurrenceIDV1;let identityPredecessorOccurrenceID:OccurrenceIDV1?;let identityCompletionEventSHA256:String?;let scheduleRelease:ScheduleDefinitionReleaseReferenceV1;let action:OccurrenceHistoryActionV1;let nominalBasis:ResolvedOccurrenceBasisV1;let effectiveBasis:ResolvedOccurrenceBasisV1;let exception:ScheduleExceptionV1?;let workInstance:ScheduledWorkInstanceReferenceV1?;let completedAt:Date?;let predecessorEventID:UUID?;let predecessorEventSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1;let recordedBy:ActorSnapshotV1;let recordedAt:Date;let eventSHA256:String
    init(eventID:UUID,workspaceID:WorkspaceID,occurrenceID:OccurrenceIDV1,identityPredecessorOccurrenceID:OccurrenceIDV1?=nil,identityCompletionEventSHA256:String?=nil,scheduleRelease:ScheduleDefinitionReleaseReferenceV1,action:OccurrenceHistoryActionV1,nominalBasis:ResolvedOccurrenceBasisV1,effectiveBasis:ResolvedOccurrenceBasisV1,exception:ScheduleExceptionV1?=nil,workInstance:ScheduledWorkInstanceReferenceV1?=nil,completedAt:Date?=nil,predecessor:Self?,revision:UInt64,mutationID:MutationIDV1,recordedBy:ActorSnapshotV1,recordedAt:Date)throws{schemaVersion=Self.schemaVersion;self.eventID=eventID;self.workspaceID=workspaceID;self.occurrenceID=occurrenceID;self.identityPredecessorOccurrenceID=identityPredecessorOccurrenceID;self.identityCompletionEventSHA256=identityCompletionEventSHA256;self.scheduleRelease=scheduleRelease;self.action=action;self.nominalBasis=nominalBasis;self.effectiveBasis=effectiveBasis;self.exception=exception;self.workInstance=workInstance;self.completedAt=completedAt;predecessorEventID=predecessor?.eventID;predecessorEventSHA256=predecessor?.eventSHA256;self.revision=revision;self.mutationID=mutationID;self.recordedBy=recordedBy;self.recordedAt=recordedAt;eventSHA256=try ScheduleCanonicalCodecV1.sha256(Basis(schemaVersion:Self.schemaVersion,eventID:eventID,workspaceID:workspaceID,occurrenceID:occurrenceID,identityPredecessorOccurrenceID:identityPredecessorOccurrenceID,identityCompletionEventSHA256:identityCompletionEventSHA256,scheduleRelease:scheduleRelease,action:action,nominalBasis:nominalBasis,effectiveBasis:effectiveBasis,exception:exception,workInstance:workInstance,completedAt:completedAt,predecessorEventID:predecessor?.eventID,predecessorEventSHA256:predecessor?.eventSHA256,revision:revision,mutationID:mutationID,recordedBy:recordedBy,recordedAt:recordedAt));try validate(predecessor:predecessor)}
    func validateIntrinsic()throws{try ScheduleLimitsV1.id(eventID);try occurrenceID.validate();try identityPredecessorOccurrenceID?.validate();if let identityCompletionEventSHA256{try ScheduleLimitsV1.digest(identityCompletionEventSHA256)};try scheduleRelease.validate();try nominalBasis.validate();try effectiveBasis.validate();try exception?.validate();try workInstance?.validate();try completedAt.map(ScheduleLimitsV1.instant);try recordedBy.validate();try ScheduleLimitsV1.instant(recordedAt);let derived=try OccurrenceIDV1(scheduleDefinitionID:scheduleRelease.scheduleDefinitionID,identityNamespaceID:scheduleRelease.occurrenceIdentityNamespaceID,nominalKey:nominalBasis.nominalKey,predecessorOccurrenceID:identityPredecessorOccurrenceID,completionEventSHA256:identityCompletionEventSHA256);guard schemaVersion==Self.schemaVersion,workspaceID==scheduleRelease.workspaceID,(identityPredecessorOccurrenceID==nil)==(identityCompletionEventSHA256==nil),occurrenceID==derived,nominalBasis.timeBasisSHA256==scheduleRelease.timeBasisSHA256,effectiveBasis.timeBasisSHA256==scheduleRelease.timeBasisSHA256,recordedBy.workspaceID==workspaceID,recordedBy.responsibility == .recordedBy,exception.map({$0.recordedBy.workspaceID==workspaceID}) ?? true,revision>0,(revision==1)==(action == .generated&&predecessorEventID==nil&&predecessorEventSHA256==nil),(exception != nil)==(action == .applyException),(action == .generated ? workInstance==nil:true),([.start,.complete].contains(action) ? workInstance != nil:true),(completedAt != nil)==(action == .complete),predecessorEventSHA256.map(KernelCanonicalHashV1.validSHA256) ?? true,eventSHA256==(try ScheduleCanonicalCodecV1.sha256(basis))else{throw ScheduleFailureV1.invalidDigest}}
    func validate(predecessor:Self?)throws{try validateIntrinsic();let exceptionValid:Bool;if action == .applyException,let predecessor,let exception{let priorSHA=try ScheduleCanonicalCodecV1.sha256(predecessor.effectiveBasis);exceptionValid=exception.priorEffectiveBasisSHA256==priorSHA&&(exception.replacementBasis.map{$0==effectiveBasis} ?? (effectiveBasis==predecessor.effectiveBasis))}else{exceptionValid=exception==nil&&(predecessor.map{$0.effectiveBasis==effectiveBasis} ?? true)};guard predecessorEventID==predecessor?.eventID,predecessorEventSHA256==predecessor?.eventSHA256,predecessor.map({$0.revision<UInt64.max&&revision==$0.revision+1&&$0.workspaceID==workspaceID&&$0.occurrenceID==occurrenceID&&$0.identityPredecessorOccurrenceID==identityPredecessorOccurrenceID&&$0.identityCompletionEventSHA256==identityCompletionEventSHA256&&$0.scheduleRelease==scheduleRelease&&$0.nominalBasis==nominalBasis&&$0.mutationID != mutationID}) ?? (revision==1),exceptionValid,Self.transition(predecessor?.action,action),predecessor.map({old in action == .applyException ? workInstance == old.workInstance : (old.workInstance == nil || old.workInstance == workInstance)}) ?? true,(action != .start || predecessor?.workInstance == nil),(action != .complete || predecessor?.workInstance != nil) else{throw ScheduleFailureV1.invalidSuccessor}}
    func rebound(to workspaceID:WorkspaceID,scheduleRelease:ScheduleDefinitionReleaseReferenceV1,recordedBy:ActorSnapshotV1,exception:ScheduleExceptionV1?,workInstance:ScheduledWorkInstanceReferenceV1?,predecessor:Self?)throws->Self{try .init(eventID:eventID,workspaceID:workspaceID,occurrenceID:occurrenceID,identityPredecessorOccurrenceID:identityPredecessorOccurrenceID,identityCompletionEventSHA256:identityCompletionEventSHA256,scheduleRelease:scheduleRelease,action:action,nominalBasis:nominalBasis,effectiveBasis:effectiveBasis,exception:exception,workInstance:workInstance,completedAt:completedAt,predecessor:predecessor,revision:revision,mutationID:mutationID,recordedBy:recordedBy,recordedAt:recordedAt)}
    private static func transition(_ old:OccurrenceHistoryActionV1?,_ new:OccurrenceHistoryActionV1)->Bool{switch(old,new){case(nil,.generated),(.generated,.applyException),(.applyException,.applyException),(.generated,.start),(.applyException,.start),(.start,.applyException),(.start,.complete),(.applyException,.complete):return true;default:return false}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,eventID:eventID,workspaceID:workspaceID,occurrenceID:occurrenceID,identityPredecessorOccurrenceID:identityPredecessorOccurrenceID,identityCompletionEventSHA256:identityCompletionEventSHA256,scheduleRelease:scheduleRelease,action:action,nominalBasis:nominalBasis,effectiveBasis:effectiveBasis,exception:exception,workInstance:workInstance,completedAt:completedAt,predecessorEventID:predecessorEventID,predecessorEventSHA256:predecessorEventSHA256,revision:revision,mutationID:mutationID,recordedBy:recordedBy,recordedAt:recordedAt)};private struct Basis:Codable{let schemaVersion:Int;let eventID:UUID;let workspaceID:WorkspaceID;let occurrenceID:OccurrenceIDV1;let identityPredecessorOccurrenceID:OccurrenceIDV1?;let identityCompletionEventSHA256:String?;let scheduleRelease:ScheduleDefinitionReleaseReferenceV1;let action:OccurrenceHistoryActionV1;let nominalBasis,effectiveBasis:ResolvedOccurrenceBasisV1;let exception:ScheduleExceptionV1?;let workInstance:ScheduledWorkInstanceReferenceV1?;let completedAt:Date?;let predecessorEventID:UUID?;let predecessorEventSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1;let recordedBy:ActorSnapshotV1;let recordedAt:Date}
}

extension OccurrenceHistoryEventV1: ScheduleCanonicalIntrinsicValidatingV1 {
    fileprivate func validateCanonicalValue() throws { try validateIntrinsic() }
}

struct OccurrenceGenerationWindowV1:Codable,Equatable,Sendable{let startsAtUTC:Date;let endsAtUTC:Date;let maximumOccurrences:Int;func validate(definition:ScheduleDefinitionReleaseV1)throws{try ScheduleLimitsV1.instant(startsAtUTC);try ScheduleLimitsV1.instant(endsAtUTC);guard startsAtUTC<=endsAtUTC,maximumOccurrences>0,maximumOccurrences<=definition.maximumGeneratedOccurrences,endsAtUTC.timeIntervalSince(startsAtUTC)<=Double(definition.generationHorizonDays*ScheduleLimitsV1.maximumCalendarDaySeconds) else{throw ScheduleFailureV1.limitExceeded}}}
struct OccurrenceGenerationCandidateV1:Codable,Equatable,Sendable{let occurrenceID:OccurrenceIDV1;let nominalBasis:ResolvedOccurrenceBasisV1;let effectiveBasis:ResolvedOccurrenceBasisV1;let predecessorOccurrenceID:OccurrenceIDV1?;let completionEventSHA256:String?;init(occurrenceID:OccurrenceIDV1,nominalBasis:ResolvedOccurrenceBasisV1,effectiveBasis:ResolvedOccurrenceBasisV1,predecessorOccurrenceID:OccurrenceIDV1?=nil,completionEventSHA256:String?=nil){self.occurrenceID=occurrenceID;self.nominalBasis=nominalBasis;self.effectiveBasis=effectiveBasis;self.predecessorOccurrenceID=predecessorOccurrenceID;self.completionEventSHA256=completionEventSHA256}func validate()throws{try occurrenceID.validate();try nominalBasis.validate();try effectiveBasis.validate();try predecessorOccurrenceID?.validate();if let completionEventSHA256{try ScheduleLimitsV1.digest(completionEventSHA256)};guard (predecessorOccurrenceID==nil)==(completionEventSHA256==nil)else{throw ScheduleFailureV1.invalidValue}}}
protocol ScheduleCalendarResolvingV1:Sendable{func candidates(definition:ScheduleDefinitionReleaseV1,window:OccurrenceGenerationWindowV1,completionHistory:[OccurrenceHistoryEventV1])throws->[OccurrenceGenerationCandidateV1]}
struct OccurrenceGenerationPlanV1:Codable,Equatable,Sendable{let workspaceID:WorkspaceID;let scheduleRelease:ScheduleDefinitionReleaseReferenceV1;let window:OccurrenceGenerationWindowV1;let candidates:[OccurrenceGenerationCandidateV1];let existingOccurrenceIDs:[OccurrenceIDV1];let planSHA256:String
    init(definition:ScheduleDefinitionReleaseV1,window:OccurrenceGenerationWindowV1,candidates:[OccurrenceGenerationCandidateV1],existingOccurrenceIDs:[OccurrenceIDV1])throws{workspaceID=definition.workspaceID;scheduleRelease=try .init(definition);self.window=window;self.candidates=candidates.sorted{$0.occurrenceID<$1.occurrenceID};self.existingOccurrenceIDs=existingOccurrenceIDs.sorted();planSHA256=try ScheduleCanonicalCodecV1.sha256(Basis(workspaceID:workspaceID,scheduleRelease:scheduleRelease,window:window,candidates:self.candidates,existingOccurrenceIDs:self.existingOccurrenceIDs));try validate(definition:definition)}
    func validate(definition:ScheduleDefinitionReleaseV1)throws{try definition.validate();try window.validate(definition:definition);try candidates.forEach{$0.validate()};try existingOccurrenceIDs.forEach{$0.validate()};guard workspaceID==definition.workspaceID,scheduleRelease==(try ScheduleDefinitionReleaseReferenceV1(definition)),candidates.count<=window.maximumOccurrences,Set(candidates.map(\.occurrenceID)).count==candidates.count,candidates==candidates.sorted(by:{$0.occurrenceID<$1.occurrenceID}),existingOccurrenceIDs==existingOccurrenceIDs.sorted(),Set(existingOccurrenceIDs).count==existingOccurrenceIDs.count,Set(candidates.map(\.occurrenceID)).isDisjoint(with:Set(existingOccurrenceIDs)),planSHA256==(try ScheduleCanonicalCodecV1.sha256(basis))else{throw ScheduleFailureV1.divergentReplay}}
    private var basis:Basis{.init(workspaceID:workspaceID,scheduleRelease:scheduleRelease,window:window,candidates:candidates,existingOccurrenceIDs:existingOccurrenceIDs)};private struct Basis:Codable{let workspaceID:WorkspaceID;let scheduleRelease:ScheduleDefinitionReleaseReferenceV1;let window:OccurrenceGenerationWindowV1;let candidates:[OccurrenceGenerationCandidateV1];let existingOccurrenceIDs:[OccurrenceIDV1]}
}

enum ScheduleOccurrenceGeneratorV1{static func generate(definition:ScheduleDefinitionReleaseV1,history:[OccurrenceHistoryEventV1],completionHistory:[OccurrenceHistoryEventV1],window:OccurrenceGenerationWindowV1,resolver:any ScheduleCalendarResolvingV1,releaseHistory:[ScheduleDefinitionReleaseV1]=[])throws->OccurrenceGenerationPlanV1{try definition.validate();try window.validate(definition:definition);try completionHistory.forEach{$0.validateIntrinsic()};let reference=try ScheduleDefinitionReleaseReferenceV1(definition),definitions=(releaseHistory+[definition]).sorted{$0.revision<$1.revision};guard definitions.last==definition,Set(definitions.map(\.releaseID)).count==definitions.count,definitions.allSatisfy({$0.workspaceID==definition.workspaceID&&$0.scheduleDefinitionID==definition.scheduleDefinitionID})else{throw ScheduleFailureV1.staleBasis};try ScheduleLifecycleClosureV1(definitions:definitions,history:[]).validate();let relevantReferences=Set(try definitions.filter{$0.occurrenceIdentityNamespaceID==definition.occurrenceIdentityNamespaceID}.map{try ScheduleDefinitionReleaseReferenceV1($0)}),relevantHistory=history.filter{relevantReferences.contains($0.scheduleRelease)};try ScheduleLifecycleClosureV1(definitions:definitions,history:relevantHistory).validate();let historyByEventID=Dictionary(grouping:relevantHistory,by:\.eventID);guard history.count==relevantHistory.count,definition.lifecycleState == .active,window.startsAtUTC>=definition.startsAtUTC,definition.endsAtUTC.map({window.endsAtUTC<=$0}) ?? true,completionHistory.allSatisfy({event in relevantReferences.contains(event.scheduleRelease)&&event.workspaceID==definition.workspaceID&&event.action == .complete&&historyByEventID[event.eventID]?.count==1&&historyByEventID[event.eventID]?.first?.eventSHA256==event.eventSHA256})else{throw ScheduleFailureV1.staleBasis};let existing=Set(relevantHistory.map(\.occurrenceID)),completions=Dictionary(grouping:completionHistory,by:\.eventSHA256),allHistory=Dictionary(grouping:relevantHistory,by:\.eventSHA256);let generated=try resolver.candidates(definition:definition,window:window,completionHistory:completionHistory);try generated.forEach{candidate in try candidate.validate();let expected=try OccurrenceIDV1(scheduleDefinitionID:definition.scheduleDefinitionID,identityNamespaceID:definition.occurrenceIdentityNamespaceID,nominalKey:candidate.nominalBasis.nominalKey,predecessorOccurrenceID:candidate.predecessorOccurrenceID,completionEventSHA256:candidate.completionEventSHA256),resolved=candidate.effectiveBasis.resolvedAtUTC;guard expected==candidate.occurrenceID,candidate.nominalBasis.timeBasisSHA256==reference.timeBasisSHA256,candidate.effectiveBasis.timeBasisSHA256==reference.timeBasisSHA256,resolved.map({$0>=window.startsAtUTC&&$0<=window.endsAtUTC}) ?? (candidate.effectiveBasis.disposition == .nonexistentGap) else{throw ScheduleFailureV1.divergentReplay};switch definition.recurrence{case .fixedCalendar:guard candidate.predecessorOccurrenceID==nil,candidate.completionEventSHA256==nil else{throw ScheduleFailureV1.staleBasis};case .completionRelative:if let digest=candidate.completionEventSHA256{guard let source=completions[digest],source.count==1,source[0].occurrenceID==candidate.predecessorOccurrenceID else{throw ScheduleFailureV1.staleBasis}};case .advanced(let configuration):switch configuration.recurrence{case .completionRelative(_,_,let gapPolicy):if let digest=candidate.completionEventSHA256{let completed=completions[digest];let skipped=allHistory[digest];let validCompletion=completed?.count==1&&completed?[0].occurrenceID==candidate.predecessorOccurrenceID;let validSkip=gapPolicy == .anchorToNominalAfterExplicitSkip&&skipped?.count==1&&skipped?[0].occurrenceID==candidate.predecessorOccurrenceID&&skipped?[0].exception?.kind == .skipped;guard validCompletion||validSkip else{throw ScheduleFailureV1.staleBasis}};default:guard candidate.predecessorOccurrenceID==nil,candidate.completionEventSHA256==nil else{throw ScheduleFailureV1.staleBasis}}}};guard generated.count<=window.maximumOccurrences else{throw ScheduleFailureV1.limitExceeded};let filtered=generated.filter{!existing.contains($0.occurrenceID)};return try .init(definition:definition,window:window,candidates:filtered,existingOccurrenceIDs:Array(existing))}}

struct ScheduleLifecycleClosureV1: Codable, Equatable, Sendable {
    let definitions: [ScheduleDefinitionReleaseV1]
    let history: [OccurrenceHistoryEventV1]
    func validate() throws {
        try definitions.forEach { try $0.validate() }
        try history.forEach { try $0.validateIntrinsic() }
        guard Set(definitions.map(\.releaseID)).count == definitions.count,
              Set(history.map(\.eventID)).count == history.count else {
            throw ScheduleFailureV1.divergentReplay
        }
        if definitions.isEmpty {
            guard history.isEmpty else { throw ScheduleFailureV1.staleBasis }
            return
        }
        var releases = Set<ScheduleDefinitionReleaseReferenceV1>()
        for group in Dictionary(grouping: definitions, by: \.scheduleDefinitionID).values {
            let ordered = group.sorted { $0.revision < $1.revision }
            guard ordered.first?.revision == 1 else { throw ScheduleFailureV1.invalidSuccessor }
            for index in 1..<ordered.count { try ordered[index].validateSuccessor(of: ordered[index - 1]) }
            for value in ordered { releases.insert(try .init(value)) }
        }
        for group in Dictionary(grouping: history, by: \.occurrenceID).values {
            let ordered = group.sorted { $0.revision < $1.revision }
            guard ordered.filter({ $0.action == .applyException }).count <= ScheduleLimitsV1.maximumExceptionsPerOccurrence else {
                throw ScheduleFailureV1.limitExceeded
            }
            guard let first = ordered.first else { continue }
            try first.validate(predecessor: nil)
            for index in 1..<ordered.count { try ordered[index].validate(predecessor: ordered[index - 1]) }
            guard ordered.allSatisfy({ releases.contains($0.scheduleRelease) }) else {
                throw ScheduleFailureV1.staleBasis
            }
        }
    }
}

struct DueQueueEntryV1:Codable,Equatable,Sendable{let occurrenceID:OccurrenceIDV1;let state:OccurrenceStateV1;let effectiveDueAtUTC:Date?;let scheduleRelease:ScheduleDefinitionReleaseReferenceV1;let workInstance:ScheduledWorkInstanceReferenceV1?}
struct DueQueueProjectionV1:Codable,Equatable,Sendable{let workspaceID:WorkspaceID;let evaluatedAt:Date;let entries:[DueQueueEntryV1];let sourceClosureSHA256:String;let projectionSHA256:String
    init(workspaceID:WorkspaceID,evaluatedAt:Date,definitions:[ScheduleDefinitionReleaseV1],history:[OccurrenceHistoryEventV1])throws{try ScheduleLimitsV1.instant(evaluatedAt);try definitions.forEach{$0.validate()};try history.forEach{$0.validateIntrinsic()};guard definitions.allSatisfy({$0.workspaceID==workspaceID}),history.allSatisfy({$0.workspaceID==workspaceID})else{throw ScheduleFailureV1.wrongWorkspace};try ScheduleLifecycleClosureV1(definitions:definitions,history:history).validate();var releases:[ScheduleDefinitionReleaseReferenceV1:ScheduleDefinitionReleaseV1]=[:];for definition in definitions{let reference=try ScheduleDefinitionReleaseReferenceV1(definition);guard releases.updateValue(definition,forKey:reference)==nil else{throw ScheduleFailureV1.divergentReplay}};let grouped=Dictionary(grouping:history,by:\.occurrenceID);var values:[DueQueueEntryV1]=[];for(id,events)in grouped{let ordered=events.sorted{$0.revision<$1.revision};guard let latest=ordered.last,let definition=releases[latest.scheduleRelease]else{throw ScheduleFailureV1.invalidValue};values.append(.init(occurrenceID:id,state:try Self.state(latest,definition,evaluatedAt),effectiveDueAtUTC:latest.effectiveBasis.resolvedAtUTC,scheduleRelease:latest.scheduleRelease,workInstance:latest.workInstance))};entries=values.sorted{($0.effectiveDueAtUTC ?? .distantFuture,$0.occurrenceID)<($1.effectiveDueAtUTC ?? .distantFuture,$1.occurrenceID)};self.workspaceID=workspaceID;self.evaluatedAt=evaluatedAt;sourceClosureSHA256=try ScheduleCanonicalCodecV1.sha256(Source(definitions:definitions.sorted{$0.releaseID.uuidString<$1.releaseID.uuidString},history:history.sorted{$0.eventID.uuidString<$1.eventID.uuidString}));projectionSHA256=try ScheduleCanonicalCodecV1.sha256(Basis(workspaceID:workspaceID,evaluatedAt:evaluatedAt,entries:entries,sourceClosureSHA256:sourceClosureSHA256))}
    private static func state(_ e:OccurrenceHistoryEventV1,_ d:ScheduleDefinitionReleaseV1,_ now:Date)throws->OccurrenceStateV1{if e.action == .complete{return .completed};if let x=e.exception{switch x.kind{case .skipped:return .skipped;case .cancelled,.retiredForRuleChange:return .cancelled;case .missed:return .missed;case .deferred:if let due=e.effectiveBasis.resolvedAtUTC,now<due.addingTimeInterval(-Double(d.readyLeadSeconds)){return .deferred};case .basisAdjusted:break}};if e.action == .start{return .started};guard let due=e.effectiveBasis.resolvedAtUTC else{return .skipped};if now<due.addingTimeInterval(-Double(d.readyLeadSeconds)){return .upcoming};if now<due{return .ready};if now<=due.addingTimeInterval(Double(d.overdueGraceSeconds)){return .due};return .overdue}
    private struct Source:Codable{let definitions:[ScheduleDefinitionReleaseV1];let history:[OccurrenceHistoryEventV1]};private struct Basis:Codable{let workspaceID:WorkspaceID;let evaluatedAt:Date;let entries:[DueQueueEntryV1];let sourceClosureSHA256:String}
}

struct ReminderEntryV1:Codable,Equatable,Hashable,Comparable,Sendable{let notificationID:String;let occurrenceID:OccurrenceIDV1;let fireAtUTC:Date;let localizationKey:String;static func <(l:Self,r:Self)->Bool{(l.fireAtUTC,l.notificationID)<(r.fireAtUTC,r.notificationID)}}
struct ReminderProjectionV1:Codable,Equatable,Sendable{let workspaceID:WorkspaceID;let evaluatedAt:Date;let dueQueueSHA256:String;let reminders:[ReminderEntryV1];let projectionSHA256:String
    init(dueQueue:DueQueueProjectionV1,localizationKey:String)throws{try ScheduleLimitsV1.token(localizationKey);workspaceID=dueQueue.workspaceID;evaluatedAt=dueQueue.evaluatedAt;dueQueueSHA256=dueQueue.projectionSHA256;reminders=try dueQueue.entries.compactMap{entry in guard [.upcoming,.ready,.due,.deferred].contains(entry.state),let fire=entry.effectiveDueAtUTC else{return nil};return .init(notificationID:"schedule.\(entry.occurrenceID.rawValue)",occurrenceID:entry.occurrenceID,fireAtUTC:fire,localizationKey:localizationKey)}.sorted();projectionSHA256=try ScheduleCanonicalCodecV1.sha256(Basis(workspaceID:workspaceID,evaluatedAt:evaluatedAt,dueQueueSHA256:dueQueueSHA256,reminders:reminders));try validate()}
    func validate()throws{try ScheduleLimitsV1.instant(evaluatedAt);try ScheduleLimitsV1.digest(dueQueueSHA256);try reminders.forEach{try $0.occurrenceID.validate();try ScheduleLimitsV1.instant($0.fireAtUTC);try ScheduleLimitsV1.token($0.localizationKey);try ScheduleLimitsV1.token($0.notificationID)};guard reminders==reminders.sorted(),Set(reminders.map(\.notificationID)).count==reminders.count,projectionSHA256==(try ScheduleCanonicalCodecV1.sha256(Basis(workspaceID:workspaceID,evaluatedAt:evaluatedAt,dueQueueSHA256:dueQueueSHA256,reminders:reminders)))else{throw ScheduleFailureV1.divergentReplay}}
    private struct Basis:Codable{let workspaceID:WorkspaceID;let evaluatedAt:Date;let dueQueueSHA256:String;let reminders:[ReminderEntryV1]}
}

enum ScheduleCanonicalCodecV1{static func data<T:Encodable>(_ value:T)throws->Data{try WorkspaceMutationCanonicalV1.data(value)}static func sha256<T:Encodable>(_ value:T)throws->String{try WorkspaceMutationCanonicalV1.sha256(value)}static func decode<T:Codable>(_ type:T.Type,from data:Data)throws->T{guard !data.isEmpty,data.count<=ScheduleLimitsV1.maximumCanonicalBytes else{throw ScheduleFailureV1.limitExceeded};let d=JSONDecoder();d.dateDecodingStrategy = .millisecondsSince1970;let value=try d.decode(type,from:data);try (value as? any ScheduleCanonicalIntrinsicValidatingV1)?.validateCanonicalValue();guard try self.data(value)==data else{throw ScheduleFailureV1.invalidDigest};return value}}

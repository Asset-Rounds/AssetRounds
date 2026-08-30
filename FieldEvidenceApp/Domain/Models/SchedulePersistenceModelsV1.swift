import Foundation
import SwiftData

extension ScheduleDefinitionReleaseRow {
    func c34NavigationAnchor() throws -> C34ScheduleNavigationAnchorV1 {
        let release = try value()
        let reference = try ScheduleDefinitionReleaseReferenceV1(release)
        return try C34ScheduleNavigationAnchorV1(reference: reference)
    }
}

extension OccurrenceHistoryEventRow {
    func c34NavigationAnchor() throws -> C34OccurrenceNavigationAnchorV1 {
        try C34OccurrenceNavigationAnchorV1(event: value())
    }
}

enum C34SchedulePersistenceNavigationBoundaryV1 {
    static let routeSnapshotCreatesPersistentScheduleRow = false
    static let routeSnapshotCopiesCanonicalSchedulePayload = false
    static let restorationWritesScheduleRows = false
}

enum SchedulePersistenceFailureV1: Error { case corruptRow }

@Model final class ScheduleDefinitionReleaseRow {
    @Attribute(.unique) var releaseID: UUID
    var scheduleDefinitionID: UUID
    var workspaceID: UUID
    var occurrenceIdentityNamespaceID: UUID
    var lifecycleStateRawValue: String
    var supersedesReleaseID: UUID?
    var revision: UInt64
    var mutationID: UUID
    var releaseSHA256: String
    var canonicalData: Data

    init(_ value: ScheduleDefinitionReleaseV1) throws {
        try value.validate()
        releaseID=value.releaseID;scheduleDefinitionID=value.scheduleDefinitionID;workspaceID=value.workspaceID.rawValue
        occurrenceIdentityNamespaceID=value.occurrenceIdentityNamespaceID
        lifecycleStateRawValue=value.lifecycleState.rawValue;supersedesReleaseID=value.supersedesReleaseID
        revision=value.revision;mutationID=value.mutationID.rawValue;releaseSHA256=value.releaseSHA256
        canonicalData=try ScheduleCanonicalCodecV1.data(value)
        let decoded=try ScheduleCanonicalCodecV1.decode(ScheduleDefinitionReleaseV1.self,from:canonicalData)
        guard decoded==value else{throw SchedulePersistenceFailureV1.corruptRow}
    }

    func value() throws -> ScheduleDefinitionReleaseV1 {
        let value=try ScheduleCanonicalCodecV1.decode(ScheduleDefinitionReleaseV1.self,from:canonicalData)
        try value.validate()
        guard value.releaseID==releaseID,value.scheduleDefinitionID==scheduleDefinitionID,
              value.workspaceID.rawValue==workspaceID,value.occurrenceIdentityNamespaceID==occurrenceIdentityNamespaceID,
              value.lifecycleState.rawValue==lifecycleStateRawValue,
              value.supersedesReleaseID==supersedesReleaseID,value.revision==revision,
              value.mutationID.rawValue==mutationID,value.releaseSHA256==releaseSHA256 else {
            throw SchedulePersistenceFailureV1.corruptRow
        }
        return value
    }

    func value(predecessor: ScheduleDefinitionReleaseV1?) throws -> ScheduleDefinitionReleaseV1 {
        let value=try self.value()
        if let predecessor { try value.validateSuccessor(of:predecessor) }
        else if value.revision != 1 { throw SchedulePersistenceFailureV1.corruptRow }
        return value
    }
}

@Model final class OccurrenceHistoryEventRow {
    @Attribute(.unique) var eventID: UUID
    var workspaceID: UUID
    var occurrenceID: String
    var scheduleReleaseID: UUID
    var scheduleReleaseWorkspaceID: UUID
    var occurrenceIdentityNamespaceID: UUID
    var actionRawValue: String
    var identityPredecessorOccurrenceID: String?
    var identityCompletionEventSHA256: String?
    var predecessorEventID: UUID?
    var revision: UInt64
    var mutationID: UUID
    var eventSHA256: String
    var canonicalData: Data

    init(_ value: OccurrenceHistoryEventV1) throws {
        try value.validateIntrinsic()
        eventID=value.eventID;workspaceID=value.workspaceID.rawValue;occurrenceID=value.occurrenceID.rawValue
        scheduleReleaseID=value.scheduleRelease.releaseID;scheduleReleaseWorkspaceID=value.scheduleRelease.workspaceID.rawValue
        occurrenceIdentityNamespaceID=value.scheduleRelease.occurrenceIdentityNamespaceID;actionRawValue=value.action.rawValue
        identityPredecessorOccurrenceID=value.identityPredecessorOccurrenceID?.rawValue;identityCompletionEventSHA256=value.identityCompletionEventSHA256
        predecessorEventID=value.predecessorEventID;revision=value.revision;mutationID=value.mutationID.rawValue
        eventSHA256=value.eventSHA256;canonicalData=try ScheduleCanonicalCodecV1.data(value)
        let decoded=try ScheduleCanonicalCodecV1.decode(OccurrenceHistoryEventV1.self,from:canonicalData)
        guard decoded==value else{throw SchedulePersistenceFailureV1.corruptRow}
    }

    func value() throws -> OccurrenceHistoryEventV1 {
        let value=try ScheduleCanonicalCodecV1.decode(OccurrenceHistoryEventV1.self,from:canonicalData)
        try value.validateIntrinsic()
        guard value.eventID==eventID,value.workspaceID.rawValue==workspaceID,
              value.occurrenceID.rawValue==occurrenceID,value.scheduleRelease.releaseID==scheduleReleaseID,
              value.scheduleRelease.workspaceID.rawValue==scheduleReleaseWorkspaceID,
              value.scheduleRelease.occurrenceIdentityNamespaceID==occurrenceIdentityNamespaceID,
              value.action.rawValue==actionRawValue,
              value.identityPredecessorOccurrenceID?.rawValue==identityPredecessorOccurrenceID,
              value.identityCompletionEventSHA256==identityCompletionEventSHA256,value.predecessorEventID==predecessorEventID,
              value.revision==revision,value.mutationID.rawValue==mutationID,value.eventSHA256==eventSHA256 else {
            throw SchedulePersistenceFailureV1.corruptRow
        }
        return value
    }

    func value(predecessor: OccurrenceHistoryEventV1?) throws -> OccurrenceHistoryEventV1 {
        let value=try self.value();try value.validate(predecessor:predecessor);return value
    }
}

/// Immutable C51 calendar-release authority.  The indexed columns are only
/// lookup/integrity mirrors; the canonical payload remains the source of
/// truth and is decoded and revalidated before use.
@Model final class ExceptionCalendarReleaseRow {
    @Attribute(.unique) var releaseID: UUID
    var calendarID: UUID
    var workspaceID: UUID
    var supersedesReleaseID: UUID?
    var revision: UInt64
    var mutationID: UUID
    var releaseSHA256: String
    var canonicalData: Data

    init(_ value: ExceptionCalendarReleaseV1) throws {
        try value.validate()
        releaseID = value.releaseID
        calendarID = value.calendarID
        workspaceID = value.workspaceID.rawValue
        supersedesReleaseID = value.supersedesReleaseID
        revision = value.revision
        mutationID = value.mutationID.rawValue
        releaseSHA256 = value.releaseSHA256
        canonicalData = try ScheduleCanonicalCodecV1.data(value)
        let decoded = try ScheduleCanonicalCodecV1.decode(
            ExceptionCalendarReleaseV1.self,
            from: canonicalData
        )
        guard decoded == value else { throw SchedulePersistenceFailureV1.corruptRow }
    }

    func value() throws -> ExceptionCalendarReleaseV1 {
        let value = try ScheduleCanonicalCodecV1.decode(
            ExceptionCalendarReleaseV1.self,
            from: canonicalData
        )
        try value.validate()
        guard value.releaseID == releaseID,
              value.calendarID == calendarID,
              value.workspaceID.rawValue == workspaceID,
              value.supersedesReleaseID == supersedesReleaseID,
              value.revision == revision,
              value.mutationID.rawValue == mutationID,
              value.releaseSHA256 == releaseSHA256 else {
            throw SchedulePersistenceFailureV1.corruptRow
        }
        return value
    }

    func value(predecessor: ExceptionCalendarReleaseV1?) throws -> ExceptionCalendarReleaseV1 {
        let value = try self.value()
        if let predecessor { try value.validateSuccessor(of: predecessor) }
        else if value.revision != 1 { throw SchedulePersistenceFailureV1.corruptRow }
        return value
    }
}

/// Append-only C51 override authority.  Supersession is represented by a new
/// immutable row; the predecessor remains available for replay/audit.
@Model final class ScheduleOverrideEventRow {
    @Attribute(.unique) var eventID: UUID
    var workspaceID: UUID
    var scheduleDefinitionID: UUID
    var scheduleReleaseID: UUID
    var supersedesEventID: UUID?
    var revision: UInt64
    var mutationID: UUID
    var eventSHA256: String
    var canonicalData: Data

    init(_ value: ScheduleOverrideEventV1) throws {
        try value.validate()
        eventID = value.eventID
        workspaceID = value.workspaceID.rawValue
        scheduleDefinitionID = value.scheduleRelease.scheduleDefinitionID
        scheduleReleaseID = value.scheduleRelease.releaseID
        supersedesEventID = value.supersedesEventID
        revision = value.revision
        mutationID = value.mutationID.rawValue
        eventSHA256 = value.eventSHA256
        canonicalData = try ScheduleCanonicalCodecV1.data(value)
        let decoded = try ScheduleCanonicalCodecV1.decode(
            ScheduleOverrideEventV1.self,
            from: canonicalData
        )
        guard decoded == value else { throw SchedulePersistenceFailureV1.corruptRow }
    }

    func value() throws -> ScheduleOverrideEventV1 {
        let value = try ScheduleCanonicalCodecV1.decode(
            ScheduleOverrideEventV1.self,
            from: canonicalData
        )
        try value.validate()
        guard value.eventID == eventID,
              value.workspaceID.rawValue == workspaceID,
              value.scheduleRelease.scheduleDefinitionID == scheduleDefinitionID,
              value.scheduleRelease.releaseID == scheduleReleaseID,
              value.supersedesEventID == supersedesEventID,
              value.revision == revision,
              value.mutationID.rawValue == mutationID,
              value.eventSHA256 == eventSHA256 else {
            throw SchedulePersistenceFailureV1.corruptRow
        }
        return value
    }

    func value(predecessor: ScheduleOverrideEventV1?) throws -> ScheduleOverrideEventV1 {
        let value = try self.value()
        if let predecessor { try value.validateSuccessor(of: predecessor) }
        else if value.revision != 1 { throw SchedulePersistenceFailureV1.corruptRow }
        return value
    }
}

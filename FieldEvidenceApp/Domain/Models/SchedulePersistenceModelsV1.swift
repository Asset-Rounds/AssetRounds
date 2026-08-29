import Foundation
import SwiftData

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

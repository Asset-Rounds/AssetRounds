import Foundation
import SwiftData

enum ServiceRequestPersistenceFailureV1: Error, Equatable, Sendable {
    case corruptRow
    case immutableRow
}

/// Immutable canonical request revisions. The composite key preserves every
/// released revision rather than updating or replacing escaped source truth.
@Model final class ServiceRequestRecordRow {
    @Attribute(.unique) private(set) var stableIdentity: String
    private(set) var recordID: UUID
    private(set) var workspaceID: UUID
    private(set) var revision: UInt64
    private(set) var sourceRawValue: String
    private(set) var siteID: UUID
    private(set) var submissionPublicID: String?
    private(set) var invitationPublicID: String?
    private(set) var mutationID: UUID
    private(set) var recordSHA256: String
    private(set) var acceptedSourceSHA256: String?
    private(set) var canonicalData: Data

    init(_ value: ServiceRequestRecordV1) throws {
        try value.validate()
        stableIdentity = Self.identity(
            workspaceID: value.workspaceID.rawValue,
            recordID: value.recordID,
            revision: value.revision
        )
        recordID = value.recordID
        workspaceID = value.workspaceID.rawValue
        revision = value.revision
        sourceRawValue = value.source.rawValue
        siteID = value.scope.siteID
        submissionPublicID = value.submissionPublicID?.rawValue
        invitationPublicID = value.invitationPublicID?.rawValue
        mutationID = value.mutationID.rawValue
        recordSHA256 = value.recordSHA256
        acceptedSourceSHA256 = value.acceptedSourceBytes?.sha256
        canonicalData = try ServiceRequestCanonicalCodecV1.data(value)
        guard try ServiceRequestCanonicalCodecV1.decode(
            ServiceRequestRecordV1.self,
            from: canonicalData
        ) == value else { throw ServiceRequestPersistenceFailureV1.corruptRow }
    }

    func value() throws -> ServiceRequestRecordV1 {
        let value = try ServiceRequestCanonicalCodecV1.decode(
            ServiceRequestRecordV1.self,
            from: canonicalData
        )
        try value.validate()
        guard stableIdentity == Self.identity(
                workspaceID: value.workspaceID.rawValue,
                recordID: value.recordID,
                revision: value.revision
              ),
              recordID == value.recordID,
              workspaceID == value.workspaceID.rawValue,
              revision == value.revision,
              sourceRawValue == value.source.rawValue,
              siteID == value.scope.siteID,
              submissionPublicID == value.submissionPublicID?.rawValue,
              invitationPublicID == value.invitationPublicID?.rawValue,
              mutationID == value.mutationID.rawValue,
              recordSHA256 == value.recordSHA256,
              acceptedSourceSHA256 == value.acceptedSourceBytes?.sha256,
              try ServiceRequestCanonicalCodecV1.data(value) == canonicalData else {
            throw ServiceRequestPersistenceFailureV1.corruptRow
        }
        return value
    }

    func value(predecessor: ServiceRequestRecordV1?) throws -> ServiceRequestRecordV1 {
        let value = try self.value()
        if let predecessor { try value.validateSuccessor(of: predecessor) }
        else if value.revision != 1 { throw ServiceRequestPersistenceFailureV1.corruptRow }
        return value
    }

    private static func identity(workspaceID: UUID, recordID: UUID, revision: UInt64) -> String {
        "\(workspaceID.uuidString.lowercased())|\(recordID.uuidString.lowercased())|\(revision)"
    }
}

/// Append-only disposition history. State is rebuilt from this series; rows
/// are never overwritten by projection changes.
@Model final class ServiceRequestDispositionEventRow {
    @Attribute(.unique) private(set) var eventID: UUID
    private(set) var workspaceID: UUID
    private(set) var requestRecordID: UUID
    private(set) var requestRevision: UInt64
    private(set) var dispositionRawValue: String
    private(set) var resultingStateRawValue: String
    private(set) var predecessorEventID: UUID?
    private(set) var revision: UInt64
    private(set) var mutationID: UUID
    private(set) var eventSHA256: String
    private(set) var canonicalData: Data

    init(_ value: ServiceRequestDispositionEventV1) throws {
        try value.validate()
        eventID = value.eventID
        workspaceID = value.workspaceID.rawValue
        requestRecordID = value.request.recordID
        requestRevision = value.request.revision
        dispositionRawValue = value.disposition.rawValue
        resultingStateRawValue = value.resultingState.rawValue
        predecessorEventID = value.predecessorEventID
        revision = value.revision
        mutationID = value.mutationID.rawValue
        eventSHA256 = value.eventSHA256
        canonicalData = try ServiceRequestCanonicalCodecV1.data(value)
        guard try ServiceRequestCanonicalCodecV1.decode(
            ServiceRequestDispositionEventV1.self,
            from: canonicalData
        ) == value else { throw ServiceRequestPersistenceFailureV1.corruptRow }
    }

    func value() throws -> ServiceRequestDispositionEventV1 {
        let value = try ServiceRequestCanonicalCodecV1.decode(
            ServiceRequestDispositionEventV1.self,
            from: canonicalData
        )
        try value.validate()
        guard eventID == value.eventID,
              workspaceID == value.workspaceID.rawValue,
              requestRecordID == value.request.recordID,
              requestRevision == value.request.revision,
              dispositionRawValue == value.disposition.rawValue,
              resultingStateRawValue == value.resultingState.rawValue,
              predecessorEventID == value.predecessorEventID,
              revision == value.revision,
              mutationID == value.mutationID.rawValue,
              eventSHA256 == value.eventSHA256,
              try ServiceRequestCanonicalCodecV1.data(value) == canonicalData else {
            throw ServiceRequestPersistenceFailureV1.corruptRow
        }
        return value
    }

    func value(predecessor: ServiceRequestDispositionEventV1?) throws -> ServiceRequestDispositionEventV1 {
        let value = try self.value()
        if let predecessor { try value.validateSuccessor(of: predecessor) }
        else if value.revision != 1 { throw ServiceRequestPersistenceFailureV1.corruptRow }
        return value
    }
}

/// Append-only request-to-work provenance, including explicit unlink reversal.
/// Canonical work remains owned by the existing work/activity writer.
@Model final class ServiceRequestWorkLinkEventRow {
    @Attribute(.unique) private(set) var eventID: UUID
    private(set) var workspaceID: UUID
    private(set) var requestRecordID: UUID
    private(set) var requestRevision: UInt64
    private(set) var targetKindRawValue: String
    private(set) var targetID: UUID
    private(set) var canonicalWorkID: UUID
    private(set) var canonicalWorkRevision: UInt64
    private(set) var kindRawValue: String
    private(set) var reversesEventID: UUID?
    private(set) var predecessorEventID: UUID?
    private(set) var revision: UInt64
    private(set) var mutationID: UUID
    private(set) var eventSHA256: String
    private(set) var canonicalData: Data

    init(_ value: ServiceRequestWorkLinkEventV1) throws {
        try value.validate()
        eventID = value.eventID
        workspaceID = value.workspaceID.rawValue
        requestRecordID = value.request.recordID
        requestRevision = value.request.revision
        targetKindRawValue = value.target.kind.rawValue
        targetID = value.target.subjectID
        canonicalWorkID = value.canonicalWorkID
        canonicalWorkRevision = value.canonicalWorkRevision
        kindRawValue = value.kind.rawValue
        reversesEventID = value.reversesEventID
        predecessorEventID = value.predecessorEventID
        revision = value.revision
        mutationID = value.mutationID.rawValue
        eventSHA256 = value.eventSHA256
        canonicalData = try ServiceRequestCanonicalCodecV1.data(value)
        guard try ServiceRequestCanonicalCodecV1.decode(
            ServiceRequestWorkLinkEventV1.self,
            from: canonicalData
        ) == value else { throw ServiceRequestPersistenceFailureV1.corruptRow }
    }

    func value() throws -> ServiceRequestWorkLinkEventV1 {
        let value = try ServiceRequestCanonicalCodecV1.decode(
            ServiceRequestWorkLinkEventV1.self,
            from: canonicalData
        )
        try value.validate()
        guard eventID == value.eventID,
              workspaceID == value.workspaceID.rawValue,
              requestRecordID == value.request.recordID,
              requestRevision == value.request.revision,
              targetKindRawValue == value.target.kind.rawValue,
              targetID == value.target.subjectID,
              canonicalWorkID == value.canonicalWorkID,
              canonicalWorkRevision == value.canonicalWorkRevision,
              kindRawValue == value.kind.rawValue,
              reversesEventID == value.reversesEventID,
              predecessorEventID == value.predecessorEventID,
              revision == value.revision,
              mutationID == value.mutationID.rawValue,
              eventSHA256 == value.eventSHA256,
              try ServiceRequestCanonicalCodecV1.data(value) == canonicalData else {
            throw ServiceRequestPersistenceFailureV1.corruptRow
        }
        return value
    }

    func value(predecessor: ServiceRequestWorkLinkEventV1?) throws -> ServiceRequestWorkLinkEventV1 {
        let value = try self.value()
        if let predecessor { try value.validateSuccessor(of: predecessor) }
        else if value.revision != 1 { throw ServiceRequestPersistenceFailureV1.corruptRow }
        return value
    }
}

enum ServiceRequestPersistenceClassV1: String, Codable, CaseIterable, Hashable, Sendable {
    case canonicalPersistent = "CANONICAL_PERSISTENT"
    case protectedOperationScoped = "PROTECTED_OPERATION_SCOPED"
    case portableReleased = "PORTABLE_RELEASED"
    case nonpersistentDerived = "NONPERSISTENT_DERIVED"
    case prohibitedPersistent = "PROHIBITED_PERSISTENT"
}

struct ServiceRequestPersistenceRegistrationDescriptorV1: Codable, Equatable, Hashable, Sendable {
    let kind: String
    let classification: ServiceRequestPersistenceClassV1
    let canonicalOwner: String
    let includedInBackup: Bool
    let includedInSearch: Bool
    let erasedWithWorkspace: Bool
}

/// Registration data consumed by later schema/lifecycle lanes. Declaring the
/// next schema here does not itself mutate the existing schema registry.
enum ServiceRequestPersistenceEnrollmentV1 {
    static let predecessorPersistentSchemaVersion = 38
    static let targetPersistentSchemaVersion = 39
    static let durableModelCount = 3
    static let durableModels: [Any.Type] = [
        ServiceRequestRecordRow.self,
        ServiceRequestDispositionEventRow.self,
        ServiceRequestWorkLinkEventRow.self
    ]
    static let durableFamilies = [
        "ServiceRequestRecordV1",
        "ServiceRequestDispositionEventV1",
        "ServiceRequestWorkLinkEventV1"
    ]

    static let registrations = [
        ServiceRequestPersistenceRegistrationDescriptorV1(
            kind: "ServiceRequestRecordV1", classification: .canonicalPersistent,
            canonicalOwner: "WorkspaceWriterV1", includedInBackup: true,
            includedInSearch: true, erasedWithWorkspace: true
        ),
        ServiceRequestPersistenceRegistrationDescriptorV1(
            kind: "ServiceRequestDispositionEventV1", classification: .canonicalPersistent,
            canonicalOwner: "WorkspaceWriterV1", includedInBackup: true,
            includedInSearch: false, erasedWithWorkspace: true
        ),
        ServiceRequestPersistenceRegistrationDescriptorV1(
            kind: "ServiceRequestWorkLinkEventV1", classification: .canonicalPersistent,
            canonicalOwner: "WorkspaceWriterV1", includedInBackup: true,
            includedInSearch: false, erasedWithWorkspace: true
        ),
        ServiceRequestPersistenceRegistrationDescriptorV1(
            kind: "PortableExchangeSessionNamespaceV2.SERVICE_REQUEST",
            classification: .protectedOperationScoped,
            canonicalOwner: "PortableExchangeSessionStoreV2", includedInBackup: true,
            includedInSearch: false, erasedWithWorkspace: true
        ),
        ServiceRequestPersistenceRegistrationDescriptorV1(
            kind: "PortableServiceRequestInvitationV1", classification: .portableReleased,
            canonicalOwner: "PortableServiceRequestCodecV1", includedInBackup: false,
            includedInSearch: false, erasedWithWorkspace: false
        ),
        ServiceRequestPersistenceRegistrationDescriptorV1(
            kind: "PortableServiceRequestSubmissionV1", classification: .portableReleased,
            canonicalOwner: "PortableServiceRequestCodecV1", includedInBackup: false,
            includedInSearch: false, erasedWithWorkspace: false
        ),
        ServiceRequestPersistenceRegistrationDescriptorV1(
            kind: "ServiceRequestDuplicateProjectionV1", classification: .nonpersistentDerived,
            canonicalOwner: "ServiceRequestDuplicateProjectionEngineV1", includedInBackup: false,
            includedInSearch: false, erasedWithWorkspace: false
        ),
        ServiceRequestPersistenceRegistrationDescriptorV1(
            kind: "ServiceRequestStateProjectionV1", classification: .nonpersistentDerived,
            canonicalOwner: "ServiceRequestProjectionEngineV1", includedInBackup: false,
            includedInSearch: false, erasedWithWorkspace: false
        ),
        ServiceRequestPersistenceRegistrationDescriptorV1(
            kind: "ServiceRequestImportPlanV1", classification: .nonpersistentDerived,
            canonicalOwner: "ServiceRequestCoordinatorV1", includedInBackup: false,
            includedInSearch: false, erasedWithWorkspace: false
        ),
        ServiceRequestPersistenceRegistrationDescriptorV1(
            kind: "ServiceRequestSubmissionCapabilityV1.rawBytes",
            classification: .prohibitedPersistent,
            canonicalOwner: "NONE", includedInBackup: false,
            includedInSearch: false, erasedWithWorkspace: false
        )
    ]

    static func validate() throws {
        guard targetPersistentSchemaVersion == predecessorPersistentSchemaVersion + 1,
              durableModels.count == durableModelCount,
              durableFamilies.count == durableModelCount,
              Set(registrations.map(\.kind)).count == registrations.count,
              registrations.filter({ $0.classification == .canonicalPersistent }).count == durableModelCount,
              registrations.first(where: { $0.kind == "ServiceRequestSubmissionCapabilityV1.rawBytes" })?.classification == .prohibitedPersistent,
              !registrations.contains(where: {
                  $0.classification == .nonpersistentDerived &&
                  ($0.includedInBackup || $0.includedInSearch || $0.erasedWithWorkspace)
              }) else { throw ServiceRequestPersistenceFailureV1.corruptRow }
    }
}

enum ServiceRequestLifecycleRegistrationBoundaryV1 {
    static let immutableAcceptedSourceBytesParticipateInBackup = true
    static let protectedInvitationMappingParticipatesInBackup = true
    static let replaceRestorePreservesHistory = true
    static let cloneOrForkPreservesHistory = true
    static let cloneOrForkInvalidatesOutstandingCapabilities = true
    static let eraseRemovesOwnedProtectedState = true
    static let escapedPortableFilesCanBeRecalled = false
    static let rawCapabilityAppearsInReportsOrDiagnostics = false
    static let derivedProjectionIsRebuildable = true
    static let exactlyOneCanonicalWriter = true
}

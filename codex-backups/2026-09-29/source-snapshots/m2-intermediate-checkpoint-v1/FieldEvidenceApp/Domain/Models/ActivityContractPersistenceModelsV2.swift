import Foundation
import SwiftData

enum ActivityContractPersistenceFailureV2: Error, Equatable, Sendable {
    case corruptRow
    case duplicateIdentity
}

private enum ActivityContractPersistenceCodecV2 {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try WorkspaceMutationCanonicalV1.data(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }

    static func identity(workspaceID: UUID, id: UUID) -> String {
        "\(workspaceID.uuidString.lowercased())|\(id.uuidString.lowercased())"
    }
}

@Model final class ActivitySessionEnvelopeRow {
    @Attribute(.unique) var stableIdentity: String
    var activityID: UUID
    var workspaceID: UUID
    var kindRawValue: String
    var stateRawValue: String
    var subjectID: UUID
    var revision: UInt64
    var mutationID: UUID
    var envelopeSHA256: String
    var canonicalData: Data

    init(_ value: ActivitySessionEnvelopeV2) throws {
        try value.validateForRead()
        guard C47ActivityContractPersistenceBoundaryV2.acceptsCanonicalRow(kind: value.kind) else {
            throw ActivityContractPersistenceFailureV2.corruptRow
        }
        stableIdentity = ActivityContractPersistenceCodecV2.identity(
            workspaceID: value.workspaceID.rawValue, id: value.activityID
        )
        activityID = value.activityID
        workspaceID = value.workspaceID.rawValue
        kindRawValue = value.kind.rawValue
        stateRawValue = value.state.rawValue
        subjectID = value.subjectID
        revision = value.revision
        mutationID = value.mutationID.rawValue
        envelopeSHA256 = value.envelopeSHA256
        canonicalData = try ActivityContractPersistenceCodecV2.encode(value)
    }

    func value() throws -> ActivitySessionEnvelopeV2 {
        let value = try ActivityContractPersistenceCodecV2.decode(
            ActivitySessionEnvelopeV2.self, from: canonicalData
        )
        try value.validateForRead()
        guard C47ActivityContractPersistenceBoundaryV2.acceptsCanonicalRow(kind: value.kind),
              stableIdentity == ActivityContractPersistenceCodecV2.identity(
                workspaceID: value.workspaceID.rawValue, id: value.activityID
              ),
              activityID == value.activityID,
              workspaceID == value.workspaceID.rawValue,
              kindRawValue == value.kind.rawValue,
              stateRawValue == value.state.rawValue,
              subjectID == value.subjectID,
              revision == value.revision,
              mutationID == value.mutationID.rawValue,
              envelopeSHA256 == value.envelopeSHA256,
              canonicalData == (try ActivityContractPersistenceCodecV2.encode(value)) else {
            throw ActivityContractPersistenceFailureV2.corruptRow
        }
        return value
    }

    func replace(with value: ActivitySessionEnvelopeV2) throws {
        let predecessor = try self.value()
        try value.validateSuccessor(of: predecessor)
        let replacement = try ActivitySessionEnvelopeRow(value)
        kindRawValue = replacement.kindRawValue
        stateRawValue = replacement.stateRawValue
        subjectID = replacement.subjectID
        revision = replacement.revision
        mutationID = replacement.mutationID
        envelopeSHA256 = replacement.envelopeSHA256
        canonicalData = replacement.canonicalData
    }
}

@Model final class ActivityStateTransitionRow {
    @Attribute(.unique) var stableIdentity: String
    var transitionID: UUID
    var workspaceID: UUID
    var activityID: UUID
    var kindRawValue: String
    var fromStateRawValue: String
    var toStateRawValue: String
    var revision: UInt64
    var mutationID: UUID
    var transitionSHA256: String
    var canonicalData: Data

    init(_ value: ActivityStateTransitionV2) throws {
        try value.validate()
        stableIdentity = ActivityContractPersistenceCodecV2.identity(
            workspaceID: value.workspaceID.rawValue, id: value.transitionID
        )
        transitionID = value.transitionID
        workspaceID = value.workspaceID.rawValue
        activityID = value.activityID
        kindRawValue = value.kind.rawValue
        fromStateRawValue = value.fromState.rawValue
        toStateRawValue = value.toState.rawValue
        revision = value.revision
        mutationID = value.mutationID.rawValue
        transitionSHA256 = value.transitionSHA256
        canonicalData = try ActivityContractPersistenceCodecV2.encode(value)
    }

    func value() throws -> ActivityStateTransitionV2 {
        let value = try ActivityContractPersistenceCodecV2.decode(
            ActivityStateTransitionV2.self, from: canonicalData
        )
        try value.validate()
        guard stableIdentity == ActivityContractPersistenceCodecV2.identity(
                workspaceID: value.workspaceID.rawValue, id: value.transitionID
              ), transitionID == value.transitionID, workspaceID == value.workspaceID.rawValue,
              activityID == value.activityID, kindRawValue == value.kind.rawValue,
              fromStateRawValue == value.fromState.rawValue, toStateRawValue == value.toState.rawValue,
              revision == value.revision, mutationID == value.mutationID.rawValue,
              transitionSHA256 == value.transitionSHA256,
              canonicalData == (try ActivityContractPersistenceCodecV2.encode(value)) else {
            throw ActivityContractPersistenceFailureV2.corruptRow
        }
        return value
    }
}

@Model final class InstallationTaskResultRow {
    @Attribute(.unique) var stableIdentity: String
    var resultID: UUID
    var workspaceID: UUID
    var activityID: UUID
    var taskID: String
    var outcomeRawValue: String
    var revision: UInt64
    var mutationID: UUID
    var resultSHA256: String
    var canonicalData: Data

    init(_ value: InstallationTaskResultV1) throws {
        try value.validate()
        stableIdentity = ActivityContractPersistenceCodecV2.identity(
            workspaceID: value.workspaceID.rawValue, id: value.resultID
        )
        resultID = value.resultID
        workspaceID = value.workspaceID.rawValue
        activityID = value.activityID
        taskID = value.taskID
        outcomeRawValue = value.outcome.rawValue
        revision = value.revision
        mutationID = value.mutationID.rawValue
        resultSHA256 = value.resultSHA256
        canonicalData = try ActivityContractPersistenceCodecV2.encode(value)
    }

    func value() throws -> InstallationTaskResultV1 {
        let value = try ActivityContractPersistenceCodecV2.decode(
            InstallationTaskResultV1.self, from: canonicalData
        )
        try value.validate()
        guard stableIdentity == ActivityContractPersistenceCodecV2.identity(
                workspaceID: value.workspaceID.rawValue, id: value.resultID
              ), resultID == value.resultID, workspaceID == value.workspaceID.rawValue,
              activityID == value.activityID, taskID == value.taskID,
              outcomeRawValue == value.outcome.rawValue, revision == value.revision,
              mutationID == value.mutationID.rawValue, resultSHA256 == value.resultSHA256,
              canonicalData == (try ActivityContractPersistenceCodecV2.encode(value)) else {
            throw ActivityContractPersistenceFailureV2.corruptRow
        }
        return value
    }
}

@Model final class InstallationAsBuiltSnapshotRow {
    @Attribute(.unique) var stableIdentity: String
    var snapshotID: UUID
    var workspaceID: UUID
    var activityID: UUID
    var revision: UInt64
    var mutationID: UUID
    var snapshotSHA256: String
    var canonicalData: Data

    init(_ value: InstallationAsBuiltSnapshotV1) throws {
        try value.validate()
        stableIdentity = ActivityContractPersistenceCodecV2.identity(
            workspaceID: value.workspaceID.rawValue, id: value.snapshotID
        )
        snapshotID = value.snapshotID
        workspaceID = value.workspaceID.rawValue
        activityID = value.activityID
        revision = value.revision
        mutationID = value.mutationID.rawValue
        snapshotSHA256 = value.snapshotSHA256
        canonicalData = try ActivityContractPersistenceCodecV2.encode(value)
    }

    func value() throws -> InstallationAsBuiltSnapshotV1 {
        let value = try ActivityContractPersistenceCodecV2.decode(
            InstallationAsBuiltSnapshotV1.self, from: canonicalData
        )
        try value.validate()
        guard stableIdentity == ActivityContractPersistenceCodecV2.identity(
                workspaceID: value.workspaceID.rawValue, id: value.snapshotID
              ), snapshotID == value.snapshotID, workspaceID == value.workspaceID.rawValue,
              activityID == value.activityID, revision == value.revision,
              mutationID == value.mutationID.rawValue, snapshotSHA256 == value.snapshotSHA256,
              canonicalData == (try ActivityContractPersistenceCodecV2.encode(value)) else {
            throw ActivityContractPersistenceFailureV2.corruptRow
        }
        return value
    }
}

@Model final class PunchReviewBasisSnapshotRow {
    @Attribute(.unique) var stableIdentity: String
    var basisID: UUID
    var workspaceID: UUID
    var activityID: UUID
    var subjectID: UUID
    var revision: UInt64
    var mutationID: UUID
    var basisSHA256: String
    var canonicalData: Data

    init(_ value: PunchReviewBasisSnapshotV1) throws {
        try value.validate()
        stableIdentity = ActivityContractPersistenceCodecV2.identity(
            workspaceID: value.workspaceID.rawValue, id: value.basisID
        )
        basisID = value.basisID
        workspaceID = value.workspaceID.rawValue
        activityID = value.activityID
        subjectID = value.subjectID
        revision = value.revision
        mutationID = value.mutationID.rawValue
        basisSHA256 = value.basisSHA256
        canonicalData = try ActivityContractPersistenceCodecV2.encode(value)
    }

    func value() throws -> PunchReviewBasisSnapshotV1 {
        let value = try ActivityContractPersistenceCodecV2.decode(
            PunchReviewBasisSnapshotV1.self, from: canonicalData
        )
        try value.validate()
        guard stableIdentity == ActivityContractPersistenceCodecV2.identity(
                workspaceID: value.workspaceID.rawValue, id: value.basisID
              ), basisID == value.basisID, workspaceID == value.workspaceID.rawValue,
              activityID == value.activityID, subjectID == value.subjectID,
              revision == value.revision, mutationID == value.mutationID.rawValue,
              basisSHA256 == value.basisSHA256,
              canonicalData == (try ActivityContractPersistenceCodecV2.encode(value)) else {
            throw ActivityContractPersistenceFailureV2.corruptRow
        }
        return value
    }
}

@MainActor
final class ActivityContractRowQueryV2 {
    private let modelContext: ModelContext
    private let workspaceID: WorkspaceID
    private let currentRevisionProvider: (() throws -> WorkspaceRevisionV1)?

    init(modelContext: ModelContext, workspaceID: WorkspaceID) {
        self.modelContext = modelContext
        self.workspaceID = workspaceID
        currentRevisionProvider = nil
    }

    init(modelContext: ModelContext, workspaceID: WorkspaceID, writer: WorkspaceWriterV1) {
        self.modelContext = modelContext
        self.workspaceID = workspaceID
        currentRevisionProvider = { try writer.currentRevision() }
    }

    func currentEnvelope(workspaceID: WorkspaceID, activityID: UUID) throws -> ActivitySessionEnvelopeV2? {
        guard workspaceID == self.workspaceID else { return nil }
        let raw = workspaceID.rawValue
        let rows = try modelContext.fetch(FetchDescriptor<ActivitySessionEnvelopeRow>(
            predicate: #Predicate { $0.workspaceID == raw && $0.activityID == activityID }
        ))
        guard rows.count <= 1 else { throw ActivityContractPersistenceFailureV2.duplicateIdentity }
        return try rows.first?.value()
    }

    func transitions(workspaceID: WorkspaceID, activityID: UUID) throws -> [ActivityStateTransitionV2] {
        guard workspaceID == self.workspaceID else { return [] }
        let raw = workspaceID.rawValue
        return try modelContext.fetch(FetchDescriptor<ActivityStateTransitionRow>(
            predicate: #Predicate { $0.workspaceID == raw && $0.activityID == activityID }
        )).map { try $0.value() }.sorted {
            $0.revision == $1.revision
                ? $0.transitionID.uuidString < $1.transitionID.uuidString
                : $0.revision < $1.revision
        }
    }

    func installationTaskResults(workspaceID: WorkspaceID, activityID: UUID) throws -> [InstallationTaskResultV1] {
        guard workspaceID == self.workspaceID else { return [] }
        let raw = workspaceID.rawValue
        return try modelContext.fetch(FetchDescriptor<InstallationTaskResultRow>(
            predicate: #Predicate { $0.workspaceID == raw && $0.activityID == activityID }
        )).map { try $0.value() }.sorted()
    }

    func installationAsBuiltSnapshots(workspaceID: WorkspaceID, activityID: UUID) throws -> [InstallationAsBuiltSnapshotV1] {
        guard workspaceID == self.workspaceID else { return [] }
        let raw = workspaceID.rawValue
        return try modelContext.fetch(FetchDescriptor<InstallationAsBuiltSnapshotRow>(
            predicate: #Predicate { $0.workspaceID == raw && $0.activityID == activityID }
        )).map { try $0.value() }.sorted { $0.revision < $1.revision }
    }

    func punchReviewBasisSnapshots(workspaceID: WorkspaceID, activityID: UUID) throws -> [PunchReviewBasisSnapshotV1] {
        guard workspaceID == self.workspaceID else { return [] }
        let raw = workspaceID.rawValue
        return try modelContext.fetch(FetchDescriptor<PunchReviewBasisSnapshotRow>(
            predicate: #Predicate { $0.workspaceID == raw && $0.activityID == activityID }
        )).map { try $0.value() }.sorted { $0.revision < $1.revision }
    }
}

extension ActivityContractRowQueryV2: ActivityContractCurrentStateQueryingV2 {
    func currentActivityContract(
        workspaceID: WorkspaceID,
        activityID: UUID
    ) async throws -> ActivityContractCurrentStateV2? {
        guard workspaceID == self.workspaceID,
              let currentRevisionProvider else { return nil }
        let current = try currentRevisionProvider()
        guard current.workspaceID == workspaceID else {
            throw WorkspaceMutationFailureV1.wrongWorkspace
        }
        let envelope = try currentEnvelope(workspaceID: workspaceID, activityID: activityID)
        let identity = try WorkspaceEntityIdentityV1(
            kind: .activitySessionEnvelope, id: activityID
        )
        var entityRevisions = current.entityRevisions
        if envelope == nil && !entityRevisions.contains(where: { $0.identity == identity }) {
            entityRevisions.append(WorkspaceEntityRevisionV1(identity: identity, revision: 0))
        }
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: current.workspaceID,
            generationID: current.generationID,
            writerInstanceID: current.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: entityRevisions
        )
        return try ActivityContractCurrentStateV2(
            workspaceID: workspaceID,
            activityID: activityID,
            expectedRevision: expected,
            envelope: envelope
        )
    }
}

enum C47ActivityContractPersistenceBoundaryV2 {
    static let persistentSchemaVersion = 36
    static let recordsSchemaVersion = 35
    static let durableModelCount = 6
    static let newlyEnrolledRows = [
        "ActivitySessionEnvelopeRow", "ActivityStateTransitionRow", "InstallationTaskResultRow",
        "InstallationAsBuiltSnapshotRow", "PunchReviewBasisSnapshotRow",
    ]
    static let reusedDurableFamily = "CompletedActivitySnapshotV2"
    static let nonpersistentConformanceReceipts = ActivityContractPersistenceEnrollmentV2.nonpersistentFamilies
    static let noPlanFallbackPersistent = false

    static func acceptsCanonicalRow(kind: ActivityKindV2) -> Bool {
        kind == .installation || kind == .punchReview
    }
}

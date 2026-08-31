import Foundation
import SwiftData

enum ReinspectionAndExceptionSchemaV1 {
    static let schemaVersion = 49
    static let predecessorSchemaVersion = 48
    static let durableModelCount = 4
    static let totalSchemaModelCount = 162
    static let usesIncumbentWorkspaceStore = true
    static let createsSecondStore = false
    static let queueItemsAreDerivedAndNotPersistent = true
    static let modelTypes: [any PersistentModel.Type] = [
        ReinspectionPlanRowV1.self, UnchangedAttestationRowV1.self,
        ExceptionQueueAcknowledgementRowV1.self, ReinspectionExceptionMutationReceiptRowV1.self,
    ]
}

enum ReinspectionExceptionRecordFamilyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case plan = "REINSPECTION_PLAN"
    case attestation = "REINSPECTION_UNCHANGED_ATTESTATION"
    case acknowledgement = "EXCEPTION_QUEUE_ACKNOWLEDGEMENT"
    case mutationReceipt = "REINSPECTION_EXCEPTION_MUTATION_RECEIPT"
}

enum ReinspectionExceptionPersistenceFailureV1: Error, Equatable, Sendable {
    case corruptRow, wrongPayload, staleRevision, receiptMismatch
}

private enum ReinspectionExceptionPersistenceCodecV1 {
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    static func data<T: Encodable>(_ value: T) throws -> Data { try WorkspaceMutationCanonicalV1.data(value) }
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }
    static func rowID(_ workspaceID: WorkspaceID, _ family: ReinspectionExceptionRecordFamilyV1,
                      _ rootID: String, _ revision: UInt64) -> String {
        "\(workspaceID.rawValue.uuidString.lowercased())|\(family.rawValue)|\(rootID)|\(String(format: "%020llu", revision))"
    }
    static func receiptRowID(_ value: ReinspectionExceptionMutationReceiptV1) -> String {
        "\(value.workspaceID.rawValue.uuidString.lowercased())|\(ReinspectionExceptionRecordFamilyV1.mutationReceipt.rawValue)|\(value.mutationID.rawValue.uuidString.lowercased())"
    }
    static func verify(_ command: ReinspectionExceptionMutationCommandV1, result: UInt64) throws {
        try command.validate(); let (next, overflow) = command.expectedRevision.workspaceRevision.addingReportingOverflow(1)
        guard !overflow, next == result else { throw ReinspectionExceptionPersistenceFailureV1.staleRevision }
    }
    static func verifyRestore(_ receipt: ReinspectionExceptionMutationReceiptV1, writerInstanceID: UUID,
                              workspaceID: UUID, mutationID: UUID, semanticSHA256: String) throws {
        try receipt.validate()
        guard writerInstanceID != zero, receipt.recoveryState == .receiptCommitted,
              receipt.workspaceID.rawValue == workspaceID, receipt.mutationID.rawValue == mutationID,
              receipt.semanticSHA256s == [semanticSHA256] else { throw ReinspectionExceptionPersistenceFailureV1.receiptMismatch }
    }
}

@Model final class ReinspectionPlanRowV1 {
    @Attribute(.unique) private(set) var rowID: String
    private(set) var recordFamilyRawValue: String; private(set) var planEventID: UUID; private(set) var planID: UUID
    private(set) var workspaceID: UUID; private(set) var revision: UInt64; private(set) var policyVersion: UInt64
    private(set) var mutationID: UUID; private(set) var canonicalSHA256: String; private(set) var canonicalData: Data
    private(set) var writerGenerationID: UUID; private(set) var writerInstanceID: UUID
    private(set) var priorWorkspaceRevision: UInt64; private(set) var resultingWorkspaceRevision: UInt64
    private(set) var recoveryStateRawValue: String; private(set) var receiptID: UUID?

    init(_ value: ReinspectionPlanV1, predecessor: ReinspectionPlanV1? = nil,
         resolver: any ReinspectionCanonicalSourceResolvingV1,
         command: ReinspectionExceptionMutationCommandV1,
         resultingWorkspaceRevision: UInt64) throws {
        try value.validate(predecessor: predecessor); try ReinspectionExceptionPersistenceCodecV1.verify(command, result: resultingWorkspaceRevision)
        for item in value.items { try item.prior.validateResolved(by: resolver); try item.current.validateResolved(by: resolver) }
        guard case let .putPlan(payload, boundPredecessor) = command.payload, payload == value,
              boundPredecessor == predecessor else { throw ReinspectionExceptionPersistenceFailureV1.wrongPayload }
        rowID = ReinspectionExceptionPersistenceCodecV1.rowID(value.workspaceID, .plan, value.planID.uuidString.lowercased(), value.revision)
        recordFamilyRawValue = ReinspectionExceptionRecordFamilyV1.plan.rawValue; planEventID = value.planEventID; planID = value.planID
        workspaceID = value.workspaceID.rawValue; revision = value.revision; policyVersion = value.policyVersion
        mutationID = value.mutationID.rawValue; canonicalSHA256 = value.planSHA256; canonicalData = try ReinspectionExceptionPersistenceCodecV1.data(value)
        writerGenerationID = command.expectedRevision.generationID; writerInstanceID = command.expectedRevision.writerInstanceID
        priorWorkspaceRevision = command.expectedRevision.workspaceRevision; self.resultingWorkspaceRevision = resultingWorkspaceRevision
        recoveryStateRawValue = ReinspectionExceptionRecoveryStateV1.effectCommittedAwaitingReceipt.rawValue; receiptID = nil
    }
    init(restoring value: ReinspectionPlanV1, receipt: ReinspectionExceptionMutationReceiptV1,
         writerInstanceID: UUID) throws {
        try value.validate(); try ReinspectionExceptionPersistenceCodecV1.verifyRestore(receipt, writerInstanceID: writerInstanceID,
            workspaceID: value.workspaceID.rawValue, mutationID: value.mutationID.rawValue, semanticSHA256: value.planSHA256)
        rowID = ReinspectionExceptionPersistenceCodecV1.rowID(value.workspaceID, .plan, value.planID.uuidString.lowercased(), value.revision)
        recordFamilyRawValue = ReinspectionExceptionRecordFamilyV1.plan.rawValue; planEventID = value.planEventID; planID = value.planID
        workspaceID = value.workspaceID.rawValue; revision = value.revision; policyVersion = value.policyVersion
        mutationID = value.mutationID.rawValue; canonicalSHA256 = value.planSHA256; canonicalData = try ReinspectionExceptionPersistenceCodecV1.data(value)
        writerGenerationID = receipt.generationID; self.writerInstanceID = writerInstanceID
        priorWorkspaceRevision = receipt.priorWorkspaceRevision; resultingWorkspaceRevision = receipt.resultingWorkspaceRevision
        recoveryStateRawValue = receipt.recoveryState.rawValue; receiptID = receipt.receiptID
    }
    func value() throws -> ReinspectionPlanV1 {
        let value = try ReinspectionExceptionPersistenceCodecV1.decode(ReinspectionPlanV1.self, from: canonicalData); try value.validate()
        guard recordFamilyRawValue == ReinspectionExceptionRecordFamilyV1.plan.rawValue,
              rowID == ReinspectionExceptionPersistenceCodecV1.rowID(value.workspaceID, .plan, value.planID.uuidString.lowercased(), value.revision),
              planEventID == value.planEventID, planID == value.planID, workspaceID == value.workspaceID.rawValue,
              revision == value.revision, policyVersion == value.policyVersion, mutationID == value.mutationID.rawValue,
              canonicalSHA256 == value.planSHA256 else { throw ReinspectionExceptionPersistenceFailureV1.corruptRow }; return value
    }
    func value(predecessor: ReinspectionPlanV1?) throws -> ReinspectionPlanV1 { let value = try value(); try value.validate(predecessor: predecessor); return value }
    func value(predecessor: ReinspectionPlanV1?, resolver: any ReinspectionCanonicalSourceResolvingV1) throws -> ReinspectionPlanV1 {
        let value = try value(); try value.validateResolved(predecessor: predecessor, by: resolver); return value
    }
    func markReceiptCommitted(_ receipt: ReinspectionExceptionMutationReceiptV1) throws { try commit(receipt, semantic: canonicalSHA256) }
    private func commit(_ receipt: ReinspectionExceptionMutationReceiptV1, semantic: String) throws {
        try receipt.validate(); guard receiptID == nil, receipt.semanticSHA256s == [semantic], receipt.workspaceID.rawValue == workspaceID,
            receipt.mutationID.rawValue == mutationID, receipt.generationID == writerGenerationID,
            receipt.priorWorkspaceRevision == priorWorkspaceRevision, receipt.resultingWorkspaceRevision == resultingWorkspaceRevision,
            receipt.recoveryState == .receiptCommitted else { throw ReinspectionExceptionPersistenceFailureV1.receiptMismatch }
        receiptID = receipt.receiptID; recoveryStateRawValue = receipt.recoveryState.rawValue
    }
}

@Model final class UnchangedAttestationRowV1 {
    @Attribute(.unique) private(set) var rowID: String
    private(set) var recordFamilyRawValue: String; private(set) var attestationID: UUID; private(set) var workspaceID: UUID
    private(set) var planID: UUID; private(set) var planRevision: UInt64; private(set) var sourceRevision: UInt64
    private(set) var mutationID: UUID; private(set) var canonicalSHA256: String; private(set) var canonicalData: Data
    private(set) var writerGenerationID: UUID; private(set) var writerInstanceID: UUID
    private(set) var priorWorkspaceRevision: UInt64; private(set) var resultingWorkspaceRevision: UInt64
    private(set) var recoveryStateRawValue: String; private(set) var receiptID: UUID?
    init(_ value: UnchangedAttestationV1, plan: ReinspectionPlanV1,
         resolver: any ReinspectionCanonicalSourceResolvingV1,
         command: ReinspectionExceptionMutationCommandV1, resultingWorkspaceRevision: UInt64) throws {
        try value.validate(plan: plan); try ReinspectionExceptionPersistenceCodecV1.verify(command, result: resultingWorkspaceRevision)
        try value.prior.validateResolved(by: resolver); try value.current.validateResolved(by: resolver)
        guard case let .recordAttestation(payload, boundPlan) = command.payload, payload == value, boundPlan == plan else { throw ReinspectionExceptionPersistenceFailureV1.wrongPayload }
        rowID = ReinspectionExceptionPersistenceCodecV1.rowID(value.workspaceID, .attestation, value.attestationID.uuidString.lowercased(), 1)
        recordFamilyRawValue = ReinspectionExceptionRecordFamilyV1.attestation.rawValue; attestationID = value.attestationID
        workspaceID = value.workspaceID.rawValue; planID = value.planID; planRevision = value.planRevision; sourceRevision = value.current.revision
        mutationID = value.mutationID.rawValue; canonicalSHA256 = value.attestationSHA256; canonicalData = try ReinspectionExceptionPersistenceCodecV1.data(value)
        writerGenerationID = command.expectedRevision.generationID; writerInstanceID = command.expectedRevision.writerInstanceID
        priorWorkspaceRevision = command.expectedRevision.workspaceRevision; self.resultingWorkspaceRevision = resultingWorkspaceRevision
        recoveryStateRawValue = ReinspectionExceptionRecoveryStateV1.effectCommittedAwaitingReceipt.rawValue; receiptID = nil
    }
    init(restoring value: UnchangedAttestationV1, receipt: ReinspectionExceptionMutationReceiptV1,
         writerInstanceID: UUID) throws {
        try value.validate(); try ReinspectionExceptionPersistenceCodecV1.verifyRestore(receipt, writerInstanceID: writerInstanceID,
            workspaceID: value.workspaceID.rawValue, mutationID: value.mutationID.rawValue, semanticSHA256: value.attestationSHA256)
        rowID = ReinspectionExceptionPersistenceCodecV1.rowID(value.workspaceID, .attestation, value.attestationID.uuidString.lowercased(), 1)
        recordFamilyRawValue = ReinspectionExceptionRecordFamilyV1.attestation.rawValue; attestationID = value.attestationID
        workspaceID = value.workspaceID.rawValue; planID = value.planID; planRevision = value.planRevision; sourceRevision = value.current.revision
        mutationID = value.mutationID.rawValue; canonicalSHA256 = value.attestationSHA256; canonicalData = try ReinspectionExceptionPersistenceCodecV1.data(value)
        writerGenerationID = receipt.generationID; self.writerInstanceID = writerInstanceID
        priorWorkspaceRevision = receipt.priorWorkspaceRevision; resultingWorkspaceRevision = receipt.resultingWorkspaceRevision
        recoveryStateRawValue = receipt.recoveryState.rawValue; receiptID = receipt.receiptID
    }
    func value() throws -> UnchangedAttestationV1 {
        let value = try ReinspectionExceptionPersistenceCodecV1.decode(UnchangedAttestationV1.self, from: canonicalData); try value.validate()
        guard recordFamilyRawValue == ReinspectionExceptionRecordFamilyV1.attestation.rawValue,
              rowID == ReinspectionExceptionPersistenceCodecV1.rowID(value.workspaceID, .attestation, value.attestationID.uuidString.lowercased(), 1),
              attestationID == value.attestationID, workspaceID == value.workspaceID.rawValue, planID == value.planID,
              planRevision == value.planRevision, sourceRevision == value.current.revision, mutationID == value.mutationID.rawValue,
              canonicalSHA256 == value.attestationSHA256 else { throw ReinspectionExceptionPersistenceFailureV1.corruptRow }; return value
    }
    func value(plan: ReinspectionPlanV1) throws -> UnchangedAttestationV1 { let value = try value(); try value.validate(plan: plan); return value }
    func value(plan: ReinspectionPlanV1, resolver: any ReinspectionCanonicalSourceResolvingV1) throws -> UnchangedAttestationV1 {
        let value = try value(); try value.validateResolved(plan: plan, by: resolver); return value
    }
    func markReceiptCommitted(_ receipt: ReinspectionExceptionMutationReceiptV1) throws {
        try receipt.validate(); guard receiptID == nil, receipt.semanticSHA256s == [canonicalSHA256], receipt.workspaceID.rawValue == workspaceID,
            receipt.mutationID.rawValue == mutationID, receipt.generationID == writerGenerationID,
            receipt.priorWorkspaceRevision == priorWorkspaceRevision, receipt.resultingWorkspaceRevision == resultingWorkspaceRevision,
            receipt.recoveryState == .receiptCommitted else { throw ReinspectionExceptionPersistenceFailureV1.receiptMismatch }
        receiptID = receipt.receiptID; recoveryStateRawValue = receipt.recoveryState.rawValue
    }
}

@Model final class ExceptionQueueAcknowledgementRowV1 {
    @Attribute(.unique) private(set) var rowID: String
    private(set) var recordFamilyRawValue: String; private(set) var acknowledgementID: UUID; private(set) var workspaceID: UUID
    private(set) var logicalExceptionKey: String; private(set) var sourceRevision: UInt64; private(set) var sourceEvidenceSHA256: String; private(set) var revision: UInt64
    private(set) var mutationID: UUID; private(set) var canonicalSHA256: String; private(set) var canonicalData: Data
    private(set) var writerGenerationID: UUID; private(set) var writerInstanceID: UUID
    private(set) var priorWorkspaceRevision: UInt64; private(set) var resultingWorkspaceRevision: UInt64
    private(set) var recoveryStateRawValue: String; private(set) var receiptID: UUID?
    init(_ value: ExceptionQueueAcknowledgementV1, source: ExceptionQueueSourceSnapshotV1,
         predecessor: ExceptionQueueAcknowledgementV1? = nil,
         resolver: any ExceptionQueueCanonicalSourceResolvingV1,
         command: ReinspectionExceptionMutationCommandV1, resultingWorkspaceRevision: UInt64) throws {
        try value.validate(source: source, predecessor: predecessor); try ReinspectionExceptionPersistenceCodecV1.verify(command, result: resultingWorkspaceRevision)
        try source.validateResolved(by: resolver)
        guard case let .recordAcknowledgement(payload, boundSource, boundPredecessor) = command.payload,
              payload == value, boundSource == source, boundPredecessor == predecessor else { throw ReinspectionExceptionPersistenceFailureV1.wrongPayload }
        rowID = ReinspectionExceptionPersistenceCodecV1.rowID(value.workspaceID, .acknowledgement, value.logicalExceptionKey, value.revision)
        recordFamilyRawValue = ReinspectionExceptionRecordFamilyV1.acknowledgement.rawValue; acknowledgementID = value.acknowledgementID
        workspaceID = value.workspaceID.rawValue; logicalExceptionKey = value.logicalExceptionKey; sourceRevision = value.sourceRevision
        sourceEvidenceSHA256 = value.evidenceSHA256; revision = value.revision
        mutationID = value.mutationID.rawValue; canonicalSHA256 = value.acknowledgementSHA256; canonicalData = try ReinspectionExceptionPersistenceCodecV1.data(value)
        writerGenerationID = command.expectedRevision.generationID; writerInstanceID = command.expectedRevision.writerInstanceID
        priorWorkspaceRevision = command.expectedRevision.workspaceRevision; self.resultingWorkspaceRevision = resultingWorkspaceRevision
        recoveryStateRawValue = ReinspectionExceptionRecoveryStateV1.effectCommittedAwaitingReceipt.rawValue; receiptID = nil
    }
    init(restoring value: ExceptionQueueAcknowledgementV1, receipt: ReinspectionExceptionMutationReceiptV1,
         writerInstanceID: UUID) throws {
        try value.validate(); try ReinspectionExceptionPersistenceCodecV1.verifyRestore(receipt, writerInstanceID: writerInstanceID,
            workspaceID: value.workspaceID.rawValue, mutationID: value.mutationID.rawValue, semanticSHA256: value.acknowledgementSHA256)
        rowID = ReinspectionExceptionPersistenceCodecV1.rowID(value.workspaceID, .acknowledgement, value.logicalExceptionKey, value.revision)
        recordFamilyRawValue = ReinspectionExceptionRecordFamilyV1.acknowledgement.rawValue; acknowledgementID = value.acknowledgementID
        workspaceID = value.workspaceID.rawValue; logicalExceptionKey = value.logicalExceptionKey; sourceRevision = value.sourceRevision
        sourceEvidenceSHA256 = value.evidenceSHA256; revision = value.revision
        mutationID = value.mutationID.rawValue; canonicalSHA256 = value.acknowledgementSHA256; canonicalData = try ReinspectionExceptionPersistenceCodecV1.data(value)
        writerGenerationID = receipt.generationID; self.writerInstanceID = writerInstanceID
        priorWorkspaceRevision = receipt.priorWorkspaceRevision; resultingWorkspaceRevision = receipt.resultingWorkspaceRevision
        recoveryStateRawValue = receipt.recoveryState.rawValue; receiptID = receipt.receiptID
    }
    func value() throws -> ExceptionQueueAcknowledgementV1 {
        let value = try ReinspectionExceptionPersistenceCodecV1.decode(ExceptionQueueAcknowledgementV1.self, from: canonicalData); try value.validate()
        guard recordFamilyRawValue == ReinspectionExceptionRecordFamilyV1.acknowledgement.rawValue,
              rowID == ReinspectionExceptionPersistenceCodecV1.rowID(value.workspaceID, .acknowledgement, value.logicalExceptionKey, value.revision),
              acknowledgementID == value.acknowledgementID, workspaceID == value.workspaceID.rawValue,
              logicalExceptionKey == value.logicalExceptionKey, sourceRevision == value.sourceRevision,
              sourceEvidenceSHA256 == value.evidenceSHA256, revision == value.revision,
              mutationID == value.mutationID.rawValue, canonicalSHA256 == value.acknowledgementSHA256 else { throw ReinspectionExceptionPersistenceFailureV1.corruptRow }; return value
    }
    func value(source: ExceptionQueueSourceSnapshotV1, predecessor: ExceptionQueueAcknowledgementV1? = nil) throws -> ExceptionQueueAcknowledgementV1 {
        let value = try value(); try value.validate(source: source, predecessor: predecessor); return value
    }
    func value(source: ExceptionQueueSourceSnapshotV1, predecessor: ExceptionQueueAcknowledgementV1? = nil,
               resolver: any ExceptionQueueCanonicalSourceResolvingV1) throws -> ExceptionQueueAcknowledgementV1 {
        try source.validateResolved(by: resolver)
        let value = try value(); try value.validate(source: source, predecessor: predecessor); return value
    }
    func markReceiptCommitted(_ receipt: ReinspectionExceptionMutationReceiptV1) throws {
        try receipt.validate(); guard receiptID == nil, receipt.semanticSHA256s == [canonicalSHA256], receipt.workspaceID.rawValue == workspaceID,
            receipt.mutationID.rawValue == mutationID, receipt.generationID == writerGenerationID,
            receipt.priorWorkspaceRevision == priorWorkspaceRevision, receipt.resultingWorkspaceRevision == resultingWorkspaceRevision,
            receipt.recoveryState == .receiptCommitted else { throw ReinspectionExceptionPersistenceFailureV1.receiptMismatch }
        receiptID = receipt.receiptID; recoveryStateRawValue = receipt.recoveryState.rawValue
    }
}

@Model final class ReinspectionExceptionMutationReceiptRowV1 {
    @Attribute(.unique) private(set) var rowID: String
    private(set) var recordFamilyRawValue: String; private(set) var receiptID: UUID
    private(set) var workspaceID: UUID; private(set) var generationID: UUID; private(set) var mutationID: UUID
    private(set) var resultingWorkspaceRevision: UInt64; private(set) var canonicalSHA256: String; private(set) var canonicalData: Data
    init(_ value: ReinspectionExceptionMutationReceiptV1) throws {
        try value.validate(); guard value.recoveryState == .receiptCommitted else { throw ReinspectionExceptionPersistenceFailureV1.receiptMismatch }
        rowID = ReinspectionExceptionPersistenceCodecV1.receiptRowID(value); recordFamilyRawValue = ReinspectionExceptionRecordFamilyV1.mutationReceipt.rawValue
        receiptID = value.receiptID; workspaceID = value.workspaceID.rawValue; generationID = value.generationID
        mutationID = value.mutationID.rawValue; resultingWorkspaceRevision = value.resultingWorkspaceRevision
        canonicalSHA256 = value.receiptSHA256; canonicalData = try ReinspectionExceptionPersistenceCodecV1.data(value)
    }
    func value() throws -> ReinspectionExceptionMutationReceiptV1 {
        let value = try ReinspectionExceptionPersistenceCodecV1.decode(ReinspectionExceptionMutationReceiptV1.self, from: canonicalData); try value.validate()
        guard recordFamilyRawValue == ReinspectionExceptionRecordFamilyV1.mutationReceipt.rawValue,
              rowID == ReinspectionExceptionPersistenceCodecV1.receiptRowID(value), receiptID == value.receiptID,
              workspaceID == value.workspaceID.rawValue, generationID == value.generationID,
              mutationID == value.mutationID.rawValue, resultingWorkspaceRevision == value.resultingWorkspaceRevision,
              canonicalSHA256 == value.receiptSHA256 else { throw ReinspectionExceptionPersistenceFailureV1.corruptRow }; return value
    }
}

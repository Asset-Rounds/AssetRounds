import Foundation
import SwiftData

enum EvidenceQualitySchemaV1 {
    static let schemaVersion = 47
    static let predecessorSchemaVersion = 46
    static let durableModelCount = 4
    static let usesIncumbentWorkspaceStore = true
    static let createsSecondStore = false
    static let recordFamilies = EvidenceQualityRecordFamilyV1.allCases.map(\.rawValue).sorted()
    static let modelTypes: [any PersistentModel.Type] = [
        EvidenceQualityRuleSetRowV1.self,
        EvidenceQualityAssessmentRowV1.self,
        EvidenceQualityWaiverRowV1.self,
        EvidenceQualityMutationReceiptRowV1.self,
    ]
}

enum EvidenceQualityRecordFamilyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case ruleSet = "EVIDENCE_QUALITY_RULE_SET"
    case assessment = "EVIDENCE_QUALITY_ASSESSMENT"
    case waiver = "EVIDENCE_QUALITY_WAIVER"
    case mutationReceipt = "EVIDENCE_QUALITY_MUTATION_RECEIPT"
}

enum EvidenceQualityPersistenceFailureV1: Error, Equatable, Sendable {
    case corruptRow
    case wrongRecordFamily
    case wrongWorkspace
    case duplicateIdentity
    case staleRevision
    case receiptMismatch
}

private enum EvidenceQualityPersistenceCodecV1 {
    static func data<T: Encodable>(_ value: T) throws -> Data {
        try WorkspaceMutationCanonicalV1.data(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }

    static func workspaceKey(_ workspaceID: WorkspaceID) -> String {
        workspaceID.rawValue.uuidString.lowercased()
    }

    static func rowID(workspaceID: WorkspaceID, family: EvidenceQualityRecordFamilyV1,
                      rootID: UUID, revision: UInt64) -> String {
        "\(workspaceKey(workspaceID))|\(family.rawValue)|\(rootID.uuidString.lowercased())|\(String(format: "%020llu", revision))"
    }

    static func receiptRowID(workspaceID: WorkspaceID, mutationID: MutationIDV1) -> String {
        "\(workspaceKey(workspaceID))|\(EvidenceQualityRecordFamilyV1.mutationReceipt.rawValue)|\(mutationID.rawValue.uuidString.lowercased())"
    }

    static func verifyRecovery(command: EvidenceQualityMutationCommandV1,
                               resultingWorkspaceRevision: UInt64) throws {
        try command.validate()
        let (next, overflow) = command.expectedRevision.workspaceRevision.addingReportingOverflow(1)
        guard !overflow, next == resultingWorkspaceRevision else {
            throw EvidenceQualityPersistenceFailureV1.staleRevision
        }
    }

    static func verifyReceipt(_ receipt: EvidenceQualityMutationReceiptV1,
                              mutationID: UUID, semanticSHA256: String,
                              workspaceID: UUID, generationID: UUID,
                              priorWorkspaceRevision: UInt64,
                              resultingWorkspaceRevision: UInt64) throws {
        try receipt.validate()
        guard receipt.mutationID.rawValue == mutationID,
              receipt.semanticSHA256 == semanticSHA256,
              receipt.workspaceID.rawValue == workspaceID,
              receipt.generationID == generationID,
              receipt.priorWorkspaceRevision == priorWorkspaceRevision,
              receipt.resultingWorkspaceRevision == resultingWorkspaceRevision,
              receipt.recoveryState == .receiptCommitted else {
            throw EvidenceQualityPersistenceFailureV1.receiptMismatch
        }
    }

    static func verifyRestore(_ receipt: EvidenceQualityMutationReceiptV1,
                              writerInstanceID: UUID, mutationID: UUID,
                              semanticSHA256: String, workspaceID: UUID) throws {
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        guard writerInstanceID != zero else { throw EvidenceQualityPersistenceFailureV1.corruptRow }
        try verifyReceipt(receipt, mutationID: mutationID, semanticSHA256: semanticSHA256,
            workspaceID: workspaceID, generationID: receipt.generationID,
            priorWorkspaceRevision: receipt.priorWorkspaceRevision,
            resultingWorkspaceRevision: receipt.resultingWorkspaceRevision)
    }
}

@Model
final class EvidenceQualityRuleSetRowV1 {
    @Attribute(.unique) private(set) var rowID: String
    private(set) var recordFamilyRawValue: String
    private(set) var ruleSetID: UUID
    private(set) var workspaceID: UUID
    private(set) var revision: UInt64
    private(set) var mutationID: UUID
    private(set) var canonicalSHA256: String
    private(set) var canonicalData: Data
    private(set) var writerGenerationID: UUID
    private(set) var writerInstanceID: UUID
    private(set) var priorWorkspaceRevision: UInt64
    private(set) var resultingWorkspaceRevision: UInt64
    private(set) var recoveryStateRawValue: String
    private(set) var receiptID: UUID?

    init(_ value: EvidenceQualityRuleSetV1, command: EvidenceQualityMutationCommandV1,
         resultingWorkspaceRevision: UInt64) throws {
        try value.validate(); try EvidenceQualityPersistenceCodecV1.verifyRecovery(
            command: command, resultingWorkspaceRevision: resultingWorkspaceRevision)
        guard case let .putRuleSet(payload) = command.payload, payload == value else {
            throw EvidenceQualityPersistenceFailureV1.receiptMismatch
        }
        rowID = EvidenceQualityPersistenceCodecV1.rowID(workspaceID: value.workspaceID,
            family: .ruleSet, rootID: value.ruleSetID, revision: value.revision)
        recordFamilyRawValue = EvidenceQualityRecordFamilyV1.ruleSet.rawValue
        ruleSetID = value.ruleSetID; workspaceID = value.workspaceID.rawValue
        revision = value.revision; mutationID = value.mutationID.rawValue
        canonicalSHA256 = value.ruleSetSHA256
        canonicalData = try EvidenceQualityPersistenceCodecV1.data(value)
        writerGenerationID = command.expectedRevision.generationID
        writerInstanceID = command.expectedRevision.writerInstanceID
        priorWorkspaceRevision = command.expectedRevision.workspaceRevision
        self.resultingWorkspaceRevision = resultingWorkspaceRevision
        recoveryStateRawValue = EvidenceQualityReceiptRecoveryStateV1.effectCommittedAwaitingReceipt.rawValue
        receiptID = nil
    }

    init(restoring value: EvidenceQualityRuleSetV1,
         receipt: EvidenceQualityMutationReceiptV1, writerInstanceID: UUID) throws {
        try value.validate()
        try EvidenceQualityPersistenceCodecV1.verifyRestore(receipt,
            writerInstanceID: writerInstanceID, mutationID: value.mutationID.rawValue,
            semanticSHA256: value.ruleSetSHA256, workspaceID: value.workspaceID.rawValue)
        rowID = EvidenceQualityPersistenceCodecV1.rowID(workspaceID: value.workspaceID,
            family: .ruleSet, rootID: value.ruleSetID, revision: value.revision)
        recordFamilyRawValue = EvidenceQualityRecordFamilyV1.ruleSet.rawValue
        ruleSetID = value.ruleSetID; workspaceID = value.workspaceID.rawValue
        revision = value.revision; mutationID = value.mutationID.rawValue
        canonicalSHA256 = value.ruleSetSHA256
        canonicalData = try EvidenceQualityPersistenceCodecV1.data(value)
        writerGenerationID = receipt.generationID; self.writerInstanceID = writerInstanceID
        priorWorkspaceRevision = receipt.priorWorkspaceRevision
        resultingWorkspaceRevision = receipt.resultingWorkspaceRevision
        recoveryStateRawValue = EvidenceQualityReceiptRecoveryStateV1.receiptCommitted.rawValue
        receiptID = receipt.receiptID
    }

    func value() throws -> EvidenceQualityRuleSetV1 {
        let value = try EvidenceQualityPersistenceCodecV1.decode(EvidenceQualityRuleSetV1.self, from: canonicalData)
        try value.validate()
        guard recordFamilyRawValue == EvidenceQualityRecordFamilyV1.ruleSet.rawValue,
              rowID == EvidenceQualityPersistenceCodecV1.rowID(workspaceID: value.workspaceID,
                family: .ruleSet, rootID: value.ruleSetID, revision: value.revision),
              ruleSetID == value.ruleSetID, workspaceID == value.workspaceID.rawValue,
              revision == value.revision, mutationID == value.mutationID.rawValue,
              canonicalSHA256 == value.ruleSetSHA256 else { throw EvidenceQualityPersistenceFailureV1.corruptRow }
        return value
    }

    func markReceiptCommitted(_ receipt: EvidenceQualityMutationReceiptV1) throws {
        try EvidenceQualityPersistenceCodecV1.verifyReceipt(receipt, mutationID: mutationID,
            semanticSHA256: canonicalSHA256, workspaceID: workspaceID, generationID: writerGenerationID,
            priorWorkspaceRevision: priorWorkspaceRevision, resultingWorkspaceRevision: resultingWorkspaceRevision)
        guard self.receiptID == nil,
              recoveryStateRawValue == EvidenceQualityReceiptRecoveryStateV1.effectCommittedAwaitingReceipt.rawValue else {
            throw EvidenceQualityPersistenceFailureV1.duplicateIdentity
        }
        self.receiptID = receipt.receiptID
        recoveryStateRawValue = EvidenceQualityReceiptRecoveryStateV1.receiptCommitted.rawValue
    }
}

@Model
final class EvidenceQualityAssessmentRowV1 {
    @Attribute(.unique) private(set) var rowID: String
    private(set) var recordFamilyRawValue: String
    private(set) var assessmentID: UUID
    private(set) var workspaceID: UUID
    private(set) var evidenceID: String
    private(set) var evidenceRevision: UInt64
    private(set) var contentSHA256: String
    private(set) var revision: UInt64
    private(set) var mutationID: UUID
    private(set) var canonicalSHA256: String
    private(set) var canonicalData: Data
    private(set) var writerGenerationID: UUID
    private(set) var writerInstanceID: UUID
    private(set) var priorWorkspaceRevision: UInt64
    private(set) var resultingWorkspaceRevision: UInt64
    private(set) var recoveryStateRawValue: String
    private(set) var receiptID: UUID?

    init(_ value: EvidenceQualityAssessmentV1, ruleSet: EvidenceQualityRuleSetV1,
         command: EvidenceQualityMutationCommandV1, resultingWorkspaceRevision: UInt64) throws {
        try value.validate(ruleSet: ruleSet); try EvidenceQualityPersistenceCodecV1.verifyRecovery(
            command: command, resultingWorkspaceRevision: resultingWorkspaceRevision)
        guard case let .recordAssessment(payload) = command.payload, payload == value else {
            throw EvidenceQualityPersistenceFailureV1.receiptMismatch
        }
        rowID = EvidenceQualityPersistenceCodecV1.rowID(workspaceID: value.workspaceID,
            family: .assessment, rootID: value.assessmentID, revision: value.revision)
        recordFamilyRawValue = EvidenceQualityRecordFamilyV1.assessment.rawValue
        assessmentID = value.assessmentID; workspaceID = value.workspaceID.rawValue
        evidenceID = value.evidence.evidenceID; evidenceRevision = value.evidence.evidenceRevision
        contentSHA256 = value.evidence.contentSHA256; revision = value.revision
        mutationID = value.mutationID.rawValue; canonicalSHA256 = value.assessmentSHA256
        canonicalData = try EvidenceQualityPersistenceCodecV1.data(value)
        writerGenerationID = command.expectedRevision.generationID
        writerInstanceID = command.expectedRevision.writerInstanceID
        priorWorkspaceRevision = command.expectedRevision.workspaceRevision
        self.resultingWorkspaceRevision = resultingWorkspaceRevision
        recoveryStateRawValue = EvidenceQualityReceiptRecoveryStateV1.effectCommittedAwaitingReceipt.rawValue
        receiptID = nil
    }

    init(restoring value: EvidenceQualityAssessmentV1, ruleSet: EvidenceQualityRuleSetV1,
         receipt: EvidenceQualityMutationReceiptV1, writerInstanceID: UUID) throws {
        try value.validate(ruleSet: ruleSet)
        try EvidenceQualityPersistenceCodecV1.verifyRestore(receipt,
            writerInstanceID: writerInstanceID, mutationID: value.mutationID.rawValue,
            semanticSHA256: value.assessmentSHA256, workspaceID: value.workspaceID.rawValue)
        rowID = EvidenceQualityPersistenceCodecV1.rowID(workspaceID: value.workspaceID,
            family: .assessment, rootID: value.assessmentID, revision: value.revision)
        recordFamilyRawValue = EvidenceQualityRecordFamilyV1.assessment.rawValue
        assessmentID = value.assessmentID; workspaceID = value.workspaceID.rawValue
        evidenceID = value.evidence.evidenceID; evidenceRevision = value.evidence.evidenceRevision
        contentSHA256 = value.evidence.contentSHA256; revision = value.revision
        mutationID = value.mutationID.rawValue; canonicalSHA256 = value.assessmentSHA256
        canonicalData = try EvidenceQualityPersistenceCodecV1.data(value)
        writerGenerationID = receipt.generationID; self.writerInstanceID = writerInstanceID
        priorWorkspaceRevision = receipt.priorWorkspaceRevision
        resultingWorkspaceRevision = receipt.resultingWorkspaceRevision
        recoveryStateRawValue = EvidenceQualityReceiptRecoveryStateV1.receiptCommitted.rawValue
        receiptID = receipt.receiptID
    }

    func value(ruleSet: EvidenceQualityRuleSetV1) throws -> EvidenceQualityAssessmentV1 {
        let value = try EvidenceQualityPersistenceCodecV1.decode(EvidenceQualityAssessmentV1.self, from: canonicalData)
        try value.validate(ruleSet: ruleSet)
        guard recordFamilyRawValue == EvidenceQualityRecordFamilyV1.assessment.rawValue,
              rowID == EvidenceQualityPersistenceCodecV1.rowID(workspaceID: value.workspaceID,
                family: .assessment, rootID: value.assessmentID, revision: value.revision),
              assessmentID == value.assessmentID, workspaceID == value.workspaceID.rawValue,
              evidenceID == value.evidence.evidenceID, evidenceRevision == value.evidence.evidenceRevision,
              contentSHA256 == value.evidence.contentSHA256, revision == value.revision,
              mutationID == value.mutationID.rawValue, canonicalSHA256 == value.assessmentSHA256 else {
            throw EvidenceQualityPersistenceFailureV1.corruptRow
        }
        return value
    }

    func markReceiptCommitted(_ receipt: EvidenceQualityMutationReceiptV1) throws {
        try EvidenceQualityPersistenceCodecV1.verifyReceipt(receipt, mutationID: mutationID,
            semanticSHA256: canonicalSHA256, workspaceID: workspaceID, generationID: writerGenerationID,
            priorWorkspaceRevision: priorWorkspaceRevision, resultingWorkspaceRevision: resultingWorkspaceRevision)
        guard self.receiptID == nil,
              recoveryStateRawValue == EvidenceQualityReceiptRecoveryStateV1.effectCommittedAwaitingReceipt.rawValue else {
            throw EvidenceQualityPersistenceFailureV1.duplicateIdentity
        }
        self.receiptID = receipt.receiptID
        recoveryStateRawValue = EvidenceQualityReceiptRecoveryStateV1.receiptCommitted.rawValue
    }
}

@Model
final class EvidenceQualityWaiverRowV1 {
    @Attribute(.unique) private(set) var rowID: String
    private(set) var recordFamilyRawValue: String
    private(set) var waiverEventID: UUID
    private(set) var waiverID: UUID
    private(set) var workspaceID: UUID
    private(set) var assessmentID: UUID
    private(set) var evidenceID: String
    private(set) var evidenceRevision: UInt64
    private(set) var revision: UInt64
    private(set) var mutationID: UUID
    private(set) var canonicalSHA256: String
    private(set) var canonicalData: Data
    private(set) var writerGenerationID: UUID
    private(set) var writerInstanceID: UUID
    private(set) var priorWorkspaceRevision: UInt64
    private(set) var resultingWorkspaceRevision: UInt64
    private(set) var recoveryStateRawValue: String
    private(set) var receiptID: UUID?

    init(_ value: EvidenceQualityWaiverV1, assessment: EvidenceQualityAssessmentV1,
         command: EvidenceQualityMutationCommandV1, resultingWorkspaceRevision: UInt64) throws {
        try value.validate(assessment: assessment); try EvidenceQualityPersistenceCodecV1.verifyRecovery(
            command: command, resultingWorkspaceRevision: resultingWorkspaceRevision)
        guard case let .recordWaiver(payload) = command.payload, payload == value else {
            throw EvidenceQualityPersistenceFailureV1.receiptMismatch
        }
        rowID = EvidenceQualityPersistenceCodecV1.rowID(workspaceID: value.workspaceID,
            family: .waiver, rootID: value.waiverID, revision: value.revision)
        recordFamilyRawValue = EvidenceQualityRecordFamilyV1.waiver.rawValue
        waiverEventID = value.waiverEventID; waiverID = value.waiverID
        workspaceID = value.workspaceID.rawValue; assessmentID = value.assessmentID
        evidenceID = value.evidence.evidenceID; evidenceRevision = value.evidence.evidenceRevision
        revision = value.revision; mutationID = value.mutationID.rawValue
        canonicalSHA256 = value.waiverSHA256
        canonicalData = try EvidenceQualityPersistenceCodecV1.data(value)
        writerGenerationID = command.expectedRevision.generationID
        writerInstanceID = command.expectedRevision.writerInstanceID
        priorWorkspaceRevision = command.expectedRevision.workspaceRevision
        self.resultingWorkspaceRevision = resultingWorkspaceRevision
        recoveryStateRawValue = EvidenceQualityReceiptRecoveryStateV1.effectCommittedAwaitingReceipt.rawValue
        receiptID = nil
    }

    init(restoring value: EvidenceQualityWaiverV1, assessment: EvidenceQualityAssessmentV1,
         receipt: EvidenceQualityMutationReceiptV1, writerInstanceID: UUID) throws {
        try value.validate(assessment: assessment)
        try EvidenceQualityPersistenceCodecV1.verifyRestore(receipt,
            writerInstanceID: writerInstanceID, mutationID: value.mutationID.rawValue,
            semanticSHA256: value.waiverSHA256, workspaceID: value.workspaceID.rawValue)
        rowID = EvidenceQualityPersistenceCodecV1.rowID(workspaceID: value.workspaceID,
            family: .waiver, rootID: value.waiverID, revision: value.revision)
        recordFamilyRawValue = EvidenceQualityRecordFamilyV1.waiver.rawValue
        waiverEventID = value.waiverEventID; waiverID = value.waiverID
        workspaceID = value.workspaceID.rawValue; assessmentID = value.assessmentID
        evidenceID = value.evidence.evidenceID; evidenceRevision = value.evidence.evidenceRevision
        revision = value.revision; mutationID = value.mutationID.rawValue
        canonicalSHA256 = value.waiverSHA256
        canonicalData = try EvidenceQualityPersistenceCodecV1.data(value)
        writerGenerationID = receipt.generationID; self.writerInstanceID = writerInstanceID
        priorWorkspaceRevision = receipt.priorWorkspaceRevision
        resultingWorkspaceRevision = receipt.resultingWorkspaceRevision
        recoveryStateRawValue = EvidenceQualityReceiptRecoveryStateV1.receiptCommitted.rawValue
        receiptID = receipt.receiptID
    }

    func value(assessment: EvidenceQualityAssessmentV1) throws -> EvidenceQualityWaiverV1 {
        let value = try EvidenceQualityPersistenceCodecV1.decode(EvidenceQualityWaiverV1.self, from: canonicalData)
        try value.validate(assessment: assessment)
        guard recordFamilyRawValue == EvidenceQualityRecordFamilyV1.waiver.rawValue,
              rowID == EvidenceQualityPersistenceCodecV1.rowID(workspaceID: value.workspaceID,
                family: .waiver, rootID: value.waiverID, revision: value.revision),
              waiverEventID == value.waiverEventID, waiverID == value.waiverID,
              workspaceID == value.workspaceID.rawValue, assessmentID == value.assessmentID,
              evidenceID == value.evidence.evidenceID, evidenceRevision == value.evidence.evidenceRevision,
              revision == value.revision, mutationID == value.mutationID.rawValue,
              canonicalSHA256 == value.waiverSHA256 else { throw EvidenceQualityPersistenceFailureV1.corruptRow }
        return value
    }

    func markReceiptCommitted(_ receipt: EvidenceQualityMutationReceiptV1) throws {
        try EvidenceQualityPersistenceCodecV1.verifyReceipt(receipt, mutationID: mutationID,
            semanticSHA256: canonicalSHA256, workspaceID: workspaceID, generationID: writerGenerationID,
            priorWorkspaceRevision: priorWorkspaceRevision, resultingWorkspaceRevision: resultingWorkspaceRevision)
        guard self.receiptID == nil,
              recoveryStateRawValue == EvidenceQualityReceiptRecoveryStateV1.effectCommittedAwaitingReceipt.rawValue else {
            throw EvidenceQualityPersistenceFailureV1.duplicateIdentity
        }
        self.receiptID = receipt.receiptID
        recoveryStateRawValue = EvidenceQualityReceiptRecoveryStateV1.receiptCommitted.rawValue
    }
}

@Model
final class EvidenceQualityMutationReceiptRowV1 {
    @Attribute(.unique) private(set) var rowID: String
    private(set) var recordFamilyRawValue: String
    private(set) var receiptID: UUID
    private(set) var workspaceID: UUID
    private(set) var generationID: UUID
    private(set) var mutationID: UUID
    private(set) var resultingWorkspaceRevision: UInt64
    private(set) var canonicalSHA256: String
    private(set) var canonicalData: Data

    init(_ value: EvidenceQualityMutationReceiptV1) throws {
        try value.validate()
        guard value.recoveryState == .receiptCommitted else {
            throw EvidenceQualityPersistenceFailureV1.receiptMismatch
        }
        rowID = EvidenceQualityPersistenceCodecV1.receiptRowID(workspaceID: value.workspaceID, mutationID: value.mutationID)
        recordFamilyRawValue = EvidenceQualityRecordFamilyV1.mutationReceipt.rawValue
        receiptID = value.receiptID; workspaceID = value.workspaceID.rawValue
        generationID = value.generationID; mutationID = value.mutationID.rawValue
        resultingWorkspaceRevision = value.resultingWorkspaceRevision
        canonicalSHA256 = value.receiptSHA256
        canonicalData = try EvidenceQualityPersistenceCodecV1.data(value)
    }

    func value() throws -> EvidenceQualityMutationReceiptV1 {
        let value = try EvidenceQualityPersistenceCodecV1.decode(EvidenceQualityMutationReceiptV1.self, from: canonicalData)
        try value.validate()
        guard recordFamilyRawValue == EvidenceQualityRecordFamilyV1.mutationReceipt.rawValue,
              rowID == EvidenceQualityPersistenceCodecV1.receiptRowID(workspaceID: value.workspaceID, mutationID: value.mutationID),
              receiptID == value.receiptID, workspaceID == value.workspaceID.rawValue,
              generationID == value.generationID, mutationID == value.mutationID.rawValue,
              resultingWorkspaceRevision == value.resultingWorkspaceRevision,
              canonicalSHA256 == value.receiptSHA256,
              value.recoveryState == .receiptCommitted else { throw EvidenceQualityPersistenceFailureV1.corruptRow }
        return value
    }
}

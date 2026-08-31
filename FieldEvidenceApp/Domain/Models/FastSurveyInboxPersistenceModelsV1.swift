import Foundation
import SwiftData

enum FastSurveyInboxSchemaV1 {
    static let schemaVersion = 48
    static let predecessorSchemaVersion = 47
    static let durableModelCount = 5
    static let totalSchemaModelCount = 158
    static let usesIncumbentWorkspaceStore = true
    static let createsSecondStore = false
    static let modelTypes: [any PersistentModel.Type] = [
        CaptureInboxItemRowV1.self, CapturePromotionRowV1.self,
        SnippetRowV1.self, SnippetInsertionHistoryRowV1.self,
        FastSurveyInboxMutationReceiptRowV1.self,
    ]
}

enum FastSurveyInboxRecordFamilyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case inboxItem = "FAST_SURVEY_INBOX_ITEM"
    case promotion = "FAST_SURVEY_CAPTURE_PROMOTION"
    case snippet = "FAST_SURVEY_SNIPPET"
    case snippetInsertion = "FAST_SURVEY_SNIPPET_INSERTION"
    case mutationReceipt = "FAST_SURVEY_MUTATION_RECEIPT"
}

enum FastSurveyInboxPersistenceFailureV1: Error, Equatable, Sendable {
    case corruptRow, wrongPayload, staleRevision, receiptMismatch, duplicateIdentity
}

private enum FastSurveyInboxPersistenceCodecV1 {
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    static func data<T: Encodable>(_ value: T) throws -> Data { try WorkspaceMutationCanonicalV1.data(value) }
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }
    static func rowID(_ workspaceID: WorkspaceID, _ family: FastSurveyInboxRecordFamilyV1,
                      _ rootID: UUID, _ revision: UInt64) -> String {
        "\(workspaceID.rawValue.uuidString.lowercased())|\(family.rawValue)|\(rootID.uuidString.lowercased())|\(String(format: "%020llu", revision))"
    }
    static func receiptRowID(_ value: FastSurveyInboxMutationReceiptV1) -> String {
        "\(value.workspaceID.rawValue.uuidString.lowercased())|\(FastSurveyInboxRecordFamilyV1.mutationReceipt.rawValue)|\(value.mutationID.rawValue.uuidString.lowercased())"
    }
    static func contentSHA256(_ content: ContentReferenceV1) throws -> String {
        guard let value = content.digests.digest(for: .sha256)?.hexadecimalValue else {
            throw FastSurveyInboxPersistenceFailureV1.corruptRow
        }
        return value
    }
    static func verify(_ command: FastSurveyInboxMutationCommandV1, result: UInt64) throws {
        try command.validate(); let (next, overflow) = command.expectedRevision.workspaceRevision.addingReportingOverflow(1)
        guard !overflow, next == result else { throw FastSurveyInboxPersistenceFailureV1.staleRevision }
    }
    static func verifyRestore(_ receipt: FastSurveyInboxMutationReceiptV1, writerInstanceID: UUID,
                              workspaceID: UUID, mutationID: UUID, semanticSHA256s: [String]) throws {
        try receipt.validate()
        guard writerInstanceID != zero, receipt.recoveryState == .receiptCommitted,
              receipt.workspaceID.rawValue == workspaceID, receipt.mutationID.rawValue == mutationID,
              receipt.semanticSHA256s == semanticSHA256s.sorted() else {
            throw FastSurveyInboxPersistenceFailureV1.receiptMismatch
        }
    }
}

@Model final class CaptureInboxItemRowV1 {
    @Attribute(.unique) private(set) var rowID: String
    private(set) var recordFamilyRawValue: String; private(set) var inboxItemID: UUID
    private(set) var inboxEventID: UUID; private(set) var workspaceID: UUID
    private(set) var revision: UInt64; private(set) var stateRawValue: String; private(set) var captureRoleRawValue: String
    private(set) var contentID: String; private(set) var contentSHA256: String
    private(set) var companionPromotionSHA256: String?
    private(set) var mutationID: UUID; private(set) var canonicalSHA256: String; private(set) var canonicalData: Data
    private(set) var writerGenerationID: UUID; private(set) var writerInstanceID: UUID
    private(set) var priorWorkspaceRevision: UInt64; private(set) var resultingWorkspaceRevision: UInt64
    private(set) var recoveryStateRawValue: String; private(set) var receiptID: UUID?

    init(_ value: CaptureInboxItemV1, command: FastSurveyInboxMutationCommandV1,
         resultingWorkspaceRevision: UInt64) throws {
        try value.validate(); try FastSurveyInboxPersistenceCodecV1.verify(command, result: resultingWorkspaceRevision)
        let companionPromotionSHA256: String?
        switch command.payload {
        case let .putInboxItem(payload):
            guard payload == value else { throw FastSurveyInboxPersistenceFailureV1.wrongPayload }
            companionPromotionSHA256 = nil
        case let .promote(promotion, promoted):
            guard promoted == value else { throw FastSurveyInboxPersistenceFailureV1.wrongPayload }
            companionPromotionSHA256 = promotion.promotionSHA256
        case .putSnippet, .insertSnippet: throw FastSurveyInboxPersistenceFailureV1.wrongPayload
        }
        rowID = FastSurveyInboxPersistenceCodecV1.rowID(value.workspaceID, .inboxItem, value.inboxItemID, value.revision)
        recordFamilyRawValue = FastSurveyInboxRecordFamilyV1.inboxItem.rawValue
        inboxItemID = value.inboxItemID; inboxEventID = value.inboxEventID; workspaceID = value.workspaceID.rawValue
        revision = value.revision; stateRawValue = value.state.rawValue; captureRoleRawValue = value.captureRole.rawValue
        contentID = value.content.contentID
        contentSHA256 = try FastSurveyInboxPersistenceCodecV1.contentSHA256(value.content)
        self.companionPromotionSHA256 = companionPromotionSHA256
        mutationID = value.mutationID.rawValue; canonicalSHA256 = value.itemSHA256
        canonicalData = try FastSurveyInboxPersistenceCodecV1.data(value)
        writerGenerationID = command.expectedRevision.generationID; writerInstanceID = command.expectedRevision.writerInstanceID
        priorWorkspaceRevision = command.expectedRevision.workspaceRevision; self.resultingWorkspaceRevision = resultingWorkspaceRevision
        recoveryStateRawValue = FastSurveyInboxRecoveryStateV1.effectCommittedAwaitingReceipt.rawValue; receiptID = nil
    }

    init(restoring value: CaptureInboxItemV1, promotion: CapturePromotionV1? = nil,
         receipt: FastSurveyInboxMutationReceiptV1, writerInstanceID: UUID) throws {
        try value.validate()
        let semantics: [String]
        if value.state == .promoted {
            guard let promotion else { throw FastSurveyInboxPersistenceFailureV1.receiptMismatch }
            try promotion.validateIntrinsic(promotedItem: value)
            semantics = [value.itemSHA256, promotion.promotionSHA256]
        } else { guard promotion == nil else { throw FastSurveyInboxPersistenceFailureV1.wrongPayload }; semantics = [value.itemSHA256] }
        try FastSurveyInboxPersistenceCodecV1.verifyRestore(receipt, writerInstanceID: writerInstanceID,
            workspaceID: value.workspaceID.rawValue, mutationID: value.mutationID.rawValue, semanticSHA256s: semantics)
        rowID = FastSurveyInboxPersistenceCodecV1.rowID(value.workspaceID, .inboxItem, value.inboxItemID, value.revision)
        recordFamilyRawValue = FastSurveyInboxRecordFamilyV1.inboxItem.rawValue
        inboxItemID = value.inboxItemID; inboxEventID = value.inboxEventID; workspaceID = value.workspaceID.rawValue
        revision = value.revision; stateRawValue = value.state.rawValue; captureRoleRawValue = value.captureRole.rawValue
        contentID = value.content.contentID
        contentSHA256 = try FastSurveyInboxPersistenceCodecV1.contentSHA256(value.content)
        companionPromotionSHA256 = promotion?.promotionSHA256
        mutationID = value.mutationID.rawValue; canonicalSHA256 = value.itemSHA256
        canonicalData = try FastSurveyInboxPersistenceCodecV1.data(value)
        writerGenerationID = receipt.generationID; self.writerInstanceID = writerInstanceID
        priorWorkspaceRevision = receipt.priorWorkspaceRevision; resultingWorkspaceRevision = receipt.resultingWorkspaceRevision
        recoveryStateRawValue = receipt.recoveryState.rawValue; receiptID = receipt.receiptID
    }

    func value() throws -> CaptureInboxItemV1 {
        let value = try FastSurveyInboxPersistenceCodecV1.decode(CaptureInboxItemV1.self, from: canonicalData); try value.validate()
        guard recordFamilyRawValue == FastSurveyInboxRecordFamilyV1.inboxItem.rawValue,
              rowID == FastSurveyInboxPersistenceCodecV1.rowID(value.workspaceID, .inboxItem, value.inboxItemID, value.revision),
              inboxItemID == value.inboxItemID, inboxEventID == value.inboxEventID,
              workspaceID == value.workspaceID.rawValue, revision == value.revision,
              stateRawValue == value.state.rawValue, captureRoleRawValue == value.captureRole.rawValue,
              contentID == value.content.contentID,
              contentSHA256 == value.content.digests.digest(for: .sha256)?.hexadecimalValue,
              (value.state == .promoted) == (companionPromotionSHA256 != nil),
              mutationID == value.mutationID.rawValue, canonicalSHA256 == value.itemSHA256 else { throw FastSurveyInboxPersistenceFailureV1.corruptRow }
        return value
    }
    func markReceiptCommitted(_ receipt: FastSurveyInboxMutationReceiptV1) throws {
        let expected = ([canonicalSHA256] + (companionPromotionSHA256.map { [$0] } ?? [])).sorted()
        guard self.receiptID == nil, receipt.semanticSHA256s == expected,
              receipt.workspaceID.rawValue == workspaceID, receipt.mutationID.rawValue == mutationID,
              receipt.generationID == writerGenerationID, receipt.priorWorkspaceRevision == priorWorkspaceRevision,
              receipt.resultingWorkspaceRevision == resultingWorkspaceRevision,
              receipt.recoveryState == .receiptCommitted else { throw FastSurveyInboxPersistenceFailureV1.receiptMismatch }
        try receipt.validate(); receiptID = receipt.receiptID; recoveryStateRawValue = receipt.recoveryState.rawValue
    }
}

@Model final class CapturePromotionRowV1 {
    @Attribute(.unique) private(set) var rowID: String
    private(set) var recordFamilyRawValue: String; private(set) var promotionID: UUID
    private(set) var workspaceID: UUID; private(set) var sourceInboxItemID: UUID
    private(set) var destinationWorkspaceID: UUID; private(set) var destinationKindRawValue: String; private(set) var destinationID: UUID
    private(set) var destinationRevision: UInt64; private(set) var mutationID: UUID
    private(set) var promotedInboxSHA256: String
    private(set) var canonicalSHA256: String; private(set) var canonicalData: Data
    private(set) var writerGenerationID: UUID; private(set) var writerInstanceID: UUID
    private(set) var priorWorkspaceRevision: UInt64; private(set) var resultingWorkspaceRevision: UInt64
    private(set) var recoveryStateRawValue: String; private(set) var receiptID: UUID?

    init(_ value: CapturePromotionV1, source: CaptureInboxItemV1, promotedItem: CaptureInboxItemV1,
         command: FastSurveyInboxMutationCommandV1, resultingWorkspaceRevision: UInt64) throws {
        try value.validate(source: source, promotedItem: promotedItem)
        try FastSurveyInboxPersistenceCodecV1.verify(command, result: resultingWorkspaceRevision)
        guard case let .promote(promotion, item) = command.payload, promotion == value, item == promotedItem else { throw FastSurveyInboxPersistenceFailureV1.wrongPayload }
        rowID = FastSurveyInboxPersistenceCodecV1.rowID(value.workspaceID, .promotion, value.promotionID, value.revision)
        recordFamilyRawValue = FastSurveyInboxRecordFamilyV1.promotion.rawValue; promotionID = value.promotionID
        workspaceID = value.workspaceID.rawValue; sourceInboxItemID = value.sourceInboxItemID
        destinationWorkspaceID = value.destination.workspaceID.rawValue
        destinationKindRawValue = value.destination.kind.rawValue; destinationID = value.destination.destinationID
        destinationRevision = value.destination.destinationRevision; mutationID = value.mutationID.rawValue
        promotedInboxSHA256 = value.promotedInboxSHA256
        canonicalSHA256 = value.promotionSHA256; canonicalData = try FastSurveyInboxPersistenceCodecV1.data(value)
        writerGenerationID = command.expectedRevision.generationID; writerInstanceID = command.expectedRevision.writerInstanceID
        priorWorkspaceRevision = command.expectedRevision.workspaceRevision; self.resultingWorkspaceRevision = resultingWorkspaceRevision
        recoveryStateRawValue = FastSurveyInboxRecoveryStateV1.effectCommittedAwaitingReceipt.rawValue; receiptID = nil
    }

    init(restoring value: CapturePromotionV1, source: CaptureInboxItemV1, promotedItem: CaptureInboxItemV1,
         receipt: FastSurveyInboxMutationReceiptV1, writerInstanceID: UUID) throws {
        try value.validate(source: source, promotedItem: promotedItem)
        try FastSurveyInboxPersistenceCodecV1.verifyRestore(receipt, writerInstanceID: writerInstanceID,
            workspaceID: value.workspaceID.rawValue, mutationID: value.mutationID.rawValue,
            semanticSHA256s: [value.promotionSHA256, promotedItem.itemSHA256])
        rowID = FastSurveyInboxPersistenceCodecV1.rowID(value.workspaceID, .promotion, value.promotionID, value.revision)
        recordFamilyRawValue = FastSurveyInboxRecordFamilyV1.promotion.rawValue; promotionID = value.promotionID
        workspaceID = value.workspaceID.rawValue; sourceInboxItemID = value.sourceInboxItemID
        destinationWorkspaceID = value.destination.workspaceID.rawValue
        destinationKindRawValue = value.destination.kind.rawValue; destinationID = value.destination.destinationID
        destinationRevision = value.destination.destinationRevision; mutationID = value.mutationID.rawValue
        promotedInboxSHA256 = value.promotedInboxSHA256
        canonicalSHA256 = value.promotionSHA256; canonicalData = try FastSurveyInboxPersistenceCodecV1.data(value)
        writerGenerationID = receipt.generationID; self.writerInstanceID = writerInstanceID
        priorWorkspaceRevision = receipt.priorWorkspaceRevision; resultingWorkspaceRevision = receipt.resultingWorkspaceRevision
        recoveryStateRawValue = receipt.recoveryState.rawValue; receiptID = receipt.receiptID
    }
    func value(source: CaptureInboxItemV1, promotedItem: CaptureInboxItemV1) throws -> CapturePromotionV1 {
        let value = try FastSurveyInboxPersistenceCodecV1.decode(CapturePromotionV1.self, from: canonicalData)
        try value.validate(source: source, promotedItem: promotedItem)
        guard recordFamilyRawValue == FastSurveyInboxRecordFamilyV1.promotion.rawValue,
              rowID == FastSurveyInboxPersistenceCodecV1.rowID(value.workspaceID, .promotion, value.promotionID, value.revision),
              promotionID == value.promotionID, workspaceID == value.workspaceID.rawValue,
              sourceInboxItemID == value.sourceInboxItemID,
              destinationWorkspaceID == value.destination.workspaceID.rawValue,
              destinationKindRawValue == value.destination.kind.rawValue,
              destinationID == value.destination.destinationID, destinationRevision == value.destination.destinationRevision,
              promotedInboxSHA256 == value.promotedInboxSHA256,
              mutationID == value.mutationID.rawValue, canonicalSHA256 == value.promotionSHA256 else { throw FastSurveyInboxPersistenceFailureV1.corruptRow }
        return value
    }
    func markReceiptCommitted(_ receipt: FastSurveyInboxMutationReceiptV1) throws {
        guard self.receiptID == nil,
              receipt.semanticSHA256s == [canonicalSHA256, promotedInboxSHA256].sorted(),
              receipt.workspaceID.rawValue == workspaceID, receipt.mutationID.rawValue == mutationID,
              receipt.generationID == writerGenerationID, receipt.priorWorkspaceRevision == priorWorkspaceRevision,
              receipt.resultingWorkspaceRevision == resultingWorkspaceRevision,
              receipt.recoveryState == .receiptCommitted else { throw FastSurveyInboxPersistenceFailureV1.receiptMismatch }
        try receipt.validate(); receiptID = receipt.receiptID; recoveryStateRawValue = receipt.recoveryState.rawValue
    }
}

@Model final class SnippetRowV1 {
    @Attribute(.unique) private(set) var rowID: String
    private(set) var recordFamilyRawValue: String; private(set) var snippetID: UUID
    private(set) var snippetEventID: UUID; private(set) var workspaceID: UUID
    private(set) var revision: UInt64; private(set) var stateRawValue: String
    private(set) var mutationID: UUID; private(set) var canonicalSHA256: String; private(set) var canonicalData: Data
    private(set) var writerGenerationID: UUID; private(set) var writerInstanceID: UUID
    private(set) var priorWorkspaceRevision: UInt64; private(set) var resultingWorkspaceRevision: UInt64
    private(set) var recoveryStateRawValue: String; private(set) var receiptID: UUID?

    init(_ value: SnippetV1, command: FastSurveyInboxMutationCommandV1, resultingWorkspaceRevision: UInt64) throws {
        try value.validate(); try FastSurveyInboxPersistenceCodecV1.verify(command, result: resultingWorkspaceRevision)
        guard case let .putSnippet(payload) = command.payload, payload == value else { throw FastSurveyInboxPersistenceFailureV1.wrongPayload }
        rowID = FastSurveyInboxPersistenceCodecV1.rowID(value.workspaceID, .snippet, value.snippetID, value.revision)
        recordFamilyRawValue = FastSurveyInboxRecordFamilyV1.snippet.rawValue; snippetID = value.snippetID
        snippetEventID = value.snippetEventID; workspaceID = value.workspaceID.rawValue; revision = value.revision
        stateRawValue = value.state.rawValue; mutationID = value.mutationID.rawValue
        canonicalSHA256 = value.snippetSHA256; canonicalData = try FastSurveyInboxPersistenceCodecV1.data(value)
        writerGenerationID = command.expectedRevision.generationID; writerInstanceID = command.expectedRevision.writerInstanceID
        priorWorkspaceRevision = command.expectedRevision.workspaceRevision; self.resultingWorkspaceRevision = resultingWorkspaceRevision
        recoveryStateRawValue = FastSurveyInboxRecoveryStateV1.effectCommittedAwaitingReceipt.rawValue; receiptID = nil
    }
    init(restoring value: SnippetV1, receipt: FastSurveyInboxMutationReceiptV1, writerInstanceID: UUID) throws {
        try value.validate(); try FastSurveyInboxPersistenceCodecV1.verifyRestore(receipt,
            writerInstanceID: writerInstanceID, workspaceID: value.workspaceID.rawValue,
            mutationID: value.mutationID.rawValue, semanticSHA256s: [value.snippetSHA256])
        rowID = FastSurveyInboxPersistenceCodecV1.rowID(value.workspaceID, .snippet, value.snippetID, value.revision)
        recordFamilyRawValue = FastSurveyInboxRecordFamilyV1.snippet.rawValue; snippetID = value.snippetID
        snippetEventID = value.snippetEventID; workspaceID = value.workspaceID.rawValue; revision = value.revision
        stateRawValue = value.state.rawValue; mutationID = value.mutationID.rawValue
        canonicalSHA256 = value.snippetSHA256; canonicalData = try FastSurveyInboxPersistenceCodecV1.data(value)
        writerGenerationID = receipt.generationID; self.writerInstanceID = writerInstanceID
        priorWorkspaceRevision = receipt.priorWorkspaceRevision; resultingWorkspaceRevision = receipt.resultingWorkspaceRevision
        recoveryStateRawValue = receipt.recoveryState.rawValue; receiptID = receipt.receiptID
    }
    func value() throws -> SnippetV1 {
        let value = try FastSurveyInboxPersistenceCodecV1.decode(SnippetV1.self, from: canonicalData); try value.validate()
        guard recordFamilyRawValue == FastSurveyInboxRecordFamilyV1.snippet.rawValue,
              rowID == FastSurveyInboxPersistenceCodecV1.rowID(value.workspaceID, .snippet, value.snippetID, value.revision),
              snippetID == value.snippetID, snippetEventID == value.snippetEventID,
              workspaceID == value.workspaceID.rawValue, revision == value.revision,
              stateRawValue == value.state.rawValue, mutationID == value.mutationID.rawValue,
              canonicalSHA256 == value.snippetSHA256 else { throw FastSurveyInboxPersistenceFailureV1.corruptRow }
        return value
    }
    func markReceiptCommitted(_ receipt: FastSurveyInboxMutationReceiptV1) throws {
        guard self.receiptID == nil, receipt.semanticSHA256s == [canonicalSHA256],
              receipt.workspaceID.rawValue == workspaceID, receipt.mutationID.rawValue == mutationID,
              receipt.generationID == writerGenerationID, receipt.priorWorkspaceRevision == priorWorkspaceRevision,
              receipt.resultingWorkspaceRevision == resultingWorkspaceRevision,
              receipt.recoveryState == .receiptCommitted else { throw FastSurveyInboxPersistenceFailureV1.receiptMismatch }
        try receipt.validate(); receiptID = receipt.receiptID; recoveryStateRawValue = receipt.recoveryState.rawValue
    }
}

@Model final class SnippetInsertionHistoryRowV1 {
    @Attribute(.unique) private(set) var rowID: String
    private(set) var recordFamilyRawValue: String; private(set) var insertionEventID: UUID
    private(set) var workspaceID: UUID; private(set) var snippetID: UUID; private(set) var snippetRevision: UInt64
    private(set) var targetKindRawValue: String; private(set) var targetID: UUID; private(set) var targetRevision: UInt64
    private(set) var mutationID: UUID; private(set) var canonicalSHA256: String; private(set) var canonicalData: Data
    private(set) var writerGenerationID: UUID; private(set) var writerInstanceID: UUID
    private(set) var priorWorkspaceRevision: UInt64; private(set) var resultingWorkspaceRevision: UInt64
    private(set) var recoveryStateRawValue: String; private(set) var receiptID: UUID?

    init(_ value: SnippetInsertionV1, snippet: SnippetV1,
         command: FastSurveyInboxMutationCommandV1, resultingWorkspaceRevision: UInt64) throws {
        try value.validate(snippet: snippet)
        try FastSurveyInboxPersistenceCodecV1.verify(command, result: resultingWorkspaceRevision)
        guard case let .insertSnippet(payload, sourceSnippet) = command.payload,
              payload == value, sourceSnippet == snippet else { throw FastSurveyInboxPersistenceFailureV1.wrongPayload }
        rowID = FastSurveyInboxPersistenceCodecV1.rowID(value.workspaceID, .snippetInsertion,
            value.insertionEventID, 1)
        recordFamilyRawValue = FastSurveyInboxRecordFamilyV1.snippetInsertion.rawValue
        insertionEventID = value.insertionEventID; workspaceID = value.workspaceID.rawValue
        snippetID = value.snippetID; snippetRevision = value.snippetRevision
        targetKindRawValue = value.target.kind.rawValue; targetID = value.target.targetID
        targetRevision = value.target.targetRevision; mutationID = value.mutationID.rawValue
        canonicalSHA256 = value.insertionSHA256; canonicalData = try FastSurveyInboxPersistenceCodecV1.data(value)
        writerGenerationID = command.expectedRevision.generationID
        writerInstanceID = command.expectedRevision.writerInstanceID
        priorWorkspaceRevision = command.expectedRevision.workspaceRevision
        self.resultingWorkspaceRevision = resultingWorkspaceRevision
        recoveryStateRawValue = FastSurveyInboxRecoveryStateV1.effectCommittedAwaitingReceipt.rawValue
        receiptID = nil
    }

    init(restoring value: SnippetInsertionV1, receipt: FastSurveyInboxMutationReceiptV1,
         writerInstanceID: UUID) throws {
        try value.validate()
        try FastSurveyInboxPersistenceCodecV1.verifyRestore(receipt, writerInstanceID: writerInstanceID,
            workspaceID: value.workspaceID.rawValue, mutationID: value.mutationID.rawValue,
            semanticSHA256s: [value.insertionSHA256])
        rowID = FastSurveyInboxPersistenceCodecV1.rowID(value.workspaceID, .snippetInsertion,
            value.insertionEventID, 1)
        recordFamilyRawValue = FastSurveyInboxRecordFamilyV1.snippetInsertion.rawValue
        insertionEventID = value.insertionEventID; workspaceID = value.workspaceID.rawValue
        snippetID = value.snippetID; snippetRevision = value.snippetRevision
        targetKindRawValue = value.target.kind.rawValue; targetID = value.target.targetID
        targetRevision = value.target.targetRevision; mutationID = value.mutationID.rawValue
        canonicalSHA256 = value.insertionSHA256; canonicalData = try FastSurveyInboxPersistenceCodecV1.data(value)
        writerGenerationID = receipt.generationID; self.writerInstanceID = writerInstanceID
        priorWorkspaceRevision = receipt.priorWorkspaceRevision
        resultingWorkspaceRevision = receipt.resultingWorkspaceRevision
        recoveryStateRawValue = receipt.recoveryState.rawValue; receiptID = receipt.receiptID
    }

    func value() throws -> SnippetInsertionV1 {
        let value = try FastSurveyInboxPersistenceCodecV1.decode(SnippetInsertionV1.self, from: canonicalData)
        try value.validate()
        guard recordFamilyRawValue == FastSurveyInboxRecordFamilyV1.snippetInsertion.rawValue,
              rowID == FastSurveyInboxPersistenceCodecV1.rowID(value.workspaceID, .snippetInsertion,
                  value.insertionEventID, 1),
              insertionEventID == value.insertionEventID, workspaceID == value.workspaceID.rawValue,
              snippetID == value.snippetID, snippetRevision == value.snippetRevision,
              targetKindRawValue == value.target.kind.rawValue, targetID == value.target.targetID,
              targetRevision == value.target.targetRevision, mutationID == value.mutationID.rawValue,
              canonicalSHA256 == value.insertionSHA256 else { throw FastSurveyInboxPersistenceFailureV1.corruptRow }
        return value
    }

    func value(snippet: SnippetV1) throws -> SnippetInsertionV1 {
        let value = try value(); try value.validate(snippet: snippet); return value
    }

    func markReceiptCommitted(_ receipt: FastSurveyInboxMutationReceiptV1) throws {
        guard self.receiptID == nil, receipt.semanticSHA256s == [canonicalSHA256],
              receipt.workspaceID.rawValue == workspaceID, receipt.mutationID.rawValue == mutationID,
              receipt.generationID == writerGenerationID, receipt.priorWorkspaceRevision == priorWorkspaceRevision,
              receipt.resultingWorkspaceRevision == resultingWorkspaceRevision,
              receipt.recoveryState == .receiptCommitted else { throw FastSurveyInboxPersistenceFailureV1.receiptMismatch }
        try receipt.validate(); receiptID = receipt.receiptID; recoveryStateRawValue = receipt.recoveryState.rawValue
    }
}

@Model final class FastSurveyInboxMutationReceiptRowV1 {
    @Attribute(.unique) private(set) var rowID: String
    private(set) var recordFamilyRawValue: String; private(set) var receiptID: UUID
    private(set) var workspaceID: UUID; private(set) var generationID: UUID; private(set) var mutationID: UUID
    private(set) var resultingWorkspaceRevision: UInt64; private(set) var canonicalSHA256: String; private(set) var canonicalData: Data
    init(_ value: FastSurveyInboxMutationReceiptV1) throws {
        try value.validate(); guard value.recoveryState == .receiptCommitted else { throw FastSurveyInboxPersistenceFailureV1.receiptMismatch }
        rowID = FastSurveyInboxPersistenceCodecV1.receiptRowID(value)
        recordFamilyRawValue = FastSurveyInboxRecordFamilyV1.mutationReceipt.rawValue
        receiptID = value.receiptID; workspaceID = value.workspaceID.rawValue; generationID = value.generationID
        mutationID = value.mutationID.rawValue; resultingWorkspaceRevision = value.resultingWorkspaceRevision
        canonicalSHA256 = value.receiptSHA256; canonicalData = try FastSurveyInboxPersistenceCodecV1.data(value)
    }
    func value() throws -> FastSurveyInboxMutationReceiptV1 {
        let value = try FastSurveyInboxPersistenceCodecV1.decode(FastSurveyInboxMutationReceiptV1.self, from: canonicalData); try value.validate()
        guard recordFamilyRawValue == FastSurveyInboxRecordFamilyV1.mutationReceipt.rawValue,
              rowID == FastSurveyInboxPersistenceCodecV1.receiptRowID(value), receiptID == value.receiptID,
              workspaceID == value.workspaceID.rawValue, generationID == value.generationID,
              mutationID == value.mutationID.rawValue, resultingWorkspaceRevision == value.resultingWorkspaceRevision,
              canonicalSHA256 == value.receiptSHA256 else { throw FastSurveyInboxPersistenceFailureV1.corruptRow }
        return value
    }
}

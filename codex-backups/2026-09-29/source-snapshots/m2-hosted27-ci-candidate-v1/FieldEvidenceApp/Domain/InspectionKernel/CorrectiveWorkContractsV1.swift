import Foundation

enum CorrectiveWorkLinkActionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case linked = "LINKED"
    case removed = "REMOVED"
}

extension CorrectiveWorkLinkV1 {
    func validateCorrectiveActionSource(
        findingID: String,
        findingRevision: Int,
        actionID: UUID
    ) throws {
        guard self.findingID == findingID, self.findingRevision == findingRevision,
              workID == actionID.uuidString.lowercased(), action == .linked else {
            throw FindingContractFailureV1.invalidValue
        }
    }
}

struct CorrectiveWorkLinkV1: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let linkID: String
    let findingID: String
    let findingRevision: Int
    let workID: String
    let workRevision: Int
    let expectedLinkRevision: Int
    let resultingLinkRevision: Int
    let mutationID: String
    let action: CorrectiveWorkLinkActionV1
    let actorID: String
    let reason: String
    let effectiveAt: String
    let supersedesLinkEventID: String?

    var id: String { linkID }

    init(
        linkID: String,
        findingID: String,
        findingRevision: Int,
        workID: String,
        workRevision: Int,
        expectedLinkRevision: Int,
        resultingLinkRevision: Int,
        mutationID: String,
        action: CorrectiveWorkLinkActionV1,
        actorID: String,
        reason: String,
        effectiveAt: String,
        supersedesLinkEventID: String? = nil
    ) throws {
        guard [linkID, findingID, workID, mutationID, actorID].allSatisfy(FindingContractValidationV1.validID),
              findingRevision >= 0, workRevision >= 0, expectedLinkRevision >= 0,
              resultingLinkRevision == expectedLinkRevision + 1,
              FindingContractValidationV1.validText(reason, maximumBytes: FindingContractLimitsV1.maximumReasonBytes),
              FindingContractValidationV1.validInstant(effectiveAt),
              supersedesLinkEventID.map(FindingContractValidationV1.validID) ?? true,
              (expectedLinkRevision == 0) == (supersedesLinkEventID == nil),
              action != .removed || supersedesLinkEventID != nil else {
            throw FindingContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.linkID = linkID
        self.findingID = findingID
        self.findingRevision = findingRevision
        self.workID = workID
        self.workRevision = workRevision
        self.expectedLinkRevision = expectedLinkRevision
        self.resultingLinkRevision = resultingLinkRevision
        self.mutationID = mutationID
        self.action = action
        self.actorID = actorID
        self.reason = reason
        self.effectiveAt = effectiveAt
        self.supersedesLinkEventID = supersedesLinkEventID
    }
}

enum CorrectiveWorkLinkLedgerV1 {
    static func validate(_ events: [CorrectiveWorkLinkV1]) throws {
        guard events.count <= FindingContractLimitsV1.maximumLinks else {
            throw FindingContractFailureV1.limitExceeded
        }
        var expectedRevision = 0
        var predecessorID: String?
        var previousAction: CorrectiveWorkLinkActionV1?
        var eventIDs = Set<String>()
        var mutationIDs = Set<String>()
        var findingID: String?
        var workID: String?

        for event in events {
            findingID = findingID ?? event.findingID
            workID = workID ?? event.workID
            guard event.findingID == findingID,
                  event.workID == workID,
                  event.expectedLinkRevision == expectedRevision,
                  event.resultingLinkRevision == expectedRevision + 1,
                  event.supersedesLinkEventID == predecessorID,
                  previousAction != event.action else {
                throw FindingContractFailureV1.historyRewrite
            }
            if expectedRevision == 0, event.action != .linked {
                throw FindingContractFailureV1.invalidTransition
            }
            guard eventIDs.insert(event.linkID).inserted,
                  mutationIDs.insert(event.mutationID).inserted else {
                throw FindingContractFailureV1.duplicateIdentity
            }
            expectedRevision = event.resultingLinkRevision
            predecessorID = event.linkID
            previousAction = event.action
        }
    }
}

extension CorrectiveWorkLinkV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, linkID, findingID, findingRevision, workID, workRevision
        case expectedLinkRevision, resultingLinkRevision, mutationID, action, actorID
        case reason, effectiveAt, supersedesLinkEventID
    }
    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireClosed(decoder, allowed: CodingKeys.allCases.map(\.rawValue), required: CodingKeys.allCases.filter { $0 != .supersedesLinkEventID }.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw FindingContractFailureV1.incompatibleVersion }
        try self.init(
            linkID: c.decode(String.self, forKey: .linkID), findingID: c.decode(String.self, forKey: .findingID),
            findingRevision: c.decode(Int.self, forKey: .findingRevision), workID: c.decode(String.self, forKey: .workID),
            workRevision: c.decode(Int.self, forKey: .workRevision), expectedLinkRevision: c.decode(Int.self, forKey: .expectedLinkRevision),
            resultingLinkRevision: c.decode(Int.self, forKey: .resultingLinkRevision), mutationID: c.decode(String.self, forKey: .mutationID),
            action: c.decode(CorrectiveWorkLinkActionV1.self, forKey: .action), actorID: c.decode(String.self, forKey: .actorID),
            reason: c.decode(String.self, forKey: .reason), effectiveAt: c.decode(String.self, forKey: .effectiveAt),
            supersedesLinkEventID: c.decodeIfPresent(String.self, forKey: .supersedesLinkEventID)
        )
    }
}

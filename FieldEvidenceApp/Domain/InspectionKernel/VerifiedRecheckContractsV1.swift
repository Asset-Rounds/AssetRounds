import Foundation

enum VerifiedRecheckOutcomeV1: String, CaseIterable, Codable, Hashable, Sendable {
    case passed = "PASSED"
    case failed = "FAILED"
    case inconclusive = "INCONCLUSIVE"
}

extension VerifiedRecheckV1 {
    func inspectionReviewEvidenceReference() throws -> ReviewEvidenceReferenceV1 {
        guard resultingRecheckRevision > 0 else { throw FindingContractFailureV1.invalidValue }
        return try .init(kind: .verifiedRecheck, referenceID: recheckID,
                         revision: UInt64(resultingRecheckRevision),
                         sha256: WorkspaceMutationCanonicalV1.sha256(self))
    }
}

struct VerifiedRecheckV1: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let recheckID: String
    let findingID: String
    let findingRevision: Int
    let correctiveWorkID: String
    let correctiveWorkRevision: Int
    let priorRecheckID: String?
    let evidenceRevisionIDs: [String]
    let expectedRecheckRevision: Int
    let resultingRecheckRevision: Int
    let mutationID: String
    let outcome: VerifiedRecheckOutcomeV1
    let verifierActorID: String
    let verifierAuthority: String
    let reason: String
    let effectiveAt: String

    var id: String { recheckID }
    var permitsVerifiedResolution: Bool { outcome == .passed }

    init(
        recheckID: String,
        findingID: String,
        findingRevision: Int,
        correctiveWorkID: String,
        correctiveWorkRevision: Int,
        priorRecheckID: String? = nil,
        evidenceRevisionIDs: [String],
        expectedRecheckRevision: Int = 0,
        resultingRecheckRevision: Int = 1,
        mutationID: String,
        outcome: VerifiedRecheckOutcomeV1,
        verifierActorID: String,
        verifierAuthority: String,
        reason: String,
        effectiveAt: String
    ) throws {
        guard [recheckID, findingID, correctiveWorkID, mutationID, verifierActorID].allSatisfy(FindingContractValidationV1.validID),
              findingRevision >= 0, correctiveWorkRevision >= 0,
              expectedRecheckRevision >= 0,
              resultingRecheckRevision == expectedRecheckRevision + 1,
              priorRecheckID.map(FindingContractValidationV1.validID) ?? true,
              FindingContractValidationV1.validText(verifierAuthority, maximumBytes: FindingContractLimitsV1.maximumReasonBytes),
              FindingContractValidationV1.validText(reason, maximumBytes: FindingContractLimitsV1.maximumReasonBytes),
              FindingContractValidationV1.validInstant(effectiveAt) else {
            throw FindingContractFailureV1.invalidValue
        }
        try FindingContractValidationV1.validateIDs(evidenceRevisionIDs, maximum: FindingContractLimitsV1.maximumEvidenceReferences)
        guard !evidenceRevisionIDs.isEmpty else { throw FindingContractFailureV1.missingTarget }
        schemaVersion = Self.schemaVersion
        self.recheckID = recheckID
        self.findingID = findingID
        self.findingRevision = findingRevision
        self.correctiveWorkID = correctiveWorkID
        self.correctiveWorkRevision = correctiveWorkRevision
        self.priorRecheckID = priorRecheckID
        self.evidenceRevisionIDs = evidenceRevisionIDs
        self.expectedRecheckRevision = expectedRecheckRevision
        self.resultingRecheckRevision = resultingRecheckRevision
        self.mutationID = mutationID
        self.outcome = outcome
        self.verifierActorID = verifierActorID
        self.verifierAuthority = verifierAuthority
        self.reason = reason
        self.effectiveAt = effectiveAt
    }
}

enum VerifiedRecheckLineageV1 {
    static func validate(_ rechecks: [VerifiedRecheckV1]) throws {
        guard rechecks.count <= FindingContractLimitsV1.maximumTransitions else { throw FindingContractFailureV1.limitExceeded }
        var expectedRevision = 0
        var predecessorID: String?
        var ids = Set<String>(), mutations = Set<String>()
        var findingID: String?, workID: String?
        for recheck in rechecks {
            findingID = findingID ?? recheck.findingID; workID = workID ?? recheck.correctiveWorkID
            guard recheck.findingID == findingID, recheck.correctiveWorkID == workID,
                  recheck.expectedRecheckRevision == expectedRevision,
                  recheck.resultingRecheckRevision == expectedRevision + 1,
                  recheck.priorRecheckID == predecessorID else { throw FindingContractFailureV1.historyRewrite }
            guard ids.insert(recheck.recheckID).inserted, mutations.insert(recheck.mutationID).inserted else { throw FindingContractFailureV1.duplicateIdentity }
            expectedRevision = recheck.resultingRecheckRevision; predecessorID = recheck.recheckID
        }
    }
}

extension VerifiedRecheckV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, recheckID, findingID, findingRevision, correctiveWorkID
        case correctiveWorkRevision, priorRecheckID, evidenceRevisionIDs, mutationID
        case expectedRecheckRevision, resultingRecheckRevision
        case outcome, verifierActorID, verifierAuthority, reason, effectiveAt
    }
    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireClosed(decoder, allowed: CodingKeys.allCases.map(\.rawValue), required: CodingKeys.allCases.filter { $0 != .priorRecheckID }.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw FindingContractFailureV1.incompatibleVersion }
        try self.init(
            recheckID: c.decode(String.self, forKey: .recheckID), findingID: c.decode(String.self, forKey: .findingID),
            findingRevision: c.decode(Int.self, forKey: .findingRevision), correctiveWorkID: c.decode(String.self, forKey: .correctiveWorkID),
            correctiveWorkRevision: c.decode(Int.self, forKey: .correctiveWorkRevision), priorRecheckID: c.decodeIfPresent(String.self, forKey: .priorRecheckID),
            evidenceRevisionIDs: c.decode([String].self, forKey: .evidenceRevisionIDs), expectedRecheckRevision: c.decode(Int.self, forKey: .expectedRecheckRevision),
            resultingRecheckRevision: c.decode(Int.self, forKey: .resultingRecheckRevision), mutationID: c.decode(String.self, forKey: .mutationID),
            outcome: c.decode(VerifiedRecheckOutcomeV1.self, forKey: .outcome), verifierActorID: c.decode(String.self, forKey: .verifierActorID),
            verifierAuthority: c.decode(String.self, forKey: .verifierAuthority), reason: c.decode(String.self, forKey: .reason),
            effectiveAt: c.decode(String.self, forKey: .effectiveAt)
        )
    }
}

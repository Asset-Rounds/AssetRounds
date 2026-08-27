import Foundation

struct ReleaseToServiceV1: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let releaseID: String
    let subjectID: String
    let findingID: String
    let findingRevision: Int
    let verifiedRecheckID: String
    let verifiedRecheckFindingRevision: Int
    let verifiedRecheckOutcome: VerifiedRecheckOutcomeV1
    let mutationID: String
    let authorizingActorID: String
    let authority: String
    let reason: String
    let effectiveAt: String

    var id: String { releaseID }

    init(
        releaseID: String,
        subjectID: String,
        findingID: String,
        findingRevision: Int,
        verifiedRecheck: VerifiedRecheckV1,
        mutationID: String,
        authorizingActorID: String,
        authority: String,
        reason: String,
        effectiveAt: String
    ) throws {
        guard verifiedRecheck.findingID == findingID,
              findingRevision == verifiedRecheck.findingRevision + 1,
              verifiedRecheck.permitsVerifiedResolution else {
            throw FindingContractFailureV1.releaseNotEligible
        }
        guard [releaseID, subjectID, findingID, mutationID, authorizingActorID].allSatisfy(FindingContractValidationV1.validID),
              findingRevision >= 0,
              FindingContractValidationV1.validText(authority, maximumBytes: FindingContractLimitsV1.maximumReasonBytes),
              FindingContractValidationV1.validText(reason, maximumBytes: FindingContractLimitsV1.maximumReasonBytes),
              FindingContractValidationV1.validInstant(effectiveAt) else {
            throw FindingContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.releaseID = releaseID
        self.subjectID = subjectID
        self.findingID = findingID
        self.findingRevision = findingRevision
        verifiedRecheckID = verifiedRecheck.recheckID
        verifiedRecheckFindingRevision = verifiedRecheck.findingRevision
        verifiedRecheckOutcome = verifiedRecheck.outcome
        self.mutationID = mutationID
        self.authorizingActorID = authorizingActorID
        self.authority = authority
        self.reason = reason
        self.effectiveAt = effectiveAt
    }

    private init(
        releaseID: String, subjectID: String, findingID: String, findingRevision: Int,
        verifiedRecheckID: String, verifiedRecheckFindingRevision: Int,
        verifiedRecheckOutcome: VerifiedRecheckOutcomeV1, mutationID: String,
        authorizingActorID: String, authority: String, reason: String, effectiveAt: String
    ) throws {
        guard [releaseID, subjectID, findingID, verifiedRecheckID, mutationID, authorizingActorID].allSatisfy(FindingContractValidationV1.validID),
              findingRevision >= 0, verifiedRecheckFindingRevision >= 0,
              findingRevision == verifiedRecheckFindingRevision + 1,
              verifiedRecheckOutcome == .passed,
              FindingContractValidationV1.validText(authority, maximumBytes: FindingContractLimitsV1.maximumReasonBytes),
              FindingContractValidationV1.validText(reason, maximumBytes: FindingContractLimitsV1.maximumReasonBytes),
              FindingContractValidationV1.validInstant(effectiveAt) else { throw FindingContractFailureV1.invalidValue }
        schemaVersion = Self.schemaVersion
        self.releaseID = releaseID; self.subjectID = subjectID; self.findingID = findingID
        self.findingRevision = findingRevision; self.verifiedRecheckID = verifiedRecheckID
        self.verifiedRecheckFindingRevision = verifiedRecheckFindingRevision
        self.verifiedRecheckOutcome = verifiedRecheckOutcome; self.mutationID = mutationID
        self.authorizingActorID = authorizingActorID; self.authority = authority; self.reason = reason; self.effectiveAt = effectiveAt
    }

    func validate(against verifiedRecheck: VerifiedRecheckV1) throws {
        guard verifiedRecheckID == verifiedRecheck.recheckID,
              findingID == verifiedRecheck.findingID,
              verifiedRecheckFindingRevision == verifiedRecheck.findingRevision,
              verifiedRecheckOutcome == verifiedRecheck.outcome,
              verifiedRecheck.permitsVerifiedResolution,
              findingRevision == verifiedRecheck.findingRevision + 1 else {
            throw FindingContractFailureV1.releaseNotEligible
        }
    }
}

extension ReleaseToServiceV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, releaseID, subjectID, findingID, findingRevision, verifiedRecheckID
        case verifiedRecheckFindingRevision, verifiedRecheckOutcome, mutationID
        case authorizingActorID, authority, reason, effectiveAt
    }
    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw FindingContractFailureV1.incompatibleVersion }
        try self.init(
            releaseID: c.decode(String.self, forKey: .releaseID), subjectID: c.decode(String.self, forKey: .subjectID), findingID: c.decode(String.self, forKey: .findingID),
            findingRevision: c.decode(Int.self, forKey: .findingRevision), verifiedRecheckID: c.decode(String.self, forKey: .verifiedRecheckID),
            verifiedRecheckFindingRevision: c.decode(Int.self, forKey: .verifiedRecheckFindingRevision),
            verifiedRecheckOutcome: c.decode(VerifiedRecheckOutcomeV1.self, forKey: .verifiedRecheckOutcome), mutationID: c.decode(String.self, forKey: .mutationID),
            authorizingActorID: c.decode(String.self, forKey: .authorizingActorID), authority: c.decode(String.self, forKey: .authority),
            reason: c.decode(String.self, forKey: .reason), effectiveAt: c.decode(String.self, forKey: .effectiveAt)
        )
    }
}

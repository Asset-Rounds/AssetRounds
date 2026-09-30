import Foundation

enum FindingStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case open = "OPEN"
    case correctiveWorkInProgress = "CORRECTIVE_WORK_IN_PROGRESS"
    case awaitingVerifiedRecheck = "AWAITING_VERIFIED_RECHECK"
    case verifiedResolved = "VERIFIED_RESOLVED"
    case closed = "CLOSED"
    case reopened = "REOPENED"

    var isTerminal: Bool { self == .closed }
}

extension FindingLifecycleV1 {
    func validateCorrectiveActionAdmission(findingRevision: Int) throws {
        try validate()
        guard currentRevision == findingRevision,
              currentState == .open || currentState == .correctiveWorkInProgress
                || currentState == .reopened else {
            throw FindingContractFailureV1.invalidTransition
        }
    }
}

struct FindingTransitionV1: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let transitionID: String
    let findingID: String
    let expectedFindingRevision: Int
    let resultingFindingRevision: Int
    let mutationID: String
    let fromState: FindingStateV1
    let toState: FindingStateV1
    let actorID: String
    let reason: String
    let effectiveAt: String
    let verifiedRecheckID: String?

    var id: String { transitionID }

    init(
        transitionID: String,
        findingID: String,
        expectedFindingRevision: Int,
        resultingFindingRevision: Int,
        mutationID: String,
        fromState: FindingStateV1,
        toState: FindingStateV1,
        actorID: String,
        reason: String,
        effectiveAt: String,
        verifiedRecheckID: String? = nil
    ) throws {
        try self.init(
            transitionID: transitionID,
            findingID: findingID,
            expectedFindingRevision: expectedFindingRevision,
            resultingFindingRevision: resultingFindingRevision,
            mutationID: mutationID,
            fromState: fromState,
            toState: toState,
            actorID: actorID,
            reason: reason,
            effectiveAt: effectiveAt,
            verifiedRecheckID: verifiedRecheckID,
            verifiedRecheckWasValidated: false
        )
    }

    init(
        transitionID: String,
        findingID: String,
        expectedFindingRevision: Int,
        resultingFindingRevision: Int,
        mutationID: String,
        fromState: FindingStateV1,
        toState: FindingStateV1,
        actorID: String,
        reason: String,
        effectiveAt: String,
        verifiedRecheck: VerifiedRecheckV1
    ) throws {
        guard verifiedRecheck.findingID == findingID,
              verifiedRecheck.findingRevision == expectedFindingRevision,
              verifiedRecheck.permitsVerifiedResolution else {
            throw FindingContractFailureV1.recheckRequired
        }
        try self.init(
            transitionID: transitionID,
            findingID: findingID,
            expectedFindingRevision: expectedFindingRevision,
            resultingFindingRevision: resultingFindingRevision,
            mutationID: mutationID,
            fromState: fromState,
            toState: toState,
            actorID: actorID,
            reason: reason,
            effectiveAt: effectiveAt,
            verifiedRecheckID: verifiedRecheck.recheckID,
            verifiedRecheckWasValidated: true
        )
    }

    private init(
        transitionID: String,
        findingID: String,
        expectedFindingRevision: Int,
        resultingFindingRevision: Int,
        mutationID: String,
        fromState: FindingStateV1,
        toState: FindingStateV1,
        actorID: String,
        reason: String,
        effectiveAt: String,
        verifiedRecheckID: String?,
        verifiedRecheckWasValidated: Bool
    ) throws {
        guard [transitionID, findingID, mutationID, actorID].allSatisfy(FindingContractValidationV1.validID),
              expectedFindingRevision >= 0,
              resultingFindingRevision == expectedFindingRevision + 1,
              FindingContractValidationV1.validText(reason, maximumBytes: FindingContractLimitsV1.maximumReasonBytes),
              FindingContractValidationV1.validInstant(effectiveAt),
              verifiedRecheckID.map(FindingContractValidationV1.validID) ?? true else {
            throw FindingContractFailureV1.invalidValue
        }
        try FindingLifecycleV1.validateTransition(
            from: fromState,
            to: toState,
            hasEligibleRecheck: verifiedRecheckWasValidated
        )
        guard (toState == .verifiedResolved) == (verifiedRecheckID != nil),
              verifiedRecheckWasValidated || verifiedRecheckID == nil else {
            throw FindingContractFailureV1.recheckRequired
        }
        schemaVersion = Self.schemaVersion
        self.transitionID = transitionID
        self.findingID = findingID
        self.expectedFindingRevision = expectedFindingRevision
        self.resultingFindingRevision = resultingFindingRevision
        self.mutationID = mutationID
        self.fromState = fromState
        self.toState = toState
        self.actorID = actorID
        self.reason = reason
        self.effectiveAt = effectiveAt
        self.verifiedRecheckID = verifiedRecheckID
    }
}

struct FindingLifecycleV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let findingID: String
    let initialRevision: Int
    let initialState: FindingStateV1
    let transitions: [FindingTransitionV1]

    var currentState: FindingStateV1 { transitions.last?.toState ?? initialState }
    var currentRevision: Int { transitions.last?.resultingFindingRevision ?? initialRevision }

    init(
        findingID: String,
        initialRevision: Int = 0,
        initialState: FindingStateV1 = .open,
        transitions: [FindingTransitionV1] = []
    ) throws {
        guard FindingContractValidationV1.validID(findingID), initialRevision >= 0,
              initialState == .open,
              transitions.count <= FindingContractLimitsV1.maximumTransitions else {
            throw FindingContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.findingID = findingID
        self.initialRevision = initialRevision
        self.initialState = initialState
        self.transitions = transitions
        try validate()
    }

    func appending(_ transition: FindingTransitionV1) throws -> FindingLifecycleV1 {
        if let existing = transitions.first(where: { $0.mutationID == transition.mutationID }) {
            guard existing == transition else { throw FindingContractFailureV1.duplicateIdentity }
            return self
        }
        guard transition.expectedFindingRevision == currentRevision else {
            throw FindingContractFailureV1.staleRevision
        }
        guard transition.fromState == currentState else {
            throw FindingContractFailureV1.invalidTransition
        }
        return try FindingLifecycleV1(
            findingID: findingID,
            initialRevision: initialRevision,
            initialState: initialState,
            transitions: transitions + [transition]
        )
    }

    func validate() throws {
        var expectedRevision = initialRevision
        var expectedState = initialState
        var transitionIDs = Set<String>()
        var mutationIDs = Set<String>()
        for transition in transitions {
            guard transition.findingID == findingID,
                  transition.expectedFindingRevision == expectedRevision,
                  transition.resultingFindingRevision == expectedRevision + 1,
                  transition.fromState == expectedState else {
                throw FindingContractFailureV1.historyRewrite
            }
            guard transitionIDs.insert(transition.transitionID).inserted,
                  mutationIDs.insert(transition.mutationID).inserted else {
                throw FindingContractFailureV1.duplicateIdentity
            }
            try Self.validateTransition(
                from: transition.fromState,
                to: transition.toState,
                hasEligibleRecheck: transition.verifiedRecheckID != nil
            )
            expectedRevision = transition.resultingFindingRevision
            expectedState = transition.toState
        }
    }

    func validateVerifiedResolutionLineage(_ rechecks: [VerifiedRecheckV1]) throws {
        let byID = Dictionary(grouping: rechecks, by: \.recheckID)
        guard byID.values.allSatisfy({ $0.count == 1 }) else {
            throw FindingContractFailureV1.duplicateIdentity
        }
        for transition in transitions where transition.toState == .verifiedResolved {
            guard let recheckID = transition.verifiedRecheckID,
                  let recheck = byID[recheckID]?.first,
                  recheck.findingID == findingID,
                  recheck.findingRevision == transition.expectedFindingRevision,
                  recheck.permitsVerifiedResolution else {
                throw FindingContractFailureV1.recheckRequired
            }
        }
    }

    static func validateTransition(
        from: FindingStateV1,
        to: FindingStateV1,
        hasEligibleRecheck: Bool
    ) throws {
        let permitted: Bool
        switch (from, to) {
        case (.open, .correctiveWorkInProgress),
             (.open, .awaitingVerifiedRecheck),
             (.correctiveWorkInProgress, .awaitingVerifiedRecheck),
             (.awaitingVerifiedRecheck, .correctiveWorkInProgress),
             (.reopened, .correctiveWorkInProgress),
             (.reopened, .awaitingVerifiedRecheck),
             (.verifiedResolved, .closed),
             (.closed, .reopened):
            permitted = true
        case (.awaitingVerifiedRecheck, .verifiedResolved):
            guard hasEligibleRecheck else { throw FindingContractFailureV1.recheckRequired }
            permitted = true
        default:
            permitted = false
        }
        guard permitted else { throw FindingContractFailureV1.invalidTransition }
        guard to == .verifiedResolved || !hasEligibleRecheck else {
            throw FindingContractFailureV1.invalidTransition
        }
    }
}

enum OperationalDispositionStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case inServiceRecorded = "IN_SERVICE_RECORDED"
    case restrictedUseRecorded = "RESTRICTED_USE_RECORDED"
    case outOfServiceRecorded = "OUT_OF_SERVICE_RECORDED"
    case returnedToServiceRecorded = "RETURNED_TO_SERVICE_RECORDED"
    case unknownReviewRequired = "UNKNOWN_REVIEW_REQUIRED"
}

struct OperationalDispositionEventV1: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let eventID: String
    let subjectID: String
    let findingID: String
    let findingRevision: Int
    let evidenceRevisionIDs: [String]
    let expectedDispositionRevision: Int
    let resultingDispositionRevision: Int
    let mutationID: String
    let state: OperationalDispositionStateV1
    let actorID: String
    let authority: String
    let reason: String
    let effectiveAt: String
    let supersedesEventID: String?
    let releaseToServiceID: String?

    var id: String { eventID }

    init(
        eventID: String,
        subjectID: String,
        findingID: String,
        findingRevision: Int,
        evidenceRevisionIDs: [String],
        expectedDispositionRevision: Int,
        resultingDispositionRevision: Int,
        mutationID: String,
        state: OperationalDispositionStateV1,
        actorID: String,
        authority: String,
        reason: String,
        effectiveAt: String,
        supersedesEventID: String? = nil,
        releaseToServiceID: String? = nil
    ) throws {
        guard [eventID, subjectID, findingID, mutationID, actorID].allSatisfy(FindingContractValidationV1.validID),
              findingRevision >= 0, expectedDispositionRevision >= 0,
              resultingDispositionRevision == expectedDispositionRevision + 1,
              FindingContractValidationV1.validText(authority, maximumBytes: FindingContractLimitsV1.maximumReasonBytes),
              FindingContractValidationV1.validText(reason, maximumBytes: FindingContractLimitsV1.maximumReasonBytes),
              FindingContractValidationV1.validInstant(effectiveAt),
              supersedesEventID.map(FindingContractValidationV1.validID) ?? true,
              releaseToServiceID.map(FindingContractValidationV1.validID) ?? true,
              (state == .returnedToServiceRecorded) == (releaseToServiceID != nil) else {
            throw FindingContractFailureV1.invalidValue
        }
        try FindingContractValidationV1.validateIDs(
            evidenceRevisionIDs,
            maximum: FindingContractLimitsV1.maximumEvidenceReferences
        )
        guard (expectedDispositionRevision == 0) == (supersedesEventID == nil) else {
            throw FindingContractFailureV1.invalidValue
        }
        schemaVersion = Self.schemaVersion
        self.eventID = eventID
        self.subjectID = subjectID
        self.findingID = findingID
        self.findingRevision = findingRevision
        self.evidenceRevisionIDs = evidenceRevisionIDs
        self.expectedDispositionRevision = expectedDispositionRevision
        self.resultingDispositionRevision = resultingDispositionRevision
        self.mutationID = mutationID
        self.state = state
        self.actorID = actorID
        self.authority = authority
        self.reason = reason
        self.effectiveAt = effectiveAt
        self.supersedesEventID = supersedesEventID
        self.releaseToServiceID = releaseToServiceID
    }
}

enum OperationalDispositionLedgerV1 {
    static func validate(_ events: [OperationalDispositionEventV1]) throws {
        guard events.count <= FindingContractLimitsV1.maximumTransitions else { throw FindingContractFailureV1.limitExceeded }
        var expectedRevision = 0
        var predecessorID: String?
        var eventIDs = Set<String>(), mutationIDs = Set<String>()
        var subjectID: String?, findingID: String?
        for event in events {
            subjectID = subjectID ?? event.subjectID; findingID = findingID ?? event.findingID
            guard event.subjectID == subjectID, event.findingID == findingID,
                  event.expectedDispositionRevision == expectedRevision,
                  event.resultingDispositionRevision == expectedRevision + 1,
                  event.supersedesEventID == predecessorID else { throw FindingContractFailureV1.historyRewrite }
            guard eventIDs.insert(event.eventID).inserted, mutationIDs.insert(event.mutationID).inserted else { throw FindingContractFailureV1.duplicateIdentity }
            expectedRevision = event.resultingDispositionRevision; predecessorID = event.eventID
        }
    }

    static func validateReturnedToService(
        event: OperationalDispositionEventV1,
        release: ReleaseToServiceV1,
        verifiedRecheck: VerifiedRecheckV1
    ) throws {
        guard event.state == .returnedToServiceRecorded,
              event.releaseToServiceID == release.releaseID,
              event.subjectID == release.subjectID,
              event.findingID == release.findingID,
              event.findingRevision == release.findingRevision else {
            throw FindingContractFailureV1.releaseNotEligible
        }
        try release.validate(against: verifiedRecheck)
    }
}

extension FindingTransitionV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, transitionID, findingID, expectedFindingRevision
        case resultingFindingRevision, mutationID, fromState, toState, actorID, reason
        case effectiveAt, verifiedRecheckID
    }
    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireClosed(decoder, allowed: CodingKeys.allCases.map(\.rawValue), required: CodingKeys.allCases.filter { $0 != .verifiedRecheckID }.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw FindingContractFailureV1.incompatibleVersion }
        let verifiedRecheckID = try c.decodeIfPresent(String.self, forKey: .verifiedRecheckID)
        try self.init(
            transitionID: c.decode(String.self, forKey: .transitionID), findingID: c.decode(String.self, forKey: .findingID),
            expectedFindingRevision: c.decode(Int.self, forKey: .expectedFindingRevision), resultingFindingRevision: c.decode(Int.self, forKey: .resultingFindingRevision),
            mutationID: c.decode(String.self, forKey: .mutationID), fromState: c.decode(FindingStateV1.self, forKey: .fromState),
            toState: c.decode(FindingStateV1.self, forKey: .toState), actorID: c.decode(String.self, forKey: .actorID),
            reason: c.decode(String.self, forKey: .reason), effectiveAt: c.decode(String.self, forKey: .effectiveAt),
            verifiedRecheckID: verifiedRecheckID,
            verifiedRecheckWasValidated: verifiedRecheckID != nil
        )
    }
}

extension FindingLifecycleV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, findingID, initialRevision, initialState, transitions }
    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw FindingContractFailureV1.incompatibleVersion }
        try self.init(findingID: c.decode(String.self, forKey: .findingID), initialRevision: c.decode(Int.self, forKey: .initialRevision), initialState: c.decode(FindingStateV1.self, forKey: .initialState), transitions: c.decode([FindingTransitionV1].self, forKey: .transitions))
    }
}

extension OperationalDispositionEventV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, eventID, subjectID, findingID, findingRevision, evidenceRevisionIDs
        case expectedDispositionRevision, resultingDispositionRevision, mutationID, state, actorID
        case authority, reason, effectiveAt, supersedesEventID, releaseToServiceID
    }
    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireClosed(
            decoder,
            allowed: CodingKeys.allCases.map(\.rawValue),
            required: CodingKeys.allCases.filter {
                $0 != .supersedesEventID && $0 != .releaseToServiceID
            }.map(\.rawValue)
        )
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw FindingContractFailureV1.incompatibleVersion }
        try self.init(
            eventID: c.decode(String.self, forKey: .eventID), subjectID: c.decode(String.self, forKey: .subjectID),
            findingID: c.decode(String.self, forKey: .findingID), findingRevision: c.decode(Int.self, forKey: .findingRevision),
            evidenceRevisionIDs: c.decode([String].self, forKey: .evidenceRevisionIDs), expectedDispositionRevision: c.decode(Int.self, forKey: .expectedDispositionRevision),
            resultingDispositionRevision: c.decode(Int.self, forKey: .resultingDispositionRevision), mutationID: c.decode(String.self, forKey: .mutationID),
            state: c.decode(OperationalDispositionStateV1.self, forKey: .state), actorID: c.decode(String.self, forKey: .actorID),
            authority: c.decode(String.self, forKey: .authority), reason: c.decode(String.self, forKey: .reason),
            effectiveAt: c.decode(String.self, forKey: .effectiveAt), supersedesEventID: c.decodeIfPresent(String.self, forKey: .supersedesEventID),
            releaseToServiceID: c.decodeIfPresent(String.self, forKey: .releaseToServiceID)
        )
    }
}

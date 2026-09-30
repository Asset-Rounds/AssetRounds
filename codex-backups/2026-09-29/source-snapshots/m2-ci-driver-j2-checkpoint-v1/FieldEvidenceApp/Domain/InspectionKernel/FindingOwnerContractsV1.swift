import Foundation

/// One immutable revision in the future sole-writer owner stream. This value is
/// not a persistence admission, an accepted receipt or an imported-write permit.
struct FindingOwnerRecordV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let kind: FindingOwnerKindV1
    let ownerID: UUID
    let ownerRevision: UInt64
    let predecessor: FindingOwnerRevisionReferenceV1?
    let mutationID: MutationIDV1
    let recordedBy: ActorSnapshotV1
    let recordedAt: Date
    let origin: FindingOwnerOriginIdentityV1
    let finding: FindingOwnedFactsV1?
    let relationship: FindingOwnedRelationshipV1?
    /// Semantic digest of every immutable basis field except this derived field.
    /// Transport/archive/receipt byte hashes must hash the actual encoded bytes.
    let recordSHA256: String

    var reference: FindingOwnerRevisionReferenceV1 {
        get throws {
            // Construction/decoding validated the immutable semantic digest.
            // This is deliberately not SHA256 of the complete transport bytes.
            try FindingOwnerRevisionReferenceV1(workspaceID: workspaceID, kind: kind, ownerID: ownerID,
                ownerRevision: ownerRevision, recordSHA256: recordSHA256)
        }
    }

    init(workspaceID: WorkspaceID, kind: FindingOwnerKindV1, ownerID: UUID, ownerRevision: UInt64,
         predecessor: FindingOwnerRevisionReferenceV1? = nil, mutationID: MutationIDV1,
         recordedBy: ActorSnapshotV1, recordedAt: Date, origin: FindingOwnerOriginIdentityV1,
         finding: FindingOwnedFactsV1? = nil, relationship: FindingOwnedRelationshipV1? = nil,
         recordSHA256: String? = nil) throws {
        self.workspaceID = workspaceID
        self.kind = kind
        self.ownerID = ownerID
        self.ownerRevision = ownerRevision
        self.predecessor = predecessor
        self.mutationID = mutationID
        self.recordedBy = recordedBy
        self.recordedAt = recordedAt
        self.origin = origin
        self.finding = finding
        self.relationship = relationship
        let basis = Basis(workspaceID: workspaceID, kind: kind, ownerID: ownerID, ownerRevision: ownerRevision,
            predecessor: predecessor, mutationID: mutationID, recordedBy: recordedBy, recordedAt: recordedAt,
            origin: origin, finding: finding, relationship: relationship)
        self.recordSHA256 = try recordSHA256 ?? WorkspaceMutationCanonicalV1.sha256(basis)
        try validate()
    }

    func validate() throws {
        try FindingOwnerValueValidationV1.id(workspaceID.rawValue)
        try FindingOwnerValueValidationV1.id(ownerID)
        try FindingOwnerValueValidationV1.id(mutationID.rawValue)
        try origin.validate()
        try recordedBy.validate()
        guard ownerRevision > 0, origin.kind == kind, origin.ownerID == ownerID,
              recordedBy.workspaceID == workspaceID, recordedBy.responsibility == .recordedBy,
              recordedAt.timeIntervalSince1970.isFinite,
              recordedBy.capturedAt <= recordedAt,
              KernelCanonicalHashV1.validSHA256(recordSHA256) else {
            throw FindingContractFailureV1.invalidValue
        }
        if let predecessor {
            try predecessor.validate()
            guard predecessor.workspaceID == workspaceID, predecessor.kind == kind, predecessor.ownerID == ownerID,
                  predecessor.ownerRevision < UInt64.max,
                  ownerRevision == predecessor.ownerRevision + 1 else {
                throw FindingContractFailureV1.staleRevision
            }
        } else {
            guard ownerRevision == 1 else { throw FindingContractFailureV1.staleRevision }
            if origin.workspaceID == workspaceID {
                guard origin.creationMutationID == mutationID else { throw FindingContractFailureV1.invalidValue }
            }
        }
        switch kind {
        case .finding:
            guard let finding, relationship == nil else { throw FindingContractFailureV1.invalidValue }
            try finding.validate(workspaceID: workspaceID)
        case .relationship:
            guard let relationship, finding == nil else { throw FindingContractFailureV1.invalidValue }
            try relationship.validate(workspaceID: workspaceID)
        }
        guard recordSHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else {
            throw FindingContractFailureV1.hashMismatch
        }
        _ = try FindingOwnerValueValidationV1.canonical(Wire(record: self))
    }

    func validateAppendOnlySuccessor(of prior: Self) throws {
        try prior.validate()
        try validate()
        guard workspaceID == prior.workspaceID, kind == prior.kind, ownerID == prior.ownerID,
              predecessor == (try prior.reference), origin == prior.origin,
              mutationID != prior.mutationID, recordedAt >= prior.recordedAt else {
            throw FindingContractFailureV1.historyRewrite
        }
        switch kind {
        case .finding:
            guard let finding, let previous = prior.finding else { throw FindingContractFailureV1.invalidValue }
            try finding.validateAppendOnlySuccessor(of: previous)
        case .relationship:
            guard let relationship, let previous = prior.relationship else { throw FindingContractFailureV1.invalidValue }
            try relationship.validateAppendOnlySuccessor(of: previous)
        }
    }

    private var basis: Basis {
        Basis(workspaceID: workspaceID, kind: kind, ownerID: ownerID, ownerRevision: ownerRevision,
              predecessor: predecessor, mutationID: mutationID, recordedBy: recordedBy, recordedAt: recordedAt,
              origin: origin, finding: finding, relationship: relationship)
    }

    private struct Basis: Encodable {
        let workspaceID: WorkspaceID
        let kind: FindingOwnerKindV1
        let ownerID: UUID
        let ownerRevision: UInt64
        let predecessor: FindingOwnerRevisionReferenceV1?
        let mutationID: MutationIDV1
        let recordedBy: ActorSnapshotV1
        let recordedAt: Date
        let origin: FindingOwnerOriginIdentityV1
        let finding: FindingOwnedFactsV1?
        let relationship: FindingOwnedRelationshipV1?
    }

    private struct Wire: Encodable {
        let record: FindingOwnerRecordV1
        func encode(to encoder: any Encoder) throws { try record.encodeFields(to: encoder) }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case workspaceID, kind, ownerID, ownerRevision, predecessor, mutationID, recordedBy, recordedAt
        case origin, finding, relationship, recordSHA256
    }

    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireClosed(decoder, allowed: CodingKeys.allCases.map(\.rawValue),
            required: ["workspaceID", "kind", "ownerID", "ownerRevision", "mutationID", "recordedBy",
                       "recordedAt", "origin", "recordSHA256"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        for key in [CodingKeys.predecessor, .finding, .relationship] {
            if c.contains(key), try c.decodeNil(forKey: key) { throw FindingContractFailureV1.invalidValue }
        }
        try self.init(workspaceID: FindingOwnerValueValidationV1.workspace(c.superDecoder(forKey: .workspaceID)),
            kind: c.decode(FindingOwnerKindV1.self, forKey: .kind), ownerID: c.decode(UUID.self, forKey: .ownerID),
            ownerRevision: c.decode(UInt64.self, forKey: .ownerRevision),
            predecessor: c.decodeIfPresent(FindingOwnerRevisionReferenceV1.self, forKey: .predecessor),
            mutationID: c.decode(MutationIDV1.self, forKey: .mutationID),
            recordedBy: FindingOwnerValueValidationV1.actor(c.superDecoder(forKey: .recordedBy)),
            recordedAt: c.decode(Date.self, forKey: .recordedAt),
            origin: c.decode(FindingOwnerOriginIdentityV1.self, forKey: .origin),
            finding: c.decodeIfPresent(FindingOwnedFactsV1.self, forKey: .finding),
            relationship: c.decodeIfPresent(FindingOwnedRelationshipV1.self, forKey: .relationship),
            recordSHA256: c.decode(String.self, forKey: .recordSHA256))
    }

    func encode(to encoder: any Encoder) throws {
        try validate()
        try encodeFields(to: encoder)
    }

    private func encodeFields(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(workspaceID, forKey: .workspaceID)
        try c.encode(kind, forKey: .kind)
        try c.encode(ownerID, forKey: .ownerID)
        try c.encode(ownerRevision, forKey: .ownerRevision)
        try c.encodeIfPresent(predecessor, forKey: .predecessor)
        try c.encode(mutationID, forKey: .mutationID)
        try c.encode(recordedBy, forKey: .recordedBy)
        try c.encode(recordedAt, forKey: .recordedAt)
        try c.encode(origin, forKey: .origin)
        try c.encodeIfPresent(finding, forKey: .finding)
        try c.encodeIfPresent(relationship, forKey: .relationship)
        try c.encode(recordSHA256, forKey: .recordSHA256)
    }
}

enum FindingOwnerCanonicalCodecV1 {
    static func encode(_ value: FindingOwnerRecordV1) throws -> Data {
        try value.validate()
        return try FindingOwnerValueValidationV1.canonical(value)
    }

    static func decode(_ bytes: Data) throws -> FindingOwnerRecordV1 {
        guard !bytes.isEmpty, bytes.count <= FindingContractLimitsV1.maximumCanonicalBytes else {
            throw FindingContractFailureV1.limitExceeded
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(FindingOwnerRecordV1.self, from: bytes)
        guard try encode(value) == bytes else { throw FindingContractFailureV1.canonicalEvidenceIncomplete }
        return value
    }
}

enum FindingOwnerCandidateRelationV1: Equatable, Sendable {
    case newStream
    case append
    /// Canonical value equality only. A checked journal receipt is still required
    /// before the writer can recognize an accepted retry or recovery attempt.
    case identicalHistoricalValue
}

enum FindingOwnerHistoryV1 {
    static let maximumHistoryRecords = FindingContractLimitsV1.maximumRegistryEntries
    static let maximumOwnerStreams = FindingContractLimitsV1.maximumRegistryEntries

    static func validate(_ history: [FindingOwnerRecordV1]) throws {
        guard !history.isEmpty, history.count <= maximumHistoryRecords else {
            throw FindingContractFailureV1.limitExceeded
        }
        var mutations = Set<MutationIDV1>()
        var immutableFacts = FindingOwnerImmutableFactCensusV1()
        for (index, record) in history.enumerated() {
            try record.validate()
            try immutableFacts.include(record)
            guard mutations.insert(record.mutationID).inserted else { throw FindingContractFailureV1.duplicateIdentity }
            if index == 0 {
                guard record.ownerRevision == 1, record.predecessor == nil else {
                    throw FindingContractFailureV1.historyRewrite
                }
            } else {
                try record.validateAppendOnlySuccessor(of: history[index - 1])
            }
        }
    }

    static func classify(_ candidate: FindingOwnerRecordV1,
                         against history: [FindingOwnerRecordV1]) throws -> FindingOwnerCandidateRelationV1 {
        try candidate.validate()
        guard let head = history.last else {
            guard candidate.ownerRevision == 1, candidate.predecessor == nil else {
                throw FindingContractFailureV1.historyRewrite
            }
            return .newStream
        }
        try validate(history)
        guard candidate.workspaceID == head.workspaceID, candidate.kind == head.kind,
              candidate.ownerID == head.ownerID else { throw FindingContractFailureV1.historyRewrite }
        if let original = history.first(where: { $0.ownerRevision == candidate.ownerRevision }) {
            guard try FindingOwnerCanonicalCodecV1.encode(candidate) == FindingOwnerCanonicalCodecV1.encode(original) else {
                throw FindingContractFailureV1.historyRewrite
            }
            return .identicalHistoricalValue
        }
        guard history.count < maximumHistoryRecords,
              !history.contains(where: { $0.mutationID == candidate.mutationID }) else {
            throw FindingContractFailureV1.duplicateIdentity
        }
        try candidate.validateAppendOnlySuccessor(of: head)
        return .append
    }

    /// Bounded current-head value census, not a query proving these are all the
    /// real heads. Authentication, completeness and currentness remain writer-owned.
    static func validateHeads(_ heads: [FindingOwnerRecordV1], workspaceID: WorkspaceID) throws {
        try FindingOwnerValueValidationV1.id(workspaceID.rawValue)
        guard heads.count <= maximumOwnerStreams else { throw FindingContractFailureV1.limitExceeded }
        var ownerIDs = Set<UUID>()
        var findingIDs = Set<String>()
        var findingBindings: [UUID: String] = [:]
        var suggestionIDs = Set<String>()
        var endpoints: [FindingRelationshipEndpointReferenceV1] = []
        var acceptances: [FindingAcceptedMutationReferenceV1] = []
        var immutableFacts = FindingOwnerImmutableFactCensusV1()
        for record in heads {
            try record.validate()
            try immutableFacts.include(record)
            guard record.workspaceID == workspaceID else { throw FindingContractFailureV1.invalidValue }
            guard ownerIDs.insert(record.ownerID).inserted else { throw FindingContractFailureV1.duplicateIdentity }
            switch record.kind {
            case .finding:
                guard let finding = record.finding,
                      findingIDs.insert(finding.evidence.finding.findingID).inserted else {
                    throw FindingContractFailureV1.duplicateIdentity
                }
                findingBindings[record.ownerID] = finding.evidence.finding.findingID
                acceptances.append(contentsOf: finding.acceptedMutationReferences)
            case .relationship:
                guard let relationship = record.relationship,
                      suggestionIDs.insert(relationship.suggestion.suggestionID).inserted else {
                    throw FindingContractFailureV1.duplicateIdentity
                }
                endpoints.append(relationship.source)
                endpoints.append(relationship.candidate)
                acceptances.append(contentsOf: relationship.source.owner.acceptedMutationReferences)
                acceptances.append(contentsOf: relationship.candidate.owner.acceptedMutationReferences)
            }
        }
        try validateEndpointIdentities(endpoints, knownFindings: findingBindings)
        try FindingOwnerValueValidationV1.acceptances(acceptances)
    }

    /// The caller supplies an affected C04 closure, not every unrelated stream
    /// in a workspace. Actual membership and source selection remain writer-owned.
    static func validateRelationshipClosure(_ records: [FindingOwnerRecordV1], workspaceID: WorkspaceID) throws {
        try validateHeads(records, workspaceID: workspaceID)
        var suggestions: [RelatedWorkSuggestionV1] = []
        var relationships: [WorkRelationshipV1] = []
        var decisions: [WorkRelationshipDecisionV1] = []
        for record in records {
            guard let relationship = record.relationship, record.kind == .relationship else {
                throw FindingContractFailureV1.invalidValue
            }
            suggestions.append(relationship.suggestion)
            if let value = relationship.relationship { relationships.append(value) }
            decisions.append(contentsOf: relationship.decisions)
        }
        // Reuse exact incumbent reverse-pair, duplicate, cycle and decision laws;
        // no derived inference from a live suggestion can create confirmation.
        try WorkRelationshipValidatorV1.validateSuggestions(suggestions)
        try WorkRelationshipValidatorV1.validate(relationships)
        try WorkRelationshipDecisionLedgerV1.validate(decisions)
    }

    private enum EndpointIdentity: Hashable {
        case finding(UUID)
        case correctiveAction(UUID)
    }

    static func validateEndpointIdentities(_ endpoints: [FindingRelationshipEndpointReferenceV1],
                                           knownFindings: [UUID: String] = [:]) throws {
        var owners: [String: EndpointIdentity] = [:]
        var tokens: [EndpointIdentity: String] = [:]
        var immutableFacts = FindingOwnerImmutableFactCensusV1()
        for (ownerID, findingID) in knownFindings {
            owners[findingID] = .finding(ownerID)
            tokens[.finding(ownerID)] = findingID
        }
        for endpoint in endpoints {
            try immutableFacts.include(endpoint.owner)
            let identity: EndpointIdentity
            switch endpoint.owner {
            case let .finding(reference): identity = .finding(reference.selected.ownerID)
            case let .correctiveAction(reference): identity = .correctiveAction(reference.selected.actionID)
            }
            if let prior = owners[endpoint.workID], prior != identity {
                throw FindingContractFailureV1.duplicateIdentity
            }
            if let prior = tokens[identity], !prior.utf8.elementsEqual(endpoint.workID.utf8) {
                throw FindingContractFailureV1.duplicateIdentity
            }
            owners[endpoint.workID] = identity
            tokens[identity] = endpoint.workID
        }
    }
}

/// Consistency of supplied immutable facts only. Matching hashes do not prove
/// acceptance, currentness, a valid Fork mapping or complete query membership.
private struct FindingOwnerImmutableFactCensusV1 {
    private struct OwnerKey: Hashable {
        let workspace: UUID
        let kind: String
        let owner: UUID
        let revision: UInt64
    }
    private struct ActionKey: Hashable {
        let workspace: UUID
        let action: UUID
        let revision: UInt64
    }
    private struct EventKey: Hashable {
        let workspace: UUID
        let event: UUID
    }
    private struct ActionFact: Equatable {
        let event: UUID
        let digest: String
    }
    private struct EventFact: Equatable {
        let action: UUID
        let revision: UInt64
        let digest: String
    }
    private struct ActivityKey: Hashable {
        let workspace: UUID
        let activity: UUID
        let revision: UInt64
    }
    private struct ActivityFact: Equatable {
        let kind: ActivityKindV2
        let digest: String
    }

    private var owners: [OwnerKey: String] = [:]
    private var actions: [ActionKey: ActionFact] = [:]
    private var events: [EventKey: EventFact] = [:]
    private var activities: [ActivityKey: ActivityFact] = [:]

    private static func retain<Key: Hashable, Value: Equatable>(
        _ key: Key, _ value: Value, in values: inout [Key: Value]
    ) throws {
        if let existing = values[key], existing != value {
            throw FindingContractFailureV1.historyRewrite
        }
        values[key] = value
    }

    private mutating func include(_ value: FindingOwnerRevisionReferenceV1) throws {
        let key = OwnerKey(workspace: value.workspaceID.rawValue, kind: value.kind.rawValue,
                           owner: value.ownerID, revision: value.ownerRevision)
        try Self.retain(key, value.recordSHA256, in: &owners)
    }

    private mutating func include(_ value: FindingCorrectiveEventReferenceV1) throws {
        let action = ActionKey(workspace: value.workspaceID.rawValue, action: value.actionID,
                               revision: value.eventRevision)
        let event = EventKey(workspace: value.workspaceID.rawValue, event: value.eventID)
        try Self.retain(action, ActionFact(event: value.eventID, digest: value.eventSHA256), in: &actions)
        try Self.retain(event, EventFact(action: value.actionID, revision: value.eventRevision,
                                        digest: value.eventSHA256), in: &events)
    }

    private mutating func include(_ value: FindingSourceContextV1) throws {
        let key = ActivityKey(workspace: value.workspaceID.rawValue, activity: value.activityID,
                              revision: value.activityRevision)
        // Distinct task/scope selections may refer to one immutable activity.
        try Self.retain(key, ActivityFact(kind: value.activityKind, digest: value.activitySHA256), in: &activities)
    }

    mutating func include(_ value: FindingOwnedFactsV1) throws {
        if let source = value.activitySource {
            try include(source.original)
            try include(source.selected)
        }
        for support in value.correctiveActions {
            try include(support.original)
            try include(support.selected)
        }
    }

    mutating func include(_ value: FindingRelationshipEndpointOwnerV1) throws {
        switch value {
        case let .finding(reference):
            try include(reference.original)
            try include(reference.selected)
        case let .correctiveAction(reference):
            try include(reference.original)
            try include(reference.selected)
        }
    }

    mutating func include(_ value: FindingOwnerRecordV1) throws {
        try include(value.reference)
        if let predecessor = value.predecessor { try include(predecessor) }
        if let finding = value.finding { try include(finding) }
        if let relationship = value.relationship {
            try include(relationship.source.owner)
            try include(relationship.candidate.owner)
        }
    }
}

/// Immutable origin identity, not proof of a receipt or an authenticated import.
/// Its creation attempt has no hash of the record/receipt it is still creating.
struct FindingOwnerOriginIdentityV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let kind: FindingOwnerKindV1
    let ownerID: UUID
    let creationMutationID: MutationIDV1

    init(workspaceID: WorkspaceID, kind: FindingOwnerKindV1, ownerID: UUID,
         creationMutationID: MutationIDV1) throws {
        self.workspaceID = workspaceID
        self.kind = kind
        self.ownerID = ownerID
        self.creationMutationID = creationMutationID
        try validate()
    }

    func validate() throws {
        try FindingOwnerValueValidationV1.id(workspaceID.rawValue)
        try FindingOwnerValueValidationV1.id(ownerID)
        try FindingOwnerValueValidationV1.id(creationMutationID.rawValue)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case workspaceID, kind, ownerID, creationMutationID
    }

    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(workspaceID: FindingOwnerValueValidationV1.workspace(c.superDecoder(forKey: .workspaceID)),
            kind: c.decode(FindingOwnerKindV1.self, forKey: .kind), ownerID: c.decode(UUID.self, forKey: .ownerID),
            creationMutationID: c.decode(MutationIDV1.self, forKey: .creationMutationID))
    }

    func encode(to encoder: any Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(workspaceID, forKey: .workspaceID)
        try c.encode(kind, forKey: .kind)
        try c.encode(ownerID, forKey: .ownerID)
        try c.encode(creationMutationID, forKey: .creationMutationID)
    }
}

/// Finding-owned C04 facts only. Relationship facts remain in their shared owner;
/// these empty local arrays do not assert that no incident relationships exist.
struct FindingOwnedFactsV1: Codable, Equatable, Sendable {
    let evidence: FindingLifecycleCanonicalEvidenceV1
    let activitySource: FindingActivitySourceReferenceV1?
    let correctiveActions: [FindingC14SupportReferenceV1]

    var acceptedMutationReferences: [FindingAcceptedMutationReferenceV1] {
        var values: [FindingAcceptedMutationReferenceV1] = []
        if let activitySource {
            values.append(activitySource.originalAcceptance)
            values.append(activitySource.selectedAcceptance)
        }
        for support in correctiveActions {
            values.append(support.original.acceptance)
            values.append(support.selected.acceptance)
        }
        return values
    }

    init(evidence: FindingLifecycleCanonicalEvidenceV1,
         activitySource: FindingActivitySourceReferenceV1? = nil,
         correctiveActions: [FindingC14SupportReferenceV1] = []) throws {
        self.evidence = evidence
        self.activitySource = activitySource
        self.correctiveActions = correctiveActions
        try validate()
    }

    func validate() throws {
        try FindingOwnerC04SafetyV1.evidence(evidence)
        guard evidence.relatedWorkSuggestions.isEmpty, evidence.workRelationships.isEmpty,
              evidence.workRelationshipDecisions.isEmpty else {
            throw FindingContractFailureV1.canonicalEvidenceIncomplete
        }
        _ = try FindingLifecycleCanonicalEvidenceCodecV1.encode(evidence)
        try activitySource?.validate()
        guard correctiveActions.count <= FindingContractLimitsV1.maximumRegistryEntries else {
            throw FindingContractFailureV1.limitExceeded
        }
        var immutableFacts = FindingOwnerImmutableFactCensusV1()
        try immutableFacts.include(self)
        var keys = Set<CorrectiveKey>()
        var previous: FindingC14SupportReferenceV1?
        for support in correctiveActions {
            try support.validate()
            let key = CorrectiveKey(workID: support.correctiveWorkID, workRevision: support.correctiveWorkRevision,
                                    eventRevision: support.selected.eventRevision)
            guard keys.insert(key).inserted else { throw FindingContractFailureV1.duplicateIdentity }
            if let previous {
                guard Self.precedes(previous, support) else { throw FindingContractFailureV1.invalidValue }
            }
            let bound = evidence.correctiveWorkLinks.filter {
                $0.workID.utf8.elementsEqual(support.correctiveWorkID.utf8)
                    && $0.workRevision == support.correctiveWorkRevision
                    && $0.action == .linked
            }
            guard !bound.isEmpty else { throw FindingContractFailureV1.missingTarget }
            // This checks the original genuine C14 identity; Fork keeps that
            // kernel String while selected destination mapping is authenticated
            // by the writer. Retained old links are not necessarily active now.
            for link in bound {
                try link.validateCorrectiveActionSource(findingID: evidence.finding.findingID,
                    findingRevision: link.findingRevision, actionID: support.original.actionID)
            }
            previous = support
        }
        try FindingOwnerValueValidationV1.acceptances(acceptedMutationReferences)
    }

    func validate(workspaceID: WorkspaceID) throws {
        try validate()
        if let activitySource {
            guard activitySource.selected.workspaceID == workspaceID else { throw FindingContractFailureV1.invalidValue }
        }
        for support in correctiveActions {
            guard support.selected.workspaceID == workspaceID else { throw FindingContractFailureV1.invalidValue }
        }
    }

    func validateAppendOnlySuccessor(of prior: Self) throws {
        try prior.validate()
        try validate()
        let old = prior.evidence
        let new = evidence
        // Lifecycle advances the revision of the original Finding, not its
        // subject, source, severity, summary or stable String identity.
        let expected = try FindingV1(findingID: old.finding.findingID, revision: new.finding.revision,
            severity: old.finding.severity, categoryID: old.finding.categoryID, subject: old.finding.subject,
            source: old.finding.source, summary: old.finding.summary)
        guard try FindingOwnerValueValidationV1.sameBytes(expected, new.finding),
              try FindingOwnerValueValidationV1.sameBytes(prior.activitySource, activitySource),
              old.lifecycle.initialRevision == new.lifecycle.initialRevision,
              old.lifecycle.initialState == new.lifecycle.initialState,
              old.lifecycle.transitions.count <= new.lifecycle.transitions.count else {
            throw FindingContractFailureV1.historyRewrite
        }
        for (index, transition) in old.lifecycle.transitions.enumerated() {
            guard try FindingOwnerValueValidationV1.sameBytes(transition, new.lifecycle.transitions[index]) else {
                throw FindingContractFailureV1.historyRewrite
            }
        }
        try FindingOwnerValueValidationV1.retained(old.correctiveWorkLinks, in: new.correctiveWorkLinks, identity: \.linkID)
        try FindingOwnerValueValidationV1.retained(old.verifiedRechecks, in: new.verifiedRechecks, identity: \.recheckID)
        try FindingOwnerValueValidationV1.retained(old.releasesToService, in: new.releasesToService, identity: \.releaseID)
        try FindingOwnerValueValidationV1.retained(old.operationalDispositionEvents,
            in: new.operationalDispositionEvents, identity: \.eventID)
        // Composite identity retains every accepted historical C14 binding, even
        // after its action's selected head advances without a Finding revision.
        try FindingOwnerValueValidationV1.retained(prior.correctiveActions, in: correctiveActions) { support in
            "\(support.correctiveWorkID)|\(support.correctiveWorkRevision)|\(support.selected.eventRevision)"
        }
        guard !(try FindingOwnerValueValidationV1.sameBytes(prior, self)) else {
            throw FindingContractFailureV1.invalidTransition
        }
    }

    private struct CorrectiveKey: Hashable {
        let workID: String
        let workRevision: Int
        let eventRevision: UInt64
    }

    private static func precedes(_ lhs: FindingC14SupportReferenceV1, _ rhs: FindingC14SupportReferenceV1) -> Bool {
        if lhs.correctiveWorkID != rhs.correctiveWorkID {
            return lhs.correctiveWorkID.utf8.lexicographicallyPrecedes(rhs.correctiveWorkID.utf8)
        }
        if lhs.correctiveWorkRevision != rhs.correctiveWorkRevision {
            return lhs.correctiveWorkRevision < rhs.correctiveWorkRevision
        }
        return lhs.selected.eventRevision < rhs.selected.eventRevision
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case evidence, activitySource, correctiveActions }

    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireClosed(decoder, allowed: CodingKeys.allCases.map(\.rawValue),
                                               required: ["evidence", "correctiveActions"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.activitySource), try c.decodeNil(forKey: .activitySource) {
            throw FindingContractFailureV1.invalidValue
        }
        let safe = try c.decode(FindingOwnerC04SafetyV1.Evidence.self, forKey: .evidence)
        try self.init(evidence: safe.value,
            activitySource: c.decodeIfPresent(FindingActivitySourceReferenceV1.self, forKey: .activitySource),
            correctiveActions: FindingOwnerValueValidationV1.array(FindingC14SupportReferenceV1.self,
                decoder: c.superDecoder(forKey: .correctiveActions), maximum: FindingContractLimitsV1.maximumRegistryEntries))
    }

    func encode(to encoder: any Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(evidence, forKey: .evidence)
        try c.encodeIfPresent(activitySource, forKey: .activitySource)
        try c.encode(correctiveActions, forKey: .correctiveActions)
    }
}

enum FindingRelationshipEndpointOwnerV1: Codable, Equatable, Sendable {
    case finding(FindingSelectedOwnerReferenceV1)
    case correctiveAction(FindingC14SupportReferenceV1)

    var selectedWorkspaceID: WorkspaceID {
        switch self {
        case let .finding(value): return value.selected.workspaceID
        case let .correctiveAction(value): return value.selected.workspaceID
        }
    }

    var acceptedMutationReferences: [FindingAcceptedMutationReferenceV1] {
        switch self {
        case let .finding(value): return [value.originalAcceptance, value.selectedAcceptance]
        case let .correctiveAction(value): return [value.original.acceptance, value.selected.acceptance]
        }
    }

    func validate() throws {
        switch self {
        case let .finding(value):
            try value.validate()
            guard value.original.kind == .finding, value.selected.kind == .finding else {
                throw FindingContractFailureV1.invalidValue
            }
        case let .correctiveAction(value):
            try value.validate()
            guard let revision = Int(exactly: value.original.eventRevision),
                  value.correctiveWorkRevision == revision,
                  value.correctiveWorkID == value.original.actionID.uuidString.lowercased() else {
                throw FindingContractFailureV1.invalidValue
            }
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case kind, finding, correctiveAction }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "finding":
            try FindingClosedCodingV1.requireExact(decoder, keys: ["kind", "finding"])
            self = .finding(try c.decode(FindingSelectedOwnerReferenceV1.self, forKey: .finding))
        case "correctiveAction":
            try FindingClosedCodingV1.requireExact(decoder, keys: ["kind", "correctiveAction"])
            self = .correctiveAction(try c.decode(FindingC14SupportReferenceV1.self, forKey: .correctiveAction))
        default: throw FindingContractFailureV1.incompatibleVersion
        }
        try validate()
    }

    func encode(to encoder: any Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .finding(value):
            try c.encode("finding", forKey: .kind)
            try c.encode(value, forKey: .finding)
        case let .correctiveAction(value):
            try c.encode("correctiveAction", forKey: .kind)
            try c.encode(value, forKey: .correctiveAction)
        }
    }
}

struct FindingRelationshipEndpointReferenceV1: Codable, Equatable, Sendable {
    let workID: String
    let workRevision: Int
    let owner: FindingRelationshipEndpointOwnerV1

    init(workID: String, workRevision: Int, owner: FindingRelationshipEndpointOwnerV1) throws {
        self.workID = workID
        self.workRevision = workRevision
        self.owner = owner
        try validate()
    }

    func validate() throws {
        guard FindingContractValidationV1.validID(workID), workRevision >= 0 else {
            throw FindingContractFailureV1.invalidValue
        }
        try owner.validate()
        if case let .correctiveAction(value) = owner {
            guard workID.utf8.elementsEqual(value.correctiveWorkID.utf8),
                  workRevision == value.correctiveWorkRevision else { throw FindingContractFailureV1.invalidValue }
        }
    }

    /// This binds supplied values. Receipt authenticity and whether this exact
    /// owner is still current are deliberately outside this method.
    func validate(findingRecord record: FindingOwnerRecordV1) throws {
        try validate()
        try record.validate()
        guard case let .finding(reference) = owner, record.kind == .finding,
              reference.selected == (try record.reference), let facts = record.finding,
              workID.utf8.elementsEqual(facts.evidence.finding.findingID.utf8),
              workRevision == facts.evidence.finding.revision else { throw FindingContractFailureV1.invalidValue }
    }

    /// C14 can originate from a review, criterion, evidence or other genuine
    /// closed source. Only a Finding source needs the separate Finding dependency.
    func validate(originalCorrectiveEvent original: CorrectiveActionEventV1,
                  selectedCorrectiveEvent selected: CorrectiveActionEventV1) throws {
        try validate()
        guard case let .correctiveAction(reference) = owner else { throw FindingContractFailureV1.invalidValue }
        try Self.bind(original, reference: reference.original)
        try Self.bind(selected, reference: reference.selected)
    }

    private static func bind(_ event: CorrectiveActionEventV1, reference: FindingCorrectiveEventReferenceV1) throws {
        try event.validate()
        guard event.workspaceID == reference.workspaceID, event.actionID == reference.actionID,
              event.eventID == reference.eventID, event.revision == reference.eventRevision,
              event.eventSHA256 == reference.eventSHA256, event.mutationID == reference.acceptance.mutationID else {
            throw FindingContractFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case workID, workRevision, owner }
    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(workID: c.decode(String.self, forKey: .workID), workRevision: c.decode(Int.self, forKey: .workRevision),
                      owner: c.decode(FindingRelationshipEndpointOwnerV1.self, forKey: .owner))
    }
    func encode(to encoder: any Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(workID, forKey: .workID)
        try c.encode(workRevision, forKey: .workRevision)
        try c.encode(owner, forKey: .owner)
    }
}

/// One frozen decision basis and one shared history. A stored remove decision
/// retains its original relationship value; it does not erase the confirmation.
struct FindingOwnedRelationshipV1: Codable, Equatable, Sendable {
    let suggestion: RelatedWorkSuggestionV1
    let source: FindingRelationshipEndpointReferenceV1
    let candidate: FindingRelationshipEndpointReferenceV1
    let relationship: WorkRelationshipV1?
    let decisions: [WorkRelationshipDecisionV1]

    init(suggestion: RelatedWorkSuggestionV1, source: FindingRelationshipEndpointReferenceV1,
         candidate: FindingRelationshipEndpointReferenceV1, relationship: WorkRelationshipV1? = nil,
         decisions: [WorkRelationshipDecisionV1]) throws {
        self.suggestion = suggestion
        self.source = source
        self.candidate = candidate
        self.relationship = relationship
        self.decisions = decisions
        try validate()
    }

    func validate() throws {
        try source.validate()
        try candidate.validate()
        try FindingOwnerHistoryV1.validateEndpointIdentities([source, candidate])
        var acceptances = source.owner.acceptedMutationReferences
        acceptances.append(contentsOf: candidate.owner.acceptedMutationReferences)
        try FindingOwnerValueValidationV1.acceptances(acceptances)
        guard !decisions.isEmpty, decisions.count <= FindingContractLimitsV1.maximumTransitions,
              source.workID.utf8.elementsEqual(suggestion.sourceWorkID.utf8),
              candidate.workID.utf8.elementsEqual(suggestion.candidateWorkID.utf8),
              source.workRevision == suggestion.sourceWorkRevision,
              candidate.workRevision == suggestion.candidateWorkRevision,
              source.owner.selectedWorkspaceID == candidate.owner.selectedWorkspaceID else {
            throw FindingContractFailureV1.invalidValue
        }
        // Constructors establish each individual C04 value; re-decoding its
        // exact canonical bytes also checks values supplied from legacy callers.
        _ = try JSONDecoder().decode(RelatedWorkSuggestionV1.self,
            from: FindingOwnerValueValidationV1.canonical(suggestion))
        try WorkRelationshipValidatorV1.validateSuggestions([suggestion])
        var relationships: [WorkRelationshipV1] = []
        if let relationship {
            _ = try JSONDecoder().decode(WorkRelationshipV1.self,
                from: FindingOwnerValueValidationV1.canonical(relationship))
            relationships.append(relationship)
        }
        try WorkRelationshipValidatorV1.validate(relationships)
        for decision in decisions {
            try FindingOwnerC04SafetyV1.incrementable(decision.expectedDecisionRevision)
            _ = try JSONDecoder().decode(WorkRelationshipDecisionV1.self,
                from: FindingOwnerValueValidationV1.canonical(decision))
            guard decision.suggestionID == suggestion.suggestionID,
                  decision.sourceWorkID == source.workID, decision.sourceWorkRevision == source.workRevision,
                  decision.candidateWorkID == candidate.workID, decision.candidateWorkRevision == candidate.workRevision,
                  decision.policySHA256 == suggestion.policySHA256 else {
                throw FindingContractFailureV1.canonicalEvidenceIncomplete
            }
            if decision.decision != .notRelated {
                guard let relationship, relationship.relationshipID == decision.relationshipID,
                      Self.matches(relationship, decision: decision) else {
                    throw FindingContractFailureV1.canonicalEvidenceIncomplete
                }
            }
        }
        try WorkRelationshipDecisionLedgerV1.validate(decisions)
        let confirmations = decisions.filter { $0.decision == .confirm }
        if relationship != nil {
            guard confirmations.count == 1 else { throw FindingContractFailureV1.canonicalEvidenceIncomplete }
        } else {
            guard confirmations.isEmpty else { throw FindingContractFailureV1.canonicalEvidenceIncomplete }
        }
    }

    func validate(workspaceID: WorkspaceID) throws {
        try validate()
        guard source.owner.selectedWorkspaceID == workspaceID,
              candidate.owner.selectedWorkspaceID == workspaceID else { throw FindingContractFailureV1.invalidValue }
    }

    func validateAppendOnlySuccessor(of prior: Self) throws {
        try prior.validate()
        try validate()
        guard try FindingOwnerValueValidationV1.sameBytes(suggestion, prior.suggestion),
              try FindingOwnerValueValidationV1.sameBytes(source, prior.source),
              try FindingOwnerValueValidationV1.sameBytes(candidate, prior.candidate),
              try FindingOwnerValueValidationV1.sameBytes(relationship, prior.relationship),
              decisions.count > prior.decisions.count else { throw FindingContractFailureV1.historyRewrite }
        for (index, decision) in prior.decisions.enumerated() {
            guard try FindingOwnerValueValidationV1.sameBytes(decision, decisions[index]) else {
                throw FindingContractFailureV1.historyRewrite
            }
        }
    }

    private static func matches(_ relationship: WorkRelationshipV1, decision: WorkRelationshipDecisionV1) -> Bool {
        let forward = relationship.sourceWorkID == decision.sourceWorkID
            && relationship.sourceWorkRevision == decision.sourceWorkRevision
            && relationship.targetWorkID == decision.candidateWorkID
            && relationship.targetWorkRevision == decision.candidateWorkRevision
        if relationship.direction == .directed { return forward }
        let reverse = relationship.sourceWorkID == decision.candidateWorkID
            && relationship.sourceWorkRevision == decision.candidateWorkRevision
            && relationship.targetWorkID == decision.sourceWorkID
            && relationship.targetWorkRevision == decision.sourceWorkRevision
        return forward || reverse
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case suggestion, source, candidate, relationship, decisions }
    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireClosed(decoder, allowed: CodingKeys.allCases.map(\.rawValue),
                                               required: ["suggestion", "source", "candidate", "decisions"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.relationship), try c.decodeNil(forKey: .relationship) { throw FindingContractFailureV1.invalidValue }
        try FindingOwnerC04SafetyV1.preflightDecisions(c.superDecoder(forKey: .decisions))
        try self.init(suggestion: c.decode(RelatedWorkSuggestionV1.self, forKey: .suggestion),
            source: c.decode(FindingRelationshipEndpointReferenceV1.self, forKey: .source),
            candidate: c.decode(FindingRelationshipEndpointReferenceV1.self, forKey: .candidate),
            relationship: c.decodeIfPresent(WorkRelationshipV1.self, forKey: .relationship),
            decisions: FindingOwnerValueValidationV1.array(WorkRelationshipDecisionV1.self,
                decoder: c.superDecoder(forKey: .decisions), maximum: FindingContractLimitsV1.maximumTransitions))
    }
    func encode(to encoder: any Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(suggestion, forKey: .suggestion)
        try c.encode(source, forKey: .source)
        try c.encode(candidate, forKey: .candidate)
        try c.encodeIfPresent(relationship, forKey: .relationship)
        try c.encode(decisions, forKey: .decisions)
    }
}

private enum FindingOwnerValueValidationV1 {
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    static func id(_ value: UUID) throws {
        guard value != zero else { throw FindingContractFailureV1.invalidValue }
    }

    static func workspace(_ decoder: any Decoder) throws -> WorkspaceID {
        try FindingClosedCodingV1.requireExact(decoder, keys: ["rawValue"])
        let value = try WorkspaceID(from: decoder)
        try id(value.rawValue)
        return value
    }

    private enum ActorKeys: String, CodingKey { case workspaceID, actor, partyID }
    static func actor(_ decoder: any Decoder) throws -> ActorSnapshotV1 {
        try FindingClosedCodingV1.requireExact(decoder, keys: ["schemaVersion", "snapshotID", "workspaceID", "actor",
            "responsibility", "displayNameAtTime", "capturedAt", "snapshotSHA256"])
        let c = try decoder.container(keyedBy: ActorKeys.self)
        _ = try workspace(c.superDecoder(forKey: .workspaceID))
        let actorDecoder = try c.superDecoder(forKey: .actor)
        try FindingClosedCodingV1.requireClosed(actorDecoder,
            allowed: ["schemaVersion", "actorReferenceID", "workspaceID", "partyID", "displayName"],
            required: ["schemaVersion", "actorReferenceID", "workspaceID", "displayName"])
        let local = try actorDecoder.container(keyedBy: ActorKeys.self)
        _ = try workspace(local.superDecoder(forKey: .workspaceID))
        if local.contains(.partyID), try local.decodeNil(forKey: .partyID) { throw FindingContractFailureV1.invalidValue }
        return try ActorSnapshotV1(from: decoder)
    }

    static func canonical<T: Encodable>(_ value: T) throws -> Data {
        let bytes = try WorkspaceMutationCanonicalV1.data(value)
        guard bytes.count <= FindingContractLimitsV1.maximumCanonicalBytes else {
            throw FindingContractFailureV1.limitExceeded
        }
        return bytes
    }

    static func sameBytes<T: Encodable>(_ lhs: T, _ rhs: T) throws -> Bool {
        try canonical(lhs) == canonical(rhs)
    }

    private struct AcceptanceKey: Hashable {
        let workspaceID: WorkspaceID
        let mutationID: MutationIDV1
    }

    static func acceptances(_ values: [FindingAcceptedMutationReferenceV1]) throws {
        var seen: [AcceptanceKey: FindingAcceptedMutationReferenceV1] = [:]
        for value in values {
            try value.validate()
            let key = AcceptanceKey(workspaceID: value.workspaceID, mutationID: value.mutationID)
            if let previous = seen[key], previous != value { throw FindingContractFailureV1.historyRewrite }
            seen[key] = value
        }
    }

    static func array<T: Decodable>(_ type: T.Type, decoder: any Decoder, maximum: Int) throws -> [T] {
        var c = try decoder.unkeyedContainer()
        if let count = c.count, count > maximum { throw FindingContractFailureV1.limitExceeded }
        var values: [T] = []
        while !c.isAtEnd {
            guard values.count < maximum else { throw FindingContractFailureV1.limitExceeded }
            values.append(try c.decode(type))
        }
        return values
    }

    /// Sorted C04 aggregates can insert a new event before another group's old
    /// tail. Match immutable event identities instead of requiring array prefix.
    static func retained<T: Encodable>(_ old: [T], in current: [T], identity: (T) -> String) throws {
        guard old.count <= current.count, current.count <= FindingContractLimitsV1.maximumRegistryEntries else {
            throw FindingContractFailureV1.historyRewrite
        }
        var currentByID: [String: Data] = [:]
        for value in current {
            let key = identity(value)
            guard currentByID[key] == nil else { throw FindingContractFailureV1.duplicateIdentity }
            currentByID[key] = try canonical(value)
        }
        var oldIDs = Set<String>()
        for value in old {
            let key = identity(value)
            guard oldIDs.insert(key).inserted,
                  currentByID[key] == (try canonical(value)) else {
                throw FindingContractFailureV1.historyRewrite
            }
        }
    }
}

/// The owner boundary delegates semantics to C04 after guarding arithmetic used
/// by its historical decoders. These checks never rewrite old C04 wire types.
private enum FindingOwnerC04SafetyV1 {
    private enum Keys: String, CodingKey {
        case lifecycle, initialRevision, transitions, expectedFindingRevision
        case correctiveWorkLinks, expectedLinkRevision
        case verifiedRechecks, expectedRecheckRevision
        case releasesToService, verifiedRecheckFindingRevision
        case operationalDispositionEvents, expectedDispositionRevision
        case workRelationshipDecisions, expectedDecisionRevision
    }

    static func incrementable(_ value: Int) throws {
        guard value >= 0, value < Int.max else { throw FindingContractFailureV1.invalidValue }
    }

    static func preflightEvidence(_ decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let lifecycle = try c.superDecoder(forKey: .lifecycle)
        let life = try lifecycle.container(keyedBy: Keys.self)
        let initial = try life.decode(Int.self, forKey: .initialRevision)
        let transitions = try life.nestedUnkeyedContainer(forKey: .transitions)
        if !transitions.isAtEnd { try incrementable(initial) }
        try scan(life.superDecoder(forKey: .transitions), field: .expectedFindingRevision,
                 maximum: FindingContractLimitsV1.maximumTransitions)
        try scan(c.superDecoder(forKey: .correctiveWorkLinks), field: .expectedLinkRevision,
                 maximum: FindingContractLimitsV1.maximumRegistryEntries)
        try scan(c.superDecoder(forKey: .verifiedRechecks), field: .expectedRecheckRevision,
                 maximum: FindingContractLimitsV1.maximumRegistryEntries)
        try scan(c.superDecoder(forKey: .releasesToService), field: .verifiedRecheckFindingRevision,
                 maximum: FindingContractLimitsV1.maximumRegistryEntries)
        try scan(c.superDecoder(forKey: .operationalDispositionEvents), field: .expectedDispositionRevision,
                 maximum: FindingContractLimitsV1.maximumRegistryEntries)
        try scan(c.superDecoder(forKey: .workRelationshipDecisions), field: .expectedDecisionRevision,
                 maximum: FindingContractLimitsV1.maximumRegistryEntries)
    }

    static func preflightDecisions(_ decoder: any Decoder) throws {
        try scan(decoder, field: .expectedDecisionRevision, maximum: FindingContractLimitsV1.maximumTransitions)
    }

    private static func scan(_ decoder: any Decoder, field: Keys, maximum: Int) throws {
        var c = try decoder.unkeyedContainer()
        if let count = c.count, count > maximum { throw FindingContractFailureV1.limitExceeded }
        var count = 0
        while !c.isAtEnd {
            guard count < maximum else { throw FindingContractFailureV1.limitExceeded }
            let entry = try c.superDecoder().container(keyedBy: Keys.self)
            try incrementable(entry.decode(Int.self, forKey: field))
            count += 1
        }
    }

    static func evidence(_ value: FindingLifecycleCanonicalEvidenceV1) throws {
        if !value.lifecycle.transitions.isEmpty { try incrementable(value.lifecycle.initialRevision) }
        for event in value.lifecycle.transitions { try incrementable(event.expectedFindingRevision) }
        for event in value.correctiveWorkLinks { try incrementable(event.expectedLinkRevision) }
        for event in value.verifiedRechecks { try incrementable(event.expectedRecheckRevision) }
        for event in value.releasesToService { try incrementable(event.verifiedRecheckFindingRevision) }
        for event in value.operationalDispositionEvents { try incrementable(event.expectedDispositionRevision) }
        for event in value.workRelationshipDecisions { try incrementable(event.expectedDecisionRevision) }
        try value.validate()
    }

    struct Evidence: Decodable {
        let value: FindingLifecycleCanonicalEvidenceV1
        init(from decoder: any Decoder) throws {
            try FindingOwnerC04SafetyV1.preflightEvidence(decoder)
            value = try FindingLifecycleCanonicalEvidenceV1(from: decoder)
            try FindingOwnerC04SafetyV1.evidence(value)
        }
    }
}

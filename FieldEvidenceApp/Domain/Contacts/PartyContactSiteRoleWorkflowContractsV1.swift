import Foundation

enum PartyContactSiteRoleWorkflowFailureV1: Error, Equatable, Sendable {
    case invalidContext
    case staleRevision
    case retiredParty
    case identityMismatch
    case preferredConflict
    case invalidReversal
    case receiptMismatch
}

enum PartyContactSiteRoleOperationV1: String, Codable, Equatable, Sendable {
    case createParty = "CREATE_PARTY"
    case editParty = "EDIT_PARTY"
    case retireParty = "RETIRE_PARTY"
    case createContact = "CREATE_CONTACT"
    case editContact = "EDIT_CONTACT"
    case retireContact = "RETIRE_CONTACT"
    case reactivateContact = "REACTIVATE_CONTACT"
    case setPreferredContact = "SET_PREFERRED_CONTACT"
    case appendSiteRole = "APPEND_SITE_ROLE"
    case reverseSiteRole = "REVERSE_SITE_ROLE"
}

enum PartyContactSiteRoleWarningV1: String, Codable, Equatable, Sendable {
    case equalValuesRemainDistinct = "EQUAL_VALUES_REMAIN_DISTINCT"
    case noCascade = "NO_CASCADE"
    case operationalPurposeOnly = "OPERATIONAL_PURPOSE_ONLY"
    case customerAndSiteLabelsArePresentationOnly = "CUSTOMER_AND_SITE_LABELS_ARE_PRESENTATION_ONLY"
}

/// Exact, zero-write impact. IDs are the only identity; names, contact values,
/// labels, and roles never participate in merging.
struct PartyContactSiteRoleImpactV1: Codable, Equatable, Sendable {
    let operation: PartyContactSiteRoleOperationV1
    let affectedPartyIDs: [UUID]
    let affectedContactPointIDs: [UUID]
    let affectedSiteRoleEventIDs: [UUID]
    let preferredScopes: [ServiceContactPreferredScopeV1]
    let cascadeCount: Int
    let identityMergeCount: Int
    let warnings: [PartyContactSiteRoleWarningV1]

    init(
        operation: PartyContactSiteRoleOperationV1,
        affectedPartyIDs: [UUID] = [],
        affectedContactPointIDs: [UUID] = [],
        affectedSiteRoleEventIDs: [UUID] = [],
        preferredScopes: [ServiceContactPreferredScopeV1] = []
    ) throws {
        let parties = affectedPartyIDs.sorted { $0.uuidString < $1.uuidString }
        let contacts = affectedContactPointIDs.sorted { $0.uuidString < $1.uuidString }
        let roles = affectedSiteRoleEventIDs.sorted { $0.uuidString < $1.uuidString }
        guard Set(parties).count == parties.count,
              Set(contacts).count == contacts.count,
              Set(roles).count == roles.count else {
            throw PartyContactSiteRoleWorkflowFailureV1.identityMismatch
        }
        let dimensionsAreExact: Bool
        switch operation {
        case .createParty, .editParty, .retireParty:
            dimensionsAreExact = parties.count == 1 && contacts.isEmpty && roles.isEmpty
                && preferredScopes.isEmpty
        case .createContact, .editContact, .retireContact,
             .reactivateContact, .setPreferredContact:
            dimensionsAreExact = parties.count == 1 && !contacts.isEmpty && roles.isEmpty
                && preferredScopes.count == 1
        case .appendSiteRole, .reverseSiteRole:
            dimensionsAreExact = parties.count == 1 && contacts.isEmpty && roles.count == 1
                && preferredScopes.isEmpty
        }
        guard dimensionsAreExact else {
            throw PartyContactSiteRoleWorkflowFailureV1.invalidContext
        }
        self.operation = operation
        self.affectedPartyIDs = parties
        self.affectedContactPointIDs = contacts
        self.affectedSiteRoleEventIDs = roles
        self.preferredScopes = preferredScopes.sorted {
            ($0.partyID.uuidString, $0.kind.rawValue)
                < ($1.partyID.uuidString, $1.kind.rawValue)
        }
        cascadeCount = 0
        identityMergeCount = 0
        warnings = [
            .equalValuesRemainDistinct,
            .noCascade,
            .operationalPurposeOnly,
            .customerAndSiteLabelsArePresentationOnly,
        ]
    }
}

struct PartyWorkflowPreviewV1: Equatable, Sendable {
    let plan: PartyAccountabilityChangePlanV1
    let impact: PartyContactSiteRoleImpactV1
    let zeroWrite: Bool

    init(plan: PartyAccountabilityChangePlanV1, impact: PartyContactSiteRoleImpactV1) throws {
        try plan.validate()
        guard case let .recordParty(successor) = plan.basis.mutation else {
            throw PartyContactSiteRoleWorkflowFailureV1.invalidContext
        }
        let operationIsExact =
            (impact.operation == .createParty && successor.revision == 1 && successor.state == .effective)
            || (impact.operation == .editParty && successor.revision > 1 && successor.state == .effective)
            || (impact.operation == .retireParty && successor.revision > 1 && successor.state == .retired)
        guard operationIsExact,
              impact.affectedPartyIDs == [successor.partyID],
              impact.affectedContactPointIDs.isEmpty,
              impact.affectedSiteRoleEventIDs.isEmpty,
              impact.preferredScopes.isEmpty,
              impact.cascadeCount == 0,
              impact.identityMergeCount == 0 else {
            throw PartyContactSiteRoleWorkflowFailureV1.invalidContext
        }
        self.plan = plan
        self.impact = impact
        zeroWrite = true
    }
}

struct OperationalContactWorkflowPreviewV1: Equatable, Sendable {
    let mutation: OperationalContactMutationV1
    let impact: PartyContactSiteRoleImpactV1
    let zeroWrite: Bool

    init(mutation: OperationalContactMutationV1, impact: PartyContactSiteRoleImpactV1) throws {
        try mutation.validate()
        let predecessorByID = Dictionary(uniqueKeysWithValues: mutation.predecessors.map {
            ($0.contactPointID, $0)
        })
        let creates = mutation.successors.filter { predecessorByID[$0.contactPointID] == nil }
        let retires = mutation.successors.filter {
            predecessorByID[$0.contactPointID]?.lifecycle == .effective && $0.lifecycle == .retired
        }
        let reactivates = mutation.successors.filter {
            predecessorByID[$0.contactPointID]?.lifecycle == .retired && $0.lifecycle == .effective
        }
        let contentEdits = mutation.successors.filter { successor in
            guard let predecessor = predecessorByID[successor.contactPointID] else { return false }
            return successor.label != predecessor.label
                || successor.displayValue != predecessor.displayValue
        }
        let preferredSelections = mutation.successors.filter { successor in
            predecessorByID[successor.contactPointID]?.preferred == false && successor.preferred
        }
        let operationIsExact: Bool
        switch impact.operation {
        case .createContact:
            operationIsExact = creates.count == 1 && creates[0].lifecycle == .effective
                && retires.isEmpty && reactivates.isEmpty
        case .editContact:
            operationIsExact = creates.isEmpty && retires.isEmpty && reactivates.isEmpty
                && contentEdits.count == 1
        case .retireContact:
            operationIsExact = creates.isEmpty && retires.count == 1 && reactivates.isEmpty
        case .reactivateContact:
            operationIsExact = creates.isEmpty && retires.isEmpty && reactivates.count == 1
        case .setPreferredContact:
            operationIsExact = creates.isEmpty && retires.isEmpty && reactivates.isEmpty
                && contentEdits.isEmpty && preferredSelections.count == 1
        default:
            operationIsExact = false
        }
        guard operationIsExact,
              impact.affectedPartyIDs == Array(Set(
            mutation.successors.map { $0.party.partyID }
        )).sorted(by: { $0.uuidString < $1.uuidString }),
              impact.affectedContactPointIDs == mutation.successors.map(\.contactPointID).sorted(
                by: { $0.uuidString < $1.uuidString }
              ),
              impact.preferredScopes == mutation.preferredScopes,
              impact.affectedSiteRoleEventIDs.isEmpty,
              impact.cascadeCount == 0,
              impact.identityMergeCount == 0 else {
            throw PartyContactSiteRoleWorkflowFailureV1.invalidContext
        }
        self.mutation = mutation
        self.impact = impact
        zeroWrite = true
    }
}

struct SiteRoleWorkflowPreviewV1: Equatable, Sendable {
    let plan: PartyAccountabilityChangePlanV1
    let predecessor: SitePartyRoleEventV1?
    let impact: PartyContactSiteRoleImpactV1
    let zeroWrite: Bool

    init(
        plan: PartyAccountabilityChangePlanV1,
        predecessor: SitePartyRoleEventV1?,
        impact: PartyContactSiteRoleImpactV1
    ) throws {
        try plan.validate()
        guard case let .appendSiteRole(successor) = plan.basis.mutation else {
            throw PartyContactSiteRoleWorkflowFailureV1.invalidContext
        }
        if let predecessor { try successor.validateSupersession(of: predecessor) }
        let operationIsExact = predecessor == nil
            ? impact.operation == .appendSiteRole && successor.supersedesEventID == nil
            : impact.operation == .reverseSiteRole
                && successor.supersedesEventID == predecessor?.eventID
        guard operationIsExact,
              impact.affectedPartyIDs == [successor.partyID],
              impact.affectedContactPointIDs.isEmpty,
              impact.affectedSiteRoleEventIDs == [successor.eventID],
              impact.preferredScopes.isEmpty,
              impact.cascadeCount == 0,
              impact.identityMergeCount == 0 else {
            throw PartyContactSiteRoleWorkflowFailureV1.invalidContext
        }
        self.plan = plan
        self.predecessor = predecessor
        self.impact = impact
        zeroWrite = true
    }
}

/// Party/contact revisions are the exact bounded values supplied by the read
/// owner. Site roles are append-only history and may be complete for a scope.
struct PartyContactSiteRoleHistoryProjectionV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let partyRevisions: [ServicePartyReferenceV1]
    let contactRevisions: [ServiceContactPointV1]
    let siteRoleEvents: [SitePartyRoleEventV1]
    let partyAndContactHistoryIsCallerBounded: Bool
    let siteRoleHistoryIsAppendOnly: Bool
    let customerPresentationLabel: String
    let sitePresentationLabel: String

    init(
        workspaceID: WorkspaceID,
        partyRevisions: [ServicePartyReferenceV1],
        contactRevisions: [ServiceContactPointV1],
        siteRoleEvents: [SitePartyRoleEventV1]
    ) throws {
        try partyRevisions.forEach { try $0.validate() }
        try contactRevisions.forEach { try $0.validate() }
        try siteRoleEvents.forEach { try $0.validate() }
        guard partyRevisions.allSatisfy({ $0.workspaceID == workspaceID }),
              contactRevisions.allSatisfy({ $0.workspaceID == workspaceID }),
              siteRoleEvents.allSatisfy({ $0.workspaceID == workspaceID }),
              Set(partyRevisions.map { "\($0.partyID)|\($0.revision)" }).count == partyRevisions.count,
              Set(contactRevisions.map { "\($0.contactPointID)|\($0.revision)" }).count == contactRevisions.count,
              Set(siteRoleEvents.map(\.eventID)).count == siteRoleEvents.count else {
            throw PartyContactSiteRoleWorkflowFailureV1.identityMismatch
        }
        self.workspaceID = workspaceID
        self.partyRevisions = partyRevisions.sorted {
            ($0.partyID.uuidString, $0.revision) < ($1.partyID.uuidString, $1.revision)
        }
        self.contactRevisions = contactRevisions.sorted {
            ($0.contactPointID.uuidString, $0.revision)
                < ($1.contactPointID.uuidString, $1.revision)
        }
        self.siteRoleEvents = siteRoleEvents.sorted {
            ($0.siteID.uuidString, $0.partyID.uuidString, $0.recordedAt, $0.eventID.uuidString)
                < ($1.siteID.uuidString, $1.partyID.uuidString, $1.recordedAt, $1.eventID.uuidString)
        }
        partyAndContactHistoryIsCallerBounded = true
        siteRoleHistoryIsAppendOnly = true
        customerPresentationLabel = "Customer"
        sitePresentationLabel = "Site"
    }
}

@MainActor
protocol PartyContactSiteRoleWorkflowQueryingV1: AnyObject {
    func currentParty(
        workspaceID: WorkspaceID,
        partyID: UUID
    ) async throws -> ServicePartyReferenceV1?

    /// Returns the complete current Party+kind scope. Historical embedded
    /// Party snapshots are accepted by stable workspace/Party/kind identity.
    func currentContactPoints(
        workspaceID: WorkspaceID,
        partyID: UUID,
        kind: ServiceContactKindV1
    ) async throws -> [ServiceContactPointV1]

    func siteRoleHistory(
        workspaceID: WorkspaceID,
        siteID: UUID,
        partyID: UUID?
    ) async throws -> [SitePartyRoleEventV1]
}

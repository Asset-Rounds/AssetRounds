import Foundation

/// One C32 aggregate is deliberately one ordinary workspace command: party
/// rows must exist before contact admission, and contact admission must finish
/// before append-only site-role events are recorded. Source bytes and C08
/// preview state remain outside this canonical mutation.
struct PartyContactSiteRoleImportMutationV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumPartyMutations = 256
    static let maximumSiteRoleMutations = 512

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let mutationID: MutationIDV1
    let expectedRevision: WorkspaceExpectedRevisionV1
    let partyMutations: [PartyAccountabilityMutationV1]
    let operationalContactMutation: OperationalContactMutationV1
    let siteRoleMutations: [PartyAccountabilityMutationV1]

    init(
        workspaceID: WorkspaceID,
        mutationID: MutationIDV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        partyMutations: [PartyAccountabilityMutationV1],
        operationalContactMutation: OperationalContactMutationV1,
        siteRoleMutations: [PartyAccountabilityMutationV1]
    ) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.mutationID = mutationID
        self.expectedRevision = expectedRevision
        self.partyMutations = partyMutations
        self.operationalContactMutation = operationalContactMutation
        self.siteRoleMutations = siteRoleMutations
        try validate()
    }

    func validate() throws {
        try operationalContactMutation.validate()
        let parties = try partyValues
        let roles = try siteRoleValues
        guard schemaVersion == Self.schemaVersion,
              expectedRevision.workspaceID == workspaceID,
              operationalContactMutation.workspaceID == workspaceID,
              operationalContactMutation.mutationID == mutationID,
              operationalContactMutation.expectedRevision == expectedRevision,
              !partyMutations.isEmpty,
              !siteRoleMutations.isEmpty,
              partyMutations.count <= Self.maximumPartyMutations,
              siteRoleMutations.count <= Self.maximumSiteRoleMutations,
              parties.map(\.partyID) == parties.map(\.partyID).sorted { $0.uuidString < $1.uuidString },
              roles.map(\.eventID) == roles.map(\.eventID).sorted { $0.uuidString < $1.uuidString },
              Set(parties.map(\.partyID)).count == parties.count,
              Set(roles.map(\.eventID)).count == roles.count,
              Set(parties.map(\.partyID)).isSuperset(of: roles.map(\.partyID)),
              Set(parties.map(\.partyID)).isSuperset(of: operationalContactMutation.successors.map(\.party.partyID)),
              Set(parties.map(\.partyID)).isSuperset(of: operationalContactMutation.preferredScopes.map(\.partyID)) else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        for value in parties {
            try value.validate()
            guard value.workspaceID == workspaceID,
                  value.mutationID == mutationID else {
                throw WorkspaceMutationContractFailureV1.invalidPlan
            }
        }
        for value in roles {
            try value.validate()
            guard value.workspaceID == workspaceID,
                  value.mutationID == mutationID else {
                throw WorkspaceMutationContractFailureV1.invalidPlan
            }
        }

        let expectedByIdentity = try expectedRevisionMap
        let concurrency = try concurrencyIdentities
        let affected = try affectedIdentities
        let images = try mutationPostImages
        guard expectedByIdentity.count == concurrency.count,
              Set(expectedRevision.entityRevisions.map(\.identity)).count == expectedRevision.entityRevisions.count,
              concurrency.allSatisfy { identity in
                  expectedRevision.entityRevisions.first(where: { $0.identity == identity })?.revision
                      == expectedByIdentity[identity]
              },
              affected.count == images.count,
              affected == (try images.map { try $0.identity }),
              images.count <= MutationReceiptV1.maximumPostImageCount,
              Set(affected).count == affected.count,
              Set(concurrency).count == concurrency.count else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
    }

    var affectedIdentities: [WorkspaceEntityIdentityV1] {
        get throws {
            let values = try partyValues.map {
                try WorkspaceEntityIdentityV1(kind: .serviceParty, id: $0.partyID)
            }
                + (try operationalContactMutation.affectedIdentities)
                + (try siteRoleValues.map {
                    try WorkspaceEntityIdentityV1(kind: .sitePartyRoleEvent, id: $0.eventID)
                })
            let ordered = values.sorted { $0.stableKey < $1.stableKey }
            guard Set(ordered).count == ordered.count else {
                throw WorkspaceMutationContractFailureV1.invalidPlan
            }
            return ordered
        }
    }

    var concurrencyIdentities: [WorkspaceEntityIdentityV1] {
        get throws { try expectedRevisionMap.keys.sorted { $0.stableKey < $1.stableKey } }
    }

    func expectedRevision(for identity: WorkspaceEntityIdentityV1) throws -> UInt64 {
        guard let value = try expectedRevisionMap[identity] else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        return value
    }

    var mutationPostImages: [MutationPostImageV1] {
        get throws {
            let values = try partyValues.map {
                MutationPostImageV1.serviceParty(
                    id: $0.partyID,
                    revision: $0.revision,
                    semanticSHA256: $0.receiptSHA256
                )
            }
                + (try operationalContactMutation.mutationPostImages)
                + (try siteRoleValues.map {
                    MutationPostImageV1.sitePartyRoleEvent(
                        id: $0.eventID,
                        revision: $0.revision,
                        semanticSHA256: $0.receiptSHA256
                    )
                })
            let ordered = try values.sorted { try $0.identity.stableKey < $1.identity.stableKey }
            guard Set(try ordered.map { try $0.identity }).count == ordered.count else {
                throw WorkspaceMutationContractFailureV1.invalidPlan
            }
            return ordered
        }
    }

    func canonicalWorkspaceMutationRequest() throws -> WorkspaceMutationRequestV1 {
        try validate()
        return WorkspaceMutationRequestV1(
            mutationID: mutationID,
            expectedRevision: expectedRevision,
            command: .applyPartyContactSiteRoleImport(self)
        )
    }

    private var partyValues: [ServicePartyReferenceV1] {
        get throws {
            try partyMutations.map { mutation in
                guard case let .recordParty(value) = mutation else {
                    throw WorkspaceMutationContractFailureV1.invalidPlan
                }
                return value
            }
        }
    }

    private var siteRoleValues: [SitePartyRoleEventV1] {
        get throws {
            try siteRoleMutations.map { mutation in
                guard case let .appendSiteRole(value) = mutation else {
                    throw WorkspaceMutationContractFailureV1.invalidPlan
                }
                return value
            }
        }
    }

    private var expectedRevisionMap: [WorkspaceEntityIdentityV1: UInt64] {
        get throws {
            guard Set(expectedRevision.entityRevisions.map(\.identity)).count
                    == expectedRevision.entityRevisions.count else {
                throw WorkspaceMutationContractFailureV1.invalidPlan
            }
            let snapshotByIdentity = Dictionary(uniqueKeysWithValues: expectedRevision.entityRevisions.map {
                ($0.identity, $0.revision)
            })
            var result: [WorkspaceEntityIdentityV1: UInt64] = [:]
            func insert(_ identity: WorkspaceEntityIdentityV1, _ revision: UInt64) throws {
                if let existing = result[identity], existing != revision {
                    throw WorkspaceMutationContractFailureV1.invalidPlan
                }
                result[identity] = revision
            }
            for value in try partyValues {
                guard value.revision > 0 else {
                    throw WorkspaceMutationContractFailureV1.invalidPlan
                }
                try insert(
                    WorkspaceEntityIdentityV1(kind: .serviceParty, id: value.partyID),
                    value.revision - 1
                )
            }
            for identity in try operationalContactMutation.concurrencyIdentities {
                try insert(identity, try operationalContactMutation.expectedRevision(for: identity))
            }
            for value in try siteRoleValues {
                // A role reads one existing Site but does not revise it. Keep
                // that read in the aggregate concurrency basis, never in its
                // postimages.
                let siteIdentity = try WorkspaceEntityIdentityV1(kind: .site, id: value.siteID)
                guard let siteRevision = snapshotByIdentity[siteIdentity], siteRevision > 0 else {
                    throw WorkspaceMutationContractFailureV1.invalidPlan
                }
                try insert(siteIdentity, siteRevision)
                try insert(
                    WorkspaceEntityIdentityV1(kind: .sitePartyRoleEvent, id: value.eventID),
                    0
                )
            }
            return result
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case workspaceID
        case mutationID
        case expectedRevision
        case partyMutations
        case operationalContactMutation
        case siteRoleMutations
    }

    init(from decoder: Decoder) throws {
        try PartyContactSiteRoleImportClosedCodingV1.requireExact(decoder, CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
        try self.init(
            workspaceID: container.decode(WorkspaceID.self, forKey: .workspaceID),
            mutationID: container.decode(MutationIDV1.self, forKey: .mutationID),
            expectedRevision: container.decode(WorkspaceExpectedRevisionV1.self, forKey: .expectedRevision),
            partyMutations: container.decode([PartyAccountabilityMutationV1].self, forKey: .partyMutations),
            operationalContactMutation: container.decode(OperationalContactMutationV1.self, forKey: .operationalContactMutation),
            siteRoleMutations: container.decode([PartyAccountabilityMutationV1].self, forKey: .siteRoleMutations)
        )
    }
}

private enum PartyContactSiteRoleImportClosedCodingV1 {
    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
        init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
    }

    static func requireExact<Key: CodingKey & CaseIterable>(
        _ decoder: Decoder,
        _ keys: Key.Type
    ) throws where Key.AllCases: Collection {
        let actual = Set(try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue))
        let expected = Set(Key.allCases.map(\.stringValue))
        guard actual == expected else {
            throw WorkspaceMutationContractFailureV1.invalidPlan
        }
    }
}

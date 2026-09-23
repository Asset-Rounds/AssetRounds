import Foundation

/// Storage identity only. Neither case introduces Finding status or closure truth.
enum FindingOwnerKindV1: String, CaseIterable, Codable, Sendable {
    case finding
    case relationship
}

/// Intrinsic validation is deliberately not receipt authentication, owner-history
/// admission, or proof that the writer queried the complete relationship set.
protocol FindingOwnerSelectionValueV1: Codable {
    func validate() throws
}

struct ActivityFindingSelectionV1: FindingOwnerSelectionValueV1, Equatable, Sendable {
    static let contract = "C47_FINDING_OWNER_SELECTION_V1"
    let contract: String
    let workspaceID: WorkspaceID
    let activityID: UUID
    let frontier: MutationPortableExpectedRevisionV1
    let links: [ActivityFindingOwnerLinkV1]
    let relationshipOwners: [FindingSelectedOwnerReferenceV1]
    let selectionSHA256: String

    /// Callers supply canonical order. No identity is normalized or deduplicated.
    init(workspaceID: WorkspaceID, activityID: UUID,
         frontier: MutationPortableExpectedRevisionV1, links: [ActivityFindingOwnerLinkV1],
         relationshipOwners: [FindingSelectedOwnerReferenceV1], selectionSHA256: String? = nil) throws {
        guard links.count <= FindingContractLimitsV1.maximumRegistryEntries,
              relationshipOwners.count <= FindingContractLimitsV1.maximumRegistryEntries else {
            throw FindingContractFailureV1.limitExceeded
        }
        guard !links.isEmpty || relationshipOwners.isEmpty else {
            throw FindingContractFailureV1.invalidValue
        }
        contract = Self.contract
        self.workspaceID = workspaceID
        self.activityID = activityID
        self.frontier = frontier
        self.links = links
        self.relationshipOwners = relationshipOwners
        let basis = Basis(contract: Self.contract, workspaceID: workspaceID, activityID: activityID,
                          frontier: frontier, links: links, relationshipOwners: relationshipOwners)
        self.selectionSHA256 = try selectionSHA256 ?? WorkspaceMutationCanonicalV1.sha256(basis)
        try validate()
    }

    func validate() throws {
        try FindingSelectionValidationV1.workspace(workspaceID)
        try FindingSelectionValidationV1.id(activityID)
        try FindingSelectionValidationV1.frontier(frontier)
        try FindingSelectionValidationV1.digest(selectionSHA256)
        guard contract == Self.contract, frontier.workspaceID == workspaceID else {
            throw FindingContractFailureV1.invalidValue
        }
        guard links.count <= FindingContractLimitsV1.maximumRegistryEntries,
              relationshipOwners.count <= FindingContractLimitsV1.maximumRegistryEntries else {
            throw FindingContractFailureV1.limitExceeded
        }
        var findingIDs = Set<String>()
        var selectedOwnerIDs = Set<UUID>()
        var originalOwnerIDs = Set<FindingSelectionValidationV1.OriginalOwnerKey>()
        var references: [FindingAcceptedMutationReferenceV1] = []
        var sourceReferences: [FindingSourceContextV1] = []
        var priorFindingID: String?
        for link in links {
            try link.validate()
            guard link.owner.selected.workspaceID == workspaceID else {
                throw FindingContractFailureV1.invalidValue
            }
            guard findingIDs.insert(link.findingID).inserted else {
                throw FindingContractFailureV1.duplicateIdentity
            }
            if let priorFindingID {
                guard priorFindingID.utf8.lexicographicallyPrecedes(link.findingID.utf8) else {
                    throw FindingContractFailureV1.invalidValue
                }
            }
            priorFindingID = link.findingID
            try FindingSelectionValidationV1.insertOwner(link.owner, selected: &selectedOwnerIDs,
                                                        original: &originalOwnerIDs)
            references.append(link.owner.originalAcceptance)
            references.append(link.owner.selectedAcceptance)
            references.append(link.source.originalAcceptance)
            references.append(link.source.selectedAcceptance)
            sourceReferences.append(link.source.original)
            sourceReferences.append(link.source.selected)
            if let corrective = link.correctiveAction {
                references.append(corrective.original.acceptance)
                references.append(corrective.selected.acceptance)
            }
        }
        var priorRelationship: FindingOwnerRevisionReferenceV1?
        for owner in relationshipOwners {
            try owner.validate()
            guard owner.selected.kind == .relationship, owner.selected.workspaceID == workspaceID else {
                throw FindingContractFailureV1.invalidValue
            }
            if let priorRelationship {
                guard FindingSelectionValidationV1.ownerPrecedes(priorRelationship, owner.selected) else {
                    throw FindingContractFailureV1.invalidValue
                }
            }
            priorRelationship = owner.selected
            try FindingSelectionValidationV1.insertOwner(owner, selected: &selectedOwnerIDs,
                                                        original: &originalOwnerIDs)
            references.append(owner.originalAcceptance)
            references.append(owner.selectedAcceptance)
        }
        try FindingSelectionValidationV1.acceptances(references)
        try FindingSelectionValidationV1.sources(sourceReferences)
        guard selectionSHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else {
            throw FindingContractFailureV1.hashMismatch
        }
        // Encode the complete value without recursively invoking validate().
        guard try WorkspaceMutationCanonicalV1.data(Wire(selection: self)).count
                <= FindingContractLimitsV1.maximumCanonicalBytes else {
            throw FindingContractFailureV1.limitExceeded
        }
    }

    private var basis: Basis {
        Basis(contract: contract, workspaceID: workspaceID, activityID: activityID,
              frontier: frontier, links: links, relationshipOwners: relationshipOwners)
    }

    private struct Basis: Encodable {
        let contract: String
        let workspaceID: WorkspaceID
        let activityID: UUID
        let frontier: MutationPortableExpectedRevisionV1
        let links: [ActivityFindingOwnerLinkV1]
        let relationshipOwners: [FindingSelectedOwnerReferenceV1]
    }

    private struct Wire: Encodable {
        let selection: ActivityFindingSelectionV1
        func encode(to encoder: any Encoder) throws { try selection.encodeFields(to: encoder) }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case contract, workspaceID, activityID, frontier, links, relationshipOwners, selectionSHA256
    }

    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(String.self, forKey: .contract) == Self.contract else {
            throw FindingContractFailureV1.incompatibleVersion
        }
        let links = try FindingSelectionClosedV1.array(ActivityFindingOwnerLinkV1.self,
            decoder: c.superDecoder(forKey: .links), maximum: FindingContractLimitsV1.maximumRegistryEntries)
        let relationships = try FindingSelectionClosedV1.array(FindingSelectedOwnerReferenceV1.self,
            decoder: c.superDecoder(forKey: .relationshipOwners), maximum: FindingContractLimitsV1.maximumRegistryEntries)
        try self.init(workspaceID: FindingSelectionClosedV1.workspace(c.superDecoder(forKey: .workspaceID)),
                      activityID: c.decode(UUID.self, forKey: .activityID),
                      frontier: FindingSelectionClosedV1.frontier(c.superDecoder(forKey: .frontier)),
                      links: links, relationshipOwners: relationships,
                      selectionSHA256: c.decode(String.self, forKey: .selectionSHA256))
    }

    func encode(to encoder: any Encoder) throws {
        try validate()
        try encodeFields(to: encoder)
    }

    private func encodeFields(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(contract, forKey: .contract)
        try c.encode(workspaceID, forKey: .workspaceID)
        try c.encode(activityID, forKey: .activityID)
        try c.encode(frontier, forKey: .frontier)
        try c.encode(links, forKey: .links)
        try c.encode(relationshipOwners, forKey: .relationshipOwners)
        try c.encode(selectionSHA256, forKey: .selectionSHA256)
    }
}

enum FindingOwnerSelectionCanonicalCodecV1 {
    static func encode<T: FindingOwnerSelectionValueV1>(_ value: T) throws -> Data {
        try value.validate()
        let data = try WorkspaceMutationCanonicalV1.data(value)
        guard data.count <= FindingContractLimitsV1.maximumCanonicalBytes else {
            throw FindingContractFailureV1.limitExceeded
        }
        return data
    }

    static func decode<T: FindingOwnerSelectionValueV1>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty, data.count <= FindingContractLimitsV1.maximumCanonicalBytes else {
            throw FindingContractFailureV1.limitExceeded
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(type, from: data)
        try value.validate()
        guard try encode(value) == data else { throw FindingContractFailureV1.hashMismatch }
        return value
    }
}

extension FindingCorrectiveEventReferenceV1 {
    /// Value consistency only; the writer must authenticate the selected history
    /// head and its accepted journal post-image independently.
    func validate(event: CorrectiveActionEventV1, finding: FindingV1) throws {
        try validate()
        try event.validate()
        guard let revision = UInt64(exactly: finding.revision),
              event.workspaceID == workspaceID, event.actionID == actionID,
              event.eventID == eventID, event.revision == eventRevision,
              event.eventSHA256 == eventSHA256, event.mutationID == acceptance.mutationID,
              event.source.kind == .finding,
              event.source.itemID.utf8.elementsEqual(finding.findingID.utf8),
              event.source.itemRevision == revision,
              event.source.itemSHA256 == (try WorkspaceMutationCanonicalV1.sha256(finding)) else {
            throw FindingContractFailureV1.invalidValue
        }
    }
}

extension FindingVerifiedRecheckReferenceV1 {
    func validate(recheck: VerifiedRecheckV1) throws {
        try validate()
        // The incumbent constructor adds one. Guard before invoking its decoder;
        // no unchecked Int.max + 1 is reachable through this new binding API.
        guard recheck.expectedRecheckRevision >= 0, recheck.expectedRecheckRevision < Int.max else {
            throw FindingContractFailureV1.invalidValue
        }
        let bytes = try WorkspaceMutationCanonicalV1.data(recheck)
        _ = try JSONDecoder().decode(VerifiedRecheckV1.self, from: bytes)
        guard recheckID.utf8.elementsEqual(recheck.recheckID.utf8),
              resultingRecheckRevision == recheck.resultingRecheckRevision,
              recheckSHA256 == KernelCanonicalHashV1.sha256(bytes) else {
            throw FindingContractFailureV1.hashMismatch
        }
    }
}

extension ActivityFindingOwnerLinkV1 {
    /// Compare supplied typed facts to the immutable references. This does not
    /// prove source receipts, owner membership, C14 head freshness or map validity.
    func validateBindings(finding: FindingV1,
                          originalCorrectiveEvent: CorrectiveActionEventV1? = nil,
                          selectedCorrectiveEvent: CorrectiveActionEventV1? = nil,
                          recheck: VerifiedRecheckV1? = nil) throws {
        try validate()
        let findingBytes = try WorkspaceMutationCanonicalV1.data(finding)
        _ = try JSONDecoder().decode(FindingV1.self, from: findingBytes)
        guard findingID.utf8.elementsEqual(finding.findingID.utf8),
              findingRevision == finding.revision,
              findingSHA256 == KernelCanonicalHashV1.sha256(findingBytes) else {
            throw FindingContractFailureV1.hashMismatch
        }
        if let correctiveAction {
            guard let originalCorrectiveEvent, let selectedCorrectiveEvent else {
                throw FindingContractFailureV1.missingTarget
            }
            try correctiveAction.original.validate(event: originalCorrectiveEvent, finding: finding)
            try correctiveAction.selected.validate(event: selectedCorrectiveEvent, finding: finding)
        } else if originalCorrectiveEvent != nil || selectedCorrectiveEvent != nil {
            throw FindingContractFailureV1.invalidValue
        }
        if let verifiedRecheck {
            guard let recheck, let correctiveAction else { throw FindingContractFailureV1.missingTarget }
            try verifiedRecheck.validate(recheck: recheck)
            guard recheck.findingID.utf8.elementsEqual(findingID.utf8),
                  recheck.findingRevision == findingRevision,
                  recheck.correctiveWorkID.utf8.elementsEqual(correctiveAction.correctiveWorkID.utf8),
                  recheck.correctiveWorkRevision == correctiveAction.correctiveWorkRevision else {
                throw FindingContractFailureV1.invalidValue
            }
        } else if recheck != nil {
            throw FindingContractFailureV1.invalidValue
        }
    }
}

private enum FindingSelectionValidationV1 {
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    static func id(_ value: UUID) throws {
        guard value != zero else { throw FindingContractFailureV1.invalidValue }
    }

    static func workspace(_ value: WorkspaceID) throws { try id(value.rawValue) }

    static func digest(_ value: String) throws {
        guard KernelCanonicalHashV1.validSHA256(value) else { throw FindingContractFailureV1.invalidValue }
    }

    static func kernelID(_ value: String) throws {
        guard FindingContractValidationV1.validID(value) else { throw FindingContractFailureV1.invalidValue }
    }

    static func sameOptionalBytes(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (lhs?, rhs?): return lhs.utf8.elementsEqual(rhs.utf8)
        default: return false
        }
    }

    static func source(_ value: FindingSourceContextV1) throws {
        try workspace(value.workspaceID)
        _ = try FindingSourceContextV1(workspaceID: value.workspaceID, activityID: value.activityID,
            activityKind: value.activityKind, activityRevision: value.activityRevision,
            activitySHA256: value.activitySHA256, taskOrScopeID: value.taskOrScopeID)
    }

    static func frontier(_ value: MutationPortableExpectedRevisionV1) throws {
        try workspace(value.workspaceID)
        try value.validate()
        // The incumbent frontier may describe more rows than the selected C04
        // registry. The complete canonical byte limit bounds it without silently
        // reducing a genuine workspace frontier to selected owners.
        guard value.entityRevisions.count <= FindingContractLimitsV1.maximumCanonicalBytes else {
            throw FindingContractFailureV1.limitExceeded
        }
        for entity in value.entityRevisions { try id(entity.identity.id) }
    }

    struct OriginalOwnerKey: Hashable {
        let workspaceID: WorkspaceID
        let ownerID: UUID
    }

    static func insertOwner(_ reference: FindingSelectedOwnerReferenceV1,
                            selected: inout Set<UUID>, original: inout Set<OriginalOwnerKey>) throws {
        let key = OriginalOwnerKey(workspaceID: reference.original.workspaceID, ownerID: reference.original.ownerID)
        guard selected.insert(reference.selected.ownerID).inserted, original.insert(key).inserted else {
            throw FindingContractFailureV1.duplicateIdentity
        }
    }

    static func ownerPrecedes(_ lhs: FindingOwnerRevisionReferenceV1,
                              _ rhs: FindingOwnerRevisionReferenceV1) -> Bool {
        if lhs.kind.rawValue != rhs.kind.rawValue { return lhs.kind.rawValue < rhs.kind.rawValue }
        let leftID = lhs.ownerID.uuidString.lowercased()
        let rightID = rhs.ownerID.uuidString.lowercased()
        if leftID != rightID { return leftID < rightID }
        return lhs.ownerRevision < rhs.ownerRevision
    }

    private struct AcceptanceKey: Hashable {
        let workspaceID: WorkspaceID
        let mutationID: MutationIDV1
    }

    private struct SourceKey: Hashable {
        let workspaceID: WorkspaceID
        let activityID: UUID
        let activityRevision: UInt64
    }

    static func sources(_ values: [FindingSourceContextV1]) throws {
        // Multiple scope references may legitimately name the same envelope.
        // Compare the envelope identity/kind/hash, not their taskOrScopeID.
        var seen: [SourceKey: FindingSourceContextV1] = [:]
        for value in values {
            let key = SourceKey(workspaceID: value.workspaceID, activityID: value.activityID,
                                activityRevision: value.activityRevision)
            if let prior = seen[key] {
                guard prior.activityKind == value.activityKind, prior.activitySHA256 == value.activitySHA256 else {
                    throw FindingContractFailureV1.historyRewrite
                }
            }
            seen[key] = value
        }
    }

    /// Repeating one accepted original is valid; conflicting hashes under its
    /// exact identity are never merged. This typed index is not another owner.
    static func acceptances(_ values: [FindingAcceptedMutationReferenceV1]) throws {
        var seen: [AcceptanceKey: FindingAcceptedMutationReferenceV1] = [:]
        for value in values {
            try value.validate()
            let key = AcceptanceKey(workspaceID: value.workspaceID, mutationID: value.mutationID)
            if let prior = seen[key], prior != value { throw FindingContractFailureV1.historyRewrite }
            seen[key] = value
        }
    }
}

/// Close reused value shapes at this new boundary without changing their legacy
/// decoders, encoders, canonical bytes or acceptance rules elsewhere.
private enum FindingSelectionClosedV1 {
    private enum Keys: String, CodingKey {
        case rawValue, workspaceID, generationID, workspaceRevision, entityRevisions
        case identity, revision, kind, id
        case activityID, activityKind, activityRevision, activitySHA256, taskOrScopeID
    }

    static func workspace(_ decoder: any Decoder) throws -> WorkspaceID {
        try FindingClosedCodingV1.requireExact(decoder, keys: ["rawValue"])
        let value = try WorkspaceID(from: decoder)
        try FindingSelectionValidationV1.workspace(value)
        return value
    }

    static func source(_ decoder: any Decoder) throws -> FindingSourceContextV1 {
        try FindingClosedCodingV1.requireClosed(decoder,
            allowed: ["workspaceID", "activityID", "activityKind", "activityRevision", "activitySHA256", "taskOrScopeID"],
            required: ["workspaceID", "activityID", "activityKind", "activityRevision", "activitySHA256"])
        let c = try decoder.container(keyedBy: Keys.self)
        _ = try workspace(c.superDecoder(forKey: .workspaceID))
        if c.contains(.taskOrScopeID), try c.decodeNil(forKey: .taskOrScopeID) {
            throw FindingContractFailureV1.invalidValue
        }
        let value = try FindingSourceContextV1(from: decoder)
        try FindingSelectionValidationV1.source(value)
        return value
    }

    static func frontier(_ decoder: any Decoder) throws -> MutationPortableExpectedRevisionV1 {
        try FindingClosedCodingV1.requireExact(decoder,
            keys: ["workspaceID", "generationID", "workspaceRevision", "entityRevisions"])
        let c = try decoder.container(keyedBy: Keys.self)
        _ = try workspace(c.superDecoder(forKey: .workspaceID))
        var entries = try c.nestedUnkeyedContainer(forKey: .entityRevisions)
        var count = 0
        while !entries.isAtEnd {
            guard count < FindingContractLimitsV1.maximumCanonicalBytes else {
                throw FindingContractFailureV1.limitExceeded
            }
            let entryDecoder = try entries.superDecoder()
            try FindingClosedCodingV1.requireExact(entryDecoder, keys: ["identity", "revision"])
            let entry = try entryDecoder.container(keyedBy: Keys.self)
            let identityDecoder = try entry.superDecoder(forKey: .identity)
            try FindingClosedCodingV1.requireExact(identityDecoder, keys: ["kind", "id"])
            count += 1
        }
        let value = try MutationPortableExpectedRevisionV1(from: decoder)
        try FindingSelectionValidationV1.frontier(value)
        return value
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
}


struct FindingOwnerRevisionReferenceV1: FindingOwnerSelectionValueV1, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let kind: FindingOwnerKindV1
    let ownerID: UUID
    let ownerRevision: UInt64
    let recordSHA256: String

    init(
        workspaceID: WorkspaceID,
        kind: FindingOwnerKindV1,
        ownerID: UUID,
        ownerRevision: UInt64,
        recordSHA256: String
    ) throws {
        self.workspaceID = workspaceID
        self.kind = kind
        self.ownerID = ownerID
        self.ownerRevision = ownerRevision
        self.recordSHA256 = recordSHA256
        try validate()
    }

    func validate() throws {
        try FindingSelectionValidationV1.workspace(workspaceID)
        try FindingSelectionValidationV1.id(ownerID)
        try FindingSelectionValidationV1.digest(recordSHA256)
        guard ownerRevision > 0 else { throw FindingContractFailureV1.invalidValue }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case workspaceID, kind, ownerID, ownerRevision, recordSHA256
    }

    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            workspaceID: FindingSelectionClosedV1.workspace(c.superDecoder(forKey: .workspaceID)),
            kind: c.decode(FindingOwnerKindV1.self, forKey: .kind),
            ownerID: c.decode(UUID.self, forKey: .ownerID),
            ownerRevision: c.decode(UInt64.self, forKey: .ownerRevision),
            recordSHA256: c.decode(String.self, forKey: .recordSHA256)
        )
    }

    func encode(to encoder: any Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(workspaceID, forKey: .workspaceID)
        try c.encode(kind, forKey: .kind)
        try c.encode(ownerID, forKey: .ownerID)
        try c.encode(ownerRevision, forKey: .ownerRevision)
        try c.encode(recordSHA256, forKey: .recordSHA256)
    }
}

struct FindingAcceptedMutationReferenceV1: FindingOwnerSelectionValueV1, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let generationID: UUID
    let mutationID: MutationIDV1
    let envelopeSHA256: String
    let receiptSHA256: String

    init(
        workspaceID: WorkspaceID,
        generationID: UUID,
        mutationID: MutationIDV1,
        envelopeSHA256: String,
        receiptSHA256: String
    ) throws {
        self.workspaceID = workspaceID
        self.generationID = generationID
        self.mutationID = mutationID
        self.envelopeSHA256 = envelopeSHA256
        self.receiptSHA256 = receiptSHA256
        try validate()
    }

    func validate() throws {
        try FindingSelectionValidationV1.workspace(workspaceID)
        try FindingSelectionValidationV1.id(generationID)
        try FindingSelectionValidationV1.id(mutationID.rawValue)
        try FindingSelectionValidationV1.digest(envelopeSHA256)
        try FindingSelectionValidationV1.digest(receiptSHA256)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case workspaceID, generationID, mutationID, envelopeSHA256, receiptSHA256
    }

    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            workspaceID: FindingSelectionClosedV1.workspace(c.superDecoder(forKey: .workspaceID)),
            generationID: c.decode(UUID.self, forKey: .generationID),
            mutationID: c.decode(MutationIDV1.self, forKey: .mutationID),
            envelopeSHA256: c.decode(String.self, forKey: .envelopeSHA256),
            receiptSHA256: c.decode(String.self, forKey: .receiptSHA256)
        )
    }

    func encode(to encoder: any Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(workspaceID, forKey: .workspaceID)
        try c.encode(generationID, forKey: .generationID)
        try c.encode(mutationID, forKey: .mutationID)
        try c.encode(envelopeSHA256, forKey: .envelopeSHA256)
        try c.encode(receiptSHA256, forKey: .receiptSHA256)
    }
}

struct FindingSelectedOwnerReferenceV1: FindingOwnerSelectionValueV1, Equatable, Sendable {
    let original: FindingOwnerRevisionReferenceV1
    let selected: FindingOwnerRevisionReferenceV1
    let originalAcceptance: FindingAcceptedMutationReferenceV1
    let selectedAcceptance: FindingAcceptedMutationReferenceV1

    init(
        original: FindingOwnerRevisionReferenceV1,
        selected: FindingOwnerRevisionReferenceV1,
        originalAcceptance: FindingAcceptedMutationReferenceV1,
        selectedAcceptance: FindingAcceptedMutationReferenceV1
    ) throws {
        self.original = original
        self.selected = selected
        self.originalAcceptance = originalAcceptance
        self.selectedAcceptance = selectedAcceptance
        try validate()
    }

    func validate() throws {
        try original.validate()
        try selected.validate()
        try originalAcceptance.validate()
        try selectedAcceptance.validate()
        guard original.kind == selected.kind, original.ownerRevision == selected.ownerRevision,
              original.workspaceID == originalAcceptance.workspaceID,
              selected.workspaceID == selectedAcceptance.workspaceID else {
            throw FindingContractFailureV1.invalidValue
        }
        if original.workspaceID == selected.workspaceID {
            guard original == selected else {
                throw FindingContractFailureV1.historyRewrite
            }
        }
        try FindingSelectionValidationV1.acceptances([originalAcceptance, selectedAcceptance])
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case original, selected, originalAcceptance, selectedAcceptance
    }

    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            original: c.decode(FindingOwnerRevisionReferenceV1.self, forKey: .original),
            selected: c.decode(FindingOwnerRevisionReferenceV1.self, forKey: .selected),
            originalAcceptance: c.decode(FindingAcceptedMutationReferenceV1.self, forKey: .originalAcceptance),
            selectedAcceptance: c.decode(FindingAcceptedMutationReferenceV1.self, forKey: .selectedAcceptance)
        )
    }

    func encode(to encoder: any Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(original, forKey: .original)
        try c.encode(selected, forKey: .selected)
        try c.encode(originalAcceptance, forKey: .originalAcceptance)
        try c.encode(selectedAcceptance, forKey: .selectedAcceptance)
    }
}

struct FindingActivitySourceReferenceV1: FindingOwnerSelectionValueV1, Equatable, Sendable {
    let original: FindingSourceContextV1
    let selected: FindingSourceContextV1
    let originalAcceptance: FindingAcceptedMutationReferenceV1
    let selectedAcceptance: FindingAcceptedMutationReferenceV1

    init(
        original: FindingSourceContextV1,
        selected: FindingSourceContextV1,
        originalAcceptance: FindingAcceptedMutationReferenceV1,
        selectedAcceptance: FindingAcceptedMutationReferenceV1
    ) throws {
        self.original = original
        self.selected = selected
        self.originalAcceptance = originalAcceptance
        self.selectedAcceptance = selectedAcceptance
        try validate()
    }

    func validate() throws {
        try FindingSelectionValidationV1.source(original)
        try FindingSelectionValidationV1.source(selected)
        try originalAcceptance.validate()
        try selectedAcceptance.validate()
        guard original.workspaceID == originalAcceptance.workspaceID,
              selected.workspaceID == selectedAcceptance.workspaceID,
              original.activityKind == selected.activityKind,
              original.activityRevision == selected.activityRevision,
              FindingSelectionValidationV1.sameOptionalBytes(original.taskOrScopeID, selected.taskOrScopeID) else {
            throw FindingContractFailureV1.invalidValue
        }
        if original.workspaceID == selected.workspaceID {
            guard original == selected else {
                throw FindingContractFailureV1.historyRewrite
            }
        }
        try FindingSelectionValidationV1.acceptances([originalAcceptance, selectedAcceptance])
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case original, selected, originalAcceptance, selectedAcceptance
    }

    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            original: FindingSelectionClosedV1.source(c.superDecoder(forKey: .original)),
            selected: FindingSelectionClosedV1.source(c.superDecoder(forKey: .selected)),
            originalAcceptance: c.decode(FindingAcceptedMutationReferenceV1.self, forKey: .originalAcceptance),
            selectedAcceptance: c.decode(FindingAcceptedMutationReferenceV1.self, forKey: .selectedAcceptance)
        )
    }

    func encode(to encoder: any Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(original, forKey: .original)
        try c.encode(selected, forKey: .selected)
        try c.encode(originalAcceptance, forKey: .originalAcceptance)
        try c.encode(selectedAcceptance, forKey: .selectedAcceptance)
    }
}

struct FindingCorrectiveEventReferenceV1: FindingOwnerSelectionValueV1, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let actionID: UUID
    let eventID: UUID
    let eventRevision: UInt64
    let eventSHA256: String
    let acceptance: FindingAcceptedMutationReferenceV1

    init(
        workspaceID: WorkspaceID,
        actionID: UUID,
        eventID: UUID,
        eventRevision: UInt64,
        eventSHA256: String,
        acceptance: FindingAcceptedMutationReferenceV1
    ) throws {
        self.workspaceID = workspaceID
        self.actionID = actionID
        self.eventID = eventID
        self.eventRevision = eventRevision
        self.eventSHA256 = eventSHA256
        self.acceptance = acceptance
        try validate()
    }

    func validate() throws {
        try FindingSelectionValidationV1.workspace(workspaceID)
        try FindingSelectionValidationV1.id(actionID)
        try FindingSelectionValidationV1.id(eventID)
        try FindingSelectionValidationV1.digest(eventSHA256)
        try acceptance.validate()
        guard eventRevision > 0, acceptance.workspaceID == workspaceID else {
            throw FindingContractFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case workspaceID, actionID, eventID, eventRevision, eventSHA256, acceptance
    }

    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            workspaceID: FindingSelectionClosedV1.workspace(c.superDecoder(forKey: .workspaceID)),
            actionID: c.decode(UUID.self, forKey: .actionID),
            eventID: c.decode(UUID.self, forKey: .eventID),
            eventRevision: c.decode(UInt64.self, forKey: .eventRevision),
            eventSHA256: c.decode(String.self, forKey: .eventSHA256),
            acceptance: c.decode(FindingAcceptedMutationReferenceV1.self, forKey: .acceptance)
        )
    }

    func encode(to encoder: any Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(workspaceID, forKey: .workspaceID)
        try c.encode(actionID, forKey: .actionID)
        try c.encode(eventID, forKey: .eventID)
        try c.encode(eventRevision, forKey: .eventRevision)
        try c.encode(eventSHA256, forKey: .eventSHA256)
        try c.encode(acceptance, forKey: .acceptance)
    }
}

struct FindingC14SupportReferenceV1: FindingOwnerSelectionValueV1, Equatable, Sendable {
    let correctiveWorkID: String
    let correctiveWorkRevision: Int
    let original: FindingCorrectiveEventReferenceV1
    let selected: FindingCorrectiveEventReferenceV1

    init(
        correctiveWorkID: String,
        correctiveWorkRevision: Int,
        original: FindingCorrectiveEventReferenceV1,
        selected: FindingCorrectiveEventReferenceV1
    ) throws {
        self.correctiveWorkID = correctiveWorkID
        self.correctiveWorkRevision = correctiveWorkRevision
        self.original = original
        self.selected = selected
        try validate()
    }

    func validate() throws {
        try FindingSelectionValidationV1.kernelID(correctiveWorkID)
        try original.validate()
        try selected.validate()
        guard correctiveWorkRevision >= 0, original.eventRevision == selected.eventRevision else {
            throw FindingContractFailureV1.invalidValue
        }
        if original.workspaceID == selected.workspaceID {
            guard original.actionID == selected.actionID, original.eventID == selected.eventID,
                  original.eventSHA256 == selected.eventSHA256 else {
                throw FindingContractFailureV1.historyRewrite
            }
        }
        try FindingSelectionValidationV1.acceptances([original.acceptance, selected.acceptance])
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case correctiveWorkID, correctiveWorkRevision, original, selected
    }

    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            correctiveWorkID: c.decode(String.self, forKey: .correctiveWorkID),
            correctiveWorkRevision: c.decode(Int.self, forKey: .correctiveWorkRevision),
            original: c.decode(FindingCorrectiveEventReferenceV1.self, forKey: .original),
            selected: c.decode(FindingCorrectiveEventReferenceV1.self, forKey: .selected)
        )
    }

    func encode(to encoder: any Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(correctiveWorkID, forKey: .correctiveWorkID)
        try c.encode(correctiveWorkRevision, forKey: .correctiveWorkRevision)
        try c.encode(original, forKey: .original)
        try c.encode(selected, forKey: .selected)
    }
}

struct FindingVerifiedRecheckReferenceV1: FindingOwnerSelectionValueV1, Equatable, Sendable {
    let owner: FindingOwnerRevisionReferenceV1
    let recheckID: String
    let resultingRecheckRevision: Int
    let recheckSHA256: String

    init(
        owner: FindingOwnerRevisionReferenceV1,
        recheckID: String,
        resultingRecheckRevision: Int,
        recheckSHA256: String
    ) throws {
        self.owner = owner
        self.recheckID = recheckID
        self.resultingRecheckRevision = resultingRecheckRevision
        self.recheckSHA256 = recheckSHA256
        try validate()
    }

    func validate() throws {
        try owner.validate()
        try FindingSelectionValidationV1.kernelID(recheckID)
        try FindingSelectionValidationV1.digest(recheckSHA256)
        guard owner.kind == .finding, resultingRecheckRevision > 0 else {
            throw FindingContractFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case owner, recheckID, resultingRecheckRevision, recheckSHA256
    }

    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireExact(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            owner: c.decode(FindingOwnerRevisionReferenceV1.self, forKey: .owner),
            recheckID: c.decode(String.self, forKey: .recheckID),
            resultingRecheckRevision: c.decode(Int.self, forKey: .resultingRecheckRevision),
            recheckSHA256: c.decode(String.self, forKey: .recheckSHA256)
        )
    }

    func encode(to encoder: any Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(owner, forKey: .owner)
        try c.encode(recheckID, forKey: .recheckID)
        try c.encode(resultingRecheckRevision, forKey: .resultingRecheckRevision)
        try c.encode(recheckSHA256, forKey: .recheckSHA256)
    }
}

struct ActivityFindingOwnerLinkV1: FindingOwnerSelectionValueV1, Equatable, Sendable {
    let findingID: String
    let findingRevision: Int
    let findingSHA256: String
    let owner: FindingSelectedOwnerReferenceV1
    let source: FindingActivitySourceReferenceV1
    let correctiveAction: FindingC14SupportReferenceV1?
    let verifiedRecheck: FindingVerifiedRecheckReferenceV1?

    init(
        findingID: String,
        findingRevision: Int,
        findingSHA256: String,
        owner: FindingSelectedOwnerReferenceV1,
        source: FindingActivitySourceReferenceV1,
        correctiveAction: FindingC14SupportReferenceV1? = nil,
        verifiedRecheck: FindingVerifiedRecheckReferenceV1? = nil
    ) throws {
        self.findingID = findingID
        self.findingRevision = findingRevision
        self.findingSHA256 = findingSHA256
        self.owner = owner
        self.source = source
        self.correctiveAction = correctiveAction
        self.verifiedRecheck = verifiedRecheck
        try validate()
    }

    func validate() throws {
        try FindingSelectionValidationV1.kernelID(findingID)
        try FindingSelectionValidationV1.digest(findingSHA256)
        try owner.validate()
        try source.validate()
        try correctiveAction?.validate()
        try verifiedRecheck?.validate()
        guard findingRevision >= 0, owner.selected.kind == .finding,
              owner.original.workspaceID == source.original.workspaceID,
              owner.selected.workspaceID == source.selected.workspaceID else {
            throw FindingContractFailureV1.invalidValue
        }
        if let correctiveAction {
            guard correctiveAction.original.workspaceID == owner.original.workspaceID,
                  correctiveAction.selected.workspaceID == owner.selected.workspaceID else {
                throw FindingContractFailureV1.invalidValue
            }
        }
        if let verifiedRecheck {
            guard correctiveAction != nil, verifiedRecheck.owner == owner.selected else {
                throw FindingContractFailureV1.invalidValue
            }
        }
        var references = [owner.originalAcceptance, owner.selectedAcceptance,
                          source.originalAcceptance, source.selectedAcceptance]
        if let correctiveAction {
            references.append(correctiveAction.original.acceptance)
            references.append(correctiveAction.selected.acceptance)
        }
        try FindingSelectionValidationV1.acceptances(references)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case findingID, findingRevision, findingSHA256, owner, source, correctiveAction, verifiedRecheck
    }

    init(from decoder: any Decoder) throws {
        try FindingClosedCodingV1.requireClosed(
            decoder, allowed: CodingKeys.allCases.map(\.rawValue),
            required: ["findingID", "findingRevision", "findingSHA256", "owner", "source"]
        )
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.correctiveAction), try c.decodeNil(forKey: .correctiveAction) {
            throw FindingContractFailureV1.invalidValue
        }
        if c.contains(.verifiedRecheck), try c.decodeNil(forKey: .verifiedRecheck) {
            throw FindingContractFailureV1.invalidValue
        }
        try self.init(
            findingID: c.decode(String.self, forKey: .findingID),
            findingRevision: c.decode(Int.self, forKey: .findingRevision),
            findingSHA256: c.decode(String.self, forKey: .findingSHA256),
            owner: c.decode(FindingSelectedOwnerReferenceV1.self, forKey: .owner),
            source: c.decode(FindingActivitySourceReferenceV1.self, forKey: .source),
            correctiveAction: c.decodeIfPresent(FindingC14SupportReferenceV1.self, forKey: .correctiveAction),
            verifiedRecheck: c.decodeIfPresent(FindingVerifiedRecheckReferenceV1.self, forKey: .verifiedRecheck)
        )
    }

    func encode(to encoder: any Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(findingID, forKey: .findingID)
        try c.encode(findingRevision, forKey: .findingRevision)
        try c.encode(findingSHA256, forKey: .findingSHA256)
        try c.encode(owner, forKey: .owner)
        try c.encode(source, forKey: .source)
        try c.encodeIfPresent(correctiveAction, forKey: .correctiveAction)
        try c.encodeIfPresent(verifiedRecheck, forKey: .verifiedRecheck)
    }
}

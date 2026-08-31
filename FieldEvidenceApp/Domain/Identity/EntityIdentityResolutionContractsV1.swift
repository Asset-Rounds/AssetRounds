import Foundation

enum EntityIdentityResolutionFailureV1: Error, Equatable, Sendable {
    case invalidValue, incompatibleVersion, corruptDigest, duplicateIdentity, wrongWorkspace
    case staleRevision, ambiguousCandidate, incompleteInventory, aliasCycle, identityReuse
    case automaticMutationForbidden, invalidSuccessor, arithmeticOverflow, receiptMismatch
}

enum EntityIdentityResolutionLimitsV1 {
    static let maximumCandidates = 128
    static let maximumInventoryItemsPerFamily = 2_048
    static let maximumQueryResults = 256
    static let maximumTokenBytes = 256
}

enum EntityIdentityResolutionLifecycleV1 {
    static let canonicalWriter = "WorkspaceWriterV1"
    static let writersPerWorkspaceGeneration = 1
    static let createsSecondStore = false
    static let plansAndPreviewsArePersistent = false
    static let automaticMutation = false
    static let workRelationshipsAreEvidenceOnly = true
}

private enum EntityIdentityResolutionValidationV1 {
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    static func id(_ value: UUID) throws { guard value != zero else { throw EntityIdentityResolutionFailureV1.invalidValue } }
    static func revision(_ value: UInt64) throws { guard value > 0 else { throw EntityIdentityResolutionFailureV1.staleRevision } }
    static func digest(_ value: String) throws {
        guard value == value.lowercased(), KernelCanonicalHashV1.validSHA256(value) else { throw EntityIdentityResolutionFailureV1.corruptDigest }
    }
    static func token(_ value: String) throws {
        guard !value.isEmpty, value.utf8.count <= EntityIdentityResolutionLimitsV1.maximumTokenBytes,
              value.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "-_.:".unicodeScalars.contains($0)) })
        else { throw EntityIdentityResolutionFailureV1.invalidValue }
    }
    static func instant(_ value: Date) throws { guard value.timeIntervalSinceReferenceDate.isFinite else { throw EntityIdentityResolutionFailureV1.invalidValue } }
    static func hash<T: Encodable>(_ value: T) throws -> String { try WorkspaceMutationCanonicalV1.sha256(value) }
}

enum EntityIdentityResolutionActionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case createNew = "CREATE_NEW"
    case linkAlias = "LINK_ALIAS"
    case consolidate = "CONSOLIDATE"
    case reject = "REJECT"
    case reviewRequired = "REVIEW_REQUIRED"
}

enum EntityIdentityResolutionReasonV1: String, CaseIterable, Codable, Hashable, Sendable {
    case exactExternalIdentifier = "EXACT_EXTERNAL_IDENTIFIER"
    case verifiedSerialOrTag = "VERIFIED_SERIAL_OR_TAG"
    case verifiedPriorAlias = "VERIFIED_PRIOR_ALIAS"
    case conflictingIdentifiers = "CONFLICTING_IDENTIFIERS"
    case ambiguousCandidates = "AMBIGUOUS_CANDIDATES"
    case insufficientEvidence = "INSUFFICIENT_EVIDENCE"
    case explicitOperatorDecision = "EXPLICIT_OPERATOR_DECISION"
    case policyRequiresReview = "POLICY_REQUIRES_REVIEW"
}

struct EntityIdentitySnapshotV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let identity: WorkspaceEntityIdentityV1
    let revision: UInt64
    let entitySHA256: String
    init(workspaceID: WorkspaceID, identity: WorkspaceEntityIdentityV1, revision: UInt64, entitySHA256: String) throws {
        self.workspaceID = workspaceID; self.identity = identity; self.revision = revision; self.entitySHA256 = entitySHA256; try validate()
    }
    func validate() throws { try EntityIdentityResolutionValidationV1.revision(revision); try EntityIdentityResolutionValidationV1.digest(entitySHA256) }
    var stableKey: String { "\(workspaceID.rawValue.uuidString.lowercased())|\(identity.stableKey)|\(revision)" }
}

struct EntityIdentityImportArtifactV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID; let sourceBatchID: UUID; let artifactID: UUID
    let artifactRevision: UInt64; let artifactSHA256: String
    init(workspaceID: WorkspaceID, sourceBatchID: UUID, artifactID: UUID, artifactRevision: UInt64, artifactSHA256: String) throws {
        self.workspaceID = workspaceID; self.sourceBatchID = sourceBatchID; self.artifactID = artifactID
        self.artifactRevision = artifactRevision; self.artifactSHA256 = artifactSHA256; try validate()
    }
    func validate() throws {
        try EntityIdentityResolutionValidationV1.id(sourceBatchID); try EntityIdentityResolutionValidationV1.id(artifactID)
        try EntityIdentityResolutionValidationV1.revision(artifactRevision); try EntityIdentityResolutionValidationV1.digest(artifactSHA256)
    }
}

struct EntityIdentityResolutionCandidateV1: Codable, Equatable, Hashable, Sendable {
    let snapshot: EntityIdentitySnapshotV1
    let reasons: [EntityIdentityResolutionReasonV1]
    init(snapshot: EntityIdentitySnapshotV1, reasons: [EntityIdentityResolutionReasonV1]) throws {
        self.snapshot = snapshot; self.reasons = reasons; try validate()
    }
    func validate() throws {
        try snapshot.validate(); guard !reasons.isEmpty, reasons == reasons.sorted(by: { $0.rawValue < $1.rawValue }), Set(reasons).count == reasons.count
        else { throw EntityIdentityResolutionFailureV1.duplicateIdentity }
    }
}

protocol EntityIdentityResolutionCanonicalInventoryProvidingV1 {
    func resolveEntityIdentity(_ identity: WorkspaceEntityIdentityV1, workspaceID: WorkspaceID, revision: UInt64) throws -> EntityIdentitySnapshotV1
    func aliasPath(from alias: WorkspaceEntityIdentityV1, workspaceID: WorkspaceID) throws -> [WorkspaceEntityIdentityV1]
    func canonicalConsolidationAtoms(source: EntityIdentitySnapshotV1, survivor: EntityIdentitySnapshotV1, family: EntityConsolidationInventoryFamilyV1) throws -> [EntityConsolidationInventoryAtomV1]
}

protocol EntityIdentityCanonicalResolvingV1: EntityIdentityResolutionCanonicalInventoryProvidingV1 {}

extension EntityIdentityCanonicalResolvingV1 {
    func canonicalConsolidationInventory(source: EntityIdentitySnapshotV1, survivor: EntityIdentitySnapshotV1) throws -> EntityConsolidationInventoryV1 {
        try EntityConsolidationInventoryBuilderV1.inventory(
            workspaceID: source.workspaceID,
            source: source,
            survivor: survivor,
            atomsByFamily: Dictionary(uniqueKeysWithValues: try EntityConsolidationInventoryFamilyV1.allCases.map { family in
                (family, try canonicalConsolidationAtoms(source: source, survivor: survivor, family: family))
            })
        )
    }
}

extension EntityIdentitySnapshotV1 {
    func validateResolved(by resolver: any EntityIdentityCanonicalResolvingV1) throws {
        try validate(); guard try resolver.resolveEntityIdentity(identity, workspaceID: workspaceID, revision: revision) == self
        else { throw EntityIdentityResolutionFailureV1.staleRevision }
    }
}

struct EntityIdentityResolutionPlanV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let planID: UUID; let workspaceID: WorkspaceID
    let source: EntityIdentityImportArtifactV1; let expectedWorkspaceRevision: UInt64
    let policyVersion: UInt64; let policySHA256: String; let candidates: [EntityIdentityResolutionCandidateV1]
    let action: EntityIdentityResolutionActionV1; let selectedCandidate: EntityIdentitySnapshotV1?
    let reasons: [EntityIdentityResolutionReasonV1]; let createdBy: ActorSnapshotV1
    let createdAt: Date; let expiresAt: Date; let automaticMutation: Bool; let planSHA256: String
    init(planID: UUID, workspaceID: WorkspaceID, source: EntityIdentityImportArtifactV1,
         expectedWorkspaceRevision: UInt64, policyVersion: UInt64, policySHA256: String,
         candidates: [EntityIdentityResolutionCandidateV1], action: EntityIdentityResolutionActionV1,
         selectedCandidate: EntityIdentitySnapshotV1?, reasons: [EntityIdentityResolutionReasonV1],
         createdBy: ActorSnapshotV1, createdAt: Date, expiresAt: Date) throws {
        schemaVersion = Self.schemaVersion; self.planID = planID; self.workspaceID = workspaceID; self.source = source
        self.expectedWorkspaceRevision = expectedWorkspaceRevision; self.policyVersion = policyVersion; self.policySHA256 = policySHA256
        self.candidates = candidates; self.action = action; self.selectedCandidate = selectedCandidate; self.reasons = reasons
        self.createdBy = createdBy; self.createdAt = createdAt; self.expiresAt = expiresAt; automaticMutation = false
        planSHA256 = try EntityIdentityResolutionValidationV1.hash(Basis(schemaVersion: Self.schemaVersion, planID: planID,
            workspaceID: workspaceID, source: source, expectedWorkspaceRevision: expectedWorkspaceRevision, policyVersion: policyVersion,
            policySHA256: policySHA256, candidates: candidates, action: action, selectedCandidate: selectedCandidate,
            reasons: reasons, createdBy: createdBy, createdAt: createdAt, expiresAt: expiresAt, automaticMutation: false)); try validate()
    }
    func validate() throws {
        try EntityIdentityResolutionValidationV1.id(planID); try source.validate(); try EntityIdentityResolutionValidationV1.revision(policyVersion)
        try EntityIdentityResolutionValidationV1.digest(policySHA256); try createdBy.validate()
        try EntityIdentityResolutionValidationV1.instant(createdAt); try EntityIdentityResolutionValidationV1.instant(expiresAt)
        try candidates.forEach { try $0.validate() }; try selectedCandidate?.validate()
        guard schemaVersion == Self.schemaVersion, source.workspaceID == workspaceID, createdBy.workspaceID == workspaceID,
              expiresAt > createdAt, !automaticMutation, candidates.count <= EntityIdentityResolutionLimitsV1.maximumCandidates,
              candidates == candidates.sorted(by: { $0.snapshot.stableKey < $1.snapshot.stableKey }),
              Set(candidates.map(\.snapshot.identity)).count == candidates.count,
              candidates.allSatisfy({ $0.snapshot.workspaceID == workspaceID }),
              !reasons.isEmpty, reasons == reasons.sorted(by: { $0.rawValue < $1.rawValue }), Set(reasons).count == reasons.count,
              planSHA256 == (try EntityIdentityResolutionValidationV1.hash(basis)) else { throw EntityIdentityResolutionFailureV1.invalidValue }
        switch action {
        case .linkAlias, .consolidate:
            guard let selectedCandidate, candidates.contains(where: { $0.snapshot == selectedCandidate }) else { throw EntityIdentityResolutionFailureV1.ambiguousCandidate }
        case .createNew, .reject, .reviewRequired:
            guard selectedCandidate == nil else { throw EntityIdentityResolutionFailureV1.ambiguousCandidate }
        }
    }
    func validate(currentRevision: WorkspaceRevisionV1, resolver: any EntityIdentityCanonicalResolvingV1, now: Date) throws {
        try validate(); guard currentRevision.workspaceID == workspaceID, currentRevision.revision == expectedWorkspaceRevision, now <= expiresAt else { throw EntityIdentityResolutionFailureV1.staleRevision }
        for candidate in candidates { try candidate.snapshot.validateResolved(by: resolver) }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, planID: planID, workspaceID: workspaceID, source: source,
        expectedWorkspaceRevision: expectedWorkspaceRevision, policyVersion: policyVersion, policySHA256: policySHA256,
        candidates: candidates, action: action, selectedCandidate: selectedCandidate, reasons: reasons, createdBy: createdBy,
        createdAt: createdAt, expiresAt: expiresAt, automaticMutation: automaticMutation) }
    private struct Basis: Codable { let schemaVersion: Int; let planID: UUID; let workspaceID: WorkspaceID; let source: EntityIdentityImportArtifactV1; let expectedWorkspaceRevision: UInt64; let policyVersion: UInt64; let policySHA256: String; let candidates: [EntityIdentityResolutionCandidateV1]; let action: EntityIdentityResolutionActionV1; let selectedCandidate: EntityIdentitySnapshotV1?; let reasons: [EntityIdentityResolutionReasonV1]; let createdBy: ActorSnapshotV1; let createdAt: Date; let expiresAt: Date; let automaticMutation: Bool }
}

struct EntityAliasLinkV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let linkEventID: UUID; let workspaceID: WorkspaceID; let alias: EntityIdentitySnapshotV1
    let canonicalEntity: EntityIdentitySnapshotV1; let revision: UInt64; let supersedesLinkEventID: UUID?; let predecessorSHA256: String?
    let reason: EntityIdentityResolutionReasonV1; let policyVersion: UInt64; let policySHA256: String
    let recordedBy: ActorSnapshotV1; let recordedAt: Date; let mutationID: MutationIDV1; let linkSHA256: String
    var aliasID: UUID { alias.identity.id }
    var survivorID: UUID { canonicalEntity.identity.id }
    var aliasSHA256: String { linkSHA256 }
    init(linkEventID: UUID, workspaceID: WorkspaceID, alias: EntityIdentitySnapshotV1, canonicalEntity: EntityIdentitySnapshotV1,
         revision: UInt64, predecessor: EntityAliasLinkV1? = nil, reason: EntityIdentityResolutionReasonV1,
         policyVersion: UInt64, policySHA256: String, recordedBy: ActorSnapshotV1, recordedAt: Date, mutationID: MutationIDV1) throws {
        schemaVersion = Self.schemaVersion; self.linkEventID = linkEventID; self.workspaceID = workspaceID; self.alias = alias
        self.canonicalEntity = canonicalEntity; self.revision = revision; supersedesLinkEventID = predecessor?.linkEventID
        predecessorSHA256 = predecessor?.linkSHA256; self.reason = reason; self.policyVersion = policyVersion; self.policySHA256 = policySHA256
        self.recordedBy = recordedBy; self.recordedAt = recordedAt; self.mutationID = mutationID
        linkSHA256 = try EntityIdentityResolutionValidationV1.hash(Basis(schemaVersion: Self.schemaVersion, linkEventID: linkEventID,
            workspaceID: workspaceID, alias: alias, canonicalEntity: canonicalEntity, revision: revision,
            supersedesLinkEventID: predecessor?.linkEventID, predecessorSHA256: predecessor?.linkSHA256, reason: reason,
            policyVersion: policyVersion, policySHA256: policySHA256, recordedBy: recordedBy, recordedAt: recordedAt, mutationID: mutationID)); try validate(predecessor: predecessor)
    }
    func validate() throws { try validate(predecessor: nil, requirePredecessor: false) }
    func validate(predecessor: EntityAliasLinkV1?) throws { try validate(predecessor: predecessor, requirePredecessor: true) }
    private func validate(predecessor: EntityAliasLinkV1?, requirePredecessor: Bool) throws {
        try EntityIdentityResolutionValidationV1.id(linkEventID); try alias.validate(); try canonicalEntity.validate()
        try EntityIdentityResolutionValidationV1.revision(revision); try EntityIdentityResolutionValidationV1.revision(policyVersion)
        try EntityIdentityResolutionValidationV1.digest(policySHA256); try recordedBy.validate(); try EntityIdentityResolutionValidationV1.instant(recordedAt)
        guard schemaVersion == Self.schemaVersion, alias.workspaceID == workspaceID, canonicalEntity.workspaceID == workspaceID,
              alias.identity != canonicalEntity.identity, alias.identity.kind == canonicalEntity.identity.kind,
              recordedBy.workspaceID == workspaceID, linkSHA256 == (try EntityIdentityResolutionValidationV1.hash(basis))
        else { throw EntityIdentityResolutionFailureV1.wrongWorkspace }
        if revision == 1 { guard predecessor == nil, supersedesLinkEventID == nil, predecessorSHA256 == nil else { throw EntityIdentityResolutionFailureV1.staleRevision } }
        else if requirePredecessor {
            guard let predecessor else { throw EntityIdentityResolutionFailureV1.staleRevision }
            let (next, overflow) = predecessor.revision.addingReportingOverflow(1)
            guard !overflow, next == revision, linkEventID != predecessor.linkEventID, predecessor.workspaceID == workspaceID, predecessor.alias.identity == alias.identity,
                  predecessor.linkEventID == supersedesLinkEventID, predecessor.linkSHA256 == predecessorSHA256 else { throw EntityIdentityResolutionFailureV1.staleRevision }
        } else { guard supersedesLinkEventID != nil, predecessorSHA256 != nil else { throw EntityIdentityResolutionFailureV1.staleRevision } }
    }
    func validateResolved(predecessor: EntityAliasLinkV1? = nil, resolver: any EntityIdentityCanonicalResolvingV1) throws {
        if let predecessor { try validate(predecessor: predecessor) } else { try validate() }
        try alias.validateResolved(by: resolver); try canonicalEntity.validateResolved(by: resolver)
        let path = try resolver.aliasPath(from: canonicalEntity.identity, workspaceID: workspaceID)
        guard !path.contains(alias.identity), Set(path).count == path.count else { throw EntityIdentityResolutionFailureV1.aliasCycle }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, linkEventID: linkEventID, workspaceID: workspaceID, alias: alias,
        canonicalEntity: canonicalEntity, revision: revision, supersedesLinkEventID: supersedesLinkEventID, predecessorSHA256: predecessorSHA256,
        reason: reason, policyVersion: policyVersion, policySHA256: policySHA256, recordedBy: recordedBy, recordedAt: recordedAt, mutationID: mutationID) }
    private struct Basis: Codable { let schemaVersion: Int; let linkEventID: UUID; let workspaceID: WorkspaceID; let alias: EntityIdentitySnapshotV1; let canonicalEntity: EntityIdentitySnapshotV1; let revision: UInt64; let supersedesLinkEventID: UUID?; let predecessorSHA256: String?; let reason: EntityIdentityResolutionReasonV1; let policyVersion: UInt64; let policySHA256: String; let recordedBy: ActorSnapshotV1; let recordedAt: Date; let mutationID: MutationIDV1 }
}

enum EntityConsolidationInventoryFamilyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case relationship = "RELATIONSHIP", evidence = "EVIDENCE", content = "CONTENT", history = "HISTORY"
    case tombstone = "TOMBSTONE", mutationReceipt = "MUTATION_RECEIPT"
}

struct EntityConsolidationInventoryAtomV1: Codable, Equatable, Hashable, Sendable {
    let kind: String; let itemID: String; let revision: UInt64; let itemSHA256: String; let associationRole: String
    init(kind: String, itemID: String, revision: UInt64, itemSHA256: String, associationRole: String) throws {
        self.kind = kind; self.itemID = itemID; self.revision = revision; self.itemSHA256 = itemSHA256; self.associationRole = associationRole; try validate()
    }
    func validate() throws { try EntityIdentityResolutionValidationV1.token(kind); try EntityIdentityResolutionValidationV1.token(itemID); try EntityIdentityResolutionValidationV1.revision(revision); try EntityIdentityResolutionValidationV1.digest(itemSHA256); try EntityIdentityResolutionValidationV1.token(associationRole) }
    var stableKey: String { "\(kind)|\(itemID)|\(revision)|\(itemSHA256)|\(associationRole)" }
}

struct EntityConsolidationInventoryFamilyManifestBasisV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let workspaceID: WorkspaceID; let source, survivor: EntityIdentitySnapshotV1
    let family: EntityConsolidationInventoryFamilyV1; let atoms: [EntityConsolidationInventoryAtomV1]
    init(workspaceID: WorkspaceID, source: EntityIdentitySnapshotV1, survivor: EntityIdentitySnapshotV1, family: EntityConsolidationInventoryFamilyV1, atoms: [EntityConsolidationInventoryAtomV1]) throws {
        schemaVersion = Self.schemaVersion; self.workspaceID = workspaceID; self.source = source; self.survivor = survivor; self.family = family
        self.atoms = atoms.sorted { $0.stableKey < $1.stableKey }; try validate()
    }
    func validate() throws {
        try source.validate(); try survivor.validate(); try atoms.forEach { try $0.validate() }
        guard schemaVersion == Self.schemaVersion, source.workspaceID == workspaceID, survivor.workspaceID == workspaceID,
              source.identity != survivor.identity, source.identity.kind == survivor.identity.kind,
              atoms == atoms.sorted(by: { $0.stableKey < $1.stableKey }), Set(atoms.map(\.stableKey)).count == atoms.count,
              atoms.count <= EntityIdentityResolutionLimitsV1.maximumInventoryItemsPerFamily else { throw EntityIdentityResolutionFailureV1.incompleteInventory }
    }
}

struct EntityConsolidationInventoryItemV1: Codable, Equatable, Hashable, Sendable {
    let family: EntityConsolidationInventoryFamilyV1; let itemID: String; let revision: UInt64; let itemSHA256: String
    let relationshipIsEvidenceOnly: Bool
    init(family: EntityConsolidationInventoryFamilyV1, itemID: String, revision: UInt64, itemSHA256: String) throws {
        self.family = family; self.itemID = itemID; self.revision = revision; self.itemSHA256 = itemSHA256
        relationshipIsEvidenceOnly = family == .relationship; try validate()
    }
    func validate() throws {
        try EntityIdentityResolutionValidationV1.token(itemID); try EntityIdentityResolutionValidationV1.revision(revision); try EntityIdentityResolutionValidationV1.digest(itemSHA256)
        guard relationshipIsEvidenceOnly == (family == .relationship), itemID == EntityConsolidationInventoryBuilderV1.manifestItemID(for: family), revision == 1 else { throw EntityIdentityResolutionFailureV1.invalidValue }
    }
    var stableKey: String { "\(family.rawValue)|\(itemID)|\(revision)|\(itemSHA256)" }
}

enum EntityConsolidationInventoryBuilderV1 {
    static func manifestItemID(for family: EntityConsolidationInventoryFamilyV1) -> String { "manifest-\(family.rawValue.lowercased().replacingOccurrences(of: "_", with: "-"))" }
    static func manifestItem(for basis: EntityConsolidationInventoryFamilyManifestBasisV1) throws -> EntityConsolidationInventoryItemV1 {
        try basis.validate()
        return try EntityConsolidationInventoryItemV1(family: basis.family, itemID: manifestItemID(for: basis.family), revision: 1, itemSHA256: EntityIdentityResolutionValidationV1.hash(basis))
    }
    static func inventory(workspaceID: WorkspaceID, source: EntityIdentitySnapshotV1, survivor: EntityIdentitySnapshotV1, atomsByFamily: [EntityConsolidationInventoryFamilyV1: [EntityConsolidationInventoryAtomV1]]) throws -> EntityConsolidationInventoryV1 {
        let bases = try EntityConsolidationInventoryFamilyV1.allCases.map { try EntityConsolidationInventoryFamilyManifestBasisV1(workspaceID: workspaceID, source: source, survivor: survivor, family: $0, atoms: atomsByFamily[$0] ?? []) }
        return try EntityConsolidationInventoryV1(bases: bases)
    }
    static func manifestItems(for bases: [EntityConsolidationInventoryFamilyManifestBasisV1]) throws -> [EntityConsolidationInventoryItemV1] { try bases.map(manifestItem).sorted { $0.stableKey < $1.stableKey } }
}

struct EntityConsolidationInventoryV1: Codable, Equatable, Sendable {
    let items: [EntityConsolidationInventoryItemV1]; let inventorySHA256: String
    init(bases: [EntityConsolidationInventoryFamilyManifestBasisV1]) throws {
        self.items = try EntityConsolidationInventoryBuilderV1.manifestItems(for: bases)
        inventorySHA256 = try EntityIdentityResolutionValidationV1.hash(items); try validate(against: bases)
    }
    func validate() throws {
        try items.forEach { try $0.validate() }
        let grouped = Dictionary(grouping: items, by: \.family)
        guard EntityConsolidationInventoryFamilyV1.allCases.allSatisfy({ grouped[$0]?.count == 1 }), items.count == EntityConsolidationInventoryFamilyV1.allCases.count,
              items == items.sorted(by: { $0.stableKey < $1.stableKey }), Set(items.map(\.stableKey)).count == items.count,
              inventorySHA256 == (try EntityIdentityResolutionValidationV1.hash(items)) else { throw EntityIdentityResolutionFailureV1.incompleteInventory }
    }
    func validate(against bases: [EntityConsolidationInventoryFamilyManifestBasisV1]) throws {
        try validate(); try bases.forEach { try $0.validate() }
        guard bases.count == EntityConsolidationInventoryFamilyV1.allCases.count,
              Set(bases.map(\.family)).count == bases.count,
              items == (try EntityConsolidationInventoryBuilderV1.manifestItems(for: bases)) else { throw EntityIdentityResolutionFailureV1.incompleteInventory }
    }
}

enum EntityConsolidationDispositionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case consolidated = "CONSOLIDATED"
    case reversedBySuccessor = "REVERSED_BY_SUCCESSOR"
}

struct EntityConsolidationReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let consolidationReceiptID: UUID; let workspaceID: WorkspaceID
    let source: EntityIdentitySnapshotV1; let survivor: EntityIdentitySnapshotV1; let inventory: EntityConsolidationInventoryV1
    let disposition: EntityConsolidationDispositionV1; let revision: UInt64; let supersedesReceiptID: UUID?; let predecessorSHA256: String?
    let policyVersion: UInt64; let policySHA256: String; let recordedBy: ActorSnapshotV1; let recordedAt: Date
    let mutationID: MutationIDV1; let receiptSHA256: String
    var receiptID: UUID { consolidationReceiptID }
    var predecessorReceiptID: UUID? { supersedesReceiptID }
    var reversal: Bool { disposition == .reversedBySuccessor }
    var sourceIDs: [UUID] { [source.identity.id] }
    var survivorIDs: [UUID] { [survivor.identity.id] }
    init(consolidationReceiptID: UUID, workspaceID: WorkspaceID, source: EntityIdentitySnapshotV1,
         survivor: EntityIdentitySnapshotV1, inventory: EntityConsolidationInventoryV1,
         disposition: EntityConsolidationDispositionV1 = .consolidated, revision: UInt64,
         predecessor: EntityConsolidationReceiptV1? = nil, policyVersion: UInt64, policySHA256: String,
         recordedBy: ActorSnapshotV1, recordedAt: Date, mutationID: MutationIDV1) throws {
        schemaVersion = Self.schemaVersion; self.consolidationReceiptID = consolidationReceiptID; self.workspaceID = workspaceID
        self.source = source; self.survivor = survivor; self.inventory = inventory; self.disposition = disposition; self.revision = revision
        supersedesReceiptID = predecessor?.consolidationReceiptID; predecessorSHA256 = predecessor?.receiptSHA256
        self.policyVersion = policyVersion; self.policySHA256 = policySHA256; self.recordedBy = recordedBy; self.recordedAt = recordedAt; self.mutationID = mutationID
        receiptSHA256 = try EntityIdentityResolutionValidationV1.hash(Basis(schemaVersion: Self.schemaVersion,
            consolidationReceiptID: consolidationReceiptID, workspaceID: workspaceID, source: source, survivor: survivor,
            inventory: inventory, disposition: disposition, revision: revision, supersedesReceiptID: predecessor?.consolidationReceiptID,
            predecessorSHA256: predecessor?.receiptSHA256, policyVersion: policyVersion, policySHA256: policySHA256,
            recordedBy: recordedBy, recordedAt: recordedAt, mutationID: mutationID)); try validate(predecessor: predecessor)
    }
    func validate() throws { try validate(predecessor: nil, requirePredecessor: false) }
    func validate(predecessor: EntityConsolidationReceiptV1?) throws { try validate(predecessor: predecessor, requirePredecessor: true) }
    private func validate(predecessor: EntityConsolidationReceiptV1?, requirePredecessor: Bool) throws {
        try EntityIdentityResolutionValidationV1.id(consolidationReceiptID); try source.validate(); try survivor.validate(); try inventory.validate()
        try EntityIdentityResolutionValidationV1.revision(revision); try EntityIdentityResolutionValidationV1.revision(policyVersion)
        try EntityIdentityResolutionValidationV1.digest(policySHA256); try recordedBy.validate(); try EntityIdentityResolutionValidationV1.instant(recordedAt)
        guard schemaVersion == Self.schemaVersion, source.workspaceID == workspaceID, survivor.workspaceID == workspaceID,
              source.identity != survivor.identity, source.identity.kind == survivor.identity.kind, recordedBy.workspaceID == workspaceID,
              receiptSHA256 == (try EntityIdentityResolutionValidationV1.hash(basis)) else { throw EntityIdentityResolutionFailureV1.wrongWorkspace }
        if revision == 1 {
            guard disposition == .consolidated, predecessor == nil, supersedesReceiptID == nil, predecessorSHA256 == nil else { throw EntityIdentityResolutionFailureV1.invalidSuccessor }
        } else if requirePredecessor {
            guard disposition == .reversedBySuccessor, let predecessor, predecessor.disposition == .consolidated else { throw EntityIdentityResolutionFailureV1.invalidSuccessor }
            let (next, overflow) = predecessor.revision.addingReportingOverflow(1)
            guard !overflow, next == revision, consolidationReceiptID != predecessor.consolidationReceiptID, predecessor.workspaceID == workspaceID, predecessor.source == source,
                  predecessor.survivor == survivor, predecessor.inventory == inventory,
                  predecessor.consolidationReceiptID == supersedesReceiptID, predecessor.receiptSHA256 == predecessorSHA256
            else { throw EntityIdentityResolutionFailureV1.invalidSuccessor }
        } else { guard disposition == .reversedBySuccessor, supersedesReceiptID != nil, predecessorSHA256 != nil else { throw EntityIdentityResolutionFailureV1.invalidSuccessor } }
    }
    func validateResolved(predecessor: EntityConsolidationReceiptV1? = nil, resolver: any EntityIdentityCanonicalResolvingV1) throws {
        if let predecessor { try validate(predecessor: predecessor) } else { try validate() }
        try source.validateResolved(by: resolver); try survivor.validateResolved(by: resolver)
        guard try resolver.canonicalConsolidationInventory(source: source, survivor: survivor) == inventory else { throw EntityIdentityResolutionFailureV1.incompleteInventory }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, consolidationReceiptID: consolidationReceiptID, workspaceID: workspaceID,
        source: source, survivor: survivor, inventory: inventory, disposition: disposition, revision: revision,
        supersedesReceiptID: supersedesReceiptID, predecessorSHA256: predecessorSHA256, policyVersion: policyVersion,
        policySHA256: policySHA256, recordedBy: recordedBy, recordedAt: recordedAt, mutationID: mutationID) }
    private struct Basis: Codable { let schemaVersion: Int; let consolidationReceiptID: UUID; let workspaceID: WorkspaceID; let source: EntityIdentitySnapshotV1; let survivor: EntityIdentitySnapshotV1; let inventory: EntityConsolidationInventoryV1; let disposition: EntityConsolidationDispositionV1; let revision: UInt64; let supersedesReceiptID: UUID?; let predecessorSHA256: String?; let policyVersion: UInt64; let policySHA256: String; let recordedBy: ActorSnapshotV1; let recordedAt: Date; let mutationID: MutationIDV1 }
}

enum EntityIdentityResolutionMutationPayloadV1: Codable, Equatable, Sendable {
    case alias(EntityAliasLinkV1, EntityAliasLinkV1?)
    case consolidation(EntityConsolidationReceiptV1, EntityConsolidationReceiptV1?)
    var workspaceID: WorkspaceID { switch self { case let .alias(v, _): return v.workspaceID; case let .consolidation(v, _): return v.workspaceID } }
    var mutationID: MutationIDV1 { switch self { case let .alias(v, _): return v.mutationID; case let .consolidation(v, _): return v.mutationID } }
    var semanticSHA256s: [String] { switch self { case let .alias(v, _): return [v.linkSHA256]; case let .consolidation(v, _): return [v.receiptSHA256] } }
    func validate() throws { switch self { case let .alias(v, p): try v.validate(predecessor: p); case let .consolidation(v, p): try v.validate(predecessor: p) } }
    func validateResolved(by resolver: any EntityIdentityCanonicalResolvingV1) throws {
        switch self { case let .alias(v, p): try v.validateResolved(predecessor: p, resolver: resolver); case let .consolidation(v, p): try v.validateResolved(predecessor: p, resolver: resolver) }
    }
}

struct EntityIdentityResolutionMutationCommandV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let commandID: UUID; let workspaceID: WorkspaceID; let expectedRevision: WorkspaceExpectedRevisionV1
    let mutationID: MutationIDV1; let payload: EntityIdentityResolutionMutationPayloadV1; let submittedAt: Date; let commandSHA256: String
    init(commandID: UUID, workspaceID: WorkspaceID, expectedRevision: WorkspaceExpectedRevisionV1,
         mutationID: MutationIDV1, payload: EntityIdentityResolutionMutationPayloadV1, submittedAt: Date) throws {
        schemaVersion = Self.schemaVersion; self.commandID = commandID; self.workspaceID = workspaceID; self.expectedRevision = expectedRevision
        self.mutationID = mutationID; self.payload = payload; self.submittedAt = submittedAt
        commandSHA256 = try EntityIdentityResolutionValidationV1.hash(Basis(schemaVersion: Self.schemaVersion, commandID: commandID,
            workspaceID: workspaceID, expectedRevision: expectedRevision, mutationID: mutationID, payload: payload, submittedAt: submittedAt)); try validate()
    }
    func validate() throws {
        try EntityIdentityResolutionValidationV1.id(commandID); try payload.validate(); try EntityIdentityResolutionValidationV1.instant(submittedAt)
        guard schemaVersion == Self.schemaVersion, expectedRevision.workspaceID == workspaceID,
              expectedRevision.generationID != EntityIdentityResolutionValidationV1.zero,
              expectedRevision.writerInstanceID != EntityIdentityResolutionValidationV1.zero,
              payload.workspaceID == workspaceID, payload.mutationID == mutationID,
              commandSHA256 == (try EntityIdentityResolutionValidationV1.hash(basis)) else { throw EntityIdentityResolutionFailureV1.wrongWorkspace }
    }
    func validate(currentRevision: WorkspaceRevisionV1, resolver: any EntityIdentityCanonicalResolvingV1) throws {
        try validate(); guard WorkspaceExpectedRevisionV1(snapshot: currentRevision) == expectedRevision else { throw EntityIdentityResolutionFailureV1.staleRevision }
        try payload.validateResolved(by: resolver)
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, commandID: commandID, workspaceID: workspaceID, expectedRevision: expectedRevision, mutationID: mutationID, payload: payload, submittedAt: submittedAt) }
    private struct Basis: Codable { let schemaVersion: Int; let commandID: UUID; let workspaceID: WorkspaceID; let expectedRevision: WorkspaceExpectedRevisionV1; let mutationID: MutationIDV1; let payload: EntityIdentityResolutionMutationPayloadV1; let submittedAt: Date }
}

enum EntityIdentityResolutionQueryTargetV1: Codable, Equatable, Sendable {
    case aliases(WorkspaceEntityIdentityV1), consolidationHistory(UUID), resolve(WorkspaceEntityIdentityV1)
}
struct EntityIdentityResolutionQueryV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID; let target: EntityIdentityResolutionQueryTargetV1; let maximumResults: Int
    init(workspaceID: WorkspaceID, target: EntityIdentityResolutionQueryTargetV1, maximumResults: Int = 100) throws {
        guard (1...EntityIdentityResolutionLimitsV1.maximumQueryResults).contains(maximumResults) else { throw EntityIdentityResolutionFailureV1.invalidValue }
        if case let .consolidationHistory(id) = target { try EntityIdentityResolutionValidationV1.id(id) }
        self.workspaceID = workspaceID; self.target = target; self.maximumResults = maximumResults
    }
    func validate() throws { _ = try Self(workspaceID: workspaceID, target: target, maximumResults: maximumResults) }
}
enum EntityIdentityResolutionQueryResultV1: Codable, Equatable, Sendable {
    case aliases([EntityAliasLinkV1]), consolidationHistory([EntityConsolidationReceiptV1])
    case resolved(EntityIdentitySnapshotV1, [EntityAliasLinkV1]); case notFound(EntityIdentityResolutionQueryV1)
    func validate(for query: EntityIdentityResolutionQueryV1) throws {
        try query.validate()
        switch (query.target, self) {
        case let (.aliases(identity), .aliases(values)):
            try values.forEach { try $0.validate() }; guard values.count <= query.maximumResults, values.allSatisfy({ $0.workspaceID == query.workspaceID && $0.alias.identity == identity }), Set(values.map(\.linkEventID)).count == values.count else { throw EntityIdentityResolutionFailureV1.duplicateIdentity }
        case let (.consolidationHistory(receiptID), .consolidationHistory(values)):
            try validateConsolidationHistory(values, queriedReceiptID: receiptID, workspaceID: query.workspaceID, maximumResults: query.maximumResults)
        case let (.resolve(identity), .resolved(snapshot, path)):
            try validateResolvedPath(path, identity: identity, snapshot: snapshot, workspaceID: query.workspaceID, maximumResults: query.maximumResults)
        case let (_, .notFound(bound)): guard bound == query else { throw EntityIdentityResolutionFailureV1.receiptMismatch }
        default: throw EntityIdentityResolutionFailureV1.invalidValue
        }
    }

    private func validateConsolidationHistory(_ values: [EntityConsolidationReceiptV1], queriedReceiptID: UUID, workspaceID: WorkspaceID, maximumResults: Int) throws {
        guard !values.isEmpty, values.count <= maximumResults, values.allSatisfy({ $0.workspaceID == workspaceID }),
              Set(values.map(\.consolidationReceiptID)).count == values.count else { throw EntityIdentityResolutionFailureV1.duplicateIdentity }
        let ordered = values.sorted { $0.revision < $1.revision }
        guard let root = ordered.first, root.revision == 1,
              values.filter({ $0.consolidationReceiptID == queriedReceiptID }).count == 1,
              ordered.allSatisfy({ $0.source == root.source && $0.survivor == root.survivor }) else { throw EntityIdentityResolutionFailureV1.invalidSuccessor }
        try root.validate(predecessor: nil)
        for index in ordered.indices.dropFirst() { try ordered[index].validate(predecessor: ordered[index - 1]) }
    }

    private func validateResolvedPath(_ path: [EntityAliasLinkV1], identity: WorkspaceEntityIdentityV1, snapshot: EntityIdentitySnapshotV1, workspaceID: WorkspaceID, maximumResults: Int) throws {
        try snapshot.validate(); try path.forEach { try $0.validate() }
        guard snapshot.workspaceID == workspaceID, path.count <= maximumResults,
              path.allSatisfy({ $0.workspaceID == workspaceID }), Set(path.map(\.linkEventID)).count == path.count,
              Set(path.map { $0.alias.identity }).count == path.count else { throw EntityIdentityResolutionFailureV1.duplicateIdentity }
        var expected = identity
        var visited = Set([identity])
        for link in path {
            guard link.alias.identity == expected, !visited.contains(link.canonicalEntity.identity) else { throw EntityIdentityResolutionFailureV1.aliasCycle }
            visited.insert(link.canonicalEntity.identity); expected = link.canonicalEntity.identity
        }
        guard snapshot.identity == expected, path.last.map({ $0.canonicalEntity.revision == snapshot.revision }) ?? true else { throw EntityIdentityResolutionFailureV1.staleRevision }
    }
}

enum EntityIdentityResolutionRecoveryStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case effectCommittedAwaitingReceipt = "EFFECT_COMMITTED_AWAITING_RECEIPT", receiptCommitted = "RECEIPT_COMMITTED"
}
struct EntityIdentityResolutionMutationReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let receiptID: UUID; let commandID: UUID; let workspaceID: WorkspaceID; let generationID: UUID; let mutationID: MutationIDV1
    let commandSHA256: String; let semanticSHA256s: [String]; let priorWorkspaceRevision: UInt64; let resultingWorkspaceRevision: UInt64
    let recoveryState: EntityIdentityResolutionRecoveryStateV1; let committedAt: Date; let receiptSHA256: String
    init(receiptID: UUID, command: EntityIdentityResolutionMutationCommandV1, resultingWorkspaceRevision: UInt64,
         recoveryState: EntityIdentityResolutionRecoveryStateV1, committedAt: Date) throws {
        try command.validate(); schemaVersion = Self.schemaVersion; self.receiptID = receiptID; commandID = command.commandID; workspaceID = command.workspaceID
        generationID = command.expectedRevision.generationID; mutationID = command.mutationID; commandSHA256 = command.commandSHA256
        semanticSHA256s = command.payload.semanticSHA256s.sorted(); priorWorkspaceRevision = command.expectedRevision.workspaceRevision
        self.resultingWorkspaceRevision = resultingWorkspaceRevision; self.recoveryState = recoveryState; self.committedAt = committedAt
        receiptSHA256 = try EntityIdentityResolutionValidationV1.hash(Basis(schemaVersion: Self.schemaVersion, receiptID: receiptID, commandID: command.commandID,
            workspaceID: command.workspaceID, generationID: command.expectedRevision.generationID, mutationID: command.mutationID,
            commandSHA256: command.commandSHA256, semanticSHA256s: command.payload.semanticSHA256s.sorted(),
            priorWorkspaceRevision: command.expectedRevision.workspaceRevision, resultingWorkspaceRevision: resultingWorkspaceRevision,
            recoveryState: recoveryState, committedAt: committedAt)); try validate(command: command)
    }
    func validate() throws {
        try EntityIdentityResolutionValidationV1.id(receiptID); try EntityIdentityResolutionValidationV1.id(commandID); try EntityIdentityResolutionValidationV1.id(generationID)
        try EntityIdentityResolutionValidationV1.digest(commandSHA256); try semanticSHA256s.forEach(EntityIdentityResolutionValidationV1.digest)
        try EntityIdentityResolutionValidationV1.instant(committedAt); let (next, overflow) = priorWorkspaceRevision.addingReportingOverflow(1)
        guard !overflow, schemaVersion == Self.schemaVersion, resultingWorkspaceRevision == next, !semanticSHA256s.isEmpty,
              semanticSHA256s == semanticSHA256s.sorted(), Set(semanticSHA256s).count == semanticSHA256s.count,
              receiptSHA256 == (try EntityIdentityResolutionValidationV1.hash(basis)) else { throw EntityIdentityResolutionFailureV1.receiptMismatch }
    }
    func validate(command: EntityIdentityResolutionMutationCommandV1) throws {
        try validate(); try command.validate(); guard workspaceID == command.workspaceID, generationID == command.expectedRevision.generationID,
              commandID == command.commandID, mutationID == command.mutationID, commandSHA256 == command.commandSHA256,
              semanticSHA256s == command.payload.semanticSHA256s.sorted(), priorWorkspaceRevision == command.expectedRevision.workspaceRevision
        else { throw EntityIdentityResolutionFailureV1.receiptMismatch }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, receiptID: receiptID, commandID: commandID, workspaceID: workspaceID, generationID: generationID,
        mutationID: mutationID, commandSHA256: commandSHA256, semanticSHA256s: semanticSHA256s,
        priorWorkspaceRevision: priorWorkspaceRevision, resultingWorkspaceRevision: resultingWorkspaceRevision,
        recoveryState: recoveryState, committedAt: committedAt) }
    private struct Basis: Codable { let schemaVersion: Int; let receiptID: UUID; let commandID: UUID; let workspaceID: WorkspaceID; let generationID: UUID; let mutationID: MutationIDV1; let commandSHA256: String; let semanticSHA256s: [String]; let priorWorkspaceRevision: UInt64; let resultingWorkspaceRevision: UInt64; let recoveryState: EntityIdentityResolutionRecoveryStateV1; let committedAt: Date }
}

struct EntityIdentityResolutionCanonicalSourceV1: Codable, Equatable, Sendable {
    let snapshot: EntityIdentitySnapshotV1
    let inventory: EntityConsolidationInventoryV1

    init(snapshot: EntityIdentitySnapshotV1, inventory: EntityConsolidationInventoryV1) throws {
        self.snapshot = snapshot; self.inventory = inventory; try validate()
    }

    func validate() throws { try snapshot.validate(); try inventory.validate() }
}

protocol EntityIdentityResolutionCanonicalSourceResolvingV1: EntityIdentityCanonicalResolvingV1 {
    func resolve(workspaceID: WorkspaceID, entityID: WorkspaceEntityIdentityV1, expectedRevision: UInt64) throws -> EntityIdentityResolutionCanonicalSourceV1
}

extension EntityIdentityResolutionMutationCommandV1 {
    func validateCanonicalSources(by resolver: any EntityIdentityResolutionCanonicalSourceResolvingV1) throws {
        try validate()
        switch payload {
        case let .alias(link, _):
            let alias = try resolver.resolve(workspaceID: workspaceID, entityID: link.alias.identity, expectedRevision: link.alias.revision)
            let canonical = try resolver.resolve(workspaceID: workspaceID, entityID: link.canonicalEntity.identity, expectedRevision: link.canonicalEntity.revision)
            guard alias.snapshot == link.alias, canonical.snapshot == link.canonicalEntity else { throw EntityIdentityResolutionFailureV1.staleRevision }
            try alias.inventory.validate(); try canonical.inventory.validate()
        case let .consolidation(receipt, _):
            let source = try resolver.resolve(workspaceID: workspaceID, entityID: receipt.source.identity, expectedRevision: receipt.source.revision)
            let survivor = try resolver.resolve(workspaceID: workspaceID, entityID: receipt.survivor.identity, expectedRevision: receipt.survivor.revision)
            guard source.snapshot == receipt.source, survivor.snapshot == receipt.survivor else { throw EntityIdentityResolutionFailureV1.staleRevision }
            try source.inventory.validate(); try survivor.inventory.validate()
            guard try resolver.canonicalConsolidationInventory(source: receipt.source, survivor: receipt.survivor) == receipt.inventory
            else { throw EntityIdentityResolutionFailureV1.incompleteInventory }
        }
    }
}

/// Canonical, domain-owned backup value. Lifecycle adapters must exchange this
/// value rather than exposing an infrastructure-nested snapshot type.
struct EntityIdentityResolutionBackupSnapshotV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let generationID: UUID
    let aliasLinks: [EntityAliasLinkV1]
    let consolidationReceipts: [EntityConsolidationReceiptV1]
    let mutationReceipts: [EntityIdentityResolutionMutationReceiptV1]
    let snapshotSHA256: String

    init(
        workspaceID: WorkspaceID,
        generationID: UUID,
        aliasLinks: [EntityAliasLinkV1],
        consolidationReceipts: [EntityConsolidationReceiptV1],
        mutationReceipts: [EntityIdentityResolutionMutationReceiptV1]
    ) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.generationID = generationID
        self.aliasLinks = aliasLinks.sorted { $0.linkEventID.uuidString < $1.linkEventID.uuidString }
        self.consolidationReceipts = consolidationReceipts.sorted { $0.consolidationReceiptID.uuidString < $1.consolidationReceiptID.uuidString }
        self.mutationReceipts = mutationReceipts.sorted { $0.receiptID.uuidString < $1.receiptID.uuidString }
        snapshotSHA256 = try EntityIdentityResolutionValidationV1.hash(Basis(
            schemaVersion: Self.schemaVersion,
            workspaceID: workspaceID,
            generationID: generationID,
            aliasLinks: self.aliasLinks,
            consolidationReceipts: self.consolidationReceipts,
            mutationReceipts: self.mutationReceipts
        ))
        try validate()
    }

    func validate() throws {
        try EntityIdentityResolutionValidationV1.id(generationID)
        guard schemaVersion == Self.schemaVersion,
              aliasLinks == aliasLinks.sorted(by: { $0.linkEventID.uuidString < $1.linkEventID.uuidString }),
              consolidationReceipts == consolidationReceipts.sorted(by: { $0.consolidationReceiptID.uuidString < $1.consolidationReceiptID.uuidString }),
              mutationReceipts == mutationReceipts.sorted(by: { $0.receiptID.uuidString < $1.receiptID.uuidString }),
              Set(aliasLinks.map(\.linkEventID)).count == aliasLinks.count,
              Set(consolidationReceipts.map(\.consolidationReceiptID)).count == consolidationReceipts.count,
              Set(mutationReceipts.map(\.receiptID)).count == mutationReceipts.count,
              Set(mutationReceipts.map(\.commandID)).count == mutationReceipts.count,
              Set(mutationReceipts.map(\.mutationID)).count == mutationReceipts.count,
              snapshotSHA256 == (try EntityIdentityResolutionValidationV1.hash(basis))
        else { throw EntityIdentityResolutionFailureV1.receiptMismatch }

        try aliasLinks.forEach { try $0.validate() }
        try consolidationReceipts.forEach { try $0.validate() }
        try mutationReceipts.forEach { try $0.validate() }
        guard aliasLinks.allSatisfy({ $0.workspaceID == workspaceID }),
              consolidationReceipts.allSatisfy({ $0.workspaceID == workspaceID }),
              mutationReceipts.allSatisfy({ $0.workspaceID == workspaceID && $0.generationID == generationID })
        else { throw EntityIdentityResolutionFailureV1.wrongWorkspace }

        try validateAliasChains()
        try validateConsolidationChains()
        try validateReceiptEffectParity()
    }

    private func validateAliasChains() throws {
        for chain in Dictionary(grouping: aliasLinks, by: { $0.alias.identity.stableKey }).values {
            let ordered = chain.sorted { $0.revision < $1.revision }
            guard let first = ordered.first, first.revision == 1 else { throw EntityIdentityResolutionFailureV1.staleRevision }
            try first.validate(predecessor: nil)
            for index in ordered.indices.dropFirst() { try ordered[index].validate(predecessor: ordered[index - 1]) }
        }
    }

    private func validateConsolidationChains() throws {
        for chain in Dictionary(grouping: consolidationReceipts, by: { "\($0.source.identity.stableKey)|\($0.survivor.identity.stableKey)" }).values {
            let ordered = chain.sorted { $0.revision < $1.revision }
            guard let first = ordered.first, first.revision == 1 else { throw EntityIdentityResolutionFailureV1.invalidSuccessor }
            try first.validate(predecessor: nil)
            for index in ordered.indices.dropFirst() { try ordered[index].validate(predecessor: ordered[index - 1]) }
        }
    }

    private func validateReceiptEffectParity() throws {
        let effects = aliasLinks.map { ($0.mutationID, $0.linkSHA256) } + consolidationReceipts.map { ($0.mutationID, $0.receiptSHA256) }
        let effectMutationIDs = effects.map(\.0)
        let receiptMutationIDs = mutationReceipts.map(\.mutationID)
        guard effects.count == mutationReceipts.count,
              Set(effectMutationIDs).count == effects.count,
              Set(receiptMutationIDs) == Set(effectMutationIDs) else { throw EntityIdentityResolutionFailureV1.receiptMismatch }
        let effectDigestByMutation = Dictionary(uniqueKeysWithValues: effects)
        for receipt in mutationReceipts {
            guard let effectDigest = effectDigestByMutation[receipt.mutationID], receipt.semanticSHA256s == [effectDigest] else { throw EntityIdentityResolutionFailureV1.receiptMismatch }
        }
    }

    private var basis: Basis { Basis(schemaVersion: schemaVersion, workspaceID: workspaceID, generationID: generationID, aliasLinks: aliasLinks, consolidationReceipts: consolidationReceipts, mutationReceipts: mutationReceipts) }
    private struct Basis: Codable {
        let schemaVersion: Int
        let workspaceID: WorkspaceID
        let generationID: UUID
        let aliasLinks: [EntityAliasLinkV1]
        let consolidationReceipts: [EntityConsolidationReceiptV1]
        let mutationReceipts: [EntityIdentityResolutionMutationReceiptV1]
    }
}

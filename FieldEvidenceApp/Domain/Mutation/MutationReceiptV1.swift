import Foundation

struct MutationReceiptIdentityV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let replicaID: ReplicaID
    let localSequence: UInt64

    init(workspaceID: WorkspaceID, replicaID: ReplicaID, localSequence: UInt64) {
        self.workspaceID = workspaceID
        self.replicaID = replicaID
        self.localSequence = localSequence
    }

    func validate() throws {
        guard localSequence > 0,
              (try? WorkspaceReplicaIdentityV1(
                workspaceID: workspaceID,
                replicaID: replicaID
              )) != nil else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }
    }

    private enum CodingKeys: String, CodingKey {
        case workspaceID, replicaID, localSequence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspaceID = try container.decode(WorkspaceID.self, forKey: .workspaceID)
        replicaID = try container.decode(ReplicaID.self, forKey: .replicaID)
        localSequence = try container.decode(UInt64.self, forKey: .localSequence)
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workspaceID, forKey: .workspaceID)
        try container.encode(replicaID, forKey: .replicaID)
        try container.encode(localSequence, forKey: .localSequence)
    }

    var stableKey: String {
        "\(workspaceID.rawValue.uuidString.lowercased()):\(replicaID.rawValue.uuidString.lowercased()):\(localSequence)"
    }
}

enum MutationWorkspaceKeyV1 {
    static func value(workspaceID: WorkspaceID, mutationID: MutationIDV1) -> String {
        "\(workspaceID.rawValue.uuidString.lowercased()):\(mutationID.rawValue.uuidString.lowercased())"
    }
}

enum MutationQuarantineIdentityDomainV1: String, Codable, Equatable, Sendable {
    case mutationEnvelope = "MUTATION_ENVELOPE"
    case semanticReversalReplayIdentity = "SEMANTIC_REVERSAL_REPLAY_IDENTITY"
}

enum MutationPostImageV1: Codable, Equatable, Sendable {
    case site(id: UUID, revision: UInt64, semanticSHA256: String)
    case asset(id: UUID, revision: UInt64, semanticSHA256: String)
    case locationNode(id: UUID, revision: UInt64, semanticSHA256: String)
    case assetPlacementEvent(id: UUID, revision: UInt64, semanticSHA256: String)
    case assetCompositionEdge(id: UUID, revision: UInt64, semanticSHA256: String)
    case assetCompositionEvent(id: UUID, revision: UInt64, semanticSHA256: String)
    case savedSmartView(id: UUID, revision: UInt64, semanticSHA256: String)
    case serviceParty(id: UUID, revision: UInt64, semanticSHA256: String)
    case sitePartyRoleEvent(id: UUID, revision: UInt64, semanticSHA256: String)
    case actorSnapshot(id: UUID, revision: UInt64, semanticSHA256: String)
    case qualificationSnapshot(id: UUID, revision: UInt64, semanticSHA256: String)
    case signoffSnapshot(id: UUID, revision: UInt64, semanticSHA256: String)
    case authoritySourceRelease(id: UUID, concurrencyIdentity: WorkspaceEntityIdentityV1, revision: UInt64, semanticSHA256: String)
    case requirementBasisBinding(id: UUID, concurrencyIdentity: WorkspaceEntityIdentityV1, revision: UInt64, semanticSHA256: String)
    case applicabilityContextSnapshot(id: UUID, concurrencyIdentity: WorkspaceEntityIdentityV1, revision: UInt64, semanticSHA256: String)
    case assessmentScopeSnapshot(id: UUID, concurrencyIdentity: WorkspaceEntityIdentityV1, revision: UInt64, semanticSHA256: String)
    case severityScaleRelease(id: UUID, concurrencyIdentity: WorkspaceEntityIdentityV1, revision: UInt64, semanticSHA256: String)
    case findingClassificationBinding(id: UUID, concurrencyIdentity: WorkspaceEntityIdentityV1, revision: UInt64, semanticSHA256: String)
    case measurementProtocolRelease(id: UUID, concurrencyIdentity: WorkspaceEntityIdentityV1, revision: UInt64, semanticSHA256: String)
    case derivedFactEvaluatorDescriptor(id: UUID, concurrencyIdentity: WorkspaceEntityIdentityV1, revision: UInt64, semanticSHA256: String)
    case derivedFactProvenance(id: UUID, concurrencyIdentity: WorkspaceEntityIdentityV1, revision: UInt64, semanticSHA256: String)
    case workflowRecord(id: UUID, revision: UInt64, semanticSHA256: String)
    case evidenceFile(id: UUID, revision: UInt64, semanticSHA256: String)
    case issue(id: UUID, revision: UInt64, semanticSHA256: String)
    case packet(id: UUID, revision: UInt64, semanticSHA256: String)
    case report(id: UUID, revision: UInt64, semanticSHA256: String)
    case deletionLedgerEntry(id: UUID, revision: UInt64, semanticSHA256: String)
    case tombstone(identity: WorkspaceEntityIdentityV1, revision: UInt64, semanticSHA256: String)

    var identity: WorkspaceEntityIdentityV1 {
        get throws {
            switch self {
            case let .site(id, _, _): return try .init(kind: .site, id: id)
            case let .asset(id, _, _): return try .init(kind: .asset, id: id)
            case let .locationNode(id, _, _): return try .init(kind: .locationNode, id: id)
            case let .assetPlacementEvent(id, _, _): return try .init(kind: .assetPlacementEvent, id: id)
            case let .assetCompositionEdge(id, _, _): return try .init(kind: .assetCompositionEdge, id: id)
            case let .assetCompositionEvent(id, _, _): return try .init(kind: .assetCompositionEvent, id: id)
            case let .savedSmartView(id, _, _): return try .init(kind: .savedSmartView, id: id)
            case let .serviceParty(id, _, _): return try .init(kind: .serviceParty, id: id)
            case let .sitePartyRoleEvent(id, _, _): return try .init(kind: .sitePartyRoleEvent, id: id)
            case let .actorSnapshot(id, _, _): return try .init(kind: .actorSnapshot, id: id)
            case let .qualificationSnapshot(id, _, _): return try .init(kind: .qualificationSnapshot, id: id)
            case let .signoffSnapshot(id, _, _): return try .init(kind: .signoffSnapshot, id: id)
            case let .authoritySourceRelease(id, _, _, _): return try .init(kind: .authoritySourceRelease, id: id)
            case let .requirementBasisBinding(id, _, _, _): return try .init(kind: .requirementBasisBinding, id: id)
            case let .applicabilityContextSnapshot(id, _, _, _): return try .init(kind: .applicabilityContextSnapshot, id: id)
            case let .assessmentScopeSnapshot(id, _, _, _): return try .init(kind: .assessmentScopeSnapshot, id: id)
            case let .severityScaleRelease(id, _, _, _): return try .init(kind: .severityScaleRelease, id: id)
            case let .findingClassificationBinding(id, _, _, _): return try .init(kind: .findingClassificationBinding, id: id)
            case let .measurementProtocolRelease(id, _, _, _): return try .init(kind: .measurementProtocolRelease, id: id)
            case let .derivedFactEvaluatorDescriptor(id, _, _, _): return try .init(kind: .derivedFactEvaluatorDescriptor, id: id)
            case let .derivedFactProvenance(id, _, _, _): return try .init(kind: .derivedFactProvenance, id: id)
            case let .workflowRecord(id, _, _): return try .init(kind: .workflowRecord, id: id)
            case let .evidenceFile(id, _, _): return try .init(kind: .evidenceFile, id: id)
            case let .issue(id, _, _): return try .init(kind: .issue, id: id)
            case let .packet(id, _, _): return try .init(kind: .packet, id: id)
            case let .report(id, _, _): return try .init(kind: .report, id: id)
            case let .deletionLedgerEntry(id, _, _): return try .init(kind: .deletionLedgerEntry, id: id)
            case let .tombstone(identity, _, _): return identity
            }
        }
    }

    var semanticSHA256: String {
        switch self {
        case let .site(_, _, value), let .asset(_, _, value), let .locationNode(_, _, value),
             let .assetPlacementEvent(_, _, value), let .assetCompositionEdge(_, _, value),
             let .assetCompositionEvent(_, _, value), let .savedSmartView(_, _, value),
             let .serviceParty(_, _, value), let .sitePartyRoleEvent(_, _, value),
             let .actorSnapshot(_, _, value), let .qualificationSnapshot(_, _, value),
             let .signoffSnapshot(_, _, value),
             let .authoritySourceRelease(_, _, _, value), let .requirementBasisBinding(_, _, _, value),
             let .applicabilityContextSnapshot(_, _, _, value), let .assessmentScopeSnapshot(_, _, _, value),
             let .severityScaleRelease(_, _, _, value), let .findingClassificationBinding(_, _, _, value),
             let .measurementProtocolRelease(_, _, _, value), let .derivedFactEvaluatorDescriptor(_, _, _, value),
             let .derivedFactProvenance(_, _, _, value),
             let .workflowRecord(_, _, value),
             let .evidenceFile(_, _, value), let .issue(_, _, value), let .packet(_, _, value),
             let .report(_, _, value), let .deletionLedgerEntry(_, _, value),
             let .tombstone(_, _, value): return value
        }
    }

    var concurrencyIdentity: WorkspaceEntityIdentityV1 {
        get throws {
            switch self {
            case let .authoritySourceRelease(_, value, _, _):
                guard value.kind == .authoritySourceRelease else { throw WorkspaceMutationFailureV1.invalidReceipt }; return value
            case let .requirementBasisBinding(_, value, _, _):
                guard value.kind == .requirementBasisBinding else { throw WorkspaceMutationFailureV1.invalidReceipt }; return value
            case let .applicabilityContextSnapshot(_, value, _, _):
                guard value.kind == .applicabilityContextSnapshot else { throw WorkspaceMutationFailureV1.invalidReceipt }; return value
            case let .assessmentScopeSnapshot(_, value, _, _):
                guard value.kind == .assessmentScopeSnapshot else { throw WorkspaceMutationFailureV1.invalidReceipt }; return value
            case let .severityScaleRelease(_, value, _, _):
                guard value.kind == .severityScaleRelease else { throw WorkspaceMutationFailureV1.invalidReceipt }; return value
            case let .findingClassificationBinding(_, value, _, _):
                guard value.kind == .findingClassificationBinding else { throw WorkspaceMutationFailureV1.invalidReceipt }; return value
            case let .measurementProtocolRelease(_, value, _, _):
                guard value.kind == .measurementProtocolRelease else { throw WorkspaceMutationFailureV1.invalidReceipt }; return value
            case let .derivedFactEvaluatorDescriptor(_, value, _, _):
                guard value.kind == .derivedFactEvaluatorDescriptor else { throw WorkspaceMutationFailureV1.invalidReceipt }; return value
            case let .derivedFactProvenance(_, value, _, _):
                guard value.kind == .derivedFactProvenance else { throw WorkspaceMutationFailureV1.invalidReceipt }; return value
            default:
                return try identity
            }
        }
    }

    var revision: UInt64 {
        switch self {
        case let .site(_, value, _), let .asset(_, value, _),
             let .locationNode(_, value, _), let .assetPlacementEvent(_, value, _),
             let .assetCompositionEdge(_, value, _), let .assetCompositionEvent(_, value, _),
             let .savedSmartView(_, value, _),
             let .serviceParty(_, value, _), let .sitePartyRoleEvent(_, value, _),
             let .actorSnapshot(_, value, _), let .qualificationSnapshot(_, value, _),
             let .signoffSnapshot(_, value, _),
             let .authoritySourceRelease(_, _, value, _), let .requirementBasisBinding(_, _, value, _),
             let .applicabilityContextSnapshot(_, _, value, _), let .assessmentScopeSnapshot(_, _, value, _),
             let .severityScaleRelease(_, _, value, _), let .findingClassificationBinding(_, _, value, _),
             let .measurementProtocolRelease(_, _, value, _), let .derivedFactEvaluatorDescriptor(_, _, value, _),
             let .derivedFactProvenance(_, _, value, _),
             let .workflowRecord(_, value, _), let .evidenceFile(_, value, _),
             let .issue(_, value, _), let .packet(_, value, _),
             let .report(_, value, _), let .deletionLedgerEntry(_, value, _),
             let .tombstone(_, value, _): return value
        }
    }
}

struct MutationReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumPostImageCount = 1_024

    let schemaVersion: Int
    let identity: MutationReceiptIdentityV1
    let mutationID: MutationIDV1
    let envelopeSHA256: String
    let commandBodySHA256: String
    let expectedRevision: MutationPortableExpectedRevisionV1
    let resultingRevision: MutationPortableExpectedRevisionV1
    let postImages: [MutationPostImageV1]
    let contentDependencyIDs: [String]
    let resultSHA256: String
    let sourceKind: MutationSourceKindV1
    let causationMutationID: MutationIDV1?
    let correlationID: UUID?
    let reversesMutationID: MutationIDV1?
    let committedAt: Date

    init(
        identity: MutationReceiptIdentityV1,
        envelope: MutationEnvelopeV1,
        resultingRevision: MutationPortableExpectedRevisionV1,
        postImages: [MutationPostImageV1],
        reversesMutationID: MutationIDV1? = nil,
        committedAt: Date
    ) throws {
        guard identity.workspaceID == envelope.workspaceID,
              identity.replicaID == envelope.replicaID else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }
        let ordered = try postImages.sorted { try $0.identity.stableKey < $1.identity.stableKey }
        let result = ResultDigestBasis(resultingRevision: resultingRevision, postImages: ordered)
        schemaVersion = Self.schemaVersion
        self.identity = identity
        mutationID = envelope.mutationID
        envelopeSHA256 = try envelope.canonicalSHA256()
        commandBodySHA256 = envelope.commandBodySHA256
        expectedRevision = envelope.expectedRevision
        self.resultingRevision = resultingRevision
        self.postImages = ordered
        contentDependencyIDs = envelope.contentDependencyIDs
        resultSHA256 = try WorkspaceMutationCanonicalV1.sha256(result)
        sourceKind = envelope.sourceKind
        causationMutationID = envelope.causationMutationID
        correlationID = envelope.correlationID
        self.reversesMutationID = reversesMutationID
        self.committedAt = committedAt
        try validate()
    }

    func validate() throws {
        try expectedRevision.validate()
        try resultingRevision.validate()
        try identity.validate()
        let identities = try postImages.map { try $0.identity }
        let concurrencyIdentities = try postImages.map { try $0.concurrencyIdentity }
        let expectedByIdentity = Dictionary(
            uniqueKeysWithValues: expectedRevision.entityRevisions.map { ($0.identity, $0.revision) }
        )
        let resultingByIdentity = Dictionary(
            uniqueKeysWithValues: resultingRevision.entityRevisions.map { ($0.identity, $0.revision) }
        )
        guard schemaVersion == Self.schemaVersion,
              identity.workspaceID == expectedRevision.workspaceID,
              expectedRevision.workspaceID == resultingRevision.workspaceID,
              expectedRevision.generationID == resultingRevision.generationID,
              expectedRevision.workspaceRevision < .max,
              resultingRevision.workspaceRevision == expectedRevision.workspaceRevision + 1,
              identity.localSequence > 0,
              !postImages.isEmpty,
              postImages.count <= Self.maximumPostImageCount,
              Set(identities).count == identities.count,
              Set(concurrencyIdentities).count == concurrencyIdentities.count,
              identities.map(\.stableKey) == identities.map(\.stableKey).sorted(),
              postImages.allSatisfy({ image in
                  guard let identity = try? image.identity,
                        let concurrencyIdentity = try? image.concurrencyIdentity,
                        let before = expectedByIdentity[concurrencyIdentity],
                        before < .max else { return false }
                  return image.revision == before + 1
                    && resultingByIdentity[identity] == image.revision
              }),
              contentDependencyIDs.count <= MutationEnvelopeV1.maximumDependencyCount,
              contentDependencyIDs == contentDependencyIDs.sorted(),
              Set(contentDependencyIDs).count == contentDependencyIDs.count,
              contentDependencyIDs.allSatisfy(MutationEnvelopeV1.validBoundedToken),
              postImages.allSatisfy({ MutationEnvelopeV1.isSHA256($0.semanticSHA256) }),
              MutationEnvelopeV1.isSHA256(envelopeSHA256),
              MutationEnvelopeV1.isSHA256(commandBodySHA256),
              MutationEnvelopeV1.isSHA256(resultSHA256),
              resultSHA256 == (try WorkspaceMutationCanonicalV1.sha256(
                ResultDigestBasis(resultingRevision: resultingRevision, postImages: postImages)
              )), committedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }
    }

    func canonicalData() throws -> Data { try validate(); return try WorkspaceMutationCanonicalV1.data(self) }
    func canonicalSHA256() throws -> String { try validate(); return try WorkspaceMutationCanonicalV1.sha256(self) }

    static func decodeCanonical(from data: Data) throws -> Self {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(Self.self, from: data)
        try value.validate()
        guard try value.canonicalData() == data else { throw WorkspaceMutationFailureV1.invalidReceipt }
        return value
    }

    private struct ResultDigestBasis: Codable {
        let resultingRevision: MutationPortableExpectedRevisionV1
        let postImages: [MutationPostImageV1]
    }
}

/// A typed C39 receipt envelope around the journal-owned receipt.  The
/// journal remains the only durable receipt writer; this value merely binds
/// the receipt back to the exact preview plan and the single Asset identity.
struct AssetSemanticsChangeReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let planSHA256: String
    let mutationReceipt: MutationReceiptV1
    let mutationReceiptIdentity: MutationReceiptIdentityV1
    let mutationReceiptSHA256: String
    let affectedIdentity: WorkspaceEntityIdentityV1
    let committedAt: Date
    let receiptSHA256: String

    init(
        plan: AssetSemanticsChangePlanV1,
        mutationReceipt: MutationReceiptV1
    ) throws {
        try plan.validate()
        try mutationReceipt.validate()
        let identity = try plan.basis.mutation.affectedIdentity
        let expected = try MutationPortableExpectedRevisionV1(
            plan.basis.expectedRevision
        )
        let expectedByIdentity = Dictionary(
            uniqueKeysWithValues: expected.entityRevisions.map {
                ($0.identity, $0.revision)
            }
        )
        let commandBodySHA256 = try WorkspaceMutationCanonicalV1.sha256(
            WorkspaceCommandV1.applyAssetSemantics(plan.basis.mutation)
        )
        guard mutationReceipt.mutationID == plan.mutationID,
              mutationReceipt.identity.workspaceID == plan.basis.workspaceID,
              mutationReceipt.expectedRevision == expected,
              mutationReceipt.commandBodySHA256 == commandBodySHA256,
              mutationReceipt.sourceKind == .localUser,
              let expectedEntityRevision = expectedByIdentity[identity],
              expected.workspaceRevision < UInt64.max,
              expectedEntityRevision < UInt64.max,
              mutationReceipt.resultingRevision.workspaceRevision
                  == expected.workspaceRevision + 1,
              mutationReceipt.resultingRevision.entityRevisions.contains(
                  where: {
                      $0.identity == identity
                          && $0.revision == expectedEntityRevision + 1
                  }
              ),
              mutationReceipt.postImages.count == 1,
              let postImage = mutationReceipt.postImages.first,
              (try? postImage.identity) == identity,
              postImage.revision == expectedEntityRevision + 1 else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }

        schemaVersion = Self.schemaVersion
        planSHA256 = plan.planSHA256
        self.mutationReceipt = mutationReceipt
        mutationReceiptIdentity = mutationReceipt.identity
        mutationReceiptSHA256 = try mutationReceipt.canonicalSHA256()
        affectedIdentity = identity
        committedAt = mutationReceipt.committedAt
        receiptSHA256 = try WorkspaceMutationCanonicalV1.sha256(
            DigestBasis(
                schemaVersion: Self.schemaVersion,
                planSHA256: plan.planSHA256,
                mutationReceiptIdentity: mutationReceipt.identity,
                mutationReceiptSHA256: mutationReceiptSHA256,
                affectedIdentity: identity,
                committedAt: committedAt
            )
        )
    }

    func validate() throws {
        try mutationReceipt.validate()
        let resultingRevision = mutationReceipt.resultingRevision.entityRevisions
            .first(where: { $0.identity == affectedIdentity })?.revision
        let postImage = mutationReceipt.postImages.first
        guard schemaVersion == Self.schemaVersion,
              MutationEnvelopeV1.isSHA256(planSHA256),
              mutationReceipt.identity == mutationReceiptIdentity,
              mutationReceiptSHA256 == (try mutationReceipt.canonicalSHA256()),
              mutationReceipt.sourceKind == .localUser,
              mutationReceipt.postImages.count == 1,
              let postImage,
              (try? postImage.identity) == affectedIdentity,
              resultingRevision == postImage.revision,
              committedAt == mutationReceipt.committedAt,
              receiptSHA256 == (try WorkspaceMutationCanonicalV1.sha256(
                  DigestBasis(
                      schemaVersion: schemaVersion,
                      planSHA256: planSHA256,
                      mutationReceiptIdentity: mutationReceiptIdentity,
                      mutationReceiptSHA256: mutationReceiptSHA256,
                      affectedIdentity: affectedIdentity,
                      committedAt: committedAt
                  )
              )),
              committedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let planSHA256: String
        let mutationReceiptIdentity: MutationReceiptIdentityV1
        let mutationReceiptSHA256: String
        let affectedIdentity: WorkspaceEntityIdentityV1
        let committedAt: Date
    }
}

extension AuthorityCriterionMutationPayloadV1 {
    var mutationPostImage: MutationPostImageV1 {
        get throws {
            let concurrencyIdentity = try predecessorIdentity ?? affectedIdentity
            switch self {
            case let .appendAuthoritySource(v), let .supersedeAuthoritySource(v):
                .authoritySourceRelease(id: v.releaseID, concurrencyIdentity: concurrencyIdentity, revision: v.revision, semanticSHA256: v.releaseSHA256)
            case let .appendRequirementBasis(v), let .supersedeRequirementBasis(v):
                .requirementBasisBinding(id: v.bindingID, concurrencyIdentity: concurrencyIdentity, revision: v.revision, semanticSHA256: v.bindingSHA256)
            case let .appendApplicabilityContext(v), let .supersedeApplicabilityContext(v):
                .applicabilityContextSnapshot(id: v.snapshotID, concurrencyIdentity: concurrencyIdentity, revision: v.revision, semanticSHA256: v.snapshotSHA256)
            case let .appendAssessmentScope(v), let .supersedeAssessmentScope(v):
                .assessmentScopeSnapshot(id: v.snapshotID, concurrencyIdentity: concurrencyIdentity, revision: v.revision, semanticSHA256: v.snapshotSHA256)
            case let .appendSeverityScale(v), let .supersedeSeverityScale(v):
                .severityScaleRelease(id: v.releaseID, concurrencyIdentity: concurrencyIdentity, revision: v.revision, semanticSHA256: v.releaseSHA256)
            case let .appendFindingClassification(v), let .supersedeFindingClassification(v):
                .findingClassificationBinding(id: v.bindingID, concurrencyIdentity: concurrencyIdentity, revision: v.revision, semanticSHA256: v.bindingSHA256)
            case let .appendMeasurementProtocol(v), let .supersedeMeasurementProtocol(v):
                .measurementProtocolRelease(id: v.releaseID, concurrencyIdentity: concurrencyIdentity, revision: v.revision, semanticSHA256: v.releaseSHA256)
            case let .appendEvaluatorDescriptor(v), let .supersedeEvaluatorDescriptor(v):
                .derivedFactEvaluatorDescriptor(id: v.descriptorID, concurrencyIdentity: concurrencyIdentity, revision: v.revision, semanticSHA256: v.descriptorSHA256)
            case let .appendDerivedFact(v), let .supersedeDerivedFact(v):
                .derivedFactProvenance(id: v.provenanceID, concurrencyIdentity: concurrencyIdentity, revision: v.revision, semanticSHA256: v.provenanceSHA256)
            }
        }
    }
}

/// Typed C40 receipt binding the journal-owned receipt to the exact canonical
/// authority/criterion post-image. It does not introduce a second receipt
/// writer or infer authority meaning from the persisted scalar fields.
struct AuthorityCriterionMutationReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let mutationSHA256: String
    let mutationReceipt: MutationReceiptV1
    let mutationReceiptIdentity: MutationReceiptIdentityV1
    let mutationReceiptSHA256: String
    let affectedIdentity: WorkspaceEntityIdentityV1
    let predecessorIdentity: WorkspaceEntityIdentityV1?
    let concurrencyIdentity: WorkspaceEntityIdentityV1
    let postImageSHA256: String
    let committedAt: Date
    let receiptSHA256: String

    init(
        mutation: AuthorityCriterionMutationV1,
        mutationReceipt: MutationReceiptV1
    ) throws {
        try mutation.validate()
        try mutationReceipt.validate()
        let affectedIdentity = try mutation.affectedIdentity
        let predecessorIdentity = try mutation.postImage.predecessorIdentity
        let concurrencyIdentity = try mutation.concurrencyIdentity
        let commandBodySHA256 = try WorkspaceMutationCanonicalV1.sha256(
            WorkspaceCommandV1.applyAuthorityCriterion(mutation)
        )
        let expectedEntityRevision = mutationReceipt.expectedRevision.entityRevisions
            .first(where: { $0.identity == concurrencyIdentity })?.revision
        let resultingEntityRevision = mutationReceipt.resultingRevision.entityRevisions
            .first(where: { $0.identity == affectedIdentity })?.revision
        let expectedPostImage = try mutation.postImage.mutationPostImage
        guard mutationReceipt.mutationID == mutation.mutationID,
              mutationReceipt.identity.workspaceID == mutation.workspaceID,
              mutationReceipt.commandBodySHA256 == commandBodySHA256,
              mutationReceipt.sourceKind == .localUser,
              expectedEntityRevision == mutation.expectedRevision,
              resultingEntityRevision == mutation.postImage.revision,
              mutationReceipt.postImages == [expectedPostImage] else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }

        schemaVersion = Self.schemaVersion
        mutationSHA256 = try mutation.canonicalSHA256()
        self.mutationReceipt = mutationReceipt
        mutationReceiptIdentity = mutationReceipt.identity
        mutationReceiptSHA256 = try mutationReceipt.canonicalSHA256()
        self.affectedIdentity = affectedIdentity
        self.predecessorIdentity = predecessorIdentity
        self.concurrencyIdentity = concurrencyIdentity
        postImageSHA256 = mutation.postImage.semanticSHA256
        committedAt = mutationReceipt.committedAt
        receiptSHA256 = try WorkspaceMutationCanonicalV1.sha256(
            DigestBasis(
                schemaVersion: Self.schemaVersion,
                mutationSHA256: mutationSHA256,
                mutationReceiptIdentity: mutationReceipt.identity,
                mutationReceiptSHA256: mutationReceiptSHA256,
                affectedIdentity: affectedIdentity,
                predecessorIdentity: predecessorIdentity,
                concurrencyIdentity: concurrencyIdentity,
                postImageSHA256: postImageSHA256,
                committedAt: committedAt
            )
        )
    }

    func validate() throws {
        try mutationReceipt.validate()
        let expectedConcurrencyRevision = mutationReceipt.expectedRevision.entityRevisions
            .first(where: { $0.identity == concurrencyIdentity })?.revision
        let resultingAffectedRevision = mutationReceipt.resultingRevision.entityRevisions
            .first(where: { $0.identity == affectedIdentity })?.revision
        let validRevisionBinding: Bool
        if predecessorIdentity == nil {
            validRevisionBinding = expectedConcurrencyRevision == 0
                && mutationReceipt.postImages.first?.revision == 1
        } else {
            validRevisionBinding = expectedConcurrencyRevision.map {
                $0 > 0 && $0 < UInt64.max
                    && mutationReceipt.postImages.first?.revision == $0 + 1
            } == true
        }
        guard schemaVersion == Self.schemaVersion,
              MutationEnvelopeV1.isSHA256(mutationSHA256),
              mutationReceipt.identity == mutationReceiptIdentity,
              mutationReceiptSHA256 == (try mutationReceipt.canonicalSHA256()),
              mutationReceipt.sourceKind == .localUser,
              mutationReceipt.postImages.count == 1,
              let postImage = mutationReceipt.postImages.first,
              (try? postImage.identity) == affectedIdentity,
              (try? postImage.concurrencyIdentity) == concurrencyIdentity,
              (predecessorIdentity ?? affectedIdentity) == concurrencyIdentity,
              predecessorIdentity.map({ $0 != affectedIdentity }) ?? true,
              validRevisionBinding,
              resultingAffectedRevision == postImage.revision,
              postImage.semanticSHA256 == postImageSHA256,
              MutationEnvelopeV1.isSHA256(postImageSHA256),
              committedAt == mutationReceipt.committedAt,
              receiptSHA256 == (try WorkspaceMutationCanonicalV1.sha256(
                DigestBasis(
                    schemaVersion: schemaVersion,
                    mutationSHA256: mutationSHA256,
                    mutationReceiptIdentity: mutationReceiptIdentity,
                    mutationReceiptSHA256: mutationReceiptSHA256,
                    affectedIdentity: affectedIdentity,
                    predecessorIdentity: predecessorIdentity,
                    concurrencyIdentity: concurrencyIdentity,
                    postImageSHA256: postImageSHA256,
                    committedAt: committedAt
                )
              )),
              committedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw WorkspaceMutationFailureV1.invalidReceipt
        }
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let mutationSHA256: String
        let mutationReceiptIdentity: MutationReceiptIdentityV1
        let mutationReceiptSHA256: String
        let affectedIdentity: WorkspaceEntityIdentityV1
        let predecessorIdentity: WorkspaceEntityIdentityV1?
        let concurrencyIdentity: WorkspaceEntityIdentityV1
        let postImageSHA256: String
        let committedAt: Date
    }
}

struct MutationHistoryReceiptRecordV1: Codable, Equatable, Sendable {
    let envelopeData: Data
    let receiptData: Data
    let reversalBasisData: Data?
    let semanticReversalData: Data?
}

struct MutationHistoryQuarantineRecordV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let mutationID: UUID
    let identityDomain: MutationQuarantineIdentityDomainV1
    let acceptedIdentitySHA256: String
    let conflictingIdentitySHA256: String
    let detectedAt: Date
}

struct MutationHistoryEntityRevisionV1: Codable, Equatable, Sendable {
    let identity: WorkspaceEntityIdentityV1
    let revision: UInt64
    let externalProjectionSHA256: String?

    init(
        identity: WorkspaceEntityIdentityV1,
        revision: UInt64,
        externalProjectionSHA256: String? = nil
    ) {
        self.identity = identity
        self.revision = revision
        self.externalProjectionSHA256 = externalProjectionSHA256
    }
}

struct MutationHistorySnapshotV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceRevision: UInt64
    let lastLocalSequence: UInt64
    let receipts: [MutationHistoryReceiptRecordV1]
    let quarantines: [MutationHistoryQuarantineRecordV1]
    let entityRevisions: [MutationHistoryEntityRevisionV1]

    init(
        workspaceRevision: UInt64,
        lastLocalSequence: UInt64,
        receipts: [MutationHistoryReceiptRecordV1],
        quarantines: [MutationHistoryQuarantineRecordV1],
        entityRevisions: [MutationHistoryEntityRevisionV1]
    ) {
        schemaVersion = Self.schemaVersion
        self.workspaceRevision = workspaceRevision
        self.lastLocalSequence = lastLocalSequence
        self.receipts = receipts
        self.quarantines = quarantines
        self.entityRevisions = entityRevisions
    }
}

enum MutationHistoryRestoreIdentityV1: Equatable, Sendable {
    case preserve
    case destination(WorkspaceReplicaIdentityV1, generationID: UUID)
}

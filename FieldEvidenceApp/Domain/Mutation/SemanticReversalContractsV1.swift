import Foundation

struct SemanticReversalReplayIdentityV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let replicaID: ReplicaID
    let generationID: UUID
    let mutationID: MutationIDV1
    let commandBodySHA256: String
    let expectedRevision: MutationPortableExpectedRevisionV1
    let targetMutationID: MutationIDV1
    let planDigest: String
    let compensatingMutationIDs: [MutationIDV1]

    init(
        request: WorkspaceMutationRequestV1,
        identity: WorkspaceReplicaIdentityV1,
        targetMutationID: MutationIDV1,
        planDigest: String,
        compensatingMutationIDs: [MutationIDV1]
    ) throws {
        try self.init(
            workspaceID: identity.workspaceID,
            replicaID: identity.replicaID,
            generationID: request.expectedRevision.generationID,
            mutationID: request.mutationID,
            commandBodySHA256: WorkspaceMutationCanonicalV1.sha256(request.command),
            expectedRevision: MutationPortableExpectedRevisionV1(request.expectedRevision),
            targetMutationID: targetMutationID,
            planDigest: planDigest,
            compensatingMutationIDs: compensatingMutationIDs
        )
    }

    init(
        workspaceID: WorkspaceID,
        replicaID: ReplicaID,
        generationID: UUID,
        mutationID: MutationIDV1,
        commandBodySHA256: String,
        expectedRevision: MutationPortableExpectedRevisionV1,
        targetMutationID: MutationIDV1,
        planDigest: String,
        compensatingMutationIDs: [MutationIDV1]
    ) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.replicaID = replicaID
        self.generationID = generationID
        self.mutationID = mutationID
        self.commandBodySHA256 = commandBodySHA256
        self.expectedRevision = expectedRevision
        self.targetMutationID = targetMutationID
        self.planDigest = planDigest
        self.compensatingMutationIDs = compensatingMutationIDs
        try validate()
    }

    func validate() throws {
        _ = try WorkspaceReplicaIdentityV1(workspaceID: workspaceID, replicaID: replicaID)
        try expectedRevision.validate()
        guard schemaVersion == Self.schemaVersion,
              generationID == expectedRevision.generationID,
              workspaceID == expectedRevision.workspaceID,
              MutationEnvelopeV1.isSHA256(commandBodySHA256),
              MutationEnvelopeV1.isSHA256(planDigest),
              compensatingMutationIDs.count <= SemanticReversalPlanV1.maximumItems else {
            throw WorkspaceMutationFailureV1.invalidReversal
        }
    }

    func canonicalSHA256() throws -> String {
        try validate()
        return try WorkspaceMutationCanonicalV1.sha256(self)
    }
}

/// A bounded executable commitment for newly recorded first-sign operations.
/// Canonical command bytes and portable authority survive process restart;
/// the process-local writer token is never persisted or exported here.
struct FirstSignCompensationV1: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let targetMutationID: MutationIDV1
    let expectedRevision: MutationPortableExpectedRevisionV1
    let originalCommandSHA256: String
    let assetID: UUID
    let siteID: UUID
    let initialPlacementMutationID: MutationIDV1?
    let initialPlacementEventID: UUID?
    let initialPhysicalEpisodeID: PhysicalPlacementEpisodeIDV1?

    init(request: WorkspaceMutationRequestV1) throws {
        guard case let .createFirstSign(value) = request.command else {
            throw WorkspaceMutationFailureV1.invalidReversal
        }
        schemaVersion = 1
        targetMutationID = request.mutationID
        expectedRevision = try MutationPortableExpectedRevisionV1(request.expectedRevision)
        originalCommandSHA256 = try WorkspaceMutationCanonicalV1.sha256(request.command)
        assetID = value.assetID
        siteID = value.siteID
        initialPlacementMutationID = value.initialPlacementMutationID
        initialPlacementEventID = value.initialPlacementEventID
        initialPhysicalEpisodeID = value.initialPhysicalEpisodeID
        try validate()
    }

    /// The full command remains in its immutable original envelope. This
    /// bounded executable basis joins that real body without copying labels,
    /// package strings, dates, evidence, or process-local writer authority.
    func requireOriginalCommand(_ command: WorkspaceCommandV1) throws -> FirstSignMutationV1 {
        guard case let .createFirstSign(value) = command,
              try WorkspaceMutationCanonicalV1.sha256(command) == originalCommandSHA256,
              value.assetID == assetID, value.siteID == siteID,
              value.initialPlacementMutationID == initialPlacementMutationID,
              value.initialPlacementEventID == initialPlacementEventID,
              value.initialPhysicalEpisodeID == initialPhysicalEpisodeID else {
            throw WorkspaceMutationFailureV1.invalidReversal
        }
        return value
    }

    func validate() throws {
        try expectedRevision.validate()
        _ = try WorkspaceEntityIdentityV1(kind: .asset, id: assetID)
        _ = try WorkspaceEntityIdentityV1(kind: .site, id: siteID)
        guard schemaVersion == 1,
              MutationEnvelopeV1.isSHA256(originalCommandSHA256) else {
            throw WorkspaceMutationFailureV1.invalidReversal
        }
        let placement = [initialPlacementMutationID != nil,
                         initialPlacementEventID != nil,
                         initialPhysicalEpisodeID != nil]
        guard placement.allSatisfy({ $0 }) || placement.allSatisfy({ !$0 }),
              initialPlacementMutationID == nil || initialPlacementMutationID == targetMutationID else {
            throw WorkspaceMutationFailureV1.invalidReversal
        }
    }

    func commitment() throws -> String {
        try validate()
        return try WorkspaceMutationCanonicalV1.sha256(self)
    }

    func compensatingCommand() throws -> WorkspaceCommandV1 {
        try validate()
        return .deleteAsset(.init(deletionID: targetMutationID.rawValue,
                                 assetID: assetID, planDigest: try commitment()))
    }

    func semanticPlan(writerInstanceID: UUID) throws -> SemanticReversalPlanV1 {
        try SemanticReversalPlanV1(firstSignCompensation: self, writerInstanceID: writerInstanceID)
    }

    func semanticPlan(expectedRevision: WorkspaceExpectedRevisionV1) throws -> SemanticReversalPlanV1 {
        try SemanticReversalPlanV1(firstSignCompensation: self,
            writerInstanceID: expectedRevision.writerInstanceID, expectedRevision: expectedRevision)
    }
}

struct ReversalBasisV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let targetMutationID: MutationIDV1
    let targetReceiptIdentity: MutationReceiptIdentityV1
    let policyVersion: Int
    let planDigest: String
    let compensatingCommandKinds: [WorkspaceCommandKindV1]
    /// Nil for the exact historic digest-only schema. Missing promised V2
    /// payloads fail closed; a legacy digest is never used to invent a body.
    let firstSignCompensation: FirstSignCompensationV1?

    init(targetMutationID: MutationIDV1, targetReceiptIdentity: MutationReceiptIdentityV1, plan: SemanticReversalPlanV1) throws {
        guard plan.mutationID == targetMutationID,
              MutationEnvelopeV1.isSHA256(plan.planDigest),
              plan.compensatingCommands.count <= SemanticReversalPlanV1.maximumItems else {
            throw WorkspaceMutationFailureV1.invalidReversal
        }
        firstSignCompensation = plan.firstSignCompensation
        schemaVersion = firstSignCompensation == nil ? Self.schemaVersion : 2
        self.targetMutationID = targetMutationID
        self.targetReceiptIdentity = targetReceiptIdentity
        policyVersion = MutationReversalPolicyRegistryV1.version
        planDigest = plan.planDigest
        compensatingCommandKinds = plan.compensatingCommands.map(\.kind)
        try validate()
    }

    /// Rebinds only the identity-bearing portion of an already validated
    /// historic basis. The archived plan digest is an opaque original
    /// commitment: replacement restore has no plan body from which to invent a
    /// destination plan, so the commitment and command kinds remain exact.
    init(
        rebinding source: ReversalBasisV1,
        targetMutationID: MutationIDV1,
        targetReceiptIdentity: MutationReceiptIdentityV1
    ) throws {
        try source.validate()
        try targetReceiptIdentity.validate()
        schemaVersion = source.schemaVersion
        self.targetMutationID = targetMutationID
        self.targetReceiptIdentity = targetReceiptIdentity
        policyVersion = MutationReversalPolicyRegistryV1.version
        planDigest = source.planDigest
        compensatingCommandKinds = source.compensatingCommandKinds
        firstSignCompensation = source.firstSignCompensation
        try validate()
    }

    func validate() throws {
        try targetReceiptIdentity.validate()
        guard schemaVersion == Self.schemaVersion || schemaVersion == 2,
              policyVersion == MutationReversalPolicyRegistryV1.version,
              MutationEnvelopeV1.isSHA256(planDigest),
              compensatingCommandKinds.count <= SemanticReversalPlanV1.maximumItems else {
            throw WorkspaceMutationFailureV1.invalidReversal
        }
        if schemaVersion == Self.schemaVersion {
            guard firstSignCompensation == nil else { throw WorkspaceMutationFailureV1.invalidReversal }
        } else {
            guard let firstSignCompensation,
                  firstSignCompensation.targetMutationID == targetMutationID,
                  try firstSignCompensation.commitment() == planDigest,
                  compensatingCommandKinds == [.deleteAsset] else {
                throw WorkspaceMutationFailureV1.invalidReversal
            }
        }
    }

    func canonicalData() throws -> Data { try validate(); return try WorkspaceMutationCanonicalV1.data(self) }
    func canonicalSHA256() throws -> String { try validate(); return try WorkspaceMutationCanonicalV1.sha256(self) }
    static func decodeCanonical(from data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate()
        guard try value.canonicalData() == data else { throw WorkspaceMutationFailureV1.invalidReversal }
        return value
    }
}

struct SemanticReversalReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let reversalReceiptIdentity: MutationReceiptIdentityV1
    let reversesMutationID: MutationIDV1
    let targetReceiptIdentity: MutationReceiptIdentityV1
    let reversalBasisSHA256: String
    let planDigest: String
    let compensatingMutationIDs: [MutationIDV1]
    let resultingRevision: MutationPortableExpectedRevisionV1

    init(
        reversalReceiptIdentity: MutationReceiptIdentityV1,
        reversesMutationID: MutationIDV1,
        targetReceiptIdentity: MutationReceiptIdentityV1,
        reversalBasisSHA256: String,
        planDigest: String,
        compensatingMutationIDs: [MutationIDV1],
        resultingRevision: MutationPortableExpectedRevisionV1
    ) throws {
        guard MutationEnvelopeV1.isSHA256(reversalBasisSHA256),
              MutationEnvelopeV1.isSHA256(planDigest),
              compensatingMutationIDs.count <= SemanticReversalPlanV1.maximumItems,
              Set(compensatingMutationIDs).count == compensatingMutationIDs.count else {
            throw WorkspaceMutationFailureV1.invalidReversal
        }
        schemaVersion = Self.schemaVersion
        self.reversalReceiptIdentity = reversalReceiptIdentity
        self.reversesMutationID = reversesMutationID
        self.targetReceiptIdentity = targetReceiptIdentity
        self.reversalBasisSHA256 = reversalBasisSHA256
        self.planDigest = planDigest
        self.compensatingMutationIDs = compensatingMutationIDs
        self.resultingRevision = resultingRevision
        try validate()
    }

    func validate() throws {
        try resultingRevision.validate()
        try reversalReceiptIdentity.validate()
        try targetReceiptIdentity.validate()
        guard schemaVersion == Self.schemaVersion,
              reversalReceiptIdentity.workspaceID == targetReceiptIdentity.workspaceID,
              resultingRevision.workspaceID == reversalReceiptIdentity.workspaceID,
              MutationEnvelopeV1.isSHA256(reversalBasisSHA256),
              MutationEnvelopeV1.isSHA256(planDigest),
              !compensatingMutationIDs.isEmpty,
              compensatingMutationIDs.count <= SemanticReversalPlanV1.maximumItems,
              Set(compensatingMutationIDs).count == compensatingMutationIDs.count else {
            throw WorkspaceMutationFailureV1.invalidReversal
        }
    }

    func canonicalData() throws -> Data { try validate(); return try WorkspaceMutationCanonicalV1.data(self) }
    static func decodeCanonical(from data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate()
        guard try value.canonicalData() == data else { throw WorkspaceMutationFailureV1.invalidReversal }
        return value
    }
}

struct SemanticReversalExecutionV1: Codable, Equatable, Sendable {
    let targetMutationID: MutationIDV1
    let targetReceiptIdentity: MutationReceiptIdentityV1
    let reversalBasisSHA256: String
    let planDigest: String
    let compensatingMutationIDs: [MutationIDV1]

    init(
        targetMutationID: MutationIDV1,
        targetReceiptIdentity: MutationReceiptIdentityV1,
        reversalBasisSHA256: String,
        planDigest: String,
        compensatingMutationIDs: [MutationIDV1]
    ) throws {
        guard MutationEnvelopeV1.isSHA256(reversalBasisSHA256),
              MutationEnvelopeV1.isSHA256(planDigest),
              compensatingMutationIDs.count <= SemanticReversalPlanV1.maximumItems,
              Set(compensatingMutationIDs).count == compensatingMutationIDs.count else {
            throw WorkspaceMutationFailureV1.invalidReversal
        }
        self.targetMutationID = targetMutationID
        self.targetReceiptIdentity = targetReceiptIdentity
        self.reversalBasisSHA256 = reversalBasisSHA256
        self.planDigest = planDigest
        self.compensatingMutationIDs = compensatingMutationIDs
        try validate()
    }

    func validate() throws {
        try targetReceiptIdentity.validate()
        guard MutationEnvelopeV1.isSHA256(reversalBasisSHA256),
              MutationEnvelopeV1.isSHA256(planDigest),
              !compensatingMutationIDs.isEmpty,
              compensatingMutationIDs.count <= SemanticReversalPlanV1.maximumItems,
              Set(compensatingMutationIDs).count == compensatingMutationIDs.count,
              !compensatingMutationIDs.contains(targetMutationID) else {
            throw WorkspaceMutationFailureV1.invalidReversal
        }
    }

}

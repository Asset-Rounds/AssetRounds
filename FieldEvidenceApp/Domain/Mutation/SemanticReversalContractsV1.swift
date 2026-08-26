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

struct ReversalBasisV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let targetMutationID: MutationIDV1
    let targetReceiptIdentity: MutationReceiptIdentityV1
    let policyVersion: Int
    let planDigest: String
    let compensatingCommandKinds: [WorkspaceCommandKindV1]

    init(targetMutationID: MutationIDV1, targetReceiptIdentity: MutationReceiptIdentityV1, plan: SemanticReversalPlanV1) throws {
        guard plan.mutationID == targetMutationID,
              MutationEnvelopeV1.isSHA256(plan.planDigest),
              plan.compensatingCommands.count <= SemanticReversalPlanV1.maximumItems else {
            throw WorkspaceMutationFailureV1.invalidReversal
        }
        schemaVersion = Self.schemaVersion
        self.targetMutationID = targetMutationID
        self.targetReceiptIdentity = targetReceiptIdentity
        policyVersion = MutationReversalPolicyRegistryV1.version
        planDigest = plan.planDigest
        compensatingCommandKinds = plan.compensatingCommands.map(\.kind)
        try validate()
    }

    func validate() throws {
        try targetReceiptIdentity.validate()
        guard schemaVersion == Self.schemaVersion,
              policyVersion == MutationReversalPolicyRegistryV1.version,
              MutationEnvelopeV1.isSHA256(planDigest),
              compensatingCommandKinds.count <= SemanticReversalPlanV1.maximumItems else {
            throw WorkspaceMutationFailureV1.invalidReversal
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

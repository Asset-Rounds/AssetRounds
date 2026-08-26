import Foundation
import SwiftData

@Model
final class MutationReceiptRow {
    var mutationID: UUID
    @Attribute(.unique) var workspaceMutationKey: String
    @Attribute(.unique) var receiptIdentity: String
    var workspaceID: UUID
    var replicaID: UUID
    var localSequence: Int64
    var commandKind: String
    var envelopeData: Data
    var envelopeSHA256: String
    var receiptData: Data
    var receiptSHA256: String
    var reversalBasisData: Data?
    var reversalBasisSHA256: String?
    var semanticReversalData: Data?

    init(
        envelope: MutationEnvelopeV1,
        receipt: MutationReceiptV1,
        reversalBasis: ReversalBasisV1? = nil,
        semanticReversal: SemanticReversalReceiptV1? = nil
    ) throws {
        if let semanticReversal {
            guard semanticReversal.reversalReceiptIdentity == receipt.identity,
                  semanticReversal.resultingRevision == receipt.resultingRevision,
                  semanticReversal.reversesMutationID == receipt.reversesMutationID else {
                throw WorkspaceMutationFailureV1.invalidReversal
            }
        }
        mutationID = envelope.mutationID.rawValue
        workspaceMutationKey = MutationWorkspaceKeyV1.value(
            workspaceID: envelope.workspaceID,
            mutationID: envelope.mutationID
        )
        receiptIdentity = receipt.identity.stableKey
        workspaceID = receipt.identity.workspaceID.rawValue
        replicaID = receipt.identity.replicaID.rawValue
        guard receipt.identity.localSequence <= UInt64(Int64.max) else {
            throw WorkspaceMutationFailureV1.revisionOverflow
        }
        localSequence = Int64(receipt.identity.localSequence)
        commandKind = envelope.commandKind.rawValue
        envelopeData = try envelope.canonicalData()
        envelopeSHA256 = try envelope.canonicalSHA256()
        receiptData = try receipt.canonicalData()
        receiptSHA256 = try receipt.canonicalSHA256()
        if let reversalBasis {
            reversalBasisData = try reversalBasis.canonicalData()
            reversalBasisSHA256 = try reversalBasis.canonicalSHA256()
        } else {
            reversalBasisData = nil
            reversalBasisSHA256 = nil
        }
        semanticReversalData = try semanticReversal?.canonicalData()
    }
}

@Model
final class MutationQuarantineRow {
    var workspaceID: UUID
    var mutationID: UUID
    @Attribute(.unique) var workspaceMutationKey: String
    var identityDomain: String
    var acceptedIdentitySHA256: String
    var conflictingIdentitySHA256: String
    var detectedAt: Date

    init(workspaceID: WorkspaceID, mutationID: MutationIDV1, identityDomain: MutationQuarantineIdentityDomainV1, acceptedIdentitySHA256: String, conflictingIdentitySHA256: String, detectedAt: Date) {
        self.workspaceID = workspaceID.rawValue
        self.workspaceMutationKey = MutationWorkspaceKeyV1.value(
            workspaceID: workspaceID,
            mutationID: mutationID
        )
        self.mutationID = mutationID.rawValue
        self.identityDomain = identityDomain.rawValue
        self.acceptedIdentitySHA256 = acceptedIdentitySHA256
        self.conflictingIdentitySHA256 = conflictingIdentitySHA256
        self.detectedAt = detectedAt
    }
}

@Model
final class WorkspaceMutationStateRow {
    @Attribute(.unique) var workspaceID: UUID
    var generationID: UUID
    var activeReplicaID: UUID
    var workspaceRevision: Int64
    var lastLocalSequence: Int64
    var mutableSemanticSHA256: String?

    init(workspaceID: UUID, generationID: UUID, activeReplicaID: UUID, workspaceRevision: Int64 = 0, lastLocalSequence: Int64 = 0, mutableSemanticSHA256: String? = nil) {
        self.workspaceID = workspaceID
        self.generationID = generationID
        self.activeReplicaID = activeReplicaID
        self.workspaceRevision = workspaceRevision
        self.lastLocalSequence = lastLocalSequence
        self.mutableSemanticSHA256 = mutableSemanticSHA256
    }
}

@Model
final class EntityMutationRevisionRow {
    @Attribute(.unique) var stableIdentity: String
    var kind: String
    var entityID: UUID
    var revision: Int64
    var externalProjectionSHA256: String?

    init(identity: WorkspaceEntityIdentityV1, revision: UInt64, externalProjectionSHA256: String? = nil) {
        stableIdentity = identity.stableKey
        kind = identity.kind.rawValue
        entityID = identity.id
        precondition(revision <= UInt64(Int64.max))
        self.revision = Int64(revision)
        self.externalProjectionSHA256 = externalProjectionSHA256
    }
}

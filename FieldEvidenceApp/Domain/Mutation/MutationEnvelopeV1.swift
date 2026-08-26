import Foundation

enum MutationSourceKindV1: String, Codable, CaseIterable, Sendable {
    case localUser = "LOCAL_USER"
    case localRecovery = "LOCAL_RECOVERY"
    case importedHistory = "IMPORTED_HISTORY"
    case semanticReversal = "SEMANTIC_REVERSAL"
}

struct MutationPortableExpectedRevisionV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let generationID: UUID
    let workspaceRevision: UInt64
    let entityRevisions: [WorkspaceEntityRevisionV1]

    init(_ value: WorkspaceExpectedRevisionV1) throws {
        workspaceID = value.workspaceID
        generationID = value.generationID
        workspaceRevision = value.workspaceRevision
        entityRevisions = value.entityRevisions.sorted { $0.identity.stableKey < $1.identity.stableKey }
        try validate()
    }

    func validate() throws {
        guard generationID != Self.zero,
              Set(entityRevisions.map(\.identity)).count == entityRevisions.count,
              entityRevisions.map(\.identity.stableKey)
                == entityRevisions.map(\.identity.stableKey).sorted() else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    private static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

/// Portable canonical mutation input. The process-local writer instance token
/// is deliberately absent so a restart can recognize an identical request.
struct MutationEnvelopeV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumDependencyCount = 256

    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let replicaID: ReplicaID
    let generationID: UUID
    let mutationID: MutationIDV1
    let commandKind: WorkspaceCommandKindV1
    let command: WorkspaceCommandV1
    let expectedRevision: MutationPortableExpectedRevisionV1
    let contentDependencyIDs: [String]
    let sourceKind: MutationSourceKindV1
    let causationMutationID: MutationIDV1?
    let correlationID: UUID?
    let reversalPlanDigest: String?
    let semanticReversalReplayIdentitySHA256: String?
    let semanticReversalExecution: SemanticReversalExecutionV1?
    let commandBodySHA256: String

    init(
        request: WorkspaceMutationRequestV1,
        identity: WorkspaceReplicaIdentityV1,
        sourceKind: MutationSourceKindV1 = .localUser,
        contentDependencyIDs: [String] = [],
        causationMutationID: MutationIDV1? = nil,
        correlationID: UUID? = nil,
        reversalPlanDigest: String? = nil,
        semanticReversalReplayIdentitySHA256: String? = nil,
        semanticReversalExecution: SemanticReversalExecutionV1? = nil
    ) throws {
        let dependencies = contentDependencyIDs.sorted()
        guard request.expectedRevision.workspaceID == identity.workspaceID,
              dependencies.count <= Self.maximumDependencyCount,
              Set(dependencies).count == dependencies.count,
              dependencies.allSatisfy({ Self.validBoundedToken($0) }),
              correlationID != Self.zero else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        schemaVersion = Self.schemaVersion
        workspaceID = identity.workspaceID
        replicaID = identity.replicaID
        generationID = request.expectedRevision.generationID
        mutationID = request.mutationID
        commandKind = request.command.kind
        command = request.command
        expectedRevision = try MutationPortableExpectedRevisionV1(request.expectedRevision)
        self.contentDependencyIDs = dependencies
        self.sourceKind = sourceKind
        self.causationMutationID = causationMutationID
        self.correlationID = correlationID
        self.reversalPlanDigest = reversalPlanDigest
        self.semanticReversalReplayIdentitySHA256 = semanticReversalReplayIdentitySHA256
        self.semanticReversalExecution = semanticReversalExecution
        commandBodySHA256 = try WorkspaceMutationCanonicalV1.sha256(request.command)
        try validate()
    }

    func validate() throws {
        try expectedRevision.validate()
        try semanticReversalExecution?.validate()
        guard (try? WorkspaceReplicaIdentityV1(
            workspaceID: workspaceID,
            replicaID: replicaID
        )) != nil else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        let expectedSemanticReplayDigest: String?
        if let execution = semanticReversalExecution {
            expectedSemanticReplayDigest = try SemanticReversalReplayIdentityV1(
                workspaceID: workspaceID,
                replicaID: replicaID,
                generationID: generationID,
                mutationID: mutationID,
                commandBodySHA256: commandBodySHA256,
                expectedRevision: expectedRevision,
                targetMutationID: execution.targetMutationID,
                planDigest: execution.planDigest,
                compensatingMutationIDs: execution.compensatingMutationIDs
            ).canonicalSHA256()
        } else {
            expectedSemanticReplayDigest = nil
        }
        guard schemaVersion == Self.schemaVersion,
              commandKind == command.kind,
              workspaceID == expectedRevision.workspaceID,
              generationID == expectedRevision.generationID,
              generationID != Self.zero,
              contentDependencyIDs.count <= Self.maximumDependencyCount,
              contentDependencyIDs == contentDependencyIDs.sorted(),
              Set(contentDependencyIDs).count == contentDependencyIDs.count,
              contentDependencyIDs.allSatisfy({ Self.validBoundedToken($0) }),
              Self.isSHA256(commandBodySHA256),
              reversalPlanDigest.map(Self.isSHA256) ?? true,
              semanticReversalReplayIdentitySHA256.map(Self.isSHA256) ?? true,
              !(reversalPlanDigest != nil && semanticReversalExecution != nil),
              (semanticReversalExecution != nil) == (semanticReversalReplayIdentitySHA256 != nil),
              semanticReversalReplayIdentitySHA256 == expectedSemanticReplayDigest,
              commandBodySHA256 == (try WorkspaceMutationCanonicalV1.sha256(command)),
              (sourceKind == .semanticReversal) == (causationMutationID != nil),
              (sourceKind == .semanticReversal) == (semanticReversalExecution != nil),
              semanticReversalExecution?.targetMutationID == causationMutationID,
              semanticReversalExecution?.targetReceiptIdentity.workspaceID == workspaceID,
              causationMutationID != mutationID,
              correlationID != Self.zero else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
    }

    func canonicalData() throws -> Data {
        try validate()
        return try WorkspaceMutationCanonicalV1.data(self)
    }

    func canonicalSHA256() throws -> String {
        try validate()
        return try WorkspaceMutationCanonicalV1.sha256(self)
    }

    static func decodeCanonical(from data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(Self.self, from: data)
        try value.validate()
        guard try value.canonicalData() == data else {
            throw WorkspaceMutationFailureV1.invalidCommand
        }
        return value
    }

    private static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    static func validBoundedToken(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 512 && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

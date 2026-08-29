import Foundation

enum ActivityContractCoordinatorFailureV2: Error, Equatable, Sendable {
    case targetMissing
    case staleExpectedRevision
    case invalidFamily
    case durableReceiptMissing
    case durableReceiptMismatch
}

enum ActivityContractAcceptanceFamilyV2: String, Codable, CaseIterable, Hashable, Sendable {
    case shared = "SHARED"
    case installation = "INSTALLATION"
    case punch = "PUNCH"
}

enum ActivityContractAcceptancePayloadV2: Equatable, Sendable {
    case shared(receipt: SharedActivityEnvelopeReceiptV1)
    case installation(receipt: SharedActivityEnvelopeReceiptV1,
                      contractSHA256: String,
                      noPlanFallback: NoPlanFallbackV1)
    case punch(receipt: SharedActivityEnvelopeReceiptV1,
               contractSHA256: String,
               noPlanFallback: NoPlanFallbackV1)

    var family: ActivityContractAcceptanceFamilyV2 {
        switch self {
        case .shared: return .shared
        case .installation: return .installation
        case .punch: return .punch
        }
    }

    var sharedReceipt: SharedActivityEnvelopeReceiptV1 {
        switch self {
        case let .shared(receipt), let .installation(receipt, _, _), let .punch(receipt, _, _):
            return receipt
        }
    }

    var independentFamilyContractSHA256: String? {
        switch self {
        case .shared: return nil
        case let .installation(_, digest, _), let .punch(_, digest, _): return digest
        }
    }

    var noPlanFallback: NoPlanFallbackV1? {
        switch self {
        case .shared: return nil
        case let .installation(_, _, fallback), let .punch(_, _, fallback): return fallback
        }
    }
}

struct ActivityContractCurrentStateV2: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let activityID: UUID
    let expectedRevision: WorkspaceExpectedRevisionV1
    let envelope: ActivitySessionEnvelopeV2?

    init(workspaceID: WorkspaceID, activityID: UUID,
         expectedRevision: WorkspaceExpectedRevisionV1,
         envelope: ActivitySessionEnvelopeV2?) throws {
        guard expectedRevision.workspaceID == workspaceID,
              envelope.map({ $0.workspaceID == workspaceID && $0.activityID == activityID }) ?? true else {
            throw ActivityContractCoordinatorFailureV2.targetMissing
        }
        let targetIdentity = try WorkspaceEntityIdentityV1(
            kind: .activitySessionEnvelope, id: activityID
        )
        var entityRevisions = expectedRevision.entityRevisions
        if envelope == nil,
           !entityRevisions.contains(where: { $0.identity == targetIdentity }) {
            entityRevisions.append(WorkspaceEntityRevisionV1(
                identity: targetIdentity, revision: 0
            ))
        }
        self.workspaceID = workspaceID
        self.activityID = activityID
        self.expectedRevision = try WorkspaceExpectedRevisionV1(
            workspaceID: expectedRevision.workspaceID,
            generationID: expectedRevision.generationID,
            writerInstanceID: expectedRevision.writerInstanceID,
            workspaceRevision: expectedRevision.workspaceRevision,
            entityRevisions: entityRevisions
        )
        self.envelope = envelope
    }
}

@MainActor
protocol ActivityContractCurrentStateQueryingV2: AnyObject {
    func currentActivityContract(workspaceID: WorkspaceID, activityID: UUID) async throws
        -> ActivityContractCurrentStateV2?
}

@MainActor
protocol ActivityContractCanonicalWorkspaceWritingV2: AnyObject {
    func commitActivityContract(_ mutation: ActivityContractMutationV2) async throws -> MutationReceiptV1
    func durableActivityContractReceipt(workspaceID: WorkspaceID, mutationID: MutationIDV1) async throws
        -> MutationReceiptV1?
}

@MainActor
protocol ActivityContractBundledReleaseSelectingV2: AnyObject {
    func bundledRelease(kind: ActivityKindV2,
                        use: ActivityWorkflowReleaseUseV2,
                        workspaceID: WorkspaceID) throws -> BundledActivityWorkflowReleaseV2
}

enum ActivityContractRouteCodecConsumerV2 {
    static func encode(_ route: ActivityRouteV2) throws -> Data {
        try ActivityRouteCanonicalRegistryV2.encode(route)
    }

    static func decode(_ data: Data) throws -> ActivityRouteV2 {
        try ActivityRouteCanonicalRegistryV2.decode(data)
    }

    static let delegatesCanonicalRouteCodec = true
    static let retainsCanonicalRouteBounds = true
    static let definesNoParallelRouteEncoding = true
}

struct ActivityContractAcceptanceRequestV2: Equatable, Sendable {
    let payload: ActivityContractAcceptancePayloadV2
    let mutation: ActivityContractMutationV2

    var family: ActivityContractAcceptanceFamilyV2 { payload.family }
    var sharedReceipt: SharedActivityEnvelopeReceiptV1 { payload.sharedReceipt }
    var independentFamilyContractSHA256: String? { payload.independentFamilyContractSHA256 }
    var noPlanFallback: NoPlanFallbackV1? { payload.noPlanFallback }

    init(payload: ActivityContractAcceptancePayloadV2,
         mutation: ActivityContractMutationV2) throws {
        try Self.validate(payload: payload, mutation: mutation)
        self.payload = payload
        self.mutation = mutation
    }

    init(family: ActivityContractAcceptanceFamilyV2, mutation: ActivityContractMutationV2,
         sharedReceipt: SharedActivityEnvelopeReceiptV1,
         independentFamilyContractSHA256: String? = nil,
         noPlanFallback: NoPlanFallbackV1? = nil) throws {
        let payload: ActivityContractAcceptancePayloadV2
        switch family {
        case .shared:
            guard independentFamilyContractSHA256 == nil, noPlanFallback == nil else {
                throw ActivityContractCoordinatorFailureV2.invalidFamily
            }
            payload = .shared(receipt: sharedReceipt)
        case .installation:
            guard let independentFamilyContractSHA256, let noPlanFallback else {
                throw ActivityContractCoordinatorFailureV2.invalidFamily
            }
            payload = .installation(receipt: sharedReceipt,
                                    contractSHA256: independentFamilyContractSHA256,
                                    noPlanFallback: noPlanFallback)
        case .punch:
            guard let independentFamilyContractSHA256, let noPlanFallback else {
                throw ActivityContractCoordinatorFailureV2.invalidFamily
            }
            payload = .punch(receipt: sharedReceipt,
                             contractSHA256: independentFamilyContractSHA256,
                             noPlanFallback: noPlanFallback)
        }
        try Self.validate(payload: payload, mutation: mutation)
        self.payload = payload
        self.mutation = mutation
    }

    private static func validate(payload: ActivityContractAcceptancePayloadV2,
                                 mutation: ActivityContractMutationV2) throws {
        try mutation.validate()
        try payload.sharedReceipt.validate()
        let hasInstallationPayload = mutation.installationBasisSnapshot != nil
            || !mutation.installationTaskResults.isEmpty
            || mutation.installationAsBuiltSnapshot != nil
            || mutation.successorEnvelope.installationCloseout != nil
        let hasPunchPayload = mutation.punchReviewBasisSnapshot != nil
            || mutation.successorEnvelope.punchReviewCloseout != nil
        switch payload {
        case .shared:
            guard !hasInstallationPayload, !hasPunchPayload else {
                throw ActivityContractCoordinatorFailureV2.invalidFamily
            }
        case let .installation(_, digest, fallback):
            guard mutation.successorEnvelope.kind == .installation,
                  hasInstallationPayload, !hasPunchPayload,
                  KernelCanonicalHashV1.validSHA256(digest) else {
                throw ActivityContractCoordinatorFailureV2.invalidFamily
            }
            try fallback.validate()
        case let .punch(_, digest, fallback):
            guard mutation.successorEnvelope.kind == .punchReview,
                  hasPunchPayload, !hasInstallationPayload,
                  KernelCanonicalHashV1.validSHA256(digest) else {
                throw ActivityContractCoordinatorFailureV2.invalidFamily
            }
            try fallback.validate()
        }
    }
}

enum ActivityContractConformanceReceiptV2: Equatable, Sendable {
    case shared(SharedActivityEnvelopeReceiptV1)
    case installation(InstallationActivityContractReceiptV1)
    case punch(PunchActivityContractReceiptV1)
}

/// Immutable C47 contract identity supplied by the package/release authority.
/// It is intentionally independent of an activity, its basis, or its current
/// revision: activity instances carry recorded facts, never contract identity.
struct ActivityContractConformanceAuthorityV2: Equatable, Sendable {
    let sharedReceipt: SharedActivityEnvelopeReceiptV1
    let installationContractSHA256: String
    let punchContractSHA256: String
    let noPlanFallback: NoPlanFallbackV1

    init(sharedReceipt: SharedActivityEnvelopeReceiptV1,
         installationContractSHA256: String,
         punchContractSHA256: String,
         noPlanFallback: NoPlanFallbackV1) throws {
        try sharedReceipt.validate()
        try noPlanFallback.validate()
        guard KernelCanonicalHashV1.validSHA256(installationContractSHA256),
              KernelCanonicalHashV1.validSHA256(punchContractSHA256) else {
            throw ActivityContractCoordinatorFailureV2.invalidFamily
        }
        self.sharedReceipt = sharedReceipt
        self.installationContractSHA256 = installationContractSHA256
        self.punchContractSHA256 = punchContractSHA256
        self.noPlanFallback = noPlanFallback
    }

    func validate(_ payload: ActivityContractAcceptancePayloadV2) throws {
        switch payload {
        case let .shared(receipt):
            guard receipt == sharedReceipt else {
                throw ActivityContractCoordinatorFailureV2.invalidFamily
            }
        case let .installation(receipt, contractSHA256, fallback):
            guard receipt == sharedReceipt,
                  contractSHA256 == installationContractSHA256,
                  fallback == noPlanFallback else {
                throw ActivityContractCoordinatorFailureV2.invalidFamily
            }
        case let .punch(receipt, contractSHA256, fallback):
            guard receipt == sharedReceipt,
                  contractSHA256 == punchContractSHA256,
                  fallback == noPlanFallback else {
                throw ActivityContractCoordinatorFailureV2.invalidFamily
            }
        }
    }

    func receipt(for family: ActivityContractAcceptanceFamilyV2)
        throws -> ActivityContractConformanceReceiptV2 {
        switch family {
        case .shared:
            return .shared(sharedReceipt)
        case .installation:
            return .installation(try InstallationActivityContractReceiptV1(
                sharedContractSHA256: sharedReceipt.sharedContractSHA256,
                installationContractSHA256: installationContractSHA256,
                noPlanFallbackSHA256: noPlanFallback.fallbackSHA256
            ))
        case .punch:
            return .punch(try PunchActivityContractReceiptV1(
                sharedContractSHA256: sharedReceipt.sharedContractSHA256,
                punchContractSHA256: punchContractSHA256,
                noPlanFallbackSHA256: noPlanFallback.fallbackSHA256
            ))
        }
    }
}

struct ActivityContractAcceptanceResultV2: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let activityID: UUID
    let expectedRevision: WorkspaceExpectedRevisionV1
    let mutationID: MutationIDV1
    let durableReceipt: MutationReceiptV1
    let receipt: ActivityContractConformanceReceiptV2
}

@MainActor
final class ActivityContractCoordinatorV2 {
    private let query: any ActivityContractCurrentStateQueryingV2
    private let writer: any ActivityContractCanonicalWorkspaceWritingV2
    private let conformanceAuthority: ActivityContractConformanceAuthorityV2

    init(query: any ActivityContractCurrentStateQueryingV2,
         writer: any ActivityContractCanonicalWorkspaceWritingV2,
         conformanceAuthority: ActivityContractConformanceAuthorityV2) {
        self.query = query
        self.writer = writer
        self.conformanceAuthority = conformanceAuthority
    }

    func accept(_ request: ActivityContractAcceptanceRequestV2) async throws
        -> ActivityContractAcceptanceResultV2 {
        let mutation = request.mutation
        try mutation.validate()
        try mutation.successorEnvelope.kind.requireKnownForMutation()
        try conformanceAuthority.validate(request.payload)
        let proposedReceipt = try conformanceAuthority.receipt(for: request.family)
        if let durable = try await writer.durableActivityContractReceipt(
            workspaceID: mutation.workspaceID, mutationID: mutation.mutationID
        ) {
            let idempotent = try await writer.commitActivityContract(mutation)
            guard durable == idempotent else {
                throw ActivityContractCoordinatorFailureV2.durableReceiptMismatch
            }
            return result(for: request, durableReceipt: durable, receipt: proposedReceipt)
        }
        guard let current = try await query.currentActivityContract(
            workspaceID: mutation.workspaceID,
            activityID: mutation.successorEnvelope.activityID
        ) else { throw ActivityContractCoordinatorFailureV2.targetMissing }
        guard current.expectedRevision == mutation.expectedRevision,
              current.envelope == mutation.predecessorEnvelope else {
            throw ActivityContractCoordinatorFailureV2.staleExpectedRevision
        }

        let committed = try await writer.commitActivityContract(mutation)
        guard let durable = try await writer.durableActivityContractReceipt(
            workspaceID: mutation.workspaceID,
            mutationID: mutation.mutationID
        ) else { throw ActivityContractCoordinatorFailureV2.durableReceiptMissing }
        guard durable == committed else { throw ActivityContractCoordinatorFailureV2.durableReceiptMismatch }

        return result(for: request, durableReceipt: durable, receipt: proposedReceipt)
    }

    private func result(for request: ActivityContractAcceptanceRequestV2,
                        durableReceipt: MutationReceiptV1,
                        receipt: ActivityContractConformanceReceiptV2)
        -> ActivityContractAcceptanceResultV2 {
        let mutation = request.mutation
        return .init(workspaceID: mutation.workspaceID,
                     activityID: mutation.successorEnvelope.activityID,
                     expectedRevision: mutation.expectedRevision,
                     mutationID: mutation.mutationID,
                     durableReceipt: durableReceipt,
                     receipt: receipt)
    }
}

enum C47ActivityContractCoordinatorBoundaryV2 {
    static let usesSoleWorkspaceWriter = true
    static let conformanceReceiptsAreNonpersistent = true
    static let installationAndPunchRequireAcceptedSharedReceipt = true
    static let sharedAcceptanceRejectsIndependentFamilyPayload = true
    static let independentAcceptanceRequiresExactlyItsFamilyPayload = true
    static let acceptancePayloadIsClosedAndTyped = true
    static let closeoutFieldsParticipateInFamilyIsolation = true
    static let conformanceReceiptMatchesCommittedFamilySlice = true
    static let activityInstanceDigestIsNotSharedContractIdentity = true
    static let unknownKindsAreReadExportOnly = true
    static let noPlanFallbackIsComplete = true
    static let noP04ScreenScanRouteOrInspectionAlias = true
}

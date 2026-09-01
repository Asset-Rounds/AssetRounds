import Foundation

/// Existing canonical-writer bridge. A conformer performs the target field
/// mutation, journal append, and AssistanceAcceptanceReceiptRow insertion in
/// one idempotent effect-before-receipt recovery path. It is not a second store.
@MainActor
protocol AssistanceCanonicalWorkspaceWritingV1: AnyObject {
    func commitAssistanceAcceptance(
        _ request: AssistanceAcceptanceRequestV1
    ) throws -> AssistanceAcceptanceReceiptV1
    func acceptedAssistanceReceipt(
        mutationID: MutationIDV1
    ) throws -> AssistanceAcceptanceReceiptV1?
}

/// Deletes only capability-owned leased scratch. Immutable canonical sources
/// are references and are never deleted when a proposal is removed.
@MainActor
protocol AssistanceScratchDiscardingV1: AnyObject {
    func discardAssistanceScratch(
        proposalID: UUID,
        source: AssistanceSourceReferenceV1
    ) async throws
    func discardOrphanedAssistanceScratch(
        retainingProposalIDs: Set<UUID>
    ) async throws

    func finishAssistanceScratch(
        proposalID: UUID,
        source: AssistanceSourceReferenceV1,
        disposition: ScratchPublicationDispositionV1,
        immutableContentReceiptDigest: String?
    ) async throws
    func transferAssistanceScratch(
        fromProposalID:UUID,toProposalID:UUID,source:AssistanceSourceReferenceV1
    ) async throws
}

@MainActor
protocol AssistanceCurrentSourceReadingV1: AnyObject {
    func currentSource(
        proposalID: UUID,
        expected: AssistanceSourceReferenceV1
    ) throws -> AssistanceSourceReferenceV1?
}

extension AssistanceScratchDiscardingV1 {
    func finishAssistanceScratch(
        proposalID: UUID,
        source: AssistanceSourceReferenceV1,
        disposition: ScratchPublicationDispositionV1,
        immutableContentReceiptDigest: String?
    ) async throws {
        try await discardAssistanceScratch(proposalID: proposalID, source: source)
    }

    func transferAssistanceScratch(
        fromProposalID:UUID,toProposalID:UUID,source:AssistanceSourceReferenceV1
    ) async throws {
        throw AssistanceContractFailureV1.scratchCleanupFailed
    }
}

/// Trusted application-owned projection of the current workspace, capability,
/// release, source, and clock state. Callers may supply a snapshot for review
/// continuity, but the lifecycle accepts it only when this resolver agrees.
@MainActor
protocol AssistanceCurrentStateResolvingV1: AnyObject {
    func obtainReviewSnapshot(
        for proposal: AssistanceProposalV1
    ) async throws -> AssistanceProposalEvaluationContextV1

    func currentEvaluationContext(
        proposalID: UUID,
        capability: AssistanceCapabilityReferenceV1,
        target: AssistanceTargetV1,
        source: AssistanceSourceReferenceV1
    ) async throws -> AssistanceProposalEvaluationContextV1
}

/// One atomic read of canonical state plus the trusted clock. Production
/// readers assemble this from the workspace writer/query projection, released
/// feature policy, current package/definition bindings, and source authority.
struct AssistanceAuthoritativeStateV1: Equatable, Sendable {
    let workspaceRevision: WorkspaceRevisionV1
    let policy: AssistanceCapabilityPolicyV1
    let packageReleaseSHA256: String?
    let definitionReleaseSHA256: String?
    let currentSource: AssistanceSourceReferenceV1?
    let evaluatedAt: Date

    init(
        workspaceRevision: WorkspaceRevisionV1,
        policy: AssistanceCapabilityPolicyV1,
        packageReleaseSHA256: String?,
        definitionReleaseSHA256: String?,
        currentSource: AssistanceSourceReferenceV1?,
        evaluatedAt: Date
    ) throws {
        self.workspaceRevision = try WorkspaceRevisionV1(
            workspaceID: workspaceRevision.workspaceID,
            generationID: workspaceRevision.generationID,
            writerInstanceID: workspaceRevision.writerInstanceID,
            revision: workspaceRevision.revision,
            entityRevisions: workspaceRevision.entityRevisions
        )
        self.policy = policy
        self.packageReleaseSHA256 = packageReleaseSHA256
        self.definitionReleaseSHA256 = definitionReleaseSHA256
        self.currentSource = currentSource
        self.evaluatedAt = evaluatedAt
        try policy.validate()
        try packageReleaseSHA256.map(AssistanceLimitsV1.digest)
        try definitionReleaseSHA256.map(AssistanceLimitsV1.digest)
        try currentSource?.validate()
        try AssistanceLimitsV1.instant(evaluatedAt)
    }

    fileprivate func sameAuthority(as other: Self) -> Bool {
        workspaceRevision == other.workspaceRevision
            && policy == other.policy
            && packageReleaseSHA256 == other.packageReleaseSHA256
            && definitionReleaseSHA256 == other.definitionReleaseSHA256
            && currentSource == other.currentSource
    }
}

@MainActor
protocol AssistanceAuthoritativeStateReadingV1: AnyObject {
    func readCurrentAssistanceState(
        proposalID: UUID,
        capability: AssistanceCapabilityReferenceV1,
        target: AssistanceTargetV1,
        source: AssistanceSourceReferenceV1
    ) async throws -> AssistanceAuthoritativeStateV1
}

/// Production resolver with bounded, memory-only review snapshots. A cached
/// timestamp remains stable through present/review/accept, but every operation
/// still re-reads canonical authority and invalidates the snapshot on change or
/// timeout. No capture runtime or durable proposal store is introduced.
@MainActor
final class AssistanceTrustedSnapshotAuthorityV1: AssistanceCurrentStateResolvingV1 {
    private struct Entry {
        let proposal: AssistanceProposalV1
        let state: AssistanceAuthoritativeStateV1
        let context: AssistanceProposalEvaluationContextV1
    }

    private let reader: any AssistanceAuthoritativeStateReadingV1
    private var entries: [UUID: Entry] = [:]
    private var order: [UUID] = []

    init(reader: any AssistanceAuthoritativeStateReadingV1) {
        self.reader = reader
    }

    func obtainReviewSnapshot(
        for proposal: AssistanceProposalV1
    ) async throws -> AssistanceProposalEvaluationContextV1 {
        try proposal.validate()
        let state = try await readState(
            proposalID: proposal.proposalID,
            capability: proposal.capability,
            target: proposal.target,
            source: proposal.source
        )
        let context = try makeContext(proposal: proposal, state: state)
        if entries[proposal.proposalID] == nil {
            order.append(proposal.proposalID)
        }
        entries[proposal.proposalID] = Entry(
            proposal: proposal,
            state: state,
            context: context
        )
        while order.count > AssistanceLimitsV1.maximumActiveProposals {
            entries.removeValue(forKey: order.removeFirst())
        }
        return context
    }

    func currentEvaluationContext(
        proposalID: UUID,
        capability: AssistanceCapabilityReferenceV1,
        target: AssistanceTargetV1,
        source: AssistanceSourceReferenceV1
    ) async throws -> AssistanceProposalEvaluationContextV1 {
        guard let entry = entries[proposalID],
              entry.proposal.capability == capability,
              entry.proposal.target == target,
              entry.proposal.source == source else {
            throw AssistanceContractFailureV1.staleTarget
        }
        let state = try await readState(
            proposalID: proposalID,
            capability: capability,
            target: target,
            source: source
        )
        guard state.evaluatedAt >= entry.state.evaluatedAt else {
            throw AssistanceContractFailureV1.staleTarget
        }
        if state.sameAuthority(as: entry.state), state.evaluatedAt < entry.proposal.expiresAt {
            return entry.context
        }
        return try makeContext(proposal: entry.proposal, state: state)
    }

    private func readState(
        proposalID: UUID,
        capability: AssistanceCapabilityReferenceV1,
        target: AssistanceTargetV1,
        source: AssistanceSourceReferenceV1
    ) async throws -> AssistanceAuthoritativeStateV1 {
        let state = try await reader.readCurrentAssistanceState(
            proposalID: proposalID,
            capability: capability,
            target: target,
            source: source
        )
        guard state.workspaceRevision.workspaceID == target.workspaceID,
              state.policy.capability.capabilityID == capability.capabilityID else {
            throw AssistanceContractFailureV1.staleTarget
        }
        return state
    }

    private func makeContext(
        proposal: AssistanceProposalV1,
        state: AssistanceAuthoritativeStateV1
    ) throws -> AssistanceProposalEvaluationContextV1 {
        guard let targetRevision = state.workspaceRevision.entityRevisions
            .first(where: { $0.identity == proposal.target.entity })?.revision else {
            throw AssistanceContractFailureV1.staleTarget
        }
        let context = AssistanceProposalEvaluationContextV1(
            workspaceID: state.workspaceRevision.workspaceID,
            targetRevision: targetRevision,
            policy: state.policy,
            packageReleaseSHA256: state.packageReleaseSHA256,
            definitionReleaseSHA256: state.definitionReleaseSHA256,
            currentSource: state.currentSource,
            evaluatedAt: state.evaluatedAt
        )
        try context.validate()
        return context
    }
}

/// Bounded, memory-only linkage between an assistance proposal and a scratch
/// lease owned by the existing capability scratch authority. Recovery delegates
/// to that authority; this adapter never creates a second scratch store.
@MainActor
final class AssistanceCapabilityScratchLifecycleAdapterV1:
    AssistanceScratchDiscardingV1,
    AssistanceCurrentSourceReadingV1
{
    private struct Binding: Equatable {
        let source: AssistanceSourceReferenceV1
        let lease: CapabilityScratchLeaseV1
    }

    private let leases: any CapabilityScratchLeasePortV1
    private var bindings: [UUID: Binding] = [:]

    init(leases: any CapabilityScratchLeasePortV1) {
        self.leases = leases
    }

    func currentSource(
        proposalID: UUID,
        expected: AssistanceSourceReferenceV1
    ) throws -> AssistanceSourceReferenceV1? {
        try expected.validate()
        guard expected.kind == .leasedScratch else {
            throw AssistanceContractFailureV1.invalidValue
        }
        return bindings[proposalID]?.source
    }

    func acquireAndBind(
        proposalID: UUID,
        source: AssistanceSourceReferenceV1,
        request: CapabilityScratchLeaseRequestV1
    ) async throws -> CapabilityScratchLeaseV1 {
        let linkage = try AssistanceCapabilityScratchV1(
            proposalID: proposalID,
            source: source
        )
        guard request.operationID == proposalID,
              request.leaseID.uuidString.lowercased() == source.sourceID else {
            throw AssistanceContractFailureV1.invalidValue
        }
        guard bindings[proposalID] == nil else {
            throw AssistanceContractFailureV1.duplicateProposal
        }
        guard bindings.count < AssistanceLimitsV1.maximumActiveProposals else {
            throw AssistanceContractFailureV1.limitExceeded
        }
        let lease = try await leases.acquire(request)
        do {
            try bind(linkage, lease: lease, request: request)
            return lease
        } catch {
            _ = try? await leases.finish(
                lease: lease,
                disposition: .failed,
                immutableContentReceiptDigest: nil
            )
            throw error
        }
    }

    func bind(
        _ linkage: AssistanceCapabilityScratchV1,
        lease: CapabilityScratchLeaseV1,
        request: CapabilityScratchLeaseRequestV1
    ) throws {
        guard request.operationID == linkage.proposalID,
              request.leaseID == lease.leaseID,
              request.purpose == lease.purpose,
              lease.leaseID.uuidString.lowercased() == linkage.source.sourceID else {
            throw AssistanceContractFailureV1.invalidValue
        }
        let binding = Binding(source: linkage.source, lease: lease)
        if let existing = bindings[linkage.proposalID] {
            guard existing == binding else {
                throw AssistanceContractFailureV1.duplicateProposal
            }
            return
        }
        guard bindings.count < AssistanceLimitsV1.maximumActiveProposals else {
            throw AssistanceContractFailureV1.limitExceeded
        }
        bindings[linkage.proposalID] = binding
    }

    func discardAssistanceScratch(
        proposalID: UUID,
        source: AssistanceSourceReferenceV1
    ) async throws {
        try await finishAssistanceScratch(
            proposalID: proposalID,
            source: source,
            disposition: .cancelled,
            immutableContentReceiptDigest: nil
        )
    }

    func transferAssistanceScratch(
        fromProposalID:UUID,toProposalID:UUID,source:AssistanceSourceReferenceV1
    ) async throws {
        try AssistanceLimitsV1.id(fromProposalID);try AssistanceLimitsV1.id(toProposalID);try source.validate()
        if bindings[fromProposalID] == nil,let existing=bindings[toProposalID],existing.source==source{return}
        guard fromProposalID != toProposalID,bindings[toProposalID] == nil,
              let binding=bindings[fromProposalID],binding.source==source else{
            throw AssistanceContractFailureV1.scratchCleanupFailed
        }
        bindings[toProposalID]=binding
        bindings.removeValue(forKey:fromProposalID)
    }

    func finishAssistanceScratch(
        proposalID: UUID,
        source: AssistanceSourceReferenceV1,
        disposition: ScratchPublicationDispositionV1,
        immutableContentReceiptDigest: String?
    ) async throws {
        guard let binding = bindings[proposalID], binding.source == source else {
            throw AssistanceContractFailureV1.scratchCleanupFailed
        }
        _ = try await leases.finish(
            lease: binding.lease,
            disposition: disposition,
            immutableContentReceiptDigest: immutableContentReceiptDigest
        )
        bindings.removeValue(forKey: proposalID)
    }

    func discardOrphanedAssistanceScratch(
        retainingProposalIDs: Set<UUID>
    ) async throws {
        guard retainingProposalIDs.isEmpty, bindings.isEmpty else {
            throw AssistanceContractFailureV1.scratchCleanupFailed
        }
        _ = try await leases.recoverAfterInterruption()
        bindings.removeAll(keepingCapacity: true)
    }
}

@MainActor
final class AssistanceLifecycleAdapterV1: AssistanceProposalLifecycleV1 {
    private let writer: any AssistanceCanonicalWorkspaceWritingV1
    private let scratch: any AssistanceScratchDiscardingV1
    private let currentState: any AssistanceCurrentStateResolvingV1
    private var proposals: [UUID: AssistanceProposalV1] = [:]
    private var terminalRemovals: [UUID: AssistanceRemovalDispositionV1] = [:]

    init(
        writer: any AssistanceCanonicalWorkspaceWritingV1,
        scratch: any AssistanceScratchDiscardingV1,
        currentState: any AssistanceCurrentStateResolvingV1
    ) {
        self.writer = writer
        self.scratch = scratch
        self.currentState = currentState
    }

    func obtainReviewSnapshot(
        for proposal: AssistanceProposalV1
    ) async throws -> AssistanceProposalEvaluationContextV1 {
        try proposal.validate()
        return try await currentState.obtainReviewSnapshot(for: proposal)
    }

    func present(
        _ proposal: AssistanceProposalV1,
        context: AssistanceProposalEvaluationContextV1
    ) async throws {
        try proposal.validate()
        try context.validate()
        let trustedContext = try await resolvedContext(for: proposal, supplied: context)
        if let reason = try proposal.expiryReason(in: trustedContext) {
            if let prior = terminalRemovals[proposal.proposalID] {
                guard prior.kind == .expired, prior.expiryReason == reason else {
                    throw AssistanceContractFailureV1.duplicateProposal
                }
                throw AssistanceContractFailureV1.expired(reason)
            }
            if proposal.source.kind == .leasedScratch {
                do {
                    try await scratch.finishAssistanceScratch(
                        proposalID: proposal.proposalID,
                        source: proposal.source,
                        disposition: .expired,
                        immutableContentReceiptDigest: nil
                    )
                } catch {
                    throw AssistanceContractFailureV1.scratchCleanupFailed
                }
            }
            recordTerminalRemoval(try AssistanceRemovalDispositionV1(
                proposalID: proposal.proposalID,
                kind: .expired,
                expiryReason: reason
            ))
            throw AssistanceContractFailureV1.expired(reason)
        }
        if let existing = proposals[proposal.proposalID] {
            guard existing == proposal else {
                throw AssistanceContractFailureV1.duplicateProposal
            }
            return
        }
        guard terminalRemovals[proposal.proposalID] == nil else {
            throw AssistanceContractFailureV1.duplicateProposal
        }
        guard proposals.count < AssistanceLimitsV1.maximumActiveProposals else {
            throw AssistanceContractFailureV1.limitExceeded
        }
        proposals[proposal.proposalID] = proposal
    }

    func replaceForReview(originalProposalID:UUID,with corrected:AssistanceProposalV1,
                          context:AssistanceProposalEvaluationContextV1)async throws{
        try AssistanceLimitsV1.id(originalProposalID);try corrected.validate();try context.validate()
        if proposals[originalProposalID] == nil,
           let existing=proposals[corrected.proposalID],existing==corrected{return}
        guard let original=proposals[originalProposalID],originalProposalID != corrected.proposalID,
              proposals[corrected.proposalID] == nil,terminalRemovals[corrected.proposalID] == nil,
              original.capability==corrected.capability,original.target==corrected.target,
              original.source==corrected.source,original.privacyClass==corrected.privacyClass,
              corrected.createdAt>=original.createdAt,corrected.expiresAt==original.expiresAt else{
            throw AssistanceContractFailureV1.duplicateProposal
        }
        let trusted=try await resolvedContext(for:original,supplied:context)
        guard try corrected.expiryReason(in:trusted)==nil else{throw AssistanceContractFailureV1.staleTarget}
        if original.source.kind == .leasedScratch{
            try await scratch.transferAssistanceScratch(fromProposalID:originalProposalID,
                toProposalID:corrected.proposalID,source:original.source)
        }
        proposals.removeValue(forKey:originalProposalID)
        proposals[corrected.proposalID]=corrected
    }

    func proposal(proposalID: UUID) async -> AssistanceProposalV1? {
        proposals[proposalID]
    }

    func activeProposals(workspaceID: WorkspaceID) async -> [AssistanceProposalV1] {
        proposals.values
            .filter { $0.target.workspaceID == workspaceID }
            .sorted {
                ($0.createdAt, $0.proposalID.uuidString)
                    < ($1.createdAt, $1.proposalID.uuidString)
            }
    }

    func review(
        proposalID: UUID,
        context: AssistanceProposalEvaluationContextV1
    ) async throws -> AssistanceReviewDecisionV1 {
        guard let proposal = proposals[proposalID] else {
            throw AssistanceContractFailureV1.proposalNotFound
        }
        let trustedContext = try await resolvedContext(for: proposal, supplied: context)
        if let reason = try proposal.expiryReason(in: trustedContext) {
            let removal = try await remove(
                proposalID: proposalID,
                kind: .expired,
                expiryReason: reason
            )
            return .expired(.init(proposalID: proposalID, reason: reason, removal: removal))
        }
        try trustedContext.policy.validateMetadata(for: proposal)
        return .ready(proposal)
    }

    func accept(
        proposalID: UUID,
        targetMutation: AssistanceCanonicalTargetMutationV1,
        expectedRevision: WorkspaceExpectedRevisionV1,
        mutationID: MutationIDV1,
        acceptedBy: ActorSnapshotV1,
        acceptedAt: Date,
        context: AssistanceProposalEvaluationContextV1
    ) async throws -> AssistanceAcceptanceReceiptV1 {
        guard let proposal = proposals[proposalID] else {
            if let recovered = try writer.acceptedAssistanceReceipt(mutationID: mutationID) {
                try recovered.validate()
                let trustedContext: AssistanceProposalEvaluationContextV1
                do {
                    trustedContext = try await resolvedContext(
                        proposalID: recovered.proposalID,
                        capability: recovered.capability,
                        target: recovered.target,
                        source: recovered.source,
                        supplied: context
                    )
                } catch {
                    throw AssistanceContractFailureV1.invalidReceipt
                }
                let concurrency = try targetMutation.concurrencyIdentities
                let expected = expectedRevision.entityRevisions
                guard recovered.proposalID == proposalID,
                      recovered.workspaceID == expectedRevision.workspaceID,
                      recovered.workspaceID == trustedContext.workspaceID,
                      recovered.mutationID == mutationID,
                      recovered.expectedRevision == expectedRevision,
                      recovered.targetMutationSHA256 == (try targetMutation.mutationSHA256),
                      recovered.acceptedBy == acceptedBy,
                      recovered.acceptedAt == acceptedAt,
                      targetMutation.workspaceID == recovered.workspaceID,
                      targetMutation.mutationID == mutationID,
                      Set(concurrency) == Set(expected.map(\.identity)),
                      concurrency.allSatisfy({ identity in
                          expected.first(where: { $0.identity == identity })?.revision
                            == (try? targetMutation.expectedRevision(for: identity))
                      }) else {
                    throw AssistanceContractFailureV1.invalidReceipt
                }
                return recovered
            }
            throw AssistanceContractFailureV1.proposalNotFound
        }
        let trustedContext = try await resolvedContext(for: proposal, supplied: context)
        if let reason = try proposal.expiryReason(in: trustedContext) {
            _ = try await remove(proposalID: proposalID, kind: .expired, expiryReason: reason)
            throw AssistanceContractFailureV1.expired(reason)
        }
        guard acceptedAt == trustedContext.evaluatedAt else {
            throw AssistanceContractFailureV1.staleTarget
        }
        try trustedContext.policy.validateMetadata(for: proposal)
        let request = try AssistanceAcceptanceRequestV1(
            proposal: proposal,
            targetMutation: targetMutation,
            expectedRevision: expectedRevision,
            mutationID: mutationID,
            acceptedBy: acceptedBy,
            acceptedAt: acceptedAt
        )
        let receipt: AssistanceAcceptanceReceiptV1
        if let existing = try writer.acceptedAssistanceReceipt(mutationID: mutationID) {
            try existing.validate(request: request)
            receipt = existing
        } else {
            let committed = try writer.commitAssistanceAcceptance(request)
            try committed.validate(request: request)
            receipt = committed
        }
        _ = try await remove(
            proposalID: proposalID,
            kind: .accepted,
            expiryReason: nil,
            immutableContentReceiptDigest: receipt.receiptSHA256
        )
        return receipt
    }

    func remove(
        proposalID: UUID,
        kind: AssistanceRemovalKindV1,
        expiryReason: AssistanceProposalExpiryReasonV1?
    ) async throws -> AssistanceRemovalDispositionV1 {
        guard kind != .accepted else {
            throw AssistanceContractFailureV1.invalidValue
        }
        if kind == .expired {
            if let proposal = proposals[proposalID] {
                guard let expiryReason else {
                    throw AssistanceContractFailureV1.invalidValue
                }
                let trustedContext = try await resolvedContext(for: proposal)
                guard try proposal.expiryReason(in: trustedContext) == expiryReason else {
                    throw AssistanceContractFailureV1.staleTarget
                }
            }
        }
        try await remove(
            proposalID: proposalID,
            kind: kind,
            expiryReason: expiryReason,
            immutableContentReceiptDigest: nil
        )
    }

    private func remove(
        proposalID: UUID,
        kind: AssistanceRemovalKindV1,
        expiryReason: AssistanceProposalExpiryReasonV1?,
        immutableContentReceiptDigest: String?
    ) async throws -> AssistanceRemovalDispositionV1 {
        guard let proposal = proposals[proposalID] else {
            if let prior = terminalRemovals[proposalID] {
                guard prior.kind == kind, prior.expiryReason == expiryReason else {
                    throw AssistanceContractFailureV1.duplicateProposal
                }
                return prior
            }
            throw AssistanceContractFailureV1.proposalNotFound
        }
        let disposition = try AssistanceRemovalDispositionV1(
            proposalID: proposalID,
            kind: kind,
            expiryReason: expiryReason
        )
        if proposal.source.kind == .leasedScratch {
            do {
                let disposition: ScratchPublicationDispositionV1
                switch kind {
                case .accepted: disposition = .acceptedIntoImmutableContent
                case .rejected: disposition = .rejected
                case .cancelled: disposition = .cancelled
                case .expired: disposition = .expired
                }
                try await scratch.finishAssistanceScratch(
                    proposalID: proposalID,
                    source: proposal.source,
                    disposition: disposition,
                    immutableContentReceiptDigest: immutableContentReceiptDigest
                )
            } catch {
                throw AssistanceContractFailureV1.scratchCleanupFailed
            }
        }
        proposals.removeValue(forKey: proposalID)
        recordTerminalRemoval(disposition)
        return disposition
    }

    private func recordTerminalRemoval(
        _ disposition: AssistanceRemovalDispositionV1
    ) {
        if terminalRemovals.count == AssistanceLimitsV1.maximumTerminalRemovals,
           let oldest = terminalRemovals.keys.sorted(by: { $0.uuidString < $1.uuidString }).first {
            terminalRemovals.removeValue(forKey: oldest)
        }
        terminalRemovals[disposition.proposalID] = disposition
    }

    func expireAll(
        contextByProposal: [UUID: AssistanceProposalEvaluationContextV1]
    ) async throws -> [AssistanceExpiryDispositionV1] {
        var result: [AssistanceExpiryDispositionV1] = []
        for proposalID in proposals.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let proposal = proposals[proposalID],
                  let supplied = contextByProposal[proposalID] else {
                throw AssistanceContractFailureV1.staleTarget
            }
            let trustedContext = try await resolvedContext(for: proposal, supplied: supplied)
            guard let reason = try proposal.expiryReason(in: trustedContext) else { continue }
            let removal = try await remove(
                proposalID: proposalID,
                kind: .expired,
                expiryReason: reason
            )
            result.append(.init(proposalID: proposalID, reason: reason, removal: removal))
        }
        return result
    }

    private func resolvedContext(
        for proposal: AssistanceProposalV1,
        supplied: AssistanceProposalEvaluationContextV1? = nil
    ) async throws -> AssistanceProposalEvaluationContextV1 {
        let trusted = try await resolvedContext(
            proposalID: proposal.proposalID,
            capability: proposal.capability,
            target: proposal.target,
            source: proposal.source,
            supplied: nil
        )
        guard trusted.evaluatedAt >= proposal.createdAt else {
            throw AssistanceContractFailureV1.staleTarget
        }
        if let supplied {
            try supplied.validate()
        }
        if let supplied, supplied != trusted {
            guard try proposal.expiryReason(in: trusted) != nil else {
                throw AssistanceContractFailureV1.staleTarget
            }
        }
        return trusted
    }

    private func resolvedContext(
        proposalID: UUID,
        capability: AssistanceCapabilityReferenceV1,
        target: AssistanceTargetV1,
        source: AssistanceSourceReferenceV1,
        supplied: AssistanceProposalEvaluationContextV1?
    ) async throws -> AssistanceProposalEvaluationContextV1 {
        let trusted = try await currentState.currentEvaluationContext(
            proposalID: proposalID,
            capability: capability,
            target: target,
            source: source
        )
        try trusted.validate()
        if let supplied {
            try supplied.validate()
            guard supplied == trusted else {
                throw AssistanceContractFailureV1.staleTarget
            }
        }
        return trusted
    }

    func recoverAfterInterruption() async throws {
        do {
            try await scratch.discardOrphanedAssistanceScratch(
                retainingProposalIDs: Set(proposals.keys)
            )
        } catch {
            throw AssistanceContractFailureV1.scratchCleanupFailed
        }
    }
}

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Infrastructure_Assistance_AssistanceLifecycleAdapterV1_swift {
    static let durableFamilyCount = TemporalEvidencePersistenceEnrollmentV1.durableModelCount
    static func validate(clip: TemporalEvidenceClipV1,
                         anchor: TimecodedEvidenceAnchorV1) throws {
        try clip.validateIntrinsic()
        try anchor.validate(clip: clip)
        guard durableFamilyCount == 2 else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
    }
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row181 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}
enum C46OperationalContactConformance_FieldEvidenceApp_Infrastructure_Assistance_AssistanceLifecycleAdapterV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noContactProjectionOrNetworkDelivery = true
}

enum OCRProposalAssistanceLifecycleBoundaryV1 {
    static let proposalsAreEphemeral = true
    static let acceptedReceiptUsesExistingWriter = true
    static let rejectionDeletesOwnedScratch = true
    static let cancellationDeletesOwnedScratch = true
    static let expiryDeletesOwnedScratch = true
    static let deletionIsIdempotent = true
    static let latestTargetFallbackAllowed = false
    static func validateAccepted(_ receipt: AssistanceAcceptanceReceiptV1,
                                 evidence: OCRProposalEvidenceV1) throws {
        try receipt.validate(ocrEvidence: evidence)
    }
}

enum DictationLocationAssistanceLifecycleBoundaryV1{
    static let proposalsAreEphemeral=true
    static let acceptedReceiptUsesExistingWriter=true
    static let acceptedReceiptBindsExpectedRevisionAndMutationID=true
    static let rejectionCancellationInterruptionDeleteTemporaryAudio=true
    static let latestTargetFallbackAllowed=false
    static let backgroundLocationAllowed=false
    static let productionAdoptionEnabled=false
    static func validateAccepted(_ receipt:AssistanceAcceptanceReceiptV1,
                                 dictation:OnDeviceDictationProposalV1)throws{
        try receipt.validate(dictation:dictation)
    }
    static func validateAccepted(_ receipt:AssistanceAcceptanceReceiptV1,
                                 location:OneShotLocationProposalV1)throws{
        try receipt.validate(location:location)
    }
}

// MARK: - C52 lifecycle and privacy boundary
enum C52ServiceRequestBoundary_FieldEvidenceApp_Infrastructure_Assistance_AssistanceLifecycleAdapterV1_swift {
    static let acceptedCanonicalRecordPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let acceptedEventPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let duplicateProjectionPersistence: ServiceRequestPersistenceClassV1 = .nonpersistentDerived
    static let rawCapabilityPersistence: ServiceRequestPersistenceClassV1 = .prohibitedPersistent
    static let acceptedLifecycleEnrollment: ServiceRequestPersistenceEnrollmentV1.Type = ServiceRequestPersistenceEnrollmentV1.self
    static let cloneOrForkInvalidatesActiveCapabilities: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.cloneOrForkInvalidatesOutstandingCapabilities
    static let duplicateProjectionIsRebuildable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.derivedProjectionIsRebuildable &&
        !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityIsExcludedFromReportsAndDiagnostics: Bool =
        !ServiceRequestLifecycleRegistrationBoundaryV1.rawCapabilityAppearsInReportsOrDiagnostics
    static let sharedPortableFilesAreRecallable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.escapedPortableFilesCanBeRecalled
    static let unverifiedAssertionsAreVerified: Bool = false
    static let automaticWorkNetworkSLAOrAIClaimsPermitted: Bool = false
}

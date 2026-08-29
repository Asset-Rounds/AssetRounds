import Foundation
import SwiftData

enum MutationJournalFaultBoundaryV1: String, CaseIterable, Equatable, Sendable {
    case afterEffectBeforeReceipt
    case afterReceiptBeforeSave
    case afterSaveBeforeReturn
}

enum MutationJournalFailureV1: Error, Equatable {
    case injected(MutationJournalFaultBoundaryV1)
}

@MainActor
final class MutationJournalFailureInjectionV1 {
    private var pending: MutationJournalFaultBoundaryV1?
    init(failOnceAt boundary: MutationJournalFaultBoundaryV1) { pending = boundary }
    func reach(_ boundary: MutationJournalFaultBoundaryV1) throws {
        guard pending == boundary else { return }
        pending = nil
        throw MutationJournalFailureV1.injected(boundary)
    }
}

@MainActor
final class MutationJournalStoreV1 {
    nonisolated static let maximumReceiptValidationCount = 100_000
    nonisolated static let maximumMutableContentValidationCount = 100_000

    private enum AccessMode {
        case canonicalWriter(StaleWriterFenceV1)
        case maintenanceOrTest
    }

    private let modelContext: ModelContext
    private let identity: WorkspaceReplicaIdentityV1
    private let generationID: UUID
    private let failureInjection: MutationJournalFailureInjectionV1?
    private let accessMode: AccessMode

    convenience init(
        modelContext: ModelContext,
        identity: WorkspaceReplicaIdentityV1,
        generationID: UUID,
        failureInjection: MutationJournalFailureInjectionV1? = nil,
        allowStateBootstrap: Bool = true,
        staleWriterFence: StaleWriterFenceV1
    ) throws {
        let writerLeaseToken: GenerationLeaseTokenV1 =
            staleWriterFence.writerLeaseToken
        guard staleWriterFence.expectedGenerationEpoch.generationID == generationID,
              writerLeaseToken.epoch == staleWriterFence.expectedGenerationEpoch,
              writerLeaseToken.role == .writer else {
            throw WorkspaceMutationFailureV1.wrongGeneration
        }
        try self.init(
            modelContext: modelContext,
            identity: identity,
            generationID: generationID,
            failureInjection: failureInjection,
            allowStateBootstrap: allowStateBootstrap,
            accessMode: .canonicalWriter(staleWriterFence)
        )
    }

    /// Legacy maintenance/read access. Canonical writer and recovery entry
    /// points reject this mode in release builds; DEBUG retains the existing
    /// isolated in-memory test seam.
    convenience init(
        modelContext: ModelContext,
        identity: WorkspaceReplicaIdentityV1,
        generationID: UUID,
        failureInjection: MutationJournalFailureInjectionV1? = nil,
        allowStateBootstrap: Bool = true
    ) throws {
        try self.init(
            modelContext: modelContext,
            identity: identity,
            generationID: generationID,
            failureInjection: failureInjection,
            allowStateBootstrap: allowStateBootstrap,
            accessMode: .maintenanceOrTest
        )
    }

    private init(
        modelContext: ModelContext,
        identity: WorkspaceReplicaIdentityV1,
        generationID: UUID,
        failureInjection: MutationJournalFailureInjectionV1?,
        allowStateBootstrap: Bool,
        accessMode: AccessMode
    ) throws {
        self.modelContext = modelContext
        self.identity = identity
        self.generationID = generationID
        self.failureInjection = failureInjection
        self.accessMode = accessMode
        try bootstrapOrValidateState(allowBootstrap: allowStateBootstrap)
    }

    func reach(_ boundary: MutationJournalFaultBoundaryV1) throws {
        try failureInjection?.reach(boundary)
    }

    func currentRevision(writerInstanceID: UUID) throws -> WorkspaceRevisionV1 {
        try validateCurrentWriterLease()
        let state = try requireState()
        let rows = try modelContext.fetch(FetchDescriptor<EntityMutationRevisionRow>(
            sortBy: [SortDescriptor(\.stableIdentity)]
        ))
        let revisions = try rows.map { row -> WorkspaceEntityRevisionV1 in
            guard let kind = WorkspaceEntityKindV1(rawValue: row.kind) else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            return WorkspaceEntityRevisionV1(
                identity: try WorkspaceEntityIdentityV1(kind: kind, id: row.entityID),
                revision: try domainRevision(row.revision)
            )
        }
        return try WorkspaceRevisionV1(
            workspaceID: identity.workspaceID,
            generationID: generationID,
            writerInstanceID: writerInstanceID,
            revision: try domainRevision(state.workspaceRevision),
            entityRevisions: revisions
        )
    }

    func nextLocalSequence() throws -> UInt64 {
        try validateCurrentWriterLease()
        let value = try requireState().lastLocalSequence
        guard value >= 0, value < Int64.max else { throw WorkspaceMutationFailureV1.revisionOverflow }
        return UInt64(value + 1)
    }

    /// Returns the prior immutable receipt before live-session revision checks.
    /// A conflicting body is durably quarantined and always fails closed.
    func resolveReplay(envelope: MutationEnvelopeV1, detectedAt: Date) throws -> MutationReceiptV1? {
        try validateCurrentWriterLease()
        try envelope.validate()
        guard envelope.workspaceID == identity.workspaceID,
              envelope.generationID == generationID else {
            throw WorkspaceMutationFailureV1.wrongGeneration
        }
        let workspaceKey = MutationWorkspaceKeyV1.value(
            workspaceID: envelope.workspaceID,
            mutationID: envelope.mutationID
        )
        if try !modelContext.fetch(FetchDescriptor<MutationQuarantineRow>(
            predicate: #Predicate { $0.workspaceMutationKey == workspaceKey }
        )).isEmpty {
            throw WorkspaceMutationFailureV1.mutationIDQuarantined
        }
        let rows = try modelContext.fetch(FetchDescriptor<MutationReceiptRow>(
            predicate: #Predicate { $0.workspaceMutationKey == workspaceKey }
        ))
        guard rows.count <= 1 else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
        guard let row = rows.first else { return nil }
        let incoming = try envelope.canonicalSHA256()
        guard row.envelopeSHA256 == incoming else {
            modelContext.insert(MutationQuarantineRow(
                workspaceID: envelope.workspaceID,
                mutationID: envelope.mutationID,
                identityDomain: .mutationEnvelope,
                acceptedIdentitySHA256: row.envelopeSHA256,
                conflictingIdentitySHA256: incoming,
                detectedAt: detectedAt
            ))
            do {
                try saveWithStaleWriterFence()
            } catch let failure as WorkspaceMutationFailureV1 {
                modelContext.rollback()
                throw failure
            } catch {
                modelContext.rollback()
                throw WorkspaceMutationFailureV1.persistenceFailed
            }
            throw WorkspaceMutationFailureV1.mutationIDQuarantined
        }
        return try validate(row: row, expectedEnvelope: envelope)
    }

    /// Probes durable replay before semantic-reversal target/plan validation.
    /// A first-time invalid request has no row and is not quarantined; reuse of
    /// an accepted mutation ID with a changed bounded replay tuple is durable.
    func resolveSemanticReversalReplay(
        request: WorkspaceMutationRequestV1,
        replayIdentitySHA256: String,
        detectedAt: Date
    ) throws -> MutationReceiptV1? {
        try validateCurrentWriterLease()
        guard request.expectedRevision.workspaceID == identity.workspaceID,
              request.expectedRevision.generationID == generationID,
              MutationEnvelopeV1.isSHA256(replayIdentitySHA256) else {
            throw WorkspaceMutationFailureV1.invalidReversal
        }
        let workspaceKey = MutationWorkspaceKeyV1.value(
            workspaceID: identity.workspaceID,
            mutationID: request.mutationID
        )
        if try !modelContext.fetch(FetchDescriptor<MutationQuarantineRow>(
            predicate: #Predicate { $0.workspaceMutationKey == workspaceKey }
        )).isEmpty {
            throw WorkspaceMutationFailureV1.mutationIDQuarantined
        }
        let rows = try modelContext.fetch(FetchDescriptor<MutationReceiptRow>(
            predicate: #Predicate { $0.workspaceMutationKey == workspaceKey }
        ))
        guard rows.count <= 1 else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
        guard let row = rows.first else { return nil }
        let receipt = try validate(row: row, expectedEnvelope: nil)
        let accepted = try MutationEnvelopeV1.decodeCanonical(from: row.envelopeData)
        guard let acceptedReplayIdentity = accepted.semanticReversalReplayIdentitySHA256 else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        guard acceptedReplayIdentity == replayIdentitySHA256 else {
            modelContext.insert(MutationQuarantineRow(
                workspaceID: identity.workspaceID,
                mutationID: request.mutationID,
                identityDomain: .semanticReversalReplayIdentity,
                acceptedIdentitySHA256: acceptedReplayIdentity,
                conflictingIdentitySHA256: replayIdentitySHA256,
                detectedAt: detectedAt
            ))
            do {
                try saveWithStaleWriterFence()
            } catch let failure as WorkspaceMutationFailureV1 {
                modelContext.rollback()
                throw failure
            } catch {
                modelContext.rollback()
                throw WorkspaceMutationFailureV1.persistenceFailed
            }
            throw WorkspaceMutationFailureV1.mutationIDQuarantined
        }
        try validateAll()
        return receipt
    }

    func commit(
        envelope: MutationEnvelopeV1,
        writerInstanceID: UUID,
        affectedEntities: [WorkspaceEntityIdentityV1],
        committedAt: Date,
        reversalBasis: ReversalBasisV1? = nil,
        semanticReversal: SemanticReversalReceiptV1? = nil,
        semanticReversalExecution: SemanticReversalExecutionV1? = nil
    ) throws -> MutationReceiptV1 {
        do {
            return try withStaleWriterFence {
                try commitAfterFence(
                    envelope: envelope,
                    writerInstanceID: writerInstanceID,
                    affectedEntities: affectedEntities,
                    committedAt: committedAt,
                    reversalBasis: reversalBasis,
                    semanticReversal: semanticReversal,
                    semanticReversalExecution: semanticReversalExecution
                )
            }
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func commitAfterFence(
        envelope: MutationEnvelopeV1,
        writerInstanceID: UUID,
        affectedEntities: [WorkspaceEntityIdentityV1],
        committedAt: Date,
        reversalBasis: ReversalBasisV1? = nil,
        semanticReversal: SemanticReversalReceiptV1? = nil,
        semanticReversalExecution: SemanticReversalExecutionV1? = nil
    ) throws -> MutationReceiptV1 {
        guard envelope.workspaceID == identity.workspaceID,
              envelope.replicaID == identity.replicaID,
              envelope.generationID == generationID else {
            throw WorkspaceMutationFailureV1.wrongGeneration
        }
        do {
            _ = try ObservationAndTimeRowStoreV1.validatedIndex(in: modelContext)
        } catch {
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
        guard semanticReversal == nil || semanticReversalExecution == nil else {
            throw WorkspaceMutationFailureV1.invalidReversal
        }
        if let execution = semanticReversalExecution {
            guard envelope.semanticReversalExecution == execution,
                  envelope.sourceKind == .semanticReversal,
                  envelope.causationMutationID == execution.targetMutationID,
                  let target = try receipt(mutationID: execution.targetMutationID),
                  target.identity == execution.targetReceiptIdentity,
                  let basis = try reversalBasis(mutationID: execution.targetMutationID),
                  execution.reversalBasisSHA256 == (try basis.canonicalSHA256()),
                  execution.planDigest == basis.planDigest,
                  basis.compensatingCommandKinds == [envelope.commandKind] else {
                throw WorkspaceMutationFailureV1.invalidReversal
            }
        }
        guard reversalBasis.map(\.planDigest) == envelope.reversalPlanDigest else {
            throw WorkspaceMutationFailureV1.invalidReversal
        }
        if case let .applyAssetSemantics(value) = envelope.command {
            do {
                try value.validate()
                guard affectedEntities == [try value.affectedIdentity] else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            } catch let failure as WorkspaceMutationFailureV1 {
                throw failure
            } catch {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        }
        if case let .applyAuthorityCriterion(value) = envelope.command {
            do {
                try value.validate()
                guard affectedEntities == [try value.affectedIdentity] else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            } catch let failure as WorkspaceMutationFailureV1 { throw failure }
            catch { throw WorkspaceMutationFailureV1.invalidCommand }
        }
        if case let .applyFunctionalRelationship(value) = envelope.command {
            do {
                try value.validate()
                guard affectedEntities == [try value.affectedIdentity] else {
                    throw WorkspaceMutationFailureV1.invalidCommand
                }
            } catch let failure as WorkspaceMutationFailureV1 { throw failure }
            catch { throw WorkspaceMutationFailureV1.invalidCommand }
        }
        if case let .applyEvidenceAssurance(value)=envelope.command{try value.validate();guard affectedEntities==[try value.affectedIdentity]else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyInspectionReview(value)=envelope.command{try value.validate();guard affectedEntities==(try value.affectedIdentities) else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyWorkPacket(value)=envelope.command{try value.validate();guard affectedEntities==[try value.affectedIdentity]else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyFieldDraft(value)=envelope.command{try value.validate();guard affectedEntities==(try value.affectedIdentities)else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyPackagePromotion(value)=envelope.command{try value.validate();guard affectedEntities==(try value.affectedIdentities)else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyMeasurementIntegrity(value)=envelope.command{try value.validate();guard affectedEntities==(try value.affectedIdentities)else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyPrivacyTransform(value)=envelope.command{try value.validate();guard affectedEntities==(try value.affectedIdentities)else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyClientCapability(value)=envelope.command{try value.validate();guard affectedEntities==[try value.affectedIdentity]else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyFieldReference(value)=envelope.command{try value.validate();guard affectedEntities==[try value.affectedIdentity]else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyAccessibleDocumentAssessment(value)=envelope.command{try value.validate();guard affectedEntities==[try value.affectedIdentity]else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applySurveyDefinition(value)=envelope.command{try value.validate();guard affectedEntities==(try value.affectedIdentities)else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applySurveySession(value)=envelope.command{try value.validate();try validateSurveySessionReferences(value);guard affectedEntities==(try value.affectedIdentities)else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyAssetLocator(value)=envelope.command{try value.validate();guard affectedEntities==(try value.affectedIdentities)else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applySchedule(value)=envelope.command{try value.validate();try validateScheduleReferences(value);guard affectedEntities==(try value.affectedIdentities)else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyPlan(value)=envelope.command{try value.validate();try validatePlanReferences(value);guard affectedEntities==(try value.affectedIdentities)else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyPlacementPose(value)=envelope.command{try value.validate();try validatePlacementPoseReferences(value);guard affectedEntities==(try value.affectedIdentities)else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyEvidenceContext(value)=envelope.command{try value.validate();try validateEvidenceContextReferences(value);guard affectedEntities==[try value.affectedIdentity]else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyAssetPlacementChange(plan)=envelope.command{try plan.validate();try validateAssetPlacementPoseReferences(plan);guard let expected=try envelope.command.canonicalLocationAffectedIdentities(),affectedEntities==expected else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyLocationHierarchyChange(change)=envelope.command{for plan in change.placementChanges{try plan.validate();try validateAssetPlacementPoseReferences(plan)}}
        let state = try requireState()
        let current = try currentRevision(writerInstanceID: writerInstanceID)
        let expected = envelope.expectedRevision
        guard current.workspaceID == expected.workspaceID,
              current.generationID == expected.generationID,
              current.revision == expected.workspaceRevision else {
            throw WorkspaceMutationFailureV1.staleWorkspaceRevision
        }
        let currentByIdentity = Dictionary(uniqueKeysWithValues: current.entityRevisions.map { ($0.identity, $0.revision) })
        let expectedByIdentity = Dictionary(uniqueKeysWithValues: expected.entityRevisions.map { ($0.identity, $0.revision) })
        if case let .applySurveySession(mutation)=envelope.command{for concurrency in try mutation.concurrencyIdentities{guard expectedByIdentity[concurrency]==(try mutation.expectedRevision(for:concurrency)),currentByIdentity[concurrency,default:0]==expectedByIdentity[concurrency] else{throw WorkspaceMutationFailureV1.staleEntityRevision(concurrency)}}}
        if case let .applyAssetLocator(mutation)=envelope.command{for concurrency in try mutation.concurrencyIdentities{guard expectedByIdentity[concurrency]==(try mutation.expectedRevision(for:concurrency)),currentByIdentity[concurrency,default:0]==expectedByIdentity[concurrency]else{throw WorkspaceMutationFailureV1.staleEntityRevision(concurrency)}}}
        if case let .applySchedule(mutation)=envelope.command{for concurrency in try mutation.concurrencyIdentities{guard expectedByIdentity[concurrency]==(try mutation.expectedRevision(for:concurrency)),currentByIdentity[concurrency,default:0]==expectedByIdentity[concurrency]else{throw WorkspaceMutationFailureV1.staleEntityRevision(concurrency)}}}
        if case let .applyPlan(mutation)=envelope.command{for concurrency in try mutation.concurrencyIdentities{guard expectedByIdentity[concurrency]==(try mutation.expectedRevision(for:concurrency)),currentByIdentity[concurrency,default:0]==expectedByIdentity[concurrency]else{throw WorkspaceMutationFailureV1.staleEntityRevision(concurrency)}}}
        if case let .applyPlacementPose(mutation)=envelope.command{for concurrency in try mutation.concurrencyIdentities{guard expectedByIdentity[concurrency]==(try mutation.expectedRevision(for:concurrency)),currentByIdentity[concurrency,default:0]==expectedByIdentity[concurrency]else{throw WorkspaceMutationFailureV1.staleEntityRevision(concurrency)}}}
        if case let .applyEvidenceContext(operation)=envelope.command{let concurrency=try operation.concurrencyIdentity;guard expectedByIdentity[concurrency]==operation.expectedRevision,currentByIdentity[concurrency,default:0]==operation.expectedRevision else{throw WorkspaceMutationFailureV1.staleEntityRevision(concurrency)}}
        if case let .applyAssetPlacementChange(plan)=envelope.command,let mutation=try plan.placementPoseMutation{for concurrency in try mutation.concurrencyIdentities{guard expectedByIdentity[concurrency]==(try mutation.expectedRevision(for:concurrency)),currentByIdentity[concurrency,default:0]==expectedByIdentity[concurrency]else{throw WorkspaceMutationFailureV1.staleEntityRevision(concurrency)}}}
        if case let .applyLocationHierarchyChange(change)=envelope.command,let mutation=try change.placementPoseMutation{for concurrency in try mutation.concurrencyIdentities{guard expectedByIdentity[concurrency]==(try mutation.expectedRevision(for:concurrency)),currentByIdentity[concurrency,default:0]==expectedByIdentity[concurrency]else{throw WorkspaceMutationFailureV1.staleEntityRevision(concurrency)}}}
        for identity in affectedEntities {
            let concurrencyIdentity: WorkspaceEntityIdentityV1
            if case let .applyAuthorityCriterion(mutation) = envelope.command,
               identity == (try mutation.affectedIdentity) {
                concurrencyIdentity = try mutation.concurrencyIdentity
            } else if case let .applyFunctionalRelationship(mutation) = envelope.command,
                      identity == (try mutation.affectedIdentity) {
                concurrencyIdentity = try mutation.concurrencyIdentity
            }else if case let .applyEvidenceAssurance(mutation)=envelope.command,identity==(try mutation.affectedIdentity){concurrencyIdentity=try mutation.concurrencyIdentity
            }else if case let .applyInspectionReview(mutation)=envelope.command,let image=try mutation.postImage.mutationPostImages.first(where:{try $0.identity==identity}){concurrencyIdentity=try image.concurrencyIdentity
            }else if case let .applyWorkPacket(mutation)=envelope.command,identity==(try mutation.affectedIdentity){concurrencyIdentity=try mutation.concurrencyIdentity
            }else if case let .applyFieldDraft(mutation)=envelope.command,let image=try mutation.postImage.mutationPostImages.first(where:{try $0.identity==identity}){concurrencyIdentity=try image.concurrencyIdentity
            }else if case let .applyPackagePromotion(mutation)=envelope.command,let image=try mutation.mutationPostImages.first(where:{try $0.identity==identity}){concurrencyIdentity=try image.concurrencyIdentity
            }else if case let .applyMeasurementIntegrity(mutation)=envelope.command,let image=try mutation.mutationPostImages.first(where:{try $0.identity==identity}){concurrencyIdentity=try image.concurrencyIdentity
            }else if case let .applyPrivacyTransform(mutation)=envelope.command,let image=try mutation.mutationPostImages.first(where:{try $0.identity==identity}){concurrencyIdentity=try image.concurrencyIdentity
            }else if case let .applyClientCapability(mutation)=envelope.command{concurrencyIdentity=try mutation.concurrencyIdentity
            }else if case let .applyFieldReference(mutation)=envelope.command{concurrencyIdentity=try mutation.concurrencyIdentity
            }else if case let .applyAccessibleDocumentAssessment(mutation)=envelope.command{concurrencyIdentity=try mutation.concurrencyIdentity
            }else if case let .applySurveyDefinition(mutation)=envelope.command,let image=try mutation.mutationPostImages.first(where:{try $0.identity==identity}){concurrencyIdentity=try image.concurrencyIdentity
            }else if case let .applySurveySession(mutation)=envelope.command,let image=try mutation.mutationPostImages.first(where:{try $0.identity==identity}){concurrencyIdentity=try image.concurrencyIdentity
            }else if case let .applyAssetLocator(mutation)=envelope.command,let image=try mutation.mutationPostImages.first(where:{try $0.identity==identity}){concurrencyIdentity=try image.concurrencyIdentity
            }else if case let .applySchedule(mutation)=envelope.command,let image=try mutation.mutationPostImages.first(where:{try $0.identity==identity}){concurrencyIdentity=try image.concurrencyIdentity
            }else if case let .applyPlan(mutation)=envelope.command,let image=try mutation.mutationPostImages.first(where:{try $0.identity==identity}){concurrencyIdentity=try image.concurrencyIdentity
            }else if case let .applyPlacementPose(mutation)=envelope.command,let image=try mutation.mutationPostImages.first(where:{try $0.identity==identity}){concurrencyIdentity=try image.concurrencyIdentity
            }else if case let .applyEvidenceContext(operation)=envelope.command{concurrencyIdentity=try operation.concurrencyIdentity
            }else if case let .applyAssetPlacementChange(plan)=envelope.command,let mutation=try plan.placementPoseMutation,let image=try mutation.mutationPostImages.first(where:{try $0.identity==identity}){concurrencyIdentity=try image.concurrencyIdentity
            }else if case let .applyLocationHierarchyChange(change)=envelope.command,let mutation=try change.placementPoseMutation,let image=try mutation.mutationPostImages.first(where:{try $0.identity==identity}){concurrencyIdentity=try image.concurrencyIdentity
            } else {
                concurrencyIdentity = identity
            }
            guard let expectedRevision = expectedByIdentity[concurrencyIdentity] else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
            guard expectedRevision == currentByIdentity[concurrencyIdentity, default: 0] else {
                throw WorkspaceMutationFailureV1.staleEntityRevision(concurrencyIdentity)
            }
        }
        guard state.workspaceRevision >= 0, state.lastLocalSequence >= 0,
              state.workspaceRevision < Int64.max, state.lastLocalSequence < Int64.max else {
            throw WorkspaceMutationFailureV1.revisionOverflow
        }

        state.workspaceRevision += 1
        state.lastLocalSequence += 1
        var postImages: [MutationPostImageV1] = []
        for entity in affectedEntities.sorted(by: { $0.stableKey < $1.stableKey }) {
            let key = entity.stableKey
            let rows = try modelContext.fetch(FetchDescriptor<EntityMutationRevisionRow>(
                predicate: #Predicate { $0.stableIdentity == key }
            ))
            guard rows.count <= 1 else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
            let row: EntityMutationRevisionRow
            if let existing = rows.first {
                guard existing.revision >= 0, existing.revision < Int64.max else { throw WorkspaceMutationFailureV1.revisionOverflow }
                existing.revision += 1
                existing.externalProjectionSHA256 = nil
                row = existing
            } else {
                let initialRevision: UInt64
                if case let .applyAuthorityCriterion(mutation) = envelope.command,
                   entity == (try mutation.affectedIdentity) {
                    initialRevision = mutation.postImage.revision
                } else if case let .applyFunctionalRelationship(mutation) = envelope.command,
                          entity == (try mutation.affectedIdentity) {
                    initialRevision = mutation.postImage.revision
                }else if case let .applyEvidenceAssurance(mutation)=envelope.command,entity==(try mutation.affectedIdentity){initialRevision=mutation.postImage.revision
                }else if case let .applyInspectionReview(mutation)=envelope.command,let image=try mutation.postImage.mutationPostImages.first(where:{try $0.identity==entity}){initialRevision=image.revision
                }else if case let .applyWorkPacket(mutation)=envelope.command,entity==(try mutation.affectedIdentity){initialRevision=mutation.postImage.revision
                }else if case let .applyFieldDraft(mutation)=envelope.command,let image=try mutation.postImage.mutationPostImages.first(where:{try $0.identity==entity}){initialRevision=image.revision
                }else if case let .applyPackagePromotion(mutation)=envelope.command,let image=try mutation.mutationPostImages.first(where:{try $0.identity==entity}){initialRevision=image.revision
                }else if case let .applyMeasurementIntegrity(mutation)=envelope.command,let image=try mutation.mutationPostImages.first(where:{try $0.identity==entity}){initialRevision=image.revision
                }else if case let .applyPrivacyTransform(mutation)=envelope.command,let image=try mutation.mutationPostImages.first(where:{try $0.identity==entity}){initialRevision=image.revision
                }else if case let .applyClientCapability(mutation)=envelope.command{initialRevision=mutation.revision
                }else if case let .applyFieldReference(mutation)=envelope.command{initialRevision=mutation.revision
                }else if case let .applyAccessibleDocumentAssessment(mutation)=envelope.command{initialRevision=mutation.revision
                }else if case let .applySurveyDefinition(mutation)=envelope.command,let image=try mutation.mutationPostImages.first(where:{try $0.identity==entity}){initialRevision=image.revision
                }else if case let .applySurveySession(mutation)=envelope.command,let image=try mutation.mutationPostImages.first(where:{try $0.identity==entity}){initialRevision=image.revision
                }else if case let .applyAssetLocator(mutation)=envelope.command,let image=try mutation.mutationPostImages.first(where:{try $0.identity==entity}){initialRevision=image.revision
                }else if case let .applySchedule(mutation)=envelope.command,let image=try mutation.mutationPostImages.first(where:{try $0.identity==entity}){initialRevision=image.revision
                }else if case let .applyPlan(mutation)=envelope.command,let image=try mutation.mutationPostImages.first(where:{try $0.identity==entity}){initialRevision=image.revision
                }else if case let .applyPlacementPose(mutation)=envelope.command,let image=try mutation.mutationPostImages.first(where:{try $0.identity==entity}){initialRevision=image.revision
                }else if case let .applyEvidenceContext(operation)=envelope.command{initialRevision=operation.revision
                }else if case let .applyAssetPlacementChange(plan)=envelope.command,let mutation=try plan.placementPoseMutation,let image=try mutation.mutationPostImages.first(where:{try $0.identity==entity}){initialRevision=image.revision
                }else if case let .applyLocationHierarchyChange(change)=envelope.command,let mutation=try change.placementPoseMutation,let image=try mutation.mutationPostImages.first(where:{try $0.identity==entity}){initialRevision=image.revision
                } else {
                    initialRevision = 1
                }
                guard initialRevision <= UInt64(Int64.max) else {
                    throw WorkspaceMutationFailureV1.revisionOverflow
                }
                row = EntityMutationRevisionRow(identity: entity, revision: initialRevision)
                modelContext.insert(row)
            }
            postImages.append(try currentPostImage(
                identity: entity,
                revision: try domainRevision(row.revision)
            ))
        }
        if case let .applyAuthorityCriterion(mutation) = envelope.command {
            guard postImages == [try mutation.postImage.mutationPostImage] else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        }
        if case let .applyFunctionalRelationship(mutation) = envelope.command {
            guard postImages == [try mutation.postImage.mutationPostImage] else {
                throw WorkspaceMutationFailureV1.invalidCommand
            }
        }
        if case let .applyEvidenceAssurance(mutation)=envelope.command{guard postImages==[try mutation.postImage.mutationPostImage]else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyInspectionReview(mutation)=envelope.command{guard postImages==(try mutation.postImage.mutationPostImages) else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyWorkPacket(mutation)=envelope.command{guard postImages==[try mutation.postImage.mutationPostImage]else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyFieldDraft(mutation)=envelope.command{guard postImages==(try mutation.postImage.mutationPostImages)else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyPackagePromotion(mutation)=envelope.command{guard postImages==(try mutation.mutationPostImages)else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyMeasurementIntegrity(mutation)=envelope.command{guard postImages==(try mutation.mutationPostImages)else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyPrivacyTransform(mutation)=envelope.command{guard postImages==(try mutation.mutationPostImages)else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyClientCapability(mutation)=envelope.command{guard postImages==[try mutation.mutationPostImage]else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyFieldReference(mutation)=envelope.command{guard postImages==[try mutation.mutationPostImage]else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyAccessibleDocumentAssessment(mutation)=envelope.command{guard postImages==[try mutation.mutationPostImage]else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applySurveyDefinition(mutation)=envelope.command{guard postImages==(try mutation.mutationPostImages)else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applySurveySession(mutation)=envelope.command{guard postImages==(try mutation.mutationPostImages)else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyAssetLocator(mutation)=envelope.command{guard postImages==(try mutation.mutationPostImages)else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applySchedule(mutation)=envelope.command{guard postImages==(try mutation.mutationPostImages)else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyPlan(mutation)=envelope.command{guard postImages==(try mutation.mutationPostImages)else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyPlacementPose(mutation)=envelope.command{guard postImages==(try mutation.mutationPostImages)else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyEvidenceContext(operation)=envelope.command{guard postImages==[try operation.mutationPostImage]else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyAssetPlacementChange(plan)=envelope.command,let mutation=try plan.placementPoseMutation{let poseImages=try mutation.mutationPostImages;guard poseImages.allSatisfy({postImages.contains($0)})else{throw WorkspaceMutationFailureV1.invalidCommand}}
        if case let .applyLocationHierarchyChange(change)=envelope.command,let mutation=try change.placementPoseMutation{let poseImages=try mutation.mutationPostImages;guard poseImages.allSatisfy({postImages.contains($0)})else{throw WorkspaceMutationFailureV1.invalidCommand}}
        let after = try currentRevision(writerInstanceID: writerInstanceID)
        let receiptIdentity = MutationReceiptIdentityV1(
            workspaceID: identity.workspaceID,
            replicaID: identity.replicaID,
            localSequence: try domainRevision(state.lastLocalSequence)
        )
        let receipt = try MutationReceiptV1(
            identity: receiptIdentity,
            envelope: envelope,
            resultingRevision: try MutationPortableExpectedRevisionV1(.init(snapshot: after)),
            postImages: postImages,
            reversesMutationID: semanticReversalExecution?.targetMutationID ?? semanticReversal?.reversesMutationID,
            committedAt: committedAt
        )
        let generatedSemanticReversal: SemanticReversalReceiptV1?
        if let execution = semanticReversalExecution {
            generatedSemanticReversal = try SemanticReversalReceiptV1(
                reversalReceiptIdentity: receipt.identity,
                reversesMutationID: execution.targetMutationID,
                targetReceiptIdentity: execution.targetReceiptIdentity,
                reversalBasisSHA256: execution.reversalBasisSHA256,
                planDigest: execution.planDigest,
                compensatingMutationIDs: execution.compensatingMutationIDs,
                resultingRevision: receipt.resultingRevision
            )
        } else {
            generatedSemanticReversal = semanticReversal
        }
        if case let .applyLocationHierarchyChange(value) = envelope.command {
            let plan = value.plan
            let operationID = plan.operationID
            guard try modelContext.fetch(FetchDescriptor<LocationHierarchyEventRow>(
                predicate: #Predicate { $0.operationID == operationID }
            )).isEmpty else { throw WorkspaceMutationFailureV1.sequenceCollision }
            let hierarchyReceipt = try LocationHierarchyChangeReceiptV1(
                plan: plan,
                placementChanges: value.placementChanges,
                mutationReceipt: receipt
            )
            modelContext.insert(try LocationHierarchyEventRow(
                plan: plan,
                receipt: hierarchyReceipt
            ))
        }
        modelContext.insert(try MutationReceiptRow(
            envelope: envelope,
            receipt: receipt,
            reversalBasis: reversalBasis,
            semanticReversal: generatedSemanticReversal
        ))
        state.mutableSemanticSHA256 = try mutableSemanticSHA256()
        try reach(.afterReceiptBeforeSave)
        do {
            try modelContext.save()
            try reach(.afterSaveBeforeReturn)
            return receipt
        } catch let failure as MutationJournalFailureV1 {
            modelContext.rollback()
            throw failure
        } catch let failure as WorkspaceMutationFailureV1 {
            modelContext.rollback()
            throw failure
        } catch {
            modelContext.rollback()
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
    }

    func receipt(mutationID: MutationIDV1) throws -> MutationReceiptV1? {
        let key = MutationWorkspaceKeyV1.value(workspaceID: identity.workspaceID, mutationID: mutationID)
        let rows = try modelContext.fetch(FetchDescriptor<MutationReceiptRow>(predicate: #Predicate { $0.workspaceMutationKey == key }))
        guard rows.count <= 1 else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
        return try rows.first.map { try validate(row: $0, expectedEnvelope: nil) }
    }

    func surveyDefinitionMutation(mutationID: MutationIDV1) throws -> SurveyDefinitionMutationV1? {
        let key=MutationWorkspaceKeyV1.value(workspaceID:identity.workspaceID,mutationID:mutationID)
        let rows=try modelContext.fetch(FetchDescriptor<MutationReceiptRow>(predicate:#Predicate{$0.workspaceMutationKey==key}))
        guard rows.count<=1 else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt}
        guard let row=rows.first else{return nil}
        _ = try validate(row:row,expectedEnvelope:nil)
        let envelope=try MutationEnvelopeV1.decodeCanonical(from:row.envelopeData)
        guard case let .applySurveyDefinition(mutation)=envelope.command else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt}
        try mutation.validate()
        return mutation
    }

    func acceptedSurveySessionMutation(_ mutation:SurveySessionMutationV1)throws->SurveySessionMutationReceiptV1?{try validateSurveySessionReferences(mutation);guard let receipt=try receipt(mutationID:mutation.mutationID)else{return nil};let stored=try surveySessionMutation(mutationID:mutation.mutationID);guard stored==mutation else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return try SurveySessionMutationReceiptV1(mutation:mutation,mutationReceipt:receipt)}

    func surveySessionMutation(mutationID:MutationIDV1)throws->SurveySessionMutationV1?{let key=MutationWorkspaceKeyV1.value(workspaceID:identity.workspaceID,mutationID:mutationID);let rows=try modelContext.fetch(FetchDescriptor<MutationReceiptRow>(predicate:#Predicate{$0.workspaceMutationKey==key}));guard rows.count<=1 else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};guard let row=rows.first else{return nil};_ = try validate(row:row,expectedEnvelope:nil);let envelope=try MutationEnvelopeV1.decodeCanonical(from:row.envelopeData);guard case let .applySurveySession(mutation)=envelope.command else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};try mutation.validate();try validateSurveySessionReferences(mutation);return mutation}
    func acceptedAssetLocatorMutation(_ mutation:AssetLocatorMutationV1)throws->AssetLocatorMutationReceiptV1?{guard let receipt=try receipt(mutationID:mutation.mutationID)else{return nil};guard try assetLocatorMutation(mutationID:mutation.mutationID)==mutation else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return try AssetLocatorMutationReceiptV1(mutation:mutation,mutationReceipt:receipt)}
    func assetLocatorMutation(mutationID:MutationIDV1)throws->AssetLocatorMutationV1?{let key=MutationWorkspaceKeyV1.value(workspaceID:identity.workspaceID,mutationID:mutationID),rows=try modelContext.fetch(FetchDescriptor<MutationReceiptRow>(predicate:#Predicate{$0.workspaceMutationKey==key}));guard rows.count<=1 else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};guard let row=rows.first else{return nil};_ = try validate(row:row,expectedEnvelope:nil);let envelope=try MutationEnvelopeV1.decodeCanonical(from:row.envelopeData);guard case let .applyAssetLocator(mutation)=envelope.command else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};try mutation.validate();return mutation}
    func acceptedScheduleMutation(_ mutation:ScheduleMutationV1)throws->ScheduleMutationReceiptV1?{guard let receipt=try receipt(mutationID:mutation.mutationID)else{return nil};guard try scheduleMutation(mutationID:mutation.mutationID)==mutation else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return try ScheduleMutationReceiptV1(mutation:mutation,mutationReceipt:receipt)}
    func scheduleMutation(mutationID:MutationIDV1)throws->ScheduleMutationV1?{let key=MutationWorkspaceKeyV1.value(workspaceID:identity.workspaceID,mutationID:mutationID),rows=try modelContext.fetch(FetchDescriptor<MutationReceiptRow>(predicate:#Predicate{$0.workspaceMutationKey==key}));guard rows.count<=1 else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};guard let row=rows.first else{return nil};_ = try validate(row:row,expectedEnvelope:nil);let envelope=try MutationEnvelopeV1.decodeCanonical(from:row.envelopeData);guard case let .applySchedule(mutation)=envelope.command else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};try mutation.validate();try validateScheduleReferences(mutation);return mutation}
    func acceptedPlanMutation(_ mutation:PlanMutationV1)throws->PlanMutationReceiptV1?{guard let receipt=try receipt(mutationID:mutation.mutationID)else{return nil};guard try planMutation(mutationID:mutation.mutationID)==mutation else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return try PlanMutationReceiptV1(mutation:mutation,mutationReceipt:receipt)}
    func planMutation(mutationID:MutationIDV1)throws->PlanMutationV1?{let key=MutationWorkspaceKeyV1.value(workspaceID:identity.workspaceID,mutationID:mutationID),rows=try modelContext.fetch(FetchDescriptor<MutationReceiptRow>(predicate:#Predicate{$0.workspaceMutationKey==key}));guard rows.count<=1 else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};guard let row=rows.first else{return nil};_ = try validate(row:row,expectedEnvelope:nil);let envelope=try MutationEnvelopeV1.decodeCanonical(from:row.envelopeData);guard case let .applyPlan(mutation)=envelope.command else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};try mutation.validate();try validatePlanReferences(mutation);return mutation}
    func validatePlanReferences(_ mutation:PlanMutationV1)throws{let documents=try modelContext.fetch(FetchDescriptor<PlanDocumentRow>()).map{try $0.value()},revisions=try modelContext.fetch(FetchDescriptor<PlanRevisionRow>()).map{try $0.value()},fieldReleases=try modelContext.fetch(FetchDescriptor<FieldReferenceReleaseRow>()).map{try $0.value()},locatorReceipts=try modelContext.fetch(FetchDescriptor<LocatorBindingReceiptRow>()).map{try $0.value()};func revision(_ value:PlanRevisionV1)throws{guard documents.filter({$0.planDocumentID==value.planDocument.planDocumentID&&$0.revision==value.planDocument.revision&&$0.documentSHA256==value.planDocument.documentSHA256}).count==1,fieldReleases.filter({$0.releaseID==value.contentBinding.fieldReferenceReleaseID&&$0.revision==value.contentBinding.fieldReferenceReleaseRevision&&$0.releaseSHA256==value.contentBinding.fieldReferenceReleaseSHA256&&$0.manifestSHA256==value.contentBinding.fieldReferenceManifestSHA256}).count==1 else{throw WorkspaceMutationFailureV1.invalidCommand}};func placement(_ value:PlanPlacementV1)throws{guard revisions.filter({$0.planRevisionID==value.planRevision.planRevisionID&&$0.revision==value.planRevision.revision&&$0.revisionSHA256==value.planRevision.revisionSHA256}).count==1 || (try mutation.payload.newRevisionForReference == value.planRevision) else{throw WorkspaceMutationFailureV1.invalidCommand};if let binding=value.assetLocatorBinding{guard locatorReceipts.filter({$0.receiptID==binding.bindingReceiptID&&$0.revision==binding.bindingReceiptRevision&&$0.receiptSHA256==binding.bindingReceiptSHA256&&$0.after==binding.locator&&$0.after.assetID==binding.assetID}).count==1 else{throw WorkspaceMutationFailureV1.invalidCommand}}};switch mutation.payload{case .appendDocument:break;case let .appendRevision(value,_,_):try revision(value);case let .appendPlacement(value,_,_):try placement(value);case let .applyRebase(value,_,placements,_,_,_,poseEffects):try revision(value);try placements.forEach(placement);if let poseEffects{try validatePlacementPoseReferences(poseEffects)};case .recordRebaseRejection:break}}
    func acceptedPlacementPoseMutation(_ mutation:PlacementPoseMutationV1)throws->PlacementPoseMutationReceiptV1?{guard let receipt=try receipt(mutationID:mutation.mutationID)else{return nil};guard try placementPoseMutation(mutationID:mutation.mutationID)==mutation else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return try PlacementPoseMutationReceiptV1(mutation:mutation,mutationReceipt:receipt)}
    func placementPoseMutation(mutationID:MutationIDV1)throws->PlacementPoseMutationV1?{let key=MutationWorkspaceKeyV1.value(workspaceID:identity.workspaceID,mutationID:mutationID),rows=try modelContext.fetch(FetchDescriptor<MutationReceiptRow>(predicate:#Predicate{$0.workspaceMutationKey==key}));guard rows.count<=1 else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};guard let row=rows.first else{return nil};_ = try validate(row:row,expectedEnvelope:nil);let envelope=try MutationEnvelopeV1.decodeCanonical(from:row.envelopeData);guard case let .applyPlacementPose(mutation)=envelope.command else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};try mutation.validate();try validatePlacementPoseReferences(mutation);return mutation}
    func acceptedEvidenceContextOperation(_ operation:EvidenceContextWriteOperationV1)throws->EvidenceContextMutationReceiptV1?{guard let receipt=try receipt(mutationID:operation.mutationID)else{return nil};guard try evidenceContextOperation(mutationID:operation.mutationID)==operation else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return try EvidenceContextMutationReceiptV1(operation:operation,mutationReceipt:receipt)}
    func evidenceContextOperation(mutationID:MutationIDV1)throws->EvidenceContextWriteOperationV1?{let key=MutationWorkspaceKeyV1.value(workspaceID:identity.workspaceID,mutationID:mutationID),rows=try modelContext.fetch(FetchDescriptor<MutationReceiptRow>(predicate:#Predicate{$0.workspaceMutationKey==key}));guard rows.count<=1 else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};guard let row=rows.first else{return nil};_ = try validate(row:row,expectedEnvelope:nil);let envelope=try MutationEnvelopeV1.decodeCanonical(from:row.envelopeData);guard case let .applyEvidenceContext(operation)=envelope.command else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};try operation.validate();try validateEvidenceContextReferences(operation);return operation}
    private func validateEvidenceContextReferences(_ operation:EvidenceContextWriteOperationV1)throws{guard case let .appendPair(value,_)=operation else{return};let existing=try modelContext.fetch(FetchDescriptor<PairedObservationLinkRow>()).map{try $0.value()};for candidate in [value.first,value.second]{let historical=existing.filter{$0.workspaceID==value.workspaceID}.flatMap{[$0.first,$0.second]}.filter{$0.evidenceID==candidate.evidenceID};guard historical.allSatisfy({$0.purpose==candidate.purpose&&$0.purposeRevision==candidate.purposeRevision})else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt}}}
    func validatePlacementPoseReferences(_ mutation:PlacementPoseMutationV1)throws{try validatePlacementPoseAdmissionClosure(mutation.admissionClosure,pendingPlacementIDs:[]);let revisions=try modelContext.fetch(FetchDescriptor<PlanRevisionRow>()).map{try $0.value()},placementEvents=try modelContext.fetch(FetchDescriptor<AssetPlacementEventRow>()).map{try $0.value()};for event in mutation.events{guard placementEvents.filter({$0.id==event.placementEventID&&$0.workspaceID==event.workspaceID&&$0.assetID==event.assetID&&$0.physicalEpisodeID==event.placementEpisodeID}).count==1 else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt}};for observation in mutation.observations{guard revisions.filter({revision in revision.planRevisionID==observation.planFrame.planRevision.planRevisionID&&revision.workspaceID==observation.workspaceID&&revision.revision==observation.planFrame.planRevision.revision&&revision.revisionSHA256==observation.planFrame.planRevision.revisionSHA256&&revision.spatialFrames.contains(where:{$0.frameID==observation.planFrame.spatialFrameID&&$0.pageID==observation.planFrame.pageID})}).count==1 else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt}}}
    private func validateAssetPlacementPoseReferences(_ plan:AssetPlacementChangePlanV1)throws{if let closure=plan.poseAdmissionClosure{try validatePlacementPoseAdmissionClosure(closure,pendingPlacementIDs:[plan.newEventID])};guard plan.poseEvents.count==plan.poseEventPredecessors.count else{throw WorkspaceMutationFailureV1.invalidCommand};let rows=try modelContext.fetch(FetchDescriptor<AssetPoseEventRow>()).map{try $0.value()};for (value,predecessor) in zip(plan.poseEvents,plan.poseEventPredecessors){guard rows.filter({$0.eventID==predecessor.eventID&&$0==predecessor}).count==1,rows.filter({$0.predecessor?.eventID==predecessor.eventID}).isEmpty,value.placementEventID==plan.newEventID,value.locationPathSnapshot==plan.basis.proposedPath else{throw WorkspaceMutationFailureV1.invalidCommand}}}
    private func validatePlacementPoseAdmissionClosure(_ closure:PlacementPoseAdmissionClosureV1,pendingPlacementIDs:Set<UUID>)throws{
        let releaseRows=try modelContext.fetch(FetchDescriptor<PromotedPackageReleaseRow>())
        let releases=try releaseRows.map{try $0.value().packageRelease}
        guard releases.filter({$0.packageReleaseID==closure.packageRelease.packageReleaseID}).count==1,
              releases.contains(closure.packageRelease) else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt}
        let revisions=try modelContext.fetch(FetchDescriptor<PlanRevisionRow>()).map{try $0.value()}
        for value in closure.planRevisions{guard revisions.filter({$0==value}).count==1 else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt}}
        let placements=try modelContext.fetch(FetchDescriptor<AssetPlacementEventRow>()).map{try $0.value()}
        for value in closure.placementEvents where !pendingPlacementIDs.contains(value.id){guard placements.filter({$0==value}).count==1 else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt}}
        guard Set(closure.placementEvents.filter({pendingPlacementIDs.contains($0.id)}).map(\.id))==pendingPlacementIDs else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt}
    }
    func validateScheduleReferences(_ mutation:ScheduleMutationV1)throws{
        let requiredRelease:ScheduleDefinitionReleaseV1,requiresPersistedRelease:Bool
        switch mutation.payload{case let .appendRelease(value,_):requiredRelease=value;requiresPersistedRelease=false;case let .appendOccurrenceEvent(_,_,release),let .startOccurrence(_,_,release),let .generateOccurrences(release,_,_):requiredRelease=release;requiresPersistedRelease=true}
        if requiresPersistedRelease{let releaseID=requiredRelease.releaseID,rows=try modelContext.fetch(FetchDescriptor<ScheduleDefinitionReleaseRow>(predicate:#Predicate{$0.releaseID==releaseID}));guard rows.count==1,try rows.first?.value()==requiredRelease else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt}}
        let definitionReference=requiredRelease.workDefinition.definitionRelease,definitionID=definitionReference.releaseID
        let definitionRows=try modelContext.fetch(FetchDescriptor<SurveyDefinitionReleaseRow>(predicate:#Predicate{$0.releaseID==definitionID}))
        guard definitionRows.count==1,let definition=try definitionRows.first?.value(),definition.workspaceID==requiredRelease.workDefinition.definitionWorkspaceID,try SurveyDefinitionReleaseReferenceV1(definition)==definitionReference else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt}
        let packageReleaseID=requiredRelease.workDefinition.packageReleaseID,packageMatches=try modelContext.fetch(FetchDescriptor<PromotedPackageReleaseRow>()).map{try $0.value().packageRelease}.filter{$0.packageReleaseID==packageReleaseID}
        guard packageMatches.count==1,let package=packageMatches.first,package.state == .published,package.packageID==requiredRelease.workDefinition.packageID,package.packageContentVersion==requiredRelease.workDefinition.packageContentVersion,package.packageSHA256==requiredRelease.workDefinition.packageSHA256,package.workflowSHA256==requiredRelease.workDefinition.workflowSHA256 else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt}
    }
    func validateSurveySessionReferences(_ mutation:SurveySessionMutationV1)throws{let binding:(SurveySessionV1,SurveyDefinitionReleaseV1)?;switch mutation.payload{case let .applySession(session,definition,_),let .captureFact(_,session,definition,_),let .publish(session,_,definition,_):binding=(session,definition);case .applyProvisionalSubject,.promoteSubject:binding=nil};guard let (session,definition)=binding else{return};let release=try surveyPackageRelease(session.authority.packageRelease.packageReleaseID);do{try session.authority.validate(definition:definition,packageRelease:release)}catch{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt}}

    func acceptedRecoverabilityVerificationReceipt(
        for plan: RecoverabilityVerificationPlanV1
    ) throws -> RecoverabilityVerificationReceiptV1? {
        try validateCurrentWriterLease()
        try plan.validate()
        guard plan.workspaceID == identity.workspaceID else {
            throw RecoverabilityVerificationFailureV1.wrongWorkspace
        }
        let matches = try recoverabilityVerificationReceiptRows(matching: plan)
        guard matches.count <= 1 else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        guard let row = matches.first else { return nil }
        let receipt = try row.value()
        try validate(receipt: receipt, matches: plan)
        return receipt
    }

    func appendRecoverabilityVerificationReceipt(
        _ receipt: RecoverabilityVerificationReceiptV1
    ) throws -> RecoverabilityVerificationReceiptV1 {
        try validateCurrentWriterLease()
        try receipt.validate()
        guard receipt.workspaceID == identity.workspaceID else {
            throw RecoverabilityVerificationFailureV1.wrongWorkspace
        }
        try validateRecoverabilityVerificationReceipts()

        let rows = try boundedFetch(FetchDescriptor<RecoverabilityVerificationReceiptRow>())
        let collisions = rows.filter {
            $0.receiptID == receipt.receiptID
                || $0.verificationID == receipt.verificationID
                || $0.mutationID == receipt.mutationID.rawValue
        }
        guard collisions.count <= 1 else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        if let existingRow = collisions.first {
            let existing = try existingRow.value()
            guard existing == receipt else {
                throw RecoverabilityVerificationFailureV1.divergentRetry
            }
            return existing
        }

        if let predecessorID = receipt.supersedesReceiptID {
            let predecessors = rows.filter { $0.receiptID == predecessorID }
            guard predecessors.count == 1, let predecessorRow = predecessors.first else {
                throw RecoverabilityVerificationFailureV1.invalidSuccessor
            }
            let predecessor = try predecessorRow.value()
            try receipt.validateSuccessor(of: predecessor)
            guard !rows.contains(where: { row in
                guard let value = try? row.value() else { return true }
                return value.supersedesReceiptID == predecessorID
            }) else {
                throw RecoverabilityVerificationFailureV1.invalidSuccessor
            }
        }

        modelContext.insert(try RecoverabilityVerificationReceiptRow(receipt))
        do {
            try reach(.afterReceiptBeforeSave)
            try saveWithStaleWriterFence()
            try reach(.afterSaveBeforeReturn)
            return receipt
        } catch let failure as WorkspaceMutationFailureV1 {
            modelContext.rollback()
            throw failure
        } catch let failure as MutationJournalFailureV1 {
            modelContext.rollback()
            throw failure
        } catch let failure as RecoverabilityVerificationFailureV1 {
            modelContext.rollback()
            throw failure
        } catch {
            modelContext.rollback()
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
    }

    /// Effect-before-receipt recovery for the C18 aggregate requires all four
    /// canonical rows to agree before an existing mutation may be adopted.
    func packagePromotionLifecycleClosure(mutationID:MutationIDV1)throws->PackageEvolutionLifecycleClosureV1?{guard try receipt(mutationID:mutationID) != nil else{return nil};let id=mutationID.rawValue;let releaseRows=try modelContext.fetch(FetchDescriptor<PromotedPackageReleaseRow>(predicate:#Predicate{$0.mutationID==id})),runRows=try modelContext.fetch(FetchDescriptor<PackageSandboxRunRow>(predicate:#Predicate{$0.mutationID==id})),receiptRows=try modelContext.fetch(FetchDescriptor<PackagePromotionReceiptRow>(predicate:#Predicate{$0.mutationID==id})),pointerRows=try modelContext.fetch(FetchDescriptor<ActivePackageRegistryPointerRow>(predicate:#Predicate{$0.mutationID==id}));guard releaseRows.count==1,runRows.count==1,receiptRows.count==1,pointerRows.count==1,let release=try releaseRows.first?.value(),let run=try runRows.first?.value(),let promotionReceipt=try receiptRows.first?.value(),let pointer=try pointerRows.first?.value()else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};var pointers=[pointer];if let predecessorID=pointer.supersedesPointerID{let predecessorRows=try modelContext.fetch(FetchDescriptor<ActivePackageRegistryPointerRow>(predicate:#Predicate{$0.pointerID==predecessorID}));guard predecessorRows.count==1,let predecessor=try predecessorRows.first?.value()else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};pointers.append(predecessor)};return try PackageEvolutionLifecycleClosureV1(promotedReleases:[release],sandboxRuns:[run],promotionReceipts:[promotionReceipt],activePointers:pointers)}

    /// Enumerates only validated, journal-owned receipts for the current
    /// workspace. The result is a bounded immutable source for C17's derived
    /// integration projection; no operational projection state is read or
    /// written here.
    func acceptedReceiptsForProjection() throws -> [MutationReceiptV1] {
        let snapshot = try exportSnapshot()
        let receipts = try snapshot.receipts.map {
            try MutationReceiptV1.decodeCanonical(from: $0.receiptData)
        }
        return try MutationReceiptV1.orderedAcceptedProjectionReceipts(
            receipts,
            workspaceID: identity.workspaceID
        )
    }

    func reversalBasis(mutationID: MutationIDV1) throws -> ReversalBasisV1? {
        let key = MutationWorkspaceKeyV1.value(workspaceID: identity.workspaceID, mutationID: mutationID)
        let rows = try modelContext.fetch(FetchDescriptor<MutationReceiptRow>(predicate: #Predicate { $0.workspaceMutationKey == key }))
        guard rows.count <= 1 else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
        guard let data = rows.first?.reversalBasisData else { return nil }
        return try ReversalBasisV1.decodeCanonical(from: data)
    }

    func validateAll() throws {
        try validateRecoverabilityVerificationReceipts()
        var descriptor = FetchDescriptor<MutationReceiptRow>(sortBy: [SortDescriptor(\.receiptIdentity)])
        descriptor.fetchLimit = Self.maximumReceiptValidationCount + 1
        let rows = try modelContext.fetch(descriptor)
        guard rows.count <= Self.maximumReceiptValidationCount else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        var identities = Set<String>()
        var mutations = Set<String>()
        var sequenceKeys = Set<String>()
        var maximumSequenceByReplica: [String: UInt64] = [:]
        var maximumWorkspaceRevision: UInt64 = 0
        var latestPostImageByIdentity: [WorkspaceEntityIdentityV1: MutationPostImageV1] = [:]
        var receiptsByMutation: [String: MutationReceiptV1] = [:]
        var rowsByMutation: [String: MutationReceiptRow] = [:]
        for row in rows {
            let receipt = try validate(row: row, expectedEnvelope: nil)
            guard identities.insert(row.receiptIdentity).inserted,
                  mutations.insert(row.workspaceMutationKey).inserted else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            let replica = "\(row.workspaceID.uuidString.lowercased()):\(row.replicaID.uuidString.lowercased())"
            guard sequenceKeys.insert("\(replica):\(receipt.identity.localSequence)").inserted else {
                throw WorkspaceMutationFailureV1.sequenceCollision
            }
            maximumSequenceByReplica[replica] = max(
                maximumSequenceByReplica[replica, default: 0],
                receipt.identity.localSequence
            )
            if receipt.identity.workspaceID == identity.workspaceID {
                maximumWorkspaceRevision = max(
                    maximumWorkspaceRevision,
                    receipt.resultingRevision.workspaceRevision
                )
                for image in receipt.postImages {
                    let entity = try image.identity
                    if let prior = latestPostImageByIdentity[entity] {
                        if prior.revision == image.revision, prior != image {
                            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
                        }
                        if prior.revision >= image.revision { continue }
                    }
                    latestPostImageByIdentity[entity] = image
                }
            }
            let key = MutationWorkspaceKeyV1.value(workspaceID: receipt.identity.workspaceID, mutationID: receipt.mutationID)
            receiptsByMutation[key] = receipt
            rowsByMutation[key] = row
        }
        for (mutationKey, row) in rowsByMutation where row.semanticReversalData != nil {
            guard let data = row.semanticReversalData else { continue }
            let reversal = try SemanticReversalReceiptV1.decodeCanonical(from: data)
            let targetKey = MutationWorkspaceKeyV1.value(
                workspaceID: reversal.targetReceiptIdentity.workspaceID,
                mutationID: reversal.reversesMutationID
            )
            guard let reversalMutationReceipt = receiptsByMutation[mutationKey],
                  reversalMutationReceipt.identity == reversal.reversalReceiptIdentity,
                  reversal.resultingRevision == reversalMutationReceipt.resultingRevision,
                  reversal.compensatingMutationIDs == [reversalMutationReceipt.mutationID],
                  let target = receiptsByMutation[targetKey],
                  target.identity == reversal.targetReceiptIdentity,
                  let targetRow = rowsByMutation[targetKey],
                  let basisData = targetRow.reversalBasisData else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            let basis = try ReversalBasisV1.decodeCanonical(from: basisData)
            guard reversal.reversalBasisSHA256 == (try basis.canonicalSHA256()),
                  reversal.planDigest == basis.planDigest,
                  try Self.requireCompleteCompensatingReceipts(
                    reversal,
                    receiptsByMutation: receiptsByMutation
                  ) else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
        }
        var quarantineDescriptor = FetchDescriptor<MutationQuarantineRow>()
        quarantineDescriptor.fetchLimit = Self.maximumReceiptValidationCount + 1
        let quarantineRows = try modelContext.fetch(quarantineDescriptor)
        guard quarantineRows.count <= Self.maximumReceiptValidationCount else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        var quarantineKeys = Set<String>()
        for quarantine in quarantineRows {
            let workspace = WorkspaceID(rawValue: quarantine.workspaceID)
            let mutation = try MutationIDV1(rawValue: quarantine.mutationID)
            let key = MutationWorkspaceKeyV1.value(workspaceID: workspace, mutationID: mutation)
            guard let domain = MutationQuarantineIdentityDomainV1(rawValue: quarantine.identityDomain),
                  let receiptRow = rowsByMutation[key] else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            let acceptedIdentity: String
            switch domain {
            case .mutationEnvelope:
                acceptedIdentity = receiptRow.envelopeSHA256
            case .semanticReversalReplayIdentity:
                acceptedIdentity = try MutationEnvelopeV1.decodeCanonical(
                    from: receiptRow.envelopeData
                ).semanticReversalReplayIdentitySHA256 ?? ""
            }
            guard key == quarantine.workspaceMutationKey,
                  quarantineKeys.insert(key).inserted,
                  MutationEnvelopeV1.isSHA256(quarantine.acceptedIdentitySHA256),
                  MutationEnvelopeV1.isSHA256(quarantine.conflictingIdentitySHA256),
                  quarantine.acceptedIdentitySHA256 != quarantine.conflictingIdentitySHA256,
                  acceptedIdentity == quarantine.acceptedIdentitySHA256,
                  quarantine.detectedAt.timeIntervalSinceReferenceDate.isFinite else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
        }
        let state = try requireState()
        let activeKey = "\(state.workspaceID.uuidString.lowercased()):\(state.activeReplicaID.uuidString.lowercased())"
        guard try domainRevision(state.lastLocalSequence) >= maximumSequenceByReplica[activeKey, default: 0],
              try domainRevision(state.workspaceRevision) >= maximumWorkspaceRevision,
              MutationEnvelopeV1.isSHA256(state.mutableSemanticSHA256 ?? ""),
              state.mutableSemanticSHA256 == (try mutableSemanticSHA256()) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        let revisionRows = try modelContext.fetch(FetchDescriptor<EntityMutationRevisionRow>())
        let revisionIdentities = try Set(revisionRows.map { row -> WorkspaceEntityIdentityV1 in
            guard let kind = WorkspaceEntityKindV1(rawValue: row.kind) else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            return try WorkspaceEntityIdentityV1(kind: kind, id: row.entityID)
        })
        guard Set(latestPostImageByIdentity.keys).isSubset(of: revisionIdentities) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        for row in revisionRows {
            guard let kind = WorkspaceEntityKindV1(rawValue: row.kind) else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            let entity = try WorkspaceEntityIdentityV1(kind: kind, id: row.entityID)
            let revision = try domainRevision(row.revision)
            let current = try currentPostImage(identity: entity, revision: revision)
            let validProjection: Bool
            if let external = row.externalProjectionSHA256 {
                validProjection = MutationEnvelopeV1.isSHA256(external)
                    && current.semanticSHA256 == external
            } else {
                validProjection = latestPostImageByIdentity[entity] == current
            }
            guard validProjection else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
        }
    }

    func exportSnapshot() throws -> MutationHistorySnapshotV1 {
        try validateAll()
        let state = try requireState()
        let decoded = try modelContext.fetch(FetchDescriptor<MutationReceiptRow>()).map { row in
            (row, try MutationReceiptV1.decodeCanonical(from: row.receiptData))
        }.sorted {
            let lhs = $0.1.identity
            let rhs = $1.1.identity
            return (lhs.workspaceID.rawValue.uuidString, lhs.replicaID.rawValue.uuidString, lhs.localSequence)
                < (rhs.workspaceID.rawValue.uuidString, rhs.replicaID.rawValue.uuidString, rhs.localSequence)
        }
        let receipts = decoded.map {
            MutationHistoryReceiptRecordV1(
                envelopeData: $0.0.envelopeData,
                receiptData: $0.0.receiptData,
                reversalBasisData: $0.0.reversalBasisData,
                semanticReversalData: $0.0.semanticReversalData
            )
        }
        let quarantines = try modelContext.fetch(FetchDescriptor<MutationQuarantineRow>()).sorted {
            $0.workspaceMutationKey < $1.workspaceMutationKey
        }.map {
            guard let domain = MutationQuarantineIdentityDomainV1(rawValue: $0.identityDomain) else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            return MutationHistoryQuarantineRecordV1(
                workspaceID: WorkspaceID(rawValue: $0.workspaceID),
                mutationID: $0.mutationID,
                identityDomain: domain,
                acceptedIdentitySHA256: $0.acceptedIdentitySHA256,
                conflictingIdentitySHA256: $0.conflictingIdentitySHA256,
                detectedAt: $0.detectedAt
            )
        }
        let revisions = try modelContext.fetch(FetchDescriptor<EntityMutationRevisionRow>(sortBy: [SortDescriptor(\.stableIdentity)])).map { row in
            guard let kind = WorkspaceEntityKindV1(rawValue: row.kind) else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            return MutationHistoryEntityRevisionV1(
                identity: try WorkspaceEntityIdentityV1(
                    kind: kind,
                    id: row.entityID
                ),
                revision: try domainRevision(row.revision),
                externalProjectionSHA256: row.externalProjectionSHA256
            )
        }
        return MutationHistorySnapshotV1(
            workspaceRevision: try domainRevision(state.workspaceRevision),
            lastLocalSequence: try domainRevision(state.lastLocalSequence),
            receipts: receipts,
            quarantines: quarantines,
            entityRevisions: revisions
        )
    }

    nonisolated static func validateImportedSnapshot(_ snapshot: MutationHistorySnapshotV1) throws {
        guard snapshot.schemaVersion == MutationHistorySnapshotV1.schemaVersion,
              snapshot.receipts.count <= maximumReceiptValidationCount,
              snapshot.quarantines.count <= maximumReceiptValidationCount,
              snapshot.entityRevisions.count <= MutationReceiptV1.maximumPostImageCount,
              Set(try snapshot.quarantines.map {
                  MutationWorkspaceKeyV1.value(
                    workspaceID: $0.workspaceID,
                    mutationID: try MutationIDV1(rawValue: $0.mutationID)
                  )
              }).count == snapshot.quarantines.count,
              Set(snapshot.entityRevisions.map(\.identity)).count == snapshot.entityRevisions.count else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        var mutationIDs = Set<String>()
        var receiptKeys = Set<String>()
        var sequences = Set<String>()
        var receiptsByMutation: [String: MutationReceiptV1] = [:]
        var basisByMutation: [String: ReversalBasisV1] = [:]
        var reversalsByMutation: [String: SemanticReversalReceiptV1] = [:]
        var envelopesByMutation: [String: MutationEnvelopeV1] = [:]
        var envelopeDigestByMutation: [String: String] = [:]
        var maximumPostImageRevisionByEntity: [WorkspaceEntityIdentityV1: UInt64] = [:]
        var totalPostImageCount = 0
        for record in snapshot.receipts {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
            let receipt = try MutationReceiptV1.decodeCanonical(from: record.receiptData)
            guard receipt.mutationID == envelope.mutationID,
                  receipt.envelopeSHA256 == (try envelope.canonicalSHA256()),
                  receipt.identity.workspaceID == envelope.workspaceID,
                  receipt.identity.replicaID == envelope.replicaID,
                  receipt.contentDependencyIDs == envelope.contentDependencyIDs,
                  mutationIDs.insert(MutationWorkspaceKeyV1.value(workspaceID: receipt.identity.workspaceID, mutationID: receipt.mutationID)).inserted,
                  receiptKeys.insert(receipt.identity.stableKey).inserted else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            let replicaKey = "\(receipt.identity.workspaceID.rawValue):\(receipt.identity.replicaID.rawValue)"
            let sequenceKey = "\(replicaKey):\(receipt.identity.localSequence)"
            guard sequences.insert(sequenceKey).inserted else {
                throw WorkspaceMutationFailureV1.sequenceCollision
            }
            let mutationKey = MutationWorkspaceKeyV1.value(workspaceID: receipt.identity.workspaceID, mutationID: receipt.mutationID)
            receiptsByMutation[mutationKey] = receipt
            envelopesByMutation[mutationKey] = envelope
            envelopeDigestByMutation[mutationKey] = receipt.envelopeSHA256
            guard receipt.postImages.count <= Self.maximumReceiptValidationCount - totalPostImageCount else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            totalPostImageCount += receipt.postImages.count
            for image in receipt.postImages {
                let entity = try image.identity
                maximumPostImageRevisionByEntity[entity] = max(
                    maximumPostImageRevisionByEntity[entity, default: 0],
                    image.revision
                )
            }
            if let data = record.reversalBasisData {
                let basis = try ReversalBasisV1.decodeCanonical(from: data)
                guard basis.targetMutationID == receipt.mutationID,
                      basis.targetReceiptIdentity == receipt.identity,
                      envelope.reversalPlanDigest == basis.planDigest else {
                    throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
                }
                basisByMutation[mutationKey] = basis
            } else if envelope.reversalPlanDigest != nil {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            if let data = record.semanticReversalData {
                reversalsByMutation[mutationKey] = try SemanticReversalReceiptV1.decodeCanonical(from: data)
            } else if receipt.reversesMutationID != nil {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
        }
        guard snapshot.entityRevisions.allSatisfy({ value in
            value.externalProjectionSHA256.map { MutationEnvelopeV1.isSHA256($0) } ?? true
        }) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        let projectionRevisionByEntity = Dictionary(
            uniqueKeysWithValues: snapshot.entityRevisions.map { ($0.identity, $0.revision) }
        )
        guard maximumPostImageRevisionByEntity.allSatisfy({ entity, maximumRevision in
            projectionRevisionByEntity[entity].map { $0 >= maximumRevision } ?? false
        }) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        for (mutationKey, reversal) in reversalsByMutation {
            let targetKey = MutationWorkspaceKeyV1.value(workspaceID: reversal.targetReceiptIdentity.workspaceID, mutationID: reversal.reversesMutationID)
            guard let reversalMutationReceipt = receiptsByMutation[mutationKey],
                  reversalMutationReceipt.identity == reversal.reversalReceiptIdentity,
                  reversal.resultingRevision == reversalMutationReceipt.resultingRevision,
                  reversal.compensatingMutationIDs == [reversalMutationReceipt.mutationID],
                  reversalMutationReceipt.reversesMutationID == reversal.reversesMutationID,
                  envelopesByMutation[mutationKey]?.semanticReversalExecution == (try SemanticReversalExecutionV1(
                    targetMutationID: reversal.reversesMutationID,
                    targetReceiptIdentity: reversal.targetReceiptIdentity,
                    reversalBasisSHA256: reversal.reversalBasisSHA256,
                    planDigest: reversal.planDigest,
                    compensatingMutationIDs: reversal.compensatingMutationIDs
                  )),
                  let target = receiptsByMutation[targetKey],
                  target.identity == reversal.targetReceiptIdentity,
                  let basis = basisByMutation[targetKey],
                  reversal.reversalBasisSHA256 == (try basis.canonicalSHA256()),
                  reversal.planDigest == basis.planDigest,
                  try Self.requireCompleteCompensatingReceipts(reversal, receiptsByMutation: receiptsByMutation) else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
        }
        for quarantine in snapshot.quarantines {
            let mutationKey = MutationWorkspaceKeyV1.value(
                workspaceID: quarantine.workspaceID,
                mutationID: try MutationIDV1(rawValue: quarantine.mutationID)
            )
            let acceptedIdentity: String?
            switch quarantine.identityDomain {
            case .mutationEnvelope:
                acceptedIdentity = envelopeDigestByMutation[mutationKey]
            case .semanticReversalReplayIdentity:
                acceptedIdentity = envelopesByMutation[mutationKey]?
                    .semanticReversalReplayIdentitySHA256
            }
            guard MutationEnvelopeV1.isSHA256(quarantine.acceptedIdentitySHA256),
                  MutationEnvelopeV1.isSHA256(quarantine.conflictingIdentitySHA256),
                  quarantine.acceptedIdentitySHA256 != quarantine.conflictingIdentitySHA256,
                  acceptedIdentity == quarantine.acceptedIdentitySHA256,
                  quarantine.detectedAt.timeIntervalSinceReferenceDate.isFinite else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
        }
    }

    /// Materializes imported history without minting receipts. The immutable
    /// historic receipt identities remain unchanged; clone/fork changes only
    /// the active destination state and resets its local sequence.
    func replaceHistory(
        with snapshot: MutationHistorySnapshotV1,
        identityDisposition: MutationHistoryRestoreIdentityV1
    ) throws {
        try Self.validateImportedSnapshot(snapshot)
        guard try modelContext.fetch(FetchDescriptor<MutationReceiptRow>()).isEmpty,
              try modelContext.fetch(FetchDescriptor<MutationQuarantineRow>()).isEmpty,
              try modelContext.fetch(FetchDescriptor<EntityMutationRevisionRow>()).isEmpty else {
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
        let state = try requireState()
        let destinationProjection: Bool
        switch identityDisposition {
        case .preserve:
            // Replacement is itself an authorized projection boundary: the
            // deletion-wins result can differ from either input history even
            // while workspace/replica sequence identity is preserved.
            destinationProjection = true
            guard snapshot.workspaceRevision <= UInt64(Int64.max),
                  snapshot.lastLocalSequence <= UInt64(Int64.max) else {
                throw WorkspaceMutationFailureV1.revisionOverflow
            }
            state.workspaceRevision = Int64(snapshot.workspaceRevision)
            state.lastLocalSequence = Int64(snapshot.lastLocalSequence)
        case let .destination(destination, targetGenerationID):
            destinationProjection = true
            guard destination == identity, targetGenerationID == generationID else {
                throw WorkspaceMutationFailureV1.wrongGeneration
            }
            guard snapshot.workspaceRevision <= UInt64(Int64.max) else {
                throw WorkspaceMutationFailureV1.revisionOverflow
            }
            state.workspaceRevision = Int64(snapshot.workspaceRevision)
            state.lastLocalSequence = 0
        }
        for record in snapshot.receipts {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
            let receipt = try MutationReceiptV1.decodeCanonical(from: record.receiptData)
            let basis = try record.reversalBasisData.map { try ReversalBasisV1.decodeCanonical(from: $0) }
            let reversal = try record.semanticReversalData.map { try SemanticReversalReceiptV1.decodeCanonical(from: $0) }
            modelContext.insert(try MutationReceiptRow(envelope: envelope, receipt: receipt, reversalBasis: basis, semanticReversal: reversal))
        }
        for value in snapshot.quarantines {
            modelContext.insert(MutationQuarantineRow(
                workspaceID: value.workspaceID,
                mutationID: try MutationIDV1(rawValue: value.mutationID),
                identityDomain: value.identityDomain,
                acceptedIdentitySHA256: value.acceptedIdentitySHA256,
                conflictingIdentitySHA256: value.conflictingIdentitySHA256,
                detectedAt: value.detectedAt
            ))
        }
        for value in snapshot.entityRevisions {
            let externalProjection: String?
            if destinationProjection {
                externalProjection = try currentPostImage(
                    identity: value.identity,
                    revision: value.revision
                ).semanticSHA256
            } else {
                externalProjection = value.externalProjectionSHA256
            }
            modelContext.insert(EntityMutationRevisionRow(
                identity: value.identity,
                revision: value.revision,
                externalProjectionSHA256: externalProjection
            ))
        }
        state.mutableSemanticSHA256 = try mutableSemanticSHA256()
        do {
            try validateAll()
            try saveWithMaintenanceAuthorization()
        } catch let error as WorkspaceMutationFailureV1 {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
    }

    func clearForErase(expectedWorkspaceID: WorkspaceID, expectedGenerationID: UUID) throws {
        guard expectedWorkspaceID == identity.workspaceID, expectedGenerationID == generationID else {
            throw WorkspaceMutationFailureV1.wrongGeneration
        }
        try modelContext.fetch(FetchDescriptor<MutationReceiptRow>()).forEach { modelContext.delete($0) }
        try modelContext.fetch(FetchDescriptor<MutationQuarantineRow>()).forEach { modelContext.delete($0) }
        try modelContext.fetch(FetchDescriptor<EntityMutationRevisionRow>()).forEach { modelContext.delete($0) }
        let state = try requireState()
        state.workspaceRevision = 0
        state.lastLocalSequence = 0
        state.mutableSemanticSHA256 = try mutableSemanticSHA256()
        do {
            try saveWithMaintenanceAuthorization()
        } catch let failure as WorkspaceMutationFailureV1 {
            modelContext.rollback()
            throw failure
        } catch {
            modelContext.rollback()
            throw WorkspaceMutationFailureV1.persistenceFailed
        }
    }

    /// Stages, but deliberately does not save, the semantic checkpoint after
    /// an already-authorized deletion/erase service has staged its content and
    /// deletion-ledger changes in this same ModelContext transaction.
    func stageMutableSemanticStateAfterAuthorizedExternalMutation() throws {
        let state = try requireState()
        for row in try boundedFetch(FetchDescriptor<EntityMutationRevisionRow>()) {
            guard let kind = WorkspaceEntityKindV1(rawValue: row.kind) else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            let identity = try WorkspaceEntityIdentityV1(kind: kind, id: row.entityID)
            row.externalProjectionSHA256 = try currentPostImage(
                identity: identity,
                revision: domainRevision(row.revision)
            ).semanticSHA256
        }
        state.mutableSemanticSHA256 = try mutableSemanticSHA256()
    }

    private func bootstrapOrValidateState(allowBootstrap: Bool) throws {
        let workspace = identity.workspaceID.rawValue
        let rows = try modelContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>(
            predicate: #Predicate { $0.workspaceID == workspace }
        ))
        guard rows.count <= 1 else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
        if let row = rows.first {
            guard row.generationID == generationID, row.activeReplicaID == identity.replicaID.rawValue else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            if row.mutableSemanticSHA256 == nil {
                guard allowBootstrap else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
                row.mutableSemanticSHA256 = try mutableSemanticSHA256()
                do { try saveWithMaintenanceAuthorization() } catch {
                    modelContext.rollback()
                    throw WorkspaceMutationFailureV1.persistenceFailed
                }
            }
        } else {
            guard allowBootstrap else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
            let row = WorkspaceMutationStateRow(
                workspaceID: workspace,
                generationID: generationID,
                activeReplicaID: identity.replicaID.rawValue
            )
            modelContext.insert(row)
            row.mutableSemanticSHA256 = try mutableSemanticSHA256()
            do { try saveWithMaintenanceAuthorization() } catch {
                modelContext.rollback()
                throw WorkspaceMutationFailureV1.persistenceFailed
            }
        }
    }

    /// Keeps startup recovery and every canonical journal save on the same
    /// generation mutation lock as pointer activation. Release builds reject
    /// recovery through the maintenance-only initializer.
    func withAuthorizedRecovery<Value>(
        _ operation: () throws -> Value
    ) throws -> Value {
        try withStaleWriterFence(operation)
    }

    private func saveWithStaleWriterFence() throws {
        try withStaleWriterFence {
            try modelContext.save()
        }
    }

    private func saveWithMaintenanceAuthorization() throws {
        switch accessMode {
        case .canonicalWriter:
            try saveWithStaleWriterFence()
        case .maintenanceOrTest:
            try modelContext.save()
        }
    }

    private func validateCurrentWriterLease() throws {
        switch accessMode {
        case .canonicalWriter(let staleWriterFence):
            do {
                try staleWriterFence.validateCurrent()
            } catch let failure as GenerationLeaseRegistryFailureV1 {
                throw mappedFenceFailure(failure)
            } catch {
                throw WorkspaceMutationFailureV1.persistenceFailed
            }
        case .maintenanceOrTest:
#if DEBUG
            return
#else
            throw WorkspaceMutationFailureV1.persistenceFailed
#endif
        }
    }

    private func withStaleWriterFence<Value>(
        _ operation: () throws -> Value
    ) throws -> Value {
        switch accessMode {
        case .canonicalWriter(let staleWriterFence):
            do {
                return try staleWriterFence.withAuthorizedCommit(operation)
            } catch let failure as WorkspaceMutationFailureV1 {
                throw failure
            } catch let failure as MutationJournalFailureV1 {
                throw failure
            } catch let failure as GenerationLeaseRegistryFailureV1 {
                throw mappedFenceFailure(failure)
            } catch {
                throw WorkspaceMutationFailureV1.persistenceFailed
            }
        case .maintenanceOrTest:
#if DEBUG
            return try operation()
#else
            throw WorkspaceMutationFailureV1.persistenceFailed
#endif
        }
    }

    private func mappedFenceFailure(
        _ failure: GenerationLeaseRegistryFailureV1
    ) -> WorkspaceMutationFailureV1 {
        switch failure {
        case .staleGeneration, .leaseNotActive, .wrongLeaseRole:
            return .wrongGeneration
        case .invalidContract, .invalidPath, .invalidIdentity,
                .corruptRegistry, .registryLimitExceeded, .duplicateLease,
                .uncertainOwner, .protectedDataUnavailable:
            return .persistenceFailed
        }
    }

    private func requireState() throws -> WorkspaceMutationStateRow {
        let workspace = identity.workspaceID.rawValue
        let rows = try modelContext.fetch(FetchDescriptor<WorkspaceMutationStateRow>(predicate: #Predicate { $0.workspaceID == workspace }))
        guard rows.count == 1, let row = rows.first,
              row.generationID == generationID,
              row.activeReplicaID == identity.replicaID.rawValue else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return row
    }

    private func domainRevision(_ value: Int64) throws -> UInt64 {
        guard value >= 0 else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
        return UInt64(value)
    }

    private func validate(row: MutationReceiptRow, expectedEnvelope: MutationEnvelopeV1?) throws -> MutationReceiptV1 {
        let envelope = try MutationEnvelopeV1.decodeCanonical(from: row.envelopeData)
        if case let .applySurveySession(mutation) = envelope.command {
            try validateSurveySessionReferences(mutation)
        }
        if case let .applyEvidenceContext(operation)=envelope.command{
            try validateEvidenceContextReferences(operation)
        }
        let receipt = try MutationReceiptV1.decodeCanonical(from: row.receiptData)
        guard row.mutationID == envelope.mutationID.rawValue,
              row.workspaceID == envelope.workspaceID.rawValue,
              row.workspaceMutationKey == MutationWorkspaceKeyV1.value(
                workspaceID: envelope.workspaceID,
                mutationID: envelope.mutationID
              ),
              row.commandKind == envelope.commandKind.rawValue,
              row.envelopeSHA256 == (try envelope.canonicalSHA256()),
              row.receiptSHA256 == (try receipt.canonicalSHA256()),
              receipt.mutationID == envelope.mutationID,
              receipt.envelopeSHA256 == row.envelopeSHA256,
              receipt.identity.workspaceID == envelope.workspaceID,
              receipt.identity.replicaID == envelope.replicaID,
              receipt.contentDependencyIDs == envelope.contentDependencyIDs,
              receipt.commandBodySHA256 == envelope.commandBodySHA256,
              receipt.expectedRevision == envelope.expectedRevision,
              receipt.sourceKind == envelope.sourceKind,
              receipt.causationMutationID == envelope.causationMutationID,
              receipt.correlationID == envelope.correlationID,
              row.receiptIdentity == receipt.identity.stableKey,
              expectedEnvelope.map({ $0 == envelope }) ?? true else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        if case let .applyEvidenceContext(operation)=envelope.command{
            _ = try EvidenceContextMutationReceiptV1(operation:operation,mutationReceipt:receipt)
        }
        if let basisData = row.reversalBasisData {
            let basis = try ReversalBasisV1.decodeCanonical(from: basisData)
            guard row.reversalBasisSHA256 == (try basis.canonicalSHA256()),
                  basis.targetMutationID == receipt.mutationID,
                  basis.targetReceiptIdentity == receipt.identity,
                  envelope.reversalPlanDigest == basis.planDigest else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
        } else if row.reversalBasisSHA256 != nil || envelope.reversalPlanDigest != nil {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        if let reversalData = row.semanticReversalData {
            let reversal = try SemanticReversalReceiptV1.decodeCanonical(from: reversalData)
            guard let execution = envelope.semanticReversalExecution,
                  receipt.reversesMutationID == reversal.reversesMutationID,
                  receipt.identity == reversal.reversalReceiptIdentity,
                  reversal.resultingRevision == receipt.resultingRevision,
                  execution.targetMutationID == reversal.reversesMutationID,
                  execution.targetReceiptIdentity == reversal.targetReceiptIdentity,
                  execution.reversalBasisSHA256 == reversal.reversalBasisSHA256,
                  execution.planDigest == reversal.planDigest,
                  execution.compensatingMutationIDs == reversal.compensatingMutationIDs else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
        } else if receipt.reversesMutationID != nil || envelope.semanticReversalExecution != nil {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return receipt
    }

    private func currentPostImage(
        identity: WorkspaceEntityIdentityV1,
        revision: UInt64
    ) throws -> MutationPostImageV1 {
        switch identity.kind {
        case .site:
            let id = identity.id
            let rows = try modelContext.fetch(FetchDescriptor<Site>(predicate: #Predicate { $0.id == id }))
            guard let row = try exactlyOneOrAbsent(rows) else { return try tombstone(identity, revision) }
            return try semanticPostImage(identity, revision, V4BackupSiteDTO(
                id: row.id, schemaVersion: row.schemaVersion, label: row.label,
                address: row.address, timeZoneID: row.timeZoneID,
                createdAt: row.createdAt, updatedAt: row.updatedAt
            ))
        case .asset:
            let id = identity.id
            let rows = try modelContext.fetch(FetchDescriptor<Asset>(predicate: #Predicate { $0.id == id }))
            guard let row = try exactlyOneOrAbsent(rows) else { return try tombstone(identity, revision) }
            let asset = V4BackupAssetDTO(
                id: row.id, schemaVersion: row.schemaVersion, siteID: row.siteID,
                packID: row.packID, packSchemaVersion: row.packSchemaVersion,
                packContentVersion: row.packContentVersion, label: row.label,
                createdAt: row.createdAt, updatedAt: row.updatedAt
            )
            let semantic = try AssetSemanticLifecycleAdapterV1.snapshot(
                workspaceID: identity.workspaceID,
                assetID: id,
                in: modelContext
            )
            return try semanticPostImage(
                identity,
                revision,
                AssetSemanticAssetPostImageV1(asset: asset, semantic: semantic)
            )
        case .locationNode:
            let id = identity.id
            let rows = try modelContext.fetch(FetchDescriptor<LocationNodeRow>(predicate: #Predicate { $0.id == id }))
            guard let row = try exactlyOneOrAbsent(rows) else { return try tombstone(identity, revision) }
            return try semanticPostImage(identity, revision, try row.value())
        case .assetPlacementEvent:
            let id = identity.id
            let rows = try modelContext.fetch(FetchDescriptor<AssetPlacementEventRow>(predicate: #Predicate { $0.id == id }))
            guard let row = try exactlyOneOrAbsent(rows) else { return try tombstone(identity, revision) }
            return try semanticPostImage(identity, revision, try row.value())
        case .assetCompositionEdge:
            let id = identity.id
            let rows = try modelContext.fetch(FetchDescriptor<AssetCompositionEdgeRow>(predicate: #Predicate { $0.id == id }))
            guard let row = try exactlyOneOrAbsent(rows) else { return try tombstone(identity, revision) }
            let value = try LocationPersistenceCodecV1.decode(AssetCompositionEdgeV1.self, from: row.canonicalData)
            try value.validate()
            return try semanticPostImage(identity, revision, value)
        case .assetCompositionEvent:
            let id = identity.id
            let rows = try modelContext.fetch(FetchDescriptor<AssetCompositionEventRow>(predicate: #Predicate { $0.id == id }))
            guard let row = try exactlyOneOrAbsent(rows) else { return try tombstone(identity, revision) }
            let value = try LocationPersistenceCodecV1.decode(AssetCompositionEventV1.self, from: row.canonicalData)
            try value.validate()
            return try semanticPostImage(identity, revision, value)
        case .savedSmartView:
            let id = identity.id
            let rows = try modelContext.fetch(FetchDescriptor<SavedSmartViewRowV1>(
                predicate: #Predicate { $0.id == id }
            ))
            guard let row = try exactlyOneOrAbsent(rows) else {
                return try tombstone(identity, revision)
            }
            return try semanticPostImage(identity, revision, try row.descriptor())
        case .serviceParty:
            let id = identity.id
            let rows = try modelContext.fetch(FetchDescriptor<ServicePartyRow>(predicate: #Predicate { $0.partyID == id }))
            guard let row = try exactlyOneOrAbsent(rows) else { return try tombstone(identity, revision) }
            return try semanticPostImage(identity, revision, try row.value())
        case .sitePartyRoleEvent:
            let id = identity.id
            let rows = try modelContext.fetch(FetchDescriptor<SitePartyRoleEventRow>(predicate: #Predicate { $0.eventID == id }))
            guard let row = try exactlyOneOrAbsent(rows) else { return try tombstone(identity, revision) }
            return try semanticPostImage(identity, revision, try row.value())
        case .actorSnapshot:
            let id = identity.id
            let rows = try modelContext.fetch(FetchDescriptor<ActorSnapshotRow>(predicate: #Predicate { $0.snapshotID == id }))
            guard let row = try exactlyOneOrAbsent(rows) else { return try tombstone(identity, revision) }
            return try semanticPostImage(identity, revision, try row.value())
        case .qualificationSnapshot:
            let id = identity.id
            let rows = try modelContext.fetch(FetchDescriptor<QualificationSnapshotRow>(predicate: #Predicate { $0.snapshotID == id }))
            guard let row = try exactlyOneOrAbsent(rows) else { return try tombstone(identity, revision) }
            return try semanticPostImage(identity, revision, try row.value())
        case .signoffSnapshot:
            let id = identity.id
            let rows = try modelContext.fetch(FetchDescriptor<SignoffSnapshotRow>(predicate: #Predicate { $0.snapshotID == id }))
            guard let row = try exactlyOneOrAbsent(rows) else { return try tombstone(identity, revision) }
            return try semanticPostImage(identity, revision, try row.value())
        case .authoritySourceRelease:
            let id=identity.id; let rows=try modelContext.fetch(FetchDescriptor<AuthoritySourceReleaseRow>(predicate:#Predicate{$0.releaseID == id})); guard let row=try exactlyOneOrAbsent(rows) else{return try tombstone(identity,revision)}; let v=try row.value(); guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt}; return .authoritySourceRelease(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesReleaseID),revision:revision,semanticSHA256:v.releaseSHA256)
        case .requirementBasisBinding:
            let id=identity.id; let rows=try modelContext.fetch(FetchDescriptor<RequirementBasisBindingRow>(predicate:#Predicate{$0.bindingID == id})); guard let row=try exactlyOneOrAbsent(rows) else{return try tombstone(identity,revision)}; let v=try row.value(); guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt}; return .requirementBasisBinding(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesBindingID),revision:revision,semanticSHA256:v.bindingSHA256)
        case .applicabilityContextSnapshot:
            let id=identity.id; let rows=try modelContext.fetch(FetchDescriptor<ApplicabilityContextSnapshotRow>(predicate:#Predicate{$0.snapshotID == id})); guard let row=try exactlyOneOrAbsent(rows) else{return try tombstone(identity,revision)}; let v=try row.value(); guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt}; return .applicabilityContextSnapshot(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesSnapshotID),revision:revision,semanticSHA256:v.snapshotSHA256)
        case .assessmentScopeSnapshot:
            let id=identity.id; let rows=try modelContext.fetch(FetchDescriptor<AssessmentScopeSnapshotRow>(predicate:#Predicate{$0.snapshotID == id})); guard let row=try exactlyOneOrAbsent(rows) else{return try tombstone(identity,revision)}; let v=try row.value(); guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt}; return .assessmentScopeSnapshot(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesSnapshotID),revision:revision,semanticSHA256:v.snapshotSHA256)
        case .severityScaleRelease:
            let id=identity.id; let rows=try modelContext.fetch(FetchDescriptor<SeverityScaleReleaseRow>(predicate:#Predicate{$0.releaseID == id})); guard let row=try exactlyOneOrAbsent(rows) else{return try tombstone(identity,revision)}; let v=try row.value(); guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt}; return .severityScaleRelease(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesReleaseID),revision:revision,semanticSHA256:v.releaseSHA256)
        case .findingClassificationBinding:
            let id=identity.id; let rows=try modelContext.fetch(FetchDescriptor<FindingClassificationBindingRow>(predicate:#Predicate{$0.bindingID == id})); guard let row=try exactlyOneOrAbsent(rows) else{return try tombstone(identity,revision)}; let v=try row.value(); guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt}; return .findingClassificationBinding(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesBindingID),revision:revision,semanticSHA256:v.bindingSHA256)
        case .measurementProtocolRelease:
            let id=identity.id; let rows=try modelContext.fetch(FetchDescriptor<MeasurementProtocolReleaseRow>(predicate:#Predicate{$0.releaseID == id})); guard let row=try exactlyOneOrAbsent(rows) else{return try tombstone(identity,revision)}; let v=try row.value(); guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt}; return .measurementProtocolRelease(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesReleaseID),revision:revision,semanticSHA256:v.releaseSHA256)
        case .derivedFactEvaluatorDescriptor:
            let id=identity.id; let rows=try modelContext.fetch(FetchDescriptor<DerivedFactEvaluatorDescriptorRow>(predicate:#Predicate{$0.descriptorID == id})); guard let row=try exactlyOneOrAbsent(rows) else{return try tombstone(identity,revision)}; let v=try row.value(); guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt}; return .derivedFactEvaluatorDescriptor(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesDescriptorID),revision:revision,semanticSHA256:v.descriptorSHA256)
        case .derivedFactProvenance:
            let id=identity.id; let rows=try modelContext.fetch(FetchDescriptor<DerivedFactProvenanceRow>(predicate:#Predicate{$0.provenanceID == id})); guard let row=try exactlyOneOrAbsent(rows) else{return try tombstone(identity,revision)}; let v=try row.value(); guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt}; return .derivedFactProvenance(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.predecessorProvenanceID),revision:revision,semanticSHA256:v.provenanceSHA256)
        case .functionalRelationshipTypeDescriptor:
            let id = identity.id
            let rows = try modelContext.fetch(FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>(predicate: #Predicate { $0.descriptorReleaseID == id }))
            guard let row = try exactlyOneOrAbsent(rows) else { return try tombstone(identity, revision) }
            let value = try row.value(); guard value.revision == revision else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
            return .functionalRelationshipTypeDescriptor(id: id, concurrencyIdentity: try authorityConcurrency(identity, value.supersedesDescriptorReleaseID), revision: revision, semanticSHA256: value.descriptorSHA256)
        case .assetFunctionalRelationshipEvent:
            let id = identity.id
            let rows = try modelContext.fetch(FetchDescriptor<AssetFunctionalRelationshipEventRow>(predicate: #Predicate { $0.eventID == id }))
            guard let row = try exactlyOneOrAbsent(rows) else { return try tombstone(identity, revision) }
            let value = try row.value(); guard value.revision == revision else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
            return .assetFunctionalRelationshipEvent(id: id, relationshipID: value.relationshipID, concurrencyIdentity: try authorityConcurrency(identity, value.predecessorEventID), revision: revision, semanticSHA256: value.eventSHA256)
        case .evidenceVisibility:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<EvidenceVisibilityRow>(predicate:#Predicate{$0.visibilityID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .evidenceVisibility(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesVisibilityID),revision:revision,semanticSHA256:v.visibilitySHA256)
        case .claimEvidenceLink:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<ClaimEvidenceLinkRow>(predicate:#Predicate{$0.linkID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .claimEvidenceLink(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesLinkID),revision:revision,semanticSHA256:v.linkSHA256)
        case .assuranceManifest:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<AssuranceManifestRow>(predicate:#Predicate{$0.manifestID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .assuranceManifest(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesManifestID),revision:revision,semanticSHA256:v.manifestSHA256)
        case .attestation:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<AttestationRow>(predicate:#Predicate{$0.attestationID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .attestation(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesAttestationID),revision:revision,semanticSHA256:v.attestationSHA256)
        case .inspectionReviewTransition:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<InspectionReviewTransitionRow>(predicate:#Predicate{$0.transitionID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .inspectionReviewTransition(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.predecessorTransitionID),revision:revision,semanticSHA256:v.transitionSHA256)
        case .reviewDisposition:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<ReviewDispositionRow>(predicate:#Predicate{$0.dispositionID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .reviewDisposition(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesDispositionID),revision:revision,semanticSHA256:v.dispositionSHA256)
        case .changeRequest:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<ChangeRequestRow>(predicate:#Predicate{$0.requestRevisionID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .changeRequest(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesRequestRevisionID),revision:revision,semanticSHA256:v.requestSHA256)
        case .correctiveActionPolicy:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<CorrectiveActionPolicyRow>(predicate:#Predicate{$0.releaseID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .correctiveActionPolicy(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesReleaseID),revision:revision,semanticSHA256:v.policySHA256)
        case .correctiveActionEvent:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<CorrectiveActionEventRow>(predicate:#Predicate{$0.eventID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .correctiveActionEvent(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.predecessorEventID),revision:revision,semanticSHA256:v.eventSHA256)
        case .workPacketManifest:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<WorkPacketManifestRow>(predicate:#Predicate{$0.manifestID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .workPacketManifest(id:id,concurrencyIdentity:identity,revision:revision,semanticSHA256:v.manifestSHA256)
        case .workItemClaim:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<WorkItemClaimRow>(predicate:#Predicate{$0.claimID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .workItemClaim(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesClaimID),revision:revision,semanticSHA256:v.claimSHA256)
        case .workLease:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<WorkLeaseRow>(predicate:#Predicate{$0.leaseID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .workLease(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesLeaseID),revision:revision,semanticSHA256:v.leaseSHA256)
        case .workRelease:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<WorkReleaseRow>(predicate:#Predicate{$0.releaseID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .workRelease(id:id,concurrencyIdentity:identity,revision:revision,semanticSHA256:v.releaseSHA256)
        case .workHandoff:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<WorkHandoffRow>(predicate:#Predicate{$0.handoffID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .workHandoff(id:id,concurrencyIdentity:identity,revision:revision,semanticSHA256:v.handoffSHA256)
        case .fieldDraftCheckpoint:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<FieldDraftCheckpointRow>(predicate:#Predicate{$0.draftID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.draftRevision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .fieldDraftCheckpoint(id:id,concurrencyIdentity:identity,revision:revision,semanticSHA256:v.checkpointSHA256)
        case .attachmentStagingItem:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<AttachmentStagingItemRow>(predicate:#Predicate{$0.stageID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .attachmentStagingItem(id:id,concurrencyIdentity:identity,revision:revision,semanticSHA256:v.stageSHA256)
        case .draftCommitSaga:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<DraftCommitSagaRow>(predicate:#Predicate{$0.sagaID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .draftCommitSaga(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.predecessorSagaID),revision:revision,semanticSHA256:v.sagaSHA256)
        case .draftContentReservation:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<DraftContentReservationRow>(predicate:#Predicate{$0.reservationID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .draftContentReservation(id:id,concurrencyIdentity:identity,revision:revision,semanticSHA256:v.reservationSHA256)
        case .draftCommitReceipt:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<DraftCommitReceiptRow>(predicate:#Predicate{$0.receiptID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .draftCommitReceipt(id:id,concurrencyIdentity:identity,revision:revision,semanticSHA256:v.receiptSHA256)
        case .draftDiscardReceipt:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<DraftDiscardReceiptRow>(predicate:#Predicate{$0.receiptID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .draftDiscardReceipt(id:id,concurrencyIdentity:identity,revision:revision,semanticSHA256:v.receiptSHA256)
        case .promotedPackageRelease:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<PromotedPackageReleaseRow>(predicate:#Predicate{$0.releaseRecordID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .promotedPackageRelease(id:id,concurrencyIdentity:identity,revision:revision,semanticSHA256:v.releaseRecordSHA256)
        case .packageSandboxRun:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<PackageSandboxRunRow>(predicate:#Predicate{$0.runID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .packageSandboxRun(id:id,concurrencyIdentity:identity,revision:revision,semanticSHA256:v.runSHA256)
        case .packagePromotionReceipt:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<PackagePromotionReceiptRow>(predicate:#Predicate{$0.receiptID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .packagePromotionReceipt(id:id,concurrencyIdentity:identity,revision:revision,semanticSHA256:v.receiptSHA256)
        case .activePackageRegistryPointer:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<ActivePackageRegistryPointerRow>(predicate:#Predicate{$0.pointerID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .activePackageRegistryPointer(id:id,concurrencyIdentity:identity,revision:revision,semanticSHA256:v.pointerSHA256)
        case .instrumentReference:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<InstrumentReferenceRow>(predicate:#Predicate{$0.referenceID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .instrumentReference(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesReferenceID),revision:revision,semanticSHA256:v.referenceSHA256)
        case .calibrationStatusSnapshot:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<CalibrationStatusSnapshotRow>(predicate:#Predicate{$0.snapshotID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .calibrationStatusSnapshot(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesSnapshotID),revision:revision,semanticSHA256:v.snapshotSHA256)
        case .measurementCapture:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<MeasurementCaptureRow>(predicate:#Predicate{$0.captureID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .measurementCapture(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesCaptureID),revision:revision,semanticSHA256:v.captureSHA256)
        case .measurementSeries:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<MeasurementSeriesRow>(predicate:#Predicate{$0.snapshotID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .measurementSeries(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesSnapshotID),revision:revision,semanticSHA256:v.seriesSHA256)
        case .measurementQualityAssessment:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<MeasurementQualityAssessmentRow>(predicate:#Predicate{$0.assessmentID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .measurementQualityAssessment(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesAssessmentID),revision:revision,semanticSHA256:v.assessmentSHA256)
        case .privacyTransformPolicy:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<PrivacyTransformPolicyRow>(predicate:#Predicate{$0.policyID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .privacyTransformPolicy(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesPolicyID),revision:revision,semanticSHA256:v.policySHA256)
        case .privacyRegion:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<PrivacyRegionRow>(predicate:#Predicate{$0.regionID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .privacyRegion(id:id,concurrencyIdentity:identity,revision:revision,semanticSHA256:v.regionSHA256)
        case .privacyTransformManifest:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<PrivacyTransformManifestRow>(predicate:#Predicate{$0.manifestID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try privacyManifestValue(row);guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .privacyTransformManifest(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesManifestID),revision:revision,semanticSHA256:v.manifestSHA256)
        case .privacyReviewReceipt:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<PrivacyReviewReceiptRow>(predicate:#Predicate{$0.receiptID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try privacyReviewValue(row);guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .privacyReviewReceipt(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesReceiptID),revision:revision,semanticSHA256:v.receiptSHA256)
        case .clientCapabilityProfile:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<ClientCapabilityProfileRow>(predicate:#Predicate{$0.profileID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .clientCapabilityProfile(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesProfileID),revision:revision,semanticSHA256:v.profileSHA256)
        case .packageLifecyclePolicy:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<PackageLifecyclePolicyRow>(predicate:#Predicate{$0.policyID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let release=try clientCapabilityRelease(row.packageReleaseID),v=try row.value(release:release);guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .packageLifecyclePolicy(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesPolicyID),revision:revision,semanticSHA256:v.policySHA256)
        case .packageLifecycleDisposition:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<PackageLifecycleDispositionRow>(predicate:#Predicate{$0.dispositionID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let release=try clientCapabilityRelease(row.packageReleaseID),v=try row.value(release:release);guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .packageLifecycleDisposition(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesDispositionID),revision:revision,semanticSHA256:v.dispositionSHA256)
        case .clientCapabilityAdmissionDecision:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<ClientCapabilityAdmissionDecisionRow>(predicate:#Predicate{$0.decisionID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try clientCapabilityDecision(row);guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .clientCapabilityAdmissionDecision(id:id,concurrencyIdentity:identity,revision:revision,semanticSHA256:v.decisionSHA256)
        case .fieldReferenceRelease:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<FieldReferenceReleaseRow>(predicate:#Predicate{$0.releaseID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .fieldReferenceRelease(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesReleaseID),revision:revision,semanticSHA256:v.releaseSHA256)
        case .fieldReferenceBinding:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<FieldReferenceBindingRow>(predicate:#Predicate{$0.bindingID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let releaseID=row.releaseID,releases=try modelContext.fetch(FetchDescriptor<FieldReferenceReleaseRow>(predicate:#Predicate{$0.releaseID==releaseID}));guard let releaseRow=try exactlyOneOrAbsent(releases)else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};let release=try releaseRow.value(),v=try row.value(release:release);guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .fieldReferenceBinding(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesBindingID),revision:revision,semanticSHA256:v.bindingSHA256)
        case .accessibleDocumentAssessmentReceipt:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<AccessibleDocumentAssessmentReceiptRow>(predicate:#Predicate{$0.receiptID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .accessibleDocumentAssessmentReceipt(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesReceiptID),revision:revision,semanticSHA256:v.receiptSHA256)
        case .surveyDefinitionIdentity:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<SurveyDefinitionIdentityRow>(predicate:#Predicate{$0.definitionID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .surveyDefinitionIdentity(id:id,concurrencyIdentity:identity,revision:revision,semanticSHA256:v.identitySHA256)
        case .surveyDefinitionRelease:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<SurveyDefinitionReleaseRow>(predicate:#Predicate{$0.releaseID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .surveyDefinitionRelease(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesReleaseID),revision:revision,semanticSHA256:v.releaseSHA256)
        case .surveySession:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<SurveySessionRow>(predicate:#Predicate{$0.sessionID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .surveySession(id:id,concurrencyIdentity:identity,revision:revision,semanticSHA256:v.sessionSHA256)
        case .factCapture:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<FactCaptureRow>(predicate:#Predicate{$0.captureID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};let predecessor=v.predecessors.first?.captureID;return .factCapture(id:id,concurrencyIdentity:try authorityConcurrency(identity,predecessor),revision:revision,semanticSHA256:v.captureSHA256)
        case .provisionalSubject:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<ProvisionalSubjectRow>(predicate:#Predicate{$0.provisionalSubjectID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .provisionalSubject(id:id,concurrencyIdentity:identity,revision:revision,semanticSHA256:v.subjectSHA256)
        case .subjectPromotionReceipt:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<SubjectPromotionReceiptRow>(predicate:#Predicate{$0.receiptID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .subjectPromotionReceipt(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.predecessorReceiptID),revision:revision,semanticSHA256:v.receiptSHA256)
        case .surveyPublicationSnapshot:let id=identity.id;let r=try modelContext.fetch(FetchDescriptor<SurveyPublicationSnapshotRow>(predicate:#Predicate{$0.snapshotID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .surveyPublicationSnapshot(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.supersedesSnapshotID),revision:revision,semanticSHA256:v.snapshotSHA256)
        case .assetLocator:let id=identity.id,r=try modelContext.fetch(FetchDescriptor<AssetLocatorRow>(predicate:#Predicate{$0.locatorID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .assetLocator(id:id,concurrencyIdentity:identity,revision:revision,semanticSHA256:v.locatorSHA256)
        case .locatorBindingReceipt:let id=identity.id,r=try modelContext.fetch(FetchDescriptor<LocatorBindingReceiptRow>(predicate:#Predicate{$0.receiptID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return .locatorBindingReceipt(id:id,concurrencyIdentity:try authorityConcurrency(identity,v.predecessorReceiptID),revision:revision,semanticSHA256:v.receiptSHA256)
        case .evidenceContext:let id=identity.id,r=try modelContext.fetch(FetchDescriptor<EvidenceContextRow>(predicate:#Predicate{$0.contextID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};var predecessor:UUID?=nil;if let digest=v.predecessorContextSHA256{let matches=try modelContext.fetch(FetchDescriptor<EvidenceContextRow>()).map{try $0.value()}.filter{$0.contextSHA256==digest};guard matches.count==1 else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};predecessor=matches[0].contextID};return .evidenceContext(id:id,concurrencyIdentity:try authorityConcurrency(identity,predecessor),revision:revision,semanticSHA256:v.contextSHA256)
        case .pairedObservationLink:let id=identity.id,r=try modelContext.fetch(FetchDescriptor<PairedObservationLinkRow>(predicate:#Predicate{$0.linkID==id}));guard let row=try exactlyOneOrAbsent(r)else{return try tombstone(identity,revision)};let v=try row.value();guard v.revision==revision else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};var predecessor:UUID?=nil;if let digest=v.predecessorLinkSHA256{let matches=try modelContext.fetch(FetchDescriptor<PairedObservationLinkRow>()).map{try $0.value()}.filter{$0.linkSHA256==digest};guard matches.count==1 else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};predecessor=matches[0].linkID};return .pairedObservationLink(id:id,concurrencyIdentity:try authorityConcurrency(identity,predecessor),revision:revision,semanticSHA256:v.linkSHA256)
        case .workflowRecord:
            let id = identity.id
            let rows = try modelContext.fetch(FetchDescriptor<WorkflowRecord>(predicate: #Predicate { $0.id == id }))
            guard let row = try exactlyOneOrAbsent(rows) else { return try tombstone(identity, revision) }
            let observationAndTime = try ObservationAndTimeRowStoreV1.requireRow(
                recordID: id,
                in: modelContext
            )
            var assuranceDescriptor = FetchDescriptor<RequirementAssuranceRow>(
                predicate: #Predicate { $0.workflowRecordID == id }
            )
            assuranceDescriptor.fetchLimit = 2
            let assuranceRows = try modelContext.fetch(assuranceDescriptor)
            guard assuranceRows.count <= 1 else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            let recordDTO = V4BackupWorkflowRecordDTO(
                id: row.id, schemaVersion: row.schemaVersion, assetID: row.assetID,
                packetID: row.packetID, issueID: row.issueID, parentRecordID: row.parentRecordID,
                recordRevisionRootID: row.recordRevisionRootID, revisesRecordID: row.revisesRecordID,
                evidenceSourceRecordID: row.evidenceSourceRecordID, revisionKind: row.revisionKind,
                stage: row.stage, state: row.state, draftStepKey: row.draftStepKey,
                startedAt: row.startedAt, completedAt: row.completedAt,
                observedAtUTC: row.observedAtUTC, timeZoneID: row.timeZoneID,
                utcOffsetMinutes: row.utcOffsetMinutes, localDate: row.localDate,
                localTime: row.localTime,
                afterDarkAcknowledgementKey: row.afterDarkAcknowledgementKey,
                afterDarkAcknowledgementCopy: row.afterDarkAcknowledgementCopy,
                afterDarkAcknowledgementVersion: row.afterDarkAcknowledgementVersion,
                afterDarkAcknowledgementAccepted: row.afterDarkAcknowledgementAccepted,
                safePositionAcknowledgementKey: row.safePositionAcknowledgementKey,
                safePositionAcknowledgementCopy: row.safePositionAcknowledgementCopy,
                safePositionAcknowledgementVersion: row.safePositionAcknowledgementVersion,
                safePositionAcknowledgementAccepted: row.safePositionAcknowledgementAccepted,
                packID: row.packID, packSchemaVersion: row.packSchemaVersion,
                packContentVersion: row.packContentVersion, pdfTemplateID: row.pdfTemplateID,
                pdfTemplateVersion: row.pdfTemplateVersion, outcomeKey: row.outcomeKey,
                couldNotVerifyKey: row.couldNotVerifyKey,
                couldNotVerifyDisplaySnapshot: row.couldNotVerifyDisplaySnapshot,
                couldNotVerifyRegistryVersion: row.couldNotVerifyRegistryVersion,
                workPerformedLocalDate: row.workPerformedLocalDate,
                workDescription: row.workDescription, note: row.note,
                finalizationMutationID: row.finalizationMutationID,
                observationBasisV1Data: observationAndTime.observationBasisV1Data,
                temporalContextV1Data: observationAndTime.temporalContextV1Data
            )
            return try semanticPostImage(identity, revision, WorkflowRecordPostImageV8(
                record: recordDTO,
                requirementAssurance: try assuranceRows.first?.snapshot()
            ))
        case .evidenceFile:
            let id = identity.id
            let rows = try modelContext.fetch(FetchDescriptor<EvidenceFile>(predicate: #Predicate { $0.id == id }))
            guard let row = try exactlyOneOrAbsent(rows) else { return try tombstone(identity, revision) }
            return try semanticPostImage(identity, revision, V4BackupEvidenceFileDTO(
                id: row.id, schemaVersion: row.schemaVersion, recordID: row.recordID,
                purposeKey: row.purposeKey, relativePath: row.relativePath,
                mimeType: row.mimeType, byteCount: row.byteCount, sha256: row.sha256,
                createdAt: row.createdAt, thumbnailRelativePath: row.thumbnailRelativePath,
                thumbnailByteCount: row.thumbnailByteCount, thumbnailSHA256: row.thumbnailSHA256
            ))
        case .issue:
            let id = identity.id
            let rows = try modelContext.fetch(FetchDescriptor<Issue>(predicate: #Predicate { $0.id == id }))
            guard let row = try exactlyOneOrAbsent(rows) else { return try tombstone(identity, revision) }
            return try semanticPostImage(identity, revision, V4BackupIssueDTO(
                id: row.id, schemaVersion: row.schemaVersion, assetID: row.assetID,
                openedByRecordID: row.openedByRecordID, labelKey: row.labelKey,
                labelDisplaySnapshot: row.labelDisplaySnapshot, status: row.status,
                resolvedByRecordID: row.resolvedByRecordID, createdAt: row.createdAt,
                updatedAt: row.updatedAt
            ))
        case .packet:
            let id = identity.id
            let rows = try modelContext.fetch(FetchDescriptor<Packet>(predicate: #Predicate { $0.id == id }))
            guard let row = try exactlyOneOrAbsent(rows) else { return try tombstone(identity, revision) }
            return try semanticPostImage(identity, revision, V4BackupPacketDTO(
                id: row.id, schemaVersion: row.schemaVersion, stableRootID: row.stableRootID,
                currentRecordID: row.currentRecordID, evaluationCounted: row.evaluationCounted,
                contentDeletedAt: row.contentDeletedAt, createdAt: row.createdAt
            ))
        case .report:
            let id = identity.id
            let rows = try modelContext.fetch(FetchDescriptor<Report>(predicate: #Predicate { $0.id == id }))
            guard let row = try exactlyOneOrAbsent(rows) else { return try tombstone(identity, revision) }
            return try semanticPostImage(identity, revision, V4BackupReportDTO(
                id: row.id, schemaVersion: row.schemaVersion, packetID: row.packetID,
                sourceRecordID: row.sourceRecordID, snapshotSchemaVersion: row.snapshotSchemaVersion,
                snapshotRelativePath: row.snapshotRelativePath, snapshotSHA256: row.snapshotSHA256,
                pdfState: row.pdfState, pdfRelativePath: row.pdfRelativePath,
                pdfSHA256: row.pdfSHA256, createdAt: row.createdAt,
                replacesReportID: row.replacesReportID
            ))
        case .deletionLedgerEntry:
            var descriptor = FetchDescriptor<DeletionLedgerRow>()
            descriptor.fetchLimit = DeletionLedgerV2.maximumEntryCount + 1
            let matches = try modelContext.fetch(descriptor).compactMap { row -> DeletionLedgerEntryV2? in
                let deletionIdentity = try DeletionIdentityV2(typedID: row.typedID)
                guard deletionIdentity.id == identity.id else { return nil }
                return try DeletionLedgerEntryV2(
                    identity: deletionIdentity,
                    deletedAt: row.deletedAt,
                    schemaVersion: row.schemaVersion
                )
            }
            guard let entry = try exactlyOneOrAbsent(matches) else { return try tombstone(identity, revision) }
            return try semanticPostImage(identity, revision, entry)
        }
    }

    private func mutableSemanticSHA256() throws -> String {
        let revisionRows = try boundedFetch(FetchDescriptor<EntityMutationRevisionRow>())
        var revisionByIdentity: [String: UInt64] = [:]
        for row in revisionRows {
            guard revisionByIdentity[row.stableIdentity] == nil else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            revisionByIdentity[row.stableIdentity] = try domainRevision(row.revision)
        }
        var identities: [WorkspaceEntityIdentityV1] = []
        identities += try boundedFetch(FetchDescriptor<Site>()).map { try .init(kind: .site, id: $0.id) }
        identities += try boundedFetch(FetchDescriptor<Asset>()).map { try .init(kind: .asset, id: $0.id) }
        identities += try boundedFetch(FetchDescriptor<LocationNodeRow>()).map { try .init(kind: .locationNode, id: $0.id) }
        identities += try boundedFetch(FetchDescriptor<AssetPlacementEventRow>()).map { try .init(kind: .assetPlacementEvent, id: $0.id) }
        identities += try boundedFetch(FetchDescriptor<AssetCompositionEdgeRow>()).map { try .init(kind: .assetCompositionEdge, id: $0.id) }
        identities += try boundedFetch(FetchDescriptor<AssetCompositionEventRow>()).map { try .init(kind: .assetCompositionEvent, id: $0.id) }
        identities += try boundedFetch(FetchDescriptor<WorkflowRecord>()).map { try .init(kind: .workflowRecord, id: $0.id) }
        identities += try boundedFetch(FetchDescriptor<EvidenceFile>()).map { try .init(kind: .evidenceFile, id: $0.id) }
        identities += try boundedFetch(FetchDescriptor<Issue>()).map { try .init(kind: .issue, id: $0.id) }
        identities += try boundedFetch(FetchDescriptor<Packet>()).map { try .init(kind: .packet, id: $0.id) }
        identities += try boundedFetch(FetchDescriptor<Report>()).map { try .init(kind: .report, id: $0.id) }
        identities += try boundedFetch(FetchDescriptor<AuthoritySourceReleaseRow>()).map { try .init(kind: .authoritySourceRelease, id: $0.releaseID) }
        identities += try boundedFetch(FetchDescriptor<RequirementBasisBindingRow>()).map { try .init(kind: .requirementBasisBinding, id: $0.bindingID) }
        identities += try boundedFetch(FetchDescriptor<ApplicabilityContextSnapshotRow>()).map { try .init(kind: .applicabilityContextSnapshot, id: $0.snapshotID) }
        identities += try boundedFetch(FetchDescriptor<AssessmentScopeSnapshotRow>()).map { try .init(kind: .assessmentScopeSnapshot, id: $0.snapshotID) }
        identities += try boundedFetch(FetchDescriptor<SeverityScaleReleaseRow>()).map { try .init(kind: .severityScaleRelease, id: $0.releaseID) }
        identities += try boundedFetch(FetchDescriptor<FindingClassificationBindingRow>()).map { try .init(kind: .findingClassificationBinding, id: $0.bindingID) }
        identities += try boundedFetch(FetchDescriptor<MeasurementProtocolReleaseRow>()).map { try .init(kind: .measurementProtocolRelease, id: $0.releaseID) }
        identities += try boundedFetch(FetchDescriptor<DerivedFactEvaluatorDescriptorRow>()).map { try .init(kind: .derivedFactEvaluatorDescriptor, id: $0.descriptorID) }
        identities += try boundedFetch(FetchDescriptor<DerivedFactProvenanceRow>()).map { try .init(kind: .derivedFactProvenance, id: $0.provenanceID) }
        identities += try boundedFetch(FetchDescriptor<FunctionalRelationshipTypeDescriptorRow>()).map { try .init(kind: .functionalRelationshipTypeDescriptor, id: $0.descriptorReleaseID) }
        identities += try boundedFetch(FetchDescriptor<AssetFunctionalRelationshipEventRow>()).map { try .init(kind: .assetFunctionalRelationshipEvent, id: $0.eventID) }
        identities += try boundedFetch(FetchDescriptor<EvidenceVisibilityRow>()).map{try .init(kind:.evidenceVisibility,id:$0.visibilityID)}
        identities += try boundedFetch(FetchDescriptor<ClaimEvidenceLinkRow>()).map{try .init(kind:.claimEvidenceLink,id:$0.linkID)}
        identities += try boundedFetch(FetchDescriptor<AssuranceManifestRow>()).map{try .init(kind:.assuranceManifest,id:$0.manifestID)}
        identities += try boundedFetch(FetchDescriptor<AttestationRow>()).map{try .init(kind:.attestation,id:$0.attestationID)}
        identities += try boundedFetch(FetchDescriptor<InspectionReviewTransitionRow>()).map{try .init(kind:.inspectionReviewTransition,id:$0.transitionID)}
        identities += try boundedFetch(FetchDescriptor<ReviewDispositionRow>()).map{try .init(kind:.reviewDisposition,id:$0.dispositionID)}
        identities += try boundedFetch(FetchDescriptor<ChangeRequestRow>()).map{try .init(kind:.changeRequest,id:$0.requestRevisionID)}
        identities += try boundedFetch(FetchDescriptor<CorrectiveActionPolicyRow>()).map{try .init(kind:.correctiveActionPolicy,id:$0.releaseID)}
        identities += try boundedFetch(FetchDescriptor<CorrectiveActionEventRow>()).map{try .init(kind:.correctiveActionEvent,id:$0.eventID)}
        identities += try boundedFetch(FetchDescriptor<WorkPacketManifestRow>()).map{try .init(kind:.workPacketManifest,id:$0.manifestID)}
        identities += try boundedFetch(FetchDescriptor<WorkItemClaimRow>()).map{try .init(kind:.workItemClaim,id:$0.claimID)}
        identities += try boundedFetch(FetchDescriptor<WorkLeaseRow>()).map{try .init(kind:.workLease,id:$0.leaseID)}
        identities += try boundedFetch(FetchDescriptor<WorkReleaseRow>()).map{try .init(kind:.workRelease,id:$0.releaseID)}
        identities += try boundedFetch(FetchDescriptor<WorkHandoffRow>()).map{try .init(kind:.workHandoff,id:$0.handoffID)}
        identities += try boundedFetch(FetchDescriptor<FieldDraftCheckpointRow>()).map{try .init(kind:.fieldDraftCheckpoint,id:$0.draftID)}
        identities += try boundedFetch(FetchDescriptor<AttachmentStagingItemRow>()).map{try .init(kind:.attachmentStagingItem,id:$0.stageID)}
        identities += try boundedFetch(FetchDescriptor<DraftCommitSagaRow>()).map{try .init(kind:.draftCommitSaga,id:$0.sagaID)}
        identities += try boundedFetch(FetchDescriptor<DraftContentReservationRow>()).map{try .init(kind:.draftContentReservation,id:$0.reservationID)}
        identities += try boundedFetch(FetchDescriptor<DraftCommitReceiptRow>()).map{try .init(kind:.draftCommitReceipt,id:$0.receiptID)}
        identities += try boundedFetch(FetchDescriptor<DraftDiscardReceiptRow>()).map{try .init(kind:.draftDiscardReceipt,id:$0.receiptID)}
        identities += try boundedFetch(FetchDescriptor<PromotedPackageReleaseRow>()).map{try .init(kind:.promotedPackageRelease,id:$0.releaseRecordID)}
        identities += try boundedFetch(FetchDescriptor<PackageSandboxRunRow>()).map{try .init(kind:.packageSandboxRun,id:$0.runID)}
        identities += try boundedFetch(FetchDescriptor<PackagePromotionReceiptRow>()).map{try .init(kind:.packagePromotionReceipt,id:$0.receiptID)}
        identities += try boundedFetch(FetchDescriptor<ActivePackageRegistryPointerRow>()).map{try .init(kind:.activePackageRegistryPointer,id:$0.pointerID)}
        identities += try boundedFetch(FetchDescriptor<InstrumentReferenceRow>()).map{try .init(kind:.instrumentReference,id:$0.referenceID)}
        identities += try boundedFetch(FetchDescriptor<CalibrationStatusSnapshotRow>()).map{try .init(kind:.calibrationStatusSnapshot,id:$0.snapshotID)}
        identities += try boundedFetch(FetchDescriptor<MeasurementCaptureRow>()).map{try .init(kind:.measurementCapture,id:$0.captureID)}
        identities += try boundedFetch(FetchDescriptor<MeasurementSeriesRow>()).map{try .init(kind:.measurementSeries,id:$0.snapshotID)}
        identities += try boundedFetch(FetchDescriptor<MeasurementQualityAssessmentRow>()).map{try .init(kind:.measurementQualityAssessment,id:$0.assessmentID)}
        identities += try boundedFetch(FetchDescriptor<PrivacyTransformPolicyRow>()).map{try .init(kind:.privacyTransformPolicy,id:$0.policyID)}
        identities += try boundedFetch(FetchDescriptor<PrivacyRegionRow>()).map{try .init(kind:.privacyRegion,id:$0.regionID)}
        identities += try boundedFetch(FetchDescriptor<PrivacyTransformManifestRow>()).map{try .init(kind:.privacyTransformManifest,id:$0.manifestID)}
        identities += try boundedFetch(FetchDescriptor<PrivacyReviewReceiptRow>()).map{try .init(kind:.privacyReviewReceipt,id:$0.receiptID)}
        identities += try boundedFetch(FetchDescriptor<ClientCapabilityProfileRow>()).map{try .init(kind:.clientCapabilityProfile,id:$0.profileID)}
        identities += try boundedFetch(FetchDescriptor<ClientCapabilityAdmissionDecisionRow>()).map{try .init(kind:.clientCapabilityAdmissionDecision,id:$0.decisionID)}
        identities += try boundedFetch(FetchDescriptor<PackageLifecyclePolicyRow>()).map{try .init(kind:.packageLifecyclePolicy,id:$0.policyID)}
        identities += try boundedFetch(FetchDescriptor<PackageLifecycleDispositionRow>()).map{try .init(kind:.packageLifecycleDisposition,id:$0.dispositionID)}
        identities += try boundedFetch(FetchDescriptor<EvidenceContextRow>()).map{try .init(kind:.evidenceContext,id:$0.contextID)}
        identities += try boundedFetch(FetchDescriptor<PairedObservationLinkRow>()).map{try .init(kind:.pairedObservationLink,id:$0.linkID)}
        guard identities.count <= Self.maximumMutableContentValidationCount,
              Set(identities).count == identities.count else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        let items = try identities.map { entity -> MutableSemanticItem in
            let revision = revisionByIdentity[entity.stableKey, default: 0]
            let image = try currentPostImage(identity: entity, revision: revision)
            return MutableSemanticItem(
                stableIdentity: entity.stableKey,
                revision: revision,
                semanticSHA256: image.semanticSHA256
            )
        }.sorted { $0.stableIdentity < $1.stableIdentity }
        let ledger = try DeletionLedgerStore(context: modelContext).snapshot()
        return try WorkspaceMutationCanonicalV1.sha256(
            MutableSemanticDigestBasis(content: items, deletionLedger: ledger)
        )
    }

    private func boundedFetch<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) throws -> [Model] {
        var bounded = descriptor
        bounded.fetchLimit = Self.maximumMutableContentValidationCount + 1
        let rows = try modelContext.fetch(bounded)
        guard rows.count <= Self.maximumMutableContentValidationCount else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        return rows
    }

    private func exactlyOneOrAbsent<Value>(_ values: [Value]) throws -> Value? {
        guard values.count <= 1 else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
        return values.first
    }

    private func recoverabilityVerificationReceiptRows(
        matching plan: RecoverabilityVerificationPlanV1
    ) throws -> [RecoverabilityVerificationReceiptRow] {
        let rows = try boundedFetch(FetchDescriptor<RecoverabilityVerificationReceiptRow>())
        return rows.filter {
            $0.receiptID == plan.receiptID
                || $0.verificationID == plan.verificationID
                || $0.mutationID == plan.mutationID.rawValue
        }
    }

    private func validate(
        receipt: RecoverabilityVerificationReceiptV1,
        matches plan: RecoverabilityVerificationPlanV1
    ) throws {
        try receipt.validate()
        guard receipt.receiptID == plan.receiptID,
              receipt.verificationID == plan.verificationID,
              receipt.workspaceID == plan.workspaceID,
              receipt.archive == plan.archive,
              receipt.mode == plan.mode,
              receipt.observedSourceFrontier == plan.observedSourceFrontier,
              receipt.verifierBuild == plan.verifierBuild,
              receipt.supersedesReceiptID == plan.supersedesReceiptID,
              receipt.revision == plan.revision,
              receipt.mutationID == plan.mutationID else {
            throw RecoverabilityVerificationFailureV1.divergentRetry
        }
    }

    private func validateRecoverabilityVerificationReceipts() throws {
        let rows = try boundedFetch(FetchDescriptor<RecoverabilityVerificationReceiptRow>())
        let values = try rows.map { try $0.value() }
        guard Set(values.map(\.receiptID)).count == values.count,
              Set(values.map(\.verificationID)).count == values.count,
              Set(values.map { $0.mutationID.rawValue }).count == values.count,
              values.allSatisfy({ $0.workspaceID == identity.workspaceID }) else {
            throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
        }
        for value in values {
            if let predecessorID = value.supersedesReceiptID {
                let predecessors = values.filter { $0.receiptID == predecessorID }
                guard predecessors.count == 1, let predecessor = predecessors.first else {
                    throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
                }
                do {
                    try value.validateSuccessor(of: predecessor)
                } catch {
                    throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
                }
            }
            guard values.filter({ $0.supersedesReceiptID == value.receiptID }).count <= 1 else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
        }
    }

    private func privacyManifestValue(_ row:PrivacyTransformManifestRow)throws->PrivacyTransformManifestV1{
        let id=row.policyID
        let rows=try modelContext.fetch(FetchDescriptor<PrivacyTransformPolicyRow>(predicate:#Predicate{$0.policyID==id}))
        guard rows.count==1,let policy=try rows.first?.value() else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt}
        return try row.value(policy:policy)
    }

    private func privacyReviewValue(_ row:PrivacyReviewReceiptRow)throws->PrivacyReviewReceiptV1{
        let manifestID=row.manifestID,policyID=row.policyID
        let manifestRows=try modelContext.fetch(FetchDescriptor<PrivacyTransformManifestRow>(predicate:#Predicate{$0.manifestID==manifestID}))
        let policyRows=try modelContext.fetch(FetchDescriptor<PrivacyTransformPolicyRow>(predicate:#Predicate{$0.policyID==policyID}))
        guard manifestRows.count==1,policyRows.count==1,let manifestRow=manifestRows.first,let policy=try policyRows.first?.value() else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt}
        let manifest=try manifestRow.value(policy:policy)
        return try row.value(manifest:manifest,policy:policy)
    }
    private func clientCapabilityRelease(_ packageReleaseID:String)throws->InspectionPackageReleaseV1{let rows=try modelContext.fetch(FetchDescriptor<PromotedPackageReleaseRow>());let matches=try rows.map{try $0.value().packageRelease}.filter{$0.packageReleaseID==packageReleaseID};guard matches.count==1,let value=matches.first else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return value}
    private func surveyPackageRelease(_ packageReleaseID:String)throws->InspectionPackageReleaseV1{let rows=try modelContext.fetch(FetchDescriptor<PromotedPackageReleaseRow>()),matches=try rows.map{try $0.value().packageRelease}.filter{$0.packageReleaseID==packageReleaseID};guard matches.count==1,let release=matches.first else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return release}
    private func clientCapabilityDecision(_ row:ClientCapabilityAdmissionDecisionRow)throws->ClientCapabilityAdmissionDecisionV1{let release=try clientCapabilityRelease(row.packageReleaseID),profileID=row.profileID,policyID=row.policyID,dispositionID=row.dispositionID;let profiles=try modelContext.fetch(FetchDescriptor<ClientCapabilityProfileRow>(predicate:#Predicate{$0.profileID==profileID})),policies=try modelContext.fetch(FetchDescriptor<PackageLifecyclePolicyRow>(predicate:#Predicate{$0.policyID==policyID})),dispositions=try modelContext.fetch(FetchDescriptor<PackageLifecycleDispositionRow>(predicate:#Predicate{$0.dispositionID==dispositionID}));guard profiles.count==1,policies.count==1,dispositions.count==1,let profile=try profiles.first?.value(),let policyRow=policies.first,let dispositionRow=dispositions.first else{throw WorkspaceMutationFailureV1.receiptHistoryCorrupt};return try row.value(profile:profile,policy:policyRow.value(release:release),disposition:dispositionRow.value(release:release),release:release)}

    private func semanticPostImage<Value: Codable>(
        _ identity: WorkspaceEntityIdentityV1,
        _ revision: UInt64,
        _ value: Value
    ) throws -> MutationPostImageV1 {
        let digest = try WorkspaceMutationCanonicalV1.sha256(
            PersistedPostImageDigestBasis(identity: identity, revision: revision, value: value)
        )
        return try Self.postImage(identity: identity, revision: revision, digest: digest)
    }

    private func tombstone(
        _ identity: WorkspaceEntityIdentityV1,
        _ revision: UInt64
    ) throws -> MutationPostImageV1 {
        .tombstone(
            identity: identity,
            revision: revision,
            semanticSHA256: try WorkspaceMutationCanonicalV1.sha256(
                PersistedTombstoneDigestBasis(identity: identity, revision: revision)
            )
        )
    }

    private func authorityConcurrency(
        _ identity: WorkspaceEntityIdentityV1,
        _ predecessorID: UUID?
    ) throws -> WorkspaceEntityIdentityV1 {
        try WorkspaceEntityIdentityV1(kind: identity.kind, id: predecessorID ?? identity.id)
    }

    private static func postImage(identity: WorkspaceEntityIdentityV1, revision: UInt64, digest: String) throws -> MutationPostImageV1 {
        switch identity.kind {
        case .site: return .site(id: identity.id, revision: revision, semanticSHA256: digest)
        case .asset: return .asset(id: identity.id, revision: revision, semanticSHA256: digest)
        case .locationNode: return .locationNode(id: identity.id, revision: revision, semanticSHA256: digest)
        case .assetPlacementEvent: return .assetPlacementEvent(id: identity.id, revision: revision, semanticSHA256: digest)
        case .assetCompositionEdge: return .assetCompositionEdge(id: identity.id, revision: revision, semanticSHA256: digest)
        case .assetCompositionEvent: return .assetCompositionEvent(id: identity.id, revision: revision, semanticSHA256: digest)
        case .savedSmartView: return .savedSmartView(id: identity.id, revision: revision, semanticSHA256: digest)
        case .serviceParty: return .serviceParty(id: identity.id, revision: revision, semanticSHA256: digest)
        case .sitePartyRoleEvent: return .sitePartyRoleEvent(id: identity.id, revision: revision, semanticSHA256: digest)
        case .actorSnapshot: return .actorSnapshot(id: identity.id, revision: revision, semanticSHA256: digest)
        case .qualificationSnapshot: return .qualificationSnapshot(id: identity.id, revision: revision, semanticSHA256: digest)
        case .signoffSnapshot: return .signoffSnapshot(id: identity.id, revision: revision, semanticSHA256: digest)
        case .authoritySourceRelease: return .authoritySourceRelease(id: identity.id, concurrencyIdentity: identity, revision: revision, semanticSHA256: digest)
        case .requirementBasisBinding: return .requirementBasisBinding(id: identity.id, concurrencyIdentity: identity, revision: revision, semanticSHA256: digest)
        case .applicabilityContextSnapshot: return .applicabilityContextSnapshot(id: identity.id, concurrencyIdentity: identity, revision: revision, semanticSHA256: digest)
        case .assessmentScopeSnapshot: return .assessmentScopeSnapshot(id: identity.id, concurrencyIdentity: identity, revision: revision, semanticSHA256: digest)
        case .severityScaleRelease: return .severityScaleRelease(id: identity.id, concurrencyIdentity: identity, revision: revision, semanticSHA256: digest)
        case .findingClassificationBinding: return .findingClassificationBinding(id: identity.id, concurrencyIdentity: identity, revision: revision, semanticSHA256: digest)
        case .measurementProtocolRelease: return .measurementProtocolRelease(id: identity.id, concurrencyIdentity: identity, revision: revision, semanticSHA256: digest)
        case .derivedFactEvaluatorDescriptor: return .derivedFactEvaluatorDescriptor(id: identity.id, concurrencyIdentity: identity, revision: revision, semanticSHA256: digest)
        case .derivedFactProvenance: return .derivedFactProvenance(id: identity.id, concurrencyIdentity: identity, revision: revision, semanticSHA256: digest)
        case .functionalRelationshipTypeDescriptor: return .functionalRelationshipTypeDescriptor(id: identity.id, concurrencyIdentity: identity, revision: revision, semanticSHA256: digest)
        case .assetFunctionalRelationshipEvent: return .assetFunctionalRelationshipEvent(id: identity.id, relationshipID: identity.id, concurrencyIdentity: identity, revision: revision, semanticSHA256: digest)
        case .evidenceVisibility:return .evidenceVisibility(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .claimEvidenceLink:return .claimEvidenceLink(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .assuranceManifest:return .assuranceManifest(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .attestation:return .attestation(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .inspectionReviewTransition:return .inspectionReviewTransition(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .reviewDisposition:return .reviewDisposition(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .changeRequest:return .changeRequest(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .correctiveActionPolicy:return .correctiveActionPolicy(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .correctiveActionEvent:return .correctiveActionEvent(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .workPacketManifest:return .workPacketManifest(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .workItemClaim:return .workItemClaim(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .workLease:return .workLease(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .workRelease:return .workRelease(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .workHandoff:return .workHandoff(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .fieldDraftCheckpoint:return .fieldDraftCheckpoint(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .attachmentStagingItem:return .attachmentStagingItem(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .draftCommitSaga:return .draftCommitSaga(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .draftContentReservation:return .draftContentReservation(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .draftCommitReceipt:return .draftCommitReceipt(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .draftDiscardReceipt:return .draftDiscardReceipt(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .promotedPackageRelease:return .promotedPackageRelease(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .packageSandboxRun:return .packageSandboxRun(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .packagePromotionReceipt:return .packagePromotionReceipt(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .activePackageRegistryPointer:return .activePackageRegistryPointer(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .instrumentReference:return .instrumentReference(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .calibrationStatusSnapshot:return .calibrationStatusSnapshot(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .measurementCapture:return .measurementCapture(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .measurementSeries:return .measurementSeries(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .measurementQualityAssessment:return .measurementQualityAssessment(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .privacyTransformPolicy:return .privacyTransformPolicy(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .privacyRegion:return .privacyRegion(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .privacyTransformManifest:return .privacyTransformManifest(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .privacyReviewReceipt:return .privacyReviewReceipt(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .clientCapabilityProfile:return .clientCapabilityProfile(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .clientCapabilityAdmissionDecision:return .clientCapabilityAdmissionDecision(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .packageLifecyclePolicy:return .packageLifecyclePolicy(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .packageLifecycleDisposition:return .packageLifecycleDisposition(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .fieldReferenceRelease:return .fieldReferenceRelease(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .fieldReferenceBinding:return .fieldReferenceBinding(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .accessibleDocumentAssessmentReceipt:return .accessibleDocumentAssessmentReceipt(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .surveyDefinitionIdentity:return .surveyDefinitionIdentity(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .surveyDefinitionRelease:return .surveyDefinitionRelease(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .surveySession:return .surveySession(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .factCapture:return .factCapture(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .provisionalSubject:return .provisionalSubject(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .subjectPromotionReceipt:return .subjectPromotionReceipt(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .surveyPublicationSnapshot:return .surveyPublicationSnapshot(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .assetLocator:return .assetLocator(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .locatorBindingReceipt:return .locatorBindingReceipt(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .evidenceContext:return .evidenceContext(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .pairedObservationLink:return .pairedObservationLink(id:identity.id,concurrencyIdentity:identity,revision:revision,semanticSHA256:digest)
        case .workflowRecord: return .workflowRecord(id: identity.id, revision: revision, semanticSHA256: digest)
        case .evidenceFile: return .evidenceFile(id: identity.id, revision: revision, semanticSHA256: digest)
        case .issue: return .issue(id: identity.id, revision: revision, semanticSHA256: digest)
        case .packet: return .packet(id: identity.id, revision: revision, semanticSHA256: digest)
        case .report: return .report(id: identity.id, revision: revision, semanticSHA256: digest)
        case .deletionLedgerEntry: return .deletionLedgerEntry(id: identity.id, revision: revision, semanticSHA256: digest)
        }
    }

    nonisolated private static func requireCompleteCompensatingReceipts(
        _ reversal: SemanticReversalReceiptV1,
        receiptsByMutation: [String: MutationReceiptV1]
    ) throws -> Bool {
        guard !reversal.compensatingMutationIDs.isEmpty else { return false }
        for mutationID in reversal.compensatingMutationIDs {
            let key = MutationWorkspaceKeyV1.value(
                workspaceID: reversal.reversalReceiptIdentity.workspaceID,
                mutationID: mutationID
            )
            guard let receipt = receiptsByMutation[key],
                  receipt.sourceKind == .semanticReversal,
                  receipt.causationMutationID == reversal.reversesMutationID,
                  receipt.reversesMutationID == reversal.reversesMutationID else {
                return false
            }
        }
        return true
    }

    private struct PersistedPostImageDigestBasis<Value: Codable>: Codable {
        let identity: WorkspaceEntityIdentityV1
        let revision: UInt64
        let value: Value
    }

    private struct PersistedTombstoneDigestBasis: Codable {
        let identity: WorkspaceEntityIdentityV1
        let revision: UInt64
        let disposition = "ABSENT_AFTER_MUTATION"
    }

    private struct MutableSemanticItem: Codable {
        let stableIdentity: String
        let revision: UInt64
        let semanticSHA256: String
    }

    private struct MutableSemanticDigestBasis: Codable {
        let content: [MutableSemanticItem]
        let deletionLedger: DeletionLedgerV2
    }
}

extension MutationJournalStoreV1: RecoverabilityVerificationReceiptWritingV1 {
    func acceptedReceipt(
        for plan: RecoverabilityVerificationPlanV1
    ) async throws -> RecoverabilityVerificationReceiptV1? {
        try acceptedRecoverabilityVerificationReceipt(for: plan)
    }

    func append(
        _ receipt: RecoverabilityVerificationReceiptV1
    ) async throws -> RecoverabilityVerificationReceiptV1 {
        try appendRecoverabilityVerificationReceipt(receipt)
    }
}

private struct WorkflowRecordPostImageV8: Codable {
    let record: V4BackupWorkflowRecordDTO
    let requirementAssurance: RequirementAssuranceSnapshotV1?
}

private struct AssetSemanticAssetPostImageV1: Codable {
    let asset: V4BackupAssetDTO
    let semantic: AssetSemanticPersistentSnapshotV1
}

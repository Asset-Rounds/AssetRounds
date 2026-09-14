import Foundation

// Internal seam for the incumbent C49/C55 replacement wrapper only.
// decoded performs canonical decoding and typed checks, not complete snapshot admission.
// The caller must admit the full imported snapshot and discard local emission state on
// any throw: emitters can mutate terminal state before a later operation fails.
// This is not a transactional builder or an independently authorized writer.
enum ReplacementHistoryCommandEmissionV1 {
    struct DecodedReceipt: Equatable, Sendable {
        let record: MutationHistoryReceiptRecordV1
        let envelope: MutationEnvelopeV1
        let receipt: MutationReceiptV1

        fileprivate init(
            record: MutationHistoryReceiptRecordV1,
            envelope: MutationEnvelopeV1,
            receipt: MutationReceiptV1
        ) {
            self.record = record
            self.envelope = envelope
            self.receipt = receipt
        }
        var mutationKey: String {
            ReplacementHistoryCommandEmissionV1.mutationKey(
                workspaceID: envelope.workspaceID,
                mutationID: envelope.mutationID.rawValue
            )
        }
        var workResourceMutation: WorkResourceMutationV1? {
            guard case let .applyWorkResource(value) = envelope.command else { return nil }
            return value
        }
        var partsStockMutation: PartsStockMutationV1? {
            guard case let .applyPartsStock(value) = envelope.command else { return nil }
            return value
        }
        var isWorkResource: Bool { workResourceMutation != nil }
        var isPartsStock: Bool { partsStockMutation != nil }
    }

    struct IdentityMap {
        let targetMutationID: MutationIDV1
        let sourceEnvelopeSHA256: String
        let targetEnvelopeSHA256: String
        let sourceReplaySHA256: String?
        let targetReplaySHA256: String?

        fileprivate init(
            targetMutationID: MutationIDV1,
            sourceEnvelopeSHA256: String,
            targetEnvelopeSHA256: String,
            sourceReplaySHA256: String?,
            targetReplaySHA256: String?
        ) {
            self.targetMutationID = targetMutationID
            self.sourceEnvelopeSHA256 = sourceEnvelopeSHA256
            self.targetEnvelopeSHA256 = targetEnvelopeSHA256
            self.sourceReplaySHA256 = sourceReplaySHA256
            self.targetReplaySHA256 = targetReplaySHA256
        }
    }

    struct Emitted {
        let record: MutationHistoryReceiptRecordV1
        let receipt: MutationReceiptV1
        let basis: ReversalBasisV1?
        let identityMap: IdentityMap

        fileprivate init(
            record: MutationHistoryReceiptRecordV1,
            receipt: MutationReceiptV1,
            basis: ReversalBasisV1?,
            identityMap: IdentityMap
        ) {
            self.record = record
            self.receipt = receipt
            self.basis = basis
            self.identityMap = identityMap
        }
    }

    static func decoded(_ history: MutationHistorySnapshotV1) throws -> [DecodedReceipt] {
        let values = try history.receipts.map { record in
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
            let receipt = try MutationReceiptV1.decodeCanonical(from: record.receiptData)
            guard receipt.expectedRevision == envelope.expectedRevision else {
                throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
            }
            if case let .applyWorkResource(mutation) = envelope.command {
                _ = try WorkResourceMutationReceiptV1(
                    mutation: mutation, mutationReceipt: receipt
                )
            }
            if case let .applyPartsStock(mutation) = envelope.command {
                guard receipt.postImages == (try mutation.mutationPostImages) else {
                    throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
                }
            }
            return DecodedReceipt(record: record, envelope: envelope, receipt: receipt)
        }
        return values.sorted {
            let lhsWorkspace = $0.envelope.workspaceID.rawValue.uuidString
            let rhsWorkspace = $1.envelope.workspaceID.rawValue.uuidString
            if lhsWorkspace != rhsWorkspace {
                return lhsWorkspace < rhsWorkspace
            }
            if $0.receipt.resultingRevision.workspaceRevision
                != $1.receipt.resultingRevision.workspaceRevision {
                return $0.receipt.resultingRevision.workspaceRevision < $1.receipt.resultingRevision.workspaceRevision
            }
            return $0.receipt.identity.stableKey < $1.receipt.identity.stableKey
        }
    }

    static func emitProjected(
        source: DecodedReceipt,
        command: WorkspaceCommandV1,
        workspaceRevision: UInt64,
        terminal: inout [WorkspaceEntityIdentityV1: UInt64],
        targetWorkspaceID: WorkspaceID,
        targetGenerationID: UUID,
        writerInstanceID: UUID,
        mutationIDBySource: [UUID: MutationIDV1],
        replicaBySource: [ReplicaID: ReplicaID],
        targetReceiptBySourceMutationID: [UUID: MutationReceiptV1],
        targetBasisBySourceMutationID: [UUID: ReversalBasisV1],
        sourceValues: [DecodedReceipt]
    ) throws -> Emitted {
        guard let targetMutationID = mutationIDBySource[source.envelope.mutationID.rawValue],
              let targetReplicaID = replicaBySource[source.receipt.identity.replicaID] else {
            throw PartsStockReplacementHistoryProjectionFailureV1.missingDependency
        }
        let concurrency: [WorkspaceEntityIdentityV1]
        let expectedValues: [WorkspaceEntityIdentityV1: UInt64]
        let postImages: [MutationPostImageV1]
        switch command {
        case let .applyWorkResource(mutation):
            concurrency = try mutation.concurrencyIdentities
            expectedValues = Dictionary(uniqueKeysWithValues: try concurrency.map {
                ($0, try mutation.expectedRevision(for: $0))
            })
            postImages = try mutation.mutationPostImages
        case let .applyPartsStock(mutation):
            concurrency = try mutation.concurrencyIdentities
            expectedValues = Dictionary(uniqueKeysWithValues: try concurrency.map {
                ($0, try mutation.expectedRevision(for: $0))
            })
            postImages = try mutation.mutationPostImages
        default:
            throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
        }
        guard concurrency.allSatisfy({ terminal[$0, default: 0] == expectedValues[$0] }) else {
            throw PartsStockReplacementHistoryProjectionFailureV1.missingDependency
        }
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: targetWorkspaceID,
            generationID: targetGenerationID,
            writerInstanceID: writerInstanceID,
            workspaceRevision: workspaceRevision,
            entityRevisions: concurrency.map {
                WorkspaceEntityRevisionV1(identity: $0, revision: expectedValues[$0]!)
            }
        )
        let request = WorkspaceMutationRequestV1(
            mutationID: targetMutationID,
            expectedRevision: expected,
            command: command
        )
        let targetReceiptIdentity = MutationReceiptIdentityV1(
            workspaceID: targetWorkspaceID,
            replicaID: targetReplicaID,
            localSequence: source.receipt.identity.localSequence
        )
        var targetBasis: ReversalBasisV1?
        var targetSemantic: SemanticReversalReceiptV1?
        var reversalPlanDigest: String?
        var semanticExecution: SemanticReversalExecutionV1?
        var replayIdentitySHA256: String?
        var reversesMutationID: MutationIDV1?
        var causationMutationID: MutationIDV1?

        if let basisData = source.record.reversalBasisData {
            let sourceBasis = try ReversalBasisV1.decodeCanonical(from: basisData)
            let sourceReversals = sourceValues.filter {
                $0.receipt.reversesMutationID == source.envelope.mutationID
            }
            guard sourceBasis.targetMutationID == source.envelope.mutationID,
                  sourceBasis.targetReceiptIdentity == source.receipt.identity,
                  source.envelope.reversalPlanDigest == sourceBasis.planDigest,
                  sourceReversals.count == 1,
                  let sourceReversal = sourceReversals.first,
                  let sourceSemanticData = sourceReversal.record.semanticReversalData else {
                throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
            }
            let sourceSemantic = try SemanticReversalReceiptV1.decodeCanonical(
                from: sourceSemanticData
            )
            guard sourceSemantic.planDigest == sourceBasis.planDigest,
                  sourceSemantic.reversalBasisSHA256 == (try sourceBasis.canonicalSHA256()),
                  sourceSemantic.compensatingMutationIDs == [sourceReversal.envelope.mutationID],
                  sourceBasis.compensatingCommandKinds == [sourceReversal.envelope.command.kind],
                  mutationIDBySource[sourceBasis.targetMutationID.rawValue] == targetMutationID,
                  mutationIDBySource[sourceReversal.envelope.mutationID.rawValue] != nil else {
                throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
            }
            targetBasis = try ReversalBasisV1(
                rebinding: sourceBasis,
                targetMutationID: targetMutationID,
                targetReceiptIdentity: targetReceiptIdentity
            )
            reversalPlanDigest = sourceBasis.planDigest
        } else {
            guard source.envelope.reversalPlanDigest == nil else {
                throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
            }
        }

        if let semanticData = source.record.semanticReversalData {
            let sourceSemantic = try SemanticReversalReceiptV1.decodeCanonical(from: semanticData)
            guard sourceSemantic.reversalReceiptIdentity == source.receipt.identity,
                  source.receipt.reversesMutationID == sourceSemantic.reversesMutationID,
                  sourceSemantic.resultingRevision == source.receipt.resultingRevision,
                  sourceSemantic.compensatingMutationIDs == [source.envelope.mutationID],
                  let targetReversedMutationID = mutationIDBySource[
                      sourceSemantic.reversesMutationID.rawValue
                  ],
                  let sourceTarget = sourceValues.first(where: {
                      $0.envelope.mutationID == sourceSemantic.reversesMutationID
                  }),
                  let targetReceipt = targetReceiptBySourceMutationID[
                      sourceSemantic.reversesMutationID.rawValue
                  ],
                  let basis = targetBasisBySourceMutationID[
                      sourceSemantic.reversesMutationID.rawValue
                  ],
                  sourceSemantic.targetReceiptIdentity == sourceTarget.receipt.identity,
                  basis.planDigest == sourceSemantic.planDigest else {
                throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
            }
            let targetBasisSHA256 = try basis.canonicalSHA256()
            semanticExecution = try SemanticReversalExecutionV1(
                targetMutationID: targetReversedMutationID,
                targetReceiptIdentity: targetReceipt.identity,
                reversalBasisSHA256: targetBasisSHA256,
                planDigest: basis.planDigest,
                compensatingMutationIDs: [targetMutationID]
            )
            replayIdentitySHA256 = try SemanticReversalReplayIdentityV1(
                request: request,
                identity: WorkspaceReplicaIdentityV1(
                    workspaceID: targetWorkspaceID,
                    replicaID: targetReplicaID
                ),
                targetMutationID: targetReversedMutationID,
                planDigest: basis.planDigest,
                compensatingMutationIDs: [targetMutationID]
            ).canonicalSHA256()
            reversesMutationID = targetReversedMutationID
            causationMutationID = targetReversedMutationID
        } else {
            guard source.receipt.reversesMutationID == nil,
                  source.envelope.semanticReversalExecution == nil,
                  source.envelope.semanticReversalReplayIdentitySHA256 == nil else {
                throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
            }
            if let sourceID = source.envelope.causationMutationID {
                guard let mapped = mutationIDBySource[sourceID.rawValue],
                      targetReceiptBySourceMutationID[sourceID.rawValue] != nil else {
                    throw PartsStockReplacementHistoryProjectionFailureV1.missingDependency
                }
                causationMutationID = mapped
            }
        }
        let sourceKind: MutationSourceKindV1 = semanticExecution == nil
            ? .localRecovery : .semanticReversal
        let envelope = try MutationEnvelopeV1(
            request: request,
            identity: WorkspaceReplicaIdentityV1(
                workspaceID: targetWorkspaceID,
                replicaID: targetReplicaID
            ),
            sourceKind: sourceKind,
            contentDependencyIDs: source.envelope.contentDependencyIDs,
            causationMutationID: causationMutationID,
            correlationID: source.envelope.correlationID,
            reversalPlanDigest: reversalPlanDigest,
            semanticReversalReplayIdentitySHA256: replayIdentitySHA256,
            semanticReversalExecution: semanticExecution
        )
        for image in postImages {
            for identity in try advancingIdentities(for: image) {
                terminal[identity] = image.revision
            }
        }
        let next = workspaceRevision.addingReportingOverflow(1)
        guard !next.overflow else {
            throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
        }
        let resulting = try MutationPortableExpectedRevisionV1(
            WorkspaceExpectedRevisionV1(
                workspaceID: targetWorkspaceID,
                generationID: targetGenerationID,
                writerInstanceID: writerInstanceID,
                workspaceRevision: next.partialValue,
                entityRevisions: terminal.map {
                    WorkspaceEntityRevisionV1(identity: $0.key, revision: $0.value)
                }
            )
        )
        let receipt = try MutationReceiptV1(
            identity: targetReceiptIdentity,
            envelope: envelope,
            resultingRevision: resulting,
            postImages: postImages,
            reversesMutationID: reversesMutationID,
            committedAt: source.receipt.committedAt
        )
        if let execution = semanticExecution, let targetReversedMutationID = reversesMutationID {
            targetSemantic = try SemanticReversalReceiptV1(
                reversalReceiptIdentity: receipt.identity,
                reversesMutationID: targetReversedMutationID,
                targetReceiptIdentity: execution.targetReceiptIdentity,
                reversalBasisSHA256: execution.reversalBasisSHA256,
                planDigest: execution.planDigest,
                compensatingMutationIDs: [targetMutationID],
                resultingRevision: receipt.resultingRevision
            )
        }
        let record = MutationHistoryReceiptRecordV1(
            envelopeData: try envelope.canonicalData(),
            receiptData: try receipt.canonicalData(),
            reversalBasisData: try targetBasis?.canonicalData(),
            semanticReversalData: try targetSemantic?.canonicalData()
        )
        return Emitted(
            record: record,
            receipt: receipt,
            basis: targetBasis,
            identityMap: IdentityMap(
                targetMutationID: targetMutationID,
                sourceEnvelopeSHA256: try source.envelope.canonicalSHA256(),
                targetEnvelopeSHA256: try envelope.canonicalSHA256(),
                sourceReplaySHA256: source.envelope.semanticReversalReplayIdentitySHA256,
                targetReplaySHA256: envelope.semanticReversalReplayIdentitySHA256
            )
        )
    }

    static func emitRetained(
        source: DecodedReceipt,
        workspaceRevision: UInt64,
        terminal: inout [WorkspaceEntityIdentityV1: UInt64],
        removedIdentities: Set<WorkspaceEntityIdentityV1>,
        targetGenerationID: UUID,
        writerInstanceID: UUID
    ) throws -> Emitted {
        let expectedRows = source.receipt.expectedRevision.entityRevisions.filter {
            !removedIdentities.contains($0.identity) && !isPartsStockKind($0.identity.kind)
        }
        guard expectedRows.allSatisfy({ terminal[$0.identity, default: 0] == $0.revision }),
              try source.receipt.postImages.allSatisfy({ image in
                  try terminalIdentities(for: image).allSatisfy {
                      !removedIdentities.contains($0) && !isPartsStockKind($0.kind)
                  }
              }) else {
            throw PartsStockReplacementHistoryProjectionFailureV1.missingDependency
        }
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: source.envelope.workspaceID,
            generationID: targetGenerationID,
            writerInstanceID: writerInstanceID,
            workspaceRevision: workspaceRevision,
            entityRevisions: expectedRows
        )
        let request = WorkspaceMutationRequestV1(
            mutationID: source.envelope.mutationID,
            expectedRevision: expected,
            command: source.envelope.command
        )
        var execution = source.envelope.semanticReversalExecution
        var replaySHA256: String?
        if let executionValue = execution {
            replaySHA256 = try SemanticReversalReplayIdentityV1(
                request: request,
                identity: WorkspaceReplicaIdentityV1(
                    workspaceID: source.envelope.workspaceID,
                    replicaID: source.envelope.replicaID
                ),
                targetMutationID: executionValue.targetMutationID,
                planDigest: executionValue.planDigest,
                compensatingMutationIDs: executionValue.compensatingMutationIDs
            ).canonicalSHA256()
        } else {
            execution = nil
        }
        let envelope = try MutationEnvelopeV1(
            request: request,
            identity: WorkspaceReplicaIdentityV1(
                workspaceID: source.envelope.workspaceID,
                replicaID: source.envelope.replicaID
            ),
            sourceKind: execution == nil ? .localRecovery : .semanticReversal,
            contentDependencyIDs: source.envelope.contentDependencyIDs,
            causationMutationID: source.envelope.causationMutationID,
            correlationID: source.envelope.correlationID,
            reversalPlanDigest: source.envelope.reversalPlanDigest,
            semanticReversalReplayIdentitySHA256: replaySHA256,
            semanticReversalExecution: execution
        )
        for row in source.receipt.resultingRevision.entityRevisions
            where !removedIdentities.contains(row.identity)
                && !isPartsStockKind(row.identity.kind) {
            if terminal[row.identity, default: 0] > row.revision {
                throw PartsStockReplacementHistoryProjectionFailureV1.collision
            }
            terminal[row.identity] = row.revision
        }
        for image in source.receipt.postImages {
            for identity in try advancingIdentities(for: image) {
                terminal[identity] = image.revision
            }
        }
        let next = workspaceRevision.addingReportingOverflow(1)
        guard !next.overflow else {
            throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
        }
        let resulting = try MutationPortableExpectedRevisionV1(
            WorkspaceExpectedRevisionV1(
                workspaceID: source.envelope.workspaceID,
                generationID: targetGenerationID,
                writerInstanceID: writerInstanceID,
                workspaceRevision: next.partialValue,
                entityRevisions: terminal.map {
                    WorkspaceEntityRevisionV1(identity: $0.key, revision: $0.value)
                }
            )
        )
        let receipt = try MutationReceiptV1(
            identity: source.receipt.identity,
            envelope: envelope,
            resultingRevision: resulting,
            postImages: source.receipt.postImages,
            reversesMutationID: source.receipt.reversesMutationID,
            committedAt: source.receipt.committedAt
        )
        let basis = try source.record.reversalBasisData.map {
            try ReversalBasisV1.decodeCanonical(from: $0)
        }
        var semantic: SemanticReversalReceiptV1?
        if let data = source.record.semanticReversalData {
            let original = try SemanticReversalReceiptV1.decodeCanonical(from: data)
            semantic = try SemanticReversalReceiptV1(
                reversalReceiptIdentity: receipt.identity,
                reversesMutationID: original.reversesMutationID,
                targetReceiptIdentity: original.targetReceiptIdentity,
                reversalBasisSHA256: original.reversalBasisSHA256,
                planDigest: original.planDigest,
                compensatingMutationIDs: original.compensatingMutationIDs,
                resultingRevision: receipt.resultingRevision
            )
        }
        return Emitted(
            record: MutationHistoryReceiptRecordV1(
                envelopeData: try envelope.canonicalData(),
                receiptData: try receipt.canonicalData(),
                reversalBasisData: try basis?.canonicalData(),
                semanticReversalData: try semantic?.canonicalData()
            ),
            receipt: receipt,
            basis: basis,
            identityMap: IdentityMap(
                targetMutationID: envelope.mutationID,
                sourceEnvelopeSHA256: try source.envelope.canonicalSHA256(),
                targetEnvelopeSHA256: try envelope.canonicalSHA256(),
                sourceReplaySHA256: source.envelope.semanticReversalReplayIdentitySHA256,
                targetReplaySHA256: envelope.semanticReversalReplayIdentitySHA256
            )
        )
    }

    private static func advancingIdentities(
        for image: MutationPostImageV1
    ) throws -> Set<WorkspaceEntityIdentityV1> {
        var result = try terminalIdentities(for: image)
        let physical = try image.identity
        let concurrency = try image.concurrencyIdentity
        if physical.kind == .workResourceEntry,
           concurrency.kind == .workResourceEntry,
           physical != concurrency {
            result.remove(concurrency)
        }
        return result
    }

    static func terminalIdentities(
        for image: MutationPostImageV1
    ) throws -> Set<WorkspaceEntityIdentityV1> {
        var result: Set<WorkspaceEntityIdentityV1> = [try image.identity]
        result.insert(try image.concurrencyIdentity)
        if case let .partsStock(id, kind, _, _, _) = image {
            result.insert(try WorkspaceEntityIdentityV1(kind: kind, id: id))
        }
        return result
    }

    static func isPartsStockKind(_ kind: WorkspaceEntityKindV1) -> Bool {
        switch kind {
        case .localPartDefinition, .stockStorageLocation, .stockBalanceStream,
             .stockMovementEvent, .stockUseReceipt, .stockUseReversalReceipt,
             .stockReturnReceipt, .stockAbandonment:
            return true
        default:
            return false
        }
    }

    static func mutationKey(workspaceID: WorkspaceID, mutationID: UUID) -> String {
        "\(workspaceID.rawValue.uuidString.lowercased()):\(mutationID.uuidString.lowercased())"
    }


}

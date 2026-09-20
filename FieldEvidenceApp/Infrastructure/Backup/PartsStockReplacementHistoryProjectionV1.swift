import Foundation

enum PartsStockReplacementHistoryProjectionFailureV1: Error, Equatable {
    case invalidSource
    case invalidBinding
    case collision
    case missingDependency
    case incompleteProjection
}

/// Preserves the admitted source history and reissues its C49/C55 partition as
/// one destination history. The caller supplies only mappings derived before
/// generic history merge; this type never infers source ownership from the
/// merged journal.
enum PartsStockReplacementHistoryProjectionV1 {
    struct MutationBinding: Equatable, Sendable {
        let source: MutationIDV1
        let target: MutationIDV1
    }

    struct SubjectBinding: Equatable, Sendable {
        let source: WorkResourceSubjectV1
        let target: WorkResourceSubjectV1
    }

    struct ReplicaBinding: Equatable, Sendable {
        let source: ReplicaID
        let target: ReplicaID
    }

    struct Input: Equatable, Sendable {
        let currentSnapshot: PartsStockBackupSnapshotV1
        let incomingSnapshot: PartsStockBackupSnapshotV1
        let currentHistory: MutationHistorySnapshotV1
        let incomingHistory: MutationHistorySnapshotV1
        let plannedHistory: MutationHistorySnapshotV1
        let currentWorkResources: [WorkResourceEntryV1]
        let incomingWorkResources: [WorkResourceEntryV1]
        let plannedWorkResources: [WorkResourceEntryV1]
        let targetWorkspaceID: WorkspaceID
        let targetGenerationID: UUID
        let writerInstanceID: UUID
        let mutationBindings: [MutationBinding]
        let subjectBindings: [SubjectBinding]
        let replicaBindings: [ReplicaBinding]
    }

    struct Requirements: Equatable, Sendable {
        let mutationIDs: [MutationIDV1]
        let partsStockMutationIDs: [MutationIDV1]
        let subjects: [WorkResourceSubjectV1]
        let replicas: [ReplicaID]
    }

    struct Result: Equatable, Sendable {
        let sourceSnapshotSHA256: String
        let targetSnapshot: PartsStockBackupSnapshotV1
        let history: MutationHistorySnapshotV1
        let workResources: [WorkResourceEntryV1]
        let roundSessions: [RoundSessionV1]
    }

    static func requirements(
        incomingSnapshot: PartsStockBackupSnapshotV1,
        incomingHistory: MutationHistorySnapshotV1,
        incomingWorkResources: [WorkResourceEntryV1],
        roundProjection: RoundSessionReplacementCommandProjectionV1.Projection? = nil
    ) throws -> Requirements {
        try incomingSnapshot.validate()
        try MutationJournalStoreV1.validateImportedSnapshot(incomingHistory)
        let values = try ReplacementHistoryCommandEmissionV1.decoded(incomingHistory)
        let roundCommands = try authenticatedRoundCommands(roundProjection,
            history: incomingHistory, workspaceID: incomingSnapshot.workspaceID)
        let roundIDs = Set(roundCommands.map { $0.source.envelope.mutationID })
        let owned = values.filter {
            ($0.isWorkResource || $0.isPartsStock || roundIDs.contains($0.envelope.mutationID))
                && $0.envelope.workspaceID == incomingSnapshot.workspaceID
                && $0.receipt.identity.workspaceID == incomingSnapshot.workspaceID
        }
        let receiptMutationIDs = owned.map(\.envelope.mutationID)
        let replicas = owned.map(\.receipt.identity.replicaID)
        guard Set(receiptMutationIDs).count == receiptMutationIDs.count else {
            throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
        }
        let baselines = try originalCatalogBaselines(
            snapshot: incomingSnapshot,
            history: incomingHistory
        )
        let stockRequirements = try PartsStockReplacementValueProjectionV1.requirements(
            for: .init(
                snapshot: incomingSnapshot,
                orderedMutations: owned.compactMap(\.partsStockMutation),
                originalCatalogBaselines: baselines
            )
        )
        let mutationIDs = Array(
            Set(receiptMutationIDs).union(stockRequirements.mutationIDs)
        ).sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
        var subjects = Set(incomingWorkResources.map(\.subject))
        subjects.formUnion(stockRequirements.workSubjects)
        return Requirements(
            mutationIDs: mutationIDs,
            partsStockMutationIDs: stockRequirements.mutationIDs,
            subjects: subjects.sorted(by: subjectLessThan),
            replicas: Array(Set(replicas)).sorted {
                $0.rawValue.uuidString < $1.rawValue.uuidString
            }
        )
    }

    static func project(_ input: Input,
                        roundProjection: RoundSessionReplacementCommandProjectionV1.Projection? = nil) throws -> Result {
        try input.currentSnapshot.validate()
        try input.incomingSnapshot.validate()
        try MutationJournalStoreV1.validateImportedSnapshot(input.currentHistory)
        try MutationJournalStoreV1.validateImportedSnapshot(input.incomingHistory)
        try MutationJournalStoreV1.validateImportedSnapshot(input.plannedHistory)
        guard input.currentSnapshot.workspaceID == input.targetWorkspaceID,
              input.incomingSnapshot.workspaceID != input.targetWorkspaceID,
              input.targetGenerationID != zero,
              input.writerInstanceID != zero else {
            throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
        }

        let currentValues = try ReplacementHistoryCommandEmissionV1.decoded(input.currentHistory)
        let incomingValues = try ReplacementHistoryCommandEmissionV1.decoded(input.incomingHistory)
        let plannedValues = try ReplacementHistoryCommandEmissionV1.decoded(input.plannedHistory)
        let roundCommands = try authenticatedRoundCommands(roundProjection,
            history: input.incomingHistory, workspaceID: input.incomingSnapshot.workspaceID)
        if let roundProjection {
            guard roundProjection.identity.targetPointer.workspaceID == input.targetWorkspaceID.rawValue,
                  roundProjection.identity.targetPointer.generationID == input.targetGenerationID else {
                throw PartsStockReplacementHistoryProjectionFailureV1.invalidBinding
            }
        }
        let roundBySourceID = Dictionary(uniqueKeysWithValues:
            roundCommands.map { ($0.source.envelope.mutationID, $0) })
        let incomingOwned = incomingValues.filter {
            ($0.isWorkResource || $0.isPartsStock || roundBySourceID[$0.envelope.mutationID] != nil)
                && $0.envelope.workspaceID == input.incomingSnapshot.workspaceID
                && $0.receipt.identity.workspaceID == input.incomingSnapshot.workspaceID
        }
        guard incomingOwned.allSatisfy({
                   $0.envelope.workspaceID == input.incomingSnapshot.workspaceID
                     && $0.receipt.identity.workspaceID == input.incomingSnapshot.workspaceID
               }) else {
            throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
        }

        let plannedByMutationKey = Dictionary(
            uniqueKeysWithValues: plannedValues.map { ($0.mutationKey, $0) }
        )
        guard incomingOwned.allSatisfy({ plannedByMutationKey[$0.mutationKey] == $0 }) else {
            // The source partition was admitted before the generic merge. A
            // matching key with changed canonical bytes is not that partition.
            throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
        }

        let requirements = try requirements(
            incomingSnapshot: input.incomingSnapshot,
            incomingHistory: input.incomingHistory,
            incomingWorkResources: input.incomingWorkResources,
            roundProjection: roundProjection
        )
        let mutationIDBySource = try exactMutationBindings(
            input.mutationBindings, required: requirements.mutationIDs
        )
        guard roundCommands.allSatisfy({
            mutationIDBySource[$0.source.envelope.mutationID.rawValue] == $0.mutation.mutationID
        }) else { throw PartsStockReplacementHistoryProjectionFailureV1.invalidBinding }
        let subjectBySource = try exactSubjectBindings(
            input.subjectBindings,
            required: requirements.subjects,
            targetWorkspaceID: input.targetWorkspaceID
        )
        let replicaBySource = try exactReplicaBindings(
            input.replicaBindings,
            required: requirements.replicas,
            targetWorkspaceID: input.targetWorkspaceID
        )

        let currentStockValues = currentValues.filter {
            $0.isPartsStock
                && $0.envelope.workspaceID == input.targetWorkspaceID
                && $0.receipt.identity.workspaceID == input.targetWorkspaceID
        }
        let currentStockMutationKeys = Set(currentStockValues.map(\.mutationKey))
        let incomingOwnedMutationKeys = Set(incomingOwned.map(\.mutationKey))
        let currentStockWorkEntries = try currentStockValues.compactMap(\.partsStockMutation)
            .flatMap(partsStockWorkEntries) + snapshotWorkEntries(input.currentSnapshot)
        var currentStockWorkEntryIDs = Set(currentStockWorkEntries.map(\.entryID))
        currentStockWorkEntryIDs.formUnion(currentStockWorkEntries.compactMap(\.supersedesEntryID))
        var currentCoupledWorkMutationKeys = Set<String>()
        var foundCoupledWork = true
        while foundCoupledWork {
            foundCoupledWork = false
            for value in currentValues {
                guard let mutation = value.workResourceMutation,
                      value.envelope.workspaceID == input.targetWorkspaceID,
                      value.receipt.identity.workspaceID == input.targetWorkspaceID,
                      mutation.workspaceID == input.targetWorkspaceID,
                      currentStockWorkEntryIDs.contains(mutation.postImage.entryID)
                        || mutation.postImage.supersedesEntryID.map(
                            currentStockWorkEntryIDs.contains
                        ) == true else { continue }
                if currentCoupledWorkMutationKeys.insert(value.mutationKey).inserted {
                    foundCoupledWork = true
                }
                if currentStockWorkEntryIDs.insert(mutation.postImage.entryID).inserted {
                    foundCoupledWork = true
                }
                if let predecessorID = mutation.postImage.supersedesEntryID,
                   currentStockWorkEntryIDs.insert(predecessorID).inserted {
                    foundCoupledWork = true
                }
            }
        }
        let currentRemovedMutationKeys = currentStockMutationKeys
            .union(currentCoupledWorkMutationKeys)
        let incomingSourceWorkEntryIDs = Set(input.incomingWorkResources.map(\.entryID))
        let currentSourceWorkEntryIDs = Set(input.currentWorkResources.map(\.entryID))
        guard input.currentWorkResources.allSatisfy({
                  (try? $0.validate()) != nil && $0.workspaceID == input.targetWorkspaceID
              }),
              input.incomingWorkResources.allSatisfy({
                  (try? $0.validate()) != nil
                    && $0.workspaceID == input.incomingSnapshot.workspaceID
              }),
              currentSourceWorkEntryIDs.count == input.currentWorkResources.count,
              incomingSourceWorkEntryIDs.count == input.incomingWorkResources.count,
              currentSourceWorkEntryIDs.isDisjoint(with: incomingSourceWorkEntryIDs) else {
            throw PartsStockReplacementHistoryProjectionFailureV1.collision
        }
        let plannedWorkByID = try canonicalWorkByID(input.plannedWorkResources)
        guard input.incomingWorkResources.allSatisfy({ plannedWorkByID[$0.entryID] == $0 }) else {
            throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
        }
        let incomingStockWorkEntryIDs = Set(
            try incomingOwned.compactMap(\.partsStockMutation)
                .flatMap(partsStockWorkEntries).map(\.entryID)
        )
        let currentWorkByID = try canonicalWorkByID(input.currentWorkResources)
        let incomingWorkByID = try canonicalWorkByID(input.incomingWorkResources)
        let currentStockWorkByID = try canonicalWorkByID(
            currentStockValues.compactMap(\.partsStockMutation)
                .flatMap(partsStockWorkEntries)
                + snapshotWorkEntries(input.currentSnapshot)
        )
        let incomingStockWorkByID = try canonicalWorkByID(
            incomingOwned.compactMap(\.partsStockMutation)
                .flatMap(partsStockWorkEntries)
                + snapshotWorkEntries(input.incomingSnapshot)
        )
        guard currentStockWorkByID.allSatisfy({ currentWorkByID[$0.key] == $0.value }),
              incomingStockWorkByID.allSatisfy({ incomingWorkByID[$0.key] == $0.value }) else {
            throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
        }
        let incomingIndependentEntryIDs = incomingSourceWorkEntryIDs
            .subtracting(incomingStockWorkEntryIDs)
        let incomingWorkReceiptEntryIDs = Set(incomingOwned.compactMap {
            $0.workResourceMutation?.postImage.entryID
        })
        guard incomingWorkReceiptEntryIDs == incomingIndependentEntryIDs else {
            // Stock-owned C49 rows are represented by applyPartsStock receipts,
            // so only independent rows have applyWorkResource receipts.
            throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
        }

        let retainedPlanned = plannedValues.filter {
            !incomingOwnedMutationKeys.contains($0.mutationKey)
                && !currentRemovedMutationKeys.contains($0.mutationKey)
        }
        let retainedTarget = retainedPlanned.filter {
            $0.envelope.workspaceID == input.targetWorkspaceID
                && $0.receipt.identity.workspaceID == input.targetWorkspaceID
        }
        let retainedHistoric = plannedValues.filter {
            $0.envelope.workspaceID != input.targetWorkspaceID
                && $0.receipt.identity.workspaceID != input.targetWorkspaceID
        }
        guard retainedTarget.count + retainedHistoric.count
                == retainedPlanned.count + incomingOwned.count,
              retainedTarget.allSatisfy({
                   $0.envelope.workspaceID == input.targetWorkspaceID
                     && $0.receipt.identity.workspaceID == input.targetWorkspaceID
               }),
              !retainedTarget.contains(where: \.isPartsStock) else {
            throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
        }

        let retainedMutationIDs = Set(retainedTarget.map { $0.envelope.mutationID.rawValue })
        let targetMutationIDs = Set(mutationIDBySource.values.map(\.rawValue))
        guard targetMutationIDs.count == mutationIDBySource.count,
              retainedMutationIDs.isDisjoint(with: targetMutationIDs) else {
            throw PartsStockReplacementHistoryProjectionFailureV1.collision
        }
        let retainedReceiptIdentities = Set(retainedTarget.map { $0.receipt.identity.stableKey })
        let targetReceiptIdentities = Set(incomingOwned.map { value in
            MutationReceiptIdentityV1(
                workspaceID: input.targetWorkspaceID,
                replicaID: replicaBySource[value.receipt.identity.replicaID]!,
                localSequence: value.receipt.identity.localSequence
            ).stableKey
        })
        guard targetReceiptIdentities.count == incomingOwned.count,
              retainedReceiptIdentities.isDisjoint(with: targetReceiptIdentities) else {
            throw PartsStockReplacementHistoryProjectionFailureV1.collision
        }

        let originalBaselines = try originalCatalogBaselines(
            snapshot: input.incomingSnapshot,
            history: input.incomingHistory
        )
        let stockMutations = incomingOwned.compactMap(\.partsStockMutation)
        let valueSource = PartsStockReplacementValueProjectionV1.Source(
            snapshot: input.incomingSnapshot,
            orderedMutations: stockMutations,
            originalCatalogBaselines: originalBaselines
        )
        let stockRequirements = try PartsStockReplacementValueProjectionV1
            .requirements(for: valueSource)
        var cursor = try PartsStockReplacementValueProjectionV1.begin(
            valueSource,
            bindings: .init(
                targetWorkspaceID: input.targetWorkspaceID,
                mutationIDs: try stockRequirements.mutationIDs.map { source in
                    guard let target = mutationIDBySource[source.rawValue] else {
                        throw PartsStockReplacementHistoryProjectionFailureV1.missingDependency
                    }
                    return .init(source: source, target: target)
                },
                workSubjects: try stockRequirements.workSubjects.map { source in
                    guard let target = subjectBySource[source] else {
                        throw PartsStockReplacementHistoryProjectionFailureV1.missingDependency
                    }
                    return .init(source: source, target: target)
                }
            )
        )
        let externalRequirementByEntryID = Dictionary(
            grouping: stockRequirements.externalWorkPredecessors,
            by: \.entryID
        )

        var retainedWorkByID: [UUID: WorkResourceEntryV1] = [:]
        for value in input.plannedWorkResources
            where !currentStockWorkEntryIDs.contains(value.entryID)
                && !incomingSourceWorkEntryIDs.contains(value.entryID) {
            try value.validate()
            guard value.workspaceID == input.targetWorkspaceID,
                  retainedWorkByID.updateValue(value, forKey: value.entryID) == nil else {
                throw PartsStockReplacementHistoryProjectionFailureV1.collision
            }
        }
        var targetWorkByID = retainedWorkByID
        var projectedValues: [(source: DecodedReceipt, command: WorkspaceCommandV1)] = []
        var projectedStockCount = 0
        var suppliedExternalRequirements = Set<
            PartsStockReplacementValueProjectionV1.ExternalWorkPredecessorRequirement
        >()

        for value in incomingOwned {
            if let round = roundBySourceID[value.envelope.mutationID] {
                guard round.source.record == value.record else {
                    throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
                }
                projectedValues.append((value, .applyRoundSession(round.mutation)))
                continue
            }
            if let sourceMutation = value.workResourceMutation {
                guard let targetMutationID = mutationIDBySource[sourceMutation.mutationID.rawValue],
                      let targetSubject = subjectBySource[sourceMutation.postImage.subject] else {
                    throw PartsStockReplacementHistoryProjectionFailureV1.missingDependency
                }
                let sourceActor = sourceMutation.postImage.actor
                let targetActor = try ActorSnapshotV1(
                    snapshotID: sourceActor.snapshotID,
                    workspaceID: input.targetWorkspaceID,
                    actor: LocalActorReferenceV1(
                        actorReferenceID: sourceActor.actor.actorReferenceID,
                        workspaceID: input.targetWorkspaceID,
                        partyID: sourceActor.actor.partyID,
                        displayName: sourceActor.actor.displayName
                    ),
                    responsibility: sourceActor.responsibility,
                    displayNameAtTime: sourceActor.displayNameAtTime,
                    capturedAt: sourceActor.capturedAt
                )
                let mappedPredecessorSHA256: String?
                if let predecessorID = sourceMutation.postImage.supersedesEntryID {
                    guard let predecessor = targetWorkByID[predecessorID] else {
                        throw PartsStockReplacementHistoryProjectionFailureV1.missingDependency
                    }
                    mappedPredecessorSHA256 = predecessor.entrySHA256
                } else {
                    mappedPredecessorSHA256 = nil
                }
                let targetEntry = try sourceMutation.postImage.rebound(
                    to: input.targetWorkspaceID,
                    mappedSubject: targetSubject,
                    mappedActor: targetActor,
                    mappedSupersedesEntrySHA256: mappedPredecessorSHA256,
                    mutationID: targetMutationID
                )
                guard targetWorkByID.updateValue(targetEntry, forKey: targetEntry.entryID) == nil else {
                    throw PartsStockReplacementHistoryProjectionFailureV1.collision
                }
                projectedValues.append((
                    value,
                    .applyWorkResource(try WorkResourceMutationV1(
                        workspaceID: input.targetWorkspaceID,
                        mutationID: targetMutationID,
                        postImage: targetEntry
                    ))
                ))
                continue
            }

            guard let sourceMutation = value.partsStockMutation else {
                throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
            }
            let sourceEntries = try partsStockWorkEntries(sourceMutation)
            var externalBindings: [
                PartsStockReplacementValueProjectionV1.ExternalWorkPredecessorBinding
            ] = []
            for entry in sourceEntries {
                guard let predecessorID = entry.supersedesEntryID else { continue }
                for requirement in externalRequirementByEntryID[predecessorID] ?? []
                    where requirement.revision == entry.expectedRevision
                        && requirement.sourceEntrySHA256 == entry.supersedesEntrySHA256
                        && !suppliedExternalRequirements.contains(requirement) {
                    guard let targetPredecessor = targetWorkByID[predecessorID] else {
                        throw PartsStockReplacementHistoryProjectionFailureV1.missingDependency
                    }
                    externalBindings.append(.init(
                        requirement: requirement,
                        targetEntrySHA256: targetPredecessor.entrySHA256
                    ))
                }
            }
            let step = try PartsStockReplacementValueProjectionV1.projectNext(
                cursor,
                externalWorkPredecessors: externalBindings
            )
            cursor = step.cursor
            suppliedExternalRequirements.formUnion(externalBindings.map(\.requirement))
            guard step.projection.source == sourceMutation else {
                throw PartsStockReplacementHistoryProjectionFailureV1.incompleteProjection
            }
            for entry in try partsStockWorkEntries(step.projection.target) {
                if let existing = targetWorkByID[entry.entryID] {
                    guard existing == entry else {
                        throw PartsStockReplacementHistoryProjectionFailureV1.collision
                    }
                } else {
                    targetWorkByID[entry.entryID] = entry
                }
            }
            projectedValues.append((value, .applyPartsStock(step.projection.target)))
            projectedStockCount += 1
        }
        guard projectedStockCount == stockMutations.count else {
            throw PartsStockReplacementHistoryProjectionFailureV1.incompleteProjection
        }
        let valueResult = try PartsStockReplacementValueProjectionV1.finish(cursor)

        let targetStockEntryByID = try canonicalWorkByID(
            snapshotWorkEntries(valueResult.targetSnapshot)
        )
        guard targetStockEntryByID.allSatisfy({ targetWorkByID[$0.key] == $0.value }) else {
            throw PartsStockReplacementHistoryProjectionFailureV1.incompleteProjection
        }

        // An empty C49/C55 replacement has no receipt ownership. Rebuilding
        // unrelated target receipts would change their original generation,
        // source kind and bytes despite there being no stock effect to emit.
        // Reach this only after the complete source, binding and value checks.
        let preservesUnrelatedTargetHistory = isEmpty(input.currentSnapshot)
            && isEmpty(input.incomingSnapshot) && isEmpty(valueResult.targetSnapshot)
            && input.currentWorkResources.isEmpty && input.incomingWorkResources.isEmpty
            && input.plannedWorkResources.isEmpty
            && currentValues.allSatisfy({ !$0.isWorkResource && !$0.isPartsStock })
            && incomingValues.allSatisfy({ !$0.isWorkResource && !$0.isPartsStock })
            && plannedValues.allSatisfy({ !$0.isWorkResource && !$0.isPartsStock })
            && currentRemovedMutationKeys.isEmpty && originalBaselines.isEmpty
            && targetWorkByID.isEmpty
        if preservesUnrelatedTargetHistory && projectedValues.isEmpty {
            return Result(sourceSnapshotSHA256: valueResult.sourceSnapshotSHA256,
                          targetSnapshot: valueResult.targetSnapshot,
                          history: input.plannedHistory, workResources: [], roundSessions: [])
        }

        var terminal: [WorkspaceEntityIdentityV1: UInt64] = [:]
        var externalRevisionByIdentity: [
            WorkspaceEntityIdentityV1: MutationHistoryEntityRevisionV1
        ] = [:]
        for baseline in originalBaselines {
            switch baseline {
            case let .part(_, source):
                guard let target = valueResult.parts.first(where: { $0.source == source })?.target else {
                    throw PartsStockReplacementHistoryProjectionFailureV1.missingDependency
                }
                let identity = try WorkspaceEntityIdentityV1(
                    kind: .localPartDefinition, id: target.partID
                )
                terminal[identity] = 1
                externalRevisionByIdentity[identity] = .init(
                    identity: identity,
                    revision: target.revision,
                    externalProjectionSHA256: target.partSHA256
                )
            case let .location(_, source):
                guard let target = valueResult.locations.first(where: { $0.source == source })?.target else {
                    throw PartsStockReplacementHistoryProjectionFailureV1.missingDependency
                }
                let identity = try WorkspaceEntityIdentityV1(
                    kind: .stockStorageLocation, id: target.locationID
                )
                terminal[identity] = 1
                externalRevisionByIdentity[identity] = .init(
                    identity: identity,
                    revision: target.revision,
                    externalProjectionSHA256: try PartsStockCanonicalCodecV1.sha256(target)
                )
            }
        }

        var targetReceiptBySourceMutationID: [UUID: MutationReceiptV1] = [:]
        var targetBasisBySourceMutationID: [UUID: ReversalBasisV1] = [:]
        var targetRecords: [MutationHistoryReceiptRecordV1] = []
        var identityMapBySourceKey: [String: IdentityMap] = [:]
        var workspaceRevision: UInt64 = 0
        if preservesUnrelatedTargetHistory {
            // Retained source receipts remain historical evidence. Only the
            // actual destination receipt prefix seeds this emission frontier.
            // The final snapshot below still covers every historical postimage.
            targetRecords = retainedTarget.map(\.record)
            for value in retainedTarget {
                workspaceRevision = max(workspaceRevision, value.receipt.resultingRevision.workspaceRevision)
                for row in value.receipt.resultingRevision.entityRevisions {
                    terminal[row.identity] = max(terminal[row.identity, default: 0], row.revision)
                }
                for image in value.receipt.postImages {
                    for identity in try ReplacementHistoryCommandEmissionV1.terminalIdentities(for: image) {
                        terminal[identity] = max(terminal[identity, default: 0], image.revision)
                    }
                }
            }
            for command in roundCommands {
                guard terminal[try command.mutation.concurrencyIdentity] == nil else {
                    throw PartsStockReplacementHistoryProjectionFailureV1.collision
                }
            }
        }

        for value in projectedValues {
            let emitted = try ReplacementHistoryCommandEmissionV1.emitProjected(
                source: value.source,
                command: value.command,
                workspaceRevision: workspaceRevision,
                terminal: &terminal,
                targetWorkspaceID: input.targetWorkspaceID,
                targetGenerationID: input.targetGenerationID,
                writerInstanceID: input.writerInstanceID,
                mutationIDBySource: mutationIDBySource,
                replicaBySource: replicaBySource,
                targetReceiptBySourceMutationID: targetReceiptBySourceMutationID,
                targetBasisBySourceMutationID: targetBasisBySourceMutationID,
                sourceValues: incomingOwned
            )
            workspaceRevision = emitted.receipt.resultingRevision.workspaceRevision
            targetReceiptBySourceMutationID[value.source.envelope.mutationID.rawValue] = emitted.receipt
            if let basis = emitted.basis {
                targetBasisBySourceMutationID[value.source.envelope.mutationID.rawValue] = basis
            }
            targetRecords.append(emitted.record)
            identityMapBySourceKey[value.source.mutationKey] = emitted.identityMap
        }

        let removedIdentities = try removedProjectionIdentities(
            snapshot: input.currentSnapshot,
            stockWorkEntryIDs: currentStockWorkEntryIDs
        )
        for value in retainedTarget where !preservesUnrelatedTargetHistory {
            let emitted = try ReplacementHistoryCommandEmissionV1.emitRetained(
                source: value,
                workspaceRevision: workspaceRevision,
                terminal: &terminal,
                removedIdentities: removedIdentities,
                targetGenerationID: input.targetGenerationID,
                writerInstanceID: input.writerInstanceID
            )
            workspaceRevision = emitted.receipt.resultingRevision.workspaceRevision
            targetRecords.append(emitted.record)
            identityMapBySourceKey[value.mutationKey] = emitted.identityMap
        }
        // Incumbent restore semantics retain the complete original foreign
        // history. Only its source-owned C49/C55 partition is additionally
        // normalized into the active destination workspace above.
        targetRecords.append(contentsOf: retainedHistoric.map(\.record))

        var quarantines: [MutationHistoryQuarantineRecordV1] = []
        for quarantine in input.plannedHistory.quarantines {
            let sourceKey = ReplacementHistoryCommandEmissionV1.mutationKey(
                workspaceID: quarantine.workspaceID,
                mutationID: quarantine.mutationID
            )
            guard let mapped = identityMapBySourceKey[sourceKey] else {
                if preservesUnrelatedTargetHistory,
                   retainedTarget.contains(where: { $0.mutationKey == sourceKey }) {
                    quarantines.append(quarantine)
                    continue
                }
                if currentRemovedMutationKeys.contains(sourceKey) { continue }
                if quarantine.workspaceID != input.targetWorkspaceID,
                   !incomingOwnedMutationKeys.contains(sourceKey) {
                    quarantines.append(quarantine)
                    continue
                }
                throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
            }
            if quarantine.workspaceID != input.targetWorkspaceID,
               incomingOwnedMutationKeys.contains(sourceKey) {
                quarantines.append(quarantine)
            }
            let sourceAccepted: String?
            let targetAccepted: String?
            switch quarantine.identityDomain {
            case .mutationEnvelope:
                sourceAccepted = mapped.sourceEnvelopeSHA256
                targetAccepted = mapped.targetEnvelopeSHA256
            case .semanticReversalReplayIdentity:
                sourceAccepted = mapped.sourceReplaySHA256
                targetAccepted = mapped.targetReplaySHA256
            }
            guard quarantine.acceptedIdentitySHA256 == sourceAccepted,
                  let targetAccepted else {
                throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
            }
            quarantines.append(.init(
                workspaceID: input.targetWorkspaceID,
                mutationID: mapped.targetMutationID.rawValue,
                identityDomain: quarantine.identityDomain,
                acceptedIdentitySHA256: targetAccepted,
                conflictingIdentitySHA256: quarantine.conflictingIdentitySHA256,
                detectedAt: quarantine.detectedAt
            ))
        }
        guard Set(quarantines.map {
            ReplacementHistoryCommandEmissionV1.mutationKey(workspaceID: $0.workspaceID, mutationID: $0.mutationID)
        }).count == quarantines.count else {
            throw PartsStockReplacementHistoryProjectionFailureV1.collision
        }

        var revisionByIdentity: [
            WorkspaceEntityIdentityV1: MutationHistoryEntityRevisionV1
        ] = [:]
        for row in input.plannedHistory.entityRevisions
            where !removedIdentities.contains(row.identity)
                && !incomingSourceWorkEntryIDs.contains(row.identity.id) {
            revisionByIdentity[row.identity] = row
        }
        for (identity, revision) in terminal {
            if let existing = revisionByIdentity[identity], existing.revision > revision {
                // The retained foreign receipts still require this frontier.
                // A destination append must not erase their higher revision.
                continue
            }
            if let existing = revisionByIdentity[identity],
               existing.revision == revision,
               existing.externalProjectionSHA256 != nil {
                continue
            }
            revisionByIdentity[identity] = MutationHistoryEntityRevisionV1(
                identity: identity,
                revision: revision,
                externalProjectionSHA256: nil
            )
        }
        for (identity, external) in externalRevisionByIdentity {
            guard terminal[identity].map({ $0 <= external.revision }) ?? true else {
                throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
            }
            revisionByIdentity[identity] = external
        }
        let history = MutationHistorySnapshotV1(
            workspaceRevision: workspaceRevision,
            lastLocalSequence: 0,
            receipts: targetRecords,
            quarantines: quarantines.sorted {
                let lhs = ReplacementHistoryCommandEmissionV1.mutationKey(workspaceID: $0.workspaceID, mutationID: $0.mutationID)
                let rhs = ReplacementHistoryCommandEmissionV1.mutationKey(workspaceID: $1.workspaceID, mutationID: $1.mutationID)
                return lhs < rhs
            },
            entityRevisions: revisionByIdentity.values.sorted {
                $0.identity.stableKey < $1.identity.stableKey
            }
        )
        try MutationJournalStoreV1.validateImportedSnapshot(history)
        return Result(
            sourceSnapshotSHA256: valueResult.sourceSnapshotSHA256,
            targetSnapshot: valueResult.targetSnapshot,
            history: history,
            workResources: targetWorkByID.values.sorted {
                ($0.workspaceID.rawValue.uuidString, $0.entryID.uuidString)
                    < ($1.workspaceID.rawValue.uuidString, $1.entryID.uuidString)
            },
            roundSessions: roundCommands.map { $0.mutation.session }
        )
    }
}

private extension PartsStockReplacementHistoryProjectionV1 {
    static func authenticatedRoundCommands(
        _ projection: RoundSessionReplacementCommandProjectionV1.Projection?,
        history: MutationHistorySnapshotV1, workspaceID: WorkspaceID
    ) throws -> [RoundSessionReplacementCommandProjectionV1.Command] {
        guard let projection else { return [] }
        guard projection.source.history == history,
              projection.source.workspaceID == workspaceID,
              projection.identity.mode == .replaceExisting,
              projection.identity.source.workspaceID == workspaceID.rawValue,
              projection.identity.targetPointer.workspaceID != workspaceID.rawValue else {
            throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
        }
        return projection.commands
    }

    static func isEmpty(_ snapshot: PartsStockBackupSnapshotV1) -> Bool {
        snapshot.parts.isEmpty && snapshot.locations.isEmpty && snapshot.movements.isEmpty
            && snapshot.uses.isEmpty && snapshot.reversals.isEmpty
            && snapshot.returns.isEmpty && snapshot.abandonments.isEmpty
    }

    private typealias DecodedReceipt = ReplacementHistoryCommandEmissionV1.DecodedReceipt
    private typealias IdentityMap = ReplacementHistoryCommandEmissionV1.IdentityMap

    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    static func exactMutationBindings(
        _ bindings: [MutationBinding], required: [MutationIDV1]
    ) throws -> [UUID: MutationIDV1] {
        guard bindings.count == required.count,
              Set(bindings.map(\.source)) == Set(required),
              Set(bindings.map(\.target)).count == bindings.count,
              bindings.allSatisfy({ $0.source != $0.target }) else {
            throw PartsStockReplacementHistoryProjectionFailureV1.invalidBinding
        }
        return Dictionary(uniqueKeysWithValues: bindings.map { ($0.source.rawValue, $0.target) })
    }

    static func exactSubjectBindings(
        _ bindings: [SubjectBinding],
        required: [WorkResourceSubjectV1],
        targetWorkspaceID: WorkspaceID
    ) throws -> [WorkResourceSubjectV1: WorkResourceSubjectV1] {
        guard bindings.count == required.count,
              Set(bindings.map(\.source)) == Set(required),
              Set(bindings.map(\.target)).count == bindings.count else {
            throw PartsStockReplacementHistoryProjectionFailureV1.invalidBinding
        }
        var result: [WorkResourceSubjectV1: WorkResourceSubjectV1] = [:]
        for binding in bindings {
            try binding.source.validate()
            try binding.target.validate()
            guard binding.target.workspaceID == targetWorkspaceID,
                  binding.target.kind == binding.source.kind,
                  binding.target.subjectID == binding.source.subjectID,
                  binding.target.subjectRevision == binding.source.subjectRevision,
                  binding.target.subjectSHA256 != binding.source.subjectSHA256,
                  result.updateValue(binding.target, forKey: binding.source) == nil else {
                throw PartsStockReplacementHistoryProjectionFailureV1.invalidBinding
            }
        }
        return result
    }

    static func exactReplicaBindings(
        _ bindings: [ReplicaBinding],
        required: [ReplicaID],
        targetWorkspaceID: WorkspaceID
    ) throws -> [ReplicaID: ReplicaID] {
        guard bindings.count == required.count,
              Set(bindings.map(\.source)) == Set(required),
              Set(bindings.map(\.target)).count == bindings.count,
              bindings.allSatisfy({
                  $0.source != $0.target && $0.target.rawValue != targetWorkspaceID.rawValue
              }) else {
            throw PartsStockReplacementHistoryProjectionFailureV1.invalidBinding
        }
        return Dictionary(uniqueKeysWithValues: bindings.map { ($0.source, $0.target) })
    }

    static func originalCatalogBaselines(
        snapshot: PartsStockBackupSnapshotV1,
        history: MutationHistorySnapshotV1
    ) throws -> [PartsStockReplacementValueProjectionV1.OriginalCatalogBaseline] {
        let parts = Dictionary(uniqueKeysWithValues: snapshot.parts.map { ($0.partID, $0) })
        let locations = Dictionary(uniqueKeysWithValues: snapshot.locations.map { ($0.locationID, $0) })
        return try history.entityRevisions.compactMap { row in
            guard row.externalProjectionSHA256 != nil else { return nil }
            switch row.identity.kind {
            case .localPartDefinition:
                guard let part = parts[row.identity.id],
                      part.revision == row.revision,
                      part.partSHA256 == row.externalProjectionSHA256 else {
                    throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
                }
                return .part(entityRevision: row, value: part)
            case .stockStorageLocation:
                guard let location = locations[row.identity.id],
                      location.revision == row.revision,
                      try PartsStockCanonicalCodecV1.sha256(location)
                        == row.externalProjectionSHA256 else {
                    throw PartsStockReplacementHistoryProjectionFailureV1.invalidSource
                }
                return .location(entityRevision: row, value: location)
            default:
                return nil
            }
        }
    }

    static func partsStockWorkEntries(
        _ mutation: PartsStockMutationV1
    ) throws -> [WorkResourceEntryV1] {
        try mutation.validate()
        switch mutation {
        case let .use(value):
            return [value.workResourceSuccessor]
        case let .reverseUse(value):
            return [value.sourceUse.workResourceSuccessor, value.workResourceSuccessor]
        case let .returnAgainstUse(value):
            return [
                value.sourceUse.workResourceSuccessor,
                value.workResourcePredecessor,
                value.workResourceSuccessor,
            ]
        default:
            return []
        }
    }

    static func snapshotWorkEntries(
        _ snapshot: PartsStockBackupSnapshotV1
    ) -> [WorkResourceEntryV1] {
        snapshot.uses.map(\.workResourceSuccessor)
            + snapshot.reversals.flatMap {
                [$0.sourceUse.workResourceSuccessor, $0.workResourceSuccessor]
            }
            + snapshot.returns.flatMap {
                [
                    $0.sourceUse.workResourceSuccessor,
                    $0.workResourcePredecessor,
                    $0.workResourceSuccessor,
                ]
            }
    }

    static func canonicalWorkByID(
        _ values: [WorkResourceEntryV1]
    ) throws -> [UUID: WorkResourceEntryV1] {
        var result: [UUID: WorkResourceEntryV1] = [:]
        for value in values {
            if let existing = result[value.entryID] {
                guard existing == value else {
                    throw PartsStockReplacementHistoryProjectionFailureV1.collision
                }
            } else {
                result[value.entryID] = value
            }
        }
        return result
    }

    static func removedProjectionIdentities(
        snapshot: PartsStockBackupSnapshotV1,
        stockWorkEntryIDs: Set<UUID>
    ) throws -> Set<WorkspaceEntityIdentityV1> {
        var result = Set<WorkspaceEntityIdentityV1>()
        for value in snapshot.parts {
            result.insert(try .init(kind: .localPartDefinition, id: value.partID))
        }
        for value in snapshot.locations {
            result.insert(try .init(kind: .stockStorageLocation, id: value.locationID))
        }
        for value in snapshot.movements {
            result.insert(try .init(kind: .stockMovementEvent, id: value.movementID))
            result.insert(try StockBalanceStreamIdentityV1.entity(
                partID: value.part.partID, locationID: value.locationID
            ))
        }
        for value in snapshot.uses {
            result.insert(try .init(kind: .stockUseReceipt, id: value.receiptID))
        }
        for value in snapshot.reversals {
            result.insert(try .init(kind: .stockUseReversalReceipt, id: value.receiptID))
        }
        for value in snapshot.returns {
            result.insert(try .init(kind: .stockReturnReceipt, id: value.receiptID))
        }
        for value in snapshot.abandonments {
            result.insert(try .init(kind: .stockAbandonment, id: value.dispositionID))
        }
        for id in stockWorkEntryIDs {
            result.insert(try .init(kind: .workResourceEntry, id: id))
        }
        return result
    }

    static func subjectLessThan(
        _ lhs: WorkResourceSubjectV1, _ rhs: WorkResourceSubjectV1
    ) -> Bool {
        (lhs.kind.rawValue, lhs.subjectID, lhs.subjectRevision, lhs.subjectSHA256)
            < (rhs.kind.rawValue, rhs.subjectID, rhs.subjectRevision, rhs.subjectSHA256)
    }
}

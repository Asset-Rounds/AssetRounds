import Foundation

struct InstallationWorkflowContextV1: Equatable, Sendable {
    let envelope: ActivitySessionEnvelopeV2
    let release: InstallationWorkflowDefinitionReleaseV1
    let basis: InstallationBasisSnapshotV1
    let taskHistory: [InstallationTaskResultV1]
    let asBuiltSnapshot: InstallationAsBuiltSnapshotV1?
    let planCapability: InstallationPlanCapabilityV1
    let scanCapability: InstallationScanCapabilityV1

    init(envelope: ActivitySessionEnvelopeV2,
         release: InstallationWorkflowDefinitionReleaseV1,
         basis: InstallationBasisSnapshotV1,
         taskHistory: [InstallationTaskResultV1] = [],
         asBuiltSnapshot: InstallationAsBuiltSnapshotV1? = nil,
         planCapability: InstallationPlanCapabilityV1,
         scanCapability: InstallationScanCapabilityV1) throws {
        self.envelope = envelope; self.release = release; self.basis = basis; self.taskHistory = taskHistory
        self.asBuiltSnapshot = asBuiltSnapshot; self.planCapability = planCapability
        self.scanCapability = scanCapability
        try validate()
    }

    func validate() throws {
        try envelope.validateForRead(); try release.validate(); try basis.validate()
        try planCapability.validate(); try scanCapability.validate(); try asBuiltSnapshot?.validate()
        guard envelope.kind == .installation, envelope.workspaceID == release.workspaceID,
              basis.workspaceID == envelope.workspaceID,
              basis.activityID == envelope.activityID,
              basis.subjectID == envelope.subjectID,
              case let .installation(basisReference)? = envelope.currentBasisReference,
              basisReference == (try InstallationBasisReferenceV1(basis)),
              basis.workflowReleaseReference.bundledRelease == .installationV1,
              basis.workflowReleaseReference.targetWorkspaceID == release.workspaceID,
              basis.workflowReleaseReference.targetReleaseID == release.releaseID,
              basis.workflowReleaseReference.targetReleaseRevision == release.revision,
              basis.workflowReleaseReference.targetReleaseSHA256 == release.releaseSHA256,
              taskHistory.allSatisfy({ $0.workspaceID == envelope.workspaceID && $0.activityID == envelope.activityID }),
              asBuiltSnapshot.map({ $0.workspaceID == envelope.workspaceID && $0.activityID == envelope.activityID }) ?? true else {
            throw InstallationWorkflowFailureV1.invalidContext
        }
        let taskIDs = Set(release.tasks.map(\.taskID))
        guard taskHistory.allSatisfy({ taskIDs.contains($0.taskID) }) else {
            throw InstallationWorkflowFailureV1.unknownTask
        }
        _ = try InstallationTaskResultLineageV1.validateAndCurrentHeads(taskHistory)
        if let reference = planCapability.planReference {
            guard reference.workspaceID == envelope.workspaceID,
                  reference.measurementSubjectID == envelope.subjectID,
                  case let .optionalPlan(sourceReference) = basis.source,
                  sourceReference.referenceID == reference.planID.uuidString,
                  sourceReference.revision == reference.planVersion,
                  sourceReference.sha256 == reference.planSHA256 else {
                throw InstallationWorkflowFailureV1.invalidContext
            }
        } else if let fallback = planCapability.noPlanFallback {
            guard case let .noPlan(basisFallback) = basis.source,
                  basisFallback == fallback else {
                throw InstallationWorkflowFailureV1.invalidContext
            }
        }
        if let receipt = scanCapability.scanReceipt {
            guard receipt.workspaceID == envelope.workspaceID, receipt.assetID == envelope.subjectID else {
                throw InstallationWorkflowFailureV1.invalidContext
            }
        }
        if let manual = scanCapability.manualFallback,
           manual.workspaceID != envelope.workspaceID {
            throw InstallationWorkflowFailureV1.invalidContext
        }
        if let asBuiltSnapshot {
            let heads = try InstallationTaskResultLineageV1.validateAndCurrentHeads(taskHistory)
            guard asBuiltSnapshot.taskResultSHA256s == heads.values.map(\.resultSHA256).sorted(),
                  asBuiltSnapshot.basisReference == basisReference,
                  envelope.installationCloseout.map({
                      $0.asBuiltSnapshotSHA256 == asBuiltSnapshot.snapshotSHA256
                        && $0.completion == asBuiltSnapshot.completion
                  }) ?? true else {
                throw InstallationWorkflowFailureV1.divergentAsBuilt
            }
        }
    }
}

enum InstallationWorkflowCommandV1: Equatable, Sendable {
    case start(ActivityContractMutationV2)
    case resume(ActivityContractMutationV2)
    case pause(ActivityContractMutationV2)
    case interrupt(ActivityContractMutationV2)
    case recordTaskResult(ActivityContractMutationV2)
    case recordAsBuilt(ActivityContractMutationV2)
    case recordVariation(ActivityContractMutationV2)
    case closeout(ActivityContractMutationV2)

    var mutation: ActivityContractMutationV2 {
        switch self {
        case let .start(value), let .resume(value), let .pause(value), let .interrupt(value),
             let .recordTaskResult(value), let .recordAsBuilt(value), let .recordVariation(value),
             let .closeout(value): return value
        }
    }
}

@MainActor
final class InstallationWorkflowCoordinatorV1 {
    private let contractCoordinator: ActivityContractCoordinatorV2
    private let installationContractSHA256: String
    private let noPlanFallback: NoPlanFallbackV1

    init(contractCoordinator: ActivityContractCoordinatorV2,
         installationContractSHA256: String,
         noPlanFallback: NoPlanFallbackV1) throws {
        guard KernelCanonicalHashV1.validSHA256(installationContractSHA256) else {
            throw InstallationWorkflowFailureV1.invalidContext
        }
        try noPlanFallback.validate()
        self.contractCoordinator = contractCoordinator
        self.installationContractSHA256 = installationContractSHA256
        self.noPlanFallback = noPlanFallback
    }

    func projection(for context: InstallationWorkflowContextV1) throws
        -> InstallationWorkflowProjectionV1 {
        try context.validate()
        let blockers = readinessBlockers(envelope: context.envelope, release: context.release)
        let heads = try InstallationTaskResultLineageV1.validateAndCurrentHeads(context.taskHistory)
        let tasks = context.release.tasks.sorted().map {
            InstallationTaskProjectionV1(definition: $0, currentResult: heads[$0.taskID])
        }
        let nextTaskID = nextOrderedTaskID(release: context.release, heads: heads)
        let canStart = context.envelope.state == .ready && blockers.isEmpty
        let nextCloseoutAction = closeoutAction(context: context, tasks: tasks)
        let reportReadiness: InstallationReportReadinessV1 = context.envelope.state == .finalized
            && context.envelope.installationCloseout != nil && context.asBuiltSnapshot != nil
            ? .readyForExistingRenderer
            : ([.fieldComplete, .readyForReview].contains(context.envelope.state)
                ? .reviewRequired : .fieldWorkIncomplete)
        return InstallationWorkflowProjectionV1(
            envelope: context.envelope, blockers: blockers, tasks: tasks,
            nextTaskID: nextTaskID,
            planDisposition: context.planCapability.disposition,
            scanDisposition: context.scanCapability.disposition,
            canStart: canStart, canCloseout: nextCloseoutAction != nil,
            nextCloseoutAction: nextCloseoutAction,
            reportReadiness: reportReadiness,
            reportReady: reportReadiness == .readyForExistingRenderer,
            closeoutRecorded: context.envelope.installationCloseout != nil,
            report: try InstallationReportProjectionV1(
                envelope: context.envelope,
                taskResults: heads.values.sorted(),
                asBuiltSnapshot: context.asBuiltSnapshot
            )
        )
    }

    func execute(_ command: InstallationWorkflowCommandV1,
                 context: InstallationWorkflowContextV1) async throws
        -> ActivityContractAcceptanceResultV2 {
        try context.validate()
        if let fallback = context.planCapability.noPlanFallback, fallback != noPlanFallback {
            throw InstallationWorkflowFailureV1.invalidContext
        }
        let mutation = command.mutation
        try validateCommon(mutation, context: context)
        try validate(command, context: context)
        let request = try ActivityContractAcceptanceRequestV2(
            family: .installation,
            mutation: mutation,
            sharedReceipt: contractCoordinator.sharedConformanceReceipt,
            independentFamilyContractSHA256: installationContractSHA256,
            noPlanFallback: noPlanFallback
        )
        return try await contractCoordinator.accept(request)
    }

    /// Recovery is the same MutationID command replay. The canonical seam
    /// returns the existing durable receipt or commits exactly once.
    func recover(_ command: InstallationWorkflowCommandV1,
                 context: InstallationWorkflowContextV1) async throws
        -> ActivityContractAcceptanceResultV2 {
        do {
            return try await execute(command, context: context)
        } catch {
            // One bounded replay uses the identical expected revision and
            // MutationID. The canonical coordinator admits only the original
            // predecessor or its exact unreceipted successor; divergence
            // remains stale and the second error is surfaced.
            return try await execute(command, context: context)
        }
    }

    private func validateCommon(_ mutation: ActivityContractMutationV2,
                                context: InstallationWorkflowContextV1) throws {
        try mutation.validate()
        guard mutation.workspaceID == context.envelope.workspaceID,
              mutation.predecessorEnvelope == context.envelope,
              mutation.successorEnvelope.activityID == context.envelope.activityID,
              mutation.successorEnvelope.kind == .installation else {
            throw InstallationWorkflowFailureV1.invalidCommand
        }
    }

    private func validate(_ command: InstallationWorkflowCommandV1,
                          context: InstallationWorkflowContextV1) throws {
        let mutation = command.mutation
        let from = context.envelope.state, to = mutation.successorEnvelope.state
        switch command {
        case .start:
            guard from == .ready, to == .inProgress,
                  readinessBlockers(envelope: context.envelope, release: context.release).isEmpty,
                  hasNoWorkPayload(mutation) else { throw InstallationWorkflowFailureV1.blockedReadiness }
        case .resume:
            guard [.paused, .changesRequested].contains(from), to == .inProgress,
                  hasNoWorkPayload(mutation) else {
                throw InstallationWorkflowFailureV1.invalidCommand
            }
        case .pause:
            guard from == .inProgress, to == .paused, hasNoWorkPayload(mutation) else {
                throw InstallationWorkflowFailureV1.invalidCommand
            }
        case .interrupt:
            guard [.inProgress, .paused].contains(from), [.deferred, .unableToComplete, .cancelled].contains(to),
                  mutation.transition?.reason != nil, hasNoWorkPayload(mutation) else {
                throw InstallationWorkflowFailureV1.invalidCommand
            }
        case .recordTaskResult:
            guard from == .inProgress, to == from, mutation.transition == nil,
                  mutation.installationTaskResults.count == 1,
                  mutation.installationBasisSnapshot == nil,
                  mutation.installationAsBuiltSnapshot == nil,
                  mutation.successorEnvelope.variations == context.envelope.variations else {
                throw InstallationWorkflowFailureV1.invalidCommand
            }
            try validateOrderedTaskResult(
                mutation.installationTaskResults[0], context: context
            )
            try validateTaskResults(context.taskHistory + mutation.installationTaskResults, release: context.release)
        case .recordAsBuilt:
            guard from == .inProgress, to == from, mutation.transition == nil,
                  mutation.installationAsBuiltSnapshot != nil,
                  mutation.successorEnvelope.installationCloseout == context.envelope.installationCloseout,
                  mutation.successorEnvelope.variations == context.envelope.variations else {
                throw InstallationWorkflowFailureV1.invalidCommand
            }
            try validateAsBuilt(mutation, context: context)
        case .recordVariation:
            guard [.inProgress, .paused, .changesRequested].contains(from),
                  to == from, mutation.transition == nil,
                  mutation.successorEnvelope.variations.count == context.envelope.variations.count + 1,
                  mutation.installationTaskResults.isEmpty,
                  mutation.installationAsBuiltSnapshot == nil else {
                throw InstallationWorkflowFailureV1.invalidCommand
            }
            try validateVariation(mutation, context: context)
        case .closeout:
            guard (from == .inProgress && to == .fieldComplete)
                    || (from == .fieldComplete && to == .readyForReview)
                    || (from == .readyForReview && to == .finalized),
                  mutation.installationAsBuiltSnapshot == nil,
                  context.asBuiltSnapshot != nil else {
                throw InstallationWorkflowFailureV1.invalidCommand
            }
            if to == .finalized {
                guard mutation.successorEnvelope.installationCloseout != nil else {
                    throw InstallationWorkflowFailureV1.invalidCommand
                }
            } else {
                guard mutation.successorEnvelope.installationCloseout == nil else {
                    throw InstallationWorkflowFailureV1.invalidCommand
                }
            }
            let history = context.taskHistory + mutation.installationTaskResults
            let heads = try validateTaskResults(history, release: context.release)
            guard heads.count == context.release.tasks.count,
                  context.asBuiltSnapshot != nil else {
                throw InstallationWorkflowFailureV1.incompleteRequiredTask
            }
            if from == .inProgress {
                guard heads.values.allSatisfy({ ![.notStarted, .inProgress].contains($0.outcome) }) else {
                    throw InstallationWorkflowFailureV1.incompleteRequiredTask
                }
            }
        }
    }

    private func readinessBlockers(envelope: ActivitySessionEnvelopeV2,
                                   release: InstallationWorkflowDefinitionReleaseV1)
        -> [InstallationReadinessBlockerV1] {
        let required = Set(release.readinessPolicy.requiredFacets)
        var blockers = envelope.readiness.compactMap { facet -> InstallationReadinessBlockerV1? in
            guard facet.disposition == .blocked || facet.disposition == .deferred else { return nil }
            return InstallationReadinessBlockerV1(
                facetID: facet.facetID, kind: facet.kind, disposition: facet.disposition,
                reason: facet.reason ?? "Readiness must be resolved before starting."
            )
        }
        let present = Set(envelope.readiness.map(\.kind))
        for missing in required.subtracting(present) {
            blockers.append(InstallationReadinessBlockerV1(
                facetID: "missing-\(missing.rawValue.lowercased())", kind: missing,
                disposition: .blocked, reason: "Required readiness has not been recorded."
            ))
        }
        return blockers.sorted()
    }

    private func closeoutAction(context: InstallationWorkflowContextV1,
                                tasks: [InstallationTaskProjectionV1])
        -> InstallationCloseoutActionV1? {
        let hasAsBuilt = context.asBuiltSnapshot != nil
        let hasAllTaskHeads = tasks.allSatisfy { $0.currentResult != nil }
        switch context.envelope.state {
        case .inProgress:
            return hasAllTaskHeads && tasks.allSatisfy(\.isTerminal) && hasAsBuilt
                ? .recordFieldComplete : nil
        case .fieldComplete:
            return hasAllTaskHeads && hasAsBuilt ? .submitForReview : nil
        case .readyForReview:
            return hasAllTaskHeads && hasAsBuilt ? .finalizeRecordedCloseout : nil
        default:
            return nil
        }
    }

    private func validateVariation(_ mutation: ActivityContractMutationV2,
                                   context: InstallationWorkflowContextV1) throws {
        guard let basis = mutation.installationBasisSnapshot,
              case let .installation(predecessorReference)? = context.envelope.currentBasisReference,
              case let .installation(successorReference)? = mutation.successorEnvelope.currentBasisReference,
              successorReference == (try InstallationBasisReferenceV1(basis)),
              basis.mutationID == mutation.mutationID,
              basis.predecessorBasisID == predecessorReference.basisID,
              basis.predecessorBasisSHA256 == predecessorReference.basisSHA256,
              basis.workflowReleaseReference.bundledRelease == .installationV1,
              basis.workflowReleaseReference.targetWorkspaceID == context.release.workspaceID,
              basis.workflowReleaseReference.targetReleaseID == context.release.releaseID,
              basis.workflowReleaseReference.targetReleaseRevision == context.release.revision,
              basis.workflowReleaseReference.targetReleaseSHA256 == context.release.releaseSHA256,
              let variation = mutation.successorEnvelope.variations.last,
              variation.mutationID == mutation.mutationID,
              variation.predecessorBasisSHA256 == predecessorReference.basisSHA256,
              variation.successorBasisSHA256 == basis.basisSHA256,
              [.basisCorrected, .optionalPlanReferenceChanged,
               .physicalPlacementReferenceChanged].contains(variation.kind) else {
            throw InstallationWorkflowFailureV1.invalidCommand
        }
    }

    @discardableResult
    private func validateTaskResults(_ history: [InstallationTaskResultV1],
                                     release: InstallationWorkflowDefinitionReleaseV1) throws
        -> [String: InstallationTaskResultV1] {
        let ids = Set(release.tasks.map(\.taskID))
        guard history.allSatisfy({ ids.contains($0.taskID) }) else {
            throw InstallationWorkflowFailureV1.unknownTask
        }
        return try InstallationTaskResultLineageV1.validateAndCurrentHeads(history)
    }

    private func validateOrderedTaskResult(_ result: InstallationTaskResultV1,
                                           context: InstallationWorkflowContextV1) throws {
        let taskIDs = Set(context.release.tasks.map(\.taskID))
        guard taskIDs.contains(result.taskID) else {
            throw InstallationWorkflowFailureV1.unknownTask
        }
        let heads = try InstallationTaskResultLineageV1.validateAndCurrentHeads(context.taskHistory)
        guard let nextTaskID = nextOrderedTaskID(release: context.release, heads: heads),
              result.taskID == nextTaskID else {
            throw InstallationWorkflowFailureV1.invalidCommand
        }
        if let current = heads[nextTaskID] {
            let (nextRevision, overflow) = current.revision.addingReportingOverflow(1)
            guard !overflow, !taskResultIsTerminal(current),
                  result.revision == nextRevision,
                  result.predecessorResultID == current.resultID,
                  result.predecessorResultSHA256 == current.resultSHA256 else {
                throw InstallationWorkflowFailureV1.invalidCommand
            }
        } else {
            guard result.revision == 1, result.predecessorResultID == nil,
                  result.predecessorResultSHA256 == nil else {
                throw InstallationWorkflowFailureV1.invalidCommand
            }
        }
    }

    private func nextOrderedTaskID(
        release: InstallationWorkflowDefinitionReleaseV1,
        heads: [String: InstallationTaskResultV1]
    ) -> String? {
        release.tasks.sorted().first { definition in
            guard let result = heads[definition.taskID] else { return true }
            return !taskResultIsTerminal(result)
        }?.taskID
    }

    private func taskResultIsTerminal(_ result: InstallationTaskResultV1) -> Bool {
        ![.notStarted, .inProgress].contains(result.outcome)
    }

    private func validateAsBuilt(_ mutation: ActivityContractMutationV2,
                                 context: InstallationWorkflowContextV1) throws {
        guard let snapshot = mutation.installationAsBuiltSnapshot else {
            throw InstallationWorkflowFailureV1.invalidCommand
        }
        let heads = try validateTaskResults(
            context.taskHistory + mutation.installationTaskResults, release: context.release
        )
        guard heads.count == context.release.tasks.count,
              heads.values.allSatisfy({ ![.notStarted, .inProgress].contains($0.outcome) }),
              snapshot.taskResultSHA256s == heads.values.map(\.resultSHA256).sorted(),
              snapshot.basisReference == (try InstallationBasisReferenceV1(context.basis)),
              mutation.successorEnvelope.installationCloseout.map({
                  $0.asBuiltSnapshotSHA256 == snapshot.snapshotSHA256
                    && $0.completion == snapshot.completion
              }) ?? true else {
            throw InstallationWorkflowFailureV1.divergentAsBuilt
        }
    }

    private func hasNoWorkPayload(_ mutation: ActivityContractMutationV2) -> Bool {
        mutation.installationBasisSnapshot == nil
            && mutation.installationTaskResults.isEmpty && mutation.installationAsBuiltSnapshot == nil
            && mutation.successorEnvelope.variations == mutation.predecessorEnvelope?.variations
            && mutation.successorEnvelope.installationCloseout == mutation.predecessorEnvelope?.installationCloseout
    }
}

enum InstallationWorkflowCoordinatorBoundaryV1 {
    static let delegatesSoleCanonicalSeam = true
    static let expectedRevisionAndMutationIDRequired = true
    static let replayReturnsSameReceiptOrNoAdditionalEffect = true
    static let effectBeforeReceiptRecoverySupported = true
    static let optionalPlanAndScanHaveTypedFallback = true
    static let automaticCompletionFromEvidenceCount = false
    static let safetyCompliancePermitCommissioningApprovalAndServiceClaims = false
}

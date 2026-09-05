import Foundation

struct PunchReviewWorkflowContextV1: Equatable, Sendable {
    let envelope: ActivitySessionEnvelopeV2
    let release: PunchReviewWorkflowDefinitionReleaseV1
    let basis: PunchReviewBasisSnapshotV1
    let scopeDecisions: [PunchItemProjectionV1]
    let findings: [FindingV1]
    let correctiveActionEvents: [CorrectiveActionEventV1]
    let verifiedRechecks: [VerifiedRecheckV1]
    let sourceEnvelopes: [ActivitySessionEnvelopeV2]
    let planCapability: PunchReviewPlanCapabilityV1
    let installationSnapshot: PunchReviewInstallationSnapshotContextV1?
    let closeoutIntent: PunchReviewCloseoutV1?

    init(envelope: ActivitySessionEnvelopeV2,
         release: PunchReviewWorkflowDefinitionReleaseV1,
         basis: PunchReviewBasisSnapshotV1,
         scopeDecisions: [PunchItemProjectionV1] = [],
         findings: [FindingV1] = [],
         correctiveActionEvents: [CorrectiveActionEventV1] = [],
         verifiedRechecks: [VerifiedRecheckV1] = [],
         sourceEnvelopes: [ActivitySessionEnvelopeV2] = [],
         planCapability: PunchReviewPlanCapabilityV1,
         installationSnapshot: PunchReviewInstallationSnapshotContextV1? = nil,
         closeoutIntent: PunchReviewCloseoutV1? = nil) throws {
        self.envelope=envelope;self.release=release;self.basis=basis
        self.scopeDecisions=scopeDecisions;self.findings=findings
        self.correctiveActionEvents=correctiveActionEvents;self.verifiedRechecks=verifiedRechecks
        self.sourceEnvelopes=sourceEnvelopes;self.planCapability=planCapability
        self.installationSnapshot=installationSnapshot
        self.closeoutIntent=closeoutIntent
        try validate()
    }

    func validate() throws {
        try envelope.validateForRead();try release.validate();try basis.validate()
        try scopeDecisions.forEach{try $0.validate()};try correctiveActionEvents.forEach{try $0.validate()}
        try sourceEnvelopes.forEach{try $0.validateForRead()};try planCapability.validate()
        try installationSnapshot?.validate()
        try closeoutIntent?.validate()
        guard envelope.kind == .punchReview,envelope.workspaceID == release.workspaceID,
              basis.workspaceID == envelope.workspaceID,basis.activityID == envelope.activityID,
              basis.subjectID == envelope.subjectID,
              case let .punchReview(reference)? = envelope.currentBasisReference,
              reference == (try PunchReviewBasisReferenceV1(basis)),
              basis.workflowReleaseReference.bundledRelease == .punchReviewV1,
              basis.workflowReleaseReference.targetWorkspaceID == release.workspaceID,
              basis.workflowReleaseReference.targetReleaseID == release.releaseID,
              basis.workflowReleaseReference.targetReleaseRevision == release.revision,
              basis.workflowReleaseReference.targetReleaseSHA256 == release.releaseSHA256 else {
            throw PunchReviewWorkflowFailureV1.invalidContext
        }
        let scopeIDs=Set(release.scope.map(\.scopeItemID))
        guard scopeDecisions.allSatisfy({scopeIDs.contains($0.scopeItemID)}),
              Set(scopeDecisions.map(\.scopeItemID)).count == scopeDecisions.count else {
            throw PunchReviewWorkflowFailureV1.duplicateDecision
        }
        if let closeout=envelope.punchReviewCloseout {
            guard closeout.basisSHA256==basis.basisSHA256,
                  closeout.scope==scopeDecisions.sorted(by:{$0.scopeItemID<$1.scopeItemID}) else {
                throw PunchReviewWorkflowFailureV1.unresolvedCloseoutCount
            }
        }
        if let closeoutIntent {
            guard closeoutIntent.basisSHA256==basis.basisSHA256,
                  closeoutIntent.scope==scopeDecisions.sorted(by:{$0.scopeItemID<$1.scopeItemID}),
                  envelope.punchReviewCloseout.map({$0==closeoutIntent}) ?? true else {
                throw PunchReviewWorkflowFailureV1.unresolvedCloseoutCount
            }
        }
        switch (planCapability.disposition,basis.source) {
        case let (.available,.optionalPlan(source)):
            guard let plan=planCapability.planReference,plan.workspaceID==envelope.workspaceID,
                  plan.measurementSubjectID==envelope.subjectID,
                  source.referenceID==plan.planID.uuidString,source.revision==plan.planVersion,
                  source.sha256==plan.planSHA256 else{throw PunchReviewWorkflowFailureV1.invalidContext}
        case let (.manualFallback,.noPlan(source)):
            guard let fallback=planCapability.noPlanFallback,source==fallback
            else{throw PunchReviewWorkflowFailureV1.invalidContext}
        case let (.unavailable,.noPlan(source)):
            guard let fallback=planCapability.noPlanFallback,source==fallback
            else{throw PunchReviewWorkflowFailureV1.invalidContext}
        case let (.externalLocal,.externalLocal(source)):
            guard let external=planCapability.externalReference,source==external
            else{throw PunchReviewWorkflowFailureV1.invalidContext}
        default:throw PunchReviewWorkflowFailureV1.invalidContext
        }
        if let installationSnapshot {
            guard installationSnapshot.envelope.workspaceID==envelope.workspaceID,
                  installationSnapshot.envelope.subjectID==envelope.subjectID else {
                throw PunchReviewWorkflowFailureV1.staleOrWrongAsset
            }
        }
        try validateReviewFacts()
    }

    private func validateReviewFacts() throws {
        let targetAsset=envelope.subjectID.uuidString.lowercased()
        var findingByID:[UUID:FindingV1]=[:]
        for finding in findings {
            guard let id=UUID(uuidString:finding.findingID),finding.subject.subjectID.lowercased()==targetAsset,
                  findingByID[id]==nil else{throw PunchReviewWorkflowFailureV1.staleOrWrongAsset}
            findingByID[id]=finding
        }
        guard Set(sourceEnvelopes.map(\.envelopeSHA256)).count==sourceEnvelopes.count else {
            throw PunchReviewWorkflowFailureV1.staleOrWrongAsset
        }
        let sourceByDigest=Dictionary(uniqueKeysWithValues:sourceEnvelopes.map{($0.envelopeSHA256,$0)})
        let actionHeads=try currentCorrectiveActions(correctiveActionEvents)
        let recheckHeads=try currentRechecks(verifiedRechecks)
        var linkedFindingIDs=Set<UUID>()
        var linkedActionIDs=Set<UUID>()
        var linkedRecheckFindingIDs=Set<UUID>()
        for link in scopeDecisions.flatMap(\.findingLinks) {
            guard linkedFindingIDs.insert(link.findingID).inserted,
                  let finding=findingByID[link.findingID],finding.revision==link.findingRevision,
                  (try WorkspaceMutationCanonicalV1.sha256(finding))==link.findingSHA256,
                  let source=sourceByDigest[link.sourceContext.activitySHA256],
                  source.workspaceID==envelope.workspaceID,source.activityID==envelope.activityID,
                  source.kind == .punchReview,source.revision==link.sourceContext.activityRevision,
                  link.sourceContext.workspaceID==envelope.workspaceID,
                  link.sourceContext.activityID==envelope.activityID else {
                throw PunchReviewWorkflowFailureV1.staleOrWrongAsset
            }
            let corrective=link.supportingRecords.first{$0.kind == .correctiveAction}
            if let corrective {
                guard let event=actionHeads[corrective.recordID],event.revision==corrective.revision,
                      event.eventSHA256==corrective.recordSHA256 else {
                    throw PunchReviewWorkflowFailureV1.staleOrWrongAsset
                }
                linkedActionIDs.insert(corrective.recordID)
            }
            let recheck=link.supportingRecords.first{$0.kind == .operationalRecheck}
            if let recheck {
                guard let head=recheckHeads[link.findingID],UUID(uuidString:head.recheckID)==recheck.recordID,
                      head.resultingRecheckRevision>0,
                      UInt64(head.resultingRecheckRevision)==recheck.revision,
                      (try WorkspaceMutationCanonicalV1.sha256(head))==recheck.recordSHA256,
                      head.findingRevision==link.findingRevision,
                      let corrective,UUID(uuidString:head.correctiveWorkID)==corrective.recordID,
                      head.correctiveWorkRevision>0,
                      UInt64(head.correctiveWorkRevision)==corrective.revision else {
                    throw PunchReviewWorkflowFailureV1.conflictingRecheck
                }
                linkedRecheckFindingIDs.insert(link.findingID)
            }
        }
        guard Set(findingByID.keys)==linkedFindingIDs,
              Set(actionHeads.keys)==linkedActionIDs,
              Set(recheckHeads.keys)==linkedRecheckFindingIDs else {
            throw PunchReviewWorkflowFailureV1.staleOrWrongAsset
        }
        for (findingID,head) in recheckHeads where linkedFindingIDs.contains(findingID) {
            let history=verifiedRechecks.filter{$0.findingID==head.findingID}
            guard Set(history.map(\.correctiveWorkID)).count==1 else {
                throw PunchReviewWorkflowFailureV1.conflictingRecheck
            }
        }
    }

    private func currentCorrectiveActions(_ values:[CorrectiveActionEventV1])throws
        ->[UUID:CorrectiveActionEventV1]{
        var heads:[UUID:CorrectiveActionEventV1]=[:]
        for (actionID,history) in Dictionary(grouping:values,by:{$0.actionID}) {
            let ordered=history.sorted{$0.revision<$1.revision}
            guard Set(ordered.map(\.eventID)).count==ordered.count,
                  Set(ordered.map(\.revision)).count==ordered.count else {
                throw PunchReviewWorkflowFailureV1.staleOrWrongAsset
            }
            for (index,event) in ordered.enumerated() {
                guard event.workspaceID==envelope.workspaceID,event.revision==UInt64(index+1),
                      (index==0 ? event.predecessorEventID==nil
                        : event.predecessorEventID==ordered[index-1].eventID) else {
                    throw PunchReviewWorkflowFailureV1.staleOrWrongAsset
                }
            }
            heads[actionID]=ordered.last
        }
        return heads
    }

    private func currentRechecks(_ values:[VerifiedRecheckV1])throws->[UUID:VerifiedRecheckV1]{
        var heads:[UUID:VerifiedRecheckV1]=[:]
        for (findingID,history) in Dictionary(grouping:values,by:{$0.findingID}) {
            guard let id=UUID(uuidString:findingID),Set(history.map(\.correctiveWorkID)).count==1 else {
                throw PunchReviewWorkflowFailureV1.conflictingRecheck
            }
            let ordered=history.sorted{$0.resultingRecheckRevision<$1.resultingRecheckRevision}
            do{try VerifiedRecheckLineageV1.validate(ordered)}
            catch{throw PunchReviewWorkflowFailureV1.conflictingRecheck}
            heads[id]=ordered.last
        }
        return heads
    }
}

enum PunchReviewWorkflowCommandV1: Equatable, Sendable {
    case start(ActivityContractMutationV2)
    case resume(ActivityContractMutationV2)
    case pause(ActivityContractMutationV2)
    case interrupt(ActivityContractMutationV2)
    case recordBasisVariation(ActivityContractMutationV2)
    case closeout(ActivityContractMutationV2)
    var mutation:ActivityContractMutationV2{switch self{
        case let .start(v),let .resume(v),let .pause(v),let .interrupt(v),
             let .recordBasisVariation(v),let .closeout(v):return v}}
}

@MainActor
final class PunchReviewWorkflowCoordinatorV1 {
    private let contractCoordinator:ActivityContractCoordinatorV2
    private let punchContractSHA256:String
    private let noPlanFallback:NoPlanFallbackV1

    init(contractCoordinator:ActivityContractCoordinatorV2,
         punchContractSHA256:String,noPlanFallback:NoPlanFallbackV1)throws{
        guard KernelCanonicalHashV1.validSHA256(punchContractSHA256)else{
            throw PunchReviewWorkflowFailureV1.invalidContext}
        try noPlanFallback.validate();self.contractCoordinator=contractCoordinator
        self.punchContractSHA256=punchContractSHA256;self.noPlanFallback=noPlanFallback
    }

    func projection(for context:PunchReviewWorkflowContextV1)throws->PunchReviewWorkflowProjectionV1{
        try context.validate();let blockers=readinessBlockers(context)
        let decisions=Dictionary(uniqueKeysWithValues:context.scopeDecisions.map{($0.scopeItemID,$0)})
        let recheckHeads=try currentRechecks(context.verifiedRechecks)
        let scope=context.release.scope.sorted().map{definition in
            let decision=decisions[definition.scopeItemID]
            let counts=findingCounts(decision?.findingLinks ?? [],recheckHeads:recheckHeads)
            return PunchReviewScopeProjectionV1(definition:definition,decision:decision,
                unresolvedFindingCount:counts.unresolved,resolvedFindingCount:counts.resolved)}
        let nextID=scope.first{$0.decision==nil || $0.decision?.disposition == .notReviewed}?.definition.scopeItemID
        let action=try closeoutAction(context,scope:scope)
        let unresolvedScope=scope.filter{item in
            guard let decision=item.decision else{return true}
            if [.notReviewed,.deferred,.unable].contains(decision.disposition){return true}
            return item.unresolvedFindingCount>0}.count
        let unresolvedFindings=scope.reduce(0){$0+$1.unresolvedFindingCount}
        let resolvedFindings=scope.reduce(0){$0+$1.resolvedFindingCount}
        let reportReadiness:PunchReviewReportReadinessV1=context.envelope.state == .finalized
            && context.envelope.punchReviewCloseout != nil ? .readyForExistingRenderer
            : ([.fieldComplete,.readyForReview].contains(context.envelope.state) ? .reviewRequired:.reviewIncomplete)
        let findingDigests=try context.findings.map{try WorkspaceMutationCanonicalV1.sha256($0)}.sorted()
        let report=try PunchReviewReportProjectionV1(activityID:context.envelope.activityID,
            envelopeSHA256:context.envelope.envelopeSHA256,state:context.envelope.state,
            basisSHA256:context.basis.basisSHA256,scopeItemIDs:scope.map(\.definition.scopeItemID),
            findingSHA256s:findingDigests,correctiveActionSHA256s:context.correctiveActionEvents.map(\.eventSHA256).sorted(),
            verifiedRecheckSHA256s:try context.verifiedRechecks.map{try WorkspaceMutationCanonicalV1.sha256($0)}.sorted(),
            unresolvedScopeCount:unresolvedScope,unresolvedFindingCount:unresolvedFindings,
            resolvedFindingCount:resolvedFindings,closeoutSHA256:context.envelope.punchReviewCloseout?.closeoutSHA256,
            installationSnapshotSHA256:context.installationSnapshot?.completedSnapshot.snapshotSHA256)
        return .init(envelope:context.envelope,blockers:blockers,scope:scope,nextScopeItemID:nextID,
            planDisposition:context.planCapability.disposition,
            installationSnapshotAvailable:context.installationSnapshot != nil,
            canStart:context.envelope.state == .ready && blockers.isEmpty,canCloseout:action != nil,
            nextCloseoutAction:action,reportReadiness:reportReadiness,
            reportReady:reportReadiness == .readyForExistingRenderer,report:report)
    }

    func execute(_ command:PunchReviewWorkflowCommandV1,context:PunchReviewWorkflowContextV1)async throws
        ->ActivityContractAcceptanceResultV2{
        try context.validate()
        if let fallback=context.planCapability.noPlanFallback,fallback != noPlanFallback {
            throw PunchReviewWorkflowFailureV1.invalidContext
        }
        let mutation=command.mutation;try validateCommon(mutation,context:context)
        try validate(command,context:context)
        let request=try ActivityContractAcceptanceRequestV2(family:.punch,mutation:mutation,
            sharedReceipt:contractCoordinator.sharedConformanceReceipt,
            independentFamilyContractSHA256:punchContractSHA256,noPlanFallback:noPlanFallback)
        return try await contractCoordinator.accept(request)
    }

    func recover(_ command:PunchReviewWorkflowCommandV1,context:PunchReviewWorkflowContextV1)async throws
        ->ActivityContractAcceptanceResultV2{
        do{return try await execute(command,context:context)}catch{return try await execute(command,context:context)}
    }

    private func validateCommon(_ mutation:ActivityContractMutationV2,
                                context:PunchReviewWorkflowContextV1)throws{
        try mutation.validate();guard mutation.workspaceID==context.envelope.workspaceID,
            mutation.predecessorEnvelope==context.envelope,
            mutation.successorEnvelope.activityID==context.envelope.activityID,
            mutation.successorEnvelope.kind == .punchReview,
            mutation.installationBasisSnapshot==nil,mutation.installationTaskResults.isEmpty,
            mutation.installationAsBuiltSnapshot==nil else{throw PunchReviewWorkflowFailureV1.invalidCommand}
    }

    private func validate(_ command:PunchReviewWorkflowCommandV1,
                          context:PunchReviewWorkflowContextV1)throws{
        let mutation=command.mutation,from=context.envelope.state,to=mutation.successorEnvelope.state
        switch command{
        case .start:
            guard from == .ready,to == .inProgress,readinessBlockers(context).isEmpty,
                  hasNoReviewPayload(mutation,context:context)
            else{throw PunchReviewWorkflowFailureV1.blockedReadiness}
        case .resume:
            guard [.paused,.changesRequested].contains(from),to == .inProgress,
                  hasNoReviewPayload(mutation,context:context)
            else{throw PunchReviewWorkflowFailureV1.invalidCommand}
        case .pause:
            guard from == .inProgress,to == .paused,hasNoReviewPayload(mutation,context:context)
            else{throw PunchReviewWorkflowFailureV1.invalidCommand}
        case .interrupt:
            guard [.inProgress,.paused].contains(from),[.deferred,.unableToComplete,.cancelled].contains(to),
                  mutation.transition?.reason != nil,hasNoReviewPayload(mutation,context:context)
            else{throw PunchReviewWorkflowFailureV1.invalidCommand}
        case .recordBasisVariation:
            try validateBasisVariation(mutation,context:context)
        case .closeout:
            guard (from == .inProgress && to == .fieldComplete)
                || (from == .fieldComplete && to == .readyForReview)
                || (from == .readyForReview && to == .finalized),
                mutation.punchReviewBasisSnapshot==nil,
                mutation.successorEnvelope.variations==context.envelope.variations
            else{throw PunchReviewWorkflowFailureV1.invalidCommand}
            let expected=Set(context.release.scope.map(\.scopeItemID))
            guard Set(context.scopeDecisions.map(\.scopeItemID))==expected else{
                throw PunchReviewWorkflowFailureV1.unresolvedCloseoutCount}
            let decisions=Dictionary(uniqueKeysWithValues:context.scopeDecisions.map{($0.scopeItemID,$0)})
            let recheckHeads=try currentRechecks(context.verifiedRechecks)
            let scope=context.release.scope.sorted().map{definition in
                let decision=decisions[definition.scopeItemID]
                let counts=findingCounts(decision?.findingLinks ?? [],recheckHeads:recheckHeads)
                return PunchReviewScopeProjectionV1(definition:definition,decision:decision,
                    unresolvedFindingCount:counts.unresolved,resolvedFindingCount:counts.resolved)}
            guard closeoutEligible(context,scope:scope) else {
                throw PunchReviewWorkflowFailureV1.unresolvedCloseoutCount
            }
            if to == .finalized{
                guard let closeout=mutation.successorEnvelope.punchReviewCloseout,
                      closeout.basisSHA256==context.basis.basisSHA256,
                      closeout.scope==context.scopeDecisions.sorted(by:{$0.scopeItemID<$1.scopeItemID}),
                      context.closeoutIntent.map({$0==closeout}) ?? completedCloseoutIsResolved(
                        closeout, scope:scope
                      )
                else{throw PunchReviewWorkflowFailureV1.unresolvedCloseoutCount}
            }else{guard mutation.successorEnvelope.punchReviewCloseout==nil
                else{throw PunchReviewWorkflowFailureV1.invalidCommand}}
        }
    }

    private func validateBasisVariation(_ mutation:ActivityContractMutationV2,
                                        context:PunchReviewWorkflowContextV1)throws{
        guard [.inProgress,.paused,.changesRequested].contains(context.envelope.state),
              mutation.successorEnvelope.state==context.envelope.state,mutation.transition==nil,
              mutation.successorEnvelope.variations.count==context.envelope.variations.count+1,
              mutation.successorEnvelope.punchReviewCloseout==context.envelope.punchReviewCloseout,
              let basis=mutation.punchReviewBasisSnapshot,
              case let .punchReview(predecessor)?=context.envelope.currentBasisReference,
              case let .punchReview(successor)?=mutation.successorEnvelope.currentBasisReference,
              successor==(try PunchReviewBasisReferenceV1(basis)),basis.mutationID==mutation.mutationID,
              basis.predecessorBasisID==predecessor.basisID,
              basis.predecessorBasisSHA256==predecessor.basisSHA256,
              let variation=mutation.successorEnvelope.variations.last,
              variation.mutationID==mutation.mutationID,
              variation.predecessorBasisSHA256==predecessor.basisSHA256,
              variation.successorBasisSHA256==basis.basisSHA256,
              [.basisCorrected,.optionalPlanReferenceChanged,.recordedScopeChanged].contains(variation.kind),
              basis.workspaceID==context.envelope.workspaceID,basis.activityID==context.envelope.activityID,
              basis.subjectID==context.envelope.subjectID,
              basis.workflowReleaseReference.targetWorkspaceID==context.release.workspaceID,
              basis.workflowReleaseReference.targetReleaseID==context.release.releaseID,
              basis.workflowReleaseReference.targetReleaseRevision==context.release.revision,
              basis.workflowReleaseReference.targetReleaseSHA256==context.release.releaseSHA256
        else{throw PunchReviewWorkflowFailureV1.invalidCommand}
        try basis.validateSuccessor(of:context.basis)
    }

    private func readinessBlockers(_ context:PunchReviewWorkflowContextV1)->[PunchReviewReadinessBlockerV1]{
        let required=Set(context.release.readinessPolicy.requiredFacets),present=Set(context.envelope.readiness.map(\.kind))
        var values=context.envelope.readiness.compactMap{facet->PunchReviewReadinessBlockerV1? in
            guard [.blocked,.deferred].contains(facet.disposition)else{return nil}
            return .init(facetID:facet.facetID,kind:facet.kind,disposition:facet.disposition,
                         reason:facet.reason ?? "Readiness must be resolved before starting.")}
        for kind in required.subtracting(present){values.append(.init(facetID:"missing-\(kind.rawValue.lowercased())",
            kind:kind,disposition:.blocked,reason:"Required readiness has not been recorded."))}
        return values.sorted()
    }

    private func hasNoReviewPayload(_ mutation:ActivityContractMutationV2,
                                    context:PunchReviewWorkflowContextV1)->Bool{
        mutation.punchReviewBasisSnapshot==nil
            && mutation.successorEnvelope.punchReviewCloseout==context.envelope.punchReviewCloseout
            && mutation.successorEnvelope.variations==context.envelope.variations
    }

    private func closeoutAction(_ context:PunchReviewWorkflowContextV1,
                                scope:[PunchReviewScopeProjectionV1])throws->PunchReviewCloseoutActionV1?{
        let complete=closeoutEligible(context,scope:scope)
        switch context.envelope.state{
        case .inProgress:return complete ? .recordFieldComplete:nil
        case .fieldComplete:return complete ? .submitForReview:nil
        case .readyForReview:return complete ? .finalizeRecordedCloseout:nil
        default:return nil}
    }

    private func closeoutEligible(_ context:PunchReviewWorkflowContextV1,
                                  scope:[PunchReviewScopeProjectionV1])->Bool{
        guard scope.allSatisfy(\.hasRecordedDecision) else{return false}
        if let intent=context.closeoutIntent {
            guard intent.basisSHA256==context.basis.basisSHA256,
                  intent.scope==context.scopeDecisions.sorted(by:{$0.scopeItemID<$1.scopeItemID}) else{return false}
            switch intent.completion {
            case .completedNoPunchItemsRecordedInScope,.completedWithPunchItemsRecorded:
                return completedCloseoutIsResolved(intent,scope:scope)
            case .partiallyReviewed:
                return intent.scope.contains{[.notReviewed,.deferred].contains($0.disposition)}
                    && !intent.scope.contains{$0.disposition == .unable}
            case .unableAttemptRecorded:
                return intent.scope.contains{$0.disposition == .unable}
            case .cancelled:
                return false
            }
        }
        return scope.allSatisfy{item in
            guard let decision=item.decision else{return false}
            return [.reviewedNoItemRecorded,.reviewedWithItems,.notApplicable].contains(decision.disposition)
                && item.unresolvedFindingCount==0
        }
    }

    private func completedCloseoutIsResolved(_ closeout:PunchReviewCloseoutV1,
                                              scope:[PunchReviewScopeProjectionV1])->Bool{
        guard closeout.completion == .completedNoPunchItemsRecordedInScope
                || closeout.completion == .completedWithPunchItemsRecorded else{return false}
        return scope.allSatisfy{item in
            guard let decision=item.decision else{return false}
            return [.reviewedNoItemRecorded,.reviewedWithItems,.notApplicable].contains(decision.disposition)
                && item.unresolvedFindingCount==0
        }
    }

    private func currentRechecks(_ values:[VerifiedRecheckV1])throws->[UUID:VerifiedRecheckV1]{
        var result:[UUID:VerifiedRecheckV1]=[:]
        for (findingID,history) in Dictionary(grouping:values,by:{$0.findingID}){
            guard let id=UUID(uuidString:findingID),Set(history.map(\.correctiveWorkID)).count==1 else{
                throw PunchReviewWorkflowFailureV1.conflictingRecheck}
            let ordered=history.sorted{$0.resultingRecheckRevision<$1.resultingRecheckRevision}
            do{try VerifiedRecheckLineageV1.validate(ordered)}catch{throw PunchReviewWorkflowFailureV1.conflictingRecheck}
            result[id]=ordered.last
        }
        return result
    }

    private func findingCounts(_ links:[PunchFindingLinkV1],recheckHeads:[UUID:VerifiedRecheckV1])
        ->(unresolved:Int,resolved:Int){
        var unresolved=0,resolved=0
        for link in links{
            let linkedRecheck=link.supportingRecords.first{$0.kind == .operationalRecheck}
            if let head=recheckHeads[link.findingID],head.outcome == .passed,
               let linkedRecheck,UUID(uuidString:head.recheckID)==linkedRecheck.recordID,
               head.resultingRecheckRevision>0,
               UInt64(head.resultingRecheckRevision)==linkedRecheck.revision {
                resolved += 1
            }else{unresolved += 1}}
        return(unresolved,resolved)
    }
}

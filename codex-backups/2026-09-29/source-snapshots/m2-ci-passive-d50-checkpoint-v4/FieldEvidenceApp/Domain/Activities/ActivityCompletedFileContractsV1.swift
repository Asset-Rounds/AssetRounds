import Foundation

// Intrinsic, immutable values only. None of these constructors authenticates a
// store, executes an absence query, admits a report release, or enables a write.
// The active-store capture and combined writer must authenticate and compare the
// complete source frontier before accepting this file.
enum ActivityCompletedFileFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case incompatibleVersion
    case missingBinding
    case staleFrontier
    case invalidHistory
    case digestMismatch
    case limitExceeded
}

private enum ActivityCompletedValueV1 {
    static let maximumMembers = ActivityContractValidationV2.maximumReferences
    static let maximumFileBytes = SnapshotProjectionLimitsV1.maximumProjectionBytes

    static func require(_ condition: Bool) throws {
        guard condition else { throw ActivityCompletedFileFailureV1.missingBinding }
    }

    static func bounded(_ count: Int) throws {
        guard count <= maximumMembers else { throw ActivityCompletedFileFailureV1.limitExceeded }
    }

    static func canonical<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func digest<T: Encodable>(_ value: T) throws -> String {
        KernelCanonicalHashV1.sha256(try canonical(value))
    }

    static func finite(_ dates: [Date]) throws {
        try require(dates.allSatisfy { $0.timeIntervalSinceReferenceDate.isFinite })
    }
}

/// The unfinished, authenticated source is retained verbatim. Final state is
/// described by the actual transition and resulting activity revision; a final
/// envelope would introduce a file/reference/envelope hash cycle.
struct ActivityCompletionCaptureV1: Codable, Equatable, Sendable {
    static let currentVersion = 1
    let version: Int
    let source: MutationPortableExpectedRevisionV1
    let predecessor: ActivitySessionEnvelopeV2
    let transitionHistory: [ActivityStateTransitionV2]
    let completionTransition: ActivityStateTransitionV2
    let resultingActivityRevision: UInt64
    let capturedAt: Date
    let generatedAt: Date

    var finalizedAt: Date { completionTransition.occurredAt }
    var mutationID: MutationIDV1 { completionTransition.mutationID }

    func validateIntrinsic() throws {
        try predecessor.validateForRead()
        try source.validate()
        try completionTransition.validate()
        try ActivityCompletedValueV1.bounded(transitionHistory.count)
        try ActivityCompletedValueV1.finite([capturedAt, generatedAt, finalizedAt])
        let (next, overflow) = predecessor.revision.addingReportingOverflow(1)
        let zero = ActivityContractValidationV2.zeroUUID
        guard version == Self.currentVersion else { throw ActivityCompletedFileFailureV1.incompatibleVersion }
        try ActivityCompletedValueV1.require(
            source.workspaceID == predecessor.workspaceID && source.generationID != zero
                && source.workspaceRevision > 0
                && !overflow && resultingActivityRevision == next
                && Int(exactly: resultingActivityRevision) != nil
                && predecessor.schemaVersion == ActivitySessionEnvelopeV2.schemaVersion
                && predecessor.state == .readyForReview
                && predecessor.finalizedAt == nil && predecessor.completedSnapshotReference == nil
                && predecessor.completedFileReference == nil
                && (predecessor.kind == .installation || predecessor.kind == .punchReview)
                && completionTransition.workspaceID == predecessor.workspaceID
                && completionTransition.activityID == predecessor.activityID
                && completionTransition.kind == predecessor.kind
                && completionTransition.fromState == predecessor.state
                && completionTransition.toState == .finalized
                && completionTransition.revision == resultingActivityRevision
                && completionTransition.mutationID != predecessor.mutationID
                && capturedAt <= generatedAt && finalizedAt <= generatedAt
        )
        if let startedAt = predecessor.startedAt {
            try ActivityCompletedValueV1.finite([startedAt])
            try ActivityCompletedValueV1.require(finalizedAt >= startedAt)
        } else { throw ActivityCompletedFileFailureV1.missingBinding }

        // The process-local writer lease is checked by live capture/admission,
        // never persisted in portable completed bytes (MutationEnvelopeV1).
        let activityIdentity = try WorkspaceEntityIdentityV1(
            kind: .activitySessionEnvelope, id: predecessor.activityID
        )
        let boundActivity = source.entityRevisions.filter { $0.identity == activityIdentity }
        try ActivityCompletedValueV1.require(
            boundActivity.count == 1 && boundActivity.first?.revision == predecessor.revision
        )

        try ActivityCompletedValueV1.require(!transitionHistory.isEmpty)
        var prior: ActivityStateTransitionV2?
        var transitionIDs = Set<UUID>()
        for transition in transitionHistory {
            try transition.validate()
            try ActivityCompletedValueV1.finite([transition.occurredAt])
            try ActivityCompletedValueV1.require(
                transition.workspaceID == predecessor.workspaceID
                    && transition.activityID == predecessor.activityID
                    && transition.kind == predecessor.kind
                    && transition.revision <= predecessor.revision
                    && transitionIDs.insert(transition.transitionID).inserted
                    && transition.occurredAt <= finalizedAt
            )
            if let prior {
                try ActivityCompletedValueV1.require(
                    transition.revision > prior.revision
                        && transition.fromState == prior.toState
                        && transition.occurredAt >= prior.occurredAt
                )
            } else {
                // Seed is draft revision 1. Same-state activity mutations have
                // no transition, so even the first transition may follow gaps.
                try ActivityCompletedValueV1.require(transition.revision > 1 && transition.fromState == .draft)
            }
            prior = transition
        }
        guard let prior else { throw ActivityCompletedFileFailureV1.invalidHistory }
        try ActivityCompletedValueV1.require(
            completionTransition.revision > prior.revision
                && prior.toState == predecessor.state
                && completionTransition.occurredAt >= prior.occurredAt
                && !transitionIDs.contains(completionTransition.transitionID)
        )
    }
}

/// Full selected installation truth, including original and rebound releases.
struct ActivityCompletedInstallationV1: Codable, Equatable, Sendable {
    let sourceRelease: InstallationWorkflowDefinitionReleaseV1
    let release: InstallationWorkflowDefinitionReleaseV1
    let basisHistory: [InstallationBasisSnapshotV1]
    let taskHistory: [InstallationTaskResultV1]
    let asBuilt: InstallationAsBuiltSnapshotV1
    let placementSources: ActivityCompletionPlacementSourcesV1
    let closeout: InstallationCloseoutV1
    let planCapability: ActivityCompletedInstallationPlanV1
    let scanCapability: ActivityCompletedInstallationScanV1
    let findings: [FindingV1]
    let sourceEnvelopes: [ActivitySessionEnvelopeV2]
    let correctiveActionEvents: [CorrectiveActionEventV1]
    let verifiedRechecks: [VerifiedRecheckV1]

    func validate(capture: ActivityCompletionCaptureV1, package: InspectionPackageV2) throws {
        try ActivityCompletedValueV1.bounded(basisHistory.count)
        try ActivityCompletedValueV1.bounded(taskHistory.count)
        guard let basis = basisHistory.last else { throw ActivityCompletedFileFailureV1.missingBinding }
        for (index, value) in basisHistory.enumerated() {
            try value.validate()
            if index == 0 { try ActivityCompletedValueV1.require(value.revision == 1) }
            else { try value.validateSuccessor(of: basisHistory[index - 1]) }
        }
        try basis.workflowReleaseReference.validateSource(installation: sourceRelease, package: package)
        try basis.workflowReleaseReference.validateTarget(installation: release, package: package)
        _ = try InstallationWorkflowContextV1(
            envelope: capture.predecessor, release: release, basis: basis,
            taskHistory: taskHistory, asBuiltSnapshot: asBuilt,
            planCapability: planCapability.resolved(), scanCapability: scanCapability.resolved()
        )
        try closeout.validate()
        try placementSources.validate(workspaceID: capture.source.workspaceID,
            assetID: capture.predecessor.subjectID, references: asBuilt.placementReferences)
        let heads = try InstallationTaskResultLineageV1.validateAndCurrentHeads(taskHistory)
        try ActivityCompletedValueV1.require(
            taskHistory == taskHistory.sorted()
                && Set(heads.keys) == Set(release.tasks.map(\.taskID))
                && closeout.asBuiltSnapshotSHA256 == asBuilt.snapshotSHA256
                && closeout.completion == asBuilt.completion
        )
        try ActivityCompletedFindingSupportV1.validate(
            links: closeout.openFindings, findings: findings, sourceEnvelopes: sourceEnvelopes,
            actions: correctiveActionEvents, rechecks: verifiedRechecks, capture: capture
        )
    }
}

/// Exact spatial values selected by the as-built references and their required
/// predecessors. Floor-plan placements are separate from C19 measurement plans.
/// Referenced content/locator releases and accepted-transform provenance still
/// require their owning capture/admission boundary; these values do not invent it.
struct ActivityCompletionPlacementSourcesV1: Codable, Equatable, Sendable {
    let planDocuments: [PlanDocumentV1]
    let planRevisions: [PlanRevisionV1]
    let planPlacements: [PlanPlacementV1]
    let poseEvents: [AssetPoseEventV1]
    let placementHistory: [AssetPlacementEventV1]

    func validate(workspaceID: WorkspaceID, assetID: UUID, references: [InstallationPlacementReferenceV2]) throws {
        for count in [references.count, planDocuments.count, planRevisions.count,
                      planPlacements.count, poseEvents.count, placementHistory.count] {
            try ActivityCompletedValueV1.bounded(count)
        }
        try ActivityCompletedValueV1.require(Set(references).count == references.count)
        var documentsBySHA: [String: PlanDocumentV1] = [:]
        var documentReferences = Set<PlanDocumentReferenceV1>()
        var documentIdentities = Set<String>()
        for document in planDocuments {
            try document.validateIntrinsic()
            let reference = try document.reference
            let identity = "\(document.planDocumentID.uuidString)|\(document.revision)"
            try ActivityCompletedValueV1.require(document.workspaceID == workspaceID
                && documentReferences.insert(reference).inserted
                && documentIdentities.insert(identity).inserted
                && documentsBySHA.updateValue(document, forKey: document.documentSHA256) == nil)
        }
        var revisionsByID: [UUID: PlanRevisionV1] = [:]
        for revision in planRevisions {
            try revision.validateIntrinsic()
            try ActivityCompletedValueV1.require(revision.workspaceID == workspaceID
                && revisionsByID.updateValue(revision, forKey: revision.planRevisionID) == nil)
        }
        var plansBySHA: [String: PlanPlacementV1] = [:]
        var placementIdentities = Set<String>()
        for placement in planPlacements {
            try placement.validateIntrinsic()
            let identity = "\(placement.placementID.uuidString)|\(placement.revision)"
            try ActivityCompletedValueV1.require(placement.workspaceID == workspaceID
                && placement.subjectID == assetID && placement.subjectKind == .asset
                && placementIdentities.insert(identity).inserted
                && plansBySHA.updateValue(placement, forKey: placement.placementSHA256) == nil)
        }
        var posesByID: [UUID: AssetPoseEventV1] = [:]
        for pose in poseEvents {
            try pose.validateIntrinsic()
            try ActivityCompletedValueV1.require(pose.workspaceID == workspaceID && pose.assetID == assetID
                && posesByID.updateValue(pose, forKey: pose.eventID) == nil)
        }
        var physicalByID: [UUID: AssetPlacementEventV1] = [:]
        for placement in placementHistory {
            try placement.validate()
            try ActivityCompletedValueV1.require(placement.workspaceID == workspaceID && placement.assetID == assetID
                && physicalByID.updateValue(placement, forKey: placement.id) == nil)
        }

        var pendingPlans: [PlanPlacementV1] = []
        var pendingPoses: [AssetPoseEventV1] = []
        for reference in references {
            try reference.validate(workspaceID: workspaceID)
            switch reference {
            case let .plan(value):
                guard let placement = plansBySHA[value.placementSHA256] else { throw ActivityCompletedFileFailureV1.missingBinding }
                try ActivityCompletedValueV1.require(placement.placementID == value.placementID && placement.revision == value.revision)
                pendingPlans.append(placement)
            case let .pose(value):
                guard let pose = posesByID[value.eventID] else { throw ActivityCompletedFileFailureV1.missingBinding }
                try ActivityCompletedValueV1.require(pose.reference == value)
                pendingPoses.append(pose)
            }
        }
        var usedPlans = Set<String>()
        var pendingRevisions: [PlanRevisionReferenceV1] = []
        while let placement = pendingPlans.popLast() {
            if !usedPlans.insert(placement.placementSHA256).inserted { continue }
            guard let revision = revisionsByID[placement.planRevision.planRevisionID] else { throw ActivityCompletedFileFailureV1.missingBinding }
            try placement.validate(planRevision: revision)
            pendingRevisions.append(placement.planRevision)
            if let priorSHA = placement.supersedesPlacementSHA256 {
                guard let prior = plansBySHA[priorSHA] else { throw ActivityCompletedFileFailureV1.invalidHistory }
                try placement.validateSuccessor(of: prior)
                pendingPlans.append(prior)
            }
        }
        var usedPoses = Set<UUID>()
        var pendingPhysical: [UUID] = []
        while let pose = pendingPoses.popLast() {
            if !usedPoses.insert(pose.eventID).inserted { continue }
            guard let physical = physicalByID[pose.placementEventID] else { throw ActivityCompletedFileFailureV1.missingBinding }
            try ActivityCompletedValueV1.require(pose.placementEpisodeID == physical.physicalEpisodeID
                && pose.locationPathSnapshot == physical.pathSnapshot)
            pendingPhysical.append(physical.id)
            if case let .planRelative(binding) = pose.pose.referenceFrame {
                guard let revision = revisionsByID[binding.planRevision.planRevisionID] else { throw ActivityCompletedFileFailureV1.missingBinding }
                let reference = try revision.reference
                try ActivityCompletedValueV1.require(reference == binding.planRevision
                    && revision.pages.contains(where: { $0.pageID == binding.pageID })
                    && revision.spatialFrames.contains(where: { $0.frameID == binding.spatialFrameID && $0.pageID == binding.pageID }))
                pendingRevisions.append(binding.planRevision)
            }
            if let reference = pose.predecessor {
                guard let prior = posesByID[reference.eventID] else { throw ActivityCompletedFileFailureV1.invalidHistory }
                try pose.validateSuccessor(of: prior)
                pendingPoses.append(prior)
            }
        }
        var usedPhysical = Set<UUID>()
        while let id = pendingPhysical.popLast() {
            if !usedPhysical.insert(id).inserted { continue }
            guard let placement = physicalByID[id] else { throw ActivityCompletedFileFailureV1.invalidHistory }
            var lineage = Set<UUID>()
            var current: AssetPlacementEventV1? = placement
            while let value = current {
                try ActivityCompletedValueV1.require(lineage.insert(value.id).inserted)
                usedPhysical.insert(value.id)
                if let priorID = value.predecessorEventID {
                    guard let prior = physicalByID[priorID] else { throw ActivityCompletedFileFailureV1.invalidHistory }
                    current = prior
                } else { current = nil }
            }
        }
        var usedRevisions = Set<UUID>()
        var pendingDocuments: [PlanDocumentReferenceV1] = []
        while let reference = pendingRevisions.popLast() {
            guard let revision = revisionsByID[reference.planRevisionID] else { throw ActivityCompletedFileFailureV1.missingBinding }
            let actualReference = try revision.reference
            try ActivityCompletedValueV1.require(actualReference == reference)
            if !usedRevisions.insert(revision.planRevisionID).inserted { continue }
            pendingDocuments.append(revision.planDocument)
            if let priorID = revision.supersedesPlanRevisionID {
                guard let prior = revisionsByID[priorID] else { throw ActivityCompletedFileFailureV1.invalidHistory }
                try revision.validateSuccessor(of: prior)
                pendingRevisions.append(try prior.reference)
            }
        }
        var usedDocuments = Set<String>()
        while let reference = pendingDocuments.popLast() {
            guard let document = documentsBySHA[reference.documentSHA256] else { throw ActivityCompletedFileFailureV1.missingBinding }
            let actualReference = try document.reference
            try ActivityCompletedValueV1.require(actualReference == reference)
            if !usedDocuments.insert(document.documentSHA256).inserted { continue }
            if let priorSHA = document.supersedesDocumentSHA256 {
                guard let prior = documentsBySHA[priorSHA] else { throw ActivityCompletedFileFailureV1.invalidHistory }
                try document.validateSuccessor(of: prior)
                pendingDocuments.append(try prior.reference)
            }
        }
        try ActivityCompletedValueV1.require(usedPlans == Set(plansBySHA.keys)
            && usedPoses == Set(posesByID.keys) && usedPhysical == Set(physicalByID.keys)
            && usedRevisions == Set(revisionsByID.keys) && usedDocuments == Set(documentsBySHA.keys))
    }
}

/// Full Punch truth. An optional installation association preserves its exact
/// typed snapshot and owner file reference; it is never inferred from an asset.
struct ActivityCompletedPunchV1: Codable, Equatable, Sendable {
    let sourceRelease: PunchReviewWorkflowDefinitionReleaseV1
    let release: PunchReviewWorkflowDefinitionReleaseV1
    let basisHistory: [PunchReviewBasisSnapshotV1]
    let scopeDecisions: [PunchItemProjectionV1]
    let closeout: PunchReviewCloseoutV1
    let planCapability: ActivityCompletedPunchPlanV1
    let findings: [FindingV1]
    let sourceEnvelopes: [ActivitySessionEnvelopeV2]
    let correctiveActionEvents: [CorrectiveActionEventV1]
    let verifiedRechecks: [VerifiedRecheckV1]
    let installation: ActivityCompletedInstallationAssociationV1?

    func validate(capture: ActivityCompletionCaptureV1, package: InspectionPackageV2) throws {
        try ActivityCompletedValueV1.bounded(basisHistory.count)
        guard let basis = basisHistory.last else { throw ActivityCompletedFileFailureV1.missingBinding }
        for (index, value) in basisHistory.enumerated() {
            try value.validate()
            if index == 0 { try ActivityCompletedValueV1.require(value.revision == 1) }
            else { try value.validateSuccessor(of: basisHistory[index - 1]) }
        }
        try basis.workflowReleaseReference.validateSource(punchReview: sourceRelease, package: package)
        try basis.workflowReleaseReference.validateTarget(punchReview: release, package: package)
        try installation?.validate(workspaceID: capture.predecessor.workspaceID, assetID: capture.predecessor.subjectID)
        let installationContext = try installation.map {
            try PunchReviewInstallationSnapshotContextV1(
                envelope: $0.envelope, asBuiltSnapshot: $0.asBuilt, completedSnapshot: $0.snapshot
            )
        }
        _ = try PunchReviewWorkflowContextV1(
            envelope: capture.predecessor, release: release, basis: basis,
            scopeDecisions: scopeDecisions, findings: findings,
            correctiveActionEvents: correctiveActionEvents, verifiedRechecks: verifiedRechecks,
            sourceEnvelopes: sourceEnvelopes, planCapability: planCapability.resolved(),
            installationSnapshot: installationContext, closeoutIntent: closeout
        )
        try ActivityCompletedValueV1.require(
            scopeDecisions == scopeDecisions.sorted(by: { $0.scopeItemID < $1.scopeItemID })
                && Set(scopeDecisions.map(\.scopeItemID)) == Set(release.scope.map(\.scopeItemID))
        )
        try ActivityCompletedFindingSupportV1.validate(
            links: scopeDecisions.flatMap(\.findingLinks), findings: findings,
            sourceEnvelopes: sourceEnvelopes, actions: correctiveActionEvents,
            rechecks: verifiedRechecks, capture: capture
        )
    }
}

struct ActivityCompletedInstallationAssociationV1: Codable, Equatable, Sendable {
    let envelope: ActivitySessionEnvelopeV2
    let asBuilt: InstallationAsBuiltSnapshotV1
    let snapshot: CompletedActivitySnapshotV2
    let fileReference: ActivityCompletedFileReferenceV1?

    func validate(workspaceID: WorkspaceID, assetID: UUID) throws {
        _ = try PunchReviewInstallationSnapshotContextV1(
            envelope: envelope, asBuiltSnapshot: asBuilt, completedSnapshot: snapshot
        )
        try fileReference?.validate()
        try ActivityCompletedValueV1.require(
            envelope.workspaceID == workspaceID && envelope.subjectID == assetID
                && envelope.completedFileReference == fileReference
        )
    }
}

private enum ActivityCompletedFindingSupportV1 {
    static func validate(
        links: [PunchFindingLinkV1], findings: [FindingV1],
        sourceEnvelopes: [ActivitySessionEnvelopeV2], actions: [CorrectiveActionEventV1],
        rechecks: [VerifiedRecheckV1], capture: ActivityCompletionCaptureV1
    ) throws {
        for count in [links.count, findings.count, sourceEnvelopes.count, actions.count, rechecks.count] {
            try ActivityCompletedValueV1.bounded(count)
        }
        try ActivityCompletedValueV1.require(
            Set(findings.map { $0.findingID.lowercased() }).count == findings.count
                && Set(links.map(\.findingID)).count == links.count
                && Set(sourceEnvelopes.map(\.envelopeSHA256)).count == sourceEnvelopes.count
        )
        let findingByID = Dictionary(uniqueKeysWithValues: findings.map { ($0.findingID.lowercased(), $0) })
        let envelopeBySHA = Dictionary(uniqueKeysWithValues: sourceEnvelopes.map { ($0.envelopeSHA256, $0) })
        var usedFindings = Set<String>()
        var usedSources = Set<String>()
        var usedActions = Set<UUID>()
        var usedRechecks = Set<String>()
        for source in sourceEnvelopes { try source.validateForRead() }
        for action in actions { try action.validate() }
        let actionGroups = Dictionary(grouping: actions, by: \.actionID)
        for history in actionGroups.values {
            let ordered = history.sorted { $0.revision < $1.revision }
            for (index, value) in ordered.enumerated() {
                try ActivityCompletedValueV1.require(
                    value.workspaceID == capture.predecessor.workspaceID
                        && value.revision == UInt64(index + 1)
                        && (index == 0 ? value.predecessorEventID == nil
                            : value.predecessorEventID == ordered[index - 1].eventID)
                )
            }
        }
        let recheckGroups = Dictionary(grouping: rechecks, by: \.findingID)
        for history in recheckGroups.values { try VerifiedRecheckLineageV1.validate(history.sorted { $0.resultingRecheckRevision < $1.resultingRecheckRevision }) }
        for link in links {
            try link.validate()
            let findingID = link.findingID.uuidString.lowercased()
            guard let finding = findingByID[findingID], let source = envelopeBySHA[link.sourceContext.activitySHA256] else {
                throw ActivityCompletedFileFailureV1.missingBinding
            }
            try ActivityCompletedValueV1.require(
                finding.revision == link.findingRevision
                    && finding.subject.subjectID.lowercased() == capture.predecessor.subjectID.uuidString.lowercased()
                    && (try WorkspaceMutationCanonicalV1.sha256(finding)) == link.findingSHA256
                    && source.workspaceID == capture.predecessor.workspaceID
                    && source.activityID == capture.predecessor.activityID
                    && source.kind == capture.predecessor.kind
                    && source.revision == link.sourceContext.activityRevision
                    && link.sourceContext.workspaceID == source.workspaceID
                    && link.sourceContext.activityID == source.activityID
                    && link.sourceContext.activityKind == source.kind
            )
            usedFindings.insert(findingID); usedSources.insert(source.envelopeSHA256)
            for reference in link.supportingRecords {
                switch reference.kind {
                case .correctiveAction:
                    guard let event = actions.first(where: { $0.eventID == reference.recordID }) else {
                        throw ActivityCompletedFileFailureV1.missingBinding
                    }
                    let head = actionGroups[event.actionID]?.max { $0.revision < $1.revision }
                    try ActivityCompletedValueV1.require(
                        head == event && event.revision == reference.revision
                            && event.eventSHA256 == reference.recordSHA256
                            && event.source.kind == .finding
                            && UUID(uuidString: event.source.itemID) == link.findingID
                            && event.source.itemRevision == UInt64(link.findingRevision)
                            && event.source.itemSHA256 == link.findingSHA256
                    )
                    usedActions.insert(event.actionID)
                case .operationalRecheck:
                    guard let value = rechecks.first(where: { UUID(uuidString: $0.recheckID) == reference.recordID }) else {
                        throw ActivityCompletedFileFailureV1.missingBinding
                    }
                    let head = recheckGroups[value.findingID]?.max { $0.resultingRecheckRevision < $1.resultingRecheckRevision }
                    try ActivityCompletedValueV1.require(
                        head == value && value.resultingRecheckRevision > 0
                            && UInt64(value.resultingRecheckRevision) == reference.revision
                            && (try WorkspaceMutationCanonicalV1.sha256(value)) == reference.recordSHA256
                            && UUID(uuidString: value.findingID) == link.findingID
                            && value.findingRevision == link.findingRevision
                    )
                    usedRechecks.insert(value.findingID)
                }
            }
        }
        try ActivityCompletedValueV1.require(
            usedFindings == Set(findingByID.keys) && usedSources == Set(envelopeBySHA.keys)
                && usedActions == Set(actionGroups.keys) && usedRechecks == Set(recheckGroups.keys)
        )
    }
}

// The live capability contexts are intentionally not Codable. These closed
// frozen values retain their complete existing fields and rebuild the incumbent
// validators without changing an old codec or storing a live provider object.
struct ActivityCompletedInstallationPlanV1: Codable, Equatable, Sendable {
    let disposition: InstallationOptionalCapabilityDispositionV1
    let planReference: InstallationPlanReferenceV1?
    let noPlanFallback: NoPlanFallbackV1?
    let availabilityReceipt: TypedAvailabilityAndFallbackReceiptV1?

    func resolved() throws -> InstallationPlanCapabilityV1 {
        try InstallationPlanCapabilityV1(disposition: disposition, planReference: planReference,
            noPlanFallback: noPlanFallback, availabilityReceipt: availabilityReceipt)
    }
}

struct ActivityCompletedInstallationScanV1: Codable, Equatable, Sendable {
    let disposition: InstallationOptionalCapabilityDispositionV1
    let scanReceipt: InstallationScanEntryReceiptV1?
    let manualFallback: ManualLookupFallbackV1?
    let availabilityReceipt: TypedAvailabilityAndFallbackReceiptV1?

    func resolved() throws -> InstallationScanCapabilityV1 {
        try InstallationScanCapabilityV1(disposition: disposition, scanReceipt: scanReceipt,
            manualFallback: manualFallback, availabilityReceipt: availabilityReceipt)
    }
}

struct ActivityCompletedPunchPlanV1: Codable, Equatable, Sendable {
    let disposition: PunchReviewPlanDispositionV1
    let planReference: PunchPlanReferenceV1?
    let noPlanFallback: NoPlanFallbackV1?
    let externalReference: ActivityExternalReferenceV1?
    let availabilityReceipt: TypedAvailabilityAndFallbackReceiptV1?

    func resolved() throws -> PunchReviewPlanCapabilityV1 {
        try PunchReviewPlanCapabilityV1(disposition: disposition, planReference: planReference,
            noPlanFallback: noPlanFallback, externalReference: externalReference,
            availabilityReceipt: availabilityReceipt)
    }
}

enum ActivityCompletionSupplementalFamilyV1: String, Codable, CaseIterable, Sendable {
    case authorityCriterion = "AUTHORITY_CRITERION"
    case functionalRelationships = "FUNCTIONAL_RELATIONSHIPS"
    case serviceHistory = "SERVICE_HISTORY"
    case evidence = "EVIDENCE"
    case optionalAccountability = "OPTIONAL_ACCOUNTABILITY"
}

enum ActivityCompletionQueryDispositionV1: String, Codable, Sendable {
    case captured = "CAPTURED"
    case checkedNoApplicableSource = "CHECKED_NO_APPLICABLE_SOURCE"
}

/// A recorded query binding is not proof that the query ran. Source capture and
/// writer admission must independently execute this closed query and compare it,
/// including empty membership, at the captured workspace/generation/writer CAS.
struct ActivityCompletionQueryV1: Codable, Equatable, Sendable {
    let family: ActivityCompletionSupplementalFamilyV1
    let disposition: ActivityCompletionQueryDispositionV1
    let sourceWorkspaceRevision: UInt64
    let rootIdentities: [String]
    let capturedValueSHA256: String

    func validate(revision: UInt64, expectedRoots: [String], valueSHA256: String) throws {
        try ActivityCompletedValueV1.bounded(rootIdentities.count)
        try ActivityCompletedValueV1.require(
            sourceWorkspaceRevision == revision
                && ActivityContractValidationV2.sortedUnique(rootIdentities)
                && rootIdentities == expectedRoots.sorted()
                && capturedValueSHA256 == valueSHA256
                && (rootIdentities.isEmpty ? disposition == .checkedNoApplicableSource : disposition == .captured)
        )
    }
}

/// Multiple scopes may intentionally freeze different historical relationship
/// tips. They remain separate; no single artificial current frontier is formed.
struct ActivityCompletionRelationshipScopeV1: Codable, Equatable, Sendable {
    let scope: WorkSubjectScopeSnapshotV1
    let relationships: CompletedFunctionalRelationshipSnapshotV1

    func validate(workspaceID: WorkspaceID) throws {
        try scope.validateFunctionalRelationshipSnapshot(relationships)
        try ActivityCompletedValueV1.require(
            scope.workspaceID == workspaceID && relationships.capturedAt == scope.recordedAt
                && Set(scope.subjects.compactMap(\.functionalRelationship)) == Set(relationships.frozenReferences)
        )
    }
}

struct ActivityCompletionSelectedObjectV1: Codable, Equatable, Sendable {
    let recordID: UUID
    let canonicalSHA256: String

    func validate() throws {
        try ActivityCompletedValueV1.require(recordID != ActivityContractValidationV2.zeroUUID
            && KernelCanonicalHashV1.validSHA256(canonicalSHA256))
    }

    func validate<T: Encodable>(recordID: UUID, value: T) throws {
        try validate()
        try ActivityCompletedValueV1.require(self.recordID == recordID
            && canonicalSHA256 == (try ActivityCompletedValueV1.digest(value)))
    }
}

/// Broader optional selection is deliberately closed and explicit. Selection
/// records exact existing values; it never selects all nearby asset/Site rows.
struct ActivityCompletionExplicitSelectionV1: Codable, Equatable, Sendable {
    let activityID: UUID
    let activityRevision: UInt64
    let activitySHA256: String
    let selectedBy: ActorSnapshotV1
    let selectedAt: Date
    let siteRoleEvents: [ActivityCompletionSelectedObjectV1]
    let qualificationSnapshots: [ActivityCompletionSelectedObjectV1]
    let signoffSnapshots: [ActivityCompletionSelectedObjectV1]
    let workScopes: [WorkSubjectScopeSnapshotV1]
    let derivedProvenance: [ActivityCompletionSelectedObjectV1]
    let additionalServiceRecords: [ServiceRequestRevisionReferenceV1]
    let additionalEvidence: [ContentReferenceV1]

    func validate(capture: ActivityCompletionCaptureV1) throws {
        try selectedBy.validate()
        try ActivityCompletedValueV1.finite([selectedAt])
        try ActivityCompletedValueV1.require(
            activityID == capture.predecessor.activityID && activityRevision == capture.predecessor.revision
                && activitySHA256 == capture.predecessor.envelopeSHA256
                && selectedBy.workspaceID == capture.source.workspaceID && selectedAt <= capture.generatedAt
        )
        for references in [siteRoleEvents, qualificationSnapshots, signoffSnapshots, derivedProvenance] {
            try ActivityCompletedValueV1.bounded(references.count)
            try references.forEach { try $0.validate() }
            let ids = references.map(\.recordID)
            try ActivityCompletedValueV1.require(ids.map(\.uuidString) == ids.map(\.uuidString).sorted() && Set(ids).count == ids.count)
        }
        try workScopes.forEach { try $0.validate() }
        try additionalServiceRecords.forEach { try $0.validate() }
        for count in [workScopes.count, additionalServiceRecords.count, additionalEvidence.count] {
            try ActivityCompletedValueV1.bounded(count)
        }
        try ActivityCompletedValueV1.require(
            workScopes.allSatisfy({ $0.workspaceID == capture.source.workspaceID })
                && Set(workScopes.map(\.snapshotID)).count == workScopes.count
                && Set(additionalServiceRecords.map(\.recordID)).count == additionalServiceRecords.count
                && Set(additionalEvidence.map(\.contentID)).count == additionalEvidence.count
                && additionalEvidence.allSatisfy({ $0.workspaceID == capture.source.workspaceID.rawValue.uuidString.lowercased() })
        )
    }
}

struct ActivityCompletionServiceFactSourceV1: Codable, Equatable, Sendable {
    let fact: CompletedServiceFactV1
    let request: ServiceRequestRevisionReferenceV1
    let dispositionEventIDs: [UUID]
    let workLinkEventIDs: [UUID]
}

struct ActivityCompletionServiceHistoryV1: Codable, Equatable, Sendable {
    let records: [ServiceRequestRecordV1]
    let dispositions: [ServiceRequestDispositionEventV1]
    let workLinks: [ServiceRequestWorkLinkEventV1]
    let sourceWorkEnvelopes: [ActivitySessionEnvelopeV2]
    let factSources: [ActivityCompletionServiceFactSourceV1]

    func validate(capture: ActivityCompletionCaptureV1) throws {
        for count in [records.count, dispositions.count, workLinks.count, sourceWorkEnvelopes.count, factSources.count] {
            try ActivityCompletedValueV1.bounded(count)
        }
        let recordsByID = Dictionary(grouping: records, by: \.recordID)
        for history in recordsByID.values {
            let ordered = history.sorted { $0.revision < $1.revision }
            for (index, value) in ordered.enumerated() {
                try value.validate()
                try ActivityCompletedValueV1.require(value.workspaceID == capture.source.workspaceID && value.recordedAt <= capture.generatedAt)
                if index == 0 { try ActivityCompletedValueV1.require(value.revision == 1) }
                else { try value.validateSuccessor(of: ordered[index - 1]) }
            }
        }
        let references = try records.map { try $0.reference }
        for history in Dictionary(grouping: dispositions, by: { $0.request.recordID }).values {
            let ordered = history.sorted { $0.revision < $1.revision }
            for (index, value) in ordered.enumerated() {
                try value.validate()
                try ActivityCompletedValueV1.require(value.workspaceID == capture.source.workspaceID && references.contains(value.request))
                if let duplicate = value.duplicateRecord { try ActivityCompletedValueV1.require(references.contains(duplicate)) }
                if index == 0 { try ActivityCompletedValueV1.require(value.revision == 1) }
                else { try value.validateSuccessor(of: ordered[index - 1]) }
            }
        }
        try ActivityCompletedValueV1.require(Set(workLinks.map(\.eventID)).count == workLinks.count)
        for value in sourceWorkEnvelopes { try value.validateForRead() }
        for value in workLinks {
            try value.validate()
            try ActivityCompletedValueV1.require(value.workspaceID == capture.source.workspaceID && references.contains(value.request))
            guard let source = sourceWorkEnvelopes.first(where: { $0.envelopeSHA256 == value.canonicalWorkSHA256 }) else {
                throw ActivityCompletedFileFailureV1.missingBinding
            }
            try ActivityCompletedValueV1.require(
                source.workspaceID == capture.source.workspaceID && source.activityID == capture.predecessor.activityID
                    && source.activityID == value.canonicalWorkID && source.revision == value.canonicalWorkRevision
            )
            if case let .activity(id, revision, digest) = value.choice {
                try ActivityCompletedValueV1.require(id == source.activityID && revision == source.revision && digest == source.envelopeSHA256)
            }
            if value.revision == 1 { try ActivityCompletedValueV1.require(value.kind == .link) }
            else {
                guard let prior = workLinks.first(where: { $0.eventID == value.predecessorEventID }) else { throw ActivityCompletedFileFailureV1.invalidHistory }
                try value.validateSuccessor(of: prior)
            }
        }
        try ActivityCompletedValueV1.require(Set(factSources.map { $0.fact.factID }).count == factSources.count)
        for source in factSources {
            try source.fact.validate()
            try ActivityCompletedValueV1.require(
                references.contains(source.request)
                    && Set(source.dispositionEventIDs).isSubset(of: Set(dispositions.filter { $0.request.recordID == source.request.recordID }.map(\.eventID)))
                    && Set(source.workLinkEventIDs).isSubset(of: Set(workLinks.filter { $0.request.recordID == source.request.recordID }.map(\.eventID)))
            )
        }
    }
}

struct ActivityCompletionMediaV1: Codable, Equatable, Sendable {
    let reference: OutputScopedContentReferenceV1
    let byteLength: Int64
    let bytes: Data

    func validate(workspaceID: WorkspaceID, outputScopeID: String) throws {
        try reference.validate()
        try ActivityCompletedValueV1.require(
            !bytes.isEmpty && Int64(bytes.count) == byteLength
                && bytes.count <= ActivityCompletedValueV1.maximumFileBytes
                && KernelCanonicalHashV1.sha256(bytes) == reference.contentSHA256
                && reference.outputScopeID == outputScopeID
                && reference.workspaceBindingSHA256 == KernelCanonicalHashV1.sha256(
                    Data("\(workspaceID.rawValue.uuidString.lowercased())|\(outputScopeID)".utf8)
                )
        )
    }
}

struct ActivityCompletionEvidenceV1: Codable, Equatable, Sendable {
    let selectedOriginals: [ContentReferenceV1]
    let associationHistory: [EvidenceAssociationV1]
    let sequenceHistory: [EvidenceSequenceV1]
    let cards: [EvidenceDetailCardV1]
    let reviewedMarkupPlans: [EvidenceReviewedMarkupPlanV1]
    let privacyProjections: [PrivacyTransformReportProjectionV1]
    let outputMedia: [ActivityCompletionMediaV1]
    let omittedEvidenceIDs: [String]
    let omissionLimitations: [String]

    func validate(capture: ActivityCompletionCaptureV1, profile: ShopReportProfileV1) throws {
        for count in [selectedOriginals.count, associationHistory.count, sequenceHistory.count,
                      cards.count, reviewedMarkupPlans.count, privacyProjections.count, outputMedia.count] {
            try ActivityCompletedValueV1.bounded(count)
        }
        try EvidenceMetadataGraphV1.validate(sequences: sequenceHistory, associationEvents: associationHistory)
        try ActivityCompletedValueV1.require(
            Set(selectedOriginals.map(\.contentID)).count == selectedOriginals.count
                && selectedOriginals.allSatisfy({ $0.workspaceID == capture.source.workspaceID.rawValue.uuidString.lowercased() })
                && selectedOriginals.allSatisfy({ $0.byteRole == .immutableOriginal })
                && associationHistory.allSatisfy({ $0.workspaceID == capture.source.workspaceID.rawValue.uuidString.lowercased() })
                && ActivityContractValidationV2.sortedUnique(omittedEvidenceIDs)
                && omittedEvidenceIDs.allSatisfy(SnapshotProjectionValidationV1.validID)
                && (omittedEvidenceIDs.isEmpty == omissionLimitations.isEmpty)
                && omissionLimitations.allSatisfy({ ActivityContractValidationV2.text($0) })
        )
        var plansByID: [String: EvidenceReviewedMarkupPlanV1] = [:]
        for plan in reviewedMarkupPlans {
            try plan.validate()
            guard let audience = ReportEvidenceAssuranceProjectionPolicyV1.evidenceAudience(for: profile.evidenceDetailProfile.audience) else {
                throw ActivityCompletedFileFailureV1.missingBinding
            }
            let decision = try PrivacyProjectionV1.decide(manifest: plan.privacyManifest, review: plan.privacyReview,
                policy: plan.privacyPolicy, requestedAudience: audience,
                currentSourceRevision: plan.privacyManifest.sourceRevision,
                currentSourceSHA256: plan.privacyManifest.sourceSHA256, at: capture.generatedAt)
            try ActivityCompletedValueV1.require(plan.workspaceID == capture.source.workspaceID
                && selectedOriginals.contains(plan.source)
                && decision.derivative == plan.privacyManifest.derivative && decision.denial == nil
                && plansByID.updateValue(plan, forKey: plan.markupID) == nil)
        }
        var projectionsByManifest: [UUID: PrivacyTransformReportProjectionV1] = [:]
        for projection in privacyProjections {
            try projection.validate()
            try ActivityCompletedValueV1.require(projectionsByManifest.updateValue(projection, forKey: projection.manifestID) == nil)
        }
        let evidenceIDs = Set(associationHistory.map(\.evidenceID))
        var usedPlans = Set<String>()
        var usedProjections = Set<UUID>()
        for card in cards {
            try card.validate()
            guard let plan = plansByID[card.reviewedMarkupID],
                  let association = associationHistory.filter({ $0.evidenceID == card.evidenceID })
                    .max(by: { $0.resultingEvidenceRevision < $1.resultingEvidenceRevision }) else {
                throw ActivityCompletedFileFailureV1.missingBinding
            }
            guard let projection = projectionsByManifest[plan.privacyManifest.manifestID] else {
                throw ActivityCompletedFileFailureV1.missingBinding
            }
            // The recorded projection carries the actual disclosure decision.
            // Rebuilding from its declared value must not synthesize approval.
            let expectedProjection = try PrivacyTransformReportProjectionV1(manifest: plan.privacyManifest,
                review: plan.privacyReview, policy: plan.privacyPolicy, audience: card.audience,
                currentSourceRevision: plan.privacyManifest.sourceRevision,
                currentSourceSHA256: plan.privacyManifest.sourceSHA256,
                redactionDeclared: projection.redactionDeclared, now: capture.generatedAt)
            try ActivityCompletedValueV1.require(projection == expectedProjection)
            _ = try card.c20ValidatePrivacyTransformProjection(projection)
            let derivative = plan.privacyManifest.derivative
            // Media-plan markup binds the derivative bytes. Report-card markup
            // binds transformed display fields; rebuild through its real composer
            // instead of treating those distinct digest domains as equal.
            let expectedCard = try EvidenceDetailComposerV1.compose(cardID: card.cardID,
                workspaceID: card.workspaceID, evidenceID: card.evidenceID, fields: card.fields,
                profile: card.profile, markupID: plan.markupID,
                annotations: plan.reviewedMarkup.orderedAnnotations,
                referenceLabels: plan.reviewedMarkup.orderedReferenceLabels,
                outputReferences: card.outputReferences)
            try ActivityCompletedValueV1.require(
                card.profile == profile.evidenceDetailProfile && evidenceIDs.contains(card.evidenceID)
                    && !omittedEvidenceIDs.contains(card.evidenceID)
                    && card.workspaceID == capture.source.workspaceID.rawValue.uuidString.lowercased()
                    && card == expectedCard && card.evidenceID == plan.source.contentID
                    && association.contentID == plan.source.contentID && association.action != .removed
                    && !card.outputReferences.isEmpty
                    && card.outputReferences.allSatisfy({ $0.contentSHA256 == plan.privacyManifest.derivativeSHA256
                        && $0.byteRole == .derivative && $0.mediaType == derivative.mediaType })
            )
            for reference in card.outputReferences {
                guard let ordinal = Int(reference.outputReferenceID.suffix(3)) else {
                    throw ActivityCompletedFileFailureV1.missingBinding
                }
                let expected = try OutputScopedContentReferenceV1(outputScopeID: card.outputScopeID,
                    ordinal: ordinal, reference: derivative)
                try ActivityCompletedValueV1.require(reference == expected)
            }
            try ActivityCompletedValueV1.require(usedPlans.insert(plan.markupID).inserted
                && usedProjections.insert(projection.manifestID).inserted)
        }
        try ActivityCompletedValueV1.require(usedPlans == Set(plansByID.keys)
            && usedProjections == Set(projectionsByManifest.keys))
        try ActivityCompletedValueV1.require(Set(omittedEvidenceIDs).isSubset(of: evidenceIDs))
        var requiredMedia = Set(cards.flatMap(\.outputReferences))
        if let logo = profile.brand.logo { requiredMedia.insert(logo) }
        try ActivityCompletedValueV1.require(
            Set(outputMedia.map(\.reference)) == requiredMedia
                && outputMedia.count == requiredMedia.count
                && outputMedia.count <= profile.exportProfile.maximumMediaItems
        )
        for media in outputMedia {
            try media.validate(workspaceID: capture.source.workspaceID, outputScopeID: profile.evidenceDetailProfile.outputScopeID)
        }
    }
}

struct ActivityCompletionSupplementalV1: Codable, Equatable, Sendable {
    let accountability: CompletedAccountabilitySnapshotV1
    let authorityCriterion: CompletedAuthorityCriterionSnapshotV1?
    let relationshipScopes: [ActivityCompletionRelationshipScopeV1]
    let serviceHistory: ActivityCompletionServiceHistoryV1
    let evidence: ActivityCompletionEvidenceV1
    let explicitSelection: ActivityCompletionExplicitSelectionV1?
    let queries: [ActivityCompletionQueryV1]

    func validate(capture: ActivityCompletionCaptureV1, profile: ShopReportProfileV1, findings: [FindingV1],
                  placementSources: ActivityCompletionPlacementSourcesV1?) throws {
        try accountability.validate()
        try authorityCriterion?.validate()
        try explicitSelection?.validate(capture: capture)
        try serviceHistory.validate(capture: capture)
        try evidence.validate(capture: capture, profile: profile)
        try ActivityCompletedValueV1.require(accountability.workspaceID == capture.source.workspaceID)
        var mandatoryActors = capture.transitionHistory.map(\.actor)
        mandatoryActors.append(capture.completionTransition.actor)
        mandatoryActors.append(contentsOf: capture.predecessor.variations.map(\.actor))
        mandatoryActors.append(profile.recordedBy)
        if let placementSources {
            mandatoryActors.append(contentsOf: placementSources.planRevisions.map(\.recordedBy))
            mandatoryActors.append(contentsOf: placementSources.poseEvents.map(\.recordedBy))
        }
        for plan in evidence.reviewedMarkupPlans {
            mandatoryActors.append(plan.privacyReview.reviewer)
            mandatoryActors.append(contentsOf: plan.privacyManifest.orderedRegions.map(\.author))
        }
        if let selection = explicitSelection { mandatoryActors.append(selection.selectedBy) }
        if let authorityCriterion {
            try ActivityCompletedValueV1.require(authorityCriterion.workspaceID == capture.source.workspaceID)
            mandatoryActors.append(contentsOf: authorityCriterion.aggregate.applicabilityContexts.map(\.actor))
            mandatoryActors.append(contentsOf: authorityCriterion.aggregate.basisBindings.map(\.selectedBy))
            for qualification in authorityCriterion.aggregate.applicabilityContexts.compactMap(\.qualification) {
                try ActivityCompletedValueV1.require(accountability.qualifications.contains(qualification))
            }
            for classification in authorityCriterion.aggregate.classificationBindings {
                guard let finding = findings.first(where: { UUID(uuidString: $0.findingID) == classification.findingID }) else {
                    throw ActivityCompletedFileFailureV1.missingBinding
                }
                let scale = authorityCriterion.aggregate.severityScaleReleases.first { $0.releaseID == classification.severityScaleReleaseID }
                try finding.validateClassification(classification, scale: scale)
            }
        }
        for sequence in evidence.sequenceHistory {
            for item in sequence.orderedItems {
                mandatoryActors.append(item.caption.reviewer)
                if let description = item.accessibilityDescription { mandatoryActors.append(description.reviewer) }
            }
        }
        let selectedRoleIDs = Set((explicitSelection?.siteRoleEvents ?? []).map(\.recordID))
        let selectedSignoffIDs = Set((explicitSelection?.signoffSnapshots ?? []).map(\.recordID))
        let roleByID = Dictionary(uniqueKeysWithValues: accountability.roleEvents.map { ($0.eventID, $0) })
        var retainedRoleIDs = Set<UUID>()
        for root in selectedRoleIDs {
            var current: UUID? = root
            var lineage = Set<UUID>()
            while let id = current {
                guard lineage.insert(id).inserted, let event = roleByID[id] else { throw ActivityCompletedFileFailureV1.invalidHistory }
                retainedRoleIDs.insert(id)
                if let priorID = event.supersedesEventID {
                    guard let prior = roleByID[priorID] else { throw ActivityCompletedFileFailureV1.invalidHistory }
                    try event.validateSupersession(of: prior)
                } else { try ActivityCompletedValueV1.require(event.revision == 1) }
                current = event.supersedesEventID
            }
        }
        try ActivityCompletedValueV1.require(retainedRoleIDs == Set(roleByID.keys))
        let signoffByID = Dictionary(uniqueKeysWithValues: accountability.signoffs.map { ($0.snapshotID, $0) })
        var retainedSignoffIDs = Set<UUID>()
        for root in selectedSignoffIDs {
            var current: UUID? = root
            var lineage = Set<UUID>()
            while let id = current {
                guard lineage.insert(id).inserted, let signoff = signoffByID[id] else { throw ActivityCompletedFileFailureV1.invalidHistory }
                retainedSignoffIDs.insert(id)
                if let priorID = signoff.supersedesSnapshotID {
                    guard let prior = signoffByID[priorID] else { throw ActivityCompletedFileFailureV1.invalidHistory }
                    try ActivityCompletedValueV1.require(prior.subjectID == signoff.subjectID
                        && prior.subjectRevision == signoff.subjectRevision && prior.purpose == signoff.purpose
                        && prior.recordedAt <= signoff.recordedAt)
                }
                current = signoff.supersedesSnapshotID
            }
        }
        try ActivityCompletedValueV1.require(retainedSignoffIDs == Set(signoffByID.keys))
        mandatoryActors.append(contentsOf: accountability.signoffs.compactMap { $0.roleAssertion?.actor })
        for actor in mandatoryActors { try ActivityCompletedValueV1.require(accountability.actors.contains(actor)) }
        try ActivityCompletedValueV1.require(!accountability.actors.isEmpty
            && Set(accountability.actors.map(\.snapshotID)) == Set(mandatoryActors.map(\.snapshotID)))

        var qualificationIDs = Set((explicitSelection?.qualificationSnapshots ?? []).map(\.recordID))
        for qualification in accountability.signoffs.compactMap(\.qualification) {
            qualificationIDs.insert(qualification.snapshotID)
            try ActivityCompletedValueV1.require(accountability.qualifications.contains(qualification))
        }
        for qualification in authorityCriterion?.aggregate.applicabilityContexts.compactMap(\.qualification) ?? [] {
            qualificationIDs.insert(qualification.snapshotID)
        }
        try ActivityCompletedValueV1.require(qualificationIDs == Set(accountability.qualifications.map(\.snapshotID)))
        if let selection = explicitSelection {
            for reference in selection.siteRoleEvents {
                guard let value = roleByID[reference.recordID] else { throw ActivityCompletedFileFailureV1.missingBinding }
                try reference.validate(recordID: value.eventID, value: value)
            }
            for reference in selection.signoffSnapshots {
                guard let value = signoffByID[reference.recordID] else { throw ActivityCompletedFileFailureV1.missingBinding }
                try reference.validate(recordID: value.snapshotID, value: value)
            }
            for reference in selection.qualificationSnapshots {
                guard let value = accountability.qualifications.first(where: { $0.snapshotID == reference.recordID }) else { throw ActivityCompletedFileFailureV1.missingBinding }
                try reference.validate(recordID: value.snapshotID, value: value)
            }
            for reference in selection.derivedProvenance {
                guard let value = authorityCriterion?.aggregate.derivedFacts.first(where: { $0.provenanceID == reference.recordID }) else { throw ActivityCompletedFileFailureV1.missingBinding }
                try reference.validate(recordID: value.provenanceID, value: value)
            }
        }
        try ActivityCompletedValueV1.require(
            Set((explicitSelection?.derivedProvenance ?? []).map(\.recordID))
                == Set(authorityCriterion?.aggregate.derivedFacts.map(\.provenanceID) ?? [])
        )
        var selectedScopes = explicitSelection?.workScopes ?? []
        if let authorityCriterion {
            selectedScopes.append(contentsOf: authorityCriterion.aggregate.applicabilityContexts.map(\.workSubjectScope))
            selectedScopes.append(contentsOf: authorityCriterion.aggregate.assessmentScopes.map(\.workSubjectScope))
        }
        var scopesByID: [UUID: WorkSubjectScopeSnapshotV1] = [:]
        for scope in selectedScopes where !scope.subjects.compactMap(\.functionalRelationship).isEmpty {
            if let prior = scopesByID[scope.snapshotID] { try ActivityCompletedValueV1.require(prior == scope) }
            scopesByID[scope.snapshotID] = scope
        }
        try ActivityCompletedValueV1.require(
            Set(relationshipScopes.map { $0.scope.snapshotID }) == Set(scopesByID.keys)
                && relationshipScopes.count == scopesByID.count
        )
        for value in relationshipScopes {
            try value.validate(workspaceID: capture.source.workspaceID)
            try ActivityCompletedValueV1.require(scopesByID[value.scope.snapshotID] == value.scope)
        }
        var partyIDs = Set(accountability.actors.compactMap { $0.actor.partyID })
        partyIDs.formUnion(accountability.roleEvents.map(\.partyID))
        for value in relationshipScopes {
            partyIDs.formUnion(value.relationships.relationships.compactMap { $0.actor.partyID })
        }
        try ActivityCompletedValueV1.require(partyIDs == Set(accountability.parties.map(\.partyID)))
        let authorityRoots: [String] = authorityCriterion.map { value in
            var roots: [String] = value.aggregate.applicabilityContexts.filter { $0.activityID == capture.predecessor.activityID }.map { "applicability:\($0.snapshotID.uuidString.lowercased())" }
            roots.append(contentsOf: value.aggregate.classificationBindings.map { "classification:\($0.bindingID.uuidString.lowercased())" })
            roots.append(contentsOf: value.aggregate.derivedFacts.map { "derived:\($0.provenanceID.uuidString.lowercased())" })
            return roots.sorted()
        } ?? []
        let relationshipRoots = relationshipScopes.map { $0.scope.snapshotID.uuidString.lowercased() }.sorted()
        var serviceRoots = serviceHistory.workLinks.map { "link:\($0.eventID.uuidString.lowercased())" }
        serviceRoots.append(contentsOf: (explicitSelection?.additionalServiceRecords ?? []).map { "record:\($0.recordID.uuidString.lowercased()):\($0.revision)" })
        var optionalRoots = (explicitSelection?.siteRoleEvents ?? []).map { "role:\($0.recordID.uuidString.lowercased())" }
        optionalRoots.append(contentsOf: (explicitSelection?.qualificationSnapshots ?? []).map { "qualification:\($0.recordID.uuidString.lowercased())" })
        optionalRoots.append(contentsOf: (explicitSelection?.signoffSnapshots ?? []).map { "signoff:\($0.recordID.uuidString.lowercased())" })
        try ActivityCompletedValueV1.require(
            queries.map(\.family) == ActivityCompletionSupplementalFamilyV1.allCases
        )
        for query in queries {
            let roots: [String]
            let digest: String
            switch query.family {
            case .authorityCriterion:
                roots = authorityRoots; digest = try ActivityCompletedValueV1.digest(authorityCriterion)
            case .functionalRelationships:
                roots = relationshipRoots; digest = try ActivityCompletedValueV1.digest(relationshipScopes)
            case .serviceHistory:
                roots = serviceRoots; digest = try ActivityCompletedValueV1.digest(serviceHistory)
            case .evidence:
                roots = evidence.selectedOriginals.map(\.contentID); digest = try ActivityCompletedValueV1.digest(evidence)
            case .optionalAccountability:
                roots = optionalRoots; digest = try ActivityCompletedValueV1.digest(explicitSelection)
            }
            try query.validate(revision: capture.source.workspaceRevision, expectedRoots: roots, valueSHA256: digest)
        }
        try ActivityCompletedValueV1.require(
            (authorityRoots.isEmpty ? authorityCriterion == nil : authorityCriterion != nil)
                && (serviceRoots.isEmpty ? serviceHistory.records.isEmpty && serviceHistory.factSources.isEmpty : true)
        )
    }
}

/// A C47 correction is its own V2 original. This relation names a different
/// activity's immutable completed output; it does not reinterpret V2 amendment.
struct ActivityCompletedPredecessorV1: Codable, Equatable, Sendable {
    let activityFrontier: ActivitySessionEnvelopeV2
    let snapshot: CompletedActivitySnapshotV2
    let owner: ActivityCompletedPredecessorOwnerV1
    let reason: String

    func validate(successor: ActivityCompletionCaptureV1, outputID: UUID, snapshotID: String) throws {
        try activityFrontier.validateForRead(); try snapshot.validate(); try owner.validate()
        guard let amendment = successor.predecessor.amendment,
              let reference = activityFrontier.completedSnapshotReference else {
            throw ActivityCompletedFileFailureV1.missingBinding
        }
        let prior = snapshot.payload.activity
        try reference.validate(snapshot: snapshot)
        switch owner.kind {
        case .completedFile:
            let fileReference = try ActivityCompletedFileReferenceV1(outputID: owner.outputID, fileSHA256: owner.fileSHA256)
            try ActivityCompletedValueV1.require(activityFrontier.completedFileReference == fileReference)
        case .legacyV2:
            // The legacy file hash is the hash of the complete encoded V2,
            // never its payload-only snapshotSHA256. Its UUID is owner-supplied.
            try ActivityCompletedValueV1.require(
                activityFrontier.completedFileReference == nil
                    && owner.fileSHA256 == KernelCanonicalHashV1.sha256(try CompletedActivitySnapshotCanonicalCodecV2.encode(snapshot))
            )
        }
        try ActivityCompletedValueV1.require(
            activityFrontier.activityID == amendment.predecessorActivityID
                && activityFrontier.revision == amendment.predecessorRevision
                && activityFrontier.envelopeSHA256 == amendment.predecessorSHA256
                && activityFrontier.activityID != successor.predecessor.activityID
                && activityFrontier.workspaceID == successor.predecessor.workspaceID
                && activityFrontier.subjectID == successor.predecessor.subjectID
                && activityFrontier.kind == successor.predecessor.kind
                && owner.outputID != outputID && prior.snapshotID != snapshotID && reason == amendment.reason
                && reference.snapshotID == prior.snapshotID
                && reference.snapshotRevision == prior.snapshotRevision
                && reference.snapshotSHA256 == snapshot.snapshotSHA256
        )
    }
}

enum ActivityCompletedPredecessorOwnerKindV1: String, Codable, Sendable {
    case completedFile = "COMPLETED_FILE"
    case legacyV2 = "LEGACY_V2"
}

/// Explicit closed tag/fields, without synthesized associated-enum JSON.
/// LEGACY_V2 output identity must be resolved from its genuine Report owner.
struct ActivityCompletedPredecessorOwnerV1: Codable, Equatable, Sendable {
    let kind: ActivityCompletedPredecessorOwnerKindV1
    let fileVersion: Int
    let outputID: UUID
    let relativePath: String
    let fileSHA256: String

    func validate() throws {
        let version = kind == .completedFile ? ActivityCompletedFileReferenceV1.fileVersion : CompletedActivitySnapshotV2.schemaVersion
        try ActivityCompletedValueV1.require(
            fileVersion == version && outputID != ActivityContractValidationV2.zeroUUID
                && relativePath == "snapshots/\(outputID.uuidString.lowercased()).json"
                && KernelCanonicalHashV1.validSHA256(fileSHA256)
        )
    }
}

struct ActivityCompletedFileV1: Codable, Equatable, Sendable {
    static let currentFamily = ActivityCompletedFileReferenceV1.fileFormat
    static let currentFormatVersion = ActivityCompletedFileReferenceV1.fileVersion
    let family: String
    let formatVersion: Int
    let outputID: UUID
    let snapshot: CompletedActivitySnapshotV2
    let capture: ActivityCompletionCaptureV1
    let installation: ActivityCompletedInstallationV1?
    let punchReview: ActivityCompletedPunchV1?
    let packageRelease: InspectionPackageReleaseV1
    let shopProfile: ShopReportProfileV1
    let manifest: ContractManifestV1
    let supplemental: ActivityCompletionSupplementalV1
    let completedPredecessor: ActivityCompletedPredecessorV1?
    let unfinishedAmendmentPredecessor: ActivitySessionEnvelopeV2?

    var relativePath: String { "snapshots/\(outputID.uuidString.lowercased()).json" }

    func validateIntrinsic() throws {
        guard family == Self.currentFamily, formatVersion == Self.currentFormatVersion else {
            throw ActivityCompletedFileFailureV1.incompatibleVersion
        }
        try snapshot.validate(); try capture.validateIntrinsic(); try packageRelease.validate()
        try manifest.validate(); try shopProfile.validate(sectionRegistry: manifest.reportSectionRegistry)
        let base = snapshot.payload.activity
        let predecessor = capture.predecessor
        try ActivityCompletedValueV1.require(
            outputID != ActivityContractValidationV2.zeroUUID
                && base.reportID == outputID.uuidString.lowercased()
                && base.workspaceID == predecessor.workspaceID.rawValue.uuidString.lowercased()
                && base.sourceActivityID == predecessor.activityID.uuidString.lowercased()
                && base.sourceRevision == Int(exactly: capture.resultingActivityRevision)
                && snapshot.payload.assetID == predecessor.subjectID
                && snapshot.payload.locationComposition.frozenAtRevision == capture.source.workspaceRevision
        )
        try ActivityCompletedValueV1.require(
            base.snapshotRevision == 1 && base.supersedesSnapshotID == nil
                && base.supersededSnapshotSHA256 == nil && base.amendmentReason == nil
                && SnapshotProjectionValidationV1.instantDate(base.completedAt) == capture.finalizedAt
                && SnapshotProjectionValidationV1.instantDate(base.generatedAt) == capture.generatedAt
                && base.packageReleaseID == packageRelease.packageReleaseID && packageRelease.state == .published
                && shopProfile.workspaceID == predecessor.workspaceID && shopProfile.activation == .on
        )
        let package = try InspectionPackageCanonicalCodecV2.decode(packageRelease.canonicalPackageBytes)
        let findings: [FindingV1]
        switch predecessor.kind {
        case .installation:
            guard let installation, punchReview == nil else { throw ActivityCompletedFileFailureV1.missingBinding }
            try installation.validate(capture: capture, package: package)
            findings = installation.findings
        case .punchReview:
            guard let punchReview, installation == nil else { throw ActivityCompletedFileFailureV1.missingBinding }
            try punchReview.validate(capture: capture, package: package)
            findings = punchReview.findings
        default: throw ActivityCompletedFileFailureV1.invalidValue
        }
        try validateProfileBinding(base.profileBinding)
        try supplemental.validate(capture: capture, profile: shopProfile, findings: findings,
            placementSources: installation?.placementSources)
        try ActivityCompletedValueV1.require(
            base.serviceFacts == supplemental.serviceHistory.factSources.map(\.fact).sorted()
                && base.evidenceCards == supplemental.evidence.cards
                && supplemental.evidence.omissionLimitations.allSatisfy({ base.limitations.contains($0) })
        )
        // Only current task heads select current report evidence. Full task
        // history remains frozen above; historical finding roots stay explicit.
        if let installation {
            let heads = try InstallationTaskResultLineageV1.validateAndCurrentHeads(installation.taskHistory)
            for head in heads.values {
                for reference in head.evidenceReferences {
                    try ActivityCompletedValueV1.require(supplemental.evidence.selectedOriginals.contains(reference))
                }
            }
            if let limitation = installation.closeout.limitation {
                try ActivityCompletedValueV1.require(base.limitations.contains(limitation))
            }
        }
        if let punchReview {
            try ActivityCompletedValueV1.require(base.limitations.contains(punchReview.closeout.scopeAndTimeLimitation))
        }
        if let completedPredecessor {
            try ActivityCompletedValueV1.require(unfinishedAmendmentPredecessor == nil)
            try completedPredecessor.validate(successor: capture, outputID: outputID, snapshotID: base.snapshotID)
        } else if let prior = unfinishedAmendmentPredecessor {
            try prior.validateForRead()
            guard let amendment = predecessor.amendment else { throw ActivityCompletedFileFailureV1.missingBinding }
            try ActivityCompletedValueV1.require(
                prior.activityID == amendment.predecessorActivityID
                    && prior.revision == amendment.predecessorRevision && prior.envelopeSHA256 == amendment.predecessorSHA256
                    && prior.activityID != predecessor.activityID && prior.workspaceID == predecessor.workspaceID
                    && prior.subjectID == predecessor.subjectID && prior.kind == predecessor.kind
                    && prior.finalizedAt == nil && prior.completedSnapshotReference == nil && prior.completedFileReference == nil
            )
        } else {
            try ActivityCompletedValueV1.require(predecessor.amendment == nil)
        }
    }

    private func validateProfileBinding(_ binding: FinalizedReportProfileBindingV1) throws {
        try binding.validate()
        let layout = shopProfile.reportLayoutProfile
        let export = shopProfile.exportProfile
        let registry = manifest.reportSectionRegistry
        let layoutSHA = try ActivityCompletedValueV1.digest(layout)
        let exportSHA = try ActivityCompletedValueV1.digest(export)
        let registrySHA = try ActivityCompletedValueV1.digest(registry)
        let manifestSHA = try ActivityCompletedValueV1.digest(manifest)
        try ActivityCompletedValueV1.require(
            binding.reportProfileID == layout.profileID && binding.reportProfileRelease == layout.profileRelease
                && binding.reportProfileSHA256 == layoutSHA
                && binding.exportProfileID == export.exportProfileID && binding.exportProfileRelease == export.exportProfileRelease
                && binding.exportProfileSHA256 == exportSHA
        )
        try ActivityCompletedValueV1.require(
            binding.sectionRegistryID == registry.registryID && binding.sectionRegistryVersion == registry.registryVersion
                && binding.sectionRegistrySHA256 == registrySHA
                && binding.contractManifestID == manifest.manifestID && binding.contractManifestVersion == manifest.manifestVersion
                && binding.contractManifestSHA256 == manifestSHA
        )
        try ActivityCompletedValueV1.require(
            binding.sectionIDs == layout.sectionIDs && binding.audience == layout.audience
                && binding.detail == layout.detail && binding.privacyTransformID == export.privacyTransformID
                && binding.localeIdentifier == layout.localeIdentifier && binding.unitsProfileID == layout.unitsProfileID
        )
        try ActivityCompletedValueV1.require(
            binding.displayProfileID == layout.displayProfileID && binding.orientation == layout.orientation
                && binding.mediaLayout == layout.mediaLayout && binding.rendererVersion == shopProfile.rendererVersion
                && binding.outputScopeID == shopProfile.evidenceDetailProfile.outputScopeID
        )
    }

    func canonicalData() throws -> Data {
        try validateIntrinsic()
        let data = try ActivityCompletedValueV1.canonical(self)
        guard data.count <= ActivityCompletedValueV1.maximumFileBytes else { throw ActivityCompletedFileFailureV1.limitExceeded }
        return data
    }

    func reference() throws -> ActivityCompletedFileReferenceV1 {
        try ActivityCompletedFileReferenceV1(outputID: outputID, fileSHA256: KernelCanonicalHashV1.sha256(canonicalData()))
    }

    static func decodeCanonical(_ data: Data, reference: ActivityCompletedFileReferenceV1? = nil) throws -> Self {
        guard !data.isEmpty, data.count <= ActivityCompletedValueV1.maximumFileBytes else { throw ActivityCompletedFileFailureV1.limitExceeded }
        let file = try JSONDecoder().decode(Self.self, from: data)
        try file.validateIntrinsic()
        guard try file.canonicalData() == data else { throw ActivityCompletedFileFailureV1.digestMismatch }
        if let reference {
            try reference.validate()
            guard reference == (try file.reference()) else { throw ActivityCompletedFileFailureV1.digestMismatch }
        }
        return file
    }
}

// New-format decoding is closed at every newly declared object boundary.
extension ActivityCompletionCaptureV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, source, predecessor, transitionHistory, completionTransition, resultingActivityRevision, capturedAt, generatedAt
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            version: values.decode(Int.self, forKey: .version),
            source: values.decode(MutationPortableExpectedRevisionV1.self, forKey: .source),
            predecessor: values.decode(ActivitySessionEnvelopeV2.self, forKey: .predecessor),
            transitionHistory: values.decode([ActivityStateTransitionV2].self, forKey: .transitionHistory),
            completionTransition: values.decode(ActivityStateTransitionV2.self, forKey: .completionTransition),
            resultingActivityRevision: values.decode(UInt64.self, forKey: .resultingActivityRevision),
            capturedAt: values.decode(Date.self, forKey: .capturedAt),
            generatedAt: values.decode(Date.self, forKey: .generatedAt)
        )
        try validateIntrinsic()
    }
}

extension ActivityCompletedInstallationV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sourceRelease, release, basisHistory, taskHistory, asBuilt, placementSources, closeout, planCapability, scanCapability, findings, sourceEnvelopes, correctiveActionEvents, verifiedRechecks
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sourceRelease: values.decode(InstallationWorkflowDefinitionReleaseV1.self, forKey: .sourceRelease),
            release: values.decode(InstallationWorkflowDefinitionReleaseV1.self, forKey: .release),
            basisHistory: values.decode([InstallationBasisSnapshotV1].self, forKey: .basisHistory),
            taskHistory: values.decode([InstallationTaskResultV1].self, forKey: .taskHistory),
            asBuilt: values.decode(InstallationAsBuiltSnapshotV1.self, forKey: .asBuilt),
            placementSources: values.decode(ActivityCompletionPlacementSourcesV1.self, forKey: .placementSources),
            closeout: values.decode(InstallationCloseoutV1.self, forKey: .closeout),
            planCapability: values.decode(ActivityCompletedInstallationPlanV1.self, forKey: .planCapability),
            scanCapability: values.decode(ActivityCompletedInstallationScanV1.self, forKey: .scanCapability),
            findings: values.decode([FindingV1].self, forKey: .findings),
            sourceEnvelopes: values.decode([ActivitySessionEnvelopeV2].self, forKey: .sourceEnvelopes),
            correctiveActionEvents: values.decode([CorrectiveActionEventV1].self, forKey: .correctiveActionEvents),
            verifiedRechecks: values.decode([VerifiedRecheckV1].self, forKey: .verifiedRechecks)
        )
    }
}

extension ActivityCompletionPlacementSourcesV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case planDocuments, planRevisions, planPlacements, poseEvents, placementHistory
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            planDocuments: values.decode([PlanDocumentV1].self, forKey: .planDocuments),
            planRevisions: values.decode([PlanRevisionV1].self, forKey: .planRevisions),
            planPlacements: values.decode([PlanPlacementV1].self, forKey: .planPlacements),
            poseEvents: values.decode([AssetPoseEventV1].self, forKey: .poseEvents),
            placementHistory: values.decode([AssetPlacementEventV1].self, forKey: .placementHistory)
        )
    }
}

extension ActivityCompletedPunchV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sourceRelease, release, basisHistory, scopeDecisions, closeout, planCapability, findings, sourceEnvelopes, correctiveActionEvents, verifiedRechecks, installation
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sourceRelease: values.decode(PunchReviewWorkflowDefinitionReleaseV1.self, forKey: .sourceRelease),
            release: values.decode(PunchReviewWorkflowDefinitionReleaseV1.self, forKey: .release),
            basisHistory: values.decode([PunchReviewBasisSnapshotV1].self, forKey: .basisHistory),
            scopeDecisions: values.decode([PunchItemProjectionV1].self, forKey: .scopeDecisions),
            closeout: values.decode(PunchReviewCloseoutV1.self, forKey: .closeout),
            planCapability: values.decode(ActivityCompletedPunchPlanV1.self, forKey: .planCapability),
            findings: values.decode([FindingV1].self, forKey: .findings),
            sourceEnvelopes: values.decode([ActivitySessionEnvelopeV2].self, forKey: .sourceEnvelopes),
            correctiveActionEvents: values.decode([CorrectiveActionEventV1].self, forKey: .correctiveActionEvents),
            verifiedRechecks: values.decode([VerifiedRecheckV1].self, forKey: .verifiedRechecks),
            installation: values.decodeIfPresent(ActivityCompletedInstallationAssociationV1.self, forKey: .installation)
        )
    }
}

extension ActivityCompletedInstallationAssociationV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case envelope, asBuilt, snapshot, fileReference
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            envelope: values.decode(ActivitySessionEnvelopeV2.self, forKey: .envelope),
            asBuilt: values.decode(InstallationAsBuiltSnapshotV1.self, forKey: .asBuilt),
            snapshot: values.decode(CompletedActivitySnapshotV2.self, forKey: .snapshot),
            fileReference: values.decodeIfPresent(ActivityCompletedFileReferenceV1.self, forKey: .fileReference)
        )
    }
}

extension ActivityCompletedInstallationPlanV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case disposition, planReference, noPlanFallback, availabilityReceipt
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            disposition: values.decode(InstallationOptionalCapabilityDispositionV1.self, forKey: .disposition),
            planReference: values.decodeIfPresent(InstallationPlanReferenceV1.self, forKey: .planReference),
            noPlanFallback: values.decodeIfPresent(NoPlanFallbackV1.self, forKey: .noPlanFallback),
            availabilityReceipt: values.decodeIfPresent(TypedAvailabilityAndFallbackReceiptV1.self, forKey: .availabilityReceipt)
        )
    }
}

extension ActivityCompletedInstallationScanV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case disposition, scanReceipt, manualFallback, availabilityReceipt
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            disposition: values.decode(InstallationOptionalCapabilityDispositionV1.self, forKey: .disposition),
            scanReceipt: values.decodeIfPresent(InstallationScanEntryReceiptV1.self, forKey: .scanReceipt),
            manualFallback: values.decodeIfPresent(ManualLookupFallbackV1.self, forKey: .manualFallback),
            availabilityReceipt: values.decodeIfPresent(TypedAvailabilityAndFallbackReceiptV1.self, forKey: .availabilityReceipt)
        )
    }
}

extension ActivityCompletedPunchPlanV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case disposition, planReference, noPlanFallback, externalReference, availabilityReceipt
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            disposition: values.decode(PunchReviewPlanDispositionV1.self, forKey: .disposition),
            planReference: values.decodeIfPresent(PunchPlanReferenceV1.self, forKey: .planReference),
            noPlanFallback: values.decodeIfPresent(NoPlanFallbackV1.self, forKey: .noPlanFallback),
            externalReference: values.decodeIfPresent(ActivityExternalReferenceV1.self, forKey: .externalReference),
            availabilityReceipt: values.decodeIfPresent(TypedAvailabilityAndFallbackReceiptV1.self, forKey: .availabilityReceipt)
        )
    }
}

extension ActivityCompletionQueryV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case family, disposition, sourceWorkspaceRevision, rootIdentities, capturedValueSHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            family: values.decode(ActivityCompletionSupplementalFamilyV1.self, forKey: .family),
            disposition: values.decode(ActivityCompletionQueryDispositionV1.self, forKey: .disposition),
            sourceWorkspaceRevision: values.decode(UInt64.self, forKey: .sourceWorkspaceRevision),
            rootIdentities: values.decode([String].self, forKey: .rootIdentities),
            capturedValueSHA256: values.decode(String.self, forKey: .capturedValueSHA256)
        )
    }
}

extension ActivityCompletionRelationshipScopeV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case scope, relationships
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            scope: values.decode(WorkSubjectScopeSnapshotV1.self, forKey: .scope),
            relationships: values.decode(CompletedFunctionalRelationshipSnapshotV1.self, forKey: .relationships)
        )
    }
}

extension ActivityCompletionSelectedObjectV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case recordID, canonicalSHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            recordID: values.decode(UUID.self, forKey: .recordID),
            canonicalSHA256: values.decode(String.self, forKey: .canonicalSHA256)
        )
    }
}

extension ActivityCompletionExplicitSelectionV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case activityID, activityRevision, activitySHA256, selectedBy, selectedAt, siteRoleEvents, qualificationSnapshots, signoffSnapshots, workScopes, derivedProvenance, additionalServiceRecords, additionalEvidence
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            activityID: values.decode(UUID.self, forKey: .activityID),
            activityRevision: values.decode(UInt64.self, forKey: .activityRevision),
            activitySHA256: values.decode(String.self, forKey: .activitySHA256),
            selectedBy: values.decode(ActorSnapshotV1.self, forKey: .selectedBy),
            selectedAt: values.decode(Date.self, forKey: .selectedAt),
            siteRoleEvents: values.decode([ActivityCompletionSelectedObjectV1].self, forKey: .siteRoleEvents),
            qualificationSnapshots: values.decode([ActivityCompletionSelectedObjectV1].self, forKey: .qualificationSnapshots),
            signoffSnapshots: values.decode([ActivityCompletionSelectedObjectV1].self, forKey: .signoffSnapshots),
            workScopes: values.decode([WorkSubjectScopeSnapshotV1].self, forKey: .workScopes),
            derivedProvenance: values.decode([ActivityCompletionSelectedObjectV1].self, forKey: .derivedProvenance),
            additionalServiceRecords: values.decode([ServiceRequestRevisionReferenceV1].self, forKey: .additionalServiceRecords),
            additionalEvidence: values.decode([ContentReferenceV1].self, forKey: .additionalEvidence)
        )
    }
}

extension ActivityCompletionServiceFactSourceV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case fact, request, dispositionEventIDs, workLinkEventIDs
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            fact: values.decode(CompletedServiceFactV1.self, forKey: .fact),
            request: values.decode(ServiceRequestRevisionReferenceV1.self, forKey: .request),
            dispositionEventIDs: values.decode([UUID].self, forKey: .dispositionEventIDs),
            workLinkEventIDs: values.decode([UUID].self, forKey: .workLinkEventIDs)
        )
    }
}

extension ActivityCompletionServiceHistoryV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case records, dispositions, workLinks, sourceWorkEnvelopes, factSources
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            records: values.decode([ServiceRequestRecordV1].self, forKey: .records),
            dispositions: values.decode([ServiceRequestDispositionEventV1].self, forKey: .dispositions),
            workLinks: values.decode([ServiceRequestWorkLinkEventV1].self, forKey: .workLinks),
            sourceWorkEnvelopes: values.decode([ActivitySessionEnvelopeV2].self, forKey: .sourceWorkEnvelopes),
            factSources: values.decode([ActivityCompletionServiceFactSourceV1].self, forKey: .factSources)
        )
    }
}

extension ActivityCompletionMediaV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case reference, byteLength, bytes
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            reference: values.decode(OutputScopedContentReferenceV1.self, forKey: .reference),
            byteLength: values.decode(Int64.self, forKey: .byteLength),
            bytes: values.decode(Data.self, forKey: .bytes)
        )
    }
}

extension ActivityCompletionEvidenceV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case selectedOriginals, associationHistory, sequenceHistory, cards, reviewedMarkupPlans, privacyProjections, outputMedia, omittedEvidenceIDs, omissionLimitations
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            selectedOriginals: values.decode([ContentReferenceV1].self, forKey: .selectedOriginals),
            associationHistory: values.decode([EvidenceAssociationV1].self, forKey: .associationHistory),
            sequenceHistory: values.decode([EvidenceSequenceV1].self, forKey: .sequenceHistory),
            cards: values.decode([EvidenceDetailCardV1].self, forKey: .cards),
            reviewedMarkupPlans: values.decode([EvidenceReviewedMarkupPlanV1].self, forKey: .reviewedMarkupPlans),
            privacyProjections: values.decode([PrivacyTransformReportProjectionV1].self, forKey: .privacyProjections),
            outputMedia: values.decode([ActivityCompletionMediaV1].self, forKey: .outputMedia),
            omittedEvidenceIDs: values.decode([String].self, forKey: .omittedEvidenceIDs),
            omissionLimitations: values.decode([String].self, forKey: .omissionLimitations)
        )
    }
}

extension ActivityCompletionSupplementalV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case accountability, authorityCriterion, relationshipScopes, serviceHistory, evidence, explicitSelection, queries
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            accountability: values.decode(CompletedAccountabilitySnapshotV1.self, forKey: .accountability),
            authorityCriterion: values.decodeIfPresent(CompletedAuthorityCriterionSnapshotV1.self, forKey: .authorityCriterion),
            relationshipScopes: values.decode([ActivityCompletionRelationshipScopeV1].self, forKey: .relationshipScopes),
            serviceHistory: values.decode(ActivityCompletionServiceHistoryV1.self, forKey: .serviceHistory),
            evidence: values.decode(ActivityCompletionEvidenceV1.self, forKey: .evidence),
            explicitSelection: values.decodeIfPresent(ActivityCompletionExplicitSelectionV1.self, forKey: .explicitSelection),
            queries: values.decode([ActivityCompletionQueryV1].self, forKey: .queries)
        )
    }
}

extension ActivityCompletedPredecessorV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case activityFrontier, snapshot, owner, reason
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            activityFrontier: values.decode(ActivitySessionEnvelopeV2.self, forKey: .activityFrontier),
            snapshot: values.decode(CompletedActivitySnapshotV2.self, forKey: .snapshot),
            owner: values.decode(ActivityCompletedPredecessorOwnerV1.self, forKey: .owner),
            reason: values.decode(String.self, forKey: .reason)
        )
    }
}

extension ActivityCompletedPredecessorOwnerV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, fileVersion, outputID, relativePath, fileSHA256
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: values.decode(ActivityCompletedPredecessorOwnerKindV1.self, forKey: .kind),
            fileVersion: values.decode(Int.self, forKey: .fileVersion),
            outputID: values.decode(UUID.self, forKey: .outputID),
            relativePath: values.decode(String.self, forKey: .relativePath),
            fileSHA256: values.decode(String.self, forKey: .fileSHA256)
        )
    }
}

extension ActivityCompletedFileV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case family, formatVersion, outputID, snapshot, capture, installation, punchReview, packageRelease, shopProfile, manifest, supplemental, completedPredecessor, unfinishedAmendmentPredecessor
    }

    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            family: values.decode(String.self, forKey: .family),
            formatVersion: values.decode(Int.self, forKey: .formatVersion),
            outputID: values.decode(UUID.self, forKey: .outputID),
            snapshot: values.decode(CompletedActivitySnapshotV2.self, forKey: .snapshot),
            capture: values.decode(ActivityCompletionCaptureV1.self, forKey: .capture),
            installation: values.decodeIfPresent(ActivityCompletedInstallationV1.self, forKey: .installation),
            punchReview: values.decodeIfPresent(ActivityCompletedPunchV1.self, forKey: .punchReview),
            packageRelease: values.decode(InspectionPackageReleaseV1.self, forKey: .packageRelease),
            shopProfile: values.decode(ShopReportProfileV1.self, forKey: .shopProfile),
            manifest: values.decode(ContractManifestV1.self, forKey: .manifest),
            supplemental: values.decode(ActivityCompletionSupplementalV1.self, forKey: .supplemental),
            completedPredecessor: values.decodeIfPresent(ActivityCompletedPredecessorV1.self, forKey: .completedPredecessor),
            unfinishedAmendmentPredecessor: values.decodeIfPresent(ActivitySessionEnvelopeV2.self, forKey: .unfinishedAmendmentPredecessor)
        )
        try validateIntrinsic()
    }
}

import Foundation

enum IlluminatedSignReportCaptureStatusV1: String, Codable, CaseIterable, Equatable, Sendable {
    case reviewed = "REVIEWED"
    case requiredUnavailableCouldNotVerify = "REQUIRED_UNAVAILABLE_COULD_NOT_VERIFY"
    case optionalNotCaptured = "OPTIONAL_NOT_CAPTURED"
}

/// One closed capture-slot fact. A present item is the exact C05 reviewed
/// sequence item; absence is explicit and can never be mistaken for evidence.
struct IlluminatedSignReportCaptureFactV1: Codable, Equatable, Sendable {
    let slotID: IlluminatedSignCaptureSlotIDV1
    let purposeKey: String
    let required: Bool
    let status: IlluminatedSignReportCaptureStatusV1
    let item: EvidenceSequenceItemV1?
    let evidenceDetailCardID: String?

    fileprivate init(
        requirement: IlluminatedSignCaptureRequirementV1,
        trace: IlluminatedSignCaptureTraceV1?,
        card: EvidenceDetailCardV1?,
        outcome: IlluminatedSignPlaybookOutcomeV1
    ) throws {
        slotID = requirement.slotID
        purposeKey = requirement.purposeKey
        required = requirement.required
        item = trace?.item
        evidenceDetailCardID = card?.cardID
        if trace != nil {
            status = .reviewed
        } else if requirement.required {
            guard outcome == .couldNotVerify else {
                throw IlluminatedSignPlaybookFailureV1.missingCapture
            }
            status = .requiredUnavailableCouldNotVerify
        } else {
            status = .optionalNotCaptured
        }
        try validate()
    }

    func validate() throws {
        guard purposeKey == slotID.rawValue,
              required == (slotID != .workContext) else {
            throw IlluminatedSignPlaybookFailureV1.invalidValue
        }
        switch status {
        case .reviewed:
            guard let item, let evidenceDetailCardID,
                  SnapshotProjectionValidationV1.validID(evidenceDetailCardID),
                  item.ordinal >= 0,
                  KernelCanonicalHashV1.validSHA256(item.associationBinding.associationSHA256),
                  item.associationBinding.resultingEvidenceRevision > 0 else {
                throw IlluminatedSignPlaybookFailureV1.staleEvidence
            }
        case .requiredUnavailableCouldNotVerify:
            guard required, item == nil, evidenceDetailCardID == nil else {
                throw IlluminatedSignPlaybookFailureV1.missingCapture
            }
        case .optionalNotCaptured:
            guard !required, item == nil, evidenceDetailCardID == nil else {
                throw IlluminatedSignPlaybookFailureV1.invalidValue
            }
        }
    }
}

/// Immutable, renderer-neutral report facts for one of the exact seven
/// illuminated-sign playbooks. It is derived only after the coordinator has
/// revalidated the live C36 checkpoint, terminal C05 associations, and current
/// evidence-sequence frontier.
struct IlluminatedSignReportProjectionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let projectionVersion = "ILLUMINATED_SIGN_REPORT_PROJECTION_V1"
    static let requiredNonCertificationDisclaimer =
        "This report records visible conditions from the listed photos and time. It is not an electrical, code, safety, or professional certification."

    let schemaVersion: Int
    let projectionVersion: String

    let workspaceID: WorkspaceID
    let subject: EvidenceAssociationTargetV1
    let snapshotSHA256: String
    let activitySnapshotSHA256: String
    let evidenceSequenceFrontier: EvidenceSequenceReferenceV1

    let packageReleaseID: String
    let packageID: String
    let packageContentVersion: Int
    let packageSHA256: String
    let workflowSHA256: String
    let sourcePackSHA256: String
    let registrySHA256: String
    let manifestSHA256: String
    let manifestVersion: UInt64

    let sectionID: String
    let sectionVersion: UInt64
    let sectionSHA256: String
    let factSHA256: String
    let playbookID: IlluminatedSignPlaybookIDV1
    let stage: IlluminatedSignPlaybookStageV1
    let outcome: IlluminatedSignPlaybookOutcomeV1
    let checkedTime: IlluminatedSignCheckedTimeV1
    let selectedVisibleCondition: IlluminatedSignSelectedVisibleConditionV1?
    let couldNotVerify: IlluminatedSignCouldNotVerifyV1?
    let captures: [IlluminatedSignReportCaptureFactV1]

    let poseReference: AssetPoseEventReferenceV1?
    let pose: C37PoseHistoryProjectionV1?
    let checkpointDraftID: UUID
    let checkpointDraftRevision: UInt64
    let checkpointSHA256: String
    let completionSHA256: String

    let visibleConditionClaim: IlluminatedSignVisibleConditionClaimV1
    let visibleConditionsOnly: Bool
    let comparisonIsProof: Bool
    let diagnosisClaimed: Bool
    let electricalCertification: Bool
    let safetyCertification: Bool
    let nonCertificationDisclaimer: String
    let projectionSHA256: String

    fileprivate init(
        snapshot: CompletedActivityEvidenceSequenceSnapshotV1,
        currentEvidenceSequence: EvidenceSequenceV1,
        section: IlluminatedSignReportSectionV1,
        completion: IlluminatedSignPlaybookCompletionV1,
        registry: IlluminatedSignPlaybookRegistryV1
    ) throws {
        try snapshot.validate()
        try currentEvidenceSequence.validate()
        try registry.validate()
        try completion.validate(registry: registry)
        try section.validate(completion: completion, registry: registry)
        let manifest = try registry.manifest(for: section.playbookID)
        let shippingPack = SignPack.illuminatedSignV1
        let parity = try ShippingIlluminatedSignAdapterV1.parityReceipt()
        let expectedWorkspace = snapshot.activity.payload.workspaceID
        let currentFrontier = try currentEvidenceSequence.frontier
        guard shippingPack.packID == SignPack.illuminatedSignPackageID,
              shippingPack.contentVersion == registry.release.packageContentVersion,
              shippingPack.disclaimer == Self.requiredNonCertificationDisclaimer,
              registry.release.state == .published,
              registry.release.packageID == shippingPack.packID,
              registry.sourcePackSHA256 == parity.sourceCanonicalSHA256,
              parity.exactParity,
              registry.release.packageReleaseID == snapshot.activity.payload.packageReleaseID,
              completion.workspaceID.rawValue.uuidString.lowercased() == expectedWorkspace,
              section.fact.workspaceID == completion.workspaceID,
              section.fact.subject == snapshot.evidenceSequence.target,
              section.fact.subject == currentEvidenceSequence.target,
              section.fact.subject.workspaceID == expectedWorkspace,
              snapshot.evidenceSequence.workspaceID == completion.workspaceID,
              currentEvidenceSequence.workspaceID == completion.workspaceID,
              completion.evidenceSequenceWorkspaceID == completion.workspaceID,
              completion.evidenceSequenceFrontier == currentFrontier,
              manifest.manifestSHA256 == completion.manifestSHA256,
              section.fact == completion.fact,
              SnapshotProjectionValidationV1.instantDate(snapshot.activity.payload.completedAt)
                == section.fact.checkedTime.context.observedAtUTC else {
            throw IlluminatedSignPlaybookFailureV1.releaseMismatch
        }

        let cardsByEvidenceID = Dictionary(uniqueKeysWithValues:
            snapshot.activity.payload.evidenceCards.map { ($0.evidenceID, $0) }
        )
        var captureFacts: [IlluminatedSignReportCaptureFactV1] = []
        for requirement in manifest.captureRequirements {
            let matches = section.fact.captures.filter { $0.slotID == requirement.slotID }
            guard matches.count <= 1 else { throw IlluminatedSignPlaybookFailureV1.staleEvidence }
            let trace = matches.first
            let card = trace.flatMap { cardsByEvidenceID[$0.item.evidenceID] }
            if let trace {
                guard snapshot.evidenceSequence.orderedItems.contains(trace.item),
                      card?.evidenceID == trace.item.evidenceID else {
                    throw IlluminatedSignPlaybookFailureV1.staleEvidence
                }
            }
            captureFacts.append(try .init(
                requirement: requirement, trace: trace, card: card, outcome: section.fact.outcome
            ))
        }
        guard captureFacts.map(\.slotID) == IlluminatedSignCaptureSlotIDV1.canonicalOrder,
              Set(captureFacts.compactMap { $0.item?.evidenceID }).count
                == captureFacts.compactMap({ $0.item?.evidenceID }).count else {
            throw IlluminatedSignPlaybookFailureV1.staleEvidence
        }

        let poseReference = section.fact.poseTrace?.eventReference
        let pose = try section.fact.poseTrace.map { try C37PoseHistoryProjectionV1(event: $0.event) }
        if let poseReference, let pose {
            guard poseReference.workspaceID == completion.workspaceID,
                  poseReference.eventID == pose.eventID,
                  poseReference.axisID.rawValue == pose.axisID,
                  poseReference.revision == pose.revision,
                  poseReference.eventSHA256 == pose.eventSHA256 else {
                throw IlluminatedSignPlaybookFailureV1.invalidPose
            }
        } else if poseReference != nil || pose != nil {
            throw IlluminatedSignPlaybookFailureV1.invalidPose
        }

        schemaVersion = Self.schemaVersion
        projectionVersion = Self.projectionVersion
        workspaceID = completion.workspaceID
        subject = section.fact.subject
        snapshotSHA256 = snapshot.snapshotSHA256
        activitySnapshotSHA256 = snapshot.activity.snapshotSHA256
        evidenceSequenceFrontier = currentFrontier
        packageReleaseID = registry.release.packageReleaseID
        packageID = registry.release.packageID
        packageContentVersion = registry.release.packageContentVersion
        packageSHA256 = registry.release.packageSHA256
        workflowSHA256 = registry.release.workflowSHA256
        sourcePackSHA256 = registry.sourcePackSHA256
        registrySHA256 = registry.registrySHA256
        manifestSHA256 = manifest.manifestSHA256
        manifestVersion = manifest.manifestVersion
        sectionID = section.sectionID
        sectionVersion = section.sectionVersion
        sectionSHA256 = section.sectionSHA256
        factSHA256 = section.fact.factSHA256
        playbookID = section.playbookID
        stage = section.fact.stage
        outcome = section.fact.outcome
        checkedTime = section.fact.checkedTime
        selectedVisibleCondition = section.fact.selectedVisibleCondition
        couldNotVerify = section.fact.couldNotVerify
        captures = captureFacts
        self.poseReference = poseReference
        self.pose = pose
        checkpointDraftID = completion.checkpointDraftID
        checkpointDraftRevision = completion.checkpointDraftRevision
        checkpointSHA256 = completion.checkpointSHA256
        completionSHA256 = completion.completionSHA256
        visibleConditionClaim = section.fact.visibleConditionClaim
        visibleConditionsOnly = section.visibleConditionsOnly
        comparisonIsProof = section.fact.comparisonIsProof
        diagnosisClaimed = section.fact.diagnosisClaimed
        electricalCertification = section.fact.electricalCertification
        safetyCertification = section.fact.safetyCertification
        nonCertificationDisclaimer = Self.requiredNonCertificationDisclaimer
        projectionSHA256 = try IlluminatedSignPlaybookCanonicalCodecV1.sha256(DigestBasis(
            schemaVersion: Self.schemaVersion,
            projectionVersion: Self.projectionVersion,
            workspaceID: completion.workspaceID,
            subject: section.fact.subject,
            snapshotSHA256: snapshot.snapshotSHA256,
            activitySnapshotSHA256: snapshot.activity.snapshotSHA256,
            evidenceSequenceFrontier: currentFrontier,
            packageReleaseID: registry.release.packageReleaseID,
            packageID: registry.release.packageID,
            packageContentVersion: registry.release.packageContentVersion,
            packageSHA256: registry.release.packageSHA256,
            workflowSHA256: registry.release.workflowSHA256,
            sourcePackSHA256: registry.sourcePackSHA256,
            registrySHA256: registry.registrySHA256,
            manifestSHA256: manifest.manifestSHA256,
            manifestVersion: manifest.manifestVersion,
            sectionID: section.sectionID,
            sectionVersion: section.sectionVersion,
            sectionSHA256: section.sectionSHA256,
            factSHA256: section.fact.factSHA256,
            playbookID: section.playbookID,
            stage: section.fact.stage,
            outcome: section.fact.outcome,
            checkedTime: section.fact.checkedTime,
            selectedVisibleCondition: section.fact.selectedVisibleCondition,
            couldNotVerify: section.fact.couldNotVerify,
            captures: captureFacts,
            poseReference: poseReference,
            pose: pose,
            checkpointDraftID: completion.checkpointDraftID,
            checkpointDraftRevision: completion.checkpointDraftRevision,
            checkpointSHA256: completion.checkpointSHA256,
            completionSHA256: completion.completionSHA256,
            visibleConditionClaim: section.fact.visibleConditionClaim,
            visibleConditionsOnly: section.visibleConditionsOnly,
            comparisonIsProof: section.fact.comparisonIsProof,
            diagnosisClaimed: section.fact.diagnosisClaimed,
            electricalCertification: section.fact.electricalCertification,
            safetyCertification: section.fact.safetyCertification,
            nonCertificationDisclaimer: Self.requiredNonCertificationDisclaimer
        ))
        try validateIntrinsic()
    }

    func validateIntrinsic() throws {
        try captures.forEach { try $0.validate() }
        try evidenceSequenceFrontier.validate()
        guard subject == (try EvidenceAssociationTargetV1(
            workspaceID: subject.workspaceID,
            kind: subject.kind,
            targetID: subject.targetID,
            targetRevision: subject.targetRevision
        )) else {
            throw IlluminatedSignPlaybookFailureV1.invalidValue
        }
        _ = try IlluminatedSignCheckedTimeV1(context: checkedTime.context)
        try selectedVisibleCondition?.validate()
        try couldNotVerify?.validate()
        try poseReference?.validate()
        try pose?.validate()
        let reviewed = captures.compactMap(\.item)
        guard schemaVersion == Self.schemaVersion,
              projectionVersion == Self.projectionVersion,
              IlluminatedSignPlaybookIDV1.canonicalOrder.count == IlluminatedSignPlaybookLimitsV1.maximumFacts,
              Set(IlluminatedSignPlaybookIDV1.canonicalOrder).count == IlluminatedSignPlaybookIDV1.allCases.count,
              IlluminatedSignPlaybookIDV1.canonicalOrder.contains(playbookID),
              subject.workspaceID == workspaceID.rawValue.uuidString.lowercased(),
              captures.map(\.slotID) == IlluminatedSignCaptureSlotIDV1.canonicalOrder,
              Set(reviewed.map(\.evidenceID)).count == reviewed.count,
              Set(reviewed.map(\.contentID)).count == reviewed.count,
              Set(reviewed.map { $0.associationBinding.associationEventID }).count == reviewed.count,
              packageID == SignPack.illuminatedSignPackageID,
              packageContentVersion > 0, manifestVersion > 0, sectionVersion > 0,
              [snapshotSHA256, activitySnapshotSHA256, packageReleaseID, packageSHA256,
               workflowSHA256, sourcePackSHA256, registrySHA256, manifestSHA256,
               sectionSHA256, factSHA256, checkpointSHA256, completionSHA256]
                .allSatisfy(KernelCanonicalHashV1.validSHA256),
              checkpointDraftRevision > 0,
              (outcome == .visibleIssue) == (selectedVisibleCondition != nil),
              selectedVisibleCondition.map({ $0.playbookID == playbookID }) ?? true,
              (outcome == .couldNotVerify) == (couldNotVerify != nil),
              !(selectedVisibleCondition != nil && couldNotVerify != nil),
              visibleConditionClaim == .visibleConditionsOnly,
              visibleConditionsOnly,
              !comparisonIsProof, !diagnosisClaimed,
              !electricalCertification, !safetyCertification,
              nonCertificationDisclaimer == Self.requiredNonCertificationDisclaimer,
              (poseReference == nil) == (pose == nil),
              outcome == .couldNotVerify || poseReference != nil,
              projectionSHA256 == (try IlluminatedSignPlaybookCanonicalCodecV1.sha256(digestBasis)) else {
            throw IlluminatedSignPlaybookFailureV1.digestMismatch
        }
        if outcome != .couldNotVerify,
           captures.contains(where: { $0.status == .requiredUnavailableCouldNotVerify }) {
            throw IlluminatedSignPlaybookFailureV1.missingCapture
        }
    }

    private var digestBasis: DigestBasis {
        .init(
            schemaVersion: schemaVersion, projectionVersion: projectionVersion,
            workspaceID: workspaceID, subject: subject,
            snapshotSHA256: snapshotSHA256,
            activitySnapshotSHA256: activitySnapshotSHA256,
            evidenceSequenceFrontier: evidenceSequenceFrontier,
            packageReleaseID: packageReleaseID, packageID: packageID,
            packageContentVersion: packageContentVersion, packageSHA256: packageSHA256,
            workflowSHA256: workflowSHA256, sourcePackSHA256: sourcePackSHA256,
            registrySHA256: registrySHA256, manifestSHA256: manifestSHA256,
            manifestVersion: manifestVersion, sectionID: sectionID,
            sectionVersion: sectionVersion, sectionSHA256: sectionSHA256,
            factSHA256: factSHA256,
            playbookID: playbookID, stage: stage, outcome: outcome,
            checkedTime: checkedTime, selectedVisibleCondition: selectedVisibleCondition,
            couldNotVerify: couldNotVerify, captures: captures,
            poseReference: poseReference, pose: pose,
            checkpointDraftID: checkpointDraftID,
            checkpointDraftRevision: checkpointDraftRevision,
            checkpointSHA256: checkpointSHA256, completionSHA256: completionSHA256,
            visibleConditionClaim: visibleConditionClaim,
            visibleConditionsOnly: visibleConditionsOnly,
            comparisonIsProof: comparisonIsProof, diagnosisClaimed: diagnosisClaimed,
            electricalCertification: electricalCertification,
            safetyCertification: safetyCertification,
            nonCertificationDisclaimer: nonCertificationDisclaimer
        )
    }

    private struct DigestBasis: Codable {
        let schemaVersion: Int
        let projectionVersion: String
        let workspaceID: WorkspaceID
        let subject: EvidenceAssociationTargetV1
        let snapshotSHA256: String
        let activitySnapshotSHA256: String
        let evidenceSequenceFrontier: EvidenceSequenceReferenceV1
        let packageReleaseID: String
        let packageID: String
        let packageContentVersion: Int
        let packageSHA256: String
        let workflowSHA256: String
        let sourcePackSHA256: String
        let registrySHA256: String
        let manifestSHA256: String
        let manifestVersion: UInt64
        let sectionID: String
        let sectionVersion: UInt64
        let sectionSHA256: String
        let factSHA256: String
        let playbookID: IlluminatedSignPlaybookIDV1
        let stage: IlluminatedSignPlaybookStageV1
        let outcome: IlluminatedSignPlaybookOutcomeV1
        let checkedTime: IlluminatedSignCheckedTimeV1
        let selectedVisibleCondition: IlluminatedSignSelectedVisibleConditionV1?
        let couldNotVerify: IlluminatedSignCouldNotVerifyV1?
        let captures: [IlluminatedSignReportCaptureFactV1]
        let poseReference: AssetPoseEventReferenceV1?
        let pose: C37PoseHistoryProjectionV1?
        let checkpointDraftID: UUID
        let checkpointDraftRevision: UInt64
        let checkpointSHA256: String
        let completionSHA256: String
        let visibleConditionClaim: IlluminatedSignVisibleConditionClaimV1
        let visibleConditionsOnly: Bool
        let comparisonIsProof: Bool
        let diagnosisClaimed: Bool
        let electricalCertification: Bool
        let safetyCertification: Bool
        let nonCertificationDisclaimer: String
    }
}

enum IlluminatedSignReportProjectorV1 {
    static func project(
        coordinator: IlluminatedSignPlaybookCoordinatorV1,
        snapshot: CompletedActivityEvidenceSequenceSnapshotV1,
        completion: IlluminatedSignPlaybookCompletionV1,
        checkpoint: FieldDraftCheckpointV1,
        predecessor: FieldDraftCheckpointV1? = nil,
        currentAssociationEvents: [EvidenceAssociationV1],
        currentEvidenceSequence: EvidenceSequenceV1,
        evidenceSequenceHistory: [EvidenceSequenceV1],
        poseEventHistory: [AssetPoseEventV1]
    ) throws -> IlluminatedSignReportProjectionV1 {
        try snapshot.validate()
        try snapshot.validateSourceFrontier(currentAssociationEvents)
        try currentEvidenceSequence.validate()
        try completion.validate(registry: coordinator.registry)
        guard evidenceSequenceHistory.count <= IlluminatedSignPlaybookLimitsV1.maximumHistoryEvents,
              snapshot.evidenceSequence.target == completion.fact.subject,
              currentEvidenceSequence.target == completion.fact.subject,
              snapshot.evidenceSequence.workspaceID == completion.workspaceID,
              currentEvidenceSequence.workspaceID == completion.workspaceID,
              completion.evidenceSequenceFrontier == (try currentEvidenceSequence.frontier) else {
            throw IlluminatedSignPlaybookFailureV1.staleEvidence
        }
        let section = try coordinator.reportSection(
            for: completion,
            checkpoint: checkpoint,
            predecessor: predecessor,
            associationEvents: currentAssociationEvents,
            evidenceSequence: currentEvidenceSequence,
            evidenceSequenceHistory: evidenceSequenceHistory,
            poseEventHistory: poseEventHistory
        )
        return try IlluminatedSignReportProjectionV1(
            snapshot: snapshot,
            currentEvidenceSequence: currentEvidenceSequence,
            section: section,
            completion: completion,
            registry: coordinator.registry
        )
    }
}

enum IlluminatedSignReportProjectionCanonicalCodecV1 {
    static func encode(_ projection: IlluminatedSignReportProjectionV1) throws -> Data {
        try projection.validateIntrinsic()
        return try IlluminatedSignPlaybookCanonicalCodecV1.encode(projection)
    }

    static func decode(_ data: Data) throws -> IlluminatedSignReportProjectionV1 {
        guard !data.isEmpty,
              data.count <= IlluminatedSignPlaybookLimitsV1.maximumCanonicalBytes else {
            throw IlluminatedSignPlaybookFailureV1.limitExceeded
        }
        let value = try JSONDecoder().decode(IlluminatedSignReportProjectionV1.self, from: data)
        try value.validateIntrinsic()
        guard try encode(value) == data else {
            throw IlluminatedSignPlaybookFailureV1.digestMismatch
        }
        return value
    }
}

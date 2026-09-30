import Foundation
import XCTest
@testable import FieldEvidenceApp

/// Constructed domain values exercise intrinsic consistency only. These are not
/// authenticated row captures, catalog releases, admission receipts or runtime
/// production evidence. The genuine published V1 manifest below tests frozen
/// value equality; it does not claim to describe a production completed V2 file.
@MainActor
final class V23ActivityCompletedFileTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)

    private func id(_ slot: Int) -> UUID {
        UUID(uuidString: String(format: "CE470000-0000-4000-8000-%012d", slot))!
    }

    private func mutation(_ slot: Int) throws -> MutationIDV1 {
        try MutationIDV1(rawValue: id(slot))
    }

    private func canonical<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func hash<T: Encodable>(_ value: T) throws -> String {
        KernelCanonicalHashV1.sha256(try canonical(value))
    }

    private func textInstant(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func resource(_ name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/V23/Activities")
                ?? bundle.url(forResource: name, withExtension: "json")
        )
        return try Data(contentsOf: url)
    }

    private func actor(_ workspace: WorkspaceID) throws -> ActorSnapshotV1 {
        let local = try LocalActorReferenceV1(actorReferenceID: id(80), workspaceID: workspace, displayName: "Constructed value recorder")
        return try ActorSnapshotV1(snapshotID: id(81), workspaceID: workspace, actor: local,
            responsibility: .recordedBy, displayNameAtTime: local.displayName, capturedAt: instant)
    }

    private func fixture(activitySlot: Int = 2, amendment: ActivityAmendmentLinkV1? = nil,
                         workspaceOverride: WorkspaceID? = nil) throws -> ActivityCompletedFileV1 {
        let workspace = workspaceOverride ?? WorkspaceID(rawValue: id(1))
        let activityID = id(activitySlot)
        let assetID = id(3)
        let outputID = id(activitySlot + 1_000)
        let recorder = try actor(workspace)
        let manifestBytes = try resource("V23P03C06LegacyContractManifestV1")
        let manifest = try JSONDecoder().decode(ContractManifestV1.self, from: manifestBytes)
        let registry = manifest.reportSectionRegistry
        let layout = try ReportLayoutProfileV1(
            profileID: "constructed-layout", profileRelease: 1, audience: .internalUse,
            detail: .complete, sectionIDs: registry.sections.map(\.sectionID), mediaLayout: .standardGrid,
            orientation: .portrait, localeIdentifier: "en_US", unitsProfileID: "constructed-units",
            displayProfileID: "constructed-display", registry: registry
        )
        let export = try ExportProfileV1(
            exportProfileID: "constructed-export", exportProfileRelease: 1,
            formats: [.formulaSafeCSV, .openJSON, .pdf, .structuredText], packaging: .combined,
            privacyTransformID: "constructed-privacy", maximumMediaItems: 16, maximumArchiveBytes: 8_388_608
        )
        let policy = try AudiencePrivacyPolicyV1(policyID: "constructed-policy", policyVersion: 1,
            audience: .internalUse, prohibitedCanaries: ["PRIVATE-CANARY"])
        let detail = try EvidenceDetailCardProfileV1(
            profileID: "constructed-detail", profileRelease: 1, audience: .internalUse,
            outputScopeID: "constructed-scope", privacyTransformID: export.privacyTransformID,
            privacyTransformVersion: 1, markupProfileID: "constructed-markup", markupProfileVersion: 1,
            localeIdentifier: layout.localeIdentifier, displayProfileID: layout.displayProfileID,
            rendererVersion: "constructed-renderer", audiencePrivacyPolicy: policy,
            includedFieldIDs: ["recorded-note"],
            limitationsText: "Evidence detail does not verify capture time, location, or person."
        )
        let profile = try ShopReportProfileV1(
            workspaceID: workspace, profileID: id(4), revision: 1, mutationID: mutation(5), activation: .on,
            brand: ShopReportBrandV1(shopDisplayName: "Constructed fixture shop"),
            reportLayoutProfile: layout, exportProfile: export, evidenceDetailProfile: detail,
            sectionRegistry: registry, rendererVersion: "constructed-renderer", packaging: .combinedArchive,
            recordedBy: recorder, recordedAt: instant
        )
        let package = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
        let workflow = try WorkflowDefinitionV1(
            workflowID: "constructed-completed-workflow", entryNodeID: "section", declaredFieldIDs: [],
            nodes: [
                WorkflowNodeV1(nodeID: "section", kind: .section, localizationKey: "section", outgoingNodeIDs: ["terminal"]),
                WorkflowNodeV1(nodeID: "terminal", kind: .terminal, localizationKey: "terminal", outgoingNodeIDs: [])
            ]
        )
        let draft = try InspectionPackageReleaseV1.makeDraft(package: package, workflow: workflow)
        let tested = try InspectionPackageReleasePublisherV1.test(draft)
        let packageRelease = try InspectionPackageReleasePublisherV1.publish(tested).release
        let scope = try PunchReviewScopeItemV1(scopeItemID: "constructed-scope-item", ordinal: 0, title: "Recorded inspection scope")
        let release = try PunchReviewWorkflowDefinitionReleaseV1(
            releaseID: id(7), workspaceID: workspace, scope: [scope],
            readinessPolicy: PunchReviewReadinessPolicyV1(requiredFacets: [.access]),
            revision: 1, mutationID: mutation(8)
        )
        let fallback = try NoPlanFallbackV1(limitation: "No plan selected for this constructed scope.")
        let basis = try PunchReviewBasisSnapshotV1(
            basisID: id(900 + activitySlot), workspaceID: workspace, activityID: activityID, subjectID: assetID,
            workflowReleaseReference: ActivityWorkflowReleaseReferenceV2(punchReview: release, package: package),
            source: .noPlan(fallback), scopeLimitation: "Only the recorded scope and time.",
            capturedAt: instant, revision: 1, mutationID: mutation(10)
        )
        let envelope = try ActivitySessionEnvelopeV2(
            activityID: activityID, workspaceID: workspace, kind: .punchReview,
            state: .readyForReview, reviewState: .pending, subjectID: assetID,
            title: "Constructed intrinsic fixture", readiness: [], amendment: amendment,
            currentBasisReference: .punchReview(PunchReviewBasisReferenceV1(basis)),
            startedAt: instant, revision: 42, mutationID: mutation(11),
            predecessorEnvelopeSHA256: String(repeating: "a", count: 64)
        )
        let pairs: [(ActivityStateV2, ActivityStateV2)] = [
            (.draft, .preflightRequired), (.preflightRequired, .ready), (.ready, .inProgress),
            (.inProgress, .fieldComplete), (.fieldComplete, .readyForReview)
        ]
        // Transitions carry the successor activity revision. Intervening
        // same-state mutations produce genuine gaps without a transition row.
        let transitionRevisions: [UInt64] = [2, 7, 11, 29, 40]
        var transitions: [ActivityStateTransitionV2] = []
        for (index, pair) in pairs.enumerated() {
            let transition = try ActivityStateTransitionV2(
                transitionID: id(100 + index), workspaceID: workspace, activityID: activityID,
                kind: .punchReview, fromState: pair.0, toState: pair.1, actor: recorder,
                occurredAt: instant.addingTimeInterval(Double(index)), revision: transitionRevisions[index],
                mutationID: mutation(200 + index)
            )
            transitions.append(transition)
        }
        let completion = try ActivityStateTransitionV2(
            transitionID: id(106), workspaceID: workspace, activityID: activityID, kind: .punchReview,
            fromState: .readyForReview, toState: .finalized, actor: recorder,
            occurredAt: instant.addingTimeInterval(5), revision: 43, mutationID: mutation(206)
        )
        let identity = try WorkspaceEntityIdentityV1(kind: .activitySessionEnvelope, id: activityID)
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: workspace, generationID: id(20), writerInstanceID: id(21), workspaceRevision: 9_001,
            entityRevisions: [WorkspaceEntityRevisionV1(identity: identity, revision: 42)]
        )
        let capture = ActivityCompletionCaptureV1(
            version: 1, source: try MutationPortableExpectedRevisionV1(expected), predecessor: envelope,
            transitionHistory: transitions, completionTransition: completion,
            resultingActivityRevision: 43, capturedAt: instant.addingTimeInterval(5), generatedAt: instant.addingTimeInterval(6)
        )
        let decision = try PunchItemProjectionV1(scopeItemID: scope.scopeItemID, disposition: .reviewedNoItemRecorded)
        let closeout = try PunchReviewCloseoutV1(
            completion: .completedNoPunchItemsRecordedInScope, basisSHA256: basis.basisSHA256,
            scope: [decision], scopeAndTimeLimitation: basis.scopeLimitation
        )
        let punch = ActivityCompletedPunchV1(
            sourceRelease: release, release: release, basisHistory: [basis], scopeDecisions: [decision],
            closeout: closeout,
            planCapability: ActivityCompletedPunchPlanV1(disposition: .manualFallback, planReference: nil,
                noPlanFallback: fallback, externalReference: nil, availabilityReceipt: nil),
            findings: [], sourceEnvelopes: [], correctiveActionEvents: [], verifiedRechecks: [], installation: nil
        )
        let path = try LocationPathSnapshotV1(siteID: id(30), siteDisplay: "Constructed site", nodes: [])
        let placement = try AssetPlacementEventV1(
            id: id(31), workspaceID: workspace, assetID: assetID, siteID: path.siteID,
            locationNodeID: nil, predecessorEventID: nil, source: .manual,
            physicalEpisodeID: PhysicalPlacementEpisodeIDV1(rawValue: id(32)), continuity: .samePhysicalInstallation,
            pathSnapshot: path, mutationID: mutation(33), occurredAt: instant
        )
        let location = try CompletedLocationCompositionSnapshotV1.build(
            workspaceID: workspace, assetID: assetID, currentLocationPath: path,
            currentPlacementByAssetID: [assetID: placement], activeCompositionEdges: [], frozenAtRevision: 9_001
        )
        let snapshotID = "legal-non-uuid-snapshot-id-\(activitySlot)"
        let binding = try FinalizedReportProfileBindingV1(
            workspaceID: workspace.rawValue.uuidString.lowercased(), snapshotID: snapshotID,
            outputScopeID: detail.outputScopeID, reportProfileID: layout.profileID,
            reportProfileRelease: layout.profileRelease, reportProfileSHA256: hash(layout),
            exportProfileID: export.exportProfileID, exportProfileRelease: export.exportProfileRelease,
            exportProfileSHA256: hash(export), sectionRegistryID: registry.registryID,
            sectionRegistryVersion: registry.registryVersion, sectionRegistrySHA256: hash(registry),
            contractManifestID: manifest.manifestID, contractManifestVersion: manifest.manifestVersion,
            contractManifestSHA256: hash(manifest), sectionIDs: layout.sectionIDs, audience: layout.audience,
            detail: layout.detail, privacyTransformID: export.privacyTransformID,
            localeIdentifier: layout.localeIdentifier, unitsProfileID: layout.unitsProfileID,
            displayProfileID: layout.displayProfileID, orientation: layout.orientation,
            mediaLayout: layout.mediaLayout, rendererVersion: profile.rendererVersion,
            projectionVersion: "constructed-projection"
        )
        let payload = try CompletedActivitySnapshotPayloadV1(
            workspaceID: workspace.rawValue.uuidString.lowercased(), snapshotID: snapshotID, snapshotRevision: 1,
            sourceActivityID: activityID.uuidString.lowercased(), sourceRevision: 43,
            reportID: outputID.uuidString.lowercased(), packageReleaseID: packageRelease.packageReleaseID,
            generatedAt: textInstant(capture.generatedAt), completedAt: textInstant(capture.finalizedAt),
            supersedesSnapshotID: nil, supersededSnapshotSHA256: nil, amendmentReason: nil,
            profileBinding: binding, serviceFacts: [], evidenceCards: [], limitations: [basis.scopeLimitation]
        )
        let snapshot = try CompletedActivitySnapshotV2.freezeOriginal(
            CompletedActivitySnapshotPayloadV2(activity: payload, assetID: assetID, locationComposition: location)
        )
        let accountability = try CompletedAccountabilitySnapshotV1(workspaceID: workspace, actors: [recorder])
        let service = ActivityCompletionServiceHistoryV1(records: [], dispositions: [], workLinks: [], sourceWorkEnvelopes: [], factSources: [])
        let evidence = ActivityCompletionEvidenceV1(selectedOriginals: [], associationHistory: [], sequenceHistory: [],
            cards: [], reviewedMarkupPlans: [], privacyProjections: [], outputMedia: [], omittedEvidenceIDs: [], omissionLimitations: [])
        let noAuthority: CompletedAuthorityCriterionSnapshotV1? = nil
        let noSelection: ActivityCompletionExplicitSelectionV1? = nil
        let relationships: [ActivityCompletionRelationshipScopeV1] = []
        let values: [(ActivityCompletionSupplementalFamilyV1, String)] = [
            (.authorityCriterion, try hash(noAuthority)), (.functionalRelationships, try hash(relationships)),
            (.serviceHistory, try hash(service)), (.evidence, try hash(evidence)), (.optionalAccountability, try hash(noSelection))
        ]
        let queries = values.map { pair in
            ActivityCompletionQueryV1(family: pair.0, disposition: .checkedNoApplicableSource,
                sourceWorkspaceRevision: 9_001, rootIdentities: [], capturedValueSHA256: pair.1)
        }
        let supplemental = ActivityCompletionSupplementalV1(accountability: accountability, authorityCriterion: nil,
            relationshipScopes: [], serviceHistory: service, evidence: evidence, explicitSelection: nil, queries: queries)
        return ActivityCompletedFileV1(
            family: ActivityCompletedFileV1.currentFamily, formatVersion: 1, outputID: outputID,
            snapshot: snapshot, capture: capture, installation: nil, punchReview: punch,
            packageRelease: packageRelease, shopProfile: profile, manifest: manifest, supplemental: supplemental,
            completedPredecessor: nil, unfinishedAmendmentPredecessor: nil
        )
    }

    private func changed(_ value: ActivityCompletedFileV1, _ mutate: (inout [String: Any]) throws -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: value.canonicalData()) as? [String: Any])
        try mutate(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private func finalizedEnvelope(_ file: ActivityCompletedFileV1, closedFile: Bool) throws -> ActivitySessionEnvelopeV2 {
        let predecessor = file.capture.predecessor
        let closeout = try XCTUnwrap(file.punchReview?.closeout)
        let typedReference = try CompletedActivitySnapshotV2CompatibilityReferenceV1(file.snapshot, activityCloseoutSHA256: closeout.closeoutSHA256)
        let fileReference: ActivityCompletedFileReferenceV1?
        if closedFile { fileReference = try file.reference() }
        else { fileReference = nil }
        return try ActivitySessionEnvelopeV2(
            activityID: predecessor.activityID, workspaceID: predecessor.workspaceID, kind: predecessor.kind,
            state: .finalized, reviewState: .acceptedRecordedFacts, subjectID: predecessor.subjectID,
            title: predecessor.title, readiness: predecessor.readiness, readinessPolicy: predecessor.readinessPolicy,
            variations: predecessor.variations, amendment: predecessor.amendment,
            currentBasisReference: predecessor.currentBasisReference, punchReviewCloseout: closeout,
            completedSnapshotReference: typedReference, startedAt: predecessor.startedAt,
            finalizedAt: file.capture.finalizedAt, revision: file.capture.resultingActivityRevision,
            mutationID: file.capture.mutationID, predecessorEnvelopeSHA256: predecessor.envelopeSHA256,
            schemaVersion: closedFile ? 3 : 2, completedFileReference: fileReference
        )
    }

    private func withPredecessor(_ file: ActivityCompletedFileV1,
                                 completed: ActivityCompletedPredecessorV1? = nil,
                                 unfinished: ActivitySessionEnvelopeV2? = nil) -> ActivityCompletedFileV1 {
        ActivityCompletedFileV1(family: file.family, formatVersion: file.formatVersion, outputID: file.outputID,
            snapshot: file.snapshot, capture: file.capture, installation: file.installation, punchReview: file.punchReview,
            packageRelease: file.packageRelease, shopProfile: file.shopProfile, manifest: file.manifest,
            supplemental: file.supplemental, completedPredecessor: completed, unfinishedAmendmentPredecessor: unfinished)
    }

    private func reviewedEvidenceFixture() throws -> (ActivityCompletedFileV1, ActivityCompletionEvidenceV1) {
        // Reuse the existing constructed C20 fixture, including real byte hashes;
        // adapting its policy audience is value-test setup, not source admission.
        let source = try C20PrivacyTransformTestSupport.makeFixture()
        let file = try fixture(workspaceOverride: source.workspace)
        let oldPolicy = source.policy
        let policy = try PrivacyTransformPolicyV1(policyID: oldPolicy.policyID, workspaceID: source.workspace,
            purpose: "Constructed internal review", audience: .internalReview,
            allowedTransformKinds: oldPolicy.allowedTransformKinds, allowedReasons: oldPolicy.allowedReasons,
            maximumAgeSeconds: oldPolicy.maximumAgeSeconds, effectiveAt: oldPolicy.effectiveAt,
            mutationID: oldPolicy.mutationID)
        let manifest = try source.manifest.rebound(to: source.workspace, policy: policy)
        let review = try source.approvedReview.rebound(to: source.workspace, manifest: manifest, policy: policy)
        let plan = try EvidenceReviewedMarkupPlanV1(markupID: "constructed-reviewed-markup", workspaceID: source.workspace,
            source: source.original, privacyPolicy: policy, privacyManifest: manifest, privacyReview: review,
            orderedAnnotations: [EvidenceAnnotationV1(annotationID: "constructed-note", action: .add, text: "Reviewed redaction")],
            orderedReferenceLabels: ["Reviewed derivative"])
        let profile = file.shopProfile.evidenceDetailProfile
        let output = try OutputScopedContentReferenceV1(outputScopeID: profile.outputScopeID, ordinal: 0, reference: source.derivative)
        let field = try EvidenceDetailFieldV1(fieldID: "recorded-note", label: "Note", value: "Recorded field note", sensitivity: .audienceSafe)
        let card = try EvidenceDetailComposerV1.compose(cardID: "constructed-card", workspaceID: source.original.workspaceID,
            evidenceID: source.original.contentID, fields: [field], profile: profile, markupID: plan.markupID,
            annotations: plan.reviewedMarkup.orderedAnnotations, referenceLabels: plan.reviewedMarkup.orderedReferenceLabels,
            outputReferences: [output])
        // This constructed output explicitly declares redaction. Production
        // capture must obtain this decision from the actual output context.
        let projection = try PrivacyTransformReportProjectionV1(manifest: manifest, review: review, policy: policy,
            audience: profile.audience, currentSourceRevision: manifest.sourceRevision,
            currentSourceSHA256: manifest.sourceSHA256, redactionDeclared: true, now: file.capture.generatedAt)
        let target = try EvidenceAssociationTargetV1(workspaceID: source.original.workspaceID, kind: .workRecord,
            targetID: file.capture.predecessor.activityID.uuidString.lowercased(), targetRevision: 42)
        let association = try EvidenceAssociationV1(associationEventID: "constructed-association", workspaceID: source.original.workspaceID,
            evidenceID: source.original.contentID, expectedEvidenceRevision: 0, resultingEvidenceRevision: 1,
            mutationID: "constructed-association-mutation", action: .assigned, contentID: source.original.contentID,
            target: target, actorID: file.capture.completionTransition.actor.actor.actorReferenceID.uuidString.lowercased(),
            reason: "Selected for constructed value test", effectiveAt: textInstant(instant))
        let media = ActivityCompletionMediaV1(reference: output, byteLength: Int64(source.derivativeBytes.count), bytes: source.derivativeBytes)
        let evidence = ActivityCompletionEvidenceV1(selectedOriginals: [source.original], associationHistory: [association],
            sequenceHistory: [], cards: [card], reviewedMarkupPlans: [plan], privacyProjections: [projection],
            outputMedia: [media], omittedEvidenceIDs: [], omissionLimitations: [])
        return (file, evidence)
    }

    private func placementSourceFixture() throws -> (ActivityCompletionPlacementSourcesV1, [InstallationPlacementReferenceV2]) {
        let workspace = WorkspaceID(rawValue: id(1))
        let asset = id(3)
        let path = try LocationPathSnapshotV1(siteID: id(30), siteDisplay: "Constructed pose site", nodes: [])
        let episode = try PhysicalPlacementEpisodeIDV1(rawValue: id(700))
        let firstPlacement = try AssetPlacementEventV1(id: id(701), workspaceID: workspace, assetID: asset,
            siteID: path.siteID, locationNodeID: nil, predecessorEventID: nil, source: .manual,
            physicalEpisodeID: episode, continuity: .samePhysicalInstallation, pathSnapshot: path,
            mutationID: mutation(702), occurredAt: instant)
        let secondPlacement = try AssetPlacementEventV1(id: id(703), workspaceID: workspace, assetID: asset,
            siteID: path.siteID, locationNodeID: nil, predecessorEventID: firstPlacement.id, source: .manual,
            physicalEpisodeID: episode, continuity: .samePhysicalInstallation, pathSnapshot: path,
            mutationID: mutation(704), occurredAt: instant.addingTimeInterval(1))
        let descriptor = try PoseAxisDescriptorV1(axisID: PoseAxisID(rawValue: "constructed-axis"),
            localizedLabelKey: "constructed.axis", semanticRole: .assetForwardAxis, requiredComponents: .azimuthOnly,
            observationRequirement: .requiredForCompletion, applicability: .applicable)
        let pose = try PlacementPoseV1(disposition: .notObserved, referenceFrame: .unknown,
            notObservedReason: .sourceUnavailable, descriptor: descriptor)
        let local = try LocalActorReferenceV1(actorReferenceID: id(705), workspaceID: workspace, displayName: "Constructed observer")
        let observer = try ActorSnapshotV1(snapshotID: id(706), workspaceID: workspace, actor: local,
            responsibility: .observedBy, displayNameAtTime: local.displayName, capturedAt: instant)
        let firstPose = try AssetPoseEventV1(eventID: id(707), workspaceID: workspace, assetID: asset,
            axisDescriptor: descriptor, placementEpisodeID: episode, placementEventID: firstPlacement.id,
            locationPathSnapshot: path, pose: pose, source: .manual, rootObservationEventID: id(707),
            rootObservedAt: instant, predecessor: nil, revision: 1, mutationID: mutation(708), recordedBy: observer,
            occurredAt: instant, recordedAt: instant)
        let secondPose = try AssetPoseEventV1(eventID: id(709), workspaceID: workspace, assetID: asset,
            axisDescriptor: descriptor, placementEpisodeID: episode, placementEventID: secondPlacement.id,
            locationPathSnapshot: path, pose: pose, source: .placementCarryForward,
            rootObservationEventID: firstPose.rootObservationEventID, rootObservedAt: firstPose.rootObservedAt,
            predecessor: firstPose, revision: 2, mutationID: mutation(710), recordedBy: actor(workspace),
            occurredAt: instant.addingTimeInterval(1), recordedAt: instant.addingTimeInterval(1))
        let values = ActivityCompletionPlacementSourcesV1(planDocuments: [], planRevisions: [], planPlacements: [],
            poseEvents: [firstPose, secondPose], placementHistory: [firstPlacement, secondPlacement])
        return (values, [.pose(secondPose.reference)])
    }

    func testClosedCompletedFileRoundTripPreservesRealNestedV2AndSeparateHashes() throws {
        let file = try fixture()
        let bytes = try file.canonicalData()
        let reference = try file.reference()
        XCTAssertEqual(file.family, "ACTIVITY_COMPLETED_FILE_V1")
        XCTAssertEqual(file.relativePath, "snapshots/ce470000-0000-4000-8000-000000001002.json")
        XCTAssertEqual(reference.fileSHA256, KernelCanonicalHashV1.sha256(bytes))
        XCTAssertEqual(file.snapshot.snapshotSHA256, KernelCanonicalHashV1.sha256(
            try CompletedActivitySnapshotCanonicalCodecV2.encodePayload(file.snapshot.payload)))
        XCTAssertNotEqual(file.snapshot.snapshotSHA256, reference.fileSHA256)
        XCTAssertEqual(try ActivityCompletedFileV1.decodeCanonical(bytes, reference: reference), file)
        XCTAssertEqual(file.snapshot.payload.activity.snapshotID, "legal-non-uuid-snapshot-id-2")
        XCTAssertEqual(file.snapshot.payload.activity.reportID, file.outputID.uuidString.lowercased())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertNotNil(object["snapshot"] as? [String: Any])
        XCTAssertNil(object["fileSHA256"])
        XCTAssertNil(object["finalEnvelope"])
        XCTAssertNil(object["receiptSHA256"])
    }

    func testCaptureUsesActivityRevisionsAndKeepsWorkspaceFrontierPortable() throws {
        let capture = try fixture().capture
        try capture.validateIntrinsic()
        XCTAssertEqual(capture.predecessor.revision, 42)
        XCTAssertEqual(capture.resultingActivityRevision, 43)
        XCTAssertEqual(capture.transitionHistory.map(\.revision), [2, 7, 11, 29, 40])
        XCTAssertEqual(capture.completionTransition.revision, capture.resultingActivityRevision)
        XCTAssertEqual(capture.source.workspaceRevision, 9_001)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: canonical(capture)) as? [String: Any])
        let source = try XCTUnwrap(object["source"] as? [String: Any])
        XCTAssertNil(source["writerInstanceID"])
        XCTAssertEqual(capture, try JSONDecoder().decode(ActivityCompletionCaptureV1.self, from: canonical(capture)))
    }

    func testCaptureRejectsStaleActivityRevisionAndInvalidTransitionOrderingOrStateChain() throws {
        let file = try fixture()
        let replacements: [UInt64] = [6, 42, 9_001, UInt64.max]
        for replacement in replacements {
            let bad = ActivityCompletionCaptureV1(version: 1, source: file.capture.source,
                predecessor: file.capture.predecessor, transitionHistory: file.capture.transitionHistory,
                completionTransition: file.capture.completionTransition, resultingActivityRevision: replacement,
                capturedAt: file.capture.capturedAt, generatedAt: file.capture.generatedAt)
            XCTAssertThrowsError(try bad.validateIntrinsic())
        }
        let missing = ActivityCompletionCaptureV1(version: 1, source: file.capture.source,
            predecessor: file.capture.predecessor, transitionHistory: Array(file.capture.transitionHistory.dropFirst()),
            completionTransition: file.capture.completionTransition, resultingActivityRevision: 43,
            capturedAt: file.capture.capturedAt, generatedAt: file.capture.generatedAt)
        XCTAssertThrowsError(try missing.validateIntrinsic())

        func replacingRevision(_ transition: ActivityStateTransitionV2, with revision: UInt64) throws -> ActivityStateTransitionV2 {
            try ActivityStateTransitionV2(transitionID: transition.transitionID, workspaceID: transition.workspaceID,
                activityID: transition.activityID, kind: transition.kind, fromState: transition.fromState,
                toState: transition.toState, reason: transition.reason, actor: transition.actor,
                occurredAt: transition.occurredAt, revision: revision, mutationID: transition.mutationID)
        }
        let invalidRevisions: [(Int, UInt64)] = [(0, 1), (1, 2), (2, 6), (4, 43)]
        for (index, revision) in invalidRevisions {
            var history = file.capture.transitionHistory
            history[index] = try replacingRevision(history[index], with: revision)
            let invalid = ActivityCompletionCaptureV1(version: 1, source: file.capture.source,
                predecessor: file.capture.predecessor, transitionHistory: history,
                completionTransition: file.capture.completionTransition, resultingActivityRevision: 43,
                capturedAt: file.capture.capturedAt, generatedAt: file.capture.generatedAt)
            XCTAssertThrowsError(try invalid.validateIntrinsic())
        }
        let invalidCompletionRevisions: [UInt64] = [6, 44]
        for revision in invalidCompletionRevisions {
            let transition = try replacingRevision(file.capture.completionTransition, with: revision)
            let invalidCompletion = ActivityCompletionCaptureV1(version: 1, source: file.capture.source,
                predecessor: file.capture.predecessor, transitionHistory: file.capture.transitionHistory,
                completionTransition: transition, resultingActivityRevision: 43,
                capturedAt: file.capture.capturedAt, generatedAt: file.capture.generatedAt)
            XCTAssertThrowsError(try invalidCompletion.validateIntrinsic())
        }
    }

    func testCaptureRejectsOverflowAndNonfiniteOrResampledTime() throws {
        let file = try fixture()
        let prior = file.capture.predecessor
        let exhausted = try ActivitySessionEnvelopeV2(
            activityID: prior.activityID, workspaceID: prior.workspaceID, kind: prior.kind,
            state: prior.state, reviewState: prior.reviewState, subjectID: prior.subjectID,
            title: prior.title, readiness: prior.readiness, currentBasisReference: prior.currentBasisReference,
            startedAt: prior.startedAt, revision: UInt64.max, mutationID: prior.mutationID,
            predecessorEnvelopeSHA256: prior.predecessorEnvelopeSHA256
        )
        let identity = try WorkspaceEntityIdentityV1(kind: .activitySessionEnvelope, id: prior.activityID)
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: prior.workspaceID, generationID: file.capture.source.generationID, writerInstanceID: id(21),
            workspaceRevision: 9_001, entityRevisions: [WorkspaceEntityRevisionV1(identity: identity, revision: UInt64.max)]
        )
        let overflow = ActivityCompletionCaptureV1(version: 1, source: try MutationPortableExpectedRevisionV1(expected),
            predecessor: exhausted, transitionHistory: file.capture.transitionHistory,
            completionTransition: file.capture.completionTransition, resultingActivityRevision: 0,
            capturedAt: file.capture.capturedAt, generatedAt: file.capture.generatedAt)
        XCTAssertThrowsError(try overflow.validateIntrinsic())
        let nonfinite = ActivityCompletionCaptureV1(version: 1, source: file.capture.source,
            predecessor: prior, transitionHistory: file.capture.transitionHistory,
            completionTransition: file.capture.completionTransition, resultingActivityRevision: 43,
            capturedAt: file.capture.capturedAt, generatedAt: Date(timeIntervalSinceReferenceDate: .infinity))
        XCTAssertThrowsError(try nonfinite.validateIntrinsic())
        let resampled = try changed(file) { object in
            var capture = try XCTUnwrap(object["capture"] as? [String: Any])
            capture["generatedAt"] = file.capture.generatedAt.addingTimeInterval(1).timeIntervalSinceReferenceDate
            object["capture"] = capture
        }
        XCTAssertThrowsError(try ActivityCompletedFileV1.decodeCanonical(resampled))
    }

    func testFileRejectsWrongFamilyVersionOutputAndUnknownFields() throws {
        let file = try fixture()
        let changes: [(String, Any)] = [
            ("family", "ACTIVITY_COMPLETED_FILE"), ("formatVersion", 2),
            ("outputID", "00000000-0000-0000-0000-000000000000"), ("unexpected", true)
        ]
        for change in changes {
            let bytes = try changed(file) { $0[change.0] = change.1 }
            XCTAssertThrowsError(try ActivityCompletedFileV1.decodeCanonical(bytes), change.0)
        }
        let nested = try changed(file) { object in
            var capture = try XCTUnwrap(object["capture"] as? [String: Any])
            capture["finalEnvelopeSHA256"] = String(repeating: "f", count: 64)
            object["capture"] = capture
        }
        XCTAssertThrowsError(try JSONDecoder().decode(ActivityCompletedFileV1.self, from: nested))
    }

    func testTypedPayloadTamperFailsEvenWithRecomputedWholeFileHash() throws {
        let file = try fixture()
        let bytes = try changed(file) { object in
            var snapshot = try XCTUnwrap(object["snapshot"] as? [String: Any])
            snapshot["snapshotSHA256"] = String(repeating: "0", count: 64)
            object["snapshot"] = snapshot
        }
        let reference = try ActivityCompletedFileReferenceV1(outputID: file.outputID, fileSHA256: KernelCanonicalHashV1.sha256(bytes))
        XCTAssertThrowsError(try ActivityCompletedFileV1.decodeCanonical(bytes, reference: reference))
    }

    func testWholeFileTamperFailsEvenWhenNestedSnapshotIsUnchanged() throws {
        let file = try fixture()
        let bytes = try file.canonicalData()
        let reference = try ActivityCompletedFileReferenceV1(outputID: file.outputID, fileSHA256: String(repeating: "0", count: 64))
        XCTAssertThrowsError(try ActivityCompletedFileV1.decodeCanonical(bytes, reference: reference))
        XCTAssertThrowsError(try ActivityCompletedFileV1.decodeCanonical(bytes + Data([0x0A])))
    }

    func testCapturedAbsenceRequiresEveryClosedQueryAtExactFrontier() throws {
        let file = try fixture()
        let missing = try changed(file) { object in
            var supplemental = try XCTUnwrap(object["supplemental"] as? [String: Any])
            var queries = try XCTUnwrap(supplemental["queries"] as? [[String: Any]])
            queries.removeLast()
            supplemental["queries"] = queries
            object["supplemental"] = supplemental
        }
        XCTAssertThrowsError(try ActivityCompletedFileV1.decodeCanonical(missing))
        let stale = try changed(file) { object in
            var supplemental = try XCTUnwrap(object["supplemental"] as? [String: Any])
            var queries = try XCTUnwrap(supplemental["queries"] as? [[String: Any]])
            queries[0]["sourceWorkspaceRevision"] = 9_002
            supplemental["queries"] = queries
            object["supplemental"] = supplemental
        }
        XCTAssertThrowsError(try ActivityCompletedFileV1.decodeCanonical(stale))
        let query = ActivityCompletionQueryV1(family: .serviceHistory, disposition: .checkedNoApplicableSource,
            sourceWorkspaceRevision: 9_001, rootIdentities: ["record:one"], capturedValueSHA256: String(repeating: "a", count: 64))
        XCTAssertThrowsError(try query.validate(revision: 9_001, expectedRoots: ["record:one"], valueSHA256: String(repeating: "a", count: 64)))
    }

    func testFullFrozenProfileAndManifestAreBoundToSnapshot() throws {
        let file = try fixture()
        let changedBinding = try changed(file) { object in
            var snapshot = try XCTUnwrap(object["snapshot"] as? [String: Any])
            var payload = try XCTUnwrap(snapshot["payload"] as? [String: Any])
            var activity = try XCTUnwrap(payload["activity"] as? [String: Any])
            var binding = try XCTUnwrap(activity["profileBinding"] as? [String: Any])
            binding["contractManifestSHA256"] = String(repeating: "b", count: 64)
            activity["profileBinding"] = binding
            payload["activity"] = activity
            let payloadBytes = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
            snapshot["payload"] = payload
            snapshot["snapshotSHA256"] = KernelCanonicalHashV1.sha256(payloadBytes)
            object["snapshot"] = snapshot
        }
        XCTAssertThrowsError(try ActivityCompletedFileV1.decodeCanonical(changedBinding))
        XCTAssertEqual(file.shopProfile.sectionRegistry, file.manifest.reportSectionRegistry)
        XCTAssertEqual(file.shopProfile.brand.shopDisplayName, "Constructed fixture shop")
    }

    func testExplicitSelectionUsesCanonicalObjectsAndClosedKeys() throws {
        let file = try fixture()
        let recorder = file.capture.completionTransition.actor
        // The reference binds a constructed value; it does not authenticate a
        // selected role/signoff or claim that this actor is one of those types.
        let selected = ActivityCompletionSelectedObjectV1(recordID: recorder.snapshotID, canonicalSHA256: try hash(recorder))
        try selected.validate(recordID: recorder.snapshotID, value: recorder)
        XCTAssertThrowsError(try selected.validate(recordID: id(999), value: recorder))
        let bytes = try canonical(selected)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["recordID", "canonicalSHA256"]))
        XCTAssertEqual(try JSONDecoder().decode(ActivityCompletionSelectedObjectV1.self, from: bytes), selected)
        var extraRevision = object
        extraRevision["revision"] = 1
        let unexpected = try JSONSerialization.data(withJSONObject: extraRevision, options: [.sortedKeys])
        XCTAssertThrowsError(try JSONDecoder().decode(ActivityCompletionSelectedObjectV1.self, from: unexpected))

        let selection = ActivityCompletionExplicitSelectionV1(
            activityID: file.capture.predecessor.activityID, activityRevision: file.capture.predecessor.revision,
            activitySHA256: file.capture.predecessor.envelopeSHA256, selectedBy: recorder,
            selectedAt: file.capture.capturedAt, siteRoleEvents: [], qualificationSnapshots: [],
            signoffSnapshots: [], workScopes: [], derivedProvenance: [], additionalServiceRecords: [], additionalEvidence: []
        )
        try selection.validate(capture: file.capture)
        let selectionBytes = try canonical(selection)
        XCTAssertEqual(try JSONDecoder().decode(ActivityCompletionExplicitSelectionV1.self, from: selectionBytes), selection)
        var selectedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: selectionBytes) as? [String: Any])
        for key in ["siteRoleEvents", "qualificationSnapshots", "signoffSnapshots", "derivedProvenance"] {
            XCTAssertNotNil(selectedObject[key] as? [Any], key)
        }
        selectedObject["siteRoleEventIDs"] = []
        let obsolete = try JSONSerialization.data(withJSONObject: selectedObject, options: [.sortedKeys])
        XCTAssertThrowsError(try JSONDecoder().decode(ActivityCompletionExplicitSelectionV1.self, from: obsolete))
    }

    func testStandalonePunchDoesNotManufactureInstallationOrAccountabilityAbsence() throws {
        let file = try fixture()
        XCTAssertNil(file.installation)
        XCTAssertNil(file.punchReview?.installation)
        XCTAssertEqual(file.supplemental.accountability.actors, [file.capture.completionTransition.actor])
        let emptied = try CompletedAccountabilitySnapshotV1(workspaceID: file.capture.source.workspaceID)
        let bytes = try changed(file) { object in
            var supplemental = try XCTUnwrap(object["supplemental"] as? [String: Any])
            supplemental["accountability"] = try JSONSerialization.jsonObject(with: canonical(emptied))
            object["supplemental"] = supplemental
        }
        XCTAssertThrowsError(try ActivityCompletedFileV1.decodeCanonical(bytes))
    }

    func testLegacyPredecessorOwnerKeepsUUIDPathAndWholeFileDigestDistinct() throws {
        let file = try fixture()
        let legacyBytes = try CompletedActivitySnapshotCanonicalCodecV2.encode(file.snapshot)
        let owner = ActivityCompletedPredecessorOwnerV1(kind: .legacyV2, fileVersion: 2,
            outputID: id(999), relativePath: "snapshots/ce470000-0000-4000-8000-000000000999.json",
            fileSHA256: KernelCanonicalHashV1.sha256(legacyBytes))
        try owner.validate()
        XCTAssertNotEqual(owner.fileSHA256, file.snapshot.snapshotSHA256)
        XCTAssertNil(UUID(uuidString: file.snapshot.payload.activity.snapshotID))
        let invalid = ActivityCompletedPredecessorOwnerV1(kind: .legacyV2, fileVersion: 2,
            outputID: owner.outputID, relativePath: "snapshots/\(file.snapshot.payload.activity.snapshotID).json",
            fileSHA256: owner.fileSHA256)
        XCTAssertThrowsError(try invalid.validate())
    }

    func testCrossActivityCorrectionOwnsNewOriginalForLegacyAndClosedPredecessors() throws {
        let prior = try fixture()
        for closedFile in [false, true] {
            let envelope = try finalizedEnvelope(prior, closedFile: closedFile)
            let amendment = try ActivityAmendmentLinkV1(predecessorActivityID: envelope.activityID,
                predecessorRevision: envelope.revision, predecessorSHA256: envelope.envelopeSHA256,
                reason: "Correct the recorded scope.")
            let successor = try fixture(activitySlot: 12, amendment: amendment)
            let priorBytes: Data
            if closedFile { priorBytes = try prior.canonicalData() }
            else { priorBytes = try CompletedActivitySnapshotCanonicalCodecV2.encode(prior.snapshot) }
            let owner = ActivityCompletedPredecessorOwnerV1(kind: closedFile ? .completedFile : .legacyV2,
                fileVersion: closedFile ? 1 : 2, outputID: prior.outputID, relativePath: prior.relativePath,
                fileSHA256: KernelCanonicalHashV1.sha256(priorBytes))
            let predecessor = ActivityCompletedPredecessorV1(activityFrontier: envelope, snapshot: prior.snapshot,
                owner: owner, reason: amendment.reason)
            let corrected = withPredecessor(successor, completed: predecessor)
            let correctedBytes = try corrected.canonicalData()
            XCTAssertEqual(try ActivityCompletedFileV1.decodeCanonical(correctedBytes), corrected)
            XCTAssertEqual(corrected.snapshot.payload.activity.snapshotRevision, 1)
            XCTAssertNil(corrected.snapshot.payload.activity.supersedesSnapshotID)
            XCTAssertNil(corrected.snapshot.payload.activity.amendmentReason)
            XCTAssertEqual(corrected.snapshot.payload.activity.sourceActivityID, id(12).uuidString.lowercased())
            XCTAssertNotEqual(corrected.outputID, prior.outputID)
            XCTAssertEqual(corrected.completedPredecessor?.snapshot, prior.snapshot)
            let retainedBytes: Data
            if closedFile { retainedBytes = try prior.canonicalData() }
            else { retainedBytes = try CompletedActivitySnapshotCanonicalCodecV2.encode(prior.snapshot) }
            XCTAssertEqual(retainedBytes, priorBytes)
            let wrongReason = ActivityCompletedPredecessorV1(activityFrontier: envelope, snapshot: prior.snapshot,
                owner: owner, reason: "Different reason")
            XCTAssertThrowsError(try withPredecessor(successor, completed: wrongReason).validateIntrinsic())
            XCTAssertThrowsError(try successor.validateIntrinsic(), "A selected completed predecessor cannot silently disappear")
        }
    }

    func testUnfinishedAmendmentRetainsActualPriorWithoutInventingCompletedOutput() throws {
        let prior = try fixture().capture.predecessor
        let amendment = try ActivityAmendmentLinkV1(predecessorActivityID: prior.activityID,
            predecessorRevision: prior.revision, predecessorSHA256: prior.envelopeSHA256, reason: "Replace unfinished work.")
        let successor = try fixture(activitySlot: 12, amendment: amendment)
        let file = withPredecessor(successor, unfinished: prior)
        try file.validateIntrinsic()
        XCTAssertNil(file.completedPredecessor)
        XCTAssertEqual(file.unfinishedAmendmentPredecessor, prior)
        XCTAssertNil(file.unfinishedAmendmentPredecessor?.completedSnapshotReference)
        XCTAssertThrowsError(try successor.validateIntrinsic())
    }

    func testApprovedMediaRequiresExactBytesLengthWorkspaceAndOutputScope() throws {
        let file = try fixture()
        let bytes = Data("constructed-approved-media".utf8)
        let digest = try ContentDigestV1(algorithm: .sha256, hexadecimalValue: KernelCanonicalHashV1.sha256(bytes))
        let content = try ContentReferenceV1(workspaceID: file.capture.source.workspaceID.rawValue.uuidString.lowercased(),
            contentID: "constructed-media", byteLength: Int64(bytes.count), mediaType: "image/png",
            digests: ContentDigestSetV1([digest]), byteRole: .derivative, createdAt: textInstant(instant))
        let reference = try OutputScopedContentReferenceV1(outputScopeID: "constructed-scope", ordinal: 0, reference: content)
        let media = ActivityCompletionMediaV1(reference: reference, byteLength: Int64(bytes.count), bytes: bytes)
        try media.validate(workspaceID: file.capture.source.workspaceID, outputScopeID: "constructed-scope")
        XCTAssertThrowsError(try media.validate(workspaceID: WorkspaceID(rawValue: id(999)), outputScopeID: "constructed-scope"))
        XCTAssertThrowsError(try media.validate(workspaceID: file.capture.source.workspaceID, outputScopeID: "different-scope"))
        let altered = ActivityCompletionMediaV1(reference: reference, byteLength: Int64(bytes.count + 1), bytes: bytes + Data([0]))
        XCTAssertThrowsError(try altered.validate(workspaceID: file.capture.source.workspaceID, outputScopeID: "constructed-scope"))
        let wrongLength = ActivityCompletionMediaV1(reference: reference, byteLength: 1, bytes: bytes)
        XCTAssertThrowsError(try wrongLength.validate(workspaceID: file.capture.source.workspaceID, outputScopeID: "constructed-scope"))
    }

    func testPlacementSourcesRetainExactPoseAndPhysicalAncestors() throws {
        let (sources, references) = try placementSourceFixture()
        let workspace = WorkspaceID(rawValue: id(1))
        try sources.validate(workspaceID: workspace, assetID: id(3), references: references)
        let bytes = try canonical(sources)
        let decoded = try JSONDecoder().decode(ActivityCompletionPlacementSourcesV1.self, from: bytes)
        XCTAssertEqual(decoded, sources)
        try decoded.validate(workspaceID: workspace, assetID: id(3), references: references)
        XCTAssertEqual(sources.poseEvents.map(\.revision), [1, 2])
        XCTAssertEqual(sources.poseEvents.last?.placementEventID, sources.placementHistory.last?.id)
        let empty = ActivityCompletionPlacementSourcesV1(planDocuments: [], planRevisions: [], planPlacements: [],
            poseEvents: [], placementHistory: [])
        try empty.validate(workspaceID: workspace, assetID: id(3), references: [])
        XCTAssertThrowsError(try empty.validate(workspaceID: workspace, assetID: id(3), references: references))
    }

    func testPlacementSourcesRejectMissingForeignAndUnselectedValues() throws {
        let (sources, references) = try placementSourceFixture()
        let workspace = WorkspaceID(rawValue: id(1))
        let missingPose = ActivityCompletionPlacementSourcesV1(planDocuments: [], planRevisions: [], planPlacements: [],
            poseEvents: Array(sources.poseEvents.dropFirst()), placementHistory: sources.placementHistory)
        XCTAssertThrowsError(try missingPose.validate(workspaceID: workspace, assetID: id(3), references: references))
        let missingPhysical = ActivityCompletionPlacementSourcesV1(planDocuments: [], planRevisions: [], planPlacements: [],
            poseEvents: sources.poseEvents, placementHistory: Array(sources.placementHistory.dropFirst()))
        XCTAssertThrowsError(try missingPhysical.validate(workspaceID: workspace, assetID: id(3), references: references))
        let duplicated = ActivityCompletionPlacementSourcesV1(planDocuments: [], planRevisions: [], planPlacements: [],
            poseEvents: sources.poseEvents + sources.poseEvents, placementHistory: sources.placementHistory)
        XCTAssertThrowsError(try duplicated.validate(workspaceID: workspace, assetID: id(3), references: references))
        XCTAssertThrowsError(try sources.validate(workspaceID: WorkspaceID(rawValue: id(999)), assetID: id(3), references: references))
        XCTAssertThrowsError(try sources.validate(workspaceID: workspace, assetID: id(999), references: references))
        XCTAssertThrowsError(try sources.validate(workspaceID: workspace, assetID: id(3), references: []))
        let tip = try XCTUnwrap(sources.poseEvents.last)
        let tampered = AssetPoseEventReferenceV1(eventID: tip.eventID, workspaceID: workspace, assetID: id(3),
            axisID: tip.axisDescriptor.axisID, revision: tip.revision, eventSHA256: String(repeating: "f", count: 64))
        XCTAssertThrowsError(try sources.validate(workspaceID: workspace, assetID: id(3), references: [.pose(tampered)]))
    }

    func testReviewedEvidenceFreezesPlanProjectionAndSeparateFieldMediaHashes() throws {
        let (file, evidence) = try reviewedEvidenceFixture()
        try evidence.validate(capture: file.capture, profile: file.shopProfile)
        let plan = try XCTUnwrap(evidence.reviewedMarkupPlans.first)
        let card = try XCTUnwrap(evidence.cards.first)
        let projection = try XCTUnwrap(evidence.privacyProjections.first)
        try plan.validate()
        XCTAssertTrue(projection.redactionDeclared)
        XCTAssertEqual(projection.manifestID, plan.privacyManifest.manifestID)
        XCTAssertEqual(projection.reviewReceiptID, plan.privacyReview.receiptID)
        XCTAssertEqual(plan.reviewedMarkup.sourcePrivacyDigest, projection.derivativeSHA256)
        XCTAssertNotEqual(card.privacyTransformedSHA256, projection.derivativeSHA256)
        XCTAssertEqual(card.annotations, plan.reviewedMarkup.orderedAnnotations)
        XCTAssertEqual(card.referenceLabels, plan.reviewedMarkup.orderedReferenceLabels)
        let bytes = try canonical(evidence)
        let decoded = try JSONDecoder().decode(ActivityCompletionEvidenceV1.self, from: bytes)
        XCTAssertEqual(decoded, evidence)
        try decoded.validate(capture: file.capture, profile: file.shopProfile)
    }

    func testReviewedEvidenceRejectsMissingTamperedAndForeignSources() throws {
        let (file, evidence) = try reviewedEvidenceFixture()
        let missingPlans = ActivityCompletionEvidenceV1(selectedOriginals: evidence.selectedOriginals,
            associationHistory: evidence.associationHistory, sequenceHistory: [], cards: evidence.cards,
            reviewedMarkupPlans: [], privacyProjections: evidence.privacyProjections, outputMedia: evidence.outputMedia,
            omittedEvidenceIDs: [], omissionLimitations: [])
        XCTAssertThrowsError(try missingPlans.validate(capture: file.capture, profile: file.shopProfile))
        let missingProjection = ActivityCompletionEvidenceV1(selectedOriginals: evidence.selectedOriginals,
            associationHistory: evidence.associationHistory, sequenceHistory: [], cards: evidence.cards,
            reviewedMarkupPlans: evidence.reviewedMarkupPlans, privacyProjections: [], outputMedia: evidence.outputMedia,
            omittedEvidenceIDs: [], omissionLimitations: [])
        XCTAssertThrowsError(try missingProjection.validate(capture: file.capture, profile: file.shopProfile))
        let missingOriginal = ActivityCompletionEvidenceV1(selectedOriginals: [],
            associationHistory: evidence.associationHistory, sequenceHistory: [], cards: evidence.cards,
            reviewedMarkupPlans: evidence.reviewedMarkupPlans, privacyProjections: evidence.privacyProjections,
            outputMedia: evidence.outputMedia, omittedEvidenceIDs: [], omissionLimitations: [])
        XCTAssertThrowsError(try missingOriginal.validate(capture: file.capture, profile: file.shopProfile))
        let unrelated = ActivityCompletionEvidenceV1(selectedOriginals: evidence.selectedOriginals,
            associationHistory: evidence.associationHistory, sequenceHistory: [], cards: [],
            reviewedMarkupPlans: evidence.reviewedMarkupPlans, privacyProjections: evidence.privacyProjections,
            outputMedia: [], omittedEvidenceIDs: [], omissionLimitations: [])
        XCTAssertThrowsError(try unrelated.validate(capture: file.capture, profile: file.shopProfile))
        let card = try XCTUnwrap(evidence.cards.first)
        let changedCard = try EvidenceDetailComposerV1.compose(cardID: card.cardID, workspaceID: card.workspaceID,
            evidenceID: card.evidenceID, fields: card.fields, profile: card.profile, markupID: card.reviewedMarkupID,
            annotations: ["Unselected annotation"], referenceLabels: card.referenceLabels, outputReferences: card.outputReferences)
        let changed = ActivityCompletionEvidenceV1(selectedOriginals: evidence.selectedOriginals,
            associationHistory: evidence.associationHistory, sequenceHistory: [], cards: [changedCard],
            reviewedMarkupPlans: evidence.reviewedMarkupPlans, privacyProjections: evidence.privacyProjections,
            outputMedia: evidence.outputMedia, omittedEvidenceIDs: [], omissionLimitations: [])
        XCTAssertThrowsError(try changed.validate(capture: file.capture, profile: file.shopProfile))
        let foreign = try fixture()
        XCTAssertThrowsError(try evidence.validate(capture: foreign.capture, profile: foreign.shopProfile))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: canonical(evidence)) as? [String: Any])
        var plans = try XCTUnwrap(object["reviewedMarkupPlans"] as? [[String: Any]])
        plans[0]["planSHA256"] = String(repeating: "0", count: 64)
        object["reviewedMarkupPlans"] = plans
        let corrupt = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        XCTAssertThrowsError(try JSONDecoder().decode(ActivityCompletionEvidenceV1.self, from: corrupt))
    }

    func testNewProvenanceArraysAreRequiredClosedWireFields() throws {
        let file = try fixture()
        let evidence = file.supplemental.evidence
        let evidenceObject = try XCTUnwrap(JSONSerialization.jsonObject(with: canonical(evidence)) as? [String: Any])
        for key in ["reviewedMarkupPlans", "privacyProjections"] {
            var missing = evidenceObject
            missing.removeValue(forKey: key)
            let bytes = try JSONSerialization.data(withJSONObject: missing, options: [.sortedKeys])
            XCTAssertThrowsError(try JSONDecoder().decode(ActivityCompletionEvidenceV1.self, from: bytes), key)
        }
        let empty = ActivityCompletionPlacementSourcesV1(planDocuments: [], planRevisions: [], planPlacements: [], poseEvents: [], placementHistory: [])
        let placementObject = try XCTUnwrap(JSONSerialization.jsonObject(with: canonical(empty)) as? [String: Any])
        for key in ["planDocuments", "planRevisions", "planPlacements", "poseEvents", "placementHistory"] {
            var missing = placementObject
            missing.removeValue(forKey: key)
            let bytes = try JSONSerialization.data(withJSONObject: missing, options: [.sortedKeys])
            XCTAssertThrowsError(try JSONDecoder().decode(ActivityCompletionPlacementSourcesV1.self, from: bytes), key)
        }
        var extra = placementObject
        extra["unselectedPlans"] = true
        let bytes = try JSONSerialization.data(withJSONObject: extra, options: [.sortedKeys])
        XCTAssertThrowsError(try JSONDecoder().decode(ActivityCompletionPlacementSourcesV1.self, from: bytes))
    }

    func testLegacy32CorpusPreservesLiteralBytesAndBareV2Codec() throws {
        struct Record: Decodable { let path: String; let sha256: String; let base64: String }
        struct Corpus: Decodable { let records: [Record] }
        let corpus = try JSONDecoder().decode(Corpus.self, from: resource("V23ActivityLegacyCodecCorpusV1"))
        XCTAssertEqual(corpus.records.count, 32)
        XCTAssertEqual(Set(corpus.records.map(\.path)).count, 32)
        var snapshots = 0
        for record in corpus.records {
            let bytes = try XCTUnwrap(Data(base64Encoded: record.base64))
            XCTAssertEqual(KernelCanonicalHashV1.sha256(bytes).uppercased(), record.sha256)
            if record.path.hasSuffix("completed-snapshot-v2.json") {
                let snapshot = try CompletedActivitySnapshotCanonicalCodecV2.decode(bytes)
                XCTAssertEqual(try CompletedActivitySnapshotCanonicalCodecV2.encode(snapshot), bytes)
                snapshots += 1
            }
        }
        XCTAssertEqual(snapshots, 6)
    }
}

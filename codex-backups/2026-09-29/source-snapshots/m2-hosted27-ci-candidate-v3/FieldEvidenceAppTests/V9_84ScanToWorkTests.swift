import Foundation
import XCTest

@testable import FieldEvidenceApp

private struct C21ScanToWorkCorpusV1: Decodable {
    struct Outcome: Decodable {
        let outcome: String
        let mayStartAfterExplicitAction: Bool
        let manualFallback: Bool
    }
    struct EntryEquivalence: Decodable {
        let sources: [String]
        let sameWorkspaceID: Bool
        let sameAssetRevision: Bool
        let sameWorkItemOrder: Bool
        let sameQualifiedPoseContext: Bool
        let sameEditorAnchor: Bool
        let poseMutationCount: Int
    }
    struct PreviewBoundary: Decodable {
        let canonicalMutationCountBeforeExplicitStart: Int
        let sessionCreationCountBeforeExplicitStart: Int
        let occurrenceLinkCountBeforeExplicitStart: Int
        let scanIsAuthorization: Bool
        let arbitraryURLExecutionAllowed: Bool
    }
    struct Fallback: Decodable {
        let id: String
        let manual: Bool
        let search: Bool
        let cameraRequired: Bool
    }
    struct NextAction: Decodable {
        let action: String
        let persistsDispositionBeforeNavigation: Bool
        let persistsNextItemBeforeNavigation: Bool
        let persistsResumePointBeforeNavigation: Bool
    }
    struct BatchBoundary: Decodable { let label: String; let count: Int }
    struct BatchRules: Decodable {
        let explicitReviewBeforeMutation: Bool
        let readyItemsOnly: Bool
        let idempotentAdd: Bool
        let duplicateCreatesSecondItem: Bool
        let oneFailureLosesPriorItems: Bool
        let oneFailureCompletesRound: Bool
    }
    struct SameSetup: Decodable { let allowed: [String]; let forbidden: [String] }
    struct PoseParity: Decodable {
        let qualifiedPosePreserved: Bool
        let notObservedPreserved: Bool
        let sameC37EditorAnchor: Bool
        let scanPayloadMayInferDirection: Bool
        let previewTextMayInferDirection: Bool
        let screenRotationMayInferDirection: Bool
        let poseMutationCount: Int
    }
    struct Accessibility: Decodable {
        let voiceOver: Bool
        let voiceControl: Bool
        let dynamicTypeAX5: Bool
        let rightToLeft: Bool
        let reduceMotion: Bool
        let nonColorState: Bool
        let errorFocus: Bool
        let manualFallbackAnnounced: Bool
        let sourceOrderIsReadingOrder: Bool
    }

    let schema: String
    let schemaVersion: Int
    let sourceLocale: String
    let selectors: [String]
    let closedResolverOutcomes: [Outcome]
    let entryEquivalence: EntryEquivalence
    let previewBoundary: PreviewBoundary
    let fallbackScenarios: [Fallback]
    let startRejections: [String]
    let nextActions: [NextAction]
    let interruptionBoundaries: [String]
    let batchBoundaries: [BatchBoundary]
    let batchRules: BatchRules
    let sameSetup: SameSetup
    let poseParity: PoseParity
    let accessibility: Accessibility
}

private enum C21ScanToWorkTestSupportV1 {
    static let digest = String(repeating: "a", count: 64)
    static let alternateDigest = String(repeating: "b", count: 64)
    static let timestamp = Date(timeIntervalSince1970: 1_788_134_400)

    static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }

    static func workspace(_ value: Int = 1) -> WorkspaceID {
        WorkspaceID(rawValue: id(984_000 + value))
    }

    static func package() throws -> RoundPackageReleaseReferenceV1 {
        try .init(
            packageReleaseID: digest,
            packageID: "c21-scan-work",
            packageContentVersion: 1,
            packageSHA256: digest,
            workflowSHA256: alternateDigest
        )
    }

    static func selection(_ value: Int = 1) throws -> RoundAssetSelectionV1 {
        try .init(
            assetID: id(985_000 + value),
            siteID: id(986_000 + value),
            labelAtSelection: "C21 asset \(value)"
        )
    }

    static func session(_ workspace: WorkspaceID) throws -> RoundSessionReferenceV1 {
        try .init(
            workspaceID: workspace,
            sessionID: id(987_001),
            revision: 1,
            sessionSHA256: digest
        )
    }

    static func readinessManifest(
        workspace: WorkspaceID,
        selection: RoundAssetSelectionV1
    ) throws -> OfflineReadinessManifestV1 {
        let snapshot = try OfflineReadinessSnapshotV1(
            session: session(workspace),
            expectedPackage: package(),
            observedPackage: package(),
            selectedAssets: [selection],
            observedAssetIDs: [selection.assetID],
            guidanceReferenceIDs: ["c21-guidance"],
            availableGuidanceReferenceIDs: ["c21-guidance"],
            contentRequirements: [],
            contentObservations: [],
            expectedFieldReferences: [],
            fieldReferenceReadiness: [],
            storage: try OfflineReadinessStorageObservationV1(
                capacityState: .checked,
                availableBytes: 100_000
            ),
            access: .init(protectedDataAvailable: true),
            checkedAt: timestamp,
            timeZoneIdentifier: "America/New_York",
            clockState: .checked
        )
        return try OfflineReadinessManifestBuilderV1.build(snapshot: snapshot)
    }

    static func locator(_ value: Int = 1) -> AssetLocatorReferenceV1 {
        .init(locatorID: id(988_000 + value), revision: 1, locatorSHA256: digest)
    }

    static func qualifiedPose(
        workspace: WorkspaceID,
        assetID: UUID
    ) throws -> AssetPoseEventReferenceV1 {
        .init(
            eventID: id(989_001),
            workspaceID: workspace,
            assetID: assetID,
            axisID: try PoseAxisID(rawValue: "asset-forward"),
            revision: 1,
            eventSHA256: alternateDigest
        )
    }

    static func readyPreview(
        source: ScanToWorkEntrySourceV1,
        workspace: WorkspaceID = workspace(),
        selection: RoundAssetSelectionV1? = nil,
        ordinal: Int = 1
    ) throws -> AssetPreviewStateV1 {
        let selected: RoundAssetSelectionV1
        if let selection {
            selected = selection
        } else {
            selected = try self.selection()
        }
        let proof = try ScanToWorkOfflineReadinessProofV1(
            manifest: readinessManifest(workspace: workspace, selection: selected),
            assetID: selected.assetID
        )
        let asset = try ScanToWorkAssetBindingV1(
            workspaceID: workspace,
            assetID: selected.assetID,
            siteID: selected.siteID,
            label: selected.labelAtSelection,
            assetRevision: 7,
            assetSHA256: digest,
            locator: locator(ordinal),
            readiness: proof,
            qualifiedPose: qualifiedPose(workspace: workspace, assetID: selected.assetID)
        )
        return try AssetPreviewStateV1(
            workspaceID: workspace,
            source: source,
            inputSHA256: KernelCanonicalHashV1.sha256(Data("shared-c21-code-\(ordinal)".utf8)),
            resolutionSHA256: alternateDigest,
            outcome: .ready,
            asset: asset,
            candidateLocators: [],
            evaluatedAt: timestamp
        )
    }

    static func blockedPreview(
        outcome: ScanToWorkResolutionOutcomeV1,
        ordinal: Int,
        workspace: WorkspaceID = workspace(),
        candidates: [AssetLocatorReferenceV1] = []
    ) throws -> AssetPreviewStateV1 {
        precondition(outcome != .ready)
        return try AssetPreviewStateV1(
            workspaceID: workspace,
            source: .manual,
            inputSHA256: KernelCanonicalHashV1.sha256(Data("blocked-\(ordinal)".utf8)),
            resolutionSHA256: KernelCanonicalHashV1.sha256(Data("resolution-\(ordinal)".utf8)),
            outcome: outcome,
            asset: nil,
            candidateLocators: candidates.sorted { $0.locatorID.uuidString < $1.locatorID.uuidString },
            evaluatedAt: timestamp
        )
    }

    static func actor(_ workspace: WorkspaceID) throws -> ActorSnapshotV1 {
        let local = try LocalActorReferenceV1(
            actorReferenceID: id(990_001),
            workspaceID: workspace,
            displayName: "C21 local recorder"
        )
        return try ActorSnapshotV1(
            snapshotID: id(990_002),
            workspaceID: workspace,
            actor: local,
            responsibility: .recordedBy,
            displayNameAtTime: local.displayName,
            capturedAt: timestamp
        )
    }

    static func startPolicy(
        workspace: WorkspaceID,
        allowed: Bool = true,
        revision: UInt64 = 1
    ) throws -> ScanToWorkStartPolicyV1 {
        try .init(
            workspaceID: workspace,
            policyID: "c21-start-policy",
            revision: revision,
            policySHA256: digest,
            startAllowed: allowed,
            evaluatedAt: timestamp
        )
    }

    static func roundMutation(
        workspace: WorkspaceID,
        selection: RoundAssetSelectionV1
    ) throws -> RoundSessionMutationV1 {
        let mutationID = try MutationIDV1(rawValue: id(991_001))
        let requirement = try RoundPackageContentRequirementV1(
            packageRelease: package(),
            requiredContent: []
        )
        let item = try RoundItemV1(
            itemID: id(991_002),
            order: 0,
            selection: selection,
            requirement: requirement
        )
        let round = try RoundSessionV1(
            workspaceID: workspace,
            sessionID: id(991_003),
            revision: 1,
            mutationID: mutationID,
            state: .draft,
            transition: .create,
            items: [item],
            recordedBy: actor(workspace),
            recordedAt: timestamp.addingTimeInterval(1)
        )
        return try RoundSessionMutationV1(
            workspaceID: workspace,
            expectedRevision: 0,
            mutationID: mutationID,
            session: round
        )
    }

    static func checkpointRound(
        workspace: WorkspaceID,
        selections: [RoundAssetSelectionV1],
        disposition: RepetitiveCaptureDispositionV1
    ) throws -> (predecessor: RoundSessionV1, mutation: RoundSessionMutationV1) {
        let requirement = try RoundPackageContentRequirementV1(
            packageRelease: package(),
            requiredContent: []
        )
        let pending = try selections.enumerated().map { index, selection in
            try RoundItemV1(
                itemID: id(994_100 + index),
                order: index,
                selection: selection,
                requirement: requirement
            )
        }
        func session(
            predecessor: RoundSessionV1?,
            revision: UInt64,
            mutationOrdinal: Int,
            state: RoundSessionStateV1,
            transition: RoundSessionTransitionV1,
            transitionItemID: UUID? = nil,
            items: [RoundItemV1]
        ) throws -> RoundSessionV1 {
            try RoundSessionV1(
                workspaceID: workspace,
                sessionID: id(994_001),
                predecessor: predecessor,
                revision: revision,
                mutationID: try MutationIDV1(rawValue: id(mutationOrdinal)),
                state: state,
                transition: transition,
                transitionItemID: transitionItemID,
                items: items,
                recordedBy: actor(workspace),
                recordedAt: timestamp.addingTimeInterval(TimeInterval(revision))
            )
        }
        let draft = try session(
            predecessor: nil,
            revision: 1,
            mutationOrdinal: 994_011,
            state: .draft,
            transition: .create,
            items: pending
        )
        let active = try session(
            predecessor: draft,
            revision: 2,
            mutationOrdinal: 994_012,
            state: .active,
            transition: .start,
            items: pending
        )
        let targetID = pending[0].itemID
        let predecessor: RoundSessionV1
        let successor: RoundSessionV1
        switch disposition {
        case .keepOpenAndNext:
            var items = pending
            items[0] = try RoundItemV1(
                itemID: pending[0].itemID,
                order: pending[0].order,
                selection: pending[0].selection,
                requirement: pending[0].requirement,
                disposition: .visited,
                visit: try RoundItemVisitV1(
                    visitedAt: timestamp.addingTimeInterval(3),
                    recordedBy: actor(workspace)
                )
            )
            predecessor = active
            successor = try session(
                predecessor: active,
                revision: 3,
                mutationOrdinal: 994_013,
                state: .active,
                transition: .visitItem,
                transitionItemID: targetID,
                items: items
            )
        case .defer:
            var items = pending
            items[0] = try RoundItemV1(
                itemID: pending[0].itemID,
                order: pending[0].order,
                selection: pending[0].selection,
                requirement: pending[0].requirement,
                disposition: .deferred,
                reason: .userDeferred
            )
            predecessor = active
            successor = try session(
                predecessor: active,
                revision: 3,
                mutationOrdinal: 994_014,
                state: .active,
                transition: .deferItem,
                transitionItemID: targetID,
                items: items
            )
        case .complete:
            var visitedItems = pending
            let visit = try RoundItemVisitV1(
                visitedAt: timestamp.addingTimeInterval(3),
                recordedBy: actor(workspace)
            )
            visitedItems[0] = try RoundItemV1(
                itemID: pending[0].itemID,
                order: pending[0].order,
                selection: pending[0].selection,
                requirement: pending[0].requirement,
                disposition: .visited,
                visit: visit
            )
            let visited = try session(
                predecessor: active,
                revision: 3,
                mutationOrdinal: 994_015,
                state: .active,
                transition: .visitItem,
                transitionItemID: targetID,
                items: visitedItems
            )
            var completedItems = visitedItems
            completedItems[0] = try RoundItemV1(
                itemID: pending[0].itemID,
                order: pending[0].order,
                selection: pending[0].selection,
                requirement: pending[0].requirement,
                disposition: .completed,
                visit: visit,
                completion: try RoundItemCompletionReferenceV1(
                    completionID: id(994_020),
                    revision: 1,
                    completionSHA256: alternateDigest
                )
            )
            predecessor = visited
            successor = try session(
                predecessor: visited,
                revision: 4,
                mutationOrdinal: 994_016,
                state: .active,
                transition: .completeItem,
                transitionItemID: targetID,
                items: completedItems
            )
        }
        return (
            predecessor,
            try RoundSessionMutationV1(
                workspaceID: workspace,
                expectedRevision: predecessor.revision,
                mutationID: successor.mutationID,
                session: successor
            )
        )
    }

    static func selectionOfCount(
        _ count: Int,
        workspace: WorkspaceID = workspace()
    ) throws -> BatchScanSelectionV1 {
        let previews = try (0..<count).map {
            try blockedPreview(outcome: .notFound, ordinal: 10_000 + $0, workspace: workspace)
        }.sorted { $0.inputSHA256 < $1.inputSHA256 }
        return try BatchScanSelectionV1(workspaceID: workspace, previews: previews)
    }
}

final class V9_84ScanToWorkTests: XCTestCase {
    func testV23P04C21G01ScanManualSearchResolveIdenticallyAndExplicitStartIsSoleMutationBoundary() throws {
        let corpus = try loadCorpus()
        assertCorpus(corpus, selector: "G01")
        let workspace = C21ScanToWorkTestSupportV1.workspace()
        let selection = try C21ScanToWorkTestSupportV1.selection()
        let previews = try ScanToWorkEntrySourceV1.allCases.map {
            try C21ScanToWorkTestSupportV1.readyPreview(
                source: $0,
                workspace: workspace,
                selection: selection
            )
        }
        XCTAssertEqual(previews.map(\.asset), Array(repeating: previews[0].asset, count: 3))
        XCTAssertEqual(previews.map { $0.asset?.qualifiedPose }, Array(repeating: previews[0].asset?.qualifiedPose, count: 3))
        XCTAssertEqual(previews.map(\.outcome), [.ready, .ready, .ready])
        XCTAssertEqual(previews.map(\.primaryAction), [.startExplicitly, .startExplicitly, .startExplicitly])
        XCTAssertEqual(ScanToWorkEntrySourceV1.allCases.map(\.locatorSource), [.camera, .manual, .search])
        XCTAssertEqual(
            ScanToWorkEntrySourceV1.allCases.map {
                ScanToWorkLocalizationKeyV1.entrySourceKey($0)
            },
            [.scanCode, .manualEntry, .search]
        )

        let flow = try ScanToWorkFlowV1(preview: previews[0])
        XCTAssertFalse(flow.automaticMutation)
        XCTAssertTrue(flow.explicitStartRequired)
        let mutation = try C21ScanToWorkTestSupportV1.roundMutation(
            workspace: workspace,
            selection: selection
        )
        let request = try ScanToWorkStartRequestV1(
            flow: flow,
            policy: C21ScanToWorkTestSupportV1.startPolicy(workspace: workspace),
            roundMutation: mutation,
            explicitUserConfirmation: true
        )
        XCTAssertTrue(request.explicitUserConfirmation)
        XCTAssertThrowsError(try ScanToWorkStartRequestV1(
            flow: flow,
            policy: C21ScanToWorkTestSupportV1.startPolicy(workspace: workspace),
            roundMutation: mutation,
            explicitUserConfirmation: false
        ))
        XCTAssertThrowsError(try ScanToWorkStartRequestV1(
            flow: flow,
            policy: C21ScanToWorkTestSupportV1.startPolicy(
                workspace: workspace,
                allowed: false
            ),
            roundMutation: mutation,
            explicitUserConfirmation: true
        ))
        XCTAssertEqual(corpus.previewBoundary.canonicalMutationCountBeforeExplicitStart, 0)
        XCTAssertEqual(corpus.previewBoundary.sessionCreationCountBeforeExplicitStart, 0)
        XCTAssertEqual(corpus.previewBoundary.occurrenceLinkCountBeforeExplicitStart, 0)
        XCTAssertFalse(corpus.previewBoundary.scanIsAuthorization)
        XCTAssertFalse(corpus.previewBoundary.arbitraryURLExecutionAllowed)
    }

    func testV23P04C21A01PermissionAndCameraDenialKeepCompleteManualFallbackAndBatchBounds() throws {
        let corpus = try loadCorpus()
        assertCorpus(corpus, selector: "A01")
        try ScanToWorkLocalizationPolicyV1.validate()
        try ScanToWorkAccessibilityPolicyV1.validate()
        let fallback = try ManualLookupFallbackV1(
            workspaceID: C21ScanToWorkTestSupportV1.workspace(),
            inputSHA256: C21ScanToWorkTestSupportV1.digest,
            reason: .notFound
        )
        try fallback.validateIntrinsic()
        XCTAssertTrue(fallback.explicitEntryRequired)
        XCTAssertFalse(fallback.automaticNetworkLookup)
        XCTAssertTrue(corpus.fallbackScenarios.allSatisfy { $0.manual && $0.search && !$0.cameraRequired })
        XCTAssertTrue(Set(corpus.fallbackScenarios.map(\.id)).isSuperset(of: ["PERMISSION_DENIED", "CAMERA_UNAVAILABLE", "DAMAGED_CODE"]))

        XCTAssertEqual(corpus.batchBoundaries.map(\.count), [1, 2, 100, ScanToWorkLimitsV1.maximumSelection])
        for boundary in corpus.batchBoundaries {
            let selection = try C21ScanToWorkTestSupportV1.selectionOfCount(boundary.count)
            XCTAssertEqual(selection.previews.count, boundary.count)
            try selection.validateIntrinsic()
        }
        XCTAssertThrowsError(try C21ScanToWorkTestSupportV1.selectionOfCount(ScanToWorkLimitsV1.maximumSelection + 1))
        XCTAssertTrue(corpus.batchRules.explicitReviewBeforeMutation)
        XCTAssertTrue(corpus.batchRules.readyItemsOnly)
        XCTAssertTrue(corpus.batchRules.idempotentAdd)
        XCTAssertFalse(corpus.batchRules.duplicateCreatesSecondItem)
        XCTAssertFalse(corpus.batchRules.oneFailureLosesPriorItems)
        XCTAssertFalse(corpus.batchRules.oneFailureCompletesRound)
    }

    func testV23P04C21H01AllClosedOutcomesAndHostilePreviewChangesFailClosed() throws {
        let corpus = try loadCorpus()
        assertCorpus(corpus, selector: "H01")
        XCTAssertEqual(corpus.closedResolverOutcomes.map(\.outcome), ScanToWorkResolutionOutcomeV1.allCases.map(\.rawValue))
        XCTAssertEqual(corpus.closedResolverOutcomes.filter(\.mayStartAfterExplicitAction).map(\.outcome), ["READY"])
        XCTAssertTrue(corpus.closedResolverOutcomes.allSatisfy { $0.manualFallback })

        let expectedActions: [ScanToWorkPrimaryActionV1] = [
            .startExplicitly, .removeDuplicate, .openExistingRound, .chooseCandidate,
            .switchWorkspace, .useReplacement, .manualLookup, .prepareOffline, .refresh,
        ]
        for (index, outcome) in ScanToWorkResolutionOutcomeV1.allCases.enumerated() where outcome != .ready {
            let candidates = outcome == .ambiguous
                ? [C21ScanToWorkTestSupportV1.locator(2), C21ScanToWorkTestSupportV1.locator(3)]
                : []
            let preview = try C21ScanToWorkTestSupportV1.blockedPreview(
                outcome: outcome,
                ordinal: index,
                candidates: candidates
            )
            XCTAssertEqual(preview.primaryAction, expectedActions[index])
            XCTAssertEqual(preview.manualFallback?.reason, outcome)
            XCTAssertEqual(ScanToWorkLocalizationKeyV1.outcomeKey(outcome).rawValue, "scan.work.outcome.\(outcome.rawValue.lowercased())")
            XCTAssertFalse(preview.manualFallback?.automaticNetworkLookup ?? true)
        }

        XCTAssertEqual(Set(corpus.startRejections), Set([
            "ASSET_CHANGED_AFTER_PREVIEW", "PACKET_INCOMPLETE", "TWO_MATCHING_WORK_ITEMS",
            "STALE_PREVIEW", "NOT_OFFLINE_READY",
        ]))
        let ready = try C21ScanToWorkTestSupportV1.readyPreview(source: .scan)
        let flow = try ScanToWorkFlowV1(preview: ready)
        let different = try C21ScanToWorkTestSupportV1.selection(99)
        XCTAssertThrowsError(try ScanToWorkStartRequestV1(
            flow: flow,
            policy: C21ScanToWorkTestSupportV1.startPolicy(workspace: ready.workspaceID),
            roundMutation: C21ScanToWorkTestSupportV1.roundMutation(
                workspace: ready.workspaceID,
                selection: different
            ),
            explicitUserConfirmation: true
        ))
        let duplicateReady = try C21ScanToWorkTestSupportV1.readyPreview(
            source: .manual,
            workspace: ready.workspaceID,
            selection: try C21ScanToWorkTestSupportV1.selection(),
            ordinal: 99
        )
        XCTAssertThrowsError(try BatchScanSelectionV1(
            workspaceID: ready.workspaceID,
            previews: [ready, duplicateReady].sorted { $0.inputSHA256 < $1.inputSHA256 }
        ))
        XCTAssertTrue(Set(corpus.fallbackScenarios.map(\.id)).isSuperset(of: Set([
            "DAMAGED_CODE", "AMBIGUOUS_CODE", "FOREIGN_CODE", "REVOKED_CODE",
            "RETIRED_OR_REPLACED", "STALE_PREVIEW",
        ])))
    }

    func testV23P04C21I01NextActionsPersistBeforeNavigationAndCanonicalStateReopens() throws {
        let corpus = try loadCorpus()
        assertCorpus(corpus, selector: "I01")
        XCTAssertEqual(corpus.nextActions.map(\.action), [
            "COMPLETE_AND_NEXT", "DEFER_AND_NEXT", "KEEP_OPEN_AND_NEXT",
        ])
        XCTAssertTrue(corpus.nextActions.allSatisfy {
            $0.persistsDispositionBeforeNavigation &&
            $0.persistsNextItemBeforeNavigation &&
            $0.persistsResumePointBeforeNavigation
        })
        XCTAssertEqual(corpus.interruptionBoundaries, [
            "BEFORE_DISPOSITION_COMMIT",
            "AFTER_DISPOSITION_BEFORE_NEXT_ITEM",
            "AFTER_NEXT_ITEM_BEFORE_RESUME_ROUTE",
            "AFTER_RESUME_ROUTE_BEFORE_NAVIGATION",
        ])

        let flow = try ScanToWorkFlowV1(
            preview: C21ScanToWorkTestSupportV1.blockedPreview(
                outcome: .stale,
                ordinal: 201
            )
        )
        let reopened = try JSONDecoder().decode(
            ScanToWorkFlowV1.self,
            from: JSONEncoder().encode(flow)
        )
        try reopened.validateIntrinsic()
        XCTAssertEqual(reopened, flow)

        let selection = try C21ScanToWorkTestSupportV1.selectionOfCount(2)
        let plan = try RepetitiveCapturePlanV1(
            workspaceID: selection.workspaceID,
            planID: C21ScanToWorkTestSupportV1.id(992_001),
            draftID: C21ScanToWorkTestSupportV1.id(992_002),
            draftRevision: 1,
            draftSHA256: C21ScanToWorkTestSupportV1.digest,
            round: nil,
            selection: selection
        )
        let reopenedPlan = try JSONDecoder().decode(
            RepetitiveCapturePlanV1.self,
            from: JSONEncoder().encode(plan)
        )
        try reopenedPlan.validateIntrinsic()
        XCTAssertEqual(reopenedPlan, plan)
    }

    func testV23P04C21R01ProjectionPoseAccessibilityAndNonsemanticSetupRemainExact() throws {
        let corpus = try loadCorpus()
        assertCorpus(corpus, selector: "R01")
        let workspace = C21ScanToWorkTestSupportV1.workspace()
        let firstSelection = try C21ScanToWorkTestSupportV1.selection(1)
        let secondSelection = try C21ScanToWorkTestSupportV1.selection(2)
        let ready = try C21ScanToWorkTestSupportV1.readyPreview(
            source: .scan,
            workspace: workspace,
            selection: firstSelection,
            ordinal: 1
        )
        let secondReady = try C21ScanToWorkTestSupportV1.readyPreview(
            source: .manual,
            workspace: workspace,
            selection: secondSelection,
            ordinal: 2
        )
        let blocked = try C21ScanToWorkTestSupportV1.blockedPreview(
            outcome: .notOfflineReady,
            ordinal: 301,
            workspace: workspace
        )
        let selection = try BatchScanSelectionV1(
            workspaceID: workspace,
            previews: [ready, secondReady, blocked].sorted { $0.inputSHA256 < $1.inputSHA256 }
        )
        let plan = try RepetitiveCapturePlanV1(
            workspaceID: workspace,
            planID: C21ScanToWorkTestSupportV1.id(993_001),
            draftID: C21ScanToWorkTestSupportV1.id(993_002),
            draftRevision: 1,
            draftSHA256: C21ScanToWorkTestSupportV1.digest,
            round: nil,
            selection: selection
        )
        let projection = try RepetitiveCaptureProjectionV1(plan: plan)
        try projection.validate(plan: plan)
        XCTAssertEqual(projection.readyAssetIDs, [
            try XCTUnwrap(ready.asset?.assetID),
            try XCTUnwrap(secondReady.asset?.assetID),
        ])
        XCTAssertEqual(projection.blockedCount, 1)
        XCTAssertEqual(projection.nextAssetID, ready.asset?.assetID)

        let next = try NextAssetProjectionV1(
            plan: plan,
            currentAssetID: try XCTUnwrap(ready.asset?.assetID)
        )
        XCTAssertEqual(next.nextAssetID, secondReady.asset?.assetID)
        XCTAssertEqual(next.remainingCount, 1)
        let resume = try DraftResumeAnchorV1(
            sectionID: "c21-section",
            fieldID: "c21-field",
            selectedStableID: secondSelection.assetID.uuidString.lowercased(),
            boundedPosition: 1
        )
        for disposition in RepetitiveCaptureDispositionV1.allCases {
            let round = try C21ScanToWorkTestSupportV1.checkpointRound(
                workspace: workspace,
                selections: [firstSelection, secondSelection],
                disposition: disposition
            )
            let checkpointPlan = try RepetitiveCapturePlanV1(
                workspaceID: workspace,
                planID: C21ScanToWorkTestSupportV1.id(993_010 + RepetitiveCaptureDispositionV1.allCases.firstIndex(of: disposition)!),
                draftID: C21ScanToWorkTestSupportV1.id(993_020 + RepetitiveCaptureDispositionV1.allCases.firstIndex(of: disposition)!),
                draftRevision: 1,
                draftSHA256: C21ScanToWorkTestSupportV1.digest,
                round: try round.predecessor.reference,
                selection: selection
            )
            let operation = try RepetitiveCapturePersistenceOperationV1(
                plan: checkpointPlan,
                assetID: firstSelection.assetID,
                disposition: disposition,
                resumeAnchor: resume,
                roundMutation: round.mutation
            )
            XCTAssertEqual(operation.assetID, firstSelection.assetID)
            XCTAssertEqual(operation.nextAsset.nextAssetID, secondSelection.assetID)
            let checkpoint = try RepetitiveCaptureCheckpointRequestV1(
                plan: checkpointPlan,
                assetID: firstSelection.assetID,
                disposition: disposition,
                requirementFocus: .facts,
                resumeAnchor: resume,
                roundMutation: round.mutation
            )
            XCTAssertEqual(checkpoint.nextAsset.nextAssetID, secondSelection.assetID)
            XCTAssertEqual(checkpoint.resumeAnchor, resume)
        }
        let deferredRound = try C21ScanToWorkTestSupportV1.checkpointRound(
            workspace: workspace,
            selections: [firstSelection, secondSelection],
            disposition: .defer
        )
        let deferredPlan = try RepetitiveCapturePlanV1(
            workspaceID: workspace,
            planID: C21ScanToWorkTestSupportV1.id(993_030),
            draftID: C21ScanToWorkTestSupportV1.id(993_031),
            draftRevision: 1,
            draftSHA256: C21ScanToWorkTestSupportV1.digest,
            round: try deferredRound.predecessor.reference,
            selection: selection
        )
        XCTAssertThrowsError(try RepetitiveCaptureCheckpointRequestV1(
            plan: deferredPlan,
            assetID: firstSelection.assetID,
            disposition: .complete,
            requirementFocus: .facts,
            resumeAnchor: resume,
            roundMutation: deferredRound.mutation
        ))
        XCTAssertThrowsError(try RepetitiveCaptureCheckpointRequestV1(
            plan: deferredPlan,
            assetID: firstSelection.assetID,
            disposition: .defer,
            requirementFocus: .facts,
            resumeAnchor: try DraftResumeAnchorV1(selectedStableID: firstSelection.assetID.uuidString.lowercased()),
            roundMutation: deferredRound.mutation
        ))

        let setup = try RepetitiveCaptureSetupV1(
            captureModeID: "photo",
            lensPreferenceID: "standard",
            framingGuideID: "center"
        )
        let copy = try RepetitiveCaptureConfigurationCopyV1(
            source: plan,
            destinationWorkspaceID: workspace,
            destinationPlanID: C21ScanToWorkTestSupportV1.id(993_003),
            copiedConfigurationSHA256: setup.setupSHA256
        )
        try copy.validateIntrinsic()
        XCTAssertFalse(copy.copiedFactsOrEvidence)

        XCTAssertEqual(corpus.sameSetup.allowed, ["DISPLAY_CONFIGURATION"])
        XCTAssertEqual(Set(corpus.sameSetup.forbidden), Set([
            "ANSWERS", "NOTES", "FINDINGS", "EVIDENCE", "POSE",
            "TIMESTAMPS", "STATUS", "COMPLETION",
        ]))
        XCTAssertTrue(corpus.poseParity.qualifiedPosePreserved)
        XCTAssertTrue(corpus.poseParity.notObservedPreserved)
        XCTAssertTrue(corpus.poseParity.sameC37EditorAnchor)
        XCTAssertFalse(corpus.poseParity.scanPayloadMayInferDirection)
        XCTAssertFalse(corpus.poseParity.previewTextMayInferDirection)
        XCTAssertFalse(corpus.poseParity.screenRotationMayInferDirection)
        XCTAssertEqual(corpus.poseParity.poseMutationCount, 0)

        XCTAssertTrue(corpus.accessibility.voiceOver)
        XCTAssertTrue(corpus.accessibility.voiceControl)
        XCTAssertTrue(corpus.accessibility.dynamicTypeAX5)
        XCTAssertTrue(corpus.accessibility.rightToLeft)
        XCTAssertTrue(corpus.accessibility.reduceMotion)
        XCTAssertTrue(corpus.accessibility.nonColorState)
        XCTAssertTrue(corpus.accessibility.errorFocus)
        XCTAssertTrue(corpus.accessibility.manualFallbackAnnounced)
        XCTAssertTrue(corpus.accessibility.sourceOrderIsReadingOrder)
        _ = try BundledLocalizationCatalogV1.scanToWorkAccessibilityRegistry(
            localization: BundledLocalizationCatalogV1.scanToWorkRegistry()
        )
    }

    private func loadCorpus() throws -> C21ScanToWorkCorpusV1 {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent(
            "FieldEvidenceAppTests/Fixtures/V23/Rounds/V23P04C21ScanToWorkCorpusV1.json"
        )
        return try JSONDecoder().decode(
            C21ScanToWorkCorpusV1.self,
            from: Data(contentsOf: url)
        )
    }

    private func assertCorpus(_ corpus: C21ScanToWorkCorpusV1, selector: String) {
        XCTAssertEqual(corpus.schema, "V23P04C21ScanToWorkCorpusV1")
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.sourceLocale, "en")
        XCTAssertEqual(corpus.selectors, ["G01", "A01", "H01", "I01", "R01"].map {
            "V23-P04-C21-\($0)"
        })
        XCTAssertTrue(corpus.selectors.contains("V23-P04-C21-\(selector)"))
        XCTAssertEqual(corpus.entryEquivalence.sources, ScanToWorkEntrySourceV1.allCases.map(\.rawValue))
        XCTAssertTrue(corpus.entryEquivalence.sameWorkspaceID)
        XCTAssertTrue(corpus.entryEquivalence.sameAssetRevision)
        XCTAssertTrue(corpus.entryEquivalence.sameWorkItemOrder)
        XCTAssertTrue(corpus.entryEquivalence.sameQualifiedPoseContext)
        XCTAssertTrue(corpus.entryEquivalence.sameEditorAnchor)
        XCTAssertEqual(corpus.entryEquivalence.poseMutationCount, 0)
    }
}

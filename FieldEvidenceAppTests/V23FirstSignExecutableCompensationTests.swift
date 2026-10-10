import Foundation
import CryptoKit
import SwiftData
import XCTest

@testable import FieldEvidenceApp

final class V23FirstSignExecutableCompensationTests: XCTestCase {
    @MainActor
    func testNewFirstSignAtomicallyRecordsExecutableOriginalCommitment() throws {
        let h = try harness(); defer { h.removeFiles() }
        let s = try h.makeScenario()
        _ = try h.writer.execute(s.request)
        let row = try XCTUnwrap(h.context.fetch(FetchDescriptor<MutationReceiptRow>()).first)
        let envelope = try MutationEnvelopeV1.decodeCanonical(from: row.envelopeData)
        let receipt = try MutationReceiptV1.decodeCanonical(from: row.receiptData)
        let basis = try XCTUnwrap(h.store.reversalBasis(mutationID: s.mutationID))
        let payload = try XCTUnwrap(basis.firstSignCompensation)
        XCTAssertEqual(basis.schemaVersion, 2)
        XCTAssertEqual(payload, try FirstSignCompensationV1(request: s.request))
        XCTAssertEqual(basis.targetReceiptIdentity, receipt.identity)
        XCTAssertEqual(envelope.reversalPlanDigest, try payload.commitment())
        XCTAssertEqual(basis.planDigest, envelope.reversalPlanDigest)
        XCTAssertEqual(basis.compensatingCommandKinds, [.deleteAsset])
        XCTAssertEqual(try payload.requireOriginalCommand(envelope.command), firstSign(s))
        XCTAssertEqual(try basis.canonicalData(), row.reversalBasisData)
        XCTAssertEqual(try basis.canonicalSHA256(), row.reversalBasisSHA256)
        XCTAssertEqual(try ReversalBasisV1.decodeCanonical(from: basis.canonicalData()), basis)
        try h.store.validateAll()
        XCTAssertFalse(h.context.hasChanges)
    }

    @MainActor
    func testColdEligibilityResolvesRealPlanAndSingleAssetCompensationRetainsSitePlacementAndHistory() throws {
        let h = try harness(); defer { h.removeFiles() }
        let s = try h.makeScenario()
        _ = try h.writer.execute(s.request)
        let original = try XCTUnwrap(h.context.fetch(FetchDescriptor<MutationReceiptRow>()).first)
        let retained = (original.envelopeData, original.receiptData, original.reversalBasisData)
        let placement = try XCTUnwrap(h.context.fetch(FetchDescriptor<AssetPlacementEventRow>()).first).canonicalData
        let cold = try h.reopen()
        let preview = try cold.writer.firstSignReversalEligibility(targetMutationID: s.mutationID)
        XCTAssertEqual(preview.eligibility, .eligible)
        let portable = try XCTUnwrap(preview.portablePlan)
        let payload = try XCTUnwrap(portable.firstSignCompensation)
        XCTAssertEqual(portable.compensatingCommands, [try payload.compensatingCommand()])
        let portableBytes = try WorkspaceMutationCanonicalV1.data(portable)
        XCTAssertEqual(try JSONDecoder().decode(PortableReversalPlanV1.self, from: portableBytes), portable)
        let reversalID = try MutationIDV1(rawValue: UUID())
        let request = try reversalRequest(writer: cold.writer, payload: payload, mutationID: reversalID)
        _ = try cold.writer.executeSemanticReversal(request, targetMutationID: s.mutationID,
            plan: payload.semanticPlan(expectedRevision: request.expectedRevision),
            compensatingMutationIDs: [reversalID])
        XCTAssertEqual(try cold.context.fetchCount(FetchDescriptor<Asset>()), 0)
        XCTAssertEqual(try cold.context.fetchCount(FetchDescriptor<Site>()), 1)
        XCTAssertEqual(try cold.context.fetchCount(FetchDescriptor<AssetPlacementEventRow>()), 1)
        XCTAssertEqual(try cold.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 2)
        XCTAssertEqual(try XCTUnwrap(cold.context.fetch(FetchDescriptor<AssetPlacementEventRow>()).first).canonicalData, placement)
        let ledger = try DeletionLedgerStore(context: cold.context, privateSystemDiscoveryIndex: nil).snapshot()
        XCTAssertEqual(ledger.entries.map(\.identity), [try DeletionIdentityV2(kind: .asset, id: payload.assetID)])
        let retainedRow = try XCTUnwrap(cold.context.fetch(FetchDescriptor<MutationReceiptRow>()).first { $0.mutationID == s.mutationID.rawValue })
        XCTAssertEqual(retainedRow.envelopeData, retained.0)
        XCTAssertEqual(retainedRow.receiptData, retained.1)
        XCTAssertEqual(retainedRow.reversalBasisData, retained.2)
        XCTAssertNotNil(try cold.store.receipt(mutationID: reversalID))
        try cold.store.validateAll()
        XCTAssertFalse(cold.context.hasChanges)
    }

    @MainActor
    func testSameIDReplayUsesOriginalCommitmentAfterColdReopenAndChangedCommandQuarantines() throws {
        let h = try harness(); defer { h.removeFiles() }
        let s = try h.makeScenario()
        let original = try h.writer.execute(s.request)
        let row = try XCTUnwrap(h.context.fetch(FetchDescriptor<MutationReceiptRow>()).first)
        let bytes = (row.envelopeData, row.receiptData, row.reversalBasisData)
        let cold = try h.reopen()
        let replay = try cold.writer.execute(s.request)
        XCTAssertEqual(replay.commandDigest, original.commandDigest)
        XCTAssertEqual(try cold.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
        let replayRow = try XCTUnwrap(cold.context.fetch(FetchDescriptor<MutationReceiptRow>()).first)
        XCTAssertEqual(replayRow.envelopeData, bytes.0)
        XCTAssertEqual(replayRow.receiptData, bytes.1)
        XCTAssertEqual(replayRow.reversalBasisData, bytes.2)
        let v = firstSign(s)
        let changed = WorkspaceCommandV1.createFirstSign(.init(siteID: v.siteID, newSite: v.newSite,
            assetID: v.assetID, assetLabel: "Changed committed command", packID: v.packID,
            packSchemaVersion: v.packSchemaVersion, packContentVersion: v.packContentVersion,
            createdAt: v.createdAt, initialPlacementMutationID: v.initialPlacementMutationID,
            initialPlacementEventID: v.initialPlacementEventID, initialPhysicalEpisodeID: v.initialPhysicalEpisodeID))
        XCTAssertThrowsError(try cold.writer.execute(.init(mutationID: s.mutationID,
            expectedRevision: s.request.expectedRevision, command: changed)))
        XCTAssertEqual(try cold.context.fetchCount(FetchDescriptor<MutationQuarantineRow>()), 1)
        XCTAssertEqual(try cold.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
        XCTAssertEqual(replayRow.envelopeData, bytes.0)
        XCTAssertEqual(replayRow.reversalBasisData, bytes.2)
        XCTAssertEqual(try cold.context.fetchCount(FetchDescriptor<Asset>()), 1)
        XCTAssertFalse(cold.context.hasChanges)
    }

    @MainActor
    func testIndependentSiteTimeZoneChangeDoesNotBecomeWholeWorkspaceUndoVeto() throws {
        let h = try harness(); defer { h.removeFiles() }
        let s = try h.makeScenario(); _ = try h.writer.execute(s.request)
        let v = firstSign(s)
        _ = try h.writer.execute(.updateSiteTimeZone(.init(siteID: v.siteID,
            timeZoneID: "America/Chicago", confirmedAt: Date(timeIntervalSince1970: 1_700_000_020))),
            mutationID: MutationIDV1(rawValue: UUID()))
        let preview = try h.writer.firstSignReversalEligibility(targetMutationID: s.mutationID)
        let payload = try XCTUnwrap(preview.portablePlan?.firstSignCompensation)
        let id = try MutationIDV1(rawValue: UUID())
        let request = try reversalRequest(writer: h.writer, payload: payload, mutationID: id)
        _ = try h.writer.executeSemanticReversal(request, targetMutationID: s.mutationID,
            plan: payload.semanticPlan(expectedRevision: request.expectedRevision),
            compensatingMutationIDs: [id])
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<Asset>()), 0)
        let site = try XCTUnwrap(h.context.fetch(FetchDescriptor<Site>()).first)
        XCTAssertEqual(site.id, v.siteID)
        XCTAssertEqual(site.timeZoneID, "America/Chicago")
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 3)
        try h.store.validateAll()
        XCTAssertFalse(h.context.hasChanges)
    }

    @MainActor
    func testLivePreviewBindsCurrentRevisionAndStalePreviewRefusesWithoutEffects() throws {
        let h = try harness(); defer { h.removeFiles() }
        let s = try h.makeScenario(); _ = try h.writer.execute(s.request)
        let plan = try h.writer.firstSignReversalPlan(targetMutationID: s.mutationID)
        let payload = try XCTUnwrap(plan.firstSignCompensation)
        XCTAssertEqual(plan.expectedRevision.workspaceRevision, try h.writer.currentRevision().revision)
        XCTAssertEqual(plan.expectedRevision.writerInstanceID, try h.writer.currentRevision().writerInstanceID)
        _ = try h.writer.execute(.updateSiteTimeZone(.init(siteID: payload.siteID,
            timeZoneID: "America/New_York", confirmedAt: Date(timeIntervalSince1970: 1_700_000_020))),
            mutationID: MutationIDV1(rawValue: UUID()))
        let id = try MutationIDV1(rawValue: UUID())
        let stale = WorkspaceMutationRequestV1(mutationID: id, expectedRevision: plan.expectedRevision,
            command: try payload.compensatingCommand())
        let counts = try h.rowCounts(in: h.context)
        XCTAssertThrowsError(try h.writer.executeSemanticReversal(stale, targetMutationID: s.mutationID,
            plan: plan, compensatingMutationIDs: [id]))
        XCTAssertEqual(try h.rowCounts(in: h.context), counts)
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<DeletionLedgerRow>()), 0)
        let refreshed = try h.writer.firstSignReversalPlan(targetMutationID: s.mutationID)
        XCTAssertEqual(refreshed.planDigest, plan.planDigest)
        XCTAssertEqual(refreshed.firstSignCompensation, plan.firstSignCompensation)
        XCTAssertNotEqual(refreshed.expectedRevision.workspaceRevision, plan.expectedRevision.workspaceRevision)
        let current = WorkspaceMutationRequestV1(mutationID: id, expectedRevision: refreshed.expectedRevision,
            command: try payload.compensatingCommand())
        _ = try h.writer.executeSemanticReversal(current, targetMutationID: s.mutationID,
            plan: refreshed, compensatingMutationIDs: [id])
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<Asset>()), 0)
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<DeletionLedgerRow>()), 1)
        XCTAssertFalse(h.context.hasChanges)
    }

    @MainActor
    func testUnknownRetainedDraftCodecRefusesBeforeDeletionTombstoneOrReceipt() throws {
        let h = try harness(); defer { h.removeFiles() }
        let s = try h.makeScenario(); _ = try h.writer.execute(s.request)
        let payload = try XCTUnwrap(h.store.reversalBasis(mutationID: s.mutationID)?.firstSignCompensation)
        let draftID = UUID(), id = try MutationIDV1(rawValue: UUID())
        let checkpoint = try FieldDraftCheckpointV1(draftID: draftID, workspaceID: h.identity.workspaceID,
            scope: .init(scopeKind: "asset", stableComponentIDs: [payload.assetID.uuidString.lowercased()]),
            purpose: .assetFieldEdit, codec: .init(codecID: "test.unresolved-owner", codecVersion: 1,
                releaseSHA256: String(repeating: "b", count: 64)),
            baseCanonicalRevision: 1, draftRevision: 1, payloadData: Data("opaque owner".utf8),
            stageIDs: [], resumeAnchor: .init(), state: .active,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_020), mutationID: id)
        let mutation = try FieldDraftMutationV1(workspaceID: h.identity.workspaceID, expectedRevision: 0,
            expectedBaseCanonicalRevision: 1, mutationID: id, postImage: .createCheckpoint(checkpoint))
        _ = try h.writer.execute(.applyFieldDraft(mutation), mutationID: id)
        let before = try h.rowCounts(in: h.context)
        let draftBytes = try XCTUnwrap(h.context.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).first).canonicalData
        XCTAssertThrowsError(try h.writer.firstSignReversalEligibility(targetMutationID: s.mutationID))
        let reversalID = try MutationIDV1(rawValue: UUID())
        let request = try reversalRequest(writer: h.writer, payload: payload, mutationID: reversalID)
        XCTAssertThrowsError(try h.writer.executeSemanticReversal(request, targetMutationID: s.mutationID,
            plan: payload.semanticPlan(expectedRevision: request.expectedRevision),
            compensatingMutationIDs: [reversalID]))
        XCTAssertEqual(try h.rowCounts(in: h.context), before)
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<DeletionLedgerRow>()), 0)
        XCTAssertNil(try h.store.receipt(mutationID: reversalID))
        XCTAssertEqual(try XCTUnwrap(h.context.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).first).canonicalData, draftBytes)
        XCTAssertFalse(h.context.hasChanges)
    }

    @MainActor
    func testRetainedSourceBatchChecksNonFirstAssetAndAdmitsUnrelatedNilPreviews() throws {
        for includesCompensatedAsset in [false, true] {
            let h = try harness(); defer { h.removeFiles() }
            let s = try h.makeScenario(); _ = try h.writer.execute(s.request)
            let other = try h.makeScenario(); _ = try h.writer.execute(other.request)
            let payload = try XCTUnwrap(h.store.reversalBasis(mutationID: s.mutationID)?.firstSignCompensation)
            let target = firstSign(s), unrelated = firstSign(other)
            let workspace = h.identity.workspaceID
            let instant = Date(timeIntervalSince1970: 1_700_000_020)
            let digest = String(repeating: "a", count: 64)
            let round = try RoundSessionReferenceV1(workspaceID: workspace, sessionID: UUID(),
                revision: 1, sessionSHA256: digest)
            let package = try RoundPackageReleaseReferenceV1(packageReleaseID: digest,
                packageID: unrelated.packID, packageContentVersion: unrelated.packContentVersion,
                packageSHA256: digest, workflowSHA256: String(repeating: "b", count: 64))
            var selected = [try RoundAssetSelectionV1(assetID: unrelated.assetID,
                siteID: unrelated.siteID, labelAtSelection: unrelated.assetLabel)]
            if includesCompensatedAsset {
                selected.append(try RoundAssetSelectionV1(assetID: target.assetID,
                    siteID: target.siteID, labelAtSelection: target.assetLabel))
            }
            selected.sort { $0.assetID.uuidString < $1.assetID.uuidString }
            let observedAssetIDs = Set(try h.context.fetch(FetchDescriptor<Asset>()).map(\.id))
            let selectedAssetIDs = Set(selected.map(\.assetID))
            XCTAssertTrue(selectedAssetIDs.isSubset(of: observedAssetIDs))
            let manifest = try OfflineReadinessManifestBuilderV1.build(snapshot: .init(session: round,
                expectedPackage: package, observedPackage: package, selectedAssets: selected,
                observedAssetIDs: selectedAssetIDs,
                guidanceReferenceIDs: [], availableGuidanceReferenceIDs: [], contentRequirements: [],
                contentObservations: [], expectedFieldReferences: [], fieldReferenceReadiness: [],
                storage: .init(capacityState: .checked, availableBytes: 100_000),
                access: .init(protectedDataAvailable: true), checkedAt: instant,
                timeZoneIdentifier: "UTC", clockState: .checked))
            func readyPreview(_ asset: FirstSignMutationV1, input: String) throws -> AssetPreviewStateV1 {
                let binding = try ScanToWorkAssetBindingV1(workspaceID: workspace,
                    assetID: asset.assetID, siteID: asset.siteID, label: asset.assetLabel,
                    assetRevision: 1, assetSHA256: digest,
                    locator: .init(locatorID: UUID(), revision: 1, locatorSHA256: digest),
                    readiness: ScanToWorkOfflineReadinessProofV1(manifest: manifest, assetID: asset.assetID),
                    qualifiedPose: nil)
                return try AssetPreviewStateV1(workspaceID: workspace, source: .manual,
                    inputSHA256: input, resolutionSHA256: digest, outcome: .ready,
                    asset: binding, candidateLocators: [], evaluatedAt: instant)
            }
            let missing = try AssetPreviewStateV1(workspaceID: workspace, source: .manual,
                inputSHA256: String(repeating: "0", count: 64), resolutionSHA256: digest,
                outcome: .notFound, asset: nil, candidateLocators: [], evaluatedAt: instant)
            let unrelatedPreview = try readyPreview(unrelated, input: digest)
            var previews = [missing, unrelatedPreview]
            if includesCompensatedAsset {
                previews.append(try readyPreview(target, input: String(repeating: "f", count: 64)))
            }
            let selection = try BatchScanSelectionV1(workspaceID: workspace, previews: previews)
            XCTAssertNil(selection.previews[0].asset)
            XCTAssertEqual(selection.previews[1].asset?.assetID, unrelated.assetID)
            if includesCompensatedAsset {
                XCTAssertEqual(selection.previews[2].asset?.assetID, payload.assetID)
            }
            let planID = UUID(), draftID = UUID(), draftMutationID = try MutationIDV1(rawValue: UUID())
            let checkpoint = try FieldDraftCheckpointV1(draftID: draftID, workspaceID: workspace,
                scope: RepetitiveCaptureDraftCodecV1.scope(planID: planID, round: round),
                purpose: .repetitiveCapture, codec: RepetitiveCaptureDraftCodecV1.release(),
                baseCanonicalRevision: 0, draftRevision: 1,
                payloadData: RepetitiveCaptureDraftCodecV1.encode(.source(planID: planID,
                    round: round, selection: selection)), stageIDs: [], resumeAnchor: .init(),
                state: .active, updatedAt: instant, mutationID: draftMutationID)
            _ = try RepetitiveCaptureDraftCodecV1.validateSourceCheckpoint(checkpoint)
            let mutation = try FieldDraftMutationV1(workspaceID: workspace, expectedRevision: 0,
                expectedBaseCanonicalRevision: 0, mutationID: draftMutationID,
                postImage: .createCheckpoint(checkpoint))
            _ = try h.writer.execute(.applyFieldDraft(mutation), mutationID: draftMutationID)
            let draft = try XCTUnwrap(h.context.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).first)
            XCTAssertEqual(try draft.value(), checkpoint)
            let draftBytes = draft.canonicalData
            let before = try h.rowCounts(in: h.context)
            let beforeRevision = try h.writer.currentRevision()
            func receiptBytes() throws -> [UUID: [Data?]] {
                let rows = try h.context.fetch(FetchDescriptor<MutationReceiptRow>())
                return Dictionary(uniqueKeysWithValues: rows.map {
                    ($0.mutationID, [$0.envelopeData, $0.receiptData,
                        $0.reversalBasisData, $0.semanticReversalData])
                })
            }
            let retained = try receiptBytes()
            let placements = Dictionary(uniqueKeysWithValues:
                try h.context.fetch(FetchDescriptor<AssetPlacementEventRow>()).map { ($0.id, $0.canonicalData) })
            let reversalID = try MutationIDV1(rawValue: UUID())
            let request = try reversalRequest(writer: h.writer, payload: payload, mutationID: reversalID)
            if includesCompensatedAsset {
                XCTAssertThrowsError(try h.writer.firstSignReversalEligibility(targetMutationID: s.mutationID)) {
                    XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidReversal)
                }
                XCTAssertThrowsError(try h.writer.executeSemanticReversal(request, targetMutationID: s.mutationID,
                    plan: payload.semanticPlan(expectedRevision: request.expectedRevision),
                    compensatingMutationIDs: [reversalID])) {
                    XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidReversal)
                }
                XCTAssertEqual(try h.rowCounts(in: h.context), before)
                XCTAssertEqual(try receiptBytes(), retained)
                let afterRevision = try h.writer.currentRevision()
                XCTAssertEqual(afterRevision.revision, beforeRevision.revision)
                XCTAssertEqual(afterRevision.entityRevisions, beforeRevision.entityRevisions)
                XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<DeletionLedgerRow>()), 0)
                XCTAssertNil(try h.store.receipt(mutationID: reversalID))
            } else {
                XCTAssertEqual(try h.writer.firstSignReversalEligibility(targetMutationID: s.mutationID).eligibility,
                    .eligible)
                _ = try h.writer.executeSemanticReversal(request, targetMutationID: s.mutationID,
                    plan: payload.semanticPlan(expectedRevision: request.expectedRevision),
                    compensatingMutationIDs: [reversalID])
                XCTAssertEqual(try h.context.fetch(FetchDescriptor<Asset>()).map(\.id), [unrelated.assetID])
                let ledger = try DeletionLedgerStore(context: h.context, privateSystemDiscoveryIndex: nil).snapshot()
                XCTAssertEqual(ledger.entries.map(\.identity), [try DeletionIdentityV2(kind: .asset, id: payload.assetID)])
                let afterReceipts = try receiptBytes()
                for (id, bytes) in retained { XCTAssertEqual(afterReceipts[id], bytes) }
                XCTAssertEqual(afterReceipts.count, retained.count + 1)
                XCTAssertNotNil(try h.store.receipt(mutationID: reversalID))
            }
            XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()), 1)
            XCTAssertEqual(draft.canonicalData, draftBytes)
            XCTAssertEqual(try draft.value(), checkpoint)
            XCTAssertEqual(Dictionary(uniqueKeysWithValues:
                try h.context.fetch(FetchDescriptor<AssetPlacementEventRow>()).map { ($0.id, $0.canonicalData) }), placements)
            XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<Site>()), before.sites)
            XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<MutationQuarantineRow>()), 0)
            XCTAssertFalse(h.context.hasChanges)
            try h.store.validateAll()
        }
    }

    @MainActor
    func testChangedCreatedAssetPostimageRefusesWithoutCompensationEffects() throws {
        let h = try harness(); defer { h.removeFiles() }
        let s = try h.makeScenario(); _ = try h.writer.execute(s.request)
        let payload = try XCTUnwrap(h.store.reversalBasis(mutationID: s.mutationID)?.firstSignCompensation)
        let asset = try XCTUnwrap(h.context.fetch(FetchDescriptor<Asset>()).first)
        asset.label = "Unexpected postimage"; try h.context.save()
        let before = try h.rowCounts(in: h.context)
        XCTAssertThrowsError(try h.writer.firstSignReversalEligibility(targetMutationID: s.mutationID))
        let id = try MutationIDV1(rawValue: UUID())
        let request = try reversalRequest(writer: h.writer, payload: payload, mutationID: id)
        XCTAssertThrowsError(try h.writer.executeSemanticReversal(request, targetMutationID: s.mutationID,
            plan: payload.semanticPlan(expectedRevision: request.expectedRevision),
            compensatingMutationIDs: [id]))
        XCTAssertEqual(try h.rowCounts(in: h.context), before)
        XCTAssertEqual(asset.label, "Unexpected postimage")
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<DeletionLedgerRow>()), 0)
        XCTAssertFalse(h.context.hasChanges)
    }

    @MainActor
    func testEveryAtomicBoundaryColdRecoversOneWholeCompensationAndRetryReplaysOnce() throws {
        for boundary in MutationJournalFaultBoundaryV1.allCases {
            let h = try harness(); defer { h.removeFiles() }
            let s = try h.makeScenario(); _ = try h.writer.execute(s.request)
            let payload = try XCTUnwrap(h.store.reversalBasis(mutationID: s.mutationID)?.firstSignCompensation)
            let cold = try h.reopen(failureInjection: .init(failOnceAt: boundary))
            let id = try MutationIDV1(rawValue: UUID())
            let request = try reversalRequest(writer: cold.writer, payload: payload, mutationID: id)
            XCTAssertThrowsError(try cold.writer.executeSemanticReversal(request, targetMutationID: s.mutationID,
                plan: payload.semanticPlan(expectedRevision: request.expectedRevision),
                compensatingMutationIDs: [id]))
            let recovered = try h.reopen()
            try recovered.store.validateAll()
            let completed = boundary == .afterSaveBeforeReturn
            XCTAssertEqual(try recovered.context.fetchCount(FetchDescriptor<Asset>()), completed ? 0 : 1)
            XCTAssertEqual(try recovered.context.fetchCount(FetchDescriptor<DeletionLedgerRow>()), completed ? 1 : 0)
            XCTAssertEqual(try recovered.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), completed ? 2 : 1)
            XCTAssertEqual(try recovered.context.fetchCount(FetchDescriptor<Site>()), 1)
            XCTAssertEqual(try recovered.context.fetchCount(FetchDescriptor<AssetPlacementEventRow>()), 1)
            let writerID = try recovered.writer.currentRevision().writerInstanceID
            let rebound = try WorkspaceExpectedRevisionV1(workspaceID: request.expectedRevision.workspaceID,
                generationID: request.expectedRevision.generationID, writerInstanceID: writerID,
                workspaceRevision: request.expectedRevision.workspaceRevision,
                entityRevisions: request.expectedRevision.entityRevisions)
            let retry = WorkspaceMutationRequestV1(mutationID: id, expectedRevision: rebound, command: request.command)
            _ = try recovered.writer.executeSemanticReversal(retry, targetMutationID: s.mutationID,
                plan: payload.semanticPlan(expectedRevision: retry.expectedRevision), compensatingMutationIDs: [id])
            _ = try recovered.writer.executeSemanticReversal(retry, targetMutationID: s.mutationID,
                plan: payload.semanticPlan(expectedRevision: retry.expectedRevision), compensatingMutationIDs: [id])
            XCTAssertEqual(try recovered.context.fetchCount(FetchDescriptor<Asset>()), 0)
            XCTAssertEqual(try recovered.context.fetchCount(FetchDescriptor<DeletionLedgerRow>()), 1)
            XCTAssertEqual(try recovered.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 2)
            try recovered.store.validateAll()
            XCTAssertFalse(recovered.context.hasChanges)
        }
    }

    @MainActor
    func testMissingPromisedExecutablePayloadFailsClosedWhileLegacyCanonicalBasisStaysExact() throws {
        let h = try harness(); defer { h.removeFiles() }
        let s = try h.makeScenario()
        let v = firstSign(s)
        let oldPlan = try SemanticReversalPlanV1(mutationID: s.mutationID, commandKind: .createFirstSign,
            expectedRevision: s.request.expectedRevision, prospectiveTargets: [.init(kind: .asset, id: v.assetID)],
            requiredSemanticValues: [], contentReferences: [], dependencyGraph: [], conflicts: [],
            compensatingCommands: [.deleteAsset(.init(deletionID: s.mutationID.rawValue,
                assetID: v.assetID, planDigest: String(repeating: "c", count: 64)))])
        let before = try h.rowCounts(in: h.context)
        XCTAssertThrowsError(try h.writer.execute(s.request, reversalPlan: oldPlan)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .invalidReversal)
        }
        XCTAssertEqual(try h.rowCounts(in: h.context), before)
        XCTAssertNil(try h.store.receipt(mutationID: s.mutationID))
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<DeletionLedgerRow>()), 0)
        XCTAssertFalse(h.context.hasChanges)
        _ = try h.writer.execute(s.request)
        let receipt = try XCTUnwrap(h.store.receipt(mutationID: s.mutationID))
        // This value-only legacy codec check never manufactures a historical
        // basis in the live store or changes the genuine new schema2 record.
        let basis = try ReversalBasisV1(targetMutationID: s.mutationID,
            targetReceiptIdentity: receipt.identity, plan: oldPlan)
        XCTAssertEqual(basis.schemaVersion, 1); XCTAssertNil(basis.firstSignCompensation)
        let bytes = try basis.canonicalData()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "targetMutationID", "targetReceiptIdentity", "policyVersion", "planDigest", "compensatingCommandKinds"])
        XCTAssertEqual(try ReversalBasisV1.decodeCanonical(from: bytes).canonicalData(), bytes)
        var promised = object; promised["schemaVersion"] = 2
        let missing = try JSONSerialization.data(withJSONObject: promised, options: [.sortedKeys, .withoutEscapingSlashes])
        XCTAssertThrowsError(try ReversalBasisV1.decodeCanonical(from: missing))
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<Asset>()), 1)
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 1)
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<DeletionLedgerRow>()), 0)
        XCTAssertFalse(h.context.hasChanges)
    }

    @MainActor
    func testDamagedPromisedExecutableBasisRefusesBeforeAnyCompensationEffect() throws {
        for damage in ["missing", "corrupt"] {
            let h = try harness(); defer { h.removeFiles() }
            let s = try h.makeScenario(); _ = try h.writer.execute(s.request)
            let row = try XCTUnwrap(h.context.fetch(FetchDescriptor<MutationReceiptRow>()).first)
            let originalBasis = try XCTUnwrap(row.reversalBasisData)
            let payload = try XCTUnwrap(h.store.reversalBasis(mutationID: s.mutationID)?.firstSignCompensation)
            var value = try XCTUnwrap(JSONSerialization.jsonObject(with: originalBasis) as? [String: Any])
            if damage == "missing" { value.removeValue(forKey: "firstSignCompensation") }
            else {
                var promised = try XCTUnwrap(value["firstSignCompensation"] as? [String: Any])
                promised["originalCommandSHA256"] = String(repeating: "0", count: 64)
                value["firstSignCompensation"] = promised
            }
            let hostile = try JSONSerialization.data(withJSONObject: value,
                options: [.sortedKeys, .withoutEscapingSlashes])
            row.reversalBasisData = hostile
            row.reversalBasisSHA256 = SHA256.hash(data: hostile).map { String(format: "%02x", $0) }.joined()
            try h.context.save()
            let before = try h.rowCounts(in: h.context)
            XCTAssertThrowsError(try h.writer.firstSignReversalEligibility(targetMutationID: s.mutationID))
            let id = try MutationIDV1(rawValue: UUID())
            let request = try reversalRequest(writer: h.writer, payload: payload, mutationID: id)
            XCTAssertThrowsError(try h.writer.executeSemanticReversal(request, targetMutationID: s.mutationID,
                plan: payload.semanticPlan(expectedRevision: request.expectedRevision), compensatingMutationIDs: [id]))
            XCTAssertEqual(try h.rowCounts(in: h.context), before)
            XCTAssertEqual(row.reversalBasisData, hostile)
            XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<DeletionLedgerRow>()), 0)
            XCTAssertFalse(h.context.hasChanges)
        }
    }

    @MainActor
    func testCompensatedAssetIdentityCannotBeRecreatedAndReversalReceiptReplaysCold() throws {
        let h = try harness(); defer { h.removeFiles() }
        let s = try h.makeScenario(); _ = try h.writer.execute(s.request)
        let payload = try XCTUnwrap(h.store.reversalBasis(mutationID: s.mutationID)?.firstSignCompensation)
        let id = try MutationIDV1(rawValue: UUID())
        let request = try reversalRequest(writer: h.writer, payload: payload, mutationID: id)
        let result = try h.writer.executeSemanticReversal(request, targetMutationID: s.mutationID,
            plan: payload.semanticPlan(expectedRevision: request.expectedRevision), compensatingMutationIDs: [id])
        let cold = try h.reopen(), writerID = try cold.writer.currentRevision().writerInstanceID
        let replay = try cold.writer.executeSemanticReversal(request, targetMutationID: s.mutationID,
            plan: payload.semanticPlan(expectedRevision: request.expectedRevision), compensatingMutationIDs: [id])
        XCTAssertEqual(replay.commandDigest, result.commandDigest)
        let v = firstSign(s)
        let recreated = WorkspaceCommandV1.createFirstSign(.init(siteID: v.siteID, newSite: nil,
            assetID: v.assetID, assetLabel: v.assetLabel, packID: v.packID, packSchemaVersion: v.packSchemaVersion,
            packContentVersion: v.packContentVersion, createdAt: v.createdAt))
        XCTAssertThrowsError(try cold.writer.execute(recreated, mutationID: MutationIDV1(rawValue: UUID())))
        XCTAssertEqual(try cold.context.fetchCount(FetchDescriptor<Asset>()), 0)
        XCTAssertEqual(try cold.context.fetchCount(FetchDescriptor<Site>()), 1)
        XCTAssertEqual(try cold.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 2)
        XCTAssertEqual(try cold.context.fetchCount(FetchDescriptor<DeletionLedgerRow>()), 1)
        XCTAssertFalse(cold.context.hasChanges)
    }

    @MainActor
    func testUnrelatedCalendarAndEvidenceAudienceMetadataRemainExactThroughCompensation() throws {
        let h = try harness(); defer { h.removeFiles() }
        let s = try h.makeScenario(); _ = try h.writer.execute(s.request)
        let metadata = try independentMetadata(workspaceID: h.identity.workspaceID)
        h.context.insert(metadata.calendar); h.context.insert(metadata.visibility)
        try h.context.save()
        let retained = (metadata.calendar.canonicalData, metadata.visibility.canonicalData)
        XCTAssertEqual(try metadata.calendar.value().workspaceID, h.identity.workspaceID)
        XCTAssertEqual(try metadata.visibility.value().workspaceID, h.identity.workspaceID)
        let preview = try h.writer.firstSignReversalEligibility(targetMutationID: s.mutationID)
        XCTAssertEqual(preview.eligibility, .eligible)
        let payload = try XCTUnwrap(preview.portablePlan?.firstSignCompensation)
        let id = try MutationIDV1(rawValue: UUID())
        let request = try reversalRequest(writer: h.writer, payload: payload, mutationID: id)
        _ = try h.writer.executeSemanticReversal(request, targetMutationID: s.mutationID,
            plan: payload.semanticPlan(expectedRevision: request.expectedRevision), compensatingMutationIDs: [id])
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<Asset>()), 0)
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<Site>()), 1)
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<ExceptionCalendarReleaseRow>()), 1)
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<EvidenceVisibilityRow>()), 1)
        XCTAssertEqual(metadata.calendar.canonicalData, retained.0)
        XCTAssertEqual(metadata.visibility.canonicalData, retained.1)
        _ = try metadata.calendar.value(); _ = try metadata.visibility.value()
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<DeletionLedgerRow>()), 1)
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), 2)
        try h.store.validateAll()
        XCTAssertFalse(h.context.hasChanges)
    }

    @MainActor
    func testUnrelatedMetadataNeverExemptsRealTypedAssetDependency() throws {
        let h = try harness(); defer { h.removeFiles() }
        let s = try h.makeScenario(); _ = try h.writer.execute(s.request)
        let payload = try XCTUnwrap(h.store.reversalBasis(mutationID: s.mutationID)?.firstSignCompensation)
        let metadata = try independentMetadata(workspaceID: h.identity.workspaceID)
        h.context.insert(metadata.calendar); h.context.insert(metadata.visibility)
        let instant = Date(timeIntervalSince1970: 1_800_000_000)
        let actor = try LocalActorReferenceV1(actorReferenceID: UUID(), workspaceID: h.identity.workspaceID,
            displayName: "C117 dependency recorder")
        let snapshot = try ActorSnapshotV1(snapshotID: UUID(), workspaceID: h.identity.workspaceID,
            actor: actor, responsibility: .recordedBy, displayNameAtTime: actor.displayName, capturedAt: instant)
        let temporal = try TemporalContextV1(occurredAtUTC: instant, recordedAtUTC: instant,
            localDate: "2027-01-15", localTime: "08:00:00", utcOffsetSeconds: 0,
            ianaTimeZoneIdentifier: "UTC", localTimeDisposition: .unambiguous)
        let dependency = try EvidenceContextV1(contextID: UUID(), workspaceID: h.identity.workspaceID,
            evidenceID: "c117.typed.context", evidenceSHA256: String(repeating: "f", count: 64),
            evidenceRevision: 1, assetID: payload.assetID, assetRevision: 1, temporalContext: temporal,
            userObserved: UserObservedEvidenceContextV1(condition: .unknown, observationNoteCode: "C117_CONTEXT"),
            derivedSolar: nil, controlExpectation: nil, predecessor: nil, revision: 1,
            mutationID: MutationIDV1(rawValue: UUID()), recordedBy: snapshot, recordedAt: instant.addingTimeInterval(1))
        let dependencyRow = try EvidenceContextRow(dependency); h.context.insert(dependencyRow)
        try h.context.save()
        let retained = (metadata.calendar.canonicalData, metadata.visibility.canonicalData, dependencyRow.canonicalData)
        let before = try h.rowCounts(in: h.context)
        XCTAssertThrowsError(try h.writer.firstSignReversalEligibility(targetMutationID: s.mutationID))
        let id = try MutationIDV1(rawValue: UUID())
        let request = try reversalRequest(writer: h.writer, payload: payload, mutationID: id)
        XCTAssertThrowsError(try h.writer.executeSemanticReversal(request, targetMutationID: s.mutationID,
            plan: payload.semanticPlan(expectedRevision: request.expectedRevision), compensatingMutationIDs: [id]))
        XCTAssertEqual(try h.rowCounts(in: h.context), before)
        XCTAssertEqual(metadata.calendar.canonicalData, retained.0)
        XCTAssertEqual(metadata.visibility.canonicalData, retained.1)
        XCTAssertEqual(dependencyRow.canonicalData, retained.2)
        XCTAssertEqual(try dependencyRow.value().assetID, payload.assetID)
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<DeletionLedgerRow>()), 0)
        XCTAssertNil(try h.store.receipt(mutationID: id))
        XCTAssertFalse(h.context.hasChanges)
    }

    @MainActor
    private func independentMetadata(workspaceID: WorkspaceID) throws
        -> (calendar: ExceptionCalendarReleaseRow, visibility: EvidenceVisibilityRow) {
        let instant = Date(timeIntervalSince1970: 1_700_000_010.125)
        let actor = try LocalActorReferenceV1(actorReferenceID: UUID(), workspaceID: workspaceID,
            displayName: "C117 calendar author")
        let snapshot = try ActorSnapshotV1(snapshotID: UUID(), workspaceID: workspaceID, actor: actor,
            responsibility: .recordedBy, displayNameAtTime: actor.displayName, capturedAt: instant)
        let range = ScheduleLocalDateRangeV1(startsOn: try ScheduleLocalDateV1("2026-01-01"),
            endsOn: try ScheduleLocalDateV1("2026-12-31"))
        let calendar = try ExceptionCalendarReleaseV1(workspaceID: workspaceID, calendarID: UUID(),
            releaseID: UUID(), name: "Independent calendar", ianaTimeZoneIdentifier: "UTC",
            effectiveRange: range, baseIncludedWeekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
            revision: 1, mutationID: MutationIDV1(rawValue: UUID()), authoredBy: snapshot, authoredAt: instant)
        let visibility = try EvidenceVisibilityV1(visibilityID: UUID(), workspaceID: workspaceID,
            sensitivity: .routine, allowedAudiences: [.internalReview, .customerReport], effectiveAt: instant,
            mutationID: MutationIDV1(rawValue: UUID()))
        return (try ExceptionCalendarReleaseRow(calendar), try EvidenceVisibilityRow(visibility))
    }

    @MainActor
    private func harness() throws -> FirstSignCompensationHarness {
        try .init(clockInstant: Date(timeIntervalSince1970: 1_700_000_010.125))
    }

    @MainActor
    private func firstSign(_ scenario: FirstSignCompensationHarness.Scenario) -> FirstSignMutationV1 {
        guard case let .createFirstSign(value) = scenario.command else { preconditionFailure("fixture command") }
        return value
    }

    @MainActor
    private func reversalRequest(writer: WorkspaceWriterV1, payload: FirstSignCompensationV1,
                                 mutationID: MutationIDV1) throws -> WorkspaceMutationRequestV1 {
        let current = try writer.currentRevision()
        let identity = try WorkspaceEntityIdentityV1(kind: .asset, id: payload.assetID)
        let values = Dictionary(uniqueKeysWithValues: current.entityRevisions.map { ($0.identity, $0.revision) })
        let expected = try WorkspaceExpectedRevisionV1(workspaceID: current.workspaceID, generationID: current.generationID,
            writerInstanceID: current.writerInstanceID, workspaceRevision: current.revision,
            entityRevisions: [.init(identity: identity, revision: values[identity, default: 0])])
        return .init(mutationID: mutationID, expectedRevision: expected, command: try payload.compensatingCommand())
    }
}

@MainActor
private final class FirstSignCompensationHarness {
    struct Scenario {
        let command: WorkspaceCommandV1
        let request: WorkspaceMutationRequestV1
        let mutationID: MutationIDV1
        let placementEventID: UUID
        let physicalEpisodeID: PhysicalPlacementEpisodeIDV1
        let createdAt: Date
    }

    struct RowCounts: Equatable {
        let sites: Int
        let assets: Int
        let placements: Int
        let receipts: Int
        let entityRevisions: Int
    }

    let root: URL
    let container: ModelContainer
    let context: ModelContext
    let registry: GenerationLeaseRegistryV1
    let fence: StaleWriterFenceV1
    let identity: WorkspaceReplicaIdentityV1
    let generationID: UUID
    let store: MutationJournalStoreV1
    let writer: WorkspaceWriterV1
    let clock: FirstSignCompensationClock

    init(clockInstant: Date) throws {
        clock = FirstSignCompensationClock(instant: clockInstant)
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V23-first-sign-compensation-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let release = PersistentSchemaReleaseRegistryV1.activeReleaseDescriptor
        let schema = Schema(release.models, version: release.versionIdentifier)
        container = try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [ModelConfiguration(
                "FirstSignCompensationClock",
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                cloudKitDatabase: .none
            )]
        )
        context = container.mainContext
        context.autosaveEnabled = false
        identity = try WorkspaceReplicaIdentityV1(
            workspaceID: WorkspaceID(rawValue: UUID()),
            replicaID: ReplicaID(rawValue: UUID())
        )
        generationID = UUID()
        let epoch = try GenerationEpochV1(
            generationID: generationID,
            generationManifestSHA256: String(repeating: "a", count: 64)
        )
        registry = try GenerationLeaseRegistryV1(applicationSupportURL: root)
        let lease = try registry.acquire(epoch: epoch, role: .writer)
        fence = try StaleWriterFenceV1(
            expectedGenerationEpoch: epoch,
            writerLeaseToken: lease,
            registry: registry,
            currentGenerationEpoch: { epoch }
        )
        store = try MutationJournalStoreV1(
            modelContext: context,
            identity: identity,
            generationID: generationID,
            staleWriterFence: fence
        )
        let writerInstanceID = UUID()
        writer = try WorkspaceWriterV1(
            identity: identity,
            generationID: generationID,
            initialRevision: store.currentRevision(
                writerInstanceID: writerInstanceID
            ),
            clock: clock,
            idSource: FirstSignCompensationIDs(value: writerInstanceID),
            fileAuthority: FirstSignCompensationFiles(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context),
            journalStore: store
        )
    }

    func makeScenario(
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000.375)
    ) throws -> Scenario {
        let siteID = UUID()
        let mutationID = try MutationIDV1(rawValue: UUID())
        let placementEventID = UUID()
        let physicalEpisodeID = try PhysicalPlacementEpisodeIDV1(rawValue: UUID())
        let assetID = UUID()
        let command = WorkspaceCommandV1.createFirstSign(FirstSignMutationV1(
            siteID: siteID,
            newSite: .init(
                id: siteID,
                label: "First Sign Clock Site",
                address: "10 Clock Street",
                timeZoneID: "UTC"
            ),
            assetID: assetID,
            assetLabel: "First Sign Clock Asset",
            packID: "test.first-sign-clock",
            packSchemaVersion: 1,
            packContentVersion: 1,
            createdAt: createdAt,
            initialPlacementMutationID: mutationID,
            initialPlacementEventID: placementEventID,
            initialPhysicalEpisodeID: physicalEpisodeID
        ))
        let current = try writer.currentRevision()
        let targets = try [
            WorkspaceEntityIdentityV1(kind: .site, id: siteID),
            WorkspaceEntityIdentityV1(kind: .asset, id: assetID),
            WorkspaceEntityIdentityV1(kind: .assetPlacementEvent, id: placementEventID),
        ]
        let known = Dictionary(
            uniqueKeysWithValues: current.entityRevisions.map {
                ($0.identity, $0.revision)
            }
        )
        let expected = try WorkspaceExpectedRevisionV1(
            workspaceID: current.workspaceID,
            generationID: current.generationID,
            writerInstanceID: current.writerInstanceID,
            workspaceRevision: current.revision,
            entityRevisions: targets.map {
                WorkspaceEntityRevisionV1(
                    identity: $0,
                    revision: known[$0, default: 0]
                )
            }
        )
        return Scenario(
            command: command,
            request: WorkspaceMutationRequestV1(
                mutationID: mutationID,
                expectedRevision: expected,
                command: command
            ),
            mutationID: mutationID,
            placementEventID: placementEventID,
            physicalEpisodeID: physicalEpisodeID,
            createdAt: createdAt
        )
    }

    func reopen(failureInjection: MutationJournalFailureInjectionV1? = nil) throws -> (
        context: ModelContext,
        store: MutationJournalStoreV1,
        writer: WorkspaceWriterV1
    ) {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let store = try MutationJournalStoreV1(
            modelContext: context,
            identity: identity,
            generationID: generationID,
            failureInjection: failureInjection,
            allowStateBootstrap: false,
            staleWriterFence: fence
        )
        let writerInstanceID = UUID()
        let writer = try WorkspaceWriterV1(
            identity: identity,
            generationID: generationID,
            initialRevision: store.currentRevision(
                writerInstanceID: writerInstanceID
            ),
            clock: clock,
            idSource: FirstSignCompensationIDs(value: writerInstanceID),
            fileAuthority: FirstSignCompensationFiles(),
            adapter: WorkspaceWriterAdapterV1(modelContext: context),
            journalStore: store
        )
        return (context, store, writer)
    }

    func rowCounts(in context: ModelContext) throws -> RowCounts {
        RowCounts(
            sites: try context.fetchCount(FetchDescriptor<Site>()),
            assets: try context.fetchCount(FetchDescriptor<Asset>()),
            placements: try context.fetchCount(
                FetchDescriptor<AssetPlacementEventRow>()
            ),
            receipts: try context.fetchCount(FetchDescriptor<MutationReceiptRow>()),
            entityRevisions: try context.fetchCount(
                FetchDescriptor<EntityMutationRevisionRow>()
            )
        )
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: root)
    }
}

private struct FirstSignCompensationClock: ApplicationClock {
    let instant: Date

    func now() -> Date {
        instant
    }
}

private struct FirstSignCompensationIDs: ApplicationIDSource {
    let value: UUID

    func makeID() -> UUID {
        value
    }
}

private struct FirstSignCompensationFiles: ApplicationFileAuthorityV1 {
    func temporaryRelativePath(
        mutationID: MutationIDV1,
        component: String
    ) throws -> String {
        "first-sign-compensation/\(mutationID.rawValue.uuidString.lowercased())/\(component)"
    }
}

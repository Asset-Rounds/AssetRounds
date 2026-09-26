import Darwin
import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V23CheckRunnerFrozenBeginPreparationTests: XCTestCase {
    func testCaptureSourceUsesAuthenticatedEntryAndClosedCanonicalRoundTripWithoutEffects() async throws {
        try await withAsyncFrozenBeginFixture("capture-source", entry: .check, storedTimeZoneID: "America/Chicago") { h in
            let before = try h.snapshot()
            let idCalls = h.ids.callCount
            let source = try h.captureSource()

            XCTAssertEqual(try h.snapshot(), before)
            XCTAssertEqual(h.ids.callCount, idCalls)
            XCTAssertEqual(source.sourceCheckpoint.draftID, h.read.chain.sourceCheckpoint.draftID)
            XCTAssertEqual(source.entryProgressCheckpoint.draftID, h.read.chain.nodes.last?.checkpoint.draftID)
            XCTAssertEqual(source.roundAtEntry, try h.read.chain.currentRound.reference)
            XCTAssertEqual(source.originalItem, h.originalItem)
            XCTAssertEqual(source.itemAtEntry, h.entryItem)
            XCTAssertEqual(source.assetID, h.assetID)
            XCTAssertEqual(source.packageRelease, try RoundPackageReleaseReferenceV1(h.publishedRelease))
            XCTAssertEqual(source.legacyPackageIdentity, try PackageReleaseIdentityV1(package: h.signPack))
            XCTAssertEqual(source.requestedEntry, .check)

            let bytes = try FieldDraftCanonicalCodecV1.encode(source)
            let decoded = try FieldDraftCanonicalCodecV1.decode(
                CheckRunnerRoundItemSourceV1.self, from: bytes
            )
            XCTAssertEqual(decoded, source)
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(decoded), bytes)
            try decoded.validate(read: h.read, publishedRelease: h.publishedRelease, signPack: h.signPack)
            try h.progress.validateHistoricalCheckRunnerSource(decoded, read: h.read,
                publishedRelease: h.publishedRelease, signPack: h.signPack)
            try h.runner.validateHistoricalCheckRunnerSource(decoded, read: h.read,
                progress: h.progress, publishedRelease: h.publishedRelease)
            XCTAssertEqual(try h.snapshot(), before)

            var unknown = try frozenBeginJSONObject(bytes)
            unknown["futureSourceAuthority"] = true
            assertSourceDecodeFails(unknown)
            var nested = try frozenBeginJSONObject(bytes)
            var request = try XCTUnwrap(nested["requestedEntry"] as? [String: Any])
            request["futureRequestAuthority"] = true
            nested["requestedEntry"] = request
            assertSourceDecodeFails(nested)
            var relationship = try frozenBeginJSONObject(bytes)
            relationship["entryProgressCheckpoint"] = relationship["sourceCheckpoint"]
            assertSourceDecodeFails(relationship)
            let object = try frozenBeginJSONObject(bytes)
            XCTAssertEqual(try decodeFrozenBeginJSON(CheckRunnerRoundItemSourceV1.self, object: object), source)
            let substitutions: [(String, String, Any)] = [
                ("entryProgressCheckpoint", "draftID", beginPreparationUUID(9_801).uuidString.lowercased()),
                ("entryProgressCheckpoint", "draftRevision", 2),
                ("entryProgressCheckpoint", "checkpointSHA256", String(repeating: "b", count: 64)),
                ("entryProgressCheckpoint", "mutationID", beginPreparationUUID(9_802).uuidString.lowercased()),
                ("sourceCheckpoint", "checkpointSHA256", String(repeating: "c", count: 64)),
                ("roundAtEntry", "sessionSHA256", String(repeating: "d", count: 64)),
            ]
            for (parentKey, field, value) in substitutions {
                var altered = object
                var nested = try XCTUnwrap(altered[parentKey] as? [String: Any])
                nested[field] = value; altered[parentKey] = nested
                let candidate = try decodeFrozenBeginJSON(CheckRunnerRoundItemSourceV1.self, object: altered)
                XCTAssertNotEqual(candidate, source)
                XCTAssertThrowsError(try h.progress.validateHistoricalCheckRunnerSource(candidate, read: h.read,
                    publishedRelease: h.publishedRelease, signPack: h.signPack), "\(parentKey).\(field)")
            }
            var alteredItems = object
            for key in ["originalItem", "itemAtEntry"] {
                var item = try XCTUnwrap(alteredItems[key] as? [String: Any])
                var selection = try XCTUnwrap(item["selection"] as? [String: Any])
                selection["labelAtSelection"] = "Rebound historical item"
                item["selection"] = selection; alteredItems[key] = item
            }
            let changedItem = try decodeFrozenBeginJSON(CheckRunnerRoundItemSourceV1.self, object: alteredItems)
            XCTAssertNotEqual(changedItem, source)
            XCTAssertThrowsError(try h.progress.validateHistoricalCheckRunnerSource(changedItem, read: h.read,
                publishedRelease: h.publishedRelease, signPack: h.signPack))
            XCTAssertThrowsError(try h.progress.validateHistoricalCheckRunnerSource(source, read: h.read,
                publishedRelease: frozenBeginShippingRelease(stage: .recheck), signPack: h.signPack))
            XCTAssertEqual(try h.snapshot(), before)
            XCTAssertEqual(h.ids.callCount, idCalls)

            let current = try await h.persistCurrentPhotoApplicationFixture()
            XCTAssertEqual(current.value.historicalSource, source)
            XCTAssertEqual(current.value.parentCheckpoint, current.value.parent.checkpoint)
            XCTAssertEqual(current.value.currentTarget.parent, current.value.parent)
            XCTAssertEqual(current.value.currentTarget.evidence.id,
                current.value.parent.child.target.command.evidenceID)
            XCTAssertEqual(current.value.currentTarget.laterPhotos, [])
            XCTAssertNil(current.value.currentTarget.finalization)
            try current.service.validateForPublication(current.value)
            XCTAssertEqual(current.mediaValue.targetRead.currentTarget,
                current.value.currentTarget)
            XCTAssertEqual(current.mediaValue.media.sourceInspection.sourceSHA256,
                current.mediaValue.media.rawReference.digests.digest(for: .sha256))
            XCTAssertEqual(current.mediaValue.media.rawReference.byteLength,
                Int64(current.sourceData.count))

            do {
                _ = try await h.runner.finalize(assetID: h.assetID,
                    selection: .noVisibleIssue,
                    completedAt: Date(timeIntervalSince1970: 1_789_323_470),
                    snapshotCreatedAt: Date(timeIntervalSince1970: 1_789_323_471),
                    sourceApp: .init(build: "photo-current-hostile", version: "1.0"))
                XCTFail("Non-CNV finalization must reject the close frontier")
            } catch {}
            let stillAtClose = try XCTUnwrap(current.service.readCurrentPhotoTarget(
                parentDraftID: current.value.parentCheckpoint.draftID,
                childDraftID: current.value.parent.slot.childDraftID))
            XCTAssertNil(stillAtClose.currentTarget.finalization)
            let stillAtCloseMediaRead = try await current.service.readCurrentPhotoMedia(
                parentDraftID: current.value.parentCheckpoint.draftID,
                childDraftID: current.value.parent.slot.childDraftID)
            let stillAtCloseMedia = try XCTUnwrap(stillAtCloseMediaRead)
            XCTAssertNil(stillAtCloseMedia.targetRead.currentTarget.finalization)
            try await current.service.validateForPublication(stillAtCloseMedia)
            _ = try await h.runner.finalize(assetID: h.assetID,
                selection: .couldNotVerify(reasonKey: "conditions_changed", note: nil),
                completedAt: Date(timeIntervalSince1970: 1_789_323_472),
                snapshotCreatedAt: Date(timeIntervalSince1970: 1_789_323_473),
                sourceApp: .init(build: "photo-current-close-cnv", version: "1.0"))
            let finalizedAtClose = try XCTUnwrap(current.service.readCurrentPhotoTarget(
                parentDraftID: current.value.parentCheckpoint.draftID,
                childDraftID: current.value.parent.slot.childDraftID))
            XCTAssertEqual(finalizedAtClose.currentTarget.laterPhotos, [])
            XCTAssertNotNil(finalizedAtClose.currentTarget.finalization)
            try current.service.validateForPublication(finalizedAtClose)
            let finalizedAtCloseMediaRead = try await current.service.readCurrentPhotoMedia(
                parentDraftID: current.value.parentCheckpoint.draftID,
                childDraftID: current.value.parent.slot.childDraftID)
            let finalizedAtCloseMedia = try XCTUnwrap(finalizedAtCloseMediaRead)
            XCTAssertEqual(finalizedAtCloseMedia.targetRead.currentTarget,
                finalizedAtClose.currentTarget)
            XCTAssertEqual(finalizedAtCloseMedia.media, current.mediaValue.media)
            try await current.service.validateForPublication(finalizedAtCloseMedia)
            let finalization = try XCTUnwrap(finalizedAtClose.currentTarget.finalization)
            var command = try XCTUnwrap(JSONSerialization.jsonObject(with:
                WorkspaceMutationCanonicalV1.data(finalization.envelope.command)) as? [String: Any])
            var finalize = try XCTUnwrap(command["finalizeCheck"] as? [String: Any])
            var value = try XCTUnwrap(finalize["_0"] as? [String: Any])
            var authority = try XCTUnwrap(value["writerAuthority"] as? [String: Any])
            var binding = try XCTUnwrap(authority["sourceBinding"] as? [String: Any])
            binding["sourceRecordID"] = beginPreparationUUID(39_999).uuidString
            authority["sourceBinding"] = binding; value["writerAuthority"] = authority
            finalize["_0"] = value; command["finalizeCheck"] = finalize
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
            let hostileCommand = try decoder.decode(WorkspaceCommandV1.self,
                from: JSONSerialization.data(withJSONObject: command))
            guard case let .finalizeCheck(hostileValue) = hostileCommand,
                  let hostileAuthority = hostileValue.writerAuthority else {
                return XCTFail("Expected hostile finalization authority")
            }
            XCTAssertThrowsError(try hostileAuthority.validate(command: hostileCommand))
        }
    }

    func testPrepareCheckFreezesStoredZoneCompleteCommandAndSourceCASWithoutEffects() async throws {
        // Exercise the actual pair/commit service and both frozen photo slots.
        try await withAsyncFrozenBeginFixture("production-photo-journey", entry: .check,
            storedTimeZoneID: "America/Chicago") { h in
            h.clock.value = Date(timeIntervalSinceReferenceDate: 811_300_000)
            let wide = try await FrozenProductionPhotoV1.make(h)
            h.clock.value = Date(timeIntervalSinceReferenceDate: 811_300_010.000002)
            let pairCheckpoint = try await wide.service.preparePhotoPair(parentDraftID: wide.parentID,
                childDraftID: wide.childID)
            XCTAssertEqual(pairCheckpoint.updatedAt, h.clock.millisecondValue)
            XCTAssertEqual(try wide.checkpoint(), pairCheckpoint)
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.decode(FieldDraftCheckpointV1.self,
                from: FieldDraftCanonicalCodecV1.encode(pairCheckpoint)), pairCheckpoint)
            let originalIDs = h.ids.callCount
            h.clock.value = h.clock.value.addingTimeInterval(50)
            let repeatedPair = try await wide.service.preparePhotoPair(parentDraftID: wide.parentID,
                childDraftID: wide.childID)
            XCTAssertEqual(repeatedPair, pairCheckpoint)
            XCTAssertEqual(h.ids.callCount, originalIDs)

            let payload = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(pairCheckpoint)
            let pair = try XCTUnwrap(payload.phase.pair)
            let validAttempt = try wide.attempt(pairCheckpoint: pairCheckpoint)
            let committedStage = try CheckRunnerPhotoContinuationEvidenceV1.committedStage(
                raw: pair.raw, attempt: validAttempt)
            let collision = try wide.attempt(pairCheckpoint: pairCheckpoint,
                reservationMutationID: committedStage.mutationID)
            let before = try h.snapshot()
            let markerURL = h.session.generationRootURL.appendingPathComponent(
                ".staging/evidence/\(wide.intent.evidenceID.uuidString.lowercased())/pair-publication.json")
            let markerBytes = try Data(contentsOf: markerURL)
            XCTAssertThrowsError(try wide.service.preparePhotoCommit(parentDraftID: wide.parentID,
                childDraftID: wide.childID, expectedCheckpointSHA256: pairCheckpoint.checkpointSHA256,
                proposal: collision))
            let fractional = try wide.attempt(pairCheckpoint: pairCheckpoint,
                instant: Date(timeIntervalSinceReferenceDate: 811_300_020.000002))
            XCTAssertNotEqual(try FieldDraftCanonicalCodecV1.decode(CheckRunnerPhotoCommitAttemptV1.self,
                from: FieldDraftCanonicalCodecV1.encode(fractional)), fractional)
            XCTAssertThrowsError(try wide.service.preparePhotoCommit(parentDraftID: wide.parentID,
                childDraftID: wide.childID, expectedCheckpointSHA256: pairCheckpoint.checkpointSHA256,
                proposal: fractional))
            XCTAssertEqual(try h.snapshot(), before)
            XCTAssertEqual(try Data(contentsOf: markerURL), markerBytes)
            XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<DraftCommitSagaRow>()), 0)
            XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<DraftContentReservationRow>()), 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: h.session.generationRootURL
                .appendingPathComponent("evidence/\(wide.intent.evidenceID.uuidString.lowercased())").path))

            let committing = try wide.service.preparePhotoCommit(parentDraftID: wide.parentID,
                childDraftID: wide.childID, expectedCheckpointSHA256: pairCheckpoint.checkpointSHA256,
                proposal: validAttempt)
            let committed = try await wide.service.resumePhotoCommit(parentDraftID: wide.parentID,
                childDraftID: wide.childID)
            XCTAssertEqual(committed.state, .committed)
            XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
            let terminal = try XCTUnwrap(h.coordinator.workspaceWriter.checkRunnerPhotoCommitEvidence(
                workspaceID: h.workspaceID, draftID: wide.childID))
            XCTAssertEqual(terminal.reconstruction.draftCommit.checkpoint, committing)
            XCTAssertEqual(terminal.stage, committedStage)
            XCTAssertEqual(terminal.reservation.createdAt, validAttempt.promotionAt)
            let wideMediaRead = try await wide.service.readCurrentPhotoMedia(parentDraftID: wide.parentID,
                childDraftID: wide.childID)
            let wideMedia = try XCTUnwrap(wideMediaRead)
            XCTAssertEqual(wideMedia.media.normalizedPair, pair.normalizedPair)
            let postWide = try h.snapshot()
            let postWideIDs = h.ids.callCount
            h.clock.value = h.clock.value.addingTimeInterval(500)
            let reopened = try FrozenProductionPhotoV1.reopen(owner: h.coordinator, root: h.root,
                profile: h.profile, release: h.publishedRelease, clock: h.clock, ids: h.ids)
            let repeated = try await reopened.service.resumePhotoCommit(parentDraftID: wide.parentID,
                childDraftID: wide.childID)
            XCTAssertEqual(repeated, committed)
            XCTAssertEqual(try h.snapshot(), postWide)
            XCTAssertEqual(h.ids.callCount, postWideIDs)

            let close = try await FrozenProductionPhotoV1.make(h, parentID: wide.parentID, step: .close)
            let closePair = try await close.service.preparePhotoPair(parentDraftID: close.parentID,
                childDraftID: close.childID)
            let closeAttempt = try close.attempt(pairCheckpoint: closePair)
            XCTAssertEqual(closeAttempt.expectedWorkflowRecordRevision, 2)
            _ = try close.service.preparePhotoCommit(parentDraftID: close.parentID, childDraftID: close.childID,
                expectedCheckpointSHA256: closePair.checkpointSHA256, proposal: closeAttempt)
            let closeCommitted = try await close.service.resumePhotoCommit(parentDraftID: close.parentID,
                childDraftID: close.childID)
            XCTAssertEqual(closeCommitted.state, .committed)
            let parent = try CheckRunnerItemDraftCodecV1.validateCheckpoint(close.service.read(draftID: close.parentID))
            XCTAssertEqual(parent.field.wideContext?.childDraftID, wide.childID)
            XCTAssertEqual(parent.field.closeDetail?.childDraftID, close.childID)
            let currentWide = try XCTUnwrap(close.service.readCurrentPhotoTarget(parentDraftID: wide.parentID,
                childDraftID: wide.childID))
            XCTAssertEqual(currentWide.currentTarget.laterPhotos.count, 1)
            XCTAssertEqual(currentWide.currentTarget.workflow.draftStepKey, WorkflowDraftStep.outcome.rawValue)
            let currentWideMediaRead = try await close.service.readCurrentPhotoMedia(parentDraftID: wide.parentID,
                childDraftID: wide.childID)
            XCTAssertEqual(try XCTUnwrap(currentWideMediaRead).media, wideMedia.media)
            XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<EvidenceFile>()), 2)
            XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<DraftCommitSagaRow>()), 10)
        }

        try await withAsyncFrozenBeginFixture("photo-existing-derived-mutation", entry: .check,
            storedTimeZoneID: "America/Chicago") { h in
            let photo = try await FrozenProductionPhotoV1.make(h)
            let checkpoint = try await photo.service.preparePhotoPair(parentDraftID: photo.parentID,
                childDraftID: photo.childID)
            let attempt = try photo.attempt(pairCheckpoint: checkpoint)
            let raw = try XCTUnwrap(CheckRunnerPhotoDraftCodecV1.validateCheckpoint(checkpoint).phase.raw)
            let occupied = try CheckRunnerPhotoContinuationEvidenceV1.committedStage(raw: raw, attempt: attempt).mutationID
            let siteID = UUID()
            _ = try h.coordinator.workspaceWriter.execute(.createFirstSign(.init(siteID: siteID,
                newSite: .init(id: siteID, label: "Unrelated receipt", address: nil, timeZoneID: "America/Chicago"),
                assetID: UUID(), assetLabel: "Independent sign", packID: h.signPack.packID,
                packSchemaVersion: h.signPack.schemaVersion, packContentVersion: h.signPack.contentVersion,
                createdAt: h.clock.millisecondValue, initialPlacementMutationID: occupied,
                initialPlacementEventID: UUID(), initialPhysicalEpisodeID: .init(rawValue: UUID()))), mutationID: occupied)
            let before = try h.snapshot()
            XCTAssertThrowsError(try photo.service.preparePhotoCommit(parentDraftID: photo.parentID,
                childDraftID: photo.childID, expectedCheckpointSHA256: checkpoint.checkpointSHA256, proposal: attempt))
            XCTAssertEqual(try h.snapshot(), before)
            XCTAssertEqual(try photo.checkpoint(), checkpoint)
            XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<DraftCommitSagaRow>()), 0)
            XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<DraftContentReservationRow>()), 0)
        }

        try await withAsyncFrozenBeginFixture("stored-zone-check", entry: .check,
                                   storedTimeZoneID: "America/Chicago") { h in
            let source = try h.captureSource()
            let before = try h.snapshot()
            let recordID = beginPreparationUUID(9_001)
            h.ids.enqueue([recordID])
            let idCalls = h.ids.callCount
            let submittedAt = Date(timeIntervalSince1970: 1_789_123_456.789)
            let submission = BeginDraftSubmission(
                assetID: h.assetID, requestedStage: .check, issueID: nil,
                observedAtUTC: submittedAt,
                confirmedTimeZoneID: " Mars/Olympus is ignored because the stored zone wins ",
                afterDarkAccepted: true, safePositionAccepted: true
            )

            let attempt = try h.runner.prepareFrozenBegin(
                source: source, progress: h.progress,
                publishedRelease: h.publishedRelease, submission: submission
            )

            XCTAssertEqual(h.ids.callCount, idCalls + 1)
            XCTAssertEqual(try h.snapshot(), before)
            XCTAssertEqual(attempt.source, source)
            XCTAssertEqual(attempt.sourceWorkspaceID, h.workspaceID)
            XCTAssertEqual(attempt.recordMutationID.rawValue, recordID)
            XCTAssertEqual(attempt.recordCommittedAt, h.clock.millisecondValue)
            XCTAssertNil(attempt.timeZone)
            XCTAssertEqual(attempt.siteID, h.siteID)
            XCTAssertEqual(attempt.resolvedSiteTimeZoneID, "America/Chicago")
            XCTAssertEqual(attempt.recordExpectedEntityRevisions,
                           try h.expectedRecordRevisions(recordID: recordID))
            XCTAssertEqual(attempt.recordCommand,
                           try h.expectedCommand(recordID: recordID, observedAt: submittedAt,
                                                 timeZoneID: "America/Chicago", parentID: nil))
            try h.runner.validateHistoricalCheckRunnerSource(source, read: h.read,
                progress: h.progress, publishedRelease: h.publishedRelease)

            let sourceBytes = try FieldDraftCanonicalCodecV1.encode(source)
            let attemptBytes = try FieldDraftCanonicalCodecV1.encode(attempt)
            let decoded = try FieldDraftCanonicalCodecV1.decode(
                CheckRunnerFrozenBeginAttemptV1.self, from: attemptBytes
            )
            XCTAssertEqual(decoded, attempt)
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(decoded), attemptBytes)
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(decoded.source), sourceBytes)
            XCTAssertEqual(try h.snapshot(), before)
        }
    }

    func testPrepareRecheckFreezesExplicitIssueParentAndOptionalZoneCommandWithoutEffects() async throws {
        let issueID = beginPreparationUUID(9_101)
        try await withAsyncFrozenBeginFixture("missing-zone-recheck", entry: .recheck(issueID: issueID),
                                   storedTimeZoneID: nil) { h in
            let source = try h.captureSource()
            let before = try h.snapshot()
            let recordID = beginPreparationUUID(9_102)
            let zoneMutationID = beginPreparationUUID(9_103)
            h.ids.enqueue([recordID, zoneMutationID])
            let idCalls = h.ids.callCount
            let submittedAt = Date(timeIntervalSince1970: 1_789_223_456.123)
            let submission = BeginDraftSubmission(
                assetID: h.assetID, requestedStage: .recheck, issueID: issueID,
                observedAtUTC: submittedAt, confirmedTimeZoneID: " America/New_York ",
                afterDarkAccepted: true, safePositionAccepted: true
            )

            let attempt = try h.runner.prepareFrozenBegin(
                source: source, progress: h.progress,
                publishedRelease: h.publishedRelease, submission: submission
            )

            XCTAssertEqual(h.ids.callCount, idCalls + 2)
            XCTAssertEqual(try h.snapshot(), before)
            XCTAssertEqual(attempt.source, source)
            XCTAssertEqual(attempt.recordMutationID.rawValue, recordID)
            XCTAssertEqual(attempt.recordCommand.stage, WorkflowStage.recheck.rawValue)
            XCTAssertEqual(attempt.recordCommand.issueID, issueID)
            XCTAssertEqual(attempt.recordCommand.parentRecordID, h.recheckParentID)
            XCTAssertEqual(attempt.recordExpectedEntityRevisions,
                           try h.expectedRecordRevisions(recordID: recordID))
            XCTAssertEqual(attempt.recordCommand,
                           try h.expectedCommand(recordID: recordID, observedAt: submittedAt,
                                                 timeZoneID: "America/New_York",
                                                 parentID: h.recheckParentID))
            let zone = try XCTUnwrap(attempt.timeZone)
            XCTAssertEqual(zone.mutationID.rawValue, zoneMutationID)
            XCTAssertEqual(zone.command.siteID, h.siteID)
            XCTAssertEqual(zone.command.timeZoneID, "America/New_York")
            XCTAssertEqual(zone.command.confirmedAt, submittedAt)
            XCTAssertEqual(zone.committedAt, h.clock.millisecondValue)
            let current = try h.coordinator.workspaceWriter.currentRevision()
            let siteIdentity = try WorkspaceEntityIdentityV1(kind: .site, id: h.siteID)
            XCTAssertEqual(zone.expectedSiteRevision, try XCTUnwrap(
                current.entityRevisions.first { $0.identity == siteIdentity }
            ).revision)
            try h.runner.validateHistoricalCheckRunnerSource(source, read: h.read,
                progress: h.progress, publishedRelease: h.publishedRelease)
            XCTAssertEqual(try h.snapshot(), before)
        }
    }

    func testInvalidPreflightRequestPackageAndAccessAllocateNoIDsOrEffects() async throws {
        try await withAsyncFrozenBeginFixture("invalid-preflight", entry: .check, storedTimeZoneID: nil) { h in
            let source = try h.captureSource()
            let valid = BeginDraftSubmission(
                assetID: h.assetID, requestedStage: .check, issueID: nil,
                observedAtUTC: Date(timeIntervalSince1970: 1_789_323_456),
                confirmedTimeZoneID: "America/New_York",
                afterDarkAccepted: true, safePositionAccepted: true
            )
            let otherRelease = try frozenBeginShippingRelease(stage: .recheck)
            try h.runner.validateHistoricalCheckRunnerSource(source, read: h.read,
                progress: h.progress, publishedRelease: h.publishedRelease)
            XCTAssertThrowsError(try h.runner.validateHistoricalCheckRunnerSource(source, read: h.read,
                progress: h.progress, publishedRelease: otherRelease))
            let cases: [(String, InspectionPackageReleaseV1, BeginDraftSubmission)] = [
                ("missing-observation", h.publishedRelease, .init(
                    assetID: valid.assetID, requestedStage: .check, issueID: nil,
                    observedAtUTC: nil, confirmedTimeZoneID: valid.confirmedTimeZoneID,
                    afterDarkAccepted: true, safePositionAccepted: true)),
                ("missing-zone", h.publishedRelease, .init(
                    assetID: valid.assetID, requestedStage: .check, issueID: nil,
                    observedAtUTC: valid.observedAtUTC, confirmedTimeZoneID: nil,
                    afterDarkAccepted: true, safePositionAccepted: true)),
                ("invalid-zone", h.publishedRelease, .init(
                    assetID: valid.assetID, requestedStage: .check, issueID: nil,
                    observedAtUTC: valid.observedAtUTC, confirmedTimeZoneID: "Mars/Olympus",
                    afterDarkAccepted: true, safePositionAccepted: true)),
                ("missing-after-dark", h.publishedRelease, .init(
                    assetID: valid.assetID, requestedStage: .check, issueID: nil,
                    observedAtUTC: valid.observedAtUTC, confirmedTimeZoneID: valid.confirmedTimeZoneID,
                    afterDarkAccepted: false, safePositionAccepted: true)),
                ("missing-safe-position", h.publishedRelease, .init(
                    assetID: valid.assetID, requestedStage: .check, issueID: nil,
                    observedAtUTC: valid.observedAtUTC, confirmedTimeZoneID: valid.confirmedTimeZoneID,
                    afterDarkAccepted: true, safePositionAccepted: false)),
                ("asset-mismatch", h.publishedRelease, .init(
                    assetID: beginPreparationUUID(9_204), requestedStage: .check, issueID: nil,
                    observedAtUTC: valid.observedAtUTC, confirmedTimeZoneID: valid.confirmedTimeZoneID,
                    afterDarkAccepted: true, safePositionAccepted: true)),
                ("request-mismatch", h.publishedRelease, .init(
                    assetID: valid.assetID, requestedStage: .recheck,
                    issueID: beginPreparationUUID(9_205), observedAtUTC: valid.observedAtUTC,
                    confirmedTimeZoneID: valid.confirmedTimeZoneID,
                    afterDarkAccepted: true, safePositionAccepted: true)),
                ("package-mismatch", otherRelease, valid),
            ]
            for (label, release, submission) in cases {
                let before = try h.snapshot()
                let idCalls = h.ids.callCount
                XCTAssertThrowsError(try h.runner.prepareFrozenBegin(
                    source: source, progress: h.progress,
                    publishedRelease: release, submission: submission
                ), label)
                XCTAssertEqual(h.ids.callCount, idCalls, label)
                XCTAssertEqual(try h.snapshot(), before, label)
            }

            let denied = try h.makeRunner(draftAccessState: { .formerPaidInactive })
            let before = try h.snapshot()
            let idCalls = h.ids.callCount
            XCTAssertThrowsError(try denied.captureFrozenBeginSource(
                read: h.read, progress: h.progress, itemID: h.itemID,
                publishedRelease: h.publishedRelease, requestedEntry: .check
            )) { error in
                XCTAssertEqual(error as? CheckRunnerCoordinatorError,
                               .accessDenied(.blockPaid))
            }
            XCTAssertThrowsError(try denied.prepareFrozenBegin(
                source: source, progress: h.progress, publishedRelease: h.publishedRelease,
                submission: valid
            ))
            XCTAssertEqual(h.ids.callCount, idCalls)
            XCTAssertEqual(try h.snapshot(), before)
        }
    }

    func testChangedSourceForeignOwnerDirtyContextCompatibilityAndInvalidSessionFailWithoutPreparationEffects() async throws {
        try await withAsyncFrozenBeginFixture("changed-source", entry: .check,
                                   storedTimeZoneID: "America/New_York") { h in
            let source = try h.captureSource()
            let current = try await h.persistCurrentPhotoApplicationFixture()
            let latest = try h.progress.read(sourceDraftID: source.sourceCheckpoint.draftID)
            try h.progress.validateHistoricalCheckRunnerSource(source, read: latest,
                publishedRelease: h.publishedRelease, signPack: h.signPack)
            let next = try h.progress.prepareStep(
                read: latest, action: .keepOpenAndNext, focus: .facts,
                completionRecordID: nil, recordedByName: "Advance after frozen entry"
            )
            _ = try h.progress.persistStep(next)
            h.read = try h.progress.read(sourceDraftID: source.sourceCheckpoint.draftID)
            let before = try h.snapshot()
            let idCalls = h.ids.callCount
            try h.progress.validateHistoricalCheckRunnerSource(source, read: h.read,
                publishedRelease: h.publishedRelease, signPack: h.signPack)
            try h.runner.validateHistoricalCheckRunnerSource(source, read: h.read,
                progress: h.progress, publishedRelease: h.publishedRelease)
            let refreshed = try XCTUnwrap(current.service.readCurrentPhotoTarget(
                parentDraftID: current.value.parentCheckpoint.draftID,
                childDraftID: current.value.parent.slot.childDraftID))
            XCTAssertEqual(refreshed.historicalSource, source)
            XCTAssertThrowsError(try current.service.validateForPublication(current.value))
            try current.service.validateForPublication(refreshed)
            do {
                try await current.service.validateForPublication(current.mediaValue)
                XCTFail("Saved media read must reject a later source revision")
            } catch {}
            let refreshedMediaRead = try await current.service.readCurrentPhotoMedia(
                parentDraftID: current.value.parentCheckpoint.draftID,
                childDraftID: current.value.parent.slot.childDraftID)
            let refreshedMedia = try XCTUnwrap(refreshedMediaRead)
            XCTAssertEqual(refreshedMedia.targetRead.currentTarget, refreshed.currentTarget)
            try await current.service.validateForPublication(refreshedMedia)
            XCTAssertThrowsError(try h.progress.validateHistoricalCheckRunnerSource(source, read: latest,
                publishedRelease: h.publishedRelease, signPack: h.signPack))
            XCTAssertThrowsError(try h.captureSource())
            XCTAssertThrowsError(try h.runner.prepareFrozenBegin(
                source: source, progress: h.progress,
                publishedRelease: h.publishedRelease, submission: h.validSubmission()
            ))
            XCTAssertEqual(h.ids.callCount, idCalls)
            XCTAssertEqual(try h.snapshot(), before)
        }

        try await withAsyncFrozenBeginFixture("foreign-owner", entry: .check,
                                   storedTimeZoneID: "America/New_York") { h in
            let source = try h.captureSource()
            let current = try await h.persistCurrentPhotoApplicationFixture()
            let foreignProgress = try h.coordinator.makeRepetitiveCaptureProgressService(
                transitions: h.transitions
            )
            let foreignService = try ProductionCheckRunnerItemDraftServiceV1(session: h.coordinator,
                progress: foreignProgress, coordinator: h.runner,
                publishedRelease: h.publishedRelease, clock: h.clock, ids: h.ids)
            let before = try h.snapshot()
            let idCalls = h.ids.callCount
            XCTAssertThrowsError(try foreignProgress.validateHistoricalCheckRunnerSource(source, read: h.read,
                publishedRelease: h.publishedRelease, signPack: h.signPack))
            XCTAssertThrowsError(try h.runner.captureFrozenBeginSource(
                read: h.read, progress: foreignProgress, itemID: h.itemID,
                publishedRelease: h.publishedRelease, requestedEntry: .check
            ))
            XCTAssertThrowsError(try foreignService.validateForPublication(current.value))
            do {
                try await foreignService.validateForPublication(current.mediaValue)
                XCTFail("Foreign media-read owner must reject publication")
            } catch {}
            XCTAssertEqual(h.ids.callCount, idCalls)
            XCTAssertEqual(try h.snapshot(), before)

            let closeCandidate = try await h.runner.importCandidate(assetID: h.assetID,
                sourceData: WorkCanonicalIntegrationTestSupportV1.makePNG(seed: 202),
                createdAt: Date(timeIntervalSince1970: 1_789_323_480))
            _ = try await h.runner.accept(candidate: closeCandidate, assetID: h.assetID)
            _ = try await h.runner.finalize(assetID: h.assetID, selection: .noVisibleIssue,
                completedAt: Date(timeIntervalSince1970: 1_789_323_481),
                snapshotCreatedAt: Date(timeIntervalSince1970: 1_789_323_482),
                sourceApp: .init(build: "photo-current-outcome", version: "1.0"))
            let finalizedAtOutcome = try XCTUnwrap(current.service.readCurrentPhotoTarget(
                parentDraftID: current.value.parentCheckpoint.draftID,
                childDraftID: current.value.parent.slot.childDraftID))
            XCTAssertEqual(finalizedAtOutcome.currentTarget.laterPhotos.map(\.command.evidenceID),
                [closeCandidate.id])
            XCTAssertNotNil(finalizedAtOutcome.currentTarget.finalization)
            try current.service.validateForPublication(finalizedAtOutcome)
            let finalizedAtOutcomeMediaRead = try await current.service.readCurrentPhotoMedia(
                parentDraftID: current.value.parentCheckpoint.draftID,
                childDraftID: current.value.parent.slot.childDraftID)
            let finalizedAtOutcomeMedia = try XCTUnwrap(finalizedAtOutcomeMediaRead)
            XCTAssertEqual(finalizedAtOutcomeMedia.targetRead.currentTarget,
                finalizedAtOutcome.currentTarget)
            XCTAssertEqual(finalizedAtOutcomeMedia.media, current.mediaValue.media)
            try await current.service.validateForPublication(finalizedAtOutcomeMedia)
        }

        try await withAsyncFrozenBeginFixture("dirty-context", entry: .check,
                                   storedTimeZoneID: "America/New_York") { h in
            let source = try h.captureSource()
            let current = try await h.persistCurrentPhotoApplicationFixture()
            let site = try XCTUnwrap(h.context.fetch(FetchDescriptor<Site>()).first { $0.id == h.siteID })
            site.label = "Unsaved hostile label"
            XCTAssertTrue(h.context.hasChanges)
            let before = try h.rowSnapshot()
            let idCalls = h.ids.callCount
            XCTAssertThrowsError(try h.progress.validateHistoricalCheckRunnerSource(source, read: h.read,
                publishedRelease: h.publishedRelease, signPack: h.signPack))
            XCTAssertThrowsError(try h.runner.prepareFrozenBegin(
                source: source, progress: h.progress,
                publishedRelease: h.publishedRelease, submission: h.validSubmission()
            ))
            XCTAssertThrowsError(try current.service.validateForPublication(current.value))
            do {
                try await current.service.validateForPublication(current.mediaValue)
                XCTFail("Dirty context must reject media publication validation")
            } catch {}
            XCTAssertEqual(h.ids.callCount, idCalls)
            XCTAssertEqual(try h.rowSnapshot(), before)
            XCTAssertTrue(h.context.hasChanges)
            h.context.rollback()
        }

        try await withAsyncFrozenBeginFixture("invalid-session", entry: .check,
                                   storedTimeZoneID: "America/New_York") { h in
            let source = try h.captureSource()
            let current = try await h.persistCurrentPhotoApplicationFixture()
            let compatibility = CheckRunnerCoordinator(
                modelContext: h.context, signPack: h.signPack,
                clock: h.clock, idSource: h.ids
            )
            let before = try h.rowSnapshot()
            let idCalls = h.ids.callCount
            XCTAssertThrowsError(try compatibility.captureFrozenBeginSource(
                read: h.read, progress: h.progress, itemID: h.itemID,
                publishedRelease: h.publishedRelease, requestedEntry: .check
            )) { error in
                XCTAssertEqual(error as? CheckRunnerCoordinatorError,
                               .packageLifecycleMismatch)
            }
            XCTAssertEqual(h.ids.callCount, idCalls)
            XCTAssertEqual(try h.rowSnapshot(), before)
            try h.closeCoordinator()
            XCTAssertThrowsError(try current.service.validateForPublication(current.value))
            do {
                try await current.service.validateForPublication(current.mediaValue)
                XCTFail("Invalidated session must reject media publication validation")
            } catch {}
            XCTAssertThrowsError(try h.progress.validateHistoricalCheckRunnerSource(source, read: h.read,
                publishedRelease: h.publishedRelease, signPack: h.signPack))
            XCTAssertThrowsError(try h.runner.prepareFrozenBegin(
                source: source, progress: h.progress,
                publishedRelease: h.publishedRelease, submission: h.validSubmission()
            ))
            XCTAssertEqual(h.ids.callCount, idCalls)
            XCTAssertEqual(try h.rowSnapshot(), before)
        }

        try await withAsyncFrozenBeginFixture("completed-item-history", entry: .check,
                                   storedTimeZoneID: "America/New_York") { h in
            let source = try h.captureSource()
            let current = try await h.persistCurrentPhotoApplicationFixture()
            let entry = try XCTUnwrap(h.read.chain.nodes.last)
            let round = h.read.chain.currentRound
            // This fixture proves journal/source correspondence. Finalization's
            // completed-record authority is tested by its own target-reader cases.
            let completion = try RoundItemCompletionReferenceV1(completionID: beginPreparationUUID(9_250),
                revision: 1, completionSHA256: String(repeating: "a", count: 64))
            let prepared = try h.transitions.prepareItem(expected: round, itemID: h.itemID,
                transition: .completeItem, completion: completion, recordedByName: "Complete fixture item")
            let mutation = try h.transitions.repetitiveCaptureMutation(for: prepared)
            let anchor = try DraftResumeAnchorV1(sectionID: "facts", selectedStableID: nil)
            let step = try RepetitiveCaptureProgressStepV2(source: source.sourceCheckpoint,
                prior: source.entryProgressCheckpoint, priorRoundReceipt: entry.roundReceipt,
                expectedRound: round, itemID: h.itemID, action: .complete, roundMutation: mutation,
                requirementFocus: .facts, resumeAnchor: anchor)
            let checkpoint = try FieldDraftCheckpointV1(draftID: beginPreparationUUID(9_251),
                workspaceID: h.workspaceID, scope: h.read.chain.sourceCheckpoint.scope,
                purpose: .repetitiveCapture, codec: RepetitiveCaptureProgressDraftCodecV2.release(),
                baseCanonicalRevision: round.revision, draftRevision: 1,
                payloadData: RepetitiveCaptureProgressDraftCodecV2.encode(.progress(step)), stageIDs: [],
                resumeAnchor: anchor, state: .active, updatedAt: h.clock.millisecondValue,
                mutationID: .init(rawValue: beginPreparationUUID(9_252)))
            let adapter = try h.coordinator.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: h.context)
            _ = try adapter.persistRepetitiveCaptureProgressStep(checkpoint)
            h.read = try h.progress.read(sourceDraftID: source.sourceCheckpoint.draftID)
            XCTAssertTrue(try XCTUnwrap(h.read.chain.nodes.last).isPendingRoundEffect)
            var before = try h.snapshot()
            let idCalls = h.ids.callCount
            // The pending later effect does not erase the already receipted ENTRY.
            try h.progress.validateHistoricalCheckRunnerSource(source, read: h.read,
                publishedRelease: h.publishedRelease, signPack: h.signPack)
            let pendingCurrent = try XCTUnwrap(current.service.readCurrentPhotoTarget(
                parentDraftID: current.value.parentCheckpoint.draftID,
                childDraftID: current.value.parent.slot.childDraftID))
            try current.service.validateForPublication(pendingCurrent)
            let pendingMediaRead = try await current.service.readCurrentPhotoMedia(
                parentDraftID: current.value.parentCheckpoint.draftID,
                childDraftID: current.value.parent.slot.childDraftID)
            let pendingMedia = try XCTUnwrap(pendingMediaRead)
            XCTAssertEqual(pendingMedia.targetRead.currentTarget, pendingCurrent.currentTarget)
            try await current.service.validateForPublication(pendingMedia)
            XCTAssertThrowsError(try h.captureSource())
            XCTAssertEqual(try h.snapshot(), before)

            _ = try h.coordinator.workspaceWriter.commitRoundSession(mutation)
            h.read = try h.progress.read(sourceDraftID: source.sourceCheckpoint.draftID)
            XCTAssertEqual(h.read.chain.nodes.last?.step.action, .complete)
            XCTAssertEqual(h.read.chain.currentRound.items.first?.disposition, .completed)
            XCTAssertFalse(try XCTUnwrap(h.read.chain.nodes.last).isPendingRoundEffect)
            before = try h.snapshot()
            try h.progress.validateHistoricalCheckRunnerSource(source, read: h.read,
                publishedRelease: h.publishedRelease, signPack: h.signPack)
            let completedCurrent = try XCTUnwrap(current.service.readCurrentPhotoTarget(
                parentDraftID: current.value.parentCheckpoint.draftID,
                childDraftID: current.value.parent.slot.childDraftID))
            XCTAssertEqual(completedCurrent.historicalSource, source)
            try current.service.validateForPublication(completedCurrent)
            let completedMediaRead = try await current.service.readCurrentPhotoMedia(
                parentDraftID: current.value.parentCheckpoint.draftID,
                childDraftID: current.value.parent.slot.childDraftID)
            let completedMedia = try XCTUnwrap(completedMediaRead)
            XCTAssertEqual(completedMedia.targetRead.currentTarget, completedCurrent.currentTarget)
            try await current.service.validateForPublication(completedMedia)
            XCTAssertThrowsError(try h.captureSource())
            XCTAssertThrowsError(try h.runner.prepareFrozenBegin(source: source, progress: h.progress,
                publishedRelease: h.publishedRelease, submission: h.validSubmission()))
            XCTAssertEqual(h.ids.callCount, idCalls)
            XCTAssertEqual(try h.snapshot(), before)

            let frontier = h.read.chain.currentRound
            let closed = try RoundSessionV1(workspaceID: h.workspaceID, sessionID: frontier.sessionID,
                predecessor: frontier, revision: frontier.revision + 1,
                mutationID: .init(rawValue: beginPreparationUUID(9_253)), state: .completed,
                transition: .close, items: frontier.items, recordedBy: frontier.recordedBy,
                recordedAt: frontier.recordedAt)
            _ = try h.coordinator.workspaceWriter.commitRoundSession(.init(workspaceID: h.workspaceID,
                expectedRevision: frontier.revision, mutationID: closed.mutationID, session: closed))
            before = try h.snapshot()
            XCTAssertThrowsError(try h.progress.read(sourceDraftID: source.sourceCheckpoint.draftID))
            XCTAssertThrowsError(try h.progress.validateHistoricalCheckRunnerSource(source, read: h.read,
                publishedRelease: h.publishedRelease, signPack: h.signPack))
            XCTAssertThrowsError(try current.service.readCurrentPhotoTarget(
                parentDraftID: current.value.parentCheckpoint.draftID,
                childDraftID: current.value.parent.slot.childDraftID))
            do {
                _ = try await current.service.readCurrentPhotoMedia(
                    parentDraftID: current.value.parentCheckpoint.draftID,
                    childDraftID: current.value.parent.slot.childDraftID)
                XCTFail("Externally closed Round must reject media read")
            } catch {}
            XCTAssertEqual(h.ids.callCount, idCalls)
            XCTAssertEqual(try h.snapshot(), before)
        }

        try await withAsyncFrozenBeginFixture("missing-current-raw", entry: .check,
                                   storedTimeZoneID: "America/New_York") { h in
            let current = try await h.persistCurrentPhotoApplicationFixture()
            let before = try h.snapshot(), idCalls = h.ids.callCount
            let raw = current.mediaValue.media.rawReference
            let rawURL = h.session.generationRootURL
                .appendingPathComponent("content", isDirectory: true)
                .appendingPathComponent(raw.workspaceID, isDirectory: true)
                .appendingPathComponent(raw.contentID, isDirectory: true)
                .appendingPathComponent("original.bin")
            XCTAssertNotNil(try current.service.readCurrentPhotoTarget(
                parentDraftID: current.value.parentCheckpoint.draftID,
                childDraftID: current.value.parent.slot.childDraftID))
            var hostileRaw = current.sourceData
            hostileRaw[hostileRaw.startIndex] ^= 0xff
            try hostileRaw.write(to: rawURL, options: [])
            do {
                _ = try await current.service.readCurrentPhotoMedia(
                    parentDraftID: current.value.parentCheckpoint.draftID,
                    childDraftID: current.value.parent.slot.childDraftID)
                XCTFail("Tampered immutable original must reject media read")
            } catch {}
            try FileManager.default.removeItem(at: rawURL)
            do {
                _ = try await current.service.readCurrentPhotoMedia(
                    parentDraftID: current.value.parentCheckpoint.draftID,
                    childDraftID: current.value.parent.slot.childDraftID)
                XCTFail("Missing immutable original must reject media read")
            } catch {}
            XCTAssertEqual(h.ids.callCount, idCalls)
            XCTAssertEqual(try h.snapshot(), before)
        }

        try await withAsyncFrozenBeginFixture("tampered-current-jpeg", entry: .check,
                                   storedTimeZoneID: "America/New_York") { h in
            let current = try await h.persistCurrentPhotoApplicationFixture()
            let before = try h.snapshot(), idCalls = h.ids.callCount
            let originalURL = h.session.generationRootURL.appendingPathComponent(
                current.mediaValue.media.normalizedPair.originalRelativePath)
            var hostile = try Data(contentsOf: originalURL)
            hostile[hostile.startIndex] ^= 0xff
            try hostile.write(to: originalURL, options: [])
            XCTAssertNotNil(try current.service.readCurrentPhotoTarget(
                parentDraftID: current.value.parentCheckpoint.draftID,
                childDraftID: current.value.parent.slot.childDraftID))
            do {
                _ = try await current.service.readCurrentPhotoMedia(
                    parentDraftID: current.value.parentCheckpoint.draftID,
                    childDraftID: current.value.parent.slot.childDraftID)
                XCTFail("Tampered promoted JPEG must reject media read")
            } catch {}
            try FileManager.default.removeItem(at: originalURL)
            do {
                _ = try await current.service.readCurrentPhotoMedia(
                    parentDraftID: current.value.parentCheckpoint.draftID,
                    childDraftID: current.value.parent.slot.childDraftID)
                XCTFail("Missing promoted JPEG must reject media read")
            } catch {}
            XCTAssertEqual(h.ids.callCount, idCalls)
            XCTAssertEqual(try h.snapshot(), before)
        }
    }

    func testFrozenContractsRejectMalformedClosedBytesAndEncodeNoDestinationAuthority() async throws {
        try await withAsyncFrozenBeginFixture("closed-contract", entry: .check, storedTimeZoneID: nil) { h in
            let source = try h.captureSource()
            let recordID = beginPreparationUUID(9_301)
            let zoneID = beginPreparationUUID(9_302)
            h.ids.enqueue([recordID, zoneID])
            let attempt = try h.runner.prepareFrozenBegin(
                source: source, progress: h.progress,
                publishedRelease: h.publishedRelease, submission: h.validSubmission()
            )
            let before = try h.snapshot()
            let bytes = try FieldDraftCanonicalCodecV1.encode(attempt)
            let decoded = try FieldDraftCanonicalCodecV1.decode(
                CheckRunnerFrozenBeginAttemptV1.self, from: bytes
            )
            XCTAssertEqual(decoded, attempt)
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(decoded), bytes)
            try h.runner.validateHistoricalCheckRunnerSource(source, read: h.read,
                progress: h.progress, publishedRelease: h.publishedRelease)

            let top = try frozenBeginJSONObject(bytes)
            XCTAssertEqual(try decodeFrozenBeginJSON(CheckRunnerFrozenBeginAttemptV1.self, object: top), attempt)
            XCTAssertEqual(try decodeFrozenBeginJSON(CheckRunnerRoundItemSourceV1.self,
                object: frozenBeginJSONObject(FieldDraftCanonicalCodecV1.encode(source))), source)
            XCTAssertEqual(Set(top.keys), Set([
                "source", "sourceWorkspaceID", "recordCommand", "recordMutationID",
                "recordExpectedEntityRevisions", "recordCommittedAt", "timeZone",
                "siteID", "resolvedSiteTimeZoneID",
            ]))
            let allKeys = jsonKeys(top)
            for forbidden in ["destination", "generation", "writer", "bound", "receipt"] {
                XCTAssertFalse(allKeys.contains { $0.lowercased().contains(forbidden) }, forbidden)
            }

            var mutations: [(String, ([String: Any]) throws -> [String: Any])] = []
            mutations.append(("unknown-top", { value in
                var value = value; value["futureDestination"] = true; return value
            }))
            mutations.append(("unknown-source", { value in
                var value = value; var source = try XCTUnwrap(value["source"] as? [String: Any])
                source["futureSource"] = true; value["source"] = source; return value
            }))
            mutations.append(("unknown-command", { value in
                var value = value; var command = try XCTUnwrap(value["recordCommand"] as? [String: Any])
                command["futureCommand"] = true; value["recordCommand"] = command; return value
            }))
            mutations.append(("unknown-revision", { value in
                var value = value; var revisions = try XCTUnwrap(value["recordExpectedEntityRevisions"] as? [[String: Any]])
                revisions[0]["futureRevision"] = true; value["recordExpectedEntityRevisions"] = revisions; return value
            }))
            mutations.append(("unknown-identity", { value in
                var value = value; var revisions = try XCTUnwrap(value["recordExpectedEntityRevisions"] as? [[String: Any]])
                var identity = try XCTUnwrap(revisions[0]["identity"] as? [String: Any])
                identity["futureIdentity"] = true; revisions[0]["identity"] = identity
                value["recordExpectedEntityRevisions"] = revisions; return value
            }))
            mutations.append(("source-relationship", { value in
                var value = value; var source = try XCTUnwrap(value["source"] as? [String: Any])
                source["entryProgressCheckpoint"] = source["sourceCheckpoint"]
                value["source"] = source; return value
            }))
            mutations.append(("command-identity", { value in
                var value = value; var command = try XCTUnwrap(value["recordCommand"] as? [String: Any])
                command["recordID"] = beginPreparationUUID(9_399).uuidString.lowercased()
                value["recordCommand"] = command; return value
            }))
            mutations.append(("zero-mutation-id", { value in
                var value = value; value["recordMutationID"] = "00000000-0000-0000-0000-000000000000"; return value
            }))
            mutations.append(("negative-revision", { value in
                var value = value; var revisions = try XCTUnwrap(value["recordExpectedEntityRevisions"] as? [[String: Any]])
                revisions[0]["revision"] = -1; value["recordExpectedEntityRevisions"] = revisions; return value
            }))
            mutations.append(("negative-time", { value in
                var value = value; value["recordCommittedAt"] = -1_000_000_000; return value
            }))
            mutations.append(("malformed-zone", { value in
                var value = value; var command = try XCTUnwrap(value["recordCommand"] as? [String: Any])
                command["timeZoneID"] = "Mars/Olympus"; value["recordCommand"] = command
                value["resolvedSiteTimeZoneID"] = "Mars/Olympus"
                var zone = try XCTUnwrap(value["timeZone"] as? [String: Any])
                var zoneCommand = try XCTUnwrap(zone["command"] as? [String: Any])
                zoneCommand["timeZoneID"] = "Mars/Olympus"; zone["command"] = zoneCommand
                value["timeZone"] = zone; return value
            }))
            mutations.append(("unknown-zone-command", { value in
                var value = value; var zone = try XCTUnwrap(value["timeZone"] as? [String: Any])
                var command = try XCTUnwrap(zone["command"] as? [String: Any])
                command["futureZoneAuthority"] = true; zone["command"] = command
                value["timeZone"] = zone; return value
            }))
            mutations.append(("unknown-zone-attempt", { value in
                var value = value; var zone = try XCTUnwrap(value["timeZone"] as? [String: Any])
                zone["futureZoneAttemptAuthority"] = true; value["timeZone"] = zone
                return value
            }))

            for (label, mutate) in mutations {
                let hostile = try mutate(top)
                XCTAssertThrowsError(try decodeFrozenBeginJSON(
                    CheckRunnerFrozenBeginAttemptV1.self, object: hostile
                ), label)
            }
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(source),
                           try FieldDraftCanonicalCodecV1.encode(attempt.source))
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(attempt), bytes)
            XCTAssertEqual(try h.snapshot(), before)
        }
    }

    private func assertSourceDecodeFails(
        _ object: [String: Any], file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertThrowsError(try decodeFrozenBeginJSON(
            CheckRunnerRoundItemSourceV1.self, object: object
        ), file: file, line: line)
    }
}

@MainActor
func withFrozenBeginFixture<Value>(
    _ label: String, entry: CheckRunnerRequestedEntryV1, storedTimeZoneID: String?,
    _ body: (FrozenBeginFixture) throws -> Value
) throws -> Value {
    var root: URL?
    do {
        let value = try autoreleasepool { () throws -> Value in
            let fixtureRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
                "V23-frozen-begin-\(label)-\(UUID().uuidString)", isDirectory: true
            )
            root = fixtureRoot
            let fixture = try FrozenBeginFixture(
                root: fixtureRoot, entry: entry, storedTimeZoneID: storedTimeZoneID
            )
            do {
                let value = try body(fixture)
                try fixture.closeCoordinator()
                return value
            } catch {
                try? fixture.closeCoordinator()
                throw error
            }
        }
        if let root { try FileManager.default.removeItem(at: root) }
        return value
    } catch {
        if let root { try? FileManager.default.removeItem(at: root) }
        throw error
    }
}

@MainActor
func withAsyncFrozenBeginFixture<Value>(
    _ label: String, entry: CheckRunnerRequestedEntryV1, storedTimeZoneID: String?,
    appDirectoryLayout: Bool = false,
    diagnosticPhase: (@MainActor (String) -> Void)? = nil,
    _ body: (FrozenBeginFixture) async throws -> Value
) async throws -> Value {
    var root: URL?
    do {
        diagnosticPhase?("fixture.init.begin")
        let fixtureRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "V23-frozen-begin-\(label)-\(UUID().uuidString)", isDirectory: true
        )
        root = fixtureRoot
        let support: URL
        if appDirectoryLayout {
            // Production startup requires an existing sibling Caches directory.
            // Keep both directories inside this fixture's unique owned root.
            support = fixtureRoot.appendingPathComponent("Application Support", isDirectory: true)
            let caches = fixtureRoot.appendingPathComponent("Caches", isDirectory: true)
            try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        } else {
            support = fixtureRoot
        }
        let fixture = try await FrozenBeginFixture.withAcceptedPromotion(
            root: support, entry: entry, storedTimeZoneID: storedTimeZoneID
        )
        diagnosticPhase?("fixture.init.end")
        let value: Value
        do {
            diagnosticPhase?("fixture.body.begin")
            value = try await body(fixture)
            diagnosticPhase?("fixture.body.end")
            diagnosticPhase?("fixture.close.begin")
            try fixture.closeCoordinator()
            diagnosticPhase?("fixture.close.end")
        } catch {
            diagnosticPhase?("fixture.body-or-close.error")
            diagnosticPhase?("fixture.error-close.begin")
            try? fixture.closeCoordinator()
            diagnosticPhase?("fixture.error-close.end")
            throw error
        }
        diagnosticPhase?("fixture.remove.begin")
        if let root { try FileManager.default.removeItem(at: root) }
        diagnosticPhase?("fixture.remove.end")
        return value
    } catch {
        diagnosticPhase?("fixture.error")
        diagnosticPhase?("fixture.error-remove.begin")
        if let root { try? FileManager.default.removeItem(at: root) }
        diagnosticPhase?("fixture.error-remove.end")
        throw error
    }
}

@MainActor
final class FrozenBeginFixture {
    struct SiteAnchor: Equatable { let id: UUID; let label: String; let timeZoneID: String?; let updatedAt: Date }
    struct AssetAnchor: Equatable {
        let id: UUID; let siteID: UUID; let packID: String
        let schemaVersion: Int; let contentVersion: Int; let label: String; let updatedAt: Date
    }
    struct WorkflowAnchor: Equatable {
        let id: UUID; let assetID: UUID; let issueID: UUID?; let parentID: UUID?
        let stage: String; let state: String; let startedAt: Date; let timeZoneID: String?
    }
    struct IssueAnchor: Equatable {
        let id: UUID; let assetID: UUID; let openedBy: UUID; let status: String; let resolvedBy: UUID?
    }
    struct RowSnapshot: Equatable {
        let checkpointBytes: [Data]; let roundBytes: [Data]; let packageBytes: [Data]
        let sites: [SiteAnchor]; let assets: [AssetAnchor]
        let workflows: [WorkflowAnchor]; let issues: [IssueAnchor]; let hasChanges: Bool
    }
    struct Snapshot: Equatable {
        let revision: WorkspaceRevisionV1
        let history: MutationHistorySnapshotV1
        let rows: RowSnapshot
    }

    let root: URL
    let factory: StoreGenerationFactory
    let session: StoreGenerationSession
    let coordinator: StoreSessionCoordinator
    let profile: WorkspacePackageLifecycleProfileV1
    let signPack: SignPack
    let publishedRelease: InspectionPackageReleaseV1
    let ids: FrozenBeginCountingIDs
    let clock: FrozenBeginClock
    let transitions: ProductionRoundSessionTransitionServiceV1
    let progress: ProductionRepetitiveCaptureProgressServiceV2
    let runner: CheckRunnerCoordinator
    let siteID: UUID
    let assetID: UUID
    let itemID: UUID
    let originalItem: RoundItemV1
    let entryItem: RoundItemV1
    let issueID: UUID?
    let recheckParentID: UUID?
    var read: ProductionRepetitiveCaptureReadV2
    private var coordinatorClosed = false

    var context: ModelContext { session.modelContext }
    var workspaceID: WorkspaceID { session.workspaceID }

    struct CurrentPhotoApplicationFixture {
        let service: ProductionCheckRunnerItemDraftServiceV1
        let value: CurrentPhotoTargetReadV1
        let mediaValue: CurrentPhotoMediaReadV1
        let sourceData: Data
    }

    private struct PreparedPromotion {
        let factory: StoreGenerationFactory
        let session: StoreGenerationSession
        let coordinator: StoreSessionCoordinator
        let ids: FrozenBeginCountingIDs
        let clock: FrozenBeginClock
        let promoted: PromotedPackageReleaseV1
    }

    /// Async export/recovery fixtures need the complete accepted package
    /// history, not the isolated published row used by synchronous unit cases.
    static func withAcceptedPromotion(root: URL, entry: CheckRunnerRequestedEntryV1,
        storedTimeZoneID: String?) async throws -> FrozenBeginFixture {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: WorkspaceID(rawValue: beginPreparationUUID(10_001)),
            replicaID: ReplicaID(rawValue: beginPreparationUUID(10_002)))
        let factory = StoreGenerationFactory(applicationSupportURL: root,
            pointerEnrichmentIdentity: identity)
        let session = try factory.openOrBootstrapCurrent()
        let ids = FrozenBeginCountingIDs()
        let clock = FrozenBeginClock(value: Date(timeIntervalSince1970: 1_789_500_000.4567))
        let coordinator = try StoreSessionCoordinator(validatingSession: session,
            clock: clock, idSource: ids,
            lifecycleProfileRegistry: WorkspacePackageLifecycleCompatibilityV1.shippingRegistry())
        do {
            let release = try frozenBeginShippingRelease(stage: entry.stage)
            let journal = try MutationJournalStoreV1(modelContext: session.modelContext,
                identity: coordinator.workspaceIdentity, generationID: coordinator.generationID,
                allowStateBootstrap: false)
            let promoted = try await CanonicalWriterSeedingV1.promotePackage(release,
                workspaceID: session.workspaceID, actor: actor(workspaceID: session.workspaceID),
                writer: coordinator.workspaceWriter, journal: journal, context: session.modelContext,
                promotedAt: Date(timeIntervalSince1970: 1_789_000_000),
                ids: .init(releaseRecordID: beginPreparationUUID(10_040),
                    sandboxRunID: beginPreparationUUID(10_042), pointerID: beginPreparationUUID(10_043),
                    receiptID: beginPreparationUUID(10_044),
                    mutationID: .init(rawValue: beginPreparationUUID(10_041)),
                    actorMutationID: .init(rawValue: beginPreparationUUID(10_045))))
            let adapter = PackageEvolutionLifecycleAdapterV1(writer: coordinator.workspaceWriter,
                journal: journal, modelContext: session.modelContext)
            let closure = try XCTUnwrap(adapter.acceptedLifecycleClosure(mutationID: promoted.mutationID))
            try closure.validate()
            XCTAssertEqual(closure.promotedReleases, [promoted])
            XCTAssertEqual(closure.sandboxRuns.count, 1)
            XCTAssertEqual(closure.promotionReceipts.count, 1)
            XCTAssertEqual(closure.activePointers.count, 1)
            XCTAssertEqual(closure.promotionReceipts.first?.operation, .initialActivation)
            XCTAssertEqual(try journal.receipt(mutationID: promoted.mutationID)?.mutationID, promoted.mutationID)
            try journal.validateAll()
            return try FrozenBeginFixture(root: root, entry: entry, storedTimeZoneID: storedTimeZoneID,
                prepared: .init(factory: factory, session: session, coordinator: coordinator,
                    ids: ids, clock: clock, promoted: promoted))
        } catch {
            try? coordinator.invalidateAndReleaseWriter()
            throw error
        }
    }

    convenience init(root: URL, entry: CheckRunnerRequestedEntryV1, storedTimeZoneID: String?) throws {
        try self.init(root: root, entry: entry, storedTimeZoneID: storedTimeZoneID, prepared: nil)
    }

    private init(root: URL, entry: CheckRunnerRequestedEntryV1, storedTimeZoneID: String?,
        prepared: PreparedPromotion?) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: WorkspaceID(rawValue: beginPreparationUUID(10_001)),
            replicaID: ReplicaID(rawValue: beginPreparationUUID(10_002))
        )
        let localFactory = prepared?.factory ?? StoreGenerationFactory(
            applicationSupportURL: root, pointerEnrichmentIdentity: identity
        )
        factory = localFactory
        let localSession = try prepared?.session ?? localFactory.openOrBootstrapCurrent()
        session = localSession
        let localIDs = prepared?.ids ?? FrozenBeginCountingIDs()
        ids = localIDs
        let localClock = prepared?.clock ?? FrozenBeginClock(value: Date(timeIntervalSince1970: 1_789_500_000.4567))
        clock = localClock
        let registry = try WorkspacePackageLifecycleCompatibilityV1.shippingRegistry()
        let localCoordinator = try prepared?.coordinator ?? StoreSessionCoordinator(
            validatingSession: localSession, clock: localClock, idSource: localIDs,
            lifecycleProfileRegistry: registry
        )
        coordinator = localCoordinator
        let localProfile = try WorkspacePackageLifecycleCompatibilityV1.legacyV3Profile(
            package: .illuminatedSignV1
        )
        profile = localProfile
        signPack = localProfile.package
        let localRelease = try frozenBeginShippingRelease(stage: entry.stage)
        publishedRelease = localRelease
        if let prepared {
            XCTAssertEqual(prepared.promoted.packageRelease, localRelease)
        } else {
            try Self.installPublishedRelease(localRelease, in: localCoordinator, context: localSession.modelContext)
        }

        let localSiteID = beginPreparationUUID(10_010)
        let localAssetID = beginPreparationUUID(10_011)
        siteID = localSiteID
        assetID = localAssetID
        let firstMutation = try MutationIDV1(rawValue: beginPreparationUUID(10_012))
        _ = try localCoordinator.workspaceWriter.execute(.createFirstSign(.init(
            siteID: localSiteID,
            newSite: .init(id: localSiteID, label: "North Campus", address: "10 Main",
                           timeZoneID: storedTimeZoneID),
            assetID: localAssetID, assetLabel: "Monument Sign",
            packID: localProfile.package.packID,
            packSchemaVersion: localProfile.package.schemaVersion,
            packContentVersion: localProfile.package.contentVersion,
            createdAt: Date(timeIntervalSince1970: 1_789_000_000),
            initialPlacementMutationID: firstMutation,
            initialPlacementEventID: beginPreparationUUID(10_013),
            initialPhysicalEpisodeID: try PhysicalPlacementEpisodeIDV1(
                rawValue: beginPreparationUUID(10_014)
            )
        )), mutationID: firstMutation)

        var localIssueID: UUID?
        var localParentID: UUID?
        if case let .recheck(requestedIssueID) = entry {
            localIssueID = requestedIssueID
            localParentID = beginPreparationUUID(10_020)
            try Self.installRecheckLineage(
                issueID: requestedIssueID, parentID: localParentID!, assetID: localAssetID,
                signPack: localProfile.package, coordinator: localCoordinator,
                context: localSession.modelContext
            )
        }
        issueID = localIssueID
        recheckParentID = localParentID

        let localItemID = beginPreparationUUID(10_030)
        itemID = localItemID
        let actor = try Self.actor(workspaceID: localSession.workspaceID)
        let requirement = try RoundPackageContentRequirementV1(
            packageRelease: .init(localRelease), requiredContent: []
        )
        let pending = try RoundItemV1(
            itemID: localItemID, order: 0,
            selection: .init(assetID: localAssetID, siteID: localSiteID,
                             labelAtSelection: "Monument Sign"),
            requirement: requirement
        )
        originalItem = pending
        let draft = try RoundSessionV1(
            workspaceID: localSession.workspaceID, sessionID: beginPreparationUUID(10_031),
            revision: 1, mutationID: .init(rawValue: beginPreparationUUID(10_032)),
            state: .draft, transition: .create, items: [pending],
            recordedBy: actor, recordedAt: Date(timeIntervalSince1970: 1_789_000_100)
        )
        _ = try localCoordinator.workspaceWriter.commitRoundSession(.init(
            workspaceID: localSession.workspaceID, expectedRevision: 0,
            mutationID: draft.mutationID, session: draft
        ))
        let active = try RoundSessionV1(
            workspaceID: localSession.workspaceID, sessionID: draft.sessionID,
            predecessor: draft, revision: 2,
            mutationID: .init(rawValue: beginPreparationUUID(10_033)),
            state: .active, transition: .start, items: [pending],
            recordedBy: actor, recordedAt: Date(timeIntervalSince1970: 1_789_000_101)
        )
        _ = try localCoordinator.workspaceWriter.commitRoundSession(.init(
            workspaceID: localSession.workspaceID, expectedRevision: draft.revision,
            mutationID: active.mutationID, session: active
        ))

        let gate = AppAccessGateV1(
            setting: .absentDisabled, authentication: FrozenBeginAuthentication(),
            clock: localClock, identifiers: localIDs
        )
        let localTransitions = try localCoordinator.makeRoundSessionTransitionService(accessGate: gate)
        transitions = localTransitions
        let localProgress = try localCoordinator.makeRepetitiveCaptureProgressService(
            transitions: localTransitions
        )
        progress = localProgress
        let manifest = try Self.manifest(round: active, release: localRelease)
        let sourceWrite = try localProgress.prepareSource(round: active, manifest: manifest)
        let sourceRead = try localProgress.persistSource(sourceWrite)
        let entryWrite = try localProgress.prepareStep(
            read: sourceRead, action: .enter, focus: .facts, completionRecordID: nil,
            recordedByName: "Frozen Begin entry recorder"
        )
        _ = try localProgress.persistStep(entryWrite)
        let roundMutation = try XCTUnwrap(entryWrite.step.roundMutation)
        _ = try localCoordinator.workspaceWriter.commitRoundSession(roundMutation)
        let localRead = try localProgress.read(sourceDraftID: sourceWrite.checkpoint.draftID)
        read = localRead
        entryItem = try XCTUnwrap(localRead.chain.currentRound.items.first { $0.itemID == localItemID })
        try localProgress.validateForPublication(localRead)
        runner = try CheckRunnerCoordinator(
            modelContext: localSession.modelContext,
            packageLifecycleDependencies: localCoordinator.packageLifecycleDependencies(
                profileRegistry: registry
            ),
            packageLifecycleProfile: localProfile
        )
        _ = try localCoordinator.workspaceWriter.sourceMutationHistorySnapshot()
        XCTAssertFalse(localSession.modelContext.hasChanges)
    }

    /// Installs one production-shaped parent/child commit using this fixture's
    /// authenticated ENTRY, durable Begin, genuine normalized JPEG promotion,
    /// and receipts written through the production writer and draft adapter.
    func persistCurrentPhotoApplicationFixture() async throws -> CurrentPhotoApplicationFixture {
        let attachmentStaging = try DraftAttachmentStagingAdapterV1(
            applicationSupportURL: root, workspaceID: workspaceID)
        let service = try ProductionCheckRunnerItemDraftServiceV1(session: coordinator,
            progress: progress, coordinator: runner, publishedRelease: publishedRelease,
            clock: clock, ids: ids, attachmentStaging: attachmentStaging)
        let source = try captureSource()
        let site = try XCTUnwrap(context.fetch(FetchDescriptor<Site>()).first { $0.id == siteID })
        let resolvedTimeZoneID = site.timeZoneID ?? "America/New_York"
        let created = try service.create(source: source, preflight: .init(
            timeZoneID: resolvedTimeZoneID, isTimeZoneConfirmed: true,
            confirmedTimeZoneID: resolvedTimeZoneID,
            afterDarkAccepted: true, safePositionAccepted: true))
        let prepared = try service.prepareBegin(draftID: created.draftID,
            expectedCheckpointSHA256: created.checkpointSHA256,
            observedAtUTC: Date(timeIntervalSince1970: 1_789_323_456))
        let bound = try service.resumeInitialBegin(draftID: prepared.draftID)
        let parent = try CheckRunnerItemDraftCodecV1.validateCheckpoint(bound)
        guard case .bound = parent.field.begin, let attempt = parent.field.begin.attempt else {
            throw FieldDraftFailureV1.missingReceipt
        }
        XCTAssertEqual(parent.source, source)
        XCTAssertEqual(parent.field.preflight.timeZoneID, resolvedTimeZoneID)
        XCTAssertEqual(parent.field.preflight.confirmedTimeZoneID, resolvedTimeZoneID)
        XCTAssertEqual(attempt.resolvedSiteTimeZoneID, resolvedTimeZoneID)
        XCTAssertNil(attempt.timeZone)

        runner.configureCapture(generationRootURL: session.generationRootURL)
        let sourceData = try WorkCanonicalIntegrationTestSupportV1.makePNG(seed: 201)
        let media = try MediaNormalizerV1().normalizeWithSourceFacts(sourceData)
        let evidenceCreatedAt = bound.updatedAt.addingTimeInterval(1)
        let candidate = try await runner.importCandidate(assetID: source.assetID,
            sourceData: sourceData, createdAt: evidenceCreatedAt)
        let originalFacts = try MediaNormalizerV1().validateCanonicalJPEG(
            media.normalized.originalJPEG, kind: .original)
        let thumbnailFacts = try MediaNormalizerV1().validateCanonicalJPEG(
            media.normalized.thumbnailJPEG, kind: .thumbnail)
        let childDraftID = beginPreparationUUID(30_001)
        let stageID = beginPreparationUUID(30_002)
        let evidenceID = candidate.id
        let intent = try CheckRunnerPhotoRawStageIntentV1(stageID: stageID,
            stageMutationID: .init(rawValue: beginPreparationUUID(30_004)),
            stageCreatedAt: bound.updatedAt.addingTimeInterval(2),
            expectedSourceByteCount: Int64(sourceData.count),
            provenanceID: "application-photo-current", evidenceID: evidenceID,
            evidenceCreatedAt: evidenceCreatedAt)
        let inspection = try CheckRunnerPhotoSourceInspectionV1(
            facts: media.sourceFacts,
            sourceSHA256: .init(algorithm: .sha256,
                hexadecimalValue: KernelCanonicalHashV1.sha256(sourceData)),
            workspaceID: workspaceID, provenanceID: intent.provenanceID)
        let ready = try AttachmentStagingItemV1(stageID: stageID, draftID: childDraftID,
            workspaceID: workspaceID, attachmentKind: .photo, scratchLeaseID: stageID,
            expectedByteCount: Int64(sourceData.count), actualByteCount: Int64(sourceData.count),
            contentDigest: inspection.sourceSHA256, retryClass: .none, state: .readyLocal,
            protectionState: .available, revision: 1, mutationID: intent.stageMutationID)
        let provenance = try ContentOriginalProvenanceV1(provenanceID: intent.provenanceID,
            workspaceID: workspaceID.rawValue.uuidString.lowercased(),
            contentID: inspection.rawContentID, contentDigest: inspection.sourceSHA256,
            origin: .humanCapture,
            recordedAt: CheckRunnerPhotoRawReadyV1.formatOriginalRecordedAt(intent.stageCreatedAt))
        let raw = try CheckRunnerPhotoRawReadyV1(intent: intent, inspection: inspection,
            readyItem: ready, stagePublicationMutationID: intent.stageMutationID,
            originalProvenance: provenance)
        XCTAssertEqual(candidate.stagedBundle.originalByteCount, media.normalized.originalJPEG.count)
        XCTAssertEqual(candidate.stagedBundle.thumbnailByteCount, media.normalized.thumbnailJPEG.count)
        XCTAssertEqual(candidate.stagedBundle.originalSHA256,
            KernelCanonicalHashV1.sha256(media.normalized.originalJPEG))
        XCTAssertEqual(candidate.stagedBundle.thumbnailSHA256,
            KernelCanonicalHashV1.sha256(media.normalized.thumbnailJPEG))
        let normalized = try CheckRunnerPhotoNormalizedPairV1(evidenceID: evidenceID,
            originalRelativePath: candidate.stagedBundle.originalRelativePath,
            originalByteCount: Int64(candidate.stagedBundle.originalByteCount),
            originalSHA256: candidate.stagedBundle.originalSHA256,
            originalPixelWidth: originalFacts.pixelWidth,
            originalPixelHeight: originalFacts.pixelHeight,
            thumbnailRelativePath: candidate.stagedBundle.thumbnailRelativePath,
            thumbnailByteCount: Int64(candidate.stagedBundle.thumbnailByteCount),
            thumbnailSHA256: candidate.stagedBundle.thumbnailSHA256,
            thumbnailPixelWidth: thumbnailFacts.pixelWidth,
            thumbnailPixelHeight: thumbnailFacts.pixelHeight,
            sourceBinding: .init(contentID: inspection.rawContentID,
                digest: inspection.sourceSHA256),
            sanitizedDerivative: CheckRunnerPhotoSourceMetadataProfileV1.sanitizedDerivative(),
            thumbnailDerivative: CheckRunnerPhotoSourceMetadataProfileV1.thumbnailDerivative(
                pixelWidth: thumbnailFacts.pixelWidth, pixelHeight: thumbnailFacts.pixelHeight))
        let pair = try CheckRunnerPhotoPairReadyV1(raw: raw, normalizedPair: normalized,
            pairPublicationMarkerSHA256: CheckRunnerPhotoPairReadyV1.markerSHA256(
                childDraftID: childDraftID, parentDraftID: bound.draftID,
                raw: raw, normalizedPair: normalized))
        let workflowIdentity = try WorkspaceEntityIdentityV1(kind: .workflowRecord,
            id: attempt.recordCommand.recordID)
        let evidenceIdentity = try WorkspaceEntityIdentityV1(kind: .evidenceFile, id: evidenceID)
        let commitAttempt = try CheckRunnerPhotoCommitAttemptV1(
            planID: beginPreparationUUID(30_010), expectedWorkflowRecordRevision: 1,
            targetMutationID: .init(rawValue: evidenceID),
            outputKeys: [workflowIdentity.stableKey, evidenceIdentity.stableKey].sorted(),
            reservationMutationID: .init(rawValue: beginPreparationUUID(30_011)),
            reservationReviewAfter: bound.updatedAt.addingTimeInterval(20),
            preparedSagaID: beginPreparationUUID(30_012),
            preparedSagaMutationID: .init(rawValue: beginPreparationUUID(30_013)),
            preparedUpdatedAt: bound.updatedAt.addingTimeInterval(4),
            contentPromotedSagaID: beginPreparationUUID(30_014),
            contentPromotedSagaMutationID: .init(rawValue: beginPreparationUUID(30_015)),
            contentPromotedUpdatedAt: bound.updatedAt.addingTimeInterval(6),
            targetCommittedSagaID: beginPreparationUUID(30_016),
            targetCommittedSagaMutationID: .init(rawValue: beginPreparationUUID(30_017)),
            targetCommittedUpdatedAt: bound.updatedAt.addingTimeInterval(7),
            draftRetirePendingSagaID: beginPreparationUUID(30_018),
            draftRetirePendingSagaMutationID: .init(rawValue: beginPreparationUUID(30_019)),
            draftRetirePendingUpdatedAt: bound.updatedAt.addingTimeInterval(8),
            draftRetiredSagaID: beginPreparationUUID(30_020),
            draftRetiredUpdatedAt: bound.updatedAt.addingTimeInterval(9),
            commitReceiptID: beginPreparationUUID(30_021),
            terminalBundleMutationID: .init(rawValue: beginPreparationUUID(30_022)),
            terminalCheckpointUpdatedAt: bound.updatedAt.addingTimeInterval(10),
            promotionAt: bound.updatedAt.addingTimeInterval(5))
        let pendingSlot = CheckRunnerPhotoSlotV1.pending(childDraftID: childDraftID,
            captureStep: .wide, purposeKey: "wide_context")
        let pendingField = try CheckRunnerItemFieldStateV1(preflight: parent.field.preflight,
            begin: parent.field.begin, outcome: parent.field.outcome, wideContext: pendingSlot,
            closeDetail: parent.field.closeDetail, semanticAnchor: parent.field.semanticAnchor)
        let pendingPayload = try CheckRunnerItemDraftPayloadV1(editing: source, field: pendingField)
        let parentPending = try parentSuccessor(bound, payload: pendingPayload,
            updatedAt: intent.stageCreatedAt,
            mutationID: .init(rawValue: beginPreparationUUID(30_030)))
        let adapter = try coordinator.workspaceWriter.makeFieldDraftLifecycleAdapter(modelContext: context)

        func photoCheckpoint(_ phase: CheckRunnerPhotoDurablePhaseV1, revision: UInt64,
                             state: FieldDraftStateV1, updatedAt: Date,
                             mutationID: MutationIDV1) throws -> FieldDraftCheckpointV1 {
            let payload = try CheckRunnerPhotoDraftPayloadV1(workspaceID: workspaceID,
                childDraftID: childDraftID, parentDraftID: bound.draftID,
                recordID: attempt.recordCommand.recordID, assetID: source.assetID,
                sourceBinding: source, workflowStage: source.requestedEntry.stage,
                captureStep: .wide, purposeKey: "wide_context",
                origin: .humanCapture, phase: phase)
            return try FieldDraftCheckpointV1(draftID: childDraftID, workspaceID: workspaceID,
                scope: CheckRunnerPhotoDraftCodecV1.scope(payload: payload),
                purpose: .inspectionReview, codec: CheckRunnerPhotoDraftCodecV1.release(),
                baseCanonicalRevision: source.roundAtEntry.revision, draftRevision: revision,
                payloadData: CheckRunnerPhotoDraftCodecV1.encode(payload),
                stageIDs: phase.declaredStageIDs,
                resumeAnchor: CheckRunnerPhotoDraftCodecV1.resumeAnchor(payload: payload),
                state: state, updatedAt: updatedAt, mutationID: mutationID)
        }
        let awaiting = try photoCheckpoint(.awaitingRawStage(intent), revision: 1,
            state: .active, updatedAt: intent.stageCreatedAt,
            mutationID: .init(rawValue: beginPreparationUUID(30_040)))
        let proposal = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(awaiting)
        func proposalWith(_ selectedIntent: CheckRunnerPhotoRawStageIntentV1) throws -> CheckRunnerPhotoDraftPayloadV1 {
            try .init(workspaceID: workspaceID, childDraftID: childDraftID, parentDraftID: bound.draftID,
                recordID: proposal.recordID, assetID: proposal.assetID, sourceBinding: proposal.sourceBinding,
                workflowStage: proposal.workflowStage, captureStep: proposal.captureStep,
                purposeKey: proposal.purposeKey, origin: proposal.origin, phase: .awaitingRawStage(selectedIntent))
        }
        // A real unrelated generic stage keeps the collision probe on valid
        // journal history and tests preservation of the original physical bytes.
        let incumbentBytes = Data("existing unrelated attachment".utf8)
        let incumbentStage = try await attachmentStaging.stage(data: incumbentBytes,
            draftID: beginPreparationUUID(38_001), workspaceID: workspaceID,
            attachmentKind: .photo, stageID: beginPreparationUUID(38_002),
            mutationID: .init(rawValue: beginPreparationUUID(38_003)))
        let generic = try C36FieldDraftTestSupportV1.makeFixture(seed: 938_100).activeCheckpoint
        let incumbentCheckpoint = try FieldDraftCheckpointV1(draftID: incumbentStage.draftID,
            workspaceID: workspaceID, scope: generic.scope, purpose: generic.purpose, codec: generic.codec,
            baseCanonicalRevision: 0, draftRevision: 1, payloadData: generic.payloadData, stageIDs: [],
            resumeAnchor: generic.resumeAnchor, state: .active, updatedAt: bound.updatedAt,
            mutationID: .init(rawValue: beginPreparationUUID(38_004)))
        _ = try adapter.compareAndSwap(checkpoint: incumbentCheckpoint, expectedDraftRevision: 0, expectedBaseRevision: 0)
        let incumbentReady = try FieldDraftCheckpointV1(draftID: incumbentCheckpoint.draftID,
            workspaceID: workspaceID, scope: generic.scope, purpose: generic.purpose, codec: generic.codec,
            baseCanonicalRevision: 0, draftRevision: 2, payloadData: generic.payloadData,
            stageIDs: [incumbentStage.stageID], resumeAnchor: generic.resumeAnchor, state: .active,
            updatedAt: bound.updatedAt, mutationID: incumbentStage.mutationID)
        let incumbentBundle = try FieldDraftStagePublicationBundleV1(expectedCheckpoint: incumbentCheckpoint,
            readyItem: incumbentStage, successorCheckpoint: incumbentReady)
        let incumbentReceipt = try adapter.publish(readyStage: incumbentBundle)
        let beforePreparation = try coordinator.workspaceWriter.currentRevision()
        let beforePreparationIDs = ids.callCount
        XCTAssertThrowsError(try service.prepareRawPhoto(parentDraftID: bound.draftID,
            expectedCheckpointSHA256: String(repeating: "0", count: 64), proposal: proposal)) { error in
            XCTAssertEqual(error as? FieldDraftFailureV1, .staleDraftRevision)
        }
        XCTAssertEqual(try coordinator.workspaceWriter.currentRevision(), beforePreparation)
        XCTAssertEqual(ids.callCount, beforePreparationIDs)
        let occupiedMutationIntent = try CheckRunnerPhotoRawStageIntentV1(stageID: intent.stageID,
            stageMutationID: bound.mutationID, stageCreatedAt: intent.stageCreatedAt,
            expectedSourceByteCount: intent.expectedSourceByteCount, provenanceID: intent.provenanceID,
            evidenceID: intent.evidenceID, evidenceCreatedAt: intent.evidenceCreatedAt)
        XCTAssertThrowsError(try service.prepareRawPhoto(parentDraftID: bound.draftID,
            expectedCheckpointSHA256: bound.checkpointSHA256, proposal: proposalWith(occupiedMutationIntent))) { error in
            XCTAssertEqual(error as? FieldDraftFailureV1, .staleDraftRevision)
        }
        XCTAssertEqual(try coordinator.workspaceWriter.currentRevision(), beforePreparation)
        XCTAssertEqual(ids.callCount, beforePreparationIDs)
        let occupiedStageIntent = try CheckRunnerPhotoRawStageIntentV1(stageID: incumbentStage.stageID,
            stageMutationID: intent.stageMutationID, stageCreatedAt: intent.stageCreatedAt,
            expectedSourceByteCount: intent.expectedSourceByteCount, provenanceID: intent.provenanceID,
            evidenceID: intent.evidenceID, evidenceCreatedAt: intent.evidenceCreatedAt)
        XCTAssertThrowsError(try service.prepareRawPhoto(parentDraftID: bound.draftID,
            expectedCheckpointSHA256: bound.checkpointSHA256, proposal: proposalWith(occupiedStageIntent))) { error in
            XCTAssertEqual(error as? FieldDraftFailureV1, .staleDraftRevision)
        }
        XCTAssertEqual(try coordinator.workspaceWriter.currentRevision(), beforePreparation)
        XCTAssertEqual(ids.callCount, beforePreparationIDs)
        XCTAssertEqual(try service.read(draftID: bound.draftID), bound)
        XCTAssertNil(try adapter.currentCheckpoint(workspaceID: workspaceID, draftID: childDraftID))
        XCTAssertEqual(try adapter.readyStagePublicationEvidence(for: incumbentBundle)?.receipt, incumbentReceipt)
        let retainedIncumbentBytes = try await attachmentStaging.data(stageID: incumbentStage.stageID)
        XCTAssertEqual(retainedIncumbentBytes, incumbentBytes)
        ids.enqueue([beginPreparationUUID(30_030), beginPreparationUUID(30_040)])
        let laterClockService = try ProductionCheckRunnerItemDraftServiceV1(session: coordinator,
            progress: progress, coordinator: runner, publishedRelease: publishedRelease,
            clock: FrozenBeginClock(value: intent.stageCreatedAt.addingTimeInterval(100)), ids: ids,
            attachmentStaging: attachmentStaging)
        let preparedPhoto = try laterClockService.prepareRawPhoto(parentDraftID: bound.draftID,
            expectedCheckpointSHA256: bound.checkpointSHA256, proposal: proposal)
        XCTAssertEqual(preparedPhoto, awaiting)
        XCTAssertEqual(try service.read(draftID: bound.draftID), parentPending)
        let preparedRevision = try coordinator.workspaceWriter.currentRevision()
        let preparedIDs = ids.callCount
        XCTAssertEqual(try service.prepareRawPhoto(parentDraftID: bound.draftID,
            expectedCheckpointSHA256: parentPending.checkpointSHA256, proposal: proposal), awaiting)
        XCTAssertEqual(try coordinator.workspaceWriter.currentRevision(), preparedRevision)
        XCTAssertEqual(ids.callCount, preparedIDs)
        let changedIntent = try CheckRunnerPhotoRawStageIntentV1(stageID: intent.stageID,
            stageMutationID: intent.stageMutationID, stageCreatedAt: intent.stageCreatedAt,
            expectedSourceByteCount: intent.expectedSourceByteCount + 1,
            provenanceID: intent.provenanceID, evidenceID: intent.evidenceID,
            evidenceCreatedAt: intent.evidenceCreatedAt)
        let divergentProposal = try proposalWith(changedIntent)
        XCTAssertThrowsError(try service.prepareRawPhoto(parentDraftID: bound.draftID,
            expectedCheckpointSHA256: parentPending.checkpointSHA256, proposal: divergentProposal)) { error in
            XCTAssertEqual(error as? FieldDraftFailureV1, .digestMismatch)
        }
        XCTAssertEqual(try coordinator.workspaceWriter.currentRevision(), preparedRevision)
        XCTAssertEqual(ids.callCount, preparedIDs)
        let rawCheckpoint = try photoCheckpoint(.rawReady(raw), revision: 2,
            state: .active, updatedAt: intent.stageCreatedAt,
            mutationID: raw.stagePublicationMutationID)
        let rawSourceURL = root.appendingPathComponent("selected-photo-source.png")
        try sourceData.write(to: rawSourceURL, options: .atomic)
        let cancelledPublication = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.publishRawPhoto(parentDraftID: bound.draftID,
                childDraftID: childDraftID, sourceURL: rawSourceURL)
        }
        do {
            _ = try await cancelledPublication.value
            XCTFail("Cancelled raw publication must leave the prepared child and physical stage unchanged")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(try coordinator.workspaceWriter.currentRevision(), preparedRevision)
        let cancelledStage = try await attachmentStaging.item(stageID: stageID)
        XCTAssertNil(cancelledStage)
        XCTAssertEqual(try adapter.currentCheckpoint(workspaceID: workspaceID, draftID: childDraftID), awaiting)
        let fifoSource = root.appendingPathComponent("selected-photo-source.fifo")
        XCTAssertEqual(Darwin.mkfifo(fifoSource.path, mode_t(0o600)), 0)
        var fifoBefore = stat()
        XCTAssertEqual(Darwin.lstat(fifoSource.path, &fifoBefore), 0)
        let fifoCompleted = XCTestExpectation(description: "Raw source FIFO rejects without a writer")
        let fifoPublication = Task { @MainActor in
            defer { fifoCompleted.fulfill() }
            do {
                _ = try await service.publishRawPhoto(parentDraftID: bound.draftID,
                    childDraftID: childDraftID, sourceURL: fifoSource)
                XCTFail("A FIFO source must fail without blocking or publishing a raw stage")
            } catch {
                XCTAssertEqual(error as? DraftAttachmentStagingFailureV1, .unsafePath)
            }
        }
        let fifoCompletion = await XCTWaiter.fulfillment(of: [fifoCompleted], timeout: 5)
        XCTAssertEqual(fifoCompletion, .completed)
        // Unblock the old faulty open after the assertion, allowing subsequent
        // state/preservation checks to run even if this regression returns.
        let fifoRescue = Darwin.open(fifoSource.path, O_RDWR | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        await fifoPublication.value
        if fifoRescue >= 0 { Darwin.close(fifoRescue) }
        var fifoAfter = stat()
        XCTAssertEqual(Darwin.lstat(fifoSource.path, &fifoAfter), 0)
        XCTAssertEqual(fifoAfter.st_mode & S_IFMT, S_IFIFO)
        XCTAssertEqual(fifoAfter.st_dev, fifoBefore.st_dev)
        XCTAssertEqual(fifoAfter.st_ino, fifoBefore.st_ino)
        XCTAssertEqual(try coordinator.workspaceWriter.currentRevision(), preparedRevision)
        XCTAssertEqual(try adapter.currentCheckpoint(workspaceID: workspaceID, draftID: childDraftID), awaiting)
        let rejectedStage = try await attachmentStaging.item(stageID: stageID)
        XCTAssertNil(rejectedStage)
        try FileManager.default.removeItem(at: fifoSource)
        let rawPublication = try await service.publishRawPhoto(parentDraftID: bound.draftID,
            childDraftID: childDraftID, sourceURL: rawSourceURL)
        let rawBundle = try FieldDraftStagePublicationBundleV1(expectedCheckpoint: awaiting,
            readyItem: ready, successorCheckpoint: rawCheckpoint)
        XCTAssertEqual(rawPublication, try XCTUnwrap(adapter.readyStagePublicationEvidence(for: rawBundle)))
        XCTAssertEqual(try adapter.currentCheckpoint(workspaceID: workspaceID, draftID: childDraftID),
                       rawCheckpoint)
        let publishedRevision = try coordinator.workspaceWriter.currentRevision()
        try FileManager.default.removeItem(at: rawSourceURL)
        // Exact retry authenticates the owned raw witness before accessing the
        // now-absent external source, and returns the original canonical receipt.
        let repeatedRawPublication = try await service.publishRawPhoto(parentDraftID: bound.draftID,
            childDraftID: childDraftID, sourceURL: rawSourceURL)
        XCTAssertEqual(repeatedRawPublication, rawPublication)
        XCTAssertEqual(try coordinator.workspaceWriter.currentRevision(), publishedRevision)
        let coldStaging = try DraftAttachmentStagingAdapterV1(applicationSupportURL: root,
                                                             workspaceID: workspaceID)
        let coldService = try ProductionCheckRunnerItemDraftServiceV1(session: coordinator,
            progress: progress, coordinator: runner, publishedRelease: publishedRelease,
            clock: clock, ids: ids, attachmentStaging: coldStaging)
        XCTAssertEqual(try coldService.prepareRawPhoto(parentDraftID: bound.draftID,
            expectedCheckpointSHA256: parentPending.checkpointSHA256, proposal: proposal), rawCheckpoint)
        XCTAssertEqual(try coordinator.workspaceWriter.currentRevision(), publishedRevision)
        XCTAssertEqual(ids.callCount, preparedIDs)
        let coldRawPublication = try await coldService.publishRawPhoto(parentDraftID: bound.draftID,
            childDraftID: childDraftID, sourceURL: rawSourceURL)
        XCTAssertEqual(coldRawPublication, rawPublication)
        XCTAssertEqual(try coordinator.workspaceWriter.currentRevision(), publishedRevision)
        for (wrongParent, wrongChild) in [
            (beginPreparationUUID(39_001), childDraftID),
            (bound.draftID, beginPreparationUUID(39_002)),
        ] {
            do {
                _ = try await service.publishRawPhoto(parentDraftID: wrongParent,
                    childDraftID: wrongChild, sourceURL: rawSourceURL)
                XCTFail("Raw publication must reject a parent or child outside its authenticated history")
            } catch {
                XCTAssertEqual(error as? FieldDraftFailureV1, .missingReceipt)
            }
            XCTAssertEqual(try coordinator.workspaceWriter.currentRevision(), publishedRevision)
        }
        let foreignStaging = try DraftAttachmentStagingAdapterV1(
            applicationSupportURL: root.appendingPathComponent("different-photo-owner"),
            workspaceID: workspaceID)
        let wrongRootService = try ProductionCheckRunnerItemDraftServiceV1(session: coordinator,
            progress: progress, coordinator: runner, publishedRelease: publishedRelease,
            clock: clock, ids: ids, attachmentStaging: foreignStaging)
        do {
            _ = try await wrongRootService.publishRawPhoto(parentDraftID: bound.draftID,
                childDraftID: childDraftID, sourceURL: rawSourceURL)
            XCTFail("A different physical owner cannot publish the current session's photo")
        } catch {
            XCTAssertEqual(error as? DraftAttachmentStagingFailureV1, .invalidRoot)
        }
        XCTAssertEqual(try coordinator.workspaceWriter.currentRevision(), publishedRevision)
        let pairCheckpoint = try photoCheckpoint(.pairReady(pair), revision: 3,
            state: .active, updatedAt: intent.stageCreatedAt,
            mutationID: .init(rawValue: beginPreparationUUID(30_041)))
        _ = try adapter.compareAndSwap(checkpoint: pairCheckpoint, expectedDraftRevision: 2,
            expectedBaseRevision: pairCheckpoint.baseCanonicalRevision)
        let committing = try photoCheckpoint(.preparedCommit(pair, commitAttempt), revision: 4,
            state: .committing, updatedAt: commitAttempt.preparedUpdatedAt,
            mutationID: .init(rawValue: beginPreparationUUID(30_042)))
        _ = try adapter.compareAndSwap(checkpoint: committing, expectedDraftRevision: 3,
            expectedBaseRevision: committing.baseCanonicalRevision)

        let reconstruction = try CheckRunnerPhotoDraftCodecV1.reconstructPhotoCommit(from: committing)
        let commit = reconstruction.draftCommit
        _ = try adapter.append(saga: commit.sagas[0], expectedRevision: 0)
        let rawRequest = try DraftImmutableContentWriteRequestV1(
            workspaceID: workspaceID, contentID: inspection.rawContentID,
            digest: inspection.sourceSHA256, byteLength: inspection.sourceByteCount,
            mediaType: inspection.sourceMediaType,
            mutationID: commitAttempt.reservationMutationID,
            createdAt: CheckRunnerPhotoRawReadyV1.formatOriginalRecordedAt(
                commitAttempt.promotionAt))
        let rawReceipt = try await EvidenceBundleStore(
            generationRootURL: session.generationRootURL
        ).persistImmutableOriginal(bytes: sourceData, request: rawRequest)
        try rawReceipt.validate(request: rawRequest, bytes: sourceData)
        let reference = try ContentReferenceV1(
            workspaceID: rawReceipt.workspaceID.rawValue.uuidString.lowercased(),
            contentID: rawReceipt.contentID, byteLength: rawReceipt.byteLength,
            mediaType: rawReceipt.mediaType, digests: .init([rawReceipt.digest]),
            byteRole: rawReceipt.byteRole, createdAt: rawReceipt.createdAt)
        let committedStage = try AttachmentStagingItemV1(stageID: ready.stageID,
            draftID: ready.draftID, workspaceID: ready.workspaceID,
            attachmentKind: ready.attachmentKind, scratchLeaseID: ready.scratchLeaseID,
            expectedByteCount: ready.expectedByteCount, actualByteCount: ready.actualByteCount,
            contentDigest: ready.contentDigest, contentReference: reference,
            processingJobID: ready.processingJobID, retryClass: ready.retryClass,
            state: .committed, protectionState: ready.protectionState,
            revision: ready.revision + 1,
            mutationID: .init(rawValue: DraftAttachmentStagingAdapterV1.deterministicUUID(
                "stage-mutation\u{1f}\(stageID.uuidString.lowercased())\u{1f}2\u{1f}COMMITTED\u{1f}\(inspection.sourceSHA256.hexadecimalValue)")))
        _ = try adapter.append(stagingItem: committedStage, expectedRevision: ready.revision)
        let locator = try ContentLocatorV1(locatorID: rawReceipt.locatorID,
            workspaceID: workspaceID.rawValue.uuidString.lowercased(),
            contentID: inspection.rawContentID, locatorRevision: 0,
            contentDigest: inspection.sourceSHA256,
            expectedByteLength: inspection.sourceByteCount)
        let reservation = try DraftContentReservationV1(
            reservationID: DraftAttachmentStagingAdapterV1.deterministicUUID(
                "reservation\u{1f}\(commit.plan.planSHA256)\u{1f}\(stageID.uuidString.lowercased())"),
            workspaceID: workspaceID, draftID: childDraftID, stageID: stageID,
            commitPlanSHA256: commit.plan.planSHA256,
            mutationID: commitAttempt.reservationMutationID,
            contentDigest: inspection.sourceSHA256, locator: locator,
            createdAt: commitAttempt.promotionAt,
            reviewAfter: commitAttempt.reservationReviewAfter,
            reconciliationState: .reserved, revision: 1)
        _ = try adapter.append(reservation: reservation, expectedRevision: 0)
        _ = try adapter.append(saga: commit.sagas[1], expectedRevision: 1)
        let accepted = try await runner.accept(candidate: candidate, assetID: source.assetID)
        XCTAssertEqual(accepted.id, reconstruction.targetCommand.evidenceID)
        XCTAssertEqual(accepted.sha256, reconstruction.targetCommand.sha256)
        XCTAssertEqual(accepted.thumbnailSHA256, reconstruction.targetCommand.thumbnailSHA256)
        let target = try XCTUnwrap(coordinator.workspaceWriter.checkRunnerPhotoEvidence(
            workspaceID: workspaceID, mutationID: commit.plan.mutationID))
        _ = try adapter.append(saga: commit.sagas[2], expectedRevision: 2)
        _ = try adapter.append(saga: commit.sagas[3], expectedRevision: 3)
        let receipt = try DraftCommitReceiptV1(receiptID: commit.commitReceiptID,
            workspaceID: workspaceID, draftID: childDraftID, sagaID: commit.retired.sagaID,
            commitPlanSHA256: commit.plan.planSHA256,
            sagaEventSHA256Chain: commit.sagas.map(\.sagaSHA256),
            targetMutationID: commit.plan.mutationID,
            targetReceiptSHA256: target.receipt.resultSHA256,
            consumedStageToContentID: [stageID.uuidString: locator.contentID],
            committedAt: target.receipt.committedAt,
            mutationID: commit.rowMutationIDs.terminalBundleMutationID)
        let terminal = try FieldDraftCheckpointV1(draftID: childDraftID,
            workspaceID: workspaceID, scope: committing.scope, purpose: committing.purpose,
            codec: committing.codec, baseCanonicalRevision: committing.baseCanonicalRevision,
            draftRevision: 5, payloadData: committing.payloadData,
            stageIDs: committing.stageIDs, resumeAnchor: committing.resumeAnchor,
            state: .committed, lastDurableMutationID: commit.rowMutationIDs.terminalBundleMutationID,
            lastReceiptSHA256: receipt.receiptSHA256,
            updatedAt: commit.terminalCheckpointUpdatedAt,
            mutationID: commit.rowMutationIDs.terminalBundleMutationID)
        _ = try adapter.apply(commitTerminalBundle: .init(retiredSaga: commit.retired,
            committedCheckpoint: terminal, receipt: receipt),
            expectedDraftRevision: 4, expectedSagaRevision: 4)
        let committedSlot = CheckRunnerPhotoSlotV1.committed(childDraftID: childDraftID,
            captureStep: .wide, purposeKey: "wide_context",
            committedChildDraftRevision: terminal.draftRevision,
            committedChildCheckpointSHA256: terminal.checkpointSHA256,
            childCommitReceiptID: receipt.receiptID,
            childCommitReceiptSHA256: receipt.receiptSHA256,
            evidenceID: target.command.evidenceID,
            targetMutationID: target.receipt.mutationID,
            targetReceiptSHA256: target.receipt.resultSHA256)
        let committedField = try CheckRunnerItemFieldStateV1(preflight: parent.field.preflight,
            begin: parent.field.begin, outcome: parent.field.outcome,
            wideContext: committedSlot, closeDetail: parent.field.closeDetail,
            semanticAnchor: parent.field.semanticAnchor)
        let committedPayload = try CheckRunnerItemDraftPayloadV1(editing: source,
            field: committedField)
        let parentCommitted = try parentSuccessor(parentPending, payload: committedPayload,
            updatedAt: commit.terminalCheckpointUpdatedAt,
            mutationID: .init(rawValue: beginPreparationUUID(30_031)))
        _ = try adapter.compareAndSwap(checkpoint: parentCommitted,
            expectedDraftRevision: parentPending.draftRevision,
            expectedBaseRevision: parentPending.baseCanonicalRevision)
        let beforeRead = try snapshot()
        let idCalls = ids.callCount
        let value = try XCTUnwrap(service.readCurrentPhotoTarget(
            parentDraftID: parentCommitted.draftID, childDraftID: childDraftID))
        try service.validateForPublication(value)
        let mediaRead = try await service.readCurrentPhotoMedia(
            parentDraftID: parentCommitted.draftID, childDraftID: childDraftID)
        let mediaValue = try XCTUnwrap(mediaRead)
        try await service.validateForPublication(mediaValue)
        XCTAssertEqual(mediaValue.targetRead.currentTarget, value.currentTarget)
        XCTAssertEqual(mediaValue.media.rawReference, reference)
        XCTAssertEqual(mediaValue.media.sourceInspection, inspection)
        XCTAssertEqual(mediaValue.media.normalizedPair, normalized)
        XCTAssertEqual(ids.callCount, idCalls)
        XCTAssertEqual(try snapshot(), beforeRead)
        return .init(service: service, value: value, mediaValue: mediaValue,
            sourceData: sourceData)
    }

    private func parentSuccessor(_ predecessor: FieldDraftCheckpointV1,
        payload: CheckRunnerItemDraftPayloadV1, updatedAt: Date,
        mutationID: MutationIDV1) throws -> FieldDraftCheckpointV1 {
        try FieldDraftCheckpointV1(draftID: predecessor.draftID,
            workspaceID: predecessor.workspaceID, scope: predecessor.scope,
            purpose: predecessor.purpose, codec: predecessor.codec,
            baseCanonicalRevision: predecessor.baseCanonicalRevision,
            draftRevision: predecessor.draftRevision + 1,
            payloadData: CheckRunnerItemDraftCodecV1.encode(payload), stageIDs: [],
            resumeAnchor: CheckRunnerItemDraftCodecV1.resumeAnchor(payload: payload),
            state: .active, updatedAt: updatedAt, mutationID: mutationID)
    }

    func captureSource() throws -> CheckRunnerRoundItemSourceV1 {
        try runner.captureFrozenBeginSource(
            read: read, progress: progress, itemID: itemID,
            publishedRelease: publishedRelease,
            requestedEntry: issueID.map { .recheck(issueID: $0) } ?? .check
        )
    }

    func validSubmission() -> BeginDraftSubmission {
        BeginDraftSubmission(
            assetID: assetID, requestedStage: issueID == nil ? .check : .recheck,
            issueID: issueID,
            observedAtUTC: Date(timeIntervalSince1970: 1_789_323_456),
            confirmedTimeZoneID: "America/New_York",
            afterDarkAccepted: true, safePositionAccepted: true
        )
    }

    func makeRunner(
        draftAccessState: @escaping @MainActor () -> DraftAccessNormalizedStateV1
    ) throws -> CheckRunnerCoordinator {
        try CheckRunnerCoordinator(
            modelContext: context,
            packageLifecycleDependencies: coordinator.packageLifecycleDependencies(
                profileRegistry: coordinator.lifecycleProfileRegistry
            ),
            packageLifecycleProfile: profile,
            draftAccessState: draftAccessState
        )
    }

    func expectedRecordRevisions(recordID: UUID) throws -> [WorkspaceEntityRevisionV1] {
        let current = try coordinator.workspaceWriter.currentRevision()
        let known = Dictionary(uniqueKeysWithValues: current.entityRevisions.map {
            ($0.identity, $0.revision)
        })
        var identities = try [
            WorkspaceEntityIdentityV1(kind: .workflowRecord, id: recordID),
            WorkspaceEntityIdentityV1(kind: .asset, id: assetID),
        ]
        if let issueID { identities.append(try .init(kind: .issue, id: issueID)) }
        if let recheckParentID {
            identities.append(try .init(kind: .workflowRecord, id: recheckParentID))
        }
        return identities.sorted { $0.stableKey < $1.stableKey }.map {
            .init(identity: $0, revision: known[$0, default: 0])
        }
    }

    func expectedCommand(
        recordID: UUID, observedAt: Date, timeZoneID: String, parentID: UUID?
    ) throws -> CheckDraftMutationV1 {
        let frozen = try TimeContextRule.freeze(
            observedAtUTC: observedAt, confirmedTimeZoneID: timeZoneID
        )
        let afterDark = try XCTUnwrap(signPack.acknowledgements.first { $0.key == "after_dark" })
        let safe = try XCTUnwrap(signPack.acknowledgements.first {
            $0.key == "safe_authorized_position"
        })
        return CheckDraftMutationV1(
            recordID: recordID, assetID: assetID, issueID: issueID,
            parentRecordID: parentID, stage: issueID == nil
                ? WorkflowStage.check.rawValue : WorkflowStage.recheck.rawValue,
            draftStepKey: WorkflowDraftStep.wide.rawValue,
            startedAt: observedAt, observedAtUTC: frozen.observedAtUTC,
            timeZoneID: frozen.timeZoneID, utcOffsetMinutes: frozen.utcOffsetMinutes,
            localDate: frozen.localDate, localTime: frozen.localTime,
            afterDarkAcknowledgementKey: afterDark.key,
            afterDarkAcknowledgementCopy: afterDark.copy,
            afterDarkAcknowledgementVersion: afterDark.version,
            afterDarkAcknowledgementAccepted: true,
            safePositionAcknowledgementKey: safe.key,
            safePositionAcknowledgementCopy: safe.copy,
            safePositionAcknowledgementVersion: safe.version,
            safePositionAcknowledgementAccepted: true,
            packID: signPack.packID, packSchemaVersion: signPack.schemaVersion,
            packContentVersion: signPack.contentVersion,
            pdfTemplateID: profile.pdfTemplate.id,
            pdfTemplateVersion: profile.pdfTemplate.version
        )
    }

    func snapshot() throws -> Snapshot {
        Snapshot(
            revision: try coordinator.workspaceWriter.currentRevision(),
            history: try coordinator.workspaceWriter.sourceMutationHistorySnapshot(),
            rows: try rowSnapshot()
        )
    }

    func rowSnapshot() throws -> RowSnapshot {
        let checkpoints = try context.fetch(FetchDescriptor<FieldDraftCheckpointRow>()).map {
            try $0.value()
        }.sorted { $0.draftID.uuidString < $1.draftID.uuidString }
        let rounds = try context.fetch(FetchDescriptor<RoundSessionRevisionRowV1>()).map {
            try $0.value()
        }.sorted {
            ($0.sessionID.uuidString, $0.revision) < ($1.sessionID.uuidString, $1.revision)
        }
        let packages = try context.fetch(FetchDescriptor<PromotedPackageReleaseRow>()).map {
            try $0.value()
        }.sorted { $0.releaseRecordID.uuidString < $1.releaseRecordID.uuidString }
        return RowSnapshot(
            checkpointBytes: try checkpoints.map { try FieldDraftCanonicalCodecV1.encode($0) },
            roundBytes: try rounds.map { try RoundSessionCanonicalCodecV1.encode($0) },
            packageBytes: try packages.map { try PackageEvolutionCanonicalCodecV1.encode($0) },
            sites: try context.fetch(FetchDescriptor<Site>()).map {
                .init(id: $0.id, label: $0.label, timeZoneID: $0.timeZoneID, updatedAt: $0.updatedAt)
            }.sorted { $0.id.uuidString < $1.id.uuidString },
            assets: try context.fetch(FetchDescriptor<Asset>()).map {
                .init(id: $0.id, siteID: $0.siteID, packID: $0.packID,
                      schemaVersion: $0.packSchemaVersion,
                      contentVersion: $0.packContentVersion,
                      label: $0.label, updatedAt: $0.updatedAt)
            }.sorted { $0.id.uuidString < $1.id.uuidString },
            workflows: try context.fetch(FetchDescriptor<WorkflowRecord>()).map {
                .init(id: $0.id, assetID: $0.assetID, issueID: $0.issueID,
                      parentID: $0.parentRecordID, stage: $0.stage, state: $0.state,
                      startedAt: $0.startedAt, timeZoneID: $0.timeZoneID)
            }.sorted { $0.id.uuidString < $1.id.uuidString },
            issues: try context.fetch(FetchDescriptor<Issue>()).map {
                .init(id: $0.id, assetID: $0.assetID, openedBy: $0.openedByRecordID,
                      status: $0.status, resolvedBy: $0.resolvedByRecordID)
            }.sorted { $0.id.uuidString < $1.id.uuidString },
            hasChanges: context.hasChanges
        )
    }

    func closeCoordinator() throws {
        guard !coordinatorClosed else { return }
        try coordinator.invalidateAndReleaseWriter()
        coordinatorClosed = true
    }

    private static func installPublishedRelease(
        _ release: InspectionPackageReleaseV1,
        in coordinator: StoreSessionCoordinator,
        context: ModelContext
    ) throws {
        let journal = try MutationJournalStoreV1(
            modelContext: context, identity: coordinator.workspaceIdentity,
            generationID: coordinator.generationID, allowStateBootstrap: false
        )
        try journal.validateAll()
        let promoted = try PromotedPackageReleaseV1(
            releaseRecordID: beginPreparationUUID(10_040),
            workspaceID: coordinator.workspaceID, packageRelease: release,
            mutationID: .init(rawValue: beginPreparationUUID(10_041)),
            promotedAt: Date(timeIntervalSince1970: 1_789_000_000)
        )
        context.insert(try PromotedPackageReleaseRow(promoted))
        context.insert(EntityMutationRevisionRow(
            identity: try .init(kind: .promotedPackageRelease, id: promoted.releaseRecordID),
            revision: promoted.revision, externalProjectionSHA256: promoted.releaseRecordSHA256
        ))
        try journal.stageMutableSemanticStateAfterAuthorizedExternalMutation()
        try context.save()
        try journal.validateAll()
    }

    private static func installRecheckLineage(
        issueID: UUID, parentID: UUID, assetID: UUID, signPack: SignPack,
        coordinator: StoreSessionCoordinator, context: ModelContext
    ) throws {
        let openingID = beginPreparationUUID(10_021)
        let opening = completedRecord(
            id: openingID, assetID: assetID, issueID: issueID, parentID: nil,
            stage: .check, signPack: signPack
        )
        let parent = completedRecord(
            id: parentID, assetID: assetID, issueID: issueID, parentID: openingID,
            stage: .work, signPack: signPack
        )
        let issue = Issue(
            id: issueID, assetID: assetID, openedByRecordID: openingID,
            labelKey: "dark_section", labelDisplaySnapshot: "Section appears dark",
            status: .recheckDue, resolvedByRecordID: nil,
            createdAt: opening.startedAt, updatedAt: parent.completedAt ?? parent.startedAt
        )
        context.insert(opening); context.insert(parent); context.insert(issue)
        for record in [opening, parent] {
            let basis = try XCTUnwrap(ObservationAndTimeLegacyMigrationV1.observationBasis(
                couldNotVerifyKey: record.couldNotVerifyKey,
                displaySnapshot: record.couldNotVerifyDisplaySnapshot,
                registryVersion: record.couldNotVerifyRegistryVersion
            ))
            let temporal = try XCTUnwrap(ObservationAndTimeLegacyMigrationV1.temporalContext(
                observedAtUTC: record.observedAtUTC, recordedAtUTC: record.startedAt,
                timeZoneID: record.timeZoneID, utcOffsetMinutes: record.utcOffsetMinutes,
                localDate: record.localDate, localTime: record.localTime
            ))
            context.insert(try ObservationAndTimeRow(
                recordID: record.id, observationBasis: basis, temporalContext: temporal
            ))
        }
        XCTAssertEqual(Set(try ObservationAndTimeRowStoreV1.validatedIndex(in: context).keys),
                       Set([openingID, parentID]))
        for identity in try [
            WorkspaceEntityIdentityV1(kind: .workflowRecord, id: openingID),
            WorkspaceEntityIdentityV1(kind: .workflowRecord, id: parentID),
            WorkspaceEntityIdentityV1(kind: .issue, id: issueID),
        ] {
            context.insert(EntityMutationRevisionRow(identity: identity, revision: 1))
        }
        let journal = try MutationJournalStoreV1(
            modelContext: context, identity: coordinator.workspaceIdentity,
            generationID: coordinator.generationID, allowStateBootstrap: false
        )
        try journal.stageMutableSemanticStateAfterAuthorizedExternalMutation()
        try context.save()
        try journal.validateAll()
    }

    private static func completedRecord(
        id: UUID, assetID: UUID, issueID: UUID, parentID: UUID?,
        stage: WorkflowStage, signPack: SignPack
    ) -> WorkflowRecord {
        WorkflowRecord(
            id: id, assetID: assetID, packetID: nil, issueID: issueID,
            parentRecordID: parentID, recordRevisionRootID: id,
            revisesRecordID: nil, evidenceSourceRecordID: nil,
            revisionKind: .original, stage: stage, state: .completed,
            draftStepKey: nil, startedAt: Date(timeIntervalSince1970: 100),
            completedAt: Date(timeIntervalSince1970: 200), observedAtUTC: nil,
            timeZoneID: nil, utcOffsetMinutes: nil, localDate: nil, localTime: nil,
            afterDarkAcknowledgementKey: nil, afterDarkAcknowledgementCopy: nil,
            afterDarkAcknowledgementVersion: nil, afterDarkAcknowledgementAccepted: nil,
            safePositionAcknowledgementKey: nil, safePositionAcknowledgementCopy: nil,
            safePositionAcknowledgementVersion: nil, safePositionAcknowledgementAccepted: nil,
            packID: signPack.packID, packSchemaVersion: signPack.schemaVersion,
            packContentVersion: signPack.contentVersion,
            pdfTemplateID: "field.evidence.pdf.worklight.v1", pdfTemplateVersion: 1,
            outcomeKey: stage == .work ? "work_recorded" : "visible_issue",
            couldNotVerifyKey: nil, couldNotVerifyDisplaySnapshot: nil,
            couldNotVerifyRegistryVersion: nil,
            workPerformedLocalDate: stage == .work ? "1970-01-01" : nil,
            workDescription: stage == .work ? "Completed fixture work" : nil,
            note: nil, finalizationMutationID: beginPreparationUUID(10_090 + (stage == .work ? 1 : 0))
        )
    }

    private static func actor(workspaceID: WorkspaceID) throws -> ActorSnapshotV1 {
        let actor = try LocalActorReferenceV1(
            actorReferenceID: beginPreparationUUID(10_050), workspaceID: workspaceID,
            displayName: "Frozen Begin fixture"
        )
        return try ActorSnapshotV1(
            snapshotID: beginPreparationUUID(10_051), workspaceID: workspaceID,
            actor: actor, responsibility: .recordedBy,
            displayNameAtTime: "Frozen Begin fixture",
            capturedAt: Date(timeIntervalSince1970: 1_789_000_000)
        )
    }

    private static func manifest(
        round: RoundSessionV1, release: InspectionPackageReleaseV1
    ) throws -> OfflineReadinessManifestV1 {
        let package = try RoundPackageReleaseReferenceV1(release)
        return try OfflineReadinessManifestBuilderV1.build(snapshot: .init(
            session: round.reference, expectedPackage: package, observedPackage: package,
            selectedAssets: round.items.map(\.selection).sorted {
                $0.assetID.uuidString < $1.assetID.uuidString
            },
            observedAssetIDs: Set(round.items.map { $0.selection.assetID }),
            guidanceReferenceIDs: [], availableGuidanceReferenceIDs: [],
            contentRequirements: [], contentObservations: [], expectedFieldReferences: [],
            fieldReferenceReadiness: [],
            storage: .init(capacityState: .checked, availableBytes: 100_000),
            access: .init(protectedDataAvailable: true),
            checkedAt: Date(timeIntervalSince1970: 1_789_000_000),
            timeZoneIdentifier: "America/New_York", clockState: .checked
        ))
    }
}

/// Shared real-owner fixture for service and cold StartupRouter photo cases.
@MainActor
struct FrozenProductionPhotoV1 {
    let owner: StoreSessionCoordinator
    let service: ProductionCheckRunnerItemDraftServiceV1
    let runner: CheckRunnerCoordinator
    let adapter: DraftAttachmentStagingAdapterV1
    let parentID: UUID
    let childID: UUID
    let intent: CheckRunnerPhotoRawStageIntentV1

    static func make(_ h: FrozenBeginFixture, parentID: UUID? = nil,
        step: WorkflowDraftStep = .wide, publishRaw: Bool = true,
        failure: EvidenceBundleStoreFailureInjection? = nil,
        diagnosticPhase: (@MainActor (String) -> Void)? = nil) async throws -> Self {
        diagnosticPhase?("owners.begin")
        let owners = try reopen(owner: h.coordinator, root: h.root, profile: h.profile,
            release: h.publishedRelease, clock: h.clock, ids: h.ids, failure: failure)
        diagnosticPhase?("owners.end")
        diagnosticPhase?("parent-and-proposal.begin")
        let service = owners.service
        let parent: FieldDraftCheckpointV1
        if let parentID { parent = try service.read(draftID: parentID) }
        else {
            let initial = try service.create(source: h.captureSource(), preflight: .init(
                timeZoneID: "America/Chicago", isTimeZoneConfirmed: true,
                confirmedTimeZoneID: "America/Chicago", afterDarkAccepted: true, safePositionAccepted: true))
            let prepared = try service.prepareBegin(draftID: initial.draftID,
                expectedCheckpointSHA256: initial.checkpointSHA256, observedAtUTC: h.clock.millisecondValue)
            parent = try service.resumeInitialBegin(draftID: prepared.draftID)
        }
        return try await stage(owner: h.coordinator, service: service,
            runner: owners.runner, adapter: owners.adapter, root: h.root,
            parent: parent, step: step,
            bytes: WorkCanonicalIntegrationTestSupportV1.makePNG(seed: step == .wide ? 183 : 184),
            clock: h.clock, publishRaw: publishRaw, diagnosticPhase: diagnosticPhase)
    }

    /// Reuses the genuine raw-stage path with an already authenticated parent
    /// in an existing mixed backup workspace. Caller supplies real picker bytes.
    static func stage(owner: StoreSessionCoordinator,
        service: ProductionCheckRunnerItemDraftServiceV1, runner: CheckRunnerCoordinator,
        adapter: DraftAttachmentStagingAdapterV1, root: URL,
        parent: FieldDraftCheckpointV1, step: WorkflowDraftStep, bytes: Data,
        clock: FrozenBeginClock, publishRaw: Bool = true,
        diagnosticPhase: (@MainActor (String) -> Void)? = nil) async throws -> Self {
        let payload = try CheckRunnerItemDraftCodecV1.validateCheckpoint(parent)
        let begin = try XCTUnwrap(payload.field.begin.attempt)
        let base = max(parent.updatedAt, clock.millisecondValue)
        let intent = try CheckRunnerPhotoRawStageIntentV1(stageID: UUID(), stageMutationID: .init(rawValue: UUID()),
            stageCreatedAt: base.addingTimeInterval(2), expectedSourceByteCount: Int64(bytes.count),
            provenanceID: "photo-production-journey", evidenceID: UUID(), evidenceCreatedAt: base.addingTimeInterval(1))
        let childID = UUID()
        let proposal = try CheckRunnerPhotoDraftPayloadV1(workspaceID: owner.workspaceID,
            childDraftID: childID, parentDraftID: parent.draftID, recordID: begin.recordCommand.recordID,
            assetID: payload.source.assetID, sourceBinding: payload.source,
            workflowStage: payload.source.requestedEntry.stage, captureStep: step,
            purposeKey: step == .wide ? "wide_context" : "close_detail", origin: .humanCapture,
            phase: .awaitingRawStage(intent))
        diagnosticPhase?("parent-and-proposal.end")
        diagnosticPhase?("raw-prepare.begin")
        _ = try service.prepareRawPhoto(parentDraftID: parent.draftID,
            expectedCheckpointSHA256: parent.checkpointSHA256, proposal: proposal)
        diagnosticPhase?("raw-prepare.end")
        if publishRaw {
            diagnosticPhase?("raw-publish.begin")
            let url = root.appendingPathComponent("picker-\(childID.uuidString).png")
            try bytes.write(to: url)
            _ = try await service.publishRawPhoto(parentDraftID: parent.draftID, childDraftID: childID, sourceURL: url)
            diagnosticPhase?("raw-publish.end")
        }
        clock.value = intent.stageCreatedAt.addingTimeInterval(1)
        return .init(owner: owner, service: service, runner: runner, adapter: adapter,
            parentID: parent.draftID, childID: childID, intent: intent)
    }

    static func reopen(owner: StoreSessionCoordinator, root: URL,
        profile: WorkspacePackageLifecycleProfileV1, release: InspectionPackageReleaseV1,
        clock: any ApplicationClock, ids: any ApplicationIDSource,
        failure: EvidenceBundleStoreFailureInjection? = nil) throws
        -> (service: ProductionCheckRunnerItemDraftServiceV1, runner: CheckRunnerCoordinator,
            adapter: DraftAttachmentStagingAdapterV1) {
        let gate = AppAccessGateV1(setting: .absentDisabled, authentication: FrozenBeginAuthentication(),
            clock: clock, identifiers: ids)
        let transitions = try owner.makeRoundSessionTransitionService(accessGate: gate)
        let progress = try owner.makeRepetitiveCaptureProgressService(transitions: transitions)
        let runner = try CheckRunnerCoordinator(modelContext: owner.modelContext,
            packageLifecycleDependencies: owner.packageLifecycleDependencies(),
            packageLifecycleProfile: profile, evidenceStoreFailureInjection: failure)
        runner.configureCapture(generationRootURL: owner.generationRootURL)
        let adapter = try DraftAttachmentStagingAdapterV1(applicationSupportURL: root,
            workspaceID: owner.workspaceID,
            immutableContentWriter: EvidenceBundleStore(generationRootURL: owner.generationRootURL))
        let service = try ProductionCheckRunnerItemDraftServiceV1(session: owner, progress: progress,
            coordinator: runner, publishedRelease: release, clock: clock, ids: ids, attachmentStaging: adapter)
        return (service, runner, adapter)
    }

    func checkpoint() throws -> FieldDraftCheckpointV1 {
        let id = childID
        return try XCTUnwrap(owner.modelContext.fetch(FetchDescriptor<FieldDraftCheckpointRow>(
            predicate: #Predicate { $0.draftID == id })).first).value()
    }

    func attempt(pairCheckpoint: FieldDraftCheckpointV1,
                 reservationMutationID: MutationIDV1? = nil,
                 instant: Date? = nil) throws -> CheckRunnerPhotoCommitAttemptV1 {
        let payload = try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(pairCheckpoint)
        let instant = instant ?? pairCheckpoint.updatedAt.addingTimeInterval(1)
        let continuation = try XCTUnwrap(owner.workspaceWriter.checkRunnerPhotoContinuationEvidence(
            workspaceID: owner.workspaceID, parentDraftID: parentID, childDraftID: childID))
        let outputs = try [WorkspaceEntityIdentityV1(kind: .workflowRecord, id: payload.recordID).stableKey,
            WorkspaceEntityIdentityV1(kind: .evidenceFile, id: intent.evidenceID).stableKey].sorted()
        return try .init(planID: UUID(), expectedWorkflowRecordRevision: continuation.currentWorkflowPostImage.revision,
            targetMutationID: .init(rawValue: intent.evidenceID), outputKeys: outputs,
            reservationMutationID: reservationMutationID ?? .init(rawValue: UUID()),
            reservationReviewAfter: instant.addingTimeInterval(90), preparedSagaID: UUID(),
            preparedSagaMutationID: .init(rawValue: UUID()), preparedUpdatedAt: instant,
            contentPromotedSagaID: UUID(), contentPromotedSagaMutationID: .init(rawValue: UUID()),
            contentPromotedUpdatedAt: instant.addingTimeInterval(2), targetCommittedSagaID: UUID(),
            targetCommittedSagaMutationID: .init(rawValue: UUID()), targetCommittedUpdatedAt: instant.addingTimeInterval(3),
            draftRetirePendingSagaID: UUID(), draftRetirePendingSagaMutationID: .init(rawValue: UUID()),
            draftRetirePendingUpdatedAt: instant.addingTimeInterval(4), draftRetiredSagaID: UUID(),
            draftRetiredUpdatedAt: instant.addingTimeInterval(5), commitReceiptID: UUID(),
            terminalBundleMutationID: .init(rawValue: UUID()), terminalCheckpointUpdatedAt: instant.addingTimeInterval(6),
            promotionAt: instant.addingTimeInterval(1))
    }
}

/// Real Begin, photo and finalizer owners; no fabricated positive receipt.
@MainActor
func makeFrozenParentFinalizationDraft(_ h: FrozenBeginFixture, selection: CheckOutcomeSelection,
    photoCount: Int, diagnosticPhase: (@MainActor (String) -> Void)? = nil
) async throws -> (service: ProductionCheckRunnerItemDraftServiceV1, checkpoint: FieldDraftCheckpointV1) {
    diagnosticPhase?("parent.setup.begin")
    let outcome: CheckRunnerEditableOutcomeV1
    switch selection {
    case .noVisibleIssue: outcome = .init(selection: .noVisibleIssue)
    case let .visibleIssue(key): outcome = .init(selection: .visibleIssue(labelKey: key), choice: .visibleIssue)
    case let .couldNotVerify(key, note):
        outcome = .init(selection: .couldNotVerify(reasonKey: key, note: note), choice: .couldNotVerify,
            selectedCouldNotVerifyReasonKey: key, couldNotVerifyNote: note ?? "", startsWithCouldNotVerify: true)
    case let .resolved(note): outcome = .init(selection: .resolved(note: note), recheckNote: note ?? "")
    case let .issueStillVisible(note): outcome = .init(selection: .issueStillVisible(note: note), recheckNote: note ?? "")
    case let .originalResolvedDifferentIssue(key, note):
        outcome = .init(selection: .originalResolvedDifferentIssue(labelKey: key, note: note),
            choice: .differentIssue, recheckNote: note ?? "")
    }
    h.runner.configureCapture(generationRootURL: h.coordinator.generationRootURL)
    let staging = try DraftAttachmentStagingAdapterV1(applicationSupportURL: h.root, workspaceID: h.workspaceID,
        immutableContentWriter: EvidenceBundleStore(generationRootURL: h.coordinator.generationRootURL))
    let service = try ProductionCheckRunnerItemDraftServiceV1(session: h.coordinator, progress: h.progress,
        coordinator: h.runner, publishedRelease: h.publishedRelease, clock: h.clock, ids: h.ids, attachmentStaging: staging)
    diagnosticPhase?("parent.setup.end")
    diagnosticPhase?("parent.create.begin")
    let created = try service.create(source: h.captureSource(), preflight: .init(
        timeZoneID: "America/Chicago", isTimeZoneConfirmed: true, confirmedTimeZoneID: "America/Chicago",
        afterDarkAccepted: true, safePositionAccepted: true), outcome: outcome)
    diagnosticPhase?("parent.create.end")
    diagnosticPhase?("parent.prepare-begin.begin")
    _ = try service.prepareBegin(draftID: created.draftID, expectedCheckpointSHA256: created.checkpointSHA256,
        observedAtUTC: h.clock.millisecondValue)
    diagnosticPhase?("parent.prepare-begin.end")
    diagnosticPhase?("parent.resume-begin.begin")
    _ = try service.resumeInitialBegin(draftID: created.draftID)
    diagnosticPhase?("parent.resume-begin.end")
    let photoSteps: [WorkflowDraftStep] = [.wide, .close]
    for (photoIndex, step) in photoSteps.prefix(photoCount).enumerated() {
        diagnosticPhase?("photo.\(photoIndex).make.begin")
        let photo = try await FrozenProductionPhotoV1.make(h, parentID: created.draftID, step: step,
            diagnosticPhase: diagnosticPhase)
        diagnosticPhase?("photo.\(photoIndex).make.end")
        diagnosticPhase?("photo.\(photoIndex).pair.begin")
        let pair = try await photo.service.preparePhotoPair(parentDraftID: photo.parentID, childDraftID: photo.childID)
        diagnosticPhase?("photo.\(photoIndex).pair.end")
        diagnosticPhase?("photo.\(photoIndex).commit-prepare.begin")
        let attempt = try photo.attempt(pairCheckpoint: pair)
        _ = try photo.service.preparePhotoCommit(parentDraftID: photo.parentID, childDraftID: photo.childID,
            expectedCheckpointSHA256: pair.checkpointSHA256, proposal: attempt)
        diagnosticPhase?("photo.\(photoIndex).commit-prepare.end")
        diagnosticPhase?("photo.\(photoIndex).commit.begin")
        _ = try await photo.service.resumePhotoCommit(parentDraftID: photo.parentID, childDraftID: photo.childID)
        diagnosticPhase?("photo.\(photoIndex).commit.end")
        h.clock.value = attempt.terminalCheckpointUpdatedAt.addingTimeInterval(1)
    }
    diagnosticPhase?("parent.final-read.begin")
    let checkpoint = try service.read(draftID: created.draftID)
    h.clock.value = max(h.clock.millisecondValue, checkpoint.updatedAt).addingTimeInterval(1)
    diagnosticPhase?("parent.final-read.end")
    return (service, checkpoint)
}

final class FrozenBeginCountingIDs: ApplicationIDSource, @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [UUID] = []
    private var count = 0

    var callCount: Int { lock.withLock { count } }

    func enqueue(_ values: [UUID]) {
        lock.withLock { queued.append(contentsOf: values) }
    }

    func makeID() -> UUID {
        lock.withLock {
            count += 1
            if !queued.isEmpty { return queued.removeFirst() }
            return beginPreparationUUID(20_000 + count)
        }
    }
}

final class FrozenBeginClock: ApplicationClock, @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Date
    var value: Date {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
    var millisecondValue: Date {
        Date(timeIntervalSince1970: floor(value.timeIntervalSince1970 * 1_000) / 1_000)
    }
    init(value: Date) { storedValue = value }
    func now() -> Date { value }
}

actor FrozenBeginAuthentication: LocalAuthenticationClient {
    func availability() -> LocalAuthenticationAvailabilityV1 {
        .systemValue(status: .available, biometry: .faceID)
    }
    func authenticate(_ attempt: LocalAuthenticationAttemptV1) -> LocalAuthenticationOutcomeV1 {
        .authenticated
    }
    func cancel(attemptID: UUID) {}
}

func frozenBeginShippingRelease(stage: WorkflowStage) throws -> InspectionPackageReleaseV1 {
    let package = try ShippingIlluminatedSignAdapterV1.inspectionPackage()
    let workflow = try ShippingIlluminatedSignAdapterV1.finalizationWorkflow(
        from: .illuminatedSignV1, stage: stage
    )
    return try InspectionPackageReleasePublisherV1.publish(
        InspectionPackageReleasePublisherV1.test(.makeDraft(package: package, workflow: workflow))
    ).release
}

func beginPreparationUUID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", value))!
}

func frozenBeginJSONObject(_ data: Data) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

/// Semantic fixture mutations still pass closed typed decoding and the real
/// canonical codec. Transport formatting must not mask their target predicate.
func decodeFrozenBeginJSON<Value: Codable>(_ type: Value.Type, object: [String: Any]) throws -> Value {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    let value = try decoder.decode(type, from: data)
    return try FieldDraftCanonicalCodecV1.decode(type, from: FieldDraftCanonicalCodecV1.encode(value))
}

private func jsonKeys(_ value: Any) -> Set<String> {
    if let object = value as? [String: Any] {
        return object.reduce(into: Set(object.keys)) { result, pair in
            result.formUnion(jsonKeys(pair.value))
        }
    }
    if let array = value as? [Any] {
        return array.reduce(into: Set<String>()) { result, element in
            result.formUnion(jsonKeys(element))
        }
    }
    return []
}

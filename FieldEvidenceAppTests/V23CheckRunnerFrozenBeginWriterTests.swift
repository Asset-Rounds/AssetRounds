import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

@MainActor
final class V23CheckRunnerFrozenBeginWriterTests: XCTestCase {
    func testFrozenBeginWriterCommitsOriginalTimeAndReplaysWithoutEffects() throws {
        try withFrozenBeginFixture("writer-check", entry: .check,
                                   storedTimeZoneID: "America/New_York") { h in
            let attempt = try prepareWriterAttempt(h, recordID: 9_501)
            let writer = h.coordinator.workspaceWriter
            let before = try writer.currentRevision()
            let original = try writer.commitFrozenCheckRunnerDraft(attempt)
            XCTAssertEqual(original.command, .createCheckDraft(attempt.recordCommand))
            XCTAssertEqual(original.receipt.committedAt, attempt.recordCommittedAt)
            XCTAssertEqual(original.envelope.expectedRevision.workspaceRevision, before.revision)
            XCTAssertEqual(original.envelope.expectedRevision.entityRevisions, attempt.recordExpectedEntityRevisions)
            let record = try XCTUnwrap(h.context.fetch(FetchDescriptor<WorkflowRecord>()).first {
                $0.id == attempt.recordCommand.recordID
            })
            XCTAssertEqual(record.assetID, h.assetID)
            XCTAssertEqual(record.stage, WorkflowStage.check.rawValue)
            XCTAssertEqual(record.startedAt, attempt.recordCommand.startedAt)
            let saved = try h.snapshot(), idCalls = h.ids.callCount
            let restoredAttempt = try FieldDraftCanonicalCodecV1.decode(CheckRunnerFrozenBeginAttemptV1.self,
                from: FieldDraftCanonicalCodecV1.encode(attempt))
            XCTAssertEqual(try writer.commitFrozenCheckRunnerDraft(restoredAttempt), original)
            XCTAssertEqual(try h.snapshot(), saved)
            XCTAssertEqual(h.ids.callCount, idCalls)
            try assertPhotoReadbackAndLaterProgress(h, attempt: attempt)
        }
    }

    func testFrozenBeginWriterRecoversSavedTimeZoneBeforeRecheckDraft() throws {
        try withFrozenBeginFixture("writer-recheck", entry: .recheck(issueID: beginPreparationUUID(9_510)),
                                   storedTimeZoneID: nil) { h in
            let attempt = try prepareWriterAttempt(h, recordID: 9_511, zoneID: 9_512)
            let writer = h.coordinator.workspaceWriter
            let zone = try XCTUnwrap(attempt.timeZone)
            let zoneOriginal = try writer.commitFrozenCheckRunnerTimeZone(attempt)
            XCTAssertEqual(zoneOriginal.command, .updateSiteTimeZone(zone.command))
            XCTAssertEqual(zoneOriginal.receipt.committedAt, zone.committedAt)
            let savedZone = try h.snapshot()
            XCTAssertEqual(try writer.commitFrozenCheckRunnerTimeZone(attempt), zoneOriginal)
            XCTAssertEqual(try h.snapshot(), savedZone)
            let original = try writer.commitFrozenCheckRunnerDraft(attempt)
            XCTAssertEqual(original.receipt.committedAt, attempt.recordCommittedAt)
            XCTAssertEqual(original.envelope.expectedRevision.entityRevisions, attempt.recordExpectedEntityRevisions)
            XCTAssertEqual(original.envelope.expectedRevision.workspaceRevision, savedZone.revision.revision)
            let record = try XCTUnwrap(h.context.fetch(FetchDescriptor<WorkflowRecord>()).first {
                $0.id == attempt.recordCommand.recordID
            })
            XCTAssertEqual(record.issueID, h.issueID)
            XCTAssertEqual(record.parentRecordID, h.recheckParentID)
            XCTAssertEqual(record.stage, WorkflowStage.recheck.rawValue)
            let savedBoth = try h.snapshot()
            XCTAssertEqual(try writer.commitFrozenCheckRunnerTimeZone(attempt), zoneOriginal)
            XCTAssertEqual(try writer.commitFrozenCheckRunnerDraft(attempt), original)
            XCTAssertEqual(try h.snapshot(), savedBoth)
            let photo = try acceptPhoto(h, attempt: attempt, evidenceID: 9_518)
            XCTAssertEqual(photo.command.draftID, attempt.recordCommand.recordID)
            XCTAssertEqual(photo.envelope.expectedRevision.entityRevisions.count, 2)
            XCTAssertGreaterThan(photo.receipt.committedAt, photo.command.createdAt)
        }
    }

    func testFrozenBeginWriterRejectsReceiptBodyTimeAndRevisionChangesWithoutQuarantine() throws {
        try withFrozenBeginFixture("writer-mismatch", entry: .check,
                                   storedTimeZoneID: "America/New_York") { h in
            let attempt = try prepareWriterAttempt(h, recordID: 9_521)
            let writer = h.coordinator.workspaceWriter
            let original = try writer.commitFrozenCheckRunnerDraft(attempt)
            var body = try frozenBeginJSONObject(FieldDraftCanonicalCodecV1.encode(attempt))
            XCTAssertEqual(try decodeFrozenBeginJSON(CheckRunnerFrozenBeginAttemptV1.self, object: body), attempt)
            var command = try XCTUnwrap(body["recordCommand"] as? [String: Any])
            command["afterDarkAcknowledgementCopy"] = "Different retained acknowledgement"
            body["recordCommand"] = command
            let changedBody = try decodeFrozenBeginJSON(CheckRunnerFrozenBeginAttemptV1.self, object: body)
            XCTAssertNotEqual(changedBody.recordCommand.afterDarkAcknowledgementCopy,
                              attempt.recordCommand.afterDarkAcknowledgementCopy)
            let changedTime = try writerAttempt(attempt,
                committedAt: attempt.recordCommittedAt.addingTimeInterval(1))
            let changedRevisions = attempt.recordExpectedEntityRevisions.map {
                WorkspaceEntityRevisionV1(identity: $0.identity,
                    revision: $0.identity.kind == .asset ? $0.revision + 1 : $0.revision)
            }
            let changedRevision = try writerAttempt(attempt, revisions: changedRevisions)
            for changed in [changedBody, changedTime, changedRevision] {
                let before = try h.snapshot()
                XCTAssertThrowsError(try writer.commitFrozenCheckRunnerDraft(changed))
                XCTAssertEqual(try h.snapshot(), before)
                XCTAssertEqual(try writer.commitFrozenCheckRunnerDraft(attempt), original)
                XCTAssertEqual(try h.snapshot(), before)
            }
            try assertPhotoSemanticRejections(h, attempt: attempt)
        }
    }

    func testFrozenBeginWriterUsesFreshWorkspaceCASButRejectsStaleTarget() throws {
        try withFrozenBeginFixture("writer-global", entry: .check,
                                   storedTimeZoneID: "America/New_York") { h in
            let attempt = try prepareWriterAttempt(h, recordID: 9_531)
            let writer = h.coordinator.workspaceWriter
            let before = try writer.currentRevision()
            _ = try writer.execute(.updateSiteTimeZone(.init(siteID: h.siteID,
                timeZoneID: "America/New_York", confirmedAt: attempt.recordCommand.startedAt)),
                mutationID: .init(rawValue: beginPreparationUUID(9_532)))
            let advanced = try writer.currentRevision()
            XCTAssertGreaterThan(advanced.revision, before.revision)
            let original = try writer.commitFrozenCheckRunnerDraft(attempt)
            XCTAssertEqual(original.envelope.expectedRevision.workspaceRevision, advanced.revision)
            XCTAssertEqual(original.envelope.expectedRevision.entityRevisions, attempt.recordExpectedEntityRevisions)
            let saved = try h.snapshot()
            XCTAssertNil(try writer.checkRunnerPhotoEvidence(workspaceID: h.workspaceID,
                mutationID: .init(rawValue: beginPreparationUUID(9_539))))
            XCTAssertThrowsError(try writer.checkRunnerPhotoEvidence(workspaceID: h.workspaceID,
                mutationID: attempt.recordMutationID)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
            }
            XCTAssertEqual(try h.snapshot(), saved)
        }
        try withFrozenBeginFixture("writer-stale", entry: .check,
                                   storedTimeZoneID: "America/New_York") { h in
            let attempt = try prepareWriterAttempt(h, recordID: 9_533)
            let writer = h.coordinator.workspaceWriter
            _ = try writer.execute(.createCheckDraft(attempt.recordCommand),
                mutationID: .init(rawValue: beginPreparationUUID(9_534)))
            let before = try h.snapshot()
            XCTAssertThrowsError(try writer.commitFrozenCheckRunnerDraft(attempt)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .staleWorkspaceRevision)
            }
            XCTAssertEqual(try h.snapshot(), before)
            XCTAssertNil(try writer.checkRunnerBeginEvidence(workspaceID: h.workspaceID,
                mutationID: attempt.recordMutationID))
        }
    }

    func testFrozenBeginWriterRejectsMissingOrChangedTimeZoneProofBeforeDraft() throws {
        try withFrozenBeginFixture("writer-missing-zone", entry: .check, storedTimeZoneID: nil) { h in
            let attempt = try prepareWriterAttempt(h, recordID: 9_541, zoneID: 9_542)
            let writer = h.coordinator.workspaceWriter
            let zone = try XCTUnwrap(attempt.timeZone)
            let before = try h.snapshot()
            XCTAssertThrowsError(try writer.commitFrozenCheckRunnerDraft(attempt))
            XCTAssertEqual(try h.snapshot(), before)
            _ = try writer.execute(.updateSiteTimeZone(zone.command),
                mutationID: .init(rawValue: beginPreparationUUID(9_543)))
            let equalText = try h.snapshot()
            XCTAssertThrowsError(try writer.commitFrozenCheckRunnerDraft(attempt))
            XCTAssertThrowsError(try writer.commitFrozenCheckRunnerTimeZone(attempt))
            XCTAssertEqual(try h.snapshot(), equalText)
            XCTAssertNil(try writer.checkRunnerBeginEvidence(workspaceID: h.workspaceID,
                mutationID: attempt.recordMutationID))
        }
        try withFrozenBeginFixture("writer-changed-zone", entry: .check, storedTimeZoneID: nil) { h in
            let attempt = try prepareWriterAttempt(h, recordID: 9_544, zoneID: 9_545)
            let writer = h.coordinator.workspaceWriter
            let zone = try XCTUnwrap(attempt.timeZone)
            let original = try writer.commitFrozenCheckRunnerTimeZone(attempt)
            let changedZone = try CheckRunnerBeginTimeZoneAttemptV1(command: zone.command,
                mutationID: zone.mutationID, expectedSiteRevision: zone.expectedSiteRevision + 1,
                committedAt: zone.committedAt)
            let changed = try writerAttempt(attempt, zone: changedZone)
            let before = try h.snapshot()
            XCTAssertThrowsError(try writer.commitFrozenCheckRunnerTimeZone(changed))
            XCTAssertThrowsError(try writer.commitFrozenCheckRunnerDraft(changed))
            XCTAssertEqual(try h.snapshot(), before)
            XCTAssertEqual(try writer.commitFrozenCheckRunnerTimeZone(attempt), original)
            _ = try writer.commitFrozenCheckRunnerDraft(attempt)
            try assertPhotoHistoryAdmission(h, attempt: attempt)
        }
    }

    func testFrozenBeginWriterRejectsDirtyAndRetiredSessionsWithoutEffects() throws {
        try withFrozenBeginFixture("writer-owner", entry: .check, storedTimeZoneID: nil) { h in
            let attempt = try prepareWriterAttempt(h, recordID: 9_551, zoneID: 9_552)
            let writer = h.coordinator.workspaceWriter
            let site = try XCTUnwrap(h.context.fetch(FetchDescriptor<Site>()).first { $0.id == h.siteID })
            site.label = "Unsaved writer precondition"
            let dirty = try h.rowSnapshot()
            XCTAssertThrowsError(try writer.commitFrozenCheckRunnerTimeZone(attempt))
            XCTAssertThrowsError(try writer.commitFrozenCheckRunnerDraft(attempt))
            XCTAssertThrowsError(try writer.checkRunnerPhotoEvidence(workspaceID: h.workspaceID,
                mutationID: attempt.recordMutationID))
            XCTAssertEqual(try h.rowSnapshot(), dirty)
            h.context.rollback()
            let rows = try h.rowSnapshot()
            try h.closeCoordinator()
            XCTAssertThrowsError(try writer.commitFrozenCheckRunnerTimeZone(attempt))
            XCTAssertThrowsError(try writer.commitFrozenCheckRunnerDraft(attempt))
            XCTAssertThrowsError(try writer.checkRunnerPhotoEvidence(workspaceID: h.workspaceID,
                mutationID: attempt.recordMutationID))
            XCTAssertEqual(try h.rowSnapshot(), rows)
        }
    }

    private func acceptPhoto(_ h: FrozenBeginFixture, attempt: CheckRunnerFrozenBeginAttemptV1,
        evidenceID: Int, nextStep: WorkflowDraftStep = .review) throws -> CheckRunnerPhotoCommittedEvidenceV1 {
        let id = beginPreparationUUID(evidenceID)
        let command = CheckEvidenceMutationV1(evidenceID: id, draftID: attempt.recordCommand.recordID,
            purposeKey: "wide", relativePath: "media/\(id.uuidString.lowercased()).jpg",
            mimeType: "image/jpeg", byteCount: 41, sha256: String(repeating: "a", count: 64),
            thumbnailRelativePath: "thumbnails/\(id.uuidString.lowercased()).jpg",
            thumbnailByteCount: 17, thumbnailSHA256: String(repeating: "b", count: 64),
            nextDraftStepKey: nextStep.rawValue, createdAt: attempt.recordCommand.startedAt.addingTimeInterval(-1))
        let writer = h.coordinator.workspaceWriter
        _ = try writer.execute(.acceptCheckEvidence(command), mutationID: .init(rawValue: id))
        let before = try h.snapshot()
        let photo = try XCTUnwrap(writer.checkRunnerPhotoEvidence(workspaceID: h.workspaceID,
            mutationID: .init(rawValue: id)))
        XCTAssertEqual(photo.command, command)
        XCTAssertEqual(try h.snapshot(), before)
        return photo
    }

    private func assertPhotoReadbackAndLaterProgress(_ h: FrozenBeginFixture,
        attempt: CheckRunnerFrozenBeginAttemptV1) throws {
        let photo = try acceptPhoto(h, attempt: attempt, evidenceID: 9_502, nextStep: .close)
        let writer = h.coordinator.workspaceWriter
        let evidenceRow = try XCTUnwrap(h.context.fetch(FetchDescriptor<EvidenceFile>()).first {
            $0.id == photo.command.evidenceID
        })
        let dto = V4BackupEvidenceFileDTO(id: evidenceRow.id, schemaVersion: evidenceRow.schemaVersion,
            recordID: evidenceRow.recordID, purposeKey: evidenceRow.purposeKey,
            relativePath: evidenceRow.relativePath, mimeType: evidenceRow.mimeType,
            byteCount: evidenceRow.byteCount, sha256: evidenceRow.sha256, createdAt: evidenceRow.createdAt,
            thumbnailRelativePath: evidenceRow.thumbnailRelativePath,
            thumbnailByteCount: evidenceRow.thumbnailByteCount, thumbnailSHA256: evidenceRow.thumbnailSHA256)
        let identity = try WorkspaceEntityIdentityV1(kind: .evidenceFile, id: evidenceRow.id)
        let digest = try WorkspaceMutationCanonicalV1.sha256(PhotoDigestBasis(identity: identity,
            revision: 1, value: dto))
        XCTAssertTrue(photo.receipt.postImages.contains(.evidenceFile(id: evidenceRow.id,
            revision: 1, semanticSHA256: digest)))
        XCTAssertEqual(try CheckRunnerPhotoCommittedEvidenceV1(
            envelope: MutationEnvelopeV1.decodeCanonical(from: photo.envelope.canonicalData()),
            receipt: MutationReceiptV1.decodeCanonical(from: photo.receipt.canonicalData())), photo)
        _ = try acceptPhoto(h, attempt: attempt, evidenceID: 9_503)
        let record = try XCTUnwrap(h.context.fetch(FetchDescriptor<WorkflowRecord>()).first {
            $0.id == attempt.recordCommand.recordID
        })
        XCTAssertEqual(record.draftStepKey, WorkflowDraftStep.review.rawValue)
        XCTAssertNotEqual(record.draftStepKey, photo.command.nextDraftStepKey)
        let before = try h.snapshot(), calls = h.ids.callCount
        XCTAssertEqual(try writer.checkRunnerPhotoEvidence(workspaceID: h.workspaceID,
            mutationID: photo.receipt.mutationID), photo)
        XCTAssertNil(try writer.checkRunnerPhotoEvidence(workspaceID: .init(rawValue: beginPreparationUUID(9_509)),
            mutationID: photo.receipt.mutationID))
        XCTAssertEqual(try h.snapshot(), before)
        XCTAssertEqual(h.ids.callCount, calls)
        try h.closeCoordinator()
        let reopenedSession = try h.factory.openOrBootstrapCurrent()
        let reopened = try StoreSessionCoordinator(validatingSession: reopenedSession,
            clock: h.clock, idSource: h.ids)
        defer { try? reopened.invalidateAndReleaseWriter() }
        XCTAssertEqual(try reopened.workspaceWriter.checkRunnerPhotoEvidence(workspaceID: h.workspaceID,
            mutationID: photo.receipt.mutationID), photo)
        XCTAssertEqual(try reopened.workspaceWriter.currentRevision().revision, before.revision.revision)
    }

    private func assertPhotoSemanticRejections(_ h: FrozenBeginFixture,
        attempt: CheckRunnerFrozenBeginAttemptV1) throws {
        let photo = try acceptPhoto(h, attempt: attempt, evidenceID: 9_522)
        let before = try h.snapshot()
        let originalBody = try frozenBeginJSONObject(WorkspaceMutationCanonicalV1.data(photo.command))
        let substitutions: [(String, Any)] = [
            ("evidenceID", beginPreparationUUID(9_523).uuidString),
            ("draftID", beginPreparationUUID(9_524).uuidString), ("purposeKey", "closeup"),
            ("relativePath", "media/other.jpg"), ("mimeType", "image/png"), ("byteCount", 42),
            ("sha256", String(repeating: "c", count: 64)),
            ("thumbnailRelativePath", "thumbnails/other.jpg"), ("thumbnailByteCount", 18),
            ("thumbnailSHA256", String(repeating: "d", count: 64)),
            ("createdAt", photo.command.createdAt.timeIntervalSince1970 * 1_000 + 1_000),
            ("nextDraftStepKey", WorkflowDraftStep.wide.rawValue)
        ]
        for (key, value) in substitutions {
            var body = originalBody; body[key] = value
            let command = try decodeFrozenBeginJSON(CheckEvidenceMutationV1.self, object: body)
            XCTAssertNotEqual(command, photo.command)
            var envelopeObject = try frozenBeginJSONObject(photo.envelope.canonicalData())
            envelopeObject["command"] = try frozenBeginJSONObject(
                WorkspaceMutationCanonicalV1.data(WorkspaceCommandV1.acceptCheckEvidence(command)))
            envelopeObject["commandBodySHA256"] = try WorkspaceMutationCanonicalV1.sha256(
                WorkspaceCommandV1.acceptCheckEvidence(command))
            let envelope = try decodeFrozenBeginJSON(MutationEnvelopeV1.self, object: envelopeObject)
            XCTAssertThrowsError(try CheckRunnerPhotoCommittedEvidenceV1(envelope: envelope,
                receipt: photo.receipt), key)
            // Rebinding a fabricated receipt must still fail immutable content
            // correspondence. The mutable workflow step needs its history join.
            if key != "nextDraftStepKey" {
                let rebound = try photoReceipt(photo, envelope: envelope)
                XCTAssertThrowsError(try CheckRunnerPhotoCommittedEvidenceV1(envelope: envelope,
                    receipt: rebound), key)
            }
        }
        let altered = photo.receipt.postImages.map { image -> MutationPostImageV1 in
            if case let .evidenceFile(id, revision, _) = image {
                return .evidenceFile(id: id, revision: revision, semanticSHA256: String(repeating: "e", count: 64))
            }
            return image
        }
        let wrongDigest = try photoReceipt(photo, images: altered)
        XCTAssertThrowsError(try CheckRunnerPhotoCommittedEvidenceV1(envelope: photo.envelope,
            receipt: wrongDigest))
        let missing = try photoReceipt(photo, images: photo.receipt.postImages.filter {
            if case .workflowRecord = $0 { return true }; return false
        })
        XCTAssertThrowsError(try CheckRunnerPhotoCommittedEvidenceV1(envelope: photo.envelope, receipt: missing))
        let reversal = try photoReceipt(photo, reverses: .init(rawValue: beginPreparationUUID(9_525)))
        XCTAssertThrowsError(try CheckRunnerPhotoCommittedEvidenceV1(envelope: photo.envelope, receipt: reversal))
        let site = try WorkspaceEntityIdentityV1(kind: .site, id: h.siteID)
        let extra = try XCTUnwrap(before.revision.entityRevisions.first { $0.identity == site })
        let extraExpected = try photoEnvelope(photo, writerInstanceID: before.revision.writerInstanceID,
            expected: photo.envelope.expectedRevision.entityRevisions + [extra])
        let extraReceipt = try photoReceipt(photo, envelope: extraExpected)
        XCTAssertThrowsError(try CheckRunnerPhotoCommittedEvidenceV1(envelope: extraExpected, receipt: extraReceipt))
        let evidenceIdentity = try WorkspaceEntityIdentityV1(kind: .evidenceFile, id: photo.command.evidenceID)
        let beforeOne = photo.envelope.expectedRevision.entityRevisions.map {
            WorkspaceEntityRevisionV1(identity: $0.identity, revision: $0.identity == evidenceIdentity ? 1 : $0.revision)
        }
        let afterTwo = photo.receipt.resultingRevision.entityRevisions.map {
            WorkspaceEntityRevisionV1(identity: $0.identity, revision: $0.identity == evidenceIdentity ? 2 : $0.revision)
        }
        let existingEvidence = try photoEnvelope(photo, writerInstanceID: before.revision.writerInstanceID,
            expected: beforeOne)
        let resulting = try MutationPortableExpectedRevisionV1(WorkspaceExpectedRevisionV1(
            workspaceID: h.workspaceID, generationID: photo.receipt.resultingRevision.generationID,
            writerInstanceID: before.revision.writerInstanceID,
            workspaceRevision: photo.receipt.resultingRevision.workspaceRevision, entityRevisions: afterTwo))
        let secondImages = photo.receipt.postImages.map { image -> MutationPostImageV1 in
            if case let .evidenceFile(id, _, digest) = image {
                return .evidenceFile(id: id, revision: 2, semanticSHA256: digest)
            }; return image
        }
        let secondReceipt = try photoReceipt(photo, envelope: existingEvidence,
            images: secondImages, resulting: resulting)
        XCTAssertThrowsError(try CheckRunnerPhotoCommittedEvidenceV1(envelope: existingEvidence,
            receipt: secondReceipt))
        // Generic receipt validation permits these metadata values, so the
        // typed pair must reject their mismatch against the original envelope.
        for (key, value) in [("contentDependencyIDs", ["other-dependency"] as Any),
                             ("sourceKind", MutationSourceKindV1.localRecovery.rawValue as Any),
                             ("correlationID", beginPreparationUUID(9_526).uuidString as Any),
                             ("commandBodySHA256", String(repeating: "f", count: 64) as Any),
                             ("envelopeSHA256", String(repeating: "f", count: 64) as Any)] {
            var object = try frozenBeginJSONObject(photo.receipt.canonicalData()); object[key] = value
            let changed = try decodeFrozenBeginJSON(MutationReceiptV1.self, object: object)
            try changed.validate()
            XCTAssertThrowsError(try CheckRunnerPhotoCommittedEvidenceV1(envelope: photo.envelope, receipt: changed), key)
        }
        let reversalEnvelope = try photoEnvelope(photo, writerInstanceID: before.revision.writerInstanceID,
            reversalPlanDigest: String(repeating: "f", count: 64))
        XCTAssertThrowsError(try CheckRunnerPhotoCommittedEvidenceV1(envelope: reversalEnvelope,
            receipt: photoReceipt(photo, envelope: reversalEnvelope)))
        XCTAssertEqual(try h.snapshot(), before)
    }

    private func assertPhotoHistoryAdmission(_ h: FrozenBeginFixture,
        attempt: CheckRunnerFrozenBeginAttemptV1) throws {
        let photo = try acceptPhoto(h, attempt: attempt, evidenceID: 9_546)
        let quarantine = MutationQuarantineRow(workspaceID: h.workspaceID,
            mutationID: photo.receipt.mutationID, identityDomain: .mutationEnvelope,
            acceptedIdentitySHA256: photo.envelopeSHA256,
            conflictingIdentitySHA256: String(repeating: "f", count: 64), detectedAt: h.clock.value)
        h.context.insert(quarantine); try h.context.save()
        let before = try h.snapshot()
        XCTAssertThrowsError(try h.coordinator.workspaceWriter.checkRunnerPhotoEvidence(
            workspaceID: h.workspaceID, mutationID: photo.receipt.mutationID)) {
            XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .mutationIDQuarantined)
        }
        XCTAssertEqual(try h.snapshot(), before)
        h.context.delete(quarantine); try h.context.save()
        let row = try XCTUnwrap(h.context.fetch(FetchDescriptor<MutationReceiptRow>()).first {
            $0.mutationID == attempt.recordMutationID.rawValue
        })
        let bytes = row.receiptData
        row.receiptData = Data("{}".utf8); try h.context.save()
        let count = try h.context.fetchCount(FetchDescriptor<MutationReceiptRow>())
        for id in [photo.receipt.mutationID, try MutationIDV1(rawValue: beginPreparationUUID(9_547))] {
            XCTAssertThrowsError(try h.coordinator.workspaceWriter.checkRunnerPhotoEvidence(
                workspaceID: h.workspaceID, mutationID: id)) {
                XCTAssertEqual($0 as? WorkspaceMutationFailureV1, .receiptHistoryCorrupt)
            }
        }
        XCTAssertEqual(row.receiptData, Data("{}".utf8))
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<MutationReceiptRow>()), count)
        XCTAssertEqual(try h.context.fetchCount(FetchDescriptor<MutationQuarantineRow>()), 0)
        row.receiptData = bytes; try h.context.save()
        XCTAssertEqual(try h.coordinator.workspaceWriter.checkRunnerPhotoEvidence(
            workspaceID: h.workspaceID, mutationID: photo.receipt.mutationID), photo)
    }

    private func photoReceipt(_ photo: CheckRunnerPhotoCommittedEvidenceV1,
        envelope: MutationEnvelopeV1? = nil, images: [MutationPostImageV1]? = nil,
        reverses: MutationIDV1? = nil,
        resulting: MutationPortableExpectedRevisionV1? = nil) throws -> MutationReceiptV1 {
        try MutationReceiptV1(identity: photo.receipt.identity, envelope: envelope ?? photo.envelope,
            resultingRevision: resulting ?? photo.receipt.resultingRevision, postImages: images ?? photo.receipt.postImages,
            reversesMutationID: reverses, committedAt: photo.receipt.committedAt)
    }

    private func photoEnvelope(_ photo: CheckRunnerPhotoCommittedEvidenceV1,
        writerInstanceID: UUID, expected: [WorkspaceEntityRevisionV1]? = nil,
        reversalPlanDigest: String? = nil) throws -> MutationEnvelopeV1 {
        let original = photo.envelope
        let revision = try WorkspaceExpectedRevisionV1(workspaceID: original.workspaceID,
            generationID: original.generationID, writerInstanceID: writerInstanceID,
            workspaceRevision: original.expectedRevision.workspaceRevision,
            entityRevisions: expected ?? original.expectedRevision.entityRevisions)
        return try MutationEnvelopeV1(request: .init(mutationID: original.mutationID,
            expectedRevision: revision, command: original.command),
            identity: .init(workspaceID: original.workspaceID, replicaID: original.replicaID),
            sourceKind: original.sourceKind, contentDependencyIDs: original.contentDependencyIDs,
            causationMutationID: original.causationMutationID, correlationID: original.correlationID,
            reversalPlanDigest: reversalPlanDigest)
    }

    private struct PhotoDigestBasis: Codable {
        let identity: WorkspaceEntityIdentityV1
        let revision: UInt64
        let value: V4BackupEvidenceFileDTO
    }

    private func prepareWriterAttempt(_ h: FrozenBeginFixture, recordID: Int, zoneID: Int? = nil) throws
        -> CheckRunnerFrozenBeginAttemptV1 {
        h.ids.enqueue([beginPreparationUUID(recordID)] + (zoneID.map { [beginPreparationUUID($0)] } ?? []))
        return try h.runner.prepareFrozenBegin(source: h.captureSource(), progress: h.progress,
            publishedRelease: h.publishedRelease, submission: h.validSubmission())
    }

    private func writerAttempt(_ original: CheckRunnerFrozenBeginAttemptV1,
        committedAt: Date? = nil, revisions: [WorkspaceEntityRevisionV1]? = nil,
        zone: CheckRunnerBeginTimeZoneAttemptV1? = nil) throws -> CheckRunnerFrozenBeginAttemptV1 {
        try .init(source: original.source, sourceWorkspaceID: original.sourceWorkspaceID,
            recordCommand: original.recordCommand, recordMutationID: original.recordMutationID,
            recordExpectedEntityRevisions: revisions ?? original.recordExpectedEntityRevisions,
            recordCommittedAt: committedAt ?? original.recordCommittedAt,
            timeZone: zone ?? original.timeZone, siteID: original.siteID,
            resolvedSiteTimeZoneID: original.resolvedSiteTimeZoneID)
    }

}

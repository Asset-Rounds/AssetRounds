import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

final class V23RepetitiveCaptureDestinationReviewTests: XCTestCase {
    func testIterativeLineageComposesFortyHopsAcrossRepeatedWorkspacesWithoutPayloadGrowth() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { fixture.removePackages() }
        var imported = try destinationReviewStart(fixture)
        var lineage = try RepetitiveCaptureReviewLineageReaderV1.read(workspaceID: imported.checkpoint.workspaceID,
            mutationID: imported.checkpoint.mutationID, in: imported.snapshot)
        let ultimate = lineage.retainedSource.reference
        let sourceBytes = try FieldDraftCanonicalCodecV1.encode(fixture.history)
        var firstInheritedSize: Int?
        for hop in 1...40 {
            let previous = lineage.selectedReview
            let mode: BackupRestoreMode = hop.isMultiple(of: 4) ? .replaceExisting : .fork
            let identity = try destinationReviewIdentity(mode: mode, source: previous.checkpoint.workspaceID.rawValue,
                destination: destinationReviewID(81_000 + hop % 3), generation: 82_000 + hop)
            let prepared = try RepetitiveCaptureDestinationReviewV1.prepareInherited(from: lineage,
                identity: identity, reviewedAt: RepetitiveCaptureSourcePackageFixture.date)
            XCTAssertEqual(prepared.sourceReviewDraftID, previous.checkpoint.draftID)
            XCTAssertNotEqual(prepared.checkpoint.draftID, previous.checkpoint.draftID)
            XCTAssertEqual(prepared.checkpoint.state, .recoveryRequired)
            XCTAssertEqual(prepared.checkpoint.draftRevision, 1)
            XCTAssertNil(prepared.checkpoint.lastDurableMutationID)
            XCTAssertEqual(prepared.payload.source, ultimate)
            let predecessor = try XCTUnwrap(prepared.payload.provenance.immediatePredecessor)
            XCTAssertEqual(predecessor.reviewMutationID, previous.anchor.envelope.mutationID)
            XCTAssertEqual(predecessor.reviewCheckpointSHA256, previous.checkpoint.checkpointSHA256)
            for pair in prepared.payload.provenance.ultimateToDestinationPairs {
                let prior = try XCTUnwrap(previous.payload.provenance.ultimateToDestinationPairs.first {
                    $0.kind == pair.kind && $0.sourceID == pair.sourceID
                })
                let expected = pair.kind == .checkpoint
                    ? RestoreIdentityV1.destinationFieldDraftID(for: prior.destinationID, namespace: "draft",
                        mode: mode, destinationWorkspaceID: identity.targetPointer.workspaceID)
                    : RestoreIdentityV1.destinationRecordID(for: prior.destinationID)
                XCTAssertEqual(pair.destinationID, expected)
                XCTAssertTrue(predecessor.predecessorToDestinationPairs.contains {
                    $0.kind == pair.kind && $0.sourceID == prior.destinationID && $0.destinationID == pair.destinationID
                })
                if hop == 1, pair.kind == .checkpoint {
                    XCTAssertNotEqual(pair.destinationID, RestoreIdentityV1.destinationFieldDraftID(
                        for: pair.sourceID, namespace: "draft", mode: .fork,
                        destinationWorkspaceID: identity.targetPointer.workspaceID))
                }
                if pair.kind != .checkpoint { XCTAssertEqual(pair.sourceID, pair.destinationID) }
            }
            firstInheritedSize = firstInheritedSize ?? prepared.checkpoint.payloadData.count
            XCTAssertLessThanOrEqual(prepared.checkpoint.payloadData.count, try XCTUnwrap(firstInheritedSize) + 64)
            let text = try XCTUnwrap(String(data: prepared.checkpoint.payloadData, encoding: .utf8))
            XCTAssertEqual(text.components(separatedBy: "\"immediatePredecessor\"").count - 1, 1)
            imported = try destinationReviewImportedHistory(source: imported.snapshot, payload: prepared.payload,
                generationID: identity.targetPointer.generationID)
            XCTAssertEqual(imported.checkpoint, prepared.checkpoint)
            lineage = try RepetitiveCaptureReviewLineageReaderV1.read(workspaceID: imported.checkpoint.workspaceID,
                mutationID: imported.checkpoint.mutationID, in: imported.snapshot)
            XCTAssertEqual(lineage.reviews.count, hop + 1)
            XCTAssertEqual(lineage.retainedSource.reference, ultimate)
            XCTAssertEqual(try destinationReviewOriginalMap(lineage.requiredHistory.map(\.original)),
                           try destinationReviewOriginalMap(imported.snapshot.receipts))
        }
        XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(fixture.history), sourceBytes)
        XCTAssertEqual(lineage.reviews.count, 41)
        for mode in [BackupRestoreMode.clone, .emptyInstall] {
            XCTAssertThrowsError(try RepetitiveCaptureDestinationReviewV1.prepareInherited(from: lineage,
                identity: destinationReviewIdentity(mode: mode, source: imported.checkpoint.workspaceID.rawValue),
                reviewedAt: RepetitiveCaptureSourcePackageFixture.date))
        }
        XCTAssertThrowsError(try RepetitiveCaptureDestinationReviewV1.prepareInherited(from: lineage,
            identity: destinationReviewIdentity(mode: .replaceExisting, source: imported.checkpoint.workspaceID.rawValue,
                destination: imported.checkpoint.workspaceID.rawValue), reviewedAt: RepetitiveCaptureSourcePackageFixture.date))
        XCTAssertThrowsError(try RepetitiveCaptureDestinationReviewV1.prepareInherited(from: lineage,
            identity: destinationReviewIdentity(mode: .fork, source: fixture.workspaceID.rawValue),
            reviewedAt: RepetitiveCaptureSourcePackageFixture.date))
    }

    func testLineageBindsLaterCheckpointPrefixAndRejectsBranchPayloadDriftAndUnreviewedActivation() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { fixture.removePackages() }
        let initial = try destinationReviewStart(fixture)
        let next = try destinationReviewRevision(initial.checkpoint, mutationSeed: 83_001)
        let revised = try destinationReviewAppendRevision(next, predecessor: initial.checkpoint,
            to: initial.snapshot, generationID: destinationReviewID(80_005))
        let lineage = try RepetitiveCaptureReviewLineageReaderV1.read(workspaceID: next.workspaceID,
            mutationID: next.mutationID, in: revised.snapshot)
        XCTAssertEqual(lineage.selectedReview.initialCheckpoint, initial.checkpoint)
        XCTAssertEqual(lineage.selectedReview.checkpoint, next)
        XCTAssertEqual(lineage.selectedReview.prefix.map(\.original), [initial.original, revised.original])
        let oldTip = try RepetitiveCaptureReviewLineageReaderV1.read(workspaceID: initial.checkpoint.workspaceID,
            mutationID: initial.checkpoint.mutationID, in: revised.snapshot)
        XCTAssertEqual(oldTip.selectedReview.checkpoint, initial.checkpoint)
        XCTAssertEqual(oldTip.selectedReview.prefix.map(\.original), [initial.original])
        let identity = try destinationReviewIdentity(mode: .fork, source: next.workspaceID.rawValue,
            destination: destinationReviewID(83_002), generation: 83_003)
        let proposal = try RepetitiveCaptureDestinationReviewV1.prepareInherited(from: lineage, identity: identity,
            reviewedAt: RepetitiveCaptureSourcePackageFixture.date)
        XCTAssertEqual(proposal.payload.provenance.immediatePredecessor?.reviewMutationID, next.mutationID)
        XCTAssertEqual(proposal.checkpoint.state, .recoveryRequired)
        let inherited = try destinationReviewImportedHistory(source: revised.snapshot, payload: proposal.payload,
            generationID: identity.targetPointer.generationID)
        let inheritedLineage = try RepetitiveCaptureReviewLineageReaderV1.read(workspaceID: inherited.checkpoint.workspaceID,
            mutationID: inherited.checkpoint.mutationID, in: inherited.snapshot)
        XCTAssertEqual(inheritedLineage.reviews.first?.checkpoint, next)
        XCTAssertEqual(inheritedLineage.reviews.first?.prefix.count, 2)
        let branch = try destinationReviewRevision(initial.checkpoint, mutationSeed: 83_004)
        let branched = try destinationReviewAppendRevision(branch, predecessor: initial.checkpoint,
            to: revised.snapshot, generationID: destinationReviewID(80_005))
        XCTAssertThrowsError(try RepetitiveCaptureReviewLineageReaderV1.read(workspaceID: next.workspaceID,
            mutationID: next.mutationID, in: branched.snapshot))
        let payload = try RepetitiveCaptureDestinationReviewCodecV1.decode(initial.checkpoint.payloadData)
        var pairs = payload.provenance.ultimateToDestinationPairs
        let asset = try XCTUnwrap(pairs.firstIndex { $0.kind == .asset })
        pairs[asset] = try .init(kind: .asset, sourceID: destinationReviewID(83_005), destinationID: destinationReviewID(83_005))
        let drift = try destinationReviewPayload(payload, pairs: pairs.sorted(by: destinationReviewPairLess))
        let changed = try destinationReviewRevision(initial.checkpoint, mutationSeed: 83_006,
            payloadData: RepetitiveCaptureDestinationReviewCodecV1.encode(drift))
        let active = try destinationReviewRevision(initial.checkpoint, state: .active, mutationSeed: 83_007)
        for checkpoint in [changed, active] {
            let candidate = try destinationReviewAppendRevision(checkpoint, predecessor: initial.checkpoint,
                to: initial.snapshot, generationID: destinationReviewID(80_005))
            XCTAssertThrowsError(try RepetitiveCaptureReviewLineageReaderV1.read(workspaceID: checkpoint.workspaceID,
                mutationID: checkpoint.mutationID, in: candidate.snapshot))
        }
        let noCreate = destinationReviewSnapshot(revised.snapshot,
            receipts: revised.snapshot.receipts.filter { $0 != initial.original })
        XCTAssertThrowsError(try RepetitiveCaptureReviewLineageReaderV1.read(workspaceID: next.workspaceID,
            mutationID: next.mutationID, in: noCreate))
    }

    func testLineageRejectsRehashedPredecessorClaimsAndCannotReuseValidationForDifferentHistory() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { fixture.removePackages() }
        let initial = try destinationReviewStart(fixture)
        let lineage = try RepetitiveCaptureReviewLineageReaderV1.read(workspaceID: initial.checkpoint.workspaceID,
            mutationID: initial.checkpoint.mutationID, in: initial.snapshot)
        let identity = try destinationReviewIdentity(mode: .fork, source: initial.checkpoint.workspaceID.rawValue,
            destination: destinationReviewID(84_001), generation: 84_002)
        let prepared = try RepetitiveCaptureDestinationReviewV1.prepareInherited(from: lineage,
            identity: identity, reviewedAt: RepetitiveCaptureSourcePackageFixture.date)
        let originalLink = try XCTUnwrap(prepared.payload.provenance.immediatePredecessor)
        for field in ["reviewCheckpointSHA256", "reviewEnvelopeSHA256", "reviewReceiptSHA256", "predecessorProvenanceSHA256",
                      "reviewDraftID", "reviewMutationID", "reviewReceiptIdentity", "predecessorToDestinationPairs"] {
            let link = try destinationReviewAlteredLink(originalLink, field: field)
            let payload = try RepetitiveCaptureDestinationReviewPayloadV1(source: prepared.payload.source,
                provenance: .init(mode: prepared.payload.provenance.mode,
                    destinationWorkspaceID: prepared.checkpoint.workspaceID,
                    ultimateSourceReferenceSHA256: prepared.payload.source.referenceSHA256,
                    ultimateToDestinationPairs: prepared.payload.provenance.ultimateToDestinationPairs,
                    immediatePredecessor: link))
            let candidate = try destinationReviewImportedHistory(source: initial.snapshot, payload: payload,
                generationID: identity.targetPointer.generationID)
            XCTAssertThrowsError(try RepetitiveCaptureReviewLineageReaderV1.read(workspaceID: candidate.checkpoint.workspaceID,
                mutationID: candidate.checkpoint.mutationID, in: candidate.snapshot), field)
        }
        let valid = try destinationReviewImportedHistory(source: initial.snapshot, payload: prepared.payload,
            generationID: identity.targetPointer.generationID)
        let facts = try MutationJournalStoreV1.validatedImportedSnapshotFacts(valid.snapshot)
        XCTAssertEqual(try RepetitiveCaptureReviewLineageReaderV1.read(workspaceID: valid.checkpoint.workspaceID,
            mutationID: valid.checkpoint.mutationID, in: valid.snapshot, validatedBy: facts).reviews.count, 2)
        let changed = destinationReviewSnapshot(valid.snapshot, receipts: valid.snapshot.receipts.filter { $0 != initial.original })
        XCTAssertThrowsError(try RepetitiveCaptureReviewLineageReaderV1.read(workspaceID: valid.checkpoint.workspaceID,
            mutationID: valid.checkpoint.mutationID, in: changed, validatedBy: facts))
        XCTAssertThrowsError(try RepetitiveCaptureDestinationReviewHistoryV1.firstReview(workspaceID: initial.checkpoint.workspaceID,
            mutationID: initial.checkpoint.mutationID, in: changed, validatedBy: facts))
        XCTAssertThrowsError(try RepetitiveCaptureSourceGraphReviewV2.retainedOriginals(for: prepared.payload.source,
            in: changed, validatedBy: facts))
        XCTAssertThrowsError(try RepetitiveCaptureReviewLineageReaderV1.read(workspaceID: valid.checkpoint.workspaceID,
            mutationID: valid.checkpoint.mutationID, in: changed))
    }

    @MainActor
    func testForeignLiveLineageReadPreservesAllOriginalsAndDeniesDirtyAncestorQuarantineAndRetirement() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { fixture.removePackages() }
        let initial = try destinationReviewStart(fixture)
        let ancestor = try RepetitiveCaptureReviewLineageReaderV1.read(workspaceID: initial.checkpoint.workspaceID,
            mutationID: initial.checkpoint.mutationID, in: initial.snapshot)
        let identity = try destinationReviewIdentity(mode: .fork, source: initial.checkpoint.workspaceID.rawValue,
            destination: destinationReviewID(85_001), generation: 85_002)
        let prepared = try RepetitiveCaptureDestinationReviewV1.prepareInherited(from: ancestor,
            identity: identity, reviewedAt: RepetitiveCaptureSourcePackageFixture.date)
        let imported = try destinationReviewImportedHistory(source: initial.snapshot, payload: prepared.payload,
            generationID: identity.targetPointer.generationID)
        let expected = try RepetitiveCaptureReviewLineageReaderV1.read(workspaceID: imported.checkpoint.workspaceID,
            mutationID: imported.checkpoint.mutationID, in: imported.snapshot)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("c36-lineage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try RetainedSourceHistoryTargetV2(root: root, records: imported.snapshot.receipts)
        defer { try? target.close() }
        @MainActor func read() throws -> RepetitiveCaptureReviewLineageV1 {
            try target.writer.repetitiveCaptureDestinationReviewLineage(
                workspaceID: imported.checkpoint.workspaceID, mutationID: imported.checkpoint.mutationID)
        }
        @MainActor func journalRead() throws -> RepetitiveCaptureReviewLineageV1 {
            try target.journal.repetitiveCaptureDestinationReviewLineage(
                workspaceID: imported.checkpoint.workspaceID, mutationID: imported.checkpoint.mutationID)
        }
        let before = try target.rawState()
        XCTAssertEqual(try read(), expected)
        XCTAssertEqual(try journalRead(), expected)
        XCTAssertEqual(try target.rawState(), before)
        XCTAssertEqual(before.canonicalCounts, [0, 0, 0, 0, 0])
        let key = MutationWorkspaceKeyV1.value(workspaceID: initial.checkpoint.workspaceID,
                                               mutationID: initial.checkpoint.mutationID)
        let row = try XCTUnwrap(target.context.fetch(FetchDescriptor<MutationReceiptRow>()).first {
            $0.workspaceMutationKey == key
        })
        let digest = row.receiptSHA256
        row.receiptSHA256 = String(repeating: "f", count: 64)
        let dirty = try target.rawState()
        XCTAssertThrowsError(try read())
        XCTAssertThrowsError(try journalRead())
        XCTAssertEqual(try target.rawState(), dirty)
        target.context.rollback()
        row.receiptSHA256 = String(repeating: "f", count: 64)
        try target.context.save()
        let corrupt = try target.rawState()
        XCTAssertThrowsError(try read())
        XCTAssertThrowsError(try journalRead())
        XCTAssertEqual(try target.rawState(), corrupt)
        row.receiptSHA256 = digest
        try target.context.save()
        let quarantine = MutationQuarantineRow(workspaceID: initial.checkpoint.workspaceID,
            mutationID: initial.checkpoint.mutationID, identityDomain: .mutationEnvelope,
            acceptedIdentitySHA256: FieldDraftCanonicalCodecV1.sha256(initial.original.envelopeData),
            conflictingIdentitySHA256: String(repeating: "b", count: 64),
            detectedAt: RepetitiveCaptureSourcePackageFixture.date.addingTimeInterval(1_000))
        target.context.insert(quarantine)
        try target.context.save()
        let quarantined = try target.rawState()
        XCTAssertThrowsError(try read())
        XCTAssertThrowsError(try journalRead())
        XCTAssertEqual(try target.rawState(), quarantined)
        target.context.delete(quarantine)
        try target.context.save()
        target.context.delete(row)
        try target.context.save()
        let missing = try target.rawState()
        XCTAssertThrowsError(try read())
        XCTAssertThrowsError(try journalRead())
        XCTAssertEqual(try target.rawState(), missing)
        try target.insert(initial.original)
        try target.context.save()
        XCTAssertEqual(try read(), expected)
        XCTAssertEqual(try target.rawState(), before)
        try target.closeJournalLease()
        XCTAssertThrowsError(try journalRead())
        XCTAssertEqual(try read(), expected)
        target.writer.invalidate()
        XCTAssertThrowsError(try read())
        XCTAssertEqual(try target.rawState(), before)
    }

    func testFirstCreateReceiptAuthenticatesRetainedSourceAndPreservesOriginalBytes() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture()
        defer { fixture.removePackages() }
        let reviewed = try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: fixture.validatedPackage())
        let sourceID = try XCTUnwrap(reviewed.graphs.first).chain.sourceCheckpoint.draftID
        let before = try FieldDraftCanonicalCodecV1.encode(fixture.history)
        for mode in [BackupRestoreMode.replaceExisting, .fork] {
            let identity = try destinationReviewIdentity(mode: mode, source: fixture.workspaceID.rawValue)
            let prepared = try RepetitiveCaptureDestinationReviewV1.prepareFirst(from: reviewed,
                sourceDraftID: sourceID, identity: identity, reviewedAt: RepetitiveCaptureSourcePackageFixture.date)
            let imported = try destinationReviewImportedHistory(source: fixture.history,
                payload: prepared.payload, generationID: identity.targetPointer.generationID,
                includeReversalBasis: mode == .fork)
            XCTAssertEqual(imported.original.reversalBasisData != nil, mode == .fork)
            XCTAssertEqual(imported.checkpoint, prepared.checkpoint)
            let evidence = try RepetitiveCaptureDestinationReviewHistoryV1.firstReview(
                workspaceID: imported.checkpoint.workspaceID, mutationID: imported.checkpoint.mutationID,
                in: imported.snapshot)
            XCTAssertEqual(evidence.checkpoint, prepared.checkpoint)
            XCTAssertEqual(evidence.payload, prepared.payload)
            XCTAssertEqual(evidence.original.original, imported.original)
            XCTAssertEqual(evidence.retainedSource.requiredHistory, reviewed.requiredHistory)
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(fixture.history), before)
            XCTAssertThrowsError(try RepetitiveCaptureDestinationReviewHistoryV1.firstReview(
                workspaceID: fixture.workspaceID, mutationID: imported.checkpoint.mutationID, in: imported.snapshot))
            let sourceMutation = try XCTUnwrap(reviewed.requiredHistory.first).envelope.mutationID
            XCTAssertThrowsError(try RepetitiveCaptureDestinationReviewHistoryV1.firstReview(
                workspaceID: fixture.workspaceID, mutationID: sourceMutation, in: imported.snapshot))
            XCTAssertThrowsError(try RepetitiveCaptureDestinationReviewHistoryV1.firstReview(
                workspaceID: imported.checkpoint.workspaceID, mutationID: imported.checkpoint.mutationID,
                in: fixture.history))
        }
    }

    func testSelfConsistentCreateReceiptCannotAuthenticateChangedMappingOrGeneration() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture()
        defer { fixture.removePackages() }
        let reviewed = try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: fixture.validatedPackage())
        let identity = try destinationReviewIdentity(mode: .fork, source: fixture.workspaceID.rawValue)
        let prepared = try RepetitiveCaptureDestinationReviewV1.prepareFirst(from: reviewed,
            sourceDraftID: XCTUnwrap(reviewed.graphs.first).chain.sourceCheckpoint.draftID,
            identity: identity, reviewedAt: RepetitiveCaptureSourcePackageFixture.date)
        var pairs = prepared.payload.provenance.ultimateToDestinationPairs
        let index = try XCTUnwrap(pairs.firstIndex { $0.kind == .asset })
        pairs[index] = try .init(kind: .asset, sourceID: destinationReviewID(90_100),
                                destinationID: destinationReviewID(90_100))
        pairs.sort(by: destinationReviewPairLess)
        let wrongMapping = try RepetitiveCaptureDestinationReviewPayloadV1(source: prepared.payload.source,
            provenance: .init(mode: .fork, destinationWorkspaceID: prepared.checkpoint.workspaceID,
                ultimateSourceReferenceSHA256: prepared.payload.source.referenceSHA256,
                ultimateToDestinationPairs: pairs))
        // Both the changed payload and its actual envelope/receipt hashes are
        // consistent. Only reconstruction from retained source detects this.
        let wrong = try destinationReviewImportedHistory(source: fixture.history, payload: wrongMapping,
            generationID: identity.targetPointer.generationID)
        let changedGeneration = try destinationReviewImportedHistory(source: fixture.history,
            payload: prepared.payload, generationID: identity.targetPointer.generationID,
            envelopeGenerationID: destinationReviewID(90_101))
        let changedBase = try destinationReviewImportedHistory(source: fixture.history,
            payload: prepared.payload, generationID: identity.targetPointer.generationID,
            expectedBaseCanonicalRevision: prepared.checkpoint.baseCanonicalRevision + 1)
        for imported in [wrong, changedGeneration, changedBase] {
            try MutationJournalStoreV1.validateImportedSnapshot(imported.snapshot)
            XCTAssertThrowsError(try RepetitiveCaptureDestinationReviewHistoryV1.firstReview(
                workspaceID: imported.checkpoint.workspaceID, mutationID: imported.checkpoint.mutationID,
                in: imported.snapshot))
        }
        let valid = try destinationReviewImportedHistory(source: fixture.history, payload: prepared.payload,
            generationID: identity.targetPointer.generationID)
        let missingSource = MutationHistorySnapshotV1(workspaceRevision: valid.snapshot.workspaceRevision,
            lastLocalSequence: valid.snapshot.lastLocalSequence, receipts: [valid.original],
            quarantines: [], entityRevisions: valid.snapshot.entityRevisions)
        XCTAssertThrowsError(try RepetitiveCaptureDestinationReviewHistoryV1.firstReview(
            workspaceID: valid.checkpoint.workspaceID, mutationID: valid.checkpoint.mutationID, in: missingSource))
        let duplicate = MutationHistorySnapshotV1(workspaceRevision: valid.snapshot.workspaceRevision,
            lastLocalSequence: valid.snapshot.lastLocalSequence, receipts: valid.snapshot.receipts + [valid.original],
            quarantines: [], entityRevisions: valid.snapshot.entityRevisions)
        XCTAssertThrowsError(try RepetitiveCaptureDestinationReviewHistoryV1.firstReview(
            workspaceID: valid.checkpoint.workspaceID, mutationID: valid.checkpoint.mutationID, in: duplicate))
    }

    @MainActor
    func testForeignLiveReviewReadDeniesTamperQuarantineDirtyAndRetiredReadersWithoutEffects() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { fixture.removePackages() }
        let reviewed = try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: fixture.validatedPackage())
        let identity = try destinationReviewIdentity(mode: .fork, source: fixture.workspaceID.rawValue)
        let prepared = try RepetitiveCaptureDestinationReviewV1.prepareFirst(from: reviewed,
            sourceDraftID: XCTUnwrap(reviewed.graphs.first).chain.sourceCheckpoint.draftID,
            identity: identity, reviewedAt: RepetitiveCaptureSourcePackageFixture.date)
        let imported = try destinationReviewImportedHistory(source: fixture.history, payload: prepared.payload,
            generationID: identity.targetPointer.generationID)
        let expected = try RepetitiveCaptureDestinationReviewHistoryV1.firstReview(
            workspaceID: imported.checkpoint.workspaceID, mutationID: imported.checkpoint.mutationID,
            in: imported.snapshot)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("c36-review-receipt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try RetainedSourceHistoryTargetV2(root: root, records: imported.snapshot.receipts)
        defer { try? target.close() }
        @MainActor func read() throws -> RepetitiveCaptureDestinationReviewEvidenceV1 {
            try target.writer.repetitiveCaptureFirstDestinationReview(
                workspaceID: imported.checkpoint.workspaceID, mutationID: imported.checkpoint.mutationID)
        }
        @MainActor func journalRead() throws -> RepetitiveCaptureDestinationReviewEvidenceV1 {
            try target.journal.repetitiveCaptureFirstDestinationReview(
                workspaceID: imported.checkpoint.workspaceID, mutationID: imported.checkpoint.mutationID)
        }
        let before = try target.rawState()
        try target.journal.validateAll()
        XCTAssertEqual(try read(), expected)
        XCTAssertEqual(try journalRead(), expected)
        XCTAssertEqual(try target.rawState(), before)
        XCTAssertTrue(try target.journal.exportSnapshot().entityRevisions.isEmpty)
        XCTAssertEqual(before.canonicalCounts, [0, 0, 0, 0, 0])
        XCTAssertThrowsError(try RepetitiveCaptureDestinationReviewHistoryV1.firstReview(
            workspaceID: imported.checkpoint.workspaceID, mutationID: imported.checkpoint.mutationID,
            in: target.journal.exportSnapshot()))
        let key = MutationWorkspaceKeyV1.value(workspaceID: imported.checkpoint.workspaceID,
                                               mutationID: imported.checkpoint.mutationID)
        let row = try XCTUnwrap(target.context.fetch(FetchDescriptor<MutationReceiptRow>()).first {
            $0.workspaceMutationKey == key
        })
        let digest = row.receiptSHA256
        row.receiptSHA256 = String(repeating: "f", count: 64)
        let dirty = try target.rawState()
        XCTAssertThrowsError(try read())
        XCTAssertThrowsError(try journalRead())
        XCTAssertEqual(try target.rawState(), dirty)
        target.context.rollback()
        XCTAssertEqual(try target.rawState(), before)
        row.receiptSHA256 = String(repeating: "f", count: 64)
        try target.context.save()
        let corrupt = try target.rawState()
        XCTAssertThrowsError(try read())
        XCTAssertThrowsError(try journalRead())
        XCTAssertEqual(try target.rawState(), corrupt)
        row.receiptSHA256 = digest
        try target.context.save()
        let quarantine = MutationQuarantineRow(workspaceID: imported.checkpoint.workspaceID,
            mutationID: imported.checkpoint.mutationID, identityDomain: .mutationEnvelope,
            acceptedIdentitySHA256: expected.original.receipt.envelopeSHA256,
            conflictingIdentitySHA256: String(repeating: "b", count: 64),
            detectedAt: RepetitiveCaptureSourcePackageFixture.date.addingTimeInterval(1_000))
        target.context.insert(quarantine)
        try target.context.save()
        let quarantined = try target.rawState()
        XCTAssertThrowsError(try read())
        XCTAssertThrowsError(try journalRead())
        XCTAssertEqual(try target.rawState(), quarantined)
        target.context.delete(quarantine)
        try target.context.save()
        target.context.delete(row)
        try target.context.save()
        let missing = try target.rawState()
        XCTAssertThrowsError(try read())
        XCTAssertThrowsError(try journalRead())
        XCTAssertEqual(try target.rawState(), missing)
        try target.insert(imported.original)
        try target.context.save()
        XCTAssertEqual(try read(), expected)
        XCTAssertEqual(try target.rawState(), before)
        try target.closeJournalLease()
        XCTAssertThrowsError(try journalRead())
        XCTAssertEqual(try read(), expected)
        target.writer.invalidate()
        XCTAssertThrowsError(try read())
        XCTAssertEqual(try target.rawState(), before)
    }

    func testFirstReviewDerivesCompleteReplacementAndForkRelationsWithoutChangingOriginals() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture()
        defer { fixture.removePackages() }
        let reviewed = try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: fixture.validatedPackage())
        let originalHistory = try FieldDraftCanonicalCodecV1.encode(fixture.history)
        let graph = try XCTUnwrap(reviewed.graphs.first)
        for mode in [BackupRestoreMode.replaceExisting, .fork] {
            let identity = try destinationReviewIdentity(mode: mode, source: fixture.workspaceID.rawValue)
            let prepared = try RepetitiveCaptureDestinationReviewV1.prepareFirst(from: reviewed,
                sourceDraftID: graph.chain.sourceCheckpoint.draftID, identity: identity,
                reviewedAt: RepetitiveCaptureSourcePackageFixture.date)
            let payload = prepared.payload
            let checkpoint = prepared.checkpoint
            XCTAssertEqual(try RepetitiveCaptureDestinationReviewCodecV1.decode(checkpoint.payloadData), payload)
            try payload.validateFirstSource(against: reviewed, identity: identity)
            try RepetitiveCaptureDestinationReviewCodecV1.validateInitialCheckpoint(checkpoint,
                creationGenerationID: identity.targetPointer.generationID)
            XCTAssertEqual(checkpoint.state, .recoveryRequired)
            XCTAssertEqual(checkpoint.draftRevision, 1)
            XCTAssertEqual(checkpoint.baseCanonicalRevision, graph.packageCurrentRound.revision)
            XCTAssertTrue(checkpoint.stageIDs.isEmpty)
            XCTAssertNil(checkpoint.lastDurableMutationID)
            XCTAssertNil(checkpoint.lastReceiptSHA256)
            XCTAssertNil(payload.provenance.immediatePredecessor)
            XCTAssertEqual(Set(prepared.sourceCheckpointIDs), Set(graph.checkpoints.map { $0.original.draftID }))
            let pairs = payload.provenance.ultimateToDestinationPairs
            XCTAssertEqual(Set(pairs.filter { $0.kind == .roundItem }.map(\.sourceID)), Set(graph.packageCurrentRound.items.map(\.itemID)))
            XCTAssertEqual(Set(pairs.filter { $0.kind == .asset }.map(\.sourceID)), Set(graph.packageCurrentRound.items.map { $0.selection.assetID }))
            XCTAssertEqual(Set(pairs.filter { $0.kind == .site }.map(\.sourceID)), Set(graph.packageCurrentRound.items.map { $0.selection.siteID }))
            XCTAssertEqual(Set(pairs.filter { $0.kind == .completion }.map(\.sourceID)), Set(graph.packageCurrentRound.items.compactMap { $0.completion?.completionID }))
            XCTAssertEqual(pairs.filter { $0.kind == .launchPlan }.map(\.sourceID), [graph.chain.launch.planID])
            for pair in pairs {
                let expected = pair.kind == .checkpoint
                    ? RestoreIdentityV1.destinationFieldDraftID(for: pair.sourceID, namespace: "draft",
                        mode: mode, destinationWorkspaceID: identity.targetPointer.workspaceID)
                    : RestoreIdentityV1.destinationRecordID(for: pair.sourceID)
                XCTAssertEqual(pair.destinationID, expected)
                XCTAssertNotEqual(checkpoint.draftID, pair.sourceID)
                XCTAssertNotEqual(checkpoint.draftID, pair.destinationID)
                XCTAssertNotEqual(checkpoint.mutationID.rawValue, pair.sourceID)
                XCTAssertNotEqual(checkpoint.mutationID.rawValue, pair.destinationID)
            }
            XCTAssertFalse(reviewed.requiredHistory.contains { $0.envelope.mutationID == checkpoint.mutationID })
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.encode(fixture.history), originalHistory)
            XCTAssertNotEqual(checkpoint.codec, graph.chain.sourceCheckpoint.codec)
        }
    }

    func testFirstReviewRetryUsesGenerationBoundFreshIdentities() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { fixture.removePackages() }
        let reviewed = try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: fixture.validatedPackage())
        let sourceID = try XCTUnwrap(reviewed.graphs.first).chain.sourceCheckpoint.draftID
        let identity = try destinationReviewIdentity(mode: .fork, source: fixture.workspaceID.rawValue)
        func prepare(_ value: RestoreIdentityV1) throws -> PreparedRepetitiveCaptureDestinationReviewV1 {
            try RepetitiveCaptureDestinationReviewV1.prepareFirst(from: reviewed, sourceDraftID: sourceID,
                identity: value, reviewedAt: RepetitiveCaptureSourcePackageFixture.date)
        }
        let first = try prepare(identity)
        XCTAssertEqual(first, try prepare(identity))
        let nextIdentity = try destinationReviewIdentity(mode: .fork, source: fixture.workspaceID.rawValue, generation: 80_099)
        let next = try prepare(nextIdentity)
        XCTAssertEqual(first.payload, next.payload)
        XCTAssertNotEqual(first.checkpoint.draftID, next.checkpoint.draftID)
        XCTAssertNotEqual(first.checkpoint.mutationID, next.checkpoint.mutationID)
        XCTAssertThrowsError(try RepetitiveCaptureDestinationReviewCodecV1.validateInitialCheckpoint(
            first.checkpoint, creationGenerationID: nextIdentity.targetPointer.generationID))
        for mode in [BackupRestoreMode.clone, .emptyInstall] {
            XCTAssertThrowsError(try prepare(destinationReviewIdentity(mode: mode, source: fixture.workspaceID.rawValue)))
        }
        XCTAssertThrowsError(try prepare(destinationReviewIdentity(mode: .replaceExisting,
            source: fixture.workspaceID.rawValue, destination: fixture.workspaceID.rawValue)))
        XCTAssertThrowsError(try prepare(destinationReviewIdentity(mode: .fork, source: destinationReviewID(90_001))))
        XCTAssertThrowsError(try RepetitiveCaptureDestinationReviewV1.prepareFirst(from: reviewed,
            sourceDraftID: destinationReviewID(90_002), identity: identity,
            reviewedAt: RepetitiveCaptureSourcePackageFixture.date))
    }

    func testRehashedPlausibleRelationsStillRequireExactSourceCoverage() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture()
        defer { fixture.removePackages() }
        let reviewed = try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: fixture.validatedPackage())
        let identity = try destinationReviewIdentity(mode: .replaceExisting, source: fixture.workspaceID.rawValue)
        let prepared = try RepetitiveCaptureDestinationReviewV1.prepareFirst(from: reviewed,
            sourceDraftID: XCTUnwrap(reviewed.graphs.first).chain.sourceCheckpoint.draftID,
            identity: identity, reviewedAt: RepetitiveCaptureSourcePackageFixture.date)
        let payload = prepared.payload
        for kind in [RepetitiveCaptureReviewIdentityKindV1.asset, .launchPlan] {
            var pairs = payload.provenance.ultimateToDestinationPairs
            let index = try XCTUnwrap(pairs.firstIndex { $0.kind == kind })
            pairs[index] = try .init(kind: kind, sourceID: destinationReviewID(90_003), destinationID: destinationReviewID(90_003))
            pairs.sort(by: destinationReviewPairLess)
            let changed = try destinationReviewPayload(payload, pairs: pairs)
            // Valid shape and a recomputed digest are insufficient evidence.
            try changed.validate()
            XCTAssertThrowsError(try changed.validateFirstSource(against: reviewed, identity: identity))
        }
        let allPairs = payload.provenance.ultimateToDestinationPairs
        XCTAssertThrowsError(try destinationReviewPayload(payload, pairs: allPairs.filter { $0.kind != .checkpoint }))
        XCTAssertThrowsError(try destinationReviewPayload(payload, pairs: Array(allPairs.reversed())))
        XCTAssertThrowsError(try destinationReviewPayload(payload, pairs: (allPairs + [allPairs[0]]).sorted(by: destinationReviewPairLess)))
        XCTAssertThrowsError(try RepetitiveCaptureReviewIdentityPairV1(kind: .asset,
            sourceID: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, destinationID: destinationReviewID(1)))
    }

    func testClosedCodecRejectsUnknownTagsKeysNoncanonicalAndInitialStateSubstitutions() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { fixture.removePackages() }
        let reviewed = try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: fixture.validatedPackage())
        let identity = try destinationReviewIdentity(mode: .fork, source: fixture.workspaceID.rawValue)
        let prepared = try RepetitiveCaptureDestinationReviewV1.prepareFirst(from: reviewed,
            sourceDraftID: XCTUnwrap(reviewed.graphs.first).chain.sourceCheckpoint.draftID,
            identity: identity, reviewedAt: RepetitiveCaptureSourcePackageFixture.date)
        let bytes = prepared.checkpoint.payloadData
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        for key in ["unknown", "tag", "schemaVersion"] {
            var changed = object
            if key == "schemaVersion" { changed[key] = 999 } else { changed[key] = "UNKNOWN" }
            XCTAssertThrowsError(try RepetitiveCaptureDestinationReviewCodecV1.decode(JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys])))
        }
        var provenance = try XCTUnwrap(object["provenance"] as? [String: Any])
        provenance["unknown"] = true
        object["provenance"] = provenance
        XCTAssertThrowsError(try RepetitiveCaptureDestinationReviewCodecV1.decode(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])))
        for value in ["UNKNOWN", "FORK"] {
            var changed = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            var p = try XCTUnwrap(changed["provenance"] as? [String: Any])
            var pairs = try XCTUnwrap(p["ultimateToDestinationPairs"] as? [[String: Any]])
            if value == "UNKNOWN" { pairs[0]["kind"] = value }
            else { pairs[0]["unknown"] = true }
            p["ultimateToDestinationPairs"] = pairs
            changed["provenance"] = p
            XCTAssertThrowsError(try RepetitiveCaptureDestinationReviewCodecV1.decode(JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys])))
        }
        var nullObject = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var nullProvenance = try XCTUnwrap(nullObject["provenance"] as? [String: Any])
        nullProvenance["immediatePredecessor"] = NSNull()
        nullObject["provenance"] = nullProvenance
        XCTAssertThrowsError(try RepetitiveCaptureDestinationReviewCodecV1.decode(JSONSerialization.data(withJSONObject: nullObject, options: [.sortedKeys])))
        XCTAssertThrowsError(try RepetitiveCaptureDestinationReviewCodecV1.decode(bytes + Data([10])))
        XCTAssertThrowsError(try RepetitiveCaptureDestinationReviewCodecV1.decode(Data()))
        XCTAssertThrowsError(try RepetitiveCaptureDestinationReviewCodecV1.decode(Data(repeating: 32, count: FieldDraftLimitsV1.maximumPayloadBytes + 1)))
        let c = prepared.checkpoint
        for state in [FieldDraftStateV1.active, .conflicted, .discardPending, .discarded] {
            XCTAssertThrowsError(try RepetitiveCaptureDestinationReviewCodecV1.validateInitialCheckpoint(
                FieldDraftCheckpointV1(draftID: c.draftID, workspaceID: c.workspaceID, scope: c.scope,
                    purpose: c.purpose, codec: c.codec, baseCanonicalRevision: c.baseCanonicalRevision,
                    draftRevision: 1, payloadData: bytes, stageIDs: [], resumeAnchor: c.resumeAnchor,
                    state: state, updatedAt: c.updatedAt, mutationID: c.mutationID),
                creationGenerationID: identity.targetPointer.generationID))
        }
    }

    func testEachRetainedGraphGetsItsOwnReviewWithoutRevivingItsDisposition() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture(
            secondSameScopeGraph: true, secondGraphIsHistorical: true)
        defer { fixture.removePackages() }
        let reviewed = try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: fixture.validatedPackage())
        let identity = try destinationReviewIdentity(mode: .fork, source: fixture.workspaceID.rawValue)
        let proposals = try reviewed.graphs.map { graph in
            try RepetitiveCaptureDestinationReviewV1.prepareFirst(from: reviewed,
                sourceDraftID: graph.chain.sourceCheckpoint.draftID, identity: identity,
                reviewedAt: RepetitiveCaptureSourcePackageFixture.date)
        }
        XCTAssertEqual(proposals.count, 2)
        XCTAssertEqual(Set(proposals.map { $0.checkpoint.draftID }).count, 2)
        for proposal in proposals {
            try proposal.payload.validateFirstSource(against: reviewed, identity: identity)
            XCTAssertEqual(proposal.checkpoint.state, .recoveryRequired)
            try proposal.payload.source.validate(against: reviewed)
        }
    }

    func testPredecessorShapeIsClosedAndDoesNotAuthenticateAnAncestor() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture(sourceOnly: true)
        defer { fixture.removePackages() }
        let reviewed = try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: fixture.validatedPackage())
        let identity = try destinationReviewIdentity(mode: .fork, source: fixture.workspaceID.rawValue)
        let graph = try XCTUnwrap(reviewed.graphs.first)
        let prepared = try RepetitiveCaptureDestinationReviewV1.prepareFirst(from: reviewed,
            sourceDraftID: graph.chain.sourceCheckpoint.draftID, identity: identity,
            reviewedAt: RepetitiveCaptureSourcePackageFixture.date)
        let original = try XCTUnwrap(reviewed.requiredHistory.first)
        let pairs = prepared.payload.provenance.ultimateToDestinationPairs
        // These are genuine source bytes but not a destination-review receipt.
        // The public grammar may parse this claim; source authentication must
        // reject it. Actual predecessor receipt authentication is a later gate.
        func link(workspace: WorkspaceID, relation: [RepetitiveCaptureReviewIdentityPairV1]) throws
            -> RepetitiveCaptureReviewPredecessorV1 {
            try .init(workspaceID: workspace, reviewDraftID: graph.chain.sourceCheckpoint.draftID,
                reviewCheckpointSHA256: graph.chain.sourceCheckpoint.checkpointSHA256,
                reviewMutationID: original.envelope.mutationID,
                reviewEnvelopeSHA256: FieldDraftCanonicalCodecV1.sha256(original.original.envelopeData),
                reviewReceiptIdentity: original.receipt.identity,
                reviewReceiptSHA256: FieldDraftCanonicalCodecV1.sha256(original.original.receiptData),
                predecessorProvenanceSHA256: prepared.payload.provenance.provenanceSHA256,
                predecessorToDestinationPairs: relation)
        }
        let predecessor = try link(workspace: fixture.workspaceID, relation: pairs)
        func withPredecessor(_ predecessor: RepetitiveCaptureReviewPredecessorV1) throws
            -> RepetitiveCaptureDestinationReviewPayloadV1 {
            try .init(source: prepared.payload.source, provenance: .init(mode: .fork,
                destinationWorkspaceID: prepared.payload.provenance.destinationWorkspaceID,
                ultimateSourceReferenceSHA256: prepared.payload.source.referenceSHA256,
                ultimateToDestinationPairs: pairs, immediatePredecessor: predecessor))
        }
        let claim = try withPredecessor(predecessor)
        let bytes = try RepetitiveCaptureDestinationReviewCodecV1.encode(claim)
        XCTAssertEqual(try RepetitiveCaptureDestinationReviewCodecV1.decode(bytes), claim)
        XCTAssertThrowsError(try claim.validateFirstSource(against: reviewed, identity: identity))
        XCTAssertThrowsError(try link(workspace: prepared.checkpoint.workspaceID, relation: pairs))
        XCTAssertThrowsError(try withPredecessor(link(workspace: fixture.workspaceID,
            relation: Array(pairs.dropLast()))))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var provenance = try XCTUnwrap(object["provenance"] as? [String: Any])
        var ancestor = try XCTUnwrap(provenance["immediatePredecessor"] as? [String: Any])
        ancestor["nestedPayload"] = true
        provenance["immediatePredecessor"] = ancestor
        object["provenance"] = provenance
        XCTAssertThrowsError(try RepetitiveCaptureDestinationReviewCodecV1.decode(
            JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])))
    }
}

// Shared only with the already-selected maximum source graph test. Identity
// decisions follow the production mode rules; no unchecked positive fixture.
func destinationReviewIdentity(mode: BackupRestoreMode, source: UUID,
                               destination: UUID = destinationReviewID(80_001),
                               generation: Int = 80_005) throws -> RestoreIdentityV1 {
    try RestoreIdentityDecisionV1.decide(.init(mode: mode,
        source: .init(workspaceID: source, replicaID: destinationReviewID(80_002)),
        oldPointer: .init(generationID: destinationReviewID(80_003),
            generationManifestSHA256: String(repeating: "a", count: 64),
            workspaceID: mode == .replaceExisting ? destination : destinationReviewID(80_004),
            replicaID: destinationReviewID(80_006)),
        targetGenerationID: destinationReviewID(generation),
        targetGenerationManifestSHA256: String(repeating: "b", count: 64),
        allocatedWorkspaceID: mode == .clone || mode == .fork ? destination : nil,
        allocatedReplicaID: destinationReviewID(80_007)))
}

private struct DestinationReviewImportedHistory {
    let checkpoint: FieldDraftCheckpointV1
    let original: MutationHistoryReceiptRecordV1
    let snapshot: MutationHistorySnapshotV1
}

private func destinationReviewStart(_ fixture: RepetitiveCaptureSourcePackageFixture) throws
    -> DestinationReviewImportedHistory {
    let reviewed = try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: fixture.validatedPackage())
    let identity = try destinationReviewIdentity(mode: .fork, source: fixture.workspaceID.rawValue)
    let prepared = try RepetitiveCaptureDestinationReviewV1.prepareFirst(from: reviewed,
        sourceDraftID: XCTUnwrap(reviewed.graphs.first).chain.sourceCheckpoint.draftID,
        identity: identity, reviewedAt: RepetitiveCaptureSourcePackageFixture.date)
    return try destinationReviewImportedHistory(source: fixture.history, payload: prepared.payload,
        generationID: identity.targetPointer.generationID, includeReversalBasis: true)
}

private func destinationReviewOriginalMap(_ records: [MutationHistoryReceiptRecordV1]) throws
    -> [String: MutationHistoryReceiptRecordV1] {
    var result: [String: MutationHistoryReceiptRecordV1] = [:]
    for record in records {
        let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
        let key = MutationWorkspaceKeyV1.value(workspaceID: envelope.workspaceID, mutationID: envelope.mutationID)
        guard result.updateValue(record, forKey: key) == nil else { throw FieldDraftFailureV1.invalidValue }
    }
    return result
}

private func destinationReviewSnapshot(_ original: MutationHistorySnapshotV1,
                                       receipts: [MutationHistoryReceiptRecordV1]) -> MutationHistorySnapshotV1 {
    .init(workspaceRevision: original.workspaceRevision, lastLocalSequence: original.lastLocalSequence,
        receipts: receipts, quarantines: original.quarantines, entityRevisions: original.entityRevisions)
}

private func destinationReviewAlteredLink(_ original: RepetitiveCaptureReviewPredecessorV1,
                                          field: String) throws -> RepetitiveCaptureReviewPredecessorV1 {
    let invalidDigest = String(repeating: "f", count: 64)
    let differentMutation = try MutationIDV1(rawValue: destinationReviewID(84_100))
    var pairs = original.predecessorToDestinationPairs
    if field == "predecessorToDestinationPairs" {
        let first = try XCTUnwrap(pairs.first)
        pairs[0] = try .init(kind: first.kind, sourceID: destinationReviewID(84_101), destinationID: first.destinationID)
        pairs.sort(by: destinationReviewPairLess)
    }
    let receiptIdentity = field == "reviewReceiptIdentity"
        ? MutationReceiptIdentityV1(workspaceID: original.workspaceID, replicaID: original.reviewReceiptIdentity.replicaID,
            localSequence: original.reviewReceiptIdentity.localSequence + 1)
        : original.reviewReceiptIdentity
    return try .init(workspaceID: original.workspaceID,
        reviewDraftID: field == "reviewDraftID" ? destinationReviewID(84_102) : original.reviewDraftID,
        reviewCheckpointSHA256: field == "reviewCheckpointSHA256" ? invalidDigest : original.reviewCheckpointSHA256,
        reviewMutationID: field == "reviewMutationID" ? differentMutation : original.reviewMutationID,
        reviewEnvelopeSHA256: field == "reviewEnvelopeSHA256" ? invalidDigest : original.reviewEnvelopeSHA256,
        reviewReceiptIdentity: receiptIdentity,
        reviewReceiptSHA256: field == "reviewReceiptSHA256" ? invalidDigest : original.reviewReceiptSHA256,
        predecessorProvenanceSHA256: field == "predecessorProvenanceSHA256" ? invalidDigest : original.predecessorProvenanceSHA256,
        predecessorToDestinationPairs: pairs)
}

/// Canonical imported-history fixture, not evidence that the not-yet-adopted
/// restore publisher ran. It exercises the real command/receipt contracts.
private func destinationReviewImportedHistory(source: MutationHistorySnapshotV1,
                                               payload: RepetitiveCaptureDestinationReviewPayloadV1,
                                               generationID: UUID,
                                               envelopeGenerationID: UUID? = nil,
                                               expectedBaseCanonicalRevision: UInt64? = nil,
                                               includeReversalBasis: Bool = false) throws
    -> DestinationReviewImportedHistory {
    let ids = try RepetitiveCaptureDestinationReviewCodecV1.initialIDs(payload: payload, generationID: generationID)
    let workspace = payload.provenance.destinationWorkspaceID
    let checkpoint = try FieldDraftCheckpointV1(draftID: ids.draftID, workspaceID: workspace,
        scope: RepetitiveCaptureDestinationReviewCodecV1.scope(draftID: ids.draftID),
        purpose: .repetitiveCapture, codec: RepetitiveCaptureDestinationReviewCodecV1.release(),
        baseCanonicalRevision: payload.source.value.packageCurrentRound.revision,
        draftRevision: 1, payloadData: RepetitiveCaptureDestinationReviewCodecV1.encode(payload), stageIDs: [],
        resumeAnchor: DraftResumeAnchorV1(sectionID: "sourceReview"), state: .recoveryRequired,
        updatedAt: RepetitiveCaptureSourcePackageFixture.date, mutationID: ids.mutationID)
    let mutation = try FieldDraftMutationV1(workspaceID: workspace, expectedRevision: 0,
        expectedBaseCanonicalRevision: expectedBaseCanonicalRevision ?? checkpoint.baseCanonicalRevision,
        mutationID: checkpoint.mutationID, postImage: .createCheckpoint(checkpoint))
    return try destinationReviewAppend(source: source, checkpoint: checkpoint, mutation: mutation,
        generationID: envelopeGenerationID ?? generationID, includeReversalBasis: includeReversalBasis)
}

private func destinationReviewAppend(source: MutationHistorySnapshotV1, checkpoint: FieldDraftCheckpointV1,
                                     mutation: FieldDraftMutationV1, generationID: UUID,
                                     includeReversalBasis: Bool = false) throws -> DestinationReviewImportedHistory {
    let workspace = checkpoint.workspaceID
    let replica = ReplicaID(rawValue: destinationReviewID(90_201))
    let priorReceipts = try source.receipts.map { try MutationReceiptV1.decodeCanonical(from: $0.receiptData) }
        .filter { $0.identity.workspaceID == workspace }
    let workspaceRevision = priorReceipts.map { $0.resultingRevision.workspaceRevision }.max() ?? 0
    let priorSequence = priorReceipts.filter { $0.identity.replicaID == replica }.map { $0.identity.localSequence }.max() ?? 0
    guard workspaceRevision < UInt64.max, priorSequence < UInt64.max else { throw FieldDraftFailureV1.limitExceeded }
    let sequence = priorSequence + 1
    let expected = try WorkspaceExpectedRevisionV1(workspaceID: workspace,
        generationID: generationID, writerInstanceID: destinationReviewID(90_200),
        workspaceRevision: workspaceRevision, entityRevisions: mutation.concurrencyIdentities.map {
            .init(identity: $0, revision: try mutation.expectedRevision(for: $0))
        }.sorted { $0.identity.stableKey < $1.identity.stableKey })
    let receiptIdentity = MutationReceiptIdentityV1(workspaceID: workspace, replicaID: replica, localSequence: sequence)
    let basis: ReversalBasisV1?
    if includeReversalBasis {
        let plan = try SemanticReversalPlanV1(mutationID: checkpoint.mutationID, commandKind: .applyFieldDraft,
            expectedRevision: expected, prospectiveTargets: mutation.affectedIdentities,
            requiredSemanticValues: [.init(key: "original-review-checkpoint", value: checkpoint.checkpointSHA256)],
            contentReferences: [], dependencyGraph: [], conflicts: [], compensatingCommands: [])
        basis = try ReversalBasisV1(targetMutationID: checkpoint.mutationID,
            targetReceiptIdentity: receiptIdentity, plan: plan)
    } else { basis = nil }
    let envelope = try MutationEnvelopeV1(request: .init(mutationID: checkpoint.mutationID,
        expectedRevision: expected, command: .applyFieldDraft(mutation)),
        identity: .init(workspaceID: workspace, replicaID: replica), reversalPlanDigest: basis?.planDigest)
    let images = try mutation.postImage.mutationPostImages
    let resulting = try WorkspaceExpectedRevisionV1(workspaceID: workspace,
        generationID: expected.generationID, writerInstanceID: expected.writerInstanceID,
        workspaceRevision: workspaceRevision + 1, entityRevisions: images.map {
            .init(identity: try $0.identity, revision: $0.revision)
        }.sorted { $0.identity.stableKey < $1.identity.stableKey })
    let receipt = try MutationReceiptV1(identity: receiptIdentity,
        envelope: envelope, resultingRevision: .init(resulting), postImages: images,
        committedAt: RepetitiveCaptureSourcePackageFixture.date.addingTimeInterval(200 + Double(workspaceRevision)))
    let original = MutationHistoryReceiptRecordV1(envelopeData: try envelope.canonicalData(),
        receiptData: try receipt.canonicalData(), reversalBasisData: try basis?.canonicalData(), semanticReversalData: nil)
    let keyed = try (source.receipts + [original]).map { record in
        (try MutationReceiptV1.decodeCanonical(from: record.receiptData).identity.stableKey, record)
    }
    guard Set(source.entityRevisions.map(\.identity)).count == source.entityRevisions.count else {
        throw FieldDraftFailureV1.invalidValue
    }
    var projection = Dictionary(uniqueKeysWithValues: source.entityRevisions.map { ($0.identity, $0) })
    for image in images {
        let key = try image.identity
        let revision = max(projection[key]?.revision ?? 0, image.revision)
        projection[key] = .init(identity: key, revision: revision)
    }
    let snapshot = MutationHistorySnapshotV1(workspaceRevision: max(workspaceRevision + 1, source.workspaceRevision),
        lastLocalSequence: max(sequence, source.lastLocalSequence), receipts: keyed.sorted { $0.0 < $1.0 }.map { $0.1 },
        quarantines: source.quarantines,
        entityRevisions: projection.values.sorted { $0.identity.stableKey < $1.identity.stableKey })
    try MutationJournalStoreV1.validateImportedSnapshot(snapshot)
    return .init(checkpoint: checkpoint, original: original, snapshot: snapshot)
}

private func destinationReviewRevision(_ original: FieldDraftCheckpointV1,
                                       state: FieldDraftStateV1 = .conflicted,
                                       mutationSeed: Int, payloadData: Data? = nil) throws -> FieldDraftCheckpointV1 {
    try .init(draftID: original.draftID, workspaceID: original.workspaceID, scope: original.scope,
        purpose: original.purpose, codec: original.codec, baseCanonicalRevision: original.baseCanonicalRevision,
        draftRevision: original.draftRevision + 1, payloadData: payloadData ?? original.payloadData,
        stageIDs: [], resumeAnchor: original.resumeAnchor, state: state,
        lastDurableMutationID: original.lastDurableMutationID, lastReceiptSHA256: original.lastReceiptSHA256,
        updatedAt: original.updatedAt.addingTimeInterval(1),
        mutationID: MutationIDV1(rawValue: destinationReviewID(mutationSeed)))
}

private func destinationReviewAppendRevision(_ checkpoint: FieldDraftCheckpointV1,
                                             predecessor: FieldDraftCheckpointV1,
                                             to source: MutationHistorySnapshotV1,
                                             generationID: UUID) throws -> DestinationReviewImportedHistory {
    let mutation = try FieldDraftMutationV1(workspaceID: checkpoint.workspaceID,
        expectedRevision: predecessor.draftRevision, expectedBaseCanonicalRevision: predecessor.baseCanonicalRevision,
        mutationID: checkpoint.mutationID, postImage: .reviseCheckpoint(checkpoint))
    return try destinationReviewAppend(source: source, checkpoint: checkpoint, mutation: mutation, generationID: generationID)
}

private func destinationReviewID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "89000000-0000-0000-0000-%012d", value))!
}

private func destinationReviewPairLess(_ lhs: RepetitiveCaptureReviewIdentityPairV1,
                                       _ rhs: RepetitiveCaptureReviewIdentityPairV1) -> Bool {
    if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
    if lhs.sourceID != rhs.sourceID { return lhs.sourceID.uuidString.lowercased() < rhs.sourceID.uuidString.lowercased() }
    return lhs.destinationID.uuidString.lowercased() < rhs.destinationID.uuidString.lowercased()
}

private func destinationReviewPayload(_ original: RepetitiveCaptureDestinationReviewPayloadV1,
                                     pairs: [RepetitiveCaptureReviewIdentityPairV1]) throws -> RepetitiveCaptureDestinationReviewPayloadV1 {
    try .init(source: original.source, provenance: .init(mode: original.provenance.mode,
        destinationWorkspaceID: original.provenance.destinationWorkspaceID,
        ultimateSourceReferenceSHA256: original.source.referenceSHA256, ultimateToDestinationPairs: pairs))
}

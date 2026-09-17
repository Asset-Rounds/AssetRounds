import Foundation
import SwiftData
import XCTest

@testable import FieldEvidenceApp

final class V23RepetitiveCaptureSourceGraphReviewTests: XCTestCase {
    func testValidatedPackageYieldsOrderedCompleteGraphWithCompletedAndPendingEffects() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture()
        defer { fixture.removePackages() }

        let package = try fixture.validatedPackage()
        let reviewed = try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: package)

        XCTAssertEqual(reviewed.sourceWorkspaceID, fixture.workspaceID)
        XCTAssertEqual(reviewed.sourcePersistentSchemaVersion, 45)
        XCTAssertEqual(reviewed.sourceRecordsSchemaVersion, 44)
        XCTAssertEqual(reviewed.manifestJSONSHA256, package.manifestJSONSHA256)
        XCTAssertEqual(reviewed.recordsJSONSHA256, package.recordsJSONSHA256)
        XCTAssertEqual(reviewed.graphs.count, 1)
        let graph = try XCTUnwrap(reviewed.graphs.first)
        XCTAssertTrue(graph.isUnchangedActiveSource)
        XCTAssertEqual(graph.packageCurrentRound, fixture.rounds.last)
        XCTAssertEqual(graph.checkpoints.map(\.original), fixture.checkpoints)
        XCTAssertEqual(graph.chain.nodes.count, 3)
        XCTAssertFalse(try XCTUnwrap(graph.chain.nodes.first).isPendingRoundEffect)
        XCTAssertNil(graph.chain.nodes[1].step.roundMutation)
        XCTAssertTrue(try XCTUnwrap(graph.chain.nodes.last).isPendingRoundEffect)
        XCTAssertEqual(reviewed.requiredHistory.count, fixture.history.receipts.count)
        XCTAssertEqual(reviewed.requiredHistory.map { $0.receipt.resultingRevision.workspaceRevision },
                       Array(1...fixture.history.receipts.count).map(UInt64.init))
    }

    func testAuthenticDiscardedSourceRetainsOriginalGraphAndExactTerminalDisposition() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture(discardSource: true)
        defer { fixture.removePackages() }

        let reviewed = try RepetitiveCaptureSourceGraphReviewV2.review(
            sourcePackage: fixture.validatedPackage())

        let graph = try XCTUnwrap(reviewed.graphs.first)
        XCTAssertFalse(graph.isUnchangedActiveSource)
        XCTAssertEqual(graph.checkpoints.first?.original.state, .active)
        XCTAssertEqual(graph.checkpoints.first?.current.state, .discarded)
        XCTAssertEqual(graph.checkpoints.first?.lifecycle.count, 3)
        XCTAssertEqual(graph.checkpoints.first?.current.draftRevision, 3)
        XCTAssertEqual(graph.chain.sourceCheckpoint, graph.checkpoints.first?.original)
        XCTAssertEqual(graph.packageCurrentRound, fixture.rounds.last)
    }

    func testDiscardedSourceRejectsOmittedDisplacedAndDuplicateCurrentDiscardReceipt() throws {
        let mutations: [(inout [[String: Any]]) throws -> Void] = [
            { (rows: inout [[String: Any]]) in
                rows.removeAll { ($0["kind"] as? String) == "discardReceipt" }
            },
            { (rows: inout [[String: Any]]) in
                let index = try XCTUnwrap(rows.firstIndex {
                    ($0["kind"] as? String) == "discardReceipt"
                })
                rows[index]["workspaceID"] = RepetitiveCaptureSourcePackageFixture.id(9_999)
                    .uuidString.lowercased()
            },
            { (rows: inout [[String: Any]]) in
                let value = try XCTUnwrap(rows.first {
                    ($0["kind"] as? String) == "discardReceipt"
                })
                rows.append(value)
            }
        ]
        for mutation in mutations {
            let fixture = try RepetitiveCaptureSourcePackageFixture(discardSource: true)
            defer { fixture.removePackages() }
            XCTAssertThrowsError(try {
                let package = try fixture.validatedPackage { object in
                    var rows = try XCTUnwrap(object["fieldDrafts"] as? [[String: Any]])
                    try mutation(&rows)
                    object["fieldDrafts"] = rows
                }
                _ = try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: package)
            }())
        }

        for fixture in [
            try RepetitiveCaptureSourcePackageFixture(directDiscardedSource: true),
            try RepetitiveCaptureSourcePackageFixture(
                discardSource: true, staleExtraDiscardReceipt: true)
        ] {
            defer { fixture.removePackages() }
            let package = try fixture.validatedPackage()
            XCTAssertThrowsError(
                try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: package))
        }
    }

    func testForeignWorkspaceOriginalHistoryDoesNotCreateOrTaintSourceGraph() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture(includeForeignOriginal: true)
        defer { fixture.removePackages() }

        let validated = try fixture.validatedPackage()
        let encoded = try BackupCanonicalEncoderV1().encodeRecords(validated.records).data
        let decoded = try BackupCanonicalDecoderV1().decodeRecords(encoded)
        XCTAssertEqual(try BackupCanonicalEncoderV1().encodeRecords(decoded).data, encoded)
        let originalForeign = try XCTUnwrap(validated.records.mutationHistory).receipts.filter {
            try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData).workspaceID
                != fixture.workspaceID
        }
        let decodedForeign = try XCTUnwrap(decoded.mutationHistory).receipts.filter {
            try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData).workspaceID
                != fixture.workspaceID
        }
        XCTAssertFalse(originalForeign.isEmpty)
        XCTAssertEqual(decodedForeign, originalForeign)

        let reviewed = try RepetitiveCaptureSourceGraphReviewV2.review(
            sourcePackage: validated)

        XCTAssertEqual(reviewed.graphs.count, 1)
        XCTAssertEqual(reviewed.graphs.first?.checkpoints.count, fixture.checkpoints.count)
        XCTAssertEqual(reviewed.requiredHistory.count, fixture.history.receipts.count / 2)
        XCTAssertTrue(reviewed.requiredHistory.allSatisfy {
            $0.envelope.workspaceID == fixture.workspaceID
        })

        let configurationClone = try RepetitiveCaptureSourcePackageFixture(
            foreignHistoryOnly: true)
        defer { configurationClone.removePackages() }
        let foreignOnlyPackage = try configurationClone.validatedPackage()
        let foreignOnlyBytes = try BackupCanonicalEncoderV1()
            .encodeRecords(foreignOnlyPackage.records).data
        let foreignOnlyRoundTrip = try BackupCanonicalDecoderV1()
            .decodeRecords(foreignOnlyBytes)
        XCTAssertEqual(
            try BackupCanonicalEncoderV1().encodeRecords(foreignOnlyRoundTrip).data,
            foreignOnlyBytes
        )
        XCTAssertEqual(
            foreignOnlyRoundTrip.mutationHistory,
            foreignOnlyPackage.records.mutationHistory
        )
        let empty = try RepetitiveCaptureSourceGraphReviewV2.review(
            sourcePackage: foreignOnlyPackage)
        XCTAssertEqual(empty.sourceWorkspaceID, configurationClone.workspaceID)
        XCTAssertTrue(empty.graphs.isEmpty)
        XCTAssertTrue(empty.requiredHistory.isEmpty)
    }

    func testAuthenticLaterActivePayloadAndDiscardPendingRemainHistoricalReviewOnly() throws {
        let fixtures = [
            try RepetitiveCaptureSourcePackageFixture(laterActiveSource: true),
            try RepetitiveCaptureSourcePackageFixture(discardPendingSource: true)
        ]
        defer { fixtures.forEach { $0.removePackages() } }

        let laterActive = try RepetitiveCaptureSourceGraphReviewV2.review(
            sourcePackage: fixtures[0].validatedPackage())
        let changed = try XCTUnwrap(laterActive.graphs.first?.checkpoints.first)
        XCTAssertFalse(try XCTUnwrap(laterActive.graphs.first).isUnchangedActiveSource)
        XCTAssertEqual(changed.original.state, .active)
        XCTAssertEqual(changed.current.state, .active)
        XCTAssertEqual(changed.current.draftRevision, 2)
        XCTAssertNotEqual(changed.current.payloadData, changed.original.payloadData)
        XCTAssertEqual(changed.lifecycle.count, 2)

        let pending = try RepetitiveCaptureSourceGraphReviewV2.review(
            sourcePackage: fixtures[1].validatedPackage())
        let pendingCheckpoint = try XCTUnwrap(pending.graphs.first?.checkpoints.first)
        XCTAssertFalse(try XCTUnwrap(pending.graphs.first).isUnchangedActiveSource)
        XCTAssertEqual(pendingCheckpoint.original.state, .active)
        XCTAssertEqual(pendingCheckpoint.current.state, .discardPending)
        XCTAssertEqual(pendingCheckpoint.lifecycle.count, 2)
    }

    func testDiscardedHistoricalGraphPreservesCapturedFrontierAndAuthenticatesLaterRound() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture(
            discardSource: true, laterRoundAfterDisposition: true)
        defer { fixture.removePackages() }

        let reviewed = try RepetitiveCaptureSourceGraphReviewV2.review(
            sourcePackage: fixture.validatedPackage())

        let graph = try XCTUnwrap(reviewed.graphs.first)
        XCTAssertFalse(graph.isUnchangedActiveSource)
        XCTAssertEqual(graph.checkpoints.first?.current.state, .discarded)
        XCTAssertEqual(graph.chain.currentRound.revision, 3)
        XCTAssertTrue(try XCTUnwrap(graph.chain.nodes.last).isPendingRoundEffect)
        XCTAssertEqual(graph.packageCurrentRound.revision, 4)
        XCTAssertEqual(reviewed.requiredHistory.filter {
            if case .applyRoundSession = $0.envelope.command { return true }
            return false
        }.count, 4)
    }

    func testSameScopeHistoricalGraphsAreAllowedButCompetingUnchangedGraphsAreRejected() throws {
        let historical = try RepetitiveCaptureSourcePackageFixture(
            laterActiveSource: true, secondSameScopeGraph: true,
            secondGraphIsHistorical: true)
        defer { historical.removePackages() }
        let reviewed = try RepetitiveCaptureSourceGraphReviewV2.review(
            sourcePackage: historical.validatedPackage())
        XCTAssertEqual(reviewed.graphs.count, 2)
        XCTAssertTrue(reviewed.graphs.allSatisfy { !$0.isUnchangedActiveSource })
        XCTAssertEqual(Set(reviewed.graphs.map { $0.chain.sourceCheckpoint.scope }).count, 1)

        let active = try RepetitiveCaptureSourcePackageFixture(secondSameScopeGraph: true)
        defer { active.removePackages() }
        let package = try active.validatedPackage()
        XCTAssertThrowsError(
            try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: package))
    }

    func testBranchOrphanAndCheckpointAfterPendingEffectAreRejected() throws {
        let fixtures = [
            try RepetitiveCaptureSourcePackageFixture(addBranch: true),
            try RepetitiveCaptureSourcePackageFixture(addOrphan: true),
            try RepetitiveCaptureSourcePackageFixture(addAfterPending: true)
        ]
        defer { fixtures.forEach { $0.removePackages() } }

        for fixture in fixtures {
            let package = try fixture.validatedPackage()
            XCTAssertThrowsError(
                try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: package))
        }
    }

    func testCanonicalEnvelopeAndTypedReceiptSubstitutionAreRejected() throws {
        for key in ["envelopeData", "receiptData"] {
            let fixture = try RepetitiveCaptureSourcePackageFixture()
            defer { fixture.removePackages() }
            XCTAssertThrowsError(try {
                let package = try fixture.validatedPackage { object in
                    var history = try XCTUnwrap(object["mutationHistory"] as? [String: Any])
                    var receipts = try XCTUnwrap(history["receipts"] as? [[String: Any]])
                    let first = receipts[0][key]
                    receipts[0][key] = receipts[1][key]
                    receipts[1][key] = first
                    history["receipts"] = receipts
                    object["mutationHistory"] = history
                }
                _ = try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: package)
            }(), key)
        }
    }

    func testRequiredEnvelopeQuarantineIsRejectedWhileUnrelatedAndForeignAreAllowed() throws {
        let requiredFixture = try RepetitiveCaptureSourcePackageFixture()
        defer { requiredFixture.removePackages() }
        let requiredEnvelope = try MutationEnvelopeV1.decodeCanonical(
            from: requiredFixture.history.receipts[0].envelopeData)
        let requiredPackage = try package(
            requiredFixture, quarantining: requiredEnvelope, domain: .mutationEnvelope)
        XCTAssertThrowsError(try RepetitiveCaptureSourceGraphReviewV2.review(
            sourcePackage: requiredPackage))

        let unrelatedFixture = try RepetitiveCaptureSourcePackageFixture(
            includeUnrelatedHistory: true)
        defer { unrelatedFixture.removePackages() }
        let unrelatedEnvelopes: [MutationEnvelopeV1] = try unrelatedFixture.history.receipts.compactMap {
            record -> MutationEnvelopeV1? in
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
            guard case let .applyFieldDraft(mutation) = envelope.command,
                  case let .createCheckpoint(checkpoint) = mutation.postImage,
                  checkpoint.purpose == .inspectionReview else { return nil }
            return envelope
        }
        let unrelatedEnvelope = try XCTUnwrap(unrelatedEnvelopes.first)
        let unrelatedReviewed = try RepetitiveCaptureSourceGraphReviewV2.review(
            sourcePackage: package(unrelatedFixture, quarantining: unrelatedEnvelope,
                                   domain: .mutationEnvelope))
        XCTAssertEqual(unrelatedReviewed.graphs.count, 1)
        XCTAssertFalse(unrelatedReviewed.requiredHistory.contains {
            $0.envelope.mutationID == unrelatedEnvelope.mutationID
        })

        let foreignFixture = try RepetitiveCaptureSourcePackageFixture(includeForeignOriginal: true)
        defer { foreignFixture.removePackages() }
        let foreignEnvelope = try XCTUnwrap(try foreignFixture.history.receipts.compactMap {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData)
            return envelope.workspaceID == foreignFixture.workspaceID ? nil : envelope
        }.first)
        let foreignReviewed = try RepetitiveCaptureSourceGraphReviewV2.review(
            sourcePackage: package(foreignFixture, quarantining: foreignEnvelope,
                                   domain: .mutationEnvelope))
        XCTAssertEqual(foreignReviewed.graphs.count, 1)
        XCTAssertTrue(foreignReviewed.requiredHistory.allSatisfy {
            $0.envelope.workspaceID == foreignFixture.workspaceID
        })
    }

    func testRequiredSemanticReplayQuarantineIsRejectedAfterValidReversalAuthentication() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture(semanticRequiredPair: true)
        defer { fixture.removePackages() }
        let control = try RepetitiveCaptureSourceGraphReviewV2.review(
            sourcePackage: fixture.validatedPackage())
        XCTAssertEqual(control.graphs.count, 1)

        let semanticEnvelope = try XCTUnwrap(try fixture.history.receipts.compactMap {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData)
            return envelope.semanticReversalReplayIdentitySHA256 == nil ? nil : envelope
        }.first)
        let quarantined = try package(
            fixture, quarantining: semanticEnvelope,
            domain: .semanticReversalReplayIdentity)
        XCTAssertThrowsError(try RepetitiveCaptureSourceGraphReviewV2.review(
            sourcePackage: quarantined))

        let unrelatedFixture = try RepetitiveCaptureSourcePackageFixture(
            includeUnrelatedHistory: true)
        defer { unrelatedFixture.removePackages() }
        let unrelatedSemanticEnvelopes: [MutationEnvelopeV1] =
            try unrelatedFixture.history.receipts.compactMap { record -> MutationEnvelopeV1? in
                let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
                guard envelope.semanticReversalReplayIdentitySHA256 != nil else { return nil }
                return envelope
            }
        let unrelatedSemanticEnvelope = try XCTUnwrap(unrelatedSemanticEnvelopes.first)
        let unrelatedReviewed = try RepetitiveCaptureSourceGraphReviewV2.review(
            sourcePackage: package(
                unrelatedFixture, quarantining: unrelatedSemanticEnvelope,
                domain: .semanticReversalReplayIdentity))
        XCTAssertEqual(unrelatedReviewed.graphs.count, 1)
        XCTAssertFalse(unrelatedReviewed.requiredHistory.contains {
            $0.envelope.mutationID == unrelatedSemanticEnvelope.mutationID
        })

        let foreignFixture = try RepetitiveCaptureSourcePackageFixture(
            includeForeignOriginal: true)
        defer { foreignFixture.removePackages() }
        let foreignSemanticEnvelopes: [MutationEnvelopeV1] =
            try foreignFixture.history.receipts.compactMap { record -> MutationEnvelopeV1? in
                let envelope = try MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
                guard envelope.workspaceID != foreignFixture.workspaceID,
                      envelope.semanticReversalReplayIdentitySHA256 != nil else { return nil }
                return envelope
            }
        let foreignSemanticEnvelope = try XCTUnwrap(foreignSemanticEnvelopes.first)
        let foreignReviewed = try RepetitiveCaptureSourceGraphReviewV2.review(
            sourcePackage: package(
                foreignFixture, quarantining: foreignSemanticEnvelope,
                domain: .semanticReversalReplayIdentity))
        XCTAssertEqual(foreignReviewed.graphs.count, 1)
        XCTAssertTrue(foreignReviewed.requiredHistory.allSatisfy {
            $0.envelope.workspaceID == foreignFixture.workspaceID
        })
    }

    func testMaximumCaptureGraphAuthenticatesTwoStepsForAllTwoHundredItems() throws {
        let started = ProcessInfo.processInfo.systemUptime
        let trace: (String) -> Void = { phase in
            let elapsed = Int((ProcessInfo.processInfo.systemUptime - started) * 1_000)
            print("C36_SOURCE_GRAPH_PHASE kind=maximumGraph phase=\(phase) elapsedMillis=\(elapsed)")
        }
        let fixture = try RepetitiveCaptureSourcePackageFixture(
            boundaryItemCount: ScanToWorkLimitsV1.maximumSelection, phaseTrace: trace)
        defer { fixture.removePackages() }

        let package = try fixture.validatedPackage()
        trace("graph-review-start")
        let reviewed = try RepetitiveCaptureSourceGraphReviewV2.review(
            sourcePackage: package)
        trace("graph-review-complete")

        let graph = try XCTUnwrap(reviewed.graphs.first)
        XCTAssertEqual(reviewed.graphs.count, 1)
        XCTAssertEqual(graph.chain.launch.round.items.count, 200)
        XCTAssertEqual(graph.checkpoints.count, 401)
        XCTAssertEqual(graph.chain.nodes.count, 400)
        XCTAssertEqual(graph.chain.currentRound.revision, 202)
        XCTAssertEqual(graph.packageCurrentRound, graph.chain.currentRound)
        XCTAssertTrue(graph.isUnchangedActiveSource)
        XCTAssertFalse(try XCTUnwrap(graph.chain.nodes.last).isPendingRoundEffect)
        XCTAssertEqual(reviewed.requiredHistory.count, 603)
    }

    func testRehashedPackageCannotOmitAnyCurrentProgressOrEntireSourceGraph() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture()
        defer { fixture.removePackages() }

        for (name, removeCount) in [("one-progress", 1),
                                    ("whole-source", fixture.checkpoints.count)] {
            let package = try fixture.validatedPackage { object in
                var rows = try XCTUnwrap(object["fieldDrafts"] as? [[String: Any]])
                rows.removeLast(removeCount)
                object["fieldDrafts"] = rows
            }
            XCTAssertThrowsError(
                try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: package), name)
        }


        let extra = try RepetitiveCaptureSourcePackageFixture(extraCurrentV2Row: true)
        defer { extra.removePackages() }
        let extraPackage = try extra.validatedPackage()
        XCTAssertThrowsError(
            try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: extraPackage))
    }

    func testRehashedPackageCannotOmitAuthenticatedRoundTail() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture()
        defer { fixture.removePackages() }

        let control = try RepetitiveCaptureSourceGraphReviewV2.review(
            sourcePackage: fixture.validatedPackage())
        XCTAssertEqual(control.graphs.first?.packageCurrentRound, fixture.rounds.last)

        let package = try fixture.validatedPackage { object in
            var rows = try XCTUnwrap(object["roundSessions"] as? [[String: Any]])
            rows.removeAll { ($0["revision"] as? NSNumber)?.uint64Value == 3 }
            object["roundSessions"] = rows
        }
        XCTAssertThrowsError(
            try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: package))

        let addedFixture = try RepetitiveCaptureSourcePackageFixture()
        defer { addedFixture.removePackages() }
        let prior = try XCTUnwrap(addedFixture.rounds.last)
        let added = try RoundSessionV1(
            workspaceID: prior.workspaceID, sessionID: prior.sessionID,
            predecessor: prior, revision: prior.revision + 1,
            mutationID: .init(rawValue: RepetitiveCaptureSourcePackageFixture.id(990)),
            state: .paused, transition: .pause, items: prior.items,
            recordedBy: prior.recordedBy,
            recordedAt: prior.recordedAt.addingTimeInterval(1))
        let addedPackage = try addedFixture.validatedPackage { object in
            var rows = try XCTUnwrap(object["roundSessions"] as? [[String: Any]])
            rows.append(try addedFixture.roundJSONObject(added))
            object["roundSessions"] = rows
        }
        XCTAssertThrowsError(
            try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: addedPackage))

        let duplicateFixture = try RepetitiveCaptureSourcePackageFixture()
        defer { duplicateFixture.removePackages() }
        XCTAssertThrowsError(try {
            let duplicatePackage = try duplicateFixture.validatedPackage { object in
                var rows = try XCTUnwrap(object["roundSessions"] as? [[String: Any]])
                rows.append(try XCTUnwrap(rows.first))
                object["roundSessions"] = rows
            }
            _ = try RepetitiveCaptureSourceGraphReviewV2.review(
                sourcePackage: duplicatePackage)
        }())

        let prelaunchFixture = try RepetitiveCaptureSourcePackageFixture()
        defer { prelaunchFixture.removePackages() }
        let originalDraft = prelaunchFixture.rounds[0]
        let changedDraft = try RoundSessionV1(
            workspaceID: originalDraft.workspaceID, sessionID: originalDraft.sessionID,
            revision: originalDraft.revision,
            mutationID: .init(rawValue: RepetitiveCaptureSourcePackageFixture.id(991)),
            state: .draft, transition: .create, items: originalDraft.items,
            recordedBy: originalDraft.recordedBy, recordedAt: originalDraft.recordedAt)
        XCTAssertThrowsError(try {
            let changedDraftPackage = try prelaunchFixture.validatedPackage { object in
                var rows = try XCTUnwrap(object["roundSessions"] as? [[String: Any]])
                let index = try XCTUnwrap(rows.firstIndex {
                    ($0["revision"] as? NSNumber)?.uint64Value == originalDraft.revision
                })
                rows[index] = try prelaunchFixture.roundJSONObject(changedDraft)
                object["roundSessions"] = rows
            }
            _ = try RepetitiveCaptureSourceGraphReviewV2.review(
                sourcePackage: changedDraftPackage)
        }())

        let receiptRecord = try XCTUnwrap(prelaunchFixture.history.receipts.first { record in
            let envelope = try? MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
            return envelope?.mutationID == originalDraft.mutationID
        })
        let draftEnvelope = try MutationEnvelopeV1.decodeCanonical(
            from: receiptRecord.envelopeData)
        let originalReceipt = try MutationReceiptV1.decodeCanonical(
            from: receiptRecord.receiptData)
        let changedMutation = try RoundSessionMutationV1(
            workspaceID: changedDraft.workspaceID, expectedRevision: 0,
            mutationID: changedDraft.mutationID, session: changedDraft)
        let changedPostimageReceipt = try MutationReceiptV1(
            identity: originalReceipt.identity, envelope: draftEnvelope,
            resultingRevision: originalReceipt.resultingRevision,
            postImages: [try changedMutation.mutationPostImage],
            committedAt: originalReceipt.committedAt)
        let changedPostimagePackage = try prelaunchFixture.validatedPackage { object in
            var history = try XCTUnwrap(object["mutationHistory"] as? [String: Any])
            var receipts = try XCTUnwrap(history["receipts"] as? [[String: Any]])
            let index = try XCTUnwrap(receipts.firstIndex { row in
                guard let encoded = row["envelopeData"] as? String,
                      let data = Data(base64Encoded: encoded),
                      let envelope = try? MutationEnvelopeV1.decodeCanonical(from: data)
                else { return false }
                return envelope.mutationID == originalDraft.mutationID
            })
            receipts[index]["receiptData"] = try changedPostimageReceipt.canonicalData()
                .base64EncodedString()
            history["receipts"] = receipts
            object["mutationHistory"] = history
        }
        XCTAssertThrowsError(try RepetitiveCaptureSourceGraphReviewV2.review(
            sourcePackage: changedPostimagePackage))

        let disposedFixture = try RepetitiveCaptureSourcePackageFixture(
            discardSource: true, laterRoundAfterDisposition: true)
        defer { disposedFixture.removePackages() }
        let frontier = disposedFixture.rounds[2]
        let changedTail = try RoundSessionV1(
            workspaceID: frontier.workspaceID, sessionID: frontier.sessionID,
            predecessor: frontier, revision: 4,
            mutationID: .init(rawValue: RepetitiveCaptureSourcePackageFixture.id(992)),
            state: .paused, transition: .pause, items: frontier.items,
            recordedBy: frontier.recordedBy,
            recordedAt: frontier.recordedAt.addingTimeInterval(18))
        let changedTailPackage = try disposedFixture.validatedPackage { object in
            var rows = try XCTUnwrap(object["roundSessions"] as? [[String: Any]])
            let index = try XCTUnwrap(rows.firstIndex {
                ($0["revision"] as? NSNumber)?.uint64Value == 4
            })
            rows[index] = try disposedFixture.roundJSONObject(changedTail)
            object["roundSessions"] = rows
        }
        XCTAssertThrowsError(try RepetitiveCaptureSourceGraphReviewV2.review(
            sourcePackage: changedTailPackage))

        let originalTail = disposedFixture.rounds[3]
        let tailRecord = try XCTUnwrap(disposedFixture.history.receipts.first { record in
            let envelope = try? MutationEnvelopeV1.decodeCanonical(from: record.envelopeData)
            return envelope?.mutationID == originalTail.mutationID
        })
        let tailEnvelope = try MutationEnvelopeV1.decodeCanonical(from: tailRecord.envelopeData)
        let tailReceipt = try MutationReceiptV1.decodeCanonical(from: tailRecord.receiptData)
        let changedTailMutation = try RoundSessionMutationV1(
            workspaceID: changedTail.workspaceID, expectedRevision: 3,
            mutationID: changedTail.mutationID, session: changedTail)
        let changedTailPostimageReceipt = try MutationReceiptV1(
            identity: tailReceipt.identity, envelope: tailEnvelope,
            resultingRevision: tailReceipt.resultingRevision,
            postImages: [try changedTailMutation.mutationPostImage],
            committedAt: tailReceipt.committedAt)
        let changedTailPostimagePackage = try disposedFixture.validatedPackage { object in
            var history = try XCTUnwrap(object["mutationHistory"] as? [String: Any])
            var receipts = try XCTUnwrap(history["receipts"] as? [[String: Any]])
            let index = try XCTUnwrap(receipts.firstIndex { row in
                guard let encoded = row["envelopeData"] as? String,
                      let data = Data(base64Encoded: encoded),
                      let envelope = try? MutationEnvelopeV1.decodeCanonical(from: data)
                else { return false }
                return envelope.mutationID == originalTail.mutationID
            })
            receipts[index]["receiptData"] = try changedTailPostimageReceipt.canonicalData()
                .base64EncodedString()
            history["receipts"] = receipts
            object["mutationHistory"] = history
        }
        XCTAssertThrowsError(try RepetitiveCaptureSourceGraphReviewV2.review(
            sourcePackage: changedTailPostimagePackage))
    }

    func testRehashedPackageCannotDropCheckpointHistoryTailOrAlterCurrentCanonicalRow() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture()
        defer { fixture.removePackages() }

        XCTAssertThrowsError(try {
            let missingTail = try fixture.validatedPackage { object in
                var snapshot = try XCTUnwrap(object["mutationHistory"] as? [String: Any])
                var receipts = try XCTUnwrap(snapshot["receipts"] as? [[String: Any]])
                receipts.removeLast()
                snapshot["receipts"] = receipts
                snapshot["workspaceRevision"] = receipts.count
                snapshot["lastLocalSequence"] = receipts.count
                object["mutationHistory"] = snapshot
            }
            _ = try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: missingTail)
        }())

        XCTAssertThrowsError(try {
            let altered = try fixture.validatedPackage { object in
                var rows = try XCTUnwrap(object["fieldDrafts"] as? [[String: Any]])
                var row = rows.removeLast()
                var canonical = try XCTUnwrap(JSONSerialization.jsonObject(
                    with: Data(base64Encoded: try XCTUnwrap(row["canonicalData"] as? String))!)
                    as? [String: Any])
                canonical["updatedAt"] = 1_788_134_499_000
                row["canonicalData"] = try JSONSerialization.data(
                    withJSONObject: canonical, options: [.sortedKeys]).base64EncodedString()
                rows.append(row)
                object["fieldDrafts"] = rows
            }
            _ = try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: altered)
        }())
    }
    @MainActor
    func testCompactReferenceAuthenticatesSourceAndAllOriginalCurrentFrontiers() throws {
        for sourceOnly in [true, false] {
            let fixture = try RepetitiveCaptureSourcePackageFixture(sourceOnly: sourceOnly)
            defer { fixture.removePackages() }
            let reviewed = try RepetitiveCaptureSourceGraphReviewV2.review(
                sourcePackage: fixture.validatedPackage())
            let reference = try XCTUnwrap(
                RepetitiveCaptureSourceGraphReviewV2.references(from: reviewed).first)
            try reference.validate(against: reviewed)
            let graph = try XCTUnwrap(reviewed.graphs.first)
            let retained = try RepetitiveCaptureSourceGraphReviewV2.retainedOriginals(
                for: reference, in: fixture.history)
            XCTAssertEqual(retained.graph, graph)
            XCTAssertEqual(retained.reference, reference)
            XCTAssertEqual(retained.requiredHistory, reviewed.requiredHistory)
            try assertRetainedDestinationReads(fixture: fixture, reference: reference, expected: retained)
            XCTAssertEqual(reference.value.checkpoints.count, sourceOnly ? 1 : 4)
            XCTAssertEqual(reference.value.sourceWorkspaceID, fixture.workspaceID)
            XCTAssertEqual(reference.value.sourceDraftID, graph.chain.sourceCheckpoint.draftID)
            XCTAssertEqual(reference.value.requiredHistory.recordCount, fixture.history.receipts.count)
            XCTAssertEqual(reference.value.roundHistory.recordCount, fixture.rounds.count)
            for (frontier, checkpoint) in zip(reference.value.checkpoints, graph.checkpoints) {
                XCTAssertEqual(frontier.draftID, checkpoint.original.draftID)
                XCTAssertEqual(frontier.original.checkpointSHA256, checkpoint.original.checkpointSHA256)
                XCTAssertEqual(frontier.current.checkpointSHA256, checkpoint.current.checkpointSHA256)
                XCTAssertEqual(frontier.current.state, checkpoint.current.state)
                XCTAssertEqual(frontier.lifecycle.recordCount, checkpoint.lifecycle.count)
                let first = try XCTUnwrap(checkpoint.lifecycle.first)
                let last = try XCTUnwrap(checkpoint.lifecycle.last)
                XCTAssertEqual(frontier.original.record.receiptIdentity, first.receipt.identity)
                XCTAssertEqual(frontier.original.record.envelopeSHA256,
                               KernelCanonicalHashV1.sha256(first.original.envelopeData))
                XCTAssertEqual(frontier.current.record.receiptSHA256,
                               KernelCanonicalHashV1.sha256(last.original.receiptData))
            }
            let data = try FieldDraftCanonicalCodecV1.encode(reference)
            XCTAssertEqual(try FieldDraftCanonicalCodecV1.decode(
                RepetitiveCaptureSourceGraphReferenceV2.self, from: data), reference)
            let text = try XCTUnwrap(String(data: data, encoding: .utf8))
            XCTAssertFalse(text.contains("\"payloadData\""))
            XCTAssertFalse(text.contains("\"envelopeData\""))
            XCTAssertFalse(text.contains("\"receiptData\""))
            if !sourceOnly {
                XCTAssertTrue(try XCTUnwrap(graph.chain.nodes.last).isPendingRoundEffect)
                XCTAssertEqual(reference.value.historicalRound.record.mutationID,
                               graph.chain.currentRound.mutationID)
            }
        }
    }

    func testCompactReferenceRejectsCanonicalRecomputedSourceAndFrontierSubstitutions() throws {
        let fixture = try RepetitiveCaptureSourcePackageFixture()
        defer { fixture.removePackages() }
        let reviewed = try RepetitiveCaptureSourceGraphReviewV2.review(
            sourcePackage: fixture.validatedPackage())
        let reference = try XCTUnwrap(
            RepetitiveCaptureSourceGraphReviewV2.references(from: reviewed).first)
        let mutations: [(inout [String: Any]) throws -> Void] = [
            { $0["sourcePersistentSchemaVersion"] = 44 },
            { $0["recordsJSONSHA256"] = String(repeating: "f", count: 64) },
            { value in
                var history = try XCTUnwrap(value["roundHistory"] as? [String: Any])
                history["recordsSHA256"] = String(repeating: "f", count: 64)
                value["roundHistory"] = history
            },
            { value in
                var rows = try XCTUnwrap(value["checkpoints"] as? [[String: Any]])
                var current = try XCTUnwrap(rows[0]["current"] as? [String: Any])
                current["checkpointSHA256"] = String(repeating: "f", count: 64)
                rows[0]["current"] = current
                value["checkpoints"] = rows
            },
            { value in
                var rows = try XCTUnwrap(value["checkpoints"] as? [[String: Any]])
                var original = try XCTUnwrap(rows[0]["original"] as? [String: Any])
                var record = try XCTUnwrap(original["record"] as? [String: Any])
                record["receiptSHA256"] = String(repeating: "f", count: 64)
                original["record"] = record
                rows[0]["original"] = original
                value["checkpoints"] = rows
            },
            { value in
                var rows = try XCTUnwrap(value["checkpoints"] as? [[String: Any]])
                let removed = rows.removeLast()
                let lifecycle = try XCTUnwrap(removed["lifecycle"] as? [String: Any])
                let removedCount = try XCTUnwrap(lifecycle["recordCount"] as? Int)
                var history = try XCTUnwrap(value["requiredHistory"] as? [String: Any])
                history["recordCount"] = try XCTUnwrap(history["recordCount"] as? Int) - removedCount
                history["recordsSHA256"] = String(repeating: "f", count: 64)
                value["requiredHistory"] = history
                value["checkpoints"] = rows
            },
            { value in
                var rows = try XCTUnwrap(value["checkpoints"] as? [[String: Any]])
                rows.swapAt(1, 2)
                for index in rows.indices { rows[index]["position"] = index }
                value["checkpoints"] = rows
            },
            { $0["sourcePersistentSchemaVersion"] = PersistentSchemaV4.versionIdentifier.major - 1 },
            { $0["sourcePersistentSchemaVersion"] = PersistentSchemaReleaseRegistryV1.activeVersionIdentifier.major + 1 }
        ]
        for (index, mutation) in mutations.enumerated() {
            // These are canonical, internally rehashed values. Shape validity
            // alone must never authenticate their claimed source completeness.
            let forged = try modifiedReference(reference, mutation: mutation)
            XCTAssertNoThrow(try forged.validate())
            XCTAssertThrowsError(try forged.validate(against: reviewed))
            // A retained-journal reader authenticates original records. Archive
            // metadata additionally requires the original package or the
            // destination receipt that bound it. The recorded schema must also
            // support every selected original command and a known release.
            if index != 1 {
                XCTAssertThrowsError(try RepetitiveCaptureSourceGraphReviewV2.retainedOriginals(
                    for: forged, in: fixture.history))
            }
        }
        let original = try XCTUnwrap(fixture.history.receipts.first)
        let envelope = try MutationEnvelopeV1.decodeCanonical(from: original.envelopeData)
        let quarantine = MutationHistoryQuarantineRecordV1(
            workspaceID: envelope.workspaceID, mutationID: envelope.mutationID.rawValue,
            identityDomain: .mutationEnvelope, acceptedIdentitySHA256: try envelope.canonicalSHA256(),
            conflictingIdentitySHA256: String(repeating: "f", count: 64),
            detectedAt: RepetitiveCaptureSourcePackageFixture.date.addingTimeInterval(1_000))
        for snapshot in [
            retainedSnapshot(fixture.history, receipts: Array(fixture.history.receipts.dropFirst())),
            retainedSnapshot(fixture.history, receipts: fixture.history.receipts + [original]),
            retainedSnapshot(fixture.history, quarantines: fixture.history.quarantines + [quarantine]),
        ] {
            XCTAssertThrowsError(try RepetitiveCaptureSourceGraphReviewV2.retainedOriginals(
                for: reference, in: snapshot))
        }
        XCTAssertThrowsError(try modifiedReference(reference) { value in
            var rows = try XCTUnwrap(value["checkpoints"] as? [[String: Any]])
            rows[1]["draftID"] = rows[0]["draftID"]
            value["checkpoints"] = rows
        })
    }

    func testCompactReferencePreservesDisposedStateAndSeparateRoundFrontiers() throws {
        let fixtures = [
            try RepetitiveCaptureSourcePackageFixture(laterActiveSource: true),
            try RepetitiveCaptureSourcePackageFixture(discardPendingSource: true),
            try RepetitiveCaptureSourcePackageFixture(discardSource: true,
                                                      laterRoundAfterDisposition: true)
        ]
        defer { fixtures.forEach { $0.removePackages() } }
        let states: [FieldDraftStateV1] = [.active, .discardPending, .discarded]
        for (fixture, state) in zip(fixtures, states) {
            let reviewed = try RepetitiveCaptureSourceGraphReviewV2.review(
                sourcePackage: fixture.validatedPackage())
            let graph = try XCTUnwrap(reviewed.graphs.first)
            let reference = try XCTUnwrap(
                RepetitiveCaptureSourceGraphReviewV2.references(from: reviewed).first)
            try reference.validate(against: reviewed)
            let frontier = try XCTUnwrap(reference.value.checkpoints.first)
            XCTAssertEqual(frontier.original.state, .active)
            XCTAssertEqual(frontier.current.state, state)
            XCTAssertEqual(frontier.current.draftRevision, graph.checkpoints.first?.current.draftRevision)
            XCTAssertFalse(reference.value.isUnchangedActiveSource)
            let retained = try RepetitiveCaptureSourceGraphReviewV2.retainedOriginals(
                for: reference, in: fixture.history)
            XCTAssertEqual(retained.graph, graph)
            XCTAssertEqual(retained.reference, reference)
            XCTAssertEqual(reference.value.historicalRound.canonicalSHA256,
                           try RoundSessionCanonicalCodecV1.sha256(graph.chain.currentRound))
            XCTAssertEqual(reference.value.packageCurrentRound.canonicalSHA256,
                           try RoundSessionCanonicalCodecV1.sha256(graph.packageCurrentRound))
            if state == .discarded {
                XCTAssertEqual(reference.value.historicalRound.revision, 3)
                XCTAssertEqual(reference.value.packageCurrentRound.revision, 4)
                XCTAssertEqual(reference.value.roundHistory.recordCount, 4)
                XCTAssertTrue(try XCTUnwrap(graph.chain.nodes.last).isPendingRoundEffect)
            }
        }
    }

    func testCompactReferenceSeparatesGraphsAndIgnoresUnrelatedHistory() throws {
        let fixtures = [
            try RepetitiveCaptureSourcePackageFixture(),
            try RepetitiveCaptureSourcePackageFixture(includeForeignOriginal: true,
                                                      includeUnrelatedHistory: true),
            try RepetitiveCaptureSourcePackageFixture(laterActiveSource: true,
                secondSameScopeGraph: true, secondGraphIsHistorical: true)
        ]
        defer { fixtures.forEach { $0.removePackages() } }
        let reviews = try fixtures.map {
            try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: $0.validatedPackage())
        }
        let allReferences = try reviews.map { try RepetitiveCaptureSourceGraphReviewV2.references(from: $0) }
        let base = try XCTUnwrap(allReferences[0].first)
        let unrelated = try XCTUnwrap(allReferences[1].first)
        XCTAssertEqual(base.value.checkpoints, unrelated.value.checkpoints)
        XCTAssertEqual(base.value.roundHistory, unrelated.value.roundHistory)
        XCTAssertEqual(base.value.requiredHistory, unrelated.value.requiredHistory)
        XCTAssertNotEqual(base.value.recordsJSONSHA256, unrelated.value.recordsJSONSHA256)
        let transported = try RepetitiveCaptureSourceGraphReviewV2.retainedOriginals(
            for: base, in: fixtures[1].history)
        XCTAssertEqual(transported.graph, reviews[0].graphs.first)
        XCTAssertEqual(transported.requiredHistory, reviews[0].requiredHistory)
        XCTAssertLessThan(unrelated.value.requiredHistory.recordCount, fixtures[1].history.receipts.count)
        XCTAssertEqual(allReferences[2].count, 2)
        XCTAssertEqual(Set(allReferences[2].map { $0.value.sourceDraftID }).count, 2)
        for (reference, graph) in zip(allReferences[2], reviews[2].graphs) {
            try reference.validate(against: reviews[2])
            let retained = try RepetitiveCaptureSourceGraphReviewV2.retainedOriginals(
                for: reference, in: fixtures[2].history)
            XCTAssertEqual(retained.graph, graph)
            XCTAssertEqual(reference.value.checkpoints.map(\.draftID), graph.checkpoints.map { $0.original.draftID })
            XCTAssertEqual(reference.value.requiredHistory.recordCount,
                graph.checkpoints.reduce(0) { $0 + $1.lifecycle.count } + fixtures[2].rounds.count)
        }
        XCTAssertEqual(allReferences[2][0].value.roundHistory, allReferences[2][1].value.roundHistory)
        XCTAssertNotEqual(allReferences[2][0].value.requiredHistory, allReferences[2][1].value.requiredHistory)
    }

    func testCompactReferenceMaximumGraphFitsPayloadBound() throws {
        let started = ProcessInfo.processInfo.systemUptime
        let trace: (String) -> Void = { phase in
            let elapsed = Int((ProcessInfo.processInfo.systemUptime - started) * 1_000)
            print("C36_SOURCE_GRAPH_PHASE kind=compactReference phase=\(phase) elapsedMillis=\(elapsed)")
        }
        let fixture = try RepetitiveCaptureSourcePackageFixture(
            boundaryItemCount: ScanToWorkLimitsV1.maximumSelection, phaseTrace: trace)
        defer { fixture.removePackages() }
        let package = try fixture.validatedPackage()
        trace("graph-review-start")
        let reviewed = try RepetitiveCaptureSourceGraphReviewV2.review(
            sourcePackage: package)
        trace("graph-review-complete")
        let reference = try XCTUnwrap(
            RepetitiveCaptureSourceGraphReviewV2.references(from: reviewed).first)
        trace("references-complete")
        try reference.validate(against: reviewed)
        trace("reference-validation-complete")
        let retained = try RepetitiveCaptureSourceGraphReviewV2.retainedOriginals(
            for: reference, in: fixture.history)
        trace("retained-history-validation-complete")
        XCTAssertEqual(retained.graph, reviewed.graphs.first)
        XCTAssertEqual(retained.requiredHistory, reviewed.requiredHistory)
        let data = try FieldDraftCanonicalCodecV1.encode(reference)
        trace("reference-encoding-complete")
        XCTAssertEqual(reference.value.checkpoints.count, 401)
        XCTAssertEqual(reference.value.requiredHistory.recordCount, 603)
        XCTAssertEqual(reference.value.roundHistory.recordCount, 202)
        XCTAssertLessThanOrEqual(data.count, FieldDraftLimitsV1.maximumPayloadBytes)
        // IDs and digests have fixed width. The allowance below exceeds the
        // maximum growth of every integer/state field per frontier, plus all
        // outer scalars, even when each is sized independently at its maximum.
        let maximumScalarGrowth = reference.value.checkpoints.count * 256 + 4_096
        XCTAssertLessThanOrEqual(data.count + maximumScalarGrowth, FieldDraftLimitsV1.maximumPayloadBytes)
        let identity = try destinationReviewIdentity(mode: .fork, source: fixture.workspaceID.rawValue)
        let destination = try RepetitiveCaptureDestinationReviewV1.prepareFirst(from: reviewed,
            sourceDraftID: reference.value.sourceDraftID, identity: identity,
            reviewedAt: RepetitiveCaptureSourcePackageFixture.date)
        trace("destination-review-complete")
        try destination.payload.validateFirstSource(against: reviewed, identity: identity)
        try RepetitiveCaptureDestinationReviewCodecV1.validateInitialCheckpoint(destination.checkpoint,
            creationGenerationID: identity.targetPointer.generationID)
        let pairs = destination.payload.provenance.ultimateToDestinationPairs
        XCTAssertEqual(pairs.filter { $0.kind == .checkpoint }.count, 401)
        XCTAssertEqual(pairs.filter { $0.kind == .roundItem }.count, 200)
        XCTAssertLessThanOrEqual(pairs.count, 1_203)
        // Reserve the missing fixed-width relation slots too: this fixture need
        // not have 200 distinct sites or a completion on every selected item.
        let maximumRelationGrowth = (1_203 - pairs.count) * 256
        for pair in pairs {
            XCTAssertLessThanOrEqual(try FieldDraftCanonicalCodecV1.encode(pair).count + 1, 256)
        }
        // A future immediate predecessor is flat: at most another complete
        // relation plus fixed receipt/digest scalars, never an ancestor payload.
        let maximumPredecessorGrowth = 1_203 * 256 + 4_096
        XCTAssertLessThanOrEqual(destination.checkpoint.payloadData.count + maximumScalarGrowth
            + maximumRelationGrowth + maximumPredecessorGrowth, FieldDraftLimitsV1.maximumPayloadBytes)
        print("C36_SOURCE_REFERENCE_METRICS kind=maximum frontiers=401 history=603 bytes=\(data.count) scalarUpperBound=\(data.count + maximumScalarGrowth)")
    }

    func testCompactReferenceLongLifecycleKeepsBoundedPayloadAndCompleteHistory() throws {
        let fixtures = [
            try RepetitiveCaptureSourcePackageFixture(laterActiveSource: true),
            try RepetitiveCaptureSourcePackageFixture(laterActiveSource: true,
                                                      extraActiveSourceRevisions: 512)
        ]
        defer { fixtures.forEach { $0.removePackages() } }
        let reviews = try fixtures.map {
            try RepetitiveCaptureSourceGraphReviewV2.review(sourcePackage: $0.validatedPackage())
        }
        let references = try reviews.map {
            try XCTUnwrap(RepetitiveCaptureSourceGraphReviewV2.references(from: $0).first)
        }
        let short = references[0], long = references[1]
        try short.validate(against: reviews[0])
        try long.validate(against: reviews[1])
        let originalPrefix = try RepetitiveCaptureSourceGraphReviewV2.retainedOriginals(
            for: short, in: fixtures[1].history)
        XCTAssertEqual(originalPrefix.graph, reviews[0].graphs.first)
        XCTAssertEqual(originalPrefix.requiredHistory, reviews[0].requiredHistory)
        let completeLong = try RepetitiveCaptureSourceGraphReviewV2.retainedOriginals(
            for: long, in: fixtures[1].history)
        XCTAssertEqual(completeLong.graph, reviews[1].graphs.first)
        XCTAssertEqual(completeLong.requiredHistory, reviews[1].requiredHistory)
        XCTAssertThrowsError(try RepetitiveCaptureSourceGraphReviewV2.retainedOriginals(
            for: long, in: fixtures[0].history))
        XCTAssertEqual(short.value.checkpoints.count, long.value.checkpoints.count)
        XCTAssertEqual(long.value.checkpoints.first?.lifecycle.recordCount, 514)
        XCTAssertEqual(long.value.checkpoints.first?.current.draftRevision, 514)
        XCTAssertEqual(long.value.requiredHistory.recordCount, short.value.requiredHistory.recordCount + 512)
        XCTAssertEqual(long.value.requiredHistory.recordCount, fixtures[1].history.receipts.count)
        XCTAssertNotEqual(long.value.checkpoints.first?.lifecycle.recordsSHA256,
                          short.value.checkpoints.first?.lifecycle.recordsSHA256)
        XCTAssertNotEqual(long.value.requiredHistory.recordsSHA256, short.value.requiredHistory.recordsSHA256)
        let shortBytes = try FieldDraftCanonicalCodecV1.encode(short).count
        let longBytes = try FieldDraftCanonicalCodecV1.encode(long).count
        XCTAssertLessThan(abs(longBytes - shortBytes), 128)
        XCTAssertThrowsError(try long.validate(against: reviews[0]))
        XCTAssertThrowsError(try short.validate(against: reviews[1]))
        print("C36_SOURCE_REFERENCE_METRICS kind=longLifecycle history=\(long.value.requiredHistory.recordCount) bytes=\(longBytes) shortBytes=\(shortBytes)")
    }
}

private extension V23RepetitiveCaptureSourceGraphReviewTests {
    func retainedSnapshot(_ original: MutationHistorySnapshotV1,
                          receipts: [MutationHistoryReceiptRecordV1]? = nil,
                          quarantines: [MutationHistoryQuarantineRecordV1]? = nil)
        -> MutationHistorySnapshotV1 {
        .init(workspaceRevision: original.workspaceRevision, lastLocalSequence: original.lastLocalSequence,
              receipts: receipts ?? original.receipts, quarantines: quarantines ?? original.quarantines,
              entityRevisions: original.entityRevisions)
    }

    @MainActor
    func assertRetainedDestinationReads(fixture: RepetitiveCaptureSourcePackageFixture,
                                        reference: RepetitiveCaptureSourceGraphReferenceV2,
                                        expected: RepetitiveCaptureRetainedOriginalsV2) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("c36-retained-reader-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try RetainedSourceHistoryTargetV2(root: root, records: fixture.history.receipts)
        defer { try? target.close() }
        XCTAssertNotEqual(target.session.workspaceID, reference.value.sourceWorkspaceID)
        let before = try target.rawState()
        // A valid live destination may retain original foreign receipts with
        // no current source rows or entity projection. Such history is not a
        // complete import snapshot and cannot use its separate admission path.
        XCTAssertNoThrow(try target.journal.validateAll())
        let foreignHistory = try target.journal.exportSnapshot()
        XCTAssertTrue(foreignHistory.entityRevisions.isEmpty)
        XCTAssertThrowsError(try MutationJournalStoreV1.validateImportedSnapshot(foreignHistory))
        XCTAssertEqual(try target.journal.repetitiveCaptureRetainedOriginals(for: reference), expected)
        XCTAssertEqual(try target.writer.repetitiveCaptureRetainedOriginals(for: reference), expected)
        XCTAssertEqual(try target.rawState(), before)
        XCTAssertFalse(target.context.hasChanges)
        XCTAssertEqual(try target.context.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()), 0)
        XCTAssertEqual(try target.context.fetchCount(FetchDescriptor<RoundSessionRevisionRowV1>()), 0)
        XCTAssertEqual(try target.context.fetchCount(FetchDescriptor<WorkflowRecord>()), 0)

        let original = try XCTUnwrap(expected.requiredHistory.first)
        let row = try XCTUnwrap(target.context.fetch(FetchDescriptor<MutationReceiptRow>()).first {
            $0.workspaceMutationKey == MutationWorkspaceKeyV1.value(
                workspaceID: original.envelope.workspaceID, mutationID: original.envelope.mutationID)
        })
        let digest = row.receiptSHA256
        row.receiptSHA256 = String(repeating: "f", count: 64)
        XCTAssertTrue(target.context.hasChanges)
        let dirty = try target.rawState()
        XCTAssertThrowsError(try target.journal.repetitiveCaptureRetainedOriginals(for: reference))
        XCTAssertThrowsError(try target.writer.repetitiveCaptureRetainedOriginals(for: reference))
        XCTAssertEqual(try target.rawState(), dirty)
        target.context.rollback()
        XCTAssertEqual(try target.rawState(), before)

        row.receiptSHA256 = String(repeating: "f", count: 64)
        try target.context.save()
        let corrupt = try target.rawState()
        XCTAssertThrowsError(try target.journal.repetitiveCaptureRetainedOriginals(for: reference))
        XCTAssertThrowsError(try target.writer.repetitiveCaptureRetainedOriginals(for: reference))
        XCTAssertEqual(try target.rawState(), corrupt)
        row.receiptSHA256 = digest
        try target.context.save()
        XCTAssertEqual(try target.rawState(), before)

        let quarantine = MutationQuarantineRow(
            workspaceID: original.envelope.workspaceID, mutationID: original.envelope.mutationID,
            identityDomain: .mutationEnvelope, acceptedIdentitySHA256: original.receipt.envelopeSHA256,
            conflictingIdentitySHA256: String(repeating: "b", count: 64),
            detectedAt: RepetitiveCaptureSourcePackageFixture.date.addingTimeInterval(1_000))
        target.context.insert(quarantine)
        try target.context.save()
        let quarantined = try target.rawState()
        XCTAssertThrowsError(try target.journal.repetitiveCaptureRetainedOriginals(for: reference))
        XCTAssertThrowsError(try target.writer.repetitiveCaptureRetainedOriginals(for: reference))
        XCTAssertEqual(try target.rawState(), quarantined)
        target.context.delete(quarantine)
        try target.context.save()

        target.context.delete(row)
        try target.context.save()
        let missing = try target.rawState()
        XCTAssertThrowsError(try target.journal.repetitiveCaptureRetainedOriginals(for: reference))
        XCTAssertThrowsError(try target.writer.repetitiveCaptureRetainedOriginals(for: reference))
        XCTAssertEqual(try target.rawState(), missing)
        try target.insert(original.original)
        try target.context.save()
        XCTAssertEqual(try target.rawState(), before)
        XCTAssertEqual(try target.writer.repetitiveCaptureRetainedOriginals(for: reference), expected)

        try target.closeJournalLease()
        let retired = try target.rawState()
        XCTAssertThrowsError(try target.journal.repetitiveCaptureRetainedOriginals(for: reference))
        XCTAssertEqual(try target.rawState(), retired)
        // The independent coordinator writer lease is still live.
        XCTAssertEqual(try target.writer.repetitiveCaptureRetainedOriginals(for: reference), expected)
        target.writer.invalidate()
        XCTAssertThrowsError(try target.writer.repetitiveCaptureRetainedOriginals(for: reference))
        XCTAssertEqual(try target.rawState(), retired)
    }

    func modifiedReference(_ reference: RepetitiveCaptureSourceGraphReferenceV2,
                           mutation: (inout [String: Any]) throws -> Void) throws
        -> RepetitiveCaptureSourceGraphReferenceV2 {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: FieldDraftCanonicalCodecV1.encode(reference)) as? [String: Any])
        var value = try XCTUnwrap(object["value"] as? [String: Any])
        try mutation(&value)
        object["value"] = value
        object["referenceSHA256"] = KernelCanonicalHashV1.sha256(try JSONSerialization.data(
            withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]))
        let data = try JSONSerialization.data(withJSONObject: object,
                                              options: [.sortedKeys, .withoutEscapingSlashes])
        return try FieldDraftCanonicalCodecV1.decode(RepetitiveCaptureSourceGraphReferenceV2.self,
                                                    from: data)
    }

    func package(
        _ fixture: RepetitiveCaptureSourcePackageFixture,
        quarantining envelope: MutationEnvelopeV1,
        domain: MutationQuarantineIdentityDomainV1
    ) throws -> ValidatedRepetitiveCaptureSourcePackageV2 {
        let accepted: String
        switch domain {
        case .mutationEnvelope:
            accepted = try envelope.canonicalSHA256()
        case .semanticReversalReplayIdentity:
            accepted = try XCTUnwrap(envelope.semanticReversalReplayIdentitySHA256)
        }
        let quarantine = MutationHistoryQuarantineRecordV1(
            workspaceID: envelope.workspaceID, mutationID: envelope.mutationID.rawValue,
            identityDomain: domain, acceptedIdentitySHA256: accepted,
            conflictingIdentitySHA256: String(repeating: "f", count: 64),
            detectedAt: RepetitiveCaptureSourcePackageFixture.date.addingTimeInterval(1_000))
        // Quarantines use the backup wire dialect, including RFC3339 dates;
        // mutation-envelope canonical JSON uses a different date representation.
        let encoded = try CanonicalJSONV1.encode(.object([
            "acceptedIdentitySHA256": .string(quarantine.acceptedIdentitySHA256),
            "conflictingIdentitySHA256": .string(quarantine.conflictingIdentitySHA256),
            "detectedAt": CanonicalJSONV1.date(quarantine.detectedAt),
            "identityDomain": .string(quarantine.identityDomain.rawValue),
            "mutationID": CanonicalJSONV1.uuid(quarantine.mutationID),
            "workspaceID": .object([
                "rawValue": CanonicalJSONV1.uuid(quarantine.workspaceID.rawValue),
            ]),
        ]))
        let quarantineObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        return try fixture.validatedPackage { object in
            var history = try XCTUnwrap(object["mutationHistory"] as? [String: Any])
            var values = try XCTUnwrap(history["quarantines"] as? [[String: Any]])
            values.append(quarantineObject)
            history["quarantines"] = values
            object["mutationHistory"] = history
            let bytes = try RepetitiveCaptureSourcePackageFixture.canonicalJSONData(object)
            let decoded = try BackupCanonicalDecoderV1().decodeRecords(bytes)
            let decodedHistory = try XCTUnwrap(decoded.mutationHistory)
            XCTAssertEqual(decodedHistory.quarantines.last, quarantine)
            let canonical = try BackupCanonicalEncoderV1().encodeRecords(decoded).data
            XCTAssertEqual(try BackupCanonicalDecoderV1().decodeRecords(canonical), decoded)
        }
    }
}


@MainActor
final class RetainedSourceHistoryTargetV2 {
    struct RawState: Equatable {
        let receipts: [[String]]
        let quarantines: [[String]]
        let states: [[String]]
        let revisions: [[String]]
        let canonicalCounts: [Int]
        let hasChanges: Bool
    }

    let factory: StoreGenerationFactory
    let session: StoreGenerationSession
    let coordinator: StoreSessionCoordinator
    let journal: MutationJournalStoreV1
    private let journalLease: GenerationLeaseHandleV1
    private var journalLeaseClosed = false
    private var coordinatorClosed = false
    var context: ModelContext { session.modelContext }
    var writer: WorkspaceWriterV1 { coordinator.workspaceWriter }

    init(root: URL, records: [MutationHistoryReceiptRecordV1]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let identity = try WorkspaceReplicaIdentityV1(
            workspaceID: WorkspaceID(rawValue: UUID()), replicaID: ReplicaID(rawValue: UUID()))
        let localFactory = StoreGenerationFactory(applicationSupportURL: root,
                                                 pointerEnrichmentIdentity: identity)
        factory = localFactory
        let localSession = try localFactory.openOrBootstrapCurrent()
        session = localSession
        coordinator = try StoreSessionCoordinator(validatingSession: localSession,
            lifecycleProfileRegistry: WorkspacePackageLifecycleCompatibilityV1.shippingRegistry())
        guard let epoch = localSession.generationEpoch else {
            throw WorkspaceMutationFailureV1.wrongGeneration
        }
        let leases = try localFactory.makeGenerationLeaseRegistry()
        let lease = try leases.acquireHandle(epoch: epoch, role: .writer)
        journalLease = lease
        journal = try MutationJournalStoreV1(modelContext: localSession.modelContext,
            identity: localSession.workspaceIdentity, generationID: localSession.generationID,
            allowStateBootstrap: false,
            staleWriterFence: localFactory.makeWriterFence(expectedGenerationEpoch: epoch,
                writerLeaseToken: lease.token, registry: leases))
        for record in records { try insert(record) }
        try context.save()
    }

    func insert(_ record: MutationHistoryReceiptRecordV1) throws {
        let row = try MutationReceiptRow(
            envelope: MutationEnvelopeV1.decodeCanonical(from: record.envelopeData),
            receipt: MutationReceiptV1.decodeCanonical(from: record.receiptData),
            reversalBasis: record.reversalBasisData.map { try ReversalBasisV1.decodeCanonical(from: $0) },
            semanticReversal: record.semanticReversalData.map { try SemanticReversalReceiptV1.decodeCanonical(from: $0) })
        context.insert(row)
    }

    func rawState() throws -> RawState {
        let receipts: [[String]] = try context.fetch(FetchDescriptor<MutationReceiptRow>())
            .sorted { $0.workspaceMutationKey < $1.workspaceMutationKey }
            .map { row -> [String] in
                [row.mutationID.uuidString, row.workspaceMutationKey, row.receiptIdentity,
                 row.workspaceID.uuidString, row.replicaID.uuidString, String(row.localSequence),
                 row.commandKind, row.envelopeData.base64EncodedString(), row.envelopeSHA256,
                 row.receiptData.base64EncodedString(), row.receiptSHA256,
                 String(describing: row.reversalBasisData?.base64EncodedString()),
                 String(describing: row.reversalBasisSHA256),
                 String(describing: row.semanticReversalData?.base64EncodedString())]
            }
        let quarantines: [[String]] = try context.fetch(FetchDescriptor<MutationQuarantineRow>())
            .sorted { $0.workspaceMutationKey < $1.workspaceMutationKey }
            .map { row -> [String] in
                [row.workspaceID.uuidString, row.mutationID.uuidString, row.workspaceMutationKey,
                 row.identityDomain, row.acceptedIdentitySHA256, row.conflictingIdentitySHA256,
                 String(row.detectedAt.timeIntervalSinceReferenceDate)]
            }
        let states: [[String]] = try context.fetch(FetchDescriptor<WorkspaceMutationStateRow>())
            .sorted { $0.workspaceID.uuidString < $1.workspaceID.uuidString }
            .map { row -> [String] in
                [row.workspaceID.uuidString, row.generationID.uuidString, row.activeReplicaID.uuidString,
                 String(row.workspaceRevision), String(row.lastLocalSequence),
                 String(describing: row.mutableSemanticSHA256)]
            }
        let revisions: [[String]] = try context.fetch(FetchDescriptor<EntityMutationRevisionRow>())
            .sorted { $0.stableIdentity < $1.stableIdentity }
            .map { row -> [String] in
                [row.stableIdentity, row.kind, row.entityID.uuidString, String(row.revision),
                 String(describing: row.externalProjectionSHA256)]
            }
        let counts = try [context.fetchCount(FetchDescriptor<FieldDraftCheckpointRow>()),
                          context.fetchCount(FetchDescriptor<RoundSessionRevisionRowV1>()),
                          context.fetchCount(FetchDescriptor<WorkflowRecord>()),
                          context.fetchCount(FetchDescriptor<Site>()),
                          context.fetchCount(FetchDescriptor<Asset>())]
        return .init(receipts: receipts, quarantines: quarantines, states: states,
                     revisions: revisions, canonicalCounts: counts, hasChanges: context.hasChanges)
    }

    func closeJournalLease() throws {
        guard !journalLeaseClosed else { return }
        try journalLease.close()
        journalLeaseClosed = true
    }

    func close() throws {
        if !coordinatorClosed {
            do {
                try coordinator.invalidateAndReleaseWriter()
                coordinatorClosed = true
            } catch {
                try? closeJournalLease()
                throw error
            }
        }
        try closeJournalLease()
    }
}

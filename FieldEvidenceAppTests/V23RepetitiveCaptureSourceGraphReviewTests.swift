import Foundation
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

        let reviewed = try RepetitiveCaptureSourceGraphReviewV2.review(
            sourcePackage: fixture.validatedPackage())

        XCTAssertEqual(reviewed.graphs.count, 1)
        XCTAssertEqual(reviewed.graphs.first?.checkpoints.count, fixture.checkpoints.count)
        XCTAssertEqual(reviewed.requiredHistory.count, fixture.history.receipts.count / 2)
        XCTAssertTrue(reviewed.requiredHistory.allSatisfy {
            $0.envelope.workspaceID == fixture.workspaceID
        })

        let configurationClone = try RepetitiveCaptureSourcePackageFixture(
            foreignHistoryOnly: true)
        defer { configurationClone.removePackages() }
        let empty = try RepetitiveCaptureSourceGraphReviewV2.review(
            sourcePackage: configurationClone.validatedPackage())
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
        let unrelatedEnvelope = try XCTUnwrap(try unrelatedFixture.history.receipts.compactMap {
            let envelope = try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData)
            guard case let .applyFieldDraft(mutation) = envelope.command,
                  case let .createCheckpoint(checkpoint) = mutation.postImage,
                  checkpoint.purpose == .inspectionReview else { return nil }
            return envelope
        }.first)
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
        let unrelatedSemanticEnvelope = try XCTUnwrap(
            try unrelatedFixture.history.receipts.compactMap {
                let envelope = try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData)
                guard envelope.semanticReversalReplayIdentitySHA256 != nil else { return nil }
                return envelope
            }.first)
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
        let foreignSemanticEnvelope = try XCTUnwrap(
            try foreignFixture.history.receipts.compactMap {
                let envelope = try MutationEnvelopeV1.decodeCanonical(from: $0.envelopeData)
                guard envelope.workspaceID != foreignFixture.workspaceID,
                      envelope.semanticReversalReplayIdentitySHA256 != nil else { return nil }
                return envelope
            }.first)
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
        let fixture = try RepetitiveCaptureSourcePackageFixture(
            boundaryItemCount: ScanToWorkLimitsV1.maximumSelection)
        defer { fixture.removePackages() }

        let reviewed = try RepetitiveCaptureSourceGraphReviewV2.review(
            sourcePackage: fixture.validatedPackage())

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
}

private extension V23RepetitiveCaptureSourceGraphReviewTests {
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
        let encoded = try WorkspaceMutationCanonicalV1.data(quarantine)
        let quarantineObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        return try fixture.validatedPackage { object in
            var history = try XCTUnwrap(object["mutationHistory"] as? [String: Any])
            var values = try XCTUnwrap(history["quarantines"] as? [[String: Any]])
            values.append(quarantineObject)
            history["quarantines"] = values
            object["mutationHistory"] = history
        }
    }
}
